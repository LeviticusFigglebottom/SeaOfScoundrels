# Sea of Scoundrels: top-level procedural island landmark generator driver.
# Usage:
#   blender --background --factory-startup --python tools/blender/gen_island_landmarks.py -- <outdir>
#   blender --background --python tools/blender/gen_island_landmarks.py -- --only <name> [<name> ...]
# Writes up to 78 sculpted coastal geology, skyline, harbour, jungle, maritime, world-craft, on-foot craft, story-craft, fort/vault, island-lore, nautical-craft, sea-lore, corsair-relics, expedition-craft, haven-relics, frontier-craft & signature set-piece .glb files into <outdir>/landmarks/.
import argparse
import bpy
import os
import sys
import random
import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import _landmark_common as lc
from _landmarks_setpieces import SETPIECE_GENERATORS

try:
    from _landmarks_geology import GEOLOGY_GENERATORS
except ImportError:
    GEOLOGY_GENERATORS = []

try:
    from _landmarks_storytelling_a import STORYTELLING_A_GENERATORS
except ImportError:
    STORYTELLING_A_GENERATORS = []

try:
    from _landmarks_storytelling_b import STORYTELLING_B_GENERATORS
except ImportError:
    STORYTELLING_B_GENERATORS = []

try:
    from _landmarks_skyline import SKYLINE_GENERATORS
except ImportError:
    SKYLINE_GENERATORS = []

try:
    from _landmarks_coastal import COASTAL_GENERATORS
except ImportError:
    COASTAL_GENERATORS = []

try:
    from _landmarks_harbour_ruins import HARBOUR_RUINS_GENERATORS
except ImportError:
    HARBOUR_RUINS_GENERATORS = []

try:
    from _landmarks_maritime_relics import MARITIME_RELICS_GENERATORS
except ImportError:
    MARITIME_RELICS_GENERATORS = []

try:
    from _landmarks_world_craft import WORLD_CRAFT_GENERATORS
except ImportError:
    WORLD_CRAFT_GENERATORS = []

try:
    from _landmarks_onfoot_craft import ONFOOT_CRAFT_GENERATORS
except ImportError:
    ONFOOT_CRAFT_GENERATORS = []

try:
    from _landmarks_story_craft import STORY_CRAFT_GENERATORS
except ImportError:
    STORY_CRAFT_GENERATORS = []

try:
    from _landmarks_fort_vault import FORT_VAULT_GENERATORS
except ImportError:
    FORT_VAULT_GENERATORS = []

try:
    from _landmarks_island_lore import ISLAND_LORE_GENERATORS
except ImportError:
    ISLAND_LORE_GENERATORS = []

try:
    from _landmarks_nautical_craft import NAUTICAL_CRAFT_GENERATORS
except ImportError:
    NAUTICAL_CRAFT_GENERATORS = []

try:
    from _landmarks_sea_lore import SEA_LORE_GENERATORS
except ImportError:
    SEA_LORE_GENERATORS = []

try:
    from _landmarks_corsair_relics import CORSAIR_RELICS_GENERATORS
except ImportError:
    CORSAIR_RELICS_GENERATORS = []

try:
    from _landmarks_expedition_craft import EXPEDITION_CRAFT_GENERATORS
except ImportError:
    EXPEDITION_CRAFT_GENERATORS = []

try:
    from _landmarks_haven_relics import HAVEN_RELICS_GENERATORS
except ImportError:
    HAVEN_RELICS_GENERATORS = []

try:
    from _landmarks_frontier_craft import FRONTIER_CRAFT_GENERATORS
except ImportError:
    FRONTIER_CRAFT_GENERATORS = []


def _normalize_name(name):
    n = name.strip()
    if n.endswith('.glb'):
        n = n[:-4]
    if n.startswith('gen_'):
        n = n[4:]
    return n


def main():
    argv = sys.argv
    cli = argv[argv.index('--') + 1:] if '--' in argv else []
    parser = argparse.ArgumentParser(description='Generate procedural island landmark GLBs.')
    parser.add_argument(
        'outdir',
        nargs='?',
        default=os.path.join(os.getcwd(), 'assets', 'generated'),
        help='Output root directory (writes into <outdir>/landmarks/)',
    )
    parser.add_argument(
        '--only',
        nargs='+',
        default=None,
        help='Generate only specific landmarks by stem name (e.g. harbour_cargo_crane_dock)',
    )
    args = parser.parse_args(cli)
    outdir = args.outdir

    random.seed(lc.SEED)
    np.random.seed(lc.SEED)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    lc.make_materials()

    generators = (
        list(GEOLOGY_GENERATORS)
        + list(SETPIECE_GENERATORS)
        + list(STORYTELLING_A_GENERATORS)
        + list(STORYTELLING_B_GENERATORS)
        + list(SKYLINE_GENERATORS)
        + list(COASTAL_GENERATORS)
        + list(HARBOUR_RUINS_GENERATORS)
        + list(MARITIME_RELICS_GENERATORS)
        + list(WORLD_CRAFT_GENERATORS)
        + list(ONFOOT_CRAFT_GENERATORS)
        + list(STORY_CRAFT_GENERATORS)
        + list(FORT_VAULT_GENERATORS)
        + list(ISLAND_LORE_GENERATORS)
        + list(NAUTICAL_CRAFT_GENERATORS)
        + list(SEA_LORE_GENERATORS)
        + list(CORSAIR_RELICS_GENERATORS)
        + list(EXPEDITION_CRAFT_GENERATORS)
        + list(HAVEN_RELICS_GENERATORS)
        + list(FRONTIER_CRAFT_GENERATORS)
    )

    if args.only:
        wanted = {_normalize_name(x) for x in args.only}
        available = {_normalize_name(fn.__name__) for fn in generators}
        missing = sorted(wanted - available)
        if missing:
            raise SystemExit('gen_island_landmarks: unknown --only target(s): %s' % ', '.join(missing))
        generators = [fn for fn in generators if _normalize_name(fn.__name__) in wanted]

    lm_dir = os.path.join(outdir, 'landmarks')
    print('gen_island_landmarks: writing %d landmarks to %s' % (len(generators), lm_dir))
    for fn in generators:
        fn(outdir)
    print('gen_island_landmarks: exported %d landmarks cleanly.' % len(generators))


if __name__ == '__main__':
    main()
