# Building Snowfall

Requirements: macOS 14 or later, Xcode 26 (Swift 6 language mode) and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
xcodegen generate                       # creates Snowfall.xcodeproj from project.yml
xcodebuild -scheme Snowfall -destination 'platform=macOS' build
xcodebuild -scheme Snowfall -destination 'platform=macOS' test
xcodebuild -scheme Snowfall -configuration Release -destination 'platform=macOS' -derivedDataPath build build
open build/Build/Products/Release/Snowfall.app
```

The Xcode project is generated and not committed. Change targets and settings in `project.yml`, then run
`xcodegen generate` again.

## Disk image

`scripts/make_dmg.sh` builds a Release app and writes `dist/Snowfall-<version>.dmg` (ad-hoc signed). The version comes
from `MARKETING_VERSION` in `project.yml`.

## Notes

- **Shaders are embedded** as strings in `Rendering/ShaderSource.swift` and compiled at launch, so the optional Metal
  Toolchain component is not required. To use precompiled `.metal` files instead, install it with
  `xcodebuild -downloadComponent MetalToolchain` and move the sources into `.metal` files.
- **Signing:** the project uses ad-hoc signing (`CODE_SIGN_IDENTITY: "-"`, "Sign to Run Locally"), so it builds and runs
  without an Apple Developer account. The bundle identifier is `com.xcode.snowfall`. To use your own, change
  `PRODUCT_BUNDLE_IDENTIFIER` and set `DEVELOPMENT_TEAM` in `project.yml`.
- **Architecture:** by default Xcode builds for your Mac's architecture. For a universal binary add
  `ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO` to the `xcodebuild` command.
- The app is menu-bar only (`LSUIElement`), so it has no Dock icon while running.
