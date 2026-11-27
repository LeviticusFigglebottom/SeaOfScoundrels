# Sea of Scoundrels: 4 sculpted 3D Sea-Haven & Ancient Relic Landmarks (Wave I-18 / Pass I-Q11 — 74-Landmark Fleet!).
# Imported by tools/blender/gen_island_landmarks.py.
# Authored in Godot game coordinates (-Z seaward/hero-facing, +Y up, +X starboard, metres)
# and converted to Blender's Z-up frame on mesh creation via _landmark_common.
# STRICT SHARED-TEXTURE DEDUP CONTRACT: uses ONLY the 11 existing shared PBR materials
# (limestone, limestone_moss, basalt, temple_stone, skull_stone, timber, paint, rope,
# iron, brass, foliage) + untextured glass / skull_glow / col.
# Emissive rule:
#   - mat_landmark_skull_glow ONLY on ancient_celestial_moon_dial (turquoise/aqua lunar runes & orb)
#   - mat_landmark_glass with warm amber/molten linear COLOR_0 on pirate_harbour_clock_belltower,
#     coastal_buccaneer_grog_stall, and volcanic_obsidian_anchor_monolith.
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

# Weathered harbour sandstone ashlar, beach cobble & coastal driftwood
C_SANDSTONE_HI   = srgb('#ebd9b4')
C_SANDSTONE_MID  = srgb('#cca97c')
C_SANDSTONE_DARK = srgb('#927556')
C_SANDSTONE_DEEP = srgb('#5d4e3e')

C_COBBLE_HI      = srgb('#cfc3ac')
C_COBBLE_MID     = srgb('#938876')
C_COBBLE_DARK    = srgb('#5a544c')
C_COBBLE_WET     = srgb('#41403b')

C_OAK_SUN        = srgb('#bd8449')
C_OAK_RICH       = srgb('#82522b')
C_OAK_DEEP       = srgb('#4e2f19')
C_OAK_CHAR       = srgb('#3a271c')
C_DRIFT_PALE     = srgb('#d4c5ab')
C_DRIFT_MID      = srgb('#9a8970')
C_DRIFT_DARK     = srgb('#645746')

# Terracotta roof shingles, buccaneer awning stripes, tavern bottles & harbour flags
C_TERRA_HI       = srgb('#d9653d')
C_TERRA_MID      = srgb('#b44424')
C_TERRA_DARK     = srgb('#7c2a15')

C_CRIMSON_HI     = srgb('#cf2c20')
C_CRIMSON_MID    = srgb('#951d16')
C_CRIMSON_DARK   = srgb('#5b120e')
C_TEAL_HI        = srgb('#23858a')
C_TEAL_MID       = srgb('#1b6368')
C_TEAL_DARK      = srgb('#123f44')
C_CREAM_SAIL     = srgb('#efe1c3')
C_CREAM_AGED     = srgb('#cdb891')
C_BOTTLE_GREEN   = srgb('#207845')
C_BOTTLE_EMERALD = srgb('#329c59')
C_BOTTLE_AMBER   = srgb('#b85d1a')

# Ancient sunken-civilization lunar temple limestone & reef moss
C_MOON_STONE_HI  = srgb('#d6ccb4')
C_MOON_STONE_MID = srgb('#9f9784')
C_MOON_STONE_DK  = srgb('#666256')
C_MOON_STONE_SK  = srgb('#46453c')
C_SLATE_BLUE     = srgb('#3e4e58')

# Burnished nautical brass, cast bell bronze, copper verdigris, pewter & wrought iron
C_GOLD_BRIGHT    = srgb('#f8cf4e')
C_BRASS_WARM     = srgb('#dba43b')
C_BRASS_DARK     = srgb('#8f6420')
C_BRONZE_BELL    = srgb('#c68d42')
C_BRONZE_DARK    = srgb('#724f25')
C_VERDIGRIS_HI   = srgb('#5ec0a8')
C_VERDIGRIS_MID  = srgb('#348c78')
C_PEWTER_HI      = srgb('#bcc5d0')
C_PEWTER_MID     = srgb('#7c8591')
C_IRON_BRIGHT    = srgb('#7a8394')
C_IRON_FORGED    = srgb('#4b5160')
C_IRON_DARK      = srgb('#282a34')
C_IRON_RUST_HI   = srgb('#ad5e34')
C_IRON_RUST_MID  = srgb('#7d4224')

# Volcanic obsidian & columnar basalt tones (crisp sunlit edge sheen vs abyssal shadow)
C_OBSIDIAN_EDGE  = srgb('#8d8498')
C_OBSIDIAN_HI    = srgb('#645c6f')
C_OBSIDIAN_MID   = srgb('#403a49')
C_OBSIDIAN_DARK  = srgb('#272330')
C_OBSIDIAN_ABYSS = srgb('#16141c')

# Mystical turquoise lunar glow (USED ONLY with 'skull_glow' on ancient_celestial_moon_dial!)
C_AQUA_CORE      = srgb('#46f7e0')
C_AQUA_MID       = srgb('#12cfb4')
C_AQUA_DEEP      = srgb('#08857a')

# Warm glowing clock-dial glass, lantern flame & volcanic molten cracks/chains (USED ONLY with 'glass'!)
C_DIAL_CREAM     = srgb('#ffe08c')
C_DIAL_AMBER     = srgb('#ffa834')
C_FLAME_WHITE    = srgb('#ffc23a')
C_FLAME_CORE     = srgb('#ff7e12')
C_FLAME_MID      = srgb('#e83b04')
C_FLAME_DEEP     = srgb('#a61402')
C_MAGMA_CRIMSON  = srgb('#660a02')

# Coastal ivy, jungle vines & beach fern foliage
C_VINE_DARK      = srgb('#174b1e')
C_VINE_MID       = srgb('#2f7827')
C_VINE_SUN       = srgb('#7ec22b')


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


def _build_coopered_cask(mb, M_bar, radius=0.33, height=0.82, rng=None,
                         col_a=C_OAK_RICH, col_b=C_OAK_SUN, col_head=C_OAK_DEEP,
                         segs=6, stripe_col=None):
    """Chunky coopered oak rum puncheon cask with forged-iron hoops."""
    hh = height * 0.5
    prof = [
        (0.0,           -hh),
        (radius * 0.82, -hh),
        (radius,         0.0),
        (radius * 0.82,  hh),
        (0.0,            hh),
    ]
    stave_cols = [
        jit(col_a if k % 2 == 0 else col_b, rng, 0.05, 0.015) if rng else col_a
        for k in range(segs)
    ]
    with xf(mb, M_bar):
        lathe(mb, prof, segs, 'timber', col_a, False, False,
              lambda i, k: col_head if i in (0, 3) else stave_cols[k])
        for hi_idx, (hy, hr) in enumerate((
            (-hh * 0.60, radius * 0.94),
            ( hh * 0.60, radius * 0.94),
        )):
            cyl(mb, hr, hy - 0.028, hy + 0.028, segs, 'iron',
                C_IRON_RUST_HI if hi_idx == 1 else C_IRON_FORGED, False, 0.0)
        if stripe_col is not None:
            cyl(mb, radius * 1.015, -hh * 0.14, hh * 0.14, segs, 'paint', stripe_col, False, 0.0)


def _build_rope_coil_lean(mb, center, radius=0.26, turns=2, r=0.035, segs=6, psegs=4, col=C_ROPE):
    """Chunky coiled braided hemp rope pile ('rope')."""
    for i in range(turns):
        rr = radius * (1.0 - 0.24 * i)
        with xf(mb, T(center[0], center[1] + r * (1.0 + i * 1.56), center[2])):
            torus(mb, rr, r, segs, psegs, 'rope', mul(col, 0.88 + 0.12 * (i % 2)), True)


def _build_wind_pennant(mb, root_pos, length=1.40, h0=0.38, out_dir=(0.92, -0.04, -0.38),
                        col_main=C_TEAL_HI, col_alt=C_CRIMSON_HI, col_trim=C_GOLD_BRIGHT, phase=0.32):
    """Wind-whipped double-sided swallowtail harbour flag ('paint') with UV2 wind weights."""
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
        wave = sin(t * 2.1 * pi) * 0.15 * t
        droop = -0.15 * t * t
        hh = h0 * (1.0 - 0.42 * t)
        ctr = rp + od * (length * t) + side * wave + Vector((0.0, droop, 0.0))
        top_pts.append(ctr + Vector((0.0, hh * 0.5, 0.0)))
        bot_pts.append(ctr - Vector((0.0, hh * 0.5, 0.0)))
        weights.append((t ** 1.15) * 0.94)
    for i in range(segs):
        c_seg = col_trim if i == 0 else (col_main if i % 2 == 1 else col_alt)
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


def _add_climbing_ivy_corner(mb, corner_xz, out_dir, y0, y1, rng, phase=0.0, segs=5):
    """Lush coastal sea-ivy vine climbing flush up the outer corner of a tower ('foliage' + UV2)."""
    cx, cz = corner_xz
    od = Vector((out_dir[0], 0.0, out_dir[2])).normalized()
    side = Vector((-od.z, 0.0, od.x))
    pts = []
    for i in range(segs + 1):
        t = i / float(segs)
        # Track pedestal taper (y0..2.22 m) then tuck snugly onto upper timber corner post (1.04, 1.04)!
        inward_step = -0.34 * smooth01((t - 0.36) / 0.28)
        wiggle = sin(t * 2.2 * pi + phase * 6.28) * 0.07
        pts.append(Vector((cx, y0 + (y1 - y0) * t, cz)) + od * (0.02 + inward_step) + side * wiggle)

    for i in range(segs):
        t0 = i / float(segs)
        t1 = (i + 1) / float(segs)
        p0, p1 = pts[i], pts[i + 1]
        w = 0.036 * (1.0 - 0.28 * t0)
        c0 = jit(mix(C_VINE_DARK, C_VINE_MID, t0), rng, 0.05)
        c1 = jit(mix(C_VINE_MID, C_VINE_SUN, t1 * 0.8), rng, 0.05)
        u0 = (0.14 + 0.32 * t0, phase)
        u1 = (0.14 + 0.32 * t1, phase)
        mb.f(
            [mb.v(p0 - side * w), mb.v(p0 + side * w), mb.v(p1 + side * w), mb.v(p1 - side * w)],
            'foliage', [c0, c0, c1, c1], [(0.2, t0), (0.8, t0), (0.8, t1), (0.2, t1)],
            smooth=False, uv2=[u0, u0, u1, u1],
        )
        for sgn in (-1.0, 1.0):
            root = p0.lerp(p1, 0.62 if sgn > 0 else 0.25)
            l_dir = (od * 0.65 + side * (sgn * 0.62) + Vector((0.0, -0.30, 0.0))).normalized()
            l_perp = l_dir.cross(Vector((0.0, 1.0, 0.0)))
            if l_perp.length < 1e-4:
                l_perp = side
            l_perp.normalize()
            ll = rng.uniform(0.20, 0.27)
            lw = ll * 0.48
            p_b = root
            p_ml = root + l_dir * (ll * 0.46) - l_perp * lw
            p_mr = root + l_dir * (ll * 0.46) + l_perp * lw
            p_tp = root + l_dir * ll + Vector((0.0, -0.04, 0.0))
            u_b = (0.18 + 0.28 * t0, phase)
            u_m = (0.48 + 0.28 * t0, phase)
            u_e = (0.74 + 0.22 * t0, phase)
            mb.f([mb.v(p_b), mb.v(p_ml), mb.v(p_tp), mb.v(p_mr)], 'foliage',
                 [c0, c1, C_VINE_SUN, c1], [(0.5, 0.0), (0.0, 0.5), (0.5, 1.0), (1.0, 0.5)],
                 smooth=False, uv2=[u_b, u_m, u_e, u_m])


def _add_coastal_fern_cluster(mb, root_pos, scale=0.80, n_fronds=4, rng=None, phase=0.0,
                              lean_dir=None, segs=2, c_dark=C_VINE_DARK, c_mid=C_VINE_MID, c_tip=C_VINE_SUN):
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


def _sculpt_magma_ribbon(mb, path_pts, widths, surface_nrm, hot_core=True, ridge_h=0.044, mat='glass',
                         c_core=C_FLAME_CORE, c_mid_col=C_FLAME_MID, c_edge_col=C_FLAME_DEEP, c_tip_col=C_MAGMA_CRIMSON):
    """Surface-hugging glowing molten magma or lunar rune vein ridge."""
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
        mid_pts.append(pts[i] + nrm * (ridge_h + 0.008 * sin(i * 1.7)))
    for i in range(n - 1):
        cm = c_core if (hot_core and i <= n // 2) else c_mid_col
        ce = c_edge_col if i < n - 2 else c_tip_col
        inside = (pts[i] + pts[i + 1]) * 0.5 - nrm * 0.5
        mb.fp([left_pts[i], mid_pts[i], mid_pts[i + 1], left_pts[i + 1]], mat,
              [ce, cm, cm, ce], (1, 0, 0), inside, smooth=False)
        mb.fp([mid_pts[i], right_pts[i], right_pts[i + 1], mid_pts[i + 1]], mat,
              [cm, ce, ce, cm], (1, 0, 0), inside, smooth=False)


def _add_chain_links(mb, p_start, p_end, n_links=6, link_r=0.16, wire_r=0.048,
                     segs=5, psegs=4, sag=0.24, mat='iron', rust_stride=2, stretch_y=1.42,
                     col_a=C_IRON_FORGED, col_b=C_IRON_RUST_HI, glow_indices=None):
    """Tightly interlocking arc-length-spaced forged-iron (and optional molten-glowing) chain links."""
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

    glow_set = set(glow_indices) if glow_indices is not None else set()
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
        if k in glow_set:
            l_mat = 'glass'
            l_col = C_FLAME_MID if (k % 2 == 0) else C_FLAME_DEEP
        else:
            l_mat = mat
            l_col = col_b if (k % rust_stride == 0) else col_a
        with xf(mb, T(pt) @ rot_q @ spin @ S(0.76, stretch_y, 0.76) @ M_Y2Z):
            torus(mb, link_r, wire_r, segs, psegs, l_mat, l_col, False)


# ==============================================================================
# 1. PIRATE HARBOUR CLOCK BELLTOWER (pirate_harbour_clock_belltower.glb)
# ==============================================================================

def _build_tide_clock_face(mb, center, radius=0.76, face_z=-1.0):
    """Prominent circular gilded-brass harbour tide-and-compass clock face with glowing warm
    'glass' dial, 12 brass hour studs, sculpted iron hands & gilded tidal moon-phase discs!"""
    yaw = 0.0 if face_z < 0.0 else 180.0
    r = radius
    with xf(mb, T(center) @ R('Y', yaw)):
        with xf(mb, M_Y2Z):
            cyl(mb, r * 1.07, -0.06, 0.08, 10, 'iron', C_IRON_DARK, False, 0.0)
            # Glowing warm amber illuminated clock dial ('glass'!)
            cyl(mb, r * 0.94, -0.09, 0.02, 10, 'glass', C_DIAL_AMBER, False, 0.0)
            cyl(mb, r * 0.72, -0.10, 0.00, 10, 'glass', C_DIAL_CREAM, False, 0.0)
            with xf(mb, T(0.0, -0.09, 0.0)):
                torus(mb, r * 0.99, r * 0.11, 12, 4, 'brass', C_GOLD_BRIGHT, False)

        # 12 Brass/Iron Hour & Cardinal Compass-Point Marker Studs
        for hi in range(12):
            ang = radians(hi * 30.0)
            is_card = (hi % 3 == 0)
            mr = r * 0.80
            mx = mr * sin(ang)
            my = mr * cos(ang)
            with xf(mb, T(mx, my, -0.115) @ R('Z', -hi * 30.0)):
                if is_card:
                    cbox(mb, (0.0, 0.0, 0.0), (r * 0.085, r * 0.20, 0.045), 'brass', C_GOLD_BRIGHT, 0.0)
                    cbox(mb, (0.0, r * 0.34, 0.02), (r * 0.11, r * 0.16, 0.05), 'brass', C_BRASS_WARM, 0.0)
                else:
                    cbox(mb, (0.0, 0.0, 0.0), (r * 0.052, r * 0.11, 0.036), 'iron', C_IRON_FORGED, 0.0)

        # Tidal Moon-Phase Sub-Dial Window in Upper Quadrant (deep sea-teal sky + gilded moon discs!)
        with xf(mb, T(0.0, r * 0.31, -0.112) @ M_Y2Z):
            cyl(mb, r * 0.25, -0.012, 0.012, 6, 'paint', C_TEAL_DARK, False, 0.0)
        with xf(mb, T(r * 0.09, r * 0.34, -0.128) @ M_Y2Z):
            cyl(mb, r * 0.105, -0.012, 0.012, 5, 'brass', C_GOLD_BRIGHT, False, 0.0)
        with xf(mb, T(-r * 0.12, r * 0.29, -0.126) @ M_Y2Z):
            cyl(mb, r * 0.075, -0.010, 0.010, 5, 'brass', C_BRASS_WARM, False, 0.0)

        # Lower High/Low Tide Compass Indicator Bar
        cbox(mb, (0.0, -r * 0.36, -0.115), (r * 0.44, r * 0.09, 0.024), 'paint', C_TEAL_HI, 0.0)
        cbox(mb, (0.0, -r * 0.36, -0.126), (r * 0.12, r * 0.12, 0.026), 'brass', C_GOLD_BRIGHT, 0.0, M=R('Z', 45.0))

        # Sculpted Forged-Iron Clock Hands + Brass Pinion Boss
        with xf(mb, T(0.0, 0.0, -0.145) @ R('Z', -54.0)):
            cbox(mb, (0.0, r * 0.26, 0.0), (r * 0.056, r * 0.72, 0.030), 'iron', C_IRON_DARK, 0.0)
            cbox(mb, (0.0, r * 0.62, -0.005), (r * 0.11, r * 0.14, 0.034), 'iron', C_IRON_BRIGHT, 0.0, M=R('Z', 45.0))
        with xf(mb, T(0.0, 0.0, -0.168) @ R('Z', 58.0)):
            cbox(mb, (0.0, r * 0.18, 0.0), (r * 0.078, r * 0.50, 0.032), 'iron', C_IRON_DARK, 0.0)
            cbox(mb, (0.0, r * 0.42, -0.004), (r * 0.13, r * 0.14, 0.034), 'brass', C_GOLD_BRIGHT, 0.0, M=R('Z', 45.0))
        with xf(mb, T(0.0, 0.0, -0.175) @ M_Y2Z):
            cyl(mb, r * 0.12, -0.03, 0.03, 5, 'brass', C_GOLD_BRIGHT, False, 0.0, r * 0.07)


def gen_pirate_harbour_clock_belltower(outdir):
    """Tall ~6.8 m timber-and-stone harbour tide-clock & curfew belfry rooted on a stepped ashlar
    stone base plunging cleanly to y = -2.80 m (footprint hx=2.40 m, hz=2.40 m), weathered
    sandstone masonry pedestal, stout X-braced timber belfry tower housing prominent front & rear
    circular gilded-brass tide-and-compass clock faces (glowing warm amber 'glass' dial, iron
    hands & tidal moon discs!), suspended cast-bronze curfew bell in open louvered belfry stage,
    steeply pitched terracotta-shingle hip roof topped with copper weathervane spire & fluttering
    swallowtail harbour flag ('paint' + UV2), climbing coastal ivy ('foliage' + UV2), collider
    'col_clocktower_base', and warm illuminated belfry/clock lantern empty 'Lantern_TideClock'."""
    clear_scene()
    mb = MB('pirate_harbour_clock_belltower', seed=1801)
    rng = random.Random(SEED + 1801)
    col_pts = []

    DECK_Y = 0.62
    PED_TOP_Y = 2.22
    CLOCK_TOP_Y = 3.68
    BELFRY_TOP_Y = 4.78

    # 1. Stepped Sandstone Ashlar Base Plunging Cleanly to y = -2.80 m (footprint hx=2.40, hz=2.40)
    base_secs = [
        _rect_oct(0.0, -2.80, 0.0, 2.40, 2.40, 0.46),
        _rect_oct(0.0, -1.15, 0.0, 2.34, 2.34, 0.44),
        _rect_oct(0.0,  0.00, 0.0, 2.26, 2.26, 0.42),
        _rect_oct(0.0,  0.34, 0.0, 2.18, 2.18, 0.40),
    ]
    _loft_horizontal_masonry(
        mb, base_secs, 'temple_stone',
        [C_SANDSTONE_DEEP, C_SANDSTONE_DARK, C_SANDSTONE_MID, C_SANDSTONE_HI],
        rng, caps=(True, True), top_mat='limestone', top_col=C_SANDSTONE_HI,
    )

    curb_secs = [
        _rect_oct(0.0, 0.33, 0.0, 1.94, 1.94, 0.32),
        _rect_oct(0.0, DECK_Y, 0.0, 1.88, 1.88, 0.30),
    ]
    _loft_horizontal_masonry(
        mb, curb_secs, 'temple_stone',
        [C_SANDSTONE_MID, C_SANDSTONE_HI],
        rng, caps=(False, True), top_mat='limestone', top_col=C_SANDSTONE_HI,
    )

    for yc, hxy in ((-2.80, 2.38), (0.0, 2.24), (DECK_Y, 1.88), (PED_TOP_Y, 1.44), (BELFRY_TOP_Y, 1.24)):
        col_pts.extend(_rect_oct(0.0, yc, 0.0, hxy, hxy, 0.28))

    # Seaward (-Z) stone threshold steps + iron harbour mooring bollard & coiled rope on apron
    for si, (sy, sh, sz, sw) in enumerate((
        (0.14, 0.28, -2.26, 1.44),
        (0.42, 0.28, -1.96, 1.32),
    )):
        cbox(mb, (0.0, sy, sz), (sw, sh, 0.34), 'limestone',
             C_SANDSTONE_HI if si == 1 else C_SANDSTONE_MID, 0.0)

    with xf(mb, T(-1.44, DECK_Y, -1.44)):
        cyl(mb, 0.16, 0.0, 0.42, 6, 'iron', C_IRON_FORGED, False, 0.0, 0.13)
        cyl(mb, 0.19, 0.38, 0.46, 6, 'iron', C_IRON_BRIGHT, False, 0.0)
    _build_rope_coil_lean(mb, (1.44, DECK_Y, -1.40), radius=0.25, turns=2, r=0.034, segs=6, psegs=4)

    # 2. Weathered Sandstone Masonry Pedestal (y = 0.62 to 2.22 m)
    ped_secs = [
        _rect_oct(0.0, DECK_Y - 0.02,    0.0, 1.42, 1.42, 0.18),
        _rect_oct(0.0, 1.40,             0.0, 1.30, 1.30, 0.16),
        _rect_oct(0.0, PED_TOP_Y - 0.14, 0.0, 1.22, 1.22, 0.14),
    ]
    _loft_horizontal_masonry(
        mb, ped_secs, 'temple_stone',
        [C_SANDSTONE_DARK, C_SANDSTONE_MID, C_SANDSTONE_HI],
        rng, caps=(False, True), top_mat='limestone', top_col=C_SANDSTONE_HI,
    )
    cbox(mb, (0.0, PED_TOP_Y - 0.06, 0.0), (2.74, 0.20, 2.74), 'limestone', C_SANDSTONE_HI, 0.0)
    cbox(mb, (0.0, PED_TOP_Y - 0.20, 0.0), (2.56, 0.12, 2.56), 'temple_stone', C_SANDSTONE_MID, 0.0)

    # Alternating corner ashlar quoin stones
    for qy_i, qy in enumerate((0.88, 1.28, 1.66)):
        qx_w = 0.36 if qy_i % 2 == 0 else 0.26
        qz_w = 0.26 if qy_i % 2 == 0 else 0.36
        off_r = 1.24 - 0.06 * qy_i
        for sx in (-1.0, 1.0):
            for sz in (-1.0, 1.0):
                cbox(mb, (sx * off_r, qy, sz * off_r), (qx_w, 0.28, qz_w),
                     'limestone', jit(C_SANDSTONE_HI, rng, 0.04), 0.0)

    # Heavy Planked Oak Maintenance Door with Forged-Iron Hinges on Seaward (-Z) Pedestal Face
    with xf(mb, T(0.0, DECK_Y, -1.30)):
        cbox(mb, (0.0, 0.70, -0.04), (1.06, 1.40, 0.16), 'limestone', C_SANDSTONE_HI, 0.0)
        cbox(mb, (0.0, 0.66, -0.07), (0.78, 1.28, 0.12), 'timber', C_OAK_DEEP, 0.0)
        for hy in (0.34, 1.00):
            cbox(mb, (-0.12, hy, -0.14), (0.50, 0.075, 0.035), 'iron', C_IRON_FORGED, 0.0)
        with xf(mb, T(0.24, 0.66, -0.15) @ M_Y2Z):
            torus(mb, 0.065, 0.018, 5, 4, 'brass', C_GOLD_BRIGHT, False)

    # Rear (+Z) Arched Stone Window Niche with Warm Slit Glow & Iron Bars
    with xf(mb, T(0.0, DECK_Y + 0.80, 1.28)):
        cbox(mb, (0.0, 0.0, 0.04), (0.76, 0.90, 0.14), 'limestone', C_SANDSTONE_HI, 0.0)
        cbox(mb, (0.0, 0.0, 0.08), (0.50, 0.64, 0.08), 'glass', C_DIAL_AMBER, 0.0)
        for bx in (-0.12, 0.12):
            cbox(mb, (bx, 0.0, 0.12), (0.035, 0.66, 0.035), 'iron', C_IRON_DARK, 0.0)
        cbox(mb, (0.0, 0.0, 0.12), (0.52, 0.04, 0.04), 'iron', C_IRON_DARK, 0.0)

    # 3. Stout X-Braced Timber Belfry Tower (y = 2.22 to 4.78 m)
    POST_OFF = 1.04
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            px, pz = sx * POST_OFF, sz * POST_OFF
            cbox(mb, (px, 0.5 * (PED_TOP_Y + BELFRY_TOP_Y), pz),
                 (0.22, BELFRY_TOP_Y - PED_TOP_Y + 0.08, 0.22), 'timber', C_OAK_DEEP, 0.0)
            for sy_b in (PED_TOP_Y + 0.12, CLOCK_TOP_Y, BELFRY_TOP_Y - 0.10):
                cbox(mb, (px, sy_b, pz), (0.25, 0.09, 0.25), 'iron', C_IRON_FORGED, 0.0)

    for ry, rh, rcol in (
        (PED_TOP_Y + 0.08,    0.18, C_OAK_DEEP),
        (CLOCK_TOP_Y,         0.20, C_OAK_SUN),
        (BELFRY_TOP_Y - 0.06, 0.20, C_OAK_DEEP),
    ):
        for sz in (-POST_OFF, POST_OFF):
            _add_beam(mb, (-POST_OFF, ry, sz), (POST_OFF, ry, sz), 0.18, rh, 'timber', rcol, 0.0)
        for sx in (-POST_OFF, POST_OFF):
            _add_beam(mb, (sx, ry, -POST_OFF), (sx, ry, POST_OFF), 0.18, rh, 'timber', rcol, 0.0)

    cbox(mb, (0.0, 2.96, 0.0), (1.84, 1.34, 1.84), 'timber', C_OAK_RICH, 0.0)
    for sx in (-1.0, 1.0):
        cbox(mb, (sx * 0.94, 2.96, 0.0), (0.06, 1.16, 1.56), 'paint', C_TEAL_MID, 0.0)

    # Bold Diagonal Timber X-Bracing on Port (-X) and Starboard (+X) Clock Stage Flanks
    for sx in (-1.0, 1.0):
        bx = sx * POST_OFF
        _add_beam(mb, (bx, PED_TOP_Y + 0.16, -POST_OFF + 0.08), (bx, CLOCK_TOP_Y - 0.10, POST_OFF - 0.08),
                  0.11, 0.12, 'timber', C_OAK_SUN, 0.0)
        _add_beam(mb, (bx, PED_TOP_Y + 0.16,  POST_OFF - 0.08), (bx, CLOCK_TOP_Y - 0.10, -POST_OFF + 0.08),
                  0.11, 0.12, 'timber', C_OAK_SUN, 0.0)
        cbox(mb, (bx + sx * 0.07, 2.96, 0.0), (0.08, 0.22, 0.22), 'brass', C_GOLD_BRIGHT, 0.0, M=R('X', 45.0))

    # 4. Prominent Circular Gilded-Brass Harbour Tide-and-Compass Clock Faces (Front -Z & Rear +Z!)
    _build_tide_clock_face(mb, (0.0, 2.98, -0.96), radius=0.76, face_z=-1.0)
    _build_tide_clock_face(mb, (0.0, 2.98,  0.96), radius=0.70, face_z= 1.0)

    # 5. Open Louvered Belfry Stage (y = 3.68 to 4.78 m) & Prominently Suspended Cast-Bronze Curfew Bell!
    cbox(mb, (0.0, CLOCK_TOP_Y + 0.05, 0.0), (2.18, 0.10, 2.18), 'timber', C_OAK_DEEP, 0.0)
    # Single crisp slatted timber louver apron around lower belfry sill so full bronze bell shines clearly!
    for sz in (-POST_OFF, POST_OFF):
        cbox(mb, (0.0, CLOCK_TOP_Y + 0.18, sz), (1.88, 0.06, 0.18), 'timber', C_OAK_SUN, 0.0, M=R('X', 28.0 if sz < 0 else -28.0))
    for sx in (-POST_OFF, POST_OFF):
        cbox(mb, (sx, CLOCK_TOP_Y + 0.18, 0.0), (0.18, 0.06, 1.88), 'timber', C_OAK_SUN, 0.0, M=R('Z', -28.0 if sx < 0 else 28.0))

    # Corner angled timber knee-braces framing all 4 open belfry arches
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            _add_beam(mb, (sx * POST_OFF, BELFRY_TOP_Y - 0.42, sz * POST_OFF),
                      (sx * (POST_OFF - 0.38), BELFRY_TOP_Y - 0.08, sz * POST_OFF), 0.085, 0.095, 'timber', C_OAK_SUN, 0.0)
            _add_beam(mb, (sx * POST_OFF, BELFRY_TOP_Y - 0.42, sz * POST_OFF),
                      (sx * POST_OFF, BELFRY_TOP_Y - 0.08, sz * (POST_OFF - 0.38)), 0.085, 0.095, 'timber', C_OAK_SUN, 0.0)

    # Transverse Oak Bell Headstock Beam + Ringing Wheel + Hemp Bell-Pull Rope
    BELL_AXLE_Y = 4.56
    _add_beam(mb, (-POST_OFF, BELL_AXLE_Y, 0.0), (POST_OFF, BELL_AXLE_Y, 0.0), 0.16, 0.18, 'timber', C_OAK_DEEP, 0.0)
    cbox(mb, (0.0, BELL_AXLE_Y, 0.0), (0.56, 0.24, 0.28), 'timber', C_OAK_RICH, 0.0)
    for sx in (-0.24, 0.24):
        cbox(mb, (sx, BELL_AXLE_Y, 0.0), (0.06, 0.28, 0.32), 'iron', C_IRON_FORGED, 0.0)
    with xf(mb, T(0.62, BELL_AXLE_Y, 0.0) @ M_Y2X):
        torus(mb, 0.34, 0.032, 8, 4, 'timber', C_OAK_SUN, False)
        for sp_a in (0.0, 90.0):
            with xf(mb, R('Y', sp_a)):
                cbox(mb, (0.0, 0.0, 0.0), (0.66, 0.036, 0.044), 'timber', C_OAK_DEEP, 0.0)
    tube(mb, [(0.62, BELL_AXLE_Y - 0.32, 0.24), (0.64, 3.78, 0.22)], 0.024, 4, 'rope', C_ROPE, mode='flat')

    # Sculpted Cast-Bronze Curfew Bell proudly showcased inside the wide-open belfry! (y = 3.86 to 4.52 m)
    with xf(mb, T(0.0, 3.86, 0.0)):
        bell_prof = [
            (0.00, 0.48),
            (0.15, 0.46),
            (0.22, 0.22),
            (0.34, 0.00),
            (0.41, 0.00),
            (0.43, 0.06),
            (0.31, 0.20),
            (0.25, 0.46),
            (0.18, 0.58),
            (0.08, 0.64),
            (0.00, 0.64),
        ]
        lathe(mb, bell_prof, 8, 'brass', C_BRONZE_BELL, False, False,
              lambda i, k: C_BRONZE_DARK if i <= 3 else (C_GOLD_BRIGHT if i in (4, 7) else C_BRONZE_BELL))
        cyl(mb, 0.38, 0.07, 0.12, 8, 'brass', C_GOLD_BRIGHT, False, 0.0)
        cyl(mb, 0.028, 0.00, 0.46, 5, 'iron', C_IRON_DARK, False, 0.0)
        lathe(mb, [(0.0, -0.07), (0.09, 0.00), (0.0, 0.08)], 5, 'iron', C_IRON_BRIGHT, False)

    # Warm Illuminated Belfry/Clock Harbour Lantern mounted off seaward-starboard belfry post so bell is 100% unobstructed!
    LANTERN_POS = Vector((0.56, 4.18, -1.26))
    _add_beam(mb, (0.56, BELFRY_TOP_Y - 0.14, -POST_OFF), (0.56, BELFRY_TOP_Y - 0.14, -1.34),
              0.062, 0.072, 'iron', C_IRON_FORGED, 0.0)
    _add_beam(mb, (0.56, BELFRY_TOP_Y - 0.42, -POST_OFF), (0.56, BELFRY_TOP_Y - 0.14, -1.26),
              0.046, 0.050, 'iron', C_IRON_BRIGHT, 0.0)
    _add_beam(mb, (0.56, BELFRY_TOP_Y - 0.14, -1.26), LANTERN_POS + Vector((0.0, 0.28, 0.0)),
              0.026, 0.026, 'iron', C_IRON_FORGED, 0.0)
    _build_storm_lantern(mb, LANTERN_POS, scale=0.86, brass_cage=True, hanging=True)

    # 6. Steeply Pitched Terracotta-Shingle Hip Roof (y = 4.74 to 5.98 m)
    roof_tiers = [
        (1.64, 4.74, C_TERRA_DARK),
        (1.22, 5.10, C_TERRA_HI),
        (0.78, 5.48, C_TERRA_MID),
        (0.34, 5.82, C_TERRA_HI),
        (0.14, 5.98, C_TERRA_DARK),
    ]
    roof_secs = [_rect_oct(0.0, ry, 0.0, rh, rh, rh * 0.14) for rh, ry, _ in roof_tiers]
    roof_cols = [rc for _, _, rc in roof_tiers]
    loft(mb, roof_secs, 'paint', C_TERRA_MID, closed=True, caps=(False, True), mode='flat', scols=roof_cols)
    cbox(mb, (0.0, 4.72, 0.0), (2.96, 0.10, 2.96), 'timber', C_OAK_DEEP, 0.0)

    # Proud Dark Oak Hip-Rafter Ribs + brass corner eave finials
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            rib_pts = [
                Vector((sx * 1.56, 4.78, sz * 1.56)),
                Vector((sx * 0.78, 5.50, sz * 0.78)),
                Vector((sx * 0.14, 6.00, sz * 0.14)),
            ]
            tube(mb, rib_pts, [0.075, 0.056, 0.040], 4, 'timber', C_OAK_DEEP, mode='flat')
            cbox(mb, (sx * 1.58, 4.72, sz * 1.58), (0.12, 0.12, 0.12), 'brass', C_GOLD_BRIGHT, 0.0)

    # Decorative Gabled Terracotta Dormer Hood projecting over the front seaward tide-clock eaves
    with xf(mb, T(0.0, 4.82, -1.36)):
        cbox(mb, (0.0, -0.02, 0.0), (0.94, 0.10, 0.42), 'timber', C_OAK_SUN, 0.0)
        for sgn in (-1.0, 1.0):
            _add_beam(mb, (sgn * 0.50, 0.02, -0.14), (0.0, 0.42, -0.14), 0.10, 0.24, 'paint', C_TERRA_HI, 0.0)
        cbox(mb, (0.0, 0.46, -0.14), (0.14, 0.18, 0.14), 'brass', C_GOLD_BRIGHT, 0.0)

    # 7. Copper/Verdigris Weathervane Spire & Fluttering Swallowtail Harbour Flag (y = 5.96 to 6.86 m!)
    cyl(mb, 0.22, 5.94, 6.08, 6, 'brass', C_VERDIGRIS_MID, False, 0.0, 0.14)
    lathe(mb, [(0.0, 6.06), (0.18, 6.18), (0.18, 6.28), (0.0, 6.40)], 6, 'brass', C_VERDIGRIS_HI, False, False,
          lambda i, k: C_GOLD_BRIGHT if i == 1 else C_VERDIGRIS_HI)
    cyl(mb, 0.036, 6.36, 6.86, 5, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.022)
    for k in range(4):
        with xf(mb, T(0.0, 6.50, 0.0) @ R('Y', k * 90.0)):
            _add_beam(mb, (0.0, 0.0, 0.0), (0.0, 0.0, -0.46), 0.026, 0.026, 'brass', C_VERDIGRIS_HI, 0.0)
            cbox(mb, (0.0, 0.0, -0.48), (0.075, 0.075, 0.075), 'brass', C_GOLD_BRIGHT, 0.0, M=R('Y', 45.0))
    with xf(mb, T(0.0, 6.76, 0.0) @ R('Y', 32.0)):
        _add_beam(mb, (0.0, 0.0, 0.36), (0.0, 0.0, -0.46), 0.028, 0.028, 'brass', C_GOLD_BRIGHT, 0.0)
        with xf(mb, T(0.0, 0.0, -0.46) @ R('X', -90.0)):
            cyl(mb, 0.075, 0.0, 0.16, 4, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.010)
        cbox(mb, (0.0, 0.0, 0.34), (0.025, 0.18, 0.22), 'brass', C_VERDIGRIS_HI, 0.0)

    _build_wind_pennant(
        mb, root_pos=(0.03, 6.60, 0.0), length=1.36, h0=0.38,
        out_dir=(0.94, -0.04, -0.34),
        col_main=C_TEAL_HI, col_alt=C_CRIMSON_HI, col_trim=C_GOLD_BRIGHT, phase=0.26,
    )

    # 8. Climbing Coastal Ivy ('foliage' + UV2!) hugging outer stone & timber corners cleanly + base ferns!
    _add_climbing_ivy_corner(mb, (-1.34, -1.34), (-0.7, 0.0, -0.7), DECK_Y + 0.04, 3.68, rng=rng, phase=0.18, segs=5)
    _add_climbing_ivy_corner(mb, ( 1.34,  1.34), ( 0.7, 0.0,  0.7), DECK_Y + 0.04, 3.56, rng=rng, phase=0.64, segs=5)
    for fpos, fsc, flean, fph in (
        ((-1.82, 0.36, -1.68), 0.72, (-0.7, 0.0, -0.7), 0.14),
        (( 1.84, 0.36, -1.64), 0.70, ( 0.7, 0.0, -0.7), 0.42),
        ((-1.84, 0.36,  1.66), 0.74, (-0.7, 0.0,  0.7), 0.71),
        (( 1.82, 0.36,  1.68), 0.70, ( 0.7, 0.0,  0.7), 0.93),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=4, rng=rng, phase=fph, lean_dir=flean, segs=2)

    build(mb)

    add_empty('Lantern_TideClock', LANTERN_POS)
    col_piece('col_clocktower_base', col_pts)
    export_landmark_glb(outdir, 'pirate_harbour_clock_belltower.glb')


# ==============================================================================
# 2. ANCIENT CELESTIAL MOON DIAL (ancient_celestial_moon_dial.glb)
# ==============================================================================

def _build_rune_obelisk(mb, base_pos, height=2.85, base_r=0.38, yaw_deg=0.0, tilt_z=0.0, rng=None):
    """Carved Mesoamerican temple-stone lunar obelisk with gilded brass pyramidion & glowing
    turquoise aqua rune inlays ('skull_glow') on front & rear faces!"""
    with xf(mb, T(base_pos) @ R('Y', yaw_deg) @ R('Z', tilt_z)):
        cbox(mb, (0.0, 0.16, 0.0), (base_r * 2.30, 0.32, base_r * 2.30), 'temple_stone', C_MOON_STONE_DK, 0.0)
        cbox(mb, (0.0, 0.36, 0.0), (base_r * 1.96, 0.12, base_r * 1.96), 'limestone_moss', C_MOON_STONE_MID, 0.0)
        sh_top = height - 0.50
        secs = [
            _rect_oct(0.0, 0.40,          0.0, base_r * 0.86, base_r * 0.86, base_r * 0.18),
            _rect_oct(0.0, sh_top * 0.55, 0.0, base_r * 0.72, base_r * 0.72, base_r * 0.15),
            _rect_oct(0.0, sh_top,        0.0, base_r * 0.54, base_r * 0.54, base_r * 0.12),
        ]
        _loft_horizontal_masonry(mb, secs, 'temple_stone',
                                 [C_MOON_STONE_DK, C_MOON_STONE_MID, C_MOON_STONE_HI], rng, caps=(False, True))
        cbox(mb, (0.0, sh_top - 0.06, 0.0), (base_r * 1.24, 0.11, base_r * 1.24), 'brass', C_GOLD_BRIGHT, 0.0)
        with xf(mb, T(0.0, sh_top, 0.0) @ R('Y', 45.0)):
            lathe(mb, [(0.0, 0.0), (base_r * 0.74, 0.02), (base_r * 0.42, 0.28), (0.0, 0.54)],
                  4, 'brass', C_BRASS_WARM, False, False,
                  lambda i, k: C_GOLD_BRIGHT if i >= 1 else C_BRASS_DARK)

        # Glowing Turquoise Aqua Rune Inlays ('skull_glow'!) etched vertically on BOTH front & rear faces!
        for z_sgn in (-1.0, 1.0):
            r_z = z_sgn * (base_r * 0.68)
            _add_beam(mb, (0.0, 0.62, r_z), (0.0, sh_top - 0.26, z_sgn * (base_r * 0.54)),
                      0.062, 0.056, 'skull_glow', C_AQUA_DEEP, 0.0)
            for frac, ds in ((0.28, 0.13), (0.55, 0.15), (0.80, 0.11)):
                gy = 0.46 + (sh_top - 0.62) * frac
                gz = z_sgn * (base_r * (0.76 - 0.22 * frac))
                cbox(mb, (0.0, gy, gz), (ds, ds, 0.06), 'skull_glow', C_AQUA_MID, 0.0, M=R('Z', 45.0))


def gen_ancient_celestial_moon_dial(outdir):
    """Mystical sunken-civilization lunar tide-altar rooted on a carved octagonal mossy reef
    terrace plunging cleanly to y = -3.40 m (radius ~2.55 m), concentric stepped temple-stone
    zodiac dial dais supporting a soaring inclined stone-and-brass crescent lunar arch (~5.8 m
    tall) framing gilded intersecting orbital gimbal rings cradling a levitating luminous
    turquoise moonstone orb ('skull_glow'!), twin flanking carved rune obelisks with aqua rune
    inlays, trailing jungle vines & ferns ('foliage' + UV2), collider 'col_moondial_base', and
    'Lantern_MoonDial' empty right at the levitating moonstone orb."""
    clear_scene()
    mb = MB('ancient_celestial_moon_dial', seed=1802)
    rng = random.Random(SEED + 1802)
    col_pts = []

    TERRACE_Y = 0.34
    DAIS_Y = 0.90

    # Inclined Celestial Meridian Frame: pivots smoothly around (0, DAIS_Y, 0) by +8 deg back around X!
    ARCH_TILT = T(0.0, DAIS_Y, 0.0) @ R('X', 8.0) @ T(0.0, -DAIS_Y, 0.0)
    # World-space exact center of the levitating moonstone orb & orbital gimbal rings (zero offset from arch pins!)
    ORB_LOCAL = Vector((0.0, 3.24, 0.0))
    ORB_C = ARCH_TILT @ ORB_LOCAL

    # 1. Carved Octagonal Mossy Reef Terrace Plunging Cleanly to y = -3.40 m (radius ~2.55 m)
    reef_secs = [
        _reg_poly(0.0, -3.40, 0.0, 2.55, sides=8, rot_deg=22.5),
        _reg_poly(0.0, -1.45, 0.0, 2.50, sides=8, rot_deg=22.5),
        _reg_poly(0.0,  0.00, 0.0, 2.42, sides=8, rot_deg=22.5),
        _reg_poly(0.0, TERRACE_Y, 0.0, 2.36, sides=8, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, reef_secs, 'limestone_moss',
        [C_MOON_STONE_SK, C_MOON_STONE_DK, C_MOON_STONE_MID, C_MOON_STONE_HI],
        rng, caps=(True, True), top_mat='limestone_moss', top_col=C_MOON_STONE_MID,
    )

    for yc, rc in ((-3.40, 2.54), (0.0, 2.42), (DAIS_Y, 2.18), (4.85, 1.85)):
        col_pts.extend(_reg_poly(0.0, yc, 0.0, rc, sides=8, rot_deg=22.5))

    # Ceremonial Seaward (-Z) & Rear (+Z) Carved Stone Steps leading onto the Lunar Dais
    for z_sgn in (-1.0, 1.0):
        cbox(mb, (0.0, 0.18, z_sgn * 2.28), (1.36, 0.32, 0.36), 'temple_stone', C_MOON_STONE_MID, 0.0)
        cbox(mb, (0.0, 0.46, z_sgn * 1.98), (1.20, 0.28, 0.34), 'temple_stone', C_MOON_STONE_HI, 0.0)
        cbox(mb, (0.0, 0.72, z_sgn * 1.66), (1.06, 0.24, 0.32), 'temple_stone', C_MOON_STONE_HI, 0.0)
        for sx in (-1.0, 1.0):
            cbox(mb, (sx * 0.72, 0.42, z_sgn * 1.98), (0.20, 0.62, 0.72), 'temple_stone', C_MOON_STONE_DK, 0.0)

    # 2. Concentric Stepped Temple-Stone Zodiac Dial Dais (y = 0.34 to 0.90 m)
    dais_t1 = [
        _reg_poly(0.0, TERRACE_Y - 0.02, 0.0, 2.02, sides=12, rot_deg=15.0),
        _reg_poly(0.0, 0.62,             0.0, 1.94, sides=12, rot_deg=15.0),
    ]
    _loft_horizontal_masonry(mb, dais_t1, 'temple_stone', [C_MOON_STONE_DK, C_MOON_STONE_MID],
                             rng, caps=(False, True), top_mat='limestone_moss', top_col=C_MOON_STONE_MID)

    dais_t2 = [
        _reg_poly(0.0, 0.60,   0.0, 1.56, sides=12, rot_deg=15.0),
        _reg_poly(0.0, DAIS_Y, 0.0, 1.48, sides=12, rot_deg=15.0),
    ]
    _loft_horizontal_masonry(mb, dais_t2, 'temple_stone', [C_MOON_STONE_MID, C_MOON_STONE_HI],
                             rng, caps=(False, True), top_mat='temple_stone', top_col=C_MOON_STONE_HI)

    # Embedded Gilded-Brass Zodiac Dial Ring, Slate Moon-Basin Floor & 12 Zodiac Marker Ticks
    cyl(mb, 1.32, DAIS_Y - 0.01, DAIS_Y + 0.024, 12, 'temple_stone', C_SLATE_BLUE, False, 0.0)
    with xf(mb, T(0.0, DAIS_Y + 0.032, 0.0)):
        torus(mb, 1.36, 0.048, 16, 4, 'brass', C_GOLD_BRIGHT, False)
        torus(mb, 0.96, 0.032, 12, 4, 'brass', C_BRASS_WARM, False)
    for zi in range(12):
        ang = radians(zi * 30.0)
        is_card = (zi % 3 == 0)
        rx = 1.16 * cos(ang)
        rz = 1.16 * sin(ang)
        with xf(mb, T(rx, DAIS_Y + 0.038, rz) @ R('Y', -zi * 30.0)):
            if is_card:
                cbox(mb, (0.0, 0.0, 0.0), (0.34, 0.04, 0.10), 'skull_glow', C_AQUA_MID, 0.0)
            else:
                cbox(mb, (0.0, 0.0, 0.0), (0.24, 0.035, 0.065), 'brass', C_GOLD_BRIGHT, 0.0)

    # Central Carved Stone Lunar Altar Pedestal positioned cleanly beneath the Levitating Orb (y = 0.90 to 1.94 m)
    with xf(mb, T(0.0, DAIS_Y, ORB_C.z * 0.45)):
        cyl(mb, 0.62, 0.00, 0.24, 8, 'temple_stone', C_MOON_STONE_DK, False, 0.0, 0.54)
        cyl(mb, 0.44, 0.24, 0.80, 8, 'temple_stone', C_MOON_STONE_MID, False, 0.0, 0.36)
        cyl(mb, 0.52, 0.78, 0.96, 8, 'temple_stone', C_MOON_STONE_HI, False, 0.0, 0.58)
        cyl(mb, 0.56, 0.94, 1.00, 8, 'brass', C_GOLD_BRIGHT, False, 0.0)
        cyl(mb, 0.42, 0.99, 1.04, 8, 'skull_glow', C_AQUA_MID, False, 0.0)
        for z_sgn in (-1.0, 1.0):
            cbox(mb, (0.0, 0.52, z_sgn * 0.41), (0.14, 0.38, 0.07), 'skull_glow', C_AQUA_MID, 0.0)
            cbox(mb, (0.0, 0.52, z_sgn * 0.44), (0.24, 0.10, 0.05), 'brass', C_GOLD_BRIGHT, 0.0)

    # 3. Soaring Inclined Stone-and-Brass Crescent Lunar Arch (~5.86 m tall!) — ZERO GAP INTO PIERS!
    with xf(mb, ARCH_TILT):
        # Twin massive carved stone arch buttress piers rising cleanly to y = 2.38 m to cradle the arch springers!
        for sgn in (-1.0, 1.0):
            b_secs = [
                _rect_oct(sgn * 1.66, TERRACE_Y - 0.12, 0.0, 0.58, 0.60, 0.12),
                _rect_oct(sgn * 1.56, 1.48,             0.0, 0.52, 0.54, 0.11),
                _rect_oct(sgn * 1.48, 2.32,             0.0, 0.48, 0.50, 0.10),
            ]
            _loft_horizontal_masonry(mb, b_secs, 'temple_stone',
                                     [C_MOON_STONE_DK, C_MOON_STONE_MID, C_MOON_STONE_HI], rng, caps=(False, True))
            # Sculpted stepped stone-and-brass springer capital locking arch cleanly into the pier!
            cbox(mb, (sgn * 1.48, 2.36, 0.0), (1.06, 0.18, 1.04), 'temple_stone', C_MOON_STONE_HI, 0.0)
            cbox(mb, (sgn * 1.48, 2.24, 0.0), (1.02, 0.10, 1.00), 'brass', C_GOLD_BRIGHT, 0.0)
            cbox(mb, (sgn * 1.58, 1.48, 0.0), (1.06, 0.11, 1.08), 'brass', C_BRASS_WARM, 0.0)
            for z_sgn in (-1.0, 1.0):
                cbox(mb, (sgn * 1.54, 1.84, z_sgn * 0.50), (0.18, 0.24, 0.07),
                     'skull_glow', C_AQUA_MID, 0.0, M=R('Z', 45.0))

        # Sweeping Soaring Stone Crescent Arch Spine spanning theta = -124 deg to +124 deg so BOTH ends
        # plunge deeply (~0.45 m!) into the solid springer capitals at y = 2.36 m -> 100% seamless joint!
        arch_n = 14
        arch_center_y = 3.24
        rx_in, ry_in = 1.38, 1.64
        arch_secs = []
        arch_cols = []
        inner_rail_pts = []
        outer_crest_pts = []
        for i in range(arch_n + 1):
            t = i / float(arch_n)
            ang = radians(-124.0 + 248.0 * t)
            ca, sa = cos(ang), sin(ang)
            thick = 0.52 + 0.30 * (max(0.0, cos(ang * 0.72)) ** 2)
            depth = 0.44 - 0.08 * abs(t - 0.5)
            p_in = Vector((rx_in * sa, arch_center_y + ry_in * ca, 0.0))
            out_dir = Vector((sa, ca * 1.12, 0.0)).normalized()
            p_out = p_in + out_dir * thick
            p_mid = (p_in + p_out) * 0.5
            sec = [
                p_in  + Vector((0.0, 0.0, -depth * 0.72)),
                p_mid + Vector((0.0, 0.0, -depth)),
                p_out + Vector((0.0, 0.0, -depth * 0.65)),
                p_out + Vector((0.0, 0.0,  depth * 0.65)),
                p_mid + Vector((0.0, 0.0,  depth)),
                p_in  + Vector((0.0, 0.0,  depth * 0.72)),
            ]
            arch_secs.append(sec)
            arch_cols.append(C_MOON_STONE_HI if abs(t - 0.5) < 0.30 else C_MOON_STONE_MID)
            inner_rail_pts.append(p_in - out_dir * 0.03)
            outer_crest_pts.append(p_out + out_dir * 0.03)

        loft(mb, arch_secs, 'temple_stone', C_MOON_STONE_HI, closed=True, caps=(True, True), mode='flat', scols=arch_cols)

        # Gleaming Gilded-Brass Inner Meridian Arc Rail + Outer Crescent Rim Trim
        tube(mb, inner_rail_pts, 0.068, 6, 'brass', C_GOLD_BRIGHT, mode='flat')
        tube(mb, outer_crest_pts, 0.052, 5, 'brass', C_BRASS_WARM, mode='flat')

        # Glowing Turquoise Lunar Phase Runes studded cleanly along BOTH seaward (-Z) & rear (+Z) arch faces
        for i in range(2, arch_n - 1, 2):
            t = i / float(arch_n)
            ang = radians(-124.0 + 248.0 * t)
            ca, sa = cos(ang), sin(ang)
            out_dir = Vector((sa, ca * 1.12, 0.0)).normalized()
            p_m = Vector((rx_in * sa, arch_center_y + ry_in * ca, 0.0)) + out_dir * 0.34
            for z_sgn in (-1.0, 1.0):
                cbox(mb, (p_m.x, p_m.y, z_sgn * 0.40), (0.14, 0.14, 0.08),
                     'skull_glow', C_AQUA_CORE if i == arch_n // 2 else C_AQUA_MID, 0.0, M=R('Z', 45.0))

        # Sculpted Stone & Gilded-Brass Crescent Moon Crown Finial atop Arch Apex (y ~ 5.88 m!)
        CROWN_Y = 5.58
        cbox(mb, (0.0, CROWN_Y - 0.06, 0.0), (0.78, 0.24, 0.56), 'temple_stone', C_MOON_STONE_HI, 0.0)
        for sgn in (-1.0, 1.0):
            horn_pts = [
                Vector((0.0,        CROWN_Y - 0.06, 0.0)),
                Vector((sgn * 0.38, CROWN_Y + 0.02, 0.0)),
                Vector((sgn * 0.66, CROWN_Y + 0.22, 0.0)),
                Vector((sgn * 0.58, CROWN_Y + 0.48, 0.0)),
            ]
            tube(mb, horn_pts, [0.115, 0.092, 0.064, 0.016], 5, 'brass', C_GOLD_BRIGHT, mode='flat')
        cbox(mb, (0.0, CROWN_Y + 0.26, 0.0), (0.20, 0.24, 0.14), 'skull_glow', C_AQUA_CORE, 0.0, M=R('Z', 45.0))

        # Slender Gilded-Brass Meridian Pivot Struts linking arch shoulders DEAD-CENTER into the outer gimbal ring!
        for sgn in (-1.0, 1.0):
            _add_beam(mb, (sgn * 1.40, ORB_LOCAL.y, 0.0), (sgn * 0.96, ORB_LOCAL.y, 0.0),
                      0.052, 0.052, 'brass', C_GOLD_BRIGHT, 0.0)
            cbox(mb, (sgn * 1.18, ORB_LOCAL.y, 0.0), (0.13, 0.13, 0.13), 'brass', C_BRASS_WARM, 0.0, M=R('Z', 45.0))

        # 4. Gilded Intersecting Orbital Gimbal Rings Cradling Levitating Luminous Turquoise Moonstone Orb!
        # Authored inside ARCH_TILT at ORB_LOCAL so gimbal rings align 100% flush with the pivot struts!
        with xf(mb, T(ORB_LOCAL)):
            # Outer Meridian Gimbal Ring (R = 0.98 m, lying cleanly in the tilted arch plane!)
            with xf(mb, M_Y2Z):
                torus(mb, 0.98, 0.046, 16, 4, 'brass', C_GOLD_BRIGHT, False)
                for k in range(4):
                    ang = k * pi * 0.5
                    cbox(mb, (0.98 * cos(ang), 0.0, 0.98 * sin(ang)), (0.12, 0.12, 0.12), 'brass', C_BRASS_WARM, 0.0)
            # Middle Oblique Ecliptic Ring (R = 0.78 m)
            with xf(mb, R('Z', -34.0) @ R('X', 58.0)):
                torus(mb, 0.78, 0.038, 14, 4, 'brass', C_BRASS_WARM, False)
                for sx in (-0.78, 0.78):
                    cbox(mb, (sx, 0.0, 0.0), (0.095, 0.095, 0.095), 'skull_glow', C_AQUA_MID, 0.0)
            # Inner Precessing Lunar Ring (R = 0.58 m)
            with xf(mb, R('Y', 42.0) @ R('X', -34.0) @ M_Y2Z):
                torus(mb, 0.58, 0.030, 12, 4, 'brass', C_GOLD_BRIGHT, False)

            # Levitating Luminous Turquoise Moonstone Orb ('skull_glow'!) right at the gimbal heart!
            orb_prof = [
                (0.00, -0.35),
                (0.18, -0.30),
                (0.32, -0.14),
                (0.35,  0.00),
                (0.32,  0.14),
                (0.18,  0.30),
                (0.00,  0.35),
            ]
            lathe(mb, orb_prof, 10, 'skull_glow', C_AQUA_MID, False, False,
                  lambda i, k: C_AQUA_CORE if i in (2, 3) else C_AQUA_MID)
            with xf(mb, R('Z', -18.0)):
                torus(mb, 0.40, 0.022, 10, 4, 'brass', C_GOLD_BRIGHT, False)
            for mx, my, mz in ((-0.47, 0.21, -0.16), (0.49, -0.19, 0.15)):
                cbox(mb, (mx, my, mz), (0.10, 0.14, 0.10), 'skull_glow', C_AQUA_CORE, 0.0, M=R('Z', 35.0) @ R('Y', 45.0))

    # 5. Twin Flanking Carved Rune Obelisks with Aqua Rune Inlays + Rear Companion Stele
    _build_rune_obelisk(mb, (-1.86, TERRACE_Y - 0.02, -0.84), height=2.92, base_r=0.36, yaw_deg=-26.0, tilt_z= 2.2, rng=rng)
    _build_rune_obelisk(mb, ( 1.88, TERRACE_Y - 0.02, -0.78), height=2.66, base_r=0.34, yaw_deg= 28.0, tilt_z=-2.5, rng=rng)
    _build_rune_obelisk(mb, ( 1.62, TERRACE_Y - 0.02,  1.28), height=1.96, base_r=0.30, yaw_deg=142.0, tilt_z= 3.0, rng=rng)

    sculpt_stone_block(mb, (-1.64, TERRACE_Y + 0.18, 1.24), (0.64, 0.42, 0.56), 'limestone_moss',
                       C_MOON_STONE_MID, rng, chip=0.04, M=R('Y', 24.0), moss_col=C_LEDGE_MOSS)

    # 6. Trailing Jungle Vines & Tropical Reef Ferns ('foliage' + UV2!)
    for v_anc, v_len, v_w, v_dir, v_ph in (
        ((-1.62, 4.18,  0.14), 1.85, 0.15, (-0.7, 0.0, -0.7), 0.14),
        (( 1.64, 4.10,  0.14), 1.72, 0.15, ( 0.7, 0.0, -0.7), 0.39),
        ((-1.26, 4.86,  0.62), 1.48, 0.14, (-0.4, 0.0,  0.9), 0.63),
        (( 1.28, 4.84,  0.64), 1.56, 0.14, ( 0.4, 0.0,  0.9), 0.85),
        ((-1.86, 2.52, -0.96), 1.18, 0.13, (-0.6, 0.0, -0.8), 0.28),
        (( 1.88, 2.30, -0.90), 1.10, 0.13, ( 0.6, 0.0, -0.8), 0.72),
    ):
        _add_leafy_vine_drape(mb, v_anc, v_len, v_w, v_dir, rng, phase=v_ph)

    for fpos, fsc, flean, fph in (
        ((-1.94, TERRACE_Y + 0.02, -1.32), 0.78, (-0.7, 0.0, -0.7), 0.11),
        (( 1.96, TERRACE_Y + 0.02, -1.26), 0.76, ( 0.7, 0.0, -0.7), 0.37),
        ((-2.02, TERRACE_Y + 0.02,  1.06), 0.80, (-0.8, 0.0,  0.6), 0.61),
        (( 1.98, TERRACE_Y + 0.02,  1.12), 0.76, ( 0.8, 0.0,  0.6), 0.88),
        ((-1.56, 0.62,  0.04),             0.64, (-1.0, 0.0,  0.0), 0.49),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=4, rng=rng, phase=fph, lean_dir=flean, segs=3)

    build(mb)

    add_empty('Lantern_MoonDial', ORB_C)
    col_piece('col_moondial_base', col_pts)
    export_landmark_glb(outdir, 'ancient_celestial_moon_dial.glb')


# ==============================================================================
# 3. COASTAL BUCCANEER GROG STALL (coastal_buccaneer_grog_stall.glb)
# ==============================================================================

def _build_rum_bottle(mb, pos, col=C_BOTTLE_GREEN, scale=1.0, tilt_z=0.0):
    """Chunky pirate onion-bellied rum bottle ('paint' tinted emerald/amber glass + cork)."""
    s = scale
    with xf(mb, T(pos) @ R('Z', tilt_z)):
        prof = [
            (0.00,      0.00),
            (0.080 * s, 0.08 * s),
            (0.072 * s, 0.24 * s),
            (0.028 * s, 0.37 * s),
            (0.00,      0.43 * s),
        ]
        lathe(mb, prof, 5, 'paint', col, False, False,
              lambda i, k: C_DRIFT_PALE if i >= 3 else col)


def _build_grog_tankard(mb, pos, yaw_deg=0.0, scale=1.0):
    """Stout tavern pewter grog tankard ('iron' bright pewter + brass hoop + handle!)."""
    s = scale
    with xf(mb, T(pos) @ R('Y', yaw_deg)):
        cyl(mb, 0.074 * s, 0.00, 0.19 * s, 5, 'iron', C_PEWTER_HI, False, 0.0, 0.062 * s)
        cyl(mb, 0.076 * s, 0.03 * s, 0.065 * s, 5, 'brass', C_BRASS_WARM, False, 0.0)
        _add_beam(mb, (0.060 * s, 0.145 * s, 0.0), (0.114 * s, 0.135 * s, 0.0), 0.022 * s, 0.022 * s, 'iron', C_PEWTER_MID, 0.0)
        _add_beam(mb, (0.114 * s, 0.135 * s, 0.0), (0.106 * s, 0.045 * s, 0.0), 0.022 * s, 0.022 * s, 'iron', C_PEWTER_MID, 0.0)


def _build_barstool(mb, pos, yaw_deg=0.0):
    """Rustic 3-legged wooden pirate tavern barstool resting solidly on deck."""
    with xf(mb, T(pos) @ R('Y', yaw_deg)):
        cyl(mb, 0.24, 0.62, 0.70, 6, 'timber', C_OAK_SUN, False, 0.0)
        feet = []
        for k in range(3):
            ang = radians(30.0 + k * 120.0)
            top_p = Vector((0.14 * cos(ang), 0.63, 0.14 * sin(ang)))
            bot_p = Vector((0.23 * cos(ang), 0.00, 0.23 * sin(ang)))
            _add_beam(mb, bot_p, top_p, 0.064, 0.064, 'timber', C_OAK_DEEP, 0.0)
            feet.append(bot_p.lerp(top_p, 0.34))
        for k in range(3):
            _add_beam(mb, feet[k], feet[(k + 1) % 3], 0.044, 0.044, 'timber', C_OAK_RICH, 0.0)


def _build_tavern_rum_skull_sign(mb, hang_top):
    """Hanging double-sided painted rum-skull buccaneer tavern sign suspended on short chains."""
    for sx in (-0.30, 0.30):
        _add_beam(mb, hang_top + Vector((sx, 0.0, 0.0)), hang_top + Vector((sx, -0.26, 0.0)),
                  0.030, 0.030, 'iron', C_IRON_BRIGHT, 0.0)
    sc = hang_top + Vector((0.0, -0.60, 0.0))
    with xf(mb, T(sc) @ R('Y', 12.0)):
        cbox(mb, (0.0, 0.0, 0.0), (0.94, 0.66, 0.075), 'paint', C_TEAL_DARK, 0.0)
        cbox(mb, (0.0,  0.34, 0.0), (0.98, 0.06, 0.095), 'timber', C_OAK_DEEP, 0.0)
        cbox(mb, (0.0, -0.34, 0.0), (0.98, 0.06, 0.095), 'timber', C_OAK_DEEP, 0.0)
        for sx in (-0.48, 0.48):
            cbox(mb, (sx, 0.0, 0.0), (0.06, 0.72, 0.095), 'iron', C_IRON_FORGED, 0.0)
        for z_sgn in (-1.0, 1.0):
            fz = z_sgn * 0.052
            for ang_b in (32.0, -32.0):
                cbox(mb, (0.0, -0.06, fz), (0.64, 0.075, 0.035), 'skull_stone', C_SKULL_MID, 0.0, M=R('Z', ang_b))
            cbox(mb, (0.0, 0.07, fz + z_sgn * 0.015), (0.28, 0.24, 0.055), 'skull_stone', C_SKULL_BONE, 0.0)
            cbox(mb, (0.0, -0.09, fz + z_sgn * 0.012), (0.19, 0.11, 0.048), 'skull_stone', C_SKULL_BONE, 0.0)
            cbox(mb, (0.0, 0.17, fz + z_sgn * 0.025), (0.32, 0.09, 0.048), 'paint', C_CRIMSON_HI, 0.0, M=R('Z', -6.0))
            for ex in (-0.068, 0.068):
                cbox(mb, (ex, 0.05, fz + z_sgn * 0.042), (0.062, 0.062, 0.025), 'basalt', C_IRON_DARK, 0.0)


def gen_coastal_buccaneer_grog_stall(outdir):
    """Lively beachside buccaneer grog-and-provisions open-air bar grounded on a driftwood-and-cobble
    deck plinth plunging cleanly to y = -2.80 m (footprint hx=2.60 m, hz=2.15 m), four lashed
    timber counter posts supporting a wind-billowed patched crimson-teal-and-cream striped canvas
    canopy ('paint' + UV2 wind sway!), stout planked tavern bar counter lined with rows of
    green/amber rum bottles & pewter grog tankards, twin stacked oak rum puncheon casks on timber
    cradles with brass spigots, three rustic wooden barstools, hanging painted rum-skull tavern
    sign, coastal ferns ('foliage' + UV2), collider 'col_grogstall_base', and warm hanging bar
    lantern empty 'Lantern_GrogStall'."""
    clear_scene()
    mb = MB('coastal_buccaneer_grog_stall', seed=1803)
    rng = random.Random(SEED + 1803)
    col_pts = []

    DECK_Y = 0.44
    POST_X = 1.90
    POST_ZF = -1.16
    POST_ZR =  1.24
    EAVE_YF = 2.94
    EAVE_YR = 2.54
    RIDGE_Y = 3.38
    RIDGE_Z = -0.18

    # 1. Driftwood-and-Cobble Deck Plinth Plunging Cleanly to y = -2.80 m (hx=2.60, hz=2.15)
    skirt_secs = [
        _rect_oct(0.0, -2.80, 0.0, 2.60, 2.15, 0.44),
        _rect_oct(0.0, -1.10, 0.0, 2.54, 2.09, 0.42),
        _rect_oct(0.0,  0.00, 0.0, 2.46, 2.01, 0.38),
        _rect_oct(0.0,  0.26, 0.0, 2.38, 1.94, 0.34),
    ]
    _loft_horizontal_masonry(
        mb, skirt_secs, 'limestone',
        [C_COBBLE_WET, C_COBBLE_DARK, C_COBBLE_MID, C_COBBLE_HI],
        rng, caps=(True, True), top_mat='limestone', top_col=C_COBBLE_HI,
    )

    for yc, hx, hz in ((-2.80, 2.58, 2.14), (0.0, 2.44, 2.00), (DECK_Y, 2.30, 1.88), (2.86, 2.08, 1.48)):
        col_pts.extend(_rect_oct(0.0, yc, 0.0, hx, hz, 0.30))

    # Weathered Planked Driftwood Deck Platform (y = 0.26 to 0.44 m)
    cbox(mb, (0.0, 0.34, 0.0), (4.56, 0.16, 3.66), 'timber', C_DRIFT_DARK, 0.0)
    n_planks = 6
    for pi_idx in range(n_planks):
        pz = -1.52 + pi_idx * (3.04 / float(n_planks - 1))
        p_col = jit(C_DRIFT_MID if pi_idx % 2 == 0 else C_DRIFT_PALE, rng, 0.06, 0.015)
        cbox(mb, (0.0, DECK_Y - 0.02, pz), (4.48, 0.07, 0.54), 'timber', p_col, 0.0)

    # Low Driftwood Entry Step + 4 Properly Positioned Corner Bumper Pilings Lashed with Rope!
    cbox(mb, (0.0, 0.18, -2.02), (2.68, 0.22, 0.36), 'timber', C_DRIFT_MID, 0.0)
    for sx in (-2.22, 2.22):
        for sz in (-1.76, 1.72):
            with xf(mb, T(sx, 0.0, sz)):
                cyl(mb, 0.125, -0.04, DECK_Y + 0.36, 5, 'timber', C_DRIFT_DARK, False, 0.0, 0.110)
                with xf(mb, T(0.0, DECK_Y + 0.20, 0.0)):
                    torus(mb, 0.132, 0.026, 5, 4, 'rope', C_ROPE, False)

    # 2. Four Lashed Timber Counter Posts & Pergola Roof Frame (y = 0.44 to 3.38 m)
    for px, pz, py_top in (
        (-POST_X, POST_ZF, EAVE_YF),
        ( POST_X, POST_ZF, EAVE_YF),
        (-POST_X, POST_ZR, EAVE_YR),
        ( POST_X, POST_ZR, EAVE_YR),
    ):
        with xf(mb, T(px, 0.0, pz)):
            cyl(mb, 0.118, DECK_Y - 0.04, py_top + 0.14, 6, 'timber', C_OAK_RICH, False, 0.0, 0.102)
            cyl(mb, 0.132, DECK_Y, DECK_Y + 0.12, 6, 'iron', C_IRON_FORGED, False, 0.0)
            with xf(mb, T(0.0, py_top - 0.08, 0.0)):
                torus(mb, 0.138, 0.032, 5, 4, 'rope', C_ROPE, False)

    # Horizontal Front/Rear Eave Beams, Side Tie Beams, King-Posts & Ridge Pole
    _add_beam(mb, (-POST_X - 0.34, EAVE_YF, POST_ZF), (POST_X + 0.34, EAVE_YF, POST_ZF), 0.12, 0.13, 'timber', C_OAK_DEEP, 0.0)
    _add_beam(mb, (-POST_X - 0.30, EAVE_YR, POST_ZR), (POST_X + 0.30, EAVE_YR, POST_ZR), 0.12, 0.13, 'timber', C_OAK_DEEP, 0.0)
    for sx in (-POST_X, POST_X):
        _add_beam(mb, (sx, EAVE_YF - 0.06, POST_ZF), (sx, EAVE_YR - 0.06, POST_ZR), 0.11, 0.12, 'timber', C_OAK_RICH, 0.0)
        _add_beam(mb, (sx, 2.74, RIDGE_Z), (sx, RIDGE_Y - 0.04, RIDGE_Z), 0.10, 0.10, 'timber', C_OAK_SUN, 0.0)
        _add_beam(mb, (sx, EAVE_YF - 0.10, POST_ZF - 0.40), (sx, RIDGE_Y - 0.06, RIDGE_Z), 0.085, 0.09, 'timber', C_OAK_DEEP, 0.0)
        _add_beam(mb, (sx, EAVE_YR - 0.10, POST_ZR + 0.34), (sx, RIDGE_Y - 0.06, RIDGE_Z), 0.085, 0.09, 'timber', C_OAK_DEEP, 0.0)
        _add_beam(mb, (sx, EAVE_YF - 0.56, POST_ZF), (sx - (0.48 if sx > 0 else -0.48), EAVE_YF - 0.04, POST_ZF),
                  0.075, 0.085, 'timber', C_DRIFT_MID, 0.0)
        _add_beam(mb, (sx, EAVE_YR - 0.50, POST_ZR), (sx - (0.46 if sx > 0 else -0.46), EAVE_YR - 0.04, POST_ZR),
                  0.075, 0.085, 'timber', C_DRIFT_MID, 0.0)

    _add_beam(mb, (-POST_X - 0.36, RIDGE_Y - 0.04, RIDGE_Z), (POST_X + 0.36, RIDGE_Y - 0.04, RIDGE_Z), 0.10, 0.10, 'timber', C_OAK_SUN, 0.0)
    for rx in (-0.64, 0.64):
        _add_beam(mb, (rx, EAVE_YF - 0.14, POST_ZF - 0.36), (rx, RIDGE_Y - 0.10, RIDGE_Z), 0.068, 0.072, 'timber', C_OAK_RICH, 0.0)
        _add_beam(mb, (rx, EAVE_YR - 0.14, POST_ZR + 0.32), (rx, RIDGE_Y - 0.10, RIDGE_Z), 0.068, 0.072, 'timber', C_OAK_RICH, 0.0)

    # 3. Wind-Billowed Patched Crimson-Teal-and-Cream Striped Canvas Canopy ('paint' + UV2 wind sway!)
    stripe_cols = [
        C_CRIMSON_HI, C_CREAM_SAIL, C_TEAL_HI, C_CREAM_SAIL,
        C_CRIMSON_HI, C_CREAM_SAIL, C_TEAL_HI,
    ]
    n_stripes = len(stripe_cols)
    x_min, x_max = -2.26, 2.26
    dx_s = (x_max - x_min) / float(n_stripes)
    prof_z = [
        (POST_ZF - 0.52, EAVE_YF - 0.42, 0.90),
        (POST_ZF - 0.46, EAVE_YF - 0.02, 0.32),
        (-0.88,          3.12,           0.44),
        (RIDGE_Z,        RIDGE_Y + 0.06, 0.04),
        ( 0.56,          2.92,           0.42),
        (POST_ZR + 0.38, EAVE_YR - 0.04, 0.30),
        (POST_ZR + 0.44, EAVE_YR - 0.38, 0.88),
    ]
    thick_c = 0.022
    for si in range(n_stripes):
        xa = x_min + si * dx_s
        xb = xa + dx_s
        col_s = stripe_cols[si]
        col_u = mul(col_s, 0.78)
        ph_s = (0.12 + si * 0.13) % 1.0

        def _canopy_pt(x_val, z_idx):
            zb, yb, wb = prof_z[z_idx]
            sag = -0.055 * abs(sin((x_val / 2.26) * pi * 2.0)) if z_idx in (2, 4) else 0.0
            billow_z = (0.07 * sin(x_val * 2.2 + 0.6)) if z_idx in (0, 6) else 0.0
            scallop_y = (-0.06 * cos((x_val - xa) / max(dx_s, 1e-4) * pi * 2.0)) if z_idx in (0, 6) else 0.0
            return Vector((x_val, yb + sag + scallop_y, zb + billow_z)), wb

        for zi in range(len(prof_z) - 1):
            p00, w0 = _canopy_pt(xa, zi)
            p10, _  = _canopy_pt(xb, zi)
            p11, w1 = _canopy_pt(xb, zi + 1)
            p01, _  = _canopy_pt(xa, zi + 1)
            # Patched canvas repair panels cleanly integrated into awning geometry (zero clipping!)
            face_c = C_CREAM_AGED if (si == 4 and zi == 1) else (C_CRIMSON_MID if (si == 1 and zi == 4) else col_s)
            u0 = (w0, ph_s)
            u1 = (w1, ph_s)
            ctr = (p00 + p10 + p11 + p01) * 0.25
            fn = newell([p00, p10, p11, p01])
            if fn.length < 1e-6:
                continue
            fn.normalize()
            if fn.dot(ctr - Vector((0.0, 1.5, 0.0))) < 0:
                fn = -fn
            off_v = fn * thick_c
            mb.fp([p00 + off_v, p10 + off_v, p11 + off_v, p01 + off_v], 'paint', face_c,
                  (0, 0, 1), ctr - fn * 2.0, smooth=False, uv2=[u0, u0, u1, u1])
            mb.fp([p10 - off_v, p00 - off_v, p01 - off_v, p11 - off_v], 'paint', col_u,
                  (0, 0, 1), ctr + fn * 2.0, smooth=False, uv2=[u0, u0, u1, u1])
            # Surface-conforming stitched canvas patch overlay on front-starboard & rear-port slopes!
            if (si == 4 and zi == 2) or (si == 2 and zi == 4):
                patch_c = C_CREAM_AGED if si == 4 else C_TEAL_DARK
                p_off = fn * (thick_c + 0.016)
                q00 = ctr.lerp(p00, 0.72) + p_off
                q10 = ctr.lerp(p10, 0.72) + p_off
                q11 = ctr.lerp(p11, 0.72) + p_off
                q01 = ctr.lerp(p01, 0.72) + p_off
                mb.fp([q00, q10, q11, q01], 'paint', patch_c, (1, 0, 0), ctr - fn * 2.0,
                      smooth=False, uv2=[u0, u0, u1, u1])

    # 4. Stout Planked Tavern Bar Counter (z = -0.80 m) + L-Return + Back-Bar Wall & Shelves
    BAR_Z = -0.80
    BAR_TOP_Y = 1.44
    cbox(mb, (-0.10, 0.92, BAR_Z), (3.16, 0.96, 0.54), 'timber', C_OAK_DEEP, 0.0)
    for px_i in range(6):
        px_b = -1.46 + px_i * 0.54
        cbox(mb, (px_b, 0.92, BAR_Z - 0.28), (0.48, 0.92, 0.055), 'timber',
             C_OAK_RICH if px_i % 2 == 0 else C_OAK_SUN, 0.0)
    for sy_s in (0.64, 1.20):
        cbox(mb, (-0.10, sy_s, BAR_Z - 0.315), (3.18, 0.055, 0.03), 'iron', C_IRON_FORGED, 0.0)
    _add_beam(mb, (-1.62, DECK_Y + 0.18, BAR_Z - 0.44), (1.44, DECK_Y + 0.18, BAR_Z - 0.44),
              0.052, 0.052, 'brass', C_BRASS_DARK, 0.0)
    for fx in (-1.35, -0.10, 1.18):
        _add_beam(mb, (fx, DECK_Y + 0.18, BAR_Z - 0.44), (fx, DECK_Y + 0.18, BAR_Z - 0.24),
                  0.042, 0.042, 'iron', C_IRON_FORGED, 0.0)

    cbox(mb, (-0.08, BAR_TOP_Y, BAR_Z - 0.04), (3.44, 0.10, 0.72), 'timber', C_OAK_SUN, 0.0)
    cbox(mb, (-1.54, 0.92, -0.22), (0.50, 0.96, 0.96), 'timber', C_OAK_RICH, 0.0)
    cbox(mb, (-1.54, BAR_TOP_Y, -0.22), (0.62, 0.10, 1.08), 'timber', C_OAK_SUN, 0.0)

    # Rear Back-Bar Planked Provisions Wall, Double Bottle Shelves & Rear Maritime Decor!
    cbox(mb, (0.52, 1.32, 1.18), (2.56, 1.72, 0.10), 'timber', C_OAK_DEEP, 0.0)
    cbox(mb, (0.52, 2.08, 1.12), (2.48, 0.22, 0.06), 'paint', C_CRIMSON_MID, 0.0)
    for sy_sh in (1.36, 1.84):
        cbox(mb, (0.52, sy_sh, 0.98), (2.42, 0.065, 0.34), 'timber', C_OAK_SUN, 0.0)
    # Rear (+Z) exterior cross-bracing & mounted striped crimson-and-cream coastal lifebuoy ring (elevates Rear 3/4!)
    _add_beam(mb, (-0.68, 0.56, 1.25), (1.72, 2.06, 1.25), 0.08, 0.05, 'timber', C_DRIFT_MID, 0.0)
    _add_beam(mb, ( 1.72, 0.56, 1.25), (-0.68, 2.06, 1.25), 0.08, 0.05, 'timber', C_DRIFT_MID, 0.0)
    with xf(mb, T(0.52, 1.38, 1.31) @ M_Y2Z):
        torus(mb, 0.36, 0.085, 8, 4, 'paint', C_CREAM_SAIL, False)
        for k in range(4):
            ang = k * pi * 0.5
            cbox(mb, (0.36 * cos(ang), 0.0, 0.36 * sin(ang)), (0.14, 0.19, 0.14), 'paint', C_CRIMSON_HI, 0.0)

    # 5. Rows of Green/Amber Rum Bottles & Pewter Grog Tankards!
    for bx, bz, bcol, bsc, btilt in (
        (-1.54, -0.82, C_BOTTLE_GREEN,   1.04,  0.0),
        (-1.26, -0.76, C_BOTTLE_AMBER,   0.96,  3.0),
        ( 0.88, -0.74, C_BOTTLE_AMBER,   1.04,  0.0),
        ( 1.08, -0.86, C_BOTTLE_GREEN,   0.96,  4.0),
        ( 1.26, -0.76, C_BOTTLE_EMERALD, 0.90, -3.0),
    ):
        _build_rum_bottle(mb, (bx, BAR_TOP_Y + 0.05, bz), col=bcol, scale=bsc, tilt_z=btilt)

    for bx, by, bcol, bsc in (
        (-0.34, 1.39, C_BOTTLE_GREEN,   0.98),
        ( 0.14, 1.39, C_BOTTLE_AMBER,   1.02),
        ( 0.72, 1.39, C_BOTTLE_EMERALD, 0.96),
        (-0.14, 1.87, C_BOTTLE_AMBER,   1.00),
        ( 0.34, 1.87, C_BOTTLE_GREEN,   0.96),
        ( 0.84, 1.87, C_BOTTLE_EMERALD, 0.98),
    ):
        _build_rum_bottle(mb, (bx, by, 0.96), col=bcol, scale=bsc)

    for tx, tz, tyaw in (
        (-0.84, -0.96,  24.0),
        (-0.18, -0.90, -18.0),
        ( 0.38, -0.94,  38.0),
        (-1.46, -0.20,  85.0),
    ):
        _build_grog_tankard(mb, (tx, BAR_TOP_Y + 0.05, tz), yaw_deg=tyaw, scale=1.08)

    # 6. Twin Stacked Oak Rum Puncheon Casks on Timber Cradles with Brass Spigots!
    CASK_X, CASK_Z = -1.16, 0.58
    for cz_c in (CASK_Z - 0.24, CASK_Z + 0.24):
        cbox(mb, (CASK_X, DECK_Y + 0.13, cz_c), (0.76, 0.26, 0.12), 'timber', C_OAK_DEEP, 0.0)
    _build_coopered_cask(
        mb, T(CASK_X, DECK_Y + 0.54, CASK_Z) @ R('X', 90.0),
        radius=0.36, height=0.90, rng=rng, segs=6, stripe_col=C_CRIMSON_HI,
    )
    cbox(mb, (CASK_X, DECK_Y + 0.42, CASK_Z - 0.50), (0.06, 0.06, 0.16), 'brass', C_GOLD_BRIGHT, 0.0)
    cbox(mb, (CASK_X, DECK_Y + 0.48, CASK_Z - 0.54), (0.14, 0.04, 0.04), 'brass', C_GOLD_BRIGHT, 0.0)
    with xf(mb, T(CASK_X, 0.0, CASK_Z - 0.54)):
        cyl(mb, 0.12, DECK_Y, DECK_Y + 0.22, 5, 'timber', C_OAK_RICH, False, 0.0, 0.15)
        cyl(mb, 0.148, DECK_Y + 0.16, DECK_Y + 0.19, 5, 'iron', C_IRON_FORGED, False, 0.0)

    for cz_c in (CASK_Z - 0.18, CASK_Z + 0.18):
        cbox(mb, (CASK_X, DECK_Y + 0.90, cz_c), (0.58, 0.12, 0.10), 'timber', C_OAK_DEEP, 0.0)
    _build_coopered_cask(
        mb, T(CASK_X, DECK_Y + 1.24, CASK_Z) @ R('X', 90.0),
        radius=0.31, height=0.80, rng=rng, segs=6, stripe_col=C_TEAL_HI,
    )
    cbox(mb, (CASK_X, DECK_Y + 1.14, CASK_Z - 0.45), (0.055, 0.055, 0.14), 'brass', C_GOLD_BRIGHT, 0.0)

    # Third standing oak rum cask beside the starboard bar entrance
    _build_coopered_cask(
        mb, T(1.66, DECK_Y + 0.38, 0.34) @ R('Y', 22.0),
        radius=0.29, height=0.76, rng=rng, segs=6, stripe_col=C_CRIMSON_HI,
    )

    # 7. Three Rustic Wooden Barstools on the Seaward Customer Deck Apron
    for sx_b, sz_b, syaw in (
        (-0.98, -1.46,  14.0),
        (-0.04, -1.52, -22.0),
        ( 0.94, -1.44,  34.0),
    ):
        _build_barstool(mb, (sx_b, DECK_Y, sz_b), yaw_deg=syaw)

    # 8. Hanging Painted Rum-Skull Tavern Sign on Forged-Iron Scroll Bracket
    SIGN_ARM_Y = 2.66
    _add_beam(mb, (POST_X, SIGN_ARM_Y, POST_ZF), (POST_X + 1.12, SIGN_ARM_Y, POST_ZF),
              0.064, 0.068, 'iron', C_IRON_FORGED, 0.0)
    _add_beam(mb, (POST_X, SIGN_ARM_Y - 0.44, POST_ZF), (POST_X + 0.72, SIGN_ARM_Y, POST_ZF),
              0.048, 0.048, 'iron', C_IRON_BRIGHT, 0.0)
    cbox(mb, (POST_X + 1.14, SIGN_ARM_Y, POST_ZF), (0.10, 0.10, 0.10), 'brass', C_GOLD_BRIGHT, 0.0)
    _build_tavern_rum_skull_sign(mb, Vector((POST_X + 0.62, SIGN_ARM_Y - 0.02, POST_ZF)))

    # 9. Warm Hanging Bar Lantern directly over the Tavern Counter ('Lantern_GrogStall')
    LANTERN_POS = Vector((0.0, 2.34, BAR_Z - 0.08))
    _add_beam(mb, (0.0, 3.04, BAR_Z - 0.08), LANTERN_POS + Vector((0.0, 0.28, 0.0)),
              0.028, 0.028, 'iron', C_IRON_FORGED, 0.0)
    _build_storm_lantern(mb, LANTERN_POS, scale=0.86, brass_cage=True, hanging=True)

    # 10. Coiled Hemp Rope & Coastal Ferns ('foliage' + UV2!)
    _build_rope_coil_lean(mb, (1.68, DECK_Y, -0.44), radius=0.25, turns=2, r=0.034, segs=6, psegs=4)
    for fpos, fsc, flean, fph in (
        ((-2.28, 0.26, -1.62), 0.78, (-0.7, 0.0, -0.7), 0.15),
        (( 2.30, 0.26, -1.56), 0.76, ( 0.7, 0.0, -0.7), 0.41),
        ((-2.26, 0.26,  1.62), 0.80, (-0.7, 0.0,  0.7), 0.68),
        (( 2.28, 0.26,  1.58), 0.78, ( 0.7, 0.0,  0.7), 0.92),
        ((-2.36, 0.26,  0.04), 0.68, (-1.0, 0.0,  0.0), 0.29),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=4, rng=rng, phase=fph, lean_dir=flean, segs=2)

    build(mb)

    add_empty('Lantern_GrogStall', LANTERN_POS)
    col_piece('col_grogstall_base', col_pts)
    export_landmark_glb(outdir, 'coastal_buccaneer_grog_stall.glb')


# ==============================================================================
# 4. VOLCANIC OBSIDIAN ANCHOR MONOLITH (volcanic_obsidian_anchor_monolith.glb)
# ==============================================================================

def _build_colossal_anchor(mb, M_anchor):
    """Colossal ~5.2 m rusted wrought-iron & magma-crusted galleon anchor with tapered octagonal
    shank, sweeping curved iron arms, sculpted barbed triangular flukes, heavy iron-banded
    cross-stock & giant forged anchor ring. Returns key world-space attachment points!"""
    with xf(mb, M_anchor):
        # 1. Heavy Tapered Wrought-Iron Main Shank (y = -2.24 to +2.34 m)
        shank_secs = [
            _rect_oct(0.0, -2.24, 0.0, 0.24, 0.22, 0.06),
            _rect_oct(0.0, -1.00, 0.0, 0.20, 0.19, 0.05),
            _rect_oct(0.0,  0.40, 0.0, 0.17, 0.17, 0.05),
            _rect_oct(0.0,  1.65, 0.0, 0.16, 0.16, 0.04),
            _rect_oct(0.0,  2.34, 0.0, 0.18, 0.18, 0.05),
        ]
        loft(mb, shank_secs, 'iron', C_IRON_RUST_HI, closed=True, caps=(True, True), mode='flat',
             scols=[C_IRON_RUST_HI, C_IRON_BRIGHT, C_IRON_RUST_MID, C_IRON_BRIGHT, C_IRON_BRIGHT])

        # Reinforced Anchor Crown Throat Boss, Center Spine Ribs & Forged Collars along shank
        cbox(mb, (0.0, -2.20, 0.0), (0.62, 0.48, 0.50), 'iron', C_IRON_RUST_HI, 0.03)
        cbox(mb, (0.0, -2.44, 0.0), (0.34, 0.22, 0.34), 'iron', C_IRON_BRIGHT, 0.0)
        for cy_c in (-0.85, 0.15, 0.92, 1.40):
            cbox(mb, (0.0, cy_c, 0.0), (0.44, 0.12, 0.44), 'iron', C_IRON_BRIGHT, 0.0)

        # Fiery orange-red glowing magma-crust veins running down shank faces
        for z_sgn in (-1.0, 1.0):
            _sculpt_magma_ribbon(
                mb,
                [(0.0, -1.35, z_sgn * 0.20), (0.08, -0.55, z_sgn * 0.19),
                 (-0.06, 0.25, z_sgn * 0.18), (0.04, 0.95, z_sgn * 0.17)],
                [0.075, 0.09, 0.08, 0.055], (0.0, 0.0, z_sgn), hot_core=False, ridge_h=0.036,
            )

        # 2. Sweeping Curved Wrought-Iron Anchor Arms & Sculpted Barbed Triangular Flukes!
        for sgn in (-1.0, 1.0):
            arm_pts = [
                Vector((sgn * 0.14, -2.22, 0.0)),
                Vector((sgn * 0.66, -2.10, 0.0)),
                Vector((sgn * 1.12, -1.76, 0.0)),
                Vector((sgn * 1.44, -1.24, 0.0)),
                Vector((sgn * 1.54, -0.80, 0.0)),
            ]
            tube(mb, arm_pts, [0.21, 0.19, 0.17, 0.145, 0.072], 6, 'iron', C_IRON_BRIGHT,
                 caps=(False, True), mode='flat',
                 scols=[C_IRON_RUST_HI, C_IRON_BRIGHT, C_IRON_RUST_HI, C_IRON_BRIGHT, C_IRON_BRIGHT])

            # Sculpted Broad Barbed Arrow-Head Fluke (Palm) with prominent central rib!
            tip = arm_pts[-1]
            tang = (arm_pts[-1] - arm_pts[-2]).normalized()
            in_nrm = Vector((-sgn * tang.y, sgn * tang.x, 0.0)).normalized()
            fluke_base = arm_pts[-2].lerp(tip, 0.30)
            p_bill = tip + tang * 0.38
            p_wing_l = fluke_base - tang * 0.16 - in_nrm * 0.22 + Vector((0.0, 0.0, -0.44))
            p_wing_r = fluke_base - tang * 0.16 - in_nrm * 0.22 + Vector((0.0, 0.0,  0.44))
            p_back   = fluke_base - tang * 0.04 + in_nrm * 0.16
            p_ridge_f = fluke_base + tang * 0.16 + in_nrm * 0.16
            p_ridge_b = fluke_base + tang * 0.16 - in_nrm * 0.18
            fluke_c = C_IRON_RUST_HI if sgn < 0 else C_IRON_BRIGHT
            ctr_fl = (p_bill + p_wing_l + p_wing_r + p_back) * 0.25
            for tri in (
                [p_bill, p_wing_l, p_ridge_f],
                [p_bill, p_ridge_f, p_wing_r],
                [p_back, p_ridge_f, p_wing_l],
                [p_back, p_wing_r, p_ridge_f],
                [p_bill, p_ridge_b, p_wing_l],
                [p_bill, p_wing_r, p_ridge_b],
                [p_back, p_wing_l, p_ridge_b],
                [p_back, p_ridge_b, p_wing_r],
            ):
                mb.fp(tri, 'iron', fluke_c, tang, ctr_fl, smooth=False)
            # Raised forged-iron spine rib & molten magma-crusted edge along each barbed fluke!
            _add_beam(mb, fluke_base - tang * 0.10, p_bill - tang * 0.06, 0.10, 0.16, 'iron', C_IRON_BRIGHT, 0.0)
            _add_beam(mb, fluke_base + in_nrm * 0.08, p_bill - tang * 0.10, 0.07, 0.18, 'glass', C_FLAME_MID, 0.0)

        # 3. Heavy Two-Piece Iron-Banded Galleon Cross-Stock (along local Z at y = +1.78 m!)
        STOCK_Y = 1.78
        cbox(mb, (0.0, STOCK_Y, 0.0), (0.38, 0.40, 2.52), 'timber', C_OAK_RICH, 0.025)
        for sz in (-1.02, -0.48, 0.48, 1.02):
            cbox(mb, (0.0, STOCK_Y, sz), (0.42, 0.44, 0.13), 'iron', C_IRON_BRIGHT, 0.0)
            # Heavy bolted iron rivet bosses on front/back of stock clamping straps!
            for sx_r in (-0.22, 0.22):
                cbox(mb, (sx_r, STOCK_Y, sz), (0.06, 0.12, 0.08), 'iron', C_IRON_RUST_HI, 0.0)
        for sz_end in (-1.32, 1.32):
            cbox(mb, (0.0, STOCK_Y, sz_end), (0.30, 0.32, 0.18), 'iron', C_IRON_RUST_HI, 0.0)

        # 4. Pierced Shank Head Eye, Heavy Shackle Collar & Giant Forged-Iron Anchor Ring!
        cbox(mb, (0.0, 2.26, 0.0), (0.44, 0.38, 0.40), 'iron', C_IRON_BRIGHT, 0.0)
        with xf(mb, T(0.0, 2.70, 0.0) @ M_Y2Z):
            torus(mb, 0.46, 0.10, 12, 5, 'iron', C_IRON_BRIGHT, False)
            with xf(mb, T(0.0, 0.0, -0.46)):
                torus(mb, 0.14, 0.044, 6, 4, 'glass', C_FLAME_MID, False)

    return {
        'ring':    M_anchor @ Vector((0.0, 3.04, 0.0)),
        'stock_p': M_anchor @ Vector((0.0, 1.78, -1.08)),
        'stock_s': M_anchor @ Vector((0.0, 1.78,  1.08)),
        'crown':   M_anchor @ Vector((0.0, -2.32, 0.0)),
    }


def gen_volcanic_obsidian_anchor_monolith(outdir):
    """Colossal cursed ship's anchor fused into a fractured volcanic obsidian spire plunging cleanly
    into a jagged basalt foundation down to y = -3.60 m (radius ~2.60 m), towering ~7.0 m leaning
    hexagonal columnar-basalt monolith etched with glowing molten cracks ('glass' warm orange-gold
    linear COLOR_0), impaled diagonally through its upper flank by a massive rusted wrought-iron &
    magma-crusted galleon anchor (~5.2 m span with sculpted stock, flukes & ring!), wrapped in taut
    draped glowing iron anchor chains anchored to flanking basalt spurs, incandescent ember clefts
    at base, collider 'col_volcanchor_base', and 'Lantern_VolcAnchor' empty."""
    clear_scene()
    mb = MB('volcanic_obsidian_anchor_monolith', seed=1804)
    rng = random.Random(SEED + 1804)
    col_pts = []

    DECK_Y = 0.54

    # 1. Jagged Fractured Basalt Foundation Plunging Cleanly to y = -3.60 m (radius ~2.60 m)
    found_secs = [
        _reg_poly(0.0, -3.60, 0.0, 2.62, sides=6, rot_deg=15.0),
        _reg_poly(0.0, -1.65, 0.0, 2.54, sides=6, rot_deg=15.0),
        _reg_poly(0.0,  0.00, 0.0, 2.42, sides=6, rot_deg=15.0),
        _reg_poly(0.0,  0.28, 0.0, 2.28, sides=6, rot_deg=15.0),
    ]
    _loft_horizontal_masonry(
        mb, found_secs, 'basalt',
        [C_OBSIDIAN_ABYSS, C_OBSIDIAN_DARK, C_OBSIDIAN_MID, C_OBSIDIAN_HI],
        rng, caps=(True, True), top_mat='basalt', top_col=C_OBSIDIAN_MID,
    )
    bench_secs = [
        _reg_poly(0.0, 0.26,   0.0, 1.98, sides=6, rot_deg=45.0),
        _reg_poly(0.0, DECK_Y, 0.0, 1.84, sides=6, rot_deg=45.0),
    ]
    _loft_horizontal_masonry(
        mb, bench_secs, 'basalt',
        [C_OBSIDIAN_MID, C_OBSIDIAN_HI],
        rng, caps=(False, True), top_mat='basalt', top_col=C_OBSIDIAN_MID,
    )

    for yc, rc in ((-3.60, 2.60), (0.0, 2.40), (DECK_Y, 1.92), (4.60, 1.48)):
        col_pts.extend(_reg_poly(0.0, yc, 0.0, rc, sides=6, rot_deg=15.0))

    # Stepped Fractured Hexagonal Basalt Plinth Benches + Incandescent Volcanic Ember Clefts at Base!
    for hx_b, hz_b, hr_b, hh_b in (
        (-1.28, -1.06, 0.42, 0.56), ( 1.32, -1.02, 0.44, 0.48),
        (-1.34,  0.98, 0.40, 0.62), ( 1.24,  1.06, 0.42, 0.52),
    ):
        with xf(mb, T(hx_b, 0.0, hz_b)):
            cyl(mb, hr_b, DECK_Y - 0.16, DECK_Y + hh_b, 6, 'basalt', C_OBSIDIAN_HI, False, 0.0, hr_b * 0.88)

    for c_ang in (-142.0, -68.0, -14.0, 50.0, 128.0):
        ar = radians(c_ang)
        ca, sa = cos(ar), sin(ar)
        p0 = Vector((0.36 * ca, DECK_Y + 0.03, 0.36 * sa))
        p1 = Vector((1.12 * ca - 0.12 * sa, DECK_Y + 0.03, 1.12 * sa + 0.12 * ca))
        p2 = Vector((1.92 * ca, DECK_Y - 0.06, 1.92 * sa))
        _sculpt_magma_ribbon(mb, [p0, p1, p2], [0.12, 0.10, 0.065], (0.0, 1.0, 0.0),
                             hot_core=True, ridge_h=0.042)

    # 2. Towering ~7.04 m Leaning Hexagonal Columnar-Basalt Monolith Spire!
    spire_spec = [
        (-0.04, DECK_Y - 0.12,  0.00, 1.12, 1.06, C_OBSIDIAN_DARK),
        (-0.14, 1.62,           0.04, 1.00, 0.94, C_OBSIDIAN_MID),
        (-0.24, 2.86,           0.08, 0.88, 0.82, C_OBSIDIAN_HI),
        (-0.36, 4.18,           0.12, 0.78, 0.72, C_OBSIDIAN_HI),
        (-0.48, 5.42,           0.16, 0.62, 0.56, C_OBSIDIAN_EDGE),
        (-0.60, 6.46,           0.20, 0.36, 0.32, C_OBSIDIAN_EDGE),
        (-0.70, 7.04,           0.24, 0.06, 0.05, C_OBSIDIAN_EDGE),
    ]
    sp_secs, sp_cols = [], []
    for idx_s, (px, py, pz, rx, rz, col) in enumerate(spire_spec):
        ring = []
        for k in range(6):
            ang = radians(18.0 + k * 60.0)
            jag = 1.0 + 0.08 * sin(ang * 2.0 + idx_s * 1.5)
            y_sl = (0.34 * cos(ang + 0.6) if idx_s == len(spire_spec) - 2 else 0.0)
            ring.append(Vector((px + rx * jag * cos(ang), py + y_sl, pz + rz * jag * sin(ang))))
        sp_secs.append(ring)
        sp_cols.append(col)
    loft(mb, sp_secs, 'basalt', C_OBSIDIAN_HI, closed=True, caps=(False, True), mode='flat', scols=sp_cols)

    # 5 Fused Hexagonal Columnar-Basalt Organ-Pipe Shoulder Shafts — kept sculpted & stepped below
    # y = 2.6 m on the front-port flank so BOTH massive anchor flukes & curved arms silhouette cleanly!
    for ox, oz, ch_c, crad, tx, tz in (
        (-0.92, -0.52, 2.15, 0.42, -5.5, -2.5),  # stepped low below impaled anchor flukes!
        ( 0.86, -0.60, 2.72, 0.40,  4.5, -3.5),
        (-0.88,  0.76, 4.86, 0.42, -5.5,  4.5),  # tall dramatic rear-port organ pipe!
        ( 0.94,  0.64, 3.24, 0.38,  5.0,  4.0),
        ( 0.08, -0.94, 2.08, 0.36, -1.5, -6.0),
    ):
        sculpt_basalt_column(
            mb, (ox, DECK_Y - 0.18, oz), ch_c, crad, 6,
            tx, tz, C_OBSIDIAN_DARK, C_OBSIDIAN_HI, rng, mat='basalt', magma_seam=True,
        )

    # Crisp Fiery Molten Lava Cracks ('glass' deep molten orange-red -> amber core!) etching spire faces
    _sculpt_magma_ribbon(
        mb,
        [(-0.08, 0.68, -0.98), (-0.30, 1.72, -0.88), (-0.06, 2.76, -0.78),
         (-0.34, 3.86, -0.68), (-0.50, 5.02, -0.54), (-0.62, 6.18, -0.24)],
        [0.10, 0.09, 0.095, 0.11, 0.08, 0.045], (0.0, 0.0, -1.0), hot_core=True, ridge_h=0.042,
    )
    _sculpt_magma_ribbon(
        mb,
        [(-0.12, 0.68, 1.00), (0.14, 1.84, 0.90), (-0.28, 3.10, 0.82),
         (-0.46, 4.44, 0.72), (-0.56, 5.82, 0.50)],
        [0.10, 0.085, 0.095, 0.085, 0.05], (0.0, 0.0, 1.0), hot_core=True, ridge_h=0.042,
    )
    _sculpt_magma_ribbon(
        mb,
        [(0.90, 0.74, -0.10), (0.76, 1.98, 0.12), (0.58, 3.36, -0.10), (0.38, 4.48, 0.08)],
        [0.095, 0.085, 0.10, 0.065], (1.0, 0.0, 0.0), hot_core=False, ridge_h=0.040,
    )

    # 3. Colossal Rusted Wrought-Iron & Magma-Crusted Galleon Anchor (~5.2 m span!) Impaled Diagonally!
    # Positioned & angled so its broadside silhouette — twin barbed triangular flukes, sweeping arms,
    # heavy bolted cross-stock & giant forged anchor ring — reads UNMISTAKABLY from both Hero & Rear 3/4!
    M_ANCHOR = T(-0.08, 4.18, -0.18) @ R('Y', -24.0) @ R('Z', -48.0) @ R('X', 6.0)
    anc_pts = _build_colossal_anchor(mb, M_ANCHOR)

    # Jagged Shattered Obsidian Impact Splinters & Fiery Molten Crack Collar where Anchor Pierces Spire!
    for sp_pos, sp_dir, sp_len, sp_r in (
        ((-0.64, 3.84, -0.66), (-0.85,  0.42, -0.70), 0.78, 0.18),
        ((-0.52, 3.38, -0.74), (-0.75, -0.36, -0.76), 0.68, 0.16),
        (( 0.42, 4.52, -0.48), ( 0.78,  0.54, -0.58), 0.72, 0.17),
        (( 0.46, 4.12,  0.56), ( 0.76,  0.34,  0.72), 0.74, 0.17),
        ((-0.58, 3.74,  0.60), (-0.74, -0.28,  0.74), 0.66, 0.16),
    ):
        bp = Vector(sp_pos)
        sd = Vector(sp_dir).normalized()
        tube(mb, [bp, bp + sd * (sp_len * 0.55), bp + sd * sp_len],
             [sp_r, sp_r * 0.62, 0.018], 5, 'basalt', C_OBSIDIAN_EDGE, caps=(False, True), mode='flat',
             scols=[C_OBSIDIAN_MID, C_OBSIDIAN_HI, C_OBSIDIAN_EDGE])

    # Recessed incandescent magma scar embers inside the anchor impact wounds (rich orange-red, not blobby!)
    for w_pos in (Vector((-0.36, 3.86, -0.68)), Vector((0.32, 4.30, 0.52))):
        with xf(mb, T(w_pos)):
            lathe(mb, [(0.0, -0.14), (0.24, -0.02), (0.20, 0.12), (0.0, 0.18)],
                  6, 'glass', C_FLAME_MID, False, False,
                  lambda i, k: C_FLAME_CORE if i == 1 else C_FLAME_DEEP)

    # 4. Flanking Razor-Sharp Basalt Anchor Spurs & Taut Draped Glowing Iron Anchor Chains!
    spur_anchors = []
    for sx_b, sz_b, sh_s, sr_s, tilt_x, tilt_z in (
        ( 2.26, -1.04, 2.38, 0.40,  18.0, -14.0),  # 0: front-starboard spur (catches giant ring chain!)
        (-2.28, -0.92, 2.24, 0.38, -18.0, -12.0),  # 1: front-port spur (catches lower crown/spire chain!)
        ( 1.94,  1.42, 2.48, 0.40,  15.0,  16.0),  # 2: rear-starboard spur (catches rear stock chain!)
        (-1.88,  1.48, 1.96, 0.35, -14.0,  18.0),  # 3: rear-port basalt shard spur
    ):
        s_dir = Vector((sin(radians(tilt_x)), 1.0, sin(radians(tilt_z)))).normalized()
        bp = Vector((sx_b, DECK_Y - 0.30, sz_b))
        sp_pts = [bp, bp + s_dir * (sh_s * 0.46), bp + s_dir * (sh_s * 0.84), bp + s_dir * sh_s]
        tube(mb, sp_pts, [sr_s, sr_s * 0.78, sr_s * 0.44, 0.024], 5, 'basalt', C_OBSIDIAN_HI,
             caps=(False, True), mode='flat',
             scols=[C_OBSIDIAN_DARK, C_OBSIDIAN_MID, C_OBSIDIAN_HI, C_OBSIDIAN_EDGE])
        shackle_pt = sp_pts[1] + Vector((0.0, 0.16, 0.0))
        spur_anchors.append(shackle_pt)
        if len(spur_anchors) <= 3:
            with xf(mb, T(shackle_pt)):
                cyl(mb, sr_s * 0.82, -0.10, 0.10, 6, 'iron', C_IRON_BRIGHT, False, 0.0)
                with xf(mb, T(0.0, 0.14, 0.0) @ M_Y2Z):
                    torus(mb, 0.12, 0.036, 6, 4, 'iron', C_IRON_BRIGHT, False)

    # Taut Draped Glowing Iron Anchor Chains connecting Anchor & Monolith to the 3 Basalt Spurs!
    # Chain 1: Giant upper anchor ring -> front-starboard basalt spur
    _add_chain_links(
        mb, anc_pts['ring'], spur_anchors[0] + Vector((0.0, 0.12, 0.0)),
        n_links=11, link_r=0.19, wire_r=0.056, segs=5, psegs=4, sag=0.40,
        mat='iron', rust_stride=2, stretch_y=1.42,
        col_a=C_IRON_BRIGHT, col_b=C_IRON_RUST_HI,
        glow_indices={0, 1, 3, 5},
    )
    # Chain 2: Anchor crown throat -> front-port basalt spur
    _add_chain_links(
        mb, anc_pts['crown'], spur_anchors[1] + Vector((0.0, 0.12, 0.0)),
        n_links=7, link_r=0.18, wire_r=0.054, segs=5, psegs=4, sag=0.22,
        mat='iron', rust_stride=2, stretch_y=1.42,
        col_a=C_IRON_BRIGHT, col_b=C_IRON_RUST_HI,
        glow_indices={0, 2, 4},
    )
    # Chain 3: Upper anchor stock -> rear-starboard basalt spur
    _add_chain_links(
        mb, anc_pts['stock_s'], spur_anchors[2] + Vector((0.0, 0.12, 0.0)),
        n_links=9, link_r=0.175, wire_r=0.052, segs=5, psegs=4, sag=0.34,
        mat='iron', rust_stride=2, stretch_y=1.42,
        col_a=C_IRON_BRIGHT, col_b=C_IRON_RUST_HI,
        glow_indices={0, 2, 4},
    )
    # Chain 4: Tightly tensioned iron-and-magma waist chain binding the spire to the rear-port spur!
    _add_chain_links(
        mb, Vector((-0.86, 2.38, 0.44)), spur_anchors[3] + Vector((0.0, 0.10, 0.0)),
        n_links=5, link_r=0.165, wire_r=0.050, segs=5, psegs=4, sag=0.18,
        mat='iron', rust_stride=2, stretch_y=1.42,
        col_a=C_IRON_FORGED, col_b=C_IRON_RUST_HI,
        glow_indices={0, 2},
    )

    # Heavy Glowing Volcanic Iron Binding Collar hugging the Monolith Waist + Surplus Coiled Anchor Chain at Base!
    with xf(mb, T(-0.20, 2.38, 0.06) @ R('Z', 6.0)):
        torus(mb, 1.00, 0.072, 10, 4, 'iron', C_IRON_BRIGHT, False)
        torus(mb, 1.03, 0.038, 10, 4, 'glass', C_FLAME_MID, False)

    # Coiled heap of heavy surplus iron anchor links resting on the front-seaward basalt apron!
    for ci, (cx_l, cy_l, cz_l, ry_l, rx_l, is_gl) in enumerate((
        ( 0.86, DECK_Y + 0.09, -1.28,  18.0, 78.0, False),
        ( 1.04, DECK_Y + 0.11, -1.16, -42.0, 68.0, True),
        ( 0.72, DECK_Y + 0.10, -1.12,  65.0, 82.0, False),
        ( 0.92, DECK_Y + 0.22, -1.20, -15.0, 72.0, False),
    )):
        with xf(mb, T(cx_l, cy_l, cz_l) @ R('Y', ry_l) @ R('X', rx_l)):
            torus(mb, 0.165, 0.048, 5, 4, 'glass' if is_gl else 'iron',
                  C_FLAME_MID if is_gl else (C_IRON_RUST_HI if ci % 2 == 0 else C_IRON_BRIGHT), False)

    # Lantern_VolcAnchor empty at the blazing seaward molten impact heart of the monolith!
    LANTERN_POS = Vector((-0.30, 3.72, -0.96))

    build(mb)

    add_empty('Lantern_VolcAnchor', LANTERN_POS)
    col_piece('col_volcanchor_base', col_pts)
    export_landmark_glb(outdir, 'volcanic_obsidian_anchor_monolith.glb')


HAVEN_RELICS_GENERATORS = [
    gen_pirate_harbour_clock_belltower,
    gen_ancient_celestial_moon_dial,
    gen_coastal_buccaneer_grog_stall,
    gen_volcanic_obsidian_anchor_monolith,
]
