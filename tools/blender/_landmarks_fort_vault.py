# Sea of Scoundrels: 4 sculpted 3D Fort, Vault & Milestone Landmarks (Wave I-12 / Pass I-Q5 — 50-Landmark Milestone!).
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
    sculpt_rock_mass,
    clear_scene, build, col_piece, col_box, add_empty, export_landmark_glb,
)


# ---------------------------------------------------------------- local palette & sculptural helpers

# Warm sunlit Caribbean sandstone masonry (harmonized with Cloud Lead's Q5A seawall_bastion)
C_SAND_PALE     = srgb('#f4e6ca')
C_SAND_WARM     = srgb('#dfb680')
C_SAND_OCHRE    = srgb('#b28d5e')
C_SAND_SHADE    = srgb('#8a7459')
C_TIDE_DARK     = mix(C_LIME_DARK, C_SEA_MOSS, 0.36)
C_TIDE_MID      = mix(C_SAND_OCHRE, C_LIME_DARK, 0.44)

# Terracotta tiles, clay pottery, water, gold & weathered maritime accents
C_TERRA_HI      = srgb('#c95e3a')
C_TERRA_MID     = srgb('#a64528')
C_TERRA_DARK    = srgb('#752c1a')
C_CLAY_WARM     = srgb('#be6c44')
C_CLAY_SHADE    = srgb('#874628')
C_WATER_DEEP    = srgb('#0d3038')
C_WATER_MID     = srgb('#174d56')
C_WATER_SPEC    = srgb('#2f7c82')
C_GOLD_BRIGHT   = srgb('#f6c948')
C_BRASS_DARK    = srgb('#9b7024')
C_OAK_FRESH     = srgb('#c68d52')
C_CRIMSON_HI    = srgb('#cc3226')
C_CRIMSON_DEEP  = srgb('#781814')
C_TEAL_BRIGHT   = srgb('#26949a')
C_CANVAS_WARM   = srgb('#e4d5b2')
C_CANVAS_SHADE  = srgb('#b5a37e')
C_COBBLE_LIGHT  = srgb('#c9baa0')
C_COBBLE_MID    = srgb('#948774')
C_COBBLE_DARK   = srgb('#5f574d')
C_RUNE_CORE     = srgb('#46ffe0')
C_RUNE_MID      = srgb('#16d6bc')
C_BARNACLE_HI   = srgb('#e8e0ca')
C_BARNACLE_MID  = srgb('#b5ab92')
C_IRON_DARK     = srgb('#1f2026')
C_FLAME_CORE    = srgb('#ffe270')
C_FLAME_MID     = srgb('#ff8a24')
C_FLAME_DEEP    = srgb('#d93814')
C_VINE_DARK     = srgb('#13461a')
C_VINE_MID      = srgb('#276c20')
C_VINE_SUN      = srgb('#6eb224')
C_FERN_DARK     = srgb('#144a1c')
C_FERN_MID      = srgb('#2a7622')
C_FERN_TIP      = srgb('#78ba28')
C_KELP_DARK     = srgb('#154c2a')
C_KELP_MID      = srgb('#287a3c')
C_KELP_SUN      = srgb('#66ad32')


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


def _reg_poly(cx, y, cz, radius, sides=10, rot_deg=0.0):
    """Regular N-sided polygon ring at height y centered at (cx, y, cz)."""
    r0 = radians(rot_deg)
    return [
        (cx + radius * cos(r0 + 2.0 * pi * k / float(sides)),
         y,
         cz + radius * sin(r0 + 2.0 * pi * k / float(sides)))
        for k in range(sides)
    ]


def _rect_ring(x0, x1, y, z0, z1):
    """Counter-clockwise rectangular ring at height y."""
    return [(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)]


def _loft_horizontal_masonry(mb, secs, mat, scols, rng, caps=(True, True), top_mat=None, top_col=None):
    """Emit a vertical stepped or battered ashlar masonry shaft with horizontal UV courses."""
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
            face_col = jit(col_i, rng, 0.035, 0.014)
            mb.fp([p00, p01, p11, p10], mat, face_col, grain=horiz, inside=c_mid, smooth=False)
    if caps[0] and n > 1:
        mb.fp(secs[0], mat, mul(scols[0], 0.72), (1, 0, 0), cents[1], smooth=False)
    if caps[1] and n > 1:
        tmat = top_mat if top_mat is not None else mat
        tcol = top_col if top_col is not None else scols[-1]
        mb.fp(secs[-1], tmat, tcol, (1, 0, 0), cents[-2], smooth=False)


def _bevel_slab(mb, center, size, mat, col, bev=0.03, top_col=None, bot_col=None, M=None):
    """Clean 1-tier beveled stone coping/cornice slab (28 tris) with crisp top/bottom shading."""
    sx, sy, sz = size
    hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
    b = min(bev, hx * 0.35, hy * 0.42, hz * 0.35)
    tcol = top_col if top_col is not None else mul(col, 1.04)
    bcol = bot_col if bot_col is not None else mul(col, 0.74)
    X = T(center) @ (M if M is not None else Matrix.Identity(4))
    with xf(mb, X):
        secs = [
            _rect_ring(-hx + b, hx - b, -hy,     -hz + b, hz - b),
            _rect_ring(-hx,     hx,     -hy + b, -hz,     hz),
            _rect_ring(-hx,     hx,      hy - b, -hz,     hz),
            _rect_ring(-hx + b, hx - b,  hy,     -hz + b, hz - b),
        ]
        loft(mb, secs, mat, col, closed=True, caps=(True, True), mode='flat',
             scols=[bcol, col, tcol, tcol])


def _build_harbour_lantern(mb, center, scale=1.0, brass_body=True):
    """Chunky Sea-of-Thieves brass/iron coastal cage lantern with warm glowing amber glass core."""
    cx, cy, cz = center
    s = scale
    cap_mat = 'brass' if brass_body else 'iron'
    cap_col = C_GOLD_BRIGHT if brass_body else C_IRON
    rib_col = C_TEMPLE_GOLD if brass_body else C_BRASS
    with xf(mb, T(cx, cy, cz)):
        cyl(mb, 0.14 * s, -0.24 * s, -0.15 * s, 6, cap_mat, cap_col, False, 0.0, 0.175 * s)
        cyl(mb, 0.21 * s,  0.15 * s,  0.26 * s, 6, cap_mat, cap_col, False, 0.0, 0.068 * s)
        cyl(mb, 0.068 * s, 0.26 * s,  0.34 * s, 6, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.032 * s)
        cyl(mb, 0.125 * s, -0.15 * s, 0.15 * s, 6, 'glass', C_LANTERN_GL, False, 0.0, 0.138 * s)
        for k in range(4):
            ang = k * pi * 0.5 + pi * 0.25
            cbox(mb, (0.154 * s * cos(ang), 0.0, 0.154 * s * sin(ang)),
                 (0.028 * s, 0.31 * s, 0.028 * s), 'brass', rib_col, 0.0)
        with xf(mb, T(0.0, 0.37 * s, 0.0) @ M_Y2Z):
            torus(mb, 0.056 * s, 0.015 * s, 6, 4, 'iron', C_IRON, False)


def _build_flame_cluster(mb, center, radius=0.28, height=0.46, n_tongues=5):
    """Sculpted stylized low-poly warm glowing ember & flame tongues ('glass' + C_FLAME_*)."""
    cx, cy, cz = center
    with xf(mb, T(cx, cy, cz)):
        cyl(mb, radius * 0.88, -0.06, 0.07, 6, 'glass', C_FLAME_DEEP, False, 0.0, radius * 0.58)
        tongues = [
            ((0.0,           0.03,  0.0),          radius * 0.36, height * 1.00, ( 4.0,   0.0,  5.0), C_FLAME_CORE),
            ((-radius*0.32,  0.02, -radius*0.22),  radius * 0.24, height * 0.72, (-9.0,  22.0, 12.0), C_FLAME_MID),
            (( radius*0.30,  0.02,  radius*0.20),  radius * 0.24, height * 0.74, ( 8.0, -30.0,-10.0), C_FLAME_MID),
            (( radius*0.22,  0.01, -radius*0.30),  radius * 0.20, height * 0.58, (11.0,  42.0, -8.0), C_FLAME_DEEP),
            ((-radius*0.20,  0.01,  radius*0.28),  radius * 0.20, height * 0.60, (-10.0,-38.0, 10.0), C_FLAME_DEEP),
        ][:n_tongues]
        for tp, tr, th, trot, tcol in tongues:
            with xf(mb, T(tp) @ R('Y', trot[1]) @ R('X', trot[0]) @ R('Z', trot[2])):
                cyl(mb, tr, 0.0, th, 4, 'glass', tcol, False, 0.0, tr * 0.14)


def _build_coopered_cask(mb, M_bar, radius=0.33, height=0.82, rng=None,
                         mat='timber', col_a=C_TIMBER_MID, col_b=C_TIMBER_HI, col_head=C_TIMBER_DARK,
                         segs=7, stripe_col=None, hoop_mat='iron'):
    """Chunky coopered pirate cask / powder keg / clay supply barrel with forged hoops."""
    hh = height * 0.5
    prof = [
        (0.0,           -hh),
        (radius * 0.80, -hh),
        (radius * 0.96, -hh * 0.55),
        (radius,         0.0),
        (radius * 0.96,  hh * 0.55),
        (radius * 0.80,  hh),
        (0.0,            hh),
    ]
    stave_cols = [
        jit(col_a if k % 2 == 0 else col_b, rng, 0.07, 0.018) if rng else col_a
        for k in range(segs)
    ]
    with xf(mb, M_bar):
        lathe(mb, prof, segs, mat, col_a, False, False,
              lambda i, k: col_head if i in (0, 5) else stave_cols[k])
        for hi_idx, (hy, hr) in enumerate(((-hh * 0.68, radius * 0.95), (hh * 0.68, radius * 0.95))):
            hcol = C_ROPE if hoop_mat == 'rope' else (C_IRON_RUST if hi_idx == 1 else C_IRON)
            cyl(mb, hr, hy - 0.028, hy + 0.028, segs, hoop_mat, hcol, False, 0.0)
        if stripe_col is not None:
            cyl(mb, radius * 1.015, -hh * 0.18, hh * 0.18, segs, 'paint', stripe_col, False, 0.0)


def _build_stenciled_crate(mb, M_crate, size=(0.80, 0.70, 0.76), rng=None,
                           stripe_col=C_TEAL_BRIGHT, stencil_col=C_GOLD_BRIGHT):
    """Weathered pirate supply crate with battens, iron corners & painted emblem band."""
    sx, sy, sz = size
    hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
    with xf(mb, M_crate):
        cbox(mb, (0.0, 0.0, 0.0), (sx, sy, sz), 'timber',
             jit(C_TIMBER_MID, rng, 0.05) if rng else C_TIMBER_MID, 0.0, (1, 0, 0))
        for ys in (-hy + 0.052, hy - 0.052):
            for zs in (-hz - 0.014, hz + 0.014):
                cbox(mb, (0.0, ys, zs), (sx + 0.045, 0.090, 0.044), 'timber', C_TIMBER_HI, 0.0, (1, 0, 0))
            for xs in (-hx - 0.014, hx + 0.014):
                cbox(mb, (xs, ys, 0.0), (0.044, 0.090, sz + 0.02), 'timber', C_TIMBER_HI, 0.0, (0, 0, 1))
        for xs in (-hx - 0.014, hx + 0.014):
            for zs in (-hz - 0.014, hz + 0.014):
                cbox(mb, (xs, 0.0, zs), (0.064, sy + 0.02, 0.064), 'iron', C_IRON, 0.0)
        for zs in (-hz - 0.016, hz + 0.016):
            _add_beam(mb, (-hx + 0.08, -hy + 0.08, zs), (hx - 0.08, hy - 0.08, zs),
                      0.070, 0.028, 'timber', C_OAK_FRESH, 0.0)
        if stripe_col is not None:
            for zs in (-hz - 0.022, hz + 0.022):
                cbox(mb, (0.0, 0.0, zs), (sx * 0.66, 0.16, 0.016), 'paint', stripe_col, 0.0)
                cbox(mb, (0.0, 0.0, zs + (0.010 if zs > 0 else -0.010)),
                     (0.15, 0.15, 0.012), 'paint', stencil_col, 0.0, M=R('Z', 45.0))


def _add_leafy_vine_drape(mb, anchor, length, width, out_dir, rng, phase=0.0):
    """Sculpted hanging leafy jungle ivy/moss vine ('foliage') with UV2 wind weights (0 root -> 0.96 tip)."""
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
        out_off = 0.02 + 0.10 * sin(t * pi * 0.78) + 0.05 * t
        stem_pts.append(a + od * out_off + side * sway + Vector((0.0, -length * t, 0.0)))

    for i in range(segs):
        t0 = i / float(segs)
        t1 = (i + 1) / float(segs)
        w0 = width * 0.22 * (1.0 - 0.50 * t0)
        w1 = width * 0.22 * (1.0 - 0.72 * t1)
        p0, p1 = stem_pts[i], stem_pts[i + 1]
        c0 = jit(mix(C_VINE_DARK, C_VINE_MID, t0 * 0.85), rng, 0.05)
        c1 = jit(mix(C_VINE_MID, C_VINE_SUN, t1 * 0.85), rng, 0.05)
        u2_0 = (t0 * 0.88, phase)
        u2_1 = (t1 * 0.94, phase)
        mb.f(
            [mb.v(p0 - side * w0), mb.v(p0 + side * w0), mb.v(p1 + side * w1), mb.v(p1 - side * w1)],
            'foliage', [c0, c0, c1, c1],
            [(0.25, t0), (0.75, t0), (0.75, t1), (0.25, t1)],
            smooth=False, uv2=[u2_0, u2_0, u2_1, u2_1],
        )

    n_leaves = max(4, int(length * 1.85))
    for li in range(n_leaves):
        t = (li + 0.35) / float(n_leaves + 0.25)
        idx_f = t * segs
        i0 = min(segs - 1, int(idx_f))
        frac = idx_f - i0
        root = stem_pts[i0].lerp(stem_pts[i0 + 1], frac)
        sgn = -1.0 if (li % 2 == 0) else 1.0
        l_scale = (0.74 + 0.52 * sin(t * pi * 0.85)) * (1.0 - 0.34 * t)
        l_len = width * 1.42 * l_scale * rng.uniform(0.86, 1.15)
        l_wid = width * 0.58 * l_scale * rng.uniform(0.86, 1.14)
        l_dir = (side * (sgn * 0.66) + od * (0.48 + rng.uniform(-0.10, 0.16)) + Vector((0.0, -0.76, 0.0))).normalized()
        l_perp = l_dir.cross(od)
        l_perp = l_perp.normalized() if l_perp.length > 1e-4 else side

        p_base  = root
        p_mid_l = root + l_dir * (l_len * 0.42) - l_perp * l_wid + od * 0.035
        p_mid_r = root + l_dir * (l_len * 0.42) + l_perp * l_wid + od * 0.035
        p_tip   = root + l_dir * l_len - Vector((0.0, l_len * 0.12, 0.0))

        c_b = jit(mix(C_VINE_DARK, C_VINE_MID, t * 0.7), rng, 0.05)
        c_t = jit(mix(C_VINE_MID, C_VINE_SUN, 0.35 + 0.65 * t), rng, 0.06)
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


def _add_jungle_fern_cluster(mb, root_pos, scale=1.0, n_fronds=4, rng=None, phase=0.0, lean_dir=None):
    """Lush broad tropical jungle fern rosette ('foliage') with UV2 wind weights (0 root -> 0.92 tip)."""
    rp = Vector(root_pos)
    segs = 4
    base_rot = rng.uniform(0.0, 2.0 * pi) if rng else 0.0
    for fi in range(n_fronds):
        ang = base_rot + 2.0 * pi * fi / float(n_fronds) + (rng.uniform(-0.22, 0.22) if rng else 0.0)
        f_len = scale * (rng.uniform(0.86, 1.16) if rng else 1.0)
        f_w = scale * (rng.uniform(0.24, 0.32) if rng else 0.28)
        f_arch_h = scale * (rng.uniform(0.44, 0.64) if rng else 0.54)
        f_droop = scale * (rng.uniform(0.24, 0.40) if rng else 0.32)
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
            w = f_w * (0.20 + 0.95 * sin(t * pi * 0.86)) * (1.0 - 0.82 * (t ** 2.2))
            arch_y = sin(t * pi * 0.78) * f_arch_h - (t * t) * f_droop
            ctr = rp + dir_xz * (f_len * t) + Vector((0.0, arch_y, 0.0))
            v_lift = w * 0.22
            pl = ctr - side * w + Vector((0.0, v_lift, 0.0))
            pr = ctr + side * w + Vector((0.0, v_lift, 0.0))
            pm = ctr
            if prev_m is not None:
                t0 = (si - 1) / float(segs)
                c0 = jit(mix(C_FERN_DARK, C_FERN_MID, t0 * 0.9), rng, 0.05) if rng else C_FERN_MID
                c1 = jit(mix(C_FERN_MID, C_FERN_TIP, t * 0.92), rng, 0.05) if rng else C_FERN_TIP
                w0 = (t0 ** 1.35) * 0.92
                w1 = (t ** 1.35) * 0.92
                uv_l0, uv_m0, uv_r0 = (0.0, t0), (0.5, t0), (1.0, t0)
                uv_l1, uv_m1, uv_r1 = (0.0, t), (0.5, t), (1.0, t)
                u2_0 = (w0, f_phase)
                u2_1 = (w1, f_phase)
                if si == segs:
                    mb.f([mb.v(prev_l), mb.v(prev_m), mb.v(pm)], 'foliage',
                         [c0, c0, c1], [uv_l0, uv_m0, uv_m1], smooth=False, uv2=[u2_0, u2_0, u2_1])
                    mb.f([mb.v(prev_m), mb.v(prev_r), mb.v(pm)], 'foliage',
                         [c0, c0, c1], [uv_m0, uv_r0, uv_m1], smooth=False, uv2=[u2_0, u2_0, u2_1])
                else:
                    mb.f([mb.v(prev_l), mb.v(prev_m), mb.v(pm), mb.v(pl)], 'foliage',
                         [c0, c0, c1, c1], [uv_l0, uv_m0, uv_m1, uv_l1], smooth=False,
                         uv2=[u2_0, u2_0, u2_1, u2_1])
                    mb.f([mb.v(prev_m), mb.v(prev_r), mb.v(pr), mb.v(pm)], 'foliage',
                         [c0, c0, c1, c1], [uv_m0, uv_r0, uv_r1, uv_m1], smooth=False,
                         uv2=[u2_0, u2_0, u2_1, u2_1])
            prev_l, prev_m, prev_r = pl, pm, pr


def _add_kelp_drape(mb, anchor, length, width, out_dir, rng, phase=0.0, segs=4):
    """Graceful sinuous coastal sea-kelp twin-frond drape ('foliage') with UV2 wind weights."""
    a = Vector(anchor)
    od = Vector((out_dir[0], 0.0, out_dir[2]))
    if od.length < 1e-4:
        od = Vector((0.0, 0.0, -1.0))
    od.normalize()
    side = Vector((-od.z, 0.0, od.x))

    for l_mul, w_mul, s_shift, ph_off in ((1.0, 1.0, 0.0, 0.0), (0.72, 0.72, 0.14, 0.39)):
        prev_l = prev_r = None
        f_len = length * l_mul
        f_w = width * w_mul
        f_ph = (phase + ph_off) % 1.0
        for i in range(segs + 1):
            t = i / float(segs)
            w = f_w * (0.48 + 0.66 * sin(t * pi * 0.86)) * (1.0 - 0.64 * (t ** 1.25))
            sway = sin(t * 4.2 + f_ph * 6.28) * 0.22 * (0.18 + 0.82 * t) + s_shift * (0.4 + 0.6 * t)
            ctr = a + od * (0.05 + 0.26 * sin(t * pi * 0.65) + 0.12 * t) + side * sway + Vector((0.0, -f_len * t, 0.0))
            pl = ctr - side * w
            pr = ctr + side * w
            if prev_l is not None:
                t0 = (i - 1) / float(segs)
                c0 = jit(mix(C_KELP_DARK, C_KELP_MID, t0 * 0.78), rng, 0.05)
                c1 = jit(mix(C_KELP_MID, C_KELP_SUN, t * 0.86), rng, 0.05)
                uvs = [(0.0, t0), (1.0, t0), (1.0, t), (0.0, t)]
                uv2 = [(t0 * 0.85, f_ph), (t0 * 0.85, f_ph), (t * 0.96, f_ph), (t * 0.96, f_ph)]
                mb.f([mb.v(prev_l), mb.v(prev_r), mb.v(pr), mb.v(pl)],
                     'foliage', [c0, c0, c1, c1], uvs, smooth=False, uv2=uv2)
            prev_l, prev_r = pl, pr


def _build_wind_pennant(mb, root_pos, length=2.35, h0=0.58, out_dir=(0.76, -0.06, -0.64),
                        col_main=C_PAINT_RED, col_trim=C_GOLD_BRIGHT, phase=0.34):
    """Wind-whipped 3D double-sided tattered pirate swallowtail pennant ('paint') with UV2 wind weights."""
    rp = Vector(root_pos)
    od = Vector(out_dir).normalized()
    side = Vector((-od.z, 0.0, od.x))
    if side.length < 1e-4:
        side = Vector((1.0, 0.0, 0.0))
    side.normalize()
    segs = 6
    thick = 0.012

    top_pts = []
    bot_pts = []
    weights = []
    for i in range(segs + 1):
        t = i / float(segs)
        wave = sin(t * 2.35 * pi) * 0.24 * t + 0.04 * sin(t * 4.8)
        droop = -0.26 * t * t
        hh = h0 * (1.0 - 0.50 * t)
        if i in (3, 4):
            hh *= 0.84
        ctr = rp + od * (length * t) + side * wave + Vector((0.0, droop, 0.0))
        top_pts.append(ctr + Vector((0.0, hh * 0.5, 0.0)))
        bot_pts.append(ctr - Vector((0.0, hh * 0.5, 0.0)))
        weights.append((t ** 1.15) * 0.95)

    for i in range(segs):
        c_seg = col_trim if i == 0 else (C_CRIMSON_HI if i % 2 == 1 else col_main)
        t0, t1 = top_pts[i], top_pts[i + 1]
        b0, b1 = bot_pts[i], bot_pts[i + 1]
        w0, w1 = weights[i], weights[i + 1]
        u0, u1 = (w0, phase), (w1, phase)
        if i == segs - 1:
            mid_notch = (t0 + b0) * 0.26 + (t1 + b1) * 0.24 - od * (length * 0.14)
            um = (0.5 * (w0 + w1), phase)
            tris_u2 = [
                ([t0, t1, mid_notch], [u0, u1, um]),
                ([b0, mid_notch, b1], [u0, um, u1]),
                ([t0, mid_notch, b0], [u0, um, u0]),
            ]
            for tri, tu2 in tris_u2:
                f_pts = [p + side * thick for p in tri]
                b_pts = [p - side * thick for p in reversed(tri)]
                ctr_tri = sum(tri, Vector()) / 3.0
                mb.fp(f_pts, 'paint', c_seg, od, ctr_tri - side * 1.0, smooth=False, uv2=tu2)
                mb.fp(b_pts, 'paint', mul(c_seg, 0.84), od, ctr_tri + side * 1.0, smooth=False, uv2=list(reversed(tu2)))
        else:
            q_f = [t0 + side * thick, t1 + side * thick, b1 + side * thick, b0 + side * thick]
            q_b = [t1 - side * thick, t0 - side * thick, b0 - side * thick, b1 - side * thick]
            u_f = [u0, u1, u1, u0]
            u_b = [u1, u0, u0, u1]
            ctr_q = (t0 + t1 + b0 + b1) * 0.25
            mb.fp(q_f, 'paint', c_seg, od, ctr_q - side * 1.0, smooth=False, uv2=u_f)
            mb.fp(q_b, 'paint', mul(c_seg, 0.84), od, ctr_q + side * 1.0, smooth=False, uv2=u_b)
            mb.fp([t0 - side * thick, t1 - side * thick, t1 + side * thick, t0 + side * thick],
                  'paint', mul(c_seg, 0.78), od, ctr_q, smooth=False, uv2=[u0, u1, u1, u0])
            mb.fp([b0 + side * thick, b1 + side * thick, b1 - side * thick, b0 - side * thick],
                  'paint', mul(c_seg, 0.74), od, ctr_q, smooth=False, uv2=[u0, u1, u1, u0])


def _add_water_disk(mb, center, radius, segs=10):
    """Recessed dark reflective turquoise-slate water surface ('basalt' sheen + radial ripple shading)."""
    cx, cy, cz = center
    r_mid = radius * 0.56
    c_ctr = Vector((cx, cy + 0.012, cz))
    ring_m = [Vector((cx + r_mid * cos(2.0 * pi * k / segs),
                      cy + 0.006 * sin(k * 2.0),
                      cz + r_mid * sin(2.0 * pi * k / segs))) for k in range(segs)]
    ring_o = [Vector((cx + radius * cos(2.0 * pi * k / segs),
                      cy - 0.008,
                      cz + radius * sin(2.0 * pi * k / segs))) for k in range(segs)]
    inside = Vector((cx, cy - 0.5, cz))
    mb.newoff()
    for k in range(segs):
        kn = (k + 1) % segs
        mb.fp([c_ctr, ring_m[kn], ring_m[k]], 'basalt',
              [C_WATER_SPEC, C_WATER_MID, C_WATER_MID], (1, 0, 0), inside, smooth=False)
        mb.fp([ring_m[k], ring_m[kn], ring_o[kn], ring_o[k]], 'basalt',
              [C_WATER_MID, C_WATER_MID, C_WATER_DEEP, C_WATER_DEEP], (1, 0, 0), inside, smooth=False)


# ================================================================ 1. STONE WELL COURTYARD

def gen_stone_well_courtyard(outdir):
    """Weathered pirate-village mossy limestone wishing/water well (~4.6 m tall x ~4.4 m wide).
    Deeply skirted cobbled circular stone courtyard apron (y = -2.70..+0.08 m anti-float!),
    circular coursed ashlar well curb with beveled coping cap & recessed dark reflective
    turquoise-slate water surface, twin mortised oak upright posts on dressed stone pilasters,
    pitched weathered timber & terracotta-painted shingle roof canopy with carved ridge beam,
    iron crank windlass wrapped with coiled hemp rope suspending an iron-hooped oak water bucket,
    stone watering trough, clay supply barrel, wooden bench, draped ivy vines ('foliage' + UV2),
    & warm brass hanging lantern off the roof beam ('Lantern_Well').
    Target: 2,800-3,600 visual tris, 1 collider (col_well_base).
    """
    clear_scene()
    rng = random.Random(SEED + 2501)
    mb = MB('StoneWellCourtyard', seed=2501)

    SKIRT_BOT = -2.70
    APRON_Y = 0.08
    col_well_pts = []

    # 1. Deeply Skirted Cobbled Circular Stone Courtyard Apron (y = -2.70..+0.08 m, ~4.4 m wide!)
    apron_secs = [
        _reg_poly(0.0, SKIRT_BOT, 0.0, 2.34, sides=10, rot_deg=18.0),
        _reg_poly(0.0, -1.10,     0.0, 2.24, sides=10, rot_deg=18.0),
        _reg_poly(0.0, -0.14,     0.0, 2.20, sides=10, rot_deg=18.0),
        _reg_poly(0.0, APRON_Y,   0.0, 2.15, sides=10, rot_deg=18.0),
    ]
    _loft_horizontal_masonry(
        mb, apron_secs, 'limestone_moss',
        [C_TIDE_DARK, C_LIME_DARK, C_COBBLE_DARK, C_COBBLE_MID],
        rng, caps=(True, True), top_mat='limestone_moss', top_col=C_COBBLE_MID,
    )

    # Ring of 10 dressed perimeter curb stones framing the circular courtyard edge (~4.42 m diameter!)
    for k in range(10):
        ang = radians(18.0 + k * 36.0)
        ca, sa = cos(ang), sin(ang)
        col_s = jit(C_COBBLE_LIGHT if k % 2 == 0 else C_LIME_WARM, rng, 0.05)
        if k in (2, 6, 9):
            col_s = mix(col_s, C_LEDGE_MOSS, 0.34)
        cbox(mb, (ca * 2.04, APRON_Y + 0.025, sa * 2.04), (0.34, 0.13, 1.16),
             'limestone_moss' if k % 3 == 0 else 'limestone', col_s, 0.0,
             M=R('Y', -degrees(ang)))

    # 8 radial cobble paver slabs inlaid slightly proud on the courtyard apron (y = 0.08..0.115 m)
    for k in range(8):
        ang = radians(k * 45.0 + rng.uniform(-3.0, 3.0))
        rr = 1.48 + (0.06 if k % 2 == 0 else -0.04)
        pcol = jit(C_COBBLE_LIGHT if k % 3 == 0 else (C_LIME_MID if k % 3 == 1 else C_COBBLE_MID), rng, 0.06)
        cbox(mb, (cos(ang) * rr, APRON_Y + 0.015, sin(ang) * rr), (0.62, 0.06, 0.48),
             'limestone_moss' if k % 4 == 0 else 'temple_stone', pcol, 0.0,
             M=R('Y', -degrees(ang) + rng.uniform(-6.0, 6.0)))

    # 2. Circular Coursed Ashlar Well Curb + Outward-Normal Beveled Coping Cap + Dark Turquoise Water
    WELL_TOP = 1.00
    well_outer = [
        _reg_poly(0.0, APRON_Y - 0.04, 0.0, 0.99, sides=10, rot_deg=18.0),
        _reg_poly(0.0, 0.38,           0.0, 0.93, sides=10, rot_deg=18.0),
        _reg_poly(0.0, 0.70,           0.0, 0.91, sides=10, rot_deg=18.0),
        _reg_poly(0.0, WELL_TOP,       0.0, 0.92, sides=10, rot_deg=18.0),
    ]
    _loft_horizontal_masonry(
        mb, well_outer, 'limestone_moss',
        [mix(C_LIME_SHADE, C_SEA_MOSS, 0.32), C_LIME_MID, C_LIME_WARM, C_LIME_WARM],
        rng, caps=(False, False),
    )
    # Protruding hand-dressed coursed ashlar stone blocks wrapping the drum (skip x=±1.0 where post pilasters seat!)
    for row_i, (ry, rh, rr_b) in enumerate(((0.25, 0.24, 0.95), (0.55, 0.25, 0.92), (0.83, 0.23, 0.93))):
        for k in range(10):
            if (k + row_i) % 2 != 0:
                continue
            ang = radians(18.0 + k * 36.0 + row_i * 18.0)
            if abs(sin(ang)) < 0.28:
                continue  # leave clean seating for port/starboard stone post pilasters!
            bcol = jit(C_LIME_WARM if row_i == 2 else (C_LIME_MID if row_i == 1 else C_LIME_SHADE), rng, 0.05)
            if row_i == 0 and k in (0, 4, 8):
                bcol = mix(bcol, C_LEDGE_MOSS, 0.42)
            cbox(mb, (cos(ang) * rr_b, ry, sin(ang) * rr_b), (0.14, rh, 0.46),
                 'temple_stone' if row_i == 1 else 'limestone_moss', bcol, 0.0,
                 M=R('Y', -degrees(ang)))

    # Bold overhanging beveled circular stone coping rim (OUTWARD-WOUND lathe: outer goes UP, top INWARD, shaft DOWN!)
    coping_prof = [
        (0.92, 0.97),  # 0: shadowed underside drip lip (outward-down)
        (1.02, 0.97),  # 1
        (1.08, 1.01),  # 2: outer vertical fascia (outward)
        (1.08, 1.13),  # 3: outer chamfered top lip
        (1.03, 1.18),  # 4: sunlit flat coping top (upward)
        (0.75, 1.18),  # 5
        (0.71, 1.14),  # 6: inner lip bevel
        (0.70, 0.98),  # 7: inner dark wet stone shaft wall (inward toward water!)
        (0.68, 0.34),  # 8
    ]
    def _coping_col(i, k):
        if i >= 6:
            return mix(C_LIME_DARK, C_WATER_DEEP, 0.35)
        if i in (3, 4):
            return jit(mix(C_LIME_PALE, C_LEDGE_MOSS, 0.22 if k in (2, 3, 8) else 0.04), rng, 0.03)
        if i in (1, 2):
            return jit(C_LIME_WARM, rng, 0.04)
        return mul(C_LIME_SHADE, 0.80)
    lathe(mb, coping_prof, 10, 'limestone', C_LIME_PALE, False, False, _coping_col)

    # Recessed dark reflective turquoise-slate water surface inside the well shaft (y = 0.62 m)
    _add_water_disk(mb, (0.0, 0.62, 0.0), 0.70, segs=10)

    # Collider points for col_well_base (deep skirt + well curb + twin post span; outer courtyard walkable!)
    for y_c, r_c in ((SKIRT_BOT, 1.18), (APRON_Y, 1.15), (1.18, 1.12), (3.12, 1.06)):
        col_well_pts.extend(Vector(p) for p in _reg_poly(0.0, y_c, 0.0, r_c, sides=8, rot_deg=22.5))

    # 3. Twin Dressed Stone Side Pilasters + Mortised Oak Upright Posts + Diagonal Knee Braces
    POST_X = 0.92
    for sx in (-1.0, 1.0):
        px = sx * POST_X
        # Sturdy dressed stone pilaster abutment rising from courtyard floor up into coping collar!
        cbox(mb, (px, 0.62, 0.0), (0.34, 1.10, 0.36), 'temple_stone',
             jit(C_LIME_MID, rng, 0.04), 0.0)
        _bevel_slab(mb, (px, 1.24, 0.0), (0.38, 0.16, 0.40), 'limestone', C_LIME_PALE, 0.024)
        # Main mortised oak upright timber post seated cleanly atop the stone pilaster collar (y = 1.24..3.12 m!)
        cbox(mb, (px, 2.18, 0.0), (0.22, 1.92, 0.22), 'timber', jit(C_TIMBER_MID, rng, 0.04), 0.0, (0, 1, 0))
        # Forged-iron mounting collar straps around post base & mid-shaft
        for sy_s in (1.38, 2.04, 2.88):
            cbox(mb, (px, sy_s, 0.0), (0.255, 0.075, 0.255), 'iron',
                 C_IRON_RUST if sy_s < 1.5 else C_IRON, 0.0)
        # Diagonal mortised oak knee-braces supporting tie-beam & eaves overhangs
        _add_beam(mb, (px, 2.48, 0.0), (px - sx * 0.44, 3.02, 0.0), 0.12, 0.12, 'timber', C_TIMBER_HI, 0.0)
        for sz in (-1.0, 1.0):
            _add_beam(mb, (px, 2.52, sz * 0.06), (px, 3.04, sz * 0.56), 0.11, 0.12, 'timber', C_TIMBER_DARK, 0.0)

    # Heavy horizontal tie-beam spanning cleanly between the twin posts at y = 3.04 m
    cbox(mb, (0.0, 3.04, 0.0), (2.36, 0.20, 0.22), 'timber', C_TIMBER_MID, 0.0, (1, 0, 0))

    # 4. Pitched Weathered Timber & Terracotta-Painted Shingle Roof Canopy (~4.62 m peak!)
    RIDGE_Y = 4.46
    EAVE_Y = 2.94
    EAVE_Z = 1.30
    ROOF_HX = 1.48

    # Carved overhanging oak ridge beam (x = -1.66..+1.66 m, crowning to y = 4.62 m with brass scroll finials!)
    cbox(mb, (0.0, RIDGE_Y + 0.04, 0.0), (3.32, 0.20, 0.18), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
    for sx in (-1.0, 1.0):
        cbox(mb, (sx * 1.66, RIDGE_Y + 0.10, 0.0), (0.16, 0.22, 0.16), 'timber', C_OAK_FRESH, 0.0, M=R('Z', sx * -16.0))
        cbox(mb, (sx * 1.72, RIDGE_Y + 0.15, 0.0), (0.10, 0.12, 0.12), 'brass', C_TEMPLE_GOLD, 0.0)

    # Gable A-frame kingposts, diagonal rafters & bargeboards
    for sx in (-1.0, 1.0):
        gx = sx * POST_X
        cbox(mb, (gx, 3.74, 0.0), (0.16, 1.32, 0.16), 'timber', C_TIMBER_HI, 0.0, (0, 1, 0))
        for sz in (-1.0, 1.0):
            _add_beam(mb, (gx, RIDGE_Y, 0.0), (gx, EAVE_Y - 0.06, sz * EAVE_Z),
                      0.14, 0.14, 'timber', C_TIMBER_MID, 0.0)
            _add_beam(mb, (sx * ROOF_HX, RIDGE_Y + 0.04, 0.0),
                      (sx * ROOF_HX, EAVE_Y - 0.06, sz * (EAVE_Z + 0.05)),
                      0.075, 0.18, 'timber', C_TIMBER_DARK, 0.0)
        mb.fp([
            Vector((gx, 3.14, -1.04)), Vector((gx, 3.14, 1.04)), Vector((gx, RIDGE_Y - 0.06, 0.0)),
        ], 'timber', C_TIMBER_DARK, (1, 0, 0), Vector((0.0, 3.5, 0.0)), smooth=False)
        mb.fp([
            Vector((gx, 3.14,  1.04)), Vector((gx, 3.14, -1.04)), Vector((gx, RIDGE_Y - 0.06, 0.0)),
        ], 'timber', C_TIMBER_MID, (1, 0, 0), Vector((sx * 2.0, 3.5, 0.0)), smooth=False)

    # Eaves purlins & center rafters under roof sheathing
    for sz in (-1.0, 1.0):
        cbox(mb, (0.0, EAVE_Y + 0.02, sz * (EAVE_Z - 0.18)), (ROOF_HX * 2.0 + 0.10, 0.14, 0.14),
             'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
        for rx in (-0.32, 0.32):
            _add_beam(mb, (rx, RIDGE_Y - 0.04, 0.0), (rx, EAVE_Y - 0.04, sz * (EAVE_Z + 0.04)),
                      0.095, 0.12, 'timber', C_TIMBER_MID, 0.0)

    # Solid timber underside sheathing + 4 bold overlapping courses x 4 strips of terracotta shingles per slope!
    slope_ang = degrees(atan2(RIDGE_Y - EAVE_Y, EAVE_Z))
    slope_len = sqrt((RIDGE_Y - EAVE_Y) ** 2 + EAVE_Z ** 2) + 0.18
    for sz in (-1.0, 1.0):
        mid_z = sz * (EAVE_Z * 0.50)
        mid_y = 0.5 * (RIDGE_Y + EAVE_Y) + 0.06
        pitch = sz * slope_ang
        cbox(mb, (0.0, mid_y, mid_z), (ROOF_HX * 2.04, 0.075, slope_len),
             'timber', C_TIMBER_DARK, 0.0, M=R('X', pitch))

        n_courses = 4
        n_strips = 4
        sw = (ROOF_HX * 2.08) / float(n_strips)
        for ci in range(n_courses):
            t0 = (ci + 0.5) / float(n_courses)
            cz_c = sz * (EAVE_Z * (1.0 - t0 * 0.90) + 0.04)
            cy_c = EAVE_Y + (RIDGE_Y - EAVE_Y) * (t0 * 0.90) + 0.120
            for si in range(n_strips):
                sx_c = -ROOF_HX * 1.04 + (si + 0.5) * sw
                roll = (ci * 7 + si * 3 + (1 if sz > 0 else 0)) % 9
                if roll == 0:
                    s_mat, s_col = 'timber', jit(C_TIMBER_MID, rng, 0.06)
                elif roll == 4 and ci <= 1:
                    s_mat, s_col = 'paint', jit(mix(C_TERRA_DARK, C_LEDGE_MOSS, 0.48), rng, 0.05)
                elif roll in (1, 5):
                    s_mat, s_col = 'paint', jit(C_TERRA_HI, rng, 0.06)
                elif roll in (2, 6, 8):
                    s_mat, s_col = 'paint', jit(C_TERRA_MID, rng, 0.06)
                else:
                    s_mat, s_col = 'paint', jit(C_TERRA_DARK, rng, 0.06)
                tilted_p = pitch + sz * rng.uniform(-2.0, 2.0)
                cbox(mb, (sx_c, cy_c + rng.uniform(-0.01, 0.012), cz_c),
                     (sw - 0.028, 0.072, slope_len / float(n_courses) + 0.095),
                     s_mat, s_col, 0.0, M=R('X', tilted_p))

    # 5 chunky terracotta ridge cap tiles crowning the peak cleanly (y ≈ 4.54..4.62 m!)
    for ri in range(5):
        rx = -1.24 + ri * 0.62
        rc = jit(C_TERRA_HI if ri % 2 == 0 else C_TERRA_MID, rng, 0.05)
        with xf(mb, T(rx, RIDGE_Y + 0.14, 0.0) @ M_Y2X):
            cyl(mb, 0.135, -0.30, 0.30, 6, 'paint', rc, False, 0.0)

    # 5. Iron Crank Windlass Wrapped with Coiled Hemp Rope + Suspended Iron-Hooped Oak Water Bucket
    WIND_Y = 2.04
    for sx in (-1.0, 1.0):
        cbox(mb, (sx * 0.78, WIND_Y, 0.0), (0.09, 0.22, 0.24), 'iron', C_IRON, 0.0)
    with xf(mb, T(0.10, WIND_Y, 0.0) @ M_Y2X):
        cyl(mb, 0.036, -1.00, 1.12, 6, 'iron', C_IRON, False, 0.0)
    with xf(mb, T(0.0, WIND_Y, 0.0) @ M_Y2X):
        cyl(mb, 0.125, -0.70, 0.70, 8, 'timber', C_TIMBER_HI, False, 0.0)
        for ex in (-0.66, 0.66):
            cyl(mb, 0.155, ex - 0.032, ex + 0.032, 8, 'iron', C_IRON_RUST, False, 0.0)

    # Forged-iron S-crank handle protruding out the starboard post (+X = +1.16..+1.46 m)
    cbox(mb, (1.16, WIND_Y + 0.16, 0.0), (0.048, 0.36, 0.068), 'iron', C_IRON, 0.0)
    with xf(mb, T(1.30, WIND_Y + 0.32, 0.0) @ M_Y2X):
        cyl(mb, 0.034, -0.15, 0.15, 6, 'timber', C_OAK_FRESH, False, 0.0)
        cyl(mb, 0.044,  0.14, 0.18, 6, 'iron', C_IRON_RUST, False, 0.0)

    # 5 thick braided hemp rope coils wrapped tightly around the windlass barrel
    for ci in range(5):
        rx_c = -0.18 + ci * 0.090
        with xf(mb, T(rx_c, WIND_Y, 0.0) @ M_Y2X):
            torus(mb, 0.150, 0.036, 6, 4, 'rope', jit(C_ROPE, rng, 0.05), False)

    # Taut vertical drop rope descending cleanly from windlass roller down to the hanging bucket bail!
    BKT_X, BKT_Y, BKT_Z = 0.02, 1.34, -0.06
    rope_path = [
        (0.02, WIND_Y - 0.13, -0.13),
        (0.02, 1.78,          -0.10),
        (BKT_X, BKT_Y + 0.36, BKT_Z),
    ]
    tube(mb, rope_path, 0.026, 5, 'rope', C_ROPE, caps=(True, True), mode='flat')

    # Iron-hooped coopered oak water bucket hanging cleanly above the well curb (filled with turquoise water!)
    with xf(mb, T(BKT_X, BKT_Y, BKT_Z) @ R('Z', 5.0)):
        bkt_prof = [
            (0.0,  -0.18),
            (0.15, -0.18),
            (0.20,  0.18),
            (0.175, 0.18),
            (0.165, 0.08),
            (0.0,   0.08),
        ]
        lathe(mb, bkt_prof, 8, 'timber', C_TIMBER_MID, False, False,
              lambda i, k: C_TIMBER_DARK if i >= 4 else jit(C_TIMBER_HI if k % 2 == 0 else C_TIMBER_MID, rng, 0.05))
        cyl(mb, 0.174, -0.12, -0.075, 8, 'iron', C_IRON_RUST, False, 0.0)
        cyl(mb, 0.198,  0.075, 0.125, 8, 'iron', C_IRON, False, 0.0)
        _add_water_disk(mb, (0.0, 0.10, 0.0), 0.168, segs=8)
        bail_pts = [
            (-0.20, 0.14, 0.0), (-0.17, 0.29, 0.0),
            ( 0.00, 0.37, 0.0), ( 0.17, 0.29, 0.0), (0.20, 0.14, 0.0),
        ]
        tube(mb, bail_pts, 0.016, 4, 'iron', C_IRON, caps=(True, True), mode='flat')

    # 6. Courtyard Storytelling Props (seated solidly on APRON_Y = 0.08 m, zero floating!)
    # 6a. Carved Mossy Stone Watering Trough on port-front arc (x = -1.36, z = -0.82)
    M_trough = T(-1.36, APRON_Y, -0.82) @ R('Y', -32.0)
    with xf(mb, M_trough):
        cbox(mb, (0.0, 0.09, 0.0), (1.08, 0.18, 0.56), 'limestone_moss', C_LIME_SHADE, 0.0)
        cbox(mb, (0.0,  0.34, -0.23), (1.10, 0.36, 0.11), 'limestone', C_LIME_WARM, 0.0)
        cbox(mb, (0.0,  0.34,  0.23), (1.10, 0.36, 0.11), 'limestone_moss', mix(C_LIME_MID, C_LEDGE_MOSS, 0.28), 0.0)
        cbox(mb, (-0.49, 0.34, 0.0),  (0.12, 0.36, 0.36), 'limestone', C_LIME_WARM, 0.0)
        cbox(mb, ( 0.49, 0.34, 0.0),  (0.12, 0.36, 0.36), 'limestone', C_LIME_MID, 0.0)
        mb.fp([
            Vector((-0.44, 0.42, -0.18)), Vector(( 0.44, 0.42, -0.18)),
            Vector(( 0.44, 0.42,  0.18)), Vector((-0.44, 0.42,  0.18)),
        ], 'basalt', C_WATER_MID, (1, 0, 0), Vector((0.0, 0.0, 0.0)), smooth=False)

    # 6b. Ribbed Terracotta Clay Supply Barrel seated on starboard-front arc (x = +1.34, z = -0.68)
    _build_coopered_cask(
        mb, T(1.34, APRON_Y + 0.40, -0.68) @ R('Y', 24.0),
        radius=0.31, height=0.80, rng=rng,
        mat='paint', col_a=C_CLAY_WARM, col_b=C_CLAY_SHADE, col_head=C_TIMBER_DARK,
        segs=7, stripe_col=None, hoop_mat='rope',
    )
    with xf(mb, T(1.34, APRON_Y + 0.82, -0.68)):
        cyl(mb, 0.16, -0.02, 0.05, 6, 'timber', C_TIMBER_HI, False, 0.0)
        cbox(mb, (0.0, 0.06, 0.0), (0.14, 0.04, 0.045), 'timber', C_TIMBER_DARK, 0.0)
    # Chunky 2-turn coiled rope pile resting beside the barrel
    for ti in range(2):
        with xf(mb, T(1.52, APRON_Y + 0.036 + ti * 0.060, -0.06)):
            torus(mb, 0.24 - ti * 0.050, 0.034, 6, 4, 'rope', mul(C_ROPE, 0.90 + 0.08 * (ti % 2)), False)

    # 6c. Weathered Wooden Courtyard Bench curving cleanly along the rear-starboard apron
    M_bench = T(0.68, APRON_Y, 1.40) @ R('Y', 154.0)
    with xf(mb, M_bench):
        cbox(mb, (0.0, 0.44, 0.0), (1.32, 0.085, 0.40), 'timber', C_TIMBER_HI, 0.0, (1, 0, 0))
        for sx in (-0.48, 0.48):
            cbox(mb, (sx, 0.21, 0.0), (0.11, 0.42, 0.34), 'timber', C_TIMBER_MID, 0.0, (0, 1, 0))
            cbox(mb, (sx, 0.04, 0.0), (0.14, 0.08, 0.42), 'timber', C_TIMBER_DARK, 0.0, (0, 0, 1))
        cbox(mb, (0.0, 0.16, 0.0), (1.08, 0.075, 0.085), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))

    # 7. Draped Leafy Ivy Vines ('foliage' + UV2 wind weights!) rooted cleanly to eave fascia, post & well curb
    vine_specs = [
        ((-1.18, EAVE_Y + 0.06, -1.16), 1.62, 0.20, (-0.52, 0.0, -0.85), 0.12),
        ((-0.94, EAVE_Y + 0.06,  1.16), 1.54, 0.19, (-0.45, 0.0,  0.89), 0.34),
        (( 1.18, EAVE_Y + 0.06,  1.14), 1.34, 0.18, ( 0.58, 0.0,  0.81), 0.58),
        ((-1.02, 2.38,          -0.08), 1.24, 0.16, (-0.92, 0.0, -0.38), 0.74),
        ((-0.86, 1.14,           0.54), 0.90, 0.18, (-0.78, 0.0,  0.62), 0.89),
    ]
    for v_anc, v_len, v_w, v_dir, v_ph in vine_specs:
        _add_leafy_vine_drape(mb, v_anc, v_len, v_w, v_dir, rng, phase=v_ph)

    _add_jungle_fern_cluster(mb, (-1.62, APRON_Y + 0.02, 0.54), scale=0.56, n_fronds=4, rng=rng, phase=0.41, lean_dir=(-0.8, 0.0, 0.6))
    _add_jungle_fern_cluster(mb, ( 1.48, APRON_Y + 0.02, 0.92), scale=0.52, n_fronds=3, rng=rng, phase=0.73, lean_dir=( 0.8, 0.0, 0.6))

    # 8. Warm Brass Hanging Lantern off the Front Roof Beam ('Lantern_Well'!)
    HOOK_POS = Vector((-0.56, 2.98, -0.74))
    LANTERN_POS = Vector((-0.56, 2.48, -0.74))
    _add_beam(mb, (-0.56, 3.04, -0.14), HOOK_POS, 0.055, 0.075, 'iron', C_IRON, 0.0)
    _add_beam(mb, (-0.56, 3.12, -0.58), HOOK_POS, 0.045, 0.055, 'iron', C_IRON_RUST, 0.0)
    # Forged-iron hanging rod + ring connecting hook cleanly to lantern bale
    _add_beam(mb, HOOK_POS, (HOOK_POS.x, LANTERN_POS.y + 0.32, HOOK_POS.z), 0.026, 0.026, 'iron', C_IRON, 0.0)
    _build_harbour_lantern(mb, LANTERN_POS, scale=0.84, brass_body=True)

    build(mb)

    add_empty('Lantern_Well', LANTERN_POS)
    col_piece('col_well_base', col_well_pts)
    export_landmark_glb(outdir, 'stone_well_courtyard.glb')


# ================================================================ 2. RUINED SEA FORT CANNON BASTION

def _build_naval_cannon_assembly(mb, M_gun, rng):
    """Heavy oak wheeled naval gun carriage mounting a forged cast-iron barrel cannon with
    gleaming brass cascabel, trunnions & reinforce rings (aiming seaward along local -Z!).
    """
    with xf(mb, M_gun):
        # 1. Heavy oak wheeled naval gun carriage (local y = 0.0 is recoil deck top!)
        for az in (-0.36, 0.38):
            cbox(mb, (0.0, 0.17, az), (0.98, 0.15, 0.15), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
            for sx in (-0.46, 0.46):
                with xf(mb, T(sx, 0.165, az) @ M_Y2X):
                    cyl(mb, 0.165, -0.055, 0.055, 8, 'timber', C_TIMBER_MID, False, 0.0)
                    cyl(mb, 0.170, -0.045, 0.045, 8, 'iron', C_IRON_RUST, False, 0.0)
                    cyl(mb, 0.048, -0.075, 0.075, 5, 'iron', C_IRON, False, 0.0)

        cbox(mb, (0.0, 0.26, 0.04), (0.64, 0.095, 1.16), 'timber', C_TIMBER_DARK, 0.0, (0, 0, 1))
        cbox(mb, (0.0, 0.36, 0.44), (0.48, 0.13, 0.20),  'timber', C_OAK_FRESH, 0.0, (1, 0, 0))

        for sx in (-1.0, 1.0):
            cx = sx * 0.29
            cbox(mb, (cx, 0.48, -0.26), (0.11, 0.42, 0.54), 'timber', C_TIMBER_MID, 0.0, (0, 0, 1))
            cbox(mb, (cx, 0.43,  0.16), (0.11, 0.32, 0.36), 'timber', C_TIMBER_MID, 0.0, (0, 0, 1))
            cbox(mb, (cx, 0.37,  0.46), (0.11, 0.22, 0.30), 'timber', C_TIMBER_DARK, 0.0, (0, 0, 1))
            cbox(mb, (cx + sx * 0.058, 0.44, -0.14), (0.016, 0.20, 0.68), 'paint', C_PAINT_RED, 0.0)
            cbox(mb, (cx, 0.70, -0.18), (0.13, 0.045, 0.22), 'iron', C_IRON, 0.0)
            with xf(mb, T(cx + sx * 0.08, 0.44, 0.48) @ M_Y2X):
                torus(mb, 0.052, 0.016, 5, 4, 'iron', C_IRON, False)

        # 2. Forged Cast-Iron Naval Cannon Barrel (aiming seaward along -Z, +3 deg elevation!)
        TRUN_Y, TRUN_Z = 0.68, -0.18
        with xf(mb, T(0.0, TRUN_Y, TRUN_Z) @ R('X', 3.0)):
            with xf(mb, M_Y2X):
                cyl(mb, 0.068, -0.39, 0.39, 7, 'brass', C_GOLD_BRIGHT, False, 0.0)

            with xf(mb, R('X', -90.0)):
                prof = [
                    (0.00, -1.06),  # 0: cascabel tip (brass)
                    (0.08, -1.04),  # 1: cascabel ball
                    (0.10, -0.97),  # 2
                    (0.06, -0.90),  # 3: cascabel neck
                    (0.22, -0.84),  # 4: breech base ring (iron)
                    (0.25, -0.78),  # 5: base astragal (brass)
                    (0.25, -0.71),  # 6
                    (0.22, -0.68),  # 7: first reinforce (iron)
                    (0.21, -0.22),  # 8
                    (0.23, -0.19),  # 9: center reinforce ring (brass)
                    (0.23, -0.12),  # 10
                    (0.195,-0.09),  # 11: chase taper (iron)
                    (0.165, 0.62),  # 12
                    (0.185, 0.65),  # 13: chase astragal ring (brass)
                    (0.185, 0.71),  # 14
                    (0.155, 0.74),  # 15: neck before tulip muzzle
                    (0.150, 1.06),  # 16
                    (0.210, 1.15),  # 17: flared tulip muzzle swell
                    (0.215, 1.24),  # 18
                    (0.185, 1.28),  # 19: muzzle face
                    (0.110, 1.28),  # 20: dark bore lip
                    (0.105, 0.96),  # 21: recessed bore throat
                    (0.00,  0.96),  # 22
                ]
                brass_segs = {0, 1, 2, 3, 5, 9, 13}
                for i in range(len(prof) - 1):
                    seg = [prof[i], prof[i + 1]]
                    if i in brass_segs:
                        mat_s, col_s = 'brass', C_GOLD_BRIGHT if i <= 3 else C_BRASS
                    elif i >= 20:
                        mat_s, col_s = 'iron', C_IRON_DARK
                    else:
                        mat_s, col_s = 'iron', C_IRON if i % 2 == 0 else mix(C_IRON, C_IRON_RUST, 0.25)
                    lathe(mb, seg, 9, mat_s, col_s, False, False)


def gen_ruined_sea_fort_cannon_bastion(outdir):
    """Crumbling moss-draped warm sandstone coastal battery parapet (~7.0 m wide x 4.6 m deep x 3.8 m tall).
    Deep tapered ashlar foundation skirt (y = -3.60..+0.90 m, harmonized with Cloud Lead's Q5A sunlit
    warm sandstone masonry!), stepped stone gun deck with twin notched cannon embrasures & merlons
    (starboard corner partially collapsed with fallen corner ashlar rubble!), heavy oak wheeled naval
    gun carriage mounting a forged cast-iron barrel cannon with brass cascabel/trunnions aiming
    seaward (-Z), stacked pyramid of cast-iron cannonballs, banded powder kegs, iron mooring rings,
    wind-swaying draped sea-ivy ('foliage' + UV2), & forged iron wall-sconce torch bracket ('Lantern_Bastion').
    Target: 2,900-3,700 visual tris, 2 colliders (col_bastion_wall, col_bastion_deck).
    """
    clear_scene()
    rng = random.Random(SEED + 2502)
    mb = MB('RuinedSeaFortCannonBastion', seed=2502)

    SKIRT_BOT = -3.60
    DECK_Y = 1.85
    col_deck_pts = []
    col_wall_pts = []

    c_warm_hi   = mix(C_SAND_WARM, C_SAND_PALE, 0.42)
    c_pale_warm = mix(C_SAND_WARM, C_SAND_PALE, 0.72)
    c_ochre_sh  = mul(C_SAND_OCHRE, 0.70)

    # 1. Deep Tapered Ashlar Foundation Skirt (y = -3.60..+0.90 m anti-float!) & Battered Curtain Wall
    skirt_secs = [
        _rect_ring(-3.68, 3.68, SKIRT_BOT, -2.42, 2.26),
        _rect_ring(-3.58, 3.58, -1.35,     -2.30, 2.18),
        _rect_ring(-3.48, 3.48,  0.18,     -2.20, 2.12),
        _rect_ring(-3.42, 3.42,  0.90,     -2.14, 2.08),
    ]
    _loft_horizontal_masonry(
        mb, skirt_secs, 'limestone_moss',
        [C_TIDE_DARK, C_TIDE_MID, C_SAND_SHADE, C_SAND_OCHRE],
        rng, caps=(True, False),
    )
    for ring in skirt_secs:
        col_deck_pts.extend(Vector(p) for p in ring)

    # Projecting beveled sandstone water-table belt course at y = 0.86..1.08 m
    _bevel_slab(mb, (0.0, 0.97, -0.04), (7.02, 0.22, 4.38), 'limestone', C_SAND_PALE, 0.036,
                top_col=C_SAND_PALE, bot_col=c_ochre_sh)

    # Upper battered warm sunlit sandstone curtain body rising cleanly to DECK_Y = 1.85 m
    curtain_secs = [
        _rect_ring(-3.42, 3.42, 1.04,   -2.14, 1.38),
        _rect_ring(-3.36, 3.36, 1.46,   -2.06, 1.38),
        _rect_ring(-3.30, 3.30, DECK_Y, -1.98, 1.38),
    ]
    _loft_horizontal_masonry(
        mb, curtain_secs, 'limestone',
        [C_SAND_WARM, c_warm_hi, c_pale_warm],
        rng, caps=(False, True), top_mat='temple_stone', top_col=C_SAND_WARM,
    )
    for ring in curtain_secs:
        col_deck_pts.extend(Vector(p) for p in ring)

    # Projecting sandstone cordon / stringcourse lip crowning the seaward & side curtain wall (top at y = 1.83 m < DECK_Y!)
    _bevel_slab(mb, (0.0, 1.75, -0.34), (6.84, 0.16, 3.56), 'limestone', C_SAND_PALE, 0.028,
                top_col=C_SAND_PALE, bot_col=c_ochre_sh)

    # Stepped Rear Stone Gun-Deck Stairway ascending from rear landing (+Z = +1.38..+2.16 m) up to DECK_Y = 1.85 m!
    for si, (sy0, sy1, sz0, sz1, sw) in enumerate((
        (0.96, 1.24, 1.82, 2.18, 4.40),
        (0.96, 1.54, 1.56, 1.92, 4.60),
        (0.96, 1.83, 1.32, 1.66, 4.80),
    )):
        cbox(mb, (0.0, 0.5 * (sy0 + sy1), 0.5 * (sz0 + sz1)), (sw, sy1 - sy0, sz1 - sz0),
             'limestone_moss' if si == 0 else 'limestone',
             jit(c_warm_hi if si == 2 else C_SAND_WARM, rng, 0.04), 0.0)
        col_deck_pts.extend([Vector((-sw*0.5, sy1, sz1)), Vector((sw*0.5, sy1, sz1))])

    # Rear corner cheek-buttresses flanking the steps (x = ±2.82 m, z = +1.34..+2.10 m)
    for sx in (-1.0, 1.0):
        bh = 1.88 if sx < 0 else 1.58
        cbox(mb, (sx * 2.84, 0.96 + (bh - 0.96) * 0.5, 1.72), (1.06, bh - 0.96, 0.74),
             'limestone_moss' if sx > 0 else 'limestone',
             jit(C_SAND_WARM if sx < 0 else C_SAND_OCHRE, rng, 0.04), 0.0)

    # Alternating protruding dressed warm-sandstone corner quoins climbing BOTH seaward (-Z) corners!
    for sx in (-1.0, 1.0):
        for qi in range(4):
            qy = 0.26 + qi * 0.44
            t_q = (qy - 0.18) / (DECK_Y - 0.18)
            qx_edge = sx * (3.48 - 0.16 * max(0.0, t_q))
            qz_edge = -2.20 + 0.20 * max(0.0, t_q)
            long_x = (qi % 2 == 0)
            qw = 0.58 if long_x else 0.34
            qd = 0.34 if long_x else 0.58
            qx_c = qx_edge - sx * (qw * 0.5 - 0.06)
            qz_c = qz_edge + (qd * 0.5 - 0.06)
            cbox(mb, (qx_c, qy, qz_c), (qw, 0.34, qd), 'limestone',
                 jit(C_SAND_PALE if long_x else c_warm_hi, rng, 0.04), 0.0)

    # Heavy weathered oak recoil plank platform bolted cleanly atop DECK_Y behind the port embrasure!
    for sz_b in (-0.86, -0.08, 0.70):
        cbox(mb, (-1.22, DECK_Y + 0.025, sz_b), (2.26, 0.05, 0.12), 'timber', C_TIMBER_DARK, 0.0)
    for pi in range(5):
        pz_p = -0.86 + pi * 0.39
        cbox(mb, (-1.22, DECK_Y + 0.072, pz_p), (2.34, 0.055, 0.35),
             'timber', jit(C_TIMBER_HI if pi % 2 == 0 else C_TIMBER_MID, rng, 0.06), 0.0, (1, 0, 0))

    # 2. Seaward Parapet Wall with Twin Notched Cannon Embrasures & 3 Merlons (Starboard Partially Collapsed!)
    for ex_c in (-1.34, 1.34):
        loft(mb, [
            [(ex_c - 0.72, DECK_Y, -1.98), (ex_c + 0.72, DECK_Y, -1.98),
             (ex_c + 0.72, DECK_Y, -1.16), (ex_c - 0.72, DECK_Y, -1.16)],
            [(ex_c - 0.72, 2.34,   -1.98), (ex_c + 0.72, 2.34,   -1.98),
             (ex_c + 0.72, 2.50,   -1.16), (ex_c - 0.72, 2.50,   -1.16)],
        ], 'limestone', c_pale_warm, closed=True, caps=(False, True), mode='flat',
            scols=[C_SAND_WARM, C_SAND_PALE])

    def _add_intact_merlon(cx, cz, mw, mh, md, y_base):
        hw0, hd0 = mw * 0.5, md * 0.5
        hw1, hd1 = hw0 * 0.94, hd0 * 0.94
        y_top = y_base + mh
        _loft_horizontal_masonry(
            mb,
            [_rect_ring(cx - hw0, cx + hw0, y_base, cz - hd0, cz + hd0),
             _rect_ring(cx - hw1, cx + hw1, y_top,  cz - hd1, cz + hd1)],
            'limestone', [C_SAND_WARM, c_warm_hi], rng, caps=(False, True),
        )
        _bevel_slab(mb, (cx, y_top + 0.09, cz), (hw1 * 2.0 + 0.16, 0.18, hd1 * 2.0 + 0.16),
                    'limestone', C_SAND_PALE, 0.032, top_col=C_SAND_PALE, bot_col=c_ochre_sh)
        _bevel_slab(mb, (cx, y_top + 0.22, cz), (hw1 * 2.0 - 0.04, 0.12, hd1 * 2.0 - 0.04),
                    'limestone_moss', mix(C_SAND_PALE, C_LEDGE_MOSS, 0.18), 0.025)
        col_wall_pts.extend([
            Vector((cx - hw0, y_base, cz - hd0)), Vector((cx + hw0, y_base, cz + hd0)),
            Vector((cx - hw1, y_top + 0.28, cz - hd1)), Vector((cx + hw1, y_top + 0.28, cz + hd1)),
        ])

    _add_intact_merlon(-2.68, -1.56, 1.32, 1.64, 0.88, DECK_Y)
    _add_intact_merlon( 0.00, -1.56, 1.34, 1.58, 0.88, DECK_Y)
    for sx_c, cx_c in ((-1.0, -1.96), (1.0, -0.72)):
        cbox(mb, (cx_c, 2.90, -1.52), (0.22, 1.18, 0.72), 'temple_stone',
             jit(C_SAND_OCHRE, rng, 0.04), 0.0, M=R('Y', sx_c * -14.0))

    # Port side flank parapet return wall
    _loft_horizontal_masonry(
        mb,
        [_rect_ring(-3.30, -2.56, DECK_Y, -1.16, 1.16),
         _rect_ring(-3.26, -2.60, 3.04,   -1.16, 1.12)],
        'limestone_moss', [C_SAND_WARM, c_warm_hi], rng, caps=(False, True),
    )
    _bevel_slab(mb, (-2.93, 3.12, -0.02), (0.82, 0.16, 2.38), 'limestone', C_SAND_PALE, 0.028)
    col_wall_pts.extend([Vector((-3.30, DECK_Y, -1.16)), Vector((-2.56, 3.20, 1.16))])

    # Starboard PARTIALLY COLLAPSED corner merlon + bold tumbled corner ashlar rubble!
    breach_blocks = [
        ((2.44, 2.26, -1.56), (0.82, 0.82, 0.86),  0.0,  0.0, 'limestone_moss', C_SAND_WARM),
        ((3.00, 2.16, -1.56), (0.64, 0.62, 0.82),  3.0, -4.0, 'limestone_moss', C_SAND_OCHRE),
        ((2.32, 2.86, -1.54), (0.60, 0.48, 0.74), -4.0,  6.0, 'temple_stone',   c_warm_hi),
        ((2.96, 2.14, -0.62), (0.68, 0.60, 1.12),  0.0,  0.0, 'limestone_moss', C_SAND_WARM),
    ]
    for bp, bsz, bry, brz, bmat, bcol in breach_blocks:
        sculpt_stone_block(mb, bp, bsz, bmat, bcol, rng, chip=0.055,
                           M=R('Y', bry) @ R('Z', brz), moss_col=C_LEDGE_MOSS)
        col_wall_pts.append(Vector(bp) + Vector((0.0, bsz[1] * 0.5, 0.0)))

    rubble_specs = [
        ((2.16, DECK_Y + 0.19, -0.96), (0.58, 0.38, 0.48), ( 6,  24, -12), 'limestone',      c_pale_warm),
        ((2.64, DECK_Y + 0.17, -0.22), (0.52, 0.34, 0.44), (-8, -32,  14), 'limestone_moss', C_SAND_WARM),
        ((2.38, DECK_Y + 0.40, -0.68), (0.44, 0.28, 0.36), (16, -18,  22), 'temple_stone',   C_SAND_PALE),
        ((3.46, 0.34, -1.78),          (0.70, 0.44, 0.58), (14,  28, -18), 'limestone_moss', C_SAND_WARM),
        ((3.10, 0.18, -2.36),          (0.60, 0.38, 0.50), (-10,-22,  14), 'limestone',      C_SAND_PALE),
    ]
    for rp, rsz, rrot, rmat, rcol in rubble_specs:
        sculpt_stone_block(mb, rp, rsz, rmat, rcol, rng, chip=0.06,
                           M=R('Y', rrot[1]) @ R('X', rrot[0]) @ R('Z', rrot[2]), moss_col=C_LEDGE_MOSS)

    # 3. Heavy Oak Wheeled Naval Gun Carriage + Cast-Iron & Brass Cannon aiming seaward (-Z)!
    GUN_POS = Vector((-1.34, DECK_Y + 0.10, -0.46))
    M_gun = T(GUN_POS) @ R('Y', -3.0)
    _build_naval_cannon_assembly(mb, M_gun, rng)

    # Thick hemp breeching recoil rope arching cleanly outside carriage cheeks & wheels to cascabel!
    for sx_r, rx_w in ((-1.0, -2.14), (1.0, -0.56)):
        with xf(mb, T(rx_w, DECK_Y + 0.62, -1.13) @ M_Y2Z):
            torus(mb, 0.068, 0.018, 5, 4, 'iron', C_IRON, False)
        breech_path = [
            (rx_w,                    DECK_Y + 0.62, -1.12),
            (rx_w + sx_r * 0.06,      DECK_Y + 0.50, -0.34),
            (GUN_POS.x + sx_r * 0.44, DECK_Y + 0.54,  0.26),
            (GUN_POS.x,               DECK_Y + 0.74,  0.38),
        ]
        tube(mb, breech_path, 0.032, 5, 'rope', C_ROPE, caps=(True, True), mode='flat')

    # 4. Prominent Stacked 10-Ball Cast-Iron Cannonball Pyramid inside Timber Shot Garland!
    SHOT_CTR = Vector((0.28, DECK_Y, 0.14))
    for ang_d in (0.0, 120.0, 240.0):
        a_rad = radians(ang_d)
        cbox(mb, (SHOT_CTR.x + cos(a_rad) * 0.27, DECK_Y + 0.048, SHOT_CTR.z + sin(a_rad) * 0.27),
             (0.08, 0.095, 0.84), 'timber', C_TIMBER_DARK, 0.0, M=R('Y', -ang_d))
    r_ball = 0.108
    d_sp = r_ball * 2.02
    h_tri = d_sp * 0.866
    ball_offsets = []
    for row in range(3):
        n_in_row = 3 - row
        for ci in range(n_in_row):
            bx = (ci - (n_in_row - 1) * 0.5) * d_sp
            bz = (row - 0.66) * h_tri
            ball_offsets.append((bx, r_ball + 0.01, bz))
    for row in range(2):
        n_in_row = 2 - row
        for ci in range(n_in_row):
            bx = (ci - (n_in_row - 1) * 0.5) * d_sp
            bz = (row - 0.33) * h_tri + h_tri * 0.33
            ball_offsets.append((bx, r_ball + 0.01 + r_ball * 1.64, bz))
    ball_offsets.append((0.0, r_ball + 0.01 + r_ball * 3.28, h_tri * 0.33))

    for bi, boff in enumerate(ball_offsets):
        bm_b = bmesh.new()
        bmesh.ops.create_icosphere(bm_b, subdivisions=1, radius=r_ball)
        b_col = C_IRON if bi % 3 != 0 else mix(C_IRON, C_IRON_RUST, 0.32)
        with xf(mb, T(SHOT_CTR + Vector(boff))):
            for f in bm_b.faces:
                pts = [v.co.copy() for v in f.verts]
                mb.fp(pts, 'iron', jit(b_col, rng, 0.04), (1, 0, 0), Vector((0, 0, 0)), smooth=False)
        bm_b.free()

    # 5. Banded Gunpowder Kegs positioned cleanly starboard of the cannonball pyramid!
    _build_coopered_cask(
        mb, T(1.20, DECK_Y + 0.36, 0.54) @ R('Y', -22.0),
        radius=0.27, height=0.72, rng=rng,
        col_a=C_TIMBER_MID, col_b=C_TIMBER_DARK, col_head=C_TIMBER_DARK,
        segs=7, stripe_col=C_PAINT_RED,
    )
    _build_coopered_cask(
        mb, T(1.82, DECK_Y + 0.25, 0.78) @ R('Y', 34.0) @ R('Z', 90.0),
        radius=0.25, height=0.66, rng=rng,
        col_a=C_TIMBER_HI, col_b=C_TIMBER_MID, col_head=C_TIMBER_DARK,
        segs=7, stripe_col=C_PAINT_RED,
    )

    # 6. Forged-Iron Mooring Rings bolted into Dressed Sandstone Bosses on Seaward & Port Walls!
    for m_pos, m_rot in (
        (( 1.72, 1.38, -2.14), R('Y',   0.0)),
        ((-3.40, 1.38, -0.58), R('Y',  90.0)),
    ):
        with xf(mb, T(m_pos) @ m_rot):
            cbox(mb, (0.0, 0.0, 0.0), (0.34, 0.34, 0.14), 'limestone', C_SAND_PALE, 0.0)
            cbox(mb, (0.0, 0.0, -0.07), (0.14, 0.14, 0.08), 'iron', C_IRON_RUST, 0.0)
            with xf(mb, T(0.0, -0.14, -0.10) @ R('X', 16.0) @ M_Y2Z):
                torus(mb, 0.16, 0.038, 6, 4, 'iron', C_IRON, False)

    # 7. Wind-Swaying Draped Sea-Ivy ('foliage' + UV2) spilling over parapet, breach & seaward wall!
    ivy_specs = [
        ((-2.52, 3.68, -2.02), 2.15, 0.22, (-0.12, 0.0, -0.99), 0.10),
        (( 0.24, 3.56, -2.02), 1.92, 0.21, ( 0.08, 0.0, -0.99), 0.31),
        (( 2.46, 2.74, -1.96), 1.88, 0.22, ( 0.26, 0.0, -0.96), 0.54),
        (( 3.32, 2.28, -1.12), 1.76, 0.20, ( 0.96, 0.0, -0.28), 0.72),
        ((-3.34, 3.10,  0.42), 1.82, 0.20, (-0.98, 0.0,  0.18), 0.88),
        (( 2.12, 2.52, -1.06), 1.12, 0.18, (-0.20, 0.0,  0.98), 0.44),
    ]
    for i_anc, i_len, i_w, i_dir, i_ph in ivy_specs:
        _add_leafy_vine_drape(mb, i_anc, i_len, i_w, i_dir, rng, phase=i_ph)

    _add_jungle_fern_cluster(mb, (2.74, DECK_Y + 0.02, 0.30), scale=0.60, n_fronds=4, rng=rng, phase=0.22, lean_dir=(-0.7, 0.0, 0.7))
    _add_jungle_fern_cluster(mb, (-2.84, 3.20, 0.88), scale=0.50, n_fronds=4, rng=rng, phase=0.66, lean_dir=(0.4, 0.0, 0.9))

    # 8. Forged-Iron Wall-Sconce Torch Bracket mounted on Center Merlon ('Lantern_Bastion'!)
    SCONCE_WALL = Vector((-0.38, 2.86, -1.12))
    TORCH_CTR   = Vector((-0.38, 3.04, -0.82))
    LANTERN_POS = Vector((-0.38, 3.26, -0.82))
    cbox(mb, SCONCE_WALL, (0.18, 0.44, 0.06), 'iron', C_IRON, 0.0)
    _add_beam(mb, SCONCE_WALL + Vector((0.0, -0.14, 0.02)), TORCH_CTR + Vector((0.0, -0.14, 0.0)),
              0.048, 0.048, 'iron', C_IRON_RUST, 0.0)
    _add_beam(mb, SCONCE_WALL + Vector((0.0,  0.04, 0.02)), TORCH_CTR + Vector((0.0,  0.00, 0.0)),
              0.052, 0.052, 'iron', C_IRON, 0.0)
    with xf(mb, T(TORCH_CTR)):
        cyl(mb, 0.08, -0.16, 0.02, 6, 'iron', C_IRON_RUST, False, 0.0, 0.16)
        cyl(mb, 0.16,  0.02, 0.18, 6, 'iron', C_IRON, False, 0.0, 0.21)
        for k in range(4):
            ang = radians(45.0 + k * 90.0)
            cbox(mb, (cos(ang) * 0.19, 0.11, sin(ang) * 0.19), (0.030, 0.20, 0.030), 'iron', C_IRON_RUST, 0.0)
    _build_flame_cluster(mb, TORCH_CTR + Vector((0.0, 0.14, 0.0)), radius=0.20, height=0.38, n_tongues=4)

    build(mb)

    add_empty('Lantern_Bastion', LANTERN_POS)
    col_piece('col_bastion_deck', col_deck_pts)
    col_piece('col_bastion_wall', col_wall_pts)
    export_landmark_glb(outdir, 'ruined_sea_fort_cannon_bastion.glb')


# ================================================================ 3. PIRATE TREASURE VAULT DOOR

def _sculpt_vault_skull_crest(mb, center, scale, rng):
    """Weathered carved bone-stone pirate skull crest crowning the vault lintel (facing seaward -Z)."""
    cx, cy, cz = center
    s = scale
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
    for v in bm.verts:
        p = v.co.copy()
        x, y, z = p.x, p.y, p.z
        parietal = smooth01((y + 0.12) / 0.88)
        rx = (0.76 + 0.14 * parietal) * s
        ry = 0.68 * s
        rz = (0.62 + 0.08 * parietal) * s
        temp = max(0.0, 1.0 - ((y + 0.36) / 0.45) ** 2) * max(0.0, (abs(x) - 0.45) / 0.55)
        rx -= 0.15 * s * temp
        brow = max(0.0, 1.0 - abs(y + 0.08) / 0.22) * smooth01((-z - 0.25) / 0.55) * 0.14 * s
        v.co = Vector((x * rx, y * ry, z * rz - brow))
    bm.faces.ensure_lookup_table()
    mb.newoff()
    with xf(mb, T(cx, cy + 0.16 * s, cz)):
        for f in bm.faces:
            pts = [v.co.copy() for v in f.verts]
            fn = newell(pts)
            if fn.length < 1e-8:
                continue
            fn.normalize()
            fc = sum(pts, Vector()) / len(pts)
            c = C_SKULL_BONE if (fn.y > 0.28 or fc.z < -0.22 * s) else (C_SKULL_SHADE if fn.y < -0.25 else C_SKULL_MID)
            mb.fp(pts, 'skull_stone', jit(c, rng, 0.045), (1, 0, 0), Vector((0, 0, 0)), smooth=False)
    bm.free()

    with xf(mb, T(cx, cy, cz)):
        for sgn in (-1.0, 1.0):
            with xf(mb, T(sgn * 0.33 * s, 0.18 * s, -0.52 * s) @ R('Z', -16.0 * sgn)):
                cbox(mb, (0.0, 0.0, 0.0), (0.46 * s, 0.17 * s, 0.26 * s), 'skull_stone', C_SKULL_BONE, 0.0)
            with xf(mb, T(sgn * 0.54 * s, -0.14 * s, -0.40 * s) @ R('Y', -22.0 * sgn)):
                cbox(mb, (0.0, 0.0, 0.0), (0.26 * s, 0.24 * s, 0.32 * s), 'skull_stone', C_SKULL_MID, 0.0)
            with xf(mb, T(sgn * 0.29 * s, -0.02 * s, -0.48 * s) @ R('Z', -14.0 * sgn) @ M_Y2Z):
                cyl(mb, 0.22 * s, -0.12 * s, 0.16 * s, 5, 'basalt', C_SKULL_CAV, False, 0.0, 0.18 * s)
            with xf(mb, T(sgn * 0.28 * s, -0.02 * s, -0.56 * s)):
                cyl(mb, 0.10 * s, -0.08 * s, 0.08 * s, 4, 'skull_glow', C_RUNE_CORE, False, 0.0, 0.04 * s)
        with xf(mb, T(0.0, -0.24 * s, -0.55 * s) @ M_Y2Z):
            cyl(mb, 0.11 * s, -0.08 * s, 0.13 * s, 4, 'basalt', C_SKULL_CAV, False, 0.0, 0.05 * s)
        cbox(mb, (0.0, -0.39 * s, -0.36 * s), (0.82 * s, 0.26 * s, 0.46 * s), 'skull_stone', C_SKULL_MID, 0.0)
        for ti, tx in enumerate((-0.28, -0.14, 0.0, 0.14, 0.28)):
            th = (0.22 if ti in (1, 3) else 0.18) * s
            tz = -0.54 * s + abs(tx) * 0.22 * s
            cbox(mb, (tx * s, -0.56 * s, tz), (0.11 * s, th, 0.12 * s),
                 'skull_stone', C_GOLD_BRIGHT if ti == 2 else jit(C_SKULL_BONE, rng, 0.04), 0.0)


def _build_overflowing_treasure_chest(mb, M_chest, scale=0.82, rng=None):
    """Iron-banded oak treasure chest propped open, overflowing with gold coins & glowing gems."""
    w, h, d = 1.06 * scale, 0.50 * scale, 0.64 * scale
    hw, hh, hd = w * 0.5, h * 0.5, d * 0.5
    with xf(mb, M_chest):
        cbox(mb, (0.0, hh, 0.0), (w, h, d), 'timber', C_TIMBER_MID, 0.0, (1, 0, 0))
        for xs in (-hw + 0.05, hw - 0.05):
            cbox(mb, (xs, hh, 0.0), (0.078, h + 0.02, d + 0.032), 'iron', C_IRON, 0.0)
        cbox(mb, (0.0, h - 0.10, -hd - 0.026), (0.18, 0.18, 0.028), 'brass', C_GOLD_BRIGHT, 0.0)

        # Heaped glistening gold treasure mound overflowing the open chest!
        bm_g = bmesh.new()
        bmesh.ops.create_icosphere(bm_g, subdivisions=1, radius=1.0)
        with xf(mb, T(0.0, h + 0.02, 0.0) @ S(hw * 0.90, 0.20 * scale, hd * 0.88)):
            for f in bm_g.faces:
                pts = [v.co.copy() for v in f.verts]
                fc = sum(pts, Vector()) / len(pts)
                if fc.y < -0.15:
                    continue
                c_g = C_GOLD_BRIGHT if fc.y > 0.35 else C_TEMPLE_GOLD
                mb.fp(pts, 'brass', jit(c_g, rng, 0.05) if rng else c_g, (1, 0, 0), Vector((0, 0, 0)), smooth=False)
        bm_g.free()

        # Sparkling turquoise gems nestled in the gold pile
        for gp, gsz in (((-0.16*scale, h + 0.15*scale, -0.08*scale), 0.08*scale),
                        (( 0.16*scale, h + 0.14*scale, -0.10*scale), 0.07*scale)):
            cbox(mb, gp, (gsz, gsz * 1.3, gsz), 'skull_glow', C_RUNE_CORE, 0.0, M=R('Y', 38.0) @ R('Z', 24.0))

        # Vaulted oak lid hinged ~36 deg open along the rear edge (+hd)!
        with xf(mb, T(0.0, h, hd) @ R('X', 36.0) @ T(0.0, 0.0, -hd)):
            r_lid = hd * 1.02
            lid_ring = [(cos(pi * k / 4.0) * r_lid, sin(pi * k / 4.0) * (0.24 * scale)) for k in range(5)]
            secs = [
                [Vector((-hw - 0.015, py, -pz)) for pz, py in lid_ring] + [Vector((-hw - 0.015, 0.0, -hd))],
                [Vector(( hw + 0.015, py, -pz)) for pz, py in lid_ring] + [Vector(( hw + 0.015, 0.0, -hd))],
            ]
            loft(mb, secs, 'timber', C_TIMBER_HI, closed=True, caps=(True, True), mode='flat')
            for xs in (-hw + 0.05, hw - 0.05):
                rib_pts = [
                    Vector((xs, sin(pi * k / 3.0) * (0.265 * scale), -cos(pi * k / 3.0) * (r_lid + 0.018)))
                    for k in range(4)
                ]
                tube(mb, rib_pts, 0.030, 4, 'iron', C_IRON, mode='flat')


def gen_pirate_treasure_vault_door(outdir):
    """Dramatic carved mossy temple-rock cliffside vault portal (~6.2 m wide x 5.8 m tall).
    Deep -3.4 m tapered rock-heel backing & stepped threshold skirt extending back along +Z
    for seamless cliff-face & terrace embedding! Monumental arched iron-strapped dark oak
    double vault doors sealed by a bold sculpted gilded-brass 8-spoke skull-and-cutlass locking
    wheel & heavy iron cross-bar, flanked by carved stone totem pilasters with glowing turquoise
    rune medallions ('skull_glow'), weathered carved skull-crest lintel, overflowing banded
    treasure chest & gold-trimmed amphora/crate outside the threshold, cascading wind-swaying
    jungle vines ('foliage' + UV2), & twin carved stone entrance fire-braziers ('Lantern_Vault').
    Target: 2,900-3,700 visual tris, 1 collider (col_vault_frame).
    """
    clear_scene()
    rng = random.Random(SEED + 2503)
    mb = MB('PirateTreasureVaultDoor', seed=2503)

    SKIRT_BOT = -3.40
    THRESH_Y = 0.28
    col_frame_pts = []

    # 1. Deep Tapered Cliffside Rock-Heel Backing & Stepped Threshold Skirt (y = -3.40..+5.70 m, z back to +3.40 m!)
    # Clean non-overlapping threshold terrace (z = -1.78..+3.10 m) + lower skirt plunging to y = -3.40 m!
    skirt_secs = [
        _rect_ring(-3.16, 3.16, SKIRT_BOT, -2.28, 3.40),
        _rect_ring(-3.10, 3.10, -1.25,     -2.20, 3.25),
        _rect_ring(-3.04, 3.04,  0.00,     -2.16, 3.12),
        _rect_ring(-2.98, 2.98,  THRESH_Y, -1.42, 2.98),
    ]
    _loft_horizontal_masonry(
        mb, skirt_secs, 'limestone_moss',
        [C_TIDE_DARK, C_LIME_DARK, C_TEMPLE_DARK, C_TEMPLE_MID],
        rng, caps=(True, True), top_mat='temple_stone', top_col=C_TEMPLE_MID,
    )
    for ring in skirt_secs:
        col_frame_pts.extend(Vector(p) for p in ring)

    # Two crisp non-overlapping entrance steps cleanly in front of skirt_secs top (ZERO coplanar z-fighting!)
    _bevel_slab(mb, (0.0, 0.08, -2.06), (4.60, 0.16, 0.42), 'temple_stone', C_TEMPLE_MID, 0.022)
    _bevel_slab(mb, (0.0, 0.16, -1.64), (4.20, 0.24, 0.44), 'temple_stone', C_TEMPLE_HI,  0.022)

    # Sculpted 8-sided tapered mossy temple-cliff rock heel extending rearward along +Z (z = -0.38..+3.28 m!)
    def _cliff_ring(y, rx, zf, zb, ch_f=0.55, ch_b=0.85):
        return [
            (-rx + ch_f, y, zf), ( rx - ch_f, y, zf),
            ( rx,        y, zf + ch_f), ( rx,        y, zb - ch_b),
            ( rx - ch_b, y, zb), (-rx + ch_b, y, zb),
            (-rx,        y, zb - ch_b), (-rx,        y, zf + ch_f),
        ]
    heel_secs = [
        _cliff_ring(0.24, 3.12, -0.44, 3.24, 0.42, 0.65),
        _cliff_ring(1.85, 3.06, -0.42, 3.10, 0.48, 0.78),
        _cliff_ring(3.65, 2.86, -0.40, 2.82, 0.56, 0.90),
        _cliff_ring(4.86, 2.48, -0.36, 2.38, 0.58, 0.88),
        _cliff_ring(5.42, 1.88, -0.30, 1.84, 0.48, 0.72),
    ]
    _loft_horizontal_masonry(
        mb, heel_secs, 'limestone_moss',
        [C_LIME_SHADE, C_LIME_MID, mix(C_LIME_WARM, C_LEDGE_MOSS, 0.28),
         mix(C_LIME_WARM, C_LEDGE_MOSS, 0.44), mix(C_LIME_PALE, C_LEDGE_MOSS, 0.54)],
        rng, caps=(False, True), top_mat='limestone_moss', top_col=mix(C_LIME_WARM, C_LEDGE_MOSS, 0.58),
    )
    for ring in heel_secs:
        col_frame_pts.extend(Vector(p) for p in ring)

    # Organic sculpted cliff crag boulders nestled smoothly into the flank shoulders & crown!
    for rpos, rrad, rrot in (
        ((-2.48, 1.65,  0.42), (0.78, 1.52, 1.08), ( 4,  12,  6)),
        (( 2.48, 1.60,  0.42), (0.78, 1.48, 1.08), (-4, -14, -6)),
    ):
        sculpt_rock_mass(
            mb, rpos, rrad, 'limestone_moss',
            C_LIME_WARM, C_LIME_MID, C_LIME_DARK, rng,
            subdiv=1, warp=0.18, strata=0.12, flat_top=0.82,
            rot_deg=rrot, crag_ribs=5, rib_amp=0.10, moss_cap=0.52,
        )

    # 2. Flanking Carved Stone Totem Pilasters with Glowing Turquoise Rune Medallions ('skull_glow')
    for sx in (-1.0, 1.0):
        px = sx * 1.82
        _bevel_slab(mb, (px, THRESH_Y + 0.18, -0.84), (1.02, 0.36, 1.06), 'temple_stone', C_TEMPLE_MID, 0.030)
        _loft_horizontal_masonry(
            mb,
            [_rect_ring(px - 0.44, px + 0.44, 0.62, -1.26, -0.40),
             _rect_ring(px - 0.40, px + 0.40, 3.94, -1.22, -0.42)],
            'temple_stone', [C_TEMPLE_MID, C_TEMPLE_HI], rng, caps=(False, True),
        )
        _bevel_slab(mb, (px, 4.04, -0.82), (0.98, 0.22, 1.02), 'temple_stone', C_TEMPLE_HI, 0.028)
        _bevel_slab(mb, (px, 4.22, -0.82), (1.08, 0.16, 1.10), 'limestone_moss',
                    mix(C_LIME_WARM, C_LEDGE_MOSS, 0.26), 0.026)
        for gy in (1.32, 2.74, 3.58):
            cbox(mb, (px, gy, -1.24), (0.86, 0.12, 0.10), 'temple_stone', C_TEMPLE_DARK, 0.0)
        # Twin Glowing Turquoise Rune Medallions inlaid into each pilaster front face (y = 2.02 m & y = 3.16 m!)
        for my, mr in ((2.02, 0.24), (3.16, 0.20)):
            with xf(mb, T(px, my, -1.25) @ M_Y2Z):
                cyl(mb, mr + 0.06, -0.04, 0.04, 6, 'brass', C_TEMPLE_GOLD, False, 0.0)
                cyl(mb, mr * 0.78,  0.00, 0.06, 6, 'basalt', C_SKULL_CAV, False, 0.0)
            cbox(mb, (px, my, -1.31), (mr * 1.15, 0.052, 0.036), 'skull_glow', C_RUNE_CORE, 0.0, M=R('Z',  45.0))
            cbox(mb, (px, my, -1.31), (mr * 1.15, 0.052, 0.036), 'skull_glow', C_RUNE_CORE, 0.0, M=R('Z', -45.0))

    # 3. Monumental Segmented Arch Voussoir Stones + Weathered Carved Skull-Crest Lintel (~5.84 m Peak!)
    ARCH_Y = 3.24
    ARCH_R = 1.44
    n_vous = 7
    for vi in range(n_vous):
        ang = radians(18.0 + vi * (144.0 / float(n_vous - 1)))
        is_key = (vi == n_vous // 2)
        vx = cos(ang) * (ARCH_R + (0.14 if is_key else 0.08))
        vy = ARCH_Y + sin(ang) * (ARCH_R + (0.14 if is_key else 0.08))
        vw = 0.56 if is_key else 0.44
        vh = 0.72 if is_key else 0.54
        vd = 0.96 if is_key else 0.84
        vcol = C_LIME_PALE if is_key else jit(C_TEMPLE_HI if vi % 2 == 0 else C_TEMPLE_MID, rng, 0.04)
        cbox(mb, (vx, vy, -0.82), (vw, vh, vd),
             'limestone' if is_key else 'temple_stone', vcol, 0.0,
             M=R('Z', degrees(ang) - 90.0))

    # Heavy Stepped Temple-Stone Entablature Lintel & Pediment (y = 4.34..5.28 m)
    _bevel_slab(mb, (0.0, 4.46, -0.82), (4.86, 0.28, 1.24), 'temple_stone', C_TEMPLE_MID, 0.032)
    _bevel_slab(mb, (0.0, 4.72, -0.84), (5.16, 0.24, 1.38), 'limestone',    C_LIME_WARM,  0.036,
                top_col=C_LIME_PALE, bot_col=C_TEMPLE_DARK)
    # Stepped ruin pediment shoulder blocks & carved stepped stone brackets flanking the central skull!
    for sx in (-1.0, 1.0):
        cbox(mb, (sx * 1.52, 5.04, -0.78), (1.58, 0.40, 0.96), 'limestone_moss',
             mix(C_LIME_MID, C_LEDGE_MOSS, 0.30), 0.0, M=R('Z', sx * -14.0))
        cbox(mb, (sx * 0.96, 5.10, -1.04), (0.34, 0.40, 0.32), 'temple_stone', C_TEMPLE_HI, 0.0, M=R('Z', sx * 12.0))
    # Carved stone backing stele behind the skull crest
    _bevel_slab(mb, (0.0, 5.26, -0.68), (1.36, 0.86, 0.72), 'temple_stone', C_TEMPLE_MID, 0.032)
    col_frame_pts.extend([Vector((-2.58, 4.86, -1.48)), Vector((2.58, 4.86, -1.48)), Vector((0.0, 5.86, -1.14))])

    # Weathered Carved Skull-Crest Lintel raised cleanly proud above the lintel cornice (peaking ~5.86 m!)
    _sculpt_vault_skull_crest(mb, (0.0, 5.32, -1.04), scale=0.68, rng=rng)

    # 4. Monumental Arched Iron-Strapped Dark Oak Double Vault Doors (z = -0.50 m, y = 0.28..4.58 m)
    DOOR_Z = -0.50
    for sx in (-1.0, 1.0):
        cbox(mb, (sx * 1.38, 2.02, DOOR_Z - 0.12), (0.24, 3.48, 0.42), 'temple_stone', C_TEMPLE_DARK, 0.0)

    n_planks_per_leaf = 4
    leaf_w = 1.28
    pw = leaf_w / float(n_planks_per_leaf)
    for sx in (-1.0, 1.0):
        for pi in range(n_planks_per_leaf):
            px_p = sx * ((pi + 0.5) * pw + 0.015)
            x_edge = min(ARCH_R - 0.05, abs(px_p))
            y_top_p = ARCH_Y + sqrt(max(0.04, ARCH_R * ARCH_R - x_edge * x_edge))
            ph = y_top_p - THRESH_Y
            pcol = jit(C_TIMBER_DARK if (pi % 2 == 0) else mul(C_TIMBER_MID, 0.82), rng, 0.05)
            cbox(mb, (px_p, THRESH_Y + ph * 0.5, DOOR_Z), (pw - 0.018, ph, 0.22),
                 'timber', pcol, 0.0, (0, 1, 0))
        cbox(mb, (sx * 0.032, 2.40, DOOR_Z - 0.115), (0.055, 4.24, 0.035), 'iron', C_IRON, 0.0)

    # Forged-iron arched door rim frame & 3 pairs of heavy horizontal iron hinge straps with bold rivets!
    arch_rim_pts = [
        Vector((cos(radians(k * 22.5)) * 1.30, ARCH_Y + sin(radians(k * 22.5)) * 1.30, DOOR_Z - 0.11))
        for k in range(9)
    ]
    tube(mb, arch_rim_pts, 0.068, 4, 'iron', C_IRON, caps=(True, True), mode='flat')

    for sy_h in (0.86, 2.66, 3.48):
        for sx in (-1.0, 1.0):
            cbox(mb, (sx * 0.68, sy_h, DOOR_Z - 0.12), (1.18, 0.14, 0.042), 'iron',
                 C_IRON_RUST if sy_h < 1.2 else C_IRON, 0.0)
            with xf(mb, T(sx * 1.29, sy_h, DOOR_Z - 0.14)):
                cyl(mb, 0.058, -0.10, 0.10, 5, 'iron', C_IRON_RUST, False, 0.0)
            for rx_r in (0.34, 0.96):
                cbox(mb, (sx * rx_r, sy_h, DOOR_Z - 0.15), (0.062, 0.062, 0.034), 'iron', C_IRON_DARK, 0.0)

    # 5. Heavy Forged-Iron Cross-Bar + Bold Sculpted Gilded-Brass 8-Spoke Skull-and-Cutlass Locking Wheel!
    BAR_Y = 1.98
    BAR_Z = DOOR_Z - 0.19
    cbox(mb, (0.0, BAR_Y, BAR_Z), (3.44, 0.19, 0.12), 'iron', C_IRON, 0.0, (1, 0, 0))
    for sx in (-1.0, 1.0):
        cbox(mb, (sx * 1.62, BAR_Y, BAR_Z - 0.04), (0.26, 0.34, 0.24), 'iron', C_IRON_RUST, 0.0)
        cbox(mb, (sx * 1.74, BAR_Y, BAR_Z), (0.075, 0.22, 0.15), 'brass', C_TEMPLE_GOLD, 0.0)

    WH_POS = Vector((0.0, BAR_Y, BAR_Z - 0.14))
    R_WHEEL = 0.68
    with xf(mb, T(WH_POS)):
        with xf(mb, T(0.0, 0.0, 0.09) @ M_Y2Z):
            cyl(mb, 0.42, -0.05, 0.05, 8, 'iron', C_IRON, False, 0.0)
        with xf(mb, M_Y2Z):
            torus(mb, R_WHEEL,        0.070, 10, 4, 'brass', C_GOLD_BRIGHT, False)
            torus(mb, R_WHEEL * 0.56, 0.038,  8, 4, 'brass', C_TEMPLE_GOLD, False)
            cyl(mb,   0.25, -0.07, 0.07, 6, 'brass', C_BRASS, False, 0.0)

        # 8 radial turned gilded-brass spokes terminating in faceted grip-handle knobs past the rim!
        for k in range(8):
            ang = radians(k * 45.0)
            ca, sa = cos(ang), sin(ang)
            _add_beam(mb, (ca * 0.20, sa * 0.20, 0.0), (ca * (R_WHEEL + 0.20), sa * (R_WHEEL + 0.20), 0.0),
                      0.058, 0.058, 'brass', C_GOLD_BRIGHT if k % 2 == 0 else C_BRASS, 0.0)
            cbox(mb, (ca * (R_WHEEL + 0.23), sa * (R_WHEEL + 0.23), 0.0),
                 (0.095, 0.095, 0.095), 'brass', C_GOLD_BRIGHT, 0.0, M=R('Z', k * 45.0 + 45.0))

        # Twin crossed boarding cutlasses behind the central skull hub!
        for sgn in (-1.0, 1.0):
            with xf(mb, T(0.0, 0.0, -0.04) @ R('Z', sgn * 42.0)):
                cbox(mb, (0.0,  0.14, 0.0), (0.085, 0.92, 0.028), 'iron', C_IRON, 0.0)
                cbox(mb, (0.0,  0.62, 0.0), (0.052, 0.22, 0.022), 'iron', C_SKULL_BONE, 0.0, M=R('Z', sgn * 14.0))
                cbox(mb, (0.0, -0.34, 0.0), (0.24,  0.05, 0.065), 'brass', C_GOLD_BRIGHT, 0.0)
                cbox(mb, (0.0, -0.48, 0.0), (0.052, 0.24, 0.048), 'timber', C_TIMBER_DARK, 0.0)

        # Central sculpted gilded-brass mini-skull medallion boss with glowing eyes!
        with xf(mb, T(0.0, 0.03, -0.09)):
            cyl(mb, 0.19, -0.06, 0.14, 6, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.15)
            cbox(mb, (0.0, -0.11, -0.04), (0.22, 0.12, 0.12), 'brass', C_BRASS, 0.0)
            for sgn in (-1.0, 1.0):
                cbox(mb, (sgn * 0.075, 0.02, -0.14), (0.062, 0.062, 0.035), 'skull_glow', C_RUNE_CORE, 0.0)

    # 6. Overflowing Banded Treasure Chest + Gold-Trimmed Amphora & Crate outside Threshold!
    _build_overflowing_treasure_chest(
        mb, T(-1.74, THRESH_Y, -1.56) @ R('Y', 26.0), scale=0.80, rng=rng,
    )
    _build_stenciled_crate(
        mb, T(1.86, THRESH_Y + 0.34, -1.52) @ R('Y', -24.0),
        size=(0.76, 0.68, 0.72), rng=rng, stripe_col=C_TEAL_BRIGHT, stencil_col=C_GOLD_BRIGHT,
    )
    # Tall ribbed terracotta & gold-trimmed amphora leaning beside the crate!
    with xf(mb, T(1.22, THRESH_Y, -1.54) @ R('Y', 18.0) @ R('Z', 6.0)):
        amph_prof = [
            (0.00, 0.00), (0.12, 0.00), (0.16, 0.12), (0.25, 0.36),
            (0.26, 0.52), (0.14, 0.68), (0.11, 0.80), (0.16, 0.86),
            (0.14, 0.90), (0.09, 0.90), (0.08, 0.76), (0.00, 0.76),
        ]
        lathe(mb, amph_prof, 6, 'paint', C_CLAY_WARM, False, False,
              lambda i, k: C_CLAY_SHADE if i <= 2 else (C_TERRA_HI if i % 2 == 0 else C_CLAY_WARM))
        cyl(mb, 0.268, 0.42, 0.49, 6, 'brass', C_GOLD_BRIGHT, False, 0.0)
        cyl(mb, 0.170, 0.84, 0.90, 6, 'brass', C_GOLD_BRIGHT, False, 0.0)
        for sx in (-1.0, 1.0):
            h_pts = [(sx * 0.13, 0.80, 0.0), (sx * 0.25, 0.70, 0.0), (sx * 0.24, 0.52, 0.0)]
            tube(mb, h_pts, 0.022, 4, 'brass', C_TEMPLE_GOLD, caps=(True, True), mode='flat')

    # 7. Twin Carved Stone Entrance Fire-Braziers flanking the Threshold ('Lantern_Vault'!)
    for sx in (-1.0, 1.0):
        bx, bz = sx * 2.48, -1.78
        _loft_horizontal_masonry(
            mb,
            [_reg_poly(bx, 0.00, bz, 0.44, sides=6, rot_deg=30.0),
             _reg_poly(bx, 0.72, bz, 0.34, sides=6, rot_deg=30.0),
             _reg_poly(bx, 0.94, bz, 0.42, sides=6, rot_deg=30.0)],
            'temple_stone', [C_TEMPLE_DARK, C_TEMPLE_MID, C_TEMPLE_HI], rng, caps=(True, True),
        )
        with xf(mb, T(bx, 0.96, bz)):
            cyl(mb, 0.28, 0.00, 0.14, 6, 'iron', C_IRON_RUST, False, 0.0, 0.46)
            cyl(mb, 0.46, 0.14, 0.28, 6, 'iron', C_IRON, False, 0.0, 0.50)
            for k in range(4):
                ang = radians(45.0 + k * 90.0)
                cbox(mb, (cos(ang) * 0.47, 0.24, sin(ang) * 0.47), (0.048, 0.22, 0.048), 'brass', C_TEMPLE_GOLD, 0.0)
        _build_flame_cluster(mb, (bx, 1.20, bz), radius=0.32, height=0.52, n_tongues=4)
        col_frame_pts.append(Vector((bx, 1.45, bz)))

    # 8. Cascading Wind-Swaying Jungle Vines ('foliage' + UV2) & Threshold Fern Clusters!
    vault_vines = [
        ((-1.92, 4.78, -1.42), 2.35, 0.22, (-0.28, 0.0, -0.96), 0.14),
        (( 1.96, 4.78, -1.42), 2.18, 0.22, ( 0.28, 0.0, -0.96), 0.38),
        ((-0.78, 4.86, -1.28), 1.48, 0.19, (-0.10, 0.0, -0.99), 0.62),
        (( 0.84, 4.86, -1.28), 1.36, 0.18, ( 0.12, 0.0, -0.99), 0.84),
    ]
    for v_anc, v_len, v_w, v_dir, v_ph in vault_vines:
        _add_leafy_vine_drape(mb, v_anc, v_len, v_w, v_dir, rng, phase=v_ph)

    _add_jungle_fern_cluster(mb, (-2.68, 0.24, -1.04), scale=0.72, n_fronds=3, rng=rng, phase=0.18, lean_dir=(-0.8, 0.0, -0.6))
    _add_jungle_fern_cluster(mb, ( 2.68, 0.24, -1.02), scale=0.70, n_fronds=3, rng=rng, phase=0.55, lean_dir=( 0.8, 0.0, -0.6))

    LANTERN_POS = Vector((0.0, 1.88, -1.78))

    build(mb)

    add_empty('Lantern_Vault', LANTERN_POS)
    col_piece('col_vault_frame', col_frame_pts)
    export_landmark_glb(outdir, 'pirate_treasure_vault_door.glb')


# ================================================================ 4. WOODEN SHIPWRECK CROW'S NEST MAST

def _build_tattered_sail_shred(mb, M_mast, yard_y, yard_z, yard_roll_deg, yard_yaw_deg, rng, phase=0.22):
    """Wind-whipped tattered galleon canvas sail shred ('paint') lashed along the angled yardarm
    billowing cleanly forward of the crow's nest with UV2 wind weights (0.0 yardarm -> 0.96 tatters!).
    """
    M_yard = M_mast @ T(0.0, yard_y, yard_z) @ R('Y', yard_yaw_deg) @ R('Z', yard_roll_deg)
    cols_x = [-2.22, -1.48, -0.68, 0.14, 0.92]
    drop_lens = [1.85, 2.48, 1.42, 2.18, 1.05]
    n_rows = 4
    thick = 0.015

    grid = []
    w_grid = []
    for ci, lx in enumerate(cols_x):
        col_pts = []
        col_w = []
        # Attach cleanly to the seaward (-Z) underside of the yardarm spar
        top_w = M_yard @ Vector((lx, -0.10, -0.14))
        dlen = drop_lens[ci]
        for ri in range(n_rows + 1):
            t = ri / float(n_rows)
            # Strong seaward (-Z) billow keeps tattered sail cleanly clear of the crow's nest basket!
            billow_z = -sin(t * pi * 0.72) * 1.18 - 0.44 * t + 0.08 * sin(ci * 1.9 + t * 4.5)
            billow_x = 0.24 * (t ** 1.3) + 0.06 * cos(ci * 2.1 + t * 3.8)
            p = top_w + Vector((billow_x, -dlen * t, billow_z))
            col_pts.append(p)
            col_w.append((t ** 1.25) * 0.95)
        grid.append(col_pts)
        w_grid.append(col_w)

    for ci in range(len(cols_x) - 1):
        for ri in range(n_rows):
            if ci == 1 and ri >= 2:
                continue  # torn vertical slit in sail
            p00 = grid[ci][ri]
            p10 = grid[ci + 1][ri]
            p11 = grid[ci + 1][ri + 1]
            p01 = grid[ci][ri + 1]
            w00, w10 = w_grid[ci][ri], w_grid[ci + 1][ri]
            w11, w01 = w_grid[ci + 1][ri + 1], w_grid[ci][ri + 1]
            u00, u10 = (w00, phase + ci * 0.11), (w10, phase + ci * 0.11)
            u11, u01 = (w11, phase + ci * 0.11), (w01, phase + ci * 0.11)

            if ri == 1:
                c_f = jit(mix(C_PAINT_RED, C_CANVAS_SHADE, 0.35), rng, 0.05)
            else:
                c_f = jit(C_CANVAS_WARM if ri == 0 else C_CANVAS_SHADE, rng, 0.05)

            nrm = newell([p00, p10, p11, p01])
            if nrm.length < 1e-5:
                continue
            nrm.normalize()
            ctr = (p00 + p10 + p11 + p01) * 0.25

            if ri == n_rows - 1:
                tip = (p01 + p11) * 0.5 + Vector((0.08, -0.34, -0.14))
                ut = (0.97, phase + ci * 0.11)
                for tri, tu2 in (([p00, p10, tip], [u00, u10, ut]),
                                 ([p00, tip, p01], [u00, ut, u01])):
                    f_pts = [p + nrm * thick for p in tri]
                    b_pts = [p - nrm * thick for p in reversed(tri)]
                    mb.fp(f_pts, 'paint', c_f, (1, 0, 0), ctr - nrm * 1.0, smooth=False, uv2=tu2)
                    mb.fp(b_pts, 'paint', mul(c_f, 0.84), (1, 0, 0), ctr + nrm * 1.0, smooth=False, uv2=list(reversed(tu2)))
            else:
                q_f = [p + nrm * thick for p in (p00, p10, p11, p01)]
                q_b = [p - nrm * thick for p in (p10, p00, p01, p11)]
                mb.fp(q_f, 'paint', c_f, (1, 0, 0), ctr - nrm * 1.0, smooth=False, uv2=[u00, u10, u11, u01])
                mb.fp(q_b, 'paint', mul(c_f, 0.84), (1, 0, 0), ctr + nrm * 1.0, smooth=False, uv2=[u10, u00, u01, u11])


def gen_wooden_shipwreck_crow_nest_mast(outdir):
    """Dramatic ~12 deg leaning splintered galleon mainmast (~9.6 m tall!) rooted deeply in a jagged
    barnacle-and-moss coastal limestone/reef rock outcrop (y = -3.60..+1.50 m deep anti-float rock base!).
    Heavy banded iron-hooped weathered oak mast spar with broken jagged upper tip & angled splintered
    yardarm, planked timber crow's nest lookout basket with iron-bound railings & hanging rusted ship's
    bell, tattered wind-whipped sail cloth shred & pirate crimson swallowtail pennant (UV2 wind weights!),
    draped hemp rope shrouds & ratline rungs, wedged driftwood crate at the rock base, & a swinging brass
    cage storm-lantern off the yardarm ('Lantern_CrowNest').
    Target: 2,700-3,600 visual tris, 2 colliders (col_mast_base, col_mast_trunk).
    """
    clear_scene()
    rng = random.Random(SEED + 2504)
    mb = MB('WoodenShipwreckCrowNestMast', seed=2504)

    SKIRT_BOT = -3.60
    col_base_pts = []
    col_trunk_pts = []

    # 1. Deep Jagged Barnacle-and-Moss Coastal Limestone/Reef Rock Outcrop (y = -3.60..+1.50 m anti-float!)
    # Top skirt ring tucked inside sculpted rock crag so only organic reef rock shows above ground!
    skirt_secs = [
        _reg_poly(0.0, SKIRT_BOT, 0.0, 2.95, sides=8, rot_deg=20.0),
        _reg_poly(0.0, -1.55,     0.0, 2.60, sides=8, rot_deg=22.0),
        _reg_poly(0.0,  0.14,     0.0, 1.94, sides=8, rot_deg=24.0),
    ]
    _loft_horizontal_masonry(
        mb, skirt_secs, 'limestone_moss',
        [C_TIDE_DARK, C_LIME_DARK, mix(C_LIME_SHADE, C_SEA_MOSS, 0.35)],
        rng, caps=(True, True), top_mat='limestone_moss', top_col=C_LIME_MID,
    )
    for ring in skirt_secs:
        col_base_pts.extend(Vector(p) for p in ring)

    col_base_pts += sculpt_rock_mass(
        mb, (0.0, 0.16, 0.0), (2.28, 1.38, 2.18), 'limestone_moss',
        C_LIME_PALE, C_LIME_WARM, C_TIDE_DARK, rng,
        subdiv=2, warp=0.26, strata=0.16, flat_top=0.82, base_flare=0.34,
        rot_deg=(0, 18, 0), crag_ribs=6, rib_amp=0.16, moss_cap=0.58,
    )
    for rpos, rrad, rrot in (
        ((-1.72, 0.08, -0.78), (1.16, 1.02, 1.08), ( 8,  32, -12)),
        (( 1.62, 0.04,  0.86), (1.18, 0.96, 1.06), (-6, -28,  10)),
        ((-0.26, 0.12,  1.54), (1.30, 1.08, 1.04), ( 5,  14,  -6)),
    ):
        col_base_pts += sculpt_rock_mass(
            mb, rpos, rrad, 'limestone_moss',
            C_LIME_WARM, C_LIME_MID, C_TIDE_DARK, rng,
            subdiv=1, warp=0.22, strata=0.14, flat_top=0.76, base_flare=0.36,
            rot_deg=rrot, crag_ribs=5, rib_amp=0.14, moss_cap=0.45,
        )

    # Clustered pale sea-barnacle cones studded across the wet coastal splash-zone rock shoulders!
    barnacle_spots = [
        (-1.42, 0.78, -1.16, 0.18, 0.12), (-1.18, 0.62, -1.32, 0.14, 0.10),
        ( 0.88, 0.86, -1.38, 0.19, 0.13), ( 1.12, 0.74, -1.24, 0.15, 0.10),
        (-1.74, 0.56,  0.42, 0.17, 0.12), ( 1.64, 0.64,  0.28, 0.18, 0.12),
        ( 0.24, 0.92, -1.46, 0.16, 0.11), (-0.54, 1.12, -1.04, 0.15, 0.10),
        ( 0.72, 1.08,  1.12, 0.17, 0.12), (-0.98, 0.96,  1.06, 0.16, 0.11),
    ]
    for bx, by, bz, br, bh in barnacle_spots:
        with xf(mb, T(bx, by, bz) @ R('X', rng.uniform(-22, 22)) @ R('Z', rng.uniform(-22, 22))):
            cyl(mb, br, -0.05, bh, 5, 'limestone',
                C_BARNACLE_HI if rng.random() > 0.35 else C_BARNACLE_MID, False, 0.0, br * 0.44)

    _add_beam(mb, (-0.82, 0.15, -0.42), (-1.58, 1.48, -1.06), 0.18, 0.22, 'timber', C_DRIFTWOOD, 0.0)
    _add_beam(mb, ( 0.74, 0.20,  0.38), ( 1.48, 1.38,  0.96), 0.17, 0.21, 'timber', C_TIMBER_DARK, 0.0)

    # Wedged Driftwood Supply Crate lodged cleanly into the starboard-front reef rock pocket!
    _build_stenciled_crate(
        mb, T(1.38, 0.76, -0.82) @ R('Y', -32.0) @ R('Z', -12.0) @ R('X', 8.0),
        size=(0.80, 0.68, 0.74), rng=rng, stripe_col=C_TEAL_BRIGHT, stencil_col=C_PAINT_CREAM,
    )
    col_base_pts.append(Vector((1.78, 1.18, -1.18)))

    # 2. Dramatic ~12 deg Leaning Heavy Banded Iron-Hooped Galleon Mainmast (~9.60 m Tall!)
    M_mast = T(0.0, 0.35, 0.0) @ R('Z', -11.5) @ R('X', 3.5)
    YARD_Y = 7.42
    YARD_Z = -0.34
    YARD_YAW = 14.0
    YARD_ROLL = -8.5

    with xf(mb, M_mast):
        mast_secs = []
        mast_cols = []
        for ly, lr, mc in (
            (-1.60, 0.48, C_TIMBER_DARK),
            ( 0.85, 0.43, C_DRIFTWOOD),
            ( 3.20, 0.38, C_TIMBER_MID),
            ( 5.45, 0.34, C_DRIFTWOOD),
            ( 7.42, 0.29, C_TIMBER_MID),
            ( 8.48, 0.25, C_TIMBER_HI),
        ):
            mast_secs.append(_reg_poly(0.0, ly, 0.0, lr, sides=8, rot_deg=22.5))
            mast_cols.append(mc)
        loft(mb, mast_secs, 'timber', C_TIMBER_MID, closed=True, caps=(True, True), mode='flat', scols=mast_cols)

        for hy, hr in ((1.55, 0.44), (2.75, 0.415), (4.05, 0.385), (5.08, 0.365), (6.95, 0.32), (8.18, 0.28)):
            cyl(mb, hr, hy - 0.045, hy + 0.045, 8, 'iron',
                C_IRON_RUST if hy < 3.5 else C_IRON, False, 0.0)

        # Broken Jagged Splintered Upper Mast Tip (peaking ~9.60 m!)
        splinters = [
            ( 0.00,  0.00, 0.14, 1.08,  3.0, -4.0, C_OAK_FRESH),
            (-0.14, -0.08, 0.11, 0.78, -9.0,  7.0, C_TIMBER_HI),
            ( 0.15, -0.06, 0.10, 0.64,  8.0, -6.0, C_OAK_FRESH),
            (-0.08,  0.14, 0.10, 0.86, -5.0, -9.0, C_DRIFTWOOD),
            ( 0.10,  0.12, 0.09, 0.54,  7.0,  8.0, C_TIMBER_MID),
        ]
        for spx, spz, spr, sph, srx, srz, spc in splinters:
            with xf(mb, T(spx, 8.40, spz) @ R('X', srx) @ R('Z', srz)):
                cyl(mb, spr, 0.0, sph, 4, 'timber', spc, False, 0.0, 0.018)

        # 3. Planked Timber Crow's Nest Lookout Basket + Iron Railings + Outward-Normal Rusted Ship's Bell!
        CN_Y = 5.52
        for k in range(4):
            ang = radians(45.0 + k * 90.0)
            ca, sa = cos(ang), sin(ang)
            _add_beam(mb, (ca * 0.32, CN_Y - 0.86, sa * 0.32), (ca * 1.10, CN_Y - 0.06, sa * 1.10),
                      0.13, 0.14, 'timber', C_TIMBER_DARK, 0.0)
        cbox(mb, (0.0, CN_Y - 0.10, 0.0), (2.22, 0.15, 0.22), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
        cbox(mb, (0.0, CN_Y - 0.10, 0.0), (0.22, 0.15, 2.22), 'timber', C_TIMBER_DARK, 0.0, (0, 0, 1))
        cyl(mb, 1.20, CN_Y - 0.04, CN_Y + 0.08, 8, 'timber', C_TIMBER_MID, False, 0.0)

        for k in range(8):
            ang = radians(22.5 + k * 45.0)
            ca, sa = cos(ang), sin(ang)
            post_a = radians(k * 45.0)
            _add_beam(mb, (cos(post_a) * 1.10, CN_Y + 0.02, sin(post_a) * 1.10),
                      (cos(post_a) * 1.26, CN_Y + 1.24, sin(post_a) * 1.26),
                      0.11, 0.11, 'timber', C_TIMBER_DARK, 0.0)
            for row_i, (ry_off, rr_p, ph_p) in enumerate(((0.32, 1.16, 0.38), (0.76, 1.22, 0.38))):
                if k == 2 and row_i == 1:
                    continue
                pcol = jit(C_DRIFTWOOD if (k + row_i) % 2 == 0 else C_TIMBER_HI, rng, 0.05)
                with xf(mb, T(ca * rr_p, CN_Y + ry_off, sa * rr_p) @ R('Y', -degrees(ang)) @ R('Z', -7.5)):
                    cbox(mb, (0.0, 0.0, 0.0), (0.075, ph_p, 0.88), 'timber', pcol, 0.0, (0, 0, 1))

        with xf(mb, T(0.0, CN_Y + 0.48, 0.0)):
            torus(mb, 1.21, 0.032, 8, 4, 'iron', C_IRON_RUST, False)
        with xf(mb, T(0.0, CN_Y + 1.00, 0.0)):
            torus(mb, 1.28, 0.036, 8, 4, 'iron', C_IRON, False)
        with xf(mb, T(0.0, CN_Y + 1.24, 0.0)):
            torus(mb, 1.30, 0.044, 8, 4, 'timber', C_TIMBER_HI, False)

        # Hanging Rusted Ship's Bell mounted on starboard-front crow's nest rim (OUTWARD-WOUND lathe profile!)
        BELL_X, BELL_Z = 0.72, -1.24
        _add_beam(mb, (0.58, CN_Y + 1.18, -1.04), (BELL_X, CN_Y + 1.14, BELL_Z - 0.04), 0.055, 0.055, 'iron', C_IRON, 0.0)
        _add_beam(mb, (0.58, CN_Y + 0.84, -1.02), (BELL_X, CN_Y + 1.14, BELL_Z - 0.02), 0.045, 0.045, 'iron', C_IRON_RUST, 0.0)
        with xf(mb, T(BELL_X, CN_Y + 0.86, BELL_Z) @ R('X', 8.0)):
            # Bottom-to-top outward-wound profile so outer bell catches sunlight crisply!
            bell_prof = [
                (0.00, -0.10), (0.13, -0.14), (0.20, -0.20), (0.22, -0.18),
                (0.16, -0.08), (0.12,  0.04), (0.09,  0.14), (0.06,  0.22), (0.00, 0.24),
            ]
            c_bell_rust = mix(C_IRON_RUST, C_BRASS_DARK, 0.45)
            lathe(mb, bell_prof, 8, 'iron', c_bell_rust, False, False,
                  lambda i, k: C_IRON_RUST if i in (3, 6) else c_bell_rust)
            cyl(mb, 0.032, -0.24, -0.10, 5, 'iron', C_IRON, False, 0.0)
            tube(mb, [(0.0, -0.22, 0.0), (0.03, -0.44, -0.04), (-0.02, -0.64, -0.02)],
                 0.016, 4, 'rope', C_ROPE, caps=(True, True), mode='flat')

        # 4. Angled Splintered Yardarm lashed cleanly across the seaward face of the upper mast!
        with xf(mb, T(0.0, YARD_Y, YARD_Z) @ R('Y', YARD_YAW) @ R('Z', YARD_ROLL)):
            with xf(mb, M_Y2X):
                cyl(mb, 0.14, -2.65, 0.0, 7, 'timber', C_DRIFTWOOD, False, 0.0, 0.19)
                cyl(mb, 0.19,  0.0, 2.02, 7, 'timber', C_TIMBER_MID, False, 0.0, 0.13)
                for yx, yr in ((-2.28, 0.155), (-1.15, 0.175), (0.0, 0.205), (1.18, 0.172)):
                    cyl(mb, yr, yx - 0.045, yx + 0.045, 7, 'iron', C_IRON_RUST if yx > 0 else C_IRON, False, 0.0)
            for sy_s, sz_s, slen in ((0.05, 0.03, 0.48), (-0.05, -0.04, 0.36), (0.01, -0.06, 0.56)):
                with xf(mb, T(2.00, sy_s, sz_s) @ M_Y2X @ R('X', rng.uniform(-10, 10))):
                    cyl(mb, 0.065, 0.0, slen, 4, 'timber', C_OAK_FRESH, False, 0.0, 0.014)

        for r_ang in (-32.0, 32.0):
            with xf(mb, T(0.0, YARD_Y, -0.18) @ R('Z', r_ang) @ R('X', 38.0)):
                torus(mb, 0.36, 0.048, 8, 4, 'rope', C_ROPE, False)

    for ly_c, lr_c in ((0.20, 0.65), (3.40, 0.58), (5.52, 1.24), (6.78, 1.32), (8.60, 0.45)):
        for p_loc in _reg_poly(0.0, ly_c, 0.0, lr_c, sides=6, rot_deg=0.0):
            col_trunk_pts.append(M_mast @ Vector(p_loc))

    # 5. Tattered Wind-Whipped Sail Cloth Shred & Pirate Crimson Swallowtail Pennant (UV2 wind weights!)
    _build_tattered_sail_shred(mb, M_mast, YARD_Y, YARD_Z, YARD_ROLL, YARD_YAW, rng, phase=0.22)

    pennant_root = M_mast @ Vector((0.0, 8.58, 0.0))
    _build_wind_pennant(
        mb, pennant_root, length=2.48, h0=0.60, out_dir=(0.74, -0.08, -0.66),
        col_main=C_PAINT_RED, col_trim=C_GOLD_BRIGHT, phase=0.46,
    )

    # 6. Draped Hemp Rope Shrouds & Climbable Ratline Rungs!
    shroud_specs = [
        (Vector((-0.44, 5.24, -0.34)), Vector((-1.78, 0.92, -0.96)), 0.10),
        (Vector((-0.44, 5.24,  0.34)), Vector((-1.76, 0.96,  0.72)), 0.12),
        (Vector(( 0.44, 5.24,  0.22)), Vector(( 1.66, 0.94,  0.84)), 0.18),
    ]
    shroud_curves = []
    for top_loc, bot_w, sag in shroud_specs:
        top_w = M_mast @ top_loc
        cbox(mb, bot_w, (0.20, 0.34, 0.20), 'timber', C_TIMBER_DARK, 0.0)
        pts_sh = []
        for si in range(7):
            u = si / 6.0
            p = bot_w.lerp(top_w, u)
            p.y -= sag * 4.0 * u * (1.0 - u)
            pts_sh.append(p)
        tube(mb, pts_sh, 0.032, 5, 'rope', C_ROPE, caps=(True, True), mode='flat')
        shroud_curves.append(pts_sh)

    for ri in range(8):
        u = 0.12 + ri * 0.108
        idx_f = u * 6.0
        i0 = min(5, int(idx_f))
        frac = idx_f - i0
        p_a = shroud_curves[0][i0].lerp(shroud_curves[0][i0 + 1], frac)
        p_b = shroud_curves[1][i0].lerp(shroud_curves[1][i0 + 1], frac)
        p_mid = (p_a + p_b) * 0.5 - Vector((0.0, 0.03, 0.0))
        tube(mb, [p_a, p_mid, p_b], 0.019, 4, 'rope', mul(C_ROPE, 0.90), caps=(True, True), mode='flat')

    M_yard_w = M_mast @ T(0.0, YARD_Y, YARD_Z) @ R('Y', YARD_YAW) @ R('Z', YARD_ROLL)
    sb_tip = M_yard_w @ Vector((1.72, -0.10, 0.0))
    tube(mb, [
        sb_tip,
        sb_tip + Vector(( 0.18, -0.78, -0.12)),
        sb_tip + Vector(( 0.06, -1.62, -0.24)),
        sb_tip + Vector(( 0.22, -2.35, -0.18)),
    ], 0.022, 4, 'rope', C_ROPE, caps=(True, True), mode='flat')

    # 7. Coastal Sea-Kelp Fronds ('foliage' + UV2 wind!) draping off the wet barnacle rock base
    for k_anc, k_len, k_w, k_dir, k_ph in (
        ((-1.62, 0.98, -0.92), 1.38, 0.18, (-0.78, 0.0, -0.62), 0.16),
        (( 1.56, 0.88,  0.94), 1.32, 0.17, ( 0.74, 0.0,  0.67), 0.44),
        ((-0.42, 1.18, -1.24), 1.24, 0.17, (-0.28, 0.0, -0.96), 0.78),
    ):
        _add_kelp_drape(mb, k_anc, k_len, k_w, k_dir, rng, phase=k_ph)

    # 8. Swinging Brass Cage Storm-Lantern suspended vertically off Port Yardarm ('Lantern_CrowNest'!)
    YARD_HOOK_W = M_yard_w @ Vector((-2.22, -0.14, 0.0))
    LANTERN_POS = YARD_HOOK_W + Vector((0.0, -0.88, 0.0))
    with xf(mb, T(YARD_HOOK_W) @ M_Y2Z):
        torus(mb, 0.062, 0.018, 6, 4, 'iron', C_IRON, False)
    for li in range(5):
        ly_l = YARD_HOOK_W.y - 0.08 - li * 0.095
        with xf(mb, T(YARD_HOOK_W.x, ly_l, YARD_HOOK_W.z) @ R('Y', 90.0 if li % 2 == 0 else 0.0) @ M_Y2Z):
            torus(mb, 0.052, 0.015, 6, 4, 'iron', C_IRON_RUST if li % 2 == 0 else C_IRON, False)
    _build_harbour_lantern(mb, LANTERN_POS, scale=1.08, brass_body=True)

    build(mb)

    add_empty('Lantern_CrowNest', LANTERN_POS)
    col_piece('col_mast_base',  col_base_pts)
    col_piece('col_mast_trunk', col_trunk_pts)
    export_landmark_glb(outdir, 'wooden_shipwreck_crow_nest_mast.glb')


FORT_VAULT_GENERATORS = [
    gen_stone_well_courtyard,
    gen_ruined_sea_fort_cannon_bastion,
    gen_pirate_treasure_vault_door,
    gen_wooden_shipwreck_crow_nest_mast,
]
