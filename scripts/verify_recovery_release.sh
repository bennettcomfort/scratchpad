#!/bin/bash
set -euo pipefail

xcodegen
xcodebuild -scheme Scratchpad -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/ScratchpadRelease build
xcodebuild -scheme Scratchpad -configuration Performance -destination 'platform=macOS' -derivedDataPath /tmp/ScratchpadRelease test
app_path=/tmp/ScratchpadRelease/Build/Products/Release/Scratchpad.app
entitlements_path="$(mktemp /tmp/ScratchpadReleaseEntitlements.XXXXXX)"
trap 'rm -f "$entitlements_path"' EXIT

codesign --verify --deep --strict "$app_path"
codesign -d --xml --entitlements "$entitlements_path" "$app_path"

entitlement_dump="$(plutil -p "$entitlements_path")"
[[ "$(/usr/bin/grep -c ' => ' <<< "$entitlement_dump")" -eq 3 ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$entitlements_path")" == true ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.user-selected.read-write' "$entitlements_path")" == true ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.bookmarks.app-scope' "$entitlements_path")" == true ]]
plutil -p "$entitlements_path"
git diff --check
