#!/bin/zsh
# Builds a release zip for GitHub Releases and updates the Homebrew cask (Casks/kazoo.rb) to match.
# Usage: Scripts/package.sh
# Then: create a GitHub release tagged v<version>, attach dist/Kazoo-<version>.zip, and commit Casks/kazoo.rb.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(grep -m1 'MARKETING_VERSION = ' Kazoo.xcodeproj/project.pbxproj | sed -E 's/.*= ([^;]+);/\1/')
Scripts/build.sh Release
ZIP="dist/Kazoo-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent dist/Kazoo.app "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" Casks/kazoo.rb
echo "Packaged $ZIP"
echo "sha256 $SHA"
echo "Next: upload $ZIP to a GitHub release tagged v$VERSION, then commit and push Casks/kazoo.rb."
