# Sea of Scoundrels: 6 signature Sea-of-Thieves-grade island landmark set-pieces.
# Imported by tools/blender/gen_island_landmarks.py.
# Authored in Godot game coordinates (-Z forward/seaward, +Y up, +X starboard, metres).
import bmesh, math, random
from math import sin, cos, pi, sqrt, atan2, radians, degrees
from mathutils import Vector, Matrix

from _landmark_common import (
    SEED,
    srgb, mul, mix, jit, smooth01,
    C_LIME_PALE, C_LIME_WARM, C_LIME_MID, C_LIME_SHADE, C_LIME_DARK,
    C_SEA_MOSS, C_LEDGE_MOSS, C_GRASS_SUN, C_GRASS_DEEP,
    C_BASALT_TOP, C_BASALT_MID, C_BASALT_DARK,
    C_SKULL_BONE, C_SKULL_MID, C_SKULL_SHADE, C_SKULL_CAV, C_SKULL_EYE,
    C_TEMPLE_HI, C_TEMPLE_MID, C_TEMPLE_DARK, C_TEMPLE_GOLD,
    C_TIMBER_HI, C_TIMBER_MID, C_TIMBER_DARK, C_DRIFTWOOD,
    C_PAINT_RED, C_PAINT_TEAL, C_PAINT_CREAM,
    C_ROPE, C_IRON, C_IRON_RUST, C_BRASS, C_LANTERN_GL,
    C_LEAF_DEEP, C_LEAF_SUN,
    T, R, S, M_Y2Z, M_Y2X, newell,
    MB, xf,
    cbox, sculpt_stone_block, loft, lathe, tube, cyl, torus, rope_coil,
    build_lantern_geom, sculpt_rock_mass, add_vine_drape,
    clear_scene, build, col_piece, col_box, add_empty, export_landmark_glb,
)


# ---------------------------------------------------------------- local sculpting helpers
def _box2(mb, lo, hi, mat, col, ch=0.025, grain=None, skip=()):
    c = ((lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5, (lo[2] + hi[2]) * 0.5)
    sz = (hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2])
    cbox(mb, c, sz, mat, col, ch, grain, skip=skip)


def _sculpt_ribbon_arch(mb, stations, mat, col_fn, rng, closed_caps=(True, True)):
    """Loft a smooth multi-station chiseled stone ridge/arch with elliptical faceted cross-sections.
    Each station is (center_vec, rx, ry, rz_fwd, tilt_deg, color_t).
    """
    secs = []
    scols = []
    n = len(stations)
    sides = 8
    for i, (ctr, rw, rh, rot_z, ct) in enumerate(stations):
        c = Vector(ctr)
        # Tangent along arch
        p_prev = Vector(stations[max(0, i - 1)][0])
        p_next = Vector(stations[min(n - 1, i + 1)][0])
        tang = (p_next - p_prev)
        if tang.length < 1e-5:
            tang = Vector((1, 0, 0))
        tang.normalize()
        up = Vector((0, 1, 0))
        fwd = tang.cross(up)
        if fwd.length < 1e-4:
            fwd = Vector((0, 0, -1))
        fwd.normalize()
        up_o = fwd.cross(tang).normalized()
        # Rotate section subtly around tangent by rot_z
        ca_t, sa_t = cos(radians(rot_z)), sin(radians(rot_z))
        u_vec = fwd * ca_t + up_o * sa_t
        v_vec = -fwd * sa_t + up_o * ca_t
        ring = []
        for k in range(sides):
            a = 2.0 * pi * k / sides
            # Slightly squarish-beveled carved stone cross-section
            ca, sa = cos(a), sin(a)
            squarish = 1.0 + 0.08 * cos(4.0 * a)
            pt = c + u_vec * (ca * rw * squarish) + v_vec * (sa * rh * squarish)
            ring.append(pt)
        secs.append(ring)
        scols.append(jit(col_fn(ct), rng, 0.04, 0.015))
    loft(mb, secs, mat, col_fn(0.5), closed=True, caps=closed_caps, mode='flat', scols=scols)


def _sculpt_skull_cranium(mb, rng):
    """Sculpt a towering, faceted, cracked pirate skull cranium dome (y=8.2..15.4 m, facing -Z)."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=3, radius=1.0)
    center = Vector((0.0, 11.70, -0.60))

    for v in bm.verts:
        p = v.co.copy()
        x, y, z = p.x, p.y, p.z

        # Broad bulbous upper parietal skull dome, cleanly pinched inward at lower temples
        parietal = smooth01((y + 0.10) / 0.90)
        rx = 4.65 + 0.78 * parietal - 0.50 * max(0.0, y - 0.58)
        ry = 3.78
        rz = 3.85 + 0.35 * parietal

        # Sculpted temporal hollows along lower-sides so brows & cheekbones read boldly
        temp_zone = max(0.0, 1.0 - ((y + 0.42) / 0.48) ** 2) * max(0.0, (abs(x) - 0.42) / 0.58)
        temp_zone *= max(0.0, 1.0 - max(0.0, z - 0.10) * 1.4)
        rx -= 0.78 * temp_zone

        # Subtle sagittal ridge & painterly flat chisel facets
        sagittal = 0.22 * max(0.0, 1.0 - abs(x) * 2.4) * max(0.0, y)
        chisel = (
            0.12 * sin(x * 5.0 + y * 3.1)
            + 0.09 * cos(y * 6.0 - z * 4.2)
            + 0.07 * sin(z * 5.4 + x * 3.9)
        )

        # Subtle carved fracture groove slashing up-right across right forehead/temple
        crack_dist = abs((x - 0.28) * 0.78 - (y - 0.20) * 0.63)
        in_front = smooth01((-z - 0.14) / 0.45) * smooth01((x + 0.02) / 0.30)
        crack_notch = max(0.0, 1.0 - crack_dist / 0.065) * in_front

        # Stylized carved stone pirate bandana / brow-scar bevel sweeping across forehead
        band_y = -0.22 + 0.22 * x + 0.04 * sin(x * 3.0)
        band_d = abs(y - band_y)
        band_ridge = max(0.0, 1.0 - band_d / 0.13) * smooth01((-z + 0.20) / 0.65) * 0.24

        px = x * rx + (0.0 if abs(x) < 0.05 else (1.0 if x > 0 else -1.0)) * chisel * 0.38
        py = y * ry + sagittal + chisel * 0.30
        pz = z * rz - band_ridge + crack_notch * 0.36 + chisel * 0.34

        # Broad bold forehead plane facing seaward (-Z)
        if z < -0.25 and y > -0.35 and y < 0.55:
            pz += 0.20 * smooth01((-z - 0.25) / 0.65) * (1.0 - abs(x) * 0.40)

        # Tuck underside smoothly into brow & skull core
        if y < -0.60:
            py = -0.60 * ry + (py + 0.60 * ry) * 0.42

        v.co = center + Vector((px, py, pz))

    bm.faces.ensure_lookup_table()
    mb.newoff()
    for f in bm.faces:
        pts = [v.co.copy() for v in f.verts]
        fn = newell(pts)
        if fn.length < 1e-8:
            continue
        fn.normalize()
        fc = sum(pts, Vector()) / len(pts)

        if fn.y > 0.55:
            moss_t = smooth01((fc.z + 0.35) / 2.8) * 0.34
            c = mix(C_SKULL_BONE, C_LEDGE_MOSS, moss_t)
        elif fn.y < -0.28:
            c = mul(C_SKULL_SHADE, 0.80)
        else:
            h_t = smooth01((fc.y - 8.8) / 6.2)
            front_t = smooth01((-fc.z - 0.4) / 3.8)
            c = mix(C_SKULL_MID, C_SKULL_BONE, 0.35 + 0.55 * front_t * (0.4 + 0.6 * h_t))

        mb.fp(pts, 'skull_stone', jit(c, rng, 0.04, 0.015), (1, 0, 0), center, smooth=False)
    bm.free()


def _sculpt_skull_eye_cavity(mb, cx, cy, cz, side_sgn, rng):
    """Build deep cavernous recessed dark eye socket ('basalt') + carved orbital bone frame + blazing turquoise core."""
    cant_deg = -15.0 * side_sgn  # angry downward inward brow cant
    rx_o, ry_o = 1.90, 1.64
    rx_i, ry_i = 1.30, 1.08
    segs = 12

    def ring_pts(rx, ry, z_off):
        pts = []
        rot = R('Z', cant_deg)
        for k in range(segs):
            ang = 2.0 * pi * k / segs
            ca, sa = cos(ang), sin(ang)
            # Bold stylized pirate eye contour: fierce angled flat-ish brow top, wide deep lower socket
            y_mod = sa * (0.82 if sa > 0.20 else 1.04)
            x_mod = ca * (1.05 if sa < 0.0 else 0.96)
            local = rot @ Vector((x_mod * rx, y_mod * ry, 0.0))
            pts.append(Vector((cx + local.x, cy + local.y, cz + z_off)))
        return pts

    # 1. Deep dark cavernous eye tunnel receding 2.6 m into skull (inward-facing dark basalt walls!)
    r_front = ring_pts(rx_i * 1.04, ry_i * 1.04, -0.22)
    r_mid = ring_pts(rx_i * 0.94, ry_i * 0.94, 1.05)
    r_back = ring_pts(rx_i * 0.72, ry_i * 0.72, 2.40)

    for r0, r1, col_t in ((r_front, r_mid, 0.40), (r_mid, r_back, 0.12)):
        c_wall = mix(C_SKULL_CAV, C_BASALT_DARK, col_t)
        for k in range(segs):
            k1 = (k + 1) % segs
            q = [r0[k], r0[k1], r1[k1], r1[k]]
            axis_mid = Vector((cx, cy, (r0[k].z + r1[k].z) * 0.5))
            q_mid = sum(q, Vector()) * 0.25
            outside_pt = q_mid + (q_mid - axis_mid).normalized() * 2.5
            mb.fp(q, 'basalt', jit(c_wall, rng, 0.04), (0, 0, 1), outside_pt, smooth=False)

    # Pitch-black cavernous back wall facing seaward (-Z)
    back_center = Vector((cx, cy, cz + 2.48))
    for k in range(segs):
        k1 = (k + 1) % segs
        mb.fp([back_center, r_back[k1], r_back[k]], 'basalt', C_SKULL_CAV, (1, 0, 0),
              Vector((cx, cy, cz + 4.8)), smooth=False)

    # 2. Clean sculpted beveled orbital bone rim collar framing the socket opening!
    r_outer = ring_pts(rx_o, ry_o, 0.45)
    r_crest = ring_pts(rx_i * 1.18, ry_i * 1.18, -0.36)
    r_lip = ring_pts(rx_i * 1.04, ry_i * 1.04, -0.22)
    for ra, rb in ((r_outer, r_crest), (r_crest, r_lip)):
        for k in range(segs):
            k1 = (k + 1) % segs
            q = [ra[k], ra[k1], rb[k1], rb[k]]
            q_mid = sum(q, Vector()) * 0.25
            rim_col = C_SKULL_BONE if q_mid.y > cy + 0.30 else (C_SKULL_MID if q_mid.y > cy - 0.65 else C_SKULL_SHADE)
            mb.fp(q, 'skull_stone', jit(rim_col, rng, 0.045), (1, 0, 0), Vector((cx, cy, cz + 2.8)), smooth=False)

    # 3. Blazing cursed turquoise-emerald crystal/flame ember core nestled cleanly inside socket!
    eye_ctr = Vector((cx, cy - 0.04, cz + 0.62))
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
    for v in bm.verts:
        p = v.co
        v.co = eye_ctr + Vector((p.x * 0.58, p.y * 0.66, p.z * 0.44))
    bm.faces.ensure_lookup_table()
    mb.newoff()
    for f in bm.faces:
        pts = [v.co.copy() for v in f.verts]
        mb.fp(pts, 'skull_glow', jit(C_SKULL_EYE, rng, 0.06), (0, 1, 0), eye_ctr, smooth=False)
    bm.free()

    # 5 jagged glowing cursed flame-crystal tongues licking inside the dark eye cavern
    shards = [
        (( 0.00,  0.22, -0.10), (0.30, 0.96, 0.26), ( 8,   0,  4 * side_sgn)),
        ((-0.36,  0.04, -0.04), (0.24, 0.76, 0.22), ( 4,  10,  22)),
        (( 0.36,  0.02, -0.04), (0.24, 0.74, 0.22), ( 4, -10, -24)),
        ((-0.18, -0.22,  0.06), (0.20, 0.58, 0.18), (-10,  8,  142)),
        (( 0.20, -0.20,  0.06), (0.20, 0.56, 0.18), (-10, -8, -145)),
    ]
    for off, (srx, sry, srz), rot_d in shards:
        p0 = eye_ctr + Vector(off)
        X = T(p0) @ R('Y', rot_d[1]) @ R('X', rot_d[0]) @ R('Z', rot_d[2])
        with xf(mb, X):
            prof = [(0.0, -sry * 0.35), (srx, 0.0), (srx * 0.70, sry * 0.45), (0.0, sry)]
            lathe(mb, prof, 5, 'skull_glow', jit(C_SKULL_EYE, rng, 0.07), smooth=False)


def _sculpt_skull_tooth(mb, pos, yaw_deg, w, h, d, col, rng, chipped=False):
    """Carved chunky slightly-tapered weathered stone skull tooth hanging downward from maxilla."""
    X = T(pos) @ R('Y', yaw_deg) @ R('X', rng.uniform(-4.0, 5.0)) @ R('Z', rng.uniform(-3.0, 3.0))
    # 4 vertical rings from broad root at y=0 down to slightly tapered chiselled biting edge at y=-h
    hw, hd = w * 0.5, d * 0.5
    def rect_ring(yl, sx, sz, slant=0.0):
        rx, rz = hw * sx, hd * sz
        ch = min(rx, rz) * 0.26
        return [
            (-rx + ch, yl - slant, -rz), ( rx - ch, yl + slant, -rz),
            ( rx, yl + slant, -rz + ch), ( rx, yl + slant,  rz - ch),
            ( rx - ch, yl + slant,  rz), (-rx + ch, yl - slant,  rz),
            (-rx, yl - slant,  rz - ch), (-rx, yl - slant, -rz + ch),
        ]
    tip_slant = (0.14 if chipped else rng.uniform(-0.04, 0.04))
    secs = [
        rect_ring(0.08, 1.06, 1.04, 0.0),
        rect_ring(-h * 0.38, 0.98, 0.96, 0.0),
        rect_ring(-h * 0.84, 0.86, 0.78, tip_slant),
        rect_ring(-h, 0.68, 0.46, tip_slant),
    ]
    scols = [
        jit(mix(col, C_SKULL_SHADE, 0.35), rng, 0.04),
        jit(col, rng, 0.04),
        jit(mix(col, C_SKULL_BONE, 0.45), rng, 0.04),
        jit(C_SKULL_BONE if not chipped else C_SKULL_SHADE, rng, 0.04),
    ]
    with xf(mb, X):
        loft(mb, secs, 'skull_stone', col, closed=True, caps=(True, True), mode='flat', scols=scols)


def _build_hanging_cargo_bundle(mb, center, rng):
    """Lashed wooden merchant cargo crate + coopered rum barrel suspended in hemp rope sling.
    Returns exact world position of top forged-iron hoist ring so the crane cable attaches seamlessly!
    """
    cx, cy, cz = center
    sway = T(cx, cy, cz) @ R('Y', 22) @ R('Z', -6.5) @ R('X', 4.0)
    with xf(mb, sway):
        # Forged-iron cargo hook & gathering ring at top (y = +0.94)
        with xf(mb, T(0.0, 0.94, 0.0) @ M_Y2Z):
            torus(mb, 0.075, 0.022, 10, 6, 'iron', C_IRON, False)
        hook_path = [
            (0.0, 0.88, 0.0), (0.0, 0.74, 0.0), (0.07, 0.64, 0.0),
            (0.04, 0.54, 0.0), (-0.06, 0.56, 0.0), (-0.09, 0.64, 0.0),
        ]
        tube(mb, hook_path, [0.024, 0.026, 0.028, 0.024, 0.020, 0.014], 6, 'iron', C_IRON, mode='flat')

        # 1. Chunky oak cargo crate resting on bottom of sling (y = -0.78..-0.06)
        c_cy = -0.42
        cbox(mb, (0.0, c_cy, 0.0), (0.78, 0.64, 0.76), 'timber', C_TIMBER_MID, 0.012)
        bw = 0.09
        for sy in (c_cy - 0.31, c_cy + 0.31):
            for sz in (-0.37, 0.37):
                cbox(mb, (0.0, sy, sz), (0.86, bw, bw), 'timber', jit(C_TIMBER_HI, rng, 0.07), 0.012, (1, 0, 0))
            for sx in (-0.37, 0.37):
                cbox(mb, (sx, sy, 0.0), (bw, bw, 0.68), 'timber', jit(C_TIMBER_HI, rng, 0.07), 0.012, (0, 0, 1))
        for sx in (-0.37, 0.37):
            for sz in (-0.37, 0.37):
                cbox(mb, (sx, c_cy, sz), (bw, 0.56, bw), 'timber', jit(C_TIMBER_DARK, rng, 0.06), 0.012, (0, 1, 0))
        # Diagonal side braces + merchant teal painted band + iron corner brackets
        for ang in (0, 90, 180, 270):
            with xf(mb, T(0.0, c_cy, 0.0) @ R('Y', ang)):
                cbox(mb, (0.0, 0.0, -0.39), (0.76, 0.085, 0.036), 'timber', C_TIMBER_HI, 0.008, M=R('Z', 36))
                cbox(mb, (0.0, 0.06, -0.395), (0.58, 0.14, 0.02), 'paint', C_PAINT_TEAL, 0.004)
        for sx in (-0.40, 0.40):
            for sy in (c_cy - 0.31, c_cy + 0.31):
                for sz in (-0.39, 0.39):
                    cbox(mb, (sx, sy, sz), (0.08, 0.08, 0.08), 'iron', C_IRON, 0.006)

        # 2. Coopered rum barrel lashed horizontally atop the crate
        with xf(mb, T(0.02, 0.21, 0.0) @ R('Y', -14) @ M_Y2X):
            prof = [
                (0.0, -0.40), (0.21, -0.40), (0.24, -0.42), (0.26, -0.34),
                (0.30, -0.12), (0.30, 0.12), (0.26, 0.34), (0.24, 0.42),
                (0.21, 0.40), (0.0, 0.40),
            ]
            stave_cols = [jit(C_TIMBER_MID, rng, 0.09, 0.02) for _ in range(10)]
            lathe(mb, prof, 10, 'timber', C_TIMBER_MID, False, False,
                  lambda i, k: C_TIMBER_DARK if i in (0, 8) else stave_cols[k])
            for hy, hr in ((-0.32, 0.272), (-0.13, 0.305), (0.13, 0.305), (0.32, 0.272)):
                cyl(mb, hr, hy - 0.024, hy + 0.024, 10, 'iron', C_IRON, False, 0.005)

        # 3. 4-strand braided hemp cargo sling cradling the crate & barrel up to the iron hook
        for sx in (-1.0, 1.0):
            for sz in (-1.0, 1.0):
                sling_pts = [
                    (sx * 0.04, 0.56, sz * 0.04),
                    (sx * 0.32, 0.32, sz * 0.26),
                    (sx * 0.46, -0.08, sz * 0.43),
                    (sx * 0.46, -0.78, sz * 0.43),
                    (sx * 0.14, -0.82, sz * 0.14),
                ]
                tube(mb, sling_pts, 0.026, 5, 'rope', jit(C_ROPE, rng, 0.06), mode='smooth')
        for lz_y in (-0.42, 0.20):
            belt = [
                (-0.47, lz_y, -0.43), (0.47, lz_y, -0.43),
                (0.47, lz_y, 0.43), (-0.47, lz_y, 0.43), (-0.47, lz_y, -0.43),
            ]
            tube(mb, belt, 0.024, 5, 'rope', C_ROPE, caps=(False, False), mode='smooth')

    return sway @ Vector((0.0, 0.99, 0.0))


def _build_double_sided_pennant(mb, root_pos, length=0.92, h0=0.34, out_dir=(0.0, 0.0, -1.0),
                                col_main=C_PAINT_RED, col_trim=C_PAINT_CREAM):
    """Fluttering 3D double-sided swallowtail cloth pennant visible from both sides (backface-cull safe!)."""
    rp = Vector(root_pos)
    od = Vector(out_dir).normalized()
    side = Vector((-od.z, 0.0, od.x)).normalized()
    segs = 6
    thick = 0.010

    top_pts = []
    bot_pts = []
    for i in range(segs + 1):
        t = i / float(segs)
        wave = sin(t * 2.15 * pi) * 0.11 * t + 0.03 * sin(t * 4.2)
        droop = -0.14 * t * t
        hh = h0 * (1.0 - 0.58 * t)
        ctr = rp + od * (length * t) + side * wave + Vector((0.0, droop, 0.0))
        top_pts.append(ctr + Vector((0.0, hh * 0.5, 0.0)))
        bot_pts.append(ctr - Vector((0.0, hh * 0.5, 0.0)))

    for i in range(segs):
        c_seg = col_trim if i == 0 else mul(col_main, 0.90 + 0.10 * ((i + 1) % 2))
        t0, t1 = top_pts[i], top_pts[i + 1]
        b0, b1 = bot_pts[i], bot_pts[i + 1]
        if i == segs - 1:
            mid_notch = (t0 + b0) * 0.25 + (t1 + b1) * 0.25 - od * (length * 0.09)
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
                mb.fp(b_pts, 'paint', mul(c_seg, 0.88), od, ctr_tri + side * 1.0, smooth=False)
        else:
            q_f = [t0 + side * thick, t1 + side * thick, b1 + side * thick, b0 + side * thick]
            q_b = [t1 - side * thick, t0 - side * thick, b0 - side * thick, b1 - side * thick]
            ctr_q = (t0 + t1 + b0 + b1) * 0.25
            mb.fp(q_f, 'paint', c_seg, od, ctr_q - side * 1.0, smooth=False)
            mb.fp(q_b, 'paint', mul(c_seg, 0.88), od, ctr_q + side * 1.0, smooth=False)
            mb.fp([t0 - side * thick, t1 - side * thick, t1 + side * thick, t0 + side * thick],
                  'paint', mul(c_seg, 0.82), od, ctr_q, smooth=False)
            mb.fp([b0 + side * thick, b1 + side * thick, b1 - side * thick, b0 - side * thick],
                  'paint', mul(c_seg, 0.78), od, ctr_q, smooth=False)


# ================================================================ 1. SKULL CLIFF CARVING
def gen_skull_cliff_carving(outdir):
    clear_scene()
    rng = random.Random(SEED + 601)
    mb = MB('SkullCliffCarving', seed=601)

    # 1. Deep coastal cliff massif rock backing (z = +0.5..+6.5 m, y = -2.5..+15.6 m, width ~14.4 m)
    #    Embeds seamlessly into Skull Bluff's cliff face while letting the carved bone skull stand proud seaward!
    backing_masses = [
        # Core rear massif behind cranium & jaw (extends solidly to z = +6.5 m)
        (( 0.0,  7.2,  3.5), (5.6, 7.6, 2.9), 'limestone',      C_LIME_PALE, C_LIME_MID,  C_LIME_DARK,  0.20, 0.18, 0.24),
        # Upper craggy cliff shoulders arching behind skull top
        ((-2.5, 12.1,  3.2), (3.4, 3.4, 3.0), 'limestone_moss', C_LIME_WARM, C_LIME_MID,  C_LIME_SHADE, 0.22, 0.14, 0.62),
        (( 2.6, 11.7,  3.4), (3.2, 3.6, 2.8), 'limestone',      C_LIME_PALE, C_LIME_WARM, C_LIME_SHADE, 0.20, 0.16, 0.25),
        # Flanking coastal cliff shoulders hugging the temples (total width ~14.2 m)
        ((-4.9,  6.4,  2.3), (2.0, 6.2, 3.2), 'limestone_moss', C_LIME_WARM, C_LIME_MID,  C_LIME_DARK,  0.22, 0.18, 0.56),
        (( 4.9,  6.2,  2.4), (2.0, 6.0, 3.1), 'limestone',      C_LIME_PALE, C_LIME_MID,  C_LIME_DARK,  0.22, 0.18, 0.28),
        # Mossy rock collar hugging chin & lower sides plunging cleanly to y = -2.5 m!
        ((-3.4,  0.3,  0.6), (2.6, 2.7, 3.1), 'limestone_moss', C_LIME_WARM, C_LIME_MID,  C_LIME_DARK,  0.20, 0.16, 0.72),
        (( 3.4,  0.2,  0.7), (2.6, 2.6, 3.0), 'limestone_moss', C_LIME_WARM, C_LIME_MID,  C_LIME_DARK,  0.20, 0.16, 0.66),
        (( 0.0, -0.7,  1.4), (4.2, 2.1, 3.9), 'limestone_moss', C_LIME_MID,  C_LIME_SHADE, C_LIME_DARK, 0.18, 0.16, 0.55),
    ]
    for ctr, rad, mat, ct, cm, cb, wp, st, mc in backing_masses:
        sculpt_rock_mass(
            mb, ctr, rad, mat, ct, cm, cb, rng,
            subdiv=2, warp=wp, strata=st, base_flare=0.14,
            crag_ribs=5, rib_amp=0.11, moss_cap=mc,
        )

    # 2. Towering Cracked Pirate Cranium Dome (y = 8.2..15.5 m, facing -Z)
    _sculpt_skull_cranium(mb, rng)
    # Crisp carved forehead battle-crack fissure slashing up-right across the right brow/temple
    crack_path = [
        (0.85,  9.75, -4.48),
        (1.38, 10.65, -4.36),
        (1.98, 11.45, -4.16),
        (2.48, 12.42, -3.76),
        (3.15, 13.38, -3.12),
    ]
    tube(mb, crack_path, [0.06, 0.11, 0.12, 0.09, 0.05], 5, 'basalt', C_SKULL_CAV, mode='flat')

    # Solid inner skull core behind eye sockets & nasal bridge so zero seams ever show through!
    sculpt_rock_mass(
        mb, (0.0, 6.9, -0.45), (3.85, 3.35, 2.15), 'skull_stone',
        C_SKULL_MID, C_SKULL_SHADE, C_SKULL_SHADE, rng, subdiv=2, warp=0.10, strata=0.05,
    )

    # 3. Continuous Sweeping Overhanging Furrowed Brow Arch (unmistakable angry pirate V-brow!)
    brow_stations = [
        ((-5.05, 8.25, -2.05), 0.78, 0.78, -14, 0.15),
        ((-4.35, 9.05, -3.55), 0.92, 0.86, -10, 0.55),
        ((-3.05, 9.55, -4.55), 1.06, 0.88,  -6, 0.92),
        ((-1.55, 9.12, -4.92), 1.08, 0.82,  -2, 1.00),
        (( 0.00, 8.62, -5.05), 1.02, 0.86,   0, 0.98),  # fierce scowling glabella dip!
        (( 1.55, 9.12, -4.92), 1.08, 0.82,   2, 1.00),
        (( 3.05, 9.55, -4.55), 1.06, 0.88,   6, 0.92),
        (( 4.35, 9.05, -3.55), 0.92, 0.86,  10, 0.55),
        (( 5.05, 8.25, -2.05), 0.78, 0.78,  14, 0.15),
    ]
    _sculpt_ribbon_arch(
        mb, brow_stations, 'skull_stone',
        lambda t: mix(C_SKULL_SHADE, C_SKULL_BONE, 0.25 + 0.75 * t), rng,
    )

    # 4. Deep Recessed Cavernous Eye Sockets + Blazing Cursed Turquoise-Emerald Eye Embers!
    eye_l = (-2.32, 7.05, -4.35)
    eye_r = ( 2.32, 7.05, -4.35)
    _sculpt_skull_eye_cavity(mb, eye_l[0], eye_l[1], eye_l[2], -1.0, rng)
    _sculpt_skull_eye_cavity(mb, eye_r[0], eye_r[1], eye_r[2],  1.0, rng)

    # 5. Bold High Sweeping Sculpted Cheekbones (Zygomatic Arches) + Outer Orbital Pillars!
    for sgn in (-1.0, 1.0):
        # Sweeping outer orbital pillar from brow arch down into bold flaring cheekbone wing
        cheek_stations = [
            ((sgn * 4.65, 8.65, -3.15), 0.74, 0.72, 0, 0.65),
            ((sgn * 4.78, 7.05, -3.45), 0.78, 0.74, 0, 0.75),
            ((sgn * 4.65, 5.55, -3.85), 0.95, 0.82, 0, 0.95),  # bold wide malar peak!
            ((sgn * 3.15, 5.15, -4.45), 0.88, 0.76, 0, 1.00),  # crisp under-eye cheekbone shelf!
            ((sgn * 1.45, 5.10, -4.52), 0.68, 0.66, 0, 0.92),  # merges smoothly into nasal flank!
        ]
        _sculpt_ribbon_arch(
            mb, cheek_stations, 'skull_stone',
            lambda t: mix(C_SKULL_SHADE, C_SKULL_BONE, 0.35 + 0.65 * t), rng,
        )
        # Rear zygomatic temple bridge curving from cheekbone peak back into the cliff
        zyg_back = [
            ((sgn * 4.65, 5.55, -3.75), 0.84, 0.78, 0, 0.85),
            ((sgn * 5.28, 5.80, -2.25), 0.76, 0.76, 0, 0.55),
            ((sgn * 5.20, 6.05, -0.45), 0.72, 0.78, 0, 0.25),
        ]
        _sculpt_ribbon_arch(
            mb, zyg_back, 'skull_stone',
            lambda t: mix(C_SKULL_SHADE, C_SKULL_MID, t), rng,
        )
        # Tucked dark sub-zygomatic shadow recess strictly behind the cheekbone/jaw junction
        cbox(mb, (sgn * 3.05, 3.65, -1.55), (1.45, 1.95, 1.75), 'basalt', C_SKULL_CAV, 0.08)

    # 6. Jagged Upturned Inverted-Heart Nasal Cavity + Crisp Sculpted Nasal Bridge & Septum!
    nas_back = Vector((0.0, 5.40, -2.10))
    nas_rim = [
        Vector(( 0.00, 6.95, -4.58)),  # crisp top apex
        Vector((-0.58, 6.05, -4.64)),
        Vector((-1.10, 4.78, -4.60)),  # flaring left nostril wing
        Vector((-0.42, 4.48, -4.62)),
        Vector(( 0.00, 4.82, -4.60)),  # central upturned nasal spine
        Vector(( 0.42, 4.48, -4.62)),
        Vector(( 1.10, 4.78, -4.60)),  # flaring right nostril wing
        Vector(( 0.58, 6.05, -4.64)),
    ]
    nas_deep = [Vector((p.x * 0.62, p.y - 0.08, -2.15)) for p in nas_rim]
    for k in range(len(nas_rim)):
        k1 = (k + 1) % len(nas_rim)
        q = [nas_rim[k], nas_rim[k1], nas_deep[k1], nas_deep[k]]
        q_mid = sum(q, Vector()) * 0.25
        out_ref = q_mid + (q_mid - Vector((0.0, 5.45, q_mid.z))).normalized() * 2.5
        mb.fp(q, 'basalt', C_SKULL_CAV, (0, 1, 0), out_ref, smooth=False)
    for k in range(len(nas_deep)):
        k1 = (k + 1) % len(nas_deep)
        mb.fp([nas_back, nas_deep[k1], nas_deep[k]], 'basalt', C_SKULL_CAV, (1, 0, 0),
              Vector((0.0, 5.40, 0.5)), smooth=False)

    # Sculpted bone nasal bridge & flaring outer nasal rims
    _sculpt_ribbon_arch(
        mb,
        [
            ((0.0, 8.45, -4.82), 0.62, 0.56, 0, 0.95),
            ((0.0, 7.62, -4.78), 0.58, 0.52, 0, 1.00),
            ((0.0, 6.88, -4.66), 0.50, 0.44, 0, 0.92),
        ],
        'skull_stone', lambda t: mix(C_SKULL_MID, C_SKULL_BONE, t), rng,
    )
    for sgn in (-1.0, 1.0):
        _sculpt_ribbon_arch(
            mb,
            [
                ((sgn * 0.48, 6.92, -4.56), 0.42, 0.36, 0, 0.90),
                ((sgn * 1.08, 5.82, -4.55), 0.48, 0.42, 0, 0.96),
                ((sgn * 1.32, 4.78, -4.52), 0.52, 0.46, 0, 0.92),
            ],
            'skull_stone', lambda t: mix(C_SKULL_MID, C_SKULL_BONE, t), rng,
        )
    # Thin jagged carved bone nasal septum blade inside cavity
    cbox(mb, (0.0, 5.55, -3.95), (0.20, 2.05, 1.30), 'skull_stone', C_SKULL_MID, 0.03)

    # 7. Continuous Curved Sculpted Maxilla (Upper Jaw Arch) + 7 Bold Chiseled Pirate Teeth!
    maxilla_stations = []
    for k in range(9):
        u = (k - 4.0) / 4.0  # -1..+1
        ang = u * 0.96
        mx = sin(ang) * 3.35
        mz = -4.68 + (1.0 - cos(ang)) * 2.15
        rw = 0.88 - 0.16 * abs(u)
        rh = 0.78 - 0.12 * abs(u)
        maxilla_stations.append(((mx, 3.88, mz + 0.55), rw, rh, 0, 1.0 - 0.55 * abs(u)))
    _sculpt_ribbon_arch(
        mb, maxilla_stations, 'skull_stone',
        lambda t: mix(C_SKULL_SHADE, C_SKULL_BONE, 0.30 + 0.70 * t), rng,
    )

    # Pitch-black deep recessed mouth/gullet cavern behind teeth for maximum contrast!
    cbox(mb, (0.0, 2.05, -2.55), (5.8, 2.75, 2.85), 'basalt', C_SKULL_CAV, 0.08)

    # 7 bold carved tapered stone teeth along upper jaw arc (including iconic chipped broken tooth gap!)
    tooth_specs = [
        (-2.52, -3.72, -34.0, 0.66, 1.25, 0.64, C_SKULL_MID,   False),
        (-1.74, -4.28, -22.0, 0.72, 1.48, 0.66, C_SKULL_BONE,  False),
        (-0.92, -4.60, -11.0, 0.70, 1.54, 0.68, C_SKULL_BONE,  False),
        (-0.04, -4.74,   1.0, 0.72, 1.50, 0.68, C_SKULL_BONE,  False),
        ( 0.84, -4.58,  11.0, 0.58, 0.66, 0.58, C_SKULL_SHADE, True),   # cracked broken pirate tooth stub!
        ( 1.74, -4.26,  22.0, 0.74, 1.50, 0.66, C_SKULL_BONE,  False),
        ( 2.52, -3.68,  35.0, 0.66, 1.24, 0.62, C_SKULL_MID,   False),
    ]
    for tx, tz, tyaw, tw, th, td, tcol, chipped in tooth_specs:
        _sculpt_skull_tooth(mb, (tx, 3.28, tz), tyaw, tw, th, td, tcol, rng, chipped=chipped)

    # Sculpted curved stone lower mandible / chin rim emerging from mossy coastal cliff rock!
    jaw_stations = [
        ((-3.45, 2.25, -2.15), 0.78, 0.72, 0, 0.25),
        ((-2.65, 1.15, -3.25), 0.86, 0.76, 0, 0.55),
        ((-1.35, 0.55, -3.95), 0.92, 0.78, 0, 0.82),
        (( 0.00, 0.35, -4.18), 0.98, 0.82, 0, 0.90),
        (( 1.35, 0.55, -3.95), 0.92, 0.78, 0, 0.82),
        (( 2.65, 1.15, -3.25), 0.86, 0.76, 0, 0.55),
        (( 3.45, 2.25, -2.15), 0.78, 0.72, 0, 0.25),
    ]
    _sculpt_ribbon_arch(
        mb, jaw_stations, 'skull_stone',
        lambda t: mix(C_SKULL_SHADE, C_SKULL_MID, 0.25 + 0.75 * t), rng,
    )
    # 3 weathered lower teeth rising out of the stone chin rim!
    for ltx, ltz, lth in ((-1.32, -3.96, 0.72), (-0.08, -4.18, 0.80), (1.22, -3.98, 0.68)):
        with xf(mb, T(ltx, 1.02, ltz) @ R('X', 180)):
            _sculpt_skull_tooth(mb, (0.0, 0.0, 0.0), rng.uniform(-10, 10), 0.60, lth, 0.54, C_SKULL_MID, rng)

    # 8. Mossy Brow Cap & Hanging Jungle Vines Draped Over the Port Brow & Outer Temple!
    #    Positioned to frame the glowing port eye dramatically WITHOUT obstructing it!
    sculpt_rock_mass(
        mb, (-3.65, 10.65, -2.45), (2.05, 0.88, 1.75), 'limestone_moss',
        C_LEDGE_MOSS, C_SEA_MOSS, C_LIME_SHADE, rng,
        subdiv=2, warp=0.22, strata=0.08, flat_top=0.45, moss_cap=0.88,
    )
    vine_specs = [
        ((-4.25,  9.45, -3.85), 4.15, 0.36, (-0.42, 0.0, -0.91)),
        ((-3.55,  9.85, -4.45), 2.55, 0.30, (-0.22, 0.0, -0.97)),
        ((-1.25,  9.35, -5.05), 1.65, 0.24, ( 0.05, 0.0, -0.99)),
        ((-4.95,  8.65, -2.95), 4.40, 0.38, (-0.60, 0.0, -0.80)),
        (( 4.75,  8.85, -3.05), 3.15, 0.30, ( 0.52, 0.0, -0.85)),
        (( 5.25,  6.15, -1.95), 2.85, 0.28, ( 0.65, 0.0, -0.76)),
        ((-3.95,  1.55, -2.85), 2.35, 0.30, (-0.38, 0.0, -0.92)),
    ]
    for anc, vlen, vw, vdir in vine_specs:
        add_vine_drape(mb, anc, vlen, vw, vdir, rng, phase=rng.random())

    build(mb)

    # Empties centered in both glowing eye sockets!
    add_empty('Lantern_SkullEyeL', (-2.32, 7.05, -3.85))
    add_empty('Lantern_SkullEyeR', ( 2.32, 7.05, -3.85))

    # Structural colliders matching lower massif/jaw and upper brow/cranium
    col_box('col_skull_base', (-6.60, -2.50, -4.80), (6.60,  8.20, 6.45))
    col_box('col_skull_brow', (-6.30,  7.80, -5.25), (6.30, 15.60, 6.45))
    export_landmark_glb(outdir, 'skull_cliff_carving.glb')


# ================================================================ 2. ANCIENT TEMPLE STAIRWAY
def gen_ancient_temple_stairway(outdir):
    clear_scene()
    rng = random.Random(SEED + 631)
    mb = MB('AncientTempleStairway', seed=631)

    N_STEPS = 12
    Z_START = -5.50
    TREAD_D = 0.65
    RISE_H = 0.40
    LAND_Z0 = Z_START + N_STEPS * TREAD_D   # +2.30 m
    LAND_Z1 = 5.80
    LAND_Y = N_STEPS * RISE_H               # +4.80 m
    STAIR_W = 5.40
    FOUND_Y = -2.20

    # 1. Deep stepped weathered masonry foundation skirt plunging solidly to y = -2.20 m
    #    Strictly stepped below each stair tread so every hand-hewn stone step reads cleanly!
    for si in range(N_STEPS):
        z0 = Z_START + si * TREAD_D
        z1 = z0 + TREAD_D + 0.08
        y_under = si * RISE_H + 0.06
        _box2(mb, (-3.68, FOUND_Y, z0), (3.68, y_under, z1),
              'temple_stone', mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.34), 0.06)
    _box2(mb, (-3.76, FOUND_Y, LAND_Z0 - 0.15), (3.76, LAND_Y - 0.34, LAND_Z1),
          'temple_stone', mix(C_TEMPLE_DARK, C_SEA_MOSS, 0.28), 0.08)

    # Entry threshold apron flagstones at foot of stairs
    for k in range(3):
        ax = -1.75 + k * 1.75
        sculpt_stone_block(mb, (ax, -0.14, Z_START - 0.22), (1.72, 0.34, 0.62), 'temple_stone',
                           C_TEMPLE_MID, rng, chip=0.06, moss_col=C_LEDGE_MOSS)

    # 2. 12 chunky hand-hewn weathered stone steps
    for si in range(N_STEPS):
        y_top = (si + 1) * RISE_H
        y_bot = y_top - 0.46
        zc = Z_START + (si + 0.5) * TREAD_D
        n_blk = 3 if si % 2 == 0 else 4
        bw = STAIR_W / float(n_blk)
        for bi in range(n_blk):
            bx = -STAIR_W * 0.5 + (bi + 0.5) * bw
            wear = -0.025 * (1.0 - abs(bx) / 2.8)
            h_col = mix(C_TEMPLE_MID, C_TEMPLE_HI, 0.25 + 0.55 * (si / float(N_STEPS)))
            edge_moss = C_LEDGE_MOSS if (bi == 0 or bi == n_blk - 1 or si < 3) else None
            sculpt_stone_block(
                mb,
                (bx + rng.uniform(-0.02, 0.02), 0.5 * (y_bot + y_top) + wear, zc),
                (bw + 0.04, (y_top - y_bot), TREAD_D + 0.10),
                'temple_stone', h_col, rng, chip=0.055,
                M=R('Y', rng.uniform(-1.2, 1.2)),
                moss_col=edge_moss,
            )

    # 3. Elevated Sanctuary Landing Flagstones + Recessed Golden Sun-Compass Medallion
    for zi in range(3):
        fz = LAND_Z0 + 0.58 + zi * 1.15
        for xi in range(4):
            fx = -2.40 + xi * 1.60
            fcol = mix(C_TEMPLE_MID, C_TEMPLE_HI, 0.55 + 0.20 * ((xi + zi) % 2))
            sculpt_stone_block(
                mb, (fx, LAND_Y - 0.20, fz), (1.58, 0.40, 1.14), 'temple_stone',
                fcol, rng, chip=0.05, moss_col=(C_LEDGE_MOSS if (xi in (0, 3) or zi == 2) else None),
            )
    med_z = LAND_Z0 + 1.85
    with xf(mb, T(0.0, LAND_Y + 0.015, med_z)):
        cyl(mb, 1.18, -0.03, 0.02, 8, 'temple_stone', C_TEMPLE_DARK, False, 0.01)
        cyl(mb, 1.02, 0.00, 0.035, 8, 'brass', C_TEMPLE_GOLD, False, 0.008)
        cyl(mb, 0.78, 0.01, 0.042, 8, 'temple_stone', C_TEMPLE_MID, False, 0.008)
        cyl(mb, 0.34, 0.015, 0.052, 8, 'brass', C_TEMPLE_GOLD, False, 0.008)
        for k in range(4):
            cbox(mb, (0.0, 0.042, 0.0), (1.92 if k % 2 == 0 else 1.48, 0.03, 0.11),
                 'brass', C_TEMPLE_GOLD, 0.006, M=R('Y', k * 45.0))

    for k in range(3):
        sculpt_stone_block(mb, (-1.6 + k * 1.6, LAND_Y + 0.24, LAND_Z1 - 0.22), (1.58, 0.50, 0.46),
                           'temple_stone', C_TEMPLE_HI, rng, chip=0.05, moss_col=C_LEDGE_MOSS)

    # 4. Twin Stepped Mossy Parapet Cheek Walls
    wall_l_pts = []
    wall_r_pts = []
    tiers = [
        (Z_START - 0.10, Z_START + 2.05, 1.48),
        (Z_START + 1.90, Z_START + 4.10, 2.75),
        (Z_START + 3.95, Z_START + 6.15, 4.02),
        (Z_START + 6.00, LAND_Z0 + 0.55, 5.45),
        (LAND_Z0 + 0.40, LAND_Z1 + 0.05, 5.75),
    ]
    for sgn in (-1.0, 1.0):
        wx = sgn * 3.22
        pts_acc = wall_l_pts if sgn < 0 else wall_r_pts
        for ti, (z0, z1, y_hi) in enumerate(tiers):
            zc = 0.5 * (z0 + z1)
            dl = z1 - z0
            h_body = (y_hi - 0.30) - (FOUND_Y + 0.30)
            y_mid = (FOUND_Y + 0.30) + h_body * 0.5
            sculpt_stone_block(
                mb, (wx, y_mid, zc), (1.08, h_body, dl), 'temple_stone',
                mix(C_TEMPLE_DARK, C_TEMPLE_MID, 0.35 + 0.14 * ti), rng, chip=0.07,
            )
            sculpt_stone_block(
                mb, (wx, y_hi - 0.14, zc), (1.24, 0.30, dl + 0.12), 'temple_stone',
                C_TEMPLE_HI, rng, chip=0.055, moss_col=C_LEDGE_MOSS,
            )
            if ti in (1, 2, 3):
                cbox(mb, (wx + sgn * 0.56, y_hi - 0.62, zc), (0.08, 0.24, dl * 0.68),
                     'brass', C_TEMPLE_GOLD, 0.012)
            for px in (wx - 0.60, wx + 0.60):
                for py in (FOUND_Y, y_hi):
                    for pz in (z0, z1):
                        pts_acc.append((px, py, pz))

        # Carved entrance newel pedestal bollard at foot of each cheek wall
        sculpt_stone_block(mb, (wx, 0.85, Z_START - 0.15), (1.36, 1.85, 1.36), 'temple_stone',
                           C_TEMPLE_HI, rng, chip=0.07, moss_col=C_LEDGE_MOSS)
        with xf(mb, T(wx, 1.78, Z_START - 0.15)):
            cyl(mb, 0.52, 0.0, 0.22, 8, 'temple_stone', C_TEMPLE_HI, False, 0.02, 0.44)
            cyl(mb, 0.36, 0.20, 0.32, 8, 'brass', C_TEMPLE_GOLD, False, 0.01, 0.30)

    # 5. Twin Tall (~6.5 m above landing -> y = 4.8..11.35 m) Carved Tapering Stone Obelisk Totems!
    for sgn in (-1.0, 1.0):
        ox = sgn * 3.22
        oz = LAND_Z0 + 2.25
        lean = R('Z', -0.8 if sgn > 0 else 0.7) @ R('X', 0.6 if sgn < 0 else -0.5)
        with xf(mb, T(ox, LAND_Y, oz) @ lean):
            # Plinths plunge solidly down into the stepped cheek-wall parapet (y = -0.25..+1.06) so zero gap shows!
            sculpt_stone_block(mb, (0.0, 0.25, 0.0), (1.78, 1.00, 1.78), 'temple_stone',
                               C_TEMPLE_MID, rng, chip=0.05, moss_col=C_LEDGE_MOSS)
            sculpt_stone_block(mb, (0.0, 0.84, 0.0), (1.50, 0.44, 1.50), 'temple_stone',
                               C_TEMPLE_HI, rng, chip=0.04, moss_col=C_LEDGE_MOSS)

            def oct_sec(y_l, hw, ch_f=0.22):
                c = hw * (1.0 - ch_f)
                return [
                    (-c, y_l, -hw), ( c, y_l, -hw),
                    ( hw, y_l, -c), ( hw, y_l,  c),
                    ( c, y_l,  hw), (-c, y_l,  hw),
                    (-hw, y_l,  c), (-hw, y_l, -c),
                ]

            shaft_levels = [
                (0.76, 0.65, C_TEMPLE_MID),
                (2.25, 0.59, C_TEMPLE_HI),
                (2.42, 0.53, C_TEMPLE_DARK),
                (2.58, 0.57, C_TEMPLE_HI),
                (3.95, 0.51, C_TEMPLE_HI),
                (4.12, 0.45, C_TEMPLE_DARK),
                (4.28, 0.49, C_TEMPLE_HI),
                (5.58, 0.43, C_TEMPLE_HI),
                (5.72, 0.48, C_TEMPLE_MID),
                (6.55, 0.04, C_TEMPLE_HI),
            ]
            secs = [oct_sec(yl, hw) for yl, hw, _ in shaft_levels]
            scols = [jit(cc, rng, 0.04) for _, _, cc in shaft_levels]
            loft(mb, secs, 'temple_stone', C_TEMPLE_HI, closed=True, caps=(True, True), mode='flat', scols=scols)

            for gy, gr in ((2.42, 0.565), (4.12, 0.485)):
                cbox(mb, (0.0, gy, 0.0), (gr * 2.0, 0.11, gr * 2.0), 'brass', C_TEMPLE_GOLD, 0.015)

            # Recessed golden inlaid nautical sun & wave reliefs on seaward (-Z) & inward (∓X) faces!
            for ryaw in (0.0, sgn * 90.0):
                with xf(mb, R('Y', ryaw)):
                    cbox(mb, (0.0, 4.88, -0.46), (0.50, 0.68, 0.06), 'temple_stone', C_TEMPLE_DARK, 0.01)
                    with xf(mb, T(0.0, 4.92, -0.495) @ R('X', -90)):
                        cyl(mb, 0.16, 0.0, 0.045, 8, 'brass', C_TEMPLE_GOLD, False, 0.008, 0.13)
                    for k in range(4):
                        cbox(mb, (0.0, 4.92, -0.50), (0.42 if k % 2 == 0 else 0.34, 0.042, 0.032),
                             'brass', C_TEMPLE_GOLD, 0.006, M=R('Z', k * 45.0))
                    cbox(mb, (0.0, 3.26, -0.54), (0.56, 0.96, 0.06), 'temple_stone', C_TEMPLE_DARK, 0.01)
                    for wy in (2.94, 3.26, 3.58):
                        cbox(mb, (-0.11, wy, -0.575), (0.24, 0.065, 0.035), 'brass', C_TEMPLE_GOLD, 0.006, M=R('Z', 24))
                        cbox(mb, ( 0.11, wy, -0.575), (0.24, 0.065, 0.035), 'brass', C_TEMPLE_GOLD, 0.006, M=R('Z', -24))
                    cbox(mb, (0.0, 1.62, -0.61), (0.52, 0.88, 0.06), 'temple_stone', C_TEMPLE_DARK, 0.01)
                    cbox(mb, (0.0, 1.62, -0.645), (0.08, 0.72, 0.035), 'brass', C_TEMPLE_GOLD, 0.006)
                    cbox(mb, (0.0, 1.80, -0.645), (0.34, 0.075, 0.035), 'brass', C_TEMPLE_GOLD, 0.006)
                    cbox(mb, (0.0, 1.46, -0.645), (0.24, 0.065, 0.035), 'brass', C_TEMPLE_GOLD, 0.006)

            with xf(mb, T(0.0, 6.22, 0.0)):
                cyl(mb, 0.18, 0.0, 0.36, 4, 'brass', C_TEMPLE_GOLD, False, 0.0, 0.02)

    # 6. Broken Toppled Temple Pillar Drum on Port Side + Grounded Mossy Limestone Boulders!
    with xf(mb, T(-4.45, 0.25, -2.15) @ R('Y', 28) @ R('Z', 82) @ R('X', 12)):
        def fluted_drum(yl, r0, r1, slope=0.0):
            pts = []
            for k in range(12):
                a = 2.0 * pi * k / 12.0
                rr = r0 if k % 2 == 0 else r1
                px, pz = cos(a) * rr, sin(a) * rr
                pts.append((px, yl + slope * px, pz))
            return pts
        loft(mb, [
            fluted_drum(-0.88, 0.56, 0.48, 0.15),
            fluted_drum( 0.00, 0.55, 0.47, 0.0),
            fluted_drum( 0.82, 0.54, 0.46, -0.42),
        ], 'temple_stone', C_TEMPLE_HI, closed=True, caps=(True, True), mode='flat',
            scols=[mix(C_TEMPLE_MID, C_LEDGE_MOSS, 0.35), C_TEMPLE_HI, C_TEMPLE_MID])
    sculpt_stone_block(mb, (-4.68, 0.10, -3.55), (1.12, 0.62, 1.05), 'temple_stone',
                       C_TEMPLE_MID, rng, chip=0.08, M=R('Y', 38) @ R('Z', -16), moss_col=C_LEDGE_MOSS)

    # Grounded mossy limestone boulders wedged solidly along the base & hillside skirt (plunging deep so zero float!)
    boulder_specs = [
        ((-4.15, -0.35, -4.65), (1.15, 1.15, 1.08), 0.72),
        (( 4.10, -0.30, -4.45), (1.12, 1.20, 1.00), 0.68),
        (( 4.25,  0.15, -1.25), (1.28, 1.85, 1.45), 0.75),
        ((-4.25,  0.45,  0.85), (1.32, 2.25, 1.45), 0.78),
        (( 4.25,  0.85,  2.85), (1.38, 2.75, 1.65), 0.70),
        ((-4.15,  1.15,  4.65), (1.30, 3.00, 1.45), 0.74),
    ]
    for bc, br, mc in boulder_specs:
        sculpt_rock_mass(
            mb, bc, br, 'limestone_moss', C_LEDGE_MOSS, C_LIME_MID, C_LIME_DARK, rng,
            subdiv=2, warp=0.22, strata=0.14, base_flare=0.24, moss_cap=mc,
        )

    # 7. Graceful Hanging Jungle Vines Draping Off Obelisk Collars & Stepped Cheek Walls!
    vines = [
        ((-3.22,  8.95,  3.96), 2.55, 0.20, ( 0.0, 0.0, -1.0)),
        ((-3.78,  7.25,  4.55), 2.15, 0.18, (-1.0, 0.0,  0.0)),
        (( 3.22,  9.20,  3.96), 2.25, 0.18, ( 0.0, 0.0, -1.0)),
        (( 3.76,  7.25,  4.45), 2.05, 0.18, ( 1.0, 0.0,  0.0)),
        ((-3.82,  5.40,  1.25), 2.25, 0.24, (-1.0, 0.0,  0.0)),
        (( 3.82,  5.40,  1.45), 2.10, 0.24, ( 1.0, 0.0,  0.0)),
        ((-3.82,  4.00, -0.45), 1.90, 0.22, (-1.0, 0.0,  0.0)),
        (( 3.82,  2.72, -2.55), 1.65, 0.22, ( 1.0, 0.0,  0.0)),
        ((-2.62,  5.35,  1.85), 1.35, 0.18, ( 1.0, 0.0,  0.0)),
        (( 2.62,  3.95, -0.35), 1.25, 0.18, (-1.0, 0.0,  0.0)),
    ]
    for anc, vlen, vw, vdir in vines:
        add_vine_drape(mb, anc, vlen, vw, vdir, rng, phase=rng.random())

    build(mb)

    # 8. Walkable & Structural Colliders (exact required names!)
    ramp_pts = []
    for x in (-2.68, 2.68):
        ramp_pts.extend([
            (x,  0.00, Z_START - 0.15),
            (x, FOUND_Y, Z_START - 0.15),
            (x, LAND_Y, LAND_Z0 + 0.05),
            (x, FOUND_Y, LAND_Z0 + 0.05),
        ])
    col_piece('col_stairs_ramp', ramp_pts)
    col_box('col_stairs_landing', (-3.76, FOUND_Y, LAND_Z0), (3.76, LAND_Y, LAND_Z1))
    col_piece('col_stairs_wall_l', wall_l_pts)
    col_piece('col_stairs_wall_r', wall_r_pts)
    col_box('col_obelisk_l', (-4.10, LAND_Y, LAND_Z0 + 1.35), (-2.34, LAND_Y + 6.60, LAND_Z0 + 3.15))
    col_box('col_obelisk_r', ( 2.34, LAND_Y, LAND_Z0 + 1.35), ( 4.10, LAND_Y + 6.60, LAND_Z0 + 3.15))
    export_landmark_glb(outdir, 'ancient_temple_stairway.glb')


# ================================================================ 3. CLIFF CATWALK PIER
def gen_cliff_catwalk_pier(outdir):
    clear_scene()
    rng = random.Random(SEED + 661)
    mb = MB('CliffCatwalkPier', seed=661)

    DECK_Y = 3.22
    Z_SEA = -6.50
    Z_CLIFF = 4.25
    brace_pts = []

    # 1. Heavy Cliffside Anchor Pilings, Sill Beams & Massive Diagonal Timber Knee-Braces!
    cbox(mb, (0.0, 2.86, 4.15), (3.30, 0.34, 0.42), 'timber', C_TIMBER_DARK, 0.025, (1, 0, 0))
    cbox(mb, (0.0, -1.65, 4.20), (3.20, 0.34, 0.46), 'timber', C_TIMBER_DARK, 0.025, (1, 0, 0))
    cbox(mb, (0.0, 0.45, 3.85), (3.10, 0.28, 0.36), 'timber', C_TIMBER_DARK, 0.022, (1, 0, 0))

    for sx in (-1.24, 1.24):
        for pz, top_y in ((3.95, 3.12), (1.70, 3.12)):
            with xf(mb, T(sx, 0.0, pz)):
                cyl(mb, 0.175, -2.10, top_y, 7, 'timber', jit(C_TIMBER_DARK, rng, 0.06), False, 0.02, 0.155)
            brace_pts.extend([(sx, -2.10, pz), (sx, 2.95, pz)])

        kb1 = [(sx, -1.85, 4.25), (sx, 2.94, -2.65)]
        tube(mb, kb1, [0.16, 0.14], 4, 'timber', jit(C_TIMBER_MID, rng, 0.07), mode='flat')
        kb2 = [(sx, -0.10, 3.85), (sx, 2.94, -5.85)]
        tube(mb, kb2, [0.145, 0.125], 4, 'timber', jit(C_TIMBER_MID, rng, 0.07), mode='flat')
        kb3 = [(sx, 0.65, 3.95), (sx, 2.94, 0.55)]
        tube(mb, kb3, [0.13, 0.12], 4, 'timber', C_TIMBER_DARK, mode='flat')

        for jz, jy in ((-5.75, 2.92), (-2.60, 2.92), (0.55, 2.92)):
            cbox(mb, (sx, jy, jz), (0.28, 0.24, 0.34), 'iron', C_IRON, 0.014)
        for p in kb1 + kb2:
            brace_pts.append(p)

    # Transverse X-bracing under cantilevered catwalk
    for (p0, p1) in (
        ((-1.24, 0.40, 2.55), ( 1.24, 2.85, -1.85)),
        (( 1.24, 0.40, 2.55), (-1.24, 2.85, -1.85)),
        ((-1.24, 1.35, 1.10), ( 1.24, 2.85, -4.65)),
        (( 1.24, 1.35, 1.10), (-1.24, 2.85, -4.65)),
    ):
        tube(mb, [p0, p1], 0.075, 4, 'timber', C_TIMBER_DARK, mode='flat')

    for sx in (-1.18, 0.0, 1.18):
        cbox(mb, (sx, 2.98, -1.12), (0.22, 0.26, 10.85), 'timber', C_TIMBER_DARK, 0.02, (0, 0, 1))
    for ji in range(9):
        jz = -6.20 + ji * 1.26
        cbox(mb, (0.0, 3.07, jz), (2.82, 0.14, 0.16), 'timber', C_TIMBER_MID, 0.014, (1, 0, 0))

    # 2. 29 Individual Varied Slightly-Skewed Oak Deck Planks ('timber')
    n_planks = 29
    plank_cols = (C_TIMBER_HI, C_TIMBER_MID, C_DRIFTWOOD, C_TIMBER_DARK)
    for pi in range(n_planks):
        pz = Z_SEA + 0.18 + (Z_CLIFF - Z_SEA - 0.36) * (pi / float(n_planks - 1))
        pw = 2.84 + rng.uniform(-0.10, 0.12)
        pcol = jit(plank_cols[pi % len(plank_cols)], rng, 0.08, 0.02)
        rot_m = R('Y', rng.uniform(-2.1, 2.1)) @ R('Z', rng.uniform(-0.8, 0.8))
        cbox(mb, (rng.uniform(-0.04, 0.04), DECK_Y - 0.045 + rng.uniform(-0.008, 0.008), pz),
             (pw, 0.095, 0.31), 'timber', pcol, 0.015, (1, 0, 0), M=rot_m)
        if pi % 2 == 0:
            for nx in (-1.18, 1.18):
                cbox(mb, (nx, DECK_Y + 0.006, pz), (0.045, 0.016, 0.045), 'iron', C_IRON_RUST, 0.004)

    cbox(mb, (-0.32, DECK_Y + 0.022, -2.35), (1.35, 0.04, 0.24), 'timber', C_DRIFTWOOD, 0.008, M=R('Y', 9.0))
    cbox(mb, ( 0.42, DECK_Y + 0.022,  0.85), (1.20, 0.04, 0.22), 'timber', C_TIMBER_HI, 0.008, M=R('Y', -7.5))

    for sx in (-1.36, 1.36):
        cbox(mb, (sx, DECK_Y + 0.045, -1.12), (0.12, 0.09, 10.65), 'timber', C_TIMBER_DARK, 0.012, (0, 0, 1))

    # 3. Stout Timber Handrail Posts & Sagging Catenary Braided Hemp Rope Rails
    post_zs = [3.65, 1.25, -1.15, -3.55, -6.10]
    post_tops = {-1: [], 1: []}
    for sgn in (-1, 1):
        px = sgn * 1.36
        for idx, pz in enumerate(post_zs):
            if sgn == 1 and idx == 4:
                post_tops[sgn].append((px, DECK_Y + 1.18, pz + 0.35))
                continue
            ph = 1.24 + rng.uniform(-0.06, 0.08) + (0.42 if (sgn == -1 and idx == 4) else 0.0)
            lean_x = rng.uniform(-2.2, 2.2)
            lean_z = rng.uniform(-2.5, 2.5)
            M = T(px, DECK_Y - 0.32, pz) @ R('X', lean_x) @ R('Z', lean_z)
            with xf(mb, M):
                cbox(mb, (0.0, (ph + 0.32) * 0.5, 0.0), (0.17, ph + 0.32, 0.17),
                     'timber', jit(C_TIMBER_MID, rng, 0.07), 0.02, (0, 1, 0))
                cbox(mb, (0.0, ph + 0.33, 0.0), (0.21, 0.06, 0.21), 'timber', C_TIMBER_HI, 0.015)
                cbox(mb, (0.0, ph + 0.12, 0.0), (0.19, 0.08, 0.19), 'iron', C_IRON, 0.008)
                for ri in range(3):
                    with xf(mb, T(0.0, ph - 0.06 + ri * 0.038, 0.0)):
                        torus(mb, 0.105, 0.020, 8, 5, 'rope', C_ROPE, True)
            top_pt = M @ Vector((0.0, ph + 0.16, 0.0))
            post_tops[sgn].append((top_pt.x, min(top_pt.y, DECK_Y + 1.18), top_pt.z))

        pts = post_tops[sgn]
        for i in range(len(pts) - 1):
            p0 = Vector(pts[i])
            p1 = Vector(pts[i + 1])
            for y_off, sag, rad in ((0.0, 0.20, 0.036), (-0.48, 0.14, 0.026)):
                cat = []
                for k in range(9):
                    t = k / 8.0
                    q = p0.lerp(p1, t)
                    q.y += y_off - sag * 4.0 * t * (1.0 - t)
                    cat.append(q)
                tube(mb, cat, rad, 6, 'rope', jit(C_ROPE, rng, 0.05), mode='smooth')

    rope_coil(mb, (-0.98, DECK_Y, -3.15), radius=0.28, turns=4, r=0.032)

    # 4. Dramatic Timber Harbour Cargo-Crane Jib Arm Cantilevered Off Seaward -Z End!
    kp_x, kp_z = 1.14, -5.75
    with xf(mb, T(kp_x, 0.0, kp_z)):
        cbox(mb, (0.0, 4.98, 0.0), (0.32, 5.16, 0.32), 'timber', C_TIMBER_DARK, 0.028, (0, 1, 0))
        for by in (3.32, 4.65, 6.25, 7.38):
            cbox(mb, (0.0, by, 0.0), (0.37, 0.14, 0.37), 'iron', C_IRON, 0.012)
        cbox(mb, (0.0, 7.60, 0.0), (0.38, 0.09, 0.38), 'timber', C_TIMBER_HI, 0.018)

    # Stability kickers tucked cleanly along starboard edge so deck walkway stays wide open!
    tube(mb, [(kp_x, 4.75, kp_z), (kp_x, 3.16, kp_z + 1.60)], [0.11, 0.12], 4, 'timber', C_TIMBER_MID, mode='flat')
    tube(mb, [(kp_x, 4.35, kp_z), (kp_x - 0.52, 3.16, kp_z - 0.48)], [0.09, 0.10], 4, 'timber', C_TIMBER_MID, mode='flat')

    jib_base = Vector((kp_x, 5.65, kp_z))
    jib_tip = Vector((-0.10, 7.72, -8.38))
    tube(mb, [jib_base, jib_tip], [0.15, 0.115], 4, 'timber', C_TIMBER_HI, mode='flat')
    tube(mb, [(kp_x, 7.38, kp_z), (jib_tip.x + 0.05, jib_tip.y - 0.06, jib_tip.z + 0.22)],
         [0.09, 0.08], 4, 'timber', C_TIMBER_MID, mode='flat')
    tube(mb, [(kp_x, 7.45, kp_z), (jib_tip.x, jib_tip.y + 0.04, jib_tip.z)],
         0.026, 6, 'iron', C_IRON, mode='flat')

    pulley_ctr = jib_tip + Vector((0.0, -0.34, 0.06))
    cbox(mb, jib_tip, (0.24, 0.24, 0.30), 'iron', C_IRON, 0.015)
    for sx in (-0.09, 0.09):
        cbox(mb, pulley_ctr + Vector((sx, 0.14, 0.0)), (0.04, 0.36, 0.12), 'iron', C_IRON, 0.008)
    with xf(mb, T(pulley_ctr) @ M_Y2X):
        torus(mb, 0.22, 0.042, 12, 6, 'iron', C_IRON, False)
        cyl(mb, 0.065, -0.11, 0.11, 8, 'brass', C_BRASS, False, 0.008)
        for k in range(3):
            cbox(mb, (0.0, 0.0, 0.0), (0.42, 0.036, 0.045), 'iron', C_IRON, 0.005, M=R('Y', k * 60.0))

    winch_pos = Vector((kp_x - 0.30, 4.28, kp_z + 0.18))
    with xf(mb, T(winch_pos) @ M_Y2X):
        cyl(mb, 0.16, -0.26, 0.26, 10, 'rope', C_ROPE, True, 0.01)
        cyl(mb, 0.22, -0.29, -0.24, 10, 'iron', C_IRON, False)
        cyl(mb, 0.22,  0.24,  0.29, 10, 'iron', C_IRON, False)
    tube(mb, [winch_pos + Vector((-0.28, 0.0, 0.0)), winch_pos + Vector((-0.38, 0.24, 0.0)),
              winch_pos + Vector((-0.56, 0.24, 0.0))], 0.025, 6, 'iron', C_IRON, mode='flat')

    # Swinging lashed wooden cargo crate & rum barrel — connect hoist cable seamlessly to rotated hook ring!
    cargo_ctr = Vector((pulley_ctr.x, 3.05, pulley_ctr.z))
    hook_ring_world = _build_hanging_cargo_bundle(mb, cargo_ctr, rng)
    tube(mb, [winch_pos + Vector((0.0, 0.12, -0.05)), Vector((kp_x - 0.08, 7.15, kp_z - 0.12)),
              pulley_ctr + Vector((0.0, 0.22, 0.04))], 0.030, 6, 'rope', C_ROPE, mode='smooth')
    rope_top = pulley_ctr + Vector((0.0, -0.18, 0.0))
    rope_mid = rope_top.lerp(hook_ring_world, 0.5)
    tube(mb, [rope_top, rope_mid, hook_ring_world], 0.032, 6, 'rope', C_ROPE, mode='smooth')

    # 5. Warm Hanging Pier Lantern on Port Seaward Post + Lantern_Catwalk Empty!
    gib_base = Vector((-1.36, 4.78, -6.10))
    gib_tip = Vector((-1.18, 4.86, -6.62))
    tube(mb, [gib_base, Vector((-1.26, 4.92, -6.36)), gib_tip], 0.026, 6, 'iron', C_IRON, mode='flat')
    tube(mb, [Vector((-1.36, 4.44, -6.10)), Vector((-1.24, 4.86, -6.44))], 0.020, 5, 'iron', C_IRON, mode='flat')
    lantern_pos = (-1.18, 4.30, -6.62)
    tube(mb, [gib_tip, (lantern_pos[0], lantern_pos[1] + 0.36, lantern_pos[2])], 0.014, 4, 'iron', C_IRON, mode='flat')
    build_lantern_geom(mb, lantern_pos, scale=1.12, hanging=True)

    build(mb)

    add_empty('Lantern_Catwalk', lantern_pos)
    col_box('col_catwalk_deck', (-1.46, 2.95, Z_SEA), (1.46, 3.26, Z_CLIFF))
    col_piece('col_catwalk_braces', brace_pts + [(-1.35, 2.94, 4.35), (1.35, 2.94, 4.35),
                                                 (-1.35, -2.05, 4.35), (1.35, -2.05, 4.35)])
    col_box('col_catwalk_crane', (0.72, 3.26, -6.20), (1.48, 7.65, -5.30))
    export_landmark_glb(outdir, 'cliff_catwalk_pier.glb')


# ================================================================ 4. IMPALED SHIPWRECK BOW
def gen_impaled_shipwreck_bow(outdir):
    clear_scene()
    rng = random.Random(SEED + 691)
    mb = MB('ImpaledShipwreckBow', seed=691)

    # 1. Sculpted Jagged Coastal Rock Fangs Base (plunging solidly to y = -2.4 m!)
    rock_pts = []
    rock_fangs = [
        (( 0.00, -0.58,  0.45), (3.85, 2.18, 4.35), ( 0.0,   0.0), ( 0,   0,   0), 0.34, 0.35),
        ((-0.25,  1.45, -0.65), (1.45, 2.95, 1.65), (-0.45, -0.55), ( 8,  15, -12), 0.16, 0.25),
        (( 2.45,  1.05,  1.30), (1.55, 2.55, 1.85), ( 0.45, -0.30), (-6, -24, -18), 0.20, 0.40),
        ((-2.65,  0.85,  0.90), (1.65, 2.35, 1.95), (-0.40,  0.25), ( 4,  32,  14), 0.22, 0.45),
        (( 0.65,  0.25, -2.65), (1.75, 1.95, 1.65), ( 0.25, -0.40), (10, -18,  -8), 0.18, 0.50),
        ((-1.15,  0.15,  3.50), (1.95, 1.85, 1.90), ( 0.0,   0.30), (-5,  22,   6), 0.26, 0.55),
    ]
    for ctr, rad, oh, rot_d, bf, mc in rock_fangs:
        mat_r = 'limestone_moss' if mc > 0.42 else 'limestone'
        pts = sculpt_rock_mass(
            mb, ctr, rad, mat_r, C_LIME_PALE, C_LIME_MID, C_LIME_DARK, rng,
            subdiv=2, warp=0.26, strata=0.16, overhang=oh,
            base_flare=bf, rot_deg=rot_d, crag_ribs=5, rib_amp=0.16, moss_cap=mc,
        )
        rock_pts.extend(pts)

    # 2. Dramatic Broken Galleon/Brigantine Bow Wedged at 26° Upward Pitch (+ 10° List)!
    hull_X = T(0.0, 2.35, 0.55) @ R('Z', -10.0) @ R('X', 26.0)
    hull_pts = []

    def keel_curve_y(z_l):
        """Sweeping upward curved galleon stempost height along z_l in [-5.6..+4.8]."""
        if z_l >= -1.60:
            return -1.65
        u = min(1.0, (-1.60 - z_l) / 3.90)
        return -1.65 + 3.45 * (u ** 1.85)

    def gunwale_curve_y(z_l):
        """Sheer line sweeping gently upward toward forecastle prow."""
        return 1.62 + 0.42 * max(0.0, (-z_l - 1.2) / 4.2)

    def hull_half_beam(z_l, y_norm):
        t = max(0.0, min(1.0, (z_l + 5.20) / 9.80))
        plan = 2.82 * (t ** 0.62) * (1.0 - 0.05 * max(0.0, t - 0.72))
        prof = 0.20 + 0.85 * sin(min(1.0, max(0.0, y_norm)) * pi * 0.68)
        return max(0.06, plan * prof)

    with xf(mb, hull_X):
        # Heavy curved dark-tarred keel + sweeping stempost matching keel_curve_y(z)!
        keel_zs = [4.75, 2.20, 0.0, -1.60, -2.85, -3.90, -4.75, -5.35, -5.75]
        keel_path = [(0.0, keel_curve_y(z), z) for z in keel_zs]
        keel_rads = [0.24, 0.26, 0.26, 0.26, 0.24, 0.22, 0.20, 0.18, 0.14]
        tube(mb, keel_path, keel_rads, 6, 'timber', C_TIMBER_DARK, mode='flat')

        # 12 curved wooden hull ribs following the exact swept keel-to-gunwale curve!
        for ri in range(12):
            zl = -4.35 + ri * 0.82
            is_aft = ri >= 9
            y_lo = keel_curve_y(zl) + 0.06
            y_hi = gunwale_curve_y(zl)
            for sgn in (-1.0, 1.0):
                max_yn = 1.0 if not is_aft else rng.uniform(0.42, 0.95)
                rib_pts = []
                for k in range(6):
                    yn = max_yn * (k / 5.0)
                    yl = y_lo + yn * (y_hi - y_lo)
                    xl = sgn * hull_half_beam(zl, yn) * 0.94
                    rib_pts.append((xl, yl, zl))
                tube(mb, rib_pts, [0.13, 0.12, 0.11, 0.10, 0.095, 0.075], 5,
                     'timber', jit(C_TIMBER_DARK, rng, 0.07), mode='flat')
                for rp in rib_pts:
                    hull_pts.append(hull_X @ Vector(rp))

        # Splintered broken aft longitudinal floor beams jutting raggedly where the ship snapped!
        for bi in range(6):
            bx = -1.90 + bi * 0.76
            by = -1.25 + 0.38 * (abs(bx) / 1.95) ** 2
            end_z = 4.65 + rng.uniform(0.35, 1.55)
            tube(mb, [(bx, by, 2.40), (bx + rng.uniform(-0.14, 0.14), by + rng.uniform(-0.18, 0.14), end_z)],
                 [0.11, 0.05], 4, 'timber', jit(C_DRIFTWOOD, rng, 0.09), mode='flat')

        # Layered clinker-planked tapered outer hull strakes cleanly sweeping up the curved stempost!
        n_strakes = 7
        z_nodes = [-5.15, -4.45, -3.55, -2.50, -1.35, -0.15, 1.10, 2.35, 3.60, 4.65]
        aft_cuts = {
            (-1, 0): 8, (-1, 1): 9, (-1, 2): 9, (-1, 3): 8, (-1, 4): 7, (-1, 5): 7, (-1, 6): 6,
            ( 1, 0): 8, ( 1, 1): 8, ( 1, 2): 7, ( 1, 3): 7, ( 1, 4): 6, ( 1, 5): 6, ( 1, 6): 5,
        }
        for sgn in (-1.0, 1.0):
            for si in range(n_strakes):
                yn0 = si / float(n_strakes)
                yn1 = (si + 1) / float(n_strakes)
                clink0 = 1.00 + si * 0.010
                clink1 = 1.03 + si * 0.010
                if si == 5:
                    mat_s, col_s = 'paint', C_PAINT_RED
                elif si == 4:
                    mat_s, col_s = 'paint', C_PAINT_TEAL
                elif si in (0, 6):
                    mat_s, col_s = 'timber', C_TIMBER_DARK
                else:
                    mat_s, col_s = 'timber', C_TIMBER_MID

                max_seg = aft_cuts[(int(sgn), si)]
                for zi in range(max_seg):
                    if si in (0, 1) and zi in (2, 3) and sgn < 0:
                        continue  # dramatic rock-impaled hull breach!
                    z0, z1 = z_nodes[zi], z_nodes[zi + 1]
                    k0, g0 = keel_curve_y(z0), gunwale_curve_y(z0)
                    k1, g1 = keel_curve_y(z1), gunwale_curve_y(z1)
                    # Interpolate strake smoothly between curved keel & sheer line so ZERO flap hangs below stempost!
                    y00 = k0 + yn0 * (g0 - k0)
                    y01 = k0 + yn1 * (g0 - k0)
                    y10 = k1 + yn0 * (g1 - k1)
                    y11 = k1 + yn1 * (g1 - k1)
                    x00 = sgn * hull_half_beam(z0, yn0) * clink0
                    x01 = sgn * hull_half_beam(z0, yn1) * clink1
                    x10 = sgn * hull_half_beam(z1, yn0) * clink0
                    x11 = sgn * hull_half_beam(z1, yn1) * clink1

                    pc = jit(col_s, rng, 0.08, 0.02)
                    q_out = [(x00, y00, z0), (x10, y10, z1), (x11, y11, z1), (x01, y01, z0)]
                    in_ref = Vector((0.0, 0.5 * (y00 + y11), 0.5 * (z0 + z1)))
                    mb.fp(q_out, mat_s, pc, (0, 0, 1), in_ref, smooth=False)
                    off_in = Vector((-sgn * 0.09, 0.0, 0.0))
                    q_in = [Vector(p) + off_in for p in reversed(q_out)]
                    out_ref = Vector((sgn * 6.0, 0.5 * (y00 + y11), 0.5 * (z0 + z1)))
                    mb.fp(q_in, 'timber', mul(C_TIMBER_DARK, 0.85), (0, 0, 1), out_ref, smooth=False)

                if si in (3, 5):
                    wale = []
                    for zi in range(max_seg + 1):
                        zl = z_nodes[zi]
                        kl, gl = keel_curve_y(zl), gunwale_curve_y(zl)
                        yl = kl + yn1 * (gl - kl)
                        xl = sgn * (hull_half_beam(zl, yn1) * clink1 + 0.05)
                        wale.append((xl, yl, zl))
                    wcol = C_PAINT_CREAM if si == 5 else C_TIMBER_DARK
                    wmat = 'paint' if si == 5 else 'timber'
                    tube(mb, wale, 0.075, 4, wmat, wcol, mode='flat')

        # Angled Weathered Foredeck Planks + Mooring Bitt & Gunwale Railings
        for di in range(12):
            zl = -4.45 + di * 0.68
            bw = hull_half_beam(zl, 0.78) * 1.88
            deck_y = gunwale_curve_y(zl) - 0.68
            if di >= 9:
                cbox(mb, (-bw * 0.24, deck_y, zl), (bw * 0.52, 0.11, 0.56), 'timber',
                     jit(C_DRIFTWOOD, rng, 0.08), 0.015, (1, 0, 0), M=R('Y', rng.uniform(-7, 7)))
            else:
                cbox(mb, (0.0, deck_y, zl), (bw, 0.11, 0.60), 'timber',
                     jit(C_TIMBER_HI if di % 2 == 0 else C_DRIFTWOOD, rng, 0.08), 0.015, (1, 0, 0),
                     M=R('Y', rng.uniform(-2.0, 2.0)))

        cbox(mb, (0.0, 1.48, -2.35), (1.35, 0.22, 0.22), 'timber', C_TIMBER_DARK, 0.02)
        for sx in (-0.42, 0.42):
            cbox(mb, (sx, 1.44, -2.35), (0.22, 0.92, 0.22), 'timber', C_TIMBER_MID, 0.02)
        for sgn in (-1.0, 1.0):
            rail_pts = []
            for zi in range(6):
                zl = z_nodes[zi]
                xl = sgn * hull_half_beam(zl, 1.0) * 1.03
                yl = gunwale_curve_y(zl) + 0.22
                rail_pts.append((xl, yl, zl))
                cbox(mb, (xl, yl - 0.18, zl), (0.12, 0.42, 0.12), 'timber', C_TIMBER_DARK, 0.012)
            tube(mb, rail_pts, 0.085, 5, 'timber', C_TIMBER_HI, mode='flat')

        # Carved Wooden & Gilded-Brass Sea-Serpent / Trident Prow Figurehead!
        serp_neck = [
            (0.0, 1.45, -5.25),
            (0.0, 1.78, -5.85),
            (0.0, 2.25, -6.32),
            (0.0, 2.72, -6.52),
            (0.0, 2.55, -6.96),
        ]
        tube(mb, serp_neck, [0.22, 0.20, 0.18, 0.16, 0.10], 6, 'timber', C_TIMBER_HI, mode='flat')
        for ty, tz in ((2.08, -6.00), (2.44, -6.24), (2.76, -6.42)):
            cbox(mb, (0.0, ty + 0.18, tz + 0.14), (0.08, 0.28, 0.36), 'brass', C_BRASS, 0.012, M=R('X', 32))
        tube(mb, [(0.0, 2.54, -6.82), (0.0, 2.86, -7.78)], [0.062, 0.025], 5, 'brass', C_BRASS, mode='flat')
        for sx in (-1.0, 1.0):
            tube(mb, [(0.0, 2.56, -6.92), (sx * 0.30, 2.64, -7.12), (sx * 0.28, 2.84, -7.62)],
                 [0.044, 0.040, 0.018], 5, 'brass', C_BRASS, mode='flat')

        # Dramatic Snapped Bowsprit Thrusting Skyward! (total asset length ~13.5 m!)
        sprit_path = [(0.0, 1.56, -2.05), (0.0, 2.58, -5.65), (0.0, 3.42, -8.35), (0.0, 3.76, -9.85)]
        tube(mb, sprit_path, [0.24, 0.20, 0.15, 0.08], 7, 'timber', C_DRIFTWOOD, mode='flat')
        for ang_s, slen in ((25, 0.58), (-35, 0.52), (150, 0.44)):
            tip = Vector(sprit_path[-1])
            off = Vector((cos(radians(ang_s)) * 0.06, sin(radians(ang_s)) * 0.06, 0.0))
            tube(mb, [tip + off, tip + off + Vector((off.x * 1.4, 0.16, -slen))],
                 [0.05, 0.015], 4, 'timber', C_TIMBER_HI, mode='flat')
        tube(mb, [(-2.25, 2.25, -7.55), (0.0, 2.96, -7.68), (1.85, 3.42, -7.42)],
             [0.068, 0.108, 0.058], 6, 'timber', C_TIMBER_MID, mode='flat')
        for bz in (-5.10, -7.62):
            by = 1.56 + (-bz - 2.05) * (2.20 / 7.80)
            with xf(mb, T(0.0, by, bz) @ R('X', -16)):
                torus(mb, 0.21, 0.038, 8, 5, 'rope', C_ROPE, True)

        shroud_paths = [
            [(0.0, 3.00, -7.62), (0.0, 1.68, -6.00), (0.0, 0.85, -4.90)],
            [(0.0, 3.22, -8.25), (-1.18, 2.38, -5.40), (-1.68, 1.75, -3.30)],
            [(0.0, 3.22, -8.25), ( 1.18, 2.38, -5.40), ( 1.68, 1.75, -3.30)],
            [(-2.05, 2.30, -7.55), (-2.15, 1.02, -7.35), (-2.00, -0.15, -7.10)],
            [( 1.65, 3.36, -7.44), ( 1.78, 2.05, -7.25), ( 1.60, 0.85, -6.98)],
        ]
        for sp in shroud_paths:
            tube(mb, sp, 0.034, 5, 'rope', jit(C_ROPE, rng, 0.06), mode='smooth')

        hawse_local = Vector((-1.14, 1.32, -3.88))
        with xf(mb, T(hawse_local) @ R('Y', -35) @ M_Y2X):
            torus(mb, 0.20, 0.055, 10, 6, 'iron', C_IRON, False)

        brack_base_local = Vector((0.88, 2.18, -4.45))
        brack_tip_local = Vector((1.24, 2.38, -5.05))
        tube(mb, [brack_base_local, brack_tip_local], 0.032, 6, 'iron', C_IRON, mode='flat')

    # 3. Iron Anchor Chain Spilling Out of Port Hawsehole Down Onto Coastal Rocks + Rusted Anchor!
    hawse_world = hull_X @ hawse_local
    chain_pts = [
        hawse_world,
        hawse_world + Vector((-0.28, -0.85, -0.15)),
        hawse_world + Vector((-0.55, -1.85,  0.02)),
        Vector((-2.25, 1.65, -2.05)),
        Vector((-2.55, 0.95, -1.55)),
        Vector((-2.35, 0.45, -2.25)),
    ]
    link_idx = 0
    for si in range(len(chain_pts) - 1):
        p0, p1 = chain_pts[si], chain_pts[si + 1]
        seg_v = p1 - p0
        seg_l = seg_v.length
        steps = max(2, int(seg_l / 0.16))
        t_dir = seg_v.normalized()
        rot_q = Vector((0, 1, 0)).rotation_difference(t_dir).to_matrix().to_4x4()
        for k in range(steps):
            pt = p0.lerp(p1, (k + 0.5) / float(steps))
            spin = R('Y', 90.0 if (link_idx % 2 == 0) else 0.0)
            with xf(mb, T(pt) @ rot_q @ spin @ S(0.75, 1.15, 0.75) @ M_Y2Z):
                torus(mb, 0.088, 0.026, 8, 5, 'iron', C_IRON if link_idx % 3 else C_IRON_RUST, False)
            link_idx += 1

    anc_pos = chain_pts[-1] + Vector((0.10, -0.25, -0.35))
    with xf(mb, T(anc_pos) @ R('Y', -35) @ R('X', 52) @ R('Z', 24)):
        cyl(mb, 0.065, -0.65, 0.78, 6, 'iron', C_IRON_RUST, False, 0.01)
        cbox(mb, (0.0, 0.62, 0.0), (1.05, 0.14, 0.14), 'timber', C_TIMBER_DARK, 0.015)
        tube(mb, [(-0.62, -0.22, 0.0), (-0.34, -0.62, 0.0), (0.0, -0.72, 0.0),
                  (0.34, -0.62, 0.0), (0.62, -0.22, 0.0)],
             [0.035, 0.065, 0.075, 0.065, 0.035], 5, 'iron', C_IRON, mode='flat')

    # 4. Hanging Tarnished Bow Lantern (dangling plumb vertical!) + Lantern_WreckBow Empty
    brack_tip_world = hull_X @ brack_tip_local
    lantern_pos = (brack_tip_world.x, brack_tip_world.y - 0.58, brack_tip_world.z)
    tube(mb, [brack_tip_world, (lantern_pos[0], lantern_pos[1] + 0.36, lantern_pos[2])],
         0.016, 5, 'iron', C_IRON, mode='flat')
    build_lantern_geom(mb, lantern_pos, scale=1.16, hanging=True)

    build(mb)

    add_empty('Lantern_WreckBow', lantern_pos)
    col_piece('col_wreck_rock', rock_pts)
    col_piece('col_wreck_hull', hull_pts)
    export_landmark_glb(outdir, 'impaled_shipwreck_bow.glb')


# ================================================================ 5. TRAIL LANTERN POST
def gen_trail_lantern_post(outdir):
    clear_scene()
    rng = random.Random(SEED + 719)
    mb = MB('TrailLanternPost', seed=719)

    # 1. Broad Grounded Ring of Chunky Mossy Fieldstones (y = -0.80..+0.48 m)
    n_stones = 8
    for k in range(n_stones):
        ang = 2.0 * pi * k / n_stones + rng.uniform(-0.16, 0.16)
        dist = 0.37 + rng.uniform(-0.04, 0.05)
        sx = cos(ang) * dist
        sz = sin(ang) * dist
        r_x = rng.uniform(0.25, 0.34)
        r_y = rng.uniform(0.24, 0.34)
        r_z = rng.uniform(0.25, 0.34)
        sculpt_rock_mass(
            mb, (sx, r_y * 0.30 - 0.08, sz), (r_x, r_y, r_z),
            'limestone_moss' if k % 2 == 0 else 'limestone',
            C_LEDGE_MOSS if k % 2 == 0 else C_LIME_PALE, C_LIME_MID, C_LIME_DARK, rng,
            subdiv=1, warp=0.20, strata=0.10, base_flare=0.30,
            rot_deg=(rng.uniform(-10, 10), rng.uniform(0, 360), rng.uniform(-10, 10)),
            moss_cap=0.65 if k % 2 == 0 else 0.25,
        )
    # Broad flat-bottomed stone root plinth anchoring cleanly down to y = -0.80 m
    sculpt_rock_mass(mb, (0.0, -0.36, 0.0), (0.56, 0.50, 0.56), 'limestone',
                     C_LIME_MID, C_LIME_SHADE, C_LIME_DARK, rng, subdiv=1, warp=0.16, base_flare=0.32)

    # 2. Slightly Leaning Rough-Hewn Timber Post (y = -0.80..+3.55 m)
    post_M = R('Z', 3.4) @ R('X', -2.6)
    with xf(mb, post_M):
        post_path = [
            (0.00, -0.80,  0.00),
            (0.01,  0.45,  0.01),
            (-0.02, 1.55, -0.01),
            (0.02,  2.65,  0.01),
            (0.00,  3.52,  0.00),
        ]
        tube(mb, post_path, [0.155, 0.142, 0.132, 0.122, 0.112], 7, 'timber', C_TIMBER_MID,
             mode='flat', scols=[C_TIMBER_DARK, C_TIMBER_DARK, C_TIMBER_MID, C_TIMBER_HI, C_DRIFTWOOD])
        cyl(mb, 0.135, 3.48, 3.60, 7, 'timber', C_TIMBER_DARK, False, 0.01, 0.04)
        cyl(mb, 0.145, 0.42, 0.54, 7, 'iron', C_IRON, False, 0.008)
        cyl(mb, 0.132, 3.24, 3.34, 7, 'iron', C_IRON, False, 0.008)

        # 3. Notched Timber Cross-Arm + Forged-Iron Scrollwork Bracket!
        cbox(mb, (0.38, 3.10, 0.0), (1.36, 0.15, 0.15), 'timber', C_TIMBER_HI, 0.018, (1, 0, 0))
        cbox(mb, (1.02, 3.13, 0.0), (0.10, 0.21, 0.17), 'timber', C_TIMBER_DARK, 0.014)
        cbox(mb, (0.0, 3.10, 0.0), (0.07, 0.07, 0.28), 'timber', C_TIMBER_DARK, 0.008)
        cbox(mb, (0.0, 3.10, 0.0), (0.28, 0.20, 0.22), 'iron', C_IRON, 0.010)
        # Iron eyelet collar & hanger hook bolted solidly into cross-arm underside
        cbox(mb, (0.92, 3.10, 0.0), (0.08, 0.18, 0.18), 'iron', C_IRON, 0.006)
        cyl(mb, 0.022, 2.98, 3.04, 6, 'iron', C_IRON, False)

        scroll_main = [
            (0.11, 2.46, 0.0), (0.26, 2.60, 0.0), (0.44, 2.82, 0.0),
            (0.64, 2.98, 0.0), (0.82, 3.04, 0.0),
        ]
        tube(mb, scroll_main, 0.022, 6, 'iron', C_IRON, mode='smooth')
        volute = []
        for k in range(11):
            t = k / 10.0
            ang = t * 1.85 * pi + 0.4
            rr = 0.14 * (1.0 - 0.55 * t)
            volute.append((0.36 + cos(ang) * rr, 2.86 + sin(ang) * rr, 0.0))
        tube(mb, volute, 0.015, 5, 'iron', C_IRON, mode='smooth')
        cbox(mb, (0.12, 2.46, 0.0), (0.04, 0.18, 0.09), 'iron', C_IRON, 0.005)

        # 4. Two Weathered Directional Arrow Wooden Signboards Nailed at Jaunty Pirate Angles!
        def add_arrow_sign(y_h, yaw_d, tilt_d, dir_sgn, col_wood, col_stripe):
            sign_M = T(0.0, y_h, -0.14 if dir_sgn > 0 else 0.14) @ R('Y', yaw_d) @ R('Z', tilt_d)
            with xf(mb, sign_M):
                x_back = -dir_sgn * 0.26
                x_neck =  dir_sgn * 0.46
                x_tip  =  dir_sgn * 0.72
                hw = 0.125
                outline = [
                    (x_back, -hw), (x_neck, -hw * 1.06), (x_tip, 0.0),
                    (x_neck,  hw * 1.06), (x_back,  hw),
                ]
                if dir_sgn < 0:
                    outline.reverse()
                hz = 0.024
                ctr_s = Vector((dir_sgn * 0.20, 0.0, 0.0))
                mb.fp([(px, py, -hz) for px, py in outline], 'timber', col_wood, (1, 0, 0), ctr_s + Vector((0, 0, 1)))
                mb.fp([(px, py,  hz) for px, py in reversed(outline)], 'timber', mul(col_wood, 0.90), (1, 0, 0), ctr_s - Vector((0, 0, 1)))
                for k in range(len(outline)):
                    k1 = (k + 1) % len(outline)
                    p0, p1 = outline[k], outline[k1]
                    mb.fp([(p0[0], p0[1], -hz), (p1[0], p1[1], -hz), (p1[0], p1[1], hz), (p0[0], p0[1], hz)],
                          'timber', mul(col_wood, 0.80), (1, 0, 0), ctr_s)
                for sz in (-hz - 0.008, hz + 0.008):
                    cbox(mb, (dir_sgn * 0.16, 0.0, sz), (0.52, 0.068, 0.014), 'paint', col_stripe, 0.003)
                    cbox(mb, (dir_sgn * 0.44, 0.0, sz), (0.14, 0.12, 0.014), 'paint', C_PAINT_CREAM, 0.003, M=R('Z', 45))
                for ny in (-0.055, 0.055):
                    cbox(mb, (0.0, ny, -hz - 0.010 if dir_sgn > 0 else hz + 0.010),
                         (0.032, 0.032, 0.022), 'iron', C_IRON, 0.004)

        add_arrow_sign(2.34, -18.0,  5.5,  1.0, C_TIMBER_HI, C_PAINT_TEAL)
        add_arrow_sign(1.94,  22.0, -6.5, -1.0, C_DRIFTWOOD, C_PAINT_RED)

        # 5. Coiled Hemp Rope Wrapped Tightly Around the Post + Hanging Tail
        for ri in range(5):
            with xf(mb, T(0.0, 1.34 + ri * 0.052, 0.0)):
                torus(mb, 0.148, 0.027, 10, 6, 'rope', mul(C_ROPE, 0.92 + 0.08 * (ri % 2)), True)
        tube(mb, [(0.145, 1.38, -0.04), (0.165, 1.15, -0.06), (0.155, 0.88, -0.03)],
             [0.026, 0.024, 0.020], 6, 'rope', C_ROPE, mode='smooth')
        for ri in range(2):
            with xf(mb, T(0.18 + ri * 0.048, 3.10, 0.0) @ M_Y2X):
                torus(mb, 0.095, 0.020, 8, 5, 'rope', C_ROPE, True)

        hook_local = Vector((0.92, 3.00, 0.0))

    # 6. Warm Glowing Iron-and-Brass Lantern Dangling Plumb Vertical + Lantern_Trail Empty!
    hook_world = post_M @ hook_local
    lantern_pos = (hook_world.x, hook_world.y - 0.56, hook_world.z)
    for k in range(3):
        cy = hook_world.y - 0.035 - k * 0.066
        with xf(mb, T(hook_world.x, cy, hook_world.z) @ R('Y', 90.0 * (k % 2)) @ M_Y2Z):
            torus(mb, 0.038, 0.011, 8, 5, 'iron', C_IRON, False)
    build_lantern_geom(mb, lantern_pos, scale=1.08, hanging=True)

    build(mb)

    add_empty('Lantern_Trail', lantern_pos)
    col_box('col_lantern_post', (-0.58, -0.80, -0.58), (0.58, 3.58, 0.58))
    export_landmark_glb(outdir, 'trail_lantern_post.glb')


# ================================================================ 6. STONE CAIRN MARKER
def gen_stone_cairn_marker(outdir):
    clear_scene()
    rng = random.Random(SEED + 751)
    mb = MB('StoneCairnMarker', seed=751)

    cairn_pts = []

    # 1. 6 Progressively Smaller Flat-Faceted Weathered Limestone Slabs (y = -0.50..+1.85 m)
    slab_specs = [
        (( 0.00, -0.06,  0.00), (0.98, 0.54, 0.92), ( 2,   8, -2), 'limestone_moss', C_LEDGE_MOSS, C_LIME_MID,  C_LIME_DARK,  0.42, 0.28, 0.72),
        (( 0.04,  0.42, -0.03), (0.76, 0.32, 0.72), (-3,  48,  4), 'limestone_moss', C_LIME_WARM,  C_LIME_MID,  C_LIME_SHADE, 0.44, 0.06, 0.52),
        ((-0.05,  0.76,  0.04), (0.62, 0.27, 0.58), ( 4, 112, -3), 'limestone',      C_LIME_PALE,  C_LIME_WARM, C_LIME_SHADE, 0.45, 0.04, 0.30),
        (( 0.03,  1.08, -0.02), (0.50, 0.24, 0.47), (-2, 175,  5), 'limestone',      C_LIME_PALE,  C_LIME_WARM, C_LIME_MID,   0.46, 0.02, 0.18),
        ((-0.02,  1.38,  0.02), (0.39, 0.21, 0.36), ( 3, 238, -4), 'limestone',      C_LIME_PALE,  C_LIME_WARM, C_LIME_MID,   0.48, 0.00, 0.10),
        (( 0.01,  1.66, -0.01), (0.28, 0.18, 0.26), (-4, 305,  3), 'limestone',      C_LIME_PALE,  C_LIME_PALE, C_LIME_WARM,  0.50, 0.00, 0.05),
    ]
    for ctr, rad, rot_d, mat_s, ct, cm, cb, ft, bf, mc in slab_specs:
        pts = sculpt_rock_mass(
            mb, ctr, rad, mat_s, ct, cm, cb, rng,
            subdiv=2, warp=0.18, strata=0.12, flat_top=ft,
            base_flare=bf, rot_deg=rot_d, crag_ribs=5, rib_amp=0.10, moss_cap=mc,
        )
        cairn_pts.extend(pts)

    for px, py, pz, pr in ((-0.74, 0.12, 0.48, 0.22), (0.78, 0.10, 0.32, 0.20), (0.62, 0.14, -0.58, 0.19)):
        pts = sculpt_rock_mass(
            mb, (px, py, pz), (pr * 1.2, pr * 0.75, pr), 'limestone_moss',
            C_LEDGE_MOSS, C_LIME_MID, C_LIME_DARK, rng, subdiv=1, warp=0.20, moss_cap=0.55,
        )
        cairn_pts.extend(pts)

    # 2. Weathered Driftwood Pointer Stake Wedged Into Top Rocks + Hemp Rope Lashing!
    stake_path = [
        ( 0.05, 1.32,  0.04),
        ( 0.02, 1.78,  0.02),
        (-0.02, 2.15, -0.01),
        (-0.05, 2.44, -0.04),
    ]
    tube(mb, stake_path, [0.056, 0.048, 0.040, 0.024], 6, 'timber', C_DRIFTWOOD, mode='flat')

    tube(mb, [(0.02, 2.02, 0.26), (-0.01, 2.05, -0.01), (-0.04, 2.09, -0.46)],
         [0.024, 0.030, 0.014], 5, 'timber', C_TIMBER_HI, mode='flat')

    for ri in range(3):
        with xf(mb, T(-0.01, 1.98 + ri * 0.036, -0.01) @ R('X', 22 * (1 if ri % 2 == 0 else -1))):
            torus(mb, 0.068, 0.016, 8, 5, 'rope', C_ROPE, True)
    for ri in range(2):
        with xf(mb, T(0.01, 1.62 + ri * 0.046, -0.01)):
            torus(mb, 0.27, 0.022, 10, 5, 'rope', mul(C_ROPE, 0.94), True)

    # 3. Fluttering Red Signal Pennant Cloth Strip ('paint', 3D double-sided!)
    _build_double_sided_pennant(
        mb,
        root_pos=(-0.04, 2.26, -0.04),
        length=0.92,
        h0=0.32,
        out_dir=(0.24, 0.0, -0.97),
        col_main=C_PAINT_RED,
        col_trim=C_PAINT_CREAM,
    )

    # 4. Weathered Carved Rune Marker Stone Propped Cleanly Against the Seaward Base!
    rune_M = T(0.10, 0.26, -0.94) @ R('Y', -14) @ R('X', -18)
    sculpt_stone_block(mb, (0.0, 0.0, 0.0), (0.62, 0.88, 0.22), 'temple_stone',
                       C_TEMPLE_HI, rng, chip=0.045, M=rune_M, moss_col=C_LEDGE_MOSS)
    with xf(mb, rune_M):
        cbox(mb, (0.0, 0.04, -0.105), (0.44, 0.64, 0.025), 'temple_stone', C_TEMPLE_DARK, 0.006)
        cbox(mb, (0.0, 0.14, -0.122), (0.30, 0.048, 0.024), 'brass', C_TEMPLE_GOLD, 0.005)
        cbox(mb, (0.0, 0.14, -0.122), (0.048, 0.34, 0.024), 'brass', C_TEMPLE_GOLD, 0.005)
        cbox(mb, (0.0, 0.14, -0.122), (0.14, 0.14, 0.026), 'brass', C_TEMPLE_GOLD, 0.005, M=R('Z', 45))
        for wy in (-0.11, -0.21):
            cbox(mb, (-0.08, wy, -0.120), (0.17, 0.036, 0.020), 'temple_stone', C_LIME_PALE, 0.004, M=R('Z', 20))
            cbox(mb, ( 0.08, wy, -0.120), (0.17, 0.036, 0.020), 'temple_stone', C_LIME_PALE, 0.004, M=R('Z', -20))
    for rx in (-0.31, 0.31):
        for ry in (-0.44, 0.44):
            for rz in (-0.12, 0.12):
                cairn_pts.append(rune_M @ Vector((rx, ry, rz)))

    build(mb)

    col_piece('col_cairn', cairn_pts)
    export_landmark_glb(outdir, 'stone_cairn_marker.glb')


SETPIECE_GENERATORS = [
    gen_skull_cliff_carving,
    gen_ancient_temple_stairway,
    gen_cliff_catwalk_pier,
    gen_impaled_shipwreck_bow,
    gen_trail_lantern_post,
    gen_stone_cairn_marker,
]
