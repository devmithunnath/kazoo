#!/bin/zsh
# Reproducible local build of Kazoo.app.
# Usage: Scripts/build.sh [Debug|Release]
#
# Signing: macOS ties Keychain "Always Allow" grants to the app's signature. Ad-hoc signatures change on every
# build, which makes macOS ask again after each update. The app is therefore re-signed with a stable identity:
#   KAZOO_SIGN_IDENTITY="<name or SHA-1>"  use this identity
#   KAZOO_SIGN_IDENTITY="-"               keep ad-hoc signing
#   (unset)                               first "Developer ID Application", else first "Apple Development", else ad-hoc
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-Release}"
DERIVED="build/DerivedData"
mkdir -p build
xcodebuild \
  -project Kazoo.xcodeproj \
  -scheme Kazoo \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS' \
  build > build/xcodebuild.log 2>&1 || { tail -40 build/xcodebuild.log >&2; exit 1; }
APP="$DERIVED/Build/Products/$CONFIG/Kazoo.app"
[[ -d "$APP" ]] || { echo "Build failed: $APP not found" >&2; exit 1; }
mkdir -p dist
rm -rf dist/Kazoo.app
ditto "$APP" dist/Kazoo.app

identity="${KAZOO_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identities=$(security find-identity -v -p codesigning 2>/dev/null || true)
  identity=$(print -r -- "$identities" | grep '"Developer ID Application' | sort -k2 | head -1 | awk '{print $2}' || true)
  [[ -n "$identity" ]] || identity=$(print -r -- "$identities" | grep '"Apple Development' | sort -k2 | head -1 | awk '{print $2}' || true)
  [[ -n "$identity" ]] || identity="-"
fi
if [[ "$identity" != "-" ]]; then
  codesign --force --options runtime --timestamp=none \
    --entitlements Kazoo/Kazoo.entitlements --sign "$identity" dist/Kazoo.app
  codesign --verify --strict dist/Kazoo.app
  signer=$(codesign -dvv dist/Kazoo.app 2>&1 | grep -m1 '^Authority=' | cut -d= -f2-)
  echo "Signed with: $signer"
else
  echo "Signed ad-hoc (Keychain permissions will be requested again after each update)"
fi
echo "Built dist/Kazoo.app ($CONFIG)"
