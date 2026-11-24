import AppKit
import ApplicationServices

/// Best-effort window discovery via documented Accessibility APIs.
///
/// Reads only position, size, minimized state and subrole of standard windows of regular apps.
/// It never reads titles or contents and never captures the screen. AX work runs on a utility
/// queue; polling is adaptive (fast while a window moved recently, slow otherwise) and never runs
/// at render frequency. AX data is best-effort: apps may expose partial or no windows.
final class WindowTracker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "snowfall.window-tracker", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastFrames: [String: CGRect] = [:]
    private var lastMotion: TimeInterval = 0
    private var slowInterval: TimeInterval = 0.5
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    /// Receives immutable snapshots (frames already converted to canonical AppKit points).
    var onSnapshots: (@Sendable ([WindowSnapshot]) -> Void)?

    func start(lowPower: Bool) {
        queue.async { [self] in
            slowInterval = lowPower ? 1.0 : 0.5
            guard timer == nil else { return }
            schedule(after: 0)
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel(); timer = nil
            lastFrames = [:]
            onSnapshots?([])
        }
    }

    private func schedule(after delay: TimeInterval) {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + delay, leeway: .milliseconds(10))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.timer?.cancel()
            self.timer = nil
            self.poll()
            let recentlyMoved = ProcessInfo.processInfo.systemUptime - self.lastMotion < 1.5
            self.schedule(after: recentlyMoved ? 1.0 / 15.0 : self.slowInterval)
        }
        timer = t
        t.resume()
    }

    private func poll() {
        guard AXIsProcessTrusted() else { onSnapshots?([]); return }
        let primaryHeight: CGFloat = DispatchQueue.main.sync {
            MainActor.assumeIsolated { NSScreen.screens.first?.frame.height ?? 0 }
        }
        let pids: [pid_t] = DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                NSWorkspace.shared.runningApplications
                    .filter { $0.activationPolicy == .regular && !$0.isHidden && !$0.isTerminated }
                    .map(\.processIdentifier)
            }
        }
        let now = ProcessInfo.processInfo.systemUptime
        var out: [WindowSnapshot] = []
        var frames: [String: CGRect] = [:]
        for pid in pids where pid != ownPID {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.15)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }
            for w in windows {
                guard let snap = Self.snapshot(of: w, pid: pid, primaryHeight: primaryHeight, time: now) else { continue }
                frames[snap.id] = snap.frame
                out.append(snap)
            }
        }
        if frames != lastFrames { lastMotion = now }
        lastFrames = frames
        onSnapshots?(out)
    }

    private static func snapshot(of w: AXUIElement, pid: pid_t, primaryHeight: CGFloat, time: TimeInterval) -> WindowSnapshot? {
        var sub: CFTypeRef?
        if AXUIElementCopyAttributeValue(w, kAXSubroleAttribute as CFString, &sub) == .success,
           let s = sub as? String, s != kAXStandardWindowSubrole as String { return nil }
        guard let pos = point(w, kAXPositionAttribute), let size = size(w, kAXSizeAttribute) else { return nil }
        var min: CFTypeRef?
        let minimized = AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &min) == .success
            && (min as? Bool ?? false)
        let ax = CGRect(origin: pos, size: size)
        let frame = CoordinateSpace.appKitRect(fromAXRect: ax, primaryHeightPoints: primaryHeight)
        return WindowSnapshot(id: "\(pid)-\(CFHash(w))", processID: pid, frame: frame, isVisible: true,
                              isMinimized: minimized, timestamp: time)
    }

    private static func point(_ e: AXUIElement, _ attr: String) -> CGPoint? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success, let v,
              CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    private static func size(_ e: AXUIElement, _ attr: String) -> CGSize? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success, let v,
              CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }
}
