#!/bin/zsh
# Reproducible local build of Kazoo.app (ad-hoc signed, runs on this Mac).
# Usage: Scripts/build.sh [Debug|Release]
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
echo "Built dist/Kazoo.app ($CONFIG)"
