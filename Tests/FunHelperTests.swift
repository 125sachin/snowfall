import XCTest
import simd
@testable import Snowfall

final class FunHelperTests: XCTestCase {
    private func world(width: CGFloat = 2400, floorSnow: Float = 12, windowSnow: Float = 0, kind: HelperKind, seed: UInt64 = 1) -> (PhysicsWorld, SurfaceState, SurfaceState?) {
        var c = SimulationConfiguration(); c.density = 0; c.plowAuto = false; c.helper = kind; c.windStrength = 0; c.turbulence = 0; c.seed = seed
        let w = PhysicsWorld(config: c)
        w.setRegion(CGRect(x: 0, y: 0, width: width, height: 900))
        var surfaces = [CollisionSurface(id: "floor", frame: CGRect(x: 0, y: 0, width: width, height: 0), velocity: .zero, kind: .displayBottom)]
        if windowSnow > 0 {
            surfaces.append(CollisionSurface(id: "win", frame: CGRect(x: 700, y: 200, width: 700, height: 300), velocity: .zero, kind: .windowTop, zRank: 0))
        }
        w.setSurfaces(surfaces)
        let floor = w.state(forSurface: "floor")!
        for i in 0..<floor.field.binCount { floor.field.add(volume: floorSnow * floor.field.binWidth, toBin: i) }
        var win: SurfaceState?
        if windowSnow > 0 {
            win = w.state(forSurface: "win")!
            for i in 0..<win!.field.binCount { win!.field.add(volume: windowSnow * win!.field.binWidth, toBin: i) }
        }
        return (w, floor, win)
    }

    @discardableResult
    private func run(_ w: PhysicsWorld, maxSeconds: Float = 90) -> Float {
        var t: Float = 0
        while w.isHelperRunning && t < maxSeconds { w.step(dt: 1.0 / 120); w.finishFrame(); t += 1.0 / 120 }
        return t
    }

    private func settled(_ w: PhysicsWorld) -> Float { w.ordered.reduce(0) { $0 + $1.field.volume } }

    // MARK: Registry

    func testAllNewHelpersAreRegisteredWithText() {
        for k in [HelperKind.penguin, .snowballFight, .snowman, .sleigh] {
            XCTAssertTrue(HelperKind.concrete.contains(k))
            XCTAssertFalse(k.label.isEmpty); XCTAssertFalse(k.shortLabel.isEmpty); XCTAssertFalse(k.summary.isEmpty)
        }
    }

    func testOnlyOneHelperAtATime() {
        let (w, _, _) = world(kind: .penguin)
        w.startHelper(.penguin)
        w.startHelper(.sleigh); w.startHelper(.snowman); w.startHelper(.snowballFight); w.startHelper(.jcb)
        XCTAssertNotNil(w.penguin)
        XCTAssertNil(w.sleigh); XCTAssertNil(w.builder); XCTAssertNil(w.fighter); XCTAssertNil(w.plow)
    }

    func testEligibilityFloorOnlyHelpersNeedFloorSnow() {
        let (w, _, _) = world(floorSnow: 0, windowSnow: 20, kind: .penguin)
        let e = w.eligibleHelpers()
        XCTAssertFalse(e.contains(.penguin)); XCTAssertFalse(e.contains(.snowman)); XCTAssertFalse(e.contains(.jcb))
        XCTAssertTrue(e.contains(.sleigh)); XCTAssertTrue(e.contains(.snowballFight))
    }

    // MARK: Penguin

    func testPenguinSlidesLeftAndClearsAStrip() {
        let (w, floor, _) = world(kind: .penguin)
        let before = floor.field.volume
        w.startHelper(.penguin)
        let startX = w.penguin!.x
        var prev = startX
        for _ in 0..<(120 * 4) {
            w.step(dt: 1.0 / 120)
            if let p = w.penguin { XCTAssertLessThanOrEqual(p.x, prev + 0.001); prev = p.x }
        }
        XCTAssertLessThan(prev, startX - 600)
        run(w)
        XCTAssertNil(w.penguin)
        XCTAssertLessThan(floor.field.volume, before * 0.2, "the belly ploughs the floor clear")
        XCTAssertEqual(before - floor.field.volume, w.totals.lostVolume, accuracy: before * 0.03, "removed snow is accounted for")
    }

    // MARK: Snowball fight

    func testFighterThrowsBallsThatSplatOnWindows() {
        let (w, _, win) = world(windowSnow: 2, kind: .snowballFight, seed: 3)
        w.startHelper(.snowballFight)
        var sawBall = false
        var left = w.fighter!.x
        for _ in 0..<(120 * 40) {
            w.step(dt: 1.0 / 120); w.finishFrame()
            if let f = w.fighter { sawBall = sawBall || !f.balls.isEmpty; XCTAssertLessThanOrEqual(f.x, left + 0.001); left = f.x }
        }
        XCTAssertTrue(sawBall)
        XCTAssertNotNil(win)
        run(w)
        XCTAssertNil(w.fighter)
        XCTAssertLessThanOrEqual(w.decals.count, 24)
    }

    func testSnowballsLandOnTheirTarget() {
        let (w, _, _) = world(windowSnow: 2, kind: .snowballFight, seed: 5)
        w.startHelper(.snowballFight)
        var checked = 0
        for _ in 0..<(120 * 30) {
            w.step(dt: 1.0 / 120)
            guard let f = w.fighter else { break }
            for b in f.balls where b.age > b.flight - 0.009 && b.age < b.flight {
                XCTAssertEqual(simd_length(b.pos - b.target), 0, accuracy: 20, "ballistic aim reaches the target")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0)
    }

    func testSnowballBlastsAPile() {
        let (w, _, win) = world(floorSnow: 0, windowSnow: 25, kind: .snowballFight, seed: 2)
        let before = win!.field.volume
        w.startHelper(.snowballFight)
        run(w)
        XCTAssertLessThan(win!.field.volume, before, "piles that get hit lose snow")
        for _ in 0..<(120 * 20) { w.step(dt: 1.0 / 120); w.finishFrame() }     // let shed snow land
        let t = w.totals
        XCTAssertEqual(settled(w) + t.lostVolume + t.clippedVolume + t.droppedVolume, before, accuracy: before * 0.04, "volume is conserved")
    }

    func testSplatsFadeAway() {
        let (w, _, _) = world(windowSnow: 2, kind: .snowballFight, seed: 4)
        w.startHelper(.snowballFight)
        run(w)
        for _ in 0..<(120 * 7) { w.step(dt: 1.0 / 120) }
        XCTAssertTrue(w.decals.isEmpty)
    }

    // MARK: Snowman builder

    func testBuilderRollsLeftGrowsAndLeavesASnowman() {
        let (w, floor, _) = world(floorSnow: 14, kind: .snowman)
        let before = floor.field.volume
        w.startHelper(.snowman)
        var maxR: Float = 0
        var prevBall = w.builder!.ballX
        for _ in 0..<(120 * 60) {
            w.step(dt: 1.0 / 120); w.finishFrame()
            guard let b = w.builder else { break }
            maxR = max(maxR, b.ballR)
            if b.phase == .rolling { XCTAssertLessThanOrEqual(b.ballX, prevBall + 0.001); prevBall = b.ballX }
        }
        run(w)
        XCTAssertNil(w.builder)
        XCTAssertGreaterThan(maxR, 30, "the ball grows as it picks up snow")
        XCTAssertEqual(w.snowmen.count, 1)
        XCTAssertLessThan(w.snowmen[0].x, 170, "built in the leftmost corner")
        XCTAssertGreaterThan(w.snowmen[0].x, w.snowmen[0].radius * 1.6 - 1, "but fully on screen")
        XCTAssertLessThan(floor.field.volume, before)
        XCTAssertEqual(before - floor.field.volume, w.totals.lostVolume, accuracy: before * 0.03)
    }

    func testSnowmanMeltsAwayEventually() {
        let (w, _, _) = world(floorSnow: 14, kind: .snowman)
        w.startHelper(.snowman)
        run(w)
        XCTAssertEqual(w.snowmen.count, 1)
        for _ in 0..<(120 * Int(FunMetrics.snowmanLife + 2)) { w.step(dt: 1.0 / 120) }
        XCTAssertTrue(w.snowmen.isEmpty)
    }

    func testAtMostThreeSnowmenStay() {
        let (w, floor, _) = world(floorSnow: 14, kind: .snowman)
        for _ in 0..<4 {
            for i in 0..<floor.field.binCount { floor.field.add(volume: 14 * floor.field.binWidth, toBin: i) }
            w.startHelper(.snowman)
            run(w)
        }
        XCTAssertLessThanOrEqual(w.snowmen.count, 3)
    }

    // MARK: Sleigh

    func testSleighFliesLeftAndBlowsSnowOffSurfacesBelow() {
        let (w, floor, win) = world(floorSnow: 6, windowSnow: 20, kind: .sleigh)
        let before = floor.field.volume + win!.field.volume
        w.startHelper(.sleigh)
        var prev = w.sleigh!.x
        for _ in 0..<(120 * 3) {
            w.step(dt: 1.0 / 120)
            if let s = w.sleigh { XCTAssertLessThan(s.x, prev); prev = s.x }
        }
        run(w)
        XCTAssertNil(w.sleigh)
        let after = floor.field.volume + win!.field.volume
        XCTAssertLessThan(after, before * 0.9, "the downdraught clears some snow")
        for _ in 0..<(120 * 20) { w.step(dt: 1.0 / 120); w.finishFrame() }     // let shed snow land
        let t = w.totals
        XCTAssertEqual(settled(w) + t.lostVolume + t.clippedVolume + t.droppedVolume, before, accuracy: before * 0.04, "volume is conserved")
    }

    func testSleighDipsOverTheTallestWindow() {
        let (w, _, _) = world(floorSnow: 2, windowSnow: 2, kind: .sleigh)
        w.startHelper(.sleigh)
        var minGap = Float.infinity
        for _ in 0..<(120 * 8) {
            w.step(dt: 1.0 / 120)
            if let s = w.sleigh, s.x > 700, s.x < 1400 { minGap = min(minGap, s.y - 500) }
        }
        XCTAssertGreaterThan(minGap, 60, "never flies through a window")
    }

    func testSleighStirsUpAirborneFlakes() {
        let (w, _, _) = world(floorSnow: 0, kind: .sleigh)
        var s = SnowParticle.blank
        s.position = SIMD2(1560, 720); s.velocity = SIMD2(0, -30); s.mass = 1; s.volume = 4
        w.pool.spawn(s)
        w.startHelper(.sleigh)
        w.sleigh!.x = 1620; w.sleigh!.y = 760
        for _ in 0..<60 { w.step(dt: 1.0 / 120) }
        let p = w.pool[0]
        XCTAssertGreaterThan(simd_length(p.velocity - SIMD2(0, -30)), 30, "the wake pushes nearby flakes")
    }

    // MARK: Drawing data

    func testPropsAreEmittedWhileRunningAndEmptyAfter() {
        for kind in [HelperKind.penguin, .snowballFight, .snowman, .sleigh] {
            let (w, _, _) = world(windowSnow: 5, kind: kind)
            w.startHelper(kind)
            for _ in 0..<120 { w.step(dt: 1.0 / 120) }
            var snap = RenderSnapshot()
            w.fill(snapshot: &snap, showSurfaces: false, stats: SimulationStats())
            XCTAssertFalse(snap.props.isEmpty, "\(kind) draws something")
            for p in snap.props { XCTAssertTrue(p.x.isFinite && p.y.isFinite && p.w > 0 && p.h > 0) }
        }
        let (w, _, _) = world(kind: .penguin)
        var snap = RenderSnapshot()
        w.fill(snapshot: &snap, showSurfaces: false, stats: SimulationStats())
        XCTAssertTrue(snap.props.isEmpty)
    }
}
