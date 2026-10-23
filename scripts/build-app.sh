#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-release}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
APP="$(pwd)/dist/Whack.app"
swift build -c "$CONFIGURATION" --product Whack
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Whack" "$APP/Contents/MacOS/Whack"
# Put resources inside Contents so the bundle can be signed and sealed normally.
for RESOURCE in "$BIN_DIR/Whack_Whack.bundle" "$BIN_DIR/Whack_WhackCore.bundle"; do
    NAME="$(basename "$RESOURCE")"
    rm -rf "$APP/$NAME" "$APP/Contents/Resources/$NAME"
    cp -R "$RESOURCE" "$APP/Contents/Resources/$NAME"
done
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
if [ "$SIGNING_IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"
printf 'Built %s\n' "$APP"
