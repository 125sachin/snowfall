import AppKit

/// Samples the global pointer position with `NSEvent.mouseLocation`, which needs **no** permission
/// (it reads the cursor position only; it does not observe clicks, keys or scrolls). Runs only while
/// enabled. Positions are canonical global AppKit points, so no conversion is needed.
@MainActor
final class MouseTracker {
    private var timer: Timer?
    private var last: CGPoint?
    private var lastTime: TimeInterval = 0
    private var smoothed = CGVector.zero
    var onSample: ((PointerSample?) -> Void)?

    var isRunning: Bool { timer != nil }

    func start(hz: Double = 60) {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1 / hz, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer?.tolerance = 0.004
    }

    func stop() {
        timer?.invalidate(); timer = nil
        last = nil
        onSample?(nil)
    }

    private func sample() {
        let p = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        defer { last = p; lastTime = now }
        guard let last, now > lastTime else { return }
        guard p != last || smoothed != .zero else { return }   // nothing changed, nothing to send
        let dt = max(now - lastTime, 1.0 / 240)
        let v = CGVector(dx: (p.x - last.x) / dt, dy: (p.y - last.y) / dt)
        smoothed = CGVector(dx: smoothed.dx * 0.6 + v.dx * 0.4, dy: smoothed.dy * 0.6 + v.dy * 0.4)
        if hypot(smoothed.dx, smoothed.dy) < 1 { smoothed = .zero }
        onSample?(PointerSample(x: Float(p.x), y: Float(p.y), vx: Float(smoothed.dx), vy: Float(smoothed.dy)))
    }
}
