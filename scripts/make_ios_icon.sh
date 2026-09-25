#!/bin/zsh
# Regenerates GymiOS/Resources/Assets.xcassets/AppIcon.appiconset (1024 single-size, Brass mark on the dark plate)
# from the shared app art (Shared/Art/AppArt*.swift), like make_app_icon.sh does for the Mac.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
cp scripts/make_ios_icon.swift "$TMP/main.swift"
swiftc -D APPICON_TOOL -o "$TMP/make_ios_icon" "$TMP/main.swift" Shared/Art/AppArt.swift Shared/Art/AppArtSource.swift
find GymiOS/Resources/Assets.xcassets/AppIcon.appiconset -name "*.png" -delete
"$TMP/make_ios_icon" GymiOS/Resources/Assets.xcassets/AppIcon.appiconset
rm -rf "$TMP"
