# Sea of Scoundrels: 4 sculpted 3D Expedition Craft Landmarks (Wave I-17 / Pass I-Q10 — 70-Landmark Milestone!).
# Imported by tools/blender/gen_island_landmarks.py.
# Authored in Godot game coordinates (-Z seaward/hero-facing, +Y up, +X starboard, metres)
# and converted to Blender's Z-up frame on mesh creation via _landmark_common.
# STRICT SHARED-TEXTURE DEDUP CONTRACT: uses ONLY the 11 existing shared PBR materials
# (limestone, limestone_moss, basalt, temple_stone, skull_stone, timber, paint, rope,
# iron, brass, foliage) + untextured glass / skull_glow / col.
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

# Harbour ashlar stone, warm beach sand, driftwood & rich ship timber
C_ASHLAR_HI      = srgb('#e2d6bc')
C_ASHLAR_MID     = srgb('#b5a88e')
C_ASHLAR_DARK    = srgb('#79705e')
C_ASHLAR_SKIRT   = srgb('#5a5448')
C_SLATE_INLAY    = srgb('#4b5359')

C_SAND_PALE      = srgb('#f0e1be')
C_SAND_WARM      = srgb('#ddb780')
C_SAND_OCHRE     = srgb('#b48a58')
C_SAND_WET       = srgb('#7d674d')
C_COBBLE_HI      = srgb('#c8bca6')
C_COBBLE_MID     = srgb('#8e8474')
C_COBBLE_DARK    = srgb('#54504a')

C_OAK_SUN        = srgb('#b8814a')
C_OAK_RICH       = srgb('#82532c')
C_OAK_DEEP       = srgb('#4f311b')
C_OAK_CHAR       = srgb('#342319')
C_DRIFT_PALE     = srgb('#cfc1a8')
C_DRIFT_MID      = srgb('#978770')
C_DRIFT_DARK     = srgb('#645848')

# Sun-baked terracotta roof tiles, crimson-gold pennants, signal sailcloth & parchment
C_TERRA_HI       = srgb('#d4613b')
C_TERRA_MID      = srgb('#b44324')
C_TERRA_DARK     = srgb('#7e2a16')
C_CRIMSON_HI     = srgb('#cc2b20')
C_CRIMSON_MID    = srgb('#941d16')
C_CRIMSON_DARK   = srgb('#5c120e')
C_CREAM_SAIL     = srgb('#eadbc0')
C_CREAM_AGED     = srgb('#ccb892')
C_TEAL_HULL      = srgb('#1e767b')
C_TEAL_DARK      = srgb('#174d52')
C_PARCHMENT_HI   = srgb('#f0e0ba')
C_PARCHMENT_MID  = srgb('#cfb584')

# Mesoamerican overgrown temple limestone & jungle moss
C_RUIN_HI        = srgb('#cfc2a5')
C_RUIN_MID       = srgb('#9a917c')
C_RUIN_DARK      = srgb('#635f51')
C_RUIN_MOSS      = srgb('#496b38')
C_RUIN_DEEP      = srgb('#434239')

# Burnished nautical brass, weathered bronze, verdigris & forged iron
C_GOLD_BRIGHT    = srgb('#f6cb4a')
C_BRASS_WARM     = srgb('#d9a33c')
C_BRASS_DARK     = srgb('#8f6522')
C_BRONZE_WARM    = srgb('#b37a3a')
C_BRONZE_DARK    = srgb('#6e4b26')
C_VERDIGRIS_HI   = srgb('#5db59e')
C_VERDIGRIS_MID  = srgb('#368471')
C_IRON_BRIGHT    = srgb('#646b7a')
C_IRON_FORGED    = srgb('#424754')
C_IRON_DARK      = srgb('#262830')
C_IRON_RUST_HI   = srgb('#8c4e2e')

# Volcanic obsidian & columnar basalt tones
C_OBSIDIAN_EDGE  = srgb('#78707e')
C_OBSIDIAN_HI    = srgb('#585160')
C_OBSIDIAN_MID   = srgb('#38333f')
C_OBSIDIAN_DARK  = srgb('#23202a')
C_OBSIDIAN_ABYSS = srgb('#15131a')

# Mystical turquoise temple glow (USED ONLY with 'skull_glow' on ancient_sun_serpent_archway!)
C_AQUA_CORE      = srgb('#7cfff0')
C_AQUA_MID       = srgb('#1fe2c6')
C_AQUA_DEEP      = srgb('#0d9588')

# Warm incandescent lantern flame, campfire embers & molten lava (USED ONLY with 'glass'!)
C_FLAME_WHITE    = srgb('#ffd354')
C_FLAME_CORE     = srgb('#ff9e1b')
C_FLAME_MID      = srgb('#ff5208')
C_FLAME_DEEP     = srgb('#bd1a04')
C_MAGMA_CRIMSON  = srgb('#780e03')

# Lush coastal sea-ivy & tropical jungle foliage
C_VINE_DARK      = srgb('#164a1e')
C_VINE_MID       = srgb('#2e7627')
C_VINE_SUN       = srgb('#7cc02b')


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


def _build_coopered_cask(mb, M_bar, radius=0.31, height=0.78, rng=None,
                         col_a=C_OAK_RICH, col_b=C_OAK_SUN, col_head=C_OAK_DEEP,
                         segs=6, stripe_col=None):
    """Chunky coopered pirate rum cask with forged-iron hoops."""
    hh = height * 0.5
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
              lambda i, k: col_head if i in (0, 3) else stave_cols[k])
        for hi_idx, (hy, hr) in enumerate(((-hh * 0.62, radius * 0.94), (hh * 0.62, radius * 0.94))):
            cyl(mb, hr, hy - 0.028, hy + 0.028, segs, 'iron',
                C_IRON_RUST_HI if hi_idx == 1 else C_IRON_FORGED, False, 0.0)
        if stripe_col is not None:
            cyl(mb, radius * 1.015, -hh * 0.15, hh * 0.15, segs, 'paint', stripe_col, False, 0.0)


def _build_rope_coil_lean(mb, center, radius=0.28, turns=2, r=0.036, segs=6, psegs=4, col=C_ROPE):
    """Chunky coiled braided hemp rope pile ('rope')."""
    for i in range(turns):
        rr = radius * (1.0 - 0.24 * i)
        with xf(mb, T(center[0], center[1] + r * (1.0 + i * 1.56), center[2])):
            torus(mb, rr, r, segs, psegs, 'rope', mul(col, 0.88 + 0.12 * (i % 2)), True)


def _add_chain_links(mb, p_start, p_end, n_links=6, link_r=0.16, wire_r=0.048,
                     segs=5, psegs=4, sag=0.24, mat='iron', rust_stride=2, stretch_y=1.42,
                     col_a=C_IRON_FORGED, col_b=C_IRON_RUST_HI):
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


def _build_wind_pennant(mb, root_pos, length=1.65, h0=0.40, out_dir=(0.76, -0.05, -0.65),
                        col_main=C_CRIMSON_HI, col_trim=C_GOLD_BRIGHT, phase=0.34):
    """Wind-whipped double-sided pirate swallowtail pennant ('paint') with UV2 wind weights."""
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
        wave = sin(t * 2.1 * pi) * 0.16 * t
        droop = -0.16 * t * t
        hh = h0 * (1.0 - 0.48 * t)
        ctr = rp + od * (length * t) + side * wave + Vector((0.0, droop, 0.0))
        top_pts.append(ctr + Vector((0.0, hh * 0.5, 0.0)))
        bot_pts.append(ctr - Vector((0.0, hh * 0.5, 0.0)))
        weights.append((t ** 1.15) * 0.94)
    for i in range(segs):
        c_seg = col_trim if i == 0 else (col_main if i % 2 == 1 else mul(col_main, 0.80))
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
        sway = sin(t * 3.1 + phase * 6.28) * 0.12 * (0.2 + 0.8 * t)
        out_off = 0.05 + 0.09 * sin(t * pi * 0.80) + 0.06 * t
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


def _add_climbing_ivy_spiral(mb, center_xz, y0, y1, r_wrap, turns, rng, phase=0.0, start_ang=0.0, segs=6):
    """Climbing coastal sea-ivy vine spiraling up a timber gazebo pillar ('foliage' + UV2)."""
    cx, cz = center_xz
    pts = []
    for i in range(segs + 1):
        t = i / float(segs)
        ang = start_ang + turns * 2.0 * pi * t
        pts.append(Vector((cx + r_wrap * cos(ang), y0 + (y1 - y0) * t, cz + r_wrap * sin(ang))))
    for i in range(segs):
        t0 = i / float(segs)
        t1 = (i + 1) / float(segs)
        p0, p1 = pts[i], pts[i + 1]
        out_v = Vector((p0.x - cx, 0.0, p0.z - cz)).normalized()
        tang = (p1 - p0).normalized()
        side = tang.cross(out_v)
        if side.length < 1e-4:
            side = Vector((0.0, 1.0, 0.0))
        side.normalize()
        w = 0.032 * (1.0 - 0.35 * t0)
        c0 = jit(mix(C_VINE_DARK, C_VINE_MID, t0), rng, 0.05)
        c1 = jit(mix(C_VINE_MID, C_VINE_SUN, t1 * 0.8), rng, 0.05)
        u0 = (0.12 + 0.30 * t0, phase)
        u1 = (0.12 + 0.30 * t1, phase)
        mb.f(
            [mb.v(p0 - side * w), mb.v(p0 + side * w), mb.v(p1 + side * w), mb.v(p1 - side * w)],
            'foliage', [c0, c0, c1, c1], [(0.2, t0), (0.8, t0), (0.8, t1), (0.2, t1)],
            smooth=False, uv2=[u0, u0, u1, u1],
        )
        # Leaf pair sprouting outward from each spiral node
        for sgn in (-1.0, 1.0):
            root = p0.lerp(p1, 0.55 if sgn > 0 else 0.25)
            o_n = Vector((root.x - cx, 0.0, root.z - cz)).normalized()
            l_dir = (o_n * 0.78 + side * (sgn * 0.45) + Vector((0.0, -0.25, 0.0))).normalized()
            l_perp = l_dir.cross(Vector((0.0, 1.0, 0.0)))
            if l_perp.length < 1e-4:
                l_perp = side
            l_perp.normalize()
            ll = rng.uniform(0.16, 0.24)
            lw = ll * 0.46
            p_b = root
            p_ml = root + l_dir * (ll * 0.45) - l_perp * lw
            p_mr = root + l_dir * (ll * 0.45) + l_perp * lw
            p_tp = root + l_dir * ll + Vector((0.0, -0.03, 0.0))
            u_b = (0.16 + 0.28 * t0, phase)
            u_m = (0.42 + 0.32 * t0, phase)
            u_e = (0.68 + 0.26 * t0, phase)
            mb.f([mb.v(p_b), mb.v(p_ml), mb.v(p_tp), mb.v(p_mr)], 'foliage',
                 [c0, c1, C_VINE_SUN, c1], [(0.5, 0.0), (0.0, 0.5), (0.5, 1.0), (1.0, 0.5)],
                 smooth=False, uv2=[u_b, u_m, u_e, u_m])


def _add_coastal_fern_cluster(mb, root_pos, scale=0.82, n_fronds=4, rng=None, phase=0.0,
                              lean_dir=None, segs=3, c_dark=C_VINE_DARK, c_mid=C_VINE_MID, c_tip=C_VINE_SUN):
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


def _sculpt_magma_ribbon(mb, path_pts, widths, surface_nrm, hot_core=True, ridge_h=0.068, mat='glass',
                         c_core=C_FLAME_CORE, c_mid_col=C_FLAME_MID, c_edge_col=C_FLAME_DEEP, c_tip_col=C_MAGMA_CRIMSON):
    """Surface-hugging glowing molten magma or rune vein ridge."""
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
        mid_pts.append(pts[i] + nrm * (ridge_h + 0.010 * sin(i * 1.7)))
    for i in range(n - 1):
        cm = c_core if (hot_core and i <= n // 2) else c_mid_col
        ce = c_edge_col if i < n - 2 else c_tip_col
        inside = (pts[i] + pts[i + 1]) * 0.5 - nrm * 0.5
        mb.fp([left_pts[i], mid_pts[i], mid_pts[i + 1], left_pts[i + 1]], mat,
              [ce, cm, cm, ce], (1, 0, 0), inside, smooth=False)
        mb.fp([mid_pts[i], right_pts[i], right_pts[i + 1], mid_pts[i + 1]], mat,
              [cm, ce, ce, cm], (1, 0, 0), inside, smooth=False)


# ==============================================================================
# 1. PIRATE CHART NAVIGATOR GAZEBO (pirate_chart_navigator_gazebo.glb)
# ==============================================================================

def gen_pirate_chart_navigator_gazebo(outdir):
    """Open-air octagonal harbour & hilltop navigator's lookout gazebo grounded on a stepped
    ashlar stone plinth (plunging to y = -2.80 m, radius ~2.55 m), six chamfered timber corner
    pillars with waist-high carved balustrades (welcoming seaward entry opening!), ornate
    scalloped terracotta-and-timber cupola roof (~5.8 m tall), gilded brass compass-rose
    weathervane finial & fluttering crimson-gold pennant ('paint' + UV2), central mounted brass
    ship's binnacle & astrolabe pedestal, climbing coastal sea-ivy ('foliage' + UV2), collider
    'col_gazebo_base', and warm hanging cupola brass lantern empty 'Lantern_NavGazebo'."""
    clear_scene()
    mb = MB('pirate_chart_navigator_gazebo', seed=1701)
    rng = random.Random(SEED + 1701)
    col_pts = []

    DECK_Y = 0.54
    PILLAR_R = 1.88
    PILLAR_TOP_Y = 3.10

    # 1. Stepped Octagonal Ashlar Stone Plinth plunging cleanly to y = -2.80 m (radius ~2.55 m)
    # Rotated by 22.5 deg so flat faces align cleanly to -Z seaward, +Z rear, and +/-X sides!
    plinth_secs = [
        _reg_poly(0.0, -2.80, 0.0, 2.54, sides=8, rot_deg=22.5),
        _reg_poly(0.0, -1.15, 0.0, 2.50, sides=8, rot_deg=22.5),
        _reg_poly(0.0,  0.00, 0.0, 2.44, sides=8, rot_deg=22.5),
        _reg_poly(0.0,  0.28, 0.0, 2.40, sides=8, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, plinth_secs, 'temple_stone',
        [C_ASHLAR_SKIRT, C_ASHLAR_DARK, C_ASHLAR_MID, C_ASHLAR_HI],
        rng, caps=(True, True), top_mat='limestone', top_col=C_ASHLAR_HI,
    )

    upper_secs = [
        _reg_poly(0.0, 0.27, 0.0, 2.22, sides=8, rot_deg=22.5),
        _reg_poly(0.0, DECK_Y, 0.0, 2.16, sides=8, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, upper_secs, 'temple_stone',
        [C_ASHLAR_MID, C_ASHLAR_HI],
        rng, caps=(False, True), top_mat='limestone', top_col=C_ASHLAR_HI,
    )

    # Collider points wrap the octagonal plinth and lower pavilion envelope
    for y_c, r_c in ((-2.80, 2.52), (0.0, 2.42), (DECK_Y, 2.18), (3.15, 2.02)):
        col_pts.extend(_reg_poly(0.0, y_c, 0.0, r_c, sides=8, rot_deg=22.5))

    # Octagonal compass-rose inlaid stone paving motif on deck floor
    cyl(mb, 1.56, DECK_Y, DECK_Y + 0.022, 8, 'limestone', C_ASHLAR_MID, False, 0.0)
    cyl(mb, 0.86, DECK_Y + 0.012, DECK_Y + 0.032, 8, 'temple_stone', C_SLATE_INLAY, False, 0.0)
    for k in range(4):
        with xf(mb, T(0.0, DECK_Y + 0.028, 0.0) @ R('Y', -k * 90.0)):
            cbox(mb, (0.0, 0.0, -0.74), (0.14, 0.022, 1.48), 'brass', C_BRASS_DARK, 0.0)

    # Welcoming seaward (-Z) ashlar stone entry steps & cheek blocks
    for si, (sy, sh, sz, sw) in enumerate((
        (0.11, 0.22, -2.40, 1.72),
        (0.28, 0.26, -2.18, 1.62),
        (0.44, 0.22, -1.96, 1.54),
    )):
        cbox(mb, (0.0, sy, sz), (sw, sh, 0.34), 'limestone',
             jit(C_ASHLAR_HI if si == 2 else C_ASHLAR_MID, rng, 0.03), 0.0)
    for sgn in (-1.0, 1.0):
        cbox(mb, (sgn * 0.94, 0.28, -2.26), (0.24, 0.56, 0.58), 'temple_stone', C_ASHLAR_MID, 0.0)
        cbox(mb, (sgn * 0.94, 0.59, -2.26), (0.28, 0.08, 0.62), 'limestone', C_ASHLAR_HI, 0.0)

    # 2. Six Chamfered Timber Corner Pillars (leaving the front -Z seaward bay wide open!)
    # Angles measured from -Z: -30, +30, +90, +150, -150, -90 deg
    pillar_angles = [-30.0, 30.0, 90.0, 150.0, -150.0, -90.0]
    pillar_pos = []
    for deg in pillar_angles:
        ar = radians(deg)
        px = PILLAR_R * sin(ar)
        pz = -PILLAR_R * cos(ar)
        pillar_pos.append(Vector((px, DECK_Y, pz)))

    for pi_idx, pp in enumerate(pillar_pos):
        px, _, pz = pp
        yaw = -pillar_angles[pi_idx]
        with xf(mb, T(px, DECK_Y, pz) @ R('Y', yaw)):
            # Carved stone plinth base shoe + gilded brass collar
            cbox(mb, (0.0, 0.14, 0.0), (0.30, 0.28, 0.30), 'temple_stone', C_ASHLAR_MID, 0.0)
            cbox(mb, (0.0, 0.31, 0.0), (0.25, 0.06, 0.25), 'brass', C_BRASS_WARM, 0.0)
            # Chamfered octagonal stout oak corner shaft (clean 8-sided chamfered profile!)
            cyl(mb, 0.122, 0.32, PILLAR_TOP_Y - DECK_Y - 0.04, 8, 'timber',
                jit(C_OAK_RICH, rng, 0.04), False, 0.0, 0.116)
            # Decorative carved mid-collar and projecting timber capital block
            cbox(mb, (0.0, 1.38, 0.0), (0.25, 0.07, 0.25), 'timber', C_OAK_DEEP, 0.0)
            cbox(mb, (0.0, PILLAR_TOP_Y - DECK_Y - 0.04, 0.0), (0.32, 0.16, 0.32), 'timber', C_OAK_SUN, 0.0)

    # 3. Upper Ring Lintel Beams, Carved Knee-Braces & Waist-High Carved Balustrades (5 bays!)
    # Bays: (0->1) is front -Z SEAWARD ENTRY (open below, ornate compass lintel above!);
    # Bays (1->2), (2->3), (3->4), (4->5), (5->0) have carved balustrades!
    for bi in range(6):
        pA = pillar_pos[bi]
        pB = pillar_pos[(bi + 1) % 6]
        mid_xz = (pA + pB) * 0.5
        span_v = pB - pA
        tang = span_v.normalized()
        out_n = Vector((mid_xz.x, 0.0, mid_xz.z)).normalized()

        # Stout upper frieze lintel beam connecting every adjacent pair of pillars
        topA = Vector((pA.x, PILLAR_TOP_Y, pA.z))
        topB = Vector((pB.x, PILLAR_TOP_Y, pB.z))
        _add_beam(mb, topA, topB, 0.20, 0.22, 'timber', C_OAK_DEEP, 0.0)

        # Twin angled carved timber knee-braces flaring from each pillar into the upper lintel
        for end_p, d_sign in ((pA, 1.0), (pB, -1.0)):
            kb0 = Vector((end_p.x, PILLAR_TOP_Y - 0.54, end_p.z)) + tang * (d_sign * 0.06)
            kb1 = Vector((end_p.x, PILLAR_TOP_Y - 0.05, end_p.z)) + tang * (d_sign * 0.46)
            _add_beam(mb, kb0, kb1, 0.095, 0.11, 'timber', C_OAK_SUN, 0.0)

        if bi == 0:
            # Welcoming Seaward Entry Archway Header Accent: gilded brass compass-star medallion!
            e_yaw = degrees(atan2(out_n.x, -out_n.z))
            with xf(mb, T(mid_xz.x, PILLAR_TOP_Y + 0.02, mid_xz.z) @ R('Y', -e_yaw)):
                cbox(mb, (0.0, 0.0, -0.12), (0.68, 0.26, 0.07), 'timber', C_OAK_SUN, 0.0)
                with xf(mb, T(0.0, 0.0, -0.165) @ M_Y2Z):
                    cyl(mb, 0.145, -0.02, 0.02, 8, 'brass', C_GOLD_BRIGHT, False, 0.0)
                    cyl(mb, 0.085, -0.032, 0.032, 4, 'paint', C_CRIMSON_HI, False, 0.0)
        else:
            # Waist-high carved balustrade (bottom sill + handrail + flanking balusters + nautical X-brace!)
            rail_y0 = DECK_Y + 0.16
            rail_y1 = DECK_Y + 0.88
            _add_beam(mb, Vector((pA.x, rail_y0, pA.z)), Vector((pB.x, rail_y0, pB.z)),
                      0.11, 0.10, 'timber', C_OAK_DEEP, 0.0)
            _add_beam(mb, Vector((pA.x, rail_y1, pA.z)), Vector((pB.x, rail_y1, pB.z)),
                      0.15, 0.10, 'timber', C_OAK_SUN, 0.0)
            for u in (0.28, 0.72):
                bp = pA.lerp(pB, u)
                _add_beam(mb, Vector((bp.x, rail_y0 + 0.04, bp.z)), Vector((bp.x, rail_y1 - 0.04, bp.z)),
                          0.068, 0.068, 'timber', C_OAK_RICH, 0.0)
            # Central carved nautical cross-brace & brass compass stud in each balustrade bay!
            b_ctr = Vector((mid_xz.x, 0.5 * (rail_y0 + rail_y1), mid_xz.z))
            b_lo_l = pA.lerp(pB, 0.30) + Vector((0.0, 0.20, 0.0))
            b_hi_r = pA.lerp(pB, 0.70) + Vector((0.0, 0.84, 0.0))
            b_lo_r = pA.lerp(pB, 0.70) + Vector((0.0, 0.20, 0.0))
            b_hi_l = pA.lerp(pB, 0.30) + Vector((0.0, 0.84, 0.0))
            _add_beam(mb, b_lo_l, b_hi_r, 0.056, 0.056, 'timber', C_OAK_SUN, 0.0)
            _add_beam(mb, b_lo_r, b_hi_l, 0.056, 0.056, 'timber', C_OAK_SUN, 0.0)
            cbox(mb, b_ctr, (0.12, 0.12, 0.12), 'brass', C_GOLD_BRIGHT, 0.0)

    # 4. Ornate Scalloped Terracotta-and-Timber Cupola Roof (y = 3.06 to 5.14 m)
    # 6-gore sweeping curved bell/ogee roof matching the 6 pillars with flared eaves & dark timber hip ribs!
    roof_profile = [
        (2.44, 3.04, C_TERRA_DARK),
        (1.94, 3.54, C_TERRA_HI),
        (1.30, 4.02, C_TERRA_MID),
        (0.66, 4.38, C_TERRA_DARK),
    ]
    roof_secs = []
    roof_cols = []
    for r_ring, y_ring, col_ring in roof_profile:
        ring_pts = []
        for gi in range(6):
            a0 = radians(pillar_angles[gi])
            a1 = radians(pillar_angles[(gi + 1) % 6])
            da = (a1 - a0)
            if da > pi:
                da -= 2.0 * pi
            elif da < -pi:
                da += 2.0 * pi
            am = a0 + 0.5 * da
            ring_pts.append(Vector((r_ring * sin(a0), y_ring, -r_ring * cos(a0))))
            r_mid = r_ring * 0.905
            y_mid = y_ring + (0.06 if r_ring > 1.8 else 0.025)
            ring_pts.append(Vector((r_mid * sin(am), y_mid, -r_mid * cos(am))))
        roof_secs.append(ring_pts)
        roof_cols.append(col_ring)

    # Outer terracotta roof shell + dark timber soffit underside!
    loft(mb, roof_secs, 'paint', C_TERRA_MID, closed=True, caps=(False, True), mode='flat', scols=roof_cols)
    soffit_secs = [
        [Vector((p.x * 0.94, p.y - 0.09, p.z * 0.94)) for p in roof_secs[0]],
        [Vector((p.x * 0.92, p.y - 0.10, p.z * 0.92)) for p in roof_secs[2]],
        [Vector((p.x * 0.90, p.y - 0.12, p.z * 0.90)) for p in roof_secs[3]],
    ]
    loft(mb, soffit_secs, 'timber', C_OAK_DEEP, closed=True, caps=(False, True), mode='flat',
         scols=[C_OAK_DEEP, C_OAK_RICH, C_OAK_DEEP], flip=True)
    eave_ring_outer = roof_secs[0]
    eave_ring_inner = soffit_secs[0]
    k_e = len(eave_ring_outer)
    for j in range(k_e):
        j1 = (j + 1) % k_e
        mb.fp([eave_ring_outer[j], eave_ring_outer[j1], eave_ring_inner[j1], eave_ring_inner[j]],
              'timber', C_OAK_SUN, (1, 0, 0), Vector((0.0, 3.6, 0.0)), smooth=False)

    # Proud dark oak timber hip-rafter ribs sweeping along all 6 cupola ridges + gilded eave finials!
    for gi in range(6):
        ar = radians(pillar_angles[gi])
        sx_d, sz_d = sin(ar), -cos(ar)
        rib_pts = [
            Vector(((r + 0.04) * sx_d, y + 0.05, (r + 0.04) * sz_d))
            for r, y, _ in roof_profile
        ]
        tube(mb, rib_pts, [0.070, 0.062, 0.054, 0.044], 4, 'timber', C_OAK_DEEP, mode='flat')
        tip_p = rib_pts[0] + Vector((sx_d * 0.08, -0.02, sz_d * 0.08))
        cbox(mb, tip_p, (0.11, 0.11, 0.11), 'brass', C_GOLD_BRIGHT, 0.0)

        # Scalloped painted cream-and-terracotta eave valance tabs hanging beneath each roof bay!
        p_o0 = roof_secs[0][gi * 2]
        p_om = roof_secs[0][gi * 2 + 1]
        p_o1 = roof_secs[0][((gi + 1) % 6) * 2]
        for va, vb, vc in ((p_o0, p_om, C_CREAM_SAIL), (p_om, p_o1, C_TERRA_HI)):
            v_mid = (va + vb) * 0.5
            v_drop = Vector((0.0, -0.17, 0.0))
            v_out = Vector((v_mid.x, 0.0, v_mid.z)).normalized() * 0.03
            mb.fp([va + v_out, vb + v_out, v_mid + v_drop + v_out], 'paint', vc, (1, 0, 0),
                  Vector((0.0, 3.0, 0.0)), smooth=False)
            mb.fp([vb - v_out, va - v_out, v_mid + v_drop - v_out], 'paint', mul(vc, 0.78), (1, 0, 0),
                  v_mid + v_out * 15.0, smooth=False)

    # Upper Cupola Clerestory Turret Drum & Domed Brass-Trimmed Crown Cap (y = 4.34 to 5.14 m)
    cyl(mb, 0.64, 4.34, 4.44, 6, 'timber', C_OAK_DEEP, False, 0.0)
    cyl(mb, 0.54, 4.44, 4.76, 6, 'timber', C_OAK_RICH, False, 0.0)
    for k in range(6):
        ar = radians(pillar_angles[k])
        cbox(mb, (0.55 * sin(ar), 4.60, -0.55 * cos(ar)), (0.06, 0.34, 0.06), 'brass', C_GOLD_BRIGHT, 0.0)
    cupola_prof = [
        (0.00, 4.74),
        (0.68, 4.76),
        (0.50, 4.98),
        (0.18, 5.16),
        (0.00, 5.20),
    ]
    lathe(mb, cupola_prof, 6, 'paint', C_TERRA_HI, False, False,
          lambda i, k: C_TERRA_DARK if i in (0, 3) else (C_TERRA_HI if i == 1 else C_TERRA_MID))
    cyl(mb, 0.69, 4.73, 4.79, 6, 'brass', C_BRASS_WARM, False, 0.0)

    # 5. Gilded Brass Compass-Rose Weathervane Finial & Fluttering Crimson-Gold Pennant (y = 5.16 to 5.95 m!)
    cyl(mb, 0.13, 5.14, 5.28, 6, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.075)
    cyl(mb, 0.036, 5.26, 5.92, 5, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.022)
    lathe(mb, [(0.0, 5.38), (0.10, 5.46), (0.0, 5.54)], 5, 'brass', C_GOLD_BRIGHT, False)
    with xf(mb, T(0.0, 5.46, 0.0) @ M_Y2Z):
        torus(mb, 0.24, 0.024, 6, 4, 'brass', C_BRASS_WARM, False)
    for k in range(4):
        ang = k * 90.0
        with xf(mb, T(0.0, 5.46, 0.0) @ R('Y', ang)):
            _add_beam(mb, (0.0, 0.0, 0.0), (0.0, 0.0, -0.52), 0.030, 0.030, 'brass', C_GOLD_BRIGHT, 0.0)
            with xf(mb, T(0.0, 0.0, -0.54) @ R('X', -90.0)):
                cyl(mb, 0.068, 0.0, 0.14, 4, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.008)
    lathe(mb, [(0.0, 5.86), (0.065, 5.93), (0.0, 6.00)], 4, 'brass', C_GOLD_BRIGHT, False)

    # Fluttering Crimson-Gold Swallowtail Pennant ('paint' + UV2!) streaming in broadside profile!
    _build_wind_pennant(
        mb, root_pos=(0.03, 5.72, 0.0), length=1.38, h0=0.36,
        out_dir=(0.94, -0.04, -0.34), col_main=C_CRIMSON_HI, col_trim=C_GOLD_BRIGHT, phase=0.28,
    )

    # 6. Central Mounted Brass Ship's Binnacle & Brass Astrolabe Pedestal (center of pavilion!)
    BIN_Z = 0.10
    with xf(mb, T(0.0, DECK_Y, BIN_Z)):
        cyl(mb, 0.44, 0.00, 0.14, 6, 'temple_stone', C_ASHLAR_MID, False, 0.0, 0.40)
        cyl(mb, 0.32, 0.14, 0.26, 6, 'timber', C_OAK_DEEP, False, 0.0, 0.26)
        cyl(mb, 0.22, 0.26, 0.88, 6, 'timber', C_OAK_RICH, False, 0.0, 0.19)
        cyl(mb, 0.245, 0.28, 0.34, 6, 'brass', C_BRASS_WARM, False, 0.0)
        cyl(mb, 0.225, 0.78, 0.84, 6, 'brass', C_GOLD_BRIGHT, False, 0.0)
        cyl(mb, 0.36, 0.86, 0.96, 6, 'timber', C_OAK_SUN, False, 0.0, 0.40)
        cyl(mb, 0.415, 0.92, 0.97, 6, 'brass', C_GOLD_BRIGHT, False, 0.0)
        # Open weathered nautical chart sheet draped on the seaward rim of the binnacle lectern
        with xf(mb, T(0.0, 0.98, -0.26) @ R('X', 26.0)):
            cbox(mb, (0.0, 0.0, 0.0), (0.48, 0.022, 0.30), 'paint', C_PARCHMENT_HI, 0.0)
            cbox(mb, (0.0, 0.015, 0.0), (0.14, 0.012, 0.14), 'paint', C_CRIMSON_MID, 0.0)
            for sx in (-0.25, 0.25):
                with xf(mb, T(sx, 0.015, 0.0) @ M_Y2Z):
                    cyl(mb, 0.026, -0.17, 0.17, 5, 'brass', C_BRASS_WARM, False, 0.0)
        # Twin classic nautical Kelvin magnetic compensating spheres (crimson port / teal starboard!)
        for sgn, scol in ((-1.0, C_CRIMSON_HI), (1.0, C_TEAL_HULL)):
            _add_beam(mb, (sgn * 0.20, 0.72, 0.0), (sgn * 0.44, 0.78, 0.0), 0.042, 0.042, 'brass', C_BRASS_WARM, 0.0)
            with xf(mb, T(sgn * 0.47, 0.80, 0.0)):
                lathe(mb, [(0.0, -0.11), (0.11, 0.0), (0.0, 0.11)], 5, 'paint', scol, False)
                cyl(mb, 0.115, -0.016, 0.016, 5, 'brass', C_GOLD_BRIGHT, False, 0.0)

        # Bold Gleaming Brass Ship's Astrolabe / Armillary Sphere mounted atop the binnacle!
        cyl(mb, 0.16, 0.96, 1.08, 6, 'brass', C_BRASS_WARM, False, 0.0, 0.075)
        with xf(mb, T(0.0, 1.38, 0.0)):
            with xf(mb, R('Y', 18.0) @ M_Y2Z):
                torus(mb, 0.34, 0.028, 8, 4, 'brass', C_GOLD_BRIGHT, False)
            with xf(mb, R('X', 62.0) @ R('Y', -24.0)):
                torus(mb, 0.29, 0.024, 8, 4, 'brass', C_BRASS_WARM, False)
            with xf(mb, R('Z', 42.0) @ R('X', 25.0)):
                torus(mb, 0.23, 0.020, 6, 4, 'brass', C_VERDIGRIS_HI, False)
            _add_beam(mb, (-0.28, -0.22, -0.10), (0.28, 0.22, 0.10), 0.026, 0.026, 'brass', C_GOLD_BRIGHT, 0.0)
            lathe(mb, [(0.0, -0.075), (0.075, 0.0), (0.0, 0.075)], 5, 'brass', C_GOLD_BRIGHT, False)

    # 7. Warm Hanging Cupola Brass Lantern ('Lantern_NavGazebo'!) showcased clearly in the seaward archway!
    LANTERN_POS = Vector((0.0, 2.52, -0.06))
    cyl(mb, 0.26, 3.68, 3.84, 6, 'timber', C_OAK_DEEP, False, 0.0)
    cyl(mb, 0.14, 3.58, 3.70, 6, 'iron', C_IRON_FORGED, False, 0.0)
    _add_chain_links(mb, (0.0, 3.60, -0.06), (0.0, 2.86, -0.06), n_links=4,
                     link_r=0.072, wire_r=0.022, segs=4, psegs=4, sag=0.0,
                     mat='iron', col_a=C_IRON_FORGED, col_b=C_BRASS_WARM)
    _build_storm_lantern(mb, LANTERN_POS, scale=1.10, brass_cage=True, hanging=True)

    # Coopered chart-scroll rum cask tucked neatly at rear-starboard deck corner
    _build_coopered_cask(mb, T(1.16, DECK_Y + 0.36, 0.96) @ R('Y', 24.0),
                         radius=0.27, height=0.72, rng=rng, stripe_col=C_TEAL_HULL)

    # 8. Climbing Coastal Sea-Ivy ('foliage' + UV2) & Plinth Ferns
    _add_climbing_ivy_spiral(mb, (pillar_pos[4].x, pillar_pos[4].z), DECK_Y + 0.26, PILLAR_TOP_Y - 0.15,
                             r_wrap=0.145, turns=1.35, rng=rng, phase=0.18, start_ang=0.4, segs=6)
    _add_climbing_ivy_spiral(mb, (pillar_pos[2].x, pillar_pos[2].z), DECK_Y + 0.26, PILLAR_TOP_Y - 0.20,
                             r_wrap=0.145, turns=1.20, rng=rng, phase=0.56, start_ang=2.1, segs=6)
    for v_anc, v_len, v_w, v_dir, v_ph in (
        ((-1.92, 3.02,  0.96), 1.08, 0.14, (-0.8, 0.0,  0.5), 0.22),
        (( 2.08, 3.00,  0.14), 1.04, 0.14, ( 0.9, 0.0,  0.1), 0.64),
    ):
        _add_leafy_vine_drape(mb, v_anc, v_len, v_w, v_dir, rng, phase=v_ph)
    for fpos, fsc, flean, fph in (
        ((-2.02, 0.28, -1.26), 0.68, (-0.7, 0.0, -0.7), 0.14),
        (( 2.05, 0.28, -1.22), 0.66, ( 0.7, 0.0, -0.7), 0.42),
        ((-2.08, 0.28,  1.24), 0.72, (-0.7, 0.0,  0.7), 0.71),
        (( 2.04, 0.28,  1.28), 0.70, ( 0.7, 0.0,  0.7), 0.91),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=4, rng=rng, phase=fph, lean_dir=flean, segs=2)

    build(mb)

    add_empty('Lantern_NavGazebo', LANTERN_POS)
    col_piece('col_gazebo_base', col_pts)
    export_landmark_glb(outdir, 'pirate_chart_navigator_gazebo.glb')


# ==============================================================================
# 2. ANCIENT SUN-SERPENT ARCHWAY (ancient_sun_serpent_archway.glb)
# ==============================================================================

def _build_serpent_head(mb, origin, mirror_x=1.0, scale=1.0):
    """Sculpted Mesoamerican fanged carved stone sun-serpent head facing outward & seaward,
    with glowing turquoise temple eye runes ('skull_glow') and gilded brass plume crest."""
    s = scale
    # Yaw outward (+/-62 deg from -Z) so the twin serpent heads roar diagonally seaward!
    with xf(mb, T(origin) @ R('Y', -mirror_x * 58.0) @ R('X', 6.0)):
        # Upper carved stone cranium & stepped armored snout facing local -Z
        snout_secs = [
            [Vector((-0.34*s, -0.10*s,  0.22*s)), Vector(( 0.34*s, -0.10*s,  0.22*s)),
             Vector(( 0.36*s,  0.28*s,  0.22*s)), Vector(( 0.20*s,  0.42*s,  0.22*s)),
             Vector((-0.20*s,  0.42*s,  0.22*s)), Vector((-0.36*s,  0.28*s,  0.22*s))],
            [Vector((-0.30*s, -0.06*s, -0.32*s)), Vector(( 0.30*s, -0.06*s, -0.32*s)),
             Vector(( 0.30*s,  0.24*s, -0.32*s)), Vector(( 0.16*s,  0.34*s, -0.32*s)),
             Vector((-0.16*s,  0.34*s, -0.32*s)), Vector((-0.30*s,  0.24*s, -0.32*s))],
            [Vector((-0.22*s,  0.00*s, -0.78*s)), Vector(( 0.22*s,  0.00*s, -0.78*s)),
             Vector(( 0.20*s,  0.20*s, -0.78*s)), Vector(( 0.10*s,  0.28*s, -0.78*s)),
             Vector((-0.10*s,  0.28*s, -0.78*s)), Vector((-0.20*s,  0.20*s, -0.78*s))],
        ]
        loft(mb, snout_secs, 'temple_stone', C_RUIN_HI, closed=True, caps=(True, True), mode='flat',
             scols=[C_RUIN_MID, C_RUIN_HI, C_RUIN_HI])
        # Curled Mesoamerican nose-scroll crest atop snout tip
        cbox(mb, (0.0, 0.30 * s, -0.74 * s), (0.20 * s, 0.16 * s, 0.18 * s), 'temple_stone', C_RUIN_HI, 0.0)
        cbox(mb, (0.0, 0.36 * s, -0.68 * s), (0.14 * s, 0.10 * s, 0.12 * s), 'brass', C_GOLD_BRIGHT, 0.0)

        # Heavy sculpted brow ridges & blazing glowing turquoise temple eye runes ('skull_glow'!)
        for sx in (-1.0, 1.0):
            cbox(mb, (sx * 0.31 * s, 0.27 * s, -0.18 * s), (0.12 * s, 0.10 * s, 0.38 * s),
                 'temple_stone', C_RUIN_HI, 0.0, M=R('Z', -sx * 16.0))
            cbox(mb, (sx * 0.32 * s, 0.14 * s, -0.22 * s), (0.08 * s, 0.11 * s, 0.22 * s),
                 'skull_glow', C_AQUA_CORE, 0.0)

        # Gaping lower stone jaw angled downward
        with xf(mb, T(0.0, -0.14 * s, 0.06 * s) @ R('X', -24.0)):
            cbox(mb, (0.0, -0.06 * s, -0.38 * s), (0.44 * s, 0.16 * s, 0.72 * s),
                 'temple_stone', C_RUIN_DARK, 0.0)
            # Dark recessed throat mouth glow rune
            cbox(mb, (0.0, 0.04 * s, -0.22 * s), (0.26 * s, 0.08 * s, 0.34 * s),
                 'skull_glow', C_AQUA_MID, 0.0)
            # Lower tusks
            for sx in (-1.0, 1.0):
                tube(mb, [(sx * 0.14 * s, 0.02 * s, -0.62 * s), (sx * 0.13 * s, 0.19 * s, -0.58 * s)],
                     [0.048 * s, 0.012 * s], 4, 'skull_stone', C_SKULL_BONE, mode='flat')

        # Long curved stone sabre-fangs descending from upper jaw!
        for sx in (-1.0, 1.0):
            tube(mb, [(sx * 0.18 * s, -0.04 * s, -0.64 * s),
                      (sx * 0.18 * s, -0.20 * s, -0.68 * s),
                      (sx * 0.16 * s, -0.36 * s, -0.62 * s)],
                 [0.060 * s, 0.042 * s, 0.012 * s], 4, 'skull_stone', C_SKULL_BONE, mode='flat')
            # Secondary rear molar fang
            tube(mb, [(sx * 0.22 * s, -0.06 * s, -0.38 * s), (sx * 0.21 * s, -0.22 * s, -0.38 * s)],
                 [0.045 * s, 0.012 * s], 4, 'skull_stone', C_SKULL_MID, mode='flat')

        # Gilded brass feathered-serpent head-plume fan sweeping rearward!
        for k, (px, py, rot_x) in enumerate((
            ( 0.00, 0.34,  34.0),
            (-0.20, 0.30,  24.0),
            ( 0.20, 0.30,  24.0),
        )):
            with xf(mb, T(px * s, py * s, 0.14 * s) @ R('X', rot_x) @ R('Z', -px * 55.0)):
                cbox(mb, (0.0, 0.18 * s, 0.06 * s), (0.11 * s, 0.44 * s, 0.06 * s),
                     'brass', C_GOLD_BRIGHT if k == 0 else C_BRASS_WARM, 0.0)


def gen_ancient_sun_serpent_archway(outdir):
    """Monumental overgrown Caribbean/Mesoamerican carved stone sun-serpent ruin portal rooted on
    a stepped mossy temple masonry plinth plunging to y = -3.40 m (footprint hx=2.65 m, hz=1.95 m),
    twin weathered relief-carved rune pillars (~5.8 m tall) supporting a bold sculpted fanged stone
    serpent lintel framing a large gilded solar-ray disc medallion ('brass' + glowing turquoise
    temple eye runes & flanking flame-crystal niches via 'skull_glow'!), cascading jungle creepers
    & ferns ('foliage' + UV2), collider 'col_sunarch_base', and 'Lantern_SunSerpent' empty."""
    clear_scene()
    mb = MB('ancient_sun_serpent_archway', seed=1702)
    rng = random.Random(SEED + 1702)
    col_pts = []

    DECK_Y = 0.52
    PIL_X = 1.46
    LINTEL_BOT_Y = 3.92

    # 1. Stepped Mossy Temple Masonry Plinth plunging cleanly to y = -3.40 m (hx=2.65, hz=1.95)
    skirt_secs = [
        _rect_oct(0.0, -3.40, 0.0, 2.65, 1.95, 0.46),
        _rect_oct(0.0, -1.45, 0.0, 2.60, 1.90, 0.44),
        _rect_oct(0.0,  0.00, 0.0, 2.52, 1.82, 0.42),
        _rect_oct(0.0,  0.26, 0.0, 2.46, 1.76, 0.40),
    ]
    _loft_horizontal_masonry(
        mb, skirt_secs, 'temple_stone',
        [C_RUIN_DEEP, C_RUIN_DARK, C_RUIN_MID, C_RUIN_HI],
        rng, caps=(True, True), top_mat='limestone_moss', top_col=C_RUIN_HI,
    )
    tier2_secs = [
        _rect_oct(0.0, 0.25, 0.0, 2.26, 1.56, 0.32),
        _rect_oct(0.0, DECK_Y, 0.0, 2.20, 1.50, 0.30),
    ]
    _loft_horizontal_masonry(
        mb, tier2_secs, 'temple_stone',
        [C_RUIN_MID, C_RUIN_HI],
        rng, caps=(False, True), top_mat='limestone_moss', top_col=C_RUIN_MID,
    )

    # Collider points enclosing base plinth + portal silhouette
    for y_c, hx, hz in ((-3.40, 2.64, 1.94), (0.0, 2.50, 1.80), (DECK_Y, 2.20, 1.50), (4.65, 2.15, 0.85)):
        col_pts.extend(_rect_oct(0.0, y_c, 0.0, hx, hz, 0.32))

    # Ceremonial mossy paving flagstones & stepped front/rear entry stairs with carved cheek walls
    for z_step_sgn in (-1.0, 1.0):
        for si, (sy, sh, sd, sw) in enumerate((
            (0.11, 0.22, 1.78, 1.86),
            (0.32, 0.24, 1.54, 1.76),
        )):
            cbox(mb, (0.0, sy, z_step_sgn * sd), (sw, sh, 0.32), 'temple_stone',
                 jit(C_RUIN_HI if si == 1 else C_RUIN_MID, rng, 0.04), 0.015)
        for sx in (-1.0, 1.0):
            cbox(mb, (sx * 1.04, 0.30, z_step_sgn * 1.66), (0.26, 0.56, 0.56), 'temple_stone', C_RUIN_DARK, 0.02)
            cbox(mb, (sx * 1.04, 0.60, z_step_sgn * 1.66), (0.28, 0.07, 0.58), 'brass', C_BRASS_DARK, 0.0)

    # Central glowing carved floor threshold sun-glyph strip between the pillars
    cbox(mb, (0.0, DECK_Y + 0.02, 0.0), (1.42, 0.04, 1.24), 'limestone_moss', C_RUIN_HI, 0.0)
    cbox(mb, (0.0, DECK_Y + 0.045, 0.0), (0.48, 0.025, 0.48), 'brass', C_BRASS_WARM, 0.0, M=R('Y', 45.0))
    cbox(mb, (0.0, DECK_Y + 0.055, 0.0), (0.20, 0.025, 0.20), 'skull_glow', C_AQUA_MID, 0.0, M=R('Y', 45.0))

    # 2. Twin Weathered Relief-Carved Rune Pillars (x = +/-1.46 m, y = 0.52 to 4.02 m)
    for sgn in (-1.0, 1.0):
        px = sgn * PIL_X
        # Stepped battered pillar pedestal base
        p_base = [
            _rect_oct(px, DECK_Y,       0.0, 0.66, 0.68, 0.12),
            _rect_oct(px, DECK_Y + 0.38, 0.0, 0.58, 0.60, 0.10),
        ]
        _loft_horizontal_masonry(mb, p_base, 'temple_stone', [C_RUIN_DARK, C_RUIN_MID], rng, caps=(False, True))

        # Main tapered carved pillar shaft (y = 0.90 to 3.68 m)
        p_shaft = [
            _rect_oct(px, 0.88, 0.0, 0.52, 0.54, 0.10),
            _rect_oct(px, 1.80, 0.0, 0.49, 0.51, 0.09),
            _rect_oct(px, 2.75, 0.0, 0.46, 0.48, 0.09),
            _rect_oct(px, 3.66, 0.0, 0.44, 0.46, 0.08),
        ]
        _loft_horizontal_masonry(mb, p_shaft, 'temple_stone',
                                 [C_RUIN_DARK, C_RUIN_MID, C_RUIN_HI, C_RUIN_HI], rng, caps=(False, True))

        # Stepped Mesoamerican corbeled capital (y = 3.64 to 4.02 m)
        p_cap = [
            _rect_oct(px, 3.64, 0.0, 0.52, 0.54, 0.10),
            _rect_oct(px, 3.84, 0.0, 0.62, 0.62, 0.11),
            _rect_oct(px, 4.02, 0.0, 0.68, 0.66, 0.12),
        ]
        _loft_horizontal_masonry(mb, p_cap, 'temple_stone', [C_RUIN_MID, C_RUIN_HI, C_RUIN_HI], rng, caps=(False, True))

        # Horizontal relief-carved stone & gilded brass fret-bands wrapping each pillar
        for by_b, bw_b, b_mat, b_col in (
            (1.36, 0.54, 'brass', C_BRASS_WARM),
            (3.04, 0.50, 'brass', C_GOLD_BRIGHT),
            (3.44, 0.50, 'temple_stone', C_RUIN_HI),
        ):
            cbox(mb, (px, by_b, 0.0), (bw_b * 2.0, 0.11, bw_b * 2.04), b_mat, b_col, 0.0)

        # Flanking Flame-Crystal Niches on BOTH seaward (-Z) AND rear (+Z) pillar faces!
        for z_dir in (-1.0, 1.0):
            nz = z_dir * 0.51
            # Stepped stone niche frame (sill, lintel hood & flanking jambs)
            cbox(mb, (px, 1.78, nz + z_dir * 0.05), (0.62, 0.12, 0.24), 'temple_stone', C_RUIN_HI, 0.0)
            cbox(mb, (px, 2.74, nz + z_dir * 0.06), (0.66, 0.14, 0.26), 'temple_stone', C_RUIN_HI, 0.0)
            for jx in (-0.26, 0.26):
                cbox(mb, (px + jx, 2.26, nz + z_dir * 0.04), (0.12, 0.88, 0.20), 'temple_stone', C_RUIN_MID, 0.0)
            # Dark stone niche backing cavity
            cbox(mb, (px, 2.26, nz - z_dir * 0.02), (0.40, 0.84, 0.08), 'basalt', C_RUIN_DEEP, 0.0)
            # Glowing turquoise flame-crystal cluster ('skull_glow'!) nestled on brass altar cup inside niche!
            with xf(mb, T(px, 1.85, nz + z_dir * 0.06)):
                cyl(mb, 0.14, 0.0, 0.09, 6, 'brass', C_BRASS_WARM, False, 0.0, 0.10)
                # Central tall hexagonal flame-crystal spire
                lathe(mb, [(0.0, 0.06), (0.115, 0.24), (0.095, 0.52), (0.0, 0.76)],
                      6, 'skull_glow', C_AQUA_CORE, False, False,
                      lambda i, k: C_AQUA_CORE if i in (1, 2) else C_AQUA_MID)
                # Twin smaller flanking flame-crystal shards
                for csx, cang in ((-0.10, 18.0), (0.10, -18.0)):
                    with xf(mb, T(csx, 0.06, 0.0) @ R('Z', cang)):
                        lathe(mb, [(0.0, 0.0), (0.058, 0.18), (0.0, 0.42)], 4, 'skull_glow', C_AQUA_MID, False)

        # Carved outer serpent-scale relief bosses & glowing turquoise rune channel on outer & inner cheeks!
        out_x = px + sgn * 0.48
        in_x = px - sgn * 0.46
        for ry in (1.16, 1.62, 2.08, 2.54, 3.24):
            cbox(mb, (out_x + sgn * 0.05, ry, 0.0), (0.14, 0.24, 0.56), 'temple_stone', C_RUIN_HI, 0.0)
        # Glowing turquoise vertical zig-zag rune vein etched into the inner portal jamb face!
        rune_path = [
            (in_x, 1.24,  0.00),
            (in_x, 1.72, -0.14),
            (in_x, 2.22,  0.14),
            (in_x, 2.74, -0.12),
            (in_x, 3.28,  0.00),
        ]
        _sculpt_magma_ribbon(
            mb, rune_path, [0.065, 0.075, 0.075, 0.070, 0.050],
            (-sgn, 0.0, 0.0), hot_core=True, ridge_h=0.045, mat='skull_glow',
            c_core=C_AQUA_CORE, c_mid_col=C_AQUA_MID, c_edge_col=C_AQUA_DEEP, c_tip_col=C_AQUA_DEEP,
        )

    # 3. Bold Sculpted Fanged Stone Serpent Lintel (y = 3.92 to 4.96 m, spanning x = -2.35 to +2.35 m!)
    # Lower stepped architrave beam + recessed glowing turquoise lintel frieze
    cbox(mb, (0.0, 4.14, 0.0), (4.24, 0.44, 1.18), 'temple_stone', C_RUIN_MID, 0.03)
    # Upper overhanging Mesoamerican cornice beam
    cbox(mb, (0.0, 4.54, 0.0), (4.56, 0.36, 1.32), 'temple_stone', C_RUIN_HI, 0.03)
    # Gilded brass horizontal cornice trim bars on front (-Z) & rear (+Z)
    for z_dir in (-1.0, 1.0):
        cbox(mb, (0.0, 4.34, z_dir * 0.62), (4.28, 0.09, 0.10), 'brass', C_GOLD_BRIGHT, 0.0)
        # Carved Mesoamerican stepped tooth-dentils along the upper cornice
        for dx in (-1.92, -1.44, -0.96, 0.96, 1.44, 1.92):
            cbox(mb, (dx, 4.74, z_dir * 0.62), (0.24, 0.16, 0.16), 'temple_stone', C_RUIN_HI, 0.0)
        # Undulating carved serpent-body stone ridge coiling along the lintel face!
        for sgn in (-1.0, 1.0):
            body_pts = [
                (sgn * 0.72, 4.26, z_dir * 0.62),
                (sgn * 1.18, 4.44, z_dir * 0.66),
                (sgn * 1.66, 4.24, z_dir * 0.66),
                (sgn * 2.08, 4.38, z_dir * 0.56),
            ]
            tube(mb, body_pts, [0.14, 0.16, 0.17, 0.18], 5, 'temple_stone', C_RUIN_HI, mode='flat')
            # Glowing turquoise scale-rune diamonds tucked along the lintel frieze
            for rx in (1.02, 1.48):
                cbox(mb, (sgn * rx, 4.14, z_dir * 0.62), (0.13, 0.13, 0.08),
                     'skull_glow', C_AQUA_MID, 0.0, M=R('Z', 45.0))

    # Carved under-lintel keystone corbels framing the open portal ceiling
    for sx in (-0.82, 0.82):
        cbox(mb, (sx, 3.84, 0.0), (0.36, 0.24, 0.98), 'temple_stone', C_RUIN_DARK, 0.0)
    cbox(mb, (0.0, 3.88, 0.0), (0.58, 0.16, 0.92), 'brass', C_BRASS_DARK, 0.0)

    # Twin Fierce Sculpted Fanged Stone Serpent Heads bursting from both ends of the lintel!
    _build_serpent_head(mb, (-2.18, 4.36, -0.14), mirror_x=-1.0, scale=1.08)
    _build_serpent_head(mb, ( 2.18, 4.36, -0.14), mirror_x= 1.0, scale=1.08)

    # 4. Large Gilded Solar-Ray Disc Medallion Crown (centered at (0, 5.20, 0), full sun-eye unobstructed!)
    SUN_Y = 5.20
    # Stepped carved stone halo cradle anchoring the lower third of the solar medallion solidly to the lintel
    cbox(mb, (0.0, 4.78, 0.0), (1.88, 0.24, 0.76), 'temple_stone', C_RUIN_MID, 0.0)
    cbox(mb, (0.0, 4.94, 0.0), (1.28, 0.18, 0.56), 'temple_stone', C_RUIN_HI, 0.0)

    with xf(mb, T(0.0, SUN_Y, 0.0)):
        # Double-sided sculpted solar calendar medallion facing BOTH -Z seaward AND +Z rear!
        with xf(mb, M_Y2Z):
            # Thick stone backing disc
            cyl(mb, 0.68, -0.22, 0.22, 12, 'temple_stone', C_RUIN_DARK, False, 0.0)
            # Outer raised gilded brass bevel frame
            cyl(mb, 0.62, -0.26, 0.26, 12, 'brass', C_GOLD_BRIGHT, False, 0.0)
            # Inner verdigris-bronze recessed calendar band
            cyl(mb, 0.46, -0.285, 0.285, 12, 'brass', C_VERDIGRIS_MID, False, 0.0)
            # Raised central gilded solar boss
            cyl(mb, 0.30, -0.315, 0.315, 8, 'brass', C_GOLD_BRIGHT, False, 0.0)
            # Luminous turquoise mystical sun-serpent eye rune in the very center (front & rear!)
            cyl(mb, 0.17, -0.345, 0.345, 6, 'skull_glow', C_AQUA_CORE, False, 0.0, 0.13)
        # Vertical brass slit pupil bars across both faces of the glowing sun-eye
        for z_dir in (-1.0, 1.0):
            cbox(mb, (0.0, 0.0, z_dir * 0.355), (0.045, 0.26, 0.03), 'brass', C_BRASS_DARK, 0.0)

        # 12 Bold Gilded Brass Solar-Ray Spikes radiating around the medallion (top spike reaches y ~ 6.20 m!)
        n_rays = 12
        for ri in range(n_rays):
            ang_deg = ri * (360.0 / n_rays)
            if 155.0 <= ang_deg <= 205.0:
                continue
            is_major = (ri % 2 == 0)
            r_len = 0.40 if is_major else 0.27
            r_w = 0.115 if is_major else 0.082
            with xf(mb, R('Z', -ang_deg) @ T(0.0, 0.64, 0.0)):
                # Faceted pyramidal gilded sun-ray spike
                lathe(mb, [(0.0, -0.04), (r_w, 0.0), (r_w * 0.52, r_len * 0.55), (0.0, r_len)],
                      4, 'brass', C_GOLD_BRIGHT if is_major else C_BRASS_WARM, False)
                if is_major:
                    # Tiny glowing turquoise rune jewel nestled at base of every major solar ray!
                    cbox(mb, (0.0, 0.05, -0.10), (0.06, 0.09, 0.06), 'skull_glow', C_AQUA_MID, 0.0)
                    cbox(mb, (0.0, 0.05,  0.10), (0.06, 0.09, 0.06), 'skull_glow', C_AQUA_MID, 0.0)

    # 5. Weathered Overgrown Ruin Rubble Blocks + Cascading Jungle Creepers & Ferns ('foliage' + UV2!)
    for rx, ry, rz, rsx, rsy, rsz, ryaw in (
        (-2.22, 0.44, -1.16, 0.56, 0.42, 0.50,  18.0),
        ( 2.26, 0.40,  1.08, 0.52, 0.38, 0.48, -26.0),
        (-2.14, 0.42,  1.20, 0.46, 0.34, 0.44,  34.0),
    ):
        sculpt_stone_block(mb, (rx, ry, rz), (rsx, rsy, rsz), 'limestone_moss', C_RUIN_MID, rng,
                           chip=0.04, M=R('Y', ryaw), moss_col=C_LEDGE_MOSS)

    # 7 Cascading jungle creepers draping down from the serpent lintel & pillar capitals!
    for v_anc, v_len, v_w, v_dir, v_ph in (
        ((-1.92, 4.02, -0.60), 1.95, 0.16, (-0.5, 0.0, -0.8), 0.11),
        (( 1.94, 4.00, -0.58), 1.82, 0.16, ( 0.5, 0.0, -0.8), 0.38),
        ((-0.88, 3.92, -0.56), 1.15, 0.14, (-0.3, 0.0, -0.9), 0.61),
        (( 0.86, 3.92,  0.56), 1.24, 0.14, ( 0.3, 0.0,  0.9), 0.77),
        ((-1.88, 4.04,  0.60), 1.88, 0.16, (-0.5, 0.0,  0.8), 0.25),
        (( 1.90, 4.02,  0.60), 1.76, 0.16, ( 0.5, 0.0,  0.8), 0.52),
        ((-1.96, 2.70,  0.04), 1.45, 0.15, (-1.0, 0.0,  0.0), 0.89),
    ):
        _add_leafy_vine_drape(mb, v_anc, v_len, v_w, v_dir, rng, phase=v_ph)

    # 6 Tropical jungle fern rosettes tucked around the mossy stepped temple plinth
    for fpos, fsc, flean, fph in (
        ((-2.06, 0.28, -1.36), 0.82, (-0.7, 0.0, -0.7), 0.15),
        (( 2.08, 0.28, -1.32), 0.80, ( 0.7, 0.0, -0.7), 0.44),
        ((-2.12, 0.28,  1.34), 0.84, (-0.7, 0.0,  0.7), 0.68),
        (( 2.10, 0.28,  1.36), 0.80, ( 0.7, 0.0,  0.7), 0.91),
        ((-1.96, 0.52, -0.10), 0.68, (-1.0, 0.0, -0.1), 0.31),
        (( 1.98, 0.52,  0.14), 0.66, ( 1.0, 0.0,  0.1), 0.79),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=4, rng=rng, phase=fph, lean_dir=flean)

    # Lantern_SunSerpent empty positioned cleanly beneath the solar medallion lintel!
    LANTERN_POS = Vector((0.0, 3.62, -0.04))

    build(mb)

    add_empty('Lantern_SunSerpent', LANTERN_POS)
    col_piece('col_sunarch_base', col_pts)
    export_landmark_glb(outdir, 'ancient_sun_serpent_archway.glb')


# ==============================================================================
# 3. COASTAL SHIPWRECK BARRICADE CAMP (coastal_shipwreck_barricade_camp.glb)
# ==============================================================================

def _build_patched_signal_flag(mb, mast_top, length=1.82, height=0.92, out_dir=(0.86, -0.05, 0.51), phase=0.22):
    """Tattered patched crimson-and-cream castaway signal flag ('paint' + UV2 wind sway)
    with jagged torn trailing edge and contrast stitched sailcloth patches!"""
    rp = Vector(mast_top)
    od = Vector(out_dir).normalized()
    side = Vector((-od.z, 0.0, od.x)).normalized()
    nx, ny = 6, 3
    thick = 0.012

    grid_f = [[None] * (ny + 1) for _ in range(nx + 1)]
    grid_b = [[None] * (ny + 1) for _ in range(nx + 1)]
    u2_grid = [[None] * (ny + 1) for _ in range(nx + 1)]

    for ix in range(nx + 1):
        u = ix / float(nx)
        wave = sin(u * 2.3 * pi) * 0.18 * (u ** 0.9)
        droop = -0.16 * (u ** 1.6)
        w_wind = (u ** 1.15) * 0.95
        for iy in range(ny + 1):
            v = iy / float(ny)
            # Jagged torn swallowtail/tattered fly edge on the last column!
            u_eff = u
            if ix == nx:
                u_eff = u - (0.16 if iy in (1, 2) else 0.0) - (0.06 if iy == 0 else 0.0)
            y_local = (v - 0.5) * height * (1.0 - 0.14 * u) + droop
            ctr = rp + od * (length * u_eff) + side * (wave + 0.03 * sin(v * pi + u * 4.0)) + Vector((0.0, y_local, 0.0))
            grid_f[ix][iy] = ctr + side * thick
            grid_b[ix][iy] = ctr - side * thick
            u2_grid[ix][iy] = (w_wind, phase)

    def _patch_col(ix, iy):
        # Bold stitched crimson-and-cream castaway signal pattern with darker weathered patches!
        if (ix == 2 and iy == 1) or (ix == 4 and iy == 2):
            return C_GOLD_BRIGHT  # stitched ochre/gold canvas patch!
        if (ix == 1 and iy == 0) or (ix == 3 and iy == 2):
            return C_CRIMSON_DARK
        if iy == 1:
            return C_CREAM_SAIL if ix % 2 == 0 else C_CREAM_AGED
        return C_CRIMSON_HI if (ix + iy) % 2 == 0 else C_CRIMSON_MID

    for ix in range(nx):
        for iy in range(ny):
            # Leave a dramatic small wind-torn notch missing at the outer-mid trailing cell!
            if ix == nx - 1 and iy == 1:
                continue
            c = _patch_col(ix, iy)
            f00, f10, f11, f01 = grid_f[ix][iy], grid_f[ix + 1][iy], grid_f[ix + 1][iy + 1], grid_f[ix][iy + 1]
            b00, b10, b11, b01 = grid_b[ix][iy], grid_b[ix + 1][iy], grid_b[ix + 1][iy + 1], grid_b[ix][iy + 1]
            u00, u10, u11, u01 = u2_grid[ix][iy], u2_grid[ix + 1][iy], u2_grid[ix + 1][iy + 1], u2_grid[ix][iy + 1]
            ctr = (f00 + f10 + f11 + f01) * 0.25
            mb.fp([f00, f10, f11, f01], 'paint', c, od, ctr - side * 1.5, smooth=False, uv2=[u00, u10, u11, u01])
            mb.fp([b10, b00, b01, b11], 'paint', mul(c, 0.84), od, ctr + side * 1.5, smooth=False, uv2=[u10, u00, u01, u11])


def _build_bronze_swivel_gun(mb, pivot_pos, yaw_deg=14.0, pitch_deg=5.0):
    """Mounted weathered bronze pirate deck-swivel gun on an iron pintle fork with curved tiller!"""
    with xf(mb, T(pivot_pos) @ R('Y', yaw_deg)):
        # Forged-iron swivel pintle shaft & U-shaped yoke fork
        cyl(mb, 0.048, -0.22, 0.08, 6, 'iron', C_IRON_FORGED, False, 0.0)
        cbox(mb, (0.0, 0.09, 0.0), (0.34, 0.06, 0.08), 'iron', C_IRON_FORGED, 0.0)
        for sx in (-0.15, 0.15):
            cbox(mb, (sx, 0.22, 0.0), (0.055, 0.24, 0.08), 'iron', C_IRON_FORGED, 0.0)

        # Tilted weathered bronze cannon barrel facing seaward (-Z local)
        with xf(mb, T(0.0, 0.28, 0.0) @ R('X', pitch_deg)):
            # Trunnion axle pins seated into the iron yoke
            with xf(mb, M_Y2X):
                cyl(mb, 0.042, -0.19, 0.19, 6, 'brass', C_BRONZE_DARK, False, 0.0)
            # Chunky flared bronze barrel profile (cascabel at +Z rear -> flared muzzle at -Z front)
            with xf(mb, R('X', -90.0)):
                barrel_prof = [
                    (0.00, -0.44),
                    (0.068, -0.40),
                    (0.045, -0.35),  # cascabel neck
                    (0.132, -0.30),  # breech ring
                    (0.118, -0.06),  # first reinforce
                    (0.128, -0.03),  # mid astragal ring
                    (0.098,  0.34),  # chase taper
                    (0.124,  0.48),  # flared muzzle swell!
                    (0.105,  0.54),  # muzzle lip
                    (0.068,  0.54),  # bore rim
                    (0.068,  0.34),  # dark recessed bore
                    (0.00,   0.34),
                ]
                lathe(mb, barrel_prof, 8, 'brass', C_BRONZE_WARM, False, False,
                      lambda i, k: C_IRON_DARK if i >= 9 else (
                          C_VERDIGRIS_MID if i in (2, 5) else (
                              C_GOLD_BRIGHT if i in (3, 7) else C_BRONZE_WARM)))
            # Curved forged-iron aiming tiller handle extending rearward (+Z) for the gunner!
            tiller_pts = [
                (0.0, 0.00, 0.42),
                (0.0, 0.02, 0.64),
                (0.0, -0.06, 0.86),
                (0.0, -0.10, 1.00),
            ]
            tube(mb, tiller_pts, [0.028, 0.024, 0.026, 0.032], 4, 'iron', C_IRON_FORGED, mode='flat')


def gen_coastal_shipwreck_barricade_camp(outdir):
    """Castaway pirates' fortified beachhead rampart grounded on a sand-and-cobble shore plinth
    plunging to y = -2.80 m (footprint hx=2.60 m, hz=2.20 m), sweeping curved barricade built from
    salvaged galleon hull planking & jutting splintered oak ship-ribs lashed with taut hemp hawser,
    mounted weathered bronze deck-swivel gun, tattered patched crimson-and-cream signal flag flying
    from a broken mast spar ('paint' + UV2), sheltered stone campfire hearth with glowing embers
    ('glass'), oak rum kegs & open crate of provisions, coastal tuft ferns ('foliage' + UV2),
    collider 'col_barricade_base', and 'Lantern_BarricadeCamp' empty."""
    clear_scene()
    mb = MB('coastal_shipwreck_barricade_camp', seed=1703)
    rng = random.Random(SEED + 1703)
    col_pts = []

    DECK_Y = 0.24

    # 1. Sand-and-Cobble Shore Plinth plunging cleanly to y = -2.80 m (hx=2.60, hz=2.20)
    shore_secs = [
        _rect_oct(0.0, -2.80, 0.0, 2.60, 2.20, 0.62),
        _rect_oct(0.0, -1.20, 0.0, 2.54, 2.14, 0.60),
        _rect_oct(0.0,  0.00, 0.0, 2.44, 2.04, 0.58),
        _rect_oct(0.0,  DECK_Y, 0.0, 2.26, 1.88, 0.54),
    ]
    _loft_horizontal_masonry(
        mb, shore_secs, 'limestone',
        [C_SAND_WET, C_SAND_OCHRE, C_SAND_WARM, C_SAND_PALE],
        rng, caps=(True, True), top_mat='limestone', top_col=C_SAND_PALE,
    )
    # Softly heaped beach sand dune pad inside the barricade camp
    cyl(mb, 1.72, DECK_Y - 0.02, DECK_Y + 0.06, 8, 'limestone', C_SAND_WARM, False, 0.0, 1.38)

    for y_c, hx, hz in ((-2.80, 2.58, 2.18), (0.0, 2.42, 2.02), (1.42, 2.05, 1.65)):
        col_pts.extend(_rect_oct(0.0, y_c, 0.0, hx, hz, 0.50))

    # Scattered faceted coastal beach cobbles framing the sand-and-cobble shore plinth
    for cx, cz, rx, ry, rz, ryaw in (
        (-2.06, -1.04, 0.24, 0.22, 0.20,  22.0),
        (-1.18, -1.78, 0.22, 0.20, 0.19, -18.0),
        ( 0.88, -1.76, 0.25, 0.24, 0.20,  31.0),
        ( 2.06, -0.84, 0.23, 0.22, 0.19, -24.0),
        ( 1.98,  1.26, 0.22, 0.20, 0.19,  15.0),
        (-1.86,  1.38, 0.24, 0.22, 0.20, -30.0),
        ( 0.14,  1.72, 0.21, 0.18, 0.18,   8.0),
    ):
        with xf(mb, T(cx, DECK_Y - 0.04, cz) @ R('Y', ryaw) @ S(1.0, 1.0, rz / rx)):
            cyl(mb, rx, 0.0, ry, 5, 'limestone', jit(C_COBBLE_MID, rng, 0.06), False, 0.0, rx * 0.72)

    # 2. Sweeping Curved Salvaged Galleon Hull Barricade (hugging seaward -Z arc!)
    # 7 control ribs tracing a sweeping fortified arc from port-mid (-1.92, +0.20) around seaward (-Z) to starboard (+1.88, -0.18)
    arc_angles = [-84.0, -56.0, -28.0, 0.0, 28.0, 56.0, 82.0]
    ARC_CX, ARC_CZ = 0.0, 0.18
    ARC_RX, ARC_RZ = 1.96, 1.72
    rib_bases = []
    rib_out = []
    for deg in arc_angles:
        ar = radians(deg)
        bx = ARC_CX + ARC_RX * sin(ar)
        bz = ARC_CZ - ARC_RZ * cos(ar)
        rib_bases.append(Vector((bx, DECK_Y, bz)))
        rib_out.append(Vector((sin(ar), 0.0, -cos(ar))).normalized())

    # 5 Overlapping Horizontal Curved Galleon Hull Planks (including faded teal & crimson ship strakes!)
    plank_specs = [
        (0.28, 0.24, 0.095, 'timber', C_OAK_DEEP,    0.00),
        (0.54, 0.24, 0.095, 'timber', C_OAK_RICH,    0.04),
        (0.80, 0.24, 0.095, 'paint',  C_TEAL_HULL,   0.08),   # weathered teal galleon strake!
        (1.06, 0.23, 0.095, 'timber', C_OAK_SUN,     0.12),
        (1.30, 0.21, 0.090, 'paint',  C_CRIMSON_MID, 0.16),   # crimson gunwale strake!
    ]
    for p_idx, (py, ph, pth, pmat, pcol, flare) in enumerate(plank_specs):
        # Broken jagged ends & battle-scarred cannonball breach notch on top gunwale (k=2) letting campfire peek!
        start_k = 1 if p_idx == 4 else 0
        end_k = 6 if p_idx == 4 else 7
        for k in range(start_k, end_k - 1):
            if p_idx == 4 and k == 2:
                continue
            p0 = rib_bases[k] + rib_out[k] * (0.04 + flare) + Vector((0.0, py - DECK_Y, 0.0))
            p1 = rib_bases[k + 1] + rib_out[k + 1] * (0.04 + flare) + Vector((0.0, py - DECK_Y, 0.0))
            if p_idx == 4 and k in (1, 4):
                p0 = p0 + Vector((0.0, -0.04, 0.0))
            _add_beam(mb, p0, p1, pth, ph, pmat, jit(pcol, rng, 0.05), 0.0)
            if p_idx == 2:
                mid_p = p0.lerp(p1, 0.5) + rib_out[k].lerp(rib_out[k + 1], 0.5).normalized() * (pth * 0.52)
                cbox(mb, mid_p, (0.05, 0.05, 0.05), 'iron', C_IRON_FORGED, 0.0)

    # 7 Jutting Splintered Oak Ship-Ribs (curved hull frames curving upward & flaring outward!)
    rib_heights = [1.86, 2.24, 1.72, 1.54, 1.98, 2.18, 1.78]
    for k, (rb, ro, rh) in enumerate(zip(rib_bases, rib_out, rib_heights)):
        r_pts = [
            rb - ro * 0.08 + Vector((0.0, -0.06, 0.0)),
            rb - ro * 0.04 + Vector((0.0, rh * 0.36, 0.0)),
            rb + ro * 0.08 + Vector((0.0, rh * 0.72, 0.0)),
            rb + ro * 0.24 + Vector((0.0, rh * 0.94, 0.0)),
            rb + ro * 0.30 + Vector((0.0, rh * 1.04, 0.0)),
        ]
        r_rads = [0.092, 0.086, 0.078, 0.058, 0.018]
        r_cols = [C_OAK_DEEP, C_OAK_RICH, C_OAK_SUN, C_DRIFT_MID, C_DRIFT_PALE]
        tube(mb, r_pts, r_rads, 4, 'timber', C_OAK_RICH, mode='flat', scols=r_cols)

        # Diagonal interior driftwood buttress brace propping alternating ribs firmly into the beach!
        if k in (1, 3, 5):
            brace_top = r_pts[2] - ro * 0.06
            brace_bot = rb - ro * 0.74 + Vector((0.0, -0.04, 0.0))
            _add_beam(mb, brace_bot, brace_top, 0.095, 0.095, 'timber', C_DRIFT_MID, 0.0)
            _add_beam(mb, brace_bot - Vector((0, 0.05, 0)), brace_bot + Vector((0, 0.34, 0)),
                      0.08, 0.08, 'timber', C_OAK_DEEP, 0.0)

        # Chunky hemp hawser lashing collar wrapping each rib to the top hull gunwale!
        lash_p = r_pts[1].lerp(r_pts[2], 0.90) + ro * 0.04
        with xf(mb, T(lash_p) @ R('Y', -arc_angles[k])):
            torus(mb, 0.118, 0.030, 5, 4, 'rope', C_ROPE, False)

    # Sweeping taut hemp hawser zig-zag lashing rope binding the barricade ribs together along the top rail!
    hawser_pts = [
        rib_bases[k] + rib_out[k] * (0.16 + 0.05 * (k % 2)) + Vector((0.0, 1.18 + 0.14 * (k % 2), 0.0))
        for k in range(7)
    ]
    tube(mb, hawser_pts, 0.034, 4, 'rope', C_ROPE, mode='flat')

    # Heavy salvaged driftwood firing-step bench tucked inside behind the central swivel gun
    cbox(mb, (0.04, DECK_Y + 0.18, -1.04), (1.06, 0.24, 0.38), 'timber', C_DRIFT_MID, 0.0)

    # 3. Mounted Weathered Bronze Deck-Swivel Gun atop the central reinforced oak pintle post!
    SWIVEL_POST_XZ = (0.04, -1.48)
    cyl(mb, 0.115, DECK_Y - 0.04, 1.54, 6, 'timber', C_OAK_DEEP, False, 0.0, 0.105)
    for hy in (0.76, 1.38):
        cyl(mb, 0.122, hy - 0.03, hy + 0.03, 6, 'iron', C_IRON_FORGED, False, 0.0)
    _build_bronze_swivel_gun(mb, (SWIVEL_POST_XZ[0], 1.54, SWIVEL_POST_XZ[1]), yaw_deg=16.0, pitch_deg=6.0)

    # 4. Broken Mast Spar & Tattered Patched Crimson-and-Cream Signal Flag ('paint' + UV2!)
    MAST_BASE = Vector((-1.54, DECK_Y - 0.06, -0.58))
    MAST_TOP  = Vector((-1.86, 4.78, -0.78))
    MAST_MID  = MAST_BASE.lerp(MAST_TOP, 0.54)
    tube(mb, [MAST_BASE, MAST_MID, MAST_TOP, MAST_TOP + Vector((-0.04, 0.22, -0.03))],
         [0.145, 0.120, 0.092, 0.025], 6, 'timber', C_OAK_RICH, mode='flat',
         scols=[C_OAK_DEEP, C_OAK_RICH, C_DRIFT_MID, C_DRIFT_PALE])
    for t_h in (0.24, 0.56, 0.80):
        hp = MAST_BASE.lerp(MAST_TOP, t_h)
        with xf(mb, T(hp) @ R('Z', 4.5)):
            cyl(mb, 0.125 * (1.0 - 0.22 * t_h), -0.038, 0.038, 6, 'iron', C_IRON_FORGED, False, 0.0)
    for ch_dx, ch_dz in ((-0.16, 0.14), (0.18, -0.10), (0.12, 0.18)):
        _add_beam(mb, MAST_BASE + Vector((ch_dx * 2.2, 0.0, ch_dz * 2.2)),
                  MAST_BASE + Vector((ch_dx * 0.4, 0.48, ch_dz * 0.4)), 0.09, 0.09, 'timber', C_OAK_DEEP, 0.0)
    yard_c = MAST_BASE.lerp(MAST_TOP, 0.86)
    _add_beam(mb, yard_c + Vector((-0.26, -0.04, -0.18)), yard_c + Vector((0.36, 0.05, 0.24)),
              0.062, 0.062, 'timber', C_DRIFT_MID, 0.0)
    for st_end in (Vector((-1.92, DECK_Y + 0.06, 0.92)), Vector((-0.78, 1.32, -1.44))):
        tube(mb, [MAST_BASE.lerp(MAST_TOP, 0.72), st_end], 0.020, 4, 'rope', C_ROPE, mode='flat')

    # Tattered Patched Crimson-and-Cream Signal Flag billowing in broadside profile ('paint' + UV2!)
    flag_root = MAST_BASE.lerp(MAST_TOP, 0.85) + Vector((0.08, 0.0, 0.04))
    _build_patched_signal_flag(mb, flag_root, length=1.84, height=0.94,
                               out_dir=(0.96, -0.04, -0.28), phase=0.31)
    for fy in (-0.36, 0.36):
        with xf(mb, T(flag_root + Vector((-0.07, fy, -0.04)))):
            torus(mb, 0.102, 0.024, 5, 4, 'rope', C_ROPE, False)

    # 5. Sheltered Stone Campfire Hearth with Glowing Molten Embers ('glass'!) & Iron Kettle Tripod
    FIRE_C = Vector((0.06, DECK_Y + 0.04, 0.34))
    # Ring of 9 soot-charred faceted hearth cobbles
    for k in range(9):
        ang = 2.0 * pi * k / 9.0 + rng.uniform(-0.10, 0.10)
        fr = 0.52 + rng.uniform(-0.04, 0.04)
        fx = FIRE_C.x + fr * cos(ang)
        fz = FIRE_C.z + fr * sin(ang)
        with xf(mb, T(fx, FIRE_C.y - 0.02, fz) @ R('Y', degrees(ang)) @ R('Z', rng.uniform(-8, 8))):
            cyl(mb, 0.14, 0.0, 0.21, 5,
                'basalt' if k % 2 == 0 else 'limestone',
                C_COBBLE_DARK if k % 2 == 0 else C_COBBLE_MID, False, 0.0, 0.10)

    # Glowing incandescent ember bed + charred criss-crossed driftwood fire logs + licking molten flames ('glass'!)
    with xf(mb, T(FIRE_C)):
        # Heaped glowing ember mound ('glass' molten colors!)
        lathe(mb, [(0.0, 0.0), (0.42, 0.04), (0.34, 0.15), (0.18, 0.22), (0.0, 0.24)],
              7, 'glass', C_FLAME_MID, False, False,
              lambda i, k: C_FLAME_CORE if i >= 2 else C_FLAME_DEEP)
        # 4 criss-crossed charred oak firewood logs
        for lang, tilt_z in ((12.0, 18.0), (104.0, -16.0), (208.0, 20.0), (305.0, -15.0)):
            with xf(mb, R('Y', lang) @ R('Z', tilt_z)):
                cyl(mb, 0.056, -0.34, 0.34, 5, 'timber', C_OAK_CHAR, False, 0.0, 0.048)
        # Sculpted faceted campfire flames licking upward ('glass' incandescent amber-gold!)
        lathe(mb, [(0.0, 0.14), (0.22, 0.26), (0.14, 0.48), (0.0, 0.66)],
              5, 'glass', C_FLAME_CORE, False, False,
              lambda i, k: C_FLAME_WHITE if i == 1 else (C_FLAME_CORE if i == 2 else C_FLAME_MID))
        for fl_x, fl_z, fl_h, fl_r in ((-0.16, -0.10, 0.44, 0.11), (0.15, 0.12, 0.48, 0.12), (0.10, -0.15, 0.38, 0.10)):
            with xf(mb, T(fl_x, 0.14, fl_z) @ R('Z', rng.uniform(-16, 16))):
                lathe(mb, [(0.0, 0.0), (fl_r, fl_h * 0.32), (0.0, fl_h)], 4, 'glass', C_FLAME_MID, False)

        # Simple lashed driftwood cooking tripod & blackened iron stew kettle over the fire!
        tri_apex = Vector((0.0, 1.38, 0.0))
        for k in range(3):
            ang = radians(35.0 + k * 120.0)
            foot = Vector((0.76 * cos(ang), -0.02, 0.76 * sin(ang)))
            _add_beam(mb, foot, tri_apex + Vector((0.06 * cos(ang), 0.12, 0.06 * sin(ang))),
                      0.052, 0.052, 'timber', C_DRIFT_DARK, 0.0)
        with xf(mb, T(tri_apex)):
            torus(mb, 0.08, 0.022, 5, 4, 'rope', C_ROPE, False)
        _add_beam(mb, tri_apex, (0.0, 0.88, 0.0), 0.022, 0.022, 'iron', C_IRON_FORGED, 0.0)
        # Blackened cast-iron castaway kettle
        lathe(mb, [(0.0, 0.62), (0.16, 0.65), (0.21, 0.78), (0.16, 0.88), (0.18, 0.91), (0.13, 0.91), (0.0, 0.87)],
              6, 'iron', C_IRON_DARK, False, False,
              lambda i, k: C_IRON_RUST_HI if i == 0 else C_IRON_DARK)

    # 6. Oak Rum Kegs, Open Crate of Provisions & Coiled Hemp Rope inside the Camp!
    # Upright crimson-banded oak rum keg + tilted resting rum keg on timber chocks (port-rear camp)
    _build_coopered_cask(mb, T(-1.12, DECK_Y + 0.39, 0.78) @ R('Y', 18.0),
                         radius=0.30, height=0.76, rng=rng, stripe_col=C_CRIMSON_HI)
    # Brass spigot tap on the upright rum keg
    cbox(mb, (-0.84, DECK_Y + 0.44, 0.68), (0.14, 0.05, 0.05), 'brass', C_GOLD_BRIGHT, 0.0)
    _build_coopered_cask(mb, T(-1.38, DECK_Y + 0.30, 0.06) @ R('Y', -32.0) @ R('Z', 90.0),
                         radius=0.28, height=0.72, rng=rng, stripe_col=C_TEAL_HULL)

    # Open Wooden Crate of Castaway Provisions (starboard-rear camp!)
    CR_C = Vector((1.14, DECK_Y + 0.28, 0.64))
    with xf(mb, T(CR_C) @ R('Y', -24.0)):
        # Bottom floor & 4 slatted oak crate walls (leaving top open!)
        cbox(mb, (0.0, -0.22, 0.0), (0.76, 0.06, 0.56), 'timber', C_OAK_DEEP, 0.0)
        for sz in (-0.26, 0.26):
            cbox(mb, (0.0, 0.02, sz), (0.76, 0.46, 0.05), 'timber', C_OAK_SUN, 0.0)
        for sx in (-0.36, 0.36):
            cbox(mb, (sx, 0.02, 0.0), (0.05, 0.46, 0.56), 'timber', C_OAK_RICH, 0.0)
        for sx in (-0.35, 0.35):
            for sz in (-0.25, 0.25):
                cbox(mb, (sx, 0.02, sz), (0.07, 0.48, 0.07), 'timber', C_OAK_DEEP, 0.0)
        # Provisions tucked inside the open crate: rolled canvas bundle, golden hardtack sack & 3 rum bottles!
        with xf(mb, T(-0.14, 0.18, 0.02) @ R('Z', 90.0)):
            cyl(mb, 0.12, -0.20, 0.20, 6, 'paint', C_CREAM_SAIL, False, 0.0)
            cyl(mb, 0.125, -0.02, 0.02, 6, 'rope', C_ROPE, False, 0.0)
        for bx, bz, bcol in ((0.18, -0.10, C_TEAL_HULL), (0.22, 0.10, C_OAK_SUN), (0.06, 0.12, C_CRIMSON_MID)):
            with xf(mb, T(bx, 0.02, bz)):
                lathe(mb, [(0.0, 0.0), (0.065, 0.0), (0.065, 0.24), (0.028, 0.32), (0.028, 0.40), (0.0, 0.40)],
                      5, 'paint', bcol, False)
        # Pried-off slatted crate lid leaning casually against the starboard side of the crate
        with xf(mb, T(0.50, 0.02, 0.02) @ R('Z', -26.0)):
            cbox(mb, (0.0, 0.0, 0.0), (0.045, 0.54, 0.52), 'timber', C_DRIFT_MID, 0.0)

    # Coiled hemp hawser rope pile near the starboard barricade entry
    _build_rope_coil_lean(mb, (1.34, DECK_Y + 0.02, -0.34), radius=0.28, turns=2, r=0.038, segs=6, psegs=4)

    # 7. Coastal Tuft Ferns ('foliage' + UV2!) framing the beachhead rampart & shore cobbles
    for fpos, fsc, flean, fph in (
        ((-2.02, DECK_Y + 0.02, -0.88), 0.78, (-0.8, 0.0, -0.6), 0.12),
        ((-1.26, DECK_Y + 0.02, -1.66), 0.72, (-0.5, 0.0, -0.8), 0.36),
        (( 1.38, DECK_Y + 0.02, -1.52), 0.76, ( 0.6, 0.0, -0.8), 0.58),
        (( 2.04, DECK_Y + 0.02, -0.46), 0.74, ( 0.9, 0.0, -0.3), 0.79),
        ((-1.72, DECK_Y + 0.02,  1.42), 0.78, (-0.7, 0.0,  0.7), 0.24),
        (( 1.82, DECK_Y + 0.02,  1.24), 0.72, ( 0.7, 0.0,  0.7), 0.92),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=4, rng=rng, phase=fph, lean_dir=flean)

    # Lantern_BarricadeCamp empty right above the crackling glowing campfire hearth!
    LANTERN_POS = FIRE_C + Vector((0.0, 0.66, 0.0))

    build(mb)

    add_empty('Lantern_BarricadeCamp', LANTERN_POS)
    col_piece('col_barricade_base', col_pts)
    export_landmark_glb(outdir, 'coastal_shipwreck_barricade_camp.glb')


# ==============================================================================
# 4. VOLCANIC OBSIDIAN LAVA GATE (volcanic_obsidian_lava_gate.glb)
# ==============================================================================

def _build_brazier_skull_crest(mb, center, face_z=-1.0, scale=0.88):
    """Sinister forged-iron & pale charred-bone skull relief crest with blazing molten 'glass' eyes!"""
    s = scale
    yaw = 0.0 if face_z < 0.0 else 180.0
    with xf(mb, T(center) @ R('Y', yaw)):
        # Sculpted bone cranium + dark forged-iron horned brow crown
        cbox(mb, (0.0, 0.14 * s, 0.0), (0.44 * s, 0.34 * s, 0.24 * s), 'skull_stone', C_SKULL_BONE, 0.0)
        cbox(mb, (0.0, 0.24 * s, -0.12 * s), (0.50 * s, 0.10 * s, 0.10 * s), 'iron', C_IRON_BRIGHT, 0.0)
        # Blazing molten fire eye sockets ('glass'!)
        for sx in (-1.0, 1.0):
            cbox(mb, (sx * 0.12 * s, 0.08 * s, -0.13 * s), (0.12 * s, 0.12 * s, 0.07 * s),
                 'glass', C_FLAME_CORE, 0.0)
        # Nose cavity & grinning jawbone teeth
        cbox(mb, (0.0, -0.02 * s, -0.13 * s), (0.08 * s, 0.09 * s, 0.06 * s), 'basalt', C_OBSIDIAN_ABYSS, 0.0)
        cbox(mb, (0.0, -0.13 * s, -0.05 * s), (0.34 * s, 0.14 * s, 0.18 * s), 'skull_stone', C_SKULL_MID, 0.0)
        for tx in (-0.09, 0.0, 0.09):
            cbox(mb, (tx * s, -0.15 * s, -0.15 * s), (0.055 * s, 0.10 * s, 0.04 * s),
                 'skull_stone', C_SKULL_BONE, 0.0)


def gen_volcanic_obsidian_lava_gate(outdir):
    """Towering ~6.8 m cursed volcanic basalt rune pylon gateway rooted in a wide fractured
    hexagonal obsidian foundation plunging to y = -3.60 m (footprint hx=2.65 m, hz=2.15 m),
    twin leaning jagged columnar-basalt monolith pylons etched with blazing molten magma veins
    ('glass' bright incandescent orange-gold linear COLOR_0), bridged overhead by a spiked
    forged-iron arch & heavy draped chains suspending a glowing iron skull-caged molten fire
    brazier directly over the open portal center, flanked by obsidian shard spurs, collider
    'col_lavagate_base', and 'Lantern_LavaGate' empty inside the fire-cage brazier."""
    clear_scene()
    mb = MB('volcanic_obsidian_lava_gate', seed=1704)
    rng = random.Random(SEED + 1704)
    col_pts = []

    DECK_Y = 0.56

    # 1. Wide Fractured Hexagonal Obsidian Foundation plunging cleanly to y = -3.60 m (hx=2.65, hz=2.15)
    found_secs = [
        _reg_poly(0.0, -3.60, 0.0, 1.0, sides=6, rot_deg=0.0, sx=2.65, sz=2.15),
        _reg_poly(0.0, -1.60, 0.0, 1.0, sides=6, rot_deg=0.0, sx=2.58, sz=2.08),
        _reg_poly(0.0,  0.00, 0.0, 1.0, sides=6, rot_deg=0.0, sx=2.48, sz=2.00),
        _reg_poly(0.0,  0.30, 0.0, 1.0, sides=6, rot_deg=0.0, sx=2.36, sz=1.88),
    ]
    _loft_horizontal_masonry(
        mb, found_secs, 'basalt',
        [C_OBSIDIAN_ABYSS, C_OBSIDIAN_DARK, C_OBSIDIAN_MID, C_OBSIDIAN_HI],
        rng, caps=(True, True), top_mat='basalt', top_col=C_OBSIDIAN_MID,
    )
    deck_secs = [
        _reg_poly(0.0, 0.28, 0.0, 1.0, sides=6, rot_deg=0.0, sx=2.14, sz=1.66),
        _reg_poly(0.0, DECK_Y, 0.0, 1.0, sides=6, rot_deg=0.0, sx=2.04, sz=1.56),
    ]
    _loft_horizontal_masonry(
        mb, deck_secs, 'basalt',
        [C_OBSIDIAN_MID, C_OBSIDIAN_HI],
        rng, caps=(False, True), top_mat='basalt', top_col=C_OBSIDIAN_MID,
    )

    for y_c, sx_c, sz_c in ((-3.60, 2.64, 2.14), (0.0, 2.46, 1.98), (DECK_Y, 2.04, 1.56), (5.20, 1.92, 0.82)):
        col_pts.extend(_reg_poly(0.0, y_c, 0.0, 1.0, sides=6, rot_deg=0.0, sx=sx_c, sz=sz_c))

    # Stepped volcanic basalt threshold slabs on BOTH -Z seaward & +Z rear sides
    for z_sgn in (-1.0, 1.0):
        cbox(mb, (0.0, 0.14, z_sgn * 1.80), (1.76, 0.28, 0.36), 'basalt', C_OBSIDIAN_MID, 0.0)
        cbox(mb, (0.0, 0.38, z_sgn * 1.52), (1.56, 0.26, 0.36), 'basalt', C_OBSIDIAN_HI, 0.0)

    # Raised fractured hexagonal basalt floor slabs + glowing molten lava threshold cracks ('glass'!)
    for hx_p, hz_p, hr_p, hh_p in (
        (-0.56, -0.44, 0.38, 0.06), (0.58, -0.38, 0.40, 0.07),
        (-0.52,  0.46, 0.36, 0.06), (0.54,  0.42, 0.38, 0.07),
    ):
        cyl(mb, hr_p, DECK_Y - 0.02, DECK_Y + hh_p, 6, 'basalt', C_OBSIDIAN_HI, False, 0.0)

    # Molten magma fissure veins cutting across the central threshold deck!
    _sculpt_magma_ribbon(
        mb,
        [(0.0, DECK_Y + 0.02, -1.56), (0.12, DECK_Y + 0.04, -0.78), (0.0, DECK_Y + 0.05, 0.0),
         (-0.14, DECK_Y + 0.04, 0.78), (0.0, DECK_Y + 0.02, 1.54)],
        [0.14, 0.19, 0.24, 0.18, 0.14], (0.0, 1.0, 0.0), hot_core=True, ridge_h=0.055,
    )
    for sgn in (-1.0, 1.0):
        _sculpt_magma_ribbon(
            mb,
            [(0.0, DECK_Y + 0.04, 0.0), (sgn * 0.68, DECK_Y + 0.04, -0.14), (sgn * 1.32, DECK_Y + 0.05, 0.0)],
            [0.18, 0.15, 0.14], (0.0, 1.0, 0.0), hot_core=True, ridge_h=0.050,
        )

    # 2. Twin Leaning Jagged Columnar-Basalt Monolith Pylons (~6.65 - 6.85 m tall!)
    pylon_collar_pts = {}  # store upper collar inner anchors for arch & chains
    for sgn, h_top, lean_in in ((-1.0, 6.84, 0.12), (1.0, 6.62, 0.10)):
        # Sweeping stepped hexagonal monolith profile leaning subtly inward over the portal then spiking jaggedly!
        spec = [
            (sgn * 1.72, DECK_Y - 0.08,  0.00, 0.78, 0.74, C_OBSIDIAN_DARK),
            (sgn * 1.66, 1.64,           0.00, 0.70, 0.66, C_OBSIDIAN_MID),
            (sgn * 1.56, 2.86,          -0.02, 0.64, 0.60, C_OBSIDIAN_HI),
            (sgn * 1.48, 4.18,          -0.03, 0.58, 0.54, C_OBSIDIAN_HI),
            (sgn * 1.44 + sgn * lean_in, 5.26, -0.02, 0.50, 0.46, C_OBSIDIAN_EDGE),
            (sgn * 1.58 + sgn * lean_in, 6.18,  0.02, 0.34, 0.30, C_OBSIDIAN_EDGE),
            (sgn * 1.72 + sgn * lean_in, h_top, 0.04, 0.08, 0.07, C_OBSIDIAN_EDGE),
        ]
        p_secs = []
        p_cols = []
        for idx_s, (px, py, pz, rx, rz, col) in enumerate(spec):
            ring = []
            for k in range(6):
                ang = radians(30.0 + k * 60.0)
                jag = 1.0 + 0.09 * sin(ang * 2.0 + idx_s * 1.4)
                y_sl = (0.28 * cos(ang) if idx_s == len(spec) - 2 else 0.0)
                ring.append(Vector((px + rx * jag * cos(ang), py + y_sl, pz + rz * jag * sin(ang))))
            p_secs.append(ring)
            p_cols.append(col)
        loft(mb, p_secs, 'basalt', C_OBSIDIAN_HI, closed=True, caps=(False, True), mode='flat', scols=p_cols)

        # Clustered hexagonal basalt organ-pipe shoulder columns hugging each monolith base!
        for ox, oz, ch_col, crad, tx, tz in (
            (sgn * 0.58, -0.44, 3.15, 0.34, sgn * 4.0, -3.0),
            (sgn * 0.54,  0.46, 2.85, 0.32, sgn * 3.0,  3.5),
            (sgn * 0.22,  0.64, 2.20, 0.28, sgn * 2.0,  5.0),
            (sgn * 0.20, -0.62, 2.40, 0.28, sgn * 2.0, -5.0),
        ):
            sculpt_basalt_column(
                mb, (sgn * 1.62 + ox, DECK_Y - 0.14, oz), ch_col, crad, 6,
                tx, tz, C_OBSIDIAN_DARK, C_OBSIDIAN_HI, rng, mat='basalt', magma_seam=True,
            )

        # Heavy Bolted Forged-Iron Rune-Binding Collars clamping each monolith at y = 2.40 m & y = 4.56 m!
        for col_y, col_r, col_h, cx_c in ((2.40, 0.72, 0.22, sgn * 1.59), (4.56, 0.62, 0.26, sgn * 1.48)):
            with xf(mb, T(cx_c, col_y, -0.02)):
                cyl(mb, col_r, -col_h * 0.5, col_h * 0.5, 6, 'iron', C_IRON_FORGED, False, 0.0)
                # Protruding forged-iron collar spikes on outer cheek
                for ang_sp in (0.0, 60.0, -60.0):
                    ar = radians(ang_sp if sgn > 0 else 180.0 - ang_sp)
                    sx_p = cos(ar) * (col_r - 0.02)
                    sz_p = sin(ar) * (col_r - 0.02)
                    _add_beam(mb, (sx_p, 0.0, sz_p), (sx_p + cos(ar) * 0.26, 0.06, sz_p + sin(ar) * 0.26),
                              0.08, 0.08, 'iron', C_IRON_BRIGHT, 0.0)

        pylon_collar_pts[sgn] = Vector((sgn * 1.44, 4.56, -0.02))

        # Blazing Molten Magma Veins ('glass' bright incandescent orange-gold!) etching BOTH front, rear & inner faces!
        # Front (-Z) zig-zag molten fissure rising almost the entire height of the monolith!
        front_vein = [
            (sgn * 1.66, 0.66, -0.66),
            (sgn * 1.52, 1.58, -0.62),
            (sgn * 1.68, 2.52, -0.58),
            (sgn * 1.44, 3.56, -0.54),
            (sgn * 1.58, 4.78, -0.46),
            (sgn * 1.66, 5.88, -0.30),
        ]
        _sculpt_magma_ribbon(mb, front_vein, [0.15, 0.13, 0.13, 0.11, 0.095, 0.060],
                             (0.0, 0.0, -1.0), hot_core=True, ridge_h=0.065)

        # Rear (+Z) molten fissure so rear 3/4 glows just as fiercely!
        rear_vein = [
            (sgn * 1.66, 0.68, 0.66),
            (sgn * 1.72, 1.74, 0.62),
            (sgn * 1.50, 2.86, 0.56),
            (sgn * 1.62, 4.12, 0.50),
            (sgn * 1.56, 5.42, 0.36),
        ]
        _sculpt_magma_ribbon(mb, rear_vein, [0.14, 0.12, 0.12, 0.10, 0.065],
                             (0.0, 0.0, 1.0), hot_core=True, ridge_h=0.062)

        # Inner portal face molten lava rune sigil (glowing chevron + vertical vein facing the portal center!)
        in_vein = [
            (sgn * 1.04, 0.72,  0.00),
            (sgn * 1.00, 1.88, -0.14),
            (sgn * 0.96, 3.06,  0.14),
            (sgn * 0.94, 4.18,  0.00),
        ]
        _sculpt_magma_ribbon(mb, in_vein, [0.13, 0.12, 0.11, 0.09],
                             (-sgn, 0.0, 0.0), hot_core=True, ridge_h=0.060)

        # Bold glowing volcanic rune diamonds inlaid into front & rear faces mid-shaft!
        for z_dir in (-1.0, 1.0):
            for ry, rs in ((1.96, 0.18), (3.42, 0.16)):
                cbox(mb, (sgn * 1.56, ry, z_dir * 0.59), (rs, rs * 1.35, 0.08),
                     'glass', C_FLAME_CORE, 0.0, M=R('Z', 45.0))

    # 3. Spiked Forged-Iron Arch Bridge spanning overhead (y = 4.56 to 6.18 m!)
    arch_n = 8
    arch_pts = []
    for i in range(arch_n + 1):
        t = i / float(arch_n)
        u = (t - 0.5) * 2.0  # -1..+1
        ax = u * 1.50
        # Gothic-pointed arch curve peaking sharply at apex y = 5.46 m!
        ay = 4.56 + 0.90 * (1.0 - abs(u) ** 1.45)
        arch_pts.append(Vector((ax, ay, 0.0)))

    # Twin parallel heavy forged-iron arch ribs (front & rear) + cross-bracing iron plates!
    for z_off in (-0.22, 0.22):
        rib_p = [p + Vector((0.0, 0.0, z_off)) for p in arch_pts]
        tube(mb, rib_p, 0.095, 4, 'iron', C_IRON_FORGED, mode='flat',
             scols=[C_IRON_FORGED if i % 2 == 0 else C_IRON_BRIGHT for i in range(arch_n + 1)])
    for i in range(1, arch_n):
        p = arch_pts[i]
        _add_beam(mb, p + Vector((0, 0, -0.24)), p + Vector((0, 0, 0.24)), 0.10, 0.10, 'iron', C_IRON_BRIGHT, 0.0)

    # 7 Cruel Forged-Iron Crown Spikes bristling along the arch bridge spine + tall central trident spire!
    for i in range(1, arch_n):
        p = arch_pts[i]
        u = (i / float(arch_n) - 0.5) * 2.0
        is_apex = (i == arch_n // 2)
        sp_h = 0.86 if is_apex else (0.50 if abs(i - arch_n // 2) == 1 else 0.36)
        sp_r = 0.095 if is_apex else 0.068
        sp_dir = Vector((u * 0.28, 1.0, 0.0)).normalized()
        tube(mb, [p, p + sp_dir * (sp_h * 0.52), p + sp_dir * sp_h],
             [sp_r, sp_r * 0.56, 0.014], 4, 'iron', C_IRON_BRIGHT if is_apex else C_IRON_FORGED, mode='flat')
        if is_apex:
            # Twin curved side-barbs on the central iron arch spear crest + hot molten ember jewel!
            for sgn in (-1.0, 1.0):
                _add_beam(mb, p + Vector((0.0, 0.24, 0.0)), p + Vector((sgn * 0.30, 0.54, 0.0)),
                          0.055, 0.055, 'iron', C_IRON_BRIGHT, 0.0)
            cbox(mb, p + Vector((0.0, 0.18, 0.0)), (0.14, 0.14, 0.30), 'glass', C_FLAME_CORE, 0.0, M=R('Z', 45.0))

    # Central heavy iron clevis ring hanging beneath arch apex
    APEX_HOOK = Vector((0.0, 5.26, 0.0))
    with xf(mb, T(APEX_HOOK) @ M_Y2Z):
        torus(mb, 0.11, 0.032, 5, 4, 'iron', C_IRON_BRIGHT, False)

    # 4. Heavy Draped Chains & Suspended Glowing Iron Skull-Caged Molten Fire Brazier (portal center!)
    BRAZ_C = Vector((0.0, 3.24, 0.0))
    BRAZ_TOP_RING = Vector((0.0, 4.10, 0.0))

    # Primary heavy forged-iron suspension chain dropping from arch apex to brazier crown ring
    _add_chain_links(mb, APEX_HOOK - Vector((0.0, 0.06, 0.0)), BRAZ_TOP_RING + Vector((0.0, 0.05, 0.0)),
                     n_links=5, link_r=0.14, wire_r=0.042, segs=5, psegs=4, sag=0.0,
                     mat='iron', rust_stride=2, stretch_y=1.42,
                     col_a=C_IRON_FORGED, col_b=C_IRON_RUST_HI)

    # Twin draped stabilizing chains from visible inner pylon iron collar shackles down to brazier side shackles!
    for sgn in (-1.0, 1.0):
        p_col_shack = Vector((sgn * 0.86, 4.46, 0.0))
        p_braz_shack = BRAZ_C + Vector((sgn * 0.56, 0.30, 0.0))
        with xf(mb, T(p_col_shack) @ M_Y2Z):
            torus(mb, 0.095, 0.028, 5, 4, 'iron', C_IRON_BRIGHT, False)
        with xf(mb, T(p_braz_shack) @ M_Y2Z):
            torus(mb, 0.090, 0.026, 5, 4, 'iron', C_IRON_RUST_HI, False)
        _add_chain_links(mb, p_col_shack, p_braz_shack,
                         n_links=5, link_r=0.130, wire_r=0.038, segs=5, psegs=4, sag=0.18,
                         mat='iron', rust_stride=2, stretch_y=1.42,
                         col_a=C_IRON_FORGED, col_b=C_IRON_RUST_HI)

    # Suspended Iron Skull-Caged Molten Fire Brazier!
    with xf(mb, T(BRAZ_C)):
        # Heavy forged-iron ribbed conical fire basket bowl + cruel lower drop spike!
        bowl_prof = [
            (0.00, -0.78),  # bottom iron drop finial spike
            (0.11, -0.46),
            (0.36, -0.32),
            (0.56,  0.04),
            (0.60,  0.22),  # thick iron rim flange
            (0.46,  0.22),
            (0.38, -0.14),
            (0.00, -0.18),
        ]
        lathe(mb, bowl_prof, 8, 'iron', C_IRON_FORGED, False, False,
              lambda i, k: C_IRON_RUST_HI if i in (0, 4) else (C_IRON_DARK if i >= 5 else C_IRON_FORGED))

        # 4 Curved Forged-Iron Cage Bars arching from rim up to the top crown ring!
        for k in range(4):
            ang = radians(45.0 + k * 90.0)
            ca, sa = cos(ang), sin(ang)
            cage_pts = [
                Vector((0.55 * ca, 0.20, 0.55 * sa)),
                Vector((0.58 * ca, 0.50, 0.58 * sa)),
                Vector((0.36 * ca, 0.74, 0.36 * sa)),
                Vector((0.12 * ca, 0.86, 0.12 * sa)),
            ]
            tube(mb, cage_pts, [0.046, 0.042, 0.038, 0.034], 4, 'iron', C_IRON_BRIGHT, mode='flat')
        # Upper cage iron band & crown suspension ring
        cyl(mb, 0.16, 0.80, 0.90, 6, 'iron', C_IRON_FORGED, False, 0.0, 0.12)
        with xf(mb, T(0.0, 0.92, 0.0) @ M_Y2Z):
            torus(mb, 0.095, 0.028, 5, 4, 'iron', C_IRON_BRIGHT, False)

        # Twin Sinister Skull Relief Crests mounted on BOTH seaward (-Z) and rear (+Z) brazier rims!
        _build_brazier_skull_crest(mb, (0.0, 0.12, -0.58), face_z=-1.0, scale=0.90)
        _build_brazier_skull_crest(mb, (0.0, 0.12,  0.58), face_z= 1.0, scale=0.90)

        # Roaring Blazing Molten Fire Core ('glass' incandescent orange-gold!) leaping inside the skull cage!
        lathe(mb, [(0.0, -0.06), (0.42, 0.10), (0.34, 0.38), (0.18, 0.62), (0.0, 0.78)],
              6, 'glass', C_FLAME_CORE, False, False,
              lambda i, k: C_FLAME_WHITE if i == 1 else (C_FLAME_CORE if i == 2 else C_FLAME_MID))
        # Secondary leaping molten flame tongues around the main core
        for fx, fz, fh, fr in ((-0.22, -0.14, 0.54, 0.14), (0.24, 0.12, 0.58, 0.14), (0.16, -0.20, 0.46, 0.12)):
            with xf(mb, T(fx, 0.08, fz) @ R('Z', -fx * 55.0)):
                lathe(mb, [(0.0, 0.0), (fr, fh * 0.35), (0.0, fh)], 4, 'glass', C_FLAME_MID, False)

    # 5. Flanking Razor-Sharp Obsidian Shard Spurs bursting from the volcanic foundation!
    for sx_b, sz_b, sh_s, sr_s, tilt_x, tilt_z in (
        (-2.34, -0.96, 2.55, 0.36, -18.0, -14.0),
        ( 2.38, -0.88, 2.38, 0.35,  17.0, -13.0),
        (-2.28,  1.06, 2.22, 0.34, -16.0,  16.0),
        ( 2.32,  1.02, 2.46, 0.36,  18.0,  15.0),
        (-1.84, -1.62, 1.56, 0.28, -10.0, -22.0),
        ( 1.88, -1.58, 1.48, 0.28,  12.0, -20.0),
    ):
        s_dir = Vector((sin(radians(tilt_x)), 1.0, sin(radians(tilt_z)))).normalized()
        bp = Vector((sx_b, DECK_Y - 0.32, sz_b))
        sp_pts = [
            bp,
            bp + s_dir * (sh_s * 0.45),
            bp + s_dir * (sh_s * 0.82),
            bp + s_dir * sh_s,
        ]
        tube(mb, sp_pts, [sr_s, sr_s * 0.78, sr_s * 0.42, 0.022], 5, 'basalt', C_OBSIDIAN_HI,
             caps=(False, True), mode='flat',
             scols=[C_OBSIDIAN_DARK, C_OBSIDIAN_MID, C_OBSIDIAN_HI, C_OBSIDIAN_EDGE])
        # Glowing molten basal crack kissing the root of the outer front shard spurs
        if sz_b < 0.0 and sh_s > 2.0:
            v_nrm = Vector((sx_b, 0.2, sz_b)).normalized()
            _sculpt_magma_ribbon(
                mb, [bp + Vector((0, 0.35, 0)) + v_nrm * (sr_s * 0.72),
                     sp_pts[1] + v_nrm * (sr_s * 0.62)],
                [0.10, 0.055], v_nrm, hot_core=False, ridge_h=0.045,
            )

    # Lantern_LavaGate empty positioned directly inside the suspended iron skull-caged molten fire brazier!
    LANTERN_POS = BRAZ_C + Vector((0.0, 0.24, 0.0))

    build(mb)

    add_empty('Lantern_LavaGate', LANTERN_POS)
    col_piece('col_lavagate_base', col_pts)
    export_landmark_glb(outdir, 'volcanic_obsidian_lava_gate.glb')


EXPEDITION_CRAFT_GENERATORS = [
    gen_pirate_chart_navigator_gazebo,
    gen_ancient_sun_serpent_archway,
    gen_coastal_shipwreck_barricade_camp,
    gen_volcanic_obsidian_lava_gate,
]
