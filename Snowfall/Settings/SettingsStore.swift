import Foundation
import Observation
import ServiceManagement

/// Main-actor observable settings model with validated, version-safe persistence.
@MainActor
@Observable
final class SettingsStore {
    static let defaultsKey = "SnowfallSettings"

    var settings: SnowfallSettings {
        didSet {
            let valid = settings.validated()
            if valid != settings {
                settings = valid
                return
            }
            persist()
        }
    }

    /// Non-nil when the last launch-at-login change failed.
    private(set) var launchAtLoginError: String?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = Self.load(from: defaults)
    }

    func resetToDefaults() {
        settings = .default
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            settings.launchAtLogin = enabled
        } catch {
            launchAtLoginError = error.localizedDescription
            settings.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Persistence

    static func load(from defaults: UserDefaults) -> SnowfallSettings {
        guard let data = defaults.data(forKey: defaultsKey) else { return .default }
        do {
            let decoded = try JSONDecoder().decode(SnowfallSettings.self, from: data)
            return migrate(decoded).validated()
        } catch {
            return .default
        }
    }

    /// Hook for future schema migrations. Version 1 is current, so nothing to do yet.
    static func migrate(_ s: SnowfallSettings) -> SnowfallSettings { s }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
