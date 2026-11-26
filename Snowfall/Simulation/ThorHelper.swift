import Foundation
import simd

/// Sprite metrics shared by simulation and renderer. Design space: origin bottom-left, he faces LEFT.
enum ThorMetrics {
    static let scale: Float = 1.0
    static let width: Float = 120
    static let height: Float = 150
    /// Gripping hand, in design coordinates.
    static let hand = SIMD2<Float>(22, 100)
    static let hammerSize = SIMD2<Float>(128, 40)
    /// Hammer pivot (the grip) is 60 pt from the hammer sprite's centre; the head centre is 100 pt from the pivot.
    static let pivotToCenter: Float = 60
    static let impactDistance: Float = 100
    static let strikeAngle: Float = 1.35     // hammer nearly vertical, head on the ground
    static let raisedAngle: Float = -1.25    // wound up over his head
    static let raisedAfterBlow: Float = -1.05
    static let restAngle: Float = 0.55
    /// Distance between hammer sites along a surface, and the most sites in one run.
    static let siteSpacing: Float = 300
    static let maxSites = 16
    static let crackRadius: Float = 110, shatterRadius: Float = 190

    /// Sprite-centre x at which the hammer head lands on `impactX`.
    static func standX(forImpactX impactX: Float) -> Float {
        let k = scale
        return impactX + width * k / 2 - hand.x * k + cos(strikeAngle) * impactDistance * k
    }
}

struct ThorSite { var x: Float; var surfaceID: String }
struct ThorBlow: Equatable { var siteIndex: Int; var level: Int; var removed: Float }
struct ThorCrack { var x: Float; var y: Float; var radius: Float; var age: Float; var seed: Float }
struct ThorRing { var x: Float; var y: Float; var maxRadius: Float; var age: Float }

struct ThorRun {
    enum Phase { case flying, working, leaving }
    var phase: Phase = .flying
    var sites: [ThorSite]
    var siteIndex = 0
    var t: Float = 0
    var totalTime: Float = 0
    var from: SIMD2<Float>
    var to: SIMD2<Float>
    var flightDuration: Float = 2.6
    var x: Float
    var y: Float
    var tilt: Float = 0.35
    var hammerAngle: Float = 0.5
    var blowsDone = 0
    var bolt: [SIMD2<Float>] = []
    var boltAge: Float = 1
    var cracks: [ThorCrack] = []
    var rings: [ThorRing] = []
    var flash: Float = 0
    var flashPos = SIMD2<Float>.zero

    var handWorld: SIMD2<Float> {
        let k = ThorMetrics.scale
        return SIMD2(x - ThorMetrics.width * k / 2 + ThorMetrics.hand.x * k, y + ThorMetrics.hand.y * k)
    }
    var impactWorld: SIMD2<Float> {
        handWorld + SIMD2(-cos(hammerAngle), -sin(hammerAngle)) * (ThorMetrics.impactDistance * ThorMetrics.scale)
    }

    var renderState: RenderThor {
        RenderThor(x: x, y: y, tilt: tilt, hammerAngle: hammerAngle,
                   bolt: boltAge < 0.24 ? bolt : [], boltAlpha: max(0, 1 - boltAge / 0.24),
                   rings: rings.map { RenderRing(x: $0.x, y: $0.y, radius: $0.maxRadius * min(1, $0.age / 0.45), alpha: max(0, 1 - $0.age / 0.6)) },
                   cracks: cracks.map { RenderCrack(x: $0.x, y: $0.y, radius: $0.radius, alpha: min(1, max(0, (3 - $0.age) / 1.5)), seed: $0.seed) },
                   flash: flash, flashPos: flashPos)
    }
}

extension PhysicsWorld {
    // MARK: Planning

    /// Plans a route that covers every snowy surface: sites are spaced `siteSpacing` apart along each
    /// surface (blow 2 clears about twice its radius, so neighbouring blows overlap), skipping stretches
    /// that are empty or hidden behind a window in front. Ordered right → left.
    func chooseThorSites() -> [ThorSite] {
        var sites: [(site: ThorSite, snow: Float)] = []
        for st in ordered where st.field.volume > 40 {
            let hidden = occludedSpans(for: st)
            let lo = st.surface.minX + 30, hi = st.surface.maxX - 30
            let n = hi > lo ? max(1, Int(((hi - lo) / ThorMetrics.siteSpacing).rounded(.up))) : 1
            let step = hi > lo ? (hi - lo) / Float(n) : 0
            for k in 0..<n {
                let x = hi > lo ? lo + step * (Float(k) + 0.5) : (st.surface.minX + st.surface.maxX) / 2
                if hidden.contains(where: { x >= $0.0 && x <= $0.1 }) { continue }
                let near = snowNear(st, x: x, radius: ThorMetrics.siteSpacing / 2)
                if near > 25 { sites.append((ThorSite(x: x, surfaceID: st.surface.id), near)) }
            }
        }
        if sites.count > ThorMetrics.maxSites {
            sites = Array(sites.sorted { $0.snow > $1.snow }.prefix(ThorMetrics.maxSites))   // the snowiest spots
        }
        if sites.isEmpty, let st = ordered.max(by: { $0.field.volume < $1.field.volume }), st.field.volume > 1 {
            return [ThorSite(x: (st.surface.minX + st.surface.maxX) / 2, surfaceID: st.surface.id)]
        }
        return sites.map(\.site).sorted { $0.x > $1.x }
    }

    /// Snow volume (pt²) within `radius` of surface x.
    func snowNear(_ st: SurfaceState, x: Float, radius: Float) -> Float {
        let local = x - st.surface.minX
        let lo = st.field.binIndex(atLocalX: local - radius), hi = st.field.binIndex(atLocalX: local + radius)
        guard lo <= hi else { return 0 }
        var v: Float = 0
        for i in lo...hi { v += st.field.height(atBin: i) * st.field.binWidth }
        return v
    }

    private func thorLanding(_ site: ThorSite) -> SIMD2<Float> {
        guard let st = state(forSurface: site.surfaceID) else { return SIMD2(ThorMetrics.standX(forImpactX: site.x), Float(region.minY)) }
        let h = st.field.height(atLocalX: site.x - st.surface.minX)
        return SIMD2(ThorMetrics.standX(forImpactX: site.x), st.surface.topY(atX: site.x) + h)
    }

    func startThor() {
        guard thor == nil, plow == nil, santa == nil, ironMan == nil, tornado == nil, spider == nil, !region.isEmpty else { return }
        let sites = chooseThorSites()
        guard let first = sites.first else { return }
        thorBlowLog.removeAll()
        let from = SIMD2(Float(region.maxX) + 200, Float(region.maxY) - 100)
        let to = thorLanding(first)
        thor = ThorRun(sites: sites, from: from, to: to, x: from.x, y: from.y)
    }

    // MARK: Stepping

    func stepThor(dt: Float) {
        guard var r = thor else { return }
        r.totalTime += dt
        r.boltAge += dt
        r.flash = max(0, r.flash - 5 * dt)
        for i in r.cracks.indices { r.cracks[i].age += dt }
        r.cracks.removeAll { $0.age > 3 }
        for i in r.rings.indices { r.rings[i].age += dt }
        r.rings.removeAll { $0.age > 0.6 }

        switch r.phase {
        case .flying:
            r.t += dt
            let u = min(r.t / r.flightDuration, 1)
            let e = u * u * (3 - 2 * u)
            r.x = r.from.x + (r.to.x - r.from.x) * e
            r.y = r.from.y + (r.to.y - r.from.y) * e + (r.siteIndex == 0 ? 0 : 60 * sin(.pi * u))
            r.tilt = 0.35 * (1 - e)
            r.hammerAngle = 0.4
            if u >= 1 {
                r.phase = .working; r.t = 0; r.blowsDone = 0
                r.x = r.to.x; r.y = r.to.y; r.tilt = 0
            }
        case .working:
            r.t += dt
            r.hammerAngle = Self.hammerAngle(at: r.t)
            if r.blowsDone == 0, r.t >= 0.64 { thorBlow(&r, level: 1) }
            if r.blowsDone == 1, r.t >= 1.40 { thorBlow(&r, level: 2) }
            if r.t >= 2.08 {
                r.siteIndex += 1
                // Skip sites the neighbouring blows have already cleared.
                while r.siteIndex < r.sites.count, let st = state(forSurface: r.sites[r.siteIndex].surfaceID),
                      snowNear(st, x: r.sites[r.siteIndex].x, radius: 120) < 20 { r.siteIndex += 1 }
                if r.siteIndex < r.sites.count {
                    r.phase = .flying; r.t = 0
                    r.from = SIMD2(r.x, r.y)
                    r.to = thorLanding(r.sites[r.siteIndex])
                    r.flightDuration = min(max(0.7 + simd_length(r.to - r.from) / 800, 0.9), 2.2)
                } else {
                    r.phase = .leaving; r.t = 0
                }
            }
        case .leaving:
            r.t += dt
            r.x -= 150 * dt
            r.y += 190 * dt
            r.tilt = 0.4
            r.hammerAngle = 0.3
            if r.t > 3 || r.y > Float(region.maxY) + 220 || r.x < Float(region.minX) - 200 {
                thor = nil
                lastHelperEnd = time
                return
            }
        }
        thor = r
    }

    /// Hammer swing timeline (seconds since arriving at a site): wind-up, blow 1, recover, blow 2, rest.
    static func hammerAngle(at t: Float) -> Float {
        func ease(_ u: Float) -> Float { u * u * (3 - 2 * u) }
        let strike = ThorMetrics.strikeAngle, raised = ThorMetrics.raisedAngle
        if t < 0.5 { return 0.5 + (raised - 0.5) * ease(t / 0.5) }
        if t < 0.64 { let u = (t - 0.5) / 0.14; return raised + (strike - raised) * u * u }
        if t < 1.24 { return strike + (ThorMetrics.raisedAfterBlow - strike) * ease((t - 0.64) / 0.6) }
        if t < 1.40 { let u = (t - 1.24) / 0.16; return ThorMetrics.raisedAfterBlow + (strike - ThorMetrics.raisedAfterBlow) * u * u }
        return strike + (ThorMetrics.restAngle - strike) * ease(min((t - 1.40) / 0.68, 1))
    }

    // MARK: A hammer blow

    /// Blow 1 cracks the ice layer (partial, narrow); blow 2 shatters it (full, wide). Broken ice is thrown
    /// out as shards (their volume leaves the system), and nearby airborne snow is blasted away.
    private func thorBlow(_ r: inout ThorRun, level: Int) {
        r.blowsDone = level
        let site = r.sites[r.siteIndex]
        guard let st = state(forSurface: site.surfaceID) else { return }
        let impactX = site.x
        let local = impactX - st.surface.minX
        let radius: Float = level == 1 ? ThorMetrics.crackRadius : ThorMetrics.shatterRadius
        let surfaceY = st.surface.topY(atX: impactX) + st.field.height(atLocalX: local)

        // Break the ice layer.
        var removed: Float = 0
        let f = st.field
        let lo = f.binIndex(atLocalX: local - radius), hi = f.binIndex(atLocalX: local + radius)
        let bw = f.binWidth
        for i in lo...hi {
            let d = abs((Float(i) + 0.5) * bw - local)
            guard d < radius else { continue }
            let u = d / radius
            let w: Float = level == 1 ? 0.65 * (1 - u * u) : (u < 0.82 ? 1 : (1 - u) / 0.18)   // blow 2 clears out past half the site spacing
            let h = st.field.height(atBin: i)
            if h > 0 { removed += st.field.melt(bin: i, depth: h * w) * bw }
        }
        if removed > 0 { st.dirty = true; totals.lostVolume += removed }
        thorBlowLog.append(ThorBlow(siteIndex: r.siteIndex, level: level, removed: removed))

        // Ice shards.
        let shards = level == 1 ? 26 : 46
        for _ in 0..<shards where pool.count < pool.capacity - 40 {
            let ang = rng.float(0.15...2.99)
            let speed = rng.float(180...520)
            var p = SnowParticle.blank
            p.position = SIMD2(impactX + rng.float(-radius * 0.5...radius * 0.5), surfaceY + 2)
            p.velocity = SIMD2(cos(ang) * speed, sin(ang) * speed * 0.9 + 120)
            p.radius = rng.float(2.2...5.5)
            p.angularVelocity = rng.float(-6...6)
            p.opacity = 0.95
            p.mass = 1.4
            p.state = .displaced
            p.orbitRadius = -1                       // fades away; carries no snow
            pool.spawn(p)
        }

        // Shock blast on airborne snow.
        let blastR = radius * 1.6
        let impact = SIMD2(impactX, surfaceY)
        for i in 0..<pool.count {
            var p = pool[i]
            guard p.state == .falling || p.state == .disturbed, p.orbitRadius >= 0 else { continue }
            let d = p.position - impact
            let dist = simd_length(d)
            guard dist < blastR else { continue }
            let dir: SIMD2<Float> = dist > 1e-3 ? d / dist : SIMD2(0, 1)
            p.velocity += (dir + SIMD2(0, 0.35)) * (520 * (1 - dist / blastR))
            p.state = .disturbed; p.stateTime = 0
            pool[i] = p
        }

        // Visuals: crack pattern, shockwave ring, lightning bolt, flash.
        r.cracks.append(ThorCrack(x: impactX, y: surfaceY, radius: radius * 1.3, age: 0, seed: rng.float(0...6.28)))
        r.rings.append(ThorRing(x: impactX, y: surfaceY, maxRadius: radius * 1.5, age: 0))
        var pts: [SIMD2<Float>] = []
        let topY = Float(region.maxY) + 20
        let startX = impactX + rng.float(-70...70)
        let segs = 9
        for k in 0...segs {
            let u = Float(k) / Float(segs)
            let jitter = (1 - u) * 38
            pts.append(SIMD2(startX + (impactX - startX) * u + (k == segs ? 0 : rng.float(-jitter...jitter)),
                             topY + (surfaceY + 10 - topY) * u))
        }
        r.bolt = pts
        r.boltAge = 0
        r.flash = 1
        r.flashPos = impact
    }
}
