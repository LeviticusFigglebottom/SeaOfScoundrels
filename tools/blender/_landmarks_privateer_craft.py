# Sea of Scoundrels: 4 sculpted 3D Privateer Craft & Mythic Coast Landmarks
# (Wave I-21 / Pass I-Q14 — Advancing to 86 Zero-Extra-VRAM Landmarks!).
# Imported by tools/blender/gen_island_landmarks.py.
# Authored in Godot game coordinates (-Z seaward/hero-facing, +Y up, +X starboard, metres)
# and converted to Blender's Z-up frame on mesh creation via _landmark_common.
# STRICT SHARED-TEXTURE DEDUP CONTRACT: uses ONLY the 11 existing shared PBR materials
# (limestone, limestone_moss, basalt, temple_stone, skull_stone, timber, paint, rope,
# iron, brass, foliage) + untextured glass / skull_glow / col.
# Emissive rule:
#   - mat_landmark_skull_glow ONLY on ancient_serpent_tide_portal (luminous cyan-turquoise
#     rune threshold arch, carved serpent-eye gems, and portal crest crystal)
#   - mat_landmark_glass with warm amber/molten linear COLOR_0 on pirate_sailmaker_rigging_loft,
#     coastal_castaway_raft_shelter, and volcanic_obsidian_phoenix_brazier (ZERO skull_glow!).
import math
import random
from math import sin, cos, pi, sqrt, atan2, radians, degrees
from mathutils import Vector, Matrix

from _landmark_common import (
    SEED,
    srgb, mul, mix, jit, smooth01,
    C_LIME_PALE, C_LIME_WARM, C_LIME_MID, C_LIME_SHADE, C_LIME_DARK,
    C_SEA_MOSS, C_LEDGE_MOSS, C_GRASS_SUN, C_GRASS_DEEP,
    C_BASALT_TOP, C_BASALT_MID, C_BASALT_DARK, C_BASALT_HOT, C_MAGMA_GLOW,
    C_SKULL_BONE, C_SKULL_MID, C_SKULL_SHADE, C_SKULL_CAV, C_SKULL_EYE,
    C_TEMPLE_HI, C_TEMPLE_MID, C_TEMPLE_DARK, C_TEMPLE_GOLD,
    C_TIMBER_HI, C_TIMBER_MID, C_TIMBER_DARK, C_DRIFTWOOD,
    C_PAINT_RED, C_PAINT_TEAL, C_PAINT_CREAM,
    C_ROPE, C_IRON, C_IRON_RUST, C_BRASS, C_LANTERN_GL,
    C_LEAF_DEEP, C_LEAF_SUN,
    T, R, S, M_Y2Z, M_Y2X, newell,
    MB, xf,
    cbox, sculpt_stone_block, loft, lathe, tube, cyl, torus,
    sculpt_rock_mass, sculpt_basalt_column,
    clear_scene, build, col_piece, col_box, add_empty, export_landmark_glb,
)


# ---------------------------------------------------------------- local painterly palette

# Coastal harbour cobble, beach sandstone & mossy temple masonry
C_SANDSTONE_HI   = srgb('#ead7b2')
C_SANDSTONE_MID  = srgb('#c8a478')
C_SANDSTONE_DARK = srgb('#8c6f51')
C_SANDSTONE_DEEP = srgb('#564739')
C_COBBLE_HI      = srgb('#d0c4ad')
C_COBBLE_MID     = srgb('#948977')
C_COBBLE_DARK    = srgb('#5e564d')
C_COBBLE_WET     = srgb('#3f3e39')

C_SANCTUM_HI     = srgb('#d6ceb8')
C_SANCTUM_MID    = srgb('#9a9480')
C_SANCTUM_DARK   = srgb('#636052')
C_SANCTUM_DEEP   = srgb('#42433a')
C_SERPENT_HI     = srgb('#a6b48c')
C_SERPENT_MID    = srgb('#647958')
C_SERPENT_DARK   = srgb('#3b4c37')
C_SERPENT_BELLY  = srgb('#cfc4a2')
C_MOSS_CUSHION   = srgb('#4b7f30')
C_MOSS_DEEP      = srgb('#2b5021')

# Harbour oak, bleached castaway driftwood & charred camp logs
C_OAK_SUN        = srgb('#c4894c')
C_OAK_RICH       = srgb('#87552c')
C_OAK_DEEP       = srgb('#50311a')
C_OAK_CHAR       = srgb('#2a1c14')
C_DRIFT_PALE     = srgb('#dfd2ba')
C_DRIFT_MID      = srgb('#aa987f')
C_DRIFT_DARK     = srgb('#6e604f')

# Sailmaker's canvas, buccaneer crimson, weathered teal & braided hemp
C_CREAM_SAIL     = srgb('#f4e7cb')
C_CREAM_AGED     = srgb('#d2bd96')
C_CREAM_SHADE    = srgb('#a6926f')
C_CRIMSON_HI     = srgb('#d83223')
C_CRIMSON_MID    = srgb('#9e2118')
C_CRIMSON_DARK   = srgb('#631410')
C_TEAL_HI        = srgb('#258a8e')
C_TEAL_MID       = srgb('#1b6368')
C_SEA_GLASS      = srgb('#48b5a0')
C_SEA_GLASS_DARK = srgb('#216c63')
C_HEMP_HI        = srgb('#e2c38c')
C_HEMP_MID       = srgb('#be995d')
C_HEMP_DARK      = srgb('#886839')

# Metals: gilded bronze, burnished brass, verdigris bronze, forged & rusted iron
C_GOLD_BRIGHT    = srgb('#fad24f')
C_BRASS_WARM     = srgb('#daa339')
C_BRASS_DARK     = srgb('#8d621f')
C_VERDIGRIS_HI   = srgb('#56bba3')
C_VERDIGRIS_MID  = srgb('#318774')
C_IRON_BRIGHT    = srgb('#828b9c')
C_IRON_FORGED    = srgb('#4b5160')
C_IRON_DARK      = srgb('#252832')
C_IRON_RUST_HI   = srgb('#b36135')
C_IRON_RUST_MID  = srgb('#7e4223')

# Volcanic charred basalt & high-contrast faceted obsidian
C_OBSIDIAN_EDGE  = srgb('#aba0bc')
C_OBSIDIAN_HI    = srgb('#736a84')
C_OBSIDIAN_MID   = srgb('#453f52')
C_OBSIDIAN_DARK  = srgb('#282432')
C_OBSIDIAN_ABYSS = srgb('#14121a')

# Luminous cyan-turquoise aquatic portal glow (USED ONLY with 'skull_glow' on ancient_serpent_tide_portal!)
C_AQUA_CORE      = srgb('#72fff4')
C_AQUA_MID       = srgb('#18dec3')
C_AQUA_DEEP      = srgb('#088d82')

# Warm amber lantern, campfire embers & incandescent magma (USED ONLY with 'glass' on the other 3 GLBs!)
C_FLAME_WHITE    = srgb('#ffcf4a')
C_FLAME_CORE     = srgb('#ff7e12')
C_FLAME_MID      = srgb('#e33804')
C_FLAME_DEEP     = srgb('#9e1402')
C_MAGMA_CRIMSON  = srgb('#5e0801')

# Tropical coastal vines & beach ferns
C_VINE_DARK      = srgb('#184d1f')
C_VINE_MID       = srgb('#317b28')
C_VINE_SUN       = srgb('#84c62d')


# ---------------------------------------------------------------- shared sculptural helpers

def _add_beam(mb, p0, p1, w, h, mat, col, ch=0.0):
    """Emit a crisp timber, iron, stone, or brass beam connecting arbitrary 3D points p0 and p1."""
    a = Vector(p0)
    b = Vector(p1)
    v = b - a
    L = v.length
    if L < 1e-4:
        return
    mid = (a + b) * 0.5
    rot = Vector((0.0, 1.0, 0.0)).rotation_difference(v.normalized()).to_matrix().to_4x4()
    with xf(mb, T(mid) @ rot):
        cbox(mb, (0.0, 0.0, 0.0), (w, L, h), mat, col, ch, (0, 1, 0))


def _reg_poly(cx, y, cz, radius, sides=8, rot_deg=0.0, sx=1.0, sz=1.0):
    """Regular or elliptical N-sided horizontal polygon ring at height y."""
    r0 = radians(rot_deg)
    return [
        (cx + radius * sx * cos(r0 + 2.0 * pi * k / float(sides)),
         y,
         cz + radius * sz * sin(r0 + 2.0 * pi * k / float(sides)))
        for k in range(sides)
    ]


def _rect_oct(cx, y, cz, hx, hz, ch):
    """Chamfered rectangular 8-vertex horizontal ring at height y."""
    c = min(ch, hx * 0.45, hz * 0.45)
    return [
        (cx - hx + c, y, cz - hz),
        (cx + hx - c, y, cz - hz),
        (cx + hx,     y, cz - hz + c),
        (cx + hx,     y, cz + hz - c),
        (cx + hx - c, y, cz + hz),
        (cx - hx + c, y, cz + hz),
        (cx - hx,     y, cz + hz - c),
        (cx - hx,     y, cz - hz + c),
    ]


def _loft_horizontal_masonry(mb, secs, mat, scols, rng, caps=(True, True), top_mat=None, top_col=None):
    """Stepped or battered stone plinth/column loft with horizontal UV masonry courses."""
    n = len(secs)
    k = len(secs[0])
    cents = [sum((Vector(p) for p in s), Vector()) / float(k) for s in secs]
    mb.newoff()
    for i in range(n - 1):
        c_mid = (cents[i] + cents[i + 1]) * 0.5
        col_i = scols[i]
        for j in range(k):
            j1 = (j + 1) % k
            p00 = Vector(secs[i][j])
            p01 = Vector(secs[i][j1])
            p11 = Vector(secs[i + 1][j1])
            p10 = Vector(secs[i + 1][j])
            horiz = p01 - p00
            horiz.y = 0.0
            if horiz.length < 1e-5:
                horiz = Vector((1.0, 0.0, 0.0))
            horiz.normalize()
            face_col = jit(col_i, rng, 0.04, 0.015)
            mb.fp([p00, p01, p11, p10], mat, face_col, grain=horiz, inside=c_mid, smooth=False)
    if caps[0] and n > 1:
        mb.fp(secs[0], mat, mul(scols[0], 0.72), (1, 0, 0), cents[1], smooth=False)
    if caps[1] and n > 1:
        tmat = top_mat if top_mat is not None else mat
        tcol = top_col if top_col is not None else scols[-1]
        mb.fp(secs[-1], tmat, tcol, (1, 0, 0), cents[-2], smooth=False)


def _build_storm_lantern(mb, center, scale=1.0, brass_cage=True, hanging=True):
    """Chunky nautical brass-and-iron storm lantern with warm glowing amber 'glass' core."""
    cx, cy, cz = center
    s = scale
    cage_mat = 'brass' if brass_cage else 'iron'
    cage_col = C_GOLD_BRIGHT if brass_cage else C_IRON_FORGED
    with xf(mb, T(cx, cy, cz)):
        cyl(mb, 0.145 * s, -0.22 * s, -0.14 * s, 6, 'iron', C_IRON_FORGED, False, 0.0, 0.165 * s)
        cyl(mb, 0.175 * s, 0.15 * s, 0.23 * s, 6, cage_mat, cage_col, False, 0.0, 0.072 * s)
        cyl(mb, 0.065 * s, 0.23 * s, 0.30 * s, 6, 'brass', C_BRASS_WARM, False, 0.0, 0.036 * s)
        cyl(mb, 0.120 * s, -0.14 * s, 0.15 * s, 6, 'glass', C_FLAME_CORE, False, 0.0, 0.130 * s)
        for k in range(4):
            ang = k * pi * 0.5 + pi * 0.25
            cbox(mb, (0.142 * s * cos(ang), 0.005 * s, 0.142 * s * sin(ang)),
                 (0.028 * s, 0.31 * s, 0.028 * s), cage_mat, cage_col, 0.0)
        if hanging:
            with xf(mb, T(0.0, 0.33 * s, 0.0) @ M_Y2Z):
                torus(mb, 0.052 * s, 0.014 * s, 5, 4, 'iron', C_IRON_FORGED, False)


def _build_pulley_block(mb, center, scale=1.0, hook_down=True):
    """Chunky nautical wooden pulley block with iron binding strap, bronze sheave & iron ring."""
    s = scale
    cx, cy, cz = center
    with xf(mb, T(cx, cy, cz)):
        cbox(mb, (0.0, 0.0, 0.0), (0.15 * s, 0.28 * s, 0.21 * s), 'timber', C_OAK_RICH, 0.0)
        cbox(mb, (0.0, 0.0, 0.0), (0.17 * s, 0.30 * s, 0.075 * s), 'iron', C_IRON_FORGED, 0.0)
        with xf(mb, M_Y2X):
            cyl(mb, 0.092 * s, -0.085 * s, 0.085 * s, 6, 'timber', C_OAK_SUN, False, 0.0)
            cyl(mb, 0.036 * s, -0.105 * s, 0.105 * s, 5, 'brass', C_GOLD_BRIGHT, False, 0.0)
        y_ring = -0.19 * s if hook_down else 0.19 * s
        with xf(mb, T(0.0, y_ring, 0.0) @ M_Y2Z):
            torus(mb, 0.052 * s, 0.016 * s, 5, 4, 'iron', C_IRON_BRIGHT, False)


def _build_coopered_barrel(mb, M_bar, radius=0.26, height=0.66, rng=None,
                           col_a=C_OAK_RICH, col_b=C_OAK_DEEP, col_head=C_OAK_SUN, segs=6):
    """Coopered oak harbour barrel with forged-iron hoops."""
    hh = height * 0.5
    prof = [
        (0.0,           -hh),
        (radius * 0.82, -hh),
        (radius,         0.0),
        (radius * 0.84,  hh),
        (radius * 0.74,  hh),
        (0.0,            hh - 0.03),
    ]
    stave_cols = [
        jit(col_a if k % 2 == 0 else col_b, rng, 0.04, 0.012) if rng else col_a
        for k in range(segs)
    ]
    with xf(mb, M_bar):
        lathe(mb, prof, segs, 'timber', col_a, False, False,
              lambda i, k: col_head if i >= 4 else (C_OAK_CHAR if i == 0 else stave_cols[k]))
        for hy, hr, hcol in (
            (-hh * 0.62, radius * 0.94, C_IRON_FORGED),
            ( hh * 0.64, radius * 0.95, C_IRON_RUST_HI),
        ):
            cyl(mb, hr, hy - 0.025, hy + 0.025, segs, 'iron', hcol, False, 0.0)


def _build_rope_coil(mb, center, radius=0.25, turns=3, r=0.040, segs=6, psegs=4,
                     col_a=C_HEMP_HI, col_b=C_HEMP_MID):
    """Stacked coiled braided marline/hawser pile ('rope')."""
    for i in range(turns):
        rr = radius * (1.0 - 0.18 * i)
        with xf(mb, T(center[0], center[1] + r * (1.0 + i * 1.58), center[2])):
            torus(mb, rr, r, segs, psegs, 'rope', col_a if i % 2 == 0 else col_b, True)


def _build_wind_banner(mb, root_pos, length=1.38, h0=0.40, out_dir=(0.94, -0.03, -0.34),
                       col_main=C_CRIMSON_HI, col_alt=C_CREAM_SAIL, col_trim=C_GOLD_BRIGHT,
                       phase=0.28, swallowtail=True, tattered=False):
    """Wind-whipped double-sided striped guild burgee or tattered signal pennant ('paint') with UV2."""
    rp = Vector(root_pos)
    od = Vector(out_dir).normalized()
    side = Vector((-od.z, 0.0, od.x))
    if side.length < 1e-4:
        side = Vector((1.0, 0.0, 0.0))
    side.normalize()
    segs = 5
    thick = 0.011
    top_pts, bot_pts, weights = [], [], []
    for i in range(segs + 1):
        t = i / float(segs)
        wave = sin(t * (2.35 if tattered else 2.10) * pi) * (0.16 if tattered else 0.13) * t
        droop = -(0.16 if tattered else 0.11) * t * t
        taper = 0.42 if swallowtail else (0.58 if tattered else 0.72)
        hh = h0 * (1.0 - taper * t)
        if tattered and i in (2, 4):
            hh *= 0.84
        ctr = rp + od * (length * t) + side * wave + Vector((0.0, droop, 0.0))
        top_pts.append(ctr + Vector((0.0, hh * 0.5, 0.0)))
        bot_pts.append(ctr - Vector((0.0, hh * 0.5, 0.0)))
        weights.append((t ** 1.12) * 0.94)
    for i in range(segs):
        c_seg = col_trim if i == 0 else (col_main if i % 2 == 1 else col_alt)
        t0, t1 = top_pts[i], top_pts[i + 1]
        b0, b1 = bot_pts[i], bot_pts[i + 1]
        w0, w1 = weights[i], weights[i + 1]
        u0, u1 = (w0, phase), (w1, phase)
        if i == segs - 1 and (swallowtail or tattered):
            notch_depth = 0.22 if tattered else 0.14
            mid_notch = (t0 + b0) * 0.25 + (t1 + b1) * 0.25 - od * (length * notch_depth)
            um = (0.5 * (w0 + w1), phase)
            for tri, tu2 in (
                ([t0, t1, mid_notch], [u0, u1, um]),
                ([b0, mid_notch, b1], [u0, um, u1]),
                ([t0, mid_notch, b0], [u0, um, u0]),
            ):
                f_pts = [p + side * thick for p in tri]
                b_pts = [p - side * thick for p in reversed(tri)]
                ctr_tri = sum(tri, Vector()) / 3.0
                mb.fp(f_pts, 'paint', c_seg, od, ctr_tri - side * 1.0, smooth=False, uv2=tu2)
                mb.fp(b_pts, 'paint', mul(c_seg, 0.84), od, ctr_tri + side * 1.0, smooth=False, uv2=list(reversed(tu2)))
        else:
            q_f = [t0 + side * thick, t1 + side * thick, b1 + side * thick, b0 + side * thick]
            q_b = [t1 - side * thick, t0 - side * thick, b0 - side * thick, b1 - side * thick]
            ctr_q = (t0 + t1 + b0 + b1) * 0.25
            mb.fp(q_f, 'paint', c_seg, od, ctr_q - side * 1.0, smooth=False, uv2=[u0, u1, u1, u0])
            mb.fp(q_b, 'paint', mul(c_seg, 0.84), od, ctr_q + side * 1.0, smooth=False, uv2=[u1, u0, u0, u1])
            mb.fp([t0 - side * thick, t1 - side * thick, t1 + side * thick, t0 + side * thick],
                  'paint', mul(c_seg, 0.78), od, ctr_q, smooth=False, uv2=[u0, u1, u1, u0])
            mb.fp([b0 + side * thick, b1 + side * thick, b1 - side * thick, b0 - side * thick],
                  'paint', mul(c_seg, 0.74), od, ctr_q, smooth=False, uv2=[u0, u1, u1, u0])


def _emit_double_sided_canvas_grid(mb, grid_pts, grid_uv2, cell_col_fn, thick=0.018, mat='paint',
                                   back_shade=0.82, edge_rim=True):
    """Emit a crisp double-sided solid canvas sail/awning surface from a (nu+1) x (nv+1) point grid
    with UV2 breeze weights and patchy stitched panel vertex colors."""
    nu = len(grid_pts) - 1
    nv = len(grid_pts[0]) - 1
    mb.newoff()
    for iu in range(nu):
        for iv in range(nv):
            p00 = grid_pts[iu][iv]
            p10 = grid_pts[iu + 1][iv]
            p11 = grid_pts[iu + 1][iv + 1]
            p01 = grid_pts[iu][iv + 1]
            nrm = newell([p00, p10, p11, p01])
            if nrm.length < 1e-6:
                continue
            nrm.normalize()
            ctr = (p00 + p10 + p11 + p01) * 0.25
            off = nrm * (thick * 0.5)
            c_front = cell_col_fn(iu, iv)
            c_back = mul(c_front, back_shade)
            u00 = grid_uv2[iu][iv]
            u10 = grid_uv2[iu + 1][iv]
            u11 = grid_uv2[iu + 1][iv + 1]
            u01 = grid_uv2[iu][iv + 1]
            grain = (p10 - p00).normalized() if (p10 - p00).length > 1e-5 else Vector((1, 0, 0))
            mb.fp([p00 + off, p10 + off, p11 + off, p01 + off], mat, c_front, grain,
                  ctr - nrm * 1.0, smooth=False, uv2=[u00, u10, u11, u01])
            mb.fp([p10 - off, p00 - off, p01 - off, p11 - off], mat, c_back, grain,
                  ctr + nrm * 1.0, smooth=False, uv2=[u10, u00, u01, u11])
            if edge_rim:
                if iv == 0:
                    mb.fp([p00 - off, p10 - off, p10 + off, p00 + off], mat, mul(c_front, 0.76),
                          grain, ctr, smooth=False, uv2=[u00, u10, u10, u00])
                if iv == nv - 1:
                    mb.fp([p11 - off, p01 - off, p01 + off, p11 + off], mat, mul(c_front, 0.76),
                          grain, ctr, smooth=False, uv2=[u11, u01, u01, u11])
                if iu == 0:
                    mb.fp([p01 - off, p00 - off, p00 + off, p01 + off], mat, mul(c_front, 0.76),
                          grain, ctr, smooth=False, uv2=[u01, u00, u00, u01])
                if iu == nu - 1:
                    mb.fp([p10 - off, p11 - off, p11 + off, p10 + off], mat, mul(c_front, 0.76),
                          grain, ctr, smooth=False, uv2=[u10, u11, u11, u10])


def _add_leafy_vine_drape(mb, anchor, length, width, out_dir, rng, phase=0.0,
                          c_dark=C_VINE_DARK, c_mid=C_VINE_MID, c_sun=C_VINE_SUN):
    """Sculpted hanging leafy tropical/jungle vine ('foliage') with UV2 wind weights."""
    a = Vector(anchor)
    od = Vector((out_dir[0], 0.0, out_dir[2]))
    if od.length < 1e-4:
        od = Vector((0.0, 0.0, -1.0))
    od.normalize()
    side = Vector((-od.z, 0.0, od.x))

    segs = 4
    stem_pts = []
    for i in range(segs + 1):
        t = i / float(segs)
        sway = sin(t * 3.0 + phase * 6.28) * 0.09 * (0.2 + 0.8 * t)
        out_off = 0.02 + 0.06 * sin(t * pi * 0.80) + 0.04 * t
        stem_pts.append(a + od * out_off + side * sway + Vector((0.0, -length * t, 0.0)))

    for i in range(segs):
        t0 = i / float(segs)
        t1 = (i + 1) / float(segs)
        w0 = width * 0.24 * (1.0 - 0.45 * t0)
        w1 = width * 0.24 * (1.0 - 0.68 * t1)
        p0, p1 = stem_pts[i], stem_pts[i + 1]
        c0 = jit(mix(c_dark, c_mid, t0 * 0.85), rng, 0.05)
        c1 = jit(mix(c_mid, c_sun, t1 * 0.85), rng, 0.05)
        u2_0 = (t0 * 0.88, phase)
        u2_1 = (t1 * 0.94, phase)
        mb.f(
            [mb.v(p0 - side * w0), mb.v(p0 + side * w0), mb.v(p1 + side * w1), mb.v(p1 - side * w1)],
            'foliage', [c0, c0, c1, c1],
            [(0.25, t0), (0.75, t0), (0.75, t1), (0.25, t1)],
            smooth=False, uv2=[u2_0, u2_0, u2_1, u2_1],
        )

    n_leaves = max(5, int(length * 2.4))
    for li in range(n_leaves):
        t = (li + 0.30) / float(n_leaves + 0.20)
        idx_f = t * segs
        i0 = min(segs - 1, int(idx_f))
        frac = idx_f - i0
        root = stem_pts[i0].lerp(stem_pts[i0 + 1], frac)
        sgn = -1.0 if (li % 2 == 0) else 1.0
        l_scale = (0.85 + 0.44 * sin(t * pi * 0.85)) * (1.0 - 0.24 * t)
        l_len = width * 1.56 * l_scale * rng.uniform(0.88, 1.12)
        l_wid = width * 0.68 * l_scale * rng.uniform(0.88, 1.12)
        l_dir = (side * (sgn * 0.64) + od * (0.48 + rng.uniform(-0.08, 0.14)) + Vector((0.0, -0.74, 0.0))).normalized()
        l_perp = l_dir.cross(od)
        l_perp = l_perp.normalized() if l_perp.length > 1e-4 else side

        p_base  = root
        p_mid_l = root + l_dir * (l_len * 0.42) - l_perp * l_wid + od * 0.03
        p_mid_r = root + l_dir * (l_len * 0.42) + l_perp * l_wid + od * 0.03
        p_tip   = root + l_dir * l_len - Vector((0.0, l_len * 0.12, 0.0))

        c_b = jit(mix(c_dark, c_mid, t * 0.7), rng, 0.05)
        c_t = jit(mix(c_mid, c_sun, 0.35 + 0.65 * t), rng, 0.06)
        w_r = t * 0.88
        w_t = min(0.98, t * 0.90 + 0.10)
        u2_b = (w_r, phase)
        u2_m = (0.5 * (w_r + w_t), phase)
        u2_e = (w_t, phase)
        mb.f(
            [mb.v(p_base), mb.v(p_mid_l), mb.v(p_tip), mb.v(p_mid_r)],
            'foliage', [c_b, c_t, c_t, c_t],
            [(0.5, 0.0), (0.0, 0.5), (0.5, 1.0), (1.0, 0.5)],
            smooth=False, uv2=[u2_b, u2_m, u2_e, u2_m],
        )


def _add_coastal_fern_cluster(mb, root_pos, scale=0.70, n_fronds=3, rng=None, phase=0.0,
                              lean_dir=None, segs=2, c_dark=C_VINE_DARK, c_mid=C_VINE_MID, c_tip=C_VINE_SUN):
    """Broad painterly coastal/jungle fern rosette ('foliage') with UV2 wind weights."""
    rp = Vector(root_pos)
    base_rot = rng.uniform(0.0, 2.0 * pi) if rng else 0.0
    for fi in range(n_fronds):
        ang = base_rot + 2.0 * pi * fi / float(n_fronds) + (rng.uniform(-0.20, 0.20) if rng else 0.0)
        f_len = scale * (rng.uniform(0.86, 1.12) if rng else 1.0)
        f_w = scale * (rng.uniform(0.24, 0.32) if rng else 0.28)
        f_arch_h = scale * (rng.uniform(0.38, 0.52) if rng else 0.44)
        f_droop = scale * (rng.uniform(0.20, 0.30) if rng else 0.25)
        dir_xz = Vector((cos(ang), 0.0, sin(ang)))
        if lean_dir is not None:
            ld = Vector((lean_dir[0], 0.0, lean_dir[2]))
            if ld.length > 1e-4:
                dir_xz = (dir_xz + ld.normalized() * 0.48).normalized()
        side = Vector((-dir_xz.z, 0.0, dir_xz.x))
        f_phase = (phase + fi * 0.17) % 1.0

        prev_l = prev_m = prev_r = None
        for si in range(segs + 1):
            t = si / float(segs)
            w = f_w * (0.22 + 0.95 * sin(t * pi * 0.86)) * (1.0 - 0.82 * (t ** 2.2))
            arch_y = sin(t * pi * 0.78) * f_arch_h - (t * t) * f_droop
            ctr = rp + dir_xz * (f_len * t) + Vector((0.0, arch_y, 0.0))
            v_lift = w * 0.22
            pl = ctr - side * w + Vector((0.0, v_lift, 0.0))
            pr = ctr + side * w + Vector((0.0, v_lift, 0.0))
            pm = ctr
            if prev_m is not None:
                t0 = (si - 1) / float(segs)
                c0 = jit(mix(c_dark, c_mid, t0 * 0.9), rng, 0.05) if rng else c_mid
                c1 = jit(mix(c_mid, c_tip, t * 0.92), rng, 0.05) if rng else c_tip
                w0 = (t0 ** 1.35) * 0.92
                w1 = (t ** 1.35) * 0.92
                u2_0 = (w0, f_phase)
                u2_1 = (w1, f_phase)
                if si == segs:
                    mb.f([mb.v(prev_l), mb.v(prev_m), mb.v(pm)], 'foliage',
                         [c0, c0, c1], [(0.0, t0), (0.5, t0), (0.5, t)], smooth=False, uv2=[u2_0, u2_0, u2_1])
                    mb.f([mb.v(prev_m), mb.v(prev_r), mb.v(pm)], 'foliage',
                         [c0, c0, c1], [(0.5, t0), (1.0, t0), (0.5, t)], smooth=False, uv2=[u2_0, u2_0, u2_1])
                else:
                    mb.f([mb.v(prev_l), mb.v(prev_m), mb.v(pm), mb.v(pl)], 'foliage',
                         [c0, c0, c1, c1], [(0.0, t0), (0.5, t0), (0.5, t), (0.0, t)],
                         smooth=False, uv2=[u2_0, u2_0, u2_1, u2_1])
                    mb.f([mb.v(prev_m), mb.v(prev_r), mb.v(pr), mb.v(pm)], 'foliage',
                         [c0, c0, c1, c1], [(0.5, t0), (1.0, t0), (1.0, t), (0.5, t)],
                         smooth=False, uv2=[u2_0, u2_0, u2_1, u2_1])
            prev_l, prev_m, prev_r = pl, pm, pr


def _build_mossy_tuft(mb, center, radii, rng):
    """Low sculpted mossy stone-turf cushion ('limestone_moss') perched cleanly on stone ledges."""
    cx, cy, cz = center
    rx, ry, rz = radii
    with xf(mb, T(cx, cy, cz)):
        secs = [
            _reg_poly(0.0, -ry * 0.25, 0.0, 1.0, sides=5, rot_deg=rng.uniform(0, 72), sx=rx * 1.02, sz=rz * 1.02),
            _reg_poly(0.0,  ry * 0.48, 0.0, 1.0, sides=5, rot_deg=rng.uniform(0, 72), sx=rx * 0.74, sz=rz * 0.74),
            _reg_poly(0.0,  ry * 0.92, 0.0, 1.0, sides=5, rot_deg=rng.uniform(0, 72), sx=rx * 0.30, sz=rz * 0.30),
        ]
        loft(mb, secs, 'limestone_moss', C_MOSS_CUSHION, closed=True, caps=(False, True), mode='flat',
             scols=[C_MOSS_DEEP, C_MOSS_CUSHION, C_VINE_SUN])


def _sculpt_glow_ribbon(mb, path_pts, widths, surface_nrm, hot_core=True, ridge_h=0.036, mat='glass',
                        c_core=C_FLAME_CORE, c_mid_col=C_FLAME_MID, c_edge_col=C_FLAME_DEEP, c_tip_col=C_MAGMA_CRIMSON):
    """Surface-hugging glowing molten magma or aquatic rune vein ridge."""
    pts = [Vector(p) for p in path_pts]
    nrm = Vector(surface_nrm).normalized()
    n = len(pts)
    if n < 2:
        return
    mb.newoff()
    left_pts, mid_pts, right_pts = [], [], []
    for i in range(n):
        t_dir = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]
        if t_dir.length < 1e-5:
            t_dir = Vector((0.0, 1.0, 0.0))
        t_dir.normalize()
        side = t_dir.cross(nrm)
        if side.length < 1e-4:
            side = Vector((1.0, 0.0, 0.0))
        side.normalize()
        w = widths[i]
        left_pts.append(pts[i] - side * w - nrm * 0.010)
        right_pts.append(pts[i] + side * w - nrm * 0.010)
        mid_pts.append(pts[i] + nrm * (ridge_h + 0.005 * sin(i * 1.7)))
    for i in range(n - 1):
        cm = c_core if (hot_core and i <= n // 2) else c_mid_col
        ce = c_edge_col if i < n - 2 else c_tip_col
        inside = (pts[i] + pts[i + 1]) * 0.5 - nrm * 0.5
        mb.fp([left_pts[i], mid_pts[i], mid_pts[i + 1], left_pts[i + 1]], mat,
              [ce, cm, cm, ce], (1, 0, 0), inside, smooth=False)
        mb.fp([mid_pts[i], right_pts[i], right_pts[i + 1], mid_pts[i + 1]], mat,
              [cm, ce, ce, cm], (1, 0, 0), inside, smooth=False)


def _add_chain_links(mb, p_start, p_end, n_links=4, link_r=0.19, wire_r=0.052,
                     segs=5, psegs=4, sag=0.14, mat='iron', rust_stride=2, stretch_y=1.44,
                     col_a=C_IRON_FORGED, col_b=C_IRON_RUST_HI):
    """Tightly interlocking arc-length-spaced forged-iron chain links."""
    a = Vector(p_start)
    b = Vector(p_end)
    if (b - a).length < 1e-4 or n_links < 1:
        return
    samples = 40
    pts_s = [
        a.lerp(b, i / float(samples))
        + Vector((0.0, -sag * 4.0 * (i / float(samples)) * (1.0 - i / float(samples)), 0.0))
        for i in range(samples + 1)
    ]
    cum = [0.0]
    for i in range(1, len(pts_s)):
        cum.append(cum[-1] + (pts_s[i] - pts_s[i - 1]).length)
    total_len = cum[-1]
    if total_len < 1e-5:
        return

    def _sample_at(s_dist):
        s_dist = max(0.0, min(total_len, s_dist))
        for i in range(1, len(cum)):
            if cum[i] >= s_dist:
                span = max(cum[i] - cum[i - 1], 1e-6)
                u = (s_dist - cum[i - 1]) / span
                return pts_s[i - 1].lerp(pts_s[i], u)
        return pts_s[-1]

    for k in range(n_links):
        s_mid = total_len * (k + 0.5) / float(n_links)
        pt = _sample_at(s_mid)
        q0 = _sample_at(s_mid - total_len * 0.02)
        q1 = _sample_at(s_mid + total_len * 0.02)
        tang = q1 - q0
        if tang.length < 1e-6:
            tang = Vector((0.0, -1.0, 0.0))
        rot_q = Vector((0.0, 1.0, 0.0)).rotation_difference(tang.normalized()).to_matrix().to_4x4()
        spin = R('Y', 90.0 if (k % 2 == 0) else 0.0)
        l_col = col_b if (k % rust_stride == 0) else col_a
        with xf(mb, T(pt) @ rot_q @ spin @ S(0.76, stretch_y, 0.76) @ M_Y2Z):
            torus(mb, link_r, wire_r, segs, psegs, mat, l_col, False)


# ==============================================================================
# 1. PIRATE SAILMAKER RIGGING LOFT (pirate_sailmaker_rigging_loft.glb)
# ==============================================================================

def _build_canvas_bolt(mb, M_bolt, radius=0.140, length=0.72, col_cloth=C_CREAM_SAIL, col_band=C_CRIMSON_HI):
    """Rolled sailmaker's linen/canvas bolt around a wooden dowel with hemp tying ribbon."""
    hl = length * 0.5
    with xf(mb, M_bolt @ M_Y2X):
        cyl(mb, radius, -hl, hl, 6, 'paint', col_cloth, False, 0.0)
        cyl(mb, 0.040, -hl - 0.08, hl + 0.08, 5, 'timber', C_OAK_DEEP, False, 0.0)
        cyl(mb, radius + 0.012, -0.055, 0.055, 6, 'rope', col_band, False, 0.0)


def gen_pirate_sailmaker_rigging_loft(outdir):
    """Open-air harbour sailmaker's awning loft (~5.4 m W x 4.0 m D x 4.0 m H, -2.80 m cobble
    wharf skirt) with heavy braced timber framing draped in freshly stitched patched cream-and-
    crimson canvas mainsail panels (UV2 gentle breeze sway), wooden sewing trestle table w/ canvas
    bolts & coiled marline twine, hanging wooden pulley blocks, striped guild burgee (UV2), convex
    collider 'col_sailmaker_base', and warm brass lantern empty 'Lantern_Sailmaker'."""
    clear_scene()
    mb = MB('pirate_sailmaker_rigging_loft', seed=2101)
    rng = random.Random(SEED + 2101)
    col_pts = []

    DECK_Y = 0.44
    POST_X = 2.02
    POST_Z = 1.20
    EAVE_Y = 2.68
    RIDGE_Y = 3.44

    # 1. Deep Harbour Cobble-and-Sandstone Wharf Skirt plunging cleanly to y = -2.80 m (~5.4 m W x 4.0 m D)
    found_secs = [
        _rect_oct(0.0, -2.80, 0.0, 2.64, 1.88, 0.34),
        _rect_oct(0.0, -1.15, 0.0, 2.58, 1.82, 0.32),
        _rect_oct(0.0,  0.00, 0.0, 2.52, 1.76, 0.30),
        _rect_oct(0.0,  0.34, 0.0, 2.46, 1.70, 0.28),
    ]
    _loft_horizontal_masonry(
        mb, found_secs, 'limestone',
        [C_COBBLE_WET, C_COBBLE_DARK, C_COBBLE_MID, C_COBBLE_HI],
        rng, caps=(True, True), top_mat='temple_stone', top_col=C_SANDSTONE_MID,
    )

    for yc, hx, hz in ((-2.80, 2.64, 1.88), (0.0, 2.52, 1.76), (DECK_Y, 2.46, 1.70), (3.44, 2.22, 1.40)):
        col_pts.extend(_rect_oct(0.0, yc, 0.0, hx, hz, 0.28))

    # Planked Oak Sail-Loft Floor Deck (y = 0.34 .. 0.44 m) + Seaward Apron Step & Mooring Pilings
    cbox(mb, (0.0, 0.36, 0.0), (4.82, 0.12, 3.30), 'timber', C_OAK_DEEP, 0.0)
    for dpi in range(6):
        pz_d = -1.32 + dpi * (2.64 / 5.0)
        cbox(mb, (0.0, DECK_Y - 0.01, pz_d), (4.76, 0.055, 0.48), 'timber',
             C_DRIFT_MID if dpi % 2 == 0 else C_OAK_RICH, 0.0)
    cbox(mb, (0.0, 0.18, -1.80), (1.92, 0.32, 0.34), 'temple_stone', C_SANDSTONE_MID, 0.0)

    for px_p in (-2.40, 2.40):
        for pz_p in (-1.62, 1.62):
            top_p = DECK_Y + (0.36 if pz_p < 0 else 0.30)
            with xf(mb, T(px_p, 0.0, pz_p)):
                cyl(mb, 0.13, -0.35, top_p, 6, 'timber', C_DRIFT_DARK, False, 0.0, 0.115)
                cyl(mb, 0.145, top_p - 0.17, top_p - 0.08, 6, 'rope', C_HEMP_MID, False, 0.0)

    # 2. Heavy Braced Oak Loft Timber Framing (4 Main Posts, Knee Braces, Gable Rafters & Hanging Yards)
    for sx in (-1.0, 1.0):
        px = sx * POST_X
        for sz in (-1.0, 1.0):
            pz = sz * POST_Z
            cbox(mb, (px, 0.5 * (DECK_Y + EAVE_Y), pz), (0.20, EAVE_Y - DECK_Y, 0.20), 'timber', C_OAK_DEEP, 0.0)
            cbox(mb, (px, DECK_Y + 0.11, pz), (0.28, 0.22, 0.28), 'iron', C_IRON_FORGED, 0.0)
            cbox(mb, (px, EAVE_Y - 0.14, pz), (0.25, 0.12, 0.25), 'iron', C_IRON_FORGED, 0.0)
            _add_beam(mb, (px, EAVE_Y - 0.62, pz), (px - sx * 0.62, EAVE_Y - 0.04, pz),
                      0.10, 0.11, 'timber', C_OAK_RICH, 0.0)
            _add_beam(mb, (px, EAVE_Y - 0.58, pz), (px, EAVE_Y - 0.04, pz - sz * 0.58),
                      0.10, 0.10, 'timber', C_OAK_RICH, 0.0)
        # Side wall-plates & gable end-trusses tucked cleanly UNDER the draped awning roof!
        cbox(mb, (px, EAVE_Y - 0.02, 0.0), (0.18, 0.16, POST_Z * 2.0 + 0.32), 'timber', C_OAK_DEEP, 0.0)
        _add_beam(mb, (px, EAVE_Y - 0.04, -POST_Z - 0.16), (px, RIDGE_Y - 0.06, 0.0), 0.13, 0.13, 'timber', C_OAK_RICH, 0.0)
        _add_beam(mb, (px, EAVE_Y - 0.04,  POST_Z + 0.16), (px, RIDGE_Y - 0.06, 0.0), 0.13, 0.13, 'timber', C_OAK_RICH, 0.0)
        cbox(mb, (px, EAVE_Y + 0.28, 0.0), (0.13, 0.64, 0.13), 'timber', C_OAK_SUN, 0.0)
        if sx < 0:
            cbox(mb, (px, DECK_Y + 0.96, 0.0), (0.12, 0.11, POST_Z * 2.0 - 0.12), 'timber', C_OAK_SUN, 0.0)

    # Overhead Ridge-Beam & Eave Purlins seated cleanly BENEATH the canvas awning (ZERO wood clipping!)
    cbox(mb, (0.0, RIDGE_Y - 0.04, 0.0), (POST_X * 2.0 + 0.88, 0.20, 0.18), 'timber', C_OAK_DEEP, 0.0)
    for sz in (-1.0, 1.0):
        cbox(mb, (0.0, EAVE_Y - 0.04, sz * (POST_Z + 0.12)),
             (POST_X * 2.0 + 0.64, 0.14, 0.14), 'timber', C_OAK_RICH, 0.0)
    for sz in (-1.0, 1.0):
        _add_beam(mb, (0.0, EAVE_Y - 0.04, sz * (POST_Z + 0.16)), (0.0, RIDGE_Y - 0.06, 0.0),
                  0.12, 0.12, 'timber', C_OAK_RICH, 0.0)
    cbox(mb, (0.0, EAVE_Y + 0.22, 0.0), (0.13, 0.12, POST_Z * 1.40), 'timber', C_OAK_SUN, 0.0)

    # Suspended timber sail-stitching yardarm hanging inside the rear half of the loft (z = +0.54 m)
    YARD_Y = 2.60
    YARD_Z = 0.54
    with xf(mb, T(0.16, YARD_Y, YARD_Z) @ M_Y2X):
        cyl(mb, 0.070, -1.62, 1.62, 6, 'timber', C_OAK_SUN, False, 0.0, 0.062)
        for yx in (-1.30, 1.30):
            cyl(mb, 0.086, yx - 0.06, yx + 0.06, 6, 'rope', C_HEMP_HI, False, 0.0)
    for yx in (-1.14, 1.46):
        tube(mb, [(yx, EAVE_Y + 0.22, YARD_Z), (yx, YARD_Y + 0.04, YARD_Z)],
             0.025, 4, 'rope', C_HEMP_MID, caps=(False, False), mode='flat')

    # 3. Draped Freshly Stitched Patched Cream-and-Crimson Canvas Mainsail Awning Roof ('paint' + UV2!)
    # Elevated cleanly OVER the ridge & eave purlins (zero beam clipping!) with scalloped breeze eaves!
    nu_aw, nv_aw = 6, 6
    aw_pts = []
    aw_uv2 = []
    for iu in range(nu_aw + 1):
        u = iu / float(nu_aw)
        x = -2.28 + 4.56 * u
        span_sag = abs(sin((x / 2.02) * pi)) * 0.036
        col_p, col_u2 = [], []
        for iv in range(nv_aw + 1):
            v = iv / float(nv_aw)  # 0 = front seaward eave (-Z), 0.5 = ridge (0), 1 = rear eave (+Z)
            dist_ridge = abs(v - 0.5) * 2.0
            if dist_ridge <= 0.80:
                s = dist_ridge / 0.80
                z = (v - 0.5) * 2.0 / 0.80 * (POST_Z + 0.30)
                y = (RIDGE_Y + 0.16) * (1.0 - s) + (EAVE_Y + 0.16) * s - span_sag * sin(s * pi)
                w_wind = (s ** 1.8) * 0.24
            else:
                s_val = (dist_ridge - 0.80) / 0.20
                z_sgn = -1.0 if v < 0.5 else 1.0
                z = z_sgn * (POST_Z + 0.34 + 0.04 * s_val)
                scallop = 0.065 * sin(u * 4.0 * pi) * s_val
                y = (EAVE_Y + 0.14) - 0.40 * s_val - scallop
                w_wind = 0.24 + 0.36 * s_val
            col_p.append(Vector((x, y, z)))
            col_u2.append((w_wind, (0.18 + 0.32 * u) % 1.0))
        aw_pts.append(col_p)
        aw_uv2.append(col_u2)

    def _awning_patch_col(iu, iv):
        if (iu, iv) in ((1, 1), (4, 2), (4, 4), (1, 4)):
            return C_CRIMSON_HI
        if (iu, iv) in ((2, 0), (3, 5), (0, 2)):
            return C_CRIMSON_MID
        if (iu, iv) in ((3, 1), (2, 3)):
            return C_TEAL_HI
        return C_CREAM_SAIL if (iu + iv) % 2 == 0 else C_CREAM_AGED

    _emit_double_sided_canvas_grid(
        mb, aw_pts, aw_uv2, _awning_patch_col, thick=0.020, mat='paint', back_shade=0.80, edge_rim=False
    )

    # Brass awning lash grommets cleanly beneath the eaves
    for lx in (-2.02, 2.02):
        for lz in (-POST_Z - 0.18, POST_Z + 0.18):
            with xf(mb, T(lx, EAVE_Y - 0.04, lz) @ M_Y2Z):
                torus(mb, 0.058, 0.016, 5, 4, 'brass', C_GOLD_BRIGHT, False)

    # 4. Hanging Half-Stitched Patched Mainsail Panel draped from Overhead Yard down to Workbench ('paint' + UV2!)
    nu_s, nv_s = 5, 4
    sail_pts, sail_uv2 = [], []
    for iu in range(nu_s + 1):
        u = iu / float(nu_s)
        x = -1.24 + 2.64 * u
        col_p, col_u2 = [], []
        for iv in range(nv_s + 1):
            v = iv / float(nv_s)
            y = YARD_Y - 0.04 - 1.44 * v
            belly = sin(v * pi) * (0.24 + 0.06 * sin(u * pi))
            ripple = sin(u * 2.5 * pi + v * 1.4) * 0.04 * sin(v * pi)
            z = YARD_Z - belly * 0.84 + (0.22 * v * v if v > 0.72 else 0.0) + ripple
            w_wind = sin(v * pi) * 0.44 + (0.14 if (v > 0.8 and u > 0.7) else 0.0)
            col_p.append(Vector((x, y, z)))
            col_u2.append((w_wind, (0.55 + 0.25 * u) % 1.0))
        sail_pts.append(col_p)
        sail_uv2.append(col_u2)

    def _sail_panel_col(iu, iv):
        if iu in (2, 3) and iv in (1, 2):
            return C_CRIMSON_HI
        if (iu, iv) in ((0, 2), (4, 1), (4, 3)):
            return C_CRIMSON_MID
        if (iu, iv) == (1, 1):
            return C_CREAM_SHADE
        return C_CREAM_SAIL if (iu + iv) % 2 == 0 else C_CREAM_AGED

    _emit_double_sided_canvas_grid(
        mb, sail_pts, sail_uv2, _sail_panel_col, thick=0.018, mat='paint', back_shade=0.84, edge_rim=False
    )

    for gx in (-1.12, 0.08, 1.32):
        with xf(mb, T(gx, YARD_Y - 0.14, YARD_Z - 0.04) @ M_Y2Z):
            torus(mb, 0.046, 0.014, 5, 4, 'brass', C_GOLD_BRIGHT, False)
        tube(mb, [(gx, YARD_Y - 0.56, YARD_Z - 0.20), (gx + 0.04, YARD_Y - 0.86, YARD_Z - 0.28)],
             0.015, 4, 'rope', C_HEMP_HI, caps=(True, True), mode='flat')

    # Folded spare jib cloth draped cleanly over Port Drying Rail (x = -2.02 m, UV2 gentle edge sway!)
    jib_pts, jib_uv2 = [], []
    for iu in range(4):
        u = iu / 3.0
        z = -0.80 + 1.44 * u
        col_p, col_u2 = [], []
        for iv in range(4):
            v = iv / 3.0
            dx = -0.14 + 0.28 * v
            y = DECK_Y + 1.05 - 0.56 * abs(v - 0.5) * 2.0
            if v in (0.0, 1.0):
                dx += (-0.05 if v == 0.0 else 0.05)
            w_u2 = (abs(v - 0.5) * 2.0) ** 1.5 * 0.34
            col_p.append(Vector((-POST_X + dx, y, z)))
            col_u2.append((w_u2, (0.72 + 0.18 * u) % 1.0))
        jib_pts.append(col_p)
        jib_uv2.append(col_u2)
    _emit_double_sided_canvas_grid(
        mb, jib_pts, jib_uv2,
        lambda iu, iv: C_CRIMSON_HI if iu == 1 else (C_CREAM_SAIL if (iu + iv) % 2 == 0 else C_CREAM_AGED),
        thick=0.016, mat='paint', back_shade=0.82, edge_rim=False,
    )

    # 5. Heavy Wooden Sewing Trestle Table w/ Rolled Canvas Bolts, Stitched Patch & Coiled Marline Twine!
    TBL_X, TBL_Z = -0.12, -0.32
    TBL_TOP_Y = DECK_Y + 0.84
    cbox(mb, (TBL_X, TBL_TOP_Y, TBL_Z), (2.36, 0.09, 1.00), 'timber', C_OAK_SUN, 0.0)
    cbox(mb, (TBL_X, DECK_Y + 0.24, TBL_Z), (2.04, 0.065, 0.70), 'timber', C_OAK_DEEP, 0.0)
    for tx_l in (-0.96, 0.0, 0.96):
        _add_beam(mb, (TBL_X + tx_l, DECK_Y, TBL_Z - 0.42), (TBL_X + tx_l, TBL_TOP_Y - 0.02, TBL_Z + 0.34),
                  0.092, 0.092, 'timber', C_OAK_DEEP, 0.0)
        _add_beam(mb, (TBL_X + tx_l, DECK_Y, TBL_Z + 0.42), (TBL_X + tx_l, TBL_TOP_Y - 0.02, TBL_Z - 0.34),
                  0.092, 0.092, 'timber', C_OAK_RICH, 0.0)
    cbox(mb, (TBL_X - 0.18, TBL_TOP_Y + 0.056, TBL_Z - 0.04), (1.16, 0.022, 0.76), 'paint', C_CREAM_SAIL, 0.0, M=R('Y', 3.0))
    cbox(mb, (TBL_X - 0.08, TBL_TOP_Y + 0.074, TBL_Z - 0.08), (0.44, 0.020, 0.36), 'paint', C_CRIMSON_HI, 0.0, M=R('Y', -5.0))
    _add_beam(mb, (TBL_X - 0.56, TBL_TOP_Y + 0.082, TBL_Z - 0.26), (TBL_X - 0.26, TBL_TOP_Y + 0.082, TBL_Z - 0.16),
              0.028, 0.018, 'iron', C_IRON_BRIGHT, 0.0)
    _add_beam(mb, (TBL_X - 0.56, TBL_TOP_Y + 0.082, TBL_Z - 0.16), (TBL_X - 0.26, TBL_TOP_Y + 0.082, TBL_Z - 0.28),
              0.028, 0.018, 'iron', C_IRON_BRIGHT, 0.0)
    with xf(mb, T(TBL_X - 0.52, TBL_TOP_Y + 0.085, TBL_Z + 0.18) @ R('Y', 24.0) @ M_Y2X):
        cyl(mb, 0.036, -0.14, 0.16, 5, 'timber', C_OAK_RICH, False, 0.0, 0.009)
    _build_canvas_bolt(mb, T(TBL_X + 0.76, TBL_TOP_Y + 0.17, TBL_Z - 0.18) @ R('Y', 84.0),
                       radius=0.132, length=0.70, col_cloth=C_CREAM_SAIL, col_band=C_CRIMSON_HI)
    _build_canvas_bolt(mb, T(TBL_X + 0.50, TBL_TOP_Y + 0.16, TBL_Z + 0.08) @ R('Y', 76.0),
                       radius=0.122, length=0.66, col_cloth=C_CRIMSON_HI, col_band=C_HEMP_HI)
    _build_canvas_bolt(mb, T(TBL_X + 0.64, TBL_TOP_Y + 0.35, TBL_Z - 0.06) @ R('Y', 80.0),
                       radius=0.112, length=0.64, col_cloth=C_CREAM_AGED, col_band=C_TEAL_HI)
    _build_canvas_bolt(mb, T(TBL_X - 0.42, DECK_Y + 0.40, TBL_Z) @ R('Y', 6.0),
                       radius=0.140, length=0.90, col_cloth=C_CREAM_AGED, col_band=C_HEMP_MID)
    _build_rope_coil(mb, (TBL_X + 0.54, DECK_Y + 0.28, TBL_Z - 0.04), radius=0.22, turns=2, r=0.036,
                     segs=5, psegs=4, col_a=C_HEMP_HI, col_b=C_HEMP_MID)
    _build_rope_coil(mb, (TBL_X - 0.90, TBL_TOP_Y + 0.05, TBL_Z + 0.14), radius=0.17, turns=2, r=0.032,
                     segs=5, psegs=4, col_a=C_HEMP_HI, col_b=C_HEMP_MID)
    with xf(mb, T(TBL_X - 0.88, TBL_TOP_Y + 0.05, TBL_Z - 0.24)):
        cyl(mb, 0.115, 0.0, 0.03, 5, 'timber', C_OAK_DEEP, False, 0.0)
        cyl(mb, 0.092, 0.03, 0.22, 5, 'rope', C_HEMP_HI, False, 0.0)
        cyl(mb, 0.115, 0.22, 0.25, 5, 'timber', C_OAK_DEEP, False, 0.0)
    _build_rope_coil(mb, (1.52, DECK_Y + 0.01, -1.12), radius=0.29, turns=3, r=0.044, segs=6, psegs=4,
                     col_a=C_HEMP_HI, col_b=C_HEMP_MID)
    _build_coopered_barrel(mb, T(-1.52, DECK_Y + 0.34, -1.08) @ R('Y', 18.0),
                           radius=0.26, height=0.66, rng=rng, segs=6)

    # Rear (+Z) Open-Topped Slatted Oak Canvas-Bolt Bin (ZERO z-fighting!) & Reserve Hawser Coil!
    with xf(mb, T(-1.18, DECK_Y, 1.08) @ R('Y', 8.0)):
        cbox(mb, (0.0, 0.05, 0.0), (0.84, 0.08, 0.54), 'timber', C_OAK_DEEP, 0.0)
        cbox(mb, (0.0, 0.32, -0.25), (0.84, 0.52, 0.06), 'timber', C_OAK_RICH, 0.0)
        cbox(mb, (0.0, 0.32,  0.25), (0.84, 0.52, 0.06), 'timber', C_OAK_RICH, 0.0)
        cbox(mb, (-0.40, 0.32, 0.0), (0.06, 0.52, 0.56), 'timber', C_OAK_SUN, 0.0)
        cbox(mb, ( 0.40, 0.32, 0.0), (0.06, 0.52, 0.56), 'timber', C_OAK_SUN, 0.0)
        for bz_r in (-0.27, 0.27):
            cbox(mb, (0.0, 0.56, bz_r), (0.88, 0.05, 0.04), 'timber', C_OAK_DEEP, 0.0)
    for bx_r, bz_r, bcol in ((-1.36, 1.04, C_CREAM_SAIL), (-1.14, 1.10, C_CRIMSON_HI), (-0.94, 1.02, C_CREAM_AGED)):
        with xf(mb, T(bx_r, DECK_Y + 0.58, bz_r) @ R('Z', (bx_r + 1.15) * 24.0)):
            cyl(mb, 0.112, -0.44, 0.52, 6, 'paint', bcol, False, 0.0)
            cyl(mb, 0.035, -0.46, 0.60, 5, 'timber', C_OAK_DEEP, False, 0.0)
    _build_rope_coil(mb, (1.24, DECK_Y + 0.01, 1.06), radius=0.27, turns=2, r=0.044, segs=5, psegs=4,
                     col_a=C_HEMP_MID, col_b=C_HEMP_DARK)

    # 6. Hanging Wooden Pulley Blocks & Taut Halyard Tackle Lines Belayed to Oak Post Cleats!
    for bx_p, bz_p, y_top, y_bot, cle_x in (
        ( 2.26, -0.64, EAVE_Y - 0.20, 1.62,  POST_X),
        (-2.26, -0.48, EAVE_Y - 0.20, 1.80, -POST_X),
    ):
        _add_beam(mb, (cle_x, EAVE_Y - 0.04, bz_p), (bx_p + (0.08 if bx_p > 0 else -0.08), EAVE_Y - 0.04, bz_p),
                  0.12, 0.12, 'timber', C_OAK_DEEP, 0.0)
        _build_pulley_block(mb, (bx_p, y_top, bz_p), scale=1.00, hook_down=True)
        _build_pulley_block(mb, (bx_p, y_bot, bz_p), scale=0.88, hook_down=False)
        for ox_r in (-0.040, 0.040):
            tube(mb, [(bx_p + ox_r, y_top - 0.10, bz_p), (bx_p + ox_r, y_bot + 0.10, bz_p)],
                 0.022, 4, 'rope', C_HEMP_HI, caps=(False, False), mode='flat')
        tube(mb, [(bx_p, y_top - 0.04, bz_p), (cle_x + (0.12 if bx_p > 0 else -0.12), DECK_Y + 1.02, bz_p - 0.44)],
             0.022, 4, 'rope', C_HEMP_MID, caps=(False, False), mode='flat')
        cbox(mb, (cle_x + (0.13 if bx_p > 0 else -0.13), DECK_Y + 1.02, bz_p - 0.44),
             (0.08, 0.28, 0.06), 'timber', C_OAK_SUN, 0.0)

    # 7. Tall Sailmakers' Guild Burgee Mast & Striped Crimson-Cream-Gold Burgee ('paint' + UV2!)
    MAST_X, MAST_Z = -POST_X, POST_Z
    with xf(mb, T(MAST_X, 0.0, MAST_Z)):
        cyl(mb, 0.075, EAVE_Y - 0.06, 3.92, 6, 'timber', C_OAK_DEEP, False, 0.0, 0.042)
        lathe(mb, [(0.0, 3.90), (0.080, 3.96), (0.0, 4.04)], 6, 'brass', C_GOLD_BRIGHT, False)
    _build_wind_banner(
        mb, root_pos=(MAST_X + 0.05, 3.70, MAST_Z), length=1.36, h0=0.40,
        out_dir=(0.90, -0.02, -0.44),
        col_main=C_CRIMSON_HI, col_alt=C_CREAM_SAIL, col_trim=C_GOLD_BRIGHT,
        phase=0.31, swallowtail=True,
    )

    # 8. Warm Brass Sailmaker Work-Lantern ('Lantern_Sailmaker') cantilevered cleanly over the Front Apron!
    LANTERN_POS = Vector((-1.40, 2.22, -1.52))
    _add_beam(mb, (-POST_X, 2.58, -POST_Z), (-1.36, 2.60, -1.58), 0.080, 0.084, 'timber', C_OAK_RICH, 0.0)
    _add_beam(mb, (-POST_X, 2.12, -POST_Z), (-1.64, 2.58, -1.40), 0.052, 0.056, 'iron', C_IRON_FORGED, 0.0)
    _add_beam(mb, (-1.40, 2.60, -1.52), LANTERN_POS + Vector((0.0, 0.28, 0.0)), 0.024, 0.024, 'iron', C_IRON_FORGED, 0.0)
    _build_storm_lantern(mb, LANTERN_POS, scale=0.86, brass_cage=True, hanging=True)

    # 9. Coastal Harbour Ferns ('foliage' + UV2) tucked neatly beside the stone apron step & wharf flanks (ZERO piling clipping!)
    for fpos, fsc, flean, fph in (
        ((-1.28, 0.26, -1.72), 0.50, (-0.5, 0.0, -0.85), 0.14),
        (( 1.28, 0.26, -1.72), 0.50, ( 0.5, 0.0, -0.85), 0.42),
        ((-2.32, 0.30,  0.32), 0.46, (-1.0, 0.0,  0.00), 0.68),
        (( 2.32, 0.30, -0.22), 0.46, ( 1.0, 0.0,  0.00), 0.91),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=3, rng=rng, phase=fph, lean_dir=flean, segs=2)

    build(mb)

    add_empty('Lantern_Sailmaker', LANTERN_POS)
    col_piece('col_sailmaker_base', col_pts)
    export_landmark_glb(outdir, 'pirate_sailmaker_rigging_loft.glb')


# ==============================================================================
# 2. ANCIENT SERPENT TIDE PORTAL (ancient_serpent_tide_portal.glb)
# ==============================================================================

def _build_coiled_stone_serpent(mb, side_sgn, pier_x, base_y, lintel_y, rng):
    """Sculpted mossy carved-stone sea-serpent spiraling CONTINUOUSLY OUTSIDE the portal jamb pier
    in exact mirror symmetry (zero buried sections, smooth C1 sweep into lintel crest!), with fierce
    open fanged jaws, carved dorsal fins, curved horns & glowing cyan-turquoise eyes ('skull_glow')."""
    n_st = 18
    pts = []
    rads = []
    # Exact helix endpoint at u=1 (ang = -95 deg: front of pier, sweeping smoothly inward toward x=0!)
    ang_end = radians(-95.0)
    p_join = Vector((pier_x + side_sgn * 0.52 * cos(ang_end), lintel_y - 0.02, 0.56 * sin(ang_end)))
    for i in range(n_st + 1):
        t = i / float(n_st)
        if t <= 0.72:
            u = t / 0.72
            # Smooth 1.08-turn mirror-symmetric external helix embracing the 0.40x0.42m stone pier!
            # Starts outer-front base (295 deg) -> inner -> rear (+Z) -> outer flank -> front-inner haunch (-95 deg)!
            ang = radians(295.0 - 390.0 * u)
            rx_wrap = 0.56 - 0.04 * u
            rz_wrap = 0.60 - 0.04 * u
            px = pier_x + side_sgn * rx_wrap * cos(ang)
            pz = rz_wrap * sin(ang)
            py = base_y + 0.18 + (lintel_y - base_y - 0.20) * (u ** 0.96)
            rad = (0.10 + 1.15 * u) if u < 0.14 else (0.255 - 0.025 * u)
        else:
            u = (t - 0.72) / 0.28
            # Exact C1-continuous Bezier sweep from p_join boldly forward & up across the lintel crest!
            p0 = p_join
            p1 = Vector((pier_x - side_sgn * 0.44, lintel_y + 0.48, -0.72))
            p2 = Vector((side_sgn * 0.86,          lintel_y + 0.56, -0.74))
            p3 = Vector((side_sgn * 0.52,          lintel_y + 0.34, -0.70))
            omt = 1.0 - u
            p_b = (omt ** 3) * p0 + 3.0 * (omt ** 2) * u * p1 + 3.0 * omt * (u ** 2) * p2 + (u ** 3) * p3
            px, py, pz = p_b.x, p_b.y, p_b.z
            rad = 0.230 + 0.028 * sin(u * pi)
        pts.append(Vector((px, py, pz)))
        rads.append(rad)

    # Crisp 6-sided keeled dorsal-crest sea-serpent cross-section lofted smoothly along all 19 stations!
    secs = []
    scols = []
    dors_vecs = []
    for i in range(n_st + 1):
        t = i / float(n_st)
        tang = (pts[min(i + 1, n_st)] - pts[max(i - 1, 0)]).normalized()
        if t <= 0.72:
            out_hint = Vector((pts[i].x - pier_x, 0.14, pts[i].z))
        else:
            out_hint = Vector((side_sgn * 0.18, 0.76, -0.62))
        if out_hint.length < 1e-4:
            out_hint = Vector((side_sgn, 0.2, -0.8))
        out_hint.normalize()
        dors = out_hint - tang * out_hint.dot(tang)
        if dors.length < 1e-4:
            dors = Vector((0.0, 1.0, 0.0))
        dors.normalize()
        lat = tang.cross(dors).normalized()
        dors_vecs.append(dors)

        r = rads[i]
        ring = [
            pts[i] + dors * (r * 1.28),
            pts[i] + dors * (r * 0.42) + lat * (r * 0.96),
            pts[i] - dors * (r * 0.56) + lat * (r * 0.84),
            pts[i] - dors * (r * 0.92),
            pts[i] - dors * (r * 0.56) - lat * (r * 0.84),
            pts[i] + dors * (r * 0.42) - lat * (r * 0.96),
        ]
        secs.append(ring)
        scols.append(
            C_SERPENT_HI if (i % 2 == 0 and t > 0.40) else (C_SERPENT_MID if t > 0.20 else C_SERPENT_DARK)
        )

    loft(mb, secs, 'limestone_moss', C_SERPENT_MID, closed=True, caps=(True, True), mode='flat', scols=scols)

    # Bold Carved Dorsal Spine Fin-Plates + Glowing Aqua Tide-Scale Diamonds along the Coiled Body!
    for fi in (2, 4, 6, 8, 10, 12, 14, 16):
        p = pts[fi]
        d = dors_vecs[fi]
        r = rads[fi]
        tube(mb, [p + d * (r * 0.96), p + d * (r * 1.98)], [r * 0.36, 0.022], 4,
             'temple_stone', C_SERPENT_BELLY, caps=(False, True), mode='flat')
        if fi in (4, 8, 12, 15):
            cbox(mb, p + d * (r * 1.24), (0.095, 0.095, 0.095), 'skull_glow', C_AQUA_MID, 0.0, M=R('Z', 45.0))

    # Fierce Sculpted Carved Stone Sea-Serpent Head projecting proudly at the Lintel Crown!
    head_pos = pts[-1]
    yaw_deg = 24.0 * side_sgn
    in_x = -side_sgn
    with xf(mb, T(head_pos) @ R('Y', yaw_deg)):
        h_secs = [
            [Vector((-in_x * 0.18,  0.29,  0.00)), Vector((-in_x * 0.18,  0.14,  0.29)),
             Vector((-in_x * 0.18, -0.20,  0.24)), Vector((-in_x * 0.18, -0.25,  0.00)),
             Vector((-in_x * 0.18, -0.20, -0.24)), Vector((-in_x * 0.18,  0.14, -0.29))],
            [Vector(( in_x * 0.20,  0.27,  0.00)), Vector(( in_x * 0.20,  0.12,  0.24)),
             Vector(( in_x * 0.20, -0.06,  0.19)), Vector(( in_x * 0.20, -0.10,  0.00)),
             Vector(( in_x * 0.20, -0.06, -0.19)), Vector(( in_x * 0.20,  0.12, -0.24))],
            [Vector(( in_x * 0.50,  0.14,  0.00)), Vector(( in_x * 0.50,  0.06,  0.13)),
             Vector(( in_x * 0.50, -0.05,  0.11)), Vector(( in_x * 0.50, -0.07,  0.00)),
             Vector(( in_x * 0.50, -0.05, -0.11)), Vector(( in_x * 0.50,  0.06, -0.13))],
        ]
        loft(mb, h_secs, 'limestone_moss', C_SERPENT_HI, closed=True, caps=(True, True), mode='flat',
             scols=[C_SERPENT_MID, C_SERPENT_HI, C_SERPENT_BELLY])
        for bz in (-0.23, 0.23):
            cbox(mb, (in_x * 0.14, 0.23, bz), (0.34, 0.085, 0.12), 'temple_stone', C_SERPENT_BELLY, 0.0,
                 M=R('Z', -side_sgn * 12.0))
        cbox(mb, (in_x * 0.20, -0.22, 0.0), (0.46, 0.12, 0.28), 'limestone_moss', C_SERPENT_DARK, 0.0,
             M=R('Z', side_sgn * 20.0))
        for fz in (-0.11, 0.11):
            tube(mb, [(in_x * 0.38, -0.04, fz), (in_x * 0.40, -0.22, fz * 0.85)],
                 [0.044, 0.009], 4, 'skull_stone', C_SKULL_BONE, caps=(False, True), mode='flat')
            tube(mb, [(in_x * 0.24, -0.20, fz * 0.85), (in_x * 0.26, -0.06, fz * 0.80)],
                 [0.036, 0.009], 4, 'skull_stone', C_SKULL_BONE, caps=(False, True), mode='flat')
        for hz in (-0.22, 0.22):
            tube(mb, [(-in_x * 0.04, 0.22, hz), (-in_x * 0.44, 0.48, hz * 1.40), (-in_x * 0.72, 0.66, hz * 1.55)],
                 [0.090, 0.056, 0.015], 5, 'temple_stone', C_SERPENT_BELLY, caps=(False, True), mode='flat')
            tube(mb, [(-in_x * 0.08, 0.02, hz * 1.05), (-in_x * 0.46, 0.12, hz * 1.55)],
                 [0.065, 0.014], 4, 'temple_stone', C_SERPENT_HI, caps=(False, True), mode='flat')
        for ez in (-0.24, 0.24):
            with xf(mb, T(in_x * 0.15, 0.12, ez) @ R('X', 90.0)):
                lathe(mb, [(0.0, -0.04), (0.115, 0.0), (0.0, 0.085)], 5, 'skull_glow', C_AQUA_CORE, False)


def gen_ancient_serpent_tide_portal(outdir):
    """Overgrown mossy temple-stone twin-coiled sea-serpent gatehouse portal (~5.0 m W x 4.2 m D x
    5.2 m H, -3.20 m deep temple-stone plinth skirt) w/ two carved stone sea-serpent bodies
    spiraling up twin jambs to meet in a crowned lintel crest, luminous cyan-turquoise rune
    threshold arch & carved serpent-eye gems ('skull_glow' ONLY), cascading jungle vines & ferns
    (UV2), convex collider 'col_serpentportal_base', and empty 'Lantern_SerpentPortal'."""
    clear_scene()
    mb = MB('ancient_serpent_tide_portal', seed=2102)
    rng = random.Random(SEED + 2102)
    col_pts = []

    STEP1_Y  = 0.32
    DAIS_Y   = 0.62
    PIER_X   = 1.46
    LINTEL_Y = 3.74
    ARCH_Y   = 2.58
    ARCH_R   = 0.98

    # 1. Deep Mossy Temple-Stone Gatehouse Plinth Skirt plunging cleanly to y = -3.20 m (~5.0 m W x 4.2 m D)
    plinth_secs = [
        _rect_oct(0.0, -3.20, 0.0, 2.44, 2.04, 0.42),
        _rect_oct(0.0, -1.35, 0.0, 2.38, 1.98, 0.40),
        _rect_oct(0.0,  0.00, 0.0, 2.32, 1.92, 0.38),
        _rect_oct(0.0, STEP1_Y, 0.0, 2.26, 1.86, 0.36),
    ]
    _loft_horizontal_masonry(
        mb, plinth_secs, 'limestone_moss',
        [C_SANCTUM_DEEP, C_SANCTUM_DARK, C_SANCTUM_MID, C_SANCTUM_HI],
        rng, caps=(True, True), top_mat='limestone_moss', top_col=C_SANCTUM_MID,
    )

    dais_secs = [
        _rect_oct(0.0, STEP1_Y - 0.02, 0.0, 2.04, 1.56, 0.32),
        _rect_oct(0.0, DAIS_Y,         0.0, 1.96, 1.48, 0.30),
    ]
    _loft_horizontal_masonry(
        mb, dais_secs, 'temple_stone',
        [C_SANCTUM_DARK, C_SANCTUM_HI], rng, caps=(False, True),
        top_mat='temple_stone', top_col=C_SANCTUM_MID,
    )

    for yc, hx, hz in ((-3.20, 2.44, 2.04), (0.0, 2.32, 1.92), (DAIS_Y, 2.24, 1.62), (4.54, 2.04, 0.96)):
        col_pts.extend(_rect_oct(0.0, yc, 0.0, hx, hz, 0.30))

    # Ceremonial Approach Stairs on both Seaward (-Z) & Rear (+Z) faces framing the walkable portal!
    for z_sgn in (-1.0, 1.0):
        cbox(mb, (0.0, 0.16, z_sgn * 1.88), (1.76, 0.30, 0.34), 'temple_stone', C_SANCTUM_MID, 0.0)
        cbox(mb, (0.0, 0.44, z_sgn * 1.56), (1.62, 0.28, 0.34), 'temple_stone', C_SANCTUM_HI, 0.0)
        for sx in (-1.0, 1.0):
            cbox(mb, (sx * 0.98, 0.44, z_sgn * 1.66), (0.24, 0.64, 0.72), 'limestone_moss', C_SANCTUM_DARK, 0.0)
            cbox(mb, (sx * 0.98, 0.80, z_sgn * 1.46), (0.26, 0.09, 0.26), 'brass', C_VERDIGRIS_HI, 0.0)
            with xf(mb, T(sx * 0.98, 0.94, z_sgn * 1.46)):
                lathe(mb, [(0.0, -0.08), (0.09, 0.0), (0.0, 0.12)], 4, 'skull_glow', C_AQUA_MID, False)

    # 2. Twin Slimmed Battered Temple-Stone Jamb Piers (cleanly embraced by the external coiled serpents!)
    for sx in (-1.0, 1.0):
        px = sx * PIER_X
        pier_secs = [
            _rect_oct(px, DAIS_Y - 0.02, 0.0, 0.44, 0.46, 0.10),
            _rect_oct(px, 2.18,          0.0, 0.40, 0.42, 0.09),
            _rect_oct(px, LINTEL_Y,      0.0, 0.38, 0.40, 0.08),
        ]
        _loft_horizontal_masonry(
            mb, pier_secs, 'temple_stone',
            [C_SANCTUM_DARK, C_SANCTUM_MID, C_SANCTUM_HI], rng, caps=(False, True),
        )
        but_secs = [
            _rect_oct(px + sx * 0.56, STEP1_Y - 0.02, 0.0, 0.32, 0.68, 0.10),
            _rect_oct(px + sx * 0.50, 1.46,           0.0, 0.24, 0.50, 0.08),
        ]
        _loft_horizontal_masonry(
            mb, but_secs, 'limestone_moss',
            [C_SANCTUM_DEEP, C_SANCTUM_DARK], rng, caps=(False, True),
        )
        cbox(mb, (px, DAIS_Y + 0.12, 0.0), (0.96, 0.10, 1.00), 'brass', C_VERDIGRIS_HI, 0.0)
        cbox(mb, (px, LINTEL_Y - 0.14, 0.0), (0.88, 0.11, 0.92), 'brass', C_GOLD_BRIGHT, 0.0)
        cbox(mb, (px, LINTEL_Y + 0.02, 0.0), (1.02, 0.14, 1.06), 'limestone_moss', C_SANCTUM_HI, 0.0)
        cbox(mb, (px - sx * 0.42, 1.64, 0.0), (0.055, 1.84, 0.16), 'skull_glow', C_AQUA_DEEP, 0.0)
        for ry_j in (1.08, 1.64, 2.20):
            cbox(mb, (px - sx * 0.44, ry_j, 0.0), (0.075, 0.15, 0.15), 'skull_glow', C_AQUA_CORE, 0.0, M=R('X', 45.0))

    # Heavy Stepped Carved Stone Gatehouse Lintel & Cornice Eaves crowning the Twin Jambs
    cbox(mb, (0.0, LINTEL_Y + 0.06, 0.0), (4.16, 0.40, 1.08), 'temple_stone', C_SANCTUM_MID, 0.0)
    cbox(mb, (0.0, LINTEL_Y + 0.32, 0.0), (4.46, 0.20, 1.24), 'limestone_moss', C_SANCTUM_HI, 0.0)
    cbox(mb, (0.0, LINTEL_Y + 0.20, 0.0), (4.28, 0.08, 1.16), 'brass', C_VERDIGRIS_HI, 0.0)

    # 3. Luminous Cyan-Turquoise Rune Threshold Arch & Floor Tide-Gate Seal ('skull_glow' ONLY!)
    n_arch = 12
    arch_stone_pts = []
    arch_glow_pts = []
    for k in range(n_arch + 1):
        ang = pi * k / float(n_arch)
        ca, sa = cos(ang), sin(ang)
        arch_stone_pts.append(Vector((ARCH_R * 1.12 * ca, ARCH_Y + ARCH_R * 1.12 * sa, 0.0)))
        arch_glow_pts.append(Vector((ARCH_R * 0.96 * ca, ARCH_Y + ARCH_R * 0.96 * sa, 0.0)))
    tube(mb, arch_stone_pts, 0.17, 6, 'temple_stone', C_SANCTUM_HI, caps=(True, True), mode='flat')
    tube(mb, arch_glow_pts, 0.070, 6, 'skull_glow', C_AQUA_MID, caps=(True, True), mode='flat')
    for k in range(1, n_arch):
        ang = pi * k / float(n_arch)
        ca, sa = cos(ang), sin(ang)
        is_key = (k == n_arch // 2)
        gs = 0.20 if is_key else 0.11
        cbox(mb, (ARCH_R * 1.16 * ca, ARCH_Y + ARCH_R * 1.16 * sa, 0.0),
             (0.22, 0.20, 0.86), 'temple_stone', C_SANCTUM_HI, 0.0, M=R('Z', degrees(ang) - 90.0))
        for z_face in (-0.42, 0.42):
            cbox(mb, (ARCH_R * 1.14 * ca, ARCH_Y + ARCH_R * 1.14 * sa, z_face),
                 (gs, gs, 0.065), 'skull_glow', C_AQUA_CORE if is_key else C_AQUA_MID, 0.0, M=R('Z', 45.0))

    # Threshold Floor Luminous Aquatic Tide-Rune Seal ('skull_glow' + verdigris bronze ring)
    with xf(mb, T(0.0, DAIS_Y + 0.02, 0.0)):
        torus(mb, 0.86, 0.044, 12, 4, 'brass', C_VERDIGRIS_HI, False)
        torus(mb, 0.68, 0.036, 12, 4, 'skull_glow', C_AQUA_MID, False)
        cyl(mb, 0.22, -0.01, 0.03, 6, 'skull_glow', C_AQUA_CORE, False, 0.0)
        for k in range(4):
            ar = radians(k * 90.0 + 45.0)
            _add_beam(mb, (0.24 * cos(ar), 0.02, 0.24 * sin(ar)),
                      (0.68 * cos(ar), 0.02, 0.68 * sin(ar)), 0.055, 0.035, 'skull_glow', C_AQUA_MID, 0.0)

    # 4. Twin-Coiled Carved Stone Sea-Serpents Spiraling Cleanly Up Both Jambs to Meet in a Crowned Lintel Crest!
    _build_coiled_stone_serpent(mb, -1.0, -PIER_X, DAIS_Y, LINTEL_Y, rng)
    _build_coiled_stone_serpent(mb,  1.0,  PIER_X, DAIS_Y, LINTEL_Y, rng)

    # Open Crowned Lintel Diadem Arch & Hovering Luminous Tide-Portal Crystal (peaking cleanly at y = 5.20 m!)
    CREST_Y = LINTEL_Y + 0.36
    with xf(mb, T(0.0, CREST_Y, 0.0)):
        cbox(mb, (0.0, 0.06, 0.0), (1.72, 0.16, 0.72), 'temple_stone', C_SANCTUM_HI, 0.0)
        with xf(mb, T(0.0, 0.40, 0.0) @ M_Y2Z):
            torus(mb, 0.44, 0.048, 12, 5, 'brass', C_GOLD_BRIGHT, False)
            torus(mb, 0.35, 0.030, 12, 4, 'brass', C_VERDIGRIS_HI, False)
        for fang_deg, flen in ((-58.0, 0.40), (-29.0, 0.48), (0.0, 0.58), (29.0, 0.48), (58.0, 0.40)):
            ar = radians(fang_deg)
            p_b = Vector((0.40 * sin(ar), 0.40 + 0.40 * cos(ar), 0.0))
            p_t = Vector(((0.40 + flen * 0.50) * sin(ar), 0.40 + (0.40 + flen * 0.50) * cos(ar), 0.0))
            tube(mb, [p_b, p_t], [0.064, 0.014], 4, 'brass', C_GOLD_BRIGHT if fang_deg == 0.0 else C_VERDIGRIS_HI,
                 caps=(False, True), mode='flat')
        with xf(mb, T(0.0, 0.40, 0.0)):
            lathe(mb, [(0.0, -0.25), (0.17, 0.0), (0.0, 0.27)], 6, 'skull_glow', C_AQUA_CORE, False)
        for sx in (-1.0, 1.0):
            r_pts = [
                Vector((sx * 1.42, -0.10, 0.56)),
                Vector((sx * 0.96,  0.22, 0.62)),
                Vector((sx * 0.46,  0.14, 0.56)),
            ]
            tube(mb, r_pts, [0.16, 0.14, 0.08], 5, 'limestone_moss', C_SERPENT_HI, caps=(True, True), mode='flat')
            cbox(mb, (sx * 0.94, 0.24, 0.72), (0.12, 0.12, 0.08), 'skull_glow', C_AQUA_MID, 0.0, M=R('Z', 45.0))

    # 5. Cascading Jungle Vines, Mossy Stone Turf Cushions & Lush Tropical Ferns ('foliage' + UV2!)
    vine_specs = [
        ((-1.98, LINTEL_Y + 0.28, -0.58), 1.96, 0.16, (-0.35, 0.0, -0.94), 0.12),
        (( 1.98, LINTEL_Y + 0.28, -0.58), 1.88, 0.16, ( 0.35, 0.0, -0.94), 0.37),
        ((-2.02, LINTEL_Y + 0.26,  0.58), 2.02, 0.16, (-0.35, 0.0,  0.94), 0.62),
        (( 2.02, LINTEL_Y + 0.26,  0.58), 1.90, 0.16, ( 0.35, 0.0,  0.94), 0.84),
        ((-1.02, LINTEL_Y + 0.24, -0.60), 1.18, 0.14, ( 0.00, 0.0, -1.00), 0.24),
        (( 1.02, LINTEL_Y + 0.24,  0.60), 1.28, 0.14, ( 0.00, 0.0,  1.00), 0.74),
    ]
    for v_pos, v_len, v_wid, v_dir, v_ph in vine_specs:
        _add_leafy_vine_drape(mb, v_pos, v_len, v_wid, v_dir, rng, phase=v_ph)

    for mpos, mrad in (
        ((-1.96, 1.54,  0.00), (0.30, 0.14, 0.44)),
        (( 1.96, 1.54,  0.00), (0.30, 0.14, 0.44)),
        ((-1.72, LINTEL_Y + 0.44, -0.26), (0.42, 0.14, 0.32)),
        (( 1.72, LINTEL_Y + 0.44,  0.26), (0.42, 0.14, 0.32)),
    ):
        _build_mossy_tuft(mb, mpos, mrad, rng)

    # 6 Grounded Lush Tropical Fern Rosettes tucked neatly within ~5.1 m W (stairs 100% clear!)
    for fpos, fsc, flean, fph in (
        ((-1.86, STEP1_Y + 0.02, -1.34), 0.68, (-0.7, 0.0, -0.7), 0.10),
        (( 1.86, STEP1_Y + 0.02, -1.34), 0.66, ( 0.7, 0.0, -0.7), 0.30),
        ((-1.86, STEP1_Y + 0.02,  1.34), 0.68, (-0.7, 0.0,  0.7), 0.50),
        (( 1.86, STEP1_Y + 0.02,  1.34), 0.66, ( 0.7, 0.0,  0.7), 0.70),
        ((-1.98, STEP1_Y + 0.02,  0.00), 0.56, (-1.0, 0.0,  0.0), 0.85),
        (( 1.98, STEP1_Y + 0.02,  0.00), 0.56, ( 1.0, 0.0,  0.0), 0.96),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=4, rng=rng, phase=fph, lean_dir=flean, segs=2)

    LANTERN_POS = Vector((0.0, 2.94, 0.0))

    build(mb)

    add_empty('Lantern_SerpentPortal', LANTERN_POS)
    col_piece('col_serpentportal_base', col_pts)
    export_landmark_glb(outdir, 'ancient_serpent_tide_portal.glb')


# ==============================================================================
# 3. COASTAL CASTAWAY RAFT SHELTER (coastal_castaway_raft_shelter.glb)
# ==============================================================================

def _build_message_bottle(mb, center, rot_deg=(0.0, 0.0, 0.0), scale=1.0):
    """Chunky sea-green shipwreck message-bottle (non-emissive sea-glass!) with cream scroll & cork."""
    s = scale
    prof = [
        (0.0,        0.00 * s),
        (0.068 * s,  0.00 * s),
        (0.072 * s,  0.17 * s),
        (0.032 * s,  0.23 * s),
        (0.030 * s,  0.30 * s),
        (0.040 * s,  0.32 * s),
        (0.024 * s,  0.32 * s),
        (0.0,        0.30 * s),
    ]
    with xf(mb, T(center) @ R('Y', rot_deg[1]) @ R('X', rot_deg[0]) @ R('Z', rot_deg[2])):
        # Glossy non-emissive sea-glass bottle ('brass' tinted sea-green for subtle glass sheen, ZERO glow!)
        lathe(mb, prof, 6, 'brass', C_SEA_GLASS, False, False,
              lambda i, k: C_CREAM_SAIL if i == 2 else (C_SEA_GLASS_DARK if i in (0, 5) else C_SEA_GLASS))
        cyl(mb, 0.028 * s, 0.29 * s, 0.36 * s, 5, 'timber', C_OAK_SUN, False, 0.0, 0.032 * s)


def _build_broken_ship_wheel(mb, M_wheel, radius=0.46):
    """Salvaged half-shattered wooden galleon ship's helm wheel leaning against the castaway boulders."""
    with xf(mb, M_wheel):
        with xf(mb, M_Y2Z):
            torus(mb, radius, 0.044, 8, 4, 'timber', C_OAK_RICH, False)
            cyl(mb, 0.11, -0.07, 0.07, 6, 'timber', C_OAK_DEEP, False, 0.0)
            cyl(mb, 0.06, -0.09, 0.09, 6, 'brass', C_BRASS_WARM, False, 0.0)
        for k in range(6):
            ang = radians(k * 60.0 + 18.0)
            ca, sa = cos(ang), sin(ang)
            s_len = radius + (0.14 if k != 2 else -0.08)  # 1 broken spoke for castaway charm!
            _add_beam(mb, (0.08 * ca, 0.08 * sa, 0.0), (s_len * ca, s_len * sa, 0.0),
                      0.038, 0.038, 'timber', C_DRIFT_PALE if k % 2 == 0 else C_OAK_SUN, 0.0)


def _build_lashed_rescue_raft(mb, M_raft, rng):
    """Hand-lashed castaway driftwood log rescue raft with twin coopered flotation barrels,
    wooden steering paddle, lashed cross-battens, spare jurymast spar & launch painter rope."""
    with xf(mb, M_raft):
        n_logs = 6
        for li in range(n_logs):
            lx = -0.58 + li * (1.16 / float(n_logs - 1))
            lr = 0.098 + 0.012 * ((li % 2) * 2 - 1)
            ll = 1.94 - 0.14 * abs(li - 2.5) / 2.5
            lcol = C_DRIFT_PALE if li % 3 == 0 else (C_DRIFT_MID if li % 3 == 1 else C_OAK_RICH)
            with xf(mb, T(lx, lr, 0.0) @ M_Y2Z):
                cyl(mb, lr, -ll * 0.5, ll * 0.5, 6, 'timber', lcol, False, 0.0, lr * 0.88)
        for bz in (-0.64, 0.0, 0.64):
            cbox(mb, (0.0, 0.22, bz), (1.36, 0.085, 0.11), 'timber', C_OAK_DEEP, 0.0)
            for lx_r in (-0.54, 0.0, 0.54):
                with xf(mb, T(lx_r, 0.16, bz) @ M_Y2X):
                    torus(mb, 0.115, 0.026, 5, 4, 'rope', C_HEMP_HI, True)
        cbox(mb, (0.0, 0.28, 0.0), (0.86, 0.055, 1.04), 'timber', C_OAK_SUN, 0.0)
        cbox(mb, (0.0, 0.34, -0.06), (0.28, 0.12, 0.28), 'timber', C_OAK_DEEP, 0.0)
        # Twin Coopered Oak Flotation Barrels Lashed Tightly onto Port & Starboard Raft Flanks!
        for sx in (-1.0, 1.0):
            _build_coopered_barrel(
                mb, T(sx * 0.80, 0.22, 0.04) @ M_Y2Z @ R('Y', sx * 8.0),
                radius=0.22, height=0.62, rng=rng,
                col_a=C_OAK_RICH, col_b=C_OAK_DEEP, col_head=C_DRIFT_MID, segs=7,
            )
            for bzr in (-0.16, 0.24):
                with xf(mb, T(sx * 0.80, 0.22, bzr) @ M_Y2Z):
                    torus(mb, 0.235, 0.028, 6, 4, 'rope', C_HEMP_HI, True)
        # Hand-Carved Wooden Castaway Steering Paddle Resting Diagonally Across the Raft!
        p_grip = Vector((-0.44, 0.40, -0.78))
        p_mid  = Vector(( 0.26, 0.36,  0.46))
        _add_beam(mb, p_grip, p_mid, 0.046, 0.046, 'timber', C_OAK_SUN, 0.0)
        blade_dir = (p_mid - p_grip).normalized()
        blade_c = p_mid + blade_dir * 0.28
        rot_b = Vector((0.0, 0.0, 1.0)).rotation_difference(blade_dir).to_matrix().to_4x4()
        cbox(mb, blade_c, (0.24, 0.032, 0.56), 'paint', C_CREAM_AGED, 0.0, M=rot_b)
        cbox(mb, blade_c + blade_dir * 0.08, (0.25, 0.038, 0.11), 'paint', C_CRIMSON_HI, 0.0, M=rot_b)
        # Rolled spare canvas raft-sail tied along port deck side + coiled bow launch painter rope!
        with xf(mb, T(-0.34, 0.38, 0.14) @ R('Y', 4.0) @ M_Y2Z):
            cyl(mb, 0.095, -0.44, 0.44, 6, 'paint', C_CREAM_SAIL, False, 0.0)
            cyl(mb, 0.104, -0.24, -0.18, 6, 'rope', C_HEMP_MID, False, 0.0)
            cyl(mb, 0.104,  0.18,  0.24, 6, 'rope', C_HEMP_MID, False, 0.0)
        _build_rope_coil(mb, (-0.12, 0.31, -0.54), radius=0.16, turns=2, r=0.030, segs=6, psegs=4,
                         col_a=C_HEMP_HI, col_b=C_HEMP_MID)


def gen_coastal_castaway_raft_shelter(outdir):
    """Atmospheric shipwrecked castaway driftwood lean-to camp & lashed-log rescue raft
    (~5.5 m W x 4.2 m D x 3.5 m H, -2.80 m deep weathered coastal sandstone sandbar skirt)
    w/ salvaged bleached spar frame, tattered patched sun-sail lean-to roof (UV2), lashed timber
    rescue raft w/ paddle & barrel floats, signal campfire ring & glowing embers ('glass' warm
    amber — ZERO skull_glow!), message-bottle crate, tattered SOS signal pennant (UV2), convex
    collider 'col_castawaycamp_base', and empty 'Lantern_CastawayCamp'."""
    clear_scene()
    mb = MB('coastal_castaway_raft_shelter', seed=2103)
    rng = random.Random(SEED + 2103)
    col_pts = []

    GROUND_Y = 0.38

    # 1. Deep Weathered Coastal Sandstone & Beach-Shelf Mound Skirt plunging cleanly to y = -2.80 m (~5.5 m W x 4.2 m D)
    def _beach_ring(y, rx, rz, jitter_s):
        pts_r = []
        sides = 10
        for k in range(sides):
            ang = 2.0 * pi * k / float(sides) + 0.15
            wob = 1.0 + jitter_s * (0.55 * sin(ang * 3.0 + 0.8) + 0.45 * cos(ang * 2.0 - 0.5))
            pts_r.append((rx * wob * cos(ang), y, rz * wob * sin(ang)))
        return pts_r

    mound_secs = [
        _beach_ring(-2.80, 2.72, 2.06, 0.05),
        _beach_ring(-1.15, 2.66, 2.00, 0.06),
        _beach_ring( 0.00, 2.58, 1.94, 0.06),
        _beach_ring(GROUND_Y, 2.46, 1.84, 0.05),
    ]
    _loft_horizontal_masonry(
        mb, mound_secs, 'limestone',
        [C_SANDSTONE_DEEP, C_SANDSTONE_DARK, C_SANDSTONE_MID, C_SANDSTONE_HI],
        rng, caps=(True, True), top_mat='limestone', top_col=C_SANDSTONE_HI,
    )

    for yc, rx, rz in ((-2.80, 2.72, 2.06), (0.0, 2.58, 1.94), (GROUND_Y, 2.46, 1.84), (2.78, 2.10, 1.46)):
        col_pts.extend(_beach_ring(yc, rx, rz, 0.04))

    # Rugged Coastal Limestone Outcrop Boulders anchoring the Rear & Flanks of the Castaway Knoll
    for bpos, brad, brot in (
        ((-2.00, GROUND_Y + 0.10,  1.22), (0.50, 0.36, 0.44), (6, 22, -8)),
        (( 2.06, GROUND_Y + 0.08,  1.18), (0.46, 0.32, 0.40), (-5, -34, 6)),
        ((-2.14, GROUND_Y + 0.05, -0.84), (0.38, 0.25, 0.34), (4, 48, -4)),
        (( 0.64, GROUND_Y + 0.04,  1.44), (0.36, 0.22, 0.30), (-4, 15, 5)),
    ):
        sculpt_rock_mass(
            mb, bpos, brad, 'limestone', C_SANDSTONE_HI, C_SANDSTONE_MID, C_SANDSTONE_DARK,
            rng, subdiv=1, warp=0.22, strata=0.14, rot_deg=brot, crag_ribs=4, rib_amp=0.10,
        )

    # 2. Salvaged Bleached Driftwood Spar Lean-To Frame (Port-Rear Quadrant)
    L_FL = Vector((-1.92, GROUND_Y, -0.22))
    L_FR = Vector(( 0.22, GROUND_Y, -0.44))
    L_BL = Vector((-1.78, GROUND_Y,  1.32))
    L_BR = Vector(( 0.34, GROUND_Y,  1.16))

    T_FL = Vector((-1.86, 2.44, -0.18))
    T_FR = Vector(( 0.18, 2.32, -0.38))
    T_BL = Vector((-1.74, 1.04,  1.28))
    T_BR = Vector(( 0.30, 1.00,  1.12))

    for bp, tp, r0, r1, col_s in (
        (L_FL, T_FL + Vector((0.02, 0.18, 0.0)), 0.11, 0.082, C_DRIFT_PALE),
        (L_FR, T_FR + Vector((-0.02, 0.16, 0.0)), 0.105, 0.078, C_DRIFT_MID),
        (L_BL, T_BL + Vector((0.0, 0.14, 0.0)), 0.095, 0.074, C_DRIFT_DARK),
        (L_BR, T_BR + Vector((0.0, 0.14, 0.0)), 0.095, 0.074, C_DRIFT_MID),
    ):
        tube(mb, [bp + Vector((0, -0.10, 0)), bp.lerp(tp, 0.5) + Vector((0.03, 0, -0.02)), tp],
             [r0, 0.5 * (r0 + r1), r1], 6, 'timber', col_s, caps=(False, True), mode='flat')

    # Front ridge boom spar, rear eave spar & 4 sloped driftwood roof rafters seated cleanly BELOW the canvas!
    ridge_a = T_FL + (T_FL - T_FR).normalized() * 0.34
    ridge_b = T_FR + (T_FR - T_FL).normalized() * 0.30
    eave_a  = T_BL + (T_BL - T_BR).normalized() * 0.26
    eave_b  = T_BR + (T_BR - T_BL).normalized() * 0.26
    tube(mb, [ridge_a, ridge_b], [0.074, 0.068], 6, 'timber', C_DRIFT_PALE, caps=(True, True), mode='flat')
    tube(mb, [eave_a, eave_b], [0.066, 0.062], 6, 'timber', C_DRIFT_MID, caps=(True, True), mode='flat')

    for k in range(4):
        u = k / 3.0
        ra = T_FL.lerp(T_FR, u) + Vector((0.0, -0.03, 0.0))
        rb = T_BL.lerp(T_BR, u) + Vector((0.0, -0.03, 0.0))
        _add_beam(mb, ra + (ra - rb).normalized() * 0.14, rb + (rb - ra).normalized() * 0.14,
                  0.072, 0.072, 'timber', C_OAK_RICH if k % 2 == 0 else C_DRIFT_MID, 0.0)

    _add_beam(mb, L_FL + Vector((0, 0.72, 0)), T_BL, 0.075, 0.075, 'timber', C_DRIFT_DARK, 0.0)
    _add_beam(mb, L_FR + Vector((0, 0.66, 0)), T_BR, 0.075, 0.075, 'timber', C_OAK_DEEP, 0.0)
    for wp_i, wy in enumerate((GROUND_Y + 0.22, GROUND_Y + 0.44, GROUND_Y + 0.66)):
        pa = Vector((-1.74, wy, 1.28))
        pb = Vector(( 0.30, wy - 0.03 * wp_i, 1.12))
        _add_beam(mb, pa, pb, 0.14, 0.045, 'timber',
                  C_DRIFT_PALE if wp_i == 1 else (C_OAK_RICH if wp_i == 0 else C_DRIFT_MID), 0.0)

    for jp in (T_FL, T_FR, T_BL, T_BR):
        with xf(mb, T(jp) @ R('X', 38.0)):
            torus(mb, 0.120, 0.030, 5, 4, 'rope', C_HEMP_HI, True)

    # 3. Tattered Patched Sun-Sail Lean-To Roof ('paint' + UV2!) lifted cleanly ABOVE the rafters (ZERO clipping!)
    nu_r, nv_r = 6, 5
    roof_pts, roof_uv2 = [], []
    for iu in range(nu_r + 1):
        u = iu / float(nu_r)
        p_top = ridge_a.lerp(ridge_b, 0.06 + 0.88 * u) + Vector((0.0, 0.12, 0.0))
        p_bot = eave_a.lerp(eave_b, 0.06 + 0.88 * u) + Vector((0.0, 0.12, 0.0))
        col_p, col_u2 = [], []
        for iv in range(nv_r + 1):
            v = iv / float(nv_r)
            if v == 0.0:
                fwd = (p_top - p_bot).normalized()
                tatter = 0.08 * sin(u * 5.0 * pi)
                p = p_top + fwd * 0.24 + Vector((0.0, -0.22 - abs(tatter), 0.0))
                w_u2 = 0.48
            elif v == 1.0:
                aft = (p_bot - p_top).normalized()
                tatter = 0.08 * cos(u * 4.0 * pi)
                p = p_bot + aft * 0.22 + Vector((0.0, -0.28 - abs(tatter), 0.0))
                w_u2 = 0.44
            else:
                s = (v - 0.15) / 0.70
                s = max(0.0, min(1.0, s))
                # Gentle catenary sag cleanly above rafters!
                sag = sin(s * pi) * (0.042 + 0.025 * sin(u * 3.0 * pi))
                p = p_top.lerp(p_bot, s) + Vector((0.0, -sag, 0.0))
                w_u2 = sin(s * pi) * 0.22
            col_p.append(p)
            col_u2.append((w_u2, (0.22 + 0.28 * u) % 1.0))
        roof_pts.append(col_p)
        roof_uv2.append(col_u2)

    def _lean_to_patch_col(iu, iv):
        if (iu, iv) in ((1, 2), (4, 1), (4, 2)):
            return C_CRIMSON_MID
        if (iu, iv) in ((2, 3), (0, 1)):
            return C_TEAL_MID
        if iv in (0, 4) and iu % 2 == 1:
            return C_CREAM_SHADE
        return C_CREAM_SAIL if (iu + iv) % 2 == 0 else C_CREAM_AGED

    _emit_double_sided_canvas_grid(mb, roof_pts, roof_uv2, _lean_to_patch_col, thick=0.018, mat='paint', back_shade=0.80)

    # Sheltered Driftwood Bed-Pallet, Canvas Bedroll, Salvaged Chest & Leaning Broken Ship's Helm Wheel!
    cbox(mb, (-0.86, GROUND_Y + 0.10, 0.62), (1.36, 0.12, 0.72), 'timber', C_DRIFT_DARK, 0.0, M=R('Y', 5.0))
    cbox(mb, (-0.84, GROUND_Y + 0.19, 0.62), (1.22, 0.08, 0.60), 'paint', C_CREAM_AGED, 0.0, M=R('Y', 5.0))
    with xf(mb, T(-1.38, GROUND_Y + 0.28, 0.68) @ R('Y', 95.0) @ M_Y2X):
        cyl(mb, 0.12, -0.26, 0.26, 6, 'paint', C_CRIMSON_MID, False, 0.0)
    cbox(mb, (-0.08, GROUND_Y + 0.22, 0.56), (0.56, 0.36, 0.38), 'timber', C_OAK_RICH, 0.0, M=R('Y', -16.0))
    cbox(mb, (-0.08, GROUND_Y + 0.39, 0.56), (0.59, 0.07, 0.41), 'iron', C_IRON_RUST_HI, 0.0, M=R('Y', -16.0))
    # Broken salvaged ship's helm wheel leaning proudly against the rear shelter wall (+Z craft!)
    _build_broken_ship_wheel(mb, T(-0.98, GROUND_Y + 0.50, 1.46) @ R('Y', -14.0) @ R('X', -18.0), radius=0.44)
    # Warm salvaged hurricane storm lantern hung beneath the front-starboard lean-to spar ('glass' amber!)
    _build_storm_lantern(mb, (0.28, 1.94, -0.44), scale=0.72, brass_cage=True, hanging=True)
    _add_beam(mb, (0.28, 2.34, -0.44), (0.28, 2.16, -0.44), 0.022, 0.022, 'iron', C_IRON_FORGED, 0.0)

    # 4. Lashed-Log Rescue Raft w/ Paddle & Barrel Floats (Starboard Side: x = +1.34, z = +0.02!)
    for rz_sk in (-0.54, 0.54):
        with xf(mb, T(1.34, GROUND_Y + 0.06, rz_sk) @ R('Y', -14.0) @ M_Y2X):
            cyl(mb, 0.075, -0.82, 0.82, 5, 'timber', C_DRIFT_DARK, False, 0.0)
    M_RAFT = T(1.36, GROUND_Y + 0.12, 0.04) @ R('Y', -14.0) @ R('Z', -4.0)
    _build_lashed_rescue_raft(mb, M_RAFT, rng)

    # 5. Signal Campfire Ring, Charred Logs, Glowing Embers ('glass' warm amber — ZERO skull_glow!) & Stew Tripod!
    FIRE_X, FIRE_Z = -1.04, -1.04
    with xf(mb, T(FIRE_X, GROUND_Y, FIRE_Z)):
        for k in range(8):
            ang = radians(k * 45.0 + 12.0)
            cbox(mb, (0.47 * cos(ang), 0.10, 0.47 * sin(ang)),
                 (0.24, 0.18 + 0.04 * (k % 2), 0.20), 'limestone',
                 C_COBBLE_DARK if k % 2 == 0 else C_SANDSTONE_DARK, 0.0, M=R('Y', -k * 45.0))
        for l_ang in (15.0, 75.0, 135.0):
            with xf(mb, T(0.0, 0.14, 0.0) @ R('Y', l_ang) @ R('Z', 16.0) @ M_Y2X):
                cyl(mb, 0.064, -0.46, 0.46, 5, 'timber', C_OAK_CHAR, False, 0.0)
        # Rich Fiery Crimson-Orange-Amber Campfire Ember Bed & S-Curved Flame Tongues ('glass' ONLY!)
        lathe(mb, [(0.0, 0.06), (0.35, 0.09), (0.27, 0.19), (0.14, 0.25), (0.0, 0.28)],
              6, 'glass', C_FLAME_DEEP, False, False,
              lambda i, k: C_FLAME_CORE if i >= 3 else (C_FLAME_MID if i == 2 else C_MAGMA_CRIMSON))
        for fx_f, fz_f, fh_f, fr_f in (
            ( 0.00,  0.00, 0.44, 0.12),
            (-0.14, -0.10, 0.32, 0.085),
            ( 0.14,  0.08, 0.30, 0.085),
        ):
            tube(mb, [(fx_f, 0.14, fz_f), (fx_f * 0.55, 0.14 + fh_f * 0.55, fz_f * 0.55),
                      (fx_f * 0.2 + 0.04, 0.14 + fh_f, fz_f * 0.2)],
                 [fr_f, fr_f * 0.50, 0.015], 4, 'glass', C_FLAME_MID,
                 caps=(False, True), mode='flat', scols=[C_MAGMA_CRIMSON, C_FLAME_DEEP, C_FLAME_CORE])
        apex_t = Vector((0.0, 1.06, 0.0))
        for k in range(3):
            ang = radians(35.0 + k * 120.0)
            _add_beam(mb, (0.58 * cos(ang), -0.02, 0.58 * sin(ang)), apex_t + Vector((0.0, 0.10, 0.0)),
                      0.044, 0.044, 'timber', C_DRIFT_MID, 0.0)
        _add_beam(mb, apex_t, (0.0, 0.72, 0.0), 0.020, 0.020, 'iron', C_IRON_FORGED, 0.0)
        lathe(mb, [(0.0, 0.50), (0.14, 0.52), (0.17, 0.64), (0.13, 0.72), (0.0, 0.70)],
              6, 'iron', C_IRON_DARK, False, False)

    # Driftwood Camp Log Bench + Salvaged Brass Spyglass & Firewood Stack beside the Campfire!
    with xf(mb, T(-1.60, GROUND_Y + 0.13, -1.24) @ R('Y', -36.0) @ M_Y2X):
        cyl(mb, 0.125, -0.38, 0.38, 6, 'timber', C_DRIFT_MID, False, 0.0, 0.112)
    with xf(mb, T(-1.54, GROUND_Y + 0.27, -1.20) @ R('Y', 18.0) @ M_Y2X):
        cyl(mb, 0.036, -0.14, 0.14, 6, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.026)

    # 6. Message-Bottle Crate & Corked Sea-Glass Message-Bottles (Front-Center Apron: x = 0.04, z = -1.24!)
    CRATE_X, CRATE_Z = 0.04, -1.24
    with xf(mb, T(CRATE_X, GROUND_Y, CRATE_Z) @ R('Y', 14.0)):
        cbox(mb, (0.0, 0.24, 0.0), (0.64, 0.46, 0.48), 'timber', C_OAK_RICH, 0.0)
        for sx in (-0.28, 0.28):
            cbox(mb, (sx, 0.24, 0.0), (0.09, 0.48, 0.51), 'timber', C_DRIFT_PALE, 0.0)
        cbox(mb, (0.0, 0.24, 0.0), (0.66, 0.07, 0.50), 'iron', C_IRON_RUST_HI, 0.0)
        _build_message_bottle(mb, (-0.15, 0.47, -0.06), rot_deg=(0.0, 12.0, 0.0), scale=1.08)
        _build_message_bottle(mb, ( 0.04, 0.47,  0.08), rot_deg=(0.0, -28.0, 0.0), scale=0.96)
        _build_message_bottle(mb, ( 0.16, 0.54, -0.08), rot_deg=(88.0, 32.0, 14.0), scale=1.00)
        with xf(mb, T(-0.08, 0.51, -0.16) @ R('Y', -24.0) @ M_Y2X):
            cyl(mb, 0.030, -0.11, 0.11, 5, 'paint', C_CREAM_SAIL, False, 0.0)

    # 7. Tall Salvaged Bleached Signal Mast & Tattered Crimson-Cream SOS Signal Pennant ('paint' + UV2!)
    SIG_X, SIG_Z = -1.88, -0.20
    tube(mb, [(SIG_X, 2.34, SIG_Z), (SIG_X - 0.06, 2.94, SIG_Z - 0.02), (SIG_X - 0.10, 3.48, SIG_Z - 0.04)],
         [0.078, 0.062, 0.042], 6, 'timber', C_DRIFT_PALE, caps=(False, True), mode='flat')
    _add_beam(mb, (SIG_X - 0.48, 3.16, SIG_Z - 0.04), (SIG_X + 0.34, 3.24, SIG_Z - 0.02),
              0.048, 0.048, 'timber', C_DRIFT_MID, 0.0)
    with xf(mb, T(SIG_X - 0.08, 3.20, SIG_Z - 0.03) @ M_Y2Z):
        torus(mb, 0.082, 0.024, 5, 4, 'rope', C_HEMP_HI, True)
    _build_wind_banner(
        mb, root_pos=(SIG_X - 0.04, 3.22, SIG_Z - 0.02), length=1.46, h0=0.44,
        out_dir=(0.88, -0.05, -0.48),
        col_main=C_CRIMSON_HI, col_alt=C_CREAM_SAIL, col_trim=C_CRIMSON_DARK,
        phase=0.44, swallowtail=False, tattered=True,
    )
    tube(mb, [(SIG_X - 0.08, 3.16, SIG_Z - 0.03), (-2.24, GROUND_Y + 0.08, -1.04)],
         0.020, 4, 'rope', C_HEMP_MID, caps=(False, False), mode='flat')

    # 8. Coastal Beach Fern Rosettes ('foliage' + UV2!) tucked snugly around the castaway knoll boulders
    for fpos, fsc, flean, fph in (
        ((-2.06, GROUND_Y - 0.02, -1.04), 0.62, (-0.7, 0.0, -0.7), 0.15),
        (( 2.16, GROUND_Y - 0.02, -1.10), 0.60, ( 0.7, 0.0, -0.7), 0.38),
        ((-2.06, GROUND_Y - 0.02,  1.26), 0.64, (-0.7, 0.0,  0.7), 0.64),
        (( 2.06, GROUND_Y - 0.02,  1.26), 0.62, ( 0.7, 0.0,  0.7), 0.88),
        (( 0.24, GROUND_Y - 0.02,  1.56), 0.56, ( 0.0, 0.0,  1.0), 0.52),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=4, rng=rng, phase=fph, lean_dir=flean, segs=2)

    LANTERN_POS = Vector((FIRE_X, GROUND_Y + 0.68, FIRE_Z))

    build(mb)

    add_empty('Lantern_CastawayCamp', LANTERN_POS)
    col_piece('col_castawaycamp_base', col_pts)
    export_landmark_glb(outdir, 'coastal_castaway_raft_shelter.glb')


# ==============================================================================
# 4. VOLCANIC OBSIDIAN PHOENIX BRAZIER (volcanic_obsidian_phoenix_brazier.glb)
# ==============================================================================

def _build_obsidian_feather_blade(mb, p_root, p_tip, width, thick, face_nrm, glow_base=True, glow_both=False):
    """Broad razor-faceted angular diamond-section volcanic obsidian wing-feather blade ('basalt')
    with crisp lighter bevel highlights & optional glowing molten lava quill veins ('glass' ONLY!)."""
    a = Vector(p_root)
    b = Vector(p_tip)
    axis = b - a
    L = axis.length
    if L < 1e-4:
        return
    ax = axis.normalized()
    fn = Vector(face_nrm)
    fn = fn - ax * fn.dot(ax)
    if fn.length < 1e-4:
        fn = Vector((0.0, 0.0, -1.0))
    fn.normalize()
    lat = ax.cross(fn).normalized()

    # 4 lengthwise stations: broad overlapping vane tapering cleanly to a razor volcanic obsidian point!
    st_t = [0.00, 0.36, 0.74, 1.00]
    st_w = [width * 0.66, width * 1.00, width * 0.68, 0.018]
    st_d = [thick * 0.92, thick * 1.00, thick * 0.58, 0.014]
    secs = []
    for t, w, d in zip(st_t, st_w, st_d):
        c = a.lerp(b, t) + fn * (0.045 * sin(t * pi))
        secs.append([
            c + lat * w,
            c + fn * d,
            c - lat * w,
            c - fn * d,
        ])
    loft(mb, secs, 'basalt', C_OBSIDIAN_HI, closed=True, caps=(True, True), mode='flat',
         scols=[C_OBSIDIAN_DARK, C_OBSIDIAN_MID, C_OBSIDIAN_HI, C_OBSIDIAN_EDGE])

    if glow_base:
        # Fiery molten lava quill seam glowing along the lower feather spine ('glass' ONLY!)
        _sculpt_glow_ribbon(
            mb, [a.lerp(b, 0.06) + fn * (thick * 0.74), a.lerp(b, 0.48) + fn * (thick * 0.80)],
            [width * 0.18, width * 0.06], fn,
            hot_core=True, ridge_h=0.022, mat='glass',
            c_core=C_FLAME_MID, c_mid_col=C_FLAME_DEEP, c_edge_col=C_MAGMA_CRIMSON, c_tip_col=C_MAGMA_CRIMSON,
        )
        if glow_both:
            _sculpt_glow_ribbon(
                mb, [a.lerp(b, 0.08) - fn * (thick * 0.74), a.lerp(b, 0.44) - fn * (thick * 0.78)],
                [width * 0.16, width * 0.055], -fn,
                hot_core=False, ridge_h=0.022, mat='glass',
                c_core=C_FLAME_MID, c_mid_col=C_FLAME_DEEP, c_edge_col=C_MAGMA_CRIMSON, c_tip_col=C_MAGMA_CRIMSON,
            )


def _build_obsidian_phoenix_wing(mb, side_sgn):
    """Monumental V-flaring sweeping faceted obsidian firebird wing soaring majestically outward
    and skyward to y = 5.78 m (~4.4 m total wingspan), built from a keeled curved wing-spar +
    7 fanning primary pinion blades + 5 overlapping secondary covert blades + 3 shoulder scapular
    plates, glowing lava quill veins ('glass' ONLY), and bolted iron shoulder shackle!
    Returns (front_shackle_lug, rear_shackle_lug)."""
    # Sweeping V-flare raptor wing-arm rising outward & upward (NEVER curling inward like horns!)
    spar_pts = [
        Vector((side_sgn * 0.76, 1.54,  0.04)),
        Vector((side_sgn * 1.18, 2.28,  0.10)),
        Vector((side_sgn * 1.54, 3.16,  0.16)),
        Vector((side_sgn * 1.76, 4.10,  0.20)),
        Vector((side_sgn * 1.88, 4.96,  0.22)),
        Vector((side_sgn * 2.02, 5.66,  0.24)),
    ]
    spar_rads = [0.27, 0.23, 0.19, 0.15, 0.105, 0.028]

    secs = []
    scols = []
    for i, (pt, r) in enumerate(zip(spar_pts, spar_rads)):
        t = i / float(len(spar_pts) - 1)
        tang = (spar_pts[min(i + 1, len(spar_pts) - 1)] - spar_pts[max(i - 1, 0)]).normalized()
        fwd = Vector((0.0, 0.0, -1.0))
        fwd = (fwd - tang * fwd.dot(tang)).normalized()
        out_v = tang.cross(fwd).normalized()
        if out_v.x * side_sgn < 0:
            out_v = -out_v
        secs.append([
            pt + out_v * (r * 1.24),
            pt + fwd * (r * 0.90) + out_v * (r * 0.24),
            pt + fwd * (r * 0.58) - out_v * (r * 0.80),
            pt - fwd * (r * 0.58) - out_v * (r * 0.80),
            pt - fwd * (r * 0.90) + out_v * (r * 0.24),
        ])
        scols.append(
            C_OBSIDIAN_EDGE if t > 0.62 else (C_OBSIDIAN_HI if t > 0.28 else C_OBSIDIAN_MID)
        )
    loft(mb, secs, 'basalt', C_OBSIDIAN_HI, closed=True, caps=(True, True), mode='flat', scols=scols)

    # Glowing molten lava vein tracing along the front leading ridge of the soaring wing-arm ('glass' ONLY!)
    lava_pts = [p + Vector((0.0, 0.0, -r * 0.88)) for p, r in zip(spar_pts[:5], spar_rads[:5])]
    _sculpt_glow_ribbon(
        mb, lava_pts, [0.062, 0.056, 0.048, 0.038, 0.022], (0.0, 0.0, -1.0),
        hot_core=True, ridge_h=0.028, mat='glass',
        c_core=C_FLAME_CORE, c_mid_col=C_FLAME_MID, c_edge_col=C_FLAME_DEEP, c_tip_col=C_MAGMA_CRIMSON,
    )

    # 7 Broad Fanning Obsidian Primary Pinion Flight-Feather Blades flaring outward & skyward!
    face_nrm = Vector((-side_sgn * 0.18, 0.0, -0.98)).normalized()
    primary_specs = [
        # (root_pt, tip_pt, width, thick, glow_base, glow_both)
        (Vector((side_sgn * 1.06, 2.08, 0.14)), Vector((side_sgn * 1.98, 2.52, 0.34)), 0.21, 0.072, True,  False),
        (Vector((side_sgn * 1.28, 2.64, 0.18)), Vector((side_sgn * 2.14, 3.30, 0.40)), 0.23, 0.076, True,  True),
        (Vector((side_sgn * 1.48, 3.22, 0.22)), Vector((side_sgn * 2.20, 4.14, 0.44)), 0.24, 0.078, True,  True),
        (Vector((side_sgn * 1.64, 3.82, 0.24)), Vector((side_sgn * 2.20, 4.96, 0.42)), 0.24, 0.078, True,  True),
        (Vector((side_sgn * 1.72, 4.38, 0.24)), Vector((side_sgn * 2.14, 5.56, 0.36)), 0.22, 0.072, True,  False),
        (Vector((side_sgn * 1.74, 4.86, 0.22)), Vector((side_sgn * 1.88, 5.78, 0.28)), 0.20, 0.066, False, False),
        (Vector((side_sgn * 1.62, 5.14, 0.20)), Vector((side_sgn * 1.54, 5.64, 0.22)), 0.17, 0.058, False, False),
    ]
    for f_root, f_tip, f_w, f_d, f_glow, f_both in primary_specs:
        _build_obsidian_feather_blade(mb, f_root, f_tip, f_w, f_d, face_nrm, glow_base=f_glow, glow_both=f_both)

    # 7 Overlapping Inner Secondary Covert & Scapular Plumage Blades forming a Lush Feathered Wing Web!
    covert_specs = [
        (Vector((side_sgn * 0.96, 2.20, 0.14)), Vector((side_sgn * 1.48, 3.16, 0.28)), 0.19, 0.062),
        (Vector((side_sgn * 1.18, 2.86, 0.18)), Vector((side_sgn * 1.62, 3.92, 0.32)), 0.20, 0.064),
        (Vector((side_sgn * 1.36, 3.52, 0.20)), Vector((side_sgn * 1.66, 4.64, 0.34)), 0.20, 0.064),
        (Vector((side_sgn * 1.46, 4.12, 0.20)), Vector((side_sgn * 1.56, 5.16, 0.30)), 0.18, 0.058),
        (Vector((side_sgn * 0.88, 1.78, 0.12)), Vector((side_sgn * 1.48, 2.14, 0.28)), 0.17, 0.058),
        (Vector((side_sgn * 1.04, 2.48, 0.22)), Vector((side_sgn * 1.76, 3.04, 0.38)), 0.18, 0.060),
        (Vector((side_sgn * 1.24, 3.18, 0.24)), Vector((side_sgn * 1.90, 3.84, 0.42)), 0.18, 0.060),
    ]
    for c_root, c_tip, c_w, c_d in covert_specs:
        _build_obsidian_feather_blade(mb, c_root, c_tip, c_w, c_d, face_nrm, glow_base=False)

    # Heavy Bolted Forged-Iron Restraining Shackle Cuff clamped snugly around Lower Wing Shoulder (station 1)!
    sh_p = spar_pts[1]
    sh_t = (spar_pts[2] - spar_pts[0]).normalized()
    rot_sh = Vector((0.0, 1.0, 0.0)).rotation_difference(sh_t).to_matrix().to_4x4()
    sh_r = spar_rads[1] * 1.18
    with xf(mb, T(sh_p) @ rot_sh):
        cyl(mb, sh_r, -0.14, 0.14, 6, 'iron', C_IRON_FORGED, False, 0.0)
        torus(mb, sh_r + 0.02, 0.044, 6, 4, 'iron', C_IRON_BRIGHT, False)
    front_lug = sh_p + Vector((side_sgn * (sh_r + 0.04), -0.06, -0.14))
    rear_lug  = sh_p + Vector((side_sgn * (sh_r + 0.04), -0.06,  0.18))
    cbox(mb, front_lug, (0.19, 0.19, 0.19), 'iron', C_IRON_RUST_HI, 0.0)
    cbox(mb, rear_lug,  (0.18, 0.18, 0.18), 'iron', C_IRON_RUST_HI, 0.0)
    return front_lug, rear_lug


def _build_phoenix_crest_head(mb, center, z_sgn=-1.0):
    """Fierce carved obsidian Phoenix head-crest medallion on the altar breastplate with
    hooked eagle beak, swept obsidian crown plumes & blazing molten amber eyes ('glass' ONLY!)."""
    cx, cy, cz = center
    with xf(mb, T(cx, cy, cz)):
        with xf(mb, M_Y2Z):
            cyl(mb, 0.56, -0.09, 0.09, 6, 'basalt', C_OBSIDIAN_HI, False, 0.0, 0.48)
            torus(mb, 0.52, 0.052, 6, 4, 'iron', C_IRON_FORGED, False)
        cbox(mb, (0.0, 0.08, z_sgn * 0.17), (0.36, 0.32, 0.28), 'basalt', C_OBSIDIAN_EDGE, 0.0)
        # Hooked obsidian firebird raptor beak
        tube(mb, [(0.0, 0.08, z_sgn * 0.26), (0.0, 0.00, z_sgn * 0.50), (0.0, -0.20, z_sgn * 0.44)],
             [0.13, 0.080, 0.016], 4, 'basalt', C_OBSIDIAN_EDGE, caps=(False, True), mode='flat')
        # 3-Plume Sweeping Obsidian Phoenix Crown & Brow Feathers
        tube(mb, [(0.0, 0.20, z_sgn * 0.16), (0.0, 0.56, z_sgn * 0.12)],
             [0.085, 0.015], 4, 'basalt', C_OBSIDIAN_EDGE, caps=(False, True), mode='flat')
        for sx in (-1.0, 1.0):
            tube(mb, [(sx * 0.12, 0.18, z_sgn * 0.16), (sx * 0.40, 0.40, z_sgn * 0.14),
                      (sx * 0.60, 0.58, z_sgn * 0.08)],
                 [0.088, 0.058, 0.015], 4, 'basalt', C_OBSIDIAN_EDGE, caps=(False, True), mode='flat')
            with xf(mb, T(sx * 0.16, 0.12, z_sgn * 0.27)):
                lathe(mb, [(0.0, -0.04), (0.082, 0.0), (0.0, 0.058)], 4, 'glass', C_FLAME_CORE, False)
        cbox(mb, (0.0, -0.28, z_sgn * 0.14), (0.17, 0.17, 0.08), 'glass', C_FLAME_MID, 0.0, M=R('Z', 45.0))


def gen_volcanic_obsidian_phoenix_brazier(outdir):
    """Monumental carved dark-basalt & obsidian winged firebird beacon altar (~4.4 m W x 4.2 m D x
    5.8 m H, -3.40 m deep lava-cracked basalt foundation skirt) featuring sweeping faceted obsidian
    wings flaring dramatically upward around a roaring incandescent magma-flame chalice ('glass'
    warm molten orange-amber linear COLOR_0 — ZERO skull_glow!), iron shackles, volcanic feather-
    scale chevrons & glowing lava veins, convex collider 'col_phoenixbrazier_base', and empty
    'Lantern_PhoenixBrazier'."""
    clear_scene()
    mb = MB('volcanic_obsidian_phoenix_brazier', seed=2104)
    rng = random.Random(SEED + 2104)
    col_pts = []

    STEP1_Y = 0.44
    DAIS_Y  = 0.96
    CHAL_Y  = 2.34

    # 1. Deep Lava-Cracked Charred-Basalt Plinth Skirt plunging cleanly to y = -3.40 m (~4.4 m W x 4.2 m D)
    plinth_secs = [
        _reg_poly(0.0, -3.40, 0.0, 2.20, sides=8, rot_deg=22.5, sx=1.00, sz=0.95),
        _reg_poly(0.0, -1.50, 0.0, 2.14, sides=8, rot_deg=22.5, sx=1.00, sz=0.95),
        _reg_poly(0.0,  0.00, 0.0, 2.06, sides=8, rot_deg=22.5, sx=1.00, sz=0.95),
        _reg_poly(0.0, STEP1_Y, 0.0, 1.98, sides=8, rot_deg=22.5, sx=1.00, sz=0.95),
    ]
    _loft_horizontal_masonry(
        mb, plinth_secs, 'basalt',
        [C_OBSIDIAN_ABYSS, C_OBSIDIAN_DARK, C_OBSIDIAN_MID, C_OBSIDIAN_HI],
        rng, caps=(True, True), top_mat='basalt', top_col=C_OBSIDIAN_MID,
    )

    dais_secs = [
        _reg_poly(0.0, STEP1_Y - 0.02, 0.0, 1.66, sides=8, rot_deg=22.5, sx=1.00, sz=0.95),
        _reg_poly(0.0, DAIS_Y,         0.0, 1.54, sides=8, rot_deg=22.5, sx=1.00, sz=0.95),
    ]
    _loft_horizontal_masonry(
        mb, dais_secs, 'basalt',
        [C_OBSIDIAN_DARK, C_OBSIDIAN_HI], rng, caps=(False, True),
        top_mat='basalt', top_col=C_OBSIDIAN_MID,
    )

    for yc, rc in ((-3.40, 2.20), (0.0, 2.06), (DAIS_Y, 2.04), (5.66, 2.16)):
        col_pts.extend(_reg_poly(0.0, yc, 0.0, rc, sides=8, rot_deg=22.5, sx=1.00, sz=0.95))

    # Jagged Volcanic Stone Offering Steps on Seaward (-Z) Hero Approach
    cbox(mb, (0.0, 0.22, -2.02), (1.38, 0.42, 0.36), 'basalt', C_OBSIDIAN_MID, 0.0)
    cbox(mb, (0.0, 0.62, -1.68), (1.16, 0.36, 0.36), 'basalt', C_OBSIDIAN_HI, 0.0)

    # 6 Radiating Molten Lava Veins ('glass' ONLY!) splitting across the stepped volcanic basalt plinth!
    for c_ang in (-145.0, -90.0, -35.0, 35.0, 90.0, 145.0):
        ar = radians(c_ang)
        ca, sa = cos(ar), sin(ar)
        p0 = Vector((0.68 * ca, DAIS_Y + 0.03, 0.64 * sa))
        p1 = Vector((1.38 * ca - 0.09 * sa, DAIS_Y + 0.02, 1.30 * sa + 0.09 * ca))
        p2 = Vector((1.88 * ca, STEP1_Y + 0.03, 1.78 * sa))
        _sculpt_glow_ribbon(
            mb, [p0, p1, p2], [0.095, 0.078, 0.048], (0.0, 1.0, 0.0),
            hot_core=True, ridge_h=0.034, mat='glass',
            c_core=C_FLAME_MID, c_mid_col=C_FLAME_DEEP, c_edge_col=C_MAGMA_CRIMSON, c_tip_col=C_MAGMA_CRIMSON,
        )

    # 2. Central Carved Obsidian Firebird Altar Pedestal w/ Volcanic Feather-Scale Chevrons (y = 0.96 .. 2.34 m)
    ped_secs = [
        _rect_oct(0.0, DAIS_Y - 0.02, 0.0, 1.02, 0.94, 0.28),
        _rect_oct(0.0, 1.66,          0.0, 0.88, 0.82, 0.24),
        _rect_oct(0.0, CHAL_Y,        0.0, 1.04, 0.96, 0.28),
    ]
    _loft_horizontal_masonry(
        mb, ped_secs, 'basalt',
        [C_OBSIDIAN_DARK, C_OBSIDIAN_MID, C_OBSIDIAN_EDGE],
        rng, caps=(False, True), top_mat='basalt', top_col=C_OBSIDIAN_HI,
    )
    cbox(mb, (0.0, CHAL_Y - 0.06, 0.0), (2.10, 0.14, 1.94), 'iron', C_IRON_FORGED, 0.0)

    # Overlapping Volcanic Feather-Scale Chevrons & Glowing Lava Veins carved on Front (-Z) & Rear (+Z)!
    for z_face in (-1.0, 1.0):
        for tier_i, ty in enumerate((1.16, 1.46, 1.96)):
            tw = 0.74 - 0.08 * tier_i
            for sx in (-1.0, 1.0):
                _add_beam(mb, (0.0, ty - 0.12, z_face * 0.91),
                          (sx * tw, ty + 0.14, z_face * 0.86), 0.11, 0.10, 'basalt', C_OBSIDIAN_EDGE, 0.0)
            if tier_i in (0, 2):
                _sculpt_glow_ribbon(
                    mb, [(-tw * 0.85, ty + 0.08, z_face * 0.89), (0.0, ty - 0.14, z_face * 0.93),
                         (tw * 0.85, ty + 0.08, z_face * 0.89)],
                    [0.042, 0.058, 0.042], (0.0, 0.0, z_face),
                    hot_core=True, ridge_h=0.028, mat='glass',
                    c_core=C_FLAME_MID, c_mid_col=C_FLAME_DEEP, c_edge_col=C_MAGMA_CRIMSON, c_tip_col=C_MAGMA_CRIMSON,
                )

    # Fierce Seaward Carved Obsidian Phoenix Head-Crest Medallion (-Z) + 7-Blade Rear Tail-Plume Fan (+Z)!
    _build_phoenix_crest_head(mb, (0.0, 1.66, -0.88), z_sgn=-1.0)
    tail_nrm = Vector((0.0, 0.18, 0.98)).normalized()
    for tang_deg, tlen, t_glow in (
        (-42.0, 1.18, False), (-28.0, 1.44, True), (-14.0, 1.68, False),
        (  0.0, 1.92, True),
        ( 14.0, 1.68, False), ( 28.0, 1.44, True), ( 42.0, 1.18, False),
    ):
        ar = radians(tang_deg)
        p_r = Vector((0.28 * sin(ar), 1.44, 0.88))
        p_t = Vector((1.22 * sin(ar), 1.44 + tlen * cos(ar), 1.38))
        _build_obsidian_feather_blade(mb, p_r, p_t, 0.17, 0.062, tail_nrm, glow_base=t_glow)

    # 3. Roaring Incandescent Magma-Flame Chalice cradling the Beacon Heart (y = 2.34 .. 4.38 m, 'glass' ONLY!)
    with xf(mb, T(0.0, CHAL_Y, 0.0)):
        chal_prof = [
            (0.00, 0.00),
            (0.72, 0.00),
            (0.94, 0.28),
            (1.06, 0.66),
            (0.94, 0.78),
            (0.78, 0.58),
            (0.00, 0.50),
        ]
        lathe(mb, chal_prof, 8, 'iron', C_IRON_DARK, False, False,
              lambda i, k: C_IRON_RUST_HI if i in (2, 3) else C_IRON_FORGED)
        with xf(mb, T(0.0, 0.68, 0.0)):
            torus(mb, 1.02, 0.072, 8, 4, 'iron', C_IRON_BRIGHT, False)
        # 6 Curved Obsidian Firebird Talon-Prongs gripping & crowning the Chalice Bowl!
        for k in range(6):
            ar = radians(k * 60.0 + 30.0)
            ca, sa = cos(ar), sin(ar)
            is_obs = (k % 2 == 0)
            t_pts = [
                Vector((0.84 * ca, 0.02, 0.84 * sa)),
                Vector((1.10 * ca, 0.46, 1.10 * sa)),
                Vector((1.06 * ca, 1.04 if is_obs else 0.84, 1.06 * sa)),
            ]
            tube(mb, t_pts, [0.125, 0.092, 0.024], 4, 'basalt' if is_obs else 'iron',
                 C_OBSIDIAN_EDGE if is_obs else C_IRON_RUST_HI, caps=(False, True), mode='flat')

        # Boiling Incandescent Molten Magma Surface + Bold Dark Obsidian Lava-Crust Slag Chunks!
        lathe(mb, [(0.0, 0.50), (0.88, 0.58), (0.76, 0.74), (0.46, 0.86), (0.0, 0.92)],
              8, 'glass', C_FLAME_DEEP, False, False,
              lambda i, k: C_FLAME_CORE if i >= 4 else (C_FLAME_MID if i == 3 else (C_FLAME_DEEP if i == 2 else C_MAGMA_CRIMSON)))
        for cx_c, cz_c, rot_c in ((-0.46, -0.28, 20.0), (0.46, -0.28, -32.0), (0.04, 0.48, 52.0), (-0.18, -0.52, -14.0)):
            cbox(mb, (cx_c, 0.80, cz_c), (0.38, 0.18, 0.26), 'basalt', C_OBSIDIAN_ABYSS, 0.0,
                 M=R('Y', rot_c) @ R('X', 14.0))

        # Roaring S-Curved Sculpted Incandescent Magma-Flame Plumes erupting high between the Wings ('glass' ONLY!)
        for fx_f, fz_f, fh_f, fr_f, sw_x, sw_z in (
            ( 0.00,  0.00, 1.56, 0.30,  0.14, -0.06),
            (-0.34, -0.18, 1.08, 0.19, -0.20, -0.10),
            ( 0.34, -0.14, 1.12, 0.19,  0.20, -0.08),
            (-0.20,  0.26, 0.96, 0.17, -0.14,  0.12),
            ( 0.22,  0.24, 0.94, 0.17,  0.14,  0.10),
        ):
            fl_pts = [
                Vector((fx_f, 0.66, fz_f)),
                Vector((fx_f * 0.82 - sw_x * 0.45, 0.66 + fh_f * 0.36, fz_f * 0.82 + sw_z * 0.3)),
                Vector((fx_f * 0.56 + sw_x * 0.65, 0.66 + fh_f * 0.72, fz_f * 0.56 - sw_z * 0.4)),
                Vector((fx_f * 0.28 + sw_x * 0.25, 0.66 + fh_f,        fz_f * 0.28 + sw_z * 0.2)),
            ]
            tube(mb, fl_pts, [fr_f, fr_f * 0.68, fr_f * 0.34, 0.018], 5, 'glass', C_FLAME_MID,
                 caps=(False, True), mode='flat',
                 scols=[C_MAGMA_CRIMSON, C_FLAME_DEEP, C_FLAME_MID, C_FLAME_CORE])

        # Twin Glowing Molten Lava Overflows dripping down the front & rear chalice lips!
        for z_ov in (-1.0, 1.0):
            ov_pts = [
                Vector((0.0, 0.70, z_ov * 0.96)),
                Vector((0.0, 0.46, z_ov * 1.08)),
                Vector((0.0, 0.10, z_ov * 1.04)),
            ]
            _sculpt_glow_ribbon(
                mb, ov_pts, [0.10, 0.075, 0.048], (0.0, 0.0, z_ov),
                hot_core=True, ridge_h=0.034, mat='glass',
                c_core=C_FLAME_MID, c_mid_col=C_FLAME_DEEP, c_edge_col=C_MAGMA_CRIMSON, c_tip_col=C_MAGMA_CRIMSON,
            )

    # 4. Twin Monumental V-Flaring Faceted Obsidian Phoenix Wings + 4 Rooted Anchor Spurs & Iron Chains!
    for side_sgn in (-1.0, 1.0):
        front_lug, rear_lug = _build_obsidian_phoenix_wing(mb, side_sgn)

        for z_sp, lug_pt in ((-1.0, front_lug), (1.0, rear_lug)):
            # Rooted 100% solidly into the octagonal basalt plinth (zero floating gap!)
            spur_bp = Vector((side_sgn * 1.48, -0.25, z_sp * 0.96))
            spur_dir = Vector((side_sgn * 0.28, 1.0, z_sp * 0.24)).normalized()
            spur_pts = [spur_bp, spur_bp + spur_dir * 0.98, spur_bp + spur_dir * 1.72]
            tube(mb, spur_pts, [0.34, 0.22, 0.03], 4, 'basalt', C_OBSIDIAN_HI,
                 caps=(False, True), mode='flat',
                 scols=[C_OBSIDIAN_DARK, C_OBSIDIAN_MID, C_OBSIDIAN_EDGE])
            bot_anchor = spur_pts[1] + Vector((0.0, 0.14, 0.0))
            with xf(mb, T(bot_anchor)):
                cyl(mb, 0.25, -0.09, 0.09, 6, 'iron', C_IRON_BRIGHT, False, 0.0)
            _add_chain_links(
                mb, lug_pt + Vector((0.0, -0.04, 0.0)), bot_anchor + Vector((0.0, 0.08, 0.0)),
                n_links=4, link_r=0.17, wire_r=0.048, segs=5, psegs=4, sag=0.12,
                mat='iron', rust_stride=2, stretch_y=1.42,
                col_a=C_IRON_BRIGHT, col_b=C_IRON_RUST_HI,
            )

    LANTERN_POS = Vector((0.0, 3.16, 0.0))

    build(mb)

    add_empty('Lantern_PhoenixBrazier', LANTERN_POS)
    col_piece('col_phoenixbrazier_base', col_pts)
    export_landmark_glb(outdir, 'volcanic_obsidian_phoenix_brazier.glb')


PRIVATEER_CRAFT_GENERATORS = [
    gen_pirate_sailmaker_rigging_loft,
    gen_ancient_serpent_tide_portal,
    gen_coastal_castaway_raft_shelter,
    gen_volcanic_obsidian_phoenix_brazier,
]
