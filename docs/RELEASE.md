# Releasing

1. Update `MARKETING_VERSION` in `project.yml` and add an entry to `CHANGELOG.md`.
2. Run the tests (see [TESTING.md](TESTING.md)).
3. Build the disk image: `scripts/make_dmg.sh` writes `dist/Snowfall-<version>.dmg`.
4. Tag the commit (`git tag v<version>`), push the tag, and create a GitHub release for it, attaching the `.dmg`.

   ```sh
   git tag v0.3.0 && git push origin v0.3.0
   gh release create v0.3.0 dist/Snowfall-0.3.0.dmg --title "Snowfall 0.3.0" --notes-file notes.md
   ```

## Signing and notarization

Releases are signed ad hoc and are not notarized, which is why users see a first-launch prompt (see the README).
To distribute a notarized build you need a paid Apple Developer account:

1. In `project.yml` set your `PRODUCT_BUNDLE_IDENTIFIER` and `DEVELOPMENT_TEAM`, and set `CODE_SIGN_IDENTITY` to
   `Developer ID Application`; run `xcodegen generate`.
2. Hardened runtime is already on. No entitlements are needed: no sandbox, no JIT, and the shaders are compiled with
   the public Metal API.
3. Archive and export (`method = developer-id`), then notarize with
   `xcrun notarytool submit Snowfall.zip --keychain-profile <profile> --wait` and staple the ticket with
   `xcrun stapler staple Snowfall.app`. Create the keychain profile yourself with `xcrun notarytool store-credentials`;
   never commit credentials.
4. Check with `spctl -a -vv Snowfall.app`.
