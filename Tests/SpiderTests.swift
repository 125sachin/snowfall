import XCTest
import simd
@testable import Snowfall

final class SpiderTests: XCTestCase {
    private func world(width: CGFloat = 2400, snow: Float = 20, windowSnow: Float = 0, seed: UInt64 = 1) -> (PhysicsWorld, SurfaceState, SurfaceState?) {
        var c = SimulationConfiguration(); c.density = 0; c.plowAuto = false; c.helper = .spiderMan; c.windStrength = 0; c.turbulence = 0; c.seed = seed
        let w = PhysicsWorld(config: c)
        w.setRegion(CGRect(x: 0, y: 0, width: width, height: 900))
        var surfaces = [CollisionSurface(id: "floor", frame: CGRect(x: 0, y: 0, width: width, height: 0), velocity: .zero, kind: .displayBottom)]
        if windowSnow > 0 {
            surfaces.append(CollisionSurface(id: "win", frame: CGRect(x: 600, y: 200, width: 700, height: 300), velocity: .zero, kind: .windowTop, zRank: 0))
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

    func testSwingsInFromTheRightAndHeadsLeft() {
        let (w, _, _) = world()
        w.startHelper(.spiderMan)
        XCTAssertNotNil(w.spider)
        let startX = w.spider!.pos.x
        XCTAssertGreaterThan(startX, 2400)
        var furthestRight = startX
        for _ in 0..<(120 * 6) {
            w.step(dt: 1.0 / 120)
            if let s = w.spider { furthestRight = max(furthestRight, s.pos.x) }
        }
        XCTAssertLessThan(w.spider?.pos.x ?? 0, startX - 600, "makes steady progress leftward")
        XCTAssertLessThanOrEqual(furthestRight, startX + 40, "never goes back to the right")
    }

    func testRopeLengthIsRespectedWhileSwinging() {
        let (w, _, _) = world()
        w.startHelper(.spiderMan)
        for _ in 0..<(120 * 8) {
            w.step(dt: 1.0 / 120)
            guard let s = w.spider, s.attached, s.phase == .swinging else { continue }
            XCTAssertLessThanOrEqual(simd_length(s.pos - s.anchor), s.rope + 0.5)
        }
    }

    func testAnchorsMoveLeftAndAreAboveHim() {
        let (w, _, _) = world()
        w.startHelper(.spiderMan)
        run(w)
        let anchors = w.spiderAnchorLog
        XCTAssertGreaterThanOrEqual(anchors.count, 4, "chains several swings across the screen")
        for (a, b) in zip(anchors, anchors.dropFirst()) { XCTAssertLessThan(b.x, a.x, "each web is further left") }
    }

    func testArcBottomSkimsTheSnowSurface() {
        let (w, _, _) = world(snow: 25)
        w.startHelper(.spiderMan)
        var lowestFeet: Float = .infinity
        for _ in 0..<(120 * 14) {
            w.step(dt: 1.0 / 120)
            if let s = w.spider, s.phase == .swinging, s.pos.x < 2000, s.pos.x > 300 {
                lowestFeet = min(lowestFeet, s.pos.y - SpiderMetrics.feetDrop)
            }
        }
        XCTAssertLessThan(lowestFeet, 40, "feet come down to the snow at the bottom of a swing (lowest \(lowestFeet))")
        XCTAssertGreaterThanOrEqual(lowestFeet, -1, "but never through the ground")
    }

    func testFeetScrapeAFurrowThroughTheSnow() {
        let (w, floor, _) = world(snow: 30)
        let before = floor.field.volume
        w.startHelper(.spiderMan)
        run(w)
        XCTAssertLessThan(floor.field.volume, before * 0.9, "he removes snow")
        XCTAssertGreaterThan(floor.field.volume, before * 0.2, "but he does not wipe out the whole floor by scraping alone")
    }

    func testWebBallLandsOnAPileThenYankTearsItOff() {
        let (w, floor, _) = world(snow: 5)
        // One tall pile for him to target.
        floor.field.deposit(localX: 1500, volume: 6000, spreadBins: 70)
        w.startHelper(.spiderMan)
        var patch: SpiderPatch?
        var removedBefore: Float = 0
        for _ in 0..<(120 * 9) {
            w.step(dt: 1.0 / 120)
            if let p = w.spider?.patches.first, patch == nil { patch = p; removedBefore = floor.field.height(atLocalX: p.x) }
        }
        guard let p = patch else { return XCTFail("no web ball landed") }
        XCTAssertGreaterThan(removedBefore, 10, "it targeted the pile")
        XCTAssertLessThan(floor.field.height(atLocalX: p.x), 1.5, "the clump is gone after the yank")
    }

    func testBallsPickTheBiggestPileAhead() {
        let (w, floor, _) = world(snow: 0.5)
        floor.field.deposit(localX: 1000, volume: 800, spreadBins: 30)
        floor.field.deposit(localX: 1600, volume: 5000, spreadBins: 40)
        let pile = w.bestPile(from: 400, to: 2300)
        XCTAssertNotNil(pile)
        XCTAssertEqual(pile!.x, 1600, accuracy: 90)
        XCTAssertNil(w.bestPile(from: 5000, to: 6000))
    }

    func testNetCatchesAirborneFlakesAndLeavesOthers() {
        let (w, _, _) = world(snow: 0)
        w.startHelper(.spiderMan)
        var caught = false
        for _ in 0..<(120 * 10) {
            w.step(dt: 1.0 / 120)
            guard let n = w.spider?.net, n.age < 0.1 else { continue }
            var inside = SnowParticle.blank
            inside.position = n.center; inside.mass = 1; inside.radius = 3; inside.opacity = 1; inside.volume = 4
            var outside = inside
            outside.position = n.center + SIMD2(0, 700)
            let lostBefore = w.totals.lostVolume
            w.pool.spawn(inside); w.pool.spawn(outside)
            w.step(dt: 1.0 / 120)
            XCTAssertGreaterThanOrEqual(w.totals.lostVolume - lostBefore, 4 - 0.001, "its snow is removed")
            XCTAssertTrue((0..<w.pool.count).contains { w.pool[$0].state == .falling && abs(w.pool[$0].position.y - outside.position.y) < 80 },
                          "flake far from the net is untouched")
            caught = true
            break
        }
        XCTAssertTrue(caught, "he spins a net")
    }

    func testVolumeIsAccountedFor() {
        let (w, floor, win) = world(snow: 15, windowSnow: 12)
        let initial = floor.field.volume + win!.field.volume
        w.startHelper(.spiderMan)
        run(w)
        for _ in 0..<(120 * 3) { w.step(dt: 1.0 / 120); w.finishFrame() }
        let accounted = floor.field.volume + win!.field.volume + w.totals.lostVolume + w.totals.clippedVolume + w.totals.droppedVolume
        XCTAssertEqual(accounted, initial, accuracy: initial * 0.03)
    }

    func testDebrisFadesAndPoolStaysBounded() {
        let (w, _, _) = world(snow: 30)
        w.startHelper(.spiderMan)
        var t: Float = 0
        while w.isHelperRunning && t < 120 {
            w.step(dt: 1.0 / 120); w.finishFrame(); t += 1.0 / 120
            XCTAssertLessThanOrEqual(w.pool.count, w.pool.capacity)
        }
        for _ in 0..<(120 * 2) { w.step(dt: 1.0 / 120) }
        XCTAssertEqual((0..<w.pool.count).filter { w.pool[$0].orbitRadius < 0 }.count, 0)
    }

    func testFinishesAndLeaves() {
        let (w, _, _) = world(snow: 8)
        w.startHelper(.spiderMan)
        let t = run(w)
        XCTAssertLessThan(t, 80)
        XCTAssertNil(w.spider)
    }

    func testOnlyOneHelperAtATimeAndSelectable() {
        let (w, _, _) = world()
        w.startHelper(.spiderMan)
        w.startHelper(.thor); w.startHelper(.jcb); w.startHelper(.santa); w.startHelper(.ironMan)
        XCTAssertNotNil(w.spider)
        XCTAssertNil(w.thor); XCTAssertNil(w.plow); XCTAssertNil(w.santa); XCTAssertNil(w.ironMan)
        let (w2, _, _) = world()
        w2.startHelper(.thor)
        w2.startHelper(.spiderMan)
        XCTAssertNil(w2.spider)
        XCTAssertTrue(HelperKind.concrete.contains(.spiderMan))
        XCTAssertFalse(HelperKind.spiderMan.label.isEmpty)
        XCTAssertTrue(w.eligibleHelpers().contains(.spiderMan))
    }

    func testAutoRunAndSettings() throws {
        var c = SimulationConfiguration(); c.density = 0; c.plowAuto = true; c.plowInterval = 5; c.helper = .spiderMan
        let w = PhysicsWorld(config: c)
        w.setRegion(CGRect(x: 0, y: 0, width: 1500, height: 800))
        w.setSurfaces([CollisionSurface(id: "floor", frame: CGRect(x: 0, y: 0, width: 1500, height: 0), velocity: .zero, kind: .displayBottom)])
        for _ in 0..<(120 * 8) { w.step(dt: 1.0 / 120); w.finishFrame() }
        XCTAssertFalse(w.isHelperRunning)
        let st = w.state(forSurface: "floor")!
        for i in 0..<st.field.binCount { st.field.add(volume: 10 * st.field.binWidth, toBin: i) }
        w.finishFrame()
        XCTAssertNotNil(w.spider)
        let s = try JSONDecoder().decode(SnowfallSettings.self, from: Data(#"{"helper":"spiderMan"}"#.utf8))
        XCTAssertEqual(s.helper, .spiderMan)
    }

    func testRenderSnapshotContainsSpiderWithWeb() {
        let (w, _, _) = world(snow: 10)
        w.startHelper(.spiderMan)
        for _ in 0..<(120 * 3) { w.step(dt: 1.0 / 120) }
        var snap = RenderSnapshot()
        w.fill(snapshot: &snap, showSurfaces: false, stats: SimulationStats())
        XCTAssertEqual(snap.spiders.count, 1)
        XCTAssertTrue(snap.spiders[0].attached)
        XCTAssertGreaterThan(snap.spiders[0].anchor.y, snap.spiders[0].y, "the web goes up to an anchor above him")
    }

    func testWindowTopsAreScrapedToo() {
        let (w, _, win) = world(snow: 0.5, windowSnow: 30)
        let before = win!.field.volume
        w.startHelper(.spiderMan)
        run(w)
        XCTAssertLessThan(win!.field.volume, before)
    }
}
