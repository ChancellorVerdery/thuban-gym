#!/bin/zsh
# Shared simulator helpers for the iOS scripts (sourced, not run).
#   sim_udid "<name>" "<device type id>"  → prints the UDID of the named device on the newest iOS runtime,
#                                           creating it when missing (never touches other devices).
#   sim_boot <udid>                        → boots it (if needed) and waits until it is ready.

BUNDLE_ID="org.thuban.gym.ios"

sim_runtime() {
  # Prefer iOS 26.5; otherwise the newest available iOS runtime.
  xcrun simctl list runtimes -j | python3 -c '
import json, sys
rs = [r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS")]
exact = [r for r in rs if r["identifier"].endswith("iOS-26-5")]
pick = exact or sorted(rs, key=lambda r: [int(p) for p in r["version"].split(".")])
print(pick[-1]["identifier"] if pick else "")'
}

sim_udid() {
  local name="$1" type="$2" runtime udid
  runtime="$(sim_runtime)"
  [[ -z "$runtime" ]] && { echo "No iOS simulator runtime is installed." >&2; return 1; }
  udid="$(xcrun simctl list devices -j | python3 -c '
import json, sys
name, runtime = sys.argv[1], sys.argv[2]
devices = json.load(sys.stdin)["devices"].get(runtime, [])
match = [d["udid"] for d in devices if d["name"] == name and d.get("isAvailable", True)]
print(match[0] if match else "")' "$name" "$runtime")"
  if [[ -z "$udid" ]]; then
    # The named type, else the newest iPhone the runtime supports.
    udid="$(xcrun simctl create "$name" "$type" "$runtime" 2>/dev/null)" || udid=""
    if [[ -z "$udid" ]]; then
      local family="iPhone" fallback
      [[ "$type" == *iPad* ]] && family="iPad"
      fallback="$(xcrun simctl list devicetypes -j | python3 -c '
import json, sys
ts = [t for t in json.load(sys.stdin)["devicetypes"] if t["name"].startswith(sys.argv[1])]
print(ts[-1]["identifier"] if ts else "")' "$family")"
      udid="$(xcrun simctl create "$name" "$fallback" "$runtime")" || return 1
    fi
    echo "Created simulator \"$name\" ($udid)" >&2
  fi
  echo "$udid"
}

sim_boot() {
  local udid="$1"
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1
}
