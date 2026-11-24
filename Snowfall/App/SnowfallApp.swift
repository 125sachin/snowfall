import SwiftUI

@main
struct SnowfallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(delegate.coordinator)
        } label: {
            Image(systemName: delegate.coordinator.isRunning ? "snowflake" : "snowflake.slash")
                .accessibilityLabel("Snowfall")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(delegate.coordinator)
        }
    }
}
