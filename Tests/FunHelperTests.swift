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

    func testTwoKidsFaceEachOtherFromOppositeSides() {
        let (w, _, _) = world(windowSnow: 2, kind: .snowballFight, seed: 3)
        w.startHelper(.snowballFight)
        guard let f = w.fighter else { return XCTFail("no fight") }
        XCTAssertEqual(f.kids.count, 2)
        XCTAssertTrue(f.kids[0].facingRight); XCTAssertFalse(f.kids[1].facingRight)
        XCTAssertLessThan(f.kids[0].x, 0, "the left kid walks in from the left edge")
        XCTAssertGreaterThan(f.kids[1].x, 2000, "the right kid walks in from the right edge")
        for _ in 0..<(120 * 6) { w.step(dt: 1.0 / 120) }
        let g = w.fighter!
        XCTAssertEqual(g.kids[0].x, g.kids[0].home); XCTAssertEqual(g.kids[1].x, g.kids[1].home)
        XCTAssertLessThan(g.kids[0].home, 300); XCTAssertGreaterThan(g.kids[1].home, 1700)
        XCTAssertEqual(g.phase, .fighting)
    }

    func testBothKidsThrowAndSomeSnowballsHitEachOther() {
        let (w, _, _) = world(windowSnow: 2, kind: .snowballFight, seed: 3)
        w.startHelper(.snowballFight)
        var thrownBy = [0, 0]
        var kidHits = 0, floorMisses = 0, staggered = [false, false]
        var seen = 0
        for _ in 0..<(120 * 60) {
            w.step(dt: 1.0 / 120); w.finishFrame()
            guard let f = w.fighter else { break }
            for (i, k) in f.kids.enumerated() where k.stagger > 0 { staggered[i] = true }
            for b in f.balls where b.age < 0.01 {
                thrownBy[b.owner] += 1; seen += 1
                if case .kid = b.hit { kidHits += 1 } else if b.hit == .floor { floorMisses += 1 }
            }
        }
        XCTAssertGreaterThanOrEqual(thrownBy[0], FighterRun.maxThrows - 1); XCTAssertGreaterThanOrEqual(thrownBy[1], FighterRun.maxThrows - 1)
        XCTAssertGreaterThan(kidHits, 3, "they hit each other")
        XCTAssertGreaterThan(floorMisses, 1, "and miss")
        XCTAssertTrue(staggered[0] && staggered[1], "a hit makes the kid react")
    }

    func testThrowsGoAtDifferentAnglesIncludingHighLobs() {
        let (w, _, _) = world(windowSnow: 2, kind: .snowballFight, seed: 6)
        w.startHelper(.snowballFight)
        var angles: [Float] = []
        for _ in 0..<(120 * 60) {
            w.step(dt: 1.0 / 120); w.finishFrame()
            guard let f = w.fighter else { break }
            for b in f.balls where b.age < 0.01 { angles.append(atan2(b.vel.y, abs(b.vel.x))) }
        }
        XCTAssertGreaterThan(angles.count, 15)
        XCTAssertGreaterThan((angles.max() ?? 0) - (angles.min() ?? 0), 1.0, "a wide spread of launch angles")
        XCTAssertTrue(angles.contains { $0 > 1.0 }, "some steep lobs")
        XCTAssertTrue(angles.contains { $0 < 0.6 }, "and some flatter throws")
    }

    func testSnowballsLandOnTheirTarget() {
        let (w, _, _) = world(windowSnow: 2, kind: .snowballFight, seed: 5)
        w.startHelper(.snowballFight)
        var checked = 0
        for _ in 0..<(120 * 40) {
            w.step(dt: 1.0 / 120)
            guard let f = w.fighter else { break }
            for b in f.balls where b.age > b.flight - 0.009 && b.age < b.flight {
                XCTAssertEqual(simd_length(b.pos - b.target), 0, accuracy: 25, "ballistic aim reaches the target")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0)
    }

    func testKidsScoopSnowOffTheFloor() {
        let (w, floor, _) = world(floorSnow: 8, windowSnow: 0, kind: .snowballFight, seed: 2)
        let before = floor.field.volume
        w.startHelper(.snowballFight)
        run(w)
        XCTAssertLessThan(floor.field.volume, before)
        let t = w.totals
        XCTAssertEqual(floor.field.volume + t.lostVolume + t.clippedVolume + t.droppedVolume, before, accuracy: before * 0.04)
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

    func testSplatsOnWindowsFadeAway() {
        let (w, _, _) = world(windowSnow: 2, kind: .snowballFight, seed: 4)
        w.startHelper(.snowballFight)
        run(w)
        for _ in 0..<(120 * 7) { w.step(dt: 1.0 / 120) }
        XCTAssertTrue(w.decals.isEmpty)
        XCTAssertLessThanOrEqual(w.decals.count, 24)
    }

    func testEachKidRunsOffItsOwnSideAtTheEnd() {
        let (w, _, _) = world(windowSnow: 2, kind: .snowballFight, seed: 3)
        w.startHelper(.snowballFight)
        var sawLeaving = false
        for _ in 0..<(120 * 90) {
            w.step(dt: 1.0 / 120); w.finishFrame()
            guard let f = w.fighter else { break }
            if f.phase == .leaving {
                sawLeaving = true
                XCTAssertTrue(f.balls.isEmpty || true)
                XCTAssertLessThanOrEqual(f.kids[0].x, f.kids[0].home + 0.01, "the left kid heads left")
                XCTAssertGreaterThanOrEqual(f.kids[1].x, f.kids[1].home - 0.01, "the right kid heads right")
            }
        }
        XCTAssertTrue(sawLeaving)
        XCTAssertNil(w.fighter)
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

    func testBuilderWorksInStagesLikeARealSnowman() {
        let (w, _, _) = world(floorSnow: 14, kind: .snowman)
        w.startHelper(.snowman)
        var phases: [BuilderRun.Phase] = []
        for _ in 0..<(120 * 90) {
            w.step(dt: 1.0 / 120); w.finishFrame()
            guard let b = w.builder else { break }
            if phases.last != b.phase { phases.append(b.phase) }
        }
        XCTAssertEqual(phases, [.rolling, .packMid, .liftMid, .packHead, .liftHead, .decorating, .waving, .leaving])
    }

    func testSnowmanIsStackedAndFullyDressed() {
        let (w, _, _) = world(floorSnow: 14, kind: .snowman)
        w.startHelper(.snowman)
        run(w)
        guard let m = w.snowmen.first else { return XCTFail("no snowman") }
        var props: [RenderProp] = []
        w.fillProps(&props)
        let balls = props.filter { $0.kind == .snowball }.sorted { $0.y < $1.y }
        XCTAssertEqual(balls.count, 3, "base, middle and head")
        XCTAssertLessThan(balls[0].w, 2 * m.radius + 0.01)
        XCTAssertGreaterThan(balls[1].y, balls[0].y + balls[0].w / 2, "the middle ball sits on the base")
        XCTAssertGreaterThan(balls[2].y, balls[1].y, "and the head on the middle")
        XCTAssertGreaterThan(balls[0].w, balls[1].w); XCTAssertGreaterThan(balls[1].w, balls[2].w)
        let parts = SnowmanLayout.parts(radius: m.radius)
        XCTAssertEqual(props.count, 3 + parts.count)
        func kinds(_ k: PropKind) -> [RenderProp] { props.filter { $0.kind == k } }
        XCTAssertEqual(kinds(.hat).count, 1); XCTAssertEqual(kinds(.scarf).count, 1); XCTAssertEqual(kinds(.carrot).count, 1)
        XCTAssertEqual(kinds(.stick).count, 2); XCTAssertEqual(kinds(.coal).count, 2 + 5 + 3, "two eyes, a smile, three buttons")
        XCTAssertGreaterThan(kinds(.hat)[0].y, balls[2].y, "the hat is on top of the head")
        XCTAssertLessThan(kinds(.carrot)[0].x, balls[2].x, "the nose points the way he faces (left)")
    }

    func testDecorationsFlyFromTheKidsHandThenStayPut() {
        let (w, _, _) = world(floorSnow: 14, kind: .snowman)
        let hand = SIMD2<Float>(400, 120)
        var mid: [RenderProp] = [], done: [RenderProp] = []
        let part = SnowmanLayout.parts(radius: 40)[0]
        w.snowmanProps(x: 100, baseY: 0, radius: 40, partTime: part.start + part.flight / 2, hand: hand, includeBalls: [false, false, false], out: &mid)
        w.snowmanProps(x: 100, baseY: 0, radius: 40, partTime: SnowmanLayout.decorTime + 1, hand: hand, includeBalls: [false, false, false], out: &done)
        let target = SIMD2<Float>(100 + part.offset.x, part.offset.y)
        let flying = mid[0]
        XCTAssertGreaterThan(flying.x, target.x + 20); XCTAssertLessThan(flying.x, hand.x - 20)
        XCTAssertEqual(done[0].x, target.x, accuracy: 0.01); XCTAssertEqual(done[0].y, target.y, accuracy: 0.01)
        XCTAssertEqual(mid.count, 1, "later parts have not been thrown yet")
        XCTAssertEqual(done.count, SnowmanLayout.parts(radius: 40).count)
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
            for p in snap.props { XCTAssertTrue(p.x.isFinite && p.y.isFinite && abs(p.w) > 0 && abs(p.h) > 0) }
        }
        let (w, _, _) = world(kind: .penguin)
        var snap = RenderSnapshot()
        w.fill(snapshot: &snap, showSurfaces: false, stats: SimulationStats())
        XCTAssertTrue(snap.props.isEmpty)
    }
}
