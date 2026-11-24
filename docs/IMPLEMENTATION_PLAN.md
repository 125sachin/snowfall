# Snowfall — Implementation Plan

Derived from `SOURCE_PLAN.md`. Milestone numbers follow section 13 there.

## Environment (verified)
macOS 26.6.2, Xcode 26.6, Swift 6.3.3, XcodeGen present. Greenfield repo; no prior code.
Deployment target: **macOS 14.0** (needed for `@Observable`, `openSettings`, modern `MenuBarExtra`).

## Architecture
SwiftUI `@main` app with `MenuBarExtra(.window)` + `Settings` scene; `LSUIElement` = menu-bar only.
`AppCoordinator` (runtime state) owns `SettingsStore` (persisted, validated). Later modules per
SOURCE_PLAN §4: Overlay, Tracking, Simulation, Rendering, Diagnostics — each independent.

## Coordinate system (canonical)
Global logical points, AppKit convention (origin bottom-left of primary display, +y up). Convert to
per-display local / Metal pixel space only at render time; AX (top-left origin) converted at the tracker edge.

## Permissions & fallback
- Overlay + falling snow + display-bottom accumulation: no permissions.
- Pointer tracking: `NSEvent.mouseLocation` polling needs no permission (to be verified in M6).
- Window physics: Accessibility; if denied, everything else keeps working.

## Risks
Overlay window level vs. menu bar/Dock/full-screen apps; Spaces behaviour; AX data incompleteness;
multi-display coordinate flips. Each is validated manually in its milestone, not assumed.

## Milestones
| # | Milestone | Status |
|---|-----------|--------|
| 1 | Repo inspection / plan | done |
| 2 | App foundation, menu bar, settings | **built, see tests** |
| 3 | Transparent click-through overlay | next |
| 4 | Particle simulation | |
| 5 | Metal renderer | |
| 6 | Pointer disturbance | |
| 7 | Display-bottom accumulation | |
| 8–10 | Window tracking, surfaces, window physics | |
| 11 | Displays / Spaces / sleep-wake | |
| 12 | Performance | |
| 13 | Packaging & audit | |

## Known limitations
Bundle ID is the placeholder `com.example.Snowfall`; signing is ad-hoc (`-`) until the user supplies an identity.
