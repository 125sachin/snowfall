# Contributing

Thanks for helping out. Bug reports, ideas and pull requests are all welcome.

## Reporting a bug

Open an issue and include your macOS version, your Mac model, how many displays you use, what you expected and what
happened. A short screen recording helps a lot. Please do not attach anything that shows private content.

## Setting up

See [docs/BUILDING.md](docs/BUILDING.md). In short: install Xcode 26 and XcodeGen, run `xcodegen generate`, then build
and run the tests with `xcodebuild`. The Xcode project is generated from `project.yml` and is not committed; change the
project settings in `project.yml`, not in Xcode.

## Making a change

1. Fork the repository and create a branch from `main`.
2. Keep the change small and focused, and run the tests before you push:
   `xcodebuild -scheme Snowfall -destination 'platform=macOS' test`.
3. Add or update tests for behaviour you change. The simulation is deterministic (seeded) so it is easy to test.
4. Open a pull request that explains what changed and why.

### Commit messages

Write the subject line in the imperative mood ("Add penguin helper", not "Added" or "Adds"), at most about 70
characters, followed by a blank line and a short explanation of *why* when it is not obvious. One logical change per
commit.

### Code guidelines

- Swift 6 with strict concurrency. Rendering, simulation, tracking and UI stay separate; the main thread does no physics.
- Positions are in global AppKit points (origin bottom-left, y up). Convert to anything else only at the edge.
- Physics uses a fixed time step, bounded storage, and no allocation in the hot loop.
- No private APIs, no screen capture, no input monitoring, no new permissions.
- Do not add controls that do nothing: unfinished features should be disabled and labelled.

## Adding a snow helper

Helpers are characters or machines that clear settled snow. The checklist is also on `HelperKind`:

1. Add a case to `HelperKind` (and to `concrete`) with a label, short label and summary. The menu and Settings pickers
   pick it up automatically.
2. Add its run state and `startX` / `stepX` functions to `PhysicsWorld` (see `FunHelpers.swift` for the simplest
   examples), call them from `startHelper`, `step` and `isHelperRunning`, and decide in `volume(_:)` whether it needs
   floor snow or any snow.
3. Draw it: for a simple character, emit `RenderProp` sprites from `fillProps` and add the artwork to
   `PropSprites.swift`. Larger helpers can have their own render types and draw functions.
4. Account for removed snow in `totals.lostVolume` and add tests (see `Tests/FunHelperTests.swift`).

## Code of conduct

Be kind and assume good intent. Harassment and personal attacks are not welcome.
