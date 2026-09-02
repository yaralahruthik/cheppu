#!/bin/bash
# Assembles Cheppu.app from the release build of the Cheppu executable.
#
# Signing and notarization are a later ticket; this produces the unsigned bundle
# they will operate on.
set -euo pipefail

cd "$(dirname "$0")/.."

DESTINATION="dist/Cheppu.app"

swift build --configuration release --arch arm64 --product Cheppu
EXECUTABLE="$(swift build --configuration release --arch arm64 --product Cheppu --show-bin-path)/Cheppu"

rm -rf "$DESTINATION"
mkdir -p "$DESTINATION/Contents/MacOS" "$DESTINATION/Contents/Resources"
cp "$EXECUTABLE" "$DESTINATION/Contents/MacOS/Cheppu"
cp App/Info.plist "$DESTINATION/Contents/Info.plist"
printf 'APPL????' > "$DESTINATION/Contents/PkgInfo"

echo "Built $DESTINATION"
