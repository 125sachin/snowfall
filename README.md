# Snowfall

Realistic snow for your Mac desktop. Snowfall is a small menu-bar app that draws falling snow over everything you
are doing, lets it pile up on the bottom of the screen and on the tops of your windows, and sends in little
characters to clear it away again.

- Native macOS app: Swift 6, SwiftUI, AppKit and Metal. No dependencies.
- The snow never gets in the way: the overlay is transparent and click-through.
- No special permissions, no network access, no analytics.

## Features

- **Falling snow** with crystal-shaped flakes, wind, and an adjustable amount and speed.
- **Snow piles up** on the bottom of the screen and on the top edge of the front-most windows, and slides off or is
  carried along when you move a window. Window corners are rounded, so snow follows the curve.
- **Readable on light and dark backgrounds:** on light backgrounds the flakes and piles get a cool outline so they stay
  visible. It follows the system appearance, or you can force it in Settings → Snow.
- **Mouse interaction:** move the pointer through the snow and it scatters.
- **Snow helpers** that clear the snow, chosen from the menu or in Settings (or "Surprise me"):

  | Helper | What it does |
  |---|---|
  | JCB snow plow | Drives right to left along the bottom, pushing the settled snow ahead of its blade. |
  | Santa's magic tornado | Waves a wand and sweeps a tornado across the screen that lifts snow off the floor and window tops. |
  | Iron Man's eye lasers | Flies in and melts settled snow into steam with twin lasers. |
  | Thor's hammer | Works across every snowy surface, shattering the ice layer with two hammer blows at each spot until it is all gone. |
  | Spider-Man's web swing | Swings in on webs, shooting webs at piles that tear the whole area clear, and netting falling flakes. |
  | Sliding penguin | Belly-slides along the floor, ploughing a strip clear. |
  | Snowball fight | Two kids on opposite sides throw snowballs at each other and across the screen, blasting piles and splatting on windows. |
  | Snowman builder | Rolls and stacks three snowballs and dresses a snowman (hat, scarf, carrot nose) in the bottom-left corner. |
  | Santa's sleigh flyby | A sleigh and reindeer sweep across; the downdraught blows snow off the surfaces below. |

  Helpers can run on demand or automatically every few minutes when there is snow to clear.
- **Multiple displays**, with a per-display on/off switch.
- **Light on resources:** it pauses under full-screen apps, drops to 30 FPS on battery and to 15 FPS when you are
  away, and frees its buffers when hidden.

> The helper characters are original, simple illustrations drawn in code. They are not affiliated with or endorsed by
> any studio or rights holder.

## Download

Snowfall is distributed as a `.dmg`.

1. Open the **[latest release](https://github.com/125sachin/snowfall/releases/latest)** and download
   `Snowfall-<version>.dmg` from the **Assets** list.
2. Open the downloaded file and drag **Snowfall** onto the **Applications** shortcut.
3. Eject the disk image, then open **Snowfall** from Applications (or Spotlight).
4. A snowflake appears in the menu bar. Click it to pause, change settings or send a helper.

**Requirements:** macOS 14 (Sonoma) or later on a Mac with Apple silicon. The current download is built for
Apple silicon only; on an Intel Mac, [build from source](#build-from-source).

### First launch: "Apple could not verify Snowfall"

The app is signed only with an ad-hoc signature and is **not notarized** (that needs a paid Apple Developer
account), so macOS asks you to confirm the first launch. Do **one** of these:

- **macOS 15 or later:** try to open Snowfall once, then go to **System Settings → Privacy & Security**, scroll down
  to the message about Snowfall, click **Open Anyway** and confirm.
- **macOS 14:** right-click Snowfall in Applications, choose **Open**, then **Open**.
- **Any version, from Terminal:** `xattr -dr com.apple.quarantine /Applications/Snowfall.app`, then open it normally.

You only have to do this once. If you would rather not run an unsigned binary, build it yourself (below).

### Start at login

Settings → General → **Launch at login**. It is managed by macOS and listed in System Settings → General →
Login Items.

### Uninstall

Quit Snowfall from its menu, delete `Snowfall.app` from Applications, and optionally remove its settings with
`defaults delete com.xcode.snowfall`.

## Using it

Click the snowflake in the menu bar.

- The switch turns snowfall on and off. **Pause / Resume** freezes it; **Clear Snow** removes what has settled.
- **Intensity** and **Wind** adjust the snow. **Accumulation**, **Mouse interaction** and **Window physics** turn
  those features on and off.
- Pick a helper in the list and click **Send** to run it now.
- **Settings…** has the full set: density, fall speed, opacity, maximum snow depth, helper schedule, pointer radius
  and strength, displays, frame rate and a low-power mode.

## Privacy and permissions

Snowfall asks for **no permissions**.

- It reads only the cursor position, and each window's position, size and stacking order from macOS. It never reads
  window titles or contents, never captures the screen, and never observes clicks or keystrokes.
- It makes no network connections and collects nothing.
- It is not sandboxed, because reading other apps' window positions is not compatible with the App Sandbox.

Details are in [docs/PERMISSIONS.md](docs/PERMISSIONS.md).

## Build from source

You need macOS 14+, Xcode 26 (Swift 6) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
git clone https://github.com/125sachin/snowfall.git
cd snowfall
xcodegen generate                 # creates Snowfall.xcodeproj from project.yml
xcodebuild -scheme Snowfall -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build build
open build/Build/Products/Release/Snowfall.app
```

Run the tests with `xcodebuild -scheme Snowfall -destination 'platform=macOS' test`. To make a disk image, run
`scripts/make_dmg.sh`. More in [docs/BUILDING.md](docs/BUILDING.md).

## Project layout

```
Snowfall/        app source
  App/           app entry point and coordinator
  Overlay/       one transparent click-through window per display
  Tracking/      pointer and window tracking
  Simulation/    physics, snow accumulation and the helpers
  Rendering/     Metal renderer, shaders and sprites
  Settings/ UI/  persisted settings, menu bar and Settings windows
Tests/           XCTest suite
docs/            architecture, building, permissions, testing, releasing
scripts/         release tooling
tools/           app icon generator
project.yml      XcodeGen project definition
```

Design notes are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Known limitations

- Apple silicon only in the published download; not notarized.
- The overlay sits above normal windows but below the menu bar and Dock, so snow can fall behind other apps'
  floating panels.
- Only windows listed by the window server are tracked; popovers and panels at other levels do not collect snow.
- Tested on one built-in display. Several displays, Spaces, sleep/wake and hot-plugging are implemented but have had
  little hands-on testing. See [docs/TESTING.md](docs/TESTING.md).

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md); it also explains how to add a new
helper.

## License

[MIT](LICENSE).
