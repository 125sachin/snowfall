import SwiftUI

struct SettingsView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var store = coordinator.store

        TabView {
            general(store).tabItem { Label("General", systemImage: "gearshape") }
            snow(store).tabItem { Label("Snow", systemImage: "snowflake") }
            interaction(store).tabItem { Label("Interaction", systemImage: "cursorarrow.motionlines") }
            displays(store).tabItem { Label("Displays", systemImage: "display") }
            performance(store).tabItem { Label("Performance", systemImage: "speedometer") }
        }
        .frame(width: 520, height: 420)
    }

    private func general(_ store: SettingsStore) -> some View {
        @Bindable var store = store
        return Form {
            Toggle("Launch at login", isOn: Binding(get: { store.settings.launchAtLogin },
                                                   set: { store.setLaunchAtLogin($0) }))
            if let error = store.launchAtLoginError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Toggle("Snowfall on", isOn: $store.settings.snowfallEnabled)
            Button("Restore Defaults") { store.resetToDefaults() }
            Text("Settings are saved automatically and restored at launch.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func snow(_ store: SettingsStore) -> some View {
        @Bindable var store = store
        return Form {
            LabeledSlider(title: "Particle density", value: $store.settings.particleDensity, lowLabel: "Light", highLabel: "Heavy")
            LabeledSlider(title: "Fall speed", value: $store.settings.fallSpeed, range: 0.5...1.5, lowLabel: "Slow", highLabel: "Fast")
            LabeledSlider(title: "Wind strength", value: $store.settings.windStrength, lowLabel: "Calm", highLabel: "Breezy")
            LabeledSlider(title: "Opacity", value: $store.settings.particleOpacity, range: 0.3...1, lowLabel: "Faint", highLabel: "Solid")
            Picker("Snow on", selection: $store.settings.backdrop) {
                ForEach(BackdropMode.allCases) { Text($0.label).tag($0) }
            }
            Text("Light backgrounds draw flakes and piles with a cool outline so they stay visible on white windows.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Accumulate snow", isOn: $store.settings.accumulationEnabled)
            LabeledSlider(title: "Maximum depth", value: $store.settings.maxAccumulationDepth, lowLabel: "Shallow", highLabel: "Deep")
                .disabled(!store.settings.accumulationEnabled)
            Section("Snow helper") {
                Picker("Helper", selection: $store.settings.helper) {
                    ForEach(HelperKind.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Run automatically", isOn: $store.settings.plowAutomatic)
                Stepper("Every \(store.settings.plowIntervalMinutes) min", value: $store.settings.plowIntervalMinutes, in: 1...60)
                    .disabled(!store.settings.plowAutomatic)
                Button("Send \(store.settings.helper.shortLabel) Now") { coordinator.sendHelper() }
                Text(store.settings.helper.summary + " Helpers only run when there is snow to clear.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func interaction(_ store: SettingsStore) -> some View {
        @Bindable var store = store
        return Form {
            Section("Pointer") {
                Toggle("Pointer disturbance", isOn: $store.settings.pointerInteractionEnabled)
                LabeledSlider(title: "Radius", value: $store.settings.pointerRadius, range: 40...300, lowLabel: "Small", highLabel: "Large")
                LabeledSlider(title: "Strength", value: $store.settings.pointerStrength, lowLabel: "Gentle", highLabel: "Strong")
                Text("Uses the cursor position only. No permission is needed; clicks and keystrokes are never observed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Window physics") {
                Toggle("Snow on window tops", isOn: $store.settings.windowPhysicsEnabled)
                LabeledSlider(title: "Displacement", value: $store.settings.windowDisplacementStrength, lowLabel: "Sticky", highLabel: "Slippery")
                Text("Snow settles on the top edge of the front-most windows and stacks on whichever window is in front. It uses each window's position, size and stacking order only — never titles or contents — and needs no special permission.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func displays(_ store: SettingsStore) -> some View {
        Form {
            if coordinator.displays.isEmpty {
                Text("No displays detected.").foregroundStyle(.secondary)
            }
            ForEach(coordinator.displays) { d in
                Toggle(isOn: Binding(get: { coordinator.isDisplayEnabled(d) },
                                     set: { coordinator.setDisplay(d, enabled: $0) })) {
                    VStack(alignment: .leading) {
                        Text(d.name)
                        Text("\(Int(d.frame.width))×\(Int(d.frame.height)) pt · \(Int(d.scale))×")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Displays are detected automatically when connected, removed or reconfigured.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func performance(_ store: SettingsStore) -> some View {
        @Bindable var store = store
        return Form {
            Picker("Target frame rate", selection: $store.settings.targetFrameRate) {
                ForEach(TargetFrameRate.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Low-power mode (30 FPS, fewer particles)", isOn: $store.settings.lowPowerMode)
            Stepper("Maximum particles: \(store.settings.maxParticles)", value: $store.settings.maxParticles, in: 200...3000, step: 100)
            Toggle("Show collision-surface outlines", isOn: $store.settings.showSurfaceDebug)
            Toggle("Show diagnostics", isOn: $store.settings.showDiagnostics)
            if store.settings.showDiagnostics { DiagnosticsView() }
        }
        .formStyle(.grouped)
    }
}
