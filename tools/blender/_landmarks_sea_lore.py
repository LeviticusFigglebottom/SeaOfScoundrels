# Sea of Scoundrels: 4 sculpted 3D Sea-Lore & Harbour Craft Landmarks (Wave I-15 / Pass I-Q8 — 62-Landmark Fleet!).
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

# Warm coastal cobble, driftwood, fresh planed oak & tarred shipwright timber
C_COBBLE_LIGHT   = srgb('#cfc2aa')
C_COBBLE_MID     = srgb('#938672')
C_COBBLE_DARK    = srgb('#5b5349')
C_TIDE_DARK      = mix(C_LIME_DARK, C_SEA_MOSS, 0.44)
C_SAND_PALE      = srgb('#efe0be')
C_SAND_WARM      = srgb('#dcb680')
C_SAND_OCHRE     = srgb('#b38b59')
C_DRIFT_PALE     = srgb('#d0c2a8')
C_DRIFT_SHADE    = srgb('#796c5b')
C_OAK_FRESH      = srgb('#c99252')
C_OAK_PLANED     = srgb('#deb072')
C_OAK_CHAR       = srgb('#543a28')
C_PITCH_BLACK    = srgb('#1a171c')

# Sailcloth, camouflage tarp, & harbour paint accents
C_CANVAS_CREAM   = srgb('#eee3c6')
C_CANVAS_WARM    = srgb('#d7c296')
C_TEAL_BRIGHT    = srgb('#238e96')
C_TEAL_MUTED     = srgb('#2b6b6e')
C_CAMO_OLIVE     = srgb('#4b5d38')
C_CAMO_DRAB      = srgb('#716849')
C_CAMO_SLATE     = srgb('#39565a')
C_CRIMSON_HI     = srgb('#c53024')
C_CRIMSON_MID    = srgb('#92221a')
C_QUENCH_WATER   = srgb('#256978')

# Burnished brass, verdigris bronze, wrought steel & iron
C_GOLD_BRIGHT    = srgb('#f6cb4a')
C_BRASS_MIRROR   = srgb('#ffd96b')
C_BRASS_WARM     = srgb('#d8a23c')
C_BRASS_DARK     = srgb('#8d6422')
C_VERDIGRIS_HI   = srgb('#64bba4')
C_VERDIGRIS_MID  = srgb('#3a8d79')
C_VERDIGRIS_DK   = srgb('#245b4f')
C_STEEL_BRIGHT   = srgb('#b2bcc9')
C_STEEL_MID      = srgb('#707887')
C_IRON_FORGED    = srgb('#535866')
C_IRON_BRONZE    = srgb('#8e5332')

# Arcane turquoise tidal runes & prism crystal (used ONLY on ancient_tidal_obelisk_mirror!)
C_RUNE_CORE      = srgb('#6affec')
C_RUNE_MID       = srgb('#1cd8be')
C_RUNE_DEEP      = srgb('#0d8c80')

# Warm volcanic forge embers, molten cutlass & lantern flames (used ONLY with 'glass'!)
C_FLAME_CORE     = srgb('#ffeb80')
C_FLAME_MID      = srgb('#ff8e22')
C_FLAME_DEEP     = srgb('#dc3410')
C_MAGMA_CRIMSON  = srgb('#b8240c')
C_OBSIDIAN_HI    = srgb('#6d656c')
C_OBSIDIAN_SHINE = srgb('#524c56')
C_OBSIDIAN_DARK  = srgb('#353139')
C_COAL_CHAR      = srgb('#292428')

# Lush coastal fern & cliff-ivy foliage tones
C_VINE_DARK      = srgb('#164a1e')
C_VINE_MID       = srgb('#2d7426')
C_VINE_SUN       = srgb('#78bc2a')


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
        cyl(mb, 0.172 * s, 0.15 * s, 0.23 * s, 6, cage_mat, cage_col, False, 0.0, 0.072 * s)
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
                         segs=6, stripe_col=None, open_fill=None):
    """Chunky coopered pirate rum/tar/quench cask with forged-iron hoops."""
    hh = height * 0.5
    if open_fill is not None:
        prof = [
            (0.0,           -hh),
            (radius * 0.82, -hh),
            (radius,         0.0),
            (radius * 0.84,  hh),
            (radius * 0.72,  hh),
            (radius * 0.72,  hh - 0.12),
            (0.0,            hh - 0.12),
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
              lambda i, k: col_head if (i == 0 or (open_fill is None and i == 3)) else stave_cols[k])
        for hi_idx, (hy, hr) in enumerate(((-hh * 0.62, radius * 0.94), (hh * 0.62, radius * 0.94))):
            cyl(mb, hr, hy - 0.028, hy + 0.028, segs, 'iron',
                C_IRON_RUST if hi_idx == 1 else C_IRON, False, 0.0)
        if stripe_col is not None:
            cyl(mb, radius * 1.015, -hh * 0.17, hh * 0.17, segs, 'paint', stripe_col, False, 0.0)
        if open_fill is not None:
            fill_mat, fill_col = open_fill
            cyl(mb, radius * 0.71, hh - 0.14, hh - 0.09, segs, fill_mat, fill_col, False, 0.0)


def _build_treasure_chest(mb, M_chest, size=(0.90, 0.44, 0.56), open_deg=0.0):
    """Chunky iron-strapped oak pirate treasure chest with arched barrel lid & brass lockplate."""
    w, h, d = size
    hw, hh, hd = w * 0.5, h * 0.5, d * 0.5
    with xf(mb, M_chest):
        cbox(mb, (0.0, hh, 0.0), (w, h, d), 'timber', C_TIMBER_MID, 0.0, (1, 0, 0))
        for xs in (-hw + 0.05, 0.0, hw - 0.05):
            cbox(mb, (xs, hh, -hd - 0.012), (0.072, h + 0.02, 0.028), 'iron', C_IRON, 0.0)
            cbox(mb, (xs, hh,  hd + 0.012), (0.072, h + 0.02, 0.028), 'iron', C_IRON, 0.0)
        for sx in (-hw - 0.014, hw + 0.014):
            with xf(mb, T(sx, hh + 0.02, 0.0) @ M_Y2X):
                torus(mb, 0.068, 0.016, 5, 4, 'iron', C_IRON_RUST, False)
        cbox(mb, (0.0, h - 0.10, -hd - 0.026), (0.17, 0.19, 0.028), 'brass', C_GOLD_BRIGHT, 0.0)
        lid_M = T(0.0, h, hd) @ R('X', open_deg) @ T(0.0, 0.0, -hd)
        with xf(mb, lid_M):
            r_lid = hd * 1.02
            lid_ring = [(cos(pi * k / 4.0) * r_lid, sin(pi * k / 4.0) * 0.22) for k in range(5)]
            secs = [
                [Vector((-hw - 0.02, py, -pz)) for pz, py in lid_ring] + [Vector((-hw - 0.02, 0.0, -hd))],
                [Vector(( hw + 0.02, py, -pz)) for pz, py in lid_ring] + [Vector(( hw + 0.02, 0.0, -hd))],
            ]
            loft(mb, secs, 'timber', C_TIMBER_HI, closed=True, caps=(True, True), mode='flat')
            for xs in (-hw + 0.05, 0.0, hw - 0.05):
                rib_pts = [Vector((xs, sin(pi * k / 4.0) * 0.245, -cos(pi * k / 4.0) * (r_lid + 0.02)))
                           for k in range(5)]
                tube(mb, rib_pts, 0.028, 4, 'iron', C_IRON, mode='flat')


def _build_rope_coil_lean(mb, center, radius=0.28, turns=3, r=0.038, segs=7, psegs=4, col=C_ROPE):
    """Chunky coiled braided hemp rope pile ('rope')."""
    for i in range(turns):
        rr = radius * (1.0 - 0.22 * i)
        with xf(mb, T(center[0], center[1] + r * (1.0 + i * 1.58), center[2])):
            torus(mb, rr, r, segs, psegs, 'rope', mul(col, 0.88 + 0.12 * (i % 2)), True)


def _add_leafy_vine_drape(mb, anchor, length, width, out_dir, rng, phase=0.0,
                          c_dark=C_VINE_DARK, c_mid=C_VINE_MID, c_sun=C_VINE_SUN):
    """Sculpted hanging leafy sea-ivy / jungle vine ('foliage') with UV2 wind weights (0 root -> 0.96 tip)."""
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
        out_off = 0.04 + 0.11 * sin(t * pi * 0.78) + 0.06 * t
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

    n_leaves = max(5, int(length * 2.1))
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
    """Broad painterly coastal fern / sea-fern rosette ('foliage') with UV2 wind weights."""
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
                     segs=5, psegs=4, sag=0.34, mat='iron', rust_stride=2, stretch_y=1.42,
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


def _build_pulley_block(mb, center, radius=0.22, yaw_deg=0.0, has_hook=False):
    """Chunky iron-strapped wooden pulley sheave block with brass wheel & optional forged hook."""
    with xf(mb, T(center) @ R('Y', yaw_deg)):
        for sx in (-0.095, 0.095):
            cbox(mb, (sx, 0.0, 0.0), (0.064, radius * 2.45, radius * 2.00), 'timber', C_TIMBER_MID, 0.0)
        cbox(mb, (0.0,  radius * 1.28, 0.0), (0.27, 0.055, 0.14), 'iron', C_IRON, 0.0)
        cbox(mb, (0.0, -radius * 1.28, 0.0), (0.27, 0.055, 0.14), 'iron', C_IRON, 0.0)
        with xf(mb, M_Y2X):
            cyl(mb, radius * 0.88, -0.054, 0.054, 6, 'brass', C_GOLD_BRIGHT, False, 0.0)
            cyl(mb, 0.042, -0.155, 0.155, 5, 'iron', C_IRON, False, 0.0)
        with xf(mb, T(0.0, radius * 1.52, 0.0) @ M_Y2Z):
            torus(mb, 0.078, 0.022, 6, 4, 'iron', C_IRON_RUST, False)
        if has_hook:
            hook_path = [
                (0.0, -radius * 1.30, 0.0),
                (0.0, -radius * 1.85, 0.0),
                (0.0, -radius * 2.34, -0.14),
                (0.0, -radius * 2.48,  0.04),
                (0.0, -radius * 2.12,  0.20),
            ]
            tube(mb, hook_path, [0.040, 0.046, 0.048, 0.040, 0.020], 4, 'iron', C_IRON, mode='flat')


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
        mid_pts.append(pts[i] + nrm * (0.052 + 0.012 * sin(i * 1.7)))
    for i in range(n - 1):
        c_mid = C_FLAME_CORE if (hot_core and i <= 1) else C_MAGMA_GLOW
        c_edge = C_MAGMA_CRIMSON if i < n - 2 else C_BASALT_HOT
        inside = (pts[i] + pts[i + 1]) * 0.5 - nrm * 0.5
        mb.fp([left_pts[i], mid_pts[i], mid_pts[i + 1], left_pts[i + 1]], 'glass',
              [c_edge, c_mid, c_mid, c_edge], (1, 0, 0), inside, smooth=False)
        mb.fp([mid_pts[i], right_pts[i], right_pts[i + 1], mid_pts[i + 1]], 'glass',
              [c_mid, c_edge, c_edge, c_mid], (1, 0, 0), inside, smooth=False)


# ================================================================ 1. PIRATE SHIPWRIGHT TIMBER RACK

def gen_pirate_shipwright_timber_rack(outdir):
    """Open-air harbour shipwright lumber & sail-mending yard grounded on a stepped cobbled &
    driftwood apron plunging cleanly to y = -2.80 m (footprint hx ~ 2.60 m, hz ~ 2.25 m).
    Features a stout timber A-frame drying rack holding seasoned curved oak hull-ribs & stacked
    air-drying oak planks, overhead crossbar yardarm suspending a wind-swaying patched cream-and-teal
    stitched spare sail ('paint' + UV2 wind weights), blacksmith tar/pitch cauldron resting on a low
    stone hearth with warm glowing coals ('glass' molten colors), oak carpentry sawhorse & wooden
    caulking mallet, coiled tarred hemp rope, iron-hooped tar barrel, coastal fern tufts ('foliage'
    + UV2), collider 'col_shipyard_base', and warm brass lantern empty 'Lantern_Shipyard'.
    Target: ~3,100-3,700 visual tris, 1 collider (col_shipyard_base).
    """
    clear_scene()
    rng = random.Random(SEED + 2811)
    mb = MB('PirateShipwrightTimberRack', seed=2811)

    SKIRT_BOT = -2.80
    STEP_Y    = 0.04
    FLOOR_Y   = 0.22
    col_pts   = []

    # 1. Stepped Cobbled & Driftwood Apron Plinth plunging cleanly to y = -2.80 m (hx=2.60, hz=2.25!)
    apron_secs = [
        _rect_oct(0.0, SKIRT_BOT, 0.0, 2.74, 2.38, 0.54),
        _rect_oct(0.0, -1.10,     0.0, 2.64, 2.28, 0.48),
        _rect_oct(0.0, STEP_Y,    0.0, 2.58, 2.22, 0.42),
    ]
    _loft_horizontal_masonry(
        mb, apron_secs, 'limestone_moss',
        [C_TIDE_DARK, C_COBBLE_DARK, C_COBBLE_MID],
        rng, caps=(True, True), top_mat='limestone_moss', top_col=C_COBBLE_MID,
    )
    for ring in apron_secs:
        col_pts.extend(Vector(p) for p in ring)

    # Raised upper working terrace step (z = -1.68 .. +2.10, y = STEP_Y .. FLOOR_Y) with driftwood timber curbs!
    upper_secs = [
        _rect_oct(0.0, STEP_Y - 0.04, 0.20, 2.46, 1.92, 0.34),
        _rect_oct(0.0, FLOOR_Y,       0.20, 2.40, 1.86, 0.32),
    ]
    _loft_horizontal_masonry(
        mb, upper_secs, 'temple_stone',
        [C_COBBLE_DARK, C_COBBLE_LIGHT],
        rng, caps=(False, True), top_mat='limestone_moss', top_col=C_COBBLE_MID,
    )
    # Driftwood curbing sleepers framing the stepped shipyard apron + weathered cobble flagstones
    cbox(mb, (0.0, FLOOR_Y - 0.02, -1.68), (4.24, 0.16, 0.22), 'timber', C_DRIFTWOOD, 0.0, (1, 0, 0))
    cbox(mb, (0.0, FLOOR_Y + 0.03,  2.02), (4.18, 0.14, 0.20), 'timber', C_DRIFT_SHADE, 0.0, (1, 0, 0))
    for sx in (-2.34, 2.34):
        cbox(mb, (sx, FLOOR_Y + 0.02, 0.20), (0.20, 0.14, 3.24), 'timber', C_DRIFTWOOD, 0.0, (0, 0, 1))
    # Seaward cobble landing step blocks along front apron (-Z)
    for sx in (-1.30, -0.42, 0.48, 1.34):
        cbox(mb, (sx, STEP_Y + 0.04, -1.94), (0.76, 0.12, 0.42), 'temple_stone',
             jit(C_COBBLE_LIGHT, rng, 0.07), 0.0, (1, 0, 0))
    # Flat workshop flagstones set slightly proud on deck
    for fx, fz, fw, fd, fyaw in (
        (-0.98, -0.92, 0.92, 0.68,   8.0),
        ( 0.04, -0.68, 0.84, 0.62,  -6.0),
        ( 1.24, -0.82, 0.96, 0.84,  14.0),
        (-0.22,  0.48, 1.05, 0.66,  -4.0),
        ( 1.02,  0.65, 0.82, 0.58,  10.0),
    ):
        cbox(mb, (fx, FLOOR_Y + 0.018, fz), (fw, 0.048, fd),
             'temple_stone', jit(C_COBBLE_LIGHT, rng, 0.07), 0.0, M=R('Y', fyaw))
    # Twin stout harbour timber bollard posts on front corners of apron
    for bx, bz in ((-2.18, -1.78), (2.18, -1.78)):
        with xf(mb, T(bx, STEP_Y, bz)):
            cyl(mb, 0.135, -0.06, 0.56, 6, 'timber', C_DRIFT_SHADE, False, 0.0, 0.118)
            cyl(mb, 0.145,  0.42, 0.49, 6, 'iron', C_IRON_RUST, False, 0.0)

    # 2. Stout Timber A-Frame Drying Rack & Overhead Sail-Mending Yardarm (z = +0.58 m, peak y = 4.28 m!)
    RACK_Z   = 0.58
    APEX_Y   = 4.26
    YARD_Y   = 4.18
    LEG_F_Z  = -0.26
    LEG_B_Z  =  1.42

    for sx in (-1.68, 1.68):
        p_fl_bot = Vector((sx, FLOOR_Y - 0.06, LEG_F_Z))
        p_bl_bot = Vector((sx, FLOOR_Y - 0.06, LEG_B_Z))
        p_apex_f = Vector((sx, APEX_Y + 0.14, RACK_Z + 0.08))
        p_apex_b = Vector((sx, APEX_Y + 0.14, RACK_Z - 0.08))
        # Heavy squared oak A-frame legs
        _add_beam(mb, p_fl_bot, p_apex_f, 0.17, 0.17, 'timber', C_TIMBER_MID, 0.0)
        _add_beam(mb, p_bl_bot, p_apex_b, 0.17, 0.17, 'timber', C_TIMBER_DARK, 0.0)
        # Iron anchor base shoes bolted into apron
        cbox(mb, (sx, FLOOR_Y + 0.09, LEG_F_Z), (0.28, 0.18, 0.28), 'iron', C_IRON, 0.0)
        cbox(mb, (sx, FLOOR_Y + 0.09, LEG_B_Z), (0.28, 0.18, 0.28), 'iron', C_IRON_RUST, 0.0)
        # Lower & mid horizontal A-frame cross-ties
        t1 = (1.16 - FLOOR_Y) / (APEX_Y - FLOOR_Y)
        z_f1 = LEG_F_Z + (RACK_Z - LEG_F_Z) * t1
        z_b1 = LEG_B_Z + (RACK_Z - LEG_B_Z) * t1
        _add_beam(mb, (sx, 1.16, z_f1 - 0.12), (sx, 1.16, z_b1 + 0.12), 0.13, 0.15, 'timber', C_TIMBER_HI, 0.0)
        t2 = (2.62 - FLOOR_Y) / (APEX_Y - FLOOR_Y)
        z_f2 = LEG_F_Z + (RACK_Z - LEG_F_Z) * t2
        z_b2 = LEG_B_Z + (RACK_Z - LEG_B_Z) * t2
        _add_beam(mb, (sx, 2.62, z_f2 - 0.10), (sx, 2.62, z_b2 + 0.10), 0.12, 0.13, 'timber', C_TIMBER_MID, 0.0)
        # Forged-iron gusset plate + heavy hemp rope lashing collar at each A-frame apex
        cbox(mb, (sx, APEX_Y - 0.22, RACK_Z), (0.24, 0.24, 0.30), 'iron', C_IRON, 0.0)
        with xf(mb, T(sx, APEX_Y - 0.04, RACK_Z) @ R('X', 38.0) @ R('Z', 18.0)):
            torus(mb, 0.19, 0.036, 6, 4, 'rope', C_ROPE, False)
        col_pts.append(Vector((sx, 2.40, RACK_Z)))

    # Overhead tapered oak yardarm crossbar spanning the A-frame apexes (x = -2.32 .. +2.32 m)
    tube(mb, [
        (-2.32, YARD_Y, RACK_Z),
        (-1.68, YARD_Y + 0.03, RACK_Z),
        ( 0.00, YARD_Y + 0.05, RACK_Z),
        ( 1.68, YARD_Y + 0.03, RACK_Z),
        ( 2.32, YARD_Y, RACK_Z),
    ], [0.088, 0.118, 0.126, 0.118, 0.088], 6, 'timber', C_DRIFT_PALE, mode='flat')
    for ex in (-2.30, 2.30):
        with xf(mb, T(ex, YARD_Y, RACK_Z) @ M_Y2X):
            cyl(mb, 0.096, -0.05, 0.05, 6, 'iron', C_IRON_RUST, False, 0.0)
            cyl(mb, 0.068,  0.05, 0.14, 6, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.024)

    # Rear longitudinal timber rail + diagonal cross-braces stiffening the drying rack
    _add_beam(mb, (-1.82, 1.18, 1.20), ( 1.82, 1.18, 1.20), 0.13, 0.14, 'timber', C_TIMBER_DARK, 0.0)
    _add_beam(mb, (-1.82, 0.56, 1.32), ( 1.82, 0.56, 1.32), 0.13, 0.14, 'timber', C_TIMBER_MID, 0.0)
    _add_beam(mb, (-1.68, 1.20, 1.20), (-0.78, 2.60, 0.94), 0.10, 0.10, 'timber', C_TIMBER_DARK, 0.0)
    _add_beam(mb, ( 1.68, 1.20, 1.20), ( 0.78, 2.60, 0.94), 0.10, 0.10, 'timber', C_TIMBER_DARK, 0.0)
    # Upper front knee braces from legs to yardarm
    _add_beam(mb, (-1.68, 3.32, 0.36), (-1.04, YARD_Y - 0.06, RACK_Z), 0.10, 0.10, 'timber', C_TIMBER_DARK, 0.0)
    _add_beam(mb, ( 1.68, 3.32, 0.36), ( 1.04, YARD_Y - 0.06, RACK_Z), 0.10, 0.10, 'timber', C_TIMBER_DARK, 0.0)

    # 3. Seasoned Curved Oak Ship Hull-Ribs & Air-Drying Stacked Lumber Planks!
    #    4 sweeping steam-bent curved oak ship hull-ribs leaning proudly in the timber rack (x = -1.26 .. +0.34)
    rib_specs = [
        (-1.26, 0.96, 1.98, C_OAK_FRESH),
        (-0.82, 0.92, 2.14, C_TIMBER_HI),
        (-0.36, 0.96, 2.02, C_OAK_PLANED),
        ( 0.10, 0.94, 1.88, C_OAK_FRESH),
    ]
    for rx, rz0, rh, rcol in rib_specs:
        # Sweeping J-curved oak hull frame rib rooted firmly on the floor crib & propped on the rail!
        rib_pts = [
            Vector((rx, FLOOR_Y + 0.08, rz0 - 0.42)),
            Vector((rx, FLOOR_Y + 0.24, rz0 + 0.04)),
            Vector((rx, FLOOR_Y + 0.72, rz0 + 0.34)),
            Vector((rx, FLOOR_Y + 1.38, rz0 + 0.42)),
            Vector((rx, FLOOR_Y + rh,   rz0 + 0.26)),
        ]
        # Rectangular oak timber frame cross-section lofted along the curved rib!
        secs = []
        hw, ht = 0.062, 0.088
        for i, p in enumerate(rib_pts):
            t_v = rib_pts[min(i + 1, len(rib_pts) - 1)] - rib_pts[max(i - 1, 0)]
            t_v.normalize()
            up_n = Vector((0.0, t_v.z, -t_v.y)).normalized()
            sx_v = Vector((1.0, 0.0, 0.0))
            taper = 1.0 - 0.16 * (i / float(len(rib_pts) - 1))
            secs.append([
                p - sx_v * (hw * taper) - up_n * (ht * taper),
                p + sx_v * (hw * taper) - up_n * (ht * taper),
                p + sx_v * (hw * taper) + up_n * (ht * taper),
                p - sx_v * (hw * taper) + up_n * (ht * taper),
            ])
        loft(mb, secs, 'timber', jit(rcol, rng, 0.05), closed=True, caps=(True, True), mode='flat')
        # Iron bolted rib-clamp band at mid-height
        cbox(mb, rib_pts[2], (0.15, 0.08, 0.20), 'iron', C_IRON, 0.0)

    # Neat Stacked Air-Drying Seasoned Oak Planks with wooden spacer stickers on starboard rack (x = +0.42 .. +1.56)
    for bx in (0.58, 1.36):
        cbox(mb, (bx, FLOOR_Y + 0.08, 0.94), (0.14, 0.16, 0.88), 'timber', C_TIMBER_DARK, 0.0, (0, 0, 1))
    for layer in range(4):
        ly = FLOOR_Y + 0.20 + layer * 0.145
        for pk in range(3):
            pz = 0.66 + pk * 0.28 + rng.uniform(-0.015, 0.015)
            plen = 1.24 + rng.uniform(-0.08, 0.12)
            px = 0.98 + rng.uniform(-0.05, 0.05)
            pcol = jit(C_OAK_PLANED if (layer + pk) % 2 == 0 else C_OAK_FRESH, rng, 0.06)
            cbox(mb, (px, ly, pz), (plen, 0.074, 0.22), 'timber', pcol, 0.0, (1, 0, 0))
        if layer < 3:
            for bx in (0.62, 1.32):
                cbox(mb, (bx, ly + 0.062, 0.94), (0.075, 0.050, 0.82), 'timber', C_DRIFT_SHADE, 0.0, (0, 0, 1))

    # 4. Wind-Swaying Patched Cream-and-Teal Stitched Spare Sail ('paint' + UV2 Wind Weights!)
    #    Suspended cleanly from the overhead yardarm crossbar (y = 4.08 -> 1.82 m), gently billowing seaward!
    snu, snv = 7, 6
    s_thick  = 0.022
    SAIL_X0, SAIL_X1 = -1.36, 1.22
    SAIL_Y_TOP = YARD_Y - 0.10
    SAIL_H     = 2.18

    def _sail_pt(u, v):
        # u across sail width (-1.36 .. +1.22), v top-to-bottom (0 at yardarm -> 1 at billowing foot!)
        x = SAIL_X0 + u * (SAIL_X1 - SAIL_X0) + sin(v * pi) * 0.06 * (u - 0.5)
        y = SAIL_Y_TOP - v * SAIL_H + 0.12 * sin(u * pi) * (v ** 1.4)  # gentle nautical roach curve at foot!
        # Sea-breeze billow arching gently toward -Z (seaward), pinned cleanly under the yardarm at v=0!
        belly = sin(v * pi * 0.82) * (0.28 + 0.24 * sin(u * pi))
        ripple = sin(u * pi * 3.0 + v * pi * 1.8) * 0.055 * v
        z = RACK_Z - 0.04 - belly + ripple
        return Vector((x, y, z))

    def _sail_w(u, v):
        # 0 at top yardarm robands (v=0), sweeping cleanly up to 0.94 at free billowing foot (v=1)!
        edge_boost = 0.82 + 0.18 * sin(u * pi)
        return min(0.95, max(0.0, (v ** 1.25) * 0.94 * edge_boost))

    sf_g = [[None] * (snv + 1) for _ in range(snu + 1)]
    sb_g = [[None] * (snv + 1) for _ in range(snu + 1)]
    sw_g = [[0.0]  * (snv + 1) for _ in range(snu + 1)]
    for iu in range(snu + 1):
        u = iu / float(snu)
        for iv in range(snv + 1):
            v = iv / float(snv)
            p = _sail_pt(u, v)
            pu = _sail_pt(min(1.0, u + 0.02), v) - _sail_pt(max(0.0, u - 0.02), v)
            pv = _sail_pt(u, min(1.0, v + 0.02)) - _sail_pt(u, max(0.0, v - 0.02))
            n = pu.cross(pv)
            if n.z > 0.0:
                n = -n
            n = n.normalized() if n.length > 1e-6 else Vector((0.0, 0.0, -1.0))
            sf_g[iu][iv] = p + n * (s_thick * 0.5)
            sb_g[iu][iv] = p - n * (s_thick * 0.5)
            sw_g[iu][iv] = _sail_w(u, v)

    def _sail_col(iu, iv):
        # Patched cream-and-teal stitched spare sail with warm ochre & crimson repair patches!
        if (iu == 1 and iv == 3) or (iu == 5 and iv == 2):
            c = C_SAND_WARM  # stitched canvas repair patch
        elif iu == 4 and iv == 4:
            c = C_CRIMSON_MID  # old brigantine red repair patch!
        elif iu in (1, 4):
            c = C_TEAL_BRIGHT if (iv % 2 == 0) else C_TEAL_MUTED
        elif iv == 0 or iv == snv - 1:
            c = C_CANVAS_WARM  # reinforced bolt-rope hem bands
        else:
            c = C_CANVAS_CREAM if ((iu + iv) % 2 == 0) else C_CANVAS_WARM
        return jit(c, rng, 0.032, 0.012)

    mb.newoff()
    s_phase = 0.27
    for iu in range(snu):
        for iv in range(snv):
            cf = _sail_col(iu, iv)
            cb = mul(cf, 0.85)
            f00, f10, f11, f01 = sf_g[iu][iv], sf_g[iu + 1][iv], sf_g[iu + 1][iv + 1], sf_g[iu][iv + 1]
            b00, b10, b11, b01 = sb_g[iu][iv], sb_g[iu + 1][iv], sb_g[iu + 1][iv + 1], sb_g[iu][iv + 1]
            u00 = (sw_g[iu][iv], s_phase)
            u10 = (sw_g[iu + 1][iv], s_phase)
            u11 = (sw_g[iu + 1][iv + 1], s_phase)
            u01 = (sw_g[iu][iv + 1], s_phase)
            ctr = (f00 + f11 + b00 + b11) * 0.25
            mb.fp([f00, f10, f11, f01], 'paint', cf, (0, 1, 0), ctr + Vector((0.0, 0.0, 1.5)),
                  smooth=False, uv2=[u00, u10, u11, u01])
            mb.fp([b00, b01, b11, b10], 'paint', cb, (0, 1, 0), ctr - Vector((0.0, 0.0, 1.5)),
                  smooth=False, uv2=[u00, u01, u11, u10])
            if iv == snv - 1:
                mb.fp([b01, f01, f11, b11], 'paint', mul(cf, 0.78), (1, 0, 0), ctr + Vector((0.0, 1.0, 0.0)),
                      uv2=[u01, u01, u11, u11])
            if iu == 0:
                mb.fp([b00, b01, f01, f00], 'paint', mul(cf, 0.78), (0, 1, 0), ctr + Vector((1.0, 0.0, 0.0)),
                      uv2=[u00, u01, u01, u00])
            if iu == snu - 1:
                mb.fp([f10, f11, b11, b10], 'paint', mul(cf, 0.78), (0, 1, 0), ctr - Vector((1.0, 0.0, 0.0)),
                      uv2=[u10, u11, u11, u10])

    # Hemp robands tying the sail cleanly onto the overhead yardarm + corner brass cringle rings & sheet lines!
    for iu in range(0, snu + 1):
        px = SAIL_X0 + (iu / float(snu)) * (SAIL_X1 - SAIL_X0)
        with xf(mb, T(px, YARD_Y + 0.02, RACK_Z) @ M_Y2X):
            torus(mb, 0.132, 0.022, 6, 4, 'rope', C_ROPE, False)
    # Trailing lower sail clew sheet-ropes tied loosely to the A-frame legs
    for clew_p, tie_p in (
        (sf_g[0][snv],   Vector((-1.68, 1.72, 0.14))),
        (sf_g[snu][snv], Vector(( 1.68, 1.78, 0.16))),
    ):
        mid_r = clew_p.lerp(tie_p, 0.5) - Vector((0.0, 0.16, 0.0))
        tube(mb, [clew_p, mid_r, tie_p], 0.020, 4, 'rope', C_ROPE, mode='flat')

    # 5. Blacksmith Tar/Pitch Cauldron on Low Stone Hearth with Warm Glowing Coals (starboard-front!)
    H_X, H_Z = 1.24, -0.82
    hearth_secs = [
        _reg_poly(H_X, FLOOR_Y - 0.04, H_Z, 0.64, sides=8, rot_deg=22.5),
        _reg_poly(H_X, FLOOR_Y + 0.34, H_Z, 0.58, sides=8, rot_deg=22.5),
        _reg_poly(H_X, FLOOR_Y + 0.44, H_Z, 0.52, sides=8, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, hearth_secs, 'temple_stone',
        [C_COBBLE_DARK, C_COBBLE_MID, C_COBBLE_LIGHT],
        rng, caps=(False, True), top_mat='basalt', top_col=C_COAL_CHAR,
    )
    # Stone hearth rim kerbstones surrounding the glowing ember bed
    for hk in range(8):
        ang = radians(hk * 45.0)
        cbox(mb, (H_X + cos(ang) * 0.46, FLOOR_Y + 0.48, H_Z + sin(ang) * 0.46),
             (0.24, 0.13, 0.18), 'temple_stone', jit(C_COBBLE_MID, rng, 0.06), 0.0, M=R('Y', -degrees(ang)))

    # Warm glowing orange-amber coal mound ('glass' + molten COLOR_0!) + charred wood chunks
    with xf(mb, T(H_X, FLOOR_Y + 0.42, H_Z)):
        coal_prof = [
            (0.00, 0.00),
            (0.42, 0.02),
            (0.34, 0.14),
            (0.18, 0.22),
            (0.00, 0.24),
        ]
        lathe(mb, coal_prof, 6, 'glass', C_FLAME_MID, False, False,
              lambda i, k: C_FLAME_CORE if i >= 2 else C_FLAME_DEEP)
        for ck in range(4):
            ang = radians(ck * 90.0 + 25.0)
            cbox(mb, (cos(ang) * 0.24, 0.12, sin(ang) * 0.24),
                 (0.14, 0.08, 0.11), 'basalt', C_COAL_CHAR, 0.0, M=R('Y', ck * 55.0) @ R('Z', 18.0))

    # Forged-iron cauldron trivet legs & bulbous cast-iron pitch cauldron filled with dark glossy pitch!
    for tk in range(3):
        ang = radians(tk * 120.0 + 30.0)
        _add_beam(mb,
                  (H_X + cos(ang) * 0.40, FLOOR_Y + 0.42, H_Z + sin(ang) * 0.40),
                  (H_X + cos(ang) * 0.30, FLOOR_Y + 0.80, H_Z + sin(ang) * 0.30),
                  0.048, 0.048, 'iron', C_IRON, 0.0)
    with xf(mb, T(H_X, FLOOR_Y + 0.64, H_Z)):
        caul_prof = [
            (0.00, 0.00),
            (0.28, 0.04),
            (0.42, 0.20),
            (0.40, 0.40),
            (0.44, 0.47),
            (0.36, 0.48),
            (0.33, 0.35),
            (0.00, 0.34),
        ]
        lathe(mb, caul_prof, 8, 'iron', C_IRON, False, False,
              lambda i, k: C_IRON_RUST if i in (2, 4) else C_IRON)
        # Dark glossy tar/pitch pool brimming inside cauldron + wooden caulking stirring paddle!
        cyl(mb, 0.35, 0.32, 0.39, 8, 'basalt', C_PITCH_BLACK, False, 0.0)
        for sx in (-0.43, 0.43):
            with xf(mb, T(sx, 0.34, 0.0) @ M_Y2X):
                torus(mb, 0.068, 0.018, 5, 4, 'iron', C_IRON_RUST, False)
        # Wooden stirring paddle resting diagonally in the pitch cauldron
        _add_beam(mb, (-0.12, 0.34, 0.06), (0.34, 0.96, -0.14), 0.042, 0.042, 'timber', C_TIMBER_MID, 0.0)
        cbox(mb, (0.34, 0.96, -0.14), (0.11, 0.04, 0.06), 'timber', C_TIMBER_HI, 0.0, M=R('Z', -30.0))

    # 6. Oak Carpentry Sawhorse, Clamped Plank & Wooden Caulking Mallet (port-front!)
    SH_M = T(-0.96, FLOOR_Y, -0.92) @ R('Y', 18.0)
    with xf(mb, SH_M):
        # Stout carpentry sawhorse spine beam & 4 splayed braced legs (top y = 0.80 m above floor!)
        cbox(mb, (0.0, 0.74, 0.0), (1.38, 0.13, 0.15), 'timber', C_TIMBER_MID, 0.0, (1, 0, 0))
        for sx in (-0.52, 0.52):
            for sz in (-1.0, 1.0):
                _add_beam(mb, (sx, -0.02, sz * 0.36), (sx * 0.92, 0.74, sz * 0.05),
                          0.092, 0.092, 'timber', C_TIMBER_DARK, 0.0)
            _add_beam(mb, (sx, 0.24, -0.26), (sx, 0.24, 0.26), 0.070, 0.080, 'timber', C_TIMBER_HI, 0.0)
        # Freshly planed oak ship-deck plank resting across the sawhorse + forged iron clamp!
        cbox(mb, (0.08, 0.85, 0.02), (1.68, 0.072, 0.28), 'timber', C_OAK_PLANED, 0.0, (1, 0, 0))
        cbox(mb, (-0.36, 0.82, -0.14), (0.055, 0.26, 0.042), 'iron', C_IRON, 0.0)
        cbox(mb, (-0.36, 0.93, -0.06), (0.055, 0.042, 0.18), 'iron', C_IRON, 0.0)
        cbox(mb, (-0.36, 0.70, -0.06), (0.055, 0.042, 0.18), 'iron', C_IRON_RUST, 0.0)
        # Chunky Shipwright's Wooden Caulking Mallet resting atop the planed oak plank!
        with xf(mb, T(0.36, 0.95, 0.03) @ R('Y', -32.0)):
            with xf(mb, M_Y2X):
                cyl(mb, 0.072, -0.15, 0.15, 6, 'timber', C_TIMBER_MID, False, 0.0, 0.072)
                for hx in (-0.11, 0.11):
                    cyl(mb, 0.078, hx - 0.016, hx + 0.016, 6, 'iron', C_IRON_FORGED, False, 0.0)
            _add_beam(mb, (0.0, 0.0, 0.0), (0.0, -0.02, 0.44), 0.038, 0.038, 'timber', C_OAK_FRESH, 0.0)
        # Iron shipwright's handsaw resting diagonally at the port end of the plank
        with xf(mb, T(-0.62, 0.90, 0.04) @ R('Y', 38.0)):
            cbox(mb, (0.0, 0.0, 0.0), (0.48, 0.014, 0.11), 'iron', C_STEEL_BRIGHT, 0.0)
            cbox(mb, (-0.28, 0.01, 0.0), (0.14, 0.036, 0.13), 'timber', C_TIMBER_DARK, 0.0)
        # Scattered oak offcut blocks on the cobbles beneath the sawhorse
        cbox(mb, (-0.18, 0.04, -0.26), (0.36, 0.068, 0.14), 'timber', C_OAK_FRESH, 0.0, M=R('Y', 24.0))
        cbox(mb, ( 0.24, 0.035, 0.22), (0.28, 0.058, 0.12), 'timber', C_OAK_PLANED, 0.0, M=R('Y', -36.0))

    # 7. Iron-Hooped Tar Barrel, Coiled Tarred Hemp Rope, Hanging Yardarm Tackle, Lantern & Coastal Ferns!
    _build_coopered_cask(
        mb, T(-1.84, FLOOR_Y + 0.39, -0.56),
        radius=0.31, height=0.78, rng=rng,
        col_a=C_TIMBER_DARK, col_b=C_TIMBER_MID, col_head=C_PITCH_BLACK,
        segs=7, stripe_col=C_TEAL_BRIGHT,
    )
    # Coiled tarred hemp rope pile on the cobbles + yardarm-hung lifting pulley block rigged to port leg!
    _build_rope_coil_lean(mb, (0.22, FLOOR_Y, -1.32), radius=0.30, turns=3, r=0.040, segs=7, psegs=4, col=mul(C_ROPE, 0.86))
    with xf(mb, T(-2.06, YARD_Y + 0.01, RACK_Z) @ M_Y2X):
        torus(mb, 0.118, 0.024, 6, 4, 'rope', C_ROPE, False)
    _build_pulley_block(mb, (-2.06, YARD_Y - 0.36, RACK_Z), radius=0.16, yaw_deg=0.0, has_hook=True)
    # Taut hemp tackle line running from yardarm pulley down to an iron belaying cleat on the port A-frame leg!
    tube(mb, [(-2.06, YARD_Y - 0.36, RACK_Z), (-1.92, 2.58, 0.30), (-1.68, 1.56, 0.06)],
         0.022, 4, 'rope', C_ROPE, mode='flat')

    # Forged-iron curved lantern bracket bolted to the front-starboard A-frame leg (x = +1.68)
    # Front leg at y = 2.95 m sits at z = -0.26 + (0.58 - (-0.26)) * ((2.95 - 0.22)/(4.26 - 0.22)) = +0.308 m!
    br_z = LEG_F_Z + (RACK_Z - LEG_F_Z) * ((2.96 - FLOOR_Y) / (APEX_Y - FLOOR_Y))
    bracket_pts = [
        (1.68, 2.96, br_z),
        (1.68, 3.04, br_z - 0.38),
        (1.68, 2.94, br_z - 0.72),
    ]
    tube(mb, bracket_pts, [0.042, 0.038, 0.030], 4, 'iron', C_IRON, mode='flat')
    _add_beam(mb, (1.68, 2.52, br_z - 0.09), (1.68, 2.99, br_z - 0.44), 0.036, 0.036, 'iron', C_IRON_RUST, 0.0)
    LANTERN_POS = Vector((1.68, 2.60, br_z - 0.72))
    _build_storm_lantern(mb, LANTERN_POS, scale=1.02, brass_cage=True, hanging=True)

    # Lush Coastal Fern Tufts ('foliage' + UV2) tucked around the stepped mossy cobbled apron corners!
    for fpos, fsc, flean, fph in (
        ((-2.22, STEP_Y + 0.02, -1.42), 0.78, (-0.7, 0.0, -0.7), 0.14),
        (( 2.24, FLOOR_Y + 0.01,  1.42), 0.84, ( 0.7, 0.0,  0.6), 0.49),
        ((-2.14, FLOOR_Y + 0.01,  1.58), 0.76, (-0.6, 0.0,  0.8), 0.78),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=4, rng=rng, phase=fph, lean_dir=flean)

    build(mb)

    add_empty('Lantern_Shipyard', LANTERN_POS)
    col_piece('col_shipyard_base', col_pts)
    export_landmark_glb(outdir, 'pirate_shipwright_timber_rack.glb')


# ================================================================ 2. ANCIENT TIDAL OBELISK MIRROR

def gen_ancient_tidal_obelisk_mirror(outdir):
    """Mystical ancient navigator's bronze-and-stone beacon reflector rooted on a carved mossy
    limestone reef plinth plunging cleanly to y = -3.40 m (radius ~ 2.55 m).
    Features a stepped octagonal relic altar supporting twin sweeping curved temple-stone crescent
    cradle arms (~6.2 m tall) gripping a large faceted concave burnished-brass heliograph mirror
    dish ('brass') centered with a floating glowing turquoise prism focus crystal ('skull_glow'),
    carved stepped runes along the plinth, trailing jungle vines & sea-ferns ('foliage' + UV2),
    collider 'col_mirror_base', and 'Lantern_MirrorShrine' empty right at the glowing mirror prism!
    Target: ~3,100-3,700 visual tris, 1 collider (col_mirror_base).
    """
    clear_scene()
    rng = random.Random(SEED + 2823)
    mb = MB('AncientTidalObeliskMirror', seed=2823)

    SKIRT_BOT = -3.40
    TIER1_Y   =  0.22
    TIER2_Y   =  0.76
    TIER3_Y   =  1.24
    col_pts   = []

    # 1. Carved Mossy Limestone Reef Plinth plunging cleanly to y = -3.40 m (radius ~ 2.55 m!)
    reef_secs = [
        _reg_poly(0.0, SKIRT_BOT, 0.0, 2.74, sides=8, rot_deg=22.5),
        _reg_poly(0.0, -1.65,     0.0, 2.64, sides=8, rot_deg=22.5),
        _reg_poly(0.0, -0.35,     0.0, 2.52, sides=8, rot_deg=22.5),
        _reg_poly(0.0, TIER1_Y,   0.0, 2.38, sides=8, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, reef_secs, 'limestone_moss',
        [C_TIDE_DARK, C_LIME_SHADE, C_LIME_MID, C_LIME_WARM],
        rng, caps=(True, True), top_mat='limestone_moss', top_col=C_LIME_MID,
    )
    for ring in reef_secs:
        col_pts.extend(Vector(p) for p in ring)

    # 4 Sculpted Mossy Limestone Reef Buttress Outcrops hugging the lower octagonal reef skirt
    for rk, (ang_d, rad_xy, rr, ry) in enumerate((
        ( 42.0, 1.98, (0.96, 1.15, 0.88), -0.62),
        (136.0, 2.02, (0.92, 1.22, 0.92), -0.58),
        (228.0, 1.96, (0.94, 1.12, 0.86), -0.64),
        (318.0, 2.04, (0.98, 1.20, 0.90), -0.60),
    )):
        ang = radians(ang_d)
        sculpt_rock_mass(
            mb, (cos(ang) * rad_xy, ry, sin(ang) * rad_xy), rr,
            'limestone_moss', C_LIME_WARM, C_LIME_MID, C_TIDE_DARK, rng,
            subdiv=1, warp=0.22, strata=0.14, flat_top=0.45, base_flare=0.14,
            rot_deg=(0.0, ang_d, 0.0), moss_cap=0.58,
        )

    # 2. Stepped Octagonal Relic Altar + Seaward Carved Stone Steps + Stepped Turquoise Runes!
    tier2_secs = [
        _reg_poly(0.0, TIER1_Y - 0.04, 0.0, 1.98, sides=8, rot_deg=22.5),
        _reg_poly(0.0, TIER2_Y,        0.0, 1.84, sides=8, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, tier2_secs, 'temple_stone',
        [C_TEMPLE_DARK, C_TEMPLE_MID],
        rng, caps=(False, True), top_mat='temple_stone', top_col=C_TEMPLE_HI,
    )
    tier3_secs = [
        _reg_poly(0.0, TIER2_Y - 0.04, 0.0, 1.44, sides=8, rot_deg=22.5),
        _reg_poly(0.0, TIER3_Y,        0.0, 1.32, sides=8, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, tier3_secs, 'temple_stone',
        [C_TEMPLE_MID, C_TEMPLE_HI],
        rng, caps=(False, True), top_mat='temple_stone', top_col=C_TEMPLE_HI,
    )
    # Seaward ceremonial stone steps ascending from reef terrace (-Z) up to the relic altar!
    for si, (sy, sz, sw, sd) in enumerate((
        (TIER1_Y + 0.14, -2.14, 1.34, 0.42),
        (TIER1_Y + 0.40, -1.84, 1.24, 0.38),
        (TIER2_Y + 0.14, -1.52, 1.12, 0.36),
        (TIER2_Y + 0.38, -1.26, 1.02, 0.34),
    )):
        cbox(mb, (0.0, sy, sz), (sw, 0.26, sd), 'temple_stone',
             jit(C_TEMPLE_HI if si % 2 == 0 else C_TEMPLE_MID, rng, 0.05), 0.0, (1, 0, 0))

    # Twin Carved Stone & Verdigris-Bronze Tidal Offering Basins flanking the seaward steps!
    for sgn in (-1.0, 1.0):
        bx, bz = sgn * 1.08, -2.02
        with xf(mb, T(bx, TIER1_Y - 0.04, bz)):
            cyl(mb, 0.28, 0.00, 0.42, 6, 'temple_stone', C_TEMPLE_MID, False, 0.0, 0.22)
            bowl_p = [
                (0.00, 0.40),
                (0.24, 0.44),
                (0.38, 0.62),
                (0.34, 0.66),
                (0.26, 0.54),
                (0.00, 0.52),
            ]
            lathe(mb, bowl_p, 8, 'brass', C_VERDIGRIS_MID, False, False,
                  lambda i, k: C_GOLD_BRIGHT if i in (2, 3) else C_VERDIGRIS_MID)
            cyl(mb, 0.27, 0.51, 0.57, 6, 'skull_glow', C_RUNE_MID, False, 0.0, 0.24)
            with xf(mb, T(0.0, 0.72, 0.0) @ R('Z', sgn * 10.0)):
                lathe(mb, [(0.0, -0.14), (0.075, 0.0), (0.0, 0.16)], 4, 'skull_glow', C_RUNE_CORE, False)

    # Gilded Bronze Azimuth Compass Ring inlaid cleanly on the Altar Deck + 4 Corner Sighting Obelisk Bollards!
    with xf(mb, T(0.0, TIER3_Y + 0.04, 0.0)):
        torus(mb, 1.14, 0.048, 8, 4, 'brass', C_VERDIGRIS_MID, False)
        torus(mb, 0.94, 0.036, 8, 4, 'brass', C_GOLD_BRIGHT, False)
        for ck in range(8):
            ang = radians(ck * 45.0)
            cbox(mb, (cos(ang) * 1.04, 0.02, sin(ang) * 1.04),
                 (0.28 if ck % 2 == 0 else 0.16, 0.045, 0.075 if ck % 2 == 0 else 0.045),
                 'brass', C_GOLD_BRIGHT, 0.0, M=R('Y', -degrees(ang)))

    # 4 Carved Stepped Rune Corner Steles around the Tier-2 octagonal sanctuary rim!
    for sk, ang_d in enumerate((42.0, 138.0, 222.0, 318.0)):
        ang = radians(ang_d)
        sx, sz = cos(ang) * 1.72, sin(ang) * 1.72
        sh = 1.08 + 0.18 * (sk % 2)
        with xf(mb, T(sx, TIER2_Y - 0.04, sz) @ R('Y', -ang_d)):
            cyl(mb, 0.24, 0.0, sh * 0.72, 6, 'temple_stone', C_TEMPLE_MID, False, 0.0, 0.19)
            cyl(mb, 0.19, sh * 0.72, sh, 6, 'temple_stone', C_TEMPLE_HI, False, 0.0, 0.04)
            cyl(mb, 0.21, sh * 0.66, sh * 0.74, 6, 'brass', C_VERDIGRIS_HI, False, 0.0)
            # Glowing turquoise rune inlay on the outward & inward faces of each stele!
            cbox(mb, (0.20, sh * 0.42, 0.0), (0.04, 0.30, 0.065), 'skull_glow', C_RUNE_MID, 0.0)
            cbox(mb, (0.20, sh * 0.42, 0.0), (0.045, 0.08, 0.16), 'skull_glow', C_RUNE_CORE, 0.0)

    # Carved Stepped Turquoise Runes inset around the octagonal altar risers ('skull_glow' ONLY here!)
    for rk in range(8):
        ang = radians(rk * 45.0)
        if abs(sin(ang) + 1.0) < 0.05:  # skip front staircase face (-Z)
            continue
        ca, sa = cos(ang), sin(ang)
        rot_r = R('Y', -degrees(ang) + 90.0)
        with xf(mb, T(ca * 1.38, TIER2_Y + 0.24, sa * 1.38) @ rot_r):
            cbox(mb, (0.0, 0.0, 0.0), (0.34, 0.065, 0.045), 'skull_glow', C_RUNE_MID, 0.0)
            cbox(mb, (0.0, 0.075, 0.005), (0.14, 0.14, 0.045), 'skull_glow', C_RUNE_CORE, 0.0, M=R('Z', 45.0))
        with xf(mb, T(ca * 1.91, TIER1_Y + 0.27, sa * 1.91) @ rot_r):
            cbox(mb, (0.0, 0.0, 0.0), (0.42, 0.060, 0.045), 'skull_glow', C_RUNE_DEEP, 0.0)

    # 3. Central Pedestal & Twin Sweeping Curved Temple-Stone Crescent Cradle Arms (~6.20 m tall!)
    PED_TOP_Y = 2.18
    ped_secs = [
        _reg_poly(0.0, TIER3_Y - 0.04, 0.08, 0.94, sides=8, rot_deg=22.5),
        _reg_poly(0.0, TIER3_Y + 0.44, 0.08, 0.78, sides=8, rot_deg=22.5),
        _reg_poly(0.0, PED_TOP_Y,      0.08, 0.84, sides=8, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, ped_secs, 'temple_stone',
        [C_TEMPLE_DARK, C_TEMPLE_MID, C_TEMPLE_HI],
        rng, caps=(False, True), top_mat='temple_stone', top_col=C_TEMPLE_HI,
    )
    # Bronze ornamental pedestal collar & glowing central tidal glyph
    with xf(mb, T(0.0, TIER3_Y + 0.44, 0.08)):
        cyl(mb, 0.83, -0.08, 0.08, 8, 'brass', C_VERDIGRIS_MID, False, 0.0)
    cbox(mb, (0.0, TIER3_Y + 0.66, -0.74), (0.24, 0.24, 0.055), 'skull_glow', C_RUNE_CORE, 0.0, M=R('Z', 45.0))

    # Twin Sweeping Curved Temple-Stone Crescent Cradle Arms cradling the heliograph mirror (y = 2.02 .. 6.24 m!)
    MIRROR_Y = 4.16
    MIRROR_Z = 0.08
    arm_profile = [
        # (x_dist, y, half_w_x, half_d_z, col)
        (0.56, 1.98, 0.34, 0.38, C_TEMPLE_DARK),
        (1.16, 2.46, 0.32, 0.36, C_TEMPLE_MID),
        (1.64, 3.16, 0.30, 0.34, C_TEMPLE_MID),
        (1.86, 4.08, 0.28, 0.32, C_TEMPLE_HI),
        (1.68, 4.98, 0.24, 0.28, C_TEMPLE_HI),
        (1.24, 5.72, 0.19, 0.22, C_TEMPLE_HI),
        (0.74, 6.20, 0.11, 0.13, C_TEMPLE_GOLD),
    ]
    for sgn in (-1.0, 1.0):
        secs = []
        scols = []
        pts_arm = [Vector((sgn * ax, ay, MIRROR_Z)) for ax, ay, _, _, _ in arm_profile]
        for i, (ax, ay, hw, hd, acol) in enumerate(arm_profile):
            p = pts_arm[i]
            tang = pts_arm[min(i + 1, len(pts_arm) - 1)] - pts_arm[max(i - 1, 0)]
            tang.normalize()
            # Outward radial normal in XY plane perpendicular to tangent
            rad = Vector((tang.y, -tang.x, 0.0))
            if rad.x * sgn < 0.0:
                rad = -rad
            rad.normalize()
            zax = Vector((0.0, 0.0, 1.0))
            # Chamfered hexagonal ashlar cross-section for chunky carved temple stonework
            ring = [
                p - rad * hw        - zax * (hd * 0.58),
                p - rad * (hw * 0.55) - zax * hd,
                p + rad * (hw * 0.55) - zax * hd,
                p + rad * hw        - zax * (hd * 0.58),
                p + rad * hw        + zax * (hd * 0.58),
                p + rad * (hw * 0.55) + zax * hd,
                p - rad * (hw * 0.55) + zax * hd,
                p - rad * hw        + zax * (hd * 0.58),
            ]
            secs.append(ring)
            scols.append(jit(acol, rng, 0.04))
        loft(mb, secs, 'temple_stone', C_TEMPLE_MID, closed=True, caps=(True, True), mode='flat', scols=scols)
        col_pts.extend([Vector((sgn * 1.70, 3.60, MIRROR_Z)), Vector((sgn * 0.85, 6.00, MIRROR_Z))])

        # Gilded & verdigris bronze ornamental binding bands + outward astronomical crest fins on each arm!
        for bi in (1, 2, 3, 4, 5):
            bp = pts_arm[bi]
            tang = (pts_arm[min(bi + 1, len(pts_arm) - 1)] - pts_arm[max(bi - 1, 0)]).normalized()
            rad = Vector((tang.y, -tang.x, 0.0))
            if rad.x * sgn < 0.0:
                rad = -rad
            rad.normalize()
            rot_b = Vector((0.0, 1.0, 0.0)).rotation_difference(tang).to_matrix().to_4x4()
            hw, hd = arm_profile[bi][2], arm_profile[bi][3]
            if bi in (1, 3, 5):
                bcol = C_GOLD_BRIGHT if bi == 3 else C_VERDIGRIS_MID
                with xf(mb, T(bp) @ rot_b):
                    cbox(mb, (0.0, 0.0, 0.0), (hw * 2.18, 0.16, hd * 2.18), 'brass', bcol, 0.0)
            if bi in (2, 4):
                # Sculpted outward-pointing gilded bronze crescent crest-fin
                fin_p = bp + rad * (hw + 0.12)
                rot_f = Vector((0.0, 1.0, 0.0)).rotation_difference(rad).to_matrix().to_4x4()
                with xf(mb, T(fin_p) @ rot_f):
                    cyl(mb, 0.095, -0.14, 0.22, 4, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.015)

        # Glowing turquoise mystical rune line tracing the inner crescent face of each stone arm!
        for ri in range(1, 5):
            rp0 = pts_arm[ri]
            rp1 = pts_arm[ri + 1]
            mid_r = rp0.lerp(rp1, 0.5)
            tang = (rp1 - rp0).normalized()
            rad = Vector((tang.y, -tang.x, 0.0))
            if rad.x * sgn < 0.0:
                rad = -rad
            rad.normalize()
            hw_avg = 0.5 * (arm_profile[ri][2] + arm_profile[ri + 1][2])
            p_in = mid_r - rad * (hw_avg + 0.015)
            rot_r = Vector((0.0, 1.0, 0.0)).rotation_difference(tang).to_matrix().to_4x4()
            with xf(mb, T(p_in) @ rot_r):
                cbox(mb, (0.0, 0.0, 0.0), (0.055, (rp1 - rp0).length * 0.72, 0.085), 'skull_glow', C_RUNE_MID, 0.0)
            p_sea = mid_r + Vector((0.0, 0.0, -(arm_profile[ri][3] + 0.015)))
            with xf(mb, T(p_sea) @ rot_r):
                cbox(mb, (0.0, 0.0, 0.0), (0.085, (rp1 - rp0).length * 0.62, 0.055), 'skull_glow', C_RUNE_CORE, 0.0)

        # Gilded bronze crescent spear-tip finial crowning each arm (peaking at y = 6.38 m!)
        tip_p = pts_arm[-1]
        tip_dir = (pts_arm[-1] - pts_arm[-2]).normalized()
        rot_t = Vector((0.0, 1.0, 0.0)).rotation_difference(tip_dir).to_matrix().to_4x4()
        with xf(mb, T(tip_p) @ rot_t):
            cyl(mb, 0.14, -0.04, 0.34, 6, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.015)

    # 4. Large Faceted Concave Burnished-Brass Heliograph Mirror Dish + Trunnion Mounts!
    #    Centered at (0, 4.16, 0.08), tilted slightly seaward (-7 deg X) toward approaching ships (-Z)!
    MIRROR_C = Vector((0.0, MIRROR_Y, MIRROR_Z))
    # Heavy horizontal forged-bronze trunnion pivot axles locking the mirror solidly into the crescent arms!
    with xf(mb, T(MIRROR_C) @ M_Y2X):
        cyl(mb, 0.085, -1.78, -1.12, 8, 'brass', C_BRASS_DARK, False, 0.0)
        cyl(mb, 0.085,  1.12,  1.78, 8, 'brass', C_BRASS_DARK, False, 0.0)
        for sx in (-1.60, -1.28, 1.28, 1.60):
            cyl(mb, 0.175 if abs(sx) > 1.4 else 0.135, sx - 0.07, sx + 0.07, 8, 'brass', C_GOLD_BRIGHT, False, 0.0)
    # Lower stabilizing bronze elevation arc connecting mirror back housing cleanly down to the central pedestal!
    _add_beam(mb, (0.0, PED_TOP_Y - 0.06, MIRROR_Z + 0.24), (0.0, MIRROR_Y - 0.85, MIRROR_Z + 0.42),
              0.14, 0.14, 'brass', C_VERDIGRIS_DK, 0.0)
    _add_beam(mb, (-0.38, PED_TOP_Y - 0.06, MIRROR_Z + 0.06), (-0.72, MIRROR_Y - 0.84, MIRROR_Z + 0.24),
              0.10, 0.10, 'brass', C_VERDIGRIS_MID, 0.0)
    _add_beam(mb, ( 0.38, PED_TOP_Y - 0.06, MIRROR_Z + 0.06), ( 0.72, MIRROR_Y - 0.84, MIRROR_Z + 0.24),
              0.10, 0.10, 'brass', C_VERDIGRIS_MID, 0.0)

    M_DISH = T(MIRROR_C) @ R('X', -7.0)
    with xf(mb, M_DISH):
        # Dish axis faces -Z: rotate local +Y axis onto -Z using R('X', -90)
        with xf(mb, R('X', -90.0)):
            # Concave 16-facet burnished-brass parabolic reflector bowl (radius = 1.18 m, depth = 0.48 m!)
            dish_prof = [
                (0.00, -0.35),  # rear bronze boss apex (+Z in dish local)
                (0.46, -0.30),  # rear verdigris-patinated domed shell
                (0.92, -0.14),
                (1.18,  0.14),  # thick outer gilded rim lip
                (1.22,  0.22),
                (1.12,  0.24),  # inner beveled bezel
                (0.84,  0.04),  # gleaming concave parabolic mirror facets!
                (0.44, -0.09),
                (0.00, -0.14),  # mirror center focal vertex
            ]
            def _dish_col(i, k):
                if i <= 2:
                    return C_VERDIGRIS_MID if (k % 2 == 0) else C_VERDIGRIS_DK
                if i in (3, 4):
                    return C_GOLD_BRIGHT
                if i == 5:
                    return C_BRASS_WARM
                return C_BRASS_MIRROR if ((i + k) % 2 == 0) else C_GOLD_BRIGHT
            lathe(mb, dish_prof, 12, 'brass', C_GOLD_BRIGHT, False, False, _dish_col)
            # Outer riveted bronze bezel ring + concentric inner decorative gold ring
            with xf(mb, T(0.0, 0.20, 0.0)):
                torus(mb, 1.19, 0.064, 12, 4, 'brass', C_GOLD_BRIGHT, False)
            with xf(mb, T(0.0, -0.08, 0.0)):
                torus(mb, 0.48, 0.024, 8, 4, 'brass', C_BRASS_WARM, False)
            # 8 Navigational Sunburst Brass Rays + 8 Curved Rear Gilded Reinforcing Ribs!
            for rk in range(8):
                ang = radians(rk * 45.0 + 22.5)
                ca, sa = cos(ang), sin(ang)
                ray_len = 0.30 if (rk % 2 == 0) else 0.19
                with xf(mb, T(ca * (1.22 + ray_len * 0.42), 0.18, sa * (1.22 + ray_len * 0.42))
                            @ R('Y', -degrees(ang)) @ R('Z', -90.0)):
                    cyl(mb, 0.075, -ray_len * 0.48, ray_len * 0.52, 4, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.012)
                # Bezel decorative rivet boss
                cbox(mb, (ca * 1.19, 0.26, sa * 1.19), (0.075, 0.045, 0.075),
                     'brass', C_VERDIGRIS_HI if rk % 2 == 0 else C_GOLD_BRIGHT, 0.0, M=R('Y', -degrees(ang)))
                # Rear radial bronze strengthening rib hugging the verdigris back shell
                rib_p = [
                    (ca * 0.22, -0.35, sa * 0.22),
                    (ca * 0.68, -0.25, sa * 0.68),
                    (ca * 1.14,  0.08, sa * 1.14),
                ]
                tube(mb, rib_p, [0.036, 0.032, 0.028], 4, 'brass', C_BRASS_WARM, mode='flat')
            # Rear ornate bronze boss cap + front central etched medallion with turquoise focal rune
            cyl(mb, 0.28, -0.44, -0.32, 8, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.22)
            cyl(mb, 0.22, -0.16, -0.09, 8, 'brass', C_BRASS_WARM, False, 0.0, 0.18)
            cyl(mb, 0.12, -0.10, -0.06, 6, 'skull_glow', C_RUNE_CORE, False, 0.0, 0.08)

        # 3 Sleek Curved Bronze Spider-Struts curving seaward from bezel directly into astrolabe gimbal sockets!
        PRISM_LOCAL = Vector((0.0, 0.0, -0.88))
        for sk in range(3):
            ang = radians(90.0 + sk * 120.0)
            ca, sa = cos(ang), sin(ang)
            s_path = [
                Vector((ca * 1.17, sa * 1.17, -0.20)),
                Vector((ca * 0.86, sa * 0.86, -0.60)),
                Vector((ca * 0.39, sa * 0.39, -0.88)),
            ]
            tube(mb, s_path, [0.042, 0.036, 0.030], 4, 'brass', C_BRASS_WARM, mode='flat')
            cbox(mb, (ca * 0.39, sa * 0.39, -0.88), (0.08, 0.08, 0.08), 'brass', C_GOLD_BRIGHT, 0.0)

        # 5. Floating Glowing Turquoise Prism Focus Crystal ('skull_glow'!) + Twin Bronze Astrolabe Rings!
        with xf(mb, T(PRISM_LOCAL)):
            # Intersecting gilded bronze astrolabe gimbal rings encircling the levitating focus prism
            with xf(mb, R('X', 90.0)):
                torus(mb, 0.38, 0.028, 12, 4, 'brass', C_GOLD_BRIGHT, False)
            with xf(mb, R('Y', 42.0) @ R('X', 28.0)):
                torus(mb, 0.31, 0.022, 10, 4, 'brass', C_VERDIGRIS_HI, False)
            # Dramatic Faceted Double-Ended Hexagonal Turquoise Prism Crystal ('skull_glow'!)
            prism_prof = [
                (0.00, -0.44),
                (0.18, -0.16),
                (0.22,  0.00),
                (0.18,  0.16),
                (0.00,  0.44),
            ]
            lathe(mb, prism_prof, 6, 'skull_glow', C_RUNE_CORE, False, False,
                  lambda i, k: C_RUNE_CORE if i in (1, 2) else C_RUNE_MID)
            # 2 Small Orbiting Crystal Shards flanking the main prism inside the astrolabe rings
            for ox, oy, oz in ((-0.26, 0.14, -0.06), (0.25, -0.15, 0.05)):
                with xf(mb, T(ox, oy, oz) @ R('Z', 22.0 if ox < 0 else -24.0)):
                    lathe(mb, [(0.0, -0.13), (0.055, 0.0), (0.0, 0.13)], 4, 'skull_glow', C_RUNE_CORE, False)

    LANTERN_POS = M_DISH @ Vector((0.0, 0.0, -0.88))

    # 6. Trailing Jungle Vines & Sea-Ferns ('foliage' + UV2) draping from the crescent shoulders & reef crevices!
    for v_anc, v_len, v_w, v_dir, v_ph in (
        ((-1.62, 3.12, -0.12), 1.65, 0.17, (-0.8, 0.0, -0.5), 0.12),
        (( 1.64, 3.04,  0.16), 1.72, 0.17, ( 0.8, 0.0,  0.5), 0.41),
        ((-1.26, 1.24,  0.88), 1.24, 0.16, (-0.7, 0.0,  0.7), 0.67),
        (( 1.32, 1.24, -0.78), 1.18, 0.15, ( 0.7, 0.0, -0.7), 0.83),
        (( 0.06, 1.22,  1.34), 1.30, 0.16, ( 0.1, 0.0,  1.0), 0.29),
    ):
        _add_leafy_vine_drape(mb, v_anc, v_len, v_w, v_dir, rng, phase=v_ph)

    for fpos, fsc, flean, fph in (
        ((-1.88, TIER1_Y + 0.02, -1.24), 0.84, (-0.7, 0.0, -0.6), 0.18),
        (( 1.92, TIER1_Y + 0.02, -1.16), 0.82, ( 0.7, 0.0, -0.6), 0.52),
        ((-1.78, TIER1_Y + 0.02,  1.44), 0.86, (-0.6, 0.0,  0.7), 0.77),
        (( 1.74, TIER1_Y + 0.02,  1.48), 0.80, ( 0.6, 0.0,  0.7), 0.91),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=4, rng=rng, phase=fph, lean_dir=flean)

    build(mb)

    add_empty('Lantern_MirrorShrine', LANTERN_POS)
    col_piece('col_mirror_base', col_pts)
    export_landmark_glb(outdir, 'ancient_tidal_obelisk_mirror.glb')


# ================================================================ 3. SMUGGLER ROPE CARGO HOIST

def gen_smuggler_rope_cargo_hoist(outdir):
    """Cliffside smugglers' concealed contraband barrel-chute & winch ledge anchored on a deeply
    skirted mossy sandstone ledge plunging cleanly to y = -3.20 m (footprint hx ~ 2.45 m, hz ~ 2.20 m).
    Features an angled heavy timber skid-chute with iron-banded side guide rails, geared iron capstan
    drum with taut hemp cargo sling hauling up a banded rum cask & treasure chest, tilted patched
    canvas camouflage shelter tarp ('paint' + UV2 wind sway), weathered warning signpost with hanging
    brass signal lantern, trailing cliff-ivy ('foliage' + UV2), collider 'col_hoist_base', and
    'Lantern_SmugglerHoist' empty!
    Target: ~3,100-3,700 visual tris, 1 collider (col_hoist_base).
    """
    clear_scene()
    rng = random.Random(SEED + 2837)
    mb = MB('SmugglerRopeCargoHoist', seed=2837)

    SKIRT_BOT = -3.20
    FLOOR_Y   =  1.16
    col_pts   = []

    # 1. Deeply Skirted Raised Mossy Sandstone Cliff Ledge (y = -3.20 .. +1.16 m, footprint hx ~ 2.45, hz ~ 2.20!)
    #    The cliff top rim ends cleanly at z = -0.82 m (extending rearward to z = +2.32 m) so the angled
    #    barrel skid-chute plunges cleanly IN FRONT OF the sandstone cliff face with ZERO rock clipping!
    ledge_secs = [
        _rect_oct(0.0, SKIRT_BOT, 0.72, 2.58, 1.82, 0.52),
        _rect_oct(0.0, -1.30,     0.74, 2.50, 1.74, 0.48),
        _rect_oct(0.0,  0.10,     0.76, 2.44, 1.66, 0.44),
        _rect_oct(0.0, FLOOR_Y,   0.78, 2.38, 1.58, 0.40),
    ]
    _loft_horizontal_masonry(
        mb, ledge_secs, 'limestone_moss',
        [C_TIDE_DARK, C_SAND_OCHRE, C_SAND_WARM, C_LIME_WARM],
        rng, caps=(True, True), top_mat='limestone_moss', top_col=C_SAND_WARM,
    )
    for ring in ledge_secs:
        col_pts.extend(Vector(p) for p in ring)

    # Rugged sculpted mossy sandstone cliff-edge crag boulders flanking the chute lip & rear rim
    for rpos, rrad, rrot, rmoss in (
        ((-1.98,  0.34, -0.68), (0.86, 1.12, 0.76), (0.0,  22.0, 0.0), 0.54),
        (( 1.94,  0.32, -0.62), (0.90, 1.14, 0.80), (0.0, -28.0, 0.0), 0.58),
        ((-1.88,  0.52,  2.02), (0.94, 1.04, 0.82), (0.0,  46.0, 0.0), 0.62),
        (( 1.88,  0.48,  1.96), (0.90, 1.00, 0.84), (0.0, -38.0, 0.0), 0.56),
    ):
        sculpt_rock_mass(
            mb, rpos, rrad, 'limestone_moss',
            C_SAND_PALE, C_SAND_WARM, C_TIDE_DARK, rng,
            subdiv=1, warp=0.24, strata=0.16, flat_top=0.42, base_flare=0.14,
            rot_deg=rrot, moss_cap=rmoss,
        )

    # Timber-planked cliff-edge working deck bolted over the sandstone ledge (z = -0.66 .. +2.06, y = DECK_Y!)
    for sx in (-1.52, -0.36, 0.80, 1.62):
        cbox(mb, (sx, FLOOR_Y + 0.02, 0.72), (0.14, 0.10, 2.74), 'timber', C_TIMBER_DARK, 0.0, (0, 0, 1))
    for pk in range(7):
        pz = -0.52 + pk * 0.42
        pcol = jit(C_DRIFTWOOD if pk % 2 == 0 else C_TIMBER_MID, rng, 0.06)
        cbox(mb, (0.06, FLOOR_Y + 0.09, pz), (3.44, 0.064, 0.34), 'timber', pcol, 0.0, (1, 0, 0))
    DECK_Y = FLOOR_Y + 0.12

    # 2. Angled Heavy Timber Skid-Chute with Iron-Banded Side Guide Rails plunging 100% CLEAR in front of the cliff!
    CHUTE_X = -0.56
    # Horizontal timber intake guide-rails on the deck feeding into the inclined cliff chute lip!
    for sx in (-0.54, 0.54):
        cbox(mb, (CHUTE_X + sx, DECK_Y + 0.10, 0.02), (0.12, 0.20, 1.38), 'timber', C_TIMBER_HI, 0.0, (0, 0, 1))
    P_TOP   = Vector((CHUTE_X, DECK_Y + 0.14, -0.66))
    P_BOT   = Vector((CHUTE_X, 0.14,          -2.54))
    ch_len  = (P_BOT - P_TOP).length
    ch_mid  = (P_TOP + P_BOT) * 0.5
    ch_pitch = degrees(atan2(P_BOT.y - P_TOP.y, -(P_BOT.z - P_TOP.z)))  # ~-34 deg sloping cleanly down seaward!
    M_CHUTE = T(ch_mid) @ R('X', ch_pitch)

    with xf(mb, M_CHUTE):
        # Twin heavy timber main skid runners + 7 slatted oak slide-planks worn pale along the barrel track!
        for sx in (-0.54, 0.54):
            cbox(mb, (sx, -0.06, 0.0), (0.14, 0.18, ch_len + 0.10), 'timber', C_TIMBER_DARK, 0.0, (0, 0, 1))
            cbox(mb, (sx + (0.02 if sx > 0 else -0.02), 0.18, 0.0), (0.10, 0.28, ch_len + 0.04),
                 'timber', C_TIMBER_HI, 0.0, (0, 0, 1))
        for si in range(7):
            sz = -ch_len * 0.44 + si * (ch_len * 0.88 / 6.0)
            cbox(mb, (0.0, 0.04, sz), (1.02, 0.065, 0.26), 'timber',
                 jit(C_OAK_FRESH if si % 2 == 0 else C_TIMBER_MID, rng, 0.06), 0.0, (1, 0, 0))
        # 4 Heavy Forged-Iron U-Bands wrapping cleanly under the chute & up both side guide rails!
        for bi in range(4):
            bz = -ch_len * 0.40 + bi * (ch_len * 0.80 / 3.0)
            cbox(mb, (0.0, -0.155, bz), (1.28, 0.036, 0.088), 'iron', C_IRON, 0.0)
            for sx in (-0.63, 0.63):
                cbox(mb, (sx, 0.08, bz), (0.038, 0.52, 0.088), 'iron',
                     C_IRON_RUST if bi % 2 == 1 else C_IRON, 0.0)
        cbox(mb, (0.0, 0.06, -ch_len * 0.50), (1.22, 0.10, 0.08), 'iron', C_IRON_RUST, 0.0)

    # Twin stout diagonal timber knee-props bracing the cantilevered chute solidly back into the sandstone cliff!
    for sx in (-0.54, 0.54):
        p_brace_ch = M_CHUTE @ Vector((sx, -0.14, -ch_len * 0.28))
        p_brace_rk = Vector((CHUTE_X + sx * 0.96, -0.52, -0.96))
        _add_beam(mb, p_brace_rk, p_brace_ch, 0.15, 0.15, 'timber', C_TIMBER_DARK, 0.0)
        cbox(mb, p_brace_ch, (0.20, 0.16, 0.18), 'iron', C_IRON, 0.0)

    # 3. Geared Iron Capstan Winch Drum + Overhead Timber Hoist Gallows + Taut Rope Sling & Banded Rum Cask!
    WINCH_X, WINCH_Z, WINCH_Y = CHUTE_X, 1.48, DECK_Y + 0.68
    for sx in (-0.58, 0.58):
        cbox(mb, (WINCH_X + sx, DECK_Y + 0.06, WINCH_Z), (0.18, 0.14, 0.94), 'timber', C_TIMBER_DARK, 0.0, (0, 0, 1))
        _add_beam(mb, (WINCH_X + sx, DECK_Y + 0.08, WINCH_Z - 0.36), (WINCH_X + sx, WINCH_Y + 0.06, WINCH_Z),
                  0.13, 0.13, 'timber', C_TIMBER_MID, 0.0)
        _add_beam(mb, (WINCH_X + sx, DECK_Y + 0.08, WINCH_Z + 0.36), (WINCH_X + sx, WINCH_Y + 0.06, WINCH_Z),
                  0.13, 0.13, 'timber', C_TIMBER_MID, 0.0)
        cbox(mb, (WINCH_X + sx, WINCH_Y, WINCH_Z), (0.20, 0.22, 0.22), 'iron', C_IRON, 0.0)
    with xf(mb, T(WINCH_X, WINCH_Y, WINCH_Z) @ M_Y2X):
        cyl(mb, 0.072, -0.78, 0.78, 6, 'iron', C_IRON, False, 0.0)
        cyl(mb, 0.24,  -0.46, 0.46, 8, 'timber', C_TIMBER_DARK, False, 0.0)
        for wi in range(5):
            wy = -0.34 + wi * 0.17
            with xf(mb, T(0.0, wy, 0.0)):
                torus(mb, 0.255, 0.044, 7, 4, 'rope', mul(C_ROPE, 0.90 + 0.10 * (wi % 2)), True)
        cyl(mb, 0.38, -0.52, -0.45, 8, 'iron', C_IRON, False, 0.0)
        cyl(mb, 0.15, -0.56, -0.42, 6, 'brass', C_GOLD_BRIGHT, False, 0.0)
        for tk in range(8):
            ang = radians(tk * 45.0)
            cbox(mb, (cos(ang) * 0.41, -0.485, sin(ang) * 0.41),
                 (0.11, 0.065, 0.09), 'iron', C_IRON_RUST if tk % 2 == 0 else C_IRON, 0.0, M=R('Y', -degrees(ang)))
        cbox(mb, (0.18, 0.74, 0.0), (0.38, 0.052, 0.068), 'iron', C_IRON, 0.0)
        with xf(mb, T(0.35, 0.86, 0.0)):
            cyl(mb, 0.036, -0.10, 0.14, 5, 'timber', C_OAK_FRESH, False, 0.0)

    # Overhead Cantilevered Hoist Gallows A-Frame (straddling chute lip, jib projecting cleanly over cliff!)
    GALLOW_Y  = DECK_Y + 3.10
    P_GL_TOP  = Vector((CHUTE_X - 0.82, GALLOW_Y, -0.34))
    P_GR_TOP  = Vector((CHUTE_X + 0.82, GALLOW_Y, -0.34))
    P_JIB_TIP = Vector((CHUTE_X, GALLOW_Y + 0.08, -1.86))
    for px, ptop in ((CHUTE_X - 0.82, P_GL_TOP), (CHUTE_X + 0.82, P_GR_TOP)):
        _add_beam(mb, (px, DECK_Y - 0.06, -0.34), ptop + Vector((0.0, 0.12, 0.0)), 0.16, 0.16, 'timber', C_TIMBER_MID, 0.0)
        _add_beam(mb, (px, DECK_Y - 0.06,  0.88), ptop - Vector((0.0, 0.18, 0.0)), 0.13, 0.13, 'timber', C_TIMBER_DARK, 0.0)
        cbox(mb, (px, DECK_Y + 0.08, -0.34), (0.26, 0.16, 0.26), 'iron', C_IRON_RUST, 0.0)
        col_pts.append(ptop)
    _add_beam(mb, P_GL_TOP + Vector((-0.24, 0.0, 0.0)), P_GR_TOP + Vector((0.24, 0.0, 0.0)), 0.16, 0.16, 'timber', C_TIMBER_HI, 0.0)
    _add_beam(mb, (CHUTE_X, GALLOW_Y - 0.04, 0.86), P_JIB_TIP + Vector((0.0, 0.0, -0.16)), 0.16, 0.17, 'timber', C_DRIFTWOOD, 0.0)
    _add_beam(mb, (CHUTE_X - 0.82, DECK_Y + 2.16, -0.34), (CHUTE_X, GALLOW_Y - 0.08, -1.24), 0.11, 0.11, 'timber', C_TIMBER_DARK, 0.0)
    _add_beam(mb, (CHUTE_X + 0.82, DECK_Y + 2.16, -0.34), (CHUTE_X, GALLOW_Y - 0.08, -1.24), 0.11, 0.11, 'timber', C_TIMBER_DARK, 0.0)
    cbox(mb, P_JIB_TIP, (0.24, 0.22, 0.22), 'iron', C_IRON, 0.0)
    PULLEY_POS = P_JIB_TIP + Vector((0.0, -0.36, 0.0))
    _build_pulley_block(mb, PULLEY_POS, radius=0.20, yaw_deg=0.0, has_hook=False)

    # Banded Crimson Contraband Rum Cask riding 100% UNCLIPPED midway up the open timber skid-chute!
    CASK_POS = M_CHUTE @ Vector((0.0, 0.42, -0.04))
    M_CASK   = T(CASK_POS) @ R('X', ch_pitch) @ R('Z', 90.0)
    _build_coopered_cask(
        mb, M_CASK, radius=0.35, height=0.86, rng=rng,
        col_a=C_TIMBER_MID, col_b=C_TIMBER_HI, col_head=C_TIMBER_DARK,
        segs=7, stripe_col=C_CRIMSON_HI,
    )
    SLING_HOOK_P = CASK_POS + Vector((0.0, 0.56, 0.12))
    with xf(mb, T(SLING_HOOK_P) @ M_Y2Z):
        torus(mb, 0.088, 0.024, 6, 4, 'iron', C_IRON, False)
    for sx in (-0.24, 0.24):
        p_c_l = M_CHUTE @ Vector((sx, 0.44, -0.36))
        p_c_u = M_CHUTE @ Vector((sx, 0.44,  0.28))
        with xf(mb, T(M_CHUTE @ Vector((sx, 0.42, -0.04))) @ R('X', ch_pitch) @ M_Y2X):
            torus(mb, 0.36, 0.026, 7, 4, 'rope', C_ROPE, False)
        tube(mb, [p_c_l, SLING_HOOK_P], 0.022, 4, 'rope', C_ROPE, mode='flat')
        tube(mb, [p_c_u, SLING_HOOK_P], 0.022, 4, 'rope', C_ROPE, mode='flat')

    # Taut main hoist rope: capstan drum -> overhead pulley block -> cargo sling ring!
    p_drum_top = Vector((WINCH_X, WINCH_Y + 0.26, WINCH_Z - 0.12))
    p_pul_back = PULLEY_POS + Vector((0.0, 0.14, 0.12))
    p_pul_bot  = PULLEY_POS + Vector((0.0, -0.16, -0.02))
    tube(mb, [p_drum_top, p_drum_top.lerp(p_pul_back, 0.5) - Vector((0.0, 0.05, 0.0)), p_pul_back],
         0.028, 5, 'rope', C_ROPE, mode='flat')
    tube(mb, [p_pul_bot, p_pul_bot.lerp(SLING_HOOK_P, 0.5), SLING_HOOK_P],
         0.028, 5, 'rope', C_ROPE, mode='flat')

    # Contraband Banded Treasure Chest + Spare Rum Cask + Coiled Hemp Rope staged clearly under the shelter!
    _build_treasure_chest(
        mb, T(1.06, DECK_Y, 0.36) @ R('Y', -28.0),
        size=(0.94, 0.44, 0.56), open_deg=0.0,
    )
    with xf(mb, T(1.06, DECK_Y, 0.36) @ R('Y', -28.0)):
        for sx in (-0.28, 0.28):
            _add_beam(mb, (sx, 0.02, -0.30), (sx, 0.56, -0.26), 0.030, 0.030, 'rope', C_ROPE, 0.0)
            _add_beam(mb, (sx, 0.56, -0.26), (sx, 0.64,  0.00), 0.030, 0.030, 'rope', C_ROPE, 0.0)
            _add_beam(mb, (sx, 0.64,  0.00), (sx, 0.56,  0.26), 0.030, 0.030, 'rope', C_ROPE, 0.0)
    _build_coopered_cask(
        mb, T(1.48, DECK_Y + 0.39, 1.24),
        radius=0.30, height=0.78, rng=rng,
        col_a=C_TIMBER_MID, col_b=C_TIMBER_DARK, col_head=C_TIMBER_DARK,
        segs=6, stripe_col=C_TEAL_MUTED,
    )
    _build_rope_coil_lean(mb, (0.58, DECK_Y, 1.66), radius=0.28, turns=3, r=0.038, segs=6, psegs=4)

    # 4. Tilted Patched Canvas Camouflage Shelter Tarp ('paint' + UV2 Wind Sway!)
    P_T_FL = Vector((0.26, DECK_Y + 2.74, -0.34))
    P_T_BL = Vector((0.22, DECK_Y + 2.52,  1.86))
    P_T_FR = Vector((2.10, DECK_Y + 1.84, -0.26))
    P_T_BR = Vector((2.06, DECK_Y + 1.64,  1.84))
    for pp, pcol in ((P_T_BL, C_DRIFTWOOD), (P_T_FR, C_TIMBER_MID), (P_T_BR, C_TIMBER_DARK)):
        _add_beam(mb, (pp.x, DECK_Y - 0.14, pp.z), pp + Vector((0.0, 0.16, 0.0)), 0.11, 0.11, 'timber', pcol, 0.0)
        with xf(mb, T(pp - Vector((0.0, 0.04, 0.0))) @ R('X', 30.0)):
            torus(mb, 0.095, 0.022, 6, 4, 'rope', C_ROPE, False)
    _add_beam(mb, P_T_FL, P_T_BL, 0.088, 0.088, 'timber', C_DRIFT_PALE, 0.0)
    _add_beam(mb, P_T_FR, P_T_BR, 0.088, 0.088, 'timber', C_DRIFTWOOD, 0.0)
    _add_beam(mb, P_T_FL, P_T_FR, 0.082, 0.082, 'timber', C_DRIFTWOOD, 0.0)
    _add_beam(mb, P_T_BL, P_T_BR, 0.082, 0.082, 'timber', C_DRIFTWOOD, 0.0)

    tnu, tnv = 6, 5
    t_thick  = 0.022

    def _tarp_pt(u, v):
        ue = -0.08 + u * 1.16
        ve = -0.10 + v * 1.20
        top_edge = P_T_FL.lerp(P_T_FR, ue)
        bot_edge = P_T_BL.lerp(P_T_BR, ue)
        p = top_edge.lerp(bot_edge, ve)
        sag = sin(max(0.0, min(1.0, u)) * pi) * sin(max(0.0, min(1.0, v)) * pi) * 0.16
        ripple = sin(u * pi * 2.5 + v * pi * 2.0) * 0.045
        eave_drop = 0.0
        if u < 0.08:
            eave_drop += ((0.08 - u) / 0.08) ** 1.3 * 0.14
        elif u > 0.90:
            eave_drop += ((u - 0.90) / 0.10) ** 1.3 * 0.22
        if v < 0.08:
            eave_drop += ((0.08 - v) / 0.08) ** 1.3 * 0.18
        elif v > 0.90:
            eave_drop += ((v - 0.90) / 0.10) ** 1.3 * 0.18
        return Vector((p.x, p.y + 0.07 - sag + ripple - eave_drop, p.z))

    def _tarp_w(u, v):
        c_dist = min(
            sqrt((u - 0.08) ** 2 + (v - 0.08) ** 2),
            sqrt((u - 0.92) ** 2 + (v - 0.08) ** 2),
            sqrt((u - 0.08) ** 2 + (v - 0.92) ** 2),
            sqrt((u - 0.92) ** 2 + (v - 0.92) ** 2),
        )
        pin_m = smooth01(c_dist / 0.30)
        edge_w = max(0.0, max(abs(u - 0.5) * 2.0, abs(v - 0.5) * 2.0) - 0.68) / 0.32 * 0.88
        belly_w = sin(u * pi) * sin(v * pi) * 0.42
        return min(0.94, max(0.0, (edge_w + belly_w) * pin_m))

    tg_top = [[None] * (tnv + 1) for _ in range(tnu + 1)]
    tg_bot = [[None] * (tnv + 1) for _ in range(tnu + 1)]
    tg_w   = [[0.0]  * (tnv + 1) for _ in range(tnu + 1)]
    for iu in range(tnu + 1):
        u = iu / float(tnu)
        for iv in range(tnv + 1):
            v = iv / float(tnv)
            p = _tarp_pt(u, v)
            pu = _tarp_pt(min(1.0, u + 0.02), v) - _tarp_pt(max(0.0, u - 0.02), v)
            pv = _tarp_pt(u, min(1.0, v + 0.02)) - _tarp_pt(u, max(0.0, v - 0.02))
            n = pv.cross(pu)
            if n.y < 0.0:
                n = -n
            n = n.normalized() if n.length > 1e-6 else Vector((0.0, 1.0, 0.0))
            tg_top[iu][iv] = p + n * (t_thick * 0.5)
            tg_bot[iu][iv] = p - n * (t_thick * 0.5)
            tg_w[iu][iv]   = _tarp_w(u, v)

    camo_grid = [
        C_CAMO_OLIVE, C_CAMO_DRAB, C_CAMO_SLATE, C_CANVAS_WARM, C_CAMO_OLIVE, C_CAMO_DRAB,
    ]
    mb.newoff()
    t_phase = 0.62
    for iu in range(tnu):
        for iv in range(tnv):
            if (iu == 2 and iv == 1) or (iu == 4 and iv == 3):
                c_top = C_CANVAS_WARM
            elif iu == 1 and iv == 3:
                c_top = C_TEAL_MUTED
            else:
                c_top = camo_grid[(iu * 2 + iv * 3) % len(camo_grid)]
            c_top = jit(c_top, rng, 0.045, 0.015)
            c_bot = mul(c_top, 0.80)
            t00, t10, t11, t01 = tg_top[iu][iv], tg_top[iu + 1][iv], tg_top[iu + 1][iv + 1], tg_top[iu][iv + 1]
            b00, b10, b11, b01 = tg_bot[iu][iv], tg_bot[iu + 1][iv], tg_bot[iu + 1][iv + 1], tg_bot[iu][iv + 1]
            u00, u10, u11, u01 = (tg_w[iu][iv], t_phase), (tg_w[iu + 1][iv], t_phase), (tg_w[iu + 1][iv + 1], t_phase), (tg_w[iu][iv + 1], t_phase)
            ctr = (t00 + t11 + b00 + b11) * 0.25
            mb.fp([t00, t10, t11, t01], 'paint', c_top, (1, 0, 0), ctr - Vector((0.0, 1.5, 0.0)),
                  smooth=False, uv2=[u00, u10, u11, u01])
            mb.fp([b00, b01, b11, b10], 'paint', c_bot, (1, 0, 0), ctr + Vector((0.0, 1.5, 0.0)),
                  smooth=False, uv2=[u00, u01, u11, u10])
            if iv == 0:
                mb.fp([b00, b10, t10, t00], 'paint', mul(c_top, 0.76), (1, 0, 0), ctr + Vector((0.0, 0.0, 1.0)),
                      uv2=[u00, u10, u10, u00])
            if iv == tnv - 1:
                mb.fp([b11, b01, t01, t11], 'paint', mul(c_top, 0.76), (1, 0, 0), ctr - Vector((0.0, 0.0, 1.0)),
                      uv2=[u11, u01, u01, u11])
            if iu == tnu - 1:
                mb.fp([b10, b11, t11, t10], 'paint', mul(c_top, 0.76), (0, 0, 1), ctr - Vector((1.0, 0.0, 0.0)),
                      uv2=[u10, u11, u11, u10])

    # Taut hemp guy-lines securing the starboard camouflage tarp eaves cleanly to stakes inside the cliff rim!
    for cp, stk in ((tg_top[tnu][0], (2.22, -0.54)), (tg_top[tnu][tnv], (2.18, 2.02))):
        s_bot = Vector((stk[0], FLOOR_Y - 0.14, stk[1]))
        s_top = Vector((stk[0] + 0.06, FLOOR_Y + 0.34, stk[1]))
        _add_beam(mb, s_bot, s_top, 0.065, 0.065, 'timber', C_TIMBER_DARK, 0.0)
        tie = s_bot.lerp(s_top, 0.74)
        tube(mb, [cp, cp.lerp(tie, 0.5) - Vector((0.0, 0.04, 0.0)), tie], 0.020, 4, 'rope', C_ROPE, mode='flat')

    # 5. Weathered Warning Signpost with Hanging Brass Signal Lantern (starboard seaward cliff rim!)
    SIGN_BASE = Vector((1.48, FLOOR_Y - 0.10, -0.62))
    SIGN_TOP  = Vector((1.56, FLOOR_Y + 2.48, -0.78))
    tube(mb, [SIGN_BASE, SIGN_BASE.lerp(SIGN_TOP, 0.5), SIGN_TOP], [0.115, 0.098, 0.084], 6, 'timber', C_DRIFT_SHADE, mode='flat')
    cbox(mb, (1.48, FLOOR_Y + 0.08, -0.62), (0.28, 0.18, 0.28), 'temple_stone', C_COBBLE_MID, 0.0)
    with xf(mb, T(1.52, FLOOR_Y + 1.42, -0.72) @ R('Y', -18.0) @ R('Z', -7.0)):
        cbox(mb, (0.0, 0.0, -0.09), (0.86, 0.38, 0.052), 'timber', C_DRIFTWOOD, 0.0, (1, 0, 0))
        cbox(mb, (0.0, 0.0, -0.125), (0.58, 0.075, 0.018), 'paint', C_CRIMSON_HI, 0.0, M=R('Z', 32.0))
        cbox(mb, (0.0, 0.0, -0.125), (0.58, 0.075, 0.018), 'paint', C_CRIMSON_HI, 0.0, M=R('Z', -32.0))
        for bx in (-0.34, 0.34):
            cbox(mb, (bx, 0.0, -0.12), (0.048, 0.048, 0.026), 'iron', C_IRON, 0.0)
    s_br_pts = [
        SIGN_TOP + Vector((0.0, -0.12, 0.0)),
        SIGN_TOP + Vector((-0.14, 0.04, -0.36)),
        SIGN_TOP + Vector((-0.30, -0.06, -0.66)),
    ]
    tube(mb, s_br_pts, [0.040, 0.036, 0.028], 4, 'iron', C_IRON, mode='flat')
    _add_beam(mb, SIGN_TOP + Vector((-0.02, -0.52, 0.04)), s_br_pts[1], 0.034, 0.034, 'iron', C_IRON_RUST, 0.0)
    LANTERN_POS = s_br_pts[-1] + Vector((0.0, -0.34, 0.0))
    _build_storm_lantern(mb, LANTERN_POS, scale=1.04, brass_cage=True, hanging=True)

    # 6. Trailing Cliff-Ivy & Coastal Ferns ('foliage' + UV2) cascading down the vertical sandstone cliff face!
    for v_anc, v_len, v_w, v_dir, v_ph in (
        ((-1.86, FLOOR_Y + 0.04, -0.78), 1.48, 0.18, (-0.3, 0.0, -0.95), 0.11),
        (( 0.84, FLOOR_Y + 0.02, -0.80), 1.54, 0.18, ( 0.2, 0.0, -0.98), 0.37),
        (( 2.24, FLOOR_Y + 0.02, -0.18), 1.46, 0.17, ( 0.9, 0.0, -0.40), 0.64),
        ((-2.32, FLOOR_Y + 0.02,  0.86), 1.42, 0.16, (-1.0, 0.0,  0.10), 0.82),
        (( 1.44, FLOOR_Y + 0.02,  2.30), 1.38, 0.16, ( 0.3, 0.0,  0.95), 0.23),
    ):
        _add_leafy_vine_drape(mb, v_anc, v_len, v_w, v_dir, rng, phase=v_ph)

    for fpos, fsc, flean, fph in (
        ((-2.02, FLOOR_Y + 0.02, -0.42), 0.80, (-0.8, 0.0, -0.5), 0.19),
        (( 2.02, FLOOR_Y + 0.02, -0.22), 0.76, ( 0.8, 0.0, -0.5), 0.56),
        ((-1.82, FLOOR_Y + 0.02,  1.96), 0.82, (-0.6, 0.0,  0.8), 0.85),
    ):
        _add_coastal_fern_cluster(mb, fpos, scale=fsc, n_fronds=4, rng=rng, phase=fph, lean_dir=flean)

    build(mb)

    add_empty('Lantern_SmugglerHoist', LANTERN_POS)
    col_piece('col_hoist_base', col_pts)
    export_landmark_glb(outdir, 'smuggler_rope_cargo_hoist.glb')


# ================================================================ 4. VOLCANIC OBSIDIAN FORGE ANVIL

def gen_volcanic_obsidian_forge_anvil(outdir):
    """Ancient cursed pirate blacksmith's volcanic caldera forge rooted in a wide fractured
    columnar-basalt foundation plunging cleanly to y = -3.60 m (radius ~ 2.65 m).
    Features a low hexagonal obsidian lava-trough hearth brimming with cracked glowing molten embers
    ('glass' + bright molten COLOR_0), towering forked obsidian chimney hood bound in forged-iron
    straps & chains, heavy horned cast-iron ship-anchor anvil set atop a banded charred oak stump,
    forged iron tongs & glowing red-hot cutlass blade resting across the anvil horn, twin flanking
    ember braziers, collider 'col_forge_base', and 'Lantern_VolcForge' empty directly above the
    glowing forge hearth!
    Target: ~3,100-3,700 visual tris, 1 collider (col_forge_base).
    """
    clear_scene()
    rng = random.Random(SEED + 2851)
    mb = MB('VolcanicObsidianForgeAnvil', seed=2851)

    SKIRT_BOT = -3.60
    FLOOR_Y   =  0.52
    col_pts   = []

    # 1. Wide Fractured Columnar-Basalt Caldera Foundation plunging cleanly to y = -3.60 m (r ~ 2.65 m!)
    base_secs = [
        _reg_poly(0.0, SKIRT_BOT, 0.0, 2.86, sides=8, rot_deg=22.5),
        _reg_poly(0.0, -1.65,     0.0, 2.74, sides=8, rot_deg=22.5),
        _reg_poly(0.0, -0.20,     0.0, 2.62, sides=8, rot_deg=22.5),
        _reg_poly(0.0, FLOOR_Y,   0.0, 2.50, sides=8, rot_deg=22.5),
    ]
    _loft_horizontal_masonry(
        mb, base_secs, 'basalt',
        [C_OBSIDIAN_DARK, C_OBSIDIAN_DARK, C_OBSIDIAN_SHINE, C_OBSIDIAN_HI],
        rng, caps=(True, True), top_mat='basalt', top_col=C_OBSIDIAN_SHINE,
    )
    for ring in base_secs:
        col_pts.extend(Vector(p) for p in ring)

    # 8 Clustered Fractured Hexagonal Volcanic Basalt Organ-Pipe Columns buttressing the foundation skirt!
    col_specs = [
        ( 24.0, 2.24, 2.08, 0.44, True),
        ( 68.0, 2.18, 2.52, 0.48, False),
        (114.0, 2.22, 2.58, 0.50, True),
        (158.0, 2.20, 2.04, 0.44, False),
        (206.0, 2.24, 1.78, 0.42, True),
        (252.0, 2.28, 1.32, 0.42, False),
        (294.0, 2.26, 1.38, 0.42, True),
        (338.0, 2.22, 1.82, 0.44, False),
    ]
    for ang_d, rad_c, ch, cr, m_seam in col_specs:
        ang = radians(ang_d)
        ca, sa = cos(ang), sin(ang)
        sculpt_basalt_column(
            mb, (ca * rad_c, -1.10, sa * rad_c), ch, cr, 6,
            ca * 4.5, sa * 4.5,
            C_OBSIDIAN_DARK, mix(C_OBSIDIAN_HI, C_BASALT_HOT, 0.28 if m_seam else 0.08),
            rng, mat='basalt', magma_seam=m_seam,
        )

    # 4 Glowing Molten Lava Fissure Cracks crawling outward across the basalt caldera deck & rim ('glass'!)
    for vk, ang_d in enumerate((22.0, 148.0, 224.0, 316.0)):
        ang = radians(ang_d)
        ca, sa = cos(ang), sin(ang)
        vnrm = Vector((ca * 0.45, 0.89, sa * 0.45)).normalized()
        vpath = [
            (ca * 0.96, FLOOR_Y + 0.03, sa * 0.96 + 0.34),
            (ca * 1.72, FLOOR_Y + 0.02, sa * 1.72 + 0.14),
            (ca * 2.44, FLOOR_Y - 0.10, sa * 2.44),
            (ca * 2.62, -0.58,          sa * 2.62),
        ]
        _sculpt_magma_ribbon(mb, vpath, [0.075, 0.065, 0.052, 0.026], vnrm, hot_core=(vk % 2 == 0))

    # 2. Low Hexagonal Obsidian Lava-Trough Hearth Brimming with Cracked Glowing Molten Embers!
    HZ       = 0.62
    HEARTH_Y = FLOOR_Y + 0.86
    hearth_secs = [
        _reg_poly(0.0, FLOOR_Y - 0.06, HZ, 1.56, sides=6, rot_deg=0.0),
        _reg_poly(0.0, FLOOR_Y + 0.46, HZ, 1.44, sides=6, rot_deg=0.0),
        _reg_poly(0.0, HEARTH_Y,       HZ, 1.38, sides=6, rot_deg=0.0),
    ]
    _loft_horizontal_masonry(
        mb, hearth_secs, 'basalt',
        [C_OBSIDIAN_DARK, C_OBSIDIAN_SHINE, C_OBSIDIAN_HI],
        rng, caps=(False, True), top_mat='basalt', top_col=C_COAL_CHAR,
    )
    # Raised hexagonal obsidian curb blocks + forged-iron corner clamp straps rimming the molten lava trough
    for hk in range(6):
        ang = radians(hk * 60.0 + 30.0)
        ca, sa = cos(ang), sin(ang)
        curb_h = 0.15 if hk == 4 else 0.24
        cbox(mb, (ca * 1.12, HEARTH_Y + curb_h * 0.45, HZ + sa * 1.12),
             (1.16, curb_h, 0.24), 'basalt', mix(C_OBSIDIAN_HI, C_BASALT_HOT, 0.18), 0.0,
             M=R('Y', -degrees(ang) + 90.0))
        ang_c = radians(hk * 60.0)
        cbox(mb, (cos(ang_c) * 1.36, HEARTH_Y - 0.04, HZ + sin(ang_c) * 1.36),
             (0.16, 0.30, 0.16), 'iron', C_IRON_BRONZE if hk % 2 == 0 else C_IRON_FORGED, 0.0,
             M=R('Y', -degrees(ang_c)))

    # Brimming Molten Lava & Cracked Glowing Ember Bed ('glass' + bright molten linear COLOR_0!)
    with xf(mb, T(0.0, HEARTH_Y - 0.02, HZ)):
        lava_prof = [
            (0.00, 0.02),
            (1.12, 0.05),
            (0.96, 0.18),
            (0.56, 0.26),
            (0.00, 0.30),
        ]
        lathe(mb, lava_prof, 6, 'glass', C_FLAME_MID, False, False,
              lambda i, k: C_FLAME_CORE if i >= 2 else (C_FLAME_MID if i == 1 else C_MAGMA_CRIMSON))
        for ck, (cx, cz, cr, ch, cyaw) in enumerate((
            (-0.46, -0.26, 0.22, 0.16,  18.0),
            ( 0.48, -0.22, 0.20, 0.15, -24.0),
            (-0.22,  0.34, 0.24, 0.18,  42.0),
            ( 0.32,  0.30, 0.21, 0.16, -35.0),
            ( 0.02, -0.44, 0.18, 0.12,  12.0),
        )):
            with xf(mb, T(cx, 0.16, cz) @ R('Y', cyaw) @ R('Z', 16.0)):
                cyl(mb, cr, -0.06, ch, 4, 'basalt', C_COAL_CHAR, False, 0.0, cr * 0.55)
        for fp, fr, fh, frot, fcol in (
            (( 0.00, 0.22,  0.00), 0.28, 0.86, (  2.0,  10.0,   4.0), C_FLAME_CORE),
            ((-0.34, 0.16, -0.14), 0.18, 0.62, (-10.0,  28.0,  12.0), C_FLAME_MID),
            (( 0.32, 0.16, -0.10), 0.19, 0.66, (  8.0, -24.0, -10.0), C_FLAME_MID),
            (( 0.04, 0.18,  0.26), 0.20, 0.68, (  6.0,  40.0,  -6.0), C_FLAME_DEEP),
        ):
            with xf(mb, T(fp) @ R('Y', frot[1]) @ R('X', frot[0]) @ R('Z', frot[2])):
                lathe(mb, [(0.0, -0.04), (fr, 0.12), (fr * 0.58, fh * 0.56), (0.0, fh)], 4, 'glass', fcol, False)

    # 3. Towering Forked Obsidian Chimney Hood Bound in Forged-Iron Straps & Anchor Chains (to y = 6.32 m!)
    HOOD_BOT_Y = HEARTH_Y + 1.24
    for px, pz, pw in (
        (-0.98, HZ - 0.52, 0.36),
        ( 0.98, HZ - 0.52, 0.36),
        (-0.96, HZ + 0.68, 0.42),
        ( 0.96, HZ + 0.68, 0.42),
    ):
        _add_beam(mb, (px, HEARTH_Y - 0.06, pz), (px * 0.88, HOOD_BOT_Y + 0.16, pz),
                  pw, pw, 'basalt', mix(C_OBSIDIAN_HI, C_BASALT_HOT, 0.20), 0.0)
    cbox(mb, (0.0, HEARTH_Y + 0.64, HZ + 0.86), (1.88, 1.38, 0.36), 'basalt', C_OBSIDIAN_SHINE, 0.0)
    # Forged-iron arched lintel beam & forged copper-rust rivets across the open seaward forge mouth!
    cbox(mb, (0.0, HOOD_BOT_Y - 0.04, HZ - 0.58), (2.20, 0.25, 0.28), 'iron', C_IRON_FORGED, 0.0)
    for rx in (-0.84, -0.42, 0.0, 0.42, 0.84):
        cbox(mb, (rx, HOOD_BOT_Y - 0.04, HZ - 0.74), (0.085, 0.085, 0.055), 'iron', C_IRON_BRONZE, 0.0)

    # Tapered Hexagonal Obsidian Main Chimney Trunk (y = HOOD_BOT_Y .. 4.38 m)
    trunk_secs = [
        _reg_poly(0.0, HOOD_BOT_Y - 0.04, HZ + 0.08, 1.36, sides=6, rot_deg=0.0),
        _reg_poly(0.0, HOOD_BOT_Y + 0.88, HZ + 0.14, 1.04, sides=6, rot_deg=0.0),
        _reg_poly(0.0, HOOD_BOT_Y + 1.74, HZ + 0.18, 0.82, sides=6, rot_deg=0.0),
    ]
    _loft_horizontal_masonry(
        mb, trunk_secs, 'basalt',
        [C_OBSIDIAN_DARK, C_OBSIDIAN_SHINE, C_OBSIDIAN_HI],
        rng, caps=(True, True), top_mat='basalt', top_col=C_OBSIDIAN_SHINE,
    )
    col_pts.extend([Vector((-1.05, 3.70, HZ)), Vector((1.05, 3.70, HZ))])

    # Towering Asymmetric FORKED Obsidian Chimney Horns splitting dramatically at y = 4.16 m!
    FORK_Y = HOOD_BOT_Y + 1.54
    horn_l_secs = [
        _reg_poly(-0.34, FORK_Y,        HZ + 0.18, 0.56, sides=6, rot_deg=15.0),
        _reg_poly(-0.62, FORK_Y + 1.12, HZ + 0.24, 0.44, sides=6, rot_deg=15.0),
        _reg_poly(-0.82, FORK_Y + 2.16, HZ + 0.30, 0.30, sides=6, rot_deg=15.0),
    ]
    _loft_horizontal_masonry(
        mb, horn_l_secs, 'basalt',
        [C_OBSIDIAN_SHINE, C_OBSIDIAN_HI, mix(C_OBSIDIAN_HI, C_BASALT_HOT, 0.22)],
        rng, caps=(False, True), top_mat='glass', top_col=C_FLAME_DEEP,
    )
    horn_r_secs = [
        _reg_poly( 0.34, FORK_Y,        HZ + 0.18, 0.50, sides=6, rot_deg=-15.0),
        _reg_poly( 0.64, FORK_Y + 0.80, HZ + 0.22, 0.39, sides=6, rot_deg=-15.0),
        _reg_poly( 0.88, FORK_Y + 1.48, HZ + 0.26, 0.26, sides=6, rot_deg=-15.0),
    ]
    _loft_horizontal_masonry(
        mb, horn_r_secs, 'basalt',
        [C_OBSIDIAN_SHINE, C_OBSIDIAN_HI, mix(C_OBSIDIAN_HI, C_BASALT_HOT, 0.22)],
        rng, caps=(False, True), top_mat='glass', top_col=C_FLAME_DEEP,
    )
    cbox(mb, (0.0, FORK_Y + 0.28, HZ + 0.08), (0.34, 0.24, 0.30), 'glass', C_FLAME_MID, 0.0, M=R('Z', 45.0))
    for hx, hy, hz, hrad in ((-0.82, FORK_Y + 2.16, HZ + 0.30, 0.32), (0.88, FORK_Y + 1.48, HZ + 0.26, 0.28)):
        with xf(mb, T(hx, hy, hz)):
            cyl(mb, hrad + 0.05, -0.14, 0.06, 6, 'iron', C_IRON_BRONZE, False, 0.0)
            for sk in range(3):
                ang = radians(sk * 120.0 + 30.0)
                cbox(mb, (cos(ang) * (hrad + 0.04), 0.14, sin(ang) * (hrad + 0.04)),
                     (0.08, 0.32, 0.08), 'iron', C_STEEL_MID, 0.0, M=R('Y', -degrees(ang)) @ R('Z', 16.0))

    # Forged-Iron Binding Straps wrapping the tapered chimney hood + 2 Heavy Interlocking Anchor Chains!
    for by, bz, br, bh in (
        (HOOD_BOT_Y + 0.20, HZ + 0.10, 1.32, 0.18),
        (HOOD_BOT_Y + 1.00, HZ + 0.15, 1.04, 0.17),
        (HOOD_BOT_Y + 1.72, HZ + 0.18, 0.86, 0.15),
    ):
        with xf(mb, T(0.0, by, bz)):
            cyl(mb, br, -bh * 0.5, bh * 0.5, 6, 'iron', C_IRON_FORGED, False, 0.0)
            for rk in range(6):
                ang = radians(rk * 60.0)
                cbox(mb, (cos(ang) * (br + 0.02), 0.0, sin(ang) * (br + 0.02)),
                     (0.095, bh * 0.94, 0.095), 'iron', C_IRON_BRONZE if rk % 2 == 0 else C_STEEL_MID, 0.0,
                     M=R('Y', -degrees(ang)))
    for sgn in (-1.0, 1.0):
        p_shack = Vector((sgn * 1.06, HOOD_BOT_Y + 1.00, HZ + 0.15))
        p_anc   = Vector((sgn * 1.88, FLOOR_Y + 0.16, HZ + 0.52))
        cbox(mb, p_anc - Vector((0.0, 0.08, 0.0)), (0.30, 0.32, 0.30), 'iron', C_IRON_BRONZE, 0.0)
        with xf(mb, T(p_shack) @ M_Y2Z):
            torus(mb, 0.11, 0.032, 5, 4, 'iron', C_IRON_BRONZE, False)
        with xf(mb, T(p_anc + Vector((0.0, 0.10, 0.0))) @ M_Y2Z):
            torus(mb, 0.11, 0.032, 5, 4, 'iron', C_IRON_FORGED, False)
        _add_chain_links(mb, p_shack, p_anc + Vector((0.0, 0.08, 0.0)),
                         n_links=7, link_r=0.22, wire_r=0.058,
                         segs=5, psegs=4, sag=0.28, mat='iron', rust_stride=2, stretch_y=1.46,
                         col_a=C_IRON_FORGED, col_b=C_IRON_BRONZE)

    # 4. Heavy Horned Cast-Iron Ship-Anchor Anvil on Banded Charred Oak Stump (hero foreground centerpiece!)
    ANV_X, ANV_Z = -0.14, -1.18
    STUMP_H      = 0.72

    with xf(mb, T(ANV_X, FLOOR_Y, ANV_Z)):
        # Chunky banded charred-oak blacksmith stump (warm dark scorched timber with bronze-iron hoops!)
        cyl(mb, 0.48, -0.04, STUMP_H, 8, 'timber', C_OAK_CHAR, False, 0.0, 0.43)
        for hy, hr in ((0.18, 0.475), (0.56, 0.448)):
            cyl(mb, hr, hy - 0.038, hy + 0.038, 8, 'iron', C_IRON_BRONZE if hy > 0.3 else C_IRON_FORGED, False, 0.0)
        # Heavy Horned Cast-Iron Ship-Anchor Anvil seated squarely atop the stump (bold & readable!)
        with xf(mb, T(0.0, STUMP_H, 0.0) @ R('Y', 14.0)):
            cbox(mb, (0.0, 0.07, 0.0), (0.86, 0.14, 0.50), 'iron', C_IRON_FORGED, 0.0)
            for fx in (-0.38, 0.38):
                for fz in (-0.20, 0.20):
                    cbox(mb, (fx, 0.15, fz), (0.085, 0.065, 0.085), 'iron', C_IRON_BRONZE, 0.0)
            waist_secs = [
                _rect_oct(0.0, 0.12, 0.0, 0.36, 0.22, 0.05),
                _rect_oct(0.0, 0.29, 0.0, 0.24, 0.15, 0.04),
                _rect_oct(0.0, 0.46, 0.0, 0.42, 0.23, 0.04),
            ]
            loft(mb, waist_secs, 'iron', C_IRON_FORGED, closed=True, caps=(True, True), mode='flat',
                 scols=[C_IRON_FORGED, C_IRON_BRONZE, C_STEEL_MID])
            # Heavy steel-topped flat anvil face & squared heel (+X)
            cbox(mb, (0.04, 0.55, 0.0), (0.94, 0.18, 0.42), 'iron', C_STEEL_MID, 0.0)
            cbox(mb, (0.04, 0.645, 0.0), (0.92, 0.028, 0.40), 'iron', C_STEEL_BRIGHT, 0.0)
            cbox(mb, (0.62, 0.56, 0.0), (0.30, 0.13, 0.32), 'iron', C_STEEL_MID, 0.0)
            cbox(mb, (0.64, 0.635, 0.0), (0.08, 0.02, 0.08), 'basalt', C_OBSIDIAN_DARK, 0.0)
            # Iconic Tapered Conical Ship-Anchor Bick-Horn curving boldly toward -X!
            horn_pts = [
                (-0.40, 0.54, 0.0),
                (-0.68, 0.57, 0.0),
                (-0.98, 0.62, 0.0),
                (-1.20, 0.69, 0.0),
            ]
            tube(mb, horn_pts, [0.175, 0.13, 0.082, 0.024], 6, 'iron', C_STEEL_BRIGHT, mode='flat')
            # Ship-Anchor Cross-Fluke Brass Ring bolted proudly to the seaward waist of the anvil!
            cbox(mb, (0.0, 0.31, -0.19), (0.15, 0.15, 0.10), 'iron', C_IRON_BRONZE, 0.0)
            with xf(mb, T(0.0, 0.24, -0.25) @ R('X', 20.0)):
                torus(mb, 0.135, 0.032, 8, 4, 'brass', C_BRASS_WARM, False)

            # 5. Glowing Red-Hot Cutlass Blade & Forged-Iron Tongs Resting Across the Anvil Face & Horn!
            with xf(mb, T(-0.10, 0.685, 0.02) @ R('Y', -24.0)):
                blade_pts = [
                    Vector(( 0.26, 0.00,  0.00)),
                    Vector(( 0.00, 0.00, -0.02)),
                    Vector((-0.28, 0.00, -0.06)),
                    Vector((-0.56, 0.01, -0.13)),
                    Vector((-0.74, 0.02, -0.20)),
                ]
                b_secs = []
                b_cols = [C_IRON_BRONZE, C_MAGMA_CRIMSON, C_FLAME_DEEP, C_FLAME_MID, C_FLAME_CORE]
                for i, bp in enumerate(blade_pts):
                    w_b = 0.056 * (1.0 - 0.70 * (i / 4.0) ** 1.6)
                    h_b = 0.020 * (1.0 - 0.45 * (i / 4.0))
                    b_secs.append([
                        bp + Vector((0.0, -h_b, -w_b)),
                        bp + Vector((0.0,  h_b, -w_b)),
                        bp + Vector((0.0,  h_b,  w_b)),
                        bp + Vector((0.0, -h_b,  w_b)),
                    ])
                loft(mb, b_secs, 'glass', C_FLAME_MID, closed=True, caps=(True, True), mode='flat', scols=b_cols)
                cbox(mb, (0.30, 0.02, 0.00), (0.045, 0.10, 0.19), 'iron', C_STEEL_MID, 0.0)
                _add_beam(mb, (0.30, 0.02, 0.00), (0.52, 0.02, 0.00), 0.046, 0.046, 'timber', C_TIMBER_MID, 0.0)
                cbox(mb, (0.54, 0.02, 0.00), (0.062, 0.062, 0.062), 'brass', C_GOLD_BRIGHT, 0.0)

            # Hinged Forged-Iron Blacksmith Tongs resting right beside the glowing cutlass on the anvil!
            with xf(mb, T(0.22, 0.685, -0.11) @ R('Y', 28.0)):
                _add_beam(mb, (-0.20, 0.0, -0.035), (0.46, 0.0,  0.075), 0.032, 0.024, 'iron', C_STEEL_BRIGHT, 0.0)
                _add_beam(mb, (-0.20, 0.0,  0.035), (0.46, 0.0, -0.075), 0.032, 0.024, 'iron', C_IRON_BRONZE, 0.0)
                cbox(mb, (-0.02, 0.01, 0.0), (0.058, 0.045, 0.058), 'brass', C_GOLD_BRIGHT, 0.0)

        # Heavy Forged Blacksmith's Cross-Peen Hammer leaning cleanly against the charred oak stump!
        _add_beam(mb, (-0.58, 0.04, -0.26), (-0.40, 0.68, -0.10), 0.046, 0.046, 'timber', C_TIMBER_HI, 0.0)
        with xf(mb, T(-0.40, 0.68, -0.10) @ R('Y', 32.0) @ R('Z', -18.0)):
            cbox(mb, (0.0, 0.0, 0.0), (0.26, 0.11, 0.11), 'iron', C_STEEL_BRIGHT, 0.0)

    # Iron-Hooped Quenching Barrel filled with cool slate-teal quenching water beside the anvil!
    _build_coopered_cask(
        mb, T(1.22, FLOOR_Y + 0.38, -0.96),
        radius=0.32, height=0.76, rng=rng,
        col_a=C_OAK_CHAR, col_b=C_TIMBER_MID, col_head=C_OAK_CHAR,
        segs=7, open_fill=('paint', C_QUENCH_WATER),
    )

    # 6. Twin Flanking Volcanic Ember Braziers (port-front & starboard-mid!)
    for bx, bz in ((-1.64, -0.46), (1.66, -0.16)):
        b_secs = [
            _reg_poly(bx, FLOOR_Y - 0.06, bz, 0.48, sides=6, rot_deg=0.0),
            _reg_poly(bx, FLOOR_Y + 0.92, bz, 0.34, sides=6, rot_deg=0.0),
        ]
        _loft_horizontal_masonry(
            mb, b_secs, 'basalt',
            [C_OBSIDIAN_DARK, C_OBSIDIAN_HI],
            rng, caps=(False, True), top_mat='basalt', top_col=C_OBSIDIAN_HI,
        )
        with xf(mb, T(bx, FLOOR_Y + 0.92, bz)):
            bowl_p = [
                (0.00, 0.00),
                (0.28, 0.04),
                (0.46, 0.28),
                (0.48, 0.38),
                (0.40, 0.38),
                (0.32, 0.16),
                (0.00, 0.14),
            ]
            lathe(mb, bowl_p, 6, 'iron', C_IRON_FORGED, False, False,
                  lambda i, k: C_IRON_BRONZE if i in (2, 3) else C_IRON_FORGED)
            with xf(mb, T(0.0, 0.36, 0.0)):
                torus(mb, 0.45, 0.028, 6, 4, 'iron', C_IRON_BRONZE, False)
            for pk in range(3):
                ang = radians(pk * 120.0 + 30.0)
                _add_beam(mb, (cos(ang) * 0.32, 0.12, sin(ang) * 0.32),
                          (cos(ang) * 0.48, 0.56, sin(ang) * 0.48), 0.036, 0.036, 'iron', C_STEEL_MID, 0.0)
            lathe(mb, [(0.0, 0.14), (0.36, 0.18), (0.28, 0.34), (0.0, 0.42)], 6, 'glass', C_FLAME_MID, False, False,
                  lambda i, k: C_FLAME_CORE if i >= 2 else C_MAGMA_CRIMSON)
            lathe(mb, [(0.0, 0.32), (0.16, 0.44), (0.09, 0.64), (0.0, 0.84)], 4, 'glass', C_FLAME_CORE, False)

    # Lantern_VolcForge empty directly above the glowing forge hearth inside the open obsidian arch!
    LANTERN_POS = Vector((0.0, HEARTH_Y + 0.70, HZ - 0.04))

    build(mb)

    add_empty('Lantern_VolcForge', LANTERN_POS)
    col_piece('col_forge_base', col_pts)
    export_landmark_glb(outdir, 'volcanic_obsidian_forge_anvil.glb')


SEA_LORE_GENERATORS = [
    gen_pirate_shipwright_timber_rack,
    gen_ancient_tidal_obelisk_mirror,
    gen_smuggler_rope_cargo_hoist,
    gen_volcanic_obsidian_forge_anvil,
]
