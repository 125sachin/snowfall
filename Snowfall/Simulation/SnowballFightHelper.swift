import Foundation
import simd

// MARK: - Snowball fight

struct FlyingSnowball {
    enum Hit { case pile, face, floor }
    var pos: SIMD2<Float>
    var vel: SIMD2<Float>
    var age: Float = 0
    var flight: Float
    var hit: Hit
    var target: SIMD2<Float>
    var surfaceID: String?
}

struct FighterRun {
    var x: Float
    var t: Float = 0
    var throwTimer: Float = 0.9
    var armTime: Float = -1              // seconds into the throw animation; -1 = not throwing
    var released = false
    var balls: [FlyingSnowball] = []
    var throwsDone = 0
    static let maxThrows = 14
    static let walkSpeed: Float = 120

    var armAngle: Float {
        guard armTime >= 0 else { return -1.5 }
        func lerp(_ a: Float, _ b: Float, _ u: Float) -> Float { a + (b - a) * min(max(u, 0), 1) }
        if armTime < 0.3 { let u = armTime / 0.3; return lerp(-1.5, 1.0, u * u * (3 - 2 * u)) }
        if armTime < 0.42 { return lerp(1.0, 2.6, (armTime - 0.3) / 0.12) }
        return lerp(2.6, -1.5, (armTime - 0.42) / 0.25)
    }
}

extension PhysicsWorld {
    func startFighter() {
        guard !isHelperRunning, !region.isEmpty else { return }
        fighter = FighterRun(x: Float(region.maxX) + 50)
    }

    func kidHand(x: Float, ground: Float, angle: Float) -> SIMD2<Float> {
        let sh = SIMD2(x + FunMetrics.kidShoulder.x, ground + FunMetrics.kidSize.y / 2 + FunMetrics.kidShoulder.y)
        return sh + SIMD2(cos(angle), sin(angle)) * (FunMetrics.armSize.x - 4)
    }

    func fighterProps(_ f: FighterRun, _ out: inout [RenderProp]) {
        let ground = funGround(at: f.x)
        let bob = abs(sin(f.t * 8)) * 2
        out.append(RenderProp(kind: .kid, x: f.x, y: ground + FunMetrics.kidSize.y / 2 + bob, w: FunMetrics.kidSize.x, h: FunMetrics.kidSize.y))
        let a = f.armAngle
        let sh = SIMD2(f.x + FunMetrics.kidShoulder.x, ground + bob + FunMetrics.kidSize.y / 2 + FunMetrics.kidShoulder.y)
        let c = sh + SIMD2(cos(a), sin(a)) * (FunMetrics.armSize.x / 2)
        out.append(RenderProp(kind: .kidArm, x: c.x, y: c.y, w: FunMetrics.armSize.x, h: FunMetrics.armSize.y, rot: a))
        if f.armTime >= 0, f.armTime < 0.36 {            // snowball in the raised hand
            let h = sh + SIMD2(cos(a), sin(a)) * (FunMetrics.armSize.x + 2)
            out.append(RenderProp(kind: .snowball, x: h.x, y: h.y, w: 14, h: 14))
        }
        for b in f.balls { out.append(RenderProp(kind: .snowball, x: b.pos.x, y: b.pos.y, w: 16, h: 16, rot: b.age * 9)) }
    }

    /// Chooses what to hit: the biggest pile ahead, a window face (leaves a splat), or the floor.
    func pickTarget(from hand: SIMD2<Float>, kidX: Float, ground: Float) -> (FlyingSnowball.Hit, SIMD2<Float>, String?) {
        let near = kidX - 150, far = kidX - 950
        if rng.float(0...1) < 0.55, let p = bestPile(from: far, to: near), p.volume > 150 {
            return (.pile, SIMD2(p.x, p.y), p.surfaceID)
        }
        let wins = ordered.filter { $0.surface.kind == .windowTop && $0.surface.maxX > far && $0.surface.minX < near }
        if !wins.isEmpty {
            let w = wins[Int(rng.next() % UInt64(wins.count))].surface
            let lo = max(w.minX, far), hi = min(w.maxX, near)
            let px = lo < hi ? rng.float(lo...hi) : lo
            let top = w.topY(atX: px)
            let low = Float(w.frame.minY) + 25
            let py = low < top - 12 ? rng.float(low...(top - 12)) : top - 12
            return (.face, SIMD2(px, py), w.id)
        }
        return (.floor, SIMD2(kidX - rng.float(200...600), ground), nil)
    }

    func stepFighter(dt: Float) {
        guard var f = fighter else { return }
        f.t += dt
        f.x -= FighterRun.walkSpeed * dt
        let ground = funGround(at: f.x)

        // Throw cycle.
        if f.armTime < 0 {
            f.throwTimer -= dt
            if f.throwTimer <= 0, f.throwsDone < FighterRun.maxThrows, f.x > Float(region.minX) + 120, f.x < Float(region.maxX) - 40 {
                f.armTime = 0; f.released = false
            }
        } else {
            f.armTime += dt
            if !f.released, f.armTime >= 0.36 {
                f.released = true
                f.throwsDone += 1
                let hand = kidHand(x: f.x, ground: ground, angle: f.armAngle)
                let (hit, target, sid) = pickTarget(from: hand, kidX: f.x, ground: ground)
                let d = target - hand
                let T = min(max(0.45 + abs(d.x) / 1500, 0.5), 1.0)
                let vel = SIMD2(d.x / T, (d.y + 0.5 * FunMetrics.gravity * T * T) / T)
                f.balls.append(FlyingSnowball(pos: hand, vel: vel, age: 0, flight: T, hit: hit, target: target, surfaceID: sid))
            }
            if f.armTime >= 0.7 { f.armTime = -1; f.throwTimer = rng.float(0.8...1.4) }
        }

        // Flying snowballs: ballistic arcs that splat on arrival.
        var i = 0
        while i < f.balls.count {
            f.balls[i].age += dt
            f.balls[i].pos += f.balls[i].vel * dt
            f.balls[i].vel.y -= FunMetrics.gravity * dt
            if f.balls[i].age >= f.balls[i].flight {
                splat(f.balls[i])
                f.balls.remove(at: i)
            } else { i += 1 }
        }

        if f.x < Float(region.minX) - 90 {
            fighter = nil
            lastHelperEnd = time
            return
        }
        fighter = f
    }

    func splat(_ b: FlyingSnowball) {
        switch b.hit {
        case .pile:
            if let id = b.surfaceID, let st = state(forSurface: id) { clearDisc(on: st, centerX: b.target.x, radius: 55, fraction: 0.85) }
            funSpray(at: b.target, count: 10, speed: 120...320)
        case .face:
            if decals.count < 24 {
                decals.append(SplatDecal(x: b.target.x, y: b.target.y, size: rng.float(56...88)))
            }
            funSpray(at: b.target, count: 5, speed: 60...200)
        case .floor:
            if let st = floorState(at: b.target.x) { clearDisc(on: st, centerX: b.target.x, radius: 40, fraction: 0.5) }
            funSpray(at: b.target, count: 6, speed: 90...260)
        }
    }
}

