# Sea of Scoundrels: 4 sculpted 3D Coastal Village, Drydock & Cursed Relic landmarks (Wave I-9).
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


# ---------------------------------------------------------------- local palette & sculptural helpers

C_GOLD_BRIGHT  = srgb('#f6c948')
C_BRASS_DARK   = srgb('#9b7024')
C_MAGMA_CORE   = srgb('#ffc842')
C_MAGMA_MID    = srgb('#f46212')
C_MAGMA_DEEP   = srgb('#a6260a')
C_TAR_PITCH    = srgb('#1c1816')
C_TAR_SHEEN    = srgb('#362c26')
C_OAK_FRESH    = srgb('#c68d52')
C_CRIMSON_HI   = srgb('#cc3226')
C_CRIMSON_DEEP = srgb('#781814')
C_TEAL_BRIGHT  = srgb('#26949a')
C_SOUL_CORE    = srgb('#48ffbe')
C_SOUL_MID     = srgb('#18d88e')
C_SOUL_DEEP    = srgb('#0c8462')
C_STAR_CORE    = srgb('#8af6ff')
C_STAR_MID     = srgb('#22c2ff')
C_STAR_DEEP    = srgb('#1072c8')
C_THATCH_HI    = srgb('#d8ab54')
C_THATCH_MID   = srgb('#b28436')
C_THATCH_SHADE = srgb('#7a5824')
C_THATCH_GREEN = srgb('#6d8630')
C_WICKER_HI    = srgb('#c89c56')
C_WICKER_DARK  = srgb('#8a6530')
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
C_FISH_SILVER  = srgb('#9ec0cc')
C_FISH_BACK    = srgb('#38627a')


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


def _add_trapezoid_voussoir(mb, center_xy, ang0, ang1, r_in, r_out, half_z, mat, col, rng, z_ctr=0.0):
    """Crisp 6-face chiseled radial stone arch voussoir wedge."""
    cx, cy = center_xy
    pad = 0.014
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


def _build_work_lantern(mb, center, scale=1.0, brass_body=False):
    """Crisp chunky low-poly Sea-of-Thieves hanging harbour work lantern / brass oil lamp (~145 tris)."""
    cx, cy, cz = center
    s = scale
    cap_mat = 'brass' if brass_body else 'iron'
    cap_col = C_GOLD_BRIGHT if brass_body else C_IRON
    rib_col = C_TEMPLE_GOLD if brass_body else C_BRASS
    with xf(mb, T(cx, cy, cz)):
        # Bottom oil reservoir & flared top hood cap
        cyl(mb, 0.15 * s, -0.22 * s, -0.14 * s, 6, cap_mat, cap_col, False, 0.0, 0.17 * s)
        cyl(mb, 0.19 * s,  0.14 * s,  0.24 * s, 6, cap_mat, cap_col, False, 0.0, 0.06 * s)
        cyl(mb, 0.06 * s,  0.24 * s,  0.31 * s, 6, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.03 * s)
        # Warm glowing glass lamp chimney
        cyl(mb, 0.125 * s, -0.14 * s, 0.14 * s, 6, 'glass', C_LANTERN_GL, False, 0.0, 0.135 * s)
        # 4 crisp corner cage ribs (ch=0.0 -> 48 tris!)
        for k in range(4):
            ang = k * pi * 0.5 + pi * 0.25
            cbox(mb, (0.148 * s * cos(ang), 0.0, 0.148 * s * sin(ang)),
                 (0.028 * s, 0.30 * s, 0.028 * s), 'brass', rib_col, 0.0)
        # Top hanging bail ring
        with xf(mb, T(0.0, 0.34 * s, 0.0) @ M_Y2Z):
            torus(mb, 0.055 * s, 0.015 * s, 6, 4, 'iron', C_IRON, False)


def _build_lean_rope_coil(mb, center, radius=0.38, turns=2, r=0.052):
    """Chunky coiled deck hawser ('rope') built with lean 8x4 tori (~128 tris)."""
    for i in range(turns):
        rr = radius * (1.0 - 0.20 * i)
        with xf(mb, T(center[0], center[1] + r * (1.0 + i * 1.75), center[2])):
            torus(mb, rr, r, 8, 4, 'rope', mul(C_ROPE, 0.90 + 0.10 * (i % 2)), True)


def _build_coopered_barrel(mb, M_bar, radius=0.33, height=0.88, rng=None,
                           mat_body='timber', col_a=C_TIMBER_MID, col_b=C_TIMBER_HI,
                           col_head=C_TIMBER_DARK, segs=6, open_tar=False, n_hoops=2):
    """Chunky coopered pirate tar, pitch, or caulking barrel with forged iron hoops."""
    hh = height * 0.5
    if open_tar:
        prof = [
            (0.0,           -hh),
            (radius * 0.80, -hh),
            (radius * 0.96, -hh * 0.52),
            (radius,         0.0),
            (radius * 0.94,  hh * 0.62),
            (radius * 0.82,  hh),
            (radius * 0.70,  hh * 0.86),
            (0.0,            hh * 0.86),
        ]
    else:
        prof = [
            (0.0,           -hh),
            (radius * 0.80, -hh),
            (radius * 0.98, -hh * 0.45),
            (radius * 0.98,  hh * 0.45),
            (radius * 0.80,  hh),
            (0.0,            hh),
        ]
    stave_cols = [
        jit(col_a if k % 2 == 0 else col_b, rng, 0.08, 0.02) if rng else col_a
        for k in range(segs)
    ]
    hoop_spec = (
        ((-hh * 0.70, radius * 0.92), (0.0, radius * 1.02), (hh * 0.70, radius * 0.92))
        if n_hoops >= 3 else
        ((-hh * 0.64, radius * 0.95), (hh * 0.64, radius * 0.95))
    )
    with xf(mb, M_bar):
        def _colfn(i, k):
            if open_tar and i >= 5:
                return C_TAR_PITCH
            if i == 0 or (not open_tar and i == 4):
                return col_head
            return stave_cols[k]
        lathe(mb, prof, segs, mat_body, col_a, False, False, _colfn)
        for hi_idx, (hy, hr) in enumerate(hoop_spec):
            cyl(mb, hr, hy - 0.028, hy + 0.028, segs, 'iron',
                C_IRON_RUST if hi_idx == 1 else C_IRON, False, 0.0)


def _add_fire_flames(mb, center, radius, height, rng, mat='glass',
                     col_core=C_MAGMA_CORE, col_mid=C_MAGMA_MID, col_outer=C_MAGMA_DEEP, n_plumes=4):
    """Chunky stylized faceted flame tongues + glowing ember bed for cauldrons & soul-braziers."""
    cx, cy, cz = center
    with xf(mb, T(cx, cy, cz)):
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
        for v in bm.verts:
            p = v.co
            v.co = Vector((p.x * radius, max(-0.22, p.y) * radius * 0.44, p.z * radius))
        bm.faces.ensure_lookup_table()
        mb.newoff()
        for f in bm.faces:
            pts = [v.co.copy() for v in f.verts]
            fc = sum(pts, Vector()) / len(pts)
            col = col_core if fc.y > radius * 0.14 else (col_mid if fc.y > 0.0 else col_outer)
            mb.fp(pts, mat, jit(col, rng, 0.05), (0, 1, 0), Vector((0.0, -0.2, 0.0)), smooth=False)
        bm.free()

        plume_specs = [
            ((0.00, 0.06, 0.00), (radius * 0.44, height * 1.00), ( 4,   0,  5), col_core),
            ((-radius * 0.34, 0.03, -radius * 0.22), (radius * 0.28, height * 0.74), (-9,  24, 14), col_mid),
            (( radius * 0.32, 0.03,  radius * 0.20), (radius * 0.27, height * 0.76), ( 8, -32,-12), col_mid),
            (( radius * 0.22, 0.02, -radius * 0.28), (radius * 0.22, height * 0.60), (10,  42, -9), col_outer),
        ][:n_plumes]
        for poff, (prx, pry), prot, pcol in plume_specs:
            with xf(mb, T(poff) @ R('Y', prot[1]) @ R('X', prot[0]) @ R('Z', prot[2])):
                prof = [
                    (0.0, -pry * 0.14),
                    (prx, 0.0),
                    (prx * 0.68, pry * 0.46),
                    (0.0, pry),
                ]
                lathe(mb, prof, 4, mat, jit(pcol, rng, 0.05), smooth=False)


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

    n_leaves = max(4, int(length * 1.8))
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
            sway = sin(t * 4.2 + f_ph * 6.28) * 0.26 * (0.18 + 0.82 * t) + s_shift * (0.4 + 0.6 * t)
            flutter = cos(t * 3.1 + f_ph * 5.2) * 0.12 * t
            ctr = a + od * (0.06 + 0.32 * sin(t * pi * 0.65) + 0.14 * t + flutter) + side * sway + Vector((0.0, -f_len * t, 0.0))
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


def _build_double_sided_pennant(mb, root_pos, length=2.45, h0=0.84, out_dir=(-0.72, 0.0, -0.69),
                                col_main=C_PAINT_RED, col_trim=C_PAINT_CREAM, tattered=True):
    """Fluttering 3D double-sided swallowtail crimson captain's banner (100% backface-cull safe!)."""
    rp = Vector(root_pos)
    od = Vector(out_dir).normalized()
    side = Vector((-od.z, 0.0, od.x))
    if side.length < 1e-4:
        side = Vector((1.0, 0.0, 0.0))
    side.normalize()
    segs = 5
    thick = 0.016

    top_pts = []
    bot_pts = []
    for i in range(segs + 1):
        t = i / float(segs)
        wave = sin(t * 2.25 * pi) * 0.24 * t + 0.05 * sin(t * 4.2)
        droop = -0.26 * t * t
        hh = h0 * (1.0 - 0.44 * t)
        if tattered and i == 3:
            hh *= 0.82
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


def _build_gold_chalice(mb, M_ch, scale=1.0):
    """Lathe-turned antique golden pirate goblet/chalice ('brass')."""
    s = scale
    prof = [
        (0.0,       0.0),
        (0.11 * s,  0.0),
        (0.036 * s, 0.08 * s),
        (0.034 * s, 0.19 * s),
        (0.145 * s, 0.34 * s),
        (0.148 * s, 0.42 * s),
        (0.0,       0.32 * s),
    ]
    with xf(mb, M_ch):
        lathe(mb, prof, 6, 'brass', C_GOLD_BRIGHT, False)


# ================================================================ 1. CAREENING SHIP DRYDOCK

def gen_careening_ship_drydock(outdir):
    """Heavy coastal pirate ship-careening timber slipway (~10.2 m long x 6.4 m wide, battered
    stone-and-piling slipway foundation plunging cleanly to y = -3.6 m anti-float!).
    Parallel heavy oak skid rails, notched keel-cradle timber blocks, angled hull shoring struts,
    stacked curved oak repair planks, iron-banded tar & caulking barrels, coiled heavy 'rope'
    hawser spool, forged-iron steaming pitch cauldron glowing warm orange ('glass' ember core),
    and hanging work lantern on a timber post ('Lantern_Drydock' empty!).
    Target: 3,200-4,200 visual tris, 1 collider (col_drydock_cradle).
    """
    clear_scene()
    rng = random.Random(SEED + 1401)
    mb = MB('CareeningShipDrydock', seed=1401)

    FOUND_BOT = -3.60
    SLOPE_Z0 = -4.90
    SLOPE_Z1 = 4.90
    Y_SEA = 0.24
    Y_LAND = 1.56

    def ramp_y(z):
        t = (z - SLOPE_Z0) / (SLOPE_Z1 - SLOPE_Z0)
        return Y_SEA + (Y_LAND - Y_SEA) * t

    slope_deg = degrees(atan2(Y_LAND - Y_SEA, SLOPE_Z1 - SLOPE_Z0))
    col_pts = []

    # 1. Battered Stone-and-Piling Slipway Foundation (10.2 m long x 6.4 m wide, plunging cleanly to y = -3.60 m!)
    def _slip_ring(y_override=None, hx=3.12, hz=5.08, ch=0.42):
        pts = _rect_oct(0.0, 0.0, 0.0, hx, hz, ch)
        out = []
        for px, _, pz in pts:
            py = y_override if y_override is not None else (ramp_y(pz) + (0.04 if abs(px) > 1.85 else 0.0))
            out.append((px, py, pz))
        return out

    found_secs = [
        _slip_ring(y_override=FOUND_BOT, hx=3.54, hz=5.42, ch=0.52),
        _slip_ring(y_override=-1.75,     hx=3.34, hz=5.26, ch=0.46),
        _slip_ring(y_override=-0.18,     hx=3.18, hz=5.14, ch=0.42),
        _slip_ring(y_override=None,      hx=3.06, hz=5.02, ch=0.38),
    ]
    found_cols = [
        mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.68),
        mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.48),
        mix(C_TEMPLE_MID,  C_SEA_MOSS, 0.30),
        mix(C_TEMPLE_HI,   C_LEDGE_MOSS, 0.20),
    ]
    _loft_horizontal_masonry(
        mb, found_secs, 'temple_stone', found_cols, rng, caps=(True, True),
        top_mat='limestone_moss', top_col=mix(C_TEMPLE_MID, C_LEDGE_MOSS, 0.28),
    )
    for ring in found_secs:
        col_pts.extend(Vector(p) for p in ring)

    # Raised continuous stone flank work curbs along port & starboard aprons (clean height offset -> 0 Z-fighting!)
    for sx in (-2.55, 2.55):
        with xf(mb, T(sx, 0.5 * (Y_SEA + Y_LAND) + 0.09, 0.0) @ R('X', -slope_deg)):
            cbox(mb, (0.0, 0.0, 0.0), (1.02, 0.22, 9.25), 'temple_stone', C_TEMPLE_MID, 0.0, (0, 0, 1))

    # Deeply-rooted mossy coastal rock footing outcrops anchoring the landward flanks!
    for rpos, rrad, rrot, mc in (
        ((-3.08, -0.95,  3.85), (1.08, 2.25, 1.15), ( 4,  24, -5), 0.68),
        (( 3.12, -0.90,  4.02), (1.12, 2.35, 1.18), (-5, -32,  4), 0.72),
    ):
        col_pts += sculpt_rock_mass(
            mb, rpos, rrad, 'limestone_moss',
            C_LEDGE_MOSS, C_LIME_WARM, C_LIME_DARK, rng,
            subdiv=1, warp=0.18, strata=0.12, base_flare=0.45, rot_deg=rrot, moss_cap=mc,
        )

    # 8 Heavy Driven Oak Fender Pilings flanking the slipway (plunging cleanly to FOUND_BOT = -3.60 m!)
    piling_zs = (-4.55, -1.55, 1.50, 4.45)
    for sx in (-3.12, 3.12):
        for pi_idx, pz in enumerate(piling_zs):
            if sx < 0 and pi_idx == 0:
                continue  # Occupied cleanly by the integrated tall work-lantern corner post!
            py_deck = ramp_y(pz)
            py_top = py_deck + (1.35 if pi_idx in (0, 3) else 0.94) + rng.uniform(-0.08, 0.12)
            lean_x = sx * 0.03
            tube(mb, [
                (sx + lean_x * 1.4, FOUND_BOT, pz),
                (sx + lean_x * 0.5, -0.35, pz),
                (sx, py_top, pz),
            ], [0.24, 0.21, 0.18], 5, 'timber', C_TIMBER_DARK, mode='flat',
                scols=[mix(C_TIMBER_DARK, C_SEA_MOSS, 0.52), C_TIMBER_DARK, C_DRIFTWOOD])
            with xf(mb, T(sx, py_top - 0.14, pz)):
                cyl(mb, 0.20, -0.055, 0.055, 5, 'iron', C_IRON_RUST if pi_idx % 2 == 0 else C_IRON, False, 0.0)
            if pi_idx == 0:
                with xf(mb, T(sx, py_deck + 0.38, pz)):
                    torus(mb, 0.22, 0.044, 6, 4, 'rope', C_ROPE, True)
            col_pts.extend([Vector((sx, FOUND_BOT, pz)), Vector((sx, py_top, pz))])

        _add_beam(mb, (sx * 1.03, Y_SEA - 0.35, -4.75), (sx * 1.03, Y_LAND - 0.45, 4.65),
                  0.22, 0.24, 'timber', C_TIMBER_DARK, 0.0)

    # 2. Cross-Tie Oak Sleepers, Parallel Heavy Oak Skid Rails & Notched Keel-Cradle Timber Blocks!
    for si in range(7):
        tz = -4.25 + si * 1.40
        ty = ramp_y(tz) + 0.08
        with xf(mb, T(0.0, ty, tz) @ R('X', -slope_deg)):
            cbox(mb, (0.0, 0.0, 0.0), (4.45, 0.18, 0.30), 'timber',
                 jit(C_TIMBER_DARK if si % 2 == 0 else C_TIMBER_MID, rng, 0.06), 0.0, (1, 0, 0))

    # Parallel Heavy Oak Skid Rails (x = -1.38, 0.0, +1.38) climbing the slipway incline!
    for rx, rw, rh, rcol in (
        (-1.38, 0.32, 0.28, C_TIMBER_HI),
        ( 0.00, 0.40, 0.24, C_TIMBER_MID),
        ( 1.38, 0.32, 0.28, C_TIMBER_HI),
    ):
        p_sea  = Vector((rx, ramp_y(-4.65) + 0.26, -4.65))
        p_land = Vector((rx, ramp_y( 4.35) + 0.26,  4.35))
        _add_beam(mb, p_sea, p_land, rw, rh, 'timber', rcol, 0.0)
        for tz_s in (-3.2, 0.0, 3.2):
            p_st = Vector((rx, ramp_y(tz_s) + 0.28, tz_s))
            with xf(mb, T(p_st) @ R('X', -slope_deg)):
                cbox(mb, (0.0, 0.0, 0.0), (rw + 0.05, rh + 0.04, 0.16), 'iron', C_IRON, 0.0)

    # 4 Chunky Stepped & Notched Keel-Cradle Timber Blocks + Bilge Chock Wedges!
    cradle_zs = (-3.15, -1.05, 1.05, 3.15)
    for ci, cz in enumerate(cradle_zs):
        cy = ramp_y(cz) + 0.38
        with xf(mb, T(0.0, cy, cz) @ R('X', -slope_deg)):
            cbox(mb, (0.0, 0.14, 0.0), (1.16, 0.28, 0.44), 'timber', jit(C_TIMBER_DARK, rng, 0.06), 0.0, (1, 0, 0))
            cbox(mb, (0.0, 0.40, 0.0), (0.86, 0.24, 0.38), 'timber', jit(C_TIMBER_MID, rng, 0.06), 0.0, (1, 0, 0))
            for sx in (-0.36, 0.36):
                with xf(mb, T(sx, 0.62, 0.0) @ R('Z', -22.0 if sx < 0 else 22.0)):
                    cbox(mb, (0.0, 0.0, 0.0), (0.36, 0.22, 0.34), 'timber', C_TIMBER_HI, 0.0, (1, 0, 0))
            for sx in (-1.38, 1.38):
                cbox(mb, (sx, 0.18, 0.0), (0.48, 0.32, 0.44), 'timber', jit(C_TIMBER_MID, rng, 0.06), 0.0, (0, 0, 1))
                with xf(mb, T(sx * 0.90, 0.42, 0.0) @ R('Z', -28.0 if sx < 0 else 28.0)):
                    cbox(mb, (0.0, 0.0, 0.0), (0.50, 0.20, 0.36), 'timber', C_OAK_FRESH, 0.0, (1, 0, 0))

    # 3. Bold Angled Hull Shoring Struts (3 pairs = 6 heavy raking A-frame shipyard hull shores!)
    shoring_specs = [
        (-2.45, -1.0, 2.75, -1.48),
        (-2.45,  1.0, 3.05,  1.45),
        ( 0.05, -1.0, 3.40, -1.42),
        ( 0.05,  1.0, 3.55,  1.40),
        ( 2.55, -1.0, 2.95, -1.48),
        ( 2.55,  1.0, 2.80,  1.50),
    ]
    for sz, sgn, sh_h, in_x in shoring_specs:
        ry = ramp_y(sz) + 0.16
        p_foot = Vector((sgn * 2.38, ry, sz))
        p_head = Vector((in_x, ry + sh_h, sz))
        _add_beam(mb, p_foot, p_head, 0.22, 0.24, 'timber', jit(C_TIMBER_MID, rng, 0.06), 0.0)
        p_post_top = Vector((sgn * 2.26, ry + sh_h * 0.54, sz))
        _add_beam(mb, Vector((sgn * 2.28, ry, sz)), p_post_top, 0.18, 0.18, 'timber', C_TIMBER_DARK, 0.0)
        _add_beam(mb, Vector((sgn * 1.46, ry + 0.14, sz)), p_post_top, 0.14, 0.14, 'timber', C_DRIFTWOOD, 0.0)
        cbox(mb, p_foot + Vector((0.0, 0.08, 0.0)), (0.34, 0.18, 0.32), 'iron', C_IRON, 0.0)
        with xf(mb, T(p_head) @ R('Z', -26.0 * sgn)):
            cbox(mb, (0.0, 0.0, 0.0), (0.46, 0.16, 0.44), 'timber', C_TIMBER_HI, 0.0, (0, 0, 1))
        col_pts.append(p_head)

    # Longitudinal catwalk scaffolding planks running along the shoring A-frames!
    for sgn in (-1.0, 1.0):
        p_a = Vector((sgn * 2.26, ramp_y(-2.45) + 1.56, -2.65))
        p_b = Vector((sgn * 2.26, ramp_y( 2.55) + 1.58,  2.75))
        _add_beam(mb, p_a, p_b, 0.44, 0.11, 'timber', C_DRIFTWOOD if sgn < 0 else C_TIMBER_HI, 0.0)

    # 4. Landward Heavy Careening Haul-Winch Frame & Iron-Hooked Tow Hawser (z = +4.25 m)!
    wy = ramp_y(4.25) + 0.18
    for sx in (-0.95, 0.95):
        cbox(mb, (sx, wy + 0.62, 4.25), (0.28, 1.32, 0.34), 'timber', C_TIMBER_DARK, 0.0, (0, 1, 0))
        _add_beam(mb, (sx, wy + 0.05, 4.92), (sx, wy + 1.15, 4.28), 0.18, 0.18, 'timber', C_TIMBER_MID, 0.0)
    with xf(mb, T(0.0, wy + 0.88, 4.25) @ M_Y2X):
        cyl(mb, 0.11, -1.16, 1.16, 6, 'iron', C_IRON, False, 0.0)
        cyl(mb, 0.30, -0.74, 0.74, 6, 'rope', C_ROPE, False, 0.0)
        for rx_w in (-0.42, 0.0, 0.42):
            with xf(mb, T(0.0, rx_w, 0.0)):
                torus(mb, 0.305, 0.048, 6, 4, 'rope', mul(C_ROPE, 0.90 + 0.10 * (rx_w == 0.0)), True)
        for sx_fl in (-0.78, 0.78):
            cyl(mb, 0.44, sx_fl - 0.04, sx_fl + 0.04, 6, 'iron', C_IRON_RUST, False, 0.0)
    for hk in range(4):
        ang = hk * pi * 0.5 + 0.4
        _add_beam(mb, (1.16, wy + 0.88, 4.25),
                  (1.16, wy + 0.88 + cos(ang) * 0.68, 4.25 + sin(ang) * 0.68),
                  0.075, 0.075, 'timber', C_TIMBER_HI, 0.0)
    haul_pts = [
        (0.0, wy + 0.58, 4.10),
        (0.0, ramp_y(1.80) + 0.60, 1.80),
        (0.0, ramp_y(-1.25) + 0.58, -1.25),
    ]
    tube(mb, haul_pts, 0.048, 4, 'rope', C_ROPE, mode='smooth')
    with xf(mb, T(0.0, ramp_y(-1.35) + 0.56, -1.38)):
        torus(mb, 0.12, 0.036, 6, 4, 'iron', C_IRON, False)
        tube(mb, [(0.0, 0.0, -0.08), (0.0, 0.08, -0.36), (0.0, 0.24, -0.44), (0.0, 0.28, -0.26)],
             [0.042, 0.048, 0.040, 0.022], 4, 'iron', C_IRON_RUST, mode='flat')

    # 5. Stacked Curved Oak Repair Planks on Starboard Work Apron (x = +2.55 m)!
    trestle_y = ramp_y(0.45) + 0.20
    for tz_t in (-0.65, 1.55):
        ty_t = ramp_y(tz_t) + 0.20
        _add_beam(mb, (2.22, ty_t, tz_t - 0.18), (2.42, ty_t + 0.72, tz_t), 0.11, 0.11, 'timber', C_TIMBER_DARK, 0.0)
        _add_beam(mb, (2.82, ty_t, tz_t + 0.18), (2.64, ty_t + 0.72, tz_t), 0.11, 0.11, 'timber', C_TIMBER_DARK, 0.0)
        _add_beam(mb, (2.15, ty_t + 0.68, tz_t), (2.92, ty_t + 0.68, tz_t), 0.13, 0.14, 'timber', C_TIMBER_MID, 0.0)
    for pl_i in range(4):
        layer = pl_i // 2
        col_off = (pl_i % 2) * 0.28 - 0.14
        px_base = 2.52 + col_off
        py_base = trestle_y + 0.80 + layer * 0.11
        p_col = jit(C_OAK_FRESH if pl_i % 2 == 0 else C_TIMBER_HI, rng, 0.07)
        p_secs = []
        for si_k in range(4):
            u = si_k / 3.0
            pz_k = -1.35 + u * 3.60
            bend_x = sin(u * pi) * 0.15 * (1.0 if pl_i % 2 == 0 else -0.6)
            bend_y = ramp_y(pz_k) - ramp_y(0.45) + sin(u * pi) * 0.08
            cx_k, cy_k = px_base + bend_x, py_base + bend_y
            hw, hh = 0.14, 0.038
            p_secs.append([(cx_k - hw, cy_k - hh, pz_k), (cx_k + hw, cy_k - hh, pz_k),
                           (cx_k + hw, cy_k + hh, pz_k), (cx_k - hw, cy_k + hh, pz_k)])
        loft(mb, p_secs, 'timber', p_col, closed=True, caps=(True, True), mode='flat')

    for lean_i in range(2):
        _add_beam(mb, (2.78 - lean_i * 0.18, ramp_y(-3.15) + 0.20, -3.20 + lean_i * 0.14),
                  (2.22 - lean_i * 0.14, ramp_y(-2.45) + 2.35, -2.52 + lean_i * 0.12),
                  0.24, 0.065, 'timber', C_OAK_FRESH if lean_i == 0 else C_DRIFTWOOD, 0.0)

    # 6. Iron-Banded Tar & Caulking Barrels + Coiled Heavy 'rope' Hawser Spool!
    bar_specs = [
        ((-2.52, ramp_y(2.35) + 0.62, 2.35), (0.0,  18.0, 0.0), 0.34, 0.88, False, C_TIMBER_DARK, C_TIMBER_MID),
        ((-2.35, ramp_y(3.15) + 0.60, 3.15), (0.0, -28.0, 0.0), 0.32, 0.84, True,  C_TAR_SHEEN,   C_TIMBER_DARK),
        ((-2.55, ramp_y(-1.35) + 0.60, -1.35), (0.0, 12.0, 0.0), 0.33, 0.84, True, C_TAR_SHEEN,   C_TIMBER_DARK),
    ]
    for bpos, brot, brad, bh, is_tar, ca, cb in bar_specs:
        M_b = T(bpos) @ R('Y', brot[1]) @ R('X', brot[0]) @ R('Z', brot[2])
        _build_coopered_barrel(mb, M_b, radius=brad, height=bh, rng=rng,
                               col_a=ca, col_b=cb, col_head=C_TIMBER_DARK, segs=6, open_tar=is_tar, n_hoops=2)
    _add_beam(mb, (-2.55, ramp_y(-1.35) + 0.82, -1.35), (-2.40, ramp_y(-1.35) + 1.56, -1.55),
              0.055, 0.055, 'timber', C_TIMBER_HI, 0.0)
    cbox(mb, (-2.53, ramp_y(-1.35) + 0.94, -1.39), (0.14, 0.22, 0.04), 'basalt', C_TAR_PITCH, 0.0)

    # Heavy Wooden Flanged Hawser Rope Spool on Starboard-Landward Apron (x = +2.45 m, z = +3.35 m)!
    sp_y = ramp_y(3.35) + 0.18
    with xf(mb, T(2.45, sp_y + 0.64, 3.35) @ R('Y', -18.0)):
        for sx_r in (-0.48, 0.48):
            _add_beam(mb, (sx_r, -0.64, -0.44), (sx_r, 0.06, 0.0), 0.11, 0.12, 'timber', C_TIMBER_DARK, 0.0)
            _add_beam(mb, (sx_r, -0.64,  0.44), (sx_r, 0.06, 0.0), 0.11, 0.12, 'timber', C_TIMBER_DARK, 0.0)
            cbox(mb, (sx_r, -0.58, 0.0), (0.12, 0.12, 0.96), 'timber', C_TIMBER_DARK, 0.0, (0, 0, 1))
        with xf(mb, M_Y2X):
            cyl(mb, 0.075, -0.62, 0.62, 5, 'iron', C_IRON, False, 0.0)
            for fx_r in (-0.38, 0.38):
                cyl(mb, 0.56, fx_r - 0.04, fx_r + 0.04, 8, 'timber', C_TIMBER_MID, False, 0.0)
            cyl(mb, 0.37, -0.34, 0.34, 8, 'rope', C_ROPE, False, 0.0)
            for rr_x in (-0.20, 0.0, 0.20):
                with xf(mb, T(0.0, rr_x, 0.0)):
                    torus(mb, 0.385, 0.062, 6, 4, 'rope', mul(C_ROPE, 0.90 + 0.10 * (rr_x == 0.0)), True)
    _build_lean_rope_coil(mb, (2.38, ramp_y(-3.95) + 0.18, -3.95), radius=0.42, turns=2, r=0.056)

    # 7. Forged-Iron Steaming Pitch Cauldron Glowing Warm Orange ('glass' ember core) on Open Port-Seaward Apron!
    caul_x, caul_z = -2.35, -3.55
    caul_y = ramp_y(caul_z) + 0.18
    with xf(mb, T(caul_x, caul_y, caul_z)):
        cyl(mb, 0.88, -0.06, 0.20, 6, 'temple_stone', C_TEMPLE_DARK, False, 0.0, 0.80)
        for ck in range(6):
            ang = 2.0 * pi * ck / 6.0
            cbox(mb, (cos(ang) * 0.72, 0.24, sin(ang) * 0.72), (0.34, 0.18, 0.24),
                 'basalt', jit(C_BASALT_MID, rng, 0.06), 0.0, M=R('Y', -degrees(ang)))
        _add_fire_flames(mb, (0.0, 0.24, 0.0), radius=0.58, height=0.82, rng=rng, mat='glass',
                         col_core=C_MAGMA_CORE, col_mid=C_MAGMA_MID, col_outer=C_MAGMA_DEEP, n_plumes=3)
        for k in range(3):
            ang = radians(30.0 + k * 120.0)
            ca, sa = cos(ang), sin(ang)
            _add_beam(mb, (ca * 0.68, 0.12, sa * 0.68), (ca * 0.56, 1.06, sa * 0.56), 0.085, 0.085, 'iron', C_IRON, 0.0)
            _add_beam(mb, (ca * 0.56, 1.06, sa * 0.56), (ca * 0.66, 1.28, sa * 0.66), 0.075, 0.075, 'iron', C_IRON_RUST, 0.0)
        kettle_prof = [
            (0.00, 0.48), (0.44, 0.54), (0.70, 0.86),
            (0.64, 1.22), (0.70, 1.28), (0.54, 1.14), (0.00, 1.14),
        ]
        lathe(mb, kettle_prof, 7, 'iron', C_IRON, smooth=False,
              colfn=lambda i, k: C_TAR_PITCH if i >= 5 else (C_IRON_RUST if i == 2 else C_IRON))
        with xf(mb, T(0.0, 1.00, 0.0)):
            torus(mb, 0.705, 0.036, 7, 4, 'iron', C_IRON_RUST, False)
        for bx, bz, br in ((-0.16, -0.10, 0.13), (0.18, 0.12, 0.11)):
            with xf(mb, T(bx, 1.16, bz)):
                cyl(mb, br, -0.02, br * 0.82, 5, 'glass', C_MAGMA_MID, False, 0.0, br * 0.35)
        _add_beam(mb, (0.12, 1.06, 0.08), (0.52, 1.94, 0.36), 0.044, 0.044, 'iron', C_IRON, 0.0)

    # 8. Tall Timber Work Lantern Post (integrated corner piling!) & Hanging Work Lantern ('Lantern_Drydock' empty!)
    post_x, post_z = -3.10, -4.55
    post_y0 = ramp_y(post_z) + 0.05
    post_top_y = post_y0 + 4.45
    tube(mb, [
        (post_x - 0.06, FOUND_BOT, post_z),
        (post_x - 0.02, -0.35, post_z),
        (post_x + 0.04, post_y0 + 2.20, post_z - 0.02),
        (post_x + 0.09, post_top_y, post_z - 0.05),
    ], [0.24, 0.21, 0.17, 0.135], 6, 'timber', C_TIMBER_DARK, mode='flat',
        scols=[mix(C_TIMBER_DARK, C_SEA_MOSS, 0.52), C_TIMBER_DARK, C_TIMBER_MID, C_DRIFTWOOD])
    with xf(mb, T(post_x + 0.01, post_y0 + 0.36, post_z)):
        torus(mb, 0.22, 0.044, 6, 4, 'rope', C_ROPE, True)
    arm_root = Vector((post_x + 0.08, post_top_y - 0.32, post_z - 0.04))
    arm_tip  = arm_root + Vector((1.28, 0.16, -0.18))
    _add_beam(mb, arm_root, arm_tip, 0.14, 0.16, 'timber', C_TIMBER_MID, 0.0)
    _add_beam(mb, Vector((post_x + 0.06, post_top_y - 1.28, post_z - 0.03)),
              arm_root.lerp(arm_tip, 0.68), 0.11, 0.11, 'timber', C_TIMBER_DARK, 0.0)
    lantern_pos = arm_tip + Vector((0.0, -0.68, 0.0))
    _add_beam(mb, arm_tip + Vector((0.0, -0.04, 0.0)), lantern_pos + Vector((0.0, 0.38, 0.0)),
              0.042, 0.042, 'iron', C_IRON, 0.0)
    _build_work_lantern(mb, lantern_pos, scale=1.38, brass_body=False)
    col_pts.extend([Vector((post_x, FOUND_BOT, post_z)), Vector((post_x, post_top_y, post_z))])

    # 9. Coastal Sea-Kelp & Crevice Fern Accents ('foliage' with UV2 wind!)
    for anc, klen, kw, odir, kph in (
        ((-3.12, 0.35, -3.50), 1.85, 0.23, (-0.9, 0.0, -0.4), 0.12),
        (( 3.12, 0.38, -3.20), 1.95, 0.24, ( 0.9, 0.0, -0.4), 0.48),
    ):
        _add_kelp_drape(mb, anc, klen, kw, odir, rng, phase=kph, segs=4)
    for fpos, fsc, nf, fph, flean in (
        ((-2.95, 1.38, 4.32), 0.95, 4, 0.22, (-0.7, 0.0, 0.7)),
        (( 2.98, 1.44, 4.38), 1.00, 4, 0.61, ( 0.7, 0.0, 0.7)),
    ):
        _add_jungle_fern_cluster(mb, fpos, scale=fsc, n_fronds=nf, rng=rng, phase=fph, lean_dir=flean)

    build(mb)

    add_empty('Lantern_Drydock', lantern_pos)
    col_piece('col_drydock_cradle', col_pts)
    export_landmark_glb(outdir, 'careening_ship_drydock.glb')


# ================================================================ 2. CURSED SKELETON THRONE SHRINE

def _sculpt_throne_skull(mb, center, scale, rng):
    """Chunky Sea-of-Thieves sculpted captain's skull crowning the throne backrest (facing seaward -Z)."""
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
        rz = (0.68 + 0.08 * parietal) * s
        temp = max(0.0, 1.0 - ((y + 0.36) / 0.45) ** 2) * max(0.0, (abs(x) - 0.45) / 0.55)
        rx -= 0.15 * s * temp
        brow = max(0.0, 1.0 - abs(y + 0.08) / 0.22) * smooth01((-z - 0.25) / 0.55) * 0.14 * s
        v.co = Vector((x * rx, y * ry, z * rz - brow))
    bm.faces.ensure_lookup_table()
    mb.newoff()
    with xf(mb, T(cx, cy + 0.18 * s, cz)):
        for f in bm.faces:
            pts = [v.co.copy() for v in f.verts]
            fn = newell(pts)
            if fn.length < 1e-8:
                continue
            fn.normalize()
            fc = sum(pts, Vector()) / len(pts)
            c = C_SKULL_BONE if (fn.y > 0.30 or fc.z < -0.25 * s) else (C_SKULL_SHADE if fn.y < -0.25 else C_SKULL_MID)
            mb.fp(pts, 'skull_stone', jit(c, rng, 0.05), (1, 0, 0), Vector((0, 0, 0)), smooth=False)
    bm.free()

    with xf(mb, T(cx, cy, cz)):
        for sgn in (-1.0, 1.0):
            with xf(mb, T(sgn * 0.34 * s, 0.20 * s, -0.56 * s) @ R('Z', -16.0 * sgn)):
                cbox(mb, (0.0, 0.0, 0.0), (0.48 * s, 0.18 * s, 0.30 * s), 'skull_stone', C_SKULL_BONE, 0.0)
            with xf(mb, T(sgn * 0.56 * s, -0.14 * s, -0.44 * s) @ R('Y', -24.0 * sgn)):
                cbox(mb, (0.0, 0.0, 0.0), (0.28 * s, 0.26 * s, 0.36 * s), 'skull_stone', C_SKULL_MID, 0.0)
            with xf(mb, T(sgn * 0.30 * s, -0.02 * s, -0.52 * s) @ R('Z', -14.0 * sgn) @ M_Y2Z):
                cyl(mb, 0.23 * s, -0.14 * s, 0.18 * s, 6, 'basalt', C_SKULL_CAV, False, 0.0, 0.19 * s)
            with xf(mb, T(sgn * 0.29 * s, -0.02 * s, -0.60 * s)):
                cyl(mb, 0.11 * s, -0.09 * s, 0.09 * s, 5, 'skull_glow', C_SOUL_CORE, False, 0.0, 0.04 * s)

        with xf(mb, T(0.0, -0.24 * s, -0.60 * s) @ M_Y2Z):
            cyl(mb, 0.12 * s, -0.08 * s, 0.14 * s, 4, 'basalt', C_SKULL_CAV, False, 0.0, 0.06 * s)
        cbox(mb, (0.0, -0.40 * s, -0.40 * s), (0.86 * s, 0.28 * s, 0.52 * s), 'skull_stone', C_SKULL_MID, 0.0)
        for ti, tx in enumerate((-0.30, -0.15, 0.0, 0.15, 0.30)):
            th = (0.24 if ti in (1, 3) else 0.20) * s
            tz = -0.60 * s + abs(tx) * 0.24 * s
            cbox(mb, (tx * s, -0.58 * s, tz), (0.115 * s, th, 0.13 * s),
                 'skull_stone', jit(C_SKULL_BONE if ti != 2 else C_GOLD_BRIGHT, rng, 0.04), 0.0)

        # Jagged Tilted Tarnished Gold Pirate Captain's Crown perched atop the Skull!
        with xf(mb, T(0.0, 0.72 * s, -0.06 * s) @ R('Z', -9.0) @ R('X', 8.0)):
            cyl(mb, 0.66 * s, -0.06 * s, 0.18 * s, 7, 'brass', C_TEMPLE_GOLD, False, 0.0, 0.72 * s)
            for k in range(6):
                ang = 2.0 * pi * k / 6.0 - pi * 0.5
                ca, sa = cos(ang), sin(ang)
                sp_h = (0.48 if k == 0 else (0.36 if k in (1, 5) else 0.28)) * s
                with xf(mb, T(ca * 0.66 * s, 0.16 * s, sa * 0.66 * s) @ R('Y', -degrees(ang)) @ R('Z', -14.0)):
                    cyl(mb, 0.14 * s, 0.0, sp_h, 4, 'brass',
                        C_GOLD_BRIGHT if k in (0, 2, 4) else C_BRASS, False, 0.0, 0.02 * s)


def _build_pirate_cutlass(mb, M_sword, length=4.45):
    """Oversized monumental pirate boarding cutlass ('iron' curved blade + 'brass' basket D-guard hilt)."""
    with xf(mb, M_sword):
        cyl(mb, 0.13, -0.16, 0.04, 6, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.08)
        cyl(mb, 0.085, 0.02, 0.64, 5, 'timber', C_TIMBER_DARK, False, 0.0, 0.075)
        cbox(mb, (0.0, 0.68, 0.0), (0.58, 0.10, 0.24), 'brass', C_GOLD_BRIGHT, 0.0)
        guard_pts = [(0.24, 0.68, 0.0), (0.42, 0.46, 0.0), (0.38, 0.16, 0.0), (0.10, -0.06, 0.0)]
        tube(mb, guard_pts, [0.046, 0.052, 0.044, 0.036], 4, 'brass', C_TEMPLE_GOLD, mode='flat')

        blade_len = length - 0.72
        n_st = 5
        secs = []
        scols = []
        for i in range(n_st):
            t = i / float(n_st - 1)
            y = 0.70 + t * blade_len
            curve_x = -0.34 * (t * t)
            half_w = (0.19 + 0.11 * sin(t * pi * 0.85)) * (1.0 - 0.88 * (t ** 3.2))
            half_d = 0.055 * (1.0 - 0.65 * t)
            secs.append([
                (curve_x - half_w,       y,  0.0),
                (curve_x + half_w * 0.2, y, -half_d),
                (curve_x + half_w,       y,  0.0),
                (curve_x + half_w * 0.2, y,  half_d),
            ])
            scols.append(C_IRON if i < 2 else (mix(C_IRON, C_SKULL_BONE, 0.28) if i >= 3 else C_IRON_RUST))
        loft(mb, secs, 'iron', C_IRON, closed=True, caps=(True, True), mode='flat', scols=scols)


def gen_cursed_skeleton_throne_shrine(outdir):
    """Jagged ancient stone & weathered bone pirate captain's throne plaza (~7.8 m wide x 7.2 m tall,
    solid stepped basalt/stone foundation skirt sinking cleanly to y = -3.6 m anti-float!).
    Towering sculpted skull-crowned throne backrest ('skull_stone' + 'basalt'), crossed forged-iron
    cutlasses mounted behind the crown, spilled gleaming 'brass' chalices & gold coin piles on the
    steps, tattered crimson captain's banner ('paint'), twin flanking iron soul-braziers blazing
    emerald-green ('skull_glow' + 'Lantern_Throne' empty!), and draping 'foliage' moss vines (UV2 wind!).
    Target: 3,000-4,200 visual tris, 2 colliders (col_throne_dais, col_throne_back).
    """
    clear_scene()
    rng = random.Random(SEED + 1433)
    mb = MB('CursedSkeletonThroneShrine', seed=1433)

    SKIRT_BOT = -3.60
    T1_TOP = 0.62
    T2_TOP = 1.18
    PODIUM_TOP = 1.68

    dais_col_pts = []
    back_col_pts = []

    # 1. Solid Stepped Ancient Basalt & Temple-Stone Plaza Foundation (~7.8 m wide, sinking to y = -3.60 m!)
    d1_secs = [
        _rect_oct(0.0, SKIRT_BOT, 0.08, 4.35, 3.65, 1.15),
        _rect_oct(0.0, -1.65,     0.08, 4.10, 3.42, 1.08),
        _rect_oct(0.0,  0.00,     0.08, 3.92, 3.26, 1.02),
        _rect_oct(0.0,  T1_TOP,   0.08, 3.84, 3.18, 0.98),
    ]
    d1_cols = [
        mix(C_BASALT_DARK, C_SEA_MOSS, 0.32),
        C_BASALT_DARK,
        C_BASALT_MID,
        mix(C_BASALT_TOP, C_TEMPLE_DARK, 0.45),
    ]
    _loft_horizontal_masonry(
        mb, d1_secs, 'basalt', d1_cols, rng, caps=(True, True),
        top_mat='temple_stone', top_col=mix(C_TEMPLE_DARK, C_BASALT_TOP, 0.50),
    )
    for ring in d1_secs:
        dais_col_pts.extend(Vector(p) for p in ring)

    d2_secs = [
        _rect_oct(0.0, T1_TOP - 0.06, 0.46, 2.86, 2.38, 0.72),
        _rect_oct(0.0, T2_TOP,        0.46, 2.74, 2.26, 0.68),
    ]
    _loft_horizontal_masonry(
        mb, d2_secs, 'temple_stone', [C_TEMPLE_DARK, C_TEMPLE_MID], rng, caps=(False, True),
        top_mat='temple_stone', top_col=C_TEMPLE_MID,
    )
    dais_col_pts.extend(Vector(p) for p in d2_secs[-1])

    d3_secs = [
        _rect_oct(0.0, T2_TOP - 0.06, 0.96, 1.94, 1.56, 0.44),
        _rect_oct(0.0, PODIUM_TOP,    0.96, 1.82, 1.44, 0.40),
    ]
    _loft_horizontal_masonry(
        mb, d3_secs, 'basalt', [C_BASALT_DARK, C_BASALT_TOP], rng, caps=(False, True),
        top_mat='basalt', top_col=C_BASALT_MID,
    )
    dais_col_pts.extend(Vector(p) for p in d3_secs[-1])

    # Ceremonial Seaward Approach Steps (-Z) grounded cleanly down to SKIRT_BOT!
    _box2(mb, (-1.62, SKIRT_BOT, -3.52), (1.62, 0.24, -2.96), 'basalt', C_BASALT_DARK, 0.0)
    _box2(mb, (-1.48,  0.16,     -3.28), (1.48, T1_TOP + 0.01, -2.72), 'temple_stone', C_TEMPLE_MID, 0.0)
    _box2(mb, (-1.34,  T1_TOP - 0.05, -2.28), (1.34, T1_TOP + 0.30, -1.72), 'temple_stone', C_TEMPLE_MID, 0.0)
    _box2(mb, (-1.22,  T1_TOP + 0.22, -1.94), (1.22, T2_TOP + 0.01, -1.36), 'temple_stone', C_TEMPLE_HI, 0.0)
    _box2(mb, (-1.08,  T2_TOP - 0.05, -0.96), (1.08, T2_TOP + 0.26, -0.44), 'basalt', C_BASALT_MID, 0.0)
    _box2(mb, (-0.96,  T2_TOP + 0.20, -0.66), (0.96, PODIUM_TOP + 0.01, -0.14), 'basalt', C_BASALT_TOP, 0.0)

    # Tattered Crimson Velvet Captain's Stair Runner cascading cleanly down the center steps!
    for ry0, rz0, rz1 in (
        (PODIUM_TOP + 0.028, -0.52,  0.48),
        (T2_TOP + 0.285,     -0.94, -0.44),
        (T2_TOP + 0.028,     -1.88, -0.92),
        (T1_TOP + 0.325,     -2.26, -1.78),
        (T1_TOP + 0.028,     -3.16, -2.22),
    ):
        cbox(mb, (0.0, ry0, 0.5 * (rz0 + rz1)), (0.94, 0.036, abs(rz1 - rz0)), 'paint', C_PAINT_RED, 0.0)
        for sx_t in (-0.42, 0.42):
            cbox(mb, (sx_t, ry0 + 0.014, 0.5 * (rz0 + rz1)), (0.075, 0.022, abs(rz1 - rz0)), 'brass', C_TEMPLE_GOLD, 0.0)

    # Flanking Jagged Columnar Volcanic Basalt Organ-Pipe Spurs framing the Throne Sanctuary!
    basalt_spurs = [
        ((-3.05, SKIRT_BOT,  1.25), 7.45, 0.64,  9.5, -5.0, False),
        ((-2.62, SKIRT_BOT,  2.18), 8.25, 0.68,  7.0, -7.0, True),
        (( 3.05, SKIRT_BOT,  1.25), 7.25, 0.62, -9.5, -5.0, False),
        (( 2.60, SKIRT_BOT,  2.20), 8.10, 0.66, -7.5, -6.5, True),
        ((-1.92, SKIRT_BOT,  2.65), 7.55, 0.66,  5.0, -5.0, False),
        (( 1.92, SKIRT_BOT,  2.65), 7.45, 0.64, -5.0, -5.0, False),
    ]
    for bpos, bh, brad, btx, btz, bseam in basalt_spurs:
        sculpt_basalt_column(
            mb, bpos, bh, brad, 5, btx, btz,
            C_BASALT_DARK, mix(C_BASALT_TOP, C_TEMPLE_MID, 0.25),
            rng, mat='basalt', magma_seam=bseam,
        )
        back_col_pts.append(Vector((bpos[0], bpos[1] + bh, bpos[2])))

    # 2. Towering Sculpted Stone & Weathered Bone Pirate Captain's Throne (y = 1.68 .. 7.20 m!)
    tz = 1.10
    _box2(mb, (-1.18, PODIUM_TOP - 0.05, tz - 0.64), (1.18, PODIUM_TOP + 0.84, tz + 0.66), 'basalt', C_BASALT_DARK, 0.0)
    cbox(mb, (0.0, PODIUM_TOP + 0.88, tz - 0.04), (1.72, 0.16, 1.12), 'paint', C_CRIMSON_DEEP, 0.0)
    cbox(mb, (0.0, PODIUM_TOP + 0.94, tz - 0.06), (1.44, 0.08, 0.92), 'paint', C_PAINT_RED, 0.0)
    cbox(mb, (0.0, PODIUM_TOP + 0.42, tz - 0.68), (0.62, 0.56, 0.08), 'brass', C_TEMPLE_GOLD, 0.0)
    cbox(mb, (0.0, PODIUM_TOP + 0.42, tz - 0.73), (0.32, 0.32, 0.06), 'skull_stone', C_SKULL_BONE, 0.0, M=R('Z', 45.0))

    # Carved Basalt & Curved Rib-Bone Throne Armrests + Miniature Skull Armrest Finials!
    for sgn in (-1.0, 1.0):
        ax = sgn * 1.14
        _box2(mb, (ax - 0.24, PODIUM_TOP - 0.04, tz - 0.74), (ax + 0.24, PODIUM_TOP + 1.48, tz + 0.72),
              'basalt', C_BASALT_MID, 0.0)
        cbox(mb, (ax, PODIUM_TOP + 1.54, tz - 0.04), (0.56, 0.16, 1.56), 'basalt', C_BASALT_TOP, 0.0)
        for rbi, rbz in enumerate((-0.42, 0.38)):
            rib_pts = [
                (ax + sgn * 0.22, PODIUM_TOP + 0.24, tz + rbz),
                (ax + sgn * 0.44, PODIUM_TOP + 0.88, tz + rbz),
                (ax + sgn * 0.18, PODIUM_TOP + 1.62, tz + rbz),
            ]
            tube(mb, rib_pts, [0.10, 0.115, 0.075], 4, 'skull_stone',
                 C_SKULL_BONE if rbi == 0 else C_SKULL_MID, mode='flat')
        with xf(mb, T(ax, PODIUM_TOP + 1.76, tz - 0.68) @ R('Y', -14.0 * sgn)):
            cyl(mb, 0.22, -0.14, 0.18, 6, 'skull_stone', C_SKULL_BONE, False, 0.0, 0.19)
            cbox(mb, (0.0, -0.06, -0.16), (0.24, 0.18, 0.14), 'skull_stone', C_SKULL_MID, 0.0)
            for ex_m in (-0.08, 0.08):
                cbox(mb, (ex_m, 0.04, -0.20), (0.075, 0.075, 0.06), 'skull_glow', C_SOUL_CORE, 0.0)

    # Towering Cathedral-Like Jagged Basalt Backrest Slab + Flaring Skeletal Rib-Fan Halo!
    back_secs = [
        _rect_oct(0.0, PODIUM_TOP,        tz + 0.56, 1.44, 0.50, 0.22),
        _rect_oct(0.0, PODIUM_TOP + 1.95, tz + 0.66, 1.48, 0.46, 0.22),
        _rect_oct(0.0, PODIUM_TOP + 3.45, tz + 0.78, 1.32, 0.44, 0.20),
        _rect_oct(0.0, PODIUM_TOP + 4.45, tz + 0.84, 0.86, 0.36, 0.16),
    ]
    _loft_horizontal_masonry(
        mb, back_secs, 'basalt', [C_BASALT_DARK, C_BASALT_MID, C_BASALT_TOP, C_BASALT_MID],
        rng, caps=(True, True),
    )
    for ring in back_secs:
        back_col_pts.extend(Vector(p) for p in ring)

    cbox(mb, (0.0, PODIUM_TOP + 2.15, tz + 0.14), (1.36, 2.38, 0.12), 'paint', C_CRIMSON_DEEP, 0.0)
    cbox(mb, (0.0, PODIUM_TOP + 2.15, tz + 0.06), (1.02, 2.12, 0.06), 'paint', C_PAINT_RED, 0.0)
    for sgn in (-1.0, 1.0):
        for ri, (ry_r, r_len, r_lift, r_z) in enumerate((
            (PODIUM_TOP + 1.95, 1.55, 0.88, tz + 0.42),
            (PODIUM_TOP + 2.85, 1.85, 1.15, tz + 0.50),
            (PODIUM_TOP + 3.65, 1.52, 1.28, tz + 0.58),
        )):
            bone_pts = [
                (sgn * 0.45, ry_r,               r_z + 0.18),
                (sgn * (0.65 + r_len * 0.56), ry_r + r_lift * 0.35, r_z - 0.18),
                (sgn * (0.65 + r_len),        ry_r + r_lift,        r_z - 0.52),
            ]
            tube(mb, bone_pts, [0.15, 0.125, 0.036], 5, 'skull_stone',
                 C_SKULL_BONE if ri != 1 else C_SKULL_MID, mode='flat')
            back_col_pts.append(Vector(bone_pts[-1]))

    # Iconic Sculpted Skull-Crown Centerpiece perched cleanly in front of the Basalt Backrest (ZERO rear clip!)
    skull_ctr = Vector((0.0, PODIUM_TOP + 3.76, tz + 0.14))
    _sculpt_throne_skull(mb, skull_ctr, scale=1.18, rng=rng)
    back_col_pts.append(skull_ctr + Vector((0.0, 1.15, 0.0)))

    # 3. Crossed Monumental Forged-Iron Cutlasses Mounted Boldly Behind the Skull Crown (blades + brass hilts clearly visible!)
    cross_ctr = Vector((0.0, PODIUM_TOP + 3.62, tz + 1.14))
    for sgn in (-1.0, 1.0):
        M_sw = T(cross_ctr) @ R('Z', sgn * 44.0) @ T(0.0, -2.05, 0.0) @ R('Y', 180.0 if sgn > 0 else 0.0)
        _build_pirate_cutlass(mb, M_sw, length=5.35)
        back_col_pts.append(cross_ctr + Vector((sgn * 2.15, 2.25, 0.0)))
    cbox(mb, cross_ctr + Vector((0.0, 0.0, 0.08)), (0.72, 0.72, 0.24), 'iron', C_IRON, 0.0, M=R('Z', 45.0))
    cbox(mb, cross_ctr + Vector((0.0, 0.0, 0.18)), (0.36, 0.36, 0.10), 'brass', C_GOLD_BRIGHT, 0.0, M=R('Z', 45.0))

    # 4. Tattered Crimson Captain's Banner Pike planted dramatically on the Starboard Throne Flank!
    pike_x, pike_z = 2.38, 0.52
    pike_y0 = T2_TOP - 0.15
    pike_top = 6.68
    tube(mb, [(pike_x, pike_y0, pike_z), (pike_x + 0.14, 3.85, pike_z - 0.05), (pike_x + 0.28, pike_top, pike_z - 0.12)],
         [0.10, 0.08, 0.055], 5, 'timber', C_TIMBER_DARK, mode='flat',
         scols=[C_TIMBER_DARK, C_TIMBER_MID, C_DRIFTWOOD])
    with xf(mb, T(pike_x + 0.28, pike_top, pike_z - 0.12)):
        cyl(mb, 0.10, -0.04, 0.38, 4, 'iron', C_IRON, False, 0.0, 0.015)
    _build_double_sided_pennant(
        mb, (pike_x + 0.26, pike_top - 0.56, pike_z - 0.10),
        length=2.35, h0=0.92, out_dir=(0.68, 0.0, -0.73),
        col_main=C_PAINT_RED, col_trim=C_TEMPLE_GOLD, tattered=True,
    )

    # 5. Twin Flanking Forged-Iron Soul-Braziers Blazing Emerald-Green ('skull_glow' + 'Lantern_Throne' empty!)
    braz_positions = [(-2.62, T1_TOP, -1.78), (2.62, T1_TOP, -1.78)]
    for bx, by, bz in braz_positions:
        with xf(mb, T(bx, by, bz)):
            cyl(mb, 0.72, -0.08, 0.38, 6, 'basalt', C_BASALT_DARK, False, 0.0, 0.62)
            cyl(mb, 0.64,  0.36, 0.52, 6, 'temple_stone', C_TEMPLE_MID, False, 0.0, 0.56)
            for k in range(4):
                ang = k * pi * 0.5 + pi * 0.25
                ca, sa = cos(ang), sin(ang)
                _add_beam(mb, (ca * 0.46, 0.46, sa * 0.46), (ca * 0.68, 1.38, sa * 0.68), 0.085, 0.085, 'iron', C_IRON, 0.0)
                _add_beam(mb, (ca * 0.68, 1.38, sa * 0.68), (ca * 0.84, 2.02, sa * 0.84), 0.055, 0.055, 'iron', C_IRON_RUST, 0.0)
            bowl_prof = [
                (0.00, 1.02), (0.44, 1.06), (0.76, 1.48),
                (0.68, 1.58), (0.54, 1.32), (0.00, 1.22),
            ]
            lathe(mb, bowl_prof, 7, 'iron', C_IRON, smooth=False,
                  colfn=lambda i, k: C_IRON_RUST if i == 2 else C_IRON)
            with xf(mb, T(0.0, 1.54, 0.0)):
                torus(mb, 0.76, 0.048, 7, 4, 'iron', C_IRON_RUST, False)
            with xf(mb, T(0.0, 1.92, 0.0)):
                torus(mb, 0.82, 0.038, 7, 4, 'iron', C_IRON, False)
        _add_fire_flames(mb, (bx, by + 1.48, bz), radius=0.54, height=1.18, rng=rng, mat='skull_glow',
                         col_core=C_SOUL_CORE, col_mid=C_SOUL_MID, col_outer=C_SOUL_DEEP, n_plumes=3)
        dais_col_pts.append(Vector((bx, by + 2.20, bz)))

    # 6. Spilled Gleaming 'brass' Chalices & Gold Coin Piles across the Steps & Plaza!
    coin_mounds = [
        (-1.42, T2_TOP + 0.01, -0.82, 0.46, 0.24),
        ( 1.36, T2_TOP + 0.01, -0.78, 0.44, 0.22),
        ( 0.92, T1_TOP + 0.01, -2.35, 0.40, 0.19),
        (-1.05, T1_TOP + 0.01, -2.42, 0.38, 0.18),
        ( 1.28, PODIUM_TOP + 0.01, 0.08, 0.34, 0.16),
    ]
    for cx_m, cy_m, cz_m, cr_m, ch_m in coin_mounds:
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
        for v in bm.verts:
            p = v.co
            v.co = Vector((p.x * cr_m, max(-0.12, p.y) * ch_m, p.z * cr_m))
        bm.faces.ensure_lookup_table()
        mb.newoff()
        with xf(mb, T(cx_m, cy_m + 0.01, cz_m)):
            for f in bm.faces:
                pts = [v.co.copy() for v in f.verts]
                mb.fp(pts, 'brass', jit(C_GOLD_BRIGHT if rng.random() > 0.35 else C_TEMPLE_GOLD, rng, 0.06),
                      (1, 0, 0), Vector((0, -0.1, 0)), smooth=False)
        bm.free()

    chalice_specs = [
        ((-1.26, T2_TOP + 0.02, -0.58), (0.0,  20.0,  0.0), 1.18),
        ((-1.62, T2_TOP + 0.13, -1.04), (78.0, 42.0, 12.0), 1.08),
        (( 1.52, T2_TOP + 0.02, -0.62), (0.0, -18.0,  0.0), 1.18),
        (( 1.16, T1_TOP + 0.12, -2.18), (82.0,-34.0, -8.0), 1.04),
        (( 1.38, PODIUM_TOP + 0.02, -0.18), (0.0, 0.0, 0.0), 1.24),
    ]
    for chp, chr_d, chs in chalice_specs:
        M_ch = T(chp) @ R('Y', chr_d[1]) @ R('X', chr_d[0]) @ R('Z', chr_d[2])
        _build_gold_chalice(mb, M_ch, scale=chs)

    # 7. Draping 'foliage' Moss Vines (UV2 wind!) & Dark Crevice Ferns climbing the Cursed Shrine!
    vine_specs = [
        ((-2.25, 5.05,  1.65), 3.15, 0.30, (-0.75, 0.0, -0.65), 0.10),
        (( 2.22, 4.95,  1.68), 3.05, 0.28, ( 0.75, 0.0, -0.65), 0.28),
        ((-1.15, 5.45,  2.35), 3.65, 0.32, (-0.30, 0.0,  0.95), 0.45),
        (( 1.18, 5.35,  2.35), 3.55, 0.32, ( 0.30, 0.0,  0.95), 0.62),
        ((-3.68, T1_TOP, -0.45), 1.95, 0.28, (-1.00, 0.0, -0.15), 0.78),
        (( 3.68, T1_TOP, -0.35), 2.05, 0.28, ( 1.00, 0.0, -0.15), 0.91),
    ]
    for anc, vlen, vw, vdir, vph in vine_specs:
        _add_leafy_vine_drape(mb, anc, vlen, vw, vdir, rng, phase=vph)
    for fpos, fsc, nf, fph, flean in (
        ((-3.15, T1_TOP - 0.04, -0.65), 1.10, 4, 0.18, (-0.9, 0.0, -0.4)),
        (( 3.18, T1_TOP - 0.04, -0.58), 1.06, 4, 0.54, ( 0.9, 0.0, -0.4)),
    ):
        _add_jungle_fern_cluster(mb, fpos, scale=fsc, n_fronds=nf, rng=rng, phase=fph, lean_dir=flean)

    build(mb)

    add_empty('Lantern_Throne', (0.0, 2.85, -1.25))
    col_piece('col_throne_dais', dais_col_pts)
    col_piece('col_throne_back', back_col_pts)
    export_landmark_glb(outdir, 'cursed_skeleton_throne_shrine.glb')


# ================================================================ 3. TROPICAL FISHING STILTS HUT

def _build_wicker_trap(mb, M_trap, radius=0.38, height=0.58, rng=None):
    """Chunky woven domed coastal lobster/crab wicker trap ('rope' + 'timber' hoop)."""
    with xf(mb, M_trap):
        prof = [
            (0.00, 0.00),
            (radius * 0.98, 0.00),
            (radius * 1.02, height * 0.40),
            (radius * 0.78, height * 0.80),
            (0.00, height),
        ]
        lathe(mb, prof, 6, 'rope', C_WICKER_HI, smooth=False,
              colfn=lambda i, k: jit(C_WICKER_HI if (i + k) % 2 == 0 else C_WICKER_DARK, rng, 0.06) if rng else C_WICKER_HI)
        with xf(mb, T(0.0, height * 0.42, 0.0)):
            torus(mb, radius * 1.02, 0.030, 6, 4, 'timber', C_TIMBER_DARK, False)
        with xf(mb, T(0.0, height * 0.38, -radius * 0.88) @ M_Y2Z):
            cyl(mb, 0.14, -0.05, 0.07, 5, 'timber', C_TIMBER_DARK, False, 0.0, 0.10)


def _build_fish_crate(mb, M_crate, size=(0.86, 0.44, 0.56), rng=None, with_fish=True):
    """Slatted weathered wooden fisherman's catch crate with painted teal stripe & fresh silver fish!"""
    sx, sy, sz = size
    hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
    with xf(mb, M_crate):
        cbox(mb, (0.0, 0.04, 0.0), (sx - 0.04, 0.08, sz - 0.04), 'timber', C_TIMBER_DARK, 0.0)
        for xs in (-hx + 0.04, hx - 0.04):
            for zs in (-hz + 0.04, hz - 0.04):
                cbox(mb, (xs, hy, zs), (0.07, sy, 0.07), 'timber', C_TIMBER_DARK, 0.0, (0, 1, 0))
        for sl_i, sl_y in enumerate((0.14, sy - 0.10)):
            sc = C_TEAL_BRIGHT if sl_i == 1 else C_DRIFTWOOD
            mat_s = 'paint' if sl_i == 1 else 'timber'
            for zs in (-hz + 0.02, hz - 0.02):
                cbox(mb, (0.0, sl_y, zs), (sx, 0.13, 0.04), mat_s, jit(sc, rng, 0.05) if rng else sc, 0.0, (1, 0, 0))
            for xs in (-hx + 0.02, hx - 0.02):
                cbox(mb, (xs, sl_y, 0.0), (0.04, 0.13, sz), mat_s, jit(sc, rng, 0.05) if rng else sc, 0.0, (0, 0, 1))
        if with_fish:
            for fx, fy, fz, fyaw in ((-0.16, sy - 0.08, -0.06, 18.0), (0.14, sy - 0.04, 0.08, -32.0)):
                with xf(mb, T(fx, fy, fz) @ R('Y', fyaw) @ R('Z', 90.0)):
                    f_prof = [(0.0, -0.22), (0.085, -0.13), (0.03, -0.05), (0.085, 0.10), (0.0, 0.28)]
                    lathe(mb, f_prof, 4, 'paint', C_FISH_SILVER, False,
                          colfn=lambda i, k: C_FISH_BACK if k == 0 else C_FISH_SILVER)


def _build_cork_buoy(mb, pos, radius=0.14, col_main=C_PAINT_RED, col_band=C_PAINT_CREAM):
    """Stylized painted pirate cork fishing buoy float wrapped with rope collar (~60 tris)."""
    with xf(mb, T(pos)):
        prof = [
            (0.00, -radius * 1.15),
            (radius * 0.82, -radius * 0.56),
            (radius, 0.0),
            (radius * 0.82, radius * 0.56),
            (0.00, radius * 1.15),
        ]
        lathe(mb, prof, 5, 'paint', col_main, False,
              colfn=lambda i, k: col_band if i in (1, 2) else col_main)
        torus(mb, radius * 1.02, radius * 0.14, 5, 3, 'rope', C_ROPE, True)


def gen_tropical_fishing_stilts_hut(outdir):
    """Charming weathered timber & layered palm-thatch pirate fisherman's stilt shelter (~8.2 m wide
    x 7.4 m tall, heavy barnacle-crusted driven timber pilings plunging deeply to y = -4.6 m so it
    roots solidly along sloped cove beaches & shallow turquoise edges!).
    Planked cantilevered fishing deck with wooden jetty steps, leaning weathered driftwood posts,
    hanging woven 'rope' fishing net draped along the railing, painted crimson/teal cork buoy floats
    ('paint'), stacked wicker traps & wooden fish crates, swaying kelp/ferns ('foliage' UV2 wind!),
    and warm hanging brass oil lamp ('Lantern_FishHut' empty!).
    Target: 3,200-4,200 visual tris, 2 colliders (col_fishhut_deck, col_fishhut_roof).
    """
    clear_scene()
    rng = random.Random(SEED + 1471)
    mb = MB('TropicalFishingStiltsHut', seed=1471)

    PILE_BOT = -4.60
    DECK_Y = 2.08
    EAVE_Y = 4.92
    RIDGE_Y = 7.36

    deck_col_pts = []
    roof_col_pts = []

    # 1. Heavy Barnacle-Crusted Driven Timber Pilings plunging deeply to y = -4.60 m!
    piling_specs = [
        (-2.55, -2.92, DECK_Y + 1.38, -0.10, -0.08, True,  True),
        ( 0.25, -2.92, DECK_Y + 0.05,  0.04, -0.08, True,  False),
        ( 3.05, -2.92, DECK_Y + 1.48,  0.12, -0.10, True,  True),
        (-2.55,  0.05, DECK_Y + 0.05, -0.06,  0.02, False, False),
        ( 3.05,  0.05, DECK_Y + 0.05,  0.08,  0.02, True,  False),
        (-2.55,  2.45, DECK_Y + 0.05, -0.08,  0.08, False, False),
        ( 0.25,  2.45, DECK_Y + 0.05,  0.02,  0.06, False, False),
        ( 3.05,  2.45, DECK_Y + 0.05,  0.08,  0.08, False, False),
        (-3.98, -2.15, 1.32,          -0.14, -0.06, True,  True),
        (-3.98, -0.75, 0.85,          -0.10,  0.04, False, False),
    ]
    for pi_idx, (px, pz, py_top, lx, lz, barn, moor) in enumerate(piling_specs):
        tube(mb, [
            (px + lx * 1.4, PILE_BOT, pz + lz * 1.4),
            (px + lx * 0.5, -0.45,    pz + lz * 0.5),
            (px,            py_top,   pz),
        ], [0.23, 0.20, 0.175], 5, 'timber', C_TIMBER_DARK, mode='flat',
            scols=[mix(C_TIMBER_DARK, C_SEA_MOSS, 0.62), mix(C_TIMBER_DARK, C_SEA_MOSS, 0.34), C_DRIFTWOOD])
        deck_col_pts.extend([Vector((px, PILE_BOT, pz)), Vector((px, py_top, pz))])

        if py_top > DECK_Y + 0.5:
            with xf(mb, T(px, DECK_Y + 0.45, pz)):
                torus(mb, 0.21, 0.042, 6, 4, 'rope', C_ROPE, True)
            with xf(mb, T(px, py_top - 0.12, pz)):
                cyl(mb, 0.19, -0.05, 0.05, 5, 'iron', C_IRON_RUST, False, 0.0)
        elif moor:
            with xf(mb, T(px, 0.68, pz)):
                torus(mb, 0.21, 0.040, 6, 4, 'rope', C_ROPE, True)

        if barn:
            for bi in range(2):
                ba = pi_idx * 1.7 + bi * 2.5 + rng.uniform(-0.35, 0.35)
                by_b = rng.uniform(-0.15, 0.58)
                bsz = rng.uniform(0.10, 0.15)
                bx_b = px + cos(ba) * 0.18
                bz_b = pz + sin(ba) * 0.18
                with xf(mb, T(bx_b, by_b, bz_b) @ R('Y', -degrees(ba)) @ R('Z', -72.0)):
                    cyl(mb, bsz, -0.05, bsz * 1.05, 4, 'skull_stone',
                        jit(C_BARNACLE_HI if bi == 0 else C_BARNACLE_MID, rng, 0.06),
                        False, 0.0, bsz * 0.42)

    # Diagonal Under-Deck Timber Sway Bracing & Heavy Deck Joists
    for (p0, p1) in (
        ((-2.55, -0.15, -2.92), ( 0.25, DECK_Y - 0.22, -2.92)),
        (( 3.05, -0.15, -2.92), ( 0.25, DECK_Y - 0.22, -2.92)),
        ((-2.55,  0.05,  2.45), ( 0.25, DECK_Y - 0.22,  2.45)),
        (( 3.05,  0.05,  2.45), ( 0.25, DECK_Y - 0.22,  2.45)),
        (( 3.05, -0.10, -2.92), ( 3.05, DECK_Y - 0.22,  0.05)),
        ((-2.55, -0.10,  0.05), (-2.55, DECK_Y - 0.22,  2.45)),
    ):
        _add_beam(mb, p0, p1, 0.14, 0.15, 'timber', C_TIMBER_DARK, 0.0)

    for jz in (-2.92, 0.05, 2.45):
        _box2(mb, (-2.88, DECK_Y - 0.26, jz - 0.12), (3.42, DECK_Y - 0.04, jz + 0.12),
              'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
    for jx in (-2.45, -0.65, 1.20, 3.08):
        _box2(mb, (jx - 0.10, DECK_Y - 0.16, -2.98), (jx + 0.10, DECK_Y - 0.01, 2.86),
              'timber', C_TIMBER_MID, 0.0, (0, 0, 1))

    # 2. Planked Cantilevered Fishing Deck (y = 2.08 m) + Wooden Jetty Steps (port-seaward!)
    plank_palette = (C_TIMBER_HI, C_TIMBER_MID, C_DRIFTWOOD, C_TIMBER_MID)
    for pi_d in range(12):
        pz = -2.74 + pi_d * 0.49
        pw = 6.26 + rng.uniform(-0.14, 0.14)
        px_c = 0.28 + rng.uniform(-0.06, 0.06)
        cbox(mb, (px_c, DECK_Y + rng.uniform(-0.008, 0.008), pz),
             (pw, 0.095, 0.450), 'timber', jit(plank_palette[pi_d % 4], rng, 0.08, 0.02),
             0.0, (1, 0, 0), M=R('Y', rng.uniform(-0.9, 0.9)))
    deck_col_pts.extend([Vector((-2.95, DECK_Y + 0.1, -3.05)), Vector((3.45, DECK_Y + 0.1, 2.90))])

    # Wooden Jetty Steps descending from Port Deck Edge (x = -2.85) down to Lower Tidal Landing (y = 0.28 m)!
    _box2(mb, (-4.18, 0.16, -2.32), (-3.76, 0.30, -0.58), 'timber', C_TIMBER_DARK, 0.0, (0, 0, 1))
    for pl_j in range(3):
        cbox(mb, (-3.96, 0.32, -2.08 + pl_j * 0.62), (0.86, 0.085, 0.56),
             'timber', jit(C_DRIFTWOOD if pl_j % 2 == 0 else C_TIMBER_MID, rng, 0.07), 0.0, (1, 0, 0))
    for sz_st in (-2.05, -0.82):
        _add_beam(mb, (-3.72, 0.28, sz_st), (-2.68, DECK_Y - 0.06, sz_st), 0.12, 0.18, 'timber', C_TIMBER_DARK, 0.0)
    for ti_s in range(5):
        u = (ti_s + 0.5) / 5.0
        sx_t = -3.68 * (1.0 - u) + (-2.74) * u
        sy_t = 0.34 * (1.0 - u) + (DECK_Y - 0.06) * u
        cbox(mb, (sx_t, sy_t, -1.44), (0.32, 0.085, 1.36), 'timber',
             jit(C_TIMBER_HI if ti_s % 2 == 0 else C_DRIFTWOOD, rng, 0.07), 0.0, (0, 0, 1))
    _add_beam(mb, (-3.98, 1.24, -2.15), (-2.55, DECK_Y + 1.16, -2.92), 0.11, 0.11, 'timber', C_DRIFTWOOD, 0.0)
    deck_col_pts.append(Vector((-4.15, 0.35, -2.25)))

    # 3. Crooked Open-Air Pirate Fisherman's Shelter Frame & Weathered Painted Clapboard Half-Walls!
    hx0, hx1 = -1.42, 2.72
    hz0, hz1 = -0.68, 2.42
    for hpx, hpz, hpy, lx, lz in (
        (hx0, hz0, EAVE_Y + 0.05, -0.08, -0.06),
        (hx1, hz0, EAVE_Y + 0.08,  0.10, -0.05),
        (hx0, hz1, EAVE_Y + 0.02, -0.06,  0.08),
        (hx1, hz1, EAVE_Y + 0.06,  0.08,  0.08),
    ):
        tube(mb, [(hpx, DECK_Y - 0.08, hpz), (hpx + lx * 0.5, DECK_Y + 1.4, hpz + lz * 0.5), (hpx + lx, hpy, hpz + lz)],
             [0.16, 0.145, 0.13], 5, 'timber', C_TIMBER_MID, mode='flat',
             scols=[C_TIMBER_DARK, C_TIMBER_MID, C_DRIFTWOOD])
        roof_col_pts.append(Vector((hpx + lx, hpy, hpz + lz)))
    _add_beam(mb, (0.65, EAVE_Y - 0.04, hz0), (0.67, RIDGE_Y - 0.16, hz0 - 0.04), 0.18, 0.18, 'timber', C_TIMBER_DARK, 0.0)
    _add_beam(mb, (0.65, DECK_Y,        hz1), (0.67, RIDGE_Y - 0.18, hz1 + 0.04), 0.18, 0.18, 'timber', C_TIMBER_DARK, 0.0)

    _add_beam(mb, (hx0 - 0.18, EAVE_Y, hz0 - 0.05), (hx1 + 0.22, EAVE_Y + 0.04, hz0 - 0.05), 0.16, 0.18, 'timber', C_TIMBER_DARK, 0.0)
    _add_beam(mb, (hx0 - 0.18, EAVE_Y, hz1 + 0.05), (hx1 + 0.22, EAVE_Y + 0.02, hz1 + 0.05), 0.16, 0.18, 'timber', C_TIMBER_DARK, 0.0)
    _add_beam(mb, (hx0 - 0.06, EAVE_Y, hz0 - 0.35), (hx0 - 0.06, EAVE_Y, hz1 + 0.35), 0.16, 0.18, 'timber', C_TIMBER_MID, 0.0)
    _add_beam(mb, (hx1 + 0.08, EAVE_Y + 0.04, hz0 - 0.35), (hx1 + 0.08, EAVE_Y + 0.02, hz1 + 0.35), 0.16, 0.18, 'timber', C_TIMBER_MID, 0.0)

    # Cozy horizontal driftwood gable pediment louver slats inside front & rear attic triangles!
    for gz_l in (hz0 + 0.02, hz1 - 0.02):
        for gy_off, gw_l in ((0.42, 3.25), (0.94, 2.18), (1.46, 1.12)):
            cbox(mb, (0.66, EAVE_Y + gy_off, gz_l), (gw_l, 0.28, 0.085), 'timber',
                 jit(C_DRIFTWOOD if gy_off > 0.8 else C_TIMBER_MID, rng, 0.06), 0.0, (1, 0, 0))

    # Back wall (+Z), Starboard wall (+X) with propped crimson shutter, & Port low counter-wall!
    for wi in range(5):
        wy = DECK_Y + 0.32 + wi * 0.52
        is_teal = (wi in (1, 3))
        cbox(mb, (0.65, wy, hz1), (4.12, 0.49, 0.11), 'paint' if is_teal else 'timber',
             jit(C_PAINT_TEAL if is_teal else (C_DRIFTWOOD if wi % 2 == 0 else C_TIMBER_MID), rng, 0.06),
             0.0, (1, 0, 0), M=R('Z', rng.uniform(-0.7, 0.7)))
    for wi in range(5):
        wy = DECK_Y + 0.32 + wi * 0.52
        if wi == 2:
            cbox(mb, (hx1, wy, hz0 + 0.44), (0.11, 0.49, 0.92), 'timber', jit(C_TIMBER_MID, rng, 0.06), 0.0, (0, 0, 1))
            cbox(mb, (hx1, wy, hz1 - 0.44), (0.11, 0.49, 0.92), 'timber', jit(C_DRIFTWOOD, rng, 0.06), 0.0, (0, 0, 1))
        else:
            cbox(mb, (hx1, wy, 0.87), (0.11, 0.49, 3.08), 'paint' if wi == 1 else 'timber',
                 jit(C_PAINT_TEAL if wi == 1 else C_TIMBER_MID, rng, 0.06), 0.0, (0, 0, 1))
    with xf(mb, T(hx1 + 0.06, DECK_Y + 1.82, 0.87) @ R('Z', 52.0)):
        cbox(mb, (0.04, -0.44, 0.0), (0.075, 0.88, 1.18), 'paint', C_PAINT_RED, 0.0, (0, 0, 1))
    _add_beam(mb, (hx1 + 0.08, DECK_Y + 0.98, 0.48), (hx1 + 0.72, DECK_Y + 1.32, 0.48), 0.055, 0.055, 'timber', C_DRIFTWOOD, 0.0)
    for wi in range(2):
        wy = DECK_Y + 0.34 + wi * 0.58
        cbox(mb, (hx0, wy, 0.87), (0.11, 0.54, 3.04), 'timber', jit(C_TIMBER_MID if wi == 0 else C_DRIFTWOOD, rng, 0.06), 0.0, (0, 0, 1))
    cbox(mb, (hx0, DECK_Y + 1.28, 0.87), (0.34, 0.09, 3.16), 'timber', C_TIMBER_HI, 0.0, (0, 0, 1))
    cbox(mb, (hx1 - 0.42, DECK_Y + 1.40, hz0), (0.86, 2.72, 0.10), 'timber', C_TIMBER_MID, 0.0, (0, 1, 0))
    with xf(mb, T(0.65, EAVE_Y - 0.18, hz0 - 0.16) @ R('Z', -2.5)):
        cbox(mb, (0.0, 0.0, 0.0), (2.15, 0.42, 0.08), 'paint', C_PAINT_CREAM, 0.0, (1, 0, 0))
        cbox(mb, (0.0, 0.0, -0.055), (1.76, 0.18, 0.03), 'paint', C_PAINT_TEAL, 0.0)

    # 4. Chunky Layered Tropical Palm-Thatch Gable Roof (peaking at y = 7.36 m, deep overhanging eaves!)
    ridge_cx = 0.66
    _add_beam(mb, (ridge_cx, RIDGE_Y - 0.12, hz0 - 1.05), (ridge_cx, RIDGE_Y - 0.08, hz1 + 0.92),
              0.20, 0.22, 'timber', C_TIMBER_DARK, 0.0)
    for rz_g in (hz0 - 0.88, hz1 + 0.78):
        _add_beam(mb, (ridge_cx - 2.68, EAVE_Y - 0.35, rz_g), (ridge_cx + 0.38, RIDGE_Y + 0.22, rz_g),
                  0.13, 0.15, 'timber', C_TIMBER_DARK, 0.0)
        _add_beam(mb, (ridge_cx + 2.68, EAVE_Y - 0.35, rz_g), (ridge_cx - 0.38, RIDGE_Y + 0.22, rz_g),
                  0.13, 0.15, 'timber', C_TIMBER_DARK, 0.0)

    # Solid dark under-thatch timber sheathing
    for sgn in (-1.0, 1.0):
        with xf(mb, T(ridge_cx + sgn * 1.38, 0.5 * (RIDGE_Y + EAVE_Y) - 0.22, 0.85) @ R('Z', -sgn * 41.5)):
            cbox(mb, (0.0, 0.0, 0.0), (3.65, 0.14, 4.78), 'timber', C_TIMBER_DARK, 0.0, (0, 0, 1))

    # 3 Stepped Overlapping Sculpted Palm-Thatch Roof Tiers (clean outward shingle lap -> ZERO poke-through!)
    thatch_tiers = [
        (0.62, 1.06, 0.28, 0.00, 0.96, mix(C_THATCH_SHADE, C_THATCH_GREEN, 0.22)),
        (0.30, 0.72, 0.30, 0.14, 0.90, C_THATCH_MID),
        (0.00, 0.40, 0.32, 0.28, 0.84, C_THATCH_HI),
    ]
    for ti, (u0, u1, th_t, lap_off, oz, tier_col) in enumerate(thatch_tiers):
        z_a = hz0 - oz
        z_b = hz1 + oz - 0.08
        for sgn in (-1.0, 1.0):
            n_z = 5
            secs_t = []
            scols_t = []
            for zi in range(n_z):
                tz_f = zi / float(n_z - 1)
                zz = z_a + (z_b - z_a) * tz_f
                sag = sin(tz_f * pi) * 0.12
                nx, ny = sgn * 0.64, 0.77
                x0 = ridge_cx + sgn * (u0 * 2.75) + nx * lap_off
                y0 = RIDGE_Y - u0 * (RIDGE_Y - (EAVE_Y - 0.36)) + 0.08 - sag * 0.4 + ny * lap_off
                x1 = ridge_cx + sgn * (u1 * 2.82 + rng.uniform(-0.03, 0.05)) + nx * lap_off
                y1 = RIDGE_Y - u1 * (RIDGE_Y - (EAVE_Y - 0.42)) - sag + ny * lap_off
                secs_t.append([
                    (x0, y0, zz),
                    (x1, y1, zz),
                    (x1 + nx * th_t, y1 + ny * th_t, zz),
                    (x0 + nx * (th_t * 0.88), y0 + ny * (th_t * 0.88), zz),
                ])
                scols_t.append(jit(tier_col, rng, 0.05, 0.015))
            loft(mb, secs_t, 'foliage', tier_col, closed=True, caps=(True, True), mode='flat', scols=scols_t)
            roof_col_pts.extend([Vector(secs_t[0][1]), Vector(secs_t[-1][1]), Vector(secs_t[0][3])])

    # Sculpted Overhanging Palm-Frond Thatch Tuft Bundles along BOTH Eaves (with UV2 wind flutter!)
    for sgn in (-1.0, 1.0):
        eave_x = ridge_cx + sgn * 2.86
        eave_y = EAVE_Y - 0.38
        for fi in range(6):
            fz = (hz0 - 0.75) + fi * 0.86
            f_ph = (fi * 0.17 + (0.4 if sgn > 0 else 0.0)) % 1.0
            p_r  = Vector((eave_x - sgn * 0.18, eave_y + 0.14, fz))
            p_l  = Vector((eave_x + sgn * 0.32, eave_y - 0.36, fz - 0.28))
            p_m  = Vector((eave_x + sgn * 0.44, eave_y - 0.46, fz))
            p_rr = Vector((eave_x + sgn * 0.32, eave_y - 0.36, fz + 0.28))
            c_r = jit(C_THATCH_MID, rng, 0.06)
            c_t = jit(C_THATCH_HI if fi % 2 == 0 else C_THATCH_GREEN, rng, 0.07)
            mb.f([mb.v(p_r), mb.v(p_l), mb.v(p_m), mb.v(p_rr)], 'foliage',
                 [c_r, c_t, c_t, c_t], [(0.5, 0.0), (0.0, 0.7), (0.5, 1.0), (1.0, 0.7)],
                 smooth=False, uv2=[(0.0, f_ph), (0.45, f_ph), (0.62, f_ph), (0.45, f_ph)])

    ridge_pts = [(ridge_cx, RIDGE_Y + 0.36, hz0 - 0.86), (ridge_cx, RIDGE_Y + 0.30, 0.85), (ridge_cx, RIDGE_Y + 0.36, hz1 + 0.78)]
    tube(mb, ridge_pts, [0.24, 0.22, 0.24], 5, 'foliage', C_THATCH_HI, mode='flat',
         scols=[C_THATCH_HI, C_THATCH_MID, C_THATCH_HI])
    for rz_l in (-0.85, 0.85, 2.55):
        with xf(mb, T(ridge_cx, RIDGE_Y + 0.32, rz_l) @ M_Y2Z):
            torus(mb, 0.245, 0.038, 6, 3, 'rope', C_ROPE, True)

    # 5. Leaning Driftwood Railing + Hanging Woven 'rope' Fishing Net Draped Cleanly OUTSIDE Seaward Edge!
    rail_y = DECK_Y + 1.04
    _add_beam(mb, (-2.55, rail_y, -2.92), ( 3.05, rail_y + 0.06, -2.92), 0.11, 0.11, 'timber', C_DRIFTWOOD, 0.0)
    _add_beam(mb, ( 3.05, rail_y + 0.06, -2.92), ( 3.05, rail_y + 0.02, -0.68), 0.11, 0.11, 'timber', C_DRIFTWOOD, 0.0)
    _add_beam(mb, (0.35, DECK_Y, -2.92), (0.42, rail_y + 0.24, -2.95), 0.13, 0.13, 'timber', C_TIMBER_MID, 0.0)

    # Hanging Woven 'rope' Fishing Net draped cleanly OUTSIDE the seaward-starboard rim (ZERO plank clipping!)
    net_x0, net_x1 = 0.52, 2.96
    net_z = -3.08
    n_cols = 5
    n_rows = 3
    grid_pts = []
    for ri in range(n_rows + 1):
        v = ri / float(n_rows)
        row = []
        for ci in range(n_cols + 1):
            u = ci / float(n_cols)
            nx = net_x0 + (net_x1 - net_x0) * u
            sag_edge = sin(u * pi) * 0.40 * (0.35 + 0.65 * v)
            ny = (rail_y + 0.04) - v * 1.46 - sag_edge
            nz = net_z - 0.12 * sin(v * pi * 0.85) - 0.06 * sin(u * pi)
            row.append(Vector((nx, ny, nz)))
        grid_pts.append(row)
    for ri in range(n_rows + 1):
        r_rad = 0.028 if ri in (0, n_rows) else 0.018
        tube(mb, grid_pts[ri], r_rad, 3, 'rope', C_ROPE if ri % 2 == 0 else mul(C_ROPE, 0.88), caps=(False, False), mode='smooth')
    for ci in range(n_cols + 1):
        col_path = [grid_pts[ri][ci] for ri in range(n_rows + 1)]
        tube(mb, col_path, 0.018, 3, 'rope', C_ROPE, caps=(False, False), mode='smooth')
    for ci in (0, 2, 4):
        tube(mb, [grid_pts[0][ci], grid_pts[2][min(n_cols, ci + 1)], grid_pts[3][min(n_cols, ci + 1)]],
             0.015, 3, 'rope', mul(C_ROPE, 0.90), caps=(False, False), mode='smooth')

    # Painted Crimson & Teal Cork Buoy Floats ('paint') strung along the net headline, eaves & deck!
    buoy_specs = [
        ((0.88, rail_y - 0.06, net_z - 0.06), 0.140, C_PAINT_RED,   C_PAINT_CREAM),
        ((1.74, rail_y - 0.22, net_z - 0.12), 0.155, C_TEAL_BRIGHT, C_PAINT_CREAM),
        ((2.58, rail_y - 0.06, net_z - 0.06), 0.140, C_PAINT_RED,   C_PAINT_CREAM),
        ((-0.52, EAVE_Y - 0.56, hz0 - 0.72),  0.145, C_TEAL_BRIGHT, C_PAINT_CREAM),
        (( 1.85, EAVE_Y - 0.54, hz0 - 0.70),  0.145, C_PAINT_RED,   C_PAINT_CREAM),
        (( 2.48, DECK_Y + 0.16, -2.02),       0.145, C_PAINT_RED,   C_PAINT_CREAM),
    ]
    for bpos, brad, bc1, bc2 in buoy_specs:
        _build_cork_buoy(mb, bpos, radius=brad, col_main=bc1, col_band=bc2)
    for ex_b in (-0.52, 1.85):
        tube(mb, [(ex_b, EAVE_Y - 0.12, hz0 - 0.72), (ex_b, EAVE_Y - 0.44, hz0 - 0.72)], 0.016, 3, 'rope', C_ROPE, caps=(False, False), mode='smooth')

    # 6. Stacked Wicker Lobster/Crab Traps, Wooden Fish Crates & Leaning Fishing Pole!
    _build_wicker_trap(mb, T(1.92, DECK_Y + 0.04, -1.78) @ R('Y', -24.0), radius=0.40, height=0.60, rng=rng)
    _build_wicker_trap(mb, T(1.88, DECK_Y + 0.62, -1.80) @ R('Y',  35.0) @ R('Z', 6.0), radius=0.33, height=0.50, rng=rng)

    _build_fish_crate(mb, T(-1.68, DECK_Y + 0.04, -1.96) @ R('Y',  14.0), size=(0.90, 0.44, 0.58), rng=rng, with_fish=True)
    _build_fish_crate(mb, T(-0.84, DECK_Y + 0.04, -2.14) @ R('Y', -16.0), size=(0.82, 0.42, 0.54), rng=rng, with_fish=True)

    rod_base = Vector((-2.15, DECK_Y + 0.04, -2.32))
    rod_tip  = Vector((-2.62, DECK_Y + 2.95, -3.85))
    tube(mb, [rod_base, rod_base.lerp(rod_tip, 0.55) + Vector((0.0, 0.25, 0.0)), rod_tip],
         [0.042, 0.028, 0.014], 4, 'timber', C_OAK_FRESH, mode='flat')
    tube(mb, [rod_tip, Vector((-2.62, 1.10, -3.85))], 0.012, 3, 'rope', C_ROPE, caps=(False, False), mode='smooth')
    _build_cork_buoy(mb, (-2.62, 1.05, -3.85), radius=0.080, col_main=C_PAINT_RED, col_band=C_PAINT_CREAM)

    # 7. Warm Hanging Brass Oil Lamp ('Lantern_FishHut' empty!) under Seaward Verandah Boom!
    boom_root = Vector((0.65, EAVE_Y - 0.14, hz0 - 0.12))
    boom_tip  = Vector((0.65, EAVE_Y - 0.02, hz0 - 1.38))
    _add_beam(mb, boom_root, boom_tip, 0.12, 0.13, 'timber', C_TIMBER_DARK, 0.0)
    lamp_pos = boom_tip + Vector((0.0, -0.64, 0.0))
    _add_beam(mb, boom_tip, lamp_pos + Vector((0.0, 0.36, 0.0)), 0.036, 0.036, 'iron', C_IRON, 0.0)
    _build_work_lantern(mb, lamp_pos, scale=1.35, brass_body=True)

    # 8. Swaying Sea-Kelp Drapes & Lush Coastal Ferns ('foliage' UV2 wind!)
    sculpt_rock_mass(
        mb, (-2.65, -0.45, 2.25), (1.15, 1.85, 1.08), 'limestone_moss',
        C_LEDGE_MOSS, C_LIME_WARM, C_LIME_DARK, rng,
        subdiv=1, warp=0.18, strata=0.12, base_flare=0.45, rot_deg=(4, 26, -5), moss_cap=0.72,
    )
    for anc, klen, kw, odir, kph in (
        ((-2.55, 1.15, -2.92), 2.15, 0.24, (-0.70, 0.0, -0.70), 0.11),
        (( 3.05, 1.25, -2.92), 2.25, 0.25, ( 0.70, 0.0, -0.70), 0.36),
        ((-3.98, 0.62, -2.15), 1.85, 0.22, (-0.85, 0.0, -0.52), 0.62),
    ):
        _add_kelp_drape(mb, anc, klen, kw, odir, rng, phase=kph, segs=4)
    for fpos, fsc, nf, fph, flean in (
        ((-2.58, 1.08, 2.18), 1.18, 4, 0.16, (-0.7, 0.0, 0.7)),
        (( 2.95, 1.22, 2.38), 1.05, 4, 0.58, ( 0.7, 0.0, 0.7)),
    ):
        _add_jungle_fern_cluster(mb, fpos, scale=fsc, n_fronds=nf, rng=rng, phase=fph, lean_dir=flean)

    build(mb)

    add_empty('Lantern_FishHut', lamp_pos)
    col_piece('col_fishhut_deck', deck_col_pts)
    col_piece('col_fishhut_roof', roof_col_pts)
    export_landmark_glb(outdir, 'tropical_fishing_stilts_hut.glb')


# ================================================================ 4. ANCIENT ASTRONOMER ORRERY RUIN

def _build_beveled_brass_ring(mb, M_ring, radius, width_r, thick_y, segs=14, col_main=C_BRASS, col_edge=C_GOLD_BRIGHT):
    """Chunky beveled metallic armillary ring ('brass') with bright edge bevels & lean tri budget."""
    r0 = radius - width_r * 0.5
    r1 = radius + width_r * 0.5
    hy = thick_y * 0.5
    bev = min(width_r, thick_y) * 0.30
    prof = [
        (r0,        -hy + bev),
        (r0 + bev,  -hy),
        (r1 - bev,  -hy),
        (r1,        -hy + bev),
        (r1,         hy - bev),
        (r1 - bev,   hy),
        (r0 + bev,   hy),
        (r0,         hy - bev),
        (r0,        -hy + bev),
    ]
    with xf(mb, M_ring):
        lathe(mb, prof, segs, 'brass', col_main, smooth=False,
              colfn=lambda i, k: col_edge if i in (1, 3, 5, 7) else col_main)


def _build_crescent_moon(mb, M_moon, radius=0.34, thick=0.075):
    """Sculptural tapered golden crescent moon pointer ('brass') for the celestial orrery."""
    pts = []
    rads = []
    segs = 6
    for i in range(segs + 1):
        t = i / float(segs)
        ang = radians(-118.0 + 236.0 * t)
        pts.append(Vector((cos(ang) * radius, sin(ang) * radius, 0.0)))
        rads.append(max(0.016, thick * sin(t * pi)))
    with xf(mb, M_moon):
        tube(mb, pts, rads, 4, 'brass', C_GOLD_BRIGHT, mode='flat')


def gen_ancient_astronomer_orrery_ruin(outdir):
    """Overgrown circular carved temple-stone cliff observatory platform (~8.8 m diameter, battered
    stepped circular stone plinth sinking cleanly to y = -3.8 m anti-float!).
    Monumental tilting weathered 'brass' celestial armillary orrery (~7.5 m tall) with nested beveled
    golden meridian & ecliptic rings, orbiting gilded planets & crescent moon pointers, glowing
    sapphire-cyan star crystal heart ('skull_glow' + 'Lantern_Orrery' empty!), carved stone star-chart
    lectern pedestal, weathered broken arch columns, and cascading 'foliage' ivy vines (UV2 wind!).
    Target: 3,200-4,200 visual tris, 1 collider (col_orrery_base).
    """
    clear_scene()
    rng = random.Random(SEED + 1511)
    mb = MB('AncientAstronomerOrreryRuin', seed=1511)

    PLINTH_BOT = -3.80
    DECK_Y = 0.74
    INNER_Y = 1.18
    ORRERY_CTR = Vector((0.0, 4.78, 0.0))

    col_pts = []

    # 1. Overgrown Circular Carved Temple-Stone Cliff Observatory Plinth (~8.8 m diameter, to y = -3.80 m!)
    p1_secs = [
        _circ_ring(0.0, PLINTH_BOT, 0.0, 4.92, 4.92, 14, rot0=pi / 14.0),
        _circ_ring(0.0, -1.75,      0.0, 4.66, 4.66, 14, rot0=pi / 14.0),
        _circ_ring(0.0,  0.00,      0.0, 4.46, 4.46, 14, rot0=pi / 14.0),
        _circ_ring(0.0,  DECK_Y,    0.0, 4.38, 4.38, 14, rot0=pi / 14.0),
    ]
    p1_cols = [
        mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.68),
        mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.46),
        mix(C_TEMPLE_MID,  C_LEDGE_MOSS, 0.24),
        C_TEMPLE_HI,
    ]
    _loft_horizontal_masonry(
        mb, p1_secs, 'temple_stone', p1_cols, rng, caps=(True, True),
        top_mat='limestone_moss', top_col=mix(C_TEMPLE_MID, C_LEDGE_MOSS, 0.34),
    )
    for ring in p1_secs:
        col_pts.extend(Vector(p) for p in ring)

    p2_secs = [
        _circ_ring(0.0, DECK_Y - 0.08, 0.0, 3.04, 3.04, 14, rot0=pi / 14.0),
        _circ_ring(0.0, INNER_Y,       0.0, 2.92, 2.92, 14, rot0=pi / 14.0),
    ]
    _loft_horizontal_masonry(
        mb, p2_secs, 'temple_stone', [C_TEMPLE_DARK, C_TEMPLE_HI], rng, caps=(False, True),
        top_mat='temple_stone', top_col=C_TEMPLE_HI,
    )
    col_pts.extend(Vector(p) for p in p2_secs[-1])

    # Ceremonial Seaward Approach Stairs (-Z) grounded cleanly to PLINTH_BOT = -3.80 m!
    _box2(mb, (-1.38, PLINTH_BOT, -4.88), (1.38, 0.22, -4.16), 'temple_stone',
          mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.50), 0.0)
    _box2(mb, (-1.28,  0.14,      -4.74), (1.28, 0.44, -4.12), 'temple_stone', C_TEMPLE_MID, 0.0)
    _box2(mb, (-1.18,  0.38,      -4.46), (1.18, DECK_Y + 0.01, -3.96), 'temple_stone', C_TEMPLE_HI, 0.0)
    _box2(mb, (-1.04,  DECK_Y - 0.04, -3.26), (1.04, DECK_Y + 0.24, -2.78), 'temple_stone', C_TEMPLE_MID, 0.0)
    _box2(mb, (-0.96,  DECK_Y + 0.20, -2.96), (0.96, INNER_Y + 0.01, -2.52), 'temple_stone', C_TEMPLE_HI, 0.0)
    for sx_s in (-1.46, 1.46):
        _box2(mb, (sx_s - 0.24, PLINTH_BOT, -4.84), (sx_s + 0.24, 1.02, -4.02), 'temple_stone',
              mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.30), 0.0)
        cbox(mb, (sx_s, 0.64, -4.86), (0.26, 0.26, 0.04), 'brass', C_GOLD_BRIGHT, 0.0, M=R('Z', 45.0))

    # Inlaid Gleaming 'brass' Celestial Azimuth Rings & Radial Meridian Lines atop Inner Terrace!
    with xf(mb, T(0.0, INNER_Y + 0.028, 0.0)):
        torus(mb, 2.72, 0.052, 14, 4, 'brass', C_TEMPLE_GOLD, False)
        for k in range(8):
            with xf(mb, R('Y', k * 45.0)):
                cbox(mb, (0.0, 0.004, -1.94), (0.095 if k % 2 == 0 else 0.055, 0.032, 1.42),
                     'brass', C_GOLD_BRIGHT if k % 2 == 0 else C_TEMPLE_GOLD, 0.0)

    # 2. Carved Octagonal Orrery Cradle Pedestal & Sweeping Iron-and-Brass Support Cradle (y = 1.18 .. 4.78 m)
    with xf(mb, T(0.0, INNER_Y, 0.0)):
        ped_prof = [
            (0.00, -0.06), (1.42, -0.06), (1.36, 0.24), (1.12, 0.42),
            (0.96,  1.06), (1.22,  1.24), (1.16, 1.32), (0.00, 1.32),
        ]
        lathe(mb, ped_prof, 8, 'temple_stone', C_TEMPLE_MID, smooth=False,
              colfn=lambda i, k: C_TEMPLE_DARK if i in (1, 2) else C_TEMPLE_HI)
        with xf(mb, T(0.0, 1.24, 0.0)):
            torus(mb, 1.22, 0.064, 8, 4, 'brass', C_TEMPLE_GOLD, False)
        cyl(mb, 0.72, 1.30, 1.56, 8, 'iron', C_IRON, False, 0.0, 0.54)
        for k in range(4):
            ang = k * pi * 0.5
            ca, sa = cos(ang), sin(ang)
            cradle_pts = [
                (ca * 0.96, 1.24, sa * 0.96),
                (ca * 1.98, 2.02, sa * 1.98),
                (ca * 2.48, 3.16, sa * 2.48),
                (ca * 2.42, 3.62, sa * 2.42),
            ]
            tube(mb, cradle_pts, [0.13, 0.115, 0.095, 0.082], 4, 'iron',
                 C_IRON if k % 2 == 0 else C_IRON_RUST, mode='flat')
            cbox(mb, (ca * 2.40, 3.60, sa * 2.40), (0.24, 0.22, 0.24), 'brass', C_GOLD_BRIGHT, 0.0)

    # 3. Monumental Tilting Weathered 'brass' Celestial Armillary Orrery (peaking at y ≈ 7.55 m!)
    R_OUT = 2.34
    with xf(mb, T(ORRERY_CTR)):
        _build_beveled_brass_ring(mb, Matrix.Identity(4), R_OUT, 0.24, 0.16, segs=16,
                                  col_main=C_BRASS, col_edge=C_GOLD_BRIGHT)
        for zk in range(8):
            ang = 2.0 * pi * zk / 8.0
            cbox(mb, (cos(ang) * (R_OUT + 0.13), 0.0, sin(ang) * (R_OUT + 0.13)),
                 (0.12, 0.12, 0.12), 'brass', C_GOLD_BRIGHT if zk % 2 == 0 else C_TEMPLE_GOLD,
                 0.0, M=R('Y', -degrees(ang)))

        M_tilt = R('Y', -22.0) @ R('Z', -23.5)
        with xf(mb, M_tilt):
            _build_beveled_brass_ring(mb, M_Y2Z, R_OUT - 0.14, 0.22, 0.15, segs=16,
                                      col_main=C_TEMPLE_GOLD, col_edge=C_GOLD_BRIGHT)
            _build_beveled_brass_ring(mb, M_Y2X, R_OUT - 0.34, 0.16, 0.13, segs=14,
                                      col_main=C_BRASS_DARK, col_edge=C_BRASS)
            _build_beveled_brass_ring(mb, R('X', 26.0) @ R('Y', 18.0), R_OUT - 0.42, 0.15, 0.34, segs=14,
                                      col_main=C_GOLD_BRIGHT, col_edge=C_TEMPLE_GOLD)
            _build_beveled_brass_ring(mb, R('X', -32.0) @ R('Z', 24.0), 1.34, 0.13, 0.11, segs=12,
                                      col_main=C_BRASS, col_edge=C_GOLD_BRIGHT)

            cyl(mb, 0.056, -R_OUT - 0.12, R_OUT + 0.56, 6, 'iron', C_IRON, False, 0.0)
            for py_b in (-R_OUT + 0.12, R_OUT - 0.12):
                with xf(mb, T(0.0, py_b, 0.0)):
                    cyl(mb, 0.16, -0.10, 0.10, 6, 'brass', C_GOLD_BRIGHT, False, 0.0)
            with xf(mb, T(0.0, R_OUT + 0.38, 0.0)):
                cyl(mb, 0.16, -0.06, 0.44, 4, 'brass', C_GOLD_BRIGHT, False, 0.0, 0.015)
                torus(mb, 0.18, 0.036, 6, 4, 'brass', C_TEMPLE_GOLD, False)

            # 1. Ringed Golden Saturn-Planet (upper-port-seaward!)
            sat_pos = Vector((-1.38, 0.82, -1.22))
            _add_beam(mb, Vector((0.0, 0.0, 0.0)), sat_pos, 0.044, 0.044, 'brass', C_TEMPLE_GOLD, 0.0)
            with xf(mb, T(sat_pos)):
                bm = bmesh.new()
                bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.31)
                bm.faces.ensure_lookup_table()
                for f in bm.faces:
                    mb.fp([v.co.copy() for v in f.verts], 'brass', jit(C_GOLD_BRIGHT, rng, 0.04),
                          (1, 0, 0), Vector((0, 0, 0)), smooth=False)
                bm.free()
                with xf(mb, R('X', 28.0) @ R('Z', -18.0)):
                    torus(mb, 0.54, 0.046, 10, 4, 'brass', C_GOLD_BRIGHT, False)

            # 2. Sculpted Golden Crescent Moon Pointer (starboard-seaward!)
            moon_pos = Vector((1.48, 0.44, -1.16))
            _add_beam(mb, Vector((0.0, 0.0, 0.0)), moon_pos, 0.044, 0.044, 'brass', C_TEMPLE_GOLD, 0.0)
            _build_crescent_moon(mb, T(moon_pos) @ R('Y', -24.0) @ R('Z', 24.0), radius=0.46, thick=0.085)

            # 3. Gilded Sun-Orb & Minor Orbital Planetoid!
            for pl_p, pl_r, is_star in (
                (Vector(( 0.88, -0.88,  1.28)), 0.24, True),
                (Vector((-1.10, -0.74,  0.86)), 0.19, False),
            ):
                _add_beam(mb, Vector((0.0, 0.0, 0.0)), pl_p, 0.036, 0.036, 'brass', C_BRASS_DARK, 0.0)
                with xf(mb, T(pl_p)):
                    bm = bmesh.new()
                    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=pl_r)
                    bm.faces.ensure_lookup_table()
                    for f in bm.faces:
                        mb.fp([v.co.copy() for v in f.verts], 'brass',
                              jit(C_GOLD_BRIGHT if is_star else C_BRASS, rng, 0.05),
                              (1, 0, 0), Vector((0, 0, 0)), smooth=False)
                    bm.free()

        # C. Glowing Sapphire-Cyan Star Crystal Heart ('skull_glow') inside Brass Filigree Gimbal!
        with xf(mb, R('Y', 24.0) @ R('X', 18.0)):
            torus(mb, 0.72, 0.042, 8, 4, 'brass', C_GOLD_BRIGHT, False)
        with xf(mb, R('Y', -42.0) @ R('Z', 72.0)):
            torus(mb, 0.64, 0.038, 8, 4, 'brass', C_TEMPLE_GOLD, False)
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.42)
        bm.faces.ensure_lookup_table()
        for f in bm.faces:
            pts = [v.co.copy() for v in f.verts]
            fc = sum(pts, Vector()) / len(pts)
            cc = C_STAR_CORE if fc.y > 0.12 else (C_STAR_DEEP if fc.y < -0.12 else C_STAR_MID)
            mb.fp(pts, 'skull_glow', jit(cc, rng, 0.05), (0, 1, 0), Vector((0, 0, 0)), smooth=False)
        bm.free()
        for dir_v, sp_l, sp_r in (
            (( 0,  1,  0), 0.94, 0.16), (( 0, -1,  0), 0.94, 0.16),
            (( 1,  0,  0), 0.80, 0.14), ((-1,  0,  0), 0.80, 0.14),
            (( 0,  0,  1), 0.80, 0.14), (( 0,  0, -1), 0.80, 0.14),
        ):
            dv = Vector(dir_v)
            rot_sp = Vector((0.0, 1.0, 0.0)).rotation_difference(dv).to_matrix().to_4x4()
            with xf(mb, rot_sp):
                lathe(mb, [(0.0, 0.20), (sp_r, 0.30), (0.0, sp_l)],
                      4, 'skull_glow', C_STAR_CORE if sp_l > 0.85 else C_STAR_MID, smooth=False)

    col_pts.extend([ORRERY_CTR + Vector((-2.4, 2.75, -2.4)), ORRERY_CTR + Vector((2.4, 2.75, 2.4))])

    # 4. Carved Stone Star-Chart Lectern Pedestal on Seaward-Port Observatory Deck (tilted seaward -Z!)
    lec_pos = Vector((-2.35, DECK_Y, -2.25))
    with xf(mb, T(lec_pos) @ R('Y', -32.0)):
        cyl(mb, 0.54, -0.06, 0.22, 6, 'temple_stone', C_TEMPLE_DARK, False, 0.0, 0.44)
        cyl(mb, 0.34,  0.20, 1.14, 6, 'temple_stone', C_TEMPLE_MID,  False, 0.0, 0.30)
        cyl(mb, 0.48,  1.12, 1.28, 6, 'temple_stone', C_TEMPLE_HI,   False, 0.0, 0.52)
        with xf(mb, T(0.0, 1.38, 0.0) @ R('X', -28.0)):
            cbox(mb, (0.0, 0.0, 0.0), (1.12, 0.16, 0.84), 'temple_stone', C_TEMPLE_HI, 0.0)
            cbox(mb, (0.0, 0.09, 0.0), (0.94, 0.04, 0.68), 'basalt', C_BASALT_DARK, 0.0)
            star_pts = [(-0.30, -0.14), (-0.08, 0.16), (0.18, 0.06), (0.34, -0.18), (0.06, -0.20)]
            for si in range(len(star_pts)):
                sx0, sz0 = star_pts[si]
                cbox(mb, (sx0, 0.125, sz0), (0.065, 0.032, 0.065), 'skull_glow', C_STAR_CORE, 0.0, M=R('Y', 45.0))
                if si + 1 < len(star_pts):
                    sx1, sz1 = star_pts[si + 1]
                    _add_beam(mb, (sx0, 0.118, sz0), (sx1, 0.118, sz1), 0.022, 0.022, 'brass', C_GOLD_BRIGHT, 0.0)

    # 5. Weathered Broken Observatory Arch Columns framing the Rear & Flank Arc of the Platform!
    col_angles = (radians(146.0), radians(108.0), radians(64.0), radians(22.0))
    col_heights = (4.95, 5.10, 3.65, 2.45)
    col_tops = []
    for ci, (ang, ch_col) in enumerate(zip(col_angles, col_heights)):
        cx_c = cos(ang) * 3.74
        cz_c = sin(ang) * 3.74
        with xf(mb, T(cx_c, DECK_Y, cz_c)):
            cbox(mb, (0.0, 0.16, 0.0), (1.12, 0.36, 1.12), 'temple_stone', C_TEMPLE_DARK, 0.0, M=R('Y', -degrees(ang)))
            cyl(mb, 0.44, 0.32, ch_col, 8, 'temple_stone' if ci != 2 else 'limestone_moss',
                jit(C_TEMPLE_MID if ci % 2 == 0 else C_TEMPLE_HI, rng, 0.05), False, 0.0, 0.37)
            if ci in (0, 1):
                cbox(mb, (0.0, ch_col + 0.14, 0.0), (1.14, 0.30, 1.14), 'temple_stone', C_TEMPLE_HI, 0.0, M=R('Y', -degrees(ang)))
                with xf(mb, T(0.0, ch_col - 0.12, 0.0)):
                    torus(mb, 0.41, 0.045, 7, 4, 'brass', C_TEMPLE_GOLD, False)
            else:
                sculpt_stone_block(mb, (0.0, ch_col + 0.08, 0.0), (0.76, 0.36, 0.72), 'limestone_moss',
                                   C_TEMPLE_MID, rng, chip=0.06, M=R('Z', 14.0 if ci == 2 else -18.0), moss_col=C_LEDGE_MOSS)
        col_tops.append(Vector((cx_c, DECK_Y + ch_col + 0.25, cz_c)))
        col_pts.append(Vector((cx_c, DECK_Y + ch_col + 0.45, cz_c)))

    p_a0, p_a1 = col_tops[0], col_tops[1]
    arch_mid = 0.5 * (p_a0 + p_a1)
    arch_span = (p_a1 - p_a0).length
    arch_yaw = -degrees(atan2(p_a1.z - p_a0.z, p_a1.x - p_a0.x))
    with xf(mb, T(arch_mid) @ R('Y', arch_yaw)):
        r_in_a = arch_span * 0.42
        r_out_a = r_in_a + 0.64
        n_v = 7
        for vi in range(n_v):
            if vi == 4:
                continue
            a0 = pi * (vi / float(n_v))
            a1 = pi * ((vi + 1) / float(n_v))
            _add_trapezoid_voussoir(
                mb, (0.0, -0.05), a0, a1, r_in_a, r_out_a, 0.42,
                'limestone_moss' if vi in (2, 5) else 'temple_stone',
                C_TEMPLE_HI if vi % 2 == 0 else C_TEMPLE_MID, rng,
            )
    col_pts.append(arch_mid + Vector((0.0, arch_span * 0.42 + 0.65, 0.0)))

    with xf(mb, T(2.86, DECK_Y + 0.36, -1.92) @ R('Y', 34.0) @ R('Z', 90.0)):
        cyl(mb, 0.39, -0.82, 0.82, 7, 'limestone_moss', C_TEMPLE_MID, False, 0.0, 0.37)
    sculpt_stone_block(
        mb, (3.24, DECK_Y + 0.28, -0.78), (0.84, 0.54, 0.68), 'temple_stone', C_TEMPLE_HI, rng,
        chip=0.055, M=R('Y', -24.0) @ R('X', 8.0), moss_col=C_LEDGE_MOSS,
    )

    # 6. Cascading 'foliage' Ivy Vines (UV2 wind!) & Overgrown Cliff Observatory Ferns!
    vine_specs = [
        ((p_a0.x, p_a0.y + 0.15, p_a0.z), 3.45, 0.30, (-0.75, 0.0, -0.65), 0.08),
        ((p_a1.x, p_a1.y + 0.20, p_a1.z), 3.75, 0.32, (-0.25, 0.0, -0.96), 0.24),
        ((col_tops[2].x, col_tops[2].y, col_tops[2].z), 2.85, 0.28, (0.45, 0.0, -0.88), 0.42),
        ((arch_mid.x, arch_mid.y + 1.45, arch_mid.z), 2.55, 0.28, (-0.50, 0.0, -0.86), 0.56),
        ((-4.32, DECK_Y, -0.45), 2.35, 0.30, (-1.00, 0.0, -0.10), 0.70),
        (( 4.32, DECK_Y,  0.55), 2.40, 0.30, ( 1.00, 0.0,  0.14), 0.84),
        (( 0.45, DECK_Y,  4.34), 2.45, 0.30, ( 0.10, 0.0,  0.99), 0.95),
    ]
    for anc, vlen, vw, vdir, vph in vine_specs:
        _add_leafy_vine_drape(mb, anc, vlen, vw, vdir, rng, phase=vph)
    for fpos, fsc, nf, fph, flean in (
        ((-3.55, DECK_Y - 0.04,  1.22), 1.24, 4, 0.14, (-0.8, 0.0,  0.5)),
        (( 3.45, DECK_Y - 0.04,  1.65), 1.18, 4, 0.46, ( 0.8, 0.0,  0.6)),
        ((-3.32, DECK_Y - 0.04, -1.62), 1.05, 4, 0.72, (-0.8, 0.0, -0.6)),
    ):
        _add_jungle_fern_cluster(mb, fpos, scale=fsc, n_fronds=nf, rng=rng, phase=fph, lean_dir=flean)

    build(mb)

    add_empty('Lantern_Orrery', ORRERY_CTR)
    col_piece('col_orrery_base', col_pts)
    export_landmark_glb(outdir, 'ancient_astronomer_orrery_ruin.glb')


WORLD_CRAFT_GENERATORS = [
    gen_careening_ship_drydock,
    gen_cursed_skeleton_throne_shrine,
    gen_tropical_fishing_stilts_hut,
    gen_ancient_astronomer_orrery_ruin,
]
