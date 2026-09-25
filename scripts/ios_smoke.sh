#!/bin/zsh
# iOS visual smoke test. Builds the simulator app (unless SKIP_BUILD=1), boots its OWN simulator "Thuban Gym Smoke"
# (iPhone 17, iOS 26.5; created when missing), installs, and launches with THUBAN_GYM_SMOKE=phone. The app moves to
# a fresh temporary home inside its container, seeds SampleData and walks every screen; for each it writes
# <name>.ready into its tmp/smoke-shots/, this script takes `simctl io screenshot` → <out>/<name>.png and answers
# <name>.done. Then the same on "Thuban Gym Smoke iPad" (iPad Air 11-inch, landscape) unless IPAD=0.
# Usage: [SKIP_BUILD=1] [IPAD=0] scripts/ios_smoke.sh [output-dir]   (default .build/ios-smoke)
# Only the smoke devices are booted / shut down; never real data, never ssh.
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/ios_sim.sh
ROOT="$PWD"
OUT="${1:-$ROOT/.build/ios-smoke}"
DERIVED="${DERIVED:-.build/DerivedData-iOS}"
APP="$ROOT/$DERIVED/Build/Products/Debug-iphonesimulator/Thuban Gym.app"

if [[ "${SKIP_BUILD:-0}" != "1" || ! -d "$APP" ]]; then
  DERIVED="$DERIVED" scripts/ios_build.sh || exit 1
fi
rm -rf "$OUT"; mkdir -p "$OUT"
echo "Output: $OUT"

# run_smoke <device name> <device type> <mode> <stall timeout s>
# The timeout restarts on every screenshot, so a slow (busy) machine only fails
# when the app makes no progress at all for that long. SMOKE_TIMEOUT overrides it.
run_smoke() {
  local name="$1" type="$2" mode="$3" limit="${SMOKE_TIMEOUT:-$4}" udid data shots start
  udid="$(sim_udid "$name" "$type")" || return 1
  echo "== $name ($udid), mode $mode"
  sim_boot "$udid"
  xcrun simctl ui "$udid" appearance light >/dev/null 2>&1
  xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 \
    --cellularBars 4 --wifiBars 3 >/dev/null 2>&1
  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1
  xcrun simctl install "$udid" "$APP" || return 1
  data="$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data)" || return 1
  shots="$data/tmp/smoke-shots"
  rm -rf "$shots"
  SIMCTL_CHILD_THUBAN_GYM_SMOKE="$mode" xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" >/dev/null || return 1
  start=$SECONDS
  local taken=0
  while (( SECONDS - start < limit )); do
    if [[ -d "$shots" ]]; then
      for ready in "$shots"/*.ready(N); do
        local shot="${ready:t:r}"
        [[ -e "$shots/$shot.done" ]] && continue
        xcrun simctl io "$udid" screenshot --type=png "$OUT/$shot.png" >/dev/null 2>&1
        echo "  $shot.png"
        : > "$shots/$shot.done"
        taken=$((taken + 1))
        start=$SECONDS
      done
      [[ -e "$shots/finished" ]] && break
    fi
    sleep 0.3
  done
  if [[ ! -e "$shots/finished" ]]; then
    echo "TIMEOUT: $name made no progress for $limit s ($taken screenshots)"
    xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1
    return 2
  fi
  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1
  xcrun simctl status_bar "$udid" clear >/dev/null 2>&1
  xcrun simctl shutdown "$udid" >/dev/null 2>&1
  echo "  $taken screenshots"
}

STATUS=0
run_smoke "Thuban Gym Smoke" "com.apple.CoreSimulator.SimDeviceType.iPhone-17" phone 300 || STATUS=$?
if [[ "${IPAD:-1}" != "0" ]]; then
  run_smoke "Thuban Gym Smoke iPad" "com.apple.CoreSimulator.SimDeviceType.iPad-Air-11-inch-M4" ipad 240 || STATUS=$?
fi
echo "--- screenshots:"; ls "$OUT"/*.png 2>/dev/null || echo "(none)"
exit $STATUS
