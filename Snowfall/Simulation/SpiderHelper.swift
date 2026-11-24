import Foundation
import simd

/// Sprite metrics shared by simulation and renderer. Design space: origin bottom-left, he faces LEFT.
enum SpiderMetrics {
    static let scale: Float = 1.0
    static let width: Float = 100
    static let height: Float = 140
    /// Hand that holds the web line (design coordinates).
    static let hand = SIMD2<Float>(22, 126)
    /// Distance from the sprite centre down to his feet.
    static let feetDrop: Float = 52
    static let gravity: Float = 900
    static let swingDY: Float = 360

    static func rotate(_ v: SIMD2<Float>, by a: Float) -> SIMD2<Float> {
        SIMD2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a))
    }
}

struct SpiderWebBall { var from: SIMD2<Float>; var target: SIMD2<Float>; var t: Float; var duration: Float; var surfaceID: String; var pos: SIMD2<Float> }
struct SpiderPatch { var x: Float; var y: Float; var radius: Float; var age: Float; var yanked: Bool; var surfaceID: String }
struct SpiderNet { var center: SIMD2<Float>; var radius: Float; var age: Float }
struct SpiderPull { var to: SIMD2<Float>; var age: Float }

struct SpiderRun {
    enum Phase { case swinging, leaving }
    var phase: Phase = .swinging
    var pos: SIMD2<Float>
    var vel: SIMD2<Float>
    var anchor = SIMD2<Float>.zero
    var rope: Float = 400
    var attached = false
    var swingTime: Float = 0
    var totalTime: Float = 0
    var leaveTime: Float = 0
    var rot: Float = 0
    var ballTimer: Float = 0.9
    var netTimer: Float = 1.8
    var balls: [SpiderWebBall] = []
    var patches: [SpiderPatch] = []
    var pulls: [SpiderPull] = []
    var net: SpiderNet?
    var sprayAccumulator: Float = 0

    var handWorld: SIMD2<Float> {
        let k = SpiderMetrics.scale
        let local = (SpiderMetrics.hand - SIMD2(SpiderMetrics.width / 2, SpiderMetrics.height / 2)) * k
        return pos + SpiderMetrics.rotate(local, by: rot)
    }

    var renderState: RenderSpider {
        let netAlpha: Float
        if let n = net { netAlpha = n.age < 0.15 ? n.age / 0.15 : max(0, (0.75 - n.age) / 0.6) } else { netAlpha = 0 }
        return RenderSpider(x: pos.x, y: pos.y, rot: rot, hand: handWorld, anchor: anchor, attached: attached,
                            balls: balls.map { RenderWebBall(pos: $0.pos) },
                            patches: patches.map { RenderWebPatch(x: $0.x, y: $0.y, radius: $0.radius, alpha: $0.age < 1 ? 1 : max(0, 1.6 - $0.age) / 0.6) },
                            pulls: pulls.map { RenderWebPull(to: $0.to, alpha: max(0, 1 - $0.age / 0.55)) },
                            netCenter: net?.center ?? .zero, netRadius: net?.radius ?? 0, netAlpha: netAlpha)
    }
}

extension PhysicsWorld {
    // MARK: Start

    func startSpider() {
        guard spider == nil, plow == nil, santa == nil, ironMan == nil, thor == nil, tornado == nil, !region.isEmpty else { return }
        spiderAnchorLog.removeAll()
        let floorTop = floorState(at: Float(region.maxX) - 1)?.surface.topY ?? Float(region.minY)
        var s = SpiderRun(pos: SIMD2(Float(region.maxX) + 130, floorTop + 260), vel: SIMD2(-480, 60))
        attachNextAnchor(&s)
        spider = s
    }

    /// Highest surface under x whose top is below `y` (a place his feet could reach).
    func spiderGround(at x: Float, below y: Float) -> SurfaceState? {
        var best: SurfaceState?
        for st in ordered where x >= st.surface.minX && x <= st.surface.maxX && st.surface.topY < y {
            if best == nil || st.surface.topY > best!.surface.topY { best = st }
        }
        return best
    }

    /// Shoots a web to an anchor ahead (left) and above, sized so the bottom of the arc skims the snow.
    /// With height H above the skim line and rise `dy`: dx = √(H² + 2·H·dy) gives a rope L = H + dy,
    /// whose lowest point is exactly the skim line.
    func attachNextAnchor(_ s: inout SpiderRun) {
        let dy = SpiderMetrics.swingDY
        var dx: Float = 320
        for _ in 0..<2 {
            let top = spiderGround(at: s.pos.x - dx, below: s.pos.y + 150)?.surface.topY ?? Float(region.minY)
            let skim = top + SpiderMetrics.feetDrop + 6
            let h = max(s.pos.y - skim, 20)
            dx = min(max(sqrt(h * h + 2 * h * dy), 220), 640)
        }
        s.anchor = SIMD2(s.pos.x - dx, s.pos.y + dy)
        s.rope = simd_length(s.anchor - s.pos)
        s.attached = true
        s.swingTime = 0
        spiderAnchorLog.append(s.anchor)
    }

    // MARK: Step

    func stepSpider(dt: Float) {
        guard var s = spider else { return }
        s.totalTime += dt
        s.swingTime += dt
        let oldX = s.pos.x

        switch s.phase {
        case .swinging:
            swingStep(&s, dt: dt)
            if s.pos.x < Float(region.minX) + 180 {
                s.phase = .leaving; s.attached = false; s.leaveTime = 0
                s.vel = SIMD2(-380, 640)
            }
        case .leaving:
            s.leaveTime += dt
            s.vel.y -= 500 * dt
            s.pos += s.vel * dt
            s.rot = min(0.9, s.rot + 2 * dt)
            if s.leaveTime > 3 || s.pos.y > Float(region.maxY) + 220 || s.pos.x < Float(region.minX) - 220 {
                spider = nil
                lastHelperEnd = time
                return
            }
        }

        if s.phase == .swinging { scrapeSnow(&s, oldX: oldX) }
        updateWebBalls(&s, dt: dt)
        updatePatches(&s, dt: dt)
        for i in s.pulls.indices { s.pulls[i].age += dt }
        s.pulls.removeAll { $0.age > 0.55 }
        updateNet(&s, dt: dt)
        spider = s
    }

    private func swingStep(_ s: inout SpiderRun, dt: Float) {
        let d = s.pos - s.anchor
        let len = max(simd_length(d), 1)
        let n = d / len
        var a = SIMD2<Float>(0, -SpiderMetrics.gravity)
        if n.y < -0.15 {                                       // below the anchor: pump toward the left
            var t = SIMD2(-n.y, n.x)
            if t.x > 0 { t = -t }
            a += t * 320
        }
        s.vel += a * dt
        s.vel *= max(0, 1 - 0.1 * dt)
        s.pos += s.vel * dt
        // Taut rope: stay on the circle and drop the outward velocity.
        let d2 = s.pos - s.anchor
        let l2 = max(simd_length(d2), 1)
        if l2 > s.rope {
            let n2 = d2 / l2
            s.pos = s.anchor + n2 * s.rope
            let vr = simd_dot(s.vel, n2)
            if vr > 0 { s.vel -= n2 * vr }
        }
        // He cannot sink into whatever he is above.
        if let g = spiderGround(at: s.pos.x, below: s.pos.y) {
            let minY = g.surface.topY + SpiderMetrics.feetDrop + 2
            if s.pos.y < minY { s.pos.y = minY; s.vel.y = max(0, s.vel.y) }
        }
        let theta = atan2(d2.x, -d2.y)
        s.rot = min(max(-theta * 0.8, -0.9), 0.9)
        // Let go on the far side of the arc, then web the next anchor.
        if (s.pos.x < s.anchor.x - s.rope * 0.62 && s.vel.y >= 0) || s.swingTime > 3.2 {
            attachNextAnchor(&s)
        }
    }

    /// His feet drag through the snow: everything above foot level is pushed out of the way.
    private func scrapeSnow(_ s: inout SpiderRun, oldX: Float) {
        let feetY = s.pos.y - SpiderMetrics.feetDrop
        var removedTotal: Float = 0
        for st in ordered where st.surface.minX <= s.pos.x && st.surface.maxX >= s.pos.x && st.surface.topY < s.pos.y - 20 {
            let keep = max(0, feetY - st.surface.topY)
            let h = st.field.height(atLocalX: s.pos.x - st.surface.minX)
            guard h > keep else { continue }
            let lo = min(oldX, s.pos.x) - 26 - st.surface.minX, hi = max(oldX, s.pos.x) + 26 - st.surface.minX
            let removed = st.field.sweep(fromLocalX: lo, toLocalX: hi, keepDepth: keep)
            if removed > 0 { st.dirty = true; removedTotal += removed }
        }
        guard removedTotal > 0 else { return }
        totals.lostVolume += removedTotal
        s.sprayAccumulator += removedTotal / 30
        var n = 0
        while s.sprayAccumulator >= 1, n < 3 {
            s.sprayAccumulator -= 1; n += 1
            guard pool.count < pool.capacity - 40 else { break }
            var p = SnowParticle.blank
            p.position = SIMD2(s.pos.x - 8 + rng.float(-6...6), feetY + rng.float(0...12))
            p.velocity = SIMD2(s.vel.x * 0.5 + rng.float(-60...60), rng.float(50...170))
            p.radius = rng.float(1.3...3.0); p.opacity = 0.9; p.mass = 1
            p.state = .displaced; p.orbitRadius = -1
            pool.spawn(p)
        }
        if s.sprayAccumulator > 6 { s.sprayAccumulator = 6 }
    }

    // MARK: Web balls and yanks

    /// The 120 pt-wide window of snow with the most volume between two x positions, over all surfaces.
    func bestPile(from minX: Float, to maxX: Float) -> (x: Float, y: Float, surfaceID: String, volume: Float)? {
        var best: (x: Float, y: Float, surfaceID: String, volume: Float)?
        for st in ordered {
            let sf = st.surface, f = st.field
            let lo = max(minX, sf.minX), hi = min(maxX, sf.maxX)
            guard hi - lo > 40 else { continue }
            let first = f.binIndex(atLocalX: lo - sf.minX), last = f.binIndex(atLocalX: hi - sf.minX)
            let win = max(2, Int(120 / f.binWidth))
            var i = first
            let stride = max(1, win / 3)
            while i <= last {
                var vol: Float = 0
                for j in i..<min(last + 1, i + win) { vol += f.height(atBin: j) * f.binWidth }
                if best == nil || vol > best!.volume {
                    let cx = sf.minX + (Float(min(last, i + win / 2)) + 0.5) * f.binWidth
                    best = (cx, sf.topY + f.height(atLocalX: cx - sf.minX), sf.id, vol)
                }
                i += stride
            }
        }
        return best
    }

    private func updateWebBalls(_ s: inout SpiderRun, dt: Float) {
        // Fire at the biggest pile ahead every couple of seconds.
        s.ballTimer -= dt
        if s.phase == .swinging, s.ballTimer <= 0, s.balls.isEmpty, s.patches.count < 2 {
            if let pile = bestPile(from: s.pos.x - 950, to: s.pos.x - 130), pile.volume > 200 {
                s.balls.append(SpiderWebBall(from: s.handWorld, target: SIMD2(pile.x, pile.y + 4), t: 0, duration: 0.4,
                                             surfaceID: pile.surfaceID, pos: s.handWorld))
                s.ballTimer = rng.float(1.5...2.2)
            } else {
                s.ballTimer = 0.5
            }
        }
        var i = 0
        while i < s.balls.count {
            s.balls[i].t += dt
            let u = min(s.balls[i].t / s.balls[i].duration, 1)
            let b = s.balls[i]
            s.balls[i].pos = b.from + (b.target - b.from) * u + SIMD2(0, 45 * sin(.pi * u))
            if u >= 1 {
                s.patches.append(SpiderPatch(x: b.target.x, y: b.target.y, radius: 70, age: 0, yanked: false, surfaceID: b.surfaceID))
                s.balls.remove(at: i)
            } else { i += 1 }
        }
    }

    private func updatePatches(_ s: inout SpiderRun, dt: Float) {
        for i in s.patches.indices {
            s.patches[i].age += dt
            if !s.patches[i].yanked, s.patches[i].age >= 0.45 {
                s.patches[i].yanked = true
                yankPatch(&s, s.patches[i])
            }
        }
        s.patches.removeAll { $0.age > 1.6 }
    }

    /// He tugs the web: the webbed clump is torn off the pile and hauled toward him, then fades away.
    private func yankPatch(_ s: inout SpiderRun, _ patch: SpiderPatch) {
        guard let st = state(forSurface: patch.surfaceID) else { return }
        let local = patch.x - st.surface.minX
        let f = st.field
        let lo = f.binIndex(atLocalX: local - patch.radius), hi = f.binIndex(atLocalX: local + patch.radius)
        let bw = f.binWidth
        var removed: Float = 0
        for i in lo...hi {
            let d = abs((Float(i) + 0.5) * bw - local)
            guard d < patch.radius else { continue }
            let u = d / patch.radius
            let w: Float = u < 0.6 ? 1 : (1 - u) / 0.4
            let h = st.field.height(atBin: i)
            if h > 0 { removed += st.field.melt(bin: i, depth: h * w) * bw }
        }
        if removed > 0 { st.dirty = true; totals.lostVolume += removed }
        let hand = s.handWorld
        for _ in 0..<14 where pool.count < pool.capacity - 40 {
            var p = SnowParticle.blank
            p.position = SIMD2(patch.x + rng.float(-patch.radius * 0.6...patch.radius * 0.6), patch.y + rng.float(0...12))
            p.velocity = (hand - p.position) / 0.5 + SIMD2(-120, 140)
            p.radius = rng.float(2.5...5.5); p.opacity = 0.95; p.mass = 1.3
            p.angularVelocity = rng.float(-5...5)
            p.state = .displaced; p.orbitRadius = -1
            pool.spawn(p)
        }
        s.pulls.append(SpiderPull(to: SIMD2(patch.x, patch.y + 6), age: 0))
    }

    // MARK: Net

    private func updateNet(_ s: inout SpiderRun, dt: Float) {
        s.netTimer -= dt
        if s.phase == .swinging, s.net == nil, s.netTimer <= 0 {
            s.net = SpiderNet(center: s.pos + SIMD2(-180, 30), radius: 150, age: 0)
            s.netTimer = rng.float(2.2...3.2)
        }
        guard var n = s.net else { return }
        n.age += dt
        n.center = s.pos + SIMD2(-180, 30)
        if n.age < 0.55 { netCapture(center: n.center, radius: n.radius) }
        s.net = n.age > 0.75 ? nil : n
    }

    /// Flakes touching the net stick, are pulled into it, and fade away (their snow is gone).
    func netCapture(center: SIMD2<Float>, radius: Float) {
        for i in 0..<pool.count {
            var p = pool[i]
            guard p.state == .falling || p.state == .disturbed, p.orbitRadius >= 0 else { continue }
            let d = p.position - center
            guard simd_length(d) < radius else { continue }
            totals.lostVolume += p.volume
            p.volume = 0
            p.state = .displaced
            p.orbitRadius = -1
            p.velocity = -d * 3.5
            p.opacity = max(p.opacity, 0.8)
            pool[i] = p
        }
    }
}
