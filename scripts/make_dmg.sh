#!/bin/bash
# Build a drag-to-Applications DMG from the assembled UsageMeter.app.
# Run via `make dmg` (which builds the .app first).
set -euo pipefail

APP_NAME="UsageMeter"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
DMG="$BUILD_DIR/$APP_NAME.dmg"
STAGING="$BUILD_DIR/dmg-staging"
VOLNAME="$APP_NAME"

if [ ! -d "$APP" ]; then
    echo "error: $APP not found — run 'make bundle' first." >&2
    exit 1
fi

# Read the app version so the DMG can be named consistently if desired.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$APP/Contents/Info.plist" 2>/dev/null || echo "")"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"

# Contents of the mounted disk image: the app plus an Applications shortcut,
# so the user just drags one onto the other.
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "$VOLNAME" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO -ov \
    "$DMG" >/dev/null

rm -rf "$STAGING"

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
echo "Created $DMG (${SIZE}${VERSION:+, v$VERSION})"
echo "Share it; recipients drag UsageMeter into Applications."
