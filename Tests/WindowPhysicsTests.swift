import XCTest
import simd
@testable import Snowfall

/// Moving-window displacement and surface lifecycle.
final class WindowPhysicsTests: XCTestCase {
    private let frame = CGRect(x: 100, y: 300, width: 600, height: 400)

    private func surface(_ f: CGRect, v: CGVector = .zero) -> CollisionSurface {
        CollisionSurface(id: "win", frame: f, velocity: v, kind: .windowTop)
    }

    private func pile(_ f: CGRect, volume: Float = 400) -> SnowAccumulationField {
        var field = SnowAccumulationField(width: Float(f.width), maxDepth: 40)
        field.deposit(localX: Float(f.width) / 2, volume: volume, spreadBins: 41)
        return field
    }

    private func total(_ r: DisplacementResult) -> Float { r.retainedVolume + r.displacedVolume + r.clippedVolume }

    func testStationaryWindowKeepsSnow() {
        let f = pile(frame)
        let r = SnowDisplacementSolver.displace(field: f, oldFrame: frame, newFrame: frame, velocity: .zero, stickSpeed: 350, maxClusters: 24)
        XCTAssertEqual(r.displacedVolume, 0, accuracy: 1e-3)
        XCTAssertEqual(r.retainedVolume, f.volume, accuracy: 0.1)
    }

    func testSlowDragCarriesSnow() {
        let f = pile(frame)
        let moved = frame.offsetBy(dx: 20, dy: 0)
        let r = SnowDisplacementSolver.displace(field: f, oldFrame: frame, newFrame: moved, velocity: CGVector(dx: 100, dy: 0), stickSpeed: 350, maxClusters: 24)
        XCTAssertEqual(r.displacedVolume, 0, accuracy: 1e-3)
    }

    func testFastHorizontalMoveDisplacesUnsupportedSnow() {
        var f = SnowAccumulationField(width: 600, maxDepth: 40)
        f.deposit(localX: 590, volume: 200, spreadBins: 21)      // pile near right edge
        let moved = frame.offsetBy(dx: -300, dy: 0)               // window flicked left
        let r = SnowDisplacementSolver.displace(field: f, oldFrame: frame, newFrame: moved, velocity: CGVector(dx: -1200, dy: 0), stickSpeed: 350, maxClusters: 24)
        XCTAssertGreaterThan(r.displacedVolume, 0)
        XCTAssertEqual(total(r), f.volume, accuracy: f.volume * 0.01)
        XCTAssertLessThanOrEqual(r.clusters.count, 24)
        // Clusters start where the snow was (old frame), not teleported to the new window.
        for c in r.clusters { XCTAssertGreaterThan(c.position.x, Float(frame.minX)) }
    }

    func testVerticalMoveShedsSnow() {
        let f = pile(frame)
        let moved = frame.offsetBy(dx: 0, dy: -150)
        let r = SnowDisplacementSolver.displace(field: f, oldFrame: frame, newFrame: moved, velocity: CGVector(dx: 0, dy: -1000), stickSpeed: 350, maxClusters: 24)
        XCTAssertGreaterThan(r.displacedVolume, 0)
        XCTAssertEqual(total(r), f.volume, accuracy: f.volume * 0.01)
    }

    func testResizeRemapsConservatively() {
        let f = pile(frame)
        let narrower = CGRect(x: frame.minX, y: frame.minY, width: 200, height: frame.height)
        let r = SnowDisplacementSolver.displace(field: f, oldFrame: frame, newFrame: narrower, velocity: .zero, stickSpeed: 350, maxClusters: 24)
        XCTAssertEqual(r.field.width, 200)
        XCTAssertGreaterThan(r.displacedVolume, 0, "snow outside the new width must fall")
        XCTAssertEqual(total(r), f.volume, accuracy: f.volume * 0.01)
    }

    func testReleaseIsBoundedAndConservesVolume() {
        let f = pile(frame)
        let clusters = SnowDisplacementSolver.release(field: f, frame: frame, maxClusters: 24)
        XCTAssertLessThanOrEqual(clusters.count, 24)
        XCTAssertEqual(clusters.reduce(0) { $0 + $1.volume }, f.volume, accuracy: f.volume * 0.001)
    }

    func testWorldClosingWindowReleasesSnowAsFallingParticles() {
        var c = SimulationConfiguration(); c.density = 0
        let w = PhysicsWorld(config: c)
        w.setSurfaces([surface(frame)])
        w.state(forSurface: "win")!.field.deposit(localX: 300, volume: 300, spreadBins: 31)
        let vol = w.state(forSurface: "win")!.field.volume
        w.setSurfaces([])
        XCTAssertGreaterThan(w.pool.count, 0)
        XCTAssertLessThanOrEqual(w.pool.count, c.maxDisplacementClusters)
        let released = (0..<w.pool.count).reduce(Float(0)) { $0 + w.pool[$1].volume }
        XCTAssertEqual(released, vol, accuracy: vol * 0.01)
    }

    func testDisplacedSnowLandsOnLowerSurface() {
        var c = SimulationConfiguration(); c.density = 0; c.windStrength = 0; c.turbulence = 0
        let w = PhysicsWorld(config: c)
        let ground = CollisionSurface(id: "ground", frame: CGRect(x: -1000, y: 0, width: 4000, height: 0), velocity: .zero, kind: .displayBottom)
        w.setSurfaces([ground, surface(frame)])
        w.state(forSurface: "win")!.field.deposit(localX: 300, volume: 200, spreadBins: 31)
        w.setSurfaces([ground])   // window disappears
        for _ in 0..<(120 * 30) { w.step(dt: 1.0 / 120); w.finishFrame() }
        XCTAssertEqual(w.pool.count, 0)
        let landed = w.state(forSurface: "ground")!.field.volume
        XCTAssertEqual(landed + w.totals.clippedVolume + w.totals.droppedVolume, 200, accuracy: 4)
    }

    func testRapidMovementStaysBoundedAndStable() {
        var c = SimulationConfiguration(); c.density = 0
        let w = PhysicsWorld(config: c)
        w.setSurfaces([surface(frame)])
        w.state(forSurface: "win")!.field.deposit(localX: 300, volume: 400, spreadBins: 41)
        var f = frame
        for i in 0..<200 {
            f = f.offsetBy(dx: i.isMultiple(of: 2) ? 400 : -400, dy: i.isMultiple(of: 3) ? 100 : -100)
            w.setSurfaces([surface(f, v: CGVector(dx: 5000, dy: 3000))])
            w.step(dt: 1.0 / 120)
            XCTAssertLessThanOrEqual(w.pool.count, w.pool.capacity)
        }
        for i in 0..<w.pool.count { XCTAssertTrue(w.pool[i].position.x.isFinite) }
    }

    func testEdgeOverflowEmitsBoundedParticlesNotUnlimited() {
        var c = SimulationConfiguration(); c.density = 0
        let w = PhysicsWorld(config: c)
        w.setSurfaces([surface(frame)])
        w.state(forSurface: "win")!.field.deposit(localX: 1, volume: 400, spreadBins: 5)
        w.surfaceStates.first!.dirty = true
        w.finishFrame()
        XCTAssertLessThanOrEqual(w.pool.count, 2)
    }

    func testDisplayResizeRemapsField() {
        var c = SimulationConfiguration(); c.density = 0
        let w = PhysicsWorld(config: c)
        let d1 = CollisionSurface(id: "d", frame: CGRect(x: 0, y: 0, width: 1000, height: 0), velocity: .zero, kind: .displayBottom)
        w.setSurfaces([d1])
        w.state(forSurface: "d")!.field.deposit(localX: 500, volume: 100, spreadBins: 9)
        w.setSurfaces([CollisionSurface(id: "d", frame: CGRect(x: 0, y: 0, width: 2000, height: 0), velocity: .zero, kind: .displayBottom)])
        XCTAssertEqual(w.state(forSurface: "d")!.field.volume, 100, accuracy: 0.5)
    }

    func testDisplayRemovalDropsItsStateWithoutParticles() {
        var c = SimulationConfiguration(); c.density = 0
        let w = PhysicsWorld(config: c)
        w.setSurfaces([CollisionSurface(id: "d", frame: CGRect(x: 0, y: 0, width: 1000, height: 0), velocity: .zero, kind: .displayBottom)])
        w.setSurfaces([])
        XCTAssertEqual(w.surfaceCount, 0)
        XCTAssertEqual(w.pool.count, 0)
    }
}

/// Window stacking: covered windows must not show snow; new top windows collect it.
final class WindowStackingTests: XCTestCase {
    private func surf(_ id: String, _ f: CGRect, z: Int) -> CollisionSurface {
        CollisionSurface(id: id, frame: f, velocity: .zero, kind: .windowTop, zRank: z)
    }

    func testZOrderMatchesByPidAndFrameAndDropsOffscreen() {
        func w(_ id: String, _ pid: pid_t, _ f: CGRect) -> WindowSnapshot {
            WindowSnapshot(id: id, processID: pid, frame: f, isVisible: true, isMinimized: false, timestamp: 0)
        }
        let a = CGRect(x: 100, y: 100, width: 500, height: 400)
        let b = CGRect(x: 300, y: 150, width: 500, height: 400)
        let r = WindowZOrder.apply(to: [w("a", 1, a), w("b", 2, b), w("gone", 3, a)],
                                   onScreen: [OnScreenWindow(pid: 2, frame: b.insetBy(dx: -2, dy: 0), rank: 0),
                                              OnScreenWindow(pid: 1, frame: a, rank: 1)])
        XCTAssertEqual(r.map(\.id).sorted(), ["a", "b"])
        XCTAssertEqual(r.first { $0.id == "b" }?.zRank, 0)
        XCTAssertEqual(r.first { $0.id == "a" }?.zRank, 1)
    }

    func testCoveredWindowSnowIsNotDrawn() {
        var c = SimulationConfiguration(); c.density = 0
        let w = PhysicsWorld(config: c)
        let back = CGRect(x: 0, y: 100, width: 600, height: 300)       // top y = 400
        let front = CGRect(x: 0, y: 200, width: 600, height: 400)      // top y = 600, covers back's top edge
        w.setSurfaces([surf("front", front, z: 0), surf("back", back, z: 1)])
        w.state(forSurface: "back")!.field.deposit(localX: 300, volume: 200, spreadBins: 21)
        var snap = RenderSnapshot()
        w.fill(snapshot: &snap, showSurfaces: false, stats: SimulationStats())
        XCTAssertTrue(snap.surfaces.count == 1)
        XCTAssertEqual(snap.heights.reduce(0, +), 0, "covered snow must be hidden")
        XCTAssertGreaterThan(w.state(forSurface: "back")!.field.volume, 0, "but it is kept")
    }

    func testUncoveredWindowSnowIsDrawn() {
        var c = SimulationConfiguration(); c.density = 0
        let w = PhysicsWorld(config: c)
        let a = CGRect(x: 0, y: 100, width: 600, height: 300)
        let b = CGRect(x: 800, y: 100, width: 600, height: 300)        // side by side
        w.setSurfaces([surf("a", a, z: 0), surf("b", b, z: 1)])
        w.state(forSurface: "b")!.field.deposit(localX: 300, volume: 200, spreadBins: 21)
        var snap = RenderSnapshot()
        w.fill(snapshot: &snap, showSurfaces: false, stats: SimulationStats())
        XCTAssertGreaterThan(snap.heights.reduce(0, +), 0)
    }

    func testSnowStacksOnNewTopWindow() {
        var c = SimulationConfiguration(); c.density = 0; c.windStrength = 0; c.turbulence = 0
        let w = PhysicsWorld(config: c)
        let back = CGRect(x: 0, y: 100, width: 600, height: 300)       // top 400
        let front = CGRect(x: 0, y: 200, width: 600, height: 400)      // top 600
        w.setSurfaces([surf("front", front, z: 0), surf("back", back, z: 1)])
        var s = SnowParticle.blank
        s.position = SIMD2(300, 600.5); s.velocity = SIMD2(0, -400); s.mass = 1; s.volume = 5
        w.pool.spawn(s)
        w.step(dt: 1.0 / 120)
        XCTAssertEqual(w.state(forSurface: "front")!.field.volume, 5, accuracy: 0.01)
        XCTAssertEqual(w.state(forSurface: "back")!.field.volume, 0, accuracy: 0.001)
    }

    func testSnowReappearsWhenCoverLeaves() {
        var c = SimulationConfiguration(); c.density = 0
        let w = PhysicsWorld(config: c)
        let back = CGRect(x: 0, y: 100, width: 600, height: 300)
        let front = CGRect(x: 0, y: 200, width: 600, height: 400)
        w.setSurfaces([surf("front", front, z: 0), surf("back", back, z: 1)])
        w.state(forSurface: "back")!.field.deposit(localX: 300, volume: 200, spreadBins: 21)
        w.setSurfaces([surf("back", back, z: 0)])
        var snap = RenderSnapshot()
        w.fill(snapshot: &snap, showSurfaces: false, stats: SimulationStats())
        XCTAssertGreaterThan(snap.heights.reduce(0, +), 0)
    }
}
