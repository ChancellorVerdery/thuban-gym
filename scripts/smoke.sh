#!/bin/zsh
# Visual smoke test: builds (unless SKIP_BUILD=1), launches the Debug binary on a fresh temporary THUBAN_GYM_HOME
# with THUBAN_GYM_SMOKE=<output dir>. The app seeds SampleData, walks every section, the registered SmokeScenes,
# Today in dark mode and every Settings pane, writes PNGs and exits. Only the process it launched is ever stopped.
# Usage: [DERIVED=.build/DerivedData-<name>] [SKIP_BUILD=1] scripts/smoke.sh [output-dir]   (default .build/smoke)
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="${1:-$ROOT/.build/smoke}"
DERIVED="${DERIVED:-.build/DerivedData}"
APP="$ROOT/$DERIVED/Build/Products/Debug/Thuban Gym.app/Contents/MacOS/Thuban Gym"
LOG="$(mktemp "${TMPDIR:-/tmp}/thuban-gym-smoke-log.XXXXXX")"

if [[ "${SKIP_BUILD:-0}" != "1" || ! -x "$APP" ]]; then
  DERIVED="$DERIVED" scripts/build.sh || exit 1
fi

HOME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/thuban-gym-smoke-home.XXXXXX")"
rm -rf "$OUT"; mkdir -p "$OUT"
echo "Smoke home: $HOME_DIR"
echo "Output:     $OUT"
THUBAN_GYM_SMOKE="$OUT" THUBAN_GYM_HOME="$HOME_DIR" "$APP" > "$LOG" 2>&1 &
PID=$!
for i in {1..180}; do
  kill -0 "$PID" 2>/dev/null || break
  sleep 1
done
if kill -0 "$PID" 2>/dev/null; then
  echo "TIMEOUT: app still running after 180 s; stopping it (pid $PID)"; kill "$PID" 2>/dev/null; STATUS=2
else
  wait "$PID"; STATUS=$?; echo "App exited with status $STATUS"
fi
echo "--- app output (last 40 lines of $LOG):"; tail -40 "$LOG"
echo "--- screenshots:"; ls "$OUT"/*.png 2>/dev/null || echo "(none)"
rm -rf "$HOME_DIR"
exit $STATUS
