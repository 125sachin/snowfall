# Testing

## Automated (`xcodebuild … test`)
70 XCTest cases: gravity/terminal velocity, wind, drag, velocity clamp, pool capacity/reuse, determinism,
huge timesteps, pointer impulse (direction, falloff, radius, zero-distance, bound), collision response,
broad phase, height-field deposit/relax/clip/shed/remap (volume conservation), moving-window displacement
(stationary, slow drag, fast move, vertical, resize, close, landing on lower surface, rapid movement),
AX↔AppKit coordinate conversion (displays above/left, scale), window eligibility/identity/velocity, settings
validation/persistence/migration.

## Measured (this machine: Apple M5, macOS 26.6.2)
- Simulation step, 3000 particles + 1 surface, **Debug** build: 1.12 ms/step (`testSimulationStepCost`).
- Release app, 1 built-in display (scale 2×), default settings (~1000 particles), single short sample with
  `top`: ≈ 8–14 % of one core, ≈ 150 MB. This is a rough sample, **not** an Instruments profile. Frame time and
  GPU cost were not profiled; FPS is shown in Settings → Performance → Show diagnostics.
- Render FPS in diagnostics is an inter-frame EMA across all overlays; with several displays it overstates FPS.

## Manual matrix (status)
| Item | Status |
|---|---|
| Overlay renders transparently over other apps (screenshot, built-in display) | verified |
| Snow settles along the display bottom | verified (screenshot) |
| Menu bar item appears | verified (screenshot) |
| Click-through into Finder/browser, typing, dragging windows | **not yet verified by hand** |
| Pointer scatters snow | **not yet verified by hand** |
| Snow on window tops (window-server list, no permission) | snow seen on a window top in a screenshot; move/resize/close/stacking **not yet checked by hand** |
| External display (same/different scale), display above/left, hot-plug | **not tested** (one display available) |
| Spaces, Mission Control, full-screen apps | **not tested** |
| Sleep/wake | **not tested** (clock reset logic is implemented) |
| Low Power Mode, thermal | **not tested** |
| Instruments (Time Profiler / Metal System Trace) | **not run** |
