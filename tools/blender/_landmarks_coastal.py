# Sea of Scoundrels: 4 sculpted 3D Coastal, Beach, Reef & Volcanic-Caldera landmarks (Wave I-5).
# Imported by tools/blender/gen_island_landmarks.py.
# Authored in Godot game coordinates (-Z seaward/hero-facing, +Y up, +X starboard, metres)
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
    C_BASALT_TOP, C_BASALT_MID, C_BASALT_DARK, C_BASALT_HOT, C_MAGMA_GLOW,
    C_TEMPLE_HI, C_TEMPLE_MID, C_TEMPLE_DARK, C_TEMPLE_GOLD,
    C_TIMBER_HI, C_TIMBER_MID, C_TIMBER_DARK, C_DRIFTWOOD,
    C_PAINT_RED, C_PAINT_TEAL, C_PAINT_CREAM,
    C_ROPE, C_IRON, C_IRON_RUST, C_BRASS, C_LANTERN_GL,
    C_LEAF_DEEP, C_LEAF_SUN,
    T, R, S, M_Y2Z, M_Y2X, newell,
    MB, xf,
    cbox, sculpt_stone_block, loft, lathe, tube, cyl, torus, rope_coil,
    build_lantern_geom, sculpt_rock_mass, sculpt_basalt_column, add_vine_drape,
    clear_scene, build, col_piece, col_box, add_empty, export_landmark_glb,
)


# ---------------------------------------------------------------- local palette & sculptural helpers

C_SAIL_CREAM   = srgb('#e8d9b4')
C_SAIL_WARM    = srgb('#d8c290')
C_PARCHMENT    = srgb('#f2e2b2')
C_PARCH_EDGE   = srgb('#c9aa6c')
C_MAGMA_CORE   = srgb('#ffe052')
C_MAGMA_MID    = srgb('#ff7a14')
C_MAGMA_DEEP   = srgb('#c9340c')

C_CORAL_PINK   = srgb('#f25278')
C_CORAL_ROSE   = srgb('#b5224e')
C_CORAL_PINKHI = srgb('#ff90aa')
C_CORAL_ORANGE = srgb('#f56e22')
C_CORAL_RUST   = srgb('#b83814')
C_CORAL_AMBER  = srgb('#ffaa38')
C_CORAL_TURQ   = srgb('#1bc7bb')
C_CORAL_TEAL   = srgb('#0c7880')
C_CORAL_AQUA   = srgb('#66f2e6')
C_CORAL_GOLD   = srgb('#ebaf22')
C_CORAL_OCHRE  = srgb('#a66812')
C_CORAL_LEMON  = srgb('#ffda58')

C_KELP_DARK    = srgb('#185230')
C_KELP_MID     = srgb('#2a7840')
C_KELP_SUN     = srgb('#60a634')


def _add_chain_links(mb, p0, p1, n_links, link_r=0.068, wire_r=0.020,
                     segs=6, psegs=4, sag=0.0, rust_stride=3):
    """Alternating 90-degree hammered wrought-iron chain links along a gentle catenary between p0 & p1."""
    a = Vector(p0)
    b = Vector(p1)
    if (b - a).length < 1e-5 or n_links < 1:
        return
    for k in range(n_links):
        t = (k + 0.5) / float(n_links)
        t0 = max(0.0, t - 0.05)
        t1 = min(1.0, t + 0.05)
        pt = a.lerp(b, t) + Vector((0.0, -sag * 4.0 * t * (1.0 - t), 0.0))
        q0 = a.lerp(b, t0) + Vector((0.0, -sag * 4.0 * t0 * (1.0 - t0), 0.0))
        q1 = a.lerp(b, t1) + Vector((0.0, -sag * 4.0 * t1 * (1.0 - t1), 0.0))
        tang = q1 - q0
        if tang.length < 1e-6:
            tang = Vector((0.0, -1.0, 0.0))
        rot_q = Vector((0.0, 1.0, 0.0)).rotation_difference(tang.normalized()).to_matrix().to_4x4()
        spin = R('Y', 90.0 if (k % 2 == 0) else 0.0)
        col = C_IRON_RUST if (k % rust_stride == 0) else C_IRON
        with xf(mb, T(pt) @ rot_q @ spin @ S(0.76, 1.18, 0.76) @ M_Y2Z):
            torus(mb, link_r, wire_r, segs, psegs, 'iron', col, False)


def _add_kelp_drape(mb, anchor, length, width, out_dir, rng, phase=0.0, segs=5):
    """Graceful sinuous coastal sea-kelp frond ('foliage') with UV2 wind bend weights (0 root -> 1 tip)."""
    a = Vector(anchor)
    od = Vector(out_dir)
    od.y = 0.0
    if od.length < 1e-4:
        od = Vector((0.0, 0.0, -1.0))
    od.normalize()
    side = Vector((-od.z, 0.0, od.x))
    prev_l = prev_r = None
    for i in range(segs + 1):
        t = i / float(segs)
        # Organic tapered kelp frond width: slender holdfast -> full blade -> wispy ribbon tip
        w = width * (0.42 + 0.62 * sin(t * pi * 0.88)) * (1.0 - 0.58 * (t ** 1.3))
        sway = sin(t * 3.8 + phase * 6.28) * 0.22 * (0.25 + 0.75 * t)
        flutter = cos(t * 2.6 + phase * 5.0) * 0.10 * t
        ctr = a + od * (0.14 + 0.30 * t + flutter) + side * sway + Vector((0.0, -length * t, 0.0))
        pl = ctr - side * w
        pr = ctr + side * w
        if prev_l is not None:
            t0 = (i - 1) / float(segs)
            c0 = jit(mix(C_KELP_DARK, C_KELP_MID, t0 * 0.75), rng, 0.05)
            c1 = jit(mix(C_KELP_MID, C_KELP_SUN, t * 0.82), rng, 0.05)
            uvs = [(0.0, t0), (1.0, t0), (1.0, t), (0.0, t)]
            uv2 = [(t0 * 0.85, phase), (t0 * 0.85, phase), (t * 0.96, phase), (t * 0.96, phase)]
            idx = [mb.v(prev_l), mb.v(prev_r), mb.v(pr), mb.v(pl)]
            mb.f(idx, 'foliage', [c0, c0, c1, c1], uvs, smooth=False, uv2=uv2)
        prev_l, prev_r = pl, pr


def _build_coopered_keg(mb, M_keg, radius=0.31, height=0.82, rng=None, spigot=False):
    """Coopered oak pirate rum keg with alternating timber staves, 4 iron hoops & optional brass spigot."""
    hh = height * 0.5
    prof = [
        (0.0,           -hh),
        (radius * 0.74, -hh),
        (radius * 0.82, -hh * 1.03),
        (radius * 0.90, -hh * 0.78),
        (radius,        -hh * 0.26),
        (radius,         hh * 0.26),
        (radius * 0.90,  hh * 0.78),
        (radius * 0.82,  hh * 1.03),
        (radius * 0.74,  hh),
        (0.0,            hh),
    ]
    segs = 7
    stave_cols = [
        jit(C_TIMBER_MID if k % 2 == 0 else C_TIMBER_HI, rng, 0.08, 0.02) if rng else C_TIMBER_MID
        for k in range(segs)
    ]
    with xf(mb, M_keg):
        lathe(mb, prof, segs, 'timber', C_TIMBER_MID, False, False,
              lambda i, k: C_TIMBER_DARK if i in (0, 8) else stave_cols[k])
        for hy, hr in (
            (-hh * 0.76, radius * 0.92),
            (-hh * 0.24, radius * 1.025),
            ( hh * 0.24, radius * 1.025),
            ( hh * 0.76, radius * 0.92),
        ):
            cyl(mb, hr, hy - 0.022, hy + 0.022, segs, 'iron', C_IRON, False, 0.0)
        if spigot:
            with xf(mb, T(0.0, -hh * 0.52, -radius * 0.92) @ M_Y2Z):
                cyl(mb, 0.026, -0.02, 0.13, 5, 'brass', C_BRASS, False, 0.0, 0.018)
            cbox(mb, (0.0, -hh * 0.52 + 0.045, -radius - 0.06), (0.08, 0.022, 0.022), 'brass', C_BRASS, 0.0)
            cbox(mb, (0.0, -hh * 0.52 - 0.035, -radius - 0.09), (0.024, 0.055, 0.024), 'brass', C_BRASS, 0.0)


def _build_ornate_galleon_lantern(mb, center, scale=1.0):
    """Large ornate hexagonal gilded-brass galleon stern lantern with flared crown & warm amber glass."""
    cx, cy, cz = center
    s = scale
    with xf(mb, T(cx, cy, cz)):
        base_prof = [
            (0.00,      -0.62 * s),
            (0.22 * s,  -0.62 * s),
            (0.16 * s,  -0.50 * s),
            (0.11 * s,  -0.36 * s),
            (0.24 * s,  -0.28 * s),
            (0.32 * s,  -0.20 * s),
            (0.28 * s,  -0.16 * s),
            (0.00,      -0.16 * s),
        ]
        lathe(mb, base_prof, 6, 'brass', C_TEMPLE_GOLD, smooth=False)
        cyl(mb, 0.24 * s, -0.17 * s, 0.30 * s, 6, 'glass', C_LANTERN_GL, False, 0.0, 0.34 * s)
        cap_prof = [
            (0.00,       0.29 * s),
            (0.38 * s,   0.29 * s),
            (0.42 * s,   0.34 * s),
            (0.34 * s,   0.46 * s),
            (0.18 * s,   0.58 * s),
            (0.09 * s,   0.64 * s),
            (0.06 * s,   0.78 * s),
            (0.00,       0.92 * s),
        ]
        lathe(mb, cap_prof, 6, 'brass', C_BRASS, smooth=False)
        for k in range(6):
            ang = 2.0 * pi * k / 6.0
            ca, sa = cos(ang), sin(ang)
            p_lo = Vector((ca * 0.27 * s, -0.20 * s, sa * 0.27 * s))
            p_hi = Vector((ca * 0.37 * s,  0.32 * s, sa * 0.37 * s))
            tube(mb, [p_lo, p_hi], [0.024 * s, 0.028 * s], 4, 'brass', C_TEMPLE_GOLD, mode='flat')


def _sculpt_continuous_coral_arch(mb, stations, sides, rng):
    """Continuous curved wave-eroded coastal limestone sea-arch sweeping organically from left foot
    (-X, y=-3.25) over the vaulted crown (y~5.1 m) down to the right foot (+X, y=-3.25)!
    Each station: (center_xyz, r_radial, r_z, twist_deg).
    Returns (left_pts, right_pts) for split arch colliders preserving the open central archway.
    """
    n = len(stations)
    pts = [Vector(st[0]) for st in stations]
    rib_j = [rng.uniform(0.84, 1.16) for _ in range(sides)]
    rib_p = [rng.uniform(0.0, 6.28) for _ in range(sides)]
    secs = []
    left_pts = []
    right_pts = []

    for i, (ctr, rr, rz, tw_d) in enumerate(stations):
        c = pts[i]
        p_prev = pts[max(0, i - 1)]
        p_next = pts[min(n - 1, i + 1)]
        tang = (p_next - p_prev)
        if tang.length < 1e-5:
            tang = Vector((0.0, 1.0, 0.0))
        tang.normalize()
        # Arch lies in X-Y plane so +Z is always cleanly perpendicular to the arch curve!
        z_ax = Vector((0.0, 0.0, 1.0))
        rad_ax = tang.cross(z_ax).normalized()
        tw = radians(tw_d)
        u_ax = rad_ax * cos(tw) + z_ax * sin(tw)
        v_ax = -rad_ax * sin(tw) + z_ax * cos(tw)

        t_arch = i / float(max(1, n - 1))
        strata = 1.0 + 0.08 * sin(t_arch * pi * 7.0 + 0.5)
        ring = []
        for k in range(sides):
            ang = 2.0 * pi * k / float(sides) + 0.18 * t_arch
            ch = rib_j[k] * strata * (1.0 + 0.07 * sin(i * 1.4 + rib_p[k]))
            # Slightly flatten the top crest & carve organic ledges along flanks
            p = c + u_ax * (cos(ang) * rr * ch) + v_ax * (sin(ang) * rz * ch)
            ring.append(p)
            if p.x < -1.85:
                left_pts.append(p)
            elif p.x > 1.85:
                right_pts.append(p)
        secs.append(ring)

    def _face_style(q_pts, inside_p):
        fn = newell(q_pts)
        fn = fn.normalized() if fn.length > 1e-8 else Vector((0.0, 1.0, 0.0))
        fc = sum(q_pts, Vector()) / float(len(q_pts))
        if fn.dot(fc - inside_p) < 0.0:
            fn = -fn
        ht = smooth01((fc.y + 0.4) / 5.2)
        base = mix(C_LIME_MID, C_LIME_PALE, 0.18 + 0.74 * ht)
        fmat = 'limestone'
        if fn.y > 0.44 and fc.y > 1.4:
            mc = 0.72 if fc.y > 3.8 else 0.52
            base = mix(base, C_LEDGE_MOSS, mc)
            if fc.y > 4.4 and fn.y > 0.65:
                base = mix(base, C_GRASS_SUN, 0.35)
            fmat = 'limestone_moss'
        elif fn.y < -0.18:
            base = mix(base, C_LIME_SHADE, 0.55)
        if fc.y < 0.35:
            wet = smooth01((0.35 - fc.y) / 1.6)
            base = mix(base, C_LIME_DARK, wet * 0.58)
        tide_moss = smooth01((1.65 - fc.y) / 1.2) * smooth01((fc.y + 1.4) / 1.1)
        if tide_moss > 0.02:
            base = mix(base, C_SEA_MOSS, tide_moss * 0.74)
            if tide_moss > 0.35:
                fmat = 'limestone_moss'
        return fmat, jit(base, rng, 0.048, 0.018)

    mb.newoff()
    for i in range(n - 1):
        r0, r1 = secs[i], secs[i + 1]
        inside = 0.5 * (pts[i] + pts[i + 1])
        for k in range(sides):
            kn = (k + 1) % sides
            q = [r0[k], r0[kn], r1[kn], r1[k]]
            fm, fc = _face_style(q, inside)
            mb.fp(q, fm, fc, (1, 0, 0), inside, smooth=False)

    # Bottom foot caps buried at y = -3.25 m
    mb.fp(secs[0], 'limestone', mul(C_LIME_DARK, 0.72), (1, 0, 0), pts[1], smooth=False)
    mb.fp(secs[-1], 'limestone', mul(C_LIME_DARK, 0.72), (1, 0, 0), pts[-2], smooth=False)
    return left_pts, right_pts


def _add_staghorn_coral_cluster(mb, base_pos, grow_dir, scale, col_base, col_tip, rng, branches=4):
    """Bold sculptural branching staghorn coral colony ('paint') with vibrant base-to-tip gradient."""
    bp = Vector(base_pos)
    gd = Vector(grow_dir)
    if gd.length < 1e-4:
        gd = Vector((0.0, 1.0, 0.0))
    gd.normalize()
    ref = Vector((1.0, 0.0, 0.0)) if abs(gd.x) < 0.8 else Vector((0.0, 0.0, 1.0))
    u_ax = gd.cross(ref).normalized()
    v_ax = gd.cross(u_ax).normalized()

    for bi in range(branches):
        ang = 2.0 * pi * bi / float(branches) + rng.uniform(-0.32, 0.32)
        spread = rng.uniform(0.36, 0.68)
        b_dir = (gd + (u_ax * cos(ang) + v_ax * sin(ang)) * spread).normalized()
        b_len = scale * rng.uniform(0.82, 1.18)
        p0 = bp - gd * (0.18 * scale)
        p1 = bp + b_dir * (b_len * 0.45)
        p2 = p1 + (b_dir + Vector((0.0, 0.30, 0.0))).normalized() * (b_len * 0.58)
        r0 = 0.125 * scale
        r1 = 0.095 * scale
        r2 = 0.048 * scale
        scols = [
            jit(col_base, rng, 0.05),
            jit(mix(col_base, col_tip, 0.55), rng, 0.05),
            jit(col_tip, rng, 0.05),
        ]
        tube(mb, [p0, p1, p2], [r0, r1, r2], 5, 'paint', col_tip, mode='flat', scols=scols)

        # Bold forked secondary staghorn tine sprouting off mid-branch!
        if bi % 2 == 0 or branches <= 3:
            ang2 = ang + rng.uniform(0.60, 1.20)
            t_dir = (b_dir + (u_ax * cos(ang2) + v_ax * sin(ang2)) * 0.72 + Vector((0.0, 0.22, 0.0))).normalized()
            t_len = b_len * rng.uniform(0.46, 0.64)
            p_fork = p1 + t_dir * t_len
            tube(mb, [p1, p_fork], [r1 * 0.84, r2 * 0.90], 4, 'paint', col_tip, mode='flat',
                 scols=[jit(mix(col_base, col_tip, 0.48), rng, 0.05), jit(col_tip, rng, 0.05)])


def _add_fan_coral_plate(mb, center, rx, rz, thick, rot_deg, col_inner, col_rim, rng, sides=7):
    """Chunky ruffled 3D Acropora table/fan-coral shelf plate ('paint', double-sided solid)."""
    X = T(center) @ R('Y', rot_deg[1]) @ R('X', rot_deg[0]) @ R('Z', rot_deg[2])
    top_ring = []
    bot_ring = []
    phase = rng.uniform(0.0, 6.28)
    for k in range(sides):
        ang = 2.0 * pi * k / float(sides)
        scallop = 1.0 + 0.18 * sin(ang * 3.0 + phase) + 0.08 * cos(ang * 4.0 - phase)
        # Slightly cupped upward ruffled coral rim!
        cup_y = 0.14 * max(rx, rz) + 0.10 * max(rx, rz) * sin(ang * 3.0 + phase * 0.7)
        px = cos(ang) * rx * scallop
        pz = sin(ang) * rz * scallop
        top_ring.append(Vector((px,  thick * 0.5 + cup_y, pz)))
        bot_ring.append(Vector((px, -thick * 0.5 + cup_y * 0.6, pz)))

    ctr_top = Vector((0.0,  thick * 0.10, 0.0))
    ctr_bot = Vector((0.0, -thick * 1.15, 0.0))
    c_in = jit(col_inner, rng, 0.05)
    c_out = jit(col_rim, rng, 0.05)
    c_under = mul(col_inner, 0.64)

    mb.newoff()
    with xf(mb, X):
        for k in range(sides):
            kn = (k + 1) % sides
            mb.fp([ctr_top, top_ring[kn], top_ring[k]], 'paint', [c_in, c_out, c_out],
                  (1, 0, 0), Vector((0.0, -1.0, 0.0)), smooth=False)
            mb.fp([ctr_bot, bot_ring[k], bot_ring[kn]], 'paint', [c_under, mul(c_out, 0.72), mul(c_out, 0.72)],
                  (1, 0, 0), Vector((0.0, 1.0, 0.0)), smooth=False)
            mb.fp([bot_ring[k], top_ring[k], top_ring[kn], bot_ring[kn]], 'paint', c_out,
                  (1, 0, 0), Vector((0.0, 0.0, 0.0)), smooth=False)


def _add_reef_sponge_cluster(mb, base_pos, rot_deg, scale, col_body, col_rim, rng, tubes=3):
    """Chunky cluster of fluted tubular tropical reef sponges ('paint') with recessed dark bore mouths."""
    X = T(base_pos) @ R('Y', rot_deg[1]) @ R('X', rot_deg[0]) @ R('Z', rot_deg[2])
    with xf(mb, X):
        for ti in range(tubes):
            ang = 2.0 * pi * ti / float(tubes) + rng.uniform(-0.3, 0.3)
            off_r = (0.18 if ti > 0 else 0.0) * scale
            ox, oz = cos(ang) * off_r, sin(ang) * off_r
            h = scale * (0.76 if ti == 0 else rng.uniform(0.48, 0.64))
            r_mid = scale * (0.17 if ti == 0 else rng.uniform(0.12, 0.15))
            lean = R('Z', cos(ang) * (14.0 if ti > 0 else 4.0)) @ R('X', sin(ang) * (14.0 if ti > 0 else -4.0))
            prof = [
                (0.00,         -0.12 * scale),
                (r_mid * 0.85, -0.06 * scale),
                (r_mid * 1.15,  h * 0.42),
                (r_mid * 0.98,  h * 0.82),
                (r_mid * 1.12,  h),
                (r_mid * 0.62,  h * 0.97),
                (r_mid * 0.42,  h * 0.56),
                (0.00,          h * 0.52),
            ]
            c_b = jit(col_body, rng, 0.06)
            c_r = jit(col_rim, rng, 0.06)
            c_bore = mul(col_body, 0.34)
            with xf(mb, T(ox, 0.0, oz) @ lean):
                lathe(mb, prof, 6, 'paint', c_b, smooth=False,
                      colfn=lambda i, k, cb=c_b, cr=c_r, ck=c_bore: (
                          ck if i >= 5 else (cr if i in (3, 4) else cb)
                      ))


def _sculpt_jagged_basalt_obelisk(mb, base_pos, height, radius, tilt_x, tilt_z,
                                  col_bot, col_top, rng, magma_seam=True):
    """Hexagonal volcanic obsidian-basalt obelisk tooth with sharp beveled jagged fang spire tip."""
    bx, by, bz = base_pos
    sides = 6
    rot0 = rng.uniform(0.0, 2.0 * pi)
    rib_j = [rng.uniform(0.90, 1.12) for _ in range(sides)]
    ring_fracs = [
        (0.00, 1.12),
        (0.24, 1.04),
        (0.56, 0.92),
        (0.84, 0.72),
    ]
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
            # Slanted cleavage step near top shoulder
            yk = y + (radius * 0.42 * cos(ang - rot0) if ri == len(ring_fracs) - 1 else 0.0)
            v = Vector((ox + cos(ang) * rk, yk, oz + sin(ang) * rk))
            ring.append(v)
            out_pts.append(v)
        secs.append(ring)

    # Sharp jagged obsidian fang apex offset slightly along lean direction!
    apex = Vector((
        bx + sin(radians(tilt_x)) * height * 1.03 + cos(rot0) * radius * 0.16,
        by + height,
        bz + sin(radians(tilt_z)) * height * 1.03 + sin(rot0) * radius * 0.16,
    ))
    out_pts.append(apex)

    mb.newoff()
    for ri in range(len(secs) - 1):
        r0, r1 = secs[ri], secs[ri + 1]
        inside = 0.5 * (centers[ri] + centers[ri + 1])
        t_h = (ri + 0.5) / float(len(secs))
        c_band = mix(col_bot, col_top, t_h)
        if magma_seam and ri == 0:
            c_band = mix(c_band, C_BASALT_HOT, 0.34)
        for k in range(sides):
            kn = (k + 1) % sides
            q = [r0[k], r0[kn], r1[kn], r1[k]]
            mb.fp(q, 'basalt', jit(c_band, rng, 0.05, 0.015), (0, 1, 0), inside, smooth=False)

    # Bottom cap
    mb.fp(secs[0], 'basalt', mul(col_bot, 0.72), (1, 0, 0), centers[1], smooth=False)
    # Sharp chiseled hexagonal obsidian fang pyramid cap!
    inside_top = centers[-1] - Vector((0.0, 0.35, 0.0))
    for k in range(sides):
        kn = (k + 1) % sides
        tri = [secs[-1][k], secs[-1][kn], apex]
        mb.fp(tri, 'basalt', jit(mul(col_top, 1.08), rng, 0.05), (0, 1, 0), inside_top, smooth=False)
    return out_pts


# ================================================================ 1. PIRATE CAMP CANOPY

def gen_pirate_camp_canopy(outdir):
    """Lived-in Sea-of-Thieves treasure-island beach camp (~6.2 m x 4.6 m, ~3.8 m tall, posts plunging
    cleanly to y = -1.2 m) with crooked driftwood posts, braided rope lashings, double-sided sagged
    weathered sailcloth awning with crimson/teal patched stripes, 4 guy-lines & stakes, oak map-table
    crate with unrolled parchment treasure chart + brass compass & spyglass, two coopered rum kegs,
    coiled mooring rope, mossy stone-ring campfire with charred logs & glowing ember coals, and a
    hanging brass camp lantern + Lantern_Camp Empty.
    Target: 2,600-4,200 visual tris.
    """
    clear_scene()
    rng = random.Random(SEED + 1011)
    mb = MB('PirateCampCanopy', seed=1011)

    # 1. Four Crooked Driftwood / Timber Posts plunging cleanly to y = -1.25 m!
    post_specs = [
        ('fl', -2.14, -1.52, 3.74, -0.08, -0.10, 0.138, 0.098),
        ('fr',  2.14, -1.48, 3.56,  0.10, -0.08, 0.135, 0.096),
        ('bl', -2.04,  1.54, 2.92, -0.06,  0.10, 0.128, 0.092),
        ('br',  2.06,  1.52, 2.78,  0.08,  0.08, 0.126, 0.090),
    ]
    post_joints = {}

    for pname, bx, bz, ytop, lx, lz, rb, rt in post_specs:
        path = []
        rads = []
        cols = []
        n_pts = 5
        for i in range(n_pts):
            t = i / float(n_pts - 1)
            y = -1.25 + t * (ytop + 1.25)
            crook_x = sin(t * pi * 1.45 + bx) * 0.075 * sin(t * pi)
            crook_z = cos(t * pi * 1.30 + bz) * 0.065 * sin(t * pi)
            px = bx + lx * t + crook_x
            pz = bz + lz * t + crook_z
            path.append(Vector((px, y, pz)))
            rads.append(rb * (1.0 - t) + rt * t)
            c_post = mix(C_TIMBER_DARK, C_DRIFTWOOD, smooth01((y + 0.4) / 3.8))
            cols.append(jit(c_post, rng, 0.06))
        tube(mb, path, rads, 6, 'timber', C_DRIFTWOOD, mode='flat', scols=cols)

        j_pt = path[-2].lerp(path[-1], 0.55)
        post_joints[pname] = j_pt
        stub_dir = Vector((0.26 if bx > 0 else -0.26, 0.34, -0.10 if bz < 0 else 0.10))
        tube(mb, [j_pt - Vector((0.0, 0.12, 0.0)), j_pt + stub_dir], [0.065, 0.032], 4,
             'timber', C_DRIFTWOOD, mode='flat')

    p_fl, p_fr = post_joints['fl'], post_joints['fr']
    p_bl, p_br = post_joints['bl'], post_joints['br']

    def _add_pole(a, b, r0, r1, ov_a=0.34, ov_b=0.34, sag=0.04, col=C_TIMBER_MID):
        v = (b - a).normalized()
        pa = a - v * ov_a
        pb = b + v * ov_b
        pm = pa.lerp(pb, 0.5) + Vector((0.0, -sag, 0.0))
        tube(mb, [pa, pm, pb], [r0, (r0 + r1) * 0.52, r1], 5, 'timber', jit(col, rng, 0.06), mode='flat')

    _add_pole(p_fl, p_fr, 0.082, 0.078, 0.38, 0.38, sag=-0.06, col=C_TIMBER_HI)
    _add_pole(p_bl, p_br, 0.074, 0.072, 0.34, 0.34, sag=0.03, col=C_DRIFTWOOD)
    _add_pole(p_fl, p_bl, 0.068, 0.064, 0.32, 0.32, sag=0.05, col=C_TIMBER_MID)
    _add_pole(p_fr, p_br, 0.068, 0.064, 0.32, 0.32, sag=0.05, col=C_TIMBER_MID)
    mid_f = p_fl.lerp(p_fr, 0.5) + Vector((0.0, 0.10, 0.0))
    mid_b = p_bl.lerp(p_br, 0.5) + Vector((0.0, 0.06, 0.0))
    _add_pole(mid_f, mid_b, 0.062, 0.056, 0.28, 0.28, sag=-0.04, col=C_DRIFTWOOD)
    # Low rear driftwood rail bracing back posts behind map table (matches col_camp_posts cleanly!)
    tube(mb, [Vector((-2.10, 1.05, 1.56)), Vector((0.0, 1.00, 1.60)), Vector((2.10, 1.02, 1.54))],
         [0.058, 0.054, 0.056], 5, 'timber', C_TIMBER_DARK, mode='flat')

    # Braided Hemp Rope Lashings cinched tightly around all 4 post-to-beam cross joints!
    for pname, jpt in post_joints.items():
        for ri in range(2):
            tilt_a = 40.0 if ri == 0 else -40.0
            with xf(mb, T(jpt + Vector((0.0, -0.02 + ri * 0.05, 0.0))) @ R('X', tilt_a) @ R('Z', 16.0)):
                torus(mb, 0.145, 0.028, 6, 4, 'rope', mul(C_ROPE, 0.90 + 0.10 * ri), True)

    # 2. Double-Sided Sagged / Billowed Weathered Sailcloth Sun-Awning ('paint', real 3D thickness!)
    #    Warm sun-bleached cream with bold weathered crimson & sea-teal patched stripes!
    nu, nv = 8, 6
    thick = 0.026

    def _awning_pt(u, v):
        f_l = p_fl + Vector((-0.20, 0.07, -0.26))
        f_r = p_fr + Vector(( 0.20, 0.07, -0.26))
        b_l = p_bl + Vector((-0.18, 0.06,  0.24))
        b_r = p_br + Vector(( 0.18, 0.06,  0.24))
        pf = f_l.lerp(f_r, u)
        pb = b_l.lerp(b_r, u)
        p = pf.lerp(pb, v)
        bay_sag = sin(min(1.0, abs(u - 0.5) * 2.0) * pi) * sin(v * pi) * 0.28
        ridge_lift = (1.0 - abs(u - 0.5) * 2.0) ** 1.35 * 0.18 * (0.35 + 0.65 * sin(v * pi))
        breeze_wave = sin(u * pi * 3.0 + v * 1.4) * 0.055 * sin(v * pi)
        edge_drop = 0.0
        if v < 0.16:
            edge_drop = -0.26 * ((0.16 - v) / 0.16) ** 1.4 - 0.06 * abs(sin(u * pi * 4.0))
        elif v > 0.84:
            edge_drop = -0.20 * ((v - 0.84) / 0.16) ** 1.4 - 0.04 * abs(sin(u * pi * 4.0))
        p.y += ridge_lift - bay_sag + breeze_wave + edge_drop
        return p

    top_grid = [[None] * (nv + 1) for _ in range(nu + 1)]
    bot_grid = [[None] * (nv + 1) for _ in range(nu + 1)]
    for iu in range(nu + 1):
        u = iu / float(nu)
        for iv in range(nv + 1):
            v = iv / float(nv)
            p = _awning_pt(u, v)
            pu = _awning_pt(min(1.0, u + 0.02), v) - _awning_pt(max(0.0, u - 0.02), v)
            pv = _awning_pt(u, min(1.0, v + 0.02)) - _awning_pt(u, max(0.0, v - 0.02))
            n = pv.cross(pu)
            if n.y < 0:
                n = -n
            n = n.normalized() if n.length > 1e-6 else Vector((0.0, 1.0, 0.0))
            top_grid[iu][iv] = p + n * (thick * 0.5)
            bot_grid[iu][iv] = p - n * (thick * 0.5)

    def _sail_patch_col(iu, iv):
        if iu in (1, 6):
            c = C_PAINT_RED
        elif iu in (3, 4) and iv in (2, 3):
            c = C_PAINT_TEAL
        elif (iu == 0 and iv == 3) or (iu == 7 and iv == 1):
            c = C_PAINT_TEAL
        elif (iu == 5 and iv == 4) or (iu == 2 and iv == 1):
            c = C_PAINT_RED
        elif (iu + iv) % 3 == 0:
            c = C_SAIL_WARM
        else:
            c = C_SAIL_CREAM
        return jit(c, rng, 0.045, 0.015)

    mb.newoff()
    for iu in range(nu):
        for iv in range(nv):
            c_top = _sail_patch_col(iu, iv)
            c_bot = mul(c_top, 0.84)
            t00, t10, t11, t01 = top_grid[iu][iv], top_grid[iu + 1][iv], top_grid[iu + 1][iv + 1], top_grid[iu][iv + 1]
            b00, b10, b11, b01 = bot_grid[iu][iv], bot_grid[iu + 1][iv], bot_grid[iu + 1][iv + 1], bot_grid[iu][iv + 1]
            ctr = (t00 + t11 + b00 + b11) * 0.25
            mb.fp([t00, t10, t11, t01], 'paint', c_top, (1, 0, 0), ctr - Vector((0.0, 1.5, 0.0)), smooth=False)
            mb.fp([b00, b01, b11, b10], 'paint', c_bot, (1, 0, 0), ctr + Vector((0.0, 1.5, 0.0)), smooth=False)
            if iv == 0:
                mb.fp([b00, b10, t10, t00], 'paint', mul(c_top, 0.78), (1, 0, 0), ctr + Vector((0.0, 0.0, 1.0)))
            if iv == nv - 1:
                mb.fp([b11, b01, t01, t11], 'paint', mul(c_top, 0.78), (1, 0, 0), ctr - Vector((0.0, 0.0, 1.0)))
            if iu == 0:
                mb.fp([b01, b00, t00, t01], 'paint', mul(c_top, 0.78), (0, 0, 1), ctr + Vector((1.0, 0.0, 0.0)))
            if iu == nu - 1:
                mb.fp([b10, b11, t11, t10], 'paint', mul(c_top, 0.78), (0, 0, 1), ctr - Vector((1.0, 0.0, 0.0)))

    # 3. Four Taut Rope Guy-Lines Anchored to Wooden Beach Stakes (~6.2 m x 4.6 m camp footprint!)
    guy_specs = [
        (p_fl, Vector((-3.02, 0.0, -2.22))),
        (p_fr, Vector(( 3.04, 0.0, -2.18))),
        (p_bl, Vector((-2.98, 0.0,  2.22))),
        (p_br, Vector(( 3.00, 0.0,  2.20))),
    ]
    for p_top, s_ground in guy_specs:
        out_v = Vector((s_ground.x - p_top.x, 0.0, s_ground.z - p_top.z)).normalized()
        st_bot = s_ground - out_v * 0.22 + Vector((0.0, -0.82, 0.0))
        st_top = s_ground + out_v * 0.14 + Vector((0.0,  0.42, 0.0))
        st_tie = st_bot.lerp(st_top, 0.84)
        tube(mb, [st_bot, s_ground, st_top], [0.048, 0.062, 0.042], 5, 'timber',
             jit(C_TIMBER_MID, rng, 0.08), mode='flat')
        with xf(mb, T(st_tie)):
            cyl(mb, 0.068, -0.028, 0.028, 5, 'rope', C_ROPE, False, 0.0)
        guy_pts = [p_top.lerp(st_tie, k / 3.0) - Vector((0.0, 0.06 * 4.0 * (k / 3.0) * (1.0 - k / 3.0), 0.0))
                   for k in range(4)]
        tube(mb, guy_pts, 0.022, 4, 'rope', jit(C_ROPE, rng, 0.05), mode='smooth')

    # 4. Sturdy Oak Map-Table Crate ('timber', 'iron' corners) + Unrolled Parchment Chart, Compass & Spyglass!
    tbl_x, tbl_z = -0.68, 0.36
    tbl_y_top = 0.88
    tbl_M = T(tbl_x, 0.0, tbl_z) @ R('Y', 10.0)
    with xf(mb, tbl_M):
        # Heavy wooden cargo-crate base plunging cleanly to y = -0.35 m for uneven sand!
        cbox(mb, (0.0, 0.22, 0.0), (1.16, 1.14, 0.72), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))
        for sy in (0.04, 0.74):
            for sz in (-0.37, 0.37):
                cbox(mb, (0.0, sy, sz), (1.24, 0.08, 0.06), 'timber', C_TIMBER_MID, 0.0, (1, 0, 0))
            for sx in (-0.59, 0.59):
                cbox(mb, (sx, sy, 0.0), (0.06, 0.08, 0.78), 'timber', C_TIMBER_MID, 0.0, (0, 0, 1))
        for sx in (-0.59, 0.59):
            for sz in (-0.37, 0.37):
                cbox(mb, (sx, 0.39, sz), (0.07, 0.78, 0.07), 'timber', C_TIMBER_HI, 0.0, (0, 1, 0))
                for cy_i in (0.06, 0.74):
                    cbox(mb, (sx * 1.01, cy_i, sz * 1.01), (0.10, 0.11, 0.10), 'iron', C_IRON, 0.0)
        # Wide overhanging planked oak map tabletop (4 rustic planks at y = 0.82..0.88 m)
        for plank_i in range(4):
            pz = -0.34 + plank_i * 0.228
            cbox(mb, (rng.uniform(-0.02, 0.02), 0.848, pz), (1.48, 0.064, 0.212), 'timber',
                 jit(C_TIMBER_HI if plank_i % 2 == 0 else C_TIMBER_MID, rng, 0.07), 0.0, (1, 0, 0))
        for sx in (-0.64, 0.64):
            cbox(mb, (sx, 0.852, 0.0), (0.065, 0.074, 0.90), 'iron', C_IRON_RUST, 0.0)

        # Unrolled Parchment Treasure Chart resting flush on tabletop (y = 0.885 m)!
        with xf(mb, T(-0.08, tbl_y_top + 0.008, -0.02) @ R('Y', -8.0)):
            cbox(mb, (0.0, 0.006, 0.0), (0.78, 0.014, 0.56), 'paint', C_PARCHMENT, 0.0, (1, 0, 0))
            for sx, rr in ((-0.40, 0.036), (0.40, 0.032)):
                with xf(mb, T(sx, 0.032, 0.0) @ M_Y2Z):
                    cyl(mb, rr, -0.29, 0.29, 6, 'paint', C_PARCH_EDGE, False, 0.0)
            cbox(mb, (-0.16, 0.016,  0.08), (0.20, 0.006, 0.14), 'paint', C_PAINT_TEAL, 0.0, M=R('Y', 18.0))
            cbox(mb, ( 0.15, 0.016, -0.06), (0.24, 0.006, 0.18), 'paint', C_SAIL_WARM,  0.0, M=R('Y', -12.0))
            for dx, dz in ((-0.10, 0.05), (-0.01, 0.01), (0.08, -0.03)):
                cbox(mb, (dx, 0.019, dz), (0.036, 0.006, 0.020), 'paint', C_PAINT_RED, 0.0, M=R('Y', -24.0))
            for xang in (45.0, -45.0):
                cbox(mb, (0.17, 0.020, -0.07), (0.16, 0.008, 0.028), 'paint', C_PAINT_RED, 0.0, M=R('Y', xang))

        # Chunky Tarnished Brass Nautical Compass weighting top-right chart corner!
        with xf(mb, T(0.42, tbl_y_top + 0.022, -0.20) @ R('Y', 24.0)):
            cyl(mb, 0.108, -0.022, 0.026, 6, 'brass', C_BRASS, False, 0.0)
            cyl(mb, 0.084,  0.024, 0.032, 6, 'paint', C_PARCHMENT, False, 0.0)
            cbox(mb, (0.0, 0.036, -0.016), (0.022, 0.008, 0.072), 'paint', C_PAINT_RED, 0.0)
            cbox(mb, (0.0, 0.036,  0.018), (0.022, 0.008, 0.066), 'iron',  C_IRON, 0.0)

        # Telescoping Brass Pirate Spyglass resting diagonally on the map table!
        with xf(mb, T(0.44, tbl_y_top + 0.038, 0.16) @ R('Y', -36.0) @ M_Y2X):
            cyl(mb, 0.044, -0.25, -0.05, 6, 'timber', C_TIMBER_DARK, False, 0.0, 0.040)
            cyl(mb, 0.048, -0.28, -0.24, 6, 'brass',  C_TEMPLE_GOLD, False, 0.0)
            cyl(mb, 0.036, -0.05,  0.12, 6, 'brass',  C_TEMPLE_GOLD, False, 0.0, 0.032)
            cyl(mb, 0.026,  0.12,  0.24, 6, 'brass',  C_BRASS, False, 0.0, 0.023)

    # 5. Two Coopered Rum Kegs prominently flanking the map-table crate!
    #    Upright keg on right-rear flank of table + horizontal spiced-rum cask on cradle chocks on left flank!
    _build_coopered_keg(mb, T(0.32, 0.24, 0.62) @ R('Y', -24.0) @ R('Z', 2.5),
                        radius=0.33, height=0.92, rng=rng, spigot=False)
    with xf(mb, T(-1.48, 0.0, -0.16) @ R('Y', -28.0)):
        for cz in (-0.22, 0.22):
            cbox(mb, (0.0, 0.02, cz), (0.58, 0.34, 0.11), 'timber', C_TIMBER_DARK, 0.0)
    _build_coopered_keg(mb, T(-1.48, 0.38, -0.16) @ R('Y', -28.0) @ R('X', 90.0),
                        radius=0.30, height=0.82, rng=rng, spigot=True)

    # 6. Coiled Mooring Rope near the front-left driftwood post + loose trailing end
    for i in range(3):
        rr = 0.25 * (1.0 - 0.16 * i)
        with xf(mb, T(-1.82, -0.02 + 0.028 * (1.0 + i * 1.65), -1.04)):
            torus(mb, rr, 0.028, 8, 4, 'rope', mul(C_ROPE, 0.92 + 0.08 * (i % 2)), True)
    tube(mb, [(-1.82, 0.04, -1.26), (-2.04, 0.14, -1.44), (-2.14, 0.52, -1.52)],
         0.024, 4, 'rope', C_ROPE, mode='smooth')

    # 7. Mossy Stone-Ring Campfire with Charred Logs & Glowing Ember Coals (front-right!)
    fire_x, fire_z = 1.04, -0.78
    n_stones = 8
    for k in range(n_stones):
        ang = 2.0 * pi * k / float(n_stones) + rng.uniform(-0.14, 0.14)
        dist = 0.56 + rng.uniform(-0.04, 0.05)
        sx = fire_x + cos(ang) * dist
        sz = fire_z + sin(ang) * dist
        rx = rng.uniform(0.22, 0.28)
        ry = rng.uniform(0.22, 0.29)
        rz = rng.uniform(0.21, 0.27)
        sculpt_rock_mass(
            mb, (sx, -0.02, sz), (rx, ry, rz),
            'limestone_moss' if k % 3 == 0 else 'limestone',
            C_LEDGE_MOSS if k % 3 == 0 else C_LIME_WARM, C_LIME_MID, C_LIME_DARK, rng,
            subdiv=1, warp=0.20, strata=0.10, base_flare=0.28,
            rot_deg=(rng.uniform(-8, 8), rng.uniform(0, 360), rng.uniform(-8, 8)),
            moss_cap=0.62 if k % 3 == 0 else 0.15,
        )

    # Glowing faceted ember coal bed inside stone ring ('glass')
    ember_c = Vector((fire_x, 0.07, fire_z))
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
    for v in bm.verts:
        p = v.co.copy()
        lump = 1.0 + 0.12 * sin(p.x * 5.0 + p.z * 4.2)
        v.co = ember_c + Vector((p.x * 0.44 * lump, (p.y * 0.18 if p.y >= 0 else p.y * 0.10), p.z * 0.44 * lump))
    bm.faces.ensure_lookup_table()
    mb.newoff()
    for f in bm.faces:
        pts = [v.co.copy() for v in f.verts]
        fc = sum(pts, Vector()) / len(pts)
        rn = min(1.0, sqrt((fc.x - fire_x) ** 2 + (fc.z - fire_z) ** 2) / 0.48)
        ec = mix(C_MAGMA_GLOW, C_MAGMA_DEEP, 0.20 + 0.65 * rn)
        mb.fp(pts, 'glass', jit(ec, rng, 0.07), (0, 1, 0), ember_c, smooth=False)
    bm.free()

    # 5 charred driftwood firelogs stacked teepee-style over the glowing embers
    for k in range(5):
        ang = 2.0 * pi * k / 5.0 + 0.25
        p_out = Vector((fire_x + cos(ang) * 0.48, 0.08, fire_z + sin(ang) * 0.48))
        p_in = Vector((fire_x - cos(ang) * 0.08, 0.46 + rng.uniform(-0.04, 0.06), fire_z - sin(ang) * 0.08))
        c_hot = mix(C_TIMBER_DARK, C_BASALT_HOT, 0.48)
        tube(mb, [p_out, p_out.lerp(p_in, 0.5), p_in], [0.068, 0.060, 0.046], 5, 'timber',
             C_TIMBER_DARK, mode='flat', scols=[C_TIMBER_DARK, c_hot, C_TIMBER_DARK])

    # 3 stylized warm glowing flame tongues rising cleanly from the campfire!
    for foff, (frx, fry), frot, fcol in (
        (( 0.00, 0.28,  0.00), (0.14, 0.44), ( 4,   0,  5), C_MAGMA_GLOW),
        ((-0.10, 0.22, -0.08), (0.10, 0.32), ( 8,  30, 12), C_LANTERN_GL),
        (( 0.10, 0.24,  0.08), (0.10, 0.34), (-6, -40, -10), C_MAGMA_GLOW),
    ):
        with xf(mb, T(fire_x + foff[0], foff[1], fire_z + foff[2]) @ R('Y', frot[1]) @ R('X', frot[0]) @ R('Z', frot[2])):
            prof = [(0.0, -fry * 0.22), (frx, 0.0), (frx * 0.65, fry * 0.48), (0.0, fry)]
            lathe(mb, prof, 5, 'glass', jit(fcol, rng, 0.06), smooth=False)

    # 8. Brass Camp Lantern Hanging from Front Ridge Beam + Lantern_Camp Empty!
    beam_mid = p_fl.lerp(p_fr, 0.5) + Vector((0.08, 0.03, 0.0))
    lantern_scale = 0.92
    lantern_pos = (beam_mid.x, beam_mid.y - 0.60, beam_mid.z)
    with xf(mb, T(beam_mid)):
        cbox(mb, (0.0, 0.0, 0.0), (0.12, 0.20, 0.20), 'iron', C_IRON, 0.0)
    _add_chain_links(
        mb,
        beam_mid + Vector((0.0, -0.10, 0.0)),
        Vector((lantern_pos[0], lantern_pos[1] + 0.30 * lantern_scale, lantern_pos[2])),
        n_links=3, link_r=0.034, wire_r=0.010, segs=6, psegs=4,
    )
    build_lantern_geom(mb, lantern_pos, scale=lantern_scale, hanging=True)

    build(mb)

    add_empty('Lantern_Camp', lantern_pos)
    col_box('col_camp_table', (-1.86, -0.35, -0.60), (0.68, 0.98, 1.02))
    col_box('col_camp_posts', (-2.26, -1.25, 1.34), (2.28, 3.00, 1.76))
    col_box('col_camp_post_fl', (-2.34, -1.25, -1.74), (-1.94, 3.76, -1.32))
    col_box('col_camp_post_fr', ( 1.94, -1.25, -1.70), ( 2.36, 3.60, -1.28))
    export_landmark_glb(outdir, 'pirate_camp_canopy.glb')


# ================================================================ 2. SUNKEN GALLEON STERN

def gen_sunken_galleon_stern(outdir):
    """Dramatic heeled (~18 deg roll, ~14 deg pitch) half-submerged broken gilded galleon stern
    quarter-gallery (~9.5 m wide x ~9.2 m tall, hull plunging solidly to y = -3.6 m into sandy reefs!).
    Pairs with impaled_shipwreck_bow.glb!
    Target: 3,400-5,200 visual tris.
    """
    clear_scene()
    rng = random.Random(SEED + 1049)
    mb = MB('SunkenGalleonStern', seed=1049)

    # Pose: 18 deg starboard-down heel (R('Z', -18)) + 14 deg transom-up pitch (R('X', +14))
    hull_X = T(-0.22, 0.38, 0.15) @ R('Z', -18.0) @ R('X', 14.0)

    def keel_y(z):
        if z < -1.80:
            u = min(1.0, (-1.80 - z) / 1.75)
            return -2.45 + 1.05 * (u ** 1.65)
        return -2.45

    def sheer_y(z):
        if z < 0.80:
            u = min(1.0, (0.80 - z) / 4.35)
            return 2.15 + 1.85 * (u ** 1.45)
        return 2.15 - 0.18 * ((z - 0.80) / 3.55)

    def half_beam(z, yn):
        u = max(0.0, min(1.0, (z + 3.55) / 7.90))
        plan = 2.45 + 0.72 * (sin(min(1.0, u * 1.25) * pi * 0.5) ** 0.75)
        yn_c = max(0.0, min(1.0, yn))
        if yn_c < 0.42:
            prof = 0.16 + 0.84 * (sin((yn_c / 0.42) * pi * 0.5) ** 0.65)
        else:
            t_th = (yn_c - 0.42) / 0.58
            prof = 1.0 - 0.25 * (t_th ** 1.35)
        return max(0.08, plan * prof)

    hull_col_pts = []
    deck_col_pts = []

    with xf(mb, hull_X):
        # 1. Heavy Dark-Tarred Oak Keel & Raked Sternpost (-Z)
        keel_zs = [4.35, 2.50, 0.60, -1.20, -2.35, -3.15, -3.55]
        keel_path = [(0.0, keel_y(z) - 0.08, z) for z in keel_zs]
        tube(mb, keel_path, [0.24, 0.26, 0.26, 0.26, 0.24, 0.22, 0.20], 5, 'timber', C_TIMBER_DARK, mode='flat')
        tube(mb, [(0.0, keel_y(-3.45), -3.45), (0.0, 0.92, -3.62)], [0.22, 0.19], 5,
             'timber', C_TIMBER_DARK, mode='flat')

        # 2. Clinker-Planked Outer & Inner Galleon Hull Strakes (6 strakes/side, ragged snapped +Z break!)
        z_nodes = [-3.52, -2.55, -1.45, -0.30, 0.90, 2.15, 3.30, 4.30]
        n_strakes = 6
        fwd_cuts = {
            (-1, 0): 7, (-1, 1): 7, (-1, 2): 6, (-1, 3): 6, (-1, 4): 5, (-1, 5): 4,
            ( 1, 0): 7, ( 1, 1): 6, ( 1, 2): 6, ( 1, 3): 5, ( 1, 4): 4, ( 1, 5): 4,
        }
        for sgn in (-1.0, 1.0):
            for si in range(n_strakes):
                yn0 = si / float(n_strakes)
                yn1 = (si + 1) / float(n_strakes)
                cl0 = 1.00 + si * 0.010
                cl1 = 1.028 + si * 0.010
                if si == 5:
                    mat_s, col_s = 'paint', C_PAINT_TEAL
                elif si == 4:
                    mat_s, col_s = 'paint', C_PAINT_RED
                elif si in (0, 1):
                    mat_s, col_s = 'timber', C_TIMBER_DARK
                else:
                    mat_s, col_s = 'timber', C_TIMBER_MID

                max_zi = fwd_cuts[(int(sgn), si)]
                for zi in range(max_zi):
                    z0, z1 = z_nodes[zi], z_nodes[zi + 1]
                    k0, g0 = keel_y(z0), sheer_y(z0)
                    k1, g1 = keel_y(z1), sheer_y(z1)
                    y00 = k0 + yn0 * (g0 - k0)
                    y01 = k0 + yn1 * (g0 - k0)
                    y10 = k1 + yn0 * (g1 - k1)
                    y11 = k1 + yn1 * (g1 - k1)
                    x00 = sgn * half_beam(z0, yn0) * cl0
                    x01 = sgn * half_beam(z0, yn1) * cl1
                    x10 = sgn * half_beam(z1, yn0) * cl0
                    x11 = sgn * half_beam(z1, yn1) * cl1

                    pc = jit(col_s, rng, 0.075, 0.02)
                    q_out = [(x00, y00, z0), (x10, y10, z1), (x11, y11, z1), (x01, y01, z0)]
                    in_ref = Vector((0.0, 0.5 * (y00 + y11), 0.5 * (z0 + z1)))
                    mb.fp(q_out, mat_s, pc, (0, 0, 1), in_ref, smooth=False)

                    off_in = Vector((-sgn * 0.11, 0.0, 0.0))
                    q_in = [Vector(p) + off_in for p in reversed(q_out)]
                    out_ref = Vector((sgn * 6.0, 0.5 * (y00 + y11), 0.5 * (z0 + z1)))
                    mb.fp(q_in, 'timber', mul(C_TIMBER_DARK, 0.84), (0, 0, 1), out_ref, smooth=False)

                    if zi % 2 == 0 and si in (0, 3, 5):
                        hull_col_pts.append(hull_X @ Vector((x00, y00, z0)))
                        hull_col_pts.append(hull_X @ Vector((x11, y11, z1)))

                if si in (2, 4, 5):
                    wale = []
                    for zi in range(max_zi + 1):
                        zl = z_nodes[zi]
                        kl, gl = keel_y(zl), sheer_y(zl)
                        yl = kl + yn1 * (gl - kl)
                        xl = sgn * (half_beam(zl, yn1) * cl1 + 0.06)
                        wale.append((xl, yl, zl))
                    wmat = 'brass' if si in (4, 5) else 'timber'
                    wcol = C_BRASS if si == 5 else (C_TEMPLE_GOLD if si == 4 else C_TIMBER_DARK)
                    tube(mb, wale, 0.062 if si == 2 else 0.048, 4, wmat, wcol, mode='flat')

        # 3. 7 Heavy Curved Interior Oak Hull Ribs + Splintered Snapped Fore-End Timbers!
        for ri in range(7):
            zl = -2.20 + ri * 1.02
            k_y, g_y = keel_y(zl) + 0.08, sheer_y(zl)
            for sgn in (-1.0, 1.0):
                max_yn = 1.0 if ri < 4 else (0.72 if ri == 4 else rng.uniform(0.36, 0.62))
                rib_pts = []
                for k in range(5):
                    yn = max_yn * (k / 4.0)
                    yl = k_y + yn * (g_y - k_y)
                    xl = sgn * half_beam(zl, yn) * 0.94
                    rib_pts.append((xl, yl, zl))
                tube(mb, rib_pts, [0.13, 0.12, 0.11, 0.10, 0.08], 4,
                     'timber', jit(C_TIMBER_DARK, rng, 0.07), mode='flat')

        for bi in range(6):
            bx = -2.10 + bi * 0.84
            by = -1.75 + 0.42 * (abs(bx) / 2.2) ** 2
            tube(mb, [(bx, by, 2.20), (bx + rng.uniform(-0.18, 0.18), by + rng.uniform(-0.22, 0.18), 4.65 + rng.uniform(0.3, 1.3))],
                 [0.11, 0.045], 4, 'timber', jit(C_DRIFTWOOD, rng, 0.09), mode='flat')

        # 4. Curved Raked Galleon Stern Transom + Crimson/Teal Frieze + 3 Tall Leaded-Glass Cabin Windows!
        def transom_z(y_l):
            if y_l < 0.75:
                t = smooth01((y_l + 1.40) / 2.15)
                return -3.45 - 0.34 * t
            t = smooth01((y_l - 0.75) / 3.65)
            return -3.79 + 0.48 * t

        def transom_hw(y_l):
            yn = max(0.0, min(1.0, (y_l - keel_y(-3.52)) / max(0.5, sheer_y(-3.52) - keel_y(-3.52))))
            return half_beam(-3.52, yn) * 1.03

        tr_ys = [-1.40, -0.50, 0.35, 0.95, 1.45, 2.95, 3.65, 4.18]
        tr_nx = 6
        for yi in range(len(tr_ys) - 1):
            y0, y1 = tr_ys[yi], tr_ys[yi + 1]
            z0_c, z1_c = transom_z(y0), transom_z(y1)
            hw0, hw1 = transom_hw(y0), transom_hw(y1)
            if yi in (0, 1, 2):
                tmat, tcol = 'timber', C_TIMBER_DARK if yi == 0 else C_TIMBER_MID
            elif yi == 3:
                tmat, tcol = 'paint', C_PAINT_RED
            elif yi == 4:
                tmat, tcol = 'timber', C_TIMBER_DARK
            elif yi == 5:
                tmat, tcol = 'paint', C_PAINT_TEAL
            else:
                tmat, tcol = 'paint', C_PAINT_RED

            for xi in range(tr_nx):
                u0 = -1.0 + 2.0 * xi / float(tr_nx)
                u1 = -1.0 + 2.0 * (xi + 1) / float(tr_nx)
                bow0 = -0.26 * (1.0 - u0 * u0)
                bow1 = -0.26 * (1.0 - u1 * u1)
                arch0 = 0.44 * (1.0 - u0 * u0) if yi == len(tr_ys) - 2 else 0.0
                arch1 = 0.44 * (1.0 - u1 * u1) if yi == len(tr_ys) - 2 else 0.0
                p00 = Vector((u0 * hw0, y0,         z0_c + bow0))
                p10 = Vector((u1 * hw0, y0,         z0_c + bow1))
                p11 = Vector((u1 * hw1, y1 + arch1, z1_c + bow1))
                p01 = Vector((u0 * hw1, y1 + arch0, z1_c + bow0))
                c_p = jit(tcol, rng, 0.05)
                mb.fp([p00, p01, p11, p10], tmat, c_p, (1, 0, 0), Vector((0.0, 0.5 * (y0 + y1), -1.0)))
                off_b = Vector((0.0, 0.0, 0.18))
                mb.fp([p00 + off_b, p10 + off_b, p11 + off_b, p01 + off_b], 'timber',
                      mul(C_TIMBER_DARK, 0.82), (1, 0, 0), Vector((0.0, 0.5 * (y0 + y1), -6.0)))
                if yi in (1, 4, 6) and xi in (0, 3, tr_nx - 1):
                    hull_col_pts.append(hull_X @ p01)

        # THREE Tall Leaded-Glass Stern Cabin Gallery Windows ('brass' mullions + warm amber 'glass'!)
        win_specs = [
            (-1.26, 0.88, 1.48, 2.92,  11.0),
            ( 0.00, 1.06, 1.44, 3.06,   0.0),
            ( 1.26, 0.88, 1.48, 2.92, -11.0),
        ]
        for wx, ww, wy0, wy1, wyaw in win_specs:
            ym = 0.5 * (wy0 + wy1)
            wh = wy1 - wy0
            u_w = wx / max(0.5, transom_hw(ym))
            wz = transom_z(ym) - 0.26 * (1.0 - u_w * u_w) - 0.06
            wM = T(wx, ym, wz) @ R('Y', wyaw) @ R('X', -7.5)
            with xf(mb, wM):
                cbox(mb, (0.0, 0.0, 0.015), (ww - 0.12, wh - 0.12, 0.04), 'glass', C_LANTERN_GL, 0.0)
                cbox(mb, (0.0,  wh * 0.5, -0.02), (ww + 0.08, 0.10, 0.12), 'brass', C_TEMPLE_GOLD, 0.0)
                cbox(mb, (0.0, -wh * 0.5, -0.02), (ww + 0.08, 0.10, 0.12), 'brass', C_TEMPLE_GOLD, 0.0)
                cbox(mb, (-ww * 0.5, 0.0, -0.02), (0.10, wh, 0.12), 'brass', C_BRASS, 0.0)
                cbox(mb, ( ww * 0.5, 0.0, -0.02), (0.10, wh, 0.12), 'brass', C_BRASS, 0.0)
                cbox(mb, (0.0, 0.0, -0.032), (0.042, wh - 0.08, 0.036), 'brass', C_BRASS, 0.0)
                for ty in (-wh * 0.18, wh * 0.18):
                    cbox(mb, (0.0, ty, -0.032), (ww - 0.08, 0.038, 0.036), 'brass', C_BRASS, 0.0)
                if abs(wx) < 0.1:
                    cbox(mb, (0.0, wh * 0.5 + 0.11, -0.05), (ww * 0.78, 0.12, 0.14), 'brass', C_BRASS, 0.0)

        # Projecting Side Quarter-Gallery Turret Bays
        for sgn in (-1.0, 1.0):
            qg_x = sgn * (half_beam(-2.85, 0.72) + 0.16)
            qg_M = T(qg_x, 2.28, -2.75) @ R('Y', sgn * -14.0) @ R('Z', sgn * 8.0)
            with xf(mb, qg_M):
                cbox(mb, (0.0, 0.0, 0.0), (0.48, 1.42, 1.18), 'timber', C_TIMBER_DARK, 0.015)
                cbox(mb, (sgn * 0.24, 0.02, 0.0), (0.06, 0.88, 0.76), 'glass', C_LANTERN_GL, 0.0)
                cbox(mb, (sgn * 0.27, 0.02, 0.0), (0.04, 0.92, 0.05), 'brass', C_BRASS, 0.0)
                cbox(mb, (sgn * 0.27, 0.02, 0.0), (0.04, 0.05, 0.80), 'brass', C_BRASS, 0.0)
                with xf(mb, T(0.0, 0.72, 0.0)):
                    cyl(mb, 0.44, 0.0, 0.44, 6, 'brass', C_TEMPLE_GOLD, False, 0.0, 0.10)
                with xf(mb, T(0.0, -0.72, 0.0)):
                    cyl(mb, 0.14, -0.42, 0.0, 6, 'brass', C_TEMPLE_GOLD, False, 0.0, 0.40)

        # 5. Ornate Gilded Stern Balcony Trim Rails, Arched Taffrail Crest & Scrollwork ('brass')!
        for rail_y, rad_r, is_crest in ((1.38, 0.088, False), (3.08, 0.078, False), (4.20, 0.098, True)):
            rail_pts = []
            hw_r = transom_hw(rail_y) + (0.14 if not is_crest else 0.08)
            z_base = transom_z(rail_y) - 0.12
            for k in range(9):
                u = -1.0 + 2.0 * k / 8.0
                bow = -0.26 * (1.0 - u * u)
                arch = 0.48 * (1.0 - u * u) if is_crest else 0.06 * (1.0 - u * u)
                rail_pts.append((u * hw_r, rail_y + arch, z_base + bow))
            tube(mb, rail_pts, rad_r, 5, 'brass', C_BRASS if is_crest else C_TEMPLE_GOLD, mode='flat')

        # Carved gilded stern-castle volute scroll brackets & curled upper cornice scrolls!
        for sgn in (-1.0, 1.0):
            hw_mid = transom_hw(2.25)
            scroll_pts = [
                (sgn * (hw_mid + 0.18), 1.32, transom_z(1.32) - 0.04),
                (sgn * (hw_mid + 0.36), 1.95, transom_z(1.95) - 0.06),
                (sgn * (hw_mid + 0.30), 2.75, transom_z(2.75) - 0.08),
                (sgn * (hw_mid + 0.12), 3.65, transom_z(3.65) - 0.10),
                (sgn * (hw_mid - 0.22), 4.24, transom_z(4.24) - 0.14),
            ]
            tube(mb, scroll_pts, [0.11, 0.12, 0.11, 0.095, 0.08], 5, 'brass', C_BRASS, mode='flat')

        crest_z = transom_z(3.72) - 0.32
        with xf(mb, T(0.0, 3.72, crest_z) @ R('X', -7.5)):
            with xf(mb, M_Y2Z):
                cyl(mb, 0.42, -0.04, 0.09, 8, 'brass', C_TEMPLE_GOLD, False, 0.0, 0.36)
            for k in range(4):
                cbox(mb, (0.0, 0.0, -0.05), (1.02 if k % 2 == 0 else 0.80, 0.075, 0.055),
                     'brass', C_BRASS, 0.0, M=R('Z', k * 45.0))
            cbox(mb, (0.0, 0.0, -0.06), (0.28, 0.34, 0.07), 'paint', C_PAINT_RED, 0.0)

        # 6. Splintered Poop-Deck Planks + Main Quarterdeck Floor + Bulwark Railings ('timber')!
        poop_zs = [-3.15, -2.55, -1.95, -1.35, -0.75, -0.15, 0.45, 1.05, 1.65]
        for plank_i, pz in enumerate(poop_zs):
            py = sheer_y(pz) - 0.72
            bw = half_beam(pz, 0.80) * 1.94
            if plank_i >= 6:
                cbox(mb, (-bw * 0.24, py, pz), (bw * 0.52, 0.12, 0.52), 'timber',
                     jit(C_DRIFTWOOD, rng, 0.08), 0.0, (1, 0, 0), M=R('Y', rng.uniform(-8, 8)))
                if plank_i == 6:
                    cbox(mb, (bw * 0.26, py - 0.04, pz + 0.08), (bw * 0.40, 0.11, 0.46), 'timber',
                         jit(C_TIMBER_MID, rng, 0.08), 0.0, (1, 0, 0), M=R('Y', 12.0) @ R('Z', -10.0))
            else:
                cbox(mb, (0.0, py, pz), (bw, 0.12, 0.55), 'timber',
                     jit(C_TIMBER_HI if plank_i % 2 == 0 else C_DRIFTWOOD, rng, 0.07), 0.0, (1, 0, 0),
                     M=R('Y', rng.uniform(-1.6, 1.6)))
            deck_col_pts.extend([
                hull_X @ Vector((-bw * 0.48, py + 0.08, pz)),
                hull_X @ Vector(( bw * 0.48, py + 0.08, pz)),
                hull_X @ Vector((-bw * 0.48, py - 0.35, pz)),
                hull_X @ Vector(( bw * 0.48, py - 0.35, pz)),
            ])

        cbox(mb, (0.0, 1.65, 1.80), (4.65, 1.35, 0.18), 'timber', C_TIMBER_DARK, 0.0)
        for sgn in (-1.0, 1.0):
            rail_pts = []
            for zi in range(5):
                zl = z_nodes[zi]
                xl = sgn * half_beam(zl, 1.0) * 1.02
                yl = sheer_y(zl) + 0.26
                rail_pts.append((xl, yl, zl))
                cbox(mb, (xl, yl - 0.18, zl), (0.12, 0.44, 0.12), 'timber', C_TIMBER_DARK, 0.0)
            tube(mb, rail_pts, 0.085, 4, 'timber', C_TIMBER_HI, mode='flat')

        # 7. Shattered Half-Buried Planked Oak Rudder Hinged to Sternpost ('timber', 'iron')!
        rud_M = T(0.0, -0.92, -3.92) @ R('Y', -16.0)
        with xf(mb, rud_M):
            cbox(mb, (0.0,  0.25, -0.28), (0.20, 2.75, 0.86), 'timber', C_TIMBER_DARK, 0.015, (0, 1, 0))
            cbox(mb, (0.0, -1.15, -0.45), (0.18, 1.15, 0.62), 'timber', C_TIMBER_MID,  0.010, (0, 1, 0), M=R('X', 12.0))
            for ry in (-0.65, -0.10, 0.55):
                tube(mb, [(0.0, ry, -0.66), (rng.uniform(-0.04, 0.04), ry - 0.18, -1.18 + rng.uniform(-0.12, 0.16))],
                     [0.08, 0.025], 4, 'timber', C_DRIFTWOOD, mode='flat')
            for hy in (-0.75, 0.05, 0.88):
                cbox(mb, (0.0, hy, -0.16), (0.26, 0.11, 0.96), 'iron', C_IRON_RUST if hy < 0 else C_IRON, 0.0)

        # 8. Dramatic Tall Snapped Mizzen Mast Stump + Askew Broken Yard + Drooping Rope Shrouds!
        #    Tall enough (~2.4 m above taffrail!) to silhouette unmistakably against the coastal sky!
        mz_z = -0.75
        mz_y0 = sheer_y(mz_z) - 1.65
        mz_top = Vector((0.0, 7.65, mz_z + 0.34))
        mast_path = [
            (0.0, mz_y0, mz_z),
            (0.0, 3.60,  mz_z + 0.10),
            (0.0, 5.75,  mz_z + 0.22),
            (mz_top.x, mz_top.y, mz_top.z),
        ]
        tube(mb, mast_path, [0.32, 0.28, 0.24, 0.18], 7, 'timber', C_DRIFTWOOD, mode='flat',
             scols=[C_TIMBER_DARK, C_TIMBER_MID, C_TIMBER_MID, C_DRIFTWOOD])
        for k in range(4):
            ang = k * pi * 0.5 + 0.4
            sp0 = mz_top + Vector((cos(ang) * 0.10, -0.10, sin(ang) * 0.10))
            sp1 = sp0 + Vector((cos(ang) * 0.06, rng.uniform(0.55, 1.05), sin(ang) * 0.06))
            tube(mb, [sp0, sp1], [0.068, 0.016], 4, 'timber', C_TIMBER_HI, mode='flat')
        for my in (3.65, 5.20, 6.55):
            with xf(mb, T(0.0, my, mz_z + 0.18)):
                cyl(mb, 0.27, -0.06, 0.06, 7, 'iron', C_IRON, False, 0.0)

        # Bold broken askew mizzen cross-yard & sagging rope shrouds clearly crowning the skyline!
        yd_l = Vector((-2.95, 5.42, mz_z + 0.20))
        yd_c = Vector(( 0.00, 6.22, mz_z - 0.14))
        yd_r = Vector(( 2.45, 6.86, mz_z - 0.38))
        tube(mb, [yd_l, yd_c, yd_r], [0.062, 0.125, 0.056], 5, 'timber', C_TIMBER_MID, mode='flat')
        with xf(mb, T(yd_c) @ R('X', 35.0)):
            torus(mb, 0.26, 0.038, 8, 4, 'rope', C_ROPE, True)

        shroud_specs = [
            ((0.0, 6.95, mz_z + 0.26), (-half_beam(-0.30, 0.95), sheer_y(-0.30) + 0.10, -0.30), 0.38),
            ((0.0, 6.85, mz_z + 0.26), (-half_beam(-1.45, 0.95), sheer_y(-1.45) + 0.10, -1.45), 0.34),
            ((0.0, 6.95, mz_z + 0.26), ( half_beam(-0.30, 0.95), sheer_y(-0.30) + 0.10, -0.30), 0.44),
            ((0.0, 6.85, mz_z + 0.26), ( half_beam(-1.45, 0.95), sheer_y(-1.45) + 0.10, -1.45), 0.40),
            (yd_l + Vector((0.30, 0.06, 0.0)), (-half_beam(-2.40, 0.92), sheer_y(-2.40) + 0.08, -2.40), 0.52),
            (yd_r + Vector((-0.25, -0.05, 0.0)), (half_beam(0.80, 0.85), sheer_y(0.80) - 0.12, 0.80), 0.58),
        ]
        for p_a, p_b, sag in shroud_specs:
            va, vb = Vector(p_a), Vector(p_b)
            pts = []
            for k in range(6):
                t = k / 5.0
                q = va.lerp(vb, t)
                q.y -= sag * 4.0 * t * (1.0 - t)
                pts.append(q)
            tube(mb, pts, 0.036, 4, 'rope', jit(C_ROPE, rng, 0.05), mode='smooth')

        # 9. ONE Tilted Ornate Brass Stern Lantern Crowning the Taffrail!
        taff_peak = Vector((0.0, 4.68, transom_z(4.20) - 0.38))
        lan_local = taff_peak + Vector((0.0, 0.88, -0.26))
        tube(mb, [
            taff_peak + Vector((0.0, -0.22, 0.06)),
            taff_peak + Vector((0.0,  0.14, -0.18)),
            lan_local + Vector((0.0, -0.58, 0.0)),
        ], [0.082, 0.068, 0.058], 5, 'brass', C_TEMPLE_GOLD, mode='flat')
        _build_ornate_galleon_lantern(mb, lan_local, scale=1.08)

        # Anchor points for 3 hanging sea-kelp drapes strictly OUTSIDE the transom balcony & counter (ZERO clipping!)
        kelp_anchors_local = [
            (Vector((-1.78, 1.38, transom_z(1.38) - 0.42)), 2.55, 0.28, Vector((-0.34, 0.0, -0.94))),
            (Vector(( 0.88, 1.38, transom_z(1.38) - 0.48)), 2.35, 0.26, Vector(( 0.18, 0.0, -0.98))),
            (Vector(( 2.48, 1.68, -2.98)),                  2.60, 0.28, Vector(( 0.76, 0.0, -0.65))),
        ]

    # 10. Bold Barnacled Mossy Limestone Reef Rocks Clutching the Submerged Starboard Quarter (+X, y -> -3.65 m!)
    reef_specs = [
        # Broad submerged starboard-quarter reef ledge cradling the heeled hull down to y = -3.65 m!
        (( 2.65, -1.55, -0.85), (2.45, 2.35, 2.75), ( 4,  18, -8), 0.32, 0.66),
        # Tall craggy mossy reef fang rising dramatically to y ~ +2.6 m clutching starboard stern quarter!
        (( 3.45,  0.15, -2.15), (1.65, 2.95, 1.85), (-6, -24, 14), 0.26, 0.78),
        # Second jagged starboard reef rock hugging the heeled waist & broken starboard planks!
        (( 3.15, -0.75,  1.65), (1.85, 2.75, 2.15), ( 5,  38, -12), 0.28, 0.64),
        # Low sandbar reef outcrop beneath the shattered rudder & keel (plunging cleanly to y = -3.65 m!)
        ((-0.45, -2.35, -2.35), (2.65, 1.55, 2.15), ( 2, -12,  4), 0.36, 0.48),
        # Port-aft grounding reef outcrop stabilizing the broken rear hull down to y = -3.65 m
        ((-2.35, -2.15,  1.85), (1.95, 1.75, 2.15), (-4,  28,  6), 0.30, 0.54),
    ]
    for ctr, rad, rot_d, bf, mc in reef_specs:
        pts = sculpt_rock_mass(
            mb, ctr, rad, 'limestone_moss',
            C_LEDGE_MOSS if mc > 0.58 else C_LIME_WARM, C_LIME_MID, C_LIME_DARK, rng,
            subdiv=2, warp=0.24, strata=0.16, base_flare=bf,
            rot_deg=rot_d, crag_ribs=5, rib_amp=0.15, moss_cap=mc,
        )
        hull_col_pts.extend(pts)

    # 11. Three Hanging Sea-Kelp / Seaweed Drapes ('foliage' with UV2 wind!)
    for idx, (anc_l, klen, kw, odir_l) in enumerate(kelp_anchors_local):
        anc_w = hull_X @ anc_l
        odir_w = (hull_X.to_3x3() @ odir_l).normalized()
        _add_kelp_drape(mb, anc_w, klen, kw, odir_w, rng, phase=0.18 + idx * 0.31, segs=5)

    build(mb)

    lantern_world = hull_X @ lan_local
    add_empty('Lantern_Stern', (lantern_world.x, lantern_world.y, lantern_world.z))
    col_piece('col_stern_hull', hull_col_pts)
    col_piece('col_stern_deck', deck_col_pts)
    export_landmark_glb(outdir, 'sunken_galleon_stern.glb')


# ================================================================ 3. GIANT TIDAL CORAL ARCH

def gen_giant_tidal_coral_arch(outdir):
    """Vibrant painterly coastal coral-reef arch & tide-pool outcrop (~10.5 m wide x ~6.2 m tall,
    flared barnacled legs plunging solidly to y = -3.2 m for crystal turquoise shallows!).
    Wave-eroded mossy limestone twin-pier arch with an open ~3.8 m central shallow-water opening,
    encrusted with lush sculptural clusters of branching coral staghorn tubes, layered fan-coral
    plates & reef sponges ('paint' vibrant coral-pink, sunset-orange, turquoise & golden-ochre),
    plus 4 hanging sea-kelp ribbons ('foliage' with UV2 wind).
    Colliders preserving open arch: col_coral_left, col_coral_right.
    Target: 1,800-3,000 visual tris.
    """
    clear_scene()
    rng = random.Random(SEED + 1087)
    mb = MB('GiantTidalCoralArch', seed=1087)

    # 1. Continuous Organic Wave-Eroded Limestone Sea-Arch sweeping gracefully from left foot
    #    (x=-3.55, y=-3.25) over the vaulted mossy crown (y~5.0) down to right foot (x=+3.55, y=-3.25)!
    #    Clear central archway opening: ~3.85 m wide (x = -1.92..+1.92) x ~3.85 m high!
    arch_stations = [
        # (center_xyz, r_radial, r_z, twist_deg)
        ((-3.68, -3.25,  0.08), 1.62, 1.85,  0.0),
        ((-3.56, -1.25,  0.05), 1.44, 1.66,  4.0),
        ((-3.38,  0.65,  0.02), 1.28, 1.50,  8.0),
        ((-3.08,  2.35, -0.02), 1.16, 1.40,  6.0),
        ((-2.42,  3.82, -0.04), 1.12, 1.38,  2.0),
        ((-1.28,  4.75, -0.02), 1.06, 1.36, -2.0),
        (( 0.06,  5.12,  0.02), 1.08, 1.42,  0.0),
        (( 1.42,  4.84,  0.04), 1.14, 1.40,  3.0),
        (( 2.48,  3.90,  0.02), 1.20, 1.42, -2.0),
        (( 3.12,  2.42,  0.00), 1.22, 1.44, -6.0),
        (( 3.42,  0.68, -0.04), 1.32, 1.54, -8.0),
        (( 3.60, -1.25, -0.06), 1.48, 1.68, -4.0),
        (( 3.72, -3.25, -0.08), 1.66, 1.88,  0.0),
    ]
    pts_l, pts_r = _sculpt_continuous_coral_arch(mb, arch_stations, sides=7, rng=rng)

    # Outer wave-carved reef foot shoulders & asymmetric tide-pool crown ridge (~10.5 m wide x ~6.2 m tall!)
    pts_l += sculpt_rock_mass(
        mb, (-4.18, -1.25, 0.22), (1.08, 2.05, 1.35), 'limestone_moss',
        C_LEDGE_MOSS, C_LIME_MID, C_LIME_DARK, rng,
        subdiv=1, warp=0.22, strata=0.14, base_flare=0.28,
        rot_deg=(4, -18, 12), crag_ribs=5, rib_amp=0.14, moss_cap=0.68,
    )
    pts_r += sculpt_rock_mass(
        mb, (4.20, -1.15, -0.22), (1.10, 2.15, 1.35), 'limestone_moss',
        C_LEDGE_MOSS, C_LIME_MID, C_LIME_DARK, rng,
        subdiv=1, warp=0.22, strata=0.14, base_flare=0.28,
        rot_deg=(-4, 22, -12), crag_ribs=5, rib_amp=0.14, moss_cap=0.70,
    )
    # Asymmetric mossy tide-pool limestone crown crest on starboard arch shoulder (peaks at y ≈ 6.18 m!)
    sculpt_rock_mass(
        mb, (1.92, 5.42, -0.06), (1.35, 0.82, 1.12), 'limestone_moss',
        C_GRASS_SUN, C_LEDGE_MOSS, C_LIME_WARM, rng,
        subdiv=1, warp=0.18, strata=0.12, flat_top=0.45,
        rot_deg=(-3, 14, -10), crag_ribs=5, rib_amp=0.12, moss_cap=0.84,
    )

    # 2. LUSH, BOLD Sculptural Branching Staghorn Coral Colonies ('paint' vibrant painterly reef palette!)
    staghorn_specs = [
        # (base_pos, grow_dir, scale, col_base, col_tip, branches)
        ((-4.15, 1.15, -0.95), (-0.48, 0.76, -0.44), 1.42, C_CORAL_ROSE,   C_CORAL_PINKHI, 4),
        ((-2.95, 3.65, -0.92), (-0.38, 0.80, -0.44), 1.32, C_CORAL_RUST,   C_CORAL_AMBER,  4),
        ((-1.05, 5.25, -0.35), (-0.34, 0.88, -0.32), 1.04, C_CORAL_TEAL,   C_CORAL_AQUA,   4),
        (( 1.55, 5.42, -0.30), ( 0.36, 0.86, -0.32), 1.06, C_CORAL_ROSE,   C_CORAL_PINK,   4),
        (( 3.38, 2.85, -1.02), ( 0.42, 0.76, -0.48), 1.42, C_CORAL_OCHRE,  C_CORAL_LEMON,  4),
        (( 4.25, 0.78, -0.78), ( 0.58, 0.70, -0.40), 1.38, C_CORAL_RUST,   C_CORAL_ORANGE, 3),
        ((-3.35, 2.35,  1.05), (-0.36, 0.80,  0.48), 1.32, C_CORAL_TEAL,   C_CORAL_TURQ,   3),
        (( 3.35, 3.15,  0.98), ( 0.36, 0.80,  0.46), 1.34, C_CORAL_ROSE,   C_CORAL_PINKHI, 3),
    ]
    for bpos, gdir, sc, cb, ct, nbr in staghorn_specs:
        _add_staghorn_coral_cluster(mb, bpos, gdir, sc, cb, ct, rng, branches=nbr)

    # 3. Tiered Overlapping Acropora Fan-Coral / Table-Coral Shelf Rosettes ('paint', double-sided!)
    plate_specs = [
        # Port waterline & mid-pier sunset-orange / golden-ochre / coral-pink reef rosettes
        ((-4.12, 0.42, -0.92), 1.18, 0.96, 0.18, ( 12, -22,  16), C_CORAL_RUST,   C_CORAL_ORANGE),
        ((-3.88, 0.92, -1.14), 0.92, 0.76, 0.15, ( 10,  14,  12), C_CORAL_ORANGE, C_CORAL_AMBER),
        ((-2.48, 2.15, -1.08), 1.04, 0.84, 0.16, ( -8,  18, -16), C_CORAL_ROSE,   C_CORAL_PINK),
        ((-2.28, 2.68, -0.92), 0.80, 0.66, 0.14, ( -6, -12, -12), C_CORAL_PINK,   C_CORAL_PINKHI),
        ((-3.75, 3.05,  0.95), 1.06, 0.86, 0.16, (-12,  32,  14), C_CORAL_OCHRE,  C_CORAL_GOLD),
        # Starboard waterline & mid-pier turquoise / golden-ochre / sunset-orange reef rosettes
        (( 4.18, 0.38, -0.82), 1.22, 0.98, 0.18, ( 10,  28, -16), C_CORAL_TEAL,   C_CORAL_TURQ),
        (( 3.92, 0.92, -1.10), 0.94, 0.78, 0.15, ( 12, -16, -12), C_CORAL_TURQ,   C_CORAL_AQUA),
        (( 2.48, 2.38, -1.04), 1.06, 0.86, 0.16, ( -8, -20,  16), C_CORAL_OCHRE,  C_CORAL_LEMON),
        (( 2.32, 2.92, -0.88), 0.82, 0.68, 0.14, ( -6,  14,  12), C_CORAL_RUST,   C_CORAL_ORANGE),
        (( 3.78, 3.35,  0.92), 1.08, 0.88, 0.16, (-10, -26, -14), C_CORAL_ROSE,   C_CORAL_PINK),
        # Arch crown cascading coral-table shelves
        ((-0.58, 4.98, -1.16), 0.98, 0.78, 0.15, ( 16,  10,   4), C_CORAL_ORANGE, C_CORAL_AMBER),
        (( 0.88, 5.10,  1.12), 1.02, 0.80, 0.15, (-16, -12,  -4), C_CORAL_TEAL,   C_CORAL_AQUA),
    ]
    for ctr, rx, rz, th, rot_d, ci, cr in plate_specs:
        _add_fan_coral_plate(mb, ctr, rx, rz, th, rot_d, ci, cr, rng, sides=7)

    # 4. Chunky Clustered Tubular Tropical Reef Sponges nestled in the tidal crevices ('paint')!
    sponge_specs = [
        ((-2.52, 0.18, -1.18), ( 12, -24, -14), 1.28, C_CORAL_OCHRE,  C_CORAL_LEMON,  3),
        (( 2.58, 0.22, -1.15), ( 12,  28,  16), 1.32, C_CORAL_ROSE,   C_CORAL_PINKHI, 3),
        ((-4.32, 0.05,  0.65), (-10,  42,  18), 1.18, C_CORAL_TEAL,   C_CORAL_AQUA,   3),
        (( 4.30, 0.15,  0.70), (-12, -38, -16), 1.22, C_CORAL_RUST,   C_CORAL_AMBER,  3),
        (( 0.35, 5.38, -0.45), (  8,  12,  -4), 0.96, C_CORAL_TURQ,   C_CORAL_AQUA,   3),
    ]
    for bpos, rot_d, sc, cb, cr, nt in sponge_specs:
        _add_reef_sponge_cluster(mb, bpos, rot_d, sc, cb, cr, rng, tubes=nt)

    # 5. Four Sinuous Hanging Sea-Kelp Ribbons framing the open tidal archway cleanly ('foliage' with UV2 wind!)
    kelp_specs = [
        ((-1.58, 4.32, -1.18), 2.15, 0.23, (-0.16, 0.0, -0.98), 0.12),
        (( 0.42, 4.52, -1.26), 1.68, 0.21, ( 0.06, 0.0, -0.99), 0.41),
        (( 1.72, 4.36, -1.18), 2.18, 0.24, ( 0.18, 0.0, -0.98), 0.69),
        ((-1.35, 4.40,  1.22), 2.08, 0.23, (-0.16, 0.0,  0.98), 0.88),
    ]
    for anc, klen, kw, odir, ph in kelp_specs:
        _add_kelp_drape(mb, anc, klen, kw, odir, rng, phase=ph, segs=5)

    build(mb)

    # Colliders preserving the wide-open ~3.84 m central shallow-water archway!
    left_col_pts = [Vector((min(p.x, -1.92), p.y, p.z)) for p in pts_l]
    right_col_pts = [Vector((max(p.x,  1.92), p.y, p.z)) for p in pts_r]
    col_piece('col_coral_left', left_col_pts)
    col_piece('col_coral_right', right_col_pts)
    export_landmark_glb(outdir, 'giant_tidal_coral_arch.glb')


# ================================================================ 4. OBSIDIAN LAVA CAULDRON SHRINE

def gen_obsidian_lava_cauldron_shrine(outdir):
    """Volcanic biome setpiece (~6.4 m wide x ~5.8 m tall, plunging solidly to y = -2.2 m) crafted
    for Cinder Crag! Crown of 7 leaning jagged black hexagonal basalt obelisk teeth framing a wide
    fractured volcanic stone cauldron basin filled with swirling glowing incandescent molten magma
    crust ('glass' blazing orange-gold + dark basalt crust islands), banded by a hollow spiked forged
    dark-iron altar collar, 4 heavy iron chain-links anchored into surrounding basalt spurs,
    tarnished brass compass-skull medallion, and Empty Lantern_CalderaShrine centered above the
    glowing magma basin!
    Collider: col_cauldron_shrine.
    Target: 2,200-3,400 visual tris.
    """
    clear_scene()
    rng = random.Random(SEED + 1123)
    mb = MB('ObsidianLavaCauldronShrine', seed=1123)

    col_pts = []

    # 1. Deep Grounded Fractured Volcanic Stone Foundation & Wide Cauldron Basin (plunging to y = -2.25 m!)
    col_pts += sculpt_rock_mass(
        mb, (0.0, -0.78, 0.0), (2.68, 1.56, 2.66), 'basalt',
        C_BASALT_TOP, C_BASALT_MID, C_BASALT_DARK, rng,
        subdiv=2, warp=0.20, strata=0.14, base_flare=0.26,
        flat_top=0.45, rot_deg=(0, 12, 0), crag_ribs=7, rib_amp=0.16,
    )

    # Wide fractured decagonal volcanic stone cauldron basin (y = -0.50 .. +2.10 m)
    # Hollow interior rim holds the swirling glowing molten magma pool at y ≈ 1.88 m!
    n_c = 10
    cauldron_prof = [
        (0.00, -0.50),
        (1.98, -0.50),
        (2.10,  0.18),
        (1.78,  0.88),
        (1.90,  1.58),
        (2.06,  2.06),
        (1.74,  2.14),
        (1.56,  1.98),
        (1.42,  1.52),
        (0.00,  1.48),
    ]
    caul_cols = [
        C_BASALT_DARK, C_BASALT_DARK, C_BASALT_MID, C_BASALT_MID,
        mix(C_BASALT_TOP, C_BASALT_HOT, 0.16),
        mix(C_BASALT_TOP, C_BASALT_HOT, 0.24),
        mix(C_BASALT_MID, C_BASALT_HOT, 0.34),
        mix(C_BASALT_DARK, C_BASALT_HOT, 0.48),
        C_BASALT_HOT,
    ]
    lathe(mb, cauldron_prof, n_c, 'basalt', C_BASALT_MID, smooth=False,
          colfn=lambda i, k: jit(caul_cols[min(i, len(caul_cols) - 1)], rng, 0.05))
    for k in range(n_c):
        ang = 2.0 * pi * k / float(n_c)
        col_pts.append(Vector((cos(ang) * 2.12, 2.10, sin(ang) * 2.12)))

    # Slim jagged glowing molten lava cracks tucked into the cauldron's dark outer stone flanks!
    for k in range(5):
        ang = 2.0 * pi * k / 5.0 + 0.35
        ca, sa = cos(ang), sin(ang)
        side_v = Vector((-sa, 0.0, ca))
        out_v = Vector((ca, 0.0, sa))
        p0 = Vector((ca * 1.92, 0.38, sa * 1.92))
        p1 = Vector((ca * 1.84, 1.02, sa * 1.84)) + side_v * 0.07
        p2 = Vector((ca * 1.98, 1.72, sa * 1.98)) - side_v * 0.04
        for q0, q1, w0, w1 in ((p0, p1, 0.024, 0.052), (p1, p2, 0.052, 0.028)):
            in_p = 0.5 * (q0 + q1) - out_v * 0.5
            mb.fp([
                q0 - side_v * w0 + out_v * 0.025,
                q0 + side_v * w0 + out_v * 0.025,
                q1 + side_v * w1 + out_v * 0.025,
                q1 - side_v * w1 + out_v * 0.025,
            ], 'glass', C_MAGMA_MID, (0, 1, 0), in_p, smooth=False)

    # 2. Crown of 7 Leaning Jagged Black Hexagonal Basalt Obelisk Teeth ('basalt', ~6.8 m wide x ~5.8 m tall!)
    #    Wide ceremonial front (-Z) framing the blazing molten cauldron & brass medallion; tallest fangs rear & flanks!
    obelisk_specs = [
        # (angle_deg, dist, height_from_bot, radius, tilt_deg_out, magma_seam)
        (  90.0, 2.02, 7.98, 0.62,  7.5, True),   # Hero towering rear (+Z) fang peaking at y ≈ 5.78 m!
        (  46.0, 2.06, 7.36, 0.58,  9.0, True),   # Rear-starboard tall fang (~5.16 m)
        ( 134.0, 2.06, 7.48, 0.58,  8.8, True),   # Rear-port tall fang (~5.28 m)
        (   8.0, 2.10, 6.64, 0.55, 10.2, True),   # Starboard flank fang (~4.44 m)
        ( 172.0, 2.10, 6.76, 0.55, 10.0, True),   # Port flank fang (~4.56 m)
        ( -36.0, 2.18, 5.58, 0.50, 11.2, False),  # Front-starboard guardian tooth (~3.38 m)
        (-144.0, 2.18, 5.70, 0.50, 11.0, False),  # Front-port guardian tooth (~3.50 m)
    ]
    obelisk_anchors = {}
    for oi, (ang_d, dist, h_tot, rad, tilt_out, seam) in enumerate(obelisk_specs):
        ang = radians(ang_d)
        bx, bz = cos(ang) * dist, sin(ang) * dist
        tx = cos(ang) * tilt_out
        tz = sin(ang) * tilt_out
        pts_ob = _sculpt_jagged_basalt_obelisk(
            mb, (bx, -2.20, bz), h_tot, rad, tx, tz,
            C_BASALT_DARK, mix(C_BASALT_TOP, C_BASALT_HOT, 0.16 if seam else 0.05),
            rng, magma_seam=seam,
        )
        col_pts.extend(pts_ob[::3])
        if oi in (1, 2, 5, 6):
            t_anc = 0.54 if oi in (5, 6) else 0.56
            ay = -2.20 + t_anc * h_tot
            ax = bx + sin(radians(tx)) * (t_anc * h_tot) - cos(ang) * (rad * 0.65)
            az = bz + sin(radians(tz)) * (t_anc * h_tot) - sin(ang) * (rad * 0.65)
            obelisk_anchors[oi] = (ang, Vector((ax, ay, az)))

    # 3. Swirling Glowing Incandescent Molten Magma Surface ('glass') + Dark Basalt Crust Islands!
    #    Open to the sky directly inside the hollow spiked iron rim (y ≈ 1.90 m)!
    magma_y = 1.90
    r_pool = 1.62
    rings_m = [0.0, 0.46, 1.02, r_pool]
    segs_m = 12
    m_rings = []
    for ri, rm in enumerate(rings_m):
        if rm < 1e-4:
            m_rings.append([Vector((0.0, magma_y + 0.12, 0.0))] * segs_m)
        else:
            rpts = []
            for k in range(segs_m):
                ang = 2.0 * pi * k / float(segs_m) + ri * 0.34
                wave = 0.075 * sin(ang * 3.0 + ri * 1.8) * (1.0 - ri / 4.2)
                rpts.append(Vector((cos(ang) * rm, magma_y + wave, sin(ang) * rm)))
            m_rings.append(rpts)

    mag_ring_cols = [C_MAGMA_CORE, C_LANTERN_GL, C_MAGMA_MID, C_MAGMA_DEEP]
    mb.newoff()
    for ri in range(len(m_rings) - 1):
        r0, r1 = m_rings[ri], m_rings[ri + 1]
        c0 = mag_ring_cols[ri]
        c1 = mag_ring_cols[ri + 1]
        for k in range(segs_m):
            kn = (k + 1) % segs_m
            if ri == 0:
                tri = [r0[0], r1[kn], r1[k]]
                mb.fp(tri, 'glass', [c0, jit(c1, rng, 0.05), jit(c1, rng, 0.05)],
                      (1, 0, 0), Vector((0.0, magma_y - 1.5, 0.0)), smooth=False)
            else:
                q = [r0[k], r0[kn], r1[kn], r1[k]]
                mb.fp(q, 'glass', [jit(c0, rng, 0.05), jit(c0, rng, 0.05), jit(c1, rng, 0.05), jit(c1, rng, 0.05)],
                      (1, 0, 0), Vector((0.0, magma_y - 1.5, 0.0)), smooth=False)

    # 4 Jagged Dark Cooling Basalt Crust Islands floating visibly atop the swirling molten magma!
    crust_specs = [
        ((-0.66, magma_y + 0.06, -0.44), (0.44, 0.16, 0.34), ( 4,  28, -6)),
        (( 0.68, magma_y + 0.06,  0.38), (0.46, 0.17, 0.36), (-5, 118,  8)),
        ((-0.34, magma_y + 0.05,  0.80), (0.38, 0.15, 0.30), ( 6, 212, -4)),
        (( 0.52, magma_y + 0.05, -0.74), (0.36, 0.14, 0.28), (-4, 305,  5)),
    ]
    for cpos, crad, crot in crust_specs:
        sculpt_rock_mass(
            mb, cpos, crad, 'basalt',
            C_BASALT_DARK, C_BASALT_MID, C_BASALT_HOT, rng,
            subdiv=1, warp=0.18, strata=0.06, flat_top=0.40,
            rot_deg=crot, crag_ribs=5, rib_amp=0.12,
        )

    # 3 Stylized Blazing Incandescent Lava Plume Tongues rising cleanly out of the cauldron core!
    for lpos, (lrx, lry), lrot, lcol in (
        (( 0.00, magma_y + 0.16,  0.00), (0.24, 0.80), ( 3,   0,  4), C_MAGMA_CORE),
        ((-0.24, magma_y + 0.12,  0.18), (0.17, 0.58), (-8,  35, 14), C_MAGMA_GLOW),
        (( 0.22, magma_y + 0.14, -0.20), (0.18, 0.62), (10, -45, -12), C_LANTERN_GL),
    ):
        with xf(mb, T(lpos) @ R('Y', lrot[1]) @ R('X', lrot[0]) @ R('Z', lrot[2])):
            prof = [(0.0, -lry * 0.22), (lrx, 0.0), (lrx * 0.65, lry * 0.48), (0.0, lry)]
            lathe(mb, prof, 5, 'glass', jit(lcol, rng, 0.05), smooth=False)

    # 4. HOLLOW Spiked Forged Dark-Iron Altar Collar banded tightly around cauldron rim ('iron')!
    #    Crucially hollow (r_in = 1.94 .. r_out = 2.16) so the blazing magma basin stays 100% open & glowing!
    collar_y = 2.00
    collar_r = 2.08
    collar_prof = [
        (1.92, collar_y - 0.15),
        (2.16, collar_y - 0.15),
        (2.18, collar_y + 0.15),
        (1.92, collar_y + 0.15),
        (1.92, collar_y - 0.15),
    ]
    lathe(mb, collar_prof, n_c, 'iron', C_IRON, smooth=False)
    with xf(mb, T(0.0, collar_y + 0.15, 0.0)):
        torus(mb, collar_r + 0.03, 0.044, n_c, 4, 'iron', C_IRON_RUST, False)
    with xf(mb, T(0.0, collar_y - 0.15, 0.0)):
        torus(mb, collar_r + 0.02, 0.042, n_c, 4, 'iron', C_IRON, False)

    # 10 wicked forged dark-iron altar spikes jutting menacingly outward & upward from the collar!
    for k in range(n_c):
        ang = 2.0 * pi * k / float(n_c) + pi / float(n_c)
        ca, sa = cos(ang), sin(ang)
        yaw_d = -degrees(ang)
        sp_pos = (ca * (collar_r + 0.04), collar_y + 0.08, sa * (collar_r + 0.04))
        with xf(mb, T(sp_pos) @ R('Y', yaw_d) @ R('Z', -42.0)):
            cyl(mb, 0.090, -0.06, 0.54, 4, 'iron', C_IRON_RUST if k % 3 == 0 else C_IRON, False, 0.0, 0.015)

    # 5. Four Heavy Hammered Iron Chains Anchoring the Spiked Collar to Surrounding Basalt Spurs ('iron')!
    for oi, (ang, p_spur) in obelisk_anchors.items():
        ca, sa = cos(ang), sin(ang)
        p_col_shackle = Vector((ca * (collar_r + 0.08), collar_y - 0.02, sa * (collar_r + 0.08)))
        yaw_d = -degrees(ang)
        with xf(mb, T(p_col_shackle) @ R('Y', yaw_d) @ M_Y2Z):
            torus(mb, 0.115, 0.034, 6, 4, 'iron', C_IRON_RUST, False)
        with xf(mb, T(p_spur) @ R('Y', yaw_d)):
            cbox(mb, (0.0, 0.0, 0.0), (0.28, 0.32, 0.28), 'iron', C_IRON_RUST, 0.0)
        _add_chain_links(
            mb, p_col_shackle, p_spur,
            n_links=5, link_r=0.092, wire_r=0.029, segs=6, psegs=4, sag=0.18, rust_stride=2,
        )

    # 6. Tarnished Brass Compass-Skull Medallion mounted proudly on the seaward (-Z) cauldron face!
    med_pos = (0.0, 1.12, -1.98)
    with xf(mb, T(med_pos) @ R('X', 6.0)):
        with xf(mb, M_Y2Z):
            cyl(mb, 0.68, -0.04, 0.18, 8, 'basalt', C_BASALT_DARK, False, 0.0)
        with xf(mb, T(0.0, 0.0, -0.05) @ M_Y2Z):
            torus(mb, 0.56, 0.058, 8, 4, 'brass', C_TEMPLE_GOLD, False)
        for k in range(8):
            is_card = (k % 2 == 0)
            r_len = 0.72 if is_card else 0.52
            r_w = 0.095 if is_card else 0.064
            with xf(mb, R('Z', k * 45.0)):
                p_in = Vector((0.0, 0.22, -0.055))
                p_l  = Vector((-r_w, r_len * 0.48, -0.055))
                p_t  = Vector((0.0, r_len, -0.050))
                p_r  = Vector(( r_w, r_len * 0.48, -0.055))
                apex = Vector((0.0, r_len * 0.48, -0.115))
                in_ref = Vector((0.0, r_len * 0.48, 0.30))
                mb.fp([p_in, p_l, p_t, apex], 'brass', C_TEMPLE_GOLD if is_card else C_BRASS, (0, 1, 0), in_ref)
                mb.fp([p_t, p_r, p_in, apex], 'brass', mul(C_BRASS, 0.88), (0, 1, 0), in_ref)
        with xf(mb, T(0.0, 0.07, -0.08) @ M_Y2Z):
            cyl(mb, 0.28, -0.05, 0.08, 8, 'brass', C_BRASS, False, 0.0, 0.22)
        cbox(mb, (0.0, -0.15, -0.095), (0.34, 0.22, 0.11), 'brass', C_TEMPLE_GOLD, 0.0)
        for sx in (-0.105, 0.105):
            cbox(mb, (sx, 0.04, -0.145), (0.11, 0.10, 0.05), 'basalt', C_BASALT_DARK, 0.0)
        cbox(mb, (0.0, -0.06, -0.145), (0.065, 0.075, 0.05), 'basalt', C_BASALT_DARK, 0.0, M=R('Z', 45.0))
        for tx in (-0.105, -0.035, 0.035, 0.105):
            cbox(mb, (tx, -0.25, -0.11), (0.048, 0.095, 0.08), 'brass', C_BRASS, 0.0)

    build(mb)

    add_empty('Lantern_CalderaShrine', (0.0, 2.55, 0.0))
    col_piece('col_cauldron_shrine', col_pts)
    export_landmark_glb(outdir, 'obsidian_lava_cauldron_shrine.glb')


COASTAL_GENERATORS = [
    gen_pirate_camp_canopy,
    gen_sunken_galleon_stern,
    gen_giant_tidal_coral_arch,
    gen_obsidian_lava_cauldron_shrine,
]
