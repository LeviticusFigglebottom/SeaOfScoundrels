#!/usr/bin/env bash
# Run the headless test suite. Usage: tools/test.sh [test_file_basename]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
args=()
[ $# -gt 0 ] && args=(-- "--only=$1")
# A script parse error can hang the runner, so bound the run.
timeout "${TEST_TIMEOUT:-600}" "$GODOT" --headless --path . res://tests/test_runner.tscn "${args[@]}"
