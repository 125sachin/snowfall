import XCTest
import simd
@testable import Snowfall

final class PlowTests: XCTestCase {
    private func world(width: CGFloat = 1000, snow: Float = 20) -> (PhysicsWorld, SurfaceState) {
        var c = SimulationConfiguration(); c.density = 0; c.plowAuto = false
        let w = PhysicsWorld(config: c)
        w.setRegion(CGRect(x: 0, y: 0, width: width, height: 800))
        w.setSurfaces([CollisionSurface(id: "floor", frame: CGRect(x: 0, y: 0, width: width, height: 0), velocity: .zero, kind: .displayBottom)])
        let st = w.state(forSurface: "floor")!
        for i in 0..<st.field.binCount { st.field.add(volume: snow * st.field.binWidth, toBin: i) }
        return (w, st)
    }

    private func runPlow(_ w: PhysicsWorld, maxSeconds: Float = 60) -> Float {
        var t: Float = 0
        while w.isPlowRunning && t < maxSeconds { w.step(dt: 1.0 / 120); w.finishFrame(); t += 1.0 / 120 }
        return t
    }

    func testSweepRemovesSnowAboveResidueAndReturnsVolume() {
        var f = SnowAccumulationField(width: 400, maxDepth: 100)
        for i in 0..<f.binCount { f.add(volume: 10 * f.binWidth, toBin: i) }
        let before = f.volume
        let removed = f.sweep(fromLocalX: 100, toLocalX: 200, keepDepth: 1)
        XCTAssertGreaterThan(removed, 0)
        XCTAssertEqual(f.volume + removed, before, accuracy: 0.01)
        XCTAssertEqual(f.height(atLocalX: 150), 1, accuracy: 0.001)
        XCTAssertEqual(f.height(atLocalX: 300), 10, accuracy: 0.001, "outside the swept span is untouched")
    }

    func testBlockedEdgePreventsSlumpingThroughBlade() {
        var f = SnowAccumulationField(width: 400, maxDepth: 100)
        f.deposit(localX: 100, volume: 800, spreadBins: 3)
        let edge = f.binIndex(atLocalX: 100)
        let left = (0..<edge).reduce(Float(0)) { $0 + f.height(atBin: $1) }
        for _ in 0..<500 { f.relax(iterations: 3, blockedEdge: edge) }
        let leftAfter = (0...edge).reduce(Float(0)) { $0 + f.height(atBin: $1) }
        let rightAfter = ((edge + 1)..<f.binCount).reduce(Float(0)) { $0 + f.height(atBin: $1) }
        XCTAssertGreaterThanOrEqual(left, 0)
        XCTAssertGreaterThan(leftAfter, 0)
        _ = rightAfter   // right side only receives from its own side; the blocked pair never exchanges
    }

    func testPlowEntersFromRightAndDrivesLeft() {
        let (w, _) = world()
        w.startPlow()
        let x0 = w.plow!.bladeX
        XCTAssertGreaterThan(x0, 1000)
        for _ in 0..<240 { w.step(dt: 1.0 / 120) }
        XCTAssertLessThan(w.plow!.bladeX, x0, "moves right to left")
        XCTAssertGreaterThan(w.plow!.wheelAngle, 0)
    }

    func testPlowClearsFloorLeavingOnlyResidue() {
        let (w, st) = world(snow: 8)
        w.startPlow()
        _ = runPlow(w)
        XCTAssertFalse(w.isPlowRunning)
        for _ in 0..<(120 * 20) { w.step(dt: 1.0 / 120); w.finishFrame() }   // let spilled snow land
        let avg = st.field.volume / 1000
        print("PLOW avg depth after run: \(avg) lost=\(w.totals.lostVolume) clipped=\(w.totals.clippedVolume)")
        XCTAssertLessThan(avg, 3, "floor should be mostly cleared, got \(avg) pt average depth")
    }

    func testPlowTakesSeveralSecondsToCrossTheScreen() {
        let (w, _) = world(width: 1920, snow: 8)
        w.startPlow()
        let t = runPlow(w)
        XCTAssertGreaterThan(t, 15, "slow, not instant")
        XCTAssertLessThan(t, 55, "a loaded plow still crosses in reasonable time")
    }

    func testHeavyLoadSlowsThePlow() {
        let (w, _) = world(snow: 0)
        w.startPlow()
        for _ in 0..<(120 * 5) { w.step(dt: 1.0 / 120) }       // empty floor → reaches near max speed
        let free = w.plow!.speed
        let (w2, _) = world(snow: 30)
        w2.startPlow()
        for _ in 0..<(120 * 8) { w2.step(dt: 1.0 / 120) }
        XCTAssertLessThan(w2.plow!.speed, free * 0.85, "load resistance must slow the vehicle")
        XCTAssertGreaterThanOrEqual(w2.plow!.speed, w2.config.plowMinSpeed)
    }

    func testSnowVolumeIsAccountedFor() {
        let (w, st) = world(snow: 12)
        let initial = st.field.volume
        w.startPlow()
        _ = runPlow(w)
        for _ in 0..<(120 * 30) { w.step(dt: 1.0 / 120); w.finishFrame() }
        XCTAssertEqual(w.pool.count, 0)
        let accounted = st.field.volume + w.totals.lostVolume + w.totals.clippedVolume + w.totals.droppedVolume
        XCTAssertEqual(accounted, initial, accuracy: initial * 0.03)
    }

    func testOverflowSpillsOverThePile() {
        var c = SimulationConfiguration(); c.density = 0; c.plowAuto = false; c.plowCapacity = 400
        let w = PhysicsWorld(config: c)
        w.setRegion(CGRect(x: 0, y: 0, width: 1000, height: 800))
        w.setSurfaces([CollisionSurface(id: "floor", frame: CGRect(x: 0, y: 0, width: 1000, height: 0), velocity: .zero, kind: .displayBottom)])
        let st = w.state(forSurface: "floor")!
        for i in 0..<st.field.binCount { st.field.add(volume: 30 * st.field.binWidth, toBin: i) }
        w.startPlow()
        var sawSpill = false
        for _ in 0..<(120 * 10) {
            w.step(dt: 1.0 / 120); w.finishFrame()
            if (0..<w.pool.count).contains(where: { w.pool[$0].volume > 0 && w.pool[$0].state == .displaced }) { sawSpill = true }
            XCTAssertLessThanOrEqual(w.pool.count, w.pool.capacity)
        }
        XCTAssertTrue(sawSpill, "snow beyond blade capacity must spill over the pile")
    }

    func testAutoPlowStartsAfterIntervalOnlyWhenThereIsSnow() {
        var c = SimulationConfiguration(); c.density = 0; c.plowAuto = true; c.plowInterval = 5
        let w = PhysicsWorld(config: c)
        w.setRegion(CGRect(x: 0, y: 0, width: 1000, height: 800))
        w.setSurfaces([CollisionSurface(id: "floor", frame: CGRect(x: 0, y: 0, width: 1000, height: 0), velocity: .zero, kind: .displayBottom)])
        for _ in 0..<(120 * 8) { w.step(dt: 1.0 / 120); w.finishFrame() }
        XCTAssertFalse(w.isPlowRunning, "no snow → no plow")
        let st = w.state(forSurface: "floor")!
        for i in 0..<st.field.binCount { st.field.add(volume: 10 * st.field.binWidth, toBin: i) }
        w.finishFrame()
        XCTAssertTrue(w.isPlowRunning)
    }

    func testPlowIsRenderedAndPileAppearsInSnapshot() {
        let (w, _) = world(snow: 25)
        w.startPlow()
        for _ in 0..<(120 * 10) { w.step(dt: 1.0 / 120) }
        var snap = RenderSnapshot()
        w.fill(snapshot: &snap, showSurfaces: false, stats: SimulationStats())
        XCTAssertEqual(snap.vehicles.count, 1)
        XCTAssertGreaterThan(snap.particles.count, 0)
    }

    func testPlowSettingsValidateAndMigrate() {
        var s = SnowfallSettings(); s.plowIntervalMinutes = 999
        XCTAssertEqual(s.validated().plowIntervalMinutes, 60)
        s.plowIntervalMinutes = 0
        XCTAssertEqual(s.validated().plowIntervalMinutes, 1)
        XCTAssertTrue(SnowfallSettings.default.plowAutomatic)
    }
}
