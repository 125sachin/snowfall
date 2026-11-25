import Foundation
import simd

/// Sprite metrics shared by simulation and renderer. Design space: origin bottom-left, he faces LEFT.
enum IronManMetrics {
    static let scale: Float = 1.0
    static let width: Float = 110
    static let height: Float = 150
    /// Forward lean (radians, positive = top toward the left), applied about the sprite centre.
    static let tilt: Float = 0.28
    /// Eye position relative to the sprite centre, in design units, before the tilt.
    static let eyeOffset = SIMD2<Float>(-14, 58)
}

struct IronManRun {
    enum Phase { case arriving, scanning, leaving }
    var phase: Phase = .arriving
    var t: Float = 0
    var totalTime: Float = 0
    var x: Float                         // sprite centre x
    var y: Float                         // sprite bottom y (before bob)
    var start: SIMD2<Float>
    var hover: SIMD2<Float>
    var sweepPhase: Float = 0
    var firing = false
    var intensity: Float = 0             // 0...1, beam brightness
    var spot = SIMD2<Float>.zero         // where the first beam ends (highest surface ahead)
    var spot2 = SIMD2<Float>.zero        // where the second beam ends (the floor)
    var steamAccumulator: Float = 0
    var firingTime: Float = 0

    var bob: Float { sin(totalTime * 2.4) * 5 }

    var eyeWorld: SIMD2<Float> {
        let k = IronManMetrics.scale
        let c = SIMD2(x, y + bob + IronManMetrics.height * k / 2)
        let o = IronManMetrics.eyeOffset * k
        let ct = cos(IronManMetrics.tilt), st = sin(IronManMetrics.tilt)
        return c + SIMD2(o.x * ct - o.y * st, o.x * st + o.y * ct)
    }
}

extension PhysicsWorld {
    func startIronMan() {
        guard ironMan == nil, plow == nil, santa == nil, tornado == nil, thor == nil, spider == nil, !region.isEmpty else { return }
        let hx = Float(region.maxX) - 40
        let floorY = floorState(at: hx)?.surface.topY ?? Float(region.minY)
        let hy = floorY + max(220, min(340, Float(region.height) * 0.32))
        let start = SIMD2(Float(region.maxX) + 220, hy + 140)
        ironMan = IronManRun(x: start.x, y: start.y, start: start, hover: SIMD2(hx, hy))
    }

    func stepIronMan(dt: Float) {
        guard var m = ironMan else { return }
        m.t += dt
        m.totalTime += dt
        m.firing = false
        switch m.phase {
        case .arriving:
            let u = min(m.t / 2.4, 1)
            let e = 1 - pow(1 - u, 3)
            m.x = m.start.x + (m.hover.x - m.start.x) * e
            m.y = m.start.y + (m.hover.y - m.start.y) * e
            if u > 0.35 { m.firing = true }                        // starts lasing as he comes into view
            if u >= 1 { m.phase = .scanning; m.t = 0 }
        case .scanning:
            m.firing = true
            m.x -= config.ironManSpeed * dt
            // Fly high enough to see over the tallest window ahead, so the beam can reach every top edge.
            var maxTop = floorState(at: m.x)?.surface.topY ?? Float(region.minY)
            for st in ordered where st.surface.maxX > m.x - 450 && st.surface.minX < m.x + 50 {
                maxTop = max(maxTop, st.surface.topY)
            }
            let desired = min(max(maxTop + 200, m.hover.y), Float(region.maxY) - 190)
            m.y += (desired - m.y) * min(1, 2.5 * dt)
            if m.x < Float(region.minX) + 140 { m.phase = .leaving; m.t = 0 }
        case .leaving:
            m.x -= 170 * dt
            m.y += 190 * dt
            m.intensity = max(0, m.intensity - 3 * dt)
            if m.t > 3 || m.y > Float(region.maxY) + 220 || m.x < Float(region.minX) - 200 {
                ironMan = nil
                lastHelperEnd = time
                return
            }
        }

        if m.firing {
            m.firingTime += dt
            m.intensity = min(1, m.firingTime / 0.5) * (0.88 + 0.12 * sin(m.totalTime * 45))
            m.sweepPhase += 6 * dt
            fireLaser(&m, dt: dt)
        }
        ironMan = m
    }

    /// Two beams from the eyes sweep ahead of him (to the left), out of phase: one lands on the highest
    /// surface under its target (e.g. a window top), the other on the floor, so both are melted.
    private func fireLaser(_ m: inout IronManRun, dt: Float) {
        let eye = m.eyeWorld
        m.spot = fireBeam(&m, from: eye, phase: m.sweepPhase, lookahead: 120, floorOnly: false, dt: dt)
        m.spot2 = fireBeam(&m, from: eye, phase: m.sweepPhase + .pi, lookahead: 170, floorOnly: true, dt: dt)
    }

    private func fireBeam(_ m: inout IronManRun, from eye: SIMD2<Float>, phase: Float, lookahead: Float,
                          floorOnly: Bool, dt: Float) -> SIMD2<Float> {
        let tx = eye.x - lookahead + 90 * sin(phase)
        var best: SurfaceState?
        if floorOnly {
            best = floorState(at: tx)
        } else {
            for st in ordered where tx >= st.surface.minX && tx <= st.surface.maxX && st.surface.topY < eye.y - 40 {
                if best == nil || st.surface.topY > best!.surface.topY { best = st }
            }
        }
        guard let st = best, st.surface.topY < eye.y - 40 else {
            let miss = SIMD2(tx, Float(region.minY) - 40)          // misses everything: beam runs off screen
            vaporizeAirborne(from: eye, to: miss)
            return miss
        }
        let local = tx - st.surface.minX
        let spot = SIMD2(tx, st.surface.topY(atX: tx) + st.field.height(atLocalX: local))
        let melted = meltSnow(on: st, atLocalX: local, dt: dt * m.intensity)
        m.steamAccumulator += melted / 5                           // steam rises where snow melts
        var n = 0
        while m.steamAccumulator >= 1, n < 6 {
            m.steamAccumulator -= 1; n += 1
            spawnSteam(at: SIMD2(spot.x + rng.float(-18...18), spot.y + rng.float(0...6)))
        }
        if m.steamAccumulator > 12 { m.steamAccumulator = 12 }
        vaporizeAirborne(from: eye, to: spot)
        return spot
    }

    /// Gaussian heat spot: depth removed per second = rate · exp(−d²/2σ²). Returns melted volume (pt²).
    private func meltSnow(on st: SurfaceState, atLocalX x: Float, dt: Float) -> Float {
        let sigma = config.laserSigma
        let reach = sigma * 3
        let f = st.field
        let lo = f.binIndex(atLocalX: x - reach), hi = f.binIndex(atLocalX: x + reach)
        let bw = f.binWidth
        var melted: Float = 0
        for i in lo...hi {
            let d = (Float(i) + 0.5) * bw - x
            let g = exp(-(d * d) / (2 * sigma * sigma))
            let h = st.field.height(atBin: i)
            guard h > 0 else { continue }
            let take = min(h, config.laserMeltRate * g * dt)
            if take > 0 { melted += st.field.melt(bin: i, depth: take) * bw }
        }
        if melted > 0 { st.dirty = true; totals.lostVolume += melted }
        return melted
    }

    /// Airborne flakes crossing the beam are vaporized (their snow is melted away).
    private func vaporizeAirborne(from a: SIMD2<Float>, to b: SIMD2<Float>) {
        let ab = b - a
        let len2 = max(simd_length_squared(ab), 1)
        var i = pool.count - 1
        var puffs = 0
        while i >= 0 {
            let p = pool[i]
            if p.state != .sparkle, p.state != .steam, p.state != .swirling {
                let u = min(max(simd_dot(p.position - a, ab) / len2, 0), 1)
                let closest = a + ab * u
                if simd_length(p.position - closest) < p.radius + 7 {
                    totals.lostVolume += p.volume
                    let pos = p.position
                    pool.remove(at: i)
                    if puffs < 6, pool.count < pool.capacity - 60 { spawnSteam(at: pos, small: true); puffs += 1 }
                }
            }
            i -= 1
        }
    }

    func spawnSteam(at pos: SIMD2<Float>, small: Bool = false) {
        guard pool.count < pool.capacity - 40 else { return }
        var p = SnowParticle.blank
        p.position = pos
        p.velocity = SIMD2(rng.float(-30...30), rng.float(small ? 30...70 : 50...115))
        p.startY = small ? rng.float(1.5...2.5) : rng.float(2.5...4.8)     // initial radius
        p.radius = p.startY
        p.baseRadius = rng.float(0.6...1.1)                                   // lifetime (s)
        p.mass = rng.float(0.55...0.85)                                       // base opacity
        p.opacity = p.mass
        p.state = .steam
        pool.spawn(p)
    }

    func stepSteam(_ p: inout SnowParticle, dt: Float) -> Bool {
        p.stateTime += dt
        guard p.stateTime < p.baseRadius else { return false }
        let u = p.stateTime / p.baseRadius
        p.velocity.x *= max(0, 1 - 1.5 * dt)
        p.velocity.y += 30 * dt                       // buoyant
        p.position += p.velocity * dt
        p.radius = p.startY * (1 + 1.8 * u)           // expands as it cools
        p.opacity = p.mass * pow(1 - u, 1.2)
        return true
    }
}
