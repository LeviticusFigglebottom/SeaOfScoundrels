# Sea of Scoundrels: 4 sculpted 3D Story-Craft Landmarks (Wave I-11 / Pass I-Q4).
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
    sculpt_rock_mass,
    clear_scene, build, col_piece, col_box, add_empty, export_landmark_glb,
)


# ---------------------------------------------------------------- local palette & sculptural helpers

C_GOLD_BRIGHT   = srgb('#f6c948')
C_BRASS_DARK    = srgb('#9b7024')
C_OAK_FRESH     = srgb('#c68d52')
C_CRIMSON_HI    = srgb('#cc3226')
C_CRIMSON_DEEP  = srgb('#781814')
C_TEAL_BRIGHT   = srgb('#26949a')
C_CANVAS_WARM   = srgb('#e4d5b2')
C_CANVAS_SHADE  = srgb('#b5a37e')
C_COBBLE_LIGHT  = srgb('#c5b699')
C_COBBLE_MID    = srgb('#928674')
C_COBBLE_DARK   = srgb('#5d564c')
C_RUNE_CORE     = srgb('#46ffe0')
C_RUNE_MID      = srgb('#16d6bc')
C_RUNE_DEEP     = srgb('#0c8278')
C_BARNACLE_HI   = srgb('#e8e0ca')
C_BARNACLE_MID  = srgb('#b5ab92')
C_CORAL_WARM    = srgb('#d9684c')
C_CORAL_PALE    = srgb('#e69c78')
C_SALT_IRON     = srgb('#565b63')
C_MAGMA_WHITE   = srgb('#ffe270')
C_MAGMA_CRIMSON = srgb('#d62610')
C_SULFUR_PALE   = srgb('#e6ca4e')
C_SULFUR_OCHRE  = srgb('#c49824')
C_SULFUR_DARK   = srgb('#7c6018')
C_VINE_DARK     = srgb('#13461a')
C_VINE_MID      = srgb('#276c20')
C_VINE_SUN      = srgb('#6eb224')
C_FERN_DARK     = srgb('#144a1c')
C_FERN_MID      = srgb('#2a7622')
C_FERN_TIP      = srgb('#78ba28')
C_KELP_DARK     = srgb('#154c2a')
C_KELP_MID      = srgb('#287a3c')
C_KELP_SUN      = srgb('#66ad32')


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


def _reg_oct(cx, y, cz, radius, rot_deg=22.5):
    """Regular 8-sided polygon ring at height y centered at (cx, y, cz)."""
    r0 = radians(rot_deg)
    return [
        (cx + radius * cos(r0 + 2.0 * pi * k / 8.0), y, cz + radius * sin(r0 + 2.0 * pi * k / 8.0))
        for k in range(8)
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


def _build_harbour_lantern(mb, center, scale=1.0, brass_body=True):
    """Chunky Sea-of-Thieves brass/iron coastal lantern with warm glowing amber glass core."""
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


def _build_rope_coil_lean(mb, center, radius=0.30, turns=3, r=0.040, segs=7, psegs=4):
    """Chunky coiled braided hemp rope pile ('rope')."""
    for i in range(turns):
        rr = radius * (1.0 - 0.22 * i)
        with xf(mb, T(center[0], center[1] + r * (1.0 + i * 1.62), center[2])):
            torus(mb, rr, r, segs, psegs, 'rope', mul(C_ROPE, 0.88 + 0.12 * (i % 2)), True)


def _build_coopered_cask(mb, M_bar, radius=0.33, height=0.84, rng=None,
                         col_a=C_TIMBER_MID, col_b=C_TIMBER_HI, col_head=C_TIMBER_DARK,
                         segs=7, stripe_col=None, spigot=False):
    """Chunky coopered pirate rum cask with forged iron hoops & optional painted band/brass spigot."""
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
        for hi_idx, (hy, hr) in enumerate(((-hh * 0.68, radius * 0.95), (hh * 0.68, radius * 0.95))):
            cyl(mb, hr, hy - 0.028, hy + 0.028, segs, 'iron',
                C_IRON_RUST if hi_idx == 1 else C_IRON, False, 0.0)
        if stripe_col is not None:
            cyl(mb, radius * 1.015, -hh * 0.18, hh * 0.18, segs, 'paint', stripe_col, False, 0.0)
        if spigot:
            with xf(mb, T(0.0, hh + 0.01, 0.0)):
                cyl(mb, 0.032, -0.02, 0.15, 5, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.020)
            cbox(mb, (0.0, hh + 0.11, 0.04), (0.095, 0.026, 0.026), 'brass', C_GOLD_BRIGHT, 0.0)


def _build_stenciled_crate(mb, M_crate, size=(0.82, 0.72, 0.78), rng=None,
                           stripe_col=C_TEAL_BRIGHT, stencil_col=C_PAINT_CREAM):
    """Weathered pirate tavern supply crate with battens, iron corners, & painted stencil accent."""
    sx, sy, sz = size
    hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
    with xf(mb, M_crate):
        cbox(mb, (0.0, 0.0, 0.0), (sx, sy, sz), 'timber',
             jit(C_TIMBER_MID, rng, 0.05) if rng else C_TIMBER_MID, 0.0, (1, 0, 0))
        for ys in (-hy + 0.055, hy - 0.055):
            for zs in (-hz - 0.016, hz + 0.016):
                cbox(mb, (0.0, ys, zs), (sx + 0.05, 0.095, 0.048), 'timber', C_TIMBER_HI, 0.0, (1, 0, 0))
            for xs in (-hx - 0.016, hx + 0.016):
                cbox(mb, (xs, ys, 0.0), (0.048, 0.095, sz + 0.02), 'timber', C_TIMBER_HI, 0.0, (0, 0, 1))
        for xs in (-hx - 0.016, hx + 0.016):
            for zs in (-hz - 0.016, hz + 0.016):
                cbox(mb, (xs, 0.0, zs), (0.068, sy + 0.02, 0.068), 'iron', C_IRON, 0.0)
        for zs in (-hz - 0.018, hz + 0.018):
            _add_beam(mb, (-hx + 0.09, -hy + 0.09, zs), (hx - 0.09, hy - 0.09, zs),
                      0.075, 0.032, 'timber', C_OAK_FRESH, 0.0)
        if stripe_col is not None:
            for zs in (-hz - 0.025, hz + 0.025):
                cbox(mb, (0.0, 0.0, zs), (sx * 0.68, 0.17, 0.018), 'paint', stripe_col, 0.0)
                cbox(mb, (0.0, 0.0, zs + (0.012 if zs > 0 else -0.012)),
                     (0.16, 0.16, 0.012), 'paint', stencil_col, 0.0, M=R('Z', 45.0))
            for xs in (-hx - 0.025, hx + 0.025):
                cbox(mb, (xs, 0.0, 0.0), (0.018, 0.17, sz * 0.68), 'paint', stripe_col, 0.0)
                cbox(mb, (xs + (0.012 if xs > 0 else -0.012), 0.0, 0.0),
                     (0.012, 0.16, 0.16), 'paint', stencil_col, 0.0, M=R('X', 45.0))


def _build_banded_chest(mb, M_chest, scale=0.88):
    """Chunky iron-banded oak pirate treasure chest with vaulted lid & gilded brass lockplate."""
    w, h, d = 1.06 * scale, 0.52 * scale, 0.64 * scale
    hw, hh, hd = w * 0.5, h * 0.5, d * 0.5
    with xf(mb, M_chest):
        cbox(mb, (0.0, hh, 0.0), (w, h, d), 'timber', C_TIMBER_MID, 0.0, (1, 0, 0))
        for xs in (-hw + 0.04, 0.0, hw - 0.04):
            cbox(mb, (xs, hh, -hd - 0.012), (0.074, h + 0.02, 0.028), 'iron', C_IRON, 0.0)
            cbox(mb, (xs, hh,  hd + 0.012), (0.074, h + 0.02, 0.028), 'iron', C_IRON, 0.0)
        for xs in (-hw - 0.012, hw + 0.012):
            cbox(mb, (xs, h - 0.045, 0.0), (0.028, 0.078, d + 0.03), 'iron', C_IRON_RUST, 0.0)
            cbox(mb, (xs * 1.03, hh + 0.03, 0.0), (0.040, 0.12, 0.15), 'brass', C_GOLD_BRIGHT, 0.0)
        cbox(mb, (0.0, 0.055, -hd - 0.012), (w + 0.03, 0.072, 0.028), 'iron', C_IRON_RUST, 0.0)
        cbox(mb, (0.0, h - 0.04, -hd - 0.012), (w + 0.03, 0.068, 0.028), 'iron', C_IRON, 0.0)
        cbox(mb, (0.0, h - 0.12, -hd - 0.028), (0.18, 0.19, 0.028), 'brass', C_GOLD_BRIGHT, 0.0)
        cbox(mb, (0.0, h - 0.13, -hd - 0.044), (0.045, 0.072, 0.016), 'iron', C_IRON, 0.0)

        with xf(mb, T(0.0, h, 0.0)):
            r_lid = hd * 1.02
            lid_ring = [(cos(pi * k / 4.0) * r_lid, sin(pi * k / 4.0) * (0.25 * scale)) for k in range(5)]
            secs = [
                [Vector((-hw - 0.02, py, -pz)) for pz, py in lid_ring] + [Vector((-hw - 0.02, 0.0, -hd))],
                [Vector(( hw + 0.02, py, -pz)) for pz, py in lid_ring] + [Vector(( hw + 0.02, 0.0, -hd))],
            ]
            loft(mb, secs, 'timber', C_TIMBER_HI, closed=True, caps=(True, True), mode='flat')
            for xs in (-hw + 0.04, 0.0, hw - 0.04):
                rib_pts = [
                    Vector((xs, sin(pi * k / 4.0) * (0.275 * scale), -cos(pi * k / 4.0) * (r_lid + 0.020)))
                    for k in range(5)
                ]
                tube(mb, rib_pts, 0.032, 4, 'iron', C_IRON, mode='flat')
            cbox(mb, (0.0, 0.03, -hd - 0.032), (0.10, 0.12, 0.024), 'brass', C_BRASS, 0.0)


def _add_chain_catenary(mb, p0, p1, sag=0.45, n_links=None, link_r=0.092, wire_r=0.028,
                        segs=5, psegs=3, start_idx=0):
    """Arc-length parameterized alternating 90-degree forged wrought-iron chain links (zero air gaps!)."""
    a = Vector(p0)
    b = Vector(p1)
    if (b - a).length < 1e-4:
        return

    def _pt(u):
        p = a.lerp(b, u)
        p.y -= sag * 4.0 * u * (1.0 - u)
        return p

    samples = 40
    pts_s = [_pt(i / float(samples)) for i in range(samples + 1)]
    cum = [0.0]
    for i in range(samples):
        cum.append(cum[-1] + (pts_s[i + 1] - pts_s[i]).length)
    total_len = cum[-1]
    if total_len < 1e-4:
        return

    # Link elongation is 1.35 along tangent -> inner opening ≈ 2.70 * link_r - 2 * wire_r;
    # spacing link centers <= 1.68 * link_r guarantees physical interlocking with zero air gaps!
    if n_links is None:
        n_links = max(2, int(math.ceil(total_len / (link_r * 1.62))))
    else:
        min_interlock = max(2, int(math.ceil(total_len / (link_r * 1.72))))
        n_links = max(n_links, min_interlock)

    def _sample_s(s_target):
        s_target = max(0.0, min(total_len, s_target))
        for i in range(samples):
            if cum[i + 1] >= s_target:
                denom = max(1e-6, cum[i + 1] - cum[i])
                f = (s_target - cum[i]) / denom
                return pts_s[i].lerp(pts_s[i + 1], f)
        return pts_s[-1]

    for k in range(n_links):
        s_k = (k + 0.5) * (total_len / float(n_links))
        pt = _sample_s(s_k)
        tang = _sample_s(s_k + 0.03) - _sample_s(s_k - 0.03)
        if tang.length < 1e-5:
            tang = Vector((0.0, -1.0, 0.0))
        tang.normalize()
        rot_q = Vector((0.0, 1.0, 0.0)).rotation_difference(tang).to_matrix().to_4x4()
        spin = R('Y', 90.0 if ((k + start_idx) % 2 == 0) else 0.0)
        col = C_IRON_RUST if ((k + start_idx) % 3 == 0) else C_IRON
        with xf(mb, T(pt) @ rot_q @ spin @ S(0.76, 1.36, 0.76) @ M_Y2Z):
            torus(mb, link_r, wire_r, segs, psegs, 'iron', col, False)


def _build_wind_pennant(mb, root_pos, length=2.25, h0=0.56, out_dir=(0.76, -0.06, -0.64),
                        col_main=C_PAINT_RED, col_trim=C_GOLD_BRIGHT, phase=0.34):
    """Wind-whipped 3D double-sided tattered swallowtail pennant ('paint') with UV2 wind weights!"""
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
        hh = h0 * (1.0 - 0.52 * t)
        if i in (3, 4):
            hh *= 0.84
        ctr = rp + od * (length * t) + side * wave + Vector((0.0, droop, 0.0))
        top_pts.append(ctr + Vector((0.0, hh * 0.5, 0.0)))
        bot_pts.append(ctr - Vector((0.0, hh * 0.5, 0.0)))
        weights.append((t ** 1.15) * 0.94)

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

    n_leaves = max(4, int(length * 1.80))
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
    """Graceful sinuous coastal sea-kelp frond ('foliage') with UV2 wind weights (0 root -> 0.96 tip)."""
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


def _sculpt_jagged_basalt_column(mb, base_pos, height, radius, tilt_x, tilt_z,
                                 col_bot, col_top, rng, sides=6, magma_seam=True,
                                 sulfur_rim=False, pointy_apex=True):
    """Hexagonal columnar volcanic obsidian-basalt shaft with jagged cleaved or pointed fang tip."""
    bx, by, bz = base_pos
    rot0 = rng.uniform(0.0, 2.0 * pi)
    rib_j = [rng.uniform(0.90, 1.12) for _ in range(sides)]
    ring_fracs = [(0.00, 1.14), (0.28, 1.04), (0.62, 0.92), (0.86, 0.74)]
    secs = []
    centers = []
    out_pts = []
    for ri, (t, rmul) in enumerate(ring_fracs):
        y = by + t * height
        ox = bx + sin(radians(tilt_x)) * t * height
        oz = bz + sin(radians(tilt_z)) * t * height
        centers.append(Vector((ox, y, oz)))
        ring = []
        for k in range(sides):
            ang = rot0 + 2.0 * pi * k / float(sides)
            rk = radius * rmul * rib_j[k]
            yk = y + (radius * 0.44 * cos(ang - rot0) if ri == len(ring_fracs) - 1 else 0.0)
            v = Vector((ox + cos(ang) * rk, yk, oz + sin(ang) * rk))
            ring.append(v)
            out_pts.append(v)
        secs.append(ring)

    mb.newoff()
    for ri in range(len(secs) - 1):
        r0, r1 = secs[ri], secs[ri + 1]
        inside = 0.5 * (centers[ri] + centers[ri + 1])
        t_h = (ri + 0.5) / float(len(secs))
        c_band = mix(col_bot, col_top, t_h)
        if magma_seam and ri == 0:
            c_band = mix(c_band, C_BASALT_HOT, 0.28)
        for k in range(sides):
            kn = (k + 1) % sides
            q = [r0[k], r0[kn], r1[kn], r1[k]]
            mb.fp(q, 'basalt', jit(c_band, rng, 0.05, 0.015), (0, 1, 0), inside, smooth=False)

    mb.fp(secs[0], 'basalt', mul(col_bot, 0.72), (1, 0, 0), centers[1], smooth=False)
    if pointy_apex:
        apex = Vector((
            bx + sin(radians(tilt_x)) * height * 1.04 + cos(rot0) * radius * 0.14,
            by + height,
            bz + sin(radians(tilt_z)) * height * 1.04 + sin(rot0) * radius * 0.14,
        ))
        out_pts.append(apex)
        inside_top = centers[-1] - Vector((0.0, 0.35, 0.0))
        top_c = mix(col_top, C_SULFUR_OCHRE, 0.36) if sulfur_rim else mul(col_top, 1.12)
        for k in range(sides):
            kn = (k + 1) % sides
            mb.fp([secs[-1][k], secs[-1][kn], apex], 'basalt',
                  jit(top_c, rng, 0.05), (0, 1, 0), inside_top, smooth=False)
    else:
        top_c = mix(col_top, C_SULFUR_OCHRE, 0.58) if sulfur_rim else mul(col_top, 1.08)
        mb.fp(secs[-1], 'basalt', jit(top_c, rng, 0.05), (1, 0, 0), centers[-2], smooth=False)
    return out_pts


def _sculpt_magma_ribbon(mb, path, widths, out_normal, rng, hot_core=True):
    """Glowing recessed molten magma fissure vein ('glass') with crisp bright core & crimson-hot seams."""
    pts = [Vector(p) for p in path]
    n = len(pts)
    on = Vector(out_normal).normalized()
    mb.newoff()
    for i in range(n - 1):
        p0, p1 = pts[i], pts[i + 1]
        seg = p1 - p0
        if seg.length < 1e-5:
            continue
        side = seg.cross(on)
        if side.length < 1e-5:
            side = Vector((1.0, 0.0, 0.0))
        side.normalize()
        w0, w1 = widths[i], widths[i + 1]
        t_mid = (i + 0.5) / max(1.0, float(n - 1))
        c_mid = C_MAGMA_GLOW if hot_core else mix(C_MAGMA_GLOW, C_MAGMA_CRIMSON, 0.45)
        c_edge = mix(C_MAGMA_CRIMSON, C_BASALT_HOT, 0.35 + 0.35 * t_mid)
        inside = 0.5 * (p0 + p1) - on * 0.45
        mb.fp([p0 - side * w0, p0 + on * 0.022, p1 + on * 0.022, p1 - side * w1],
              'glass', [c_edge, c_mid, c_mid, c_edge], (0, 1, 0), inside, smooth=False)
        mb.fp([p0 + on * 0.022, p0 + side * w0, p1 + side * w1, p1 + on * 0.022],
              'glass', [c_mid, c_edge, c_edge, c_mid], (0, 1, 0), inside, smooth=False)


# ================================================================ 1. PIRATE TAVERN SUPPLY CART

def _build_cartwheel_10spoke(mb, center, radius=0.62, side_sign=1.0, rng=None):
    """Chunky 10-spoke iron-rimmed pirate wooden cartwheel with beveled felloe & gleaming brass hubcap."""
    segs = 10
    r_hub = 0.145
    r_felloe_in = radius - 0.135
    r_felloe_out = radius - 0.036
    hw_felloe = 0.062
    hw_tire = 0.068

    # Wheel lies in local Y-Z plane (axle along X); lathe rotates around local Y -> orient via R('Z', ±90)!
    with xf(mb, T(center) @ R('Z', -90.0 if side_sign > 0 else 90.0)):
        # Chunky wooden felloe ring (open outer face seated tightly under iron tire band)
        felloe_prof = [
            (r_felloe_out, -hw_felloe),
            (r_felloe_in,  -hw_felloe),
            (r_felloe_in,   hw_felloe),
            (r_felloe_out,  hw_felloe),
        ]
        lathe(mb, felloe_prof, segs, 'timber', C_TIMBER_MID, False, False,
              lambda i, k: jit(C_TIMBER_HI if k % 2 == 0 else C_TIMBER_MID, rng, 0.06) if rng else C_TIMBER_MID)

        # Forged-iron tire band wrapping outside felloe
        tire_prof = [
            (r_felloe_out, -hw_tire),
            (radius,       -hw_tire * 0.88),
            (radius,        hw_tire * 0.88),
            (r_felloe_out,  hw_tire),
        ]
        lathe(mb, tire_prof, segs, 'iron', C_IRON, False, False,
              lambda i, k: C_IRON_RUST if k % 3 == 0 else C_IRON)

        # 10 sturdy tapered oak spokes radiating cleanly from hub to felloe!
        for k in range(segs):
            ang = 2.0 * pi * k / float(segs) + pi / float(segs)
            ca, sa = cos(ang), sin(ang)
            p_in = Vector((ca * (r_hub * 0.82), 0.0, sa * (r_hub * 0.82)))
            p_out = Vector((ca * (r_felloe_in + 0.025), 0.0, sa * (r_felloe_in + 0.025)))
            _add_beam(mb, p_in, p_out, 0.056, 0.044, 'timber',
                      C_TIMBER_HI if k % 2 == 0 else C_OAK_FRESH, 0.0)

        # Turned oak axle nave/hub + iron hub hoop + gleaming domed brass hubcap (+Y is outward!)
        cyl(mb, r_hub, -0.11, 0.13, 6, 'timber', C_TIMBER_DARK, False, 0.0, r_hub * 0.92)
        cyl(mb, r_hub * 1.04, 0.065, 0.12, 6, 'iron', C_IRON_RUST, False, 0.0)
        cap_prof = [
            (0.0,          0.12),
            (r_hub * 0.86, 0.12),
            (r_hub * 0.80, 0.19),
            (r_hub * 0.54, 0.24),
            (0.0,          0.26),
        ]
        lathe(mb, cap_prof, 6, 'brass', C_GOLD_BRIGHT, False, False,
              lambda i, k: C_GOLD_BRIGHT if i >= 2 else C_BRASS)
        cbox(mb, (0.0, 0.165, 0.0), (0.032, 0.028, 0.24), 'iron', C_IRON, 0.0)


def _build_folded_canvas_tarp(mb, M_tarp, size=(0.92, 0.30, 0.78), rng=None):
    """Sculpted thick multi-fold weathered cream & crimson canvas sailcloth tarp bundle ('paint')."""
    sx, sy, sz = size
    hx, hz = sx * 0.5, sz * 0.5
    with xf(mb, M_tarp):
        layers = [
            (0.00, 0.095, 1.00, 1.00,  0.0, C_CANVAS_SHADE),
            (0.09, 0.092, 0.94, 0.95,  3.5, C_CANVAS_WARM),
            (0.18, 0.085, 0.86, 0.88, -4.0, C_CANVAS_WARM),
        ]
        for y0, th, mx, mz, yaw, col in layers:
            w, d = sx * mx, sz * mz
            cbox(mb, (0.0, y0 + th * 0.5, 0.0), (w, th, d), 'paint',
                 jit(col, rng, 0.04) if rng else col, 0.0, (1, 0, 0), M=R('Y', yaw))
        cbox(mb, (0.0, 0.272, 0.0), (sx * 0.86, 0.018, 0.16), 'paint', C_PAINT_RED, 0.0, M=R('Y', -4.0))
        with xf(mb, T(0.0, 0.14, -hz * 0.94) @ M_Y2X):
            cyl(mb, 0.088, -hx * 0.92, hx * 0.92, 6, 'paint', C_CANVAS_WARM, True, 0.0, 0.078)
        flap_secs = [
            [Vector((-0.26, 0.14, hz * 0.86)), Vector((0.26, 0.14, hz * 0.86)),
             Vector((0.26, 0.10, hz * 0.86)),  Vector((-0.26, 0.10, hz * 0.86))],
            [Vector((-0.24, -0.08, hz * 1.08)), Vector((0.24, -0.06, hz * 1.08)),
             Vector((0.24, -0.10, hz * 1.04)),  Vector((-0.24, -0.12, hz * 1.04))],
            [Vector((-0.18, -0.34, hz * 1.14)), Vector((0.20, -0.30, hz * 1.12)),
             Vector((0.20, -0.33, hz * 1.09)),  Vector((-0.18, -0.37, hz * 1.11))],
        ]
        loft(mb, flap_secs, 'paint', C_CANVAS_WARM, closed=True, caps=(True, True), mode='flat',
             scols=[C_CANVAS_WARM, C_PAINT_RED, C_CANVAS_SHADE])


def gen_pirate_tavern_supply_cart(outdir):
    """Weathered pirate harbour wooden cargo handcart (~4.6 m long x 2.4 m wide x 2.6 m tall)
    resting atop a deeply skirted cobbled coastal stone hardstand apron (y = -2.65..+0.08 m so
    wheels NEVER float on sloping village trails or beaches!).
    Features twin chunky iron-rimmed 10-spoke wooden cartwheels with gleaming brass hubcaps, heavy
    oak axle beam, planked bed with slatted flared side railings, twin forward draft shafts propped
    on a weathered oak rum barrel, iron-hooped rum casks, banded treasure chest, stenciled supply
    crate, coiled hemp rope, folded canvas tarp, and a hanging brass harbour lantern off the rear
    upright post ('Lantern_Cart').
    Target: 2,600-3,600 visual tris, 1 collider (col_cart_body).
    """
    clear_scene()
    rng = random.Random(SEED + 2101)
    mb = MB('PirateTavernSupplyCart', seed=2101)

    SKIRT_BOT = -2.65
    APRON_Y   =  0.06
    AXLE_Y    =  0.68
    AXLE_Z    =  0.22
    DECK_Y    =  0.98
    col_pts = []

    # 1. Deeply Skirted Cobbled Coastal Stone Hardstand Apron (y = -2.65..+0.08 m anti-float!)
    apron_secs = [
        _rect_oct(0.0, SKIRT_BOT, -0.18, 1.92, 3.08, 0.62),
        _rect_oct(0.0, -1.35,     -0.18, 1.76, 2.92, 0.56),
        _rect_oct(0.0, -0.18,     -0.18, 1.62, 2.76, 0.50),
        _rect_oct(0.0, APRON_Y,   -0.18, 1.50, 2.64, 0.44),
    ]
    apron_cols = [
        mix(C_LIME_DARK, C_SEA_MOSS, 0.58),
        mix(C_LIME_SHADE, C_SEA_MOSS, 0.36),
        mix(C_LIME_MID, C_LEDGE_MOSS, 0.20),
        mix(C_COBBLE_MID, C_LIME_WARM, 0.32),
    ]
    _loft_horizontal_masonry(
        mb, apron_secs, 'limestone_moss', apron_cols, rng, caps=(True, True),
        top_mat='temple_stone', top_col=C_COBBLE_MID,
    )
    for ring in apron_secs[2:]:
        col_pts.extend(Vector(p) for p in ring)

    # Raised irregular hand-laid coastal cobble flagstones across the hardstand surface (y = 0.05..0.09 m)
    cobble_specs = [
        (-0.68, -1.96, 1.04, 0.72,  5.0, C_COBBLE_LIGHT),
        ( 0.68, -1.90, 0.98, 0.74, -6.0, C_COBBLE_MID),
        (-0.74, -0.96, 1.12, 0.82, -4.0, C_COBBLE_MID),
        ( 0.72, -0.92, 1.08, 0.84,  5.0, C_COBBLE_LIGHT),
        (-0.76,  0.18, 1.14, 0.96,  2.0, C_COBBLE_LIGHT),
        ( 0.76,  0.20, 1.14, 0.94, -3.0, C_COBBLE_DARK),
        (-0.70,  1.30, 1.08, 0.86, -5.0, C_COBBLE_DARK),
        ( 0.72,  1.28, 1.06, 0.84,  4.0, C_COBBLE_LIGHT),
    ]
    for cx_c, cz_c, sx_c, sz_c, yaw_c, col_c in cobble_specs:
        cbox(mb, (cx_c, APRON_Y + 0.012, cz_c), (sx_c, 0.045, sz_c), 'temple_stone',
             jit(col_c, rng, 0.05), 0.0, (1, 0, 0), M=R('Y', yaw_c), skip=('-y',))

    # Grounded mossy coastal kerb stone blocks anchoring the outer apron corners
    for kb_p, kb_s, kb_y in (
        ((-1.42, 0.14, -2.18), (0.58, 0.34, 0.48),  24.0),
        (( 1.44, 0.14,  1.92), (0.62, 0.36, 0.50), -30.0),
    ):
        sculpt_stone_block(
            mb, kb_p, kb_s, 'limestone_moss', C_COBBLE_MID, rng,
            chip=0.055, M=R('Y', kb_y), moss_col=C_LEDGE_MOSS,
        )

    # 2. Twin Chunky 10-Spoke Iron-Rimmed Cartwheels with Brass Hubcaps + Heavy Oak Axle Beam
    for sgn_x in (-1.0, 1.0):
        _build_cartwheel_10spoke(mb, (sgn_x * 1.06, AXLE_Y, AXLE_Z), radius=0.62, side_sign=sgn_x, rng=rng)
        cbox(mb, (sgn_x * 1.06, APRON_Y + 0.075, AXLE_Z - 0.34), (0.20, 0.11, 0.16),
             'timber', C_TIMBER_DARK, 0.0, M=R('X', 26.0))
        cbox(mb, (sgn_x * 1.06, APRON_Y + 0.075, AXLE_Z + 0.34), (0.20, 0.11, 0.16),
             'timber', C_TIMBER_DARK, 0.0, M=R('X', -26.0))

    # Heavy oak axle beam & iron axle-strap U-bolts + longitudinal chassis bolster stringers
    cbox(mb, (0.0, AXLE_Y, AXLE_Z), (2.28, 0.17, 0.17), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
    for sx_u in (-0.74, 0.74):
        cbox(mb, (sx_u, AXLE_Y + 0.09, AXLE_Z), (0.22, 0.24, 0.22), 'timber', C_TIMBER_MID, 0.0)
        cbox(mb, (sx_u, AXLE_Y, AXLE_Z), (0.14, 0.22, 0.23), 'iron', C_IRON, 0.0)
        cbox(mb, (sx_u, DECK_Y - 0.11, 0.32), (0.13, 0.13, 2.48), 'timber', C_TIMBER_DARK, 0.0, (0, 0, 1))
    for cz_b in (-0.84, 0.22, 1.46):
        cbox(mb, (0.0, DECK_Y - 0.08, cz_b), (1.76, 0.11, 0.14), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))

    # 3. Twin Forward Draft Shafts Propped Solidly on a Weathered Upright Oak Rum Barrel!
    _build_coopered_cask(
        mb, T(0.0, APRON_Y + 0.40, -1.78) @ R('Y', 18.0),
        radius=0.33, height=0.80, rng=rng,
        col_a=C_TIMBER_DARK, col_b=C_DRIFTWOOD, col_head=C_TIMBER_MID,
        segs=6, stripe_col=None, spigot=False,
    )
    cbox(mb, (0.0, 0.87, -1.24), (1.42, 0.09, 0.11), 'timber', C_TIMBER_MID, 0.0, (1, 0, 0))
    cbox(mb, (0.0, 0.88, -1.78), (1.18, 0.08, 0.10), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
    for sgn_x in (-1.0, 1.0):
        p_rear = Vector((sgn_x * 0.72, DECK_Y - 0.11, -0.82))
        p_mid  = Vector((sgn_x * 0.56, 0.89,          -1.78))
        p_tip  = Vector((sgn_x * 0.50, 0.91,          -2.42))
        _add_beam(mb, p_rear, p_mid, 0.105, 0.105, 'timber', C_TIMBER_MID, 0.0)
        _add_beam(mb, p_mid,  p_tip, 0.090, 0.088, 'timber', C_OAK_FRESH, 0.0)
        cbox(mb, p_tip, (0.105, 0.105, 0.12), 'iron', C_IRON, 0.0)
        cbox(mb, p_tip + Vector((0.0, -0.06, -0.05)), (0.05, 0.08, 0.09), 'iron', C_IRON_RUST, 0.0)
        col_pts.append(p_tip)

    # 4. Planked Oak Cart Bed & Flared Slatted Side Railings + Strapped Rear Tailgate
    for pi_b in range(7):
        px = -0.75 + pi_b * 0.25
        cbox(mb, (px, DECK_Y - 0.025, 0.31), (0.225, 0.068, 2.46), 'timber',
             jit(C_TIMBER_HI if pi_b % 2 == 0 else C_TIMBER_MID, rng, 0.07),
             0.0, (0, 0, 1), skip=('-y',))

    for sgn_x in (-1.0, 1.0):
        for sz_p in (-0.86, -0.08, 0.70, 1.46):
            p_b = Vector((sgn_x * 0.85, DECK_Y - 0.04, sz_p))
            p_t = Vector((sgn_x * 0.95, DECK_Y + 0.64, sz_p))
            _add_beam(mb, p_b, p_t, 0.085, 0.085, 'timber', C_TIMBER_DARK, 0.0)
            cbox(mb, (sgn_x * 0.87, DECK_Y + 0.06, sz_p), (0.10, 0.14, 0.11), 'iron', C_IRON, 0.0)
        for ry_off, flare_x, h_slat, mat_s, col_s in (
            (0.18, 0.88, 0.16, 'timber', C_TIMBER_HI),
            (0.36, 0.91, 0.11, 'paint',  C_PAINT_RED),
            (0.54, 0.94, 0.11, 'timber', C_OAK_FRESH),
        ):
            cbox(mb, (sgn_x * flare_x, DECK_Y + ry_off, 0.30), (0.052, h_slat, 2.44),
                 mat_s, col_s, 0.0, (0, 0, 1), M=R('Z', -sgn_x * 8.0))
        for sz_i in (-0.86, 1.46):
            cbox(mb, (sgn_x * 0.93, DECK_Y + 0.54, sz_i), (0.095, 0.12, 0.11), 'iron', C_IRON, 0.0)

    for ry_f, h_f, col_f in ((0.18, 0.18, C_TIMBER_MID), (0.40, 0.14, C_TIMBER_HI), (0.58, 0.12, C_OAK_FRESH)):
        cbox(mb, (0.0, DECK_Y + ry_f, -0.88), (1.76, h_f, 0.062), 'timber', col_f, 0.0, (1, 0, 0))
    with xf(mb, T(0.0, DECK_Y + 0.02, 1.50) @ R('X', 24.0)):
        cbox(mb, (0.0, 0.20, 0.0), (1.70, 0.36, 0.064), 'timber', C_DRIFTWOOD, 0.0, (1, 0, 0))
        cbox(mb, (-0.72, 0.20, 0.02), (0.08, 0.38, 0.08), 'iron', C_IRON, 0.0)
        cbox(mb, ( 0.72, 0.20, 0.02), (0.08, 0.38, 0.08), 'iron', C_IRON, 0.0)
    for sgn_x in (-1.0, 1.0):
        _add_beam(mb, (sgn_x * 0.92, DECK_Y + 0.52, 1.46), (sgn_x * 0.80, DECK_Y + 0.34, 1.64),
                  0.032, 0.028, 'iron', C_IRON_RUST, 0.0)

    # 5. Rich Pirate Tavern Cargo Stack (Rum Casks, Banded Chest, Stenciled Crate, Rope, Canvas Tarp)
    for cz_k in (-0.42, -0.02):
        cbox(mb, (-0.36, DECK_Y + 0.06, cz_k), (0.64, 0.12, 0.10), 'timber', C_TIMBER_DARK, 0.0)
    _build_coopered_cask(
        mb, T(-0.36, DECK_Y + 0.42, -0.22) @ R('Y', 12.0) @ R('X', 90.0),
        radius=0.35, height=0.92, rng=rng,
        col_a=C_TIMBER_MID, col_b=C_TIMBER_HI, col_head=C_TIMBER_DARK,
        segs=7, stripe_col=C_PAINT_RED, spigot=True,
    )
    _build_coopered_cask(
        mb, T(0.42, DECK_Y + 0.43, 0.82) @ R('Y', -26.0),
        radius=0.32, height=0.84, rng=rng,
        col_a=C_TIMBER_DARK, col_b=C_TIMBER_MID, col_head=C_OAK_FRESH,
        segs=6, stripe_col=C_PAINT_CREAM, spigot=False,
    )
    _build_banded_chest(
        mb, T(-0.32, DECK_Y + 0.01, 0.82) @ R('Y', 158.0),
        scale=0.86,
    )
    _build_stenciled_crate(
        mb, T(0.40, DECK_Y + 0.37, -0.26) @ R('Y', -9.0),
        size=(0.76, 0.72, 0.78), rng=rng,
        stripe_col=C_TEAL_BRIGHT, stencil_col=C_PAINT_CREAM,
    )
    _build_folded_canvas_tarp(
        mb, T(0.38, DECK_Y + 0.74, -0.24) @ R('Y', 14.0),
        size=(0.80, 0.28, 0.74), rng=rng,
    )
    _build_rope_coil_lean(mb, (-0.34, DECK_Y + 0.75, -0.18), radius=0.26, turns=3, r=0.036, segs=6, psegs=4)
    tube(mb, [(-0.88, DECK_Y + 0.50, -0.22), (-0.36, DECK_Y + 0.79, -0.45),
              (0.06, DECK_Y + 0.62, -0.35), (0.88, DECK_Y + 0.50, -0.22)],
         0.026, 4, 'rope', C_ROPE, mode='smooth')

    # 6. Rear Upright Lantern Standard & Hanging Brass Harbour Lantern ('Lantern_Cart')!
    post_x, post_z = 0.88, 1.48
    _add_beam(mb, (post_x, DECK_Y - 0.04, post_z), (post_x + 0.04, 2.58, post_z + 0.04),
              0.11, 0.11, 'timber', C_TIMBER_DARK, 0.0)
    cbox(mb, (post_x + 0.01, DECK_Y + 0.28, post_z + 0.01), (0.145, 0.18, 0.145), 'iron', C_IRON, 0.0)
    cbox(mb, (post_x + 0.04, 2.54, post_z + 0.04), (0.145, 0.16, 0.145), 'iron', C_IRON_RUST, 0.0)

    arm_root = Vector((post_x + 0.04, 2.54, post_z + 0.04))
    arm_tip  = Vector((post_x + 0.28, 2.62, post_z + 0.52))
    _add_beam(mb, arm_root, arm_tip, 0.056, 0.056, 'iron', C_IRON, 0.0)
    _add_beam(mb, (post_x + 0.03, 2.12, post_z + 0.03), arm_root.lerp(arm_tip, 0.66),
              0.042, 0.042, 'iron', C_IRON_RUST, 0.0)
    cbox(mb, arm_tip + Vector((0.0, 0.06, 0.02)), (0.06, 0.11, 0.09), 'iron', C_IRON, 0.0)

    lantern_pos = arm_tip + Vector((0.0, -0.54, 0.0))
    _add_beam(mb, arm_tip + Vector((0.0, -0.02, 0.0)), lantern_pos + Vector((0.0, 0.38, 0.0)),
              0.032, 0.032, 'iron', C_IRON, 0.0)
    _build_harbour_lantern(mb, lantern_pos, scale=1.08, brass_body=True)

    # Collect cart cargo/body silhouette extrema for clean convex collider
    for p_ext in (
        (-1.24, APRON_Y, -0.60), ( 1.24, APRON_Y,  1.65),
        (-1.05, 1.98,    -0.95), ( 1.05, 2.02,     1.58),
        (-0.56, 1.02,    -2.44), ( 0.56, 1.02,    -2.44),
        ( 1.02, 2.62,     1.62),
    ):
        col_pts.append(Vector(p_ext))

    build(mb)

    add_empty('Lantern_Cart', lantern_pos)
    col_piece('col_cart_body', col_pts)
    export_landmark_glb(outdir, 'pirate_tavern_supply_cart.glb')


# ================================================================ 2. SUNKEN ANCHOR MEMORIAL

def _build_fluke_palm(mb, tip_pos, arm_dir, up_hint, rng=None):
    """Chunky beveled spade-shaped barbed iron galleon anchor fluke palm."""
    tp = Vector(tip_pos)
    fwd = Vector(arm_dir).normalized()
    side = fwd.cross(Vector(up_hint))
    if side.length < 1e-4:
        side = Vector((0.0, 0.0, 1.0))
    side.normalize()
    nrm = side.cross(fwd).normalized()

    # 3D faceted diamond-spade fluke palm with raised spine & twin rear barbs
    p_tip   = tp + fwd * 0.56
    p_bl    = tp - fwd * 0.34 - side * 0.44
    p_br    = tp - fwd * 0.34 + side * 0.44
    p_mid_l = tp + fwd * 0.04 - side * 0.32
    p_mid_r = tp + fwd * 0.04 + side * 0.32
    p_spine_f = tp + fwd * 0.04 + nrm * 0.135
    p_spine_b = tp + fwd * 0.04 - nrm * 0.135
    p_base_f  = tp - fwd * 0.24 + nrm * 0.11
    p_base_b  = tp - fwd * 0.24 - nrm * 0.11

    ctr = tp + fwd * 0.04
    c_hi = C_SALT_IRON
    c_mid = C_IRON
    c_rst = C_IRON_RUST
    for tri, col in (
        # Upper (+nrm) beveled palm facets
        ([p_tip, p_mid_r, p_spine_f], c_hi),
        ([p_tip, p_spine_f, p_mid_l], c_mid),
        ([p_mid_r, p_br, p_base_f],   c_rst),
        ([p_mid_r, p_base_f, p_spine_f], c_mid),
        ([p_mid_l, p_spine_f, p_base_f], c_hi),
        ([p_mid_l, p_base_f, p_bl],   c_rst),
        # Lower (-nrm) beveled palm facets
        ([p_tip, p_spine_b, p_mid_r], c_mid),
        ([p_tip, p_mid_l, p_spine_b], c_rst),
        ([p_mid_r, p_base_b, p_br],   c_mid),
        ([p_mid_r, p_spine_b, p_base_b], c_mid),
        ([p_mid_l, p_base_b, p_spine_b], c_rst),
        ([p_mid_l, p_bl, p_base_b],   c_mid),
        # Rear barb step closing the palm base solidly
        ([p_bl, p_base_f, p_base_b],  c_rst),
        ([p_br, p_base_b, p_base_f],  c_rst),
    ):
        c_f = jit(col, rng, 0.05) if rng else col
        mb.fp(tri, 'iron', c_f, fwd, ctr, smooth=False)


def _add_barnacle_coral_cluster(mb, center, normal_dir, rng, scale=1.0, add_coral=True):
    """Salt-crusted pale barnacle cones ('skull_stone') + coastal coral knobs ('limestone')."""
    c = Vector(center)
    nd = Vector(normal_dir).normalized()
    rot_n = Vector((0.0, 1.0, 0.0)).rotation_difference(nd).to_matrix().to_4x4()
    with xf(mb, T(c) @ rot_n):
        for bi in range(3):
            ang = 2.0 * pi * bi / 3.0 + rng.uniform(-0.35, 0.35)
            dist = (0.04 + 0.13 * (bi > 0)) * scale
            r_b = rng.uniform(0.058, 0.095) * scale
            h_b = rng.uniform(0.075, 0.135) * scale
            with xf(mb, T(cos(ang) * dist, 0.0, sin(ang) * dist) @ R('X', rng.uniform(-14, 14))):
                cyl(mb, r_b, -0.02 * scale, h_b, 5, 'skull_stone',
                    jit(C_BARNACLE_HI if bi % 2 == 0 else C_BARNACLE_MID, rng, 0.06),
                    False, 0.0, r_b * 0.44)
        if add_coral:
            for ci in (-1, 1):
                p0 = Vector((ci * 0.07 * scale, 0.0, 0.07 * scale))
                p1 = p0 + Vector((ci * 0.13 * scale, 0.21 * scale, 0.07 * scale))
                tube(mb, [p0, p1], [0.056 * scale, 0.026 * scale], 4, 'limestone',
                     C_CORAL_WARM if ci < 0 else C_CORAL_PALE, mode='flat')


def gen_sunken_anchor_memorial(outdir):
    """Iconic ~6.8 m tall salt-crusted iron galleon anchor impaled dramatically at a ~16 deg angle
    into a multi-tiered mossy stratified coastal limestone rock pedestal (y = -3.6..+1.4 m deep
    anti-float rock base!).
    Features a heavy octagonal iron shank, timber-and-iron bolted cross-stock, twin swept pointed
    barbed flukes with barnacle/coral clusters, top shackle ring with thick draped forged-iron
    chain links looping down around two stubby oak mooring bollards on the rock ledge, a
    wind-whipped tattered crimson pennant tied below the stock (UV2 wind weights!), and a brass
    storm-lantern hanging from the cross-stock arm ('Lantern_Anchor').
    Target: 2,600-3,500 visual tris, 2 colliders (col_anchor_base, col_anchor_shank).
    """
    clear_scene()
    rng = random.Random(SEED + 2207)
    mb = MB('SunkenAnchorMemorial', seed=2207)

    ROCK_BOT = -3.60
    col_base_pts = []
    col_shank_pts = []

    # 1. Multi-Tiered Mossy Stratified Coastal Limestone Rock Pedestal (y = -3.60..+1.45 m!)
    # Deep buried octagonal anti-float foundation core (hidden cleanly inside tiered sculpted coastal rock shelves!)
    ped_secs = [
        _reg_oct(0.0, ROCK_BOT, 0.0, 3.15, rot_deg=18.0),
        _reg_oct(0.0, -1.75,    0.0, 2.82, rot_deg=20.0),
        _reg_oct(0.0,  0.18,    0.0, 2.38, rot_deg=22.0),
    ]
    _loft_horizontal_masonry(
        mb, ped_secs, 'limestone_moss',
        [mix(C_LIME_DARK, C_SEA_MOSS, 0.68), mix(C_LIME_SHADE, C_SEA_MOSS, 0.44), C_LIME_MID],
        rng, caps=(True, True), top_mat='limestone_moss', top_col=C_LIME_MID,
    )
    for ring in ped_secs:
        col_base_pts.extend(Vector(p) for p in ring)

    # Multi-tiered sculpted stratified coastal limestone rock crags forming natural stepped tide ledges!
    col_base_pts += sculpt_rock_mass(
        mb, (0.05, 0.25, 0.12), (2.42, 1.38, 2.18), 'limestone_moss',
        C_LEDGE_MOSS, C_LIME_WARM, C_LIME_DARK, rng,
        subdiv=2, warp=0.22, strata=0.20, flat_top=0.66, base_flare=0.32,
        rot_deg=(2, 18, -3), crag_ribs=6, rib_amp=0.16, moss_cap=0.68,
    )
    col_base_pts += sculpt_rock_mass(
        mb, (-1.18, -0.05, -0.52), (1.52, 1.32, 1.48), 'limestone',
        C_LIME_PALE, C_LIME_WARM, C_LIME_SHADE, rng,
        subdiv=1, warp=0.20, strata=0.18, flat_top=0.62, base_flare=0.36,
        rot_deg=(-3, 32, 4), crag_ribs=5, rib_amp=0.14, moss_cap=0.42,
    )
    col_base_pts += sculpt_rock_mass(
        mb, (1.24, -0.08, -0.44), (1.48, 1.28, 1.44), 'limestone_moss',
        C_LEDGE_MOSS, C_LIME_MID, C_LIME_DARK, rng,
        subdiv=1, warp=0.20, strata=0.16, flat_top=0.60, base_flare=0.36,
        rot_deg=(4, -26, -4), crag_ribs=5, rib_amp=0.12, moss_cap=0.62,
    )
    # Chunky stratified coastal limestone ledge slabs around the outer skirt perimeter
    for sb_p, sb_s, sb_y in (
        ((-1.95, 0.42,  1.12), (1.12, 0.72, 0.94),  22.0),
        (( 1.92, 0.38,  1.08), (1.08, 0.68, 0.92), -26.0),
        (( 0.04, 0.34, -1.78), (1.46, 0.62, 0.88),   8.0),
    ):
        sculpt_stone_block(
            mb, sb_p, sb_s, 'limestone_moss', C_LIME_WARM, rng,
            chip=0.075, M=R('Y', sb_y), moss_col=C_LEDGE_MOSS,
        )

    # 2. Iconic ~6.8 m Tall Salt-Crusted Iron Galleon Anchor Impaled at ~16 deg Angle!
    M_anc = T(0.10, 1.18, 0.18) @ R('Y', -24.0) @ R('Z', 16.0) @ R('X', -4.0)

    def _aw(p):
        return M_anc @ Vector(p)

    with xf(mb, M_anc):
        # 2a. Heavy Octagonal Salt-Crusted Iron Shank (y_local = -0.65 .. +5.18 m -> world peak ~6.8 m!)
        shank_rings = [
            (-0.65, 0.34, C_IRON_RUST),
            ( 0.10, 0.32, C_IRON),
            ( 1.25, 0.27, C_SALT_IRON),
            ( 2.65, 0.23, C_IRON),
            ( 3.95, 0.20, C_IRON_RUST),
            ( 4.65, 0.19, C_SALT_IRON),
            ( 5.18, 0.21, C_IRON),
        ]
        shank_secs = []
        shank_cols = []
        for sy, sr, sc in shank_rings:
            shank_secs.append(_reg_oct(0.0, sy, 0.0, sr, rot_deg=22.5))
            shank_cols.append(jit(sc, rng, 0.05))
        loft(mb, shank_secs, 'iron', C_IRON, closed=True, caps=(True, True), mode='flat', scols=shank_cols)

        cyl(mb, 0.38, -0.52, 0.14, 8, 'iron', C_IRON_RUST, False, 0.0, 0.34)
        cbox(mb, (0.0, 4.78, 0.0), (0.46, 0.64, 0.46), 'iron', C_IRON, 0.03)
        cbox(mb, (0.0, 5.26, 0.0), (0.34, 0.38, 0.34), 'iron', C_IRON_RUST, 0.025)

        # 2b. Twin Swept Pointed Barbed Flukes curving gracefully from the forged crown boss!
        for sgn_x in (-1.0, 1.0):
            arm_path = [
                Vector((sgn_x * 0.16, -0.20, 0.0)),
                Vector((sgn_x * 0.72, -0.18, 0.0)),
                Vector((sgn_x * 1.24,  0.14, 0.0)),
                Vector((sgn_x * 1.58,  0.70, 0.0)),
                Vector((sgn_x * 1.72,  1.34, 0.0)),
            ]
            arm_rads = [0.27, 0.24, 0.21, 0.175, 0.135]
            arm_cols = [C_IRON_RUST, C_IRON, C_SALT_IRON, C_IRON, C_IRON_RUST]
            tube(mb, arm_path, arm_rads, 6, 'iron', C_IRON, mode='flat', scols=arm_cols)

            tip_dir = (arm_path[-1] - arm_path[-2]).normalized()
            _build_fluke_palm(mb, arm_path[-1], tip_dir, Vector((0.0, 0.0, 1.0)), rng=rng)

        # 2c. Heavy Timber-and-Iron Bolted Cross-Stock (spanning perpendicular to flukes along local Z!)
        for sgn_x in (-1.0, 1.0):
            stock_secs = []
            stock_cols = []
            for sz_k, hw_x, hh_y, col_st in (
                (-1.72, 0.10, 0.13, C_DRIFTWOOD),
                (-0.88, 0.14, 0.18, C_TIMBER_MID),
                ( 0.00, 0.17, 0.22, C_TIMBER_DARK),
                ( 0.88, 0.14, 0.18, C_TIMBER_MID),
                ( 1.72, 0.10, 0.13, C_DRIFTWOOD),
            ):
                cx_b = sgn_x * (0.04 + hw_x)
                ring = [
                    Vector((cx_b - hw_x, 4.78 - hh_y, sz_k)),
                    Vector((cx_b + hw_x, 4.78 - hh_y, sz_k)),
                    Vector((cx_b + hw_x, 4.78 + hh_y, sz_k)),
                    Vector((cx_b - hw_x, 4.78 + hh_y, sz_k)),
                ]
                stock_secs.append(ring)
                stock_cols.append(jit(col_st, rng, 0.05))
            loft(mb, stock_secs, 'timber', C_TIMBER_MID, closed=True, caps=(True, True),
                 mode='flat', scols=stock_cols)

        for sz_h, bw_h, bh_h in (
            (-1.46, 0.36, 0.35), (-0.78, 0.44, 0.42), (-0.28, 0.50, 0.48),
            ( 0.28, 0.50, 0.48), ( 0.78, 0.44, 0.42), ( 1.46, 0.36, 0.35),
        ):
            cbox(mb, (0.0, 4.78, sz_h), (bw_h, bh_h, 0.095), 'iron',
                 C_IRON_RUST if abs(sz_h) > 1.0 else C_IRON, 0.0)
            for sgn_bx in (-1.0, 1.0):
                cbox(mb, (sgn_bx * (bw_h * 0.5 + 0.02), 4.78, sz_h), (0.055, 0.08, 0.08),
                     'iron', C_SALT_IRON, 0.0)

        # 2d. Massive Forged-Iron Top Shackle Ring (peaking cleanly at world y ≈ 6.82 m!)
        with xf(mb, T(0.0, 5.66, 0.0) @ M_Y2Z):
            torus(mb, 0.44, 0.072, 8, 5, 'iron', C_IRON, False)
        with xf(mb, T(0.0, 5.26, 0.0) @ M_Y2X):
            cyl(mb, 0.095, -0.24, 0.24, 6, 'iron', C_IRON_RUST, False, 0.0)

        # 2e. Salt-Crusted Barnacle & Coastal Coral Clusters embedded snugly into lower shank & flukes!
        _add_barnacle_coral_cluster(mb, (-0.12, 0.48, -0.22), (-0.4, 0.15, -0.9), rng, scale=1.18, add_coral=True)
        _add_barnacle_coral_cluster(mb, ( 0.16, 0.92,  0.16), ( 0.6, 0.25,  0.7), rng, scale=1.02, add_coral=True)
        _add_barnacle_coral_cluster(mb, (-1.16, 0.14, -0.10), (-0.4, 0.75, -0.4), rng, scale=1.05, add_coral=True)
        _add_barnacle_coral_cluster(mb, ( 1.38, 0.54, -0.10), ( 0.3, 0.50, -0.8), rng, scale=0.92, add_coral=False)

        # Hemp lashing collar below cross-stock holding the fluttering crimson pennant!
        cyl(mb, 0.245, 4.10, 4.32, 8, 'rope', C_ROPE, False, 0.0)

    for lp in (
        (-1.82, 1.38, -0.35), ( 1.82, 1.48,  0.35),
        (-0.45, 0.05, -0.45), ( 0.45, 0.05,  0.45),
        (-0.40, 4.78, -1.78), ( 0.40, 4.78,  1.78),
        (-0.46, 6.08, -0.22), ( 0.46, 6.08,  0.22),
    ):
        col_shank_pts.append(_aw(lp))

    # 3. Two Stubby Oak Mooring Bollards on the Front Mossy Rock Ledge + Interlocking Iron Chains!
    bollard_specs = [
        (Vector((-1.42, 0.96, -1.04)), -6.0,  5.0),  # Port mooring bollard
        (Vector(( 1.48, 0.92, -0.92)),  6.0, -4.0),  # Starboard mooring bollard
    ]
    bollard_wraps = []
    for bpos, tilt_z, tilt_x in bollard_specs:
        with xf(mb, T(bpos) @ R('Z', tilt_z) @ R('X', tilt_x)):
            cyl(mb, 0.24, -1.65, 0.84, 7, 'timber', C_TIMBER_DARK, False, 0.0, 0.21)
            cyl(mb, 0.28,  0.82, 0.98, 7, 'timber', C_DRIFTWOOD,   False, 0.0, 0.23)
            cyl(mb, 0.25,  0.64, 0.74, 7, 'iron',   C_IRON_RUST,   False, 0.0)
            with xf(mb, T(0.0, 0.44, 0.0)):
                torus(mb, 0.27, 0.048, 6, 3, 'iron', C_IRON, False)
            with xf(mb, T(0.0, 0.55, 0.0)):
                torus(mb, 0.26, 0.044, 6, 3, 'iron', C_IRON_RUST, False)
        bollard_wraps.append(bpos + Vector((0.0, 0.50, 0.0)))
        col_base_pts.append(bpos + Vector((0.0, 1.06, 0.0)))

    # 100% physically interlocking forged-iron galleon chain (routed cleanly clear of the brass storm lantern!):
    # Drops off starboard rim of shackle ring -> starboard bollard -> draped high across front shelf -> port bollard!
    shackle_chain_pt = _aw((0.36, 5.56, 0.14))
    _add_chain_catenary(
        mb, shackle_chain_pt, bollard_wraps[1] + Vector((0.0, 0.06, 0.14)),
        sag=0.52, n_links=None, link_r=0.168, wire_r=0.048, segs=5, psegs=3, start_idx=0,
    )
    _add_chain_catenary(
        mb, bollard_wraps[1] + Vector((-0.18, 0.04, -0.14)), bollard_wraps[0] + Vector((0.18, 0.04, -0.14)),
        sag=0.22, n_links=None, link_r=0.155, wire_r=0.044, segs=5, psegs=3, start_idx=1,
    )
    _add_chain_catenary(
        mb, bollard_wraps[0] + Vector((-0.20, -0.02, 0.14)), Vector((-1.98, 0.96, -0.18)),
        sag=0.08, n_links=None, link_r=0.145, wire_r=0.040, segs=5, psegs=3, start_idx=0,
    )
    _build_rope_coil_lean(mb, (0.98, 1.06, -1.24), radius=0.28, turns=2, r=0.042, segs=6, psegs=4)

    # 4. Wind-Whipped Tattered Crimson Pennant Tied Below the Cross-Stock (UV2 Wind Weights!)
    pennant_root = _aw((0.18, 4.20, 0.08))
    _build_wind_pennant(
        mb, pennant_root, length=2.35, h0=0.58, out_dir=(0.82, -0.05, -0.56),
        col_main=C_PAINT_RED, col_trim=C_GOLD_BRIGHT, phase=0.28,
    )

    # 5. Brass Storm-Lantern Hanging Plumb from Forward Cross-Stock Arm ('Lantern_Anchor')!
    stock_hook_world = _aw((0.0, 4.58, -1.36))
    with xf(mb, T(stock_hook_world) @ M_Y2Z):
        torus(mb, 0.075, 0.022, 6, 4, 'iron', C_IRON, False)
    lantern_pos = stock_hook_world + Vector((0.0, -0.86, 0.0))
    _add_chain_catenary(
        mb, stock_hook_world + Vector((0.0, -0.04, 0.0)), lantern_pos + Vector((0.0, 0.44, 0.0)),
        sag=0.0, n_links=None, link_r=0.068, wire_r=0.020, segs=5, psegs=3,
    )
    _build_harbour_lantern(mb, lantern_pos, scale=1.28, brass_body=True)

    # 6. Coastal Crevice Kelp Drapes ('foliage' + UV2 wind weights!) hanging visibly over outer ledges
    for anc, klen, kw, kdir, kph in (
        ((-2.28, 0.88, -0.22), 1.48, 0.25, (-0.96, 0.0, -0.28), 0.16),
        (( 2.26, 0.84,  0.28), 1.38, 0.24, ( 0.94, 0.0,  0.34), 0.64),
    ):
        _add_kelp_drape(mb, anc, klen, kw, kdir, rng, phase=kph, segs=4)

    build(mb)

    add_empty('Lantern_Anchor', lantern_pos)
    col_piece('col_anchor_base',  col_base_pts)
    col_piece('col_anchor_shank', col_shank_pts)
    export_landmark_glb(outdir, 'sunken_anchor_memorial.glb')


# ================================================================ 3. ANCIENT SUN DIAL PLAZA

def _build_sun_brazier(mb, base_pos, rng=None):
    """Ornate golden altar flame brazier ('brass' + carved 'temple_stone' + blazing 'glass' embers)."""
    bx, by, bz = base_pos
    with xf(mb, T(bx, by, bz)):
        # Stepped carved octagonal stone plinth base
        cyl(mb, 0.44, -0.04, 0.16, 8, 'temple_stone', C_TEMPLE_MID, False, 0.0, 0.36)
        cyl(mb, 0.26,  0.16, 0.56, 8, 'temple_stone', C_TEMPLE_HI,  False, 0.0, 0.22)
        # 4 sculpted brass tripod scroll legs clutching the bowl
        for k in range(4):
            ang = k * pi * 0.5 + pi * 0.25
            ca, sa = cos(ang), sin(ang)
            _add_beam(mb, (ca * 0.34, 0.14, sa * 0.34), (ca * 0.42, 0.72, sa * 0.42),
                      0.068, 0.068, 'brass', C_TEMPLE_GOLD, 0.0)
        # Flared golden brass fire basin
        bowl_prof = [
            (0.00, 0.52),
            (0.24, 0.54),
            (0.46, 0.74),
            (0.52, 0.92),
            (0.42, 0.94),
            (0.34, 0.78),
            (0.00, 0.72),
        ]
        lathe(mb, bowl_prof, 8, 'brass', C_GOLD_BRIGHT, False, False,
              lambda i, k: C_BRASS_DARK if i >= 5 else (C_GOLD_BRIGHT if i in (2, 3) else C_BRASS))
        # Dark scorched ember coal bed ('basalt')
        cyl(mb, 0.36, 0.74, 0.88, 7, 'basalt', C_BASALT_DARK, False, 0.0, 0.28)
        # Blazing multi-tongue sculpted amber flame cluster ('glass')
        for fx, fz, fh, fr, rot_z, col_f in (
            ( 0.00,  0.00, 0.44, 0.14,   4.0, C_MAGMA_WHITE),
            (-0.12, -0.06, 0.32, 0.10,  16.0, C_LANTERN_GL),
            ( 0.12,  0.05, 0.34, 0.10, -14.0, C_LANTERN_GL),
            ( 0.02, -0.11, 0.28, 0.09,   8.0, C_MAGMA_GLOW),
        ):
            with xf(mb, T(fx, 0.86, fz) @ R('Z', rot_z)):
                cyl(mb, fr, 0.0, fh, 5, 'glass', col_f, False, 0.0, 0.015)


def gen_ancient_sun_dial_plaza(outdir):
    """Sunlit stepped octagonal mossy temple stone dais (~7.4 m diameter, deep tapered ashlar
    foundation skirt y = -3.40..+0.75 m so outer steps NEVER overhang slopes!).
    Features radial carved limestone compass floor slabs inlaid with gleaming golden brass 8-point
    sunburst rings & raised cardinal hour-marker plinths, a bold tilted carved stone-and-brass
    triangular gnomon obelisk at center (~4.45 m high) with turquoise glowing sun-rune crystal
    inset ('skull_glow'), 2 crumbling moss-capped perimeter pillar stubs, wind-swaying draped
    jungle ivy/vines ('foliage' + UV2), and a golden altar flame brazier ('Lantern_Sundial').
    Target: 2,900-3,800 visual tris, 2 colliders (col_plaza_dais, col_plaza_gnomon; walkway open!).
    """
    clear_scene()
    rng = random.Random(SEED + 2311)
    mb = MB('AncientSunDialPlaza', seed=2311)

    SKIRT_BOT = -3.40
    FLOOR_Y   =  0.75
    col_dais_pts = []
    col_gnomon_pts = []

    # 1. Stepped Octagonal Mossy Temple Stone Dais & Deep Tapered Ashlar Foundation Skirt!
    skirt_secs = [
        _reg_oct(0.0, SKIRT_BOT, 0.0, 4.35, rot_deg=22.5),
        _reg_oct(0.0, -1.60,     0.0, 4.06, rot_deg=22.5),
        _reg_oct(0.0, -0.06,     0.0, 3.84, rot_deg=22.5),
        _reg_oct(0.0,  0.28,     0.0, 3.72, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, skirt_secs, 'limestone_moss',
        [mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.64), mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.42),
         mix(C_TEMPLE_MID, C_LEDGE_MOSS, 0.28), mix(C_TEMPLE_HI, C_LEDGE_MOSS, 0.22)],
        rng, caps=(True, True), top_mat='temple_stone', top_col=C_TEMPLE_HI,
    )
    for ring in skirt_secs:
        col_dais_pts.extend(Vector(p) for p in ring)

    # Step 2 (r = 3.36 m, y = 0.26..0.52 m) & Top Plaza Deck (r = 3.00 m, y = 0.50..0.75 m)
    step2_secs = [
        _reg_oct(0.0, 0.26, 0.0, 3.38, rot_deg=22.5),
        _reg_oct(0.0, 0.52, 0.0, 3.32, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, step2_secs, 'temple_stone', [C_TEMPLE_MID, C_TEMPLE_HI],
        rng, caps=(False, True), top_mat='temple_stone', top_col=C_TEMPLE_HI,
    )
    step3_secs = [
        _reg_oct(0.0, 0.50,    0.0, 3.04, rot_deg=22.5),
        _reg_oct(0.0, FLOOR_Y, 0.0, 2.98, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, step3_secs, 'temple_stone', [C_TEMPLE_HI, C_LIME_WARM],
        rng, caps=(False, True), top_mat='limestone', top_col=C_LIME_MID,
    )
    col_dais_pts.extend(Vector(p) for p in step3_secs[-1])

    # 1b. Hand-hewn chipped mossy temple corner blocks anchoring the octagonal dais steps & grounding skirt!
    for k in range(8):
        ang = radians(22.5 + k * 45.0)
        ca, sa = cos(ang), sin(ang)
        sculpt_stone_block(
            mb, (ca * 3.44, 0.28, sa * 3.44), (0.64, 0.42, 0.56), 'temple_stone',
            C_TEMPLE_MID if k % 2 == 0 else C_TEMPLE_HI, rng, chip=0.05,
            M=R('Y', -degrees(ang)), moss_col=C_LEDGE_MOSS,
        )
    for sb_p, sb_s, sb_y in (
        ((-3.52, 0.14,  2.06), (0.86, 0.44, 0.72),  26.0),
        (( 3.56, 0.14,  1.92), (0.82, 0.42, 0.70), -28.0),
        (( 0.24, 0.12,  3.74), (0.94, 0.38, 0.68),  12.0),
    ):
        sculpt_stone_block(
            mb, sb_p, sb_s, 'limestone_moss', C_TEMPLE_MID, rng,
            chip=0.06, M=R('Y', sb_y), moss_col=C_LEDGE_MOSS,
        )

    # 2. Radial Carved Limestone Compass Floor Slabs & Gleaming Golden Brass 8-Point Sunburst Inlays!
    r_in_slab = 1.02
    r_out_slab = 2.86
    for k in range(8):
        a0 = radians(22.5 + k * 45.0 + 1.6)
        a1 = radians(22.5 + (k + 1) * 45.0 - 1.6)
        slab_col = jit(C_LIME_PALE if k % 2 == 0 else C_LIME_WARM, rng, 0.04)
        p00 = Vector((cos(a0) * r_in_slab,  FLOOR_Y,        sin(a0) * r_in_slab))
        p01 = Vector((cos(a1) * r_in_slab,  FLOOR_Y,        sin(a1) * r_in_slab))
        p11 = Vector((cos(a1) * r_out_slab, FLOOR_Y,        sin(a1) * r_out_slab))
        p10 = Vector((cos(a0) * r_out_slab, FLOOR_Y,        sin(a0) * r_out_slab))
        dy_s = Vector((0.0, 0.032, 0.0))
        q_top = [p00 + dy_s, p01 + dy_s, p11 + dy_s, p10 + dy_s]
        ctr_s = sum(q_top, Vector()) * 0.25 - Vector((0.0, 0.15, 0.0))
        mb.fp(q_top, 'limestone', slab_col, (cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5)), ctr_s, smooth=False)
        mb.fp([p10, p11, p11 + dy_s, p10 + dy_s], 'limestone', mul(slab_col, 0.86),
              (1, 0, 0), Vector((0.0, FLOOR_Y, 0.0)), smooth=False)

    # Gleaming inlaid golden brass concentric compass rings (r = 1.46 m & r = 2.46 m) + 16 brass degree ticks!
    for r_ring, w_ring, col_r in ((1.46, 0.09, C_TEMPLE_GOLD), (2.46, 0.11, C_GOLD_BRIGHT)):
        r_i = r_ring - w_ring * 0.5
        r_o = r_ring + w_ring * 0.5
        ring_prof = [
            (r_i, FLOOR_Y + 0.025),
            (r_o, FLOOR_Y + 0.025),
            (r_o, FLOOR_Y + 0.056),
            (r_i, FLOOR_Y + 0.056),
            (r_i, FLOOR_Y + 0.025),
        ]
        lathe(mb, ring_prof, 16, 'brass', col_r, False, False)
    for tk in range(16):
        if tk % 2 == 0:
            continue
        ang_t = tk * pi / 8.0
        cbox(mb, (cos(ang_t) * 2.16, FLOOR_Y + 0.046, sin(ang_t) * 2.16), (0.34, 0.038, 0.068),
             'brass', C_GOLD_BRIGHT, 0.0, M=R('Y', -degrees(ang_t)))

    # 8 Radiating Golden Brass Sunburst Rays + Raised Hour-Marker Plinths (4 tall cardinal, 4 low intercardinal!)
    for k in range(8):
        ang = k * pi * 0.25
        is_cardinal = (k % 2 == 0)
        ca, sa = cos(ang), sin(ang)
        ray_len = 1.62 if is_cardinal else 1.24
        ray_w = 0.14 if is_cardinal else 0.09
        ray_r = 1.02 + ray_len * 0.5
        cbox(mb, (ca * ray_r, FLOOR_Y + 0.044, sa * ray_r), (ray_len, 0.040, ray_w),
             'brass', C_GOLD_BRIGHT if is_cardinal else C_TEMPLE_GOLD, 0.0, M=R('Y', -degrees(ang)))

        if k == 6:
            continue
        pl_r = 2.68
        px, pz = ca * pl_r, sa * pl_r
        if is_cardinal:
            cbox(mb, (px, FLOOR_Y + 0.22, pz), (0.44, 0.44, 0.36), 'temple_stone',
                 C_TEMPLE_HI, 0.0, M=R('Y', -degrees(ang)))
            cbox(mb, (px, FLOOR_Y + 0.46, pz), (0.32, 0.08, 0.26), 'brass',
                 C_GOLD_BRIGHT, 0.0, M=R('Y', -degrees(ang)))
            cbox(mb, (px, FLOOR_Y + 0.53, pz), (0.14, 0.10, 0.14), 'brass',
                 C_TEMPLE_GOLD, 0.0, M=R('Y', -degrees(ang) + 45.0))
            cbox(mb, (ca * 2.48, FLOOR_Y + 0.22, sa * 2.48), (0.04, 0.14, 0.14), 'skull_glow',
                 C_RUNE_MID, 0.0, M=R('Y', -degrees(ang)) @ R('X', 45.0))
        else:
            cbox(mb, (px, FLOOR_Y + 0.12, pz), (0.30, 0.24, 0.26), 'temple_stone',
                 C_TEMPLE_MID, 0.0, M=R('Y', -degrees(ang)))
            cbox(mb, (px, FLOOR_Y + 0.25, pz), (0.20, 0.055, 0.18), 'brass',
                 C_BRASS, 0.0, M=R('Y', -degrees(ang)))

    # 3. Bold Tilted Carved Stone-and-Brass Triangular Gnomon Obelisk at Center (~4.58 m High!)
    gped_secs = [
        _reg_oct(0.0, FLOOR_Y - 0.02, 0.0, 1.04, rot_deg=22.5),
        _reg_oct(0.0, FLOOR_Y + 0.32, 0.0, 0.94, rot_deg=22.5),
        _reg_oct(0.0, FLOOR_Y + 0.58, 0.0, 0.78, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, gped_secs, 'temple_stone', [C_TEMPLE_MID, C_TEMPLE_HI, C_LIME_PALE],
        rng, caps=(False, True), top_mat='temple_stone', top_col=C_TEMPLE_HI,
    )
    cyl(mb, 0.97, FLOOR_Y + 0.22, FLOOR_Y + 0.32, 8, 'brass', C_GOLD_BRIGHT, False, 0.0)
    for k in range(4):
        ang = k * pi * 0.5 + pi * 0.25
        cbox(mb, (cos(ang) * 0.88, FLOOR_Y + 0.24, sin(ang) * 0.88), (0.28, 0.34, 0.22),
             'temple_stone', C_TEMPLE_MID, 0.0, M=R('Y', -degrees(ang)))
        cbox(mb, (cos(ang) * 0.88, FLOOR_Y + 0.43, sin(ang) * 0.88), (0.22, 0.055, 0.16),
             'brass', C_GOLD_BRIGHT, 0.0, M=R('Y', -degrees(ang)))
    for ring in gped_secs:
        col_gnomon_pts.extend(Vector(p) for p in ring)

    # Sculpted tilted triangular carved stone gnomon obelisk fin sweeping upward toward -Z (y = 1.28..4.58 m!)
    gnomon_secs = [
        (1.26, -0.62,  0.66, 0.34, C_TEMPLE_MID),
        (1.98, -0.82,  0.54, 0.29, C_TEMPLE_HI),
        (2.86, -1.04,  0.34, 0.23, C_TEMPLE_HI),
        (3.76, -1.26,  0.02, 0.16, C_LIME_PALE),
        (4.36, -1.40, -0.34, 0.10, C_LIME_PALE),
    ]
    g_rings = []
    g_cols = []
    for gy, zf, zb, hwx, gc in gnomon_secs:
        zm = 0.5 * (zf + zb)
        ring = [
            Vector(( 0.0, gy, zf)),
            Vector(( hwx, gy, zm)),
            Vector(( 0.0, gy, zb)),
            Vector((-hwx, gy, zm)),
        ]
        g_rings.append(ring)
        g_cols.append(jit(gc, rng, 0.04))
        col_gnomon_pts.extend(ring)
    loft(mb, g_rings, 'temple_stone', C_TEMPLE_HI, closed=True, caps=(True, False), mode='flat', scols=g_cols)

    # Sharp sculpted golden-brass solar apex finial crowning the gnomon tip at y ≈ 4.58 m!
    g_apex = Vector((0.0, 4.58, -1.08))
    col_gnomon_pts.append(g_apex)
    top_r = g_rings[-1]
    for k in range(4):
        kn = (k + 1) % 4
        mb.fp([top_r[k], top_r[kn], g_apex], 'brass', C_GOLD_BRIGHT, (0, 1, 0),
              Vector((0.0, 4.10, -0.88)), smooth=False)

    # Gleaming golden-brass spine ribs hugging BOTH front slanted edge & rear dorsal edge of the gnomon!
    _add_beam(mb, (0.0, 1.24, -0.63), (0.0, 4.44, -1.39), 0.11, 0.13, 'brass', C_GOLD_BRIGHT, 0.0)
    _add_beam(mb, (0.0, 1.24,  0.67), (0.0, 4.38, -0.35), 0.10, 0.11, 'brass', C_TEMPLE_GOLD, 0.0)
    # Tightly fitted golden-brass horizontal inlaid bands matching the exact diamond cross-section at each level!
    for idx_b in (1, 2, 3):
        gy_b, zf_b, zb_b, hwx_b, _ = gnomon_secs[idx_b]
        zm_b = 0.5 * (zf_b + zb_b)
        b_pad = 0.032
        br0 = [
            Vector((0.0, gy_b - 0.045, zf_b - b_pad)),
            Vector((hwx_b + b_pad, gy_b - 0.045, zm_b)),
            Vector((0.0, gy_b - 0.045, zb_b + b_pad)),
            Vector((-hwx_b - b_pad, gy_b - 0.045, zm_b)),
        ]
        br1 = [p + Vector((0.0, 0.09, 0.0)) for p in br0]
        loft(mb, [br0, br1], 'brass', C_GOLD_BRIGHT, closed=True, caps=(True, True), mode='flat')

    # Clean Dual Gleaming Golden Brass Celestial Armillary Rings piercing the gnomon + cardinal solar pins!
    with xf(mb, T(0.0, 2.68, -0.30) @ R('X', 20.0)):
        torus(mb, 0.80, 0.056, 14, 5, 'brass', C_GOLD_BRIGHT, False)
        with xf(mb, R('Z', 90.0)):
            torus(mb, 0.74, 0.042, 14, 5, 'brass', C_TEMPLE_GOLD, False)
        for sk in range(8):
            ang_s = sk * pi * 0.25
            ca_s, sa_s = cos(ang_s), sin(ang_s)
            cbox(mb, (ca_s * 0.90, 0.0, sa_s * 0.90), (0.18, 0.055, 0.055),
                 'brass', C_GOLD_BRIGHT, 0.0, M=R('Y', -degrees(ang_s)))
        # Golden brass crest bezel cradling a glowing turquoise zenith sun-crystal right atop the meridian ring!
        with xf(mb, T(0.0, 0.78, 0.0)):
            cbox(mb, (0.0, -0.02, 0.0), (0.20, 0.10, 0.20), 'brass', C_GOLD_BRIGHT, 0.0, M=R('Y', 45.0))
            cbox(mb, (0.0,  0.10, 0.0), (0.14, 0.20, 0.14), 'skull_glow', C_RUNE_CORE, 0.0, M=R('Y', 45.0))

    # Turquoise Glowing Sun-Rune Crystal Insets ('skull_glow') seated flush into BOTH tapered flanks of the gnomon!
    for sgn_x in (-1.0, 1.0):
        c_pos = Vector((sgn_x * 0.175, 2.42, -0.24))
        M_rune = R('X', -15.0)
        cbox(mb, c_pos, (0.11, 0.78, 0.36), 'brass', C_GOLD_BRIGHT, 0.0, M=M_rune)
        cbox(mb, c_pos + Vector((sgn_x * 0.036, 0.0, 0.0)), (0.075, 0.62, 0.24),
             'basalt', C_BASALT_DARK, 0.0, M=M_rune)
        cbox(mb, c_pos + Vector((sgn_x * 0.062, 0.0, 0.0)), (0.060, 0.46, 0.17),
             'skull_glow', C_RUNE_CORE, 0.0, M=M_rune)

    # 4. Two Crumbling Moss-Capped Perimeter Pillar Stubs (Rear-Port & Rear-Starboard; walkway 100% open!)
    pillar_specs = [
        (-2.24, 1.56, 2.62, 0.42,  24.0, True),
        ( 2.30, 1.48, 1.88, 0.40, -18.0, True),
    ]
    for px, pz, ph, prad, shear_d, fallen_d in pillar_specs:
        cbox(mb, (px, FLOOR_Y + 0.18, pz), (prad * 2.42, 0.38, prad * 2.42),
             'temple_stone', C_TEMPLE_MID, 0.0, M=R('Y', 22.5))
        cyl(mb, prad * 1.12, FLOOR_Y + 0.36, FLOOR_Y + 0.48, 8, 'brass', C_TEMPLE_GOLD, False, 0.0)
        cyl(mb, prad * 1.06, FLOOR_Y + 1.18, FLOOR_Y + 1.26, 8, 'brass', C_BRASS, False, 0.0)
        p_secs = []
        p_cols = []
        for si, (frac, rm, col_p) in enumerate((
            (0.00, 1.04, C_TEMPLE_MID),
            (0.38, 0.98, C_TEMPLE_HI),
            (0.76, 0.94, mix(C_TEMPLE_HI, C_LEDGE_MOSS, 0.25)),
            (1.00, 0.90, mix(C_TEMPLE_HI, C_LEDGE_MOSS, 0.52)),
        )):
            y_base = FLOOR_Y + 0.44 + frac * (ph - 0.44)
            ring = []
            for k in range(8):
                ang = 2.0 * pi * k / 8.0 + radians(22.5)
                dy_shear = (cos(ang) * prad * 0.55 * (1.0 if shear_d > 0 else -1.0)) if si == 3 else 0.0
                ring.append(Vector((px + cos(ang) * prad * rm, y_base + dy_shear, pz + sin(ang) * prad * rm)))
            p_secs.append(ring)
            p_cols.append(jit(col_p, rng, 0.05))
        _loft_horizontal_masonry(
            mb, p_secs, 'limestone_moss', p_cols, rng, caps=(False, True),
            top_mat='limestone_moss', top_col=mix(C_LEDGE_MOSS, C_GRASS_SUN, 0.34),
        )
        sculpt_stone_block(
            mb, (px * 1.18, FLOOR_Y - 0.18, pz * 1.14), (0.68, 0.46, 0.54),
            'temple_stone', C_TEMPLE_MID, rng, chip=0.05, M=R('Y', 32.0 if px < 0 else -28.0),
            moss_col=C_LEDGE_MOSS,
        )
        if fallen_d:
            sgn_p = -1.0 if px < 0 else 1.0
            with xf(mb, T(sgn_p * 2.96, 0.64, 1.08) @ R('Y', sgn_p * -28.0) @ R('Z', sgn_p * -84.0)):
                cyl(mb, 0.36, -0.52, 0.52, 8, 'limestone_moss', C_TEMPLE_HI, False, 0.0, 0.34)
                cyl(mb, 0.38, -0.06,  0.06, 8, 'brass', C_TEMPLE_GOLD, False, 0.0)

    # 5. Golden Altar Flame Brazier at Forward Ceremonial Axis ('Lantern_Sundial')!
    brazier_base = Vector((0.0, FLOOR_Y + 0.02, -1.78))
    _build_sun_brazier(mb, brazier_base, rng=rng)
    lantern_pos = brazier_base + Vector((0.0, 1.12, 0.0))

    # 6. Wind-Swaying Draped Jungle Ivy/Vines (anchored cleanly INSIDE stonework!) & Perimeter Ferns ('foliage' + UV2!)
    vine_specs = [
        ((-2.34, FLOOR_Y + 2.38,  1.86), 2.30, 0.27, (-0.38, 0.0,  0.92), 0.10),
        ((-2.54, FLOOR_Y + 2.15,  1.52), 2.10, 0.26, (-0.96, 0.0,  0.26), 0.24),
        (( 2.52, FLOOR_Y + 1.66,  1.66), 1.80, 0.25, ( 0.78, 0.0,  0.62), 0.42),
        (( 2.24, FLOOR_Y + 1.62,  1.78), 1.65, 0.23, ( 0.18, 0.0,  0.98), 0.56),
        ((-2.90, FLOOR_Y - 0.04, -1.16), 1.45, 0.24, (-0.92, 0.0, -0.38), 0.70),
        (( 2.92, FLOOR_Y - 0.04, -1.10), 1.40, 0.24, ( 0.92, 0.0, -0.38), 0.82),
        ((-0.20, FLOOR_Y - 0.04,  2.90), 1.50, 0.24, (-0.08, 0.0,  0.99), 0.94),
    ]
    for anc, vlen, vw, vdir, vph in vine_specs:
        _add_leafy_vine_drape(mb, anc, vlen, vw, vdir, rng, phase=vph)

    for fpos, fsc, nf, fph, flean in (
        ((-2.85, 0.54,  2.18), 0.98, 5, 0.14, (-0.8, 0.0,  0.6)),
        (( 2.92, 0.52,  2.05), 0.94, 5, 0.36, ( 0.8, 0.0,  0.6)),
        (( 0.24, 0.52,  3.12), 0.90, 5, 0.62, ( 0.1, 0.0,  0.99)),
        ((-3.24, 0.28, -1.64), 0.88, 4, 0.78, (-0.9, 0.0, -0.4)),
        (( 3.26, 0.28, -1.58), 0.86, 4, 0.92, ( 0.9, 0.0, -0.4)),
    ):
        _add_jungle_fern_cluster(mb, fpos, scale=fsc, n_fronds=nf, rng=rng, phase=fph, lean_dir=flean)

    build(mb)

    add_empty('Lantern_Sundial', lantern_pos)
    col_piece('col_plaza_dais',   col_dais_pts)
    col_piece('col_plaza_gnomon', col_gnomon_pts)
    export_landmark_glb(outdir, 'ancient_sun_dial_plaza.glb')


# ================================================================ 4. VOLCANIC OBSIDIAN FISSURE VENT

def gen_volcanic_obsidian_fissure_vent(outdir):
    """Dramatic ~6.0 m tall jagged hexagonal columnar black-basalt volcanic chimney formation rooted
    in a massive fractured lava-crust base skirt (y = -3.80..+1.25 m!).
    Split cleanly down the core by a deep recessed glowing molten magma fissure throat ('glass'
    with bright orange-crimson C_MAGMA_GLOW vertex-colored magma core & crust veins!), ringed with
    jagged outward-canting obsidian shard teeth, sulfur-ochre encrusted vent rims, weathered iron
    warning chain-stakes driven into the outer basalt apron, and a recessed volcanic glow empty
    ('Lantern_MagmaVent').
    Target: 2,500-3,500 visual tris, 2 colliders (col_vent_base, col_vent_chimney).
    """
    clear_scene()
    rng = random.Random(SEED + 2417)
    mb = MB('VolcanicObsidianFissureVent', seed=2417)

    SKIRT_BOT = -3.80
    col_base_pts = []
    col_chim_pts = []

    # 1. Massive Fractured Lava-Crust Base Skirt (y = -3.80..+1.25 m anti-float!)
    # Deep buried flared octagonal basalt foundation skirt plunging cleanly to y = -3.80 m!
    skirt_secs = [
        _reg_oct(0.0, SKIRT_BOT, 0.0, 4.10, rot_deg=15.0),
        _reg_oct(0.0, -1.70,     0.0, 3.72, rot_deg=18.0),
        _reg_oct(0.0,  0.32,     0.0, 3.22, rot_deg=20.0),
    ]
    _loft_horizontal_masonry(
        mb, skirt_secs, 'basalt',
        [C_BASALT_DARK, C_BASALT_DARK, C_BASALT_MID],
        rng, caps=(True, True), top_mat='basalt', top_col=C_BASALT_MID,
    )
    for ring in skirt_secs:
        col_base_pts.extend(Vector(p) for p in ring)

    # Commanding fractured lava-crust volcanic mound rising cleanly to y ≈ +1.28 m above ground!
    col_base_pts += sculpt_rock_mass(
        mb, (0.0, -0.15, 0.0), (3.32, 1.56, 3.24), 'basalt',
        C_BASALT_TOP, C_BASALT_MID, C_BASALT_DARK, rng,
        subdiv=2, warp=0.22, strata=0.14, flat_top=0.78, base_flare=0.32,
        rot_deg=(0, 16, 0), crag_ribs=7, rib_amp=0.16,
    )
    # 3 rugged fractured basalt apron shoulder buttresses sloping outward around the mound perimeter!
    for lb_pos, lb_rad, lb_rot in (
        ((-2.12, -0.22, -1.32), (1.38, 1.18, 1.32), ( 5,  28, -8)),
        (( 2.16, -0.24, -1.20), (1.42, 1.16, 1.28), (-4, -34,  7)),
        (( 0.04, -0.16,  1.96), (1.76, 1.26, 1.46), ( 6,  12, -5)),
    ):
        col_base_pts += sculpt_rock_mass(
            mb, lb_pos, lb_rad, 'basalt',
            C_BASALT_TOP, C_BASALT_MID, C_BASALT_DARK, rng,
            subdiv=1, warp=0.20, strata=0.12, flat_top=0.72, base_flare=0.36,
            rot_deg=lb_rot, crag_ribs=5, rib_amp=0.14,
        )

    # 2. Split Jagged Hexagonal Columnar Black-Basalt Volcanic Chimney (~6.05 m Tall!)
    #    Cleaved cleanly down the center (x in [-0.45, +0.45]) with dark obsidian organ-pipe walls
    #    framing the deeply recessed glowing molten magma chasm!
    chimney_cols = [
        # (bx, bz, y_bot, height, rad, tilt_x, tilt_z, sulfur_rim, pointy)
        (-0.98,  0.18,  0.10, 5.95, 0.62,  -6.5,  2.5, True,  True),   # Hero port spire peaking ~6.05 m!
        (-1.02, -0.56,  0.10, 4.75, 0.56,  -8.5, -5.0, True,  True),   # Port-front jaw column (~4.85 m)
        (-0.84,  0.94,  0.10, 5.10, 0.58,  -5.5,  7.0, True,  False),  # Port-rear cleaved flat-crown column
        (-1.68,  0.14,  0.00, 3.85, 0.52, -13.0,  1.5, False, True),   # Port outer buttress column
        (-1.54, -1.04, -0.05, 2.75, 0.46, -15.0, -8.5, True,  False),  # Port lower stepped front organ pipe
        (-1.38,  1.16, -0.05, 3.25, 0.48, -11.5, 10.0, False, False),  # Port-rear stepped basalt column
        ( 1.00,  0.14,  0.10, 5.82, 0.60,   7.0,  2.0, True,  True),   # Hero starboard spire peaking ~5.92 m!
        ( 1.04, -0.58,  0.10, 4.52, 0.55,   9.0, -4.5, True,  True),   # Starboard-front jaw column (~4.62 m)
        ( 0.86,  0.92,  0.10, 4.92, 0.57,   5.5,  6.5, True,  False),  # Starboard-rear cleaved column
        ( 1.70,  0.10,  0.00, 3.68, 0.50,  13.5,  1.0, False, True),   # Starboard outer buttress column
        ( 1.56, -1.02, -0.05, 2.65, 0.46,  15.0, -8.0, True,  False),  # Starboard lower stepped front column
        ( 1.40,  1.12, -0.05, 3.12, 0.48,  11.5,  9.5, False, False),  # Starboard-rear stepped basalt column
        # Rear volcanic saddle wall sealing behind the recessed molten throat core
        ( 0.00,  1.06,  0.10, 3.45, 0.68,   0.0,  7.5, True,  False),
    ]
    for bx, bz, yb, hh, rad, tx, tz, s_rim, p_apex in chimney_cols:
        pts_c = _sculpt_jagged_basalt_column(
            mb, (bx, yb, bz), hh, rad, tx, tz,
            C_BASALT_DARK, C_BASALT_TOP, rng, sides=6,
            magma_seam=True, sulfur_rim=s_rim, pointy_apex=p_apex,
        )
        col_chim_pts.extend(pts_c[::3])

    # 3. Ring of 10 Jagged Outward-Canting Obsidian Shard Teeth framing the vent & flanks!
    shard_specs = [
        (-1.42, 2.25, -0.96, 2.45, 0.34, -24.0, -18.0),
        ( 1.44, 2.18, -0.94, 2.38, 0.33,  25.0, -17.0),
        (-1.86, 1.55,  0.56, 2.30, 0.35, -28.0,  12.0),
        ( 1.88, 1.48,  0.54, 2.25, 0.34,  28.0,  11.0),
        (-0.96, 3.35,  1.14, 2.20, 0.30, -16.0,  22.0),
        ( 0.98, 3.28,  1.12, 2.15, 0.30,  16.0,  22.0),
        (-2.22, 0.85, -0.35, 1.85, 0.32, -32.0,  -8.0),
        ( 2.24, 0.82, -0.32, 1.82, 0.32,  32.0,  -8.0),
        (-1.12, 4.05, -0.54, 1.70, 0.25, -22.0, -16.0),
        ( 1.14, 3.92, -0.52, 1.66, 0.25,  22.0, -16.0),
    ]
    for sx, sy, sz, sh, sr, stx, stz in shard_specs:
        pts_s = _sculpt_jagged_basalt_column(
            mb, (sx, sy, sz), sh, sr, stx, stz,
            C_BASALT_DARK, mul(C_BASALT_TOP, 1.15), rng, sides=5,
            magma_seam=False, sulfur_rim=False, pointy_apex=True,
        )
        col_chim_pts.extend(pts_s[::4])

    # 4. Deep Recessed Glowing Molten Magma Fissure Throat & Crust Veins ('glass' + C_MAGMA_GLOW/CRIMSON!)
    # Recessed deeply between the twin jagged basalt walls (z_front = -0.34..+0.02 m) for rich volcanic depth!
    throat_secs = [
        (0.78, 0.56, -0.44,  0.62, C_MAGMA_GLOW),
        (1.72, 0.48, -0.34,  0.54, C_MAGMA_CRIMSON),
        (2.74, 0.40, -0.24,  0.46, C_MAGMA_GLOW),
        (3.72, 0.32, -0.14,  0.38, C_MAGMA_CRIMSON),
        (4.56, 0.20, -0.04,  0.28, C_BASALT_HOT),
    ]
    t_rings = []
    t_cols = []
    for ty, hx, zf, zb, tc in throat_secs:
        zm = 0.5 * (zf + zb)
        ring = [
            Vector(( 0.0, ty, zf)),
            Vector(( hx,  ty, zm)),
            Vector(( 0.0, ty, zb)),
            Vector((-hx,  ty, zm)),
        ]
        t_rings.append(ring)
        t_cols.append(tc)
    loft(mb, t_rings, 'glass', C_MAGMA_GLOW, closed=True, caps=(True, True), mode='flat', scols=t_cols)

    # 4b. Bubbling glowing magma fissure pool nestled squarely atop the fractured lava-crust terrace (y ≈ 1.14 m!)
    pool_rings = []
    for rm, ym in ((0.0, 1.22), (0.44, 1.18), (0.86, 1.10)):
        if rm < 1e-4:
            pool_rings.append([Vector((0.0, ym, -0.76))] * 8)
        else:
            pool_rings.append([
                Vector((cos(2.0 * pi * k / 8.0) * rm * 0.86,
                        ym + 0.03 * sin(k * 2.2),
                        -0.76 + sin(2.0 * pi * k / 8.0) * rm * 1.08))
                for k in range(8)
            ])
    for ri in range(2):
        r0, r1 = pool_rings[ri], pool_rings[ri + 1]
        c0 = C_MAGMA_GLOW if ri == 0 else C_MAGMA_CRIMSON
        c1 = C_MAGMA_CRIMSON if ri == 0 else C_BASALT_HOT
        for k in range(8):
            kn = (k + 1) % 8
            if ri == 0:
                mb.fp([r0[0], r1[kn], r1[k]], 'glass', [c0, c1, c1], (1, 0, 0),
                      Vector((0.0, 0.2, -0.76)), smooth=False)
            else:
                mb.fp([r0[k], r0[kn], r1[kn], r1[k]], 'glass', [c0, c0, c1, c1], (1, 0, 0),
                      Vector((0.0, 0.2, -0.76)), smooth=False)

    # Dark jagged cooled basalt crust slabs floating cleanly atop the molten pool!
    for cr_p, cr_r, cr_rot in (
        ((-0.32, 1.22, -0.92), (0.28, 0.11, 0.24), ( 4,  22, -6)),
        (( 0.34, 1.20, -0.74), (0.26, 0.11, 0.22), (-5, -34,  8)),
    ):
        sculpt_rock_mass(
            mb, cr_p, cr_r, 'basalt',
            C_BASALT_DARK, C_BASALT_MID, C_BASALT_HOT, rng,
            subdiv=1, warp=0.22, strata=0.06, rot_deg=cr_rot, crag_ribs=4, rib_amp=0.10,
        )

    # 4c. Jagged dark cooled basalt slag ribs anchored SOLIDLY into both left & right basalt chimney walls!
    for sy_b, sz_b, tilt_b in ((2.08, -0.34, 14.0), (3.44, -0.22, -16.0)):
        cbox(mb, (0.0, sy_b, sz_b), (1.88, 0.18, 0.26), 'basalt', C_BASALT_DARK, 0.0, M=R('Z', tilt_b))

    # 4d. 5 Surface-hugging glowing crust magma veins crawling down the rocky basalt apron & flank seams!
    apron_veins = [
        ([( 0.00, 1.24, -1.24), (-0.14, 1.12, -1.82), (-0.24, 0.86, -2.38)], [0.095, 0.072, 0.036], ( 0.0,  0.80, -0.60)),
        ([(-0.56, 1.24, -0.96), (-1.12, 1.08, -1.52), (-1.62, 0.84, -2.02)], [0.082, 0.064, 0.032], (-0.48, 0.74, -0.48)),
        ([( 0.60, 1.22, -0.94), ( 1.16, 1.06, -1.48), ( 1.66, 0.80, -1.96)], [0.082, 0.064, 0.032], ( 0.48, 0.74, -0.48)),
        ([(-1.46, 1.32, -0.24), (-1.54, 2.35, -0.30), (-1.42, 3.35, -0.22)], [0.052, 0.068, 0.032], (-0.96, 0.10, -0.26)),
        ([( 1.48, 1.30, -0.22), ( 1.56, 2.28, -0.28), ( 1.44, 3.25, -0.20)], [0.052, 0.068, 0.032], ( 0.96, 0.10, -0.26)),
    ]
    for vpath, vw, vn in apron_veins:
        _sculpt_magma_ribbon(mb, vpath, vw, vn, rng, hot_core=True)

    # 5. Sulfur-Ochre Encrusted Vent Rim Nodules embedded flush into the basalt column shoulders!
    sulfur_crusts = [
        ((-1.02, 4.66, -0.28), (0.48, 0.28, 0.42), ( 10,  18, -14), C_SULFUR_PALE),
        (( 1.04, 4.52, -0.24), (0.46, 0.26, 0.40), (-12, -22,  12), C_SULFUR_OCHRE),
        ((-1.16, 2.66, -0.68), (0.42, 0.30, 0.36), ( 14,  34, -10), C_SULFUR_OCHRE),
        (( 1.18, 2.52, -0.66), (0.40, 0.28, 0.34), (-10, -28,  16), C_SULFUR_PALE),
        ((-1.06, 1.24, -1.04), (0.54, 0.28, 0.46), (  8,  20,  -8), C_SULFUR_OCHRE),
        (( 1.08, 1.22, -1.02), (0.52, 0.26, 0.44), ( -8, -18,   8), C_SULFUR_DARK),
        (( 0.00, 3.55,  1.04), (0.64, 0.28, 0.42), ( 12,   4,   6), C_SULFUR_PALE),
    ]
    for sc_p, sc_r, sc_rot, sc_col in sulfur_crusts:
        sculpt_rock_mass(
            mb, sc_p, sc_r, 'basalt',
            sc_col, mix(sc_col, C_BASALT_HOT, 0.32), C_BASALT_DARK, rng,
            subdiv=1, warp=0.22, strata=0.08, rot_deg=sc_rot, crag_ribs=4, rib_amp=0.10,
        )

    # 6. Weathered Iron Warning Chain-Stakes Driven into the Raised Basalt Apron Shoulders!
    stake_specs = [
        (Vector((-2.44, 0.44, -1.72)), -10.0,  11.0, 1.32),
        (Vector((-0.94, 0.56, -2.52)),  -6.0,   4.0, 1.22),
        (Vector(( 0.98, 0.54, -2.50)),   6.0,  -5.0, 1.24),
        (Vector(( 2.48, 0.42, -1.66)),  10.0,  -9.0, 1.30),
    ]
    stake_eyes = []
    for spos, lx, lz, h_ab in stake_specs:
        M_st = T(spos) @ R('X', lx) @ R('Z', lz)
        with xf(mb, M_st):
            cyl(mb, 0.105, -1.15, h_ab, 6, 'iron', C_IRON, False, 0.0, 0.082)
            cyl(mb, 0.135, h_ab - 0.06, h_ab + 0.05, 6, 'iron', C_IRON_RUST, False, 0.0, 0.11)
            cyl(mb, 0.125, h_ab - 0.32, h_ab - 0.20, 6, 'iron', C_IRON_RUST, False, 0.0)
            cbox(mb, (0.0, 0.02, 0.0), (0.30, 0.16, 0.30), 'iron', C_IRON_RUST, 0.0)
            with xf(mb, T(0.0, h_ab - 0.26, -0.13) @ M_Y2Z):
                torus(mb, 0.072, 0.022, 6, 4, 'iron', C_IRON, False)
        eye_w = M_st @ Vector((0.0, h_ab - 0.26, -0.14))
        stake_eyes.append(eye_w)
        col_base_pts.append(M_st @ Vector((0.0, h_ab + 0.08, 0.0)))

    # 100% physically interlocking sagging forged-iron warning chains strung across all 4 basalt stakes!
    _add_chain_catenary(mb, stake_eyes[0], stake_eyes[1], sag=0.24, n_links=None, link_r=0.105, wire_r=0.032, segs=5, psegs=3, start_idx=0)
    _add_chain_catenary(mb, stake_eyes[1], stake_eyes[2], sag=0.28, n_links=None, link_r=0.108, wire_r=0.033, segs=5, psegs=3, start_idx=1)
    _add_chain_catenary(mb, stake_eyes[2], stake_eyes[3], sag=0.24, n_links=None, link_r=0.105, wire_r=0.032, segs=5, psegs=3, start_idx=0)

    # Scorched pirate wooden warning cross-plank bolted to the front-port stake!
    with xf(mb, T(stake_eyes[0] + Vector((0.06, 0.14, -0.08))) @ R('Y', -32.0) @ R('Z', 9.0)):
        cbox(mb, (0.0, 0.0, 0.0), (0.86, 0.28, 0.055), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
        cbox(mb, (0.0, 0.0, -0.032), (0.68, 0.18, 0.018), 'paint', C_PAINT_RED, 0.0)
        cbox(mb, (0.0, 0.0, -0.044), (0.24, 0.05, 0.014), 'paint', C_PAINT_CREAM, 0.0, M=R('Z',  42.0))
        cbox(mb, (0.0, 0.0, -0.044), (0.24, 0.05, 0.014), 'paint', C_PAINT_CREAM, 0.0, M=R('Z', -42.0))

    # 7. Recessed Volcanic Glow Empty inside the blazing molten fissure throat!
    lantern_pos = Vector((0.0, 2.72, -0.18))

    build(mb)

    add_empty('Lantern_MagmaVent', lantern_pos)
    col_piece('col_vent_base',    col_base_pts)
    col_piece('col_vent_chimney', col_chim_pts)
    export_landmark_glb(outdir, 'volcanic_obsidian_fissure_vent.glb')


STORY_CRAFT_GENERATORS = [
    gen_pirate_tavern_supply_cart,
    gen_sunken_anchor_memorial,
    gen_ancient_sun_dial_plaza,
    gen_volcanic_obsidian_fissure_vent,
]
