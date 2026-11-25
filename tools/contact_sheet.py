#!/usr/bin/env python3
"""Tile capture frames into one labelled image for side-by-side review.

Usage: tools/contact_sheet.py out.png [--cols N] [--width W] item...
Each item is a PNG path, or a captures/<name> directory (its last frame is used;
append ":k" for frame k, or ":all" / ":every=N" for several frames).
"""
import glob, os, sys
from PIL import Image, ImageDraw

def frames(item):
    sel = None
    if ":" in item and not os.path.exists(item):
        item, sel = item.rsplit(":", 1)
    if os.path.isdir(item):
        fs = sorted(glob.glob(os.path.join(item, "*.png")))
        if sel is None:
            fs = fs[-1:]
        elif sel == "all":
            pass
        elif sel.startswith("every="):
            fs = fs[::int(sel[6:])]
        else:
            fs = [fs[int(sel)]]
        return [(f, "%s %s" % (os.path.basename(item), os.path.basename(f)[1:-4].lstrip("0") or "0")) for f in fs]
    return [(item, os.path.basename(item))]

def main():
    args = sys.argv[1:]
    out = args.pop(0)
    cols, width = 2, 800
    items = []
    while args:
        a = args.pop(0)
        if a == "--cols":
            cols = int(args.pop(0))
        elif a == "--width":
            width = int(args.pop(0))
        else:
            items += frames(a)
    tiles = []
    for path, label in items:
        im = Image.open(path).convert("RGB")
        im = im.resize((width, int(im.height * width / im.width)), Image.LANCZOS)
        d = ImageDraw.Draw(im)
        d.rectangle([0, 0, 8 + 7 * len(label), 16], fill=(0, 0, 0))
        d.text((4, 2), label, fill=(255, 255, 255))
        tiles.append(im)
    rows = (len(tiles) + cols - 1) // cols
    h = tiles[0].height
    sheet = Image.new("RGB", (cols * width, rows * h), (20, 20, 20))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % cols) * width, (i // cols) * h))
    sheet.save(out)
    print("wrote", out, sheet.size)

if __name__ == "__main__":
    main()
