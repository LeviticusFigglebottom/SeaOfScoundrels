# Sea of Scoundrels: 4 sculpted 3D Armada Relics & Maritime Industry Landmarks
# (Wave I-20 / Pass I-Q13 — Historic 82-Landmark Zero-Extra-VRAM Fleet!).
# Imported by tools/blender/gen_island_landmarks.py.
# Authored in Godot game coordinates (-Z seaward/hero-facing, +Y up, +X starboard, metres)
# and converted to Blender's Z-up frame on mesh creation via _landmark_common.
# STRICT SHARED-TEXTURE DEDUP CONTRACT: uses ONLY the 11 existing shared PBR materials
# (limestone, limestone_moss, basalt, temple_stone, skull_stone, timber, paint, rope,
# iron, brass, foliage) + untextured glass / skull_glow / col.
# Emissive rule:
#   - mat_landmark_skull_glow ONLY on ancient_tidal_compass_sanctum (cyan-turquoise crystal
#     compass needle, aquatic rune ring, and obelisk glyphs)
#   - mat_landmark_glass with warm amber/molten linear COLOR_0 on pirate_ropewalk_cordage_loom,
#     coastal_buccaneer_careening_cradle, and volcanic_obsidian_kraken_altar (ZERO skull_glow!).
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

# Coastal harbour cobble, seawall sandstone & mossy sanctuary masonry
C_SANDSTONE_HI   = srgb('#ead7b2')
C_SANDSTONE_MID  = srgb('#c8a478')
C_SANDSTONE_DARK = srgb('#8c6f51')
C_SANDSTONE_DEEP = srgb('#564739')
C_COBBLE_HI      = srgb('#d0c4ad')
C_COBBLE_MID     = srgb('#948977')
C_COBBLE_DARK    = srgb('#5e564d')
C_COBBLE_WET     = srgb('#3f3e39')

C_SANCTUM_HI     = srgb('#d4ccb5')
C_SANCTUM_MID    = srgb('#99937f')
C_SANCTUM_DARK   = srgb('#625f51')
C_SANCTUM_DEEP   = srgb('#424239')
C_MOSS_CUSHION   = srgb('#4b7f30')
C_MOSS_DEEP      = srgb('#2b5021')

# Harbour oak, weathered driftwood & caulking pitch
C_OAK_SUN        = srgb('#c4894c')
C_OAK_RICH       = srgb('#87552c')
C_OAK_DEEP       = srgb('#50311a')
C_OAK_CHAR       = srgb('#352217')
C_DRIFT_PALE     = srgb('#d7c8ae')
C_DRIFT_MID      = srgb('#9d8b72')
C_DRIFT_DARK     = srgb('#645646')
C_PITCH_TAR      = srgb('#18161b')

# Bold buccaneer guild paints & cordage hemp
C_CRIMSON_HI     = srgb('#d62e21')
C_CRIMSON_MID    = srgb('#991e16')
C_CRIMSON_DARK   = srgb('#5e120e')
C_TEAL_HI        = srgb('#228489')
C_TEAL_MID       = srgb('#196065')
C_TEAL_DARK      = srgb('#123d41')
C_CREAM_SAIL     = srgb('#f2e4c6')
C_CREAM_AGED     = srgb('#cbb58d')
C_HEMP_HI        = srgb('#dfc088')
C_HEMP_MID       = srgb('#be995d')
C_HEMP_DARK      = srgb('#8c6c3b')

# Metals: gilded bronze, burnished brass, verdigris bronze, forged & rusted iron
C_GOLD_BRIGHT    = srgb('#fad24f')
C_BRASS_WARM     = srgb('#daa339')
C_BRASS_DARK     = srgb('#8d621f')
C_VERDIGRIS_HI   = srgb('#56bba3')
C_VERDIGRIS_MID  = srgb('#318774')
C_IRON_BRIGHT    = srgb('#80899a')
C_IRON_FORGED    = srgb('#4b5160')
C_IRON_DARK      = srgb('#262933')
C_IRON_RUST_HI   = srgb('#b36135')
C_IRON_RUST_MID  = srgb('#7e4223')

# Volcanic charred basalt & high-contrast faceted obsidian
C_OBSIDIAN_EDGE  = srgb('#9990a8')
C_OBSIDIAN_HI    = srgb('#6b6379')
C_OBSIDIAN_MID   = srgb('#433d4e')
C_OBSIDIAN_DARK  = srgb('#272330')
C_OBSIDIAN_ABYSS = srgb('#14121a')

# Luminous cyan-turquoise aquatic sanctum glow (USED ONLY with 'skull_glow' on ancient_tidal_compass_sanctum!)
C_AQUA_CORE      = srgb('#70fff3')
C_AQUA_MID       = srgb('#16dac0')
C_AQUA_DEEP      = srgb('#088a80')

# Warm amber lantern & molten volcanic lava (USED ONLY with 'glass' on the other 3 GLBs!)
C_FLAME_WHITE    = srgb('#ffd754')
C_FLAME_CORE     = srgb('#ff8716')
C_FLAME_MID      = srgb('#ed4206')
C_FLAME_DEEP     = srgb('#aa1802')
C_MAGMA_CRIMSON  = srgb('#690a02')

# Tropical coastal vines & beach ferns
C_VINE_DARK      = srgb('#184d1f')
C_VINE_MID       = srgb('#317b28')
C_VINE_SUN       = srgb('#84c62d')


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


def _rect_quad(cx, y, cz, hx, hz):
    """Crisp 4-vertex horizontal rectangular ring at height y."""
    return [
        (cx - hx, y, cz - hz),
        (cx + hx, y, cz - hz),
        (cx + hx, y, cz + hz),
        (cx - hx, y, cz + hz),
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


def _build_coopered_barrel(mb, M_bar, radius=0.28, height=0.68, rng=None,
                           col_a=C_OAK_RICH, col_b=C_OAK_DEEP, col_head=C_PITCH_TAR, segs=6):
    """Coopered oak harbour pitch/tar barrel with forged-iron hoops and glossy dark tar surface."""
    hh = height * 0.5
    prof = [
        (0.0,           -hh),
        (radius * 0.82, -hh),
        (radius,         0.0),
        (radius * 0.84,  hh),
        (radius * 0.72,  hh),
        (radius * 0.72,  hh - 0.06),
        (0.0,            hh - 0.06),
    ]
    stave_cols = [
        jit(col_a if k % 2 == 0 else col_b, rng, 0.04, 0.012) if rng else col_a
        for k in range(segs)
    ]
    with xf(mb, M_bar):
        lathe(mb, prof, segs, 'timber', col_a, False, False,
              lambda i, k: col_head if i >= 5 else (C_OAK_CHAR if i in (0, 3, 4) else stave_cols[k]))
        for hy, hr, hcol in (
            (-hh * 0.62, radius * 0.94, C_IRON_FORGED),
            ( hh * 0.64, radius * 0.95, C_IRON_RUST_HI),
        ):
            cyl(mb, hr, hy - 0.026, hy + 0.026, segs, 'iron', hcol, False, 0.0)


def _build_rope_coil(mb, center, radius=0.28, turns=3, r=0.044, segs=6, psegs=4,
                     col_a=C_HEMP_HI, col_b=C_HEMP_MID):
    """Stacked coiled braided anchor hawser pile ('rope')."""
    for i in range(turns):
        rr = radius * (1.0 - 0.18 * i)
        with xf(mb, T(center[0], center[1] + r * (1.0 + i * 1.60), center[2])):
            torus(mb, rr, r, segs, psegs, 'rope', col_a if i % 2 == 0 else col_b, True)


def _build_wind_banner(mb, root_pos, length=1.42, h0=0.42, out_dir=(0.94, -0.03, -0.34),
                       col_main=C_CRIMSON_HI, col_alt=C_CREAM_SAIL, col_trim=C_GOLD_BRIGHT,
                       phase=0.28, swallowtail=True):
    """Wind-whipped double-sided striped guild banner or burgee ('paint') with UV2 wind weights."""
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
        wave = sin(t * 2.15 * pi) * 0.14 * t
        droop = -0.12 * t * t
        hh = h0 * (1.0 - (0.38 if swallowtail else 0.72) * t)
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
        if i == segs - 1 and swallowtail:
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

    n_leaves = max(5, int(length * 2.2))
    for li in range(n_leaves):
        t = (li + 0.30) / float(n_leaves + 0.20)
        idx_f = t * segs
        i0 = min(segs - 1, int(idx_f))
        frac = idx_f - i0
        root = stem_pts[i0].lerp(stem_pts[i0 + 1], frac)
        sgn = -1.0 if (li % 2 == 0) else 1.0
        l_scale = (0.82 + 0.44 * sin(t * pi * 0.85)) * (1.0 - 0.26 * t)
        l_len = width * 1.50 * l_scale * rng.uniform(0.88, 1.12)
        l_wid = width * 0.64 * l_scale * rng.uniform(0.88, 1.12)
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


def _add_coastal_fern_cluster(mb, root_pos, scale=0.72, n_fronds=3, rng=None, phase=0.0,
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


def _sculpt_glow_ribbon(mb, path_pts, widths, surface_nrm, hot_core=True, ridge_h=0.040, mat='glass',
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
        mid_pts.append(pts[i] + nrm * (ridge_h + 0.006 * sin(i * 1.7)))
    for i in range(n - 1):
        cm = c_core if (hot_core and i <= n // 2) else c_mid_col
        ce = c_edge_col if i < n - 2 else c_tip_col
        inside = (pts[i] + pts[i + 1]) * 0.5 - nrm * 0.5
        mb.fp([left_pts[i], mid_pts[i], mid_pts[i + 1], left_pts[i + 1]], mat,
              [ce, cm, cm, ce], (1, 0, 0), inside, smooth=False)
        mb.fp([mid_pts[i], right_pts[i], right_pts[i + 1], mid_pts[i + 1]], mat,
              [cm, ce, ce, cm], (1, 0, 0), inside, smooth=False)


def _add_chain_links(mb, p_start, p_end, n_links=4, link_r=0.20, wire_r=0.056,
                     segs=5, psegs=4, sag=0.18, mat='iron', rust_stride=2, stretch_y=1.46,
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
# 1. PIRATE ROPEWALK CORDAGE LOOM (pirate_ropewalk_cordage_loom.glb)
# ==============================================================================

def _build_serving_mallet(mb, M_mallet, scale=1.0):
    """Distinctive nautical T-shaped wooden ropewalker's serving mallet with brass ferrule."""
    s = scale
    with xf(mb, M_mallet):
        with xf(mb, T(0.0, 0.06 * s, 0.0) @ M_Y2X):
            cyl(mb, 0.065 * s, -0.14 * s, 0.14 * s, 5, 'timber', C_OAK_RICH, False, 0.0)
            cyl(mb, 0.072 * s, -0.11 * s,  0.11 * s, 5, 'brass', C_BRASS_WARM, False, 0.0)
        with xf(mb, T(0.0, 0.06 * s, 0.0) @ M_Y2Z):
            cyl(mb, 0.028 * s, 0.02 * s, 0.34 * s, 5, 'timber', C_OAK_SUN, False, 0.0, 0.032 * s)


def _build_spoked_gear_wheel(mb, center, radius=0.72, n_spokes=8, n_teeth=8):
    """Chunky nautical spoked wooden spinning & geared cordage wheel facing -Z/+Z (X-Y plane)."""
    cx, cy, cz = center
    with xf(mb, T(cx, cy, cz)):
        with xf(mb, M_Y2Z):
            torus(mb, radius, 0.056, 9, 4, 'timber', C_OAK_RICH, False)
            torus(mb, radius + 0.044, 0.022, 9, 4, 'iron', C_IRON_FORGED, False)
            cyl(mb, 0.14, -0.10, 0.10, 6, 'timber', C_OAK_DEEP, False, 0.0)
            cyl(mb, 0.085, -0.14, 0.14, 6, 'brass', C_GOLD_BRIGHT, False, 0.0)
            cyl(mb, radius * 0.42, 0.08, 0.16, 6, 'brass', C_BRASS_WARM, False, 0.0)
        for k in range(n_spokes):
            ang = 2.0 * pi * k / float(n_spokes)
            ca, sa = cos(ang), sin(ang)
            _add_beam(mb, (0.10 * ca, 0.10 * sa, 0.0), ((radius - 0.02) * ca, (radius - 0.02) * sa, 0.0),
                      0.048, 0.042, 'timber', C_OAK_SUN if k % 2 == 0 else C_OAK_RICH, 0.0)
        for k in range(n_teeth):
            ang = 2.0 * pi * k / float(n_teeth)
            ca, sa = cos(ang), sin(ang)
            cbox(mb, ((radius * 0.45) * ca, (radius * 0.45) * sa, 0.12),
                 (0.082, 0.062, 0.072), 'brass', C_GOLD_BRIGHT, 0.0, M=R('Z', degrees(ang)))
        h_ang = radians(38.0)
        hx, hy = (radius * 0.80) * cos(h_ang), (radius * 0.80) * sin(h_ang)
        with xf(mb, T(hx, hy, 0.0) @ M_Y2Z):
            cyl(mb, 0.036, -0.26, 0.02, 5, 'timber', C_OAK_SUN, False, 0.0, 0.028)
            cyl(mb, 0.048, -0.27, -0.22, 5, 'brass', C_GOLD_BRIGHT, False, 0.0)


def _build_iron_hook(mb, pos, dir_x=1.0, scale=1.0):
    """Chunky forged-iron ropewalk twisting hook extending along dir_x * X."""
    s = scale
    px, py, pz = pos
    with xf(mb, T(px, py, pz)):
        h_pts = [
            Vector((-0.02 * s * dir_x,  0.00,     0.0)),
            Vector(( 0.14 * s * dir_x, -0.03 * s, 0.0)),
            Vector(( 0.25 * s * dir_x,  0.02 * s, 0.0)),
            Vector(( 0.18 * s * dir_x,  0.09 * s, 0.0)),
        ]
        tube(mb, h_pts, [0.030 * s, 0.025 * s, 0.020 * s, 0.012 * s], 4, 'iron', C_IRON_FORGED,
             caps=(True, True), mode='flat')


def gen_pirate_ropewalk_cordage_loom(outdir):
    """Open-air harbour timber ropewalk & cordage twisting loom (~5.4 m W x 3.8 m D x 3.8 m H,
    -2.80 m deep cobble-and-ashlar wharf skirt) with twin braced oak trestles, spoked geared
    spinning wheel, taut braided hemp strands stretched between iron hooks through a grooved
    laying cone, stacked coils of coiled anchor hawser, pitch barrel & wooden serving mallets,
    fluttering red-cream guild banner (UV2 wind sway), convex collider 'col_ropewalk_base',
    and warm brass work-lantern empty 'Lantern_Ropewalk'."""
    clear_scene()
    mb = MB('pirate_ropewalk_cordage_loom', seed=2001)
    rng = random.Random(SEED + 2001)
    col_pts = []

    DECK_Y = 0.44
    LOOM_Z = 0.24

    # 1. Deep Harbour Cobble-and-Sandstone Wharf Skirt plunging cleanly to y = -2.80 m (~5.4 m W x 3.8 m D)
    found_secs = [
        _rect_oct(0.0, -2.80, 0.0, 2.64, 1.84, 0.34),
        _rect_oct(0.0, -1.15, 0.0, 2.58, 1.78, 0.32),
        _rect_oct(0.0,  0.00, 0.0, 2.52, 1.72, 0.30),
        _rect_oct(0.0,  0.34, 0.0, 2.46, 1.66, 0.28),
    ]
    _loft_horizontal_masonry(
        mb, found_secs, 'limestone',
        [C_COBBLE_WET, C_COBBLE_DARK, C_COBBLE_MID, C_COBBLE_HI],
        rng, caps=(True, True), top_mat='temple_stone', top_col=C_SANDSTONE_MID,
    )

    for yc, hx, hz in ((-2.80, 2.64, 1.84), (0.0, 2.52, 1.72), (DECK_Y, 2.46, 1.66), (2.72, 2.26, 1.24)):
        col_pts.extend(_rect_oct(0.0, yc, 0.0, hx, hz, 0.28))

    # Planked Weathered Oak Harbour Ropewalk Deck (y = 0.34 .. 0.44 m) + Seaward Apron Step!
    cbox(mb, (0.0, 0.36, 0.0), (4.82, 0.12, 3.24), 'timber', C_OAK_DEEP, 0.0)
    n_planks = 5
    for dpi in range(n_planks):
        pz_d = -1.28 + dpi * (2.56 / float(n_planks - 1))
        cbox(mb, (0.0, DECK_Y - 0.01, pz_d), (4.78, 0.06, 0.56), 'timber',
             C_DRIFT_MID if dpi % 2 == 0 else C_OAK_RICH, 0.0)
    cbox(mb, (0.0, 0.18, -1.76), (1.92, 0.32, 0.34), 'temple_stone', C_SANDSTONE_MID, 0.0)

    # Corner Mooring Timber Pilings bound with braided hemp rope collars
    for px_p in (-2.40, 2.40):
        for pz_p in (-1.58, 1.58):
            top_p = DECK_Y + (0.36 if pz_p < 0 else 0.28)
            with xf(mb, T(px_p, 0.0, pz_p)):
                cyl(mb, 0.135, -0.35, top_p, 6, 'timber', C_DRIFT_DARK, False, 0.0, 0.120)
                cyl(mb, 0.148, top_p - 0.18, top_p - 0.08, 6, 'rope', C_HEMP_MID, False, 0.0)

    # 2. Longitudinal Oak Ropewalk Guide-Rails connecting Headstock & Tailstock Trestles
    for rz_g in (LOOM_Z - 0.44, LOOM_Z + 0.44):
        cbox(mb, (0.0, DECK_Y + 0.09, rz_g), (4.38, 0.14, 0.14), 'timber', C_OAK_DEEP, 0.0)
        cbox(mb, (0.0, DECK_Y + 0.17, rz_g), (4.32, 0.03, 0.055), 'iron', C_IRON_FORGED, 0.0)
    for tx_s in (-1.94, -0.64, 0.66, 1.94):
        cbox(mb, (tx_s, DECK_Y + 0.05, LOOM_Z), (0.18, 0.10, 1.44), 'timber', C_OAK_CHAR, 0.0)

    # 3. Port Headstock Twisting Trestle (x = -1.94 m) w/ Timber Weather-Hood & Spoked Geared Wheel!
    HX = -1.94
    for sz in (-0.54, 0.54):
        _add_beam(mb, (HX, DECK_Y, LOOM_Z + sz * 1.18), (HX, 2.68, LOOM_Z + sz * 0.92),
                  0.17, 0.17, 'timber', C_OAK_DEEP, 0.0)
        cbox(mb, (HX, DECK_Y + 0.10, LOOM_Z + sz * 1.18), (0.24, 0.20, 0.24), 'iron', C_IRON_FORGED, 0.0)
        _add_beam(mb, (HX - 0.44, DECK_Y + 0.04, LOOM_Z + sz * 1.08), (HX, 1.56, LOOM_Z + sz * 1.02),
                  0.11, 0.12, 'timber', C_OAK_RICH, 0.0)
        _add_beam(mb, (HX + 0.44, DECK_Y + 0.06, LOOM_Z + sz * 0.96), (HX, 1.18, LOOM_Z + sz * 1.04),
                  0.10, 0.11, 'timber', C_OAK_RICH, 0.0)

    cbox(mb, (HX, 1.12, LOOM_Z), (0.22, 0.16, 1.24), 'timber', C_OAK_RICH, 0.0)
    cbox(mb, (HX, 2.02, LOOM_Z), (0.24, 0.18, 1.18), 'timber', C_OAK_RICH, 0.0)
    cbox(mb, (HX, 2.64, LOOM_Z), (0.28, 0.18, 1.32), 'timber', C_OAK_DEEP, 0.0)
    cbox(mb, (HX + 0.06, 1.56, LOOM_Z), (0.34, 0.72, 0.88), 'timber', C_OAK_SUN, 0.0)
    for gy in (1.24, 1.88):
        cbox(mb, (HX + 0.06, gy, LOOM_Z), (0.38, 0.075, 0.92), 'iron', C_IRON_FORGED, 0.0)

    # Sloped Planked Oak Weather-Hood Canopy crowning Headstock Gearbox
    for side_s in (-1.0, 1.0):
        _add_beam(mb, (HX, 3.02, LOOM_Z), (HX, 2.64, LOOM_Z + side_s * 0.78),
                  0.12, 0.11, 'timber', C_OAK_DEEP, 0.0)
        cbox(mb, (HX, 2.86, LOOM_Z + side_s * 0.42), (0.88, 0.065, 0.96), 'timber',
             C_OAK_SUN if side_s < 0 else C_OAK_RICH, 0.0, M=R('X', side_s * 26.0))
    cbox(mb, (HX, 3.06, LOOM_Z), (0.94, 0.10, 0.14), 'timber', C_OAK_DEEP, 0.0)

    # Prominent Spoked Geared Spinning Wheel mounted cleanly on Front-Port Headstock Face (X-Y plane!)
    WHEEL_C = Vector((HX + 0.22, 1.56, LOOM_Z - 0.68))
    _build_spoked_gear_wheel(mb, WHEEL_C, radius=0.72, n_spokes=8, n_teeth=8)
    with xf(mb, T(WHEEL_C.x, WHEEL_C.y, LOOM_Z - 0.48) @ M_Y2Z):
        cyl(mb, 0.055, -0.24, 0.26, 5, 'iron', C_IRON_BRIGHT, False, 0.0)
    with xf(mb, T(HX + 0.22, 1.96, LOOM_Z - 0.56) @ M_Y2Z):
        cyl(mb, 0.16, -0.05, 0.05, 7, 'brass', C_GOLD_BRIGHT, False, 0.0)
        cyl(mb, 0.055, -0.08, 0.24, 5, 'iron', C_IRON_FORGED, False, 0.0)

    # Matching spoked iron tension balance wheel on rear (+Z) headstock flank for Rear 3/4 craft!
    with xf(mb, T(HX + 0.14, 1.56, LOOM_Z + 0.62) @ M_Y2Z):
        torus(mb, 0.42, 0.038, 8, 4, 'iron', C_IRON_FORGED, False)
        cyl(mb, 0.09, -0.07, 0.07, 6, 'brass', C_BRASS_WARM, False, 0.0)
    for k in range(4):
        ang = k * pi * 0.5
        _add_beam(mb, (HX + 0.14 - 0.40 * cos(ang), 1.56 - 0.40 * sin(ang), LOOM_Z + 0.62),
                  (HX + 0.14 + 0.40 * cos(ang), 1.56 + 0.40 * sin(ang), LOOM_Z + 0.62),
                  0.038, 0.032, 'iron', C_IRON_BRIGHT, 0.0)

    # 3 Forged-Iron Twisting Hooks projecting starboard (+X) from the headstock whirl-box
    hook_offsets = [(0.0, 0.22, -0.22), (0.0, 0.22, 0.22), (0.0, -0.20, 0.0)]
    port_hooks = []
    for ox, oy, oz in hook_offsets:
        hp = Vector((HX + 0.22, 1.58 + oy, LOOM_Z + oz))
        with xf(mb, T(hp) @ M_Y2X):
            cyl(mb, 0.076, -0.03, 0.04, 5, 'brass', C_BRASS_WARM, False, 0.0)
        _build_iron_hook(mb, hp, dir_x=1.0, scale=0.92)
        port_hooks.append(hp + Vector((0.20, 0.0, 0.0)))

    # 4. Starboard Braced Oak Tailstock Tension Sledge & Counterweight Trestle (x = +1.94 m!)
    TX = 1.94
    for sz in (-0.52, 0.52):
        _add_beam(mb, (TX, DECK_Y + 0.12, LOOM_Z + sz * 1.12), (TX, 2.34, LOOM_Z + sz * 0.78),
                  0.16, 0.16, 'timber', C_OAK_DEEP, 0.0)
        _add_beam(mb, (TX + 0.44, DECK_Y + 0.12, LOOM_Z + sz * 1.06), (TX, 1.72, LOOM_Z + sz * 0.90),
                  0.11, 0.11, 'timber', C_OAK_RICH, 0.0)
        _add_beam(mb, (TX - 0.38, DECK_Y + 0.12, LOOM_Z + sz * 0.94), (TX, 1.24, LOOM_Z + sz * 0.98),
                  0.095, 0.10, 'timber', C_OAK_RICH, 0.0)
    cbox(mb, (TX + 0.12, DECK_Y + 0.22, LOOM_Z), (0.96, 0.14, 1.22), 'timber', C_OAK_RICH, 0.0)
    cbox(mb, (TX, 1.56, LOOM_Z), (0.24, 0.24, 1.12), 'timber', C_OAK_SUN, 0.0)
    cbox(mb, (TX, 2.28, LOOM_Z), (0.22, 0.16, 1.04), 'timber', C_OAK_DEEP, 0.0)
    # Cut ashlar tension counterweight stone blocks strapped onto tailstock sledge (clean low-poly!)
    cbox(mb, (TX + 0.34, DECK_Y + 0.50, LOOM_Z - 0.24), (0.42, 0.44, 0.42), 'temple_stone', C_SANDSTONE_MID, 0.0)
    cbox(mb, (TX + 0.35, DECK_Y + 0.48, LOOM_Z + 0.24), (0.40, 0.40, 0.40), 'limestone', C_COBBLE_HI, 0.0)
    TAIL_HOOK = Vector((TX - 0.14, 1.56, LOOM_Z))
    with xf(mb, T(TX, 1.56, LOOM_Z) @ M_Y2X):
        cyl(mb, 0.12, -0.16, 0.24, 6, 'iron', C_IRON_FORGED, False, 0.0)
        cyl(mb, 0.09, 0.22, 0.32, 6, 'brass', C_GOLD_BRIGHT, False, 0.0)
    _build_iron_hook(mb, TAIL_HOOK, dir_x=-1.0, scale=1.22)
    tail_anchor = TAIL_HOOK + Vector((-0.24, 0.0, 0.0))

    # 5. Mid-Span Oak Strand-Support Crutches, Grooved Wooden Laying Cone & Taut Braided Hemp Strands!
    for cx_c, pin_zs in ((-0.64, (-0.24, 0.0, 0.24)), (0.96, (-0.09, 0.09))):
        cbox(mb, (cx_c, 0.5 * (DECK_Y + 1.46), LOOM_Z), (0.12, 1.46 - DECK_Y, 0.12), 'timber', C_OAK_DEEP, 0.0)
        _add_beam(mb, (cx_c, DECK_Y + 0.08, LOOM_Z - 0.44), (cx_c, 1.06, LOOM_Z), 0.08, 0.08, 'timber', C_OAK_RICH, 0.0)
        _add_beam(mb, (cx_c, DECK_Y + 0.08, LOOM_Z + 0.44), (cx_c, 1.06, LOOM_Z), 0.08, 0.08, 'timber', C_OAK_RICH, 0.0)
        cbox(mb, (cx_c, 1.44, LOOM_Z), (0.14, 0.10, 0.72 if len(pin_zs) == 3 else 0.42), 'timber', C_OAK_SUN, 0.0)
        for p_z in pin_zs:
            cbox(mb, (cx_c, 1.54, LOOM_Z + p_z), (0.04, 0.14, 0.04), 'iron', C_IRON_BRIGHT, 0.0)

    # Iconic Grooved Wooden Cordage Laying Cone Carriage riding at x = 0.26 m!
    CONE_X = 0.26
    CONE_Y = 1.56
    with xf(mb, T(CONE_X, CONE_Y, LOOM_Z) @ M_Y2X):
        lathe(mb, [(0.0, -0.22), (0.18, -0.20), (0.15, 0.0), (0.085, 0.22), (0.0, 0.24)],
              6, 'timber', C_OAK_SUN, False, False,
              lambda i, k: C_OAK_DEEP if i in (0, 4) else C_OAK_SUN)
        cyl(mb, 0.19, -0.18, -0.12, 6, 'brass', C_GOLD_BRIGHT, False, 0.0)
    cbox(mb, (CONE_X, 0.98, LOOM_Z), (0.20, 0.98, 0.14), 'timber', C_OAK_RICH, 0.0)
    cbox(mb, (CONE_X, DECK_Y + 0.24, LOOM_Z), (0.48, 0.12, 1.06), 'timber', C_OAK_DEEP, 0.0)
    for wz in (-0.44, 0.44):
        with xf(mb, T(CONE_X, DECK_Y + 0.24, LOOM_Z + wz) @ M_Y2Z):
            cyl(mb, 0.11, -0.05, 0.05, 6, 'iron', C_IRON_FORGED, False, 0.0)

    # 3 Taut Braided Hemp Strands (port iron hooks -> laying cone) twisting into 1 Fat Laid Anchor Hawser!
    for si, ph in enumerate(port_hooks):
        s_end = Vector((CONE_X - 0.16, CONE_Y + (ph.y - 1.58) * 0.45, LOOM_Z + (ph.z - LOOM_Z) * 0.45))
        pts_s = []
        for k in range(5):
            t = k / 4.0
            p = ph.lerp(s_end, t)
            tw_ang = t * 4.0 * pi + si * (2.0 * pi / 3.0)
            p += Vector((0.0, 0.018 * sin(tw_ang) - 0.03 * t * (1.0 - t), 0.018 * cos(tw_ang)))
            pts_s.append(p)
        tube(mb, pts_s, 0.036, 4, 'rope', C_HEMP_HI if si % 2 == 0 else C_HEMP_MID,
             caps=(True, True), mode='flat')

    hawser_pts = []
    for k in range(6):
        t = k / 5.0
        p = Vector((CONE_X + 0.16, CONE_Y, LOOM_Z)).lerp(tail_anchor, t)
        p.y -= 0.025 * 4.0 * t * (1.0 - t)
        hawser_pts.append(p)
    tube(mb, hawser_pts, 0.072, 5, 'rope', C_HEMP_HI, caps=(True, True), mode='flat')
    # 3 Tight Whipping / Seizing Collars along the laid hawser
    for t_c in (0.26, 0.54, 0.80):
        rp = Vector((CONE_X + 0.20, CONE_Y, LOOM_Z)).lerp(tail_anchor - Vector((0.05, 0.0, 0.0)), t_c)
        with xf(mb, T(rp) @ M_Y2X):
            cyl(mb, 0.084, -0.04, 0.04, 5, 'rope', C_HEMP_DARK, False, 0.0)

    # 6. Stacked Coils of Coiled Anchor Hawser, Pitch Barrel & Wooden Serving Mallets!
    cbox(mb, (0.28, DECK_Y + 0.05, -1.04), (1.16, 0.08, 0.86), 'timber', C_OAK_DEEP, 0.0)
    _build_rope_coil(mb, (0.04, DECK_Y + 0.09, -1.04), radius=0.33, turns=3, r=0.052, segs=6, psegs=4,
                     col_a=C_HEMP_HI, col_b=C_HEMP_MID)
    _build_rope_coil(mb, (0.64, DECK_Y + 0.09, -1.08), radius=0.25, turns=2, r=0.046, segs=6, psegs=4,
                     col_a=C_HEMP_MID, col_b=C_HEMP_DARK)
    with xf(mb, T(1.56, DECK_Y + 0.34, -0.96) @ R('Y', -22.0) @ R('X', 74.0)):
        torus(mb, 0.32, 0.052, 6, 4, 'rope', C_HEMP_HI, True)
        with xf(mb, T(0.0, 0.09, 0.0)):
            torus(mb, 0.26, 0.048, 6, 4, 'rope', C_HEMP_MID, True)

    # Coopered Tar/Pitch Barrel w/ Wooden Tar-Brush Dipper on Front-Port Apron
    _build_coopered_barrel(mb, T(-1.32, DECK_Y + 0.35, -1.16) @ R('Y', 16.0),
                           radius=0.28, height=0.70, rng=rng, segs=6)
    _add_beam(mb, (-1.34, DECK_Y + 0.56, -1.14), (-1.04, DECK_Y + 1.06, -1.32),
              0.036, 0.036, 'timber', C_OAK_SUN, 0.0)
    cbox(mb, (-1.28, DECK_Y + 0.66, -1.18), (0.11, 0.11, 0.11), 'rope', C_PITCH_TAR, 0.0)

    # Oak Chopping & Splicing Block bearing 2 Sculpted Wooden Serving Mallets + Fid!
    with xf(mb, T(-0.68, DECK_Y, -1.18)):
        cyl(mb, 0.24, 0.0, 0.46, 6, 'timber', C_OAK_DEEP, False, 0.0, 0.22)
        cyl(mb, 0.23, 0.34, 0.40, 6, 'iron', C_IRON_FORGED, False, 0.0)
    _build_serving_mallet(mb, T(-0.72, DECK_Y + 0.46, -1.24) @ R('Y', 32.0), scale=1.08)
    _build_serving_mallet(mb, T(-0.56, DECK_Y + 0.46, -1.10) @ R('Y', -48.0), scale=0.96)
    with xf(mb, T(-0.34, DECK_Y + 0.12, -1.36) @ R('Y', 24.0) @ M_Y2X):
        cyl(mb, 0.044, -0.16, 0.18, 5, 'timber', C_OAK_SUN, False, 0.0, 0.010)

    # Rear (+Z) Cordage Workbench, Spare Twine Spools & Reserve Hawser Coil
    cbox(mb, (0.64, DECK_Y + 0.72, 1.22), (1.36, 0.08, 0.62), 'timber', C_OAK_SUN, 0.0)
    for lx in (-0.56, 0.56):
        for lz in (-0.23, 0.23):
            cbox(mb, (0.64 + lx, DECK_Y + 0.36, 1.22 + lz), (0.08, 0.72, 0.08), 'timber', C_OAK_DEEP, 0.0)
    for sp_x, sp_col in ((0.28, C_HEMP_HI), (0.76, C_HEMP_MID)):
        with xf(mb, T(sp_x, DECK_Y + 0.76, 1.20)):
            cyl(mb, 0.16, 0.00, 0.04, 6, 'timber', C_OAK_DEEP, False, 0.0)
            cyl(mb, 0.13, 0.04, 0.28, 6, 'rope', sp_col, False, 0.0)
            cyl(mb, 0.16, 0.28, 0.32, 6, 'timber', C_OAK_DEEP, False, 0.0)
    _build_serving_mallet(mb, T(1.08, DECK_Y + 0.76, 1.24) @ R('Y', -110.0), scale=1.0)
    _build_rope_coil(mb, (-0.56, DECK_Y + 0.02, 1.18), radius=0.30, turns=2, r=0.048, segs=6, psegs=4,
                     col_a=C_HEMP_HI, col_b=C_HEMP_MID)

    # 7. Tall Harbour Guild Banner Mast, Fluttering Red-Cream Banner (UV2!) & Warm Brass Work-Lantern!
    MAST_X, MAST_Z = -2.14, 1.04
    with xf(mb, T(MAST_X, 0.0, MAST_Z)):
        cyl(mb, 0.11, DECK_Y - 0.08, 3.68, 6, 'timber', C_OAK_DEEP, False, 0.0, 0.068)
        cyl(mb, 0.135, DECK_Y, DECK_Y + 0.22, 6, 'iron', C_IRON_FORGED, False, 0.0)
        lathe(mb, [(0.0, 3.66), (0.095, 3.74), (0.0, 3.84)], 6, 'brass', C_GOLD_BRIGHT, False)
    _add_beam(mb, (MAST_X, 2.56, MAST_Z), (HX, 2.64, LOOM_Z + 0.56), 0.09, 0.09, 'timber', C_OAK_RICH, 0.0)

    _build_wind_banner(
        mb, root_pos=(MAST_X + 0.07, 3.38, MAST_Z), length=1.48, h0=0.44,
        out_dir=(0.94, -0.03, -0.34),
        col_main=C_CRIMSON_HI, col_alt=C_CREAM_SAIL, col_trim=C_GOLD_BRIGHT,
        phase=0.26, swallowtail=True,
    )

    # Warm Brass Work-Lantern ('Lantern_Ropewalk') lifted cleanly clear of the spoked wheel rim!
    LANTERN_POS = Vector((-1.36, 2.52, -1.04))
    _add_beam(mb, (HX, 2.86, LOOM_Z - 0.44), (-1.34, 2.88, -1.08), 0.082, 0.088, 'timber', C_OAK_RICH, 0.0)
    _add_beam(mb, (HX, 2.34, LOOM_Z - 0.52), (-1.62, 2.86, -0.76), 0.058, 0.064, 'iron', C_IRON_FORGED, 0.0)
    _add_beam(mb, (-1.36, 2.88, -1.04), LANTERN_POS + Vector((0.0, 0.28, 0.0)), 0.025, 0.025, 'iron', C_IRON_FORGED, 0.0)
    _build_storm_lantern(mb, LANTERN_POS, scale=0.86, brass_cage=True, hanging=True)

    # 8. Coastal Harbour Ferns ('foliage' + UV2) tucked neatly around seawall corners
    for fpos, fsc, flean, fph in (
        ((-2.28, DECK_Y - 0.08, -1.46), 0.62, (-0.7, 0.0, -0.7), 0.14),
        (( 2.28, DECK_Y - 0.08, -1.44), 0.60, ( 0.7, 0.0, -0.7), 0.42),
        ((-2.26, DECK_Y - 0.08,  1.46), 0.62, (-0.7, 0.0,  0.7), 0.69),
        (( 2.26, DECK_Y - 0.08,  1.46), 0.60, ( 0.7, 0.0,  0.7), 0.91),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=3, rng=rng, phase=fph, lean_dir=flean, segs=2)

    build(mb)

    add_empty('Lantern_Ropewalk', LANTERN_POS)
    col_piece('col_ropewalk_base', col_pts)
    export_landmark_glb(outdir, 'pirate_ropewalk_cordage_loom.glb')


# ==============================================================================
# 2. ANCIENT TIDAL COMPASS SANCTUM (ancient_tidal_compass_sanctum.glb)
# ==============================================================================

def _build_rune_obelisk(mb, cx, cz, base_y, height, ang_deg, rng):
    """Crisp 4-sided tapered mossy temple-stone corner rune obelisk with verdigris-bronze bands,
    taper-flush luminous cyan-turquoise aquatic glyphs ('skull_glow'), and pyramidion cap."""
    ar = radians(ang_deg)
    in_dir = Vector((-cos(ar), 0.0, -sin(ar))).normalized()
    out_dir = -in_dir
    shaft_y0 = base_y + 0.50
    shaft_top = height - 0.70
    r_bot = 0.35
    r_top = 0.25
    with xf(mb, T(cx, 0.0, cz) @ R('Y', -ang_deg + 45.0)):
        # Stepped mossy plinth footing (crisp 4-sided ancient ashlar!)
        foot_secs = [
            _rect_quad(0.0, base_y - 0.04, 0.0, 0.46, 0.46),
            _rect_quad(0.0, shaft_y0 + 0.02, 0.0, 0.41, 0.41),
        ]
        _loft_horizontal_masonry(
            mb, foot_secs, 'limestone_moss',
            [C_SANCTUM_DARK, C_SANCTUM_MID], rng, caps=(False, True),
        )
        # Battered 4-sided tapered carved temple-stone obelisk shaft
        shaft_secs = [
            _rect_quad(0.0, shaft_y0, 0.0, r_bot, r_bot),
            _rect_quad(0.0, 0.5 * (shaft_y0 + shaft_top), 0.0, 0.5 * (r_bot + r_top), 0.5 * (r_bot + r_top)),
            _rect_quad(0.0, shaft_top, 0.0, r_top, r_top),
        ]
        _loft_horizontal_masonry(
            mb, shaft_secs, 'temple_stone',
            [C_SANCTUM_MID, C_SANCTUM_HI, C_SANCTUM_HI], rng, caps=(False, True),
        )
        # Verdigris-bronze & gilded ceremonial collar bands hugging the tapered shaft
        cbox(mb, (0.0, shaft_y0 + 0.06, 0.0), (0.76, 0.10, 0.76), 'brass', C_VERDIGRIS_HI, 0.0)
        cbox(mb, (0.0, shaft_top - 0.04, 0.0), (0.58, 0.11, 0.58), 'brass', C_GOLD_BRIGHT, 0.0)
        cbox(mb, (0.0, shaft_top + 0.08, 0.0), (0.64, 0.09, 0.64), 'limestone_moss', C_SANCTUM_HI, 0.0)
        # Tapered faceted 4-sided pyramidion cap
        cap_secs = [
            _rect_quad(0.0, shaft_top + 0.12, 0.0, 0.27, 0.27),
            _rect_quad(0.0, height - 0.12,    0.0, 0.09, 0.09),
            _rect_quad(0.0, height,           0.0, 0.015, 0.015),
        ]
        _loft_horizontal_masonry(
            mb, cap_secs, 'temple_stone',
            [C_SANCTUM_HI, C_SANCTUM_HI, C_SANCTUM_HI], rng, caps=(False, True),
        )
        # Taper-Flush Glowing Cyan-Turquoise Carved Aquatic Rune Channels ('skull_glow' ONLY!) on all 4 faces!
        y_lo = shaft_y0 + 0.30
        y_hi = shaft_top - 0.24
        def _face_r(y_val):
            t = (y_val - shaft_y0) / max(shaft_top - shaft_y0, 0.01)
            return r_bot + (r_top - r_bot) * t + 0.012
        for rot_y in (0.0, 90.0, 180.0, 270.0):
            with xf(mb, R('Y', rot_y)):
                _add_beam(mb, (0.0, y_lo, -_face_r(y_lo)), (0.0, y_hi, -_face_r(y_hi)),
                          0.056, 0.036, 'skull_glow', C_AQUA_DEEP, 0.0)
                for gi, gy_frac in enumerate((0.32, 0.70)):
                    gy = y_lo + (y_hi - y_lo) * gy_frac
                    gs = 0.13 if gi == 0 else 0.10
                    cbox(mb, (0.0, gy, -_face_r(gy)), (gs, gs, 0.045), 'skull_glow',
                         C_AQUA_CORE if gi == 0 else C_AQUA_MID, 0.0, M=R('Z', 45.0))
        # Luminous aqua crown diamond gem embedded right below the pyramidion peak
        with xf(mb, T(0.0, shaft_top + 0.30, 0.0)):
            lathe(mb, [(0.0, -0.09), (0.13, 0.0), (0.0, 0.09)], 4, 'skull_glow', C_AQUA_CORE, False)
    return Vector((cx, shaft_top, cz)), in_dir, out_dir


def _build_wind_rose_ray(mb, ang_deg, r_in, r_out, half_w, y_base, y_ridge, col_left, col_right):
    """Crisp faceted 3D raised gilded-bronze compass rose ray pointer triangle."""
    ar = radians(ang_deg)
    fwd = Vector((cos(ar), 0.0, sin(ar)))
    side = Vector((-sin(ar), 0.0, cos(ar)))
    p_in_c = fwd * r_in + Vector((0.0, y_ridge, 0.0))
    p_tip  = fwd * r_out + Vector((0.0, y_base + 0.025, 0.0))
    p_l    = fwd * (r_in + (r_out - r_in) * 0.22) - side * half_w + Vector((0.0, y_base, 0.0))
    p_r    = fwd * (r_in + (r_out - r_in) * 0.22) + side * half_w + Vector((0.0, y_base, 0.0))
    p_mid  = fwd * (r_in + (r_out - r_in) * 0.26) + Vector((0.0, y_ridge, 0.0))
    inside = fwd * (0.5 * (r_in + r_out)) + Vector((0.0, y_base - 0.5, 0.0))
    mb.fp([p_in_c, p_l, p_mid], 'brass', col_left, fwd, inside, smooth=False)
    mb.fp([p_mid, p_l, p_tip], 'brass', col_left, fwd, inside, smooth=False)
    mb.fp([p_in_c, p_mid, p_r], 'brass', col_right, fwd, inside, smooth=False)
    mb.fp([p_mid, p_tip, p_r], 'brass', col_right, fwd, inside, smooth=False)


def gen_ancient_tidal_compass_sanctum(outdir):
    """Overgrown octagonal mossy temple-stone compass rose sanctuary (~5.0 m W x 5.0 m D x 4.8 m H,
    -3.00 m octagonal temple plinth skirt) crowned by 4 carved rune obelisk corner columns &
    bronze meridian crown arcs, raised gilded bronze 8-point wind-rose floor inlay, hovering
    luminous cyan-turquoise crystal compass needle & glowing aquatic rune ring ('skull_glow' ONLY),
    cascading jungle vines & ferns (UV2 wind sway), convex collider 'col_tidalcompass_base',
    and empty 'Lantern_TidalCompass'."""
    clear_scene()
    mb = MB('ancient_tidal_compass_sanctum', seed=2002)
    rng = random.Random(SEED + 2002)
    col_pts = []

    STEP1_Y = 0.36
    DAIS_Y  = 0.68
    NEEDLE_C = Vector((0.0, 2.66, 0.0))

    # 1. Deep Octagonal Mossy Temple-Stone Plinth Skirt plunging cleanly to y = -3.00 m (~5.0 m W x 5.0 m D)
    plinth_secs = [
        _reg_poly(0.0, -3.00, 0.0, 2.38, sides=8, rot_deg=22.5),
        _reg_poly(0.0, -1.25, 0.0, 2.32, sides=8, rot_deg=22.5),
        _reg_poly(0.0,  0.00, 0.0, 2.26, sides=8, rot_deg=22.5),
        _reg_poly(0.0, STEP1_Y, 0.0, 2.20, sides=8, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, plinth_secs, 'limestone_moss',
        [C_SANCTUM_DEEP, C_SANCTUM_DARK, C_SANCTUM_MID, C_SANCTUM_HI],
        rng, caps=(True, True), top_mat='limestone_moss', top_col=C_SANCTUM_MID,
    )

    dais_secs = [
        _reg_poly(0.0, STEP1_Y - 0.02, 0.0, 1.94, sides=8, rot_deg=22.5),
        _reg_poly(0.0, DAIS_Y,         0.0, 1.86, sides=8, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, dais_secs, 'temple_stone',
        [C_SANCTUM_DARK, C_SANCTUM_HI], rng, caps=(False, True),
        top_mat='temple_stone', top_col=C_SANCTUM_MID,
    )

    for yc, rc in ((-3.00, 2.38), (0.0, 2.26), (DAIS_Y, 2.16), (4.55, 1.90)):
        col_pts.extend(_reg_poly(0.0, yc, 0.0, rc, sides=8, rot_deg=22.5))

    # Ceremonial Carved Stone Approach Steps on Seaward (-Z) & Rear (+Z) + Low Tidal Balustrades on (-X/+X)
    for z_sgn in (-1.0, 1.0):
        cbox(mb, (0.0, 0.18, z_sgn * 2.16), (1.32, 0.34, 0.32), 'temple_stone', C_SANCTUM_MID, 0.0)
        cbox(mb, (0.0, 0.48, z_sgn * 1.86), (1.16, 0.28, 0.32), 'temple_stone', C_SANCTUM_HI, 0.0)
        for sx in (-1.0, 1.0):
            cbox(mb, (sx * 0.70, 0.42, z_sgn * 1.96), (0.20, 0.62, 0.64), 'limestone_moss', C_SANCTUM_DARK, 0.0)
            cbox(mb, (sx * 0.70, 0.76, z_sgn * 1.80), (0.22, 0.09, 0.22), 'brass', C_VERDIGRIS_HI, 0.0)
    for x_sgn in (-1.0, 1.0):
        cbox(mb, (x_sgn * 1.94, 0.64, 0.0), (0.26, 0.56, 1.18), 'limestone_moss', C_SANCTUM_DARK, 0.0)
        cbox(mb, (x_sgn * 1.94, 0.96, 0.0), (0.32, 0.10, 1.26), 'temple_stone', C_SANCTUM_HI, 0.0)
        cbox(mb, (x_sgn * 1.94, 1.04, 0.0), (0.15, 0.08, 0.60), 'brass', C_VERDIGRIS_HI, 0.0)

    # 2. Raised Gilded Bronze 8-Point Wind-Rose Floor Inlay & Luminous Aquatic Floor Rune Ring!
    with xf(mb, T(0.0, DAIS_Y + 0.02, 0.0)):
        torus(mb, 1.62, 0.052, 12, 4, 'brass', C_BRASS_WARM, False)
        torus(mb, 1.10, 0.036, 12, 4, 'brass', C_VERDIGRIS_HI, False)
        torus(mb, 1.34, 0.036, 12, 4, 'skull_glow', C_AQUA_MID, False)
        for k in range(8):
            ang = radians(k * 45.0)
            is_maj = (k % 2 == 0)
            cbox(mb, (1.56 * cos(ang), 0.038, 1.56 * sin(ang)),
                 (0.14 if is_maj else 0.09, 0.045, 0.06 if is_maj else 0.045),
                 'brass', C_GOLD_BRIGHT if is_maj else C_BRASS_WARM, 0.0, M=R('Y', -k * 45.0))

    for k in range(8):
        ang_deg = k * 45.0
        is_card = (k % 2 == 0)
        if is_card:
            _build_wind_rose_ray(mb, ang_deg, 0.44, 1.58, 0.21, DAIS_Y + 0.01, DAIS_Y + 0.12,
                                 C_GOLD_BRIGHT, C_BRASS_WARM)
            ar = radians(ang_deg)
            cbox(mb, (1.66 * cos(ar), DAIS_Y + 0.08, 1.66 * sin(ar)),
                 (0.11, 0.07, 0.11), 'skull_glow', C_AQUA_CORE, 0.0, M=R('Y', 45.0))
        else:
            _build_wind_rose_ray(mb, ang_deg, 0.44, 1.18, 0.15, DAIS_Y + 0.01, DAIS_Y + 0.09,
                                 C_VERDIGRIS_HI, C_BRASS_DARK)

    # 3. Central Carved Tide-Dial Stone Pedestal Basin (y = 0.68 .. 1.54 m)
    with xf(mb, T(0.0, DAIS_Y, 0.0)):
        ped_secs = [
            _reg_poly(0.0, -0.02, 0.0, 0.68, sides=8, rot_deg=22.5),
            _reg_poly(0.0,  0.24, 0.0, 0.54, sides=8, rot_deg=22.5),
            _reg_poly(0.0,  0.64, 0.0, 0.46, sides=8, rot_deg=22.5),
            _reg_poly(0.0,  0.84, 0.0, 0.64, sides=8, rot_deg=22.5),
        ]
        _loft_horizontal_masonry(
            mb, ped_secs, 'temple_stone',
            [C_SANCTUM_DARK, C_SANCTUM_MID, C_SANCTUM_MID, C_SANCTUM_HI],
            rng, caps=(False, True), top_mat='temple_stone', top_col=C_SANCTUM_HI,
        )
        with xf(mb, T(0.0, 0.84, 0.0)):
            torus(mb, 0.62, 0.055, 10, 4, 'brass', C_GOLD_BRIGHT, False)
            cyl(mb, 0.50, -0.02, 0.04, 8, 'skull_glow', C_AQUA_MID, False, 0.0)
            lathe(mb, [(0.0, 0.02), (0.24, 0.06), (0.14, 0.24), (0.04, 0.44), (0.0, 0.52)],
                  6, 'skull_glow', C_AQUA_CORE, False, False,
                  lambda i, k: C_AQUA_CORE if i >= 2 else C_AQUA_MID)
        for k in range(4):
            ar = radians(k * 90.0)
            cbox(mb, (0.50 * cos(ar), 0.44, 0.50 * sin(ar)), (0.13, 0.13, 0.13),
                 'skull_glow', C_AQUA_CORE, 0.0, M=R('Y', -k * 90.0) @ R('Z', 45.0))

    # 4. Four Carved Rune Obelisk Corner Columns (NE, NW, SE, SW) + Sweeping Bronze-Stone Sanctuary Crown Arcs!
    obelisk_specs = [
        ( 45.0, 4.78),
        (135.0, 4.72),
        (225.0, 4.46),
        (315.0, 4.54),
    ]
    ob_tops = []
    for ang_deg, ob_h in obelisk_specs:
        ar = radians(ang_deg)
        ox, oz = 1.74 * cos(ar), 1.74 * sin(ar)
        top_pt, in_d, out_d = _build_rune_obelisk(mb, ox, oz, STEP1_Y, ob_h, ang_deg, rng)
        ob_tops.append((top_pt, in_d, out_d, ang_deg))

        p_start = Vector((ox, 3.22, oz))
        p_mid   = Vector((ox * 0.72, 4.08, oz * 0.72))
        p_end   = Vector((0.90 * cos(ar), 4.34, 0.90 * sin(ar)))
        tube(mb, [p_start, p_mid, p_end], [0.16, 0.13, 0.10], 4, 'temple_stone', C_SANCTUM_HI,
             caps=(True, True), mode='flat', scols=[C_SANCTUM_MID, C_SANCTUM_HI, C_SANCTUM_HI])
        tube(mb, [p_start + Vector((0, -0.10, 0)), p_mid + Vector((0, -0.09, 0)), p_end + Vector((0, -0.07, 0))],
             0.042, 4, 'brass', C_VERDIGRIS_HI, caps=(True, True), mode='flat')
        cbox(mb, p_mid + Vector((0.0, 0.08, 0.0)), (0.12, 0.12, 0.12), 'skull_glow', C_AQUA_MID, 0.0,
             M=R('Y', -ang_deg) @ R('Z', 45.0))

    # Open Celestial Gilded-Bronze Astrolabe Crown Ring linking the 4 Meridian Ribs overhead (y = 4.34 m)!
    with xf(mb, T(0.0, 4.34, 0.0)):
        torus(mb, 0.90, 0.075, 12, 4, 'brass', C_GOLD_BRIGHT, False)
        torus(mb, 0.78, 0.042, 12, 4, 'brass', C_VERDIGRIS_HI, False)
        for k in range(4):
            ar = radians(k * 90.0)
            p_b = Vector((0.90 * cos(ar), 0.04, 0.90 * sin(ar)))
            tube(mb, [p_b, p_b + Vector((0.0, 0.44, 0.0))],
                 [0.068, 0.010], 4, 'brass', C_GOLD_BRIGHT, caps=(False, True), mode='flat')

    # 5. Hovering Luminous Cyan-Turquoise Crystal Compass Needle & Glowing Aquatic Rune Ring ('skull_glow'!)
    with xf(mb, T(NEEDLE_C)):
        # Sleek razor-sharp double-pointed faceted crystal compass needle pointing seaward (-Z)!
        with xf(mb, R('X', 8.0)):
            n_pts = [
                (0.0, 0.0, -1.20),
                (0.0, 0.0, -0.36),
                (0.0, 0.0,  0.00),
                (0.0, 0.0,  0.34),
                (0.0, 0.0,  1.04),
            ]
            n_rads = [
                (0.010, 0.010),
                (0.16,  0.12),
                (0.24,  0.17),
                (0.15,  0.11),
                (0.010, 0.010),
            ]
            needle_secs = []
            for (px, py, pz), (rx, ry) in zip(n_pts, n_rads):
                needle_secs.append([
                    Vector((px,      py + ry, pz)),
                    Vector((px + rx, py,      pz)),
                    Vector((px,      py - ry, pz)),
                    Vector((px - rx, py,      pz)),
                ])
            loft(mb, needle_secs, 'skull_glow', C_AQUA_CORE, closed=True, caps=(True, True),
                 mode='flat', scols=[C_AQUA_CORE, C_AQUA_MID, C_AQUA_CORE, C_AQUA_MID, C_AQUA_DEEP])
            # Gilded-Bronze Gimbal Collar & Cross-Vanes embracing the Crystal Needle Heart!
            with xf(mb, M_Y2Z):
                torus(mb, 0.28, 0.038, 10, 4, 'brass', C_GOLD_BRIGHT, False)
            torus(mb, 0.38, 0.030, 10, 4, 'brass', C_VERDIGRIS_HI, False)
            for sx in (-1.0, 1.0):
                tube(mb, [Vector((sx * 0.28, 0.0, 0.0)), Vector((sx * 0.66, 0.0, 0.06))],
                     [0.062, 0.012], 4, 'brass', C_GOLD_BRIGHT, caps=(False, True), mode='flat')

        # Hovering Glowing Aquatic Rune Ring ('skull_glow'!) + Gimballed Bronze Astrolabe Halos!
        with xf(mb, R('Z', 10.0) @ R('X', -8.0)):
            torus(mb, 1.04, 0.044, 12, 4, 'skull_glow', C_AQUA_MID, False)
            torus(mb, 1.14, 0.028, 12, 4, 'brass', C_GOLD_BRIGHT, False)
            for k in range(8):
                ar = radians(k * 45.0)
                is_c = (k % 2 == 0)
                sc_c = 0.16 if is_c else 0.10
                with xf(mb, T(1.04 * cos(ar), 0.0, 1.04 * sin(ar)) @ R('Y', -k * 45.0)):
                    lathe(mb, [(0.0, -sc_c), (sc_c * 0.56, 0.0), (0.0, sc_c)],
                          4, 'skull_glow', C_AQUA_CORE if is_c else C_AQUA_MID, False)
        with xf(mb, R('Z', -42.0) @ R('Y', 28.0) @ M_Y2Z):
            torus(mb, 0.84, 0.026, 12, 4, 'brass', C_VERDIGRIS_HI, False)

    # 6. Cascading Jungle Vines, Mossy Ledge Cushions & Cleanly Grounded Tropical Ferns ('foliage' + UV2!)
    for idx_ob, (top_pt, in_d, out_d, ang_deg) in enumerate(ob_tops):
        ar = radians(ang_deg)
        side_d = Vector((-sin(ar), 0.0, cos(ar)))
        # Snug cornice vine anchor hugging the tapered obelisk shoulder!
        _add_leafy_vine_drape(mb, top_pt + out_d * 0.22 + Vector((0.0, -0.10, 0.0)),
                              1.90, 0.15, out_d, rng, phase=(ang_deg / 360.0))
        if idx_ob % 2 == 0:
            _add_leafy_vine_drape(mb, top_pt + side_d * 0.22 + Vector((0.0, -0.58, 0.0)),
                                  1.46, 0.14, (out_d + side_d).normalized(), rng, phase=((ang_deg + 90.0) / 360.0))
        _build_mossy_tuft(mb, (top_pt.x * 1.06, STEP1_Y + 0.50, top_pt.z * 1.06), (0.32, 0.15, 0.32), rng)

    for mpos, mrad in (
        ((-1.92, 1.02, -0.34), (0.26, 0.13, 0.34)),
        (( 1.92, 1.02,  0.34), (0.26, 0.13, 0.34)),
    ):
        _build_mossy_tuft(mb, mpos, mrad, rng)

    # 6 Lush Jungle Fern Clusters tucked cleanly beside the obelisk footings & side curbs (ZERO stair clipping!)
    for fpos, fsc, flean, fph in (
        ((-1.62, STEP1_Y + 0.02, -1.62), 0.68, (-0.7, 0.0, -0.7), 0.12),
        (( 1.62, STEP1_Y + 0.02, -1.62), 0.66, ( 0.7, 0.0, -0.7), 0.28),
        ((-1.62, STEP1_Y + 0.02,  1.62), 0.68, (-0.7, 0.0,  0.7), 0.45),
        (( 1.62, STEP1_Y + 0.02,  1.62), 0.66, ( 0.7, 0.0,  0.7), 0.62),
        ((-2.06, STEP1_Y + 0.02,  0.44), 0.60, (-1.0, 0.0,  0.2), 0.78),
        (( 2.06, STEP1_Y + 0.02, -0.44), 0.60, ( 1.0, 0.0, -0.2), 0.91),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=4, rng=rng, phase=fph, lean_dir=flean, segs=2)

    build(mb)

    add_empty('Lantern_TidalCompass', NEEDLE_C)
    col_piece('col_tidalcompass_base', col_pts)
    export_landmark_glb(outdir, 'ancient_tidal_compass_sanctum.glb')


# ==============================================================================
# 3. COASTAL BUCCANEER CAREENING CRADLE (coastal_buccaneer_careening_cradle.glb)
# ==============================================================================

def _build_pulley_block(mb, center, scale=1.0, hook_down=True):
    """Chunky nautical wooden pulley block with iron binding strap, bronze sheave wheel & iron hook."""
    s = scale
    cx, cy, cz = center
    with xf(mb, T(cx, cy, cz)):
        cbox(mb, (0.0, 0.0, 0.0), (0.16 * s, 0.30 * s, 0.22 * s), 'timber', C_OAK_RICH, 0.0)
        cbox(mb, (0.0, 0.0, 0.0), (0.18 * s, 0.32 * s, 0.08 * s), 'iron', C_IRON_FORGED, 0.0)
        with xf(mb, M_Y2X):
            cyl(mb, 0.095 * s, -0.09 * s, 0.09 * s, 6, 'timber', C_OAK_SUN, False, 0.0)
            cyl(mb, 0.036 * s, -0.11 * s, 0.11 * s, 5, 'brass', C_GOLD_BRIGHT, False, 0.0)
        y_ring = -0.20 * s if hook_down else 0.20 * s
        with xf(mb, T(0.0, y_ring, 0.0) @ M_Y2Z):
            torus(mb, 0.056 * s, 0.018 * s, 5, 4, 'iron', C_IRON_BRIGHT, False)


def _galleon_rib_pt(u_t, v_t):
    """Analytical salvaged pirate galleon hull-section surface in local hull coords."""
    x = -1.40 + 2.80 * u_t
    mid_bow = sin(u_t * pi)
    sheer_y = 0.14 * ((2.0 * u_t - 1.0) ** 2)
    y = v_t * 1.66 + sheer_y * v_t
    z = -(0.84 * sin(v_t * pi * 0.72) ** 0.80 + 0.12 * mid_bow * sin(v_t * pi * 0.7))
    return Vector((x, y, z))


def _emit_galleon_strake(mb, u_vals, v0, v1, mat, col_out, col_in, thick=0.055):
    """Emit solid double-sided curved galleon outer planking strake along u_vals and [v0..v1]."""
    for i in range(len(u_vals) - 1):
        u0, u1 = u_vals[i], u_vals[i + 1]
        p00 = _galleon_rib_pt(u0, v0)
        p10 = _galleon_rib_pt(u1, v0)
        p11 = _galleon_rib_pt(u1, v1)
        p01 = _galleon_rib_pt(u0, v1)
        ctr = (p00 + p10 + p11 + p01) * 0.25
        nrm = newell([p00, p10, p11, p01])
        if nrm.length < 1e-6:
            continue
        nrm.normalize()
        if nrm.z > 0.15:
            nrm = -nrm
        off_o = nrm * (thick * 0.5)
        off_i = -nrm * (thick * 0.5)
        mb.fp([p00 + off_o, p10 + off_o, p11 + off_o, p01 + off_o], mat, col_out,
              (1, 0, 0), ctr - nrm * 1.0, smooth=False)
        mb.fp([p10 + off_i, p00 + off_i, p01 + off_i, p11 + off_i], mat, col_in,
              (1, 0, 0), ctr + nrm * 1.0, smooth=False)
        mb.fp([p01 + off_i, p11 + off_i, p11 + off_o, p01 + off_o], mat, mul(col_out, 0.80),
              (1, 0, 0), ctr - Vector((0.0, 0.4, 0.0)), smooth=False)
        mb.fp([p00 + off_o, p10 + off_o, p10 + off_i, p00 + off_i], mat, mul(col_out, 0.72),
              (1, 0, 0), ctr + Vector((0.0, 0.4, 0.0)), smooth=False)


def _build_salvaged_galleon_section(mb, M_hull):
    """Salvaged tilted painted buccaneer galleon hull rib-section with 5 heavy curved oak frames,
    weathered scraped bilge strakes, crimson-teal-gold-cream painted gunport side w/ twin hinged
    gunport lids, interior deck knee-beams, and forged-iron hoist sling rings."""
    with xf(mb, M_hull):
        keel_pts = [_galleon_rib_pt(i / 4.0, 0.0) + Vector((0.0, -0.05, 0.08)) for i in range(5)]
        tube(mb, keel_pts, 0.105, 4, 'timber', C_OAK_CHAR, caps=(True, True), mode='flat')

        # 5 Heavy Curved Oak Galleon Hull Ribs (Frames) with bold interior deck knees
        rib_us = [0.05, 0.27, 0.50, 0.73, 0.95]
        for ri, ru in enumerate(rib_us):
            r_pts = [_galleon_rib_pt(ru, vi / 4.0) + Vector((0.0, 0.0, 0.075)) for vi in range(5)]
            r_pts.append(r_pts[-1] + Vector((0.0, 0.18 + 0.08 * (ri % 2), 0.02)))
            tube(mb, r_pts, [0.084, 0.076, 0.070, 0.064, 0.058, 0.046], 4,
                 'timber', C_OAK_SUN if ri % 2 == 0 else C_OAK_RICH, caps=(True, True), mode='flat')
            p_knee = r_pts[2]
            _add_beam(mb, p_knee, p_knee + Vector((0.0, 0.04, 0.60)), 0.082, 0.088, 'timber', C_OAK_DEEP, 0.0)
            _add_beam(mb, p_knee + Vector((0.0, -0.28, 0.06)), p_knee + Vector((0.0, 0.02, 0.34)),
                      0.068, 0.072, 'timber', C_OAK_RICH, 0.0)

        clamp_pts = [_galleon_rib_pt(i / 4.0, 0.58) + Vector((0.0, 0.02, 0.16)) for i in range(5)]
        tube(mb, clamp_pts, 0.065, 4, 'timber', C_OAK_DEEP, caps=(True, True), mode='flat')
        bilge_pts = [_galleon_rib_pt(i / 4.0, 0.24) + Vector((0.0, 0.02, 0.14)) for i in range(5)]
        tube(mb, bilge_pts, 0.058, 4, 'timber', C_OAK_RICH, caps=(True, True), mode='flat')

        # Bold Painted Buccaneer Galleon Outer Hull Planking w/ Exposed Scraped Rib Cutaway & 2 Gunports!
        u_all = [0.0, 0.25, 0.50, 0.75, 1.0]
        _emit_galleon_strake(mb, [0.38, 0.68, 1.00], 0.02, 0.28, 'timber', C_OAK_CHAR, C_OAK_DEEP, 0.054)
        _emit_galleon_strake(mb, [0.16, 0.50, 0.84], 0.28, 0.50, 'timber', C_OAK_DEEP, C_OAK_CHAR, 0.054)

        _emit_galleon_strake(mb, [0.00, 0.22], 0.50, 0.78, 'paint', C_CREAM_SAIL, C_OAK_RICH, 0.058)
        _emit_galleon_strake(mb, [0.40, 0.60], 0.50, 0.78, 'paint', C_CREAM_SAIL, C_OAK_RICH, 0.058)
        _emit_galleon_strake(mb, [0.78, 1.00], 0.50, 0.78, 'paint', C_CREAM_SAIL, C_OAK_RICH, 0.058)
        _emit_galleon_strake(mb, u_all, 0.78, 1.00, 'paint', C_CRIMSON_HI, C_OAK_RICH, 0.060)

        wale_lo = [_galleon_rib_pt(u, 0.49) + Vector((0.0, 0.0, -0.045)) for u in u_all]
        wale_hi = [_galleon_rib_pt(u, 0.79) + Vector((0.0, 0.0, -0.045)) for u in u_all]
        tube(mb, wale_lo, 0.044, 4, 'paint', C_TEAL_HI, caps=(True, True), mode='flat')
        tube(mb, wale_hi, 0.042, 4, 'brass', C_GOLD_BRIGHT, caps=(True, True), mode='flat')

        for gu_mid in (0.31, 0.69):
            p_gp = _galleon_rib_pt(gu_mid, 0.76) + Vector((0.0, 0.06, -0.14))
            cbox(mb, p_gp, (0.46, 0.36, 0.06), 'paint', C_CRIMSON_HI, 0.0, M=R('X', -50.0))
            cbox(mb, p_gp + Vector((0.0, 0.02, -0.02)), (0.42, 0.06, 0.08), 'iron', C_IRON_FORGED, 0.0, M=R('X', -50.0))

        # Heavy Braided Hemp Hoist Slings + Forged-Iron Hoist Rings
        sling_hooks_local = []
        for su in (0.18, 0.82):
            s_pts = [_galleon_rib_pt(su, vi / 4.0) + Vector((0.0, 0.0, -0.055)) for vi in range(5)]
            s_pts.append(_galleon_rib_pt(su, 1.0) + Vector((0.0, 0.18, 0.04)))
            tube(mb, s_pts, 0.042, 4, 'rope', C_HEMP_HI, caps=(True, True), mode='flat')
            ring_p = _galleon_rib_pt(su, 1.0) + Vector((0.0, 0.24, 0.06))
            with xf(mb, T(ring_p) @ M_Y2Z):
                torus(mb, 0.082, 0.024, 5, 4, 'iron', C_IRON_BRIGHT, False)
            sling_hooks_local.append(ring_p)

    return M_hull @ sling_hooks_local[0], M_hull @ sling_hooks_local[1]


def gen_coastal_buccaneer_careening_cradle(outdir):
    """Rugged seaside ship-careening & hull-scraping timber rigging gantry (~5.6 m W x 4.0 m D x 4.3 m H,
    -2.80 m deep cobble seawall & piling foundation) w/ twin braced A-frame timber derricks, wooden
    pulley blocks & taut tackle lines hoisting a salvaged tilted painted galleon hull rib-section,
    glowing pitch-cauldron brazier ('glass' warm amber — ZERO skull_glow!), stacked oak caulking
    planks, fluttering red-gold burgee (UV2 wind sway), convex collider 'col_careening_base',
    and warm work-lantern empty 'Lantern_Careening'."""
    clear_scene()
    mb = MB('coastal_buccaneer_careening_cradle', seed=2003)
    rng = random.Random(SEED + 2003)
    col_pts = []

    DECK_Y = 0.42

    # 1. Deep Coastal Cobble Seawall & Timber-Piling Careening Wharf plunging cleanly to y = -2.80 m (~5.6 m W x 4.0 m D)
    found_secs = [
        _rect_oct(0.0, -2.80, 0.0, 2.74, 1.94, 0.36),
        _rect_oct(0.0, -1.15, 0.0, 2.68, 1.88, 0.34),
        _rect_oct(0.0,  0.00, 0.0, 2.62, 1.82, 0.32),
        _rect_oct(0.0, DECK_Y, 0.0, 2.56, 1.76, 0.30),
    ]
    _loft_horizontal_masonry(
        mb, found_secs, 'limestone',
        [C_COBBLE_WET, C_COBBLE_DARK, C_COBBLE_MID, C_COBBLE_HI],
        rng, caps=(True, True), top_mat='limestone', top_col=C_COBBLE_HI,
    )

    for yc, hx, hz in ((-2.80, 2.74, 1.94), (0.0, 2.62, 1.82), (DECK_Y, 2.54, 1.74), (3.68, 2.22, 1.30)):
        col_pts.extend(_rect_oct(0.0, yc, 0.0, hx, hz, 0.30))

    for sx_sk in (-1.92, -0.96, 0.0, 0.96, 1.92):
        cbox(mb, (sx_sk, DECK_Y + 0.06, 0.08), (0.20, 0.12, 2.88), 'timber',
             C_DRIFT_DARK if int(sx_sk) % 2 == 0 else C_OAK_DEEP, 0.0)
    for px_p in (-2.48, 2.48):
        for pz_p in (-1.64, 1.64):
            with xf(mb, T(px_p, 0.0, pz_p)):
                cyl(mb, 0.135, -0.35, DECK_Y + 0.44, 6, 'timber', C_DRIFT_DARK, False, 0.0, 0.12)
                cyl(mb, 0.148, DECK_Y + 0.24, DECK_Y + 0.34, 6, 'rope', C_HEMP_MID, False, 0.0)

    # 2. Twin Braced A-Frame Timber Derricks & Overhead Rigging Gantry (x = -1.92 & +1.92, apex y = 3.72 m!)
    GANTRY_Z = 0.08
    APEX_Y = 3.72
    for ax in (-1.92, 1.92):
        for sz_leg in (-1.32, 1.32):
            foot_p = Vector((ax, DECK_Y + 0.04, GANTRY_Z + sz_leg))
            apex_p = Vector((ax, APEX_Y, GANTRY_Z + sz_leg * 0.06))
            _add_beam(mb, foot_p, apex_p, 0.18, 0.18, 'timber', C_OAK_DEEP, 0.0)
            cbox(mb, foot_p + Vector((0.0, 0.08, 0.0)), (0.26, 0.20, 0.26), 'iron', C_IRON_FORGED, 0.0)
        _add_beam(mb, (ax, 1.08, GANTRY_Z - 1.08), (ax, 1.08, GANTRY_Z + 1.08), 0.13, 0.14, 'timber', C_OAK_RICH, 0.0)
        _add_beam(mb, (ax, 2.74, GANTRY_Z - 0.54), (ax, 2.74, GANTRY_Z + 0.54), 0.14, 0.14, 'timber', C_OAK_RICH, 0.0)
        _add_beam(mb, (ax, 1.14, GANTRY_Z - 1.00), (ax, 2.68, GANTRY_Z + 0.46), 0.09, 0.09, 'timber', C_OAK_SUN, 0.0)
        _add_beam(mb, (ax, 1.14, GANTRY_Z + 1.00), (ax, 2.68, GANTRY_Z - 0.46), 0.09, 0.09, 'timber', C_OAK_SUN, 0.0)
        with xf(mb, T(ax, APEX_Y - 0.14, GANTRY_Z) @ M_Y2X):
            torus(mb, 0.22, 0.046, 6, 4, 'rope', C_HEMP_HI, True)
        in_sgn = 1.0 if ax < 0 else -1.0
        _add_beam(mb, (ax, 2.74, GANTRY_Z), (ax + in_sgn * 0.78, APEX_Y - 0.10, GANTRY_Z),
                  0.13, 0.13, 'timber', C_OAK_RICH, 0.0)
        px_out = -2.48 if ax < 0 else 2.48
        for pz_out in (-1.64, 1.64):
            tube(mb, [(ax, APEX_Y - 0.12, GANTRY_Z), (px_out, DECK_Y + 0.30, pz_out)],
                 0.026, 4, 'rope', C_HEMP_DARK, caps=(False, False), mode='flat')

    cbox(mb, (0.0, APEX_Y - 0.04, GANTRY_Z), (4.68, 0.24, 0.24), 'timber', C_OAK_DEEP, 0.0)
    for bx_s in (-1.92, -0.90, 0.0, 0.90, 1.92):
        cbox(mb, (bx_s, APEX_Y - 0.04, GANTRY_Z), (0.14, 0.28, 0.28), 'iron', C_IRON_FORGED, 0.0)

    # Hand-Cranked Careening Hauling Windlass Drum bolted across the Port A-Frame Legs
    with xf(mb, T(-1.92, 1.38, GANTRY_Z)):
        with xf(mb, M_Y2Z):
            cyl(mb, 0.16, -0.76, 0.76, 6, 'timber', C_OAK_SUN, False, 0.0)
            cyl(mb, 0.22, -0.72, -0.64, 6, 'iron', C_IRON_BRIGHT, False, 0.0)
            cyl(mb, 0.22,  0.64,  0.72, 6, 'iron', C_IRON_BRIGHT, False, 0.0)
            for dz_w in (-0.28, -0.14, 0.00):
                with xf(mb, T(0.0, dz_w, 0.0)):
                    torus(mb, 0.185, 0.038, 6, 4, 'rope', C_HEMP_HI, True)
        _add_beam(mb, (0.0, 0.0, -0.82), (-0.28, 0.26, -0.82), 0.05, 0.05, 'iron', C_IRON_FORGED, 0.0)
        with xf(mb, T(-0.28, 0.26, -0.96) @ M_Y2Z):
            cyl(mb, 0.034, -0.16, 0.16, 5, 'timber', C_OAK_SUN, False, 0.0)

    # 3. Salvaged Tilted Painted Galleon Hull Rib-Section hoisted cleanly inside the Careening Cradle!
    M_HULL = T(0.02, 0.92, 0.42) @ R('Y', -4.0) @ R('X', -19.0)
    sling_l, sling_r = _build_salvaged_galleon_section(mb, M_HULL)

    for sx_sh in (-0.92, 0.02, 0.92):
        cbox(mb, (sx_sh, DECK_Y + 0.24, 0.34), (0.22, 0.28, 0.48), 'timber', C_OAK_DEEP, 0.0)
        _add_beam(mb, (sx_sh, DECK_Y + 0.12, -0.44), (sx_sh, 0.96, 0.08), 0.12, 0.12, 'timber', C_OAK_RICH, 0.0)
        _add_beam(mb, (sx_sh, DECK_Y + 0.12,  0.96), (sx_sh, 1.10, 0.56), 0.11, 0.11, 'timber', C_OAK_RICH, 0.0)

    # 4. Wooden Pulley Blocks & Taut Multi-Part Tackle Lines hoisting the Galleon Hull Section!
    for sling_pt in (sling_l, sling_r):
        bx = sling_pt.x
        top_blk = Vector((bx, APEX_Y - 0.38, GANTRY_Z))
        bot_blk = sling_pt + Vector((0.0, 0.24, 0.0))
        _build_pulley_block(mb, top_blk, scale=1.06, hook_down=True)
        _build_pulley_block(mb, bot_blk, scale=0.96, hook_down=False)
        _add_beam(mb, (bx, APEX_Y - 0.08, GANTRY_Z), top_blk + Vector((0.0, 0.14, 0.0)),
                  0.04, 0.04, 'iron', C_IRON_BRIGHT, 0.0)
        _add_beam(mb, bot_blk + Vector((0.0, -0.14, 0.0)), sling_pt,
                  0.036, 0.036, 'iron', C_IRON_BRIGHT, 0.0)
        for off_x in (-0.045, 0.045):
            tube(mb, [top_blk + Vector((off_x, -0.10, 0.0)), bot_blk + Vector((off_x, 0.10, 0.0))],
                 0.025, 4, 'rope', C_HEMP_HI, caps=(False, False), mode='flat')
        lead_mid = Vector((-1.78, APEX_Y - 0.42, GANTRY_Z - 0.10))
        tube(mb, [top_blk + Vector((-0.06, 0.0, 0.0)), lead_mid, Vector((-1.90, 1.54, GANTRY_Z - 0.16))],
             0.026, 4, 'rope', C_HEMP_MID, caps=(False, False), mode='flat')

    # 5. Glowing Pitch-Cauldron Brazier ('glass' warm amber — ZERO skull_glow!) w/ Iron Fire-Cage Bars!
    CAUL_X, CAUL_Z = -1.26, -1.26
    with xf(mb, T(CAUL_X, DECK_Y, CAUL_Z)):
        torus(mb, 0.40, 0.082, 6, 4, 'limestone', C_COBBLE_DARK, False)
        cyl(mb, 0.33, 0.04, 0.16, 6, 'iron', C_IRON_DARK, False, 0.0, 0.36)
        # Deep fiery orange-crimson molten ember coal bed + flame tongues framed by iron grate bars!
        lathe(mb, [(0.0, 0.12), (0.30, 0.14), (0.25, 0.24), (0.14, 0.30), (0.0, 0.32)],
              6, 'glass', C_FLAME_DEEP, False, False,
              lambda i, k: C_FLAME_MID if i >= 3 else (C_FLAME_DEEP if i == 2 else C_MAGMA_CRIMSON))
        for fx_e, fz_e, fh_e in ((-0.14, -0.12, 0.24), (0.16, -0.08, 0.22), (0.00, 0.14, 0.24)):
            tube(mb, [(fx_e, 0.16, fz_e), (fx_e * 0.7, 0.16 + fh_e, fz_e * 0.7)],
                 [0.082, 0.016], 4, 'glass', C_FLAME_MID, caps=(False, True), mode='flat',
                 scols=[C_FLAME_DEEP, C_FLAME_CORE])
        # 6 Vertical forged-iron brazier grate bars + 3 heavy tripod legs holding the tar cauldron!
        for k in range(6):
            ang = radians(k * 60.0)
            cbox(mb, (0.31 * cos(ang), 0.26, 0.31 * sin(ang)), (0.040, 0.28, 0.040), 'iron', C_IRON_DARK, 0.0)
        for k in range(3):
            ang = radians(30.0 + k * 120.0)
            _add_beam(mb, (0.42 * cos(ang), 0.0, 0.42 * sin(ang)), (0.26 * cos(ang), 0.72, 0.26 * sin(ang)),
                      0.044, 0.044, 'iron', C_IRON_FORGED, 0.0)
        caul_prof = [
            (0.00, 0.34), (0.26, 0.38), (0.36, 0.56), (0.34, 0.74), (0.38, 0.78), (0.31, 0.78), (0.00, 0.71),
        ]
        lathe(mb, caul_prof, 6, 'iron', C_IRON_DARK, False, False,
              lambda i, k: C_PITCH_TAR if i >= 5 else (C_IRON_RUST_HI if i == 3 else C_IRON_DARK))
        # Wooden caulking pitch-mop tilted cleanly forward-port (zero clipping with hoisted hull!)
        _add_beam(mb, (0.04, 0.62, 0.02), (-0.34, 1.22, -0.26), 0.036, 0.036, 'timber', C_OAK_SUN, 0.0)
        cbox(mb, (-0.04, 0.73, -0.04), (0.14, 0.13, 0.14), 'rope', C_PITCH_TAR, 0.0)

    # 6. Stacked Oak Caulking Planks, Hull-Scraper & Rear Reserve Careening Gear!
    STK_X, STK_Z = 1.16, -1.24
    for bx_s in (-0.54, 0.54):
        cbox(mb, (STK_X + bx_s, DECK_Y + 0.06, STK_Z), (0.14, 0.12, 0.60), 'timber', C_OAK_DEEP, 0.0)
    for layer in range(4):
        cbox(mb, (STK_X + 0.03 * (layer - 1.5), DECK_Y + 0.16 + layer * 0.075, STK_Z + 0.02 * (layer % 2)),
             (1.56 - 0.06 * layer, 0.060, 0.50), 'timber',
             C_OAK_SUN if layer % 2 == 0 else C_DRIFT_PALE, 0.0, M=R('Y', -4.0 + layer * 2.5))
    _add_beam(mb, (0.30, DECK_Y + 0.02, -1.36), (0.56, DECK_Y + 0.94, -1.04), 0.036, 0.036, 'timber', C_OAK_RICH, 0.0)
    cbox(mb, (0.30, DECK_Y + 0.09, -1.36), (0.24, 0.12, 0.03), 'iron', C_IRON_BRIGHT, 0.0, M=R('Y', 24.0))
    _build_serving_mallet(mb, T(1.36, DECK_Y + 0.42, -1.24) @ R('Y', -35.0), scale=1.06)

    _build_coopered_barrel(mb, T(-1.12, DECK_Y + 0.34, 1.34) @ R('Y', -18.0),
                           radius=0.26, height=0.66, rng=rng, segs=6)
    _build_rope_coil(mb, (0.18, DECK_Y + 0.02, 1.40), radius=0.30, turns=2, r=0.048, segs=6, psegs=4,
                     col_a=C_HEMP_HI, col_b=C_HEMP_MID)
    cbox(mb, (1.16, DECK_Y + 0.24, 1.34), (0.82, 0.46, 0.50), 'timber', C_OAK_RICH, 0.0, M=R('Y', -10.0))
    cbox(mb, (1.16, DECK_Y + 0.46, 1.34), (0.86, 0.08, 0.54), 'timber', C_OAK_DEEP, 0.0, M=R('Y', -10.0))
    cbox(mb, (1.16, DECK_Y + 0.28, 1.60), (0.12, 0.12, 0.05), 'brass', C_GOLD_BRIGHT, 0.0)

    # 7. Fluttering Red-Gold Buccaneers' Burgee ('paint' + UV2!) streaming inward-seaward cleanly inside 5.6 m W!
    FLAG_X, FLAG_Z = 1.92, GANTRY_Z
    with xf(mb, T(FLAG_X, 0.0, FLAG_Z)):
        cyl(mb, 0.064, APEX_Y - 0.06, 4.24, 6, 'timber', C_OAK_DEEP, False, 0.0, 0.038)
        lathe(mb, [(0.0, 4.22), (0.075, 4.28), (0.0, 4.35)], 6, 'brass', C_GOLD_BRIGHT, False)
    _build_wind_banner(
        mb, root_pos=(FLAG_X - 0.05, 4.02, FLAG_Z), length=1.34, h0=0.38,
        out_dir=(-0.78, -0.04, -0.62),
        col_main=C_CRIMSON_HI, col_alt=C_GOLD_BRIGHT, col_trim=C_CREAM_SAIL,
        phase=0.52, swallowtail=True,
    )

    # 8. Warm Brass Careening Work-Lantern ('Lantern_Careening') hanging cleanly over Front-Port Brazier!
    LANTERN_POS = Vector((-1.78, 2.34, -1.16))
    _add_beam(mb, (-1.92, 2.74, GANTRY_Z - 0.54), (-1.78, 2.74, -1.24), 0.085, 0.09, 'timber', C_OAK_RICH, 0.0)
    _add_beam(mb, (-1.92, 2.28, GANTRY_Z - 0.72), (-1.82, 2.72, -1.04), 0.06, 0.06, 'iron', C_IRON_FORGED, 0.0)
    _add_beam(mb, (-1.78, 2.74, -1.16), LANTERN_POS + Vector((0.0, 0.28, 0.0)), 0.025, 0.025, 'iron', C_IRON_FORGED, 0.0)
    _build_storm_lantern(mb, LANTERN_POS, scale=0.86, brass_cage=True, hanging=True)

    # 9. Hardy Coastal Beach Fern Tufts ('foliage' + UV2!) tucked snugly at the Cobble Seawall Corners
    for fpos, fsc, flean, fph in (
        ((-2.32, DECK_Y - 0.04, -1.46), 0.58, (-0.7, 0.0, -0.7), 0.18),
        (( 2.32, DECK_Y - 0.04, -1.46), 0.58, ( 0.7, 0.0, -0.7), 0.44),
        ((-2.32, DECK_Y - 0.04,  1.46), 0.58, (-0.7, 0.0,  0.7), 0.71),
        (( 2.32, DECK_Y - 0.04,  1.46), 0.58, ( 0.7, 0.0,  0.7), 0.92),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=3, rng=rng, phase=fph, lean_dir=flean, segs=2)

    build(mb)

    add_empty('Lantern_Careening', LANTERN_POS)
    col_piece('col_careening_base', col_pts)
    export_landmark_glb(outdir, 'coastal_buccaneer_careening_cradle.glb')


# ==============================================================================
# 4. VOLCANIC OBSIDIAN KRAKEN ALTAR (volcanic_obsidian_kraken_altar.glb)
# ==============================================================================

def _build_obsidian_tentacle(mb, corner_ang_deg, base_r, peak_h, flare_out, sway_sgn, rng):
    """Smooth C2 sweeping & curling faceted volcanic obsidian Kraken tentacle arching gracefully
    outward and soaring upward to curl inward around an open sky-window above the molten cauldron,
    with faceted ventral suckers, glowing base magma crack ('glass'), and snug iron shackle cuff!
    Returns world-space position of the bolted iron shackle anchor lug."""
    ar = radians(corner_ang_deg)
    rad_dir = Vector((cos(ar), 0.0, sin(ar))).normalized()
    tan_dir = Vector((-sin(ar), 0.0, cos(ar))).normalized()

    # 11 smooth spline stations: rooted solidly into basalt plinth -> sweeping gracefully outward ->
    # soaring to peak -> smooth organic spiral-hook curl framing an unobstructed sky-window overhead!
    n_st = 10
    pts = []
    rads = []
    for i in range(n_st + 1):
        t = i / float(n_st)
        # Smooth continuous parametric arch + inward spiral tip (zero abrupt kinks, zero tip collision!)
        # r(t): starts at base_r (1.44), swells gracefully out to ~2.02 around t=0.38, curves smoothly
        # inward to ~0.92 at t=0.88, then hooks gently back out/down to ~1.06 at t=1.0 like a real octopus curl!
        r_dist = (
            base_r * (1.0 - t)
            + 0.96 * t
            + flare_out * sin(t * pi * 1.05) * ((1.0 - t) ** 0.45)
            - 0.24 * sin(max(0.0, (t - 0.55) / 0.45) * pi)
        )
        # y(t): rises smoothly to peak_h around t=0.80, then curls gracefully downward 0.58 m at tip!
        y_arch = 0.16 + (peak_h - 0.16) * (sin(min(1.0, t / 0.82) * pi * 0.5) ** 0.92)
        curl_t = max(0.0, (t - 0.78) / 0.22)
        y_val = y_arch - 0.56 * (curl_t ** 1.65)
        sw_off = 0.26 * sin(t * pi * 1.25) * sway_sgn
        pt = rad_dir * r_dist + tan_dir * sw_off + Vector((0.0, y_val, 0.0))
        pts.append(pt)
        rads.append(0.43 * ((1.0 - 0.88 * (t ** 1.15)) ** 0.92) + 0.022)

    # Crisp 5-sided keeled faceted obsidian cross-section (razor dorsal crest + broad ventral sucker belly)
    secs = []
    scols = []
    in_vecs = []
    side_vecs = []
    for i in range(n_st + 1):
        t = i / float(n_st)
        tang = (pts[min(i + 1, n_st)] - pts[max(i - 1, 0)]).normalized()
        to_ctr = Vector((-pts[i].x, 0.0, -pts[i].z))
        if to_ctr.length < 1e-4:
            to_ctr = -rad_dir
        to_ctr.normalize()
        vent = to_ctr - tang * to_ctr.dot(tang)
        if vent.length < 1e-4:
            vent = Vector((0.0, -1.0, 0.0))
        vent.normalize()
        lat = tang.cross(vent).normalized()
        in_vecs.append(vent)
        side_vecs.append(lat)

        r = rads[i]
        ring = [
            pts[i] - vent * (r * 1.22),                          # sharp obsidian dorsal spine ridge
            pts[i] - vent * (r * 0.24) + lat * (r * 1.00),
            pts[i] + vent * (r * 0.76) + lat * (r * 0.62),
            pts[i] + vent * (r * 0.76) - lat * (r * 0.62),
            pts[i] - vent * (r * 0.24) - lat * (r * 1.00),
        ]
        secs.append(ring)
        scols.append(
            C_OBSIDIAN_EDGE if t > 0.66 else (C_OBSIDIAN_HI if t > 0.30 else C_OBSIDIAN_MID)
        )

    loft(mb, secs, 'basalt', C_OBSIDIAN_HI, closed=True, caps=(True, True), mode='flat', scols=scols)

    # Paired Faceted Volcanic Suction-Cup Bosses lining the Inner Ventral Arch (4 pairs per tentacle!)
    for si in (2, 4, 6, 8):
        p = pts[si]
        vent = in_vecs[si]
        lat = side_vecs[si]
        r = rads[si]
        rot_v = Vector((0.0, 1.0, 0.0)).rotation_difference(vent).to_matrix().to_4x4()
        for sgn_s in (-1.0, 1.0):
            cup_r = r * 0.45
            cup_p = p + vent * (r * 0.68) + lat * (sgn_s * r * 0.40)
            with xf(mb, T(cup_p) @ rot_v):
                cyl(mb, cup_r, -0.02, cup_r * 0.72, 4, 'basalt', C_OBSIDIAN_EDGE, False, 0.0, cup_r * 0.78)
                if si == 4:
                    cyl(mb, cup_r * 0.42, cup_r * 0.66, cup_r * 0.80, 4, 'glass', C_FLAME_DEEP, False, 0.0)

    # Sharp Obsidian Dorsal Fin-Spurs along outer spine + Glowing Molten Base Crack ('glass' ONLY!)
    for di in (3, 6):
        p = pts[di]
        dors = -in_vecs[di]
        tube(mb, [p + dors * (rads[di] * 0.85), p + dors * (rads[di] * 1.68) + Vector((0.0, 0.14, 0.0))],
             [rads[di] * 0.32, 0.02], 4, 'basalt', C_OBSIDIAN_EDGE, caps=(False, True), mode='flat')

    mag_pts = [pts[0] + rad_dir * 0.34, pts[1] + rad_dir * 0.36, pts[2] + rad_dir * 0.34]
    _sculpt_glow_ribbon(
        mb, mag_pts, [0.09, 0.075, 0.045], rad_dir,
        hot_core=False, ridge_h=0.036, mat='glass',
        c_core=C_FLAME_MID, c_mid_col=C_FLAME_DEEP, c_edge_col=C_MAGMA_CRIMSON, c_tip_col=C_MAGMA_CRIMSON,
    )

    # Heavy Bolted Forged-Iron Restraining Shackle Cuff clamped snugly around Tentacle Waist (station 3)!
    sh_i = 3
    sh_p = pts[sh_i]
    sh_t = (pts[sh_i + 1] - pts[sh_i - 1]).normalized()
    rot_sh = Vector((0.0, 1.0, 0.0)).rotation_difference(sh_t).to_matrix().to_4x4()
    sh_r = rads[sh_i] * 1.15
    with xf(mb, T(sh_p) @ rot_sh):
        cyl(mb, sh_r, -0.14, 0.14, 5, 'iron', C_IRON_FORGED, False, 0.0)
        torus(mb, sh_r + 0.02, 0.044, 5, 4, 'iron', C_IRON_BRIGHT, False)
    # Snug bolted outer iron shackle lug merged right into the shackle cuff!
    shackle_lug = sh_p - in_vecs[sh_i] * (sh_r + 0.04)
    cbox(mb, shackle_lug, (0.22, 0.22, 0.22), 'iron', C_IRON_RUST_HI, 0.0)
    return shackle_lug


def _build_kraken_eye_medallion(mb, center, z_sgn=-1.0, scale=1.0):
    """Carved volcanic obsidian Kraken-Eye medallion framed in forged iron with a fierce blazing
    molten vertical-slit lava eye ('glass' warm molten orange-amber — ZERO skull_glow!)."""
    s = scale
    cx, cy, cz = center
    with xf(mb, T(cx, cy, cz)):
        with xf(mb, M_Y2Z):
            cyl(mb, 0.58 * s, -0.09 * s, 0.09 * s, 8, 'basalt', C_OBSIDIAN_HI, False, 0.0, 0.50 * s)
            torus(mb, 0.54 * s, 0.058 * s, 8, 4, 'iron', C_IRON_FORGED, False)
        # Deep dark obsidian socket recess + fierce angular overhanging brow & lower eyelid ridges
        with xf(mb, T(0.0, 0.0, z_sgn * 0.06 * s) @ S(1.36, 0.90, 1.0) @ M_Y2Z):
            cyl(mb, 0.34 * s, -0.04 * s, 0.04 * s, 8, 'basalt', C_OBSIDIAN_ABYSS, False, 0.0)
        for sy in (-1.0, 1.0):
            _add_beam(mb, (-0.44 * s, sy * 0.22 * s, z_sgn * 0.11 * s),
                      (0.0, sy * 0.36 * s, z_sgn * 0.15 * s), 0.13 * s, 0.13 * s, 'basalt', C_OBSIDIAN_EDGE, 0.0)
            _add_beam(mb, (0.44 * s, sy * 0.22 * s, z_sgn * 0.11 * s),
                      (0.0, sy * 0.36 * s, z_sgn * 0.15 * s), 0.13 * s, 0.13 * s, 'basalt', C_OBSIDIAN_EDGE, 0.0)
        # Rich deep fiery molten lava Kraken iris ('glass' ONLY — deep crimson-orange-amber gradient!)
        with xf(mb, T(0.0, 0.0, z_sgn * 0.09 * s) @ S(1.28, 0.78, 1.0) @ M_Y2Z):
            cyl(mb, 0.28 * s, -0.04 * s, 0.04 * s, 8, 'glass', C_MAGMA_CRIMSON, False, 0.0)
            cyl(mb, 0.21 * s, -0.06 * s, 0.06 * s, 8, 'glass', C_FLAME_DEEP, False, 0.0)
            cyl(mb, 0.13 * s, -0.08 * s, 0.08 * s, 8, 'glass', C_FLAME_MID, False, 0.0)
        # Razor-sharp Dark Obsidian Vertical Kraken Slit Pupil slicing straight across the molten eye!
        cbox(mb, (0.0, 0.0, z_sgn * 0.15 * s), (0.085 * s, 0.40 * s, 0.08 * s), 'basalt', C_OBSIDIAN_ABYSS, 0.0)
        for sx in (-1.0, 1.0):
            cbox(mb, (sx * 0.56 * s, 0.0, z_sgn * 0.06 * s), (0.14 * s, 0.24 * s, 0.12 * s),
                 'iron', C_IRON_RUST_HI, 0.0, M=R('Z', sx * 22.0))


def gen_volcanic_obsidian_kraken_altar(outdir):
    """Monumental charred-basalt & obsidian abyssal Kraken shrine (~4.4 m W x 4.2 m D x 5.6 m H,
    -3.40 m deep lava-cracked basalt foundation skirt) featuring 4 towering curling faceted
    obsidian tentacles arching dramatically around a blazing molten lava offering cauldron
    ('glass' warm molten orange-amber linear COLOR_0 — ZERO skull_glow!), iron shackles &
    restraining chains, carved volcanic kraken-eye medallion & lava-cracked plinth, convex
    collider 'col_volckraken_base', and empty 'Lantern_VolcKraken'."""
    clear_scene()
    mb = MB('volcanic_obsidian_kraken_altar', seed=2004)
    rng = random.Random(SEED + 2004)
    col_pts = []

    STEP1_Y = 0.44
    DAIS_Y  = 0.96
    CAUL_Y  = 2.04

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

    for yc, rc in ((-3.40, 2.20), (0.0, 2.06), (DAIS_Y, 2.04), (5.38, 1.96)):
        col_pts.extend(_reg_poly(0.0, yc, 0.0, rc, sides=8, rot_deg=22.5, sx=1.00, sz=0.95))

    # Jagged Volcanic Stone Offering Steps on Seaward (-Z) Hero Approach
    cbox(mb, (0.0, 0.22, -2.02), (1.36, 0.42, 0.36), 'basalt', C_OBSIDIAN_MID, 0.0)
    cbox(mb, (0.0, 0.62, -1.68), (1.16, 0.36, 0.36), 'basalt', C_OBSIDIAN_HI, 0.0)

    # 6 Radiating Molten Lava Cracks ('glass' ONLY!) splitting across the stepped basalt plinth!
    for c_ang in (-145.0, -90.0, -35.0, 35.0, 90.0, 145.0):
        ar = radians(c_ang)
        ca, sa = cos(ar), sin(ar)
        p0 = Vector((0.66 * ca, DAIS_Y + 0.03, 0.62 * sa))
        p1 = Vector((1.38 * ca - 0.09 * sa, DAIS_Y + 0.02, 1.30 * sa + 0.09 * ca))
        p2 = Vector((1.88 * ca, STEP1_Y + 0.03, 1.78 * sa))
        _sculpt_glow_ribbon(
            mb, [p0, p1, p2], [0.10, 0.082, 0.054], (0.0, 1.0, 0.0),
            hot_core=True, ridge_h=0.038, mat='glass',
            c_core=C_FLAME_MID, c_mid_col=C_FLAME_DEEP, c_edge_col=C_MAGMA_CRIMSON, c_tip_col=C_MAGMA_CRIMSON,
        )

    # 2. Central Carved Obsidian Altar Pedestal & Volcanic Kraken-Eye Medallions (y = 0.96 .. 2.06 m)
    ped_secs = [
        _rect_oct(0.0, DAIS_Y - 0.02, 0.0, 0.98, 0.92, 0.26),
        _rect_oct(0.0, 1.48,          0.0, 0.86, 0.82, 0.22),
        _rect_oct(0.0, CAUL_Y,        0.0, 1.02, 0.96, 0.28),
    ]
    _loft_horizontal_masonry(
        mb, ped_secs, 'basalt',
        [C_OBSIDIAN_DARK, C_OBSIDIAN_MID, C_OBSIDIAN_EDGE],
        rng, caps=(False, True), top_mat='basalt', top_col=C_OBSIDIAN_HI,
    )
    cbox(mb, (0.0, CAUL_Y - 0.06, 0.0), (2.06, 0.14, 1.94), 'iron', C_IRON_FORGED, 0.0)

    _build_kraken_eye_medallion(mb, (0.0, 1.50, -0.88), z_sgn=-1.0, scale=1.04)
    _build_kraken_eye_medallion(mb, (0.0, 1.50,  0.88), z_sgn= 1.0, scale=0.88)

    # 3. Blazing Molten Lava Offering Cauldron perched atop the Altar (y = 2.04 .. 3.20 m, 'glass' ONLY!)
    with xf(mb, T(0.0, CAUL_Y, 0.0)):
        caul_prof = [
            (0.00, 0.00),
            (0.76, 0.00),
            (0.96, 0.28),
            (1.04, 0.62),
            (0.92, 0.72),
            (0.78, 0.56),
            (0.00, 0.48),
        ]
        lathe(mb, caul_prof, 8, 'iron', C_IRON_DARK, False, False,
              lambda i, k: C_IRON_RUST_HI if i in (2, 3) else C_IRON_FORGED)
        with xf(mb, T(0.0, 0.64, 0.0)):
            torus(mb, 1.00, 0.072, 8, 4, 'iron', C_IRON_BRIGHT, False)
        # 6 Jagged Carved Obsidian & Forged-Iron Buttress Spikes cradling the Cauldron Bowl!
        for k in range(6):
            ar = radians(k * 60.0 + 30.0)
            ca, sa = cos(ar), sin(ar)
            is_obs = (k % 2 == 0)
            r_pts = [
                Vector((0.86 * ca, 0.02, 0.86 * sa)),
                Vector((1.08 * ca, 0.42, 1.08 * sa)),
                Vector((1.16 * ca, 0.90 if is_obs else 0.76, 1.16 * sa)),
            ]
            tube(mb, r_pts, [0.125, 0.095, 0.024], 4, 'basalt' if is_obs else 'iron',
                 C_OBSIDIAN_EDGE if is_obs else C_IRON_RUST_HI, caps=(False, True), mode='flat')

        # Blazing Boiling Molten Lava Offering Pool + Floating Charred Obsidian Lava-Crust Chunks!
        lathe(mb, [(0.0, 0.48), (0.86, 0.56), (0.74, 0.72), (0.44, 0.84), (0.0, 0.90)],
              8, 'glass', C_FLAME_DEEP, False, False,
              lambda i, k: C_FLAME_CORE if i >= 4 else (C_FLAME_MID if i == 3 else (C_FLAME_DEEP if i == 2 else C_MAGMA_CRIMSON)))
        # Floating dark volcanic slag/obsidian crust islands breaking up the glowing magma surface!
        for cx_c, cz_c, rot_c in ((-0.46, -0.26, 22.0), (0.44, -0.30, -34.0), (0.08, 0.46, 54.0)):
            cbox(mb, (cx_c, 0.70, cz_c), (0.34, 0.14, 0.24), 'basalt', C_OBSIDIAN_ABYSS, 0.0,
                 M=R('Y', rot_c) @ R('X', 12.0))
        # Dramatic Sculpted Rising Molten Magma Plumes ('glass' warm orange-amber!)
        for fx_f, fz_f, fh_f, fr_f, fcol_top in (
            ( 0.00,  0.00, 0.92, 0.28, C_FLAME_CORE),
            (-0.28, -0.18, 0.68, 0.18, C_FLAME_MID),
            ( 0.30,  0.14, 0.66, 0.18, C_FLAME_MID),
        ):
            fl_pts = [
                Vector((fx_f, 0.64, fz_f)),
                Vector((fx_f * 0.72, 0.64 + fh_f * 0.54, fz_f * 0.72)),
                Vector((fx_f * 0.40 + 0.05, 0.64 + fh_f, fz_f * 0.40)),
            ]
            tube(mb, fl_pts, [fr_f, fr_f * 0.54, 0.020], 5, 'glass', C_FLAME_MID,
                 caps=(False, True), mode='flat', scols=[C_FLAME_DEEP, fcol_top, C_FLAME_CORE])
        # Twin molten lava overflows spilling down the front & rear cauldron lips!
        for z_ov in (-1.0, 1.0):
            ov_pts = [
                Vector((0.0, 0.68, z_ov * 0.94)),
                Vector((0.0, 0.44, z_ov * 1.06)),
                Vector((0.0, 0.10, z_ov * 1.02)),
            ]
            _sculpt_glow_ribbon(
                mb, ov_pts, [0.10, 0.075, 0.048], (0.0, 0.0, z_ov),
                hot_core=True, ridge_h=0.036, mat='glass',
                c_core=C_FLAME_MID, c_mid_col=C_FLAME_DEEP, c_edge_col=C_MAGMA_CRIMSON, c_tip_col=C_MAGMA_CRIMSON,
            )

    # 4. Four Towering Smooth-Curling Faceted Obsidian Tentacles + Heavy Iron Shackles & Chains!
    # Rear two soar to ~5.58 m and 5.32 m; Front two frame hero view cleanly at ~4.82 m and 4.98 m!
    tentacle_specs = [
        ( 46.0, 1.46, 5.56, 0.86,  1.0),   # Rear-Starboard (+X, +Z) — tallest sweeping crown!
        (134.0, 1.46, 5.32, 0.84, -1.0),   # Rear-Port (-X, +Z)
        (224.0, 1.44, 4.80, 0.82,  1.0),   # Front-Port (-X, -Z) — wide open hero frame!
        (316.0, 1.44, 4.98, 0.82, -1.0),   # Front-Starboard (+X, -Z)
    ]
    for c_ang, b_r, p_h, fl_o, sw in tentacle_specs:
        shackle_lug = _build_obsidian_tentacle(mb, c_ang, b_r, p_h, fl_o, sw, rng)

        ar = radians(c_ang)
        ca, sa = cos(ar), sin(ar)
        spur_bp = Vector((1.78 * ca, -0.35, 1.70 * sa))
        spur_dir = Vector((0.28 * ca, 1.0, 0.28 * sa)).normalized()
        spur_pts = [spur_bp, spur_bp + spur_dir * 1.02, spur_bp + spur_dir * 1.78]
        tube(mb, spur_pts, [0.34, 0.23, 0.03], 4, 'basalt', C_OBSIDIAN_HI,
             caps=(False, True), mode='flat',
             scols=[C_OBSIDIAN_DARK, C_OBSIDIAN_MID, C_OBSIDIAN_EDGE])
        bot_anchor = spur_pts[1] + Vector((0.0, 0.16, 0.0))
        with xf(mb, T(bot_anchor)):
            cyl(mb, 0.26, -0.09, 0.09, 6, 'iron', C_IRON_BRIGHT, False, 0.0)

        _add_chain_links(
            mb, shackle_lug + Vector((0.0, -0.04, 0.0)), bot_anchor + Vector((0.0, 0.08, 0.0)),
            n_links=4, link_r=0.19, wire_r=0.054, segs=5, psegs=4, sag=0.14,
            mat='iron', rust_stride=2, stretch_y=1.46,
            col_a=C_IRON_BRIGHT, col_b=C_IRON_RUST_HI,
        )

    LANTERN_POS = Vector((0.0, 2.74, 0.0))

    build(mb)

    add_empty('Lantern_VolcKraken', LANTERN_POS)
    col_piece('col_volckraken_base', col_pts)
    export_landmark_glb(outdir, 'volcanic_obsidian_kraken_altar.glb')


ARMADA_RELICS_GENERATORS = [
    gen_pirate_ropewalk_cordage_loom,
    gen_ancient_tidal_compass_sanctum,
    gen_coastal_buccaneer_careening_cradle,
    gen_volcanic_obsidian_kraken_altar,
]
