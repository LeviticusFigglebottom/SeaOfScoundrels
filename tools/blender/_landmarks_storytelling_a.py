# Sea of Scoundrels: 3 monumental Sea-of-Thieves-grade storytelling island landmarks (Set A).
# Imported by tools/blender/gen_island_landmarks.py.
# Authored in Godot game coordinates (-Z forward/seaward, +Y up, +X starboard, metres) and
# converted to Blender's Z-up frame on mesh creation via _landmark_common.
import bmesh
import math
import random
from math import sin, cos, pi, sqrt, atan2, radians
from mathutils import Vector, Matrix

from _landmark_common import (
    SEED,
    mul,
    mix,
    jit,
    smooth01,
    C_LIME_PALE,
    C_LIME_WARM,
    C_LIME_MID,
    C_LIME_SHADE,
    C_LIME_DARK,
    C_SEA_MOSS,
    C_LEDGE_MOSS,
    C_GRASS_SUN,
    C_BASALT_TOP,
    C_BASALT_MID,
    C_BASALT_DARK,
    C_BASALT_HOT,
    C_MAGMA_GLOW,
    C_SKULL_BONE,
    C_SKULL_MID,
    C_SKULL_SHADE,
    C_SKULL_CAV,
    C_SKULL_EYE,
    C_TEMPLE_HI,
    C_TEMPLE_MID,
    C_TEMPLE_DARK,
    C_TEMPLE_GOLD,
    C_ROPE,
    C_BRASS,
    T,
    R,
    S,
    M_Y2Z,
    M_Y2X,
    newell,
    MB,
    xf,
    cbox,
    sculpt_stone_block,
    loft,
    lathe,
    tube,
    cyl,
    torus,
    sculpt_rock_mass,
    sculpt_basalt_column,
    add_vine_drape,
    clear_scene,
    build,
    col_piece,
    col_box,
    add_empty,
    export_landmark_glb,
)


# ---------------------------------------------------------------- local sculptural helpers

def _box2(mb, lo, hi, mat, col, ch=0.025, grain=None, skip=()):
    c = ((lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5, (lo[2] + hi[2]) * 0.5)
    sz = (hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2])
    cbox(mb, c, sz, mat, col, ch, grain, skip=skip)


def _cubic_bezier(p0, p1, p2, p3, u):
    """Evaluate a smooth C-infinity cubic Bezier curve at parameter u in [0, 1]."""
    om = 1.0 - u
    return (
        p0 * (om * om * om)
        + p1 * (3.0 * om * om * u)
        + p2 * (3.0 * om * u * u)
        + p3 * (u * u * u)
    )


def _parallel_frames(pts, init_up=None):
    """Compute twist-free parallel-transport (tangent, normal, binormal) frames along a 3D polyline."""
    n = len(pts)
    frames = []
    nrm = None
    for i in range(n):
        p_prev = pts[max(0, i - 1)]
        p_next = pts[min(n - 1, i + 1)]
        tang = p_next - p_prev
        if tang.length < 1e-6:
            tang = Vector((0.0, 1.0, 0.0))
        else:
            tang.normalize()
        if nrm is None:
            ref = Vector(init_up) if init_up is not None else (
                Vector((0.0, 1.0, 0.0)) if abs(tang.y) < 0.88 else Vector((0.0, 0.0, -1.0))
            )
            nrm = ref - tang * ref.dot(tang)
            if nrm.length < 1e-5:
                ref2 = Vector((1.0, 0.0, 0.0)) if abs(tang.x) < 0.8 else Vector((0.0, 0.0, 1.0))
                nrm = ref2 - tang * ref2.dot(tang)
        else:
            nrm = nrm - tang * nrm.dot(tang)
            if nrm.length < 1e-5:
                ref2 = Vector((1.0, 0.0, 0.0)) if abs(tang.x) < 0.8 else Vector((0.0, 1.0, 0.0))
                nrm = ref2 - tang * ref2.dot(tang)
        nrm.normalize()
        bn = tang.cross(nrm).normalized()
        frames.append((tang, nrm, bn))
    return frames


def _sculpt_bevel_ribbon(mb, stations, mat, col_fn, rng, sides=8, closed_caps=(True, True),
                         squarish=0.09, init_up=None):
    """Loft a bold multi-station chiseled stone/beard/arch/horn ribbon with twist-free frames.
    Each station: (center_xyz, r_u, r_v, twist_deg, color_t).
    """
    pts = [Vector(st[0]) for st in stations]
    frames = _parallel_frames(pts, init_up=init_up)
    secs = []
    scols = []
    out_pts = []
    for i, (ctr, ru, rv, tw_deg, ct) in enumerate(stations):
        c = pts[i]
        _, nrm, bn = frames[i]
        ca_t, sa_t = cos(radians(tw_deg)), sin(radians(tw_deg))
        u_vec = bn * ca_t + nrm * sa_t
        v_vec = -bn * sa_t + nrm * ca_t
        ring = []
        for k in range(sides):
            ang = 2.0 * pi * k / float(sides)
            ca, sa = cos(ang), sin(ang)
            sq = 1.0 + squarish * cos(4.0 * ang)
            p = c + u_vec * (ca * ru * sq) + v_vec * (sa * rv * sq)
            ring.append(p)
            out_pts.append(p)
        secs.append(ring)
        scols.append(jit(col_fn(ct), rng, 0.038, 0.014))
    loft(mb, secs, mat, col_fn(0.5), closed=True, caps=closed_caps, mode='flat', scols=scols)
    return out_pts


def _sculpt_tapered_prism(mb, p_bot, p_top, rx_bot, rz_bot, rx_top, rz_top, sides, rng,
                          mat, col_bot, col_top, rings=4, rot_deg=0.0, mid_bulge=0.0,
                          arch_off=(0.0, 0.0, 0.0), apex_pt=None, notch_amp=0.0, jitter=0.10):
    """Angular faceted stone/obsidian blade, crown fin, or volcanic shard with outward normals."""
    pb = Vector(p_bot)
    pt = Vector(p_top)
    aoff = Vector(arch_off)
    axis = pt - pb
    if axis.length < 1e-5:
        axis = Vector((0.0, 1.0, 0.0))
    else:
        axis.normalize()
    ref = Vector((0.0, 0.0, -1.0)) if abs(axis.z) < 0.85 else Vector((1.0, 0.0, 0.0))
    u_ax = axis.cross(ref).normalized()
    v_ax = axis.cross(u_ax).normalized()

    rot0 = radians(rot_deg)
    rib_j = [rng.uniform(1.0 - jitter, 1.0 + jitter) if jitter > 0.0 else 1.0 for _ in range(sides)]
    secs = []
    centers = []
    out_pts = []

    for ri in range(rings):
        t = ri / float(max(1, rings - 1))
        c = pb.lerp(pt, t) + aoff * sin(t * pi)
        centers.append(c)
        bulge = 1.0 + mid_bulge * sin(t * pi) + notch_amp * sin(t * pi * 3.0)
        rx = (rx_bot * (1.0 - t) + rx_top * t) * bulge
        rz = (rz_bot * (1.0 - t) + rz_top * t) * bulge
        ring = []
        for k in range(sides):
            ang = rot0 + 2.0 * pi * k / float(sides)
            rk = rib_j[k]
            p = c + u_ax * (cos(ang) * rx * rk) + v_ax * (sin(ang) * rz * rk)
            ring.append(p)
            out_pts.append(p)
        secs.append(ring)

    def _face_col(pts_f, inside_p, t_h):
        fn = newell(pts_f)
        fn = fn.normalized() if fn.length > 1e-8 else Vector((0.0, 1.0, 0.0))
        fc = sum(pts_f, Vector()) / float(len(pts_f))
        if fn.dot(fc - inside_p) < 0.0:
            fn = -fn
        base = mix(col_bot, col_top, t_h)
        if fn.y > 0.45:
            base = mix(base, col_top, 0.42)
        elif fn.y < -0.25:
            base = mul(base, 0.72)
        return jit(base, rng, 0.045, 0.015)

    mb.newoff()
    for ri in range(rings - 1):
        r0, r1 = secs[ri], secs[ri + 1]
        inside = 0.5 * (centers[ri] + centers[ri + 1])
        t_mid = (ri + 0.5) / float(max(1, rings - 1))
        for k in range(sides):
            kn = (k + 1) % sides
            q = [r0[k], r0[kn], r1[kn], r1[k]]
            mb.fp(q, mat, _face_col(q, inside, t_mid), (1, 0, 0), inside, smooth=False)

    mb.fp(secs[0], mat, mul(col_bot, 0.75), (1, 0, 0), centers[min(1, rings - 1)], smooth=False)

    if apex_pt is not None:
        ap = Vector(apex_pt)
        out_pts.append(ap)
        inside_top = centers[-1] - axis * 0.45
        for k in range(sides):
            kn = (k + 1) % sides
            tri = [secs[-1][k], secs[-1][kn], ap]
            mb.fp(tri, mat, _face_col(tri, inside_top, 1.0), (1, 0, 0), inside_top, smooth=False)
    else:
        mb.fp(secs[-1], mat, _face_col(secs[-1], centers[-2], 1.0), (1, 0, 0), centers[-2], smooth=False)
    return out_pts


def _sculpt_magma_vein(mb, path, widths, out_dirs, rng):
    """Subtle recessed glowing molten magma vein sliver ('glass') tucked inside volcanic cracks."""
    pts = [Vector(p) for p in path]
    n = len(pts)
    ws = widths if isinstance(widths, (list, tuple)) else [widths] * n
    ods = [Vector(d).normalized() for d in out_dirs] if isinstance(out_dirs[0], (list, tuple, Vector)) else [
        Vector(out_dirs).normalized() for _ in range(n)
    ]

    mb.newoff()
    for i in range(n - 1):
        t0 = i / float(max(1, n - 1))
        t1 = (i + 1) / float(max(1, n - 1))
        c0, c1 = pts[i], pts[i + 1]
        tang = c1 - c0
        if tang.length < 1e-6:
            continue
        tang.normalize()
        od0, od1 = ods[i], ods[i + 1]
        s0 = tang.cross(od0)
        if s0.length < 1e-5:
            s0 = Vector((0.0, 0.0, 1.0))
        s0.normalize()
        s1 = tang.cross(od1)
        if s1.length < 1e-5:
            s1 = s0
        s1.normalize()

        w0, w1 = ws[i], ws[i + 1]
        al = c0 - s0 * w0 - od0 * (w0 * 0.45)
        ar = c0 + s0 * w0 - od0 * (w0 * 0.45)
        am = c0 + od0 * (w0 * 0.16)
        bl = c1 - s1 * w1 - od1 * (w1 * 0.45)
        br = c1 + s1 * w1 - od1 * (w1 * 0.45)
        bm = c1 + od1 * (w1 * 0.16)

        h0 = 0.28 + 0.72 * sin(t0 * pi)
        h1 = 0.28 + 0.72 * sin(t1 * pi)
        ce0 = mix(C_BASALT_HOT, C_MAGMA_GLOW, h0 * 0.62)
        ce1 = mix(C_BASALT_HOT, C_MAGMA_GLOW, h1 * 0.62)
        cm0 = mix(C_BASALT_HOT, C_MAGMA_GLOW, 0.65 + 0.35 * h0)
        cm1 = mix(C_BASALT_HOT, C_MAGMA_GLOW, 0.65 + 0.35 * h1)
        inside_pt = 0.5 * (c0 + c1) - 0.5 * (od0 + od1) * 0.85

        mb.fp([al, am, bm, bl], 'glass', [ce0, cm0, cm1, ce1],
              (0, 1, 0), inside_pt, smooth=False)
        mb.fp([am, ar, br, bm], 'glass', [cm0, ce0, ce1, cm1],
              (0, 1, 0), inside_pt, smooth=False)


def _basalt_col_hull_pts(base_pos, height, radius, sides, tilt_x, tilt_z):
    """Outer hull sample points for a sculpt_basalt_column to feed col_piece cleanly."""
    bx, by, bz = base_pos
    pts = []
    for t in (0.0, 0.45, 0.90, 1.0):
        y = by + t * height
        rad_t = radius * (1.04 - 0.16 * t) * (0.86 if t > 0.92 else 1.0)
        ox = bx + sin(radians(tilt_x)) * t * height
        oz = bz + sin(radians(tilt_z)) * t * height
        for k in range(sides):
            ang = 2.0 * pi * k / float(sides)
            pts.append(Vector((ox + rad_t * cos(ang), y, oz + rad_t * sin(ang))))
    return pts


def _sculpt_idol_eye_cavity(mb, cx, cy, cz, side_sgn, rng):
    """Deep recessed dark stone eye socket + angular temple orbital bezel + blazing turquoise rune core."""
    cant_deg = -14.0 * side_sgn
    rx_o, ry_o = 0.44, 0.34
    rx_i, ry_i = 0.28, 0.20
    segs = 8

    def ring_pts(rx, ry, z_off):
        pts = []
        rot = R('Z', cant_deg)
        for k in range(segs):
            ang = 2.0 * pi * k / float(segs)
            ca, sa = cos(ang), sin(ang)
            y_m = sa * (0.80 if sa > 0.15 else 1.05)
            x_m = ca * (1.08 if abs(sa) < 0.45 else 0.92)
            local = rot @ Vector((x_m * rx, y_m * ry, 0.0))
            pts.append(Vector((cx + local.x, cy + local.y, cz + z_off)))
        return pts

    # 1. Deep pitch-dark carved eye recess receding +0.58 m into the stone cranium
    r_front = ring_pts(rx_i * 1.02, ry_i * 1.02, -0.08)
    r_back = ring_pts(rx_i * 0.72, ry_i * 0.72, 0.52)
    for k in range(segs):
        k1 = (k + 1) % segs
        q = [r_front[k], r_front[k1], r_back[k1], r_back[k]]
        q_mid = sum(q, Vector()) * 0.25
        axis_mid = Vector((cx, cy, q_mid.z))
        out_pt = q_mid + (q_mid - axis_mid).normalized() * 1.5
        mb.fp(q, 'basalt', C_SKULL_CAV, (0, 0, 1), out_pt, smooth=False)
    back_c = Vector((cx, cy, cz + 0.56))
    for k in range(segs):
        k1 = (k + 1) % segs
        mb.fp([back_c, r_back[k1], r_back[k]], 'basalt', C_SKULL_CAV, (1, 0, 0),
              Vector((cx, cy, cz + 1.8)), smooth=False)

    # 2. Chiseled angular temple orbital rim collar framing the socket
    r_outer = ring_pts(rx_o, ry_o, 0.16)
    r_crest = ring_pts(rx_i * 1.24, ry_i * 1.24, -0.14)
    for ra, rb in ((r_outer, r_crest), (r_crest, r_front)):
        for k in range(segs):
            k1 = (k + 1) % segs
            q = [ra[k], ra[k1], rb[k1], rb[k]]
            qm = sum(q, Vector()) * 0.25
            rc = C_SKULL_BONE if qm.y > cy + 0.06 else C_TEMPLE_MID
            mb.fp(q, 'skull_stone', jit(rc, rng, 0.04), (1, 0, 0), Vector((cx, cy, cz + 1.4)), smooth=False)

    # 3. Blazing turquoise emissive sea-rune diamond eye core ('skull_glow')
    eye_ctr = Vector((cx, cy - 0.01, cz + 0.14))
    with xf(mb, T(eye_ctr) @ R('Z', cant_deg)):
        prof = [
            (0.0, -0.14), (0.14, -0.05), (0.19, 0.0), (0.14, 0.06), (0.0, 0.15),
        ]
        lathe(mb, prof, 6, 'skull_glow', C_SKULL_EYE, smooth=False)
        for sx in (-1.0, 1.0):
            with xf(mb, T(sx * 0.14, 0.0, -0.02) @ R('Z', -sx * 68.0)):
                p_w = [(0.0, -0.05), (0.065, 0.0), (0.0, 0.14)]
                lathe(mb, p_w, 4, 'skull_glow', jit(C_SKULL_EYE, rng, 0.06), smooth=False)


def _sculpt_bone_rib(mb, pts, rads_z, rads_r, rng, side_sgn=1.0, broken=False):
    """Colossal curved calcified leviathan rib with flattened oval bone-ridge cross-section."""
    vpts = [Vector(p) for p in pts]
    n = len(vpts)
    frames = _parallel_frames(vpts, init_up=(0.0, 0.0, 1.0))
    sides = 6
    secs = []
    scols = []
    out_pts = []

    for i in range(n):
        t = i / float(max(1, n - 1))
        c = vpts[i]
        tang, nrm, bn = frames[i]
        z_ax = Vector((0.0, 0.0, 1.0)) - tang * tang.z
        if z_ax.length < 1e-4:
            z_ax = bn
        else:
            z_ax.normalize()
        r_ax = z_ax.cross(tang).normalized()
        out_hint = Vector((side_sgn, 0.35 * t, 0.0))
        if r_ax.dot(out_hint) < 0.0:
            r_ax = -r_ax

        rz = rads_z[i]
        rr = rads_r[i]
        swell = 1.0 + 0.05 * sin(t * pi * 4.0)
        ring = []
        for k in range(sides):
            ang = 2.0 * pi * k / float(sides)
            ca, sa = cos(ang), sin(ang)
            # Chunky flattened bone cross-section with proud outer dorsal bone keel (+r_ax)
            keel = 1.26 if ca > 0.45 else (0.84 if ca < -0.45 else 1.02)
            p = c + r_ax * (ca * rr * keel * swell) + z_ax * (sa * rz * swell)
            ring.append(p)
            out_pts.append(p)
        secs.append(ring)

        # Smooth coastal weathering: dark sand/moss-stained buried root -> warm ivory -> sun-bleached top
        ht = smooth01((c.y + 1.40) / 6.20)
        col_low = mix(C_SKULL_SHADE, C_SEA_MOSS, 0.20)
        if ht < 0.45:
            col_i = mix(col_low, C_SKULL_MID, ht / 0.45)
        else:
            col_i = mix(C_SKULL_MID, C_SKULL_BONE, (ht - 0.45) / 0.55)
        if broken and i == n - 1:
            col_i = mix(col_i, C_SKULL_SHADE, 0.45)
        scols.append(jit(col_i, rng, 0.04, 0.014))

    loft(mb, secs, 'skull_stone', C_SKULL_BONE, closed=True, caps=(True, True), mode='flat', scols=scols)
    return out_pts


def _sculpt_conical_fang(mb, base_pos, tip_pos, r_base, curve_off, rng, chipped=False):
    """Curved tapered calcified conical leviathan tooth rising from split jawbone."""
    pb = Vector(base_pos)
    pt = Vector(tip_pos)
    coff = Vector(curve_off)
    if chipped:
        pt = pb.lerp(pt, 0.58)
    segs = 3
    sides = 5
    pts = [pb.lerp(pt, i / float(segs)) + coff * sin(pi * i / float(segs)) for i in range(segs + 1)]
    rads = [r_base * (1.0 - 0.80 * (i / float(segs)) ** 1.12) for i in range(segs + 1)]
    if not chipped:
        rads[-1] = max(0.024, r_base * 0.14)
    scols = [
        jit(C_SKULL_SHADE, rng, 0.04),
        jit(C_SKULL_MID, rng, 0.04),
        jit(mix(C_SKULL_MID, C_SKULL_BONE, 0.72), rng, 0.03),
        jit(C_SKULL_SHADE if chipped else C_SKULL_BONE, rng, 0.03),
    ]
    tube(mb, pts, rads, sides, 'skull_stone', C_SKULL_BONE, caps=(True, True), mode='flat', scols=scols)


# ================================================================ 1. ANCIENT SEA GOD IDOL

def gen_ancient_sea_god_idol(outdir):
    """Monumental ~10.5 m tall mossy weathered carved stone ocean-deity / pirate-temple totem statue
    facing -Z, with stepped ashlar plinth rooted to y = -1.8 m, antique gold compass chest medallion,
    expressive carved bearded visage, glowing turquoise rune eyes, jagged sea-crown & hanging vines."""
    clear_scene()
    rng = random.Random(SEED + 811)
    mb = MB('AncientSeaGodIdol', seed=811)
    plinth_pts = []
    body_pts = []

    # 1. Stepped Carved Ashlar Stone Plinth (grounded cleanly down to y = -1.80 m!)
    plinth_pts += _sculpt_tapered_prism(
        mb, (0.0, -1.80, 0.0), (0.0, 0.34, 0.0),
        2.90, 2.60, 2.52, 2.24, 8, rng,
        mat='temple_stone',
        col_bot=mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.38),
        col_top=mix(C_TEMPLE_MID, C_SEA_MOSS, 0.20),
        rings=4, rot_deg=22.5, jitter=0.05,
    )

    # 4 low grounded mossy limestone rubble anchor clusters tucked snugly against the plinth corners
    corner_rocks = [
        ((-2.02, -0.78, -1.62), (1.02, 1.15, 0.94), ( 4,  18, -6), 0.78),
        (( 2.02, -0.75, -1.65), (1.00, 1.12, 0.92), (-3, -24,  6), 0.74),
        ((-2.06, -0.74,  1.56), (1.06, 1.18, 0.98), ( 5, -16,  5), 0.80),
        (( 2.04, -0.76,  1.54), (1.02, 1.15, 0.96), (-4,  28, -5), 0.76),
    ]
    for ctr, rad, rot_d, mc in corner_rocks:
        plinth_pts += sculpt_rock_mass(
            mb, ctr, rad, 'limestone_moss',
            C_LEDGE_MOSS, C_LIME_MID, C_LIME_DARK, rng,
            subdiv=1, warp=0.16, strata=0.12, flat_top=0.50, base_flare=0.22,
            rot_deg=rot_d, crag_ribs=5, rib_amp=0.09, moss_cap=mc,
        )

    # 1b. Tier 1 stepped ashlar masonry pedestal (y = 0.24 .. 1.08 m)
    _box2(mb, (-2.05, 0.24, -1.78), (2.05, 1.06, 1.78),
          'temple_stone', mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.22), 0.06)
    tier1_blocks = [
        ((-1.42, 0.66, -1.72), (1.38, 0.80, 0.56)),
        (( 0.00, 0.66, -1.74), (1.42, 0.82, 0.58)),
        (( 1.42, 0.66, -1.72), (1.38, 0.80, 0.56)),
        ((-1.42, 0.66,  1.70), (1.38, 0.80, 0.56)),
        (( 0.00, 0.66,  1.72), (1.42, 0.82, 0.58)),
        (( 1.42, 0.66,  1.70), (1.38, 0.80, 0.56)),
        ((-1.98, 0.66, -0.82), (0.58, 0.80, 1.24)),
        ((-1.98, 0.66,  0.82), (0.58, 0.80, 1.24)),
        (( 1.98, 0.66, -0.82), (0.58, 0.80, 1.24)),
        (( 1.98, 0.66,  0.82), (0.58, 0.80, 1.24)),
    ]
    for bctr, bsz in tier1_blocks:
        sculpt_stone_block(mb, bctr, bsz, 'temple_stone', C_TEMPLE_MID, rng,
                           chip=0.055, moss_col=C_LEDGE_MOSS)
        hx, hy, hz = bsz[0] * 0.5, bsz[1] * 0.5, bsz[2] * 0.5
        plinth_pts.extend([
            Vector((bctr[0] - hx, bctr[1] - hy, bctr[2] - hz)),
            Vector((bctr[0] + hx, bctr[1] + hy, bctr[2] + hz)),
        ])

    # Seaward ceremonial offering step & carved altar apron (z = -2.56 .. -1.72 m)
    _box2(mb, (-1.42, -1.78, -2.56), (1.42, 0.52, -1.72),
          'temple_stone', mix(C_TEMPLE_MID, C_SEA_MOSS, 0.24), 0.06)
    sculpt_stone_block(mb, (0.0, 0.60, -2.18), (2.48, 0.26, 0.78), 'temple_stone',
                       C_TEMPLE_HI, rng, chip=0.045, moss_col=C_LEDGE_MOSS)
    cbox(mb, (0.0, 0.62, -2.55), (1.68, 0.085, 0.055), 'brass', C_TEMPLE_GOLD, 0.012)
    cbox(mb, (0.0, 0.62, -2.57), (0.20, 0.20, 0.055), 'brass', C_BRASS, 0.012, M=R('Z', 45))
    for sgn in (-1.0, 1.0):
        sculpt_stone_block(mb, (sgn * 1.66, 0.52, -2.02), (0.56, 0.92, 0.72), 'temple_stone',
                           C_TEMPLE_MID, rng, chip=0.05, M=R('X', -12), moss_col=C_LEDGE_MOSS)
        plinth_pts.append(Vector((sgn * 1.96, 0.95, -2.42)))
    plinth_pts.extend([Vector((-1.45, -1.78, -2.58)), Vector((1.45, 0.75, -2.58))])

    # 1c. Tier 2 stepped plinth & overhanging beveled cornice platform (y = 1.02 .. 1.70 m)
    _box2(mb, (-1.72, 1.02, -1.48), (1.72, 1.50, 1.48), 'temple_stone', C_TEMPLE_MID, 0.05)
    for sx in (-0.92, 0.92):
        for sz in (-0.78, 0.78):
            sculpt_stone_block(mb, (sx, 1.56, sz), (1.88, 0.28, 1.62), 'temple_stone',
                               C_TEMPLE_HI, rng, chip=0.04, moss_col=C_LEDGE_MOSS)
    sculpt_rock_mass(mb, (-1.45, 1.72, 1.08), (0.68, 0.26, 0.62), 'limestone_moss',
                     C_LEDGE_MOSS, C_SEA_MOSS, C_LIME_SHADE, rng,
                     subdiv=1, warp=0.16, flat_top=0.45, moss_cap=0.88)
    sculpt_rock_mass(mb, (1.42, 1.70, -1.12), (0.62, 0.24, 0.56), 'limestone_moss',
                     C_LEDGE_MOSS, C_SEA_MOSS, C_LIME_SHADE, rng,
                     subdiv=1, warp=0.16, flat_top=0.45, moss_cap=0.85)
    plinth_pts.extend([
        Vector((-1.92, 1.70, -1.65)), Vector((1.92, 1.70, -1.65)),
        Vector((-1.92, 1.70,  1.65)), Vector((1.92, 1.70,  1.65)),
    ])

    # 2. Massive Monolithic Carved Stone Torso & Broad Heroic Shoulders (y = 1.62 .. 5.52 m)
    torso_specs = [
        (1.62, 1.44, 1.15,  0.00, mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.26)),
        (2.38, 1.48, 1.20, -0.02, C_TEMPLE_MID),
        (3.25, 1.66, 1.28, -0.05, C_TEMPLE_MID),
        (4.25, 1.88, 1.34, -0.08, C_TEMPLE_HI),
        (5.05, 1.94, 1.28, -0.04, C_TEMPLE_HI),
        (5.52, 1.44, 1.16, -0.04, C_TEMPLE_MID),
    ]
    torso_secs = []
    torso_cols = []
    for y, rx, rz, zoff, tcol in torso_specs:
        ring = []
        for k in range(8):
            ang = radians(22.5) + 2.0 * pi * k / 8.0
            ca, sa = cos(ang), sin(ang)
            sq = 1.06 if abs(ca) > 0.5 and abs(sa) > 0.5 else 1.0
            v = Vector((ca * rx * sq, y, zoff + sa * rz * sq))
            ring.append(v)
            body_pts.append(v)
        torso_secs.append(ring)
        torso_cols.append(jit(tcol, rng, 0.04, 0.015))
    loft(mb, torso_secs, 'temple_stone', C_TEMPLE_MID, closed=True, caps=(True, True),
         mode='flat', scols=torso_cols)

    # Carved waist girdle, antique gold buckle diamond & sculpted pectoral slabs
    cbox(mb, (0.0, 2.08, -1.18), (2.52, 0.34, 0.26), 'temple_stone', C_TEMPLE_DARK, 0.04)
    cbox(mb, (0.0, 2.08, -1.32), (0.44, 0.36, 0.08), 'brass', C_TEMPLE_GOLD, 0.015, M=R('Z', 45))
    for sgn in (-1.0, 1.0):
        cbox(mb, (sgn * 0.90, 4.46, -1.18), (1.02, 0.66, 0.30), 'temple_stone',
             C_TEMPLE_HI, 0.055, M=R('Y', -sgn * 14.0) @ R('X', 8.0))
        body_pts += _sculpt_tapered_prism(
            mb, (sgn * 1.96, 4.02, -0.04), (sgn * 2.14, 5.26, -0.02),
            0.76, 1.08, 0.62, 0.92, 6, rng,
            mat='temple_stone', col_bot=C_TEMPLE_MID, col_top=C_TEMPLE_HI,
            rings=3, rot_deg=15.0 * sgn, jitter=0.06,
        )
        cbox(mb, (sgn * 2.16, 5.26, -0.04), (0.76, 0.24, 1.38), 'temple_stone',
             C_TEMPLE_HI, 0.045, M=R('Z', -sgn * 16.0))
        sculpt_rock_mass(
            mb, (sgn * 1.94, 5.40, 0.12), (0.62, 0.24, 0.66), 'limestone_moss',
            C_LEDGE_MOSS, C_SEA_MOSS, C_TEMPLE_MID, rng,
            subdiv=1, warp=0.15, flat_top=0.45, moss_cap=0.88,
        )

        # Stylized monolithic totem arms curving down flanks & folding across belly
        arm_stations = [
            ((sgn * 1.96, 4.55, -0.18), 0.44, 0.48, 0.0, 0.72),
            ((sgn * 2.00, 3.60, -0.26), 0.40, 0.44, 0.0, 0.56),
            ((sgn * 1.86, 2.72, -0.48), 0.42, 0.44, 0.0, 0.48),
            ((sgn * 1.32, 2.60, -1.06), 0.36, 0.38, 0.0, 0.64),
            ((sgn * 0.58, 2.54, -1.42), 0.34, 0.36, 0.0, 0.85),
        ]
        body_pts += _sculpt_bevel_ribbon(
            mb, arm_stations, 'temple_stone',
            lambda t: mix(C_TEMPLE_DARK, C_TEMPLE_HI, 0.25 + 0.75 * t),
            rng, sides=6, squarish=0.12,
        )
        for ki in range(3):
            cbox(mb, (sgn * (0.48 + ki * 0.12), 2.54, -1.68), (0.09, 0.34, 0.12),
                 'skull_stone', C_TEMPLE_HI, 0.018)

    # Ceremonial carved stone & tarnished gold sea-scepter bar clutched across waist
    with xf(mb, T(0.0, 2.54, -1.52) @ M_Y2X):
        cyl(mb, 0.12, -1.28, 1.28, 6, 'temple_stone', C_TEMPLE_DARK, False, 0.02)
        for sx in (-1.22, 1.22):
            cyl(mb, 0.17, sx - 0.14, sx + 0.14, 6, 'brass', C_TEMPLE_GOLD, False, 0.025)

    # 3. Inlaid Tarnished Antique Gold Sun / Compass Ritual Medallion on Chest (y = 3.74, z = -1.36)
    med_ctr = Vector((0.0, 3.74, -1.36))
    with xf(mb, T(med_ctr)):
        with xf(mb, M_Y2Z):
            cyl(mb, 0.80, -0.10, 0.16, 12, 'temple_stone', C_TEMPLE_DARK, False, 0.025)
        with xf(mb, T(0.0, 0.0, -0.09) @ M_Y2Z):
            torus(mb, 0.68, 0.072, 12, 6, 'brass', C_TEMPLE_GOLD, False)
            torus(mb, 0.34, 0.044, 10, 5, 'brass', C_BRASS, False)
        for k in range(8):
            ang = k * 45.0
            is_card = (k % 2 == 0)
            r_len = 0.78 if is_card else 0.56
            r_w = 0.115 if is_card else 0.075
            col_r = C_TEMPLE_GOLD if is_card else C_BRASS
            with xf(mb, R('Z', ang)):
                ray_pts = [
                    (0.0, 0.0, -0.11),
                    (-r_w, r_len * 0.34, -0.10),
                    (0.0, r_len, -0.09),
                    (r_w, r_len * 0.34, -0.10),
                ]
                apex_f = Vector((0.0, r_len * 0.34, -0.175))
                ctr_in = Vector((0.0, r_len * 0.34, 0.15))
                for rk in range(4):
                    p0 = Vector(ray_pts[rk])
                    p1 = Vector(ray_pts[(rk + 1) % 4])
                    mb.fp([p0, p1, apex_f], 'brass', jit(col_r, rng, 0.05), (0, 1, 0), ctr_in, smooth=False)
        with xf(mb, T(0.0, 0.0, -0.11) @ M_Y2Z):
            cyl(mb, 0.21, -0.04, 0.09, 8, 'brass', C_TEMPLE_GOLD, False, 0.025, 0.14)
        with xf(mb, T(0.0, 0.0, -0.17) @ M_Y2Z):
            cyl(mb, 0.085, -0.02, 0.06, 6, 'skull_glow', C_SKULL_EYE, False, 0.015, 0.03)

    gorget_pts = [
        (-1.12, 5.14, -0.90), (-0.64, 4.92, -1.26), (0.0, 4.82, -1.38),
        ( 0.64, 4.92, -1.26), ( 1.12, 5.14, -0.90),
    ]
    tube(mb, gorget_pts, [0.065, 0.085, 0.095, 0.085, 0.065], 6, 'brass', C_TEMPLE_GOLD, mode='flat')

    # 4. Expressive Stylized Angular Carved Bearded Sea-God Visage (y = 5.36 .. 8.28 m, facing -Z)
    #    Broadened forward face monolith so brow, cheeks, and beard meld seamlessly from every side view!
    head_specs = [
        (5.36, 1.22, 1.24, -0.08, C_TEMPLE_MID),
        (6.05, 1.28, 1.34, -0.14, C_TEMPLE_HI),
        (6.85, 1.36, 1.38, -0.16, C_TEMPLE_HI),
        (7.62, 1.40, 1.40, -0.14, C_TEMPLE_HI),
        (8.26, 1.34, 1.32, -0.06, C_TEMPLE_MID),
    ]
    head_secs = []
    head_cols = []
    for y, rx, rz, zoff, hcol in head_specs:
        ring = []
        for k in range(8):
            ang = radians(22.5) + 2.0 * pi * k / 8.0
            ca, sa = cos(ang), sin(ang)
            sq = 1.05 if abs(ca) > 0.5 and abs(sa) > 0.5 else 1.0
            v = Vector((ca * rx * sq, y, zoff + sa * rz * sq))
            ring.append(v)
            body_pts.append(v)
        head_secs.append(ring)
        head_cols.append(jit(hcol, rng, 0.035, 0.015))
    loft(mb, head_secs, 'temple_stone', C_TEMPLE_HI, closed=True, caps=(True, True),
         mode='flat', scols=head_cols)

    # 4a. Bold overhanging furrowed V-brow arch ('skull_stone' highlights!)
    brow_stations = [
        ((-1.42, 7.36, -0.82), 0.24, 0.24, 0.0, 0.25),
        ((-1.04, 7.64, -1.44), 0.28, 0.26, 0.0, 0.65),
        ((-0.46, 7.62, -1.66), 0.30, 0.25, 0.0, 0.92),
        (( 0.00, 7.32, -1.74), 0.28, 0.27, 0.0, 1.00),
        (( 0.46, 7.62, -1.66), 0.30, 0.25, 0.0, 0.92),
        (( 1.04, 7.64, -1.44), 0.28, 0.26, 0.0, 0.65),
        (( 1.42, 7.36, -0.82), 0.24, 0.24, 0.0, 0.25),
    ]
    body_pts += _sculpt_bevel_ribbon(
        mb, brow_stations, 'skull_stone',
        lambda t: mix(C_TEMPLE_MID, C_SKULL_BONE, 0.30 + 0.70 * t),
        rng, sides=6, squarish=0.14, init_up=(0.0, 1.0, 0.0),
    )

    # 4b. Deep recessed dark eye sockets + blazing turquoise 'skull_glow' emissive rune cores!
    eye_l = (-0.56, 6.92, -1.44)
    eye_r = ( 0.56, 6.92, -1.44)
    _sculpt_idol_eye_cavity(mb, eye_l[0], eye_l[1], eye_l[2], -1.0, rng)
    _sculpt_idol_eye_cavity(mb, eye_r[0], eye_r[1], eye_r[2],  1.0, rng)

    # 4c. Bold angular Moai/ocean-deity carved stone nose & flared nostrils + high cheekbones
    nose_stations = [
        ((0.0, 7.36, -1.60), 0.16, 0.18, 0.0, 0.65),
        ((0.0, 6.86, -1.68), 0.18, 0.24, 0.0, 0.85),
        ((0.0, 6.36, -1.80), 0.24, 0.26, 0.0, 1.00),
    ]
    _sculpt_bevel_ribbon(
        mb, nose_stations, 'skull_stone',
        lambda t: mix(C_TEMPLE_HI, C_SKULL_BONE, t),
        rng, sides=6, squarish=0.16, init_up=(0.0, 0.0, -1.0),
    )
    for sgn in (-1.0, 1.0):
        cbox(mb, (sgn * 0.24, 6.40, -1.62), (0.22, 0.22, 0.24), 'skull_stone', C_TEMPLE_HI, 0.035)
        cheek_st = [
            ((sgn * 1.34, 7.22, -0.96), 0.22, 0.24, 0.0, 0.35),
            ((sgn * 1.20, 6.46, -1.40), 0.25, 0.25, 0.0, 0.85),
            ((sgn * 0.72, 6.32, -1.56), 0.20, 0.18, 0.0, 0.95),
        ]
        _sculpt_bevel_ribbon(
            mb, cheek_st, 'skull_stone',
            lambda t: mix(C_TEMPLE_MID, C_SKULL_BONE, 0.25 + 0.65 * t),
            rng, sides=6, squarish=0.10,
        )

    # 4d. Stern dark carved mouth recess + sweeping curled stone moustache & cascading wave-beard!
    cbox(mb, (0.0, 5.86, -1.40), (0.92, 0.28, 0.36), 'basalt', C_SKULL_CAV, 0.03)
    for sgn in (-1.0, 1.0):
        stache = [
            ((sgn * 0.06, 6.16, -1.66), 0.18, 0.17, 0.0, 1.00),
            ((sgn * 0.48, 6.08, -1.66), 0.20, 0.18, 0.0, 0.92),
            ((sgn * 0.92, 5.76, -1.52), 0.19, 0.18, 0.0, 0.75),
            ((sgn * 1.12, 5.36, -1.40), 0.16, 0.16, 0.0, 0.55),
            ((sgn * 0.90, 5.18, -1.46), 0.12, 0.12, 0.0, 0.68),
        ]
        _sculpt_bevel_ribbon(
            mb, stache, 'skull_stone',
            lambda t: mix(C_TEMPLE_MID, C_SKULL_BONE, 0.35 + 0.65 * t),
            rng, sides=6, squarish=0.12,
        )

    # 5 cascading sculpted curled stone beard locks (clearing gold chest medallion cleanly!)
    beard_center = [
        ((0.0, 5.66, -1.56), 0.34, 0.26, 0.0, 0.95),
        ((0.0, 5.24, -1.66), 0.30, 0.26, 0.0, 1.00),
        ((0.0, 4.84, -1.60), 0.22, 0.20, 0.0, 0.85),
        ((0.0, 4.50, -1.48), 0.10, 0.10, 0.0, 0.65),
    ]
    _sculpt_bevel_ribbon(
        mb, beard_center, 'skull_stone',
        lambda t: mix(C_TEMPLE_MID, C_SKULL_BONE, 0.30 + 0.70 * t),
        rng, sides=6, squarish=0.14, init_up=(0.0, 0.0, -1.0),
    )
    for sgn in (-1.0, 1.0):
        beard_in = [
            ((sgn * 0.42, 5.72, -1.50), 0.24, 0.22, 0.0, 0.88),
            ((sgn * 0.52, 5.26, -1.58), 0.22, 0.20, 0.0, 0.92),
            ((sgn * 0.66, 4.86, -1.52), 0.17, 0.16, 0.0, 0.76),
            ((sgn * 0.84, 4.78, -1.44), 0.11, 0.11, 0.0, 0.62),
        ]
        _sculpt_bevel_ribbon(
            mb, beard_in, 'temple_stone',
            lambda t: mix(C_TEMPLE_MID, C_SKULL_BONE, 0.20 + 0.65 * t),
            rng, sides=6, squarish=0.12,
        )
        beard_out = [
            ((sgn * 0.86, 5.88, -1.28), 0.22, 0.20, 0.0, 0.70),
            ((sgn * 0.98, 5.42, -1.26), 0.19, 0.18, 0.0, 0.75),
            ((sgn * 1.10, 5.02, -1.16), 0.14, 0.14, 0.0, 0.58),
        ]
        _sculpt_bevel_ribbon(
            mb, beard_out, 'temple_stone',
            lambda t: mix(C_TEMPLE_DARK, C_TEMPLE_HI, 0.30 + 0.65 * t),
            rng, sides=6, squarish=0.10,
        )
        # Carved Atlantean sea-fin ear ornaments + antique gold ear-spools
        _sculpt_tapered_prism(
            mb, (sgn * 1.34, 6.26, -0.18), (sgn * 1.56, 7.12, -0.05),
            0.18, 0.34, 0.10, 0.44, 5, rng,
            mat='temple_stone', col_bot=C_TEMPLE_MID, col_top=C_TEMPLE_HI,
            rings=3, apex_pt=(sgn * 1.66, 7.28, 0.05), jitter=0.05,
        )
        with xf(mb, T(sgn * 1.46, 6.52, -0.22) @ M_Y2X):
            cyl(mb, 0.15, -0.08, 0.08, 8, 'brass', C_TEMPLE_GOLD, False, 0.02)

    # 5. Jagged Sea-Crown / Trident-Fin Headdress Crest (y = 7.94 .. 10.55 m!)
    body_pts += _sculpt_tapered_prism(
        mb, (0.0, 7.94, -0.06), (0.0, 8.62, -0.06),
        1.44, 1.42, 1.56, 1.50, 8, rng,
        mat='temple_stone', col_bot=C_TEMPLE_MID, col_top=C_TEMPLE_HI,
        rings=3, rot_deg=22.5, jitter=0.0,
    )
    # Flush inlaid tarnished antique gold diadem band + front diamond emblem
    diadem_band = []
    for k in range(9):
        ang = radians(22.5) + 2.0 * pi * (k % 8) / 8.0
        diadem_band.append((cos(ang) * 1.53, 8.28, -0.06 + sin(ang) * 1.48))
    tube(mb, diadem_band, 0.068, 6, 'brass', C_TEMPLE_GOLD, caps=(False, False), mode='flat')
    cbox(mb, (0.0, 8.30, -1.52), (0.34, 0.34, 0.12), 'brass', C_BRASS, 0.02, M=R('Z', 45))

    # Central hero symmetric trident crest blade peaking cleanly at y = 10.55 m!
    body_pts += _sculpt_tapered_prism(
        mb, (0.0, 8.46, -0.34), (0.0, 10.12, -0.38),
        0.46, 0.36, 0.24, 0.20, 6, rng,
        mat='temple_stone', col_bot=C_TEMPLE_MID, col_top=C_SKULL_BONE,
        rings=4, rot_deg=0.0, notch_amp=0.10, apex_pt=(0.0, 10.55, -0.40), jitter=0.0,
    )
    # Centered flush inlaid antique gold trident spine & crossbar
    cbox(mb, (0.0, 9.38, -0.62), (0.11, 1.24, 0.08), 'brass', C_TEMPLE_GOLD, 0.014)
    cbox(mb, (0.0, 9.18, -0.60), (0.54, 0.11, 0.08), 'brass', C_TEMPLE_GOLD, 0.014)

    for sgn in (-1.0, 1.0):
        body_pts += _sculpt_tapered_prism(
            mb, (sgn * 0.72, 8.44, -0.28), (sgn * 1.06, 9.52, -0.22),
            0.34, 0.30, 0.16, 0.16, 5, rng,
            mat='temple_stone', col_bot=C_TEMPLE_MID, col_top=C_TEMPLE_HI,
            rings=4, rot_deg=18.0 * sgn, arch_off=(sgn * 0.12, 0.0, -0.06),
            notch_amp=0.08, apex_pt=(sgn * 1.16, 9.92, -0.20), jitter=0.05,
        )
        body_pts += _sculpt_tapered_prism(
            mb, (sgn * 1.24, 8.26, -0.08), (sgn * 1.88, 8.95, 0.10),
            0.34, 0.36, 0.15, 0.18, 5, rng,
            mat='temple_stone', col_bot=C_TEMPLE_DARK, col_top=C_TEMPLE_HI,
            rings=4, rot_deg=30.0 * sgn, arch_off=(sgn * 0.08, 0.12, 0.0),
            apex_pt=(sgn * 2.12, 9.18, 0.16), jitter=0.05,
        )

    body_pts += _sculpt_tapered_prism(
        mb, (0.0, 8.42, 0.56), (0.0, 9.42, 0.88),
        0.40, 0.36, 0.18, 0.18, 5, rng,
        mat='temple_stone', col_bot=C_TEMPLE_MID, col_top=C_TEMPLE_HI,
        rings=3, apex_pt=(0.0, 9.78, 0.98), jitter=0.05,
    )
    sculpt_rock_mass(
        mb, (-0.58, 8.64, 0.34), (0.68, 0.24, 0.56), 'limestone_moss',
        C_GRASS_SUN, C_LEDGE_MOSS, C_TEMPLE_MID, rng,
        subdiv=1, warp=0.16, flat_top=0.45, moss_cap=0.88,
    )
    sculpt_rock_mass(
        mb, (0.62, 8.62, 0.24), (0.60, 0.22, 0.52), 'limestone_moss',
        C_LEDGE_MOSS, C_SEA_MOSS, C_TEMPLE_MID, rng,
        subdiv=1, warp=0.16, flat_top=0.45, moss_cap=0.84,
    )

    # 6. 4 Hanging Jungle Vines ('foliage' with UV2 wind weights!) framing crown & shoulders
    vine_specs = [
        ((-1.60, 8.54, -0.52), 2.45, 0.28, (-0.48, 0.0, -0.88), 0.12),
        (( 1.54, 8.48, -0.58), 2.05, 0.24, ( 0.44, 0.0, -0.90), 0.39),
        ((-2.14, 5.14, -0.62), 2.70, 0.32, (-0.54, 0.0, -0.84), 0.67),
        (( 2.06, 5.08,  0.48), 2.30, 0.28, ( 0.60, 0.0,  0.80), 0.89),
    ]
    for anc, vlen, vw, vdir, vph in vine_specs:
        add_vine_drape(mb, anc, vlen, vw, vdir, rng, phase=vph)

    build(mb)

    add_empty('Lantern_IdolEyeL', (-0.56, 6.92, -1.58))
    add_empty('Lantern_IdolEyeR', ( 0.56, 6.92, -1.58))

    col_piece('col_idol_plinth', plinth_pts)
    col_piece('col_idol_body', body_pts)
    export_landmark_glb(outdir, 'ancient_sea_god_idol.glb')


# ================================================================ 2. VOLCANIC OBSIDIAN ARCH

def gen_volcanic_obsidian_arch(outdir):
    """Dramatic ~16.5 m wide, ~13.0 m tall jagged black-obsidian volcanic rock portal arch spanning
    an open walkable ~8.2 m wide x ~8.0 m high central underpass, with twin basalt column piers
    rooted to y = -2.6 m, radially wedged obsidian voussoirs, spiked volcanic keystone ridge crest,
    and recessed glowing molten magma veins."""
    clear_scene()
    rng = random.Random(SEED + 827)
    mb = MB('VolcanicObsidianArch', seed=827)
    pts_l = []
    pts_r = []

    # 1. Twin Flared Hexagonal/Pentagonal Volcanic Basalt Pillar Piers (rooted cleanly to y = -2.60 m!)
    #    Strictly keeps inner portal clearance |x| >= 4.25 across y in [0, 8.0] and total width ~16.5 m!
    #    Tuple: (bx, by, bz, height, radius, sides, tilt_x, tilt_z)
    left_cols = [
        (-6.12, -2.60,  0.04, 11.45, 1.12, 6,  3.8, -0.8),
        (-5.98, -2.60, -1.18, 10.85, 0.96, 5,  3.4,  2.0),
        (-6.02, -2.60,  1.20, 10.95, 0.98, 6,  3.6, -1.8),
        (-6.62, -2.60, -0.06, 12.25, 1.06, 6, -1.8,  0.6),
        (-6.78, -2.60, -1.16,  8.65, 0.92, 5, -4.0, -4.2),
        (-6.80, -2.60,  1.18,  8.35, 0.90, 6, -3.8,  4.4),
        (-6.68, -2.60,  0.08, 13.15, 0.84, 5, -2.8, -1.0),
    ]
    right_cols = [
        ( 6.14, -2.60, -0.04, 11.50, 1.12, 6, -3.8,  0.8),
        ( 6.00, -2.60, -1.20, 10.75, 0.96, 6, -3.3,  1.8),
        ( 6.02, -2.60,  1.18, 11.05, 0.98, 5, -3.5, -2.0),
        ( 6.64, -2.60,  0.06, 12.40, 1.06, 6,  1.9, -0.6),
        ( 6.80, -2.60, -1.14,  8.45, 0.90, 6,  3.9, -4.4),
        ( 6.78, -2.60,  1.20,  8.85, 0.92, 5,  4.1,  4.0),
        ( 6.70, -2.60, -0.10, 13.30, 0.86, 5,  2.9,  1.2),
    ]

    for bx, by, bz, h, rad, sides, tx, tz in left_cols:
        sculpt_basalt_column(mb, (bx, by, bz), h, rad, sides, tx, tz,
                             C_BASALT_DARK, C_BASALT_TOP, rng, mat='basalt', magma_seam=False)
        pts_l.extend(_basalt_col_hull_pts((bx, by, bz), h, rad, sides, tx, tz))

    for bx, by, bz, h, rad, sides, tx, tz in right_cols:
        sculpt_basalt_column(mb, (bx, by, bz), h, rad, sides, tx, tz,
                             C_BASALT_DARK, C_BASALT_TOP, rng, mat='basalt', magma_seam=False)
        pts_r.extend(_basalt_col_hull_pts((bx, by, bz), h, rad, sides, tx, tz))

    # Jagged fractured black-obsidian rock talus aprons welding pier feet cleanly into terrain (y <= -2.6 m!)
    pts_l += sculpt_rock_mass(
        mb, (-6.52, 0.45, 0.02), (1.42, 3.25, 1.98), 'basalt',
        C_BASALT_TOP, C_BASALT_MID, C_BASALT_DARK, rng,
        subdiv=2, warp=0.18, strata=0.14, base_flare=0.18,
        rot_deg=(0, 16, 4), crag_ribs=6, rib_amp=0.15,
    )
    pts_r += sculpt_rock_mass(
        mb, ( 6.54, 0.48, -0.04), (1.42, 3.28, 1.98), 'basalt',
        C_BASALT_TOP, C_BASALT_MID, C_BASALT_DARK, rng,
        subdiv=2, warp=0.18, strata=0.14, base_flare=0.18,
        rot_deg=(0, -18, -4), crag_ribs=6, rib_amp=0.15,
    )

    # 2. Soaring Pointed-Vault Obsidian Arch Spine + Radially Wedged Jagged Obsidian Voussoirs
    #    Soffit stays strictly >= 8.35 m across |x| <= 4.10 m and rises dramatically to ~9.80 m at apex!
    arch_stations = [
        ((-5.85,  8.35,  0.04), 1.82, 1.06,  0.0, 0.18),
        ((-4.60,  9.38, -0.02), 1.76, 1.04,  2.0, 0.42),
        ((-3.00, 10.22, -0.05), 1.70, 1.04, -2.0, 0.68),
        ((-1.42, 10.78, -0.02), 1.68, 1.08,  1.0, 0.88),
        (( 0.00, 11.02,  0.00), 1.72, 1.14,  0.0, 1.00),
        (( 1.42, 10.78,  0.02), 1.68, 1.08, -1.0, 0.88),
        (( 3.00, 10.20,  0.05), 1.70, 1.04,  2.0, 0.68),
        (( 4.60,  9.35,  0.02), 1.76, 1.04, -2.0, 0.42),
        (( 5.85,  8.32, -0.04), 1.82, 1.06,  0.0, 0.18),
    ]
    _sculpt_bevel_ribbon(
        mb, arch_stations, 'basalt',
        lambda t: mix(C_BASALT_DARK, C_BASALT_TOP, 0.20 + 0.65 * t),
        rng, sides=6, squarish=0.16, init_up=(0.0, 1.0, 0.0),
    )

    # 7 Radially Splayed Faceted Obsidian Arch Voussoir Blades (tapered crystalline ridge tops, NOT flat boxes!)
    voussoir_specs = [
        # (p_bot, p_top, rx_b, rz_b, rx_t, rz_t, apex_pt)
        ((-4.95, 8.20,  0.06), (-5.78, 10.28,  0.10), 1.04, 1.88, 0.68, 1.48, (-6.02, 10.72,  0.12)),
        ((-3.40, 9.05, -0.08), (-3.95, 11.10, -0.10), 1.00, 1.82, 0.62, 1.38, (-4.18, 11.62, -0.12)),
        ((-1.72, 9.58,  0.05), (-2.05, 11.58,  0.06), 0.96, 1.78, 0.58, 1.32, (-2.22, 12.08,  0.08)),
        (( 0.00, 9.64,  0.00), ( 0.00, 11.98,  0.00), 1.08, 1.88, 0.72, 1.42, ( 0.00, 12.56,  0.00)),
        (( 1.72, 9.58, -0.05), ( 2.08, 11.56, -0.06), 0.96, 1.78, 0.58, 1.32, ( 2.24, 12.06, -0.08)),
        (( 3.40, 9.02,  0.08), ( 3.98, 11.08,  0.10), 1.00, 1.82, 0.62, 1.38, ( 4.20, 11.60,  0.12)),
        (( 4.95, 8.18, -0.06), ( 5.80, 10.25, -0.10), 1.04, 1.88, 0.68, 1.48, ( 6.05, 10.70, -0.12)),
    ]
    for pb, pt, rxb, rzb, rxt, rzt, ap in voussoir_specs:
        _sculpt_tapered_prism(
            mb, pb, pt, rxb, rzb, rxt, rzt, 6, rng,
            mat='basalt', col_bot=C_BASALT_DARK, col_top=C_BASALT_TOP,
            rings=3, rot_deg=rng.uniform(-14.0, 14.0), notch_amp=0.06, apex_pt=ap,
        )

    # 3. Dramatic Spiked Volcanic Obsidian Keystone Ridge Crest (soaring jagged crystal blades peaking ~13.04 m!)
    crest_spires = [
        # Towering central obsidian keystone fang (peaks cleanly at y = 13.04 m)
        (( 0.00, 11.20,  0.00), ( 0.02, 12.50, -0.04), 0.66, 0.88, 0.24, 0.30, 6, ( 0.04, 13.04, -0.06)),
        # Flanking sharp tilted obsidian crystal fangs
        ((-0.92, 10.95, -0.24), (-1.28, 12.15, -0.32), 0.48, 0.62, 0.16, 0.22, 5, (-1.42, 12.66, -0.36)),
        (( 0.94, 10.92,  0.22), ( 1.30, 12.12,  0.30), 0.48, 0.62, 0.16, 0.22, 5, ( 1.44, 12.62,  0.34)),
        # Mid-arch diagonal volcanic obsidian shards
        ((-2.58, 10.50,  0.22), (-3.22, 11.82,  0.32), 0.54, 0.68, 0.18, 0.24, 5, (-3.48, 12.34,  0.36)),
        (( 2.60, 10.48, -0.20), ( 3.26, 11.80, -0.30), 0.54, 0.68, 0.18, 0.24, 5, ( 3.52, 12.32, -0.34)),
        # Swept volcanic shoulder crystal horns tying the arch dramatically into the twin basalt towers!
        ((-4.62,  9.72, -0.26), (-5.45, 11.25, -0.36), 0.60, 0.76, 0.20, 0.26, 5, (-5.78, 11.82, -0.40)),
        (( 4.65,  9.70,  0.24), ( 5.50, 11.28,  0.34), 0.60, 0.76, 0.20, 0.26, 5, ( 5.82, 11.86,  0.38)),
    ]
    for pb, pt, rxb, rzb, rxt, rzt, sd, ap in crest_spires:
        _sculpt_tapered_prism(
            mb, pb, pt, rxb, rzb, rxt, rzt, sd, rng,
            mat='basalt', col_bot=C_BASALT_MID, col_top=C_BASALT_TOP,
            rings=3, rot_deg=rng.uniform(-18.0, 18.0), apex_pt=ap,
        )

    # 4. Subtle Recessed Glowing Molten Magma Veins ('glass' with C_MAGMA_GLOW / C_BASALT_HOT)
    # 4a. Sinuous glowing magma fissure running cleanly along the recessed arch soffit ceiling!
    arch_magma_path = [
        (-4.08, 8.66, -0.10),
        (-2.70, 9.22,  0.16),
        (-1.35, 9.56, -0.14),
        ( 0.00, 9.72,  0.08),
        ( 1.35, 9.54,  0.14),
        ( 2.70, 9.20, -0.12),
        ( 4.08, 8.64,  0.10),
    ]
    _sculpt_magma_vein(
        mb, arch_magma_path,
        [0.05, 0.09, 0.12, 0.15, 0.12, 0.09, 0.05],
        (0.0, -1.0, 0.0), rng,
    )
    # 4b. Recessed vertical glowing magma slivers tucked inside the keystone mortar seams
    for sz in (-1.0, 1.0):
        for sx in (-0.98, 0.98):
            _sculpt_magma_vein(
                mb,
                [(sx * 0.92, 9.88, sz * 1.62), (sx * 1.04, 10.68, sz * 1.64),
                 (sx * 1.14, 11.35, sz * 1.50)],
                [0.04, 0.08, 0.04],
                (0.0, 0.0, sz), rng,
            )
    # 4c. 4 Narrow recessed pillar-seam magma fissures glowing deep between the basalt columns
    pillar_fissures = [
        ([(-5.06, 0.45, -0.60), (-4.96, 2.75, -0.56), (-4.86, 5.05, -0.62), (-4.72, 7.10, -0.56)],
         ( 0.85, 0.0, -0.52)),
        ([(-5.08, 0.65,  0.62), (-4.98, 2.95,  0.58), (-4.88, 5.15,  0.64), (-4.74, 7.05,  0.58)],
         ( 0.85, 0.0,  0.52)),
        ([( 5.08, 0.50, -0.62), ( 4.98, 2.85, -0.56), ( 4.88, 5.10, -0.60), ( 4.74, 7.15, -0.54)],
         (-0.85, 0.0, -0.52)),
        ([( 5.10, 0.70,  0.60), ( 5.00, 2.90,  0.64), ( 4.89, 5.05,  0.58), ( 4.76, 7.00,  0.62)],
         (-0.85, 0.0,  0.52)),
    ]
    for fpath, fdir in pillar_fissures:
        _sculpt_magma_vein(mb, fpath, [0.045, 0.085, 0.080, 0.040], fdir, rng)

    build(mb)

    add_empty('Lantern_MagmaArch', (0.0, 9.35, 0.0))

    # 3 Clean Colliders strictly preserving the open walkable central underpass x in [-4.1, +4.1], y in [0, 8.0]!
    left_col_pts = [Vector((min(p.x, -4.15), p.y, p.z)) for p in pts_l if p.y <= 8.20]
    right_col_pts = [Vector((max(p.x, 4.15), p.y, p.z)) for p in pts_r if p.y <= 8.20]
    col_piece('col_varch_left', left_col_pts)
    col_piece('col_varch_right', right_col_pts)

    bridge_col_pts = [
        (-5.85,  8.15, -1.95), ( 5.85,  8.15, -1.95),
        (-5.85,  8.15,  1.95), ( 5.85,  8.15,  1.95),
        (-4.85, 11.45, -1.80), ( 4.85, 11.45, -1.80),
        (-4.85, 11.45,  1.80), ( 4.85, 11.45,  1.80),
        (-1.45, 12.55, -1.55), ( 1.45, 12.55, -1.55),
        (-1.45, 12.55,  1.55), ( 1.45, 12.55,  1.55),
        ( 0.00, 13.02, -0.80), ( 0.00, 13.02,  0.80),
    ]
    col_piece('col_varch_bridge', bridge_col_pts)
    export_landmark_glb(outdir, 'volcanic_obsidian_arch.glb')


# ================================================================ 3. LEVIATHAN RIBCAGE BONES

def gen_leviathan_ribcage_bones(outdir):
    """Colossal ~14.5 m long curving calcified sea-monster ribcage & weathered split horned
    jawbone rising dramatically out of coastal sand along Z (jaw toward -Z), with 6 pairs of
    soaring smooth C-arched curved bone ribs rooted to y = -1.8 m, half-buried spine ridges,
    draped weathered hemp fishing net/ropes, hanging sea-kelp drapes, and a wide walkable
    sandy central ribcage aisle!"""
    clear_scene()
    rng = random.Random(SEED + 853)
    mb = MB('LeviathanRibcageBones', seed=853)
    left_col_pts = []
    right_col_pts = []

    def spine_x(z):
        return 0.30 * sin((z + 0.9) * 0.22)

    # 1. 6 Pairs of Towering Sculpted Smooth Bezier C-Arched Bone Ribs (y_root = -1.80 -> y ≈ 5.6..7.85 m!)
    #    Tuple: (z_root, belly_x, peak_y_l, peak_y_r, tip_x_gap, aft_sweep, base_w, broken_r)
    rib_specs = [
        (-2.60, 3.45, 6.25, 6.08, 1.02, 0.55, 0.72, False),  # Pair 0: forward neck-chest arch
        (-0.88, 3.92, 7.36, 7.18, 0.65, 0.68, 0.84, False),  # Pair 1: broad thorax arch
        ( 0.88, 4.18, 7.86, 7.68, 0.42, 0.74, 0.90, False),  # Pair 2: colossal hero cathedral peak!
        ( 2.65, 3.88, 7.25, 7.42, 0.62, 0.80, 0.84, False),  # Pair 3: mid-thorax arch
        ( 4.40, 3.48, 6.45, 5.58, 0.86, 0.86, 0.76, True),   # Pair 4: aft thorax (stbd rib fractured!)
        ( 6.10, 3.08, 5.65, 5.82, 0.96, 0.96, 0.66, False),  # Pair 5: trailing bone arch
    ]

    rib_anchors = {}
    for ri, (zr, bx, py_l, py_r, tip_gap, aft, bw, broken_r) in enumerate(rib_specs):
        cx = spine_x(zr)
        for sgn in (-1.0, 1.0):
            is_broken = (broken_r and sgn > 0.0)
            peak_y = py_l if sgn < 0.0 else py_r
            # Smooth C-infinity cubic Bezier curve in (lx, ly) — ZERO kinks, majestic sweeping crescent!
            p0 = Vector((bx * 0.58, -1.80, 0.0))
            p1 = Vector((bx * 1.24,  1.25, 0.0))
            p2 = Vector((bx * 1.12,  peak_y * 1.16, 0.0))
            p3 = Vector((tip_gap,    peak_y * 0.96, 0.0))

            n_st = 8 if is_broken else 10
            u_max = 0.76 if is_broken else 1.00
            pts = []
            rads_z = []
            rads_r = []
            for si in range(n_st):
                u = u_max * (si / float(n_st - 1))
                b = _cubic_bezier(p0, p1, p2, p3, u)
                lz = zr + aft * (u ** 1.30) + sgn * 0.07 * sin(u * pi)
                px = cx + sgn * b.x
                pts.append(Vector((px, b.y, lz)))

                # Chunky monumental calcified bone taper: broad flat blade at sand -> graceful arched tip
                taper = 1.0 - 0.64 * (u ** 1.20)
                if is_broken and si == n_st - 1:
                    taper *= 0.84
                rads_z.append(max(0.14, bw * 0.50 * taper))
                rads_r.append(max(0.09, bw * 0.30 * taper))

            rib_pts = _sculpt_bone_rib(mb, pts, rads_z, rads_r, rng, side_sgn=sgn, broken=is_broken)
            rib_anchors[(ri, -1 if sgn < 0 else 1)] = pts

            for p in rib_pts:
                if p.y <= 5.20:
                    if sgn < 0.0:
                        left_col_pts.append(Vector((min(p.x, -1.85), p.y, p.z)))
                    else:
                        right_col_pts.append(Vector((max(p.x, 1.85), p.y, p.z)))

    # 2. Half-Buried Segmented Vertebral Spine Ridges Peeking Through the Sandy Aisle Base!
    #    Low organic buried backbone segments (y <= 0.42 m) so players stride effortlessly down the aisle!
    vert_zs = [-3.25, -1.78, -0.32, 1.15, 2.62, 4.08, 5.48, 6.65]
    # Continuous low half-buried weathered spinal cord core linking the vertebrae under the sand
    spine_core_st = []
    for vz in vert_zs:
        sc = 1.0 - 0.22 * abs(vz - 1.2) / 6.0
        spine_core_st.append(((spine_x(vz), -0.34, vz), 0.78 * sc, 0.46 * sc, 0.0, 0.25))
    _sculpt_bevel_ribbon(
        mb, spine_core_st, 'skull_stone',
        lambda t: mix(C_SKULL_SHADE, C_SKULL_MID, 0.35 + 0.30 * t),
        rng, sides=6, squarish=0.06, init_up=(0.0, 1.0, 0.0),
    )
    for vi, vz in enumerate(vert_zs):
        vx = spine_x(vz)
        sc = 1.0 - 0.24 * abs(vi - 3.0) / 4.0
        # Buried vertebral centrum arch peeking cleanly out of coastal sand (rooted to y = -1.65 m!)
        _sculpt_tapered_prism(
            mb, (vx, -1.65, vz), (vx, 0.26 * sc, vz),
            0.96 * sc, 0.62 * sc, 0.70 * sc, 0.48 * sc, 6, rng,
            mat='skull_stone',
            col_bot=mix(C_SKULL_SHADE, C_SEA_MOSS, 0.24),
            col_top=C_SKULL_MID,
            rings=3, rot_deg=rng.uniform(-7.0, 7.0), jitter=0.06,
        )
        # Sculpted dorsal neural-spine hump ridge peeking through the sand
        _sculpt_tapered_prism(
            mb, (vx, 0.06, vz - 0.16 * sc), (vx + rng.uniform(-0.04, 0.04), 0.36 * sc, vz + 0.22 * sc),
            0.26 * sc, 0.42 * sc, 0.12 * sc, 0.24 * sc, 5, rng,
            mat='skull_stone', col_bot=C_SKULL_MID, col_top=C_SKULL_BONE,
            rings=2, apex_pt=(vx, 0.44 * sc, vz + 0.30 * sc), jitter=0.05,
        )

    # 3. Dramatic Weathered Split Leviathan Horned Jawbone & Skull Crest Near -Z Front (z ≈ -3.6..-7.35 m)
    for sgn in (-1.0, 1.0):
        tilt_up = 1.00 if sgn < 0.0 else 0.86
        # 3a. Massive curved calcified split mandible arm emerging organically from the coastal sand!
        jp0 = Vector((sgn * 3.18, -1.80, -3.55))
        jp1 = Vector((sgn * 2.98,  0.30, -4.45))
        jp2 = Vector((sgn * 2.52,  0.88 * tilt_up, -5.95))
        jp3 = Vector((sgn * 1.98,  1.58 * tilt_up, -7.38))

        jaw_stations = []
        n_jaw = 8
        for ji in range(n_jaw):
            u = ji / float(n_jaw - 1)
            jp = _cubic_bezier(jp0, jp1, jp2, jp3, u)
            rw = 0.56 * (1.0 - 0.72 * (u ** 1.35))
            rh = 0.74 * (1.0 - 0.72 * (u ** 1.30))
            ct = smooth01((jp.y + 1.50) / 3.0)
            jaw_stations.append((jp, max(0.12, rw), max(0.16, rh), sgn * 10.0 * (1.0 - u), ct))

        jaw_pts = _sculpt_bevel_ribbon(
            mb, jaw_stations, 'skull_stone',
            lambda t: mix(mix(C_SKULL_SHADE, C_SEA_MOSS, 0.20), C_SKULL_BONE, t),
            rng, sides=6, squarish=0.12, init_up=(0.0, 1.0, 0.0),
        )
        for p in jaw_pts:
            if sgn < 0.0:
                left_col_pts.append(Vector((min(p.x, -1.75), p.y, p.z)))
            else:
                right_col_pts.append(Vector((max(p.x, 1.75), p.y, p.z)))

        # 3b. 6 Jagged Curved Conical Leviathan Teeth lining the upper ridge of each split mandible!
        tooth_defs = [
            (0.32, 0.72, 0.16, -0.18, False),
            (0.46, 0.88, 0.18, -0.22, False),
            (0.59, 0.98, 0.19, -0.20, sgn > 0.0),  # chipped battle fang on starboard jaw!
            (0.72, 0.82, 0.16, -0.18, False),
            (0.84, 0.94, 0.17, -0.16, False),      # dramatic front canine fang!
            (0.94, 0.58, 0.13, -0.12, False),
        ]
        for tf, th, tr, lean_in, chipped in tooth_defs:
            sock = _cubic_bezier(jp0, jp1, jp2, jp3, tf)
            rh = max(0.16, 0.74 * (1.0 - 0.72 * (tf ** 1.30)))
            base_p = Vector((sock.x - sgn * 0.04, sock.y + rh * 0.60, sock.z))
            tip_p = base_p + Vector((sgn * lean_in, th, -0.18 * th))
            curve_v = Vector((-sgn * 0.06, 0.07, -0.11))
            _sculpt_conical_fang(mb, base_p, tip_p, tr, curve_v, rng, chipped=chipped)

        # 3c. Smooth Sweeping Calcified Leviathan Brow-Horn Skull Crest rising behind each jaw hinge!
        horn_h = 4.45 if sgn < 0.0 else 4.02
        hp0 = Vector((sgn * 3.22, -1.80, -4.45))
        hp1 = Vector((sgn * 3.72,  0.65, -4.55))
        hp2 = Vector((sgn * 4.18,  2.75, -3.75))
        hp3 = Vector((sgn * 3.42,  horn_h, -2.52))

        horn_stations = []
        n_horn = 8
        for hi in range(n_horn):
            u = hi / float(n_horn - 1)
            hp = _cubic_bezier(hp0, hp1, hp2, hp3, u)
            hr = max(0.06, 0.64 * (1.0 - 0.88 * (u ** 1.15)))
            ct = smooth01((hp.y + 1.50) / 5.4)
            horn_stations.append((hp, hr * 0.92, hr * 1.06, 0.0, ct))

        horn_pts = _sculpt_bevel_ribbon(
            mb, horn_stations, 'skull_stone',
            lambda t: mix(mix(C_SKULL_SHADE, C_SEA_MOSS, 0.16), C_SKULL_BONE, t),
            rng, sides=6, squarish=0.14, init_up=(0.0, 0.0, -1.0),
        )
        for p in horn_pts:
            if p.y <= 5.20:
                if sgn < 0.0:
                    left_col_pts.append(Vector((min(p.x, -1.85), p.y, p.z)))
                else:
                    right_col_pts.append(Vector((max(p.x, 1.85), p.y, p.z)))

        # Swept weathered zygomatic/cheek bone crest seamlessly welding jaw hinge & brow horn!
        cheek_st = [
            ((sgn * 3.35, -1.50, -4.65), 0.56, 0.72, 0.0, 0.15),
            ((sgn * 3.25, -0.15, -4.85), 0.46, 0.64, 0.0, 0.45),
            ((sgn * 2.95,  0.95, -4.75), 0.30, 0.46, 0.0, 0.72),
            ((sgn * 2.72,  1.45, -4.45), 0.14, 0.22, 0.0, 0.92),
        ]
        _sculpt_bevel_ribbon(
            mb, cheek_st, 'skull_stone',
            lambda t: mix(C_SKULL_SHADE, C_SKULL_BONE, t),
            rng, sides=6, squarish=0.10,
        )

    # 4. Environmental Storytelling Accents: Draped Weathered Hemp Fishing Net, Ropes & Sea-Kelp!
    r0_l = rib_anchors[(0, -1)]
    r1_l = rib_anchors[(1, -1)]
    r2_l = rib_anchors[(2, -1)]
    r2_r = rib_anchors[(2,  1)]
    r3_r = rib_anchors[(3,  1)]

    # 4a. Organic draped diamond-weave weathered hemp fishing net snagged across Port Ribs 1 & 2!
    net_rows = []
    for k_idx in (3, 4, 5, 6):
        p_a = r1_l[k_idx] + Vector((-0.14, 0.0, 0.0))
        p_b = r2_l[k_idx] + Vector((-0.14, 0.0, 0.0))
        row_pts = []
        for s_i in range(5):
            u = s_i / 4.0
            sag = -0.44 * sin(u * pi)
            bow = -0.18 * sin(u * pi)
            row_pts.append(p_a.lerp(p_b, u) + Vector((bow, sag, 0.0)))
        net_rows.append(row_pts)
        tube(mb, row_pts, 0.036, 4, 'rope', jit(C_ROPE, rng, 0.07), mode='flat')

    # Crossed diagonal trawler-net drape cords + loose torn dangling rope tails!
    diag_pairs = [
        (net_rows[3][0], net_rows[2][1], net_rows[1][2], net_rows[0][3]),
        (net_rows[3][1], net_rows[2][2], net_rows[1][3], net_rows[0][4]),
        (net_rows[3][4], net_rows[2][3], net_rows[1][2], net_rows[0][1]),
        (net_rows[3][3], net_rows[2][2], net_rows[1][1], net_rows[0][0]),
    ]
    for dp in diag_pairs:
        pts_d = list(dp)
        # Torn frayed dangling bottom tail
        pts_d.append(pts_d[-1] + Vector((-0.12, -0.72 - rng.uniform(0.0, 0.35), rng.uniform(-0.14, 0.14))))
        tube(mb, pts_d, 0.028, 4, 'rope', jit(mul(C_ROPE, 0.88), rng, 0.06), mode='flat')

    # 4b. Heavy salvaged shipwreck hawser ropes lashed around ribs & catenary-draped high overhead!
    for (pa, pb, sag_h) in (
        (r0_l[5], r1_l[6], 0.58),
        (r2_l[7], r3_r[6], 0.86),  # high overhead catenary clear above walkway (y > 5.8 m!)
        (r2_r[5], r3_r[5], 0.48),
    ):
        cat_pts = []
        for si in range(6):
            u = si / 5.0
            cat_pts.append(pa.lerp(pb, u) + Vector((0.0, -sag_h * sin(u * pi), 0.0)))
        tube(mb, cat_pts, 0.046, 4, 'rope', C_ROPE, mode='flat')

    # Tight hemp rope wraps lashed around Port Rib 1 & Starboard Rib 2
    for rib_pt, tilt_z in ((r1_l[3], -16.0), (r2_r[3], 16.0)):
        for wi in range(2):
            with xf(mb, T(rib_pt + Vector((0.0, (wi - 0.5) * 0.12, 0.0))) @ R('Z', tilt_z)):
                torus(mb, 0.38, 0.042, 7, 4, 'rope', mul(C_ROPE, 0.90 + 0.08 * (wi % 2)), False)

    # 4c. 3 Hanging Sea-Kelp / Vine Strands ('foliage' with UV2 wind weights!) clinging to arched ribs
    kelp_specs = [
        (r1_l[7] + Vector(( 0.06, -0.10, 0.0)), 2.55, 0.34, (-0.35, 0.0, -0.94), 0.16),
        (r2_r[7] + Vector((-0.06, -0.10, 0.0)), 2.40, 0.32, ( 0.30, 0.0,  0.95), 0.52),
        (rib_anchors[(4, -1)][7] + Vector((0.06, -0.08, 0.0)), 2.25, 0.30, (-0.42, 0.0, 0.91), 0.84),
    ]
    for anc, klen, kw, kdir, kph in kelp_specs:
        add_vine_drape(mb, anc, klen, kw, kdir, rng, phase=kph)

    build(mb)

    # 2 Clean Wall Colliders along left/right ribs & jaw halves (keeping central sandy aisle 100% open!)
    col_piece('col_ribcage_left', left_col_pts)
    col_piece('col_ribcage_right', right_col_pts)
    export_landmark_glb(outdir, 'leviathan_ribcage_bones.glb')


STORYTELLING_A_GENERATORS = [
    gen_ancient_sea_god_idol,
    gen_volcanic_obsidian_arch,
    gen_leviathan_ribcage_bones,
]
