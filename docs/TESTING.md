# Testing

## Automated

```sh
xcodebuild -scheme Snowfall -destination 'platform=macOS' test
```

The suite covers the pure logic and the simulation, which is deterministic (seeded) and runs headless:

- gravity, wind, drag, particle pool limits and determinism
- collision response and the broad phase
- the snow height field: deposit, relaxation, clipping, edge shedding, remapping, and volume conservation
- moving, resizing and closing windows, window eligibility and stacking, rounded corners, and full-screen coverage
- coordinate conversion between the window server and AppKit
- every helper: direction of travel, that removed snow is accounted for, and one-helper-at-a-time
- settings validation, persistence and migration

## Manual checklist

Rendering and window behaviour depend on the real window server, so these are checked by hand. Status is what the
maintainers have actually verified.

| Item | Status |
|---|---|
| Overlay is transparent over other apps | verified |
| Snow settles along the bottom and on window tops, follows window corners | verified |
| Menu bar item, helpers and the new icon | verified |
| Click-through into other apps, typing, dragging windows | not yet verified by hand |
| Pointer scatters snow | not yet verified by hand |
| Moving, resizing, closing and stacking windows | partly verified |
| External displays (same or different scale), display above/left, hot-plug | not tested (one display available) |
| Spaces, Mission Control, full-screen apps | not tested |
| Sleep and wake | not tested (clock reset is implemented) |
| Low Power Mode and thermal throttling | not tested |
| Profiling with Instruments | not done |

Reports from other setups are very welcome.

## Resource use

A rough sample on an Apple silicon laptop (one Retina display, default settings) with `top`/`footprint`: about
115 MB resident while snow is visible (46 MB of that is the two full-screen drawables), about 27 MB with the overlay
hidden, and low single-digit CPU. This is not an Instruments profile.
