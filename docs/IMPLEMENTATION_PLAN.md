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
All 13 milestones are implemented; see `FINAL_AUDIT.md` for verification status and gaps.

## Design decisions (as built)
- Overlay: `NSPanel` per display at `.floating`, click-through, `canJoinAllSpaces + fullScreenAuxiliary + stationary`.
- Simulation: dedicated queue, 1/120 s fixed step, ≤8 substeps, elapsed clamped to 0.25 s; renderers read lock-protected snapshots.
- Settled snow: per-surface height field (≤1024 bins), angle-of-repose relaxation, max depth clip, bounded edge shedding on windows.
- Window motion: below the stick speed snow is carried; above it a growing fraction slips/falls as ≤24 clusters; volume is conserved; closed windows release their snow as bounded clusters; removed displays drop theirs.
- Rendering: MSL compiled at runtime, premultiplied alpha, instanced procedural flakes, triangle-list snow surfaces, two reused buffer sets.

## Known limitations
Bundle ID is the placeholder `com.xcode.snowfall`; signing is ad-hoc (`-`) until the user supplies an identity.
