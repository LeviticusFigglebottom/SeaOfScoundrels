#!/usr/bin/env bash
# Run the tests that need a real renderer (shader vs CPU parity). Works with
# software Vulkan under Xvfb. Usage: tools/test_gpu.sh [test_file_basename]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
[ -d .godot/imported ] || "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
runner=()
[ -z "${DISPLAY:-}" ] && runner=(xvfb-run -a -s "-screen 0 1280x720x24")
"${runner[@]}" "$GODOT" --path . --rendering-method forward_plus --audio-driver Dummy \
	res://tests/test_runner.tscn -- "--only=${1:-test_sea_shader}"
