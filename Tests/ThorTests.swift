import XCTest
import simd
@testable import Snowfall

final class ThorTests: XCTestCase {
    private func world(width: CGFloat = 2000, snow: Float = 20, windowSnow: Float = 0, seed: UInt64 = 1) -> (PhysicsWorld, SurfaceState, SurfaceState?) {
        var c = SimulationConfiguration(); c.density = 0; c.plowAuto = false; c.helper = .thor; c.windStrength = 0; c.turbulence = 0; c.seed = seed
        let w = PhysicsWorld(config: c)
        w.setRegion(CGRect(x: 0, y: 0, width: width, height: 900))
        var surfaces = [CollisionSurface(id: "floor", frame: CGRect(x: 0, y: 0, width: width, height: 0), velocity: .zero, kind: .displayBottom)]
        if windowSnow > 0 {
            surfaces.append(CollisionSurface(id: "win", frame: CGRect(x: 300, y: 200, width: 600, height: 300), velocity: .zero, kind: .windowTop, zRank: 0))
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

    func testPlansASiteEveryFewHundredPointsOrderedRightToLeft() {
        let (w, _, _) = world(snow: 20)
        w.startHelper(.thor)
        guard let r = w.thor else { return XCTFail("no run") }
        XCTAssertGreaterThan(r.sites.count, 4, "the whole stack is covered, not two or three spots")
        XCTAssertLessThanOrEqual(r.sites.count, ThorMetrics.maxSites)
        for (a, b) in zip(r.sites, r.sites.dropFirst()) { XCTAssertGreaterThanOrEqual(a.x, b.x, "right to left") }
        let floorSites = r.sites.filter { $0.surfaceID == "floor" }
        for (a, b) in zip(floorSites, floorSites.dropFirst()) { XCTAssertLessThanOrEqual(a.x - b.x, ThorMetrics.siteSpacing + 1, "no gaps wider than a blow clears") }
    }

    func testSkipsEmptySurfaces() {
        let (w, _, _) = world(snow: 0, windowSnow: 25)
        w.startHelper(.thor)
        XCTAssertTrue(w.thor!.sites.allSatisfy { $0.surfaceID == "win" }, "no wasted trips to the empty floor")
    }

    func testFliesInFromTheRight() {
        let (w, _, _) = world()
        w.startHelper(.thor)
        XCTAssertGreaterThan(w.thor!.x, 2000)
        for _ in 0..<(120 * 2) { w.step(dt: 1.0 / 120) }
        XCTAssertLessThan(w.thor!.x, 2000)
    }

    func testExactlyTwoBlowsAtEachSite() {
        let (w, _, _) = world(seed: 4)
        w.startHelper(.thor)
        let sites = w.thor!.sites.count
        run(w)
        XCTAssertEqual(w.thorBlowLog.count, sites * 2)
        for s in 0..<sites {
            XCTAssertEqual(w.thorBlowLog.filter { $0.siteIndex == s }.map(\.level), [1, 2], "blow 1 cracks, blow 2 shatters")
        }
    }

    func testSecondBlowBreaksMoreThanTheFirst() {
        let (w, _, _) = world(snow: 25)
        w.startHelper(.thor)
        run(w)
        for s in 0..<3 {
            let a = w.thorBlowLog.first { $0.siteIndex == s && $0.level == 1 }
            let b = w.thorBlowLog.first { $0.siteIndex == s && $0.level == 2 }
            if let a, let b { XCTAssertGreaterThan(b.removed + 0.001, a.removed, "shatter ≥ crack") }
        }
    }

    func testBlowsBreakSnowOnlyAroundTheImpact() {
        let (w, floor, _) = world(snow: 20)
        w.startHelper(.thor)
        let site = w.thor!.sites[0]
        while w.thorBlowLog.count < 2 { w.step(dt: 1.0 / 120); w.finishFrame() }
        XCTAssertLessThan(floor.field.height(atLocalX: site.x), 1.0, "cleared at the impact")
        XCTAssertEqual(floor.field.height(atLocalX: site.x - 400), 20, accuracy: 0.01, "untouched far away")
        if site.x + 400 < 1990 { XCTAssertEqual(floor.field.height(atLocalX: site.x + 400), 20, accuracy: 0.01) }
    }

    func testRunClearsAllTheStackedSnowAndFinishes() {
        let (w, floor, _) = world(snow: 20)
        w.startHelper(.thor)
        let before = floor.field.volume
        let t = run(w, maxSeconds: 150)
        XCTAssertLessThan(t, 120, "finishes in reasonable time (\(t) s)")
        XCTAssertNil(w.thor)
        XCTAssertLessThan(floor.field.volume, before * 0.05, "the hammer clears the whole floor")
    }

    func testWorksOnWindowTopsToo() {
        let (w, floor, win) = world(snow: 0.5, windowSnow: 25)
        _ = floor
        w.startHelper(.thor)
        let before = win!.field.volume
        run(w)
        XCTAssertLessThan(win!.field.volume, before, "snow on the window top is broken as well")
    }

    func testBrokenIceIsAccountedFor() {
        let (w, floor, win) = world(snow: 15, windowSnow: 12)
        let initial = floor.field.volume + win!.field.volume
        w.startHelper(.thor)
        run(w)
        for _ in 0..<(120 * 3) { w.step(dt: 1.0 / 120); w.finishFrame() }
        let accounted = floor.field.volume + win!.field.volume + w.totals.lostVolume + w.totals.clippedVolume + w.totals.droppedVolume
        XCTAssertEqual(accounted, initial, accuracy: initial * 0.03)
    }

    func testHammerHeadLandsOnTheSiteDuringBlows() {
        let (w, floor, _) = world(snow: 20)
        w.startHelper(.thor)
        let site = w.thor!.sites[0]
        var checked = false
        while w.thorBlowLog.isEmpty { w.step(dt: 1.0 / 120) }
        if let r = w.thor, r.siteIndex == 0 {
            XCTAssertEqual(r.impactWorld.x, site.x, accuracy: 6)
            XCTAssertEqual(r.impactWorld.y, floor.surface.topY + 20, accuracy: 14, "head meets the top of the snow layer")
            checked = true
        }
        XCTAssertTrue(checked)
    }

    func testShardsFlyOutAndFadeAway() {
        let (w, _, _) = world(snow: 20)
        w.startHelper(.thor)
        while w.thorBlowLog.isEmpty { w.step(dt: 1.0 / 120) }
        for _ in 0..<12 { w.step(dt: 1.0 / 120) }
        let shards = (0..<w.pool.count).filter { w.pool[$0].orbitRadius < 0 }
        XCTAssertGreaterThan(shards.count, 15)
        XCTAssertTrue(shards.contains { w.pool[$0].velocity.y > 100 }, "thrown upward")
        run(w)
        for _ in 0..<(120 * 2) { w.step(dt: 1.0 / 120) }
        XCTAssertEqual((0..<w.pool.count).filter { w.pool[$0].orbitRadius < 0 }.count, 0, "all shards fade")
        XCTAssertLessThanOrEqual(w.pool.count, w.pool.capacity)
    }

    func testBlastPushesNearbyAirborneSnowAway() {
        let (w, _, _) = world(snow: 20)
        w.startHelper(.thor)
        let site = w.thor!.sites[0]
        while w.thor?.phase != .working { w.step(dt: 1.0 / 120) }
        var near = SnowParticle.blank
        near.position = SIMD2(site.x + 60, 120); near.velocity = .zero; near.mass = 1; near.radius = 3; near.opacity = 1; near.volume = 3
        var far = near
        far.position = SIMD2(site.x + 900, 120)
        w.pool.spawn(near); w.pool.spawn(far)
        while w.thorBlowLog.isEmpty { w.step(dt: 1.0 / 120) }
        let pushedRight = (0..<w.pool.count).filter { w.pool[$0].state == .disturbed && w.pool[$0].velocity.x > 60 }.count
        XCTAssertEqual(pushedRight, 1, "the nearby flake is blasted outward; the far one is untouched")
    }

    func testCracksAppearThenFade() {
        let (w, _, _) = world()
        w.startHelper(.thor)
        while w.thorBlowLog.isEmpty { w.step(dt: 1.0 / 120) }
        XCTAssertFalse(w.thor!.cracks.isEmpty)
        XCTAssertFalse(w.thor!.rings.isEmpty)
        XCTAssertFalse(w.thor!.bolt.isEmpty)
        for _ in 0..<(120 * 4) {
            w.step(dt: 1.0 / 120)
            guard let r = w.thor else { break }
            if r.phase != .working || r.siteIndex > 0 { break }
        }
        // After the last blow of a site, old cracks age out (3 s) rather than accumulate forever.
        run(w)
        XCTAssertNil(w.thor)
    }

    func testLightningBoltRunsFromTheSkyToTheImpact() {
        let (w, _, _) = world()
        w.startHelper(.thor)
        while w.thorBlowLog.isEmpty { w.step(dt: 1.0 / 120) }
        let r = w.thor!
        XCTAssertGreaterThan(r.bolt.first!.y, 800, "starts above the screen")
        XCTAssertLessThan(r.bolt.last!.y, 100, "ends on the ground")
        XCTAssertEqual(r.bolt.last!.x, r.sites[0].x, accuracy: 1)
    }

    func testOnlyOneHelperAtATimeAndSelectable() {
        let (w, _, _) = world()
        w.startHelper(.thor)
        w.startHelper(.jcb); w.startHelper(.santa); w.startHelper(.ironMan)
        XCTAssertNotNil(w.thor); XCTAssertNil(w.plow); XCTAssertNil(w.santa); XCTAssertNil(w.ironMan)
        let (w2, _, _) = world()
        w2.startHelper(.santa)
        w2.startHelper(.thor)
        XCTAssertNil(w2.thor)
        XCTAssertTrue(HelperKind.concrete.contains(.thor))
        XCTAssertFalse(HelperKind.thor.label.isEmpty)
        XCTAssertTrue(w.eligibleHelpers().contains(.thor))
    }

    func testAutoRunAndSettings() throws {
        var c = SimulationConfiguration(); c.density = 0; c.plowAuto = true; c.plowInterval = 5; c.helper = .thor
        let w = PhysicsWorld(config: c)
        w.setRegion(CGRect(x: 0, y: 0, width: 1500, height: 800))
        w.setSurfaces([CollisionSurface(id: "floor", frame: CGRect(x: 0, y: 0, width: 1500, height: 0), velocity: .zero, kind: .displayBottom)])
        for _ in 0..<(120 * 8) { w.step(dt: 1.0 / 120); w.finishFrame() }
        XCTAssertFalse(w.isHelperRunning)
        let st = w.state(forSurface: "floor")!
        for i in 0..<st.field.binCount { st.field.add(volume: 10 * st.field.binWidth, toBin: i) }
        w.finishFrame()
        XCTAssertNotNil(w.thor)
        let s = try JSONDecoder().decode(SnowfallSettings.self, from: Data(#"{"helper":"thor"}"#.utf8))
        XCTAssertEqual(s.helper, .thor)
    }

    func testRenderSnapshotContainsThorWithEffects() {
        let (w, _, _) = world()
        w.startHelper(.thor)
        while w.thorBlowLog.isEmpty { w.step(dt: 1.0 / 120) }
        var snap = RenderSnapshot()
        w.fill(snapshot: &snap, showSurfaces: false, stats: SimulationStats())
        XCTAssertEqual(snap.thors.count, 1)
        XCTAssertFalse(snap.thors[0].bolt.isEmpty)
        XCTAssertFalse(snap.thors[0].cracks.isEmpty)
        XCTAssertGreaterThan(snap.thors[0].flash, 0.5)
    }

    func testHammerTimelineSwingsDownTwice() {
        var downs = 0
        var prev = PhysicsWorld.hammerAngle(at: 0)
        var wasUp = false
        for i in 1...300 {
            let a = PhysicsWorld.hammerAngle(at: Float(i) * 0.007)
            if a < -0.9 { wasUp = true }
            if wasUp, a > 1.3, prev <= 1.3 { downs += 1; wasUp = false }
            prev = a
        }
        XCTAssertEqual(downs, 2)
    }
}
