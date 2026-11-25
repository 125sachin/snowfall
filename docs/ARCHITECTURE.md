# Architecture

Snowfall is a menu-bar app (`LSUIElement`) built with SwiftUI, AppKit and Metal. This document describes how the
pieces fit together and the decisions behind them.

## Modules

| Module | Role |
|---|---|
| `App` | `SnowfallApp` (the `MenuBarExtra` and Settings scenes), `AppDelegate`, and `AppCoordinator`, which owns runtime state and wires everything together. |
| `Settings` | Persisted, validated settings (`SnowfallSettings`, `SettingsStore`) and launch-at-login. |
| `UI` | The menu-bar popover, the Settings window and the diagnostics view. |
| `Overlay` | One borderless, transparent, click-through `NSPanel` per display, and the display model. |
| `Tracking` | Pointer position (`NSEvent.mouseLocation`) and window geometry (`CGWindowListCopyWindowInfo`). |
| `Simulation` | The physics world, snow accumulation, and all helpers. Runs on its own queue. |
| `Rendering` | The Metal renderer, shaders (embedded as source) and the sprite art. |
| `Diagnostics` | Logging and a small performance monitor. |

Rendering, simulation, tracking and UI are kept separate: the main thread does no physics, and renderers only read
immutable snapshots.

## Coordinates

Everything is in **global logical points, AppKit convention** (origin at the bottom-left of the primary display, +y
up). Window-server rectangles (top-left origin) are converted at the tracking edge, and Metal pixel space is used only
when drawing.

## Windows and stacking

Windows come from the window server's on-screen list: owner process, window number, bounds, layer, alpha and
front-to-back order. Titles and pixels are never read, and no permission is needed. Each eligible window becomes a
collision surface whose top edge holds snow. A window's top corners are quarter circles (16 pt) and snow follows the
curve. Snow on an edge covered by a window in front is hidden and reappears when the cover moves; new snow lands on
whichever window is in front.

## Simulation

- Fixed time step of 1/120 s, at most 8 sub-steps per tick, elapsed time clamped to 0.25 s.
- A dedicated serial queue runs the simulation and publishes a lock-protected immutable snapshot; renderers never wait
  for physics.
- Falling flakes live in a fixed-capacity pool (no allocation in the hot loop).
- **Settled snow** is a per-surface height field (at most 1024 bins) with angle-of-repose relaxation, a maximum depth
  and bounded shedding at window edges.
- **Window motion:** below a stick speed snow is carried along; above it a growing fraction slips off as at most 24
  clusters. Closed windows release their snow as bounded clusters. Volume is conserved, and tests check it.
- Quality adapts: the particle density scales down if the simulation or frame rate falls behind.

## Rendering

- Shaders are Metal Shading Language embedded as strings and compiled at launch (`makeLibrary(source:)`), so the
  optional Metal Toolchain component is not needed to build.
- Premultiplied alpha. Flakes are instanced quads; the flake shape is computed in the fragment shader (a six-fold
  symmetric crystal), and half of the flakes sample an SVG-derived mask instead. Settled snow is drawn as a triangle
  list per surface.
- The overlay renders at the display's native scale with two drawables. Helper artwork is built on first use and
  released after 20 s of not being drawn.

## Overlay behaviour

Windows sit at the `.floating` level: above normal windows, below the Dock and menu bar so system UI and prompts are
never covered. They join all Spaces, are click-through, and are re-asserted when an app activates or the Space changes.
A display whose front-most window fills it (a full-screen app) is hidden and its buffers freed; if every display is
covered, simulation stops.

## Power

Animation is kept alive with an activity that allows idle system sleep. The frame rate is 60 FPS, 30 FPS on battery,
Low Power Mode or a hot machine, and 15 FPS after 3 minutes without input. Pointer sampling is 30 Hz and runs only when
enabled; the window poll slows down when nothing moves.

## Snow helpers

### JCB snow plow
A procedurally drawn backhoe loader (Core Graphics → Metal textures, rotating wheels) drives right → left on the display floor.
Physics (pt, s): speed' = engine − drag·speed − load·min(carried, 2·capacity); unloaded top speed 90 pt/s, ~45 pt/s fully loaded.
The blade sweeps the floor height field down to a 1 pt residue; swept snow becomes the carried pile in front of the blade.
Beyond blade capacity (1500 pt²) snow spills over the pile and is thrown faster than the blade so it lands ahead; relaxation
is blocked across the blade so snow cannot slump through it; a pile too deep ahead is pushed along. At the end of the floor the
pile is dumped (counted as lost volume). Runs automatically every N minutes (default 3) when the floor holds snow, or on demand
(menu "Send Plow", Settings → Snow). Dev flag: `--args -plowAfterSeconds 30`.

### How helpers work
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
**Fun helpers** (`FunHelpers.swift`, drawn as generic `RenderProp` sprites by `PropSprites.swift`): **Penguin** belly-slides right → left along the floor, ploughing a 84 pt strip clear and spraying flakes.
**Snowball fight:** a kid walks the floor and every ~1 s throws a snowball on a ballistic arc (flight 0.5–1.0 s, g = 900) at the biggest pile ahead (blasts a 55 pt disc), a point on a window (leaves a splat decal that fades after 5 s) or the floor.
**Snowman builder:** a kid pushes a snowball left along the floor; it sweeps everything under it and grows (R = √(14² + 0.9·collected/π), max 58), then, at the bottom-left corner of the screen, stacks a snowman (kept ≤ 3 at once, melts away after 55 s) and waves goodbye.
**Sleigh flyby:** Santa's sleigh (drawn at 55% of its 560 × 150 art, so ~308 × 83 pt) crosses at 520 pt/s, climbing over the tallest surface within 1000 pt ahead; its downdraught clears snow from surfaces below (strength rises as the gap closes below 200 pt),
airborne flakes within ~147 pt are thrown aside, and it leaves a glitter trail. Floor-only helpers (JCB, penguin, snowman) need floor snow; the others accept snow anywhere.
**Adding a helper:** see the checklist in [CONTRIBUTING.md](../CONTRIBUTING.md#adding-a-snow-helper).
