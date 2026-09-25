#!/bin/zsh
# iOS Simulator build of Thuban Gym (target GymiOS, iPhone + iPad) into .build/DerivedData-iOS. Unsigned
# (CODE_SIGNING_ALLOWED=NO: simulator apps need no identity) and therefore without the iCloud entitlements
# (THUBAN_SIGNED=NO: Settings shows "Off: iCloud needs a signed build"). Prints only errors/warnings from our sources.
# CONFIG=Release for a Release build; DERIVED=<dir> overrides the DerivedData path.
# The Xcode project is regenerated from project.yml first (it is not committed).
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
CONFIG="${CONFIG:-Debug}"
DERIVED="${DERIVED:-.build/DerivedData-iOS}"
LOG="${DERIVED}/xcodebuild.log"
mkdir -p "$DERIVED"
xcodegen generate --quiet || exit 1
xcodebuild -project ThubanGym.xcodeproj -scheme GymiOS -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" -destination 'generic/platform=iOS Simulator' \
  THUBAN_SIGNED=NO CODE_SIGNING_ALLOWED=NO build "$@" > "$LOG" 2>&1
STATUS=$?
grep -E "(error|warning): " "$LOG" | grep -E "GymiOS/|Shared/|ThubanGymCore/|xcodebuild: error" | grep -v "DerivedData" | sort -u | head -80
grep -E "\*\* BUILD (SUCCEEDED|FAILED) \*\*" "$LOG" || echo "** BUILD RESULT UNKNOWN (see $LOG) **"
echo "App: $DERIVED/Build/Products/$CONFIG-iphonesimulator/Thuban Gym.app"
exit $STATUS
