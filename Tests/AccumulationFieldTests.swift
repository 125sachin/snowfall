import XCTest
@testable import Snowfall

final class AccumulationFieldTests: XCTestCase {
    func testBinCountIsBounded() {
        XCTAssertEqual(SnowAccumulationField.binCount(forWidth: 100000), SnowAccumulationField.maxBins)
        XCTAssertGreaterThanOrEqual(SnowAccumulationField.binCount(forWidth: 1), 4)
    }

    func testDepositConservesVolume() {
        var f = SnowAccumulationField(width: 400, maxDepth: 100)
        f.deposit(localX: 200, volume: 40, spreadBins: 5)
        XCTAssertEqual(f.volume, 40, accuracy: 0.001)
        XCTAssertGreaterThan(f.height(atLocalX: 200), f.height(atLocalX: 100))
    }

    func testDepositAtEdgeStillConserves() {
        var f = SnowAccumulationField(width: 400, maxDepth: 100)
        f.deposit(localX: 0, volume: 10, spreadBins: 9)
        XCTAssertEqual(f.volume, 10, accuracy: 0.001)
    }

    func testRelaxConservesVolumeAndFlattensSpike() {
        var f = SnowAccumulationField(width: 400, maxDepth: 1000)
        f.deposit(localX: 200, volume: 2000, spreadBins: 3)
        let v = f.volume
        let peak = f.height(atLocalX: 200)
        for _ in 0..<200 { f.relax(iterations: 3) }
        XCTAssertEqual(f.volume, v, accuracy: v * 0.001)
        XCTAssertLessThan(f.height(atLocalX: 200), peak)
    }

    func testRelaxStopsAtReposeSlope() {
        var f = SnowAccumulationField(width: 400, maxDepth: 1000)
        f.deposit(localX: 200, volume: 500, spreadBins: 3)
        for _ in 0..<2000 { f.relax(iterations: 3) }
        for i in 0..<(f.binCount - 1) {
            XCTAssertLessThanOrEqual(abs(f.height(atBin: i) - f.height(atBin: i + 1)), f.reposeSlope * f.binWidth + 0.01)
        }
    }

    func testMaxDepthClipReportsVolume() {
        var f = SnowAccumulationField(width: 400, maxDepth: 10)
        f.deposit(localX: 200, volume: 1000, spreadBins: 3)
        let before = f.volume
        let clipped = f.clipToMaxDepth()
        XCTAssertGreaterThan(clipped, 0)
        XCTAssertEqual(f.volume + clipped, before, accuracy: 0.01)
        for i in 0..<f.binCount { XCTAssertLessThanOrEqual(f.height(atBin: i), 10.0001) }
    }

    func testClear() {
        var f = SnowAccumulationField(width: 400, maxDepth: 10)
        f.deposit(localX: 10, volume: 5)
        f.clear()
        XCTAssertTrue(f.isEmpty)
    }

    func testEdgeShedConservesAndIsBounded() {
        var f = SnowAccumulationField(width: 400, maxDepth: 40)
        f.deposit(localX: 2, volume: 200, spreadBins: 3)
        let before = f.volume
        let shed = f.shedEdges(edgeBins: 3, edgeLimit: 5, minVolume: 1, maxVolume: 30)
        XCTAssertGreaterThan(shed.left, 0)
        XCTAssertEqual(shed.right, 0)
        XCTAssertLessThanOrEqual(shed.left, 30.001)
        XCTAssertEqual(f.volume + shed.left, before, accuracy: 0.01)
    }

    func testEdgeShedBelowThresholdKeepsSnow() {
        var f = SnowAccumulationField(width: 400, maxDepth: 40)
        f.deposit(localX: 200, volume: 20, spreadBins: 3)
        let shed = f.shedEdges(edgeBins: 3, edgeLimit: 5, minVolume: 1, maxVolume: 30)
        XCTAssertEqual(shed.left + shed.right, 0)
    }

    func testRemapConservesVolume() {
        var f = SnowAccumulationField(width: 400, maxDepth: 100)
        f.deposit(localX: 100, volume: 60, spreadBins: 5)
        let r = f.remapped(toWidth: 800)
        XCTAssertEqual(r.field.volume + r.clipped, 60, accuracy: 0.05)
        let r2 = f.remapped(toWidth: 200)
        XCTAssertEqual(r2.field.volume + r2.clipped, 60, accuracy: 0.05)
    }

    func testHeightInterpolationIsContinuous() {
        var f = SnowAccumulationField(width: 400, maxDepth: 100)
        f.deposit(localX: 200, volume: 100, spreadBins: 3)
        XCTAssertEqual(f.height(atLocalX: 200), f.height(atLocalX: 200.01), accuracy: 0.5)
    }

    func testWorldDepositSkippedWhenAccumulationDisabled() {
        var c = SimulationConfiguration(); c.density = 0; c.accumulationEnabled = false
        let w = PhysicsWorld(config: c)
        w.setSurfaces([CollisionSurface(id: "d", frame: CGRect(x: 0, y: 0, width: 400, height: 0), velocity: .zero, kind: .displayBottom)])
        var s = SnowParticle.blank
        s.position = SIMD2(100, 0.2); s.velocity = SIMD2(0, -200); s.mass = 1; s.volume = 5
        w.pool.spawn(s)
        w.step(dt: 1.0 / 120)
        XCTAssertEqual(w.state(forSurface: "d")!.field.volume, 0)
    }

    func testSnowAccumulatesOnDisplayBottomOverTime() {
        var c = SimulationConfiguration(); c.density = 1; c.maxParticles = 400; c.seed = 3
        let w = PhysicsWorld(config: c)
        w.setRegion(CGRect(x: 0, y: 0, width: 800, height: 600))
        w.setSurfaces([CollisionSurface(id: "d", frame: CGRect(x: 0, y: 0, width: 800, height: 0), velocity: .zero, kind: .displayBottom)])
        w.prewarm()
        for _ in 0..<(120 * 20) { w.step(dt: 1.0 / 120); w.finishFrame() }
        XCTAssertGreaterThan(w.settledVolume, 100)
        w.clearSnow()
        XCTAssertEqual(w.settledVolume, 0)
    }
}
