import Foundation

/// Immutable best-effort description of an application window. `frame` is canonical global
/// AppKit points. Window titles are intentionally never read.
struct WindowSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let processID: pid_t
    let frame: CGRect
    let isVisible: Bool
    let isMinimized: Bool
    let timestamp: TimeInterval
    /// 0 = frontmost on screen. Derived from the window server's stacking order.
    var zRank: Int = 0

    func withZRank(_ r: Int) -> WindowSnapshot {
        WindowSnapshot(id: id, processID: processID, frame: frame, isVisible: isVisible,
                       isMinimized: isMinimized, timestamp: timestamp, zRank: r)
    }
}

enum WindowEligibility {
    static let minSize = CGSize(width: 100, height: 60)
    /// A window must have this much clearance below the top of the visible area to hold snow.
    static let topClearance: CGFloat = 24
    /// Typical top-corner radius of a macOS window (pt).
    static let cornerRadius: Float = 16

    static func isEligible(_ w: WindowSnapshot, displays: [DisplayDescriptor], ownPID: pid_t) -> Bool {
        guard w.processID != ownPID, w.isVisible, !w.isMinimized else { return false }
        guard w.frame.width >= minSize.width, w.frame.height >= minSize.height else { return false }
        guard w.frame.origin.x.isFinite, w.frame.origin.y.isFinite else { return false }
        guard let d = displays.first(where: { $0.frame.intersects(w.frame) }) else { return false }
        let top = w.frame.maxY
        return top <= d.visibleFrame.maxY - topClearance && top >= d.visibleFrame.minY + 10
    }
}

extension WindowEligibility {
    /// Displays whose front-most window fills the whole display (a full-screen app, which also
    /// hides the menu bar). Snow behind it is invisible, so it is not worth drawing.
    /// `snapshots` are in any order; `zRank` decides which window is in front.
    static func coveredDisplays(snapshots: [WindowSnapshot], displays: [DisplayDescriptor], ownPID: pid_t) -> Set<UInt32> {
        var covered = Set<UInt32>()
        let others = snapshots.filter { $0.processID != ownPID && $0.isVisible && !$0.isMinimized }
        for d in displays {
            let front = others.filter { $0.frame.intersects(d.frame.insetBy(dx: 2, dy: 2)) }
                              .min { $0.zRank < $1.zRank }
            if let f = front, f.frame.insetBy(dx: -2, dy: -2).contains(d.frame) { covered.insert(d.id) }
        }
        return covered
    }
}

/// Turns window snapshots into collision surfaces, keeping identity and estimating velocity
/// from frame deltas. Not thread-safe: use from one queue.
struct SurfaceBuilder {
    private var previous: [String: (frame: CGRect, time: TimeInterval, velocity: CGVector)] = [:]
    let ownPID: pid_t
    init(ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) { self.ownPID = ownPID }

    mutating func update(snapshots: [WindowSnapshot], displays: [DisplayDescriptor]) -> [CollisionSurface] {
        var seen = Set<String>()
        var result: [CollisionSurface] = []
        var next: [String: (CGRect, TimeInterval, CGVector)] = [:]
        for w in snapshots where WindowEligibility.isEligible(w, displays: displays, ownPID: ownPID) {
            guard seen.insert(w.id).inserted else { continue }   // no duplicates
            var v = CGVector.zero
            if let p = previous[w.id] {
                if p.frame == w.frame {
                    v = .zero
                } else {
                    let dt = max(w.timestamp - p.time, 1.0 / 60.0)
                    v = CGVector(dx: (w.frame.minX - p.frame.minX) / dt, dy: (w.frame.maxY - p.frame.maxY) / dt)
                }
            }
            next[w.id] = (w.frame, w.timestamp, v)
            result.append(CollisionSurface(id: "window-\(w.id)", frame: w.frame, velocity: v, kind: .windowTop, zRank: w.zRank,
                                           cornerRadius: WindowEligibility.cornerRadius))
        }
        previous = next
        return result
    }
}
