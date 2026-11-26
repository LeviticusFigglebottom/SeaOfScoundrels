# Sea of Scoundrels: 4 sculpted 3D On-Foot Trail & Cove Architecture landmarks (Wave I-10).
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
    C_SKULL_BONE, C_SKULL_MID, C_SKULL_SHADE, C_SKULL_EYE,
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

C_GOLD_BRIGHT  = srgb('#f6c948')
C_BRASS_DARK   = srgb('#9b7024')
C_OAK_FRESH    = srgb('#c68d52')
C_CRIMSON_HI   = srgb('#cc3226')
C_CRIMSON_DEEP = srgb('#781814')
C_TEAL_BRIGHT  = srgb('#26949a')
C_RUNE_CORE    = srgb('#46ffe0')
C_RUNE_MID     = srgb('#16d6bc')
C_RUNE_DEEP    = srgb('#0c8278')
C_BARNACLE_HI  = srgb('#e6dec8')
C_BARNACLE_MID = srgb('#b5ab92')
C_KELP_DARK    = srgb('#154c2a')
C_KELP_MID     = srgb('#287a3c')
C_KELP_SUN     = srgb('#66ad32')
C_VINE_DARK    = srgb('#13461a')
C_VINE_MID     = srgb('#276c20')
C_VINE_SUN     = srgb('#6eb224')
C_FERN_DARK    = srgb('#144a1c')
C_FERN_MID     = srgb('#2a7622')
C_FERN_TIP     = srgb('#78ba28')
C_WINE_STAVE   = srgb('#64321e')


def _box2(mb, lo, hi, mat, col, ch=0.0, grain=None, skip=()):
    c = ((lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5, (lo[2] + hi[2]) * 0.5)
    sz = (hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2])
    cbox(mb, c, sz, mat, col, ch, grain, skip=skip)


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


def _rect_oct(cx, y, cz, hx, hz, ch=0.28):
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
            face_col = jit(col_i, rng, 0.04, 0.015)
            mb.fp([p00, p01, p11, p10], mat, face_col, grain=horiz, inside=c_mid, smooth=False)
    if caps[0] and n > 1:
        mb.fp(secs[0], mat, mul(scols[0], 0.72), (1, 0, 0), cents[1], smooth=False)
    if caps[1] and n > 1:
        tmat = top_mat if top_mat is not None else mat
        tcol = top_col if top_col is not None else scols[-1]
        mb.fp(secs[-1], tmat, tcol, (1, 0, 0), cents[-2], smooth=False)


def _build_trail_lantern(mb, center, scale=1.0, brass_body=True):
    """Chunky Sea-of-Thieves brass/iron coastal trail & harbour lantern with glowing amber glass core."""
    cx, cy, cz = center
    s = scale
    cap_mat = 'brass' if brass_body else 'iron'
    cap_col = C_GOLD_BRIGHT if brass_body else C_IRON
    rib_col = C_TEMPLE_GOLD if brass_body else C_BRASS
    with xf(mb, T(cx, cy, cz)):
        cyl(mb, 0.14 * s, -0.24 * s, -0.15 * s, 6, cap_mat, cap_col, False, 0.0, 0.175 * s)
        cyl(mb, 0.21 * s,  0.15 * s,  0.26 * s, 6, cap_mat, cap_col, False, 0.0, 0.065 * s)
        cyl(mb, 0.065 * s, 0.26 * s,  0.34 * s, 6, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.032 * s)
        cyl(mb, 0.125 * s, -0.15 * s, 0.15 * s, 6, 'glass', C_LANTERN_GL, False, 0.0, 0.138 * s)
        for k in range(4):
            ang = k * pi * 0.5 + pi * 0.25
            cbox(mb, (0.154 * s * cos(ang), 0.0, 0.154 * s * sin(ang)),
                 (0.028 * s, 0.31 * s, 0.028 * s), 'brass', rib_col, 0.0)
        with xf(mb, T(0.0, 0.37 * s, 0.0) @ M_Y2Z):
            torus(mb, 0.056 * s, 0.015 * s, 6, 4, 'iron', C_IRON, False)


def _build_lean_rope_coil(mb, center, radius=0.34, turns=3, r=0.046, segs=6, psegs=4):
    """Chunky coiled braided deck rope / pull-rope pile ('rope')."""
    for i in range(turns):
        rr = radius * (1.0 - 0.22 * i)
        with xf(mb, T(center[0], center[1] + r * (1.0 + i * 1.65), center[2])):
            torus(mb, rr, r, segs, psegs, 'rope', mul(C_ROPE, 0.88 + 0.12 * (i % 2)), True)


def _build_coopered_barrel(mb, M_bar, radius=0.34, height=0.88, rng=None,
                           col_a=C_TIMBER_MID, col_b=C_TIMBER_HI, col_head=C_TIMBER_DARK,
                           segs=6, stripe_col=None, spigot=False):
    """Chunky coopered pirate rum barrel with forged iron hoops & optional painted band/spigot."""
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
        jit(col_a if k % 2 == 0 else col_b, rng, 0.08, 0.02) if rng else col_a
        for k in range(segs)
    ]
    with xf(mb, M_bar):
        lathe(mb, prof, segs, 'timber', col_a, False, False,
              lambda i, k: col_head if i in (0, 5) else stave_cols[k])
        for hi_idx, (hy, hr) in enumerate(((-hh * 0.68, radius * 0.94), (hh * 0.68, radius * 0.94))):
            cyl(mb, hr, hy - 0.028, hy + 0.028, segs, 'iron',
                C_IRON_RUST if hi_idx == 1 else C_IRON, False, 0.0)
        if stripe_col is not None:
            cyl(mb, radius * 1.015, -hh * 0.18, hh * 0.18, segs, 'paint', stripe_col, False, 0.0)
        if spigot:
            with xf(mb, T(0.0, -hh * 0.44, -radius * 0.92) @ M_Y2Z):
                cyl(mb, 0.032, -0.02, 0.15, 5, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.020)
            cbox(mb, (0.0, -hh * 0.44 + 0.048, -radius - 0.072), (0.095, 0.026, 0.026), 'brass', C_GOLD_BRIGHT, 0.0)


def _build_supply_crate(mb, M_crate, size=(0.94, 0.78, 0.82), rng=None, stripe_col=C_TEAL_BRIGHT):
    """Chunky weathered pirate supply crate with outer timber battens, iron corner straps & painted stripe."""
    sx, sy, sz = size
    hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
    with xf(mb, M_crate):
        cbox(mb, (0.0, 0.0, 0.0), (sx, sy, sz), 'timber',
             jit(C_TIMBER_MID, rng, 0.05) if rng else C_TIMBER_MID, 0.0, (1, 0, 0))
        for ys in (-hy + 0.055, hy - 0.055):
            for zs in (-hz - 0.016, hz + 0.016):
                cbox(mb, (0.0, ys, zs), (sx + 0.06, 0.10, 0.055), 'timber', C_TIMBER_HI, 0.0, (1, 0, 0))
            for xs in (-hx - 0.016, hx + 0.016):
                cbox(mb, (xs, ys, 0.0), (0.055, 0.10, sz + 0.02), 'timber', C_TIMBER_HI, 0.0, (0, 0, 1))
        for xs in (-hx - 0.016, hx + 0.016):
            for zs in (-hz - 0.016, hz + 0.016):
                cbox(mb, (xs, 0.0, zs), (0.068, sy - 0.14, 0.068), 'timber', C_TIMBER_DARK, 0.0, (0, 1, 0))
                for yc in (-hy + 0.055, hy - 0.055):
                    cbox(mb, (xs * 1.02, yc, zs * 1.02), (0.105, 0.115, 0.105), 'iron', C_IRON, 0.0)
        for zs in (-hz - 0.020, hz + 0.020):
            _add_beam(mb, (-hx + 0.10, -hy + 0.10, zs), (hx - 0.10, hy - 0.10, zs),
                      0.085, 0.036, 'timber', C_OAK_FRESH, 0.0)
        if stripe_col is not None:
            for zs in (-hz - 0.026, hz + 0.026):
                cbox(mb, (0.0, 0.0, zs), (sx * 0.72, 0.16, 0.020), 'paint', stripe_col, 0.0)
            for xs in (-hx - 0.026, hx + 0.026):
                cbox(mb, (xs, 0.0, 0.0), (0.020, 0.16, sz * 0.72), 'paint', stripe_col, 0.0)


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
        sway = sin(t * 3.4 + phase * 6.28) * 0.16 * (0.2 + 0.8 * t)
        out_off = 0.04 + 0.13 * sin(t * pi * 0.78) + 0.07 * t
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
        l_len = width * 1.46 * l_scale * rng.uniform(0.86, 1.16)
        l_wid = width * 0.62 * l_scale * rng.uniform(0.86, 1.14)
        l_dir = (side * (sgn * 0.66) + od * (0.48 + rng.uniform(-0.10, 0.16)) + Vector((0.0, -0.76, 0.0))).normalized()
        l_perp = l_dir.cross(od)
        l_perp = l_perp.normalized() if l_perp.length > 1e-4 else side

        p_base  = root
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


def _add_kelp_drape(mb, anchor, length, width, out_dir, rng, phase=0.0, segs=4):
    """Graceful sinuous coastal sea-kelp twin-frond drape ('foliage') with UV2 wind weights (0 root -> 0.96 tip)."""
    a = Vector(anchor)
    od = Vector((out_dir[0], 0.0, out_dir[2]))
    if od.length < 1e-4:
        od = Vector((0.0, 0.0, -1.0))
    od.normalize()
    side = Vector((-od.z, 0.0, od.x))

    for l_mul, w_mul, s_shift, ph_off in ((1.0, 1.0, 0.0, 0.0), (0.72, 0.72, 0.16, 0.37)):
        prev_l = prev_r = None
        f_len = length * l_mul
        f_w = width * w_mul
        f_ph = (phase + ph_off) % 1.0
        for i in range(segs + 1):
            t = i / float(segs)
            w = f_w * (0.48 + 0.68 * sin(t * pi * 0.86)) * (1.0 - 0.64 * (t ** 1.25))
            sway = sin(t * 4.2 + f_ph * 6.28) * 0.24 * (0.18 + 0.82 * t) + s_shift * (0.4 + 0.6 * t)
            flutter = cos(t * 3.1 + f_ph * 5.2) * 0.11 * t
            ctr = a + od * (0.06 + 0.30 * sin(t * pi * 0.65) + 0.14 * t + flutter) + side * sway + Vector((0.0, -f_len * t, 0.0))
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


def _add_jungle_fern_cluster(mb, root_pos, scale=1.0, n_fronds=4, rng=None, phase=0.0, lean_dir=None):
    """Lush broad tropical jungle fern rosette ('foliage') with UV2 wind weights (0 root -> 0.92 tip)."""
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


def _build_double_sided_streamer(mb, root_pos, length=1.85, h0=0.46, out_dir=(-0.78, 0.0, -0.62),
                                 col_main=C_PAINT_RED, col_trim=C_PAINT_CREAM):
    """Fluttering 3D double-sided tattered swallowtail pennant ribbon (100% backface-cull safe!)."""
    rp = Vector(root_pos)
    od = Vector(out_dir).normalized()
    side = Vector((-od.z, 0.0, od.x))
    if side.length < 1e-4:
        side = Vector((1.0, 0.0, 0.0))
    side.normalize()
    segs = 5
    thick = 0.015

    top_pts = []
    bot_pts = []
    for i in range(segs + 1):
        t = i / float(segs)
        wave = sin(t * 2.35 * pi) * 0.22 * t + 0.04 * sin(t * 4.5)
        droop = -0.24 * t * t
        hh = h0 * (1.0 - 0.56 * t)
        if i == 3:
            hh *= 0.80
        ctr = rp + od * (length * t) + side * wave + Vector((0.0, droop, 0.0))
        top_pts.append(ctr + Vector((0.0, hh * 0.5, 0.0)))
        bot_pts.append(ctr - Vector((0.0, hh * 0.5, 0.0)))

    for i in range(segs):
        c_seg = col_trim if i == 0 else (C_CRIMSON_HI if i % 2 == 1 else col_main)
        t0, t1 = top_pts[i], top_pts[i + 1]
        b0, b1 = bot_pts[i], bot_pts[i + 1]
        if i == segs - 1:
            mid_notch = (t0 + b0) * 0.26 + (t1 + b1) * 0.24 - od * (length * 0.16)
            for tri in ([t0, t1, mid_notch], [b0, mid_notch, b1], [t0, mid_notch, b0]):
                f_pts = [p + side * thick for p in tri]
                b_pts = [p - side * thick for p in reversed(tri)]
                ctr_tri = sum(tri, Vector()) / 3.0
                mb.fp(f_pts, 'paint', c_seg, od, ctr_tri - side * 1.0, smooth=False)
                mb.fp(b_pts, 'paint', mul(c_seg, 0.84), od, ctr_tri + side * 1.0, smooth=False)
        else:
            q_f = [t0 + side * thick, t1 + side * thick, b1 + side * thick, b0 + side * thick]
            q_b = [t1 - side * thick, t0 - side * thick, b0 - side * thick, b1 - side * thick]
            ctr_q = (t0 + t1 + b0 + b1) * 0.25
            mb.fp(q_f, 'paint', c_seg, od, ctr_q - side * 1.0, smooth=False)
            mb.fp(q_b, 'paint', mul(c_seg, 0.84), od, ctr_q + side * 1.0, smooth=False)
            mb.fp([t0 - side * thick, t1 - side * thick, t1 + side * thick, t0 + side * thick],
                  'paint', mul(c_seg, 0.78), od, ctr_q, smooth=False)
            mb.fp([b0 + side * thick, b1 + side * thick, b1 - side * thick, b0 - side * thick],
                  'paint', mul(c_seg, 0.74), od, ctr_q, smooth=False)


# ================================================================ 1. WOODEN TRAIL FOOTBRIDGE

def gen_wooden_trail_footbridge(outdir):
    """Charming gently arched weathered oak trail footbridge (~10.4 m long along local Z,
    3.8 m wide along X, heavy battered stone-and-timber abutment piers at both ends sinking
    cleanly to y = -3.45 m anti-float!).
    Chunky slightly varied transverse deck planks, arched heavy timber stringer beams & lower
    arch ribs with forged iron strap plates, notched handrail posts & taut 'rope' lashings,
    draping 'foliage' moss vines (UV2 wind!), and an arched shepherd's-crook lantern post at
    the bridge crest holding a glowing brass trail lantern ('Lantern_Footbridge' empty!).
    Target: 2,800-3,800 visual tris, 3 colliders (col_bridge_deck, col_bridge_left, col_bridge_right)
    keeping the center walkway 100% open & smoothly walkable!
    """
    clear_scene()
    rng = random.Random(SEED + 1601)
    mb = MB('WoodenTrailFootbridge', seed=1601)

    ABUT_BOT = -3.45
    HALF_L = 5.20
    ARCH_RISE = 0.96

    def deck_y(z):
        u = max(-1.0, min(1.0, z / HALF_L))
        return 0.04 + ARCH_RISE * cos(u * pi * 0.5)

    def deck_pitch_deg(z):
        u = max(-1.0, min(1.0, z / HALF_L))
        dydz = -ARCH_RISE * (pi * 0.5 / HALF_L) * sin(u * pi * 0.5)
        return degrees(atan2(dydz, 1.0))

    deck_col_pts = []
    left_col_pts = []
    right_col_pts = []

    # 1. Heavy Battered Stone-and-Timber Abutment Piers at BOTH Ends (z = +/-4.58 m, plunging to y = -3.45 m!)
    for sgn_z in (-1.0, 1.0):
        az = sgn_z * 4.58
        top_y = deck_y(sgn_z * 4.35) - 0.14
        abut_secs = [
            _rect_oct(0.0, ABUT_BOT, az, 2.22, 0.94, 0.28),
            _rect_oct(0.0, -1.55,    az, 2.06, 0.82, 0.24),
            _rect_oct(0.0,  top_y,   az, 1.88, 0.66, 0.18),
        ]
        abut_cols = [
            mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.62),
            mix(C_TEMPLE_MID,  C_LEDGE_MOSS, 0.28),
            C_TEMPLE_HI,
        ]
        _loft_horizontal_masonry(
            mb, abut_secs, 'temple_stone', abut_cols, rng, caps=(True, True),
            top_mat='limestone_moss', top_col=mix(C_TEMPLE_MID, C_LEDGE_MOSS, 0.36),
        )
        for ring in abut_secs:
            deck_col_pts.extend(Vector(p) for p in ring)

        # Heavy oak abutment sill beam seated cleanly atop the masonry shelf + iron anchor plates
        cbox(mb, (0.0, top_y + 0.12, sgn_z * 4.18), (3.76, 0.24, 0.32), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
        for sx_p in (-1.62, 1.62):
            cbox(mb, (sx_p, top_y + 0.12, sgn_z * 4.18), (0.34, 0.28, 0.38), 'iron', C_IRON, 0.0)
            tube(mb, [
                (sx_p * 1.12, ABUT_BOT,     sgn_z * 3.92),
                (sx_p * 1.04, top_y + 0.16, sgn_z * 3.92),
            ], [0.20, 0.16], 5, 'timber', C_TIMBER_DARK, mode='flat',
                scols=[mix(C_TIMBER_DARK, C_SEA_MOSS, 0.54), C_DRIFTWOOD])

        # Flanking low battered stone wing-wall entry cheeks (keeping center walkway x = -1.62..+1.62 open!)
        for sx_w in (-1.0, 1.0):
            wx = sx_w * 1.88
            _box2(mb, (wx - 0.34, ABUT_BOT, az - 0.56), (wx + 0.34, top_y + 0.72, az + 0.56),
                  'temple_stone', jit(C_TEMPLE_MID, rng, 0.04), 0.0, (0, 0, 1))
            cbox(mb, (wx, top_y + 0.80, az), (0.78, 0.18, 1.24), 'limestone_moss',
                 jit(mix(C_TEMPLE_HI, C_LEDGE_MOSS, 0.32), rng, 0.04), 0.0, (0, 0, 1))
            sculpt_rock_mass(
                mb, (sx_w * 2.24, -0.52, sgn_z * 4.70), (0.64, 1.02, 0.74), 'limestone_moss',
                C_LEDGE_MOSS, C_LIME_WARM, C_LIME_DARK, rng,
                subdiv=1, warp=0.18, strata=0.10, base_flare=0.35,
                rot_deg=(4 * sgn_z, 25 * sx_w, -4 * sx_w), moss_cap=0.72,
            )

        # Gentle stone-and-timber trail approach apron bridging cleanly to y = 0.0 at z = +/-5.20 m
        _box2(mb, (-1.68, ABUT_BOT, sgn_z * 5.20 - 0.34), (1.68, 0.06, sgn_z * 5.20 + 0.34),
              'temple_stone', mix(C_TEMPLE_MID, C_SEA_MOSS, 0.35), 0.0, (1, 0, 0))

    # 2. Arched Heavy Timber Stringer Beams + Lower Curved Arch Ribs + Iron Strap Plates!
    n_arc = 6
    for sx_s, sw, sh, scol in (
        (-1.46, 0.24, 0.28, C_TIMBER_DARK),
        ( 0.00, 0.24, 0.24, C_TIMBER_MID),
        ( 1.46, 0.24, 0.28, C_TIMBER_DARK),
    ):
        secs_s = []
        scols_s = []
        for i in range(n_arc + 1):
            u = -1.0 + 2.0 * (i / float(n_arc))
            zz = u * 4.85
            yy = deck_y(zz) - 0.19
            secs_s.append([
                (sx_s - sw * 0.5, yy - sh * 0.5, zz),
                (sx_s + sw * 0.5, yy - sh * 0.5, zz),
                (sx_s + sw * 0.5, yy + sh * 0.5, zz),
                (sx_s - sw * 0.5, yy + sh * 0.5, zz),
            ])
            scols_s.append(jit(scol, rng, 0.05))
        loft(mb, secs_s, 'timber', scol, closed=True, caps=(True, True), mode='flat', scols=scols_s)

    # Lower parabolic under-arch oak ribs springing from stone abutment haunches
    for sx_r in (-1.46, 1.46):
        secs_r = []
        scols_r = []
        for i in range(n_arc + 1):
            u = -1.0 + 2.0 * (i / float(n_arc))
            zz = u * 4.10
            yy = -0.62 + 1.18 * (1.0 - u * u)
            secs_r.append([
                (sx_r - 0.13, yy - 0.14, zz),
                (sx_r + 0.13, yy - 0.14, zz),
                (sx_r + 0.13, yy + 0.14, zz),
                (sx_r - 0.13, yy + 0.14, zz),
            ])
            scols_r.append(jit(C_TIMBER_MID if abs(u) < 0.5 else C_TIMBER_DARK, rng, 0.05))
        loft(mb, secs_r, 'timber', C_TIMBER_DARK, closed=True, caps=(True, True), mode='flat', scols=scols_r)

        # Forged-iron reinforcement strap plates & vertical arch struts tying stringers to lower ribs!
        for tz_st in (-3.05, -1.55, 0.0, 1.55, 3.05):
            u_st = tz_st / 4.10
            y_rib = -0.62 + 1.18 * (1.0 - u_st * u_st)
            y_str = deck_y(tz_st) - 0.19
            if abs(tz_st) > 0.5:
                _add_beam(mb, (sx_r, y_rib, tz_st), (sx_r, y_str, tz_st), 0.16, 0.16, 'timber', C_TIMBER_DARK, 0.0)
            pdeg = deck_pitch_deg(tz_st)
            with xf(mb, T(sx_r, y_str, tz_st) @ R('X', -pdeg)):
                cbox(mb, (0.0, 0.0, 0.0), (0.31, 0.34, 0.18), 'iron',
                     C_IRON_RUST if int(abs(tz_st)) % 2 == 1 else C_IRON, 0.0)
            with xf(mb, T(sx_r, y_rib, tz_st)):
                cbox(mb, (0.0, 0.0, 0.0), (0.32, 0.32, 0.16), 'iron', C_IRON, 0.0)

    # Under-deck transverse tie joists bracing the 3 stringers
    for jz in (-3.15, -1.55, 0.0, 1.55, 3.15):
        cbox(mb, (0.0, deck_y(jz) - 0.24, jz), (3.32, 0.16, 0.18), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))

    # 3. Chunky Slightly Varied Transverse Oak Deck Planks (20 chunky planks spanning x = -1.78..+1.78 m!)
    n_planks = 20
    plank_palette = (C_TIMBER_HI, C_TIMBER_MID, C_DRIFTWOOD, C_OAK_FRESH)
    for pi_d in range(n_planks):
        t = pi_d / float(n_planks - 1)
        pz = -4.90 + t * 9.80
        py = deck_y(pz)
        pdeg = deck_pitch_deg(pz)
        pw = 3.54 + rng.uniform(-0.12, 0.12)
        px_off = rng.uniform(-0.04, 0.04)
        pcol = jit(plank_palette[pi_d % 4], rng, 0.08, 0.02)
        M_p = T(px_off, py - 0.035 + rng.uniform(-0.006, 0.006), pz) @ R('X', -pdeg) @ R('Y', rng.uniform(-1.1, 1.1))
        cbox(mb, (0.0, 0.0, 0.0), (pw, 0.10, 0.455), 'timber', pcol, 0.0, (1, 0, 0), M=M_p)
        if pi_d % 5 == 0:
            for nx in (-1.44, 1.44):
                cbox(mb, (nx, py + 0.020, pz), (0.055, 0.020, 0.055), 'iron', C_IRON_RUST, 0.0)
        deck_col_pts.extend([
            Vector((-1.64, py + 0.015, pz)),
            Vector(( 1.64, py + 0.015, pz)),
        ])

    # Rustic timber curb guard rails along port & starboard deck margins
    for sgn_x in (-1.0, 1.0):
        cx_c = sgn_x * 1.66
        for i in range(4):
            z0 = -4.70 + i * (9.40 / 4.0)
            z1 = -4.70 + (i + 1) * (9.40 / 4.0)
            _add_beam(mb, (cx_c, deck_y(z0) + 0.075, z0), (cx_c, deck_y(z1) + 0.075, z1),
                      0.14, 0.13, 'timber', C_TIMBER_DARK, 0.0)

    # 4. Notched Handrail Posts, Arched Oak Top Rails & Taut 'rope' Lashings!
    post_zs = (-4.25, -2.15, 0.00, 2.15, 4.25)
    post_tops = {-1: [], 1: []}
    for sgn_x in (-1, 1):
        px = sgn_x * 1.76
        col_list = left_col_pts if sgn_x < 0 else right_col_pts
        for idx, pz in enumerate(post_zs):
            dy = deck_y(pz)
            is_lantern_post = (sgn_x == 1 and idx == 2)
            ph = 1.20 + (0.08 if idx == 2 else 0.0) + rng.uniform(-0.04, 0.04)
            splay = sgn_x * 0.08
            p_base = Vector((px, dy - 0.34, pz))
            p_top  = Vector((px + splay, dy + ph, pz))
            if not is_lantern_post:
                _add_beam(mb, p_base, p_top, 0.175, 0.175, 'timber',
                          jit(C_TIMBER_MID if idx % 2 == 0 else C_DRIFTWOOD, rng, 0.06), 0.0)
                cbox(mb, p_top + Vector((0.0, 0.045, 0.0)), (0.23, 0.08, 0.23), 'timber', C_TIMBER_HI, 0.0)
                cbox(mb, (px, dy + 0.10, pz), (0.22, 0.16, 0.22), 'iron', C_IRON, 0.0)
                if idx in (0, 4):
                    cbox(mb, (px + splay * 0.72, dy + ph * 0.62, pz), (0.20, 0.16, 0.20),
                         'paint', C_TEAL_BRIGHT if idx == 0 else C_PAINT_RED, 0.0)
            else:
                cbox(mb, (px, dy + 0.12, pz), (0.28, 0.22, 0.28), 'iron', C_IRON, 0.0)

            # Bold chunky braided 'rope' lashing collar wrapping each handrail post!
            with xf(mb, T(px + splay * 0.88, dy + ph - 0.18, pz)):
                torus(mb, 0.122, 0.036, 5, 4, 'rope', C_ROPE, True)
            if idx in (0, 2, 4):
                with xf(mb, T(px + splay * 0.45, dy + 0.56, pz)):
                    torus(mb, 0.118, 0.032, 5, 4, 'rope', mul(C_ROPE, 0.92), True)

            post_tops[sgn_x].append(Vector((px + splay, dy + ph - 0.08, pz)))
            col_list.extend([
                Vector((px - 0.14, dy - 0.20, pz - 0.18)),
                Vector((px + 0.18, dy + ph + 0.12, pz + 0.18)),
            ])

        # Heavy arched oak top handrail + double taut braided 'rope' mid-rails between posts!
        pts = post_tops[sgn_x]
        for i in range(len(pts) - 1):
            p0 = pts[i]
            p1 = pts[i + 1]
            _add_beam(mb, p0, p1, 0.12, 0.105, 'timber',
                      C_TIMBER_HI if i in (1, 2) else C_TIMBER_MID, 0.0)
            for y_off, sag, r_rad in ((-0.34, 0.065, 0.032), (-0.64, 0.055, 0.028)):
                cat = [
                    p0.lerp(p1, k / 3.0) + Vector((0.0, y_off - sag * 4.0 * (k / 3.0) * (1.0 - k / 3.0), 0.0))
                    for k in range(4)
                ]
                tube(mb, cat, r_rad, 3, 'rope', jit(C_ROPE, rng, 0.05), caps=(False, False), mode='smooth')
            if i in (0, 3):
                _add_beam(mb, p0 + Vector((0.0, -0.82, 0.0)), p0.lerp(p1, 0.45) + Vector((0.0, -0.06, 0.0)),
                          0.085, 0.085, 'timber', C_TIMBER_DARK, 0.0)

    # 5. Arched Shepherd's-Crook Timber Lantern Post at Bridge Crest + Glowing Brass Trail Lantern!
    crest_y = deck_y(0.0)
    lp_x = 1.76
    post_curve = [
        (lp_x,        crest_y - 0.48, 0.0),
        (lp_x + 0.08, crest_y + 1.45, 0.0),
        (lp_x + 0.10, crest_y + 2.78, 0.0),
        (lp_x - 0.06, crest_y + 3.38, 0.0),
        (lp_x - 0.62, crest_y + 3.48, 0.0),
    ]
    tube(mb, post_curve, [0.165, 0.148, 0.128, 0.108, 0.084], 6, 'timber', C_TIMBER_MID, mode='flat',
         scols=[C_TIMBER_DARK, C_TIMBER_MID, C_TIMBER_HI, C_TIMBER_MID, C_DRIFTWOOD])
    for by_i in (crest_y + 1.20, crest_y + 2.48):
        with xf(mb, T(lp_x + 0.09, by_i, 0.0)):
            cyl(mb, 0.158, -0.065, 0.065, 6, 'iron', C_IRON, False, 0.0)
    _add_beam(mb, (lp_x + 0.08, crest_y + 2.52, 0.0), (lp_x - 0.38, crest_y + 3.40, 0.0),
              0.065, 0.065, 'iron', C_IRON_RUST, 0.0)
    with xf(mb, T(lp_x - 0.08, crest_y + 3.38, 0.0) @ R('Z', 42.0)):
        torus(mb, 0.130, 0.030, 6, 4, 'rope', C_ROPE, True)
    lantern_pos = Vector((lp_x - 0.62, crest_y + 2.62, 0.0))
    _add_beam(mb, (lp_x - 0.62, crest_y + 3.44, 0.0), lantern_pos + Vector((0.0, 0.44, 0.0)),
              0.036, 0.036, 'iron', C_IRON, 0.0)
    _build_trail_lantern(mb, lantern_pos, scale=1.32, brass_body=True)
    right_col_pts.extend([Vector((lp_x - 0.10, crest_y + 3.55, -0.18)), Vector((lp_x + 0.22, crest_y + 3.55, 0.18))])

    # 6. Draping 'foliage' Moss Vines (UV2 wind!) & Lush Trail Abutment Ferns!
    vine_specs = [
        ((-1.78, deck_y(-2.25) - 0.08, -2.25), 2.15, 0.27, (-1.0, 0.0, -0.15), 0.10),
        ((-1.78, deck_y( 0.55) - 0.10,  0.55), 2.35, 0.28, (-1.0, 0.0,  0.12), 0.31),
        (( 1.78, deck_y(-2.15) - 0.08, -2.15), 2.05, 0.27, ( 1.0, 0.0, -0.15), 0.52),
        (( 1.78, deck_y( 2.25) - 0.08,  2.25), 2.18, 0.27, ( 1.0, 0.0,  0.18), 0.74),
        ((lp_x + 0.08, crest_y + 2.82,  0.04), 1.72, 0.23, ( 0.85, 0.0, 0.52), 0.91),
    ]
    for anc, vlen, vw, vdir, vph in vine_specs:
        _add_leafy_vine_drape(mb, anc, vlen, vw, vdir, rng, phase=vph)
    for fpos, fsc, nf, fph, flean in (
        ((-2.02, 0.12, -4.45), 0.96, 3, 0.14, (-0.8, 0.0, -0.6)),
        (( 2.04, 0.12, -4.50), 0.92, 3, 0.46, ( 0.8, 0.0, -0.6)),
        ((-2.04, 0.12,  4.48), 0.98, 3, 0.72, (-0.8, 0.0,  0.6)),
        (( 2.02, 0.12,  4.42), 0.90, 3, 0.88, ( 0.8, 0.0,  0.6)),
    ):
        _add_jungle_fern_cluster(mb, fpos, scale=fsc, n_fronds=nf, rng=rng, phase=fph, lean_dir=flean)

    build(mb)

    add_empty('Lantern_Footbridge', lantern_pos)
    col_piece('col_bridge_deck', deck_col_pts)
    col_piece('col_bridge_left', left_col_pts)
    col_piece('col_bridge_right', right_col_pts)
    export_landmark_glb(outdir, 'wooden_trail_footbridge.glb')


# ================================================================ 2. COASTAL SMUGGLER JETTY

def gen_coastal_smuggler_jetty(outdir):
    """Atmospheric weathered timber pirate cove landing jetty (~12.0 m long extending seaward
    toward -Z from z = +0.55 m landward butt to z = -11.45 m seaward tip, 3.4 m wide, heavy
    barnacle-encrusted driven pilings plunging deeply to y = -4.85 m anti-float!).
    Crooked planked timber deck with stepped landward beach ramp meeting y = 0.0 at z = 0,
    thick timber mooring bollards wrapped with coiled 'rope' hawsers, stacked coopered rum
    barrels & strapped supply crate at the landward butt, trailing sea kelp ('foliage', UV2 wind!),
    and a tall weathered harbour lantern post at the seaward jetty tip ('Lantern_Jetty' empty!).
    Target: 3,000-4,000 visual tris, 2 colliders (col_jetty_deck, col_jetty_bollard).
    """
    clear_scene()
    rng = random.Random(SEED + 1637)
    mb = MB('CoastalSmugglerJetty', seed=1637)

    PILE_BOT = -4.85
    DECK_Y = 0.92
    RAMP_Z0 = 0.40     # Beach ramp foot at y = 0.0, z ≈ 0 (landward butt!)
    RAMP_Z1 = -1.85    # Top of beach ramp meeting main horizontal jetty deck
    TIP_Z = -11.45     # Seaward jetty tip (-Z seaward matching careening_ship_drydock!)

    deck_col_pts = []
    bollard_col_pts = []

    # 1. Grounded Landward Beach-Butt Stone & Timber Cribbing (z = +0.55..-1.90 m, sinking to y = -4.85 m!)
    butt_secs = [
        _rect_oct(0.0, PILE_BOT, -0.58, 2.08, 1.32, 0.28),
        _rect_oct(0.0, -2.00,    -0.58, 1.92, 1.22, 0.24),
        _rect_oct(0.0,  0.02,    -0.58, 1.76, 1.12, 0.18),
    ]
    _loft_horizontal_masonry(
        mb, butt_secs, 'temple_stone',
        [mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.65), mix(C_TEMPLE_MID, C_SEA_MOSS, 0.30), C_TEMPLE_MID],
        rng, caps=(True, True),
        top_mat='limestone_moss', top_col=mix(C_TEMPLE_MID, C_LEDGE_MOSS, 0.34),
    )
    for ring in butt_secs:
        deck_col_pts.extend(Vector(p) for p in ring)

    # Mossy shore anchor boulders tucked snugly into both landward beach butt flanks!
    for rpos, rrad, rrot in (
        ((-1.78, -0.38,  0.14), (0.86, 1.15, 0.94), ( 5,  22, -6)),
        (( 1.80, -0.36,  0.10), (0.82, 1.08, 0.90), (-4, -28,  5)),
    ):
        sculpt_rock_mass(
            mb, rpos, rrad, 'limestone_moss',
            C_LEDGE_MOSS, C_LIME_WARM, C_LIME_DARK, rng,
            subdiv=1, warp=0.18, strata=0.12, base_flare=0.40, rot_deg=rrot, moss_cap=0.68,
        )

    # Stepped Landward Beach Ramp (y = 0.02 at z = +0.40 climbing smoothly to y = 0.92 at z = -1.85!)
    for sx_rs in (-1.38, 0.0, 1.38):
        _add_beam(mb, (sx_rs, -0.02, RAMP_Z0 + 0.08), (sx_rs, DECK_Y - 0.14, RAMP_Z1 - 0.10),
                  0.18, 0.22, 'timber', C_TIMBER_DARK, 0.0)
    n_ramp = 5
    ramp_slope_deg = degrees(atan2(DECK_Y - 0.02, RAMP_Z0 - RAMP_Z1))
    for ri in range(n_ramp):
        u = (ri + 0.5) / float(n_ramp)
        rz = RAMP_Z0 * (1.0 - u) + RAMP_Z1 * u
        ry = 0.02 * (1.0 - u) + (DECK_Y - 0.03) * u
        rw = 3.40 + rng.uniform(-0.10, 0.10)
        M_rp = T(rng.uniform(-0.03, 0.03), ry, rz) @ R('X', ramp_slope_deg * 0.72) @ R('Y', rng.uniform(-1.0, 1.0))
        cbox(mb, (0.0, 0.0, 0.0), (rw, 0.115, 0.42), 'timber',
             jit(C_DRIFTWOOD if ri % 2 == 0 else C_TIMBER_MID, rng, 0.07), 0.0, (1, 0, 0), M=M_rp)
    deck_col_pts.extend([
        Vector((-1.70, 0.02, RAMP_Z0 + 0.10)),
        Vector(( 1.70, 0.02, RAMP_Z0 + 0.10)),
    ])

    # 2. Heavy Barnacle-Encrusted Driven Pilings Plunging Deeply to y = -4.85 m!
    bent_zs = (-1.92, -4.28, -6.62, -8.98, -11.12)
    piling_specs = []
    for bi, bz in enumerate(bent_zs):
        for sx in (-1.56, 1.56):
            is_lantern = (bi == 4 and sx > 0)
            is_bollard = (
                (bi == 1 and sx < 0)
                or (bi == 2 and sx > 0)
                or (bi == 3 and sx < 0)
                or (bi == 4 and sx < 0)
            )
            if is_lantern:
                py_top = 5.38
            elif is_bollard:
                py_top = DECK_Y + (1.16 if bi == 4 else 0.96) + rng.uniform(-0.04, 0.06)
            else:
                py_top = DECK_Y + (0.62 if bi == 0 else 0.06)
            lx = sx * 0.055
            lz = -0.04 if bi >= 3 else 0.02
            piling_specs.append((sx, bz, py_top, lx, lz, True, is_bollard, is_lantern))
    # Pair of heavy lashed outboard mooring dolphin pilings on port seaward berth!
    piling_specs.append((-1.98, -6.92, DECK_Y + 1.06, -0.10, -0.05, True, True, False))
    piling_specs.append((-1.96, -10.55, DECK_Y + 0.92, -0.12, -0.08, True, True, False))

    for pi_idx, (px, pz, py_top, lx, lz, has_barn, has_moor, is_lan) in enumerate(piling_specs):
        r_bot = 0.23 if not is_lan else 0.25
        r_top = 0.145 if is_lan else (0.19 if has_moor else 0.18)
        tube(mb, [
            (px + lx * 1.4, PILE_BOT, pz + lz * 1.4),
            (px + lx * 0.5, -0.45,    pz + lz * 0.5),
            (px,            py_top,   pz),
        ], [r_bot, 0.21, r_top], 6 if is_lan else 5, 'timber', C_TIMBER_DARK, mode='flat',
            scols=[mix(C_TIMBER_DARK, C_SEA_MOSS, 0.65), mix(C_TIMBER_DARK, C_SEA_MOSS, 0.28), C_DRIFTWOOD])
        deck_col_pts.extend([Vector((px, PILE_BOT, pz)), Vector((px, min(py_top, DECK_Y + 0.04), pz))])

        # Thick mooring bollard iron cap bands + chunky coiled braided 'rope' hawser wraps!
        if has_moor:
            with xf(mb, T(px, py_top - 0.12, pz)):
                cyl(mb, r_top + 0.018, -0.055, 0.055, 5, 'iron', C_IRON_RUST if pi_idx % 2 == 0 else C_IRON, False, 0.0)
            for ri in range(2):
                with xf(mb, T(px, DECK_Y + 0.30 + ri * 0.115, pz)):
                    torus(mb, r_top + 0.048, 0.050, 6, 4, 'rope', mul(C_ROPE, 0.90 + 0.10 * (ri % 2)), True)
        if is_lan:
            for band_y in (DECK_Y + 0.45, DECK_Y + 2.15, 4.95):
                with xf(mb, T(px, band_y, pz)):
                    cyl(mb, 0.205, -0.06, 0.06, 6, 'iron', C_IRON, False, 0.0)
            with xf(mb, T(px, DECK_Y + 0.34, pz)):
                torus(mb, 0.23, 0.048, 6, 4, 'rope', C_ROPE, True)
            bollard_col_pts.extend([
                Vector((px - 0.34, DECK_Y, pz - 0.40)),
                Vector((px + 0.34, py_top + 0.12, pz + 0.40)),
            ])

        # Encrusted pale conical tidal barnacle clusters around the waterline (y = -0.25 .. +0.42 m)!
        if has_barn:
            n_b = 2 if abs(pz) > 5.0 else 1
            for bi_k in range(n_b):
                ba = pi_idx * 1.9 + bi_k * 2.4 + rng.uniform(-0.3, 0.3)
                by_b = rng.uniform(-0.18, 0.42)
                bsz = rng.uniform(0.10, 0.15)
                bx_b = px + cos(ba) * 0.19
                bz_b = pz + sin(ba) * 0.19
                with xf(mb, T(bx_b, by_b, bz_b) @ R('Y', -degrees(ba)) @ R('Z', -70.0)):
                    cyl(mb, bsz, -0.05, bsz * 1.05, 4, 'skull_stone',
                        jit(C_BARNACLE_HI if bi_k == 0 else C_BARNACLE_MID, rng, 0.06),
                        False, 0.0, bsz * 0.42)

    # Heavy Under-Deck Pile Bent Cross-Caps, Diagonal Sway X-Braces & Longitudinal Stringers
    for bz in bent_zs:
        _box2(mb, (-1.82, DECK_Y - 0.30, bz - 0.13), (1.82, DECK_Y - 0.08, bz + 0.13),
              'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
    for bz in (-4.28, -6.62, -8.98, -11.12):
        _add_beam(mb, (-1.56, -0.58, bz), ( 1.56, DECK_Y - 0.24, bz), 0.13, 0.14, 'timber', C_TIMBER_DARK, 0.0)
        _add_beam(mb, ( 1.56, -0.58, bz), (-1.56, DECK_Y - 0.24, bz), 0.13, 0.14, 'timber', C_TIMBER_DARK, 0.0)
    for sx_st in (-1.34, 0.0, 1.34):
        _box2(mb, (sx_st - 0.11, DECK_Y - 0.20, TIP_Z + 0.12), (sx_st + 0.11, DECK_Y - 0.03, RAMP_Z1 + 0.10),
              'timber', C_TIMBER_MID if sx_st == 0.0 else C_TIMBER_DARK, 0.0, (0, 0, 1))

    # 3. Crooked Planked Timber Deck (3.4 m wide, z = -1.85 .. -11.45 m, y = 0.92 m!)
    n_planks = 19
    plank_cols = (C_TIMBER_HI, C_TIMBER_MID, C_DRIFTWOOD, C_OAK_FRESH)
    for pi_d in range(n_planks):
        t = pi_d / float(n_planks - 1)
        pz = RAMP_Z1 - 0.18 + t * (TIP_Z - RAMP_Z1 + 0.36)
        pw = 3.40 + rng.uniform(-0.14, 0.16)
        px_c = rng.uniform(-0.07, 0.07)
        py_c = DECK_Y - 0.035 + rng.uniform(-0.008, 0.008)
        pcol = jit(plank_cols[pi_d % 4], rng, 0.08, 0.02)
        M_p = T(px_c, py_c, pz) @ R('Y', rng.uniform(-1.6, 1.6)) @ R('Z', rng.uniform(-0.5, 0.5))
        cbox(mb, (0.0, 0.0, 0.0), (pw, 0.10, 0.455), 'timber', pcol, 0.0, (1, 0, 0), M=M_p)
    deck_col_pts.extend([
        Vector((-1.72, DECK_Y + 0.015, RAMP_Z1)),
        Vector(( 1.72, DECK_Y + 0.015, RAMP_Z1)),
        Vector((-1.72, DECK_Y + 0.015, TIP_Z)),
        Vector(( 1.72, DECK_Y + 0.015, TIP_Z)),
    ])

    # Weathered timber rub-strake edge curbs & sagging mooring hawsers!
    for sgn_x in (-1.0, 1.0):
        _box2(mb, (sgn_x * 1.62 - 0.07, DECK_Y + 0.01, -10.85), (sgn_x * 1.62 + 0.07, DECK_Y + 0.12, -2.05),
              'timber', C_TIMBER_DARK, 0.0, (0, 0, 1))
    _add_beam(mb, (1.56, DECK_Y + 0.55, -1.92), (1.56, DECK_Y + 0.78, -4.28), 0.10, 0.10, 'timber', C_DRIFTWOOD, 0.0)
    for p0, p1, sag in (
        ((-1.56, DECK_Y + 0.44, -4.28), (-1.98, DECK_Y + 0.50, -6.92), 0.24),
        ((-1.56, DECK_Y + 0.42, -8.98), (-1.56, DECK_Y + 0.48, -11.12), 0.18),
    ):
        a, b = Vector(p0), Vector(p1)
        cat = [a.lerp(b, k / 4.0) + Vector((0.0, -sag * 4.0 * (k / 4.0) * (1.0 - k / 4.0), 0.0)) for k in range(5)]
        tube(mb, cat, 0.036, 4, 'rope', C_ROPE, caps=(False, False), mode='smooth')

    # Heavy deck hawser rope coils resting flush on the jetty planks!
    _build_lean_rope_coil(mb, (-1.08, DECK_Y + 0.015, -10.32), radius=0.36, turns=2, r=0.048, segs=6, psegs=4)
    _build_lean_rope_coil(mb, ( 1.05, DECK_Y + 0.015, -6.28), radius=0.30, turns=2, r=0.042, segs=6, psegs=4)

    # 4. Stacked Coopered Rum Barrels & Strapped Supply Crate at the Landward Butt!
    _build_coopered_barrel(
        mb, T(-1.14, DECK_Y + 0.45, -2.52) @ R('Y', 18.0),
        radius=0.35, height=0.88, rng=rng,
        col_a=C_TIMBER_MID, col_b=C_TIMBER_HI, col_head=C_TIMBER_DARK,
        segs=6, stripe_col=C_PAINT_RED, spigot=True,
    )
    _build_coopered_barrel(
        mb, T(-1.16, DECK_Y + 0.43, -3.32) @ R('Y', -32.0),
        radius=0.33, height=0.84, rng=rng,
        col_a=C_WINE_STAVE, col_b=C_TIMBER_MID, col_head=C_TIMBER_DARK,
        segs=6, stripe_col=None, spigot=False,
    )
    # Horizontal cask nested snugly into the saddle atop the two upright barrels!
    _build_coopered_barrel(
        mb, T(-1.12, DECK_Y + 1.14, -2.92) @ R('Y', 12.0) @ R('X', 90.0),
        radius=0.30, height=0.78, rng=rng,
        col_a=C_OAK_FRESH, col_b=C_TIMBER_MID, col_head=C_TIMBER_DARK,
        segs=6, stripe_col=C_TEAL_BRIGHT, spigot=False,
    )
    _build_supply_crate(
        mb, T(1.06, DECK_Y + 0.40, -2.65) @ R('Y', -14.0),
        size=(0.88, 0.76, 0.80), rng=rng, stripe_col=C_TEAL_BRIGHT,
    )
    _build_lean_rope_coil(mb, (1.06, DECK_Y + 0.79, -2.65), radius=0.24, turns=2, r=0.036, segs=6, psegs=4)

    # 5. Tall Weathered Harbour Lantern Post at the Seaward Jetty Tip (x = +1.56, z = -11.12 m)!
    post_x, post_z = 1.56, -11.12
    post_top_y = 5.38
    arm_root = Vector((post_x, post_top_y - 0.36, post_z))
    arm_tip  = arm_root + Vector((-0.62, 0.14, -0.46))
    _add_beam(mb, arm_root, arm_tip, 0.15, 0.16, 'timber', C_TIMBER_MID, 0.0)
    _add_beam(mb, Vector((post_x, post_top_y - 1.32, post_z)), arm_root.lerp(arm_tip, 0.68),
              0.11, 0.12, 'timber', C_TIMBER_DARK, 0.0)
    with xf(mb, T(post_x - 0.16, DECK_Y + 2.48, post_z - 0.08) @ R('Y', 24.0) @ R('Z', -4.0)):
        cbox(mb, (0.0, 0.0, 0.0), (1.18, 0.36, 0.075), 'timber', C_DRIFTWOOD, 0.0, (1, 0, 0))
        cbox(mb, (0.0, 0.0, -0.050), (0.94, 0.22, 0.024), 'paint', C_PAINT_CREAM, 0.0)
        cbox(mb, (0.0, 0.0, -0.068), (0.28, 0.16, 0.020), 'paint', C_PAINT_RED, 0.0, M=R('Z', 45.0))
    lantern_pos = arm_tip + Vector((0.0, -0.78, 0.0))
    _add_beam(mb, arm_tip + Vector((0.0, -0.04, 0.0)), lantern_pos + Vector((0.0, 0.44, 0.0)),
              0.042, 0.042, 'iron', C_IRON, 0.0)
    _build_trail_lantern(mb, lantern_pos, scale=1.42, brass_body=False)
    bollard_col_pts.append(arm_tip)

    # 6. Trailing Sea Kelp ('foliage', UV2 wind!) draping prominently from under-deck caps + Landward Ferns!
    kelp_specs = [
        ((-1.56, 0.78, -4.28),  2.05, 0.24, (-0.92, 0.0, -0.38), 0.09),
        (( 1.56, 0.76, -6.62),  2.20, 0.25, ( 0.90, 0.0, -0.44), 0.28),
        ((-1.98, 0.80, -6.92),  2.15, 0.24, (-0.85, 0.0, -0.52), 0.47),
        ((-1.56, 0.78, -11.12), 2.25, 0.26, (-0.65, 0.0, -0.76), 0.68),
        (( 1.56, 0.76, -11.12), 2.10, 0.24, ( 0.65, 0.0, -0.76), 0.85),
    ]
    for anc, klen, kw, odir, kph in kelp_specs:
        _add_kelp_drape(mb, anc, klen, kw, odir, rng, phase=kph, segs=4)
    for fpos, fsc, nf, fph, flean in (
        ((-1.86, 0.22, 0.18), 0.96, 3, 0.16, (-0.8, 0.0, 0.6)),
        (( 1.88, 0.20, 0.14), 0.92, 3, 0.58, ( 0.8, 0.0, 0.6)),
    ):
        _add_jungle_fern_cluster(mb, fpos, scale=fsc, n_fronds=nf, rng=rng, phase=fph, lean_dir=flean)

    build(mb)

    add_empty('Lantern_Jetty', lantern_pos)
    col_piece('col_jetty_deck', deck_col_pts)
    col_piece('col_jetty_bollard', bollard_col_pts)
    export_landmark_glb(outdir, 'coastal_smuggler_jetty.glb')


# ================================================================ 3. ANCIENT RUINED OBELISK GATE

def _add_compass_emblem_double(mb, center, scale=1.0, rng=None):
    """Monumental double-sided gleaming 'brass' 8-point ancient compass rose emblem crowning the gate lintel."""
    s = scale
    with xf(mb, T(center)):
        with xf(mb, M_Y2Z):
            torus(mb, 0.88 * s, 0.098 * s, 12, 5, 'brass', C_TEMPLE_GOLD, False)
            torus(mb, 0.52 * s, 0.058 * s, 10, 4, 'brass', C_GOLD_BRIGHT, False)
        for k in range(8):
            is_card = (k % 2 == 0)
            p_len = (1.38 if k == 0 else (1.24 if is_card else 0.96)) * s
            p_w = (0.20 if is_card else 0.13) * s
            p_d = (0.14 if is_card else 0.095) * s
            col_a = C_GOLD_BRIGHT if is_card else C_BRASS
            col_b = C_TEMPLE_GOLD if is_card else C_BRASS_DARK
            with xf(mb, R('Z', k * 45.0)):
                p_in  = Vector((0.0, 0.14 * s, 0.0))
                p_tip = Vector((0.0, p_len,    0.0))
                p_l   = Vector((-p_w, 0.42 * s, 0.0))
                p_r   = Vector(( p_w, 0.42 * s, 0.0))
                p_f   = Vector((0.0, 0.42 * s, -p_d))
                p_b   = Vector((0.0, 0.42 * s,  p_d))
                ctr   = Vector((0.0, 0.48 * s, 0.0))
                for tri, col_f in (
                    ([p_in, p_l, p_f], col_a), ([p_in, p_f, p_r], col_b),
                    ([p_l, p_tip, p_f], col_a), ([p_f, p_tip, p_r], col_b),
                    ([p_in, p_b, p_l], col_b), ([p_in, p_r, p_b], col_a),
                    ([p_b, p_tip, p_l], col_b), ([p_r, p_tip, p_b], col_a),
                ):
                    mb.fp(tri, 'brass', jit(col_f, rng, 0.04) if rng else col_f, (0, 1, 0), ctr, smooth=False)
        with xf(mb, M_Y2Z):
            cyl(mb, 0.28 * s, -0.15 * s, 0.15 * s, 8, 'brass', C_TEMPLE_GOLD, False, 0.0)
            cyl(mb, 0.19 * s, -0.22 * s, 0.22 * s, 8, 'skull_glow', C_RUNE_CORE, False, 0.0)


def _add_runic_medallion(mb, center, face_z_sgn, scale=1.0):
    """Carved stone & brass recessed ancient medallion with glowing turquoise runic diamond ('skull_glow')."""
    s = scale
    sz = face_z_sgn
    with xf(mb, T(center)):
        with xf(mb, M_Y2Z):
            cyl(mb, 0.58 * s, -0.06 * s, 0.08 * s, 8, 'basalt', C_BASALT_DARK, False, 0.0)
            torus(mb, 0.54 * s, 0.064 * s, 8, 4, 'brass', C_TEMPLE_GOLD, False)
        z_out = sz * 0.075 * s
        cbox(mb, (0.0, 0.0, z_out), (0.44 * s, 0.44 * s, 0.06 * s), 'skull_glow', C_RUNE_MID, 0.0, M=R('Z', 45.0))
        cbox(mb, (0.0, 0.0, z_out + sz * 0.03 * s), (0.20 * s, 0.20 * s, 0.05 * s), 'skull_glow', C_RUNE_CORE, 0.0)
        cbox(mb, (0.0, 0.0, z_out + sz * 0.015 * s), (0.66 * s, 0.07 * s, 0.045 * s), 'skull_glow', C_RUNE_DEEP, 0.0)
        cbox(mb, (0.0, 0.0, z_out + sz * 0.015 * s), (0.07 * s, 0.66 * s, 0.045 * s), 'skull_glow', C_RUNE_DEEP, 0.0)


def gen_ancient_ruined_obelisk_gate(outdir):
    """Monumental mossy carved temple-stone twin-pillar trail gateway (~9.6 m wide x 9.8 m tall,
    battered stone plinth footings plunging cleanly to y = -3.85 m anti-float!).
    Twin tapering carved obelisk pylons spaced to keep a generous 4.8 m-wide center archway
    100% open & walkable, bridged by a cracked weathered stone lintel crowned with a gleaming
    'brass' 8-point compass emblem, glowing runic turquoise stone medallions ('skull_glow' +
    'Lantern_ObeliskGate' empty!), cascading 'foliage' leafy ivy drapes (UV2 wind!), and tumbled
    mossy carved stone rubble flanking the bases!
    Target: 3,000-4,000 visual tris, 2 colliders (col_gate_left, col_gate_right).
    """
    clear_scene()
    rng = random.Random(SEED + 1669)
    mb = MB('AncientRuinedObeliskGate', seed=1669)

    PLINTH_BOT = -3.85
    PYLON_X = 3.48  # Inner face stays strictly outside |x| >= 2.42 m -> >4.84 m open clear archway!

    col_pts_side = {-1: [], 1: []}

    # 1. Twin Battered Temple-Stone Plinth Footings & Tapering Carved Obelisk Pylons!
    for sgn in (-1, 1):
        px = sgn * PYLON_X
        c_list = col_pts_side[sgn]

        def _plinth_ring(y, x_in, x_out, hz, ch=0.22):
            xa = min(sgn * x_in, sgn * x_out)
            xb = max(sgn * x_in, sgn * x_out)
            return [
                (xa + ch, y, -hz),
                (xb - ch, y, -hz),
                (xb,      y, -hz + ch),
                (xb,      y,  hz - ch),
                (xb - ch, y,  hz),
                (xa + ch, y,  hz),
                (xa,      y,  hz - ch),
                (xa,      y, -hz + ch),
            ]

        plinth_secs = [
            _plinth_ring(PLINTH_BOT, 2.44, 4.78, 1.56, 0.24),
            _plinth_ring(-1.80,      2.44, 4.64, 1.46, 0.22),
            _plinth_ring( 0.00,      2.44, 4.52, 1.38, 0.20),
            _plinth_ring( 1.08,      2.46, 4.44, 1.32, 0.18),
        ]
        plinth_cols = [
            mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.56),
            mix(C_TEMPLE_MID,  C_SEA_MOSS, 0.36),
            mix(C_TEMPLE_MID,  C_LEDGE_MOSS, 0.24),
            C_TEMPLE_HI,
        ]
        _loft_horizontal_masonry(
            mb, plinth_secs, 'temple_stone', plinth_cols, rng, caps=(True, True),
            top_mat='limestone_moss', top_col=mix(C_TEMPLE_HI, C_LEDGE_MOSS, 0.30),
        )
        for ring in plinth_secs:
            c_list.extend(Vector(p) for p in ring)

        # Stepped plinth collar cap molding (strictly |x| >= 2.43 m)
        cbox(mb, (sgn * 3.46, 1.18, 0.0), (2.06, 0.24, 2.68), 'temple_stone', C_TEMPLE_HI, 0.0, (1, 0, 0))

        # Tapering carved obelisk pylon shaft (cohesive sunlit warm temple-stone gradient!)
        shaft_secs = [
            _rect_oct(px, 1.24, 0.0, 0.98, 1.06, 0.20),
            _rect_oct(px, 3.60, 0.0, 0.88, 0.96, 0.18),
            _rect_oct(px, 5.85, 0.0, 0.78, 0.86, 0.16),
            _rect_oct(px, 7.82, 0.0, 0.68, 0.76, 0.14),
        ]
        _loft_horizontal_masonry(
            mb, shaft_secs, 'temple_stone',
            [mix(C_TEMPLE_MID, C_LEDGE_MOSS, 0.14),
             mix(C_TEMPLE_MID, C_TEMPLE_HI, 0.52),
             C_TEMPLE_HI,
             mix(C_TEMPLE_HI, C_LEDGE_MOSS, 0.18)],
            rng, caps=(False, True),
        )
        for ring in shaft_secs:
            c_list.extend(Vector(p) for p in ring)

        # Horizontal carved string-course cornice bands & corner brass trim accents
        for cy_b, bw, bd, bh, is_brass in (
            (2.58, 2.08, 2.24, 0.22, False),
            (4.78, 1.92, 2.08, 0.22, False),
            (5.78, 2.04, 2.18, 0.26, False),
            (7.72, 1.54, 1.68, 0.24, False),
            (2.68, 1.98, 2.18, 0.07, True),
            (4.88, 1.84, 2.04, 0.07, True),
            (5.90, 1.94, 2.14, 0.07, True),
        ):
            cbox(mb, (px, cy_b, 0.0), (bw, bh, bd),
                 'brass' if is_brass else 'temple_stone',
                 C_TEMPLE_GOLD if is_brass else C_TEMPLE_HI, 0.0, (1, 0, 0))

        # Recessed vertical temple glyph pilasters + glowing turquoise runic medallions on front (-Z) & rear (+Z)!
        for sz in (-1.0, 1.0):
            cbox(mb, (px, 3.68, sz * 1.00), (0.94, 1.92, 0.10), 'temple_stone', C_TEMPLE_DARK, 0.0, (0, 1, 0))
            _add_runic_medallion(mb, (px, 3.68, sz * 1.04), sz, scale=0.88)
            cbox(mb, (px, 5.26, sz * 0.90), (0.34, 0.34, 0.06), 'skull_glow', C_RUNE_MID, 0.0, M=R('Z', 45.0))
            cbox(mb, (px, 5.26, sz * 0.93), (0.16, 0.16, 0.05), 'skull_glow', C_RUNE_CORE, 0.0)
            # Lower carved plinth tablet relief
            cbox(mb, (px, 1.88, sz * 1.05), (0.88, 0.88, 0.08), 'temple_stone', C_TEMPLE_DARK, 0.0)
            cbox(mb, (px, 1.88, sz * 1.10), (0.42, 0.42, 0.04), 'brass', C_BRASS_DARK, 0.0, M=R('Z', 45.0))

        # Inner archway carved glowing runic pilasters facing INTO the open trail passage (strictly |x| >= 2.48 m!)
        in_x = sgn * 2.58
        cbox(mb, (in_x, 3.68, 0.0), (0.10, 1.82, 0.94), 'temple_stone', C_TEMPLE_DARK, 0.0, (0, 1, 0))
        for ry_in in (3.12, 3.68, 4.24):
            cbox(mb, (in_x - sgn * 0.05, ry_in, 0.0), (0.05, 0.24, 0.24), 'skull_glow',
                 C_RUNE_CORE if ry_in == 3.68 else C_RUNE_MID, 0.0, M=R('X', 45.0))

        # Pyramidion Obelisk Crown Finials atop both pylons (y = 7.82 .. 9.05 m; port weathered & chipped!)
        if sgn > 0:
            pyr_secs = [
                _rect_oct(px, 7.82, 0.0, 0.68, 0.76, 0.14),
                _rect_oct(px, 8.62, 0.0, 0.32, 0.36, 0.07),
                _rect_oct(px, 9.02, 0.0, 0.06, 0.06, 0.015),
            ]
            _loft_horizontal_masonry(
                mb, pyr_secs, 'temple_stone', [C_TEMPLE_HI, C_TEMPLE_HI], rng, caps=(False, True),
            )
            with xf(mb, T(px, 8.95, 0.0)):
                cyl(mb, 0.15, 0.0, 0.34, 4, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.02)
            c_list.append(Vector((px, 9.15, 0.0)))
        else:
            pyr_secs = [
                _rect_oct(px, 7.82, 0.0, 0.68, 0.76, 0.14),
                _rect_oct(px - 0.05, 8.48, 0.02, 0.42, 0.46, 0.09),
            ]
            _loft_horizontal_masonry(
                mb, pyr_secs, 'limestone_moss', [C_TEMPLE_MID], rng, caps=(False, True),
                top_mat='limestone_moss', top_col=mix(C_TEMPLE_MID, C_LEDGE_MOSS, 0.48),
            )
            sculpt_stone_block(
                mb, (px - 0.10, 8.64, -0.08), (0.64, 0.42, 0.68), 'temple_stone', C_TEMPLE_HI,
                rng, chip=0.065, M=R('Z', 14.0) @ R('X', -8.0), moss_col=C_LEDGE_MOSS,
            )
            c_list.append(Vector((px, 8.85, 0.0)))

        # Stepped stone soffit corbel bracket supporting the lintel (starts high at y = 5.05 m -> zero obstruction!)
        cbox(mb, (sgn * 2.58, 5.46, 0.0), (0.62, 0.72, 1.56), 'temple_stone', C_TEMPLE_MID, 0.0, (1, 0, 0))
        cbox(mb, (sgn * 2.34, 5.72, 0.0), (0.56, 0.34, 1.48), 'temple_stone', C_TEMPLE_HI, 0.0, (1, 0, 0))

    # 2. Massive Cracked Weathered Stone Lintel Beam Bridging the Twin Pylons (y = 5.85 .. 7.30 m!)
    sculpt_stone_block(
        mb, (-2.04, 6.56, 0.0), (4.76, 1.42, 1.62), 'temple_stone', C_TEMPLE_HI,
        rng, chip=0.065, M=R('Z', 1.2), moss_col=C_LEDGE_MOSS,
    )
    sculpt_stone_block(
        mb, (2.42, 6.52, 0.0), (3.88, 1.38, 1.58), 'temple_stone', C_TEMPLE_MID,
        rng, chip=0.065, M=R('Z', -1.8), moss_col=C_LEDGE_MOSS,
    )
    cbox(mb, (0.42, 6.58, 0.0), (0.16, 1.22, 1.68), 'basalt', C_BASALT_DARK, 0.0, M=R('Z', -14.0))

    # Overhanging carved stone lintel cornice slabs + sculpted dentil frieze blocks!
    cbox(mb, (-1.92, 7.36, 0.0), (4.65, 0.28, 1.94), 'temple_stone', C_TEMPLE_HI, 0.0, (1, 0, 0), M=R('Z', 1.0))
    cbox(mb, ( 2.32, 7.32, 0.0), (3.82, 0.28, 1.90), 'limestone_moss',
         mix(C_TEMPLE_HI, C_LEDGE_MOSS, 0.24), 0.0, (1, 0, 0), M=R('Z', -1.5))
    for sz in (-1.0, 1.0):
        for dx_d in (-3.6, -2.7, -1.8, -0.9, 1.0, 1.9, 2.8, 3.6):
            cbox(mb, (dx_d, 7.16, sz * 0.88), (0.34, 0.24, 0.24), 'temple_stone',
                 C_TEMPLE_HI if int(abs(dx_d)) % 2 == 0 else C_TEMPLE_MID, 0.0)

    # Central stepped pediment keystone & flanking scroll cheeks cradling the gleaming brass compass crown!
    cbox(mb, (0.0, 7.72, 0.0), (2.56, 0.72, 1.54), 'temple_stone', C_TEMPLE_HI, 0.0, (1, 0, 0))
    cbox(mb, (0.0, 8.16, 0.0), (1.82, 0.34, 1.26), 'temple_stone', C_TEMPLE_MID, 0.0, (1, 0, 0))
    for sx_sc in (-1.38, 1.38):
        sculpt_stone_block(
            mb, (sx_sc, 7.72, 0.0), (0.58, 0.62, 1.18), 'temple_stone', C_TEMPLE_MID,
            rng, chip=0.05, M=R('Z', -16.0 if sx_sc < 0 else 16.0), moss_col=C_LEDGE_MOSS,
        )
    # Glowing turquoise center archway keystone rune tablet on BOTH front (-Z) & rear (+Z)!
    for sz in (-1.0, 1.0):
        cbox(mb, (0.0, 6.58, sz * 0.86), (1.42, 0.88, 0.14), 'temple_stone', C_TEMPLE_DARK, 0.0)
        cbox(mb, (0.0, 6.58, sz * 0.94), (1.18, 0.66, 0.06), 'brass', C_TEMPLE_GOLD, 0.0)
        cbox(mb, (0.0, 6.58, sz * 0.98), (0.94, 0.44, 0.05), 'basalt', C_BASALT_DARK, 0.0)
        for rx_r in (-0.28, 0.0, 0.28):
            r_sz = 0.24 if rx_r == 0.0 else 0.16
            cbox(mb, (rx_r, 6.58, sz * 1.02), (r_sz, r_sz, 0.05), 'skull_glow',
                 C_RUNE_CORE if rx_r == 0.0 else C_RUNE_MID, 0.0, M=R('Z', 45.0))

    # 3. Gleaming 'brass' 8-Point Compass Emblem Crowning the Gateway Pediment (peaks cleanly at y ≈ 9.82 m!)
    compass_ctr = Vector((0.0, 8.64, 0.0))
    _add_compass_emblem_double(mb, compass_ctr, scale=0.86, rng=rng)

    # 4. Prominent Tumbled Mossy Carved Stone Rubble Flanking Both Bases (strictly |x| >= 2.6 m -> 4.8 m arch 100% clear!)
    rubble_specs = [
        # Prominent fallen carved lintel slab & broken stone blocks flanking the port (-X) base!
        ((-4.92,  0.34, -0.96), (1.28, 0.82, 0.96), ( 8,  26, -14), 'temple_stone', C_TEMPLE_HI),
        ((-4.86,  0.32,  0.94), (1.18, 0.78, 0.92), (-9, -20,  12), 'limestone_moss', C_TEMPLE_MID),
        ((-4.35,  0.86, -1.28), (0.86, 0.62, 0.74), (14,  38,  -9), 'temple_stone', C_TEMPLE_HI),
        ((-5.22,  0.18,  0.04), (0.96, 0.66, 0.88), (-6,  14,  18), 'temple_stone', C_TEMPLE_MID),
        # Prominent fallen carved stone blocks & tumbled broken column drum flanking the starboard (+X) base!
        (( 4.94,  0.34, -0.92), (1.24, 0.80, 0.94), (-8, -28,  15), 'temple_stone', C_TEMPLE_HI),
        (( 4.78,  0.28,  1.02), (1.12, 0.74, 0.88), (10,  18, -12), 'limestone_moss', C_TEMPLE_MID),
        (( 4.42,  0.82,  1.24), (0.82, 0.58, 0.70), (-12, 42,   7), 'temple_stone', C_TEMPLE_HI),
    ]
    for rpos, rsz, rrot, rmat, rcol in rubble_specs:
        M_rb = R('Y', rrot[1]) @ R('X', rrot[0]) @ R('Z', rrot[2])
        sculpt_stone_block(mb, rpos, rsz, rmat, rcol, rng, chip=0.065, M=M_rb, moss_col=C_LEDGE_MOSS)
        sgn_rb = -1 if rpos[0] < 0 else 1
        col_pts_side[sgn_rb].append(Vector((rpos[0] + sgn_rb * rsz[0] * 0.45, rpos[1] + rsz[1] * 0.45, rpos[2])))
    # Fallen weathered carved obelisk drum lying tilted beside starboard base!
    with xf(mb, T(5.12, 0.34, 0.14) @ R('Y', -32.0) @ R('Z', 82.0)):
        cyl(mb, 0.46, -0.68, 0.68, 7, 'limestone_moss', C_TEMPLE_HI, False, 0.0, 0.40)
    # Grounded mossy rock shoulders burying the outer rubble into sloped terrain
    for sgn in (-1, 1):
        sculpt_rock_mass(
            mb, (sgn * 4.58, -0.56, 0.06), (1.02, 1.38, 1.54), 'limestone_moss',
            C_LEDGE_MOSS, C_LIME_WARM, C_LIME_DARK, rng,
            subdiv=1, warp=0.18, strata=0.12, base_flare=0.42,
            rot_deg=(4, 20 * sgn, -5 * sgn), moss_cap=0.76,
        )

    # 5. Cascading 'foliage' Leafy Ivy Drapes (UV2 wind!) & Lush Base Trail Ferns!
    vine_specs = [
        ((-2.25, 7.22, -0.92), 3.45, 0.31, (-0.18, 0.0, -0.98), 0.06),
        (( 0.48, 7.20, -0.92), 2.25, 0.27, ( 0.08, 0.0, -0.99), 0.18),
        (( 2.28, 7.18, -0.92), 3.25, 0.30, ( 0.16, 0.0, -0.98), 0.31),
        ((-4.22, 8.38, -0.32), 4.15, 0.32, (-0.96, 0.0, -0.26), 0.44),
        (( 4.20, 7.62,  0.28), 3.55, 0.30, ( 0.98, 0.0,  0.20), 0.58),
        ((-2.15, 7.24,  0.92), 3.20, 0.29, (-0.15, 0.0,  0.98), 0.72),
        (( 2.18, 7.20,  0.92), 3.05, 0.29, ( 0.15, 0.0,  0.98), 0.85),
        ((-4.12, 7.55,  0.52), 3.15, 0.28, (-0.85, 0.0,  0.52), 0.94),
    ]
    for anc, vlen, vw, vdir, vph in vine_specs:
        _add_leafy_vine_drape(mb, anc, vlen, vw, vdir, rng, phase=vph)
    for fpos, fsc, nf, fph, flean in (
        ((-4.65, 0.28, -1.24), 1.06, 5, 0.14, (-0.8, 0.0, -0.6)),
        (( 4.68, 0.28, -1.18), 1.02, 5, 0.48, ( 0.8, 0.0, -0.6)),
        ((-4.62, 0.26,  1.28), 1.00, 5, 0.72, (-0.8, 0.0,  0.6)),
        (( 4.65, 0.26,  1.22), 1.00, 5, 0.88, ( 0.8, 0.0,  0.6)),
    ):
        _add_jungle_fern_cluster(mb, fpos, scale=fsc, n_fronds=nf, rng=rng, phase=fph, lean_dir=flean)

    build(mb)

    add_empty('Lantern_ObeliskGate', (0.0, 6.58, 0.0))
    col_piece('col_gate_left',  col_pts_side[-1])
    col_piece('col_gate_right', col_pts_side[1])
    export_landmark_glb(outdir, 'ancient_ruined_obelisk_gate.glb')


# ================================================================ 4. PIRATE LOOKOUT BELL FRAME

def _build_warning_bell(mb, M_bell, radius=0.68, height=1.08, segs=10, clapper_tilt=-12.0):
    """Large gleaming sculpted 'brass' ship's warning bell with flared sound-bow, bands & clapper."""
    hh = height * 0.5
    prof = [
        (0.00,          hh * 1.12),
        (radius * 0.22, hh * 1.06),
        (radius * 0.36, hh * 0.84),
        (radius * 0.50, hh * 0.46),
        (radius * 0.62, 0.00),
        (radius * 0.86, -hh * 0.64),
        (radius * 1.04, -hh * 0.96),
        (radius * 0.96, -hh * 1.04),
        (radius * 0.78, -hh * 0.72),
        (radius * 0.44, hh * 0.30),
        (0.00,          hh * 0.62),
    ]
    with xf(mb, M_bell):
        lathe(mb, prof, segs, 'brass', C_GOLD_BRIGHT, smooth=False,
              colfn=lambda i, k: C_BRASS_DARK if i >= 7 else (C_GOLD_BRIGHT if i in (2, 5, 6) else C_BRASS))
        for by_r, br_r in ((hh * 0.52, radius * 0.49), (-hh * 0.60, radius * 0.86)):
            with xf(mb, T(0.0, by_r, 0.0)):
                torus(mb, br_r, 0.032, segs, 4, 'brass', C_GOLD_BRIGHT, False)
        with xf(mb, T(0.0, hh * 1.18, 0.0) @ M_Y2Z):
            torus(mb, 0.13, 0.042, 6, 4, 'iron', C_IRON, False)
        with xf(mb, T(0.0, hh * 0.52, 0.0) @ R('Z', clapper_tilt)):
            cyl(mb, 0.040, -height * 0.92, 0.0, 5, 'iron', C_IRON, False, 0.0, 0.030)
            with xf(mb, T(0.0, -height * 0.88, 0.0)):
                cyl(mb, 0.145, -0.14, 0.14, 6, 'iron', C_IRON_RUST, False, 0.0, 0.11)


def _build_mounted_spyglass(mb, M_sg):
    """Chunky telescoping gleaming 'brass' lookout captain's spyglass mounted on a forged-iron fork gimbal."""
    with xf(mb, M_sg):
        cyl(mb, 0.085, -0.12, 0.08, 6, 'iron', C_IRON, False, 0.0)
        for sx in (-0.11, 0.11):
            _add_beam(mb, (sx * 0.45, 0.05, 0.0), (sx, 0.24, 0.0), 0.038, 0.038, 'iron', C_IRON, 0.0)
        with xf(mb, T(0.0, 0.26, 0.0) @ R('X', -7.0) @ M_Y2Z):
            cyl(mb, 0.052, -0.58, -0.18, 8, 'brass', C_BRASS, False, 0.0, 0.062)
            cyl(mb, 0.072, -0.18,  0.22, 8, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.082)
            cyl(mb, 0.094,  0.22,  0.64, 8, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.112)
            cyl(mb, 0.086, -0.12, 0.16, 8, 'timber', C_TIMBER_DARK, False, 0.0)
            for ry in (-0.56, -0.18, 0.22, 0.62):
                with xf(mb, T(0.0, ry, 0.0)):
                    torus(mb, 0.068 if ry < 0 else (0.098 if ry < 0.4 else 0.118),
                          0.018, 8, 4, 'brass', C_TEMPLE_GOLD, False)
            cyl(mb, 0.095, 0.62, 0.66, 8, 'skull_glow', C_RUNE_MID, False, 0.0)


def _build_tattered_windsock(mb, root_pos, out_dir=(-0.78, 0.0, -0.62)):
    """Bold 3D tapered crimson & cream maritime windsock pennant + fluttering tattered tail streamers ('paint')."""
    rp = Vector(root_pos)
    od = Vector(out_dir).normalized()
    side = Vector((-od.z, 0.0, od.x)).normalized()
    up = Vector((0.0, 1.0, 0.0))

    hoop_ctr = rp + od * 0.22
    rot_hoop = Vector((0.0, 1.0, 0.0)).rotation_difference(od).to_matrix().to_4x4()
    with xf(mb, T(hoop_ctr) @ rot_hoop):
        torus(mb, 0.26, 0.024, 8, 4, 'iron', C_IRON, False)
    for dy_b in (-0.22, 0.22):
        _add_beam(mb, rp, hoop_ctr + up * dy_b, 0.022, 0.022, 'iron', C_IRON, 0.0)

    segs_l = 5
    r_segs = 7
    sock_len = 1.65
    outer_secs = []
    inner_secs = []
    scols = []
    for i in range(segs_l + 1):
        t = i / float(segs_l)
        sway = sin(t * 2.1 * pi) * 0.16 * t
        droop = -0.26 * t * t
        ctr = hoop_ctr + od * (sock_len * t) + side * sway + up * droop
        r_out = 0.26 * (1.0 - 0.56 * t)
        r_in = max(0.05, r_out - 0.022)
        ring_o = []
        ring_i = []
        for k in range(r_segs):
            ang = 2.0 * pi * k / float(r_segs)
            off = side * cos(ang) + up * sin(ang)
            ring_o.append(ctr + off * r_out)
            ring_i.append(ctr + off * r_in)
        outer_secs.append(ring_o)
        inner_secs.append(ring_i)
        scols.append(C_PAINT_CREAM if i in (1, 3) else (C_CRIMSON_HI if i == 0 else C_PAINT_RED))
    loft(mb, outer_secs, 'paint', C_PAINT_RED, closed=True, caps=(False, False), mode='flat', scols=scols)
    loft(mb, [list(reversed(r)) for r in inner_secs], 'paint', C_CRIMSON_DEEP,
         closed=True, caps=(False, False), mode='flat', scols=[mul(c, 0.72) for c in scols])

    tail_ctr = hoop_ctr + od * (sock_len * 0.96) + side * (sin(2.1 * pi) * 0.16) + up * (-0.25)
    _build_double_sided_streamer(mb, tail_ctr + up * 0.05, length=1.18, h0=0.22,
                                 out_dir=(od.x, -0.08, od.z), col_main=C_PAINT_RED, col_trim=C_PAINT_CREAM)
    _build_double_sided_streamer(mb, tail_ctr - up * 0.06, length=0.95, h0=0.18,
                                 out_dir=(od.x * 0.92 + side.x * 0.22, -0.14, od.z * 0.92 + side.z * 0.22),
                                 col_main=C_CRIMSON_HI, col_trim=C_PAINT_RED)


def gen_pirate_lookout_bell_frame(outdir):
    """Characterful weathered timber & stacked-stone ridge-top maritime warning bell belfry
    (~7.4 m tall, heavy flared mossy stone cairn plinth sinking cleanly to y = -3.25 m anti-float!).
    Heavy battered A-frame oak bell gantry with forged-iron gusset plates, pitched driftwood weather
    hood, large gleaming 'brass' ship's warning bell + coiled braided pull-rope ('rope'), timber
    lookout railing post with a mounted brass spyglass, tattered crimson windsock pennant ('paint'),
    and a blazing amber ridge signal lantern ('Lantern_BellFrame' empty!).
    Target: 2,400-3,400 visual tris, 1 collider (col_bellframe_base).
    """
    clear_scene()
    rng = random.Random(SEED + 1709)
    mb = MB('PirateLookoutBellFrame', seed=1709)

    CAIRN_BOT = -3.25
    DECK_Y = 1.12
    YOKE_Y = 5.68
    ROOF_RIDGE_Y = 6.72

    col_pts = []

    # 1. Heavy Flared Mossy Stacked-Stone Cairn Plinth (sinking cleanly to y = -3.25 m anti-float!)
    cairn_secs = [
        _rect_oct(0.0, CAIRN_BOT, 0.0, 2.74, 2.38, 0.66),
        _rect_oct(0.0, -1.55,     0.0, 2.54, 2.20, 0.58),
        _rect_oct(0.0,  0.00,     0.0, 2.36, 2.04, 0.52),
        _rect_oct(0.0,  1.06,     0.0, 2.20, 1.90, 0.46),
    ]
    cairn_cols = [
        mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.66),
        mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.44),
        mix(C_TEMPLE_MID,  C_LEDGE_MOSS, 0.28),
        mix(C_TEMPLE_HI,   C_LEDGE_MOSS, 0.16),
    ]
    _loft_horizontal_masonry(
        mb, cairn_secs, 'limestone_moss', cairn_cols, rng, caps=(True, True),
        top_mat='temple_stone', top_col=C_TEMPLE_MID,
    )
    for ring in cairn_secs:
        col_pts.extend(Vector(p) for p in ring)

    # Chunky stacked protruding cairn corner stones + grounded mossy ridge boulders around the base!
    for spos, ssz, syaw in (
        ((-2.02, 0.54, -1.52), (0.72, 0.56, 0.62),  18.0),
        (( 2.04, 0.52, -1.48), (0.74, 0.58, 0.64), -22.0),
        ((-2.04, 0.56,  1.50), (0.76, 0.60, 0.64), -14.0),
        (( 2.02, 0.54,  1.52), (0.72, 0.56, 0.62),  20.0),
    ):
        sculpt_stone_block(mb, spos, ssz, 'temple_stone', C_TEMPLE_HI, rng,
                           chip=0.055, M=R('Y', syaw), moss_col=C_LEDGE_MOSS)

    for rk_pos, rk_rad, rk_rot in (
        ((-2.28, -0.36,  1.22), (0.88, 1.24, 0.86), ( 6,  28, -6)),
        (( 2.32, -0.34,  1.15), (0.84, 1.18, 0.82), (-5, -24,  7)),
        ((-2.15, -0.40, -1.35), (0.76, 1.05, 0.78), ( 4,  16, -4)),
    ):
        sculpt_rock_mass(
            mb, rk_pos, rk_rad, 'limestone_moss',
            C_LEDGE_MOSS, C_LIME_WARM, C_LIME_DARK, rng,
            subdiv=1, warp=0.18, strata=0.12, base_flare=0.40, rot_deg=rk_rot, moss_cap=0.74,
        )

    # Broad seaward stone approach steps (-Z, grounded cleanly down to CAIRN_BOT!)
    _box2(mb, (-0.52, CAIRN_BOT, -2.56), (1.38, 0.34, -1.96), 'temple_stone',
          mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.40), 0.0, (1, 0, 0))
    _box2(mb, (-0.44,  0.26,     -2.32), (1.30, 0.68, -1.86), 'temple_stone', C_TEMPLE_MID, 0.0, (1, 0, 0))
    _box2(mb, (-0.38,  0.60,     -2.08), (1.24, 1.06, -1.68), 'temple_stone', C_TEMPLE_HI,  0.0, (1, 0, 0))

    # Weathered timber deck planks seated atop the stone cairn crown (y = 1.12 m)
    for pi_d in range(7):
        pz = -1.52 + pi_d * 0.51
        cbox(mb, (rng.uniform(-0.04, 0.04), DECK_Y - 0.025, pz), (3.86, 0.09, 0.45),
             'timber', jit(C_TIMBER_HI if pi_d % 2 == 0 else C_DRIFTWOOD, rng, 0.07),
             0.0, (1, 0, 0), M=R('Y', rng.uniform(-0.8, 0.8)))

    # 2. Heavy Battered A-Frame Oak Bell Gantry with Forged-Iron Gusset Plates!
    for sgn_x in (-1.0, 1.0):
        x_bot = sgn_x * 1.78
        x_top = sgn_x * 1.38
        for sgn_z in (-1.0, 1.0):
            p_foot = Vector((x_bot, DECK_Y - 0.08, sgn_z * 1.38))
            p_apex = Vector((x_top, YOKE_Y + 0.06, sgn_z * 0.14))
            _add_beam(mb, p_foot, p_apex, 0.23, 0.24, 'timber',
                      C_TIMBER_DARK if sgn_z > 0 else C_TIMBER_MID, 0.0)
            cbox(mb, (x_bot, DECK_Y + 0.12, sgn_z * 1.38), (0.34, 0.26, 0.34), 'iron', C_IRON, 0.0)
            col_pts.extend([p_foot, p_apex])

        y_mid = 3.22
        xm = x_bot * 0.54 + x_top * 0.46
        _add_beam(mb, (xm, y_mid, -0.82), (xm, y_mid, 0.82), 0.16, 0.18, 'timber', C_TIMBER_DARK, 0.0)
        _add_beam(mb, (x_bot, DECK_Y + 0.20, -1.28), (xm, y_mid, 0.72), 0.11, 0.12, 'timber', C_DRIFTWOOD, 0.0)
        _add_beam(mb, (x_bot, DECK_Y + 0.20,  1.28), (xm, y_mid, -0.72), 0.11, 0.12, 'timber', C_TIMBER_MID, 0.0)

        # Oversized Forged-Iron Gusset Plates at Apex & Mid-Collar Joints!
        cbox(mb, (x_top, YOKE_Y - 0.16, 0.0), (0.34, 0.56, 0.64), 'iron', C_IRON, 0.0)
        for sz_g in (-0.80, 0.80):
            cbox(mb, (xm, y_mid, sz_g), (0.28, 0.32, 0.30), 'iron',
                 C_IRON_RUST if sz_g < 0 else C_IRON, 0.0)
        _add_beam(mb, (x_top * 1.06, YOKE_Y - 1.15, 0.0), (x_top * 0.58, YOKE_Y - 0.06, 0.0),
                  0.16, 0.16, 'timber', C_TIMBER_MID, 0.0)

    # Massive Overhanging Oak Bell Yoke Lintel Beam (x = -2.18..+2.18 m, y = 5.68 m)
    cbox(mb, (0.0, YOKE_Y, 0.0), (4.36, 0.32, 0.34), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
    for sx_b in (-1.42, 0.0, 1.42):
        cbox(mb, (sx_b, YOKE_Y, 0.0), (0.28, 0.38, 0.40), 'iron', C_IRON_RUST if sx_b == 0.0 else C_IRON, 0.0)

    # Chunky Pitched Driftwood Belfry Weather-Hood Canopy (y = 5.95 .. 6.72 m)
    _add_beam(mb, (-1.92, ROOF_RIDGE_Y, 0.0), (1.92, ROOF_RIDGE_Y, 0.0), 0.18, 0.20, 'timber', C_TIMBER_DARK, 0.0)
    for sx_k in (-1.38, 1.38):
        _add_beam(mb, (sx_k, YOKE_Y + 0.12, 0.0), (sx_k, ROOF_RIDGE_Y - 0.04, 0.0), 0.18, 0.18, 'timber', C_TIMBER_MID, 0.0)
    for sgn_z in (-1.0, 1.0):
        with xf(mb, T(0.0, 6.26, sgn_z * 0.58) @ R('X', sgn_z * 36.0)):
            for sl_i in range(2):
                cbox(mb, (0.0, 0.04 + sl_i * 0.07, (-0.34 if sl_i == 0 else 0.30) * sgn_z),
                     (3.96, 0.09, 0.78), 'timber',
                     jit(C_DRIFTWOOD if sl_i == 0 else C_TIMBER_MID, rng, 0.06), 0.0, (1, 0, 0))
            cbox(mb, (-1.45, 0.10, 0.0), (0.14, 0.08, 1.38), 'iron', C_IRON, 0.0)
            cbox(mb, ( 1.45, 0.10, 0.0), (0.14, 0.08, 1.38), 'iron', C_IRON, 0.0)
    col_pts.extend([Vector((-1.90, ROOF_RIDGE_Y, -0.95)), Vector((1.90, ROOF_RIDGE_Y, 0.95))])

    # 3. Large Gleaming 'brass' Ship's Warning Bell + Rocking Headstock + Coiled Braided Pull-Rope ('rope')!
    bell_pivot_y = YOKE_Y - 0.34
    cbox(mb, (0.0, bell_pivot_y, 0.0), (0.86, 0.24, 0.30), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
    for sx_tr in (-0.48, 0.48):
        _add_beam(mb, (sx_tr, YOKE_Y - 0.06, 0.0), (sx_tr, bell_pivot_y - 0.04, 0.0), 0.10, 0.14, 'iron', C_IRON, 0.0)
    lever_tip = Vector((0.88, bell_pivot_y + 0.18, -0.06))
    _add_beam(mb, (0.36, bell_pivot_y, 0.0), lever_tip, 0.095, 0.095, 'iron', C_IRON_RUST, 0.0)
    with xf(mb, T(lever_tip) @ M_Y2Z):
        torus(mb, 0.09, 0.025, 6, 4, 'iron', C_IRON, False)

    bell_pos = Vector((0.0, 4.32, 0.0))
    _build_warning_bell(mb, T(bell_pos) @ R('Z', 6.5), radius=0.70, height=1.12, segs=10, clapper_tilt=-14.0)

    rope_path = [
        lever_tip + Vector((0.0, -0.04, 0.0)),
        Vector((1.06, 3.82, -0.34)),
        Vector((1.22, 2.70, -0.75)),
        Vector((1.08, 1.82, -0.82)),
        Vector((0.94, DECK_Y + 0.22, -0.76)),
    ]
    tube(mb, rope_path, 0.034, 5, 'rope', C_ROPE, mode='smooth')
    with xf(mb, T(1.16, 2.28, -0.78)):
        cyl(mb, 0.056, -0.14, 0.14, 6, 'paint', C_PAINT_RED, False, 0.0)
    # Iron eye-bolt guide ring bolted cleanly into the starboard-front A-frame leg!
    _add_beam(mb, (1.64, 2.70, -0.94), (1.27, 2.70, -0.77), 0.048, 0.048, 'iron', C_IRON, 0.0)
    with xf(mb, T(1.22, 2.70, -0.75) @ M_Y2X):
        torus(mb, 0.075, 0.024, 6, 4, 'iron', C_IRON, False)
    _build_lean_rope_coil(mb, (0.94, DECK_Y + 0.02, -0.76), radius=0.36, turns=3, r=0.044, segs=7, psegs=4)

    # 4. Timber Lookout Railing Post + Mounted Telescoping Gleaming 'brass' Spyglass (-Z Seaward Edge)!
    rail_y = DECK_Y + 1.06
    for rx_p, rz_p, ph_r in ((-1.64, -1.58, 1.24), (-0.72, -1.58, 1.12), (-1.64, -0.25, 1.12)):
        _add_beam(mb, (rx_p, DECK_Y - 0.04, rz_p), (rx_p, DECK_Y + ph_r, rz_p),
                  0.145, 0.145, 'timber', C_TIMBER_MID, 0.0)
    _add_beam(mb, (-1.68, rail_y, -1.58), (-0.64, rail_y, -1.58), 0.12, 0.11, 'timber', C_TIMBER_HI, 0.0)
    _add_beam(mb, (-1.64, rail_y, -1.62), (-1.64, rail_y, -0.20), 0.12, 0.11, 'timber', C_TIMBER_HI, 0.0)
    spy_post_top = Vector((-1.64, DECK_Y + 1.28, -1.58))
    cbox(mb, spy_post_top + Vector((0.0, -0.04, 0.0)), (0.20, 0.08, 0.20), 'iron', C_IRON, 0.0)
    _build_mounted_spyglass(mb, T(spy_post_top) @ R('Y', 16.0))
    col_pts.append(spy_post_top + Vector((-0.2, 0.35, -0.55)))

    # 5. Tall Signal Spar & Tattered Crimson Windsock Pennant ('paint') on Starboard Roof Peak (y = 7.45 m!)
    mast_x, mast_z = 1.46, 0.18
    tube(mb, [(mast_x, YOKE_Y - 0.15, mast_z), (mast_x + 0.06, 6.65, mast_z), (mast_x + 0.10, 7.42, mast_z)],
         [0.105, 0.082, 0.056], 6, 'timber', C_TIMBER_DARK, mode='flat',
         scols=[C_TIMBER_DARK, C_TIMBER_MID, C_DRIFTWOOD])
    with xf(mb, T(mast_x + 0.10, 7.45, mast_z)):
        cyl(mb, 0.095, -0.04, 0.14, 6, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.03)
    _build_tattered_windsock(mb, (mast_x + 0.09, 7.12, mast_z), out_dir=(0.76, 0.0, -0.65))
    col_pts.append(Vector((mast_x + 0.10, 7.48, mast_z)))

    # 6. Blazing Amber Ridge Signal Lantern on Port Gantry Bracket ('Lantern_BellFrame' empty!)
    g_root = Vector((-1.58, YOKE_Y + 0.02, -0.10))
    g_tip  = Vector((-2.44, YOKE_Y + 0.26, -0.34))
    _add_beam(mb, g_root, g_tip, 0.09, 0.09, 'iron', C_IRON, 0.0)
    _add_beam(mb, (-1.66, YOKE_Y - 0.72, -0.12), g_root.lerp(g_tip, 0.65), 0.065, 0.065, 'iron', C_IRON_RUST, 0.0)
    lantern_pos = g_tip + Vector((0.0, -0.78, 0.0))
    _add_beam(mb, g_tip + Vector((0.0, -0.04, 0.0)), lantern_pos + Vector((0.0, 0.44, 0.0)),
              0.040, 0.040, 'iron', C_IRON, 0.0)
    _build_trail_lantern(mb, lantern_pos, scale=1.42, brass_body=True)

    # 7. Mossy Ridge Ivy Drapes & Base Ferns ('foliage', UV2 wind!)
    for anc, vlen, vw, vdir, vph in (
        ((-2.16, 1.02, -0.35), 1.85, 0.24, (-0.98, 0.0, -0.18), 0.12),
        (( 2.16, 1.02,  0.42), 1.95, 0.25, ( 0.96, 0.0,  0.26), 0.48),
        (( 0.25, 1.02,  1.88), 1.75, 0.24, ( 0.12, 0.0,  0.99), 0.81),
    ):
        _add_leafy_vine_drape(mb, anc, vlen, vw, vdir, rng, phase=vph)
    for fpos, fsc, nf, fph, flean in (
        ((-2.18, 0.24, 1.15), 0.95, 4, 0.22, (-0.8, 0.0, 0.6)),
        (( 2.18, 0.22, 1.08), 0.92, 4, 0.66, ( 0.8, 0.0, 0.6)),
    ):
        _add_jungle_fern_cluster(mb, fpos, scale=fsc, n_fronds=nf, rng=rng, phase=fph, lean_dir=flean)

    build(mb)

    add_empty('Lantern_BellFrame', lantern_pos)
    col_piece('col_bellframe_base', col_pts)
    export_landmark_glb(outdir, 'pirate_lookout_bell_frame.glb')


ONFOOT_CRAFT_GENERATORS = [
    gen_wooden_trail_footbridge,
    gen_coastal_smuggler_jetty,
    gen_ancient_ruined_obelisk_gate,
    gen_pirate_lookout_bell_frame,
]
