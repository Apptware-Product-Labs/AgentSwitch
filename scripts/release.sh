#!/usr/bin/env bash
# Builds a distributable zip. For a Gatekeeper-clean download, teammates need the app
# signed with a Developer ID and notarized:
#
#   CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE=agentswitch ./scripts/release.sh
#
# (Create NOTARY_PROFILE once with: xcrun notarytool store-credentials agentswitch)
# Without those, the zip is still produced; recipients must right-click ▸ Open the app.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
UNIVERSAL=${UNIVERSAL:-0} ./scripts/build_app.sh

APP="build/AgentSwitch.app"
ZIP="build/AgentSwitch-$VERSION.zip"
rm -f "$ZIP"

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP"
fi

ditto -c -k --keepParent "$APP" "$ZIP"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
fi

shasum -a 256 "$ZIP"
echo "Release: $ZIP"
