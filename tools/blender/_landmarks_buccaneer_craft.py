# Sea of Scoundrels: 4 sculpted 3D Buccaneer Craft & Mythic Coast Landmarks
# (Wave I-23 / Pass I-Q16 — Road to the 100-Landmark Centennial: 90 -> 94 Zero-Extra-VRAM Landmarks!).
# Imported by tools/blender/gen_island_landmarks.py.
# Authored in Godot game coordinates (-Z seaward/hero-facing, +Y up, +X starboard, metres)
# and converted to Blender's Z-up frame on mesh creation via _landmark_common.
# STRICT SHARED-TEXTURE DEDUP CONTRACT: uses ONLY the 11 existing shared PBR materials
# (limestone, limestone_moss, basalt, temple_stone, skull_stone, timber, paint, rope,
# iron, brass, foliage) + untextured glass / skull_glow / col.
# Emissive rule:
#   - mat_landmark_skull_glow ONLY on ancient_abyssal_nautilus_shrine (hovering luminous
#     turquoise-cyan sea-pearl orb, glowing aquatic basin runes & coral brazier sea-flames)
#   - mat_landmark_glass with warm amber/molten linear COLOR_0 on pirate_blacksmith_anchor_forge,
#     coastal_smuggler_signal_tripod, and volcanic_obsidian_wyrm_arch (ZERO skull_glow!).
import math
import random
from math import sin, cos, exp, pi, sqrt, atan2, radians, degrees
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

# Coastal harbour cobble, headland limestone & mossy abyssal temple masonry
C_COBBLE_HI      = srgb('#d4c7b0')
C_COBBLE_MID     = srgb('#978c7a')
C_COBBLE_DARK    = srgb('#5d554a')
C_COBBLE_WET     = srgb('#3c3c36')
C_FORGE_STONE_HI = srgb('#c2b59e')
C_FORGE_STONE_MD = srgb('#887e70')
C_FORGE_STONE_DK = srgb('#4f4942')
C_SOOT_STONE     = srgb('#2a2625')

C_HEADLAND_HI    = srgb('#e7d3ae')
C_HEADLAND_MID   = srgb('#bfa074')
C_HEADLAND_DARK  = srgb('#826a4e')
C_HEADLAND_DEEP  = srgb('#4e4134')

C_NAUTILUS_HI    = srgb('#e5dec8')
C_NAUTILUS_MID   = srgb('#b2aa94')
C_NAUTILUS_DARK  = srgb('#736f5f')
C_NAUTILUS_DEEP  = srgb('#48483e')
C_CORAL_PALE     = srgb('#d9b6a4')
C_CORAL_ROSE     = srgb('#b8685c')
C_MOSS_CUSHION   = srgb('#4c8532')
C_MOSS_DEEP      = srgb('#29501f')

# Seasoned smithy oak, driftwood spars, shingled cedar & leather accents
C_OAK_PALE       = srgb('#e3be84')
C_OAK_SUN        = srgb('#c98e50')
C_OAK_RICH       = srgb('#8b582d')
C_OAK_DEEP       = srgb('#52321a')
C_OAK_CHAR       = srgb('#261912')
C_DRIFT_SUN      = srgb('#c4b296')
C_DRIFT_MID      = srgb('#988872')
C_DRIFT_DARK     = srgb('#5f5448')
C_SHINGLE_A      = srgb('#7e5538')
C_SHINGLE_B      = srgb('#5c4130')
C_SHINGLE_MOSS   = srgb('#546445')
C_LEATHER_HI     = srgb('#7c3b24')
C_LEATHER_DARK   = srgb('#461f14')

# Painted accents: buccaneer crimson, gold, cream, smuggler teal & quench water
C_CRIMSON_HI     = srgb('#df3222')
C_CRIMSON_MID    = srgb('#a32018')
C_CRIMSON_DARK   = srgb('#63130f')
C_CREAM_BRIGHT   = srgb('#f6e9cc')
C_CREAM_AGED     = srgb('#d6c096')
C_GOLD_CLOTH     = srgb('#ebb232')
C_TEAL_HI        = srgb('#249498')
C_TEAL_DARK      = srgb('#165258')
C_QUENCH_WATER   = srgb('#1c5f6a')

C_HEMP_HI        = srgb('#e5c68e')
C_HEMP_MID       = srgb('#be985c')
C_HEMP_DARK      = srgb('#846437')

# Metals: burnished brass, gilded bronze, verdigris bronze, bright steel & forged iron
C_GOLD_BRIGHT    = srgb('#fcd654')
C_BRASS_WARM     = srgb('#dca43a')
C_BRASS_DARK     = srgb('#8c611d')
C_VERDIGRIS_HI   = srgb('#56bfa6')
C_VERDIGRIS_MID  = srgb('#2f8773')
C_STEEL_BRIGHT   = srgb('#adb8c8')
C_IRON_BRIGHT    = srgb('#8590a2')
C_IRON_FORGED    = srgb('#4b5262')
C_IRON_DARK      = srgb('#242731')
C_IRON_RUST_HI   = srgb('#b86234')
C_IRON_RUST_MID  = srgb('#7d4122')

# Volcanic charred basalt & high-contrast faceted obsidian
C_OBSIDIAN_EDGE  = srgb('#b6aac9')
C_OBSIDIAN_HI    = srgb('#796f8c')
C_OBSIDIAN_MID   = srgb('#494257')
C_OBSIDIAN_DARK  = srgb('#272332')
C_OBSIDIAN_ABYSS = srgb('#14111a')

# Luminous turquoise-cyan abyssal glow (USED ONLY with 'skull_glow' on ancient_abyssal_nautilus_shrine!)
C_AQUA_WHITE     = srgb('#c2fffb')
C_AQUA_CORE      = srgb('#72fff4')
C_AQUA_MID       = srgb('#18e2c7')
C_AQUA_DEEP      = srgb('#078d82')

# Warm amber coals, forge lanterns, beacon fire & molten magma (USED ONLY with 'glass' on the other 3 GLBs!)
C_FLAME_WHITE    = srgb('#ffdb5c')
C_FLAME_CORE     = srgb('#ff8214')
C_FLAME_MID      = srgb('#e63a04')
C_FLAME_DEEP     = srgb('#a01502')
C_MAGMA_CRIMSON  = srgb('#5e0801')

# Tropical coastal vines & headland ferns
C_VINE_DARK      = srgb('#184e1f')
C_VINE_MID       = srgb('#327d29')
C_VINE_SUN       = srgb('#86c82d')


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


def _open_band(mb, radius, y0, y1, segs, mat, col):
    """Lightweight uncapped cylindrical band/hoop (zero hidden end-cap tris!)."""
    lathe(mb, [(radius, y0), (radius, y1)], segs, mat, col, False, False)


def _build_storm_lantern(mb, center, scale=1.0, brass_cage=True, hanging=True):
    """Chunky nautical brass-and-iron storm lantern with warm glowing amber 'glass' core."""
    cx, cy, cz = center
    s = scale
    cage_mat = 'brass' if brass_cage else 'iron'
    cage_col = C_GOLD_BRIGHT if brass_cage else C_IRON_FORGED
    with xf(mb, T(cx, cy, cz)):
        cyl(mb, 0.145 * s, -0.22 * s, -0.14 * s, 6, 'iron', C_IRON_FORGED, False, 0.0, 0.165 * s)
        cyl(mb, 0.175 * s,  0.15 * s,  0.23 * s, 6, cage_mat, cage_col, False, 0.0, 0.072 * s)
        cyl(mb, 0.065 * s,  0.23 * s,  0.30 * s, 6, 'brass', C_BRASS_WARM, False, 0.0, 0.036 * s)
        cyl(mb, 0.120 * s, -0.14 * s,  0.15 * s, 6, 'glass', C_FLAME_CORE, False, 0.0, 0.130 * s)
        for k in range(4):
            ang = k * pi * 0.5 + pi * 0.25
            cbox(mb, (0.142 * s * cos(ang), 0.005 * s, 0.142 * s * sin(ang)),
                 (0.028 * s, 0.31 * s, 0.028 * s), cage_mat, cage_col, 0.0)
        if hanging:
            with xf(mb, T(0.0, 0.33 * s, 0.0) @ M_Y2Z):
                torus(mb, 0.052 * s, 0.014 * s, 5, 4, 'iron', C_IRON_FORGED, False)


def _build_rope_coil(mb, center, radius=0.26, turns=2, r=0.044, segs=6, psegs=4,
                     col_a=C_HEMP_HI, col_b=C_HEMP_MID):
    """Stacked coiled braided mooring rope pile ('rope')."""
    for i in range(turns):
        rr = radius * (1.0 - 0.19 * i)
        with xf(mb, T(center[0], center[1] + r * (1.0 + i * 1.56), center[2])):
            torus(mb, rr, r, segs, psegs, 'rope', col_a if i % 2 == 0 else col_b, True)


def _build_wind_banner(mb, root_pos, length=1.38, h0=0.42, out_dir=(0.92, -0.02, -0.38),
                       col_main=C_CRIMSON_HI, col_alt=C_GOLD_CLOTH, col_trim=C_CREAM_BRIGHT,
                       phase=0.28, swallowtail=True, triangular=False):
    """Wind-whipped double-sided striped guild burgee/signal pennant ('paint') with UV2 breeze weights."""
    rp = Vector(root_pos)
    od = Vector(out_dir).normalized()
    side = Vector((-od.z, 0.0, od.x))
    if side.length < 1e-4:
        side = Vector((1.0, 0.0, 0.0))
    side.normalize()
    segs = 4 if triangular else 5
    thick = 0.010
    top_pts, bot_pts, weights = [], [], []
    for i in range(segs + 1):
        t = i / float(segs)
        wave = sin(t * 2.15 * pi) * 0.13 * t
        droop = -0.09 * t * t
        taper = 0.94 if triangular else (0.44 if swallowtail else 0.72)
        hh = h0 * (1.0 - taper * t)
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
        if i == segs - 1 and triangular:
            tip = (t1 + b1) * 0.5
            tri = [t0, tip, b0]
            tu2 = [u0, u1, u0]
            f_pts = [p + side * thick for p in tri]
            b_pts = [p - side * thick for p in reversed(tri)]
            ctr_tri = sum(tri, Vector()) / 3.0
            mb.fp(f_pts, 'paint', c_seg, od, ctr_tri - side * 1.0, smooth=False, uv2=tu2)
            mb.fp(b_pts, 'paint', mul(c_seg, 0.84), od, ctr_tri + side * 1.0, smooth=False, uv2=list(reversed(tu2)))
        elif i == segs - 1 and swallowtail:
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
        sway = sin(t * 3.0 + phase * 6.28) * 0.08 * (0.2 + 0.8 * t)
        out_off = 0.02 + 0.05 * sin(t * pi * 0.80) + 0.03 * t
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
        l_scale = (0.85 + 0.42 * sin(t * pi * 0.85)) * (1.0 - 0.24 * t)
        l_len = width * 1.54 * l_scale * rng.uniform(0.88, 1.12)
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


def _add_coastal_fern_cluster(mb, root_pos, scale=0.68, n_fronds=3, rng=None, phase=0.0,
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
    """Surface-hugging glowing molten magma or aquatic glyph vein ridge."""
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


def _add_chain_links(mb, p_start, p_end, n_links=4, link_r=0.16, wire_r=0.044,
                     segs=5, psegs=4, sag=0.12, mat='iron', rust_stride=2, stretch_y=1.42,
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
# 1. PIRATE BLACKSMITH ANCHOR FORGE (pirate_blacksmith_anchor_forge.glb)
# ==============================================================================

def _build_forged_ship_anchor(mb, M_anchor, scale=1.0):
    """Hero-scale forged pirate Admiralty ship's anchor: stout iron shank, riveted oak-and-iron
    stock, shackle ring, sweeping twin arms & sharp barbed triangular flukes."""
    s = scale
    with xf(mb, M_anchor):
        # Heavy tapered forged-iron shank
        cyl(mb, 0.088 * s, 0.00, 1.48 * s, 6, 'iron', C_IRON_FORGED, False, 0.0, 0.064 * s)
        # Crown boss at bottom of shank
        cbox(mb, (0.0, 0.02 * s, 0.0), (0.24 * s, 0.16 * s, 0.18 * s), 'iron', C_IRON_DARK, 0.0)
        # Top forged iron anchor shackle ring + collar nut
        cbox(mb, (0.0, 1.46 * s, 0.0), (0.16 * s, 0.14 * s, 0.16 * s), 'iron', C_IRON_BRIGHT, 0.0)
        with xf(mb, T(0.0, 1.64 * s, 0.0) @ M_Y2Z):
            torus(mb, 0.155 * s, 0.036 * s, 6, 4, 'iron', C_IRON_RUST_HI, False)
        # Heavy riveted timber-and-iron cross-stock (perpendicular to fluke plane -> Z axis!)
        cbox(mb, (0.0, 1.24 * s, 0.0), (0.16 * s, 0.17 * s, 1.12 * s), 'timber', C_OAK_DEEP, 0.0)
        for sz_b in (-0.44 * s, -0.18 * s, 0.18 * s, 0.44 * s):
            cbox(mb, (0.0, 1.24 * s, sz_b), (0.19 * s, 0.20 * s, 0.055 * s), 'iron', C_IRON_BRIGHT, 0.0)
        # Sweeping curved twin anchor arms + broad barbed triangular flukes in X-Y plane!
        for sgn in (-1.0, 1.0):
            arm_pts = [
                Vector((sgn * 0.04 * s, 0.02 * s, 0.0)),
                Vector((sgn * 0.34 * s, 0.06 * s, 0.0)),
                Vector((sgn * 0.62 * s, 0.26 * s, 0.0)),
                Vector((sgn * 0.72 * s, 0.56 * s, 0.0)),
            ]
            tube(mb, arm_pts, [0.088 * s, 0.078 * s, 0.064 * s, 0.042 * s], 5,
                 'iron', C_IRON_FORGED if sgn > 0 else C_IRON_RUST_MID, caps=(False, True), mode='flat')
            # Broad barbed diamond/triangular anchor fluke palm
            with xf(mb, T(sgn * 0.70 * s, 0.52 * s, 0.0) @ R('Z', -sgn * 24.0)):
                fl_secs = [
                    [(-0.08 * s, -0.14 * s, -0.17 * s), (0.08 * s, -0.14 * s, -0.17 * s),
                     (0.08 * s, -0.14 * s,  0.17 * s), (-0.08 * s, -0.14 * s,  0.17 * s)],
                    [(-0.06 * s,  0.04 * s, -0.21 * s), (0.06 * s,  0.04 * s, -0.21 * s),
                     (0.06 * s,  0.04 * s,  0.21 * s), (-0.06 * s,  0.04 * s,  0.21 * s)],
                    [(-0.02 * s,  0.26 * s, -0.02 * s), (0.02 * s,  0.26 * s, -0.02 * s),
                     (0.02 * s,  0.26 * s,  0.02 * s), (-0.02 * s,  0.26 * s,  0.02 * s)],
                ]
                loft(mb, fl_secs, 'iron', C_IRON_BRIGHT, closed=True, caps=(True, True), mode='flat',
                     scols=[C_IRON_FORGED, C_IRON_BRIGHT, C_STEEL_BRIGHT])


def _build_blacksmith_anvil(mb, center, yaw_deg=22.0):
    """Heavy iron anchor-smithing horned anvil bolted atop an iron-hooped seasoned oak stump,
    complete with cross-peen hammer & glowing hot forged iron bar ('glass' ONLY!)."""
    cx, cy, cz = center
    with xf(mb, T(cx, cy, cz) @ R('Y', yaw_deg)):
        # Massive seasoned oak anvil block stump + 2 forged iron reinforcing bands
        cyl(mb, 0.34, 0.0, 0.62, 8, 'timber', C_OAK_RICH, False, 0.0, 0.31)
        _open_band(mb, 0.338, 0.12, 0.18, 8, 'iron', C_IRON_FORGED)
        _open_band(mb, 0.322, 0.44, 0.50, 8, 'iron', C_IRON_RUST_HI)
        # Stepped iron anvil foot + pinched hourglass waist + heavy steel table face
        cbox(mb, (0.0, 0.67, 0.0), (0.48, 0.11, 0.30), 'iron', C_IRON_DARK, 0.0)
        cbox(mb, (0.0, 0.80, 0.0), (0.30, 0.17, 0.18), 'iron', C_IRON_FORGED, 0.0)
        cbox(mb, (0.04, 0.96, 0.0), (0.56, 0.16, 0.24), 'iron', C_IRON_BRIGHT, 0.0)
        cbox(mb, (0.04, 1.045, 0.0), (0.56, 0.032, 0.24), 'iron', C_STEEL_BRIGHT, 0.0)
        # Bold tapered conical blacksmith bick horn pointing port-forward (-X in local anvil frame)
        with xf(mb, T(-0.24, 0.96, 0.0) @ R('Z', 90.0)):
            cyl(mb, 0.112, 0.0, 0.38, 6, 'iron', C_IRON_BRIGHT, False, 0.0, 0.024)
        # Squared anvil heel + hardy lip (+X)
        cbox(mb, (0.38, 0.99, 0.0), (0.16, 0.10, 0.21), 'iron', C_IRON_FORGED, 0.0)
        # Glowing hot forged iron bar being hammered across the anvil face ('glass' warm amber-orange!)
        cbox(mb, (-0.02, 1.078, 0.02), (0.34, 0.044, 0.068), 'glass', C_FLAME_CORE, 0.0, M=R('Y', 14.0))
        cbox(mb, (0.20, 1.076, -0.02), (0.16, 0.042, 0.064), 'iron', C_IRON_DARK, 0.0, M=R('Y', 14.0))
        # Chunky cross-peen blacksmith hammer resting beside the hot bar
        _add_beam(mb, (0.08, 1.09, -0.04), (0.34, 1.09, -0.26), 0.036, 0.036, 'timber', C_OAK_PALE, 0.0)
        cbox(mb, (0.06, 1.11, -0.02), (0.095, 0.095, 0.20), 'iron', C_STEEL_BRIGHT, 0.0, M=R('Y', 42.0))


def _build_forged_cutlass(mb, M_sword):
    """Sculpted pirate forged-iron cutlass w/ curved steel blade, brass basket-guard & dark grip."""
    with xf(mb, M_sword):
        # Grip & pommel
        cyl(mb, 0.022, -0.18, 0.0, 5, 'timber', C_OAK_CHAR, False, 0.0)
        cbox(mb, (0.0, -0.19, 0.0), (0.056, 0.042, 0.056), 'brass', C_GOLD_BRIGHT, 0.0)
        # Brass D-guard knuckle-bow basket hilt
        cbox(mb, (0.0, 0.01, 0.0), (0.055, 0.028, 0.135), 'brass', C_GOLD_BRIGHT, 0.0)
        _add_beam(mb, (0.0, 0.01, 0.065), (0.0, -0.16, 0.052), 0.022, 0.024, 'brass', C_BRASS_WARM, 0.0)
        # Gently curved broad steel cutlass blade
        bl_pts = [
            Vector((0.0, 0.02, 0.0)),
            Vector((0.0, 0.34, -0.014)),
            Vector((0.0, 0.64, -0.052)),
            Vector((0.0, 0.84, -0.105)),
        ]
        bl_secs = []
        for i, bp in enumerate(bl_pts):
            w_b = 0.042 if i < 2 else (0.048 if i == 2 else 0.008)
            t_b = 0.012 if i < 3 else 0.005
            bl_secs.append([
                bp + Vector((-t_b, 0.0, -w_b)),
                bp + Vector(( t_b, 0.0, -w_b)),
                bp + Vector(( t_b, 0.0,  w_b)),
                bp + Vector((-t_b, 0.0,  w_b)),
            ])
        loft(mb, bl_secs, 'iron', C_STEEL_BRIGHT, closed=True, caps=(False, True), mode='flat',
             scols=[C_IRON_BRIGHT, C_STEEL_BRIGHT, C_STEEL_BRIGHT, C_STEEL_BRIGHT])


def _build_forge_bellows(mb, center):
    """Leather-and-iron blacksmith concertina bellows on timber trestle with overhead pumping pole
    and brass/iron tuyere nozzle feeding directly into the stone forge hearth!"""
    cx, cy, cz = center
    with xf(mb, T(cx, cy, cz)):
        # Timber A-trestle stand supporting the bellows
        for lz_b in (-0.28, 0.28):
            _add_beam(mb, (-0.24, 0.0, lz_b), (-0.06, 0.88, lz_b * 0.72), 0.085, 0.085, 'timber', C_OAK_DEEP, 0.0)
            _add_beam(mb, ( 0.22, 0.0, lz_b), ( 0.08, 0.88, lz_b * 0.72), 0.085, 0.085, 'timber', C_OAK_RICH, 0.0)
        cbox(mb, (0.0, 0.86, 0.0), (0.44, 0.075, 0.52), 'timber', C_OAK_SUN, 0.0)
        # Teardrop wooden paddles + pleated dark-leather concertina bellows chamber (pointing +X into forge!)
        bel_secs = [
            [(-0.34, 0.90, -0.26), (0.34, 0.92, -0.10), (0.34, 0.92,  0.10), (-0.34, 0.90,  0.26)],
            [(-0.30, 1.06, -0.22), (0.32, 0.99, -0.09), (0.32, 0.99,  0.09), (-0.30, 1.06,  0.22)],
            [(-0.34, 1.24, -0.26), (0.34, 1.06, -0.10), (0.34, 1.06,  0.10), (-0.34, 1.24,  0.26)],
        ]
        loft(mb, bel_secs, 'paint', C_LEATHER_HI, closed=True, caps=(True, True), mode='flat',
             scols=[C_LEATHER_DARK, C_LEATHER_HI, C_LEATHER_DARK])
        # Seasoned oak top & bottom bellows boards + brass rivet strip
        cbox(mb, (-0.02, 0.90, 0.0), (0.72, 0.048, 0.54), 'timber', C_OAK_DEEP, 0.0)
        cbox(mb, (-0.02, 1.18, 0.0), (0.74, 0.052, 0.54), 'timber', C_OAK_SUN, 0.0, M=R('Z', -14.0))
        cbox(mb, (-0.02, 1.21, 0.0), (0.64, 0.022, 0.08), 'brass', C_BRASS_WARM, 0.0, M=R('Z', -14.0))
        # Tapered iron & brass tuyere nozzle plugging solidly into the port forge firebox wall!
        with xf(mb, T(0.32, 1.00, 0.0) @ M_Y2X):
            cyl(mb, 0.095, 0.0, 0.34, 6, 'iron', C_IRON_FORGED, False, 0.0, 0.052)
            _open_band(mb, 0.086, 0.06, 0.14, 6, 'brass', C_GOLD_BRIGHT)
        # Overhead timber pumping rocker lever & hanging wooden grip handle
        _add_beam(mb, (-0.08, 0.88, -0.24), (-0.08, 1.66, -0.24), 0.075, 0.075, 'timber', C_OAK_DEEP, 0.0)
        _add_beam(mb, (-0.32, 1.24, 0.0), (-0.08, 1.62, -0.18), 0.042, 0.042, 'iron', C_IRON_FORGED, 0.0)
        _add_beam(mb, (-0.30, 1.60, 0.14), (0.26, 1.72, -0.56), 0.056, 0.056, 'timber', C_OAK_PALE, 0.0)
        _add_beam(mb, (0.24, 1.72, -0.54), (0.24, 1.24, -0.54), 0.024, 0.024, 'rope', C_HEMP_HI, 0.0)
        with xf(mb, T(0.24, 0.0, -0.54)):
            cyl(mb, 0.036, 1.10, 1.26, 5, 'timber', C_OAK_RICH, False, 0.0)


def gen_pirate_blacksmith_anchor_forge(outdir):
    """Bustling timber-and-stone pirate harbour blacksmith & anchor forge (~5.4 m W x 4.0 m D x
    4.2 m H, -2.80 m deep cobble wharf skirt) w/ stone forge hood & chimney stack over roaring
    glowing orange coals ('glass' warm amber — ZERO skull_glow!), heavy iron anchor-smithing anvil
    on oak stump, hero forged iron ship's anchor, quenched slack-tub barrel, racked forged iron
    cutlasses & ship chains, leather-and-iron bellows, crimson guild burgee (UV2), convex collider
    'col_anchorforge_base', and warm brass forge-lantern empty 'Lantern_AnchorForge'."""
    clear_scene()
    mb = MB('pirate_blacksmith_anchor_forge', seed=2301)
    rng = random.Random(SEED + 2301)
    col_pts = []

    DECK_Y   = 0.44
    F_POST_Z = -0.82
    R_POST_Z =  1.24
    F_EAVE_Y =  2.76
    RIDGE_Z  = -0.24
    RIDGE_Y  =  3.22
    R_EAVE_Y =  2.22

    # 1. Deep Harbour Cobble & Dressed Stone Wharf Foundation Skirt plunging cleanly to y = -2.80 m (~5.4 m W x 4.0 m D)
    found_secs = [
        _rect_oct(0.0, -2.80, 0.0, 2.62, 1.88, 0.34),
        _rect_oct(0.0, -1.15, 0.0, 2.54, 1.82, 0.32),
        _rect_oct(0.0,  0.00, 0.0, 2.48, 1.76, 0.30),
        _rect_oct(0.0,  0.36, 0.0, 2.42, 1.70, 0.28),
    ]
    _loft_horizontal_masonry(
        mb, found_secs, 'limestone',
        [C_COBBLE_WET, C_COBBLE_DARK, C_COBBLE_MID, C_COBBLE_HI],
        rng, caps=(True, True), top_mat='temple_stone', top_col=C_FORGE_STONE_MD,
    )

    for yc, hx, hz in ((-2.80, 2.62, 1.88), (0.0, 2.48, 1.76), (DECK_Y, 2.42, 1.70), (3.24, 2.24, 1.48), (4.20, 1.65, 1.05)):
        col_pts.extend(_rect_oct(0.0, yc, 0.0, hx, hz, 0.28))

    # Fireproof Dressed Stone Hearth Floor (port half) + Heavy Oak Plank Smithy Deck (starboard half) + Seaward Step!
    cbox(mb, (-1.18, 0.40, 0.0), (2.34, 0.10, 3.24), 'temple_stone', C_FORGE_STONE_MD, 0.0)
    cbox(mb, ( 1.18, 0.37, 0.0), (2.36, 0.10, 3.24), 'timber', C_OAK_DEEP, 0.0)
    for dpi in range(6):
        pz_d = -1.32 + dpi * (2.64 / 5.0)
        cbox(mb, (1.18, DECK_Y - 0.01, pz_d), (2.34, 0.055, 0.48), 'timber',
             C_OAK_SUN if dpi % 2 == 0 else C_DRIFT_MID, 0.0)
    cbox(mb, (0.16, 0.20, -1.84), (1.96, 0.34, 0.36), 'temple_stone', C_FORGE_STONE_HI, 0.0)

    # 4 Stout Iron-Capped Harbour Wharf Corner Pilings
    for px_p in (-2.36, 2.36):
        for pz_p in (-1.60, 1.60):
            top_p = DECK_Y + (0.36 if pz_p < 0 else 0.30)
            with xf(mb, T(px_p, 0.0, pz_p)):
                cyl(mb, 0.130, -0.35, top_p, 6, 'timber', C_DRIFT_DARK, False, 0.0, 0.114)
                _open_band(mb, 0.140, top_p - 0.16, top_p - 0.06, 6, 'iron', C_IRON_FORGED)

    # 2. Timber-and-Stone Smithy Shed Frame + Half-Height Dressed Stone Rear/Side Dwarf Wall!
    for px in (-2.04, 1.98):
        cbox(mb, (px, 0.5 * (DECK_Y + F_EAVE_Y), F_POST_Z), (0.20, F_EAVE_Y - DECK_Y, 0.20), 'timber', C_OAK_DEEP, 0.0)
        cbox(mb, (px, DECK_Y + 0.11, F_POST_Z), (0.27, 0.22, 0.27), 'iron', C_IRON_FORGED, 0.0)
        cbox(mb, (px, F_EAVE_Y - 0.14, F_POST_Z), (0.25, 0.11, 0.25), 'iron', C_IRON_FORGED, 0.0)
        in_sgn = 1.0 if px < 0 else -1.0
        _add_beam(mb, (px, F_EAVE_Y - 0.56, F_POST_Z), (px + in_sgn * 0.56, F_EAVE_Y - 0.04, F_POST_Z),
                  0.10, 0.10, 'timber', C_OAK_RICH, 0.0)
        _add_beam(mb, (px, F_EAVE_Y - 0.52, F_POST_Z), (px, F_EAVE_Y - 0.10, F_POST_Z + 0.52),
                  0.10, 0.10, 'timber', C_OAK_RICH, 0.0)
    for px in (-2.04, 0.14, 1.98):
        cbox(mb, (px, 0.5 * (DECK_Y + R_EAVE_Y), R_POST_Z), (0.19, R_EAVE_Y - DECK_Y, 0.19), 'timber', C_OAK_DEEP, 0.0)
        cbox(mb, (px, DECK_Y + 0.10, R_POST_Z), (0.26, 0.20, 0.26), 'iron', C_IRON_FORGED, 0.0)

    # Half-height dressed stone rear dwarf wall + upper timber sill & diagonal braces (rich Front & Rear!)
    cbox(mb, (-0.03, DECK_Y + 0.44, R_POST_Z), (3.88, 0.88, 0.22), 'temple_stone', C_FORGE_STONE_MD, 0.0)
    cbox(mb, (-0.03, DECK_Y + 0.92, R_POST_Z), (4.02, 0.11, 0.28), 'timber', C_OAK_DEEP, 0.0)
    _add_beam(mb, (0.20, DECK_Y + 0.94, R_POST_Z), (1.90, R_EAVE_Y - 0.12, R_POST_Z), 0.085, 0.075, 'timber', C_OAK_RICH, 0.0)
    _add_beam(mb, (1.90, DECK_Y + 0.94, R_POST_Z), (0.20, R_EAVE_Y - 0.12, R_POST_Z), 0.085, 0.075, 'timber', C_OAK_RICH, 0.0)

    # Roof header plates, ridge beam & 4 rafter trusses
    cbox(mb, (-0.03, F_EAVE_Y - 0.04, F_POST_Z), (4.48, 0.18, 0.18), 'timber', C_OAK_DEEP, 0.0)
    cbox(mb, (-0.03, RIDGE_Y  - 0.12, RIDGE_Z),  (4.52, 0.18, 0.16), 'timber', C_OAK_DEEP, 0.0)
    cbox(mb, (-0.03, R_EAVE_Y - 0.04, R_POST_Z), (4.46, 0.18, 0.18), 'timber', C_OAK_DEEP, 0.0)
    for rx in (-2.04, -0.50, 0.78, 1.98):
        _add_beam(mb, (rx, F_EAVE_Y - 0.04, F_POST_Z - 0.26), (rx, RIDGE_Y - 0.10, RIDGE_Z),
                  0.11, 0.11, 'timber', C_OAK_RICH, 0.0)
        _add_beam(mb, (rx, RIDGE_Y - 0.10, RIDGE_Z), (rx, R_EAVE_Y - 0.06, R_POST_Z + 0.26),
                  0.11, 0.11, 'timber', C_OAK_RICH, 0.0)

    # Stepped Wooden Shingled Saltbox Roof Slopes (visible from BOTH Front & Rear, cleanly pierced by chimney!)
    shingle_cols = [C_SHINGLE_A, C_SHINGLE_B, C_OAK_RICH, C_SHINGLE_MOSS, C_DRIFT_DARK]
    def _build_shingle_slope(z0, y0, z1, y1, n_courses, n_tiles, seed_shift, patch_cells):
        dz = z1 - z0
        dy = y1 - y0
        p_deg = degrees(atan2(dy, dz))
        r_len = sqrt(dz * dz + dy * dy)
        cbox(mb, (-0.03, 0.5 * (y0 + y1) - 0.03, 0.5 * (z0 + z1)),
             (4.58, 0.06, r_len), 'timber', C_OAK_CHAR, 0.0, M=R('X', -p_deg))
        for ci in range(n_courses):
            t = (ci + 0.5) / float(n_courses)
            zc = z0 + dz * t
            yc = y0 + dy * t + 0.042
            cd = r_len / float(n_courses) + 0.07
            for ti in range(n_tiles):
                tw = 4.66 / float(n_tiles)
                tx = -2.36 + tw * (ti + 0.5)
                th = 0.056 + 0.016 * ((ci + ti) % 2)
                if (ci, ti) in patch_cells:
                    tmat, tcol = 'paint', C_CRIMSON_MID
                else:
                    tmat = 'timber'
                    tcol = jit(shingle_cols[(ci * 2 + ti + seed_shift) % len(shingle_cols)], rng, 0.06, 0.02)
                cbox(mb, (tx, yc + 0.010 * ((ci + ti) % 2), zc),
                     (tw - 0.02, th, cd), tmat, tcol, 0.0, M=R('X', -p_deg + (2.4 if dz > 0 else -2.4)))
        for sx_b in (-2.36, 2.30):
            cbox(mb, (sx_b, 0.5 * (y0 + y1) + 0.02, 0.5 * (z0 + z1)),
                 (0.11, 0.16, r_len + 0.08), 'timber', C_OAK_DEEP, 0.0, M=R('X', -p_deg))

    _build_shingle_slope(RIDGE_Z, RIDGE_Y + 0.04, -1.26, 2.68, n_courses=2, n_tiles=4, seed_shift=0, patch_cells={(0, 3)})
    _build_shingle_slope(RIDGE_Z, RIDGE_Y + 0.04,  1.56, 2.18, n_courses=3, n_tiles=4, seed_shift=2, patch_cells={(1, 2), (2, 1)})
    cbox(mb, (-0.03, RIDGE_Y + 0.10, RIDGE_Z), (4.76, 0.14, 0.16), 'timber', C_OAK_SUN, 0.0)

    # 3. Stone Forge Hearth, Tapered Stone-and-Iron Hood & Chimney Stack (y = 0.44 .. 4.22 m) Over Roaring Coals!
    FX, FZ = -1.04, 0.24
    hearth_secs = [
        _rect_oct(FX, DECK_Y - 0.02, FZ, 0.68, 0.60, 0.10),
        _rect_oct(FX, DECK_Y + 0.86, FZ, 0.64, 0.56, 0.09),
    ]
    _loft_horizontal_masonry(
        mb, hearth_secs, 'temple_stone', [C_FORGE_STONE_DK, C_FORGE_STONE_HI],
        rng, caps=(False, True), top_mat='basalt', top_col=C_SOOT_STONE,
    )
    cbox(mb, (FX, DECK_Y + 0.90, FZ + 0.46), (1.30, 0.14, 0.22), 'temple_stone', C_FORGE_STONE_HI, 0.0)
    cbox(mb, (FX - 0.56, DECK_Y + 0.90, FZ), (0.20, 0.14, 1.08), 'temple_stone', C_FORGE_STONE_MD, 0.0)
    cbox(mb, (FX + 0.56, DECK_Y + 0.90, FZ), (0.20, 0.14, 1.08), 'temple_stone', C_FORGE_STONE_MD, 0.0)
    cbox(mb, (FX, DECK_Y + 0.88, FZ - 0.50), (1.28, 0.10, 0.14), 'iron', C_IRON_FORGED, 0.0)
    cbox(mb, (FX, DECK_Y + 0.36, FZ - 0.55), (0.58, 0.50, 0.08), 'basalt', C_OBSIDIAN_ABYSS, 0.0)
    cbox(mb, (FX, DECK_Y + 0.64, FZ - 0.56), (0.70, 0.09, 0.14), 'temple_stone', C_FORGE_STONE_HI, 0.0)
    for gi in (-0.18, 0.0, 0.18):
        cbox(mb, (FX + gi, DECK_Y + 0.36, FZ - 0.57), (0.036, 0.46, 0.036), 'iron', C_IRON_RUST_HI, 0.0)
    cbox(mb, (FX, DECK_Y + 1.38, FZ + 0.46), (1.18, 0.96, 0.24), 'temple_stone', C_FORGE_STONE_DK, 0.0)
    cbox(mb, (FX, DECK_Y + 1.32, FZ + 0.32), (0.94, 0.78, 0.07), 'basalt', C_SOOT_STONE, 0.0)

    # Roaring Glowing Orange Coals & Crisp Flickering Ember Flames ('glass' warm amber ONLY — ZERO skull_glow!)
    with xf(mb, T(FX, DECK_Y + 0.86, FZ - 0.04)):
        lathe(mb, [(0.0, 0.0), (0.40, 0.04), (0.33, 0.16), (0.18, 0.24), (0.0, 0.27)],
              6, 'glass', C_MAGMA_CRIMSON, False, False,
              lambda i, k: C_FLAME_CORE if i >= 3 else (C_FLAME_MID if i == 2 else C_MAGMA_CRIMSON))
        # Chunky dark charred coal lumps nestled across the glowing ember bed for rich painterly contrast!
        for c_ang, cr_d, cy_c, cs_r in (
            (15, 0.34, 0.09, 0.10), (75, 0.30, 0.12, 0.095), (140, 0.35, 0.10, 0.10),
            (205, 0.32, 0.11, 0.09), (265, 0.34, 0.09, 0.10), (320, 0.28, 0.14, 0.085),
        ):
            ar = radians(c_ang)
            cbox(mb, (cr_d * cos(ar), cy_c, cr_d * sin(ar)),
                 (cs_r * 1.45, cs_r, cs_r * 1.30), 'basalt', C_OBSIDIAN_ABYSS, 0.0, M=R('Y', c_ang) @ R('X', 24.0))
        # 3 Compact leaping warm amber-orange forge flame tongues ('glass' ONLY!)
        for fx_f, fz_f, fh_f, fr_f, sw in (
            ( 0.00,  0.00, 0.46, 0.105,  0.06),
            (-0.16, -0.05, 0.32, 0.075, -0.07),
            ( 0.15, -0.04, 0.34, 0.078,  0.07),
        ):
            tube(mb, [(fx_f, 0.18, fz_f),
                      (fx_f * 0.7 + sw, 0.18 + fh_f * 0.54, fz_f * 0.7),
                      (fx_f * 0.3 - sw * 0.5, 0.18 + fh_f, fz_f * 0.3)],
                 [fr_f, fr_f * 0.50, 0.014], 4, 'glass', C_FLAME_DEEP, caps=(False, True), mode='flat',
                 scols=[C_MAGMA_CRIMSON, C_FLAME_DEEP, C_FLAME_CORE])

    # Tapered Stone-and-Iron Forge Hood + Front Iron Support Pillars + Towering Chimney Stack (to y = 4.22 m!)
    for sx_h in (-0.54, 0.54):
        cbox(mb, (FX + sx_h, DECK_Y + 1.38, FZ - 0.44), (0.085, 0.92, 0.085), 'iron', C_IRON_FORGED, 0.0)
    hood_secs = [
        _rect_oct(FX, DECK_Y + 1.76, FZ + 0.02, 0.66, 0.58, 0.10),
        _rect_oct(FX, DECK_Y + 2.38, FZ + 0.10, 0.46, 0.42, 0.08),
        _rect_oct(FX, 3.44,          FZ + 0.16, 0.36, 0.34, 0.07),
        _rect_oct(FX, 4.00,          FZ + 0.16, 0.32, 0.30, 0.06),
    ]
    _loft_horizontal_masonry(
        mb, hood_secs, 'temple_stone',
        [C_FORGE_STONE_DK, C_FORGE_STONE_MD, C_FORGE_STONE_HI, C_FORGE_STONE_HI],
        rng, caps=(True, True), top_mat='basalt', top_col=C_SOOT_STONE,
    )
    cbox(mb, (FX, DECK_Y + 1.80, FZ + 0.02), (1.38, 0.12, 1.22), 'iron', C_IRON_DARK, 0.0)
    cbox(mb, (FX, 3.22, FZ + 0.16), (0.82, 0.10, 0.78), 'iron', C_IRON_FORGED, 0.0)
    cbox(mb, (FX, 3.68, FZ + 0.16), (0.74, 0.09, 0.70), 'iron', C_IRON_RUST_HI, 0.0)
    cbox(mb, (FX, 4.00, FZ + 0.16), (0.76, 0.10, 0.72), 'temple_stone', C_FORGE_STONE_HI, 0.0)
    for sx_c in (-0.24, 0.24):
        for sz_c in (-0.22, 0.22):
            cbox(mb, (FX + sx_c, 4.10, FZ + 0.16 + sz_c), (0.048, 0.18, 0.048), 'iron', C_IRON_FORGED, 0.0)
    with xf(mb, T(FX, 4.16, FZ + 0.16) @ R('Y', 45.0)):
        cyl(mb, 0.48, 0.0, 0.14, 4, 'iron', C_IRON_DARK, False, 0.0, 0.06)

    # 4. Leather-and-Iron Blacksmith Bellows mounted cleanly beside the port side of the Stone Forge!
    _build_forge_bellows(mb, (-1.94, DECK_Y, 0.18))

    # 5. Heavy Iron Anchor-Smithing Anvil on Oak Stump (front-center hero placement!)
    _build_blacksmith_anvil(mb, (0.06, DECK_Y, -0.60), yaw_deg=20.0)

    # 6. Hero Forged Pirate Iron Ship's Anchor resting unobstructed on the Starboard Front Apron!
    cbox(mb, (1.20, DECK_Y + 0.05, -0.76), (0.80, 0.10, 0.56), 'timber', C_OAK_DEEP, 0.0, M=R('Y', -10.0))
    _add_beam(mb, (0.94, DECK_Y + 0.06, -0.58), (1.16, DECK_Y + 0.90, -0.36), 0.095, 0.095, 'timber', C_OAK_RICH, 0.0)
    _add_beam(mb, (1.46, DECK_Y + 0.06, -0.64), (1.30, DECK_Y + 0.90, -0.38), 0.095, 0.095, 'timber', C_OAK_RICH, 0.0)
    _build_forged_ship_anchor(mb, T(1.18, DECK_Y + 0.16, -0.82) @ R('Y', -12.0) @ R('X', 22.0), scale=0.95)

    # 7. Quenched Slack-Tub Barrel w/ Shimmering Coastal-Teal Quench Water & Iron Blacksmith Tongs!
    QT_X, QT_Z = -0.66, -1.06
    with xf(mb, T(QT_X, DECK_Y, QT_Z)):
        cyl(mb, 0.30, 0.0, 0.58, 8, 'timber', C_OAK_RICH, False, 0.0, 0.34)
        _open_band(mb, 0.312, 0.09, 0.14, 8, 'iron', C_IRON_FORGED)
        _open_band(mb, 0.330, 0.28, 0.33, 8, 'iron', C_IRON_DARK)
        _open_band(mb, 0.348, 0.48, 0.53, 8, 'iron', C_IRON_RUST_HI)
        # Non-emissive glossy dark teal quench water surface clearly visible at the barrel rim!
        cyl(mb, 0.31, 0.54, 0.565, 8, 'paint', srgb('#257f8c'), False, 0.0)
        # Long forged-iron smithing tongs resting out of the quenching barrel
        _add_beam(mb, (-0.10, 0.40, -0.04), (0.34, 0.74, -0.22), 0.026, 0.026, 'iron', C_IRON_BRIGHT, 0.0)
        _add_beam(mb, (-0.06, 0.40,  0.04), (0.38, 0.70, -0.14), 0.026, 0.026, 'iron', C_IRON_FORGED, 0.0)

    # 8. Racked Forged Iron Cutlasses (4 gleaming pirate cutlasses!) & Heavy Draped Ship Chains!
    RK_X, RK_Z = 0.88, 0.86
    for rx_p in (-0.54, 0.54):
        cbox(mb, (RK_X + rx_p, DECK_Y + 0.70, RK_Z), (0.10, 1.40, 0.12), 'timber', C_OAK_DEEP, 0.0)
        cbox(mb, (RK_X + rx_p, DECK_Y + 0.05, RK_Z), (0.16, 0.10, 0.44), 'timber', C_OAK_RICH, 0.0)
    cbox(mb, (RK_X, DECK_Y + 0.36, RK_Z), (1.18, 0.10, 0.10), 'timber', C_OAK_SUN, 0.0)
    cbox(mb, (RK_X, DECK_Y + 1.14, RK_Z), (1.18, 0.10, 0.12), 'timber', C_OAK_SUN, 0.0)
    for si, sx_s in enumerate((-0.36, -0.12, 0.12, 0.36)):
        _build_forged_cutlass(
            mb, T(RK_X + sx_s, DECK_Y + 0.50, RK_Z - 0.08) @ R('Y', 90.0 + (si - 1.5) * 4.0) @ R('Z', -10.0),
        )

    # Heavy Forged-Iron Ship Anchor Chains draped from starboard post to anchor + coiled on deck & rear hooks!
    _add_chain_links(
        mb, (1.92, DECK_Y + 1.56, F_POST_Z + 0.04), (1.44, DECK_Y + 1.56, -0.26),
        n_links=4, link_r=0.10, wire_r=0.030, segs=5, psegs=3, sag=0.16,
        mat='iron', rust_stride=2, stretch_y=1.38, col_a=C_IRON_BRIGHT, col_b=C_IRON_RUST_HI,
    )
    _add_chain_links(
        mb, (0.28, DECK_Y + 1.24, R_POST_Z + 0.14), (1.84, DECK_Y + 1.24, R_POST_Z + 0.14),
        n_links=5, link_r=0.11, wire_r=0.032, segs=5, psegs=3, sag=0.22,
        mat='iron', rust_stride=2, stretch_y=1.40, col_a=C_IRON_FORGED, col_b=C_IRON_RUST_HI,
    )
    # Coiled heavy ship chain pile on front-starboard deck
    for ci_c in range(2):
        with xf(mb, T(1.94, DECK_Y + 0.05 + ci_c * 0.075, -1.16)):
            torus(mb, 0.24 - ci_c * 0.05, 0.040, 6, 4, 'iron', C_IRON_FORGED if ci_c == 0 else C_IRON_RUST_HI, False)

    # Rear (+Z) Blacksmith Craft: Iron-Bound Coal Bin, Shovel & Stacked Iron Ingots (rich Rear 3/4!)
    cbox(mb, (-1.18, DECK_Y + 0.26, 1.46), (0.98, 0.50, 0.44), 'timber', C_OAK_DEEP, 0.0)
    cbox(mb, (-1.18, DECK_Y + 0.44, 1.46), (0.86, 0.14, 0.34), 'basalt', C_OBSIDIAN_ABYSS, 0.0)
    for cx_c in (-1.42, -1.18, -0.96):
        cbox(mb, (cx_c, DECK_Y + 0.54, 1.46), (0.20, 0.12, 0.18), 'basalt', C_OBSIDIAN_DARK, 0.0, M=R('Y', cx_c * 45.0))
    for ing_i in range(3):
        cbox(mb, (0.64 + ing_i * 0.19, DECK_Y + 0.07, 1.48), (0.14, 0.10, 0.34), 'iron',
             C_IRON_BRIGHT if ing_i % 2 == 0 else C_IRON_FORGED, 0.0, M=R('Y', 8.0 * (ing_i - 1)))

    # 9. Crimson Blacksmith Guild Burgee Mast ('paint' + UV2!) rising cleanly from starboard-rear corner!
    MAST_X, MAST_Z = 1.98, R_POST_Z
    with xf(mb, T(MAST_X, 0.0, MAST_Z)):
        cyl(mb, 0.070, R_EAVE_Y - 0.10, 4.10, 6, 'timber', C_OAK_DEEP, False, 0.0, 0.042)
        lathe(mb, [(0.0, 4.08), (0.082, 4.14), (0.0, 4.22)], 6, 'brass', C_GOLD_BRIGHT, False)
    _build_wind_banner(
        mb, root_pos=(MAST_X - 0.04, 3.84, MAST_Z), length=1.42, h0=0.44,
        out_dir=(-0.88, -0.02, -0.48),
        col_main=C_CRIMSON_HI, col_alt=C_GOLD_CLOTH, col_trim=C_CRIMSON_MID,
        phase=0.31, swallowtail=True,
    )

    # 10. Warm Brass Forge-Lantern ('Lantern_AnchorForge') cantilevered seaward off the Front-Port Post!
    LANTERN_POS = Vector((-1.62, 2.28, -1.30))
    _add_beam(mb, (-2.04, 2.68, F_POST_Z), (-1.58, 2.68, -1.34), 0.068, 0.072, 'iron', C_IRON_FORGED, 0.0)
    _add_beam(mb, (-2.04, 2.24, F_POST_Z), (-1.78, 2.66, -1.14), 0.046, 0.050, 'iron', C_IRON_DARK, 0.0)
    _add_beam(mb, (-1.62, 2.68, -1.30), LANTERN_POS + Vector((0.0, 0.28, 0.0)), 0.024, 0.024, 'iron', C_IRON_FORGED, 0.0)
    _build_storm_lantern(mb, LANTERN_POS, scale=0.88, brass_cage=True, hanging=True)

    # 11. Coastal Harbour Ferns ('foliage' + UV2) tucked neatly beside the stone apron step & wharf flanks
    for fpos, fsc, flean, fph in (
        ((-1.24, 0.28, -1.74), 0.48, (-0.5, 0.0, -0.85), 0.18),
        (( 1.48, 0.28, -1.72), 0.46, ( 0.5, 0.0, -0.85), 0.46),
        ((-2.34, 0.30,  0.44), 0.44, (-1.0, 0.0,  0.00), 0.72),
        (( 2.34, 0.30,  0.22), 0.44, ( 1.0, 0.0,  0.00), 0.91),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=3, rng=rng, phase=fph, lean_dir=flean, segs=2)

    build(mb)

    add_empty('Lantern_AnchorForge', LANTERN_POS)
    col_piece('col_anchorforge_base', col_pts)
    export_landmark_glb(outdir, 'pirate_blacksmith_anchor_forge.glb')


# ==============================================================================
# 2. ANCIENT ABYSSAL NAUTILUS SHRINE (ancient_abyssal_nautilus_shrine.glb)
# ==============================================================================

def _build_coral_brazier(mb, center, yaw_deg=0.0, rng=None):
    """Carved mossy-limestone & branching rose-coral ritual brazier cradling luminous turquoise-cyan
    abyssal sea-fire crystals ('skull_glow' ONLY!)."""
    cx, cy, cz = center
    with xf(mb, T(cx, cy, cz) @ R('Y', yaw_deg)):
        prof = [
            (0.00, 0.00), (0.34, 0.00), (0.28, 0.16), (0.18, 0.48),
            (0.24, 0.68), (0.38, 0.88), (0.32, 0.94), (0.22, 0.80), (0.00, 0.76),
        ]
        lathe(mb, prof, 6, 'temple_stone', C_NAUTILUS_MID, False, False,
              lambda i, k: C_NAUTILUS_HI if i in (4, 5) else (C_NAUTILUS_DARK if i <= 2 else C_NAUTILUS_MID))
        with xf(mb, T(0.0, 0.66, 0.0)):
            torus(mb, 0.25, 0.028, 6, 3, 'brass', C_VERDIGRIS_HI, False)
        # 4 Sculpted branching coral prongs w/ secondary forked coral tines around the brazier rim!
        for k in range(4):
            ar = radians(k * 90.0 + 45.0)
            ca, sa = cos(ar), sin(ar)
            c_pts = [
                Vector((0.28 * ca, 0.78, 0.28 * sa)),
                Vector((0.40 * ca, 1.04, 0.40 * sa)),
                Vector((0.33 * ca, 1.28, 0.33 * sa)),
            ]
            c_col = C_CORAL_ROSE if k % 2 == 0 else C_CORAL_PALE
            tube(mb, c_pts, [0.068, 0.048, 0.016], 4, 'limestone_moss',
                 c_col, caps=(False, True), mode='flat')
            # Secondary coral side-branch sprouting outward from mid-prong
            side_t = Vector((-sa, 0.0, ca))
            fork_tip = c_pts[1] + Vector((0.12 * ca, 0.14, 0.12 * sa)) + side_t * 0.11
            tube(mb, [c_pts[1], fork_tip], [0.036, 0.012], 3, 'limestone_moss',
                 C_CORAL_PALE if k % 2 == 0 else C_CORAL_ROSE, caps=(False, True), mode='flat')
        # Luminous turquoise-cyan sea-fire crystal core ('skull_glow' ONLY!)
        lathe(mb, [(0.0, 0.76), (0.21, 0.86), (0.15, 1.06), (0.0, 1.28)],
              6, 'skull_glow', C_AQUA_CORE, False, False,
              lambda i, k: C_AQUA_WHITE if i == 2 else (C_AQUA_CORE if i == 1 else C_AQUA_MID))


def _build_nautilus_spiral_arch(mb, rng):
    """Monumental carved mossy-limestone & temple-stone logarithmic nautilus-shell spiral arch:
    rises from a wide fluted aperture pier on port (-X), soars grandly to y=5.16 m over the
    central sanctuary opening, sweeps down starboard (+X), and coils inward into an unmistakable
    grand 1.55-turn chambered logarithmic nautilus spiral volute with 16 raised carved radial
    septa ribs, sculpted dorsal shell crests & glowing aqua chamber seams ('skull_glow' ONLY!)."""
    # Part A: Smooth 11-station Grand Outer Ribbed Nautilus Shell Arch (Port Aperture -> High Crown -> Starboard Coil Entry)
    # Each entry: (x, y, rad_in_plane, z_half_depth)
    outer_ctrl = [
        (-1.62, 0.96, 0.46, 0.58),
        (-1.84, 1.72, 0.43, 0.54),
        (-1.86, 2.58, 0.40, 0.50),
        (-1.64, 3.44, 0.37, 0.46),
        (-1.14, 4.18, 0.35, 0.43),
        (-0.42, 4.66, 0.33, 0.40),
        ( 0.40, 4.72, 0.31, 0.38),
        ( 1.14, 4.38, 0.29, 0.36),
        ( 1.68, 3.74, 0.27, 0.34),
        ( 1.94, 2.94, 0.25, 0.32),
        ( 1.96, 2.08, 0.23, 0.30),
    ]

    # Part B: Grand True Logarithmic Nautilus Spiral Volute centered at S_c = (1.12, 2.08)
    # Starting seamlessly from (1.96, 2.08) -> phi = 0, r0 = 0.84 m, coiling clockwise 1.56 turns!
    sc_x, sc_y = 1.12, 2.08
    r0 = 0.84
    b_decay = 0.172
    n_spiral = 16
    phi_max = 1.56 * 2.0 * pi
    spiral_ctrl = []
    for i in range(1, n_spiral + 1):
        phi = phi_max * (i / float(n_spiral))
        rr = r0 * exp(-b_decay * phi)
        x = sc_x + rr * cos(-phi)
        y = sc_y + rr * sin(-phi)
        scale_r = rr / r0
        rad_p = max(0.062, 0.23 * (scale_r ** 0.86))
        z_hd  = max(0.13,  0.30 * (scale_r ** 0.72))
        spiral_ctrl.append((x, y, rad_p, z_hd))

    all_ctrl = outer_ctrl + spiral_ctrl
    pts = [Vector((c[0], c[1], 0.0)) for c in all_ctrl]
    n_pts = len(pts)

    secs = []
    scols = []
    out_dirs = []
    for i, (cx, cy, rp, zh) in enumerate(all_ctrl):
        p = pts[i]
        tang = (pts[min(i + 1, n_pts - 1)] - pts[max(i - 1, 0)]).normalized()
        n_out = Vector((-tang.y, tang.x, 0.0)).normalized()
        out_dirs.append(n_out)
        z_v = Vector((0.0, 0.0, 1.0))
        ring = [
            p + n_out * (rp * 1.22),
            p + n_out * (rp * 0.56) + z_v * (zh * 0.94),
            p - n_out * (rp * 0.64) + z_v * (zh * 0.86),
            p - n_out * (rp * 0.96),
            p - n_out * (rp * 0.64) - z_v * (zh * 0.86),
            p + n_out * (rp * 0.56) - z_v * (zh * 0.94),
        ]
        secs.append(ring)
        if i <= 2:
            scols.append(C_NAUTILUS_DARK)
        elif i <= 8:
            scols.append(C_NAUTILUS_HI if i % 2 == 1 else C_NAUTILUS_MID)
        else:
            scols.append(mix(C_NAUTILUS_MID, C_NAUTILUS_HI, 0.58 if i % 2 == 0 else 0.26))

    loft(mb, secs, 'temple_stone', C_NAUTILUS_MID, closed=True, caps=(True, True), mode='flat', scols=scols)

    # Flared carved scalloped port nautilus aperture lip collar grounding cleanly onto port dais pier!
    p0 = pts[0]
    t0 = (pts[1] - pts[0]).normalized()
    rot0 = Vector((0.0, 1.0, 0.0)).rotation_difference(t0).to_matrix().to_4x4()
    with xf(mb, T(p0) @ rot0):
        cbox(mb, (0.0, 0.04, 0.0), (1.12, 0.24, 1.28), 'temple_stone', C_NAUTILUS_HI, 0.0)
        cbox(mb, (0.0, 0.22, 0.0), (1.04, 0.08, 1.20), 'brass', C_VERDIGRIS_HI, 0.0)

    # 16 Sculpted Raised Carved Nautilus Chamber Septa Ribs + Dorsal Shell Scallop Crests!
    rib_indices = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16, 18, 20, 22]
    for ri in rib_indices:
        cx, cy, rp, zh = all_ctrl[ri]
        p = pts[ri]
        tang = (pts[min(ri + 1, n_pts - 1)] - pts[max(ri - 1, 0)]).normalized()
        n_out = out_dirs[ri]
        z_v = Vector((0.0, 0.0, 1.0))
        r_thick = 0.056 if ri <= 10 else 0.036
        pad_r = 0.082 if ri <= 10 else 0.050
        pad_z = 0.072 if ri <= 10 else 0.048
        # Raised scalloped dorsal shell crest keel peaking outward along the outer whorl!
        crest_extra = (0.14 if ri in (3, 4, 5, 6, 7, 8) else 0.06) if ri <= 10 else 0.03
        rib_secs = []
        for s_t in (-r_thick, r_thick):
            pc = p + tang * s_t
            rib_secs.append([
                pc + n_out * (rp * 1.24 + pad_r + crest_extra),
                pc + n_out * (rp * 0.58 + pad_r * 0.6) + z_v * (zh * 0.94 + pad_z),
                pc - n_out * (rp * 0.66 + pad_r * 0.5) + z_v * (zh * 0.86 + pad_z),
                pc - n_out * (rp * 0.98 + pad_r * 0.4),
                pc - n_out * (rp * 0.66 + pad_r * 0.5) - z_v * (zh * 0.86 + pad_z),
                pc + n_out * (rp * 0.58 + pad_r * 0.6) - z_v * (zh * 0.94 + pad_z),
            ])
        is_bronze = (ri in (3, 6, 9, 14, 18))
        r_mat = 'brass' if is_bronze else 'limestone_moss'
        r_col = C_VERDIGRIS_HI if is_bronze else C_NAUTILUS_HI
        loft(mb, rib_secs, r_mat, r_col, closed=True, caps=(True, True), mode='flat')

    # Glowing Turquoise-Cyan Carved Spiral Wave Rune Ribbons continuing cleanly into the Nautilus Coil ('skull_glow'!)
    for z_sgn in (-1.0, 1.0):
        vein_pts = [Vector((all_ctrl[i][0], all_ctrl[i][1], z_sgn * (all_ctrl[i][3] * 0.92))) for i in range(1, 18)]
        vein_w = [max(0.022, 0.060 - 0.0022 * k) for k in range(len(vein_pts))]
        _sculpt_glow_ribbon(
            mb, vein_pts, vein_w, (0.0, 0.0, z_sgn), hot_core=True, ridge_h=0.024, mat='skull_glow',
            c_core=C_AQUA_CORE, c_mid_col=C_AQUA_MID, c_edge_col=C_AQUA_DEEP, c_tip_col=C_AQUA_DEEP,
        )

    # Solid Carved Mossy Stone Spiral-Eye Umbilicus Disc + Gilded Ring + Glowing Aqua Nautilus Eye Gem (both faces!)
    with xf(mb, T(sc_x, sc_y, 0.0) @ M_Y2Z):
        cyl(mb, 0.46, -0.17, 0.17, 8, 'temple_stone', C_NAUTILUS_DARK, False, 0.0)
        cyl(mb, 0.24, -0.21, 0.21, 8, 'brass', C_VERDIGRIS_HI, False, 0.0)
        cyl(mb, 0.16, -0.24, 0.24, 6, 'brass', C_GOLD_BRIGHT, False, 0.0)
        cyl(mb, 0.11, -0.27, 0.27, 6, 'skull_glow', C_AQUA_CORE, False, 0.0)

    # Stout Starboard Temple-Stone Abutment Plinth grounding the Grand Nautilus Spiral Coil solidly onto the Dais!
    abut_secs = [
        _rect_oct(1.24, 0.72, 0.0, 0.72, 0.56, 0.16),
        _rect_oct(1.20, 1.34, 0.0, 0.62, 0.44, 0.14),
    ]
    _loft_horizontal_masonry(
        mb, abut_secs, 'limestone_moss', [C_NAUTILUS_DARK, C_NAUTILUS_MID],
        rng, caps=(False, True), top_mat='temple_stone', top_col=C_NAUTILUS_HI,
    )
    # Port Flanking Carved Ammonite Scroll Buttress grounding the wide shell mouth cleanly!
    port_secs = [
        _rect_oct(-1.62, 0.72, 0.0, 0.68, 0.64, 0.16),
        _rect_oct(-1.62, 1.06, 0.0, 0.60, 0.58, 0.14),
    ]
    _loft_horizontal_masonry(
        mb, port_secs, 'limestone_moss', [C_NAUTILUS_DARK, C_NAUTILUS_HI],
        rng, caps=(False, True), top_mat='temple_stone', top_col=C_NAUTILUS_HI,
    )


def gen_ancient_abyssal_nautilus_shrine(outdir):
    """Monumental carved mossy limestone & temple-stone giant spiral nautilus-shell sea shrine
    (~4.8 m W x 4.4 m D x 5.2 m H, -3.20 m deep mossy stone skirt) w/ grand ribbed stone
    logarithmic nautilus spiral arch cradling a hovering luminous turquoise-cyan sea-pearl orb &
    glowing aquatic basin runes ('skull_glow' ONLY!), twin carved coral braziers, cascading jungle
    vines & ferns (UV2), convex collider 'col_nautilusshrine_base', and empty 'Lantern_NautilusShrine'."""
    clear_scene()
    mb = MB('ancient_abyssal_nautilus_shrine', seed=2302)
    rng = random.Random(SEED + 2302)
    col_pts = []

    STEP1_Y = 0.38
    STEP2_Y = 0.72
    DAIS_Y  = 1.04
    ORB_POS = Vector((-0.14, 2.94, 0.0))

    # 1. Deep Terraced Mossy Limestone & Temple-Stone Sea-Shrine Foundation Skirt plunging to y = -3.20 m (~4.8 m W x 4.4 m D)
    plinth_secs = [
        _reg_poly(0.0, -3.20, 0.0, 2.34, sides=8, rot_deg=22.5, sx=1.02, sz=0.94),
        _reg_poly(0.0, -1.35, 0.0, 2.28, sides=8, rot_deg=22.5, sx=1.02, sz=0.94),
        _reg_poly(0.0,  0.00, 0.0, 2.22, sides=8, rot_deg=22.5, sx=1.02, sz=0.94),
        _reg_poly(0.0, STEP1_Y, 0.0, 2.16, sides=8, rot_deg=22.5, sx=1.02, sz=0.94),
    ]
    _loft_horizontal_masonry(
        mb, plinth_secs, 'limestone_moss',
        [C_NAUTILUS_DEEP, C_NAUTILUS_DARK, C_NAUTILUS_MID, C_NAUTILUS_HI],
        rng, caps=(True, True), top_mat='limestone_moss', top_col=C_NAUTILUS_MID,
    )

    tier2_secs = [
        _reg_poly(0.0, STEP1_Y - 0.02, 0.0, 1.94, sides=8, rot_deg=22.5, sx=1.02, sz=0.92),
        _reg_poly(0.0, STEP2_Y,        0.0, 1.86, sides=8, rot_deg=22.5, sx=1.02, sz=0.92),
    ]
    _loft_horizontal_masonry(
        mb, tier2_secs, 'temple_stone',
        [C_NAUTILUS_DARK, C_NAUTILUS_HI], rng, caps=(False, True),
        top_mat='temple_stone', top_col=C_NAUTILUS_MID,
    )

    dais_secs = [
        _reg_poly(0.0, STEP2_Y - 0.02, 0.0, 1.48, sides=8, rot_deg=22.5, sx=1.02, sz=0.90),
        _reg_poly(0.0, DAIS_Y,         0.0, 1.40, sides=8, rot_deg=22.5, sx=1.02, sz=0.90),
    ]
    _loft_horizontal_masonry(
        mb, dais_secs, 'temple_stone',
        [C_NAUTILUS_DARK, C_NAUTILUS_HI], rng, caps=(False, True),
        top_mat='temple_stone', top_col=C_NAUTILUS_HI,
    )

    for yc, rx, rz in ((-3.20, 2.38, 2.20), (0.0, 2.26, 2.08), (DAIS_Y, 2.12, 1.88), (3.90, 2.02, 0.92), (5.20, 1.18, 0.62)):
        col_pts.extend(_reg_poly(0.0, yc, 0.0, 1.0, sides=8, rot_deg=22.5, sx=rx, sz=rz))

    # Seaward (-Z) & Rear (+Z) Carved Stone Ritual Steps w/ Verdigris Bronze Riser Trim & Glowing Aqua Rune Chevrons!
    for z_sgn in (-1.0, 1.0):
        cbox(mb, (0.0, 0.19, z_sgn * 2.02), (1.22, 0.36, 0.38), 'temple_stone', C_NAUTILUS_MID, 0.0)
        cbox(mb, (0.0, 0.52, z_sgn * 1.72), (1.08, 0.34, 0.36), 'temple_stone', C_NAUTILUS_HI, 0.0)
        cbox(mb, (0.0, 0.84, z_sgn * 1.38), (0.96, 0.32, 0.34), 'temple_stone', C_NAUTILUS_HI, 0.0)
        for sx in (-1.0, 1.0):
            cbox(mb, (sx * 0.66, 0.52, z_sgn * 1.70), (0.20, 0.58, 0.84), 'limestone_moss', C_NAUTILUS_DARK, 0.0)
            cbox(mb, (sx * 0.66, 0.84, z_sgn * 1.40), (0.22, 0.08, 0.24), 'brass', C_VERDIGRIS_HI, 0.0)
            # Carved spiral conch stud medallions inlaid on the outer stair curbs
            with xf(mb, T(sx * 0.77, 0.56, z_sgn * 1.72) @ M_Y2X):
                cyl(mb, 0.14, -0.03, 0.03, 6, 'brass', C_GOLD_BRIGHT, False, 0.0)
        cbox(mb, (0.0, 0.38, z_sgn * 1.92), (0.86, 0.032, 0.09), 'brass', C_GOLD_BRIGHT, 0.0)
        cbox(mb, (0.0, 0.72, z_sgn * 1.62), (0.76, 0.032, 0.09), 'brass', C_VERDIGRIS_HI, 0.0)
        cbox(mb, (0.0, 1.05, z_sgn * 1.18), (0.18, 0.04, 0.18), 'skull_glow', C_AQUA_CORE, 0.0, M=R('Y', 45.0))

    # 2. Sacred Carved Aquatic Tide Basin, Carved Shell-Wave Rim Petals & Glowing Basin Runes ('skull_glow' ONLY!)
    with xf(mb, T(-0.14, DAIS_Y, 0.0)):
        basin_prof = [
            (0.00, 0.00), (0.96, 0.00), (1.02, 0.14), (0.94, 0.30),
            (0.82, 0.30), (0.76, 0.16), (0.00, 0.14),
        ]
        lathe(mb, basin_prof, 8, 'temple_stone', C_NAUTILUS_HI, False, False,
              lambda i, k: C_NAUTILUS_HI if i in (2, 3) else C_NAUTILUS_DARK)
        with xf(mb, T(0.0, 0.28, 0.0)):
            torus(mb, 0.92, 0.038, 12, 4, 'brass', C_VERDIGRIS_HI, False)
        # Luminous Turquoise-Cyan Sacred Tide Pool & Concentric Glowing Aquatic Basin Runes!
        lathe(mb, [(0.0, 0.20), (0.34, 0.21), (0.62, 0.19), (0.80, 0.18)],
              10, 'skull_glow', C_AQUA_MID, False, False,
              lambda i, k: C_AQUA_WHITE if i == 0 else (C_AQUA_CORE if i == 1 else C_AQUA_MID))
        with xf(mb, T(0.0, 0.22, 0.0)):
            torus(mb, 0.54, 0.026, 10, 3, 'brass', C_GOLD_BRIGHT, False)
        # 8 Radial glowing aquatic rune bands + carved scalloped stone wave-lugs around the basin rim!
        for k in range(8):
            ar = radians(k * 45.0 + 22.5)
            ca, sa = cos(ar), sin(ar)
            _sculpt_glow_ribbon(
                mb, [Vector((0.74 * ca, 0.26, 0.74 * sa)), Vector((1.00 * ca, 0.31, 1.00 * sa)),
                     Vector((1.05 * ca, 0.07, 1.05 * sa))],
                [0.042, 0.050, 0.032], (ca, 0.4, sa), hot_core=True, ridge_h=0.022, mat='skull_glow',
                c_core=C_AQUA_CORE, c_mid_col=C_AQUA_MID, c_edge_col=C_AQUA_DEEP, c_tip_col=C_AQUA_DEEP,
            )

    # 3. Monumental Carved Ribbed Stone Logarithmic Nautilus Spiral Arch (rises to y = 5.20 m!)
    _build_nautilus_spiral_arch(mb, rng)

    # 4. Hovering Luminous Turquoise-Cyan Sea-Pearl Orb & Verdigris Wave Orbital Rings ('skull_glow' ONLY!)
    with xf(mb, T(ORB_POS)):
        pearl_prof = [
            (0.00, -0.43), (0.29, -0.33), (0.43, -0.10), (0.43, 0.10), (0.29, 0.33), (0.00, 0.43),
        ]
        lathe(mb, pearl_prof, 10, 'skull_glow', C_AQUA_CORE, False, False,
              lambda i, k: C_AQUA_WHITE if i in (2, 3) else (C_AQUA_CORE if i in (1, 4) else C_AQUA_MID))
        with xf(mb, R('Z', 24.0) @ R('X', 32.0)):
            torus(mb, 0.68, 0.038, 12, 4, 'brass', C_GOLD_BRIGHT, False)
        with xf(mb, R('Z', -34.0) @ R('Y', 48.0) @ M_Y2Z):
            torus(mb, 0.80, 0.034, 12, 3, 'brass', C_VERDIGRIS_HI, False)
        # 4 Sculpted gilded orbital wave-crest fins + 4 hovering luminous aqua sea-droplet shards!
        for k in range(4):
            ar = radians(k * 90.0 + 45.0)
            sy_off = 0.18 * (1.0 if k % 2 == 0 else -1.0)
            with xf(mb, T(0.64 * cos(ar), sy_off, 0.64 * sin(ar)) @ R('Z', 18.0 * cos(ar))):
                lathe(mb, [(0.0, -0.15), (0.075, 0.0), (0.0, 0.17)], 4, 'skull_glow', C_AQUA_CORE, False)

    # 5. Twin Carved Coral Braziers flanking the Seaward Approach + Rear Carved Coral Sanctuary Braziers!
    _build_coral_brazier(mb, (-1.46, STEP1_Y, -1.24), yaw_deg=28.0, rng=rng)
    _build_coral_brazier(mb, ( 1.46, STEP1_Y, -1.24), yaw_deg=-28.0, rng=rng)
    _build_coral_brazier(mb, (-1.40, STEP1_Y,  1.20), yaw_deg=152.0, rng=rng)
    _build_coral_brazier(mb, ( 1.40, STEP1_Y,  1.20), yaw_deg=-152.0, rng=rng)

    # 6. Cascading Jungle Vines (100% anchored directly onto stone arch shoulders — ZERO floating!),
    #    Natural Haunch Mossy Cushions & Lush Tropical Ferns ('foliage' + UV2!)
    vine_specs = [
        ((-1.64, 3.44, -0.44), 1.92, 0.15, (-0.50, 0.0, -0.86), 0.14),
        (( 1.66, 3.74, -0.34), 1.72, 0.14, ( 0.45, 0.0, -0.89), 0.38),
        ((-1.64, 3.42,  0.44), 1.88, 0.15, (-0.50, 0.0,  0.86), 0.62),
        (( 1.66, 3.72,  0.34), 1.66, 0.14, ( 0.45, 0.0,  0.89), 0.84),
        ((-1.12, 4.18, -0.40), 1.56, 0.14, (-0.30, 0.0, -0.95), 0.25),
        (( 1.12, 4.38,  0.35), 1.48, 0.13, ( 0.30, 0.0,  0.95), 0.75),
        ((-1.82, 2.38, -0.46), 1.24, 0.13, (-0.75, 0.0, -0.66), 0.49),
    ]
    for v_pos, v_len, v_wid, v_dir, v_ph in vine_specs:
        _add_leafy_vine_drape(mb, v_pos, v_len, v_wid, v_dir, rng, phase=v_ph)

    for mpos, mrad in (
        ((-1.64, 1.06, -0.46), (0.34, 0.14, 0.26)),
        (( 1.38, 1.34, -0.38), (0.32, 0.13, 0.24)),
        ((-1.62, 1.06,  0.46), (0.32, 0.13, 0.24)),
        (( 1.38, 1.34,  0.38), (0.30, 0.12, 0.24)),
        ((-1.08, 4.52,  0.00), (0.36, 0.12, 0.26)),
        (( 1.16, 4.66,  0.00), (0.32, 0.11, 0.24)),
    ):
        _build_mossy_tuft(mb, mpos, mrad, rng)

    for fpos, fsc, flean, fph in (
        ((-1.82, STEP1_Y + 0.02, -0.32), 0.56, (-0.95, 0.0, -0.30), 0.12),
        (( 1.82, STEP1_Y + 0.02, -0.28), 0.54, ( 0.95, 0.0, -0.30), 0.37),
        ((-1.78, STEP1_Y + 0.02,  0.48), 0.54, (-0.88, 0.0,  0.48), 0.64),
        (( 1.78, STEP1_Y + 0.02,  0.48), 0.54, ( 0.88, 0.0,  0.48), 0.88),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=4, rng=rng, phase=fph, lean_dir=flean, segs=2)

    build(mb)

    add_empty('Lantern_NautilusShrine', ORB_POS)
    col_piece('col_nautilusshrine_base', col_pts)
    export_landmark_glb(outdir, 'ancient_abyssal_nautilus_shrine.glb')


# ==============================================================================
# 3. COASTAL SMUGGLER SIGNAL TRIPOD (coastal_smuggler_signal_tripod.glb)
# ==============================================================================

def _build_suspended_beacon_basket(mb, center, apex_pos):
    """Wrought-iron suspended night-signal fire-basket hanging on heavy chains from the lashed
    tripod apex, blazing with charred driftwood logs, glowing warm amber embers & flame tongues
    ('glass' ONLY — ZERO skull_glow!)."""
    cx, cy, cz = center
    swivel_y = cy + 0.56
    _add_chain_links(
        mb, (apex_pos[0], apex_pos[1] - 0.04, apex_pos[2]), (cx, swivel_y + 0.04, cz),
        n_links=3, link_r=0.078, wire_r=0.024, segs=5, psegs=3, sag=0.0,
        mat='iron', rust_stride=2, stretch_y=1.35, col_a=C_IRON_BRIGHT, col_b=C_IRON_RUST_HI,
    )
    with xf(mb, T(cx, swivel_y, cz) @ M_Y2Z):
        torus(mb, 0.088, 0.024, 6, 3, 'iron', C_IRON_BRIGHT, False)

    rim_y = cy + 0.18
    for k in range(3):
        ar = radians(k * 120.0 + 30.0)
        _add_beam(mb, (cx, swivel_y - 0.04, cz),
                  (cx + 0.45 * cos(ar), rim_y, cz + 0.45 * sin(ar)),
                  0.030, 0.030, 'iron', C_IRON_FORGED, 0.0)

    with xf(mb, T(cx, cy, cz)):
        # Riveted iron ash-pan dish below the basket + lower iron damping ring
        cyl(mb, 0.30, -0.34, -0.26, 8, 'iron', C_IRON_DARK, False, 0.0, 0.34)
        with xf(mb, T(0.0, -0.40, 0.0) @ M_Y2Z):
            torus(mb, 0.068, 0.020, 6, 3, 'iron', C_IRON_RUST_HI, False)
        for hy, hr, hcol in ((-0.26, 0.32, C_IRON_DARK), (-0.04, 0.39, C_IRON_FORGED), (0.18, 0.46, C_IRON_RUST_HI)):
            with xf(mb, T(0.0, hy, 0.0)):
                torus(mb, hr, 0.028, 8, 3, 'iron', hcol, False)
        for k in range(8):
            ar = radians(k * 45.0 + 22.5)
            ca, sa = cos(ar), sin(ar)
            _add_beam(mb, (0.31 * ca, -0.28, 0.31 * sa), (0.46 * ca, 0.22, 0.46 * sa),
                      0.032, 0.032, 'iron', C_IRON_FORGED if k % 2 == 0 else C_IRON_RUST_MID, 0.0)
        # Chunky dark charred driftwood logs crisscrossed inside the basket for crisp warm-vs-dark contrast!
        for lag, ly_l in ((14.0, -0.10), (74.0, -0.02), (132.0, 0.05), (168.0, -0.08)):
            with xf(mb, T(0.0, ly_l, 0.0) @ R('Y', lag) @ R('Z', 24.0) @ M_Y2X):
                cyl(mb, 0.056, -0.38, 0.38, 5, 'timber', C_OAK_CHAR, False, 0.0)
        # Deep fiery warm-amber signal ember mound & crisp leaping flame tongues ('glass' ONLY!)
        lathe(mb, [(0.0, -0.24), (0.28, -0.18), (0.30, -0.02), (0.19, 0.11), (0.0, 0.17)],
              6, 'glass', C_MAGMA_CRIMSON, False, False,
              lambda i, k: C_FLAME_CORE if i >= 3 else (C_FLAME_MID if i == 2 else C_MAGMA_CRIMSON))
        for fx_f, fz_f, fh_f, fr_f, sw in (
            ( 0.00,  0.00, 0.48, 0.11,  0.06),
            (-0.14, -0.09, 0.34, 0.075, -0.07),
            ( 0.14,  0.08, 0.36, 0.078,  0.07),
        ):
            tube(mb, [(fx_f, 0.06, fz_f),
                      (fx_f * 0.65 + sw, 0.06 + fh_f * 0.54, fz_f * 0.65),
                      (fx_f * 0.25 - sw * 0.5, 0.06 + fh_f, fz_f * 0.25)],
                 [fr_f, fr_f * 0.48, 0.014], 4, 'glass', C_FLAME_DEEP, caps=(False, True), mode='flat',
                 scols=[C_MAGMA_CRIMSON, C_FLAME_DEEP, C_FLAME_CORE])


def _build_signal_flag_chest(mb, center, yaw_deg=24.0):
    """Iron-banded oak smuggler's signal-flag chest w/ propped-open lid revealing rolled crimson,
    gold & teal canvas signal code flags tucked cleanly inside!"""
    cx, cy, cz = center
    with xf(mb, T(cx, cy, cz) @ R('Y', yaw_deg)):
        cbox(mb, (0.0, 0.20, 0.0), (0.76, 0.38, 0.46), 'timber', C_OAK_RICH, 0.0)
        cbox(mb, (0.0, 0.37, 0.0), (0.68, 0.06, 0.38), 'timber', C_OAK_CHAR, 0.0)
        for sx in (-0.34, 0.0, 0.34):
            cbox(mb, (sx, 0.20, 0.0), (0.055, 0.40, 0.49), 'iron', C_IRON_FORGED, 0.0)
        cbox(mb, (0.0, 0.32, -0.25), (0.12, 0.14, 0.04), 'brass', C_GOLD_BRIGHT, 0.0)
        for fi, (fz_f, fcol_f, ftrim_f) in enumerate((
            (-0.10, C_CRIMSON_HI, C_GOLD_CLOTH),
            ( 0.01, C_GOLD_CLOTH, C_CRIMSON_HI),
            ( 0.11, C_TEAL_HI,    C_CREAM_BRIGHT),
        )):
            with xf(mb, T(-0.04 + fi * 0.03, 0.41, fz_f) @ R('Y', (fi - 1) * 6.0) @ M_Y2X):
                cyl(mb, 0.058, -0.28, 0.28, 6, 'paint', fcol_f, False, 0.0)
                _open_band(mb, 0.063, -0.05, 0.05, 6, 'paint', ftrim_f)
        with xf(mb, T(0.0, 0.39, 0.23) @ R('X', 66.0)):
            cbox(mb, (0.0, 0.06, -0.23), (0.78, 0.11, 0.48), 'timber', C_OAK_SUN, 0.0)
            for sx in (-0.34, 0.34):
                cbox(mb, (sx, 0.065, -0.23), (0.055, 0.13, 0.50), 'iron', C_IRON_FORGED, 0.0)


def _build_rum_crate(mb, center, size=(0.56, 0.46, 0.48), yaw_deg=0.0, stripe_col=C_CRIMSON_HI):
    """Slatted weathered smuggler's rum crate with diagonal cross-braces & crimson stencil band."""
    cx, cy, cz = center
    sx, sy, sz = size
    with xf(mb, T(cx, cy + sy * 0.5, cz) @ R('Y', yaw_deg)):
        cbox(mb, (0.0, 0.0, 0.0), (sx * 0.90, sy * 0.90, sz * 0.90), 'timber', C_OAK_DEEP, 0.0)
        for y_e in (-sy * 0.43, sy * 0.43):
            cbox(mb, (0.0, y_e, 0.0), (sx, 0.07, sz), 'timber', C_OAK_SUN, 0.0)
        for x_e in (-sx * 0.44, sx * 0.44):
            for z_e in (-sz * 0.44, sz * 0.44):
                cbox(mb, (x_e, 0.0, z_e), (0.075, sy, 0.075), 'timber', C_DRIFT_SUN, 0.0)
        for z_f in (-sz * 0.46, sz * 0.46):
            _add_beam(mb, (-sx * 0.38, -sy * 0.36, z_f), (sx * 0.38, sy * 0.36, z_f), 0.06, 0.032, 'timber', C_OAK_RICH, 0.0)
        cbox(mb, (0.0, 0.0, 0.0), (sx * 0.94, 0.10, sz * 0.94), 'paint', stripe_col, 0.0)


def gen_coastal_smuggler_signal_tripod(outdir):
    """Weathered headland timber smuggler's night-signal tripod & spyglass watch-perch (~4.6 m W x
    4.4 m D x 4.6 m H, -2.80 m deep coastal headland skirt) w/ 3 lashed drift-spar tripod legs
    hoisting a suspended iron fire-basket signal beacon ('glass' warm amber embers — ZERO
    skull_glow!), rope pulley halyard, wooden signal-flag chest, coiled hawser, rum crates,
    fluttering crimson-gold signal code pennants (UV2), convex collider 'col_signaltripod_base',
    and empty 'Lantern_SignalTripod'."""
    clear_scene()
    mb = MB('coastal_smuggler_signal_tripod', seed=2303)
    rng = random.Random(SEED + 2303)
    col_pts = []

    DECK_Y = 0.52
    APEX_POS = Vector((0.0, 3.84, 0.0))
    BEACON_POS = Vector((0.0, 2.72, 0.0))

    # 1. Deep Coastal Headland Limestone Crag Skirt plunging cleanly to y = -2.80 m (~4.6 m W x 4.4 m D)
    head_secs = [
        _reg_poly(0.0, -2.80, 0.0, 2.30, sides=8, rot_deg=22.5, sx=1.01, sz=0.96),
        _reg_poly(0.0, -1.15, 0.0, 2.22, sides=8, rot_deg=22.5, sx=1.01, sz=0.96),
        _reg_poly(0.0,  0.00, 0.0, 2.14, sides=8, rot_deg=22.5, sx=1.01, sz=0.96),
        _reg_poly(0.0,  0.38, 0.0, 2.04, sides=8, rot_deg=22.5, sx=1.01, sz=0.96),
    ]
    _loft_horizontal_masonry(
        mb, head_secs, 'limestone',
        [C_HEADLAND_DEEP, C_HEADLAND_DARK, C_HEADLAND_MID, C_HEADLAND_HI],
        rng, caps=(True, True), top_mat='limestone_moss', top_col=C_HEADLAND_MID,
    )

    for yc, rx, rz in ((-2.80, 2.32, 2.20), (0.0, 2.16, 2.06), (DECK_Y, 2.06, 1.94), (3.88, 0.85, 0.85), (4.58, 0.42, 0.42)):
        col_pts.extend(_reg_poly(0.0, yc, 0.0, 1.0, sides=8, rot_deg=22.5, sx=rx, sz=rz))

    # Rugged Coastal Headland Outcrop Boulders tucked around the rocky rim
    for bpos, brad, brot in (
        ((-1.92, 0.24, -0.96), (0.42, 0.28, 0.34), (6, 22, -8)),
        (( 1.94, 0.22, -0.88), (0.38, 0.25, 0.34), (-5, -30, 6)),
        (( 1.56, 0.26,  1.42), (0.44, 0.30, 0.38), (4, 42, -5)),
        ((-1.62, 0.24,  1.36), (0.40, 0.28, 0.36), (-4, 58, 7)),
        (( 0.88, 0.22,  1.86), (0.36, 0.24, 0.30), (3, -18, -4)),
    ):
        sculpt_rock_mass(
            mb, bpos, brad, 'limestone', C_HEADLAND_HI, C_HEADLAND_MID, C_HEADLAND_DARK,
            rng, subdiv=1, warp=0.22, strata=0.14, rot_deg=brot, crag_ribs=4, rib_amp=0.10,
        )

    # Bolted Weathered Driftwood Octagonal Lookout Platform Deck (y = 0.52 m) + Seaward Stone Step & Mooring Posts!
    with xf(mb, T(0.0, 0.38, 0.0) @ R('Y', 22.5)):
        cyl(mb, 1.88, 0.0, 0.14, 8, 'timber', C_DRIFT_DARK, False, 0.0, 1.86)
    for pi_d in range(6):
        pz_d = -1.25 + pi_d * (2.50 / 5.0)
        pw_d = 3.36 if abs(pz_d) < 0.85 else 2.52
        cbox(mb, (0.0, DECK_Y - 0.01, pz_d), (pw_d, 0.058, 0.44), 'timber',
             C_DRIFT_SUN if pi_d % 2 == 0 else C_DRIFT_MID, 0.0)
    cbox(mb, (0.0, 0.22, -1.94), (1.36, 0.34, 0.38), 'limestone', C_HEADLAND_HI, 0.0)
    # 6 Driven Weathered Timber Perimeter Mooring Bollards w/ Braided Hemp Rope Loops!
    for b_ang in (32.0, 90.0, 148.0, 212.0, 270.0, 328.0):
        ar = radians(b_ang)
        bx_p, bz_p = 1.84 * cos(ar), 1.80 * sin(ar)
        if bz_p < -1.40:
            continue
        with xf(mb, T(bx_p, 0.0, bz_p)):
            cyl(mb, 0.105, -0.25, DECK_Y + 0.44, 6, 'timber', C_DRIFT_DARK, False, 0.0, 0.092)
            _open_band(mb, 0.114, DECK_Y + 0.22, DECK_Y + 0.32, 6, 'rope', C_HEMP_HI)

    # 2. Three Lashed Weathered Drift-Spar Tripod Legs rising cleanly to y = 4.58 m!
    LEG_SPECS = [
        (Vector((-1.36, DECK_Y - 0.08, -0.86)), Vector((-0.07, 3.84, -0.05)), Vector(( 0.20, 4.38,  0.14)), C_DRIFT_SUN),
        (Vector(( 1.40, DECK_Y - 0.08, -0.82)), Vector(( 0.07, 3.84, -0.05)), Vector((-0.20, 4.36,  0.12)), C_DRIFT_MID),
        (Vector(( 0.02, DECK_Y - 0.08,  1.42)), Vector(( 0.00, 3.84,  0.07)), Vector(( 0.00, 4.54, -0.20)), C_OAK_RICH),
    ]
    for p_bot, p_jct, p_tip, l_col in LEG_SPECS:
        p_mid = p_bot.lerp(p_jct, 0.50)
        tube(mb, [p_bot, p_mid, p_jct, p_tip], [0.132, 0.114, 0.095, 0.068], 6,
             'timber', l_col, caps=(False, True), mode='flat')
        cbox(mb, (p_bot.x, DECK_Y + 0.10, p_bot.z), (0.30, 0.22, 0.30), 'iron', C_IRON_FORGED, 0.0)
        p_band = p_bot.lerp(p_jct, 0.56)
        v_leg = (p_jct - p_bot).normalized()
        rot_l = Vector((0.0, 1.0, 0.0)).rotation_difference(v_leg).to_matrix().to_4x4()
        with xf(mb, T(p_band) @ rot_l):
            _open_band(mb, 0.122, -0.055, 0.055, 6, 'iron', C_IRON_RUST_HI)

    # Heavy Crisscross Braided Hemp Rope Apex Lashing Collar binding all 3 drift-spars tightly!
    for l_off, l_rx, l_rz, l_col in (
        (-0.10, 0.0,  0.0, C_HEMP_HI),
        ( 0.00, 16.0, -10.0, C_HEMP_MID),
        ( 0.10, -14.0, 12.0, C_HEMP_HI),
    ):
        with xf(mb, T(APEX_POS.x, APEX_POS.y + l_off, APEX_POS.z) @ R('X', l_rx) @ R('Z', l_rz)):
            torus(mb, 0.185, 0.048, 8, 4, 'rope', l_col, True)
    with xf(mb, T(0.0, 4.54, -0.20)):
        lathe(mb, [(0.0, -0.02), (0.080, 0.04), (0.0, 0.12)], 6, 'brass', C_GOLD_BRIGHT, False)

    # Horizontal drift-spar structural cross-braces + upper tension collar + brass smuggler warning bell!
    leg1_15 = LEG_SPECS[0][0].lerp(LEG_SPECS[0][1], 0.36)
    leg2_15 = LEG_SPECS[1][0].lerp(LEG_SPECS[1][1], 0.36)
    leg3_15 = LEG_SPECS[2][0].lerp(LEG_SPECS[2][1], 0.36)
    _add_beam(mb, leg1_15, leg3_15, 0.095, 0.105, 'timber', C_OAK_DEEP, 0.0)
    _add_beam(mb, leg2_15, leg3_15, 0.095, 0.105, 'timber', C_OAK_DEEP, 0.0)
    leg1_hi = LEG_SPECS[0][0].lerp(LEG_SPECS[0][1], 0.78)
    leg2_hi = LEG_SPECS[1][0].lerp(LEG_SPECS[1][1], 0.78)
    leg3_hi = LEG_SPECS[2][0].lerp(LEG_SPECS[2][1], 0.78)
    _add_beam(mb, leg1_hi, leg2_hi, 0.068, 0.068, 'timber', C_DRIFT_MID, 0.0)
    _add_beam(mb, leg2_hi, leg3_hi, 0.068, 0.068, 'timber', C_DRIFT_MID, 0.0)
    _add_beam(mb, leg3_hi, leg1_hi, 0.068, 0.068, 'timber', C_DRIFT_MID, 0.0)

    # Hanging Brass Smuggler's Warning Ship's Bell on Front-Port Tripod Leg!
    bell_root = LEG_SPECS[0][0].lerp(LEG_SPECS[0][1], 0.44)
    bell_pos = bell_root + Vector((-0.26, 0.02, -0.14))
    _add_beam(mb, bell_root, bell_pos + Vector((0.0, 0.10, 0.0)), 0.056, 0.056, 'iron', C_IRON_FORGED, 0.0)
    with xf(mb, T(bell_pos)):
        lathe(mb, [(0.0, 0.08), (0.065, 0.06), (0.095, -0.06), (0.145, -0.15), (0.125, -0.16), (0.0, -0.12)],
              8, 'brass', C_GOLD_BRIGHT, False, False)
        _add_beam(mb, (0.0, -0.12, 0.0), (0.0, -0.34, 0.0), 0.018, 0.018, 'rope', C_HEMP_HI, 0.0)

    # 3. Spyglass Watch-Perch Platform lashed on the Port-Rear Tripod Flank (y = 1.66 m) + Brass Spyglass, Lantern & Ladder!
    PERCH_Y = 1.66
    _add_beam(mb, (-1.24, DECK_Y, 0.44), (-1.12, PERCH_Y, 0.36), 0.105, 0.105, 'timber', C_OAK_DEEP, 0.0)
    _add_beam(mb, (-0.54, DECK_Y, 1.06), (-0.48, PERCH_Y, 0.94), 0.105, 0.105, 'timber', C_OAK_DEEP, 0.0)
    with xf(mb, T(-0.68, PERCH_Y, 0.36) @ R('Y', -32.0)):
        for pli in range(4):
            cbox(mb, (0.0, 0.03, -0.32 + pli * 0.215), (1.02, 0.06, 0.19), 'timber',
                 C_DRIFT_SUN if pli % 2 == 0 else C_OAK_SUN, 0.0)
        # 2-Sided Lookout Handrail + Mid-Rope Guardrail wrapping the Seaward & Port Perch Edges!
        for rx_r, rz_r in ((-0.44, -0.36), (0.44, -0.36), (-0.44, 0.36)):
            cbox(mb, (rx_r, 0.44, rz_r), (0.075, 0.80, 0.075), 'timber', C_OAK_DEEP, 0.0)
        cbox(mb, (0.0, 0.82, -0.36), (0.98, 0.075, 0.085), 'timber', C_DRIFT_SUN, 0.0)
        cbox(mb, (-0.44, 0.82, 0.0), (0.085, 0.075, 0.80), 'timber', C_DRIFT_SUN, 0.0)
        tube(mb, [Vector((-0.44, 0.44, 0.36)), Vector((-0.44, 0.40, 0.0)), Vector((-0.44, 0.44, -0.36)),
                  Vector((0.0, 0.40, -0.36)), Vector((0.44, 0.44, -0.36))],
             0.022, 4, 'rope', C_HEMP_HI, caps=(False, False), mode='flat')
        # Mounted Burnished Brass Smuggler's Spyglass Telescope aimed Seaward (-Z)!
        with xf(mb, T(-0.18, 0.94, -0.36) @ R('Y', 32.0) @ R('X', -8.0)):
            cbox(mb, (0.0, -0.07, 0.0), (0.065, 0.14, 0.065), 'brass', C_BRASS_DARK, 0.0)
            with xf(mb, M_Y2Z):
                cyl(mb, 0.060, -0.34, 0.02, 6, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.046)
                cyl(mb, 0.040,  0.02, 0.26, 6, 'brass', C_BRASS_WARM, False, 0.0, 0.032)
                _open_band(mb, 0.066, -0.35, -0.28, 6, 'brass', C_BRASS_DARK)
        # Compact Warm Brass Watch-Perch Storm Lantern perched on the Port Corner Post ('glass' warm amber!)
        _build_storm_lantern(mb, (-0.44, 1.00, 0.36), scale=0.62, brass_cage=True, hanging=False)

    # Rustic wooden rung ladder climbing from the rear-port deck up to the spyglass watch-perch
    lad_l0, lad_l1 = Vector((-1.16, DECK_Y, 0.84)), Vector((-0.94, PERCH_Y + 0.06, 0.56))
    lad_r0, lad_r1 = Vector((-0.78, DECK_Y, 1.12)), Vector((-0.56, PERCH_Y + 0.06, 0.84))
    _add_beam(mb, lad_l0, lad_l1, 0.060, 0.060, 'timber', C_OAK_RICH, 0.0)
    _add_beam(mb, lad_r0, lad_r1, 0.060, 0.060, 'timber', C_OAK_RICH, 0.0)
    for ri in range(4):
        rt = (ri + 0.5) / 4.0
        _add_beam(mb, lad_l0.lerp(lad_l1, rt), lad_r0.lerp(lad_r1, rt), 0.042, 0.042, 'timber', C_OAK_PALE, 0.0)

    # 4. Suspended Iron Fire-Basket Signal Beacon ('glass' warm amber embers — ZERO skull_glow!)
    _build_suspended_beacon_basket(mb, BEACON_POS, APEX_POS)

    # 5. Rope Pulley Halyard, Counterweight Stone Block & Timber Hauling Winch/Cleat on Starboard Leg!
    PULLEY_POS = Vector((0.26, 3.60, -0.14))
    CLEAT_POS  = LEG_SPECS[1][0].lerp(LEG_SPECS[1][1], 0.28)
    _add_beam(mb, (0.12, 3.78, -0.06), PULLEY_POS + Vector((0.0, 0.10, 0.0)), 0.026, 0.026, 'iron', C_IRON_FORGED, 0.0)
    with xf(mb, T(PULLEY_POS) @ R('Y', -30.0)):
        cbox(mb, (0.0, 0.0, 0.0), (0.12, 0.22, 0.16), 'timber', C_OAK_DEEP, 0.0)
        with xf(mb, M_Y2X):
            cyl(mb, 0.075, -0.04, 0.04, 6, 'brass', C_GOLD_BRIGHT, False, 0.0)
    tube(mb, [Vector((0.0, BEACON_POS.y + 0.56, 0.0)), PULLEY_POS, CLEAT_POS + Vector((-0.06, 0.04, -0.08))],
         0.024, 4, 'rope', C_HEMP_HI, caps=(True, True), mode='flat')
    with xf(mb, T(CLEAT_POS + Vector((-0.08, 0.0, -0.08))) @ R('Y', -32.0)):
        cbox(mb, (0.0, 0.0, 0.0), (0.12, 0.34, 0.12), 'timber', C_OAK_DEEP, 0.0)
        cbox(mb, (0.0, 0.0, -0.09), (0.08, 0.40, 0.07), 'iron', C_IRON_BRIGHT, 0.0)
        torus(mb, 0.095, 0.026, 6, 3, 'rope', C_HEMP_HI, True)
    # Stone counterweight hanging neatly below the cleat pulley line for beacon hoisting authenticity!
    cw_p = CLEAT_POS + Vector((0.18, -0.36, 0.12))
    _add_beam(mb, CLEAT_POS + Vector((0.06, 0.06, 0.02)), cw_p + Vector((0.0, 0.14, 0.0)), 0.022, 0.022, 'rope', C_HEMP_MID, 0.0)
    with xf(mb, T(cw_p)):
        cyl(mb, 0.14, -0.14, 0.14, 6, 'limestone', C_HEADLAND_DARK, False, 0.0)
        _open_band(mb, 0.148, -0.04, 0.04, 6, 'iron', C_IRON_FORGED)

    # 6. Wooden Signal-Flag Chest, Coiled Hawsers, Stacked Rum Crates, Rum Kegs & Spare Beacon Firewood Rack!
    _build_signal_flag_chest(mb, (-0.72, DECK_Y, -0.96), yaw_deg=26.0)
    _build_rope_coil(mb, (0.86, DECK_Y + 0.01, -1.04), radius=0.30, turns=3, r=0.046, segs=6, psegs=4,
                     col_a=C_HEMP_HI, col_b=C_HEMP_MID)
    _build_rope_coil(mb, (-0.18, DECK_Y + 0.01, 1.10), radius=0.22, turns=2, r=0.038, segs=6, psegs=3,
                     col_a=C_HEMP_MID, col_b=C_HEMP_DARK)

    # Stacked Rum Crates & Twin Coopered Smuggler's Rum Kegs (rich Front & Rear 3/4!)
    _build_rum_crate(mb, (0.88, DECK_Y, 0.32), size=(0.58, 0.46, 0.50), yaw_deg=-18.0, stripe_col=C_CRIMSON_HI)
    _build_rum_crate(mb, (0.76, DECK_Y + 0.46, 0.38), size=(0.46, 0.38, 0.42), yaw_deg=12.0, stripe_col=C_GOLD_CLOTH)
    _build_rum_crate(mb, (0.28, DECK_Y, 0.88), size=(0.54, 0.42, 0.46), yaw_deg=28.0, stripe_col=C_TEAL_HI)
    for b_pos, b_yaw, b_rad, b_h in (
        ((1.04, DECK_Y + 0.34, -0.26), -14.0, 0.25, 0.68),
        ((0.46, DECK_Y + 0.28, -0.44),  22.0, 0.21, 0.56),
    ):
        with xf(mb, T(b_pos) @ R('Y', b_yaw)):
            hh = b_h * 0.5
            prof_b = [(0.0, -hh), (b_rad * 0.80, -hh), (b_rad, 0.0), (b_rad * 0.80, hh), (0.0, hh)]
            lathe(mb, prof_b, 6, 'timber', C_OAK_RICH, False, False)
            _open_band(mb, b_rad * 0.92, -hh * 0.65, -hh * 0.48, 6, 'iron', C_IRON_FORGED)
            _open_band(mb, b_rad * 0.96,  hh * 0.48,  hh * 0.65, 6, 'iron', C_IRON_RUST_HI)

    # Bundled Spare Beacon Firewood Log Rack on Port Mid-Deck (-1.28, DECK_Y, -0.02)!
    with xf(mb, T(-1.26, DECK_Y, -0.02) @ R('Y', 18.0)):
        for sx_w in (-0.26, 0.26):
            _add_beam(mb, (sx_w, 0.0, -0.22), (sx_w, 0.48, 0.22), 0.055, 0.055, 'timber', C_OAK_DEEP, 0.0)
            _add_beam(mb, (sx_w, 0.0,  0.22), (sx_w, 0.48, -0.22), 0.055, 0.055, 'timber', C_OAK_DEEP, 0.0)
        for ly_w, lz_w, lc_w in ((0.22, -0.09, C_DRIFT_SUN), (0.22, 0.09, C_OAK_RICH),
                                 (0.35, -0.05, C_OAK_SUN), (0.35, 0.07, C_DRIFT_MID), (0.46, 0.0, C_DRIFT_SUN)):
            with xf(mb, T(0.0, ly_w, lz_w) @ M_Y2X):
                cyl(mb, 0.068, -0.38, 0.38, 5, 'timber', lc_w, False, 0.0)
        with xf(mb, T(0.0, 0.34, 0.0) @ M_Y2X):
            torus(mb, 0.18, 0.022, 6, 3, 'rope', C_HEMP_HI, True)

    # 7. Fluttering Crimson-Gold Signal Code Pennants ('paint' + UV2!)
    _build_wind_banner(
        mb, root_pos=(0.0, 4.38, -0.18), length=1.42, h0=0.42,
        out_dir=(0.90, -0.02, -0.44),
        col_main=C_CRIMSON_HI, col_alt=C_GOLD_CLOTH, col_trim=C_CRIMSON_MID,
        phase=0.24, swallowtail=True,
    )
    # Taut diagonal signal-code halyard line carrying 2 broadside-streaming triangular crimson-gold code pennants!
    hal_top = Vector((0.0, 4.12, -0.14))
    hal_bot = CLEAT_POS + Vector((0.06, 0.16, -0.06))
    tube(mb, [hal_top, hal_bot], 0.014, 3, 'rope', C_HEMP_MID, caps=(False, False), mode='flat')
    for ht, hc1, hc2, hc3, hph in (
        (0.28, C_GOLD_CLOTH, C_CRIMSON_HI, C_CRIMSON_MID, 0.52),
        (0.56, C_CRIMSON_HI, C_GOLD_CLOTH, C_CREAM_BRIGHT, 0.78),
    ):
        hp = hal_top.lerp(hal_bot, ht)
        _build_wind_banner(
            mb, root_pos=hp, length=0.78, h0=0.32,
            out_dir=(0.94, -0.03, 0.34),
            col_main=hc1, col_alt=hc2, col_trim=hc3,
            phase=hph, swallowtail=False, triangular=True,
        )

    # 8. Coastal Headland Ferns ('foliage' + UV2) tucked neatly into the rocky headland flanks
    for fpos, fsc, flean, fph in (
        ((-1.42, 0.34, -1.56), 0.54, (-0.55, 0.0, -0.84), 0.15),
        (( 1.44, 0.34, -1.52), 0.52, ( 0.55, 0.0, -0.84), 0.42),
        ((-1.78, 0.34,  1.06), 0.56, (-0.82, 0.0,  0.58), 0.68),
        (( 1.82, 0.34,  0.88), 0.52, ( 0.84, 0.0,  0.54), 0.91),
        ((-0.24, 0.34,  1.88), 0.50, (-0.15, 0.0,  0.98), 0.31),
        ((-1.98, 0.34, -0.12), 0.48, (-0.98, 0.0, -0.12), 0.57),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=3, rng=rng, phase=fph, lean_dir=flean, segs=2)

    build(mb)

    add_empty('Lantern_SignalTripod', BEACON_POS)
    col_piece('col_signaltripod_base', col_pts)
    export_landmark_glb(outdir, 'coastal_smuggler_signal_tripod.glb')


# ==============================================================================
# 4. VOLCANIC OBSIDIAN WYRM ARCH (volcanic_obsidian_wyrm_arch.glb)
# ==============================================================================

def _build_obsidian_rib_fin(mb, p_root, p_tip, width, thick, face_nrm, glow_vein=True, curve_up=0.0):
    """Sweeping sickle-curved razor-faceted volcanic obsidian wyrm spine-rib blade ('basalt')
    with crisp edge facets and optional glowing molten lava base seam ('glass' ONLY!)."""
    a = Vector(p_root)
    b = Vector(p_tip)
    axis = b - a
    if axis.length < 1e-4:
        return
    ax = axis.normalized()
    fn = Vector(face_nrm)
    fn = fn - ax * fn.dot(ax)
    if fn.length < 1e-4:
        fn = Vector((0.0, 0.0, -1.0))
    fn.normalize()
    lat = ax.cross(fn).normalized()

    st_t = [0.00, 0.36, 0.72, 1.00]
    st_w = [width * 0.86, width * 1.00, width * 0.56, 0.018]
    st_d = [thick * 1.00, thick * 0.88, thick * 0.46, 0.014]
    secs = []
    for t, w, d in zip(st_t, st_w, st_d):
        # Graceful sickle arch sweep along Y when curve_up != 0
        arc_off = Vector((0.0, curve_up * sin(t * pi) * (0.4 + 0.6 * t), 0.0))
        c = a.lerp(b, t) + lat * (0.04 * sin(t * pi)) + arc_off
        secs.append([
            c + lat * w,
            c + fn * d,
            c - lat * w,
            c - fn * d,
        ])
    loft(mb, secs, 'basalt', C_OBSIDIAN_HI, closed=True, caps=(True, True), mode='flat',
         scols=[C_OBSIDIAN_DARK, C_OBSIDIAN_MID, C_OBSIDIAN_HI, C_OBSIDIAN_EDGE])

    if glow_vein:
        for s_fn in (-1.0, 1.0):
            _sculpt_glow_ribbon(
                mb, [a.lerp(b, 0.06) + fn * (s_fn * thick * 0.80), a.lerp(b, 0.46) + fn * (s_fn * thick * 0.72)],
                [width * 0.16, width * 0.05], fn * s_fn,
                hot_core=True, ridge_h=0.022, mat='glass',
                c_core=C_FLAME_MID, c_mid_col=C_FLAME_DEEP, c_edge_col=C_MAGMA_CRIMSON, c_tip_col=C_MAGMA_CRIMSON,
            )


def _build_wyrm_arch_wing(mb, side_sgn):
    """One sweeping half of the monumental volcanic obsidian wyrm spine-ribbed gateway arch,
    rising from battered basalt piers at x=±1.82 m to meet cleanly at the keystone apex (y=5.06 m),
    bristling with sweeping jagged sickle-curved volcanic spine-ribs, glowing molten magma veins
    ('glass' ONLY!) and bolted iron restraining shackle cuffs."""
    arch_ctrl = [
        (side_sgn * 1.84, 0.42, 0.48, 0.58),
        (side_sgn * 1.88, 1.56, 0.42, 0.50),
        (side_sgn * 1.68, 2.76, 0.37, 0.44),
        (side_sgn * 1.20, 3.86, 0.33, 0.40),
        (side_sgn * 0.54, 4.68, 0.30, 0.36),
        (side_sgn * 0.02, 5.04, 0.28, 0.34),
    ]
    pts = [Vector((c[0], c[1], 0.0)) for c in arch_ctrl]
    n = len(pts)

    secs = []
    scols = []
    for i, (cx, cy, rxy, zh) in enumerate(arch_ctrl):
        p = pts[i]
        tang = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        n_out = Vector((side_sgn * tang.y, -side_sgn * tang.x, 0.0)).normalized()
        z_v = Vector((0.0, 0.0, 1.0))
        secs.append([
            p + n_out * (rxy * 1.24),
            p + n_out * (rxy * 0.52) + z_v * (zh * 0.94),
            p - n_out * (rxy * 0.62) + z_v * (zh * 0.86),
            p - n_out * (rxy * 0.96),
            p - n_out * (rxy * 0.62) - z_v * (zh * 0.86),
            p + n_out * (rxy * 0.52) - z_v * (zh * 0.94),
        ])
        scols.append(C_OBSIDIAN_DARK if i == 0 else (C_OBSIDIAN_MID if i <= 2 else (C_OBSIDIAN_HI if i <= 4 else C_OBSIDIAN_EDGE)))

    loft(mb, secs, 'basalt', C_OBSIDIAN_HI, closed=True, caps=(True, True), mode='flat', scols=scols)

    # Glowing Molten Magma Veins climbing both Front (-Z) & Rear (+Z) Arch Faces ('glass' ONLY!)
    for z_sgn in (-1.0, 1.0):
        v_pts = [Vector((arch_ctrl[i][0], arch_ctrl[i][1], z_sgn * (arch_ctrl[i][3] * 0.92))) for i in range(n)]
        _sculpt_glow_ribbon(
            mb, v_pts, [0.072, 0.064, 0.056, 0.048, 0.042, 0.036], (0.0, 0.0, z_sgn),
            hot_core=True, ridge_h=0.028, mat='glass',
            c_core=C_FLAME_MID, c_mid_col=C_FLAME_DEEP, c_edge_col=C_MAGMA_CRIMSON, c_tip_col=C_MAGMA_CRIMSON,
        )

    # 5 Sweeping Sickle-Curved Jagged Volcanic Spine-Rib Blades flaring dramatically along the Arch!
    rib_specs = [
        (1, 0.76, 0.52, 0.23, 0.078, False, -0.14),
        (2, 0.94, 0.68, 0.25, 0.084, True,  -0.18),
        (3, 0.92, 0.78, 0.24, 0.080, True,  -0.18),
        (4, 0.78, 0.82, 0.21, 0.074, True,  -0.16),
        (5, 0.54, 0.76, 0.18, 0.064, False, -0.12),
    ]
    for st_i, r_out, r_up, rw, rd, r_glow, r_cu in rib_specs:
        pr = pts[st_i]
        pt = pr + Vector((side_sgn * r_out, r_up, 0.06))
        _build_obsidian_rib_fin(mb, pr, pt, rw, rd, (0.0, 0.0, -1.0), glow_vein=r_glow, curve_up=r_cu)

    # Swept Forward & Rear Inner Wyrm Ribcage Talons framing the Lower Pier Portal (rich 3D depth!)
    for z_sgn in (-1.0, 1.0):
        for py, p_out_z, p_up in ((1.36, 0.64, 0.38), (2.34, 0.58, 0.42)):
            pr = Vector((side_sgn * 1.78, py, z_sgn * 0.32))
            pt = Vector((side_sgn * 1.56, py + p_up, z_sgn * (0.32 + p_out_z)))
            _build_obsidian_rib_fin(mb, pr, pt, 0.16, 0.058, (side_sgn, 0.0, 0.0), glow_vein=(py > 2.0))

    # Heavy Forged-Iron Restraining Shackle Cuff clamped snugly onto the Arch Haunch (station 2, y=2.76 m)
    sh_p = pts[2]
    sh_t = (pts[3] - pts[1]).normalized()
    rot_sh = Vector((0.0, 1.0, 0.0)).rotation_difference(sh_t).to_matrix().to_4x4()
    with xf(mb, T(sh_p) @ rot_sh):
        cyl(mb, 0.48, -0.14, 0.14, 6, 'iron', C_IRON_FORGED, False, 0.0)
        torus(mb, 0.50, 0.048, 6, 4, 'iron', C_IRON_BRIGHT, False)
    front_lug = sh_p + Vector((side_sgn * 0.42, -0.06, -0.32))
    rear_lug  = sh_p + Vector((side_sgn * 0.42, -0.06,  0.32))
    inner_lug = sh_p + Vector((-side_sgn * 0.42, 0.12, 0.0))
    cbox(mb, front_lug, (0.18, 0.18, 0.18), 'iron', C_IRON_RUST_HI, 0.0)
    cbox(mb, rear_lug,  (0.18, 0.18, 0.18), 'iron', C_IRON_RUST_HI, 0.0)
    cbox(mb, inner_lug, (0.16, 0.16, 0.16), 'iron', C_IRON_BRIGHT, 0.0)
    return front_lug, rear_lug, inner_lug


def _build_obsidian_wyrm_skull_keystone(mb):
    """Monumental horned obsidian magma-wyrm skull keystone crowning the arch apex (y=4.34..6.20 m),
    complete with snarling upper & lower obsidian jaws, fiery fangs, blazing molten maw & eyes
    ('glass' ONLY — ZERO skull_glow!), twin colossal curved wyrm horns & spiked rear dorsal crest."""
    KY = 4.98
    with xf(mb, T(0.0, KY, 0.0)):
        skull_secs = [
            _rect_oct(0.0, -0.36,  0.04, 0.56, 0.54, 0.16),
            _rect_oct(0.0,  0.14, -0.02, 0.64, 0.62, 0.18),
            _rect_oct(0.0,  0.46,  0.06, 0.46, 0.48, 0.14),
        ]
        loft(mb, skull_secs, 'basalt', C_OBSIDIAN_HI, closed=True, caps=(True, True), mode='flat',
             scols=[C_OBSIDIAN_DARK, C_OBSIDIAN_HI, C_OBSIDIAN_EDGE])

        # Swept armored upper wyrm snout projecting boldly seaward (-Z)
        snout_secs = [
            [(-0.46, 0.34, -0.34), (0.46, 0.34, -0.34), (0.50, -0.04, -0.34), (-0.50, -0.04, -0.34)],
            [(-0.34, 0.24, -0.78), (0.34, 0.24, -0.78), (0.38, -0.06, -0.78), (-0.38, -0.06, -0.78)],
            [(-0.18, 0.14, -1.18), (0.18, 0.14, -1.18), (0.20, -0.04, -1.18), (-0.20, -0.04, -1.18)],
        ]
        loft(mb, snout_secs, 'basalt', C_OBSIDIAN_EDGE, closed=True, caps=(True, True), mode='flat',
             scols=[C_OBSIDIAN_MID, C_OBSIDIAN_HI, C_OBSIDIAN_EDGE])

        # Snarling Hinged Obsidian Lower Wyrm Jaw Mandible flaring boldly downward beneath the molten maw!
        jaw_secs = [
            [(-0.38, -0.26, -0.30), (0.38, -0.26, -0.30), (0.40, -0.44, -0.30), (-0.40, -0.44, -0.30)],
            [(-0.28, -0.42, -0.74), (0.28, -0.42, -0.74), (0.30, -0.58, -0.74), (-0.30, -0.58, -0.74)],
            [(-0.14, -0.52, -1.06), (0.14, -0.52, -1.06), (0.12, -0.66, -1.06), (-0.12, -0.66, -1.06)],
        ]
        loft(mb, jaw_secs, 'basalt', C_OBSIDIAN_HI, closed=True, caps=(True, True), mode='flat',
             scols=[C_OBSIDIAN_DARK, C_OBSIDIAN_MID, C_OBSIDIAN_EDGE])

        # Nasal horn spire & sharp sculpted brow ridges
        _build_obsidian_rib_fin(mb, (0.0, 0.16, -0.96), (0.0, 0.64, -1.18), 0.14, 0.056, (1.0, 0.0, 0.0), glow_vein=False)
        for sx in (-1.0, 1.0):
            _add_beam(mb, (sx * 0.12, 0.30, -0.58), (sx * 0.68, 0.46, -0.24), 0.11, 0.12, 'basalt', C_OBSIDIAN_EDGE, 0.0)
            _add_beam(mb, (sx * 0.44, -0.14, -0.34), (sx * 0.78, -0.44, -0.08), 0.12, 0.11, 'basalt', C_OBSIDIAN_HI, 0.0)
            # Twin fiercely blazing molten amber-gold wyrm eyes ('glass' ONLY!)
            with xf(mb, T(sx * 0.34, 0.22, -0.58) @ R('Y', -sx * 24.0)):
                lathe(mb, [(0.0, -0.065), (0.145, 0.0), (0.0, 0.095)], 4, 'glass', C_FLAME_CORE, False)

        # Blazing Incandescent Molten Wyrm Jaws & Furnace Throat Core ('glass' warm molten orange-amber ONLY!)
        lathe(mb, [(0.0, -0.48), (0.40, -0.36), (0.44, -0.12), (0.30, 0.02), (0.0, 0.06)],
              6, 'glass', C_FLAME_MID, False, False,
              lambda i, k: C_FLAME_CORE if i in (1, 2) else C_FLAME_DEEP)
        cbox(mb, (0.0, -0.24, -0.70), (0.50, 0.22, 0.56), 'glass', C_FLAME_MID, 0.0)
        # 6 Upper Downward Fangs + 2 Lower Upward Chin Fangs framing the Blazing Molten Maw!
        for sx in (-1.0, 1.0):
            for fz_f, fx_f, flen_f, fr_f in ((-1.06, 0.16, 0.38, 0.064), (-0.74, 0.32, 0.32, 0.056), (-0.42, 0.44, 0.28, 0.050)):
                tube(mb, [Vector((sx * fx_f, -0.04, fz_f)),
                          Vector((sx * (fx_f * 0.90), -0.04 - flen_f * 0.55, fz_f - 0.04)),
                          Vector((sx * (fx_f * 0.80), -0.04 - flen_f, fz_f + 0.04))],
                     [fr_f, fr_f * 0.55, 0.012], 4, 'basalt', C_OBSIDIAN_EDGE, caps=(False, True), mode='flat')
            # Upward-pointing lower mandible fang
            tube(mb, [Vector((sx * 0.14, -0.52, -0.96)), Vector((sx * 0.12, -0.26, -0.98))],
                 [0.048, 0.012], 4, 'basalt', C_OBSIDIAN_EDGE, caps=(False, True), mode='flat')

        # Rear (+Z) Spiked Obsidian Wyrm Occiput Spine Crest (so Rear 3/4 is equally fierce!)
        for f_r, f_t, fw in (
            ((0.0, 0.34, 0.36), (0.0, 0.98, 0.86), 0.20),
            ((0.0, 0.02, 0.46), (0.0, 0.44, 1.12), 0.18),
            ((0.0, -0.26, 0.42), (0.0, -0.12, 0.98), 0.15),
        ):
            _build_obsidian_rib_fin(mb, f_r, f_t, fw, 0.068, (1.0, 0.0, 0.0), glow_vein=True)

        # Twin Colossal Curved Obsidian Wyrm Horns sweeping dramatically skyward to y = 6.20 m!
        for sx in (-1.0, 1.0):
            h_pts = [
                Vector((sx * 0.42, 0.28, -0.04)),
                Vector((sx * 0.94, 0.62,  0.04)),
                Vector((sx * 1.32, 0.96,  0.14)),
                Vector((sx * 1.44, 1.22,  0.24)),
            ]
            tube(mb, h_pts, [0.22, 0.16, 0.095, 0.022], 5, 'basalt', C_OBSIDIAN_EDGE,
                 caps=(False, True), mode='flat',
                 scols=[C_OBSIDIAN_MID, C_OBSIDIAN_HI, C_OBSIDIAN_EDGE, C_OBSIDIAN_EDGE])
            _sculpt_glow_ribbon(
                mb, [p + Vector((0.0, 0.0, -0.11)) for p in h_pts[:3]],
                [0.048, 0.036, 0.020], (0.0, 0.0, -1.0), hot_core=True, ridge_h=0.020, mat='glass',
                c_core=C_FLAME_MID, c_mid_col=C_FLAME_DEEP, c_edge_col=C_MAGMA_CRIMSON, c_tip_col=C_MAGMA_CRIMSON,
            )
        # Forged-iron keystone suspension hook directly beneath the blazing molten jaws!
        with xf(mb, T(0.0, -0.56, 0.0) @ M_Y2Z):
            torus(mb, 0.12, 0.034, 6, 4, 'iron', C_IRON_BRIGHT, False)


def gen_volcanic_obsidian_wyrm_arch(outdir):
    """Monumental charred-basalt & obsidian horned magma-wyrm ribbed arch gateway (~5.2 m W x
    4.2 m D x 6.2 m H, -3.50 m deep volcanic basalt skirt) w/ sweeping jagged volcanic spine-ribs
    arching over an obsidian skull keystone with blazing molten jaws & suspended glowing magma-ore
    heart ('glass' warm molten orange-amber linear COLOR_0 — ZERO skull_glow!), iron restraining
    chains & lava-fissured anchor spurs, convex collider 'col_wyrmarch_base', and empty
    'Lantern_WyrmArch'."""
    clear_scene()
    mb = MB('volcanic_obsidian_wyrm_arch', seed=2304)
    rng = random.Random(SEED + 2304)
    col_pts = []

    PLINTH_Y = 0.44
    CAUSE_Y  = 0.64
    HEART_POS = Vector((0.0, 2.94, 0.0))

    # 1. Deep Lava-Cracked Charred-Basalt Gateway Plinth Skirt plunging cleanly to y = -3.50 m (~5.2 m W x 4.2 m D)
    plinth_secs = [
        _rect_oct(0.0, -3.50, 0.0, 2.54, 1.96, 0.42),
        _rect_oct(0.0, -1.55, 0.0, 2.48, 1.90, 0.40),
        _rect_oct(0.0,  0.00, 0.0, 2.42, 1.84, 0.38),
        _rect_oct(0.0, PLINTH_Y, 0.0, 2.36, 1.78, 0.36),
    ]
    _loft_horizontal_masonry(
        mb, plinth_secs, 'basalt',
        [C_OBSIDIAN_ABYSS, C_OBSIDIAN_DARK, C_OBSIDIAN_MID, C_OBSIDIAN_HI],
        rng, caps=(True, True), top_mat='basalt', top_col=C_OBSIDIAN_MID,
    )

    for yc, hx, hz in ((-3.50, 2.54, 1.96), (0.0, 2.42, 1.84), (CAUSE_Y, 2.38, 1.88), (4.60, 2.22, 1.12), (6.20, 1.56, 0.96)):
        col_pts.extend(_rect_oct(0.0, yc, 0.0, hx, hz, 0.34))

    # Stepped Obsidian Ceremonial Gateway Causeway running cleanly through the arch (-Z to +Z)!
    cbox(mb, (0.0, 0.54, 0.0), (2.28, 0.20, 3.32), 'basalt', C_OBSIDIAN_HI, 0.0)
    for z_sgn in (-1.0, 1.0):
        cbox(mb, (0.0, 0.24, z_sgn * 1.94), (1.76, 0.42, 0.36), 'basalt', C_OBSIDIAN_MID, 0.0)
        cbox(mb, (0.0, 0.48, z_sgn * 1.66), (1.52, 0.30, 0.32), 'basalt', C_OBSIDIAN_HI, 0.0)

    # Organic Jagged Tectonic Molten Lava Floor Fissures fracturing the Gateway Threshold ('glass' ONLY!)
    _sculpt_glow_ribbon(
        mb, [Vector((-0.06, CAUSE_Y + 0.02, -1.78)), Vector((0.20, CAUSE_Y + 0.02, -1.04)),
             Vector((-0.14, CAUSE_Y + 0.02, -0.32)), Vector((0.12, CAUSE_Y + 0.02,  0.42)),
             Vector((-0.18, CAUSE_Y + 0.02,  1.12)), Vector((0.06, CAUSE_Y + 0.02,  1.78))],
        [0.042, 0.068, 0.092, 0.088, 0.064, 0.040], (0.0, 1.0, 0.0), hot_core=True, ridge_h=0.028, mat='glass',
        c_core=C_FLAME_MID, c_mid_col=C_FLAME_DEEP, c_edge_col=C_MAGMA_CRIMSON, c_tip_col=C_MAGMA_CRIMSON,
    )
    for sx in (-1.0, 1.0):
        _sculpt_glow_ribbon(
            mb, [Vector((sx * 0.10, CAUSE_Y + 0.02, sx * -0.18)),
                 Vector((sx * 0.72, CAUSE_Y + 0.02, sx *  0.22)),
                 Vector((sx * 1.28, CAUSE_Y + 0.02, sx * -0.16)),
                 Vector((sx * 1.82, PLINTH_Y + 0.02, sx * 0.04))],
            [0.075, 0.068, 0.056, 0.038], (0.0, 1.0, 0.0), hot_core=True, ridge_h=0.026, mat='glass',
            c_core=C_FLAME_MID, c_mid_col=C_FLAME_DEEP, c_edge_col=C_MAGMA_CRIMSON, c_tip_col=C_MAGMA_CRIMSON,
        )

    # 2. Monumental Twin Volcanic Obsidian Wyrm Spine-Ribbed Gateway Arch Wings!
    wing_lugs = {}
    for side_sgn in (-1.0, 1.0):
        wing_lugs[side_sgn] = _build_wyrm_arch_wing(mb, side_sgn)

    # 3. Monumental Horned Obsidian Wyrm Skull Keystone with Blazing Molten Jaws (y = 4.34 .. 6.20 m)!
    _build_obsidian_wyrm_skull_keystone(mb)

    # 4. Suspended Glowing Magma-Ore Heart Cradled in Iron Containment Rings ('glass' ONLY — ZERO skull_glow!)
    with xf(mb, T(HEART_POS)):
        lathe(mb, [(0.0, -0.52), (0.34, -0.32), (0.43, 0.00), (0.33, 0.32), (0.0, 0.54)],
              8, 'glass', C_FLAME_MID, False, False,
              lambda i, k: C_FLAME_CORE if i == 2 else (C_FLAME_MID if i in (1, 3) else C_FLAME_DEEP))
        for k in range(6):
            ar = radians(k * 60.0 + 30.0)
            ca, sa = cos(ar), sin(ar)
            tube(mb, [Vector((0.36 * ca, -0.46, 0.36 * sa)),
                      Vector((0.54 * ca,  0.00, 0.54 * sa)),
                      Vector((0.32 * ca,  0.50, 0.32 * sa))],
                 [0.084, 0.106, 0.044], 4, 'basalt', C_OBSIDIAN_ABYSS, caps=(True, True), mode='flat')
        torus(mb, 0.55, 0.046, 8, 4, 'iron', C_IRON_FORGED, False)
        with xf(mb, M_Y2Z):
            torus(mb, 0.57, 0.040, 8, 4, 'iron', C_IRON_BRIGHT, False)
        with xf(mb, T(0.0, 0.64, 0.0) @ M_Y2Z):
            torus(mb, 0.10, 0.030, 6, 4, 'iron', C_IRON_BRIGHT, False)
        # 3 Sharp Erupting Incandescent Magma Flame Licks curling upward toward the Wyrm Jaws ('glass' ONLY!)
        for fx_f, fz_f, fh_f, fr_f, sw in (
            ( 0.00,  0.00, 0.68, 0.11,  0.09),
            (-0.20, -0.09, 0.48, 0.075, -0.10),
            ( 0.20,  0.09, 0.50, 0.078,  0.10),
        ):
            tube(mb, [(fx_f, 0.34, fz_f),
                      (fx_f * 0.7 - sw * 0.4, 0.34 + fh_f * 0.48, fz_f * 0.7),
                      (fx_f * 0.2 + sw * 0.4, 0.34 + fh_f,        fz_f * 0.2)],
                 [fr_f, fr_f * 0.48, 0.014], 4, 'glass', C_FLAME_DEEP, caps=(False, True), mode='flat',
                 scols=[C_MAGMA_CRIMSON, C_FLAME_DEEP, C_FLAME_CORE])

    # Heavy Forged-Iron Suspension Chains holding the Magma-Ore Heart cleanly from Keystone & Inner Arch Shoulders!
    _add_chain_links(
        mb, (0.0, 4.38, 0.0), (0.0, HEART_POS.y + 0.64, 0.0),
        n_links=3, link_r=0.11, wire_r=0.032, segs=5, psegs=4, sag=0.0,
        mat='iron', rust_stride=2, stretch_y=1.40, col_a=C_IRON_BRIGHT, col_b=C_IRON_RUST_HI,
    )
    for side_sgn in (-1.0, 1.0):
        inner_lug = wing_lugs[side_sgn][2]
        _add_chain_links(
            mb, inner_lug, HEART_POS + Vector((side_sgn * 0.56, 0.02, 0.0)),
            n_links=3, link_r=0.11, wire_r=0.032, segs=5, psegs=4, sag=0.08,
            mat='iron', rust_stride=2, stretch_y=1.40, col_a=C_IRON_FORGED, col_b=C_IRON_RUST_HI,
        )

    # 5. Four Lava-Fissured Volcanic Basalt Anchor Spurs & Heavy Iron Restraining Chains!
    for side_sgn in (-1.0, 1.0):
        front_lug, rear_lug, _ = wing_lugs[side_sgn]
        for z_sp, lug_pt in ((-1.0, front_lug), (1.0, rear_lug)):
            spur_bp = Vector((side_sgn * 1.96, -0.35, z_sp * 1.18))
            spur_dir = Vector((side_sgn * 0.28, 1.0, z_sp * 0.24)).normalized()
            spur_pts = [spur_bp, spur_bp + spur_dir * 1.24, spur_bp + spur_dir * 2.12]
            tube(mb, spur_pts, [0.34, 0.22, 0.030], 4, 'basalt', C_OBSIDIAN_HI,
                 caps=(False, True), mode='flat',
                 scols=[C_OBSIDIAN_DARK, C_OBSIDIAN_MID, C_OBSIDIAN_EDGE])
            _sculpt_glow_ribbon(
                mb, [spur_pts[0] + Vector((side_sgn * 0.24, 0.65, z_sp * 0.14)),
                     spur_pts[1] + Vector((side_sgn * 0.16, 0.30, z_sp * 0.10))],
                [0.056, 0.028], (side_sgn, 0.1, z_sp), hot_core=True, ridge_h=0.024, mat='glass',
                c_core=C_FLAME_MID, c_mid_col=C_FLAME_DEEP, c_edge_col=C_MAGMA_CRIMSON, c_tip_col=C_MAGMA_CRIMSON,
            )
            bot_anchor = spur_pts[1] + Vector((0.0, 0.18, 0.0))
            with xf(mb, T(bot_anchor)):
                cyl(mb, 0.25, -0.09, 0.09, 6, 'iron', C_IRON_BRIGHT, False, 0.0)
            _add_chain_links(
                mb, lug_pt + Vector((0.0, -0.04, 0.0)), bot_anchor + Vector((0.0, 0.08, 0.0)),
                n_links=5, link_r=0.14, wire_r=0.040, segs=5, psegs=4, sag=0.10,
                mat='iron', rust_stride=2, stretch_y=1.42,
                col_a=C_IRON_BRIGHT, col_b=C_IRON_RUST_HI,
            )

    build(mb)

    add_empty('Lantern_WyrmArch', HEART_POS)
    col_piece('col_wyrmarch_base', col_pts)
    export_landmark_glb(outdir, 'volcanic_obsidian_wyrm_arch.glb')


BUCCANEER_CRAFT_GENERATORS = [
    gen_pirate_blacksmith_anchor_forge,
    gen_ancient_abyssal_nautilus_shrine,
    gen_coastal_smuggler_signal_tripod,
    gen_volcanic_obsidian_wyrm_arch,
]
