#!/bin/zsh
# Direct-distribution release: Developer ID signing, notarization, stapling, and a zip for download.
#
# Prerequisites (one time):
#   1. A "Developer ID Application" certificate in your login keychain.
#   2. A notarytool keychain profile:
#        xcrun notarytool store-credentials kazoo-notary \
#          --apple-id "<apple-id>" --team-id "<TEAMID>" --password "<app-specific-password>"
#
# Usage:
#   DEVELOPER_ID="Developer ID Application: PipBoxes (TEAMID)" TEAM_ID=TEAMID \
#   NOTARY_PROFILE=kazoo-notary Scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEVELOPER_ID:?Set DEVELOPER_ID to your Developer ID Application identity}"
: "${TEAM_ID:?Set TEAM_ID}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"

mkdir -p build dist
xcodebuild \
  -project Kazoo.xcodeproj -scheme Kazoo -configuration Release \
  -derivedDataPath build/DerivedData -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$DEVELOPER_ID" DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
  build > build/release.log 2>&1 || { tail -40 build/release.log >&2; exit 1; }

APP=build/DerivedData/Build/Products/Release/Kazoo.app
rm -rf dist/Kazoo.app && ditto "$APP" dist/Kazoo.app
# Re-sign nested code inside-out with hardened runtime and a secure timestamp.
find dist/Kazoo.app/Contents -type f \( -perm -u+x -o -name "*.dylib" \) -print0 |
  xargs -0 -I{} codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID" "{}" 2>/dev/null || true
codesign --force --timestamp --options runtime \
  --entitlements Kazoo/Kazoo.entitlements --sign "$DEVELOPER_ID" dist/Kazoo.app
codesign --verify --deep --strict --verbose=2 dist/Kazoo.app

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" dist/Kazoo.app/Contents/Info.plist)
ZIP="dist/Kazoo-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent dist/Kazoo.app "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple dist/Kazoo.app
spctl --assess --type execute --verbose dist/Kazoo.app
rm -f "$ZIP" && ditto -c -k --keepParent dist/Kazoo.app "$ZIP"
echo "Notarized and stapled: $ZIP"
