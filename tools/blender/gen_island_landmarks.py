# Sea of Scoundrels: top-level procedural island landmark generator driver.
# Usage: blender --background --factory-startup --python tools/blender/gen_island_landmarks.py -- <outdir>
# Writes up to 12 sculpted coastal geology & signature set-piece .glb files into <outdir>/landmarks/.
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


def main():
    argv = sys.argv
    outdir = argv[-1] if '--' in argv else os.path.join(os.getcwd(), 'assets', 'generated')
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
    )
    lm_dir = os.path.join(outdir, 'landmarks')
    print('gen_island_landmarks: writing %d landmarks to %s' % (len(generators), lm_dir))
    for fn in generators:
        fn(outdir)
    print('gen_island_landmarks: exported %d landmarks cleanly.' % len(generators))


if __name__ == '__main__':
    main()
