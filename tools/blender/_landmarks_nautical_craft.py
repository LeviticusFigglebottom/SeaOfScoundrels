# Sea of Scoundrels: 4 sculpted 3D Nautical Craft Landmarks (Wave I-14 / Pass I-Q7 — 58-Landmark Fleet!).
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

# Warm sandstone, tidal rock, driftwood & cobbled terrace tones
C_SAND_PALE     = srgb('#f2e2c2')
C_SAND_WARM     = srgb('#dfb882')
C_SAND_OCHRE    = srgb('#b48d5d')
C_COBBLE_LIGHT  = srgb('#cdc0a8')
C_COBBLE_MID    = srgb('#928672')
C_COBBLE_DARK   = srgb('#5a5349')
C_TIDE_DARK     = mix(C_LIME_DARK, C_SEA_MOSS, 0.42)
C_DRIFT_PALE    = srgb('#d0c2a9')
C_DRIFT_SHADE   = srgb('#796c5b')
C_OAK_FRESH     = srgb('#c38b50')

# Verdigris sea-bronze, gilded brass, coral & barnacle accents
C_VERDIGRIS_HI  = srgb('#66baa4')
C_VERDIGRIS_MID = srgb('#3d8e7a')
C_VERDIGRIS_DK  = srgb('#265e52')
C_BRONZE_MID    = srgb('#8e7b42')
C_BRONZE_SHINE  = srgb('#d2ac4a')
C_GOLD_BRIGHT   = srgb('#f5c948')
C_BRASS_DARK    = srgb('#8f6624')
C_CORAL_PINK    = srgb('#d46c5c')
C_CORAL_OCHRE   = srgb('#d9934c')
C_BARNACLE_PALE = srgb('#e8dfc8')

# Sailcloth stripes, parchment archipelago chart & pirate accents
C_CRIMSON_HI    = srgb('#c62f24')
C_CRIMSON_MID   = srgb('#962119')
C_CANVAS_CREAM  = srgb('#eee3c8')
C_CANVAS_WARM   = srgb('#d8c49a')
C_TEAL_BRIGHT   = srgb('#248e96')
C_TEAL_CHART    = srgb('#3a9696')
C_CHART_SEA     = srgb('#78b4a6')
C_CHART_PAPER   = srgb('#e7d4a6')
C_CHART_EDGE    = srgb('#b89562')
C_CHART_ISLE    = srgb('#6c9e44')
C_CHART_INK     = srgb('#3b2a1c')
C_STEEL_BRIGHT  = srgb('#8a94a2')
C_ASH_DARK      = srgb('#282428')

# Arcane turquoise tidal runes, sea-kelp & lush coastal ivy
C_RUNE_CORE     = srgb('#54ffe8')
C_RUNE_MID      = srgb('#18d6bc')
C_RUNE_DEEP     = srgb('#0c8c80')
C_KELP_DARK     = srgb('#164a30')
C_KELP_MID      = srgb('#2a7242')
C_KELP_TIP      = srgb('#64a644')
C_VINE_DARK     = srgb('#15481d')
C_VINE_MID      = srgb('#2b7024')
C_VINE_SUN      = srgb('#74b928')

# Volcanic molten ember, flame & sulfur tones
C_FLAME_CORE    = srgb('#ffe87c')
C_FLAME_MID     = srgb('#ff8c24')
C_FLAME_DEEP    = srgb('#d83612')
C_MAGMA_CRIMSON = srgb('#de3010')
C_COAL_CHAR     = srgb('#1c181b')


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
    """Stepped or battered stone foundation/pillar shaft with clean horizontal UV courses."""
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
    cage_col = C_GOLD_BRIGHT if brass_cage else C_IRON
    with xf(mb, T(cx, cy, cz)):
        cyl(mb, 0.145 * s, -0.22 * s, -0.14 * s, 6, 'iron', C_IRON, False, 0.0, 0.165 * s)
        cyl(mb, 0.17 * s, 0.15 * s, 0.23 * s, 6, cage_mat, cage_col, False, 0.0, 0.07 * s)
        cyl(mb, 0.065 * s, 0.23 * s, 0.30 * s, 6, 'iron', C_IRON_RUST, False, 0.0, 0.038 * s)
        cyl(mb, 0.118 * s, -0.14 * s, 0.15 * s, 6, 'glass', C_LANTERN_GL, False, 0.0, 0.128 * s)
        for k in range(4):
            ang = k * pi * 0.5 + pi * 0.25
            cbox(mb, (0.142 * s * cos(ang), 0.005 * s, 0.142 * s * sin(ang)),
                 (0.028 * s, 0.31 * s, 0.028 * s), cage_mat, cage_col, 0.0)
        if hanging:
            with xf(mb, T(0.0, 0.33 * s, 0.0) @ M_Y2Z):
                torus(mb, 0.052 * s, 0.014 * s, 6, 4, 'iron', C_IRON, False)


def _build_coopered_cask(mb, M_bar, radius=0.32, height=0.80, rng=None,
                         col_a=C_TIMBER_MID, col_b=C_TIMBER_HI, col_head=C_TIMBER_DARK,
                         segs=6, stripe_col=None, spigot=False):
    """Chunky coopered pirate rum/supply cask with forged-iron hoops."""
    hh = height * 0.5
    prof = [
        (0.0,           -hh),
        (radius * 0.82, -hh),
        (radius,         0.0),
        (radius * 0.82,  hh),
        (0.0,            hh),
    ]
    stave_cols = [
        jit(col_a if k % 2 == 0 else col_b, rng, 0.07, 0.018) if rng else col_a
        for k in range(segs)
    ]
    with xf(mb, M_bar):
        lathe(mb, prof, segs, 'timber', col_a, False, False,
              lambda i, k: col_head if i in (0, 3) else stave_cols[k])
        for hi_idx, (hy, hr) in enumerate(((-hh * 0.62, radius * 0.94), (hh * 0.62, radius * 0.94))):
            cyl(mb, hr, hy - 0.028, hy + 0.028, segs, 'iron',
                C_IRON_RUST if hi_idx == 1 else C_IRON, False, 0.0)
        if stripe_col is not None:
            cyl(mb, radius * 1.015, -hh * 0.18, hh * 0.18, segs, 'paint', stripe_col, False, 0.0)
        if spigot:
            with xf(mb, T(0.0, hh + 0.01, 0.0)):
                cyl(mb, 0.028, -0.02, 0.13, 4, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.018)
            cbox(mb, (0.0, hh + 0.09, 0.04), (0.084, 0.024, 0.024), 'brass', C_GOLD_BRIGHT, 0.0)


def _build_stenciled_crate(mb, M_crate, size=(0.76, 0.64, 0.70), rng=None,
                           stripe_col=C_CRIMSON_HI, stencil_col=C_CANVAS_CREAM):
    """Weathered pirate cargo crate with timber battens, iron corner straps & painted stencil."""
    sx, sy, sz = size
    hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
    with xf(mb, M_crate):
        cbox(mb, (0.0, 0.0, 0.0), (sx, sy, sz), 'timber',
             jit(C_TIMBER_MID, rng, 0.05) if rng else C_TIMBER_MID, 0.0, (1, 0, 0))
        for ys in (-hy + 0.052, hy - 0.052):
            for zs in (-hz - 0.012, hz + 0.012):
                cbox(mb, (0.0, ys, zs), (sx + 0.04, 0.084, 0.038), 'timber', C_TIMBER_HI, 0.0, (1, 0, 0))
            for xs in (-hx - 0.012, hx + 0.012):
                cbox(mb, (xs, ys, 0.0), (0.038, 0.084, sz + 0.02), 'timber', C_TIMBER_HI, 0.0, (0, 0, 1))
        for xs in (-hx - 0.012, hx + 0.012):
            for zs in (-hz - 0.012, hz + 0.012):
                cbox(mb, (xs, 0.0, zs), (0.058, sy + 0.02, 0.058), 'iron', C_IRON, 0.0)
        if stripe_col is not None:
            for zs in (-hz - 0.020, hz + 0.020):
                cbox(mb, (0.0, 0.0, zs), (sx * 0.62, 0.14, 0.014), 'paint', stripe_col, 0.0)
                if stencil_col is not None:
                    cbox(mb, (0.0, 0.0, zs + (0.009 if zs > 0 else -0.009)),
                         (0.13, 0.13, 0.010), 'paint', stencil_col, 0.0, M=R('Z', 45.0))


def _build_rope_coil_lean(mb, center, radius=0.28, turns=3, r=0.038, segs=7, psegs=4):
    """Chunky coiled braided hemp rope pile ('rope')."""
    for i in range(turns):
        rr = radius * (1.0 - 0.22 * i)
        with xf(mb, T(center[0], center[1] + r * (1.0 + i * 1.60), center[2])):
            torus(mb, rr, r, segs, psegs, 'rope', mul(C_ROPE, 0.88 + 0.12 * (i % 2)), True)


def _add_leafy_vine_drape(mb, anchor, length, width, out_dir, rng, phase=0.0,
                          c_dark=C_VINE_DARK, c_mid=C_VINE_MID, c_sun=C_VINE_SUN):
    """Sculpted hanging leafy sea-ivy / kelp vine ('foliage') with UV2 wind weights (0 root -> 0.96 tip)."""
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
        sway = sin(t * 3.4 + phase * 6.28) * 0.14 * (0.2 + 0.8 * t)
        out_off = 0.04 + 0.12 * sin(t * pi * 0.78) + 0.06 * t
        stem_pts.append(a + od * out_off + side * sway + Vector((0.0, -length * t, 0.0)))

    for i in range(segs):
        t0 = i / float(segs)
        t1 = (i + 1) / float(segs)
        w0 = width * 0.24 * (1.0 - 0.50 * t0)
        w1 = width * 0.24 * (1.0 - 0.72 * t1)
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
        t = (li + 0.35) / float(n_leaves + 0.25)
        idx_f = t * segs
        i0 = min(segs - 1, int(idx_f))
        frac = idx_f - i0
        root = stem_pts[i0].lerp(stem_pts[i0 + 1], frac)
        sgn = -1.0 if (li % 2 == 0) else 1.0
        l_scale = (0.78 + 0.52 * sin(t * pi * 0.85)) * (1.0 - 0.30 * t)
        l_len = width * 1.48 * l_scale * rng.uniform(0.86, 1.15)
        l_wid = width * 0.62 * l_scale * rng.uniform(0.86, 1.14)
        l_dir = (side * (sgn * 0.66) + od * (0.48 + rng.uniform(-0.10, 0.16)) + Vector((0.0, -0.74, 0.0))).normalized()
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
    """Broad painterly coastal fern / sea-kelp rosette ('foliage') with UV2 wind weights."""
    rp = Vector(root_pos)
    base_rot = rng.uniform(0.0, 2.0 * pi) if rng else 0.0
    for fi in range(n_fronds):
        ang = base_rot + 2.0 * pi * fi / float(n_fronds) + (rng.uniform(-0.20, 0.20) if rng else 0.0)
        f_len = scale * (rng.uniform(0.86, 1.16) if rng else 1.0)
        f_w = scale * (rng.uniform(0.24, 0.32) if rng else 0.28)
        f_arch_h = scale * (rng.uniform(0.42, 0.58) if rng else 0.50)
        f_droop = scale * (rng.uniform(0.22, 0.36) if rng else 0.28)
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


def _add_chain_links(mb, p_start, p_end, n_links=6, link_r=0.18, wire_r=0.054,
                     segs=6, psegs=4, sag=0.40, mat='iron', rust_stride=2, stretch_y=1.34,
                     col_a=C_IRON, col_b=C_IRON_RUST):
    """Tightly interlocking arc-length-spaced forged-iron chain links between p_start and p_end."""
    a = Vector(p_start)
    b = Vector(p_end)
    if (b - a).length < 1e-4 or n_links < 1:
        return
    samples = 48
    pts_s = [a.lerp(b, i / float(samples)) + Vector((0.0, -sag * 4.0 * (i / float(samples)) * (1.0 - i / float(samples)), 0.0))
             for i in range(samples + 1)]
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


def _build_pulley_block(mb, center, radius=0.22, yaw_deg=0.0, has_hook=False, uv2_w=None):
    """Chunky iron-strapped wooden pulley sheave block with brass wheel & optional forged hook."""
    with xf(mb, T(center) @ R('Y', yaw_deg)):
        for sx in (-0.095, 0.095):
            cbox(mb, (sx, 0.0, 0.0), (0.064, radius * 2.50, radius * 2.02), 'timber', C_TIMBER_MID, 0.0)
        cbox(mb, (0.0,  radius * 1.30, 0.0), (0.27, 0.055, 0.14), 'iron', C_IRON, 0.0)
        cbox(mb, (0.0, -radius * 1.30, 0.0), (0.27, 0.055, 0.14), 'iron', C_IRON, 0.0)
        with xf(mb, M_Y2X):
            cyl(mb, radius * 0.90, -0.054, 0.054, 6, 'brass', C_GOLD_BRIGHT, False, 0.0)
            cyl(mb, 0.042, -0.155, 0.155, 5, 'iron', C_IRON, False, 0.0)
        with xf(mb, T(0.0, radius * 1.54, 0.0) @ M_Y2Z):
            torus(mb, 0.080, 0.022, 6, 4, 'iron', C_IRON_RUST, False)
        if has_hook:
            hook_path = [
                (0.0, -radius * 1.32, 0.0),
                (0.0, -radius * 1.88, 0.0),
                (0.0, -radius * 2.38, -0.14),
                (0.0, -radius * 2.52,  0.04),
                (0.0, -radius * 2.15,  0.22),
            ]
            suv2 = [(uv2_w, 0.18)] * len(hook_path) if uv2_w is not None else None
            tube(mb, hook_path, [0.042, 0.048, 0.050, 0.042, 0.022], 4, 'iron', C_IRON, mode='flat', suv2=suv2)


def _build_wind_pennant(mb, root_pos, length=1.75, h0=0.44, out_dir=(0.78, -0.06, -0.62),
                        col_main=C_CRIMSON_HI, col_trim=C_GOLD_BRIGHT, phase=0.36):
    """Wind-whipped double-sided tattered pirate swallowtail pennant ('paint') with UV2 wind weights."""
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
        wave = sin(t * 2.2 * pi) * 0.18 * t
        droop = -0.20 * t * t
        hh = h0 * (1.0 - 0.50 * t)
        ctr = rp + od * (length * t) + side * wave + Vector((0.0, droop, 0.0))
        top_pts.append(ctr + Vector((0.0, hh * 0.5, 0.0)))
        bot_pts.append(ctr - Vector((0.0, hh * 0.5, 0.0)))
        weights.append((t ** 1.15) * 0.94)
    for i in range(segs):
        c_seg = col_trim if i == 0 else (col_main if i % 2 == 1 else mul(col_main, 0.78))
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
                mb.fp(b_pts, 'paint', mul(c_seg, 0.82), od, ctr_tri + side * 1.0, smooth=False, uv2=list(reversed(tu2)))
        else:
            q_f = [t0 + side * thick, t1 + side * thick, b1 + side * thick, b0 + side * thick]
            q_b = [t1 - side * thick, t0 - side * thick, b0 - side * thick, b1 - side * thick]
            ctr_q = (t0 + t1 + b0 + b1) * 0.25
            mb.fp(q_f, 'paint', c_seg, od, ctr_q - side * 1.0, smooth=False, uv2=[u0, u1, u1, u0])
            mb.fp(q_b, 'paint', mul(c_seg, 0.82), od, ctr_q + side * 1.0, smooth=False, uv2=[u1, u0, u0, u1])
            mb.fp([t0 - side * thick, t1 - side * thick, t1 + side * thick, t0 + side * thick],
                  'paint', mul(c_seg, 0.76), od, ctr_q, smooth=False, uv2=[u0, u1, u1, u0])
            mb.fp([b0 + side * thick, b1 + side * thick, b1 - side * thick, b0 - side * thick],
                  'paint', mul(c_seg, 0.72), od, ctr_q, smooth=False, uv2=[u0, u1, u1, u0])


def _sculpt_magma_ribbon(mb, path_pts, widths, surface_nrm, hot_core=True):
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
        left_pts.append(pts[i] - side * w - nrm * 0.015)
        right_pts.append(pts[i] + side * w - nrm * 0.015)
        mid_pts.append(pts[i] + nrm * (0.055 + 0.014 * sin(i * 1.8)))
    for i in range(n - 1):
        c_mid = C_FLAME_CORE if (hot_core and i <= 1) else C_MAGMA_GLOW
        c_edge = C_MAGMA_CRIMSON if i < n - 2 else C_BASALT_HOT
        inside = (pts[i] + pts[i + 1]) * 0.5 - nrm * 0.5
        mb.fp([left_pts[i], mid_pts[i], mid_pts[i + 1], left_pts[i + 1]], 'glass',
              [c_edge, c_mid, c_mid, c_edge], (1, 0, 0), inside, smooth=False)
        mb.fp([mid_pts[i], right_pts[i], right_pts[i + 1], mid_pts[i + 1]], 'glass',
              [c_mid, c_edge, c_edge, c_mid], (1, 0, 0), inside, smooth=False)


# ================================================================ 1. COASTAL ROPE FERRY PULLEY

def gen_coastal_rope_ferry_pulley(outdir):
    """Cliffside timber cargo-winch gantry (~6.2 m tall) anchored on a deeply skirted stepped
    warm sandstone & moss abutment plunging cleanly to y = -3.20 m (hx = 2.45 m, hz = 2.25 m).
    Stout braced timber A-frame tower with cantilevered seaward loading boom, stone-filled
    rear ballast crib, cast-iron geared hand-crank windlass drum with toothed cogwheel,
    taut hemp pulley line + coiled mooring rope on deck, suspended timber cargo crate & lashed
    rum barrel hanging from the pulley hook (subtle UV2 sway!), rusted iron mooring bollard,
    trailing sea-ivy fronds ('foliage' + UV2), and hanging brass storm lantern ('Lantern_FerryWinch').
    Target: 3,000-3,700 visual tris, 2 colliders (col_ferry_base, col_ferry_frame).
    """
    clear_scene()
    rng = random.Random(SEED + 2701)
    mb = MB('CoastalRopeFerryPulley', seed=2701)

    SKIRT_BOT = -3.20
    ABUT_TOP = 0.24
    DECK_Y = 0.42
    base_col_pts = []
    frame_col_pts = []

    # 1. Stepped Warm Sandstone & Moss Cliff Abutment (y = -3.20 .. +0.24 m, hx ~ 2.45 m, hz ~ 2.25 m!)
    abut_secs = [
        _rect_oct(0.0, SKIRT_BOT, 0.0, 2.66, 2.44, 0.56),
        _rect_oct(0.0, -1.55,     0.0, 2.56, 2.34, 0.50),
        _rect_oct(0.0, -0.30,     0.0, 2.46, 2.24, 0.44),
        _rect_oct(0.0, ABUT_TOP,  0.0, 2.38, 2.16, 0.40),
    ]
    _loft_horizontal_masonry(
        mb, abut_secs, 'limestone_moss',
        [C_TIDE_DARK, C_LIME_SHADE, C_LIME_MID, C_LIME_WARM],
        rng, caps=(True, True), top_mat='limestone_moss', top_col=C_LIME_WARM,
    )
    for ring in abut_secs:
        base_col_pts.extend(Vector(p) for p in ring)

    # Organic sandstone cliff shoulder rocks clinging to flanks & rear edge (blends cleanly into steep cliffs!)
    for rpos, rrad, rrot in (
        ((-2.28, -0.45,  0.96), (0.86, 0.92, 0.98), ( 4,  18, -6)),
        (( 2.26, -0.48,  0.88), (0.88, 0.88, 0.94), (-5, -22,  8)),
        ((-1.92, -0.58, -1.78), (0.76, 0.78, 0.74), ( 6,  34, -4)),
        (( 1.88, -0.55, -1.74), (0.78, 0.80, 0.76), (-4, -28,  5)),
    ):
        sculpt_rock_mass(
            mb, rpos, rrad, 'limestone_moss',
            C_LIME_PALE, C_LIME_WARM, C_TIDE_DARK, rng,
            subdiv=1, warp=0.22, strata=0.14, flat_top=0.68, base_flare=0.24,
            rot_deg=rrot, crag_ribs=5, rib_amp=0.13, moss_cap=0.34,
        )

    # Dressed sandstone coping curb blocks along the abutment edge + 2-step landward approach (+Z, buried deep!)
    for sx in (-2.24, 2.24):
        cbox(mb, (sx, ABUT_TOP + 0.04, 0.0), (0.28, 0.14, 3.68), 'limestone', jit(C_LIME_PALE, rng, 0.05), 0.0)
    for sz in (-2.04, 2.04):
        cbox(mb, (0.0, ABUT_TOP + 0.04, sz), (4.06, 0.14, 0.28), 'limestone', jit(C_LIME_WARM, rng, 0.05), 0.0)
    cbox(mb, (0.0, 0.02, 2.34), (1.88, 0.48, 0.44), 'limestone_moss', C_LIME_MID, 0.0)
    cbox(mb, (0.0, -0.18, 2.68), (1.72, 0.56, 0.40), 'limestone_moss', C_LIME_SHADE, 0.0)

    # Heavy Timber Wharf-Plank Loading Platform Deck (y = 0.24 .. 0.42 m)
    for sx in (-1.75, -0.58, 0.58, 1.75):
        cbox(mb, (sx, ABUT_TOP + 0.055, -0.08), (0.18, 0.12, 3.84), 'timber', C_TIMBER_DARK, 0.0, (0, 0, 1))
    n_planks = 9
    for pi_d in range(n_planks):
        zp = -1.84 + pi_d * 0.45
        p_col = jit(C_TIMBER_HI if pi_d % 3 == 0 else (C_DRIFTWOOD if pi_d % 3 == 1 else C_TIMBER_MID), rng, 0.06)
        cbox(mb, (0.0, DECK_Y - 0.04, zp), (4.22, 0.085, 0.39), 'timber', p_col, 0.0, (1, 0, 0))
    # Front timber rub-rail & corner iron tie-plates along seaward cliff rim
    cbox(mb, (0.0, DECK_Y + 0.055, -2.02), (4.30, 0.14, 0.18), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
    for sx in (-2.06, 2.06):
        cbox(mb, (sx, DECK_Y + 0.055, -2.02), (0.22, 0.18, 0.22), 'iron', C_IRON_RUST, 0.0)
    base_col_pts.extend([Vector((-2.25, DECK_Y + 0.05, -2.10)), Vector((2.25, DECK_Y + 0.05, 2.10))])

    # 2. Stout Braced Timber A-Frame Gantry Tower (~6.22 m tall!)
    PEAK_Y = 5.95
    PEAK_Z = 0.12
    LEGS = [
        # (bot_pos, top_pos)
        (Vector((-1.54, DECK_Y - 0.08, -1.04)), Vector((-0.68, PEAK_Y, PEAK_Z - 0.14))),
        (Vector(( 1.54, DECK_Y - 0.08, -1.04)), Vector(( 0.68, PEAK_Y, PEAK_Z - 0.14))),
        (Vector((-1.54, DECK_Y - 0.08,  1.26)), Vector((-0.68, PEAK_Y, PEAK_Z + 0.14))),
        (Vector(( 1.54, DECK_Y - 0.08,  1.26)), Vector(( 0.68, PEAK_Y, PEAK_Z + 0.14))),
    ]
    for p_bot, p_top in LEGS:
        _add_beam(mb, p_bot, p_top, 0.24, 0.24, 'timber', jit(C_TIMBER_MID, rng, 0.06), 0.0)
        # Heavy bolted iron foot shoe anchoring leg cleanly to the loading deck
        cbox(mb, (p_bot.x, DECK_Y + 0.14, p_bot.z), (0.34, 0.26, 0.34), 'iron', C_IRON, 0.0)
        frame_col_pts.extend([p_bot, p_top])

    # Double heavy gantry saddle cross-beams & peaked cap roof beam (peaking at y = 6.24 m!)
    for cz_cap in (PEAK_Z - 0.16, PEAK_Z + 0.16):
        cbox(mb, (0.0, PEAK_Y + 0.04, cz_cap), (1.92, 0.22, 0.18), 'timber', C_TIMBER_HI, 0.0, (1, 0, 0))
    # Weather-shedding pitched timber gable cap atop the A-frame crown
    for sgn in (-1.0, 1.0):
        cbox(mb, (0.0, PEAK_Y + 0.24, PEAK_Z + sgn * 0.20), (1.98, 0.08, 0.56),
             'timber', C_TIMBER_DARK, 0.0, (1, 0, 0), M=R('X', sgn * 24.0))
    cbox(mb, (0.0, PEAK_Y + 0.33, PEAK_Z), (2.02, 0.08, 0.10), 'iron', C_IRON_RUST, 0.0)
    frame_col_pts.append(Vector((0.0, PEAK_Y + 0.34, PEAK_Z)))

    # Mid-level & upper gantry cross-girts + bold X-braces & iron gusset straps
    def _leg_pt(leg_idx, t):
        return LEGS[leg_idx][0].lerp(LEGS[leg_idx][1], t)

    # Lower horizontal side girts (port & starboard) + mid saddle beam supporting the boom
    for side_f, side_b in ((0, 2), (1, 3)):
        _add_beam(mb, _leg_pt(side_f, 0.44), _leg_pt(side_b, 0.44), 0.17, 0.17, 'timber', C_TIMBER_HI, 0.0)
        _add_beam(mb, _leg_pt(side_f, 0.78), _leg_pt(side_b, 0.78), 0.16, 0.16, 'timber', C_TIMBER_DARK, 0.0)
        # Side diagonal X-braces
        _add_beam(mb, _leg_pt(side_f, 0.44), _leg_pt(side_b, 0.78), 0.11, 0.11, 'timber', C_DRIFTWOOD, 0.0)
        _add_beam(mb, _leg_pt(side_b, 0.44), _leg_pt(side_f, 0.78), 0.11, 0.11, 'timber', C_DRIFTWOOD, 0.0)
    # Transverse tie beams across gantry width (front & rear at t = 0.78 + rear lower brace)
    _add_beam(mb, _leg_pt(0, 0.78), _leg_pt(1, 0.78), 0.18, 0.22, 'timber', C_TIMBER_HI, 0.0)
    _add_beam(mb, _leg_pt(2, 0.78), _leg_pt(3, 0.78), 0.18, 0.22, 'timber', C_TIMBER_HI, 0.0)
    _add_beam(mb, _leg_pt(2, 0.44), _leg_pt(3, 0.44), 0.17, 0.19, 'timber', C_TIMBER_MID, 0.0)
    # Rear X-braces for dramatic engineered carpentry silhouette
    _add_beam(mb, _leg_pt(2, 0.12), _leg_pt(3, 0.44), 0.11, 0.11, 'timber', C_TIMBER_DARK, 0.0)
    _add_beam(mb, _leg_pt(3, 0.12), _leg_pt(2, 0.44), 0.11, 0.11, 'timber', C_TIMBER_DARK, 0.0)
    # Iron corner gusset bands + hemp cross-lashings at key crown joints
    for sx in (-0.68, 0.68):
        cbox(mb, (sx, PEAK_Y - 0.04, PEAK_Z), (0.30, 0.30, 0.44), 'iron', C_IRON, 0.0)
        with xf(mb, T(sx, 4.72, PEAK_Z) @ R('X', 32.0)):
            torus(mb, 0.20, 0.036, 6, 4, 'rope', C_ROPE, False)

    # Rear Stone-Filled Timber Counterweight Ballast Crib (z = +1.15 .. +1.92 m)
    cbox(mb, (0.0, DECK_Y + 0.34, 1.54), (1.96, 0.68, 0.78), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
    for xs in (-0.98, 0.0, 0.98):
        cbox(mb, (xs, DECK_Y + 0.36, 1.54), (0.10, 0.74, 0.84), 'iron', C_IRON_RUST, 0.0)
    for bx, bz, bw, bh, bd, byaw in (
        (-0.56, 1.52, 0.56, 0.32, 0.50,  14.0),
        ( 0.02, 1.56, 0.62, 0.36, 0.54, -10.0),
        ( 0.58, 1.48, 0.54, 0.30, 0.48,  20.0),
    ):
        cbox(mb, (bx, DECK_Y + 0.72, bz), (bw, bh, bd),
             'limestone_moss', jit(C_LIME_MID, rng, 0.06), 0.0, M=R('Y', byaw) @ R('Z', rng.uniform(-6, 6)))

    # 3. Angled Overhanging Seaward Loading Boom + Iron Stays + Pulley Sheaves!
    BOOM_HEEL = Vector((0.0, 3.20, 1.56))
    BOOM_TIP  = Vector((0.0, 5.82, -3.22))
    _add_beam(mb, BOOM_HEEL, BOOM_TIP, 0.24, 0.28, 'timber', C_TIMBER_HI, 0.0)
    # Iron binding bands along the loading boom
    for bt in (0.14, 0.36, 0.68, 0.94):
        bp = BOOM_HEEL.lerp(BOOM_TIP, bt)
        b_rot = Vector((0.0, 1.0, 0.0)).rotation_difference((BOOM_TIP - BOOM_HEEL).normalized()).to_matrix().to_4x4()
        with xf(mb, T(bp) @ b_rot):
            cbox(mb, (0.0, 0.0, 0.0), (0.29, 0.14, 0.33), 'iron', C_IRON_RUST if bt > 0.6 else C_IRON, 0.0)
    # Twin inclined compression struts supporting the overhanging boom from forward A-frame legs
    boom_mid = BOOM_HEEL.lerp(BOOM_TIP, 0.72)
    _add_beam(mb, _leg_pt(0, 0.56), boom_mid + Vector((-0.10, -0.06, 0.0)), 0.14, 0.14, 'timber', C_TIMBER_MID, 0.0)
    _add_beam(mb, _leg_pt(1, 0.56), boom_mid + Vector(( 0.10, -0.06, 0.0)), 0.14, 0.14, 'timber', C_TIMBER_MID, 0.0)
    # Twin forged-iron tension stay rods from A-frame peak down to boom tip + rear tie-back to ballast crib!
    boom_tip_top = BOOM_TIP + Vector((0.0, 0.12, 0.18))
    _add_beam(mb, (-0.64, PEAK_Y + 0.06, PEAK_Z), boom_tip_top + Vector((-0.08, 0.0, 0.0)), 0.044, 0.044, 'iron', C_IRON, 0.0)
    _add_beam(mb, ( 0.64, PEAK_Y + 0.06, PEAK_Z), boom_tip_top + Vector(( 0.08, 0.0, 0.0)), 0.044, 0.044, 'iron', C_IRON, 0.0)
    _add_beam(mb, BOOM_HEEL, (0.0, DECK_Y + 0.62, 1.56), 0.18, 0.18, 'timber', C_TIMBER_DARK, 0.0)

    # Upper Tip Pulley Block + Crown Fairlead Sheave
    TIP_SHEAVE = BOOM_TIP + Vector((0.0, -0.34, 0.16))
    MID_SHEAVE = Vector((0.0, 4.46, 0.24))
    _build_pulley_block(mb, TIP_SHEAVE, radius=0.22, yaw_deg=0.0, has_hook=False)
    _build_pulley_block(mb, MID_SHEAVE, radius=0.18, yaw_deg=0.0, has_hook=False)

    # 4. Cast-Iron Geared Hand-Crank Windlass Drum (center x=0, y=1.34, z=0.42!)
    WINCH_Y = DECK_Y + 0.90
    WINCH_Z = 0.42
    for sx in (-0.82, 0.82):
        # Timber bed sill + cast-iron A-frame winch stanchion
        cbox(mb, (sx, DECK_Y + 0.09, WINCH_Z), (0.24, 0.18, 1.06), 'timber', C_TIMBER_DARK, 0.0, (0, 0, 1))
        _add_beam(mb, (sx, DECK_Y + 0.16, WINCH_Z - 0.42), (sx, WINCH_Y + 0.06, WINCH_Z), 0.09, 0.11, 'iron', C_IRON, 0.0)
        _add_beam(mb, (sx, DECK_Y + 0.16, WINCH_Z + 0.42), (sx, WINCH_Y + 0.06, WINCH_Z), 0.09, 0.11, 'iron', C_IRON, 0.0)
        with xf(mb, T(sx, WINCH_Y, WINCH_Z) @ M_Y2X):
            cyl(mb, 0.15, -0.075, 0.075, 6, 'iron', C_IRON_RUST, False, 0.0)
    # Main iron axle + ribbed wooden winch drum wrapped in coiled braided hemp rope!
    with xf(mb, T(0.0, WINCH_Y, WINCH_Z) @ M_Y2X):
        cyl(mb, 0.062, -1.16, 1.18, 6, 'iron', C_IRON, False, 0.0)
        cyl(mb, 0.23, -0.70, 0.70, 7, 'timber', C_TIMBER_MID, False, 0.0)
        for dx_fl in (-0.70, 0.70):
            cyl(mb, 0.34, dx_fl - 0.04, dx_fl + 0.04, 7, 'iron', C_IRON, False, 0.0)
        # Wrapped rope coils around the windlass barrel
        for wi in range(5):
            rx_w = -0.48 + wi * 0.24
            with xf(mb, T(0.0, rx_w, 0.0)):
                torus(mb, 0.255, 0.048, 6, 4, 'rope', mul(C_ROPE, 0.90 + 0.10 * (wi % 2)), True)
        # Toothed Cast-Iron Bull Gear (port side x = -0.96) + Brass Ratchet Hub
        with xf(mb, T(0.0, -0.96, 0.0)):
            cyl(mb, 0.42, -0.045, 0.045, 9, 'iron', C_IRON, False, 0.0)
            cyl(mb, 0.18, -0.065, 0.065, 6, 'brass', C_BRASS, False, 0.0)
            for tk in range(9):
                ang = 2.0 * pi * tk / 9.0
                cbox(mb, (cos(ang) * 0.445, 0.0, sin(ang) * 0.445),
                     (0.09, 0.075, 0.08), 'iron', C_IRON_RUST if tk % 2 == 0 else C_IRON, 0.0,
                     M=R('Y', -degrees(ang)))
        # Starboard Crank Wheel + Forged Offset Hand Crank with Turned Oak Grip!
        with xf(mb, T(0.0, 0.98, 0.0)):
            cyl(mb, 0.28, -0.04, 0.04, 7, 'iron', C_IRON, False, 0.0)
    _add_beam(mb, (1.06, WINCH_Y, WINCH_Z), (1.06, WINCH_Y + 0.46, WINCH_Z - 0.18), 0.065, 0.065, 'iron', C_IRON, 0.0)
    with xf(mb, T(1.24, WINCH_Y + 0.46, WINCH_Z - 0.18) @ M_Y2X):
        cyl(mb, 0.046, -0.18, 0.18, 6, 'timber', C_OAK_FRESH, False, 0.0)
        cyl(mb, 0.056, -0.18, -0.13, 6, 'brass', C_BRASS, False, 0.0)

    # 5. Taut Hemp Pulley Hoist Line + Suspended Cargo Crate & Lashed Rum Barrel (Subtle UV2 Sway!)
    HOOK_Y = 3.22
    CARGO_Z = TIP_SHEAVE.z
    # Static tension run: winch drum -> crown fairlead -> boom tip sheave
    tube(mb, [
        (0.0, WINCH_Y + 0.26, WINCH_Z - 0.06),
        (0.0, MID_SHEAVE.y - 0.14, MID_SHEAVE.z + 0.08),
        (0.0, TIP_SHEAVE.y + 0.14, TIP_SHEAVE.z + 0.14),
    ], 0.032, 5, 'rope', C_ROPE, caps=(True, True), mode='flat')
    # Hanging vertical drop line from tip sheave down to lower cargo pulley hook (baked UV2 subtle pendulum sway!)
    n_drop = 5
    drop_pts = [Vector((0.0, TIP_SHEAVE.y - 0.18 - (TIP_SHEAVE.y - 0.18 - HOOK_Y) * (i / float(n_drop - 1)), CARGO_Z))
                for i in range(n_drop)]
    drop_uv2 = [((i / float(n_drop - 1)) * 0.24, 0.18) for i in range(n_drop)]
    tube(mb, drop_pts, 0.032, 5, 'rope', C_ROPE, caps=(True, True), mode='flat', suv2=drop_uv2)

    # Lower travelling pulley block + forged cargo hook
    _build_pulley_block(mb, (0.0, HOOK_Y, CARGO_Z), radius=0.17, yaw_deg=90.0, has_hook=True, uv2_w=0.24)

    # Suspended Timber Cargo Sling Pallet cradling 1 Stenciled Crate + 1 Lashed Rum Barrel (y = 1.68 .. 2.55 m)
    HOOK_EYE = Vector((0.0, HOOK_Y - 0.40, CARGO_Z))
    PALLET_Y = 1.72
    cbox(mb, (0.0, PALLET_Y, CARGO_Z), (1.36, 0.09, 0.88), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
    for sx_p in (-0.54, 0.54):
        cbox(mb, (sx_p, PALLET_Y - 0.06, CARGO_Z), (0.12, 0.07, 0.86), 'timber', C_TIMBER_MID, 0.0, (0, 0, 1))
    # 4 taut sling ropes from pallet corners converging cleanly into the iron cargo hook (subtle UV2 sway!)
    for sx_s in (-0.64, 0.64):
        for sz_s in (-0.40, 0.40):
            p_corn = Vector((sx_s, PALLET_Y + 0.04, CARGO_Z + sz_s))
            tube(mb, [HOOK_EYE, HOOK_EYE.lerp(p_corn, 0.52), p_corn], 0.024, 4, 'rope', C_ROPE,
                 caps=(True, True), mode='flat', suv2=[(0.24, 0.18), (0.28, 0.18), (0.30, 0.18)])
    # Stenciled Pirate Cargo Crate + Lashed Coopered Rum Barrel riding the suspended sling!
    _build_stenciled_crate(
        mb, T(-0.28, PALLET_Y + 0.36, CARGO_Z + 0.02) @ R('Y', 10.0),
        size=(0.68, 0.62, 0.64), rng=rng, stripe_col=C_CRIMSON_HI, stencil_col=C_CANVAS_CREAM,
    )
    _build_coopered_cask(
        mb, T(0.36, PALLET_Y + 0.36, CARGO_Z - 0.02) @ R('Y', -14.0) @ R('Z', -7.0),
        radius=0.27, height=0.66, rng=rng, col_a=C_TIMBER_HI, col_b=C_OAK_FRESH,
        segs=6, stripe_col=C_TEAL_BRIGHT,
    )
    # Horizontal hemp lashing belt binding crate & barrel tightly together on the sling
    with xf(mb, T(0.04, PALLET_Y + 0.38, CARGO_Z) @ S(1.12, 1.0, 0.66)):
        torus(mb, 0.62, 0.028, 6, 4, 'rope', C_ROPE, True)

    # 6. Rusted Cast-Iron Mooring Bollard, Coiled Mooring Rope & Deck Cargo Props
    BOL_X, BOL_Z = -1.66, -1.62
    with xf(mb, T(BOL_X, DECK_Y, BOL_Z)):
        cbox(mb, (0.0, 0.03, 0.0), (0.50, 0.06, 0.50), 'iron', C_IRON_RUST, 0.0)
        cyl(mb, 0.15, 0.05, 0.54, 6, 'iron', C_IRON_RUST, False, 0.0, 0.13)
        cyl(mb, 0.21, 0.50, 0.60, 6, 'iron', C_IRON, False, 0.0, 0.17)
        cbox(mb, (0.0, 0.42, 0.0), (0.52, 0.075, 0.075), 'iron', C_IRON, 0.0)
        # Mooring hawser turns wrapped around the bollard neck
        for ri in range(2):
            with xf(mb, T(0.0, 0.16 + ri * 0.085, 0.0)):
                torus(mb, 0.175, 0.036, 6, 4, 'rope', C_ROPE, True)
    # Chunky coiled mooring rope on deck right beside the bollard + rope tail connecting to bollard!
    _build_rope_coil_lean(mb, (-1.04, DECK_Y + 0.01, -1.48), radius=0.30, turns=3, r=0.038, segs=6, psegs=4)
    tube(mb, [(BOL_X + 0.16, DECK_Y + 0.14, BOL_Z + 0.04), (-1.34, DECK_Y + 0.05, -1.56), (-1.06, DECK_Y + 0.05, -1.48)],
         0.030, 4, 'rope', C_ROPE, mode='flat')

    # Spare starboard deck cargo barrel & small nailed crate
    _build_coopered_cask(
        mb, T(1.66, DECK_Y + 0.36, -1.36) @ R('Y', 24.0),
        radius=0.28, height=0.70, rng=rng, col_a=C_TIMBER_MID, col_b=C_DRIFTWOOD, segs=6, stripe_col=C_CRIMSON_HI,
    )

    # 7. Hanging Brass Storm Lantern on Port Forward A-Frame Bracket ('Lantern_FerryWinch'!)
    BRACK_ROOT = _leg_pt(0, 0.56)
    LANTERN_HOOK = BRACK_ROOT + Vector((-0.56, 0.14, -0.34))
    LANTERN_POS  = LANTERN_HOOK + Vector((0.0, -0.44, 0.0))
    _add_beam(mb, BRACK_ROOT, LANTERN_HOOK, 0.052, 0.052, 'iron', C_IRON, 0.0)
    _add_beam(mb, BRACK_ROOT + Vector((0.0, -0.34, 0.0)), BRACK_ROOT.lerp(LANTERN_HOOK, 0.68),
              0.040, 0.040, 'iron', C_IRON_RUST, 0.0)
    _build_storm_lantern(mb, LANTERN_POS, scale=1.18, brass_cage=True, hanging=True)

    # 8. Trailing Sea-Ivy Fronds & Coastal Cliff Ferns ('foliage' + UV2!)
    LEG_VINE_ANC = _leg_pt(0, 0.42) + Vector((-0.08, 0.0, -0.06))
    for v_anc, v_len, v_w, v_dir, v_ph in (
        ((-2.28, ABUT_TOP + 0.04, -1.10), 2.15, 0.24, (-0.85, 0.0, -0.52), 0.11),
        (( 2.28, ABUT_TOP + 0.04, -1.16), 2.05, 0.24, ( 0.85, 0.0, -0.52), 0.37),
        ((-0.68, ABUT_TOP + 0.02, -2.14), 1.90, 0.22, (-0.18, 0.0, -0.98), 0.59),
        (( 0.82, ABUT_TOP + 0.02, -2.14), 1.75, 0.22, ( 0.22, 0.0, -0.97), 0.82),
        (LEG_VINE_ANC,                    1.85, 0.20, (-0.75, 0.0, -0.66), 0.24),
    ):
        _add_leafy_vine_drape(mb, v_anc, v_len, v_w, v_dir, rng, phase=v_ph)
    for fp, fsc, fph, fln in (
        ((-2.14, ABUT_TOP + 0.08,  1.42), 0.78, 0.16, (-0.8, 0.0,  0.6)),
        (( 2.12, ABUT_TOP + 0.08,  1.46), 0.74, 0.63, ( 0.8, 0.0,  0.6)),
        (( 2.18, ABUT_TOP + 0.06, -0.25), 0.70, 0.44, ( 1.0, 0.0, -0.2)),
    ):
        _add_coastal_fern_cluster(mb, fp, scale=fsc, n_fronds=4, rng=rng, phase=fph, lean_dir=fln)

    build(mb)

    add_empty('Lantern_FerryWinch', LANTERN_POS)
    col_piece('col_ferry_base', base_col_pts)
    col_piece('col_ferry_frame', frame_col_pts)
    export_landmark_glb(outdir, 'coastal_rope_ferry_pulley.glb')


# ================================================================ 2. ANCIENT SUNKEN BELL SHRINE

def gen_ancient_sunken_bell_shrine(outdir):
    """Mossy coral-and-barnacle-crusted carved temple stone bell arch (~6.25 m tall) rising from a
    deeply skirted stepped limestone tidal reef plinth plunging cleanly to y = -3.40 m (r ~ 2.65 m).
    Twin weathered relief-carved stone bell pillars bridged by an ornate stepped stone architrave,
    suspending a large detailed verdigris-patina cast-bronze cathedral sea bell ('brass' tinted
    green-gold via linear COLOR_0) hung from heavy iron yoke straps + forged pull-chain, glowing
    turquoise tidal rune basin at base ('skull_glow' + 'Lantern_BellShrine'), coral/barnacle crusts,
    and swaying clinging sea-kelp & ivy vines ('foliage' + UV2).
    Target: 3,000-3,700 visual tris, 1 collider (col_bellshrine_base).
    """
    clear_scene()
    rng = random.Random(SEED + 2719)
    mb = MB('AncientSunkenBellShrine', seed=2719)

    SKIRT_BOT = -3.40
    DAIS_Y1 = 0.28
    DAIS_Y2 = 0.56
    col_pts = []

    # 1. Stepped Limestone Tidal Reef Plinth plunging cleanly to y = -3.40 m (radius ~ 2.65 m!)
    reef_secs = [
        _reg_poly(0.0, SKIRT_BOT, 0.0, 2.86, sides=10, rot_deg=18.0),
        _reg_poly(0.0, -1.60,     0.0, 2.72, sides=10, rot_deg=18.0),
        _reg_poly(0.0, -0.15,     0.0, 2.58, sides=10, rot_deg=18.0),
        _reg_poly(0.0, DAIS_Y1,   0.0, 2.44, sides=10, rot_deg=18.0),
    ]
    _loft_horizontal_masonry(
        mb, reef_secs, 'limestone_moss',
        [C_TIDE_DARK, mix(C_LIME_DARK, C_SEA_MOSS, 0.52), mix(C_LIME_SHADE, C_SEA_MOSS, 0.30), C_LIME_MID],
        rng, caps=(True, True), top_mat='limestone_moss', top_col=mix(C_LIME_MID, C_LEDGE_MOSS, 0.32),
    )
    for ring in reef_secs:
        col_pts.extend(Vector(p) for p in ring)

    # Carved octagonal stepped temple shrine dais atop the tidal reef
    dais_secs = [
        _reg_poly(0.0, DAIS_Y1 - 0.04, 0.0, 2.16, sides=8, rot_deg=22.5),
        _reg_poly(0.0, DAIS_Y2,        0.0, 2.02, sides=8, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, dais_secs, 'temple_stone',
        [C_TEMPLE_DARK, C_TEMPLE_MID],
        rng, caps=(False, True), top_mat='temple_stone', top_col=C_TEMPLE_HI,
    )
    # Seaward & landward carved stone ritual approach steps
    for sz in (-1.0, 1.0):
        cbox(mb, (0.0, DAIS_Y1 + 0.12, sz * 2.04), (1.42, 0.26, 0.44), 'temple_stone', C_TEMPLE_MID, 0.0)

    # Sculpted tidal reef boulders & vibrant sea-coral / barnacle encrustations around the tide-line!
    for rp, rr, rrot in (
        ((-2.22, -0.18, -1.12), (0.78, 0.68, 0.72), ( 6,  24, -5)),
        (( 2.24, -0.22, -1.06), (0.80, 0.66, 0.74), (-5, -18,  6)),
        ((-2.16, -0.16,  1.22), (0.82, 0.70, 0.76), ( 4,  38, -7)),
        (( 2.18, -0.14,  1.18), (0.76, 0.68, 0.72), (-6, -32,  5)),
    ):
        sculpt_rock_mass(
            mb, rp, rr, 'limestone_moss',
            C_LIME_WARM, C_LIME_SHADE, C_TIDE_DARK, rng,
            subdiv=1, warp=0.22, strata=0.14, flat_top=0.66, base_flare=0.22,
            rot_deg=rrot, crag_ribs=5, rib_amp=0.14, moss_cap=0.45,
        )

    # Coral branch fans & ivory barnacle clusters encrusting the wet limestone plinth & lower pillar bases!
    coral_clusters = [
        ((-1.92, DAIS_Y1 + 0.14, -1.16), C_CORAL_PINK,  1.00,  22.0),
        (( 1.98, DAIS_Y1 + 0.12, -1.04), C_CORAL_OCHRE, 0.94, -34.0),
        ((-1.86, DAIS_Y1 + 0.16,  1.18), C_CORAL_OCHRE, 0.92,  46.0),
        (( 1.90, DAIS_Y1 + 0.12,  1.12), C_CORAL_PINK,  1.04, -18.0),
        ((-1.32, DAIS_Y2 + 0.16, -0.58), C_CORAL_PINK,  0.76,  12.0),
        (( 1.38, DAIS_Y2 + 0.18,  0.54), C_CORAL_OCHRE, 0.74, -26.0),
    ]
    for cp, ccol, csc, cyaw in coral_clusters:
        with xf(mb, T(cp) @ R('Y', cyaw)):
            for bk, (bx, bz, bh, btx, btz) in enumerate((
                ( 0.00,  0.00, 0.44 * csc,  10.0,  -8.0),
                (-0.14,  0.06, 0.34 * csc, -24.0,  16.0),
                ( 0.15, -0.05, 0.32 * csc,  26.0, -14.0),
            )):
                with xf(mb, T(bx * csc, 0.0, bz * csc) @ R('X', btx) @ R('Z', btz)):
                    cyl(mb, 0.078 * csc, -0.06, bh, 5, 'limestone', jit(ccol, rng, 0.06), False, 0.0, 0.032 * csc)
    # Pale crusty barnacle cones clustered on the wet tide-line masonry
    for bp in (
        (-1.62, DAIS_Y2 + 0.36, -0.44), (-1.40, DAIS_Y2 + 0.56, -0.48),
        ( 1.62, DAIS_Y2 + 0.34, -0.42), ( 1.44, DAIS_Y2 + 0.62,  0.46),
        (-1.58, DAIS_Y2 + 0.42,  0.44), ( 1.60, DAIS_Y2 + 0.38,  0.42),
    ):
        for k_b in range(2):
            ox = rng.uniform(-0.11, 0.11)
            oz = rng.uniform(-0.11, 0.11)
            br = rng.uniform(0.068, 0.102)
            with xf(mb, T(bp[0] + ox, bp[1] + rng.uniform(-0.06, 0.06), bp[2] + oz) @ R('Z', rng.uniform(-18, 18))):
                cyl(mb, br, -0.04, br * 0.95, 5, 'skull_stone', C_BARNACLE_PALE, False, 0.0, br * 0.34)

    # 2. Twin Weathered Relief-Carved Stone Bell Pillars (x = ±1.44 m, y = 0.56 .. 5.06 m!)
    PILLAR_X = 1.44
    LINTEL_Y = 5.06
    for sx in (-1.0, 1.0):
        px = sx * PILLAR_X
        # Heavy stepped stone plinth base
        pbase_secs = [
            _rect_oct(px, DAIS_Y2 - 0.06, 0.0, 0.58, 0.62, 0.14),
            _rect_oct(px, DAIS_Y2 + 0.68, 0.0, 0.52, 0.56, 0.12),
        ]
        _loft_horizontal_masonry(
            mb, pbase_secs, 'temple_stone', [C_TEMPLE_DARK, C_TEMPLE_MID], rng, caps=(False, True),
        )
        # Main tapered carved ashlar bell pillar shaft (y = 1.24 .. 4.62 m)
        shaft_secs = [
            _rect_oct(px, DAIS_Y2 + 0.66, 0.0, 0.44, 0.48, 0.10),
            _rect_oct(px, 2.85,           0.0, 0.41, 0.45, 0.10),
            _rect_oct(px, 4.64,           0.0, 0.39, 0.43, 0.10),
        ]
        _loft_horizontal_masonry(
            mb, shaft_secs, 'temple_stone', [C_TEMPLE_MID, C_TEMPLE_HI, C_TEMPLE_MID], rng, caps=(False, True),
        )
        # Sculpted carved relief stone collar bands & vertical fluted pilasters on seaward/landward faces
        for ry in (1.72, 2.95, 4.18):
            cbox(mb, (px, ry, 0.0), (0.96, 0.16, 1.04), 'temple_stone', jit(C_TEMPLE_HI, rng, 0.05), 0.0)
        for fz in (-0.47, 0.47):
            cbox(mb, (px, 2.95, fz), (0.48, 2.16, 0.06), 'temple_stone', C_TEMPLE_DARK, 0.0)
            # Subtle glowing carved sea-rune vertical glyph recessed into the pillar relief!
            cbox(mb, (px, 2.95, fz + (-0.025 if fz < 0 else 0.025)),
                 (0.08, 1.44, 0.03), 'skull_glow', C_RUNE_MID, 0.0)
            cbox(mb, (px, 2.95, fz + (-0.030 if fz < 0 else 0.030)),
                 (0.24, 0.24, 0.03), 'skull_glow', C_RUNE_CORE, 0.0, M=R('Z', 45.0))
        # Ornate flared stepped corbel capital (y = 4.62 .. 5.08 m)
        cbox(mb, (px, 4.74, 0.0), (1.02, 0.22, 1.10), 'temple_stone', C_TEMPLE_HI, 0.0)
        cbox(mb, (px, 4.96, 0.0), (1.20, 0.22, 1.24), 'temple_stone', C_TEMPLE_MID, 0.0)
        # Inner carved arch corbel bracket curving inward toward the bell bay
        _add_beam(mb, (px - sx * 0.36, 4.30, 0.0), (px - sx * 0.68, 4.96, 0.0),
                  0.26, 0.54, 'temple_stone', C_TEMPLE_HI, 0.0)
        col_pts.append(Vector((px, LINTEL_Y + 0.55, 0.0)))

    # 3. Ornate Stepped Stone Architrave & Carved Sea-Temple Pediment Crown (y = 5.06 .. 6.26 m!)
    cbox(mb, (0.0, LINTEL_Y + 0.22, 0.0), (4.24, 0.44, 1.18), 'temple_stone', C_TEMPLE_MID, 0.0)
    # Projecting weathered cornice molding + relief dentil blocks
    cbox(mb, (0.0, LINTEL_Y + 0.52, 0.0), (4.54, 0.18, 1.38), 'temple_stone', C_TEMPLE_HI, 0.0)
    for dx in (-1.80, -1.20, -0.60, 0.0, 0.60, 1.20, 1.80):
        for fz in (-0.64, 0.64):
            cbox(mb, (dx, LINTEL_Y + 0.40, fz), (0.20, 0.14, 0.14), 'temple_stone', C_TEMPLE_DARK, 0.0)
    # Stepped carved sanctuary gable pediment crowning center (peaking ~6.26 m)
    cbox(mb, (0.0, LINTEL_Y + 0.76, 0.0), (2.78, 0.34, 1.04), 'temple_stone', C_TEMPLE_MID, 0.0)
    cbox(mb, (0.0, LINTEL_Y + 1.04, 0.0), (1.56, 0.28, 0.86), 'temple_stone', C_TEMPLE_HI, 0.0)
    sculpt_stone_block(mb, (0.0, LINTEL_Y + 1.24, 0.0), (0.76, 0.30, 0.64),
                       'temple_stone', C_TEMPLE_HI, rng, chip=0.04, moss_col=C_LEDGE_MOSS)
    # Corner temple scroll acroteria finials (one intact, one chipped/tilted for ancient charm!)
    sculpt_stone_block(mb, (-1.94, LINTEL_Y + 0.80, 0.0), (0.50, 0.46, 0.56),
                       'temple_stone', C_TEMPLE_MID, rng, chip=0.04, M=R('Z', 6.0), moss_col=C_LEDGE_MOSS)
    sculpt_stone_block(mb, ( 1.92, LINTEL_Y + 0.76, 0.0), (0.48, 0.38, 0.52),
                       'temple_stone', C_TEMPLE_MID, rng, chip=0.05, M=R('Z', -11.0), moss_col=C_LEDGE_MOSS)
    # Carved verdigris-brass circular tidal medallion centered on both architrave faces!
    for fz in (-0.62, 0.62):
        with xf(mb, T(0.0, LINTEL_Y + 0.22, fz) @ M_Y2Z):
            cyl(mb, 0.30, -0.04, 0.04, 8, 'brass', C_VERDIGRIS_HI, False, 0.0)
            cyl(mb, 0.14, -0.055, 0.055, 6, 'skull_glow', C_RUNE_CORE, False, 0.0)

    # 4. Large Detailed Verdigris-Patina Cast-Bronze Cathedral Sea Bell ('brass' tinted green-gold!)
    #    Suspended cleanly beneath the stone architrave via heavy oak yoke & forged-iron straps!
    BELL_TOP_Y = 4.38
    BELL_MOUTH_Y = 2.74
    YOKE_Y = 4.64

    # Heavy weathered timber headstock yoke & twin iron suspension hanger straps bolted into the lintel!
    cbox(mb, (0.0, YOKE_Y, 0.0), (1.76, 0.28, 0.34), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
    for sx in (-0.82, 0.82):
        _add_beam(mb, (sx, YOKE_Y - 0.12, 0.0), (sx, LINTEL_Y + 0.08, 0.0), 0.11, 0.16, 'iron', C_IRON, 0.0)
        cbox(mb, (sx, YOKE_Y, 0.0), (0.16, 0.34, 0.40), 'iron', C_IRON_RUST, 0.0)
    # Iron U-strap clamps wrapping the yoke & bell crown cannons
    for sx in (-0.34, 0.0, 0.34):
        cbox(mb, (sx, YOKE_Y, 0.0), (0.09, 0.36, 0.40), 'iron', C_IRON, 0.0)
        _add_beam(mb, (sx, BELL_TOP_Y - 0.06, 0.0), (sx, YOKE_Y + 0.08, 0.0), 0.075, 0.12, 'iron', C_IRON_RUST, 0.0)

    # Lathe-sculpted cathedral sea bell profile with hollowed inner chamber & bold sound-bow lip!
    # Profile ordered outward-wound (bottom inner apex -> inner skirt -> lip -> outer flared bow -> waist -> shoulder -> crown)
    bell_prof = [
        (0.00, BELL_TOP_Y - 0.18),  # 0: inner ceiling
        (0.32, BELL_TOP_Y - 0.24),  # 1: inner upper waist
        (0.42, 3.55),               # 2: inner mid waist
        (0.68, BELL_MOUTH_Y + 0.04),# 3: inner mouth bevel
        (0.80, BELL_MOUTH_Y),       # 4: bold flared sound-bow rim
        (0.75, BELL_MOUTH_Y + 0.16),# 5: sound-bow bead
        (0.56, 3.24),               # 6: lower concave waist
        (0.46, 3.74),               # 7: upper concave waist
        (0.42, 4.14),               # 8: shoulder curve
        (0.28, BELL_TOP_Y - 0.04),  # 9: crown top
        (0.00, BELL_TOP_Y),         # 10: crown center
    ]
    def _bell_patina(i, k):
        # Rich Sea-of-Thieves verdigris-patina cast bronze: sea-green verdigris on shoulder/crown,
        # weathered antique bronze waist, gleaming burnished gold along the raised sound-bow lip!
        if i <= 2:
            return C_VERDIGRIS_DK
        if i in (3, 4):
            return jit(C_BRONZE_SHINE if k % 2 == 0 else C_BRONZE_MID, rng, 0.04)
        if i == 5:
            return jit(mix(C_BRONZE_MID, C_VERDIGRIS_HI, 0.42), rng, 0.05)
        if i == 6:
            return jit(mix(C_BRONZE_MID, C_VERDIGRIS_MID, 0.56), rng, 0.05)
        if i == 7:
            return jit(mix(C_VERDIGRIS_MID, C_VERDIGRIS_HI, 0.52), rng, 0.05)
        return jit(C_VERDIGRIS_HI if k % 2 == 0 else C_VERDIGRIS_MID, rng, 0.05)

    lathe(mb, bell_prof, 14, 'brass', C_VERDIGRIS_MID, smooth=True, sp=False, colfn=_bell_patina)
    # Raised cast-bronze decorative relief rings encircling the bell shoulder & sound bow
    for ry, rr, rc in ((4.08, 0.435, C_BRONZE_SHINE), (3.18, 0.585, C_VERDIGRIS_HI), (2.94, 0.755, C_BRONZE_SHINE)):
        with xf(mb, T(0.0, ry, 0.0)):
            torus(mb, rr, 0.032, 12, 4, 'brass', rc, True)
    # Heavy Forged-Iron Bell Clapper Stem & Ball hanging cleanly inside the bronze mouth!
    _add_beam(mb, (0.0, BELL_TOP_Y - 0.16, 0.0), (0.04, BELL_MOUTH_Y - 0.14, -0.04), 0.058, 0.058, 'iron', C_IRON, 0.0)
    with xf(mb, T(0.04, BELL_MOUTH_Y - 0.14, -0.04)):
        lathe(mb, [(0.0, -0.14), (0.125, -0.07), (0.14, 0.0), (0.12, 0.08), (0.0, 0.14)],
              8, 'iron', C_IRON_RUST, False)

    # Starboard Bell Lever Arm + Tightly Interlocked Forged-Iron Pull-Chain down to reachable bronze pull-ring!
    LEVER_TIP = Vector((0.82, YOKE_Y - 0.06, -0.32))
    _add_beam(mb, (0.58, YOKE_Y, 0.0), LEVER_TIP, 0.085, 0.085, 'iron', C_IRON, 0.0)
    RING_POS = Vector((0.86, 1.92, -0.42))
    _add_chain_links(mb, LEVER_TIP, RING_POS, n_links=9, link_r=0.148, wire_r=0.044,
                     segs=5, psegs=4, sag=0.12, mat='iron', rust_stride=2, stretch_y=1.42)
    with xf(mb, T(RING_POS) @ M_Y2Z):
        torus(mb, 0.145, 0.034, 7, 4, 'brass', C_BRONZE_SHINE, False)

    # 5. Glowing Turquoise Tidal Rune Basin at Base ('skull_glow' + 'Lantern_BellShrine'!)
    BASIN_Y = DAIS_Y2
    LANTERN_POS = Vector((0.0, BASIN_Y + 0.96, 0.0))
    with xf(mb, T(0.0, BASIN_Y, 0.0)):
        basin_prof = [
            (0.00, 0.00), (0.54, 0.00), (0.42, 0.16), (0.34, 0.44),
            (0.68, 0.66), (0.76, 0.84), (0.64, 0.86), (0.54, 0.68), (0.00, 0.62),
        ]
        lathe(mb, basin_prof, 8, 'temple_stone', C_TEMPLE_MID, False, False,
              lambda i, k: C_TEMPLE_HI if i in (4, 5) else C_TEMPLE_DARK)
        # Verdigris brass collar ring embracing the tidal basin lip
        with xf(mb, T(0.0, 0.82, 0.0)):
            torus(mb, 0.74, 0.036, 8, 4, 'brass', C_VERDIGRIS_HI, False)
        # Glowing turquoise tidal rune pool surface ('skull_glow'!) + central crystal spire cluster
        cyl(mb, 0.56, 0.62, 0.74, 8, 'skull_glow', C_RUNE_MID, False, 0.0, 0.58)
        cyl(mb, 0.34, 0.72, 0.78, 8, 'skull_glow', C_RUNE_CORE, False, 0.0, 0.28)
        for cx_c, cz_c, ch_c, cr_c, ct_x, ct_z in (
            ( 0.00,  0.00, 0.38, 0.11,  4.0, -5.0),
            (-0.24, -0.18, 0.24, 0.075,-18.0, 14.0),
            ( 0.26, -0.14, 0.22, 0.070, 16.0,-16.0),
            ( 0.08,  0.24, 0.25, 0.072,-14.0,-18.0),
        ):
            with xf(mb, T(cx_c, 0.70, cz_c) @ R('X', ct_x) @ R('Z', ct_z)):
                lathe(mb, [(0.0, -0.06), (cr_c, 0.08), (cr_c * 0.78, ch_c * 0.65), (0.0, ch_c)],
                      5, 'skull_glow', C_RUNE_CORE if ch_c > 0.30 else C_RUNE_MID, False)

    # 4 Glowing Carved Tidal Rune Inlays embedded flush in the temple dais floor
    for rk in range(4):
        ang = radians(45.0 + rk * 90.0)
        cbox(mb, (cos(ang) * 1.24, DAIS_Y2 + 0.02, sin(ang) * 1.24),
             (0.24, 0.04, 0.24), 'skull_glow', C_RUNE_CORE, 0.0, M=R('Y', -degrees(ang) + 45.0))

    # 6. Clinging Sea-Kelp & Coastal Ivy Vines ('foliage' + UV2 wind sway, rooted flush into masonry!)
    for v_anc, v_len, v_w, v_dir, v_ph in (
        ((-1.82, 4.92, -0.44), 2.45, 0.25, (-0.76, 0.0, -0.65), 0.10),
        (( 1.82, 4.90, -0.44), 2.35, 0.24, ( 0.76, 0.0, -0.65), 0.34),
        ((-1.80, 4.88,  0.46), 2.20, 0.24, (-0.72, 0.0,  0.69), 0.58),
        (( 1.82, 4.90,  0.46), 2.30, 0.24, ( 0.72, 0.0,  0.69), 0.81),
        ((-0.86, LINTEL_Y + 0.02, -0.44), 1.55, 0.20, (-0.28, 0.0, -0.96), 0.22),
        (( 0.86, LINTEL_Y + 0.02,  0.44), 1.50, 0.20, ( 0.30, 0.0,  0.95), 0.67),
    ):
        _add_leafy_vine_drape(mb, v_anc, v_len, v_w, v_dir, rng, phase=v_ph,
                              c_dark=C_KELP_DARK, c_mid=C_KELP_MID, c_sun=C_KELP_TIP)

    for kp, ksc, kph, kln in (
        ((-2.06, DAIS_Y1 + 0.08, -0.04), 0.90, 0.15, (-1.0, 0.0,  0.0)),
        (( 2.08, DAIS_Y1 + 0.08,  0.08), 0.88, 0.48, ( 1.0, 0.0,  0.0)),
        ((-1.32, DAIS_Y1 + 0.06, -1.78), 0.80, 0.72, (-0.6, 0.0, -0.8)),
        (( 1.38, DAIS_Y1 + 0.06,  1.76), 0.82, 0.91, ( 0.6, 0.0,  0.8)),
    ):
        _add_coastal_fern_cluster(mb, kp, scale=ksc, n_fronds=4, rng=rng, phase=kph, lean_dir=kln,
                                  c_dark=C_KELP_DARK, c_mid=C_KELP_MID, c_tip=C_KELP_TIP)

    build(mb)

    add_empty('Lantern_BellShrine', LANTERN_POS)
    col_piece('col_bellshrine_base', col_pts)
    export_landmark_glb(outdir, 'ancient_sunken_bell_shrine.glb')


# ================================================================ 3. PIRATE MAP PLANNING TABLE TENT

def _build_banded_chest(mb, M_chest, open_deg=18.0, rng=None):
    """Compact ornate iron-banded oak treasure chest with vaulted lid, brass lock & glinting coins."""
    w, h, d = 0.96, 0.50, 0.60
    hw, hh, hd = w * 0.5, h * 0.5, d * 0.5
    with xf(mb, M_chest):
        if open_deg > 2.0:
            cbox(mb, (0.0, 0.06, 0.0), (w - 0.04, 0.12, d - 0.04), 'timber', C_TIMBER_DARK, 0.0)
            cbox(mb, (0.0, hh, -hd + 0.04), (w, h, 0.08), 'timber', C_TIMBER_MID, 0.0, (1, 0, 0))
            cbox(mb, (0.0, hh,  hd - 0.04), (w, h, 0.08), 'timber', C_TIMBER_MID, 0.0, (1, 0, 0))
            cbox(mb, (-hw + 0.04, hh, 0.0), (0.08, h, d - 0.14), 'timber', C_TIMBER_MID, 0.0, (0, 0, 1))
            cbox(mb, ( hw - 0.04, hh, 0.0), (0.08, h, d - 0.14), 'timber', C_TIMBER_MID, 0.0, (0, 0, 1))
            # Glinting gold coin mound nestled inside the cracked-open chest!
            cyl(mb, hw * 0.72, h * 0.52, h * 0.96, 7, 'brass', C_GOLD_BRIGHT, False, 0.0, hw * 0.42)
        else:
            cbox(mb, (0.0, hh, 0.0), (w, h, d), 'timber', C_TIMBER_MID, 0.0, (1, 0, 0))
        for xs in (-hw + 0.04, 0.0, hw - 0.04):
            cbox(mb, (xs, hh, -hd - 0.012), (0.072, h + 0.02, 0.028), 'iron', C_IRON, 0.0)
            cbox(mb, (xs, hh,  hd + 0.012), (0.072, h + 0.02, 0.028), 'iron', C_IRON, 0.0)
        cbox(mb, (0.0, h - 0.12, -hd - 0.028), (0.18, 0.20, 0.028), 'brass', C_GOLD_BRIGHT, 0.0)
        # Vaulted barrel lid pivoting smoothly around rear hinge (z = +hd)
        lid_M = T(0.0, h, hd) @ R('X', open_deg) @ T(0.0, 0.0, -hd)
        with xf(mb, lid_M):
            r_lid = hd * 1.02
            lid_ring = [(cos(pi * k / 4.0) * r_lid, sin(pi * k / 4.0) * 0.24) for k in range(5)]
            secs = [
                [Vector((-hw - 0.02, py, -pz)) for pz, py in lid_ring] + [Vector((-hw - 0.02, 0.0, -hd))],
                [Vector(( hw + 0.02, py, -pz)) for pz, py in lid_ring] + [Vector(( hw + 0.02, 0.0, -hd))],
            ]
            loft(mb, secs, 'timber', C_TIMBER_HI, closed=True, caps=(True, True), mode='flat')
            for xs in (-hw + 0.04, 0.0, hw - 0.04):
                rib_pts = [Vector((xs, sin(pi * k / 4.0) * 0.265, -cos(pi * k / 4.0) * (r_lid + 0.02)))
                           for k in range(5)]
                tube(mb, rib_pts, 0.030, 4, 'iron', C_IRON, mode='flat')


def gen_pirate_map_planning_table_tent(outdir):
    """Captain's open-air war-table pavilion grounded on a deeply skirted cobbled stone & driftwood
    terrace plinth plunging cleanly to y = -2.80 m (hx = 2.60 m, hz = 2.30 m).
    Four timber & driftwood corner posts lashed with hemp rope supporting a gracefully draped,
    wind-billowed patched crimson-and-cream striped sailcloth awning canopy ('paint' + UV2 wind
    weights along outer skirt + fluttering pirate swallowtail pennant!), stout plank-and-trestle
    oak war table topped with a sculpted vertex-painted archipelago parchment chart, brass spyglass,
    brass dividers/sextant, steel cutlass pinning the map, wooden grog tankard, lashed oak supply
    cask & banded treasure chest beside the table, and warm brass lantern ('Lantern_MapTent') above!
    Target: 3,000-3,700 visual tris, 1 collider (col_maptent_base).
    """
    clear_scene()
    rng = random.Random(SEED + 2737)
    mb = MB('PirateMapPlanningTableTent', seed=2737)

    SKIRT_BOT = -2.80
    FLOOR_Y = 0.18
    col_pts = []

    # 1. Deeply Skirted Cobbled Stone & Driftwood Terrace Plinth (y = -2.80 .. +0.18 m, hx ~ 2.60, hz ~ 2.30!)
    plinth_secs = [
        _rect_oct(0.0, SKIRT_BOT, 0.0, 2.76, 2.46, 0.56),
        _rect_oct(0.0, -1.10,     0.0, 2.66, 2.36, 0.50),
        _rect_oct(0.0, FLOOR_Y,   0.0, 2.56, 2.26, 0.44),
    ]
    _loft_horizontal_masonry(
        mb, plinth_secs, 'limestone_moss',
        [C_TIDE_DARK, C_COBBLE_DARK, C_COBBLE_MID],
        rng, caps=(True, True), top_mat='limestone_moss', top_col=C_COBBLE_MID,
    )
    for ring in plinth_secs:
        col_pts.extend(Vector(p) for p in ring)

    # Weathered driftwood edge-curb timbers framing the cobbled pavilion terrace + proud flagstones!
    for sx in (-2.38, 2.38):
        cbox(mb, (sx, FLOOR_Y + 0.04, 0.0), (0.22, 0.14, 3.66), 'timber', C_DRIFTWOOD, 0.0, (0, 0, 1))
    for sz in (-2.08, 2.08):
        cbox(mb, (0.0, FLOOR_Y + 0.04, sz), (4.12, 0.14, 0.22), 'timber', C_DRIFT_SHADE, 0.0, (1, 0, 0))
    for fx, fz, fw, fd, fyaw in (
        (-0.98, -1.16, 0.82, 0.62,  10.0),
        ( 0.88, -1.18, 0.78, 0.58, -12.0),
        ( 0.02, -1.32, 0.86, 0.56,   4.0),
        (-1.12,  1.24, 0.76, 0.58, -14.0),
        ( 0.96,  1.22, 0.80, 0.58,  11.0),
    ):
        cbox(mb, (fx, FLOOR_Y + 0.02, fz), (fw, 0.055, fd),
             'temple_stone', jit(C_COBBLE_LIGHT, rng, 0.07), 0.0, M=R('Y', fyaw))

    # 2. Four Timber & Driftwood Corner Posts + Center Gable Spars + Hemp Lashings + Guy-Lines!
    RIDGE_Y = 3.74
    P_FL = Vector((-1.92, 2.94, -1.46))
    P_FR = Vector(( 1.92, 2.90, -1.46))
    P_BL = Vector((-1.92, 2.66,  1.46))
    P_BR = Vector(( 1.92, 2.64,  1.46))
    P_ML = Vector((-1.94, RIDGE_Y - 0.06, 0.00))
    P_MR = Vector(( 1.94, RIDGE_Y - 0.06, 0.00))

    for pt, lean_x, lean_z, pcol in (
        (P_FL, -0.06, -0.05, C_TIMBER_MID),
        (P_FR,  0.06, -0.05, C_DRIFTWOOD),
        (P_BL, -0.05,  0.06, C_DRIFTWOOD),
        (P_BR,  0.05,  0.06, C_TIMBER_MID),
        (P_ML, -0.04,  0.00, C_DRIFT_PALE),
        (P_MR,  0.04,  0.00, C_DRIFT_PALE),
    ):
        p_bot = Vector((pt.x, FLOOR_Y - 0.14, pt.z))
        p_top = Vector((pt.x + lean_x, pt.y + 0.18, pt.z + lean_z))
        tube(mb, [p_bot, p_bot.lerp(p_top, 0.52), p_top], [0.115, 0.098, 0.084], 6, 'timber', pcol, mode='flat')
        cbox(mb, (pt.x, FLOOR_Y + 0.12, pt.z), (0.24, 0.14, 0.24), 'iron', C_IRON_RUST, 0.0)
        # Hemp rope lashing collar right where the eaves / ridge poles join each post!
        with xf(mb, T(pt + Vector((0.0, -0.06, 0.0))) @ R('X', 34.0) @ R('Z', 22.0)):
            torus(mb, 0.135, 0.028, 6, 4, 'rope', C_ROPE, False)
        col_pts.append(pt)

    # Ridge spar + side eaves poles + gable rafter spars + corner knee braces
    tube(mb, [Vector((-2.28, RIDGE_Y, 0.0)), Vector((0.0, RIDGE_Y + 0.06, 0.0)), Vector((2.28, RIDGE_Y, 0.0))],
         [0.082, 0.096, 0.082], 6, 'timber', C_DRIFT_PALE, mode='flat')
    _add_beam(mb, P_FL + Vector((-0.24, -0.04, -0.04)), P_FR + Vector((0.24, -0.04, -0.04)), 0.11, 0.11, 'timber', C_TIMBER_HI, 0.0)
    _add_beam(mb, P_BL + Vector((-0.24, -0.04,  0.04)), P_BR + Vector((0.24, -0.04,  0.04)), 0.11, 0.11, 'timber', C_TIMBER_DARK, 0.0)
    for pf, pm, pb in ((P_FL, P_ML, P_BL), (P_FR, P_MR, P_BR)):
        _add_beam(mb, pf + Vector((0.0, -0.04, -0.14)), pm + Vector((0.0, 0.02, 0.0)), 0.095, 0.095, 'timber', C_DRIFTWOOD, 0.0)
        _add_beam(mb, pb + Vector((0.0, -0.04,  0.14)), pm + Vector((0.0, 0.02, 0.0)), 0.095, 0.095, 'timber', C_DRIFTWOOD, 0.0)
    # Front corner knee braces framing the captain's open pavilion entrance
    _add_beam(mb, (-1.92, 2.26, -1.46), (-1.34, 2.90, -1.46), 0.09, 0.09, 'timber', C_TIMBER_DARK, 0.0)
    _add_beam(mb, ( 1.92, 2.22, -1.46), ( 1.34, 2.86, -1.46), 0.09, 0.09, 'timber', C_TIMBER_DARK, 0.0)

    # Tall Flagpole Extension on Port Gable flying a Fluttering Pirate Swallowtail Pennant ('paint' + UV2!)
    FLAG_ROOT = Vector((-1.98, RIDGE_Y + 0.08, 0.0))
    FLAG_TOP  = Vector((-2.04, 5.04, -0.04))
    tube(mb, [FLAG_ROOT, FLAG_TOP], [0.068, 0.040], 5, 'timber', C_TIMBER_DARK, mode='flat')
    with xf(mb, T(FLAG_TOP)):
        cyl(mb, 0.082, -0.02, 0.12, 6, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.02)
    _build_wind_pennant(
        mb, FLAG_TOP + Vector((0.04, -0.26, 0.0)),
        length=2.12, h0=0.50, out_dir=(0.82, -0.06, -0.57),
        col_main=C_CRIMSON_HI, col_trim=C_GOLD_BRIGHT, phase=0.33,
    )

    # 3. Gracefully Draped, Wind-Billowed Patched Crimson-and-Cream Striped Sailcloth Canopy ('paint' + UV2!)
    nu, nv = 8, 6
    thick = 0.024

    def _canopy_pt(u, v):
        # u across width (-X -> +X, -2.18 .. +2.18), v front-to-back (-Z -> +Z, -1.78 .. +1.78)
        x = -2.18 + u * 4.36
        z = -1.78 + v * 3.56
        # Ridge along v = 0.50 (z = 0), sloping cleanly OVER eaves poles (y = 3.08 front / 2.78 rear!)
        dv = abs(v - 0.50) * 2.0  # 0 at ridge -> 1 at eaves
        eave_y = 3.10 * (1.0 - v) + 2.80 * v
        # Graceful catenary swag between ridge & eaves (clears eaves pole!) + scalloped skirt valance drop!
        base_y = (RIDGE_Y + 0.14) * (1.0 - dv) + eave_y * dv
        cat_sag = sin(dv * pi) * 0.13 * (0.45 + 0.55 * sin(u * pi))
        # Subtle upward wind-billow swell & rippling breeze waves
        billow = sin(u * pi * 2.5 + v * pi * 2.0) * 0.048 * (0.35 + 0.65 * dv)
        # Outer overhanging skirt valance curves softly downward strictly OUTSIDE the timber eaves poles!
        skirt_drop = 0.0
        if dv > 0.86:
            skirt_drop += ((dv - 0.86) / 0.14) ** 1.35 * 0.30
        du_edge = max(0.0, abs(u - 0.50) * 2.0 - 0.88) / 0.12
        if du_edge > 0.0:
            skirt_drop += (du_edge ** 1.35) * 0.24
        return Vector((x, base_y - cat_sag + billow - skirt_drop, z))

    def _canopy_w(u, v):
        dv = abs(v - 0.50) * 2.0
        du = abs(u - 0.50) * 2.0
        # 0 at the 4 lashed corner posts & ridge poles, strongest wind flutter along the hanging skirt!
        post_pin = min(sqrt((du - 0.88) ** 2 + (dv - 0.84) ** 2), sqrt((du - 0.88) ** 2 + dv ** 2))
        pin_mask = smooth01(post_pin / 0.34)
        skirt_w = max(0.0, dv - 0.72) / 0.28 * 0.88 + max(0.0, du - 0.78) / 0.22 * 0.75
        mid_w = sin(dv * pi) * sin(u * pi) * 0.38
        return min(0.95, max(0.0, (mid_w + skirt_w) * pin_mask))

    top_g = [[None] * (nv + 1) for _ in range(nu + 1)]
    bot_g = [[None] * (nv + 1) for _ in range(nu + 1)]
    w_g   = [[0.0]  * (nv + 1) for _ in range(nu + 1)]
    for iu in range(nu + 1):
        u = iu / float(nu)
        for iv in range(nv + 1):
            v = iv / float(nv)
            p = _canopy_pt(u, v)
            pu = _canopy_pt(min(1.0, u + 0.02), v) - _canopy_pt(max(0.0, u - 0.02), v)
            pv = _canopy_pt(u, min(1.0, v + 0.02)) - _canopy_pt(u, max(0.0, v - 0.02))
            n = pv.cross(pu)
            if n.y < 0.0:
                n = -n
            n = n.normalized() if n.length > 1e-6 else Vector((0.0, 1.0, 0.0))
            top_g[iu][iv] = p + n * (thick * 0.5)
            bot_g[iu][iv] = p - n * (thick * 0.5)
            w_g[iu][iv] = _canopy_w(u, v)

    def _stripe_col(iu, iv):
        # Vibrant crimson-and-cream sailcloth awning stripes + 2 stitched pirate repair patches!
        if (iu == 2 and iv == 4) or (iu == 5 and iv == 1):
            c = C_TEAL_BRIGHT
        elif iu == 6 and iv == 3:
            c = C_SAND_WARM
        elif iu % 2 == 0:
            c = C_CRIMSON_HI if (iv % 2 == 0) else C_CRIMSON_MID
        else:
            c = C_CANVAS_CREAM if (iv % 2 == 0) else C_CANVAS_WARM
        return jit(c, rng, 0.035, 0.012)

    mb.newoff()
    c_phase = 0.21
    for iu in range(nu):
        for iv in range(nv):
            c_top = _stripe_col(iu, iv)
            c_bot = mul(c_top, 0.84)
            t00, t10, t11, t01 = top_g[iu][iv], top_g[iu + 1][iv], top_g[iu + 1][iv + 1], top_g[iu][iv + 1]
            b00, b10, b11, b01 = bot_g[iu][iv], bot_g[iu + 1][iv], bot_g[iu + 1][iv + 1], bot_g[iu][iv + 1]
            u00, u10, u11, u01 = (w_g[iu][iv], c_phase), (w_g[iu + 1][iv], c_phase), (w_g[iu + 1][iv + 1], c_phase), (w_g[iu][iv + 1], c_phase)
            ctr = (t00 + t11 + b00 + b11) * 0.25
            mb.fp([t00, t10, t11, t01], 'paint', c_top, (1, 0, 0), ctr - Vector((0.0, 1.5, 0.0)),
                  smooth=False, uv2=[u00, u10, u11, u01])
            mb.fp([b00, b01, b11, b10], 'paint', c_bot, (1, 0, 0), ctr + Vector((0.0, 1.5, 0.0)),
                  smooth=False, uv2=[u00, u01, u11, u10])
            if iv == 0:
                mb.fp([b00, b10, t10, t00], 'paint', mul(c_top, 0.78), (1, 0, 0), ctr + Vector((0.0, 0.0, 1.0)),
                      uv2=[u00, u10, u10, u00])
            if iv == nv - 1:
                mb.fp([b11, b01, t01, t11], 'paint', mul(c_top, 0.78), (1, 0, 0), ctr - Vector((0.0, 0.0, 1.0)),
                      uv2=[u11, u01, u01, u11])
            if iu == 0:
                mb.fp([b01, b00, t00, t01], 'paint', mul(c_top, 0.78), (0, 0, 1), ctr + Vector((1.0, 0.0, 0.0)),
                      uv2=[u01, u00, u00, u01])
            if iu == nu - 1:
                mb.fp([b10, b11, t11, t10], 'paint', mul(c_top, 0.78), (0, 0, 1), ctr - Vector((1.0, 0.0, 0.0)),
                      uv2=[u10, u11, u11, u10])

    # 4 Taut Hemp Tent Guy-Ropes tied to angled wooden stakes driven solidly INSIDE the terrace rim!
    for corner_p, stake_xz in (
        (top_g[0][0],  (-2.22, -1.84)),
        (top_g[0][nv], (-2.22,  1.84)),
        (top_g[nu][0], ( 2.22, -1.84)),
        (top_g[nu][nv],( 2.22,  1.84)),
    ):
        sx, sz = stake_xz
        s_bot = Vector((sx, FLOOR_Y - 0.18, sz))
        s_top = Vector((sx + (0.08 if sx > 0 else -0.08), FLOOR_Y + 0.34, sz + (0.06 if sz > 0 else -0.06)))
        _add_beam(mb, s_bot, s_top, 0.070, 0.070, 'timber', C_TIMBER_DARK, 0.0)
        tie_p = s_bot.lerp(s_top, 0.74)
        mid_g = corner_p.lerp(tie_p, 0.5) - Vector((0.0, 0.04, 0.0))
        tube(mb, [corner_p, mid_g, tie_p], 0.020, 4, 'rope', C_ROPE, mode='flat')

    # 4. Stout Plank-and-Trestle Oak War Table (center x=0, z=-0.06, top y = 1.08 m!)
    TBL_Z = -0.06
    TBL_Y = 1.08
    for sx in (-0.82, 0.82):
        # Foot sled + twin A-trestle legs + upper bearer crossbeam
        cbox(mb, (sx, FLOOR_Y + 0.07, TBL_Z), (0.16, 0.14, 1.14), 'timber', C_TIMBER_DARK, 0.0, (0, 0, 1))
        _add_beam(mb, (sx, FLOOR_Y + 0.10, TBL_Z - 0.44), (sx, TBL_Y - 0.08, TBL_Z - 0.22), 0.12, 0.12, 'timber', C_TIMBER_MID, 0.0)
        _add_beam(mb, (sx, FLOOR_Y + 0.10, TBL_Z + 0.44), (sx, TBL_Y - 0.08, TBL_Z + 0.22), 0.12, 0.12, 'timber', C_TIMBER_MID, 0.0)
        cbox(mb, (sx, TBL_Y - 0.10, TBL_Z), (0.15, 0.12, 1.08), 'timber', C_TIMBER_DARK, 0.0, (0, 0, 1))
    # Heavy horizontal wedged trestle stretcher beam connecting both leg frames
    cbox(mb, (0.0, FLOOR_Y + 0.34, TBL_Z), (1.98, 0.12, 0.12), 'timber', C_TIMBER_HI, 0.0, (1, 0, 0))
    for sx in (-0.94, 0.94):
        cbox(mb, (sx, FLOOR_Y + 0.34, TBL_Z), (0.045, 0.24, 0.055), 'timber', C_OAK_FRESH, 0.0)
    # 5 Thick Individual Oak Tabletop Planks + Forged-Iron Corner Edge Straps!
    for pk in range(5):
        pz = TBL_Z - 0.48 + pk * 0.24
        pcol = jit(C_TIMBER_HI if pk % 2 == 0 else C_TIMBER_MID, rng, 0.05)
        cbox(mb, (0.0, TBL_Y - 0.038, pz), (2.16, 0.076, 0.224), 'timber', pcol, 0.0, (1, 0, 0))
    for sx in (-1.08, 1.08):
        cbox(mb, (sx, TBL_Y - 0.038, TBL_Z), (0.036, 0.088, 1.22), 'iron', C_IRON, 0.0)

    # 5. Sculpted Parchment Archipelago Chart (Vertex-Painted Islands & Compass Rose!) + Hero Table Props!
    MAP_X, MAP_Z = -0.06, TBL_Z + 0.01
    MAP_W, MAP_D = 1.40, 0.86
    mnu, mnv = 10, 6

    def _map_pt(u, v):
        px = MAP_X + (u - 0.5) * MAP_W
        pz = MAP_Z + (v - 0.5) * MAP_D
        # Natural wavy parchment ripple + gracefully curled-up map corners!
        dist_edge = max(abs(u - 0.5) * 2.0, abs(v - 0.5) * 2.0)
        curl = max(0.0, dist_edge - 0.72) ** 2 * 0.42
        ripple = 0.008 * sin(u * pi * 3.0) * cos(v * pi * 2.0)
        return Vector((px, TBL_Y + 0.012 + ripple + curl, pz))

    def _chart_cell_col(iu, iv):
        # 10x6 painterly nautical chart grid: tanned parchment rim, teal sea interior,
        # 3 sculpted green-and-sand islands, crimson treasure route & bold compass rose corner!
        if iu in (0, mnu - 1) or iv in (0, mnv - 1):
            return C_CHART_EDGE if (iu + iv) % 2 == 0 else C_CHART_PAPER
        # Compass rose in front-starboard corner (iu=8, iv=1)
        if iu == 8 and iv == 1:
            return C_CRIMSON_HI
        if (iu == 7 and iv == 1) or (iu == 8 and iv == 2):
            return C_GOLD_BRIGHT
        # Archipelago islands (3 vivid clusters!)
        if (iu in (2, 3) and iv in (2, 3)):
            return C_CHART_ISLE if (iu == 2 and iv == 2) else C_SAND_WARM
        if (iu == 5 and iv == 4) or (iu == 6 and iv == 4):
            return C_CHART_ISLE
        if (iu == 7 and iv == 3):
            return C_CRIMSON_HI  # X marks the treasure isle!
        # Dotted crimson voyage track connecting islands
        if (iu == 4 and iv == 3) or (iu == 5 and iv == 3) or (iu == 6 and iv == 3):
            return mix(C_CHART_SEA, C_CRIMSON_HI, 0.48)
        return C_CHART_SEA if (iu + iv) % 2 == 0 else C_TEAL_CHART

    map_g = [[_map_pt(iu / float(mnu), iv / float(mnv)) for iv in range(mnv + 1)] for iu in range(mnu + 1)]
    for iu in range(mnu):
        for iv in range(mnv):
            p00, p10, p11, p01 = map_g[iu][iv], map_g[iu + 1][iv], map_g[iu + 1][iv + 1], map_g[iu][iv + 1]
            cc = _chart_cell_col(iu, iv)
            ctr_m = (p00 + p11) * 0.5
            mb.fp([p00, p10, p11, p01], 'paint', cc, (1, 0, 0), ctr_m - Vector((0.0, 0.5, 0.0)))
    # Rolled parchment scroll resting beside the left map edge
    with xf(mb, T(-0.88, TBL_Y + 0.048, TBL_Z - 0.14) @ R('Y', 16.0) @ M_Y2Z):
        cyl(mb, 0.044, -0.34, 0.34, 6, 'paint', C_CANVAS_CREAM, False, 0.0)
        cyl(mb, 0.048, -0.04, 0.04, 6, 'paint', C_CRIMSON_HI, False, 0.0)

    # Raised Brass Compass-Rose Medallion & Brass Spyglass on the Starboard Map Corner!
    # Extended 3-stage brass spyglass angled jauntily across front-starboard corner
    with xf(mb, T(0.62, TBL_Y + 0.056, TBL_Z - 0.24) @ R('Y', -36.0) @ M_Y2Z):
        cyl(mb, 0.048, -0.24, -0.02, 7, 'timber', C_TIMBER_DARK, False, 0.0, 0.046)  # leather grip barrel
        cyl(mb, 0.052, -0.26, -0.21, 7, 'brass', C_GOLD_BRIGHT, False, 0.0)
        cyl(mb, 0.040, -0.02,  0.14, 7, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.036)
        cyl(mb, 0.030,  0.14,  0.26, 7, 'brass', C_BRASS, False, 0.0, 0.028)
        cyl(mb, 0.024,  0.26,  0.28, 6, 'glass', C_LANTERN_GL, False, 0.0)

    # Brass Navigational Sextant & Drafting Dividers on Rear-Starboard Chart Edge!
    SEXT_P = Vector((0.46, TBL_Y + 0.025, TBL_Z + 0.28))
    with xf(mb, T(SEXT_P) @ R('Y', 24.0)):
        _add_beam(mb, (0.0, 0.0, -0.14), (-0.16, 0.0, 0.14), 0.024, 0.020, 'brass', C_GOLD_BRIGHT, 0.0)
        _add_beam(mb, (0.0, 0.0, -0.14), ( 0.16, 0.0, 0.14), 0.024, 0.020, 'brass', C_GOLD_BRIGHT, 0.0)
        # Curved brass sextant arc limb
        arc_pts = [Vector((sin(radians(-36.0 + k * 18.0)) * 0.26, 0.008, -0.14 + cos(radians(-36.0 + k * 18.0)) * 0.26))
                   for k in range(5)]
        tube(mb, arc_pts, 0.018, 4, 'brass', C_BRASS, mode='flat')
        cyl(mb, 0.040, 0.0, 0.036, 6, 'brass', C_GOLD_BRIGHT, False, 0.0)
    # Brass Dividers caliper laid beside the sextant
    with xf(mb, T(0.84, TBL_Y + 0.022, TBL_Z + 0.14) @ R('Y', -18.0)):
        cyl(mb, 0.026, 0.0, 0.024, 6, 'brass', C_GOLD_BRIGHT, False, 0.0)
        _add_beam(mb, (0.0, 0.012, 0.0), (-0.08, 0.008, -0.26), 0.018, 0.016, 'brass', C_GOLD_BRIGHT, 0.0)
        _add_beam(mb, (0.0, 0.012, 0.0), ( 0.09, 0.008, -0.25), 0.018, 0.016, 'brass', C_GOLD_BRIGHT, 0.0)

    # Steel Pirate Cutlass / Boarding Dagger Stabbed Boldly Point-Down Pinning the Map!
    DAG_M = T(-0.42, TBL_Y + 0.02, TBL_Z - 0.14) @ R('Y', 28.0) @ R('Z', -14.0) @ R('X', 8.0)
    with xf(mb, DAG_M):
        # Tapered steel blade buried solidly into tabletop
        cbox(mb, (0.0, 0.14, 0.0), (0.068, 0.30, 0.018), 'iron', C_STEEL_BRIGHT, 0.0)
        # Ornate curved brass crossguard & swept knuckle-bow
        cbox(mb, (0.0, 0.30, 0.0), (0.24, 0.032, 0.046), 'brass', C_GOLD_BRIGHT, 0.0)
        guard_pts = [Vector((0.10, 0.30, 0.0)), Vector((0.14, 0.38, 0.0)), Vector((0.11, 0.46, 0.0)), Vector((0.02, 0.48, 0.0))]
        tube(mb, guard_pts, 0.016, 4, 'brass', C_GOLD_BRIGHT, mode='flat')
        # Wrapped dark-oak grip & gleaming brass pommel orb
        cyl(mb, 0.028, 0.31, 0.47, 6, 'timber', C_TIMBER_DARK, False, 0.0)
        with xf(mb, T(0.0, 0.50, 0.0)):
            cyl(mb, 0.044, -0.03, 0.04, 6, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.024)

    # Chunky Wooden Grog Tankard with Iron Hoops & Curved Handle on Port-Rear Corner!
    with xf(mb, T(-0.76, TBL_Y + 0.01, TBL_Z + 0.30) @ R('Y', -32.0)):
        cyl(mb, 0.092, 0.0, 0.22, 7, 'timber', C_OAK_FRESH, False, 0.0, 0.076)
        cyl(mb, 0.094, 0.03, 0.06, 7, 'iron', C_IRON, False, 0.0)
        cyl(mb, 0.082, 0.16, 0.19, 7, 'iron', C_IRON, False, 0.0)
        cyl(mb, 0.068, 0.21, 0.235, 7, 'paint', C_CANVAS_CREAM, False, 0.0, 0.055)  # frothy grog head!
        h_pts = [Vector((0.076, 0.18, 0.0)), Vector((0.145, 0.16, 0.0)), Vector((0.148, 0.07, 0.0)), Vector((0.084, 0.04, 0.0))]
        tube(mb, h_pts, 0.018, 4, 'timber', C_TIMBER_DARK, mode='flat')

    # 6. Warm Hanging Brass Lantern Suspended Above the Chart Table ('Lantern_MapTent'!)
    LANTERN_POS = Vector((0.0, 2.28, TBL_Z))
    _add_chain_links(mb, Vector((0.0, RIDGE_Y - 0.04, 0.0)), LANTERN_POS + Vector((0.0, 0.38, 0.0)),
                     n_links=6, link_r=0.098, wire_r=0.028, segs=5, psegs=4, sag=0.0, mat='iron', stretch_y=1.40)
    _build_storm_lantern(mb, LANTERN_POS, scale=1.24, brass_cage=True, hanging=True)

    # 7. Lashed Oak Supply Casks, Banded Treasure Chest, Captain's Camp Stool & Perimeter Ferns!
    # Ajar iron-banded oak treasure chest resting beside starboard end of war table!
    _build_banded_chest(mb, T(1.32, FLOOR_Y + 0.01, 0.66) @ R('Y', -32.0), open_deg=24.0, rng=rng)
    # Upright & tilted lashed oak supply casks on port flank!
    _build_coopered_cask(
        mb, T(-1.46, FLOOR_Y + 0.39, 0.56) @ R('Y', 18.0),
        radius=0.31, height=0.78, rng=rng, col_a=C_TIMBER_MID, col_b=C_TIMBER_HI,
        segs=6, stripe_col=C_CRIMSON_HI, spigot=True,
    )
    _build_coopered_cask(
        mb, T(-1.38, FLOOR_Y + 0.28, -0.34) @ R('Y', 24.0) @ R('Z', 90.0),
        radius=0.27, height=0.66, rng=rng, col_a=C_DRIFTWOOD, col_b=C_TIMBER_MID, segs=6,
    )
    # Hemp lashing binding the upright cask to the rear-port post + coiled rope near front-starboard post
    tube(mb, [(-1.86, FLOOR_Y + 0.56, 1.38), (-1.46, FLOOR_Y + 0.56, 0.88), (-1.18, FLOOR_Y + 0.52, 0.56)],
         0.024, 4, 'rope', C_ROPE, mode='flat')
    _build_rope_coil_lean(mb, (1.44, FLOOR_Y + 0.01, -0.98), radius=0.27, turns=3, r=0.036, segs=7, psegs=4)

    # Rustic 3-legged Captain's oak camp stool tucked neatly before the war table
    ST_X, ST_Z = -0.18, -0.92
    with xf(mb, T(ST_X, FLOOR_Y, ST_Z)):
        cyl(mb, 0.24, 0.46, 0.53, 7, 'timber', C_TIMBER_HI, False, 0.0)
        for sk in range(3):
            ang = radians(25.0 + sk * 120.0)
            _add_beam(mb, (cos(ang) * 0.22, 0.0, sin(ang) * 0.22),
                      (cos(ang) * 0.14, 0.48, sin(ang) * 0.14), 0.052, 0.052, 'timber', C_TIMBER_DARK, 0.0)

    # Small coastal fern tufts softening the rear terrace stone corners ('foliage' + UV2)
    for fp, fph, fln in (
        ((-2.16, FLOOR_Y + 0.04,  1.66), 0.18, (-0.7, 0.0,  0.7)),
        (( 2.18, FLOOR_Y + 0.04,  1.62), 0.64, ( 0.7, 0.0,  0.7)),
    ):
        _add_coastal_fern_cluster(mb, fp, scale=0.72, n_fronds=4, rng=rng, phase=fph, lean_dir=fln)

    build(mb)

    add_empty('Lantern_MapTent', LANTERN_POS)
    col_piece('col_maptent_base', col_pts)
    export_landmark_glb(outdir, 'pirate_map_planning_table_tent.glb')


# ================================================================ 4. VOLCANIC BASALT OBELISK BRAZIER

def gen_volcanic_basalt_obelisk_brazier(outdir):
    """Dramatic ~8.3 m tall fractured hexagonal obsidian/basalt rune monolith plunging cleanly into
    a wide stepped caldera stone pedestal down to y = -3.60 m (radius ~ 2.65 m) for Cinder Crag &
    Skull Bluff! Sculpted clustered hexagonal basalt ribs wrapped in forged-iron binding bands &
    draped heavy anchor chains, etched glowing magma-vein vertical runes ('glass' warm orange-gold
    emission + bright molten linear COLOR_0 so volcanic fire & runes blaze incandescent orange-gold
    rather than skull_glow's cyan emission!), crowned atop with a wide spiked cast-iron fire bowl
    cradling glowing incandescent volcanic coal mounds & rising ember-crystal flame tongues, plus
    'Lantern_BasaltBrazier' empty right inside the crown fire bowl!
    Target: 3,000-3,700 visual tris, 1 collider (col_basaltbrazier_base).
    """
    clear_scene()
    rng = random.Random(SEED + 2753)
    mb = MB('VolcanicBasaltObeliskBrazier', seed=2753)

    SKIRT_BOT = -3.60
    TIER1_Y = 0.28
    TIER2_Y = 0.80
    TIER3_Y = 1.32
    OBEL_TOP_Y = 6.56
    col_pts = []

    # 1. Wide Stepped Caldera Stone Pedestal plunging cleanly to y = -3.60 m (radius ~ 2.68 m!)
    base_secs = [
        _reg_poly(0.0, SKIRT_BOT, 0.0, 2.86, sides=8, rot_deg=22.5),
        _reg_poly(0.0, -1.65,     0.0, 2.70, sides=8, rot_deg=22.5),
        _reg_poly(0.0, TIER1_Y,   0.0, 2.52, sides=8, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, base_secs, 'basalt',
        [C_BASALT_DARK, C_BASALT_DARK, C_BASALT_MID],
        rng, caps=(True, True), top_mat='basalt', top_col=C_BASALT_MID,
    )
    for ring in base_secs:
        col_pts.extend(Vector(p) for p in ring)

    # Stepped hexagonal caldera altar tiers (y = 0.28 .. 1.32 m)
    tier2_secs = [
        _reg_poly(0.0, TIER1_Y - 0.04, 0.0, 2.18, sides=6, rot_deg=0.0),
        _reg_poly(0.0, TIER2_Y,        0.0, 2.02, sides=6, rot_deg=0.0),
    ]
    _loft_horizontal_masonry(
        mb, tier2_secs, 'basalt', [C_BASALT_DARK, C_BASALT_MID], rng, caps=(False, True), top_col=C_BASALT_TOP,
    )
    tier3_secs = [
        _reg_poly(0.0, TIER2_Y - 0.04, 0.0, 1.66, sides=6, rot_deg=30.0),
        _reg_poly(0.0, TIER3_Y,        0.0, 1.48, sides=6, rot_deg=30.0),
    ]
    _loft_horizontal_masonry(
        mb, tier3_secs, 'basalt', [C_BASALT_MID, C_BASALT_TOP], rng, caps=(False, True), top_col=C_BASALT_TOP,
    )

    # Rugged perimeter lava-crag buttress rocks framing the caldera pedestal base!
    for bk in range(6):
        ang = radians(30.0 + bk * 60.0)
        rx, rz = cos(ang) * 2.16, sin(ang) * 2.16
        sculpt_basalt_column(
            mb, (rx, -0.35, rz), 1.45 + 0.35 * (bk % 2), 0.44, 6,
            cos(ang) * 14.0, sin(ang) * 14.0,
            C_BASALT_DARK, mix(C_BASALT_TOP, C_BASALT_HOT, 0.18 if bk % 2 == 0 else 0.05),
            rng, mat='basalt', magma_seam=(bk % 2 == 0),
        )

    # 2. Central Fractured Hexagonal Obsidian/Basalt Monolith Shaft (y = 1.24 .. 6.56 m!)
    mono_secs = [
        _reg_poly(0.0, TIER3_Y - 0.10, 0.0, 1.04, sides=6, rot_deg=0.0),
        _reg_poly(0.0, 2.65,           0.0, 0.94, sides=6, rot_deg=0.0),
        _reg_poly(0.0, 4.10,           0.0, 0.84, sides=6, rot_deg=0.0),
        _reg_poly(0.0, 5.45,           0.0, 0.74, sides=6, rot_deg=0.0),
        _reg_poly(0.0, OBEL_TOP_Y,     0.0, 0.66, sides=6, rot_deg=0.0),
    ]
    _loft_horizontal_masonry(
        mb, mono_secs, 'basalt',
        [C_BASALT_DARK, C_BASALT_MID, C_BASALT_MID, C_BASALT_TOP, C_BASALT_TOP],
        rng, caps=(False, True), top_col=C_BASALT_TOP,
    )
    col_pts.extend([Vector((-0.72, OBEL_TOP_Y, -0.72)), Vector((0.72, OBEL_TOP_Y, 0.72))])

    # 6 Clustered Sculpted Hexagonal Basalt Organ-Pipe Ribs hugging the obelisk flanks!
    rib_heights = (4.55, 3.65, 5.15, 3.85, 4.80, 3.40)
    for rk in range(6):
        ang = radians(rk * 60.0)
        rx = cos(ang) * 0.92
        rz = sin(ang) * 0.92
        sculpt_basalt_column(
            mb, (rx, TIER2_Y - 0.10, rz), rib_heights[rk], 0.36, 6,
            -cos(ang) * 3.8, -sin(ang) * 3.8,
            C_BASALT_DARK, mix(C_BASALT_TOP, C_BASALT_HOT, 0.22 if rk % 2 == 0 else 0.08),
            rng, mat='basalt', magma_seam=(rk % 2 == 0),
        )

    # 3. Forged-Iron Hexagonal Binding Bands & 4 Tightly-Interlocked Draped Heavy Anchor Chains!
    band_specs = [
        (2.18, 1.06, 0.18),
        (3.86, 0.94, 0.18),
        (5.68, 0.79, 0.16),
    ]
    for by, br, bh in band_specs:
        with xf(mb, T(0.0, by, 0.0)):
            cyl(mb, br, -bh * 0.5, bh * 0.5, 6, 'iron', C_IRON, False, 0.0)
            for rk in range(6):
                ang = radians(rk * 60.0)
                cbox(mb, (cos(ang) * (br + 0.02), 0.0, sin(ang) * (br + 0.02)),
                     (0.09, bh * 0.92, 0.09), 'iron', C_IRON_RUST if rk % 2 == 0 else C_IRON, 0.0,
                     M=R('Y', -degrees(ang)))

    # 4 Heavy Forged-Iron Anchor Chains sweeping cleanly from mid collar shackles down to pedestal bollards
    #    Arc length ~3.08 m, n_links=7 -> spacing 0.440 m vs link outer half 0.438 m & inner half 0.249 m -> 100% interlocked!
    for ck in range(4):
        ang = radians(45.0 + ck * 90.0)
        ca, sa = cos(ang), sin(ang)
        p_shack = Vector((ca * 0.96, 3.86, sa * 0.96))
        p_anc   = Vector((ca * 1.94, TIER2_Y + 0.14, sa * 1.94))
        # Forged-iron anchor bollard bolted solidly into Tier 2 caldera stone!
        cbox(mb, p_anc - Vector((0.0, 0.10, 0.0)), (0.34, 0.34, 0.34), 'iron', C_IRON_RUST, 0.0, M=R('Y', -degrees(ang)))
        with xf(mb, T(p_anc + Vector((0.0, 0.10, 0.0))) @ R('Y', -degrees(ang)) @ M_Y2Z):
            torus(mb, 0.125, 0.038, 5, 4, 'iron', C_IRON, False)
        with xf(mb, T(p_shack) @ R('Y', -degrees(ang)) @ M_Y2Z):
            torus(mb, 0.115, 0.036, 5, 4, 'iron', C_IRON_RUST, False)
        _add_chain_links(mb, p_shack, p_anc + Vector((0.0, 0.08, 0.0)),
                         n_links=7, link_r=0.235, wire_r=0.064,
                         segs=5, psegs=4, sag=0.34, mat='iron', rust_stride=2, stretch_y=1.50)

    # 4. Etched Glowing Magma-Vein Vertical Runes on the Hexagonal Monolith + Crawling Lava Fissures!
    #    Uses 'glass' (warm amber-orange emission + bright molten linear COLOR_0) consistent with all volcanic landmarks!
    for fk in range(6):
        # Face mid-normal of flat-side hexagon (rot_deg=0 -> faces face 30, 90, 150, 210, 270, 330 deg)
        ang = radians(30.0 + fk * 60.0)
        ca, sa = cos(ang), sin(ang)
        n_out = Vector((ca, 0.0, sa))
        rot_face = R('Y', -degrees(ang) + 90.0)
        # Main vertical magma-rune channel running up the center of every hexagonal facet
        r_bot, r_top = 0.87, 0.62
        p_r0 = Vector((ca * r_bot, 1.56, sa * r_bot))
        p_r1 = Vector((ca * 0.77,  3.20, sa * 0.77))
        p_r2 = Vector((ca * r_top, 5.28, sa * r_top))
        _sculpt_magma_ribbon(mb, [p_r0, p_r1, p_r2], [0.065, 0.080, 0.052], n_out, hot_core=True)
        # Bold geometric volcanic rune glyphs (glowing chevron diamonds & cross-bars) on alternating facets!
        for gy, gr, gsz in ((2.85, 0.82, 0.26), (4.86, 0.68, 0.22)):
            gp = Vector((ca * gr, gy, sa * gr))
            with xf(mb, T(gp) @ rot_face):
                cbox(mb, (0.0, 0.0, 0.02), (gsz, gsz, 0.045), 'glass', C_FLAME_CORE, 0.0, M=R('Z', 45.0))
                cbox(mb, (0.0, -gsz * 0.75, 0.015), (gsz * 1.15, 0.055, 0.04), 'glass', C_MAGMA_GLOW, 0.0)

    # 4 Surface-Hugging Glowing Lava Cracks crawling down the Stepped Caldera Pedestal!
    for vk in range(4):
        ang = radians(15.0 + vk * 90.0)
        ca, sa = cos(ang), sin(ang)
        v_nrm = Vector((ca * 0.62, 0.78, sa * 0.62)).normalized()
        v_path = [
            (ca * 1.24, TIER3_Y + 0.02, sa * 1.24),
            (ca * 1.72, TIER2_Y + 0.04, sa * 1.72),
            (ca * 2.18, TIER1_Y + 0.04, sa * 2.18),
            (ca * 2.48, -0.22,          sa * 2.48),
        ]
        _sculpt_magma_ribbon(mb, v_path, [0.085, 0.075, 0.058, 0.032], v_nrm, hot_core=True)

    # 5. Wide Spiked Cast-Iron Crown Fire Bowl + Incandescent Coal Mound & Rising Ember-Crystal Tongues!
    BOWL_BASE_Y = OBEL_TOP_Y
    LANTERN_POS = Vector((0.0, BOWL_BASE_Y + 1.02, 0.0))  # y = 7.58 m inside blazing crown fire bowl!

    with xf(mb, T(0.0, BOWL_BASE_Y, 0.0)):
        # Flared cast-iron calyx socket seating the fire bowl cleanly atop the basalt obelisk
        cyl(mb, 0.74, -0.10, 0.24, 6, 'iron', C_IRON, False, 0.0, 0.58)
        # Wide heavy cast-iron fire bowl with hollowed coal basin (y = 0.22 .. 0.94 m, rim r = 1.24 m!)
        bowl_prof = [
            (0.00, 0.20),
            (0.56, 0.24),
            (0.98, 0.56),
            (1.22, 0.88),
            (1.26, 0.96),
            (1.12, 0.98),
            (0.94, 0.64),
            (0.00, 0.52),
        ]
        lathe(mb, bowl_prof, 6, 'iron', C_IRON, False, False,
              lambda i, k: C_IRON_RUST if i in (2, 4) else C_IRON)
        # Heavy riveted rim hoops around fire bowl & outer flame basket
        with xf(mb, T(0.0, 0.94, 0.0)):
            torus(mb, 1.22, 0.058, 6, 4, 'iron', C_IRON_RUST, False)
        with xf(mb, T(0.0, 1.34, 0.0)):
            torus(mb, 1.32, 0.042, 6, 4, 'iron', C_IRON, False)

        # 6 Dramatic Spiked Forged-Iron Crown Prongs matching hexagonal obelisk symmetry (to y = 8.28 m!)
        for sk in range(6):
            ang = 2.0 * pi * sk / 6.0
            ca, sa = cos(ang), sin(ang)
            prong_pts = [
                (ca * 0.66, 0.26, sa * 0.66),
                (ca * 1.18, 0.78, sa * 1.18),
                (ca * 1.36, 1.32, sa * 1.36),
                (ca * 1.16, 1.72, sa * 1.16),
            ]
            tube(mb, prong_pts, [0.072, 0.068, 0.054, 0.014], 4, 'iron',
                 C_IRON_RUST if sk % 2 == 0 else C_IRON, mode='flat')

        # Glowing Incandescent Volcanic Coal Mound cradling dark charred basalt slag chunks!
        coal_prof = [
            (0.00, 0.50),
            (0.96, 0.60),
            (0.84, 0.84),
            (0.54, 1.02),
            (0.00, 1.10),
        ]
        lathe(mb, coal_prof, 6, 'glass', C_MAGMA_GLOW, False, False,
              lambda i, k: C_FLAME_CORE if i >= 3 else (C_MAGMA_GLOW if i == 2 else C_MAGMA_CRIMSON))
        # Dark charred volcanic coal nuggets half-embedded in the glowing magma bed
        for ck in range(5):
            ang = radians(20.0 + ck * 72.0)
            r_c = 0.56 + 0.14 * (ck % 2)
            with xf(mb, T(cos(ang) * r_c, 0.82 + 0.06 * (ck % 2), sin(ang) * r_c) @ R('Y', degrees(ang)) @ R('Z', 24.0)):
                cyl(mb, 0.18, -0.10, 0.16, 4, 'basalt', C_COAL_CHAR, False, 0.0, 0.09)

        # Rising Sculpted Incandescent Ember-Crystal Flame Tongues peaking cleanly at y ~ 8.38 m!
        ember_tongues = [
            (( 0.00, 0.92,  0.00), 0.36, 1.00, ( 3.0,   0.0,  4.0), C_FLAME_CORE),
            ((-0.38, 0.82, -0.26), 0.24, 0.80, (-12.0, 24.0, 14.0), C_FLAME_MID),
            (( 0.36, 0.82,  0.28), 0.25, 0.82, ( 10.0,-28.0,-12.0), C_FLAME_MID),
            (( 0.30, 0.80, -0.34), 0.22, 0.70, ( 14.0, 44.0,-10.0), C_MAGMA_GLOW),
            ((-0.28, 0.80,  0.34), 0.22, 0.72, (-14.0,-38.0, 12.0), C_FLAME_DEEP),
        ]
        for ep, er, eh, erot, ecol in ember_tongues:
            with xf(mb, T(ep) @ R('Y', erot[1]) @ R('X', erot[0]) @ R('Z', erot[2])):
                # Faceted crystalline flame spire (double-tapered ember crystal tongue!)
                lathe(mb, [(0.0, -0.06), (er, 0.14), (er * 0.62, eh * 0.56), (0.0, eh)],
                      4, 'glass', ecol, False)

    build(mb)

    add_empty('Lantern_BasaltBrazier', LANTERN_POS)
    col_piece('col_basaltbrazier_base', col_pts)
    export_landmark_glb(outdir, 'volcanic_basalt_obelisk_brazier.glb')


NAUTICAL_CRAFT_GENERATORS = [
    gen_coastal_rope_ferry_pulley,
    gen_ancient_sunken_bell_shrine,
    gen_pirate_map_planning_table_tent,
    gen_volcanic_basalt_obelisk_brazier,
]
