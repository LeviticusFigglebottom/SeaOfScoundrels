# Sea of Scoundrels: 4 sculpted 3D Upper-Mountain & Cliff-Crown skyline landmarks (Wave I-4).
# Imported by tools/blender/gen_island_landmarks.py.
# Authored in Godot game coordinates (-Z seaward/outward downhill, +Y up, +X starboard, metres)
# and converted to Blender's Z-up frame on mesh creation via _landmark_common.
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
    C_TEMPLE_HI, C_TEMPLE_MID, C_TEMPLE_DARK, C_TEMPLE_GOLD,
    C_TIMBER_HI, C_TIMBER_MID, C_TIMBER_DARK, C_DRIFTWOOD,
    C_PAINT_RED, C_PAINT_TEAL, C_PAINT_CREAM,
    C_ROPE, C_IRON, C_IRON_RUST, C_BRASS, C_LANTERN_GL,
    T, R, S, M_Y2Z, M_Y2X, newell,
    MB, xf,
    cbox, sculpt_stone_block, loft, lathe, tube, cyl, torus, rope_coil,
    build_lantern_geom, sculpt_rock_mass, add_vine_drape,
    clear_scene, build, col_piece, col_box, add_empty, export_landmark_glb,
)


# ---------------------------------------------------------------- local sculptural helpers

def _box2(mb, lo, hi, mat, col, ch=0.0, grain=None, skip=()):
    c = ((lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5, (lo[2] + hi[2]) * 0.5)
    sz = (hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2])
    cbox(mb, c, sz, mat, col, ch, grain, skip=skip)


def _sculpt_stepped_crag(mb, ring_specs, sides, rng, mat='limestone', top_mat=None,
                         col_top=C_LIME_PALE, col_mid=C_LIME_WARM, col_bot=C_LIME_SHADE,
                         rot0=0.0, twist=0.14, rib_amp=0.18, strata_jog=0.10,
                         moss_cap=0.0, apex_pt=None):
    """Multi-ring angular chiseled limestone crag spire / flared summit massif with crisp
    stepped horizontal sedimentary strata jogs and vertical fracture cleavage ribs.
    ring_specs: list of (y, rx, rz, cx, cz).
    """
    n_rings = len(ring_specs)
    rib_j = [1.0 + rib_amp * (0.62 * cos(2.0 * pi * k / sides * 2.0 + 0.5)
                              + rng.uniform(-0.85, 0.85)) for k in range(sides)]
    secs = []
    centers = []
    out_pts = []

    y_lo = ring_specs[0][0]
    y_hi = apex_pt[1] if apex_pt is not None else ring_specs[-1][0]
    y_span = max(y_hi - y_lo, 0.5)
    t_mat = top_mat if top_mat is not None else mat

    for ri, (y, rx, rz, cx, cz) in enumerate(ring_specs):
        t = ri / float(max(1, n_rings - 1))
        centers.append(Vector((cx, y, cz)))
        # Alternating horizontal sedimentary strata terrace step jog
        jog = 1.0 + (strata_jog * (0.75 if ri % 2 == 1 else -0.45) if 0 < ri < n_rings - 1 else 0.0)
        ring = []
        for k in range(sides):
            ang = rot0 + 2.0 * pi * k / float(sides) + twist * t
            rk = rib_j[k] * jog * (1.0 + 0.07 * sin(ang * 3.0 + ri * 1.5))
            px = cx + cos(ang) * rx * rk
            pz = cz + sin(ang) * rz * rk
            py = y + (0.0 if ri == 0 else rng.uniform(-0.20, 0.20))
            v = Vector((px, py, pz))
            ring.append(v)
            out_pts.append(v)
        secs.append(ring)

    def _face_style(pts, inside_pt):
        fn = newell(pts)
        fn = fn.normalized() if fn.length > 1e-8 else Vector((0.0, 1.0, 0.0))
        fc = sum(pts, Vector()) / float(len(pts))
        if fn.dot(fc - inside_pt) < 0.0:
            fn = -fn
        ht = smooth01((fc.y - y_lo) / y_span)
        fmat = mat
        if fn.y > 0.46:
            tc = mix(col_top, C_LEDGE_MOSS, moss_cap) if moss_cap > 0.01 else col_top
            if moss_cap > 0.45 and fn.y > 0.62:
                tc = mix(tc, C_GRASS_SUN, 0.35 * moss_cap)
            base = mix(col_mid, tc, smooth01((fn.y - 0.46) / 0.46))
            if moss_cap > 0.25:
                fmat = t_mat
        elif fn.y < -0.14:
            sh = smooth01((-fn.y - 0.14) / 0.55)
            base = mix(mix(col_bot, col_mid, ht * 0.45), mul(col_bot, 0.72), sh)
        else:
            base = mix(col_bot, col_mid, ht * 0.78 + 0.14)
            if fn.z < -0.32:
                base = mix(base, col_top, 0.22 * ht)
        st_tint = 0.90 + 0.13 * sin(fc.y * 1.30 + fc.x * 0.35)
        return fmat, jit(mul(base, st_tint), rng, 0.048, 0.018)

    mb.newoff()
    for ri in range(n_rings - 1):
        r0, r1 = secs[ri], secs[ri + 1]
        inside = 0.5 * (centers[ri] + centers[ri + 1])
        for k in range(sides):
            kn = (k + 1) % sides
            q = [r0[k], r0[kn], r1[kn], r1[k]]
            fm, fc = _face_style(q, inside)
            mb.fp(q, fm, fc, (1, 0, 0), inside, smooth=False)

    # Bottom cap
    mb.fp(secs[0], mat, mul(col_bot, 0.72), (1, 0, 0), centers[0] + Vector((0.0, 0.9, 0.0)), smooth=False)

    if apex_pt is not None:
        ap = Vector(apex_pt)
        out_pts.append(ap)
        inside_top = centers[-1] - Vector((0.0, 0.75, 0.0))
        for k in range(sides):
            kn = (k + 1) % sides
            tri = [secs[-1][k], secs[-1][kn], ap]
            fm, fc = _face_style(tri, inside_top)
            mb.fp(tri, fm, fc, (1, 0, 0), inside_top, smooth=False)
    else:
        inside_top = centers[-1] - Vector((0.0, 0.75, 0.0))
        fm, fc = _face_style(secs[-1], inside_top)
        mb.fp(secs[-1], fm, fc, (1, 0, 0), inside_top, smooth=False)
    return out_pts


def _sculpt_grounded_terrace(mb, center, radii, mat, col_top, col_mid, col_bot, rng,
                             subdiv=3, warp=0.18, strata=0.18, flat_top=0.44,
                             base_flare=0.34, rot_deg=(0, 0, 0),
                             crag_ribs=6, rib_amp=0.14, moss_cap=0.72):
    """Deep-rooted faceted coastal limestone terrace boulder / highland bench whose lower skirt flares
    wide downward so it welds solidly into the parent crag with ZERO floating underside gaps!
    """
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    ph = [rng.uniform(0.0, 6.28) for _ in range(10)]
    dirs = [
        Vector((0.81, 0.38, 0.45)).normalized(),
        Vector((-0.62, 0.68, 0.39)).normalized(),
        Vector((0.22, -0.52, 0.82)).normalized(),
        Vector((-0.71, -0.34, -0.61)).normalized(),
        Vector((0.35, 0.84, -0.41)).normalized(),
    ]
    X = T(center) @ R('Y', rot_deg[1]) @ R('X', rot_deg[0]) @ R('Z', rot_deg[2])
    out_pts = []
    for v in bm.verts:
        p = v.co.copy()
        n = p.normalized()
        d = 1.0
        for idx, dv in enumerate(dirs):
            d += warp * (0.35 if idx < 3 else 0.22) * sin(n.dot(dv) * (2.8 + idx * 0.6) + ph[idx])
        ang = atan2(p.z, p.x)
        d += rib_amp * (0.65 * cos(ang * crag_ribs + ph[6] + p.y * 0.6) + 0.35 * sin(ang * (crag_ribs + 2) + ph[7]))
        st_phase = p.y * 5.2 + ph[5] + 0.55 * sin(p.x * 2.2 + p.z * 2.0)
        d += strata * (sin(st_phase) + 0.35 * sin(st_phase * 2.0 + 0.7))
        # Strong bottom flare ensures bottom-heavy silhouette (no mushroom undercut!)
        if p.y < 0.15:
            t_b = max(0.0, (0.15 - p.y) / 1.15)
            d += base_flare * (t_b ** 1.35)
        if p.y < -0.68:
            p.y = -0.68 + (p.y + 0.68) * 0.35
        if flat_top > 0.0 and p.y > flat_top:
            p.y = flat_top + (p.y - flat_top) * 0.14
        v.co = Vector((p.x * radii[0] * d, p.y * radii[1] * (0.94 + 0.06 * d), p.z * radii[2] * d))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    mb.newoff()
    with xf(mb, X):
        for f in bm.faces:
            pts = [v.co.copy() for v in f.verts]
            fn = newell(pts)
            if fn.length < 1e-8:
                continue
            fn.normalize()
            fc = sum(pts, Vector()) / len(pts)
            wn = (X.to_3x3() @ fn).normalized()
            h01 = smooth01((fc.y / max(radii[1], 0.1) + 0.85) * 0.56)
            if wn.y > 0.48:
                tc = mix(col_top, C_LEDGE_MOSS, moss_cap) if moss_cap > 0.01 else col_top
                if moss_cap > 0.55 and wn.y > 0.65:
                    tc = mix(tc, C_GRASS_SUN, 0.38)
                base = mix(col_mid, tc, smooth01((wn.y - 0.48) / 0.44))
                fmat = mat
            elif wn.y < -0.18:
                sh = smooth01((-wn.y - 0.18) / 0.55)
                base = mix(mix(col_bot, col_mid, h01 * 0.55), mul(col_bot, 0.74), sh)
                fmat = 'limestone'
            else:
                base = mix(col_bot, col_mid, h01)
                fmat = 'limestone'
            st_tint = 0.90 + 0.13 * sin(fc.y * 1.45 + ph[8])
            mb.fp(pts, fmat, jit(mul(base, st_tint), rng, 0.048, 0.018), (1, 0, 0), inside=None, smooth=False)
            for p in pts:
                out_pts.append(X @ p)
    bm.free()
    return out_pts


def _loft_horizontal_masonry(mb, secs, mat, scols, rng, caps=(True, True)):
    """Emit a vertical tapered ashlar masonry pier shaft with strictly horizontal UV mortar courses."""
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
            face_col = jit(col_i, rng, 0.036, 0.012)
            mb.fp([p00, p01, p11, p10], mat, face_col, grain=horiz, inside=c_mid, smooth=False)
    if caps[0] and n > 1:
        mb.fp(secs[0], mat, mul(scols[0], 0.78), (1, 0, 0), cents[1], smooth=False)
    if caps[1] and n > 1:
        mb.fp(secs[-1], mat, scols[-1], (1, 0, 0), cents[-2], smooth=False)


def _add_trapezoid_voussoir(mb, center_xy, ang0, ang1, r_in, r_out, half_z, mat, col, rng):
    """Crisp lightweight 6-face chiseled radial stone arch voussoir wedge (12 tris each!)."""
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
    ctr = Vector((cx + cos(am) * rm, cy + sin(am) * rm, 0.0))
    tang_grain = Vector((-sin(am), cos(am), 0.0))

    r_f = [Vector((x, y, -half_z)) for x, y in m_pts2]
    r_b = [Vector((x, y,  half_z)) for x, y in m_pts2]

    mb.newoff()
    c_main = jit(col, rng, 0.045, 0.015)
    mb.fp(r_f, mat, c_main, tang_grain, ctr, smooth=False)
    mb.fp(list(reversed(r_b)), mat, c_main, tang_grain, ctr, smooth=False)
    for k in range(4):
        kn = (k + 1) % 4
        q = [r_f[k], r_f[kn], r_b[kn], r_b[k]]
        qc = mul(c_main, 0.74) if k == 0 else (mul(c_main, 1.05) if k == 2 else mul(c_main, 0.90))
        mb.fp(q, mat, qc, tang_grain, ctr, smooth=False)


def _add_sun_compass_medallion(mb, center, facing_z_sgn, rng, scale=1.0):
    """Lightweight carved tarnished antique-gold sun-compass keystone medallion (~156 tris each)."""
    cx, cy, cz = center
    s = scale
    rot_y = 0.0 if facing_z_sgn < 0 else 180.0
    with xf(mb, T(cx, cy, cz) @ R('Y', rot_y)):
        # Dark carved temple stone circular recess bezel (8-sided)
        with xf(mb, M_Y2Z):
            cyl(mb, 0.62 * s, -0.065 * s, 0.14 * s, 8, 'temple_stone', C_TEMPLE_DARK, False, 0.0)
        # Outer forged antique-gold compass ring (8x4 torus = 64 tris)
        with xf(mb, T(0.0, 0.0, -0.065 * s) @ M_Y2Z):
            torus(mb, 0.50 * s, 0.055 * s, 8, 4, 'brass', C_TEMPLE_GOLD, False)
        # 8 sharp faceted compass-rose starburst rays (4 long cardinal + 4 intercardinal)
        for k in range(8):
            is_card = (k % 2 == 0)
            r_len = (0.58 if is_card else 0.42) * s
            r_w = (0.092 if is_card else 0.062) * s
            col_r = C_TEMPLE_GOLD if is_card else C_BRASS
            with xf(mb, R('Z', k * 45.0)):
                p_in = Vector((0.0, 0.06 * s, -0.072 * s))
                p_l  = Vector((-r_w, r_len * 0.35, -0.070 * s))
                p_t  = Vector((0.0, r_len, -0.068 * s))
                p_r  = Vector(( r_w, r_len * 0.35, -0.070 * s))
                apex = Vector((0.0, r_len * 0.35, -0.132 * s))
                in_ref = Vector((0.0, r_len * 0.35, 0.25 * s))
                mb.fp([p_in, p_l, p_t, apex], 'brass', jit(col_r, rng, 0.04), (0, 1, 0), in_ref, smooth=False)
                mb.fp([p_t, p_r, p_in, apex], 'brass', jit(mul(col_r, 0.90), rng, 0.04), (0, 1, 0), in_ref, smooth=False)
        # Raised central golden sun boss (6-sided cone-frustum = 24 tris)
        with xf(mb, T(0.0, 0.0, -0.075 * s) @ M_Y2Z):
            cyl(mb, 0.18 * s, -0.03 * s, 0.08 * s, 6, 'brass', C_BRASS, False, 0.0, 0.09 * s)


def _build_double_sided_pennant(mb, root_pos, length=2.45, h0=0.72, out_dir=(0.48, 0.0, -0.88),
                                col_main=C_PAINT_RED, col_trim=C_PAINT_CREAM, tattered=True):
    """Fluttering 3D double-sided swallowtail crimson pirate pennant (100% backface-cull safe!)."""
    rp = Vector(root_pos)
    od = Vector(out_dir).normalized()
    side = Vector((-od.z, 0.0, od.x))
    if side.length < 1e-4:
        side = Vector((1.0, 0.0, 0.0))
    side.normalize()
    segs = 6
    thick = 0.014

    top_pts = []
    bot_pts = []
    for i in range(segs + 1):
        t = i / float(segs)
        wave = sin(t * 2.20 * pi) * 0.22 * t + 0.05 * sin(t * 4.4)
        droop = -0.26 * t * t
        hh = h0 * (1.0 - 0.50 * t)
        if tattered and i in (3, 4):
            hh *= 0.88
        ctr = rp + od * (length * t) + side * wave + Vector((0.0, droop, 0.0))
        top_pts.append(ctr + Vector((0.0, hh * 0.5, 0.0)))
        bot_pts.append(ctr - Vector((0.0, hh * 0.5, 0.0)))

    for i in range(segs):
        c_seg = col_trim if i == 0 else mul(col_main, 0.90 + 0.10 * ((i + 1) % 2))
        t0, t1 = top_pts[i], top_pts[i + 1]
        b0, b1 = bot_pts[i], bot_pts[i + 1]
        if i == segs - 1:
            mid_notch = (t0 + b0) * 0.28 + (t1 + b1) * 0.22 - od * (length * 0.14)
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
                mb.fp(b_pts, 'paint', mul(c_seg, 0.86), od, ctr_tri + side * 1.0, smooth=False)
        else:
            q_f = [t0 + side * thick, t1 + side * thick, b1 + side * thick, b0 + side * thick]
            q_b = [t1 - side * thick, t0 - side * thick, b0 - side * thick, b1 - side * thick]
            ctr_q = (t0 + t1 + b0 + b1) * 0.25
            mb.fp(q_f, 'paint', c_seg, od, ctr_q - side * 1.0, smooth=False)
            mb.fp(q_b, 'paint', mul(c_seg, 0.86), od, ctr_q + side * 1.0, smooth=False)
            mb.fp([t0 - side * thick, t1 - side * thick, t1 + side * thick, t0 + side * thick],
                  'paint', mul(c_seg, 0.80), od, ctr_q, smooth=False)
            mb.fp([b0 + side * thick, b1 + side * thick, b1 - side * thick, b0 - side * thick],
                  'paint', mul(c_seg, 0.76), od, ctr_q, smooth=False)


def _add_beam(mb, p0, p1, w, h, mat, col, ch=0.0):
    """Emit a crisp timber beam connecting arbitrary 3D points p0 and p1."""
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


def _add_chain_links(mb, p_top, p_bot, n_links, link_r=0.044, wire_r=0.013):
    """Alternating 90-degree hammered wrought-iron chain links between p_top and p_bot."""
    a = Vector(p_top)
    b = Vector(p_bot)
    seg_v = b - a
    if seg_v.length < 1e-5 or n_links < 1:
        return
    rot_q = Vector((0, 1, 0)).rotation_difference(seg_v.normalized()).to_matrix().to_4x4()
    for k in range(n_links):
        pt = a.lerp(b, (k + 0.5) / float(n_links))
        spin = R('Y', 90.0 if (k % 2 == 0) else 0.0)
        col = C_IRON_RUST if (k % 3 == 0) else C_IRON
        with xf(mb, T(pt) @ rot_q @ spin @ S(0.76, 1.18, 0.76) @ M_Y2Z):
            torus(mb, link_r, wire_r, 6, 4, 'iron', col, False)


def _sculpt_strata_plate(mb, y_bot, y_top, x_half, z_front, z_back, rng,
                         mat='limestone', top_mat='limestone_moss',
                         moss_top=0.72, n_front=11, jag_x=0.45, jag_z=0.58,
                         brow_step=0.28, x_shift=0.0, crest_lift=0.0):
    """Closed rugged jagged sedimentary limestone strata slab with strictly receding front & tapered
    organic rocky flanks (ZERO forward overhang, ZERO boxy corners!), deep mountain-embedding back
    wedge anchored solidly at z_back, and mossy top shelf rim. Guaranteed outward normals via bmesh.
    """
    perim_base = []
    # Jagged sweeping organic front contour curving naturally back toward both mountain flanks
    for i in range(n_front):
        u = i / float(n_front - 1)
        s = u * 2.0 - 1.0  # -1..+1
        # Organic rounded-crag sweep: flanks recede smoothly toward mountain wall (no 90° box corners!)
        arch_back = (s * s) * min(3.4, (z_back - z_front) * 0.44)
        px = x_shift + s * x_half + (0.0 if i in (0, n_front - 1) else rng.uniform(-jag_x, jag_x))
        # Natural coastal fracture crenellation along the front strata brow
        jag_wave = 0.42 * sin(s * pi * 2.5 + y_bot * 0.4) + rng.uniform(-jag_z * 0.42, jag_z * 0.58)
        pz = z_front + arch_back + jag_wave
        pz = max(z_front - 0.28, min(z_back - 1.2, pz))
        perim_base.append((px, pz))

    # Tapered organic flanks sweeping cleanly into the solid rear mountain-embedding wedge at z_back!
    z_flank_r = 0.5 * (perim_base[-1][1] + z_back)
    z_flank_l = 0.5 * (perim_base[0][1] + z_back)
    perim_base.append((x_shift + x_half * 0.90, z_flank_r))
    perim_base.append((x_shift + x_half * 0.72, z_back))
    perim_base.append((x_shift,                 z_back + 0.14))
    perim_base.append((x_shift - x_half * 0.72, z_back))
    perim_base.append((x_shift - x_half * 0.90, z_flank_l))

    k_n = len(perim_base)
    h = y_top - y_bot
    # 5 vertical rings -> crisp geological cleavage contours + strictly monotonic +Z retreat!
    ring_cfgs = [
        (y_bot,               1.06, -0.02, 0.00),
        (y_bot + h * 0.34,    1.02,  brow_step * 0.32, 0.07),
        (y_bot + h * 0.70,    0.97,  brow_step * 0.68, 0.08),
        (y_top - h * 0.10,    0.92,  brow_step * 1.05, 0.05),
        (y_top,               0.82,  brow_step * 1.55, 0.04),
    ]

    bm = bmesh.new()
    bm_rings = []
    out_pts = []
    for ri, (yl, xmul, z_retreat, y_jit) in enumerate(ring_cfgs):
        rverts = []
        for idx, (bx, bz) in enumerate(perim_base):
            is_back = (idx >= n_front + 1 and idx <= n_front + 3)
            if is_back:
                px = x_shift + (bx - x_shift) * (0.94 if ri == 4 else 1.0)
                pz = bz  # Solid back wedge anchored at z = +8.5 m from bottom to top!
            else:
                px = x_shift + (bx - x_shift) * xmul
                pz = min(z_back - 0.45, bz + z_retreat)
            py = yl
            if ri in (1, 2, 3):
                py += rng.uniform(-y_jit, y_jit) * h
            elif ri == 4:
                # Subtle organic undulating strata shelf height
                u_c = 1.0 - min(1.0, abs(bx - x_shift) / max(x_half, 0.5))
                py += 0.16 * sin((bx - x_shift) * 0.7 + y_top)
                if crest_lift > 0.0:
                    py += crest_lift * (0.35 + 0.65 * u_c) * rng.uniform(0.70, 1.15)
            v = bm.verts.new((px, py, pz))
            rverts.append(v)
            out_pts.append(Vector((px, py, pz)))
        bm_rings.append(rverts)

    for ri in range(len(bm_rings) - 1):
        r0, r1 = bm_rings[ri], bm_rings[ri + 1]
        for k in range(k_n):
            kn = (k + 1) % k_n
            try:
                bm.faces.new((r0[k], r0[kn], r1[kn], r1[k]))
            except ValueError:
                pass

    c_bot = sum((v.co for v in bm_rings[0]), Vector()) / float(k_n)
    v_cbot = bm.verts.new(c_bot)
    for k in range(k_n):
        kn = (k + 1) % k_n
        try:
            bm.faces.new((v_cbot, bm_rings[0][kn], bm_rings[0][k]))
        except ValueError:
            pass

    c_top = sum((v.co for v in bm_rings[-1]), Vector()) / float(k_n)
    if crest_lift > 0.0:
        c_top.y += crest_lift * 0.55
    v_ctop = bm.verts.new(c_top)
    for k in range(k_n):
        kn = (k + 1) % k_n
        try:
            bm.faces.new((v_ctop, bm_rings[-1][k], bm_rings[-1][kn]))
        except ValueError:
            pass

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    mb.newoff()

    for f in bm.faces:
        pts = [v.co.copy() for v in f.verts]
        fn = newell(pts)
        if fn.length < 1e-8:
            continue
        fn.normalize()
        fc = sum(pts, Vector()) / float(len(pts))
        ht = smooth01((fc.y - y_bot) / max(h, 0.2))
        if fn.y > 0.44:
            tc = mix(C_LIME_PALE, C_LEDGE_MOSS, moss_top)
            if moss_top > 0.62:
                tc = mix(tc, C_GRASS_SUN, 0.36 * smooth01((fn.y - 0.55) / 0.42))
            base = mix(C_LIME_WARM, tc, smooth01((fn.y - 0.44) / 0.46))
            fmat = top_mat
        elif fn.y < -0.25:
            base = mul(C_LIME_SHADE, 0.76)
            fmat = mat
        else:
            base = mix(C_LIME_SHADE, C_LIME_WARM, 0.26 + 0.64 * ht)
            if fn.z < -0.35:
                base = mix(base, C_LIME_PALE, 0.26 * ht)
            fmat = mat
        st_tint = 0.90 + 0.13 * sin(fc.y * 1.55 + fc.x * 0.4)
        mb.fp(pts, fmat, jit(mul(base, st_tint), rng, 0.048, 0.018), (1, 0, 0), inside=None, smooth=False)

    bm.free()
    return out_pts


# ================================================================ 1. CLIFF SUMMIT CRAG SPIRE

def gen_cliff_summit_crag_spire(outdir):
    """Monumental ~22.5 m tall, ~18.5 m wide asymmetric jagged stepped coastal-limestone mountain
    summit crown & twin fractured rocky pinnacles designed to cap rounded 35°-45° mountain domes.
    Massive flared base skirt plunges solidly to y = -7.5 m (r = 8.5..9.5 m) for ZERO edge gaps!
    Target: 1,400–2,400 visual tris.
    """
    clear_scene()
    rng = random.Random(SEED + 911)
    mb = MB('CliffSummitCragSpire', seed=911)
    base_pts = []
    crown_pts = []

    # 1. Massive Unified Flared Summit Skirt Massif (y = -7.5 .. +5.6 m, r = 8.9..9.4 m at foot!)
    #    Steps inward in 4 rugged horizontal sedimentary strata ledges so it buries into 35°-45° domes.
    skirt_rings = [
        (-7.50, 9.35, 8.95,  0.00,  0.00),
        (-4.80, 8.65, 8.20, -0.08,  0.06),
        (-2.20, 7.65, 7.15, -0.15,  0.10),
        ( 0.25, 6.75, 6.10, -0.18,  0.05),
        ( 2.25, 5.85, 5.20, -0.10,  0.00),
        ( 4.10, 4.95, 4.25,  0.05, -0.05),
        ( 5.55, 4.10, 3.35,  0.25, -0.10),
    ]
    base_pts += _sculpt_stepped_crag(
        mb, skirt_rings, sides=9, rng=rng, mat='limestone', top_mat='limestone_moss',
        col_top=C_LIME_PALE, col_mid=C_LIME_WARM, col_bot=C_LIME_SHADE,
        rot0=0.22, twist=0.14, rib_amp=0.16, strata_jog=0.11, moss_cap=0.52,
    )

    # 2. Four Deep-Plunging Radial Skirt Buttress Spurs (all root solidly to y = -7.5 m around r = 8.6..9.4 m!)
    spur_specs = [
        [
            (-7.50, 4.05, 3.80, -4.95, -4.25),
            (-4.20, 3.55, 3.35, -4.55, -3.85),
            (-1.10, 3.00, 2.80, -4.05, -3.20),
            ( 1.65, 2.25, 2.10, -3.45, -2.55),
            ( 3.85, 1.35, 1.25, -2.90, -1.85),
        ],
        [
            (-7.50, 4.10, 3.80,  5.05, -4.05),
            (-4.10, 3.55, 3.30,  4.65, -3.55),
            (-0.90, 2.95, 2.75,  4.25, -2.85),
            ( 1.95, 2.35, 2.15,  3.85, -2.05),
            ( 4.35, 1.55, 1.40,  3.50, -1.35),
        ],
        [
            (-7.50, 4.20, 4.00, -4.80,  4.40),
            (-4.15, 3.65, 3.50, -4.30,  3.85),
            (-0.95, 3.05, 2.90, -3.65,  3.15),
            ( 2.10, 2.45, 2.30, -3.05,  2.35),
            ( 5.10, 1.65, 1.55, -2.50,  1.50),
        ],
        [
            (-7.50, 4.15, 3.95,  4.95,  4.20),
            (-4.00, 3.60, 3.40,  4.45,  3.65),
            (-0.75, 2.95, 2.80,  3.85,  2.95),
            ( 2.35, 2.30, 2.15,  3.25,  2.15),
            ( 5.35, 1.45, 1.35,  2.65,  1.45),
        ],
    ]
    for si, sp_rings in enumerate(spur_specs):
        pts = _sculpt_stepped_crag(
            mb, sp_rings, sides=6, rng=rng, mat='limestone', top_mat='limestone_moss',
            col_top=C_LIME_PALE, col_mid=C_LIME_WARM, col_bot=C_LIME_SHADE,
            rot0=0.45 * si, twist=0.12 if si % 2 == 0 else -0.12, rib_amp=0.17,
            strata_jog=0.10, moss_cap=0.45,
            apex_pt=(sp_rings[-1][3] * 0.86, sp_rings[-1][0] + 1.05, sp_rings[-1][4] * 0.86),
        )
        base_pts.extend(pts)

    # 3. HERO TALL MAIN CRAG PINNACLE (jagged stepped wind-carved limestone fang peaking at y = +15.05 m!)
    main_fang_rings = [
        ( 1.20, 4.25, 3.65, -2.45,  0.45),
        ( 3.60, 3.85, 3.25, -2.40,  0.38),
        ( 5.80, 3.15, 2.70, -2.25,  0.26),  # stepped strata notch 1
        ( 7.60, 2.95, 2.55, -2.15,  0.18),  # bold limestone ledge collar
        ( 9.55, 2.25, 1.95, -2.00,  0.04),  # stepped strata notch 2
        (11.35, 1.85, 1.55, -1.86, -0.08),
        (13.10, 1.12, 0.94, -1.72, -0.22),
        (14.35, 0.56, 0.44, -1.64, -0.30),
    ]
    crown_pts += _sculpt_stepped_crag(
        mb, main_fang_rings, sides=8, rng=rng, mat='limestone', top_mat='limestone_moss',
        col_top=C_LIME_PALE, col_mid=C_LIME_WARM, col_bot=C_LIME_MID,
        rot0=0.18, twist=0.22, rib_amp=0.20, strata_jog=0.12, moss_cap=0.32,
        apex_pt=(-1.58, 15.08, -0.34),
    )

    # Secondary jagged fractured crag blade fused to main fang's port shoulder (peaks at y ~ 11.6 m)
    blade_rings = [
        ( 1.80, 2.55, 2.15, -4.25, -0.85),
        ( 4.60, 2.15, 1.80, -4.05, -0.75),
        ( 7.10, 1.65, 1.38, -3.75, -0.58),
        ( 9.40, 1.12, 0.92, -3.38, -0.42),
        (10.85, 0.58, 0.48, -3.15, -0.35),
    ]
    crown_pts += _sculpt_stepped_crag(
        mb, blade_rings, sides=6, rng=rng, mat='limestone', top_mat='limestone_moss',
        col_top=C_LIME_PALE, col_mid=C_LIME_WARM, col_bot=C_LIME_SHADE,
        rot0=0.82, twist=-0.18, rib_amp=0.19, strata_jog=0.11, moss_cap=0.38,
        apex_pt=(-3.05, 11.60, -0.30),
    )

    # 4. SHORTER FLANKING SHOULDER HORN (wind-carved twin pinnacle separated by saddle, peaks at y = +10.65 m!)
    horn_rings = [
        ( 1.00, 3.40, 2.95,  3.85, -0.60),
        ( 3.20, 2.90, 2.50,  3.98, -0.68),
        ( 5.30, 2.25, 1.95,  4.12, -0.76),  # stepped notch
        ( 6.90, 1.95, 1.68,  4.25, -0.82),
        ( 8.55, 1.25, 1.08,  4.40, -0.90),
        ( 9.80, 0.62, 0.54,  4.52, -0.98),
    ]
    crown_pts += _sculpt_stepped_crag(
        mb, horn_rings, sides=7, rng=rng, mat='limestone', top_mat='limestone_moss',
        col_top=C_LIME_PALE, col_mid=C_LIME_WARM, col_bot=C_LIME_MID,
        rot0=-0.35, twist=-0.24, rib_amp=0.20, strata_jog=0.12, moss_cap=0.35,
        apex_pt=(4.64, 10.65, -1.04),
    )

    # 5. Grounded Integrated Stepped Sedimentary Strata Benches & Mossy Highland Turf Caps ('limestone_moss')
    #    Every terrace plunges deeply downward with broad flared rock roots -> ZERO floating pancake undersides!
    # Bench 1: Massive lower seaward stepped limestone bastion with mossy highland turf top (y = -5.5..+2.2 m)
    base_pts += _sculpt_grounded_terrace(
        mb, (-1.85, -1.45, -4.35), (3.45, 4.35, 2.65), 'limestone_moss',
        C_GRASS_SUN, C_LIME_PALE, C_LIME_SHADE, rng,
        subdiv=3, warp=0.18, strata=0.18, flat_top=0.52, base_flare=0.36,
        rot_deg=(-4, 14, -3), crag_ribs=6, rib_amp=0.14, moss_cap=0.78,
    )
    # Bench 2: Mid starboard terraced shoulder bastion welding under the shoulder horn (y = -2.2..+4.1 m)
    base_pts += _sculpt_grounded_terrace(
        mb, (4.35, 0.65, -2.55), (2.75, 3.95, 2.45), 'limestone_moss',
        C_GRASS_SUN, C_LIME_PALE, C_LIME_WARM, rng,
        subdiv=3, warp=0.17, strata=0.17, flat_top=0.52, base_flare=0.34,
        rot_deg=(-4, -18, 4), crag_ribs=5, rib_amp=0.14, moss_cap=0.80,
    )
    # Bench 3: Wind-carved saddle mossy highland turf terrace bridging between the twin fangs (y = +2.8..+5.9 m)
    crown_pts += _sculpt_grounded_terrace(
        mb, (0.95, 4.15, -0.30), (2.75, 2.15, 2.65), 'limestone_moss',
        C_GRASS_SUN, C_LEDGE_MOSS, C_LIME_WARM, rng,
        subdiv=2, warp=0.16, strata=0.14, flat_top=0.46, base_flare=0.28,
        rot_deg=(-3, 8, -2), crag_ribs=5, rib_amp=0.11, moss_cap=0.88,
    )
    # Bench 4: High fractured strata shoulder shelf welded into the main crag spire (y = +4.8..+8.4 m)
    crown_pts += _sculpt_grounded_terrace(
        mb, (-3.35, 6.25, -0.55), (2.15, 2.45, 1.95), 'limestone_moss',
        C_GRASS_SUN, C_LIME_PALE, C_LIME_WARM, rng,
        subdiv=2, warp=0.17, strata=0.16, flat_top=0.48, base_flare=0.32,
        rot_deg=(-5, -14, 4), crag_ribs=5, rib_amp=0.13, moss_cap=0.82,
    )
    # Bench 5: Rear (+Z) broad highland flank terrace so 360° mountain silhouette stays craggy & stepped!
    base_pts += _sculpt_grounded_terrace(
        mb, (0.65, 0.25, 4.15), (3.65, 4.45, 2.55), 'limestone_moss',
        C_LEDGE_MOSS, C_LIME_WARM, C_LIME_SHADE, rng,
        subdiv=2, warp=0.18, strata=0.18, flat_top=0.50, base_flare=0.34,
        rot_deg=(4, 168, 3), crag_ribs=6, rib_amp=0.13, moss_cap=0.72,
    )
    # Jagged port-flank lower cliff buttress shoulder adding extra angular limestone relief
    base_pts += _sculpt_grounded_terrace(
        mb, (-5.45, -1.85, -0.85), (2.55, 4.15, 2.45), 'limestone_moss',
        C_LEDGE_MOSS, C_LIME_WARM, C_LIME_SHADE, rng,
        subdiv=2, warp=0.20, strata=0.18, flat_top=0.48, base_flare=0.34,
        rot_deg=(3, -72, 5), crag_ribs=5, rib_amp=0.15, moss_cap=0.66,
    )

    # 6. Three Hardy Cliffside Hanging Vines anchored cleanly OUTSIDE the mossy bench lips (UV2 wind!)
    add_vine_drape(mb, (-1.85, 1.45, -7.12), 3.45, 0.42, (-0.15, 0.0, -1.0), rng, phase=0.14)
    add_vine_drape(mb, ( 0.95, 5.25, -2.95), 3.15, 0.38, ( 0.08, 0.0, -1.0), rng, phase=0.49)
    add_vine_drape(mb, ( 4.85, 3.15, -4.95), 2.95, 0.36, ( 0.36, 0.0, -0.93), rng, phase=0.82)

    build(mb)

    col_piece('col_summit_base', base_pts)
    col_piece('col_summit_crown', crown_pts)
    export_landmark_glb(outdir, 'cliff_summit_crag_spire.glb')


# ================================================================ 2. CLIFF RUIN AQUEDUCT ARCH

def gen_cliff_ruin_aqueduct_arch(outdir):
    """Dramatic ~18.5 m wide (x = -9.2..+9.2 m), ~14.0 m tall overgrown ancient ruined stone
    cliffside aqueduct / temple viaduct with 3 deep-plunging battered piers (y = -5.5 m),
    TWO soaring semicircular stepped voussoir stone arches (~4.8 m clear width, y = 6.2..9.8 m),
    elevated broken stone water-trough parapet (y = 10.6..12.2 m) crumbling into staggered jagged
    ruined stone teeth on the +X end, golden sun-compass keystone medallions & 6 cascading vines.
    Target: 2,600–4,200 visual tris.
    """
    clear_scene()
    rng = random.Random(SEED + 941)
    mb = MB('CliffRuinAqueductArch', seed=941)

    PIER_BOT = -5.50
    IMPOST_Y0 = 6.20
    SPRING_Y = 6.80
    R_IN = 2.40          # ~4.80 m clear archway opening!
    R_OUT = 3.12         # stepped voussoir outer radius (peaks at y = 6.80 + 3.12 = 9.92 m!)
    DECK_Y0 = 10.14
    DECK_Y1 = 10.62

    pier_xs = (-7.35, 0.00, 7.35)
    arch_xs = (-3.675, 3.675)

    # 1. Three Chunky Battered Ashlar Masonry Piers plunging deeply to y = -5.5 m!
    pier_col_pts = {0: [], 1: [], 2: []}

    def rect_oct(cx, y, hx, hz, ch=0.18):
        return [
            (cx - hx + ch, y, -hz),
            (cx + hx - ch, y, -hz),
            (cx + hx,      y, -hz + ch),
            (cx + hx,      y,  hz - ch),
            (cx + hx - ch, y,  hz),
            (cx - hx + ch, y,  hz),
            (cx - hx,      y,  hz - ch),
            (cx - hx,      y, -hz + ch),
        ]

    for pi_idx, px in enumerate(pier_xs):
        hx_bot = 1.78 if pi_idx != 1 else 1.72
        hz_bot = 1.92
        hx_top = 1.22
        hz_top = 1.32

        secs = [
            rect_oct(px, PIER_BOT, hx_bot, hz_bot, 0.16),
            rect_oct(px, -2.00,    hx_bot * 0.90, hz_bot * 0.90, 0.15),
            rect_oct(px,  0.50,    hx_bot * 0.80, hz_bot * 0.82, 0.14),
            rect_oct(px,  3.20,    hx_top * 1.08, hz_top * 1.08, 0.14),
            rect_oct(px,  IMPOST_Y0, hx_top,      hz_top,        0.13),
        ]
        scols = [
            mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.42),
            mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.30),
            mix(C_TEMPLE_MID,  C_SEA_MOSS, 0.18),
            C_TEMPLE_MID,
            C_TEMPLE_HI,
        ]
        _loft_horizontal_masonry(mb, secs, 'temple_stone', scols, rng, caps=(True, True))
        for ring in secs:
            pier_col_pts[pi_idx].extend(Vector(p) for p in ring)

        # Mid-pier stepped ashlar string-course molding (ch=0.0 -> 12 tris, crisp with PBR normal map!)
        cbox(mb, (px, 3.12, 0.0), (hx_top * 2.34, 0.34, hz_top * 2.34),
             'temple_stone', C_TEMPLE_HI, 0.0, (1, 0, 0))
        # Subtle weathered recessed temple pilaster panels on seaward (-Z) and landward (+Z) faces
        panel_col = mix(C_TEMPLE_DARK, C_TEMPLE_MID, 0.48)
        for sz_s in (-1.0, 1.0):
            cbox(mb, (px, 1.55, sz_s * (hz_top * 1.14)), (hx_top * 1.10, 2.30, 0.14),
                 'temple_stone', panel_col, 0.0, (1, 0, 0))
            cbox(mb, (px, 4.68, sz_s * (hz_top * 1.02)), (hx_top * 1.02, 2.10, 0.12),
                 'temple_stone', panel_col, 0.0, (1, 0, 0))

        # Heavy overhanging carved stone impost capital at arch springline (y = 6.20 .. 6.84 m)
        cbox(mb, (px, 6.38, 0.0), (hx_top * 2.30, 0.36, hz_top * 2.24),
             'temple_stone', C_TEMPLE_MID, 0.0, (1, 0, 0))
        cbox(mb, (px, 6.68, 0.0), (hx_top * 2.52, 0.30, hz_top * 2.42),
             'temple_stone', C_TEMPLE_HI, 0.0, (1, 0, 0))
        if pi_idx == 1:
            for sz_s in (-1.0, 1.0):
                cbox(mb, (px, 6.68, sz_s * (hz_top * 1.22)), (1.95, 0.10, 0.05),
                     'brass', C_TEMPLE_GOLD, 0.0)

        # Weathered corner quoin blocks gripping pier base near ground line (y ~ 0.35 m)
        for sx_q in (-1.0, 1.0):
            for sz_q in (-1.0, 1.0):
                cbox(mb, (px + sx_q * (hx_bot * 0.72), 0.35 + rng.uniform(-0.14, 0.14), sz_q * (hz_bot * 0.72)),
                     (0.76, 0.80, 0.72), 'temple_stone',
                     jit(mix(C_TEMPLE_MID, C_LEDGE_MOSS, 0.22), rng, 0.05), 0.0, (1, 0, 0))

    # 2. TWO Soaring Semicircular Stepped Voussoir Stone Arches (~4.8 m clear width, y = 6.2..9.95 m!)
    n_vous = 11
    for ax in arch_xs:
        for vi in range(n_vous):
            ang0 = pi * (vi / float(n_vous))
            ang1 = pi * ((vi + 1) / float(n_vous))
            is_key = (vi == n_vous // 2)
            if is_key:
                ro = R_OUT + 0.24
                ri_v = R_IN - 0.06
                hz_v = 1.44
                vcol = C_TEMPLE_HI
            else:
                step_r = 0.09 if (vi % 2 == 0) else -0.04
                ro = R_OUT + step_r
                ri_v = R_IN
                hz_v = 1.36 if (vi % 2 == 0) else 1.28
                vcol = C_TEMPLE_HI if (vi % 2 == 0) else C_TEMPLE_MID
            _add_trapezoid_voussoir(mb, (ax, SPRING_Y), ang0, ang1, ri_v, ro, hz_v, 'temple_stone', vcol, rng)

        # 3. Carved Golden Sun-Compass Keystone Medallions ('brass') on BOTH -Z & +Z faces!
        med_y = SPRING_Y + 0.5 * (R_IN + R_OUT) + 0.06  # y ≈ 9.62 m
        _add_sun_compass_medallion(mb, (ax, med_y, -1.43), -1.0, rng, scale=1.04)
        _add_sun_compass_medallion(mb, (ax, med_y,  1.43),  1.0, rng, scale=0.98)

    # 4. Solid Gap-Free Ashlar Spandrel Walls filling above piers & arch extrados up to DECK_Y0!
    #    Mathematically exact curved spandrel quads anchored at r = 2.74 m (strictly OUTSIDE R_IN = 2.40 m
    #    and cleanly INSIDE R_OUT = 3.12 m voussoirs) -> ZERO arch intrusion AND ZERO crown shadow slits!
    _box2(mb, (-8.80, SPRING_Y, -1.26), (-6.08, DECK_Y0 + 0.06, 1.26), 'temple_stone', C_TEMPLE_MID, 0.0, (1, 0, 0))
    _box2(mb, (-1.26, SPRING_Y, -1.26), ( 1.26, DECK_Y0 + 0.06, 1.26), 'temple_stone', C_TEMPLE_MID, 0.0, (1, 0, 0))
    _box2(mb, ( 6.08, SPRING_Y, -1.26), ( 8.48, DECK_Y0 + 0.04, 1.26), 'temple_stone', C_TEMPLE_MID, 0.0, (1, 0, 0))

    r_sp = 2.74
    hz_sp = 1.245
    y_sp_top = DECK_Y0 + 0.06
    n_sp = 8
    for ax in arch_xs:
        for si in range(n_sp):
            a0 = pi * (si / float(n_sp))
            a1 = pi * ((si + 1) / float(n_sp))
            x0, y0 = ax + cos(a0) * r_sp, SPRING_Y + sin(a0) * r_sp
            x1, y1 = ax + cos(a1) * r_sp, SPRING_Y + sin(a1) * r_sp
            c_sp = jit(C_TEMPLE_MID if (si % 2 == 0) else C_TEMPLE_HI, rng, 0.03)
            in_ref = Vector((0.5 * (x0 + x1), 0.5 * (min(y0, y1) + y_sp_top), 0.0))
            mb.fp([(x0, y0, -hz_sp), (x1, y1, -hz_sp), (x1, y_sp_top, -hz_sp), (x0, y_sp_top, -hz_sp)],
                  'temple_stone', c_sp, (1, 0, 0), in_ref, smooth=False)
            mb.fp([(x1, y1,  hz_sp), (x0, y0,  hz_sp), (x0, y_sp_top,  hz_sp), (x1, y_sp_top,  hz_sp)],
                  'temple_stone', c_sp, (1, 0, 0), in_ref, smooth=False)

    # Middle pier decorative gold-inlaid spandrel diamond plaque facing -Z & +Z
    for sz_s in (-1.0, 1.0):
        cbox(mb, (0.0, 8.55, sz_s * 1.28), (1.12, 1.52, 0.08), 'temple_stone', C_TEMPLE_DARK, 0.0)
        cbox(mb, (0.0, 8.55, sz_s * 1.33), (0.64, 0.64, 0.05), 'brass', C_TEMPLE_GOLD, 0.0, M=R('Z', 45.0))
        cbox(mb, (0.0, 8.55, sz_s * 1.35), (0.28, 0.28, 0.05), 'brass', C_BRASS, 0.0)

    # 5. Overhanging Cornice Deck & Elevated Broken Stone Water-Trough Parapet (y = 10.6 .. 12.2 m)
    deck_segs = [
        (-9.15, -6.10, C_TEMPLE_HI),
        (-6.10, -2.90, C_TEMPLE_HI),
        (-2.90,  0.30, C_TEMPLE_MID),
        ( 0.30,  3.50, C_TEMPLE_HI),
        ( 3.50,  5.95, C_TEMPLE_MID),
    ]
    for x0, x1, dcol in deck_segs:
        _box2(mb, (x0, DECK_Y0, -1.56), (x1, DECK_Y1, 1.56), 'temple_stone', dcol, 0.0, (1, 0, 0))
    # Damp mossy stone water-channel bed inside the trough (y = 10.58 .. 10.74 m)
    _box2(mb, (-8.85, DECK_Y1 - 0.04, -0.84), (6.15, DECK_Y1 + 0.12, 0.84),
          'limestone_moss', mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.55), 0.0, (1, 0, 0))

    # Intact & progressively fractured stone water-trough parapet walls (z = -1.16 & +1.16, y = 10.6..12.2 m)
    parapet_front_courses = [
        (-7.65, 2.85, 12.22, True),
        (-4.75, 2.95, 12.18, True),
        (-1.85, 2.85, 12.12, True),
        ( 1.05, 2.90, 12.06, True),
        ( 3.70, 2.40, 11.78, False),
        ( 5.55, 1.45, 11.48, False),
    ]
    parapet_back_courses = [
        (-7.65, 2.85, 12.22, True),
        (-4.75, 2.95, 12.20, True),
        (-1.85, 2.85, 12.18, True),
        ( 1.05, 2.90, 12.12, True),
        ( 3.85, 2.65, 11.98, True),
        ( 5.85, 1.55, 11.65, False),
    ]
    for sz_p, courses in ((-1.16, parapet_front_courses), (1.16, parapet_back_courses)):
        for ci, (px_c, pw, py_hi, has_cap) in enumerate(courses):
            ph = py_hi - DECK_Y1
            if ci >= 4:
                sculpt_stone_block(
                    mb, (px_c, DECK_Y1 + ph * 0.5, sz_p), (pw, ph, 0.62),
                    'temple_stone', C_TEMPLE_HI, rng, chip=0.055, moss_col=C_LEDGE_MOSS,
                )
            else:
                cbox(mb, (px_c, DECK_Y1 + ph * 0.5, sz_p), (pw, ph, 0.62),
                     'temple_stone', jit(C_TEMPLE_MID, rng, 0.04), 0.0, (1, 0, 0))
            if has_cap:
                cbox(mb, (px_c, py_hi + 0.14, sz_p), (pw + 0.08, 0.30, 0.76),
                     'temple_stone', jit(mix(C_TEMPLE_HI, C_LEDGE_MOSS, 0.16), rng, 0.04), 0.0, (1, 0, 0))

    # 6. Monumental Left (-X) Headwater Sluice Pylon Crown (rises proudly to y = 13.95 m -> ~14.0 m tall!)
    for sz_p in (-1.12, 1.12):
        sculpt_stone_block(
            mb, (-8.25, 12.92, sz_p), (1.72, 1.42, 0.86), 'temple_stone',
            C_TEMPLE_HI, rng, chip=0.055, moss_col=C_LEDGE_MOSS,
        )
    sculpt_stone_block(
        mb, (-8.25, 13.62, 0.0), (1.88, 0.56, 3.16), 'temple_stone',
        C_TEMPLE_HI, rng, chip=0.055, moss_col=C_LEDGE_MOSS,
    )
    for sz_s in (-1.0, 1.0):
        cbox(mb, (-8.25, 13.15, sz_s * 1.56), (1.32, 0.14, 0.06), 'brass', C_TEMPLE_GOLD, 0.0)

    # 7. Dramatic Staggered Jagged Ruined Stone Teeth Crumbling Off the Right (+X) End! (x = +6.0..+9.2 m)
    ruin_teeth = [
        ((6.55, 10.42, -0.82), (1.42, 0.56, 1.38), ( 3,  -6, -5), C_TEMPLE_HI),
        ((6.78, 10.46,  0.76), (1.68, 0.62, 1.48), (-2,   8, -4), C_TEMPLE_MID),
        ((7.28, 11.35,  1.10), (1.16, 1.36, 0.66), ( 4, -10, -7), C_TEMPLE_HI),   # dramatic tall jagged tooth!
        ((6.68, 11.15, -1.14), (0.98, 1.08, 0.62), (-5,  12, -10), C_TEMPLE_HI),  # snapped front wall tooth
        ((7.86, 10.35, -0.35), (1.34, 0.68, 1.25), ( 6,  14, -12), C_TEMPLE_MID), # tilted fractured deck slab
        ((8.28, 10.72,  0.96), (1.06, 1.05, 0.72), (-4,  -8, -9), C_TEMPLE_HI),   # jagged outer ruined fang
        ((8.68,  9.92, -0.78), (1.08, 0.82, 0.92), ( 7,  18, -16), C_TEMPLE_MID), # crumbling lower step tooth
        ((8.88,  9.48,  0.55), (0.94, 0.86, 0.98), (-6, -15, -14), C_TEMPLE_DARK),# far-right cracked masonry spur
    ]
    for rctr, rsz, rrot, rcol in ruin_teeth:
        M_r = R('Y', rrot[1]) @ R('X', rrot[0]) @ R('Z', rrot[2])
        sculpt_stone_block(mb, rctr, rsz, 'temple_stone', rcol, rng, chip=0.065, M=M_r, moss_col=C_LEDGE_MOSS)

    # 8. Mossy Highland Stone Cap Blocks ('limestone_moss') seated flush INTO the weathered parapet & pier ledges
    moss_caps = [
        ((-8.20, 13.76,  0.10), (1.05, 0.42, 1.28), 0.88),
        ((-4.15, 12.22, -1.12), (1.12, 0.36, 0.46), 0.84),
        (( 0.25, 12.16,  1.12), (1.22, 0.38, 0.46), 0.86),
        (( 4.85, 11.58,  1.08), (0.92, 0.36, 0.44), 0.82),
        (( 7.28, 11.86,  1.08), (0.66, 0.32, 0.42), 0.78),
        ((-8.15,  6.72, -1.10), (0.76, 0.40, 0.52), 0.80),
        (( 8.05,  6.66,  1.05), (0.78, 0.42, 0.54), 0.76),
    ]
    for mc_c, mc_r, mc_f in moss_caps:
        _sculpt_grounded_terrace(
            mb, mc_c, mc_r, 'limestone_moss',
            C_GRASS_SUN, C_LEDGE_MOSS, C_TEMPLE_MID, rng,
            subdiv=2, warp=0.14, strata=0.08, flat_top=0.42, base_flare=0.30,
            crag_ribs=5, rib_amp=0.09, moss_cap=mc_f,
        )

    # 9. Six Cascading Jungle Vines Draping Through BOTH Arches (framing—NEVER blocking—the gold medallions!)
    vine_specs = [
        # Left arch (x_c = -3.675) — 3 drapes framing left/right haunches & rear arch opening
        ((-5.28, 10.35, -1.44), 4.55, 0.38, (-0.12, 0.0, -1.0), 0.08),
        ((-2.12, 10.32, -1.44), 3.95, 0.34, ( 0.10, 0.0, -1.0), 0.27),
        ((-3.85, 10.45,  1.44), 3.35, 0.34, (-0.06, 0.0,  1.0), 0.46),
        # Right arch (x_c = +3.675) — 3 drapes framing left/right haunches & rear arch opening
        (( 2.08, 10.35, -1.44), 4.35, 0.36, (-0.10, 0.0, -1.0), 0.62),
        (( 5.26, 10.22, -1.42), 3.75, 0.34, ( 0.14, 0.0, -1.0), 0.79),
        (( 3.85, 10.42,  1.44), 3.25, 0.32, ( 0.05, 0.0,  1.0), 0.93),
    ]
    for anc, vlen, vw, vdir, vph in vine_specs:
        add_vine_drape(mb, anc, vlen, vw, vdir, rng, phase=vph)

    build(mb)

    # Four clean colliders preserving BOTH ~4.8 m open archways cleanly!
    col_piece('col_aqueduct_left',  pier_col_pts[0] + [Vector((-9.10, 9.45, -1.45)), Vector((-6.05, 9.45, 1.45))])
    col_piece('col_aqueduct_mid',   pier_col_pts[1] + [Vector((-1.30, 9.45, -1.45)), Vector(( 1.30, 9.45, 1.45))])
    col_piece('col_aqueduct_right', pier_col_pts[2] + [Vector(( 6.05, 9.45, -1.45)), Vector(( 9.10, 9.45, 1.45))])
    col_box('col_aqueduct_deck', (-9.20, 9.15, -1.58), (8.95, 12.45, 1.58))
    export_landmark_glb(outdir, 'cliff_ruin_aqueduct_arch.glb')


# ================================================================ 3. CLIFFSIDE PIRATE WATCHPOST

def gen_cliffside_pirate_watchpost(outdir):
    """Sea-of-Thieves-grade ~11.4 m tall cantilevered weathered-timber cliff-edge pirate lookout
    scaffolding & crow's-nest watchpost facing seaward (-Z).
    Heavy angled timber stilts plunging to y = -4.8 m, diagonal X-bracing, rear cliff-anchor beams
    extending to z = +3.85 m, planked octagonal lookout platform (y = 4.6 m, r ~ 2.4 m), rope-lashed
    guardrail, weathered rear wooden ladder, mounted brass spyglass on oak tripod, oak rum barrel &
    spyglass crate, crooked signal mast rising to y = 10.8 m with 3D double-sided swallowtail crimson
    pirate pennant, and suspended iron-cage watch lantern with Empty 'Lantern_Watchpost'.
    Target: 2,800–4,600 visual tris.
    """
    clear_scene()
    rng = random.Random(SEED + 971)
    mb = MB('CliffsidePirateWatchpost', seed=971)

    DECK_Y = 4.60
    PLAT_Z = -0.35
    PLAT_R = 2.42
    STILT_BOT = -4.80
    ANCHOR_Z = 3.85
    frame_col_pts = []

    # 1. Heavy Angled Timber Stilts (plunging to y = -4.8 m), Rear Cliff-Anchor Beams (z = +3.85 m) & X-Bracing!
    stilt_specs = [
        ((-1.62, DECK_Y - 0.14, PLAT_Z - 1.35), (-2.12, STILT_BOT,  1.15), 0.165, 0.215),
        (( 1.62, DECK_Y - 0.14, PLAT_Z - 1.35), ( 2.12, STILT_BOT,  1.15), 0.165, 0.215),
        ((-1.72, DECK_Y - 0.14, PLAT_Z + 1.48), (-1.95, STILT_BOT,  2.35), 0.160, 0.205),
        (( 1.72, DECK_Y - 0.14, PLAT_Z + 1.48), ( 1.95, STILT_BOT,  2.35), 0.160, 0.205),
        ((-1.78, DECK_Y - 0.18,  3.55),         (-1.82, -1.60,      3.72), 0.155, 0.185),
        (( 1.78, DECK_Y - 0.18,  3.55),         ( 1.82, -1.60,      3.72), 0.155, 0.185),
    ]
    for p_top, p_bot, rt, rb in stilt_specs:
        pa, pb = Vector(p_bot), Vector(p_top)
        pm = pa.lerp(pb, 0.50) + Vector((rng.uniform(-0.04, 0.04), 0.0, rng.uniform(-0.04, 0.04)))
        tube(mb, [pa, pm, pb], [rb, 0.5 * (rb + rt), rt], 6, 'timber',
             jit(C_TIMBER_DARK, rng, 0.06), mode='flat',
             scols=[C_TIMBER_DARK, C_TIMBER_MID, C_TIMBER_MID])
        frame_col_pts.extend([pa, pb])
        for t_band in (0.64, 0.94):
            bp = pa.lerp(pb, t_band)
            cbox(mb, bp, (rt * 2.45, 0.14, rt * 2.45), 'iron',
                 C_IRON_RUST if t_band < 0.8 else C_IRON, 0.0)

    # Stout Rear Cliff-Anchor Longitudinal Tie-Back Beams extending solidly back to z = +3.85 m!
    for sx in (-1.75, 1.75):
        _box2(mb, (sx - 0.13, DECK_Y - 0.34, PLAT_Z - 1.92), (sx + 0.13, DECK_Y - 0.06, ANCHOR_Z),
              'timber', C_TIMBER_DARK, 0.0, (0, 0, 1))
        _box2(mb, (sx - 0.12, 1.32, -0.45), (sx + 0.12, 1.58, ANCHOR_Z),
              'timber', C_TIMBER_MID, 0.0, (0, 0, 1))
        _add_beam(mb, (sx, 1.42, 2.15), (sx, DECK_Y - 0.22, PLAT_Z - 1.92), 0.20, 0.22, 'timber', C_TIMBER_MID, 0.0)
        cbox(mb, (sx, DECK_Y - 0.20, ANCHOR_Z - 0.08), (0.34, 0.36, 0.18), 'iron', C_IRON, 0.0)
        cbox(mb, (sx, 1.45, ANCHOR_Z - 0.08), (0.32, 0.34, 0.18), 'iron', C_IRON_RUST, 0.0)
        cbox(mb, (sx, DECK_Y - 0.20, PLAT_Z - 1.72), (0.32, 0.32, 0.32), 'iron', C_IRON, 0.0)
        frame_col_pts.extend([Vector((sx, DECK_Y - 0.10, ANCHOR_Z)), Vector((sx, 1.32, ANCHOR_Z))])

    # Rear Cliff-Anchor Cross-Header Sill Beams & Mid-Tier Ledger + Mast-Step Support Crossbeam!
    _box2(mb, (-2.35, DECK_Y - 0.38, ANCHOR_Z - 0.34), (2.35, DECK_Y - 0.06, ANCHOR_Z),
          'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
    _box2(mb, (-2.25, 1.28, ANCHOR_Z - 0.32), (2.25, 1.60, ANCHOR_Z),
          'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
    _add_beam(mb, (-1.92, 1.42, -0.35), (1.92, 1.42, -0.35), 0.20, 0.22, 'timber', C_TIMBER_MID, 0.0)
    _add_beam(mb, (-1.85, 1.42,  1.88), (1.85, 1.42,  1.88), 0.20, 0.22, 'timber', C_TIMBER_MID, 0.0)
    # Dedicated Mast-Step Cross-Timber supporting the heel of the crooked signal mast at y = 1.42 m!
    _add_beam(mb, (-1.86, 1.42, PLAT_Z + 0.65), (1.86, 1.42, PLAT_Z + 0.65), 0.24, 0.26, 'timber', C_TIMBER_DARK, 0.0)
    cbox(mb, (-0.22, 1.56, PLAT_Z + 0.65), (0.50, 0.22, 0.50), 'iron', C_IRON, 0.0)
    _add_beam(mb, (-2.04, -1.65, 0.38), (2.04, -1.65, 0.38), 0.20, 0.22, 'timber', C_TIMBER_DARK, 0.0)

    # Diagonal X-Bracing across front bay, lower bay, and port/starboard side bays!
    x_braces = [
        ((-1.88, 1.42, -0.32), ( 1.62, DECK_Y - 0.22, PLAT_Z - 1.32)),
        (( 1.88, 1.42, -0.32), (-1.62, DECK_Y - 0.22, PLAT_Z - 1.32)),
        ((-2.02, -1.65, 0.40), ( 1.88,  1.42, -0.32)),
        (( 2.02, -1.65, 0.40), (-1.88,  1.42, -0.32)),
        ((-1.88, 1.42, -0.32), (-1.74, DECK_Y - 0.22, PLAT_Z + 1.45)),
        ((-1.84, 1.42,  1.88), (-1.64, DECK_Y - 0.22, PLAT_Z - 1.32)),
        (( 1.88, 1.42, -0.32), ( 1.74, DECK_Y - 0.22, PLAT_Z + 1.45)),
        (( 1.84, 1.42,  1.88), ( 1.64, DECK_Y - 0.22, PLAT_Z - 1.32)),
    ]
    for p0, p1 in x_braces:
        _add_beam(mb, p0, p1, 0.13, 0.13, 'timber', jit(C_TIMBER_DARK, rng, 0.06), 0.0)
    cbox(mb, (0.0, 2.90, -0.96), (0.28, 0.28, 0.22), 'iron', C_IRON, 0.0)
    cbox(mb, (0.0, -0.12, 0.04), (0.28, 0.28, 0.22), 'iron', C_IRON_RUST, 0.0)
    for sx in (-1.78, 1.78):
        cbox(mb, (sx, 2.90, 0.42), (0.22, 0.26, 0.26), 'iron', C_IRON, 0.0)

    # 2. Planked Octagonal Lookout Platform (y = 4.60 m, r = 2.42 m)
    oct_pts = []
    for k in range(8):
        ang = pi / 8.0 + 2.0 * pi * k / 8.0
        oct_pts.append(Vector((PLAT_R * cos(ang), DECK_Y, PLAT_Z + PLAT_R * sin(ang))))

    for k in range(8):
        kn = (k + 1) % 8
        _add_beam(mb, oct_pts[k] - Vector((0.0, 0.20, 0.0)), oct_pts[kn] - Vector((0.0, 0.20, 0.0)),
                  0.18, 0.22, 'timber', C_TIMBER_DARK, 0.0)
    for jz in (-1.45, -0.50, 0.45, 1.40):
        az = abs(jz)
        hw = min(PLAT_R * 0.90, (PLAT_R * 0.94) - max(0.0, az - PLAT_R * 0.38) * 0.98)
        if hw > 0.35:
            _box2(mb, (-hw, DECK_Y - 0.22, PLAT_Z + jz - 0.08), (hw, DECK_Y - 0.08, PLAT_Z + jz + 0.08),
                  'timber', C_TIMBER_MID, 0.0, (1, 0, 0))

    # 13 Individual Weathered Oak Deck Planks clipped cleanly to the octagonal platform footprint!
    n_planks = 13
    p_cols = (C_TIMBER_HI, C_TIMBER_MID, C_DRIFTWOOD, C_TIMBER_HI)
    apothems = PLAT_R * cos(pi / 8.0)
    for pi_i in range(n_planks):
        u = (pi_i + 0.5) / float(n_planks)
        dz = -apothems + 0.06 + u * (2.0 * apothems - 0.12)
        hw = min(apothems, apothems * (1.0 + sqrt(2.0) * 0.5) - abs(dz)) - 0.04
        hw = max(0.75, min(apothems - 0.04, hw))
        pw = hw * 2.0 + rng.uniform(-0.04, 0.04)
        pcol = jit(p_cols[pi_i % len(p_cols)], rng, 0.075, 0.02)
        cbox(mb, (rng.uniform(-0.02, 0.02), DECK_Y - 0.045 + rng.uniform(-0.006, 0.006), PLAT_Z + dz),
             (pw, 0.095, 0.305), 'timber', pcol, 0.0, (1, 0, 0), M=R('Y', rng.uniform(-1.3, 1.3)))

    # 3. Rope-Lashed Octagonal Timber Guardrail (facet 1->2 open for rear +Z wooden ladder!)
    RAIL_H = 1.16
    post_tops = []
    for k in range(8):
        pv = oct_pts[k]
        inward = (Vector((0.0, DECK_Y, PLAT_Z)) - pv).normalized()
        pc = pv + inward * 0.12
        ph = 2.86 if k == 5 else (RAIL_H + rng.uniform(-0.05, 0.06))
        lx = rng.uniform(-2.0, 2.0) if k != 5 else -1.5
        lz = rng.uniform(-2.0, 2.0) if k != 5 else 2.0
        pM = T(pc.x, DECK_Y - 0.24, pc.z) @ R('X', lx) @ R('Z', lz)
        with xf(mb, pM):
            cbox(mb, (0.0, (ph + 0.24) * 0.5, 0.0), (0.155, ph + 0.24, 0.155),
                 'timber', jit(C_TIMBER_MID if k != 5 else C_TIMBER_DARK, rng, 0.06), 0.0, (0, 1, 0))
            cbox(mb, (0.0, ph + 0.25, 0.0), (0.19, 0.055, 0.19), 'timber', C_TIMBER_HI, 0.0)
            # Crisp wrapped hemp rope lashing collar at rail joint (6-sided banded collar = 24 tris!)
            cyl(mb, 0.112, RAIL_H + 0.02, RAIL_H + 0.16, 6, 'rope', C_ROPE, False, 0.0)
        post_tops.append(pM @ Vector((0.0, RAIL_H + 0.12, 0.0)))
        if k == 5:
            lantern_post_M = pM

    for k in range(8):
        if k == 1:
            continue  # Open rear (+Z) ladder entrance!
        kn = (k + 1) % 8
        p0, p1 = post_tops[k], post_tops[kn]
        _add_beam(mb, p0, p1, 0.10, 0.10, 'timber', jit(C_TIMBER_HI, rng, 0.06), 0.0)
        # Sagging catenary braided hemp rope guard line (5 stations, 4 sides -> light & clean!)
        cat = []
        for si in range(5):
            t = si / 4.0
            q = p0.lerp(p1, t)
            q.y -= 0.46 + 0.12 * 4.0 * t * (1.0 - t)
            cat.append(q)
        tube(mb, cat, 0.030, 4, 'rope', jit(C_ROPE, rng, 0.05), mode='smooth')

    # Seaward pirate timber breastwork planks & painted crimson lookout crest across front 3 facets!
    for k in (4, 5, 6):
        kn = (k + 1) % 8
        p0, p1 = oct_pts[k], oct_pts[kn]
        mid = (p0 + p1) * 0.5
        edge = p1 - p0
        elen = edge.length - 0.12
        eyaw = -degrees(atan2(edge.z, edge.x))
        with xf(mb, T(mid.x, DECK_Y, mid.z) @ R('Y', eyaw)):
            cbox(mb, (0.0, 0.24, 0.0), (elen, 0.28, 0.065), 'timber', jit(C_TIMBER_MID, rng, 0.06), 0.0, (1, 0, 0))
            cbox(mb, (0.0, 0.54, 0.0), (elen, 0.26, 0.065), 'timber', jit(C_DRIFTWOOD, rng, 0.06), 0.0, (1, 0, 0))
            if k == 5:
                cbox(mb, (0.0, 0.39, -0.048), (1.18, 0.34, 0.025), 'paint', C_PAINT_RED, 0.0)
                cbox(mb, (0.0, 0.39, -0.064), (0.28, 0.28, 0.022), 'paint', C_PAINT_CREAM, 0.0, M=R('Z', 45.0))
                cbox(mb, (0.0, 0.39, -0.072), (0.14, 0.14, 0.018), 'brass', C_BRASS, 0.0)

    # 4. Weathered Wooden Ladder Climbing From Rear Cliff Terrace Into Open Rear Gate (+Z)!
    lad_bot_l = Vector((-0.44, -0.35, 3.62))
    lad_bot_r = Vector(( 0.44, -0.35, 3.62))
    lad_top_l = Vector((-0.44, DECK_Y + 0.78, PLAT_Z + apothems - 0.10))
    lad_top_r = Vector(( 0.44, DECK_Y + 0.78, PLAT_Z + apothems - 0.10))
    _add_beam(mb, lad_bot_l, lad_top_l, 0.11, 0.11, 'timber', C_TIMBER_DARK, 0.0)
    _add_beam(mb, lad_bot_r, lad_top_r, 0.11, 0.11, 'timber', C_TIMBER_DARK, 0.0)
    n_rungs = 11
    for ri in range(n_rungs):
        t = (ri + 0.5) / float(n_rungs + 0.6)
        rl = lad_bot_l.lerp(lad_top_l, t)
        rr = lad_bot_r.lerp(lad_top_r, t)
        tilt_y = rng.uniform(-0.025, 0.025)
        _add_beam(mb, rl + Vector((-0.05, tilt_y, 0.0)), rr + Vector((0.05, -tilt_y, 0.0)),
                  0.065, 0.065, 'timber', jit(C_TIMBER_HI if ri % 2 == 0 else C_DRIFTWOOD, rng, 0.07), 0.0)
        if ri % 3 == 1:
            for r_end in (rl, rr):
                cbox(mb, r_end, (0.145, 0.115, 0.145), 'rope', C_ROPE, 0.0)
    frame_col_pts.extend([lad_bot_l, lad_bot_r, lad_top_l, lad_top_r])

    # 5. Mounted Brass Spyglass on an Oak Tripod Aiming Seaward (-Z)!
    tri_ctr = Vector((0.64, DECK_Y, PLAT_Z - 1.38))
    tri_hub = Vector((tri_ctr.x, DECK_Y + 1.24, tri_ctr.z))
    for k in range(3):
        ang = radians(30.0 + k * 120.0)
        foot = Vector((tri_ctr.x + cos(ang) * 0.48, DECK_Y + 0.02, tri_ctr.z + sin(ang) * 0.48))
        _add_beam(mb, foot, tri_hub, 0.052, 0.052, 'timber', C_TIMBER_MID, 0.0)
        cbox(mb, foot + Vector((0.0, 0.04, 0.0)), (0.068, 0.08, 0.068), 'iron', C_IRON, 0.0)
    with xf(mb, T(tri_hub)):
        cyl(mb, 0.082, -0.06, 0.07, 6, 'brass', C_TEMPLE_GOLD, False, 0.0)
        for sx in (-0.062, 0.062):
            cbox(mb, (sx, 0.12, 0.0), (0.028, 0.16, 0.052), 'brass', C_BRASS, 0.0)
    spy_M = T(tri_hub + Vector((0.0, 0.17, 0.0))) @ R('Y', -8.0) @ R('X', -6.0)
    with xf(mb, spy_M @ M_Y2Z):
        cyl(mb, 0.032,  0.34,  0.54, 6, 'brass', C_BRASS, False, 0.0, 0.026)
        cyl(mb, 0.042,  0.18,  0.35, 6, 'brass', C_TEMPLE_GOLD, False, 0.0, 0.038)
        cyl(mb, 0.058, -0.26,  0.19, 6, 'timber', C_TIMBER_DARK, False, 0.0, 0.052)
        cyl(mb, 0.065, -0.28, -0.22, 6, 'brass', C_BRASS, False, 0.0)
        cyl(mb, 0.062,  0.14,  0.20, 6, 'brass', C_BRASS, False, 0.0)
        cyl(mb, 0.066, -0.56, -0.26, 6, 'brass', C_BRASS, False, 0.0, 0.078)
        cyl(mb, 0.064, -0.57, -0.53, 6, 'glass', C_LANTERN_GL, False, 0.0)

    # 6. Oak Lookout Rum Barrel, Spyglass Supply Crate & Rope Coil on Port/Starboard Deck!
    bar_pos = Vector((-1.32, DECK_Y + 0.44, PLAT_Z - 0.42))
    with xf(mb, T(bar_pos)):
        b_prof = [
            (0.0, -0.44), (0.26, -0.44), (0.31, -0.24),
            (0.34, 0.0), (0.31, 0.24), (0.26, 0.44), (0.0, 0.44),
        ]
        stave_cols = [jit(C_TIMBER_MID, rng, 0.09, 0.02) for _ in range(8)]
        lathe(mb, b_prof, 8, 'timber', C_TIMBER_MID, False, False,
              lambda i, k: C_TIMBER_DARK if i in (0, 5) else stave_cols[k])
        for hy, hr in ((-0.32, 0.302), (-0.12, 0.342), (0.12, 0.342), (0.32, 0.302)):
            cyl(mb, hr, hy - 0.026, hy + 0.026, 8, 'iron', C_IRON, False, 0.0)
        with xf(mb, T(0.32, -0.20, 0.0) @ M_Y2X):
            cyl(mb, 0.024, 0.0, 0.10, 5, 'brass', C_BRASS, False, 0.0)

    crate_M = T(-1.18, DECK_Y + 0.34, PLAT_Z + 0.62) @ R('Y', 19.0)
    with xf(mb, crate_M):
        cbox(mb, (0.0, 0.0, 0.0), (0.76, 0.66, 0.72), 'timber', C_TIMBER_MID, 0.0)
        for sy in (-0.31, 0.31):
            for sz in (-0.35, 0.35):
                cbox(mb, (0.0, sy, sz), (0.82, 0.085, 0.085), 'timber', C_TIMBER_HI, 0.0, (1, 0, 0))
            for sx in (-0.37, 0.37):
                cbox(mb, (sx, sy, 0.0), (0.085, 0.085, 0.64), 'timber', C_TIMBER_HI, 0.0, (0, 0, 1))
        for sx in (-0.37, 0.37):
            for sz in (-0.35, 0.35):
                cbox(mb, (sx, 0.0, sz), (0.085, 0.56, 0.085), 'timber', C_TIMBER_DARK, 0.0, (0, 1, 0))
        cbox(mb, (0.0, 0.04, -0.37), (0.56, 0.14, 0.02), 'paint', C_PAINT_RED, 0.0)
        cbox(mb, (0.0, 0.04,  0.37), (0.56, 0.14, 0.02), 'paint', C_PAINT_RED, 0.0)
        for sx in (-0.38, 0.38):
            for sz in (-0.36, 0.36):
                cbox(mb, (sx, 0.31, sz), (0.09, 0.09, 0.09), 'iron', C_IRON, 0.0)

    # Compact 2-turn deck rope coil
    for ci in range(2):
        with xf(mb, T(1.28, DECK_Y + 0.032 + ci * 0.052, PLAT_Z + 0.38)):
            torus(mb, 0.25 - ci * 0.04, 0.032, 8, 4, 'rope', mul(C_ROPE, 0.92 + 0.08 * ci), True)

    # 7. Crooked Timber Signal Mast Rising to y = 10.85 m + Yardarm + 3D Double-Sided Crimson Pirate Pennant!
    mast_path = [
        (-0.22, 1.45, PLAT_Z + 0.65),
        (-0.26, 3.20, PLAT_Z + 0.58),
        (-0.30, 4.75, PLAT_Z + 0.52),
        (-0.24, 6.45, PLAT_Z + 0.44),
        (-0.14, 8.15, PLAT_Z + 0.34),
        (-0.08, 9.65, PLAT_Z + 0.25),
        (-0.04, 10.85, PLAT_Z + 0.20),
    ]
    mast_rads = [0.22, 0.20, 0.19, 0.175, 0.155, 0.135, 0.105]
    mast_cols = [
        C_TIMBER_DARK, C_TIMBER_DARK, C_TIMBER_MID,
        C_TIMBER_MID, C_DRIFTWOOD, C_DRIFTWOOD, C_DRIFTWOOD,
    ]
    tube(mb, mast_path, mast_rads, 6, 'timber', C_DRIFTWOOD, mode='flat', scols=mast_cols)

    def mast_at(yh):
        for i in range(len(mast_path) - 1):
            y0, y1 = mast_path[i][1], mast_path[i + 1][1]
            if y0 <= yh <= y1:
                t = (yh - y0) / max(y1 - y0, 1e-5)
                p0, p1 = Vector(mast_path[i]), Vector(mast_path[i + 1])
                return p0.lerp(p1, t), mast_rads[i] * (1.0 - t) + mast_rads[i + 1] * t
        return Vector(mast_path[-1]), mast_rads[-1]

    for by in (4.95, 6.85, 9.25, 10.55):
        pm, rm = mast_at(by)
        with xf(mb, T(pm)):
            cyl(mb, rm + 0.022, -0.055, 0.055, 6, 'iron', C_IRON, False, 0.0)
    with xf(mb, T(mast_path[-1])):
        cyl(mb, 0.125, -0.02, 0.14, 6, 'brass', C_TEMPLE_GOLD, False, 0.0, 0.04)
        cyl(mb, 0.022,  0.12, 0.42, 4, 'iron', C_IRON, False, 0.0, 0.008)
    for cy_c in (5.60, 6.25, 6.90, 7.55, 8.20):
        pm, rm = mast_at(cy_c)
        sgn_c = 1.0 if (int(cy_c * 2) % 2 == 0) else -1.0
        cbox(mb, pm + Vector((sgn_c * (rm + 0.12), 0.0, 0.0)), (0.28, 0.055, 0.065), 'timber', C_TIMBER_HI, 0.0)

    # Crooked Horizontal Timber Signal Yardarm Spar (y = 9.35 m) lashed with rope + 4 hemp shrouds!
    p_yard, r_yard = mast_at(9.35)
    yard_l = p_yard + Vector((-1.95, -0.14, -0.25))
    yard_r = p_yard + Vector(( 1.95,  0.18,  0.15))
    tube(mb, [yard_l, p_yard + Vector((0.0, 0.02, -0.06)), yard_r],
         [0.055, 0.095, 0.055], 5, 'timber', C_DRIFTWOOD, mode='flat')
    with xf(mb, T(p_yard + Vector((0.0, 0.0, -0.03))) @ R('X', 36)):
        torus(mb, r_yard + 0.055, 0.034, 6, 4, 'rope', C_ROPE, True)
    p_shroud_hi, _ = mast_at(9.20)
    for k_sh in (0, 3, 4, 7):
        tube(mb, [p_shroud_hi, post_tops[k_sh]], 0.024, 4, 'rope', jit(C_ROPE, rng, 0.05), mode='smooth')

    # Fluttering 3D Double-Sided Swallowtail Crimson Pirate Pennant ('paint') streaming boldly crosswind!
    p_pen, _ = mast_at(10.50)
    _build_double_sided_pennant(
        mb,
        root_pos=p_pen + Vector((-0.11, 0.0, -0.02)),
        length=2.85,
        h0=0.84,
        out_dir=(-0.95, 0.0, -0.31),
        col_main=C_PAINT_RED,
        col_trim=C_PAINT_CREAM,
        tattered=True,
    )

    # 8. Suspended Iron-Cage Watch Lantern + Empty 'Lantern_Watchpost' + Glowing 'glass' Core!
    with xf(mb, lantern_post_M):
        cbox(mb, (0.0, 2.75, -0.10), (0.12, 0.42, 0.055), 'iron', C_IRON, 0.0)
        tube(mb, [
            (0.0, 2.86, -0.06),
            (0.0, 2.94, -0.52),
            (0.0, 2.96, -0.96),
            (0.0, 2.86, -1.04),
        ], [0.028, 0.026, 0.024, 0.018], 4, 'iron', C_IRON, mode='flat')
        tube(mb, [
            (0.0, 2.38, -0.06),
            (0.0, 2.66, -0.48),
            (0.0, 2.93, -0.84),
        ], 0.020, 4, 'iron', C_IRON_RUST, mode='flat')
        l_hook_local = Vector((0.0, 2.84, -1.04))

    l_hook_w = lantern_post_M @ l_hook_local
    l_scale = 1.24
    lantern_pos = (l_hook_w.x, l_hook_w.y - 0.68, l_hook_w.z)
    _add_chain_links(
        mb,
        l_hook_w + Vector((0.0, -0.02, 0.0)),
        Vector((lantern_pos[0], lantern_pos[1] + 0.31 * l_scale, lantern_pos[2])),
        n_links=3, link_r=0.044, wire_r=0.013,
    )
    build_lantern_geom(mb, lantern_pos, scale=l_scale, hanging=True)
    # Protective forged-iron watch-cage hoop & vertical guard bars framing the glowing glass lantern!
    with xf(mb, T(lantern_pos)):
        for hy_c in (-0.12 * l_scale, 0.12 * l_scale):
            torus(mb, 0.178 * l_scale, 0.014 * l_scale, 6, 4, 'iron', C_IRON, False)
        for k_c in range(4):
            ang = k_c * pi * 0.5
            cbox(mb, (cos(ang) * 0.178 * l_scale, 0.0, sin(ang) * 0.178 * l_scale),
                 (0.024 * l_scale, 0.34 * l_scale, 0.024 * l_scale), 'iron', C_IRON_RUST, 0.0)

    build(mb)

    add_empty('Lantern_Watchpost', lantern_pos)
    col_piece('col_watchpost_frame', frame_col_pts)
    deck_col_pts = []
    for v in oct_pts:
        deck_col_pts.append(Vector((v.x, DECK_Y - 0.18, v.z)))
        deck_col_pts.append(Vector((v.x, DECK_Y + 0.06, v.z)))
    col_piece('col_watchpost_deck', deck_col_pts)
    export_landmark_glb(outdir, 'cliffside_pirate_watchpost.glb')


# ================================================================ 4. UPPER CLIFF STRATA RIB

def gen_upper_cliff_strata_rib(outdir):
    """~17.0 m tall, ~13.5 m wide reclined stepped sedimentary limestone cliff rib & layered strata
    plate built SPECIFICALLY for 45°-75° mid-to-upper mountain walls (-Z faces outward downhill,
    +Z plunges deep into the mountain).
    CRITICAL ANTI-FLOAT SILHOUETTE: strictly monotonic bottom-heavy ~58° reclined diagonal A-frame
    profile (y = -4.5..+13.3 m, retreating steadily backward from z = -2.2 m at base to z = +4.8 m
    at crest, with a massive solid back rock wedge extending to z = +8.5 m from bottom to top!).
    5 bold jagged horizontal limestone strata ledges, continuous reclined vertical cleavage ribs,
    flush mossy top shelf rims, and 2 short cliff vines. ZERO mushroom caps, ZERO dangling undersides!
    Target: 1,000–1,800 visual tris.
    """
    clear_scene()
    rng = random.Random(SEED + 997)
    mb = MB('UpperCliffStrataRib', seed=997)
    col_pts = []

    Z_BACK = 8.50

    # 1. Five Bold Jagged Organic Horizontal Limestone Strata Plates stepping monotonically backward (~58°!)
    #    Every upper plate is strictly BEHIND & NARROWER than the plate below -> ZERO overhangs / mushroom caps!
    #    Every plate anchors solidly to z = +8.50 m from bottom to top -> ZERO floating backs or dangling undersides!
    strata_specs = [
        # (y_bot, y_top, x_half, z_front, moss_top, jag_x, jag_z, brow_step, x_shift, crest_lift)
        (-4.50, -0.35, 6.75, -2.20, 0.62, 0.45, 0.56, 0.40,  0.00, 0.00),  # Stratum 1: broad grounded apron
        (-0.70,  2.95, 5.85, -0.55, 0.78, 0.42, 0.54, 0.44, -0.25, 0.00),  # Stratum 2: lower-mid mossy shelf
        ( 2.60,  6.20, 4.85,  1.20, 0.84, 0.38, 0.50, 0.46,  0.22, 0.00),  # Stratum 3: mid cliff asymmetric bench
        ( 5.85,  9.45, 3.75,  3.00, 0.86, 0.32, 0.44, 0.46, -0.18, 0.00),  # Stratum 4: upper cliff stepped shelf
        ( 9.10, 12.55, 2.55,  4.80, 0.88, 0.25, 0.38, 0.44,  0.10, 0.80),  # Stratum 5: jagged asymmetric crest
    ]
    for si, (yb, yt, xh, zf, mt, jx, jz, bs, xs, cl) in enumerate(strata_specs):
        col_pts += _sculpt_strata_plate(
            mb, yb, yt, xh, zf, Z_BACK, rng,
            mat='limestone', top_mat='limestone_moss',
            moss_top=mt, n_front=11 if si < 3 else 9,
            jag_x=jx, jag_z=jz, brow_step=bs, x_shift=xs, crest_lift=cl,
        )

    # 2. Five Bold Continuous Reclined Vertical Cleavage Ribs sculpted straight up the ~58° sloping face!
    #    Wide at the bottom apron, leaning monotonically BACKWARD (+Z) and tapering smoothly into upper strata!
    rib_specs = [
        # Central hero vertical cleavage spine (y = -4.5 .. +13.4 m, receding z = -1.75 -> +5.55 m!)
        (
            [
                (-4.50, 2.45, 1.95,  0.15, -1.25),
                (-0.40, 2.10, 1.75,  0.08,  0.18),
                ( 3.20, 1.78, 1.50, -0.04,  1.88),
                ( 6.80, 1.42, 1.25, -0.12,  3.62),
                (10.10, 1.02, 0.96, -0.05,  5.20),
                (12.35, 0.62, 0.60,  0.02,  5.95),
            ],
            (0.06, 13.45, 6.28),
        ),
        # Port inner cleavage rib (y = -4.5 .. +10.2 m)
        (
            [
                (-4.50, 2.05, 1.72, -2.95, -1.05),
                (-0.40, 1.72, 1.48, -2.65,  0.42),
                ( 3.20, 1.38, 1.22, -2.20,  2.10),
                ( 6.60, 1.02, 0.96, -1.78,  3.75),
                ( 9.35, 0.62, 0.62, -1.45,  4.98),
            ],
            (-1.32, 10.25, 5.38),
        ),
        # Starboard inner cleavage rib (y = -4.5 .. +10.5 m)
        (
            [
                (-4.50, 2.05, 1.72,  3.00, -1.00),
                (-0.40, 1.74, 1.48,  2.68,  0.45),
                ( 3.20, 1.40, 1.24,  2.25,  2.12),
                ( 6.80, 1.04, 0.96,  1.82,  3.82),
                ( 9.65, 0.64, 0.62,  1.48,  5.08),
            ],
            ( 1.36, 10.55, 5.45),
        ),
        # Port outer flank shoulder buttress rib (y = -4.5 .. +6.8 m)
        (
            [
                (-4.50, 1.85, 1.68, -5.15, -0.35),
                (-0.50, 1.52, 1.40, -4.60,  1.15),
                ( 2.95, 1.15, 1.08, -3.95,  2.70),
                ( 5.85, 0.68, 0.66, -3.35,  4.05),
            ],
            (-3.15, 6.75, 4.45),
        ),
        # Starboard outer flank shoulder buttress rib (y = -4.5 .. +7.0 m)
        (
            [
                (-4.50, 1.85, 1.68,  5.18, -0.30),
                (-0.50, 1.52, 1.40,  4.62,  1.20),
                ( 3.05, 1.15, 1.08,  3.95,  2.75),
                ( 6.05, 0.68, 0.66,  3.35,  4.12),
            ],
            ( 3.15, 6.95, 4.52),
        ),
    ]
    for ri_idx, (r_rings, r_apex) in enumerate(rib_specs):
        col_pts += _sculpt_stepped_crag(
            mb, r_rings, sides=7, rng=rng, mat='limestone', top_mat='limestone_moss',
            col_top=C_LIME_PALE, col_mid=C_LIME_WARM, col_bot=C_LIME_SHADE,
            rot0=0.32 * ri_idx, twist=0.06 if ri_idx % 2 == 0 else -0.06,
            rib_amp=0.16, strata_jog=0.09, moss_cap=0.50, apex_pt=r_apex,
        )

    # 3. Two Flush Recessed Mossy Highland Turf Cushions tucked strictly BEHIND the strata shelf lips!
    #    Seated well back (+Z) on Strata 2 & Strata 3 shelves so they NEVER overhang or protrude forward!
    moss_cushions = [
        ((-1.95, 2.78, 1.75), (1.85, 0.48, 0.85), ( 0,  8, -2), 0.88),
        (( 1.85, 6.02, 3.55), (1.65, 0.46, 0.80), ( 0, -10,  2), 0.88),
    ]
    for ms_c, ms_r, ms_rot, ms_f in moss_cushions:
        col_pts += _sculpt_grounded_terrace(
            mb, ms_c, ms_r, 'limestone_moss',
            C_GRASS_SUN, C_LEDGE_MOSS, C_LIME_WARM, rng,
            subdiv=2, warp=0.14, strata=0.08, flat_top=0.40, base_flare=0.25,
            rot_deg=ms_rot, crag_ribs=5, rib_amp=0.08, moss_cap=ms_f,
        )

    # 4. Two Short Cliff Vines anchored flush to the stepped mossy rock ledges (ZERO floating roots!)
    add_vine_drape(mb, (-2.25, 2.82,  0.22), 2.15, 0.30, (-0.10, 0.0, -1.0), rng, phase=0.22)
    add_vine_drape(mb, ( 2.05, 6.08,  2.05), 1.95, 0.28, ( 0.12, 0.0, -1.0), rng, phase=0.71)

    build(mb)

    col_piece('col_strata_rib', col_pts)
    export_landmark_glb(outdir, 'upper_cliff_strata_rib.glb')


SKYLINE_GENERATORS = [
    gen_cliff_summit_crag_spire,
    gen_cliff_ruin_aqueduct_arch,
    gen_cliffside_pirate_watchpost,
    gen_upper_cliff_strata_rib,
]
