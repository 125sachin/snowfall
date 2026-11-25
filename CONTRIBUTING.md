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

1. Fork the repository, clone your fork, and run `scripts/setup_hooks.sh` once. It enables local checks for commit
   messages and branch names.
2. Create a branch from the latest `main` using the [branch naming rules](#branch-names).
3. Keep the change small and focused. Add or update tests for behaviour you change. The simulation is deterministic
   (seeded) so it is easy to test.
4. Run `scripts/precheck.sh --full` before you push (see [Before you open a pull request](#before-you-open-a-pull-request)).
5. Open a pull request against `main` and fill in the template.

### Branch names

Use `<type>/<short-kebab-case-description>`, optionally starting with an issue number.

- `<type>` is one of the commit types below.
- Use lowercase letters, digits and hyphens only, and at most 60 characters in total.
- Examples: `feat/reindeer-helper`, `fix/123-flicker-on-wake`, `docs/building-guide`.

`main` is protected: nothing is pushed to it directly. `release/<x.y.z>` and `dependabot/*` are reserved for
maintainers and bots.

### Commit messages

This project uses [Conventional Commits](https://www.conventionalcommits.org/).

```
<type>(<optional-scope>): <description>

<optional body: why the change is needed>

<optional footers>
```

- **Type** is one of: `feat` (new behaviour), `fix` (bug fix), `docs`, `style` (formatting only), `refactor`, `perf`,
  `test`, `build` (build system, dependencies, packaging), `ci`, `chore`, `revert`.
- **Scope** is optional, lowercase, and names the area: `helpers`, `rendering`, `simulation`, `tracking`, `overlay`,
  `app`, `ui`, `settings`, `docs`.
- **Description** is in the imperative mood ("add penguin helper", not "added" or "adds"), starts with a lowercase
  letter, has no trailing period, and keeps the whole first line to 72 characters or fewer.
- **Body** is separated from the subject by a blank line, explains *why* rather than *what*, and is wrapped at 100
  characters.
- **Breaking changes** add `!` after the type or scope (`feat(settings)!: rename the helper option`) and a
  `BREAKING CHANGE: <what changed and how to migrate>` footer.
- **Issues** are referenced in a footer: `Fixes #123`.
- One logical change per commit. The commit message is checked by `scripts/check_commit_msg.sh` locally (the
  `commit-msg` hook) and in CI.

Examples:

```
feat(helpers): add reindeer sleigh flyby
fix(tracking): ignore windows with zero alpha
docs: explain how to build the disk image
```

### Before you open a pull request

Run `scripts/precheck.sh` (add `--full` to also build and test). It runs the same checks as CI:

| Check | Rule |
| --- | --- |
| Working tree | No uncommitted changes. |
| Branch name | Matches the [naming rules](#branch-names). |
| Up to date | The branch is rebased on the latest `origin/main` and has no conflicts. |
| Commit messages | Every commit follows the rules above. |
| Conflict markers and artifacts | No `<<<<<<<` markers, `.dmg`, `.app`, `build/`, `dist/` or `.DS_Store` files. |
| SwiftLint | `swiftlint lint --strict` reports nothing (`brew install swiftlint`). |
| Build and tests | `xcodegen generate` then `xcodebuild -scheme Snowfall -destination 'platform=macOS' test` passes. |

Resolve conflicts by rebasing, not by merging `main` into your branch:

```sh
git fetch origin
git rebase origin/main          # fix conflicts, then: git add <files> && git rebase --continue
git push --force-with-lease     # only on your own branch
```

### Pull requests

- Target `main`. Keep the pull request focused; split unrelated changes.
- The **title** must follow the commit message rules, because it becomes the commit on `main` (pull requests are
  squash-merged). Describe what changed and why, how you tested it, and link the issue.
- CI must pass (SwiftLint, build and tests, and the conventions check) and the branch must be up to date with `main`.
- A maintainer review is required. Address review comments with new commits; they are squashed on merge.
- Update `CHANGELOG.md` for user-visible changes.

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

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Be kind and assume good intent.
