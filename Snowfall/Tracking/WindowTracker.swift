import AppKit

/// Discovers on-screen windows from the window server's list (`CGWindowListCopyWindowInfo`).
///
/// Reads only owner pid, window number, layer, alpha, bounds and front-to-back order. It never
/// reads window titles and never captures pixels, and it needs no Accessibility or Screen
/// Recording permission for these fields. Unlike Accessibility, it sees windows of every app
/// (including Electron/Chrome apps) and tells us stacking order. Polling is adaptive (fast while
/// a window moved recently) and runs off the main thread, never at render frequency.
final class WindowTracker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "snowfall.window-tracker", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastFrames: [Int: CGRect] = [:]
    private var lastMotion: TimeInterval = 0
    private var slowInterval: TimeInterval = 0.5
    private var pollCount = 0
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    /// Receives immutable snapshots (frames in canonical AppKit points), front-most first.
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
        let primaryHeight: CGFloat = DispatchQueue.main.sync {
            MainActor.assumeIsolated { NSScreen.screens.first?.frame.height ?? 0 }
        }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { onSnapshots?([]); return }
        let now = ProcessInfo.processInfo.systemUptime
        var out: [WindowSnapshot] = []
        var frames: [Int: CGRect] = [:]
        for (rank, d) in list.enumerated() {
            guard let layer = d["kCGWindowLayer"] as? Int, layer == 0,
                  let pid = d["kCGWindowOwnerPID"] as? Int, pid_t(pid) != ownPID,
                  let number = d["kCGWindowNumber"] as? Int,
                  let b = d["kCGWindowBounds"] as? [String: Any],
                  let axRect = CGRect(dictionaryRepresentation: b as CFDictionary) else { continue }
            if let alpha = d["kCGWindowAlpha"] as? Double, alpha < 0.05 { continue }
            let frame = CoordinateSpace.appKitRect(fromAXRect: axRect, primaryHeightPoints: primaryHeight)
            frames[number] = frame
            out.append(WindowSnapshot(id: "\(number)", processID: pid_t(pid), frame: frame, isVisible: true,
                                      isMinimized: false, timestamp: now, zRank: rank))
        }
        if frames != lastFrames { lastMotion = now }
        lastFrames = frames
        pollCount += 1
        if pollCount % 20 == 1 {
            SnowfallLogger.tracking.info("poll: windows=\(out.count, privacy: .public)")
        }
        onSnapshots?(out)
    }
}
