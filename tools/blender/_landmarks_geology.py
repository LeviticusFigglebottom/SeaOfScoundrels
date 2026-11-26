# Sea of Scoundrels: sculptural 3D geological cliff, overhang, sea-arch, basalt spire & boulder
# landmark generators for Blender 5.3.0.
# Authored in Godot game coordinates (-Z outward cliff normal, +Y up, +X starboard, metres).
# Embeds directly into island cliff slopes to shatter flat 2D heightfield silhouettes.

import bmesh
import math
import random
from math import sin, cos, pi, sqrt, atan2, radians
from mathutils import Vector, Matrix

from _landmark_common import (
    SEED,
    C_LIME_PALE,
    C_LIME_WARM,
    C_LIME_MID,
    C_LIME_SHADE,
    C_LIME_DARK,
    C_SEA_MOSS,
    C_LEDGE_MOSS,
    C_GRASS_SUN,
    C_GRASS_DEEP,
    C_BASALT_TOP,
    C_BASALT_MID,
    C_BASALT_DARK,
    C_BASALT_HOT,
    C_MAGMA_GLOW,
    T,
    R,
    S,
    MB,
    xf,
    mul,
    mix,
    jit,
    newell,
    smooth01,
    loft,
    sculpt_rock_mass,
    sculpt_basalt_column,
    add_vine_drape,
    clear_scene,
    build,
    col_piece,
    col_box,
    export_landmark_glb,
)


# ---------------------------------------------------------------- local sculptural helpers

def _sculpt_crag_rib(mb, p_bot, p_top, rx_bot, rz_bot, rx_top, rz_top, sides, rng,
                     mat='limestone', col_top=C_LIME_PALE, col_mid=C_LIME_WARM,
                     col_bot=C_LIME_SHADE, twist=0.14, rings=6, arch_z=0.0, apex_y=None):
    """Angular chiseled vertical limestone crag rib / spire buttress with stepped strata jogs."""
    pb = Vector(p_bot)
    pt = Vector(p_top)
    rib_scale = [rng.uniform(0.82, 1.18) for _ in range(sides)]
    rot0 = rng.uniform(0.0, 2.0 * pi)
    secs = []
    centers = []
    out_pts = []

    for ri in range(rings):
        t = ri / float(max(1, rings - 1))
        c = pb.lerp(pt, t)
        c.z += arch_z * sin(t * pi)
        # Flared skirt at bottom tapering organically into strata face
        flare = 1.0 + 0.28 * (1.0 - t) ** 2.0
        strata_step = (1.0 + 0.14 * sin(t * pi * 3.8 + 0.6)) * flare
        rx = (rx_bot * (1.0 - t) + rx_top * t) * strata_step
        rz = (rz_bot * (1.0 - t) + rz_top * t) * strata_step
        centers.append(c)
        ring = []
        for k in range(sides):
            ang = rot0 + 2.0 * pi * k / float(sides) + twist * t
            rk = rib_scale[k] * (0.92 + 0.10 * sin(ang * 2.0 + ri * 1.4))
            px = c.x + cos(ang) * rx * rk
            pz = c.z + sin(ang) * rz * rk
            py = c.y + (0.0 if ri in (0, rings - 1) else rng.uniform(-0.16, 0.16))
            v = Vector((px, py, pz))
            ring.append(v)
            out_pts.append(v)
        secs.append(ring)

    def _rib_col(pts, inside_pt):
        fn = newell(pts)
        fn = fn.normalized() if fn.length > 1e-8 else Vector((0.0, 1.0, 0.0))
        fc = sum(pts, Vector()) / float(len(pts))
        if fn.dot(fc - inside_pt) < 0.0:
            fn = -fn
        ht = smooth01((fc.y - pb.y) / max(pt.y - pb.y, 0.5))
        if fn.y > 0.52:
            base = mix(col_mid, col_top, smooth01((fn.y - 0.52) / 0.44))
        elif fn.y < -0.10:
            sh_t = smooth01((-fn.y - 0.10) / 0.55)
            base = mix(mix(col_bot, col_mid, ht * 0.5), mul(col_bot, 0.72), sh_t)
        else:
            base = mix(col_bot, col_mid, ht * 0.80 + 0.15)
            if fn.z < -0.35:
                base = mix(base, col_top, 0.24 * ht)
        return jit(base, rng, 0.05, 0.018)

    mb.newoff()
    for ri in range(rings - 1):
        r0, r1 = secs[ri], secs[ri + 1]
        inside = 0.5 * (centers[ri] + centers[ri + 1])
        for k in range(sides):
            kn = (k + 1) % sides
            q = [r0[k], r0[kn], r1[kn], r1[k]]
            mb.fp(q, mat, _rib_col(q, inside), (1, 0, 0), inside, smooth=False)

    mb.fp(secs[0], mat, mul(col_bot, 0.74), (1, 0, 0), centers[0] + Vector((0, 0.6, 0)), smooth=False)

    if apex_y is not None:
        apex = Vector((pt.x + rng.uniform(-0.14, 0.14), apex_y, pt.z + rng.uniform(-0.12, 0.12)))
        out_pts.append(apex)
        inside_top = pt - Vector((0, 0.5, 0))
        for k in range(sides):
            kn = (k + 1) % sides
            tri = [secs[-1][k], secs[-1][kn], apex]
            mb.fp(tri, mat, _rib_col(tri, inside_top), (1, 0, 0), inside_top, smooth=False)
    else:
        mb.fp(secs[-1], mat, _rib_col(secs[-1], centers[-1] - Vector((0, 0.6, 0))),
              (1, 0, 0), centers[-1] - Vector((0, 0.6, 0)), smooth=False)
    return out_pts


def _sculpt_underside_rib(mb, heel_pt, tip_pt, w_heel, d_heel, w_tip, d_tip, rng,
                          mat='limestone', arch_lift=0.38):
    """Chunky curved cantilevered limestone support rib bracing an overhang ceiling."""
    p0 = Vector(heel_pt)
    p1 = Vector(tip_pt)
    segs = 5
    secs = []
    centers = []
    out_pts = []

    for i in range(segs):
        t = i / float(segs - 1)
        c = p0.lerp(p1, t)
        c.y += arch_lift * sin(t * pi)
        w = (w_heel * (1.0 - t) + w_tip * t) * (1.0 + 0.10 * sin(t * 7.0))
        d = (d_heel * (1.0 - t) + d_tip * t) * (1.0 - 0.14 * sin(t * pi))
        centers.append(c)
        ring = [
            Vector((c.x - w * 0.54, c.y + d * 0.40, c.z)),
            Vector((c.x + w * 0.54, c.y + d * 0.40, c.z)),
            Vector((c.x + w * 0.36, c.y - d * 0.20, c.z)),
            Vector((c.x + rng.uniform(-0.05, 0.05), c.y - d * 0.62, c.z)),
            Vector((c.x - w * 0.36, c.y - d * 0.20, c.z)),
        ]
        secs.append(ring)
        out_pts.extend(ring)

    mb.newoff()
    for i in range(segs - 1):
        r0, r1 = secs[i], secs[i + 1]
        inside = 0.5 * (centers[i] + centers[i + 1])
        for k in range(5):
            kn = (k + 1) % 5
            q = [r0[k], r0[kn], r1[kn], r1[k]]
            fn = newell(q)
            if fn.length > 1e-8:
                fn.normalize()
                if fn.dot(sum(q, Vector()) * 0.25 - inside) < 0.0:
                    fn = -fn
            col = mix(C_LIME_DARK, C_LIME_SHADE, 0.35) if fn.y < -0.25 else mix(C_LIME_SHADE, C_LIME_MID, 0.45)
            mb.fp(q, mat, jit(col, rng, 0.05, 0.015), (0, 0, 1), inside, smooth=False)

    mb.fp(secs[0], mat, mul(C_LIME_SHADE, 0.78), (1, 0, 0), centers[1], smooth=False)
    mb.fp(secs[-1], mat, mul(C_LIME_SHADE, 0.85), (1, 0, 0), centers[-2], smooth=False)
    return out_pts


def _sculpt_stalactite_tooth(mb, top_pos, length, radius, rng, mat='limestone', sides=5):
    """Closed chunky faceted limestone karst stalactite tooth hanging from a cliff overhang lip."""
    tp = Vector(top_pos)
    rot0 = rng.uniform(0.0, 2.0 * pi)
    bend_x = rng.uniform(-0.08, 0.08) * length
    bend_z = rng.uniform(-0.10, 0.06) * length
    rings = [
        (-0.14, 1.32),
        ( 0.28, 0.88),
        ( 0.68, 0.46),
    ]
    secs = []
    centers = []
    for frac, rmul in rings:
        c = Vector((tp.x + bend_x * max(0.0, frac), tp.y - length * frac, tp.z + bend_z * max(0.0, frac)))
        centers.append(c)
        ring = []
        for k in range(sides):
            ang = rot0 + 2.0 * pi * k / float(sides) + max(0.0, frac) * 0.22
            rk = radius * rmul * (0.86 + 0.22 * sin(ang * 2.0 + frac * 3.0))
            ring.append(Vector((c.x + cos(ang) * rk, c.y, c.z + sin(ang) * rk)))
        secs.append(ring)

    tip = Vector((tp.x + bend_x * 1.08, tp.y - length, tp.z + bend_z * 1.08))
    mb.newoff()
    # Top cap (closes the mesh cleanly for manifold signed volume!)
    mb.fp(secs[0], mat, C_LIME_SHADE, (1, 0, 0), centers[1], smooth=False)
    for ri in range(len(secs) - 1):
        r0, r1 = secs[ri], secs[ri + 1]
        inside = 0.5 * (centers[ri] + centers[ri + 1])
        c_band = mix(C_LIME_MID, C_LIME_SHADE, 0.45 + 0.28 * ri)
        for k in range(sides):
            kn = (k + 1) % sides
            q = [r0[k], r0[kn], r1[kn], r1[k]]
            mb.fp(q, mat, jit(c_band, rng, 0.06, 0.015), (0, 1, 0), inside, smooth=False)

    inside_tip = centers[-1] + Vector((0, 0.18, 0))
    for k in range(sides):
        kn = (k + 1) % sides
        tri = [secs[-1][k], secs[-1][kn], tip]
        mb.fp(tri, mat, jit(mix(C_LIME_MID, C_LIME_SHADE, 0.65), rng, 0.06, 0.015), (0, 1, 0), inside_tip, smooth=False)


def _sculpt_tidal_pillar(mb, ring_specs, sides, rng, mat='limestone', rot_y=0.0, twist=0.14):
    """Continuous multi-ring flared coastal sea-arch pillar with barnacle & C_SEA_MOSS waterline band."""
    rib_scale = [rng.uniform(0.84, 1.16) for _ in range(sides)]
    rib_phase = [rng.uniform(0.0, 2.0 * pi) for _ in range(sides)]
    rings = []
    centers = []
    out_pts = []
    n_rings = len(ring_specs)

    for ri, (y, rx, rz, ox, oz) in enumerate(ring_specs):
        t = ri / float(max(1, n_rings - 1))
        centers.append(Vector((ox, y, oz)))
        ring = []
        strata_bump = 1.0 + 0.08 * sin(t * pi * 4.5 + 0.4)
        for k in range(sides):
            ang = rot_y + 2.0 * pi * k / float(sides) + twist * t
            chisel = rib_scale[k] * strata_bump * (1.0 + 0.07 * sin(t * 5.8 + rib_phase[k]))
            px = ox + cos(ang) * rx * chisel
            pz = oz + sin(ang) * rz * chisel
            py = y + (0.0 if ri in (0, n_rings - 1) else rng.uniform(-0.16, 0.16))
            v = Vector((px, py, pz))
            ring.append(v)
            out_pts.append(v)
        rings.append(ring)

    def _tidal_face_col(pts, inside_pt):
        fn = newell(pts)
        fn = fn.normalized() if fn.length > 1e-8 else Vector((0.0, 1.0, 0.0))
        fc = sum(pts, Vector()) / float(len(pts))
        if fn.dot(fc - inside_pt) < 0.0:
            fn = -fn
        pale_t = smooth01((fc.y - 1.5) / 8.5)
        facet_v = max(-0.4, min(0.4, fn.x * 0.28 - fn.z * 0.25 + fn.y * 0.45))
        base = mix(C_LIME_MID, C_LIME_PALE, max(0.0, min(1.0, pale_t * 0.72 + 0.12 + facet_v * 0.22)))
        if fn.y < -0.10:
            base = mix(base, C_LIME_SHADE, 0.55)
        elif fn.y > 0.55:
            base = mix(base, C_LIME_PALE, 0.24)
        # Wet dark barnacle zone below y = 0.0
        if fc.y < 0.35:
            wet_t = smooth01((0.35 - fc.y) / 1.8)
            base = mix(base, C_LIME_DARK, wet_t * 0.62)
        # Coastal barnacle / sea-moss waterline collar near y = -1.0 .. +2.2 m
        sea_moss_t = smooth01((2.3 - fc.y) / 1.5) * smooth01((fc.y + 1.4) / 1.2)
        if sea_moss_t > 0.01:
            base = mix(base, C_SEA_MOSS, sea_moss_t * 0.76)
        return jit(base, rng, 0.048, 0.018)

    mb.newoff()
    for ri in range(n_rings - 1):
        r0, r1 = rings[ri], rings[ri + 1]
        inside = 0.5 * (centers[ri] + centers[ri + 1])
        for k in range(sides):
            kn = (k + 1) % sides
            q = [r0[k], r0[kn], r1[kn], r1[k]]
            mb.fp(q, mat, _tidal_face_col(q, inside), (1, 0, 0), inside, smooth=False)

    mb.fp(rings[0], mat, mul(C_LIME_DARK, 0.72), (1, 0, 0), centers[0] + Vector((0, 0.8, 0)), smooth=False)
    mb.fp(rings[-1], mat, _tidal_face_col(rings[-1], centers[-1] - Vector((0, 0.8, 0))),
          (1, 0, 0), centers[-1] - Vector((0, 0.8, 0)), smooth=False)
    return out_pts


def _sculpt_faceted_slab(mb, center, radii, mat, col_top, col_mid, col_bot, rng,
                         subdiv=2, warp=0.22, strata=0.16, flat_top=0.0,
                         flat_bot=0.0, base_flare=0.0, rot_deg=(0, 0, 0), crag_ribs=5,
                         rib_amp=0.12, moss_cap=0.0, tidal_moss=False):
    """Faceted chunky rock slab with guaranteed outward winding, painterly smooth shadow shading & blocky rim."""
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
            d += warp * (0.36 if idx < 3 else 0.22) * sin(n.dot(dv) * (2.9 + idx * 0.6) + ph[idx])
        ang = atan2(p.z, p.x)
        d += rib_amp * (0.65 * cos(ang * crag_ribs + ph[6] + p.y * 0.7) + 0.35 * sin(ang * (crag_ribs + 2) + ph[7]))
        st_phase = p.y * 5.6 + ph[5] + 0.65 * sin(p.x * 2.3 + p.z * 2.1)
        d += strata * (sin(st_phase) + 0.35 * sin(st_phase * 2.0 + 0.8))
        if base_flare != 0.0 and p.y < 0.0:
            d += base_flare * (-p.y) * (-p.y)
        if flat_bot > 0.0 and p.y < -flat_bot:
            p.y = -flat_bot + (p.y + flat_bot) * 0.16
        elif p.y < -0.62:
            p.y = -0.62 + (p.y + 0.62) * 0.42
        if flat_top > 0.0 and p.y > flat_top:
            p.y = flat_top + (p.y - flat_top) * 0.14
        if flat_top > 0.0 and flat_bot > 0.0:
            rim_boost = 1.0 + 0.16 * max(0.0, 1.0 - (p.y / max(flat_top, 0.3)) ** 2)
            d *= rim_boost
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
            fw = X @ fc
            h01 = smooth01((fc.y / max(radii[1], 0.1) + 0.85) * 0.56)
            if fn.y > 0.50:
                top_c = mix(col_top, C_LEDGE_MOSS, moss_cap) if moss_cap > 0.01 else col_top
                base = mix(col_mid, top_c, smooth01((fn.y - 0.50) / 0.44))
            elif fn.y < -0.15:
                # Smooth painterly overhang underside darkening (never harsh isolated black patches!)
                sh_t = smooth01((-fn.y - 0.15) / 0.60)
                base = mix(mix(col_bot, col_mid, h01 * 0.6), mul(col_bot, 0.72), sh_t)
            else:
                base = mix(col_bot, col_mid, h01)
            if tidal_moss:
                if fw.y < 0.25:
                    base = mix(base, C_LIME_DARK, smooth01((0.25 - fw.y) / 1.6) * 0.55)
                sm_t = smooth01((2.2 - fw.y) / 1.4) * smooth01((fw.y + 1.4) / 1.2)
                if sm_t > 0.01:
                    base = mix(base, C_SEA_MOSS, sm_t * 0.76)
            st_tint = 0.90 + 0.14 * sin(fc.y * 1.45 + ph[8])
            c = jit(mul(base, st_tint), rng, 0.052, 0.018)
            mb.fp(pts, mat, c, (1, 0, 0), inside=None, smooth=False)
            for p in pts:
                out_pts.append(X @ p)
    bm.free()
    return out_pts


def _sculpt_shale_slab(mb, center, size, rot_deg, rng, mat='limestone',
                       col_top=C_LIME_PALE, col_mid=C_LIME_WARM, col_bot=C_LIME_SHADE,
                       moss_cap=0.0):
    """Angular tilted fractured limestone shale slab with crisp sedimentary cleavage steps."""
    sx, sy, sz = size
    sides = 6
    rot0 = rng.uniform(0.0, 2.0 * pi)
    rad_jitter = [rng.uniform(0.78, 1.18) for _ in range(sides)]
    X = T(center) @ R('Y', rot_deg[1]) @ R('X', rot_deg[0]) @ R('Z', rot_deg[2])

    layer_specs = [
        (-sy * 0.50, 1.08, 1.08),
        (-sy * 0.04, 1.02, 1.02),
        ( sy * 0.34, 0.94, 0.94),
        ( sy * 0.50, 0.76, 0.76),
    ]
    secs = []
    centers = []
    out_pts = []
    for li, (ly, mx, mz) in enumerate(layer_specs):
        ring = []
        centers.append(Vector((0.0, ly, 0.0)))
        for k in range(sides):
            ang = rot0 + 2.0 * pi * k / float(sides) + (0.05 if li >= 2 else 0.0)
            r_k = rad_jitter[k] * (1.0 + 0.06 * sin(k * 2.1 + li * 1.7))
            px = cos(ang) * sx * 0.5 * mx * r_k
            pz = sin(ang) * sz * 0.5 * mz * r_k
            py = ly + (rng.uniform(-0.04, 0.04) * sy if li in (1, 2) else 0.0)
            p = Vector((px, py, pz))
            ring.append(p)
            out_pts.append(X @ p)
        secs.append(ring)

    mb.newoff()
    with xf(mb, X):
        for li in range(len(secs) - 1):
            r0, r1 = secs[li], secs[li + 1]
            inside = 0.5 * (centers[li] + centers[li + 1])
            for k in range(sides):
                kn = (k + 1) % sides
                q = [r0[k], r0[kn], r1[kn], r1[k]]
                fn = newell(q)
                if fn.length > 1e-8:
                    fn.normalize()
                    if fn.dot(sum(q, Vector()) * 0.25 - inside) < 0.0:
                        fn = -fn
                wn = (X.to_3x3() @ fn).normalized()
                if wn.y > 0.45:
                    tc = mix(col_top, C_LEDGE_MOSS, moss_cap) if moss_cap > 0.01 else col_top
                    base = mix(col_mid, tc, smooth01((wn.y - 0.45) / 0.48))
                elif wn.y < -0.20:
                    base = mul(col_bot, 0.76)
                else:
                    base = mix(col_bot, col_mid, 0.40 + 0.35 * (li / 2.0))
                mb.fp(q, mat, jit(base, rng, 0.055, 0.018), (1, 0, 0), inside, smooth=False)

        mb.fp(secs[0], mat, mul(col_bot, 0.72), (1, 0, 0), Vector((0, 0.5, 0)), smooth=False)
        top_wn = (X.to_3x3() @ Vector((0, 1, 0))).normalized()
        top_c = mix(col_top, C_LEDGE_MOSS, moss_cap * smooth01((top_wn.y - 0.30) / 0.60)) if moss_cap > 0.01 else col_top
        mb.fp(secs[-1], mat, jit(top_c, rng, 0.04, 0.015), (1, 0, 0), Vector((0, -0.5, 0)), smooth=False)
    return out_pts


def _add_magma_fissure(mb, base_pos, top_pos, out_dir, width, rng):
    """Subtle recessed glowing molten magma fissure sliver tucked deep in basalt column cracks."""
    p0 = Vector(base_pos)
    p1 = Vector(top_pos)
    od = Vector(out_dir)
    od.y = 0.0
    if od.length < 1e-4:
        od = Vector((0.0, 0.0, -1.0))
    od.normalize()
    side = Vector((-od.z, 0.0, od.x))

    segs = 4
    pts_c = []
    for i in range(segs + 1):
        t = i / float(segs)
        zig = sin(t * pi * 2.5 + rng.uniform(-0.25, 0.25)) * width * 0.40
        c = p0.lerp(p1, t) + side * zig
        pts_c.append(c)

    mb.newoff()
    for i in range(segs):
        t0 = i / float(segs)
        t1 = (i + 1) / float(segs)
        w0 = width * max(0.14, sin(t0 * pi) ** 0.72)
        w1 = width * max(0.14, sin(t1 * pi) ** 0.72)
        c0 = pts_c[i]
        c1 = pts_c[i + 1]
        al = c0 - side * w0 - od * (width * 0.42)
        ar = c0 + side * w0 - od * (width * 0.42)
        am = c0 + od * (width * 0.20)
        bl = c1 - side * w1 - od * (width * 0.42)
        br = c1 + side * w1 - od * (width * 0.42)
        bm_pt = c1 + od * (width * 0.20)

        heat0 = 0.35 + 0.65 * sin(t0 * pi)
        heat1 = 0.35 + 0.65 * sin(t1 * pi)
        col_edge0 = mix(C_BASALT_HOT, C_MAGMA_GLOW, heat0 * 0.78)
        col_edge1 = mix(C_BASALT_HOT, C_MAGMA_GLOW, heat1 * 0.78)
        inside_pt = 0.5 * (c0 + c1) - od * 0.6

        mb.fp([al, am, bm_pt, bl], 'glass', [col_edge0, C_MAGMA_GLOW, C_MAGMA_GLOW, col_edge1],
              (0, 1, 0), inside_pt, smooth=False)
        mb.fp([am, ar, br, bm_pt], 'glass', [C_MAGMA_GLOW, col_edge0, col_edge1, C_MAGMA_GLOW],
              (0, 1, 0), inside_pt, smooth=False)


def _basalt_column_hull_pts(base_pos, height, radius, sides, tilt_x, tilt_z):
    """Generate clean outer sample points for a sculpt_basalt_column to feed col_piece."""
    bx, by, bz = base_pos
    pts = []
    for t in (0.0, 0.5, 1.0):
        y = by + t * height
        rad_t = radius * (1.02 - 0.18 * t) * (0.86 if t > 0.9 else 1.0)
        ox = bx + sin(radians(tilt_x)) * t * height
        oz = bz + sin(radians(tilt_z)) * t * height
        for k in range(sides):
            ang = 2.0 * pi * k / float(sides)
            pts.append(Vector((ox + rad_t * cos(ang), y, oz + rad_t * sin(ang))))
    return pts


# ---------------------------------------------------------------- 1. Cliff Buttress Tall

def gen_cliff_buttress_tall(outdir):
    """Monumental ~19 m tall continuous fractured limestone mountain spur / cliff buttress jutting toward -Z."""
    clear_scene()
    rng = random.Random(SEED + 201)
    mb = MB('CliffButtressTall', seed=201)
    col_pts = []

    # Deep continuous flared rock core plunging to y = -6.0 m and z = +5.2 m so steep cliffs never expose a bottom gap!
    col_pts += _sculpt_crag_rib(
        mb, (0.0, -5.80, 1.30), (0.0, 12.20, -0.45),
        4.45, 3.85, 2.85, 2.75, 7, rng,
        mat='limestone', col_top=C_LIME_PALE, col_mid=C_LIME_WARM, col_bot=C_LIME_SHADE,
        twist=0.14, rings=7, arch_z=-0.55,
    )

    # Bold forward-jutting central limestone prow spur descending cleanly from overhanging crown to y = -5.5 m
    col_pts += _sculpt_crag_rib(
        mb, (0.15, -5.50, -0.35), (-0.15, 10.60, -2.20),
        3.40, 2.85, 2.25, 2.35, 6, rng,
        mat='limestone', col_top=C_LIME_PALE, col_mid=C_LIME_WARM, col_bot=C_LIME_MID,
        twist=-0.16, rings=7, arch_z=-0.75,
    )

    # Port (-X) angular coastal buttress flank stepping outward & anchoring deep into the mountain skirt
    col_pts += _sculpt_crag_rib(
        mb, (-2.90, -5.20, 0.55), (-2.35, 9.40, -0.95),
        2.55, 2.75, 1.75, 2.05, 6, rng,
        mat='limestone', col_top=C_LIME_PALE, col_mid=C_LIME_WARM, col_bot=C_LIME_SHADE,
        twist=0.20, rings=6, arch_z=-0.45, apex_y=11.0,
    )

    # Starboard (+X) towering secondary rocky shoulder spur
    col_pts += _sculpt_crag_rib(
        mb, (2.95, -5.00, 0.65), (2.25, 10.20, -0.80),
        2.65, 2.70, 1.85, 2.05, 6, rng,
        mat='limestone', col_top=C_LIME_PALE, col_mid=C_LIME_WARM, col_bot=C_LIME_SHADE,
        twist=-0.18, rings=6, arch_z=-0.40, apex_y=12.1,
    )

    # Sculpted angular mid-cliff rock cheek blocks fused solidly into the ribs (natural geological fractures, zero air gaps!)
    col_pts += sculpt_rock_mass(
        mb, (-1.15, 3.80, -1.65), (2.55, 3.85, 2.15), 'limestone',
        C_LIME_PALE, C_LIME_WARM, C_LIME_MID, rng,
        subdiv=2, warp=0.20, strata=0.14, overhang=(-0.15, -0.55),
        base_flare=0.24, rot_deg=(3, -15, 4), crag_ribs=5, rib_amp=0.14,
    )
    col_pts += sculpt_rock_mass(
        mb, (1.35, 5.40, -1.55), (2.40, 3.95, 2.15), 'limestone',
        C_LIME_PALE, C_LIME_WARM, C_LIME_MID, rng,
        subdiv=2, warp=0.20, strata=0.14, overhang=(0.18, -0.60),
        base_flare=0.18, rot_deg=(-2, 16, -3), crag_ribs=5, rib_amp=0.14,
    )

    # Chunky overhanging sunlit limestone brow & integrated mossy crown shoulder (y = 9.8..14.0 m)
    col_pts += _sculpt_faceted_slab(
        mb, (-0.10, 11.40, -1.15), (3.85, 2.35, 3.10), 'limestone_moss',
        C_LEDGE_MOSS, C_LIME_PALE, C_LIME_WARM, rng,
        subdiv=3, warp=0.18, strata=0.12, flat_top=0.58,
        rot_deg=(0, 8, -2), crag_ribs=6, rib_amp=0.12, moss_cap=0.68,
    )
    col_pts += sculpt_rock_mass(
        mb, (-0.70, 12.60, 0.25), (2.75, 1.95, 2.35), 'limestone_moss',
        C_GRASS_SUN, C_LIME_PALE, C_LIME_WARM, rng,
        subdiv=2, warp=0.18, strata=0.12, flat_top=0.62,
        rot_deg=(2, -14, 3), crag_ribs=5, rib_amp=0.12, moss_cap=0.78,
    )

    # Subtle hanging jungle vines tucked along the overhanging brow shoulder
    add_vine_drape(mb, (-1.45, 10.65, -3.75), 3.30, 0.34, (-0.18, 0.0, -1.0), rng, phase=0.15)
    add_vine_drape(mb, ( 1.40, 10.75, -3.55), 2.85, 0.32, ( 0.14, 0.0, -1.0), rng, phase=0.62)

    build(mb)
    col_piece('col_buttress_tall', col_pts)
    export_landmark_glb(outdir, 'cliff_buttress_tall.glb')


# ---------------------------------------------------------------- 2. Cliff Buttress Wide

def gen_cliff_buttress_wide(outdir):
    """Broad ~17 m wide, ~14.5 m total grounded coastal cliff massif / terraced headland bluff."""
    clear_scene()
    rng = random.Random(SEED + 217)
    mb = MB('CliffButtressWide', seed=217)
    main_pts = []
    shelf_pts = []

    # Solid monolithic flared coastal headland core plunging to y = -5.5 m and back to z = +4.8 m (ZERO air slots!)
    main_pts += _sculpt_crag_rib(
        mb, (-3.60, -5.50, 0.90), (-3.10, 7.20, -0.35),
        4.60, 3.60, 3.85, 3.05, 7, rng,
        mat='limestone', col_top=C_LIME_PALE, col_mid=C_LIME_WARM, col_bot=C_LIME_SHADE,
        twist=0.10, rings=6, arch_z=-0.50,
    )
    main_pts += _sculpt_crag_rib(
        mb, (3.60, -5.50, 0.90), (3.10, 7.15, -0.35),
        4.65, 3.60, 3.90, 3.05, 7, rng,
        mat='limestone', col_top=C_LIME_PALE, col_mid=C_LIME_WARM, col_bot=C_LIME_SHADE,
        twist=-0.10, rings=6, arch_z=-0.50,
    )
    main_pts += _sculpt_crag_rib(
        mb, (0.05, -5.40, -0.20), (-0.10, 7.45, -1.15),
        4.10, 3.15, 3.55, 2.75, 7, rng,
        mat='limestone', col_top=C_LIME_PALE, col_mid=C_LIME_WARM, col_bot=C_LIME_MID,
        twist=0.06, rings=6, arch_z=-0.65,
    )

    # Outer angular headland shoulder spurs pushing width cleanly to ~16.5 m
    main_pts += _sculpt_crag_rib(
        mb, (-6.20, -4.80, 0.85), (-5.50, 5.90, 0.15),
        2.55, 2.75, 2.05, 2.25, 6, rng,
        mat='limestone', col_top=C_LIME_PALE, col_mid=C_LIME_WARM, col_bot=C_LIME_SHADE,
        twist=0.16, rings=5, arch_z=-0.35,
    )
    main_pts += _sculpt_crag_rib(
        mb, (6.20, -4.80, 0.85), (5.50, 5.85, 0.20),
        2.55, 2.75, 2.05, 2.25, 6, rng,
        mat='limestone', col_top=C_LIME_PALE, col_mid=C_LIME_WARM, col_bot=C_LIME_SHADE,
        twist=-0.16, rings=5, arch_z=-0.35,
    )

    # Stepped forward rocky outcrop cheekbones welded seamlessly across the mid face
    main_pts += sculpt_rock_mass(
        mb, (-2.85, 2.80, -1.65), (3.45, 3.55, 2.25), 'limestone',
        C_LIME_PALE, C_LIME_WARM, C_LIME_MID, rng,
        subdiv=2, warp=0.18, strata=0.14, overhang=(-0.10, -0.60),
        base_flare=0.22, rot_deg=(0, 8, 0), crag_ribs=6, rib_amp=0.13,
    )
    main_pts += sculpt_rock_mass(
        mb, (3.05, 2.65, -1.60), (3.45, 3.50, 2.25), 'limestone',
        C_LIME_PALE, C_LIME_WARM, C_LIME_MID, rng,
        subdiv=2, warp=0.18, strata=0.14, overhang=(0.12, -0.55),
        base_flare=0.22, rot_deg=(0, -10, 0), crag_ribs=6, rib_amp=0.13,
    )

    # Broad mossy walkable cliff terrace crown welded seamlessly across top (y ≈ 7.95 m, moss_cap=0.60)
    shelf_pts += _sculpt_faceted_slab(
        mb, (-3.05, 6.75, -0.95), (4.65, 2.15, 2.75), 'limestone_moss',
        C_LIME_PALE, C_LIME_WARM, C_LIME_MID, rng,
        subdiv=3, warp=0.16, strata=0.12, flat_top=0.52,
        rot_deg=(0, -5, 0), crag_ribs=6, rib_amp=0.11, moss_cap=0.62,
    )
    shelf_pts += _sculpt_faceted_slab(
        mb, (3.05, 6.70, -0.90), (4.65, 2.15, 2.75), 'limestone_moss',
        C_LIME_PALE, C_LIME_WARM, C_LIME_MID, rng,
        subdiv=2, warp=0.16, strata=0.12, flat_top=0.52,
        rot_deg=(0, 7, 0), crag_ribs=6, rib_amp=0.11, moss_cap=0.62,
    )
    shelf_pts += _sculpt_faceted_slab(
        mb, (0.05, 6.60, 1.35), (6.05, 2.40, 2.35), 'limestone_moss',
        C_LIME_PALE, C_LIME_WARM, C_LIME_MID, rng,
        subdiv=2, warp=0.15, strata=0.12, flat_top=0.56,
        rot_deg=(0, 3, 0), crag_ribs=5, rib_amp=0.10, moss_cap=0.66,
    )

    # Subtle hanging vines draped along the upper moss lip
    add_vine_drape(mb, (-3.85, 6.85, -3.55), 2.55, 0.34, (-0.10, 0.0, -1.0), rng, phase=0.22)
    add_vine_drape(mb, ( 2.65, 6.80, -3.48), 2.85, 0.36, ( 0.08, 0.0, -1.0), rng, phase=0.74)

    build(mb)

    # Collider 1: Main grounded coastal cliff massif
    col_piece('col_buttress_wide_main', main_pts)

    # Collider 2: Flat-topped walkable upper mossy cliff terrace shelf
    top_y = max(p.y for p in shelf_pts) - 0.10
    shelf_col_pts = [
        (-7.05, 5.40, -3.35), ( 7.05, 5.40, -3.35),
        (-7.25, 5.40,  3.15), ( 7.25, 5.40,  3.15),
        (-6.90, top_y, -3.50), ( 6.90, top_y, -3.50),
        (-7.15, top_y,  3.15), ( 7.15, top_y,  3.15),
    ]
    col_piece('col_buttress_wide_shelf', shelf_col_pts)
    export_landmark_glb(outdir, 'cliff_buttress_wide.glb')


# ---------------------------------------------------------------- 3. Cliff Overhang Ledge

def gen_cliff_overhang_ledge(outdir):
    """Iconic ~12.5 m wide cantilevered cliff overhang jutting ~6 m toward -Z with walkable top & open alcove."""
    clear_scene()
    rng = random.Random(SEED + 233)
    mb = MB('CliffOverhangLedge', seed=233)

    # --- Sturdy Anchored Cliff Heel (z = +1.5 .. +5.0 m, plunging deeply to y <= -2.45 m) ---
    sculpt_rock_mass(
        mb, (0.0, 0.72, 3.20), (3.95, 4.18, 1.75), 'limestone',
        C_LIME_MID, C_LIME_SHADE, C_LIME_SHADE, rng,
        subdiv=2, warp=0.19, strata=0.20, flat_top=0.68,
        base_flare=0.22, rot_deg=(0, 5, 0), crag_ribs=5, rib_amp=0.12,
    )
    # Flanking alcove cheek buttresses framing the shadowed grotto (kept back at z >= +1.2 m)
    sculpt_rock_mass(
        mb, (-3.95, 0.72, 2.55), (2.05, 4.15, 1.65), 'limestone',
        C_LIME_WARM, C_LIME_MID, C_LIME_SHADE, rng,
        subdiv=2, warp=0.20, strata=0.20, overhang=(0.15, -0.35),
        flat_top=0.68, base_flare=0.22, rot_deg=(0, -16, 4), crag_ribs=5, rib_amp=0.13,
    )
    sculpt_rock_mass(
        mb, (3.95, 0.72, 2.65), (2.05, 4.15, 1.65), 'limestone',
        C_LIME_WARM, C_LIME_MID, C_LIME_SHADE, rng,
        subdiv=2, warp=0.20, strata=0.20, overhang=(-0.15, -0.35),
        flat_top=0.68, base_flare=0.22, rot_deg=(0, 14, -4), crag_ribs=5, rib_amp=0.13,
    )

    # --- Cantilevered Main Overhanging Brow Slab (z = -5.4 .. +2.8 m, y = 3.55 .. 4.98 m) ---
    # Thick chunky limestone canopy slab (~1.3 m thick!) with flat walkable mossy plateau at y ≈ 4.8 m!
    _sculpt_faceted_slab(
        mb, (0.0, 4.30, -1.15), (4.15, 1.12, 3.55), 'limestone_moss',
        C_LEDGE_MOSS, C_LIME_PALE, C_LIME_SHADE, rng,
        subdiv=3, warp=0.13, strata=0.16, flat_top=0.52, flat_bot=0.56,
        rot_deg=(0, 4, 0), crag_ribs=6, rib_amp=0.10, moss_cap=0.72,
    )
    # Chunky cantilevered forward prow nose jutting boldly out to z ≈ -5.5 m
    _sculpt_faceted_slab(
        mb, (-0.25, 4.34, -3.50), (2.65, 1.06, 1.68), 'limestone_moss',
        C_GRASS_SUN, C_LIME_PALE, C_LIME_SHADE, rng,
        subdiv=2, warp=0.14, strata=0.15, flat_top=0.52, flat_bot=0.54,
        rot_deg=(0, -6, 0), crag_ribs=5, rib_amp=0.11, moss_cap=0.78,
    )
    # Port (-X) wing cantilevered brow slab expanding total width cleanly to ~12.5 m (X ≈ -6.25 m)
    _sculpt_faceted_slab(
        mb, (-3.75, 4.28, -0.35), (2.15, 1.08, 2.85), 'limestone_moss',
        C_LEDGE_MOSS, C_LIME_WARM, C_LIME_SHADE, rng,
        subdiv=2, warp=0.15, strata=0.16, flat_top=0.52, flat_bot=0.56,
        rot_deg=(0, -13, 0), crag_ribs=5, rib_amp=0.11, moss_cap=0.64,
    )
    # Starboard (+X) wing cantilevered brow slab expanding width cleanly to X ≈ +6.25 m
    _sculpt_faceted_slab(
        mb, (3.70, 4.26, -0.45), (2.20, 1.08, 2.80), 'limestone_moss',
        C_LEDGE_MOSS, C_LIME_WARM, C_LIME_SHADE, rng,
        subdiv=2, warp=0.15, strata=0.16, flat_top=0.52, flat_bot=0.56,
        rot_deg=(0, 14, 0), crag_ribs=5, rib_amp=0.11, moss_cap=0.66,
    )
    # Shadowed stepped strata chin plate welding the rear overhang solidly into the heel
    _sculpt_faceted_slab(
        mb, (0.10, 4.02, 0.80), (4.45, 0.82, 2.25), 'limestone',
        C_LIME_MID, C_LIME_SHADE, C_LIME_DARK, rng,
        subdiv=2, warp=0.14, strata=0.18, flat_top=0.56, flat_bot=0.56,
        rot_deg=(0, -5, 0), crag_ribs=6, rib_amp=0.10,
    )

    # --- Sculpted Underside Structural Rock Ribs bracing heel up into the overhang canopy ---
    _sculpt_underside_rib(mb, (-3.15, 3.15, 1.95), (-3.55, 3.88, -2.55), 0.88, 0.65, 0.44, 0.34, rng, arch_lift=0.38)
    _sculpt_underside_rib(mb, ( 0.05, 3.25, 2.05), (-0.15, 3.92, -4.15), 0.98, 0.68, 0.48, 0.36, rng, arch_lift=0.42)
    _sculpt_underside_rib(mb, ( 3.15, 3.12, 1.95), ( 3.45, 3.86, -2.45), 0.86, 0.64, 0.44, 0.34, rng, arch_lift=0.38)

    # --- Sculpted Chunky Limestone Stalactite Teeth framing the outer lip & alcove flanks ---
    teeth_specs = [
        (-4.65, 3.80, -1.75, 0.82, 0.34),
        (-3.35, 3.78, -2.95, 0.68, 0.30),
        (-1.95, 3.78, -4.20, 0.56, 0.26),
        (-0.45, 3.80, -4.85, 0.52, 0.25),
        ( 1.15, 3.78, -4.45, 0.58, 0.27),
        ( 2.65, 3.78, -3.25, 0.72, 0.31),
        ( 4.35, 3.80, -2.05, 0.84, 0.35),
        (-4.30, 3.75,  0.10, 0.78, 0.32),
        ( 4.25, 3.75,  0.15, 0.80, 0.33),
    ]
    for tx, ty, tz, tlen, trad in teeth_specs:
        _sculpt_stalactite_tooth(mb, (tx, ty, tz), tlen, trad, rng)

    # --- 6 Hanging Jungle Vines draped cleanly from beneath the cantilevered brow lip ---
    vine_specs = [
        (-4.55, 4.15, -2.88, 2.55, 0.34, (-0.30, 0.0, -1.0), 0.08),
        (-2.85, 4.18, -4.08, 2.15, 0.30, (-0.15, 0.0, -1.0), 0.26),
        (-1.15, 4.24, -5.08, 1.85, 0.28, (-0.06, 0.0, -1.0), 0.44),
        ( 0.80, 4.22, -4.98, 2.25, 0.31, ( 0.08, 0.0, -1.0), 0.61),
        ( 2.75, 4.16, -3.88, 2.65, 0.34, ( 0.20, 0.0, -1.0), 0.79),
        ( 4.45, 4.12, -2.78, 2.40, 0.32, ( 0.34, 0.0, -1.0), 0.93),
    ]
    for vx, vy, vz, vlen, vw, vdir, vph in vine_specs:
        add_vine_drape(mb, (vx, vy, vz), vlen, vw, vdir, rng, phase=vph)

    build(mb)

    # Walkable Collider 1: Anchored rear cliff heel (z >= +1.50 m so alcove in front is 100% open!)
    col_box('col_ledge_heel', (-5.45, -2.50, 1.50), (5.45, 4.80, 4.95))

    # Walkable Collider 2: Flat cantilevered plateau slab on top (y = 3.55 .. 4.86 m)
    # Leaves the entire shadowed alcove below (y = 0 .. 3.55 m) completely open for walking underneath!
    slab_col_pts = [
        (-5.75, 3.55,  2.75), ( 5.75, 3.55,  2.75),
        (-5.55, 3.55, -2.75), ( 5.55, 3.55, -2.75),
        (-2.65, 3.55, -5.25), ( 2.45, 3.55, -5.15),
        (-5.75, 4.86,  2.75), ( 5.75, 4.86,  2.75),
        (-5.55, 4.86, -2.75), ( 5.55, 4.86, -2.75),
        (-2.65, 4.86, -5.25), ( 2.45, 4.86, -5.15),
    ]
    col_piece('col_ledge_top', slab_col_pts)
    export_landmark_glb(outdir, 'cliff_overhang_ledge.glb')


# ---------------------------------------------------------------- 4. Coastal Sea Arch

def gen_coastal_sea_arch(outdir):
    """Monumental ~19 m span, ~14.5 m tall sea-carved limestone arch with open 8.5x8.3+ m underpass."""
    clear_scene()
    rng = random.Random(SEED + 251)
    mb = MB('CoastalSeaArch', seed=251)
    pts_l = []
    pts_r = []

    # --- Twin Flared Craggy Buttress Legs (rooted deep to y = -3.3 m, barnacle/sea-moss waterline!) ---
    # Sweeping organic natural rock curve flaring wide at the surf foot and curving robustly into the vaulted haunches!
    left_rings = [
        (-3.30, 3.65, 3.65, -7.85,  0.14),
        (-1.10, 3.25, 3.25, -7.55,  0.10),
        ( 1.20, 2.85, 2.90, -7.20,  0.06),
        ( 3.60, 2.55, 2.65, -6.78,  0.00),
        ( 6.00, 2.45, 2.55, -6.18, -0.04),
        ( 8.30, 2.65, 2.65, -5.35, -0.05),
        (10.20, 2.85, 2.65, -4.35, -0.03),
    ]
    pts_l += _sculpt_tidal_pillar(mb, left_rings, sides=7, rng=rng, mat='limestone', rot_y=0.24, twist=0.28)

    right_rings = [
        (-3.30, 3.70, 3.60,  7.90, -0.12),
        (-1.10, 3.30, 3.25,  7.60, -0.08),
        ( 1.20, 2.90, 2.90,  7.25, -0.04),
        ( 3.60, 2.60, 2.65,  6.80,  0.02),
        ( 6.00, 2.48, 2.55,  6.18,  0.04),
        ( 8.30, 2.68, 2.65,  5.35,  0.05),
        (10.20, 2.85, 2.65,  4.35,  0.03),
    ]
    pts_r += _sculpt_tidal_pillar(mb, right_rings, sides=7, rng=rng, mat='limestone', rot_y=-0.38, twist=-0.30)

    # Craggy outer sea-carved rock shoulders & flying ribs fusing the pillars organically into the arch crown
    pts_l += _sculpt_faceted_slab(
        mb, (-8.35, 0.55, 0.45), (2.35, 4.15, 2.55), 'limestone',
        C_LIME_PALE, C_LIME_WARM, C_LIME_SHADE, rng,
        subdiv=2, warp=0.24, strata=0.18, base_flare=0.26,
        rot_deg=(4, -22, 14), crag_ribs=5, rib_amp=0.16, tidal_moss=True,
    )
    pts_l += _sculpt_faceted_slab(
        mb, (-6.85, 6.20, -0.35), (2.05, 3.45, 2.35), 'limestone',
        C_LIME_PALE, C_LIME_WARM, C_LIME_MID, rng,
        subdiv=2, warp=0.22, strata=0.16,
        rot_deg=(-3, 18, -16), crag_ribs=5, rib_amp=0.15,
    )
    pts_r += _sculpt_faceted_slab(
        mb, (8.40, 0.70, -0.40), (2.35, 4.25, 2.55), 'limestone',
        C_LIME_PALE, C_LIME_WARM, C_LIME_SHADE, rng,
        subdiv=2, warp=0.24, strata=0.18, base_flare=0.26,
        rot_deg=(-4, 24, -13), crag_ribs=5, rib_amp=0.16, tidal_moss=True,
    )
    pts_r += _sculpt_faceted_slab(
        mb, (6.85, 6.35, 0.30), (2.05, 3.45, 2.35), 'limestone',
        C_LIME_PALE, C_LIME_WARM, C_LIME_MID, rng,
        subdiv=2, warp=0.22, strata=0.16,
        rot_deg=(3, -16, 16), crag_ribs=5, rib_amp=0.15,
    )

    # --- Chunky Multi-Keystone Vaulted Limestone Arch Span (central clearance ~8.6 m wide x ~8.4+ m high!) ---
    _sculpt_faceted_slab(
        mb, (-4.30, 10.15, 0.04), (2.25, 2.05, 2.38), 'limestone',
        C_LIME_PALE, C_LIME_WARM, C_LIME_SHADE, rng,
        subdiv=2, warp=0.17, strata=0.16, flat_top=0.58,
        rot_deg=(0, 10, -22), crag_ribs=5, rib_amp=0.12,
    )
    _sculpt_faceted_slab(
        mb, (4.30, 10.10, -0.04), (2.25, 2.05, 2.38), 'limestone',
        C_LIME_PALE, C_LIME_WARM, C_LIME_SHADE, rng,
        subdiv=2, warp=0.17, strata=0.16, flat_top=0.58,
        rot_deg=(0, -12, 22), crag_ribs=5, rib_amp=0.12,
    )

    # Inner left & right vaulted arch voussoirs (soffit stays cleanly above y >= 8.5 m!)
    _sculpt_faceted_slab(
        mb, (-2.18, 11.15, -0.05), (2.38, 2.02, 2.35), 'limestone',
        C_LIME_PALE, C_LIME_WARM, C_LIME_SHADE, rng,
        subdiv=2, warp=0.17, strata=0.16, flat_top=0.56,
        rot_deg=(2, -14, -11), crag_ribs=5, rib_amp=0.11,
    )
    _sculpt_faceted_slab(
        mb, (2.18, 11.12, 0.05), (2.38, 2.02, 2.35), 'limestone',
        C_LIME_PALE, C_LIME_WARM, C_LIME_SHADE, rng,
        subdiv=2, warp=0.17, strata=0.16, flat_top=0.56,
        rot_deg=(-2, 16, 11), crag_ribs=5, rib_amp=0.11,
    )

    # Hero massive central keystone spanning the vault apex (subdiv=3 for bold sculpted ceiling & walkable top)
    _sculpt_faceted_slab(
        mb, (0.0, 11.65, 0.0), (2.58, 2.15, 2.45), 'limestone_moss',
        C_LEDGE_MOSS, C_LIME_PALE, C_LIME_SHADE, rng,
        subdiv=3, warp=0.16, strata=0.16, flat_top=0.54,
        rot_deg=(0, 6, 0), crag_ribs=6, rib_amp=0.12, moss_cap=0.72,
    )

    # --- Crowned Mossy Turf Ledges & Asymmetric Sculpted Rock Spire Crest (peaking at y ≈ 14.5 m!) ---
    _sculpt_faceted_slab(
        mb, (-3.45, 11.82, 0.12), (2.40, 1.18, 2.18), 'limestone_moss',
        C_GRASS_SUN, C_LEDGE_MOSS, C_LIME_MID, rng,
        subdiv=2, warp=0.16, strata=0.12, flat_top=0.48,
        rot_deg=(0, -8, -9), crag_ribs=5, rib_amp=0.10, moss_cap=0.82,
    )
    _sculpt_faceted_slab(
        mb, (3.40, 11.78, -0.08), (2.45, 1.20, 2.18), 'limestone_moss',
        C_GRASS_SUN, C_LEDGE_MOSS, C_LIME_MID, rng,
        subdiv=2, warp=0.16, strata=0.12, flat_top=0.48,
        rot_deg=(0, 11, 9), crag_ribs=5, rib_amp=0.10, moss_cap=0.80,
    )

    # Bold asymmetric sea-carved limestone spire crest (broader flared crag peak + balancing shoulder)
    _sculpt_crag_rib(
        mb, (4.35, 10.75, 0.30), (4.60, 13.80, 0.15),
        1.85, 1.65, 0.62, 0.52, 6, rng,
        mat='limestone_moss', col_top=C_GRASS_SUN, col_mid=C_LIME_PALE, col_bot=C_LIME_WARM,
        twist=0.22, rings=5, apex_y=14.55,
    )
    _sculpt_faceted_slab(
        mb, (5.55, 11.60, 0.10), (1.35, 1.65, 1.30), 'limestone_moss',
        C_LEDGE_MOSS, C_LIME_PALE, C_LIME_MID, rng,
        subdiv=2, warp=0.20, strata=0.16, rot_deg=(4, 18, -14),
        crag_ribs=5, rib_amp=0.14, moss_cap=0.68,
    )
    _sculpt_crag_rib(
        mb, (-4.95, 10.35, -0.25), (-5.20, 12.25, -0.15),
        1.45, 1.30, 0.55, 0.48, 5, rng,
        mat='limestone_moss', col_top=C_LEDGE_MOSS, col_mid=C_LIME_PALE, col_bot=C_LIME_MID,
        twist=-0.16, rings=4, apex_y=12.90,
    )

    # --- 5 Hanging Jungle Vines framing the arch flanks & outer brows ---
    add_vine_drape(mb, (-4.25, 10.45, -2.18), 3.15, 0.36, (-0.18, 0.0, -1.0), rng, phase=0.12)
    add_vine_drape(mb, (-2.35, 11.25, -2.28), 2.10, 0.30, (-0.05, 0.0, -1.0), rng, phase=0.38)
    add_vine_drape(mb, ( 2.55, 11.20, -2.22), 2.30, 0.32, ( 0.08, 0.0, -1.0), rng, phase=0.64)
    add_vine_drape(mb, ( 4.35, 10.35,  2.18), 2.95, 0.35, ( 0.16, 0.0,  1.0), rng, phase=0.81)
    add_vine_drape(mb, (-3.15, 10.95,  2.22), 2.35, 0.30, (-0.10, 0.0,  1.0), rng, phase=0.52)

    build(mb)

    # 3 clean colliders preserving the ~8.6 m wide x ~8.4+ m high open central underpass!
    left_col_pts = [Vector((min(p.x, -4.30), p.y, p.z)) for p in pts_l if p.y <= 9.60]
    right_col_pts = [Vector((max(p.x, 4.30), p.y, p.z)) for p in pts_r if p.y <= 9.60]
    col_piece('col_arch_left', left_col_pts)
    col_piece('col_arch_right', right_col_pts)

    # Walkable arched bridge top collider: bottom stays strictly >= 8.90 m across central opening!
    bridge_col_pts = [
        (-5.45, 8.90, -2.35), ( 5.45, 8.90, -2.35),
        (-5.45, 8.90,  2.35), ( 5.45, 8.90,  2.35),
        (-5.45, 11.35, -2.12), ( 5.45, 11.35, -2.12),
        (-5.45, 11.35,  2.12), ( 5.45, 11.35,  2.12),
        (-2.25, 12.40, -2.12), ( 2.25, 12.40, -2.12),
        (-2.25, 12.40,  2.12), ( 2.25, 12.40,  2.12),
        ( 0.00, 12.75, -2.08), ( 0.00, 12.75,  2.08),
    ]
    col_piece('col_arch_bridge', bridge_col_pts)
    export_landmark_glb(outdir, 'coastal_sea_arch.glb')


# ---------------------------------------------------------------- 5. Volcanic Basalt Spire

def gen_volcanic_basalt_spire(outdir):
    """Dramatic ~16.5 m tall cluster of 13 leaning obsidian-basalt organ-pipe columns + magma fissures."""
    clear_scene()
    rng = random.Random(SEED + 271)
    mb = MB('VolcanicBasaltSpire', seed=271)
    col_pts = []

    # Central shattered obsidian-basalt crag core (deep base plunging solidly to y = -2.6 m)
    col_pts += sculpt_rock_mass(
        mb, (0.0, 1.30, 0.0), (3.45, 4.30, 3.35), 'basalt',
        C_BASALT_TOP, C_BASALT_MID, C_BASALT_DARK, rng,
        subdiv=2, warp=0.22, strata=0.14, base_flare=0.26,
        rot_deg=(0, 14, 0), crag_ribs=7, rib_amp=0.18,
    )
    # Upper fractured volcanic shoulder crag wedging the tall inner columns together
    col_pts += sculpt_rock_mass(
        mb, (-0.30, 6.10, 0.20), (2.05, 3.15, 1.95), 'basalt',
        C_BASALT_TOP, C_BASALT_MID, C_BASALT_DARK, rng,
        subdiv=2, warp=0.20, strata=0.12,
        rot_deg=(3, -22, -4), crag_ribs=6, rib_amp=0.16,
    )

    # 13 fractured hexagonal/pentagonal volcanic organ-pipe columns erupting at dynamic outward leans!
    column_specs = [
        # Hero central spire monolith (reaches y ≈ +16.5 m cleanly including sloped fracture crown!)
        ( 0.00, -2.60,  0.00, 18.55, 1.48, 6, -3.2, -2.4, True),

        # Inner ring: 5 tall jagged fractured columns leaning dynamically outward (6..9.5 deg)
        (-1.40, -2.60, -1.00, 16.05, 1.20, 6, -7.2, -5.5, True),
        ( 1.50, -2.60, -0.90, 14.95, 1.16, 5,  7.8, -4.8, True),
        ( 1.55, -2.60,  1.20, 14.05, 1.14, 6,  7.0,  6.5, True),
        (-0.22, -2.60,  1.75, 13.35, 1.10, 5, -1.8,  8.2, True),
        (-1.75, -2.60,  0.80, 14.55, 1.14, 6, -9.0,  3.8, True),

        # Outer ring: 7 shorter dramatic organ-pipe buttress columns leaning boldly outward (10..15 deg)
        ( 0.15, -2.60, -2.40, 11.20, 0.96, 6,  1.5, -12.5, True),
        (-2.40, -2.60, -1.75, 10.05, 0.90, 5, -11.5, -9.0, False),
        ( 2.50, -2.60, -1.60,  9.45, 0.88, 6,  12.0, -8.2, True),
        ( 2.85, -2.60,  0.42,  8.65, 0.86, 5,  14.2,  2.5, False),
        ( 2.05, -2.60,  2.30,  9.25, 0.90, 6,  9.8,  11.5, True),
        (-1.18, -2.60,  2.55,  8.35, 0.84, 5, -6.0,  13.2, False),
        (-2.85, -2.60,  0.15, 10.45, 0.94, 6, -13.8,  1.2, True),
    ]

    for bx, by, bz, h, rad, sides, tx, tz, seam in column_specs:
        c_bot = C_BASALT_DARK
        c_top = mix(C_BASALT_TOP, C_BASALT_HOT, 0.14 if seam else 0.04)
        sculpt_basalt_column(
            mb, (bx, by, bz), h, rad, sides, tx, tz,
            c_bot, c_top, rng, mat='basalt', magma_seam=seam,
        )
        col_pts.extend(_basalt_column_hull_pts((bx, by, bz), h, rad, sides, tx, tz))

    # Subtle recessed glowing molten magma fissure slivers tucked deep in the lower-mid cracks!
    fissure_specs = [
        ((-0.78, 0.70, -1.72), (-1.02, 5.85, -2.18), (-0.38, 0.0, -0.92), 0.17),
        (( 1.05, 0.65, -1.68), ( 1.42, 5.20, -2.10), ( 0.48, 0.0, -0.88), 0.16),
        (( 2.05, 0.75, -0.25), ( 2.48, 4.85, -0.35), ( 0.98, 0.0, -0.15), 0.16),
        (( 1.50, 0.80,  1.78), ( 1.88, 5.05,  2.22), ( 0.64, 0.0,  0.77), 0.15),
        ((-0.62, 0.75,  2.02), (-0.82, 4.80,  2.50), (-0.30, 0.0,  0.95), 0.15),
        ((-2.15, 0.85,  0.42), (-2.55, 5.45,  0.60), (-0.97, 0.0,  0.24), 0.17),
        ((-1.82, 1.15, -1.38), (-2.22, 6.20, -1.78), (-0.78, 0.0, -0.62), 0.15),
        (( 0.25, 1.85, -1.85), ( 0.35, 6.55, -2.42), ( 0.10, 0.0, -0.99), 0.14),
    ]
    for p0, p1, odir, w in fissure_specs:
        _add_magma_fissure(mb, p0, p1, odir, w, rng)

    build(mb)
    col_piece('col_basalt_spire', col_pts)
    export_landmark_glb(outdir, 'volcanic_basalt_spire.glb')


# ---------------------------------------------------------------- 6. Mossy Cliff Boulder Cluster

def gen_mossy_cliff_boulder_cluster(outdir):
    """Organic ~7.5 m wide coastal boulder cluster with 1 monumental mossy main boulder,
    2 flanking angular boulders, and 3 tilted fractured limestone shale slabs grounded to y = -1.4 m."""
    clear_scene()
    rng = random.Random(SEED + 293)
    mb = MB('MossyCliffBoulderCluster', seed=293)
    col_pts = []

    # 1. Monumental moss-capped main coastal boulder (~3.85 m tall, grounded deeply to y <= -1.45 m)
    col_pts += sculpt_rock_mass(
        mb, (-0.15, 1.12, 0.05), (2.25, 3.25, 2.05), 'limestone_moss',
        C_LEDGE_MOSS, C_LIME_WARM, C_LIME_SHADE, rng,
        subdiv=3, warp=0.22, strata=0.16, overhang=(0.20, -0.38),
        flat_top=0.74, base_flare=0.22, rot_deg=(3, 16, -5),
        crag_ribs=6, rib_amp=0.13, moss_cap=0.76,
    )
    # Sculpted sunlit mossy turf cap ridge crowning the main boulder right around y ≈ 3.85 m
    col_pts += sculpt_rock_mass(
        mb, (0.12, 3.18, -0.12), (1.42, 0.92, 1.32), 'limestone_moss',
        C_GRASS_SUN, C_LEDGE_MOSS, C_LIME_MID, rng,
        subdiv=2, warp=0.18, strata=0.12, flat_top=0.58,
        rot_deg=(-2, -12, 4), crag_ribs=5, rib_amp=0.10, moss_cap=0.86,
    )

    # 2. Two flanking angular weathered boulders spanning full cluster width ~7.5 m (grounded <= -1.4 m)
    col_pts += sculpt_rock_mass(
        mb, (-2.22, 0.22, 0.40), (1.45, 2.20, 1.42), 'limestone',
        C_LIME_PALE, C_LIME_MID, C_LIME_SHADE, rng,
        subdiv=2, warp=0.23, strata=0.19, base_flare=0.22,
        rot_deg=(-5, -34, 10), crag_ribs=5, rib_amp=0.17,
    )
    col_pts += sculpt_rock_mass(
        mb, (2.18, 0.32, -0.32), (1.45, 2.30, 1.40), 'limestone_moss',
        C_LEDGE_MOSS, C_LIME_WARM, C_LIME_SHADE, rng,
        subdiv=2, warp=0.23, strata=0.18, base_flare=0.22,
        rot_deg=(6, 44, -8), crag_ribs=5, rib_amp=0.16, moss_cap=0.48,
    )

    # 3. Three distinct tilted fractured limestone shale slabs wedged at the base (all grounded <= -1.4 m!)
    col_pts += _sculpt_shale_slab(
        mb, (-1.45, -0.05, -1.78), (2.75, 2.95, 0.72), (-32, -22, 14), rng,
        mat='limestone', col_top=C_LIME_PALE, col_mid=C_LIME_WARM, col_bot=C_LIME_SHADE,
        moss_cap=0.28,
    )
    col_pts += _sculpt_shale_slab(
        mb, (1.58, -0.10, -1.62), (2.55, 2.85, 0.68), (-36, 30, -16), rng,
        mat='limestone_moss', col_top=C_LIME_PALE, col_mid=C_LIME_MID, col_bot=C_LIME_SHADE,
        moss_cap=0.44,
    )
    col_pts += _sculpt_shale_slab(
        mb, (0.55, -0.05, 1.78), (2.95, 2.95, 0.76), (28, -14, -10), rng,
        mat='limestone', col_top=C_LIME_WARM, col_mid=C_LIME_MID, col_bot=C_LIME_SHADE,
        moss_cap=0.22,
    )

    build(mb)
    col_piece('col_boulder_cluster', col_pts)
    export_landmark_glb(outdir, 'mossy_cliff_boulder_cluster.glb')


GEOLOGY_GENERATORS = [
    gen_cliff_buttress_tall,
    gen_cliff_buttress_wide,
    gen_cliff_overhang_ledge,
    gen_coastal_sea_arch,
    gen_volcanic_basalt_spire,
    gen_mossy_cliff_boulder_cluster,
]
