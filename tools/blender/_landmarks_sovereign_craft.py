# Sea of Scoundrels: 4 sculpted 3D Sovereign Craft & Mythic Coast Landmarks
# (Wave I-22 / Pass I-Q15 — THE HISTORIC 90-LANDMARK MILESTONE: 86 -> 90 Zero-Extra-VRAM Landmarks!).
# Imported by tools/blender/gen_island_landmarks.py.
# Authored in Godot game coordinates (-Z seaward/hero-facing, +Y up, +X starboard, metres)
# and converted to Blender's Z-up frame on mesh creation via _landmark_common.
# STRICT SHARED-TEXTURE DEDUP CONTRACT: uses ONLY the 11 existing shared PBR materials
# (limestone, limestone_moss, basalt, temple_stone, skull_stone, timber, paint, rope,
# iron, brass, foliage) + untextured glass / skull_glow / col.
# Emissive rule:
#   - mat_landmark_skull_glow ONLY on ancient_astral_tide_obelisk (hovering luminous
#     turquoise-cyan astrolabe tide crystal & glowing carved glyph bands)
#   - mat_landmark_glass with warm amber/molten linear COLOR_0 on pirate_cooperage_barrel_workshop,
#     coastal_buccaneer_net_mending_pier, and volcanic_obsidian_leviathan_spire (ZERO skull_glow!).
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

# Coastal harbour cobble, beach sandstone & mossy astral temple masonry
C_SANDSTONE_HI   = srgb('#ebd8b4')
C_SANDSTONE_MID  = srgb('#c7a477')
C_SANDSTONE_DARK = srgb('#8a6d50')
C_SANDSTONE_DEEP = srgb('#544638')
C_COBBLE_HI      = srgb('#d2c6af')
C_COBBLE_MID     = srgb('#958a78')
C_COBBLE_DARK    = srgb('#5d554b')
C_COBBLE_WET     = srgb('#3d3d38')

C_ASTRAL_HI      = srgb('#ded6c0')
C_ASTRAL_MID     = srgb('#a69f8b')
C_ASTRAL_DARK    = srgb('#6d695a')
C_ASTRAL_DEEP    = srgb('#48483e')
C_MOSS_CUSHION   = srgb('#4b8231')
C_MOSS_DEEP      = srgb('#2a5020')

# Cooper's seasoned oak, fresh-split pale staves, weathered cedar & tarred pier pilings
C_STAVE_PALE     = srgb('#e7c38a')
C_OAK_SUN        = srgb('#cc9152')
C_OAK_RICH       = srgb('#8e5a2f')
C_OAK_DEEP       = srgb('#54341c')
C_OAK_CHAR       = srgb('#2a1c14')
C_CEDAR_SUN      = srgb('#c89c70')
C_CEDAR_WEATHER  = srgb('#9d8b76')
C_CEDAR_DARK     = srgb('#5d5247')
C_SHINGLE_A      = srgb('#855b3c')
C_SHINGLE_B      = srgb('#644734')
C_SHINGLE_MOSS   = srgb('#5a6a49')

# Painted accents: cooper's guild crimson, cream, coastal teal, cork & tarred nets
C_CRIMSON_HI     = srgb('#dc3424')
C_CRIMSON_MID    = srgb('#a12219')
C_CRIMSON_DARK   = srgb('#641410')
C_CREAM_BRIGHT   = srgb('#f5e8cc')
C_CREAM_AGED     = srgb('#d4bf98')
C_TEAL_HI        = srgb('#249094')
C_TEAL_MID       = srgb('#19666b')
C_SEA_GLASS      = srgb('#45bda4')
C_SEA_GLASS_DARK = srgb('#1d6f64')
C_FISH_SILVER    = srgb('#a9c8d2')
C_FISH_BACK      = srgb('#356d7e')

C_HEMP_HI        = srgb('#e4c58d')
C_HEMP_MID       = srgb('#be995d')
C_HEMP_DARK      = srgb('#866638')
C_NET_TAR_HI     = srgb('#78674c')
C_NET_TAR_MID    = srgb('#544736')
C_NET_TAR_DARK   = srgb('#362e23')
C_CORK_HI        = srgb('#e3b677')
C_CORK_MID       = srgb('#b8884d')

# Metals: gilded astral bronze, burnished brass, verdigris bronze, forged & rusted iron
C_GOLD_BRIGHT    = srgb('#fbd452')
C_BRASS_WARM     = srgb('#dba43a')
C_BRASS_DARK     = srgb('#8c611e')
C_VERDIGRIS_HI   = srgb('#58bda4')
C_VERDIGRIS_MID  = srgb('#318773')
C_IRON_BRIGHT    = srgb('#8892a3')
C_IRON_FORGED    = srgb('#4c5262')
C_IRON_DARK      = srgb('#252832')
C_IRON_RUST_HI   = srgb('#b56235')
C_IRON_RUST_MID  = srgb('#7f4324')

# Volcanic charred basalt & high-contrast faceted obsidian
C_OBSIDIAN_EDGE  = srgb('#b4a8c6')
C_OBSIDIAN_HI    = srgb('#786e8a')
C_OBSIDIAN_MID   = srgb('#474054')
C_OBSIDIAN_DARK  = srgb('#282432')
C_OBSIDIAN_ABYSS = srgb('#14111a')

# Luminous turquoise-cyan astral glow (USED ONLY with 'skull_glow' on ancient_astral_tide_obelisk!)
C_AQUA_CORE      = srgb('#78fff5')
C_AQUA_MID       = srgb('#18e0c5')
C_AQUA_DEEP      = srgb('#088f84')

# Warm amber embers, lanterns & incandescent molten lava (USED ONLY with 'glass' on the other 3 GLBs!)
C_FLAME_WHITE    = srgb('#ffd24d')
C_FLAME_CORE     = srgb('#ff7e12')
C_FLAME_MID      = srgb('#e43804')
C_FLAME_DEEP     = srgb('#9e1402')
C_MAGMA_CRIMSON  = srgb('#5e0801')

# Tropical coastal vines & beach ferns
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


def _build_coopered_cask(mb, M_bar, radius=0.28, height=0.70, rng=None,
                         col_a=C_OAK_RICH, col_b=C_OAK_DEEP, col_head=C_OAK_SUN,
                         segs=6, powder_band=False, spigot=False):
    """Chunky coopered oak rum/powder cask with forged-iron hoops, optional crimson powder stripe & brass tap."""
    hh = height * 0.5
    prof = [
        (0.0,           -hh),
        (radius * 0.82, -hh),
        (radius,         0.0),
        (radius * 0.83,  hh),
        (radius * 0.72,  hh),
        (0.0,            hh - 0.03),
    ]
    stave_cols = [
        jit(col_a if k % 2 == 0 else col_b, rng, 0.04, 0.012) if rng else col_a
        for k in range(segs)
    ]
    with xf(mb, M_bar):
        lathe(mb, prof, segs, 'timber', col_a, False, False,
              lambda i, k: col_head if i >= 4 else (C_OAK_CHAR if i == 0 else stave_cols[k]))
        for hy, hr, hcol in (
            (-hh * 0.68, radius * 0.92, C_IRON_FORGED),
            (-hh * 0.28, radius * 0.99, C_IRON_DARK),
            ( hh * 0.28, radius * 0.99, C_IRON_RUST_HI),
            ( hh * 0.68, radius * 0.92, C_IRON_FORGED),
        ):
            _open_band(mb, hr, hy - 0.024, hy + 0.024, segs, 'iron', hcol)
        if powder_band:
            _open_band(mb, radius * 1.01, -hh * 0.14, hh * 0.14, segs, 'paint', C_CRIMSON_HI)
        if spigot:
            with xf(mb, T(0.0, -hh * 0.44, -radius * 0.98) @ M_Y2Z):
                cyl(mb, 0.030, -0.04, 0.11, 5, 'brass', C_GOLD_BRIGHT, False, 0.0)
            cbox(mb, (0.0, -hh * 0.44 + 0.04, -radius * 1.08), (0.09, 0.03, 0.03), 'brass', C_BRASS_WARM, 0.0)


def _build_rope_coil(mb, center, radius=0.26, turns=2, r=0.044, segs=6, psegs=4,
                     col_a=C_HEMP_HI, col_b=C_HEMP_MID):
    """Stacked coiled braided mooring rope pile ('rope')."""
    for i in range(turns):
        rr = radius * (1.0 - 0.19 * i)
        with xf(mb, T(center[0], center[1] + r * (1.0 + i * 1.56), center[2])):
            torus(mb, rr, r, segs, psegs, 'rope', col_a if i % 2 == 0 else col_b, True)


def _build_wind_banner(mb, root_pos, length=1.38, h0=0.42, out_dir=(0.92, -0.02, -0.38),
                       col_main=C_CRIMSON_HI, col_alt=C_CREAM_BRIGHT, col_trim=C_GOLD_BRIGHT,
                       phase=0.28, swallowtail=True):
    """Wind-whipped double-sided striped guild pennant ('paint') with UV2 breeze weights."""
    rp = Vector(root_pos)
    od = Vector(out_dir).normalized()
    side = Vector((-od.z, 0.0, od.x))
    if side.length < 1e-4:
        side = Vector((1.0, 0.0, 0.0))
    side.normalize()
    segs = 5
    thick = 0.011
    top_pts, bot_pts, weights = [], [], []
    for i in range(segs + 1):
        t = i / float(segs)
        wave = sin(t * 2.15 * pi) * 0.14 * t
        droop = -0.11 * t * t
        taper = 0.42 if swallowtail else 0.72
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


def _add_chain_links(mb, p_start, p_end, n_links=4, link_r=0.18, wire_r=0.050,
                     segs=5, psegs=4, sag=0.14, mat='iron', rust_stride=2, stretch_y=1.42,
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
# 1. PIRATE COOPERAGE BARREL WORKSHOP (pirate_cooperage_barrel_workshop.glb)
# ==============================================================================

def _build_inprogress_barrel_shell(mb, center, radius=0.30, height=0.72):
    """Iconic cooper's 'raised barrel' mid-assembly: splayed pale-oak staves clamped at the base
    by heavy iron raising hoops with a hemp windlass rope drawing the upper staves inward!"""
    cx, cy, cz = center
    n_staves = 8
    with xf(mb, T(cx, cy, cz)):
        for k in range(n_staves):
            ang = 2.0 * pi * k / float(n_staves)
            ca, sa = cos(ang), sin(ang)
            p0 = Vector((radius * 0.84 * ca, 0.00, radius * 0.84 * sa))
            p2 = Vector((radius * 1.20 * ca, height, radius * 1.20 * sa))
            scol = C_STAVE_PALE if k % 2 == 0 else C_OAK_SUN
            _add_beam(mb, p0, p2, 0.135, 0.042, 'timber', scol, 0.0)
        with xf(mb, T(0.0, 0.12, 0.0)):
            torus(mb, radius * 0.90, 0.026, 6, 3, 'iron', C_IRON_FORGED, False)
        with xf(mb, T(0.0, height * 0.44, 0.0)):
            torus(mb, radius * 1.03, 0.028, 6, 3, 'iron', C_IRON_RUST_HI, False)
        with xf(mb, T(0.0, height * 0.78, 0.0)):
            torus(mb, radius * 1.15, 0.024, 6, 3, 'rope', C_HEMP_HI, True)
        _add_beam(mb, (radius * 1.12, height * 0.78, -0.05),
                  (radius * 1.12 + 0.34, height * 0.90, -0.26), 0.052, 0.052, 'timber', C_OAK_DEEP, 0.0)


def _build_cresset_fire_brazier(mb, center):
    """Cooper's wrought-iron stave-bending cresset fire basket seated on a stone hearth slab,
    blazing with warm amber oak embers & curling flame tongues ('glass' ONLY — ZERO skull_glow!)."""
    cx, cy, cz = center
    with xf(mb, T(cx, cy, cz)):
        cyl(mb, 0.54, 0.00, 0.10, 6, 'limestone', C_COBBLE_DARK, False, 0.0, 0.50)
        cyl(mb, 0.40, 0.09, 0.13, 6, 'basalt', C_OBSIDIAN_DARK, False, 0.0)
        for k in range(4):
            ang = radians(k * 90.0 + 45.0)
            ca, sa = cos(ang), sin(ang)
            _add_beam(mb, (0.35 * ca, 0.09, 0.35 * sa), (0.24 * ca, 0.38, 0.24 * sa),
                      0.052, 0.052, 'iron', C_IRON_DARK, 0.0)
        for hy, hr, hcol in ((0.36, 0.25, C_IRON_DARK), (0.64, 0.33, C_IRON_FORGED), (0.90, 0.37, C_IRON_RUST_HI)):
            with xf(mb, T(0.0, hy, 0.0)):
                torus(mb, hr, 0.026, 6, 3, 'iron', hcol, False)
        for k in range(6):
            ang = radians(k * 60.0 + 15.0)
            ca, sa = cos(ang), sin(ang)
            _add_beam(mb, (0.24 * ca, 0.34, 0.24 * sa), (0.37 * ca, 0.94, 0.37 * sa),
                      0.036, 0.036, 'iron', C_IRON_FORGED if k % 2 == 0 else C_IRON_RUST_MID, 0.0)
        # Bold dark charred oak stave offcuts framing the glowing amber ember core!
        for lag in (18.0, 78.0, 142.0):
            with xf(mb, T(0.0, 0.56, 0.0) @ R('Y', lag) @ R('Z', 30.0) @ M_Y2X):
                cyl(mb, 0.048, -0.32, 0.32, 5, 'timber', C_OAK_CHAR, False, 0.0)
        # Compact high-contrast glowing ember mound + jagged warm amber flame tongues ('glass' ONLY!)
        lathe(mb, [(0.0, 0.38), (0.23, 0.44), (0.25, 0.62), (0.18, 0.76), (0.0, 0.82)],
              6, 'glass', C_FLAME_DEEP, False, False,
              lambda i, k: C_FLAME_CORE if i >= 3 else (C_FLAME_MID if i == 2 else C_MAGMA_CRIMSON))
        for fx, fz, fh, fr in ((0.0, 0.0, 0.44, 0.11), (-0.10, -0.08, 0.32, 0.075), (0.11, 0.07, 0.34, 0.08)):
            tube(mb, [(fx, 0.68, fz), (fx * 0.6 + 0.04, 0.68 + fh * 0.55, fz * 0.6),
                      (fx * 0.2 - 0.03, 0.68 + fh, fz * 0.2)],
                 [fr, fr * 0.50, 0.014], 4, 'glass', C_FLAME_MID, caps=(False, True), mode='flat',
                 scols=[C_MAGMA_CRIMSON, C_FLAME_DEEP, C_FLAME_CORE])


def gen_pirate_cooperage_barrel_workshop(outdir):
    """Bustling seaside harbour cooper's barrel-making workshop (~5.4 m W x 4.0 m D x 3.9 m H,
    -2.80 m deep cobble wharf skirt) w/ timber-framed shingled saltbox lean-to roof, oak stave-
    bending cresset fire brazier ('glass' warm amber embers — ZERO skull_glow!), raised in-progress
    stave barrel, stacked finished iron-hooped rum & powder casks, cooper's adze workbench &
    hanging iron barrel hoops, striped crimson-cream guild pennant (UV2), convex collider
    'col_cooperage_base', and warm brass lantern empty 'Lantern_Cooperage'."""
    clear_scene()
    mb = MB('pirate_cooperage_barrel_workshop', seed=2201)
    rng = random.Random(SEED + 2201)
    col_pts = []

    DECK_Y   = 0.44
    F_POST_Z = -0.84
    R_POST_Z =  1.22
    F_EAVE_Y =  2.72
    RIDGE_Z  = -0.34
    RIDGE_Y  =  3.16
    R_EAVE_Y =  2.16

    # 1. Deep Harbour Cobble-and-Sandstone Wharf Plinth Skirt plunging cleanly to y = -2.80 m (~5.4 m W x 4.0 m D)
    found_secs = [
        _rect_oct(0.0, -2.80, 0.0, 2.56, 1.88, 0.34),
        _rect_oct(0.0, -1.15, 0.0, 2.50, 1.82, 0.32),
        _rect_oct(0.0,  0.00, 0.0, 2.44, 1.76, 0.30),
        _rect_oct(0.0,  0.34, 0.0, 2.38, 1.70, 0.28),
    ]
    _loft_horizontal_masonry(
        mb, found_secs, 'limestone',
        [C_COBBLE_WET, C_COBBLE_DARK, C_COBBLE_MID, C_COBBLE_HI],
        rng, caps=(True, True), top_mat='temple_stone', top_col=C_SANDSTONE_MID,
    )

    for yc, hx, hz in ((-2.80, 2.56, 1.88), (0.0, 2.44, 1.76), (DECK_Y, 2.38, 1.70), (3.18, 2.22, 1.46)):
        col_pts.extend(_rect_oct(0.0, yc, 0.0, hx, hz, 0.28))

    # Planked Heavy Oak Workshop Floor Deck + Seaward Entrance Step & Corner Mooring Pilings
    cbox(mb, (0.0, 0.36, 0.0), (4.68, 0.12, 3.26), 'timber', C_OAK_DEEP, 0.0)
    for dpi in range(6):
        pz_d = -1.32 + dpi * (2.64 / 5.0)
        cbox(mb, (0.0, DECK_Y - 0.01, pz_d), (4.62, 0.055, 0.48), 'timber',
             C_CEDAR_WEATHER if dpi % 2 == 0 else C_OAK_SUN, 0.0)
    cbox(mb, (0.0, 0.18, -1.80), (1.88, 0.32, 0.34), 'temple_stone', C_SANDSTONE_MID, 0.0)

    for px_p in (-2.34, 2.34):
        for pz_p in (-1.60, 1.60):
            top_p = DECK_Y + (0.38 if pz_p < 0 else 0.32)
            with xf(mb, T(px_p, 0.0, pz_p)):
                cyl(mb, 0.128, -0.35, top_p, 6, 'timber', C_CEDAR_DARK, False, 0.0, 0.114)
                _open_band(mb, 0.142, top_p - 0.18, top_p - 0.08, 6, 'rope', C_HEMP_HI)

    # 2. Timber-Framed Saltbox Lean-To Workshop Shed w/ Stepped Shingled Roof Visible from BOTH Front & Rear!
    POST_XS = (-1.98, 0.00, 1.92)
    for idx_p, px in enumerate(POST_XS):
        if idx_p != 1:
            cbox(mb, (px, 0.5 * (DECK_Y + F_EAVE_Y), F_POST_Z), (0.20, F_EAVE_Y - DECK_Y, 0.20), 'timber', C_OAK_DEEP, 0.0)
            cbox(mb, (px, DECK_Y + 0.11, F_POST_Z), (0.27, 0.22, 0.27), 'iron', C_IRON_FORGED, 0.0)
            cbox(mb, (px, F_EAVE_Y - 0.14, F_POST_Z), (0.25, 0.11, 0.25), 'iron', C_IRON_FORGED, 0.0)
            in_sgn = 1.0 if px < 0 else -1.0
            _add_beam(mb, (px, F_EAVE_Y - 0.58, F_POST_Z), (px + in_sgn * 0.58, F_EAVE_Y - 0.04, F_POST_Z),
                      0.10, 0.11, 'timber', C_OAK_RICH, 0.0)
            _add_beam(mb, (px, F_EAVE_Y - 0.54, F_POST_Z), (px, F_EAVE_Y - 0.12, F_POST_Z + 0.54),
                      0.10, 0.10, 'timber', C_OAK_RICH, 0.0)
        cbox(mb, (px, 0.5 * (DECK_Y + R_EAVE_Y), R_POST_Z), (0.19, R_EAVE_Y - DECK_Y, 0.19), 'timber', C_OAK_DEEP, 0.0)
        cbox(mb, (px, DECK_Y + 0.10, R_POST_Z), (0.26, 0.20, 0.26), 'iron', C_IRON_FORGED, 0.0)

    # Front header, ridge-beam, rear wall-plate & 4 saltbox roof rafter trusses seated cleanly BELOW shingles!
    cbox(mb, (-0.03, F_EAVE_Y - 0.04, F_POST_Z), (4.42, 0.18, 0.18), 'timber', C_OAK_DEEP, 0.0)
    cbox(mb, (-0.03, RIDGE_Y  - 0.14, RIDGE_Z),  (4.46, 0.18, 0.16), 'timber', C_OAK_DEEP, 0.0)
    cbox(mb, (-0.03, R_EAVE_Y - 0.04, R_POST_Z), (4.40, 0.18, 0.18), 'timber', C_OAK_DEEP, 0.0)
    for rx in (-1.98, -0.68, 0.64, 1.92):
        _add_beam(mb, (rx, F_EAVE_Y - 0.04, F_POST_Z - 0.28), (rx, RIDGE_Y - 0.10, RIDGE_Z),
                  0.11, 0.12, 'timber', C_OAK_RICH, 0.0)
        _add_beam(mb, (rx, RIDGE_Y - 0.10, RIDGE_Z), (rx, R_EAVE_Y - 0.06, R_POST_Z + 0.24),
                  0.11, 0.12, 'timber', C_OAK_RICH, 0.0)

    # Rear Half-Timbered Plank Back Wall & Open Framed Viewport (rich Rear 3/4 craft!)
    for bi, by in enumerate((DECK_Y + 0.24, DECK_Y + 0.62, DECK_Y + 1.00, DECK_Y + 1.38)):
        cbox(mb, (-0.99, by, R_POST_Z), (1.88, 0.34, 0.09), 'timber',
             C_OAK_SUN if bi % 2 == 0 else C_CEDAR_WEATHER, 0.0)
    for bi, by in enumerate((DECK_Y + 0.24, DECK_Y + 0.62)):
        cbox(mb, (0.96, by, R_POST_Z), (1.82, 0.34, 0.09), 'timber',
             C_OAK_SUN if bi == 0 else C_OAK_RICH, 0.0)
    cbox(mb, (0.96, DECK_Y + 0.84, R_POST_Z), (1.86, 0.10, 0.18), 'timber', C_OAK_DEEP, 0.0)
    _add_beam(mb, (-1.90, DECK_Y + 0.10, R_POST_Z + 0.07), (-0.08, R_EAVE_Y - 0.14, R_POST_Z + 0.07),
              0.09, 0.06, 'timber', C_OAK_DEEP, 0.0)
    _add_beam(mb, (0.08, DECK_Y + 0.10, R_POST_Z + 0.07), (1.84, DECK_Y + 0.80, R_POST_Z + 0.07),
              0.09, 0.06, 'timber', C_OAK_DEEP, 0.0)
    cbox(mb, (-1.98, DECK_Y + 0.42, 0.20), (0.10, 0.78, 1.92), 'timber', C_OAK_RICH, 0.0)
    cbox(mb, (-1.98, DECK_Y + 0.84, 0.20), (0.18, 0.09, 2.02), 'timber', C_OAK_DEEP, 0.0)

    # Saltbox Shingled Lean-To Roof: Front Shingled Apron Slope (-Z) + Long Rear Shingled Slope (+Z)!
    # Both Hero Front 3/4 AND Rear 3/4 show unmistakable handcrafted stepped wooden shingles!
    shingle_cols = [C_SHINGLE_A, C_SHINGLE_B, C_OAK_RICH, C_SHINGLE_MOSS, C_CEDAR_DARK]
    def _build_shingle_slope(z0, y0, z1, y1, n_courses, n_tiles, seed_shift, patch_cells):
        dz = z1 - z0
        dy = y1 - y0
        p_deg = degrees(atan2(dy, dz))
        r_len = sqrt(dz * dz + dy * dy)
        cbox(mb, (-0.03, 0.5 * (y0 + y1) - 0.03, 0.5 * (z0 + z1)),
             (4.54, 0.06, r_len), 'timber', C_OAK_CHAR, 0.0, M=R('X', -p_deg))
        for ci in range(n_courses):
            t = (ci + 0.5) / float(n_courses)
            zc = z0 + dz * t
            yc = y0 + dy * t + 0.042
            cd = r_len / float(n_courses) + 0.07
            for ti in range(n_tiles):
                tw = 4.62 / float(n_tiles)
                tx = -2.34 + tw * (ti + 0.5)
                th = 0.056 + 0.016 * ((ci + ti) % 2)
                if (ci, ti) in patch_cells:
                    tmat, tcol = 'paint', C_CRIMSON_MID
                else:
                    tmat = 'timber'
                    tcol = jit(shingle_cols[(ci * 2 + ti + seed_shift) % len(shingle_cols)], rng, 0.06, 0.02)
                cbox(mb, (tx, yc + 0.010 * ((ci + ti) % 2), zc),
                     (tw - 0.02, th, cd), tmat, tcol, 0.0, M=R('X', -p_deg + (2.5 if dz > 0 else -2.5)))
        for sx_b in (-2.34, 2.28):
            cbox(mb, (sx_b, 0.5 * (y0 + y1) + 0.02, 0.5 * (z0 + z1)),
                 (0.11, 0.16, r_len + 0.08), 'timber', C_OAK_DEEP, 0.0, M=R('X', -p_deg))

    # Front visible shingled apron (ridge z=-0.34,y=3.20 down to front eave z=-1.26,y=2.66)
    _build_shingle_slope(RIDGE_Z, RIDGE_Y + 0.04, -1.26, 2.66, n_courses=2, n_tiles=4, seed_shift=0, patch_cells={(0, 2)})
    # Long rear shingled lean-to slope (ridge z=-0.34,y=3.20 down to rear eave z=+1.54,y=2.14)
    _build_shingle_slope(RIDGE_Z, RIDGE_Y + 0.04,  1.54, 2.14, n_courses=3, n_tiles=4, seed_shift=2, patch_cells={(1, 1), (2, 3)})
    # Bold ridge cap timber beam crowning the saltbox peak
    cbox(mb, (-0.03, RIDGE_Y + 0.10, RIDGE_Z), (4.72, 0.14, 0.16), 'timber', C_OAK_SUN, 0.0)

    # Forged-Iron Flue Smoke-Hood & Chimneystack rising cleanly above the Cresset Brazier!
    with xf(mb, T(-1.16, 2.94, -0.46)):
        cyl(mb, 0.30, -0.14, 0.10, 6, 'iron', C_IRON_DARK, False, 0.0, 0.15)
        cyl(mb, 0.145, 0.10, 0.72, 6, 'iron', C_IRON_FORGED, False, 0.0, 0.13)
        cyl(mb, 0.23,  0.76, 0.88, 6, 'iron', C_IRON_RUST_HI, False, 0.0, 0.06)
        for k in range(3):
            ang = radians(k * 120.0)
            _add_beam(mb, (0.12 * cos(ang), 0.68, 0.12 * sin(ang)),
                      (0.15 * cos(ang), 0.80, 0.15 * sin(ang)), 0.028, 0.028, 'iron', C_IRON_DARK, 0.0)

    # Hanging Painted Cooper's Guild Barrel-Signboard elevated cleanly off the Starboard Corner Eave (zero cask overlap!)
    _add_beam(mb, (1.92, 2.54, F_POST_Z), (2.48, 2.54, F_POST_Z - 0.16), 0.052, 0.052, 'iron', C_IRON_FORGED, 0.0)
    _add_beam(mb, (1.92, 2.24, F_POST_Z), (2.34, 2.54, F_POST_Z - 0.12), 0.038, 0.038, 'iron', C_IRON_DARK, 0.0)
    with xf(mb, T(2.38, 2.26, F_POST_Z - 0.14) @ R('Y', -14.0)):
        cbox(mb, (0.0, 0.0, 0.0), (0.56, 0.42, 0.060), 'paint', C_CRIMSON_HI, 0.0)
        cbox(mb, (0.0, 0.0, 0.0), (0.42, 0.28, 0.075), 'paint', C_CREAM_BRIGHT, 0.0)
        cbox(mb, (0.0, 0.0, 0.0), (0.22, 0.20, 0.090), 'timber', C_OAK_RICH, 0.0)
        cbox(mb, (0.0,  0.055, 0.0), (0.24, 0.028, 0.098), 'iron', C_IRON_FORGED, 0.0)
        cbox(mb, (0.0, -0.055, 0.0), (0.24, 0.028, 0.098), 'iron', C_IRON_FORGED, 0.0)

    # 3. Oak Stave-Bending Cresset Fire Brazier ('glass' warm amber embers!) + In-Progress Raised Barrel!
    _build_cresset_fire_brazier(mb, (-1.18, DECK_Y, -0.82))
    _build_inprogress_barrel_shell(mb, (-0.26, DECK_Y, -0.78), radius=0.29, height=0.72)

    # 4. Cooper's Adze Workbench w/ Fresh Oak Staves, Curved Adze, Mallet & Hanging Iron Barrel Hoops!
    WB_X, WB_Z = 0.62, 0.44
    WB_Y = DECK_Y + 0.80
    cbox(mb, (WB_X, WB_Y, WB_Z), (1.72, 0.10, 0.80), 'timber', C_OAK_SUN, 0.0)
    cbox(mb, (WB_X, DECK_Y + 0.24, WB_Z), (1.52, 0.065, 0.60), 'timber', C_OAK_DEEP, 0.0)
    for lx_w in (-0.72, 0.72):
        for lz_w in (-0.28, 0.28):
            cbox(mb, (WB_X + lx_w, 0.5 * (DECK_Y + WB_Y), WB_Z + lz_w),
                 (0.11, WB_Y - DECK_Y, 0.11), 'timber', C_OAK_DEEP, 0.0)
    cbox(mb, (WB_X - 0.16, WB_Y + 0.08, WB_Z - 0.14), (0.92, 0.055, 0.14), 'timber', C_STAVE_PALE, 0.0, M=R('Y', 5.0))
    for si in range(3):
        cbox(mb, (WB_X + 0.26, WB_Y + 0.075 + si * 0.045, WB_Z + 0.16 - si * 0.02),
             (0.82, 0.040, 0.12), 'timber', C_STAVE_PALE if si % 2 == 0 else C_OAK_SUN, 0.0, M=R('Y', -6.0 + si * 3.0))
    for si in range(3):
        cbox(mb, (WB_X - 0.10, DECK_Y + 0.30 + (si // 2) * 0.055, WB_Z - 0.10 + (si % 2) * 0.18),
             (1.08, 0.048, 0.13), 'timber', C_STAVE_PALE if si % 2 == 0 else C_OAK_SUN, 0.0)
    # Cooper's Curved Adze + Wooden Bung Mallet
    _add_beam(mb, (WB_X - 0.54, WB_Y + 0.08, WB_Z + 0.18), (WB_X - 0.18, WB_Y + 0.11, WB_Z - 0.02),
              0.040, 0.040, 'timber', C_OAK_RICH, 0.0)
    cbox(mb, (WB_X - 0.56, WB_Y + 0.11, WB_Z + 0.18), (0.09, 0.16, 0.12), 'iron', C_IRON_BRIGHT, 0.0, M=R('Z', 24.0))
    with xf(mb, T(WB_X - 0.60, WB_Y + 0.12, WB_Z - 0.20) @ R('Y', 32.0)):
        cbox(mb, (0.0, 0.0, 0.0), (0.14, 0.11, 0.22), 'timber', C_OAK_DEEP, 0.0)
        _add_beam(mb, (0.0, 0.0, 0.0), (0.28, -0.02, 0.06), 0.036, 0.036, 'timber', C_STAVE_PALE, 0.0)

    # Hanging Forged-Iron Barrel Hoops on Wall Pegs (visible from BOTH Front & Rear 3/4!)
    cbox(mb, (-1.00, DECK_Y + 1.48, R_POST_Z - 0.10), (1.66, 0.10, 0.08), 'timber', C_OAK_DEEP, 0.0)
    for h_i, (hx_h, hr_h, hcol_h) in enumerate((
        (-1.54, 0.26, C_IRON_BRIGHT),
        (-1.08, 0.30, C_IRON_FORGED),
        (-0.62, 0.25, C_IRON_RUST_HI),
    )):
        cbox(mb, (hx_h, DECK_Y + 1.48, R_POST_Z - 0.20), (0.06, 0.06, 0.20), 'timber', C_OAK_SUN, 0.0)
        with xf(mb, T(hx_h, DECK_Y + 1.48 - hr_h, R_POST_Z - 0.22) @ R('Y', 12.0 * (h_i - 1)) @ M_Y2Z):
            torus(mb, hr_h, 0.028, 6, 3, 'iron', hcol_h, False)
    for hx_r, hr_r, hcol_r in ((-1.28, 0.28, C_IRON_BRIGHT), (-0.70, 0.26, C_IRON_RUST_HI)):
        cbox(mb, (hx_r, DECK_Y + 1.42, R_POST_Z + 0.14), (0.06, 0.06, 0.18), 'timber', C_OAK_SUN, 0.0)
        with xf(mb, T(hx_r, DECK_Y + 1.42 - hr_r, R_POST_Z + 0.18) @ M_Y2Z):
            torus(mb, hr_r, 0.028, 6, 3, 'iron', hcol_r, False)
    with xf(mb, T(1.70, DECK_Y + 0.28, F_POST_Z + 0.14) @ R('Y', 68.0) @ R('X', 14.0) @ M_Y2Z):
        torus(mb, 0.28, 0.026, 6, 3, 'iron', C_IRON_BRIGHT, False)

    # 5. Stacked Finished Iron-Hooped Rum & Crimson-Branded Powder Casks!
    for sx_s in (1.22, 1.82):
        cbox(mb, (sx_s, DECK_Y + 0.05, -0.34), (0.12, 0.08, 1.16), 'timber', C_OAK_DEEP, 0.0)
    _build_coopered_cask(mb, T(1.52, DECK_Y + 0.34, -0.62) @ R('Y', 6.0) @ M_Y2X,
                         radius=0.27, height=0.68, rng=rng, segs=6, powder_band=False)
    _build_coopered_cask(mb, T(1.52, DECK_Y + 0.34, -0.02) @ R('Y', -4.0) @ M_Y2X,
                         radius=0.27, height=0.68, rng=rng, col_a=C_OAK_SUN, col_b=C_OAK_RICH, segs=6, powder_band=False)
    _build_coopered_cask(mb, T(1.52, DECK_Y + 0.80, -0.32) @ R('Y', 3.0) @ M_Y2X,
                         radius=0.25, height=0.64, rng=rng, segs=6, powder_band=True)

    _build_coopered_cask(mb, T(-1.58, DECK_Y + 0.38, 0.42) @ R('Y', 24.0),
                         radius=0.30, height=0.76, rng=rng, segs=6, powder_band=False, spigot=True)
    _build_coopered_cask(mb, T(-0.92, DECK_Y + 0.34, 0.64) @ R('Y', -14.0),
                         radius=0.26, height=0.68, rng=rng, segs=6, powder_band=True)

    # Rear (+Z) Wharf Apron Craft: Finished Rum Cask, Leaning Raw Oak Stave Bundle & Coiled Hemp Rope!
    _build_coopered_cask(mb, T(1.32, DECK_Y + 0.35, 1.44) @ R('Y', -18.0),
                         radius=0.26, height=0.68, rng=rng, segs=6, powder_band=False)
    for si in range(4):
        _add_beam(mb, (0.34 + si * 0.14, DECK_Y + 0.02, 1.56),
                  (0.32 + si * 0.14, DECK_Y + 0.94, 1.28),
                  0.095, 0.036, 'timber', C_STAVE_PALE if si % 2 == 0 else C_OAK_SUN, 0.0)
    _build_rope_coil(mb, (-1.80, DECK_Y + 0.01, -1.24), radius=0.26, turns=2, r=0.042, segs=6, psegs=4,
                     col_a=C_HEMP_HI, col_b=C_HEMP_MID)

    # 6. Striped Crimson-Cream Cooper's Guild Pennant Mast ('paint' + UV2!)
    MAST_X, MAST_Z = -1.98, R_POST_Z
    with xf(mb, T(MAST_X, 0.0, MAST_Z)):
        cyl(mb, 0.072, R_EAVE_Y - 0.10, 3.84, 6, 'timber', C_OAK_DEEP, False, 0.0, 0.044)
        lathe(mb, [(0.0, 3.82), (0.080, 3.88), (0.0, 3.96)], 6, 'brass', C_GOLD_BRIGHT, False)
    _build_wind_banner(
        mb, root_pos=(MAST_X + 0.05, 3.62, MAST_Z), length=1.38, h0=0.42,
        out_dir=(0.90, -0.02, -0.44),
        col_main=C_CRIMSON_HI, col_alt=C_CREAM_BRIGHT, col_trim=C_GOLD_BRIGHT,
        phase=0.27, swallowtail=True,
    )

    # 7. Warm Brass Cooperage Lantern ('Lantern_Cooperage') cantilevered over the Front-Port Apron!
    LANTERN_POS = Vector((-1.50, 2.26, -1.32))
    _add_beam(mb, (-1.98, 2.66, F_POST_Z), (-1.46, 2.66, -1.36), 0.074, 0.078, 'timber', C_OAK_RICH, 0.0)
    _add_beam(mb, (-1.98, 2.22, F_POST_Z), (-1.68, 2.64, -1.16), 0.048, 0.052, 'iron', C_IRON_FORGED, 0.0)
    _add_beam(mb, (-1.50, 2.66, -1.32), LANTERN_POS + Vector((0.0, 0.28, 0.0)), 0.024, 0.024, 'iron', C_IRON_FORGED, 0.0)
    _build_storm_lantern(mb, LANTERN_POS, scale=0.86, brass_cage=True, hanging=True)

    # 8. Coastal Harbour Ferns ('foliage' + UV2) tucked neatly beside the stone apron step & wharf flanks
    for fpos, fsc, flean, fph in (
        ((-1.28, 0.26, -1.72), 0.48, (-0.5, 0.0, -0.85), 0.16),
        (( 1.28, 0.26, -1.72), 0.48, ( 0.5, 0.0, -0.85), 0.44),
        ((-2.28, 0.30,  0.26), 0.44, (-1.0, 0.0,  0.00), 0.71),
        (( 2.28, 0.30,  0.14), 0.44, ( 1.0, 0.0,  0.00), 0.93),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=3, rng=rng, phase=fph, lean_dir=flean, segs=2)

    build(mb)

    add_empty('Lantern_Cooperage', LANTERN_POS)
    col_piece('col_cooperage_base', col_pts)
    export_landmark_glb(outdir, 'pirate_cooperage_barrel_workshop.glb')


# ==============================================================================
# 2. ANCIENT ASTRAL TIDE OBELISK (ancient_astral_tide_obelisk.glb)
# ==============================================================================

def _build_split_obelisk_spire(mb, side_sgn, base_y, top_y, rng):
    """One half of the monumental tapered split-stone astral tide obelisk rising cleanly from the
    pedestal shoulders (y=1.94 m) around a bold central aperture to a razor split-pyramidion peak
    at y=5.78 m, banded with bronze-framed luminous turquoise carved glyph channels ('skull_glow' ONLY!)."""
    stations = [
        (base_y,       0.14, 0.62, 0.52, C_ASTRAL_DARK),
        (base_y + 0.48, 0.54, 0.96, 0.48, C_ASTRAL_MID),
        (base_y + 1.38, 0.66, 1.04, 0.44, C_ASTRAL_MID),
        (base_y + 2.26, 0.54, 0.88, 0.38, C_ASTRAL_HI),
        (base_y + 3.04, 0.16, 0.54, 0.28, C_ASTRAL_HI),
        (top_y - 0.30,  0.10, 0.34, 0.18, C_ASTRAL_HI),
        (top_y,         0.08, 0.14, 0.06, C_ASTRAL_HI),
    ]
    secs = []
    scols = []
    for y, xi, xo, zh, col_s in stations:
        ch = min(0.08, (xo - xi) * 0.24, zh * 0.28)
        cx = side_sgn * 0.5 * (xi + xo)
        hx = 0.5 * (xo - xi)
        secs.append(_rect_oct(cx, y, 0.0, hx, zh, ch))
        scols.append(col_s)
    _loft_horizontal_masonry(
        mb, secs, 'temple_stone', scols, rng, caps=(True, True),
        top_mat='limestone_moss', top_col=C_ASTRAL_HI,
    )

    # Bronze-Framed Luminous Turquoise Carved Glyph Bands & Binding Collars hugging the Split Monolith!
    band_specs = [
        (base_y + 0.52, 0.54, 0.96, 0.48, False),
        (base_y + 1.04, 0.62, 1.01, 0.46, True),
        (base_y + 1.68, 0.64, 1.01, 0.42, True),
        (base_y + 2.30, 0.52, 0.86, 0.37, False),
        (base_y + 2.84, 0.28, 0.64, 0.31, True),
    ]
    for by, bxi, bxo, bzh, is_glow in band_specs:
        bcx = side_sgn * 0.5 * (bxi + bxo)
        bw = (bxo - bxi) + 0.052
        bd = bzh * 2.0 + 0.052
        if is_glow:
            cbox(mb, (bcx, by, 0.0), (bw, 0.085, bd), 'skull_glow', C_AQUA_MID, 0.0)
            # Crisp flanking bronze fillet rails framing each carved glowing glyph band!
            for dy_f in (-0.065, 0.065):
                cbox(mb, (bcx, by + dy_f, 0.0), (bw + 0.02, 0.036, bd + 0.02), 'brass', C_VERDIGRIS_HI, 0.0)
            for zf in (-1.0, 1.0):
                cbox(mb, (bcx, by, zf * (bzh + 0.04)), (0.16, 0.16, 0.05), 'skull_glow', C_AQUA_CORE, 0.0, M=R('Z', 45.0))
        else:
            cbox(mb, (bcx, by, 0.0), (bw + 0.04, 0.11, bd + 0.04), 'brass', C_VERDIGRIS_HI, 0.0)
            cbox(mb, (bcx, by, 0.0), (bw + 0.06, 0.045, bd + 0.06), 'brass', C_GOLD_BRIGHT, 0.0)

    # Vertical glowing tide-rune inlay strips along the inner aperture walls facing the hovering crystal!
    in_pts = [
        Vector((side_sgn * 0.54, base_y + 0.54, 0.0)),
        Vector((side_sgn * 0.65, base_y + 1.38, 0.0)),
        Vector((side_sgn * 0.53, base_y + 2.26, 0.0)),
    ]
    _sculpt_glow_ribbon(
        mb, in_pts, [0.068, 0.088, 0.068], (-side_sgn, 0.0, 0.0),
        hot_core=True, ridge_h=0.032, mat='skull_glow',
        c_core=C_AQUA_CORE, c_mid_col=C_AQUA_MID, c_edge_col=C_AQUA_DEEP, c_tip_col=C_AQUA_DEEP,
    )
    # Sculpted Stepped Outer Temple-Stone Buttress Fin + Bronze Astrolabe Anchor Bracket!
    _add_beam(mb, (side_sgn * 1.07, base_y + 0.54, 0.0), (side_sgn * 0.96, base_y + 2.28, 0.0),
              0.15, 0.24, 'temple_stone', C_ASTRAL_MID, 0.0)
    cbox(mb, (side_sgn * 1.08, base_y + 1.40, 0.0), (0.12, 0.28, 0.28), 'brass', C_GOLD_BRIGHT, 0.0, M=R('X', 45.0))
    # Inner bronze mounting bracket prongs bridging cleanly toward the outer astrolabe ring!
    _add_beam(mb, (side_sgn * 0.68, 3.42, 0.0), (side_sgn * 0.92, 3.42, 0.0), 0.065, 0.065, 'brass', C_GOLD_BRIGHT, 0.0)


def gen_ancient_astral_tide_obelisk(outdir):
    """Monumental stepped mossy temple-stone celestial tide obelisk & ring altar (~4.6 m W x 4.6 m D
    x 5.8 m H, -3.20 m deep mossy temple-stone skirt) crowned by a tapered split-stone monolith
    cradling a hovering luminous turquoise-cyan astrolabe tide crystal & glowing carved glyph bands
    ('skull_glow' ONLY!), inlaid bronze compass terrace steps, cascading jungle vines & ferns (UV2),
    convex collider 'col_astralobelisk_base', and empty 'Lantern_AstralObelisk'."""
    clear_scene()
    mb = MB('ancient_astral_tide_obelisk', seed=2202)
    rng = random.Random(SEED + 2202)
    col_pts = []

    STEP1_Y = 0.36
    STEP2_Y = 0.68
    DAIS_Y  = 0.98
    PED_Y   = 1.94
    CORE_Y  = 3.42

    # 1. Deep Stepped Mossy Temple-Stone Foundation Skirt plunging cleanly to y = -3.20 m (~4.6 m W x 4.6 m D)
    plinth_secs = [
        _reg_poly(0.0, -3.20, 0.0, 2.30, sides=8, rot_deg=22.5),
        _reg_poly(0.0, -1.35, 0.0, 2.24, sides=8, rot_deg=22.5),
        _reg_poly(0.0,  0.00, 0.0, 2.18, sides=8, rot_deg=22.5),
        _reg_poly(0.0, STEP1_Y, 0.0, 2.12, sides=8, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, plinth_secs, 'limestone_moss',
        [C_ASTRAL_DEEP, C_ASTRAL_DARK, C_ASTRAL_MID, C_ASTRAL_HI],
        rng, caps=(True, True), top_mat='limestone_moss', top_col=C_ASTRAL_MID,
    )

    tier2_secs = [
        _reg_poly(0.0, STEP1_Y - 0.02, 0.0, 1.84, sides=8, rot_deg=22.5),
        _reg_poly(0.0, STEP2_Y,        0.0, 1.76, sides=8, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, tier2_secs, 'temple_stone',
        [C_ASTRAL_DARK, C_ASTRAL_HI], rng, caps=(False, True),
        top_mat='temple_stone', top_col=C_ASTRAL_MID,
    )

    dais_secs = [
        _reg_poly(0.0, STEP2_Y - 0.02, 0.0, 1.38, sides=8, rot_deg=22.5),
        _reg_poly(0.0, DAIS_Y,         0.0, 1.30, sides=8, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, dais_secs, 'temple_stone',
        [C_ASTRAL_DARK, C_ASTRAL_HI], rng, caps=(False, True),
        top_mat='temple_stone', top_col=C_ASTRAL_HI,
    )

    for yc, rc in ((-3.20, 2.30), (0.0, 2.18), (DAIS_Y, 1.96), (4.60, 1.18), (5.78, 0.42)):
        col_pts.extend(_reg_poly(0.0, yc, 0.0, rc, sides=8, rot_deg=22.5))

    # 2. Inlaid Bronze Compass Terrace Steps on all 4 Cardinal Approaches + Carved Stone Stair Balustrades!
    for k in range(4):
        ang_deg = k * 90.0
        with xf(mb, R('Y', ang_deg)):
            cbox(mb, (0.0, 0.18, -2.08), (1.04, 0.34, 0.36), 'temple_stone', C_ASTRAL_MID, 0.0)
            cbox(mb, (0.0, 0.50, -1.78), (0.94, 0.32, 0.34), 'temple_stone', C_ASTRAL_HI, 0.0)
            cbox(mb, (0.0, 0.80, -1.42), (0.86, 0.30, 0.34), 'temple_stone', C_ASTRAL_HI, 0.0)
            # Flanking carved stone stair-curb balustrades with gilded bronze cap studs!
            for sx in (-1.0, 1.0):
                cbox(mb, (sx * 0.58, 0.50, -1.76), (0.18, 0.56, 0.82), 'temple_stone', C_ASTRAL_DARK, 0.0)
                cbox(mb, (sx * 0.58, 0.80, -1.46), (0.20, 0.07, 0.22), 'brass', C_GOLD_BRIGHT, 0.0)
            # Inlaid burnished bronze compass riser trim & luminous cyan cardinal pointer chevron!
            cbox(mb, (0.0, 0.355, -1.98), (0.78, 0.03, 0.09), 'brass', C_GOLD_BRIGHT, 0.0)
            cbox(mb, (0.0, 0.675, -1.68), (0.70, 0.03, 0.09), 'brass', C_VERDIGRIS_HI, 0.0)
            cbox(mb, (0.0, 0.985, -1.10), (0.14, 0.035, 0.48), 'brass', C_GOLD_BRIGHT, 0.0)
            cbox(mb, (0.0, 1.00,  -1.12), (0.13, 0.045, 0.13), 'skull_glow', C_AQUA_MID, 0.0, M=R('Y', 45.0))

    # Concentric Bronze Compass & Tidal Azimuth Rings inlaid cleanly around the Stepped Altar Terrace!
    with xf(mb, T(0.0, STEP2_Y + 0.02, 0.0)):
        torus(mb, 1.56, 0.038, 12, 4, 'brass', C_VERDIGRIS_HI, False)
    with xf(mb, T(0.0, DAIS_Y + 0.02, 0.0)):
        torus(mb, 1.18, 0.042, 12, 4, 'brass', C_GOLD_BRIGHT, False)
        torus(mb, 0.96, 0.028, 12, 4, 'skull_glow', C_AQUA_MID, False)

    # 4 Diagonal Ring-Altar Standing Pylon Stones framing the Celestial Ring Altar (lightened carved temple masonry!)
    for k in range(4):
        ang = radians(k * 90.0 + 45.0)
        ca, sa = cos(ang), sin(ang)
        px, pz = 1.66 * ca, 1.66 * sa
        p_secs = [
            _reg_poly(px, STEP1_Y - 0.02, pz, 0.30, sides=6, rot_deg=k * 90.0 + 45.0),
            _reg_poly(px * 0.94, 1.38,    pz * 0.94, 0.24, sides=6, rot_deg=k * 90.0 + 45.0),
            _reg_poly(px * 0.89, 1.98,    pz * 0.89, 0.16, sides=6, rot_deg=k * 90.0 + 45.0),
        ]
        _loft_horizontal_masonry(
            mb, p_secs, 'temple_stone',
            [C_ASTRAL_DARK, C_ASTRAL_MID, C_ASTRAL_HI], rng, caps=(False, True),
            top_mat='limestone_moss', top_col=C_ASTRAL_HI,
        )
        # Sculpted bronze crescent-ring collar, vertical glowing glyph vein & hovering aqua beacon diamond!
        with xf(mb, T(px * 0.91, 1.66, pz * 0.91)):
            cyl(mb, 0.25, -0.050, 0.050, 6, 'brass', C_VERDIGRIS_HI, False, 0.0)
            torus(mb, 0.24, 0.024, 8, 4, 'brass', C_GOLD_BRIGHT, False)
        with xf(mb, T(px * 0.89, 2.04, pz * 0.89)):
            cyl(mb, 0.19, -0.04, 0.04, 6, 'brass', C_GOLD_BRIGHT, False, 0.0)
        with xf(mb, T(px * 0.89, 2.24, pz * 0.89)):
            lathe(mb, [(0.0, -0.14), (0.095, 0.0), (0.0, 0.16)], 4, 'skull_glow', C_AQUA_CORE, False)
        # Vertical glowing rune seam on outer pylon face
        _sculpt_glow_ribbon(
            mb, [Vector((px * 1.07, 0.72, pz * 1.07)), Vector((px * 1.01, 1.54, pz * 1.01))],
            [0.044, 0.036], (ca, 0.0, sa), hot_core=True, ridge_h=0.022, mat='skull_glow',
            c_core=C_AQUA_CORE, c_mid_col=C_AQUA_MID, c_edge_col=C_AQUA_DEEP, c_tip_col=C_AQUA_DEEP,
        )

    # 3. Carved Temple-Stone Obelisk Base Pedestal w/ Glowing Carved Glyph Bands & Bronze Compass Plaques!
    ped_secs = [
        _rect_oct(0.0, DAIS_Y - 0.02, 0.0, 0.80, 0.72, 0.18),
        _rect_oct(0.0, 1.46,          0.0, 0.72, 0.64, 0.16),
        _rect_oct(0.0, PED_Y,         0.0, 0.76, 0.66, 0.16),
    ]
    _loft_horizontal_masonry(
        mb, ped_secs, 'temple_stone',
        [C_ASTRAL_DARK, C_ASTRAL_MID, C_ASTRAL_HI], rng, caps=(False, True),
        top_mat='temple_stone', top_col=C_ASTRAL_HI,
    )
    cbox(mb, (0.0, DAIS_Y + 0.12, 0.0), (1.64, 0.11, 1.48), 'brass', C_VERDIGRIS_HI, 0.0)
    cbox(mb, (0.0, PED_Y - 0.08,  0.0), (1.58, 0.12, 1.38), 'brass', C_GOLD_BRIGHT, 0.0)
    cbox(mb, (0.0, 1.46, 0.0), (1.48, 0.10, 1.32), 'skull_glow', C_AQUA_DEEP, 0.0)
    for zf in (-1.0, 1.0):
        cbox(mb, (0.0, 1.46, zf * 0.68), (0.28, 0.28, 0.06), 'skull_glow', C_AQUA_CORE, 0.0, M=R('Z', 45.0))
        cbox(mb, (0.0, 1.46, zf * 0.64), (0.46, 0.46, 0.05), 'brass', C_GOLD_BRIGHT, 0.0, M=R('Z', 45.0))
        with xf(mb, T(0.0, 1.46, zf * 0.69) @ M_Y2Z):
            torus(mb, 0.28, 0.026, 8, 4, 'brass', C_VERDIGRIS_HI, False)
    for xf_s in (-1.0, 1.0):
        cbox(mb, (xf_s * 0.75, 1.46, 0.0), (0.06, 0.24, 0.24), 'skull_glow', C_AQUA_MID, 0.0, M=R('X', 45.0))
        cbox(mb, (xf_s * 0.72, 1.46, 0.0), (0.05, 0.38, 0.38), 'brass', C_GOLD_BRIGHT, 0.0, M=R('X', 45.0))

    # 4. Monumental Tapered Split-Stone Obelisk Monolith rising to y = 5.78 m!
    _build_split_obelisk_spire(mb, -1.0, PED_Y - 0.02, 5.78, rng)
    _build_split_obelisk_spire(mb,  1.0, PED_Y - 0.02, 5.78, rng)

    # Carved Bronze & Stone Arch Tie-Crown + Celestial Crescent Finial bridging the upper cleft!
    cbox(mb, (0.0, 4.92, 0.0), (0.68, 0.14, 0.46), 'brass', C_GOLD_BRIGHT, 0.0)
    cbox(mb, (0.0, 4.80, 0.0), (0.76, 0.07, 0.52), 'brass', C_VERDIGRIS_HI, 0.0)
    with xf(mb, T(0.0, 5.34, 0.0)):
        lathe(mb, [(0.0, -0.26), (0.115, 0.0), (0.0, 0.34)], 4, 'skull_glow', C_AQUA_CORE, False)

    # 5. Hovering Luminous Turquoise-Cyan Astrolabe Tide Crystal & Intricate Bronze Armillary Sphere!
    with xf(mb, T(0.0, CORE_Y, 0.0)):
        # Outer vertical gilded bronze meridian astrolabe ring + 8 degree-lug sighting pointers!
        with xf(mb, M_Y2Z):
            torus(mb, 0.90, 0.048, 12, 4, 'brass', C_GOLD_BRIGHT, False)
            torus(mb, 0.81, 0.026, 12, 3, 'brass', C_VERDIGRIS_HI, False)
        # Tilted verdigris-bronze ecliptic tide ring
        with xf(mb, R('Z', 34.0) @ R('X', 28.0) @ M_Y2Z):
            torus(mb, 0.72, 0.038, 12, 3, 'brass', C_VERDIGRIS_HI, False)
        # Counter-tilted golden lunar horizon ring
        with xf(mb, R('Z', -42.0) @ R('Y', 56.0)):
            torus(mb, 0.56, 0.032, 10, 3, 'brass', C_GOLD_BRIGHT, False)
        # Equatorial bronze sight-bar axis & 8 radial compass degree ticks on the outer meridian ring
        for k in range(8):
            ang = radians(k * 45.0)
            is_card = (k % 2 == 0)
            r_in = 0.86 if is_card else 0.88
            r_out = 1.08 if is_card else 0.99
            tube(mb, [Vector((r_in * cos(ang), r_in * sin(ang), 0.0)),
                      Vector((r_out * cos(ang), r_out * sin(ang), 0.0))],
                 [0.056 if is_card else 0.038, 0.014], 4, 'brass',
                 C_GOLD_BRIGHT if is_card else C_VERDIGRIS_HI, caps=(False, True), mode='flat')
        # Luminous Faceted Turquoise-Cyan Astrolabe Tide Crystal Core ('skull_glow' ONLY!)
        lathe(mb, [(0.0, -0.52), (0.28, -0.10), (0.32, 0.04), (0.24, 0.22), (0.0, 0.56)],
              6, 'skull_glow', C_AQUA_CORE, False, False,
              lambda i, k: C_AQUA_CORE if i in (1, 2) else C_AQUA_MID)
        # Delicate gilded bronze equatorial collar-band hovering around the waist of the crystal
        with xf(mb, R('Z', 14.0) @ R('X', -12.0)):
            torus(mb, 0.40, 0.022, 10, 3, 'brass', C_GOLD_BRIGHT, False)
        # 4 Hovering Orbiting Turquoise Crystal Tide Shards circling the central crystal!
        for k in range(4):
            ang = radians(k * 90.0 + 45.0)
            sy_off = 0.16 * (1.0 if k % 2 == 0 else -1.0)
            with xf(mb, T(0.49 * cos(ang), sy_off, 0.49 * sin(ang)) @ R('Z', 16.0 * cos(ang))):
                lathe(mb, [(0.0, -0.14), (0.072, 0.0), (0.0, 0.16)], 4, 'skull_glow', C_AQUA_MID, False)

    # 6. Cascading Jungle Vines (100% anchored directly onto stone shoulders & pylons — ZERO floating!),
    #    Mossy Cushions & Lush Intercardinal Tropical Ferns ('foliage' + UV2!)
    # Diagonal pylons sit at radius 1.66 * 0.91 * cos(45 deg) = 1.07 m -> outer surface at ~1.22 m!
    vine_specs = [
        ((-0.94, 3.88, -0.34), 1.96, 0.15, (-0.55, 0.0, -0.84), 0.12),
        (( 0.94, 3.88, -0.34), 1.90, 0.15, ( 0.55, 0.0, -0.84), 0.36),
        ((-0.94, 3.84,  0.34), 2.02, 0.15, (-0.55, 0.0,  0.84), 0.61),
        (( 0.94, 3.84,  0.34), 1.88, 0.15, ( 0.55, 0.0,  0.84), 0.85),
        # Anchored tightly onto the 4 diagonal ring-altar pylons (r = 1.22 -> x=±1.14, z=±1.14)!
        ((-1.16, 1.66, -1.16), 1.18, 0.14, (-0.71, 0.0, -0.71), 0.22),
        (( 1.16, 1.66, -1.16), 1.14, 0.14, ( 0.71, 0.0, -0.71), 0.48),
        ((-1.16, 1.66,  1.16), 1.16, 0.14, (-0.71, 0.0,  0.71), 0.72),
        (( 1.16, 1.66,  1.16), 1.12, 0.14, ( 0.71, 0.0,  0.71), 0.94),
    ]
    for v_pos, v_len, v_wid, v_dir, v_ph in vine_specs:
        _add_leafy_vine_drape(mb, v_pos, v_len, v_wid, v_dir, rng, phase=v_ph)

    for mpos, mrad in (
        ((-0.72, PED_Y + 0.04, -0.46), (0.30, 0.12, 0.24)),
        (( 0.72, PED_Y + 0.04,  0.46), (0.30, 0.12, 0.24)),
        ((-0.72, PED_Y + 0.04,  0.46), (0.26, 0.11, 0.22)),
        (( 0.72, PED_Y + 0.04, -0.46), (0.26, 0.11, 0.22)),
        ((-1.56, STEP1_Y + 0.05,  0.90), (0.34, 0.14, 0.30)),
        (( 1.56, STEP1_Y + 0.05, -0.90), (0.34, 0.14, 0.30)),
    ):
        _build_mossy_tuft(mb, mpos, mrad, rng)

    for k in range(4):
        ang = radians(k * 90.0 + 45.0)
        ca, sa = cos(ang), sin(ang)
        _add_coastal_fern_cluster(
            mb, (1.84 * ca, STEP1_Y + 0.02, 1.84 * sa),
            scale=0.64, n_fronds=5, rng=rng, phase=(0.14 + k * 0.23) % 1.0,
            lean_dir=(ca, 0.0, sa), segs=2,
        )

    LANTERN_POS = Vector((0.0, CORE_Y, 0.0))

    build(mb)

    add_empty('Lantern_AstralObelisk', LANTERN_POS)
    col_piece('col_astralobelisk_base', col_pts)
    export_landmark_glb(outdir, 'ancient_astral_tide_obelisk.glb')


# ==============================================================================
# 3. COASTAL BUCCANEER NET MENDING PIER (coastal_buccaneer_net_mending_pier.glb)
# ==============================================================================

def _build_lobster_pot(mb, M_pot, length=0.66, width=0.44, height=0.34):
    """Woven slatted coastal wooden lobster/crab creel trap with arched cedar lath hoops,
    hemp funnel netting entry & hauling rope bridle."""
    hl = length * 0.5
    hw = width * 0.5
    with xf(mb, M_pot):
        cbox(mb, (0.0, 0.03, 0.0), (length, 0.055, width), 'timber', C_CEDAR_DARK, 0.0)
        for xi in (-hl + 0.05, 0.0, hl - 0.05):
            rib_pts = []
            for k in range(5):
                ang = pi * k / 4.0
                rib_pts.append(Vector((xi, 0.05 + height * sin(ang), -hw * cos(ang))))
            tube(mb, rib_pts, 0.024, 3, 'timber', C_CEDAR_SUN if xi == 0.0 else C_OAK_RICH,
                 caps=(False, False), mode='flat')
        for s_ang in (32.0, 72.0, 108.0, 148.0):
            ar = radians(s_ang)
            ly = 0.05 + (height + 0.016) * sin(ar)
            lz = -(hw + 0.014) * cos(ar)
            cbox(mb, (0.0, ly, lz), (length + 0.02, 0.026, 0.048), 'timber',
                 C_CEDAR_WEATHER if int(s_ang) % 4 == 0 else C_OAK_SUN, 0.0, M=R('X', 90.0 - s_ang))
        for sx in (-1.0, 1.0):
            with xf(mb, T(sx * (hl - 0.04), height * 0.50, 0.0) @ M_Y2X):
                _open_band(mb, height * 0.36, -0.025, 0.025, 5, 'rope', C_NET_TAR_HI)
        with xf(mb, T(0.0, height + 0.08, 0.0) @ M_Y2Z):
            torus(mb, 0.068, 0.018, 5, 3, 'rope', C_HEMP_HI, True)


def _build_sea_glass_buoy(mb, center, radius=0.165, is_glass_sphere=True, col_body=C_SEA_GLASS):
    """Chunky coastal fisherman's sea-green glass buoy float wrapped in braided hemp net-bands
    (non-emissive 'brass' tinted sea-green for glossy sheen — ZERO glow!) or striped wood buoy."""
    cx, cy, cz = center
    with xf(mb, T(cx, cy, cz)):
        if is_glass_sphere:
            prof = [
                (0.0, -radius),
                (radius * 0.72, -radius * 0.68),
                (radius, 0.0),
                (radius * 0.72,  radius * 0.68),
                (0.0,  radius),
            ]
            lathe(mb, prof, 6, 'brass', col_body, False, False,
                  lambda i, k: C_SEA_GLASS if i in (1, 2) else C_SEA_GLASS_DARK)
            torus(mb, radius * 1.03, 0.022, 6, 3, 'rope', C_HEMP_HI, True)
            with xf(mb, M_Y2Z):
                torus(mb, radius * 1.03, 0.020, 6, 3, 'rope', C_HEMP_MID, True)
        else:
            cyl(mb, radius * 0.85, -radius * 1.15, radius * 1.15, 6, 'paint', col_body, False, 0.0, radius * 0.72)
            _open_band(mb, radius * 0.88, -radius * 0.28, radius * 0.28, 6, 'paint', C_CREAM_BRIGHT)
            with xf(mb, T(0.0, radius * 1.24, 0.0) @ M_Y2Z):
                torus(mb, 0.045, 0.015, 5, 3, 'rope', C_HEMP_HI, True)


def _build_open_lattice_fishing_net(mb, p_top_l, p_top_r, drop_h, sag_mid, belly_dir,
                                    phase=0.2, n_diag=6, n_corks=5, tail_pull=None, double_swag=True):
    """Authentic 3D open-mesh crisscrossed diamond-lattice tarred fishing net ('rope' + UV2 gentle
    wind ripple!) allowing sunlight to stream cleanly THROUGH the woven diamond holes! Features
    scalloped headrope, chunky cork & crimson wooden net floats, weighted footrope & optional
    gathered net tail pulled onto the mending bench!"""
    tl = Vector(p_top_l)
    tr = Vector(p_top_r)
    bd = Vector(belly_dir).normalized()

    def _net_pt(u, v):
        u_c = max(0.0, min(1.0, u))
        v_c = max(0.0, min(1.0, v))
        top_p = tl.lerp(tr, u_c)
        swag = abs(sin(u_c * 2.0 * pi)) if double_swag else sin(u_c * pi)
        u_arch = sin(u_c * pi)
        y_top_sag = 0.08 * swag
        y_drop = y_top_sag + (drop_h * (0.76 + 0.24 * swag) + sag_mid * u_arch) * v_c
        out_belly = (0.04 + 0.26 * sin(v_c * pi * 0.86) + 0.14 * v_c * v_c) * (0.55 + 0.45 * swag)
        fold = sin(u_c * 4.0 * pi + 0.3) * 0.045 * v_c
        p = top_p + Vector((0.0, -y_drop, 0.0)) + bd * (out_belly + fold)
        if tail_pull is not None and u_c < 0.36 and v_c > 0.50:
            pull_w = ((0.36 - u_c) / 0.36) * ((v_c - 0.50) / 0.50)
            p = p.lerp(Vector(tail_pull), pull_w * 0.78)
        w_wind = (v_c ** 1.25) * (0.38 + 0.28 * swag)
        return p, (w_wind, (phase + 0.26 * u_c) % 1.0)

    # 1. Scalloped Braided Top Headrope, Weighted Bottom Footrope & Vertical Side Leech Cords!
    n_edge = 6
    top_pts, top_u2 = [], []
    bot_pts, bot_u2 = [], []
    for k in range(n_edge + 1):
        u = k / float(n_edge)
        pt, ut = _net_pt(u, 0.0)
        pb, ub = _net_pt(u, 1.0)
        top_pts.append(pt)
        top_u2.append(ut)
        bot_pts.append(pb)
        bot_u2.append(ub)
    tube(mb, top_pts, 0.028, 3, 'rope', C_HEMP_HI, caps=(True, True), mode='flat', suv2=top_u2)
    tube(mb, bot_pts, 0.024, 3, 'rope', C_NET_TAR_HI, caps=(True, True), mode='flat', suv2=bot_u2)
    for u_side in (0.0, 1.0):
        s_pts, s_u2 = [], []
        for j in range(4):
            ps, us = _net_pt(u_side, j / 3.0)
            s_pts.append(ps)
            s_u2.append(us)
        tube(mb, s_pts, 0.022, 3, 'rope', C_HEMP_MID, caps=(False, False), mode='flat', suv2=s_u2)

    # 2. Open Crisscrossing 3D Diamond-Lattice Tarred Rope Cords ('rope' + UV2 gentle wind ripple!)
    slope = 0.62
    for fam in (-1.0, 1.0):
        for ci in range(n_diag):
            c_val = -0.35 + (1.70 * (ci + 0.5) / float(n_diag))
            pts_c, u2_c = [], []
            for si in range(4):
                v = si / 3.0
                u = c_val + fam * slope * v
                if -0.02 <= u <= 1.02:
                    p, u2 = _net_pt(u, v)
                    pts_c.append(p)
                    u2_c.append(u2)
            if len(pts_c) >= 2:
                cord_col = C_NET_TAR_HI if (ci % 2 == 0) else C_NET_TAR_MID
                tube(mb, pts_c, 0.020, 3, 'rope', cord_col, caps=(False, False), mode='flat', suv2=u2_c)

    # 3. Chunky Tan Cork & Crimson Wooden Net Floats strung along the Scalloped Top Headrope!
    tang = (tr - tl).normalized()
    rot_f = Vector((0.0, 1.0, 0.0)).rotation_difference(tang).to_matrix().to_4x4()
    for fi in range(n_corks):
        u_f = (fi + 0.6) / float(n_corks + 0.2)
        fp, _ = _net_pt(u_f, 0.0)
        with xf(mb, T(fp + bd * 0.02) @ rot_f):
            is_mid = (fi == n_corks // 2)
            f_mat = 'paint' if is_mid else 'timber'
            f_col = C_CRIMSON_HI if is_mid else (C_CORK_HI if fi % 2 == 0 else C_CORK_MID)
            cyl(mb, 0.058, -0.075, 0.075, 5, f_mat, f_col, False, 0.0)


def gen_coastal_buccaneer_net_mending_pier(outdir):
    """Picturesque beachside fisherman & smuggler net-mending timber platform (~5.6 m W x 4.0 m D
    x 3.8 m H, -2.80 m deep rocky cobble-and-piling skirt) w/ twin weathered cedar net-drying
    A-frames draped in swaying open-lattice tarred fishing nets & cork floats (UV2 gentle wind
    ripple!), stacked woven lobster pots & sea-green buoy floats, wooden gutting bench & coiled
    mooring lines, fluttering coastal pennant (UV2), convex collider 'col_netpier_base', and warm
    harbour lantern empty 'Lantern_NetPier'."""
    clear_scene()
    mb = MB('coastal_buccaneer_net_mending_pier', seed=2203)
    rng = random.Random(SEED + 2203)
    col_pts = []

    DECK_Y = 0.50

    # 1. Deep Coastal Cobble-Sandbar & Pier Timber-Crib Foundation Skirt plunging cleanly to y = -2.80 m (~5.6 m W x 4.0 m D)
    found_secs = [
        _rect_oct(0.0, -2.80, 0.0, 2.68, 1.88, 0.36),
        _rect_oct(0.0, -1.15, 0.0, 2.60, 1.82, 0.34),
        _rect_oct(0.0,  0.00, 0.0, 2.52, 1.76, 0.32),
        _rect_oct(0.0,  0.34, 0.0, 2.44, 1.68, 0.30),
    ]
    _loft_horizontal_masonry(
        mb, found_secs, 'limestone',
        [C_SANDSTONE_DEEP, C_SANDSTONE_DARK, C_COBBLE_MID, C_SANDSTONE_MID],
        rng, caps=(True, True), top_mat='limestone', top_col=C_SANDSTONE_MID,
    )

    for yc, hx, hz in ((-2.80, 2.68, 1.88), (0.0, 2.52, 1.76), (DECK_Y, 2.48, 1.72), (3.12, 2.22, 1.34)):
        col_pts.extend(_rect_oct(0.0, yc, 0.0, hx, hz, 0.28))

    # Heavy Pier Timber Joists, Weathered Cedar Plank Decking (y=0.50 m) & Driven Mooring Pilings!
    for jz in (-1.34, 0.0, 1.34):
        cbox(mb, (0.0, 0.38, jz), (4.94, 0.16, 0.18), 'timber', C_CEDAR_DARK, 0.0)
    for pi_d in range(7):
        pz_d = -1.44 + pi_d * (2.88 / 6.0)
        pcol = C_CEDAR_WEATHER if pi_d % 3 == 0 else (C_CEDAR_SUN if pi_d % 3 == 1 else C_OAK_RICH)
        cbox(mb, (0.0, DECK_Y - 0.02, pz_d), (4.98, 0.068, 0.43), 'timber', pcol, 0.0)
    cbox(mb, (-0.18, 0.24, -1.78), (1.76, 0.28, 0.34), 'timber', C_CEDAR_DARK, 0.0)
    cbox(mb, (-0.18, 0.38, -1.72), (1.72, 0.06, 0.32), 'timber', C_CEDAR_WEATHER, 0.0)

    # 6 Stout Tarred Coastal Wharf Pilings with Braided Hemp Mooring Wraps!
    for px_p, pz_p, h_add in (
        (-2.44, -1.54, 0.56), ( 2.44, -1.54, 0.62),
        (-2.44,  1.54, 0.44), ( 2.44,  1.54, 0.46),
        (-2.48,  0.00, 0.34), ( 2.48,  0.00, 0.34),
    ):
        top_p = DECK_Y + h_add
        with xf(mb, T(px_p, 0.0, pz_p)):
            cyl(mb, 0.138, -1.40, top_p, 6, 'timber', C_CEDAR_DARK, False, 0.0, 0.118)
            _open_band(mb, 0.152, top_p - 0.22, top_p - 0.10, 6, 'rope', C_HEMP_HI)

    # Rugged Beach Boulders tucked around the Pier Cribbing Base
    for bpos, brad, brot in (
        ((-2.22, 0.22, -1.32), (0.36, 0.24, 0.32), (5, 28, -6)),
        (( 2.20, 0.20,  1.32), (0.40, 0.26, 0.34), (-4, -36, 5)),
    ):
        sculpt_rock_mass(
            mb, bpos, brad, 'limestone', C_SANDSTONE_HI, C_SANDSTONE_MID, C_SANDSTONE_DARK,
            rng, subdiv=1, warp=0.22, strata=0.14, rot_deg=brot, crag_ribs=4, rib_amp=0.10,
        )

    # 2. Twin Weathered Cedar Net-Drying A-Frames (x = -1.92 m & x = +1.76 m) + Overhead Drying Ridge-Pole!
    AF_L_X = -1.92
    AF_R_X =  1.76
    AF_Z0  = -0.32
    AF_Z1  =  1.14
    AF_ZM  =  0.41
    APEX_Y =  2.96
    RAIL_Y =  2.78

    for ax_f in (AF_L_X, AF_R_X):
        tube(mb, [(ax_f, DECK_Y - 0.06, AF_Z0), (ax_f, APEX_Y + 0.18, AF_ZM + 0.10)],
             [0.105, 0.074], 5, 'timber', C_CEDAR_SUN, caps=(False, True), mode='flat')
        tube(mb, [(ax_f, DECK_Y - 0.06, AF_Z1), (ax_f, APEX_Y + 0.18, AF_ZM - 0.10)],
             [0.105, 0.074], 5, 'timber', C_CEDAR_WEATHER, caps=(False, True), mode='flat')
        _add_beam(mb, (ax_f, DECK_Y + 1.06, AF_Z0 + 0.18), (ax_f, DECK_Y + 1.06, AF_Z1 - 0.18),
                  0.092, 0.105, 'timber', C_OAK_RICH, 0.0)
        for fz_b in (AF_Z0, AF_Z1):
            cbox(mb, (ax_f, DECK_Y + 0.10, fz_b), (0.24, 0.20, 0.24), 'iron', C_IRON_FORGED, 0.0)
        with xf(mb, T(ax_f, RAIL_Y, AF_ZM) @ R('X', 28.0)):
            torus(mb, 0.145, 0.036, 6, 3, 'rope', C_HEMP_HI, True)

    # Overhead Cedar Net-Drying Ridge-Pole + Lower Rear Rail + Diagonal Braces!
    with xf(mb, T(-0.08, RAIL_Y, AF_ZM) @ M_Y2X):
        cyl(mb, 0.078, -2.30, 2.30, 6, 'timber', C_CEDAR_SUN, False, 0.0, 0.068)
    with xf(mb, T(-0.08, DECK_Y + 1.18, AF_Z1 - 0.16) @ M_Y2X):
        cyl(mb, 0.056, -2.02, 2.02, 5, 'timber', C_CEDAR_WEATHER, False, 0.0, 0.052)
    _add_beam(mb, (AF_L_X, DECK_Y + 1.18, AF_Z1 - 0.16), (AF_L_X + 0.94, RAIL_Y - 0.06, AF_ZM),
              0.078, 0.078, 'timber', C_OAK_RICH, 0.0)
    _add_beam(mb, (AF_R_X, DECK_Y + 1.18, AF_Z1 - 0.16), (AF_R_X - 0.94, RAIL_Y - 0.06, AF_ZM),
              0.078, 0.078, 'timber', C_OAK_RICH, 0.0)

    # 3. Swaying 3D Open-Lattice Tarred Fishing Nets & Cork Floats Draped Over Both Sides ('rope' + UV2!)
    _build_open_lattice_fishing_net(
        mb,
        p_top_l=(AF_L_X + 0.14, RAIL_Y - 0.04, AF_ZM - 0.06),
        p_top_r=(AF_R_X - 0.12, RAIL_Y - 0.04, AF_ZM - 0.06),
        drop_h=1.52, sag_mid=0.20, belly_dir=(0.0, 0.0, -1.0),
        phase=0.22, n_diag=6, n_corks=5,
        tail_pull=(-1.12, DECK_Y + 0.82, -0.60), double_swag=True,
    )
    _build_open_lattice_fishing_net(
        mb,
        p_top_l=(AF_L_X + 0.24, RAIL_Y - 0.06, AF_ZM + 0.08),
        p_top_r=(AF_R_X - 0.24, RAIL_Y - 0.06, AF_ZM + 0.08),
        drop_h=1.42, sag_mid=0.22, belly_dir=(0.0, 0.0, 1.0),
        phase=0.64, n_diag=4, n_corks=4, double_swag=True,
    )
    _build_open_lattice_fishing_net(
        mb,
        p_top_l=(-2.34, RAIL_Y - 0.04, AF_ZM - 0.02),
        p_top_r=(AF_L_X - 0.04, RAIL_Y - 0.04, AF_ZM - 0.02),
        drop_h=1.18, sag_mid=0.14, belly_dir=(-0.6, 0.0, -0.8),
        phase=0.82, n_diag=3, n_corks=2, double_swag=False,
    )

    # 4. Wooden Gutting & Net-Mending Bench w/ Fresh Catch, Cleaver, Gathered Net Fold & Salt Bait-Bucket!
    BN_X, BN_Z = -0.84, -0.82
    BN_Y = DECK_Y + 0.78
    cbox(mb, (BN_X, BN_Y, BN_Z), (1.76, 0.095, 0.80), 'timber', C_CEDAR_SUN, 0.0, M=R('Y', 4.0))
    cbox(mb, (BN_X, DECK_Y + 0.24, BN_Z), (1.52, 0.06, 0.56), 'timber', C_CEDAR_DARK, 0.0, M=R('Y', 4.0))
    for lx_b in (-0.72, 0.72):
        _add_beam(mb, (BN_X + lx_b, DECK_Y, BN_Z - 0.32), (BN_X + lx_b, BN_Y - 0.02, BN_Z + 0.26),
                  0.090, 0.090, 'timber', C_OAK_DEEP, 0.0)
        _add_beam(mb, (BN_X + lx_b, DECK_Y, BN_Z + 0.32), (BN_X + lx_b, BN_Y - 0.02, BN_Z - 0.26),
                  0.090, 0.090, 'timber', C_OAK_RICH, 0.0)

    # Wooden Fish-Gutting Board, 2 Sculpted Fresh Silvery Coastal Fish & Forged-Iron Gutting Cleaver!
    cbox(mb, (BN_X + 0.16, BN_Y + 0.065, BN_Z - 0.06), (0.74, 0.036, 0.44), 'timber', C_OAK_RICH, 0.0, M=R('Y', 8.0))
    for fx_i, fz_i, frot, fsc in ((0.08, -0.10, 14.0, 1.0), (0.26, 0.06, -16.0, 0.86)):
        with xf(mb, T(BN_X + fx_i, BN_Y + 0.11, BN_Z + fz_i) @ R('Y', frot) @ S(fsc, fsc, fsc)):
            with xf(mb, M_Y2X):
                lathe(mb, [(0.0, -0.22), (0.064, -0.06), (0.050, 0.12), (0.014, 0.20), (0.0, 0.22)],
                      5, 'paint', C_FISH_SILVER, False, False,
                      lambda i, k: C_FISH_BACK if k in (0, 1) else C_FISH_SILVER)
            cbox(mb, (0.24, 0.0, 0.0), (0.08, 0.024, 0.11), 'paint', C_FISH_BACK, 0.0)
    cbox(mb, (BN_X + 0.56, BN_Y + 0.14, BN_Z - 0.18), (0.18, 0.10, 0.020), 'iron', C_IRON_BRIGHT, 0.0, M=R('Y', -26.0) @ R('Z', -16.0))
    _add_beam(mb, (BN_X + 0.64, BN_Y + 0.18, BN_Z - 0.22), (BN_X + 0.78, BN_Y + 0.24, BN_Z - 0.28),
              0.036, 0.036, 'timber', C_OAK_DEEP, 0.0)
    # Gathered tarred net fold being actively mended + wooden mending shuttle & twine spool on port bench end!
    _build_rope_coil(mb, (BN_X - 0.44, BN_Y + 0.04, BN_Z + 0.10), radius=0.17, turns=2, r=0.036, segs=5, psegs=3,
                     col_a=C_NET_TAR_HI, col_b=C_NET_TAR_MID)
    with xf(mb, T(BN_X - 0.64, BN_Y + 0.07, BN_Z - 0.12) @ R('Y', 22.0)):
        cbox(mb, (0.0, 0.0, 0.0), (0.28, 0.030, 0.082), 'timber', C_STAVE_PALE, 0.0)
        cyl(mb, 0.072, -0.02, 0.16, 6, 'rope', C_HEMP_HI, False, 0.0)
    # Coopered Wooden Bait-Brine Bucket beside the Gutting Bench
    with xf(mb, T(-1.80, DECK_Y, -1.04)):
        cyl(mb, 0.18, 0.0, 0.38, 6, 'timber', C_OAK_RICH, False, 0.0, 0.22)
        _open_band(mb, 0.20, 0.08, 0.12, 6, 'iron', C_IRON_FORGED)
        _open_band(mb, 0.22, 0.28, 0.32, 6, 'iron', C_IRON_RUST_HI)

    # 5. Stacked Woven Lobster Pots (100% unobstructed Hero View!), Sea-Green Glass Buoy Floats & Coiled Lines!
    _build_lobster_pot(mb, T(1.22, DECK_Y, -0.82) @ R('Y', -16.0))
    _build_lobster_pot(mb, T(1.38, DECK_Y, -0.22) @ R('Y',  12.0))
    _build_lobster_pot(mb, T(1.28, DECK_Y + 0.36, -0.56) @ R('Y', -34.0))
    # Rear (+Z) Lobster Pot & Salted Fish Barrel for Rich Rear 3/4 Storytelling!
    _build_lobster_pot(mb, T(-1.34, DECK_Y, 1.08) @ R('Y', 22.0))
    _build_coopered_cask(mb, T(1.34, DECK_Y + 0.34, 1.08) @ R('Y', -14.0),
                         radius=0.25, height=0.66, rng=rng, segs=6, powder_band=False)

    # Sea-Green Glass Buoy Floats & Painted Striped Wooden Buoys!
    _build_sea_glass_buoy(mb, ( 0.62, DECK_Y + 0.17, -1.22), radius=0.17, is_glass_sphere=True, col_body=C_SEA_GLASS)
    _build_sea_glass_buoy(mb, ( 0.92, DECK_Y + 0.14, -1.34), radius=0.14, is_glass_sphere=True, col_body=C_SEA_GLASS)
    _build_sea_glass_buoy(mb, ( 0.76, DECK_Y + 0.16,  1.18), radius=0.16, is_glass_sphere=True, col_body=C_SEA_GLASS)
    _build_sea_glass_buoy(mb, (AF_L_X, DECK_Y + 1.54, AF_Z0 + 0.06), radius=0.14, is_glass_sphere=False, col_body=C_CRIMSON_HI)
    _build_sea_glass_buoy(mb, (AF_R_X, DECK_Y + 1.50, AF_Z0 + 0.06), radius=0.14, is_glass_sphere=False, col_body=C_TEAL_HI)

    # Heavy Coiled Mooring Hawsers on Front-Starboard & Rear Pier Corners!
    _build_rope_coil(mb, (2.02, DECK_Y + 0.01, -1.10), radius=0.28, turns=2, r=0.048, segs=6, psegs=3,
                     col_a=C_HEMP_HI, col_b=C_HEMP_MID)
    _build_rope_coil(mb, (-0.10, DECK_Y + 0.01, 1.18), radius=0.25, turns=2, r=0.042, segs=5, psegs=3,
                     col_a=C_HEMP_MID, col_b=C_HEMP_DARK)

    # 6. Fluttering Coastal Pennant Mast ('paint' + UV2!) lashed to the Port A-Frame Apex!
    MAST_X, MAST_Z = AF_L_X, AF_ZM
    with xf(mb, T(MAST_X, 0.0, MAST_Z)):
        cyl(mb, 0.068, RAIL_Y - 0.12, 3.72, 6, 'timber', C_CEDAR_DARK, False, 0.0, 0.040)
        lathe(mb, [(0.0, 3.70), (0.075, 3.76), (0.0, 3.84)], 6, 'brass', C_GOLD_BRIGHT, False)
    _build_wind_banner(
        mb, root_pos=(MAST_X + 0.05, 3.52, MAST_Z), length=1.36, h0=0.40,
        out_dir=(0.90, -0.02, -0.44),
        col_main=C_TEAL_HI, col_alt=C_CREAM_BRIGHT, col_trim=C_CRIMSON_HI,
        phase=0.39, swallowtail=True,
    )

    # 7. Warm Harbour Storm Lantern ('Lantern_NetPier') cantilevered cleanly from the Starboard A-Frame (ZERO view blocking!)
    LANTERN_POS = Vector((1.96, 2.26, -0.96))
    _add_beam(mb, (AF_R_X, 2.66, AF_ZM - 0.22), (1.98, 2.68, -1.00), 0.078, 0.082, 'timber', C_OAK_RICH, 0.0)
    _add_beam(mb, (AF_R_X, 2.10, AF_Z0 + 0.16), (1.92, 2.66, -0.82), 0.050, 0.054, 'iron', C_IRON_FORGED, 0.0)
    _add_beam(mb, (1.96, 2.68, -0.96), LANTERN_POS + Vector((0.0, 0.28, 0.0)), 0.024, 0.024, 'iron', C_IRON_FORGED, 0.0)
    _build_storm_lantern(mb, LANTERN_POS, scale=0.86, brass_cage=True, hanging=True)

    # 8. Coastal Beach Ferns ('foliage' + UV2!) tucked cleanly around the pier base flanks
    for fpos, fsc, flean, fph in (
        ((-1.58, 0.26, -1.72), 0.54, (-0.6, 0.0, -0.8), 0.14),
        (( 1.52, 0.26, -1.70), 0.52, ( 0.6, 0.0, -0.8), 0.38),
        ((-2.22, 0.28,  1.38), 0.56, (-0.7, 0.0,  0.7), 0.65),
        (( 2.20, 0.28,  1.38), 0.54, ( 0.7, 0.0,  0.7), 0.89),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=3, rng=rng, phase=fph, lean_dir=flean, segs=2)

    build(mb)

    add_empty('Lantern_NetPier', LANTERN_POS)
    col_piece('col_netpier_base', col_pts)
    export_landmark_glb(outdir, 'coastal_buccaneer_net_mending_pier.glb')


# ==============================================================================
# 4. VOLCANIC OBSIDIAN LEVIATHAN SPIRE (volcanic_obsidian_leviathan_spire.glb)
# ==============================================================================

def _build_obsidian_dorsal_fin(mb, p_root, p_tip, width, thick, face_nrm, glow_vein=True):
    """Razor-faceted volcanic obsidian dorsal fin blade ('basalt') with high-contrast edge facets
    and optional glowing molten lava base seam ('glass' ONLY!)."""
    a = Vector(p_root)
    b = Vector(p_tip)
    axis = b - a
    if axis.length < 1e-4:
        return
    ax = axis.normalized()
    fn = Vector(face_nrm)
    fn = fn - ax * fn.dot(ax)
    if fn.length < 1e-4:
        fn = Vector((1.0, 0.0, 0.0))
    fn.normalize()
    lat = ax.cross(fn).normalized()

    st_t = [0.00, 0.34, 0.72, 1.00]
    st_w = [width * 0.84, width * 1.00, width * 0.56, 0.018]
    st_d = [thick * 1.00, thick * 0.88, thick * 0.48, 0.014]
    secs = []
    for t, w, d in zip(st_t, st_w, st_d):
        c = a.lerp(b, t) + lat * (0.04 * sin(t * pi))
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
                mb, [a.lerp(b, 0.06) + fn * (s_fn * thick * 0.78), a.lerp(b, 0.46) + fn * (s_fn * thick * 0.72)],
                [width * 0.16, width * 0.05], fn * s_fn,
                hot_core=True, ridge_h=0.022, mat='glass',
                c_core=C_FLAME_MID, c_mid_col=C_FLAME_DEEP, c_edge_col=C_MAGMA_CRIMSON, c_tip_col=C_MAGMA_CRIMSON,
            )


def _build_leviathan_crown_horn(mb, side_sgn):
    """Colossal curved faceted obsidian sea-beast horn flaring dramatically outward from the jaw
    crown (y=3.12 m) and curving majestically skyward to y=6.30 m, veined with glowing molten magma
    ('glass' ONLY!) and strapped with a bolted forged-iron shoulder shackle."""
    horn_pts = [
        Vector((side_sgn * 0.62, 3.06, -0.02)),
        Vector((side_sgn * 1.14, 3.66, -0.06)),
        Vector((side_sgn * 1.48, 4.38, -0.02)),
        Vector((side_sgn * 1.54, 5.14,  0.04)),
        Vector((side_sgn * 1.34, 5.80,  0.08)),
        Vector((side_sgn * 1.04, 6.30,  0.10)),
    ]
    horn_rads = [0.30, 0.26, 0.21, 0.155, 0.095, 0.022]

    secs = []
    scols = []
    for i, (pt, r) in enumerate(zip(horn_pts, horn_rads)):
        t = i / float(len(horn_pts) - 1)
        tang = (horn_pts[min(i + 1, len(horn_pts) - 1)] - horn_pts[max(i - 1, 0)]).normalized()
        fwd = Vector((0.0, 0.0, -1.0))
        fwd = (fwd - tang * fwd.dot(tang)).normalized()
        out_v = tang.cross(fwd).normalized()
        if out_v.x * side_sgn < 0:
            out_v = -out_v
        secs.append([
            pt + out_v * (r * 1.28),
            pt + fwd * (r * 0.92) + out_v * (r * 0.20),
            pt + fwd * (r * 0.56) - out_v * (r * 0.84),
            pt - fwd * (r * 0.56) - out_v * (r * 0.84),
            pt - fwd * (r * 0.92) + out_v * (r * 0.20),
        ])
        scols.append(C_OBSIDIAN_EDGE if t > 0.62 else (C_OBSIDIAN_HI if t > 0.28 else C_OBSIDIAN_MID))
    loft(mb, secs, 'basalt', C_OBSIDIAN_HI, closed=True, caps=(True, True), mode='flat', scols=scols)

    lava_pts = [p + Vector((0.0, 0.0, -r * 0.88)) for p, r in zip(horn_pts[:5], horn_rads[:5])]
    _sculpt_glow_ribbon(
        mb, lava_pts, [0.058, 0.052, 0.044, 0.032, 0.018], (0.0, 0.0, -1.0),
        hot_core=True, ridge_h=0.026, mat='glass',
        c_core=C_FLAME_CORE, c_mid_col=C_FLAME_MID, c_edge_col=C_FLAME_DEEP, c_tip_col=C_MAGMA_CRIMSON,
    )

    # 4 Swept Outer Horn-Barb Fin Spurs bristling off the outer flank of each colossal horn!
    for h_i, b_len, b_up in ((1, 0.60, 0.34), (2, 0.58, 0.44), (3, 0.48, 0.48), (4, 0.34, 0.44)):
        pr = horn_pts[h_i]
        pt = pr + Vector((side_sgn * b_len, b_up, 0.16))
        _build_obsidian_dorsal_fin(mb, pr, pt, 0.16, 0.060, (0.0, 0.0, -1.0), glow_vein=(h_i in (1, 2)))

    # Heavy Forged-Iron Restraining Shackle Cuff clamped snugly onto the Lower Horn Root!
    sh_p = horn_pts[1]
    sh_t = (horn_pts[2] - horn_pts[0]).normalized()
    rot_sh = Vector((0.0, 1.0, 0.0)).rotation_difference(sh_t).to_matrix().to_4x4()
    sh_r = horn_rads[1] * 1.18
    with xf(mb, T(sh_p) @ rot_sh):
        cyl(mb, sh_r, -0.14, 0.14, 6, 'iron', C_IRON_FORGED, False, 0.0)
        torus(mb, sh_r + 0.02, 0.044, 6, 4, 'iron', C_IRON_BRIGHT, False)
    front_lug = sh_p + Vector((side_sgn * (sh_r + 0.05), -0.06, -0.16))
    rear_lug  = sh_p + Vector((side_sgn * (sh_r + 0.05), -0.06,  0.18))
    cbox(mb, front_lug, (0.18, 0.18, 0.18), 'iron', C_IRON_RUST_HI, 0.0)
    cbox(mb, rear_lug,  (0.18, 0.18, 0.18), 'iron', C_IRON_RUST_HI, 0.0)
    return front_lug, rear_lug


def gen_volcanic_obsidian_leviathan_spire(outdir):
    """Towering carved charred-basalt & obsidian horned sea-beast spire altar (~4.2 m W x 4.2 m D
    x 6.4 m H, -3.50 m deep volcanic basalt skirt) w/ sweeping jagged volcanic dorsal fins &
    horned beast-jaw crown cradling a blazing incandescent lava heart core ('glass' warm molten
    orange-amber linear COLOR_0 — ZERO skull_glow!), iron shackles, glowing magma spine fissures &
    anchored basalt spurs, convex collider 'col_volcspire_base', and empty 'Lantern_VolcSpire'."""
    clear_scene()
    mb = MB('volcanic_obsidian_leviathan_spire', seed=2204)
    rng = random.Random(SEED + 2204)
    col_pts = []

    STEP1_Y = 0.44
    DAIS_Y  = 0.96
    JAW_Y   = 3.16
    CORE_Y  = 4.20

    # 1. Deep Lava-Cracked Charred-Basalt Plinth Skirt plunging cleanly to y = -3.50 m (~4.2 m W x 4.2 m D)
    plinth_secs = [
        _reg_poly(0.0, -3.50, 0.0, 2.12, sides=8, rot_deg=22.5),
        _reg_poly(0.0, -1.55, 0.0, 2.06, sides=8, rot_deg=22.5),
        _reg_poly(0.0,  0.00, 0.0, 2.00, sides=8, rot_deg=22.5),
        _reg_poly(0.0, STEP1_Y, 0.0, 1.92, sides=8, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, plinth_secs, 'basalt',
        [C_OBSIDIAN_ABYSS, C_OBSIDIAN_DARK, C_OBSIDIAN_MID, C_OBSIDIAN_HI],
        rng, caps=(True, True), top_mat='basalt', top_col=C_OBSIDIAN_MID,
    )

    dais_secs = [
        _reg_poly(0.0, STEP1_Y - 0.02, 0.0, 1.56, sides=8, rot_deg=22.5),
        _reg_poly(0.0, DAIS_Y,         0.0, 1.44, sides=8, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, dais_secs, 'basalt',
        [C_OBSIDIAN_DARK, C_OBSIDIAN_HI], rng, caps=(False, True),
        top_mat='basalt', top_col=C_OBSIDIAN_MID,
    )

    for yc, rc in ((-3.50, 2.12), (0.0, 2.00), (DAIS_Y, 1.92), (4.60, 1.66), (6.36, 0.92)):
        col_pts.extend(_reg_poly(0.0, yc, 0.0, rc, sides=8, rot_deg=22.5))

    # Jagged Volcanic Basalt Approach Steps on Seaward (-Z) Hero Face + Flanking Volcanic Basalt Crag Teeth!
    cbox(mb, (0.0, 0.22, -1.96), (1.28, 0.42, 0.36), 'basalt', C_OBSIDIAN_MID, 0.0)
    cbox(mb, (0.0, 0.62, -1.62), (1.08, 0.36, 0.34), 'basalt', C_OBSIDIAN_HI, 0.0)
    for sx in (-1.0, 1.0):
        sculpt_basalt_column(mb, (sx * 0.92, -0.35, -1.74), 1.24, 0.26, 5, sx * 10.0, -8.0,
                             C_OBSIDIAN_ABYSS, C_OBSIDIAN_EDGE, rng, mat='basalt', magma_seam=True)
        sculpt_basalt_column(mb, (sx * 0.96, -0.35,  1.66), 1.42, 0.28, 5, sx * 12.0,  9.0,
                             C_OBSIDIAN_ABYSS, C_OBSIDIAN_EDGE, rng, mat='basalt', magma_seam=True)

    # 6 Radiating Molten Magma Plinth Fissures ('glass' ONLY!)
    for c_ang in (-145.0, -90.0, -35.0, 35.0, 90.0, 145.0):
        ar = radians(c_ang)
        ca, sa = cos(ar), sin(ar)
        p0 = Vector((0.64 * ca, DAIS_Y + 0.03, 0.64 * sa))
        p1 = Vector((1.28 * ca - 0.08 * sa, DAIS_Y + 0.02, 1.28 * sa + 0.08 * ca))
        p2 = Vector((1.78 * ca, STEP1_Y + 0.03, 1.78 * sa))
        _sculpt_glow_ribbon(
            mb, [p0, p1, p2], [0.090, 0.072, 0.044], (0.0, 1.0, 0.0),
            hot_core=True, ridge_h=0.032, mat='glass',
            c_core=C_FLAME_MID, c_mid_col=C_FLAME_DEEP, c_edge_col=C_MAGMA_CRIMSON, c_tip_col=C_MAGMA_CRIMSON,
        )

    # 2. Towering Carved Charred-Basalt & Obsidian Sea-Beast Spire Trunk (y = 0.96 .. 3.24 m)
    trunk_secs = [
        _rect_oct(0.0, DAIS_Y - 0.02, 0.0, 0.96, 0.92, 0.28),
        _rect_oct(0.0, 1.78,          0.0, 0.80, 0.78, 0.24),
        _rect_oct(0.0, 2.58,          0.0, 0.76, 0.74, 0.22),
        _rect_oct(0.0, JAW_Y,         0.0, 0.92, 0.88, 0.28),
    ]
    _loft_horizontal_masonry(
        mb, trunk_secs, 'basalt',
        [C_OBSIDIAN_DARK, C_OBSIDIAN_MID, C_OBSIDIAN_HI, C_OBSIDIAN_EDGE],
        rng, caps=(False, True), top_mat='basalt', top_col=C_OBSIDIAN_HI,
    )
    # Sculpted Octagonal Forged-Iron Restraining Collars + Bolted Iron Stud Teeth hugging the Spire Neck (NO flat square shelf!)
    with xf(mb, T(0.0, 1.82, 0.0) @ R('Y', 22.5)):
        cyl(mb, 0.90, -0.09, 0.09, 8, 'iron', C_IRON_FORGED, False, 0.0)
        torus(mb, 0.91, 0.040, 8, 4, 'iron', C_IRON_BRIGHT, False)
    with xf(mb, T(0.0, JAW_Y - 0.08, 0.0) @ R('Y', 22.5)):
        cyl(mb, 0.98, -0.10, 0.10, 8, 'iron', C_IRON_DARK, False, 0.0, 1.02)
        torus(mb, 1.01, 0.052, 8, 4, 'iron', C_IRON_RUST_HI, False)
        for k in range(8):
            ar = radians(k * 45.0)
            cbox(mb, (1.03 * cos(ar), 0.0, 1.03 * sin(ar)), (0.12, 0.18, 0.12), 'iron',
                 C_IRON_BRIGHT if k % 2 == 0 else C_IRON_RUST_HI, 0.0, M=R('Y', -k * 45.0))

    # Swept Side Volcanic Gill-Fin Ribs flaring dramatically off the Port & Starboard Spire Flanks!
    for side_sgn in (-1.0, 1.0):
        for gy, g_out, g_up, g_glow in ((1.48, 0.56, 0.34, False), (2.22, 0.62, 0.44, True), (2.82, 0.54, 0.40, False)):
            _build_obsidian_dorsal_fin(
                mb, Vector((side_sgn * 0.72, gy, 0.06)),
                Vector((side_sgn * (0.72 + g_out), gy + g_up, 0.30)),
                0.18, 0.064, (0.0, 0.0, -1.0), glow_vein=g_glow,
            )

    # Glowing Vertical Magma Spine Fissures running boldly up Front (-Z) & Rear (+Z) ('glass' ONLY!)
    for z_face in (-1.0, 1.0):
        fiss_pts = [
            Vector((0.0, DAIS_Y + 0.08, z_face * 0.92)),
            Vector((z_face * 0.10, 1.78, z_face * 0.81)),
            Vector((-z_face * 0.08, 2.56, z_face * 0.77)),
            Vector((0.0, JAW_Y + 0.02, z_face * 0.92)),
        ]
        _sculpt_glow_ribbon(
            mb, fiss_pts, [0.086, 0.070, 0.068, 0.090], (0.0, 0.0, z_face),
            hot_core=True, ridge_h=0.036, mat='glass',
            c_core=C_FLAME_CORE, c_mid_col=C_FLAME_MID, c_edge_col=C_FLAME_DEEP, c_tip_col=C_MAGMA_CRIMSON,
        )
        for ry in (1.36, 2.16):
            for sx in (-1.0, 1.0):
                _add_beam(mb, (0.0, ry - 0.14, z_face * 0.86),
                          (sx * 0.68, ry + 0.16, z_face * 0.78), 0.11, 0.10, 'basalt', C_OBSIDIAN_EDGE, 0.0)

    # Fierce Sculpted Obsidian Leviathan Visage: Brow-Mask, Serrated Cheek-Fins, Chin Fang & Blazing Eyes (-Z)!
    with xf(mb, T(0.0, 2.66, -0.78)):
        cbox(mb, (0.0, 0.08, -0.08), (0.68, 0.30, 0.24), 'basalt', C_OBSIDIAN_EDGE, 0.0)
        # Carved central obsidian nasal-ridge crest & lower jaw chin-fang
        tube(mb, [(0.0, 0.18, -0.18), (0.0, -0.06, -0.34), (0.0, -0.36, -0.22)],
             [0.12, 0.09, 0.024], 4, 'basalt', C_OBSIDIAN_EDGE, caps=(False, True), mode='flat')
        for sx in (-1.0, 1.0):
            _add_beam(mb, (sx * 0.08, 0.08, -0.18), (sx * 0.62, 0.38, -0.10), 0.11, 0.10, 'basalt', C_OBSIDIAN_EDGE, 0.0)
            _add_beam(mb, (sx * 0.16, -0.12, -0.16), (sx * 0.58, -0.26, -0.02), 0.09, 0.09, 'basalt', C_OBSIDIAN_HI, 0.0)
            with xf(mb, T(sx * 0.24, 0.04, -0.23)):
                lathe(mb, [(0.0, -0.04), (0.096, 0.0), (0.0, 0.068)], 4, 'glass', C_FLAME_CORE, False)

    # 3. Horned Beast-Jaw Crown Cradling the Blazing Incandescent Lava Heart Core (y = 3.16 .. 6.38 m)!
    with xf(mb, T(0.0, JAW_Y, 0.0)):
        bowl_prof = [
            (0.00, 0.00),
            (0.68, 0.00),
            (0.92, 0.26),
            (0.98, 0.58),
            (0.84, 0.66),
            (0.68, 0.44),
            (0.00, 0.36),
        ]
        lathe(mb, bowl_prof, 8, 'basalt', C_OBSIDIAN_DARK, False, False,
              lambda i, k: C_OBSIDIAN_EDGE if i in (2, 3) else C_OBSIDIAN_MID)
        with xf(mb, T(0.0, 0.58, 0.0)):
            torus(mb, 0.94, 0.068, 8, 4, 'iron', C_IRON_FORGED, False)
        lathe(mb, [(0.0, 0.36), (0.76, 0.44), (0.64, 0.58), (0.0, 0.66)],
              8, 'glass', C_FLAME_DEEP, False, False,
              lambda i, k: C_FLAME_CORE if i >= 2 else C_MAGMA_CRIMSON)
        # 8 Razor Curved Obsidian Beast-Jaw Fangs bristling upward around the Maw Crown!
        for k in range(8):
            ar = radians(k * 45.0 + 22.5)
            ca, sa = cos(ar), sin(ar)
            is_big = (k % 2 == 0)
            f_pts = [
                Vector((0.84 * ca, 0.14, 0.84 * sa)),
                Vector((1.08 * ca, 0.56, 1.08 * sa)),
                Vector((0.92 * ca, 1.24 if is_big else 0.92, 0.92 * sa)),
            ]
            tube(mb, f_pts, [0.128, 0.090, 0.020], 4, 'basalt',
                 C_OBSIDIAN_EDGE if is_big else C_OBSIDIAN_HI, caps=(False, True), mode='flat')

    # Towering Sweeping Rear Dorsal Spine Fin-Crest rising cleanly behind the Lava Core to y = 6.38 m!
    spine_pts = [
        Vector((0.0, 1.44, 0.82)),
        Vector((0.0, 2.54, 0.86)),
        Vector((0.0, 3.68, 0.98)),
        Vector((0.0, 4.78, 0.96)),
        Vector((0.0, 5.68, 0.72)),
        Vector((0.0, 6.38, 0.32)),
    ]
    tube(mb, spine_pts, [0.30, 0.26, 0.24, 0.20, 0.13, 0.028], 5, 'basalt', C_OBSIDIAN_HI,
         caps=(False, True), mode='flat',
         scols=[C_OBSIDIAN_DARK, C_OBSIDIAN_MID, C_OBSIDIAN_HI, C_OBSIDIAN_EDGE, C_OBSIDIAN_EDGE, C_OBSIDIAN_EDGE])
    _sculpt_glow_ribbon(
        mb, [p + Vector((0.0, 0.0, 0.20)) for p in spine_pts[:5]],
        [0.064, 0.056, 0.050, 0.040, 0.024], (0.0, 0.0, 1.0),
        hot_core=True, ridge_h=0.028, mat='glass',
        c_core=C_FLAME_CORE, c_mid_col=C_FLAME_MID, c_edge_col=C_FLAME_DEEP, c_tip_col=C_MAGMA_CRIMSON,
    )
    # 6 Sweeping Jagged Obsidian Dorsal Fin Blades flaring boldly backward & skyward along the Rear Spine!
    for f_root, f_tip, f_w, f_d, f_g in (
        (Vector((0.0, 1.66, 0.86)), Vector((0.0, 2.18, 1.62)), 0.22, 0.076, False),
        (Vector((0.0, 2.48, 0.90)), Vector((0.0, 3.16, 1.78)), 0.25, 0.082, True),
        (Vector((0.0, 3.36, 0.98)), Vector((0.0, 4.18, 1.88)), 0.26, 0.084, True),
        (Vector((0.0, 4.22, 1.00)), Vector((0.0, 5.14, 1.78)), 0.24, 0.080, True),
        (Vector((0.0, 5.02, 0.90)), Vector((0.0, 5.92, 1.48)), 0.21, 0.072, False),
        (Vector((0.0, 5.66, 0.70)), Vector((0.0, 6.36, 0.86)), 0.17, 0.062, False),
    ):
        _build_obsidian_dorsal_fin(mb, f_root, f_tip, f_w, f_d, (1.0, 0.0, 0.0), glow_vein=f_g)

    # Blazing Incandescent Lava Heart Core Cradled Inside the Horned Beast-Jaw Crown (y = 4.20 m, 'glass' ONLY!)
    with xf(mb, T(0.0, CORE_Y, 0.0)):
        lathe(mb, [(0.0, -0.50), (0.34, -0.32), (0.44, 0.00), (0.34, 0.32), (0.0, 0.54)],
              8, 'glass', C_FLAME_CORE, False, False,
              lambda i, k: C_FLAME_WHITE if i == 2 else (C_FLAME_CORE if i in (1, 3) else C_FLAME_MID))
        # 6 Bold Dark Obsidian Volcanic Crust Armor Ribs cracking open around the Molten Lava Heart!
        for k in range(6):
            ang = radians(k * 60.0 + 30.0)
            ca, sa = cos(ang), sin(ang)
            c_pts = [
                Vector((0.36 * ca, -0.46, 0.36 * sa)),
                Vector((0.55 * ca,  0.00, 0.55 * sa)),
                Vector((0.32 * ca,  0.50, 0.32 * sa)),
            ]
            tube(mb, c_pts, [0.082, 0.105, 0.044], 4, 'basalt', C_OBSIDIAN_ABYSS, caps=(True, True), mode='flat')
        # 4 Swirling S-Curved Incandescent Magma Flame Plumes erupting skyward from the Lava Heart ('glass' ONLY!)
        for fx_f, fz_f, fh_f, fr_f, sw_x in (
            ( 0.00,  0.00, 1.36, 0.21,  0.14),
            (-0.26, -0.14, 0.96, 0.14, -0.18),
            ( 0.26, -0.14, 0.98, 0.14,  0.18),
            ( 0.00,  0.22, 0.90, 0.13, -0.10),
        ):
            fl_pts = [
                Vector((fx_f, 0.28, fz_f)),
                Vector((fx_f * 0.7 - sw_x * 0.4, 0.28 + fh_f * 0.40, fz_f * 0.7)),
                Vector((fx_f * 0.4 + sw_x * 0.5, 0.28 + fh_f * 0.76, fz_f * 0.4)),
                Vector((fx_f * 0.2 + sw_x * 0.2, 0.28 + fh_f,        fz_f * 0.2)),
            ]
            tube(mb, fl_pts, [fr_f, fr_f * 0.64, fr_f * 0.32, 0.016], 4, 'glass', C_FLAME_MID,
                 caps=(False, True), mode='flat',
                 scols=[C_MAGMA_CRIMSON, C_FLAME_DEEP, C_FLAME_MID, C_FLAME_CORE])

    # 4. Twin Colossal Curved Obsidian Sea-Beast Horns + 4 Widened Anchored Basalt Spurs & Iron Chains!
    for side_sgn in (-1.0, 1.0):
        front_lug, rear_lug = _build_leviathan_crown_horn(mb, side_sgn)

        for z_sp, lug_pt in ((-1.0, front_lug), (1.0, rear_lug)):
            # Steep angular basalt anchor spur rooted solidly into the octagonal plinth & cleanly spaced for taut chains!
            spur_bp = Vector((side_sgn * 1.44, -0.35, z_sp * 1.04))
            spur_dir = Vector((side_sgn * 0.30, 1.0, z_sp * 0.26)).normalized()
            spur_pts = [spur_bp, spur_bp + spur_dir * 1.18, spur_bp + spur_dir * 2.06]
            tube(mb, spur_pts, [0.34, 0.22, 0.032], 4, 'basalt', C_OBSIDIAN_HI,
                 caps=(False, True), mode='flat',
                 scols=[C_OBSIDIAN_DARK, C_OBSIDIAN_MID, C_OBSIDIAN_EDGE])
            bot_anchor = spur_pts[1] + Vector((0.0, 0.22, 0.0))
            with xf(mb, T(bot_anchor)):
                cyl(mb, 0.25, -0.09, 0.09, 6, 'iron', C_IRON_BRIGHT, False, 0.0)
            _add_chain_links(
                mb, lug_pt + Vector((0.0, -0.04, 0.0)), bot_anchor + Vector((0.0, 0.08, 0.0)),
                n_links=5, link_r=0.17, wire_r=0.048, segs=5, psegs=4, sag=0.11,
                mat='iron', rust_stride=2, stretch_y=1.44,
                col_a=C_IRON_BRIGHT, col_b=C_IRON_RUST_HI,
            )

    LANTERN_POS = Vector((0.0, CORE_Y, 0.0))

    build(mb)

    add_empty('Lantern_VolcSpire', LANTERN_POS)
    col_piece('col_volcspire_base', col_pts)
    export_landmark_glb(outdir, 'volcanic_obsidian_leviathan_spire.glb')


SOVEREIGN_CRAFT_GENERATORS = [
    gen_pirate_cooperage_barrel_workshop,
    gen_ancient_astral_tide_obelisk,
    gen_coastal_buccaneer_net_mending_pier,
    gen_volcanic_obsidian_leviathan_spire,
]
