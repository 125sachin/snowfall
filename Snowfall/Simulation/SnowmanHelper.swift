import Foundation
import simd

/// Where each piece of a snowman sits, in points relative to the bottom centre of the base ball, for a
/// base radius `R`. (Design: base r = 50, middle r = 35, head r = 25, scaled by `R / 50`.)
enum SnowmanLayout {
    struct Part {
        let kind: PropKind
        let offset: SIMD2<Float>
        let size: SIMD2<Float>
        let rot: Float
        let start: Float      // seconds into the decorating phase at which it is thrown on
        let flight: Float
    }

    static func centers(radius R: Float) -> (base: SIMD2<Float>, mid: SIMD2<Float>, head: SIMD2<Float>) {
        let s = R / 50
        return (SIMD2(0, 50 * s), SIMD2(0, 127 * s), SIMD2(0, 179 * s))
    }

    /// Time at which the last part has landed.
    static let decorTime: Float = 5.2

    /// Coal eyes, carrot nose, coal mouth, buttons, scarf, hat and twig arms, in the order they are put on.
    static func parts(radius R: Float) -> [Part] {
        let s = R / 50
        var out: [Part] = []
        func add(_ kind: PropKind, _ x: Float, _ y: Float, _ w: Float, _ h: Float, rot: Float = 0, start: Float, flight: Float) {
            out.append(Part(kind: kind, offset: SIMD2(x, y) * s, size: SIMD2(w, h) * s, rot: rot, start: start, flight: flight))
        }
        add(.coal, -12, 184, 6, 6, start: 0.0, flight: 0.3)
        add(.coal, 6, 184, 6, 6, start: 0.3, flight: 0.3)
        add(.carrot, -17, 177, 30, 9, start: 0.7, flight: 0.4)
        let mouth: [(Float, Float)] = [(-14, 168), (-8, 165.5), (-2, 164.5), (4, 165.5), (10, 168)]
        for (i, p) in mouth.enumerated() { add(.coal, p.0, p.1, 3.4, 3.4, start: 1.2 + 0.12 * Float(i), flight: 0.25) }
        for (i, y) in [Float(143), 127, 111].enumerated() { add(.coal, 0, y, 6.5, 6.5, start: 1.9 + 0.25 * Float(i), flight: 0.3) }
        add(.scarf, 0, 135, 64, 44, start: 2.9, flight: 0.5)
        add(.hat, 0, 218, 52, 38, start: 3.6, flight: 0.7)
        add(.stick, -48, 148, 51, 8, rot: 2.46, start: 4.4, flight: 0.45)
        add(.stick, 48, 144, 47, 8, rot: 0.54, start: 4.7, flight: 0.45)
        return out
    }
}

struct BuilderRun {
    enum Phase { case rolling, packMid, liftMid, packHead, liftHead, decorating, waving, leaving }
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
    var packR: Float = 0                 // radius of the ball being packed or lifted
    var packPos = SIMD2<Float>.zero      // its centre
    var liftFrom = SIMD2<Float>.zero
    var midDone = false
    var headDone = false
    static let rollSpeed: Float = 85
    static let packMidTime: Float = 1.7, packHeadTime: Float = 1.4
    static let liftMidTime: Float = 0.9, liftHeadTime: Float = 0.8
    static let waveTime: Float = 1.4

    var crouch: Float {
        switch phase {
        case .packMid, .packHead: return 0.5 + 0.5 * sin(phaseTime * 7)
        default: return 0
        }
    }
    var armAngle: Float {
        switch phase {
        case .rolling: return -2.4 + 0.1 * sin(t * 6)             // pushing the ball ahead (to the left)
        case .packMid, .packHead: return -2.0 + 0.5 * sin(phaseTime * 7)   // patting the snow into a ball
        case .liftMid, .liftHead: return 2.3                        // heaving it up
        case .decorating: return 1.5 + 0.5 * sin(phaseTime * 9)     // tossing things up onto the snowman
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
        builder = BuilderRun(kidX: bx + 14 + 34, ballX: bx, stopX: Float(region.minX))
    }

    /// Balls and parts of one snowman. `partTime` nil = finished; otherwise the time since decorating began
    /// (parts fly from the kid's hand to their places).
    func snowmanProps(x: Float, baseY: Float, radius R: Float, partTime: Float?, fade: Float = 1,
                      hand: SIMD2<Float> = .zero, includeBalls: [Bool] = [true, true, true], out: inout [RenderProp]) {
        let sag = 0.85 + 0.15 * fade                       // sags as it melts
        let c = SnowmanLayout.centers(radius: R)
        func ball(_ center: SIMD2<Float>, _ r: Float) {
            out.append(RenderProp(kind: .snowball, x: x + center.x, y: baseY + center.y * sag, w: 2 * r, h: 2 * r * sag, rot: 0, alpha: fade))
        }
        if includeBalls[0] { ball(c.base, R) }
        if includeBalls[1] { ball(c.mid, 0.7 * R) }
        if includeBalls[2] { ball(c.head, 0.5 * R) }
        for part in SnowmanLayout.parts(radius: R) {
            let target = SIMD2(x + part.offset.x, baseY + part.offset.y * sag)
            var pos = target, rot = part.rot, alpha = fade
            if let te = partTime?.advanced(by: -part.start) {
                if te < 0 { continue }
                if te < part.flight {
                    let u = te / part.flight
                    pos = hand + (target - hand) * u + SIMD2(0, 45 * sin(.pi * u))
                    if part.kind == .hat { rot = part.rot + 5 * (1 - u) }
                    alpha = fade * min(1, u * 4)
                }
            }
            out.append(RenderProp(kind: part.kind, x: pos.x, y: pos.y, w: part.size.x, h: part.size.y * sag, rot: rot, alpha: alpha))
        }
    }

    func builderProps(_ b: BuilderRun, _ out: inout [RenderProp]) {
        let ground = funGround(at: b.kidX)
        let bob = b.phase == .rolling || b.phase == .leaving ? abs(sin(b.t * 8)) * 2 : 0
        func ball(_ p: SIMD2<Float>, _ r: Float, rot: Float = 0) {
            out.append(RenderProp(kind: .snowball, x: p.x, y: p.y, w: 2 * r, h: 2 * r, rot: rot))
        }
        switch b.phase {
        case .rolling:
            ball(SIMD2(b.ballX, ground + b.ballR), b.ballR, rot: b.rollAngle)
        case .packMid, .liftMid, .packHead, .liftHead, .decorating:
            let base = funGround(at: b.snowmanX)
            let c = SnowmanLayout.centers(radius: b.snowmanR)
            ball(SIMD2(b.snowmanX, base + c.base.y), b.snowmanR)
            if b.midDone { ball(SIMD2(b.snowmanX, base + c.mid.y), 0.7 * b.snowmanR) }
            if b.headDone { ball(SIMD2(b.snowmanX, base + c.head.y), 0.5 * b.snowmanR) }
            if b.phase == .packMid || b.phase == .liftMid || b.phase == .packHead || b.phase == .liftHead { ball(b.packPos, b.packR) }
            if b.phase == .decorating {
                // Parts only (the three balls were drawn above).
                let hand = kidHandWorld(x: b.kidX, ground: ground, armAngle: 1.4)
                snowmanProps(x: b.snowmanX, baseY: base, radius: b.snowmanR, partTime: b.phaseTime, hand: hand,
                             includeBalls: [false, false, false], out: &out)
            }
        case .waving, .leaving:
            break                                   // the finished snowman is a lingering `SnowmanDecor`
        }
        kidProps(x: b.kidX, ground: ground, bob: bob, crouch: b.crouch, armAngle: b.armAngle, out: &out)
    }

    /// Scoops the snow on the floor near `x` into the ball (the volume is counted as removed).
    private func scoopFloor(near x: Float, halfWidth: Float) {
        guard let st = floorState(at: x) else { return }
        let removed = st.field.sweep(fromLocalX: x - halfWidth - st.surface.minX, toLocalX: x + halfWidth - st.surface.minX, keepDepth: 0.3)
        if removed > 0 { st.dirty = true; totals.lostVolume += removed }
    }

    func stepBuilder(dt: Float) {
        guard var b = builder else { return }
        b.t += dt
        b.phaseTime += dt
        func ease(_ u: Float) -> Float { let c = min(max(u, 0), 1); return c * c * (3 - 2 * c) }
        let standX = { (b: BuilderRun) in b.snowmanX + b.snowmanR + 62 }
        let ground = funGround(at: b.snowmanX)
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
                b.snowmanX = b.ballX
                b.snowmanR = max(b.ballR, 30)
                b.phase = .packMid; b.phaseTime = 0
                b.packR = 6
            }
        case .packMid, .packHead:
            let isMid = b.phase == .packMid
            let total = isMid ? BuilderRun.packMidTime : BuilderRun.packHeadTime
            let target = (isMid ? 0.7 : 0.5) * b.snowmanR
            b.kidX += (standX(b) - b.kidX) * min(1, 5 * dt)
            b.packR = 6 + (target - 6) * ease(b.phaseTime / total)
            b.packPos = SIMD2(b.kidX - 46, ground + b.packR)
            scoopFloor(near: b.packPos.x, halfWidth: 34)
            if b.phaseTime >= total {
                b.liftFrom = b.packPos
                b.phase = isMid ? .liftMid : .liftHead; b.phaseTime = 0
            }
        case .liftMid, .liftHead:
            let isMid = b.phase == .liftMid
            let total = isMid ? BuilderRun.liftMidTime : BuilderRun.liftHeadTime
            let c = SnowmanLayout.centers(radius: b.snowmanR)
            let dest = SIMD2(b.snowmanX, ground + (isMid ? c.mid.y : c.head.y))
            let u = min(b.phaseTime / total, 1)
            b.packPos = b.liftFrom + (dest - b.liftFrom) * ease(u) + SIMD2(0, 70 * sin(.pi * u))
            if u >= 1 {
                funSpray(at: dest + SIMD2(0, -b.packR), count: 10, speed: 60...180)       // a puff as it settles
                if isMid { b.midDone = true; b.phase = .packHead } else { b.headDone = true; b.phase = .decorating }
                b.phaseTime = 0
                b.packR = 6
            }
        case .decorating:
            b.kidX += (standX(b) - b.kidX) * min(1, 5 * dt)
            if b.phaseTime >= SnowmanLayout.decorTime {
                snowmen.removeAll { abs($0.x - b.snowmanX) < 160 }          // never two on top of each other
                if snowmen.count >= 3 { snowmen.removeFirst() }
                snowmen.append(SnowmanDecor(x: b.snowmanX, baseY: ground, radius: b.snowmanR))
                b.phase = .waving; b.phaseTime = 0
            }
        case .waving:
            if b.phaseTime >= BuilderRun.waveTime { b.phase = .leaving; b.phaseTime = 0 }
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
