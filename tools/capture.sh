#!/usr/bin/env bash
# Render a scene off-screen (software Vulkan works) to PNG frames + an mp4.
# Usage: tools/capture.sh <res://scene.tscn> <name> [seconds=3] [fps=10] [-- user args]
# Output: captures/<name>/f00000000.png ... and captures/<name>.mp4
# Frames are rendered at the project viewport size (1600x900; movie mode ignores --resolution).
# Frames are deterministic (fixed timestep), so slow rendering does not change the result.
# The scene can read OS.get_cmdline_user_args() for scripted cameras/scenarios.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
scene="$1"; name="$2"; secs="${3:-3}"; fps="${4:-10}"
shift $(( $# < 4 ? $# : 4 ))
[ "${1:-}" = "--" ] && shift
out="captures/$name"
rm -rf "$out"; mkdir -p "$out"
frames=$(python3 -c "print(int(round($secs*$fps)))")
[ -d .godot/imported ] || "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
runner=()
[ -z "${DISPLAY:-}" ] && runner=(xvfb-run -a -s "-screen 0 1920x1080x24")
"${runner[@]}" "$GODOT" --path . --rendering-method forward_plus --audio-driver Dummy --debug-mute-audio \
	--write-movie "$out/f.png" --fixed-fps "$fps" --quit-after "$frames" \
	"$scene" -- "$@" 2>&1 | grep -E "ERROR|SHADER|WARNING|at: |res://|recorded in|render time" | grep -vE "ALSA|audio|f_wav|movie_writer|d.is_null" || true
rm -f "$out"/*.wav
n=$(ls "$out"/*.png 2>/dev/null | wc -l)
if [ "$n" -gt 1 ]; then
	ffmpeg -y -loglevel error -framerate "$fps" -pattern_type glob -i "$out/*.png" \
		-pix_fmt yuv420p -crf 20 "captures/$name.mp4" || true
fi
echo "captured $n frames -> $out/"
