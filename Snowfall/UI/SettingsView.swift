import SwiftUI

struct SettingsView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var store = coordinator.store

        TabView {
            Form {
                Toggle("Launch at login", isOn: Binding(
                    get: { store.settings.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }
                ))
                if let error = store.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Toggle("Start snowfall automatically", isOn: $store.settings.snowfallEnabled)
                Button("Restore Defaults") { store.resetToDefaults() }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Slider(value: $store.settings.particleDensity, in: 0...1) { Text("Particle density") }
                Slider(value: $store.settings.windStrength, in: 0...1) { Text("Wind strength") }
                Toggle("Accumulate snow", isOn: $store.settings.accumulationEnabled)
                Text("Snow rendering arrives in a later milestone; these values are saved now.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .tabItem { Label("Snow", systemImage: "snowflake") }

            Form {
                Toggle("Pointer interaction", isOn: $store.settings.pointerInteractionEnabled)
                Toggle("Window physics", isOn: $store.settings.windowPhysicsEnabled)
                    .disabled(true)
                Text("Window physics requires Accessibility permission and is not available yet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .tabItem { Label("Interaction", systemImage: "cursorarrow.motionlines") }

            Form {
                Picker("Target frame rate", selection: $store.settings.targetFrameRate) {
                    ForEach(TargetFrameRate.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Low-power mode", isOn: $store.settings.lowPowerMode)
            }
            .formStyle(.grouped)
            .tabItem { Label("Performance", systemImage: "speedometer") }
        }
        .frame(width: 460, height: 280)
    }
}
