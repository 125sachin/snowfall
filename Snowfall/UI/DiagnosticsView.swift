import SwiftUI

struct DiagnosticsView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        let r = coordinator.reading, s = coordinator.stats
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            row("Overlays", "\(coordinator.overlayCount)")
            row("Render FPS", String(format: "%.0f", r.renderFPS))
            row("Render CPU time", String(format: "%.2f ms", r.renderMs))
            row("Simulation step", String(format: "%.2f ms", r.simMs))
            row("Active particles", "\(s.particleCount)")
            row("Density scale", String(format: "%.2f", s.densityScale))
            row("Surfaces (windows)", "\(s.surfaceCount) (\(s.windowSurfaceCount))")
            row("Settled snow", String(format: "%.0f pt²", s.settledVolume))
            row("Memory", String(format: "%.0f MB", r.memoryMB))
            row("CPU", String(format: "%.1f %%", r.cpuPercent))
        }
        .font(.callout.monospacedDigit())
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow { Text(k).foregroundStyle(.secondary); Text(v) }
    }
}
