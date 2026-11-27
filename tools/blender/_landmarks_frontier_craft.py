# Sea of Scoundrels: 4 sculpted 3D Frontier Craft & Volcanic/Coral Relic Landmarks
# (Wave I-19 / Pass I-Q12 — 78-Landmark Zero-Extra-VRAM Fleet!).
# Imported by tools/blender/gen_island_landmarks.py.
# Authored in Godot game coordinates (-Z seaward/hero-facing, +Y up, +X starboard, metres)
# and converted to Blender's Z-up frame on mesh creation via _landmark_common.
# STRICT SHARED-TEXTURE DEDUP CONTRACT: uses ONLY the 11 existing shared PBR materials
# (limestone, limestone_moss, basalt, temple_stone, skull_stone, timber, paint, rope,
# iron, brass, foliage) + untextured glass / skull_glow / col.
# Emissive rule:
#   - mat_landmark_skull_glow ONLY on ancient_coral_leviathan_altar (cyan-turquoise pearl orb & aqua altar runes)
#   - mat_landmark_glass with warm amber/molten linear COLOR_0 on pirate_powder_magazine_bunker,
#     coastal_boatbuilder_slipway_winch, and volcanic_obsidian_ember_totem.
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

# Fortified harbour sandstone ashlar, limestone mortar & mossy turf
C_SANDSTONE_HI   = srgb('#ebd9b4')
C_SANDSTONE_MID  = srgb('#cca77a')
C_SANDSTONE_DARK = srgb('#907354')
C_SANDSTONE_DEEP = srgb('#5a4b3c')
C_MOSS_CUSHION   = srgb('#4b7f30')
C_MOSS_DEEP      = srgb('#2c5222')

# Coastal cobble & beach stone seawall
C_COBBLE_HI      = srgb('#cfc3ac')
C_COBBLE_MID     = srgb('#938876')
C_COBBLE_DARK    = srgb('#5c554c')
C_COBBLE_WET     = srgb('#403f3a')

# Shipwright & bunker timbers
C_OAK_SUN        = srgb('#c2884b')
C_OAK_RICH       = srgb('#85542c')
C_OAK_DEEP       = srgb('#4f301a')
C_OAK_CHAR       = srgb('#362318')
C_DRIFT_PALE     = srgb('#d6c7ad')
C_DRIFT_MID      = srgb('#9b8a71')
C_DRIFT_DARK     = srgb('#635645')
C_PITCH_TAR      = srgb('#19171b')

# Bold pirate & shipyard paints
C_CRIMSON_HI     = srgb('#d42d20')
C_CRIMSON_MID    = srgb('#981e16')
C_CRIMSON_DARK   = srgb('#5d120e')
C_TEAL_HI        = srgb('#23858a')
C_TEAL_MID       = srgb('#1a6166')
C_TEAL_DARK      = srgb('#123e42')
C_CREAM_SAIL     = srgb('#f2e4c6')
C_CREAM_AGED     = srgb('#cbb68e')

# Ancient reef temple stone & fossil coral tones
C_REEF_STONE_HI  = srgb('#d8cfb8')
C_REEF_STONE_MID = srgb('#9f9884')
C_REEF_STONE_DK  = srgb('#656254')
C_REEF_STONE_SK  = srgb('#44443b')
C_CORAL_IVORY    = srgb('#ede2cc')
C_CORAL_BLUSH    = srgb('#d9a38c')
C_CORAL_ROSE     = srgb('#c47c6a')
C_CORAL_SHADE    = srgb('#8e6456')

# Metals: burnished brass, verdigris bronze, forged & rusted iron
C_GOLD_BRIGHT    = srgb('#f9d14f')
C_BRASS_WARM     = srgb('#dba43a')
C_BRASS_DARK     = srgb('#8e6320')
C_VERDIGRIS_HI   = srgb('#58bca4')
C_VERDIGRIS_MID  = srgb('#328975')
C_IRON_BRIGHT    = srgb('#7e8798')
C_IRON_FORGED    = srgb('#4c5261')
C_IRON_DARK      = srgb('#262933')
C_IRON_RUST_HI   = srgb('#b26034')
C_IRON_RUST_MID  = srgb('#7d4123')

# Volcanic obsidian & columnar basalt (high-contrast carved edges vs abyssal crevices)
C_OBSIDIAN_EDGE  = srgb('#958ca3')
C_OBSIDIAN_HI    = srgb('#686075')
C_OBSIDIAN_MID   = srgb('#423c4c')
C_OBSIDIAN_DARK  = srgb('#272330')
C_OBSIDIAN_ABYSS = srgb('#15131b')

# Mystical cyan-turquoise pearl & rune glow (USED ONLY with 'skull_glow' on ancient_coral_leviathan_altar!)
C_AQUA_CORE      = srgb('#64fff0')
C_AQUA_MID       = srgb('#14d6bc')
C_AQUA_DEEP      = srgb('#08877d')

# Warm glowing lantern & molten volcanic magma (USED ONLY with 'glass' on the other 3 GLBs!)
C_FLAME_WHITE    = srgb('#ffd24d')
C_FLAME_CORE     = srgb('#ff8414')
C_FLAME_MID      = srgb('#eb3f05')
C_FLAME_DEEP     = srgb('#a81602')
C_MAGMA_CRIMSON  = srgb('#680a02')

# Tropical coastal vines, mossy tufts & beach ferns
C_VINE_DARK      = srgb('#184d1f')
C_VINE_MID       = srgb('#317b28')
C_VINE_SUN       = srgb('#82c42c')


# ---------------------------------------------------------------- shared sculptural helpers

def _add_beam(mb, p0, p1, w, h, mat, col, ch=0.0):
    """Emit a crisp timber, iron, or brass beam connecting arbitrary 3D points p0 and p1."""
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


def _build_powder_keg(mb, M_keg, radius=0.28, height=0.68, rng=None,
                      stave_mat='paint', col_a=C_CRIMSON_HI, col_b=C_CRIMSON_MID,
                      col_head=C_OAK_DEEP, segs=6, add_fuse=False):
    """Chunky crimson-painted coopered black-powder keg with forged-iron hoops & brass bung."""
    hh = height * 0.5
    prof = [
        (0.0,           -hh),
        (radius * 0.80, -hh),
        (radius,         0.0),
        (radius * 0.80,  hh),
        (0.0,            hh),
    ]
    stave_cols = [
        jit(col_a if k % 2 == 0 else col_b, rng, 0.04, 0.012) if rng else col_a
        for k in range(segs)
    ]
    with xf(mb, M_keg):
        lathe(mb, prof, segs, stave_mat, col_a, False, False,
              lambda i, k: col_head if i in (0, 3) else stave_cols[k])
        for hy, hr, hcol in (
            (-hh * 0.64, radius * 0.93, C_IRON_FORGED),
            ( hh * 0.64, radius * 0.93, C_IRON_RUST_HI),
        ):
            cyl(mb, hr, hy - 0.024, hy + 0.024, segs, 'iron', hcol, False, 0.0)
        # Cream skull-band / black-powder warning stripe around the belly
        cyl(mb, radius * 1.015, -hh * 0.14, hh * 0.14, segs, 'paint', C_CREAM_SAIL, False, 0.0)
        # Brass bung plug on top head
        cyl(mb, 0.036, hh - 0.01, hh + 0.032, 5, 'brass', C_GOLD_BRIGHT, False, 0.0)
        if add_fuse:
            tube(mb, [(0.0, hh + 0.02, 0.0), (0.04, hh + 0.14, -0.04),
                      (0.11, hh + 0.18, -0.09), (0.14, hh + 0.11, -0.14)],
                 0.016, 4, 'rope', C_ROPE, mode='flat')


def _build_rope_coil_lean(mb, center, radius=0.26, turns=2, r=0.035, segs=6, psegs=4, col=C_ROPE):
    """Chunky coiled braided hemp rope pile ('rope')."""
    for i in range(turns):
        rr = radius * (1.0 - 0.24 * i)
        with xf(mb, T(center[0], center[1] + r * (1.0 + i * 1.56), center[2])):
            torus(mb, rr, r, segs, psegs, 'rope', mul(col, 0.88 + 0.12 * (i % 2)), True)


def _build_wind_pennant(mb, root_pos, length=1.32, h0=0.38, out_dir=(0.92, -0.04, -0.38),
                        col_main=C_CRIMSON_HI, col_alt=C_CRIMSON_MID, col_trim=C_GOLD_BRIGHT, phase=0.32):
    """Wind-whipped double-sided swallowtail pennant ('paint') with UV2 wind weights."""
    rp = Vector(root_pos)
    od = Vector(out_dir).normalized()
    side = Vector((-od.z, 0.0, od.x))
    if side.length < 1e-4:
        side = Vector((1.0, 0.0, 0.0))
    side.normalize()
    segs = 5
    thick = 0.012
    top_pts, bot_pts, weights = [], [], []
    for i in range(segs + 1):
        t = i / float(segs)
        wave = sin(t * 2.1 * pi) * 0.14 * t
        droop = -0.14 * t * t
        hh = h0 * (1.0 - 0.42 * t)
        ctr = rp + od * (length * t) + side * wave + Vector((0.0, droop, 0.0))
        top_pts.append(ctr + Vector((0.0, hh * 0.5, 0.0)))
        bot_pts.append(ctr - Vector((0.0, hh * 0.5, 0.0)))
        weights.append((t ** 1.15) * 0.94)
    for i in range(segs):
        c_seg = col_trim if i == 0 else (col_main if i % 2 == 1 else col_alt)
        t0, t1 = top_pts[i], top_pts[i + 1]
        b0, b1 = bot_pts[i], bot_pts[i + 1]
        w0, w1 = weights[i], weights[i + 1]
        u0, u1 = (w0, phase), (w1, phase)
        if i == segs - 1:
            mid_notch = (t0 + b0) * 0.25 + (t1 + b1) * 0.25 - od * (length * 0.14)
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


def _add_leafy_vine_drape(mb, anchor, length, width, out_dir, rng, phase=0.0,
                          c_dark=C_VINE_DARK, c_mid=C_VINE_MID, c_sun=C_VINE_SUN):
    """Sculpted hanging leafy coastal/jungle vine ('foliage') with UV2 wind weights."""
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
        sway = sin(t * 3.1 + phase * 6.28) * 0.11 * (0.2 + 0.8 * t)
        out_off = 0.04 + 0.08 * sin(t * pi * 0.80) + 0.05 * t
        stem_pts.append(a + od * out_off + side * sway + Vector((0.0, -length * t, 0.0)))

    for i in range(segs):
        t0 = i / float(segs)
        t1 = (i + 1) / float(segs)
        w0 = width * 0.22 * (1.0 - 0.50 * t0)
        w1 = width * 0.22 * (1.0 - 0.72 * t1)
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

    n_leaves = max(5, int(length * 2.1))
    for li in range(n_leaves):
        t = (li + 0.35) / float(n_leaves + 0.25)
        idx_f = t * segs
        i0 = min(segs - 1, int(idx_f))
        frac = idx_f - i0
        root = stem_pts[i0].lerp(stem_pts[i0 + 1], frac)
        sgn = -1.0 if (li % 2 == 0) else 1.0
        l_scale = (0.78 + 0.46 * sin(t * pi * 0.85)) * (1.0 - 0.28 * t)
        l_len = width * 1.46 * l_scale * rng.uniform(0.86, 1.14)
        l_wid = width * 0.60 * l_scale * rng.uniform(0.86, 1.14)
        l_dir = (side * (sgn * 0.64) + od * (0.48 + rng.uniform(-0.10, 0.16)) + Vector((0.0, -0.74, 0.0))).normalized()
        l_perp = l_dir.cross(od)
        l_perp = l_perp.normalized() if l_perp.length > 1e-4 else side

        p_base  = root
        p_mid_l = root + l_dir * (l_len * 0.42) - l_perp * l_wid + od * 0.04
        p_mid_r = root + l_dir * (l_len * 0.42) + l_perp * l_wid + od * 0.04
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


def _add_coastal_fern_cluster(mb, root_pos, scale=0.80, n_fronds=4, rng=None, phase=0.0,
                              lean_dir=None, segs=2, c_dark=C_VINE_DARK, c_mid=C_VINE_MID, c_tip=C_VINE_SUN):
    """Broad painterly coastal fern rosette ('foliage') with UV2 wind weights."""
    rp = Vector(root_pos)
    base_rot = rng.uniform(0.0, 2.0 * pi) if rng else 0.0
    for fi in range(n_fronds):
        ang = base_rot + 2.0 * pi * fi / float(n_fronds) + (rng.uniform(-0.20, 0.20) if rng else 0.0)
        f_len = scale * (rng.uniform(0.86, 1.15) if rng else 1.0)
        f_w = scale * (rng.uniform(0.24, 0.32) if rng else 0.28)
        f_arch_h = scale * (rng.uniform(0.40, 0.54) if rng else 0.46)
        f_droop = scale * (rng.uniform(0.22, 0.34) if rng else 0.28)
        dir_xz = Vector((cos(ang), 0.0, sin(ang)))
        if lean_dir is not None:
            ld = Vector((lean_dir[0], 0.0, lean_dir[2]))
            if ld.length > 1e-4:
                dir_xz = (dir_xz + ld.normalized() * 0.42).normalized()
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


def _sculpt_magma_ribbon(mb, path_pts, widths, surface_nrm, hot_core=True, ridge_h=0.044, mat='glass',
                         c_core=C_FLAME_CORE, c_mid_col=C_FLAME_MID, c_edge_col=C_FLAME_DEEP, c_tip_col=C_MAGMA_CRIMSON):
    """Surface-hugging glowing molten magma or mystic rune vein ridge."""
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
        left_pts.append(pts[i] - side * w - nrm * 0.012)
        right_pts.append(pts[i] + side * w - nrm * 0.012)
        mid_pts.append(pts[i] + nrm * (ridge_h + 0.008 * sin(i * 1.7)))
    for i in range(n - 1):
        cm = c_core if (hot_core and i <= n // 2) else c_mid_col
        ce = c_edge_col if i < n - 2 else c_tip_col
        inside = (pts[i] + pts[i + 1]) * 0.5 - nrm * 0.5
        mb.fp([left_pts[i], mid_pts[i], mid_pts[i + 1], left_pts[i + 1]], mat,
              [ce, cm, cm, ce], (1, 0, 0), inside, smooth=False)
        mb.fp([mid_pts[i], right_pts[i], right_pts[i + 1], mid_pts[i + 1]], mat,
              [cm, ce, ce, cm], (1, 0, 0), inside, smooth=False)


def _add_chain_links(mb, p_start, p_end, n_links=6, link_r=0.16, wire_r=0.048,
                     segs=5, psegs=4, sag=0.24, mat='iron', rust_stride=2, stretch_y=1.42,
                     col_a=C_IRON_FORGED, col_b=C_IRON_RUST_HI, glow_indices=None):
    """Tightly interlocking arc-length-spaced forged-iron (and optional molten-glowing) chain links."""
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

    glow_set = set(glow_indices) if glow_indices is not None else set()
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
        if k in glow_set:
            l_mat = 'glass'
            l_col = C_FLAME_MID if (k % 2 == 0) else C_FLAME_DEEP
        else:
            l_mat = mat
            l_col = col_b if (k % rust_stride == 0) else col_a
        with xf(mb, T(pt) @ rot_q @ spin @ S(0.76, stretch_y, 0.76) @ M_Y2Z):
            torus(mb, link_r, wire_r, segs, psegs, l_mat, l_col, False)


# ==============================================================================
# 1. PIRATE POWDER MAGAZINE BUNKER (pirate_powder_magazine_bunker.glb)
# ==============================================================================

def _build_bunker_voussoir_arch(mb, center_x, spring_y, z_pos, r_in, r_out, depth,
                                n_voussoirs=9, rng=None, keystone_boost=0.22):
    """Sculpted radial stone voussoir arch with proud protruding central keystone."""
    mid_idx = n_voussoirs // 2
    a_min, a_max = -88.0, 88.0
    step = (a_max - a_min) / float(n_voussoirs)
    for i in range(n_voussoirs):
        is_key = (i == mid_idx)
        a0 = radians(a_min + i * step + 0.7)
        a1 = radians(a_min + (i + 1) * step - 0.7)
        ri = r_in - (0.04 if is_key else 0.0)
        ro = r_out + (keystone_boost if is_key else (0.04 if i % 2 == 0 else -0.02))
        dz = depth * (1.28 if is_key else 1.0)
        z0 = z_pos - dz * 0.5
        z1 = z_pos + dz * 0.5
        p00 = Vector((center_x + ri * sin(a0), spring_y + ri * cos(a0), z0))
        p01 = Vector((center_x + ro * sin(a0), spring_y + ro * cos(a0), z0))
        p11 = Vector((center_x + ro * sin(a1), spring_y + ro * cos(a1), z0))
        p10 = Vector((center_x + ri * sin(a1), spring_y + ri * cos(a1), z0))
        q00 = Vector((p00.x, p00.y, z1))
        q01 = Vector((p01.x, p01.y, z1))
        q11 = Vector((p11.x, p11.y, z1))
        q10 = Vector((p10.x, p10.y, z1))
        ctr = (p00 + p01 + p11 + p10 + q00 + q01 + q11 + q10) * 0.125
        vcol = C_SANDSTONE_HI if is_key else (
            jit(C_SANDSTONE_HI if i % 2 == 0 else C_SANDSTONE_MID, rng, 0.04, 0.015) if rng else C_SANDSTONE_MID
        )
        vmat = 'limestone' if (is_key or i % 2 == 0) else 'temple_stone'
        for face in (
            [p00, p01, p11, p10],
            [q10, q11, q01, q00],
            [p01, q01, q11, p11],
            [p10, q10, q00, p00],
            [p00, q00, q01, p01],
            [p11, q11, q10, p10],
        ):
            mb.fp(face, vmat, vcol, (1, 0, 0), ctr, smooth=False)


def _build_mossy_tuft(mb, center, radii, rng):
    """Low sculpted mossy stone-turf cushion ('limestone_moss') perched cleanly on stone ledges."""
    cx, cy, cz = center
    rx, ry, rz = radii
    with xf(mb, T(cx, cy, cz)):
        secs = [
            _reg_poly(0.0, -ry * 0.25, 0.0, 1.0, sides=6, rot_deg=rng.uniform(0, 60), sx=rx * 1.02, sz=rz * 1.02),
            _reg_poly(0.0,  ry * 0.45, 0.0, 1.0, sides=6, rot_deg=rng.uniform(0, 60), sx=rx * 0.78, sz=rz * 0.78),
            _reg_poly(0.0,  ry * 0.92, 0.0, 1.0, sides=6, rot_deg=rng.uniform(0, 60), sx=rx * 0.34, sz=rz * 0.34),
        ]
        loft(mb, secs, 'limestone_moss', C_MOSS_CUSHION, closed=True, caps=(False, True), mode='flat',
             scols=[C_MOSS_DEEP, C_MOSS_CUSHION, C_VINE_SUN])


def gen_pirate_powder_magazine_bunker(outdir):
    """Fortified arched sandstone & timber black-powder magazine bunker (~4.8 m W x 4.2 m D x 4.4 m H,
    -3.00 m deep ashlar foundation skirt) with barrel-vaulted keystone stone arch, recessed studded
    iron-banded oak blast door, stacked crimson-painted powder kegs & brass scoop/funnel under timber
    eaves, iron vent stack, crimson warning pennant (UV2 wind sway), mossy stonework tufts, convex
    collider 'col_powderbunker_base', and warm brass warning lantern empty 'Lantern_PowderBunker'."""
    clear_scene()
    mb = MB('pirate_powder_magazine_bunker', seed=1901)
    rng = random.Random(SEED + 1901)
    col_pts = []

    DECK_Y = 0.42
    BUNKER_X = -0.26   # shift vaulted stone bunker slightly port so starboard eaves bay fits cleanly in 4.8 m W!
    SPRING_Y = 1.94
    VAULT_ZF = -1.36
    VAULT_ZB =  1.48

    # 1. Deep Fortified Sandstone Ashlar Foundation Skirt plunging cleanly to y = -3.00 m (~4.8 m W x 4.2 m D)
    found_secs = [
        _rect_oct(0.0, -3.00, 0.0, 2.40, 2.08, 0.38),
        _rect_oct(0.0, -1.25, 0.0, 2.34, 2.02, 0.36),
        _rect_oct(0.0,  0.00, 0.0, 2.28, 1.96, 0.34),
        _rect_oct(0.0,  DECK_Y, 0.0, 2.22, 1.90, 0.32),
    ]
    _loft_horizontal_masonry(
        mb, found_secs, 'temple_stone',
        [C_SANDSTONE_DEEP, C_SANDSTONE_DARK, C_SANDSTONE_MID, C_SANDSTONE_HI],
        rng, caps=(True, True), top_mat='limestone', top_col=C_SANDSTONE_HI,
    )

    for yc, hx, hz in ((-3.00, 2.40, 2.08), (0.0, 2.28, 1.96), (DECK_Y, 2.20, 1.88), (2.48, 1.98, 1.62), (3.42, 1.38, 1.48)):
        col_pts.extend(_rect_oct(0.0, yc, 0.0, hx, hz, 0.30))

    # Seaward (-Z) stone blast-apron threshold steps leading into the recessed blast door
    cbox(mb, (BUNKER_X, 0.16, -2.02), (1.76, 0.32, 0.36), 'limestone', C_SANDSTONE_MID, 0.0)
    cbox(mb, (BUNKER_X, 0.36, -1.78), (1.62, 0.16, 0.40), 'limestone', C_SANDSTONE_HI, 0.0)
    # Stone curbing & heavy corner mooring bollards framing the front apron
    for bx_p in (-2.04, 2.06):
        cbox(mb, (bx_p, DECK_Y + 0.12, -1.72), (0.34, 0.28, 0.34), 'temple_stone', C_SANDSTONE_DARK, 0.0)

    # 2. Fortified Battered Sandstone Magazine Walls & Barrel-Vaulted Roof (x centered at BUNKER_X = -0.26)
    # Lower solid side walls flanking the deep front & rear vaulted niches
    for sgn in (-1.0, 1.0):
        wx = BUNKER_X + sgn * 1.18
        cbox(mb, (wx, 1.18, 0.06), (0.64, 1.56, 2.84), 'temple_stone', C_SANDSTONE_MID, 0.0)
        # Sloped blast-proof stone side buttresses anchoring the walls into the plinth
        for bz in (-0.82, 0.88):
            b_secs = [
                _rect_oct(BUNKER_X + sgn * 1.56, DECK_Y - 0.02, bz, 0.30, 0.28, 0.05),
                _rect_oct(BUNKER_X + sgn * 1.48, 1.24,          bz, 0.24, 0.25, 0.04),
                _rect_oct(BUNKER_X + sgn * 1.38, 1.96,          bz, 0.16, 0.22, 0.03),
            ]
            _loft_horizontal_masonry(
                mb, b_secs, 'limestone',
                [C_SANDSTONE_DARK, C_SANDSTONE_MID, C_SANDSTONE_HI], rng, caps=(False, True),
            )
        # Alternating corner ashlar quoin stones along front & rear bunker corners
        for qz in (VAULT_ZF + 0.06, VAULT_ZB - 0.06):
            for qi, qy in enumerate((0.68, 1.08, 1.48, 1.82)):
                qw = 0.34 if qi % 2 == 0 else 0.24
                qd = 0.24 if qi % 2 == 0 else 0.34
                cbox(mb, (BUNKER_X + sgn * 1.44, qy, qz), (qw, 0.28, qd),
                     'limestone', jit(C_SANDSTONE_HI, rng, 0.04), 0.0)

    # Interior solid vault core wall between front recessed blast door (z = -1.04) and rear vent niche (z = +1.18)
    cbox(mb, (BUNKER_X, 1.72, 0.08), (2.28, 2.60, 2.18), 'temple_stone', C_SANDSTONE_DARK, 0.0)

    # Sweeping Sculpted Barrel-Vaulted Sandstone Roof Shell (theta = -90..+90 deg, extruded front-to-back)
    R_IN = 1.06
    R_OUT = 1.54
    n_arc = 8
    vault_secs = []
    vault_cols = []
    for i in range(n_arc + 1):
        t = i / float(n_arc)
        ang = radians(-90.0 + 180.0 * t)
        ca, sa = cos(ang), sin(ang)
        # Slightly thicker shoulder crown for sturdy fortified barrel silhouette
        ro_i = R_OUT + 0.08 * (1.0 - ca * ca)
        p_in_f  = Vector((BUNKER_X + R_IN * sa, SPRING_Y + R_IN * ca, VAULT_ZF))
        p_out_f = Vector((BUNKER_X + ro_i * sa, SPRING_Y + ro_i * ca, VAULT_ZF))
        p_out_b = Vector((BUNKER_X + ro_i * sa, SPRING_Y + ro_i * ca, VAULT_ZB))
        p_in_b  = Vector((BUNKER_X + R_IN * sa, SPRING_Y + R_IN * ca, VAULT_ZB))
        vault_secs.append([p_in_f, p_out_f, p_out_b, p_in_b])
        vault_cols.append(C_SANDSTONE_HI if abs(t - 0.5) < 0.26 else C_SANDSTONE_MID)
    loft(mb, vault_secs, 'temple_stone', C_SANDSTONE_MID, closed=True, caps=(True, True),
         mode='flat', scols=vault_cols)

    # Stone barrel-vault coping stringcourses along both eaves + central stone ridge spine
    for sgn in (-1.0, 1.0):
        cbox(mb, (BUNKER_X + sgn * 1.58, SPRING_Y - 0.02, 0.06), (0.28, 0.16, 3.04),
             'limestone', C_SANDSTONE_HI, 0.0)
    cbox(mb, (BUNKER_X, SPRING_Y + R_OUT + 0.04, 0.06), (0.38, 0.14, 3.02),
         'limestone_moss', C_SANDSTONE_HI, 0.0)

    # Proud Faceted Stone Voussoir Keystone Arches on BOTH Seaward (-Z) Hero & Rear (+Z) Facades!
    _build_bunker_voussoir_arch(mb, BUNKER_X, SPRING_Y, VAULT_ZF - 0.08, R_IN - 0.02, R_OUT + 0.04, 0.28,
                                n_voussoirs=9, rng=rng, keystone_boost=0.24)
    _build_bunker_voussoir_arch(mb, BUNKER_X, SPRING_Y, VAULT_ZB + 0.06, R_IN - 0.04, R_OUT + 0.02, 0.24,
                                n_voussoirs=9, rng=rng, keystone_boost=0.18)

    # 3. Recessed Studded Iron-Banded Oak Blast Door (Hero -Z Vault Portal, recessed at z = -1.08 m!)
    DOOR_Z = -1.08
    # Stone door jamb posts & heavy lintel beam inside the vaulted recess
    for sgn in (-1.0, 1.0):
        cbox(mb, (BUNKER_X + sgn * 0.90, 1.24, DOOR_Z - 0.04), (0.24, 1.66, 0.28), 'limestone', C_SANDSTONE_HI, 0.0)
    cbox(mb, (BUNKER_X, 2.08, DOOR_Z - 0.04), (1.98, 0.22, 0.28), 'limestone', C_SANDSTONE_HI, 0.0)

    # Recessed Heavy Planked Oak Blast Door Panels (double-leaf with bold plank groove relief)
    cbox(mb, (BUNKER_X, 1.24, DOOR_Z + 0.05), (1.58, 1.64, 0.14), 'timber', C_OAK_DEEP, 0.0)
    n_dplanks = 5
    for pi_d in range(n_dplanks):
        px_d = BUNKER_X - 0.62 + pi_d * (1.24 / float(n_dplanks - 1))
        cbox(mb, (px_d, 1.24, DOOR_Z - 0.02), (0.25, 1.58, 0.055), 'timber',
             C_OAK_RICH if pi_d % 2 == 0 else C_OAK_DEEP, 0.0)
    # Recessed Arched Oak Tympanum Board above the lintel
    with xf(mb, T(BUNKER_X, SPRING_Y + 0.04, DOOR_Z + 0.06) @ M_Y2Z):
        cyl(mb, 0.98, -0.06, 0.06, 8, 'timber', C_OAK_CHAR, False, 0.0)
    # Bold Painted Crimson-and-Cream Diamond Powder-Warning Plaque framed cleanly inside the tympanum!
    with xf(mb, T(BUNKER_X, 2.40, DOOR_Z - 0.03)):
        cbox(mb, (0.0, 0.0, 0.0), (0.48, 0.48, 0.06), 'paint', C_CRIMSON_HI, 0.0, M=R('Z', 45.0))
        cbox(mb, (0.0, 0.0, -0.028), (0.34, 0.34, 0.04), 'paint', C_CREAM_SAIL, 0.0, M=R('Z', 45.0))
        with xf(mb, T(0.0, -0.02, -0.055) @ M_Y2Z):
            cyl(mb, 0.095, -0.02, 0.02, 6, 'iron', C_IRON_DARK, False, 0.0)
        cbox(mb, (0.05, 0.09, -0.056), (0.085, 0.085, 0.03), 'brass', C_GOLD_BRIGHT, 0.0, M=R('Z', 45.0))

    # Forged-Iron Blast-Door Hinge Straps, Crossed Reinforcement Bars, Studs & Brass Padlock!
    for hy in (0.72, 1.24, 1.76):
        cbox(mb, (BUNKER_X, hy, DOOR_Z - 0.065), (1.56, 0.105, 0.045), 'iron', C_IRON_FORGED, 0.0)
        for rx_s in (-0.60, -0.20, 0.20, 0.60):
            cbox(mb, (BUNKER_X + rx_s, hy, DOOR_Z - 0.098), (0.072, 0.072, 0.042), 'iron',
                 C_IRON_BRIGHT if abs(rx_s) > 0.4 else C_IRON_RUST_HI, 0.0, M=R('Z', 45.0))
    # Crossed diagonal iron reinforcement straps on lower door
    _add_beam(mb, (BUNKER_X - 0.68, 0.72, DOOR_Z - 0.065), (BUNKER_X + 0.68, 1.76, DOOR_Z - 0.065),
              0.065, 0.036, 'iron', C_IRON_DARK, 0.0)
    _add_beam(mb, (BUNKER_X + 0.68, 0.72, DOOR_Z - 0.065), (BUNKER_X - 0.68, 1.76, DOOR_Z - 0.065),
              0.065, 0.036, 'iron', C_IRON_DARK, 0.0)
    # Heavy sliding iron blast-bar latch + brass padlock & pull ring!
    cbox(mb, (BUNKER_X + 0.08, 1.24, DOOR_Z - 0.11), (1.16, 0.095, 0.065), 'iron', C_IRON_BRIGHT, 0.0)
    cbox(mb, (BUNKER_X + 0.42, 1.12, DOOR_Z - 0.12), (0.14, 0.18, 0.08), 'brass', C_GOLD_BRIGHT, 0.0)
    with xf(mb, T(BUNKER_X - 0.36, 1.24, DOOR_Z - 0.12) @ M_Y2Z):
        torus(mb, 0.075, 0.020, 6, 4, 'brass', C_BRASS_WARM, False)

    # 4. Rear (+Z) Fortified Blast-Vent Iron Grille & Spare Cannonball Shot Garland
    REAR_Z = 1.26
    cbox(mb, (BUNKER_X, 1.66, REAR_Z), (1.42, 1.46, 0.14), 'iron', C_IRON_DARK, 0.0)
    cbox(mb, (BUNKER_X, 1.66, REAR_Z + 0.08), (1.52, 0.12, 0.12), 'iron', C_IRON_FORGED, 0.0)
    for bx_r in (-0.48, -0.24, 0.0, 0.24, 0.48):
        cbox(mb, (BUNKER_X + bx_r, 1.66, REAR_Z + 0.09), (0.048, 1.38, 0.055), 'iron', C_IRON_BRIGHT, 0.0)
    for by_r in (1.28, 1.66, 2.04):
        cbox(mb, (BUNKER_X, by_r, REAR_Z + 0.09), (1.34, 0.052, 0.055), 'iron', C_IRON_RUST_HI, 0.0)
    # Timber cannonball shot garland on the rear apron (+Z)
    cbox(mb, (BUNKER_X - 0.32, DECK_Y + 0.07, 1.68), (1.10, 0.14, 0.36), 'timber', C_OAK_DEEP, 0.0)
    for cb_x in (BUNKER_X - 0.64, BUNKER_X - 0.32, BUNKER_X):
        with xf(mb, T(cb_x, DECK_Y + 0.22, 1.68)):
            lathe(mb, [(0.0, -0.13), (0.11, -0.09), (0.13, 0.0), (0.11, 0.09), (0.0, 0.13)],
                  5, 'iron', C_IRON_DARK, False)

    # 5. Starboard Timber Eaves Shelter Canopy cleanly framing Powder Kegs & Measuring Station!
    # Unobstructed vaulted stone arch on front (-Z), crisp sloped timber eaves shed along starboard (+X)!
    EAVE_X = 2.04
    EAVE_Y = 2.30
    WALL_TIE_X = BUNKER_X + 1.38
    WALL_TIE_Y = 2.70
    for pz_p in (-1.52, -0.06, 1.24):
        cbox(mb, (EAVE_X, 0.5 * (DECK_Y + EAVE_Y), pz_p), (0.16, EAVE_Y - DECK_Y + 0.06, 0.16), 'timber', C_OAK_DEEP, 0.0)
        cbox(mb, (EAVE_X, DECK_Y + 0.08, pz_p), (0.20, 0.16, 0.20), 'iron', C_IRON_FORGED, 0.0)
        # Diagonal knee brace up to eave plate
        _add_beam(mb, (EAVE_X, EAVE_Y - 0.46, pz_p), (EAVE_X - 0.42, EAVE_Y + 0.10, pz_p),
                  0.08, 0.09, 'timber', C_OAK_RICH, 0.0)
        # Sloped oak rafter anchored solidly into the stone barrel-vault shoulder!
        _add_beam(mb, (WALL_TIE_X - 0.14, WALL_TIE_Y, pz_p), (EAVE_X + 0.28, EAVE_Y - 0.08, pz_p),
                  0.10, 0.12, 'timber', C_OAK_DEEP, 0.0)
    # Longitudinal eave header beam & wall ledger beam + front fascia board
    _add_beam(mb, (EAVE_X, EAVE_Y - 0.02, -1.76), (EAVE_X, EAVE_Y - 0.02, 1.46), 0.14, 0.15, 'timber', C_OAK_RICH, 0.0)
    _add_beam(mb, (WALL_TIE_X, WALL_TIE_Y - 0.04, -1.68), (WALL_TIE_X, WALL_TIE_Y - 0.04, 1.40), 0.12, 0.12, 'timber', C_OAK_DEEP, 0.0)

    # Sloped Planked Timber Eaves Roof Decking over the Starboard Powder-Keg Bay!
    n_roof_planks = 5
    for rpi in range(n_roof_planks):
        t_rp = (rpi + 0.5) / float(n_roof_planks)
        px_r = WALL_TIE_X - 0.12 + (EAVE_X + 0.34 - (WALL_TIE_X - 0.12)) * t_rp
        py_r = WALL_TIE_Y + 0.08 + (EAVE_Y - 0.02 - (WALL_TIE_Y + 0.08)) * t_rp
        tilt_r = degrees(atan2((EAVE_Y - 0.02) - (WALL_TIE_Y + 0.08), (EAVE_X + 0.34) - (WALL_TIE_X - 0.12)))
        cbox(mb, (px_r, py_r, -0.14), (0.30, 0.065, 3.30), 'timber',
             C_OAK_SUN if rpi % 2 == 0 else C_OAK_RICH, 0.0, M=R('Z', tilt_r))

    # 6. Stacked Crimson-Painted Black-Powder Kegs & Brass Scoop/Funnel Bench under Timber Eaves!
    # Low timber dunnage cradle on front-starboard apron (x = 1.56, z = -0.96) holding a 3-keg pyramid!
    cbox(mb, (1.58, DECK_Y + 0.06, -0.94), (0.86, 0.12, 1.18), 'timber', C_OAK_DEEP, 0.0)
    _build_powder_keg(mb, T(1.58, DECK_Y + 0.39, -1.20) @ R('Z', 90.0), radius=0.27, height=0.66, rng=rng, segs=6)
    _build_powder_keg(mb, T(1.58, DECK_Y + 0.39, -0.62) @ R('Z', 90.0), radius=0.27, height=0.66, rng=rng, segs=6)
    _build_powder_keg(mb, T(1.58, DECK_Y + 0.85, -0.91) @ R('Z', 90.0), radius=0.26, height=0.64, rng=rng, segs=6, add_fuse=True)

    # Standing upright crimson powder keg on front-port entrance flank with coiled slow-match fuse!
    _build_powder_keg(mb, T(-1.74, DECK_Y + 0.34, -1.48) @ R('Y', 18.0),
                      radius=0.26, height=0.68, rng=rng, segs=6, add_fuse=True)
    _build_rope_coil_lean(mb, (-1.96, DECK_Y, -1.06), radius=0.22, turns=2, r=0.030, segs=6, psegs=4)

    # Oak Powder-Handling Workbench under Starboard Eaves (x = 1.66, z = 0.42) w/ Brass Scoop & Flared Funnel!
    TB_X, TB_Z = 1.66, 0.42
    TB_Y = DECK_Y + 0.72
    cbox(mb, (TB_X, TB_Y, TB_Z), (0.76, 0.08, 1.16), 'timber', C_OAK_SUN, 0.0)
    for lx in (-0.30, 0.30):
        for lz in (-0.48, 0.48):
            cbox(mb, (TB_X + lx, DECK_Y + 0.35, TB_Z + lz), (0.085, 0.70, 0.085), 'timber', C_OAK_DEEP, 0.0)
    # Open priming keg standing beside workbench
    _build_powder_keg(mb, T(1.62, DECK_Y + 0.32, 1.28) @ R('Y', -24.0),
                      radius=0.24, height=0.64, rng=rng, segs=6)
    # Sculpted Burnished-Brass Powder Filling Funnel resting upright on bench!
    with xf(mb, T(TB_X + 0.04, TB_Y + 0.04, TB_Z - 0.26)):
        lathe(mb, [(0.0, 0.0), (0.17, 0.0), (0.15, 0.12), (0.045, 0.25), (0.035, 0.40), (0.0, 0.40)],
              6, 'brass', C_GOLD_BRIGHT, False, False,
              lambda i, k: C_BRASS_DARK if i == 0 else C_GOLD_BRIGHT)
        with xf(mb, T(0.16, 0.09, 0.0) @ M_Y2Z):
            torus(mb, 0.055, 0.015, 5, 4, 'brass', C_BRASS_WARM, False)
    # Sculpted Burnished-Brass Powder Measuring Scoop & Cup resting prominently on bench!
    with xf(mb, T(TB_X + 0.08, TB_Y + 0.09, TB_Z + 0.18) @ R('Y', -28.0)):
        with xf(mb, M_Y2X):
            cyl(mb, 0.080, -0.15, 0.15, 6, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.066)
        cbox(mb, (-0.25, 0.0, 0.0), (0.24, 0.044, 0.044), 'timber', C_OAK_DEEP, 0.0)
        cbox(mb, (-0.13, 0.0, 0.0), (0.06, 0.060, 0.060), 'brass', C_BRASS_WARM, 0.0)
    with xf(mb, T(TB_X - 0.14, TB_Y + 0.04, TB_Z + 0.34)):
        cyl(mb, 0.075, 0.0, 0.15, 5, 'brass', C_BRASS_WARM, False, 0.0, 0.088)

    # Heavy Iron-Bound Munitions Crate under the workbench
    cbox(mb, (TB_X, DECK_Y + 0.22, TB_Z), (0.58, 0.44, 0.72), 'timber', C_OAK_RICH, 0.0)
    cbox(mb, (TB_X, DECK_Y + 0.22, TB_Z), (0.61, 0.08, 0.75), 'iron', C_IRON_FORGED, 0.0)

    # 7. Riveted Forged-Iron Blast-Proof Exhaust Vent Stack on Vault Crown (y = 3.25 to 4.38 m!)
    VENT_X, VENT_Z = BUNKER_X + 0.14, 0.34
    with xf(mb, T(VENT_X, 0.0, VENT_Z)):
        cbox(mb, (0.0, 3.38, 0.0), (0.68, 0.24, 0.68), 'limestone', C_SANDSTONE_HI, 0.0)
        cyl(mb, 0.24, 3.44, 3.60, 6, 'iron', C_IRON_FORGED, False, 0.0, 0.21)
        cyl(mb, 0.19, 3.58, 4.10, 6, 'iron', C_IRON_DARK, False, 0.0, 0.18)
        cyl(mb, 0.215, 3.80, 3.88, 6, 'brass', C_BRASS_WARM, False, 0.0)
        cyl(mb, 0.22, 4.08, 4.14, 6, 'iron', C_IRON_BRIGHT, False, 0.0)
        for k in range(4):
            ang = radians(45.0 + k * 90.0)
            cbox(mb, (0.17 * cos(ang), 4.20, 0.17 * sin(ang)), (0.036, 0.18, 0.036), 'iron', C_IRON_FORGED, 0.0)
        lathe(mb, [(0.0, 4.22), (0.34, 4.22), (0.28, 4.27), (0.05, 4.38), (0.0, 4.40)],
              6, 'iron', C_IRON_RUST_HI, False, False,
              lambda i, k: C_IRON_BRIGHT if i >= 2 else C_IRON_RUST_HI)
    # Iron guy-rod braces anchoring the vent stack solidly to the stone barrel vault!
    for gx, gz in ((-0.74, 0.06), (0.72, 0.06), (0.0, 0.86)):
        _add_beam(mb, (VENT_X, 3.92, VENT_Z), (VENT_X + gx, 3.24, VENT_Z + gz),
                  0.030, 0.030, 'iron', C_IRON_FORGED, 0.0)

    # 8. Crimson Warning Pennant Flagpole on Front-Port Vault Parapet (y up to ~4.42 m, UV2 wind sway!)
    POLE_X, POLE_Z = BUNKER_X - 1.38, -1.24
    cbox(mb, (POLE_X, 2.02, POLE_Z), (0.24, 0.24, 0.24), 'iron', C_IRON_FORGED, 0.0)
    with xf(mb, T(POLE_X, 0.0, POLE_Z)):
        cyl(mb, 0.055, 1.94, 4.34, 6, 'timber', C_OAK_DEEP, False, 0.0, 0.034)
        cyl(mb, 0.072, 2.48, 2.58, 6, 'iron', C_IRON_BRIGHT, False, 0.0)
        lathe(mb, [(0.0, 4.32), (0.072, 4.38), (0.0, 4.46)], 6, 'brass', C_GOLD_BRIGHT, False)
    _build_wind_pennant(
        mb, root_pos=(POLE_X + 0.04, 4.08, POLE_Z), length=1.34, h0=0.40,
        out_dir=(0.90, -0.04, -0.44),
        col_main=C_CRIMSON_HI, col_alt=C_CRIMSON_DARK, col_trim=C_GOLD_BRIGHT, phase=0.22,
    )

    # 9. Warm Brass Warning Lantern ('Lantern_PowderBunker') on Forged-Iron Wall Bracket beside Portal!
    LANTERN_POS = Vector((BUNKER_X - 1.18, 2.44, -1.78))
    _add_beam(mb, (BUNKER_X - 1.18, 2.74, VAULT_ZF - 0.06), (BUNKER_X - 1.18, 2.74, -1.84),
              0.058, 0.064, 'iron', C_IRON_FORGED, 0.0)
    _add_beam(mb, (BUNKER_X - 1.18, 2.34, VAULT_ZF - 0.06), (BUNKER_X - 1.18, 2.74, -1.76),
              0.044, 0.048, 'iron', C_IRON_BRIGHT, 0.0)
    _add_beam(mb, (BUNKER_X - 1.18, 2.74, -1.78), LANTERN_POS + Vector((0.0, 0.25, 0.0)),
              0.024, 0.024, 'iron', C_IRON_FORGED, 0.0)
    _build_storm_lantern(mb, LANTERN_POS, scale=0.84, brass_cage=True, hanging=True)

    # 10. Mossy Stonework Tufts ('limestone_moss') & Coastal Fern Clumps ('foliage' + UV2!)
    for mpos, mrad in (
        ((BUNKER_X - 1.48, SPRING_Y + 0.12, -0.58), (0.34, 0.16, 0.44)),
        ((BUNKER_X - 1.42, SPRING_Y + 0.14,  0.74), (0.36, 0.18, 0.48)),
        ((BUNKER_X - 0.64, SPRING_Y + 1.42, -0.42), (0.42, 0.14, 0.46)),
        ((BUNKER_X + 0.56, SPRING_Y + 1.38,  0.96), (0.38, 0.14, 0.42)),
        ((BUNKER_X + 1.46, SPRING_Y + 0.12,  1.26), (0.30, 0.15, 0.34)),
        ((-2.02, DECK_Y + 0.04, 1.56),              (0.42, 0.18, 0.38)),
    ):
        _build_mossy_tuft(mb, mpos, mrad, rng)

    for fpos, fsc, flean, fph in (
        ((-2.08, DECK_Y + 0.02, -1.62), 0.72, (-0.7, 0.0, -0.7), 0.14),
        ((-2.06, DECK_Y + 0.02,  1.44), 0.78, (-0.7, 0.0,  0.7), 0.42),
        (( 2.02, DECK_Y + 0.02,  1.56), 0.74, ( 0.7, 0.0,  0.7), 0.68),
        ((BUNKER_X - 1.44, SPRING_Y + 0.14, 0.12), 0.56, (-1.0, 0.0, 0.0), 0.85),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=4, rng=rng, phase=fph, lean_dir=flean, segs=2)

    build(mb)

    add_empty('Lantern_PowderBunker', LANTERN_POS)
    col_piece('col_powderbunker_base', col_pts)
    export_landmark_glb(outdir, 'pirate_powder_magazine_bunker.glb')


# ==============================================================================
# 2. ANCIENT CORAL LEVIATHAN ALTAR (ancient_coral_leviathan_altar.glb)
# ==============================================================================

def _build_fossil_coral_horn(mb, base_pos, main_dir, length=1.18, base_r=0.14,
                             branch_specs=(), mat='skull_stone', col_base=C_CORAL_SHADE,
                             col_mid=C_CORAL_BLUSH, col_tip=C_CORAL_IVORY):
    """Sculpted organic branching staghorn/reef fossil coral cluster."""
    bp = Vector(base_pos)
    md = Vector(main_dir).normalized()
    side = md.cross(Vector((0.0, 1.0, 0.0)))
    if side.length < 1e-4:
        side = Vector((1.0, 0.0, 0.0))
    side.normalize()
    up_v = side.cross(md).normalized()

    pts = [
        bp,
        bp + md * (length * 0.36) + up_v * (length * 0.08),
        bp + md * (length * 0.72) + up_v * (length * 0.18) + side * (length * 0.04),
        bp + md * length + up_v * (length * 0.28),
    ]
    tube(mb, pts, [base_r, base_r * 0.76, base_r * 0.48, base_r * 0.14], 5, mat, col_mid,
         caps=(False, True), mode='flat', scols=[col_base, col_mid, col_tip, col_tip])

    for t_fork, s_amt, u_amt, b_len_frac, b_rad_frac in branch_specs:
        i0 = min(2, int(t_fork * 3.0))
        root = pts[i0].lerp(pts[i0 + 1], t_fork * 3.0 - i0)
        b_dir = (md * 0.62 + side * s_amt + up_v * u_amt).normalized()
        bl = length * b_len_frac
        br = base_r * b_rad_frac
        b_pts = [root, root + b_dir * (bl * 0.55), root + b_dir * bl + Vector((0.0, bl * 0.16, 0.0))]
        tube(mb, b_pts, [br, br * 0.64, br * 0.16], 4, mat, col_tip,
             caps=(False, True), mode='flat', scols=[col_mid, col_tip, col_tip])


def _build_leviathan_jaw_arch(mb, sgn, spring_y, orb_c, rng):
    """Single sweeping fanged carved sea-serpent jaw-rib stone arch rising from a serpent-carved
    shoulder pier to y ~ 4.86 m with inward-curving carved stone fangs & coral-ivory dorsal crests."""
    # Massive carved temple-stone shoulder pier locking the jaw arch cleanly into the terrace!
    pier_secs = [
        _rect_oct(sgn * 1.50, 0.32, 0.0, 0.60, 0.64, 0.14),
        _rect_oct(sgn * 1.48, 1.08, 0.0, 0.54, 0.56, 0.12),
        _rect_oct(sgn * 1.50, 1.66, 0.0, 0.48, 0.50, 0.10),
    ]
    _loft_horizontal_masonry(
        mb, pier_secs, 'temple_stone',
        [C_REEF_STONE_DK, C_REEF_STONE_MID, C_REEF_STONE_HI], rng, caps=(False, True),
    )
    # Ancient verdigris-brass ceremonial collar & carved guardian sea-serpent head relief on front & rear!
    cbox(mb, (sgn * 1.50, 1.62, 0.0), (1.04, 0.12, 1.06), 'brass', C_VERDIGRIS_HI, 0.0)
    cbox(mb, (sgn * 1.50, 1.72, 0.0), (0.94, 0.08, 0.96), 'brass', C_GOLD_BRIGHT, 0.0)
    for z_sgn in (-1.0, 1.0):
        fz = z_sgn * 0.54
        # Carved angular stone serpent brow, snout bridge & flanking cheek volutes
        cbox(mb, (sgn * 1.48, 1.38, fz + z_sgn * 0.04), (0.58, 0.18, 0.18), 'temple_stone', C_REEF_STONE_HI, 0.0)
        cbox(mb, (sgn * 1.48, 1.12, fz + z_sgn * 0.06), (0.34, 0.28, 0.18), 'temple_stone', C_CORAL_IVORY, 0.0)
        for ex_s in (-0.18, 0.18):
            cbox(mb, (sgn * 1.48 + ex_s, 1.24, fz + z_sgn * 0.07), (0.11, 0.11, 0.08),
                 'skull_glow', C_AQUA_CORE, 0.0, M=R('Z', 45.0))
        # Twin miniature carved stone serpent fangs beneath the snout relief
        for fx_s in (-0.12, 0.12):
            bp_f = Vector((sgn * 1.48 + fx_s, 0.98, fz + z_sgn * 0.11))
            tube(mb, [bp_f, bp_f + Vector((0.0, -0.18, z_sgn * 0.04))], [0.055, 0.010], 4,
                 'skull_stone', C_CORAL_IVORY, caps=(False, True), mode='flat')

    # Sweeping Ogival Leviathan Jaw-Rib Curve (12 sculpted stations tapering smoothly to curved fang-tips!)
    n_st = 11
    jaw_pts = []
    jaw_secs = []
    jaw_cols = []
    for i in range(n_st + 1):
        t = i / float(n_st)
        jx = sgn * (1.46 + 0.50 * sin(t * pi * 0.90) - 1.26 * (t ** 1.98))
        jy = 1.40 + 3.26 * (sin(t * pi * 0.56) ** 0.90) - 0.10 * max(0.0, (t - 0.80) / 0.20)
        jz = 0.05 * sin(t * pi) - 0.06 * (t ** 2.0)
        jaw_pts.append(Vector((jx, jy, jz)))

    for i in range(n_st + 1):
        t = i / float(n_st)
        p = jaw_pts[i]
        in_dir = (orb_c - p)
        in_dir.z = 0.0
        if in_dir.length < 1e-4:
            in_dir = Vector((-sgn, 0.0, 0.0))
        in_dir.normalize()
        out_dir = -in_dir

        # Smooth organic jaw taper ending in a graceful pointed sea-serpent crest tip!
        tip_pinch = 1.0 - 0.72 * max(0.0, (t - 0.78) / 0.22)
        thick_r = 0.44 * (1.0 - 0.52 * (t ** 1.25)) * tip_pinch
        half_z  = 0.36 * (1.0 - 0.50 * (t ** 1.25)) * tip_pinch
        p_in  = p + in_dir * (thick_r * 0.54)
        p_out = p + out_dir * (thick_r * 0.86)
        p_mid = (p_in + p_out) * 0.5
        sec = [
            p_in  + Vector((0.0, 0.0, -half_z * 0.58)),
            p_mid + Vector((0.0, 0.0, -half_z)),
            p_out + Vector((0.0, 0.0, -half_z * 0.52)),
            p_out + Vector((0.0, 0.0,  half_z * 0.52)),
            p_mid + Vector((0.0, 0.0,  half_z)),
            p_in  + Vector((0.0, 0.0,  half_z * 0.58)),
        ]
        jaw_secs.append(sec)
        jaw_cols.append(C_CORAL_IVORY if t > 0.65 else (C_REEF_STONE_HI if t > 0.25 else C_REEF_STONE_MID))

    loft(mb, jaw_secs, 'temple_stone', C_REEF_STONE_HI, closed=True, caps=(True, True),
         mode='flat', scols=jaw_cols)

    # Sweeping Inward-Pointing Carved Leviathan Fangs ('skull_stone') lining the inner jaw arch!
    for fi_idx, st_i in enumerate((2, 4, 6, 8, 9, 10)):
        p_root = jaw_pts[st_i]
        to_orb = (orb_c - p_root)
        to_orb.z = 0.0
        to_orb.normalize()
        fang_dir = (to_orb * 0.92 + Vector((0.0, -0.26 if st_i >= 7 else 0.08, 0.0))).normalized()
        fang_len = 0.56 if fi_idx in (1, 2, 3) else (0.44 if fi_idx == 4 else 0.34)
        fang_r   = 0.115 if fi_idx in (1, 2, 3) else 0.086
        f_pts = [
            p_root + to_orb * 0.08,
            p_root + fang_dir * (fang_len * 0.54) + Vector((0.0, -0.04, 0.0)),
            p_root + fang_dir * fang_len + Vector((0.0, -0.10, 0.0)),
        ]
        tube(mb, f_pts, [fang_r, fang_r * 0.56, 0.014], 5, 'skull_stone', C_CORAL_IVORY,
             caps=(False, True), mode='flat', scols=[C_REEF_STONE_MID, C_CORAL_IVORY, C_CORAL_IVORY])

    # Crisp Carved Fossil-Coral & Pale Reef-Stone Dorsal Serpent Crest Spines along Outer Jaw Back!
    for st_i in (2, 4, 6, 8):
        p = jaw_pts[st_i]
        out_v = (p - orb_c)
        out_v.z = 0.0
        out_v.normalize()
        fin_len = 0.40 if st_i in (4, 6) else 0.30
        y_lift = 0.10 if st_i < 8 else 0.08
        f_pts = [
            p + out_v * 0.16,
            p + out_v * (0.16 + fin_len * 0.55) + Vector((0.0, y_lift, 0.0)),
            p + out_v * (0.16 + fin_len) + Vector((0.0, y_lift * 1.6, 0.0)),
        ]
        tube(mb, f_pts, [0.11, 0.072, 0.016], 4, 'skull_stone', C_CORAL_BLUSH,
             caps=(False, True), mode='flat', scols=[C_REEF_STONE_MID, C_CORAL_BLUSH, C_CORAL_IVORY])

    # Ancient Gilded-Bronze Collar Bands & Glowing Aqua Mystic Rune Studs inlaid on Jaw Flanks!
    for st_i in (3, 5, 7):
        p = jaw_pts[st_i]
        t_r = st_i / float(n_st)
        hz = 0.34 * (1.0 - 0.48 * (t_r ** 1.25))
        for z_sgn in (-1.0, 1.0):
            cbox(mb, (p.x, p.y, p.z + z_sgn * (hz + 0.02)), (0.12, 0.12, 0.06),
                 'skull_glow', C_AQUA_MID, 0.0, M=R('Z', 45.0))


def gen_ancient_coral_leviathan_altar(outdir):
    """Overgrown carved mossy coral-and-temple-stone sea-serpent offering altar (~4.6 m W x 4.2 m D x
    4.9 m H, -3.00 m stepped temple plinth) crowned by twin sweeping fanged leviathan-jaw stone arches
    cradling a hovering luminous cyan-turquoise pearl orb ('skull_glow'), glowing aqua altar basin runes
    ('skull_glow'), branching fossil coral horns, cascading jungle vines & ferns (UV2 wind sway), convex
    collider 'col_coralaltar_base', and empty 'Lantern_CoralAltar'."""
    clear_scene()
    mb = MB('ancient_coral_leviathan_altar', seed=1902)
    rng = random.Random(SEED + 1902)
    col_pts = []

    TERRACE_Y = 0.34
    DAIS_Y = 0.90
    ORB_C = Vector((0.0, 3.04, 0.0))

    # 1. Stepped Mossy Temple-Stone Plinth plunging cleanly to y = -3.00 m (~4.6 m W x 4.2 m D)
    plinth_secs = [
        _rect_oct(0.0, -3.00, 0.0, 2.30, 2.08, 0.56),
        _rect_oct(0.0, -1.20, 0.0, 2.24, 2.02, 0.54),
        _rect_oct(0.0,  0.00, 0.0, 2.18, 1.96, 0.52),
        _rect_oct(0.0, TERRACE_Y, 0.0, 2.12, 1.90, 0.50),
    ]
    _loft_horizontal_masonry(
        mb, plinth_secs, 'limestone_moss',
        [C_REEF_STONE_SK, C_REEF_STONE_DK, C_REEF_STONE_MID, C_REEF_STONE_HI],
        rng, caps=(True, True), top_mat='limestone_moss', top_col=C_REEF_STONE_MID,
    )

    for yc, hx, hz in ((-3.00, 2.30, 2.08), (0.0, 2.18, 1.96), (DAIS_Y, 1.92, 1.72), (4.40, 1.78, 0.72)):
        col_pts.extend(_rect_oct(0.0, yc, 0.0, hx, hz, 0.36))

    # Second & Third Concentric Stepped Reef Temple Terraces
    t2_secs = [
        _rect_oct(0.0, TERRACE_Y - 0.02, 0.0, 1.84, 1.62, 0.44),
        _rect_oct(0.0, 0.64,             0.0, 1.76, 1.54, 0.42),
    ]
    _loft_horizontal_masonry(mb, t2_secs, 'temple_stone', [C_REEF_STONE_DK, C_REEF_STONE_MID],
                             rng, caps=(False, True), top_mat='limestone_moss', top_col=C_REEF_STONE_MID)

    t3_secs = [
        _rect_oct(0.0, 0.62,   0.0, 1.46, 1.28, 0.36),
        _rect_oct(0.0, DAIS_Y, 0.0, 1.38, 1.20, 0.34),
    ]
    _loft_horizontal_masonry(mb, t3_secs, 'temple_stone', [C_REEF_STONE_MID, C_REEF_STONE_HI],
                             rng, caps=(False, True), top_mat='temple_stone', top_col=C_REEF_STONE_HI)

    # Ceremonial Carved Stone Steps on BOTH Seaward (-Z) & Rear (+Z) Approaches
    for z_sgn in (-1.0, 1.0):
        cbox(mb, (0.0, 0.18, z_sgn * 1.96), (1.32, 0.34, 0.36), 'temple_stone', C_REEF_STONE_MID, 0.0)
        cbox(mb, (0.0, 0.48, z_sgn * 1.66), (1.18, 0.28, 0.34), 'temple_stone', C_REEF_STONE_HI, 0.0)
        cbox(mb, (0.0, 0.74, z_sgn * 1.36), (1.04, 0.24, 0.32), 'temple_stone', C_REEF_STONE_HI, 0.0)
        for sx in (-1.0, 1.0):
            cbox(mb, (sx * 0.70, 0.44, z_sgn * 1.66), (0.20, 0.64, 0.72), 'limestone_moss', C_REEF_STONE_DK, 0.0)
            cbox(mb, (sx * 0.70, 0.79, z_sgn * 1.48), (0.22, 0.10, 0.24), 'brass', C_VERDIGRIS_HI, 0.0)

    # 2. Carved Sea-Serpent Offering Altar & Glowing Aqua Basin Runes ('skull_glow'!) (y = 0.90 to 1.84 m)
    with xf(mb, T(0.0, DAIS_Y, 0.0)):
        # Sculpted pedestal base & tapered carved stone offering table
        alt_secs = [
            _rect_oct(0.0, -0.02, 0.0, 0.76, 0.62, 0.18),
            _rect_oct(0.0,  0.22, 0.0, 0.56, 0.46, 0.14),
            _rect_oct(0.0,  0.62, 0.0, 0.52, 0.44, 0.12),
            _rect_oct(0.0,  0.84, 0.0, 0.84, 0.68, 0.20),
        ]
        _loft_horizontal_masonry(
            mb, alt_secs, 'temple_stone',
            [C_REEF_STONE_DK, C_REEF_STONE_MID, C_REEF_STONE_MID, C_REEF_STONE_HI],
            rng, caps=(False, True), top_mat='temple_stone', top_col=C_REEF_STONE_HI,
        )
        # Sculpted Coral-Lotus Stone Support Petals cupping the Four Corners of the Offering Basin!
        for sx in (-1.0, 1.0):
            for sz in (-1.0, 1.0):
                p0 = Vector((sx * 0.46, 0.16, sz * 0.38))
                p1 = Vector((sx * 0.76, 0.56, sz * 0.60))
                p2 = Vector((sx * 0.86, 0.94, sz * 0.68))
                tube(mb, [p0, p1, p2], [0.13, 0.11, 0.036], 5, 'skull_stone', C_CORAL_IVORY,
                     caps=(False, True), mode='flat', scols=[C_REEF_STONE_MID, C_CORAL_BLUSH, C_CORAL_IVORY])
        # Raised carved basin rim + verdigris-brass ceremonial trim collar
        with xf(mb, T(0.0, 0.88, 0.0) @ S(1.16, 1.0, 0.94)):
            torus(mb, 0.60, 0.075, 10, 4, 'temple_stone', C_REEF_STONE_HI, False)
            torus(mb, 0.66, 0.036, 10, 4, 'brass', C_GOLD_BRIGHT, False)
        # Luminous Glowing Aqua Offering Basin Pool & Central Energy Ripple Crest ('skull_glow'!)
        with xf(mb, T(0.0, 0.87, 0.0) @ S(1.16, 1.0, 0.94)):
            cyl(mb, 0.54, -0.02, 0.04, 10, 'skull_glow', C_AQUA_MID, False, 0.0)
            cyl(mb, 0.34,  0.03, 0.07,  8, 'skull_glow', C_AQUA_CORE, False, 0.0, 0.22)
        # Glowing Aqua Carved Altar Basin Runes etched prominently on Front, Rear & Side Aprons!
        for z_sgn in (-1.0, 1.0):
            cbox(mb, (0.0, 0.72, z_sgn * 0.64), (0.96, 0.065, 0.06), 'skull_glow', C_AQUA_MID, 0.0)
            for rx_g, gs in ((-0.34, 0.12), (0.0, 0.16), (0.34, 0.12)):
                cbox(mb, (rx_g, 0.44, z_sgn * 0.48), (gs, gs, 0.07),
                     'skull_glow', C_AQUA_CORE if rx_g == 0.0 else C_AQUA_MID, 0.0, M=R('Z', 45.0))
            _add_beam(mb, (0.0, 0.16, z_sgn * 0.56), (0.0, 0.68, z_sgn * 0.54),
                      0.055, 0.055, 'skull_glow', C_AQUA_DEEP, 0.0)
        for x_sgn in (-1.0, 1.0):
            cbox(mb, (x_sgn * 0.78, 0.72, 0.0), (0.06, 0.065, 0.74), 'skull_glow', C_AQUA_MID, 0.0)
            cbox(mb, (x_sgn * 0.56, 0.44, 0.0), (0.07, 0.14, 0.14), 'skull_glow', C_AQUA_CORE, 0.0, M=R('X', 45.0))

    # Luminous Aqua Floor Rune Channels & Brass Ring Medallion inlaid across the Dais!
    with xf(mb, T(0.0, DAIS_Y + 0.015, 0.0)):
        torus(mb, 0.96, 0.028, 12, 4, 'brass', C_VERDIGRIS_HI, False)
    for sx in (-1.0, 1.0):
        _sculpt_magma_ribbon(
            mb, [(sx * 0.64, DAIS_Y + 0.02, 0.0), (sx * 1.08, DAIS_Y + 0.02, 0.0)],
            [0.085, 0.065], (0.0, 1.0, 0.0), hot_core=True, ridge_h=0.028,
            mat='skull_glow', c_core=C_AQUA_CORE, c_mid_col=C_AQUA_MID, c_edge_col=C_AQUA_DEEP, c_tip_col=C_AQUA_DEEP,
        )
    for sz in (-1.0, 1.0):
        _sculpt_magma_ribbon(
            mb, [(0.0, DAIS_Y + 0.02, sz * 0.56), (0.0, DAIS_Y + 0.02, sz * 1.12)],
            [0.085, 0.060], (0.0, 1.0, 0.0), hot_core=True, ridge_h=0.028,
            mat='skull_glow', c_core=C_AQUA_CORE, c_mid_col=C_AQUA_MID, c_edge_col=C_AQUA_DEEP, c_tip_col=C_AQUA_DEEP,
        )

    # 3. Twin Sweeping Fanged Leviathan-Jaw Stone Arches crowning the Altar (y = 0.34 to ~4.88 m!)
    for sgn in (-1.0, 1.0):
        _build_leviathan_jaw_arch(mb, sgn, DAIS_Y, ORB_C, rng)

    # 4. Hovering Luminous Cyan-Turquoise Pearl Orb ('skull_glow'!) nestled cleanly between the Fanged Jaws!
    with xf(mb, T(ORB_C)):
        orb_prof = [
            (0.00, -0.44),
            (0.24, -0.37),
            (0.40, -0.18),
            (0.44,  0.00),
            (0.40,  0.18),
            (0.24,  0.37),
            (0.00,  0.44),
        ]
        lathe(mb, orb_prof, 10, 'skull_glow', C_AQUA_MID, False, False,
              lambda i, k: C_AQUA_CORE if i in (2, 3) else C_AQUA_MID)
        # Twin angled verdigris-brass & gilded sea-current filigree halos orbiting the hovering pearl!
        with xf(mb, R('Z', 24.0) @ R('X', 22.0)):
            torus(mb, 0.62, 0.032, 12, 4, 'brass', C_GOLD_BRIGHT, False)
            for k in range(4):
                ang = k * pi * 0.5
                cbox(mb, (0.62 * cos(ang), 0.0, 0.62 * sin(ang)), (0.09, 0.09, 0.09), 'skull_glow', C_AQUA_CORE, 0.0)
        with xf(mb, R('Z', -38.0) @ R('Y', 32.0) @ M_Y2Z):
            torus(mb, 0.76, 0.028, 12, 4, 'brass', C_VERDIGRIS_HI, False)
        # Sleek faceted diamond-crystal orbiting luminous aqua motes!
        for mx, my, mz, msc in ((-0.54, 0.42, -0.22, 0.13), (0.56, -0.34, 0.24, 0.12), (0.10, 0.62, -0.14, 0.11)):
            with xf(mb, T(mx, my, mz) @ R('Z', 18.0)):
                lathe(mb, [(0.0, -msc), (msc * 0.58, 0.0), (0.0, msc)], 4, 'skull_glow', C_AQUA_CORE, False)

    # 5. Sculpted Branching Fossil Coral Horns sprouting organically from Piers, Mid-Shoulders & Corners!
    coral_clusters = [
        ((-1.78, 1.54, -0.36), (-0.72, 0.68, -0.34), 1.24, 0.15,
         [(0.42, 0.65, 0.45, 0.56, 0.62), (0.68, -0.58, 0.55, 0.44, 0.52)],
         'skull_stone', C_CORAL_SHADE, C_CORAL_BLUSH, C_CORAL_IVORY),
        (( 1.78, 1.50, -0.34), ( 0.74, 0.66, -0.30), 1.18, 0.145,
         [(0.40, -0.62, 0.48, 0.54, 0.60), (0.66, 0.56, 0.54, 0.42, 0.50)],
         'skull_stone', C_CORAL_SHADE, C_CORAL_ROSE, C_CORAL_IVORY),
        ((-1.68, 1.48,  0.48), (-0.64, 0.72,  0.46), 1.32, 0.15,
         [(0.38, -0.58, 0.50, 0.58, 0.62), (0.70, 0.55, 0.48, 0.44, 0.50)],
         'limestone', C_CORAL_SHADE, C_CORAL_ROSE, C_CORAL_BLUSH),
        (( 1.70, 1.44,  0.46), ( 0.62, 0.74,  0.48), 1.26, 0.145,
         [(0.42, 0.60, 0.52, 0.55, 0.60), (0.68, -0.54, 0.46, 0.42, 0.48)],
         'limestone', C_CORAL_SHADE, C_CORAL_BLUSH, C_CORAL_IVORY),
        # Upper jaw-shoulder coral fan-horns adding rich organic marine reef silhouette!
        ((-1.86, 2.52, -0.18), (-0.82, 0.56, -0.22), 0.96, 0.115,
         [(0.44, 0.58, 0.46, 0.52, 0.58), (0.70, -0.52, 0.44, 0.40, 0.48)],
         'skull_stone', C_CORAL_SHADE, C_CORAL_ROSE, C_CORAL_IVORY),
        (( 1.86, 2.48,  0.18), ( 0.82, 0.58,  0.24), 0.94, 0.115,
         [(0.42, -0.56, 0.48, 0.52, 0.58), (0.68, 0.52, 0.44, 0.40, 0.48)],
         'skull_stone', C_CORAL_SHADE, C_CORAL_BLUSH, C_CORAL_IVORY),
        # Lower reef plinth staghorn coral horns framing the front & rear corners
        ((-1.72, TERRACE_Y + 0.04, -1.26), (-0.48, 0.84, -0.44), 0.94, 0.125,
         [(0.48, 0.62, 0.42, 0.52, 0.58)],
         'skull_stone', C_CORAL_SHADE, C_CORAL_BLUSH, C_CORAL_IVORY),
        (( 1.74, TERRACE_Y + 0.04, -1.22), ( 0.46, 0.85, -0.42), 0.88, 0.12,
         [(0.46, -0.58, 0.44, 0.50, 0.56)],
         'skull_stone', C_CORAL_SHADE, C_CORAL_ROSE, C_CORAL_BLUSH),
        ((-1.68, TERRACE_Y + 0.04,  1.24), (-0.50, 0.82,  0.44), 0.92, 0.12,
         [(0.45, -0.56, 0.44, 0.50, 0.56)],
         'skull_stone', C_CORAL_SHADE, C_CORAL_BLUSH, C_CORAL_IVORY),
        (( 1.68, TERRACE_Y + 0.04,  1.26), ( 0.48, 0.84,  0.46), 0.90, 0.12,
         [(0.46, 0.58, 0.42, 0.50, 0.56)],
         'limestone', C_CORAL_SHADE, C_CORAL_ROSE, C_CORAL_IVORY),
    ]
    for bp, md, clen, brad, bsp, cmat, cb, cm, ct in coral_clusters:
        _build_fossil_coral_horn(mb, bp, md, clen, brad, bsp, cmat, cb, cm, ct)

    # 6. Cascading Jungle Vines & Tropical Reef Ferns ('foliage' + UV2 wind sway!)
    for v_anc, v_len, v_w, v_dir, v_ph in (
        ((-1.82, 3.60, -0.18), 1.92, 0.15, (-0.7, 0.0, -0.7), 0.12),
        (( 1.82, 3.54, -0.16), 1.80, 0.15, ( 0.7, 0.0, -0.7), 0.38),
        ((-1.40, 4.18,  0.22), 1.66, 0.14, (-0.5, 0.0,  0.8), 0.62),
        (( 1.42, 4.14,  0.22), 1.72, 0.14, ( 0.5, 0.0,  0.8), 0.84),
        ((-1.74, 2.38,  0.42), 1.32, 0.13, (-0.6, 0.0,  0.8), 0.28),
        (( 1.74, 2.32,  0.44), 1.28, 0.13, ( 0.6, 0.0,  0.8), 0.71),
    ):
        _add_leafy_vine_drape(mb, v_anc, v_len, v_w, v_dir, rng, phase=v_ph)

    for fpos, fsc, flean, fph in (
        ((-1.88, TERRACE_Y + 0.02, -1.48), 0.78, (-0.7, 0.0, -0.7), 0.15),
        (( 1.90, TERRACE_Y + 0.02, -1.44), 0.76, ( 0.7, 0.0, -0.7), 0.41),
        ((-1.88, TERRACE_Y + 0.02,  1.46), 0.80, (-0.7, 0.0,  0.7), 0.67),
        (( 1.88, TERRACE_Y + 0.02,  1.48), 0.76, ( 0.7, 0.0,  0.7), 0.91),
        ((-1.54, 0.66, -0.76),             0.62, (-0.9, 0.0, -0.4), 0.32),
        (( 1.54, 0.66,  0.78),             0.62, ( 0.9, 0.0,  0.4), 0.55),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=4, rng=rng, phase=fph, lean_dir=flean, segs=2)

    build(mb)

    add_empty('Lantern_CoralAltar', ORB_C)
    col_piece('col_coralaltar_base', col_pts)
    export_landmark_glb(outdir, 'ancient_coral_leviathan_altar.glb')


# ==============================================================================
# 3. COASTAL BOATBUILDER SLIPWAY WINCH (coastal_boatbuilder_slipway_winch.glb)
# ==============================================================================

def _skiff_surface_pt(u_t, v_t, side):
    """Analytical pirate skiff hull surface in local boat coordinates:
    u_t in [0..1] (0 = sharp bow stem at x=-1.60, 1 = raked transom at x=+1.52),
    v_t in [0..1] (0 = keel centerline, 1 = sweeping gunwale sheerline),
    side in {-1.0 (hero -Z flank), +1.0 (rear +Z flank)}."""
    L_bow, L_stern = -1.60, 1.52
    x = L_bow + (L_stern - L_bow) * u_t
    # Smooth beam curve: pointed entry at bow -> full midships -> graceful wineglass transom
    if u_t < 0.46:
        b_u = sin((u_t / 0.46) * pi * 0.5) ** 0.78
    else:
        b_u = 1.0 - 0.30 * (((u_t - 0.46) / 0.54) ** 1.65)
    half_beam = max(0.022, 0.74 * b_u)
    # Keel rocker & sweeping pirate sheerline
    y_keel = 0.14 * ((2.0 * u_t - 1.0) ** 2)
    y_sheer = 0.64 + 0.24 * ((1.0 - u_t) ** 1.8) + 0.16 * (u_t ** 2.1)
    # Cross-section bilge curve (rounded chine & slight upper flare)
    z_frac = (sin(v_t * pi * 0.52) ** 0.78) * (0.94 + 0.08 * v_t)
    y_frac = (1.0 - cos(v_t * pi * 0.50)) ** 0.90
    y = y_keel + (y_sheer - y_keel) * y_frac
    z = side * half_beam * z_frac
    return Vector((x, y, z))


def _emit_hull_strake_strip(mb, u_vals, v0, v1, side, mat, col_out, col_in, thick=0.036, top_rim=False):
    """Emit a double-sided solid planked hull strake ribbon between u_vals and [v0..v1]."""
    for i in range(len(u_vals) - 1):
        u0, u1 = u_vals[i], u_vals[i + 1]
        p00 = _skiff_surface_pt(u0, v0, side)
        p10 = _skiff_surface_pt(u1, v0, side)
        p11 = _skiff_surface_pt(u1, v1, side)
        p01 = _skiff_surface_pt(u0, v1, side)
        ctr = (p00 + p10 + p11 + p01) * 0.25
        nrm = newell([p00, p10, p11, p01])
        if nrm.length < 1e-6:
            continue
        nrm.normalize()
        if nrm.dot(ctr - Vector((ctr.x, 0.58, 0.0))) < 0:
            nrm = -nrm
        off_o = nrm * (thick * 0.5)
        off_i = -nrm * (thick * 0.5)
        mb.fp([p00 + off_o, p10 + off_o, p11 + off_o, p01 + off_o], mat, col_out,
              (1, 0, 0), ctr - nrm * 1.0, smooth=False)
        mb.fp([p10 + off_i, p00 + off_i, p01 + off_i, p11 + off_i], mat, col_in,
              (1, 0, 0), ctr + nrm * 1.0, smooth=False)
        if top_rim:
            mb.fp([p01 + off_i, p11 + off_i, p11 + off_o, p01 + off_o], mat, mul(col_out, 0.85),
                  (1, 0, 0), ctr - Vector((0.0, 0.3, 0.0)), smooth=False)


def _build_half_planked_skiff(mb, M_hull, rng):
    """Sculpted ~3.2 m half-planked wooden pirate skiff hull with exposed curved oak ribs,
    painted crimson-red & cream sheer strakes, raked stern transom, oak thwarts & bow ring!
    Returns world-space bow hauling ring position."""
    with xf(mb, M_hull):
        # 1. Heavy Oak Keel Timber Spine + Sweeping Curved Bow Stempost
        keel_pts = [_skiff_surface_pt(u / 6.0, 0.0, 1.0) - Vector((0.0, 0.04, 0.0)) for u in range(7)]
        tube(mb, keel_pts, 0.072, 4, 'timber', C_OAK_DEEP, caps=(True, True), mode='flat')

        stem_pts = [
            _skiff_surface_pt(0.0, 0.0, 1.0) - Vector((0.02, 0.04, 0.0)),
            _skiff_surface_pt(0.0, 0.35, 1.0) - Vector((0.07, 0.0, 0.0)),
            _skiff_surface_pt(0.0, 0.72, 1.0) - Vector((0.12, 0.0, 0.0)),
            _skiff_surface_pt(0.0, 1.00, 1.0) + Vector((-0.14, 0.14, 0.0)),
        ]
        tube(mb, stem_pts, [0.068, 0.062, 0.056, 0.048], 4, 'timber', C_OAK_DEEP, caps=(True, True), mode='flat')

        # Heavy Forged-Iron Bow Hauling Ring bolted right onto the proud oak stempost!
        bow_ring_local = stem_pts[2] + Vector((-0.08, 0.02, 0.0))
        cbox(mb, stem_pts[2] + Vector((-0.02, 0.02, 0.0)), (0.12, 0.12, 0.13), 'iron', C_IRON_FORGED, 0.0)
        with xf(mb, T(bow_ring_local) @ M_Y2Z):
            torus(mb, 0.085, 0.024, 6, 4, 'iron', C_IRON_BRIGHT, False)

        # 2. Seven Bold Exposed Curved Oak Hull Ribs (Frames) rising cleanly from keel to sheerline!
        rib_us = [0.12, 0.26, 0.40, 0.54, 0.68, 0.82, 0.94]
        for ru in rib_us:
            for side in (-1.0, 1.0):
                r_pts = [_skiff_surface_pt(ru, vi / 4.0, side) for vi in range(5)]
                r_in = [Vector((p.x, p.y + 0.016, p.z * 0.94)) for p in r_pts]
                tube(mb, r_in, 0.042, 4, 'timber', C_OAK_SUN, caps=(True, True), mode='flat')

        # Continuous Oak Gunwale Caprails (top edge beams) & Inner Bilge Stringers along BOTH flanks!
        u_rail = [i / 7.0 for i in range(8)]
        for side in (-1.0, 1.0):
            gun_pts = [_skiff_surface_pt(u, 1.0, side) for u in u_rail]
            tube(mb, gun_pts, 0.046, 4, 'timber', C_OAK_DEEP, caps=(True, True), mode='flat')
            str_pts = [Vector((p.x, p.y, p.z * 0.90)) for p in (_skiff_surface_pt(u, 0.54, side) for u in u_rail)]
            tube(mb, str_pts, 0.030, 4, 'timber', C_OAK_RICH, caps=(True, True), mode='flat')

        # 3. Half-Planked Hull Sheathing + Painted Red-and-Cream Sheer Strakes!
        # Rear (+Z) side: fully planked from keel to gunwale so Rear 3/4 showcases painted hull craftsmanship!
        u_full = [i / 6.0 for i in range(7)]
        _emit_hull_strake_strip(mb, u_full, 0.00, 0.28,  1.0, 'timber', C_OAK_DEEP,   C_OAK_CHAR,  0.036, False)
        _emit_hull_strake_strip(mb, u_full, 0.28, 0.56,  1.0, 'timber', C_OAK_RICH,   C_OAK_DEEP,  0.036, False)
        _emit_hull_strake_strip(mb, u_full, 0.56, 0.78,  1.0, 'paint',  C_CREAM_SAIL, C_OAK_RICH,  0.038, False)
        _emit_hull_strake_strip(mb, u_full, 0.78, 1.00,  1.0, 'paint',  C_CRIMSON_HI, C_OAK_RICH,  0.040, True)

        # Hero (-Z) side: lower bilge planked full-length; wide midships cutaway exposes 4 bold curved oak ribs!
        _emit_hull_strake_strip(mb, u_full, 0.00, 0.28, -1.0, 'timber', C_OAK_DEEP,   C_OAK_CHAR,  0.036, True)
        u_bow_mid  = [0.00, 0.14, 0.28]
        u_bow_top  = [0.00, 0.13, 0.26, 0.37]
        u_st_mid   = [0.78, 1.00]
        u_st_top   = [0.74, 0.87, 1.00]
        _emit_hull_strake_strip(mb, u_bow_mid, 0.28, 0.56, -1.0, 'timber', C_OAK_RICH,   C_OAK_DEEP, 0.036, False)
        _emit_hull_strake_strip(mb, u_bow_top, 0.56, 0.78, -1.0, 'paint',  C_CREAM_SAIL, C_OAK_RICH, 0.038, False)
        _emit_hull_strake_strip(mb, u_bow_top, 0.78, 1.00, -1.0, 'paint',  C_CRIMSON_HI, C_OAK_RICH, 0.040, True)
        _emit_hull_strake_strip(mb, u_st_mid,  0.28, 0.56, -1.0, 'timber', C_OAK_RICH,   C_OAK_DEEP, 0.036, False)
        _emit_hull_strake_strip(mb, u_st_top,  0.56, 0.78, -1.0, 'paint',  C_CREAM_SAIL, C_OAK_RICH, 0.038, False)
        _emit_hull_strake_strip(mb, u_st_top,  0.78, 1.00, -1.0, 'paint',  C_CRIMSON_HI, C_OAK_RICH, 0.040, True)

        # 4. Raked Oak Stern Transom (u_t = 1.0) w/ Painted Crimson Trim & Forged-Iron Rudder Pintles!
        for vi, (va, vb, tmat, tcol) in enumerate((
            (0.00, 0.35, 'timber', C_OAK_DEEP),
            (0.35, 0.68, 'timber', C_OAK_RICH),
            (0.68, 0.84, 'paint',  C_CREAM_SAIL),
            (0.84, 1.00, 'paint',  C_CRIMSON_HI),
        )):
            pl0 = _skiff_surface_pt(1.0, va, -1.0)
            pr0 = _skiff_surface_pt(1.0, va,  1.0)
            pr1 = _skiff_surface_pt(1.0, vb,  1.0)
            pl1 = _skiff_surface_pt(1.0, vb, -1.0)
            ctr = (pl0 + pr0 + pr1 + pl1) * 0.25
            dx = Vector((0.045, 0.0, 0.0))
            mb.fp([pl0 + dx, pr0 + dx, pr1 + dx, pl1 + dx], tmat, tcol, (0, 0, 1), ctr - Vector((1, 0, 0)), smooth=False)
            mb.fp([pr0, pl0, pl1, pr1], 'timber', C_OAK_DEEP, (0, 0, 1), ctr + Vector((1, 0, 0)), smooth=False)
        for py_r in (0.34, 0.62):
            cbox(mb, (1.57, py_r, 0.0), (0.06, 0.08, 0.20), 'iron', C_IRON_FORGED, 0.0)

        # 5. Interior Floorboards, Oak Thwart Rowing Benches & Unfinished Oar resting diagonally!
        cbox(mb, (0.04, 0.20, 0.0), (2.22, 0.055, 0.56), 'timber', C_DRIFT_MID, 0.0)
        for tu in (0.28, 0.58, 0.84):
            pl = _skiff_surface_pt(tu, 0.72, -0.94)
            pr = _skiff_surface_pt(tu, 0.72,  0.94)
            cbox(mb, ((pl.x + pr.x) * 0.5, pl.y, 0.0), (0.24, 0.055, abs(pr.z - pl.z)), 'timber', C_OAK_SUN, 0.0)
        _add_beam(mb, (-0.42, 0.66, -0.26), (1.38, 0.82, 0.34), 0.042, 0.042, 'timber', C_DRIFT_PALE, 0.0)
        cbox(mb, (1.28, 0.81, 0.31), (0.48, 0.032, 0.14), 'timber', C_OAK_SUN, 0.0, M=R('Y', -18.0))

    return M_hull @ bow_ring_local


def gen_coastal_boatbuilder_slipway_winch(outdir):
    """Sloped weathered-timber boatbuilder's coastal launch slipway & cradle (~5.4 m W x 3.6 m D x 3.5 m H,
    -2.80 m deep timber/cobble piling foundation) cradling a sculpted half-planked wooden pirate skiff hull
    with exposed curved oak ribs, painted red-and-cream sheer strakes, hand-turned capstan hauling winch
    with coiled hawser rope to the bow ring, pitch pot & timber sawhorse, fluttering shipyard flag (UV2
    wind sway), convex collider 'col_boatslipway_base', and warm hanging work-lantern empty
    'Lantern_BoatSlipway'."""
    clear_scene()
    mb = MB('coastal_boatbuilder_slipway_winch', seed=1903)
    rng = random.Random(SEED + 1903)
    col_pts = []

    WINCH_DECK_Y = 0.60
    SLOPE_DEG = -6.8  # gentle downward slope from port winch deck (-X) toward starboard launch (+X)

    def _slip_y(x_val):
        t = max(0.0, min(1.0, (x_val + 1.60) / 4.20))
        return 0.58 - 0.40 * t

    # 1. Deep Timber/Cobble Piling Foundation plunging cleanly to y = -2.80 m (~5.4 m W x 3.6 m D)
    def _sloped_ring(y_base, hx, hz, ch, slope_top=False):
        pts = _rect_oct(0.0, y_base, 0.0, hx, hz, ch)
        if not slope_top:
            return pts
        return [(px, _slip_y(px), pz) for (px, _, pz) in pts]

    cobble_secs = [
        _sloped_ring(-2.80, 2.62, 1.74, 0.34, False),
        _sloped_ring(-1.10, 2.56, 1.68, 0.32, False),
        _sloped_ring( 0.00, 2.50, 1.62, 0.30, False),
        _sloped_ring( 0.42, 2.44, 1.56, 0.28, True),
    ]
    _loft_horizontal_masonry(
        mb, cobble_secs, 'limestone',
        [C_COBBLE_WET, C_COBBLE_DARK, C_COBBLE_MID, C_COBBLE_HI],
        rng, caps=(True, True), top_mat='limestone', top_col=C_COBBLE_HI,
    )

    for yc, hx, hz in ((-2.80, 2.62, 1.74), (0.0, 2.50, 1.62), (0.62, 2.42, 1.54), (1.92, 2.16, 1.22)):
        col_pts.extend(_rect_oct(0.0, yc, 0.0, hx, hz, 0.28))

    # Stout Weathered Timber Foundation Pilings lashed with hemp rope along front & rear seawall edges!
    for px_p in (-2.40, -0.80, 0.80, 2.40):
        for pz_p in (-1.54, 1.54):
            top_y = _slip_y(px_p) + (0.34 if px_p < -1.0 else 0.18)
            with xf(mb, T(px_p, 0.0, pz_p)):
                cyl(mb, 0.125, -0.35, top_y, 6, 'timber', C_DRIFT_DARK, False, 0.0, 0.112)
                if abs(px_p) > 1.8:
                    with xf(mb, T(0.0, top_y - 0.14, 0.0)):
                        torus(mb, 0.132, 0.026, 5, 4, 'rope', C_ROPE, False)

    # Raised Planked Oak Winch Platform Deck at port (-X) end (x = -2.42 to -1.22, y = 0.60 m)
    cbox(mb, (-1.82, WINCH_DECK_Y - 0.06, 0.0), (1.26, 0.14, 3.00), 'timber', C_OAK_DEEP, 0.0)
    for dpi in range(5):
        pz_d = -1.20 + dpi * 0.60
        cbox(mb, (-1.82, WINCH_DECK_Y + 0.02, pz_d), (1.22, 0.06, 0.54), 'timber',
             C_DRIFT_MID if dpi % 2 == 0 else C_DRIFT_PALE, 0.0)

    # 2. Sloped Timber Slipway Launch Skid Rails, Cross-Tie Sleepers & Boat Cradle!
    for sx_t in (-0.98, -0.34, 0.30, 0.94, 1.58, 2.24):
        ty = _slip_y(sx_t)
        cbox(mb, (sx_t, ty + 0.04, 0.08), (0.20, 0.12, 1.86), 'timber',
             C_DRIFT_DARK if int(sx_t * 2) % 2 == 0 else C_OAK_DEEP, 0.0, M=R('Z', SLOPE_DEG))

    for rail_z in (-0.36, 0.52):
        _add_beam(mb, (-1.18, _slip_y(-1.18) + 0.12, rail_z), (2.60, _slip_y(2.60) + 0.12, rail_z),
                  0.14, 0.13, 'timber', C_OAK_RICH, 0.0)
        _add_beam(mb, (-1.16, _slip_y(-1.16) + 0.19, rail_z), (2.58, _slip_y(2.58) + 0.19, rail_z),
                  0.055, 0.025, 'iron', C_IRON_FORGED, 0.0)

    # Heavy Oak Boat Cradle riding squarely on the launch rails beneath the skiff hull!
    CRADLE_X = 0.64
    CRADLE_Z = 0.08
    M_CRADLE = T(CRADLE_X, _slip_y(CRADLE_X) + 0.24, CRADLE_Z) @ R('Z', SLOPE_DEG)
    with xf(mb, M_CRADLE):
        for cz_r in (-0.44, 0.44):
            cbox(mb, (0.0, 0.04, cz_r), (2.34, 0.14, 0.14), 'timber', C_OAK_DEEP, 0.0)
        for cx_b in (-0.86, 0.0, 0.88):
            cbox(mb, (cx_b, 0.15, 0.0), (0.18, 0.14, 1.24), 'timber', C_OAK_RICH, 0.0)
            for sgn in (-1.0, 1.0):
                _add_beam(mb, (cx_b, 0.16, sgn * 0.54), (cx_b, 0.52, sgn * 0.36),
                          0.095, 0.10, 'timber', C_OAK_SUN, 0.0)
                cbox(mb, (cx_b, 0.22, sgn * 0.58), (0.14, 0.10, 0.10), 'iron', C_IRON_FORGED, 0.0)

    # 3. Sculpted Half-Planked Wooden Pirate Skiff Hull sitting cleanly inside the Boat Cradle!
    M_HULL = T(CRADLE_X, _slip_y(CRADLE_X) + 0.46, CRADLE_Z) @ R('Z', SLOPE_DEG)
    bow_ring_pos = _build_half_planked_skiff(mb, M_HULL, rng)

    # 4. Hand-Turned Capstan Hauling Winch & Taut Hawser Rope to Bow Ring (port deck x = -1.92)
    CAP_X, CAP_Z = -1.92, 0.08
    CAP_Y = WINCH_DECK_Y + 0.04
    with xf(mb, T(CAP_X, CAP_Y, CAP_Z)):
        cyl(mb, 0.40, 0.00, 0.09, 7, 'iron', C_IRON_FORGED, False, 0.0, 0.36)
        cyl(mb, 0.34, 0.08, 0.16, 7, 'timber', C_OAK_DEEP, False, 0.0)
        cap_prof = [
            (0.00, 0.16),
            (0.30, 0.16),
            (0.22, 0.42),
            (0.21, 0.62),
            (0.32, 0.86),
            (0.32, 1.06),
            (0.26, 1.12),
            (0.00, 1.12),
        ]
        lathe(mb, cap_prof, 7, 'timber', C_OAK_RICH, False, False,
              lambda i, k: C_OAK_SUN if i in (2, 4) else C_OAK_DEEP)
        cyl(mb, 0.33, 0.88, 0.94, 7, 'iron', C_IRON_BRIGHT, False, 0.0)
        cyl(mb, 0.20, 1.11, 1.18, 7, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.12)
        for k in range(4):
            ang = radians(25.0 + k * 90.0)
            p_in  = Vector((0.24 * cos(ang), 0.98, 0.24 * sin(ang)))
            p_out = Vector((0.86 * cos(ang), 1.04, 0.86 * sin(ang)))
            _add_beam(mb, p_in, p_out, 0.064, 0.064, 'timber', C_OAK_SUN, 0.0)
            cbox(mb, p_out, (0.085, 0.085, 0.085), 'iron', C_IRON_FORGED, 0.0)
        # Chunky Braided Hemp Hawser Rope wrapped tightly around the Capstan Waist!
        for hi_r, hy_r in enumerate((0.41, 0.51)):
            with xf(mb, T(0.0, hy_r, 0.0)):
                torus(mb, 0.248, 0.044, 6, 4, 'rope', mul(C_ROPE, 0.90 + 0.10 * (hi_r % 2)), True)

    # Taut Braided Hemp Hawser Line stretching cleanly from the Capstan Waist to the Skiff Bow Ring!
    cap_exit = Vector((CAP_X + 0.24, CAP_Y + 0.50, CAP_Z))
    hawser_mid = cap_exit.lerp(bow_ring_pos, 0.5) + Vector((0.0, -0.04, 0.0))
    tube(mb, [cap_exit, hawser_mid, bow_ring_pos], 0.038, 4, 'rope', C_ROPE, mode='flat')
    # Fat Coiled Surplus Hawser Rope Pile resting on the winch deck beside the capstan!
    _build_rope_coil_lean(mb, (-1.84, WINCH_DECK_Y + 0.04, -0.82), radius=0.28, turns=2, r=0.042, segs=6, psegs=4)

    # 5. Boatbuilder's Caulking Pitch Pot on Iron Tripod w/ Deep Glowing Embers & Ladle (front-port apron!)
    POT_X, POT_Z = -0.94, -1.04
    POT_Y = _slip_y(POT_X)
    with xf(mb, T(POT_X, POT_Y, POT_Z)):
        torus(mb, 0.28, 0.068, 6, 4, 'limestone', C_COBBLE_DARK, False)
        cyl(mb, 0.22, 0.00, 0.08, 6, 'glass', C_MAGMA_CRIMSON, False, 0.0, 0.15)
        cyl(mb, 0.13, 0.05, 0.12, 5, 'glass', C_FLAME_DEEP, False, 0.0, 0.05)
        for k in range(3):
            ang = radians(30.0 + k * 120.0)
            _add_beam(mb, (0.34 * cos(ang), 0.0, 0.34 * sin(ang)), (0.20 * cos(ang), 0.54, 0.20 * sin(ang)),
                      0.036, 0.036, 'iron', C_IRON_FORGED, 0.0)
        pot_prof = [
            (0.00, 0.18), (0.20, 0.21), (0.28, 0.38), (0.26, 0.54), (0.30, 0.58), (0.24, 0.58), (0.00, 0.52),
        ]
        lathe(mb, pot_prof, 6, 'iron', C_IRON_DARK, False, False,
              lambda i, k: C_PITCH_TAR if i >= 5 else (C_IRON_RUST_HI if i == 3 else C_IRON_DARK))
        _add_beam(mb, (0.0, 0.44, 0.0), (0.28, 0.94, -0.18), 0.034, 0.034, 'timber', C_OAK_SUN, 0.0)
        cbox(mb, (0.06, 0.54, -0.04), (0.11, 0.11, 0.11), 'rope', C_PITCH_TAR, 0.0)

    # 6. Carpenter's Timber Sawhorse with Freshly Cut Hull Plank & Hand-Saw (front-starboard work apron!)
    # Positioned slightly starboard so the exposed curved oak hull ribs shine 100% unobstructed!
    SAW_X, SAW_Z = 1.44, -1.08
    SAW_Y = _slip_y(SAW_X)
    with xf(mb, T(SAW_X, SAW_Y, SAW_Z) @ R('Y', -16.0)):
        cbox(mb, (0.0, 0.62, 0.0), (1.06, 0.10, 0.12), 'timber', C_OAK_RICH, 0.0)
        for sx_l in (-0.42, 0.42):
            for sz_l in (-1.0, 1.0):
                _add_beam(mb, (sx_l, 0.60, sz_l * 0.04), (sx_l * 1.12, -0.02, sz_l * 0.28),
                          0.062, 0.062, 'timber', C_OAK_DEEP, 0.0)
            _add_beam(mb, (sx_l * 1.06, 0.26, -0.16), (sx_l * 1.06, 0.26, 0.16),
                      0.045, 0.045, 'timber', C_OAK_SUN, 0.0)
        cbox(mb, (0.04, 0.70, 0.0), (1.46, 0.055, 0.22), 'timber', C_DRIFT_PALE, 0.0, M=R('Y', 8.0))
        cbox(mb, (0.26, 0.74, -0.06), (0.44, 0.018, 0.12), 'iron', C_IRON_BRIGHT, 0.0, M=R('Y', -24.0))
        cbox(mb, (0.04, 0.76, -0.12), (0.12, 0.045, 0.09), 'timber', C_OAK_DEEP, 0.0, M=R('Y', -24.0))
        cbox(mb, (-0.34, 0.77, 0.02), (0.14, 0.085, 0.085), 'timber', C_OAK_DEEP, 0.0, M=R('Y', 32.0))
        _add_beam(mb, (-0.34, 0.76, 0.02), (-0.54, 0.74, 0.14), 0.032, 0.032, 'timber', C_OAK_SUN, 0.0)

    # 7. Rear (+Z) Boatyard Storytelling: Stacked Reserve Hull Planks, Tar Barrel & Tool Chest!
    STK_X, STK_Z = 0.88, 1.16
    STK_Y = _slip_y(STK_X)
    for bx_s in (-0.58, 0.58):
        cbox(mb, (STK_X + bx_s, STK_Y + 0.07, STK_Z), (0.14, 0.14, 0.56), 'timber', C_OAK_DEEP, 0.0)
    for layer in range(3):
        cbox(mb, (STK_X + 0.04 * (layer - 1), STK_Y + 0.18 + layer * 0.085, STK_Z + 0.02 * (layer % 2)),
             (1.62 - 0.08 * layer, 0.065, 0.44), 'timber',
             C_OAK_SUN if layer % 2 == 0 else C_DRIFT_PALE, 0.0, M=R('Z', SLOPE_DEG))
    # Tar/linseed coopered barrel + brass-clasped shipwright's tool chest on rear apron
    _build_powder_keg(mb, T(-0.68, _slip_y(-0.68) + 0.34, 1.18) @ R('Y', 24.0),
                      radius=0.26, height=0.68, rng=rng, stave_mat='timber',
                      col_a=C_OAK_RICH, col_b=C_OAK_DEEP, col_head=C_OAK_CHAR, segs=6)
    cbox(mb, (-1.46, WINCH_DECK_Y + 0.22, 1.06), (0.68, 0.40, 0.44), 'timber', C_OAK_RICH, 0.0, M=R('Y', 12.0))
    cbox(mb, (-1.46, WINCH_DECK_Y + 0.42, 1.06), (0.72, 0.08, 0.48), 'timber', C_OAK_DEEP, 0.0, M=R('Y', 12.0))
    cbox(mb, (-1.44, WINCH_DECK_Y + 0.34, 0.84), (0.10, 0.10, 0.05), 'brass', C_GOLD_BRIGHT, 0.0)

    # 8. Shipyard Work-Lantern Gallows Post, Warm Hanging Lantern ('Lantern_BoatSlipway') & Fluttering Flag!
    POST_X, POST_Z = -2.14, 1.02
    with xf(mb, T(POST_X, 0.0, POST_Z)):
        cyl(mb, 0.115, WINCH_DECK_Y - 0.08, 3.44, 6, 'timber', C_OAK_DEEP, False, 0.0, 0.082)
        cyl(mb, 0.140, WINCH_DECK_Y, WINCH_DECK_Y + 0.18, 6, 'iron', C_IRON_FORGED, False, 0.0)
        lathe(mb, [(0.0, 3.42), (0.095, 3.48), (0.0, 3.56)], 6, 'brass', C_GOLD_BRIGHT, False)
    # Forward projecting timber gallows arm & knee brace extending over the skiff bow & capstan
    ARM_END = Vector((-1.42, 2.86, -0.24))
    _add_beam(mb, (POST_X, 2.86, POST_Z), ARM_END + Vector((0.10, 0.0, -0.14)),
              0.10, 0.11, 'timber', C_OAK_RICH, 0.0)
    _add_beam(mb, (POST_X, 2.18, POST_Z), ARM_END.lerp(Vector((POST_X, 2.86, POST_Z)), 0.36),
              0.082, 0.086, 'timber', C_OAK_DEEP, 0.0)
    with xf(mb, T(POST_X, 2.86, POST_Z)):
        torus(mb, 0.125, 0.028, 5, 4, 'rope', C_ROPE, False)

    # Warm Hanging Work-Lantern suspended cleanly from gallows arm!
    LANTERN_POS = ARM_END + Vector((0.0, -0.44, 0.0))
    _add_beam(mb, ARM_END, LANTERN_POS + Vector((0.0, 0.28, 0.0)), 0.026, 0.026, 'iron', C_IRON_FORGED, 0.0)
    _build_storm_lantern(mb, LANTERN_POS, scale=0.86, brass_cage=True, hanging=True)

    # Fluttering Shipyard Swallowtail Flag ('paint' + UV2 wind sway!) flying from the post finial!
    _build_wind_pennant(
        mb, root_pos=(POST_X + 0.08, 3.24, POST_Z), length=1.34, h0=0.40,
        out_dir=(0.94, -0.03, -0.34),
        col_main=C_TEAL_HI, col_alt=C_CRIMSON_HI, col_trim=C_CREAM_SAIL, phase=0.48,
    )

    # 9. Coastal Beach Fern Tufts ('foliage' + UV2) tucked along seawall base corners
    for fpos, fsc, flean, fph in (
        ((-2.34, WINCH_DECK_Y - 0.14, -1.44), 0.72, (-0.7, 0.0, -0.7), 0.16),
        (( 2.26, _slip_y(2.26) - 0.02, -1.36), 0.68, ( 0.7, 0.0, -0.7), 0.44),
        ((-2.30, WINCH_DECK_Y - 0.14,  1.42), 0.74, (-0.7, 0.0,  0.7), 0.72),
        (( 2.24, _slip_y(2.24) - 0.02,  1.38), 0.70, ( 0.7, 0.0,  0.7), 0.93),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=4, rng=rng, phase=fph, lean_dir=flean, segs=2)

    build(mb)

    add_empty('Lantern_BoatSlipway', LANTERN_POS)
    col_piece('col_boatslipway_base', col_pts)
    export_landmark_glb(outdir, 'coastal_boatbuilder_slipway_winch.glb')


# ==============================================================================
# 4. VOLCANIC OBSIDIAN EMBER TOTEM (volcanic_obsidian_ember_totem.glb)
# ==============================================================================

def _build_tiki_fang(mb, base_pos, tip_pos, half_w=0.10, half_d=0.09, mat='basalt', col=C_OBSIDIAN_EDGE):
    """Sharp sculpted 4-sided carved obsidian tiki skull fang/tooth."""
    bp = Vector(base_pos)
    tp = Vector(tip_pos)
    ctr = (bp + tp) * 0.5
    p0 = bp + Vector((-half_w, 0.0, -half_d))
    p1 = bp + Vector(( half_w, 0.0, -half_d))
    p2 = bp + Vector(( half_w, 0.0,  half_d))
    p3 = bp + Vector((-half_w, 0.0,  half_d))
    for tri in ([p0, p1, tp], [p1, p2, tp], [p2, p3, tp], [p3, p0, tp]):
        mb.fp(tri, mat, col, (0, 1, 0), ctr, smooth=False)
    mb.fp([p3, p2, p1, p0], mat, mul(col, 0.78), (1, 0, 0), ctr, smooth=False)


def gen_volcanic_obsidian_ember_totem(outdir):
    """Towering carved jagged obsidian & dark-basalt pirate-tiki skull fire totem (~3.8 m W x 3.8 m D x
    6.5 m H, -3.50 m deep magma-cracked basalt pedestal) with fierce angular carved brow & cheek ridges,
    blazing molten magma mouth & eye cavities ('glass' material w/ glowing orange-amber COLOR_0, NOT
    'skull_glow'!), iron chains & spiked forged-iron magma-crown fire bowl atop the head, convex
    collider 'col_embertotem_base', and empty 'Lantern_EmberTotem'."""
    clear_scene()
    mb = MB('volcanic_obsidian_ember_totem', seed=1904)
    rng = random.Random(SEED + 1904)
    col_pts = []

    DECK_Y = 0.82

    # 1. Deep Magma-Cracked Hexagonal Basalt Pedestal plunging cleanly to y = -3.50 m (~3.8 m W x 3.8 m D)
    ped_secs = [
        _reg_poly(0.0, -3.50, 0.0, 1.92, sides=6, rot_deg=30.0),
        _reg_poly(0.0, -1.55, 0.0, 1.88, sides=6, rot_deg=30.0),
        _reg_poly(0.0,  0.00, 0.0, 1.80, sides=6, rot_deg=30.0),
        _reg_poly(0.0,  0.46, 0.0, 1.70, sides=6, rot_deg=30.0),
    ]
    _loft_horizontal_masonry(
        mb, ped_secs, 'basalt',
        [C_OBSIDIAN_ABYSS, C_OBSIDIAN_DARK, C_OBSIDIAN_MID, C_OBSIDIAN_HI],
        rng, caps=(True, True), top_mat='basalt', top_col=C_OBSIDIAN_MID,
    )
    dais_secs = [
        _reg_poly(0.0, 0.44,   0.0, 1.44, sides=6, rot_deg=0.0),
        _reg_poly(0.0, DECK_Y, 0.0, 1.32, sides=6, rot_deg=0.0),
    ]
    _loft_horizontal_masonry(
        mb, dais_secs, 'basalt',
        [C_OBSIDIAN_MID, C_OBSIDIAN_HI],
        rng, caps=(False, True), top_mat='basalt', top_col=C_OBSIDIAN_MID,
    )

    for yc, rc in ((-3.50, 1.92), (0.0, 1.80), (DECK_Y, 1.48), (5.55, 1.34)):
        col_pts.extend(_reg_poly(0.0, yc, 0.0, rc, sides=6, rot_deg=30.0))

    # Radiating Molten Magma Cracks ('glass'!) burning across the stepped basalt pedestal!
    for c_ang in (-150.0, -90.0, -30.0, 30.0, 90.0, 150.0):
        ar = radians(c_ang)
        ca, sa = cos(ar), sin(ar)
        p0 = Vector((0.52 * ca, DECK_Y + 0.03, 0.52 * sa))
        p1 = Vector((1.14 * ca - 0.10 * sa, DECK_Y + 0.02, 1.14 * sa + 0.10 * ca))
        p2 = Vector((1.66 * ca, 0.48, 1.66 * sa))
        _sculpt_magma_ribbon(
            mb, [p0, p1, p2], [0.11, 0.095, 0.062], (0.0, 1.0, 0.0),
            hot_core=True, ridge_h=0.040, mat='glass',
            c_core=C_FLAME_MID, c_mid_col=C_FLAME_DEEP, c_edge_col=C_MAGMA_CRIMSON, c_tip_col=C_MAGMA_CRIMSON,
        )

    # 2. Lower Carved Obsidian Pirate-Tiki Torso Pillar (y = 0.78 to 2.74 m)
    torso_secs = [
        _rect_oct(0.0, 0.76, 0.0, 1.06, 0.94, 0.28),
        _rect_oct(0.0, 1.46, 0.0, 0.92, 0.84, 0.24),
        _rect_oct(0.0, 2.16, 0.0, 0.84, 0.78, 0.22),
        _rect_oct(0.0, 2.74, 0.0, 0.94, 0.86, 0.24),
    ]
    _loft_horizontal_masonry(
        mb, torso_secs, 'basalt',
        [C_OBSIDIAN_DARK, C_OBSIDIAN_MID, C_OBSIDIAN_HI, C_OBSIDIAN_HI],
        rng, caps=(False, True),
    )

    # Heavy Riveted Forged-Iron Waist Binding Collar hugging the Totem Pillar
    with xf(mb, T(0.0, 2.20, 0.0)):
        cbox(mb, (0.0, 0.0, 0.0), (1.84, 0.16, 1.68), 'iron', C_IRON_FORGED, 0.03)
        for sx in (-0.86, 0.86):
            for sz in (-0.78, 0.78):
                cbox(mb, (sx, 0.0, sz), (0.12, 0.20, 0.12), 'iron', C_IRON_RUST_HI, 0.0)

    # Carved Angular Pirate-Tiki Crossed-Bone / Tribal Chevron Reliefs & Glowing Magma Runes on Front & Rear Torso!
    for z_sgn in (-1.0, 1.0):
        fz = z_sgn * 0.86
        # Crossed obsidian tiki-bone relief bars framing a glowing molten diamond heart
        _add_beam(mb, (-0.56, 1.04, fz), (0.56, 1.88, fz), 0.14, 0.12, 'basalt', C_OBSIDIAN_EDGE, 0.0)
        _add_beam(mb, ( 0.56, 1.04, fz), (-0.56, 1.88, fz), 0.14, 0.12, 'basalt', C_OBSIDIAN_EDGE, 0.0)
        cbox(mb, (0.0, 1.46, fz + z_sgn * 0.04), (0.28, 0.28, 0.10), 'glass', C_FLAME_DEEP, 0.0, M=R('Z', 45.0))
        cbox(mb, (0.0, 1.46, fz + z_sgn * 0.07), (0.14, 0.14, 0.08), 'glass', C_FLAME_CORE, 0.0, M=R('Z', 45.0))
        # Vertical glowing magma channel rising from pedestal into the jaw throat
        _sculpt_magma_ribbon(
            mb, [(0.0, 0.86, fz + z_sgn * 0.02), (0.0, 1.98, fz - z_sgn * 0.04), (0.0, 2.66, fz + z_sgn * 0.01)],
            [0.085, 0.072, 0.080], (0.0, 0.0, z_sgn), hot_core=False, ridge_h=0.036, mat='glass',
            c_core=C_FLAME_MID, c_mid_col=C_FLAME_DEEP, c_edge_col=C_MAGMA_CRIMSON, c_tip_col=C_MAGMA_CRIMSON,
        )

    # Flanking Jagged Basalt Shoulder Fins jutting along +-X
    for sgn in (-1.0, 1.0):
        sh_pts = [
            Vector((sgn * 0.84, 1.62, 0.0)),
            Vector((sgn * 1.24, 1.96, 0.0)),
            Vector((sgn * 1.48, 2.38, -0.06)),
        ]
        tube(mb, sh_pts, [0.24, 0.18, 0.04], 5, 'basalt', C_OBSIDIAN_HI, caps=(False, True), mode='flat',
             scols=[C_OBSIDIAN_DARK, C_OBSIDIAN_HI, C_OBSIDIAN_EDGE])

    # 3. Colossal Carved Jagged Obsidian Pirate-Tiki Skull Head (y = 2.68 to 5.26 m!)
    head_secs = [
        _rect_oct(0.0, 2.68, 0.06, 1.00, 0.90, 0.24),
        _rect_oct(0.0, 3.62, 0.04, 1.14, 0.96, 0.28),
        _rect_oct(0.0, 4.54, 0.02, 1.18, 0.98, 0.28),
        _rect_oct(0.0, 5.26, 0.04, 1.04, 0.90, 0.26),
    ]
    _loft_horizontal_masonry(
        mb, head_secs, 'basalt',
        [C_OBSIDIAN_DARK, C_OBSIDIAN_MID, C_OBSIDIAN_HI, C_OBSIDIAN_EDGE],
        rng, caps=(False, True),
    )

    # --- A. Blazing Molten Magma Mouth Cavity & Interlocking Carved Obsidian Tiki Fangs (Hero -Z face!) ---
    # Deep glowing molten lava throat plates ('glass' ONLY — rich volcanic orange-amber gradient!)
    cbox(mb, (0.0, 3.24, -0.84), (1.42, 0.72, 0.18), 'glass', C_MAGMA_CRIMSON, 0.0)
    cbox(mb, (0.0, 3.24, -0.88), (1.16, 0.50, 0.14), 'glass', C_FLAME_DEEP, 0.0)
    cbox(mb, (0.0, 3.24, -0.91), (0.82, 0.28, 0.10), 'glass', C_FLAME_MID, 0.0)

    # Heavy protruding carved obsidian lower jaw lip & upper maxilla lip framing the blazing magma maw!
    cbox(mb, (0.0, 2.82, -0.96), (1.68, 0.24, 0.34), 'basalt', C_OBSIDIAN_EDGE, 0.03)
    cbox(mb, (0.0, 3.66, -0.98), (1.76, 0.24, 0.36), 'basalt', C_OBSIDIAN_EDGE, 0.03)
    for sgn in (-1.0, 1.0):
        cbox(mb, (sgn * 0.82, 3.24, -0.94), (0.28, 0.88, 0.34), 'basalt', C_OBSIDIAN_HI, 0.02)

    # 9 Fierce Interlocking Carved Angular Obsidian Tiki Fangs biting across the blazing magma mouth!
    for fx_u, fl_u in ((-0.54, 0.34), (-0.28, 0.28), (0.0, 0.32), (0.28, 0.28), (0.54, 0.34)):
        _build_tiki_fang(mb, (fx_u, 3.58, -1.03), (fx_u * 0.96, 3.58 - fl_u, -1.07),
                         half_w=0.105, half_d=0.095, mat='basalt', col=C_OBSIDIAN_EDGE)
    for fx_d, fl_d in ((-0.42, 0.30), (-0.14, 0.26), (0.14, 0.26), (0.42, 0.30)):
        _build_tiki_fang(mb, (fx_d, 2.90, -1.03), (fx_d * 0.98, 2.90 + fl_d, -1.07),
                         half_w=0.10, half_d=0.09, mat='basalt', col=C_OBSIDIAN_EDGE)

    # --- B. Sculpted Angular Cheekbone Ridges & Chiseled Tribal Tiki Nose Bridge ---
    for sgn in (-1.0, 1.0):
        _add_beam(mb, (sgn * 0.34, 3.74, -1.06), (sgn * 1.12, 4.02, -0.82),
                  0.24, 0.26, 'basalt', C_OBSIDIAN_EDGE, 0.03)
        _add_beam(mb, (sgn * 1.06, 4.02, -0.82), (sgn * 0.98, 3.36, -0.88),
                  0.22, 0.24, 'basalt', C_OBSIDIAN_HI, 0.02)

    nose_secs = [
        [(-0.28, 3.74, -0.94), (0.28, 3.74, -0.94), (0.18, 3.74, -1.24), (-0.18, 3.74, -1.24)],
        [(-0.22, 4.18, -0.94), (0.22, 4.18, -0.94), (0.12, 4.18, -1.20), (-0.12, 4.18, -1.20)],
        [(-0.18, 4.54, -0.94), (0.18, 4.54, -0.94), (0.10, 4.54, -1.14), (-0.10, 4.54, -1.14)],
    ]
    loft(mb, nose_secs, 'basalt', C_OBSIDIAN_EDGE, closed=True, caps=(True, True), mode='flat',
         scols=[C_OBSIDIAN_HI, C_OBSIDIAN_EDGE, C_OBSIDIAN_EDGE])
    for sgn in (-1.0, 1.0):
        cbox(mb, (sgn * 0.12, 3.84, -1.21), (0.075, 0.14, 0.06), 'glass', C_FLAME_DEEP, 0.0)

    # --- C. Fierce V-Angled Overhanging Brow Ridges & Blazing Molten Magma Eye Cavities ('glass'!) ---
    for sgn in (-1.0, 1.0):
        ex, ey = sgn * 0.54, 4.24
        cbox(mb, (ex, ey, -0.92), (0.58, 0.44, 0.16), 'basalt', C_OBSIDIAN_ABYSS, 0.0)
        cbox(mb, (ex, ey, -0.97), (0.44, 0.28, 0.12), 'glass', C_MAGMA_CRIMSON, 0.0, M=R('Z', -sgn * 16.0))
        cbox(mb, (ex, ey, -1.01), (0.32, 0.18, 0.10), 'glass', C_FLAME_DEEP, 0.0, M=R('Z', -sgn * 16.0))
        cbox(mb, (ex, ey, -1.04), (0.18, 0.10, 0.08), 'glass', C_FLAME_CORE, 0.0, M=R('Z', -sgn * 16.0))

        _add_beam(mb, (sgn * 0.06, 4.44, -1.16), (sgn * 1.18, 4.76, -0.92),
                  0.30, 0.34, 'basalt', C_OBSIDIAN_EDGE, 0.03)
        _add_beam(mb, (sgn * 1.12, 4.74, -0.84), (sgn * 0.94, 5.18, -0.58),
                  0.22, 0.24, 'basalt', C_OBSIDIAN_HI, 0.02)

    # Scorched Forged-Iron Pirate Brow-Band & Forehead Skull-Spike Plate riveted across the forehead!
    cbox(mb, (0.0, 4.94, 0.02), (2.22, 0.18, 1.94), 'iron', C_IRON_FORGED, 0.02)
    cbox(mb, (0.0, 4.92, -0.98), (0.34, 0.34, 0.14), 'iron', C_IRON_RUST_HI, 0.0, M=R('Z', 45.0))
    cbox(mb, (0.0, 4.92, -1.04), (0.16, 0.16, 0.08), 'glass', C_FLAME_MID, 0.0, M=R('Z', 45.0))

    # --- D. Carved Flanking Tiki Totem Ear-Wings (w/ Forged-Iron Pirate Ear-Rings!) & Rear Dorsal Spines ---
    for sgn in (-1.0, 1.0):
        cbox(mb, (sgn * 1.24, 4.02, 0.04), (0.42, 1.38, 0.38), 'basalt', C_OBSIDIAN_HI, 0.03)
        cbox(mb, (sgn * 1.48, 4.18, 0.04), (0.28, 0.88, 0.26), 'basalt', C_OBSIDIAN_EDGE, 0.02)
        cbox(mb, (sgn * 1.30, 4.02, -0.14), (0.18, 0.62, 0.08), 'glass', C_FLAME_DEEP, 0.0)
        with xf(mb, T(sgn * 1.42, 3.24, 0.04) @ M_Y2Z):
            torus(mb, 0.22, 0.048, 8, 4, 'iron', C_IRON_BRIGHT, False)

    # Rear (+Z) Jagged Obsidian Dorsal Spine Crests & Glowing Molten Spine Vein so Rear 3/4 is Fierce!
    for sy_sp, sp_l, sp_r in ((2.94, 0.56, 0.16), (3.62, 0.68, 0.18), (4.30, 0.72, 0.18), (4.94, 0.60, 0.16)):
        bp = Vector((0.0, sy_sp, 0.86))
        tube(mb, [bp, bp + Vector((0.0, 0.18, sp_l * 0.55)), bp + Vector((0.0, 0.34, sp_l))],
             [sp_r, sp_r * 0.62, 0.022], 5, 'basalt', C_OBSIDIAN_EDGE, caps=(False, True), mode='flat',
             scols=[C_OBSIDIAN_MID, C_OBSIDIAN_HI, C_OBSIDIAN_EDGE])
    _sculpt_magma_ribbon(
        mb, [(0.0, 2.74, 0.94), (0.14, 3.44, 0.96), (-0.12, 4.20, 0.97), (0.0, 5.02, 0.94)],
        [0.09, 0.10, 0.095, 0.075], (0.0, 0.0, 1.0), hot_core=False, ridge_h=0.040, mat='glass',
        c_core=C_FLAME_MID, c_mid_col=C_FLAME_DEEP, c_edge_col=C_MAGMA_CRIMSON, c_tip_col=C_MAGMA_CRIMSON,
    )

    # 4. Spiked Forged-Iron Magma-Crown Fire Bowl Atop the Head (y = 5.20 to 6.54 m!)
    BOWL_Y = 5.22
    with xf(mb, T(0.0, BOWL_Y, 0.04)):
        bowl_prof = [
            (0.00, 0.00),
            (0.96, 0.00),
            (1.14, 0.24),
            (1.26, 0.54),
            (1.12, 0.58),
            (0.92, 0.34),
            (0.00, 0.30),
        ]
        lathe(mb, bowl_prof, 8, 'iron', C_IRON_FORGED, False, False,
              lambda i, k: C_IRON_RUST_HI if i in (2, 3) else C_IRON_FORGED)
        torus(mb, 1.24, 0.068, 8, 4, 'iron', C_IRON_BRIGHT, False)
        with xf(mb, T(0.0, 0.52, 0.0)):
            torus(mb, 1.24, 0.062, 8, 4, 'iron', C_IRON_RUST_HI, False)

        # 8 Dramatic Tall Upward-Flaring Spiked Forged-Iron Magma-Crown Prongs (reaching y = 6.50 m!)
        for k in range(8):
            ang = radians(k * 45.0)
            is_card = (k % 2 == 0)
            ca, sa = cos(ang), sin(ang)
            sh_h = 0.80 if is_card else 0.54
            sp_pts = [
                Vector((1.16 * ca, 0.46, 1.16 * sa)),
                Vector((1.28 * ca, 0.46 + sh_h * 0.55, 1.28 * sa)),
                Vector((1.40 * ca, 0.46 + sh_h, 1.40 * sa)),
            ]
            tube(mb, sp_pts, [0.115 if is_card else 0.09, 0.072, 0.016], 4, 'iron',
                 C_IRON_BRIGHT if is_card else C_IRON_RUST_HI, caps=(False, True), mode='flat')

        # Blazing Sculpted Molten Magma Coals & Upward-Licking Ember Flame Tongues inside the Crown Bowl ('glass'!)
        lathe(mb, [(0.0, 0.30), (0.94, 0.36), (0.82, 0.54), (0.48, 0.66), (0.0, 0.72)],
              8, 'glass', C_FLAME_DEEP, False, False,
              lambda i, k: C_FLAME_CORE if i >= 3 else (C_FLAME_MID if i == 2 else C_MAGMA_CRIMSON))
        # Central sculpted molten flame-tongue crown + 3 dancing satellite licks (peaking at y ~ 6.52 m!)
        for fx_f, fz_f, fh_f, fr_f, fcol_top in (
            ( 0.00,  0.00, 0.86, 0.34, C_FLAME_CORE),
            (-0.40, -0.28, 0.68, 0.21, C_FLAME_MID),
            ( 0.42, -0.24, 0.66, 0.21, C_FLAME_MID),
            ( 0.02,  0.38, 0.70, 0.21, C_FLAME_DEEP),
        ):
            fl_pts = [
                Vector((fx_f, 0.44, fz_f)),
                Vector((fx_f * 0.82, 0.44 + fh_f * 0.52, fz_f * 0.82)),
                Vector((fx_f * 0.55 + 0.05, 0.44 + fh_f, fz_f * 0.55)),
            ]
            tube(mb, fl_pts, [fr_f, fr_f * 0.58, 0.022], 5, 'glass', C_FLAME_MID,
                 caps=(False, True), mode='flat', scols=[C_FLAME_DEEP, fcol_top, C_MAGMA_CRIMSON])

    # 5. Four Deeply Grounded Hexagonal Basalt Anchor Spurs & Bolted Forged-Iron Restraining Chains!
    spur_cfg = [
        (-1.38, -0.92, 2.08, 0.32, -13.0, -9.0, Vector((-1.14, BOWL_Y + 0.16, -0.46))),
        ( 1.38, -0.92, 2.08, 0.32,  13.0, -9.0, Vector(( 1.14, BOWL_Y + 0.16, -0.46))),
        (-1.36,  0.96, 2.18, 0.33, -13.0, 10.0, Vector((-1.12, BOWL_Y + 0.16,  0.54))),
        ( 1.36,  0.96, 2.18, 0.33,  13.0, 10.0, Vector(( 1.12, BOWL_Y + 0.16,  0.54))),
    ]
    for sx_b, sz_b, sh_s, sr_s, tilt_x, tilt_z, top_shackle in spur_cfg:
        s_dir = Vector((sin(radians(tilt_x)), 1.0, sin(radians(tilt_z)))).normalized()
        # Base buried solidly inside the stepped basalt pedestal (y = -0.35 m) -> ZERO floating edges!
        bp = Vector((sx_b, -0.35, sz_b))
        sp_pts = [bp, bp + s_dir * (sh_s * 0.54), bp + s_dir * (sh_s * 0.86), bp + s_dir * sh_s]
        tube(mb, sp_pts, [sr_s * 1.08, sr_s * 0.80, sr_s * 0.48, 0.028], 5, 'basalt', C_OBSIDIAN_HI,
             caps=(False, True), mode='flat',
             scols=[C_OBSIDIAN_DARK, C_OBSIDIAN_MID, C_OBSIDIAN_HI, C_OBSIDIAN_EDGE])
        bot_shackle = sp_pts[1] + Vector((0.0, 0.38, 0.0))
        with xf(mb, T(bot_shackle)):
            cyl(mb, sr_s * 0.86, -0.09, 0.09, 6, 'iron', C_IRON_BRIGHT, False, 0.0)
        # Heavy forged-iron crown shackle lug bolted cleanly onto the outer fire bowl wall!
        cbox(mb, top_shackle, (0.24, 0.22, 0.22), 'iron', C_IRON_RUST_HI, 0.0)
        # Taut interlocking forged-iron restraining chain from Magma-Crown Lug down to Basalt Spur!
        _add_chain_links(
            mb, top_shackle + Vector((0.0, -0.06, 0.0)), bot_shackle + Vector((0.0, 0.10, 0.0)),
            n_links=7, link_r=0.19, wire_r=0.052, segs=5, psegs=4, sag=0.20,
            mat='iron', rust_stride=2, stretch_y=1.42,
            col_a=C_IRON_BRIGHT, col_b=C_IRON_RUST_HI,
            glow_indices=None,
        )

    # Lantern_EmberTotem empty centered in the blazing spiked magma-crown fire bowl!
    LANTERN_POS = Vector((0.0, 5.84, -0.04))

    build(mb)

    add_empty('Lantern_EmberTotem', LANTERN_POS)
    col_piece('col_embertotem_base', col_pts)
    export_landmark_glb(outdir, 'volcanic_obsidian_ember_totem.glb')


FRONTIER_CRAFT_GENERATORS = [
    gen_pirate_powder_magazine_bunker,
    gen_ancient_coral_leviathan_altar,
    gen_coastal_boatbuilder_slipway_winch,
    gen_volcanic_obsidian_ember_totem,
]
