import XCTest
@testable import Snowfall

final class WindowGeometryTests: XCTestCase {
    private let primary = DisplayDescriptor(id: 1, uuid: "A", name: "Primary", frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                            visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 805), scale: 2)

    func testAXToAppKitOnPrimary() {
        let ax = CGRect(x: 100, y: 50, width: 400, height: 300)   // top-left origin
        let r = CoordinateSpace.appKitRect(fromAXRect: ax, primaryHeightPoints: 900)
        XCTAssertEqual(r, CGRect(x: 100, y: 550, width: 400, height: 300))
        XCTAssertEqual(r.maxY, 900 - 50)   // top edge
    }

    func testRoundTrip() {
        let r = CGRect(x: -300, y: 120, width: 640, height: 480)
        let ax = CoordinateSpace.axRect(fromAppKitRect: r, primaryHeightPoints: 900)
        XCTAssertEqual(CoordinateSpace.appKitRect(fromAXRect: ax, primaryHeightPoints: 900), r)
    }

    func testDisplayAbovePrimaryHasNegativeAXY() {
        // Secondary 1920x1080 placed above primary in AppKit space: y from 900 to 1980.
        let appKit = CGRect(x: 0, y: 900, width: 1920, height: 1080)
        let ax = CoordinateSpace.axRect(fromAppKitRect: appKit, primaryHeightPoints: 900)
        XCTAssertEqual(ax.minY, -1080)
    }

    func testDisplayLeftOfPrimaryHasNegativeX() {
        let appKit = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let ax = CoordinateSpace.axRect(fromAppKitRect: appKit, primaryHeightPoints: 900)
        XCTAssertEqual(ax.minX, -1920)
        XCTAssertEqual(ax.minY, 900 - 1080)
    }

    func testDisplayLocalAndPixelConversions() {
        let local = CoordinateSpace.displayLocalRect(fromGlobalPoints: CGRect(x: -1800, y: 100, width: 50, height: 50),
                                                     display: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(local, CGRect(x: 120, y: 100, width: 50, height: 50))
        XCTAssertEqual(CoordinateSpace.pixels(fromPoints: 100, scale: 2), 200)
        XCTAssertEqual(CoordinateSpace.points(fromPixels: 300, scale: 1.5), 200)
    }

    private func win(_ id: String, _ f: CGRect, pid: pid_t = 99, min: Bool = false, t: TimeInterval = 0) -> WindowSnapshot {
        WindowSnapshot(id: id, processID: pid, frame: f, isVisible: true, isMinimized: min, timestamp: t)
    }

    func testEligibilityFilters() {
        let ok = CGRect(x: 100, y: 200, width: 600, height: 400)
        func e(_ w: WindowSnapshot) -> Bool { WindowEligibility.isEligible(w, displays: [primary], ownPID: 1) }
        XCTAssertTrue(e(win("a", ok)))
        XCTAssertFalse(e(win("own", ok, pid: 1)), "own windows excluded")
        XCTAssertFalse(e(win("min", ok, min: true)))
        XCTAssertFalse(e(win("tiny", CGRect(x: 0, y: 200, width: 20, height: 20))))
        XCTAssertFalse(e(win("zero", .zero)))
        XCTAssertFalse(e(win("off", CGRect(x: 5000, y: 200, width: 600, height: 400))))
        XCTAssertFalse(e(win("maximized", CGRect(x: 0, y: 70, width: 1440, height: 805))), "top touches menu bar area")
    }

    func testSurfaceBuilderDedupesAndKeepsIdentity() {
        var b = SurfaceBuilder(ownPID: 1)
        let f = CGRect(x: 100, y: 200, width: 600, height: 400)
        let s = b.update(snapshots: [win("a", f), win("a", f)], displays: [primary])
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].id, "window-a")
        XCTAssertEqual(s[0].kind, .windowTop)
        XCTAssertEqual(s[0].frame.maxY, 600)
    }

    func testSurfaceBuilderEstimatesVelocity() {
        var b = SurfaceBuilder(ownPID: 1)
        _ = b.update(snapshots: [win("a", CGRect(x: 100, y: 200, width: 600, height: 400), t: 0)], displays: [primary])
        let s = b.update(snapshots: [win("a", CGRect(x: 150, y: 200, width: 600, height: 400), t: 0.5)], displays: [primary])
        XCTAssertEqual(s[0].velocity.dx, 100, accuracy: 0.01)
        XCTAssertEqual(s[0].velocity.dy, 0, accuracy: 0.01)
    }

    func testSurfaceBuilderDropsRemovedAndMinimized() {
        var b = SurfaceBuilder(ownPID: 1)
        let f = CGRect(x: 100, y: 200, width: 600, height: 400)
        XCTAssertEqual(b.update(snapshots: [win("a", f)], displays: [primary]).count, 1)
        XCTAssertEqual(b.update(snapshots: [win("a", f, min: true)], displays: [primary]).count, 0)
        XCTAssertEqual(b.update(snapshots: [], displays: [primary]).count, 0)
    }

    func testDisplayBottomSurfaceSitsOnVisibleFrame() {
        XCTAssertEqual(primary.bottomSurface.frame.maxY, 70)
        XCTAssertEqual(primary.bottomSurface.kind, .displayBottom)
    }
}

final class CornerCurveTests: XCTestCase {
    private func win(r: Float = 16) -> CollisionSurface {
        CollisionSurface(id: "w", frame: CGRect(x: 100, y: 200, width: 400, height: 300), velocity: .zero, kind: .windowTop, cornerRadius: r)
    }

    func testDropProfile() {
        let s = win()
        XCTAssertEqual(s.drop(atLocalX: 200), 0, accuracy: 1e-5)
        XCTAssertEqual(s.drop(atLocalX: 16), 0, accuracy: 1e-4)
        XCTAssertEqual(s.drop(atLocalX: 0), 16, accuracy: 1e-4)
        XCTAssertEqual(s.drop(atLocalX: 400), 16, accuracy: 1e-4)
        XCTAssertGreaterThan(s.drop(atLocalX: 4), s.drop(atLocalX: 8))   // monotonic toward the edge
    }

    func testFlatWithoutRadius() {
        XCTAssertEqual(win(r: 0).drop(atLocalX: 0), 0)
    }

    func testFlakeAtCornerPassesFlatTopLineButLandsOnCurve() {
        var c = SimulationConfiguration(); c.density = 0; c.windStrength = 0; c.turbulence = 0
        let w = PhysicsWorld(config: c)
        w.setSurfaces([win()])                       // top at y = 500, radius 16
        var s = SnowParticle.blank
        s.position = SIMD2(101, 500.5); s.velocity = SIMD2(0, -200); s.mass = 1; s.volume = 6
        w.pool.spawn(s)
        w.step(dt: 1.0 / 120)
        XCTAssertEqual(w.pool.count, 1, "at the very corner the surface is ~16 pt below the flat top")
        for _ in 0..<120 { w.step(dt: 1.0 / 120) }
        XCTAssertEqual(w.pool.count, 0, "it should land on the curve")
        XCTAssertEqual(w.state(forSurface: "w")!.field.volume, 6, accuracy: 0.01)
    }
}

final class CoverageTests: XCTestCase {
    private let display = DisplayDescriptor(id: 1, uuid: "d", name: "D", frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 870), scale: 2)

    private func win(_ id: String, _ f: CGRect, z: Int, pid: pid_t = 99) -> WindowSnapshot {
        WindowSnapshot(id: id, processID: pid, frame: f, isVisible: true, isMinimized: false, timestamp: 0, zRank: z)
    }

    func testFullScreenWindowInFrontCoversDisplay() {
        let s = [win("a", display.frame, z: 0), win("b", CGRect(x: 100, y: 100, width: 400, height: 300), z: 1)]
        XCTAssertEqual(WindowEligibility.coveredDisplays(snapshots: s, displays: [display], ownPID: 1), [1])
    }

    func testNormalWindowDoesNotCover() {
        let s = [win("a", CGRect(x: 0, y: 0, width: 1440, height: 870), z: 0)]   // maximised, menu bar visible
        XCTAssertTrue(WindowEligibility.coveredDisplays(snapshots: s, displays: [display], ownPID: 1).isEmpty)
    }

    func testFullScreenBehindAnotherWindowDoesNotCover() {
        let s = [win("a", CGRect(x: 100, y: 100, width: 400, height: 300), z: 0), win("b", display.frame, z: 1)]
        XCTAssertTrue(WindowEligibility.coveredDisplays(snapshots: s, displays: [display], ownPID: 1).isEmpty)
    }

    func testOwnWindowsAreIgnored() {
        let s = [win("a", display.frame, z: 0, pid: 1)]
        XCTAssertTrue(WindowEligibility.coveredDisplays(snapshots: s, displays: [display], ownPID: 1).isEmpty)
    }
}
