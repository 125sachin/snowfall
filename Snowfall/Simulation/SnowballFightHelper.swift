import Foundation
import simd

/// Two kids, one at each side of the screen, have a snowball fight. They scoop snow off the floor, throw at
/// each other (some hit, some miss), and lob the rest across the screen at different angles: at piles of snow,
/// at windows (leaving a splat) and at the floor.

struct FlyingSnowball {
    enum Hit: Equatable { case kid(Int), pile, face, floor }
    var pos: SIMD2<Float>
    var vel: SIMD2<Float>
    var age: Float = 0
    var flight: Float
    var hit: Hit
    var target: SIMD2<Float>
    var surfaceID: String?
    var owner: Int
}

struct FightKid {
    var x: Float
    var home: Float
    var facingRight: Bool
    var phase: Float                   // offsets the shuffle so the kids do not move in step
    var timer: Float                   // until the next scoop
    var scoopTime: Float = -1          // >= 0 while scooping
    var armTime: Float = -1            // >= 0 while throwing
    var released = false
    var throwsDone = 0
    var stagger: Float = 0             // seconds left of the "ouch" reaction after being hit
    var splats: [Float] = []           // ages of snow splats on the coat

    static let scoopDuration: Float = 0.7
    static let throwDuration: Float = 0.7
    static let releaseAt: Float = 0.36

    var crouch: Float { scoopTime >= 0 ? sin(.pi * min(scoopTime / Self.scoopDuration, 1)) : 0 }

    /// Arm angle (0 = right, π = left), mirrored for the kid who faces right.
    var armAngle: Float {
        func lerp(_ a: Float, _ b: Float, _ u: Float) -> Float { a + (b - a) * min(max(u, 0), 1) }
        func ease(_ u: Float) -> Float { let c = min(max(u, 0), 1); return c * c * (3 - 2 * c) }
        var a: Float
        if scoopTime >= 0 {
            a = -1.9 + 0.5 * sin(scoopTime * 14)                       // reaching down to scoop
        } else if armTime >= 0 {
            if armTime < 0.3 { a = lerp(-1.5, 1.0, ease(armTime / 0.3)) }
            else if armTime < 0.42 { a = lerp(1.0, 2.6, (armTime - 0.3) / 0.12) }
            else { a = lerp(2.6, -1.5, (armTime - 0.42) / 0.25) }
        } else if stagger > 0 {
            a = 0.9 + 0.7 * sin(stagger * 30)                          // flailing
        } else {
            a = -1.5
        }
        return facingRight ? .pi - a : a
    }

    /// Horizontal offset of the "ouch" reaction.
    var shake: Float { stagger > 0 ? sin(stagger * 45) * 5 * min(1, stagger / 0.3) * (facingRight ? -1 : 1) : 0 }
}

struct FighterRun {
    enum Phase { case arriving, fighting, leaving }
    var phase: Phase = .arriving
    var t: Float = 0
    var kids: [FightKid]
    var balls: [FlyingSnowball] = []
    static let maxThrows = 12
    static let walkSpeed: Float = 130

    var totalThrows: Int { kids.reduce(0) { $0 + $1.throwsDone } }
}

extension PhysicsWorld {
    func startFighter() {
        guard !isHelperRunning, !region.isEmpty else { return }
        let left = FightKid(x: Float(region.minX) - 60, home: Float(region.minX) + 150, facingRight: true, phase: 0, timer: 0.6)
        let right = FightKid(x: Float(region.maxX) + 60, home: Float(region.maxX) - 150, facingRight: false, phase: 2.1, timer: 1.4)
        fighter = FighterRun(kids: [left, right])
    }

    func kidDrawX(_ k: FightKid, t: Float) -> Float { k.x + 14 * sin(t * 0.9 + k.phase) * (k.scoopTime < 0 && k.armTime < 0 ? 1 : 0.3) + k.shake }

    func fighterProps(_ f: FighterRun, _ out: inout [RenderProp]) {
        for k in f.kids {
            let dx = kidDrawX(k, t: f.t)
            let ground = funGround(at: k.x)
            let walking = f.phase != .fighting
            let bob = walking ? abs(sin(f.t * 8 + k.phase)) * 2 : 0
            // Snow splats on the coat fade out.
            for age in k.splats {
                let sz: Float = 24
                out.append(RenderProp(kind: .splat, x: dx + (k.facingRight ? 4 : -4), y: ground + 52 + bob, w: sz, h: sz, rot: 0, alpha: max(0, 1 - age / 2.2) * 0.95))
            }
            kidProps(x: dx, ground: ground, bob: bob, crouch: k.crouch, armAngle: k.armAngle, facingRight: k.facingRight, out: &out)
            if k.armTime >= 0, k.armTime < FightKid.releaseAt {                         // snowball in the raised hand
                let h = kidHandWorld(x: dx, ground: ground, bob: bob, armAngle: k.armAngle, facingRight: k.facingRight)
                out.append(RenderProp(kind: .snowball, x: h.x, y: h.y, w: 14, h: 14))
            } else if k.scoopTime >= FightKid.scoopDuration * 0.5 {                     // a freshly packed ball
                let h = kidHandWorld(x: dx, ground: ground, bob: bob, crouch: k.crouch, armAngle: k.armAngle, facingRight: k.facingRight)
                out.append(RenderProp(kind: .snowball, x: h.x, y: h.y, w: 12, h: 12))
            }
        }
        for b in f.balls { out.append(RenderProp(kind: .snowball, x: b.pos.x, y: b.pos.y, w: 16, h: 16, rot: b.age * 9 * (b.vel.x < 0 ? 1 : -1))) }
    }

    /// Chooses what a kid throws at: the other kid (about half hit), a window, a pile, or the floor.
    func pickFightTarget(thrower i: Int, run f: FighterRun) -> (FlyingSnowball.Hit, SIMD2<Float>, String?) {
        let other = f.kids[1 - i]
        let r = rng.float(0...1)
        if r < 0.42 {
            let ground = funGround(at: other.x)
            if rng.float(0...1) < 0.58 {                                                // a hit
                return (.kid(1 - i), SIMD2(other.x + rng.float(-8...8), ground + rng.float(36...64)), nil)
            }
            let miss = (rng.float(0...1) < 0.5 ? -1 : 1) * rng.float(50...140)           // a miss: lands short or long
            return (.floor, SIMD2(other.x + miss, funGround(at: other.x + miss)), nil)
        }
        if r < 0.74 {
            let wins = ordered.filter { $0.surface.kind == .windowTop }
            if !wins.isEmpty {
                let w = wins[Int(rng.next() % UInt64(wins.count))].surface
                let px = rng.float(w.minX + 10...max(w.minX + 11, w.maxX - 10))
                let top = w.topY(atX: px)
                let low = Float(w.frame.minY) + 25
                let py = low < top - 12 ? rng.float(low...(top - 12)) : top - 12
                return (.face, SIMD2(px, py), w.id)
            }
        }
        if r < 0.88, let p = bestPile(from: Float(region.minX) + 200, to: Float(region.maxX) - 200), p.volume > 100 {
            return (.pile, SIMD2(p.x, p.y), p.surfaceID)
        }
        let fx = rng.float(Float(region.minX) + 250...Float(region.maxX) - 250)
        return (.floor, SIMD2(fx, funGround(at: fx)), nil)
    }

    func stepFighter(dt: Float) {
        guard var f = fighter else { return }
        f.t += dt
        let minX = Float(region.minX), maxX = Float(region.maxX)

        // Movement.
        for i in f.kids.indices {
            switch f.phase {
            case .arriving:
                let dir: Float = f.kids[i].x < f.kids[i].home ? 1 : -1
                f.kids[i].x += dir * FighterRun.walkSpeed * dt
                if (dir > 0 && f.kids[i].x >= f.kids[i].home) || (dir < 0 && f.kids[i].x <= f.kids[i].home) { f.kids[i].x = f.kids[i].home }
            case .leaving:                                                              // each runs off its own side
                f.kids[i].x += (f.kids[i].facingRight ? -1 : 1) * 160 * dt
            case .fighting:
                break
            }
            f.kids[i].stagger = max(0, f.kids[i].stagger - dt)
            f.kids[i].splats = f.kids[i].splats.map { $0 + dt }.filter { $0 < 2.2 }
        }
        if f.phase == .arriving, f.kids.allSatisfy({ $0.x == $0.home }) { f.phase = .fighting }

        // Throw cycle: scoop snow off the floor, wind up, throw.
        if f.phase == .fighting {
            for i in f.kids.indices {
                var k = f.kids[i]
                let ground = funGround(at: k.x)
                if k.scoopTime < 0, k.armTime < 0 {
                    k.timer -= dt
                    if k.timer <= 0, k.throwsDone < FighterRun.maxThrows { k.scoopTime = 0 }
                } else if k.scoopTime >= 0 {
                    k.scoopTime += dt
                    if k.scoopTime >= FightKid.scoopDuration {
                        k.scoopTime = -1; k.armTime = 0; k.released = false
                        if let st = floorState(at: k.x) { clearDisc(on: st, centerX: k.x + (k.facingRight ? 28 : -28), radius: 36, fraction: 0.5) }
                    }
                } else {
                    k.armTime += dt
                    if !k.released, k.armTime >= FightKid.releaseAt {
                        k.released = true
                        k.throwsDone += 1
                        let hand = kidHandWorld(x: kidDrawX(k, t: f.t), ground: ground, armAngle: k.armAngle, facingRight: k.facingRight)
                        let (hit, target, sid) = pickFightTarget(thrower: i, run: f)
                        let d = target - hand
                        // Flight time varies a lot, so some throws are flat and fast and others are high lobs.
                        let base = min(max(0.42 + abs(d.x) / 1700, 0.45), 1.0)
                        var T = base * (rng.float(0...1) < 0.4 ? rng.float(1.8...3.0) : rng.float(1.0...1.4))   // 40% high lobs
                        func launch(_ T: Float) -> SIMD2<Float> { SIMD2(d.x / T, (d.y + 0.5 * FunMetrics.gravity * T * T) / T) }
                        // Keep the arc on screen: shorten the flight until the top of the arc fits.
                        while T > base, hand.y + launch(T).y * launch(T).y / (2 * FunMetrics.gravity) > Float(region.maxY) - 60 { T *= 0.92 }
                        let vel = launch(T)
                        f.balls.append(FlyingSnowball(pos: hand, vel: vel, age: 0, flight: T, hit: hit, target: target, surfaceID: sid, owner: i))
                    }
                    if k.armTime >= FightKid.throwDuration { k.armTime = -1; k.timer = rng.float(0.45...1.0) }
                }
                f.kids[i] = k
            }
            if f.kids.allSatisfy({ $0.throwsDone >= FighterRun.maxThrows && $0.armTime < 0 && $0.scoopTime < 0 }), f.balls.isEmpty {
                f.phase = .leaving
            }
        }

        // Flying snowballs: ballistic arcs that burst on arrival.
        var i = 0
        while i < f.balls.count {
            f.balls[i].age += dt
            f.balls[i].pos += f.balls[i].vel * dt
            f.balls[i].vel.y -= FunMetrics.gravity * dt
            if f.balls[i].age >= f.balls[i].flight {
                let b = f.balls[i]
                if case .kid(let j) = b.hit {
                    f.kids[j].stagger = 0.55
                    f.kids[j].splats.append(0)
                    funSpray(at: b.target, count: 14, speed: 80...260)
                } else {
                    splat(b)
                }
                f.balls.remove(at: i)
            } else { i += 1 }
        }

        if f.phase == .leaving, f.kids.allSatisfy({ $0.x < minX - 90 || $0.x > maxX + 90 }) {
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
        case .kid:
            break
        }
    }
}
