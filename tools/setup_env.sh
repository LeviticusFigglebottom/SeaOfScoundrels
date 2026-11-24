#!/usr/bin/env bash
# Install the pinned toolchain on a fresh Ubuntu machine (needs root).
set -euo pipefail
cd "$(dirname "$0")/.."
GVF=$(cat .godot-version); GV=${GVF%-*}; GF=${GVF#*-}; BV=$(cat .blender-version)
mkdir -p /opt/tools && cd /opt/tools
apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mesa-vulkan-drivers xvfb ffmpeg unzip xz-utils curl python3-pip >/dev/null
if ! command -v godot >/dev/null; then
	curl -fsSL -o godot.zip "https://downloads.godotengine.org/?version=$GV&flavor=$GF&slug=linux.x86_64.zip&platform=linux.64"
	unzip -oq godot.zip && rm godot.zip
	ln -sf "/opt/tools/Godot_v$GV-${GF}_linux.x86_64" /usr/local/bin/godot
fi
if ! command -v blender >/dev/null; then
	curl -fsSL -o blender.tar.xz "https://download.blender.org/release/Blender${BV%.*}/blender-$BV-linux-x64.tar.xz"
	tar xf blender.tar.xz && rm blender.tar.xz
	ln -sf "/opt/tools/blender-$BV-linux-x64/blender" /usr/local/bin/blender
fi
pip install -q --break-system-packages numpy scipy pillow 2>/dev/null || pip install -q numpy scipy pillow
godot --version; blender --version | head -1
