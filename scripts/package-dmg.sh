#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/whack-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
cp -R dist/Whack.app "$STAGING/Whack.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname Whack -srcfolder "$STAGING" -ov -format UDZO dist/Whack.dmg
if [ -n "${NOTARY_PROFILE:-}" ]; then
    if [ -z "${SIGNING_IDENTITY:-}" ] || [ "$SIGNING_IDENTITY" = "-" ]; then
        printf 'Notarization requires a Developer ID SIGNING_IDENTITY.\n' >&2
        exit 1
    fi
    xcrun notarytool submit dist/Whack.dmg --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple dist/Whack.dmg
    xcrun stapler validate dist/Whack.dmg
else
    printf 'Local development DMG created. Set SIGNING_IDENTITY and NOTARY_PROFILE for public distribution.\n'
fi
