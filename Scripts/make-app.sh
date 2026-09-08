#!/bin/bash
# Assembles Cheppu.app from the release build of the Cheppu executable, and
# signs it with whatever identity the machine has.
#
# Notarization and a Developer ID are a later ticket. What the signature here
# is for is smaller and immediate: macOS files an Accessibility grant under the
# code that asked for it, and an ad-hoc signature is pinned to the exact bytes
# of the build it was made from. Signed ad-hoc, every rebuild is a different
# app to the system — the switch in System Settings stays on while the Hotkey
# quietly stops arriving, and the only way back is to remove the entry and add
# it again. A signature made with the same identity every time is the same app
# every time, so the grant outlives the rebuild and a day of polishing is spent
# on Cheppu rather than in System Settings.
#
# Set CHEPPU_SIGN_IDENTITY to the name of a code signing identity in the
# keychain to get that. A self-signed one is enough and takes a minute to make;
# the Building section of the README says how. Without it the bundle is signed
# ad-hoc, which runs and asks for Accessibility again after every build.
set -euo pipefail

cd "$(dirname "$0")/.."

DESTINATION="dist/Cheppu.app"
IDENTITY="${CHEPPU_SIGN_IDENTITY:--}"

swift build --configuration release --arch arm64 --product Cheppu
EXECUTABLE="$(swift build --configuration release --arch arm64 --product Cheppu --show-bin-path)/Cheppu"

rm -rf "$DESTINATION"
mkdir -p "$DESTINATION/Contents/MacOS" "$DESTINATION/Contents/Resources"
cp "$EXECUTABLE" "$DESTINATION/Contents/MacOS/Cheppu"
cp App/Info.plist "$DESTINATION/Contents/Info.plist"
printf 'APPL????' > "$DESTINATION/Contents/PkgInfo"

# The whole bundle rather than the executable inside it, so that the Info.plist
# — and with it the bundle identifier every grant is filed under — is sealed by
# the signature rather than sitting next to it. `--identifier` is passed because
# the signature the linker leaves on the binary names it `Cheppu`, and what
# macOS should have on file is what ADR-0004 settled on: com.iamyhr.cheppu.
#
# The hardened runtime is deliberately not switched on here. Notarization will
# need it, and will need the microphone entitlement alongside it; turning it on
# without that would take the microphone away from every local build.
codesign --force --sign "$IDENTITY" --identifier com.iamyhr.cheppu "$DESTINATION"
codesign --verify --strict "$DESTINATION"

echo "Built $DESTINATION"

if [ "$IDENTITY" = "-" ]; then
    echo "  Signed ad-hoc: Accessibility has to be granted again after each rebuild."
    echo "  Set CHEPPU_SIGN_IDENTITY to a keychain identity to keep the grant."
else
    echo "  Signed by $IDENTITY."
fi
