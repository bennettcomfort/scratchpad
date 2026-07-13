#!/usr/bin/env bash
# Usage: APPLE_ID=you@x.com TEAM_ID=XXXX APP_PASSWORD=app-specific ./scripts/build_and_notarize.sh
set -euo pipefail
: "${APPLE_ID:?}" "${TEAM_ID:?}" "${APP_PASSWORD:?}"
xcodegen
xcodebuild -scheme Scratchpad -configuration Release -destination 'platform=macOS' \
  -archivePath build/Scratchpad.xcarchive archive
ditto -c -k --keepParent build/Scratchpad.xcarchive/Products/Applications/Scratchpad.app build/Scratchpad.zip
xcrun notarytool submit build/Scratchpad.zip \
  --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD" --wait
xcrun stapler staple build/Scratchpad.xcarchive/Products/Applications/Scratchpad.app
spctl -a -vv build/Scratchpad.xcarchive/Products/Applications/Scratchpad.app
echo "Notarization + stapling complete. Gatekeeper check passed."

# DMG
mkdir -p build/dmg
cp -R build/Scratchpad.xcarchive/Products/Applications/Scratchpad.app build/dmg/
ln -sf /Applications build/dmg/Applications
hdiutil create -volname Scratchpad -srcfolder build/dmg -ov -format UDZO build/Scratchpad.dmg
rm -rf build/dmg
echo "DMG created: build/Scratchpad.dmg"
