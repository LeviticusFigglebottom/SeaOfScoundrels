# Sea of Scoundrels: 4 sculpted 3D Harbour, Jungle & Smuggler landmarks (Wave 6-A).
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
    C_BASALT_TOP, C_BASALT_MID, C_BASALT_DARK,
    C_SKULL_BONE, C_SKULL_MID, C_SKULL_EYE,
    C_TEMPLE_HI, C_TEMPLE_MID, C_TEMPLE_DARK, C_TEMPLE_GOLD,
    C_TIMBER_HI, C_TIMBER_MID, C_TIMBER_DARK, C_DRIFTWOOD,
    C_PAINT_RED, C_PAINT_TEAL, C_PAINT_CREAM,
    C_ROPE, C_IRON, C_IRON_RUST, C_BRASS, C_LANTERN_GL,
    C_LEAF_DEEP, C_LEAF_SUN,
    T, R, S, M_Y2Z, M_Y2X, newell,
    MB, xf,
    cbox, sculpt_stone_block, loft, lathe, tube, cyl, torus,
    build_lantern_geom, sculpt_rock_mass,
    clear_scene, build, col_piece, col_box, add_empty, export_landmark_glb,
)


# ---------------------------------------------------------------- local palette & sculptural helpers

C_SAIL_CREAM   = srgb('#e8d9b4')
C_SAIL_WARM    = srgb('#cfae78')
C_GOLD_BRIGHT  = srgb('#f5c644')
C_GOLD_DEEP    = srgb('#ad781d')
C_WINE_STAVE   = srgb('#64321e')
C_WATER_DEEP   = srgb('#0f4d5c')
C_WATER_TURQ   = srgb('#1d8f9c')
C_WATER_FOAM   = srgb('#8ae0dc')
C_FERN_DARK    = srgb('#144a1c')
C_FERN_MID     = srgb('#2a7622')
C_FERN_TIP     = srgb('#78ba28')
C_VINE_DARK    = srgb('#13461a')
C_VINE_MID     = srgb('#276c20')
C_VINE_SUN     = srgb('#6eb224')
C_EMERALD_CORE = srgb('#38ffd8')


def _box2(mb, lo, hi, mat, col, ch=0.0, grain=None, skip=()):
    c = ((lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5, (lo[2] + hi[2]) * 0.5)
    sz = (hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2])
    cbox(mb, c, sz, mat, col, ch, grain, skip=skip)


def _add_beam(mb, p0, p1, w, h, mat, col, ch=0.0):
    """Emit a crisp timber or iron beam connecting arbitrary 3D points p0 and p1."""
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


def _rect_oct(cx, y, cz, hx, hz, ch=0.22):
    """Chamfered rectangular octagon ring at height y centered at (cx, y, cz)."""
    ch = min(ch, hx * 0.45, hz * 0.45)
    return [
        (cx - hx + ch, y, cz - hz),
        (cx + hx - ch, y, cz - hz),
        (cx + hx,      y, cz - hz + ch),
        (cx + hx,      y, cz + hz - ch),
        (cx + hx - ch, y, cz + hz),
        (cx - hx + ch, y, cz + hz),
        (cx - hx,      y, cz + hz - ch),
        (cx - hx,      y, cz - hz + ch),
    ]


def _loft_horizontal_masonry(mb, secs, mat, scols, rng, caps=(True, True), top_mat=None, top_col=None):
    """Emit a vertical stepped or battered ashlar masonry block with horizontal UV courses."""
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


def _add_chain_links(mb, p0, p1, n_links, link_r=0.048, wire_r=0.014,
                     segs=6, psegs=4, sag=0.0, mat='iron'):
    """Alternating 90-degree hammered forged chain links along a gentle catenary between p0 and p1."""
    a = Vector(p0)
    b = Vector(p1)
    if (b - a).length < 1e-5 or n_links < 1:
        return
    for k in range(n_links):
        t = (k + 0.5) / float(n_links)
        t0 = max(0.0, t - 0.05)
        t1 = min(1.0, t + 0.05)
        pt = a.lerp(b, t) + Vector((0.0, -sag * 4.0 * t * (1.0 - t), 0.0))
        q0 = a.lerp(b, t0) + Vector((0.0, -sag * 4.0 * t0 * (1.0 - t0), 0.0))
        q1 = a.lerp(b, t1) + Vector((0.0, -sag * 4.0 * t1 * (1.0 - t1), 0.0))
        tang = q1 - q0
        if tang.length < 1e-6:
            tang = Vector((0.0, -1.0, 0.0))
        rot_q = Vector((0.0, 1.0, 0.0)).rotation_difference(tang.normalized()).to_matrix().to_4x4()
        spin = R('Y', 90.0 if (k % 2 == 0) else 0.0)
        if mat == 'brass':
            col = C_BRASS if (k % 2 == 0) else C_TEMPLE_GOLD
        else:
            col = C_IRON_RUST if (k % 3 == 0) else C_IRON
        with xf(mb, T(pt) @ rot_q @ spin @ S(0.76, 1.18, 0.76) @ M_Y2Z):
            torus(mb, link_r, wire_r, segs, psegs, mat, col, False)


def _build_coopered_barrel(mb, M_bar, radius=0.33, height=0.88, rng=None,
                           mat_body='timber', col_a=C_TIMBER_MID, col_b=C_TIMBER_HI,
                           col_head=C_TIMBER_DARK, segs=6, spigot=False, stripe_col=None, n_hoops=4):
    """Chunky coopered pirate rum barrel, tall wine cask, or painted crimson powder keg."""
    hh = height * 0.5
    prof = [
        (0.0,           -hh),
        (radius * 0.80, -hh),
        (radius * 0.94, -hh * 0.62),
        (radius,         0.0),
        (radius * 0.94,  hh * 0.62),
        (radius * 0.80,  hh),
        (0.0,            hh),
    ]
    stave_cols = [
        jit(col_a if k % 2 == 0 else col_b, rng, 0.08, 0.02) if rng else col_a
        for k in range(segs)
    ]
    hoop_spec = (
        ((-hh * 0.72, radius * 0.93), (-hh * 0.22, radius * 1.015), (hh * 0.22, radius * 1.015), (hh * 0.72, radius * 0.93))
        if n_hoops >= 4 else
        ((-hh * 0.72, radius * 0.93), (hh * 0.72, radius * 0.93))
    )
    with xf(mb, M_bar):
        lathe(mb, prof, segs, mat_body, col_a, False, False,
              lambda i, k: col_head if i in (0, 5) else stave_cols[k])
        for hi_idx, (hy, hr) in enumerate(hoop_spec):
            cyl(mb, hr, hy - 0.026, hy + 0.026, segs, 'iron',
                C_IRON_RUST if hi_idx == 1 else C_IRON, False, 0.0)
        if stripe_col is not None:
            cyl(mb, radius * 1.010, -hh * 0.16, hh * 0.16, segs, 'paint', stripe_col, False, 0.0)
        if spigot:
            with xf(mb, T(0.0, -hh * 0.48, -radius * 0.90) @ M_Y2Z):
                cyl(mb, 0.028, -0.02, 0.14, 5, 'brass', C_BRASS, False, 0.0, 0.018)
            cbox(mb, (0.0, -hh * 0.48 + 0.048, -radius - 0.065), (0.085, 0.024, 0.024), 'brass', C_BRASS, 0.0)


def _build_strapped_crate(mb, M_crate, size=(0.86, 0.72, 0.78), rng=None, stripe_col=C_PAINT_RED):
    """Chunky oak harbour supply crate with perimeter cleats, iron corner straps & painted cargo stripe."""
    sx, sy, sz = size
    hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
    with xf(mb, M_crate):
        cbox(mb, (0.0, 0.0, 0.0), (sx, sy, sz), 'timber',
             jit(C_TIMBER_MID, rng, 0.05) if rng else C_TIMBER_MID, 0.0, (1, 0, 0))
        for y_s in (-hy + 0.045, hy - 0.045):
            for z_s in (-hz - 0.012, hz + 0.012):
                cbox(mb, (0.0, y_s, z_s), (sx + 0.06, 0.09, 0.055), 'timber', C_TIMBER_HI, 0.0, (1, 0, 0))
            for x_s in (-hx - 0.012, hx + 0.012):
                cbox(mb, (x_s, y_s, 0.0), (0.055, 0.09, sz + 0.02), 'timber', C_TIMBER_HI, 0.0, (0, 0, 1))
        for x_s in (-hx - 0.012, hx + 0.012):
            for z_s in (-hz - 0.012, hz + 0.012):
                cbox(mb, (x_s, 0.0, z_s), (0.065, sy - 0.14, 0.065), 'timber', C_TIMBER_DARK, 0.0, (0, 1, 0))
                for y_c in (-hy + 0.045, hy - 0.045):
                    cbox(mb, (x_s * 1.015, y_c, z_s * 1.015), (0.095, 0.11, 0.095), 'iron', C_IRON, 0.0)
        for z_s in (-hz - 0.015, hz + 0.015):
            _add_beam(mb, (-hx + 0.08, -hy + 0.09, z_s), (hx - 0.08, hy - 0.09, z_s),
                      0.075, 0.036, 'timber', C_TIMBER_HI, 0.0)
        if stripe_col is not None:
            for z_s in (-hz - 0.018, hz + 0.018):
                cbox(mb, (0.0, 0.0, z_s), (sx * 0.72, 0.14, 0.018), 'paint', stripe_col, 0.0)
            for x_s in (-hx - 0.018, hx + 0.018):
                cbox(mb, (x_s, 0.0, 0.0), (0.018, 0.14, sz * 0.72), 'paint', stripe_col, 0.0)


def _add_sun_compass_relief(mb, M_med, rng, scale=1.0, flat_horiz=False):
    """Carved tarnished antique-gold sun-compass sunburst relief ('brass') for altar slabs & shrine keystones."""
    s = scale
    with xf(mb, M_med):
        if flat_horiz:
            torus(mb, 0.56 * s, 0.055 * s, 10, 4, 'brass', C_TEMPLE_GOLD, False)
            cyl(mb, 0.50 * s, -0.02 * s, 0.028 * s, 10, 'temple_stone', C_TEMPLE_DARK, False, 0.0)
            for k in range(8):
                is_card = (k % 2 == 0)
                r_len = (0.52 if is_card else 0.38) * s
                r_w = (0.085 if is_card else 0.058) * s
                col_r = C_GOLD_BRIGHT if is_card else C_BRASS
                with xf(mb, R('Y', k * 45.0)):
                    p_in = Vector((0.0, 0.032 * s, 0.06 * s))
                    p_l  = Vector((-r_w, 0.032 * s, r_len * 0.36))
                    p_t  = Vector((0.0, 0.030 * s, r_len))
                    p_r  = Vector(( r_w, 0.032 * s, r_len * 0.36))
                    apex = Vector((0.0, 0.088 * s, r_len * 0.36))
                    in_ref = Vector((0.0, -0.25 * s, r_len * 0.36))
                    mb.fp([p_in, p_l, p_t, apex], 'brass', jit(col_r, rng, 0.04), (0, 0, 1), in_ref, smooth=False)
                    mb.fp([p_t, p_r, p_in, apex], 'brass', jit(mul(col_r, 0.90), rng, 0.04), (0, 0, 1), in_ref, smooth=False)
            cyl(mb, 0.16 * s, 0.02 * s, 0.095 * s, 8, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.08 * s)
        else:
            with xf(mb, M_Y2Z):
                cyl(mb, 0.64 * s, -0.065 * s, 0.14 * s, 8, 'temple_stone', C_TEMPLE_DARK, False, 0.0)
            with xf(mb, T(0.0, 0.0, -0.065 * s) @ M_Y2Z):
                torus(mb, 0.52 * s, 0.058 * s, 8, 4, 'brass', C_TEMPLE_GOLD, False)
            for k in range(8):
                is_card = (k % 2 == 0)
                r_len = (0.60 if is_card else 0.43) * s
                r_w = (0.092 if is_card else 0.062) * s
                col_r = C_GOLD_BRIGHT if is_card else C_BRASS
                with xf(mb, R('Z', k * 45.0)):
                    p_in = Vector((0.0, 0.06 * s, -0.072 * s))
                    p_l  = Vector((-r_w, r_len * 0.35, -0.070 * s))
                    p_t  = Vector((0.0, r_len, -0.068 * s))
                    p_r  = Vector(( r_w, r_len * 0.35, -0.070 * s))
                    apex = Vector((0.0, r_len * 0.35, -0.138 * s))
                    in_ref = Vector((0.0, r_len * 0.35, 0.25 * s))
                    mb.fp([p_in, p_l, p_t, apex], 'brass', jit(col_r, rng, 0.04), (0, 1, 0), in_ref, smooth=False)
                    mb.fp([p_t, p_r, p_in, apex], 'brass', jit(mul(col_r, 0.90), rng, 0.04), (0, 1, 0), in_ref, smooth=False)
            with xf(mb, T(0.0, 0.0, -0.075 * s) @ M_Y2Z):
                cyl(mb, 0.18 * s, -0.03 * s, 0.09 * s, 6, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.09 * s)


def _add_trapezoid_voussoir(mb, center_xy, ang0, ang1, r_in, r_out, half_z, mat, col, rng, z_ctr=0.0):
    """Crisp 6-face chiseled radial stone arch voussoir wedge."""
    cx, cy = center_xy
    pad = 0.015
    a0 = ang0 - pad
    a1 = ang1 + pad
    m_pts2 = [
        (cx + cos(a0) * r_in,  cy + sin(a0) * r_in),
        (cx + cos(a1) * r_in,  cy + sin(a1) * r_in),
        (cx + cos(a1) * r_out, cy + sin(a1) * r_out),
        (cx + cos(a0) * r_out, cy + sin(a0) * r_out),
    ]
    am = 0.5 * (ang0 + ang1)
    rm = 0.5 * (r_in + r_out)
    ctr = Vector((cx + cos(am) * rm, cy + sin(am) * rm, z_ctr))
    tang_grain = Vector((-sin(am), cos(am), 0.0))

    r_f = [Vector((x, y, z_ctr - half_z)) for x, y in m_pts2]
    r_b = [Vector((x, y, z_ctr + half_z)) for x, y in m_pts2]

    mb.newoff()
    c_main = jit(col, rng, 0.045, 0.015)
    mb.fp(r_f, mat, c_main, tang_grain, ctr, smooth=False)
    mb.fp(list(reversed(r_b)), mat, c_main, tang_grain, ctr, smooth=False)
    for k in range(4):
        kn = (k + 1) % 4
        q = [r_f[k], r_f[kn], r_b[kn], r_b[k]]
        qc = mul(c_main, 0.72) if k == 0 else (mul(c_main, 1.06) if k == 2 else mul(c_main, 0.90))
        mb.fp(q, mat, qc, tang_grain, ctr, smooth=False)


def _add_leafy_vine_drape(mb, anchor, length, width, out_dir, rng, phase=0.0):
    """Sculpted organic hanging jungle ivy/moss vine ('foliage') with slender winding runner stem,
    staggered diamond-lobed tropical leaves jutting out at varied angles, and UV2 wind weights!
    """
    a = Vector(anchor)
    od = Vector((out_dir[0], 0.0, out_dir[2]))
    if od.length < 1e-4:
        od = Vector((0.0, 0.0, -1.0))
    od.normalize()
    side = Vector((-od.z, 0.0, od.x))

    # Slender sinuous central hanging vine stem (4 segments, tapered to a fine trailing tip!)
    segs = 5
    stem_pts = []
    for i in range(segs + 1):
        t = i / float(segs)
        sway = sin(t * 3.4 + phase * 6.28) * 0.16 * (0.2 + 0.8 * t)
        out_off = 0.08 + 0.16 * sin(t * pi * 0.75) + 0.08 * t
        stem_pts.append(a + od * out_off + side * sway + Vector((0.0, -length * t, 0.0)))

    for i in range(segs):
        t0 = i / float(segs)
        t1 = (i + 1) / float(segs)
        w0 = width * 0.22 * (1.0 - 0.55 * t0)
        w1 = width * 0.22 * (1.0 - 0.75 * t1)
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

    # Staggered sculpted angular jungle vine leaves sprouting organically along both flanks!
    n_leaves = max(5, int(length * 2.1))
    for li in range(n_leaves):
        t = (li + 0.35) / float(n_leaves + 0.25)
        idx_f = t * segs
        i0 = min(segs - 1, int(idx_f))
        frac = idx_f - i0
        root = stem_pts[i0].lerp(stem_pts[i0 + 1], frac)
        sgn = -1.0 if (li % 2 == 0) else 1.0
        l_scale = (0.72 + 0.55 * sin(t * pi * 0.85)) * (1.0 - 0.35 * t)
        l_len = width * 1.48 * l_scale * rng.uniform(0.85, 1.18)
        l_wid = width * 0.62 * l_scale * rng.uniform(0.85, 1.15)
        # Leaf angles outward and gracefully downward for lush overlapping tropical silhouette!
        l_dir = (side * (sgn * 0.68) + od * (0.48 + rng.uniform(-0.12, 0.16)) + Vector((0.0, -0.76, 0.0))).normalized()
        l_perp = l_dir.cross(od)
        if l_perp.length < 1e-4:
            l_perp = side
        else:
            l_perp.normalize()
        p_base = root
        p_mid_l = root + l_dir * (l_len * 0.42) - l_perp * l_wid + od * 0.04
        p_mid_r = root + l_dir * (l_len * 0.42) + l_perp * l_wid + od * 0.04
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


def _add_jungle_fern_cluster(mb, root_pos, scale=1.0, n_fronds=6, rng=None, phase=0.0, lean_dir=None):
    """Lush broad tropical jungle fern rosette ('foliage') with proper UV2 wind weights (0 root -> 0.92 tip)."""
    rp = Vector(root_pos)
    segs = 4
    base_rot = rng.uniform(0.0, 2.0 * pi) if rng else 0.0
    for fi in range(n_fronds):
        ang = base_rot + 2.0 * pi * fi / float(n_fronds) + (rng.uniform(-0.22, 0.22) if rng else 0.0)
        f_len = scale * (rng.uniform(0.86, 1.18) if rng else 1.0)
        f_w = scale * (rng.uniform(0.24, 0.34) if rng else 0.28)
        f_arch_h = scale * (rng.uniform(0.46, 0.68) if rng else 0.56)
        f_droop = scale * (rng.uniform(0.24, 0.42) if rng else 0.32)
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


def _build_pulley_block(mb, center, radius=0.22, yaw_deg=0.0, has_hook=False):
    """Chunky iron-strapped wooden harbour pulley sheave block with brass wheel & optional forged hook."""
    with xf(mb, T(center) @ R('Y', yaw_deg)):
        for sx in (-0.095, 0.095):
            cbox(mb, (sx, 0.0, 0.0), (0.065, radius * 2.55, radius * 2.05), 'timber', C_TIMBER_MID, 0.0)
        cbox(mb, (0.0,  radius * 1.32, 0.0), (0.28, 0.055, 0.14), 'iron', C_IRON, 0.0)
        cbox(mb, (0.0, -radius * 1.32, 0.0), (0.28, 0.055, 0.14), 'iron', C_IRON, 0.0)
        with xf(mb, M_Y2X):
            cyl(mb, radius * 0.92, -0.055, 0.055, 6, 'brass', C_BRASS, False, 0.0)
            cyl(mb, 0.042, -0.16, 0.16, 5, 'iron', C_IRON, False, 0.0)
        with xf(mb, T(0.0, radius * 1.56, 0.0) @ M_Y2Z):
            torus(mb, 0.082, 0.022, 6, 4, 'iron', C_IRON, False)
        if has_hook:
            hook_path = [
                (0.0, -radius * 1.35, 0.0),
                (0.0, -radius * 1.90, 0.0),
                (0.0, -radius * 2.38, -0.14),
                (0.0, -radius * 2.50,  0.04),
                (0.0, -radius * 2.15,  0.22),
            ]
            tube(mb, hook_path, [0.042, 0.048, 0.050, 0.042, 0.022], 4, 'iron', C_IRON, mode='flat')


def _build_treasure_chest(mb, M_chest, open_deg=0.0, rng=None, spill_gold=False):
    """Ornate iron-banded oak pirate treasure chest with vaulted lid, brass lock & optional spilling gold."""
    w, h, d = 1.12, 0.56, 0.68
    hw, hh, hd = w * 0.5, h * 0.5, d * 0.5
    with xf(mb, M_chest):
        if open_deg > 2.0:
            cbox(mb, (0.0, 0.07, 0.0), (w - 0.04, 0.14, d - 0.04), 'timber', C_TIMBER_DARK, 0.0)
            cbox(mb, (0.0, hh, -hd + 0.045), (w, h, 0.09), 'timber', C_TIMBER_MID, 0.0, (1, 0, 0))
            cbox(mb, (0.0, hh,  hd - 0.045), (w, h, 0.09), 'timber', C_TIMBER_MID, 0.0, (1, 0, 0))
            cbox(mb, (-hw + 0.045, hh, 0.0), (0.09, h, d - 0.16), 'timber', C_TIMBER_MID, 0.0, (0, 0, 1))
            cbox(mb, ( hw - 0.045, hh, 0.0), (0.09, h, d - 0.16), 'timber', C_TIMBER_MID, 0.0, (0, 0, 1))
        else:
            cbox(mb, (0.0, hh, 0.0), (w, h, d), 'timber', C_TIMBER_MID, 0.0, (1, 0, 0))

        # Forged-iron vertical straps & perimeter corner trim
        for xs in (-hw + 0.04, 0.0, hw - 0.04):
            cbox(mb, (xs, hh, -hd - 0.014), (0.082, h + 0.02, 0.032), 'iron', C_IRON, 0.0)
            cbox(mb, (xs, hh,  hd + 0.014), (0.082, h + 0.02, 0.032), 'iron', C_IRON, 0.0)
        for xs in (-hw - 0.014, hw + 0.014):
            cbox(mb, (xs, h - 0.05, 0.0), (0.032, 0.085, d + 0.04), 'iron', C_IRON, 0.0)
            cbox(mb, (xs * 1.03, hh + 0.04, 0.0), (0.045, 0.14, 0.16), 'brass', C_BRASS, 0.0)
        cbox(mb, (0.0, 0.06, -hd - 0.014), (w + 0.04, 0.085, 0.032), 'iron', C_IRON_RUST, 0.0)
        cbox(mb, (0.0, h - 0.04, -hd - 0.014), (w + 0.04, 0.080, 0.032), 'iron', C_IRON, 0.0)

        # Ornate gilded brass front lockplate
        cbox(mb, (0.0, h - 0.14, -hd - 0.032), (0.20, 0.22, 0.032), 'brass', C_GOLD_BRIGHT, 0.0)
        cbox(mb, (0.0, h - 0.16, -hd - 0.050), (0.05, 0.08, 0.018), 'iron', C_IRON, 0.0)

        # Curved barrel-vault oak chest lid pivoting around rear hinge (y=h, z=+hd)
        lid_M = T(0.0, h, hd) @ R('X', open_deg) @ T(0.0, 0.0, -hd)
        with xf(mb, lid_M):
            r_lid = hd * 1.02
            lid_ring = [(cos(pi * k / 4.0) * r_lid, sin(pi * k / 4.0) * 0.28) for k in range(5)]
            secs = [
                [Vector((-hw - 0.02, py, -pz)) for pz, py in lid_ring] + [Vector((-hw - 0.02, 0.0, -hd))],
                [Vector(( hw + 0.02, py, -pz)) for pz, py in lid_ring] + [Vector(( hw + 0.02, 0.0, -hd))],
            ]
            loft(mb, secs, 'timber', C_TIMBER_HI, closed=True, caps=(True, True), mode='flat')
            for xs in (-hw + 0.04, 0.0, hw - 0.04):
                rib_pts = [Vector((xs, sin(pi * k / 4.0) * 0.305, -cos(pi * k / 4.0) * (r_lid + 0.022)))
                           for k in range(5)]
                tube(mb, rib_pts, 0.036, 4, 'iron', C_IRON, mode='flat')
            cbox(mb, (0.0, 0.04, -hd - 0.035), (0.11, 0.14, 0.028), 'brass', C_BRASS, 0.0)

        if spill_gold:
            # Chunky faceted gleaming gold coin heap inside the ajar chest mouth
            bm = bmesh.new()
            bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
            for v in bm.verts:
                p = v.co.copy()
                bump = 1.0 + 0.14 * sin(p.x * 7.0 + p.z * 6.0)
                py = max(-0.16, p.y) * 0.24 * bump
                v.co = Vector((p.x * (hw - 0.07) * bump, h - 0.03 + py, p.z * (hd - 0.07) * bump))
            bm.faces.ensure_lookup_table()
            mb.newoff()
            ctr_g = Vector((0.0, h - 0.12, 0.0))
            for f in bm.faces:
                pts = [v.co.copy() for v in f.verts]
                gc = jit(C_GOLD_BRIGHT if (rng and rng.random() > 0.32) else C_BRASS, rng, 0.06) if rng else C_GOLD_BRIGHT
                mb.fp(pts, 'brass', gc, (1, 0, 0), ctr_g, smooth=False)
            bm.free()

            # Spilled gold coin mounds & gleaming chalices resting on the deck directly in front (-Z)!
            for cx, cy, cz, cr, ch_c in (
                (-0.22, 0.035, -hd - 0.18, 0.17, 0.068),
                ( 0.08, 0.032, -hd - 0.25, 0.20, 0.062),
                ( 0.30, 0.028, -hd - 0.14, 0.14, 0.052),
                (-0.04, 0.024, -hd - 0.43, 0.13, 0.044),
            ):
                with xf(mb, T(cx, cy, cz)):
                    cyl(mb, cr, -0.02, ch_c, 6, 'brass',
                        jit(C_GOLD_BRIGHT, rng, 0.05) if rng else C_GOLD_BRIGHT, False, 0.0, cr * 0.65)
            # Tipped golden pirate chalice spilling beside the coin heap
            with xf(mb, T(-0.34, 0.085, -hd - 0.30) @ R('Y', 32.0) @ R('Z', 74.0)):
                ch_prof = [
                    (0.0, -0.11), (0.078, -0.11), (0.025, -0.05), (0.028, 0.02),
                    (0.095, 0.10), (0.100, 0.16), (0.072, 0.16), (0.0, 0.07),
                ]
                lathe(mb, ch_prof, 6, 'brass', C_GOLD_BRIGHT, False)
            # Upright golden goblet perched atop the coin mound inside the cracked chest!
            with xf(mb, T(0.20, h + 0.14, -0.04) @ R('Z', -16.0)):
                ch_prof2 = [
                    (0.0, -0.09), (0.068, -0.09), (0.022, -0.03), (0.026, 0.02),
                    (0.086, 0.10), (0.090, 0.15), (0.0, 0.08),
                ]
                lathe(mb, ch_prof2, 6, 'brass', C_GOLD_BRIGHT, False)


def _build_gold_chalice(mb, M_ch, scale=1.0):
    """Lathe-turned antique golden ritual goblet/chalice ('brass')."""
    s = scale
    prof = [
        (0.0,       0.0),
        (0.11 * s,  0.0),
        (0.035 * s, 0.07 * s),
        (0.032 * s, 0.18 * s),
        (0.138 * s, 0.31 * s),
        (0.146 * s, 0.42 * s),
        (0.112 * s, 0.42 * s),
        (0.0,       0.26 * s),
    ]
    with xf(mb, M_ch):
        lathe(mb, prof, 6, 'brass', C_GOLD_BRIGHT, False)


# ================================================================ 1. HARBOUR CARGO CRANE DOCK

def gen_harbour_cargo_crane_dock(outdir):
    """Iconic Sea-of-Thieves-grade ~11.4 m tall harbour cargo crane & stepped stone-and-timber quay pier
    facing seaward (-Z).
    Heavy stepped stone-and-timber pier footing sinking solidly to y = -3.60 m (anti-float!),
    corner mooring pilings & oak plank deck, tall weathered timber swivel mast (~11.2 m) with forged
    iron tension bands & 4 heavy diagonal knee braces, long angled timber jib boom cantilevered ~5.5 m
    seaward with truss tie rods, geared iron winch drum + toothed bull-gear + spoked hand-crank wheel,
    iron-strapped oak pulley blocks & taut rope hoist line suspending a rope cargo sling cradling
    2 iron-banded rum barrels & 1 crimson-striped strapped supply crate clear beneath the jib tip,
    and a hanging brass harbour lantern on a forged-iron bracket near the mast head ('Lantern_Crane').
    Target: 2,800-4,200 visual tris, 2 colliders (col_crane_base, col_crane_post).
    """
    clear_scene()
    rng = random.Random(SEED + 1111)
    mb = MB('HarbourCargoCraneDock', seed=1111)

    PIER_BOT = -3.60
    DECK_Y = 1.12
    MAST_Z = 0.42
    MAST_TOP_Y = 11.25
    JIB_ROOT = Vector((0.0, 4.35, MAST_Z - 0.18))
    JIB_TIP = Vector((0.0, 10.65, -5.45))

    base_col_pts = []
    post_col_pts = []

    # 1. Heavy Stepped Stone-and-Timber Harbour Pier Footing plunging cleanly to y = -3.60 m!
    pier_secs = [
        _rect_oct(0.0, PIER_BOT, 0.10, 2.95, 2.85, 0.42),
        _rect_oct(0.0, -1.65,    0.10, 2.68, 2.58, 0.38),
        _rect_oct(0.0, -0.15,    0.10, 2.42, 2.34, 0.34),
        _rect_oct(0.0,  0.62,    0.10, 2.28, 2.20, 0.30),
        _rect_oct(0.0,  0.86,    0.10, 2.36, 2.28, 0.30),
    ]
    pier_cols = [
        mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.64),
        mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.46),
        mix(C_TEMPLE_MID,  C_SEA_MOSS, 0.24),
        C_TEMPLE_MID,
        C_TEMPLE_HI,
    ]
    _loft_horizontal_masonry(mb, pier_secs, 'temple_stone', pier_cols, rng, caps=(True, True))
    for ring in pier_secs:
        base_col_pts.extend(Vector(p) for p in ring)

    # Four Heavy Corner Timber Fender Pilings driven cleanly to y = -3.60 m with iron collars & mooring rope!
    piling_coords = [
        (-2.22, -2.08, 1.98, True),
        ( 2.22, -2.08, 1.92, True),
        (-2.22,  2.28, 1.56, False),
        ( 2.22,  2.28, 1.62, False),
    ]
    for px, pz, py_top, has_rope in piling_coords:
        tube(mb, [(px * 1.04, PIER_BOT, pz * 1.04), (px * 1.01, -0.4, pz * 1.01), (px, py_top, pz)],
             [0.24, 0.21, 0.19], 6, 'timber', C_TIMBER_DARK, mode='flat',
             scols=[mix(C_TIMBER_DARK, C_SEA_MOSS, 0.40), C_TIMBER_DARK, C_DRIFTWOOD])
        with xf(mb, T(px, py_top - 0.14, pz)):
            cyl(mb, 0.215, -0.055, 0.055, 6, 'iron', C_IRON, False, 0.0)
        if has_rope:
            for ri in range(2):
                with xf(mb, T(px, DECK_Y + 0.18 + ri * 0.095, pz)):
                    torus(mb, 0.228, 0.038, 6, 4, 'rope', mul(C_ROPE, 0.90 + 0.10 * ri), True)
        base_col_pts.extend([Vector((px, PIER_BOT, pz)), Vector((px, py_top, pz))])

    # Horizontal Dark-Oak Fender Bumper Wales bolted across seaward & flank pier faces
    for wy in (-0.35, 0.45):
        _box2(mb, (-2.38, wy - 0.11, -2.38), (2.38, wy + 0.11, -2.14), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
        for sx in (-2.38, 2.38):
            _box2(mb, (sx - 0.12, wy - 0.11, -2.26), (sx + 0.12, wy + 0.11, 2.40),
                  'timber', C_TIMBER_DARK, 0.0, (0, 0, 1))

    # Heavy Timber Pier Stringers & 10 Individual Weathered Oak Deck Planks (y = 0.86 .. 1.12 m)
    for sx in (-1.92, -0.68, 0.68, 1.92):
        _box2(mb, (sx - 0.12, 0.84, -2.28), (sx + 0.12, 1.02, 2.42), 'timber', C_TIMBER_DARK, 0.0, (0, 0, 1))
    n_planks = 10
    plank_palette = (C_TIMBER_HI, C_TIMBER_MID, C_DRIFTWOOD, C_TIMBER_MID)
    for pi_i in range(n_planks):
        pz = -2.10 + pi_i * 0.475
        pw = 4.78 + rng.uniform(-0.08, 0.08)
        cbox(mb, (rng.uniform(-0.03, 0.03), DECK_Y - 0.05 + rng.uniform(-0.006, 0.006), pz),
             (pw, 0.105, 0.435), 'timber', jit(plank_palette[pi_i % 4], rng, 0.075, 0.02),
             0.0, (1, 0, 0), M=R('Y', rng.uniform(-0.9, 0.9)))
    base_col_pts.extend([Vector((-2.42, DECK_Y + 0.05, -2.35)), Vector((2.42, DECK_Y + 0.05, 2.45))])

    # Raised Octagonal Stone & Forged-Iron Swivel Turntable Pedestal at Mast Foot (y = 1.10 .. 1.85 m)
    with xf(mb, T(0.0, DECK_Y, MAST_Z)):
        cyl(mb, 1.06, -0.04, 0.32, 8, 'temple_stone', C_TEMPLE_DARK, False, 0.0, 0.96)
        cyl(mb, 0.98,  0.30, 0.44, 8, 'iron', C_IRON_RUST, False, 0.0, 0.92)
        cyl(mb, 0.72,  0.42, 0.68, 6, 'iron', C_IRON, False, 0.0, 0.64)
        for k in range(6):
            ang = 2.0 * pi * k / 6.0
            cbox(mb, (cos(ang) * 0.82, 0.46, sin(ang) * 0.82), (0.11, 0.10, 0.11), 'brass', C_BRASS, 0.0)

    # 2. Tall Weathered Timber Swivel Mast (~11.25 m tall!) + Iron Tension Bands + 4 Diagonal Knee Braces!
    mast_path = [
        (0.0, 1.00,       MAST_Z),
        (0.0, 4.35,       MAST_Z),
        (0.0, 7.80,       MAST_Z),
        (0.0, MAST_TOP_Y, MAST_Z),
    ]
    mast_rads = [0.43, 0.38, 0.33, 0.27]
    tube(mb, mast_path, mast_rads, 6, 'timber', C_TIMBER_MID, mode='flat',
         scols=[C_TIMBER_DARK, C_TIMBER_MID, C_TIMBER_HI, C_DRIFTWOOD])
    post_col_pts.extend([
        Vector((-0.55, 1.05, MAST_Z - 0.55)), Vector((0.55, 1.05, MAST_Z + 0.55)),
        Vector((-0.38, MAST_TOP_Y + 0.2, MAST_Z - 0.38)), Vector((0.38, MAST_TOP_Y + 0.2, MAST_Z + 0.38)),
    ])

    for bi, by in enumerate((2.15, 4.35, 6.40, 8.75, 10.75)):
        t_m = (by - 1.0) / (MAST_TOP_Y - 1.0)
        rm = 0.43 * (1.0 - t_m) + 0.27 * t_m
        with xf(mb, T(0.0, by, MAST_Z)):
            cyl(mb, rm + 0.036, -0.095, 0.095, 6, 'iron',
                C_IRON_RUST if bi % 2 == 1 else C_IRON, False, 0.0)
    with xf(mb, T(0.0, MAST_TOP_Y, MAST_Z)):
        cyl(mb, 0.32, -0.02, 0.16, 6, 'iron', C_IRON, False, 0.0, 0.26)
        cyl(mb, 0.16,  0.14, 0.34, 6, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.05)

    # Four Massive Diagonal Timber Knee Braces locking Mast to Pier Deck!
    for dx, dz in ((0.0, -1.0), (0.0, 1.0), (-1.0, 0.0), (1.0, 0.0)):
        p_foot = Vector((dx * 1.88, DECK_Y + 0.04, MAST_Z + dz * 1.72))
        p_mast = Vector((dx * 0.26, 4.10,          MAST_Z + dz * 0.26))
        _add_beam(mb, p_foot, p_mast, 0.24, 0.26, 'timber', jit(C_TIMBER_DARK, rng, 0.05), 0.0)
        cbox(mb, p_foot + Vector((0.0, 0.08, 0.0)), (0.38, 0.22, 0.38), 'iron', C_IRON, 0.0)
        post_col_pts.append(p_foot)

    # Rear Counterweight Timber Frame & Ballast Stone Box behind Mast (z = +1.05..+1.95 m)
    for sx in (-0.42, 0.42):
        _box2(mb, (sx - 0.09, 1.70, MAST_Z + 0.18), (sx + 0.09, 2.02, MAST_Z + 1.56), 'timber', C_TIMBER_DARK, 0.0, (0, 0, 1))
        _add_beam(mb, (sx, 1.86, MAST_Z + 1.48), (sx, 5.15, MAST_Z + 0.22), 0.15, 0.15, 'timber', C_TIMBER_MID, 0.0)
    cbox(mb, (0.0, 2.42, MAST_Z + 1.24), (1.12, 0.94, 0.78), 'temple_stone', C_TEMPLE_DARK, 0.0)
    cbox(mb, (0.0, 2.42, MAST_Z + 1.24), (1.18, 0.14, 0.84), 'iron', C_IRON, 0.0)

    # 3. Long Angled Timber Jib Boom + Upper Truss Tie Rods reaching Seaward (-Z)!
    jib_mid = JIB_ROOT.lerp(JIB_TIP, 0.52)
    tube(mb, [JIB_ROOT, jib_mid, JIB_TIP], [0.27, 0.23, 0.18], 6, 'timber', C_TIMBER_HI, mode='flat',
         scols=[C_TIMBER_DARK, C_TIMBER_MID, C_TIMBER_HI])
    for sx in (-0.28, 0.28):
        _add_beam(mb, (sx, 4.18, MAST_Z + 0.20), (sx, 5.45, MAST_Z - 1.15), 0.10, 0.30, 'timber', C_TIMBER_DARK, 0.0)
    for t_j in (0.14, 0.50, 0.96):
        jp = JIB_ROOT.lerp(JIB_TIP, t_j)
        cbox(mb, jp, (0.48 - 0.10 * t_j, 0.44 - 0.08 * t_j, 0.24), 'iron',
             C_IRON if t_j > 0.4 else C_IRON_RUST, 0.0)

    for sx in (-0.22, 0.22):
        _add_beam(mb, (sx, 10.88, MAST_Z - 0.15), (sx * 0.72, JIB_TIP.y + 0.12, JIB_TIP.z + 0.10),
                  0.068, 0.068, 'iron', C_IRON, 0.0)
        _add_beam(mb, (sx, 10.65, MAST_Z - 0.18), (sx * 0.85, jib_mid.y + 0.12, jib_mid.z),
                  0.048, 0.048, 'iron', C_IRON_RUST, 0.0)
    _add_beam(mb, (0.0, 7.65, MAST_Z - 0.20), (0.0, jib_mid.y + 0.05, jib_mid.z),
              0.19, 0.21, 'timber', C_TIMBER_MID, 0.0)

    # 4. Iron Geared Winch Drum + Toothed Bull-Gear + Spoked Hand Crank Wheel on Mast Front!
    winch_y = 2.68
    winch_z = MAST_Z - 0.74
    for sx in (-0.54, 0.54):
        cbox(mb, (sx, winch_y, MAST_Z - 0.42), (0.09, 0.68, 0.92), 'iron', C_IRON, 0.0)
    with xf(mb, T(0.0, winch_y, winch_z) @ M_Y2X):
        cyl(mb, 0.11, -0.66, 0.66, 6, 'iron', C_IRON, False, 0.0)
        cyl(mb, 0.24, -0.44, 0.44, 6, 'rope', C_ROPE, False, 0.0)
        for rx_w in (-0.30, -0.10, 0.10, 0.30):
            with xf(mb, T(0.0, rx_w, 0.0)):
                torus(mb, 0.242, 0.036, 6, 4, 'rope', mul(C_ROPE, 0.90 + 0.10 * (rx_w > 0)), True)
        for sx_fl in (-0.46, 0.46):
            cyl(mb, 0.34, sx_fl - 0.035, sx_fl + 0.035, 6, 'iron', C_IRON, False, 0.0)

    # Large Toothed Cast-Iron Bull-Gear Cogwheel (starboard side x = +0.62) + Hand-Crank Wheel!
    gear_x = 0.62
    with xf(mb, T(gear_x, winch_y, winch_z)):
        with xf(mb, M_Y2X):
            torus(mb, 0.42, 0.048, 8, 4, 'iron', C_IRON, False)
            cyl(mb, 0.14, -0.055, 0.055, 6, 'brass', C_TEMPLE_GOLD, False, 0.0)
        for sk in range(4):
            ang = sk * pi * 0.5
            _add_beam(mb, (0.0, 0.0, 0.0), (0.0, cos(ang) * 0.40, sin(ang) * 0.40), 0.05, 0.055, 'iron', C_IRON, 0.0)
        for tk in range(8):
            ang = 2.0 * pi * tk / 8.0
            with xf(mb, T(0.0, cos(ang) * 0.475, sin(ang) * 0.475) @ R('X', degrees(ang))):
                cbox(mb, (0.0, 0.0, 0.0), (0.082, 0.095, 0.082), 'iron', C_IRON_RUST if tk % 2 == 0 else C_IRON, 0.0)

    pin_y = winch_y - 0.48
    pin_z = winch_z - 0.38
    with xf(mb, T(gear_x, pin_y, pin_z)):
        with xf(mb, M_Y2X):
            cyl(mb, 0.15, -0.06, 0.24, 6, 'iron', C_IRON, False, 0.0)
        with xf(mb, T(0.24, 0.0, 0.0)):
            with xf(mb, M_Y2X):
                torus(mb, 0.34, 0.034, 6, 4, 'iron', C_IRON, False)
            for sk in range(4):
                ang = sk * pi * 0.5 + pi * 0.25
                _add_beam(mb, (0.0, 0.0, 0.0), (0.0, cos(ang) * 0.32, sin(ang) * 0.32), 0.036, 0.036, 'iron', C_IRON, 0.0)
            with xf(mb, T(0.14, 0.28, -0.18) @ M_Y2X):
                cyl(mb, 0.038, -0.14, 0.16, 5, 'timber', C_TIMBER_HI, False, 0.0)
                cyl(mb, 0.044,  0.14, 0.18, 5, 'brass', C_BRASS, False, 0.0)

    # 5. Wooden Pulley Blocks & Taut 'rope' Hoist Line Running Winch -> Mast Head -> Jib Tip -> Hook!
    p_pulley_head = Vector((0.0, 10.18, MAST_Z - 0.42))
    p_pulley_tip  = Vector((0.0, 10.10, JIB_TIP.z + 0.05))
    p_hook_block  = Vector((0.0,  6.28, JIB_TIP.z + 0.05))

    _build_pulley_block(mb, p_pulley_head, radius=0.21, yaw_deg=0.0, has_hook=False)
    _build_pulley_block(mb, p_pulley_tip,  radius=0.22, yaw_deg=0.0, has_hook=False)
    _build_pulley_block(mb, p_hook_block,  radius=0.21, yaw_deg=0.0, has_hook=True)

    for r0, r1 in (
        ((0.0, winch_y + 0.22, winch_z - 0.08), (0.0, p_pulley_head.y, p_pulley_head.z - 0.12)),
        ((0.0, p_pulley_head.y + 0.12, p_pulley_head.z - 0.12), (0.0, p_pulley_tip.y + 0.12, p_pulley_tip.z)),
        ((0.0, p_pulley_tip.y - 0.10, p_pulley_tip.z - 0.10), (0.0, p_hook_block.y + 0.22, p_hook_block.z - 0.08)),
        ((0.0, p_pulley_tip.y - 0.10, p_pulley_tip.z + 0.10), (0.0, p_hook_block.y + 0.22, p_hook_block.z + 0.08)),
    ):
        tube(mb, [r0, r1], 0.030, 4, 'rope', C_ROPE, mode='smooth')

    # 6. Suspended Rope Cargo Sling Cradling 2 Banded Rum Barrels & 1 Strapped Supply Crate!
    sling_z = JIB_TIP.z + 0.05
    pallet_y = 3.62
    hook_eye = Vector((0.0, p_hook_block.y - 0.48, sling_z))

    for sx in (-0.72, 0.72):
        cbox(mb, (sx, pallet_y - 0.08, sling_z), (0.14, 0.12, 1.38), 'timber', C_TIMBER_DARK, 0.0, (0, 0, 1))
    for pi_p in range(5):
        pz_p = sling_z - 0.56 + pi_p * 0.28
        cbox(mb, (0.0, pallet_y + 0.02, pz_p), (1.92, 0.08, 0.24), 'timber',
             jit(C_TIMBER_HI if pi_p % 2 == 0 else C_TIMBER_MID, rng, 0.06), 0.0, (1, 0, 0))

    for sx_s in (-0.86, 0.86):
        for sz_s in (-0.60, 0.60):
            p_corn = Vector((sx_s, pallet_y + 0.04, sling_z + sz_s))
            tube(mb, [p_corn, hook_eye], 0.028, 4, 'rope', jit(C_ROPE, rng, 0.04), mode='smooth')
    belly_pts = [
        Vector((-0.90, pallet_y + 0.46, sling_z - 0.56)),
        Vector(( 0.90, pallet_y + 0.46, sling_z - 0.56)),
        Vector(( 0.90, pallet_y + 0.46, sling_z + 0.56)),
        Vector((-0.90, pallet_y + 0.46, sling_z + 0.56)),
        Vector((-0.90, pallet_y + 0.46, sling_z - 0.56)),
    ]
    tube(mb, belly_pts, 0.026, 4, 'rope', C_ROPE, mode='smooth')

    _build_strapped_crate(
        mb, T(-0.42, pallet_y + 0.40, sling_z + 0.04) @ R('Y', 6.0),
        size=(0.86, 0.72, 0.78), rng=rng, stripe_col=C_PAINT_RED,
    )
    _build_coopered_barrel(
        mb, T(0.46, pallet_y + 0.48, sling_z - 0.22) @ R('Y', -14.0),
        radius=0.31, height=0.88, rng=rng, segs=6, col_a=C_TIMBER_MID, col_b=C_TIMBER_HI,
    )
    _build_coopered_barrel(
        mb, T(0.44, pallet_y + 0.46, sling_z + 0.32) @ R('Y', 22.0) @ R('Z', -4.0),
        radius=0.30, height=0.84, rng=rng, segs=6, col_a=C_WINE_STAVE, col_b=C_TIMBER_MID,
    )

    # 7. Hanging Brass Harbour Lantern on Forged-Iron Bracket near Mast Head + 'Lantern_Crane' Empty!
    br_y = 8.95
    with xf(mb, T(0.0, br_y, MAST_Z)):
        cbox(mb, (0.34, 0.0, -0.10), (0.08, 0.54, 0.14), 'iron', C_IRON, 0.0)
        tube(mb, [
            (0.34, 0.16, -0.08),
            (0.88, 0.28, -0.22),
            (1.36, 0.26, -0.34),
            (1.42, 0.12, -0.36),
        ], [0.034, 0.030, 0.026, 0.020], 4, 'iron', C_IRON, mode='flat')
        tube(mb, [
            (0.34, -0.34, -0.08),
            (0.82, -0.04, -0.20),
            (1.24,  0.24, -0.31),
        ], 0.024, 4, 'iron', C_IRON_RUST, mode='flat')

    l_hook = Vector((1.42, br_y + 0.10, MAST_Z - 0.36))
    l_scale = 1.38
    lantern_pos = (l_hook.x, l_hook.y - 0.72, l_hook.z)
    _add_chain_links(
        mb,
        l_hook,
        Vector((lantern_pos[0], lantern_pos[1] + 0.31 * l_scale, lantern_pos[2])),
        n_links=3, link_r=0.042, wire_r=0.013,
    )
    build_lantern_geom(mb, lantern_pos, scale=l_scale, hanging=True)

    # Compact 2-turn dockside coiled mooring rope & iron tie cleat on pier deck
    for ci in range(2):
        with xf(mb, T(-1.52, DECK_Y + 0.036 + ci * 0.056, -1.42)):
            torus(mb, 0.28 - ci * 0.045, 0.034, 6, 4, 'rope', mul(C_ROPE, 0.90 + 0.10 * ci), True)
    cbox(mb, (1.58, DECK_Y + 0.08, -1.62), (0.48, 0.10, 0.14), 'iron', C_IRON, 0.0)
    cbox(mb, (1.58, DECK_Y + 0.16, -1.62), (0.64, 0.07, 0.10), 'iron', C_IRON_RUST, 0.0)

    build(mb)

    add_empty('Lantern_Crane', lantern_pos)
    col_piece('col_crane_base', base_col_pts)
    col_piece('col_crane_post', post_col_pts)
    export_landmark_glb(outdir, 'harbour_cargo_crane_dock.glb')


# ================================================================ 2. OVERGROWN JUNGLE IDOL ALTAR

def gen_overgrown_jungle_idol_altar(outdir):
    """Monumental overgrown ancient jungle idol offering plaza (~9.2 m wide x ~8.2 m deep, ~6.8 m tall,
    stepped plinth skirt sinking cleanly to y = -3.80 m anti-float!).
    3-tiered mossy carved temple-stone offering plaza with deep-grounded front steps & carved newels,
    central weathered stone altar slab inlaid with raised golden ('brass') compass-sun & coiled
    sea-serpent relief + ritual chalices & miniature golden idol statuette, flanking pair of
    half-crumbled carved stone monolith pillars topped by glowing emerald-turquoise ('skull_glow')
    ritual fire bowls + centered 'Lantern_Altar' Empty, ruined staggered rear relic wall, and
    cascading sculpted 'foliage' leafy jungle vines & broad fern clusters with UV2 wind weights!
    Target: 3,000-4,400 visual tris, 2 colliders (col_altar_plinth, col_altar_pillars).
    """
    clear_scene()
    rng = random.Random(SEED + 1141)
    mb = MB('OvergrownJungleIdolAltar', seed=1141)

    SKIRT_BOT = -3.80
    T1_TOP = 0.78
    T2_TOP = 1.54
    T3_TOP = 2.22

    plinth_col_pts = []
    pillar_col_pts = []

    # 1. Broad 3-Tiered Mossy Carved Temple-Stone Offering Plaza (9.2 m x 8.2 m, skirt to y = -3.80 m!)
    t1_secs = [
        _rect_oct(0.0, SKIRT_BOT, 0.0, 5.25, 4.75, 0.72),
        _rect_oct(0.0, -1.65,     0.0, 4.88, 4.38, 0.66),
        _rect_oct(0.0,  0.00,     0.0, 4.62, 4.12, 0.62),
        _rect_oct(0.0,  T1_TOP,   0.0, 4.52, 4.02, 0.60),
    ]
    t1_cols = [
        mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.62),
        mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.46),
        mix(C_TEMPLE_MID,  C_LEDGE_MOSS, 0.28),
        C_TEMPLE_MID,
    ]
    _loft_horizontal_masonry(
        mb, t1_secs, 'temple_stone', t1_cols, rng, caps=(True, True),
        top_mat='limestone_moss', top_col=mix(C_TEMPLE_MID, C_LEDGE_MOSS, 0.48),
    )
    for ring in t1_secs:
        plinth_col_pts.extend(Vector(p) for p in ring)

    # Tier 2 Offering Terrace (7.2 m x 6.4 m)
    t2_secs = [
        _rect_oct(0.0, T1_TOP - 0.12, 0.12, 3.68, 3.26, 0.52),
        _rect_oct(0.0, T2_TOP,        0.12, 3.55, 3.14, 0.50),
    ]
    _loft_horizontal_masonry(
        mb, t2_secs, 'temple_stone', [C_TEMPLE_DARK, C_TEMPLE_MID], rng, caps=(False, True),
        top_mat='limestone_moss', top_col=mix(C_TEMPLE_HI, C_LEDGE_MOSS, 0.36),
    )

    # Tier 3 Inner Sanctum Dais (4.9 m x 4.2 m)
    t3_secs = [
        _rect_oct(0.0, T2_TOP - 0.10, 0.22, 2.52, 2.16, 0.42),
        _rect_oct(0.0, T3_TOP,        0.22, 2.42, 2.06, 0.40),
    ]
    _loft_horizontal_masonry(
        mb, t3_secs, 'temple_stone', [C_TEMPLE_MID, C_TEMPLE_HI], rng, caps=(False, True),
        top_mat='temple_stone', top_col=C_TEMPLE_HI,
    )
    plinth_col_pts.extend([Vector((-2.52, T3_TOP, -1.94)), Vector((2.52, T3_TOP, 2.38))])

    # Inlaid tarnished gold brass ceremonial compass strips set into the Tier 3 dais floor
    cbox(mb, (0.0, T3_TOP + 0.015, 0.22), (4.15, 0.035, 0.14), 'brass', C_TEMPLE_GOLD, 0.0)
    cbox(mb, (0.0, T3_TOP + 0.015, 0.22), (0.14, 0.035, 3.45), 'brass', C_TEMPLE_GOLD, 0.0)

    # Broad Front Ceremonial Offering Steps grounded solidly all the way down to SKIRT_BOT (-3.80 m!)
    _box2(mb, (-2.12, SKIRT_BOT, -4.35), (2.12, 0.15, -3.50), 'temple_stone',
          mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.52), 0.0, (1, 0, 0))
    for si in range(6):
        sy_top = 0.22 + si * 0.34
        sz_f = -4.25 + si * 0.46
        sz_b = sz_f + 0.62
        sw = 3.15 - si * 0.14
        _box2(mb, (-sw * 0.5, sy_top - 0.65, sz_f), (sw * 0.5, sy_top, sz_b),
              'temple_stone', jit(C_TEMPLE_HI if si % 2 == 0 else C_TEMPLE_MID, rng, 0.05), 0.0, (1, 0, 0))
    # Stepped stair cheek balustrades plunging solidly down to SKIRT_BOT (-3.80 m!)
    for sx in (-1.78, 1.78):
        _box2(mb, (sx - 0.34, SKIRT_BOT, -4.35), (sx + 0.34, 1.05, -3.50), 'temple_stone',
              mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.30), 0.0)
        _box2(mb, (sx - 0.38, 1.02, -4.38), (sx + 0.38, 1.24, -3.46), 'limestone_moss',
              mix(C_TEMPLE_HI, C_LEDGE_MOSS, 0.40), 0.0)
        _box2(mb, (sx - 0.28, 0.40, -3.55), (sx + 0.28, 2.15, -1.78), 'temple_stone', C_TEMPLE_MID, 0.0)
        cbox(mb, (sx, 0.64, -4.37), (0.34, 0.34, 0.04), 'brass', C_GOLD_BRIGHT, 0.0, M=R('Z', 45.0))
        if sx > 0:
            with xf(mb, T(sx, 1.24, -3.92)):
                cyl(mb, 0.24, 0.0, 0.14, 6, 'temple_stone', C_TEMPLE_DARK, False, 0.0, 0.30)
                cyl(mb, 0.22, 0.12, 0.18, 6, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.16)

    for sx in (-4.18, 4.18):
        for sz in (-3.65, 3.65):
            sculpt_stone_block(
                mb, (sx, T1_TOP + 0.22, sz), (0.92, 0.62, 0.88),
                'temple_stone', C_TEMPLE_MID, rng, chip=0.06, moss_col=C_LEDGE_MOSS,
            )

    # 2. Central Weathered Stone Altar Slab + Raised Golden Serpent/Compass Sun Relief + Chalices/Idols!
    alt_z = 0.25
    alt_y_top = T3_TOP + 1.18
    for sx in (-0.98, 0.98):
        cbox(mb, (sx, T3_TOP + 0.48, alt_z), (0.64, 0.98, 1.26), 'temple_stone', C_TEMPLE_MID, 0.0, (1, 0, 0))
        cbox(mb, (sx, T3_TOP + 0.12, alt_z), (0.76, 0.26, 1.40), 'temple_stone', C_TEMPLE_DARK, 0.0, (1, 0, 0))
    cbox(mb, (0.0, T3_TOP + 0.48, alt_z + 0.08), (1.36, 0.86, 0.94), 'temple_stone', C_TEMPLE_DARK, 0.0, (1, 0, 0))
    sculpt_stone_block(
        mb, (0.0, alt_y_top - 0.16, alt_z), (2.84, 0.34, 1.68),
        'temple_stone', C_TEMPLE_HI, rng, chip=0.045, moss_col=C_LEDGE_MOSS,
    )
    plinth_col_pts.extend([
        Vector((-1.45, alt_y_top + 0.1, alt_z - 0.85)),
        Vector(( 1.45, alt_y_top + 0.1, alt_z + 0.85)),
    ])

    _add_sun_compass_relief(mb, T(0.0, alt_y_top + 0.01, alt_z - 0.06), rng, scale=1.08, flat_horiz=True)
    _add_sun_compass_relief(mb, T(0.0, T3_TOP + 0.56, alt_z - 0.42), rng, scale=0.62, flat_horiz=False)

    serp_pts = []
    serp_rads = []
    n_serp = 12
    for i in range(n_serp):
        t = i / float(n_serp - 1)
        ang = radians(-155.0 + t * 310.0)
        rr = 0.72 + 0.045 * sin(t * pi * 5.0)
        px = cos(ang) * rr * 1.18
        pz = alt_z - 0.04 + sin(ang) * rr * 0.84
        py = alt_y_top + 0.04 + 0.025 * sin(t * pi * 4.0) + (0.14 * max(0.0, (t - 0.82) / 0.18))
        serp_pts.append(Vector((px, py, pz)))
        serp_rads.append(0.024 + 0.036 * sin(t * pi * 0.85))
    tube(mb, serp_pts, serp_rads, 5, 'brass', C_GOLD_BRIGHT, mode='smooth')
    cbox(mb, serp_pts[-1] + Vector((0.02, 0.02, -0.04)), (0.12, 0.09, 0.16), 'brass', C_GOLD_BRIGHT, 0.0)

    # Chunky Carved Golden Miniature Sea-God / Tiki Idol Statuette perched proudly on rear center of Altar!
    idol_base = Vector((0.0, alt_y_top + 0.01, alt_z + 0.44))
    with xf(mb, T(idol_base)):
        cyl(mb, 0.24, 0.0, 0.14, 6, 'temple_stone', C_TEMPLE_DARK, False, 0.0, 0.20)
        cyl(mb, 0.18, 0.12, 0.56, 6, 'brass', C_TEMPLE_GOLD, False, 0.0, 0.16)
        cbox(mb, (0.0, 0.64, -0.02), (0.34, 0.24, 0.28), 'brass', C_GOLD_BRIGHT, 0.0)
        cbox(mb, (0.0, 0.86,  0.00), (0.42, 0.18, 0.22), 'brass', C_BRASS, 0.0)
        cbox(mb, (0.0, 1.02,  0.00), (0.24, 0.16, 0.18), 'brass', C_GOLD_BRIGHT, 0.0)
        for sx_e in (-0.08, 0.08):
            cbox(mb, (sx_e, 0.66, -0.155), (0.055, 0.045, 0.035), 'skull_glow', C_SKULL_EYE, 0.0)

    _build_gold_chalice(mb, T(-1.02, alt_y_top + 0.01, alt_z - 0.34) @ R('Y', 18.0), scale=1.05)
    _build_gold_chalice(mb, T( 1.06, alt_y_top + 0.01, alt_z + 0.18) @ R('Y', -35.0), scale=0.92)
    _build_gold_chalice(mb, T( 0.94, alt_y_top + 0.11, alt_z - 0.44) @ R('Y', 48.0) @ R('Z', 82.0), scale=0.88)

    # 3. Flanking Pair of Half-Crumbled Carved Stone Monolith Pillars + Glowing Emerald-Turquoise Fire Bowls!
    pillar_specs = [
        (-3.08, 0.92, 6.08, 1.0),
        ( 3.08, 0.92, 5.42, -1.0),
    ]
    bowl_glow_centers = []

    for px, pz, py_top, side_s in pillar_specs:
        p_secs = [
            _rect_oct(px, T1_TOP - 0.15, pz, 0.98, 0.98, 0.18),
            _rect_oct(px, T2_TOP + 0.25, pz, 0.84, 0.84, 0.16),
            _rect_oct(px, py_top - 1.35, pz, 0.72, 0.72, 0.15),
            _rect_oct(px, py_top - 0.35, pz, 0.78, 0.78, 0.15),
        ]
        _loft_horizontal_masonry(
            mb, p_secs, 'temple_stone',
            [mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.34), C_TEMPLE_MID, C_TEMPLE_MID, C_TEMPLE_HI],
            rng, caps=(False, True),
        )
        cbox(mb, (px, 3.42, pz), (1.62, 0.26, 1.62), 'temple_stone', C_TEMPLE_HI, 0.0)
        cbox(mb, (px, 3.42, pz), (1.66, 0.09, 1.66), 'brass', C_GOLD_BRIGHT, 0.0)
        sculpt_stone_block(
            mb, (px - side_s * 0.10, py_top - 0.16, pz + 0.06), (1.66, 0.44, 1.62),
            'temple_stone', C_TEMPLE_HI, rng, chip=0.065,
            M=R('Z', side_s * 3.5), moss_col=C_LEDGE_MOSS,
        )
        sculpt_stone_block(
            mb, (px + side_s * 0.42, py_top + 0.30, pz + 0.36), (0.64, 0.56, 0.58),
            'temple_stone', C_TEMPLE_MID, rng, chip=0.06,
            M=R('Z', -side_s * 12.0), moss_col=C_LEDGE_MOSS,
        )

        by = py_top + 0.06
        with xf(mb, T(px, by, pz)):
            bowl_prof = [
                (0.0,  0.0),  (0.46, 0.0),  (0.36, 0.16), (0.66, 0.36),
                (0.76, 0.52), (0.62, 0.54), (0.48, 0.34), (0.0,  0.32),
            ]
            lathe(mb, bowl_prof, 8, 'temple_stone', C_TEMPLE_DARK, False)
            torus(mb, 0.72, 0.048, 8, 4, 'brass', C_TEMPLE_GOLD, False)
            for bk in range(4):
                ang = bk * pi * 0.5 + pi * 0.25
                cbox(mb, (cos(ang) * 0.68, 0.34, sin(ang) * 0.68), (0.10, 0.36, 0.10), 'brass', C_BRASS, 0.0)
            bm = bmesh.new()
            bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
            for v in bm.verts:
                p = v.co
                v.co = Vector((p.x * 0.48, 0.46 + p.y * 0.22, p.z * 0.48))
            bm.faces.ensure_lookup_table()
            mb.newoff()
            for f in bm.faces:
                pts = [v.co.copy() for v in f.verts]
                mb.fp(pts, 'skull_glow', jit(C_SKULL_EYE, rng, 0.06), (0, 1, 0), Vector((0, 0.42, 0)), smooth=False)
            bm.free()
            for foff, (frx, fry), frot in (
                (( 0.00, 0.58,  0.00), (0.18, 0.68), ( 4,  10,  5)),
                ((-0.18, 0.50, -0.10), (0.13, 0.48), (-8,  30, 14)),
                (( 0.18, 0.52,  0.12), (0.13, 0.50), ( 7, -25,-12)),
                (( 0.02, 0.48, -0.18), (0.11, 0.42), (10,  45, -6)),
            ):
                with xf(mb, T(foff) @ R('Y', frot[1]) @ R('X', frot[0]) @ R('Z', frot[2])):
                    lathe(mb, [(0.0, -0.10), (frx, 0.0), (frx * 0.65, fry * 0.48), (0.0, fry)],
                          5, 'skull_glow', jit(C_EMERALD_CORE, rng, 0.07), False)
        bowl_glow_centers.append(Vector((px, by + 0.72, pz)))
        pillar_col_pts.extend([
            Vector((px - 0.95, T1_TOP, pz - 0.95)),
            Vector((px + 0.95, py_top + 0.85, pz + 0.95)),
        ])

    # Half-crumbled Carved Rear Relic Wall framing behind the Altar (z = +2.38 m)
    wall_blocks = [
        ((-1.78, T3_TOP + 0.85, 2.38), (1.38, 1.85, 0.82), ( 2,  -4,  3), C_TEMPLE_MID),
        ((-0.42, T3_TOP + 1.15, 2.42), (1.42, 2.45, 0.86), (-1,   3, -2), C_TEMPLE_HI),
        (( 0.95, T3_TOP + 0.98, 2.38), (1.36, 2.12, 0.84), ( 3,  -5, -4), C_TEMPLE_MID),
        (( 2.15, T3_TOP + 0.55, 2.32), (1.02, 1.25, 0.76), (-4,   8, -8), C_TEMPLE_DARK),
        ((-0.35, T3_TOP + 2.48, 2.42), (1.08, 0.76, 0.74), ( 2,  -6,  5), C_TEMPLE_HI),
    ]
    for wctr, wsz, wrot, wcol in wall_blocks:
        M_w = R('Y', wrot[1]) @ R('X', wrot[0]) @ R('Z', wrot[2])
        sculpt_stone_block(mb, wctr, wsz, 'temple_stone', wcol, rng, chip=0.06, M=M_w, moss_col=C_LEDGE_MOSS)
    _add_sun_compass_relief(mb, T(-0.35, T3_TOP + 1.65, 1.94), rng, scale=0.72, flat_horiz=False)
    pillar_col_pts.extend([Vector((-2.55, T3_TOP, 1.90)), Vector((2.65, T3_TOP + 2.85, 2.88))])

    # 4. Cascading Sculpted Leafy 'foliage' Jungle Vines & Broad Fern Clusters (with UV2 wind weights!)
    vine_specs = [
        ((-3.08, 5.82,  0.10), 3.35, 0.32, ( 0.05, 0.0, -1.0), 0.10),
        ((-3.88, 5.45,  0.95), 3.10, 0.30, (-1.00, 0.0, -0.1), 0.24),
        (( 3.08, 5.18,  0.10), 2.95, 0.32, (-0.05, 0.0, -1.0), 0.39),
        (( 3.86, 4.95,  0.92), 2.80, 0.28, ( 1.00, 0.0,  0.1), 0.54),
        ((-0.42, 4.72,  2.02), 2.15, 0.28, ( 0.00, 0.0, -1.0), 0.68),
        ((-4.48, 0.74, -2.15), 2.25, 0.32, (-1.00, 0.0, -0.2), 0.79),
        (( 4.48, 0.74, -1.95), 2.35, 0.32, ( 1.00, 0.0, -0.2), 0.91),
        (( 0.85, 0.74,  4.05), 2.40, 0.34, ( 0.10, 0.0,  1.0), 0.45),
    ]
    for anc, vlen, vw, vdir, vph in vine_specs:
        _add_leafy_vine_drape(mb, anc, vlen, vw, vdir, rng, phase=vph)

    fern_specs = [
        ((-3.75, T1_TOP - 0.06, -2.65), 1.30, 6, 0.12, (-0.6, 0.0, -0.8)),
        (( 3.82, T1_TOP - 0.06, -2.55), 1.35, 6, 0.31, ( 0.6, 0.0, -0.8)),
        ((-3.92, T1_TOP - 0.06,  2.45), 1.38, 6, 0.48, (-0.7, 0.0,  0.7)),
        (( 3.85, T1_TOP - 0.06,  2.55), 1.28, 6, 0.66, ( 0.7, 0.0,  0.7)),
        ((-2.65, T2_TOP - 0.06, -1.78), 1.08, 5, 0.80, (-0.5, 0.0, -0.8)),
        (( 2.68, T2_TOP - 0.06, -1.72), 1.10, 5, 0.94, ( 0.5, 0.0, -0.8)),
        ((-2.25, T2_TOP - 0.06,  2.48), 1.18, 5, 0.22, (-0.3, 0.0,  0.9)),
    ]
    for fpos, fsc, nf, fph, flean in fern_specs:
        _add_jungle_fern_cluster(mb, fpos, scale=fsc, n_fronds=nf, rng=rng, phase=fph, lean_dir=flean)

    build(mb)

    altar_light_pos = (
        0.5 * (bowl_glow_centers[0].x + bowl_glow_centers[1].x),
        0.5 * (bowl_glow_centers[0].y + bowl_glow_centers[1].y) - 0.15,
        0.65,
    )
    add_empty('Lantern_Altar', altar_light_pos)
    col_piece('col_altar_plinth', plinth_col_pts)
    col_piece('col_altar_pillars', pillar_col_pts)
    export_landmark_glb(outdir, 'overgrown_jungle_idol_altar.glb')


# ================================================================ 3. CLIFFSIDE WATERFALL SHRINE

def gen_cliffside_waterfall_shrine(outdir):
    """Sculpted mossy temple-stone cliffside waterfall shrine archway & terraced pool basin
    (~10.2 m tall x ~9.0 m wide, facing seaward -Z).
    Deep -4.20 m stepped stone base + solid +4.50 m rear cliff-weld masonry backing so it NEVER
    floats on steep slopes, flanking battered temple-stone piers, soaring 11-voussoir carved stone
    archway over an open terraced turquoise-stone water pool basin, carved guardian stone sea-serpent
    & golden compass crest keystone at the arch crown, deep-grounded weathered front offering steps
    leading to the basin rim, hanging ornate gilded-brass shrine censer ('Lantern_WaterfallShrine'
    at glow core!), and rich trailing leafy 'foliage' moss vines & cliff ferns with UV2 wind weights!
    Target: 2,400-3,800 visual tris, 2 colliders (col_shrine_left, col_shrine_right keeping center open!).
    """
    clear_scene()
    rng = random.Random(SEED + 1171)
    mb = MB('CliffsideWaterfallShrine', seed=1171)

    BASE_BOT = -4.20
    Z_BACK = 4.50
    SPRING_Y = 5.45
    R_IN = 2.15
    R_OUT = 2.98
    CORN_Y = 8.78

    left_col_pts = []
    right_col_pts = []

    # 1. Deep Stepped Stone Base (y = -4.20 .. +0.56 m) + Solid Rear Cliff-Weld Masonry Backing (to z = +4.50 m!)
    base_secs = [
        _rect_oct(0.0, BASE_BOT, 0.62, 4.78, 3.95, 0.58),
        _rect_oct(0.0, -1.80,    0.58, 4.58, 3.85, 0.54),
        _rect_oct(0.0,  0.15,    0.54, 4.46, 3.76, 0.48),
        _rect_oct(0.0,  0.56,    0.52, 4.38, 3.68, 0.46),
    ]
    _loft_horizontal_masonry(
        mb, base_secs, 'temple_stone',
        [mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.64), mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.48),
         mix(C_TEMPLE_MID, C_SEA_MOSS, 0.30), C_TEMPLE_MID],
        rng, caps=(True, True),
        top_mat='limestone_moss', top_col=mix(C_TEMPLE_MID, C_LEDGE_MOSS, 0.44),
    )

    # Massive Solid Rear Cliff-Weld Masonry Backing Wall (z = +1.35 .. +4.50 m, y = -4.20 .. +8.95 m!)
    back_tiers = [
        (-4.20, 2.60, 4.48, 1.36, Z_BACK,        mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.40)),
        ( 2.40, 6.20, 4.30, 1.42, Z_BACK,        C_TEMPLE_MID),
        ( 6.00, 8.95, 4.10, 1.48, Z_BACK - 0.15, C_TEMPLE_HI),
    ]
    for yb, yt, xh, zf, zb, bcol in back_tiers:
        _box2(mb, (-xh, yb, zf), (xh, yt, zb), 'temple_stone', bcol, 0.0, (1, 0, 0))
    for sx in (-3.65, 3.65):
        sculpt_rock_mass(
            mb, (sx, 2.25, 3.35), (1.35, 4.85, 1.45), 'limestone_moss',
            C_LEDGE_MOSS, C_LIME_MID, C_LIME_DARK, rng,
            subdiv=2, warp=0.18, strata=0.16, base_flare=0.26, moss_cap=0.68,
        )

    # Carved Waterfall Spout Chute Niche in Rear Backing Wall (y = 4.55 m, z = +1.30 m)
    _box2(mb, (-1.18, 0.56, 1.24), (1.18, 4.95, 1.56), 'temple_stone',
          mix(C_TEMPLE_DARK, C_WATER_DEEP, 0.48), 0.0, (0, 1, 0))
    _box2(mb, (-0.76, 4.32, 0.58), (0.76, 4.62, 1.52), 'temple_stone', C_TEMPLE_HI, 0.0, (1, 0, 0))
    for sx in (-0.72, 0.72):
        _box2(mb, (sx - 0.16, 4.52, 0.62), (sx + 0.16, 5.02, 1.50), 'temple_stone', C_TEMPLE_MID, 0.0)
    cbox(mb, (0.0, 4.46, 0.55), (1.12, 0.08, 0.18), 'brass', C_GOLD_BRIGHT, 0.0)
    for wx, ww, wz, wc in (
        ( 0.00, 0.68, 0.92, C_WATER_TURQ),
        (-0.32, 0.28, 0.98, C_WATER_FOAM),
        ( 0.34, 0.26, 0.98, C_WATER_FOAM),
    ):
        _box2(mb, (wx - ww * 0.5, 0.62, wz - 0.08), (wx + ww * 0.5, 4.48, wz + 0.08), 'paint', wc, 0.0, (0, 1, 0))

    # 2. Terraced Carved Stone Pool Basin & Deep-Grounded Front Offering Steps (-Z approach, center OPEN!)
    basin_rim = [
        (-2.28, 1.25), (-2.28, -1.65), (-1.42, -2.55), (1.42, -2.55), (2.28, -1.65), (2.28, 1.25),
    ]
    for i in range(len(basin_rim) - 1):
        x0, z0 = basin_rim[i]
        x1, z1 = basin_rim[i + 1]
        is_spill = (i == 2)
        h_rim = 0.92 if is_spill else 1.28
        p0 = Vector((x0, (0.56 + h_rim) * 0.5, z0))
        p1 = Vector((x1, (0.56 + h_rim) * 0.5, z1))
        seg = p1 - p0
        yaw_s = -degrees(atan2(seg.z, seg.x))
        with xf(mb, T((p0 + p1) * 0.5) @ R('Y', yaw_s)):
            cbox(mb, (0.0, 0.0, 0.0), (seg.length + 0.24, h_rim - 0.50, 0.44),
                 'temple_stone', C_TEMPLE_HI if not is_spill else C_TEMPLE_MID, 0.0, (1, 0, 0))
            if not is_spill:
                cbox(mb, (0.0, (h_rim - 0.50) * 0.5 + 0.06, 0.0), (seg.length + 0.32, 0.14, 0.54),
                     'limestone_moss', mix(C_TEMPLE_HI, C_LEDGE_MOSS, 0.42), 0.0, (1, 0, 0))
    _box2(mb, (-2.10, 0.58, -2.35), (2.10, 0.88, 1.25), 'paint', C_WATER_DEEP, 0.0, (1, 0, 0))
    _box2(mb, (-1.65, 0.86, -1.95), (1.65, 0.91, 1.05), 'paint', C_WATER_TURQ, 0.0, (1, 0, 0))
    with xf(mb, T(0.0, 0.92, 0.68)):
        cyl(mb, 0.72, 0.0, 0.03, 8, 'paint', C_WATER_FOAM, False, 0.0)
    _box2(mb, (-0.52, 0.10, -2.86), (0.52, 0.92, -2.42), 'paint', C_WATER_TURQ, 0.0, (0, 1, 0))

    # Deep-grounded Front Offering Steps & Entry Balustrades extending cleanly down to BASE_BOT (-4.20 m!)
    _box2(mb, (-2.86, BASE_BOT, -4.16), (2.86, 0.05, -2.85), 'temple_stone',
          mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.56), 0.0, (1, 0, 0))
    for si in range(4):
        sy_t = 0.08 + si * 0.28
        sz_f = -4.10 + si * 0.40
        _box2(mb, (-2.38 + si * 0.08, sy_t - 0.50, sz_f), (2.38 - si * 0.08, sy_t, sz_f + 0.48),
              'temple_stone', jit(C_TEMPLE_MID if si % 2 == 0 else C_TEMPLE_HI, rng, 0.045), 0.0, (1, 0, 0))
    for sx in (-2.52, 2.52):
        _box2(mb, (sx - 0.34, BASE_BOT, -4.16), (sx + 0.34, 1.18, -2.55), 'temple_stone',
              mix(C_TEMPLE_MID, C_SEA_MOSS, 0.24), 0.0)
        with xf(mb, T(sx, 1.18, -3.72)):
            cyl(mb, 0.22, 0.0, 0.16, 6, 'brass', C_TEMPLE_GOLD, False, 0.0, 0.28)
            cyl(mb, 0.18, 0.14, 0.20, 6, 'glass', C_LANTERN_GL, False, 0.0, 0.10)

    # 3. Flanking Monumental Battered Temple-Stone Shrine Piers (x = ±3.22 m, y = -4.20 .. 5.45 m!)
    for sx_p, col_list in ((-3.22, left_col_pts), (3.22, right_col_pts)):
        p_secs = [
            _rect_oct(sx_p, BASE_BOT,  -0.05, 1.48, 1.85, 0.22),
            _rect_oct(sx_p,  0.40,     -0.05, 1.32, 1.66, 0.20),
            _rect_oct(sx_p,  3.10,     -0.05, 1.18, 1.50, 0.18),
            _rect_oct(sx_p,  SPRING_Y, -0.05, 1.10, 1.40, 0.16),
        ]
        _loft_horizontal_masonry(
            mb, p_secs, 'temple_stone',
            [mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.48), mix(C_TEMPLE_MID, C_SEA_MOSS, 0.22),
             C_TEMPLE_MID, C_TEMPLE_HI],
            rng, caps=(True, True),
        )
        cbox(mb, (sx_p, 2.95, -1.52), (1.18, 3.85, 0.18), 'temple_stone', C_TEMPLE_DARK, 0.0, (0, 1, 0))
        cbox(mb, (sx_p, 2.95, -1.62), (0.14, 3.20, 0.05), 'brass', C_GOLD_BRIGHT, 0.0)
        cbox(mb, (sx_p, 5.52, -0.05), (2.48, 0.34, 3.05), 'temple_stone', C_TEMPLE_MID, 0.0, (1, 0, 0))
        cbox(mb, (sx_p, 5.82, -0.05), (2.72, 0.30, 3.24), 'temple_stone', C_TEMPLE_HI, 0.0, (1, 0, 0))
        cbox(mb, (sx_p, 5.82, -1.69), (2.10, 0.10, 0.05), 'brass', C_GOLD_BRIGHT, 0.0)

        x_in = -1.98 if sx_p < 0 else 1.98
        x_out = -4.65 if sx_p < 0 else 4.65
        for xx in (x_in, x_out):
            for yy in (BASE_BOT, 10.05):
                for zz in (-3.35, Z_BACK):
                    col_list.append(Vector((xx, yy, zz)))

    # 4. Soaring 11-Voussoir Carved Stone Archway + Recessed Coplanar-Free Spandrel Masonry!
    arch_z = -0.10
    n_vous = 11
    for vi in range(n_vous):
        ang0 = pi * (vi / float(n_vous))
        ang1 = pi * ((vi + 1) / float(n_vous))
        is_key = (vi == n_vous // 2)
        if is_key:
            ro = R_OUT + 0.32
            ri_v = R_IN - 0.08
            hz_v = 1.62
            vcol = C_TEMPLE_HI
        else:
            step_r = 0.09 if (vi % 2 == 0) else -0.04
            ro = R_OUT + step_r
            ri_v = R_IN
            hz_v = 1.48 if (vi % 2 == 0) else 1.38
            vcol = C_TEMPLE_HI if (vi % 2 == 0) else C_TEMPLE_MID
        _add_trapezoid_voussoir(mb, (0.0, SPRING_Y), ang0, ang1, ri_v, ro, hz_v,
                                'temple_stone', vcol, rng, z_ctr=arch_z)

    # Solid curved spandrel infill recessed cleanly (hz_sp = 1.24 < hz_v = 1.38) -> ZERO Z-fighting!
    _box2(mb, (-4.38, SPRING_Y, -1.34), (-2.12, CORN_Y + 0.08, 1.34), 'temple_stone', C_TEMPLE_MID, 0.0, (1, 0, 0))
    _box2(mb, ( 2.12, SPRING_Y, -1.34), ( 4.38, CORN_Y + 0.08, 1.34), 'temple_stone', C_TEMPLE_MID, 0.0, (1, 0, 0))
    r_sp = 2.66
    hz_sp = 1.24
    n_sp = 10
    for si in range(n_sp):
        a0 = pi * (si / float(n_sp))
        a1 = pi * ((si + 1) / float(n_sp))
        x0, y0 = cos(a0) * r_sp, SPRING_Y + sin(a0) * r_sp
        x1, y1 = cos(a1) * r_sp, SPRING_Y + sin(a1) * r_sp
        c_sp = jit(C_TEMPLE_MID if si % 2 == 0 else C_TEMPLE_HI, rng, 0.03)
        in_ref = Vector((0.5 * (x0 + x1), 0.5 * (min(y0, y1) + CORN_Y), arch_z))
        mb.fp([(x0, y0, arch_z - hz_sp), (x1, y1, arch_z - hz_sp),
               (x1, CORN_Y, arch_z - hz_sp), (x0, CORN_Y, arch_z - hz_sp)],
              'temple_stone', c_sp, (1, 0, 0), in_ref, smooth=False)
        mb.fp([(x1, y1, arch_z + hz_sp), (x0, y0, arch_z + hz_sp),
               (x0, CORN_Y, arch_z + hz_sp), (x1, CORN_Y, arch_z + hz_sp)],
              'temple_stone', c_sp, (1, 0, 0), in_ref, smooth=False)

    # Stepped Overhanging Temple Cornice & Terraced Mossy Roof Crest rising to y = 10.22 m!
    _box2(mb, (-4.62, CORN_Y, -1.78), (4.62, CORN_Y + 0.44, 1.85), 'temple_stone', C_TEMPLE_HI, 0.0, (1, 0, 0))
    _box2(mb, (-3.95, CORN_Y + 0.42, -1.42), (3.95, CORN_Y + 0.88, 1.95), 'limestone_moss',
          mix(C_TEMPLE_MID, C_LEDGE_MOSS, 0.52), 0.0, (1, 0, 0))
    for sx in (-3.85, 3.85):
        sculpt_stone_block(
            mb, (sx, CORN_Y + 0.92, -0.75), (1.18, 0.88, 1.18),
            'temple_stone', C_TEMPLE_HI, rng, chip=0.055, moss_col=C_LEDGE_MOSS,
        )
        cbox(mb, (sx, CORN_Y + 1.44, -0.75), (0.58, 0.34, 0.58), 'temple_stone', C_TEMPLE_MID, 0.0)

    # 5. Carved Guardian Stone Sea-Serpent & Golden Compass Crest Keystone at Arch Crown!
    key_y = 8.65
    key_z = -1.76
    sculpt_stone_block(
        mb, (0.0, key_y + 0.55, key_z + 0.24), (2.25, 1.98, 0.92),
        'temple_stone', C_TEMPLE_HI, rng, chip=0.05, moss_col=C_LEDGE_MOSS,
    )
    _add_sun_compass_relief(mb, T(0.0, key_y, key_z - 0.16), rng, scale=1.08, flat_horiz=False)
    for sgn in (-1.0, 1.0):
        horn_path = [
            (sgn * 0.55, key_y + 0.42, key_z - 0.14),
            (sgn * 1.12, key_y + 0.86, key_z - 0.24),
            (sgn * 1.38, key_y + 1.32, key_z - 0.16),
            (sgn * 1.04, key_y + 1.60, key_z - 0.08),
        ]
        tube(mb, horn_path, [0.22, 0.18, 0.13, 0.07], 6, 'temple_stone', C_TEMPLE_HI, mode='flat')
        tube(mb, [Vector(p) + Vector((0.0, 0.06, -0.10)) for p in horn_path[:3]],
             [0.065, 0.052, 0.036], 4, 'brass', C_GOLD_BRIGHT, mode='flat')
        cbox(mb, (sgn * 0.34, key_y + 0.92, key_z - 0.24), (0.14, 0.09, 0.06), 'skull_glow', C_SKULL_EYE, 0.0)
    sculpt_stone_block(
        mb, (0.0, 9.88, key_z + 0.18), (0.76, 0.78, 0.62),
        'temple_stone', C_TEMPLE_HI, rng, chip=0.045, M=R('Z', 45.0), moss_col=C_LEDGE_MOSS,
    )

    # 6. Ornate Hanging Brass Shrine Censer ('Lantern_WaterfallShrine' Empty at glow core!)
    censer_z = -0.58
    arch_ceil = Vector((0.0, SPRING_Y + R_IN - 0.04, censer_z))
    censer_y = 5.32
    censer_pos = (0.0, censer_y, censer_z)
    with xf(mb, T(arch_ceil)):
        cyl(mb, 0.20, -0.08, 0.14, 6, 'brass', C_TEMPLE_GOLD, False, 0.0)
    _add_chain_links(
        mb,
        arch_ceil + Vector((0.0, -0.06, 0.0)),
        Vector((0.0, censer_y + 0.72, censer_z)),
        n_links=9, link_r=0.052, wire_r=0.015, mat='brass',
    )
    with xf(mb, T(censer_pos)):
        bot_prof = [
            (0.0,  -0.68), (0.06, -0.54), (0.14, -0.36), (0.44, -0.22),
            (0.48, -0.14), (0.38, -0.12), (0.0,  -0.12),
        ]
        lathe(mb, bot_prof, 6, 'brass', C_TEMPLE_GOLD, False)
        cyl(mb, 0.30, -0.14, 0.26, 6, 'glass', C_LANTERN_GL, False, 0.0, 0.36)
        top_prof = [
            (0.0,  0.24), (0.46, 0.24), (0.50, 0.30), (0.36, 0.44),
            (0.20, 0.56), (0.08, 0.68), (0.0,  0.76),
        ]
        lathe(mb, top_prof, 6, 'brass', C_GOLD_BRIGHT, False)
        for k in range(6):
            ang = 2.0 * pi * k / 6.0
            ca, sa = cos(ang), sin(ang)
            tube(mb, [(ca * 0.42, -0.18, sa * 0.42), (ca * 0.45, 0.28, sa * 0.45)],
                 0.028, 4, 'brass', C_BRASS, mode='flat')

    # 7. Rich Trailing Sculpted Leafy 'foliage' Moss Vines & Lush Cliff Ferns (with UV2 wind weights!)
    vine_specs = [
        ((-1.95, 8.85, -1.62), 4.10, 0.34, (-0.12, 0.0, -1.0), 0.09),
        (( 1.98, 8.82, -1.62), 3.85, 0.32, ( 0.14, 0.0, -1.0), 0.25),
        ((-3.35, 8.75, -1.68), 3.55, 0.34, (-0.22, 0.0, -1.0), 0.41),
        (( 3.38, 8.72, -1.68), 3.40, 0.32, ( 0.22, 0.0, -1.0), 0.58),
        ((-1.25, 5.10,  1.22), 2.65, 0.28, ( 0.15, 0.0, -1.0), 0.72),
        (( 1.28, 5.05,  1.22), 2.55, 0.28, (-0.15, 0.0, -1.0), 0.86),
        ((-4.42, 5.75, -0.35), 3.25, 0.30, (-1.00, 0.0, -0.1), 0.33),
        (( 4.42, 5.75, -0.35), 3.15, 0.30, ( 1.00, 0.0, -0.1), 0.64),
    ]
    for anc, vlen, vw, vdir, vph in vine_specs:
        _add_leafy_vine_drape(mb, anc, vlen, vw, vdir, rng, phase=vph)

    fern_specs = [
        ((-3.55, 0.56, -2.32), 1.32, 6, 0.15, (-0.5, 0.0, -0.8)),
        (( 3.58, 0.56, -2.28), 1.35, 6, 0.42, ( 0.5, 0.0, -0.8)),
        ((-2.65, CORN_Y + 0.82, -1.15), 1.15, 5, 0.68, (-0.3, 0.0, -0.9)),
        (( 2.68, CORN_Y + 0.82, -1.12), 1.18, 5, 0.88, ( 0.3, 0.0, -0.9)),
    ]
    for fpos, fsc, nf, fph, flean in fern_specs:
        _add_jungle_fern_cluster(mb, fpos, scale=fsc, n_fronds=nf, rng=rng, phase=fph, lean_dir=flean)

    build(mb)

    add_empty('Lantern_WaterfallShrine', censer_pos)
    col_piece('col_shrine_left', left_col_pts)
    col_piece('col_shrine_right', right_col_pts)
    export_landmark_glb(outdir, 'cliffside_waterfall_shrine.glb')


# ================================================================ 4. SMUGGLER CONTRABAND HOARD

def gen_smuggler_contraband_hoard(outdir):
    """Sheltered pirate contraband stash (~6.4 m wide x ~5.0 m deep, stepped weathered driftwood &
    stone bedding skirt sinking cleanly to y = -1.80 m for sloped cove beaches!).
    Asymmetric weathered cream/crimson canvas sailcloth tarpaulin rigged over notched crooked
    driftwood poles & taut braided hemp guy ropes, sheltering a densely packed contraband hoard:
    2 ornate iron-banded oak treasure chests (front hero chest cracked ajar spilling golden coins
    & chalices in 'brass'!), 3 tall coopered wine casks (2 upright + 1 cradled horizontal with
    brass spigot), 2 crimson-painted powder kegs ('paint' + 'iron'), coiled heavy forged-iron
    anchor chain, and a warm brass hurricane lantern sitting squarely atop a barrel ('Lantern_Hoard').
    Target: 2,400-3,600 visual tris, 1 collider (col_hoard_stack).
    """
    clear_scene()
    rng = random.Random(SEED + 1201)
    mb = MB('SmugglerContrabandHoard', seed=1201)

    SKIRT_BOT = -1.80
    DECK_Y = 0.24
    col_pts = []

    # 1. Stepped Weathered Stone & Driftwood Cove Bedding Skirt (6.4 m x 5.0 m, down to y = -1.80 m!)
    bed_secs = [
        _rect_oct(0.0, SKIRT_BOT, 0.0, 3.55, 2.85, 0.65),
        _rect_oct(0.0, -0.72,     0.0, 3.30, 2.62, 0.58),
        _rect_oct(0.0,  0.14,     0.0, 3.06, 2.40, 0.52),
    ]
    _loft_horizontal_masonry(
        mb, bed_secs, 'limestone',
        [mix(C_LIME_DARK, C_SEA_MOSS, 0.52), C_LIME_SHADE, C_LIME_MID],
        rng, caps=(True, True),
        top_mat='limestone_moss', top_col=mix(C_LIME_WARM, C_LEDGE_MOSS, 0.34),
    )
    for ring in bed_secs:
        col_pts.extend(Vector(p) for p in ring)

    # Salvaged Ship-Timber Duckboard Sleepers & Irregular Weathered Driftwood Deck Planks (y = 0.12..0.24 m)
    for sz_s in (-1.25, 0.0, 1.25):
        _box2(mb, (-2.65, 0.08, sz_s - 0.11), (2.65, 0.18, sz_s + 0.11), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
    for pi_i in range(9):
        px = -2.28 + pi_i * 0.57
        pl = 3.45 + rng.uniform(-0.32, 0.28)
        cbox(mb, (px, DECK_Y - 0.035 + rng.uniform(-0.008, 0.008), rng.uniform(-0.14, 0.12)),
             (0.49, 0.085, pl), 'timber',
             jit(C_DRIFTWOOD if pi_i % 3 == 0 else (C_TIMBER_MID if pi_i % 2 == 0 else C_TIMBER_HI), rng, 0.07),
             0.0, (0, 0, 1), M=R('Y', rng.uniform(-1.8, 1.8)))

    sculpt_rock_mass(
        mb, (-2.55, 0.22, 1.88), (0.92, 0.78, 0.82), 'limestone_moss',
        C_LEDGE_MOSS, C_LIME_WARM, C_LIME_SHADE, rng, subdiv=1, warp=0.22, base_flare=0.25, moss_cap=0.60,
    )
    sculpt_rock_mass(
        mb, (2.52, 0.18, 1.92), (0.86, 0.68, 0.78), 'limestone',
        C_LIME_PALE, C_LIME_WARM, C_LIME_SHADE, rng, subdiv=1, warp=0.22, base_flare=0.25, moss_cap=0.22,
    )

    # 2. Asymmetric Notched Crooked Driftwood Poles (plunging to y = -1.80 m) + Canvas Sailcloth Tarpaulin!
    pole_specs = [
        ('fl', -2.32, -1.28, 3.22, -0.14, -0.10, 0.135, 0.088),
        ('fr',  2.36, -1.16, 2.58,  0.18, -0.08, 0.125, 0.084),
        ('bl', -2.26,  1.62, 1.82, -0.08,  0.14, 0.118, 0.080),
        ('br',  2.22,  1.58, 1.48,  0.10,  0.12, 0.115, 0.078),
    ]
    pole_tops = {}
    for pname, bx, bz, ytop, lx, lz, rb, rt in pole_specs:
        path = []
        rads = []
        cols = []
        for i in range(4):
            t = i / 3.0
            y = SKIRT_BOT + t * (ytop - SKIRT_BOT)
            crook_x = sin(t * pi * 1.4 + bx) * 0.065 * sin(t * pi)
            crook_z = cos(t * pi * 1.3 + bz) * 0.055 * sin(t * pi)
            path.append(Vector((bx + lx * t + crook_x, y, bz + lz * t + crook_z)))
            rads.append(rb * (1.0 - t) + rt * t)
            cols.append(jit(mix(C_TIMBER_DARK, C_DRIFTWOOD, smooth01((y + 0.5) / 3.4)), rng, 0.06))
        tube(mb, path, rads, 5, 'timber', C_DRIFTWOOD, mode='flat', scols=cols)
        jpt = path[-2].lerp(path[-1], 0.62)
        pole_tops[pname] = jpt
        col_pts.append(path[-1])
        stub_d = Vector((0.22 if bx > 0 else -0.22, 0.28, -0.10 if bz < 0 else 0.10))
        tube(mb, [jpt - Vector((0.0, 0.08, 0.0)), jpt + stub_d], [0.058, 0.028], 4, 'timber', C_DRIFTWOOD, mode='flat')
        with xf(mb, T(jpt)):
            cyl(mb, 0.125, -0.055, 0.055, 6, 'rope', C_ROPE, False, 0.0)

    p_fl, p_fr = pole_tops['fl'], pole_tops['fr']
    p_bl, p_br = pole_tops['bl'], pole_tops['br']

    for pa, pb, rad in ((p_fl, p_fr, 0.072), (p_bl, p_br, 0.064), (p_fl, p_bl, 0.060), (p_fr, p_br, 0.058)):
        v = (pb - pa).normalized()
        a_e = pa - v * 0.34
        b_e = pb + v * 0.34
        tube(mb, [a_e, a_e.lerp(b_e, 0.5) + Vector((0.0, -0.04, 0.0)), b_e],
             [rad, rad * 0.92, rad * 0.88], 4, 'timber', C_TIMBER_MID, mode='flat')

    # Double-Sided Real-Thickness Asymmetric Weathered Cream/Crimson Canvas Sailcloth Tarpaulin!
    nu, nv = 6, 5
    thick = 0.024

    def _tarp_pt(u, v):
        f_l = p_fl + Vector((-0.24, 0.07, -0.30))
        f_r = p_fr + Vector(( 0.26, 0.06, -0.26))
        b_l = p_bl + Vector((-0.22, 0.05,  0.34))
        b_r = p_br + Vector(( 0.24, 0.05,  0.36))
        pf = f_l.lerp(f_r, u)
        pb = b_l.lerp(b_r, u)
        p = pf.lerp(pb, v)
        sag = sin(u * pi) * sin(v * pi) * 0.32
        flutter = sin(u * pi * 2.5 + v * 1.8) * 0.065 * sin(v * pi)
        flap_drop = 0.0
        if v > 0.78:
            flap_drop -= 0.42 * ((v - 0.78) / 0.22) ** 1.3
        elif v < 0.18:
            flap_drop -= 0.22 * ((0.18 - v) / 0.18) ** 1.4 - 0.05 * abs(sin(u * pi * 3.0))
        if u > 0.82:
            flap_drop -= 0.36 * ((u - 0.82) / 0.18) ** 1.3 * (0.4 + 0.6 * v)
        p.y += -sag + flutter + flap_drop
        return p

    top_g = [[None] * (nv + 1) for _ in range(nu + 1)]
    bot_g = [[None] * (nv + 1) for _ in range(nu + 1)]
    for iu in range(nu + 1):
        u = iu / float(nu)
        for iv in range(nv + 1):
            v = iv / float(nv)
            p = _tarp_pt(u, v)
            pu = _tarp_pt(min(1.0, u + 0.02), v) - _tarp_pt(max(0.0, u - 0.02), v)
            pv = _tarp_pt(u, min(1.0, v + 0.02)) - _tarp_pt(u, max(0.0, v - 0.02))
            n = pv.cross(pu)
            if n.y < 0:
                n = -n
            n = n.normalized() if n.length > 1e-6 else Vector((0.0, 1.0, 0.0))
            top_g[iu][iv] = p + n * (thick * 0.5)
            bot_g[iu][iv] = p - n * (thick * 0.5)

    def _tarp_col(iu, iv):
        if iu in (1, 4):
            c = C_PAINT_RED
        elif iu == 3 and iv in (2, 3):
            c = C_PAINT_TEAL
        elif (iu == 0 and iv == 3) or (iu == 5 and iv == 1):
            c = C_PAINT_RED
        elif (iu + iv) % 2 == 0:
            c = C_SAIL_CREAM
        else:
            c = C_SAIL_WARM
        return jit(c, rng, 0.045, 0.015)

    mb.newoff()
    for iu in range(nu):
        for iv in range(nv):
            c_t = _tarp_col(iu, iv)
            c_b = mul(c_t, 0.82)
            t00, t10, t11, t01 = top_g[iu][iv], top_g[iu + 1][iv], top_g[iu + 1][iv + 1], top_g[iu][iv + 1]
            b00, b10, b11, b01 = bot_g[iu][iv], bot_g[iu + 1][iv], bot_g[iu + 1][iv + 1], bot_g[iu][iv + 1]
            ctr = (t00 + t11 + b00 + b11) * 0.25
            mb.fp([t00, t10, t11, t01], 'paint', c_t, (1, 0, 0), ctr - Vector((0.0, 1.5, 0.0)), smooth=False)
            mb.fp([b00, b01, b11, b10], 'paint', c_b, (1, 0, 0), ctr + Vector((0.0, 1.5, 0.0)), smooth=False)
            if iv == 0:
                mb.fp([b00, b10, t10, t00], 'paint', mul(c_t, 0.78), (1, 0, 0), ctr + Vector((0.0, 0.0, 1.0)))
            if iv == nv - 1:
                mb.fp([b11, b01, t01, t11], 'paint', mul(c_t, 0.78), (1, 0, 0), ctr - Vector((0.0, 0.0, 1.0)))
            if iu == 0:
                mb.fp([b01, b00, t00, t01], 'paint', mul(c_t, 0.78), (0, 0, 1), ctr + Vector((1.0, 0.0, 0.0)))
            if iu == nu - 1:
                mb.fp([b10, b11, t11, t10], 'paint', mul(c_t, 0.78), (0, 0, 1), ctr - Vector((1.0, 0.0, 0.0)))

    # 4 Taut Guy Ropes Anchored to Driven Wooden Stakes around the 6.4 m x 5.0 m Bedding Skirt!
    for p_top, s_gnd in (
        (p_fl, Vector((-3.06, 0.10, -2.26))),
        (p_fr, Vector(( 3.08, 0.10, -2.18))),
        (p_bl, Vector((-2.98, 0.10,  2.30))),
        (p_br, Vector(( 2.98, 0.10,  2.26))),
    ):
        out_v = Vector((s_gnd.x - p_top.x, 0.0, s_gnd.z - p_top.z)).normalized()
        st_b = s_gnd - out_v * 0.18 + Vector((0.0, -0.85, 0.0))
        st_t = s_gnd + out_v * 0.12 + Vector((0.0,  0.40, 0.0))
        st_tie = st_b.lerp(st_t, 0.84)
        tube(mb, [st_b, st_t], [0.044, 0.040], 4, 'timber', C_TIMBER_MID, mode='flat')
        guy = [p_top.lerp(st_tie, k / 2.0) - Vector((0.0, 0.05 * 4.0 * (k / 2.0) * (1.0 - k / 2.0), 0.0))
               for k in range(3)]
        tube(mb, guy, 0.022, 4, 'rope', jit(C_ROPE, rng, 0.04), mode='smooth')

    # 3. Packed Contraband Hoard Beneath the Tarpaulin!
    #    A. Two Ornate Iron-Banded Wooden Treasure Chests (front hero chest cracked ajar spilling gold!)
    _build_treasure_chest(
        mb, T(-0.48, DECK_Y - 0.01, -0.52) @ R('Y', 16.0),
        open_deg=32.0, rng=rng, spill_gold=True,
    )
    _build_treasure_chest(
        mb, T(-1.28, DECK_Y - 0.01, 0.56) @ R('Y', -22.0),
        open_deg=0.0, rng=rng, spill_gold=False,
    )
    with xf(mb, T(-1.28, DECK_Y + 0.86, 0.56)):
        torus(mb, 0.22, 0.036, 6, 4, 'rope', C_ROPE, True)

    #    B. Three Tall Coopered Wine Casks (2 upright starboard + 1 horizontal on cradle chocks!)
    cask_lan_x, cask_lan_z = 1.62, -0.32
    cask_h = 1.08
    _build_coopered_barrel(
        mb, T(cask_lan_x, DECK_Y + cask_h * 0.5 - 0.02, cask_lan_z) @ R('Y', 18.0),
        radius=0.34, height=cask_h, rng=rng,
        col_a=C_WINE_STAVE, col_b=C_TIMBER_MID, segs=6, n_hoops=4,
    )
    _build_coopered_barrel(
        mb, T(1.18, DECK_Y + 0.54, 0.44) @ R('Y', -30.0) @ R('Z', 2.0),
        radius=0.35, height=1.12, rng=rng,
        col_a=C_TIMBER_MID, col_b=C_WINE_STAVE, segs=6, n_hoops=4,
    )
    with xf(mb, T(0.24, DECK_Y, 0.78) @ R('Y', -14.0)):
        for cz_c in (-0.26, 0.26):
            cbox(mb, (0.0, 0.14, cz_c), (0.64, 0.28, 0.12), 'timber', C_TIMBER_DARK, 0.0)
    _build_coopered_barrel(
        mb, T(0.24, DECK_Y + 0.48, 0.78) @ R('Y', -14.0) @ R('X', 90.0),
        radius=0.34, height=1.02, rng=rng,
        col_a=C_WINE_STAVE, col_b=C_TIMBER_HI, segs=6, spigot=True, n_hoops=2,
    )

    #    C. Two Crimson-Painted Powder Kegs ('paint' + 'iron' hoops + cream warning bands!)
    _build_coopered_barrel(
        mb, T(0.76, DECK_Y + 0.32, -0.78) @ R('Y', -12.0),
        radius=0.27, height=0.66, rng=rng,
        mat_body='paint', col_a=C_PAINT_RED, col_b=mul(C_PAINT_RED, 0.86),
        col_head=C_TIMBER_DARK, segs=6, stripe_col=C_PAINT_CREAM, n_hoops=2,
    )
    _build_coopered_barrel(
        mb, T(1.38, DECK_Y + 0.31, -1.10) @ R('Y', 26.0) @ R('Z', -4.0),
        radius=0.26, height=0.64, rng=rng,
        mat_body='paint', col_a=C_PAINT_RED, col_b=mul(C_PAINT_RED, 0.84),
        col_head=C_TIMBER_DARK, segs=6, stripe_col=C_PAINT_CREAM, n_hoops=2,
    )

    #    D. Coiled Heavy Forged-Iron Anchor Chain heaped on front-left corner of driftwood deck!
    chain_cx, chain_cz = -1.78, -0.88
    for layer, (n_l, rad_c) in enumerate(((4, 0.38), (2, 0.18))):
        ly = DECK_Y + 0.065 + layer * 0.105
        for k in range(n_l):
            ang = 2.0 * pi * k / float(n_l) + layer * 0.75
            px = chain_cx + cos(ang) * rad_c
            pz = chain_cz + sin(ang) * rad_c
            col_c = C_IRON_RUST if (k + layer) % 2 == 0 else C_IRON
            tilt_x = 14.0 if (k % 2 == 0) else 66.0
            with xf(mb, T(px, ly, pz) @ R('Y', -degrees(ang)) @ R('X', tilt_x) @ S(0.86, 1.32, 0.86)):
                torus(mb, 0.135, 0.036, 6, 4, 'iron', col_c, False)
    _add_chain_links(
        mb,
        Vector((chain_cx + 0.32, DECK_Y + 0.06, chain_cz - 0.34)),
        Vector((chain_cx + 0.70, DECK_Y + 0.03, chain_cz - 0.80)),
        n_links=2, link_r=0.108, wire_r=0.030,
    )

    # 4. Warm Brass Hurricane Lantern Sitting Atop Front-Starboard Wine Cask + 'Lantern_Hoard' Empty!
    lan_base_y = DECK_Y + cask_h - 0.02
    lan_scale = 1.12
    lantern_pos = (cask_lan_x, lan_base_y + 0.24 * lan_scale, cask_lan_z)
    with xf(mb, T(cask_lan_x, lan_base_y, cask_lan_z)):
        cyl(mb, 0.21 * lan_scale, 0.0, 0.06 * lan_scale, 6, 'brass', C_TEMPLE_GOLD, False, 0.0, 0.16 * lan_scale)
    build_lantern_geom(mb, lantern_pos, scale=lan_scale, hanging=False)
    with xf(mb, T(lantern_pos) @ T(0.0, 0.16 * lan_scale, 0.0) @ R('Y', 24.0)):
        bail_pts = [
            Vector((-0.18 * lan_scale, 0.0, 0.0)),
            Vector((-0.15 * lan_scale, 0.24 * lan_scale, 0.0)),
            Vector(( 0.00,             0.30 * lan_scale, 0.0)),
            Vector(( 0.15 * lan_scale, 0.24 * lan_scale, 0.0)),
            Vector(( 0.18 * lan_scale, 0.0, 0.0)),
        ]
        tube(mb, bail_pts, 0.015 * lan_scale, 4, 'brass', C_BRASS, mode='flat')

    build(mb)

    add_empty('Lantern_Hoard', lantern_pos)
    col_piece('col_hoard_stack', col_pts)
    export_landmark_glb(outdir, 'smuggler_contraband_hoard.glb')


HARBOUR_RUINS_GENERATORS = [
    gen_harbour_cargo_crane_dock,
    gen_overgrown_jungle_idol_altar,
    gen_cliffside_waterfall_shrine,
    gen_smuggler_contraband_hoard,
]
