#!/bin/zsh
# Unit tests for the core package. THUBAN_GYM_LIVE_ATLAS=1 also runs the read-only live Atlas dry run
# (prints counts and workout names only).
set -uo pipefail
cd "$(dirname "$0")/../Packages/ThubanGymCore"
swift test 2>&1 | tee "${TMPDIR:-/tmp}/thuban-gym-test.log" | grep -E "error|failed|Executed|LIVE ATLAS|Build complete" | tail -30
exit ${pipestatus[1]}
