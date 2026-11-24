#!/usr/bin/env bash
# Rebuild every generated asset from source scripts. One command, reproducible.
# Each generator writes into assets/generated/<area>/ and takes the output dir as its last argument.
set -euo pipefail
cd "$(dirname "$0")/.."
BLENDER="${BLENDER:-blender}"
out="$PWD/assets/generated"
shopt -s nullglob
for f in tools/blender/gen_*.py; do
	echo "== blender: $f"
	"$BLENDER" --background --factory-startup --python "$f" -- "$out" 2>&1 | grep -vE "^(Blender|Read|Saved|$)" || true
done
for f in tools/textures/gen_*.py tools/audio/gen_*.py; do
	echo "== python: $f"
	python3 "$f" "$out"
done
echo "assets rebuilt in $out"
