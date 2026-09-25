#!/bin/zsh
# Installs Thuban Gym for iOS:
#  1. a Release simulator build into the simulator "Thuban iPhone" (iPhone 17, iOS 26.5; created when missing).
#     A simulator that was shut down is shut down again afterwards (the app stays installed).
#  2. ONLY when `xcrun devicectl list devices` shows a paired iPhone AND DEVELOPMENT_TEAM is set: a signed Release
#     device build installed on that iPhone. Otherwise it prints how to enable that.
# Usage: [DEVELOPMENT_TEAM=<team id>] [DEVICE=<devicectl id or name>] scripts/ios_install.sh
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/ios_sim.sh
export PATH="$HOME/.local/bin:$PATH"

# --- Simulator ---------------------------------------------------------------------------------------------------
CONFIG=Release DERIVED=.build/DerivedData-iOS-Release scripts/ios_build.sh || exit 1
SIM_APP=".build/DerivedData-iOS-Release/Build/Products/Release-iphonesimulator/Thuban Gym.app"
UDID="$(sim_udid "Thuban iPhone" "com.apple.CoreSimulator.SimDeviceType.iPhone-17")" || exit 1
WAS_BOOTED=0
xcrun simctl list devices | grep -q "$UDID) (Booted)" && WAS_BOOTED=1
sim_boot "$UDID"
xcrun simctl install "$UDID" "$SIM_APP" || exit 1
echo "Installed on simulator \"Thuban iPhone\" ($UDID). Open it with: open -a Simulator --args -CurrentDeviceUDID $UDID"
if [[ "$WAS_BOOTED" == "0" ]]; then xcrun simctl shutdown "$UDID" >/dev/null 2>&1; fi

# --- Device (optional) ---------------------------------------------------------------------------------------------
JSON="$(mktemp "${TMPDIR:-/tmp}/thuban-devices.XXXXXX")"
xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1
PHONE="$(python3 - "$JSON" "${DEVICE:-}" <<'PY'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
wanted = sys.argv[2]
for d in devices:
    hw, conn, props = d.get("hardwareProperties", {}), d.get("connectionProperties", {}), d.get("deviceProperties", {})
    if hw.get("platform") != "iOS" or hw.get("deviceType") != "iPhone" or conn.get("pairingState") != "paired":
        continue
    if wanted and wanted not in (d.get("identifier"), props.get("name")):
        continue
    print(d["identifier"]); break
PY
)"
rm -f "$JSON"

if [[ -z "$PHONE" || -z "${DEVELOPMENT_TEAM:-}" ]]; then
  REASON="no paired iPhone found"
  [[ -n "$PHONE" ]] && REASON="no DEVELOPMENT_TEAM set"
  echo
  echo "Device install skipped ($REASON). To install on your iPhone:"
  echo "  1. Xcode ▸ Settings ▸ Accounts: add your Apple ID (a free account works; its apps expire after 7 days)."
  echo "  2. Connect the iPhone by cable, unlock it, tap Trust, and turn on Developer Mode"
  echo "     (Settings ▸ Privacy & Security ▸ Developer Mode) when iOS asks."
  echo "  3. Find your team id (Xcode ▸ Settings ▸ Accounts ▸ the team), then run:"
  echo "       DEVELOPMENT_TEAM=<team id> scripts/ios_install.sh"
  exit 0
fi

echo
echo "Building for the iPhone ($PHONE), team $DEVELOPMENT_TEAM…"
DERIVED=.build/DerivedData-iOS-Device
mkdir -p "$DERIVED"
xcodebuild -project ThubanGym.xcodeproj -scheme GymiOS -configuration Release -derivedDataPath "$DERIVED" \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" CODE_SIGN_STYLE=Automatic build > "$DERIVED/xcodebuild.log" 2>&1
if ! grep -q "\*\* BUILD SUCCEEDED \*\*" "$DERIVED/xcodebuild.log"; then
  grep -E "error: " "$DERIVED/xcodebuild.log" | sort -u | head -20
  echo "Device build failed (see $DERIVED/xcodebuild.log)."
  exit 1
fi
xcrun devicectl device install app --device "$PHONE" "$DERIVED/Build/Products/Release-iphoneos/Thuban Gym.app" || exit 1
echo "Installed on the iPhone."
