# Building Snowfall

Requirements: macOS 14+ (built on 26.6), Xcode 26 (Swift 6 language mode), XcodeGen (`brew install xcodegen`).

```sh
xcodegen generate                       # creates Snowfall.xcodeproj from project.yml
xcodebuild -scheme Snowfall -destination 'platform=macOS' build
xcodebuild -scheme Snowfall -destination 'platform=macOS' test
xcodebuild -scheme Snowfall -configuration Release -destination 'platform=macOS' -derivedDataPath build build
open build/Build/Products/Release/Snowfall.app
```

## Notes
- **Shaders are embedded** as MSL strings (`Rendering/ShaderSource.swift`) and compiled at launch with
  `makeLibrary(source:)`. The optional *Metal Toolchain* component was not installed when this was
  written, and runtime compilation avoids requiring it. If you prefer precompiled `.metal` files, run
  `xcodebuild -downloadComponent MetalToolchain` and move the sources into `.metal` files.
- The bundle identifier is the placeholder `com.xcode.snowfall`; signing is ad-hoc (`-`).
  Set your team and identifier in `project.yml` (`PRODUCT_BUNDLE_IDENTIFIER`, `DEVELOPMENT_TEAM`).
- The app is `LSUIElement` (menu bar only, no Dock icon). There is no app icon yet (empty AppIcon set).
