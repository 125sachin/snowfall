import SwiftUI

struct MenuBarView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var store = coordinator.store

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "snowflake").font(.title3).foregroundStyle(.tint)
                Text("Snowfall").font(.headline)
                Spacer()
                Toggle("Snowfall", isOn: $store.settings.snowfallEnabled)
                    .labelsHidden().toggleStyle(.switch)
                    .accessibilityLabel("Snowfall on or off")
            }

            if let err = coordinator.rendererError {
                Label("Rendering unavailable: \(err)", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }

            Divider()

            LabeledSlider(title: "Intensity", value: $store.settings.particleDensity, lowLabel: "Low", highLabel: "High")
            LabeledSlider(title: "Wind", value: $store.settings.windStrength, lowLabel: "Calm", highLabel: "Breezy")

            Toggle("Accumulation", isOn: $store.settings.accumulationEnabled)
            Toggle("Mouse interaction", isOn: $store.settings.pointerInteractionEnabled)
            Toggle("Window physics", isOn: $store.settings.windowPhysicsEnabled)
                .disabled(!coordinator.permission.isTrusted)
            if !coordinator.permission.isTrusted {
                Text("Window physics needs Accessibility permission. Open Settings → Interaction.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button(coordinator.isPaused ? "Resume" : "Pause") { coordinator.togglePause() }
                    .disabled(!store.settings.snowfallEnabled)
                Button("Clear Snow") { coordinator.clearSnow() }
            }

            HStack {
                Button("Settings…") { NSApp.activate(); openSettings() }
                Spacer()
                Button("Quit Snowfall") { coordinator.quit() }.keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 290)
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    let lowLabel: String
    let highLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline)
            Slider(value: $value, in: range) {
                EmptyView()
            } minimumValueLabel: {
                Text(lowLabel).font(.caption)
            } maximumValueLabel: {
                Text(highLabel).font(.caption)
            }
            .accessibilityLabel(title)
        }
    }
}
