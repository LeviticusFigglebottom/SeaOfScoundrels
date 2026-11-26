# Sea of Scoundrels: shared sculpted 3D island landmark geometry & 512x512 PBR texture toolkit.
# Imported by tools/blender/_landmarks_geology.py, _landmarks_setpieces.py, and gen_island_landmarks.py.
# Authored in Godot game coordinates (-Z forward, +Y up, +X starboard, metres) and converted to
# Blender's Z-up frame on mesh creation, matching tools/blender/gen_props.py.
import bpy, bmesh, os, math, random
import numpy as np
from contextlib import contextmanager
from math import sin, cos, pi, sqrt, atan2, radians
from mathutils import Vector, Matrix

SEED = 7331

# ---------------------------------------------------------------- colour helpers (sRGB hex -> linear)
def srgb(h):
    h = h.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c)

def mul(c, f):
    return (max(0.0, min(1.0, c[0] * f)), max(0.0, min(1.0, c[1] * f)), max(0.0, min(1.0, c[2] * f)))

def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] * (1.0 - t) + b[i] * t for i in range(3))

def jit(c, rng, amt=0.08, hue=0.025):
    f = 1.0 + rng.uniform(-amt, amt)
    return (
        max(0.0, min(1.0, c[0] * f * (1.0 + rng.uniform(-hue, hue)))),
        max(0.0, min(1.0, c[1] * f)),
        max(0.0, min(1.0, c[2] * f * (1.0 + rng.uniform(-hue, hue)))),
    )

# Painterly coastal rock, volcanic basalt, ruins, timber & accent palette (aligned with island_shader.gdshader)
C_LIME_PALE   = srgb('#f4e6c8')
C_LIME_WARM   = srgb('#e3be8c')
C_LIME_MID    = srgb('#d1ab7e')
C_LIME_SHADE  = srgb('#9b8265')
C_LIME_DARK   = srgb('#665848')
C_SEA_MOSS    = srgb('#395232')
C_LEDGE_MOSS  = srgb('#42782a')
C_GRASS_SUN   = srgb('#79b02c')
C_GRASS_DEEP  = srgb('#265e20')

C_BASALT_TOP  = srgb('#4c4546')
C_BASALT_MID  = srgb('#2c282d')
C_BASALT_DARK = srgb('#171519')
C_BASALT_HOT  = srgb('#9e3c16')
C_MAGMA_GLOW  = srgb('#ff6a18')

C_SKULL_BONE  = srgb('#e3d6b8')
C_SKULL_MID   = srgb('#b8a586')
C_SKULL_SHADE = srgb('#6e604f')
C_SKULL_CAV   = srgb('#1b1a1e')
C_SKULL_EYE   = srgb('#24f2c8')

C_TEMPLE_HI   = srgb('#b8ab92')
C_TEMPLE_MID  = srgb('#827a68')
C_TEMPLE_DARK = srgb('#4e4a41')
C_TEMPLE_GOLD = srgb('#c89c3a')

C_TIMBER_HI   = srgb('#a97748')
C_TIMBER_MID  = srgb('#7a502d')
C_TIMBER_DARK = srgb('#4b301c')
C_DRIFTWOOD   = srgb('#93826b')
C_PAINT_RED   = srgb('#a82b20')
C_PAINT_TEAL  = srgb('#1f6e72')
C_PAINT_CREAM = srgb('#dcc99a')
C_ROPE        = srgb('#c7a872')
C_IRON        = srgb('#34363e')
C_IRON_RUST   = srgb('#66402c')
C_BRASS       = srgb('#d9a644')
C_LANTERN_GL  = srgb('#ffbd54')
C_LEAF_DEEP   = srgb('#1e6926')
C_LEAF_SUN    = srgb('#84bd2c')

SU, SV = 1.0 / 2.2, 1.0 / 2.2

# ---------------------------------------------------------------- transforms (game coords)
def T(x, y=None, z=None):
    return Matrix.Translation(Vector(x) if y is None else Vector((x, y, z)))

def R(axis, deg):
    return Matrix.Rotation(radians(deg), 4, axis)

def S(x, y=None, z=None):
    if y is None:
        y = z = x
    return Matrix.Diagonal((x, y, z, 1.0))

M_Y2Z = R('X', 90)
M_Y2X = R('Z', -90)

def newell(pts):
    n = Vector((0, 0, 0))
    for i in range(len(pts)):
        a = pts[i]
        b = pts[(i + 1) % len(pts)]
        n.x += (a.y - b.y) * (a.z + b.z)
        n.y += (a.z - b.z) * (a.x + b.x)
        n.z += (a.x - b.x) * (a.y + b.y)
    return n

def smooth01(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)

# ---------------------------------------------------------------- mesh builder (MikkTSpace-safe)
class MB:
    """Procedural mesh builder with automatic n-gon fan triangulation for export_tangents=True."""
    def __init__(self, name, origin=(0, 0, 0), seed=0, yaw=0.0):
        self.name = name
        self.origin = Vector(origin)
        self.yaw = yaw
        self.verts = []
        self.faces = []
        self.fmat = []
        self.fsm = []
        self.fcol = []
        self.fuv = []
        self.fuv2 = []
        self.has_uv2 = False
        self.stack = [Matrix.Identity(4)]
        self.flip = False
        self.rng = random.Random(SEED * 7919 + seed + sum(ord(c) for c in name))
        self.off = (0.0, 0.0)
        self.uv_scale = (SU, SV)

    def push(self, M):
        self.stack.append(self.stack[-1] @ M)
        self.flip = self.stack[-1].to_3x3().determinant() < 0

    def pop(self):
        self.stack.pop()
        self.flip = self.stack[-1].to_3x3().determinant() < 0

    def newoff(self):
        self.off = (self.rng.random(), self.rng.random())
        return self.off

    def v(self, p):
        self.verts.append(self.stack[-1] @ Vector(p))
        return len(self.verts) - 1

    def _emit_poly(self, idx, mat, col, uvs, smooth, uv2):
        self.faces.append(tuple(idx))
        self.fmat.append(mat)
        self.fsm.append(smooth)
        self.fcol.append(col)
        self.fuv.append(uvs)
        if uv2 is not None:
            self.has_uv2 = True
            self.fuv2.append(uv2)
        else:
            self.fuv2.append(None)

    def f(self, idx, mat, col, uvs, smooth=False, uv2=None):
        if len(set(idx)) < 3:
            return
        if self.flip:
            idx = idx[::-1]
            uvs = uvs[::-1]
            if isinstance(col, list):
                col = col[::-1]
            if uv2 is not None:
                uv2 = uv2[::-1]
        # MikkTSpace tangents only support triangles & quads; fan-triangulate any 5+ n-gon cleanly.
        if len(idx) <= 4:
            self._emit_poly(idx, mat, col, uvs, smooth, uv2)
        else:
            for k in range(1, len(idx) - 1):
                tri_i = [idx[0], idx[k], idx[k + 1]]
                tri_u = [uvs[0], uvs[k], uvs[k + 1]]
                tri_c = [col[0], col[k], col[k + 1]] if isinstance(col, list) else col
                tri_u2 = [uv2[0], uv2[k], uv2[k + 1]] if uv2 is not None else None
                if len(set(tri_i)) == 3:
                    self._emit_poly(tri_i, mat, tri_c, tri_u, smooth, tri_u2)

    def fp(self, pts, mat, col, grain=None, inside=None, smooth=False, uv2=None, uv_scale=None):
        pts = [Vector(p) for p in pts]
        n = newell(pts)
        if n.length < 1e-10:
            return
        n.normalize()
        if inside is not None:
            c = sum(pts, Vector()) / len(pts)
            if n.dot(c - Vector(inside)) < 0:
                pts.reverse()
                n = -n
                if isinstance(col, list):
                    col = col[::-1]
                if uv2 is not None:
                    uv2 = uv2[::-1]
        g = Vector(grain) if grain is not None else Vector((0, 0, 1))
        gu = g - n * g.dot(n)
        if gu.length < 0.35:
            a = Vector((1, 0, 0)) if abs(n.x) < 0.8 else Vector((0, 1, 0))
            gu = a - n * a.dot(n)
        gu.normalize()
        gv = n.cross(gu)
        o = self.off
        su, sv = uv_scale if uv_scale is not None else self.uv_scale
        uvs = [(p.dot(gu) * su + o[0], p.dot(gv) * sv + o[1]) for p in pts]
        self.f([self.v(p) for p in pts], mat, col, uvs, smooth, uv2=uv2)

    def tris(self):
        return sum(len(f) - 2 for f in self.faces)

@contextmanager
def xf(mb, M):
    mb.push(M)
    try:
        yield
    finally:
        mb.pop()

# ---------------------------------------------------------------- primitives & sculptural builders
def cbox(mb, c, size, mat, col, ch=0.025, grain=None, M=None, skip=()):
    h = [size[0] * 0.5, size[1] * 0.5, size[2] * 0.5]
    ch = min(ch, min(h) * 0.42)
    if grain is None:
        a = max(range(3), key=lambda i: h[i])
        grain = [0, 0, 0]
        grain[a] = 1
    mb.newoff()
    X = T(c) @ M if M is not None else T(c)
    names = 'xyz'
    with xf(mb, X):
        O = Vector((0, 0, 0))
        def fv(a, s, s1, s2):
            p = [0, 0, 0]
            b = (a + 1) % 3
            cc = (a + 2) % 3
            p[a] = s * h[a]
            p[b] = s1 * (h[b] - ch)
            p[cc] = s2 * (h[cc] - ch)
            return Vector(p)
        for a in range(3):
            for s in (-1, 1):
                if (('+' if s > 0 else '-') + names[a]) in skip:
                    continue
                shade = 1.0 if (a == 1 and s > 0) else (0.82 if (a == 1 and s < 0) else 0.95)
                mb.fp([fv(a, s, -1, -1), fv(a, s, 1, -1), fv(a, s, 1, 1), fv(a, s, -1, 1)],
                      mat, mul(col, shade), grain, O)
        if ch > 1e-5:
            dk = mul(col, 0.84)
            def on(a, sa, b, sb, sc):
                cc = 3 - a - b
                p = [0, 0, 0]
                p[a] = sa * h[a]
                p[b] = sb * (h[b] - ch)
                p[cc] = sc * (h[cc] - ch)
                return Vector(p)
            for a in range(3):
                for b in range(a + 1, 3):
                    for sa in (-1, 1):
                        for sb in (-1, 1):
                            mb.fp([on(a, sa, b, sb, -1), on(a, sa, b, sb, 1),
                                   on(b, sb, a, sa, 1), on(b, sb, a, sa, -1)], mat, dk, grain, O)
            for sx in (-1, 1):
                for sy in (-1, 1):
                    for sz in (-1, 1):
                        mb.fp([
                            Vector((sx * h[0], sy * (h[1] - ch), sz * (h[2] - ch))),
                            Vector((sx * (h[0] - ch), sy * h[1], sz * (h[2] - ch))),
                            Vector((sx * (h[0] - ch), sy * (h[1] - ch), sz * h[2])),
                        ], mat, dk, grain, O)

def sculpt_stone_block(mb, center, size, mat, col, rng, chip=0.05, M=None, moss_col=None):
    """Hand-hewn weathered stone masonry block with chipped corners & optional mossy top face."""
    hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    c_amt = min(chip, min(hx, hy, hz) * 0.35)
    X = T(center) @ (M if M is not None else Matrix.Identity(4))
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        p = v.co
        # Taper and chip each corner deterministically for ancient hand-cut look
        sx = 1.0 + rng.uniform(-0.04, 0.04)
        sy = 1.0 + rng.uniform(-0.04, 0.04)
        sz = 1.0 + rng.uniform(-0.04, 0.04)
        v.co = Vector((p.x * size[0] * sx, p.y * size[1] * sy, p.z * size[2] * sz))
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=c_amt, segments=1, affect='EDGES', clamp_overlap=True)
    for v in bm.verts:
        v.co += Vector((rng.uniform(-c_amt * 0.3, c_amt * 0.3),
                        rng.uniform(-c_amt * 0.2, c_amt * 0.2),
                        rng.uniform(-c_amt * 0.3, c_amt * 0.3)))
    bm.faces.ensure_lookup_table()
    mb.newoff()
    with xf(mb, X):
        for f in bm.faces:
            pts = [v.co.copy() for v in f.verts]
            fn = newell(pts)
            if fn.length < 1e-8:
                continue
            fn.normalize()
            if fn.y > 0.65 and moss_col is not None:
                c_face = mix(col, moss_col, rng.uniform(0.32, 0.72))
            elif fn.y > 0.55:
                c_face = mul(col, 1.05)
            elif fn.y < -0.45:
                c_face = mul(col, 0.74)
            else:
                c_face = mul(col, rng.uniform(0.88, 1.02))
            mb.fp(pts, mat, jit(c_face, rng, 0.04, 0.015), (1, 0, 0), Vector((0, 0, 0)), smooth=False)
    bm.free()

def loft(mb, secs, mat, col, closed=True, caps=(True, True), mode='flat', scols=None, flip=None, suv2=None):
    secs = [[Vector(p) for p in s] for s in secs]
    n = len(secs)
    k = len(secs[0])
    cents = [sum(s, Vector()) / k for s in secs]
    L = [0.0]
    for i in range(1, n):
        L.append(L[-1] + (cents[i] - cents[i - 1]).length)
    ne = k if closed else k - 1
    W = []
    for s in secs:
        w = [0.0]
        for j in range(1, k + 1):
            w.append(w[-1] + (s[j % k] - s[j - 1]).length)
        W.append(w)
    if flip is None:
        vote = 0.0
        for i in range(n - 1):
            cc = (cents[i] + cents[i + 1]) * 0.5
            for j in range(ne):
                q = [secs[i][j], secs[i][(j + 1) % k], secs[i + 1][(j + 1) % k], secs[i + 1][j]]
                vote += newell(q).dot(sum(q, Vector()) * 0.25 - cc)
        flip = vote < 0
    o = mb.newoff()
    su, sv = mb.uv_scale
    def uv(i, j):
        return (L[i] * su + o[0], W[i][j] * sv + o[1])
    shared = mode in ('flat', 'smooth')
    sm = mode != 'flat'
    ids = [[mb.v(p) for p in s] for s in secs] if shared else None
    for j in range(ne):
        j1 = (j + 1) % k
        if not shared:
            e0 = [mb.v(s[j]) for s in secs]
            e1 = [mb.v(s[j1]) for s in secs]
        for i in range(n - 1):
            if shared:
                idx = [ids[i][j], ids[i][j1], ids[i + 1][j1], ids[i + 1][j]]
            else:
                idx = [e0[i], e1[i], e1[i + 1], e0[i + 1]]
            uvs = [uv(i, j), uv(i, j + 1), uv(i + 1, j + 1), uv(i + 1, j)]
            c = scols[i] if scols else col
            u2 = [suv2[i], suv2[i], suv2[i + 1], suv2[i + 1]] if suv2 else None
            if flip:
                idx = idx[::-1]
                uvs = uvs[::-1]
                if u2:
                    u2 = u2[::-1]
            keep = []
            kuv = []
            ku2 = [] if u2 else None
            for q_idx in range(len(idx)):
                a = idx[q_idx]
                if all((mb.verts[a] - mb.verts[q]).length > 1e-6 for q in keep):
                    keep.append(a)
                    kuv.append(uvs[q_idx])
                    if u2:
                        ku2.append(u2[q_idx])
            if len(keep) >= 3:
                mb.f(keep, mat, c, kuv, sm, uv2=ku2)
    if closed and caps[0] and n > 1:
        mb.fp(secs[0], mat, scols[0] if scols else col, cents[1] - cents[0], cents[1],
              uv2=[suv2[0]] * k if suv2 else None)
    if closed and caps[1] and n > 1:
        cap_col = scols[-2] if (scols and len(scols) >= 2) else (scols[-1] if scols else col)
        mb.fp(secs[-1], mat, cap_col, cents[-1] - cents[-2], cents[-2],
              uv2=[suv2[-1]] * k if suv2 else None)

def lathe(mb, prof, segs, mat, col, smooth=True, sp=False, colfn=None, axial=True):
    o = mb.newoff()
    su, sv = mb.uv_scale
    rmax = max(r for r, _ in prof)
    pl = [0.0]
    for i in range(1, len(prof)):
        pl.append(pl[-1] + sqrt((prof[i][0] - prof[i - 1][0]) ** 2 + (prof[i][1] - prof[i - 1][1]) ** 2))
    def ring(r, y):
        if r < 1e-6:
            return [mb.v((0, y, 0))] * segs
        return [mb.v((r * cos(2 * pi * k / segs), y, r * sin(2 * pi * k / segs))) for k in range(segs)]
    def uv(i, k):
        ua = 2 * pi * k / segs * rmax
        return (pl[i] * su + o[0], ua * sv + o[1]) if axial else (ua * su + o[0], pl[i] * sv + o[1])
    shared = [ring(r, y) for r, y in prof] if sp else None
    for i in range(len(prof) - 1):
        (r0, y0), (r1, y1) = prof[i], prof[i + 1]
        if (r0 < 1e-6 and r1 < 1e-6) or (abs(r0 - r1) < 1e-9 and abs(y0 - y1) < 1e-9):
            continue
        a = shared[i] if sp else ring(r0, y0)
        b = shared[i + 1] if sp else ring(r1, y1)
        for k in range(segs):
            k1 = (k + 1) % segs
            idx = [a[k], b[k], b[k1], a[k1]]
            uvs = [uv(i, k), uv(i + 1, k), uv(i + 1, k + 1), uv(i, k + 1)]
            if abs(y0 - y1) < 1e-6:
                uvs = [(r * cos(2 * pi * kk / segs) * su + o[0], r * sin(2 * pi * kk / segs) * sv + o[1])
                       for r, kk in ((r0, k), (r1, k), (r1, k + 1), (r0, k + 1))]
            if r0 < 1e-6:
                idx = idx[:3]
                uvs = uvs[:3]
            elif r1 < 1e-6:
                idx = [idx[0], idx[1], idx[3]]
                uvs = [uvs[0], uvs[1], uvs[3]]
            mb.f(idx, mat, colfn(i, k) if colfn else col, uvs, smooth)

def tube(mb, path, rad, sides, mat, col, caps=(True, True), mode='flat', scols=None, suv2=None):
    path = [Vector(p) for p in path]
    n = len(path)
    rads = rad if isinstance(rad, (list, tuple)) else [rad] * n
    secs = []
    nrm = None
    for i in range(n):
        t = (path[min(i + 1, n - 1)] - path[max(i - 1, 0)]).normalized()
        if nrm is None:
            ref = Vector((0, 1, 0)) if abs(t.y) < 0.9 else Vector((1, 0, 0))
            nrm = ref - t * ref.dot(t)
        else:
            nrm = nrm - t * nrm.dot(t)
        nrm.normalize()
        bn = t.cross(nrm)
        secs.append([path[i] + (nrm * cos(2 * pi * k / sides) + bn * sin(2 * pi * k / sides)) * rads[i] for k in range(sides)])
    loft(mb, secs, mat, col, True, caps, mode, scols=scols, suv2=suv2)

def cyl(mb, r, y0, y1, segs, mat, col, smooth=False, bev=0.0, r1=None):
    r1 = r if r1 is None else r1
    if bev > 0:
        prof = [(0, y0), (max(0.01, r - bev), y0), (r, y0 + bev), (r1, y1 - bev), (max(0.01, r1 - bev), y1), (0, y1)]
    else:
        prof = [(0, y0), (r, y0), (r1, y1), (0, y1)]
    lathe(mb, prof, segs, mat, col, smooth)

def torus(mb, Rr, r, segs, psegs, mat, col, smooth=True):
    prof = [(Rr + r * cos(-pi * 0.5 + 2 * pi * i / psegs), r * sin(-pi * 0.5 + 2 * pi * i / psegs)) for i in range(psegs)]
    prof.append(prof[0])
    lathe(mb, prof, segs, mat, col, smooth, True)

def rope_coil(mb, center, radius=0.22, turns=3, r=0.026):
    for i in range(turns):
        rr = radius * (1.0 - 0.16 * i)
        with xf(mb, T(center[0], center[1] + r * (1.0 + i * 1.7), center[2])):
            torus(mb, rr, r, 10, 6, 'rope', mul(C_ROPE, 0.92 + 0.08 * (i % 2)), True)

def build_lantern_geom(mb, center, scale=1.0, hanging=True):
    """Chunky forged-iron & brass coastal lantern with warm glowing glass core."""
    cx, cy, cz = center
    s = scale
    with xf(mb, T(cx, cy, cz)):
        cyl(mb, 0.14 * s, -0.20 * s, -0.14 * s, 6, 'iron', C_IRON, False, 0.01 * s, 0.16 * s)
        cyl(mb, 0.16 * s, 0.15 * s, 0.22 * s, 6, 'iron', C_IRON, False, 0.01 * s, 0.06 * s)
        cyl(mb, 0.055 * s, 0.22 * s, 0.28 * s, 6, 'brass', C_BRASS, False, 0.005 * s, 0.03 * s)
        cyl(mb, 0.115 * s, -0.14 * s, 0.15 * s, 6, 'glass', C_LANTERN_GL, False, 0.0, 0.125 * s)
        for k in range(4):
            ang = k * pi * 0.5 + pi * 0.25
            rx = 0.135 * s * cos(ang)
            rz = 0.135 * s * sin(ang)
            cbox(mb, (rx, 0.005 * s, rz), (0.026 * s, 0.30 * s, 0.026 * s), 'brass', C_BRASS, 0.004 * s)
        if hanging:
            with xf(mb, T(0, 0.31 * s, 0) @ M_Y2Z):
                torus(mb, 0.048 * s, 0.013 * s, 8, 5, 'iron', C_IRON, False)

def sculpt_rock_mass(mb, center, radii, mat, col_top, col_mid, col_bot, rng,
                     subdiv=2, warp=0.26, strata=0.16, overhang=(0.0, 0.0),
                     flat_top=0.0, base_flare=0.0, rot_deg=(0, 0, 0),
                     crag_ribs=5, rib_amp=0.12, moss_cap=0.0):
    """Sculpted chunky faceted 3D coastal cliff / rock formation with true overhangs & strata ledges."""
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
        # Angular vertical cliff fracture ribs
        ang = atan2(p.z, p.x)
        d += rib_amp * (0.65 * cos(ang * crag_ribs + ph[6] + p.y * 0.7) + 0.35 * sin(ang * (crag_ribs + 2) + ph[7]))
        # Stepped horizontal sedimentary strata benches (sawtooth-like undercut ledges!)
        st_phase = p.y * 5.6 + ph[5] + 0.65 * sin(p.x * 2.3 + p.z * 2.1)
        d += strata * (sin(st_phase) + 0.35 * sin(st_phase * 2.0 + 0.8))
        # Optional flared base skirt so rock buries solidly into steep terrain
        if base_flare != 0.0 and p.y < 0.0:
            d += base_flare * (-p.y) * (-p.y)
        # Flatten underside gently
        if p.y < -0.62:
            p.y = -0.62 + (p.y + 0.62) * 0.42
        # Optional walkable flat terrace crown
        if flat_top > 0.0 and p.y > flat_top:
            p.y = flat_top + (p.y - flat_top) * 0.16
        px = p.x * radii[0] * d
        py = p.y * radii[1] * (0.94 + 0.06 * d)
        pz = p.z * radii[2] * d
        # True 3D overhang cantilever: upper half juts outward in local X/Z!
        oh_t = smooth01((p.y + 0.35) / 1.25)
        px += overhang[0] * oh_t * oh_t
        pz += overhang[1] * oh_t * oh_t
        v.co = Vector((px, py, pz))

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
            h01 = smooth01((fc.y / max(radii[1], 0.1) + 0.85) * 0.56)
            if fn.y > 0.52:
                top_c = mix(col_top, C_LEDGE_MOSS, moss_cap) if moss_cap > 0.01 else col_top
                base = mix(col_mid, top_c, smooth01((fn.y - 0.52) / 0.44))
            elif fn.y < -0.18:
                # Deep overhang underside occlusion darkening!
                base = mul(col_bot, 0.62)
            else:
                base = mix(col_bot, col_mid, h01)
            st_tint = 0.90 + 0.14 * sin(fc.y * 1.45 + ph[8])
            c = jit(mul(base, st_tint), rng, 0.055, 0.02)
            mb.fp(pts, mat, c, (1, 0, 0), Vector((0, 0, 0)), smooth=False)
            for p in pts:
                out_pts.append(X @ p)
    bm.free()
    return out_pts

def sculpt_basalt_column(mb, base_pos, height, radius, sides, tilt_x, tilt_z,
                         col_bot, col_top, rng, mat='basalt', magma_seam=False):
    """Beveled polygonal volcanic basalt organ-pipe column with stepped fractured crown."""
    bx, by, bz = base_pos
    rings = 5
    secs = []
    scols = []
    rot0 = rng.uniform(0.0, TAU if 'TAU' in globals() else 6.28318)
    for ri in range(rings):
        t = ri / float(rings - 1)
        y = by + t * height
        # Subtle fracture taper & step pinch
        rad_t = radius * (1.06 - 0.16 * t)
        if ri == rings - 1:
            rad_t *= 0.82
        ox = bx + sin(radians(tilt_x)) * t * height
        oz = bz + sin(radians(tilt_z)) * t * height
        ring = []
        for k in range(sides):
            ang = rot0 + 2.0 * pi * k / sides
            rk = rad_t * (0.94 + 0.12 * sin(ang * 2.0 + ri * 1.3))
            # Slightly sloped fractured top facet
            yk = y + (radius * 0.38 * cos(ang - rot0) if ri >= rings - 2 else 0.0)
            ring.append(Vector((ox + rk * cos(ang), yk, oz + rk * sin(ang))))
        secs.append(ring)
        c_step = mix(col_bot, col_top, t)
        if magma_seam and ri == 1:
            c_step = mix(c_step, C_BASALT_HOT, 0.42)
        scols.append(jit(c_step, rng, 0.06, 0.015))
    loft(mb, secs, mat, col_top, closed=True, caps=(True, True), mode='flat', scols=scols)

def add_vine_drape(mb, anchor, length, width, out_dir, rng, phase=0.0):
    """Hanging jungle vine/moss cluster with UV2 wind bend weights (0 at root -> 1 at tip)."""
    a = Vector(anchor)
    od = Vector(out_dir)
    od.y = 0.0
    if od.length < 1e-4:
        od = Vector((0, 0, -1))
    od.normalize()
    side = Vector((-od.z, 0.0, od.x))
    segs = 4
    prev_l = prev_r = None
    for i in range(segs + 1):
        t = i / float(segs)
        w = width * (0.55 + 0.45 * sin(t * pi)) * (1.0 - 0.35 * t)
        sway = sin(t * 2.6 + phase * 6.28) * 0.14
        ctr = a + od * (0.12 + 0.24 * t) + side * sway + Vector((0.0, -length * t, 0.0))
        pl = ctr - side * w
        pr = ctr + side * w
        if prev_l is not None:
            t0 = (i - 1) / float(segs)
            c0 = mix(C_LEAF_DEEP, C_LEAF_SUN, t0 * 0.65)
            c1 = mix(C_LEAF_DEEP, C_LEAF_SUN, t * 0.85)
            uvs = [(0.0, t0), (1.0, t0), (1.0, t), (0.0, t)]
            uv2 = [(t0 * 0.85, phase), (t0 * 0.85, phase), (t * 0.95, phase), (t * 0.95, phase)]
            idx = [mb.v(prev_l), mb.v(prev_r), mb.v(pr), mb.v(pl)]
            mb.f(idx, 'foliage', [c0, c0, c1, c1], uvs, smooth=False, uv2=uv2)
        prev_l, prev_r = pl, pr

# ---------------------------------------------------------------- 512x512 Seamless PBR Texture Synthesis
def tile_noise(rs, w, h, gx, gy):
    g = rs.rand(gy, gx).astype(np.float32)
    ys = np.arange(h, dtype=np.float32) * gy / h
    xs = np.arange(w, dtype=np.float32) * gx / w
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    fy = ys - y0
    fx = xs - x0
    fy = fy * fy * (3.0 - 2.0 * fy)
    fx = fx * fx * (3.0 - 2.0 * fx)
    y1 = (y0 + 1) % gy
    x1 = (x0 + 1) % gx
    a = g[np.ix_(y0, x0)]
    b = g[np.ix_(y0, x1)]
    c = g[np.ix_(y1, x0)]
    d = g[np.ix_(y1, x1)]
    FX = fx[None, :]
    FY = fy[:, None]
    return (a * (1.0 - FX) + b * FX) * (1.0 - FY) + (c * (1.0 - FX) + d * FX) * FY

def tile_fbm(rs, w, h, octaves):
    acc = np.zeros((h, w), dtype=np.float32)
    wsum = 0.0
    for gx, gy, amp in octaves:
        acc += tile_noise(rs, w, h, gx, gy) * amp
        wsum += amp
    return acc / max(wsum, 1e-6)

def tile_ridged(rs, w, h, gx, gy):
    n = tile_noise(rs, w, h, gx, gy)
    r = 1.0 - np.abs(n * 2.0 - 1.0)
    return r * r

def height_to_normal(height_map, strength=3.2):
    """Convert seamless scalar heightfield (0..1) into OpenGL (+Y up) tangent-space normal RGB (0..1)."""
    dh_dx = (np.roll(height_map, -1, axis=1) - np.roll(height_map, 1, axis=1)) * 0.5 * strength
    dh_dy = (np.roll(height_map, -1, axis=0) - np.roll(height_map, 1, axis=0)) * 0.5 * strength
    nx = -dh_dx
    # Note: image row 0 in Blender is bottom (+V), so positive row derivative is +Y tangent!
    ny = -dh_dy
    nz = np.ones_like(height_map, dtype=np.float32)
    inv_l = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz + 1e-8)
    return np.stack([nx * inv_l * 0.5 + 0.5, ny * inv_l * 0.5 + 0.5, nz * inv_l * 0.5 + 0.5], axis=-1)

def make_image(name, arr, non_color=False):
    h, w = arr.shape[:2]
    rgba = np.ones((h, w, 4), dtype=np.float32)
    if arr.ndim == 2:
        v = np.clip(arr, 0.0, 1.0)
        rgba[..., 0] = v
        rgba[..., 1] = v
        rgba[..., 2] = v
    else:
        rgba[..., :3] = np.clip(arr, 0.0, 1.0)
    img = bpy.data.images.new(name, w, h, alpha=False)
    if non_color:
        img.colorspace_settings.name = 'Non-Color'
    img.pixels.foreach_set(rgba.ravel())
    img.file_format = 'PNG'
    img.pack()
    return img

def synth_limestone_pbr(rs, size=512, mossy=False, bone_carved=False):
    """512x512 seamless painterly sedimentary limestone (albedo, normal, roughness)."""
    w = h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32) / float(size)
    macro = tile_fbm(rs, w, h, [(4, 4, 0.55), (8, 8, 0.30), (16, 16, 0.15)])
    med = tile_fbm(rs, w, h, [(12, 12, 0.50), (24, 24, 0.32), (48, 48, 0.18)])
    fine = tile_fbm(rs, w, h, [(32, 32, 0.55), (64, 64, 0.30), (128, 128, 0.15)])

    # Domain-warped horizontal geological strata benches + fractured overhangs
    warp_y = (yy + (macro - 0.5) * 0.14 + (med - 0.5) * 0.05) % 1.0
    strata = 0.5 + 0.5 * np.sin(warp_y * 2.0 * pi * (7.0 if not bone_carved else 5.0) + macro * 2.6)
    strata2 = 0.5 + 0.5 * np.sin(warp_y * 2.0 * pi * 17.0 - med * 3.1)
    bench = np.clip(strata * 0.65 + strata2 * 0.35, 0.0, 1.0)

    # Vertical weathering cracks & fracture seams
    crack_a = tile_ridged(rs, w, h, 10, 4)
    crack_b = tile_ridged(rs, w, h, 22, 8)
    cracks = np.clip((crack_a * 0.62 + crack_b * 0.38 - 0.62) * 3.2, 0.0, 1.0)

    # Chipped limestone pores & painterly chisel brushwork
    chisel = tile_noise(rs, w, h, 18, 36) * 0.6 + tile_noise(rs, w, h, 40, 20) * 0.4
    pores = np.clip((0.24 - fine) * 4.5, 0.0, 1.0)

    height = (0.48 * bench + 0.24 * macro + 0.18 * chisel + 0.10 * fine
              - 0.34 * cracks - 0.14 * pores)
    height = np.clip(height, 0.0, 1.0)

    # Neutral-warm multiplicative albedo (tinted cleanly by vertex colors!)
    val = 0.80 + 0.18 * (bench - 0.5) + 0.14 * (macro - 0.5) + 0.08 * (chisel - 0.5) - 0.24 * cracks - 0.08 * pores
    r = np.clip(val * (1.03 if not bone_carved else 1.02), 0.18, 1.0)
    g = np.clip(val * (0.99 if not bone_carved else 1.00), 0.18, 1.0)
    b = np.clip(val * (0.92 if not bone_carved else 0.96), 0.16, 1.0)

    # Warm terracotta mineral streaks in strata seams
    ochre_m = np.clip((0.55 - bench) * 1.8 * macro, 0.0, 1.0) * (0.18 if bone_carved else 0.28)
    r = np.clip(r * (1.0 + ochre_m * 0.22), 0.0, 1.0)
    g = np.clip(g * (1.0 - ochre_m * 0.05), 0.0, 1.0)
    b = np.clip(b * (1.0 - ochre_m * 0.24), 0.0, 1.0)

    rough = np.clip(0.84 - 0.12 * bench + 0.14 * cracks + 0.08 * pores + 0.06 * (1.0 - fine), 0.58, 0.98)

    if mossy:
        moss_mask = np.clip((macro * 0.55 + (1.0 - bench) * 0.35 + cracks * 0.35 - 0.48) * 3.0, 0.0, 1.0)
        r = r * (1.0 - moss_mask * 0.42) + 0.34 * moss_mask * 0.42
        g = g * (1.0 - moss_mask * 0.30) + 0.62 * moss_mask * 0.30
        b = b * (1.0 - moss_mask * 0.48) + 0.24 * moss_mask * 0.48
        rough = np.clip(rough + moss_mask * 0.10, 0.62, 0.98)
        height = np.clip(height + moss_mask * 0.08 * fine, 0.0, 1.0)

    albedo = np.stack([r, g, b], axis=-1)
    normal = height_to_normal(height, strength=4.6 if not bone_carved else 5.2)
    return albedo, normal, rough

def synth_basalt_pbr(rs, size=512):
    """512x512 seamless volcanic columnar basalt with vertical cooling cracks & lava vesicles."""
    w = h = size
    macro = tile_fbm(rs, w, h, [(6, 4, 0.55), (14, 8, 0.30), (28, 16, 0.15)])
    vert_col = tile_ridged(rs, w, h, 16, 3) * 0.6 + tile_ridged(rs, w, h, 32, 6) * 0.4
    cross_cr = tile_ridged(rs, w, h, 6, 14)
    pits = tile_noise(rs, w, h, 64, 64)
    vesicles = np.clip((0.26 - pits) * 4.5, 0.0, 1.0)

    fissures = np.clip((vert_col * 0.72 + cross_cr * 0.28 - 0.58) * 3.4, 0.0, 1.0)
    height = np.clip(0.56 + 0.26 * (macro - 0.5) + 0.16 * (1.0 - vert_col) - 0.38 * fissures - 0.18 * vesicles, 0.0, 1.0)

    val = np.clip(0.78 + 0.22 * (macro - 0.5) - 0.32 * fissures - 0.14 * vesicles, 0.22, 1.0)
    r = np.clip(val * 0.98 + fissures * 0.08 * macro, 0.0, 1.0)
    g = np.clip(val * 0.96, 0.0, 1.0)
    b = np.clip(val * 1.02, 0.0, 1.0)
    albedo = np.stack([r, g, b], axis=-1)
    # Obsidian-basalt fracture facets have subtle glassy sheen vs rough vesicular pits
    rough = np.clip(0.68 + 0.24 * fissures + 0.18 * vesicles - 0.12 * macro, 0.44, 0.97)
    normal = height_to_normal(height, strength=5.4)
    return albedo, normal, rough

def synth_temple_stone_pbr(rs, size=512):
    """512x512 seamless weathered carved ashlar masonry blocks with moss seams & ancient glyph relief."""
    w = h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32) / float(size)
    rows = 6
    cols = 4
    row_id = np.floor(yy * rows)
    row_f = (yy * rows) % 1.0
    col_shift = (row_id % 2.0) * 0.5
    col_f = ((xx * cols) + col_shift) % 1.0

    # Irregular weathered mortar seams
    wob = (tile_fbm(rs, w, h, [(12, 12, 0.6), (28, 28, 0.4)]) - 0.5) * 0.045
    hy_edge = np.minimum(row_f, 1.0 - row_f) + wob
    hx_edge = np.minimum(col_f, 1.0 - col_f) + wob
    mortar_h = np.clip(1.0 - hy_edge / 0.065, 0.0, 1.0)
    mortar_v = np.clip(1.0 - hx_edge / 0.045, 0.0, 1.0)
    mortar = np.maximum(mortar_h, mortar_v)

    stone_grain = tile_fbm(rs, w, h, [(8, 8, 0.45), (24, 24, 0.35), (64, 64, 0.20)])
    chips = tile_ridged(rs, w, h, 18, 18)
    # Subtle carved wave-spiral relief band inside alternating stone courses
    glyph = np.sin((col_f * 2.0 * pi * 2.0) + np.sin(row_f * 2.0 * pi) * 1.4) * 0.5 + 0.5
    glyph_band = ((row_f > 0.28) & (row_f < 0.72) & (col_f > 0.12) & (col_f < 0.88)).astype(np.float32)
    glyph_groove = glyph_band * np.clip((glyph - 0.74) * 3.6, 0.0, 1.0) * 0.14

    height = np.clip(0.68 + 0.18 * (stone_grain - 0.5) - 0.46 * mortar - 0.12 * np.clip(chips - 0.65, 0.0, 1.0) - glyph_groove, 0.0, 1.0)
    val = np.clip(0.84 + 0.16 * (stone_grain - 0.5) - 0.34 * mortar - 0.12 * glyph_groove, 0.20, 1.0)
    moss = np.clip((mortar * 0.75 + (1.0 - stone_grain) * 0.45 - 0.45) * 2.4, 0.0, 1.0)
    r = np.clip(val * (1.0 - moss * 0.35) + 0.32 * moss * 0.35, 0.0, 1.0)
    g = np.clip(val * (1.0 - moss * 0.18) + 0.54 * moss * 0.18, 0.0, 1.0)
    b = np.clip(val * (1.0 - moss * 0.42) + 0.24 * moss * 0.42, 0.0, 1.0)
    albedo = np.stack([r, g, b], axis=-1)
    rough = np.clip(0.78 + 0.16 * mortar + 0.10 * moss + 0.08 * (1.0 - stone_grain), 0.60, 0.98)
    normal = height_to_normal(height, strength=4.8)
    return albedo, normal, rough

def synth_timber_pbr(rs, size=512):
    """512x512 seamless salt-weathered shipwreck & pier oak planks (albedo, normal, roughness)."""
    w = h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32) / float(size)
    warp = tile_fbm(rs, w, h, [(3, 6, 0.6), (8, 16, 0.4)]) * 0.065
    yw = (yy + warp) % 1.0
    planks = 5
    pf = (yy * planks) % 1.0
    seam = np.clip(1.0 - np.minimum(pf, 1.0 - pf) / 0.032, 0.0, 1.0)

    rings = (0.5 + 0.5 * np.sin(yw * 2.0 * pi * 14.0 + tile_noise(rs, w, h, 4, 8) * 3.5)) * 0.55 \
          + (0.5 + 0.5 * np.sin(yw * 2.0 * pi * 34.0 + tile_noise(rs, w, h, 8, 16) * 2.2)) * 0.45
    fibers = tile_noise(rs, w, h, 6, 96) * 0.65 + tile_noise(rs, w, h, 14, 192) * 0.35
    splits = np.clip((0.20 - fibers) * 5.0, 0.0, 1.0)

    height = np.clip(0.62 + 0.14 * (rings - 0.5) + 0.16 * (fibers - 0.5) - 0.48 * seam - 0.22 * splits, 0.0, 1.0)
    val = np.clip(0.84 + 0.14 * (rings - 0.5) + 0.12 * (fibers - 0.5) - 0.36 * seam - 0.18 * splits, 0.18, 1.0)
    albedo = np.stack([val, val * 0.97, val * 0.92], axis=-1)
    rough = np.clip(0.80 + 0.14 * seam + 0.10 * splits - 0.08 * rings, 0.62, 0.97)
    normal = height_to_normal(height, strength=4.2)
    return albedo, normal, rough

def synth_metal_pbr(rs, size=512, rusty=True):
    """512x512 seamless hammered wrought iron or tarnished ship's brass PBR maps."""
    w = h = size
    dimples = tile_fbm(rs, w, h, [(12, 12, 0.55), (28, 28, 0.30), (56, 56, 0.15)])
    scratches = tile_noise(rs, w, h, 64, 12) * 0.5 + tile_noise(rs, w, h, 12, 64) * 0.5
    rust = np.clip((dimples * 0.65 + (1.0 - scratches) * 0.35 - 0.56) * 3.0, 0.0, 1.0) if rusty else np.zeros((h, w), dtype=np.float32)

    height = np.clip(0.55 + 0.28 * (dimples - 0.5) + 0.12 * (scratches - 0.5) - 0.14 * rust, 0.0, 1.0)
    val = np.clip(0.86 + 0.18 * (dimples - 0.5) + 0.08 * (scratches - 0.5), 0.35, 1.0)
    if rusty:
        r = np.clip(val * (1.0 - rust * 0.30) + 0.72 * rust * 0.30, 0.0, 1.0)
        g = np.clip(val * (1.0 - rust * 0.45) + 0.42 * rust * 0.45, 0.0, 1.0)
        b = np.clip(val * (1.0 - rust * 0.55) + 0.28 * rust * 0.55, 0.0, 1.0)
        rough = np.clip(0.46 + 0.38 * rust + 0.12 * (1.0 - dimples), 0.34, 0.92)
    else:
        r = np.clip(val * 1.02, 0.0, 1.0)
        g = np.clip(val * 0.99, 0.0, 1.0)
        b = np.clip(val * 0.93, 0.0, 1.0)
        rough = np.clip(0.30 + 0.22 * (1.0 - dimples) + 0.10 * (1.0 - scratches), 0.22, 0.66)
    albedo = np.stack([r, g, b], axis=-1)
    normal = height_to_normal(height, strength=3.4)
    return albedo, normal, rough

def synth_rope_pbr(rs, size=512):
    """512x512 seamless twisted 3-strand hemp rope PBR maps."""
    w = h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32) / float(size)
    twist = 0.5 + 0.5 * np.sin((xx * 18.0 + yy * 12.0) * 2.0 * pi)
    fibers = tile_noise(rs, w, h, 36, 12)
    height = np.clip(0.5 + 0.38 * (twist - 0.5) + 0.14 * (fibers - 0.5), 0.0, 1.0)
    val = np.clip(0.84 + 0.18 * (twist - 0.5) + 0.08 * (fibers - 0.5), 0.40, 1.0)
    albedo = np.stack([val, val * 0.96, val * 0.88], axis=-1)
    rough = np.clip(0.90 - 0.08 * twist + 0.06 * fibers, 0.78, 0.98)
    normal = height_to_normal(height, strength=3.6)
    return albedo, normal, rough

def synth_foliage_pbr(rs, size=512):
    """512x512 seamless veined painterly tropical vine/fern texture."""
    w = h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32) / float(size)
    veins = 0.5 + 0.5 * np.sin((xx * 24.0 + np.abs(yy - 0.5) * 14.0) * 2.0 * pi)
    brush = tile_fbm(rs, w, h, [(8, 16, 0.6), (24, 48, 0.4)])
    val = np.clip(0.86 + 0.10 * (veins - 0.5) + 0.12 * (brush - 0.5), 0.45, 1.0)
    albedo = np.stack([val * 0.96, val, val * 0.92], axis=-1)
    normal = height_to_normal(np.clip(0.5 + 0.25 * (veins - 0.5) + 0.20 * (brush - 0.5), 0.0, 1.0), strength=2.2)
    rough = np.clip(0.58 + 0.16 * (1.0 - veins), 0.42, 0.82)
    return albedo, normal, rough

MATS = {}
MAT_NAMES = {
    'limestone': 'mat_landmark_limestone',
    'limestone_moss': 'mat_landmark_limestone_moss',
    'basalt': 'mat_landmark_basalt',
    'temple_stone': 'mat_landmark_temple_stone',
    'skull_stone': 'mat_landmark_skull_stone',
    'timber': 'mat_landmark_timber',
    'paint': 'mat_landmark_paint',
    'rope': 'mat_landmark_rope',
    'iron': 'mat_landmark_iron',
    'brass': 'mat_landmark_brass',
    'glass': 'mat_landmark_glass',
    'skull_glow': 'mat_landmark_skull_glow',
    'foliage': 'mat_foliage',
    'col': 'mat_collision',
}

def make_materials():
    MATS.clear()
    rs = np.random.RandomState(SEED)
    pbr_sets = {
        'limestone': synth_limestone_pbr(rs, 512, mossy=False, bone_carved=False),
        'limestone_moss': synth_limestone_pbr(rs, 512, mossy=True, bone_carved=False),
        'basalt': synth_basalt_pbr(rs, 512),
        'temple_stone': synth_temple_stone_pbr(rs, 512),
        'skull_stone': synth_limestone_pbr(rs, 512, mossy=False, bone_carved=True),
        'timber': synth_timber_pbr(rs, 512),
        'rope': synth_rope_pbr(rs, 512),
        'iron': synth_metal_pbr(rs, 512, rusty=True),
        'brass': synth_metal_pbr(rs, 512, rusty=False),
        'foliage': synth_foliage_pbr(rs, 512),
    }

    def mk(key, pbr=None, rough=0.84, metal=0.0, emit=0.0, two=False,
           emit_col=(1.0, 0.64, 0.22, 1.0), normal_str=1.0):
        m = bpy.data.materials.new(MAT_NAMES[key])
        m.use_nodes = True
        nt = m.node_tree
        bsdf = nt.nodes['Principled BSDF']
        bsdf.inputs['Roughness'].default_value = rough
        bsdf.inputs['Metallic'].default_value = metal

        ca = nt.nodes.new('ShaderNodeVertexColor')
        ca.layer_name = 'Color'

        if pbr is not None:
            alb_arr, nrm_arr, rgh_arr = pbr
            alb_img = make_image('lm_%s_albedo' % key, alb_arr, non_color=False)
            nrm_img = make_image('lm_%s_normal' % key, nrm_arr, non_color=True)
            rgh_img = make_image('lm_%s_rough' % key, rgh_arr, non_color=True)

            t_alb = nt.nodes.new('ShaderNodeTexImage')
            t_alb.image = alb_img
            mx = nt.nodes.new('ShaderNodeMix')
            mx.data_type = 'RGBA'
            mx.blend_type = 'MULTIPLY'
            mx.inputs[0].default_value = 1.0
            nt.links.new(t_alb.outputs['Color'], mx.inputs[6])
            nt.links.new(ca.outputs['Color'], mx.inputs[7])
            nt.links.new(mx.outputs[2], bsdf.inputs['Base Color'])

            t_rgh = nt.nodes.new('ShaderNodeTexImage')
            t_rgh.image = rgh_img
            nt.links.new(t_rgh.outputs['Color'], bsdf.inputs['Roughness'])

            t_nrm = nt.nodes.new('ShaderNodeTexImage')
            t_nrm.image = nrm_img
            nmap = nt.nodes.new('ShaderNodeNormalMap')
            nmap.space = 'TANGENT'
            nmap.inputs['Strength'].default_value = normal_str
            nt.links.new(t_nrm.outputs['Color'], nmap.inputs['Color'])
            nt.links.new(nmap.outputs['Normal'], bsdf.inputs['Normal'])
        else:
            nt.links.new(ca.outputs['Color'], bsdf.inputs['Base Color'])

        if emit > 0.0:
            bsdf.inputs['Emission Color'].default_value = emit_col
            bsdf.inputs['Emission Strength'].default_value = emit
        m.use_backface_culling = not two
        MATS[key] = m

    mk('limestone', pbr_sets['limestone'], 0.86, 0.0, normal_str=1.0)
    mk('limestone_moss', pbr_sets['limestone_moss'], 0.88, 0.0, normal_str=1.0)
    mk('basalt', pbr_sets['basalt'], 0.72, 0.0, normal_str=1.1)
    mk('temple_stone', pbr_sets['temple_stone'], 0.85, 0.0, normal_str=1.05)
    mk('skull_stone', pbr_sets['skull_stone'], 0.84, 0.0, normal_str=1.05)
    mk('timber', pbr_sets['timber'], 0.82, 0.0, normal_str=0.95)
    mk('paint', pbr_sets['timber'], 0.72, 0.0, normal_str=0.65)
    mk('rope', pbr_sets['rope'], 0.92, 0.0, normal_str=0.85)
    mk('iron', pbr_sets['iron'], 0.52, 0.68, normal_str=0.85)
    mk('brass', pbr_sets['brass'], 0.34, 0.86, normal_str=0.65)
    mk('glass', None, 0.22, 0.0, emit=2.8, emit_col=(1.0, 0.68, 0.24, 1.0))
    mk('skull_glow', None, 0.24, 0.0, emit=3.6, emit_col=(0.14, 0.96, 0.78, 1.0))
    mk('foliage', pbr_sets['foliage'], 0.62, 0.0, two=True, normal_str=0.65)
    mk('col', None, 1.0)

# ---------------------------------------------------------------- Blender object builder & glTF export
def conv(p):
    return (p[0], -p[2], p[1])

def clear_scene():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me, do_unlink=True)

def build(mb):
    me = bpy.data.meshes.new(mb.name)
    rinv = Matrix.Rotation(radians(-mb.yaw), 3, 'Y')
    me.from_pydata([conv(rinv @ (v - mb.origin)) for v in mb.verts], [], mb.faces)
    names = sorted(set(mb.fmat))
    for n in names:
        me.materials.append(MATS[n])
    mi = {n: i for i, n in enumerate(names)}
    uvl = me.uv_layers.new(name='UVMap')
    ca = me.color_attributes.new('Color', 'FLOAT_COLOR', 'CORNER')
    uvs = []
    cols = []
    uv2 = []
    write_uv2 = mb.has_uv2
    for fi, f in enumerate(mb.faces):
        c = mb.fcol[fi]
        fu2 = mb.fuv2[fi]
        for k in range(len(f)):
            uvs.extend(mb.fuv[fi][k])
            cc = c[k] if isinstance(c, list) else c
            cols.extend((cc[0], cc[1], cc[2], 1.0))
            if write_uv2:
                if fu2 is not None:
                    uv2.extend(fu2[k])
                else:
                    uv2.extend((0.0, 0.0))
    uvl.data.foreach_set('uv', uvs)
    ca.data.foreach_set('color', cols)
    if write_uv2:
        u2 = me.uv_layers.new(name='Wind')
        u2.data.foreach_set('uv', uv2)
    me.polygons.foreach_set('material_index', [mi[m] for m in mb.fmat])
    me.polygons.foreach_set('use_smooth', mb.fsm)
    me.update()
    ob = bpy.data.objects.new(mb.name, me)
    ob.location = conv(mb.origin)
    ob.rotation_euler = (0, 0, radians(mb.yaw))
    bpy.context.scene.collection.objects.link(ob)
    return ob, mb.tris()

def col_piece(name, pts):
    bm = bmesh.new()
    seen = set()
    for p in pts:
        k = tuple(round(c, 4) for c in conv(p))
        if k not in seen:
            seen.add(k)
            bm.verts.new(k)
    bm.verts.index_update()
    r = bmesh.ops.convex_hull(bm, input=bm.verts)
    junk = list({e for e in r['geom_interior'] + r['geom_unused'] if isinstance(e, bmesh.types.BMVert)})
    junk.sort(key=lambda e: e.index)
    if junk:
        bmesh.ops.delete(bm, geom=junk, context='VERTS')
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(MATS['col'])
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob

def col_box(name, lo, hi):
    pts = [(x, y, z) for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]
    return col_piece(name, pts)

def add_empty(name, pos, yaw_deg=0.0):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.45
    e.location = conv(pos)
    e.rotation_euler = (0, 0, radians(yaw_deg))
    bpy.context.scene.collection.objects.link(e)
    return e

def export_landmark_glb(outdir, filename):
    lm_dir = os.path.join(outdir, 'landmarks')
    os.makedirs(lm_dir, exist_ok=True)
    path = os.path.join(lm_dir, filename)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', export_yup=True, export_apply=False,
        export_vertex_color='MATERIAL', export_all_vertex_colors=False,
        export_cameras=False, export_lights=False, export_animations=False,
        export_extras=False, export_tangents=True,
    )
    tris = 0
    cols = 0
    for ob in bpy.data.objects:
        if ob.type == 'MESH':
            if ob.name.startswith('col_'):
                cols += 1
            else:
                tris += sum(len(p.vertices) - 2 for p in ob.data.polygons)
    print('  %-34s %5d tris  (%d col_)' % (filename, tris, cols))
