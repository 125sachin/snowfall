import AppKit
import MetalKit

/// Owns one overlay window (and renderer) per enabled display and reconciles them with display
/// changes. Rendering state lives here; physics and tracking are separate.
@MainActor
final class OverlayManager {
    private struct Overlay {
        let window: OverlayWindow
        let view: SnowfallView
        let renderer: MetalRenderer
    }

    private var overlays: [UInt32: Overlay] = [:]
    private let simulation: SimulationCoordinator
    private let monitor: PerformanceMonitor
    private var fps = 60
    private var paused = false
    private var showBorders = false
    private var contrast: Float = 0
    private var hidden = false
    /// Displays under a full-screen app: their overlay is hidden and not drawn.
    private var covered = Set<UInt32>()

    /// Called when Metal setup fails so the UI can say why snow is unavailable.
    var onRendererFailure: ((String) -> Void)?
    var onOcclusionLost: (() -> Void)?

    init(simulation: SimulationCoordinator, monitor: PerformanceMonitor) {
        self.simulation = simulation
        self.monitor = monitor
    }

    var overlayCount: Int { overlays.count }

    /// Creates, updates and removes overlays so exactly the given displays have one.
    func reconcile(displays: [DisplayDescriptor]) {
        let wanted = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0) })
        for id in overlays.keys where wanted[id] == nil { remove(id) }
        for d in displays {
            if let o = overlays[d.id] {
                if o.window.frame != d.frame { o.window.setFrame(d.frame, display: false) }
                o.renderer.displayFrame = d.frame
            } else {
                create(d)
            }
        }
        applyState()
    }

    func setState(fps: Int, paused: Bool, showBorders: Bool, contrast: Float) {
        self.fps = fps; self.paused = paused; self.showBorders = showBorders; self.contrast = contrast
        applyState()
    }

    func setCovered(_ ids: Set<UInt32>) {
        guard ids != covered else { return }
        covered = ids
        applyState()
    }

    func hideAll() {
        hidden = true
        for o in overlays.values { o.view.isPaused = true; o.window.orderOut(nil); o.view.releaseDrawables = true }
    }

    /// Redraws once while paused so changes such as Clear Snow become visible immediately.
    func refreshFrame() {
        guard paused else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated { self?.overlays.values.forEach { $0.view.draw() } }
        }
    }

    func tearDown() {
        for id in Array(overlays.keys) { remove(id) }
    }

    /// Brings overlays back to front and resumes drawing. Cheap; safe to call often.
    func reassert() {
        guard !hidden else { return }
        for (id, o) in overlays where !covered.contains(id) {
            o.view.releaseDrawables = false
            o.window.orderFrontRegardless()
            if !paused { o.view.isPaused = false }
        }
    }

    private func create(_ d: DisplayDescriptor) {
        let window = OverlayWindow(display: d)
        let view = SnowfallView(frame: CGRect(origin: .zero, size: d.frame.size))
        view.autoresizingMask = [.width, .height]
        view.configureTransparency()
        do {
            let provider = simulation
            let renderer = try MetalRenderer(view: view, displayFrame: d.frame, monitor: monitor) {
                provider.latestSnapshot()
            }
            window.contentView = view
            window.setFrame(d.frame, display: false)
            overlays[d.id] = Overlay(window: window, view: view, renderer: renderer)
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let self, let window, !self.hidden, !window.occlusionState.contains(.visible) else { return }
                    self.onOcclusionLost?()
                    self.reassert()
                }
            }
            SnowfallLogger.overlay.info("overlay created for display \(d.id) scale \(d.scale)")
        } catch {
            SnowfallLogger.render.error("renderer failed: \(error.localizedDescription)")
            onRendererFailure?(error.localizedDescription)
        }
    }

    private func remove(_ id: UInt32) {
        guard let o = overlays.removeValue(forKey: id) else { return }
        o.view.isPaused = true
        o.view.delegate = nil
        o.window.orderOut(nil)
        o.window.contentView = nil
        o.window.close()
    }

    private func applyState() {
        hidden = false
        for (id, o) in overlays {
            if covered.contains(id) {
                o.view.isPaused = true
                o.window.orderOut(nil)
                o.view.releaseDrawables = true     // frees the two full-screen buffers (~46 MB on Retina)
                continue
            }
            o.view.releaseDrawables = false
            o.view.preferredFramesPerSecond = fps
            o.renderer.drawsDisplayBorder = showBorders
            o.renderer.contrast = contrast
            o.window.orderFrontRegardless()
            if paused {
                o.view.isPaused = true
                o.view.draw()   // keep the last frame visible
            } else {
                o.view.isPaused = false
            }
        }
    }
}
