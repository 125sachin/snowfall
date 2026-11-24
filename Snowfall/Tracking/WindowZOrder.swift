import Foundation

struct OnScreenWindow: Equatable, Sendable {
    let pid: pid_t
    let frame: CGRect      // canonical global AppKit points
    let rank: Int          // 0 = frontmost
}

enum WindowZOrder {
    /// Gives each AX window the stacking rank of the on-screen window-server entry with the same
    /// owner and (approximately) the same frame. AX windows with no match are not on screen
    /// (other Space, hidden, off-screen) and are dropped.
    static func apply(to windows: [WindowSnapshot], onScreen: [OnScreenWindow], tolerance: CGFloat = 8) -> [WindowSnapshot] {
        var used = Set<Int>()
        var out: [WindowSnapshot] = []
        let ordered = onScreen.sorted { $0.rank < $1.rank }
        for w in windows {
            if let hit = ordered.first(where: { !used.contains($0.rank) && $0.pid == w.processID && close($0.frame, w.frame, tolerance) }) {
                used.insert(hit.rank)
                out.append(w.withZRank(hit.rank))
            }
        }
        return out
    }

    private static func close(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> Bool {
        abs(a.minX - b.minX) <= t && abs(a.minY - b.minY) <= t && abs(a.width - b.width) <= t && abs(a.height - b.height) <= t
    }
}
