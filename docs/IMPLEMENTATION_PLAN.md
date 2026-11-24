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

## Snow plow (JCB)
A procedurally drawn backhoe loader (Core Graphics → Metal textures, rotating wheels) drives right → left on the display floor.
Physics (pt, s): speed' = engine − drag·speed − load·min(carried, 2·capacity); unloaded top speed 90 pt/s, ~45 pt/s fully loaded.
The blade sweeps the floor height field down to a 1 pt residue; swept snow becomes the carried pile in front of the blade.
Beyond blade capacity (1500 pt²) snow spills over the pile and is thrown faster than the blade so it lands ahead; relaxation
is blocked across the blade so snow cannot slump through it; a pile too deep ahead is pushed along. At the end of the floor the
pile is dumped (counted as lost volume). Runs automatically every N minutes (default 3) when the floor holds snow, or on demand
(menu "Send Plow", Settings → Snow). Dev flag: `--args -plowAfterSeconds 30`.

## Snow helpers (pluggable)
`HelperKind` (jcb, santa, random) is chosen in the menu or Settings → Snow → Snow helper; it runs on demand or automatically every N
minutes when it has snow to clear (the JCB needs floor snow, Santa accepts any surface). Only one helper runs at a time.
**Santa:** flies in from the upper right, flourishes a wand (glitter particles at the tip), conjures a tornado at the right edge that
sweeps right → left across the whole width. The funnel is a cone of orbiting particles (kinematic, phase/radius per particle, near
side brighter/larger). Every surface whose top edge lies inside the funnel (floor and window tops) is swept under the funnel's catch
zone; lifted snow becomes swirling clusters that rise, then are flung off at the top (their volume is counted as lost). Airborne (not yet settled) flakes are taken too, strictly in the direction of travel: everything BEHIND the tornado (to its right) is captured at once and
streams into the funnel, so the right side is empty as it passes; snow AHEAD of it is drawn in only within reach (320 pt) and otherwise taken on arrival.
Thrown-out flakes always fly left and fade away. New snow does not spawn until the tornado has left. Flakes the tornado has thrown out are marked (orbitRadius = -1) so they are not re-captured. Santa follows
behind, then flies off.
**Iron Man:** flies in from the right, tilted forward, and heads left at 130 pt/s, adjusting altitude to clear the tallest window ahead. Two eye beams
sweep ahead of him out of phase: one lands on the highest surface under its target (a window top), the other on the floor. Heat model: depth melted per
second = 450 · exp(−d²/2σ²) (σ = 14 pt) around the spot, so melting is local and needs a few passes for deep snow; melted volume is counted as lost and
produces rising, expanding, fading steam puffs. Airborne flakes crossing a beam segment are vaporized (their snow is melted too).
**Thor:** picks 2–3 sites on snowy surfaces (weighted by snow volume, ≥260 pt apart, visited right → left), flies in, lands with the hammer head on the snow
top, and swings twice per site on a fixed timeline (wind-up 0.5 s, blow 1 at 0.64 s, recover, blow 2 at 1.40 s). Blow 1 cracks the ice layer (radius 85 pt, up to 65%
of depth removed, falling off toward the edge); blow 2 shatters it (radius 155 pt, everything in the core removed). Removed volume is thrown out as fading ice shards
(counted as lost), airborne snow within 1.6× the radius is blasted outward, and each blow draws a lightning bolt from the sky, a shockwave ring, a crack pattern that fades
after 3 s, and a flash. He does not clear the whole floor — only the spots he hits.
**Spider-Man:** swings in from the right on webs, always heading left. Each swing is a rigid-rope pendulum (g = 900, small leftward pump below the anchor so he
keeps going). The next anchor is placed ahead-left and above (rise 360 pt) with dx = √(H² + 2·H·dy), which makes the rope L = H + dy so the lowest point of the arc is
exactly the skim line (feet 6 pt above the surface base); he lets go on the far side and webs the next anchor. His feet scrape a furrow through the snow (everything above
foot level within ±26 pt of his path), shedding fading spray. Every ~2 s a web ball is fired at the biggest 120 pt-wide pile 130–950 pt ahead; it lands as a web patch, then
a yank tears the clump off (radius 70 pt, shatter profile) and hauls the chunks toward him before they fade. Every ~3 s he spins a net (radius 150 pt) ahead of him that
captures airborne flakes touching it for 0.55 s. All removed snow is counted as lost; he exits up-left past the left edge.
**Adding a helper:** see the checklist on `HelperKind`.

## Known limitations
Bundle ID is the placeholder `com.xcode.snowfall`; signing is ad-hoc (`-`) until the user supplies an identity.
