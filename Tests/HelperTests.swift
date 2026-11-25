import XCTest
import simd
@testable import Snowfall

final class HelperTests: XCTestCase {
    private func world(width: CGFloat = 1600, snow: Float = 10, windowSnow: Float = 0, helper: HelperKind = .santa) -> (PhysicsWorld, SurfaceState, SurfaceState?) {
        var c = SimulationConfiguration(); c.density = 0; c.plowAuto = false; c.helper = helper
        let w = PhysicsWorld(config: c)
        w.setRegion(CGRect(x: 0, y: 0, width: width, height: 900))
        var surfaces = [CollisionSurface(id: "floor", frame: CGRect(x: 0, y: 0, width: width, height: 0), velocity: .zero, kind: .displayBottom)]
        if windowSnow > 0 {
            surfaces.append(CollisionSurface(id: "win", frame: CGRect(x: 300, y: 200, width: 500, height: 300), velocity: .zero, kind: .windowTop, zRank: 0))
        }
        w.setSurfaces(surfaces)
        let floor = w.state(forSurface: "floor")!
        for i in 0..<floor.field.binCount { floor.field.add(volume: snow * floor.field.binWidth, toBin: i) }
        var win: SurfaceState?
        if windowSnow > 0 {
            win = w.state(forSurface: "win")!
            for i in 0..<win!.field.binCount { win!.field.add(volume: windowSnow * win!.field.binWidth, toBin: i) }
        }
        return (w, floor, win)
    }

    @discardableResult
    private func runHelper(_ w: PhysicsWorld, maxSeconds: Float = 90) -> Float {
        var t: Float = 0
        while w.isHelperRunning && t < maxSeconds { w.step(dt: 1.0 / 120); w.finishFrame(); t += 1.0 / 120 }
        return t
    }

    func testSantaEntersFromTheRightAndHovers() {
        let (w, _, _) = world()
        w.startHelper(.santa)
        XCTAssertNotNil(w.santa)
        XCTAssertGreaterThan(w.santa!.x, 1600)
        for _ in 0..<(120 * 3) { w.step(dt: 1.0 / 120) }
        XCTAssertLessThan(w.santa!.x, 1600)
        XCTAssertNotEqual(w.santa!.phase, .arriving)
    }

    func testWandFlourishRaisesAndSwings() {
        let (w, _, _) = world()
        w.startHelper(.santa)
        var minA: Float = 9, maxA: Float = -9
        for _ in 0..<(120 * 8) {
            w.step(dt: 1.0 / 120)
            if let a = w.santa?.wandAngle { minA = min(minA, a); maxA = max(maxA, a) }
        }
        XCTAssertGreaterThan(maxA - minA, 0.8, "wand must visibly swing")
    }

    func testTornadoAppearsAndTravelsRightToLeft() {
        let (w, _, _) = world()
        w.startHelper(.santa)
        var firstX: Float?
        var lastX: Float?
        for _ in 0..<(120 * 14) {
            w.step(dt: 1.0 / 120)
            if let t = w.tornado { if firstX == nil { firstX = t.x }; lastX = t.x }
        }
        XCTAssertNotNil(firstX)
        XCTAssertLessThan(lastX ?? 9999, firstX ?? 0, "tornado travels right to left")
    }

    func testTornadoClearsFloorAndWindowTops() {
        let (w, floor, win) = world(snow: 10, windowSnow: 8)
        w.startHelper(.santa)
        runHelper(w)
        XCTAssertFalse(w.isHelperRunning)
        for _ in 0..<(120 * 10) { w.step(dt: 1.0 / 120) }
        XCTAssertLessThan(floor.field.volume / 1600, 1.0, "floor cleared")
        XCTAssertLessThan(win!.field.volume / 500, 1.0, "window top cleared")
    }

    func testSnowVolumeIsAccountedFor() {
        let (w, floor, win) = world(snow: 10, windowSnow: 8)
        let initial = floor.field.volume + win!.field.volume
        w.startHelper(.santa)
        runHelper(w)
        for _ in 0..<(120 * 15) { w.step(dt: 1.0 / 120); w.finishFrame() }
        let remaining = floor.field.volume + win!.field.volume
        let accounted = remaining + w.totals.lostVolume + w.totals.clippedVolume + w.totals.droppedVolume
        XCTAssertEqual(accounted, initial, accuracy: initial * 0.03)
    }

    func testSwirlParticlesStayBoundedAndFinite() {
        let (w, _, _) = world(snow: 30, windowSnow: 20)
        w.startHelper(.santa)
        var maxCount = 0
        var t: Float = 0
        while w.isHelperRunning && t < 90 {
            w.step(dt: 1.0 / 120); w.finishFrame(); t += 1.0 / 120
            maxCount = max(maxCount, w.pool.count)
            XCTAssertLessThanOrEqual(w.pool.count, w.pool.capacity)
        }
        XCTAssertGreaterThan(maxCount, 50, "funnel should be visible")
        for i in 0..<w.pool.count {
            XCTAssertTrue(w.pool[i].position.x.isFinite && w.pool[i].position.y.isFinite)
        }
    }

    func testSwirlingParticlesFormAFunnel() {
        let (w, _, _) = world(snow: 10)
        w.startHelper(.santa)
        for _ in 0..<(120 * 9) { w.step(dt: 1.0 / 120) }
        guard let t = w.tornado else { return XCTFail("no tornado") }
        var lowSpread: Float = 0, highSpread: Float = 0, lowN: Float = 0, highN: Float = 0
        for i in 0..<w.pool.count where w.pool[i].state == .swirling {
            let h = w.pool[i].position.y - t.baseY
            let dx = abs(w.pool[i].position.x - t.x)
            if h < t.height * 0.3 { lowSpread += dx; lowN += 1 } else if h > t.height * 0.6 { highSpread += dx; highN += 1 }
        }
        XCTAssertGreaterThan(lowN, 3); XCTAssertGreaterThan(highN, 3)
        XCTAssertGreaterThan(highSpread / highN, lowSpread / lowN, "funnel widens with height")
    }

    func testSparklesAreShortLived() {
        let (w, _, _) = world()
        w.startHelper(.santa)
        for _ in 0..<(120 * 5) { w.step(dt: 1.0 / 120) }
        let sparkles = (0..<w.pool.count).filter { w.pool[$0].state == .sparkle }.count
        XCTAssertGreaterThan(sparkles, 0)
        XCTAssertLessThan(sparkles, 200)
    }

    func testSantaLeavesAndHelperFinishes() {
        let (w, _, _) = world()
        w.startHelper(.santa)
        let t = runHelper(w)
        XCTAssertLessThan(t, 90)
        XCTAssertNil(w.santa); XCTAssertNil(w.tornado)
    }

    func testOnlyOneHelperAtATime() {
        let (w, _, _) = world()
        w.startHelper(.jcb)
        w.startHelper(.santa)
        XCTAssertNotNil(w.plow)
        XCTAssertNil(w.santa)
    }

    func testConfiguredHelperIsUsedAndRandomPicksAConcreteOne() {
        let (w1, _, _) = world(helper: .jcb)
        w1.startHelper()
        XCTAssertNotNil(w1.plow)
        let (w2, _, _) = world(helper: .santa)
        w2.startHelper()
        XCTAssertNotNil(w2.santa)
        let (w3, _, _) = world(helper: .random)
        w3.startHelper()
        XCTAssertTrue(w3.isHelperRunning)
    }

    func testAutoRunUsesChosenHelperAndNeedsSnow() {
        var c = SimulationConfiguration(); c.density = 0; c.plowAuto = true; c.plowInterval = 5; c.helper = .santa
        let w = PhysicsWorld(config: c)
        w.setRegion(CGRect(x: 0, y: 0, width: 1000, height: 800))
        w.setSurfaces([CollisionSurface(id: "floor", frame: CGRect(x: 0, y: 0, width: 1000, height: 0), velocity: .zero, kind: .displayBottom)])
        for _ in 0..<(120 * 8) { w.step(dt: 1.0 / 120); w.finishFrame() }
        XCTAssertFalse(w.isHelperRunning, "no snow → no helper")
        let st = w.state(forSurface: "floor")!
        for i in 0..<st.field.binCount { st.field.add(volume: 10 * st.field.binWidth, toBin: i) }
        w.finishFrame()
        XCTAssertNotNil(w.santa)
        XCTAssertNil(w.plow)
    }

    func testEligibilityDependsOnWhereTheSnowIs() {
        var c = SimulationConfiguration(); c.density = 0
        let w = PhysicsWorld(config: c)
        w.setRegion(CGRect(x: 0, y: 0, width: 1000, height: 800))
        w.setSurfaces([CollisionSurface(id: "floor", frame: CGRect(x: 0, y: 0, width: 1000, height: 0), velocity: .zero, kind: .displayBottom),
                       CollisionSurface(id: "win", frame: CGRect(x: 100, y: 100, width: 400, height: 300), velocity: .zero, kind: .windowTop, zRank: 0)])
        let win = w.state(forSurface: "win")!
        for i in 0..<win.field.binCount { win.field.add(volume: 10 * win.field.binWidth, toBin: i) }
        XCTAssertEqual(w.eligibleHelpers(), [.santa, .ironMan, .thor, .spiderMan, .snowballFight, .sleigh], "only window snow: the floor helpers have nothing to clear")
    }

    func testRenderSnapshotContainsSanta() {
        let (w, _, _) = world()
        w.startHelper(.santa)
        for _ in 0..<(120 * 2) { w.step(dt: 1.0 / 120) }
        var snap = RenderSnapshot()
        w.fill(snapshot: &snap, showSurfaces: false, stats: SimulationStats())
        XCTAssertEqual(snap.santas.count, 1)
        XCTAssertTrue(snap.vehicles.isEmpty)
    }

    func testWandTipFollowsAngle() {
        var s = SantaRun(x: 500, y: 300, start: .zero, hover: .zero)
        s.wandAngle = 0
        XCTAssertLessThan(s.tipWorld.x, s.handWorld.x, "tip points left")
        XCTAssertEqual(s.tipWorld.y, s.handWorld.y, accuracy: 0.001)
        s.wandAngle = -.pi / 2
        XCTAssertGreaterThan(s.tipWorld.y, s.handWorld.y, "negative angle raises the wand")
    }

    func testHelperSettingDefaultsAndToleratesUnknownValues() throws {
        XCTAssertEqual(SnowfallSettings.default.helper, .jcb)
        let json = #"{"version":2,"helper":"unicorn","particleDensity":0.7}"#
        let s = try JSONDecoder().decode(SnowfallSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.helper, .jcb)
        XCTAssertEqual(s.particleDensity, 0.7)
        let ok = try JSONDecoder().decode(SnowfallSettings.self, from: Data(#"{"helper":"santa"}"#.utf8))
        XCTAssertEqual(ok.helper, .santa)
    }

    func testEveryConcreteHelperHasLabelsAndIsRegistered() {
        for k in HelperKind.concrete { XCTAssertFalse(k.label.isEmpty); XCTAssertFalse(k.summary.isEmpty) }
        XCTAssertTrue(HelperKind.allCases.contains(.random))
        XCTAssertFalse(HelperKind.concrete.contains(.random))
    }
}

/// The tornado also takes snow that is still in the air.
final class TornadoAirborneTests: XCTestCase {
    private func tornadoWorld() -> PhysicsWorld {
        var c = SimulationConfiguration(); c.density = 0; c.plowAuto = false; c.helper = .santa; c.windStrength = 0; c.turbulence = 0
        let w = PhysicsWorld(config: c)
        w.setRegion(CGRect(x: 0, y: 0, width: 1600, height: 900))
        w.setSurfaces([CollisionSurface(id: "floor", frame: CGRect(x: 0, y: 0, width: 1600, height: 0), velocity: .zero, kind: .displayBottom)])
        w.startHelper(.santa)
        for _ in 0..<(120 * 7) where w.tornado == nil || (w.tornado?.strength ?? 0) < 1 { w.step(dt: 1.0 / 120) }
        for _ in 0..<(120 * 2) { w.step(dt: 1.0 / 120) }       // fully formed
        return w
    }

    private func flake(_ x: Float, _ y: Float) -> SnowParticle {
        var p = SnowParticle.blank
        p.position = SIMD2(x, y); p.velocity = SIMD2(0, -60); p.mass = 1; p.radius = 3; p.opacity = 0.9; p.volume = 5
        return p
    }

    func testFallingFlakeInsideTheFunnelIsTaken() {
        let w = tornadoWorld()
        guard let t = w.tornado else { return XCTFail("no tornado") }
        w.pool.spawn(flake(t.x + 8, t.baseY + 150))
        let idx = w.pool.count - 1
        w.step(dt: 1.0 / 120)
        XCTAssertEqual(w.pool[idx].state, .swirling)
    }

    func testDistantFlakeIsEventuallyTaken() {
        let w = tornadoWorld()
        guard let t = w.tornado else { return XCTFail("no tornado") }
        w.pool.spawn(flake(t.x + 900, t.baseY + 150))      // far behind the tornado
        let idx = w.pool.count - 1
        var caught = false
        for _ in 0..<(120 * 5) {
            w.step(dt: 1.0 / 120)
            if idx < w.pool.count, w.pool[idx].state == .swirling { caught = true; break }
        }
        XCTAssertTrue(caught, "Santa's magic pulls in flakes from anywhere on screen")
    }

    func testFlakeAheadOfTheTornadoIsTakenToo() {
        let w = tornadoWorld()
        guard let t = w.tornado else { return XCTFail("no tornado") }
        w.pool.spawn(flake(t.x - 380, t.baseY + 300))      // inside the tornado's reach
        let idx = w.pool.count - 1
        var caught = false
        for _ in 0..<(120 * 5) {
            w.step(dt: 1.0 / 120)
            if idx < w.pool.count, w.pool[idx].state == .swirling { caught = true; break }
        }
        XCTAssertTrue(caught)
    }

    func testSnowAheadOutsideReachIsLeftUntilTheTornadoArrives() {
        let w = tornadoWorld()
        guard let t = w.tornado else { return XCTFail("no tornado") }
        w.pool.spawn(flake(t.x - 900, t.baseY + 600))
        let idx = w.pool.count - 1
        for _ in 0..<30 { w.step(dt: 1.0 / 120) }
        XCTAssertEqual(w.pool[idx].state, .falling, "the sweep advances right to left; far-ahead snow is not yet touched")
    }

    func testNothingIsLeftOnTheRightOfTheTornado() {
        var c = SimulationConfiguration(); c.density = 1; c.maxParticles = 800; c.plowAuto = false; c.helper = .santa; c.seed = 21
        let w = PhysicsWorld(config: c)
        w.setRegion(CGRect(x: 0, y: 0, width: 1600, height: 900))
        w.setSurfaces([CollisionSurface(id: "floor", frame: CGRect(x: 0, y: 0, width: 1600, height: 0), velocity: .zero, kind: .displayBottom)])
        w.prewarm()
        w.startHelper(.santa)
        while w.tornado == nil && w.isHelperRunning { w.step(dt: 1.0 / 120) }
        var worst = 0
        var samples = 0
        while let t = w.tornado {
            w.step(dt: 1.0 / 120)
            guard t.x < 1000, t.strength >= 1 else { continue }
            // Allow time for flakes that were just passed to streak in; check a strip well behind.
            let behind = (0..<w.pool.count).filter { i in
                let p = w.pool[i]
                return p.state != .sparkle && p.position.x > t.x + 450 && p.position.x < 1700
            }.count
            worst = max(worst, behind); samples += 1
        }
        XCTAssertGreaterThan(samples, 100)
        XCTAssertLessThanOrEqual(worst, 6, "no snow should be visible to the right of the tornado (worst \(worst))")
    }

    func testThrownOutFlakesFlyLeftAndFadeAway() {
        let w = tornadoWorld()
        for _ in 0..<(120 * 3) { w.step(dt: 1.0 / 120) }
        let thrown = (0..<w.pool.count).filter { w.pool[$0].orbitRadius < 0 }
        XCTAssertFalse(thrown.isEmpty)
        for i in thrown { XCTAssertLessThan(w.pool[i].velocity.x, 40, "thrown out toward the left, never back to the right") }
        for _ in 0..<(120 * 3) { w.step(dt: 1.0 / 120) }
        XCTAssertLessThan((0..<w.pool.count).filter { w.pool[$0].orbitRadius < 0 }.count, thrown.count + 40)
    }

    func testNoNewSnowSpawnsWhileTheTornadoWorks() {
        var c = SimulationConfiguration(); c.density = 1; c.maxParticles = 400; c.plowAuto = false; c.helper = .santa
        let w = PhysicsWorld(config: c)
        w.setRegion(CGRect(x: 0, y: 0, width: 1600, height: 900))
        w.setSurfaces([CollisionSurface(id: "floor", frame: CGRect(x: 0, y: 0, width: 1600, height: 0), velocity: .zero, kind: .displayBottom)])
        w.startHelper(.santa)
        for _ in 0..<(120 * 5) { w.step(dt: 1.0 / 120) }      // tornado now exists
        XCTAssertNotNil(w.tornado)
        let falling = { (0..<w.pool.count).filter { w.pool[$0].state == .falling }.count }
        let a = falling()
        for _ in 0..<(120 * 2) { w.step(dt: 1.0 / 120) }
        XCTAssertLessThanOrEqual(falling(), a, "no new flakes while the tornado is active")
    }

    func testHomingFlakesDoNotRedepositSnowBehindTheTornado() {
        var c = SimulationConfiguration(); c.density = 1; c.maxParticles = 800; c.plowAuto = false; c.helper = .santa; c.seed = 9
        let w = PhysicsWorld(config: c)
        w.setRegion(CGRect(x: 0, y: 0, width: 1600, height: 900))
        w.setSurfaces([CollisionSurface(id: "floor", frame: CGRect(x: 0, y: 0, width: 1600, height: 0), velocity: .zero, kind: .displayBottom)])
        w.prewarm()
        let airborne = (0..<w.pool.count).reduce(Float(0)) { $0 + w.pool[$1].volume }
        w.startHelper(.santa)
        while w.isHelperRunning { w.step(dt: 1.0 / 120); w.finishFrame() }
        for _ in 0..<(120 * 2) { w.step(dt: 1.0 / 120) }
        let floor = w.state(forSurface: "floor")!.field.volume
        print("HOMING floor volume after run: \(floor) of \(airborne) airborne")
        XCTAssertLessThan(floor, airborne * 0.12, "snow must not pile up again behind the tornado")
    }

    func testTheSkyIsClearedByTheEndOfTheSweep() {
        var c = SimulationConfiguration(); c.density = 1; c.maxParticles = 800; c.plowAuto = false; c.helper = .santa; c.seed = 5
        let w = PhysicsWorld(config: c)
        w.setRegion(CGRect(x: 0, y: 0, width: 1600, height: 900))
        w.setSurfaces([CollisionSurface(id: "floor", frame: CGRect(x: 0, y: 0, width: 1600, height: 0), velocity: .zero, kind: .displayBottom)])
        w.prewarm()
        let before = (0..<w.pool.count).filter { w.pool[$0].state == .falling }.count
        XCTAssertGreaterThan(before, 200)
        w.startHelper(.santa)
        while w.tornado == nil && w.isHelperRunning { w.step(dt: 1.0 / 120) }
        while w.tornado != nil { w.step(dt: 1.0 / 120) }       // until the tornado leaves the screen
        let after = (0..<w.pool.count).filter { w.pool[$0].state == .falling }.count
        XCTAssertLessThan(Double(after), Double(before) * 0.05, "airborne snow is taken (before \(before), after \(after))")
    }

    func testNearbyFlakeIsDrawnTowardTheAxisThenCaught() {
        let w = tornadoWorld()
        guard let t = w.tornado else { return XCTFail("no tornado") }
        let startDX: Float = 170
        w.pool.spawn(flake(t.x + startDX, t.baseY + 250))
        let idx = w.pool.count - 1
        var caught = false
        for _ in 0..<(120 * 3) {
            w.step(dt: 1.0 / 120)
            if idx < w.pool.count, w.pool[idx].state == .swirling { caught = true; break }
        }
        XCTAssertTrue(caught, "suction should pull a nearby flake into the funnel")
    }

    func testFlakeAboveTheFunnelIsPulledIn() {
        let w = tornadoWorld()
        guard let t = w.tornado else { return XCTFail("no tornado") }
        let h = t.baseY + t.height + 200
        w.pool.spawn(flake(t.x + 120, h))
        let idx = w.pool.count - 1
        let before = abs(w.pool[idx].position.x - t.x)
        for _ in 0..<60 { w.step(dt: 1.0 / 120) }
        guard idx < w.pool.count else { return }
        let after = abs(w.pool[idx].position.x - (w.tornado?.x ?? t.x))
        XCTAssertLessThan(after, before, "moves toward the axis (got \(after) from \(before))")
    }

    func testThrownOutFlakesAreNotRecaptured() {
        let w = tornadoWorld()
        guard let t = w.tornado else { return XCTFail("no tornado") }
        var p = flake(t.x + 5, t.baseY + 100)
        p.state = .displaced; p.orbitRadius = -1; p.volume = 0
        w.pool.spawn(p)
        let idx = w.pool.count - 1
        w.step(dt: 1.0 / 120)
        XCTAssertEqual(w.pool[idx].state, .displaced)
    }

    func testFallingSnowIsClearedDuringARun() {
        var c = SimulationConfiguration(); c.density = 1; c.maxParticles = 600; c.plowAuto = false; c.helper = .santa; c.seed = 11
        let w = PhysicsWorld(config: c)
        w.setRegion(CGRect(x: 0, y: 0, width: 1600, height: 900))
        w.setSurfaces([CollisionSurface(id: "floor", frame: CGRect(x: 0, y: 0, width: 1600, height: 0), velocity: .zero, kind: .displayBottom)])
        w.prewarm()
        let airborneBefore = w.pool.count
        w.startHelper(.santa)
        var swirled = 0
        for _ in 0..<(120 * 20) {
            w.step(dt: 1.0 / 120)
            swirled = max(swirled, (0..<w.pool.count).filter { w.pool[$0].state == .swirling && w.pool[$0].volume > 0 }.count)
        }
        XCTAssertGreaterThan(airborneBefore, 100)
        XCTAssertGreaterThan(swirled, 5, "falling flakes with snow volume get taken into the funnel")
        XCTAssertLessThanOrEqual(w.pool.count, w.pool.capacity)
    }
}
