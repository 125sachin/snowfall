#!/bin/sh
# Builds a Release app and packs it into dist/Snowfall-<version>.dmg.
# The app is signed ad hoc ("-"); notarization needs a paid Apple Developer account (see docs/RELEASE.md).
set -eu
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null || { echo "xcodegen is required: brew install xcodegen" >&2; exit 1; }
xcodegen generate >/dev/null
xcodebuild -scheme Snowfall -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build build | tail -1

APP="build/Build/Products/Release/Snowfall.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE" "$TMP_DMG"' EXIT
TMP_DMG="$(mktemp -u).dmg"

# --norsrc/--noextattr keep Finder metadata out of the signed bundle.
ditto --norsrc --noextattr "$APP" "$STAGE/Snowfall.app"
ln -s /Applications "$STAGE/Applications"
codesign --force --deep -s - "$STAGE/Snowfall.app"

mkdir -p dist
OUT="dist/Snowfall-$VERSION.dmg"
rm -f "$OUT"
# makehybrid + convert is more reliable than `hdiutil create` when Spotlight/Finder hold the volume busy.
hdiutil makehybrid -hfs -hfs-volume-name Snowfall -o "$TMP_DMG" "$STAGE" >/dev/null
hdiutil convert "$TMP_DMG" -format UDZO -o "$OUT" >/dev/null
hdiutil verify "$OUT" | tail -1
echo "Created $OUT ($(du -h "$OUT" | cut -f1))"
