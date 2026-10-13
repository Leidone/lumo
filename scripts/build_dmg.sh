#!/bin/bash
# Builds Lumo.app (universal: Apple Silicon + Intel) and packs it into Lumo.dmg.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Lumo.app"
DMG="$BUILD/Lumo.dmg"
STAGING="$BUILD/dmg"

cd "$ROOT"
echo "→ Running tests"
swift test --quiet

echo "→ Compiling release (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

echo "→ Assembling Lumo.app"
rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Lumo" "$APP/Contents/MacOS/Lumo"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "→ Building Now Playing bridge"
clang -dynamiclib -fobjc-arc -O2 -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 -framework Foundation \
  Helpers/NowPlaying.m -o "$APP/Contents/Resources/LumoNowPlaying.dylib"
clang -O2 -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 -framework IOKit -framework CoreFoundation \
  Helpers/FanHelper.c -o "$APP/Contents/Resources/lumo-fan"

echo "→ Rendering app icon"
swift scripts/make_icon.swift "$BUILD/AppIcon.iconset" >/dev/null
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$BUILD/AppIcon.iconset"

echo "→ Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"
codesign --verify --strict "$APP"

echo "→ Creating DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cp "Resources/Install Instructions.txt" "$STAGING/Install Instructions.txt"
hdiutil create -volname "Lumo" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo "✓ Done: $DMG"
