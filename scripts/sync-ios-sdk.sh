#!/usr/bin/env bash
# Copy the Intunix iOS SDK sources (one tag) into ios/IntunixSDK.
#
# Why vendored: React Native's spm_dependency links the Swift package into the pod twice
# (duplicate symbols), and the SDK is not on CocoaPods trunk. The pod compiles these files
# into its own module instead. CI checks the copy still matches the tag.
set -euo pipefail
TAG="${1:-$(cat "$(dirname "$0")/../ios/IntunixSDK/VERSION")}"
DEST="$(cd "$(dirname "$0")/.." && pwd)/ios/IntunixSDK"
TMP="$(mktemp -d)"
git clone -q --depth 1 --branch "$TAG" https://github.com/intunix/intunix-ios "$TMP/sdk"
rm -rf "$DEST" && mkdir -p "$DEST"
cp "$TMP"/sdk/Sources/Intunix/*.swift "$DEST/"
echo "$TAG" > "$DEST/VERSION"
rm -rf "$TMP"
echo "ios/IntunixSDK now matches intunix-ios $TAG"
