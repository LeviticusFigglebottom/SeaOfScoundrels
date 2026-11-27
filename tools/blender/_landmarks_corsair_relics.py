# Sea of Scoundrels: 4 sculpted 3D Corsair & Reef Relic Landmarks (Wave I-16 / Pass I-Q9 — 66-Landmark Milestone!).
# Imported by tools/blender/gen_island_landmarks.py.
# Authored in Godot game coordinates (-Z seaward/hero-facing, +Y up, +X starboard, metres)
# and converted to Blender's Z-up frame on mesh creation via _landmark_common.
# STRICT SHARED-TEXTURE DEDUP CONTRACT: uses ONLY the 11 existing shared PBR materials
# (limestone, limestone_moss, basalt, temple_stone, skull_stone, timber, paint, rope,
# iron, brass, foliage) + untextured glass / skull_glow / col.
import bmesh
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

# Coastal cobble, wet beach pebbles, weathered driftwood & harbour oak
C_COBBLE_LIGHT   = srgb('#d4c7af')
C_COBBLE_MID     = srgb('#978a76')
C_COBBLE_DARK    = srgb('#5d554b')
C_TIDE_DARK      = mix(C_LIME_DARK, C_SEA_MOSS, 0.45)
C_PEBBLE_WET     = srgb('#6f6a60')
C_SAND_PALE      = srgb('#efe0be')
C_SAND_WARM      = srgb('#dcb680')
C_SAND_OCHRE     = srgb('#b28a58')
C_DRIFT_PALE     = srgb('#d4c7ae')
C_DRIFT_MID      = srgb('#9d8d76')
C_DRIFT_SHADE    = srgb('#6f6252')
C_OAK_FRESH      = srgb('#c68e4f')
C_OAK_CHAR       = srgb('#483122')
C_BARNACLE_PALE  = srgb('#efe7d4')
C_BARNACLE_MID   = srgb('#c5bba4')

# Warm temple limestone highlights for Kraken shrine readability
C_KRAKEN_STONE_HI  = srgb('#cfc3a8')
C_KRAKEN_STONE_MID = srgb('#99907d')
C_KRAKEN_STONE_DK  = srgb('#625d52')

# Pirate bounty parchment, crimson wax/pennant, ink silhouettes & tropical fish tones
C_PARCHMENT_HI   = srgb('#f2e4c1')
C_PARCHMENT_AGED = srgb('#d5bc8a')
C_PARCHMENT_EDGE = srgb('#ab8e5d')
C_INK_DARK       = srgb('#241b17')
C_CRIMSON_HI     = srgb('#cc2d22')
C_CRIMSON_MID    = srgb('#961f18')
C_CRIMSON_DARK   = srgb('#5d1310')
C_TEAL_BRIGHT    = srgb('#238e96')
C_TEAL_DARK      = srgb('#1b575c')
C_BRINE_WATER    = srgb('#39808a')
C_FISH_BACK      = srgb('#1b6e7d')
C_FISH_SILVER    = srgb('#a9d7da')
C_FISH_BELLY     = srgb('#ebf2ea')
C_FISH_FIN       = srgb('#e38c38')
C_FISH_SMOKED    = srgb('#c7762a')
C_WICKER_HI      = srgb('#d2b377')
C_WICKER_MID     = srgb('#9e7d4a')
C_WICKER_DARK    = srgb('#664d2b')

# Burnished brass, verdigris patina, forged iron & gleaming steel
C_GOLD_BRIGHT    = srgb('#f6cb4a')
C_BRASS_WARM     = srgb('#d8a23c')
C_BRASS_DARK     = srgb('#8a6220')
C_VERDIGRIS_HI   = srgb('#63baa3')
C_VERDIGRIS_MID  = srgb('#398b78')
C_VERDIGRIS_DK   = srgb('#23574b')
C_STEEL_BRIGHT   = srgb('#c2ccd9')
C_STEEL_MID      = srgb('#7c8696')
C_IRON_FORGED    = srgb('#505664')
C_IRON_BRONZE    = srgb('#905432')

# Mystical Kraken shrine turquoise tidal glow (used ONLY with 'skull_glow' on ancient_kraken_stone_fountain!)
C_AQUA_CORE      = srgb('#78fff0')
C_AQUA_MID       = srgb('#20dfc4')
C_AQUA_DEEP      = srgb('#0e9386')

# Warm lantern glow, smoking embers & volcanic molten magma (used ONLY with 'glass'!)
C_FLAME_CORE     = srgb('#ffdf6b')
C_FLAME_MID      = srgb('#ff7d18')
C_FLAME_DEEP     = srgb('#d62d0b')
C_MAGMA_CRIMSON  = srgb('#9e1b08')
C_OBSIDIAN_HI    = srgb('#706874')
C_OBSIDIAN_SHINE = srgb('#514b58')
C_OBSIDIAN_DARK  = srgb('#2e2a34')
C_OBSIDIAN_ABYSS = srgb('#19171e')

# Coastal foliage tones
C_VINE_DARK      = srgb('#164a1e')
C_VINE_MID       = srgb('#2d7426')
C_VINE_SUN       = srgb('#78bc2a')


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
        cyl(mb, 0.145 * s, -0.22 * s, -0.14 * s, 6, 'iron', C_IRON, False, 0.0, 0.165 * s)
        cyl(mb, 0.175 * s, 0.15 * s, 0.23 * s, 6, cage_mat, cage_col, False, 0.0, 0.072 * s)
        cyl(mb, 0.065 * s, 0.23 * s, 0.30 * s, 6, 'iron', C_IRON_RUST, False, 0.0, 0.036 * s)
        cyl(mb, 0.118 * s, -0.14 * s, 0.15 * s, 6, 'glass', C_LANTERN_GL, False, 0.0, 0.128 * s)
        for k in range(4):
            ang = k * pi * 0.5 + pi * 0.25
            cbox(mb, (0.142 * s * cos(ang), 0.005 * s, 0.142 * s * sin(ang)),
                 (0.028 * s, 0.31 * s, 0.028 * s), cage_mat, cage_col, 0.0)
        if hanging:
            with xf(mb, T(0.0, 0.33 * s, 0.0) @ M_Y2Z):
                torus(mb, 0.052 * s, 0.014 * s, 5, 4, 'iron', C_IRON, False)


def _build_coopered_cask(mb, M_bar, radius=0.31, height=0.78, rng=None,
                         col_a=C_TIMBER_MID, col_b=C_TIMBER_HI, col_head=C_TIMBER_DARK,
                         segs=6, stripe_col=None, open_fill=None):
    """Chunky coopered pirate rum or brine cask with forged-iron hoops."""
    hh = height * 0.5
    if open_fill is not None:
        prof = [
            (0.0,           -hh),
            (radius * 0.82, -hh),
            (radius,         0.0),
            (radius * 0.84,  hh),
            (radius * 0.72,  hh),
            (radius * 0.72,  hh - 0.12),
            (0.0,            hh - 0.12),
        ]
    else:
        prof = [
            (0.0,           -hh),
            (radius * 0.82, -hh),
            (radius,         0.0),
            (radius * 0.82,  hh),
            (0.0,            hh),
        ]
    stave_cols = [
        jit(col_a if k % 2 == 0 else col_b, rng, 0.06, 0.016) if rng else col_a
        for k in range(segs)
    ]
    with xf(mb, M_bar):
        lathe(mb, prof, segs, 'timber', col_a, False, False,
              lambda i, k: col_head if (i == 0 or (open_fill is None and i == 3)) else stave_cols[k])
        for hi_idx, (hy, hr) in enumerate(((-hh * 0.62, radius * 0.94), (hh * 0.62, radius * 0.94))):
            cyl(mb, hr, hy - 0.028, hy + 0.028, segs, 'iron',
                C_IRON_RUST if hi_idx == 1 else C_IRON, False, 0.0)
        if stripe_col is not None:
            cyl(mb, radius * 1.015, -hh * 0.16, hh * 0.16, segs, 'paint', stripe_col, False, 0.0)
        if open_fill is not None:
            fill_mat, fill_col = open_fill
            cyl(mb, radius * 0.71, hh - 0.14, hh - 0.08, segs, fill_mat, fill_col, False, 0.0)


def _build_treasure_chest(mb, M_chest, size=(0.92, 0.44, 0.56), open_deg=0.0):
    """Chunky iron-strapped oak pirate treasure chest with arched barrel lid & brass lockplate."""
    w, h, d = size
    hw, hh, hd = w * 0.5, h * 0.5, d * 0.5
    with xf(mb, M_chest):
        cbox(mb, (0.0, hh, 0.0), (w, h, d), 'timber', C_TIMBER_MID, 0.0, (1, 0, 0))
        for xs in (-hw + 0.055, 0.0, hw - 0.055):
            cbox(mb, (xs, hh, -hd - 0.012), (0.072, h + 0.02, 0.028), 'iron', C_IRON, 0.0)
            cbox(mb, (xs, hh,  hd + 0.012), (0.072, h + 0.02, 0.028), 'iron', C_IRON, 0.0)
        for sx in (-hw - 0.014, hw + 0.014):
            with xf(mb, T(sx, hh + 0.02, 0.0) @ M_Y2X):
                torus(mb, 0.068, 0.016, 4, 4, 'iron', C_IRON_RUST, False)
        cbox(mb, (0.0, h - 0.10, -hd - 0.026), (0.18, 0.20, 0.028), 'brass', C_GOLD_BRIGHT, 0.0)
        lid_M = T(0.0, h, hd) @ R('X', open_deg) @ T(0.0, 0.0, -hd)
        with xf(mb, lid_M):
            r_lid = hd * 1.02
            lid_ring = [(cos(pi * k / 4.0) * r_lid, sin(pi * k / 4.0) * 0.22) for k in range(5)]
            secs = [
                [Vector((-hw - 0.02, py, -pz)) for pz, py in lid_ring] + [Vector((-hw - 0.02, 0.0, -hd))],
                [Vector(( hw + 0.02, py, -pz)) for pz, py in lid_ring] + [Vector(( hw + 0.02, 0.0, -hd))],
            ]
            loft(mb, secs, 'timber', C_TIMBER_HI, closed=True, caps=(True, True), mode='flat')
            for xs in (-hw + 0.055, 0.0, hw - 0.055):
                rib_pts = [Vector((xs, sin(pi * k / 4.0) * 0.245, -cos(pi * k / 4.0) * (r_lid + 0.02)))
                           for k in range(5)]
                tube(mb, rib_pts, 0.028, 4, 'iron', C_IRON, mode='flat')


def _build_rope_coil_lean(mb, center, radius=0.28, turns=2, r=0.038, segs=6, psegs=4, col=C_ROPE):
    """Chunky coiled braided hemp rope pile ('rope')."""
    for i in range(turns):
        rr = radius * (1.0 - 0.24 * i)
        with xf(mb, T(center[0], center[1] + r * (1.0 + i * 1.56), center[2])):
            torus(mb, rr, r, segs, psegs, 'rope', mul(col, 0.88 + 0.12 * (i % 2)), True)


def _add_chain_links(mb, p_start, p_end, n_links=6, link_r=0.16, wire_r=0.048,
                     segs=4, psegs=4, sag=0.26, mat='iron', rust_stride=2, stretch_y=1.42,
                     col_a=C_IRON, col_b=C_IRON_RUST):
    """Tightly interlocking arc-length-spaced forged-iron chain links between p_start and p_end."""
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
        col = col_b if (k % rust_stride == 0) else col_a
        with xf(mb, T(pt) @ rot_q @ spin @ S(0.76, stretch_y, 0.76) @ M_Y2Z):
            torus(mb, link_r, wire_r, segs, psegs, mat, col, False)


def _add_leafy_vine_drape(mb, anchor, length, width, out_dir, rng, phase=0.0,
                          c_dark=C_VINE_DARK, c_mid=C_VINE_MID, c_sun=C_VINE_SUN):
    """Sculpted hanging leafy jungle vine ('foliage') with UV2 wind weights (0 root -> 0.96 tip)."""
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
        sway = sin(t * 3.2 + phase * 6.28) * 0.13 * (0.2 + 0.8 * t)
        out_off = 0.05 + 0.10 * sin(t * pi * 0.80) + 0.06 * t
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

    n_leaves = max(5, int(length * 2.0))
    for li in range(n_leaves):
        t = (li + 0.35) / float(n_leaves + 0.25)
        idx_f = t * segs
        i0 = min(segs - 1, int(idx_f))
        frac = idx_f - i0
        root = stem_pts[i0].lerp(stem_pts[i0 + 1], frac)
        sgn = -1.0 if (li % 2 == 0) else 1.0
        l_scale = (0.78 + 0.48 * sin(t * pi * 0.85)) * (1.0 - 0.30 * t)
        l_len = width * 1.48 * l_scale * rng.uniform(0.86, 1.14)
        l_wid = width * 0.62 * l_scale * rng.uniform(0.86, 1.14)
        l_dir = (side * (sgn * 0.65) + od * (0.48 + rng.uniform(-0.10, 0.16)) + Vector((0.0, -0.74, 0.0))).normalized()
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


def _add_coastal_fern_cluster(mb, root_pos, scale=0.85, n_fronds=4, rng=None, phase=0.0,
                              lean_dir=None, segs=3, c_dark=C_VINE_DARK, c_mid=C_VINE_MID, c_tip=C_VINE_SUN):
    """Broad painterly coastal fern rosette ('foliage') with UV2 wind weights."""
    rp = Vector(root_pos)
    base_rot = rng.uniform(0.0, 2.0 * pi) if rng else 0.0
    for fi in range(n_fronds):
        ang = base_rot + 2.0 * pi * fi / float(n_fronds) + (rng.uniform(-0.20, 0.20) if rng else 0.0)
        f_len = scale * (rng.uniform(0.86, 1.15) if rng else 1.0)
        f_w = scale * (rng.uniform(0.24, 0.32) if rng else 0.28)
        f_arch_h = scale * (rng.uniform(0.42, 0.56) if rng else 0.48)
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


def _sculpt_magma_ribbon(mb, path_pts, widths, surface_nrm, hot_core=True, ridge_h=0.068):
    """Surface-hugging glowing molten magma vein ridge ('glass' warm orange-gold emission!)."""
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
            t_dir = Vector((0.0, 0.0, -1.0))
        t_dir.normalize()
        side = t_dir.cross(nrm)
        if side.length < 1e-4:
            side = Vector((1.0, 0.0, 0.0))
        side.normalize()
        w = widths[i]
        left_pts.append(pts[i] - side * w - nrm * 0.012)
        right_pts.append(pts[i] + side * w - nrm * 0.012)
        mid_pts.append(pts[i] + nrm * (ridge_h + 0.012 * sin(i * 1.7)))
    for i in range(n - 1):
        c_mid = C_FLAME_CORE if (hot_core and i <= n // 2) else C_FLAME_MID
        c_edge = C_FLAME_DEEP if i < n - 2 else C_MAGMA_CRIMSON
        inside = (pts[i] + pts[i + 1]) * 0.5 - nrm * 0.5
        mb.fp([left_pts[i], mid_pts[i], mid_pts[i + 1], left_pts[i + 1]], 'glass',
              [c_edge, c_mid, c_mid, c_edge], (1, 0, 0), inside, smooth=False)
        mb.fp([mid_pts[i], right_pts[i], right_pts[i + 1], mid_pts[i + 1]], 'glass',
              [c_mid, c_edge, c_edge, c_mid], (1, 0, 0), inside, smooth=False)


# ---------------------------------------------------------------- bespoke wave-I16 prop helpers

def _build_pirate_skull_crest(mb, center, scale=1.0, yaw_deg=0.0):
    """Bold carved bone-stone pirate skull emblem facing -Z with clean rounded back cranium."""
    s = scale
    with xf(mb, T(center) @ R('Y', yaw_deg)):
        cran_prof = [
            (0.00,     -0.14 * s),
            (0.24 * s, -0.10 * s),
            (0.33 * s,  0.08 * s),
            (0.31 * s,  0.26 * s),
            (0.20 * s,  0.40 * s),
            (0.00,      0.44 * s),
        ]
        with xf(mb, S(1.00, 1.00, 0.92)):
            lathe(mb, cran_prof, 7, 'skull_stone', C_SKULL_BONE, False, False,
                  lambda i, k: C_SKULL_MID if i <= 1 else C_SKULL_BONE)
        # Bold brow ridge, cheekbones & dark recessed eye sockets facing -Z
        cbox(mb, (0.0, 0.14 * s, -0.25 * s), (0.50 * s, 0.10 * s, 0.14 * s), 'skull_stone', C_SKULL_BONE, 0.0)
        for sx in (-1.0, 1.0):
            cbox(mb, (sx * 0.21 * s, -0.02 * s, -0.23 * s), (0.14 * s, 0.14 * s, 0.14 * s),
                 'skull_stone', C_SKULL_MID, 0.0)
            cbox(mb, (sx * 0.115 * s, 0.04 * s, -0.28 * s), (0.12 * s, 0.12 * s, 0.07 * s),
                 'basalt', C_SKULL_CAV, 0.0)
        cbox(mb, (0.0, -0.04 * s, -0.285 * s), (0.075 * s, 0.095 * s, 0.06 * s), 'basalt', C_SKULL_CAV, 0.0)
        cbox(mb, (0.0, -0.17 * s, -0.16 * s), (0.35 * s, 0.16 * s, 0.22 * s), 'skull_stone', C_SKULL_MID, 0.0)
        cbox(mb, (0.0, -0.20 * s, -0.27 * s), (0.28 * s, 0.10 * s, 0.05 * s), 'basalt', C_SKULL_CAV, 0.0)
        for tx in (-0.085, 0.0, 0.085):
            cbox(mb, (tx * s, -0.20 * s, -0.29 * s), (0.052 * s, 0.095 * s, 0.042 * s),
                 'skull_stone', C_SKULL_BONE, 0.0)
        # Crimson pirate headband sash wrapping around the skull brow!
        cyl(mb, 0.325 * s, 0.19 * s, 0.27 * s, 7, 'paint', C_CRIMSON_HI, False, 0.0, 0.315 * s)


def _build_crossed_cutlass(mb, center, tilt_deg=48.0, mirror_x=1.0, scale=1.0):
    """Long sweeping forged-steel pirate cutlass with gleaming brass basket guard & leather hilt."""
    s = scale
    with xf(mb, T(center) @ R('Z', tilt_deg * mirror_x)):
        # Sweeping long curved blade extending proudly upward (+Y) well past the skull crest!
        b_pts = [
            Vector((0.00 * s,           -0.18 * s, 0.0)),
            Vector((0.03 * s * mirror_x, 0.34 * s, 0.0)),
            Vector((0.12 * s * mirror_x, 0.86 * s, 0.0)),
            Vector((0.28 * s * mirror_x, 1.32 * s, 0.0)),
        ]
        b_secs = []
        b_cols = [C_STEEL_MID, C_STEEL_BRIGHT, C_STEEL_BRIGHT, C_STEEL_BRIGHT]
        for i, p in enumerate(b_pts):
            w = (0.072 if i < 2 else (0.086 if i == 2 else 0.016)) * s
            th = 0.022 * s * (1.0 - 0.48 * (i / 3.0))
            b_secs.append([
                p + Vector((-w, 0.0, -th)),
                p + Vector(( w, 0.0,  0.0)),
                p + Vector((-w, 0.0,  th)),
                p + Vector((-w * 1.15, 0.0, 0.0)),
            ])
        loft(mb, b_secs, 'iron', C_STEEL_BRIGHT, closed=True, caps=(True, True), mode='flat', scols=b_cols)
        # Ornate brass cup-guard, knuckle bow, leather grip & pommel projecting below the cross!
        cbox(mb, (0.0, -0.20 * s, 0.0), (0.28 * s, 0.065 * s, 0.14 * s), 'brass', C_GOLD_BRIGHT, 0.0)
        cyl(mb, 0.046 * s, -0.50 * s, -0.21 * s, 5, 'timber', C_TIMBER_DARK, False, 0.0)
        cyl(mb, 0.076 * s, -0.58 * s, -0.49 * s, 5, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.052 * s)
        guard_pts = [
            ( 0.12 * s * mirror_x, -0.22 * s, 0.0),
            ( 0.18 * s * mirror_x, -0.36 * s, 0.0),
            ( 0.07 * s * mirror_x, -0.52 * s, 0.0),
        ]
        tube(mb, guard_pts, 0.024 * s, 4, 'brass', C_GOLD_BRIGHT, mode='flat')


def _build_wanted_poster(mb, center, width=0.48, height=0.60, tilt_deg=0.0, face_dir=-1.0,
                         pattern=0, rng=None):
    """Nailed weathered parchment wanted poster ('paint' mat) with crisp pirate silhouette &
    crimson wax bounty seal encoded cleanly via faceted 4x5 vertex colors!"""
    nx, ny = 4, 5
    hw, hh = width * 0.5, height * 0.5
    thick = 0.016

    def _cell_col(ix, iy):
        # Crimson wax seal stamp in bottom-right corner
        if ix == 3 and iy == 0:
            return C_CRIMSON_HI
        # Bold crimson "WANTED" header banner across top row
        if iy == 4 and ix in (1, 2):
            return C_CRIMSON_MID
        if iy == 4:
            return C_PARCHMENT_AGED
        # Central dark ink pirate silhouette (0=tricorn outlaw, 1=skull cross, 2=black brigantine)
        if pattern == 0:
            if (iy == 3 and ix in (1, 2)) or (iy == 2 and ix in (1, 2)) or (iy == 1 and ix in (1, 2)):
                return C_INK_DARK if not (iy == 1 and ix == 2) else C_CRIMSON_DARK
        elif pattern == 1:
            if (iy == 3 and ix in (1, 2)) or (iy == 2 and ix in (1, 2)) or (iy == 1 and ix == 1):
                return C_INK_DARK
        else:
            if (iy == 3 and ix == 2) or (iy == 2 and ix in (1, 2)) or (iy == 1 and ix in (1, 2)):
                return C_INK_DARK if iy >= 2 else C_TEAL_DARK
        if ix in (0, 3) or iy == 0:
            return jit(C_PARCHMENT_AGED, rng, 0.035, 0.01) if rng else C_PARCHMENT_AGED
        return jit(C_PARCHMENT_HI, rng, 0.03, 0.01) if rng else C_PARCHMENT_HI

    with xf(mb, T(center) @ R('Z', tilt_deg)):
        grid_f = [[None] * (ny + 1) for _ in range(nx + 1)]
        grid_b = [[None] * (ny + 1) for _ in range(nx + 1)]
        for ix in range(nx + 1):
            u = ix / float(nx)
            x = -hw + u * width
            for iy in range(ny + 1):
                v = iy / float(ny)
                y = -hh + v * height
                curl = (1.0 - v) ** 2.2 * (abs(u - 0.5) * 2.0) ** 1.5 * 0.044
                zf = face_dir * (thick * 0.5 + curl)
                zb = face_dir * (-thick * 0.5 + curl * 0.6)
                grid_f[ix][iy] = Vector((x, y, zf))
                grid_b[ix][iy] = Vector((x, y, zb))

        mb.newoff()
        inside_f = Vector((0.0, 0.0, -face_dir * 0.8))
        inside_b = Vector((0.0, 0.0,  face_dir * 0.8))
        for ix in range(nx):
            for iy in range(ny):
                col = _cell_col(ix, iy)
                f00, f10, f11, f01 = grid_f[ix][iy], grid_f[ix + 1][iy], grid_f[ix + 1][iy + 1], grid_f[ix][iy + 1]
                mb.fp([f00, f10, f11, f01], 'paint', col, (0, 1, 0), inside_f, smooth=False)
        mb.fp([grid_b[0][0], grid_b[nx][0], grid_b[nx][ny], grid_b[0][ny]],
              'paint', C_PARCHMENT_EDGE, (0, 1, 0), inside_b, smooth=False)
        # Forged-iron mounting tack & raised crimson wax seal boss!
        cbox(mb, (0.0, hh - 0.036, face_dir * (thick * 0.6 + 0.012)), (0.046, 0.046, 0.036), 'iron', C_IRON, 0.0)
        with xf(mb, T(hw * 0.48, -hh + 0.088, face_dir * (thick * 0.6 + 0.022)) @ M_Y2Z):
            cyl(mb, 0.048, -0.014, 0.014, 5, 'paint', C_CRIMSON_HI, False, 0.0)


def _build_hanging_fish(mb, top_pos, length=0.64, yaw_deg=0.0, tilt_deg=0.0, rng=None, smoked=False):
    """Sculpted hanging tropical sea-fish suspended by tail twine ('paint' silver-teal & 'rope')."""
    L = length
    with xf(mb, T(top_pos) @ R('Y', yaw_deg) @ R('Z', tilt_deg)):
        # Crisp taut hemp suspension cord (3-sided tube = 6 tris!)
        tube(mb, [(0.0, 0.02, 0.0), (0.0, -0.17, 0.0)], 0.012, 3, 'rope', C_ROPE, caps=(False, False), mode='flat')
        y0 = -0.16
        prof = [
            (0.00, 0.020, 0.013),
            (0.25, 0.094, 0.046),
            (0.56, 0.138, 0.062),
            (0.82, 0.106, 0.052),
            (1.00, 0.018, 0.014),
        ]
        c_back  = C_FISH_SMOKED if smoked else (jit(C_FISH_BACK, rng, 0.06, 0.02) if rng else C_FISH_BACK)
        c_side  = mul(C_FISH_SMOKED, 1.15) if smoked else (jit(C_FISH_SILVER, rng, 0.05, 0.02) if rng else C_FISH_SILVER)
        c_belly = C_OAK_FRESH if smoked else C_FISH_BELLY
        c_fin   = C_OAK_CHAR if smoked else C_FISH_FIN

        secs = []
        scols = []
        for idx, (f, hz, hx) in enumerate(prof):
            yy = y0 - f * L
            bow_x = sin(f * pi) * 0.024
            secs.append([
                Vector((bow_x,      yy, -hz)),
                Vector((bow_x + hx, yy,  0.0)),
                Vector((bow_x,      yy,  hz)),
                Vector((bow_x - hx, yy,  0.0)),
            ])
            scols.append(c_back if idx == 0 else (c_side if idx in (1, 2) else mix(c_side, c_belly, 0.48)))
        loft(mb, secs, 'paint', c_side, closed=True, caps=(True, True), mode='flat', scols=scols)
        # Coral/amber dorsal fin crest + crisp forked caudal tail fin (single faceted fin slab!)
        cbox(mb, (0.014, y0 - L * 0.46, -0.136), (0.018, L * 0.36, 0.052), 'paint', c_fin, 0.0)
        tail_secs = [
            [Vector((-0.010, y0 - 0.01, -0.024)), Vector((0.010, y0 - 0.01, -0.024)),
             Vector((0.010, y0 - 0.01,  0.024)), Vector((-0.010, y0 - 0.01,  0.024))],
            [Vector((-0.010, y0 + 0.13, -0.118)), Vector((0.010, y0 + 0.13, -0.118)),
             Vector((0.010, y0 + 0.13,  0.118)), Vector((-0.010, y0 + 0.13,  0.118))],
        ]
        loft(mb, tail_secs, 'paint', c_back, closed=True, caps=(True, True), mode='flat')


# ================================================================ 1. PIRATE BOUNTY GALLOWS POST

def gen_pirate_bounty_gallows_post(outdir):
    """Harbour outlaw bounty & trophy notice archway rooted on a stepped cobbled & stone apron
    plunging cleanly to y = -2.80 m (footprint hx ~ 2.45 m, hz ~ 2.00 m).
    Features twin weathered barnacle-crusted timber posts (~5.2 m tall) bridged by an ornate carved
    skull-and-cutlass crossbeam, hanging weathered wooden bounty plaques & nailed parchment wanted
    posters ('paint' mat w/ distinct crimson seals & pirate silhouettes via vertex color), rusted
    iron chain suspending an ornate pirate trophy lantern cage, stacked iron-banded treasure chest
    & rum kegs at the base, tattered crimson swallowtail pennant ('paint' + UV2 wind sway), coastal
    ferns ('foliage' + UV2), collider 'col_bounty_base', and warm lantern empty 'Lantern_BountyPost'.
    Target: ~3,100-3,700 visual tris, 1 collider (col_bounty_base).
    """
    clear_scene()
    rng = random.Random(SEED + 2911)
    mb = MB('PirateBountyGallowsPost', seed=2911)

    SKIRT_BOT = -2.80
    STEP_Y    =  0.06
    FLOOR_Y   =  0.24
    col_pts   = []

    # 1. Stepped Cobbled & Stone Apron Plinth plunging cleanly to y = -2.80 m (hx=2.45, hz=2.00!)
    apron_secs = [
        _rect_oct(0.0, SKIRT_BOT, 0.0, 2.58, 2.12, 0.48),
        _rect_oct(0.0, -1.05,     0.0, 2.50, 2.04, 0.44),
        _rect_oct(0.0, STEP_Y,    0.0, 2.44, 1.98, 0.40),
    ]
    _loft_horizontal_masonry(
        mb, apron_secs, 'limestone_moss',
        [C_TIDE_DARK, C_COBBLE_DARK, C_COBBLE_MID],
        rng, caps=(True, True), top_mat='limestone_moss', top_col=C_COBBLE_MID,
    )
    for ring in apron_secs:
        col_pts.extend(Vector(p) for p in ring)

    # Raised inner cobbled plinth terrace (y = STEP_Y .. FLOOR_Y) + seaward entry kerb steps
    terrace_secs = [
        _rect_oct(0.0, STEP_Y - 0.02, 0.0, 2.08, 1.56, 0.30),
        _rect_oct(0.0, FLOOR_Y,       0.0, 2.00, 1.48, 0.26),
    ]
    _loft_horizontal_masonry(
        mb, terrace_secs, 'limestone',
        [C_COBBLE_DARK, C_COBBLE_LIGHT],
        rng, caps=(False, True), top_mat='limestone', top_col=C_COBBLE_MID,
    )
    cbox(mb, (0.0, STEP_Y + 0.06, -1.72), (1.76, 0.14, 0.42), 'limestone', C_COBBLE_LIGHT, 0.0, (1, 0, 0))
    for fx, fz, fw, fd, fyaw in (
        (-0.82, -0.96, 0.64, 0.46,  4.0),
        ( 0.08, -0.88, 0.72, 0.48, -3.0),
        ( 0.92, -0.94, 0.62, 0.44,  5.0),
        (-0.18,  0.86, 0.76, 0.50, -4.0),
        ( 0.84,  0.82, 0.66, 0.44,  3.0),
    ):
        cbox(mb, (fx, FLOOR_Y + 0.015, fz), (fw, 0.04, fd), 'limestone',
             jit(C_COBBLE_LIGHT, rng, 0.06, 0.015), 0.0, (1, 0, 0), M=R('Y', fyaw))

    # 2. Twin Weathered Barnacle-Crusted Timber Posts (~5.2 m tall) with Stone Plinth Sockets!
    POST_X = 1.38
    POST_Z = 0.08
    POST_H = 5.16
    BEAM_Y = 3.92

    for sgn in (-1.0, 1.0):
        px = sgn * POST_X
        sock_secs = [
            _rect_oct(px, FLOOR_Y - 0.04, POST_Z, 0.36, 0.36, 0.08),
            _rect_oct(px, FLOOR_Y + 0.48, POST_Z, 0.28, 0.28, 0.06),
        ]
        _loft_horizontal_masonry(
            mb, sock_secs, 'temple_stone', [C_COBBLE_DARK, C_COBBLE_LIGHT],
            rng, caps=(False, True), top_mat='temple_stone', top_col=C_COBBLE_LIGHT,
        )
        p_secs = []
        p_cols = []
        for sy, sr, sx_off, sc in (
            (FLOOR_Y + 0.36, 0.22,  0.00, C_TIMBER_DARK),
            (1.60,           0.20, -sgn * 0.02, C_TIMBER_MID),
            (3.15,           0.185, 0.00, C_TIMBER_MID),
            (POST_H,         0.165, sgn * 0.02, C_TIMBER_HI),
        ):
            p_secs.append(_reg_poly(px + sx_off, sy, POST_Z, sr, sides=6, rot_deg=30.0))
            p_cols.append(jit(sc, rng, 0.05, 0.015))
        loft(mb, p_secs, 'timber', C_TIMBER_MID, closed=True, caps=(True, True), mode='flat', scols=p_cols)

        # Forged-iron reinforcement collar bands along each post
        for by, br in ((FLOOR_Y + 0.62, 0.232), (2.42, 0.208), (BEAM_Y - 0.02, 0.198)):
            with xf(mb, T(px, by, POST_Z)):
                cyl(mb, br, -0.055, 0.055, 6, 'iron', C_IRON_RUST if by < 2.0 else C_IRON, False, 0.0)
        with xf(mb, T(px + sgn * 0.02, POST_H, POST_Z)):
            cyl(mb, 0.21, 0.00, 0.12, 6, 'timber', C_TIMBER_DARK, False, 0.0, 0.15)
            cyl(mb, 0.14, 0.12, 0.28, 6, 'iron', C_IRON_FORGED, False, 0.0, 0.035)

        # Splayed heel timber buttresses bracing posts firmly into the cobbled plinth!
        for bz_dir in (-1.0, 1.0):
            _add_beam(mb,
                      (px, FLOOR_Y + 0.04, POST_Z + bz_dir * 0.88),
                      (px, FLOOR_Y + 1.18, POST_Z + bz_dir * 0.16),
                      0.14, 0.14, 'timber', C_TIMBER_DARK, 0.0)
            cbox(mb, (px, FLOOR_Y + 0.08, POST_Z + bz_dir * 0.90), (0.20, 0.16, 0.18), 'iron', C_IRON_RUST, 0.0)

        # Bold Clustered Pale Barnacle Crusts clinging to the lower weathered timber (y = 0.72 .. 1.65 m)!
        for bk in range(5):
            ang = radians(bk * 72.0 + (22.0 if sgn > 0 else 58.0))
            by = FLOOR_Y + 0.50 + (bk % 3) * 0.28 + rng.uniform(-0.04, 0.05)
            rad_p = 0.21
            bx_c = px + cos(ang) * rad_p
            bz_c = POST_Z + sin(ang) * rad_p
            n_out = Vector((cos(ang), 0.12, sin(ang))).normalized()
            rot_b = Vector((0.0, 1.0, 0.0)).rotation_difference(n_out).to_matrix().to_4x4()
            with xf(mb, T(bx_c, by, bz_c) @ rot_b):
                b_r = rng.uniform(0.058, 0.084)
                cyl(mb, b_r, -0.02, b_r * 0.82, 4, 'skull_stone',
                    C_BARNACLE_PALE if bk % 2 == 0 else C_BARNACLE_MID, False, 0.0, b_r * 0.44)

    # 3. Ornate Carved Skull-and-Cutlass Crossbeam + Projecting Gallows Jib-Arm!
    cbox(mb, (0.14, BEAM_Y, POST_Z), (4.22, 0.34, 0.32), 'timber', C_TIMBER_MID, 0.0, (1, 0, 0))
    cbox(mb, (0.00, BEAM_Y + 0.21, POST_Z), (3.46, 0.11, 0.42), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
    for sgn in (-1.0, 1.0):
        _add_beam(mb,
                  (sgn * (POST_X - 0.12), BEAM_Y - 0.92, POST_Z),
                  (sgn * (POST_X - 0.88), BEAM_Y - 0.10, POST_Z),
                  0.14, 0.16, 'timber', C_TIMBER_HI, 0.0)
        cbox(mb, (sgn * POST_X, BEAM_Y, POST_Z - 0.175), (0.36, 0.38, 0.036), 'iron', C_IRON, 0.0)
        cbox(mb, (sgn * POST_X, BEAM_Y, POST_Z + 0.175), (0.36, 0.38, 0.036), 'iron', C_IRON, 0.0)
        cbox(mb, (sgn * POST_X, BEAM_Y, POST_Z - 0.20), (0.078, 0.078, 0.03), 'brass', C_GOLD_BRIGHT, 0.0)

    # Projecting Starboard Gallows Arm (x = +1.38 .. +2.28 m, y = 4.56 m) braced by forged iron strut!
    GALLOW_Y = 4.56
    GALLOW_X = 2.08
    cbox(mb, (1.76, GALLOW_Y, POST_Z), (1.16, 0.22, 0.22), 'timber', C_TIMBER_HI, 0.0, (1, 0, 0))
    cbox(mb, (2.26, GALLOW_Y, POST_Z), (0.16, 0.27, 0.27), 'iron', C_IRON_FORGED, 0.0)
    _add_beam(mb, (POST_X + 0.12, BEAM_Y + 0.06, POST_Z), (GALLOW_X - 0.08, GALLOW_Y - 0.08, POST_Z),
              0.085, 0.085, 'iron', C_IRON_RUST, 0.0)

    # Centerpiece Carved Skull-and-Cutlass Crest mounted proudly atop the Crossbeam!
    CREST_Y = BEAM_Y + 0.58
    with xf(mb, T(0.0, CREST_Y, POST_Z + 0.04) @ M_Y2Z):
        cyl(mb, 0.50, -0.065, 0.065, 8, 'timber', C_TIMBER_DARK, False, 0.0)
        cyl(mb, 0.55, -0.045, 0.045, 8, 'iron', C_IRON_FORGED, False, 0.0)
        # Rear brass pirate-star boss on +Z side so the rear view shines cleanly!
        cyl(mb, 0.26, 0.055, 0.095, 6, 'brass', C_BRASS_WARM, False, 0.0, 0.18)
    # Long Sweeping Crossed Forged-Steel & Brass Cutlasses flaring boldly behind the skull!
    _build_crossed_cutlass(mb, (-0.16, CREST_Y - 0.18, POST_Z - 0.02), tilt_deg=48.0, mirror_x=-1.0, scale=1.22)
    _build_crossed_cutlass(mb, ( 0.16, CREST_Y - 0.18, POST_Z - 0.02), tilt_deg=48.0, mirror_x= 1.0, scale=1.22)
    # Bold Sculpted Pirate Skull Crest facing seaward (-Z)
    _build_pirate_skull_crest(mb, (0.0, CREST_Y + 0.08, POST_Z - 0.09), scale=1.02, yaw_deg=0.0)

    # 4. Hanging Weathered Wooden Bounty Plaques & Nailed Parchment Wanted Posters!
    PLQ_Y = 3.24
    for sx in (-0.82, 0.72):
        _add_chain_links(mb, (sx, BEAM_Y - 0.16, POST_Z), (sx, PLQ_Y + 0.22, POST_Z),
                         n_links=2, link_r=0.095, wire_r=0.026, segs=4, psegs=4, sag=0.0,
                         mat='iron', rust_stride=2, stretch_y=1.42)
    cbox(mb, (-0.05, PLQ_Y, POST_Z), (2.06, 0.44, 0.10), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
    for fz in (-1.0, 1.0):
        cbox(mb, (-0.05, PLQ_Y, POST_Z + fz * 0.058), (1.88, 0.30, 0.022), 'paint', C_CRIMSON_MID, 0.0)
        cbox(mb, (-0.05, PLQ_Y + 0.04, POST_Z + fz * 0.072), (1.36, 0.09, 0.018), 'paint', C_PARCHMENT_HI, 0.0)
        cbox(mb, (-0.05, PLQ_Y - 0.07, POST_Z + fz * 0.072), (0.94, 0.065, 0.018), 'brass', C_GOLD_BRIGHT, 0.0)
    # Smaller dangling outlaw tally wooden slat hanging beneath the starboard side of the plaque!
    for sx in (0.32, 0.68):
        _add_beam(mb, (sx, PLQ_Y - 0.22, POST_Z), (sx, PLQ_Y - 0.38, POST_Z), 0.024, 0.024, 'iron', C_IRON_RUST, 0.0)
    with xf(mb, T(0.50, PLQ_Y - 0.48, POST_Z) @ R('Z', -4.5)):
        cbox(mb, (0.0, 0.0, 0.0), (0.62, 0.22, 0.075), 'timber', C_TIMBER_HI, 0.0, (1, 0, 0))
        cbox(mb, (0.0, 0.0, -0.042), (0.48, 0.12, 0.016), 'paint', C_PARCHMENT_AGED, 0.0)

    # Port-Side Double-Sided Timber Bounty Notice Board Panel leaving starboard archway bay wide open!
    MULL_X = 0.34
    _add_beam(mb, (MULL_X, FLOOR_Y, POST_Z), (MULL_X, BEAM_Y - 0.16, POST_Z), 0.15, 0.15, 'timber', C_TIMBER_DARK, 0.0)
    cbox(mb, (-0.45, 2.76, POST_Z), (1.66, 0.12, 0.18), 'timber', C_TIMBER_MID, 0.0, (1, 0, 0))
    cbox(mb, (-0.45, 1.24, POST_Z), (1.66, 0.12, 0.18), 'timber', C_TIMBER_MID, 0.0, (1, 0, 0))
    for pi_idx in range(4):
        py = 1.46 + pi_idx * 0.36
        cbox(mb, (-0.45, py, POST_Z), (1.56, 0.32, 0.085), 'timber',
             jit(C_TIMBER_MID if pi_idx % 2 == 0 else C_TIMBER_HI, rng, 0.06, 0.015), 0.0, (1, 0, 0))

    # Nailed Parchment Wanted Posters with Crimson Seals & Pirate Silhouettes (front -Z, rear +Z & post!)
    _build_wanted_poster(mb, (-0.86, 2.26, POST_Z - 0.056), width=0.52, height=0.64, tilt_deg= 4.5, face_dir=-1.0, pattern=0, rng=rng)
    _build_wanted_poster(mb, (-0.16, 2.18, POST_Z - 0.056), width=0.48, height=0.60, tilt_deg=-5.2, face_dir=-1.0, pattern=1, rng=rng)
    _build_wanted_poster(mb, (-0.52, 1.56, POST_Z - 0.064), width=0.54, height=0.48, tilt_deg= 2.6, face_dir=-1.0, pattern=2, rng=rng)
    _build_wanted_poster(mb, (-0.76, 2.14, POST_Z + 0.056), width=0.50, height=0.62, tilt_deg=-3.8, face_dir= 1.0, pattern=1, rng=rng)
    _build_wanted_poster(mb, (-0.10, 1.84, POST_Z + 0.056), width=0.48, height=0.58, tilt_deg= 5.0, face_dir= 1.0, pattern=0, rng=rng)
    # Extra wanted poster tacked boldly to the seaward face of the starboard timber post + pinned iron dagger!
    _build_wanted_poster(mb, (POST_X, 2.02, POST_Z - 0.205), width=0.40, height=0.50, tilt_deg=-6.0, face_dir=-1.0, pattern=2, rng=rng)
    with xf(mb, T(POST_X + 0.08, 2.18, POST_Z - 0.26) @ R('X', 68.0) @ R('Z', -16.0)):
        cbox(mb, (0.0, 0.08, 0.0), (0.032, 0.18, 0.014), 'iron', C_STEEL_BRIGHT, 0.0)
        cbox(mb, (0.0, -0.02, 0.0), (0.11, 0.026, 0.028), 'brass', C_GOLD_BRIGHT, 0.0)
        cbox(mb, (0.0, -0.09, 0.0), (0.034, 0.13, 0.034), 'timber', C_TIMBER_DARK, 0.0)

    # 5. Rusted Iron Chain Suspending Ornate Pirate Trophy Lantern Cage from the Gallows Arm!
    CHAIN_TOP   = Vector((GALLOW_X, GALLOW_Y - 0.11, POST_Z))
    CAGE_TOP    = Vector((GALLOW_X, 3.36, POST_Z))
    LANTERN_POS = Vector((GALLOW_X, 2.84, POST_Z))
    _add_chain_links(mb, CHAIN_TOP, CAGE_TOP, n_links=6, link_r=0.125, wire_r=0.036,
                     segs=4, psegs=4, sag=0.0, mat='iron', rust_stride=2, stretch_y=1.45,
                     col_a=C_IRON, col_b=C_IRON_RUST)
    # Ornate Pirate Trophy Lantern Cage (forged-iron bowed ribs + brass crown/waist + warm glowing glass core!)
    with xf(mb, T(LANTERN_POS)):
        with xf(mb, T(0.0, 0.50, 0.0) @ M_Y2Z):
            torus(mb, 0.085, 0.024, 5, 4, 'iron', C_IRON_RUST, False)
        cyl(mb, 0.34, 0.30, 0.44, 6, 'iron', C_IRON, False, 0.0, 0.09)
        cyl(mb, 0.36, 0.26, 0.31, 6, 'brass', C_GOLD_BRIGHT, False, 0.0)
        cyl(mb, 0.30, -0.38, -0.28, 6, 'iron', C_IRON_RUST, False, 0.0, 0.34)
        cyl(mb, 0.14, -0.52, -0.38, 6, 'iron', C_IRON, False, 0.0, 0.28)
        cyl(mb, 0.04, -0.66, -0.52, 5, 'brass', C_BRASS_WARM, False, 0.0, 0.11)
        for rk in range(4):
            ang = radians(rk * 90.0 + 45.0)
            ca, sa = cos(ang), sin(ang)
            rib_p = [
                (ca * 0.31, -0.30, sa * 0.31),
                (ca * 0.38,  0.00, sa * 0.38),
                (ca * 0.33,  0.29, sa * 0.33),
            ]
            tube(mb, rib_p, 0.028, 4, 'iron', C_IRON_FORGED if rk % 2 == 0 else C_IRON_RUST, mode='flat')
        with xf(mb, T(0.0, -0.02, 0.0)):
            torus(mb, 0.38, 0.022, 6, 4, 'brass', C_BRASS_WARM, False)
        cyl(mb, 0.22, -0.24, 0.24, 6, 'glass', C_LANTERN_GL, False, 0.0, 0.25)

    # 6. Tattered Crimson Swallowtail Pennant ('paint' + UV2 Wind Sway!) on Port Post Flagstaff!
    POLE_X, POLE_Z = -POST_X - 0.02, POST_Z
    _add_beam(mb, (POLE_X, POST_H + 0.14, POLE_Z), (POLE_X, POST_H + 1.06, POLE_Z), 0.056, 0.056, 'timber', C_TIMBER_DARK, 0.0)
    with xf(mb, T(POLE_X, POST_H + 1.12, POLE_Z)):
        cyl(mb, 0.068, -0.04, 0.08, 5, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.018)
    pnu, pnv = 5, 3
    p_len, p_h0 = 1.56, 0.58
    p_top_y = POST_H + 1.00
    p_thick = 0.018
    p_phase = 0.33

    def _pen_pt(u, v):
        taper = 1.0 - 0.40 * u
        notch_push = 0.28 * (1.0 - abs(v - 0.5) * 2.0) * (u ** 3.0)
        uu = max(0.0, u - notch_push)
        x = POLE_X - 0.04 - uu * p_len
        droop = -0.16 * (uu ** 1.55)
        y = p_top_y - 0.5 * p_h0 + (v - 0.5) * p_h0 * taper + droop
        wave = sin(uu * pi * 2.4 + v * 0.7) * 0.14 * (uu ** 1.15)
        z = POLE_Z - 0.04 * uu + wave
        return Vector((x, y, z))

    pf_g = [[None] * (pnv + 1) for _ in range(pnu + 1)]
    pb_g = [[None] * (pnv + 1) for _ in range(pnu + 1)]
    pw_g = [[0.0]  * (pnv + 1) for _ in range(pnu + 1)]
    for iu in range(pnu + 1):
        u = iu / float(pnu)
        for iv in range(pnv + 1):
            v = iv / float(pnv)
            p = _pen_pt(u, v)
            pf_g[iu][iv] = p + Vector((0.0, 0.0, -p_thick * 0.5))
            pb_g[iu][iv] = p + Vector((0.0, 0.0,  p_thick * 0.5))
            pw_g[iu][iv] = min(0.95, (u ** 1.25) * 0.94)

    mb.newoff()
    for iu in range(pnu):
        for iv in range(pnv):
            if iu == 0:
                cf = C_GOLD_BRIGHT
            elif iu == pnu - 1 and iv == 1:
                cf = C_CRIMSON_DARK
            elif iu == 2 and iv == 1:
                cf = C_PARCHMENT_HI
            else:
                cf = C_CRIMSON_HI if (iu + iv) % 2 == 0 else C_CRIMSON_MID
            cb = mul(cf, 0.86)
            f00, f10, f11, f01 = pf_g[iu][iv], pf_g[iu + 1][iv], pf_g[iu + 1][iv + 1], pf_g[iu][iv + 1]
            b00, b10, b11, b01 = pb_g[iu][iv], pb_g[iu + 1][iv], pb_g[iu + 1][iv + 1], pb_g[iu][iv + 1]
            u00 = (pw_g[iu][iv], p_phase)
            u10 = (pw_g[iu + 1][iv], p_phase)
            u11 = (pw_g[iu + 1][iv + 1], p_phase)
            u01 = (pw_g[iu][iv + 1], p_phase)
            ctr = (f00 + f11 + b00 + b11) * 0.25
            mb.fp([f00, f10, f11, f01], 'paint', cf, (1, 0, 0), ctr + Vector((0.0, 0.0, 1.0)),
                  smooth=False, uv2=[u00, u10, u11, u01])
            mb.fp([b00, b01, b11, b10], 'paint', cb, (1, 0, 0), ctr - Vector((0.0, 0.0, 1.0)),
                  smooth=False, uv2=[u00, u01, u11, u10])

    # 7. Stacked Iron-Banded Treasure Chest & Rum Kegs at the Base + Coiled Rope & Coastal Ferns!
    _build_treasure_chest(mb, T(-0.76, FLOOR_Y, -0.74) @ R('Y', 16.0), size=(0.94, 0.44, 0.56), open_deg=0.0)
    # Upright crimson-banded rum keg on starboard-front + smaller keg stacked/nestled cleanly beside it!
    _build_coopered_cask(
        mb, T(0.96, FLOOR_Y + 0.39, -0.82),
        radius=0.31, height=0.78, rng=rng,
        col_a=C_TIMBER_MID, col_b=C_TIMBER_HI, col_head=C_TIMBER_DARK,
        segs=6, stripe_col=C_CRIMSON_HI,
    )
    _build_coopered_cask(
        mb, T(-1.38, FLOOR_Y + 0.34, 0.90),
        radius=0.28, height=0.68, rng=rng,
        col_a=C_TIMBER_DARK, col_b=C_TIMBER_MID, col_head=C_OAK_CHAR,
        segs=6, stripe_col=C_TEAL_BRIGHT,
    )
    # Small rum keg resting neatly on its side at starboard-front cobbles (zero buttress clipping!)
    _build_coopered_cask(
        mb, T(1.56, FLOOR_Y + 0.24, -1.02) @ R('Y', -32.0) @ M_Y2X,
        radius=0.23, height=0.56, rng=rng,
        col_a=C_OAK_FRESH, col_b=C_TIMBER_MID, col_head=C_TIMBER_DARK,
        segs=6, stripe_col=C_CRIMSON_MID,
    )
    _build_rope_coil_lean(mb, (0.28, FLOOR_Y, -0.98), radius=0.26, turns=2, r=0.036, segs=6, psegs=4)

    # Coastal Ferns ('foliage' + UV2) tucked around the stepped mossy stone apron corners!
    for fpos, fsc, flean, fph in (
        ((-2.06, STEP_Y + 0.02, -1.32), 0.78, (-0.7, 0.0, -0.7), 0.14),
        (( 2.04, STEP_Y + 0.02, -1.28), 0.74, ( 0.7, 0.0, -0.7), 0.42),
        (( 1.98, STEP_Y + 0.02,  1.26), 0.82, ( 0.7, 0.0,  0.7), 0.68),
        ((-2.02, STEP_Y + 0.02,  1.28), 0.76, (-0.7, 0.0,  0.7), 0.91),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=3, rng=rng, phase=fph, lean_dir=flean, segs=2)

    build(mb)

    add_empty('Lantern_BountyPost', LANTERN_POS)
    col_piece('col_bounty_base', col_pts)
    export_landmark_glb(outdir, 'pirate_bounty_gallows_post.glb')


# ================================================================ 2. ANCIENT KRAKEN STONE FOUNTAIN

def gen_ancient_kraken_stone_fountain(outdir):
    """Overgrown carved temple-stone Kraken water-shrine rooted on a stepped octagonal mossy reef
    plinth plunging cleanly to y = -3.40 m (radius ~ 2.55 m).
    Features 4 dramatic sculpted curling carved temple-stone Kraken tentacles (~5.6 m tall, lined
    with relief sucker discs!) arching upward around a central carved stone lotus basin brimming
    with luminous glowing turquoise tidal water ('skull_glow' aqua core + glowing pouring stone
    spout!), weathered golden-brass trident collar, draping jungle vines & coastal ferns ('foliage'
    + UV2), collider 'col_kraken_base', and 'Lantern_KrakenShrine' empty directly over the luminous
    turquoise water basin.
    Target: ~3,100-3,700 visual tris, 1 collider (col_kraken_base).
    """
    clear_scene()
    rng = random.Random(SEED + 2923)
    mb = MB('AncientKrakenStoneFountain', seed=2923)

    SKIRT_BOT = -3.40
    TIER1_Y   =  0.20
    TIER2_Y   =  0.66
    BASIN_Y   =  1.48
    col_pts   = []

    # 1. Stepped Octagonal Mossy Reef Plinth plunging cleanly to y = -3.40 m (radius ~ 2.55 m!)
    reef_secs = [
        _reg_poly(0.0, SKIRT_BOT, 0.0, 2.72, sides=8, rot_deg=22.5),
        _reg_poly(0.0, -1.60,     0.0, 2.62, sides=8, rot_deg=22.5),
        _reg_poly(0.0, -0.35,     0.0, 2.50, sides=8, rot_deg=22.5),
        _reg_poly(0.0, TIER1_Y,   0.0, 2.38, sides=8, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, reef_secs, 'limestone_moss',
        [C_TIDE_DARK, C_LIME_SHADE, C_LIME_MID, C_LIME_WARM],
        rng, caps=(True, True), top_mat='limestone_moss', top_col=C_LIME_MID,
    )
    for ring in reef_secs:
        col_pts.extend(Vector(p) for p in ring)

    # 4 Sculpted Mossy Limestone Reef Buttress Rocks hugging the octagonal skirt
    for ang_d, rad_xy, rr, ry in (
        ( 45.0, 1.98, (0.94, 1.15, 0.88), -0.60),
        (135.0, 2.02, (0.90, 1.20, 0.92), -0.58),
        (225.0, 1.96, (0.92, 1.12, 0.86), -0.62),
        (315.0, 2.00, (0.96, 1.18, 0.90), -0.60),
    ):
        ang = radians(ang_d)
        sculpt_rock_mass(
            mb, (cos(ang) * rad_xy, ry, sin(ang) * rad_xy), rr,
            'limestone_moss', C_LIME_WARM, C_LIME_MID, C_TIDE_DARK, rng,
            subdiv=1, warp=0.22, strata=0.14, flat_top=0.45, base_flare=0.14,
            rot_deg=(0.0, ang_d, 0.0), moss_cap=0.58,
        )

    # 2. Stepped Octagonal Temple-Stone Shrine Terrace & Seaward Ceremonial Steps
    tier2_secs = [
        _reg_poly(0.0, TIER1_Y - 0.04, 0.0, 1.98, sides=8, rot_deg=22.5),
        _reg_poly(0.0, TIER2_Y,        0.0, 1.86, sides=8, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, tier2_secs, 'temple_stone', [C_KRAKEN_STONE_DK, C_KRAKEN_STONE_MID],
        rng, caps=(False, True), top_mat='temple_stone', top_col=C_KRAKEN_STONE_HI,
    )
    for si, (sy, sz, sw, sd) in enumerate((
        (TIER1_Y + 0.14, -2.14, 1.32, 0.42),
        (TIER1_Y + 0.36, -1.86, 1.16, 0.38),
    )):
        cbox(mb, (0.0, sy, sz), (sw, 0.24, sd), 'temple_stone',
             jit(C_KRAKEN_STONE_HI if si == 0 else C_KRAKEN_STONE_MID, rng, 0.05), 0.0, (1, 0, 0))

    # Shallow seaward overflow catch-pool inset at foot of the lotus basin!
    with xf(mb, T(0.0, TIER2_Y, -1.36)):
        cyl(mb, 0.48, -0.02, 0.16, 8, 'temple_stone', C_KRAKEN_STONE_MID, False, 0.0, 0.52)
        cyl(mb, 0.38,  0.04, 0.17, 8, 'skull_glow', C_AQUA_MID, False, 0.0)

    # 3. Central Carved Stone Lotus Basin, Weathered Golden-Brass Trident Collar & Luminous Turquoise Water!
    basin_prof = [
        (0.00, TIER2_Y - 0.04),
        (0.92, TIER2_Y - 0.04),
        (0.68, TIER2_Y + 0.34),
        (0.76, TIER2_Y + 0.50),
        (1.26, BASIN_Y - 0.06),
        (1.36, BASIN_Y + 0.10),
        (1.12, BASIN_Y + 0.12),
        (1.04, BASIN_Y - 0.08),
        (0.00, BASIN_Y - 0.12),
    ]
    lathe(mb, basin_prof, 8, 'temple_stone', C_KRAKEN_STONE_MID, False, False,
          lambda i, k: C_KRAKEN_STONE_HI if i in (4, 5, 6) else (C_KRAKEN_STONE_DK if i <= 2 else C_KRAKEN_STONE_MID))

    # 8 Sculpted Flaring Carved Stone Lotus Petals cupping the exterior of the fountain basin!
    for pk in range(8):
        ang = radians(pk * 45.0 + 22.5)
        with xf(mb, R('Y', -degrees(ang))):
            petal_secs = [
                [Vector((0.68, TIER2_Y + 0.28, -0.28)), Vector((0.78, TIER2_Y + 0.28, 0.0)), Vector((0.68, TIER2_Y + 0.28, 0.28)), Vector((0.58, TIER2_Y + 0.28, 0.0))],
                [Vector((1.08, TIER2_Y + 0.64, -0.36)), Vector((1.28, TIER2_Y + 0.64, 0.0)), Vector((1.08, TIER2_Y + 0.64, 0.36)), Vector((0.92, TIER2_Y + 0.64, 0.0))],
                [Vector((1.30, BASIN_Y + 0.20, -0.19)), Vector((1.50, BASIN_Y + 0.26, 0.0)), Vector((1.30, BASIN_Y + 0.20, 0.19)), Vector((1.18, BASIN_Y + 0.14, 0.0))],
            ]
            loft(mb, petal_secs, 'temple_stone',
                 jit(C_KRAKEN_STONE_HI if pk % 2 == 0 else C_KRAKEN_STONE_MID, rng, 0.04),
                 closed=True, caps=(True, True), mode='flat')

    # Weathered Golden-Brass Trident Collar clasping the lotus pedestal waist + 4 Trident Relief Crests!
    COLLAR_Y = TIER2_Y + 0.42
    cyl(mb, 0.79, COLLAR_Y - 0.09, COLLAR_Y + 0.09, 8, 'brass', C_BRASS_WARM, False, 0.0, 0.81)
    with xf(mb, T(0.0, COLLAR_Y + 0.09, 0.0)):
        torus(mb, 0.80, 0.038, 8, 4, 'brass', C_GOLD_BRIGHT, False)
    with xf(mb, T(0.0, COLLAR_Y - 0.09, 0.0)):
        torus(mb, 0.78, 0.036, 8, 4, 'brass', C_VERDIGRIS_MID, False)
    for tk in range(4):
        ang = radians(tk * 90.0)
        with xf(mb, R('Y', -degrees(ang)) @ T(0.0, COLLAR_Y + 0.04, -0.83)):
            cbox(mb, (0.0, -0.06, 0.0), (0.36, 0.055, 0.068), 'brass', C_BRASS_WARM, 0.0)
            cbox(mb, (0.0,  0.14, 0.0), (0.058, 0.44, 0.058), 'brass', C_GOLD_BRIGHT, 0.0)
            for sx in (-0.15, 0.15):
                cbox(mb, (sx, 0.09, 0.0), (0.048, 0.30, 0.052), 'brass', C_GOLD_BRIGHT, 0.0, M=R('Z', -sx * 65.0))

    # Luminous Glowing Turquoise Tidal Water Surface ('skull_glow' ONLY on this landmark!)
    water_prof = [
        (0.00, BASIN_Y + 0.06),
        (0.42, BASIN_Y + 0.02),
        (0.76, BASIN_Y + 0.05),
        (1.08, BASIN_Y + 0.01),
    ]
    lathe(mb, water_prof, 8, 'skull_glow', C_AQUA_MID, False, False,
          lambda i, k: C_AQUA_CORE if i <= 1 else (C_AQUA_MID if i == 2 else C_AQUA_DEEP))

    # Central Carved Kraken Head & Pouring Spout Pillar rising inside the lotus basin!
    SPOUT_BASE_Y = BASIN_Y - 0.06
    pillar_secs = [
        _reg_poly(0.0, SPOUT_BASE_Y,        0.0, 0.44, sides=6, rot_deg=30.0),
        _reg_poly(0.0, SPOUT_BASE_Y + 0.56, 0.0, 0.36, sides=6, rot_deg=30.0),
        _reg_poly(0.0, SPOUT_BASE_Y + 1.06, 0.0, 0.42, sides=6, rot_deg=30.0),
        _reg_poly(0.0, SPOUT_BASE_Y + 1.44, 0.0, 0.24, sides=6, rot_deg=30.0),
    ]
    _loft_horizontal_masonry(
        mb, pillar_secs, 'temple_stone',
        [C_KRAKEN_STONE_DK, C_KRAKEN_STONE_MID, C_KRAKEN_STONE_HI, C_KRAKEN_STONE_HI],
        rng, caps=(False, True), top_mat='temple_stone', top_col=C_KRAKEN_STONE_HI,
    )
    HEAD_Y = SPOUT_BASE_Y + 0.96
    with xf(mb, T(0.0, HEAD_Y + 0.46, 0.0)):
        cyl(mb, 0.29, -0.05, 0.06, 6, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.25)
        cbox(mb, (0.0, 0.14, 0.0), (0.48, 0.068, 0.068), 'brass', C_BRASS_WARM, 0.0)
        cyl(mb, 0.048, 0.04, 0.72, 5, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.012)
        for sx in (-0.22, 0.22):
            _add_beam(mb, (sx, 0.14, 0.0), (sx * 1.12, 0.56, 0.0), 0.048, 0.048, 'brass', C_GOLD_BRIGHT, 0.0)
    for sx in (-1.0, 1.0):
        cbox(mb, (sx * 0.25, HEAD_Y + 0.12, -0.27), (0.14, 0.08, 0.12), 'temple_stone', C_KRAKEN_STONE_HI, 0.0, M=R('Y', -sx * 24.0))
        cbox(mb, (sx * 0.22, HEAD_Y + 0.04, -0.34), (0.12, 0.090, 0.078), 'skull_glow', C_AQUA_CORE, 0.0, M=R('Y', -sx * 24.0))
    cbox(mb, (0.0, HEAD_Y - 0.18, -0.46), (0.30, 0.22, 0.42), 'temple_stone', C_KRAKEN_STONE_HI, 0.0)
    cbox(mb, (0.0, HEAD_Y - 0.15, -0.68), (0.25, 0.14, 0.06), 'brass', C_VERDIGRIS_HI, 0.0)
    jet_pts = [
        (0.0, HEAD_Y - 0.17, -0.62),
        (0.0, HEAD_Y - 0.26, -0.80),
        (0.0, HEAD_Y - 0.54, -0.90),
        (0.0, BASIN_Y + 0.03, -0.84),
    ]
    tube(mb, jet_pts, [0.090, 0.078, 0.070, 0.108], 6, 'skull_glow', C_AQUA_CORE, mode='flat',
         scols=[C_AQUA_CORE, C_AQUA_CORE, C_AQUA_MID, C_AQUA_CORE])
    with xf(mb, T(0.0, BASIN_Y + 0.06, -0.84)):
        torus(mb, 0.18, 0.036, 6, 4, 'skull_glow', C_AQUA_CORE, False)
    spill_pts = [
        (0.0, BASIN_Y + 0.06, -1.16),
        (0.0, BASIN_Y - 0.06, -1.36),
        (0.0, TIER2_Y + 0.44, -1.42),
        (0.0, TIER2_Y + 0.14, -1.38),
    ]
    tube(mb, spill_pts, [0.11, 0.088, 0.074, 0.118], 5, 'skull_glow', C_AQUA_MID, mode='flat',
         scols=[C_AQUA_MID, C_AQUA_CORE, C_AQUA_MID, C_AQUA_CORE])

    # 4. Four Dramatic Sculpted Curling Carved Temple-Stone Kraken Tentacles (~5.6 m tall, lined with relief sucker discs!)
    #    Wide theatrical framing around -Z seaward view (unobstructed view of the lotus basin & pouring spout!)
    tentacle_specs = [
        # (azimuth_deg, peak_h, flare_out, curl_rad, twist_deg, vine_phase)
        (-152.0, 5.46, 2.24, 0.52,  10.0, 0.12),  # port-front (flares cleanly left of seaward steps!)
        ( -28.0, 5.18, 2.18, 0.50, -12.0, 0.37),  # starboard-front (flares cleanly right!)
        ( 138.0, 5.66, 2.26, 0.54, -10.0, 0.63),  # port-rear (towering spire!)
        (  42.0, 5.36, 2.20, 0.50,  12.0, 0.88),  # starboard-rear
    ]
    for tidx, (az_d, peak_h, flare_out, curl_rad, twist_d, v_ph) in enumerate(tentacle_specs):
        az = radians(az_d)
        r_dir = Vector((cos(az), 0.0, sin(az)))
        t_dir = Vector((-sin(az), 0.0, cos(az)))
        root_r = 1.54

        # Silky-smooth 11-point C1-continuous sweeping Kraken tentacle curl (zero elbow kinks!)
        n_seg = 11
        path_pts = []
        rads = []
        t_cols = []
        # Smooth upward arch (0..7) seamlessly transitioning into an inward spiral tip (7..10)!
        arch_top_y = peak_h - curl_rad
        arch_top_r = 1.38
        for si in range(n_seg):
            u = si / float(n_seg - 1)
            if u <= 0.65:
                u1 = u / 0.65
                # Smooth belly outward then gently curving back toward arch_top_r with vertical tangent at u1=1
                belly = sin(u1 * pi) * (flare_out - root_r + 0.16)
                rad_d = root_r * (1.0 - smooth01(u1)) + (arch_top_r + curl_rad) * smooth01(u1) + belly * 0.68
                yy = (TIER2_Y - 0.08) + (arch_top_y - (TIER2_Y - 0.08)) * sin(u1 * pi * 0.5)
            else:
                # Smooth 210-degree inward polar spiral curl around center (arch_top_r, arch_top_y)!
                u2 = (u - 0.65) / 0.35
                theta = u2 * radians(205.0)  # 0 (outermost) -> 90 (peak_h!) -> 205 (curled inward & down!)
                r_sp = curl_rad * (1.0 - 0.38 * u2)
                rad_d = arch_top_r + cos(theta) * r_sp
                yy = arch_top_y + sin(theta) * r_sp
            sway_t = sin(u * pi * 1.15) * radians(twist_d) * 0.90
            pt = r_dir * rad_d + t_dir * sway_t + Vector((0.0, yy, 0.0))
            path_pts.append(pt)
            rads.append(0.39 * ((1.0 - 0.84 * u) ** 0.88))
            c_t = mix(C_KRAKEN_STONE_DK, C_KRAKEN_STONE_HI, smooth01(u * 1.10))
            if si <= 1:
                c_t = mix(c_t, C_LEDGE_MOSS, 0.20)
            t_cols.append(jit(c_t, rng, 0.04, 0.014))

        tube(mb, path_pts, rads, 6, 'temple_stone', C_KRAKEN_STONE_MID, caps=(True, True), mode='flat', scols=t_cols)

        # Heavy Weathered Golden-Brass & Verdigris Root Collar Cuff binding tentacle onto altar deck!
        c_pos = path_pts[0].lerp(path_pts[1], 0.55)
        c_tan = (path_pts[1] - path_pts[0]).normalized()
        c_rot = Vector((0.0, 1.0, 0.0)).rotation_difference(c_tan).to_matrix().to_4x4()
        with xf(mb, T(c_pos) @ c_rot):
            cyl(mb, 0.44, -0.10, 0.10, 6, 'brass', C_BRASS_WARM if tidx % 2 == 0 else C_VERDIGRIS_MID, False, 0.0, 0.41)
            with xf(mb, T(0.0, 0.09, 0.0)):
                torus(mb, 0.42, 0.034, 6, 4, 'brass', C_GOLD_BRIGHT, False)

        # Bold Sculpted Pale Relief Sucker Discs lining the inner concave arch of every Kraken tentacle!
        for sk in range(1, n_seg - 3):
            p_c = path_pts[sk]
            p_prev = path_pts[sk - 1]
            p_next = path_pts[sk + 1]
            tang = (p_next - p_prev).normalized()
            to_in = Vector((-p_c.x, 0.0, -p_c.z))
            to_in = to_in - tang * to_in.dot(tang)
            if to_in.length < 1e-4:
                to_in = -r_dir
            to_in.normalize()
            lat = tang.cross(to_in).normalized()
            r_body = rads[sk]
            s_rad = max(0.062, r_body * 0.44)
            rot_s = Vector((0.0, 1.0, 0.0)).rotation_difference(to_in).to_matrix().to_4x4()
            for side_sgn in (-1.0, 1.0):
                s_off = p_c + to_in * (r_body * 0.90) + lat * (side_sgn * r_body * 0.42) + tang * (side_sgn * 0.05)
                with xf(mb, T(s_off) @ rot_s):
                    cyl(mb, s_rad, -0.025, s_rad * 0.56, 5, 'skull_stone',
                        C_SKULL_BONE if sk % 2 == 0 else C_LIME_PALE, False, 0.0, s_rad * 0.74)

        # Draping Jungle Vines ('foliage' + UV2) hanging gracefully from the curling upper arches!
        v_anchor = path_pts[6] + r_dir * (rads[6] * 0.55)
        _add_leafy_vine_drape(mb, v_anchor, length=2.05 + (tidx % 2) * 0.40, width=0.22,
                              out_dir=(r_dir.x, 0.0, r_dir.z), rng=rng, phase=v_ph)
        v_anchor2 = path_pts[3] + t_dir * (rads[3] * 0.88)
        _add_leafy_vine_drape(mb, v_anchor2, length=1.30, width=0.18,
                              out_dir=(t_dir.x, 0.0, t_dir.z), rng=rng, phase=(v_ph + 0.24) % 1.0)

    # 5. Coastal Ferns ('foliage' + UV2) tucked around the mossy reef apron & shrine steps!
    for fpos, fsc, flean, fph in (
        ((-1.62, TIER1_Y + 0.02, -1.66), 0.82, (-0.7, 0.0, -0.7), 0.11),
        (( 1.64, TIER1_Y + 0.02, -1.62), 0.80, ( 0.7, 0.0, -0.7), 0.36),
        ((-1.98, TIER1_Y + 0.02,  1.24), 0.86, (-0.8, 0.0,  0.6), 0.62),
        (( 1.94, TIER1_Y + 0.02,  1.28), 0.84, ( 0.8, 0.0,  0.6), 0.87),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=4, rng=rng, phase=fph, lean_dir=flean)

    # Lantern_KrakenShrine empty directly over the luminous turquoise water basin!
    LANTERN_POS = Vector((0.0, BASIN_Y + 0.36, -0.44))

    build(mb)

    add_empty('Lantern_KrakenShrine', LANTERN_POS)
    col_piece('col_kraken_base', col_pts)
    export_landmark_glb(outdir, 'ancient_kraken_stone_fountain.glb')


# ================================================================ 3. COASTAL SALTED FISH DRYING RACK

def gen_coastal_salted_fish_drying_rack(outdir):
    """Living pirate fishing-cove smoke & drying station grounded on a driftwood-and-pebble shore
    apron plunging cleanly to y = -2.80 m (footprint hx ~ 2.55 m, hz ~ 2.15 m).
    Features dual lashed driftwood A-frame drying racks strung with rows of hanging sculpted
    silver-teal tropical fish & draped knotted hemp fishing net ('rope' + UV2 gentle breeze sway!),
    low stone fish-smoking hearth glowing with warm amber embers ('glass' molten colors), oak brine
    barrels, woven wicker lobster-trap creels, upturned wooden boat oar, coastal tuft ferns ('foliage'
    + UV2), collider 'col_fishrack_base', and hanging brass storm lantern empty 'Lantern_FishRack'.
    Target: ~3,100-3,700 visual tris, 1 collider (col_fishrack_base).
    """
    clear_scene()
    rng = random.Random(SEED + 2939)
    mb = MB('CoastalSaltedFishDryingRack', seed=2939)

    SKIRT_BOT = -2.80
    STEP_Y    =  0.05
    FLOOR_Y   =  0.22
    col_pts   = []

    # 1. Driftwood-and-Pebble Shore Apron plunging cleanly to y = -2.80 m (hx=2.55, hz=2.15!)
    apron_secs = [
        _rect_oct(0.0, SKIRT_BOT, 0.0, 2.68, 2.26, 0.56),
        _rect_oct(0.0, -1.05,     0.0, 2.60, 2.20, 0.52),
        _rect_oct(0.0, STEP_Y,    0.0, 2.54, 2.14, 0.48),
    ]
    _loft_horizontal_masonry(
        mb, apron_secs, 'limestone_moss',
        [C_TIDE_DARK, C_PEBBLE_WET, C_SAND_OCHRE],
        rng, caps=(True, True), top_mat='limestone', top_col=C_SAND_WARM,
    )
    for ring in apron_secs:
        col_pts.extend(Vector(p) for p in ring)

    pad_secs = [
        _rect_oct(0.0, STEP_Y - 0.02, 0.0, 2.26, 1.82, 0.42),
        _rect_oct(0.0, FLOOR_Y,       0.0, 2.18, 1.74, 0.38),
    ]
    _loft_horizontal_masonry(
        mb, pad_secs, 'limestone', [C_SAND_OCHRE, C_SAND_WARM],
        rng, caps=(False, True), top_mat='limestone', top_col=C_SAND_PALE,
    )
    for p0, p1 in (
        ((-1.86, FLOOR_Y + 0.02, -1.72), ( 0.42, FLOOR_Y + 0.02, -1.76)),
        (( 0.68, FLOOR_Y + 0.02, -1.74), ( 1.88, FLOOR_Y + 0.02, -1.58)),
        ((-2.16, FLOOR_Y + 0.02, -1.24), (-2.12, FLOOR_Y + 0.02,  1.28)),
        (( 2.14, FLOOR_Y + 0.02, -1.12), ( 2.08, FLOOR_Y + 0.02,  1.32)),
    ):
        tube(mb, [p0, ((p0[0] + p1[0]) * 0.5, FLOOR_Y + 0.05, (p0[2] + p1[2]) * 0.5), p1],
             [0.105, 0.115, 0.098], 5, 'timber', C_DRIFT_PALE, mode='flat')
    for px, pz, pr in (
        (-2.14, -1.68, 0.24), (-0.92, -1.86, 0.21), (0.58, -1.88, 0.22),
        ( 2.06, -1.64, 0.25), ( 2.24,  0.54, 0.23),
    ):
        with xf(mb, T(px, STEP_Y + 0.04, pz) @ S(1.2, 0.55, 0.95) @ R('Y', rng.uniform(0, 180))):
            cyl(mb, pr, -0.06, pr * 0.85, 5, 'limestone', jit(C_PEBBLE_WET, rng, 0.08), False, 0.0, pr * 0.65)

    # 2. Dual Lashed Driftwood A-Frame Drying Racks!
    def _build_aframe_rack(M_rack, span_x, peak_h, spread_z, lower_bar_y=None, lantern_arm=False):
        hx = span_x * 0.5
        hz = spread_z * 0.5
        with xf(mb, M_rack):
            for sgn in (-1.0, 1.0):
                rx = sgn * hx
                p_f_bot = Vector((rx, -0.04, -hz))
                p_f_top = Vector((rx, peak_h + 0.34,  0.16))
                p_r_bot = Vector((rx, -0.04,  hz))
                p_r_top = Vector((rx, peak_h + 0.34, -0.16))
                tube(mb, [p_f_bot, p_f_bot.lerp(p_f_top, 0.5) + Vector((sgn * 0.03, 0.0, 0.0)), p_f_top],
                     [0.095, 0.082, 0.068], 5, 'timber', C_DRIFT_MID, mode='flat')
                tube(mb, [p_r_bot, p_r_bot.lerp(p_r_top, 0.5) - Vector((sgn * 0.03, 0.0, 0.0)), p_r_top],
                     [0.095, 0.082, 0.068], 5, 'timber', C_DRIFT_SHADE, mode='flat')
                _add_beam(mb, (rx, peak_h * 0.40, -hz * 0.62), (rx, peak_h * 0.40, hz * 0.62),
                          0.085, 0.085, 'timber', C_DRIFT_PALE, 0.0)
                with xf(mb, T(rx, peak_h, 0.0) @ R('X', 38.0)):
                    torus(mb, 0.125, 0.032, 5, 4, 'rope', C_ROPE, False)
                with xf(mb, T(rx, peak_h, 0.0) @ R('X', -38.0)):
                    torus(mb, 0.125, 0.030, 5, 4, 'rope', mul(C_ROPE, 0.88), False)

            pole_pts = [
                (-hx - 0.36, peak_h + 0.06, 0.0),
                ( 0.0,       peak_h + 0.02, 0.02),
                ( hx + 0.36, peak_h + 0.06, 0.0),
            ]
            tube(mb, pole_pts, [0.068, 0.076, 0.068], 5, 'timber', C_DRIFT_PALE, mode='flat')

            if lower_bar_y is not None:
                zf = -hz * (1.0 - lower_bar_y / peak_h) - 0.08
                tube(mb, [(-hx - 0.20, lower_bar_y, zf), (0.0, lower_bar_y - 0.03, zf - 0.02), (hx + 0.20, lower_bar_y, zf)],
                     [0.056, 0.062, 0.056], 5, 'timber', C_TIMBER_HI, mode='flat')
                for sgn in (-1.0, 1.0):
                    with xf(mb, T(sgn * hx, lower_bar_y, zf + 0.05) @ M_Y2X):
                        torus(mb, 0.095, 0.024, 5, 4, 'rope', C_ROPE, False)

            _add_beam(mb, (-hx + 0.05, 0.18, hz * 0.90), (hx * 0.25, peak_h - 0.10, 0.02),
                      0.078, 0.078, 'timber', C_DRIFT_SHADE, 0.0)

            if lantern_arm:
                arm_pts = [
                    (hx, peak_h - 0.08,  0.04),
                    (hx + 0.18, peak_h + 0.42, -0.32),
                    (hx + 0.30, peak_h + 0.56, -0.76),
                ]
                tube(mb, arm_pts, [0.068, 0.056, 0.044], 5, 'timber', C_TIMBER_MID, mode='flat')
                with xf(mb, T(hx, peak_h + 0.04, 0.0) @ M_Y2Z):
                    torus(mb, 0.11, 0.028, 5, 4, 'rope', C_ROPE, False)

    M_RACK_A = T(-0.62, FLOOR_Y, 0.62) @ R('Y', 7.0)
    _build_aframe_rack(M_RACK_A, span_x=2.36, peak_h=2.92, spread_z=1.32, lower_bar_y=1.96, lantern_arm=False)

    M_RACK_B = T(1.30, FLOOR_Y, 0.10) @ R('Y', -32.0)
    _build_aframe_rack(M_RACK_B, span_x=1.52, peak_h=2.42, spread_z=1.12, lower_bar_y=None, lantern_arm=True)

    # 3. Rows of Hanging Sculpted Silver-Teal Tropical Fish strung along both drying racks (10 bold fish!)
    with xf(mb, M_RACK_A):
        for fx, flen, fyaw, ftilt in (
            (-0.78, 0.68,  18.0,  3.0),
            (-0.24, 0.62, -14.0, -2.5),
            ( 0.32, 0.72,  24.0,  2.0),
            ( 0.86, 0.64, -20.0, -3.5),
        ):
            _build_hanging_fish(mb, (fx, 2.94, 0.01), length=flen, yaw_deg=fyaw, tilt_deg=ftilt, rng=rng, smoked=False)
        zf_low = -0.66 * (1.0 - 1.96 / 2.92) - 0.09
        for fx, flen, fyaw, ftilt, smk in (
            (-0.62, 0.56, -16.0, -2.0, False),
            ( 0.04, 0.60,  22.0,  3.0, True),
            ( 0.70, 0.54, -24.0, -2.5, False),
        ):
            _build_hanging_fish(mb, (fx, 1.94, zf_low), length=flen, yaw_deg=fyaw, tilt_deg=ftilt, rng=rng, smoked=smk)

    with xf(mb, M_RACK_B):
        for fx, flen, fyaw, ftilt in (
            (-0.46, 0.62,  14.0,  2.5),
            ( 0.02, 0.68, -18.0, -3.0),
            ( 0.48, 0.58,  24.0,  2.0),
        ):
            _build_hanging_fish(mb, (fx, 2.44, 0.01), length=flen, yaw_deg=fyaw, tilt_deg=ftilt, rng=rng, smoked=False)

    # 4. Draped Knotted Hemp Fishing Net ('rope' + UV2 gentle breeze sway!)
    #    Chunky stylized 4x4 diamond-mesh seine net draped cleanly over the port end of Main Rack!
    net_nu, net_nv = 4, 4
    net_phase = 0.41
    with xf(mb, M_RACK_A):
        def _net_pt(u, v):
            x = -1.44 + u * 1.00 - 0.14 * sin(v * pi * 0.7) * (1.0 - u)
            y = 2.98 - v * 2.15 + 0.18 * sin(u * pi) * (v ** 1.2)
            billow = sin(v * pi * 0.85) * 0.24 + 0.06 * sin(u * pi * 2.4 + v * 2.0)
            z = 0.12 - v * 0.90 - billow
            return Vector((x, y, z))

        def _net_uv2(u, v):
            return (min(0.82, (v ** 1.35) * 0.76 * (0.75 + 0.25 * (1.0 - u))), net_phase)

        n_pts = [[_net_pt(iu / float(net_nu), iv / float(net_nv)) for iv in range(net_nv + 1)] for iu in range(net_nu + 1)]
        n_u2  = [[_net_uv2(iu / float(net_nu), iv / float(net_nv)) for iv in range(net_nv + 1)] for iu in range(net_nu + 1)]

        def _emit_net_cord(p0, p1, u2_0, u2_1, half_w=0.022, col=C_ROPE):
            v_d = p1 - p0
            if v_d.length < 1e-4:
                return
            side = v_d.cross(Vector((0.0, 0.0, -1.0)))
            if side.length < 1e-4:
                side = Vector((1.0, 0.0, 0.0))
            side.normalize()
            out_n = side.cross(v_d).normalized()
            a0, a1 = p0 - side * half_w, p0 + side * half_w
            b0, b1 = p1 - side * half_w, p1 + side * half_w
            mb.fp([a0, a1, b1, b0], 'rope', col, (1, 0, 0), (p0 + p1) * 0.5 - out_n * 0.5,
                  smooth=False, uv2=[u2_0, u2_0, u2_1, u2_1])
            mb.fp([a1, a0, b0, b1], 'rope', mul(col, 0.86), (1, 0, 0), (p0 + p1) * 0.5 + out_n * 0.5,
                  smooth=False, uv2=[u2_0, u2_0, u2_1, u2_1])

        for iu in range(net_nu + 1):
            for iv in range(net_nv):
                w_c = 0.028 if iu in (0, net_nu) else 0.020
                _emit_net_cord(n_pts[iu][iv], n_pts[iu][iv + 1], n_u2[iu][iv], n_u2[iu][iv + 1], w_c, C_ROPE)
        for iv in range(net_nv + 1):
            for iu in range(net_nu):
                w_c = 0.028 if iv in (0, net_nv) else 0.018
                _emit_net_cord(n_pts[iu][iv], n_pts[iu + 1][iv], n_u2[iu][iv], n_u2[iu + 1][iv], w_c, mul(C_ROPE, 0.92))
        for iu in range(net_nu):
            for iv in range(net_nv):
                if (iu + iv) % 2 == 0:
                    _emit_net_cord(n_pts[iu][iv], n_pts[iu + 1][iv + 1], n_u2[iu][iv], n_u2[iu + 1][iv + 1], 0.015, C_ROPE)
                else:
                    _emit_net_cord(n_pts[iu + 1][iv], n_pts[iu][iv + 1], n_u2[iu + 1][iv], n_u2[iu][iv + 1], 0.015, C_ROPE)
        for iu in range(0, net_nu + 1, 2):
            fp = n_pts[iu][0]
            with xf(mb, T(fp) @ M_Y2X):
                cyl(mb, 0.048, -0.055, 0.055, 5, 'timber', C_OAK_FRESH, False, 0.0)

    # 5. Low Stone Fish-Smoking Hearth Glowing with Warm Amber Embers ('glass' molten colors)!
    HX, HZ = -0.26, -0.84
    with xf(mb, T(HX, FLOOR_Y, HZ)):
        for sk in range(7):
            ang = radians(sk * (360.0 / 7.0) + 18.0)
            r_h = 0.56
            sx, sz = cos(ang) * r_h, sin(ang) * r_h
            sh = rng.uniform(0.32, 0.44)
            cbox(mb, (sx, sh * 0.5 - 0.02, sz), (0.40, sh, 0.28), 'limestone',
                 jit(C_COBBLE_DARK if sk % 2 == 0 else C_COBBLE_MID, rng, 0.08), 0.0,
                 M=R('Y', -degrees(ang) + rng.uniform(-8, 8)))
        ember_prof = [
            (0.00, 0.04),
            (0.45, 0.06),
            (0.38, 0.18),
            (0.20, 0.26),
            (0.00, 0.28),
        ]
        lathe(mb, ember_prof, 6, 'glass', C_FLAME_MID, False, False,
              lambda i, k: C_FLAME_CORE if i >= 2 else C_FLAME_DEEP)
        for lg_a, lg_l in ((28.0, 0.68), (-36.0, 0.62), (82.0, 0.56)):
            with xf(mb, T(0.0, 0.20, 0.0) @ R('Y', lg_a) @ R('Z', 12.0)):
                cbox(mb, (0.0, 0.0, 0.0), (lg_l, 0.09, 0.095), 'timber', C_OAK_CHAR, 0.0, (1, 0, 0))
        for gz in (-0.22, 0.0, 0.22):
            _add_beam(mb, (-0.48, 0.44, gz), (0.48, 0.44, gz), 0.028, 0.028, 'iron', C_IRON_FORGED, 0.0)
        for gx in (-0.24, 0.24):
            _add_beam(mb, (gx, 0.42, -0.36), (gx, 0.42, 0.36), 0.026, 0.026, 'iron', C_IRON_RUST, 0.0)
        for fx, fz, fyaw in ((-0.12, -0.08, 16.0), (0.14, 0.10, -24.0)):
            with xf(mb, T(fx, 0.48, fz) @ R('Y', fyaw)):
                cbox(mb, (0.0, 0.0, 0.0), (0.34, 0.042, 0.14), 'paint', C_FISH_SMOKED, 0.0)
                cbox(mb, (0.20, 0.0, 0.0), (0.09, 0.024, 0.11), 'paint', C_OAK_CHAR, 0.0)

    # 6. Oak Brine Barrels, Woven Wicker Lobster-Trap Creels & Upturned Wooden Boat Oar!
    _build_coopered_cask(
        mb, T(-1.46, FLOOR_Y + 0.38, -0.82),
        radius=0.31, height=0.76, rng=rng,
        col_a=C_TIMBER_MID, col_b=C_TIMBER_HI, col_head=C_TIMBER_DARK,
        segs=6, open_fill=('paint', C_BRINE_WATER),
    )
    with xf(mb, T(-1.42, FLOOR_Y + 0.72, -0.80) @ R('Z', -28.0) @ R('Y', 22.0)):
        cbox(mb, (0.0, 0.06, 0.0), (0.055, 0.18, 0.12), 'paint', C_FISH_SILVER, 0.0)
        cbox(mb, (0.0, 0.18, 0.0), (0.024, 0.12, 0.18), 'paint', C_FISH_BACK, 0.0)

    _build_coopered_cask(
        mb, T(-1.72, FLOOR_Y + 0.34, -0.10),
        radius=0.28, height=0.68, rng=rng,
        col_a=C_DRIFT_MID, col_b=C_TIMBER_MID, col_head=C_TIMBER_DARK,
        segs=6, stripe_col=C_TEAL_BRIGHT,
    )
    _build_rope_coil_lean(mb, (-1.72, FLOOR_Y + 0.68, -0.10), radius=0.18, turns=2, r=0.032, segs=6, psegs=4)

    def _build_lobster_creel(M_cr, length=0.76, width=0.48, height=0.40):
        hl, hw = length * 0.5, width * 0.5
        with xf(mb, M_cr):
            for sz in (-hw + 0.05, hw - 0.05):
                cbox(mb, (0.0, 0.025, sz), (length + 0.04, 0.042, 0.085), 'timber', C_DRIFT_SHADE, 0.0, (1, 0, 0))
            arch_pts = [
                (0.0, -hw),
                (height * 0.68, -hw * 0.92),
                (height, -hw * 0.42),
                (height,  hw * 0.42),
                (height * 0.68,  hw * 0.92),
                (0.0,  hw),
            ]
            c_secs = [[Vector((x_e, py + 0.04, pz)) for py, pz in arch_pts] for x_e in (-hl, hl)]
            loft(mb, c_secs, 'rope', C_WICKER_MID, closed=True, caps=(True, True), mode='flat',
                 scols=[C_WICKER_HI, C_WICKER_MID])
            for bx in (-hl + 0.04, 0.0, hl - 0.04):
                bow = [Vector((bx, py + 0.045, pz * 1.04)) for py, pz in arch_pts]
                tube(mb, bow, 0.024, 4, 'timber', C_TIMBER_DARK, mode='flat')
            with xf(mb, T(-hl - 0.01, height * 0.48, 0.0) @ M_Y2X):
                cyl(mb, 0.125, -0.02, 0.03, 5, 'rope', C_WICKER_DARK, False, 0.0, 0.095)
            with xf(mb, T(hl + 0.14, 0.08, -0.14) @ R('Z', 35.0)):
                cyl(mb, 0.085, -0.09, 0.09, 5, 'paint', C_CRIMSON_HI, False, 0.0, 0.072)
                cyl(mb, 0.090, -0.025, 0.025, 5, 'paint', C_PARCHMENT_HI, False, 0.0)

    # Pair of woven wicker lobster-trap creels grounded solidly side-by-side & angled neatly!
    _build_lobster_creel(T(0.88, FLOOR_Y, -1.06) @ R('Y', -26.0), length=0.78, width=0.48, height=0.40)
    _build_lobster_creel(T(1.48, FLOOR_Y, -0.66) @ R('Y',  28.0), length=0.68, width=0.44, height=0.36)

    # Upturned Wooden Boat Oar leaning clearly against the outer-port A-frame leg (never blocking net!)
    OAR_BOT = Vector((-2.02, FLOOR_Y + 0.02,  0.14))
    OAR_TOP = Vector((-1.78, FLOOR_Y + 2.38,  0.54))
    oar_v = OAR_TOP - OAR_BOT
    oar_rot = Vector((0.0, 1.0, 0.0)).rotation_difference(oar_v.normalized()).to_matrix().to_4x4()
    with xf(mb, T(OAR_BOT) @ oar_rot):
        cyl(mb, 0.034, 0.00, 1.72, 5, 'timber', C_OAK_FRESH, False, 0.0, 0.042)
        cyl(mb, 0.052, 0.72, 0.88, 5, 'rope', C_ROPE, False, 0.0)
        blade_secs = [
            _rect_oct(0.0, 1.66, 0.0, 0.042, 0.028, 0.012),
            _rect_oct(0.0, 2.02, 0.0, 0.150, 0.022, 0.010),
            _rect_oct(0.0, 2.42, 0.0, 0.160, 0.018, 0.008),
        ]
        loft(mb, blade_secs, 'timber', C_TIMBER_HI, closed=True, caps=(True, True), mode='flat',
             scols=[C_OAK_FRESH, C_TIMBER_HI, C_TIMBER_HI])
        cbox(mb, (0.0, 2.18, 0.0), (0.322, 0.16, 0.044), 'paint', C_CRIMSON_HI, 0.0)
        cbox(mb, (0.0, 2.04, 0.0), (0.314, 0.055, 0.044), 'paint', C_PARCHMENT_HI, 0.0)

    # 7. Hanging Brass Storm Lantern suspended from the Starboard Rack Cantilever Arm!
    arm_tip_w = M_RACK_B @ Vector((1.06, 2.98, -0.76))
    LANTERN_POS = arm_tip_w + Vector((0.0, -0.44, 0.0))
    _add_beam(mb, arm_tip_w, LANTERN_POS + Vector((0.0, 0.32, 0.0)), 0.020, 0.020, 'rope', C_ROPE, 0.0)
    _build_storm_lantern(mb, LANTERN_POS, scale=1.06, brass_cage=True, hanging=True)

    # 8. Coastal Tuft Ferns ('foliage' + UV2) tucked around the pebble-and-driftwood shore apron!
    for fpos, fsc, flean, fph in (
        ((-2.14, STEP_Y + 0.02, -1.42), 0.78, (-0.7, 0.0, -0.7), 0.16),
        (( 2.08, STEP_Y + 0.02, -1.36), 0.74, ( 0.7, 0.0, -0.7), 0.44),
        ((-2.06, STEP_Y + 0.02,  1.46), 0.84, (-0.7, 0.0,  0.7), 0.71),
        (( 2.02, STEP_Y + 0.02,  1.38), 0.80, ( 0.7, 0.0,  0.7), 0.93),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=3, rng=rng, phase=fph, lean_dir=flean, segs=2)

    build(mb)

    add_empty('Lantern_FishRack', LANTERN_POS)
    col_piece('col_fishrack_base', col_pts)
    export_landmark_glb(outdir, 'coastal_salted_fish_drying_rack.glb')


# ================================================================ 4. VOLCANIC OBSIDIAN DRAGON MAW

def gen_volcanic_obsidian_dragon_maw(outdir):
    """Iconic cursed volcanic stone sea-serpent / dragon-maw lava altar rooted in a fractured
    hexagonal columnar-basalt foundation plunging cleanly to y = -3.60 m (radius ~ 2.65 m).
    Features jagged curving upper & lower obsidian jaw arches lined with razor-sharp obsidian fangs
    framing a gaping glowing molten-magma gullet & hearth tongue ('glass' bright incandescent
    orange-gold linear COLOR_0!), bound in heavy forged-iron shackles & draped anchor chains,
    flanked by twin tall glowing obsidian horn spires, collider 'col_dragonmaw_base', and
    'Lantern_DragonMaw' empty right inside the blazing molten gullet.
    Target: ~3,100-3,700 visual tris, 1 collider (col_dragonmaw_base).
    """
    clear_scene()
    rng = random.Random(SEED + 2953)
    mb = MB('VolcanicObsidianDragonMaw', seed=2953)

    SKIRT_BOT = -3.60
    DECK_Y    =  0.34
    col_pts   = []

    # 1. Fractured Hexagonal Columnar-Basalt Foundation plunging cleanly to y = -3.60 m (radius ~ 2.65 m!)
    base_secs = [
        _reg_poly(0.0, SKIRT_BOT, 0.0, 2.82, sides=6, rot_deg=30.0),
        _reg_poly(0.0, -1.75,     0.0, 2.72, sides=6, rot_deg=30.0),
        _reg_poly(0.0, -0.45,     0.0, 2.62, sides=6, rot_deg=30.0),
        _reg_poly(0.0, DECK_Y,    0.0, 2.48, sides=6, rot_deg=30.0),
    ]
    _loft_horizontal_masonry(
        mb, base_secs, 'basalt',
        [C_OBSIDIAN_ABYSS, C_OBSIDIAN_DARK, C_OBSIDIAN_SHINE, C_OBSIDIAN_HI],
        rng, caps=(True, True), top_mat='basalt', top_col=C_OBSIDIAN_DARK,
    )
    for ring in base_secs:
        col_pts.extend(Vector(p) for p in ring)

    # Ring of 10 Fractured Hexagonal Basalt Organ-Pipe Columns framing the caldera rim!
    col_specs = [
        (-2.14, -0.92, 1.05, 0.50, -6.0, -4.0, True),
        ( 2.14, -0.92, 0.98, 0.50,  6.0, -4.0, True),
        (-2.28,  0.18, 1.48, 0.54, -8.0,  2.0, False),
        ( 2.28,  0.18, 1.42, 0.54,  8.0,  2.0, False),
        (-1.86,  1.34, 2.10, 0.58, -6.0,  6.0, True),
        ( 1.86,  1.34, 2.02, 0.58,  6.0,  6.0, True),
        (-0.92,  1.96, 2.52, 0.60, -3.0,  7.0, False),
        ( 0.92,  1.96, 2.46, 0.60,  3.0,  7.0, False),
        (-1.38, -1.78, 0.72, 0.44, -4.0, -6.0, True),
        ( 1.38, -1.78, 0.70, 0.44,  4.0, -6.0, True),
    ]
    for cx, cz, ch_top, crad, tx, tz, hot in col_specs:
        base_y = -2.20
        sculpt_basalt_column(
            mb, (cx, base_y, cz), ch_top - base_y, crad, 6, tx, tz,
            C_OBSIDIAN_ABYSS, C_OBSIDIAN_HI, rng, mat='basalt', magma_seam=hot,
        )

    # Twin glowing volcanic ember fissures nestled atop the front-flanking basalt columns!
    for sgn in (-1.0, 1.0):
        with xf(mb, T(sgn * 1.38, 0.70, -1.78)):
            lathe(mb, [(0.0, 0.0), (0.28, 0.04), (0.18, 0.22), (0.0, 0.30)],
                  5, 'glass', C_FLAME_MID, False, False,
                  lambda i, k: C_FLAME_CORE if i >= 2 else C_FLAME_DEEP)

    # Seaward stepped scorched basalt approach slabs split by a glowing central lava runoff channel!
    for sgn in (-1.0, 1.0):
        cbox(mb, (sgn * 0.58, DECK_Y + 0.08, -2.18), (0.64, 0.24, 0.56), 'basalt', C_OBSIDIAN_SHINE, 0.0, (1, 0, 0))
        cbox(mb, (sgn * 0.54, DECK_Y + 0.22, -1.80), (0.56, 0.24, 0.52), 'basalt', C_OBSIDIAN_HI, 0.0, (1, 0, 0))

    # 2. Heavy Armored Obsidian Neck / Cranium Bastion (rear +Z backbone rising y = 0.34 .. 3.78 m!)
    neck_secs = [
        _rect_oct(0.0, DECK_Y - 0.06, 0.88, 1.56, 1.06, 0.38),
        _rect_oct(0.0, 1.54,          0.96, 1.44, 0.98, 0.36),
        _rect_oct(0.0, 2.74,          0.84, 1.32, 0.90, 0.32),
        _rect_oct(0.0, 3.68,          0.54, 1.16, 0.82, 0.28),
    ]
    _loft_horizontal_masonry(
        mb, neck_secs, 'basalt',
        [C_OBSIDIAN_DARK, C_OBSIDIAN_SHINE, C_OBSIDIAN_HI, C_OBSIDIAN_HI],
        rng, caps=(False, True), top_mat='basalt', top_col=C_OBSIDIAN_HI,
    )
    # Bold Jagged Dorsal Obsidian Spine Plates + Glowing Magma Veins & Iron Straps down the rear (+Z)!
    for sp_y, sp_z, sp_h, sp_w in (
        (3.74, 1.24, 0.78, 0.28),
        (2.94, 1.66, 0.84, 0.32),
        (2.06, 1.88, 0.78, 0.34),
        (1.22, 1.94, 0.64, 0.30),
    ):
        with xf(mb, T(0.0, sp_y, sp_z) @ R('X', 42.0)):
            s_secs = [
                _rect_oct(0.0, -0.22, 0.0, sp_w * 0.56, sp_h * 0.52, 0.06),
                _rect_oct(0.0,  sp_h, 0.0, 0.04,        0.06,        0.02),
            ]
            loft(mb, s_secs, 'basalt', C_OBSIDIAN_HI, closed=True, caps=(True, True), mode='flat',
                 scols=[C_OBSIDIAN_DARK, C_STEEL_MID])
    # Twin glowing volcanic fissure veins snaking down the rear armored dragon neck (+Z)!
    for sgn in (-1.0, 1.0):
        rear_vein = [
            (sgn * 0.42, 3.55, 1.28),
            (sgn * 0.64, 2.78, 1.68),
            (sgn * 0.72, 1.88, 1.88),
            (sgn * 0.58, 0.96, 1.88),
        ]
        _sculpt_magma_ribbon(mb, rear_vein, [0.11, 0.13, 0.12, 0.08], (sgn * 0.36, 0.10, 0.92), hot_core=False, ridge_h=0.075)
    # Forged-iron collar strap bolted across the rear neck!
    cbox(mb, (0.0, 2.52, 1.72), (2.28, 0.22, 0.16), 'iron', C_IRON_FORGED, 0.0)
    for rx in (-0.88, -0.44, 0.44, 0.88):
        cbox(mb, (rx, 2.52, 1.82), (0.11, 0.11, 0.08), 'iron', C_IRON_BRONZE, 0.0)

    # 3. Jagged Curving Lower Obsidian Jaw Arch & Multi-Layered Blazing Molten-Magma Gullet + Hearth Tongue!
    #    Lower U-shaped jaw arches with a deliberate open molten cleft at the seaward chin!
    for sgn in (-1.0, 1.0):
        lj_pts = [
            Vector((sgn * 1.34, DECK_Y + 0.56,  0.48)),
            Vector((sgn * 1.26, DECK_Y + 0.50, -0.34)),
            Vector((sgn * 0.94, DECK_Y + 0.44, -1.18)),
            Vector((sgn * 0.44, DECK_Y + 0.50, -1.78)),
            Vector((sgn * 0.24, DECK_Y + 0.54, -1.96)),
        ]
        lj_secs = []
        lj_cols = [C_OBSIDIAN_DARK, C_OBSIDIAN_SHINE, C_OBSIDIAN_HI, C_OBSIDIAN_HI, C_STEEL_MID]
        for i, p in enumerate(lj_pts):
            hw = 0.34 * (1.0 - 0.34 * (i / 4.0))
            hh = 0.30 * (1.0 - 0.26 * (i / 4.0))
            lj_secs.append([
                p + Vector((-hw, -hh, 0.0)),
                p + Vector(( hw, -hh, 0.0)),
                p + Vector(( hw * 0.82, hh, 0.0)),
                p + Vector((-hw * 0.82, hh, 0.0)),
            ])
        loft(mb, lj_secs, 'basalt', C_OBSIDIAN_SHINE, closed=True, caps=(True, True), mode='flat', scols=lj_cols)
        # Flanking chin armor tusks bracketing the molten cleft!
        cbox(mb, (sgn * 0.36, DECK_Y + 0.44, -1.94), (0.30, 0.36, 0.34), 'basalt', C_OBSIDIAN_HI, 0.0, M=R('X', -18.0))

    # Multi-Layered Blazing Molten-Magma Gullet & Hearth Tongue ('glass' rich crimson-orange-gold!)
    #    a) Recessed curved magma throat furnace backdrop (deep fiery orange-crimson, NOT a flat white block!)
    throat_secs = [
        _reg_poly(0.0, DECK_Y + 0.36, 0.34, 1.04, sides=6, rot_deg=0.0, sx=1.06, sz=0.52),
        _reg_poly(0.0, 1.48,          0.42, 0.94, sides=6, rot_deg=0.0, sx=1.02, sz=0.48),
        _reg_poly(0.0, 2.54,          0.46, 0.74, sides=6, rot_deg=0.0, sx=0.94, sz=0.44),
    ]
    loft(mb, throat_secs, 'glass', C_FLAME_DEEP, closed=True, caps=(True, True), mode='flat',
         scols=[C_FLAME_MID, C_FLAME_DEEP, C_MAGMA_CRIMSON])

    # Sculpted jagged dark-obsidian inner throat ribs framing fiery molten cascades inside the gullet!
    for sgn in (-1.0, 1.0):
        _add_beam(mb, (sgn * 0.88, DECK_Y + 0.56, 0.18), (sgn * 0.62, 2.68, 0.24),
                  0.22, 0.24, 'basalt', C_OBSIDIAN_DARK, 0.0)
        # Fiery orange-gold molten lava streams cascading down the inner cheeks of the throat!
        side_lava = [
            (sgn * 0.46, 2.38, 0.16),
            (sgn * 0.52, 1.62, 0.06),
            (sgn * 0.44, 0.98, -0.18),
        ]
        _sculpt_magma_ribbon(mb, side_lava, [0.16, 0.22, 0.26], (-sgn * 0.25, 0.18, -0.95), hot_core=True, ridge_h=0.08)

    # Central roaring volcanic hearth-core flame crystal licking up inside the open gullet!
    with xf(mb, T(0.0, DECK_Y + 0.54, -0.14)):
        lathe(mb, [(0.0, 0.0), (0.42, 0.16), (0.28, 0.64), (0.12, 1.02), (0.0, 1.24)],
              6, 'glass', C_FLAME_MID, False, False,
              lambda i, k: C_FLAME_CORE if i in (1, 2) else C_FLAME_DEEP)

    #    b) Glowing Molten Hearth Pool inside the lower jaw bowl crusted with dark volcanic basalt slag chunks!
    pool_pts = [
        (-0.96, DECK_Y + 0.52,  0.22),
        (-0.80, DECK_Y + 0.52, -0.78),
        (-0.42, DECK_Y + 0.54, -1.54),
        ( 0.00, DECK_Y + 0.56, -1.78),
        ( 0.42, DECK_Y + 0.54, -1.54),
        ( 0.80, DECK_Y + 0.52, -0.78),
        ( 0.96, DECK_Y + 0.52,  0.22),
    ]
    mb.fp(pool_pts, 'glass', C_FLAME_MID, (1, 0, 0), Vector((0.0, -1.0, -0.5)), smooth=False)
    # Floating dark basalt slag rocks breaking up the glowing magma pool for rich painterly contrast!
    for rx, rz, rs in ((-0.54, -0.68, 0.18), (0.56, -0.52, 0.20), (-0.42, -1.24, 0.15), (0.44, -1.18, 0.16)):
        cbox(mb, (rx, DECK_Y + 0.58, rz), (rs * 1.4, rs * 0.72, rs * 1.2), 'basalt', C_OBSIDIAN_DARK, 0.0,
             M=R('Y', rng.uniform(0, 180)) @ R('Z', rng.uniform(-14, 14)))

    #    c) Iconic Glowing Molten Hearth Tongue spilling continuously through the open chin cleft & down the steps!
    tongue_path = [
        (0.0, DECK_Y + 0.66,  0.14),
        (0.0, DECK_Y + 0.68, -0.54),
        (0.0, DECK_Y + 0.70, -1.24),
        (0.0, DECK_Y + 0.66, -1.86),
        (0.0, DECK_Y + 0.42, -2.10),
        (0.0, DECK_Y + 0.16, -2.38),
        (0.0, DECK_Y + 0.04, -2.58),
    ]
    _sculpt_magma_ribbon(mb, tongue_path, [0.36, 0.34, 0.30, 0.24, 0.22, 0.26, 0.18], (0.0, 0.86, -0.50), hot_core=True, ridge_h=0.085)

    # 4. Jagged Curving Upper Obsidian Jaw Arch, Armored Snout Crest & Glowing Molten Eye-Slits!
    upper_jaw_spec = [
        ( 0.56, 3.34, 1.24, 0.56, C_OBSIDIAN_DARK),
        (-0.18, 3.64, 1.14, 0.52, C_OBSIDIAN_SHINE),
        (-0.96, 3.48, 0.92, 0.44, C_OBSIDIAN_HI),
        (-1.62, 3.08, 0.62, 0.34, C_OBSIDIAN_HI),
        (-2.06, 2.66, 0.28, 0.22, C_OBSIDIAN_SHINE),
    ]
    uj_secs = []
    uj_cols = []
    for zc, yc, hw, hh, col in upper_jaw_spec:
        uj_secs.append([
            Vector(( 0.00,       yc + hh * 1.18, zc)),
            Vector(( hw * 0.78,  yc + hh * 0.66, zc)),
            Vector(( hw,         yc - hh * 0.16, zc)),
            Vector(( hw * 0.68,  yc - hh * 0.72, zc)),
            Vector(( 0.00,       yc - hh * 0.24, zc)),
            Vector((-hw * 0.68,  yc - hh * 0.72, zc)),
            Vector((-hw,         yc - hh * 0.16, zc)),
            Vector((-hw * 0.78,  yc + hh * 0.66, zc)),
        ])
        uj_cols.append(col)
    loft(mb, uj_secs, 'basalt', C_OBSIDIAN_HI, closed=True, caps=(True, True), mode='flat', scols=uj_cols)

    # Flared Angular Obsidian Brow Ridges, Glowing Molten Eye-Slits & Nasal Horn Spike!
    for sgn in (-1.0, 1.0):
        cbox(mb, (sgn * 0.96, 3.68, -0.58), (0.38, 0.24, 0.96), 'basalt', C_OBSIDIAN_HI, 0.0,
             M=R('Y', -sgn * 16.0) @ R('Z', -sgn * 22.0))
        cbox(mb, (sgn * 1.00, 3.44, -0.62), (0.14, 0.17, 0.46), 'glass', C_FLAME_CORE, 0.0,
             M=R('Y', -sgn * 18.0) @ R('X', 14.0))
        cbox(mb, (sgn * 0.36, 2.94, -1.72), (0.12, 0.11, 0.22), 'glass', C_FLAME_MID, 0.0,
             M=R('Y', -sgn * 24.0))
    # Jagged Nasal Snout Horn Spike jutting upward at the tip of the upper jaw!
    tube(mb, [(0.0, 3.16, -1.58), (0.0, 3.60, -1.82), (0.0, 4.08, -1.90)],
         [0.21, 0.14, 0.025], 5, 'basalt', C_OBSIDIAN_HI, mode='flat',
         scols=[C_OBSIDIAN_DARK, C_OBSIDIAN_HI, C_STEEL_MID])

    # 5. Razor-Sharp Obsidian Fangs lining BOTH Upper & Lower Jaw Arches (high-contrast glossy sheen!)
    def _add_obsidian_fang(base_p, tip_p, r_base):
        bp, tp = Vector(base_p), Vector(tip_p)
        mid_p = bp.lerp(tp, 0.52) + Vector((0.0, 0.0, 0.06))
        tube(mb, [bp, mid_p, tp], [r_base, r_base * 0.58, 0.018], 4, 'basalt', C_STEEL_MID,
             caps=(True, True), mode='flat', scols=[C_OBSIDIAN_HI, C_STEEL_MID, C_STEEL_BRIGHT])

    for sgn in (-1.0, 1.0):
        for bx, by, bz, flen, frad in (
            (0.42, 2.74, -1.78, 0.74, 0.125),  # giant front sabre-fangs!
            (0.68, 3.04, -1.34, 0.58, 0.110),
            (0.86, 3.20, -0.82, 0.52, 0.102),
            (0.98, 3.16, -0.28, 0.46, 0.095),
            (1.06, 2.94,  0.22, 0.40, 0.090),
        ):
            _add_obsidian_fang((sgn * bx, by, bz), (sgn * bx * 0.94, by - flen, bz + 0.06), frad)
        for bx, by, bz, flen, frad in (
            (0.36, DECK_Y + 0.66, -1.72, 0.64, 0.115),  # bold lower chin tusks!
            (0.76, DECK_Y + 0.62, -1.24, 0.48, 0.098),
            (1.04, DECK_Y + 0.64, -0.68, 0.44, 0.092),
            (1.16, DECK_Y + 0.68, -0.08, 0.38, 0.086),
        ):
            _add_obsidian_fang((sgn * bx, by, bz), (sgn * bx * 0.95, by + flen, bz + 0.04), frad)

    # 6. Twin Tall Glowing Obsidian Horn Spires (~6.0 m tall!) with Proudly Raised Molten Magma Veins!
    for sgn, h_boost in ((-1.0, 0.18), (1.0, -0.06)):
        horn_pts = [
            Vector((sgn * 0.72, 3.58,  0.46)),
            Vector((sgn * 1.18, 4.24,  0.64)),
            Vector((sgn * 1.56, 4.96,  0.84)),
            Vector((sgn * 1.72, 5.56 + h_boost, 0.72)),
            Vector((sgn * 1.54, 5.98 + h_boost, 0.44)),
        ]
        horn_rads = [0.42, 0.32, 0.22, 0.14, 0.038]
        tube(mb, horn_pts, horn_rads, 6, 'basalt', C_OBSIDIAN_HI,
             caps=(True, True), mode='flat',
             scols=[C_OBSIDIAN_DARK, C_OBSIDIAN_SHINE, C_OBSIDIAN_HI, C_OBSIDIAN_HI, C_BASALT_HOT])
        # Front-seaward glowing magma fissure vein projecting proudly outside the obsidian horn!
        f_nrm = Vector((-sgn * 0.24, 0.18, -0.95)).normalized()
        vein_front = [p + f_nrm * (r * 0.84 + 0.02) for p, r in zip(horn_pts, horn_rads)]
        _sculpt_magma_ribbon(mb, vein_front, [0.13, 0.11, 0.09, 0.07, 0.036], f_nrm, hot_core=True, ridge_h=0.065)
        # Rear-outer glowing magma crack so the horn spires glow fiercely in rear 3/4 view too!
        r_nrm = Vector((sgn * 0.42, 0.16, 0.89)).normalized()
        vein_rear = [p + r_nrm * (r * 0.84 + 0.02) for p, r in zip(horn_pts[:-1], horn_rads[:-1])]
        _sculpt_magma_ribbon(mb, vein_rear, [0.11, 0.09, 0.075, 0.055], r_nrm, hot_core=False, ridge_h=0.060)

    # 7. Heavy Forged-Iron Shackles & Draped Anchor Chains binding the Cursed Dragon Maw!
    cbox(mb, (0.0, 3.86, -0.98), (1.78, 0.18, 0.28), 'iron', C_IRON_FORGED, 0.0)
    for rx in (-0.64, 0.0, 0.64):
        cbox(mb, (rx, 3.98, -0.98), (0.12, 0.09, 0.12), 'iron', C_IRON_BRONZE, 0.0)
    for sgn in (-1.0, 1.0):
        cbox(mb, (sgn * 0.94, 3.48, -0.98), (0.20, 0.74, 0.28), 'iron', C_IRON_FORGED, 0.0, M=R('Z', sgn * 14.0))
        cbox(mb, (sgn * 1.02, 3.50, -0.98), (0.10, 0.12, 0.12), 'iron', C_IRON_BRONZE, 0.0)
        shack_jaw = Vector((sgn * 1.06, 3.24, -0.98))
        anc_front = Vector((sgn * 2.08, 1.04, -0.92))
        cbox(mb, anc_front - Vector((0.0, 0.10, 0.0)), (0.30, 0.34, 0.30), 'iron', C_IRON_BRONZE, 0.0)
        with xf(mb, T(shack_jaw) @ M_Y2Z):
            torus(mb, 0.12, 0.036, 5, 4, 'iron', C_IRON_BRONZE, False)
        with xf(mb, T(anc_front + Vector((0.0, 0.10, 0.0))) @ M_Y2Z):
            torus(mb, 0.12, 0.036, 5, 4, 'iron', C_IRON_FORGED, False)
        _add_chain_links(mb, shack_jaw, anc_front + Vector((0.0, 0.08, 0.0)),
                         n_links=7, link_r=0.19, wire_r=0.054, segs=5, psegs=4, sag=0.28,
                         mat='iron', rust_stride=2, stretch_y=1.44,
                         col_a=C_IRON_FORGED, col_b=C_IRON_BRONZE)

        h_shack_pos = Vector((sgn * 1.18, 4.24, 0.64))
        with xf(mb, T(h_shack_pos) @ R('Z', -sgn * 28.0)):
            cyl(mb, 0.37, -0.10, 0.10, 6, 'iron', C_IRON_FORGED, False, 0.0)
        anc_rear = Vector((sgn * 1.88, 2.06, 1.34))
        cbox(mb, anc_rear - Vector((0.0, 0.08, 0.0)), (0.28, 0.30, 0.28), 'iron', C_IRON_FORGED, 0.0)
        _add_chain_links(mb, h_shack_pos + Vector((sgn * 0.28, -0.06, 0.12)), anc_rear + Vector((0.0, 0.08, 0.0)),
                         n_links=6, link_r=0.18, wire_r=0.050, segs=5, psegs=4, sag=0.22,
                         mat='iron', rust_stride=2, stretch_y=1.44,
                         col_a=C_IRON_FORGED, col_b=C_IRON_BRONZE)

    # Lantern_DragonMaw empty right inside the blazing molten gullet!
    LANTERN_POS = Vector((0.0, 1.56, -0.34))

    build(mb)

    add_empty('Lantern_DragonMaw', LANTERN_POS)
    col_piece('col_dragonmaw_base', col_pts)
    export_landmark_glb(outdir, 'volcanic_obsidian_dragon_maw.glb')


CORSAIR_RELICS_GENERATORS = [
    gen_pirate_bounty_gallows_post,
    gen_ancient_kraken_stone_fountain,
    gen_coastal_salted_fish_drying_rack,
    gen_volcanic_obsidian_dragon_maw,
]
