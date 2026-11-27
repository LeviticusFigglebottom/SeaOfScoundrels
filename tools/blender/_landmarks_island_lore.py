# Sea of Scoundrels: 4 sculpted 3D Island Lore Landmarks (Wave I-13 / Pass I-Q6 — 54-Landmark Fleet!).
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

# Distillery copper, brick, rum amber, bottle glass, and beach sand
C_COPPER_HI     = srgb('#e88b4f')
C_COPPER_MID    = srgb('#c66232')
C_COPPER_DARK   = srgb('#82381c')
C_VERDIGRIS     = srgb('#3d8a78')
C_BRICK_HI      = srgb('#b85234')
C_BRICK_MID     = srgb('#8f3924')
C_BRICK_SOOT    = srgb('#3b2722')
C_COBBLE_LIGHT  = srgb('#cbbca2')
C_COBBLE_MID    = srgb('#928673')
C_COBBLE_DARK   = srgb('#5a534a')
C_OAK_FRESH     = srgb('#c48b50')
C_DRIFT_PALE    = srgb('#cfc1a8')
C_DRIFT_SHADE   = srgb('#786c5c')
C_BOTTLE_GREEN  = srgb('#1d5e3b')
C_BOTTLE_AMBER  = srgb('#9e5618')
C_CANE_PALE     = srgb('#c4b45c')
C_CANE_GREEN    = srgb('#6da136')
C_WATER_DEEP    = srgb('#0e323a')
C_WATER_MID     = srgb('#1a525c')
C_WATER_SPEC    = srgb('#32828a')

# Jade serpent totem stone, gilded gold, turquoise crystal, jungle vines & ferns
C_JADE_HI       = srgb('#7fa88e')
C_JADE_MID      = srgb('#4f7a66')
C_JADE_DARK     = srgb('#2c4a3e')
C_JADE_DEEP     = srgb('#1c332b')
C_GOLD_BRIGHT   = srgb('#f6c948')
C_BRASS_DARK    = srgb('#966a22')
C_RUNE_CORE     = srgb('#4cffe4')
C_RUNE_MID      = srgb('#16d6bc')
C_VINE_DARK     = srgb('#14481c')
C_VINE_MID      = srgb('#286e22')
C_VINE_SUN      = srgb('#72b826')
C_FERN_DARK     = srgb('#154c1e')
C_FERN_MID      = srgb('#2c7824')
C_FERN_TIP      = srgb('#7cbd2a')

# Coastal beach bivouac sand, terracotta & cream patched sailcloth, flame tones
C_SAND_PALE     = srgb('#f2e2c2')
C_SAND_WARM     = srgb('#dcb57e')
C_SAND_OCHRE    = srgb('#ae8858')
C_SAND_SHADE    = srgb('#7d6850')
C_TIDE_DARK     = mix(C_LIME_DARK, C_SEA_MOSS, 0.36)
C_CANVAS_CREAM  = srgb('#ebe0c4')
C_CANVAS_WARM   = srgb('#d8c498')
C_TERRA_HI      = srgb('#c95836')
C_TERRA_MID     = srgb('#9e3e22')
C_TEAL_BRIGHT   = srgb('#248d94')
C_CRIMSON_HI    = srgb('#c42e22')
C_ASH_DARK      = srgb('#2a2528')

# Volcanic magma, sulfur & flame accents
C_FLAME_CORE    = srgb('#ffe678')
C_FLAME_MID     = srgb('#ff8822')
C_FLAME_DEEP    = srgb('#d43412')
C_MAGMA_CRIMSON = srgb('#d92e10')
C_SULFUR_PALE   = srgb('#e3c84a')
C_SULFUR_OCHRE  = srgb('#b89426')
C_SULFUR_DARK   = srgb('#7d6218')


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


def _reg_poly(cx, y, cz, radius, sides=10, rot_deg=0.0, sx=1.0, sz=1.0):
    """Regular or elliptical N-sided polygon ring at height y centered at (cx, y, cz)."""
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
    """Emit a stepped or battered ashlar/stone foundation shaft with clean horizontal UV courses."""
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
            face_col = jit(col_i, rng, 0.038, 0.015)
            mb.fp([p00, p01, p11, p10], mat, face_col, grain=horiz, inside=c_mid, smooth=False)
    if caps[0] and n > 1:
        mb.fp(secs[0], mat, mul(scols[0], 0.72), (1, 0, 0), cents[1], smooth=False)
    if caps[1] and n > 1:
        tmat = top_mat if top_mat is not None else mat
        tcol = top_col if top_col is not None else scols[-1]
        mb.fp(secs[-1], tmat, tcol, (1, 0, 0), cents[-2], smooth=False)


def _build_flame_cluster(mb, center, radius=0.28, height=0.48, n_tongues=5):
    """Sculpted stylized low-poly warm glowing ember bed & flame tongues ('glass' + C_FLAME_*)."""
    cx, cy, cz = center
    with xf(mb, T(cx, cy, cz)):
        cyl(mb, radius * 0.90, -0.05, 0.07, 6, 'glass', C_FLAME_DEEP, False, 0.0, radius * 0.62)
        tongues = [
            ((0.0,           0.03,  0.0),          radius * 0.38, height * 1.00, ( 4.0,   0.0,  5.0), C_FLAME_CORE),
            ((-radius*0.32,  0.02, -radius*0.20),  radius * 0.25, height * 0.74, (-9.0,  22.0, 12.0), C_FLAME_MID),
            (( radius*0.30,  0.02,  radius*0.22),  radius * 0.24, height * 0.72, ( 8.0, -30.0,-10.0), C_FLAME_MID),
            (( radius*0.22,  0.01, -radius*0.30),  radius * 0.20, height * 0.58, (11.0,  42.0, -8.0), C_FLAME_DEEP),
            ((-radius*0.22,  0.01,  radius*0.28),  radius * 0.20, height * 0.60, (-10.0,-38.0, 10.0), C_FLAME_DEEP),
        ][:n_tongues]
        for tp, tr, th, trot, tcol in tongues:
            with xf(mb, T(tp) @ R('Y', trot[1]) @ R('X', trot[0]) @ R('Z', trot[2])):
                cyl(mb, tr, 0.0, th, 4, 'glass', tcol, False, 0.0, tr * 0.12)


def _build_coopered_cask(mb, M_bar, radius=0.32, height=0.80, rng=None,
                         col_a=C_TIMBER_MID, col_b=C_TIMBER_HI, col_head=C_TIMBER_DARK,
                         segs=6, stripe_col=None, spigot=False, open_top=False):
    """Chunky coopered pirate rum cask / worm-tub with forged iron hoops."""
    hh = height * 0.5
    if open_top:
        # Outward-wound open-top oak tub: bottom -> outer up -> top rim inward -> inner down!
        prof = [
            (0.0,           -hh),
            (radius * 0.84, -hh),
            (radius,         0.0),
            (radius * 0.88,  hh),
            (radius * 0.78,  hh),
            (radius * 0.78,  hh * 0.50),
            (0.0,            hh * 0.50),
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
        jit(col_a if k % 2 == 0 else col_b, rng, 0.07, 0.018) if rng else col_a
        for k in range(segs)
    ]
    with xf(mb, M_bar):
        lathe(mb, prof, segs, 'timber', col_a, False, False,
              lambda i, k: col_head if (i == 0 or (not open_top and i == 3) or (open_top and i >= 4)) else stave_cols[k])
        hoop_ys = ((-hh * 0.68, radius * 0.94), (0.0, radius * 1.01), (hh * 0.68, radius * 0.93)) if open_top \
                  else ((-hh * 0.62, radius * 0.94), (hh * 0.62, radius * 0.94))
        for hi_idx, (hy, hr) in enumerate(hoop_ys):
            cyl(mb, hr, hy - 0.028, hy + 0.028, segs, 'iron',
                C_IRON_RUST if hi_idx == 1 else C_IRON, False, 0.0)
        if stripe_col is not None:
            cyl(mb, radius * 1.015, -hh * 0.18, hh * 0.18, segs, 'paint', stripe_col, False, 0.0)
        if spigot:
            with xf(mb, T(0.0, hh + 0.01, 0.0)):
                cyl(mb, 0.030, -0.02, 0.14, 4, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.018)
            cbox(mb, (0.0, hh + 0.10, 0.04), (0.088, 0.024, 0.024), 'brass', C_GOLD_BRIGHT, 0.0)


def _build_stenciled_crate(mb, M_crate, size=(0.78, 0.66, 0.72), rng=None,
                           stripe_col=C_TEAL_BRIGHT, stencil_col=C_GOLD_BRIGHT, open_top=False):
    """Weathered pirate crate with timber battens, forged iron corner brackets & painted band."""
    sx, sy, sz = size
    hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
    with xf(mb, M_crate):
        if open_top:
            wt = 0.06
            cbox(mb, (0.0, -hy + wt * 0.5, 0.0), (sx, wt, sz), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
            for zs in (-hz + wt * 0.5, hz - wt * 0.5):
                cbox(mb, (0.0, 0.0, zs), (sx, sy, wt), 'timber', jit(C_TIMBER_MID, rng, 0.05) if rng else C_TIMBER_MID, 0.0, (1, 0, 0))
            for xs in (-hx + wt * 0.5, hx - wt * 0.5):
                cbox(mb, (xs, 0.0, 0.0), (wt, sy, sz - wt * 2.0), 'timber', jit(C_TIMBER_MID, rng, 0.05) if rng else C_TIMBER_MID, 0.0, (0, 0, 1))
        else:
            cbox(mb, (0.0, 0.0, 0.0), (sx, sy, sz), 'timber',
                 jit(C_TIMBER_MID, rng, 0.05) if rng else C_TIMBER_MID, 0.0, (1, 0, 0))
        for ys in (-hy + 0.050, hy - 0.050):
            for zs in (-hz - 0.012, hz + 0.012):
                cbox(mb, (0.0, ys, zs), (sx + 0.04, 0.082, 0.040), 'timber', C_TIMBER_HI, 0.0, (1, 0, 0))
            for xs in (-hx - 0.012, hx + 0.012):
                cbox(mb, (xs, ys, 0.0), (0.040, 0.082, sz + 0.02), 'timber', C_TIMBER_HI, 0.0, (0, 0, 1))
        for xs in (-hx - 0.012, hx + 0.012):
            for zs in (-hz - 0.012, hz + 0.012):
                cbox(mb, (xs, 0.0, zs), (0.058, sy + 0.02, 0.058), 'iron', C_IRON, 0.0)
        if stripe_col is not None:
            for zs in (-hz - 0.020, hz + 0.020):
                cbox(mb, (0.0, 0.0, zs), (sx * 0.64, 0.14, 0.014), 'paint', stripe_col, 0.0)
                if stencil_col is not None:
                    cbox(mb, (0.0, 0.0, zs + (0.009 if zs > 0 else -0.009)),
                         (0.13, 0.13, 0.010), 'paint', stencil_col, 0.0, M=R('Z', 45.0))


def _build_rope_coil_lean(mb, center, radius=0.28, turns=3, r=0.038, segs=6, psegs=4):
    """Chunky coiled braided hemp rope pile ('rope')."""
    for i in range(turns):
        rr = radius * (1.0 - 0.22 * i)
        with xf(mb, T(center[0], center[1] + r * (1.0 + i * 1.60), center[2])):
            torus(mb, rr, r, segs, psegs, 'rope', mul(C_ROPE, 0.88 + 0.12 * (i % 2)), True)


def _build_rum_bottle(mb, M_bot, scale=1.0, col=C_BOTTLE_GREEN, cork=True):
    """Lean stylized blown-glass pirate rum / message bottle (~56 tris, glossy non-emissive basalt)."""
    s = scale
    prof = [
        (0.0,       0.00 * s),
        (0.072 * s, 0.00 * s),
        (0.074 * s, 0.18 * s),
        (0.028 * s, 0.26 * s),
        (0.028 * s, 0.36 * s),
        (0.0,       0.36 * s),
    ]
    with xf(mb, M_bot):
        lathe(mb, prof, 5, 'basalt', col, False, False)
        if cork:
            cyl(mb, 0.022 * s, 0.34 * s, 0.415 * s, 4, 'timber', C_OAK_FRESH, False, 0.0, 0.018 * s)


def _add_water_disk(mb, center, radius, segs=6):
    """Recessed dark reflective turquoise-slate water surface ('basalt' sheen + radial ripple shading)."""
    cx, cy, cz = center
    r_mid = radius * 0.56
    c_ctr = Vector((cx, cy + 0.010, cz))
    ring_m = [Vector((cx + r_mid * cos(2.0 * pi * k / segs),
                      cy + 0.005 * sin(k * 2.0),
                      cz + r_mid * sin(2.0 * pi * k / segs))) for k in range(segs)]
    ring_o = [Vector((cx + radius * cos(2.0 * pi * k / segs),
                      cy - 0.006,
                      cz + radius * sin(2.0 * pi * k / segs))) for k in range(segs)]
    inside = Vector((cx, cy - 0.5, cz))
    mb.newoff()
    for k in range(segs):
        kn = (k + 1) % segs
        mb.fp([c_ctr, ring_m[kn], ring_m[k]], 'basalt',
              [C_WATER_SPEC, C_WATER_MID, C_WATER_MID], (1, 0, 0), inside, smooth=False)
        mb.fp([ring_m[k], ring_m[kn], ring_o[kn], ring_o[k]], 'basalt',
              [C_WATER_MID, C_WATER_MID, C_WATER_DEEP, C_WATER_DEEP], (1, 0, 0), inside, smooth=False)


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
        out_off = 0.04 + 0.12 * sin(t * pi * 0.78) + 0.06 * t
        stem_pts.append(a + od * out_off + side * sway + Vector((0.0, -length * t, 0.0)))

    for i in range(segs):
        t0 = i / float(segs)
        t1 = (i + 1) / float(segs)
        w0 = width * 0.24 * (1.0 - 0.50 * t0)
        w1 = width * 0.24 * (1.0 - 0.72 * t1)
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


def _add_jungle_fern_cluster(mb, root_pos, scale=1.0, n_fronds=4, rng=None, phase=0.0, lean_dir=None, segs=4):
    """Lush broad tropical jungle fern rosette ('foliage') with UV2 wind weights (0 root -> 0.92 tip)."""
    rp = Vector(root_pos)
    base_rot = rng.uniform(0.0, 2.0 * pi) if rng else 0.0
    for fi in range(n_fronds):
        ang = base_rot + 2.0 * pi * fi / float(n_fronds) + (rng.uniform(-0.22, 0.22) if rng else 0.0)
        f_len = scale * (rng.uniform(0.86, 1.16) if rng else 1.0)
        f_w = scale * (rng.uniform(0.24, 0.32) if rng else 0.28)
        f_arch_h = scale * (rng.uniform(0.44, 0.62) if rng else 0.52)
        f_droop = scale * (rng.uniform(0.22, 0.38) if rng else 0.30)
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


def _add_palm_frond(mb, root_pos, direction, length=1.35, width=0.42, droop=0.22,
                    rng=None, phase=0.0, col_base=C_FERN_DARK, col_tip=C_LEAF_SUN, segs=3):
    """Layered tropical palm-thatch frond ('foliage') with V-spine & UV2 wind flutter at overhanging tips."""
    rp = Vector(root_pos)
    d = Vector(direction).normalized()
    up = Vector((0.0, 1.0, 0.0))
    side = d.cross(up)
    if side.length < 1e-4:
        side = Vector((1.0, 0.0, 0.0))
    side.normalize()
    l_up = side.cross(d).normalized()
    prev_l = prev_m = prev_r = None
    for si in range(segs + 1):
        t = si / float(segs)
        w = width * (0.28 + 0.85 * sin(t * pi * 0.88)) * (1.0 - 0.78 * (t ** 2.0))
        # Subtle upward arch near root so frond rests cleanly ABOVE roof planks before drooping past eaves!
        ctr = rp + d * (length * t) + Vector((0.0, 0.10 * sin(t * pi * 0.85) - droop * (t ** 2.4), 0.0))
        pl = ctr - side * w - l_up * (w * 0.14)
        pr = ctr + side * w - l_up * (w * 0.14)
        pm = ctr + l_up * 0.03
        if prev_m is not None:
            t0 = (si - 1) / float(segs)
            c0 = jit(mix(col_base, col_tip, t0 * 0.72), rng, 0.05) if rng else col_base
            c1 = jit(mix(col_base, col_tip, 0.22 + t * 0.78), rng, 0.05) if rng else col_tip
            w0 = max(0.0, (t0 - 0.30) / 0.70) ** 1.4 * 0.88
            w1 = max(0.0, (t - 0.30) / 0.70) ** 1.4 * 0.88
            u2_0, u2_1 = (w0, phase), (w1, phase)
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


def _add_chain_links(mb, p_start, p_end, n_links=6, link_r=0.20, wire_r=0.062,
                     segs=6, psegs=4, sag=0.45, mat='iron', rust_stride=2, stretch_y=1.34):
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
        col = C_IRON_RUST if (k % rust_stride == 0) else C_IRON
        with xf(mb, T(pt) @ rot_q @ spin @ S(0.76, stretch_y, 0.76) @ M_Y2Z):
            torus(mb, link_r, wire_r, segs, psegs, mat, col, False)


def _sculpt_magma_ribbon(mb, path_pts, widths, surface_nrm, rng, hot_core=True):
    """Surface-hugging glowing molten magma vein ridge ('glass') crawling cleanly across basalt cracks."""
    pts = [Vector(p) for p in path_pts]
    nrm = Vector(surface_nrm).normalized()
    n = len(pts)
    if n < 2:
        return
    mb.newoff()
    left_pts, mid_pts, right_pts = [], [], []
    for i in range(n):
        t_dir = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)])
        if t_dir.length < 1e-5:
            t_dir = Vector((0.0, 0.0, -1.0))
        t_dir.normalize()
        side = t_dir.cross(nrm)
        if side.length < 1e-4:
            side = Vector((1.0, 0.0, 0.0))
        side.normalize()
        w = widths[i]
        left_pts.append(pts[i] - side * w - nrm * 0.02)
        right_pts.append(pts[i] + side * w - nrm * 0.02)
        mid_pts.append(pts[i] + nrm * (0.065 + 0.015 * sin(i * 1.9)))
    for i in range(n - 1):
        c_mid = C_FLAME_CORE if (hot_core and i == 0) else C_MAGMA_GLOW
        c_edge = C_MAGMA_CRIMSON if i < n - 2 else C_BASALT_HOT
        inside = (pts[i] + pts[i + 1]) * 0.5 - nrm * 0.5
        mb.fp([left_pts[i], mid_pts[i], mid_pts[i + 1], left_pts[i + 1]], 'glass',
              [c_edge, c_mid, c_mid, c_edge], (1, 0, 0), inside, smooth=False)
        mb.fp([mid_pts[i], right_pts[i], right_pts[i + 1], mid_pts[i + 1]], 'glass',
              [c_mid, c_edge, c_edge, c_mid], (1, 0, 0), inside, smooth=False)


def _build_wind_pennant(mb, root_pos, length=1.65, h0=0.42, out_dir=(0.75, -0.08, -0.65),
                        col_main=C_CRIMSON_HI, col_trim=C_ASH_DARK, phase=0.32):
    """Wind-whipped double-sided tattered banner/streamer ('paint') with UV2 wind weights."""
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
        droop = -0.22 * t * t
        hh = h0 * (1.0 - 0.52 * t)
        ctr = rp + od * (length * t) + side * wave + Vector((0.0, droop, 0.0))
        top_pts.append(ctr + Vector((0.0, hh * 0.5, 0.0)))
        bot_pts.append(ctr - Vector((0.0, hh * 0.5, 0.0)))
        weights.append((t ** 1.15) * 0.94)
    for i in range(segs):
        c_seg = col_trim if i == 0 else (col_main if i % 2 == 1 else mul(col_main, 0.72))
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


# ================================================================ 1. PIRATE RUM DISTILLERY SHACK

def gen_pirate_rum_distillery_shack(outdir):
    """Rickety pirate smuggler's copper-and-oak rum distillery lean-to (~5.0 m wide x 4.2 m deep x 4.2 m tall)
    anchored atop a deeply skirted cobbled stone plinth (y = -2.70..+0.12 m anti-float!).
    Weathered timber post frame supporting a slanted corrugated-plank & palm-frond lean-to roof
    ('foliage' + UV2 wind!), brick-and-stone arched fire furnace ('Lantern_Still' inside glowing hearth!),
    gleaming hammered brass/copper bulbous alembic still pot with curved swan-neck pipe spiraling into an
    oak cooling barrel worm-tub, dripping rum spout filling iron-hooped rum casks, stacked sugar-cane crates,
    coiled hemp rope, painted skull rum-signboard, and hanging rum bottles!
    Target: 2,900-3,600 visual tris, 1 collider (col_still_base).
    """
    clear_scene()
    rng = random.Random(SEED + 2601)
    mb = MB('PirateRumDistilleryShack', seed=2601)

    SKIRT_BOT = -2.70
    PLINTH_Y = 0.12
    col_pts = []

    # 1. Deeply Skirted Cobbled Stone Plinth (y = -2.70..+0.12 m, ~5.0 m wide x 4.2 m deep!)
    plinth_secs = [
        _rect_oct(0.0, SKIRT_BOT, 0.0, 2.68, 2.26, 0.52),
        _rect_oct(0.0, -0.95,     0.0, 2.54, 2.12, 0.48),
        _rect_oct(0.0, PLINTH_Y,  0.0, 2.40, 1.98, 0.44),
    ]
    _loft_horizontal_masonry(
        mb, plinth_secs, 'limestone_moss',
        [C_TIDE_DARK, C_COBBLE_DARK, C_COBBLE_MID],
        rng, caps=(True, True), top_mat='limestone_moss', top_col=C_COBBLE_MID,
    )
    for ring in plinth_secs:
        col_pts.extend(Vector(p) for p in ring)

    # Dressed perimeter curb stones & proud cobbled flagstones across the distillery floor
    for sx in (-2.28, 2.28):
        for kz in (-0.90, 0.90):
            cbox(mb, (sx, PLINTH_Y + 0.025, kz), (0.28, 0.12, 1.48),
                 'limestone_moss' if kz > 0 else 'limestone', jit(C_COBBLE_LIGHT, rng, 0.06), 0.0)
    for sz in (-1.88, 1.88):
        for kx in (-1.10, 1.10):
            cbox(mb, (kx, PLINTH_Y + 0.025, sz), (1.92, 0.12, 0.26),
                 'limestone' if kx > 0 else 'limestone_moss', jit(C_COBBLE_MID, rng, 0.06), 0.0)
    for cx_p, cz_p, pw, pd, pyaw in (
        (-0.08, -1.08, 0.80, 0.60,  8.0),
        ( 0.88, -1.20, 0.68, 0.52, -12.0),
        (-1.24, -1.14, 0.70, 0.52, 14.0),
        ( 0.16,  0.22, 0.76, 0.58, -6.0),
    ):
        cbox(mb, (cx_p, PLINTH_Y + 0.015, cz_p), (pw, 0.055, pd),
             'temple_stone', jit(C_COBBLE_LIGHT, rng, 0.07), 0.0, M=R('Y', pyaw))

    # 2. Rickety Weathered Timber Post Frame + Rear Half-Wall + Diagonal Braces
    # High open seaward front (y = 3.68 m) sloping down to rear (y = 2.92 m) -> generous headroom above still!
    POST_FL = Vector((-2.02, 3.68, -1.44))
    POST_FR = Vector(( 2.02, 3.62, -1.44))
    POST_BL = Vector((-2.00, 2.92,  1.40))
    POST_BR = Vector(( 2.00, 2.88,  1.40))
    POST_BM = Vector(( 0.00, 2.90,  1.44))

    for pt, tilt_x, tilt_z in (
        (POST_FL, -0.05, -0.04),
        (POST_FR,  0.06, -0.03),
        (POST_BL, -0.04,  0.05),
        (POST_BR,  0.05,  0.04),
        (POST_BM,  0.01,  0.03),
    ):
        p_bot = Vector((pt.x, PLINTH_Y - 0.12, pt.z))
        p_top = Vector((pt.x + tilt_x, pt.y, pt.z + tilt_z))
        _add_beam(mb, p_bot, p_top, 0.19, 0.19, 'timber', jit(C_TIMBER_MID, rng, 0.06), 0.0)
        cbox(mb, (pt.x, PLINTH_Y + 0.15, pt.z), (0.24, 0.14, 0.24), 'iron', C_IRON_RUST, 0.0)
        col_pts.append(p_top)

    # Top header beams & diagonal knee braces
    _add_beam(mb, POST_FL + Vector((-0.34, 0.0, -0.04)), POST_FR + Vector((0.34, 0.0, -0.03)),
              0.17, 0.19, 'timber', C_TIMBER_HI, 0.0)
    _add_beam(mb, POST_BL + Vector((-0.30, 0.0,  0.05)), POST_BR + Vector((0.30, 0.0,  0.04)),
              0.16, 0.17, 'timber', C_TIMBER_DARK, 0.0)
    _add_beam(mb, POST_FL + Vector((-0.05, -0.04, -0.34)), POST_BL + Vector((-0.04, 0.02, 0.34)),
              0.15, 0.16, 'timber', C_TIMBER_MID, 0.0)
    _add_beam(mb, POST_FR + Vector(( 0.06, -0.04, -0.34)), POST_BR + Vector(( 0.05, 0.02, 0.34)),
              0.15, 0.16, 'timber', C_TIMBER_MID, 0.0)
    _add_beam(mb, (-2.02, 2.94, -1.44), (-1.42, 3.64, -1.44), 0.11, 0.11, 'timber', C_TIMBER_DARK, 0.0)
    _add_beam(mb, ( 2.02, 2.88, -1.44), ( 1.44, 3.58, -1.44), 0.11, 0.11, 'timber', C_TIMBER_DARK, 0.0)
    _add_beam(mb, (-2.02, 2.86, -1.44), (-2.01, 3.44, -0.78), 0.10, 0.11, 'timber', C_TIMBER_HI, 0.0)
    _add_beam(mb, ( 2.02, 2.80, -1.44), ( 2.01, 3.38, -0.78), 0.10, 0.11, 'timber', C_TIMBER_HI, 0.0)
    # Rope lashings at the front two hero post joints
    for jp in (POST_FL, POST_FR):
        with xf(mb, T(jp + Vector((0.0, -0.04, 0.0))) @ R('X', 38.0) @ R('Z', 24.0)):
            torus(mb, 0.16, 0.028, 6, 4, 'rope', C_ROPE, False)

    # Rickety weathered timber plank rear half-wall & starboard slatted windbreak
    for pi_w in range(4):
        wy = PLINTH_Y + 0.28 + pi_w * 0.38
        pcol = jit(C_TIMBER_DARK if pi_w % 2 == 0 else C_DRIFTWOOD, rng, 0.06)
        cbox(mb, (0.0, wy, 1.46), (4.06, 0.28, 0.065), 'timber', pcol, 0.0, (1, 0, 0), M=R('Z', rng.uniform(-1.5, 1.5)))
    for wy in (PLINTH_Y + 0.44, PLINTH_Y + 0.92):
        cbox(mb, (2.02, wy, 0.24), (0.065, 0.21, 2.42), 'timber', jit(C_DRIFTWOOD, rng, 0.06), 0.0, (0, 0, 1))
    _add_beam(mb, (2.02, PLINTH_Y + 0.14, 1.38), (2.02, 1.68, -0.25), 0.08, 0.12, 'timber', C_TIMBER_DARK, 0.0)

    # 3. Slanted Corrugated-Plank Timber & Palm-Frond Lean-To Roof ('foliage' + UV2 wind!)
    # Roof plane: z from -1.94 (y=3.92) down to +1.84 (y=2.84) — ~16 deg slope with clean headroom!
    def _roof_y(x, z):
        tz = (z + 1.94) / 3.78
        return 3.92 * (1.0 - tz) + 2.84 * tz - 0.025 * abs(x)

    for rx in (-2.02, -0.68, 0.68, 2.02):
        _add_beam(mb, (rx, _roof_y(rx, -1.92) - 0.09, -1.92),
                  (rx, _roof_y(rx,  1.84) - 0.09,  1.84), 0.11, 0.13, 'timber', C_TIMBER_DARK, 0.0)

    roof_pitch = degrees(atan2(3.92 - 2.84, 3.78))
    for ci in range(8):
        u = ci / 7.0
        zc = -1.80 + u * 3.50
        yc = _roof_y(0.0, zc) + 0.02 + (0.020 if ci % 2 == 0 else 0.0)
        pcol = jit(C_TIMBER_MID if ci % 2 == 0 else C_DRIFTWOOD, rng, 0.07)
        if ci in (5, 6):
            # Split plank cleanly around the brick chimney shaft at x ≈ -1.16, z ≈ +0.62!
            cbox(mb, (-2.04, yc, zc), (0.86, 0.055, 0.52), 'timber', pcol, 0.0, (1, 0, 0), M=R('X', roof_pitch))
            cbox(mb, ( 0.84, yc, zc), (3.18, 0.055, 0.52), 'timber', pcol, 0.0, (1, 0, 0), M=R('X', roof_pitch))
        else:
            cbox(mb, (0.0, yc, zc), (4.84, 0.055, 0.52), 'timber', pcol, 0.0, (1, 0, 0),
                 M=R('X', roof_pitch) @ R('Y', rng.uniform(-1.0, 1.0)))
        if ci in (1, 4, 7):
            cbox(mb, (0.0, yc + 0.042, zc), (4.74, 0.045, 0.08), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0),
                 M=R('X', roof_pitch))

    # Lush overlapping tropical palm-frond thatch bundles resting cleanly ABOVE the slanted roof planks!
    frond_specs = [
        # Front overhanging eaves (rooted atop planks, sloping slightly UP then drooping over front eaves!)
        (-1.68, -1.12, (-0.18,  0.26, -0.95), 1.38, 0.48, 0.34, 0.08),
        (-0.74, -1.16, ( 0.06,  0.28, -0.96), 1.44, 0.50, 0.36, 0.24),
        ( 0.24, -1.14, (-0.08,  0.28, -0.96), 1.46, 0.50, 0.36, 0.41),
        ( 1.24, -1.12, ( 0.14,  0.26, -0.95), 1.42, 0.48, 0.34, 0.59),
        # Rear sloping palm-thatch layers seated cleanly ABOVE roof planks (sloping along roof pitch!)
        (-0.18,  0.34, (-0.08, -0.24,  0.96), 1.56, 0.52, 0.24, 0.73),
        ( 0.94,  0.32, ( 0.10, -0.24,  0.96), 1.52, 0.50, 0.24, 0.87),
        # Starboard side eaves overhang frond
        ( 1.72, -0.35, ( 0.92, -0.02, -0.36), 1.20, 0.42, 0.32, 0.32),
    ]
    for fx, fz, fdir, flen, fw, fdr, fph in frond_specs:
        fy = _roof_y(fx, fz) + 0.12  # sits cleanly above the corrugated timber roof surface!
        _add_palm_frond(mb, (fx, fy, fz), fdir, flen, fw, fdr, rng=rng, phase=fph,
                        col_base=C_FERN_DARK, col_tip=C_LEAF_SUN, segs=3)

    # 4. Brick-and-Stone Arched Fire Furnace + Chimney Stack ('Lantern_Still' inside glowing hearth!)
    FURN_X, FURN_Z = -0.94, 0.06
    FURN_TOP = 1.08
    furn_secs = [
        _reg_poly(FURN_X, PLINTH_Y - 0.04, FURN_Z, 0.82, sides=6, rot_deg=30.0),
        _reg_poly(FURN_X, 0.60,            FURN_Z, 0.78, sides=6, rot_deg=30.0),
        _reg_poly(FURN_X, FURN_TOP,        FURN_Z, 0.74, sides=6, rot_deg=30.0),
    ]
    _loft_horizontal_masonry(
        mb, furn_secs, 'temple_stone',
        [C_BRICK_SOOT, C_BRICK_MID, C_BRICK_HI],
        rng, caps=(False, True), top_mat='temple_stone', top_col=C_BRICK_SOOT,
    )
    with xf(mb, T(FURN_X, FURN_TOP, FURN_Z)):
        cyl(mb, 0.79, -0.06, 0.08, 6, 'limestone', C_COBBLE_MID, False, 0.0, 0.76)
        cyl(mb, 0.80, -0.44, -0.36, 6, 'iron', C_IRON_RUST, False, 0.0)

    # Projecting arched brick firebox portal facing seaward (-Z) + glowing hearth flames ('Lantern_Still'!)
    FB_Z = FURN_Z - 0.64
    for sx in (-0.33, 0.33):
        cbox(mb, (FURN_X + sx, PLINTH_Y + 0.34, FB_Z), (0.19, 0.68, 0.32), 'temple_stone',
             jit(C_BRICK_MID, rng, 0.06), 0.0)
    cbox(mb, (FURN_X, PLINTH_Y + 0.07, FB_Z - 0.16), (0.94, 0.14, 0.40), 'limestone', C_COBBLE_LIGHT, 0.0)
    for vk in range(5):
        ang = radians(-68.0 + vk * 34.0)
        vx = FURN_X + sin(ang) * 0.35
        vy = PLINTH_Y + 0.66 + cos(ang) * 0.25
        vcol = C_COBBLE_LIGHT if vk == 2 else jit(C_BRICK_HI, rng, 0.06)
        cbox(mb, (vx, vy, FB_Z - 0.02), (0.18, 0.15, 0.34), 'temple_stone', vcol, 0.0, M=R('Z', -degrees(ang)))
    cbox(mb, (FURN_X, PLINTH_Y + 0.40, FB_Z + 0.08), (0.48, 0.56, 0.14), 'basalt', C_BRICK_SOOT, 0.0)
    for lx_l, lyaw_l in ((-0.09, 24.0), (0.09, -24.0)):
        with xf(mb, T(FURN_X + lx_l, PLINTH_Y + 0.20, FB_Z - 0.04) @ R('Y', lyaw_l) @ M_Y2Z):
            cyl(mb, 0.052, -0.20, 0.20, 4, 'timber', C_BRICK_SOOT, False, 0.0)
    HEARTH_POS = Vector((FURN_X, PLINTH_Y + 0.36, FB_Z - 0.06))
    _build_flame_cluster(mb, (FURN_X, PLINTH_Y + 0.22, FB_Z - 0.04), radius=0.25, height=0.40, n_tongues=4)

    # Rear-port tapered brick chimney flue rising cleanly through roof slot to y = 4.24 m!
    CHIM_X, CHIM_Z = -1.16, 0.62
    chim_secs = [
        _reg_poly(CHIM_X, 0.78, CHIM_Z, 0.33, sides=6, rot_deg=30.0),
        _reg_poly(CHIM_X, 2.35, CHIM_Z, 0.27, sides=6, rot_deg=30.0),
        _reg_poly(CHIM_X, 3.88, CHIM_Z, 0.23, sides=6, rot_deg=30.0),
    ]
    _loft_horizontal_masonry(
        mb, chim_secs, 'temple_stone',
        [C_BRICK_MID, C_BRICK_HI, C_BRICK_SOOT], rng, caps=(False, True), top_col=C_BRICK_SOOT,
    )
    _add_beam(mb, (FURN_X - 0.10, 0.88, FURN_Z + 0.36), (CHIM_X, 1.24, CHIM_Z), 0.40, 0.40, 'temple_stone', C_BRICK_MID, 0.0)
    for cy_b, cr_b in ((2.15, 0.295), (3.45, 0.258)):
        with xf(mb, T(CHIM_X, cy_b, CHIM_Z)):
            cyl(mb, cr_b, -0.04, 0.04, 6, 'iron', C_IRON_RUST, False, 0.0)
    with xf(mb, T(CHIM_X, 3.88, CHIM_Z)):
        cyl(mb, 0.27, -0.04, 0.08, 6, 'iron', C_IRON, False, 0.0, 0.25)
        for k in range(3):
            ang = radians(30.0 + k * 120.0)
            cbox(mb, (cos(ang) * 0.19, 0.17, sin(ang) * 0.19), (0.04, 0.24, 0.04), 'iron', C_IRON, 0.0)
        with xf(mb, T(0.0, 0.26, 0.0) @ R('Z', 6.0)):
            cyl(mb, 0.33, 0.0, 0.14, 6, 'iron', C_IRON_RUST, False, 0.0, 0.04)
    col_pts.append(Vector((CHIM_X, 4.24, CHIM_Z)))

    # 5. Gleaming Hammered Copper/Brass Bulbous Alembic Still Pot + Curved Swan-Neck & Spiral Condenser!
    #    Positioned cleanly UNDER the slanted roof with ~0.40 m clearance (ZERO roof poke-through!)
    with xf(mb, T(FURN_X, FURN_TOP + 0.04, FURN_Z)):
        alembic_prof = [
            (0.00, 0.00),
            (0.56, 0.00),
            (0.70, 0.34),
            (0.60, 0.72),
            (0.38, 0.88),
            (0.45, 0.94),  # riveted copper flange collar
            (0.36, 1.02),
            (0.44, 1.22),  # bulbous onion-head helmet cap
            (0.24, 1.44),
            (0.11, 1.54),
            (0.00, 1.56),
        ]
        def _copper_col(i, k):
            if i in (4, 5):
                return C_VERDIGRIS if k % 3 == 0 else C_COPPER_DARK
            if i in (7, 8):
                return C_COPPER_HI
            if i == 1:
                return mix(C_COPPER_DARK, C_COPPER_MID, 0.5)
            return C_COPPER_MID if k % 2 == 0 else C_COPPER_HI
        lathe(mb, alembic_prof, 8, 'brass', C_COPPER_MID, True, False, _copper_col)
        # Riveted brass pressure gauge dial on front of pot belly
        with xf(mb, T(0.0, 0.46, -0.68) @ R('X', 90.0)):
            cyl(mb, 0.14, 0.0, 0.055, 6, 'brass', C_GOLD_BRIGHT, False, 0.0)
            cyl(mb, 0.09, 0.04, 0.072, 6, 'paint', C_PAINT_CREAM, False, 0.0)
            cbox(mb, (0.02, 0.075, 0.0), (0.07, 0.014, 0.016), 'iron', C_IRON, 0.0, M=R('Y', 32.0))

    # Oak Cooling Barrel Worm-Tub seated on a sturdy timber cradle stand on starboard side!
    TUB_X, TUB_Z = 0.78, 0.08
    TUB_STAND_H = 0.42
    for sx in (-0.42, 0.42):
        for sz in (-0.38, 0.38):
            cbox(mb, (TUB_X + sx, PLINTH_Y + TUB_STAND_H * 0.5, TUB_Z + sz),
                 (0.14, TUB_STAND_H + 0.06, 0.14), 'timber', C_TIMBER_DARK, 0.0)
    cbox(mb, (TUB_X, PLINTH_Y + TUB_STAND_H, TUB_Z), (1.06, 0.12, 1.02), 'timber', C_TIMBER_MID, 0.0)
    TUB_Y_BOT = PLINTH_Y + TUB_STAND_H + 0.04
    TUB_H = 1.20
    TUB_R = 0.56
    _build_coopered_cask(
        mb, T(TUB_X, TUB_Y_BOT + TUB_H * 0.5, TUB_Z),
        radius=TUB_R, height=TUB_H, rng=rng,
        col_a=C_TIMBER_MID, col_b=C_OAK_FRESH, col_head=C_TIMBER_DARK,
        segs=7, open_top=True,
    )
    _add_water_disk(mb, (TUB_X, TUB_Y_BOT + TUB_H * 0.88, TUB_Z), TUB_R * 0.78, segs=7)

    # Graceful curved copper swan-neck condenser pipe arcing cleanly BELOW the roof (peak y = 2.94 m < roof 3.30 m!)
    swan_path = [
        Vector((FURN_X,        FURN_TOP + 1.54, FURN_Z)),
        Vector((FURN_X + 0.14, FURN_TOP + 1.82, FURN_Z)),
        Vector((-0.34,         FURN_TOP + 1.86, FURN_Z)),
        Vector(( 0.18,         FURN_TOP + 1.62, TUB_Z)),
        Vector(( 0.62,         TUB_Y_BOT + TUB_H + 0.24, TUB_Z - 0.05)),
        Vector((TUB_X + 0.18,  TUB_Y_BOT + TUB_H - 0.04, TUB_Z - 0.14)),
    ]
    swan_rads = [0.090, 0.078, 0.068, 0.058, 0.048, 0.042]
    swan_cols = [C_COPPER_HI, C_COPPER_HI, C_COPPER_MID, C_COPPER_HI, C_COPPER_MID, C_COPPER_DARK]
    tube(mb, swan_path, swan_rads, 5, 'brass', C_COPPER_HI, caps=(True, True), mode='smooth', scols=swan_cols)
    with xf(mb, T(-0.34, FURN_TOP + 1.86, FURN_Z) @ R('Z', -16.0)):
        cyl(mb, 0.092, -0.045, 0.045, 6, 'brass', C_GOLD_BRIGHT, False, 0.0)

    # Visible spiraling copper worm-coil plunging into the top cooling water of the worm-tub!
    coil_pts = []
    n_coil = 11
    for ci in range(n_coil):
        t = ci / float(n_coil - 1)
        ang = t * 2.0 * pi * 1.75 - 0.6
        rr = 0.25 - 0.02 * t
        cy_c = (TUB_Y_BOT + TUB_H + 0.04) - t * 0.44
        coil_pts.append(Vector((TUB_X + cos(ang) * rr, cy_c, TUB_Z + sin(ang) * rr)))
    tube(mb, coil_pts, 0.036, 4, 'brass', C_COPPER_HI, caps=(True, True), mode='smooth')

    # 6. Dripping Rum Spout Filling Iron-Hooped Oak Rum Casks!
    CATCH_X, CATCH_Z = 0.96, -0.80
    _build_coopered_cask(
        mb, T(CATCH_X, PLINTH_Y + 0.36, CATCH_Z),
        radius=0.29, height=0.72, rng=rng, segs=6, stripe_col=C_PAINT_RED,
    )
    with xf(mb, T(CATCH_X, PLINTH_Y + 0.72, CATCH_Z)):
        cyl(mb, 0.035, -0.02, 0.08, 5, 'brass', C_COPPER_DARK, False, 0.0, 0.13)
    spout_p0 = Vector((TUB_X + 0.14, TUB_Y_BOT + 0.42, TUB_Z - TUB_R + 0.04))
    spout_p1 = Vector((CATCH_X,      PLINTH_Y + 0.88,  CATCH_Z + 0.02))
    tube(mb, [spout_p0, spout_p0.lerp(spout_p1, 0.5) + Vector((0.0, 0.03, 0.0)), spout_p1],
         [0.042, 0.032, 0.026], 4, 'brass', C_GOLD_BRIGHT, caps=(True, True), mode='flat')
    with xf(mb, T(CATCH_X, 0.0, CATCH_Z)):
        cyl(mb, 0.015, PLINTH_Y + 0.75, spout_p1.y - 0.02, 4, 'glass', C_LANTERN_GL, False, 0.0, 0.010)

    _build_coopered_cask(
        mb, T(1.62, PLINTH_Y + 0.41, -0.34) @ R('Y', -24.0),
        radius=0.31, height=0.82, rng=rng, segs=5, stripe_col=C_TEAL_BRIGHT, spigot=True,
    )
    for cz_w in (0.94, 1.28):
        cbox(mb, (1.42, PLINTH_Y + 0.07, cz_w), (0.64, 0.14, 0.10), 'timber', C_TIMBER_DARK, 0.0)
    _build_coopered_cask(
        mb, T(1.42, PLINTH_Y + 0.38, 1.11) @ R('Y', 18.0) @ R('Z', 90.0),
        radius=0.30, height=0.78, rng=rng, segs=5, stripe_col=C_PAINT_RED, spigot=True,
    )

    # 7. Stacked Sugar-Cane Crates, Coiled Hemp Rope, Painted Skull Rum-Signboard & Hanging Bottles!
    _build_stenciled_crate(
        mb, T(-1.66, PLINTH_Y + 0.34, -0.82) @ R('Y', 16.0),
        size=(0.74, 0.66, 0.68), rng=rng, stripe_col=C_PAINT_RED, stencil_col=C_GOLD_BRIGHT,
    )
    _build_stenciled_crate(
        mb, T(-1.62, PLINTH_Y + 0.96, -0.80) @ R('Y', -8.0),
        size=(0.64, 0.56, 0.58), rng=rng, stripe_col=C_TEAL_BRIGHT, stencil_col=None, open_top=True,
    )
    for sc_x, sc_z, sc_len, sc_rx, sc_rz, sc_c in (
        (-1.74, -0.88, 0.92, -14.0,  16.0, C_CANE_GREEN),
        (-1.64, -0.74, 1.04,  10.0,  -8.0, C_CANE_PALE),
        (-1.54, -0.86, 0.88, -18.0, -14.0, C_CANE_GREEN),
        (-1.58, -0.68, 0.96,  14.0,  12.0, C_CANE_PALE),
    ):
        with xf(mb, T(sc_x, PLINTH_Y + 0.82, sc_z) @ R('X', sc_rx) @ R('Z', sc_rz)):
            cyl(mb, 0.036, 0.0, sc_len, 4, 'foliage', sc_c, False, 0.0, 0.026)

    _build_rope_coil_lean(mb, (-0.16, PLINTH_Y, -1.46), radius=0.26, turns=2, r=0.042, segs=6, psegs=4)

    # Painted Skull Rum-Signboard hanging from a front-starboard timber jib-arm!
    SIGN_ARM_Y = 3.30
    _add_beam(mb, (2.02, SIGN_ARM_Y, -1.44), (2.78, SIGN_ARM_Y + 0.06, -1.50), 0.095, 0.095, 'timber', C_TIMBER_HI, 0.0)
    _add_beam(mb, (2.02, SIGN_ARM_Y - 0.52, -1.44), (2.52, SIGN_ARM_Y + 0.02, -1.48), 0.075, 0.075, 'timber', C_TIMBER_DARK, 0.0)
    for sx_r in (2.22, 2.66):
        _add_beam(mb, (sx_r, SIGN_ARM_Y + 0.04, -1.48), (sx_r, SIGN_ARM_Y - 0.24, -1.48), 0.026, 0.026, 'iron', C_IRON, 0.0)
    SIGN_CTR = Vector((2.44, SIGN_ARM_Y - 0.56, -1.48))
    with xf(mb, T(SIGN_CTR) @ R('Y', -8.0) @ R('Z', 3.0)):
        cbox(mb, (0.0, 0.0, 0.0), (0.74, 0.62, 0.068), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
        cbox(mb, (0.0, 0.0, 0.0), (0.64, 0.52, 0.078), 'paint', C_PAINT_RED, 0.0)
        for sz_f in (-0.044, 0.044):
            cbox(mb, (0.0,  0.07, sz_f), (0.24, 0.22, 0.022), 'skull_stone', C_SKULL_BONE, 0.0)
            cbox(mb, (0.0, -0.06, sz_f), (0.14, 0.10, 0.022), 'skull_stone', C_SKULL_MID, 0.0)
            for ex in (-0.055, 0.055):
                cbox(mb, (ex, 0.08, sz_f + (0.012 if sz_f > 0 else -0.012)), (0.048, 0.048, 0.012), 'basalt', C_SKULL_CAV, 0.0)
            for ang_b in (-26.0, 26.0):
                cbox(mb, (0.0, -0.14, sz_f), (0.42, 0.042, 0.018), 'skull_stone', C_SKULL_BONE, 0.0, M=R('Z', ang_b))

    # Hanging blown-glass rum bottles dangling on hemp twine from the front eaves beam + 2 resting on cask!
    for bx_h, blen_h, bcol_h in (
        (-0.82, 0.42, C_BOTTLE_GREEN),
        (-0.42, 0.56, C_BOTTLE_AMBER),
        ( 0.36, 0.50, C_BOTTLE_AMBER),
        ( 0.76, 0.38, C_BOTTLE_GREEN),
    ):
        top_p = Vector((bx_h, 3.58, -1.44))
        bot_p = Vector((bx_h, 3.58 - blen_h, -1.44))
        _add_beam(mb, top_p, bot_p, 0.016, 0.016, 'rope', C_ROPE, 0.0)
        _build_rum_bottle(mb, T(bot_p - Vector((0.0, 0.34, 0.0))) @ R('Z', rng.uniform(-7, 7)),
                          scale=1.06, col=bcol_h, cork=True)
    _build_rum_bottle(mb, T(1.56, PLINTH_Y + 0.82, -0.28) @ R('Y', 12.0), scale=1.0, col=C_BOTTLE_GREEN)
    _build_rum_bottle(mb, T(1.70, PLINTH_Y + 0.82, -0.40) @ R('Y', -35.0), scale=0.92, col=C_BOTTLE_AMBER)

    build(mb)

    add_empty('Lantern_Still', HEARTH_POS)
    col_piece('col_still_base', col_pts)
    export_landmark_glb(outdir, 'pirate_rum_distillery_shack.glb')


# ================================================================ 2. ANCIENT JADE SERPENT TOTEM

def gen_ancient_jade_serpent_totem(outdir):
    """Towering ~6.8 m tall carved mossy jade temple-stone sea-serpent & kraken-coil obelisk monolith
    rooted on a stepped circular ancient stone dais (y = -3.40..+0.65 m deep anti-float skirt!).
    Sculpted coiled serpentine stone column rising to an open-jawed horned sea-serpent head gripping a
    radiant faceted turquoise crystal orb ('skull_glow' + 'Lantern_Serpent'!), inlaid gilded brass
    wave-rune rings & ceremonial gold collar bands, offering stone bowl, wind-swaying draped jungle
    vines & base ferns ('foliage' + UV2 wind!), and cracked mossy rubble blocks!
    Target: 2,900-3,600 visual tris, 1 collider (col_serpent_base).
    """
    clear_scene()
    rng = random.Random(SEED + 2617)
    mb = MB('AncientJadeSerpentTotem', seed=2617)

    SKIRT_BOT = -3.40
    DAIS_Y1 = 0.24
    DAIS_Y2 = 0.46
    DAIS_Y3 = 0.65
    col_pts = []

    # 1. Stepped Circular Ancient Stone Dais (y = -3.40..+0.65 m deep anti-float skirt!)
    t1_secs = [
        _reg_poly(0.0, SKIRT_BOT, 0.0, 2.78, sides=10, rot_deg=18.0),
        _reg_poly(0.0, -1.50,     0.0, 2.54, sides=10, rot_deg=18.0),
        _reg_poly(0.0, -0.10,     0.0, 2.38, sides=10, rot_deg=18.0),
        _reg_poly(0.0, DAIS_Y1,   0.0, 2.28, sides=10, rot_deg=18.0),
    ]
    _loft_horizontal_masonry(
        mb, t1_secs, 'temple_stone',
        [C_JADE_DEEP, mix(C_JADE_DARK, C_SEA_MOSS, 0.45), C_JADE_DARK, C_JADE_MID],
        rng, caps=(True, True), top_mat='limestone_moss', top_col=mix(C_JADE_MID, C_LEDGE_MOSS, 0.38),
    )
    for ring in t1_secs:
        col_pts.extend(Vector(p) for p in ring)

    t2_secs = [
        _reg_poly(0.0, DAIS_Y1 - 0.06, 0.0, 1.98, sides=10, rot_deg=0.0),
        _reg_poly(0.0, DAIS_Y2,        0.0, 1.88, sides=10, rot_deg=0.0),
    ]
    _loft_horizontal_masonry(
        mb, t2_secs, 'temple_stone', [C_JADE_DARK, C_JADE_MID],
        rng, caps=(False, True), top_mat='temple_stone', top_col=C_JADE_HI,
    )

    t3_secs = [
        _reg_poly(0.0, DAIS_Y2 - 0.05, 0.0, 1.48, sides=8, rot_deg=22.5),
        _reg_poly(0.0, DAIS_Y3,        0.0, 1.38, sides=8, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, t3_secs, 'temple_stone', [C_JADE_MID, C_JADE_HI],
        rng, caps=(False, True), top_mat='temple_stone', top_col=C_JADE_HI,
    )

    with xf(mb, T(0.0, DAIS_Y3 + 0.018, 0.0)):
        torus(mb, 1.24, 0.042, 10, 4, 'brass', C_GOLD_BRIGHT, False)

    for si, (sy, sz, sw) in enumerate(((0.18, -2.28, 1.36), (0.38, -1.94, 1.20), (0.58, -1.62, 1.06))):
        cbox(mb, (0.0, sy - 0.14, sz), (sw, 0.34, 0.42), 'temple_stone',
             jit(C_JADE_HI if si == 2 else C_JADE_MID, rng, 0.05), 0.0)

    # 2. Carved Mossy Jade Temple-Stone Obelisk Core Monolith + Solid Sculpted Neck Capital (y = 0.60..5.52 m!)
    ob_secs = [
        _reg_poly(0.0, DAIS_Y3 - 0.06, 0.06, 0.84, sides=8, rot_deg=22.5),
        _reg_poly(0.0, 1.95,           0.06, 0.74, sides=8, rot_deg=22.5),
        _reg_poly(0.0, 3.45,           0.06, 0.64, sides=8, rot_deg=22.5),
        _reg_poly(0.0, 4.92,           0.06, 0.56, sides=8, rot_deg=22.5),
        _reg_poly(0.0, 5.48,           0.00, 0.48, sides=8, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, ob_secs, 'temple_stone',
        [C_JADE_DARK, C_JADE_MID, C_JADE_HI, C_JADE_HI, C_JADE_MID],
        rng, caps=(False, True), top_mat='temple_stone', top_col=C_JADE_HI,
    )
    # Stepped carved capital collar seamlessly wedding the monolith summit into the serpent head (ZERO rear gap!)
    with xf(mb, T(0.0, 5.06, 0.04)):
        cyl(mb, 0.64, -0.10, 0.14, 8, 'temple_stone', C_JADE_HI, False, 0.0, 0.56)
        torus(mb, 0.62, 0.036, 8, 4, 'brass', C_GOLD_BRIGHT, False)
    col_pts.extend(Vector(p) for p in _reg_poly(0.0, 6.80, 0.0, 0.74, sides=6, rot_deg=0.0))

    # 3. Inlaid Gilded Brass Wave-Rune Rings & Ceremonial Gold Collar Bands
    for ry, rr_c, rh, n_studs in (
        (1.48, 0.80, 0.14, 8),
        (2.88, 0.70, 0.14, 8),
        (4.32, 0.62, 0.16, 8),
    ):
        with xf(mb, T(0.0, ry, 0.06)):
            cyl(mb, rr_c, -rh * 0.5, rh * 0.5, 8, 'brass', C_TEMPLE_GOLD, False, 0.0, rr_c * 0.98)
            torus(mb, rr_c + 0.015, 0.030, 8, 4, 'brass', C_GOLD_BRIGHT, False)
            for sk in range(n_studs):
                ang = 2.0 * pi * sk / float(n_studs)
                cbox(mb, (cos(ang) * (rr_c + 0.03), 0.0, sin(ang) * (rr_c + 0.03)),
                     (0.06, 0.11, 0.11), 'brass', C_GOLD_BRIGHT, 0.0,
                     M=R('Y', -degrees(ang)) @ R('X', 45.0))
    for ang_d in (0.0, 90.0, 180.0, 270.0):
        ang = radians(ang_d)
        _add_beam(mb, (cos(ang) * 0.78, 0.85, 0.06 + sin(ang) * 0.78),
                  (cos(ang) * 0.58, 4.92, 0.06 + sin(ang) * 0.58),
                  0.065, 0.065, 'brass', C_GOLD_BRIGHT, 0.0)

    # 4. Sculpted Coiled Sea-Serpent Body Spiraling Upward Around the Obelisk + Dorsal Crest Fins!
    serp_pts, serp_rads, serp_cols = [], [], []
    n_serp = 26
    for i in range(n_serp):
        t = i / float(n_serp - 1)
        ang = radians(-135.0 + t * 765.0)
        if t < 0.84:
            u = t / 0.84
            rad_orbit = 1.06 * (1.0 - u) + 0.64 * u + 0.05 * sin(u * pi * 6.0)
            px = cos(ang) * rad_orbit
            pz = 0.06 + sin(ang) * rad_orbit
            py = DAIS_Y3 + 0.14 + u * 4.22
            s_rad = 0.11 + 0.19 * sin(min(1.0, u * 1.15) * pi * 0.65)
        else:
            v = (t - 0.84) / 0.16
            p_join = Vector((cos(radians(-135.0 + 0.84 * 765.0)) * 0.64,
                             DAIS_Y3 + 4.36,
                             0.06 + sin(radians(-135.0 + 0.84 * 765.0)) * 0.64))
            p_neck_apex = Vector((0.0, 5.44, 0.20))
            p_head_root = Vector((0.0, 5.62, -0.14))
            p = p_join.lerp(p_neck_apex, v * 2.0) if v < 0.5 else p_neck_apex.lerp(p_head_root, (v - 0.5) * 2.0)
            px, py, pz = p.x, p.y, p.z
            s_rad = 0.30 + 0.05 * sin(v * pi)
        serp_pts.append(Vector((px, py, pz)))
        serp_rads.append(s_rad)
        serp_cols.append(jit(mix(C_JADE_DARK, C_JADE_HI, 0.25 + 0.70 * t), rng, 0.05))
    tube(mb, serp_pts, serp_rads, 7, 'temple_stone', C_JADE_MID, caps=(True, True), mode='flat', scols=serp_cols)

    for i in range(3, n_serp - 2, 2):
        pt = serp_pts[i]
        out_v = Vector((pt.x, 0.0, pt.z - 0.06))
        if out_v.length < 1e-4:
            out_v = Vector((0.0, 0.0, -1.0))
        out_v.normalize()
        fin_p = pt + out_v * (serp_rads[i] * 0.88)
        f_yaw = -degrees(atan2(out_v.z, out_v.x))
        with xf(mb, T(fin_p) @ R('Y', f_yaw) @ R('Z', -22.0)):
            cyl(mb, 0.088, -0.02, 0.28, 4, 'limestone_moss',
                C_GOLD_BRIGHT if i % 6 == 3 else C_JADE_HI, False, 0.0, 0.016)

    # 3 Sculpted Kraken-Coil Stone Tentacles curling tightly out from the monolith root onto the dais!
    for kt_ang, kt_dir, kt_len in ((35.0, 1.0, 1.38), (155.0, -1.0, 1.42), (-145.0, 1.0, 1.32)):
        a0 = radians(kt_ang)
        t_pts, t_rads, t_cols = [], [], []
        for si in range(7):
            u = si / 6.0
            a = a0 + kt_dir * u * 0.85
            rr = 0.72 + u * kt_len
            yy = DAIS_Y3 + 0.24 * (1.0 - u) + 0.34 * sin(u * pi * 1.35) - (0.32 * max(0.0, u - 0.55))
            if si == 6:
                yy += 0.26
            t_pts.append(Vector((cos(a) * rr, yy, sin(a) * rr)))
            t_rads.append(0.18 * (1.0 - 0.72 * u))
            t_cols.append(jit(mix(C_JADE_DARK, C_JADE_HI, u * 0.8), rng, 0.05))
        tube(mb, t_pts, t_rads, 5, 'temple_stone', C_JADE_MID, caps=(True, True), mode='flat', scols=t_cols)

    # 5. Open-Jawed Horned Sea-Serpent Head Gripping Radiant Faceted Turquoise Crystal Orb ('Lantern_Serpent')!
    HEAD_CTR = Vector((0.0, 5.66, -0.24))
    ORB_POS  = Vector((0.0, 5.58, -0.88))
    with xf(mb, T(HEAD_CTR)):
        # Heavy angular carved stone cranium + solid rear neck bolster + flared cobra hood gill-plates!
        cbox(mb, (0.0,  0.14,  0.12), (0.80, 0.58, 0.74), 'temple_stone', C_JADE_HI, 0.0)
        cbox(mb, (0.0, -0.18,  0.22), (0.64, 0.44, 0.56), 'temple_stone', C_JADE_MID, 0.0)
        for sx in (-1.0, 1.0):
            cbox(mb, (sx * 0.56, 0.06, 0.28), (0.48, 0.74, 0.16), 'temple_stone',
                 C_JADE_MID, 0.0, M=R('Y', sx * 28.0) @ R('Z', -sx * 16.0))
            cbox(mb, (sx * 0.66, 0.16, 0.24), (0.34, 0.14, 0.19), 'brass',
                 C_GOLD_BRIGHT, 0.0, M=R('Y', sx * 28.0) @ R('Z', -sx * 12.0))
        cbox(mb, (0.0,  0.42, -0.14), (0.88, 0.18, 0.58), 'temple_stone', C_JADE_HI, 0.0)
        cbox(mb, (0.0,  0.48, -0.34), (0.34, 0.16, 0.16), 'brass', C_GOLD_BRIGHT, 0.0, M=R('Z', 45.0))
        for sx in (-1.0, 1.0):
            cbox(mb, (sx * 0.35, 0.26, -0.22), (0.16, 0.12, 0.18), 'skull_glow', C_RUNE_CORE, 0.0,
                 M=R('Y', sx * -18.0) @ R('Z', sx * 14.0))
        # Upper arched snout lifted slightly higher & hinged lower jaw opened wider to showcase the glowing orb!
        cbox(mb, (0.0,  0.38, -0.58), (0.58, 0.24, 0.68), 'temple_stone', C_JADE_HI, 0.0, M=R('X', -15.0))
        cbox(mb, (0.0,  0.52, -0.78), (0.28, 0.16, 0.34), 'temple_stone', C_JADE_MID, 0.0, M=R('X', -20.0))
        cbox(mb, (0.0, -0.32, -0.48), (0.54, 0.20, 0.80), 'temple_stone', C_JADE_MID, 0.0, M=R('X', 28.0))
        cbox(mb, (0.0, -0.48, -0.78), (0.36, 0.14, 0.34), 'temple_stone', C_JADE_DARK, 0.0, M=R('X', 30.0))
        cbox(mb, (0.0, -0.02, -0.18), (0.44, 0.36, 0.26), 'basalt', C_SKULL_CAV, 0.0)
        for sx in (-0.23, 0.23):
            with xf(mb, T(sx, 0.24, -0.78) @ R('X', 180.0)):
                cyl(mb, 0.056, 0.0, 0.24, 4, 'skull_stone', C_SKULL_BONE, False, 0.0, 0.012)
            with xf(mb, T(sx * 0.85, -0.40, -0.78)):
                cyl(mb, 0.048, 0.0, 0.22, 4, 'skull_stone', C_SKULL_MID, False, 0.0, 0.010)

        # Twin dramatic swept-back curved sea-serpent horns peaking ~6.85 m!
        for sx in (-1.0, 1.0):
            horn_pts = [
                Vector((sx * 0.30, 0.38,  0.14)),
                Vector((sx * 0.56, 0.68,  0.32)),
                Vector((sx * 0.72, 0.98,  0.24)),
                Vector((sx * 0.58, 1.18,  0.02)),
            ]
            tube(mb, horn_pts, [0.12, 0.095, 0.064, 0.018], 5, 'skull_stone', C_SKULL_BONE,
                 caps=(True, True), mode='flat',
                 scols=[C_JADE_HI, C_SKULL_MID, C_SKULL_BONE, C_SKULL_BONE])
            with xf(mb, T(sx * 0.44, 0.54, 0.24) @ R('Z', -sx * 36.0)):
                cyl(mb, 0.118, -0.05, 0.05, 6, 'brass', C_GOLD_BRIGHT, False, 0.0)

    # Radiant Faceted Turquoise Crystal Orb gripped cleanly inside the open jaws ('skull_glow' + brass cage!)
    with xf(mb, T(ORB_POS)):
        orb_prof = [
            (0.00, -0.36),
            (0.24, -0.22),
            (0.35,  0.00),
            (0.24,  0.22),
            (0.00,  0.36),
        ]
        lathe(mb, orb_prof, 7, 'skull_glow', C_RUNE_CORE, False, False,
              lambda i, k: C_RUNE_CORE if i in (1, 2) else C_RUNE_MID)
        torus(mb, 0.365, 0.026, 7, 4, 'brass', C_GOLD_BRIGHT, False)
        for pk in range(3):
            ang = radians(30.0 + pk * 120.0)
            _add_beam(mb, (cos(ang) * 0.28, -0.30, sin(ang) * 0.28),
                      (cos(ang) * 0.36,  0.04, sin(ang) * 0.36),
                      0.032, 0.032, 'brass', C_TEMPLE_GOLD, 0.0)

    # 6. Carved Offering Stone Bowl perched on the Front Dais (z ≈ -1.36) + Gold Tribute Accents!
    BOWL_X, BOWL_Z = 0.0, -1.36
    with xf(mb, T(BOWL_X, DAIS_Y3 - 0.04, BOWL_Z)):
        bowl_prof = [
            (0.00, 0.00), (0.34, 0.00), (0.26, 0.12), (0.20, 0.38),
            (0.46, 0.56), (0.52, 0.72), (0.44, 0.74), (0.36, 0.56), (0.00, 0.50),
        ]
        lathe(mb, bowl_prof, 8, 'temple_stone', C_JADE_MID, False, False,
              lambda i, k: C_JADE_HI if i in (4, 5) else C_JADE_DARK)
        with xf(mb, T(0.0, 0.68, 0.0)):
            torus(mb, 0.51, 0.028, 8, 4, 'brass', C_GOLD_BRIGHT, False)
        cyl(mb, 0.30, 0.48, 0.60, 7, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.16)
        with xf(mb, T(0.0, 0.64, -0.02) @ R('Z', 12.0)):
            lathe(mb, [(0.0, -0.04), (0.088, 0.06), (0.0, 0.25)], 5, 'skull_glow', C_RUNE_CORE, False)

    # 7. Wind-Swaying Draped Jungle Vines, Lush Base Ferns ('foliage' + UV2) & Cracked Mossy Rubble Blocks!
    for v_anc, v_len, v_w, v_dir, v_ph in (
        ((-0.62, 4.46, -0.22), 2.30, 0.24, (-0.75, 0.0, -0.66), 0.12),
        (( 0.64, 4.35, -0.18), 2.15, 0.23, ( 0.78, 0.0, -0.62), 0.34),
        ((-0.60, 3.15,  0.54), 1.95, 0.22, (-0.64, 0.0,  0.76), 0.58),
        (( 0.62, 3.25,  0.52), 2.05, 0.23, ( 0.66, 0.0,  0.75), 0.81),
    ):
        _add_leafy_vine_drape(mb, v_anc, v_len, v_w, v_dir, rng, phase=v_ph)

    for fp_pos, fp_sc, fp_nf, fp_ph, fp_lean in (
        ((-1.62, DAIS_Y1 + 0.02, -1.16), 0.92, 5, 0.15, (-0.7, 0.0, -0.7)),
        (( 1.66, DAIS_Y1 + 0.02, -1.12), 0.88, 5, 0.42, ( 0.7, 0.0, -0.7)),
        ((-1.78, DAIS_Y1 + 0.02,  1.06), 0.95, 4, 0.67, (-0.7, 0.0,  0.7)),
        (( 1.72, DAIS_Y1 + 0.02,  1.10), 0.90, 4, 0.89, ( 0.7, 0.0,  0.7)),
        (( 0.04, DAIS_Y2 + 0.02,  1.62), 0.84, 4, 0.28, ( 0.0, 0.0,  1.0)),
    ):
        _add_jungle_fern_cluster(mb, fp_pos, scale=fp_sc, n_fronds=fp_nf, rng=rng, phase=fp_ph, lean_dir=fp_lean)

    for rb_pos, rb_sz, rb_rot in (
        ((-1.86, DAIS_Y1 + 0.16, -0.44), (0.64, 0.40, 0.54), ( 4,  24, -8)),
        (( 1.92, DAIS_Y1 + 0.14,  0.34), (0.68, 0.36, 0.56), (-6, -32,  6)),
        ((-1.18, DAIS_Y2 + 0.14,  1.42), (0.58, 0.36, 0.52), ( 8,  16,  5)),
        (( 1.24, DAIS_Y1 + 0.12, -1.68), (0.56, 0.32, 0.48), (-5,  42, -9)),
        ((-0.88, DAIS_Y1 + 0.10, -1.86), (0.48, 0.28, 0.44), ( 6, -18,  7)),
    ):
        sculpt_stone_block(
            mb, rb_pos, rb_sz, 'temple_stone', C_JADE_MID, rng,
            chip=0.045, M=R('Y', rb_rot[1]) @ R('X', rb_rot[0]) @ R('Z', rb_rot[2]),
            moss_col=C_LEDGE_MOSS,
        )

    build(mb)

    add_empty('Lantern_Serpent', ORB_POS)
    col_piece('col_serpent_base', col_pts)
    export_landmark_glb(outdir, 'ancient_jade_serpent_totem.glb')


# ================================================================ 3. COASTAL DRIFTWOOD ARCH CAMP

def gen_coastal_driftwood_arch_camp(outdir):
    """Atmospheric castaway's shipwreck-survivor beach bivouac (~5.4 m wide x 4.4 m deep x 3.8 m tall)
    anchored on a deeply skirted weathered coastal stone-and-sand mound (y = -2.80..+0.15 m anti-float!).
    Twin arched bleached driftwood & curved whalebone ribs lashed together at the ridge by thick hemp ropes,
    draped with a wind-rippling patched cream-and-terracotta sailcloth sun-tarp ('paint' + UV2 wind!),
    woven rope-and-plank hammock slung between posts, driftwood tripod cooking spit over glowing beach
    fire stones ('Lantern_Bivouac'), stuck fishing spears, message-bottle crate, cracked compass keg,
    and a crooked hand-painted driftwood plank sign!
    Target: 2,800-3,500 visual tris, 1 collider (col_bivouac_base).
    """
    clear_scene()
    rng = random.Random(SEED + 2633)
    mb = MB('CoastalDriftwoodArchCamp', seed=2633)

    SKIRT_BOT = -2.80
    MOUND_Y = 0.15
    col_pts = []

    # 1. Deeply Skirted Weathered Coastal Stone-and-Sand Mound (y = -2.80..+0.15 m, ~5.6 m x 4.6 m!)
    #    Generously covers all guy-line stakes & shore boulders so ZERO parts ever hang over slopes!
    mound_secs = [
        _reg_poly(0.0, SKIRT_BOT, 0.0, 3.04, sides=10, rot_deg=18.0, sx=1.04, sz=0.86),
        _reg_poly(0.0, -1.05,     0.0, 2.84, sides=10, rot_deg=18.0, sx=1.03, sz=0.85),
        _reg_poly(0.0, MOUND_Y,   0.0, 2.66, sides=10, rot_deg=18.0, sx=1.02, sz=0.84),
    ]
    _loft_horizontal_masonry(
        mb, mound_secs, 'limestone',
        [C_TIDE_DARK, C_SAND_OCHRE, C_SAND_WARM],
        rng, caps=(True, True), top_mat='limestone', top_col=C_SAND_PALE,
    )
    for ring in mound_secs:
        col_pts.extend(Vector(p) for p in ring)

    # Low embedded weathered coastal shore boulders anchoring the mound perimeter
    for rp, rr, rrot in (
        ((-2.28, 0.02,  0.86), (0.76, 0.42, 0.64), ( 4,  24, -6)),
        (( 2.24, 0.04,  0.94), (0.78, 0.44, 0.66), (-5, -18,  7)),
        (( 2.18, 0.00, -1.04), (0.70, 0.36, 0.58), ( 6,  38, -5)),
        ((-0.18, 0.06,  1.88), (1.02, 0.40, 0.62), (-4,  10,  4)),
    ):
        sculpt_rock_mass(
            mb, rp, rr, 'limestone_moss',
            C_LIME_WARM, C_SAND_OCHRE, C_TIDE_DARK, rng,
            subdiv=1, warp=0.22, strata=0.10, flat_top=0.70, base_flare=0.24,
            rot_deg=rrot, crag_ribs=5, rib_amp=0.12, moss_cap=0.22,
        )

    # 2. Twin Arched Bleached Driftwood & Curved Whalebone Ribs Lashed at the Ridge!
    RIDGE_Y = 3.24

    def _arch_curve(side_sgn, z_base, span_x, top_y, z_lean, n_pts=6, overshoot=0.16):
        pts = []
        for i in range(n_pts):
            t = i / float(n_pts - 1)
            u = t * (1.0 + overshoot)
            px = side_sgn * span_x * (1.0 - u) + side_sgn * sin(t * pi) * 0.38
            py = -0.32 + (top_y + 0.32) * sin(min(1.0, t) * pi * 0.5) + (0.28 * max(0.0, u - 1.0) / max(overshoot, 1e-4))
            pz = z_base + z_lean * t + sin(t * pi * 1.4) * 0.07
            pts.append(Vector((px, py, pz)))
        return pts

    arch_specs = [
        (-1.0, -0.98, 2.08, RIDGE_Y,        -0.06, 'timber', C_DRIFT_PALE, C_DRIFT_SHADE, 0.135, 0.078),
        ( 1.0, -0.94, 2.06, RIDGE_Y,        -0.04, 'timber', C_DRIFTWOOD,  C_TIMBER_DARK, 0.132, 0.076),
        (-1.0,  1.06, 2.02, RIDGE_Y - 0.10,  0.08, 'timber', C_DRIFTWOOD,  C_TIMBER_DARK, 0.130, 0.076),
        ( 1.0,  1.02, 2.04, RIDGE_Y - 0.10,  0.06, 'timber', C_DRIFT_PALE, C_DRIFT_SHADE, 0.128, 0.075),
    ]
    for sgn, zb, sx, ty, zl, mat, c_top, c_bot, r0, r1 in arch_specs:
        pts = _arch_curve(sgn, zb, sx, ty, zl, n_pts=6, overshoot=0.16)
        rads = [r0 * (1.0 - i / 5.0) + r1 * (i / 5.0) for i in range(6)]
        cols = [jit(mix(c_bot, c_top, i / 5.0), rng, 0.05) for i in range(6)]
        tube(mb, pts, rads, 5, mat, c_top, caps=(True, True), mode='flat', scols=cols)
        col_pts.append(pts[-1])

    # Twin Dramatic Curved Bleached Whalebone Ribs arching between front & rear driftwood frames!
    for sgn, zb_w, ty_w in ((-1.0, 0.06, RIDGE_Y + 0.08), (1.0, 0.02, RIDGE_Y + 0.08)):
        w_pts, w_rads, w_cols = [], [], []
        for i in range(6):
            t = i / 5.0
            ang = radians(12.0 + t * 88.0)
            px = sgn * (2.16 * cos(ang) + 0.10 * sin(t * pi))
            py = -0.20 + (ty_w + 0.20) * sin(ang)
            pz = zb_w - 0.12 * sin(t * pi)
            w_pts.append(Vector((px, py, pz)))
            w_rads.append(0.115 * (1.0 - 0.38 * t) + 0.025 * sin(t * pi))
            w_cols.append(jit(mix(C_SKULL_SHADE, C_SKULL_BONE, 0.35 + 0.65 * t), rng, 0.04))
        tube(mb, w_pts, w_rads, 5, 'skull_stone', C_SKULL_BONE, caps=(True, True), mode='flat', scols=w_cols)

    # Heavy horizontal bleached driftwood ridge pole & side purlins
    RIDGE_F = Vector((0.0, RIDGE_Y + 0.04, -1.52))
    RIDGE_B = Vector((0.0, RIDGE_Y - 0.06,  1.56))
    tube(mb, [RIDGE_F, Vector((0.02, RIDGE_Y + 0.06, 0.04)), RIDGE_B],
         [0.090, 0.108, 0.088], 5, 'timber', C_DRIFT_PALE, caps=(True, True), mode='flat')
    for sx in (-1.0, 1.0):
        _add_beam(mb, (sx * 1.62, 1.94, -1.16), (sx * 1.58, 1.88, 1.24), 0.082, 0.082, 'timber', C_DRIFTWOOD, 0.0)

    # Thick braided hemp rope lashings binding every arch apex to the ridge pole!
    for lz, ly in ((-0.96, RIDGE_Y + 0.02), (0.04, RIDGE_Y + 0.05), (1.04, RIDGE_Y - 0.05)):
        for rx_a in (-38.0, 38.0):
            with xf(mb, T(0.0, ly, lz) @ R('X', rx_a) @ R('Z', 24.0)):
                torus(mb, 0.21, 0.042, 6, 4, 'rope', C_ROPE, False)

    # 3. Wind-Rippling Patched Cream-and-Terracotta Sailcloth Sun-Tarp ('paint' + UV2 wind!)
    nu, nv = 7, 5
    thick = 0.024

    def _tarp_pt(u, v):
        z = -1.26 + v * 2.58
        ridge_y_z = (RIDGE_Y + 0.15) * (1.0 - v) + (RIDGE_Y + 0.05) * v
        ang = radians(-72.0 + u * 134.0)
        rx = 2.02 if ang < 0 else 1.88
        px = sin(ang) * rx
        py = ridge_y_z - (1.0 - cos(ang)) * (1.92 if ang < 0 else 1.56)
        rib_sag = abs(sin(v * pi * 2.0)) * 0.14 * abs(sin(ang))
        ripple = sin(u * pi * 3.0 + v * pi * 2.5) * 0.055 * (0.25 + 0.75 * abs(u - 0.52) * 2.0)
        if u < 0.12 or u > 0.88:
            px += (0.14 if u > 0.88 else -0.14) * (1.0 - min(u, 1.0 - u) / 0.12)
        return Vector((px, py - rib_sag + ripple, z))

    def _tarp_w(u, v):
        dist_ridge = abs(u - 0.52) * 2.0
        rib_dist = min(abs(v - 0.12), abs(v - 0.50), abs(v - 0.88)) * 3.0
        edge_boost = 0.35 if (v < 0.14 or v > 0.86) else 0.0
        return min(0.94, max(0.0, (dist_ridge ** 1.3) * 0.72 + rib_dist * 0.20 + edge_boost))

    top_g = [[None] * (nv + 1) for _ in range(nu + 1)]
    bot_g = [[None] * (nv + 1) for _ in range(nu + 1)]
    w_g   = [[0.0]  * (nv + 1) for _ in range(nu + 1)]
    for iu in range(nu + 1):
        u = iu / float(nu)
        for iv in range(nv + 1):
            v = iv / float(nv)
            p = _tarp_pt(u, v)
            pu = _tarp_pt(min(1.0, u + 0.02), v) - _tarp_pt(max(0.0, u - 0.02), v)
            pv = _tarp_pt(u, min(1.0, v + 0.02)) - _tarp_pt(u, max(0.0, v - 0.02))
            n = pv.cross(pu)
            if n.y < 0.0:
                n = -n
            n = n.normalized() if n.length > 1e-6 else Vector((0.0, 1.0, 0.0))
            top_g[iu][iv] = p + n * (thick * 0.5)
            bot_g[iu][iv] = p - n * (thick * 0.5)
            w_g[iu][iv] = _tarp_w(u, v)

    def _patch_col(iu, iv):
        if iu in (1, 5):
            c = C_TERRA_HI if (iv % 2 == 0) else C_TERRA_MID
        elif (iu == 3 and iv in (1, 2)) or (iu == 4 and iv == 3):
            c = C_TERRA_HI
        elif (iu == 0 and iv == 3) or (iu == 6 and iv == 1):
            c = C_TEAL_BRIGHT
        elif (iu + iv) % 2 == 0:
            c = C_CANVAS_CREAM
        else:
            c = C_CANVAS_WARM
        return jit(c, rng, 0.04, 0.014)

    mb.newoff()
    t_phase = 0.27
    for iu in range(nu):
        for iv in range(nv):
            c_top = _patch_col(iu, iv)
            c_bot = mul(c_top, 0.84)
            t00, t10, t11, t01 = top_g[iu][iv], top_g[iu + 1][iv], top_g[iu + 1][iv + 1], top_g[iu][iv + 1]
            b00, b10, b11, b01 = bot_g[iu][iv], bot_g[iu + 1][iv], bot_g[iu + 1][iv + 1], bot_g[iu][iv + 1]
            u00, u10, u11, u01 = (w_g[iu][iv], t_phase), (w_g[iu + 1][iv], t_phase), (w_g[iu + 1][iv + 1], t_phase), (w_g[iu][iv + 1], t_phase)
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

    # 4 Taut Hemp Guy-Lines staked solidly INSIDE the sand-mound rim (plunging deep to y = -0.85 m!)
    for corner_p, stake_xz in (
        (top_g[0][0],  (-2.34, -1.26)),
        (top_g[0][nv], (-2.34,  1.34)),
        (top_g[nu][0], ( 2.30, -1.24)),
        (top_g[nu][nv],( 2.30,  1.36)),
    ):
        s_bot = Vector((stake_xz[0], -0.85, stake_xz[1]))
        s_top = Vector((stake_xz[0] + (0.10 if stake_xz[0] > 0 else -0.10), MOUND_Y + 0.36, stake_xz[1]))
        _add_beam(mb, s_bot, s_top, 0.075, 0.075, 'timber', C_TIMBER_DARK, 0.0)
        tie_p = Vector((stake_xz[0] + (0.06 if stake_xz[0] > 0 else -0.06), MOUND_Y + 0.24, stake_xz[1]))
        mid_g = corner_p.lerp(tie_p, 0.5) - Vector((0.0, 0.05, 0.0))
        tube(mb, [corner_p, mid_g, tie_p], 0.020, 4, 'rope', C_ROPE, caps=(True, True), mode='flat')

    # 4. Woven Rope-and-Plank Hammock Slung Gracefully Between Port Driftwood Arch Legs!
    HAM_A = Vector((-1.62, 1.46, -0.96))
    HAM_B = Vector((-1.58, 1.42,  1.06))
    for hp in (HAM_A, HAM_B):
        with xf(mb, T(hp) @ R('Z', 24.0)):
            torus(mb, 0.145, 0.028, 6, 4, 'rope', C_ROPE, False)
    BAR_A = Vector((-1.32, 1.12, -0.64))
    BAR_B = Vector((-1.28, 1.10,  0.74))
    for anchor_p, bar_p in ((HAM_A, BAR_A), (HAM_B, BAR_B)):
        _add_beam(mb, bar_p + Vector((-0.30, 0.0, 0.0)), bar_p + Vector((0.30, 0.0, 0.0)),
                  0.058, 0.058, 'timber', C_TIMBER_HI, 0.0)
        for sx_b in (-0.26, 0.26):
            tube(mb, [anchor_p, bar_p + Vector((sx_b, 0.0, 0.0))], 0.020, 4, 'rope', C_ROPE, mode='flat')
    n_h = 6
    h_l, h_r = [], []
    for hi in range(n_h):
        t = hi / float(n_h - 1)
        sag = sin(t * pi) * 0.36
        cx = BAR_A.x * (1.0 - t) + BAR_B.x * t + sin(t * pi) * 0.12
        cy = BAR_A.y * (1.0 - t) + BAR_B.y * t - sag
        cz = BAR_A.z * (1.0 - t) + BAR_B.z * t
        hw = 0.29 + 0.08 * sin(t * pi)
        h_l.append(Vector((cx - hw, cy + 0.04, cz)))
        h_r.append(Vector((cx + hw, cy + 0.04, cz)))
        if 0 < hi < n_h - 1:
            cbox(mb, (cx, cy - 0.01, cz), (hw * 2.04, 0.032, 0.14), 'timber',
                 C_DRIFT_PALE if hi % 2 == 0 else C_TIMBER_HI, 0.0)
    for hi in range(n_h - 1):
        p00, p10 = h_l[hi], h_r[hi]
        p11, p01 = h_r[hi + 1], h_l[hi + 1]
        c_hm = C_CANVAS_WARM if hi % 2 == 0 else C_TERRA_HI
        ctr_h = (p00 + p11) * 0.5
        mb.fp([p00, p10, p11, p01], 'paint', c_hm, (1, 0, 0), ctr_h - Vector((0.0, 1.0, 0.0)))
        mb.fp([p00, p01, p11, p10], 'paint', mul(c_hm, 0.80), (1, 0, 0), ctr_h + Vector((0.0, 1.0, 0.0)))
    tube(mb, h_l, 0.022, 4, 'rope', C_ROPE, mode='flat')
    tube(mb, h_r, 0.022, 4, 'rope', C_ROPE, mode='flat')

    # 5. Driftwood Tripod Cooking Spit Over Glowing Beach Fire Stones ('Lantern_Bivouac'!)
    FIRE_X, FIRE_Z = 0.78, -0.78
    FIRE_POS = Vector((FIRE_X, MOUND_Y + 0.30, FIRE_Z))
    for sk in range(7):
        ang = 2.0 * pi * sk / 7.0 + 0.2
        rx = FIRE_X + cos(ang) * 0.48
        rz = FIRE_Z + sin(ang) * 0.48
        cbox(mb, (rx, MOUND_Y + 0.10, rz), (0.26, 0.20, 0.22), 'limestone',
             jit(C_COBBLE_MID if sk % 2 == 0 else C_SAND_SHADE, rng, 0.08), 0.0,
             M=R('Y', -degrees(ang)) @ R('Z', rng.uniform(-12, 12)))
    for la in (18.0, 76.0, 134.0):
        with xf(mb, T(FIRE_X, MOUND_Y + 0.12, FIRE_Z) @ R('Y', la) @ M_Y2Z):
            cyl(mb, 0.056, -0.34, 0.34, 4, 'timber', C_BRICK_SOOT, False, 0.0)
    _build_flame_cluster(mb, (FIRE_X, MOUND_Y + 0.14, FIRE_Z), radius=0.28, height=0.46, n_tongues=5)

    TRI_APEX = Vector((FIRE_X, MOUND_Y + 1.48, FIRE_Z))
    for tk in range(3):
        ang = radians(32.0 + tk * 120.0)
        leg_bot = Vector((FIRE_X + cos(ang) * 0.74, MOUND_Y - 0.18, FIRE_Z + sin(ang) * 0.74))
        leg_tip = TRI_APEX + (TRI_APEX - leg_bot).normalized() * 0.24
        _add_beam(mb, leg_bot, leg_tip, 0.068, 0.068, 'timber', C_DRIFT_PALE, 0.0)
    with xf(mb, T(TRI_APEX)):
        torus(mb, 0.095, 0.026, 6, 4, 'rope', C_ROPE, False)
    _add_beam(mb, TRI_APEX, Vector((FIRE_X, MOUND_Y + 0.88, FIRE_Z)), 0.024, 0.024, 'iron', C_IRON, 0.0)
    with xf(mb, T(FIRE_X, MOUND_Y + 0.56, FIRE_Z)):
        pot_prof = [
            (0.00, 0.00), (0.18, 0.02), (0.24, 0.14), (0.20, 0.28),
            (0.23, 0.32), (0.18, 0.32), (0.16, 0.12), (0.00, 0.10),
        ]
        lathe(mb, pot_prof, 6, 'iron', C_IRON, False, False,
              lambda i, k: C_IRON_RUST if i in (1, 4) else C_IRON)
        with xf(mb, T(0.0, 0.30, 0.0) @ M_Y2Z):
            torus(mb, 0.19, 0.018, 6, 4, 'iron', C_IRON, False)

    # 6. Stuck Fishing Spears, Message-Bottle Crate, Cracked Compass Keg & Crooked Driftwood Sign!
    for sp_base, sp_top in (
        ((-0.58, MOUND_Y - 0.20, -1.24), (-0.82, MOUND_Y + 1.54, -1.48)),
        ((-0.44, MOUND_Y - 0.20, -1.32), (-0.26, MOUND_Y + 1.40, -1.56)),
        ((-0.70, MOUND_Y - 0.20, -1.10), (-1.04, MOUND_Y + 1.28, -1.16)),
    ):
        pb, pt = Vector(sp_base), Vector(sp_top)
        v_sp = (pt - pb).normalized()
        _add_beam(mb, pb, pt, 0.044, 0.044, 'timber', C_DRIFTWOOD, 0.0)
        grip_p = pb.lerp(pt, 0.84)
        rot_sp = Vector((0.0, 1.0, 0.0)).rotation_difference(v_sp).to_matrix().to_4x4()
        with xf(mb, T(grip_p) @ rot_sp):
            cyl(mb, 0.036, -0.05, 0.05, 4, 'rope', C_ROPE, False, 0.0)
        with xf(mb, T(pt) @ rot_sp):
            cyl(mb, 0.042, -0.02, 0.22, 4, 'iron', C_IRON_RUST, False, 0.0, 0.008)
            for sb in (-1.0, 1.0):
                _add_beam(mb, (0.0, 0.06, 0.0), (sb * 0.075, -0.04, 0.0), 0.022, 0.022, 'iron', C_IRON, 0.0)

    CR_X, CR_Z = 0.72, 0.76
    _build_stenciled_crate(
        mb, T(CR_X, MOUND_Y + 0.30, CR_Z) @ R('Y', -22.0),
        size=(0.74, 0.58, 0.62), rng=rng, stripe_col=C_TEAL_BRIGHT, stencil_col=C_CANVAS_CREAM, open_top=True,
    )
    for bx, by, bz, bcol, btilt in (
        (CR_X - 0.14, MOUND_Y + 0.34, CR_Z - 0.08, C_BOTTLE_GREEN,  8.0),
        (CR_X + 0.08, MOUND_Y + 0.34, CR_Z + 0.06, C_BOTTLE_AMBER, -10.0),
        (CR_X + 0.16, MOUND_Y + 0.34, CR_Z - 0.12, C_BOTTLE_GREEN,  6.0),
        (CR_X - 0.52, MOUND_Y + 0.02, CR_Z - 0.18, C_BOTTLE_AMBER,  0.0),
    ):
        _build_rum_bottle(mb, T(bx, by, bz) @ R('Z', btilt), scale=1.08, col=bcol, cork=True)
    with xf(mb, T(CR_X - 0.04, MOUND_Y + 0.50, CR_Z + 0.12) @ R('X', 16.0) @ R('Z', -12.0)):
        cyl(mb, 0.042, 0.0, 0.38, 5, 'paint', C_CANVAS_CREAM, False, 0.0)
        cyl(mb, 0.046, 0.16, 0.21, 5, 'paint', C_CRIMSON_HI, False, 0.0)

    KEG_X, KEG_Z = 1.54, 0.34
    _build_coopered_cask(
        mb, T(KEG_X, MOUND_Y + 0.38, KEG_Z) @ R('Y', 18.0) @ R('Z', -4.0),
        radius=0.31, height=0.76, rng=rng, col_a=C_DRIFTWOOD, col_b=C_TIMBER_MID,
        segs=6, stripe_col=C_TERRA_HI,
    )
    cbox(mb, (KEG_X + 0.30, MOUND_Y + 0.36, KEG_Z - 0.12), (0.045, 0.56, 0.11), 'timber',
         C_OAK_FRESH, 0.0, M=R('Y', 24.0) @ R('Z', -16.0))
    with xf(mb, T(KEG_X - 0.02, MOUND_Y + 0.78, KEG_Z) @ R('Y', -14.0)):
        cyl(mb, 0.17, 0.0, 0.065, 7, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.16)
        cyl(mb, 0.135, 0.055, 0.072, 7, 'paint', C_CANVAS_CREAM, False, 0.0)
        cbox(mb, (0.0, 0.080, 0.0), (0.036, 0.016, 0.20), 'paint', C_CRIMSON_HI, 0.0, M=R('Y', 32.0))
        cbox(mb, (0.0, 0.080, 0.0), (0.16,  0.014, 0.024), 'iron', C_IRON, 0.0, M=R('Y', 32.0))

    # Crooked Hand-Painted Driftwood Plank Sign clear of the front-port arch leg!
    SIGN_X, SIGN_Z = -1.78, -1.52
    _add_beam(mb, (SIGN_X, MOUND_Y - 0.28, SIGN_Z), (SIGN_X - 0.12, MOUND_Y + 1.66, SIGN_Z - 0.06),
              0.12, 0.12, 'timber', C_DRIFT_SHADE, 0.0)
    for sy_p, s_ang, s_yaw, s_col, s_stripe in (
        (MOUND_Y + 1.38,  8.0, -18.0, C_DRIFT_PALE, C_TERRA_HI),
        (MOUND_Y + 0.98, -7.0,  14.0, C_TIMBER_HI,  C_TEAL_BRIGHT),
    ):
        with xf(mb, T(SIGN_X - 0.08, sy_p, SIGN_Z - 0.04) @ R('Y', s_yaw) @ R('Z', s_ang)):
            cbox(mb, (0.0, 0.0, 0.0), (0.84, 0.24, 0.052), 'timber', s_col, 0.0, (1, 0, 0))
            with xf(mb, T(0.41, 0.0, 0.0) @ R('Z', -90.0)):
                cyl(mb, 0.125, 0.0, 0.20, 4, 'timber', s_col, False, 0.0, 0.015)
            for sz_m in (-0.030, 0.030):
                cbox(mb, (-0.06, 0.0, sz_m), (0.54, 0.10, 0.012), 'paint', s_stripe, 0.0)
                cbox(mb, ( 0.23, 0.0, sz_m), (0.11, 0.11, 0.014), 'paint', C_CANVAS_CREAM, 0.0, M=R('Z', 45.0))

    for bp_pos, bp_ph in (((-2.02, MOUND_Y + 0.02, 0.56), 0.18), ((1.98, MOUND_Y + 0.02, -0.78), 0.64)):
        _add_jungle_fern_cluster(mb, bp_pos, scale=0.68, n_fronds=3, rng=rng, phase=bp_ph, segs=3)

    build(mb)

    add_empty('Lantern_Bivouac', FIRE_POS)
    col_piece('col_bivouac_base', col_pts)
    export_landmark_glb(outdir, 'coastal_driftwood_arch_camp.glb')


# ================================================================ 4. VOLCANIC OBSIDIAN BRIDGE RUIN

def gen_volcanic_obsidian_bridge_ruin(outdir):
    """Dramatic fractured black columnar-basalt volcanic overpass abutment (~6.2 m wide x 5.2 m deep x 5.4 m tall)
    plunging into a deep lava-crust basalt base skirt (y = -3.80..+1.10 m anti-float!).
    Broken cantilevered arched dark-basalt bridge deck ending in jagged collapsed stone teeth, glowing
    orange-crimson magma veins cracking through the dark stone foundation ('glass' / C_MAGMA_GLOW),
    twin iron-banded volcanic bridge pylons carrying dangling heavy forged iron chain spans,
    sulfur-encrusted basalt shards, wind-tattered scorched crimson streamer ('paint' + UV2 wind),
    and a blazing iron-cage fire signal brazier crowning the intact parapet ('Lantern_VolcBridge')!
    Target: 2,800-3,600 visual tris, 1 collider (col_volcbridge_base).
    """
    clear_scene()
    rng = random.Random(SEED + 2647)
    mb = MB('VolcanicObsidianBridgeRuin', seed=2647)

    SKIRT_BOT = -3.80
    DECK_Y = 3.04
    col_pts = []

    # 1. Deep Lava-Crust Basalt Base Skirt (y = -3.80..+1.10 m, ~6.2 m wide x 5.2 m deep!)
    #    Buried octagonal anti-float foundation skirt capped cleanly underneath rugged sculpted volcanic crags!
    skirt_secs = [
        _rect_oct(0.0, SKIRT_BOT, 0.0, 3.12, 2.58, 0.80),
        _rect_oct(0.0, -1.55,     0.0, 2.94, 2.44, 0.74),
        _rect_oct(0.0,  0.22,     0.0, 2.74, 2.26, 0.68),
    ]
    _loft_horizontal_masonry(
        mb, skirt_secs, 'basalt',
        [C_BASALT_DARK, C_BASALT_DARK, C_BASALT_MID],
        rng, caps=(True, True), top_mat='basalt', top_col=C_BASALT_MID,
    )
    for ring in skirt_secs:
        col_pts.extend(Vector(p) for p in ring)

    # Rugged volcanic lava-crust crag shoulders wrapping the entire foundation organically (to y ≈ 1.15 m!)
    for mpos, mrad, mrot in (
        ((-1.68,  0.04,  0.00), (1.88, 1.32, 2.34), ( 0,  12,  0)),
        (( 1.92, -0.06,  0.04), (1.28, 1.14, 1.94), ( 3, -18, -4)),
        (( 0.05, -0.14,  1.58), (1.72, 1.18, 1.06), (-4,  10,  4)),
        (( 0.05, -0.16, -1.60), (1.68, 1.14, 1.04), ( 5, -14, -4)),
        ((-2.34, -0.12, -1.26), (1.16, 1.10, 1.16), ( 6,  28, -6)),
    ):
        col_pts += sculpt_rock_mass(
            mb, mpos, mrad, 'basalt',
            C_BASALT_TOP, C_BASALT_MID, C_BASALT_DARK, rng,
            subdiv=1, warp=0.24, strata=0.14, flat_top=0.76, base_flare=0.28,
            rot_deg=mrot, crag_ribs=6, rib_amp=0.16,
        )

    # 2. Hexagonal Columnar-Basalt Overpass Abutment & Broken Far Pier Stub
    abut_secs = [
        _rect_oct(-1.84, 0.45,   0.0, 1.06, 1.62, 0.24),
        _rect_oct(-1.78, 1.75,   0.0, 1.00, 1.54, 0.22),
        _rect_oct(-1.72, DECK_Y, 0.0, 0.96, 1.48, 0.20),
    ]
    _loft_horizontal_masonry(
        mb, abut_secs, 'basalt',
        [C_BASALT_DARK, C_BASALT_MID, C_BASALT_TOP], rng, caps=(False, True), top_col=C_BASALT_TOP,
    )
    col_specs = [
        ((-2.52, 0.25, -1.22), 2.95, 0.46,  6.0,  4.0, True),
        ((-2.54, 0.25,  1.20), 3.05, 0.46,  6.0, -4.0, True),
        ((-1.20, 0.30, -1.52), 2.85, 0.44, -4.0,  6.0, True),
        ((-1.22, 0.30,  1.50), 2.90, 0.44, -4.0, -6.0, False),
        (( 2.18, 0.15, -1.00), 1.68, 0.48,  8.0, -6.0, True),
        (( 2.24, 0.15,  0.96), 1.92, 0.48, -6.0,  8.0, True),
        (( 2.38, 0.15, -0.04), 1.38, 0.52, 10.0,  2.0, True),
    ]
    for bpos, bh, brad, btx, btz, bseam in col_specs:
        sculpt_basalt_column(
            mb, bpos, bh, brad, 6, btx, btz,
            C_BASALT_DARK, mix(C_BASALT_TOP, C_BASALT_HOT, 0.24 if bseam else 0.06),
            rng, mat='basalt', magma_seam=bseam,
        )

    # 3. Broken Cantilevered Arched Dark-Basalt Bridge Deck Ending in Jagged Collapsed Stone Teeth!
    ARCH_CX = 0.54
    ARCH_CY = 1.02
    ARCH_R_IN = 1.44
    ARCH_R_OUT = 1.96
    DECK_HALF_Z = 1.36

    n_vous = 7
    for vi in range(n_vous):
        a0 = radians(176.0 - vi * 18.0)
        a1 = radians(176.0 - (vi + 1) * 18.0)
        am = 0.5 * (a0 + a1)
        ca, sa = cos(am), sin(am)
        r_mid = 0.5 * (ARCH_R_IN + ARCH_R_OUT)
        vx = ARCH_CX + ca * r_mid
        vy = ARCH_CY + sa * r_mid
        seg_len = r_mid * radians(18.6)
        v_col = jit(C_BASALT_TOP if vi % 2 == 0 else C_BASALT_MID, rng, 0.05)
        v_z_span = DECK_HALF_Z * 2.0 * (0.94 if vi < n_vous - 2 else (0.76 if vi == n_vous - 2 else 0.54))
        v_z_off = 0.0 if vi < n_vous - 2 else (-0.18 if vi == n_vous - 2 else 0.26)
        cbox(mb, (vx, vy, v_z_off), (ARCH_R_OUT - ARCH_R_IN, seg_len * 1.12, v_z_span),
             'basalt', v_col, 0.0, M=R('Z', degrees(am)))
        sp_bot = vy + 0.16
        if sp_bot < DECK_Y - 0.12 and vi < n_vous - 1:
            sp_h = DECK_Y - sp_bot
            cbox(mb, (vx, sp_bot + sp_h * 0.5, v_z_off * 0.6), (0.64, sp_h + 0.14, v_z_span * 0.94),
                 'basalt', jit(C_BASALT_MID, rng, 0.06), 0.0)

    cbox(mb, (-0.98, DECK_Y, 0.0), (3.58, 0.34, DECK_HALF_Z * 2.04), 'basalt', C_BASALT_TOP, 0.0)
    for si, (sx_r, sy_r) in enumerate(((-2.72, 2.66), (-2.92, 2.26))):
        cbox(mb, (sx_r, sy_r - 0.85, 0.0), (0.42, 1.95, 2.44 - si * 0.22), 'basalt', C_BASALT_MID, 0.0)

    # Jagged Collapsed Stone Teeth cantilevered dramatically out into mid-air (+X broken edge)!
    broken_teeth = [
        ((1.20, DECK_Y + 0.02, -0.80), (1.36, 0.32, 0.78), ( 4,  -6, -5)),
        ((1.52, DECK_Y - 0.06, -0.06), (1.52, 0.30, 0.84), (-3,   8, -11)),
        ((1.16, DECK_Y + 0.04,  0.82), (1.28, 0.32, 0.82), ( 5, -10, -4)),
        ((2.20, DECK_Y - 0.28, -0.18), (0.92, 0.26, 0.56), (-6,  14, -19)),
        ((1.88, DECK_Y - 0.20,  0.74), (0.84, 0.24, 0.52), ( 8, -16, -15)),
    ]
    for tc, tsz, trot in broken_teeth:
        sculpt_stone_block(
            mb, tc, tsz, 'basalt', jit(C_BASALT_TOP, rng, 0.06), rng,
            chip=0.045, M=R('Y', trot[1]) @ R('X', trot[0]) @ R('Z', trot[2]),
        )
        col_pts.append(Vector((tc[0] + tsz[0] * 0.45, tc[1], tc[2])))
    for ix, iy, iz, ilen, itilt in (
        (1.74, DECK_Y - 0.04, -0.76, 0.74, -12.0),
        (2.34, DECK_Y - 0.32, -0.22, 0.64, -26.0),
        (2.02, DECK_Y - 0.20,  0.70, 0.70, -18.0),
    ):
        _add_beam(mb, (ix - 0.25, iy + 0.04, iz), (ix + ilen, iy + sin(radians(itilt)) * ilen, iz + 0.08),
                  0.048, 0.048, 'iron', C_IRON_RUST, 0.0)

    # Low Broken Crenellated Obsidian Parapet Walls along both bridge flanks (-Z and +Z)
    # Rear (+Z) parapet extends solidly to x = +1.08 so the chain mooring bollard seats 100% into solid masonry!
    for sz_s, p_cx, p_len in ((-1.0, -1.08, 3.16), (1.0, -0.78, 3.74)):
        pz = sz_s * (DECK_HALF_Z - 0.16)
        cbox(mb, (p_cx, DECK_Y + 0.50, pz), (p_len, 0.74, 0.34), 'basalt', C_BASALT_MID, 0.0)
        for mx, mh in ((-2.40, 0.40), (-0.68, 0.44), (0.38, 0.34)):
            cbox(mb, (mx, DECK_Y + 0.86 + mh * 0.45, pz), (0.56, mh, 0.36), 'basalt', C_BASALT_TOP, 0.0)
        sculpt_stone_block(mb, (1.32, 0.96, sz_s * 1.16), (0.64, 0.44, 0.54), 'basalt', C_BASALT_MID, rng,
                           chip=0.05, M=R('Y', sz_s * 28.0) @ R('Z', sz_s * -16.0))

    # 4. Twin Iron-Banded Volcanic Bridge Pylons Carrying Dangling Heavy Forged Iron Chain Spans!
    PYLON_X = -1.58
    PYLON_F_Z = -1.42
    PYLON_B_Z =  1.42
    PYLON_F_TOP = 4.32
    PYLON_B_TOP = 4.46

    for pz, ptop in ((PYLON_F_Z, PYLON_F_TOP), (PYLON_B_Z, PYLON_B_TOP)):
        p_secs = [
            _reg_poly(PYLON_X, DECK_Y - 0.25, pz, 0.58, sides=6, rot_deg=30.0),
            _reg_poly(PYLON_X, 3.75,          pz, 0.50, sides=6, rot_deg=30.0),
            _reg_poly(PYLON_X, ptop,          pz, 0.46, sides=6, rot_deg=30.0),
        ]
        _loft_horizontal_masonry(
            mb, p_secs, 'basalt', [C_BASALT_DARK, C_BASALT_MID, C_BASALT_TOP],
            rng, caps=(False, True), top_col=C_BASALT_TOP,
        )
        for cy_b, cr_b in ((3.54, 0.545), (ptop - 0.24, 0.495)):
            with xf(mb, T(PYLON_X, cy_b, pz)):
                cyl(mb, cr_b, -0.085, 0.085, 6, 'iron', C_IRON, False, 0.0)
                for rk in range(6):
                    ang = radians(30.0 + rk * 60.0)
                    cbox(mb, (cos(ang) * (cr_b + 0.025), 0.0, sin(ang) * (cr_b + 0.025)),
                         (0.075, 0.09, 0.075), 'iron', C_IRON_RUST if rk % 2 == 0 else C_IRON, 0.0,
                         M=R('Y', -degrees(ang)))
        col_pts.append(Vector((PYLON_X, ptop + 0.85, pz)))

    with xf(mb, T(PYLON_X, PYLON_B_TOP, PYLON_B_Z)):
        cyl(mb, 0.44, -0.02, 0.56, 6, 'basalt', C_BASALT_TOP, False, 0.0, 0.10)
        cyl(mb, 0.14, 0.50, 0.84, 4, 'iron', C_IRON_RUST, False, 0.0, 0.016)

    # Heavy Forged-Iron Chain Spans (bold oversized tightly-interlocking links, ZERO floating mounts!)
    # Span A: Sagging suspension chain from Rear Pylon -> Iron Bollard bolted SOLIDLY into the rear stone parapet!
    p_shack_b = Vector((PYLON_X + 0.46, PYLON_B_TOP - 0.24, PYLON_B_Z))
    p_bollard = Vector((0.88, DECK_Y + 0.94, DECK_HALF_Z - 0.16))
    cbox(mb, (0.88, DECK_Y + 0.62, DECK_HALF_Z - 0.16), (0.36, 0.68, 0.36), 'iron', C_IRON, 0.0)
    with xf(mb, T(p_bollard) @ M_Y2Z):
        torus(mb, 0.15, 0.046, 6, 4, 'iron', C_IRON_RUST, False)
    _add_chain_links(mb, p_shack_b, p_bollard, n_links=5, link_r=0.205, wire_r=0.062, sag=0.46, rust_stride=2)

    # Span B: Dramatic SNAPPED heavy iron chain dangling freely from Front Pylon over the volcanic chasm!
    p_shack_f = Vector((PYLON_X + 0.46, PYLON_F_TOP - 0.24, PYLON_F_Z))
    p_snap_end = Vector((PYLON_X + 1.04, 1.66, PYLON_F_Z - 0.16))
    with xf(mb, T(p_shack_f) @ M_Y2Z):
        torus(mb, 0.15, 0.044, 6, 4, 'iron', C_IRON, False)
    _add_chain_links(mb, p_shack_f, p_snap_end, n_links=5, link_r=0.20, wire_r=0.060, sag=0.14, rust_stride=2)

    # Span C: Heavy anchor chain tying Rear Pylon back down to a port lava-crust iron mooring anchor!
    p_back_anc = Vector((-2.62, 1.06, PYLON_B_Z + 0.28))
    cbox(mb, p_back_anc - Vector((0.0, 0.18, 0.0)), (0.46, 0.42, 0.46), 'iron', C_IRON_RUST, 0.0)
    _add_chain_links(mb, Vector((PYLON_X - 0.42, PYLON_B_TOP - 0.24, PYLON_B_Z)), p_back_anc,
                     n_links=5, link_r=0.195, wire_r=0.058, sag=0.24, rust_stride=2)

    # Wind-whipped scorched crimson-and-ash bridge warning streamer lashed to Rear Pylon ('paint' + UV2!)
    _build_wind_pennant(
        mb, (PYLON_X + 0.18, PYLON_B_TOP + 0.34, PYLON_B_Z),
        length=1.64, h0=0.38, out_dir=(0.82, -0.08, -0.56),
        col_main=C_CRIMSON_HI, col_trim=C_ASH_DARK, phase=0.41,
    )

    # 5. Glowing Orange-Crimson Magma Veins Cracking Visibly Through the Dark Basalt Foundation ('glass'!)
    # Recessed magma chasm fissure beneath the broken bridge arch + dark cooled-basalt slag chunks atop it!
    POOL_CTR = Vector((0.68, 0.72, 0.02))
    ring_m = [Vector((POOL_CTR.x + cos(2.0 * pi * k / 7.0) * 0.46,
                      POOL_CTR.y + 0.02 * sin(k * 2.0),
                      POOL_CTR.z + sin(2.0 * pi * k / 7.0) * 0.56)) for k in range(7)]
    ring_o = [Vector((POOL_CTR.x + cos(2.0 * pi * k / 7.0) * 0.94,
                      POOL_CTR.y - 0.04,
                      POOL_CTR.z + sin(2.0 * pi * k / 7.0) * 1.12)) for k in range(7)]
    for k in range(7):
        kn = (k + 1) % 7
        mb.fp([POOL_CTR + Vector((0.0, 0.04, 0.0)), ring_m[kn], ring_m[k]], 'glass',
              [C_MAGMA_GLOW, C_MAGMA_CRIMSON, C_MAGMA_CRIMSON], (1, 0, 0), POOL_CTR - Vector((0.0, 0.8, 0.0)))
        mb.fp([ring_m[k], ring_m[kn], ring_o[kn], ring_o[k]], 'glass',
              [C_MAGMA_CRIMSON, C_MAGMA_CRIMSON, C_BASALT_HOT, C_BASALT_HOT], (1, 0, 0), POOL_CTR - Vector((0.0, 0.8, 0.0)))
    # Dark jagged cooled-basalt slag plates breaking up the glowing chasm fissure pool!
    for sp_p, sp_sz, sp_r in (
        ((0.46, 0.80, -0.22), (0.58, 0.22, 0.44), ( 5,  24, -8)),
        ((0.92, 0.78,  0.26), (0.54, 0.20, 0.42), (-6, -32,  9)),
    ):
        sculpt_stone_block(mb, sp_p, sp_sz, 'basalt', C_BASALT_DARK, rng, chip=0.04,
                           M=R('Y', sp_r[1]) @ R('X', sp_r[0]) @ R('Z', sp_r[2]))

    # 6 Bold surface-hugging glowing orange-crimson magma veins crawling across the basalt crags & abutment!
    magma_veins = [
        ([( 0.58, 0.82, -0.88), ( 0.34, 0.96, -1.56), ( 0.06, 0.68, -2.28), (-0.12, 0.32, -2.56)], [0.11, 0.095, 0.065, 0.032], ( 0.0,  0.70, -0.71)),
        ([( 0.82, 0.80,  0.90), ( 0.56, 0.94,  1.58), ( 0.28, 0.64,  2.26), ( 0.14, 0.28,  2.54)], [0.10, 0.090, 0.062, 0.030], ( 0.0,  0.70,  0.71)),
        ([(-0.46, 1.02, -1.32), (-0.98, 1.44, -1.62), (-1.42, 2.08, -1.58)],                       [0.08, 0.088, 0.036],        (-0.35, 0.32, -0.88)),
        ([(-1.72, 1.12, -1.66), (-2.12, 0.86, -2.14), (-2.44, 0.44, -2.42)],                       [0.095, 0.075, 0.034],       (-0.55, 0.60, -0.58)),
        ([( 1.42, 0.92, -0.78), ( 1.98, 0.88, -1.28), ( 2.42, 0.54, -1.68)],                       [0.090, 0.068, 0.032],       ( 0.52, 0.68, -0.52)),
        ([(-1.88, 1.16,  1.66), (-2.24, 0.86,  2.14), (-2.50, 0.44,  2.40)],                       [0.090, 0.070, 0.034],       (-0.50, 0.60,  0.62)),
    ]
    for vpath, vw, vn in magma_veins:
        _sculpt_magma_ribbon(mb, vpath, vw, vn, rng, hot_core=True)

    # 6. Sulfur-Encrusted Jagged Basalt Shards erupting along the fractured volcanic foundation!
    shard_specs = [
        ((-2.58, 0.68, -1.72), 1.62, 0.28, -24.0, -18.0),
        (( 2.52, 0.62, -1.36), 1.50, 0.26,  28.0, -16.0),
        (( 2.64, 0.66,  1.24), 1.56, 0.28,  26.0,  18.0),
        ((-2.50, 0.72,  1.78), 1.54, 0.27, -22.0,  20.0),
    ]
    for spos, sh, srad, stx, stz in shard_specs:
        sculpt_basalt_column(mb, spos, sh, srad, 5, stx, stz, C_BASALT_DARK, C_BASALT_TOP, rng, mat='basalt')

    # Crisp angular ochre-yellow sulfur crystal encrustations nestled around the magma crevices!
    sulfur_crusts = [
        ((-0.52, 0.96, -1.38), (0.38, 0.28, 0.34), ( 12,  22, -14), C_SULFUR_PALE),
        (( 1.28, 0.88, -1.14), (0.36, 0.26, 0.32), (-14, -18,  12), C_SULFUR_OCHRE),
        (( 1.48, 0.92,  1.10), (0.40, 0.28, 0.36), ( 10,  34,  -8), C_SULFUR_PALE),
        ((-1.58, 1.06, -1.62), (0.42, 0.30, 0.34), ( 14, -24,  10), C_SULFUR_OCHRE),
    ]
    for sc_p, sc_r, sc_rot, sc_col in sulfur_crusts:
        with xf(mb, T(sc_p) @ R('Y', sc_rot[1]) @ R('X', sc_rot[0]) @ R('Z', sc_rot[2])):
            cyl(mb, sc_r[0] * 0.72, -sc_r[1] * 0.4, sc_r[1] * 0.95, 5, 'basalt', sc_col, False, 0.0, sc_r[0] * 0.22)
            with xf(mb, T(sc_r[0] * 0.42, 0.02, -sc_r[2] * 0.22) @ R('Z', -28.0)):
                cyl(mb, sc_r[0] * 0.46, -0.06, sc_r[1] * 0.72, 4, 'basalt', C_SULFUR_DARK, False, 0.0, 0.04)

    # 7. Blazing Iron-Cage Fire Signal Brazier Crowning the Intact Front Parapet Pylon ('Lantern_VolcBridge'!)
    BRAZ_BASE = Vector((PYLON_X, PYLON_F_TOP, PYLON_F_Z))
    BRAZ_FLAME_POS = BRAZ_BASE + Vector((0.0, 0.56, 0.0))
    with xf(mb, T(BRAZ_BASE)):
        cyl(mb, 0.48, -0.06, 0.14, 7, 'iron', C_IRON, False, 0.0, 0.40)
        bowl_prof = [
            (0.00, 0.12), (0.36, 0.16), (0.56, 0.38), (0.62, 0.56),
            (0.54, 0.58), (0.44, 0.36), (0.00, 0.28),
        ]
        lathe(mb, bowl_prof, 7, 'iron', C_IRON, False, False,
              lambda i, k: C_IRON_RUST if i in (2, 4) else C_IRON)
        with xf(mb, T(0.0, 0.56, 0.0)):
            torus(mb, 0.60, 0.042, 7, 4, 'iron', C_IRON_RUST, False)
        with xf(mb, T(0.0, 0.90, 0.0)):
            torus(mb, 0.66, 0.032, 7, 4, 'iron', C_IRON, False)
        for k in range(6):
            ang = 2.0 * pi * k / 6.0
            ca, sa = cos(ang), sin(ang)
            spike_path = [
                (ca * 0.42, 0.20, sa * 0.42),
                (ca * 0.64, 0.56, sa * 0.64),
                (ca * 0.68, 0.90, sa * 0.68),
                (ca * 0.52, 1.16, sa * 0.52),
            ]
            tube(mb, spike_path, [0.052, 0.048, 0.038, 0.012], 4, 'iron',
                 C_IRON_RUST if k % 2 == 0 else C_IRON, mode='flat')
        for ck in range(4):
            ang = ck * pi * 0.5 + 0.3
            with xf(mb, T(cos(ang) * 0.28, 0.42, sin(ang) * 0.28) @ R('Z', 18.0)):
                cyl(mb, 0.14, -0.08, 0.12, 4, 'basalt', C_BASALT_DARK, False, 0.0, 0.07)

    _build_flame_cluster(mb, BRAZ_FLAME_POS - Vector((0.0, 0.14, 0.0)), radius=0.44, height=0.76, n_tongues=4)

    build(mb)

    add_empty('Lantern_VolcBridge', BRAZ_FLAME_POS)
    col_piece('col_volcbridge_base', col_pts)
    export_landmark_glb(outdir, 'volcanic_obsidian_bridge_ruin.glb')


ISLAND_LORE_GENERATORS = [
    gen_pirate_rum_distillery_shack,
    gen_ancient_jade_serpent_totem,
    gen_coastal_driftwood_arch_camp,
    gen_volcanic_obsidian_bridge_ruin,
]
