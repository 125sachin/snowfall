import AppKit
import Observation

/// Owns app-level runtime state (separate from persisted settings and, later, simulation state).
@MainActor
@Observable
final class AppCoordinator {
    let store: SettingsStore

    /// Runtime pause flag. Not persisted.
    var isPaused = false

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
    }

    /// True when snow should be running.
    var isRunning: Bool { store.settings.snowfallEnabled && !isPaused }

    func togglePause() { isPaused.toggle() }

    /// Placeholder hook: the simulation does not exist yet (Milestone 4).
    func clearSnow() {}

    func quit() { NSApplication.shared.terminate(nil) }
}
