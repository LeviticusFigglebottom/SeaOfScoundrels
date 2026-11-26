# Sea of Scoundrels: 4 sculpted 3D Sea-Fort, Maritime Beacon & Ancient Relic landmarks (Wave 7-A).
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
    C_SKULL_BONE, C_SKULL_MID, C_SKULL_SHADE, C_SKULL_EYE,
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


# ---------------------------------------------------------------- local palette & sculptural helpers

C_GOLD_BRIGHT  = srgb('#f6c948')
C_BRASS_DARK   = srgb('#9e7426')
C_MAGMA_CORE   = srgb('#ffc236')
C_MAGMA_MID    = srgb('#f25c0e')
C_MAGMA_DEEP   = srgb('#a82208')
C_EMERALD_CORE = srgb('#2ef5cc')
C_CRYSTAL_MID  = srgb('#14bfa8')
C_CRYSTAL_DEEP = srgb('#096e68')
C_CRIMSON_DEEP = srgb('#781914')
C_CRIMSON_HI   = srgb('#c93428')
C_BARNACLE_HI  = srgb('#e6dec8')
C_BARNACLE_MID = srgb('#b7ad96')
C_KELP_DARK    = srgb('#144a2a')
C_KELP_MID     = srgb('#26763a')
C_KELP_SUN     = srgb('#66ad32')
C_VINE_DARK    = srgb('#13461a')
C_VINE_MID     = srgb('#276c20')
C_VINE_SUN     = srgb('#6eb224')
C_FERN_DARK    = srgb('#144a1c')
C_FERN_MID     = srgb('#2a7622')
C_FERN_TIP     = srgb('#78ba28')


def _box2(mb, lo, hi, mat, col, ch=0.0, grain=None, skip=()):
    c = ((lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5, (lo[2] + hi[2]) * 0.5)
    sz = (hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2])
    cbox(mb, c, sz, mat, col, ch, grain, skip=skip)


def _add_beam(mb, p0, p1, w, h, mat, col, ch=0.0):
    """Emit a crisp timber or forged-iron beam connecting arbitrary 3D points p0 and p1."""
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


def _rect_oct(cx, y, cz, hx, hz, ch=0.35):
    """Chamfered rectangular octagon ring at height y centered at (cx, y, cz)."""
    ch = min(ch, hx * 0.46, hz * 0.46)
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


def _circ_ring(cx, y, cz, rx, rz, segs, rot0=0.0, jitter_fn=None):
    """Polygonal circular/elliptical ring at height y."""
    pts = []
    for k in range(segs):
        ang = rot0 + 2.0 * pi * k / float(segs)
        mul_r = jitter_fn(k, ang) if jitter_fn else 1.0
        pts.append((cx + cos(ang) * rx * mul_r, y, cz + sin(ang) * rz * mul_r))
    return pts


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


def _add_chain_links(mb, p0, p1, n_links, link_r=0.068, wire_r=0.020,
                     segs=6, psegs=4, sag=0.0, rust_stride=3, mat='iron', stretch_y=1.28):
    """Tightly interlocking alternating 90-degree forged chain links along an arc-length catenary."""
    a = Vector(p0)
    b = Vector(p1)
    if (b - a).length < 1e-5 or n_links < 1:
        return
    # Sample curve finely so links space evenly by true arc length (zero stretched gaps near steep ends!)
    samples = 64
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
        if mat == 'brass':
            col = C_BRASS if (k % 2 == 0) else C_TEMPLE_GOLD
        else:
            col = C_IRON_RUST if (k % rust_stride == 0) else C_IRON
        with xf(mb, T(pt) @ rot_q @ spin @ S(0.76, stretch_y, 0.76) @ M_Y2Z):
            torus(mb, link_r, wire_r, segs, psegs, mat, col, False)


def _add_leafy_vine_drape(mb, anchor, length, width, out_dir, rng, phase=0.0):
    """Sculpted hanging leafy jungle ivy/moss vine ('foliage') with UV2 wind weights (0 root -> 0.96 tip)."""
    a = Vector(anchor)
    od = Vector((out_dir[0], 0.0, out_dir[2]))
    if od.length < 1e-4:
        od = Vector((0.0, 0.0, -1.0))
    od.normalize()
    side = Vector((-od.z, 0.0, od.x))

    segs = 5
    stem_pts = []
    for i in range(segs + 1):
        t = i / float(segs)
        sway = sin(t * 3.4 + phase * 6.28) * 0.16 * (0.2 + 0.8 * t)
        out_off = 0.03 + 0.14 * sin(t * pi * 0.78) + 0.07 * t
        stem_pts.append(a + od * out_off + side * sway + Vector((0.0, -length * t, 0.0)))

    for i in range(segs):
        t0 = i / float(segs)
        t1 = (i + 1) / float(segs)
        w0 = width * 0.22 * (1.0 - 0.52 * t0)
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

    n_leaves = max(5, int(length * 2.0))
    for li in range(n_leaves):
        t = (li + 0.35) / float(n_leaves + 0.25)
        idx_f = t * segs
        i0 = min(segs - 1, int(idx_f))
        frac = idx_f - i0
        root = stem_pts[i0].lerp(stem_pts[i0 + 1], frac)
        sgn = -1.0 if (li % 2 == 0) else 1.0
        l_scale = (0.74 + 0.52 * sin(t * pi * 0.85)) * (1.0 - 0.34 * t)
        l_len = width * 1.44 * l_scale * rng.uniform(0.86, 1.16)
        l_wid = width * 0.60 * l_scale * rng.uniform(0.86, 1.14)
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


def _add_kelp_drape(mb, anchor, length, width, out_dir, rng, phase=0.0, segs=5):
    """Graceful sinuous coastal sea-kelp twin-frond drape ('foliage') with UV2 wind weights (0 root -> 0.96 tip)."""
    a = Vector(anchor)
    od = Vector((out_dir[0], 0.0, out_dir[2]))
    if od.length < 1e-4:
        od = Vector((0.0, 0.0, -1.0))
    od.normalize()
    side = Vector((-od.z, 0.0, od.x))

    # Emit primary sinuous blade + slightly shorter offsetting sister frond for natural tangled kelp silhouette
    for fi, (l_mul, w_mul, s_shift, ph_off) in enumerate(((1.0, 1.0, 0.0, 0.0), (0.72, 0.74, 0.18, 0.37))):
        prev_l = prev_r = None
        f_len = length * l_mul
        f_w = width * w_mul
        f_ph = (phase + ph_off) % 1.0
        for i in range(segs + 1):
            t = i / float(segs)
            w = f_w * (0.48 + 0.68 * sin(t * pi * 0.86)) * (1.0 - 0.64 * (t ** 1.25))
            sway = sin(t * 4.2 + f_ph * 6.28) * 0.30 * (0.18 + 0.82 * t) + s_shift * (0.4 + 0.6 * t)
            flutter = cos(t * 3.1 + f_ph * 5.2) * 0.14 * t
            ctr = a + od * (0.06 + 0.38 * sin(t * pi * 0.65) + 0.16 * t + flutter) + side * sway + Vector((0.0, -f_len * t, 0.0))
            pl = ctr - side * w
            pr = ctr + side * w
            if prev_l is not None:
                t0 = (i - 1) / float(segs)
                c0 = jit(mix(C_KELP_DARK, C_KELP_MID, t0 * 0.78), rng, 0.05)
                c1 = jit(mix(C_KELP_MID, C_KELP_SUN, t * 0.86), rng, 0.05)
                uvs = [(0.0, t0), (1.0, t0), (1.0, t), (0.0, t)]
                uv2 = [(t0 * 0.85, f_ph), (t0 * 0.85, f_ph), (t * 0.96, f_ph), (t * 0.96, f_ph)]
                idx = [mb.v(prev_l), mb.v(prev_r), mb.v(pr), mb.v(pl)]
                mb.f(idx, 'foliage', [c0, c0, c1, c1], uvs, smooth=False, uv2=uv2)
            prev_l, prev_r = pl, pr


def _add_jungle_fern_cluster(mb, root_pos, scale=1.0, n_fronds=5, rng=None, phase=0.0, lean_dir=None):
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


def _build_double_sided_pennant(mb, root_pos, length=2.75, h0=0.82, out_dir=(-0.72, 0.0, -0.69),
                                col_main=C_PAINT_RED, col_trim=C_PAINT_CREAM, tattered=True):
    """Fluttering 3D double-sided swallowtail crimson garrison pennant (100% backface-cull safe!)."""
    rp = Vector(root_pos)
    od = Vector(out_dir).normalized()
    side = Vector((-od.z, 0.0, od.x))
    if side.length < 1e-4:
        side = Vector((1.0, 0.0, 0.0))
    side.normalize()
    segs = 6
    thick = 0.016

    top_pts = []
    bot_pts = []
    for i in range(segs + 1):
        t = i / float(segs)
        wave = sin(t * 2.25 * pi) * 0.25 * t + 0.05 * sin(t * 4.2)
        droop = -0.28 * t * t
        hh = h0 * (1.0 - 0.46 * t)
        if tattered and i in (3, 4):
            hh *= 0.84
        ctr = rp + od * (length * t) + side * wave + Vector((0.0, droop, 0.0))
        top_pts.append(ctr + Vector((0.0, hh * 0.5, 0.0)))
        bot_pts.append(ctr - Vector((0.0, hh * 0.5, 0.0)))

    for i in range(segs):
        c_seg = col_trim if i == 0 else (C_CRIMSON_HI if i % 2 == 1 else col_main)
        t0, t1 = top_pts[i], top_pts[i + 1]
        b0, b1 = bot_pts[i], bot_pts[i + 1]
        if i == segs - 1:
            mid_notch = (t0 + b0) * 0.26 + (t1 + b1) * 0.24 - od * (length * 0.16)
            tris_pair = [
                [t0, t1, mid_notch],
                [b0, mid_notch, b1],
                [t0, mid_notch, b0],
            ]
            for tri in tris_pair:
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


def _build_brass_bell(mb, M_bell, radius=0.40, height=0.64, segs=8, clapper_tilt=0.0):
    """Chunky Sea-of-Thieves lathe-turned gleaming 'brass' maritime alarm / fog bell with clapper."""
    r = radius
    h = height
    prof = [
        (0.00,      h * 0.56),
        (r * 0.22,  h * 0.54),
        (r * 0.28,  h * 0.44),
        (r * 0.48,  h * 0.36),
        (r * 0.56,  h * 0.22),
        (r * 0.64, -h * 0.08),
        (r * 0.86, -h * 0.34),
        (r * 1.00, -h * 0.48),
        (r * 0.94, -h * 0.52),
        (r * 0.78, -h * 0.42),
        (r * 0.50, -h * 0.08),
        (0.00,      h * 0.26),
    ]
    def _bcol(i, k):
        if i in (1, 2, 3):
            return C_TEMPLE_GOLD
        if i in (6, 7):
            return C_GOLD_BRIGHT
        if i >= 8:
            return C_BRASS_DARK
        return C_BRASS

    with xf(mb, M_bell):
        lathe(mb, prof, segs, 'brass', C_BRASS, smooth=False, colfn=_bcol)
        with xf(mb, T(0.0, h * 0.22, 0.0)):
            torus(mb, r * 0.57, r * 0.045, segs, 4, 'brass', C_GOLD_BRIGHT, False)
        with xf(mb, T(0.0, -h * 0.36, 0.0)):
            torus(mb, r * 0.89, r * 0.042, segs, 4, 'brass', C_TEMPLE_GOLD, False)
        with xf(mb, T(0.0, h * 0.62, 0.0) @ M_Y2Z):
            torus(mb, r * 0.16, r * 0.045, 6, 4, 'iron', C_IRON, False)
        with xf(mb, T(0.0, h * 0.18, 0.0) @ R('Z', clapper_tilt)):
            cyl(mb, r * 0.065, -h * 0.84, 0.0, 5, 'iron', C_IRON, False, 0.0)
            with xf(mb, T(0.0, -h * 0.78, 0.0)):
                cyl(mb, r * 0.18, -r * 0.16, r * 0.16, 6, 'iron', C_IRON_RUST, False, 0.0)


def _add_fire_flames(mb, center, radius, height, rng, mat='glass',
                     col_core=C_MAGMA_CORE, col_mid=C_MAGMA_MID, col_outer=C_MAGMA_DEEP):
    """Chunky stylized faceted flame tongues + glowing ember bed for fort & volcanic braziers."""
    cx, cy, cz = center
    with xf(mb, T(cx, cy, cz)):
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
        for v in bm.verts:
            p = v.co
            v.co = Vector((p.x * radius, max(-0.22, p.y) * radius * 0.42, p.z * radius))
        bm.faces.ensure_lookup_table()
        mb.newoff()
        for f in bm.faces:
            pts = [v.co.copy() for v in f.verts]
            fc = sum(pts, Vector()) / len(pts)
            col = col_core if fc.y > radius * 0.15 else (col_mid if fc.y > 0.0 else col_outer)
            mb.fp(pts, mat, jit(col, rng, 0.05), (0, 1, 0), Vector((0.0, -0.2, 0.0)), smooth=False)
        bm.free()

        plume_specs = [
            ((0.00, 0.08, 0.00), (radius * 0.42, height * 1.00), ( 4,   0,  5), col_core),
            ((-radius * 0.34, 0.04, -radius * 0.22), (radius * 0.28, height * 0.72), (-9,  24, 14), col_mid),
            (( radius * 0.32, 0.04,  radius * 0.20), (radius * 0.27, height * 0.76), ( 8, -32,-12), col_mid),
            (( radius * 0.24, 0.02, -radius * 0.32), (radius * 0.23, height * 0.58), (11,  45, -9), col_outer),
            ((-radius * 0.22, 0.02,  radius * 0.30), (radius * 0.24, height * 0.62), (-10,-40, 11), col_outer),
        ]
        for poff, (prx, pry), prot, pcol in plume_specs:
            with xf(mb, T(poff) @ R('Y', prot[1]) @ R('X', prot[0]) @ R('Z', prot[2])):
                prof = [
                    (0.0, -pry * 0.14),
                    (prx, 0.0),
                    (prx * 0.72, pry * 0.42),
                    (prx * 0.34, pry * 0.76),
                    (0.0, pry),
                ]
                lathe(mb, prof, 5, mat, jit(pcol, rng, 0.05), smooth=False)


# ================================================================ 1. FORT COASTAL WATCHTOWER RUIN

def gen_fort_coastal_watchtower_ruin(outdir):
    """Iconic crumbling mossy coastal sea-fort stone watchtower ruin (~12.6 m tall at pennant finial,
    solid flared battered masonry foundation extending deeply down to y = -4.0 m anti-float!).
    Weathered chamfered octagonal-square ashlar tower shaft with projecting corner quoins, recessed
    arrow-slit windows, half-ruined seaward fort sally-port archway, breached uneven broken stone
    crenellations, heavy L-shaped cantilevered timber parapet platform with planked decking & 7 bold
    diagonal knee braces, wall-hugging weathered climbing access ladder, forged-iron bell bracket with
    gleaming 'brass' garrison alarm bell, crimson-painted tattered garrison pennant on a corner mast,
    cascading leafy 'foliage' vines (with UV2 wind weights!), and a glowing iron fire-brazier beacon
    ('glass' flames + 'Lantern_Watchtower' empty centered right at the flame!).
    Target: 3,200-4,400 visual tris, 2 colliders (col_tower_base, col_tower_upper).
    """
    clear_scene()
    rng = random.Random(SEED + 1201)
    mb = MB('FortCoastalWatchtowerRuin', seed=1201)

    FOUND_BOT = -4.00
    DECK_Y = 7.12
    WALL_TOP_Y = 8.95

    base_col_pts = []
    upper_col_pts = []

    # 1. Solid Flared Battered Sea-Fort Masonry Foundation & Octagonal-Square Tower Shaft (y = -4.00 .. +8.95 m!)
    tower_secs = [
        _rect_oct(0.0, FOUND_BOT, 0.0, 3.26, 3.26, 0.78),
        _rect_oct(0.0, -1.85,     0.0, 2.90, 2.90, 0.70),
        _rect_oct(0.0,  0.15,     0.0, 2.54, 2.54, 0.62),
        _rect_oct(0.0,  1.65,     0.0, 2.26, 2.26, 0.56),
        _rect_oct(0.0,  4.40,     0.0, 2.02, 2.02, 0.50),
        _rect_oct(0.0,  6.72,     0.0, 1.88, 1.88, 0.46),
        _rect_oct(0.0,  7.22,     0.0, 2.04, 2.04, 0.50),
        _rect_oct(0.0,  WALL_TOP_Y, 0.0, 1.98, 1.98, 0.48),
    ]
    tower_cols = [
        mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.68),
        mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.50),
        mix(C_LIME_SHADE,  C_SEA_MOSS, 0.34),
        mix(C_LIME_MID,    C_LEDGE_MOSS, 0.16),
        C_LIME_WARM,
        mix(C_LIME_WARM,   C_LEDGE_MOSS, 0.24),
        C_LIME_PALE,
        mix(C_LIME_PALE,   C_LEDGE_MOSS, 0.38),
    ]
    _loft_horizontal_masonry(
        mb, tower_secs, 'temple_stone', tower_cols, rng, caps=(True, True),
        top_mat='limestone_moss', top_col=mix(C_LIME_WARM, C_LEDGE_MOSS, 0.45),
    )
    for ring in tower_secs[:6]:
        base_col_pts.extend(Vector(p) for p in ring)
    for ring in tower_secs[5:]:
        upper_col_pts.extend(Vector(p) for p in ring)

    # Heavy protruding stone belt-course plinth ledge at y = 1.62 m & corbelled string-course at y = 6.92 m
    for cy_b, hx_b, hz_b, h_b, col_b in (
        (1.62, 2.38, 2.38, 0.28, mix(C_TEMPLE_MID, C_LEDGE_MOSS, 0.32)),
        (6.92, 2.12, 2.12, 0.24, C_TEMPLE_HI),
    ):
        ring_lo = _rect_oct(0.0, cy_b - h_b * 0.5, 0.0, hx_b - 0.08, hz_b - 0.08, 0.52)
        ring_hi = _rect_oct(0.0, cy_b + h_b * 0.5, 0.0, hx_b,        hz_b,        0.54)
        _loft_horizontal_masonry(mb, [ring_lo, ring_hi], 'limestone_moss', [col_b, mul(col_b, 1.05)], rng, caps=(True, True))

    # Crisp protruding staggered corner quoins climbing the 4 chamfered corners (ch=0.0 -> lean tri budget!)
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            yaw_q = degrees(atan2(sx, sz)) + 45.0
            for qi, qy in enumerate((0.85, 2.25, 3.65, 5.05, 6.25, 7.95)):
                if sx > 0 and sz > 0 and qi == 5:
                    continue
                t_h = max(0.0, min(1.0, (qy - 0.15) / 6.7))
                rad_c = (2.36 * (1.0 - t_h) + 1.84 * t_h) if qy < 7.0 else 1.88
                qx = sx * rad_c * 0.875
                qz = sz * rad_c * 0.875
                q_w = 0.64 if qi % 2 == 0 else 0.52
                q_h = 0.52 if qi % 2 == 0 else 0.44
                cbox(mb, (qx, qy, qz), (q_w, q_h, 0.42),
                     'limestone_moss' if (qi in (0, 5)) else 'limestone',
                     jit(C_LIME_PALE if qi % 2 == 0 else C_LIME_WARM, rng, 0.06),
                     0.0, M=R('Y', yaw_q))

    # Deeply-rooted mossy fort footing outcrop buttresses welded solidly down into the flared skirt (ZERO undercut!)
    for rpos, rrad, rrot, mc in (
        ((-2.28, -1.05, -1.68), (1.08, 2.05, 1.02), ( 3,  22, -4), 0.65),
        (( 2.22, -1.02,  1.88), (1.16, 2.10, 1.08), (-4, -34,  5), 0.72),
        ((-2.15, -1.12,  1.92), (0.98, 1.95, 0.96), ( 4,  48, -3), 0.58),
    ):
        base_col_pts += sculpt_rock_mass(
            mb, rpos, rrad, 'limestone_moss',
            C_LEDGE_MOSS, C_LIME_WARM, C_LIME_DARK, rng,
            subdiv=1, warp=0.18, strata=0.10, base_flare=0.45, rot_deg=rrot, moss_cap=mc,
        )
    # Tumbled broken merlon block perched solidly atop the rear-starboard mossy footing buttress
    sculpt_stone_block(
        mb, (2.25, 0.72, 1.62), (0.88, 0.56, 0.68), 'temple_stone', C_TEMPLE_MID, rng,
        chip=0.05, M=R('Y', 28.0) @ R('Z', -11.0), moss_col=C_LEDGE_MOSS,
    )

    # 2. Recessed Stone Fort Sally-Port Archway on Seaward Base (-Z, y = 0.0 .. 2.85 m)
    door_z = -2.36
    _box2(mb, (-1.18, FOUND_BOT, door_z - 0.85), (1.18, 0.24, door_z + 0.25), 'temple_stone',
          mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.45), 0.0, (1, 0, 0))
    _box2(mb, (-1.02, 0.16, door_z - 0.62), (1.02, 0.54, door_z + 0.18), 'temple_stone', C_TEMPLE_MID, 0.0, (1, 0, 0))
    for sx in (-0.82, 0.82):
        cbox(mb, (sx, 1.48, door_z - 0.12), (0.42, 2.15, 0.44), 'temple_stone', C_TEMPLE_HI, 0.0)
    cbox(mb, (0.0, 2.66, door_z - 0.14), (2.22, 0.46, 0.52), 'temple_stone', C_LIME_PALE, 0.0)
    cbox(mb, (0.0, 2.76, door_z - 0.18), (0.52, 0.58, 0.58), 'limestone', C_LIME_PALE, 0.0)
    cbox(mb, (0.0, 1.48, door_z + 0.02), (1.26, 2.02, 0.12), 'basalt', C_BASALT_DARK, 0.0)
    for px_d in (-0.42, -0.14, 0.14, 0.42):
        h_d = 1.92 if px_d < 0.30 else 1.42
        cbox(mb, (px_d, 0.54 + h_d * 0.5, door_z - 0.08), (0.25, h_d, 0.08),
             'timber', jit(C_TIMBER_DARK if px_d < 0 else C_TIMBER_MID, rng, 0.07), 0.0, (0, 1, 0))
    for hy_d in (1.08, 2.04):
        cbox(mb, (-0.08, hy_d, door_z - 0.14), (1.12, 0.11, 0.04), 'iron', C_IRON_RUST if hy_d < 1.5 else C_IRON, 0.0)

    # 3. Recessed Arrow-Slit Windows (seaward -Z, port -X, rear +Z, starboard +X)
    slit_specs = [
        (( 0.00, 4.65, -2.02),   0.0),
        ((-2.02, 4.15,  0.00),  90.0),
        (( 0.00, 5.15,  1.98), 180.0),
        (( 2.02, 3.95,  0.75), -90.0),
    ]
    for spos, syaw in slit_specs:
        with xf(mb, T(spos) @ R('Y', syaw)):
            cbox(mb, (-0.28, 0.00, -0.06), (0.22, 1.38, 0.24), 'temple_stone', C_LIME_WARM, 0.0)
            cbox(mb, ( 0.28, 0.00, -0.06), (0.22, 1.38, 0.24), 'temple_stone', C_LIME_WARM, 0.0)
            cbox(mb, ( 0.00, 0.74, -0.08), (0.88, 0.24, 0.28), 'limestone', C_LIME_PALE, 0.0)
            cbox(mb, ( 0.00,-0.74, -0.09), (0.86, 0.22, 0.30), 'limestone_moss', mix(C_LIME_WARM, C_LEDGE_MOSS, 0.35), 0.0)
            cbox(mb, ( 0.00, 0.00, -0.01), (0.22, 1.24, 0.10), 'basalt', C_BASALT_DARK, 0.0)
            cbox(mb, ( 0.00, 0.14, -0.02), (0.48, 0.18, 0.10), 'basalt', C_BASALT_DARK, 0.0)

    # 4. Weathered Broken Stone Crenellations around the Parapet Crown (y = 8.90 .. 10.28 m)
    merlon_specs = [
        ((-1.58, 9.56, -1.62), (0.98, 1.36, 0.92), ( 0,  0,  0), 'temple_stone', C_LIME_PALE),
        ((-0.24, 9.48, -1.78), (0.96, 1.18, 0.56), ( 2,  0, -2), 'temple_stone', C_LIME_WARM),
        (( 1.54, 9.42, -1.60), (1.06, 1.14, 1.02), ( 0,  0,  0), 'temple_stone', C_LIME_PALE),
        ((-1.78, 9.44, -0.18), (0.56, 1.12, 0.94), ( 0,  0,  3), 'limestone_moss', C_LIME_WARM),
        ((-1.58, 9.38,  1.56), (0.96, 1.04, 0.92), (-3,  4,  4), 'temple_stone', C_LIME_MID),
        ((-0.18, 9.24,  1.76), (0.92, 0.72, 0.54), (-5,  0, -6), 'limestone_moss', C_LIME_SHADE),
        (( 1.76, 9.18, -0.22), (0.54, 0.62, 0.84), ( 4, -5, -8), 'temple_stone', C_LIME_MID),
        (( 1.24, 9.06,  1.66), (0.74, 0.42, 0.52), (-8, 12, -11), 'limestone_moss', C_LIME_SHADE),
    ]
    for mpos, msz, mrot, mmat, mcol in merlon_specs:
        M_m = R('Y', mrot[1]) @ R('X', mrot[0]) @ R('Z', mrot[2])
        sculpt_stone_block(mb, mpos, msz, mmat, mcol, rng, chip=0.055, M=M_m, moss_col=C_LEDGE_MOSS)
        upper_col_pts.append(Vector(mpos) + Vector((0.0, msz[1] * 0.5, 0.0)))

    # 5. Heavy Cantilevered L-Shaped Timber Parapet Platform (seaward -Z & starboard +X, y = 7.12 m)
    #    Seaward gallery extends to x = -2.92 so the hanging brass alarm bell & pull-rope sit squarely over deck!
    joist_y = DECK_Y - 0.16
    for jx in (-2.28, -0.82, 0.62, 2.04):
        _box2(mb, (jx - 0.11, joist_y - 0.11, -3.44), (jx + 0.11, joist_y + 0.11, -1.60),
              'timber', C_TIMBER_DARK, 0.0, (0, 0, 1))
        wx = max(-1.72, min(1.72, jx))
        p_wall = Vector((wx, 5.18, -1.94))
        p_out  = Vector((jx, joist_y - 0.06, -3.14))
        _add_beam(mb, p_wall, p_out, 0.19, 0.21, 'timber', jit(C_TIMBER_MID, rng, 0.05), 0.0)
        cbox(mb, (wx, 5.12, -1.98), (0.34, 0.28, 0.30), 'temple_stone', C_TEMPLE_MID, 0.0)
        cbox(mb, (jx, joist_y, -3.16), (0.26, 0.26, 0.12), 'iron', C_IRON, 0.0)
        upper_col_pts.append(Vector((jx, DECK_Y + 0.8, -3.42)))

    for jz in (-1.35, 0.15, 1.62):
        _box2(mb, (1.60, joist_y - 0.11, jz - 0.11), (3.34, joist_y + 0.11, jz + 0.11),
              'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
        p_wall = Vector((1.94, 5.18, jz))
        p_out  = Vector((3.08, joist_y - 0.06, jz))
        _add_beam(mb, p_wall, p_out, 0.19, 0.21, 'timber', jit(C_TIMBER_MID, rng, 0.05), 0.0)
        cbox(mb, (1.98, 5.12, jz), (0.30, 0.28, 0.34), 'temple_stone', C_TEMPLE_MID, 0.0)
        cbox(mb, (3.10, joist_y, jz), (0.12, 0.26, 0.26), 'iron', C_IRON, 0.0)
        upper_col_pts.append(Vector((3.34, DECK_Y + 0.8, jz)))

    _box2(mb, (-2.94, joist_y - 0.08, -3.46), (3.36, joist_y + 0.12, -3.26), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
    _box2(mb, ( 3.16, joist_y - 0.08, -3.46), (3.36, joist_y + 0.12,  2.14), 'timber', C_TIMBER_DARK, 0.0, (0, 0, 1))

    # Individual weathered oak deck planks across Seaward & Starboard gallery wings!
    plank_cols = (C_TIMBER_HI, C_TIMBER_MID, C_DRIFTWOOD, C_TIMBER_MID)
    for pi_s in range(4):
        pz = -3.26 + pi_s * 0.36
        pw = 6.18 if pi_s != 0 else 5.82
        px_off = 0.20 if pi_s != 0 else 0.32
        cbox(mb, (px_off, DECK_Y + rng.uniform(-0.008, 0.008), pz),
             (pw, 0.095, 0.32), 'timber', jit(plank_cols[pi_s % 4], rng, 0.07),
             0.0, (1, 0, 0), M=R('Y', rng.uniform(-0.7, 0.7)))
    for pi_e in range(4):
        px = 2.08 + pi_e * 0.36
        # Leave clean ladder entry notch on inner starboard deck at z = -1.25..-0.45!
        pl = 3.92 if pi_e < 3 else 3.45
        pz_off = 0.12 if pi_e < 3 else -0.05
        cbox(mb, (px, DECK_Y + 0.005 + rng.uniform(-0.008, 0.008), pz_off),
             (0.32, 0.095, pl), 'timber', jit(plank_cols[(pi_e + 1) % 4], rng, 0.07),
             0.0, (0, 0, 1), M=R('Y', rng.uniform(-0.8, 0.8)))

    # Chunky Timber Parapet Balustrade Posts & Weathered Railings (leaving access gap at ladder head!)
    rail_posts = [
        (-2.82, -3.32, 1.24),
        (-0.92, -3.32, 1.18),
        ( 1.24, -3.32, 1.22),
        ( 3.22, -3.32, 1.26),
        ( 3.22, -1.35, 1.16),
        ( 3.22,  0.48, 1.02),
        ( 3.22,  2.02, 1.18),
    ]
    for rpx, rpz, rph in rail_posts:
        cbox(mb, (rpx, DECK_Y + rph * 0.5 - 0.12, rpz), (0.17, rph + 0.14, 0.17),
             'timber', jit(C_TIMBER_DARK, rng, 0.06), 0.0, (0, 1, 0))
        cbox(mb, (rpx, DECK_Y + 0.08, rpz), (0.21, 0.16, 0.21), 'iron', C_IRON, 0.0)
    _add_beam(mb, (-2.82, DECK_Y + 1.06, -3.32), (3.22, DECK_Y + 1.08, -3.32), 0.12, 0.12, 'timber', C_TIMBER_HI, 0.0)
    _add_beam(mb, (-2.82, DECK_Y + 0.56, -3.32), (1.24, DECK_Y + 0.54, -3.32), 0.10, 0.10, 'timber', C_TIMBER_MID, 0.0)
    _add_beam(mb, (3.22, DECK_Y + 1.08, -3.32), (3.22, DECK_Y + 1.02, -1.35), 0.12, 0.12, 'timber', C_TIMBER_HI, 0.0)
    _add_beam(mb, (3.22, DECK_Y + 0.56, -3.32), (3.22, DECK_Y + 0.54, -1.35), 0.10, 0.10, 'timber', C_TIMBER_MID, 0.0)
    _add_beam(mb, (3.22, DECK_Y + 0.94,  0.48), (3.22, DECK_Y + 1.04,  2.02), 0.11, 0.11, 'timber', C_DRIFTWOOD, 0.0)

    # 6. Wall-Hugging Weathered Climbing Access Ladder on Starboard Face (leaning naturally INWARD up to parapet!)
    #    Foot rests solidly on an integral stepped stone entry terrace fused into the battered base!
    lad_z = -0.72
    lad_x_bot = 2.86
    lad_x_top = 2.38
    _box2(mb, (1.85, FOUND_BOT, lad_z - 0.78), (3.12, 0.12, lad_z + 0.78), 'temple_stone',
          mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.46), 0.0)
    for s_off in (-0.34, 0.34):
        p_b = Vector((lad_x_bot, 0.04, lad_z + s_off))
        p_t = Vector((lad_x_top, DECK_Y + 0.62, lad_z + s_off))
        _add_beam(mb, p_b, p_t, 0.11, 0.13, 'timber', C_TIMBER_MID, 0.0)
    n_rungs = 12
    for ri in range(n_rungs):
        t_r = (ri + 0.5) / float(n_rungs)
        rx_c = lad_x_bot * (1.0 - t_r) + lad_x_top * t_r
        ry_c = 0.18 * (1.0 - t_r) + (DECK_Y + 0.24) * t_r
        skew = 0.045 if ri == 5 else 0.0
        _add_beam(
            mb,
            (rx_c, ry_c - skew, lad_z - 0.35),
            (rx_c, ry_c + skew, lad_z + 0.35),
            0.075, 0.065, 'timber', jit(C_TIMBER_HI if ri % 2 == 0 else C_DRIFTWOOD, rng, 0.08), 0.0,
        )
    # Short sturdy forged-iron wall standoff brackets clamping ladder cleanly into the battered stone face
    for t_br in (0.30, 0.66):
        bx_c = lad_x_bot * (1.0 - t_br) + lad_x_top * t_br
        by_c = 0.18 * (1.0 - t_br) + (DECK_Y + 0.24) * t_br
        _add_beam(mb, (1.92, by_c, lad_z - 0.34), (bx_c, by_c, lad_z - 0.34), 0.07, 0.07, 'iron', C_IRON, 0.0)
        _add_beam(mb, (1.92, by_c, lad_z + 0.34), (bx_c, by_c, lad_z + 0.34), 0.07, 0.07, 'iron', C_IRON, 0.0)

    # 7. Forged-Iron Bell Bracket Holding a Gleaming 'brass' Garrison Alarm Bell (Seaward-Port Corner!)
    bell_anchor = Vector((-1.92, 9.48, -1.86))
    bell_out = Vector((-0.56, 0.0, -0.83)).normalized()
    bell_tip = bell_anchor + bell_out * 1.34
    with xf(mb, T(bell_anchor) @ R('Y', degrees(atan2(bell_out.x, bell_out.z)))):
        cbox(mb, (0.0, -0.35, 0.0), (0.28, 1.24, 0.14), 'iron', C_IRON, 0.0)
    _add_beam(mb, bell_anchor + Vector((0.0, 0.16, 0.0)), bell_tip + Vector((0.0, 0.16, 0.0)),
              0.11, 0.13, 'iron', C_IRON, 0.0)
    _add_beam(mb, bell_anchor + Vector((0.0, -0.78, 0.0)), bell_anchor + bell_out * 1.04 + Vector((0.0, 0.12, 0.0)),
              0.085, 0.095, 'iron', C_IRON_RUST, 0.0)
    tube(mb, [
        bell_tip + Vector((0.0, 0.16, 0.0)),
        bell_tip + bell_out * 0.22 + Vector((0.0, 0.26, 0.0)),
        bell_tip + bell_out * 0.34 + Vector((0.0, 0.10, 0.0)),
    ], [0.055, 0.042, 0.025], 4, 'iron', C_IRON, mode='flat')

    bell_ctr = bell_tip + Vector((0.0, -0.52, 0.0))
    _add_beam(mb, bell_tip + Vector((0.0, 0.16, 0.0)), bell_ctr + Vector((0.0, 0.38, 0.0)),
              0.065, 0.065, 'iron', C_IRON, 0.0)
    _build_brass_bell(mb, T(bell_ctr) @ R('Z', 6.0), radius=0.44, height=0.66, segs=8, clapper_tilt=-10.0)
    rope_top = bell_ctr + Vector((0.0, -0.48, 0.0))
    rope_bot = Vector((bell_ctr.x + 0.08, DECK_Y + 0.85, bell_ctr.z + 0.10))
    tube(mb, [rope_top, rope_top.lerp(rope_bot, 0.5) + Vector((0.06, 0.0, -0.04)), rope_bot],
         0.028, 4, 'rope', C_ROPE, mode='smooth')

    # 8. Tall Corner Flagstaff & Crimson-Painted Tattered Garrison Pennant (peaking at y = 12.64 m!)
    mast_x, mast_z = -1.56, -1.58
    mast_y0 = 9.05
    mast_y1 = 12.42
    tube(mb, [(mast_x, mast_y0, mast_z), (mast_x + 0.04, 10.75, mast_z - 0.02), (mast_x + 0.08, mast_y1, mast_z - 0.04)],
         [0.115, 0.090, 0.062], 6, 'timber', C_TIMBER_MID, mode='flat',
         scols=[C_TIMBER_DARK, C_TIMBER_MID, C_DRIFTWOOD])
    with xf(mb, T(mast_x, 10.22, mast_z)):
        cyl(mb, 0.15, -0.14, 0.18, 6, 'iron', C_IRON, False, 0.0)
    with xf(mb, T(mast_x + 0.08, mast_y1, mast_z - 0.04)):
        cyl(mb, 0.095, -0.04, 0.12, 6, 'brass', C_TEMPLE_GOLD, False, 0.0, 0.12)
        cyl(mb, 0.120,  0.10, 0.24, 6, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.02)
    _build_double_sided_pennant(
        mb, (mast_x + 0.10, mast_y1 - 0.52, mast_z - 0.04),
        length=2.85, h0=0.88, out_dir=(-0.74, 0.0, -0.67),
        col_main=C_PAINT_RED, col_trim=C_PAINT_CREAM, tattered=True,
    )
    for ry_f in (mast_y1 - 0.18, mast_y1 - 0.86):
        with xf(mb, T(mast_x + 0.07, ry_f, mast_z - 0.03)):
            torus(mb, 0.095, 0.022, 6, 4, 'iron', C_IRON, False)

    # 9. Glowing Iron Fire-Brazier Beacon on Front-Starboard Bastion Corner + 'Lantern_Watchtower' Empty!
    braz_x, braz_y, braz_z = 1.54, 9.98, -1.60
    with xf(mb, T(braz_x, braz_y, braz_z)):
        cyl(mb, 0.64, -0.06, 0.16, 8, 'temple_stone', C_TEMPLE_DARK, False, 0.0, 0.56)
        for k in range(4):
            ang = k * pi * 0.5 + pi * 0.25
            ca, sa = cos(ang), sin(ang)
            _add_beam(mb, (ca * 0.46, 0.10, sa * 0.46), (ca * 0.66, 0.68, sa * 0.66), 0.09, 0.09, 'iron', C_IRON, 0.0)
        bowl_prof = [
            (0.00, 0.36), (0.42, 0.38), (0.68, 0.62), (0.78, 0.86),
            (0.68, 0.90), (0.56, 0.64), (0.00, 0.52),
        ]
        lathe(mb, bowl_prof, 8, 'iron', C_IRON, smooth=False)
        with xf(mb, T(0.0, 0.88, 0.0)):
            torus(mb, 0.76, 0.050, 8, 4, 'iron', C_IRON_RUST, False)
        for k in range(8):
            ang = 2.0 * pi * k / 8.0
            ca, sa = cos(ang), sin(ang)
            _add_beam(mb, (ca * 0.52, 0.48, sa * 0.52), (ca * 0.84, 1.18, sa * 0.84),
                      0.055, 0.055, 'iron', C_IRON_RUST if k % 2 == 0 else C_IRON, 0.0)
    flame_center = (braz_x, braz_y + 0.78, braz_z)
    _add_fire_flames(mb, flame_center, radius=0.58, height=0.98, rng=rng, mat='glass')
    upper_col_pts.append(Vector((braz_x, braz_y + 1.45, braz_z)))

    # 10. Cascading Leafy 'foliage' Vines (UV2 wind!) & Crevice Ferns climbing the Mossy Sea-Fort!
    vine_specs = [
        ((-1.94, 8.95, -0.82), 3.85, 0.34, (-1.00, 0.0, -0.20), 0.08),
        ((-0.88, 8.92, -1.94), 2.95, 0.30, (-0.15, 0.0, -1.00), 0.21),
        (( 0.82, 8.96, -1.94), 2.45, 0.28, ( 0.15, 0.0, -1.00), 0.35),
        ((-1.94, 8.90,  1.02), 4.10, 0.34, (-1.00, 0.0,  0.30), 0.49),
        (( 0.45, 8.92,  1.94), 4.35, 0.36, ( 0.20, 0.0,  1.00), 0.63),
        (( 1.94, 8.75,  0.98), 3.65, 0.32, ( 1.00, 0.0,  0.25), 0.77),
        ((-2.52, 7.06, -3.18), 2.45, 0.28, (-0.65, 0.0, -0.76), 0.89),
        (( 3.08, 7.06,  1.32), 2.65, 0.28, ( 1.00, 0.0,  0.25), 0.54),
    ]
    for anc, vlen, vw, vdir, vph in vine_specs:
        _add_leafy_vine_drape(mb, anc, vlen, vw, vdir, rng, phase=vph)

    for fpos, fsc, nf, fph, flean in (
        ((-2.28, 1.56, -1.45), 0.92, 5, 0.15, (-0.8, 0.0, -0.6)),
        (( 2.24, 1.56,  1.62), 1.02, 5, 0.46, ( 0.7, 0.0,  0.7)),
        ((-1.62, 8.92,  0.65), 0.78, 4, 0.78, (-0.7, 0.0,  0.7)),
    ):
        _add_jungle_fern_cluster(mb, fpos, scale=fsc, n_fronds=nf, rng=rng, phase=fph, lean_dir=flean)

    build(mb)

    add_empty('Lantern_Watchtower', (braz_x, braz_y + 1.02, braz_z))
    col_piece('col_tower_base', base_col_pts)
    col_piece('col_tower_upper', upper_col_pts)
    export_landmark_glb(outdir, 'fort_coastal_watchtower_ruin.glb')


# ================================================================ 2. SHIPWRECK BELL BUOY BEACON

def gen_shipwreck_bell_buoy_beacon(outdir):
    """Iconic coastal shoal warning bell-buoy beacon (~9.6 m tall, heavy stone-crib & driven timber
    piling base plunging deeply to y = -4.5 m so it roots solidly into shallow turquoise reef seabeds!).
    Tall battered iron-strapped timber tripod cage with horizontal cross-bracing & service crow's-nest,
    deeply-rooted encrusted tidal barnacle rock buttresses around the waterline, lush draping sea kelp
    ('foliage' with UV2 wind!), tilted weathered warning plank sign, large hanging gleaming 'brass' fog
    bell inside the upper frame, and an ornate iron-caged glowing emerald-gold reef lantern at the
    pinnacle ('skull_glow' + 'glass' + 'Lantern_ReefBeacon' empty!).
    Target: 2,600-3,600 visual tris, 1 collider (col_buoy_base).
    """
    clear_scene()
    rng = random.Random(SEED + 1237)
    mb = MB('ShipwreckBellBuoyBeacon', seed=1237)

    PILE_BOT = -4.50
    CRIB_TOP_Y = 1.48
    PLAT_Y = 7.38
    LANTERN_Y = 8.26

    col_pts = []

    # 1. Heavy Stone-Crib & Driven Timber Piling Foundation Base plunging deeply to y = -4.50 m!
    crib_secs = [
        _circ_ring(0.0, PILE_BOT,   0.0, 2.66, 2.66, 8, rot0=pi / 8.0),
        _circ_ring(0.0, -2.10,      0.0, 2.34, 2.34, 8, rot0=pi / 8.0),
        _circ_ring(0.0, -0.15,      0.0, 2.08, 2.08, 8, rot0=pi / 8.0),
        _circ_ring(0.0, CRIB_TOP_Y, 0.0, 1.88, 1.88, 8, rot0=pi / 8.0),
    ]
    crib_cols = [
        mix(C_LIME_DARK,  C_SEA_MOSS, 0.72),
        mix(C_LIME_SHADE, C_SEA_MOSS, 0.56),
        mix(C_LIME_MID,   C_SEA_MOSS, 0.36),
        mix(C_LIME_WARM,  C_LEDGE_MOSS, 0.42),
    ]
    _loft_horizontal_masonry(
        mb, crib_secs, 'limestone_moss', crib_cols, rng, caps=(True, True),
        top_mat='limestone_moss', top_col=mix(C_LIME_MID, C_SEA_MOSS, 0.48),
    )
    for ring in crib_secs:
        col_pts.extend(Vector(p) for p in ring)

    # Three bold horizontal interlocking dark-oak timber crib framing rings wrapping the stone caisson
    for ly in (-0.15, 0.62, 1.36):
        r_log = 2.08 - (ly + 0.15) * 0.095
        for k in range(8):
            a0 = pi / 8.0 + 2.0 * pi * k / 8.0
            a1 = pi / 8.0 + 2.0 * pi * ((k + 1) % 8) / 8.0
            p0 = Vector((cos(a0) * r_log, ly, sin(a0) * r_log))
            p1 = Vector((cos(a1) * r_log, ly, sin(a1) * r_log))
            v_ext = (p1 - p0).normalized() * 0.16
            _add_beam(mb, p0 - v_ext, p1 + v_ext, 0.21, 0.23, 'timber',
                      jit(C_TIMBER_DARK if ly < 0.5 else C_DRIFTWOOD, rng, 0.07), 0.0)

    # 6 Driven Timber Fender Pilings plunging straight down to PILE_BOT (-4.50 m!) with iron collars & rope!
    for k in range(6):
        ang = radians(30.0 + k * 60.0)
        ca, sa = cos(ang), sin(ang)
        r_bot = 2.58
        r_top = 1.98
        py_top = 2.04 + rng.uniform(-0.18, 0.28)
        tube(mb, [
            (ca * r_bot, PILE_BOT, sa * r_bot),
            (ca * 2.28, -1.10, sa * 2.28),
            (ca * r_top, py_top, sa * r_top),
        ], [0.24, 0.205, 0.175], 6, 'timber', C_TIMBER_DARK, mode='flat',
            scols=[mix(C_TIMBER_DARK, C_SEA_MOSS, 0.52), C_TIMBER_DARK, C_DRIFTWOOD])
        with xf(mb, T(ca * (r_top + 0.02), py_top - 0.16, sa * (r_top + 0.02))):
            cyl(mb, 0.195, -0.055, 0.055, 6, 'iron', C_IRON_RUST if k % 2 == 0 else C_IRON, False, 0.0)
        if k in (0, 2, 4):
            for ri in range(2):
                with xf(mb, T(ca * 2.04, CRIB_TOP_Y + 0.12 + ri * 0.09, sa * 2.04)):
                    torus(mb, 0.205, 0.036, 6, 4, 'rope', mul(C_ROPE, 0.90 + 0.10 * ri), True)
        col_pts.extend([Vector((ca * r_bot, PILE_BOT, sa * r_bot)), Vector((ca * r_top, py_top, sa * r_top))])

    # 2. Deeply-Rooted Asymmetric Encrusted Tidal Barnacle Reef Buttresses welded into Waterline Crib!
    #    Plunge deep below z=0 with strong base_flare so ZERO undercut gaps ever appear!
    rock_specs = [
        ((-1.78, -0.82, -1.32), (1.16, 2.05, 1.06), ( 3,  24, -5), 0.62),
        (( 1.84, -0.92, -1.18), (1.08, 1.95, 1.02), (-4, -32,  6), 0.56),
        ((-1.82, -0.88,  1.24), (1.12, 2.00, 1.08), (-3,  46,  4), 0.68),
        (( 1.72, -0.78,  1.42), (1.18, 2.15, 1.12), ( 4, -52, -5), 0.64),
    ]
    for rpos, rrad, rrot, mc in rock_specs:
        col_pts += sculpt_rock_mass(
            mb, rpos, rrad, 'limestone_moss',
            C_SEA_MOSS, C_LIME_MID, C_LIME_DARK, rng,
            subdiv=1, warp=0.20, strata=0.12, base_flare=0.46, rot_deg=rrot, moss_cap=mc,
        )
        # Tight clusters of stylized pale conical tidal barnacles encrusted on the waterline face
        rx0, ry0, rz0 = rpos
        out_xz = Vector((rx0, 0.0, rz0)).normalized()
        for bi in range(3):
            ba = atan2(out_xz.z, out_xz.x) + rng.uniform(-0.62, 0.62)
            b_rad = rrad[0] * rng.uniform(0.46, 0.60)
            bx = rx0 + cos(ba) * b_rad
            bz = rz0 + sin(ba) * b_rad
            by = rng.uniform(0.05, 0.60)
            b_sz = rng.uniform(0.115, 0.180)
            with xf(mb, T(bx, by, bz) @ R('Y', -degrees(ba)) @ R('Z', -48.0 + rng.uniform(-14, 14))):
                cyl(mb, b_sz, -0.14, b_sz * 1.12, 5, 'skull_stone',
                    jit(C_BARNACLE_HI if bi % 2 == 0 else C_BARNACLE_MID, rng, 0.06),
                    False, 0.0, b_sz * 0.48)

    # 3. Tall Battered Iron-Strapped Timber Tripod Cage (y = -0.85 .. +7.45 m) with Slight Maritime List!
    leg_angles = (radians(-145.0), radians(-35.0), radians(90.0))
    LIST_X = 0.22
    LIST_Z = -0.14

    def _leg_pt(idx, y):
        t = (y - CRIB_TOP_Y) / float(PLAT_Y - CRIB_TOP_Y)
        r = 1.62 * (1.0 - t) + 0.72 * t
        ang = leg_angles[idx]
        return Vector((cos(ang) * r + LIST_X * max(0.0, t), y, sin(ang) * r + LIST_Z * max(0.0, t)))

    for li in range(3):
        p_root = _leg_pt(li, -0.85)
        p_crib = _leg_pt(li, CRIB_TOP_Y)
        p_mid1 = _leg_pt(li, 4.35)
        p_top  = _leg_pt(li, PLAT_Y + 0.08)
        tube(mb, [p_root, p_crib, p_mid1, p_top], [0.25, 0.23, 0.195, 0.165], 6, 'timber',
             C_TIMBER_MID, mode='flat',
             scols=[C_TIMBER_DARK, C_TIMBER_DARK, C_TIMBER_MID, C_DRIFTWOOD])
        col_pts.extend([p_crib, p_top])

        for sy in (2.35, 4.55, 6.72):
            sp = _leg_pt(li, sy)
            t_s = (sy - CRIB_TOP_Y) / float(PLAT_Y - CRIB_TOP_Y)
            rs = 0.23 * (1.0 - t_s) + 0.165 * t_s + 0.036
            with xf(mb, T(sp)):
                cyl(mb, rs, -0.12, 0.12, 6, 'iron', C_IRON_RUST if sy < 4.0 else C_IRON, False, 0.0)

    # Horizontal Cross-Bracing Beams & Diagonal X-Bracing connecting all 3 Tripod Legs!
    brace_tiers = (2.35, 4.55, 6.72)
    for ti, by in enumerate(brace_tiers):
        for li in range(3):
            lj = (li + 1) % 3
            pa = _leg_pt(li, by)
            pb = _leg_pt(lj, by)
            _add_beam(mb, pa, pb, 0.16, 0.18, 'timber',
                      C_TIMBER_DARK if ti == 0 else C_TIMBER_MID, 0.0)
            _add_beam(mb, pa.lerp(pb, 0.44), pa.lerp(pb, 0.56), 0.19, 0.21, 'iron', C_IRON, 0.0)

    for li in range(3):
        lj = (li + 1) % 3
        _add_beam(mb, _leg_pt(li, 2.38), _leg_pt(lj, 4.52), 0.11, 0.12, 'timber', C_DRIFTWOOD, 0.0)
        _add_beam(mb, _leg_pt(lj, 2.38), _leg_pt(li, 4.52), 0.11, 0.12, 'timber', C_TIMBER_MID, 0.0)
        if li != 0:
            _add_beam(mb, _leg_pt(li, 4.58), _leg_pt(lj, 6.68), 0.10, 0.11, 'timber', C_DRIFTWOOD, 0.0)

    # Forged-iron climbing service rungs bolted up the Front-Starboard tripod leg (li == 1)
    for ri in range(8):
        ry = 2.05 + ri * 0.64
        p_leg = _leg_pt(1, ry)
        out_r = Vector((cos(leg_angles[1]), 0.0, sin(leg_angles[1])))
        side_r = Vector((-out_r.z, 0.0, out_r.x))
        _add_beam(mb, p_leg + out_r * 0.24 - side_r * 0.22, p_leg + out_r * 0.24 + side_r * 0.22,
                  0.045, 0.045, 'iron', C_IRON_RUST if ri % 2 == 0 else C_IRON, 0.0)

    # 4. Tilted Weathered Warning Plank Sign mounted boldly on Seaward Lower Tripod Bay!
    sign_ctr = _leg_pt(0, 3.48).lerp(_leg_pt(1, 3.48), 0.5) + Vector((0.0, 0.0, -0.22))
    with xf(mb, T(sign_ctr) @ R('X', -8.0) @ R('Z', -7.5)):
        for si, sy_p in enumerate((-0.26, 0.00, 0.26)):
            pw = 1.92 + (0.14 if si == 1 else -0.06)
            cbox(mb, (rng.uniform(-0.04, 0.04), sy_p, 0.0), (pw, 0.23, 0.075), 'timber',
                 jit(C_DRIFTWOOD if si == 1 else C_TIMBER_MID, rng, 0.06), 0.0, (1, 0, 0))
        for sx_c in (-0.72, 0.72):
            cbox(mb, (sx_c, 0.0, 0.02), (0.11, 0.84, 0.095), 'iron', C_IRON, 0.0)
        cbox(mb, (0.0, 0.0, -0.055), (1.36, 0.56, 0.030), 'paint', C_PAINT_CREAM, 0.0)
        cbox(mb, (0.0, 0.0, -0.075), (0.46, 0.46, 0.026), 'paint', C_PAINT_RED, 0.0, M=R('Z', 45.0))
        for sx_ch in (-0.52, 0.52):
            cbox(mb, (sx_ch, 0.0, -0.075), (0.12, 0.44, 0.026), 'paint', C_PAINT_RED, 0.0, M=R('Z', 24.0 if sx_ch < 0 else -24.0))

    # 5. Large Hanging Gleaming 'brass' Fog Bell inside the Open Upper Frame (y ≈ 5.55 m)!
    bell_head_ctr = Vector((LIST_X * 0.88, 6.72, LIST_Z * 0.88))
    _add_beam(mb, _leg_pt(0, 6.72).lerp(_leg_pt(2, 6.72), 0.35),
              _leg_pt(1, 6.72).lerp(_leg_pt(2, 6.72), 0.35), 0.22, 0.24, 'timber', C_TIMBER_DARK, 0.0)
    cbox(mb, bell_head_ctr + Vector((0.0, -0.14, 0.0)), (0.64, 0.18, 0.24), 'iron', C_IRON, 0.0)
    bell_pos = bell_head_ctr + Vector((0.0, -0.94, -0.04))
    _add_chain_links(
        mb,
        bell_head_ctr + Vector((0.0, -0.22, 0.0)),
        bell_pos + Vector((0.0, 0.52, 0.0)),
        n_links=3, link_r=0.055, wire_r=0.018, segs=6, psegs=4,
    )
    _build_brass_bell(mb, T(bell_pos) @ R('Z', 7.5), radius=0.58, height=0.92, segs=8, clapper_tilt=-14.0)
    _add_beam(mb, _leg_pt(0, 5.20), bell_pos + Vector((-0.56, -0.32, 0.0)), 0.06, 0.06, 'iron', C_IRON_RUST, 0.0)
    with xf(mb, T(bell_pos + Vector((-0.60, -0.32, 0.0)))):
        cyl(mb, 0.11, -0.10, 0.10, 6, 'iron', C_IRON, False, 0.0)

    # 6. Planked Crow's-Nest Beacon Platform (y = 7.38 m) & Ornate Iron-Caged Glowing Emerald-Gold Reef Lantern!
    plat_ctr = Vector((LIST_X, PLAT_Y, LIST_Z))
    with xf(mb, T(plat_ctr)):
        cyl(mb, 1.18, -0.18, 0.04, 8, 'timber', C_TIMBER_DARK, False, 0.0, 1.24)
        cyl(mb, 1.28, -0.12, 0.05, 8, 'iron', C_IRON, False, 0.0)
        for k in range(6):
            ang = 2.0 * pi * k / 6.0 + pi / 6.0
            ca, sa = cos(ang), sin(ang)
            _add_beam(mb, (ca * 1.16, 0.02, sa * 1.16), (ca * 1.22, 0.72, sa * 1.22), 0.055, 0.055, 'iron', C_IRON, 0.0)
        with xf(mb, T(0.0, 0.70, 0.0)):
            torus(mb, 1.22, 0.042, 8, 4, 'iron', C_IRON_RUST, False)

        # Stepped iron & brass lantern plinth
        cyl(mb, 0.66, 0.02, 0.24, 8, 'iron', C_IRON, False, 0.0, 0.56)
        cyl(mb, 0.58, 0.22, 0.34, 8, 'brass', C_TEMPLE_GOLD, False, 0.0, 0.52)

        # Glowing emerald-gold dual-tone beacon core ('skull_glow' emerald Fresnel + 'glass' warm gold bands!)
        cyl(mb, 0.38, 0.34, 1.32, 8, 'skull_glow', C_CRYSTAL_MID, False, 0.0, 0.42)
        for gy in (0.58, 0.86, 1.14):
            with xf(mb, T(0.0, gy, 0.0)):
                torus(mb, 0.435, 0.056, 8, 4, 'glass', C_MAGMA_CORE, False)

        # Ornate curved forged-iron protective cage ribs
        for k in range(6):
            ang = 2.0 * pi * k / 6.0
            ca, sa = cos(ang), sin(ang)
            cage_path = [
                (ca * 0.54, 0.28, sa * 0.54),
                (ca * 0.62, 0.82, sa * 0.62),
                (ca * 0.58, 1.36, sa * 0.58),
            ]
            tube(mb, cage_path, [0.046, 0.040, 0.046], 4, 'iron', C_IRON, mode='flat')

        # Dome cupola cap + gleaming brass ventilator + weathervane arrow spire (world y ≈ 9.64 m!)
        roof_prof = [
            (0.00, 1.32), (0.72, 1.32), (0.76, 1.40), (0.58, 1.60),
            (0.32, 1.78), (0.14, 1.92), (0.00, 2.26),
        ]
        lathe(mb, roof_prof, 8, 'iron', C_IRON, smooth=False,
              colfn=lambda i, k: C_BRASS if i in (1, 4) else (C_IRON_RUST if i == 3 else C_IRON))
        _add_beam(mb, (-0.50, 2.04, 0.0), (0.50, 2.04, 0.0), 0.036, 0.055, 'brass', C_GOLD_BRIGHT, 0.0)
        cbox(mb, (0.44, 2.04, 0.0), (0.18, 0.16, 0.024), 'brass', C_GOLD_BRIGHT, 0.0, M=R('Z', 45.0))
        col_pts.append(plat_ctr + Vector((0.0, 2.26, 0.0)))

    # 7. Lush Sinuous Draping Sea-Kelp Ribbons ('foliage' with UV2 wind!) off cross-beams & reef shoulders!
    kelp_specs = [
        ((-1.38, 2.34, -1.24), 2.55, 0.26, (-0.65, 0.0, -0.76), 0.08),
        (( 1.36, 2.34, -1.26), 2.35, 0.25, ( 0.65, 0.0, -0.76), 0.24),
        ((-0.14, 2.32, -1.42), 2.05, 0.24, ( 0.00, 0.0, -1.00), 0.41),
        ((-1.82, 1.28,  1.20), 2.30, 0.25, (-0.75, 0.0,  0.66), 0.58),
        (( 1.76, 1.28,  1.28), 2.40, 0.26, ( 0.74, 0.0,  0.67), 0.74),
        (( 0.05, 2.34,  1.62), 2.50, 0.25, ( 0.05, 0.0,  0.99), 0.89),
        (( 0.80, 4.52, -0.60), 1.85, 0.21, ( 0.62, 0.0, -0.78), 0.15),
    ]
    for anc, klen, kw, odir, kph in kelp_specs:
        _add_kelp_drape(mb, anc, klen, kw, odir, rng, phase=kph, segs=4)

    build(mb)

    add_empty('Lantern_ReefBeacon', (LIST_X, LANTERN_Y, LIST_Z))
    col_piece('col_buoy_base', col_pts)
    export_landmark_glb(outdir, 'shipwreck_bell_buoy_beacon.glb')


# ================================================================ 3. ANCIENT COMPASS MONOLITH RING

def _sculpt_rune_monolith(mb, base_pos, height, w_x, w_z, yaw_deg, lean_out_deg,
                          mat, col_bot, col_top, rng, cracked_top=False, has_glow_rune=True, rear_glyph=False):
    """Sculpted weathered & cracked standing stone navigator monolith with carved rune channel & brass bands."""
    bx, by, bz = base_pos
    rings = 6
    secs = []
    scols = []
    out_pts = []
    rot_m = R('Y', yaw_deg) @ R('X', lean_out_deg)

    for ri in range(rings):
        t = ri / float(rings - 1)
        y = t * height
        taper = 1.08 - 0.34 * (t ** 1.15)
        if cracked_top and ri == rings - 1:
            taper *= 0.82
        hx = w_x * 0.5 * taper * (1.0 + 0.06 * sin(ri * 2.1))
        hz = w_z * 0.5 * taper * (1.0 + 0.05 * cos(ri * 1.7))
        ch = min(hx, hz) * 0.34
        base_r = _rect_oct(0.0, y, 0.0, hx, hz, ch)
        ring_w = []
        for vi, (px, py, pz) in enumerate(base_r):
            dy = 0.0
            if ri >= rings - 2:
                slope = (0.48 if cracked_top else 0.26) * (px / max(hx, 0.1))
                dy = slope * (1.0 if ri == rings - 1 else 0.45)
            p_loc = Vector((px + rng.uniform(-0.03, 0.03), py + dy, pz + rng.uniform(-0.03, 0.03)))
            p_w = Vector((bx, by, bz)) + (rot_m @ p_loc)
            ring_w.append(p_w)
            out_pts.append(p_w)
        secs.append(ring_w)
        c_step = mix(col_bot, col_top, smooth01(t))
        if ri == rings - 1:
            c_step = mix(c_step, C_LEDGE_MOSS, 0.46)
        scols.append(c_step)

    _loft_horizontal_masonry(
        mb, secs, mat, scols, rng, caps=(True, True),
        top_mat='limestone_moss', top_col=mix(col_top, C_LEDGE_MOSS, 0.58),
    )

    with xf(mb, T(bx, by, bz) @ rot_m):
        band_y = height * 0.62
        t_b = 0.62
        taper_b = 1.08 - 0.34 * (t_b ** 1.15)
        bw = w_x * taper_b + 0.07
        bd = w_z * taper_b + 0.07
        cbox(mb, (0.0, band_y, 0.0), (bw, 0.16, bd), 'brass', C_TEMPLE_GOLD, 0.0)
        if has_glow_rune:
            rz_face = -w_z * 0.5 * taper_b - 0.035
            cbox(mb, (0.0, band_y - 0.85, rz_face), (0.14, 1.32, 0.055), 'skull_glow', C_CRYSTAL_MID, 0.0)
            cbox(mb, (0.0, band_y - 0.55, rz_face - 0.01), (0.38, 0.38, 0.055), 'skull_glow', C_EMERALD_CORE, 0.0, M=R('Z', 45.0))
            cbox(mb, (0.0, band_y - 1.35, rz_face - 0.01), (0.30, 0.12, 0.055), 'skull_glow', C_CRYSTAL_MID, 0.0)
        if rear_glyph:
            rz_back = w_z * 0.5 * taper_b + 0.035
            cbox(mb, (0.0, band_y - 0.72, rz_back), (0.44, 0.44, 0.055), 'brass', C_GOLD_BRIGHT, 0.0, M=R('Z', 45.0))
            cbox(mb, (0.0, band_y - 0.72, rz_back + 0.025), (0.18, 0.18, 0.045), 'skull_glow', C_CRYSTAL_MID, 0.0, M=R('Z', 45.0))
    return out_pts


def gen_ancient_compass_monolith_ring(outdir):
    """Circular ancient navigator's sundial & standing stone monolith ring (~9.4 m diameter,
    stepped circular stone dais skirt sinking cleanly to y = -3.6 m anti-float!).
    Central elevated octagonal altar plinth inlaid with a crisp gleaming 'brass' 8-point compass rose
    dial + armillary horizon rings & glowing crystalline turquoise rune obelisk ('skull_glow' +
    'Lantern_Monolith' empty right at the glowing crystal!), encircled by 5 dramatic leaning weathered
    & cracked standing rune-monoliths ('temple_stone' & 'limestone_moss') arranged asymmetrically
    around the dais perimeter, draped with sculpted 'foliage' jungle ferns & trailing moss (UV2 wind!).
    Target: 3,000-4,200 visual tris, 2 colliders (col_ring_dais, col_ring_stones).
    """
    clear_scene()
    rng = random.Random(SEED + 1279)
    mb = MB('AncientCompassMonolithRing', seed=1279)

    SKIRT_BOT = -3.60
    T1_TOP = 0.56
    T2_TOP = 1.04
    ALTAR_TOP = 2.08

    dais_col_pts = []
    stone_col_pts = []

    # 1. Stepped Circular Ancient Stone Dais (~9.4 m diameter -> r = 4.70 m, skirt to y = -3.60 m!)
    d1_secs = [
        _circ_ring(0.0, SKIRT_BOT, 0.0, 5.18, 5.18, 16, rot0=pi / 16.0),
        _circ_ring(0.0, -1.65,     0.0, 4.92, 4.92, 16, rot0=pi / 16.0),
        _circ_ring(0.0,  0.00,     0.0, 4.72, 4.72, 16, rot0=pi / 16.0),
        _circ_ring(0.0,  T1_TOP,   0.0, 4.65, 4.65, 16, rot0=pi / 16.0),
    ]
    d1_cols = [
        mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.65),
        mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.48),
        mix(C_TEMPLE_MID,  C_LEDGE_MOSS, 0.28),
        C_TEMPLE_MID,
    ]
    _loft_horizontal_masonry(
        mb, d1_secs, 'temple_stone', d1_cols, rng, caps=(True, True),
        top_mat='limestone_moss', top_col=mix(C_TEMPLE_MID, C_LEDGE_MOSS, 0.36),
    )
    for ring in d1_secs:
        dais_col_pts.extend(Vector(p) for p in ring)

    # Tier 2 Inner Sundial Plaza Platform (r = 3.18 m, y = 0.48 .. 1.04 m)
    d2_secs = [
        _circ_ring(0.0, T1_TOP - 0.10, 0.0, 3.26, 3.26, 16, rot0=pi / 16.0),
        _circ_ring(0.0, T2_TOP,        0.0, 3.12, 3.12, 16, rot0=pi / 16.0),
    ]
    _loft_horizontal_masonry(
        mb, d2_secs, 'temple_stone', [C_TEMPLE_DARK, C_TEMPLE_HI], rng, caps=(False, True),
        top_mat='temple_stone', top_col=C_TEMPLE_HI,
    )
    dais_col_pts.extend(Vector(p) for p in d2_secs[-1])

    # Hero Seaward (-Z) Stepped Ceremonial Approach Stairs + 3 Minor Cardinal Step Approaches (grounded to SKIRT_BOT!)
    for s_ang_d, is_hero in ((0.0, True), (90.0, False), (180.0, False), (270.0, False)):
        sw = 2.10 if is_hero else 1.45
        with xf(mb, R('Y', s_ang_d)):
            _box2(mb, (-sw * 0.54, SKIRT_BOT, -5.02), (sw * 0.54, 0.12, -4.32), 'temple_stone',
                  mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.50), 0.0)
            _box2(mb, (-sw * 0.50, -0.10, -4.96), (sw * 0.50, 0.28, -4.45), 'temple_stone', C_TEMPLE_MID, 0.0)
            _box2(mb, (-sw * 0.46,  0.14, -4.64), (sw * 0.46, T1_TOP + 0.01, -4.18), 'temple_stone', C_TEMPLE_HI, 0.0)
            _box2(mb, (-sw * 0.44, T1_TOP - 0.06, -3.52), (sw * 0.44, T1_TOP + 0.25, -3.02), 'temple_stone', C_TEMPLE_MID, 0.0)
            _box2(mb, (-sw * 0.40, T1_TOP + 0.18, -3.22), (sw * 0.40, T2_TOP + 0.01, -2.76), 'temple_stone', C_TEMPLE_HI, 0.0)
            if is_hero:
                for sx in (-1.22, 1.22):
                    _box2(mb, (sx - 0.24, SKIRT_BOT, -5.06), (sx + 0.24, 0.88, -4.22), 'temple_stone',
                          mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.34), 0.0)
                    cbox(mb, (sx, 0.54, -5.08), (0.28, 0.28, 0.04), 'brass', C_GOLD_BRIGHT, 0.0, M=R('Z', 45.0))

    # Radial Gleaming Brass Sundial Sight-Lines & Outer Brass Azimuth Ring inlaid cleanly atop Tier 2!
    with xf(mb, T(0.0, T2_TOP + 0.024, 0.0)):
        torus(mb, 2.86, 0.055, 16, 4, 'brass', C_TEMPLE_GOLD, False)
        torus(mb, 2.02, 0.038, 16, 4, 'brass', C_BRASS, False)
        for k in range(8):
            ang = k * pi * 0.25
            w_ray = 0.11 if (k % 2 == 0) else 0.065
            with xf(mb, R('Y', degrees(ang))):
                cbox(mb, (0.0, 0.004, -2.08), (w_ray, 0.036, 1.56), 'brass',
                     C_GOLD_BRIGHT if (k % 2 == 0) else C_TEMPLE_GOLD, 0.0)

    # 2. Central Elevated Octagonal Altar Plinth + Crisp Gleaming 'brass' 8-Point Compass Rose Dial!
    with xf(mb, T(0.0, T2_TOP, 0.0)):
        plinth_prof = [
            (0.00, -0.06), (1.62, -0.06), (1.56, 0.22), (1.36, 0.34),
            (1.24,  0.88), (1.44,  1.04), (0.00, 1.04),
        ]
        lathe(mb, plinth_prof, 8, 'temple_stone', C_TEMPLE_MID, smooth=False,
              colfn=lambda i, k: C_TEMPLE_DARK if i in (1, 2) else C_TEMPLE_HI)
        with xf(mb, T(0.0, 0.98, 0.0)):
            torus(mb, 1.44, 0.058, 8, 4, 'brass', C_TEMPLE_GOLD, False)
        for k in range(4):
            ang = k * pi * 0.5
            with xf(mb, R('Y', degrees(ang))):
                cbox(mb, (0.0, 0.56, -1.32), (0.26, 0.72, 0.22), 'brass', C_BRASS, 0.0)
                cbox(mb, (0.0, 0.56, -1.44), (0.14, 0.36, 0.04), 'skull_glow', C_CRYSTAL_MID, 0.0)

    # Crisp Gleaming 'brass' 8-Point Compass Rose Dial inlaid proudly atop the Central Altar (y = ALTAR_TOP)!
    with xf(mb, T(0.0, ALTAR_TOP, 0.0)):
        cyl(mb, 1.28, -0.01, 0.035, 16, 'temple_stone', C_TEMPLE_DARK, False, 0.0)
        torus(mb, 1.24, 0.064, 16, 4, 'brass', C_GOLD_BRIGHT, False)
        for k in range(8):
            is_card = (k % 2 == 0)
            r_len = 1.22 if is_card else 0.92
            r_w = 0.21 if is_card else 0.14
            col_r = C_GOLD_BRIGHT if is_card else C_BRASS
            with xf(mb, R('Y', k * 45.0)):
                p_in = Vector((0.0, 0.042, 0.16))
                p_l  = Vector((-r_w, 0.042, r_len * 0.42))
                p_t  = Vector((0.0, 0.040, r_len))
                p_r  = Vector(( r_w, 0.042, r_len * 0.42))
                apex = Vector((0.0, 0.165 if is_card else 0.120, r_len * 0.42))
                in_ref = Vector((0.0, -0.35, r_len * 0.42))
                mb.fp([p_in, p_l, p_t, apex], 'brass', jit(col_r, rng, 0.03), (0, 0, 1), in_ref, smooth=False)
                mb.fp([p_t, p_r, p_in, apex], 'brass', jit(mul(col_r, 0.86), rng, 0.03), (0, 0, 1), in_ref, smooth=False)

    # 3. Glowing Crystalline Turquoise Rune Obelisk ('skull_glow') + Tilted Brass Armillary Compass Hoops!
    with xf(mb, T(0.0, ALTAR_TOP, 0.0)):
        cyl(mb, 0.56, 0.02, 0.28, 6, 'iron', C_IRON, False, 0.0, 0.46)
        for k in range(6):
            ang = 2.0 * pi * k / 6.0
            ca, sa = cos(ang), sin(ang)
            _add_beam(mb, (ca * 0.48, 0.18, sa * 0.48), (ca * 0.34, 0.82, sa * 0.34), 0.085, 0.095, 'brass', C_TEMPLE_GOLD, 0.0)

        # Rich jewel-faceted glowing turquoise crystal obelisk (deeper teal root -> glowing emerald apex!)
        crys_prof = [
            (0.00, 0.22), (0.42, 0.22), (0.48, 0.95),
            (0.38, 2.38), (0.28, 2.75), (0.00, 3.34),
        ]
        lathe(mb, crys_prof, 6, 'skull_glow', C_CRYSTAL_MID, smooth=False,
              colfn=lambda i, k: C_EMERALD_CORE if i in (3, 4) else (C_CRYSTAL_DEEP if i in (0, 1) else C_CRYSTAL_MID))

        for k in range(3):
            ang = radians(30.0 + k * 120.0)
            with xf(mb, T(cos(ang) * 0.42, 0.36, sin(ang) * 0.42) @ R('Y', -degrees(ang)) @ R('Z', -22.0)):
                lathe(mb, [(0.0, -0.10), (0.16, 0.05), (0.12, 0.72), (0.0, 1.08)],
                      5, 'skull_glow', C_CRYSTAL_MID if k > 0 else C_EMERALD_CORE, smooth=False)

        with xf(mb, T(0.0, 1.56, 0.0) @ R('Y', 24.0) @ R('X', 36.0)):
            torus(mb, 0.98, 0.054, 12, 4, 'brass', C_GOLD_BRIGHT, False)
        with xf(mb, T(0.0, 1.56, 0.0) @ R('Y', -58.0) @ R('X', 58.0)):
            torus(mb, 0.84, 0.046, 12, 4, 'brass', C_TEMPLE_GOLD, False)

    stone_col_pts.extend([Vector((-1.35, ALTAR_TOP, -1.35)), Vector((1.35, ALTAR_TOP + 3.35, 1.35))])

    # 4. Five Dramatic Leaning Weathered & Cracked Standing Rune-Monoliths around the Dais Perimeter!
    monolith_specs = [
        (  94.0, 3.92, 6.75, 1.48, 0.94,  -6.5, 'temple_stone',   C_TEMPLE_DARK, C_TEMPLE_HI,  False, True,  True),
        ( 148.0, 3.88, 5.55, 1.32, 0.88,  10.5, 'limestone_moss', C_LIME_SHADE,  C_LIME_PALE,  False, True,  False),
        (  34.0, 3.86, 4.95, 1.36, 0.90,   8.5, 'temple_stone',   C_TEMPLE_DARK, C_TEMPLE_MID, True,  True,  True),
        (-152.0, 3.94, 4.45, 1.18, 0.82,  -9.0, 'limestone_moss', C_LIME_SHADE,  C_LIME_WARM,  False, True,  False),
        ( -26.0, 3.94, 3.92, 1.16, 0.80,  11.0, 'temple_stone',   C_TEMPLE_DARK, C_TEMPLE_HI,  True,  False, False),
    ]
    for ang_d, mrad, mh, mwx, mwz, mlean, mmat, c_bot, c_top, mcrack, mglow, rglyph in monolith_specs:
        ang = radians(ang_d)
        mx = cos(ang) * mrad
        mz = sin(ang) * mrad
        face_yaw = degrees(atan2(mx, mz))
        pts_m = _sculpt_rune_monolith(
            mb, (mx, -0.35, mz), mh + 0.35, mwx, mwz, face_yaw, mlean,
            mmat, c_bot, c_top, rng, cracked_top=mcrack, has_glow_rune=mglow, rear_glyph=rglyph,
        )
        stone_col_pts.extend(pts_m[::4])

    # Fallen cracked monolith capstone slab + weathered rubble fragment resting solidly on Tier 1!
    sculpt_stone_block(
        mb, (2.68, T1_TOP + 0.34, 2.75), (1.35, 0.72, 0.88), 'temple_stone', C_TEMPLE_MID, rng,
        chip=0.06, M=R('Y', 38.0) @ R('Z', -11.0), moss_col=C_LEDGE_MOSS,
    )
    sculpt_stone_block(
        mb, (1.82, T1_TOP + 0.24, 3.42), (0.78, 0.48, 0.62), 'limestone_moss', C_LIME_WARM, rng,
        chip=0.05, M=R('Y', -24.0) @ R('X', 8.0), moss_col=C_LEDGE_MOSS,
    )
    for rpos, rrad, rrot in (
        ((-3.75, T1_TOP + 0.14, 0.42), (0.82, 0.56, 0.76), ( 4,  18, -5)),
        (( 3.82, T1_TOP + 0.12,-0.18), (0.78, 0.52, 0.72), (-5, -24,  6)),
    ):
        sculpt_rock_mass(
            mb, rpos, rrad, 'limestone_moss',
            C_LEDGE_MOSS, C_LIME_WARM, C_LIME_SHADE, rng,
            subdiv=1, warp=0.20, base_flare=0.28, rot_deg=rrot, moss_cap=0.72,
        )

    # 5. Sculpted 'foliage' Jungle Ferns & Trailing Moss Vines (with UV2 wind weights!)
    fern_specs = [
        ((-3.35, T1_TOP - 0.04, -2.55), 1.24, 5, 0.09, (-0.7, 0.0, -0.7)),
        (( 3.42, T1_TOP - 0.04, -2.42), 1.18, 5, 0.24, ( 0.7, 0.0, -0.7)),
        ((-3.85, T1_TOP - 0.04,  1.45), 1.32, 5, 0.41, (-0.9, 0.0,  0.4)),
        (( 3.78, T1_TOP - 0.04,  1.52), 1.26, 5, 0.57, ( 0.9, 0.0,  0.4)),
        ((-1.25, T1_TOP - 0.04,  3.82), 1.35, 5, 0.72, (-0.3, 0.0,  0.9)),
        (( 1.48, T1_TOP - 0.04,  3.75), 1.22, 5, 0.86, ( 0.4, 0.0,  0.9)),
        ((-2.02, T2_TOP - 0.04,  2.25), 0.96, 4, 0.33, (-0.5, 0.0,  0.8)),
        (( 2.10, T2_TOP - 0.04, -1.95), 0.92, 4, 0.65, ( 0.6, 0.0, -0.7)),
    ]
    for fpos, fsc, nf, fph, flean in fern_specs:
        _add_jungle_fern_cluster(mb, fpos, scale=fsc, n_fronds=nf, rng=rng, phase=fph, lean_dir=flean)

    vine_specs = [
        ((-0.24, 6.25,  3.48), 3.40, 0.30, ( 0.00, 0.0, -1.00), 0.11),
        ((-3.22, 4.95,  2.22), 2.95, 0.28, ( 0.65, 0.0, -0.75), 0.28),
        (( 3.12, 4.55,  2.32), 2.75, 0.28, (-0.65, 0.0, -0.75), 0.44),
        ((-3.58, 3.85, -1.65), 2.45, 0.26, ( 0.82, 0.0,  0.56), 0.61),
        ((-4.66, T1_TOP, -0.82), 2.10, 0.28, (-1.00, 0.0, -0.18), 0.75),
        (( 4.66, T1_TOP,  0.92), 2.15, 0.28, ( 1.00, 0.0,  0.22), 0.89),
        (( 0.85, T1_TOP,  4.60), 2.25, 0.30, ( 0.18, 0.0,  0.98), 0.52),
    ]
    for anc, vlen, vw, vdir, vph in vine_specs:
        _add_leafy_vine_drape(mb, anc, vlen, vw, vdir, rng, phase=vph)

    build(mb)

    add_empty('Lantern_Monolith', (0.0, ALTAR_TOP + 1.62, 0.0))
    col_piece('col_ring_dais', dais_col_pts)
    col_piece('col_ring_stones', stone_col_pts)
    export_landmark_glb(outdir, 'ancient_compass_monolith_ring.glb')


# ================================================================ 4. VOLCANIC CHAIN BRIDGE ANCHOR

def _sculpt_volcanic_anchor_pylon(mb, ring_specs, sides, rng):
    """Multi-ring angular dark-obsidian & basalt anchor monolith spire with sharp volcanic fracture ribs."""
    n = len(ring_specs)
    rib_j = [1.0 + 0.15 * (0.65 * cos(2.0 * pi * k / sides * 2.0 + 0.4) + rng.uniform(-0.82, 0.82))
             for k in range(sides)]
    secs = []
    centers = []
    out_pts = []
    y_lo = ring_specs[0][0]
    y_hi = ring_specs[-1][0]
    y_span = max(y_hi - y_lo, 1.0)

    for ri, (y, rx, rz, cx, cz) in enumerate(ring_specs):
        t = ri / float(max(1, n - 1))
        centers.append(Vector((cx, y, cz)))
        jog = 1.0 + (0.08 if ri % 2 == 1 else -0.05) if (0 < ri < n - 1) else 1.0
        ring = []
        for k in range(sides):
            ang = 2.0 * pi * k / float(sides) + 0.12 * t
            rk = rib_j[k] * jog * (1.0 + 0.06 * sin(ang * 3.0 + ri * 1.4))
            px = cx + cos(ang) * rx * rk
            pz = cz + sin(ang) * rz * rk
            py = y + (0.0 if ri in (0, n - 1) else rng.uniform(-0.14, 0.14))
            v = Vector((px, py, pz))
            ring.append(v)
            out_pts.append(v)
        secs.append(ring)

    mb.newoff()
    for ri in range(n - 1):
        r0, r1 = secs[ri], secs[ri + 1]
        inside = 0.5 * (centers[ri] + centers[ri + 1])
        for k in range(sides):
            kn = (k + 1) % sides
            q = [r0[k], r0[kn], r1[kn], r1[k]]
            fc = sum(q, Vector()) * 0.25
            ht = smooth01((fc.y - y_lo) / y_span)
            base = mix(C_BASALT_DARK, C_BASALT_MID, 0.22 + 0.62 * ht)
            if ht > 0.72:
                base = mix(base, C_BASALT_HOT, (ht - 0.72) * 0.85)
            elif 0.24 < ht < 0.48 and (k % 3 == 0):
                base = mix(base, C_BASALT_HOT, 0.34)
            mb.fp(q, 'basalt', jit(base, rng, 0.055, 0.015), (0, 1, 0), inside, smooth=False)

    mb.fp(secs[0], 'basalt', mul(C_BASALT_DARK, 0.72), (1, 0, 0), centers[1], smooth=False)
    mb.fp(secs[-1], 'basalt', mix(C_BASALT_TOP, C_BASALT_HOT, 0.30), (1, 0, 0), centers[-2], smooth=False)
    return out_pts


def gen_volcanic_chain_bridge_anchor(outdir):
    """Colossal jagged dark-obsidian & basalt volcanic chain-bridge anchor pylon (~11.5 m tall,
    wide unified flared volcanic rock root sinking cleanly to y = -4.5 m anti-float!).
    Encircled by 3 massive riveted forged-iron collar bands ('iron'), bold tightly-interlocking
    oversized forged-iron chain links sweeping dramatically from the upper shackle collar down to
    anchored iron mooring rings bolted into unified flank basalt anchor spurs (+ a dramatic snapped
    bridge chain stub!), and crowned with a wicked spiked iron fire-cage brazier glowing molten
    magma-orange ('glass' embers & flames + 'Lantern_ChainPylon' empty!).
    Target: 2,600-3,600 visual tris, 1 collider (col_chain_pylon).
    """
    clear_scene()
    rng = random.Random(SEED + 1307)
    mb = MB('VolcanicChainBridgeAnchor', seed=1307)

    ROOT_BOT = -4.50
    PYLON_TOP = 9.05
    COLLAR_HI_Y = 7.62

    col_pts = []

    # 1. Colossal Jagged Dark-Obsidian & Basalt Anchor Pylon + Broad Unified Volcanic Rock Root (to y = -4.50 m!)
    pylon_rings = [
        (ROOT_BOT, 4.15, 4.05,  0.00,  0.10),
        (-2.05,    3.35, 3.25,  0.00,  0.08),
        ( 0.05,    2.45, 2.38,  0.00,  0.04),
        ( 2.35,    1.78, 1.72,  0.00, -0.02),
        ( 5.05,    1.46, 1.42,  0.00, -0.14),
        ( 7.35,    1.28, 1.24,  0.00, -0.26),
        (PYLON_TOP, 1.08, 1.06, 0.00, -0.34),
    ]
    col_pts += _sculpt_volcanic_anchor_pylon(mb, pylon_rings, sides=7, rng=rng)

    # 5 Buttressing Jagged Hexagonal Columnar Basalt Organ-Pipe Ribs welding the Pylon Root!
    basalt_buttresses = [
        ((-1.62, ROOT_BOT, -0.95), 8.20, 0.78,  7.0,  4.0, True),
        (( 1.65, ROOT_BOT, -0.88), 7.75, 0.76, -7.5,  3.5, True),
        ((-1.55, ROOT_BOT,  1.25), 9.45, 0.80,  6.0, -5.5, True),
        (( 1.52, ROOT_BOT,  1.32), 8.85, 0.76, -6.2, -5.0, False),
        (( 0.08, ROOT_BOT,  1.78), 10.65, 0.84, -1.5, -7.2, True),
    ]
    for bpos, bh, brad, btx, btz, bseam in basalt_buttresses:
        sculpt_basalt_column(
            mb, bpos, bh, brad, 6, btx, btz,
            C_BASALT_DARK, mix(C_BASALT_TOP, C_BASALT_HOT, 0.28 if bseam else 0.08),
            rng, mat='basalt', magma_seam=bseam,
        )
        col_pts.append(Vector((bpos[0], bpos[1] + bh, bpos[2])))

    # 3 Massive Grounded Flank Basalt Mooring Spurs welded organically into the Wide Volcanic Massif!
    #    Deeply rooted with generous flare so ZERO detached canyon gaps appear between spurs and pylon!
    anchor_boulders = [
        # (boulder_ctr, radii, rot_deg, ring_anchor_pos)
        ((-2.92, -1.10, -1.45), (1.68, 2.95, 1.55), ( 3,  26, -6), Vector((-2.88, 1.56, -1.36))),
        (( 2.98, -1.05,  1.08), (1.72, 3.05, 1.58), (-4, -38,  5), Vector(( 2.94, 1.68,  0.98))),
        (( 0.24, -1.18, -3.12), (1.62, 2.85, 1.56), ( 4,  12, -4), Vector(( 0.22, 1.38, -2.98))),
    ]
    for bctr, brad, brot, ring_pos in anchor_boulders:
        col_pts += sculpt_rock_mass(
            mb, bctr, brad, 'basalt',
            C_BASALT_TOP, C_BASALT_MID, C_BASALT_DARK, rng,
            subdiv=1, warp=0.20, strata=0.14, base_flare=0.45, rot_deg=brot, crag_ribs=6, rib_amp=0.14,
        )
        col_pts.append(ring_pos)

    # Subtle glowing molten ember crystal ridges tucked inside the volcanic crevices between spurs!
    for epos, erot, esc in (
        ((-1.25, 1.52, -1.68), (14, -28, 18), (0.14, 0.62)),
        (( 1.32, 1.85, -1.45), (10,  34,-15), (0.12, 0.54)),
        (( 1.48, 2.15,  1.35), (-12, 42,-16), (0.13, 0.58)),
    ):
        with xf(mb, T(epos) @ R('Y', erot[1]) @ R('X', erot[0]) @ R('Z', erot[2])):
            lathe(mb, [(0.0, -esc[1] * 0.45), (esc[0], 0.0), (esc[0] * 0.62, esc[1] * 0.55), (0.0, esc[1])],
                  4, 'glass', C_MAGMA_MID, smooth=False)

    # 2. Three Massive Riveted Forged-Iron Collar Bands encircling the Basalt Pylon ('iron')!
    collar_specs = [
        (2.65, -0.02, 1.66, 1.98, 0.28, 6),
        (5.32, -0.15, 1.38, 1.70, 0.28, 6),
        (COLLAR_HI_Y, -0.27, 1.22, 1.58, 0.38, 8),
    ]
    for cy_c, cz_c, r_in, r_out, hh, n_riv in collar_specs:
        with xf(mb, T(0.0, cy_c, cz_c)):
            c_prof = [
                (r_in,  -hh),
                (r_out, -hh),
                (r_out,  hh),
                (r_in,   hh),
                (r_in,  -hh),
            ]
            lathe(mb, c_prof, 8, 'iron', C_IRON, smooth=False,
                  colfn=lambda i, k: C_IRON_RUST if i in (0, 2) else C_IRON)
            for rk in range(n_riv):
                ang = 2.0 * pi * rk / float(n_riv) + 0.25
                rx = cos(ang) * (r_out + 0.05)
                rz = sin(ang) * (r_out + 0.05)
                cbox(mb, (rx, 0.0, rz), (0.14, 0.16, 0.14), 'iron',
                     C_IRON_RUST if rk % 2 == 0 else C_IRON, 0.0, M=R('Y', -degrees(ang)))

    # 4 Vertical Forged-Iron Tension Straps clamping the 3 Collar Bands together along the Pylon!
    for k in range(4):
        ang = radians(45.0 + k * 90.0)
        ca, sa = cos(ang), sin(ang)
        p_lo = Vector((ca * 1.92, 2.65, -0.02 + sa * 1.92))
        p_hi = Vector((ca * 1.50, COLLAR_HI_Y, -0.27 + sa * 1.50))
        _add_beam(mb, p_lo, p_hi, 0.18, 0.16, 'iron', C_IRON, 0.0)

    # 3. Bold Tightly-Interlocking Oversized Forged-Iron Chain Links Sweeping Dramatically to Mooring Rings!
    for _, _, _, ring_pos in anchor_boulders:
        dir_xz = Vector((ring_pos.x, 0.0, ring_pos.z + 0.27)).normalized()
        p_shackle = Vector((dir_xz.x * 1.66, COLLAR_HI_Y, -0.27 + dir_xz.z * 1.66))
        sh_yaw = -degrees(atan2(dir_xz.z, dir_xz.x))

        with xf(mb, T(p_shackle) @ R('Y', sh_yaw)):
            cbox(mb, (-0.18, 0.0, 0.0), (0.44, 0.42, 0.34), 'iron', C_IRON_RUST, 0.0)
            with xf(mb, T(0.14, 0.0, 0.0) @ M_Y2Z):
                torus(mb, 0.26, 0.078, 6, 4, 'iron', C_IRON, False)

        with xf(mb, T(ring_pos) @ R('Y', sh_yaw)):
            cbox(mb, (0.0, -0.14, 0.0), (0.72, 0.26, 0.72), 'iron', C_IRON_RUST, 0.0)
            cbox(mb, (0.0,  0.04, 0.0), (0.30, 0.30, 0.38), 'iron', C_IRON, 0.0)
            with xf(mb, T(0.0, 0.24, 0.0) @ M_Y2Z):
                torus(mb, 0.28, 0.080, 6, 4, 'iron', C_IRON, False)

        # Oversized arc-length-spaced chain links (link_r=0.28, stretch_y=1.34 -> 100% tight physical interlock!)
        _add_chain_links(
            mb,
            p_shackle + dir_xz * 0.12,
            ring_pos + Vector((0.0, 0.26, 0.0)),
            n_links=8, link_r=0.28, wire_r=0.084, segs=6, psegs=4, sag=0.72, rust_stride=3, stretch_y=1.34,
        )

    # Dramatic Snapped Heavy Bridge-Chain Remnant dangling freely from a seaward-starboard clevis at y = 5.32 m!
    snap_top = Vector((1.22, 5.32, -1.42))
    snap_bot = Vector((1.58, 3.42, -1.86))
    with xf(mb, T(snap_top)):
        cbox(mb, (-0.12, 0.0, 0.12), (0.34, 0.34, 0.34), 'iron', C_IRON_RUST, 0.0)
    _add_chain_links(
        mb, snap_top, snap_bot,
        n_links=3, link_r=0.25, wire_r=0.076, segs=6, psegs=4, sag=0.10, rust_stride=2, stretch_y=1.36,
    )

    # 4. Wicked Spiked Forged-Iron Fire-Cage Brazier Crown (y = 9.00 .. 11.55 m) + 'Lantern_ChainPylon' Empty!
    braz_ctr = Vector((0.0, PYLON_TOP, -0.34))
    with xf(mb, T(braz_ctr)):
        cyl(mb, 1.20, -0.14, 0.22, 8, 'iron', C_IRON, False, 0.0, 1.06)
        cage_prof = [
            (0.00, 0.20), (0.76, 0.24), (1.14, 0.68), (1.26, 1.08),
            (1.12, 1.14), (0.92, 0.72), (0.00, 0.56),
        ]
        lathe(mb, cage_prof, 8, 'iron', C_IRON, smooth=False,
              colfn=lambda i, k: C_IRON_RUST if i in (2, 4) else C_IRON)
        with xf(mb, T(0.0, 1.12, 0.0)):
            torus(mb, 1.24, 0.072, 8, 4, 'iron', C_IRON_RUST, False)
        with xf(mb, T(0.0, 1.88, 0.0)):
            torus(mb, 1.38, 0.056, 8, 4, 'iron', C_IRON, False)

        # 8 Wicked Upward-Flaring Curved Forged-Iron Cage Spikes crowning the Volcanic Brazier (to y ≈ 11.55 m!)
        for k in range(8):
            ang = 2.0 * pi * k / 8.0
            ca, sa = cos(ang), sin(ang)
            yaw_d = -degrees(ang)
            spike_path = [
                (ca * 0.88, 0.34, sa * 0.88),
                (ca * 1.28, 1.08, sa * 1.28),
                (ca * 1.44, 1.86, sa * 1.44),
                (ca * 1.18, 2.48, sa * 1.18),
            ]
            tube(mb, spike_path, [0.095, 0.088, 0.072, 0.018], 4, 'iron',
                 C_IRON_RUST if k % 2 == 0 else C_IRON, mode='flat')
            with xf(mb, T(ca * 1.26, 1.08, sa * 1.26) @ R('Y', yaw_d) @ R('Z', -58.0)):
                cyl(mb, 0.095, -0.05, 0.62, 4, 'iron', C_IRON_RUST, False, 0.0, 0.014)

        # 4 Lean Faceted Charred Basalt Coal Chunks wedged around the rim of the glowing magma brazier
        for ck in range(4):
            ang = ck * pi * 0.5 + 0.4
            with xf(mb, T(cos(ang) * 0.64, 0.92, sin(ang) * 0.64) @ R('Y', ck * 72.0) @ R('Z', 16.0)):
                cyl(mb, 0.28, -0.14, 0.22, 5, 'basalt', C_BASALT_DARK, False, 0.0, 0.14)

    # Blazing molten magma-orange ember mound & fierce flame tongues inside the spiked fire-cage!
    flame_pos = (braz_ctr.x, braz_ctr.y + 0.96, braz_ctr.z)
    _add_fire_flames(
        mb, flame_pos, radius=0.88, height=1.52, rng=rng, mat='glass',
        col_core=C_MAGMA_CORE, col_mid=C_MAGMA_MID, col_outer=C_MAGMA_DEEP,
    )
    col_pts.append(braz_ctr + Vector((0.0, 2.50, 0.0)))

    build(mb)

    add_empty('Lantern_ChainPylon', (braz_ctr.x, braz_ctr.y + 1.38, braz_ctr.z))
    col_piece('col_chain_pylon', col_pts)
    export_landmark_glb(outdir, 'volcanic_chain_bridge_anchor.glb')


MARITIME_RELICS_GENERATORS = [
    gen_fort_coastal_watchtower_ruin,
    gen_shipwreck_bell_buoy_beacon,
    gen_ancient_compass_monolith_ring,
    gen_volcanic_chain_bridge_anchor,
]
