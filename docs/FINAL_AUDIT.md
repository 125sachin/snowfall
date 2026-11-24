# Final audit

Environment: Apple M5, macOS 26.6.2, Xcode 26.6, Swift 6.3.3 (Swift 6 language mode, strict concurrency). Date 2026-11-24.
Honest scope: automated tests and a short live run were done; most interactive/multi-display checks were not.

| Category | Status | Evidence / gap |
|---|---|---|
| Build (Debug + Release) | PASS | both succeed |
| Unit tests | PASS | 70/70 |
| Product: menu bar, start/pause/resume/clear/quit, settings persist | PASS (code + tests); UI clicked through by hand: **not done** | settings persistence tested; Clear/Pause call the real simulation |
| Overlay transparent | PASS | screenshot of live app |
| Overlay click-through | UNVERIFIED | `ignoresMouseEvents = true`, view `hitTest → nil`; no hands-on test |
| Window level/ordering | UNVERIFIED | `.floating` chosen with rationale in `OverlayWindow.swift`; Spaces/full-screen not tested |
| Simulation (fixed step, clamp, bounds, determinism) | PASS | tests |
| No allocation in `step()` | PASS by construction (fixed pool, raw pointer loop); not verified with Instruments |
| Pointer | PASS in tests; live behaviour UNVERIFIED |
| Display-bottom accumulation | PASS | tests + screenshot |
| Window accumulation/displacement | PASS in unit tests; live AX tracking UNVERIFIED (permission not granted in this session) |
| Volume conservation | PASS | tests (retained + displaced + clipped = original within 1 %) |
| Reliability (display change, sleep/wake, revocation) | implemented, UNTESTED live |
| Metal failure | handled: init throws, UI shows message; not fault-injected |
| Privacy: no private APIs, no capture, no titles | PASS by code review |

## Known limitations
- **Z-order:** AX gives no occlusion data, so snow can rest on the top edge of a window hidden behind another window.
- Overlay sits at `.floating`: snow can fall behind other apps' floating panels and the menu bar/Dock.
- Snow settles on the visible-frame bottom (above the Dock); with the Dock hidden it sits on the display edge.
- Window ids come from `CFHash(AXUIElement)` (no public AX window id); ids may change if an app recreates a window, which releases its snow.
- Clipped snow beyond max depth leaves the system (counted in stats, not re-emitted).
- Debug "diagnostics" is a Settings panel, not an on-screen overlay.
- Sliding is modelled by height-field relaxation, not per-flake sliding state.

## Release blockers
Signing identity/bundle id, app icon, hands-on manual matrix (TESTING.md), Instruments profiling.

## Next improvements
Occlusion-aware window filtering, precompiled shaders, AXObserver events instead of polling, on-screen diagnostics.
