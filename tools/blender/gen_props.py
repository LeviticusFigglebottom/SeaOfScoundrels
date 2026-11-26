# Sea of Scoundrels: procedural island & outpost prop generator.
# Usage: blender --background --factory-startup --python tools/blender/gen_props.py -- <outdir>
# Writes 24 stylized .glb files into <outdir>/props/. Deterministic (seeded).
# Everything is authored in Godot game coordinates (-Z forward, +Y up, +X starboard, metres)
# and converted to Blender's Z-up frame only on mesh creation, matching gen_sloop.py.
import bpy, bmesh, sys, os, math, random
import numpy as np
from contextlib import contextmanager
from math import sin, cos, pi, sqrt, atan2, radians
from mathutils import Vector, Matrix

SEED = 4219

# ---------------------------------------------------------------- colour helpers
def srgb(h):
    h = h.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c)

def mul(c, f):
    return (max(0.0, min(1.0, c[0] * f)), max(0.0, min(1.0, c[1] * f)), max(0.0, min(1.0, c[2] * f)))

def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] * (1.0 - t) + b[i] * t for i in range(3))

def jit(c, rng, amt=0.09, hue=0.03):
    f = 1.0 + rng.uniform(-amt, amt)
    return (
        max(0.0, min(1.0, c[0] * f * (1.0 + rng.uniform(-hue, hue)))),
        max(0.0, min(1.0, c[1] * f)),
        max(0.0, min(1.0, c[2] * f * (1.0 + rng.uniform(-hue, hue)))),
    )

# Palette aligned with gen_sloop.py & docs/DESIGN.md
C_HULL = srgb('#b06e3c')
C_DECK = srgb('#d2a468')
C_DARK = srgb('#6e4428')
C_WEATH = srgb('#8d6e4c')
C_DRIFT = srgb('#9e8d74')
C_TAR = srgb('#2d2622')
C_CREAM = srgb('#f0dfb2')
C_PLASTER = srgb('#ebe0c2')
C_PLASTER_SH = srgb('#c6b38f')
C_RED = srgb('#c9281e')
C_TEAL = srgb('#1c8088')
C_COPPER = srgb('#2f8c7b')
C_GOLD = srgb('#e9ae2c')
C_BRASS = srgb('#e2b04a')
C_IRON = srgb('#30313a')
C_ROPE = srgb('#cdb07c')
C_GLASS = srgb('#ffc061')
C_EMBER = srgb('#ff661a')
C_CHAR = srgb('#231d19')

C_TRUNK_DARK = srgb('#66462b')
C_TRUNK_LIGHT = srgb('#a07b51')
C_COCONUT = srgb('#5b3a1c')
C_LEAF_DEEP = srgb('#1b6826')
C_LEAF_MID = srgb('#399b29')
C_LEAF_SUN = srgb('#9bd12f')
C_FLOWER = srgb('#e64527')

C_STONE_PALE = srgb('#f7eed8')
C_STONE_WARM = srgb('#dfb882')
C_STONE_SHADE = srgb('#ab9b86')
C_SEA_MOSS = srgb('#4f6344')
C_STONE_LIGHT = srgb('#a69b86')
C_STONE_MID = srgb('#7a7265')
C_STONE_DARK = srgb('#4f4b46')
C_STONE_OCHRE = srgb('#b08f62')
C_MOSS = srgb('#46692d')
C_SAND = srgb('#cbb076')
C_SAND_DARK = srgb('#937847')
C_THATCH = srgb('#c99d4a')
C_SHINGLE = srgb('#68412b')
C_CEDAR_PALETTE = (
    srgb('#6b422a'),
    srgb('#7e4b2d'),
    srgb('#8f4f32'),
    srgb('#5f3d2b'),
    srgb('#985f3b'),
    srgb('#76462e'),
)
C_WHITE = (1.0, 1.0, 1.0)

SU, SV = 1.0 / 1.8, 1.0 / 0.9

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

# ---------------------------------------------------------------- mesh builder (matching gen_sloop.py)
class MB:
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
        self.wfn = None

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

    def fp(self, pts, mat, col, grain=None, inside=None, smooth=False, uv2=None):
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
        uvs = [(p.dot(gu) * SU + o[0], p.dot(gv) * SV + o[1]) for p in pts]
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

# ---------------------------------------------------------------- primitives
def cbox(mb, c, size, mat, col, ch=0.018, grain=None, M=None, skip=()):
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
                shade = 1.0 if (a == 1 and s > 0) else (0.86 if (a == 1 and s < 0) else 0.96)
                mb.fp([fv(a, s, -1, -1), fv(a, s, 1, -1), fv(a, s, 1, 1), fv(a, s, -1, 1)], mat, mul(col, shade), grain, O)
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
                            mb.fp([on(a, sa, b, sb, -1), on(a, sa, b, sb, 1), on(b, sb, a, sa, 1), on(b, sb, a, sa, -1)], mat, dk, grain, O)
            for sx in (-1, 1):
                for sy in (-1, 1):
                    for sz in (-1, 1):
                        mb.fp([
                            Vector((sx * h[0], sy * (h[1] - ch), sz * (h[2] - ch))),
                            Vector((sx * (h[0] - ch), sy * h[1], sz * (h[2] - ch))),
                            Vector((sx * (h[0] - ch), sy * (h[1] - ch), sz * h[2])),
                        ], mat, dk, grain, O)

def box2(mb, lo, hi, mat, col, ch=0.016, grain=None, skip=()):
    cbox(mb, [(lo[i] + hi[i]) * 0.5 for i in range(3)], [abs(hi[i] - lo[i]) for i in range(3)], mat, col, ch, grain, skip=skip)

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
    def uv(i, j):
        return (L[i] * SU + o[0], W[i][j] * SV + o[1])
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
        mb.fp(secs[0], mat, scols[0] if scols else col, cents[1] - cents[0], cents[1], uv2=[suv2[0]] * k if suv2 else None)
    if closed and caps[1] and n > 1:
        cap_col = scols[-2] if (scols and len(scols) >= 2) else (scols[-1] if scols else col)
        mb.fp(secs[-1], mat, cap_col, cents[-1] - cents[-2], cents[-2], uv2=[suv2[-1]] * k if suv2 else None)

def lathe(mb, prof, segs, mat, col, smooth=True, sp=False, colfn=None, axial=True):
    o = mb.newoff()
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
        return (pl[i] * SU + o[0], ua * SV + o[1]) if axial else (ua * SU + o[0], pl[i] * SV + o[1])
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
                uvs = [(r * cos(2 * pi * kk / segs) * SU + o[0], r * sin(2 * pi * kk / segs) * SV + o[1])
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

def ellipsoid(mb, c, radii, mat, col, segs=10, rings=6, M=None):
    prof = [(0.0 if i in (0, rings) else sin(pi * i / rings), -cos(pi * i / rings)) for i in range(rings + 1)]
    X = T(c) @ (M if M is not None else Matrix.Identity(4)) @ S(*radii)
    with xf(mb, X):
        lathe(mb, prof, segs, mat, col, True, True)

def torus(mb, Rr, r, segs, psegs, mat, col, smooth=True):
    prof = [(Rr + r * cos(-pi * 0.5 + 2 * pi * i / psegs), r * sin(-pi * 0.5 + 2 * pi * i / psegs)) for i in range(psegs)]
    prof.append(prof[0])
    lathe(mb, prof, segs, mat, col, smooth, True)

def rope_coil(mb, center, radius=0.22, turns=3, r=0.026):
    for i in range(turns):
        rr = radius * (1.0 - 0.16 * i)
        with xf(mb, T(center[0], center[1] + r * (1.0 + i * 1.7), center[2])):
            torus(mb, rr, r, 12, 6, 'rope', mul(C_ROPE, 0.92 + 0.08 * (i % 2)), True)

def faceted_rock(mb, center, radii, mat, col_top, col_mid, col_bot, rng, subdiv=2, warp=0.24, strata=0.14, flat_top=0.0, rot_deg=(0, 0, 0)):
    """Sculpted chunky faceted coastal rock with horizontal strata & vertex colour gradients."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    # Deterministic harmonic deformation (chunky planes + coastal strata)
    ph = [rng.uniform(0, 6.28) for _ in range(9)]
    dirs = [
        Vector((0.8, 0.4, 0.44)).normalized(),
        Vector((-0.6, 0.7, 0.38)).normalized(),
        Vector((0.25, -0.5, 0.83)).normalized(),
        Vector((-0.7, -0.35, -0.62)).normalized(),
    ]
    X = T(center) @ R('Y', rot_deg[1]) @ R('X', rot_deg[0]) @ R('Z', rot_deg[2])
    out_pts = []
    for v in bm.verts:
        p = v.co.copy()
        n = p.normalized()
        d = 1.0
        for idx, dv in enumerate(dirs):
            d += warp * 0.45 * sin(n.dot(dv) * 3.1 + ph[idx])
        # Horizontal sedimentary ledges
        d += strata * sin(p.y * 5.2 + ph[5] + 0.8 * sin(p.x * 2.5 + p.z * 2.2))
        # Slightly flatten underside for solid seating
        if p.y < -0.55:
            p.y = -0.55 + (p.y + 0.55) * 0.45
        if flat_top > 0.0 and p.y > flat_top:
            p.y = flat_top + (p.y - flat_top) * 0.25
        # Quantize slightly along radial facets for chunky painterly planes
        p = Vector((p.x * radii[0] * d, p.y * radii[1] * d, p.z * radii[2] * d))
        v.co = p
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
            h01 = smooth01((fc.y / max(radii[1], 0.1) + 0.85) * 0.55)
            # Upward faces catch warm ochre/moss, steep faces mid stone, undersides dark
            if fn.y > 0.55:
                base = mix(col_mid, col_top, smooth01((fn.y - 0.55) / 0.45))
            elif fn.y < -0.1:
                base = mul(col_bot, 0.78)
            else:
                base = mix(col_bot, col_mid, h01)
            # Subtle strata tinting per face
            st = 0.92 + 0.12 * sin(fc.y * 2.6 + ph[6])
            c = jit(mul(base, st), rng, 0.05, 0.02)
            mb.fp(pts, mat, c, (1, 0, 0), Vector((0, 0, 0)), smooth=False)
            for p in pts:
                out_pts.append(X @ p)
    bm.free()
    return out_pts

def build_lantern_geom(mb, center, scale=1.0, hanging=True):
    """Chunky iron-and-brass maritime lantern with glowing glass core."""
    cx, cy, cz = center
    s = scale
    # Top cap & loop
    with xf(mb, T(cx, cy, cz)):
        cyl(mb, 0.14 * s, -0.19 * s, -0.14 * s, 6, 'iron', C_IRON, False, 0.01 * s, 0.16 * s)
        cyl(mb, 0.15 * s, 0.15 * s, 0.21 * s, 6, 'iron', C_IRON, False, 0.01 * s, 0.06 * s)
        cyl(mb, 0.05 * s, 0.21 * s, 0.27 * s, 6, 'brass', C_BRASS, False, 0.005 * s, 0.03 * s)
        # Glowing glass hexagon
        cyl(mb, 0.115 * s, -0.14 * s, 0.15 * s, 6, 'glass', C_GLASS, False, 0.0, 0.125 * s)
        # Brass guard ribs
        for k in range(4):
            ang = k * pi * 0.5 + pi * 0.25
            rx = 0.132 * s * cos(ang)
            rz = 0.132 * s * sin(ang)
            cbox(mb, (rx, 0.005 * s, rz), (0.024 * s, 0.30 * s, 0.024 * s), 'brass', C_BRASS, 0.004 * s)
        if hanging:
            with xf(mb, T(0, 0.30 * s, 0) @ M_Y2Z):
                torus(mb, 0.045 * s, 0.012 * s, 8, 5, 'iron', C_IRON, False)

# ---------------------------------------------------------------- procedural textures & materials
def tile_noise(rs, w, h, gx, gy):
    g = rs.rand(gy, gx)
    ys = np.arange(h) * gy / h
    xs = np.arange(w) * gx / w
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

def make_image(name, arr):
    h, w = arr.shape[:2]
    rgba = np.ones((h, w, 4), dtype=np.float32)
    rgba[..., :3] = np.clip(arr, 0.0, 1.0)
    img = bpy.data.images.new(name, w, h, alpha=False)
    img.pixels.foreach_set(rgba.ravel())
    img.file_format = 'PNG'
    img.pack()
    return img

def tex_wood(rs):
    w = h = 256
    warp = tile_noise(rs, w, h, 3, 4) * 0.08
    yy = (np.arange(h)[:, None] / h + warp) % 1.0
    lines = np.zeros((h, w))
    for freq, amp in ((9, 0.5), (23, 0.3), (49, 0.2)):
        ph = rs.rand() * 6.28
        lines += amp * (0.5 + 0.5 * np.sin(yy * 2.0 * pi * freq + ph + tile_noise(rs, w, h, 2, 6) * 2.8))
    streak = tile_noise(rs, w, h, 3, 48) * 0.6 + tile_noise(rs, w, h, 6, 96) * 0.4
    val = 0.80 + 0.12 * lines + 0.10 * (streak - 0.5) * 2.0
    dark = np.clip((0.30 - streak) * 6.0, 0.0, 1.0) * 0.16
    val = val - dark + (tile_noise(rs, w, h, 64, 64) - 0.5) * 0.04
    return np.stack([val, val * 0.975, val * 0.93], axis=-1)

def tex_stone(rs):
    w = h = 256
    n1 = tile_noise(rs, w, h, 6, 6)
    n2 = tile_noise(rs, w, h, 16, 16)
    n3 = tile_noise(rs, w, h, 40, 40)
    strata = 0.5 + 0.5 * np.sin((np.arange(h)[:, None] / h * 10.0 + n1 * 1.4) * 2.0 * pi)
    cracks = np.clip((0.26 - np.abs(n2 - 0.5) * 2.0) * 3.0, 0.0, 1.0) * 0.15
    val = 0.82 + 0.14 * (n1 - 0.5) + 0.10 * (n2 - 0.5) + 0.06 * (n3 - 0.5) + 0.05 * (strata - 0.5) - cracks
    return np.stack([val, val * 0.99, val * 0.96], axis=-1)

def tex_foliage(rs):
    w = h = 256
    yy, xx = np.mgrid[0:h, 0:w] / float(w)
    veins = 0.5 + 0.5 * np.sin((xx * 28.0 + np.abs(yy - 0.5) * 14.0) * 2.0 * pi)
    brush = tile_noise(rs, w, h, 8, 24)
    fine = tile_noise(rs, w, h, 32, 32)
    val = 0.86 + 0.08 * veins + 0.10 * (brush - 0.5) + 0.05 * (fine - 0.5)
    return np.stack([val * 0.98, val, val * 0.94], axis=-1)

def tex_canvas_striped(rs):
    w = h = 256
    yy, xx = np.mgrid[0:h, 0:w] / float(w)
    weave = 0.95 + 0.03 * np.sin(xx * 2.0 * pi * 64.0) * np.sin(yy * 2.0 * pi * 64.0)
    blot = 0.90 + 0.10 * tile_noise(rs, w, h, 6, 6)
    val = weave * blot
    return np.stack([val, val * 0.99, val * 0.95], axis=-1)

MATS = {}
MAT_NAMES = {
    'wood': 'mat_wood',
    'paint': 'mat_paint',
    'stone': 'mat_stone',
    'foliage': 'mat_foliage',
    'awning': 'mat_awning',
    'rope': 'mat_rope',
    'iron': 'mat_iron',
    'brass': 'mat_brass',
    'glass': 'mat_lantern_glass',
    'window': 'mat_window_glass',
    'embers': 'mat_embers',
    'col': 'mat_collision',
}

def make_materials():
    rs = np.random.RandomState(SEED)
    wood_img = make_image('prop_wood', tex_wood(rs))
    stone_img = make_image('prop_stone', tex_stone(rs))
    fol_img = make_image('prop_foliage', tex_foliage(rs))
    awn_img = make_image('prop_canvas', tex_canvas_striped(rs))

    def mk(key, tex=None, rough=0.8, metal=0.0, emit=0.0, two=False, emit_col=(1.0, 0.64, 0.22, 1.0)):
        m = bpy.data.materials.new(MAT_NAMES[key])
        m.use_nodes = True
        nt = m.node_tree
        b = nt.nodes['Principled BSDF']
        b.inputs['Roughness'].default_value = rough
        b.inputs['Metallic'].default_value = metal
        ca = nt.nodes.new('ShaderNodeVertexColor')
        ca.layer_name = 'Color'
        if tex is not None:
            t = nt.nodes.new('ShaderNodeTexImage')
            t.image = tex
            mx = nt.nodes.new('ShaderNodeMix')
            mx.data_type = 'RGBA'
            mx.blend_type = 'MULTIPLY'
            mx.inputs[0].default_value = 1.0
            nt.links.new(t.outputs['Color'], mx.inputs[6])
            nt.links.new(ca.outputs['Color'], mx.inputs[7])
            nt.links.new(mx.outputs[2], b.inputs['Base Color'])
        else:
            nt.links.new(ca.outputs['Color'], b.inputs['Base Color'])
        if emit > 0.0:
            b.inputs['Emission Color'].default_value = emit_col
            b.inputs['Emission Strength'].default_value = emit
        m.use_backface_culling = not two
        MATS[key] = m

    mk('wood', wood_img, 0.82)
    mk('paint', None, 0.70)
    mk('stone', stone_img, 0.88)
    mk('foliage', fol_img, 0.62, two=True)
    mk('awning', awn_img, 0.90, two=True)
    mk('rope', None, 0.94)
    mk('iron', None, 0.48, 0.60)
    mk('brass', None, 0.30, 0.86)
    mk('glass', None, 0.22, 0.0, emit=2.6, emit_col=(1.0, 0.66, 0.22, 1.0))
    mk('window', None, 0.14, 0.0, emit=1.55, emit_col=(1.0, 0.68, 0.26, 1.0))
    mk('embers', None, 0.60, 0.0, emit=3.8, emit_col=(1.0, 0.34, 0.06, 1.0))
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
    wv = [mb.wfn(v) for v in mb.verts] if mb.wfn else None
    write_uv2 = mb.has_uv2 or (wv is not None)
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
                elif wv is not None:
                    uv2.extend(wv[f[k]])
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
    e.empty_display_size = 0.35
    e.location = conv(pos)
    e.rotation_euler = (0, 0, radians(yaw_deg))
    bpy.context.scene.collection.objects.link(e)
    return e

def export_glb(outdir, filename):
    props_dir = os.path.join(outdir, 'props')
    os.makedirs(props_dir, exist_ok=True)
    path = os.path.join(props_dir, filename)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', export_yup=True, export_apply=False,
        export_vertex_color='MATERIAL', export_all_vertex_colors=False,
        export_cameras=False, export_lights=False, export_animations=False,
        export_extras=False, export_tangents=False
    )
    tris = 0
    cols = 0
    for ob in bpy.data.objects:
        if ob.type == 'MESH':
            if ob.name.startswith('col_'):
                cols += 1
            else:
                tris += sum(len(p.vertices) - 2 for p in ob.data.polygons)
    print('  %-22s %5d tris  (%d col_)' % (filename, tris, cols))

# ================================================================ PROP GENERATORS

def _add_palm_frond(mb, crown, azimuth, pitch_deg, length, width, droop, tier_tint, phase, rng):
    """Sculpted tropical palm frond: arched midrib + folded serrated leaflet panels with UV2 wind weights 0..1."""
    ca, sa = cos(azimuth), sin(azimuth)
    fwd = Vector((ca, 0.0, sa))
    side = Vector((-sa, 0.0, ca))
    up = Vector((0.0, 1.0, 0.0))
    segs = 8
    pitch = radians(pitch_deg)

    def spine(t):
        r = length * t
        # Arches upward then droops cleanly toward tip
        y = sin(pitch) * r - droop * (t ** 2.15) * length
        h = cos(pitch) * r * (1.0 - 0.14 * t * t)
        return crown + fwd * h + up * y

    pts = [spine(i / float(segs)) for i in range(segs + 1)]
    # Chunky central midrib stem (thin tapering spine)
    for i in range(segs):
        t0 = i / float(segs)
        t1 = (i + 1) / float(segs)
        p0, p1 = pts[i], pts[i + 1]
        w0 = 0.045 * (1.0 - 0.72 * t0)
        w1 = 0.045 * (1.0 - 0.72 * t1)
        u0 = (pow(t0, 1.35), phase)
        u1 = (pow(t1, 1.35), phase)
        stem_col = mix(C_LEAF_DEEP, C_LEAF_MID, t0)
        # V-ridge midrib strip
        for sgn in (-1.0, 1.0):
            q = [p0, p0 + side * (sgn * w0) - up * (w0 * 0.4), p1 + side * (sgn * w1) - up * (w1 * 0.4), p1]
            mb.fp(q, 'foliage', stem_col, fwd, p0 - up, smooth=True, uv2=[u0, u0, u1, u1])

    # Paired arched serrated leaflet blades along left and right sides of the midrib
    frond_shift = rng.uniform(-0.08, 0.10)
    base_tier = max(0.0, min(1.0, tier_tint * 0.88 + frond_shift))
    for i in range(segs):
        t0 = i / float(segs)
        t1 = (i + 1) / float(segs)
        # Envelope: narrow at stem base, lush and wide in middle, sweeping to pointed tip
        env0 = sin(pi * pow(max(0.03, t0), 0.72))
        env1 = sin(pi * pow(min(0.99, t1), 0.72))
        bw0 = width * env0
        bw1 = width * env1
        # Slight notch between leaflet clusters for unmistakable palm silhouette
        notch = 0.82 if (i % 2 == 1 and 1 <= i <= segs - 2) else 1.0
        p0, p1 = pts[i], pts[i + 1]
        tan = (p1 - p0).normalized()
        bn = tan.cross(side).normalized()  # local frond up
        w_base0 = pow(t0, 1.35)
        w_base1 = pow(t1, 1.35)
        # Rich sunlit emerald-to-chartreuse tropical gradient from crown to drooping tips
        c0 = jit(mix(mix(C_LEAF_DEEP, C_LEAF_MID, base_tier), C_LEAF_SUN, pow(t0, 1.05)), rng, 0.06, 0.03)
        c1 = jit(mix(mix(C_LEAF_DEEP, C_LEAF_MID, base_tier), C_LEAF_SUN, pow(t1, 1.05)), rng, 0.06, 0.03)
        for sgn in (-1.0, 1.0):
            # Folded V-profile blade (inner rib -> arched mid -> drooping tip edge)
            m0 = p0 + side * (sgn * bw0 * 0.54) + bn * (0.11 * bw0)
            m1 = p1 + side * (sgn * bw1 * 0.54 * notch) + bn * (0.11 * bw1)
            e0 = p0 + side * (sgn * bw0) - bn * (0.28 * bw0) + fwd * (0.11 * bw0)
            e1 = p1 + side * (sgn * bw1 * notch) - bn * (0.28 * bw1) + fwd * (0.11 * bw1)
            u_in0 = (min(1.0, w_base0), phase)
            u_in1 = (min(1.0, w_base1), phase)
            u_mid0 = (min(1.0, w_base0 * 0.92 + 0.08), phase)
            u_mid1 = (min(1.0, w_base1 * 0.92 + 0.08), phase)
            u_out0 = (min(1.0, w_base0 * 0.85 + 0.15), phase)
            u_out1 = (min(1.0, w_base1 * 0.85 + 0.15), phase)
            # Inner blade quad
            mb.fp([p0, m0, m1, p1], 'foliage', [c0, c0, c1, c1], fwd, None, smooth=True, uv2=[u_in0, u_mid0, u_mid1, u_in1])
            # Outer drooping blade quad (sunlit chartreuse-emerald edge catch)
            c0_tip = mix(c0, C_LEAF_SUN, 0.32)
            c1_tip = mix(c1, C_LEAF_SUN, 0.42)
            mb.fp([m0, e0, e1, m1], 'foliage', [c0, c0_tip, c1_tip, c1], fwd, None, smooth=True, uv2=[u_mid0, u_out0, u_out1, u_mid1])

def _build_palm_tree(name, height, lean_x, lean_z, s_curve, n_rings, frond_count, seed_off):
    clear_scene()
    rng = random.Random(SEED + seed_off)
    mb_trunk = MB('Trunk', seed=seed_off)
    mb_fronds = MB('Fronds', seed=seed_off + 100)

    def trunk_pt(t):
        # Smooth sweeping tropical trunk curve; starts at y=-0.85 so base embeds cleanly on slopes
        y = -0.85 + (height + 0.85) * t
        bend = (t ** 1.65)
        sw = sin(t * pi * 1.15) * s_curve
        return Vector((lean_x * bend + sw, y, lean_z * bend + sw * 0.35))

    # Ringed segmented coconut-palm trunk (chunky overlapping bark collars!)
    sides = 8
    col_pts_a = []
    col_pts_b = []
    for i in range(n_rings):
        t0 = i / float(n_rings)
        t1 = (i + 1) / float(n_rings)
        tm = 0.5 * (t0 + t1)
        p0 = trunk_pt(t0)
        p1 = trunk_pt(t1)
        # Flared root buttress at bottom, tapering gently to crown
        r_base = (0.44 if i == 0 else (0.35 if i == 1 else 0.30 * (1.0 - 0.44 * t0)))
        r_top = 0.30 * (1.0 - 0.44 * t1) * 1.12  # characteristic palm bark ring lip!
        tan = (p1 - p0).normalized()
        ref = Vector((1, 0, 0)) if abs(tan.x) < 0.8 else Vector((0, 0, 1))
        nx = (ref - tan * ref.dot(tan)).normalized()
        nz = tan.cross(nx)
        sec0 = []
        sec1 = []
        for k in range(sides):
            ang = 2.0 * pi * k / sides + i * 0.14
            fl = 1.0 + (0.14 * sin(ang * 4.0) if i <= 1 else 0.0)
            off = nx * cos(ang) + nz * sin(ang)
            v0 = p0 + off * (r_base * fl)
            v1 = p1 + off * (r_top * fl)
            sec0.append(v0)
            sec1.append(v1)
            if t0 < 0.55:
                col_pts_a.extend([v0, v1])
            else:
                col_pts_b.extend([v0, v1])
        c_ring = jit(mix(C_TRUNK_DARK, C_TRUNK_LIGHT, smooth01(tm)), rng, 0.07, 0.02)
        if i % 2 == 1:
            c_ring = mul(c_ring, 0.91)
        w0 = (0.12 * t0 * t0, 0.0)
        w1 = (0.12 * t1 * t1, 0.0)
        loft(mb_trunk, [sec0, sec1], 'wood', c_ring, closed=True, caps=(i == 0, i == n_rings - 1), mode='flat', suv2=[w0, w1])

    crown = trunk_pt(1.0)
    # Chunky palm heart bulb at crown
    ellipsoid(mb_trunk, crown + Vector((0, 0.05, 0)), (0.28, 0.24, 0.28), 'wood', C_TRUNK_DARK, 8, 5)

    # Cluster of 6 chunky tropical coconuts tucked beneath crown
    for ci in range(6):
        ang = ci * (2.0 * pi / 6.0) + rng.uniform(-0.18, 0.18)
        cr = 0.24 + rng.uniform(-0.02, 0.04)
        cy = -0.22 - (ci % 2) * 0.11
        cpos = crown + Vector((cos(ang) * cr, cy, sin(ang) * cr))
        ccol = jit(mix(C_COCONUT, C_LEAF_DEEP, 0.15 if ci % 3 == 0 else 0.0), rng, 0.08, 0.02)
        ellipsoid(mb_trunk, cpos, (0.14, 0.17, 0.14), 'paint', ccol, 7, 5, R('Z', rng.uniform(-25, 25)))

    # Lush 3-tier tropical palm crown (~35% wider reach & fuller drooping silhouette)
    lower_n = frond_count // 2 + 1
    upper_n = frond_count - lower_n
    for i in range(lower_n):
        az = i * (2.0 * pi / lower_n) + rng.uniform(-0.18, 0.18)
        _add_palm_frond(
            mb_fronds, crown + Vector((0, 0.02, 0)), az,
            pitch_deg=rng.uniform(14.0, 26.0),
            length=rng.uniform(4.35, 5.25),
            width=rng.uniform(1.04, 1.26),
            droop=rng.uniform(0.50, 0.62),
            tier_tint=0.22, phase=rng.random(), rng=rng
        )
    for i in range(upper_n):
        az = (i + 0.5) * (2.0 * pi / upper_n) + rng.uniform(-0.20, 0.20)
        _add_palm_frond(
            mb_fronds, crown + Vector((0, 0.16, 0)), az,
            pitch_deg=rng.uniform(35.0, 50.0),
            length=rng.uniform(3.45, 4.30),
            width=rng.uniform(0.92, 1.14),
            droop=rng.uniform(0.40, 0.50),
            tier_tint=0.78, phase=rng.random(), rng=rng
        )
    # Sunlit chartreuse-emerald young crown shoots for a rich, full canopy heart
    for i in range(3):
        az = i * (2.0 * pi / 3.0) + rng.uniform(-0.35, 0.35)
        _add_palm_frond(
            mb_fronds, crown + Vector((0, 0.24, 0)), az,
            pitch_deg=rng.uniform(58.0, 74.0),
            length=rng.uniform(2.15, 2.85),
            width=rng.uniform(0.66, 0.84),
            droop=rng.uniform(0.26, 0.35),
            tier_tint=1.0, phase=rng.random(), rng=rng
        )

    build(mb_trunk)
    build(mb_fronds)
    col_piece('col_trunk_lower', col_pts_a)
    col_piece('col_trunk_upper', col_pts_b)

def gen_palm_tall(outdir):
    _build_palm_tree('palm_tall', height=11.4, lean_x=1.15, lean_z=-0.55, s_curve=0.32, n_rings=14, frond_count=13, seed_off=11)
    export_glb(outdir, 'palm_tall.glb')

def gen_palm_curved(outdir):
    _build_palm_tree('palm_curved', height=9.0, lean_x=3.15, lean_z=-1.05, s_curve=0.68, n_rings=13, frond_count=12, seed_off=23)
    export_glb(outdir, 'palm_curved.glb')

def gen_bush_fern(outdir):
    clear_scene()
    rng = random.Random(SEED + 37)
    mb = MB('BushFern', seed=37)
    # Earthy root heart mound
    ellipsoid(mb, (0, 0.08, 0), (0.34, 0.22, 0.34), 'wood', C_TRUNK_DARK, 8, 4)

    # Outer & inner layered tropical fern fronds with UV2 wind weights
    tiers = [(9, 14.0, 26.0, 1.15, 1.45, 0.42, 0.36, 0.2), (6, 38.0, 56.0, 0.78, 1.08, 0.34, 0.28, 0.85)]
    for count, pmin, pmax, lmin, lmax, w0, drp, tint in tiers:
        for i in range(count):
            az = i * (2.0 * pi / count) + rng.uniform(-0.22, 0.22) + tint * 0.4
            _add_palm_frond(
                mb, Vector((0, 0.12, 0)), az,
                pitch_deg=rng.uniform(pmin, pmax),
                length=rng.uniform(lmin, lmax),
                width=w0 * rng.uniform(0.88, 1.14),
                droop=drp, tier_tint=tint, phase=rng.random(), rng=rng
            )

    # 3 bright tropical blossom buds for painterly colour contrast
    for i in range(3):
        az = i * 2.1 + 0.4
        bp = Vector((cos(az) * 0.26, 0.56 + 0.08 * i, sin(az) * 0.26))
        tube(mb, [(cos(az) * 0.1, 0.14, sin(az) * 0.1), bp], [0.022, 0.015], 4, 'foliage', C_LEAF_MID, suv2=[(0.0, 0.3), (0.55, 0.3)])
        ellipsoid(mb, bp, (0.09, 0.12, 0.09), 'paint', jit(C_FLOWER, rng, 0.08), 6, 4)

    build(mb)
    export_glb(outdir, 'bush_fern.glb')

def gen_rock_boulder(outdir):
    clear_scene()
    rng = random.Random(SEED + 51)
    mb = MB('RockBoulder', seed=51)
    pts = []
    pts += faceted_rock(mb, (0.0, 0.55, 0.0), (1.75, 1.35, 1.55), 'stone', C_STONE_OCHRE, C_STONE_MID, C_STONE_DARK, rng, subdiv=2, warp=0.26, strata=0.14)
    pts += faceted_rock(mb, (1.25, 0.12, 0.72), (0.95, 0.78, 0.86), 'stone', C_STONE_LIGHT, C_STONE_MID, C_STONE_DARK, rng, subdiv=2, warp=0.24, strata=0.10, rot_deg=(8, 42, -5))
    pts += faceted_rock(mb, (-1.10, -0.05, -0.68), (0.88, 0.65, 0.80), 'stone', C_MOSS, C_STONE_MID, C_STONE_DARK, rng, subdiv=1, warp=0.22, strata=0.08, rot_deg=(-6, -30, 9))
    build(mb)
    col_piece('col_rock_boulder', pts)
    export_glb(outdir, 'rock_boulder.glb')

def _limestone_monolith(mb, ring_specs, sides, rng, rot_y=0.0, twist=0.18, apex_y=None, apex_off=(0.0, 0.0)):
    """Build a continuous tapered faceted sunlit limestone spire matching island cliff planes."""
    # Per-rib angular profile creates bold vertical limestone facets without stacked-sphere waists.
    rib_scale = [rng.uniform(0.84, 1.16) for _ in range(sides)]
    rib_phase = [rng.uniform(0.0, 6.28) for _ in range(sides)]
    rings = []
    centers = []
    out_pts = []

    n_rings = len(ring_specs)
    for ri, (y, rx, rz, ox, oz) in enumerate(ring_specs):
        t = ri / float(max(1, n_rings - 1))
        ring = []
        centers.append(Vector((ox, y, oz)))
        for k in range(sides):
            ang = rot_y + 2.0 * pi * k / float(sides) + twist * t
            # Subtle organic chisel relief along height while preserving clean monotonic taper
            chisel = rib_scale[k] * (1.0 + 0.06 * sin(t * 5.2 + rib_phase[k]))
            px = ox + cos(ang) * rx * chisel
            pz = oz + sin(ang) * rz * chisel
            py = y + (0.0 if ri == 0 else rng.uniform(-0.18, 0.18) * (1.0 - 0.5 * t))
            v = Vector((px, py, pz))
            ring.append(v)
            out_pts.append(v)
        rings.append(ring)

    def _stone_face_col(pts, inside_pt):
        fn = newell(pts)
        fn = fn.normalized() if fn.length > 1e-8 else Vector((0.0, 1.0, 0.0))
        fc = sum(pts, Vector()) / float(len(pts))
        if fn.dot(fc - inside_pt) < 0.0:
            fn = -fn
        # Sunlit pale limestone upper planes blending smoothly into warm ochre lower cliffs
        pale_t = smooth01((fc.y - 1.8) / 11.5)
        facet_var = max(-0.5, min(0.5, fn.x * 0.35 - fn.z * 0.30 + fn.y * 0.40))
        ivory_t = max(0.0, min(1.0, pale_t * 0.78 + 0.18 + facet_var * 0.18))
        base = mix(C_STONE_WARM, C_STONE_PALE, ivory_t)
        if fn.y < -0.08:
            base = mix(base, C_STONE_SHADE, 0.38)
        elif fn.y > 0.50:
            base = mix(base, C_STONE_PALE, 0.25)
        # Subtle coastal sea-moss collar right around the tidal waterline
        moss_t = smooth01((2.2 - fc.y) / 2.6) * smooth01((fc.y + 3.2) / 2.0)
        if moss_t > 0.0:
            base = mix(base, C_SEA_MOSS, moss_t * 0.50)
        return jit(base, rng, 0.045, 0.016)

    mb.newoff()
    for ri in range(n_rings - 1):
        r0, r1 = rings[ri], rings[ri + 1]
        inside = 0.5 * (centers[ri] + centers[ri + 1])
        for k in range(sides):
            kn = (k + 1) % sides
            q = [r0[k], r0[kn], r1[kn], r1[k]]
            mb.fp(q, 'stone', _stone_face_col(q, inside), (1, 0, 0), inside, smooth=False)

    # Bottom cap
    mb.fp(rings[0], 'stone', C_STONE_SHADE, (1, 0, 0), centers[0] + Vector((0, 1.0, 0)), smooth=False)

    # Tapered chisel summit cap (crisp faceted peak with zero flat disc look)
    top_ring = rings[-1]
    top_c = centers[-1]
    if apex_y is not None:
        apex = Vector((top_c.x + apex_off[0], apex_y, top_c.z + apex_off[1]))
        out_pts.append(apex)
        inside_top = Vector((top_c.x, top_c.y - 0.6, top_c.z))
        for k in range(sides):
            kn = (k + 1) % sides
            tri = [top_ring[k], top_ring[kn], apex]
            mb.fp(tri, 'stone', _stone_face_col(tri, inside_top), (1, 0, 0), inside_top, smooth=False)
    else:
        inside_top = top_c - Vector((0, 1.0, 0))
        mb.fp(top_ring, 'stone', _stone_face_col(top_ring, inside_top), (1, 0, 0), inside_top, smooth=False)

    return out_pts

def gen_rock_spire(outdir):
    clear_scene()
    rng = random.Random(SEED + 67)
    mb = MB('RockSpire', seed=67)
    # Unified tapered faceted sunlit limestone sea-stack monolith (~19 m tall)
    # matching the island limestone cliffs (no stacked dark bowling-pin spheres).
    main_rings = [
        (-4.2, 4.35, 3.80,  0.15,  0.10),
        (-1.2, 3.95, 3.45,  0.10,  0.06),
        ( 1.5, 3.55, 3.10,  0.02,  0.00),
        ( 4.4, 3.10, 2.70, -0.10, -0.05),
        ( 7.6, 2.60, 2.25, -0.24, -0.12),
        (10.8, 2.05, 1.75, -0.40, -0.20),
        (13.8, 1.48, 1.26, -0.58, -0.26),
        (16.4, 0.92, 0.76, -0.76, -0.32),
        (18.2, 0.42, 0.30, -0.88, -0.35),
    ]
    all_pts = _limestone_monolith(mb, main_rings, sides=7, rng=rng, rot_y=0.22, twist=0.26, apex_y=19.2, apex_off=(-0.10, -0.04))

    # Fused secondary limestone shoulder fin for an iconic asymmetric horizon silhouette
    fin_rings = [
        (-4.0, 2.45, 2.15, 1.70, -0.45),
        (-0.8, 2.20, 1.92, 1.85, -0.50),
        ( 2.4, 1.88, 1.62, 2.05, -0.58),
        ( 5.6, 1.46, 1.24, 2.22, -0.68),
        ( 8.4, 0.95, 0.78, 2.38, -0.76),
        (10.4, 0.44, 0.34, 2.50, -0.82),
    ]
    all_pts += _limestone_monolith(mb, fin_rings, sides=6, rng=rng, rot_y=-0.45, twist=-0.18, apex_y=11.3, apex_off=(0.08, -0.04))

    # Wave-cut limestone base buttress anchoring the opposite flank into the surf
    spur_rings = [
        (-3.8, 2.10, 1.85, -1.75, 1.05),
        (-1.0, 1.85, 1.60, -1.82, 1.08),
        ( 1.6, 1.42, 1.22, -1.70, 0.98),
        ( 3.6, 0.78, 0.66, -1.52, 0.85),
    ]
    all_pts += _limestone_monolith(mb, spur_rings, sides=6, rng=rng, rot_y=0.85, twist=0.12, apex_y=4.4, apex_off=(0.12, -0.06))

    pts_bot = [p for p in all_pts if p.y <= 5.0]
    pts_mid = [p for p in all_pts if 3.5 <= p.y <= 12.2]
    pts_top = [p for p in all_pts if p.y >= 10.2]

    build(mb)
    col_piece('col_spire_base', pts_bot)
    col_piece('col_spire_mid', pts_mid)
    col_piece('col_spire_top', pts_top)
    export_glb(outdir, 'rock_spire.glb')

def gen_rock_arch(outdir):
    clear_scene()
    rng = random.Random(SEED + 83)
    mb = MB('RockArch', seed=83)
    # Dramatic natural coastal stone arch (~16 m span, ~12.5 m tall, open passable central vault!)
    pts_l = []
    pts_r = []
    pts_b = []
    # Left & right sea-pillars extending to y = -3.0 m
    pts_l += faceted_rock(mb, (-6.2, 0.8, 0.0), (2.8, 4.2, 2.9), 'stone', C_STONE_OCHRE, C_STONE_MID, C_STONE_DARK, rng, subdiv=2, warp=0.22, strata=0.15, rot_deg=(0, 15, -6))
    pts_l += faceted_rock(mb, (-5.4, 5.6, 0.1), (2.3, 3.6, 2.4), 'stone', C_STONE_LIGHT, C_STONE_MID, C_STONE_DARK, rng, subdiv=2, warp=0.22, strata=0.15, rot_deg=(2, -10, -14))
    pts_r += faceted_rock(mb, (6.2, 0.8, 0.1), (2.9, 4.3, 2.8), 'stone', C_STONE_OCHRE, C_STONE_MID, C_STONE_DARK, rng, subdiv=2, warp=0.22, strata=0.15, rot_deg=(0, -22, 7))
    pts_r += faceted_rock(mb, (5.3, 5.8, -0.1), (2.2, 3.8, 2.3), 'stone', C_STONE_LIGHT, C_STONE_MID, C_STONE_DARK, rng, subdiv=2, warp=0.22, strata=0.15, rot_deg=(-3, 18, 15))
    # Vaulted keystone arch span (5 chunky interlocking faceted rock masses!)
    span_specs = [
        (-3.6, 9.2, 0.0, (2.2, 2.1, 2.2), (0, 8, -24)),
        (-1.2, 10.6, 0.05, (2.3, 1.9, 2.1), (2, -12, -8)),
        (1.3, 10.7, -0.05, (2.4, 2.0, 2.2), (-2, 14, 10)),
        (3.6, 9.3, 0.0, (2.1, 2.0, 2.1), (0, -9, 26)),
        (-0.2, 12.1, 0.0, (1.8, 1.15, 1.5), (0, 5, -4)),  # grassy-ochre crown crag
    ]
    for x, y, z, rad, rot in span_specs:
        top_c = C_MOSS if y > 11.2 else C_STONE_OCHRE
        pts_b += faceted_rock(mb, (x, y, z), rad, 'stone', top_c, C_STONE_LIGHT, C_STONE_DARK, rng, subdiv=2, warp=0.20, strata=0.12, rot_deg=rot)
    build(mb)
    col_piece('col_arch_left', pts_l)
    col_piece('col_arch_right', pts_r)
    col_piece('col_arch_bridge', pts_b)
    export_glb(outdir, 'rock_arch.glb')

def gen_dock_pier(outdir):
    clear_scene()
    rng = random.Random(SEED + 101)
    mb = MB('DockPier', seed=101)
    DECK_Y = 1.35
    W = 3.6
    HW = W * 0.5          # 1.80 m
    L = 16.0              # z from 0.0 to -16.0
    PILING_BOT = -10.5    # extends deep below -9 m so pilings plant firmly in deep water!

    # Heavy longitudinal stringers under deck
    for sx in (-1.45, -0.50, 0.50, 1.45):
        box2(mb, (sx - 0.11, DECK_Y - 0.34, -L + 0.15), (sx + 0.11, DECK_Y - 0.10, 0.2), 'wood', jit(C_DARK, rng, 0.05), 0.018, (0, 0, 1))

    # Cross-beams & deep timber pilings every 3.2 m
    z_bents = [0.0, -3.2, -6.4, -9.6, -12.8, -15.6]
    for bi, zb in enumerate(z_bents):
        # Cross cap timber
        cbox(mb, (0.0, DECK_Y - 0.36, zb), (W + 0.10, 0.24, 0.24), 'wood', jit(C_DARK, rng, 0.06), 0.02, (1, 0, 0))
        # Diagonal sway brace between pilings
        for sgn in (-1, 1):
            tube(mb, [(sgn * 1.56, DECK_Y - 0.45, zb), (-sgn * 1.56, DECK_Y - 2.35, zb)], 0.075, 5, 'wood', C_WEATH, mode='flat')
        for sx in (-1.58, 1.58):
            # Piling rises above deck as mooring post on alternate & end bents
            is_bollard = (bi in (0, 2, 4, 5))
            top_y = DECK_Y + (0.88 if is_bollard else -0.10)
            # Barnacle-darkened underwater section + weathered timber above
            with xf(mb, T(sx, 0.0, zb)):
                cyl(mb, 0.20, PILING_BOT, -0.35, 8, 'wood', C_TAR, False, 0.0, 0.19)
                cyl(mb, 0.19, -0.35, top_y, 8, 'wood', jit(C_WEATH, rng, 0.07), False, 0.02, 0.175)
                if is_bollard:
                    # Forged iron collar + beveled timber cap + wrapped mooring rope
                    cyl(mb, 0.188, top_y - 0.16, top_y - 0.06, 8, 'iron', C_IRON, False, 0.008)
                    with xf(mb, T(0, DECK_Y + 0.34, 0)):
                        for ri in range(3):
                            with xf(mb, T(0, ri * 0.048, 0)):
                                torus(mb, 0.185, 0.024, 10, 5, 'rope', C_ROPE, True)
            if is_bollard:
                col_box('col_post_%d_%s' % (bi, 'R' if sx > 0 else 'L'),
                        (sx - 0.20, DECK_Y, zb - 0.20), (sx + 0.20, top_y, zb + 0.20))

    # Individual chunky weathered deck planks (top surface right at y = +1.35 m)
    z = 0.05
    plank_idx = 0
    while z > -L:
        pw = rng.uniform(0.32, 0.40)
        z0 = max(-L, z - pw + 0.022)
        z1 = z
        yc = DECK_Y - 0.05 + rng.uniform(-0.006, 0.006)
        w_jit = W + rng.uniform(-0.06, 0.08)
        pcol = jit(C_DECK if plank_idx % 3 != 0 else C_WEATH, rng, 0.08, 0.025)
        cbox(mb, (rng.uniform(-0.02, 0.02), yc, 0.5 * (z0 + z1)), (w_jit, 0.10, z1 - z0), 'wood', pcol, 0.015, (1, 0, 0))
        z -= pw
        plank_idx += 1

    # Low timber curb rails along outer edges (with generous mooring gaps!)
    for sx in (-1.68, 1.68):
        for seg_z0, seg_z1 in ((-0.4, -2.8), (-3.6, -6.0), (-6.8, -9.2), (-10.0, -12.4), (-13.2, -15.2)):
            cbox(mb, (sx, DECK_Y + 0.07, 0.5 * (seg_z0 + seg_z1)), (0.14, 0.12, abs(seg_z1 - seg_z0)), 'wood', C_DARK, 0.014, (0, 0, 1))

    # Landward timber ramp (z = 0.0 to +2.2, descending smoothly from y = 1.35 to y = 0.12 so pawns walk straight on!)
    ramp_steps = 6
    for i in range(ramp_steps):
        t0 = i / float(ramp_steps)
        t1 = (i + 1) / float(ramp_steps)
        rz0 = t0 * 2.2
        rz1 = t1 * 2.2
        ry = DECK_Y - 0.05 - (DECK_Y - 0.12) * (0.5 * (t0 + t1))
        cbox(mb, (0.0, ry, 0.5 * (rz0 + rz1)), (W - 0.08, 0.12, (rz1 - rz0) * 0.96), 'wood', jit(C_DECK, rng, 0.07), 0.014, (1, 0, 0))
    for sx in (-1.45, 0.0, 1.45):
        tube(mb, [(sx, DECK_Y - 0.18, 0.0), (sx, -0.05, 2.3)], 0.12, 4, 'wood', C_DARK, mode='flat')

    # Coiled mooring ropes & dock cleats
    rope_coil(mb, (-1.28, DECK_Y, -4.4), 0.24, 3)
    rope_coil(mb, (1.28, DECK_Y, -11.4), 0.22, 3)
    for zb in (-4.8, -11.0, -14.8):
        cbox(mb, (1.52, DECK_Y + 0.06, zb), (0.14, 0.09, 0.44), 'iron', C_IRON, 0.015)

    # Tall crooked timber lantern post at pier head (-1.52, z = -15.3)
    lx, lz = -1.52, -15.3
    tube(mb, [(lx, DECK_Y - 0.1, lz), (lx - 0.06, DECK_Y + 1.6, lz - 0.04), (lx + 0.02, DECK_Y + 3.25, lz + 0.05)], [0.11, 0.095, 0.08], 6, 'wood', C_DARK, mode='flat')
    # Cross-arm + iron hook + glowing hanging lantern
    cbox(mb, (lx + 0.36, DECK_Y + 3.12, lz + 0.05), (0.92, 0.11, 0.11), 'wood', C_DARK, 0.015)
    tube(mb, [(lx + 0.02, DECK_Y + 2.55, lz + 0.05), (lx + 0.55, DECK_Y + 3.10, lz + 0.05)], 0.04, 4, 'wood', C_WEATH, mode='flat')
    lantern_pos = (lx + 0.72, DECK_Y + 2.74, lz + 0.05)
    tube(mb, [(lx + 0.72, DECK_Y + 3.06, lz + 0.05), (lx + 0.72, lantern_pos[1] + 0.30, lz + 0.05)], 0.016, 5, 'iron', C_IRON)
    build_lantern_geom(mb, lantern_pos, scale=1.25, hanging=True)

    build(mb)
    add_empty('Lantern_Dock', lantern_pos)

    # Collision pieces: cleanly walkable deck + gentle ramp + under-deck solid (never wider than ±1.78 m!)
    col_box('col_dock_deck', (-HW + 0.02, DECK_Y - 0.40, -L), (HW - 0.02, DECK_Y, 0.04))
    col_piece('col_dock_ramp', [
        (sx * (HW - 0.05), y, z)
        for sx in (-1, 1)
        for (y, z) in ((DECK_Y, 0.04), (DECK_Y - 0.35, 0.04), (0.12, 2.25), (-0.30, 2.25))
    ])
    export_glb(outdir, 'dock_pier.glb')

def gen_outpost_tavern(outdir):
    clear_scene()
    rng = random.Random(SEED + 127)
    mb = MB('OutpostTavern', seed=127)

    # Dimensions: main hall x = -4.6..+4.6 (9.2 m), z = -3.4..+3.6 (7.0 m), front porch z = -3.4..-5.6
    FLOOR_Y = 0.58
    EAVE_Y = 3.85
    RIDGE_Y = 7.15

    # Chunky stone masonry foundation plinth (extends to y = -1.8 m for sloped terraces!)
    box2(mb, (-4.85, -1.8, -3.65), (4.85, FLOOR_Y, 3.85), 'stone', C_STONE_MID, 0.06)
    # Corner stone quoins
    for sx in (-4.78, 4.78):
        for sz in (-3.58, 3.78):
            for yi in range(3):
                cbox(mb, (sx, -0.5 + yi * 0.42, sz), (0.58, 0.38, 0.58), 'stone', jit(C_STONE_LIGHT, rng, 0.07), 0.03)

    # Slightly flared whimsical pirate walls (wider at eaves by 0.25 m!)
    secs = [
        [(-4.55, FLOOR_Y, -3.35), (4.55, FLOOR_Y, -3.35), (4.55, FLOOR_Y, 3.55), (-4.55, FLOOR_Y, 3.55)],
        [(-4.82, EAVE_Y, -3.56), (4.82, EAVE_Y, -3.56), (4.82, EAVE_Y, 3.76), (-4.82, EAVE_Y, 3.76)],
    ]
    loft(mb, secs, 'paint', C_PLASTER, closed=True, caps=(True, True), mode='flat', scols=[C_PLASTER])

    # Gable triangles (left & right ends along X)
    for sx in (-1, 1):
        gx = sx * 4.80
        g_pts = [(gx, EAVE_Y - 0.05, -3.56), (gx, EAVE_Y - 0.05, 3.76), (gx, RIDGE_Y - 0.15, 0.10)]
        mb.fp(g_pts, 'paint', C_PLASTER_SH, (0, 0, 1), (0, EAVE_Y, 0))

    # Heavy dark-oak half-timber framing (corner posts, horizontals, diagonal X-braces)
    for sx in (-1, 1):
        for sz in (-1, 1):
            tube(mb, [(sx * 4.62, FLOOR_Y, sz * 3.42), (sx * 4.90, EAVE_Y + 0.05, sz * 3.64)], 0.18, 4, 'wood', C_DARK, mode='flat')
    for y_beam in (FLOOR_Y + 0.10, 2.20, EAVE_Y - 0.06):
        t = (y_beam - FLOOR_Y) / (EAVE_Y - FLOOR_Y)
        bx = 4.60 + 0.26 * t
        bz = 3.42 + 0.20 * t
        cbox(mb, (0, y_beam, -bz), (bx * 2.0 + 0.25, 0.22, 0.22), 'wood', C_DARK, 0.02)
        cbox(mb, (0, y_beam, bz), (bx * 2.0 + 0.25, 0.22, 0.22), 'wood', C_DARK, 0.02)
        cbox(mb, (-bx, y_beam, 0.10), (0.22, 0.22, bz * 2.0 + 0.25), 'wood', C_DARK, 0.02)
        cbox(mb, (bx, y_beam, 0.10), (0.22, 0.22, bz * 2.0 + 0.25), 'wood', C_DARK, 0.02)
    # Front/back vertical studs & diagonal braces
    for sx in (-2.2, 2.2):
        for sz in (-3.50, 3.70):
            cbox(mb, (sx, 2.20, sz), (0.22, 3.25, 0.22), 'wood', C_DARK, 0.02)
        tube(mb, [(sx, FLOOR_Y + 0.2, -3.48), (sx + (1.8 if sx > 0 else -1.8), 2.15, -3.54)], 0.09, 4, 'wood', C_DARK, mode='flat')

    # Steep pitched weathered cedar-shake roof with staggered seams, chunky overhang & roof sag
    courses = 6
    for side_z in (-1, 1):
        for ci in range(courses):
            f0 = ci / float(courses)
            f1 = min(1.02, (ci + 1) / float(courses) + 0.025)
            y0 = RIDGE_Y - (RIDGE_Y - EAVE_Y + 0.45) * f0
            y1 = RIDGE_Y - (RIDGE_Y - EAVE_Y + 0.45) * f1
            z0 = 0.10 + side_z * (4.65 * f0)
            z1 = 0.10 + side_z * (4.65 * f1)
            # Organically staggered cedar shake widths (zero aligned grid or checkerboard!)
            xs = [-5.65]
            cur_x = -5.65 + (rng.uniform(0.42, 0.64) if ci % 2 == 1 else rng.uniform(0.80, 1.12))
            while cur_x < 5.65 - 0.55:
                xs.append(cur_x)
                cur_x += rng.uniform(0.76, 1.18)
            xs.append(5.65)
            prev_pal_idx = -1
            for si in range(len(xs) - 1):
                x0, x1 = xs[si], xs[si + 1]
                xm = 0.5 * (x0 + x1)
                sag = -0.14 * (1.0 - (xm / 5.65) ** 2)
                th = 0.165 + rng.uniform(-0.020, 0.026)
                lip_dy = rng.uniform(-0.016, 0.014)
                # Pick organically from warm weathered cedar/terracotta/umber palette
                pal_idx = rng.randrange(len(C_CEDAR_PALETTE))
                if pal_idx == prev_pal_idx and rng.random() < 0.65:
                    pal_idx = (pal_idx + rng.randint(1, len(C_CEDAR_PALETTE) - 1)) % len(C_CEDAR_PALETTE)
                prev_pal_idx = pal_idx
                base_sh = mix(C_CEDAR_PALETTE[pal_idx], C_DARK, 0.12 * f0)
                c_sh = jit(base_sh, rng, 0.075, 0.022)
                mb.newoff()
                p_top = [(x0, y0 + sag + th, z0), (x1, y0 + sag + th, z0), (x1, y1 + sag + th + lip_dy, z1), (x0, y1 + sag + th + lip_dy, z1)]
                p_bot = [(x0, y0 + sag, z0), (x1, y0 + sag, z0), (x1, y1 + sag + lip_dy, z1), (x0, y1 + sag + lip_dy, z1)]
                mb.fp(p_top, 'wood', c_sh, (1, 0, 0), (xm, y0 - 2.0, 0.10))
                mb.fp(p_bot, 'wood', mul(c_sh, 0.65), (1, 0, 0), (xm, y0 + 2.0, 0.10))
                # Front lip edge of shake course
                mb.fp([p_bot[3], p_bot[2], p_top[2], p_top[3]], 'wood', mul(c_sh, 0.78), (1, 0, 0), (xm, y0, 0.10))
    # Heavy ridge cap timber + crimson bargeboards
    cbox(mb, (0.0, RIDGE_Y + 0.12, 0.10), (11.6, 0.32, 0.34), 'wood', C_DARK, 0.03)
    for sx in (-5.62, 5.62):
        for side_z in (-1, 1):
            tube(mb, [(sx, RIDGE_Y + 0.05, 0.10), (sx, EAVE_Y - 0.38, 0.10 + side_z * 4.65)], 0.14, 4, 'wood', C_RED, mode='flat')

    # Rustic crooked stone chimney on +X rear roof slope
    chim_x, chim_z = 3.25, 1.85
    box2(mb, (chim_x - 0.62, EAVE_Y - 0.5, chim_z - 0.62), (chim_x + 0.62, RIDGE_Y + 0.65, chim_z + 0.62), 'stone', C_STONE_MID, 0.05)
    cbox(mb, (chim_x + 0.05, RIDGE_Y + 0.85, chim_z), (1.42, 0.28, 1.42), 'stone', C_STONE_LIGHT, 0.04)
    cbox(mb, (chim_x + 0.05, RIDGE_Y + 1.05, chim_z), (0.90, 0.18, 0.90), 'stone', C_CHAR, 0.02)

    # Welcoming covered front timber porch (z = -3.4..-5.65, floor y = 0.58)
    box2(mb, (-4.55, -1.6, -5.65), (4.55, FLOOR_Y, -3.45), 'wood', C_DECK, 0.025)
    # Wide welcoming wooden steps down to ground (z = -5.65..-6.75)
    for si in range(3):
        sy = FLOOR_Y - (si + 1) * 0.19
        sz = -5.85 - si * 0.34
        cbox(mb, (0.0, sy, sz), (2.75, 0.20, 0.36), 'wood', jit(C_DECK, rng, 0.06), 0.02)
    # Porch posts & railing (leaving center doorway lane open!)
    for px in (-4.30, -1.55, 1.55, 4.30):
        cbox(mb, (px, FLOOR_Y + 1.40, -5.42), (0.24, 2.80, 0.24), 'wood', C_DARK, 0.02)
        col_box('col_porch_post_%d' % int(px * 10), (px - 0.14, FLOOR_Y, -5.56), (px + 0.14, FLOOR_Y + 2.8, -5.28))
    for rx in (-2.92, 2.92):
        cbox(mb, (rx, FLOOR_Y + 0.92, -5.42), (2.60, 0.12, 0.14), 'wood', C_HULL, 0.015)
        for bi in range(4):
            bx = rx - 0.95 + bi * 0.63
            cbox(mb, (bx, FLOOR_Y + 0.46, -5.42), (0.09, 0.82, 0.09), 'wood', C_WEATH, 0.01)
    # Slanted porch overhang roof (shelters porch from rain!)
    p_r_top = [(-4.75, 3.72, -3.45), (4.75, 3.72, -3.45), (4.75, 3.12, -6.05), (-4.75, 3.12, -6.05)]
    p_r_bot = [(p[0], p[1] - 0.18, p[2]) for p in p_r_top]
    mb.fp(p_r_top, 'wood', C_THATCH, (1, 0, 0), (0, 1.0, -4.5))
    mb.fp(p_r_bot, 'wood', mul(C_DARK, 0.8), (1, 0, 0), (0, 5.0, -4.5))
    mb.fp([p_r_bot[3], p_r_bot[2], p_r_top[2], p_r_top[3]], 'wood', C_RED, (1, 0, 0), (0, 3.4, -3.0))

    # Heavy pirate plank front door with brass ring & iron hinges
    cbox(mb, (0.0, FLOOR_Y + 1.15, -3.46), (1.42, 2.26, 0.18), 'wood', C_HULL, 0.025)
    cbox(mb, (0.0, FLOOR_Y + 2.34, -3.50), (1.72, 0.20, 0.26), 'wood', C_DARK, 0.02)
    for hy in (FLOOR_Y + 0.65, FLOOR_Y + 1.72):
        cbox(mb, (-0.36, hy, -3.56), (0.62, 0.09, 0.04), 'iron', C_IRON, 0.008)
    with xf(mb, T(0.42, FLOOR_Y + 1.08, -3.58) @ M_Y2Z):
        torus(mb, 0.08, 0.02, 10, 5, 'brass', C_BRASS, True)

    # Glowing warm multi-pane tavern windows (mat_window_glass!)
    def add_window(pos, rot_y, w=1.25, h=1.18):
        with xf(mb, T(pos) @ R('Y', rot_y)):
            # Outer timber sill & frame
            cbox(mb, (0, -h * 0.5 - 0.06, -0.06), (w + 0.34, 0.14, 0.26), 'wood', C_DARK, 0.02)
            cbox(mb, (0, h * 0.5 + 0.05, -0.04), (w + 0.28, 0.14, 0.22), 'wood', C_DARK, 0.02)
            for sx in (-w * 0.5 - 0.07, w * 0.5 + 0.07):
                cbox(mb, (sx, 0, -0.04), (0.14, h + 0.12, 0.20), 'wood', C_DARK, 0.02)
            # Painted teal shutters swung open beside window
            for sx in (-1, 1):
                cbox(mb, (sx * (w * 0.5 + 0.34), 0, -0.04), (0.38, h, 0.07), 'wood', C_TEAL, 0.015)
            # Glowing warm glass pane
            cbox(mb, (0, 0, 0.0), (w, h, 0.06), 'window', C_GLASS, 0.0)
            # Mullion crossbars
            cbox(mb, (0, 0, -0.04), (w, 0.07, 0.06), 'wood', C_DARK, 0.008)
            cbox(mb, (0, 0, -0.04), (0.07, h, 0.06), 'wood', C_DARK, 0.008)

    add_window((-2.95, FLOOR_Y + 1.55, -3.50), 0.0)
    add_window((2.95, FLOOR_Y + 1.55, -3.50), 0.0)
    add_window((-4.76, FLOOR_Y + 1.55, 0.10), 90.0, 1.45, 1.18)
    add_window((4.76, FLOOR_Y + 1.55, 0.10), -90.0, 1.45, 1.18)
    add_window((0.0, FLOOR_Y + 1.55, 3.70), 180.0, 1.60, 1.15)
    add_window((-4.85, EAVE_Y + 1.15, 0.10), 90.0, 1.05, 1.05)  # Attic gable glow!
    add_window((4.85, EAVE_Y + 1.15, 0.10), -90.0, 1.05, 1.05)

    # Hanging tavern signboard on porch corner
    cbox(mb, (2.25, 2.95, -5.65), (0.10, 0.10, 1.15), 'iron', C_IRON, 0.01)
    cbox(mb, (2.25, 2.48, -6.05), (0.98, 0.62, 0.10), 'wood', C_RED, 0.02)
    cbox(mb, (2.25, 2.48, -6.05), (0.76, 0.42, 0.12), 'wood', C_GOLD, 0.015)

    # Hanging warm porch lantern right above the front steps
    lantern_pos = (0.0, 2.75, -5.55)
    tube(mb, [(0.0, 3.18, -5.55), (0.0, 3.00, -5.55)], 0.015, 5, 'iron', C_IRON)
    build_lantern_geom(mb, lantern_pos, scale=1.15, hanging=True)

    build(mb)
    add_empty('Lantern_Tavern', lantern_pos)

    # Collision pieces: main solid building + walkable porch floor + ramp steps + porch roof
    col_box('col_tavern_body', (-4.85, -1.6, -3.60), (4.85, EAVE_Y + 0.5, 3.80))
    col_box('col_tavern_porch_floor', (-4.55, -1.6, -5.65), (4.55, FLOOR_Y, -3.45))
    col_piece('col_tavern_steps', [
        (sx * 1.40, y, z)
        for sx in (-1, 1)
        for (y, z) in ((FLOOR_Y, -5.65), (0.0, -5.65), (0.0, -6.85), (-0.4, -6.85))
    ])
    col_box('col_tavern_porch_roof', (-4.75, 3.05, -6.05), (4.75, 3.75, -3.45))
    export_glb(outdir, 'outpost_tavern.glb')

def gen_outpost_stall(outdir):
    clear_scene()
    rng = random.Random(SEED + 151)
    mb = MB('OutpostStall', seed=151)

    # Timber floor platform (plinth extends down to -1.2 m so it never floats!)
    box2(mb, (-2.45, -1.20, -1.45), (2.45, 0.14, 1.55), 'wood', C_WEATH, 0.025)

    # Four sturdy corner timber posts + diagonal brackets
    for sx in (-2.22, 2.22):
        cbox(mb, (sx, 1.55, -1.15), (0.20, 3.10, 0.20), 'wood', C_DARK, 0.02)
        cbox(mb, (sx, 1.38, 1.32), (0.20, 2.76, 0.20), 'wood', C_DARK, 0.02)
        tube(mb, [(sx, 2.30, -1.15), (sx - (0.65 if sx > 0 else -0.65), 2.95, -1.15)], 0.06, 4, 'wood', C_HULL, mode='flat')

    # Chunky plank trading counter (front z = -1.05, top at y = 1.08)
    box2(mb, (-2.20, 0.14, -1.22), (2.20, 0.98, -0.52), 'wood', C_HULL, 0.02)
    cbox(mb, (0.0, 1.04, -0.88), (4.62, 0.12, 0.88), 'wood', C_DECK, 0.02)
    # Decorative painted front trim & emblem
    cbox(mb, (0.0, 0.56, -1.24), (3.90, 0.62, 0.06), 'wood', C_TEAL, 0.012)
    cbox(mb, (0.0, 0.58, -1.27), (0.72, 0.44, 0.05), 'brass', C_GOLD, 0.01)

    # Striped red-and-cream canvas awning with gentle sag & scalloped valance!
    stripes = 9
    for si in range(stripes):
        x0 = -2.55 + (5.10 * si / stripes)
        x1 = -2.55 + (5.10 * (si + 1) / stripes)
        col = C_RED if si % 2 == 0 else C_CREAM
        # 3 segments front-to-back for slight billowing sag
        pts_z = [-1.62, -0.65, 0.45, 1.62]
        pts_y = [3.16, 2.94, 2.82, 2.66]
        for zi in range(3):
            q = [(x0, pts_y[zi], pts_z[zi]), (x1, pts_y[zi], pts_z[zi]), (x1, pts_y[zi + 1], pts_z[zi + 1]), (x0, pts_y[zi + 1], pts_z[zi + 1])]
            mb.fp(q, 'awning', col, (0, 0, 1), None, smooth=True)
        # Hanging front valance flap
        val = [(x0, 3.16, -1.62), (x1, 3.16, -1.62), (x1 - 0.05, 2.74, -1.68), (x0 + 0.05, 2.74, -1.68)]
        mb.fp(val, 'awning', mul(col, 0.94), (0, 1, 0), None, smooth=False)

    # Brass merchant balance scales on counter
    scx, scy, scz = -1.05, 1.10, -0.86
    with xf(mb, T(scx, scy, scz)):
        cyl(mb, 0.14, 0.0, 0.06, 8, 'brass', C_BRASS, False, 0.01, 0.10)
        cyl(mb, 0.025, 0.06, 0.56, 6, 'brass', C_BRASS, False)
        cbox(mb, (0.0, 0.54, 0.0), (0.56, 0.035, 0.035), 'brass', C_GOLD, 0.006, M=R('Z', 6))
        for sgn, dy in ((-1, -0.03), (1, 0.03)):
            px = sgn * 0.25
            for chain_a in (0.0, 2.1, 4.2):
                tube(mb, [(px, 0.54 + dy, 0), (px + cos(chain_a) * 0.10, 0.28 + dy, sin(chain_a) * 0.10)], 0.006, 3, 'brass', C_BRASS)
            with xf(mb, T(px, 0.24 + dy, 0)):
                cyl(mb, 0.12, 0.0, 0.04, 8, 'brass', C_GOLD, False, 0.005, 0.09)

    # Merchant ledger & small pile of gold coins on counter
    cbox(mb, (0.65, 1.13, -0.82), (0.44, 0.07, 0.34), 'paint', C_CREAM, 0.01, M=R('Y', -14))
    for ci in range(5):
        with xf(mb, T(0.18 + ci * 0.055, 1.10, -0.92 + (ci % 2) * 0.05)):
            cyl(mb, 0.032, 0.0, 0.03 + 0.02 * (ci % 3), 6, 'brass', C_GOLD, False)

    # Stacked merchant chests & barrels tucked behind & beside counter
    # Back stacked chests
    for cx, cy, cz, ry in ((1.25, 0.14, 0.65, -18), (1.20, 0.62, 0.68, 12), (-1.45, 0.14, 0.72, 22)):
        with xf(mb, T(cx, cy, cz) @ R('Y', ry)):
            cbox(mb, (0, 0.22, 0), (0.72, 0.44, 0.48), 'wood', jit(C_DARK, rng, 0.08), 0.02)
            for bx in (-0.28, 0.28):
                cbox(mb, (bx, 0.22, 0), (0.07, 0.46, 0.50), 'brass', C_BRASS, 0.008)
    # Side barrels
    for bx, bz in ((-2.78, 0.25), (2.72, 0.10), (2.82, 0.82)):
        with xf(mb, T(bx, 0.0, bz)):
            lathe(mb, [(0, 0), (0.26, 0), (0.31, 0.28), (0.31, 0.58), (0.26, 0.86), (0, 0.86)], 10, 'wood', jit(C_HULL, rng, 0.08), False)
            for hy in (0.18, 0.68):
                cyl(mb, 0.315, hy, hy + 0.05, 10, 'iron', C_IRON, False)

    # Hanging lantern from front awning beam
    lantern_pos = (1.62, 2.52, -1.18)
    tube(mb, [(1.62, 2.98, -1.18), (1.62, 2.76, -1.18)], 0.014, 4, 'iron', C_IRON)
    build_lantern_geom(mb, lantern_pos, scale=1.05, hanging=True)

    build(mb)
    add_empty('Lantern_Stall', lantern_pos)
    col_box('col_stall_counter', (-2.30, -0.5, -1.35), (2.30, 1.12, -0.45))
    col_box('col_stall_back', (-2.40, -0.5, 0.20), (2.40, 1.60, 1.55))
    col_box('col_stall_roof', (-2.55, 2.62, -1.65), (2.55, 3.22, 1.65))
    export_glb(outdir, 'outpost_stall.glb')

def gen_beacon_tower(outdir):
    clear_scene()
    rng = random.Random(SEED + 179)
    mb = MB('BeaconTower', seed=179)

    # Iconic ~20.5 m coastal lighthouse / watchtower readable from kilometres at sea!
    # 1. Octagonal battered stone masonry base (y = -2.5..+6.2)
    lathe(mb, [(0, -2.5), (3.55, -2.5), (3.40, 0.4), (2.85, 3.6), (2.48, 6.2), (0, 6.2)], 8, 'stone', C_STONE_MID, False)
    # Stone buttress ribs around the base for dramatic silhouette
    for k in range(4):
        ang = k * 90.0 + 45.0
        with xf(mb, R('Y', ang)):
            cbox(mb, (0.0, 1.6, 2.95), (0.85, 6.4, 1.10), 'stone', jit(C_STONE_LIGHT, rng, 0.07), 0.05, M=R('X', -12))
    # Stone cornice ring at y = 6.2
    cyl(mb, 2.75, 5.95, 6.38, 8, 'stone', C_STONE_LIGHT, False, 0.06, 2.62)
    # Arched timber entry door on -Z face
    cbox(mb, (0.0, 1.30, -3.22), (1.35, 2.40, 0.35), 'wood', C_DARK, 0.03)
    cbox(mb, (0.0, 1.30, -3.32), (1.05, 2.10, 0.22), 'wood', C_HULL, 0.02)

    # 2. Bold maritime banded tower shaft (y = 6.3..16.2) with crimson/cream bands for horizon contrast!
    bands = [
        (6.35, 8.8, 2.38, 2.18, 'paint', C_CREAM),
        (8.8, 11.4, 2.18, 1.98, 'paint', C_RED),
        (11.4, 13.9, 1.98, 1.80, 'paint', C_CREAM),
        (13.9, 16.2, 1.80, 1.66, 'paint', C_RED),
    ]
    for y0, y1, r0, r1, mat, col in bands:
        cyl(mb, r0, y0, y1, 8, mat, col, False, 0.03, r1)
    # Exterior chunky dark-oak corner ribs & X-bracing timbers
    for k in range(8):
        ang = 2.0 * pi * k / 8.0 + pi / 8.0
        p0 = Vector((cos(ang) * 2.42, 6.2, sin(ang) * 2.42))
        p1 = Vector((cos(ang) * 1.72, 16.2, sin(ang) * 1.72))
        tube(mb, [p0, p1], 0.13, 4, 'wood', C_DARK, mode='flat')
    # Warm tower slit windows
    for wy, wang in ((8.0, 0), (10.5, 90), (13.0, 180), (14.8, -90)):
        r_at = 2.40 - (wy - 6.2) * 0.072
        with xf(mb, R('Y', wang) @ T(0, wy, -r_at - 0.04)):
            cbox(mb, (0, 0, 0), (0.62, 1.05, 0.16), 'wood', C_DARK, 0.02)
            cbox(mb, (0, 0, -0.05), (0.42, 0.82, 0.10), 'window', C_GLASS, 0.0)

    # 3. Cantilevered wooden watch gallery deck (y = 16.2, radius 3.05 m!)
    cyl(mb, 3.08, 16.0, 16.32, 8, 'wood', C_DECK, False, 0.04, 3.08)
    for k in range(8):
        ang = 2.0 * pi * k / 8.0
        c, s = cos(ang), sin(ang)
        # Diagonal corbel brackets supporting gallery
        tube(mb, [(c * 1.65, 14.3, s * 1.65), (c * 2.90, 16.05, s * 2.90)], 0.13, 4, 'wood', C_DARK, mode='flat')
        # Gallery balustrade posts
        cbox(mb, (c * 2.86, 16.82, s * 2.86), (0.18, 1.05, 0.18), 'wood', C_DARK, 0.015)
        ang2 = 2.0 * pi * ((k + 1) % 8) / 8.0
        p_a = Vector((c * 2.86, 17.28, s * 2.86))
        p_b = Vector((cos(ang2) * 2.86, 17.28, sin(ang2) * 2.86))
        tube(mb, [p_a, p_b], 0.09, 4, 'wood', C_RED, mode='flat')

    # 4. Giant glowing brazier / lantern crown (y = 16.32..20.6)
    # Iron brazier pedestal & glowing embers + huge golden lantern glass core
    cyl(mb, 1.48, 16.32, 16.85, 8, 'iron', C_IRON, False, 0.04, 1.62)
    cyl(mb, 1.38, 16.85, 18.75, 8, 'glass', C_GLASS, False, 0.0, 1.38)
    ellipsoid(mb, (0.0, 17.45, 0.0), (1.05, 0.65, 1.05), 'embers', C_EMBER, 8, 5)
    # 8 forged iron lantern mullions
    for k in range(8):
        ang = 2.0 * pi * k / 8.0
        cbox(mb, (cos(ang) * 1.46, 17.80, sin(ang) * 1.46), (0.14, 2.05, 0.14), 'iron', C_IRON, 0.015)
    # Conical patinated copper-teal lantern roof & spire finial (reaches ~21.2 m!)
    lathe(mb, [(0, 18.72), (2.25, 18.72), (2.15, 18.96), (1.15, 19.85), (0.28, 20.65), (0.0, 21.15)], 8, 'paint', C_COPPER, False)
    cyl(mb, 0.07, 20.6, 21.8, 6, 'brass', C_GOLD, False)
    ellipsoid(mb, (0.0, 21.35, 0.0), (0.22, 0.22, 0.22), 'brass', C_GOLD, 8, 5)

    build(mb)
    add_empty('Lantern_Beacon', (0.0, 17.80, 0.0))
    col_piece('col_beacon_base', [(3.35 * cos(k * pi / 4), y, 3.35 * sin(k * pi / 4)) for k in range(8) for y in (-2.0, 6.2)])
    col_piece('col_beacon_shaft', [(2.35 * cos(k * pi / 4), y, 2.35 * sin(k * pi / 4)) for k in range(8) for y in (6.2, 16.2)])
    col_piece('col_beacon_gallery', [(3.05 * cos(k * pi / 4), y, 3.05 * sin(k * pi / 4)) for k in range(8) for y in (16.0, 18.8)])
    export_glb(outdir, 'beacon_tower.glb')

def gen_chest_treasure(outdir):
    clear_scene()
    rng = random.Random(SEED + 211)
    mb = MB('TreasureChest', seed=211)

    # Dimensions: ~0.66 m wide (X) x 0.44 m tall (Y, 0..0.44) x 0.44 m deep (Z)
    # Tapered chunky oak lower body (y = 0.02..0.28)
    secs = [
        [(-0.30, 0.02, -0.19), (0.30, 0.02, -0.19), (0.30, 0.02, 0.19), (-0.30, 0.02, 0.19)],
        [(-0.325, 0.28, -0.215), (0.325, 0.28, -0.215), (0.325, 0.28, 0.215), (-0.325, 0.28, 0.215)],
    ]
    loft(mb, secs, 'wood', C_DARK, True, (True, True), 'flat')
    # Chunky wood corner feet
    for sx in (-0.27, 0.27):
        for sz in (-0.16, 0.16):
            cbox(mb, (sx, 0.015, sz), (0.09, 0.03, 0.09), 'brass', C_BRASS, 0.005)

    # Domed slatted pirate chest lid (y = 0.28..0.44, curved arch in YZ extruded along X)
    lid_n = 7
    lid_secs = []
    for x in (-0.328, 0.328):
        ring = []
        for i in range(lid_n + 1):
            ang = pi * i / float(lid_n)
            rz = -0.218 * cos(ang)
            ry = 0.28 + 0.155 * sin(ang)
            ring.append((x, ry, rz))
        lid_secs.append(ring)
    loft(mb, lid_secs, 'wood', C_HULL, closed=True, caps=(True, True), mode='flat')

    # Decorative crimson-and-gold crest plaque on lid top
    cbox(mb, (0.0, 0.435, 0.0), (0.24, 0.024, 0.16), 'paint', C_RED, 0.005)
    cbox(mb, (0.0, 0.444, 0.0), (0.14, 0.018, 0.09), 'brass', C_GOLD, 0.004)

    # Heavy riveted brass straps wrapping body & lid!
    for sx in (-0.245, 0.245):
        cbox(mb, (sx, 0.15, 0.0), (0.056, 0.27, 0.445), 'brass', C_BRASS, 0.006)
        # Curved brass strap over domed lid
        strap_secs = []
        for dx in (-0.028, 0.028):
            ring = []
            for i in range(lid_n + 1):
                ang = pi * i / float(lid_n)
                ring.append((sx + dx, 0.28 + 0.164 * sin(ang), -0.226 * cos(ang)))
            strap_secs.append(ring)
        loft(mb, strap_secs, 'brass', C_GOLD, closed=True, caps=(True, True), mode='flat')
    # Rim trim & corner brackets
    cbox(mb, (0.0, 0.282, 0.0), (0.665, 0.042, 0.442), 'brass', C_BRASS, 0.006)
    for sx in (-0.318, 0.318):
        for sz in (-0.208, 0.208):
            cbox(mb, (sx, 0.06, sz), (0.065, 0.08, 0.065), 'brass', C_GOLD, 0.006)

    # Chunky front brass lockplate & hanging padlock (on -Z front face)
    cbox(mb, (0.0, 0.26, -0.226), (0.13, 0.14, 0.028), 'brass', C_GOLD, 0.005)
    cbox(mb, (0.0, 0.21, -0.246), (0.085, 0.095, 0.036), 'brass', C_BRASS, 0.008)
    with xf(mb, T(0.0, 0.265, -0.244) @ M_Y2Z):
        torus(mb, 0.030, 0.009, 8, 5, 'iron', C_IRON, False)

    # Side carrying ring handles (+X / -X)
    for sx in (-1, 1):
        cbox(mb, (sx * 0.33, 0.17, 0.0), (0.028, 0.08, 0.12), 'brass', C_BRASS, 0.005)
        with xf(mb, T(sx * 0.348, 0.14, 0.0) @ R('Z', 90)):
            torus(mb, 0.052, 0.013, 10, 5, 'iron', C_IRON, True)

    build(mb)
    export_glb(outdir, 'chest_treasure.glb')

def gen_dig_mound(outdir):
    clear_scene()
    rng = random.Random(SEED + 241)
    mb = MB('DigMound', seed=241)

    # Sculpted irregular disturbed sand mound (~1.65 m diameter, skirt down to -0.22 m for seamless slope blending)
    rings = 5
    segs = 14
    secs = []
    scols = []
    radii_r = [0.88, 0.72, 0.48, 0.26, 0.06]
    heights_r = [-0.22, 0.04, 0.22, 0.31, 0.28]  # subtle scooped dimple at very top!
    cols_r = [C_SAND, C_SAND_DARK, C_SAND, C_SAND_DARK, C_SAND_DARK]
    for ri in range(rings):
        ring = []
        for k in range(segs):
            ang = 2.0 * pi * k / segs
            wob = 1.0 + 0.16 * sin(ang * 3.0 + 0.7) + 0.09 * cos(ang * 5.0 - 0.5)
            r = radii_r[ri] * wob
            y = heights_r[ri] + (0.04 * sin(ang * 4.0 + ri) if ri in (1, 2, 3) else 0.0)
            ring.append((cos(ang) * r, y, sin(ang) * r))
        secs.append(ring)
        scols.append(cols_r[ri])
    loft(mb, secs, 'paint', C_SAND, closed=True, caps=(False, True), mode='flat', scols=scols)

    # Scattered coastal pebbles around the disturbed sand
    for i in range(9):
        ang = i * (2.0 * pi / 9.0) + rng.uniform(-0.25, 0.25)
        rr = rng.uniform(0.32, 0.74)
        py = 0.06 + max(0.0, (0.65 - rr) * 0.32)
        sr = rng.uniform(0.055, 0.11)
        faceted_rock(mb, (cos(ang) * rr, py, sin(ang) * rr), (sr * 1.2, sr * 0.7, sr), 'stone',
                     C_STONE_LIGHT, C_STONE_MID, C_STONE_DARK, rng, subdiv=1, warp=0.18, strata=0.05, rot_deg=(0, rng.uniform(0, 360), 0))

    # Subtle crossed weathered driftwood / shovel-mark sticks poking from the sand
    cbox(mb, (0.14, 0.24, -0.08), (0.62, 0.055, 0.11), 'wood', C_DRIFT, 0.01, M=R('Y', 28) @ R('Z', -16))
    cbox(mb, (-0.12, 0.22, 0.10), (0.52, 0.05, 0.09), 'wood', C_WEATH, 0.01, M=R('Y', -42) @ R('Z', 12))

    build(mb)
    export_glb(outdir, 'dig_mound.glb')

def gen_shipwreck_hulk(outdir):
    clear_scene()
    rng = random.Random(SEED + 277)
    mb = MB('ShipwreckHulk', seed=277)

    # Dramatic broken half-sunken pirate ship hulk (~12 m long, listed 18 deg to starboard!)
    tilt = R('Z', -18) @ R('X', 6)
    hull_pts = []
    mast_pts = []

    with xf(mb, tilt):
        # Heavy curved dark-tarred keel + broken stempost
        keel_path = [(0, -1.2, 5.4), (0, -1.2, 1.5), (0, -1.1, -2.2), (0, -0.5, -4.6), (0, 1.2, -5.9), (0, 2.5, -6.3)]
        tube(mb, keel_path, [0.22, 0.24, 0.24, 0.22, 0.19, 0.15], 5, 'wood', C_TAR, mode='flat')

        # 11 jagged curved ship ribs rising like whalebones along the hull!
        for ri in range(11):
            z = -4.8 + ri * 0.96
            t_len = abs(z / 5.6)
            bw = 2.45 * max(0.28, (1.0 - t_len ** 2.2) ** 0.72)
            # Port side mostly intact, starboard side snapped jaggedly
            for sgn, intact in ((-1, True), (1, ri < 4 or ri > 7)):
                h_max = (2.35 if intact else rng.uniform(0.55, 1.65))
                rib = [
                    (0.0, -1.05, z),
                    (sgn * bw * 0.52, -0.82, z),
                    (sgn * bw * 0.92, -0.05, z),
                    (sgn * bw, min(h_max, 1.05), z),
                ]
                if h_max > 1.15:
                    rib.append((sgn * (bw * 0.96), h_max, z))
                tube(mb, rib, 0.11, 5, 'wood', jit(C_DARK, rng, 0.08), mode='flat')
                for pt in rib:
                    hull_pts.append(tilt @ Vector(pt))

        # Splintered outer hull planking strakes on intact port side & lower starboard
        for si in range(5):
            y0 = -0.85 + si * 0.56
            y1 = y0 + 0.48
            for seg in range(9):
                if si >= 2 and seg in (4, 5):
                    continue  # gaping wreck breach!
                z0 = -4.6 + seg * 1.02
                z1 = z0 + 0.96
                b0 = 2.48 * max(0.30, (1.0 - abs(z0 / 5.7) ** 2.2) ** 0.72)
                b1 = 2.48 * max(0.30, (1.0 - abs(z1 / 5.7) ** 2.2) ** 0.72)
                p_col = jit(C_TAR if si == 0 else (C_HULL if si != 3 else C_TEAL), rng, 0.10)
                # Port side strake
                q = [(-b0, y0, z0), (-b1, y0, z1), (-b1 * 0.98, y1, z1), (-b0 * 0.98, y1, z0)]
                mb.fp(q, 'wood', p_col, (0, 0, 1), (0, 0, 0.5 * (z0 + z1)))
                mb.fp(q[::-1], 'wood', mul(p_col, 0.72), (0, 0, 1), (-6.0, 0, 0.5 * (z0 + z1)))
                # Starboard lower strakes only
                if si <= 1 or seg <= 2:
                    q2 = [(b0, y0, z0), (b1, y0, z1), (b1 * 0.98, y1, z1), (b0 * 0.98, y1, z0)]
                    mb.fp(q2, 'wood', p_col, (0, 0, 1), (0, 0, 0.5 * (z0 + z1)))

        # Broken stern deck planks & splintered forecastle deck
        for zi in range(5):
            z = 1.6 + zi * 0.66
            bw = 2.25 * max(0.4, (1.0 - abs(z / 5.8) ** 2.4))
            cbox(mb, (-0.35, 0.85, z), (bw * 1.35, 0.11, 0.56), 'wood', jit(C_DRIFT, rng, 0.08), 0.015, M=R('Y', rng.uniform(-5, 5)))
        # Snapped stern transom slab
        cbox(mb, (0.0, 0.65, 5.15), (3.1, 2.35, 0.24), 'wood', C_DARK, 0.03)
        cbox(mb, (0.0, 1.35, 5.26), (2.7, 0.42, 0.12), 'wood', C_RED, 0.015)

        # Snapped tilted mainmast stub (~5.8 m tall!) + crooked yardarm cross-piece for unmistakable wreck silhouette!
        mast_path = [(0.0, -1.0, -0.85), (0.15, 2.1, -0.95), (0.38, 4.9, -1.15), (0.48, 5.8, -1.25)]
        tube(mb, mast_path, [0.28, 0.24, 0.19, 0.10], 7, 'wood', C_WEATH, mode='flat')
        # Broken splintered cross-yard hanging askew
        tube(mb, [(-2.45, 3.35, -1.35), (0.28, 4.10, -1.35), (1.75, 4.55, -1.20)], [0.09, 0.14, 0.07], 6, 'wood', C_DRIFT, mode='flat')
        # Broken bowsprit spar jutting forward
        tube(mb, [(0.0, 1.55, -5.2), (0.10, 2.75, -8.1)], [0.16, 0.09], 6, 'wood', C_DRIFT, mode='flat')
        # Tattered rope shrouds
        tube(mb, [(0.35, 4.7, -1.15), (-2.1, 1.6, 0.2)], 0.035, 4, 'rope', C_ROPE, mode='flat')
        tube(mb, [(0.35, 4.7, -1.15), (-2.0, 1.4, -2.0)], 0.035, 4, 'rope', C_ROPE, mode='flat')
        for p in mast_path:
            for dx in (-0.35, 0.35):
                mast_pts.append(tilt @ (Vector(p) + Vector((dx, 0, 0))))

    build(mb)
    col_piece('col_wreck_hull', hull_pts)
    col_piece('col_wreck_mast', mast_pts)
    export_glb(outdir, 'shipwreck_hulk.glb')

def gen_barrel_prop(outdir):
    clear_scene()
    rng = random.Random(SEED + 307)
    mb = MB('BarrelProp', seed=307)
    # Chunky coopered oak barrel (~0.62 m diameter, 0.88 m tall, origin y=0)
    prof = [(0.0, 0.02), (0.23, 0.02), (0.255, 0.0), (0.275, 0.06), (0.315, 0.30), (0.315, 0.58), (0.275, 0.82), (0.255, 0.88), (0.23, 0.86), (0.0, 0.86)]
    stave_cols = [jit(C_HULL, rng, 0.09, 0.02) for _ in range(12)]
    lathe(mb, prof, 12, 'wood', C_HULL, False, False, lambda i, k: C_DARK if i in (0, 8) else stave_cols[k])
    # 4 forged iron barrel hoops
    for hy, hr in ((0.10, 0.288), (0.29, 0.320), (0.59, 0.320), (0.78, 0.288)):
        cyl(mb, hr, hy - 0.026, hy + 0.026, 12, 'iron', C_IRON, False, 0.005)
    # Wooden cork bung on side
    with xf(mb, T(0.315, 0.44, 0.0) @ M_Y2X):
        cyl(mb, 0.032, -0.02, 0.025, 6, 'wood', C_DECK, False)
    build(mb)
    col_box('col_barrel', (-0.31, 0.0, -0.31), (0.31, 0.88, 0.31))
    export_glb(outdir, 'barrel_prop.glb')

def gen_crate_supply(outdir):
    clear_scene()
    rng = random.Random(SEED + 331)
    mb = MB('CrateSupply', seed=331)
    # Chunky pirate cargo crate (~0.78 x 0.68 x 0.78 m, origin y=0)
    # Inner recessed panel core
    cbox(mb, (0.0, 0.34, 0.0), (0.70, 0.60, 0.70), 'wood', C_WEATH, 0.01)
    # Outer beveled timber battens (12 frame rails!)
    bw = 0.09
    for sy in (0.045, 0.635):
        for sz in (-0.345, 0.345):
            cbox(mb, (0.0, sy, sz), (0.78, bw, bw), 'wood', jit(C_DECK, rng, 0.07), 0.012, (1, 0, 0))
        for sx in (-0.345, 0.345):
            cbox(mb, (sx, sy, 0.0), (bw, bw, 0.62), 'wood', jit(C_DECK, rng, 0.07), 0.012, (0, 0, 1))
    for sx in (-0.345, 0.345):
        for sz in (-0.345, 0.345):
            cbox(mb, (sx, 0.34, sz), (bw, 0.56, bw), 'wood', jit(C_HULL, rng, 0.06), 0.012, (0, 1, 0))
    # Diagonal cross-brace planks on all 4 sides
    for ang in (0, 90, 180, 270):
        with xf(mb, T(0.0, 0.34, 0.0) @ R('Y', ang)):
            cbox(mb, (0.0, 0.0, -0.36), (0.72, 0.085, 0.036), 'wood', C_HULL, 0.008, M=R('Z', 38))
    # Painted merchant teal stripe on top
    cbox(mb, (0.0, 0.655, 0.0), (0.58, 0.02, 0.14), 'paint', C_TEAL, 0.004)
    # Iron corner plates
    for sx in (-0.365, 0.365):
        for sy in (0.05, 0.63):
            for sz in (-0.365, 0.365):
                cbox(mb, (sx, sy, sz), (0.08, 0.08, 0.08), 'iron', C_IRON, 0.006)
    build(mb)
    col_box('col_crate', (-0.39, 0.0, -0.39), (0.39, 0.68, 0.39))
    export_glb(outdir, 'crate_supply.glb')

def gen_campfire(outdir):
    clear_scene()
    rng = random.Random(SEED + 367)
    mb = MB('Campfire', seed=367)

    # Charred ash bed
    cyl(mb, 0.56, -0.05, 0.08, 10, 'stone', C_CHAR, False, 0.02, 0.44)
    # Ring of 10 chunky faceted beach stones
    for i in range(10):
        ang = i * (2.0 * pi / 10.0) + rng.uniform(-0.14, 0.14)
        rr = rng.uniform(0.56, 0.66)
        sx = rng.uniform(0.18, 0.25)
        sy = rng.uniform(0.13, 0.21)
        sz = rng.uniform(0.17, 0.24)
        faceted_rock(mb, (cos(ang) * rr, sy * 0.55, sin(ang) * rr), (sx, sy, sz), 'stone',
                     C_STONE_LIGHT, C_STONE_MID, C_STONE_DARK, rng, subdiv=1, warp=0.20, strata=0.06, rot_deg=(0, rng.uniform(0, 360), 0))

    # Glowing cracked ember mound at heart (mat_embers!)
    ellipsoid(mb, (0.0, 0.13, 0.0), (0.36, 0.16, 0.36), 'embers', C_EMBER, 8, 5)
    for i in range(5):
        ang = i * 1.25 + 0.2
        ellipsoid(mb, (cos(ang) * 0.18, 0.15, sin(ang) * 0.18), (0.11, 0.08, 0.10), 'embers', C_GOLD if i % 2 == 0 else C_EMBER, 6, 4)

    # 6 crossed split firewood logs stacked in a classic pirate campfire teepee
    for i in range(6):
        ang = i * (2.0 * pi / 6.0) + rng.uniform(-0.12, 0.12)
        p0 = Vector((cos(ang) * 0.52, 0.08, sin(ang) * 0.52))
        p1 = Vector((cos(ang + 2.4) * 0.12, 0.44 + rng.uniform(-0.05, 0.08), sin(ang + 2.4) * 0.12))
        tube(mb, [p0, p1], [0.068, 0.052], 6, 'wood', jit(C_DARK if i % 2 == 0 else C_CHAR, rng, 0.08), mode='flat')

    build(mb)
    add_empty('Lantern_Fire', (0.0, 0.55, 0.0))
    export_glb(outdir, 'campfire.glb')

def gen_notice_board(outdir):
    clear_scene()
    rng = random.Random(SEED + 401)
    mb = MB('NoticeBoard', seed=401)

    # Sturdy timber A-frame Voyage Notice Board for Outposts (no placeholder boxes!)
    for sx in (-1.05, 1.05):
        cbox(mb, (sx, 0.85, 0.0), (0.18, 2.85, 0.18), 'wood', C_DARK, 0.02)
        tube(mb, [(sx, 0.0, -0.42), (sx, 0.65, 0.0)], 0.075, 4, 'wood', C_DARK, mode='flat')
        tube(mb, [(sx, 0.0, 0.42), (sx, 0.65, 0.0)], 0.075, 4, 'wood', C_DARK, mode='flat')
    # Plank bulletin board backdrop (y = 0.95..2.05)
    cbox(mb, (0.0, 1.50, 0.0), (2.02, 1.12, 0.12), 'wood', C_HULL, 0.02)
    cbox(mb, (0.0, 2.08, 0.0), (2.28, 0.14, 0.18), 'wood', C_DARK, 0.02)
    cbox(mb, (0.0, 0.92, 0.0), (2.28, 0.14, 0.18), 'wood', C_DARK, 0.02)
    # Pitched shingle rain hood over board
    for sz in (-1, 1):
        q = [(-1.35, 2.52, 0.0), (1.35, 2.52, 0.0), (1.35, 2.20, sz * 0.58), (-1.35, 2.20, sz * 0.58)]
        mb.fp(q, 'wood', C_SHINGLE, (1, 0, 0), (0, 1.8, 0))
    cbox(mb, (0.0, 2.54, 0.0), (2.78, 0.10, 0.12), 'wood', C_RED, 0.015)
    # Pinned parchment voyage notices & crimson wax seals!
    notes = [(-0.56, 1.62, 0.28, 0.36, 5), (0.02, 1.54, 0.38, 0.44, -4), (0.58, 1.60, 0.30, 0.34, 8), (-0.42, 1.18, 0.34, 0.26, -7), (0.44, 1.20, 0.32, 0.28, 3)]
    for nx, ny, nw, nh, rot in notes:
        cbox(mb, (nx, ny, -0.072), (nw, nh, 0.014), 'paint', jit(C_CREAM, rng, 0.05), 0.002, M=R('Z', rot))
        # Red wax seal pin
        with xf(mb, T(nx, ny + nh * 0.34, -0.082) @ M_Y2Z):
            cyl(mb, 0.032, 0.0, 0.016, 6, 'paint', C_RED, False)

    build(mb)
    col_box('col_notice_board', (-1.18, -0.4, -0.35), (1.18, 2.50, 0.35))
    export_glb(outdir, 'notice_board.glb')


# ================================================================ WAVE 24A LANDMARK, JUNGLE, RUIN & HARBOUR PROPS

def _add_faceted_canopy_dome(mb, center, radii, rng, phase, base_w=0.18, tip_w=0.88, tint=0.5):
    """Chunky painterly multi-faceted jungle leaf-cluster dome with baked UV2 wind sway weights."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
    ph = [rng.uniform(0.0, 6.28) for _ in range(4)]
    cx, cy, cz = center
    rx, ry, rz = radii
    for v in bm.verts:
        p = v.co.copy()
        wob = 1.0 + 0.16 * sin(p.x * 3.1 + ph[0]) * cos(p.z * 2.8 + ph[1]) + 0.10 * sin(p.y * 4.0 + ph[2])
        # Slightly flatten underside so canopy domes stack into lush umbrella tiers
        py = p.y * (0.58 if p.y < 0.0 else 1.06)
        v.co = Vector((cx + p.x * rx * wob, cy + py * ry * wob, cz + p.z * rz * wob))
    bm.faces.ensure_lookup_table()
    mb.newoff()
    for f in bm.faces:
        pts = [v.co.copy() for v in f.verts]
        fn = newell(pts)
        if fn.length < 1e-8:
            continue
        fn.normalize()
        fc = sum(pts, Vector()) / len(pts)
        # Ensure outward face orientation from cluster center
        if fn.dot(fc - Vector(center)) < 0.0:
            pts.reverse()
            fn = -fn
        h_frac = smooth01((fc.y - (cy - ry * 0.6)) / max(0.2, ry * 1.6))
        sun_k = smooth01(0.55 * max(0.0, fn.y) + 0.45 * h_frac + (tint - 0.5) * 0.35)
        if fn.y < -0.15:
            col = jit(mul(C_LEAF_DEEP, 0.80), rng, 0.06, 0.02)
        else:
            col = jit(mix(mix(C_LEAF_DEEP, C_LEAF_MID, smooth01(sun_k * 1.35)), C_LEAF_SUN, pow(sun_k, 1.45) * 0.72), rng, 0.06, 0.03)
        uv2s = []
        for p in pts:
            r_out = sqrt((p.x - cx) ** 2 + (p.z - cz) ** 2) / max(0.1, max(rx, rz))
            w = max(0.0, min(1.0, base_w + (tip_w - base_w) * min(1.0, r_out * 0.85 + max(0.0, (p.y - cy) / max(0.2, ry)) * 0.25)))
            uv2s.append((w, phase))
        mb.fp(pts, 'foliage', col, (1, 0, 0), Vector(center), smooth=False, uv2=uv2s)
    bm.free()

def _add_ivy_drape(mb, anchor, length, width, out_dir, rng, phase):
    """Hanging jungle ivy ribbon pinned at top (UV2.x = 0) and swaying softly toward the tip (UV2.x = 0.9)."""
    od = Vector(out_dir).normalized()
    side = Vector((-od.z, 0.0, od.x)).normalized()
    segs = 5
    pts_l = []
    pts_r = []
    for i in range(segs + 1):
        t = i / float(segs)
        sway = sin(t * pi * 1.6 + phase * 6.28) * 0.09
        w = width * (0.55 + 0.45 * sin(t * pi * 0.85)) * (1.0 - 0.58 * t)
        c = Vector(anchor) + od * (0.08 + 0.10 * sin(t * pi)) + side * sway + Vector((0.0, -length * t, 0.0))
        pts_l.append(c - side * w)
        pts_r.append(c + side * w)
    for i in range(segs):
        t0 = i / float(segs)
        t1 = (i + 1) / float(segs)
        c0 = jit(mix(C_LEAF_DEEP, C_LEAF_MID, 0.35 + 0.45 * t0), rng, 0.07, 0.03)
        c1 = jit(mix(C_LEAF_MID, C_LEAF_SUN, 0.30 * t1), rng, 0.07, 0.03)
        u0 = (pow(t0, 1.25) * 0.90, phase)
        u1 = (pow(t1, 1.25) * 0.90, phase)
        mb.fp([pts_l[i], pts_r[i], pts_r[i + 1], pts_l[i + 1]], 'foliage', [c0, c0, c1, c1], (0, 1, 0), None, smooth=False, uv2=[u0, u0, u1, u1])

def gen_jungle_banyan(outdir):
    clear_scene()
    rng = random.Random(SEED + 431)
    mb_wood = MB('BanyanWood', seed=431)
    mb_leaf = MB('BanyanCanopy', seed=531)

    # 1. Twisted furrowed dark-bark main trunk (y = -0.85..+4.65 m) with subtle root fluting!
    trunk_pts = [
        (0.00, -0.85, 0.00, 0.92),
        (0.04,  0.10, -0.02, 0.78),
        (0.10,  1.25, -0.06, 0.64),
        (0.06,  2.45,  0.02, 0.56),
        (-0.04, 3.55,  0.08, 0.58),
        (-0.02, 4.65,  0.04, 0.68),
    ]
    sides = 8
    secs = []
    scols = []
    col_pts = []
    for i, (tx, ty, tz, tr) in enumerate(trunk_pts):
        t = i / float(len(trunk_pts) - 1)
        ring = []
        for k in range(sides):
            ang = 2.0 * pi * k / sides + t * 0.55
            flute = 1.0 + (0.16 * sin(ang * 5.0) * (1.0 - 0.6 * t))
            v = Vector((tx + cos(ang) * tr * flute, ty, tz + sin(ang) * tr * flute))
            ring.append(v)
            col_pts.append(v)
        secs.append(ring)
        scols.append(jit(mix(C_TRUNK_DARK, C_DARK, 0.35 + 0.30 * t), rng, 0.06, 0.02))
    loft(mb_wood, secs, 'wood', C_TRUNK_DARK, closed=True, caps=(True, True), mode='flat', scols=scols)

    # 2. Five dramatic splayed buttress roots plunging cleanly down to y = -0.85 m for sloped terrain!
    for ri in range(5):
        ang = ri * (2.0 * pi / 5.0) + rng.uniform(-0.16, 0.16)
        ca, sa = cos(ang), sin(ang)
        reach = rng.uniform(1.95, 2.45)
        r_path = [
            Vector((ca * 0.42, 2.35 + rng.uniform(-0.2, 0.25), sa * 0.42)),
            Vector((ca * (reach * 0.46), 1.05, sa * (reach * 0.46))),
            Vector((ca * (reach * 0.82), 0.12, sa * (reach * 0.82))),
            Vector((ca * reach, -0.85, sa * reach)),
        ]
        tube(mb_wood, r_path, [0.34, 0.28, 0.23, 0.16], 6, 'wood', jit(C_TRUNK_DARK, rng, 0.07), mode='flat')
        for p in r_path[:3]:
            col_pts.append(p)

    # 3. Four heavy gnarled spreading boughs + central crown limb!
    bough_specs = [
        (0.25,  3.55, 6.85, 0.42, 0.18),
        (1.75,  3.25, 7.25, 0.40, 0.17),
        (3.35,  3.45, 6.55, 0.40, 0.18),
        (4.90,  3.15, 7.45, 0.38, 0.16),
    ]
    bough_tips = []
    for bi, (az, reach, top_y, r0, r1) in enumerate(bough_specs):
        ca, sa = cos(az), sin(az)
        sx, sz = -sa, ca
        sw = rng.uniform(-0.35, 0.35)
        b_path = [
            Vector((ca * 0.22, 4.15 + 0.12 * (bi % 2), sa * 0.22)),
            Vector((ca * (reach * 0.42) + sx * sw * 0.5, 5.25, sa * (reach * 0.42) + sz * sw * 0.5)),
            Vector((ca * (reach * 0.78) + sx * sw, top_y - 0.55, sa * (reach * 0.78) + sz * sw)),
            Vector((ca * reach, top_y, sa * reach)),
        ]
        tube(mb_wood, b_path, [r0, r0 * 0.78, r0 * 0.56, r1], 6, 'wood', jit(C_DARK, rng, 0.07), mode='flat')
        bough_tips.append(b_path[-1])
        # Forked secondary sub-branch for rich broad-canopy structure
        for sgn in (-1.0, 1.0):
            fork_az = az + sgn * 0.58
            fca, fsa = cos(fork_az), sin(fork_az)
            f_start = b_path[2]
            f_end = f_start + Vector((fca * 1.45, 0.85 + rng.uniform(-0.15, 0.25), fsa * 1.45))
            tube(mb_wood, [f_start, f_end], [r0 * 0.42, r1 * 0.65], 5, 'wood', jit(C_TRUNK_LIGHT, rng, 0.07), mode='flat')
            bough_tips.append(f_end)

        # Hanging banyan aerial root tendrils draping down from the heavy bough!
        a_anchor = b_path[1].lerp(b_path[2], 0.55)
        a_end_y = -0.65 if bi % 2 == 0 else rng.uniform(1.4, 2.6)
        a_mid = Vector((a_anchor.x * 1.06, 0.5 * (a_anchor.y + a_end_y), a_anchor.z * 1.06))
        a_bot = Vector((a_anchor.x * 1.04, a_end_y, a_anchor.z * 1.04))
        tube(mb_wood, [a_anchor, a_mid, a_bot], [0.065, 0.050, 0.042], 5, 'wood', jit(C_WEATH, rng, 0.08), mode='flat')

    # Towering central crown bough reaching up into the sunlit canopy apex (~10.5 m!)
    crown_limb = [Vector((-0.02, 4.50, 0.04)), Vector((0.18, 6.45, -0.12)), Vector((0.08, 8.25, -0.06))]
    tube(mb_wood, crown_limb, [0.42, 0.28, 0.16], 6, 'wood', C_TRUNK_DARK, mode='flat')

    # 4. Lush multi-tiered emerald-to-sunlit-gold layered leaf-frond dome canopy ('foliage' -> wind shader!)
    # Outer broad bough leaf domes + forked mid-canopy tiers
    for idx, tip in enumerate(bough_tips):
        is_primary = (idx % 3 == 0)
        rx = rng.uniform(2.05, 2.55) if is_primary else rng.uniform(1.55, 1.95)
        ry = rng.uniform(1.30, 1.65) if is_primary else rng.uniform(1.05, 1.35)
        rz = rng.uniform(1.95, 2.45) if is_primary else rng.uniform(1.48, 1.88)
        _add_faceted_canopy_dome(
            mb_leaf,
            (tip.x, tip.y + 0.55, tip.z),
            (rx, ry, rz),
            rng, phase=rng.random(), base_w=0.16, tip_w=0.86, tint=0.45 if is_primary else 0.62
        )
    # Upper crowning sunlit umbrella dome pushing tree silhouette cleanly to ~10.5 m!
    _add_faceted_canopy_dome(mb_leaf, (0.05, 8.95, -0.05), (2.75, 1.60, 2.65), rng, phase=rng.random(), base_w=0.22, tip_w=0.92, tint=0.92)
    _add_faceted_canopy_dome(mb_leaf, (-1.15, 8.35, 0.85), (1.95, 1.25, 1.85), rng, phase=rng.random(), base_w=0.20, tip_w=0.88, tint=0.78)
    _add_faceted_canopy_dome(mb_leaf, (1.10, 8.25, -0.90), (1.90, 1.22, 1.80), rng, phase=rng.random(), base_w=0.20, tip_w=0.88, tint=0.82)

    # Hanging lush jungle vine ribbons trailing from outer boughs
    for vi in range(5):
        vaz = vi * (2.0 * pi / 5.0) + 0.45
        vr = rng.uniform(2.6, 3.4)
        v_anc = (cos(vaz) * vr, rng.uniform(5.7, 6.5), sin(vaz) * vr)
        _add_ivy_drape(mb_leaf, v_anc, rng.uniform(1.8, 2.8), 0.24, (cos(vaz), 0.0, sin(vaz)), rng, phase=rng.random())

    build(mb_wood)
    build(mb_leaf)
    col_piece('col_banyan_trunk', col_pts)
    export_glb(outdir, 'jungle_banyan.glb')

def gen_ruin_arch(outdir):
    clear_scene()
    rng = random.Random(SEED + 461)
    mb = MB('RuinArch', seed=461)

    # Monumental ~6.8 m tall x ~6.4 m wide ancient maritime temple archway (~3.8 m clear walkable opening!)
    # 1. Twin stepped limestone foundation plinths extending solidly down to y = -1.2 m
    for sx in (-1.0, 1.0):
        px = sx * 2.52
        box2(mb, (px - 0.74, -1.20, -0.84), (px + 0.74, 0.44, 0.84), 'stone', jit(C_STONE_MID, rng, 0.06), 0.05)
        box2(mb, (px - 0.62, 0.44, -0.72), (px + 0.62, 0.84, 0.72), 'stone', jit(C_STONE_LIGHT, rng, 0.06), 0.04)

        # 5 stacked beveled coral-limestone ashlar pillar courses (y = 0.84..4.28, inner face at |x| = 1.92 -> 3.84 m open!)
        course_y = [0.84, 1.54, 2.24, 2.94, 3.60, 4.24]
        for ci in range(5):
            y0, y1 = course_y[ci], course_y[ci + 1]
            ym = 0.5 * (y0 + y1)
            h_c = y1 - y0 - 0.015
            ox = rng.uniform(-0.03, 0.03)
            oz = rng.uniform(-0.03, 0.03)
            col_c = mix(C_STONE_WARM, C_STONE_PALE, 0.25 + 0.14 * ci)
            if ci == 0:
                col_c = mix(col_c, C_SEA_MOSS, 0.28)
            cbox(mb, (px + ox, ym, oz), (1.14, h_c, 1.24), 'stone', jit(col_c, rng, 0.06), 0.045, M=R('Y', rng.uniform(-2.0, 2.0)))
            # Subtle protruding inner pilaster quoin strip
            cbox(mb, (px - sx * 0.56, ym, 0.0), (0.12, h_c * 0.82, 0.72), 'stone', jit(C_STONE_PALE, rng, 0.05), 0.02)

        # Stepped flaring temple capital abacus (y = 4.24..4.68)
        cbox(mb, (px, 4.38, 0.0), (1.32, 0.28, 1.42), 'stone', C_STONE_WARM, 0.04)
        cbox(mb, (px, 4.60, 0.0), (1.46, 0.18, 1.54), 'stone', C_STONE_PALE, 0.035)

    # 2. Seven-voussoir radial coral-limestone arch span (clear opening ~3.8 m wide x ~4.6..5.45 m tall!)
    arch_r = 2.38
    arch_cy = 3.22
    n_vous = 7
    for vi in range(n_vous):
        ang_deg = -62.0 + (124.0 * vi / float(n_vous - 1))
        ang = radians(ang_deg)
        is_key = (vi == n_vous // 2)
        vx = sin(ang) * arch_r
        vy = arch_cy + cos(ang) * arch_r
        vw = 0.82 if is_key else 0.72
        vh = 0.96 if is_key else 0.76
        vd = 1.46 if is_key else 1.28
        vcol = C_STONE_PALE if is_key else jit(mix(C_STONE_WARM, C_STONE_PALE, 0.55), rng, 0.06)
        cbox(mb, (vx, vy, 0.0), (vw, vh, vd), 'stone', vcol, 0.045, M=R('Z', -ang_deg))

    # Carved antique-brass maritime compass-crest medallion inlaid on BOTH faces of the central keystone!
    key_y = arch_cy + arch_r
    for sz in (-1.0, 1.0):
        with xf(mb, T(0.0, key_y, sz * 0.74) @ R('X', 90 if sz > 0 else -90)):
            cyl(mb, 0.28, 0.0, 0.06, 8, 'brass', C_BRASS, False, 0.012, 0.24)
            cyl(mb, 0.16, 0.05, 0.09, 8, 'brass', C_GOLD, False, 0.008, 0.12)
        for k in range(4):
            a_deg = k * 45.0
            cbox(mb, (0.0, key_y, sz * 0.78), (0.48 if k % 2 == 0 else 0.36, 0.06, 0.05), 'brass', C_GOLD, 0.008, M=R('Z', a_deg))

    # 3. Weathered fractured temple entablature & stepped cornice blocks crowning arch to ~6.8 m!
    lintel_blocks = [
        (-2.35, 5.42, 0.0, (1.55, 0.68, 1.46), 1.5, C_STONE_WARM),
        (-0.88, 6.08, 0.02, (1.72, 0.72, 1.42), -1.2, C_STONE_PALE),
        ( 0.85, 6.06, -0.02, (1.68, 0.68, 1.40), 2.5, C_STONE_WARM),
        ( 2.38, 5.38, 0.0, (1.42, 0.64, 1.44), -3.5, C_STONE_LIGHT),
        # Broken stepped pediment crest peak (~6.80 m on port side, weathered fracture slope to starboard!)
        (-1.25, 6.62, 0.0, (1.85, 0.46, 1.24), 4.0, C_STONE_PALE),
        ( 0.22, 6.56, 0.02, (1.35, 0.38, 1.16), -8.0, C_STONE_OCHRE),
    ]
    for lx, ly, lz, lsz, lrot, lcol in lintel_blocks:
        cbox(mb, (lx, ly, lz), lsz, 'stone', jit(lcol, rng, 0.05), 0.05, M=R('Z', lrot))

    # 4. Cushioned emerald moss patches & hanging wind-swaying jungle ivy drapes ('foliage')!
    moss_spots = [
        (-2.45, 5.82, -0.25, (0.62, 0.22, 0.56)),
        (-0.95, 6.84,  0.10, (0.78, 0.22, 0.58)),
        ( 1.95, 5.76,  0.18, (0.58, 0.20, 0.52)),
        (-2.55, 0.88, -0.45, (0.48, 0.16, 0.42)),
        ( 2.55, 0.88,  0.42, (0.46, 0.15, 0.40)),
    ]
    for mx, my, mz, mrad in moss_spots:
        _add_faceted_canopy_dome(mb, (mx, my, mz), mrad, rng, phase=rng.random(), base_w=0.04, tip_w=0.22, tint=0.42)

    ivy_spots = [
        ((-1.95, 5.65, -0.74), 2.05, 0.26, (0.0, 0.0, -1.0)),
        ((-1.35, 6.28, -0.72), 1.65, 0.22, (0.0, 0.0, -1.0)),
        (( 1.78, 5.52, -0.74), 1.85, 0.24, (0.0, 0.0, -1.0)),
        ((-1.82, 5.72,  0.74), 1.90, 0.24, (0.0, 0.0,  1.0)),
        (( 1.55, 5.95,  0.72), 1.55, 0.22, (0.0, 0.0,  1.0)),
        (( 2.95, 4.65, -0.58), 2.15, 0.26, (0.5, 0.0, -0.8)),
    ]
    for anc, ilen, iw, idir in ivy_spots:
        _add_ivy_drape(mb, anc, ilen, iw, idir, rng, phase=rng.random())

    build(mb)
    # Two separate side-pillar colliders ONLY — leaving the entire ~3.8 m central archway 100% walkable!
    col_box('col_arch_l', (-3.26, -1.20, -0.85), (-1.90, 5.50, 0.85))
    col_box('col_arch_r', ( 1.90, -1.20, -0.85), ( 3.26, 5.50, 0.85))
    export_glb(outdir, 'ruin_arch.glb')

def gen_ruin_pillar(outdir):
    clear_scene()
    rng = random.Random(SEED + 491)
    mb = MB('RuinPillar', seed=491)

    # Chunky ~5.4 m tall broken fluted octagonal limestone monolith column on a stepped plinth (y = -1.0..+5.4 m)
    # 1. Stepped ancient foundation plinth plunging to y = -1.0 m
    box2(mb, (-1.02, -1.00, -1.02), (1.02, 0.36, 1.02), 'stone', C_STONE_MID, 0.055)
    cyl(mb, 0.90, 0.36, 0.72, 8, 'stone', C_STONE_LIGHT, False, 0.045, 0.82)
    cyl(mb, 0.76, 0.72, 0.94, 8, 'stone', C_STONE_WARM, False, 0.035, 0.66)

    # 2. Fluted 16-vertex (8 rib + 8 concave flute) weathered limestone column drums rising to diagonal snap (~5.4 m)!
    def fluted_ring(y_base, r_rib, r_flute, tilt_slope=0.0):
        pts = []
        for k in range(16):
            ang = 2.0 * pi * k / 16.0
            r = r_rib if k % 2 == 0 else r_flute
            px = cos(ang) * r
            pz = sin(ang) * r
            py = y_base + tilt_slope * (px * 0.72 - pz * 0.45)
            pts.append((px, py, pz))
        return pts

    # Lower shaft drum (y = 0.92..2.64)
    loft(mb, [
        fluted_ring(0.92, 0.64, 0.55),
        fluted_ring(1.80, 0.61, 0.52),
        fluted_ring(2.64, 0.59, 0.50),
    ], 'stone', C_STONE_WARM, closed=True, caps=(True, True), mode='flat',
        scols=[mix(C_STONE_WARM, C_SEA_MOSS, 0.18), C_STONE_WARM, C_STONE_PALE])

    # 3. Inlaid oxidized antique-bronze ring collar (y = 2.64..3.08) with raised gold border bands & studs!
    cyl(mb, 0.635, 2.64, 3.08, 8, 'brass', C_COPPER, False, 0.015, 0.635)
    cyl(mb, 0.665, 2.65, 2.74, 8, 'brass', C_GOLD, False, 0.012, 0.665)
    cyl(mb, 0.665, 2.98, 3.07, 8, 'brass', C_GOLD, False, 0.012, 0.665)
    for k in range(8):
        ang = 2.0 * pi * k / 8.0 + pi / 8.0
        with xf(mb, T(cos(ang) * 0.61, 2.86, sin(ang) * 0.61) @ R('Y', -degrees_of(ang))):
            cbox(mb, (0.0, 0.0, 0.0), (0.06, 0.14, 0.14), 'brass', C_GOLD, 0.012)

    # 4. Upper fluted column shaft with authentic weathered diagonal fracture top (peaking at y = 5.42 m!)
    loft(mb, [
        fluted_ring(3.08, 0.58, 0.49),
        fluted_ring(4.12, 0.55, 0.46),
        fluted_ring(5.05, 0.53, 0.44, tilt_slope=-0.82),
    ], 'stone', C_STONE_PALE, closed=True, caps=(True, True), mode='flat',
        scols=[C_STONE_WARM, C_STONE_PALE, jit(C_STONE_PALE, rng, 0.04)])

    # Jagged chipped limestone fracture shards crowning the diagonal break & 2 fallen stones at foot
    faceted_rock(mb, (-0.18, 5.18, 0.10), (0.34, 0.24, 0.30), 'stone', C_STONE_PALE, C_STONE_WARM, C_STONE_SHADE, rng, subdiv=1, warp=0.18, strata=0.06)
    faceted_rock(mb, (0.86, 0.16, -0.78), (0.34, 0.24, 0.28), 'stone', C_STONE_OCHRE, C_STONE_MID, C_STONE_DARK, rng, subdiv=1, warp=0.22, strata=0.08, rot_deg=(12, 35, -8))
    faceted_rock(mb, (-0.95, 0.12, 0.62), (0.28, 0.19, 0.25), 'stone', C_MOSS, C_STONE_MID, C_STONE_DARK, rng, subdiv=1, warp=0.20, strata=0.06, rot_deg=(-8, -42, 10))

    # 5. Emerald moss patches clinging to plinth ledge & fractured top + trailing ivy sprig
    _add_faceted_canopy_dome(mb, (0.22, 4.92, -0.18), (0.36, 0.16, 0.32), rng, phase=rng.random(), base_w=0.04, tip_w=0.18, tint=0.45)
    _add_faceted_canopy_dome(mb, (-0.65, 0.42, -0.58), (0.42, 0.16, 0.38), rng, phase=rng.random(), base_w=0.03, tip_w=0.14, tint=0.35)
    _add_ivy_drape(mb, (0.38, 4.65, -0.46), 1.45, 0.20, (0.7, 0.0, -0.7), rng, phase=rng.random())

    build(mb)
    col_box('col_pillar', (-1.00, -1.00, -1.00), (1.00, 5.38, 1.00))
    export_glb(outdir, 'ruin_pillar.glb')

def degrees_of(rad):
    return rad * 180.0 / pi

def gen_timber_bridge(outdir):
    clear_scene()
    rng = random.Random(SEED + 521)
    mb = MB('TimberBridge', seed=521)

    # Chunky ~11.0 m long (Z = -5.5..+5.5) x 2.6 m wide arched oak-plank & hemp-rope suspension footbridge!
    HALF_L = 5.50
    HALF_W = 1.30
    ARCH_H = 0.55

    def arch_y(z):
        u = z / HALF_L
        return ARCH_H * max(0.0, 1.0 - u * u)

    def arch_pitch_deg(z):
        # Slope dy/dz = -2 * ARCH_H * z / HALF_L^2; rotation around X lifts -Z when positive
        dydz = -2.0 * ARCH_H * z / (HALF_L * HALF_L)
        return degrees_of(atan2(dydz, 1.0))

    # 1. Twin heavy weathered oak end-posts at both canyon lips (y = -1.80..+2.10 m!) + end sill anchor timbers
    for sz in (-1.0, 1.0):
        pz = sz * 5.42
        # Heavy transverse end-sill lip beam anchoring bridge deck cleanly into canyon rim
        box2(mb, (-1.52, -0.45, pz - 0.22), (1.52, 0.02, pz + 0.22), 'wood', C_DARK, 0.025, (1, 0, 0))
        for sx in (-1.0, 1.0):
            px = sx * HALF_W
            # Sturdy timber suspension post plunging deep to y = -1.8 m!
            box2(mb, (px - 0.14, -1.80, pz - 0.14), (px + 0.14, 2.08, pz + 0.14), 'wood', jit(C_DARK, rng, 0.06), 0.024, (0, 1, 0))
            # Beveled oak cap finial & forged iron collar band
            cbox(mb, (px, 2.12, pz), (0.34, 0.08, 0.34), 'wood', C_HULL, 0.018)
            cbox(mb, (px, 1.84, pz), (0.31, 0.10, 0.31), 'iron', C_IRON, 0.01)
            # Wrapped hemp rope lashing around post top where handrail cables anchor
            with xf(mb, T(px, 1.66, pz)):
                for ri in range(3):
                    with xf(mb, T(0, ri * 0.044, 0)):
                        torus(mb, 0.16, 0.024, 10, 5, 'rope', C_ROPE, True)
            # Angled canyon-lip anchor strut bracing each end post outward
            tube(mb, [(px, 0.95, pz), (px + sx * 0.55, -1.45, pz + sz * 0.55)], [0.095, 0.115], 5, 'wood', C_WEATH, mode='flat')

    # 2. Two curved under-deck timber carrier stringers spanning full 11 m arch
    for sx in (-0.96, 0.96):
        str_path = []
        for i in range(13):
            z = -HALF_L + (2.0 * HALF_L * i / 12.0)
            str_path.append((sx, arch_y(z) - 0.14, z))
        tube(mb, str_path, 0.11, 4, 'wood', C_DARK, mode='flat')

    # 3. 26 chunky weathered oak walkway planks gently arching up to y = +0.55 m mid-span!
    n_planks = 26
    plank_palette = (C_DECK, C_HULL, C_WEATH, C_DRIFT)
    for pi in range(n_planks):
        z = -5.22 + (10.44 * pi / float(n_planks - 1))
        py = arch_y(z)
        pitch = -arch_pitch_deg(z)
        pw = 2.48 + rng.uniform(-0.06, 0.06)
        pcol = jit(plank_palette[pi % len(plank_palette)], rng, 0.08, 0.02)
        rot_m = R('X', pitch) @ R('Y', rng.uniform(-1.3, 1.3))
        cbox(mb, (0.0, py - 0.045, z), (pw, 0.09, 0.35), 'wood', pcol, 0.015, (1, 0, 0), M=rot_m)

    # Low side timber curb rails along outer deck edges
    for sx in (-1.18, 1.18):
        curb_path = []
        for i in range(13):
            z = -5.30 + (10.60 * i / 12.0)
            curb_path.append((sx, arch_y(z) + 0.05, z))
        tube(mb, curb_path, 0.055, 4, 'wood', C_WEATH, mode='flat')

    # 4. Taut catenary side hemp-rope handrails & vertical rope hangers on port & starboard!
    def handrail_y(z):
        u = z / HALF_L
        return 1.48 + 0.36 * (u * u)

    def midrail_y(z):
        u = z / HALF_L
        return 0.96 + 0.22 * (u * u)

    for sx in (-HALF_W, HALF_W):
        top_rope = [(sx, handrail_y(-5.42 + 10.84 * i / 16.0), -5.42 + 10.84 * i / 16.0) for i in range(17)]
        mid_rope = [(sx, midrail_y(-5.42 + 10.84 * i / 16.0), -5.42 + 10.84 * i / 16.0) for i in range(17)]
        tube(mb, top_rope, 0.044, 6, 'rope', C_ROPE, mode='smooth')
        tube(mb, mid_rope, 0.030, 5, 'rope', mul(C_ROPE, 0.92), mode='smooth')
        # 9 vertical rope hangers per side tying handrail to deck planks
        for hi in range(9):
            hz = -4.20 + (8.40 * hi / 8.0)
            hy_bot = arch_y(hz) - 0.04
            hy_top = handrail_y(hz)
            tube(mb, [(sx, hy_bot, hz), (sx, hy_top, hz)], 0.022, 5, 'rope', mul(C_ROPE, 0.88), mode='flat')
            # Knotted tie-off collar on top rail
            with xf(mb, T(sx, hy_top, hz)):
                cyl(mb, 0.048, -0.03, 0.03, 6, 'rope', C_ROPE, False)

    build(mb)

    # Smooth walkable 3-segment ramp-matched convex deck collider matching exact arch_y(z)!
    deck_segs = [
        ('col_bridge_deck_0', -5.50, -1.80),
        ('col_bridge_deck_1', -1.92,  1.92),
        ('col_bridge_deck_2',  1.80,  5.50),
    ]
    for cname, z0, z1 in deck_segs:
        y0 = arch_y(z0)
        y1 = arch_y(z1)
        ym = arch_y(0.5 * (z0 + z1))
        pts = []
        for x in (-1.26, 1.26):
            pts.append((x, y0, z0))
            pts.append((x, y0 - 0.24, z0))
            pts.append((x, ym, 0.5 * (z0 + z1)))
            pts.append((x, ym - 0.24, 0.5 * (z0 + z1)))
            pts.append((x, y1, z1))
            pts.append((x, y1 - 0.24, z1))
        col_piece(cname, pts)
    export_glb(outdir, 'timber_bridge.glb')

def gen_harbour_warehouse(outdir):
    clear_scene()
    rng = random.Random(SEED + 557)
    mb = MB('HarbourWarehouse', seed=557)

    # Chunky ~8.4 x 5.8 x 6.2 m coastal stone-and-timber port trading warehouse (facing -Z dockside!)
    FLOOR_Y = 0.60
    EAVE_Y = 3.65
    RIDGE_Y = 6.20

    # 1. Battered stone foundation plinth (y = -1.8..+0.60 m) + corner stone quoins + loading apron!
    loft(mb, [
        [(-4.52, -1.80, -3.22), (4.52, -1.80, -3.22), (4.52, -1.80, 3.22), (-4.52, -1.80, 3.22)],
        [(-4.26, FLOOR_Y, -2.96), (4.26, FLOOR_Y, -2.96), (4.26, FLOOR_Y, 2.96), (-4.26, FLOOR_Y, 2.96)],
    ], 'stone', C_STONE_MID, closed=True, caps=(True, True), mode='flat', scols=[C_STONE_DARK, C_STONE_MID])
    for sx in (-4.24, 4.24):
        for sz in (-2.94, 2.94):
            for yi in range(3):
                cbox(mb, (sx, -0.35 + yi * 0.36, sz), (0.56, 0.32, 0.56), 'stone', jit(C_STONE_LIGHT, rng, 0.06), 0.03)
    # Stone cargo-loading porch apron in front of warehouse doors (-Z)
    box2(mb, (-4.10, -1.40, -3.95), (4.10, 0.14, -2.90), 'stone', C_STONE_LIGHT, 0.035)
    cbox(mb, (0.0, 0.36, -3.35), (2.75, 0.24, 0.65), 'stone', C_STONE_MID, 0.025)

    # 2. Timber-framed whitewashed plaster upper walls (y = 0.60..3.65 m) + front/rear gable triangles!
    loft(mb, [
        [(-4.15, FLOOR_Y, -2.86), (4.15, FLOOR_Y, -2.86), (4.15, FLOOR_Y, 2.86), (-4.15, FLOOR_Y, 2.86)],
        [(-4.30, EAVE_Y, -2.96), (4.30, EAVE_Y, -2.96), (4.30, EAVE_Y, 2.96), (-4.30, EAVE_Y, 2.96)],
    ], 'paint', C_PLASTER, closed=True, caps=(True, True), mode='flat', scols=[C_PLASTER])
    for sz in (-1.0, 1.0):
        gz = sz * 2.94
        g_pts = [(-4.28, EAVE_Y - 0.04, gz), (4.28, EAVE_Y - 0.04, gz), (0.0, RIDGE_Y - 0.12, gz)]
        mb.fp(g_pts, 'paint', C_PLASTER_SH, (1, 0, 0), (0.0, EAVE_Y, 0.0))

    # Heavy dark-oak half-timber framing (corner posts, horizontals, diagonal X-braces)
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            tube(mb, [(sx * 4.20, FLOOR_Y, sz * 2.90), (sx * 4.35, EAVE_Y + 0.04, sz * 3.00)], 0.16, 4, 'wood', C_DARK, mode='flat')
    for y_beam in (FLOOR_Y + 0.08, 2.15, EAVE_Y - 0.05):
        t = (y_beam - FLOOR_Y) / (EAVE_Y - FLOOR_Y)
        bx = 4.18 + 0.16 * t
        bz = 2.88 + 0.10 * t
        cbox(mb, (0.0, y_beam, -bz), (bx * 2.0 + 0.24, 0.20, 0.20), 'wood', C_DARK, 0.02)
        cbox(mb, (0.0, y_beam,  bz), (bx * 2.0 + 0.24, 0.20, 0.20), 'wood', C_DARK, 0.02)
        cbox(mb, (-bx, y_beam, 0.0), (0.20, 0.20, bz * 2.0 + 0.24), 'wood', C_DARK, 0.02)
        cbox(mb, ( bx, y_beam, 0.0), (0.20, 0.20, bz * 2.0 + 0.24), 'wood', C_DARK, 0.02)
    for sx in (-1.65, 1.65):
        cbox(mb, (sx, 2.12, -2.96), (0.20, 3.05, 0.20), 'wood', C_DARK, 0.02)
    for sz in (-1.0, 1.0):
        for sx in (-4.28, 4.28):
            tube(mb, [(sx, FLOOR_Y + 0.15, sz * 2.85), (sx, EAVE_Y - 0.15, sz * 1.10)], 0.08, 4, 'wood', C_DARK, mode='flat')

    # 3. Pitched weathered cedar-shingle gable roof (eaves along +/-X, ridge running front-to-back along Z!)
    courses = 5
    for side_x in (-1.0, 1.0):
        for ci in range(courses):
            f0 = ci / float(courses)
            f1 = min(1.02, (ci + 1) / float(courses) + 0.03)
            y0 = RIDGE_Y - (RIDGE_Y - EAVE_Y + 0.35) * f0
            y1 = RIDGE_Y - (RIDGE_Y - EAVE_Y + 0.35) * f1
            x0 = side_x * (4.78 * f0)
            x1 = side_x * (4.78 * f1)
            zs = [-3.48, -2.35, -1.20, 0.05, 1.25, 2.38, 3.48]
            for zi in range(len(zs) - 1):
                z0, z1 = zs[zi], zs[zi + 1]
                th = 0.15 + rng.uniform(-0.015, 0.02)
                c_sh = jit(mix(C_CEDAR_PALETTE[(ci + zi) % len(C_CEDAR_PALETTE)], C_DARK, 0.12 * f0), rng, 0.07, 0.02)
                p_top = [(x0, y0 + th, z0), (x0, y0 + th, z1), (x1, y1 + th, z1), (x1, y1 + th, z0)]
                p_bot = [(x0, y0, z0), (x0, y0, z1), (x1, y1, z1), (x1, y1, z0)]
                mb.fp(p_top, 'wood', c_sh, (0, 0, 1), (0.0, y0 - 2.0, 0.5 * (z0 + z1)))
                mb.fp(p_bot, 'wood', mul(c_sh, 0.68), (0, 0, 1), (0.0, y0 + 2.0, 0.5 * (z0 + z1)))
                mb.fp([p_bot[3], p_bot[2], p_top[2], p_top[3]], 'wood', mul(c_sh, 0.78), (0, 0, 1), (0.0, y0, 0.5 * (z0 + z1)))
    # Heavy ridge cap timber + bold maritime teal bargeboards distinguishing the Trading Warehouse!
    cbox(mb, (0.0, RIDGE_Y + 0.12, 0.0), (0.34, 0.30, 7.15), 'wood', C_DARK, 0.03)
    for sz in (-3.44, 3.44):
        for side_x in (-1.0, 1.0):
            tube(mb, [(0.0, RIDGE_Y + 0.05, sz), (side_x * 4.78, EAVE_Y - 0.30, sz)], 0.14, 4, 'wood', C_TEAL, mode='flat')

    # 4. Projecting timber cargo hoist gantry beam with iron pulley block, cargo hook & coiled hemp rope!
    cbox(mb, (0.0, 5.52, -3.72), (0.24, 0.24, 2.25), 'wood', C_DARK, 0.025)
    tube(mb, [(0.0, 4.35, -2.94), (0.0, 5.48, -4.18)], 0.09, 4, 'wood', C_HULL, mode='flat')
    cbox(mb, (0.0, 5.52, -4.62), (0.28, 0.28, 0.14), 'iron', C_IRON, 0.01)
    # Hanging iron pulley sheave block & vertical hoist rope + hook
    cbox(mb, (0.0, 5.18, -4.62), (0.14, 0.28, 0.24), 'iron', C_IRON, 0.015)
    with xf(mb, T(0.0, 5.16, -4.62) @ M_Y2X):
        cyl(mb, 0.11, -0.04, 0.04, 10, 'wood', C_DECK, False)
    tube(mb, [(0.0, 5.05, -4.62), (0.0, 3.35, -4.62)], 0.024, 5, 'rope', C_ROPE, mode='flat')
    with xf(mb, T(0.0, 3.22, -4.62) @ M_Y2Z):
        torus(mb, 0.085, 0.022, 8, 5, 'iron', C_IRON, False)
    # Coiled hemp cargo line resting beside front porch apron
    rope_coil(mb, (-1.95, 0.14, -3.55), radius=0.26, turns=3, r=0.028)

    # Upper cargo loft hatch doors (swung open beneath hoist beam!)
    cbox(mb, (0.0, 4.35, -2.96), (1.42, 1.38, 0.16), 'wood', C_DARK, 0.02)
    cbox(mb, (0.0, 4.35, -2.90), (1.16, 1.14, 0.10), 'wood', C_TAR, 0.01)
    for sx in (-1.0, 1.0):
        cbox(mb, (sx * 0.94, 4.35, -3.14), (0.58, 1.18, 0.08), 'wood', C_TEAL, 0.014, M=R('Y', sx * 28))

    # 5. Double heavy timber warehouse cargo doors (-Z) with iron strap hinges & brass ring pulls!
    cbox(mb, (0.0, FLOOR_Y + 1.24, -2.96), (2.48, 2.48, 0.22), 'wood', C_DARK, 0.025)
    for sx in (-1.0, 1.0):
        dx = sx * 0.56
        cbox(mb, (dx, FLOOR_Y + 1.18, -3.02), (1.06, 2.28, 0.12), 'wood', jit(C_HULL, rng, 0.06), 0.018)
        cbox(mb, (dx, FLOOR_Y + 1.18, -3.08), (0.92, 0.12, 0.05), 'wood', C_DARK, 0.01, M=R('Z', sx * 42))
        for hy in (FLOOR_Y + 0.56, FLOOR_Y + 1.78):
            cbox(mb, (dx + sx * 0.20, hy, -3.10), (0.58, 0.09, 0.04), 'iron', C_IRON, 0.008)
        with xf(mb, T(sx * 0.16, FLOOR_Y + 1.08, -3.12) @ M_Y2Z):
            torus(mb, 0.072, 0.018, 8, 5, 'brass', C_BRASS, True)

    # 6. Warm glowing mullioned warehouse windows ('window'!)
    def add_wh_window(pos, rot_y, w=1.18, h=1.08):
        with xf(mb, T(pos) @ R('Y', rot_y)):
            cbox(mb, (0, -h * 0.5 - 0.06, -0.05), (w + 0.30, 0.13, 0.22), 'wood', C_DARK, 0.02)
            cbox(mb, (0, h * 0.5 + 0.05, -0.04), (w + 0.24, 0.13, 0.20), 'wood', C_DARK, 0.02)
            for sx in (-w * 0.5 - 0.06, w * 0.5 + 0.06):
                cbox(mb, (sx, 0, -0.04), (0.12, h + 0.10, 0.18), 'wood', C_DARK, 0.02)
            for sx in (-1, 1):
                cbox(mb, (sx * (w * 0.5 + 0.30), 0, -0.04), (0.34, h, 0.06), 'wood', C_TEAL, 0.012)
            cbox(mb, (0, 0, 0.0), (w, h, 0.06), 'window', C_GLASS, 0.0)
            cbox(mb, (0, 0, -0.04), (w, 0.065, 0.05), 'wood', C_DARK, 0.006)
            cbox(mb, (0, 0, -0.04), (0.065, h, 0.05), 'wood', C_DARK, 0.006)

    add_wh_window((-2.88, FLOOR_Y + 1.52, -2.94), 0.0)
    add_wh_window(( 2.88, FLOOR_Y + 1.52, -2.94), 0.0)
    add_wh_window((-4.26, FLOOR_Y + 1.52, -0.85), 90.0, 1.25, 1.08)
    add_wh_window((-4.26, FLOOR_Y + 1.52,  1.05), 90.0, 1.25, 1.08)
    add_wh_window(( 4.26, FLOOR_Y + 1.52, -0.85), -90.0, 1.25, 1.08)
    add_wh_window(( 4.26, FLOOR_Y + 1.52,  1.05), -90.0, 1.25, 1.08)
    add_wh_window(( 0.00, FLOOR_Y + 1.52,  2.94), 180.0, 1.45, 1.08)

    # 7. Stacked cargo barrels & crates beside the loading porch!
    for bx, bz in ((-3.38, -3.45), (-2.72, -3.56)):
        with xf(mb, T(bx, 0.14, bz)):
            lathe(mb, [(0, 0), (0.25, 0), (0.30, 0.26), (0.30, 0.56), (0.25, 0.84), (0, 0.84)], 10, 'wood', jit(C_HULL, rng, 0.08), False)
            for hy in (0.18, 0.66):
                cyl(mb, 0.305, hy, hy + 0.05, 10, 'iron', C_IRON, False)
    for cx, cy, cz, csz, cry in ((3.12, 0.48, -3.46, 0.68, -8), (3.16, 1.08, -3.44, 0.52, 16), (2.36, 0.44, -3.52, 0.60, 5)):
        with xf(mb, T(cx, cy, cz) @ R('Y', cry)):
            cbox(mb, (0, 0, 0), (csz, csz, csz), 'wood', jit(C_DECK, rng, 0.07), 0.018)
            cbox(mb, (0, 0, -csz * 0.48), (csz * 0.92, 0.08, 0.04), 'wood', C_HULL, 0.008, M=R('Z', 38))
            cbox(mb, (0, csz * 0.49, 0), (csz * 0.72, 0.025, 0.12), 'paint', C_TEAL, 0.004)

    # 8. Porch hoist bracket lantern + Lantern_Warehouse empty anchor!
    lantern_pos = (-1.65, 2.95, -3.48)
    cbox(mb, (-1.65, 3.24, -3.22), (0.08, 0.08, 0.62), 'iron', C_IRON, 0.01)
    tube(mb, [(-1.65, 2.92, -2.96), (-1.65, 3.24, -3.38)], 0.025, 4, 'iron', C_IRON, mode='flat')
    build_lantern_geom(mb, lantern_pos, scale=1.10, hanging=True)

    build(mb)
    add_empty('Lantern_Warehouse', lantern_pos)
    col_box('col_warehouse_main', (-4.40, -1.80, -3.15), (4.40, EAVE_Y + 0.05, 3.15))
    col_piece('col_warehouse_roof', [
        (x, y, z)
        for z in (-3.45, 3.45)
        for (x, y) in ((-4.75, EAVE_Y - 0.25), (4.75, EAVE_Y - 0.25), (0.0, RIDGE_Y + 0.15))
    ])
    export_glb(outdir, 'harbour_warehouse.glb')

def gen_seawall_bastion(outdir):
    clear_scene()
    rng = random.Random(SEED + 587)
    mb = MB('SeawallBastion', seed=587)

    # Heavy battered coral-limestone harbour sea-wall & crenellated parapet segment:
    # 9.0 m wide (X = -4.5..+4.5), 3.6 m deep (Z = -1.8..+1.8), 4.2 m high above y=0, plunging to y = -2.4 m!
    DECK_Y = 3.00

    # 1. Battered main masonry curtain wall (wider battered seawall foot on -Z seaward side!)
    loft(mb, [
        [(-4.50, -2.40, -2.18), (4.50, -2.40, -2.18), (4.50, -2.40, 1.85), (-4.50, -2.40, 1.85)],
        [(-4.50,  0.40, -1.96), (4.50,  0.40, -1.96), (4.50,  0.40, 1.78), (-4.50,  0.40, 1.78)],
        [(-4.50, DECK_Y, -1.68), (4.50, DECK_Y, -1.68), (4.50, DECK_Y, 1.72), (-4.50, DECK_Y, 1.72)],
    ], 'stone', C_STONE_WARM, closed=True, caps=(True, True), mode='flat',
        scols=[mix(C_STONE_DARK, C_SEA_MOSS, 0.45), mix(C_STONE_WARM, C_SEA_MOSS, 0.18), C_STONE_WARM])

    # Projecting beveled stone cornice stringcourse along top of seaward wall (y = 2.74..3.04)
    cbox(mb, (0.0, 2.89, -1.74), (9.16, 0.30, 0.36), 'stone', C_STONE_PALE, 0.045)

    # Paved coral-limestone flagstone slabs crowning the walkable deck (y = 3.00..3.08)
    for fi in range(6):
        fx = -3.75 + fi * 1.50
        for fz in (-0.20, 1.02):
            cbox(mb, (fx, DECK_Y + 0.03, fz), (1.42, 0.08, 1.14), 'stone', jit(C_STONE_LIGHT, rng, 0.05), 0.015)

    # 2. Two heavy battered corner buttress piers (x = +/-4.05, y = -2.4..+4.20 m)
    for sx in (-1.0, 1.0):
        bx = sx * 4.02
        loft(mb, [
            [(bx - 0.68, -2.40, -2.45), (bx + 0.68, -2.40, -2.45), (bx + 0.68, -2.40, -0.75), (bx - 0.68, -2.40, -0.75)],
            [(bx - 0.58,  0.50, -2.22), (bx + 0.58,  0.50, -2.22), (bx + 0.58,  0.50, -0.78), (bx - 0.58,  0.50, -0.78)],
            [(bx - 0.54,  3.04, -1.96), (bx + 0.54,  3.04, -1.96), (bx + 0.54,  3.04, -0.82), (bx - 0.54,  3.04, -0.82)],
        ], 'stone', C_STONE_WARM, closed=True, caps=(True, True), mode='flat',
            scols=[mix(C_STONE_MID, C_SEA_MOSS, 0.35), C_STONE_WARM, C_STONE_PALE])
        # Stepped buttress cap & heavy corner merlon rising to y = 4.20 m
        cbox(mb, (bx, 3.16, -1.42), (1.22, 0.24, 1.24), 'stone', C_STONE_PALE, 0.04)
        cbox(mb, (bx, 3.74, -1.36), (1.06, 0.94, 1.02), 'stone', jit(C_STONE_WARM, rng, 0.05), 0.045)
        cbox(mb, (bx, 4.18, -1.36), (1.14, 0.14, 1.10), 'stone', C_STONE_PALE, 0.03)

    # 3. Recessed stone parapet breastwork, flanking merlons & central seaward cannon embrasure!
    # Low beveled embrasure sill across the central bay (x = -1.25..+1.25, top y = 3.44)
    cbox(mb, (0.0, 3.22, -1.32), (2.75, 0.44, 0.84), 'stone', C_STONE_LIGHT, 0.035)
    # Two stout beveled crenellation merlons flanking the central embrasure (y = 3.02..4.18)
    for sx in (-1.0, 1.0):
        mx = sx * 2.18
        cbox(mb, (mx, 3.58, -1.32), (1.68, 1.10, 0.88), 'stone', jit(C_STONE_WARM, rng, 0.05), 0.045)
        cbox(mb, (mx, 4.14, -1.32), (1.76, 0.14, 0.96), 'stone', C_STONE_PALE, 0.03)

    # Weathered inset ashlar stone relief blocks along the seaward face for painterly masonry readability
    for rx, ry in ((-2.4, 1.8), (0.0, 2.0), (2.3, 1.6), (-1.2, 0.9), (1.4, 1.0)):
        cbox(mb, (rx, ry, -1.84), (1.15, 0.48, 0.14), 'stone', jit(C_STONE_PALE, rng, 0.06), 0.03)

    # 4. Twin heavy forged-iron harbour mooring bollards on the seawall deck + coiled mooring ropes!
    for sx in (-1.0, 1.0):
        px = sx * 3.05
        pz = 0.98
        with xf(mb, T(px, DECK_Y + 0.06, pz)):
            cyl(mb, 0.28, 0.0, 0.08, 8, 'iron', C_IRON, False, 0.015, 0.24)
            cyl(mb, 0.17, 0.08, 0.62, 8, 'iron', C_IRON, False, 0.012, 0.19)
            cyl(mb, 0.24, 0.58, 0.70, 8, 'iron', C_IRON, False, 0.02, 0.21)
            # Horizontal cast-iron horn cross-bar
            with xf(mb, T(0, 0.48, 0) @ M_Y2X):
                cyl(mb, 0.065, -0.34, 0.34, 6, 'iron', C_IRON, False, 0.01)
            rope_coil(mb, (0.0, 0.08, 0.0), radius=0.22, turns=2, r=0.026)

    # 5. Hanging forged-iron wall lantern bracket + Lantern_Seawall empty anchor!
    lantern_pos = (-3.95, 2.42, -2.42)
    cbox(mb, (-3.95, 2.74, -2.14), (0.10, 0.10, 0.68), 'iron', C_IRON, 0.012)
    tube(mb, [(-3.95, 2.38, -1.86), (-3.95, 2.74, -2.30)], 0.028, 4, 'iron', C_IRON, mode='flat')
    build_lantern_geom(mb, lantern_pos, scale=1.15, hanging=True)

    build(mb)
    add_empty('Lantern_Seawall', lantern_pos)
    col_box('col_seawall_base', (-4.62, -2.40, -2.18), (4.62, DECK_Y + 0.06, 1.80))
    col_box('col_seawall_parapet', (-4.62, DECK_Y, -1.82), (4.62, 4.22, -0.82))
    export_glb(outdir, 'seawall_bastion.glb')

def gen_watchtower_wood(outdir):
    clear_scene()
    rng = random.Random(SEED + 617)
    mb = MB('WatchtowerWood', seed=617)

    # Tall ~8.8 m lashed-timber pirate cliffside lookout tower!
    DECK_Y = 5.20
    EAVE_Y = 7.40
    PEAK_Y = 8.80

    # 1. Four splayed heavy timber stilts plunging to y = -1.80 m, rising cleanly to roof eaves (y = 7.42 m)!
    def stilt_xy(sx, sz, y):
        # Splayed wide at base (-1.8 m -> +/-1.72 m), tapering inward to deck (5.2 m -> +/-1.24 m), vertical above deck
        t = max(0.0, min(1.0, (y + 1.80) / (DECK_Y + 1.80)))
        spread = 1.72 - 0.48 * t
        return (sx * spread, sz * spread)

    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            bx, bz = stilt_xy(sx, sz, -1.80)
            dx, dz = stilt_xy(sx, sz, DECK_Y)
            tube(mb, [(bx, -1.80, bz), (dx, DECK_Y, dz), (dx, EAVE_Y + 0.05, dz)], [0.18, 0.15, 0.13], 6, 'wood', jit(C_DARK, rng, 0.06), mode='flat')
            # Wrapped hemp rope lashings at major joint heights
            for ly in (1.50, 3.35, DECK_Y - 0.12, EAVE_Y - 0.10):
                lx, lz = stilt_xy(sx, sz, ly)
                with xf(mb, T(lx, ly, lz)):
                    for ri in range(2):
                        with xf(mb, T(0, ri * 0.052, 0)):
                            torus(mb, 0.17, 0.025, 8, 5, 'rope', C_ROPE, True)

    # 2. Horizontal ledger beams & diagonal X-bracing timbers across 2 stilt tiers!
    corners = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)]
    tier_ys = [(0.15, 1.50), (1.50, 3.35), (3.35, DECK_Y - 0.12)]
    for ti, (y0, y1) in enumerate(tier_ys):
        for side in range(4):
            c0 = corners[side]
            c1 = corners[(side + 1) % 4]
            a0 = stilt_xy(c0[0], c0[1], y0)
            b0 = stilt_xy(c1[0], c1[1], y0)
            a1 = stilt_xy(c0[0], c0[1], y1)
            b1 = stilt_xy(c1[0], c1[1], y1)
            # Horizontal ledger beam at y1
            tube(mb, [(a1[0], y1, a1[1]), (b1[0], y1, b1[1])], 0.095, 5, 'wood', jit(C_HULL, rng, 0.06), mode='flat')
            # Diagonal X-bracing (leave front -Z face side=0 open for climbing ladder!)
            if side != 0 or ti == 2:
                if side != 0:
                    tube(mb, [(a0[0], y0, a0[1]), (b1[0], y1, b1[1])], 0.072, 4, 'wood', C_WEATH, mode='flat')
                    tube(mb, [(b0[0], y0, b0[1]), (a1[0], y1, a1[1])], 0.072, 4, 'wood', C_WEATH, mode='flat')

    # Sloped wooden climbing ladder rising up front -Z face to the y = 5.20 m lookout deck!
    lad_bot_z = -2.28
    lad_top_z = -1.46
    for sx in (-0.34, 0.34):
        tube(mb, [(sx, -0.80, lad_bot_z), (sx, DECK_Y + 0.25, lad_top_z)], 0.052, 5, 'wood', C_HULL, mode='flat')
    for ri in range(14):
        rt = (ri + 0.5) / 14.0
        ry = -0.35 + (DECK_Y + 0.35) * rt
        rz = lad_bot_z + (lad_top_z - lad_bot_z) * rt
        tube(mb, [(-0.34, ry, rz), (0.34, ry, rz)], 0.032, 5, 'wood', C_DECK, mode='flat')

    # 3. Elevated planked lookout deck (y = 5.20 m) + cantilevered joists + chunky perimeter railings!
    for jz in (-1.22, 0.0, 1.22):
        cbox(mb, (0.0, DECK_Y - 0.14, jz), (3.32, 0.16, 0.16), 'wood', C_DARK, 0.018)
    for pi in range(9):
        px = -1.40 + pi * 0.35
        cbox(mb, (px, DECK_Y, 0.0), (0.31, 0.11, 3.16), 'wood', jit(C_DECK if pi % 2 == 0 else C_HULL, rng, 0.07), 0.014, (0, 0, 1))

    # Waist-high perimeter timber railings (leaving front -Z ladder entrance open!)
    for side in range(4):
        c0 = corners[side]
        c1 = corners[(side + 1) % 4]
        p0 = Vector((c0[0] * 1.48, DECK_Y, c0[1] * 1.48))
        p1 = Vector((c1[0] * 1.48, DECK_Y, c1[1] * 1.48))
        if side == 0:
            # Left & right short safety rails framing front ladder gap
            for end_p, dir_v in ((p0, (p1 - p0).normalized()), (p1, (p0 - p1).normalized())):
                seg_e = end_p + dir_v * 0.95
                tube(mb, [end_p + Vector((0, 0.96, 0)), seg_e + Vector((0, 0.96, 0))], 0.068, 5, 'wood', C_HULL, mode='flat')
                tube(mb, [end_p + Vector((0, 0.50, 0)), seg_e + Vector((0, 0.50, 0))], 0.048, 4, 'wood', C_WEATH, mode='flat')
                tube(mb, [seg_e + Vector((0, 0.04, 0)), seg_e + Vector((0, 1.02, 0))], 0.065, 5, 'wood', C_DARK, mode='flat')
        else:
            tube(mb, [p0 + Vector((0, 0.96, 0)), p1 + Vector((0, 0.96, 0))], 0.068, 5, 'wood', C_HULL, mode='flat')
            tube(mb, [p0 + Vector((0, 0.50, 0)), p1 + Vector((0, 0.50, 0))], 0.048, 4, 'wood', C_WEATH, mode='flat')
            for bi in (1, 2):
                bp = p0.lerp(p1, bi / 3.0)
                tube(mb, [bp + Vector((0, 0.04, 0)), bp + Vector((0, 0.96, 0))], 0.052, 4, 'wood', C_WEATH, mode='flat')

    # Lookout deck storytelling cargo (tucked rum barrel & ammo crate in rear corner)
    with xf(mb, T(-0.92, DECK_Y + 0.06, 0.88)):
        lathe(mb, [(0, 0), (0.22, 0), (0.26, 0.24), (0.26, 0.50), (0.22, 0.74), (0, 0.74)], 8, 'wood', C_HULL, False)
        cyl(mb, 0.265, 0.16, 0.21, 8, 'iron', C_IRON, False)
        cyl(mb, 0.265, 0.54, 0.59, 8, 'iron', C_IRON, False)
    cbox(mb, (0.88, DECK_Y + 0.30, 0.92), (0.52, 0.48, 0.52), 'wood', C_DECK, 0.015, M=R('Y', 14))

    # 4. Pitched overhanging palm-thatch roof canopy (y = 7.30..8.80 m!)
    for side in range(4):
        c0 = corners[side]
        c1 = corners[(side + 1) % 4]
        tube(mb, [(c0[0] * 1.24, EAVE_Y, c0[1] * 1.24), (c1[0] * 1.24, EAVE_Y, c1[1] * 1.24)], 0.095, 5, 'wood', C_DARK, mode='flat')
    # 3 overlapping stepped hipped thatch tiers for rich painterly tropical-island roof texture
    tiers = [
        (7.28, 7.82, 1.98, 1.46, C_THATCH),
        (7.76, 8.32, 1.54, 0.86, mul(C_THATCH, 0.93)),
        (8.26, PEAK_Y, 0.94, 0.14, jit(C_DECK, rng, 0.05)),
    ]
    for y0, y1, r0, r1, tcol in tiers:
        loft(mb, [
            [(-r0, y0, -r0), (r0, y0, -r0), (r0, y0, r0), (-r0, y0, r0)],
            [(-r1, y1, -r1), (r1, y1, -r1), (r1, y1, r1), (-r1, y1, r1)],
        ], 'wood', tcol, closed=True, caps=(True, True), mode='flat', scols=[mul(tcol, 0.88), tcol])
    # Thatch crown finial bundle & bamboo corner rafter tails
    cyl(mb, 0.18, PEAK_Y - 0.06, PEAK_Y + 0.16, 6, 'wood', C_DARK, False, 0.02, 0.08)
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            tube(mb, [(0.0, PEAK_Y - 0.08, 0.0), (sx * 2.08, EAVE_Y - 0.16, sz * 2.08)], [0.06, 0.05], 4, 'wood', C_WEATH, mode='flat')

    # 5. Fluttering crimson forked swallowtail pirate banner pennant on starboard roof corner!
    pole_b = Vector((1.24, EAVE_Y - 0.20, -1.24))
    pole_t = Vector((1.58, PEAK_Y + 0.35, -1.48))
    tube(mb, [pole_b, pole_t], [0.052, 0.036], 6, 'wood', C_DARK, mode='flat')
    # Rippling swallowtail crimson banner with gold accent bar
    b_t0 = pole_t + Vector((0.0, -0.08, 0.0))
    b_b0 = pole_t + Vector((0.0, -0.78, 0.0))
    b_m1 = pole_t + Vector((0.88, -0.44, -0.22))
    b_tu = pole_t + Vector((1.65, -0.18, -0.42))
    b_tl = pole_t + Vector((1.58, -0.76, -0.40))
    b_notch = pole_t + Vector((1.18, -0.46, -0.32))
    mb.fp([b_t0, b_tu, b_notch, b_m1], 'awning', C_RED, (1, 0, 0), None, smooth=False)
    mb.fp([b_b0, b_m1, b_notch, b_tl], 'awning', mul(C_RED, 0.88), (1, 0, 0), None, smooth=False)
    mb.fp([b_t0, b_m1, b_b0], 'awning', C_GOLD, (1, 0, 0), None, smooth=False)

    # 6. Warm hanging lookout lantern under the front -Z eave + Lantern_Watch empty!
    lantern_pos = (0.0, 6.92, -1.58)
    tube(mb, [(0.0, EAVE_Y - 0.02, -1.58), (0.0, 7.18, -1.58)], 0.015, 4, 'iron', C_IRON, mode='flat')
    build_lantern_geom(mb, lantern_pos, scale=1.12, hanging=True)

    build(mb)
    add_empty('Lantern_Watch', lantern_pos)
    col_box('col_watch_base', (-1.62, -1.80, -1.62), (1.62, DECK_Y - 0.05, 1.62))
    col_box('col_watch_deck', (-1.58, DECK_Y - 0.05, -1.58), (1.58, PEAK_Y, 1.58))
    export_glb(outdir, 'watchtower_wood.glb')

# ================================================================ main
def main():
    argv = sys.argv
    outdir = argv[-1] if '--' in argv else os.path.join(os.getcwd(), 'assets', 'generated')
    random.seed(SEED)
    np.random.seed(SEED)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    make_materials()

    print('gen_props: writing stylized props to %s' % os.path.join(outdir, 'props'))
    generators = [
        gen_palm_tall,
        gen_palm_curved,
        gen_bush_fern,
        gen_rock_boulder,
        gen_rock_spire,
        gen_rock_arch,
        gen_dock_pier,
        gen_outpost_tavern,
        gen_outpost_stall,
        gen_beacon_tower,
        gen_chest_treasure,
        gen_dig_mound,
        gen_shipwreck_hulk,
        gen_barrel_prop,
        gen_crate_supply,
        gen_campfire,
        gen_notice_board,
        # Wave 24A: 7 brand-new island landmark, jungle, ruin, fort & harbour props
        gen_jungle_banyan,
        gen_ruin_arch,
        gen_ruin_pillar,
        gen_timber_bridge,
        gen_harbour_warehouse,
        gen_seawall_bastion,
        gen_watchtower_wood,
    ]
    for fn in generators:
        fn(outdir)
    print('gen_props: exported %d props cleanly.' % len(generators))

main()
