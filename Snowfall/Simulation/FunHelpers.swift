import Foundation
import simd

// Four lighter-weight snow helpers that share one generic sprite type (`RenderProp`):
// a belly-sliding penguin, a snowball-fight kid, a snowman builder and Santa's sleigh flyby.
// Everything faces left and travels right → left, like the other helpers. Snow they remove is
// counted in `totals.lostVolume`; debris is purely visual (`orbitRadius = -1`, fades out).

enum PropKind: Int, Sendable, CaseIterable {
    case penguin, kid, kidArm, snowball, splat, snowman, sleigh
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
    /// Snowman sprite box for a base ball of diameter 100 (design units).
    static let snowmanBox = SIMD2<Float>(160, 250)
    static let snowmanMidY: Float = 127, snowmanHeadY: Float = 179
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
        for m in snowmen { out.append(snowmanProp(m)) }
        if let p = penguin { out.append(penguinProp(p)) }
        if let b = builder { builderProps(b, &out) }
        if let f = fighter { fighterProps(f, &out) }
        if let s = sleigh {
            out.append(RenderProp(kind: .sleigh, x: s.x, y: s.y, w: FunMetrics.sleighSize.x, h: FunMetrics.sleighSize.y,
                                  rot: s.tilt, alpha: 1))
        }
    }

    fileprivate func snowmanProp(_ m: SnowmanDecor) -> RenderProp {
        let s = 2 * m.radius / 100
        let fade = min(1, (FunMetrics.snowmanLife - m.age) / 6)
        let w = FunMetrics.snowmanBox.x * s, h = FunMetrics.snowmanBox.y * s * (0.82 + 0.18 * fade)   // sags as it melts
        return RenderProp(kind: .snowman, x: m.x, y: m.baseY + h / 2, w: w, h: h, rot: 0, alpha: fade)
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

    fileprivate func penguinProp(_ p: PenguinRun) -> RenderProp {
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

    fileprivate func fighterProps(_ f: FighterRun, _ out: inout [RenderProp]) {
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
    private func pickTarget(from hand: SIMD2<Float>, kidX: Float, ground: Float) -> (FlyingSnowball.Hit, SIMD2<Float>, String?) {
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

    private func splat(_ b: FlyingSnowball) {
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

// MARK: - Snowman builder

struct BuilderRun {
    enum Phase { case rolling, building, waving, leaving }
    var phase: Phase = .rolling
    var t: Float = 0
    var phaseTime: Float = 0
    var kidX: Float
    var ballX: Float
    var ballR: Float = 14
    var collected: Float = 0
    var rollAngle: Float = 0
    var stopX: Float
    var snowmanX: Float = 0
    var snowmanR: Float = 0
    static let rollSpeed: Float = 85
    /// Time into `.building` at which the middle ball, the head and the finished figure appear.
    static let midAt: Float = 0.6, headAt: Float = 1.6, doneAt: Float = 2.6, buildEnd: Float = 3.4

    var armAngle: Float {
        switch phase {
        case .rolling: return -2.4 + 0.1 * sin(t * 6)            // pushing the ball ahead (to the left)
        case .building: return -1.4
        case .waving: return 1.2 + 0.5 * sin(phaseTime * 9)
        case .leaving: return -1.5
        }
    }
}

extension PhysicsWorld {
    func startBuilder() {
        guard !isHelperRunning, !region.isEmpty else { return }
        let bx = Float(region.maxX) + 40
        // The snowman is built in the bottom-left corner: the ball is rolled all the way across.
        let stop = Float(region.minX)
        builder = BuilderRun(kidX: bx + 14 + 34, ballX: bx, stopX: stop)
    }

    fileprivate func builderProps(_ b: BuilderRun, _ out: inout [RenderProp]) {
        let ground = funGround(at: b.kidX)
        let kid = FunMetrics.kidSize
        let bob = b.phase == .building || b.phase == .waving ? 0 : abs(sin(b.t * 8)) * 2
        func ball(_ x: Float, _ y: Float, _ d: Float, rot: Float = 0, alpha: Float = 1) {
            out.append(RenderProp(kind: .snowball, x: x, y: y, w: d, h: d, rot: rot, alpha: alpha))
        }
        switch b.phase {
        case .rolling:
            ball(b.ballX, ground + b.ballR, b.ballR * 2, rot: b.rollAngle)
        case .building, .waving, .leaving:
            if b.phase == .building {
                let s = 2 * b.snowmanR / 100
                let base = funGround(at: b.snowmanX)
                let pop: (Float) -> Float = { u in min(max(u, 0), 1) }
                let finished = pop((b.phaseTime - BuilderRun.doneAt) / 0.7)
                if finished < 1 {
                    ball(b.snowmanX, base + b.snowmanR, b.snowmanR * 2)
                    let mu = pop((b.phaseTime - BuilderRun.midAt) / 0.4)
                    if mu > 0 { ball(b.snowmanX, base + FunMetrics.snowmanMidY * s, 70 * s * mu) }
                    let hu = pop((b.phaseTime - BuilderRun.headAt) / 0.4)
                    if hu > 0 { ball(b.snowmanX, base + FunMetrics.snowmanHeadY * s, 50 * s * hu) }
                }
                if finished > 0 {
                    let w = FunMetrics.snowmanBox.x * s, h = FunMetrics.snowmanBox.y * s
                    out.append(RenderProp(kind: .snowman, x: b.snowmanX, y: base + h / 2, w: w, h: h, rot: 0, alpha: finished))
                }
            }
        }
        out.append(RenderProp(kind: .kid, x: b.kidX, y: ground + kid.y / 2 + bob, w: kid.x, h: kid.y))
        let a = b.armAngle
        let sh = SIMD2(b.kidX + FunMetrics.kidShoulder.x, ground + bob + kid.y / 2 + FunMetrics.kidShoulder.y)
        let c = sh + SIMD2(cos(a), sin(a)) * (FunMetrics.armSize.x / 2)
        out.append(RenderProp(kind: .kidArm, x: c.x, y: c.y, w: FunMetrics.armSize.x, h: FunMetrics.armSize.y, rot: a))
    }

    func stepBuilder(dt: Float) {
        guard var b = builder else { return }
        b.t += dt
        b.phaseTime += dt
        switch b.phase {
        case .rolling:
            let old = b.ballX
            b.ballX -= BuilderRun.rollSpeed * dt
            b.rollAngle += BuilderRun.rollSpeed * dt / b.ballR            // rolls to the left (CCW)
            b.kidX = b.ballX + b.ballR + 34
            // The ball picks up everything under it, so it grows as it goes.
            if let st = floorState(at: b.ballX) {
                let removed = st.field.sweep(fromLocalX: b.ballX - b.ballR - st.surface.minX, toLocalX: old + b.ballR - st.surface.minX, keepDepth: 0.4)
                if removed > 0 {
                    st.dirty = true
                    totals.lostVolume += removed
                    b.collected += removed
                    b.ballR = min(58, (14 * 14 + b.collected * 0.9 / Float.pi).squareRoot())
                }
            }
            // Stop once the finished snowman (arms included, ~1.6 radii each side) would touch the left edge.
            if b.ballX <= max(b.stopX + max(b.ballR, 28) * 1.6 + 6, b.stopX) {
                b.phase = .building; b.phaseTime = 0
                b.snowmanX = b.ballX
                b.snowmanR = max(b.ballR, 28)
            }
        case .building:
            b.kidX += (b.snowmanX + b.snowmanR + 70 - b.kidX) * min(1, 3 * dt)   // steps back to admire
            if b.phaseTime >= BuilderRun.buildEnd {
                if snowmen.count >= 3 { snowmen.removeFirst() }
                snowmen.append(SnowmanDecor(x: b.snowmanX, baseY: funGround(at: b.snowmanX), radius: b.snowmanR))
                b.phase = .waving; b.phaseTime = 0
            }
        case .waving:
            if b.phaseTime >= 1.3 { b.phase = .leaving; b.phaseTime = 0 }
        case .leaving:
            b.kidX -= 120 * dt
            if b.kidX < Float(region.minX) - 90 {
                builder = nil
                lastHelperEnd = time
                return
            }
        }
        builder = b
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
