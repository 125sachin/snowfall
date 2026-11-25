import AppKit
import IOKit.ps
import Observation

/// Owns app-level runtime state and wires settings, displays, tracking, simulation and overlays.
/// UI state stays here; physics lives in `SimulationCoordinator`, drawing in `OverlayManager`.
@MainActor
@Observable
final class AppCoordinator {
    let store: SettingsStore

    var isPaused = false
    private(set) var displays: [DisplayDescriptor] = []
    private(set) var rendererError: String?
    private(set) var stats = SimulationStats()
    private(set) var reading = PerformanceReading()
    private(set) var overlayCount = 0

    @ObservationIgnored private let monitor = PerformanceMonitor()
    @ObservationIgnored private let simulation: SimulationCoordinator
    @ObservationIgnored private let overlays: OverlayManager
    @ObservationIgnored private let mouse = MouseTracker()
    @ObservationIgnored private let windows = WindowTracker()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var timers: [Timer] = []
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var windowsRunning = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var lastStatus = ""
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var statTicks = 0
    @ObservationIgnored private var coveredDisplays = Set<UInt32>()
    @ObservationIgnored private var lastIdleLevel = false
    @ObservationIgnored private var lastOnBattery = false

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        simulation = SimulationCoordinator(monitor: monitor)
        overlays = OverlayManager(simulation: simulation, monitor: monitor)
    }

    /// True when snow should be falling.
    var isRunning: Bool { store.settings.snowfallEnabled && !isPaused }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        displays = DisplayDescriptor.current()
        store.onChange = { [weak self] _ in self?.applyAll() }
        overlays.onRendererFailure = { [weak self] msg in self?.rendererError = msg }
        mouse.onSample = { [simulation] in simulation.updatePointer($0) }
        windows.onSnapshots = { [weak self, simulation] snaps in
            simulation.updateWindows(snaps)
            Task { @MainActor in self?.updateCoverage(snaps) }
        }

        let nc = NotificationCenter.default
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.displaysChanged() }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.suspended = true; self?.applyAll() }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        })
        observers.append(nc.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyAll() }
        })

        timers.append(Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStats() }
        })
        // Keep timers and display links running while another app is frontmost (App Nap would
        // otherwise throttle an accessory app with no visible UI of its own).
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep], reason: "Snowfall animation")
        // Re-evaluate the "automatic" backdrop when the system switches between light and dark.
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyAll() }
        })
        // Another app activating or a Space change can reorder windows; re-assert the overlays.
        let ws2 = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(ws2.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.overlays.reassert() }
            })
        }
        // Dev aid: `open Snowfall.app --args -plowAfterSeconds 40` sends the plow after 40 s.
        let after = UserDefaults.standard.double(forKey: "plowAfterSeconds")
        if after > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + after) { [weak self] in
                MainActor.assumeIsolated {
                    // `-helperKind santa` forces a helper for testing.
                    let raw = UserDefaults.standard.string(forKey: "helperKind")
                    self?.sendHelper(raw.flatMap(HelperKind.init(rawValue:)))
                }
            }
        }
        overlays.onOcclusionLost = { SnowfallLogger.overlay.info("overlay occlusion lost; re-asserting") }
        applyAll()
    }

    func stop() {
        if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
        timers.forEach { $0.invalidate() }
        timers.removeAll()
        mouse.stop()
        windows.stop()
        simulation.shutdown()
        overlays.tearDown()
    }

    // MARK: Actions

    func togglePause() { isPaused.toggle(); applyAll() }

    func sendHelper(_ kind: HelperKind? = nil) { simulation.sendHelper(kind) }

    func clearSnow() {
        simulation.clearSnow()
        overlays.refreshFrame()
    }

    func quit() { stop(); NSApplication.shared.terminate(nil) }

    func setDisplay(_ display: DisplayDescriptor, enabled: Bool) {
        var list = store.settings.disabledDisplays.filter { $0 != display.uuid }
        if !enabled { list.append(display.uuid) }
        store.settings.disabledDisplays = list
    }

    func isDisplayEnabled(_ d: DisplayDescriptor) -> Bool { !store.settings.disabledDisplays.contains(d.uuid) }

    // MARK: Wiring

    /// A full-screen app hides our overlay on that display; when every enabled display is covered
    /// the simulation and drawing stop entirely until a window uncovers one.
    private func updateCoverage(_ snaps: [WindowSnapshot]) {
        guard started, windowsRunning else { return }
        let enabled = displays.filter { !store.settings.disabledDisplays.contains($0.uuid) }
        let ids = WindowEligibility.coveredDisplays(snapshots: snaps, displays: enabled,
                                                    ownPID: ProcessInfo.processInfo.processIdentifier)
        guard ids != coveredDisplays else { return }
        coveredDisplays = ids
        overlays.setCovered(ids)
        applyAll()
    }

    /// Seconds since the last keyboard/mouse event (reads the system idle counter only).
    private static func idleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    private func displaysChanged() {
        displays = DisplayDescriptor.current()
        applyAll()
    }

    private func didWake() {
        suspended = false
        displays = DisplayDescriptor.current()
        simulation.resetClock()
        monitor.resetFrameClock()
        applyAll()
    }

    /// 1 when snow should be outlined for a light background, 0 for a dark one.
    private func backdropContrast(_ mode: BackdropMode) -> Float {
        switch mode {
        case .light: return 1
        case .dark: return 0
        case .auto:
            let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark ? 0 : 1
        }
    }

    /// True when the Mac is running on battery (snow looks fine at 30 FPS and costs far less).
    private static func onBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return false }
        return type == kIOPSBatteryPowerValue
    }

    private func effectiveFPS(_ s: SnowfallSettings) -> Int {
        let pi = ProcessInfo.processInfo
        if lastIdleLevel { return 15 }          // user away: a slow, cheap snowfall
        if s.lowPowerMode || pi.isLowPowerModeEnabled || Self.onBattery() { return 30 }
        switch s.targetFrameRate {
        case .fps30: return 30
        case .fps60: return 60
        case .adaptive: return pi.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue ? 30 : 60
        }
    }

    func applyAll() {
        let s = store.settings
        let enabled = displays.filter { !s.disabledDisplays.contains($0.uuid) }
        let running = s.snowfallEnabled && !isPaused && !suspended && !enabled.isEmpty
        if !(running && s.windowPhysicsEnabled), !coveredDisplays.isEmpty {   // no window data -> no coverage
            coveredDisplays = []; overlays.setCovered([])
        }
        let allCovered = !enabled.isEmpty && enabled.allSatisfy { coveredDisplays.contains($0.id) }
        let simRunning = running && !allCovered
        let lowPower = s.lowPowerMode || ProcessInfo.processInfo.isLowPowerModeEnabled
        let fps = effectiveFPS(s)
        let windowPhysics = s.windowPhysicsEnabled
        let status = "window physics: enabled=\(s.windowPhysicsEnabled)"
        if status != lastStatus { lastStatus = status; SnowfallLogger.app.info("\(status, privacy: .public)") }

        let ss = SimulationSettings(
            running: simRunning, density: s.particleDensity, wind: s.windStrength, fallSpeed: s.fallSpeed,
            opacity: s.particleOpacity, maxParticles: s.maxParticles, accumulation: s.accumulationEnabled,
            maxDepth: s.maxAccumulationDepth, pointerEnabled: s.pointerInteractionEnabled,
            pointerRadius: s.pointerRadius, pointerStrength: s.pointerStrength, windowPhysics: windowPhysics,
            displacementStrength: s.windowDisplacementStrength, lowPower: lowPower, showSurfaces: s.showSurfaceDebug,
            helper: s.helper, plowAuto: s.plowAutomatic, plowIntervalSeconds: Double(s.plowIntervalMinutes) * 60)
        simulation.updateDisplays(enabled)
        simulation.apply(settings: ss, targetFPS: Double(fps))

        if s.snowfallEnabled && !suspended && !enabled.isEmpty {
            overlays.reconcile(displays: enabled)
            overlays.setState(fps: fps, paused: isPaused, showBorders: s.showSurfaceDebug, contrast: backdropContrast(s.backdrop))
        } else if s.snowfallEnabled == false || enabled.isEmpty {
            overlays.tearDown()
        } else {
            overlays.hideAll()
        }
        overlayCount = overlays.overlayCount

        if simRunning && s.pointerInteractionEnabled { mouse.start() } else { mouse.stop() }

        let wantWindows = running && windowPhysics
        if wantWindows { windows.start(lowPower: lowPower); windowsRunning = true }
        else if windowsRunning { windows.stop(); windowsRunning = false }
    }

    private func refreshStats() {
        guard started else { return }
        statTicks += 1
        if statTicks % 10 == 0 {
            let battery = Self.onBattery()
            if battery != lastOnBattery { lastOnBattery = battery; applyAll() }
        }
        if statTicks % 5 == 0 {
            let idle = Self.idleSeconds() >= 180
            if idle != lastIdleLevel { lastIdleLevel = idle; applyAll() }
        }
        stats = simulation.latestSnapshot().stats
        reading = monitor.reading()
    }
}
