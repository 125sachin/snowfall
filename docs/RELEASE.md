# Release

1. Set `PRODUCT_BUNDLE_IDENTIFIER` and `DEVELOPMENT_TEAM` in `project.yml`; `CODE_SIGN_IDENTITY` to `Developer ID Application`; `xcodegen generate`.
2. Hardened runtime is already on (`ENABLE_HARDENED_RUNTIME`). No entitlements are required: no sandbox, no
   JIT, shaders are compiled via the public Metal API.
3. Archive: `xcodebuild -scheme Snowfall -configuration Release archive -archivePath build/Snowfall.xcarchive`, then export with an
   `ExportOptions.plist` (`method = developer-id`).
4. Notarize: `xcrun notarytool submit Snowfall.zip --keychain-profile <your-profile> --wait` then `xcrun stapler staple Snowfall.app`.
   Create the keychain profile yourself with `xcrun notarytool store-credentials`; no credentials are in this repo.
5. Verify: `spctl -a -vv Snowfall.app`, then run the manual matrix in TESTING.md.

Open items before shipping: real bundle ID and signing identity, app icon, the unverified manual tests in TESTING.md.
