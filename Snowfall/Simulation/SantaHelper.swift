import Foundation
import simd

/// Sprite metrics shared by simulation (wand tip position) and renderer. Design space: origin
/// bottom-left of the sprite, Santa faces LEFT.
enum SantaMetrics {
    static let scale: Float = 1.0
    static let width: Float = 120
    static let height: Float = 150
    /// Gloved hand holding the wand, in design coordinates.
    static let hand = SIMD2<Float>(20, 98)
    static let wandSize = SIMD2<Float>(64, 16)
    /// Wand pivot (handle end) is 30 pt from the wand sprite's centre; the tip is 56 pt from the pivot.
    static let wandPivotToCenter: Float = 30
    static let wandLength: Float = 56
}

struct SantaRun {
    enum Phase { case arriving, casting, sweeping, leaving }
    var phase: Phase = .arriving
    var t: Float = 0                    // time in the current phase
    var totalTime: Float = 0
    var x: Float                        // sprite centre x
    var y: Float                        // sprite bottom y
    var start: SIMD2<Float>
    var hover: SIMD2<Float>
    var wandAngle: Float = -0.6         // radians; 0 = pointing left, negative = raised
    var sparkleAccumulator: Float = 0

    var handWorld: SIMD2<Float> {
        let k = SantaMetrics.scale
        return SIMD2(x - SantaMetrics.width * k / 2 + SantaMetrics.hand.x * k, y + SantaMetrics.hand.y * k)
    }
    var tipWorld: SIMD2<Float> {
        handWorld + SIMD2(-cos(wandAngle), -sin(wandAngle)) * (SantaMetrics.wandLength * SantaMetrics.scale)
    }
}

/// A magic whirlwind. Axis at `x`, leaning with height; cone-shaped (radius grows with height).
struct Tornado {
    var x: Float
    var baseY: Float
    var height: Float = 0
    var age: Float = 0
    var strength: Float = 0             // 0...1 ramp while forming
    var lean: Float = 0
    var leanPhase: Float
    var emitAccumulator: Float = 0
    var liftAccumulator: Float = 0      // snow lifted but not yet turned into a particle
    var liftX: Float = 0
    var liftY: Float = 0
}

extension PhysicsWorld {
    // MARK: Santa

    func startSanta() {
        guard santa == nil, plow == nil, !region.isEmpty else { return }
        let hx = max(Float(region.minX) + 300, Float(region.maxX) - 200)
        let floorY = floorState(at: hx)?.surface.topY ?? Float(region.minY)
        let hy = floorY + max(150, min(300, Float(region.height) * 0.28))
        let start = SIMD2(Float(region.maxX) + 160, hy + 170)
        santa = SantaRun(x: start.x, y: start.y, start: start, hover: SIMD2(hx, hy))
    }

    func stepSanta(dt: Float) {
        guard var s = santa else { return }
        s.t += dt
        s.totalTime += dt
        var casting = false
        switch s.phase {
        case .arriving:
            let u = min(s.t / 2.6, 1)
            let e = 1 - pow(1 - u, 3)
            s.x = s.start.x + (s.hover.x - s.start.x) * e
            s.y = s.start.y + (s.hover.y - s.start.y) * e
            s.wandAngle = -0.7 + 0.1 * sin(s.t * 3)
            if u >= 1 { s.phase = .casting; s.t = 0 }
        case .casting:
            casting = true
            s.wandAngle = -0.95 + 0.75 * sin(s.t * 9)          // flourish
            if tornado == nil, s.t > 0.6 {
                // Conjured at the right edge so that its sweep covers the whole width.
                let tx = Float(region.maxX) + 10
                tornado = Tornado(x: tx, baseY: floorState(at: tx - 20)?.surface.topY ?? Float(region.minY),
                                  leanPhase: rng.float(0...6.28))
            }
            if s.t > 1.6 { s.phase = .sweeping; s.t = 0 }
        case .sweeping:
            casting = true
            s.wandAngle = -0.55 + 0.8 * sin(s.t * 7.5)
            if let t = tornado {
                let target = min(t.x + 260, s.hover.x)            // stays put until the tornado has moved on
                s.x += (target - s.x) * min(1, 2.5 * dt)          // conducts the tornado from behind
            } else {
                s.phase = .leaving; s.t = 0
            }
        case .leaving:
            s.wandAngle = -0.3
            s.x -= 170 * dt
            s.y += 150 * dt
            if s.t > 2.6 || s.y > Float(region.maxY) + 220 || s.x < Float(region.minX) - 200 {
                santa = nil
                lastHelperEnd = time
                return
            }
        }
        if casting {
            s.sparkleAccumulator += 110 * dt
            var n = 0
            while s.sparkleAccumulator >= 1, n < 4 {
                s.sparkleAccumulator -= 1; n += 1
                spawnSparkle(at: s.tipWorld)
            }
        }
        santa = s
    }

    private func spawnSparkle(at tip: SIMD2<Float>) {
        guard pool.count < pool.capacity - 40 else { return }
        var p = SnowParticle.blank
        p.position = tip + SIMD2(rng.float(-4...4), rng.float(-4...4))
        p.velocity = SIMD2(rng.float(-45...45), rng.float(-10...55))
        p.radius = rng.float(1.1...1.6)
        p.mass = rng.float(0.8...1)              // base opacity
        p.baseRadius = rng.float(0.6...1.1)      // lifetime (s)
        p.opacity = p.mass
        p.state = .sparkle
        pool.spawn(p)
    }

    func stepSparkle(_ p: inout SnowParticle, dt: Float) -> Bool {
        p.stateTime += dt
        guard p.stateTime < p.baseRadius else { return false }
        p.velocity *= max(0, 1 - 2.5 * dt)
        p.position += p.velocity * dt
        p.opacity = p.mass * (1 - p.stateTime / p.baseRadius)
        return true
    }

    // MARK: Tornado

    func stepTornado(dt: Float) {
        guard var t = tornado else { return }
        let c = config
        t.age += dt
        t.strength = min(1, t.age / 1.6)
        let ease = t.strength * t.strength * (3 - 2 * t.strength)
        t.x -= c.tornadoSpeed * ease * dt
        t.baseY = floorState(at: t.x)?.surface.topY ?? t.baseY
        t.height = min(Float(region.height) * 0.72, 700) * ease
        t.lean = 38 * sin(t.age * 0.9 + t.leanPhase)

        // Visible whirl: light flakes spiralling up the funnel (no volume).
        t.emitAccumulator += c.tornadoEmitRate * ease * dt
        var n = 0
        while t.emitAccumulator >= 1, n < 4 {
            t.emitAccumulator -= 1; n += 1
            if pool.count < pool.capacity - 150 { spawnSwirl(t, volume: 0, x: nil, y: nil) }
        }

        // Lift snow from every surface whose top edge is inside the funnel and under its catch zone.
        for st in ordered {
            let sf = st.surface
            let top = sf.topY
            guard top >= t.baseY - 4, top <= t.baseY + t.height else { continue }
            let rr = c.tornadoCoreRadius + (top - t.baseY) * c.tornadoSlope + 45 * ease
            guard sf.maxX > t.x - rr, sf.minX < t.x + rr else { continue }
            let removed = st.field.sweep(fromLocalX: t.x - rr - sf.minX, toLocalX: t.x + rr - sf.minX, keepDepth: 0)
            if removed > 0 {
                t.liftAccumulator += removed
                t.liftX = min(max(t.x + rng.float(-rr...rr), sf.minX), sf.maxX)
                t.liftY = top + 2
                st.dirty = true
            }
        }
        var spawned = 0
        while t.liftAccumulator >= c.tornadoClusterVolume, spawned < 8 {
            let v = min(t.liftAccumulator, 400)
            t.liftAccumulator -= v
            spawned += 1
            spawnSwirl(t, volume: v, x: t.liftX, y: t.liftY)
        }
        if t.liftAccumulator > 8 * c.tornadoClusterVolume {      // overwhelmed: the vortex swallows the rest
            totals.lostVolume += t.liftAccumulator - 8 * c.tornadoClusterVolume
            t.liftAccumulator = 8 * c.tornadoClusterVolume
        }

        if t.x < Float(region.minX) - 80 {
            totals.lostVolume += t.liftAccumulator
            tornado = nil
            return
        }
        tornado = t
    }

    private func spawnSwirl(_ t: Tornado, volume: Float, x: Float?, y: Float?) {
        var p = SnowParticle.blank
        let startX = x ?? t.x
        p.position = SIMD2(startX, y ?? (t.baseY + rng.float(0...10)))
        p.velocity = SIMD2(startX, rng.float(95...175))          // .x = entry x (blended away), .y = rise speed
        p.orbitPhase = rng.float(0...6.283)
        p.orbitRadius = rng.float(0.55...1.35)
        p.angularVelocity = config.tornadoOmega * rng.float(0.8...1.25)
        p.baseRadius = volume > 0 ? min(max(sqrt(volume) * 0.45, 2.5), 8) : rng.float(1.2...3.0)
        p.radius = p.baseRadius
        p.mass = volume > 0 ? 0.97 : rng.float(0.5...0.9)        // base opacity while swirling
        p.opacity = p.mass
        p.volume = volume
        p.state = .swirling
        if !pool.spawn(p) { totals.droppedVolume += volume }
    }

    /// Spiral up the funnel; returns false only if the particle should be removed.
    func stepSwirl(_ p: inout SnowParticle, dt: Float) -> Bool {
        guard let t = tornado else { eject(&p, rho: 30); return true }
        p.stateTime += dt
        p.position.y += p.velocity.y * dt
        let h = max(0, p.position.y - t.baseY)
        p.orbitPhase += p.angularVelocity * dt
        let rho = (config.tornadoCoreRadius + h * config.tornadoSlope) * p.orbitRadius * (0.35 + 0.65 * t.strength)
        let axis = t.x + t.lean * (h / max(t.height, 1))
        let orbitX = axis + rho * cos(p.orbitPhase)
        let blend = min(1, p.stateTime / 0.7)
        let e = blend * blend * (3 - 2 * blend)
        p.position.x = p.velocity.x * (1 - e) + orbitX * e
        let depth = 0.5 + 0.5 * sin(p.orbitPhase)                // 1 = near side of the funnel
        p.radius = p.baseRadius * (0.7 + 0.3 * depth)
        p.opacity = p.mass * (0.45 + 0.55 * depth)
        p.rotation += 2 * dt
        if p.position.y > t.baseY + t.height + 30 || p.stateTime > 6 { eject(&p, rho: rho) }
        return true
    }

    /// Flings a swirling particle off the funnel. Its snow volume has now left the system.
    private func eject(_ p: inout SnowParticle, rho: Float) {
        p.velocity = SIMD2(-sin(p.orbitPhase) * rho * p.angularVelocity * 0.8 - 60, 70 + rng.float(0...80))
        p.state = .displaced
        p.stateTime = 0
        p.radius = p.baseRadius
        p.opacity = max(p.opacity, 0.7)
        p.mass = 1.3
        p.orbitRadius = -1                 // marks "already thrown out": the tornado ignores it from now on
        totals.lostVolume += p.volume
        p.volume = 0
    }

    /// Effect of the tornado on an airborne flake: flakes inside the funnel's catch zone are taken
    /// into the spiral (the state becomes `.swirling`); flakes nearby are drawn inward and upward.
    /// Returns the extra acceleration (pt/s²) to apply this step.
    func tornadoInfluence(_ p: inout SnowParticle, tornado t: Tornado) -> SIMD2<Float> {
        let h = p.position.y - t.baseY
        guard h > -20 else { return .zero }
        let hc = min(max(h, 0), t.height)
        let axis = t.x + t.lean * (hc / max(t.height, 1))
        let dx = p.position.x - axis
        let coneR = (config.tornadoCoreRadius + hc * config.tornadoSlope) * (0.35 + 0.65 * t.strength)
        let suck = coneR * 3 + 120 * t.strength
        let adx = abs(dx)
        guard adx < suck else { return .zero }
        if h <= t.height, adx < coneR * 1.5 + 30 * t.strength {
            p.state = .swirling
            p.stateTime = 0
            p.velocity = SIMD2(p.position.x, rng.float(95...175))     // .x = entry x, .y = rise speed
            p.orbitPhase = dx >= 0 ? rng.float(-0.8...0.8) : rng.float(2.3...3.9)
            p.orbitRadius = rng.float(0.55...1.35)
            p.angularVelocity = config.tornadoOmega * rng.float(0.8...1.25)
            p.baseRadius = p.radius
            p.mass = min(max(p.opacity, 0.5), 1)                      // base opacity while swirling
            return .zero
        }
        let f = 1 - adx / suck
        let inward: Float = dx > 0 ? -1 : 1
        // Strong inward pull, plus the tornado's own travel so pulled flakes keep up with it.
        let travel = -config.tornadoSpeed * config.baseDrag
        return SIMD2((inward * 2400 + travel) * f * t.strength, 260 * f * t.strength)
    }
}
