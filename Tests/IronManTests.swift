import XCTest
import simd
@testable import Snowfall

final class IronManTests: XCTestCase {
    private func world(width: CGFloat = 1600, snow: Float = 10, windowSnow: Float = 0) -> (PhysicsWorld, SurfaceState, SurfaceState?) {
        var c = SimulationConfiguration(); c.density = 0; c.plowAuto = false; c.helper = .ironMan; c.windStrength = 0; c.turbulence = 0
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
    private func run(_ w: PhysicsWorld, maxSeconds: Float = 120) -> Float {
        var t: Float = 0
        while w.isHelperRunning && t < maxSeconds { w.step(dt: 1.0 / 120); w.finishFrame(); t += 1.0 / 120 }
        return t
    }

    func testFliesInFromTheRight() {
        let (w, _, _) = world()
        w.startHelper(.ironMan)
        XCTAssertNotNil(w.ironMan)
        XCTAssertGreaterThan(w.ironMan!.x, 1600)
        for _ in 0..<(120 * 3) { w.step(dt: 1.0 / 120) }
        XCTAssertLessThan(w.ironMan!.x, 1600)
    }

    func testTravelsRightToLeftWhileScanning() {
        let (w, _, _) = world()
        w.startHelper(.ironMan)
        var xs: [Float] = []
        for step in 0..<(120 * 12) {
            w.step(dt: 1.0 / 120)
            if step % 120 == 0, let m = w.ironMan, m.phase == .scanning { xs.append(m.x) }
        }
        XCTAssertGreaterThan(xs.count, 3)
        for (a, b) in zip(xs, xs.dropFirst()) { XCTAssertLessThan(b, a, "only ever moves left while scanning") }
    }

    func testBeamStartsAtTheEyesAndEndsOnASurface() {
        let (w, floor, _) = world()
        w.startHelper(.ironMan)
        var checked = false
        for _ in 0..<(120 * 8) {
            w.step(dt: 1.0 / 120)
            if let m = w.ironMan, m.firing, m.phase == .scanning {
                XCTAssertGreaterThan(m.eyeWorld.y, m.spot.y, "beam points downward")
                XCTAssertLessThan(m.spot.x, m.eyeWorld.x + 120, "beam points forward (left)")
                XCTAssertGreaterThanOrEqual(m.spot.y, floor.surface.topY - 0.5)
                checked = true
            }
        }
        XCTAssertTrue(checked)
    }

    func testBeamMeltsSnowAtTheImpactPoint() {
        let (w, floor, _) = world(snow: 20)
        let before = floor.field.volume
        w.startHelper(.ironMan)
        for _ in 0..<(120 * 8) { w.step(dt: 1.0 / 120) }
        XCTAssertLessThan(floor.field.volume, before * 0.9, "snow under the beam melts away")
        XCTAssertGreaterThan(w.totals.lostVolume, 0)
    }

    func testTwoBeamsReachBothTheWindowTopAndTheFloor() {
        let (w, _, _) = world(snow: 10, windowSnow: 8)
        w.startHelper(.ironMan)
        var sawWindowBeam = false, sawFloorBeam = false
        for _ in 0..<(120 * 20) {
            w.step(dt: 1.0 / 120)
            guard let m = w.ironMan, m.firing else { continue }
            if m.spot.x > 320, m.spot.x < 780, m.spot.y > 400 { sawWindowBeam = true }
            if m.spot2.y < 60 { sawFloorBeam = true }
        }
        XCTAssertTrue(sawWindowBeam, "one beam lands on the window top")
        XCTAssertTrue(sawFloorBeam, "the other lands on the floor")
    }

    func testMeltIsLocalNotGlobal() {
        let (w, floor, _) = world(snow: 20)
        w.startHelper(.ironMan)
        for _ in 0..<(120 * 5) { w.step(dt: 1.0 / 120) }
        // Far left of the beam is untouched.
        XCTAssertEqual(floor.field.height(atLocalX: 100), 20, accuracy: 0.01)
    }

    func testRunClearsFloorAndWindowTops() {
        let (w, floor, win) = world(snow: 12, windowSnow: 8)
        w.startHelper(.ironMan)
        run(w)
        XCTAssertFalse(w.isHelperRunning)
        XCTAssertLessThan(floor.field.volume / 1600, 1.0, "floor melted")
        XCTAssertLessThan(win!.field.volume / 500, 1.0, "window top melted")
    }

    func testMeltedVolumeIsAccountedFor() {
        let (w, floor, win) = world(snow: 12, windowSnow: 8)
        let initial = floor.field.volume + win!.field.volume
        w.startHelper(.ironMan)
        run(w)
        for _ in 0..<(120 * 3) { w.step(dt: 1.0 / 120); w.finishFrame() }
        let accounted = floor.field.volume + win!.field.volume + w.totals.lostVolume + w.totals.clippedVolume + w.totals.droppedVolume
        XCTAssertEqual(accounted, initial, accuracy: initial * 0.03)
    }

    func testSteamRisesFadesAndIsBounded() {
        let (w, _, _) = world(snow: 25)
        w.startHelper(.ironMan)
        var sawSteam = false
        var maxCount = 0
        for _ in 0..<(120 * 14) {
            w.step(dt: 1.0 / 120); w.finishFrame()
            let steam = (0..<w.pool.count).filter { w.pool[$0].state == .steam }.count
            if steam > 0 { sawSteam = true }
            maxCount = max(maxCount, w.pool.count)
            XCTAssertLessThanOrEqual(w.pool.count, w.pool.capacity)
        }
        XCTAssertTrue(sawSteam, "melting snow makes steam")
        // Steam is short-lived: after the run ends it is gone.
        run(w)
        for _ in 0..<(120 * 3) { w.step(dt: 1.0 / 120) }
        XCTAssertEqual((0..<w.pool.count).filter { w.pool[$0].state == .steam }.count, 0)
    }

    func testAirborneFlakeCrossingTheBeamIsVaporized() {
        let (w, _, _) = world(snow: 0)
        w.startHelper(.ironMan)
        for _ in 0..<(120 * 4) { w.step(dt: 1.0 / 120) }
        guard let m = w.ironMan, m.firing else { return XCTFail("not firing") }
        let mid = (m.eyeWorld + m.spot) / 2
        var p = SnowParticle.blank
        p.position = mid; p.velocity = .zero; p.mass = 1; p.radius = 3; p.opacity = 1; p.volume = 5
        w.pool.spawn(p)
        let before = w.totals.lostVolume
        w.step(dt: 1.0 / 120)
        XCTAssertGreaterThan(w.totals.lostVolume, before, "its snow is melted away")
        XCTAssertFalse((0..<w.pool.count).contains { w.pool[$0].state == .falling && abs(w.pool[$0].position.x - mid.x) < 2 && abs(w.pool[$0].position.y - mid.y) < 8 })
    }

    func testFlakeAwayFromTheBeamIsLeftAlone() {
        let (w, _, _) = world(snow: 0)
        w.startHelper(.ironMan)
        for _ in 0..<(120 * 4) { w.step(dt: 1.0 / 120) }
        guard let m = w.ironMan else { return XCTFail() }
        var p = SnowParticle.blank
        p.position = SIMD2(m.spot.x - 600, m.spot.y + 400); p.velocity = .zero; p.mass = 1; p.radius = 3; p.opacity = 1; p.volume = 5
        w.pool.spawn(p)
        let idx = w.pool.count - 1
        w.step(dt: 1.0 / 120)
        XCTAssertEqual(w.pool[idx].state, .falling)
    }

    func testLeavesAndFinishes() {
        let (w, _, _) = world(snow: 5)
        w.startHelper(.ironMan)
        let t = run(w)
        XCTAssertLessThan(t, 100)
        XCTAssertNil(w.ironMan)
    }

    func testOnlyOneHelperAtATime() {
        let (w, _, _) = world()
        w.startHelper(.ironMan)
        w.startHelper(.santa)
        w.startHelper(.jcb)
        XCTAssertNotNil(w.ironMan); XCTAssertNil(w.santa); XCTAssertNil(w.plow)
        let (w2, _, _) = world()
        w2.startHelper(.jcb)
        w2.startHelper(.ironMan)
        XCTAssertNil(w2.ironMan)
    }

    func testRegisteredEligibleAndSelectable() {
        XCTAssertTrue(HelperKind.concrete.contains(.ironMan))
        XCTAssertFalse(HelperKind.ironMan.label.isEmpty)
        let (w, _, _) = world(snow: 10)
        XCTAssertTrue(w.eligibleHelpers().contains(.ironMan))
        let (w2, _, _) = world(snow: 0)
        XCTAssertFalse(w2.eligibleHelpers().contains(.ironMan))
    }

    func testAutoRunPicksIronManWhenChosen() {
        var c = SimulationConfiguration(); c.density = 0; c.plowAuto = true; c.plowInterval = 5; c.helper = .ironMan
        let w = PhysicsWorld(config: c)
        w.setRegion(CGRect(x: 0, y: 0, width: 1000, height: 800))
        w.setSurfaces([CollisionSurface(id: "floor", frame: CGRect(x: 0, y: 0, width: 1000, height: 0), velocity: .zero, kind: .displayBottom)])
        for _ in 0..<(120 * 8) { w.step(dt: 1.0 / 120); w.finishFrame() }
        XCTAssertFalse(w.isHelperRunning)
        let st = w.state(forSurface: "floor")!
        for i in 0..<st.field.binCount { st.field.add(volume: 10 * st.field.binWidth, toBin: i) }
        w.finishFrame()
        XCTAssertNotNil(w.ironMan)
    }

    func testRenderSnapshotContainsIronManWithBeam() {
        let (w, _, _) = world(snow: 10)
        w.startHelper(.ironMan)
        for _ in 0..<(120 * 5) { w.step(dt: 1.0 / 120) }
        var snap = RenderSnapshot()
        w.fill(snapshot: &snap, showSurfaces: false, stats: SimulationStats())
        XCTAssertEqual(snap.ironMen.count, 1)
        XCTAssertTrue(snap.ironMen[0].firing)
        XCTAssertGreaterThan(snap.ironMen[0].intensity, 0.5)
    }

    func testFieldMeltNeverGoesNegative() {
        var f = SnowAccumulationField(width: 200, maxDepth: 50)
        f.add(volume: 8, toBin: 3)
        let d = f.height(atBin: 3)
        XCTAssertEqual(f.melt(bin: 3, depth: 1000), d, accuracy: 1e-5)
        XCTAssertEqual(f.height(atBin: 3), 0)
        XCTAssertEqual(f.melt(bin: -1, depth: 5), 0)
    }

    func testSettingsAcceptIronMan() throws {
        let s = try JSONDecoder().decode(SnowfallSettings.self, from: Data(#"{"helper":"ironMan"}"#.utf8))
        XCTAssertEqual(s.helper, .ironMan)
    }
}
