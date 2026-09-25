#!/bin/zsh
# Regenerates ThubanGym/Resources/Assets.xcassets/AppIcon.appiconset from the app's mark (Brass, dark plate).
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
cp scripts/make_app_icon.swift "$TMP/main.swift"
swiftc -D APPICON_TOOL -o "$TMP/make_app_icon" "$TMP/main.swift" \
  ThubanGym/Views/Components/AppArt.swift ThubanGym/Views/Components/AppArtSource.swift
find ThubanGym/Resources/Assets.xcassets/AppIcon.appiconset -name "*.png" -delete
"$TMP/make_app_icon" ThubanGym/Resources/Assets.xcassets/AppIcon.appiconset
rm -rf "$TMP"
