#!/usr/bin/env python3
"""Enable VRAM compression (compress/mode=2) and mipmaps on 3D PBR texture imports.

Leaves 2D UI, BMFont, sky, and high-precision 4-channel FFT ocean maps untouched
(lossless) while switching 3D world/ship/prop/landmark/character PBR maps from
uncompressed RGBA8 (compress/mode=0) to hardware VRAM compression (~6x VRAM savings,
plus full mipmap chains on terrain_*.png and ship_*.png).
"""
import glob
import os
import re
import sys

TARGET_DIRS = ("textures", "ship", "props", "characters")
ALL_DIRS = ("textures", "ship", "props", "characters", "landmarks")


def optimize_import_file(path: str) -> bool:
    with open(path, "r", encoding="utf-8") as fh:
        orig = fh.read()
    text = orig
    text = re.sub(r"(?m)^compress/mode=\d+$", "compress/mode=2", text)
    text = re.sub(r"(?m)^mipmaps/generate=(true|false)$", "mipmaps/generate=true", text)
    if text != orig:
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        return True
    return False


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.join("assets", "generated")
    changed = 0
    scanned = 0
    for sub in TARGET_DIRS:
        pattern = os.path.join(root, sub, "*.png.import")
        for path in sorted(glob.glob(pattern)):
            scanned += 1
            if optimize_import_file(path):
                changed += 1
    print(f"optimize_imports: scanned {scanned} 3D .png.import files, updated {changed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
