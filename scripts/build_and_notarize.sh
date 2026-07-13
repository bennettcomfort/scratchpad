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
echo "Notarization dry-run complete."
