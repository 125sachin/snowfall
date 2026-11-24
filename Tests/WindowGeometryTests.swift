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
