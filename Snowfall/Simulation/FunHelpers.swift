import Foundation
import simd

// Four lighter-weight snow helpers that share one generic sprite type (`RenderProp`):
// a belly-sliding penguin, a snowball-fight kid, a snowman builder and Santa's sleigh flyby.
// Everything faces left and travels right → left, like the other helpers. Snow they remove is
// counted in `totals.lostVolume`; debris is purely visual (`orbitRadius = -1`, fades out).

enum PropKind: Int, Sendable, CaseIterable {
    case penguin, kid, kidArm, snowball, splat, sleigh
    case hat, scarf, carrot, coal, stick           // snowman parts
}

/// One sprite to draw, centred on (x, y), `w × h` pt, rotated by `rot` (radians, CCW).
struct RenderProp: Sendable {
    var kind: PropKind
    var x: Float
    var y: Float
    var w: Float
    var h: Float
    var rot: Float = 0
    var alpha: Float = 1
}

enum FunMetrics {
    static let gravity: Float = 900
    static let penguinSize = SIMD2<Float>(92, 46)
    static let penguinSpeed: Float = 210
    static let kidSize = SIMD2<Float>(56, 92)
    static let kidShoulder = SIMD2<Float>(-4, 26)        // relative to the kid sprite centre
    static let armSize = SIMD2<Float>(40, 14)
    static let sleighScale: Float = 0.55
    static let sleighSize = SIMD2<Float>(560, 150) * sleighScale
    static let sleighSpeed: Float = 520
    static let snowmanLife: Float = 55
}

struct SnowmanDecor: Sendable {
    var x: Float
    var baseY: Float
    var radius: Float
    var age: Float = 0
}

struct SplatDecal: Sendable {
    var x: Float
    var y: Float
    var size: Float
    var age: Float = 0
    static let life: Float = 5
}

// MARK: - Shared helpers

extension PhysicsWorld {
    func funGround(at x: Float) -> Float { floorState(at: x)?.surface.topY ?? Float(region.minY) }

    /// Removes `fraction` of the snow depth in a disc (full strength in the core, falling off toward
    /// the rim). Returns the removed volume, which is counted as lost.
    @discardableResult
    func clearDisc(on st: SurfaceState, centerX: Float, radius: Float, fraction: Float) -> Float {
        let local = centerX - st.surface.minX
        let bw = st.field.binWidth
        let lo = st.field.binIndex(atLocalX: local - radius), hi = st.field.binIndex(atLocalX: local + radius)
        guard lo <= hi else { return 0 }
        var removed: Float = 0
        for i in lo...hi {
            let d = abs((Float(i) + 0.5) * bw - local)
            guard d < radius else { continue }
            let u = d / radius
            let w = min(1, fraction * (u < 0.55 ? 1 : (1 - u) / 0.45))
            let h = st.field.height(atBin: i)
            if h > 0 { removed += st.field.melt(bin: i, depth: h * w) * bw }
        }
        if removed > 0 { st.dirty = true; totals.lostVolume += removed }
        return removed
    }

    /// Visual-only spray: fading flakes thrown up and out (no snow volume).
    func funSpray(at pos: SIMD2<Float>, count: Int, speed: ClosedRange<Float>, bias: SIMD2<Float> = .zero) {
        for _ in 0..<count where pool.count < pool.capacity - 40 {
            let ang = rng.float(0.2...2.9)
            let sp = rng.float(speed)
            var p = SnowParticle.blank
            p.position = pos + SIMD2(rng.float(-6...6), rng.float(0...5))
            p.velocity = SIMD2(cos(ang) * sp, sin(ang) * sp) + bias
            p.radius = rng.float(1.4...3.6)
            p.opacity = 0.9; p.mass = 1.2
            p.angularVelocity = rng.float(-5...5)
            p.state = .displaced
            p.orbitRadius = -1
            pool.spawn(p)
        }
    }

    func funSparkle(at pos: SIMD2<Float>) {
        guard pool.count < pool.capacity - 40 else { return }
        var p = SnowParticle.blank
        p.position = pos + SIMD2(rng.float(-6...6), rng.float(-6...6))
        p.velocity = SIMD2(rng.float(-30...30), rng.float(-25...35))
        p.radius = rng.float(1.1...1.7)
        p.mass = rng.float(0.8...1)
        p.baseRadius = rng.float(0.7...1.3)
        p.opacity = p.mass
        p.state = .sparkle
        pool.spawn(p)
    }

    /// Ages decorative leftovers (snowmen, splats). Runs even when no helper is active.
    func stepDecor(dt: Float) {
        if !decals.isEmpty {
            for i in decals.indices { decals[i].age += dt }
            decals.removeAll { $0.age >= SplatDecal.life }
        }
        if !snowmen.isEmpty {
            for i in snowmen.indices { snowmen[i].age += dt }
            snowmen.removeAll { $0.age >= FunMetrics.snowmanLife }
        }
    }

    /// Sprites for everything the fun helpers (and their leftovers) draw, back to front.
    func fillProps(_ out: inout [RenderProp]) {
        for d in decals {
            let a = min(1, (SplatDecal.life - d.age) / 1.5) * 0.92
            out.append(RenderProp(kind: .splat, x: d.x, y: d.y, w: d.size, h: d.size, rot: 0, alpha: a))
        }
        for m in snowmen { snowmanProps(x: m.x, baseY: m.baseY, radius: m.radius, partTime: nil, fade: min(1, (FunMetrics.snowmanLife - m.age) / 6), out: &out) }
        if let p = penguin { out.append(penguinProp(p)) }
        if let b = builder { builderProps(b, &out) }
        if let f = fighter { fighterProps(f, &out) }
        if let s = sleigh {
            out.append(RenderProp(kind: .sleigh, x: s.x, y: s.y, w: FunMetrics.sleighSize.x, h: FunMetrics.sleighSize.y,
                                  rot: s.tilt, alpha: 1))
        }
    }

    /// A kid standing on the floor: body plus a separate arm that can point anywhere (0 = right, π = left).
    /// `crouch` (0...1) squats; `facingRight` mirrors the sprite (the art faces left).
    func kidProps(x: Float, ground: Float, bob: Float = 0, crouch: Float = 0, armAngle: Float,
                  facingRight: Bool = false, out: inout [RenderProp]) {
        let size = FunMetrics.kidSize
        let h = size.y * (1 - 0.14 * crouch)
        out.append(RenderProp(kind: .kid, x: x, y: ground + h / 2 + bob, w: facingRight ? -size.x : size.x, h: h))
        let sh = kidShoulder(x: x, ground: ground, bob: bob, crouch: crouch, facingRight: facingRight)
        let c = sh + SIMD2(cos(armAngle), sin(armAngle)) * (FunMetrics.armSize.x / 2)
        out.append(RenderProp(kind: .kidArm, x: c.x, y: c.y, w: FunMetrics.armSize.x, h: FunMetrics.armSize.y, rot: armAngle))
    }

    func kidShoulder(x: Float, ground: Float, bob: Float = 0, crouch: Float = 0, facingRight: Bool = false) -> SIMD2<Float> {
        let h = FunMetrics.kidSize.y * (1 - 0.14 * crouch)
        return SIMD2(x + FunMetrics.kidShoulder.x * (facingRight ? -1 : 1), ground + bob + h / 2 + FunMetrics.kidShoulder.y * h / FunMetrics.kidSize.y)
    }

    func kidHandWorld(x: Float, ground: Float, bob: Float = 0, crouch: Float = 0, armAngle: Float, facingRight: Bool = false) -> SIMD2<Float> {
        kidShoulder(x: x, ground: ground, bob: bob, crouch: crouch, facingRight: facingRight)
            + SIMD2(cos(armAngle), sin(armAngle)) * (FunMetrics.armSize.x - 4)
    }
}

// MARK: - Penguin

struct PenguinRun {
    var x: Float
    var t: Float = 0
    var sprayAccumulator: Float = 0
}

extension PhysicsWorld {
    func startPenguin() {
        guard !isHelperRunning, !region.isEmpty else { return }
        penguin = PenguinRun(x: Float(region.maxX) + 80)
    }

    func penguinProp(_ p: PenguinRun) -> RenderProp {
        let ground = funGround(at: p.x)
        let size = FunMetrics.penguinSize
        return RenderProp(kind: .penguin, x: p.x, y: ground + size.y / 2 + 1 + abs(sin(p.t * 7)) * 1.5, w: size.x, h: size.y,
                          rot: sin(p.t * 5) * 0.05, alpha: 1)
    }

    func stepPenguin(dt: Float) {
        guard var p = penguin else { return }
        p.t += dt
        let speed = FunMetrics.penguinSpeed * (1 + 0.15 * sin(p.t * 1.7))
        let old = p.x
        p.x -= speed * dt
        if let st = floorState(at: p.x) {
            // The belly ploughs a strip of the floor clear.
            let removed = st.field.sweep(fromLocalX: p.x - 42 - st.surface.minX, toLocalX: old + 42 - st.surface.minX, keepDepth: 1.2)
            if removed > 0 {
                st.dirty = true
                totals.lostVolume += removed
                p.sprayAccumulator += removed / 24
            }
        }
        var n = 0
        while p.sprayAccumulator >= 1, n < 3 {
            p.sprayAccumulator -= 1; n += 1
            funSpray(at: SIMD2(p.x - 36, funGround(at: p.x) + 6), count: 1, speed: 60...200, bias: SIMD2(-speed * 0.25, 40))
        }
        if p.sprayAccumulator > 6 { p.sprayAccumulator = 6 }
        if p.x < Float(region.minX) - 130 {
            penguin = nil
            lastHelperEnd = time
            return
        }
        penguin = p
    }
}

// MARK: - Santa's sleigh flyby

struct SleighRun {
    var x: Float
    var y: Float
    var t: Float = 0
    var tilt: Float = 0
    var sparkleAccumulator: Float = 0
    var sprayAccumulator: Float = 0
}

extension PhysicsWorld {
    func startSleigh() {
        guard !isHelperRunning, !region.isEmpty else { return }
        let k = FunMetrics.sleighScale
        let top = Float(region.maxY) - 120
        sleigh = SleighRun(x: Float(region.maxX) + 330 * k, y: top)
    }

    func stepSleigh(dt: Float) {
        guard var s = sleigh else { return }
        s.t += dt
        let k = FunMetrics.sleighScale
        s.x -= FunMetrics.sleighSpeed * dt
        // Fly low enough to dip over the tallest thing under the sleigh so the downdraught reaches the snow.
        var maxTop = Float(region.minY)
        // Looks ~1000 pt ahead (about 2 s of flight) so it climbs in time.
        for st in ordered where st.surface.maxX > s.x - 1000 && st.surface.minX < s.x + 300 { maxTop = max(maxTop, st.surface.topY) }
        let desired = min(max(maxTop + 110 + 25 * sin(s.t * 2.2), Float(region.minY) + 110), Float(region.maxY) - 90)
        let oldY = s.y
        s.y += (desired - s.y) * min(1, 2.2 * dt)
        s.tilt = min(max((s.y - oldY) / max(dt, 1e-4) * 0.0008, -0.12), 0.12)

        // Downdraught: snow on surfaces beneath the sleigh is blown off, strongest when close.
        let belly = s.y - 40 * k
        for st in ordered where st.surface.maxX > s.x - 90 && st.surface.minX < s.x + 90 {
            let cx = min(max(s.x, st.surface.minX), st.surface.maxX)
            let top = st.surface.topY(atX: cx)
            let gap = belly - top
            guard gap > 0, gap < 200 else { continue }
            let strength = 1 - gap / 200
            let removed = clearDisc(on: st, centerX: cx, radius: 90, fraction: 6 * strength * dt)
            s.sprayAccumulator += removed / 30
        }
        var n = 0
        while s.sprayAccumulator >= 1, n < 4 {
            s.sprayAccumulator -= 1; n += 1
            funSpray(at: SIMD2(s.x + rng.float(-80...80), belly - 90 + rng.float(0...30)), count: 1, speed: 100...300, bias: SIMD2(-FunMetrics.sleighSpeed * 0.2, 0))
        }
        if s.sprayAccumulator > 8 { s.sprayAccumulator = 8 }

        // Wake: airborne flakes near the sleigh are thrown out of its path and dragged along behind it.
        let wakeCenter = SIMD2(s.x + 60 * k, s.y - 20 * k)
        let reach: Float = 230 * k + 20
        for i in 0..<pool.count {
            var p = pool[i]
            guard p.state == .falling || p.state == .disturbed, p.orbitRadius >= 0 else { continue }
            let d = p.position - wakeCenter
            let dist = simd_length(d)
            guard dist < reach else { continue }
            let dir: SIMD2<Float> = dist > 1e-3 ? d / dist : SIMD2(0, 1)
            let k = 1 - dist / reach
            p.velocity += (dir * 1500 * k + SIMD2(-300, 0) * k) * dt
            p.state = .disturbed; p.stateTime = 0
            pool[i] = p
        }

        // Glitter trail behind the sleigh.
        s.sparkleAccumulator += 120 * dt
        n = 0
        while s.sparkleAccumulator >= 1, n < 4 {
            s.sparkleAccumulator -= 1; n += 1
            funSparkle(at: SIMD2(s.x + 250 * k, s.y - 30 * k))
        }

        if s.x < Float(region.minX) - 340 * k {
            sleigh = nil
            lastHelperEnd = time
            return
        }
        sleigh = s
    }
}
