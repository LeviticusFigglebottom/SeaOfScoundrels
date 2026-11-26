# Sea of Scoundrels: 3 Sea-of-Thieves-grade coastal storytelling 3D island landmarks (Batch B).
# Imported by tools/blender/gen_island_landmarks.py.
# Authored in Godot game coordinates (-Z forward/seaward, +Y up, +X starboard, metres).
import bmesh, math, random
from math import sin, cos, pi, sqrt, atan2, radians
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
    T, R, S, M_Y2Z, M_Y2X, newell,
    MB, xf,
    cbox, sculpt_stone_block, loft, lathe, tube, cyl, torus, rope_coil,
    build_lantern_geom, sculpt_rock_mass,
    clear_scene, build, col_piece, col_box, add_empty, export_landmark_glb,
)


# ---------------------------------------------------------------- local sculpting helpers
def _build_double_sided_pennant(mb, root_pos, length=1.42, h0=0.40, out_dir=(0.0, 0.0, -1.0),
                                col_main=C_PAINT_RED, col_trim=C_PAINT_CREAM, tattered=True):
    """Fluttering 3D double-sided cloth pennant visible from both sides (backface-cull safe)."""
    rp = Vector(root_pos)
    od = Vector(out_dir).normalized()
    side = Vector((-od.z, 0.0, od.x))
    if side.length < 1e-4:
        side = Vector((1.0, 0.0, 0.0))
    side.normalize()
    segs = 6
    thick = 0.011

    top_pts = []
    bot_pts = []
    for i in range(segs + 1):
        t = i / float(segs)
        wave = sin(t * 2.20 * pi) * 0.14 * t + 0.03 * sin(t * 4.5)
        droop = -0.18 * t * t
        hh = h0 * (1.0 - 0.54 * t)
        if tattered and i in (3, 4):
            hh *= 0.86
        ctr = rp + od * (length * t) + side * wave + Vector((0.0, droop, 0.0))
        top_pts.append(ctr + Vector((0.0, hh * 0.5, 0.0)))
        bot_pts.append(ctr - Vector((0.0, hh * 0.5, 0.0)))

    for i in range(segs):
        c_seg = col_trim if i == 0 else mul(col_main, 0.88 + 0.12 * ((i + 1) % 2))
        t0, t1 = top_pts[i], top_pts[i + 1]
        b0, b1 = bot_pts[i], bot_pts[i + 1]
        if i == segs - 1:
            # Deep tattered swallowtail notch at pennant tail
            mid_notch = (t0 + b0) * 0.25 + (t1 + b1) * 0.25 - od * (length * 0.12)
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


def _add_chain_links(mb, p_top, p_bot, n_links, link_r=0.056, wire_r=0.016,
                     segs=8, psegs=4, rust_stride=3, start_idx=0):
    """Alternating 90-degree hammered wrought-iron chain links between p_top and p_bot."""
    a = Vector(p_top)
    b = Vector(p_bot)
    seg_v = b - a
    if seg_v.length < 1e-5 or n_links < 1:
        return
    t_dir = seg_v.normalized()
    rot_q = Vector((0, 1, 0)).rotation_difference(t_dir).to_matrix().to_4x4()
    for k in range(n_links):
        pt = a.lerp(b, (k + 0.5) / float(n_links))
        spin = R('Y', 90.0 if ((k + start_idx) % 2 == 0) else 0.0)
        col = C_IRON_RUST if ((k + start_idx) % rust_stride == 0) else C_IRON
        with xf(mb, T(pt) @ rot_q @ spin @ S(0.76, 1.18, 0.76) @ M_Y2Z):
            torus(mb, link_r, wire_r, segs, psegs, 'iron', col, False)


def _build_sculpted_oar(mb, M_oar, length=2.85, rng=None):
    """Sculpted pirate wooden rowing oar: turned grip, leather collar, tapered loom, beveled blade."""
    with xf(mb, M_oar):
        # Local +Z along oar from grip (-L*0.46) to blade tip (+L*0.54)
        z_grip = -length * 0.46
        z_neck = length * 0.20
        z_tip  = length * 0.54

        # Ergonomic grip + tapered wooden shaft/loom
        shaft_path = [
            (0.0, 0.0, z_grip),
            (0.0, 0.0, z_grip + 0.20),
            (0.0, 0.0, -0.32),
            (0.0, 0.0,  0.18),
            (0.0, 0.0, z_neck),
        ]
        shaft_rads = [0.022, 0.036, 0.038, 0.035, 0.030]
        col_shaft = jit(C_TIMBER_HI, rng, 0.06) if rng else C_TIMBER_HI
        tube(mb, shaft_path, shaft_rads, 5, 'timber', col_shaft, mode='flat')

        # Dark worn leather oarlock sleeve + hemp whipping rings
        with xf(mb, T(0.0, 0.0, -0.40) @ M_Y2Z):
            cyl(mb, 0.044, -0.10, 0.10, 6, 'timber', C_TIMBER_DARK, False, 0.0)
        for wz in (-0.50, -0.30):
            with xf(mb, T(0.0, 0.0, wz) @ M_Y2Z):
                cyl(mb, 0.048, -0.014, 0.014, 6, 'rope', C_ROPE, False, 0.0)

        # Broad tapered beveled wooden oar blade (lofted 6-sided diamond/bevel cross-sections)
        blade_specs = [
            (z_neck - 0.04, 0.032, 0.024, C_TIMBER_MID),
            (z_neck + 0.24, 0.078, 0.018, C_TIMBER_HI),
            (z_tip  - 0.18, 0.106, 0.013, C_DRIFTWOOD),
            (z_tip,         0.080, 0.008, C_DRIFTWOOD),
        ]
        secs = []
        scols = []
        for zb, wx, wy, cb in blade_specs:
            secs.append([
                (-wx,        0.0,       zb),
                (-wx * 0.45,  wy,       zb),
                ( wx * 0.45,  wy,       zb),
                ( wx,        0.0,       zb),
                ( wx * 0.45, -wy,       zb),
                (-wx * 0.45, -wy,       zb),
            ])
            scols.append(jit(cb, rng, 0.05) if rng else cb)
        loft(mb, secs, 'timber', C_TIMBER_HI, closed=True, caps=(True, True), mode='flat', scols=scols)

        # Painted teal band near blade tip for lively pirate character
        cbox(mb, (0.0, 0.0, z_tip - 0.24), (0.208, 0.029, 0.088), 'paint', C_PAINT_TEAL, 0.0, (0, 0, 1))


def _loft_horizontal_masonry(mb, secs, mat, scols, rng, caps=(True, True)):
    """Emit a vertical tapered/fluted masonry shaft with strictly horizontal UV stone courses."""
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
            # Horizontal tangent along facet keeps ashlar masonry courses dead level!
            horiz = p01 - p00
            horiz.y = 0.0
            if horiz.length < 1e-5:
                horiz = Vector((1.0, 0.0, 0.0))
            horiz.normalize()
            face_col = jit(col_i, rng, 0.035, 0.012)
            mb.fp([p00, p01, p11, p10], mat, face_col, grain=horiz, inside=c_mid, smooth=False)
    if caps[0] and n > 1:
        mb.fp(secs[0], mat, scols[0], (1, 0, 0), cents[1], smooth=False)
    if caps[1] and n > 1:
        mb.fp(secs[-1], mat, scols[-1], (1, 0, 0), cents[-2], smooth=False)


# ================================================================ 1. BEACHED ROWBOAT WRECK
def gen_beached_rowboat_wreck(outdir):
    """~5.2 m weathered clinker-planked pirate rowboat heeled ~14° & pitched ~8°, half-buried in sand."""
    clear_scene()
    rng = random.Random(SEED + 811)
    mb = MB('BeachedRowboatWreck', seed=811)

    col_pts = []

    # Pose: ~14° heel to port (+Z lifts starboard +X, displaying the broken starboard bow planks!)
    # and ~8° pitch bow-up (+X lifts bow -Z while settling stern +Z deeper into the beach sand).
    boat_X = T(0.0, 0.14, 0.0) @ R('Z', 14.0) @ R('X', 8.0)

    # Parametric clinker rowboat hull lines (length = 5.20 m, z in [-2.60 .. +2.60])
    # Pointed bow at z = -2.60, trapezoidal raked transom at z = +2.60.
    def keel_y(z):
        if z < -1.25:
            u = min(1.0, (-1.25 - z) / 1.35)
            return -0.38 + 0.94 * (u ** 1.95)
        elif z > 1.35:
            u = min(1.0, (z - 1.35) / 1.25)
            return -0.38 + 0.26 * (u ** 1.60)
        return -0.38

    def sheer_y(z):
        if z < 0.0:
            u = min(1.0, -z / 2.60)
            return 0.36 + 0.28 * (u ** 1.65)
        u = min(1.0, z / 2.60)
        return 0.36 + 0.16 * (u ** 1.55)

    def half_beam(z, yn):
        u = max(0.0, min(1.0, (z + 2.60) / 5.20))
        if u < 0.56:
            plan = 0.94 * sin((u / 0.56) * pi * 0.5) ** 0.78
        else:
            v = (u - 0.56) / 0.44
            plan = 0.94 * (1.0 - 0.35 * (v ** 1.55))
        yn_c = max(0.0, min(1.0, yn))
        prof = 0.08 + 0.92 * (sin(yn_c * pi * 0.5) ** 0.64)
        if u > 0.75:
            stern_blend = smooth01((u - 0.75) / 0.25)
            prof = prof * (1.0 - 0.24 * stern_blend) + (0.48 + 0.52 * yn_c) * (0.24 * stern_blend)
        return max(0.025, plan * prof)

    with xf(mb, boat_X):
        # 1. Heavy Dark-Tarred Oak Keel, Curved Stempost (-Z) & Sternpost (+Z)
        keel_zs = [2.56, 1.95, 1.20, 0.30, -0.60, -1.35, -1.95, -2.35, -2.62]
        keel_path = [(0.0, keel_y(z) - 0.03, z) for z in keel_zs]
        keel_rads = [0.065, 0.076, 0.084, 0.085, 0.085, 0.082, 0.075, 0.066, 0.052]
        tube(mb, keel_path, keel_rads, 5, 'timber', C_TIMBER_DARK, mode='flat')

        # 2. Clinker-Planked Outer & Inner Hull Strakes (5 strakes/side, 9 stations)
        #    Starboard bow (sgn > 0) has a jagged broken-plank breach exposing interior oak ribs!
        z_nodes = [-2.58, -2.14, -1.60, -1.00, -0.35, 0.35, 1.02, 1.68, 2.20, 2.56]
        n_strakes = 5
        for sgn in (-1.0, 1.0):
            for si in range(n_strakes):
                yn0 = si / float(n_strakes)
                yn1 = (si + 1) / float(n_strakes)
                clink0 = 1.00 + si * 0.016
                clink1 = 1.045 + si * 0.016

                if si == 4:
                    mat_s, col_s = 'paint', C_PAINT_TEAL
                elif si == 3:
                    mat_s, col_s = 'timber', C_TIMBER_HI
                elif si == 2:
                    mat_s, col_s = 'timber', C_TIMBER_MID
                elif si == 1:
                    mat_s, col_s = 'timber', C_DRIFTWOOD
                else:
                    mat_s, col_s = 'timber', C_TIMBER_DARK

                for zi in range(len(z_nodes) - 1):
                    # Dramatic broken plank gap on the starboard bow revealing curved oak hull ribs!
                    if sgn > 0 and ((si == 2 and zi in (1, 2)) or (si == 3 and zi == 2)):
                        continue
                    z0, z1 = z_nodes[zi], z_nodes[zi + 1]
                    k0, g0 = keel_y(z0), sheer_y(z0)
                    k1, g1 = keel_y(z1), sheer_y(z1)
                    y00 = k0 + yn0 * (g0 - k0)
                    y01 = k0 + yn1 * (g0 - k0)
                    y10 = k1 + yn0 * (g1 - k1)
                    y11 = k1 + yn1 * (g1 - k1)
                    x00 = sgn * half_beam(z0, yn0) * clink0
                    x01 = sgn * half_beam(z0, yn1) * clink1
                    x10 = sgn * half_beam(z1, yn0) * clink0
                    x11 = sgn * half_beam(z1, yn1) * clink1

                    pc = jit(col_s, rng, 0.075, 0.02)
                    q_out = [(x00, y00, z0), (x10, y10, z1), (x11, y11, z1), (x01, y01, z0)]
                    in_ref = Vector((0.0, 0.5 * (y00 + y11) + 0.15, 0.5 * (z0 + z1)))
                    mb.fp(q_out, mat_s, pc, (0, 0, 1), in_ref, smooth=False)

                    off_in = Vector((-sgn * 0.048, 0.012, 0.0))
                    q_in = [Vector(p) + off_in for p in reversed(q_out)]
                    out_ref = Vector((sgn * 4.5, 0.5 * (y00 + y11) - 0.10, 0.5 * (z0 + z1)))
                    mb.fp(q_in, 'timber', jit(C_TIMBER_MID if si >= 3 else C_TIMBER_DARK, rng, 0.06),
                          (0, 0, 1), out_ref, smooth=False)

                    if si in (0, 4) and zi % 2 == 0:
                        col_pts.append(boat_X @ Vector((x01, y01, z0)))
                        col_pts.append(boat_X @ Vector((x11, y11, z1)))

        # Jagged splintered broken plank stubs framing the starboard bow hull breach!
        breach_stubs = [
            ((0.36, 0.16, -2.14), (0.48, 0.11, -1.86), 0.036, 0.014, C_TIMBER_MID),
            ((0.44, 0.25, -1.62), (0.56, 0.21, -1.36), 0.038, 0.013, C_TIMBER_HI),
            ((0.76, 0.04, -0.96), (0.64, 0.09, -1.26), 0.038, 0.014, C_TIMBER_MID),
            ((0.83, 0.20, -0.98), (0.71, 0.26, -1.22), 0.035, 0.013, C_TIMBER_HI),
        ]
        for p0, p1, r0, r1, cs in breach_stubs:
            tube(mb, [p0, p1], [r0, r1], 4, 'timber', jit(cs, rng, 0.07), mode='flat')

        # 3. Painted Cream Gunwale Trim Cap + Teal Rub-Strake & Forged-Iron Oarlocks
        for sgn in (-1.0, 1.0):
            gun_pts = []
            for z in z_nodes:
                xg = sgn * (half_beam(z, 1.0) * 1.11 + 0.02)
                yg = sheer_y(z) + 0.015
                gun_pts.append((xg, yg, z))
                col_pts.append(boat_X @ Vector((xg, yg, z)))
            tube(mb, gun_pts, 0.044, 4, 'paint', C_PAINT_CREAM, mode='flat')

            rub_pts = [(sgn * (half_beam(z, 0.84) * 1.10 + 0.015),
                        keel_y(z) + 0.84 * (sheer_y(z) - keel_y(z)), z) for z in z_nodes]
            tube(mb, rub_pts, 0.024, 4, 'paint', C_PAINT_TEAL, mode='flat')

            # U-shaped iron oarlock midships on gunwale
            z_ol = 0.06
            x_ol = sgn * (half_beam(z_ol, 1.0) * 1.10)
            y_ol = sheer_y(z_ol) + 0.045
            cbox(mb, (x_ol, y_ol, z_ol), (0.06, 0.042, 0.14), 'iron', C_IRON, 0.0)
            tube(mb, [
                (x_ol, y_ol + 0.11, z_ol - 0.048),
                (x_ol, y_ol + 0.025, z_ol - 0.030),
                (x_ol, y_ol + 0.025, z_ol + 0.030),
                (x_ol, y_ol + 0.11, z_ol + 0.048),
            ], 0.013, 4, 'iron', C_IRON_RUST if sgn > 0 else C_IRON, mode='flat')

        # 4. Sculpted Raked Trapezoidal Transom Stern (+Z)
        z_tr = 2.54
        k_tr, g_tr = keel_y(z_tr), sheer_y(z_tr)
        for ti in range(4):
            u0, u1 = ti / 4.0, (ti + 1) / 4.0
            ym = k_tr + 0.5 * (u0 + u1) * (g_tr - k_tr)
            ph = (g_tr - k_tr) * 0.255
            pw = half_beam(z_tr, 0.5 * (u0 + u1)) * 2.12
            t_mat = 'paint' if ti == 3 else 'timber'
            t_col = C_PAINT_TEAL if ti == 3 else jit(C_TIMBER_MID if ti % 2 else C_TIMBER_DARK, rng, 0.06)
            cbox(mb, (0.0, ym, z_tr), (pw, ph, 0.075), t_mat, t_col, 0.008, (1, 0, 0), M=R('X', -8))
        cbox(mb, (0.0, g_tr + 0.02, z_tr - 0.02), (half_beam(z_tr, 1.0) * 2.24, 0.068, 0.11),
             'paint', C_PAINT_CREAM, 0.008, (1, 0, 0))
        cbox(mb, (0.0, k_tr + 0.22, z_tr - 0.14), (0.11, 0.40, 0.20), 'timber', C_TIMBER_DARK, 0.0)

        # 5. 7 Curved Interior Oak Hull Ribs (visible inside open hull & through starboard bow breach!)
        rib_zs = [-1.92, -1.36, -0.78, -0.16, 0.48, 1.16, 1.84]
        for rz in rib_zs:
            kl = keel_y(rz) + 0.03
            gl = sheer_y(rz) - 0.02
            rib_path = []
            for k in range(7):
                s = (k - 3) / 3.0  # -1..+1
                sgn_r = -1.0 if s < 0 else (1.0 if s > 0 else 0.0)
                yn = abs(s)
                xr = sgn_r * half_beam(rz, yn) * 0.94
                yr = kl + (yn ** 1.18) * (gl - kl)
                rib_path.append((xr, yr, rz))
            tube(mb, rib_path, 0.035, 4, 'timber', jit(C_TIMBER_DARK, rng, 0.08), mode='flat')

        # 6. Weathered Slatted Bottom Floorboards (Duckboards) inside bilge
        for fi, fx in enumerate((-0.24, -0.08, 0.08, 0.24)):
            f_len = 2.60 - abs(fx) * 1.4
            f_y = -0.26 + abs(fx) * 0.14
            tilt_f = rng.uniform(-3.0, 3.0) if fi != 2 else 6.0
            cbox(mb, (fx, f_y, 0.10), (0.125, 0.032, f_len), 'timber',
                 jit(C_DRIFTWOOD if fi % 2 else C_TIMBER_MID, rng, 0.07), 0.0, (0, 0, 1),
                 M=R('Z', tilt_f))

        # 7. Bow Breasthook + Wooden Bow Cleat + 3 Rowing Thwarts (Middle Cracked & Askew!)
        cbox(mb, (0.0, 0.36, -2.02), (0.64, 0.055, 0.56), 'timber', C_TIMBER_HI, 0.008, (1, 0, 0))
        cbox(mb, (0.0, 0.43, -2.08), (0.08, 0.09, 0.10), 'timber', C_TIMBER_DARK, 0.0)
        cbox(mb, (0.0, 0.48, -2.08), (0.28, 0.048, 0.068), 'timber', C_TIMBER_DARK, 0.0, (1, 0, 0))

        # Bow thwart (z = -1.32)
        bw_bow = half_beam(-1.32, 0.72) * 1.98
        cbox(mb, (0.0, 0.20, -1.32), (bw_bow, 0.055, 0.27), 'timber', C_TIMBER_HI, 0.008, (1, 0, 0))

        # Middle thwart (z = -0.06) — CRACKED in the middle with starboard half sagging askew!
        bw_mid = half_beam(-0.06, 0.72) * 1.98
        cbox(mb, (-bw_mid * 0.23, 0.18, -0.05), (bw_mid * 0.52, 0.055, 0.28), 'timber',
             jit(C_TIMBER_MID, rng, 0.05), 0.008, (1, 0, 0), M=R('Y', 4.5) @ R('Z', -6.5))
        cbox(mb, ( bw_mid * 0.23, 0.14, -0.11), (bw_mid * 0.52, 0.055, 0.28), 'timber',
             jit(C_DRIFTWOOD, rng, 0.05), 0.008, (1, 0, 0), M=R('Y', -9.0) @ R('Z', 14.5))

        # Aft thwart (z = +1.18) + Stern seat (+2.14)
        bw_aft = half_beam(1.18, 0.74) * 1.98
        cbox(mb, (0.0, 0.19, 1.18), (bw_aft, 0.055, 0.28), 'timber', C_TIMBER_HI, 0.008, (1, 0, 0))
        bw_st = half_beam(2.14, 0.76) * 1.92
        cbox(mb, (0.0, 0.24, 2.14), (bw_st, 0.055, 0.34), 'timber', C_TIMBER_MID, 0.008, (1, 0, 0))

        # 8. Coiled Hemp Painter Rope Draped Over the Bow Cleat (`rope_coil`)
        rope_coil(mb, (0.0, 0.39, -1.98), radius=0.19, turns=3, r=0.025)

        # 9. Crooked Forged-Iron Stern Lantern Bracket Mounted on Starboard Transom (+Z)
        brack_base_l = Vector((0.46, 0.38, 2.52))
        brack_elbow_l = Vector((0.54, 0.96, 2.66))
        brack_tip_l = Vector((0.60, 1.06, 3.00))
        cbox(mb, (0.46, 0.38, 2.55), (0.11, 0.24, 0.045), 'iron', C_IRON, 0.0)
        tube(mb, [brack_base_l, brack_elbow_l, brack_tip_l], [0.026, 0.022, 0.018], 5, 'iron', C_IRON, mode='flat')
        # Welded iron corner brace connecting cleanly between vertical mast & overhang arm!
        tube(mb, [
            brack_base_l.lerp(brack_elbow_l, 0.50),
            brack_elbow_l + Vector((0.02, -0.08, 0.12)),
            brack_elbow_l.lerp(brack_tip_l, 0.58),
        ], 0.015, 4, 'iron', C_IRON_RUST, mode='flat')

    # Slack trailing hemp painter rope draping gracefully over the port bow gunwale onto beach sand!
    p_coil_exit = boat_X @ Vector((-0.14, 0.45, -2.02))
    p_gun_drape = boat_X @ Vector((-0.34, 0.58, -2.14))
    painter_world = [
        p_coil_exit,
        p_gun_drape,
        Vector((p_gun_drape.x - 0.18, 0.34, p_gun_drape.z - 0.14)),
        Vector((p_gun_drape.x - 0.36, 0.05, p_gun_drape.z - 0.22)),
        Vector((p_gun_drape.x - 0.62, 0.02, p_gun_drape.z - 0.08)),
        Vector((p_gun_drape.x - 0.86, 0.02, p_gun_drape.z + 0.18)),
    ]
    tube(mb, painter_world, 0.023, 5, 'rope', C_ROPE, mode='smooth')

    # 10. Pair of Sculpted Wooden Oars Resting Crossed Over the Aft Thwart & Beach Sand!
    #     Oar 1: grip on starboard-aft gunwale, crossing aft thwart & Oar 2 cleanly over low port gunwale onto sand!
    aft_thwart_w = boat_X @ Vector((0.0, 0.24, 1.18))
    oar1_grip = Vector((0.76, 0.59, 1.50))
    oar1_tip  = Vector((-1.58, 0.03, 0.72))
    oar1_v = oar1_tip - oar1_grip
    oar1_len = oar1_v.length
    # Center of oar in _build_sculpted_oar has grip at -0.46*L and tip at +0.54*L
    oar1_ctr = oar1_grip + oar1_v * 0.46
    oar1_rot = Vector((0, 0, 1)).rotation_difference(oar1_v.normalized()).to_matrix().to_4x4()
    _build_sculpted_oar(mb, T(oar1_ctr) @ oar1_rot @ R('Z', 18.0), length=oar1_len, rng=rng)
    #     Oar 2: crosses cleanly under Oar 1 on the aft thwart & port-aft gunwale down onto port-aft sand!
    oar2_M = T(aft_thwart_w + Vector((-0.40, 0.14, 0.46))) @ R('Y', -30.0) @ R('X', 12.0) @ R('Z', 10.0)
    _build_sculpted_oar(mb, oar2_M, length=2.76, rng=rng)

    # 11. 3 Coastal Limestone/Moss Beach Rocks Bracing the Buried Keel Down to y <= -0.86 m!
    #     Visibly wedge against the exterior hull & buried keel while plunging deep below y = -0.85 m.
    beach_rocks = [
        # Port midships keel-bracing boulder cradling the heeled port bilge (y ≈ -0.88 .. +0.26 m)
        ((-1.14, -0.36, -0.22), (0.68, 0.65, 0.86), ( 4,  18, -6), 0.36, 0.58),
        # Starboard-aft bracing rock cradling buried starboard-aft bilge & transom (y ≈ -0.88 .. +0.24 m)
        (( 1.06, -0.38,  1.52), (0.72, 0.64, 0.78), (-5, 112,  8), 0.38, 0.62),
        # Forward bow-keel grounding rock wedged squarely beneath the stranded bow forefoot (y ≈ -0.88 .. +0.20 m)
        (( 0.22, -0.40, -1.96), (0.64, 0.62, 0.68), ( 6, 235, -5), 0.34, 0.48),
    ]
    for ctr, rad, rot_d, bf, mc in beach_rocks:
        pts = sculpt_rock_mass(
            mb, ctr, rad, 'limestone_moss',
            C_LIME_WARM, C_LIME_MID, C_LIME_DARK, rng,
            subdiv=1, warp=0.22, strata=0.14, base_flare=bf,
            rot_deg=rot_d, crag_ribs=5, rib_amp=0.12, moss_cap=mc,
        )
        col_pts.extend(pts)

    # 12. Hanging Warm Brass Stern Lantern (plumb vertical!) + Lantern_Rowboat Empty
    brack_tip_w = boat_X @ brack_tip_l
    lantern_scale = 0.88
    lantern_pos = (brack_tip_w.x, brack_tip_w.y - 0.48, brack_tip_w.z)
    _add_chain_links(
        mb,
        brack_tip_w + Vector((0.0, -0.02, 0.0)),
        Vector((lantern_pos[0], lantern_pos[1] + 0.30 * lantern_scale, lantern_pos[2])),
        n_links=2, link_r=0.036, wire_r=0.010, segs=8, psegs=4,
    )
    build_lantern_geom(mb, lantern_pos, scale=lantern_scale, hanging=True)

    build(mb)

    add_empty('Lantern_Rowboat', lantern_pos)
    col_piece('col_rowboat', col_pts)
    export_landmark_glb(outdir, 'beached_rowboat_wreck.glb')


# ================================================================ 2. PIRATE WARNING GIBBET
def gen_pirate_warning_gibbet(outdir):
    """~7.4 m crooked salt-bleached pirate warning post & empty octagonal iron cage on mossy stone cairn."""
    clear_scene()
    rng = random.Random(SEED + 839)
    mb = MB('PirateWarningGibbet', seed=839)

    post_col_pts = []

    # 1. Chunky Mossy Coastal Stone Base Cairn (deeply rooted past y = -1.25 m!)
    cairn_specs = [
        # Broad grounded subterranean stone foundation plunging cleanly below y = -1.25 m
        (( 0.00, -0.64,  0.00), (1.46, 0.74, 1.46), ( 0,   0,  0), 0.36, 0.45),
        # 5 interlocking coastal headland boulders heaped solidly around the mast foot
        ((-0.68,  0.22, -0.52), (0.78, 0.56, 0.74), ( 6,  24, -8), 0.24, 0.68),
        (( 0.72,  0.18, -0.44), (0.76, 0.52, 0.70), (-5, 108,  7), 0.22, 0.58),
        (( 0.12,  0.34,  0.74), (0.84, 0.62, 0.72), ( 8, 196, -5), 0.25, 0.72),
        ((-0.62,  0.38,  0.54), (0.64, 0.48, 0.60), (-4, 285,  9), 0.18, 0.64),
        (( 0.48,  0.58,  0.12), (0.56, 0.44, 0.54), ( 5,  62, -6), 0.14, 0.74),
    ]
    for ctr, rad, rot_d, bf, mc in cairn_specs:
        pts = sculpt_rock_mass(
            mb, ctr, rad, 'limestone_moss',
            C_LIME_PALE if mc < 0.60 else C_LIME_WARM, C_LIME_MID, C_LIME_DARK, rng,
            subdiv=1, warp=0.24, strata=0.14, base_flare=bf,
            rot_deg=rot_d, crag_ribs=5, rib_amp=0.13, moss_cap=mc,
        )
        post_col_pts.extend(pts)

    # 2. Stout Leaning Rough-Hewn Salt-Bleached Timber Upright Mast (y = -1.22 .. +7.36 m)
    mast_path = [
        ( 0.00, -1.22,  0.00),
        ( 0.02,  0.55, -0.02),
        (-0.04,  2.25, -0.09),
        (-0.09,  4.05, -0.18),
        (-0.14,  5.75, -0.26),
        (-0.16,  6.72, -0.32),
        (-0.18,  7.34, -0.35),
    ]
    mast_rads = [0.29, 0.265, 0.242, 0.224, 0.208, 0.195, 0.165]
    # Smooth weather-beaten salt-bleached gradient from damp mossy base to bleached crown
    mast_cols = [
        C_TIMBER_DARK,
        mix(C_TIMBER_DARK, C_TIMBER_MID, 0.55),
        C_TIMBER_MID,
        mix(C_TIMBER_MID, C_DRIFTWOOD, 0.48),
        mix(C_TIMBER_MID, C_DRIFTWOOD, 0.82),
        C_DRIFTWOOD,
        C_DRIFTWOOD,
    ]
    tube(mb, mast_path, mast_rads, 7, 'timber', C_DRIFTWOOD, mode='flat', scols=mast_cols)
    with xf(mb, T(-0.18, 7.30, -0.35) @ R('X', 3.0) @ R('Z', 2.0)):
        cyl(mb, 0.18, 0.0, 0.12, 7, 'iron', C_IRON, False, 0.0, 0.05)
    for mp in mast_path:
        for sx in (-0.34, 0.34):
            for sz in (-0.34, 0.34):
                post_col_pts.append(Vector((mp[0] + sx, mp[1], mp[2] + sz)))

    def mast_at_y(yh):
        for i in range(len(mast_path) - 1):
            y0, y1 = mast_path[i][1], mast_path[i + 1][1]
            if y0 <= yh <= y1:
                t = (yh - y0) / max(y1 - y0, 1e-5)
                p0 = Vector(mast_path[i])
                p1 = Vector(mast_path[i + 1])
                r = mast_rads[i] * (1.0 - t) + mast_rads[i + 1] * t
                return p0.lerp(p1, t), r
        return Vector(mast_path[-1]), mast_rads[-1]

    # Wrought-iron collar bands cinched tight around the leaning mast
    for by in (1.38, 3.62, 4.72, 6.46):
        pc, rr = mast_at_y(by)
        with xf(mb, T(pc) @ R('X', 3.0)):
            cyl(mb, rr + 0.022, -0.068, 0.068, 7, 'iron',
                C_IRON_RUST if by == 3.62 else C_IRON, False, 0.0)

    # 3. Cantilevered Horizontal Crossbeam Extending Toward -Z + Diagonal Oak Knee Brace
    p_cross, _ = mast_at_y(6.62)
    beam_M = T(p_cross) @ R('X', 3.5)
    with xf(mb, beam_M):
        cbox(mb, (0.0, 0.0, -0.85), (0.28, 0.30, 3.54), 'timber', C_DRIFTWOOD, 0.024, (0, 0, 1))
        cbox(mb, (0.0, 0.0, -2.56), (0.31, 0.33, 0.14), 'iron', C_IRON, 0.0)
        cbox(mb, (0.0, 0.0,  0.84), (0.30, 0.32, 0.12), 'iron', C_IRON_RUST, 0.0)
        cbox(mb, (0.0, 0.0,  0.00), (0.34, 0.36, 0.38), 'iron', C_IRON, 0.0)
        cbox(mb, (0.0, 0.0, -2.26), (0.33, 0.35, 0.14), 'iron', C_IRON, 0.0)
        with xf(mb, T(0.0, -0.22, -2.26) @ M_Y2Z):
            torus(mb, 0.075, 0.022, 8, 4, 'iron', C_IRON, False)

    # Diagonal oak knee brace (mast y=4.72 -> crossbeam underside z=-1.55)
    p_knee_lo, _ = mast_at_y(4.72)
    p_knee_hi = beam_M @ Vector((0.0, -0.10, -1.55))
    knee_dir = p_knee_hi - p_knee_lo
    knee_mid = (p_knee_lo + p_knee_hi) * 0.5
    knee_rot = Vector((0, 1, 0)).rotation_difference(knee_dir.normalized()).to_matrix().to_4x4()
    with xf(mb, T(knee_mid) @ knee_rot):
        cbox(mb, (0.0, 0.0, 0.0), (0.21, knee_dir.length + 0.18, 0.22), 'timber', C_TIMBER_MID, 0.018, (0, 1, 0))
        for sy in (-knee_dir.length * 0.38, knee_dir.length * 0.38):
            cbox(mb, (0.0, sy, 0.0), (0.24, 0.12, 0.25), 'iron', C_IRON_RUST, 0.0)

    # Heavy Hemp Rope Lashings binding crossbeam joint & coiled mid-post + dangling tail
    for ri in range(3):
        with xf(mb, T(p_cross + Vector((0.0, -0.04 + ri * 0.06, -0.02))) @ R('X', 38 if ri % 2 == 0 else -38)):
            torus(mb, 0.30, 0.032, 8, 4, 'rope', mul(C_ROPE, 0.92 + 0.08 * (ri % 2)), True)
    p_rope, r_rope = mast_at_y(2.12)
    for ri in range(3):
        with xf(mb, T(p_rope + Vector((0.0, ri * 0.064, 0.0))) @ R('X', 3.0)):
            torus(mb, r_rope + 0.026, 0.028, 8, 4, 'rope', mul(C_ROPE, 0.90 + 0.10 * (ri % 2)), True)
    tube(mb, [
        p_rope + Vector((r_rope + 0.02, 0.04, -0.06)),
        p_rope + Vector((r_rope + 0.05, -0.28, -0.08)),
        p_rope + Vector((r_rope + 0.03, -0.62, -0.04)),
    ], [0.026, 0.024, 0.018], 5, 'rope', C_ROPE, mode='smooth')

    # 4. Heavy Wrought-Iron Chain + Iconic EMPTY Octagonal Wrought-Iron Warning Cage!
    #    Strictly ZERO gore or human remains — stylized Sea-of-Thieves warning landmark!
    hook_w = beam_M @ Vector((0.0, -0.27, -2.26))
    cage_top_swivel = Vector((hook_w.x, hook_w.y - 1.24, hook_w.z))
    _add_chain_links(mb, hook_w, cage_top_swivel, n_links=6, link_r=0.072, wire_r=0.020, segs=8, psegs=4)

    cage_M = T(cage_top_swivel) @ R('Y', 18.0) @ R('Z', -4.5) @ R('X', 3.5)
    with xf(mb, cage_M):
        # Top swivel ring & crown collar boss
        with xf(mb, T(0.0, -0.04, 0.0) @ M_Y2X):
            torus(mb, 0.082, 0.022, 8, 4, 'iron', C_IRON, False)
        cyl(mb, 0.11, -0.22, -0.10, 8, 'iron', C_IRON, False, 0.0, 0.08)

        y_top_hoop = -0.58
        y_mid_hoop = -1.42
        y_bot_hoop = -2.28
        r_cage = 0.62

        # 4 forged arched crown ribs from swivel boss down to top octagonal hoop
        for k in range(4):
            ang = k * pi * 0.5 + pi * 0.125
            ca, sa = cos(ang), sin(ang)
            arch_pts = [
                (ca * 0.08, -0.16, sa * 0.08),
                (ca * 0.36, -0.25, sa * 0.36),
                (ca * 0.56, -0.40, sa * 0.56),
                (ca * r_cage, y_top_hoop, sa * r_cage),
            ]
            tube(mb, arch_pts, 0.024, 4, 'iron', C_IRON_RUST if k % 2 else C_IRON, mode='flat')

        # Seamless octagonal top & bottom forged-iron hoops via 8-sided lathe (super crisp & light!)
        def add_solid_oct_hoop(yh, rad, h_band, thick_b, col_h):
            r_in = rad - thick_b * 0.5
            r_out = rad + thick_b * 0.5
            hh = h_band * 0.5
            prof = [
                (r_in,  yh - hh),
                (r_out, yh - hh),
                (r_out, yh + hh),
                (r_in,  yh + hh),
                (r_in,  yh - hh),
            ]
            with xf(mb, R('Y', -22.5)):
                lathe(mb, prof, 8, 'iron', col_h, smooth=False)

        add_solid_oct_hoop(y_top_hoop, r_cage, 0.090, 0.044, C_IRON)
        add_solid_oct_hoop(y_bot_hoop, r_cage, 0.105, 0.048, C_IRON)

        # Waist band with facet 5 open for the hinged slightly-ajar cage door + riveted corner bosses!
        door_facet = 5
        for k in range(8):
            a0 = 2.0 * pi * k / 8.0 + pi / 8.0
            a1 = 2.0 * pi * (k + 1) / 8.0 + pi / 8.0
            p0 = Vector((r_cage * cos(a0), y_mid_hoop, r_cage * sin(a0)))
            p1 = Vector((r_cage * cos(a1), y_mid_hoop, r_cage * sin(a1)))
            yaw_d = -math.degrees(atan2(p1.z - p0.z, p1.x - p0.x))
            if k != door_facet:
                mid = (p0 + p1) * 0.5
                seg_l = (p1 - p0).length + 0.024
                cbox(mb, mid, (seg_l, 0.095, 0.044), 'iron',
                     C_IRON_RUST if (k % 3 == 0) else C_IRON, 0.0, M=R('Y', yaw_d))
            # Riveted iron stud strictly on outer X/Z perimeter at exact hoop height (NEVER offset Y!)
            for yh_r in (y_top_hoop, y_mid_hoop, y_bot_hoop):
                cbox(mb, (p0.x * 1.045, yh_r, p0.z * 1.045), (0.040, 0.040, 0.040),
                     'iron', C_IRON_RUST if yh_r == y_mid_hoop else C_IRON, 0.0, M=R('Y', yaw_d))

        # 8 stout vertical forged-iron corner bars connecting bottom hoop through waist up to top hoop
        for k in range(8):
            ang = 2.0 * pi * k / 8.0 + pi / 8.0
            ca, sa = cos(ang), sin(ang)
            r_mid = r_cage + (0.065 if k == 2 else 0.0)
            bar_pts = [
                (ca * r_cage, y_bot_hoop, sa * r_cage),
                (ca * r_mid,  y_mid_hoop, sa * r_mid),
                (ca * r_cage, y_top_hoop, sa * r_cage),
            ]
            tube(mb, bar_pts, 0.022, 4, 'iron', C_IRON_RUST if k % 3 == 1 else C_IRON, mode='flat')

        # Bottom crossed iron grate floor bars (empty floor clearly visible from below!)
        for g_ang in (0.0, 45.0, 90.0, 135.0):
            with xf(mb, T(0.0, y_bot_hoop - 0.01, 0.0) @ R('Y', g_ang)):
                cbox(mb, (0.0, 0.0, 0.0), (r_cage * 1.92, 0.036, 0.042), 'iron', C_IRON, 0.0)

        # Hinged Slightly-Ajar Iron Cage Door + Brass Latch Hasp on facet `door_facet`
        a_hinge = 2.0 * pi * door_facet / 8.0 + pi / 8.0
        a_latch = 2.0 * pi * (door_facet + 1) / 8.0 + pi / 8.0
        p_hinge = Vector((r_cage * cos(a_hinge), y_mid_hoop, r_cage * sin(a_hinge)))
        p_latch = Vector((r_cage * cos(a_latch), y_mid_hoop, r_cage * sin(a_latch)))
        door_w = (p_latch - p_hinge).length
        door_yaw = -math.degrees(atan2(p_latch.z - p_hinge.z, p_latch.x - p_hinge.x))
        door_M = T(p_hinge) @ R('Y', door_yaw - 28.0)
        with xf(mb, door_M):
            for dy in (0.76, 0.0, -0.76):
                cbox(mb, (door_w * 0.5, dy, 0.0), (door_w, 0.056, 0.034), 'iron', C_IRON_RUST, 0.0)
            cbox(mb, (door_w * 0.5, 0.0, 0.0), (0.034, 1.54, 0.034), 'iron', C_IRON, 0.0)
            cbox(mb, (door_w - 0.02, 0.0, 0.0), (0.042, 1.56, 0.038), 'iron', C_IRON, 0.0)
            cbox(mb, (door_w + 0.03, 0.0, 0.026), (0.12, 0.072, 0.028), 'brass', C_BRASS, 0.0)
            for hy in (-0.54, 0.54):
                cyl(mb, 0.028, hy - 0.05, hy + 0.05, 6, 'iron', C_IRON, False)

    # 5. Angled Weathered Wooden Warning Signboard Nailed Mid-Post (Crossed Cutlasses!)
    p_sign, r_sign = mast_at_y(3.15)
    sign_M = T(p_sign + Vector((0.02, 0.0, -(r_sign + 0.05)))) @ R('Y', -10.0) @ R('Z', -7.5)
    with xf(mb, sign_M):
        plank_specs = [
            ( 0.23, 1.48, 0.21, C_TIMBER_HI),
            ( 0.00, 1.56, 0.22, C_DRIFTWOOD),
            (-0.23, 1.42, 0.20, C_TIMBER_MID),
        ]
        for py, pw, ph, pc in plank_specs:
            cbox(mb, (0.0, py, 0.0), (pw, ph, 0.052), 'timber', jit(pc, rng, 0.06), 0.008, (1, 0, 0))
        for bx in (-0.48, 0.48):
            cbox(mb, (bx, 0.0, 0.038), (0.09, 0.64, 0.042), 'timber', C_TIMBER_DARK, 0.0)
            for py in (-0.22, 0.0, 0.22):
                cbox(mb, (bx, py, -0.032), (0.036, 0.036, 0.024), 'iron', C_IRON, 0.0)
        # Painted Crimson Warning Plaque + Crossed Cream Cutlasses & Brass Hilts
        cbox(mb, (0.0, 0.0, -0.030), (1.18, 0.50, 0.016), 'paint', C_PAINT_RED, 0.0, (1, 0, 0))
        for csgn in (-1.0, 1.0):
            with xf(mb, T(0.0, 0.0, -0.044) @ R('Z', csgn * 28.0)):
                cbox(mb, (csgn * 0.14, 0.0, 0.0), (0.76, 0.072, 0.016), 'paint', C_PAINT_CREAM, 0.0, (1, 0, 0))
                cbox(mb, (csgn * 0.54, 0.01, 0.0), (0.14, 0.055, 0.015), 'paint', C_PAINT_CREAM, 0.0,
                     M=R('Z', -csgn * 18.0))
                cbox(mb, (-csgn * 0.26, 0.0, -0.004), (0.048, 0.18, 0.022), 'brass', C_BRASS, 0.0)
                cbox(mb, (-csgn * 0.38, 0.0, 0.0), (0.20, 0.052, 0.018), 'timber', C_TIMBER_DARK, 0.0)
        cbox(mb, (0.0,  0.14, 0.030), (1.02, 0.065, 0.012), 'paint', C_PAINT_RED, 0.0)
        cbox(mb, (0.0, -0.14, 0.030), (1.02, 0.065, 0.012), 'paint', C_PAINT_CREAM, 0.0)

    # 6. Fluttering Tattered Crimson Signal Pennant near Mast Peak ('paint', double-sided!)
    p_pen, r_pen = mast_at_y(7.04)
    with xf(mb, T(p_pen)):
        cyl(mb, r_pen + 0.018, -0.04, 0.04, 7, 'iron', C_IRON, False)
    _build_double_sided_pennant(
        mb,
        root_pos=p_pen + Vector((0.08, 0.0, -0.16)),
        length=1.55,
        h0=0.44,
        out_dir=(0.42, 0.0, -0.91),
        col_main=C_PAINT_RED,
        col_trim=C_PAINT_CREAM,
        tattered=True,
    )

    # 7. Warm Flickering Iron-Bracketed Warning Lantern + Lantern_Gallows Empty
    p_lbr, r_lbr = mast_at_y(4.32)
    lbr_M = T(p_lbr) @ R('Y', 24.0)
    with xf(mb, lbr_M):
        cbox(mb, (r_lbr + 0.02, 0.0, 0.0), (0.055, 0.34, 0.11), 'iron', C_IRON, 0.0)
        tube(mb, [
            (r_lbr, 0.12, 0.0),
            (r_lbr + 0.44, 0.14, 0.0),
            (r_lbr + 0.86, 0.16, 0.0),
            (r_lbr + 0.94, 0.08, 0.0),
        ], [0.026, 0.024, 0.022, 0.018], 4, 'iron', C_IRON, mode='flat')
        tube(mb, [
            (r_lbr, -0.32, 0.0),
            (r_lbr + 0.24, -0.18, 0.0),
            (r_lbr + 0.50,  0.02, 0.0),
            (r_lbr + 0.72,  0.14, 0.0),
        ], 0.018, 4, 'iron', C_IRON_RUST, mode='flat')
        l_hook_local = Vector((r_lbr + 0.94, 0.06, 0.0))

    l_hook_w = lbr_M @ l_hook_local
    l_scale = 1.08
    lantern_pos = (l_hook_w.x, l_hook_w.y - 0.58, l_hook_w.z)
    _add_chain_links(
        mb,
        l_hook_w + Vector((0.0, -0.02, 0.0)),
        Vector((lantern_pos[0], lantern_pos[1] + 0.30 * l_scale, lantern_pos[2])),
        n_links=2, link_r=0.040, wire_r=0.011, segs=8, psegs=4,
    )
    build_lantern_geom(mb, lantern_pos, scale=l_scale, hanging=True)

    build(mb)

    add_empty('Lantern_Gallows', lantern_pos)
    col_piece('col_gibbet_post', post_col_pts)
    export_landmark_glb(outdir, 'pirate_warning_gibbet.glb')


# ================================================================ 3. COASTAL SIGNAL BRAZIER
def gen_coastal_signal_brazier(outdir):
    """~5.6 m monumental octagonal coral-limestone harbour headland pedestal + wrought-iron firebowl."""
    clear_scene()
    rng = random.Random(SEED + 877)
    mb = MB('CoastalSignalBrazier', seed=877)

    col_pts = []

    # 1. Deep Grounded Octagonal Foundation Drum & 4 Mossy Headland Anchor Rocks (down to y = -1.45 m!)
    def oct_ring(y, r, rot_offset=pi / 8.0):
        return [(r * cos(2.0 * pi * k / 8.0 + rot_offset), y, r * sin(2.0 * pi * k / 8.0 + rot_offset))
                for k in range(8)]

    found_secs = [
        oct_ring(-1.45, 2.38),
        oct_ring(-0.65, 2.24),
        oct_ring( 0.08, 2.08),
    ]
    found_cols = [C_LIME_DARK, C_LIME_SHADE, C_LIME_MID]
    _loft_horizontal_masonry(mb, found_secs, 'limestone_moss', found_cols, rng)
    for ring in found_secs:
        col_pts.extend(Vector(p) for p in ring)

    # 4 chunky coastal limestone/moss anchor boulders wedging foundation into uneven coastal bluff rock
    for k in range(4):
        ang = k * pi * 0.5 + pi * 0.25 + rng.uniform(-0.14, 0.14)
        dist = 1.88 + rng.uniform(-0.10, 0.12)
        rx = rng.uniform(0.68, 0.86)
        ry = rng.uniform(0.56, 0.70)
        rz = rng.uniform(0.66, 0.84)
        pts = sculpt_rock_mass(
            mb, (cos(ang) * dist, -0.35 + rng.uniform(-0.08, 0.08), sin(ang) * dist),
            (rx, ry, rz), 'limestone_moss',
            C_LIME_WARM, C_LIME_MID, C_LIME_DARK, rng,
            subdiv=1, warp=0.22, strata=0.14, base_flare=0.34,
            rot_deg=(rng.uniform(-6, 6), rng.uniform(0, 360), rng.uniform(-6, 6)),
            crag_ribs=5, rib_amp=0.12, moss_cap=0.68,
        )
        col_pts.extend(pts)

    # 2. Broad Stepped Octagonal Weathered Ashlar Stone Plinth (y = 0.00 .. 1.42 m)
    for k in range(8):
        ang = 2.0 * pi * k / 8.0
        yaw_d = -math.degrees(ang)
        dist = 1.66
        blk_M = T(cos(ang) * dist, 0.30, sin(ang) * dist) @ R('Y', yaw_d)
        sculpt_stone_block(
            mb, (0.0, 0.0, 0.0), (0.58, 0.64, 1.32), 'temple_stone',
            C_TEMPLE_HI if k % 2 == 0 else C_TEMPLE_MID, rng,
            chip=0.055, M=blk_M, moss_col=C_LEDGE_MOSS,
        )
    plinth_secs = [
        oct_ring(0.05, 1.62),
        oct_ring(0.62, 1.56),
        oct_ring(0.66, 1.42),
        oct_ring(1.18, 1.36),
        oct_ring(1.24, 1.46),
        oct_ring(1.36, 1.44),
        oct_ring(1.42, 1.24),
    ]
    plinth_cols = [
        C_TEMPLE_DARK, C_TEMPLE_MID, C_TEMPLE_HI,
        C_TEMPLE_MID, C_TEMPLE_HI, C_LIME_WARM, C_TEMPLE_MID,
    ]
    _loft_horizontal_masonry(mb, plinth_secs, 'temple_stone', plinth_cols, rng)

    # 3. Monumental Tapered Fluted Octagonal Pillar & Corbeled Capital (y = 1.38 .. 3.84 m)
    #    16-point alternating ridge/flute section with horizontal ashlar masonry UV orientation!
    def fluted_oct_ring(y, r_outer, flute_depth=0.09, rot_offset=pi / 8.0):
        pts = []
        for k in range(16):
            ang = 2.0 * pi * k / 16.0 + rot_offset
            rad = r_outer if (k % 2 == 0) else (r_outer * cos(pi / 8.0) - flute_depth)
            pts.append((rad * cos(ang), y, rad * sin(ang)))
        return pts

    pillar_specs = [
        (1.38, 1.22, 0.03, C_TEMPLE_MID),
        (1.56, 1.15, 0.08, C_TEMPLE_HI),
        (2.38, 1.00, 0.09, C_TEMPLE_HI),
        (3.16, 0.88, 0.08, C_LIME_WARM),
        (3.32, 0.90, 0.02, C_TEMPLE_MID),
        (3.48, 1.08, 0.01, C_TEMPLE_HI),
        (3.68, 1.26, 0.00, C_LIME_PALE),
        (3.84, 1.22, 0.00, C_TEMPLE_MID),
    ]
    pillar_secs = [fluted_oct_ring(y, r, fd) for y, r, fd, _ in pillar_specs]
    pillar_cols = [c for _, _, _, c in pillar_specs]
    _loft_horizontal_masonry(mb, pillar_secs, 'temple_stone', pillar_cols, rng)
    for p in pillar_secs[-1][::2]:
        col_pts.append(Vector(p))

    # 4 Carved Coral-Limestone Cardinal Buttress Ribs bracing lower pillar shaft (N/S/E/W)
    for k in range(4):
        ang = k * pi * 0.5
        yaw_d = -math.degrees(ang)
        but_M = T(cos(ang) * 1.18, 1.72, sin(ang) * 1.18) @ R('Y', yaw_d) @ R('Z', 12.0)
        cbox(mb, (0.0, 0.0, 0.0), (0.34, 1.26, 0.30), 'temple_stone',
             jit(C_TEMPLE_HI, rng, 0.05), 0.024, (0, 0, 1), M=but_M)

    # 4. Embossed Tarnished Brass Compass-Ring Collar Bands ('brass')
    with xf(mb, T(0.0, 1.52, 0.0) @ R('Y', 22.5)):
        cyl(mb, 1.19, -0.075, 0.075, 8, 'brass', C_BRASS, False, 0.0)
    with xf(mb, T(0.0, 3.26, 0.0) @ R('Y', 22.5)):
        cyl(mb, 0.94, -0.095, 0.095, 8, 'brass', C_BRASS, False, 0.0)
    with xf(mb, T(0.0, 3.82, 0.0) @ R('Y', 22.5)):
        cyl(mb, 1.25, -0.045, 0.045, 8, 'brass', C_BRASS, False, 0.0)

    # Embossed cardinal & intercardinal brass compass diamond studs on both collar rings
    for cy_b, stud_r, sz_card, sz_inter in ((1.52, 1.14, 0.13, 0.085), (3.26, 0.91, 0.16, 0.105)):
        for k in range(8):
            ang = 2.0 * pi * k / 8.0
            yaw_d = -math.degrees(ang)
            is_card = (k % 2 == 0)
            sd = sz_card if is_card else sz_inter
            cbox(mb, (cos(ang) * stud_r, cy_b, sin(ang) * stud_r),
                 (0.065, sd, sd), 'brass', C_TEMPLE_GOLD if is_card else C_BRASS, 0.0,
                 M=R('Y', yaw_d) @ R('X', 45.0))

    # 5. 4 Heavy Scrolled Hammered Wrought-Iron Quadpod Brackets ('iron', cradling firebowl!)
    for k in range(4):
        ang = k * pi * 0.5 + pi * 0.25
        yaw_d = -math.degrees(ang)
        with xf(mb, R('Y', yaw_d)):
            cbox(mb, (0.93, 3.16, 0.0), (0.08, 0.42, 0.20), 'iron', C_IRON, 0.0)
            # Bold sweeping forged-iron bracket arm rising cleanly into upper crown finial
            arm_pts = [
                (0.94, 3.02, 0.0),
                (1.16, 3.20, 0.0),
                (1.38, 3.54, 0.0),
                (1.52, 3.98, 0.0),
                (1.55, 4.44, 0.0),
                (1.52, 4.82, 0.0),
                (1.62, 5.04, 0.0),
            ]
            tube(mb, arm_pts, [0.068, 0.064, 0.060, 0.056, 0.052, 0.048, 0.022], 5,
                 'iron', C_IRON_RUST if k % 2 else C_IRON, mode='flat')
            # Graceful nested inner forged scroll brace tucked smoothly under the stone corbel
            scroll_pts = [
                (0.96, 3.30, 0.0),
                (1.16, 3.44, 0.0),
                (1.36, 3.68, 0.0),
                (1.42, 3.90, 0.0),
                (1.30, 4.02, 0.0),
                (1.18, 3.92, 0.0),
            ]
            tube(mb, scroll_pts, 0.032, 4, 'iron', C_IRON, mode='flat')
            col_pts.append(R('Y', yaw_d) @ Vector((1.56, 4.86, 0.0)))

    # 6. Wide Flared Slatted Wrought-Iron Coastal Signal Firebowl (y ≈ 3.82 .. 4.92 m)
    ash_prof = [
        (0.00, 3.82),
        (0.84, 3.82),
        (0.98, 3.92),
        (1.08, 4.08),
        (0.98, 4.10),
        (0.00, 4.00),
    ]
    lathe(mb, ash_prof, 12, 'iron', C_IRON, smooth=False)

    # 3 heavy forged-iron containment hoops around flared slatted firebowl
    for hy, hr, hth, hcol in (
        (4.12, 1.12, 0.042, C_IRON),
        (4.48, 1.33, 0.044, C_IRON_RUST),
        (4.82, 1.50, 0.054, C_IRON),
    ):
        with xf(mb, T(0.0, hy, 0.0)):
            torus(mb, hr, hth, 12, 4, 'iron', hcol, False)

    # 12 curved flared hammered-iron basket slats framing the glowing amber firebed!
    for k in range(12):
        ang = 2.0 * pi * k / 12.0
        ca, sa = cos(ang), sin(ang)
        slat_pts = [
            (ca * 0.90, 3.92, sa * 0.90),
            (ca * 1.11, 4.14, sa * 1.11),
            (ca * 1.32, 4.48, sa * 1.32),
            (ca * 1.49, 4.82, sa * 1.49),
            (ca * 1.53, 4.95, sa * 1.53),
        ]
        tube(mb, slat_pts, [0.036, 0.036, 0.034, 0.034, 0.020], 4,
             'iron', C_IRON_RUST if k % 3 == 0 else C_IRON, mode='flat')

    # 7. Glowing Sculptured Multi-Faceted Amber Ember Firebed ('glass', strictly inside basket!)
    ember_ctr = Vector((0.0, 4.18, 0.0))
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
    for v in bm.verts:
        p = v.co.copy()
        ang = atan2(p.z, p.x)
        lump = 1.0 + 0.10 * sin(ang * 5.0 + p.y * 4.0) + 0.06 * cos(p.x * 5.5 - p.z * 5.0)
        # Strictly contained inside the lower/mid iron basket & ash pan (~0.94 m max radius)!
        rx = 0.82 * lump
        rz = 0.82 * lump
        ry = 0.44 * (1.0 + 0.16 * max(0.0, p.y)) if p.y >= 0.0 else 0.14
        v.co = ember_ctr + Vector((p.x * rx, p.y * ry, p.z * rz))
    bm.faces.ensure_lookup_table()
    mb.newoff()
    for f in bm.faces:
        pts = [v.co.copy() for v in f.verts]
        fc = sum(pts, Vector()) / len(pts)
        rad_n = min(1.0, sqrt(fc.x * fc.x + fc.z * fc.z) / 0.92)
        ec = mix(C_LANTERN_GL, C_MAGMA_GLOW, 0.42 + 0.50 * rad_n)
        mb.fp(pts, 'glass', jit(ec, rng, 0.07), (0, 1, 0), ember_ctr, smooth=False)
    bm.free()

    # 8. Stacked Charred Timber Signal Logs Criss-Crossed Boldly Inside Firebowl ('timber', C_TIMBER_DARK)
    log_specs = [
        # Lower crossed hearth logs cradled directly above the glowing ember bed
        ((-0.96, 4.44, -0.36), ( 1.02, 4.74,  0.44), 0.115, 0.095),
        (( 0.94, 4.42, -0.46), (-0.92, 4.78,  0.54), 0.110, 0.092),
        ((-0.38, 4.46,  0.96), ( 0.52, 4.80, -0.98), 0.106, 0.090),
        # Upper teepee-stacked charred signal logs rising cleanly above the iron rim!
        ((-0.88, 4.62,  0.24), ( 0.24, 5.26, -0.14), 0.098, 0.072),
        (( 0.80, 4.60,  0.40), (-0.22, 5.30, -0.18), 0.095, 0.068),
        (( 0.12, 4.62, -0.88), (-0.10, 5.24,  0.24), 0.096, 0.066),
        ((-0.26, 4.64,  0.80), ( 0.18, 5.18, -0.28), 0.092, 0.064),
    ]
    for p0, p1, r0, r1 in log_specs:
        v0, v1 = Vector(p0), Vector(p1)
        vm = v0.lerp(v1, 0.5) + Vector((rng.uniform(-0.03, 0.03), 0.03, rng.uniform(-0.03, 0.03)))
        c_end = jit(C_TIMBER_DARK, rng, 0.08)
        c_hot = mix(C_TIMBER_DARK, C_BASALT_HOT, 0.42)
        tube(mb, [v0, vm, v1], [r0, (r0 + r1) * 0.52, r1], 6, 'timber', c_end,
             mode='flat', scols=[c_end, c_hot, c_end])

    # Stylized Sculptured Amber/Magma Flame Tongues Licking Up to ~5.62 m Peak!
    flame_tongues = [
        (( 0.00, 4.80,  0.00), (0.26, 0.82, 0.24), ( 4,   0,   3), C_MAGMA_GLOW),
        ((-0.24, 4.74, -0.16), (0.19, 0.62, 0.18), ( 8,  25,  14), C_LANTERN_GL),
        (( 0.26, 4.72,  0.14), (0.20, 0.66, 0.19), (-7, -30, -15), C_MAGMA_GLOW),
        (( 0.12, 4.70, -0.26), (0.17, 0.54, 0.17), (12,  55,  -8), C_LANTERN_GL),
        ((-0.16, 4.68,  0.26), (0.16, 0.52, 0.16), (-11, 140, 10), C_MAGMA_GLOW),
    ]
    for fpos, (frx, fry, frz), frot, fcol in flame_tongues:
        fM = T(fpos) @ R('Y', frot[1]) @ R('X', frot[0]) @ R('Z', frot[2])
        with xf(mb, fM):
            prof = [
                (0.0,        -fry * 0.26),
                (frx,         0.0),
                (frx * 0.72,  fry * 0.44),
                (frx * 0.34,  fry * 0.76),
                (0.0,         fry),
            ]
            lathe(mb, prof, 5, 'glass', jit(fcol, rng, 0.06), smooth=False)

    build(mb)

    lantern_pos = (0.0, 5.06, 0.0)
    add_empty('Lantern_Brazier', lantern_pos)
    col_piece('col_brazier', col_pts)
    export_landmark_glb(outdir, 'coastal_signal_brazier.glb')


STORYTELLING_B_GENERATORS = [
    gen_beached_rowboat_wreck,
    gen_pirate_warning_gibbet,
    gen_coastal_signal_brazier,
]
