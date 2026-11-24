import SwiftUI

@main
struct SnowfallApp: App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(coordinator)
        } label: {
            Image(systemName: coordinator.isRunning ? "snowflake" : "snowflake.slash")
                .accessibilityLabel("Snowfall")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(coordinator)
        }
    }
}
