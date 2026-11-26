# Sea of Scoundrels: procedural Brigantine generator (M3 second playable ship class).
# Usage: blender --background --factory-startup --python tools/blender/gen_brigantine.py -- <outdir>
# Writes <outdir>/ship/brigantine.glb and <outdir>/ship/brigantine_lod.glb. Deterministic (seeded).
# Everything is authored in *game* coordinates (Godot: -Z bow, +Y up, +X starboard, metres) and
# converted to Blender's Z-up frame only when meshes/objects are created, matching docs/SHIP_ART.md.
import bpy, bmesh, sys, os, math, random
import numpy as np
from contextlib import contextmanager
from math import sin, cos, pi, sqrt, atan2, radians, ceil, floor
from mathutils import Vector, Matrix

SEED = 1729

# ---------------------------------------------------------------- spec constants
Z_BOW = -9.2            # stem at main deck
Z_STERN = 8.2           # transom at main deck (17.4 m hull deck length)
HALF_BEAM = 2.70        # 5.4 m beam amidships
DECK_Y = 1.25           # main deck
QDECK_Y = 2.25          # quarterdeck (aft of QDECK_Z)
QDECK_Z = 4.0
HOLD_Y = float(os.environ.get('BRIGANTINE_HOLD_Y', '-0.95'))  # 2.10 m clear headroom under main deck (1.15 - (-0.95))

# Mainmast (tall aft mast with crow's nest, huge square mainsail, long forked pennant)
MAST_Z = 0.5
YARD_Y = 11.2
MAST_TOP = 17.5
YARD_FWD = 0.62
YARD_HALF = 3.90
SAIL_FOOT_Y = 3.85

# Foremast (second mast forward, slightly lower, crisp billowing square foresail + pennant)
MAST_FORE_Z = -4.6
YARD_FORE_Y = 9.15
MAST_FORE_TOP = 15.0
YARD_FORE_FWD = 0.70
YARD_FORE_HALF = 3.35
SAIL_FORE_FOOT_Y = 3.55

TH = 0.16               # hull plank thickness

# Station markers (Godot game coords + yaw deg around +Y)
STATIONS = {
    "Station_Helm": ((0.0, QDECK_Y, 6.8), 0),
    "Station_SailLength": ((-2.35, DECK_Y, 2.55), 0),
    "Station_SailAngle": ((2.35, DECK_Y, 2.55), 0),
    "Station_Anchor": ((0.0, DECK_Y, -6.5), 0),
    "Station_CannonPort": ((-2.46, DECK_Y, -2.4), 90),           # -Z faces -X
    "Station_CannonStarboard": ((2.46, DECK_Y, -2.4), -90),      # -Z faces +X
    "Station_CannonPortAft": ((-2.52, DECK_Y, 1.4), 90),         # -Z faces -X
    "Station_CannonStarboardAft": ((2.52, DECK_Y, 1.4), -90),    # -Z faces +X
    "Station_MapTable": ((0.0, HOLD_Y, 4.6), 0),
    "Station_Bilge": ((0.0, HOLD_Y, 2.0), 0),
    "Station_Ladder_Port": ((-2.64, 0.0, -0.50), 0),
    "Station_Ladder_Starboard": ((2.64, 0.0, -0.50), 0),
}

# Bulwark cutouts: fore gunports (-2.4), amidships boarding ladders (-0.5), aft gunports (+1.4)
GAPS = [(-2.85, -1.95), (-0.95, -0.05), (0.95, 1.85)]

# Central hatch & stairs between foremast (-4.6) and mainmast (+0.5): open aft, descending forward
HOLD_STAIR = (-0.75, -3.60)
HATCH = (-0.50, 0.50, -3.70, -0.70)

# Twin port/starboard flights let into the quarterdeck break
QSTAIR = (1.12, 2.15, 3.55, 5.05)

# Bold sweeping bowsprit reaching z = -14.2
BS_HEEL = (0.0, 2.75, -7.8)
BS_TIP = (0.0, 4.95, -14.2)

# ---------------------------------------------------------------- colour (original Brigantine livery)
def srgb(h):
    h = h.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c)

def mul(c, f):
    return (c[0] * f, c[1] * f, c[2] * f)

def mix(a, b, t):
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3))

def jit(c, rng, amt=0.10, hue=0.03):
    f = 1.0 + rng.uniform(-amt, amt)
    return (c[0] * f * (1 + rng.uniform(-hue, hue)), c[1] * f, c[2] * f * (1 + rng.uniform(-hue, hue)))

# Deep weathered mahogany hull, bold gilded-brass rails, ocean-teal gunwale bands,
# indigo & cream canvas accents, sun-bleached warm teak deck planks.
C_HULL = srgb('#733828')      # deep weathered mahogany
C_DECK = srgb('#cea36b')      # warm sun-bleached teak deck
C_DARK = srgb('#44241b')      # dark walnut/mahogany frames & rails
C_INNER = srgb('#825034')     # warm mahogany hold lining
C_TAR = srgb('#242126')       # dark tarred underwater hull
C_CREAM = srgb('#f2e4be')     # warm sunlit cream boot stripe & trim
C_TEAL = srgb('#148490')      # vibrant ocean-teal gunwale band & bulkhead
C_INDIGO = srgb('#1f3460')    # deep maritime indigo accents
C_RED = srgb('#b82a24')       # rich crimson accent (cushions, rug, kegs)
C_GOLD = srgb('#ebb434')      # bold gilded trim & carved emblem
C_BRASS = srgb('#e6b64c')     # metallic brass rails, finials, hardware
C_IRON = srgb('#2e313b')      # cast iron
C_ROPE = srgb('#cfb482')
C_ROPE_D = srgb('#54412e')
C_WHITE = (1.0, 1.0, 1.0)
C_GLASS = srgb('#ffc264')
C_BLACK = srgb('#14110f')

SU, SV = 1 / 2.2, 1 / 1.45

# ---------------------------------------------------------------- transforms (game coords)
def T(x, y=None, z=None):
    return Matrix.Translation(Vector(x) if y is None else Vector((x, y, z)))

def R(axis, deg):
    return Matrix.Rotation(radians(deg), 4, axis)

def S(x, y=None, z=None):
    if y is None:
        y = z = x
    return Matrix.Diagonal((x, y, z, 1.0))

M_ZY = Matrix(((0, 1, 0, 0), (0, 0, 1, 0), (1, 0, 0, 0), (0, 0, 0, 1)))
M_Y2Z = R('X', 90)
M_Y2X = R('Z', -90)

def newell(pts):
    n = Vector((0, 0, 0))
    for i in range(len(pts)):
        a = pts[i]; b = pts[(i + 1) % len(pts)]
        n.x += (a.y - b.y) * (a.z + b.z)
        n.y += (a.z - b.z) * (a.x + b.x)
        n.z += (a.x - b.x) * (a.y + b.y)
    return n

def smooth01(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)

# ---------------------------------------------------------------- mesh builder
class MB:
    def __init__(self, name, origin=(0, 0, 0), seed=0, yaw=0.0, parent=None):
        self.name = name; self.origin = Vector(origin); self.yaw = yaw; self.parent = parent
        self.verts = []; self.faces = []; self.fmat = []; self.fsm = []; self.fcol = []; self.fuv = []
        self.stack = [Matrix.Identity(4)]; self.flip = False
        self.rng = random.Random(SEED * 7919 + seed + sum(ord(c) for c in name))
        self.off = (0.0, 0.0)
        self.wfn = None       # optional pos -> (weight, aux): written to UV2 for wind shaders
        self.gmatrix = None   # optional full object matrix in game coords

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

    def f(self, idx, mat, col, uvs, smooth=False):
        if len(set(idx)) < 3:
            return
        if self.flip:
            idx = idx[::-1]; uvs = uvs[::-1]
        if len(idx) > 4:
            for k in range(1, len(idx) - 1):
                tri = (idx[0], idx[k], idx[k + 1])
                if len(set(tri)) < 3:
                    continue
                self.faces.append(tri); self.fmat.append(mat); self.fsm.append(smooth)
                self.fcol.append(col); self.fuv.append([uvs[0], uvs[k], uvs[k + 1]])
            return
        self.faces.append(tuple(idx)); self.fmat.append(mat); self.fsm.append(smooth)
        self.fcol.append(col); self.fuv.append(uvs)

    def fp(self, pts, mat, col, grain=None, inside=None):
        pts = [Vector(p) for p in pts]
        n = newell(pts)
        if n.length < 1e-10:
            return
        n.normalize()
        if inside is not None:
            c = sum(pts, Vector()) / len(pts)
            if n.dot(c - Vector(inside)) < 0:
                pts.reverse(); n = -n
        g = Vector(grain) if grain is not None else Vector((0, 0, 1))
        gu = g - n * g.dot(n)
        if gu.length < 0.35:
            a = Vector((1, 0, 0)) if abs(n.x) < 0.8 else Vector((0, 1, 0))
            gu = a - n * a.dot(n)
        gu.normalize(); gv = n.cross(gu)
        o = self.off
        uvs = [(p.dot(gu) * SU + o[0], p.dot(gv) * SV + o[1]) for p in pts]
        self.f([self.v(p) for p in pts], mat, col, uvs, False)

    def tris(self):
        return sum(len(f) - 2 for f in self.faces)

    def merge(self, other):
        """Append geometry from another static MB (authored in ship-local game coords) into self."""
        assert other.gmatrix is None and other.parent is None and other.wfn is None and other.yaw == 0.0, \
            'cannot merge non-static MB: %s' % other.name
        assert self.origin.length < 1e-9 and self.yaw == 0.0, \
            'merge target %s must sit at ship origin' % self.name
        base = len(self.verts)
        self.verts.extend(other.verts)
        self.faces.extend(tuple(i + base for i in f) for f in other.faces)
        self.fmat.extend(other.fmat)
        self.fsm.extend(other.fsm)
        self.fcol.extend(other.fcol)
        self.fuv.extend(other.fuv)

@contextmanager
def xf(mb, M):
    mb.push(M)
    try:
        yield
    finally:
        mb.pop()

# ---------------------------------------------------------------- primitives
def cbox(mb, c, size, mat, col, ch=0.015, grain=None, M=None, skip=()):
    h = [size[0] / 2, size[1] / 2, size[2] / 2]
    ch = min(ch, min(h) * 0.45)
    if grain is None:
        a = max(range(3), key=lambda i: h[i]); grain = [0, 0, 0]; grain[a] = 1
    mb.newoff()
    X = T(c) @ M if M is not None else T(c)
    names = 'xyz'
    with xf(mb, X):
        O = Vector((0, 0, 0))
        def fv(a, s, s1, s2):
            p = [0, 0, 0]; b = (a + 1) % 3; cc = (a + 2) % 3
            p[a] = s * h[a]; p[b] = s1 * (h[b] - ch); p[cc] = s2 * (h[cc] - ch)
            return Vector(p)
        for a in range(3):
            for s in (-1, 1):
                if (('+' if s > 0 else '-') + names[a]) in skip:
                    continue
                mb.fp([fv(a, s, -1, -1), fv(a, s, 1, -1), fv(a, s, 1, 1), fv(a, s, -1, 1)], mat, col, grain, O)
        if ch > 1e-5:
            dk = mul(col, 0.86)
            def on(a, sa, b, sb, sc):
                cc = 3 - a - b
                p = [0, 0, 0]; p[a] = sa * h[a]; p[b] = sb * (h[b] - ch); p[cc] = sc * (h[cc] - ch)
                return Vector(p)
            for a in range(3):
                for b in range(a + 1, 3):
                    for sa in (-1, 1):
                        for sb in (-1, 1):
                            mb.fp([on(a, sa, b, sb, -1), on(a, sa, b, sb, 1), on(b, sb, a, sa, 1), on(b, sb, a, sa, -1)], mat, dk, grain, O)
            for sx in (-1, 1):
                for sy in (-1, 1):
                    for sz in (-1, 1):
                        mb.fp([Vector((sx * h[0], sy * (h[1] - ch), sz * (h[2] - ch))),
                               Vector((sx * (h[0] - ch), sy * h[1], sz * (h[2] - ch))),
                               Vector((sx * (h[0] - ch), sy * (h[1] - ch), sz * h[2]))], mat, dk, grain, O)

def box2(mb, lo, hi, mat, col, ch=0.015, grain=None):
    cbox(mb, [(lo[i] + hi[i]) / 2 for i in range(3)], [abs(hi[i] - lo[i]) for i in range(3)], mat, col, ch, grain)

def hexa(mb, p, mat, col, grain=None):
    p = [Vector(q) for q in p]; c = sum(p, Vector()) / 8; mb.newoff()
    for q in ((0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
        mb.fp([p[i] for i in q], mat, col, grain, c)

def loft(mb, secs, mat, col, closed=True, caps=(True, True), mode='flat', ecols=None, scols=None, flip=None, grain_caps=None, uniform_w=False):
    secs = [[Vector(p) for p in s] for s in secs]
    n = len(secs); k = len(secs[0])
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
    if uniform_w:
        W = [W[n // 2]] * n
    if flip is None:
        vote = 0.0
        for i in range(n - 1):
            cc = (cents[i] + cents[i + 1]) / 2
            for j in range(ne):
                q = [secs[i][j], secs[i][(j + 1) % k], secs[i + 1][(j + 1) % k], secs[i + 1][j]]
                vote += newell(q).dot(sum(q, Vector()) / 4 - cc)
        flip = vote < 0
    o = mb.newoff()
    def uv(i, j): return (L[i] * SU + o[0], W[i][j] * SV + o[1])
    shared = mode in ('flat', 'smooth'); sm = mode != 'flat'
    if shared:
        ids = [[mb.v(p) for p in s] for s in secs]
    for j in range(ne):
        j1 = (j + 1) % k
        if not shared:
            e0 = [mb.v(s[j]) for s in secs]; e1 = [mb.v(s[j1]) for s in secs]
        for i in range(n - 1):
            if shared:
                idx = [ids[i][j], ids[i][j1], ids[i + 1][j1], ids[i + 1][j]]
            else:
                idx = [e0[i], e1[i], e1[i + 1], e0[i + 1]]
            uvs = [uv(i, j), uv(i, j + 1), uv(i + 1, j + 1), uv(i + 1, j)]
            c = scols[i] if scols else (ecols[j] if ecols else col)
            if flip:
                idx = idx[::-1]; uvs = uvs[::-1]
            keep = []; kuv = []
            for a, b in zip(idx, uvs):
                if all((mb.verts[a] - mb.verts[q]).length > 1e-7 for q in keep):
                    keep.append(a); kuv.append(b)
            if len(keep) >= 3:
                mb.f(keep, mat, c, kuv, sm)
    g = grain_caps
    if closed and caps[0] and n > 1:
        mb.fp(secs[0], mat, scols[0] if scols else (ecols[0] if ecols else col), g or (cents[1] - cents[0]), cents[1])
    if closed and caps[1] and n > 1:
        mb.fp(secs[-1], mat, scols[-2] if scols else (ecols[0] if ecols else col), g or (cents[-1] - cents[-2]), cents[-2])

def lathe(mb, prof, segs, mat, col, smooth=True, sp=False, colfn=None, axial=True, inside=False):
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
    shared = None
    if sp:
        shared = [ring(r, y) for r, y in prof]
        if len(prof) > 2 and abs(prof[0][0] - prof[-1][0]) < 1e-9 and abs(prof[0][1] - prof[-1][1]) < 1e-9 and prof[0][0] > 1e-6:
            shared[-1] = shared[0]
    for i in range(len(prof) - 1):
        (r0, y0), (r1, y1) = prof[i], prof[i + 1]
        if (r0 < 1e-6 and r1 < 1e-6) or (abs(r0 - r1) < 1e-9 and abs(y0 - y1) < 1e-9):
            continue
        a = shared[i] if sp else ring(r0, y0); b = shared[i + 1] if sp else ring(r1, y1)
        for k in range(segs):
            k1 = (k + 1) % segs
            idx = [a[k], b[k], b[k1], a[k1]]; uvs = [uv(i, k), uv(i + 1, k), uv(i + 1, k + 1), uv(i, k + 1)]
            if abs(y0 - y1) < 1e-6:
                uvs = [(r * cos(2 * pi * kk / segs) * SU + o[0], r * sin(2 * pi * kk / segs) * SV + o[1])
                       for r, kk in ((r0, k), (r1, k), (r1, k + 1), (r0, k + 1))]
            if r0 < 1e-6:
                idx = idx[:3]; uvs = uvs[:3]
            elif r1 < 1e-6:
                idx = [idx[0], idx[1], idx[3]]; uvs = [uvs[0], uvs[1], uvs[3]]
            if inside:
                idx = idx[::-1]; uvs = uvs[::-1]
            mb.f(idx, mat, colfn(i, k) if colfn else col, uvs, smooth)

def tube(mb, path, rad, sides, mat, col, caps=(True, True), mode='smooth', scols=None):
    path = [Vector(p) for p in path]; n = len(path)
    rads = rad if isinstance(rad, (list, tuple)) else [rad] * n
    secs = []; nrm = None
    for i in range(n):
        t = (path[min(i + 1, n - 1)] - path[max(i - 1, 0)]).normalized()
        if nrm is None:
            ref = Vector((0, 1, 0)) if abs(t.y) < 0.9 else Vector((1, 0, 0))
            nrm = ref - t * ref.dot(t)
        else:
            nrm = nrm - t * nrm.dot(t)
        nrm.normalize(); bn = t.cross(nrm)
        secs.append([path[i] + (nrm * cos(2 * pi * k / sides) + bn * sin(2 * pi * k / sides)) * rads[i] for k in range(sides)])
    loft(mb, secs, mat, col, True, caps, mode, scols=scols)

def ellipsoid(mb, c, radii, mat, col, segs=12, rings=7, M=None):
    prof = [(0.0 if i in (0, rings) else sin(pi * i / rings), -cos(pi * i / rings)) for i in range(rings + 1)]
    X = T(c) @ (M if M is not None else Matrix.Identity(4)) @ S(*radii)
    with xf(mb, X):
        lathe(mb, prof, segs, mat, col, True, True)

def torus(mb, Rr, r, segs, psegs, mat, col, smooth=True):
    prof = [(Rr + r * cos(-pi / 2 + 2 * pi * i / psegs), r * sin(-pi / 2 + 2 * pi * i / psegs)) for i in range(psegs)]
    prof.append(prof[0])
    lathe(mb, prof, segs, mat, col, smooth, True)

def cyl(mb, r, y0, y1, segs, mat, col, smooth=True, bev=0.0, r1=None):
    r1 = r if r1 is None else r1
    if bev > 0:
        prof = [(0, y0), (r - bev, y0), (r, y0 + bev), (r1, y1 - bev), (r1 - bev, y1), (0, y1)]
    else:
        prof = [(0, y0), (r, y0), (r1, y1), (0, y1)]
    lathe(mb, prof, segs, mat, col, smooth)

# ---- 2D convex polygon helpers (x, z)
def poly_area(p):
    return 0.5 * sum(p[i][0] * p[(i + 1) % len(p)][1] - p[(i + 1) % len(p)][0] * p[i][1] for i in range(len(p)))

def poly_clean(p, eps=1e-4):
    out = []
    for q in p:
        if not out or abs(q[0] - out[-1][0]) + abs(q[1] - out[-1][1]) > eps:
            out.append(q)
    if len(out) > 1 and abs(out[0][0] - out[-1][0]) + abs(out[0][1] - out[-1][1]) <= eps:
        out.pop()
    res = []
    for i in range(len(out)):
        a = out[i - 1]; b = out[i]; c = out[(i + 1) % len(out)]
        if abs((b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])) > 1e-7:
            res.append(b)
    return res

def clip_half(p, a, b, c):
    out = []
    for i in range(len(p)):
        s = p[i]; e = p[(i + 1) % len(p)]
        ds = a * s[0] + b * s[1] - c; de = a * e[0] + b * e[1] - c
        if ds <= 0:
            out.append(s)
        if (ds < 0 < de) or (de < 0 < ds):
            t = ds / (ds - de); out.append((s[0] + (e[0] - s[0]) * t, s[1] + (e[1] - s[1]) * t))
    return out

def clip_rect(p, x0, x1, z0, z1):
    for a, b, c in ((-1, 0, -x0), (1, 0, x1), (0, -1, -z0), (0, 1, z1)):
        p = clip_half(p, a, b, c)
        if len(p) < 3:
            return []
    p = poly_clean(p)
    return p if len(p) >= 3 and abs(poly_area(p)) > 1e-4 else []

def inset_convex(p, d):
    if poly_area(p) < 0:
        p = p[::-1]
    n = len(p); lines = []
    for i in range(n):
        a = p[i]; b = p[(i + 1) % n]
        dx, dz = b[0] - a[0], b[1] - a[1]; l = sqrt(dx * dx + dz * dz)
        nx, nz = -dz / l, dx / l
        lines.append((a[0] + nx * d, a[1] + nz * d, dx / l, dz / l))
    out = []
    for i in range(n):
        x1, z1, dx1, dz1 = lines[i - 1]; x2, z2, dx2, dz2 = lines[i]
        den = dx1 * dz2 - dz1 * dx2
        if abs(den) < 1e-5:
            out.append((x2, z2)); continue
        t = ((x2 - x1) * dz2 - (z2 - z1) * dx2) / den
        out.append((x1 + dx1 * t, z1 + dz1 * t))
    if poly_area(out) <= 1e-5:
        return None
    for i in range(n):
        a = p[i]; b = p[(i + 1) % n]; c = out[i]; e = out[(i + 1) % n]
        if (b[0] - a[0]) * (e[0] - c[0]) + (b[1] - a[1]) * (e[1] - c[1]) <= 0:
            return None
    return out

def prism(mb, poly, y0, y1, mat, col, ch=0.0, grain=(0, 0, 1), bottom=True):
    poly = poly_clean(poly)
    if len(poly) < 3:
        return
    if poly_area(poly) < 0:
        poly = poly[::-1]
    mb.newoff()
    cx = sum(q[0] for q in poly) / len(poly); cz = sum(q[1] for q in poly) / len(poly)
    C = Vector((cx, (y0 + y1) / 2, cz))
    top = inset_convex(poly, ch) if ch > 0 else None
    n = len(poly)
    if top is None:
        mb.fp([(x, y1, z) for x, z in poly], mat, col, grain, C); ys = y1
    else:
        mb.fp([(x, y1, z) for x, z in top], mat, col, grain, C); ys = y1 - ch
        dk = mul(col, 0.8)
        for i in range(n):
            j = (i + 1) % n
            mb.fp([(poly[i][0], ys, poly[i][1]), (poly[j][0], ys, poly[j][1]),
                   (top[j][0], y1, top[j][1]), (top[i][0], y1, top[i][1])], mat, dk, grain, C)
    for i in range(n):
        j = (i + 1) % n
        mb.fp([(poly[i][0], y0, poly[i][1]), (poly[j][0], y0, poly[j][1]),
               (poly[j][0], ys, poly[j][1]), (poly[i][0], ys, poly[i][1])], mat, col, grain, C)
    if bottom:
        mb.fp([(x, y0, z) for x, z in poly], mat, col, grain, C)

# ---------------------------------------------------------------- Brigantine hull form
NS = 60                                     # longitudinal hull samples
YS = [-1.10, -1.07, -0.99, -0.80, -0.52, -0.22, 0.06, 0.34, 0.62, 0.90, 1.14, 1.38, 1.66, 1.95, 2.25]
VS = [(y + 1.10) / 3.35 for y in YS]
J_BOOT = YS.index(0.06)
J_WALE = YS.index(0.90)
J_SILL = YS.index(1.38)
J_SHEER = len(YS) - 2
YT = -0.18                                  # bottom of stern transom

def hull_th(y):
    """Planking thickness: slightly thinner at bottom for generous 2.1 m hold headroom."""
    return 0.10 + (TH - 0.10) * smooth01((y + 1.05) / 0.42)

# Stem cubic Bezier from keel forefoot (-1.10, -5.4) to sweeping prow (1.25, -9.20)
_SB = []
for _i in range(241):
    _t = _i / 240.0
    _b = ((1 - _t) ** 3, 3 * (1 - _t) ** 2 * _t, 3 * (1 - _t) * _t * _t, _t ** 3)
    _SB.append((-1.10 * _b[0] - 1.10 * _b[1] + 0.10 * _b[2] + DECK_Y * _b[3],
                -5.40 * _b[0] - 8.20 * _b[1] - 9.05 * _b[2] + Z_BOW * _b[3]))

def zstem(y):
    if y <= -1.10:
        return -5.40
    if y >= DECK_Y:
        d = y - DECK_Y
        return Z_BOW - 0.14 * d - 0.14 * d * d
    lo, hi = 0, 240
    while hi - lo > 1:
        m = (lo + hi) // 2
        if _SB[m][0] < y:
            lo = m
        else:
            hi = m
    (y0, z0), (y1, z1) = _SB[lo], _SB[hi]
    return z0 + (z1 - z0) * (y - y0) / max(y1 - y0, 1e-9)

def zstern(y):
    return Z_STERN + 0.22 * (max(y, YT) - DECK_Y)

def tumble(y):
    return 1.0 if y <= 1.05 else 1.0 - 0.055 * ((y - 1.05) / 1.25) ** 1.3

def bmid(y):
    h = max(0.0, min(1.0, (y + 1.10) / 2.15))
    return HALF_BEAM * (1 - (1 - h) ** 3.0) ** (1 / 3.6) * tumble(y)

def wtrans(y):
    if y <= YT:
        return 0.0
    h = min(1.0, (y - YT) / (DECK_Y - YT))
    return 1.92 * (1 - (1 - h) ** 2.4) ** (1 / 2.2) * tumble(y)

def hull_b(z, y):
    bm = bmid(y)
    if z >= 0:
        t = min(1.0, z / zstern(y))
        return bm - (bm - wtrans(y)) * t ** 2.8
    t = min(1.0, z / zstem(y))
    return bm * max(0.0, 1 - t ** 2.5) ** 0.72

def ytop(z):
    """Bold sweeping Brigantine sheer rising strongly at prow and stern castle."""
    if z < 0:
        return 2.25 + 0.68 * (-z / abs(Z_BOW)) ** 2
    return 2.25 + 0.72 * smooth01((z - 1.8) / 4.2) + 0.15 * (z / Z_STERN) ** 2

def umap(s):
    return 1.0 - (1.0 - min(max(s / NS, 0.0), 1.0)) ** 1.4

def z_approx(u):
    return Z_STERN + (Z_BOW - Z_STERN) * u

def hull_pt(u, v):
    yt = ytop(z_approx(u))
    y = -1.10 + v * (yt + 1.10)
    zs = zstern(y); z = zs + (zstem(y) - zs) * u
    return Vector((hull_b(z, y), y, z))

def hull_n(u, v):
    e = 2e-3
    pu = hull_pt(min(u + e, 1.0), v) - hull_pt(max(u - e, 0.0), v)
    pv = hull_pt(u, v + e) - hull_pt(u, max(v - e, 0.0))
    n = pu.cross(pv)
    if n.length < 1e-12:
        return Vector((1, 0, 0))
    return n.normalized()

def v_of_y(u, y):
    return (y + 1.10) / (ytop(z_approx(u)) + 1.10)

def s_of_z(z, v=1.0):
    lo, hi = 0.0, float(NS)
    for _ in range(40):
        m = (lo + hi) / 2
        if hull_pt(umap(m), v).z > z:
            lo = m
        else:
            hi = m
    return (lo + hi) / 2

def hull_in(u, v):
    p = hull_pt(u, v); p = p - hull_n(u, v) * hull_th(p.y)
    p.x = max(p.x, 0.0)
    return p

def inner_half(z, y):
    lo, hi = 0.0, 1.0
    for _ in range(26):
        v = (lo + hi) / 2
        if hull_in(umap(s_of_z(z, v)), v).y < y:
            lo = v
        else:
            hi = v
    v = (lo + hi) / 2
    return hull_in(umap(s_of_z(z, v)), v).x

# ---------------------------------------------------------------- procedural textures & materials
def tile_noise(rs, w, h, gx, gy):
    g = rs.rand(gy, gx)
    ys = np.arange(h) * gy / h; xs = np.arange(w) * gx / w
    y0 = np.floor(ys).astype(int); x0 = np.floor(xs).astype(int)
    fy = ys - y0; fx = xs - x0
    fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)
    y1 = (y0 + 1) % gy; x1 = (x0 + 1) % gx
    a = g[np.ix_(y0, x0)]; b = g[np.ix_(y0, x1)]; c = g[np.ix_(y1, x0)]; d = g[np.ix_(y1, x1)]
    FX = fx[None, :]; FY = fy[:, None]
    return (a * (1 - FX) + b * FX) * (1 - FY) + (c * (1 - FX) + d * FX) * FY

def make_image(name, arr):
    h, w = arr.shape[:2]
    rgba = np.ones((h, w, 4), dtype=np.float32)
    rgba[..., :3] = np.clip(arr, 0, 1)
    img = bpy.data.images.new(name, w, h, alpha=False)
    img.pixels.foreach_set(rgba.ravel())
    img.file_format = 'PNG'
    img.pack()
    return img

def tex_wood(rs):
    w = h = 256
    warp = tile_noise(rs, w, h, 3, 4) * 0.085
    yy = (np.arange(h)[:, None] / h + warp) % 1.0
    lines = np.zeros((h, w))
    for freq, amp in ((8, 0.50), (21, 0.30), (49, 0.20)):
        ph = rs.rand() * 6.28
        lines += amp * (0.5 + 0.5 * np.sin(yy * 2 * pi * freq + ph + tile_noise(rs, w, h, 2, 6) * 3.0))
    streak = tile_noise(rs, w, h, 3, 48) * 0.6 + tile_noise(rs, w, h, 6, 96) * 0.4
    val = 0.80 + 0.12 * lines + 0.10 * (streak - 0.5) * 2
    dark = np.clip((0.30 - streak) * 6, 0, 1) * 0.17
    val = val - dark + (tile_noise(rs, w, h, 64, 64) - 0.5) * 0.04
    return np.stack([val, val * 0.965, val * 0.92], axis=-1)

def compass_star_layers(X, Y):
    """Original geometric 8-point nautical compass-star emblem in unit coordinates (outer radius ~1.65).
    Returns (indigo_mask, teal_mask, gold_mask) boolean arrays."""
    r = np.hypot(X, Y)
    th = np.arctan2(Y, X)

    # Outer compass ring + 16 degree ticks
    outer_ring = (r > 0.84) & (r < 0.96)
    tick_ang = np.abs(((th / (2 * pi) * 16 + 0.5) % 1.0) - 0.5) * 2
    ticks = (r >= 0.95) & (r < 1.12) & (tick_ang < 0.16)

    # 4 cardinal spear points (N/S/E/W) reaching r = 1.68, meeting cleanly along the 45-deg diagonals
    ax = np.abs(X); ay = np.abs(Y)
    card_v = (ax < 0.35 * np.clip(1.0 - ay / 1.68, 0.0, 1.0)) & (ay < 1.68) & (ay >= ax)
    card_h = (ay < 0.35 * np.clip(1.0 - ax / 1.68, 0.0, 1.0)) & (ax < 1.68) & (ax > ay)
    card_all = card_v | card_h
    # Classic faceted split: alternating gold / indigo halves around each cardinal arm
    card_gold = (card_v & (((Y >= 0) & (X >= 0)) | ((Y < 0) & (X < 0)))) | \
                (card_h & (((X >= 0) & (Y < 0)) | ((X < 0) & (Y >= 0))))
    card_indigo = card_all & ~card_gold

    # 4 intercardinal diamond points (NE/NW/SE/SW) rotated 45 deg, reaching r = 1.26
    c45 = sqrt(0.5)
    U = (X + Y) * c45; V = (-X + Y) * c45
    au = np.abs(U); av = np.abs(V)
    inter_1 = (au < 0.25 * np.clip(1.0 - av / 1.26, 0.0, 1.0)) & (av < 1.26)
    inter_2 = (av < 0.25 * np.clip(1.0 - au / 1.26, 0.0, 1.0)) & (au < 1.26)
    inter_all = (inter_1 | inter_2) & ~card_all

    # Crisp central gilded compass jewel framed by a sharp indigo diamond collar
    d_man = ax + ay
    center_gold = d_man < 0.21
    center_collar = (d_man >= 0.21) & (d_man < 0.30)

    gold_mask = (card_gold | center_gold) & ~center_collar
    indigo_mask = (card_indigo | outer_ring | ticks | center_collar) & ~center_gold
    teal_mask = inter_all & ~gold_mask & ~indigo_mask
    return indigo_mask, teal_mask, gold_mask

def tex_sail(rs):
    """512x512 (2x supersampled) cream canvas with indigo border trim, gold pinstripe, seams, patches & compass-star emblem."""
    W = 512; ss = 2; w = W * ss
    yy, xx = np.mgrid[0:w, 0:w] / float(w)
    weave = 0.975 + 0.02 * np.sin(xx * 2 * pi * 136) * np.sin(yy * 2 * pi * 136) + \
            0.03 * (tile_noise(rs, w, w, 256, 256) - 0.5)
    blot = 0.91 + 0.09 * tile_noise(rs, w, w, 5, 5)
    base = np.array([0.95, 0.90, 0.77])
    img = base[None, None, :] * (weave * blot)[..., None]

    # Subtle weathered foot & edge salt-darkening
    img *= (1.0 - 0.09 * np.clip((0.18 - yy) / 0.18, 0, 1))[..., None]
    img *= (1.0 - 0.05 * np.clip((np.abs(xx - 0.5) - 0.43) / 0.07, 0, 1))[..., None]

    # Bold indigo border bands along top, bottom, and side leeches + crisp gold inner pinstripe
    brush_n = (tile_noise(rs, w, w, 36, 36) - 0.5) * 0.008
    bx = np.minimum(xx, 1.0 - xx) + brush_n
    by = np.minimum(yy, 1.0 - yy) + brush_n
    indigo_col = np.array([0.14, 0.23, 0.42]) * (0.88 + 0.18 * tile_noise(rs, w, w, 10, 10))[..., None] * weave[..., None]
    teal_col = np.array([0.09, 0.52, 0.58]) * (0.88 + 0.18 * tile_noise(rs, w, w, 10, 10))[..., None] * weave[..., None]
    gold_col = np.array([0.91, 0.71, 0.22]) * (0.90 + 0.16 * tile_noise(rs, w, w, 12, 12))[..., None] * weave[..., None]

    border_ind = (bx < 0.085) | (by < 0.075)
    border_gold = ((bx >= 0.092) & (bx < 0.107) & (by >= 0.082)) | \
                  ((by >= 0.082) & (by < 0.097) & (bx >= 0.092))
    img[border_ind] = indigo_col[border_ind]
    img[border_gold] = gold_col[border_gold]

    # Sailmaker stitched patches
    def rect(x0, x1, y0, y1):
        return (xx > x0) & (xx < x1) & (yy > y0) & (yy < y1)
    for (x0, x1, y0, y1, tint) in ((0.14, 0.27, 0.65, 0.80, (0.92, 0.94, 0.97)),
                                   (0.73, 0.86, 0.15, 0.29, (0.99, 0.92, 0.80)),
                                   (0.16, 0.26, 0.16, 0.27, (0.94, 0.89, 0.82))):
        m = rect(x0, x1, y0, y1) & ~border_ind & ~border_gold
        img[m] *= np.array(tint)
        edge = rect(x0 - 0.005, x1 + 0.005, y0 - 0.005, y1 + 0.005) & ~rect(x0 + 0.004, x1 - 0.004, y0 + 0.004, y1 - 0.004)
        dash = (np.sin((xx + yy) * 2 * pi * 64) > -0.2)
        img[edge & dash & ~border_ind] *= 0.60

    # Vertical cloth panel seams
    for kx in range(1, 7):
        d = np.abs(xx - kx / 7.0)
        img[d < 0.0028] *= 0.76
        img[(d > 0.0055) & (d < 0.0075) & (np.sin(yy * 2 * pi * 72) > 0)] *= 0.88

    # Horizontal reef bands + reef points
    for ry in (0.28, 0.72):
        d = np.abs(yy - ry)
        img[d < 0.0075] *= 0.86
        img[(d < 0.028) & (yy < ry) & (np.abs(((xx * 26) % 1.0) - 0.5) < 0.045)] *= 0.64

    # Centered original 8-point compass-star emblem
    R0 = 0.205
    edge_n = (tile_noise(rs, w, w, 44, 44) - 0.5) * 0.045
    X = (xx - 0.5) / R0 * (1.0 + edge_n)
    Y = (yy - 0.50) / R0 * (1.0 + edge_n)
    m_ind, m_teal, m_gold = compass_star_layers(X, Y)
    img[m_teal] = teal_col[m_teal]
    img[m_ind] = indigo_col[m_ind]
    img[m_gold] = gold_col[m_gold]

    return img.reshape(W, ss, W, ss, 3).mean(axis=(1, 3))

def tex_flag(rs):
    """Deep indigo masthead pennant with teal/gold borders and crisp golden compass star."""
    W, H, ss = 256, 128, 2; w, h = W * ss, H * ss
    yy, xx = np.mgrid[0:h, 0:w]; xx = xx / float(w); yy = yy / float(h)
    n = 0.88 + 0.14 * tile_noise(rs, w, h, 8, 4)
    img = np.array([0.13, 0.22, 0.42])[None, None, :] * n[..., None]
    # Ocean-teal horizontal top & bottom bands + gold pinstripe
    by = np.minimum(yy, 1.0 - yy)
    img[by < 0.14] = np.array([0.09, 0.52, 0.58])[None, None, :] * n[by < 0.14, None]
    img[(by >= 0.14) & (by < 0.19)] = np.array([0.92, 0.72, 0.22])
    img[xx < 0.032] = (0.94, 0.88, 0.72)
    # Crisp compass star near the hoist
    X = (xx - 0.30) * 2.0 / 0.185
    Y = (yy - 0.50) / 0.185
    m_ind, m_teal, m_gold = compass_star_layers(X, Y)
    img[m_teal] = (0.14, 0.76, 0.80)
    img[m_ind] = (0.96, 0.90, 0.72)
    img[m_gold] = (0.96, 0.76, 0.24)
    return img.reshape(H, ss, W, ss, 3).mean(axis=(1, 3))

MATS = {}
MAT_NAMES = {
    'wood': 'mat_wood', 'paint': 'mat_paint', 'rope': 'mat_rope', 'iron': 'mat_iron', 'brass': 'mat_brass',
    'glass': 'mat_lantern_glass', 'window': 'mat_window_glass', 'canvas': 'mat_canvas', 'canvas_back': 'mat_canvas_back',
    'cloth': 'mat_cloth', 'flag': 'mat_flag', 'canvas_lod': 'mat_canvas_lod', 'canvas_back_lod': 'mat_canvas_back_lod',
    'col': 'mat_collision',
}

def load_pbr_image(tex_dir, filename, non_color=False):
    path = os.path.join(tex_dir, filename)
    if not os.path.isfile(path):
        return None
    img = bpy.data.images.load(path, check_existing=True)
    if non_color:
        img.colorspace_settings.name = 'Non-Color'
    img.pack()
    return img

def make_materials(outdir=None):
    rs = np.random.RandomState(SEED)
    tex_dir = os.path.join(outdir, 'textures') if outdir else os.path.join(os.getcwd(), 'assets', 'generated', 'textures')
    sail_px = tex_sail(rs)
    wood_alb = load_pbr_image(tex_dir, 'ship_oak_albedo.png') or make_image('brigantine_wood', tex_wood(rs))
    wood_nrm = load_pbr_image(tex_dir, 'ship_oak_normal.png', True)
    wood_rgh = load_pbr_image(tex_dir, 'ship_oak_rough.png', True)
    paint_alb = load_pbr_image(tex_dir, 'ship_paint_albedo.png')
    paint_nrm = load_pbr_image(tex_dir, 'ship_paint_normal.png', True)
    paint_rgh = load_pbr_image(tex_dir, 'ship_paint_rough.png', True)
    iron_alb = load_pbr_image(tex_dir, 'ship_iron_albedo.png')
    iron_nrm = load_pbr_image(tex_dir, 'ship_iron_normal.png', True)
    iron_rgh = load_pbr_image(tex_dir, 'ship_iron_rough.png', True)
    brass_alb = load_pbr_image(tex_dir, 'ship_brass_albedo.png')
    brass_nrm = load_pbr_image(tex_dir, 'ship_brass_normal.png', True)
    brass_rgh = load_pbr_image(tex_dir, 'ship_brass_rough.png', True)
    rope_alb = load_pbr_image(tex_dir, 'ship_rope_albedo.png')
    rope_nrm = load_pbr_image(tex_dir, 'ship_rope_normal.png', True)
    rope_rgh = load_pbr_image(tex_dir, 'ship_rope_rough.png', True)
    cloth_alb = load_pbr_image(tex_dir, 'ship_cloth_albedo.png')
    cloth_nrm = load_pbr_image(tex_dir, 'ship_cloth_normal.png', True)
    sail = make_image('brigantine_sail', sail_px)
    flag = make_image('brigantine_flag', tex_flag(rs))
    back = sail_px * 0.42 + np.array([1.0, 0.95, 0.82]) * 0.58
    sail_back = make_image('brigantine_sail_back', back)

    def mk(name, tex=None, rough=0.8, metal=0.0, emit=0.0, two=False, alpha=1.0, emit_col=(1.0, 0.62, 0.22, 1),
           norm_tex=None, norm_strength=0.9, rough_tex=None):
        m = bpy.data.materials.new(MAT_NAMES[name])
        if m.node_tree is None:
            m.use_nodes = True
        nt = m.node_tree; b = nt.nodes['Principled BSDF']
        b.inputs['Roughness'].default_value = rough; b.inputs['Metallic'].default_value = metal
        ca = nt.nodes.new('ShaderNodeVertexColor'); ca.layer_name = 'Color'
        if tex is not None:
            t = nt.nodes.new('ShaderNodeTexImage'); t.image = tex
            mx = nt.nodes.new('ShaderNodeMix'); mx.data_type = 'RGBA'; mx.blend_type = 'MULTIPLY'
            mx.inputs[0].default_value = 1.0
            nt.links.new(t.outputs['Color'], mx.inputs[6]); nt.links.new(ca.outputs['Color'], mx.inputs[7])
            nt.links.new(mx.outputs[2], b.inputs['Base Color'])
        else:
            nt.links.new(ca.outputs['Color'], b.inputs['Base Color'])
        if norm_tex is not None:
            tn = nt.nodes.new('ShaderNodeTexImage'); tn.image = norm_tex
            nm = nt.nodes.new('ShaderNodeNormalMap'); nm.inputs['Strength'].default_value = norm_strength
            nt.links.new(tn.outputs['Color'], nm.inputs['Color'])
            nt.links.new(nm.outputs['Normal'], b.inputs['Normal'])
        if rough_tex is not None:
            tr = nt.nodes.new('ShaderNodeTexImage'); tr.image = rough_tex
            nt.links.new(tr.outputs['Color'], b.inputs['Roughness'])
        if emit > 0:
            b.inputs['Emission Color'].default_value = emit_col
            b.inputs['Emission Strength'].default_value = emit
        if alpha < 1.0:
            b.inputs['Alpha'].default_value = alpha
            m.surface_render_method = 'BLENDED'
        m.use_backface_culling = not two
        MATS[name] = m

    mk('wood', wood_alb, 0.80, norm_tex=wood_nrm, norm_strength=0.95, rough_tex=wood_rgh)
    mk('paint', paint_alb, 0.56, norm_tex=paint_nrm, norm_strength=0.65, rough_tex=paint_rgh)
    mk('rope', rope_alb, 0.94, norm_tex=rope_nrm, norm_strength=1.05, rough_tex=rope_rgh)
    mk('iron', iron_alb, 0.48, 0.62, norm_tex=iron_nrm, norm_strength=0.85, rough_tex=iron_rgh)
    mk('brass', brass_alb, 0.28, 0.88, norm_tex=brass_nrm, norm_strength=0.60, rough_tex=brass_rgh)
    mk('glass', None, 0.24, 0.0, 2.2)
    mk('window', None, 0.08, 0.0, 0.35, two=True, alpha=0.32)
    mk('canvas', sail, 0.94, norm_tex=cloth_nrm, norm_strength=0.35)
    mk('canvas_back', sail_back, 0.94, emit=0.22, emit_col=(1.0, 0.87, 0.62, 1), norm_tex=cloth_nrm, norm_strength=0.35)
    mk('cloth', cloth_alb, 0.92, two=True, norm_tex=cloth_nrm, norm_strength=0.72)
    mk('flag', flag, 0.90, two=True)
    mk('col', None, 1.0)
    small = sail_px.reshape(128, 4, 128, 4, 3).mean(axis=(1, 3))
    mk('canvas_lod', make_image('brigantine_sail_lod', small), 0.94)
    mk('canvas_back_lod', make_image('brigantine_sail_back_lod', small * 0.42 + np.array([1.0, 0.95, 0.82]) * 0.58),
       0.94, emit=0.22, emit_col=(1.0, 0.87, 0.62, 1))

# ---------------------------------------------------------------- object creation
def conv(p):
    return (p[0], -p[2], p[1])

OBJS = {}
def build(mb):
    me = bpy.data.meshes.new(mb.name)
    rinv = Matrix.Rotation(radians(-mb.yaw), 3, 'Y')
    if mb.gmatrix is not None:
        me.from_pydata([conv(v) for v in mb.verts], [], mb.faces)
    else:
        me.from_pydata([conv(rinv @ (v - mb.origin)) for v in mb.verts], [], mb.faces)
    names = sorted(set(mb.fmat))
    for n in names:
        me.materials.append(MATS[n])
    mi = {n: i for i, n in enumerate(names)}
    uvl = me.uv_layers.new(name='UVMap')
    ca = me.color_attributes.new('Color', 'FLOAT_COLOR', 'CORNER')
    uvs = []; cols = []; uv2 = []
    wv = [mb.wfn(v) for v in mb.verts] if mb.wfn else None
    for fi, f in enumerate(mb.faces):
        c = mb.fcol[fi]
        for k in range(len(f)):
            uvs.extend(mb.fuv[fi][k])
            cc = c[k] if isinstance(c, list) else c
            cols.extend((cc[0], cc[1], cc[2], 1.0))
            if wv:
                uv2.extend(wv[f[k]])
    uvl.data.foreach_set('uv', uvs)
    ca.data.foreach_set('color', cols)
    if wv:
        u2 = me.uv_layers.new(name='Wind')
        u2.data.foreach_set('uv', uv2)
    me.polygons.foreach_set('material_index', [mi[m] for m in mb.fmat])
    me.polygons.foreach_set('use_smooth', mb.fsm)
    me.update()
    ob = bpy.data.objects.new(mb.name, me)
    if mb.gmatrix is not None:
        C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
        ob.matrix_world = C @ mb.gmatrix @ C.inverted()
    elif mb.parent is not None:
        po = mb.parent; pr = Matrix.Rotation(radians(-po.yaw), 3, 'Y')
        ob.parent = OBJS[po.name][0]
        ob.location = conv(pr @ (mb.origin - po.origin))
        ob.rotation_euler = (0, 0, radians(mb.yaw - po.yaw))
    else:
        ob.location = conv(mb.origin)
        ob.rotation_euler = (0, 0, radians(mb.yaw))
    bpy.context.scene.collection.objects.link(ob)
    OBJS[mb.name] = (ob, mb.tris())
    return ob

def empty_anchor(name, origin, yaw=0.0):
    """Named Node3D anchor (glTF Empty) preserving exact origin after merging static geometry into Hull."""
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.25
    e.location = conv(origin)
    if yaw != 0.0:
        e.rotation_euler = (0, 0, radians(yaw))
    bpy.context.scene.collection.objects.link(e)
    return e

def col_piece(name, pts):
    bm = bmesh.new()
    seen = set()
    for p in pts:
        k = tuple(round(c, 4) for c in conv(p))
        if k not in seen:
            seen.add(k); bm.verts.new(k)
    bm.verts.index_update()
    r = bmesh.ops.convex_hull(bm, input=bm.verts)
    junk = list({e for e in r['geom_interior'] + r['geom_unused'] if isinstance(e, bmesh.types.BMVert)})
    junk.sort(key=lambda e: e.index)
    if junk:
        bmesh.ops.delete(bm, geom=junk, context='VERTS')
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    me.materials.append(MATS['col'])
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    OBJS[name] = (ob, 0)

# ================================================================ HULL & DAMAGE PANELS
def strake_look(j):
    """(outer colour, extra outward offset) for strake j: mahogany + cream boot + gilded wale + ocean-teal gunwale."""
    if YS[j + 1] <= 0.07:
        return C_TAR, 0.0
    if j == J_BOOT:
        return C_CREAM, 0.015
    if j == J_WALE:
        return C_GOLD, 0.055
    if j in (J_SILL, J_SILL + 1):
        return C_TEAL, 0.016
    if j == J_SHEER:
        return C_GOLD, 0.028
    return C_HULL, 0.0

def gap_ranges():
    return sorted((s_of_z(z1), s_of_z(z0)) for (z0, z1) in GAPS)

def top_intervals(s_end=NS):
    iv = []; a = 0.0
    for (g0, g1) in gap_ranges():
        iv.append((a, g0)); a = g1
    iv.append((a, float(s_end)))
    return iv

def hull_plank(mb, j, s0, s1, col, extra, inner_col):
    v0, v1 = VS[j], VS[j + 1]; dv = 0.02 / 3.05; b = 0.022
    ss = [s0, s0 + 0.07] + [float(s) for s in range(int(ceil(s0 + 0.35)), int(floor(s1 - 0.35)) + 1)] + [s1 - 0.07, s1]
    secs = []
    for i, s in enumerate(ss):
        u = umap(s); end = i in (0, len(ss) - 1)
        n0 = hull_n(u, v0); n1 = hull_n(u, v1); p0 = hull_pt(u, v0); p1 = hull_pt(u, v1)
        e = -b if end else extra
        A = p0 - n0 * b; D = p1 - n1 * b
        Bp = hull_pt(u, v0 + dv) + hull_n(u, v0 + dv) * e
        Cp = hull_pt(u, v1 - dv) + hull_n(u, v1 - dv) * e
        E = p1 - n1 * hull_th(p1.y); F = p0 - n0 * hull_th(p0.y)
        for q in (A, Bp, Cp, D, E, F):
            q.x = max(q.x, 0.0)
        secs.append([A, Bp, Cp, D, E, F])
    dk = mul(col, 0.55)
    loft(mb, secs, 'wood', col, True, (True, True), 'len',
         ecols=[dk, col, dk, mul(col, 0.9), inner_col, inner_col], uniform_w=True)

# 10 damage slots (01-05 starboard, 06-10 port), all inside the hollow hold
J_LOW = YS.index(-0.22)
J_HIGH = YS.index(0.62)
HOLES = [
    (1, -4.2, J_LOW), (1, -2.0, J_HIGH), (1, 0.2, J_LOW), (1, 2.5, J_HIGH), (1, 5.0, J_LOW),
    (-1, -3.5, J_HIGH), (-1, -1.2, J_LOW), (-1, 1.3, J_HIGH), (-1, 3.7, J_LOW), (-1, 5.5, J_HIGH),
]
PANEL_HALF = 0.48
PANELS = []

def plan_panels():
    PANELS.clear()
    for idx, (sg, z, jb) in enumerate(HOLES):
        v = VS[jb]; sc = s_of_z(z, v); e = 0.01
        mps = (hull_pt(umap(sc + e), v) - hull_pt(umap(sc - e), v)).length / (2 * e)
        u = umap(sc); p = hull_pt(u, v); n = hull_n(u, v)
        mpv = (hull_pt(u, v + 1e-3) - hull_pt(u, v - 1e-3)).length / 2e-3
        org = p - n * (TH / 2); org.x *= sg
        PANELS.append(dict(
            idx=idx, side=sg, jb=jb, sc=sc,
            sa=sc - PANEL_HALF / mps, sb=sc + PANEL_HALF / mps,
            mps=mps, mpv=mpv, v=v, origin=org,
            yaw=math.degrees(atan2(-n.x * sg, -n.z)),
            cols={}, mb=None,
        ))
    for P in PANELS:
        P['mb'] = MB('HullPanel_%02d' % (P['idx'] + 1), P['origin'], seed=P['idx'], yaw=P['yaw'])

def build_hull(mb):
    rng = mb.rng
    plan_panels()
    for side in (1, -1):
        with xf(mb, S(side, 1, 1)):
            for j in range(len(YS) - 1):
                base, extra = strake_look(j)
                ivs = top_intervals(NS - 0.05) if j >= J_SILL else [(0.0, NS - 0.05)]
                here = [P for P in PANELS if P['side'] == side and j in (P['jb'] - 1, P['jb'])]
                for (a, bnd) in ivs:
                    cuts = [a]; s = a - rng.uniform(0, 6)
                    while True:
                        s += rng.uniform(8, 14)
                        if s > bnd - 3:
                            break
                        if s > a + 3:
                            cuts.append(float(round(s)))
                    cuts.append(bnd)
                    for P in here:
                        cuts = [c for c in cuts if c in (a, bnd) or not (P['sa'] - 2.2 < c < P['sb'] + 2.2)] + [P['sa'], P['sb']]
                    cuts.sort()
                    for k in range(len(cuts) - 1):
                        amt = 0.05 if base in (C_GOLD, C_TEAL, C_CREAM) else 0.13
                        inner = jit(C_INNER if j <= J_WALE else C_HULL, rng, 0.10)
                        colr = jit(base, rng, amt)
                        P = next((P for P in here if abs(cuts[k] - P['sa']) < 1e-9 and abs(cuts[k + 1] - P['sb']) < 1e-9), None)
                        if P is None:
                            hull_plank(mb, j, cuts[k], cuts[k + 1], colr, extra, inner)
                        else:
                            P['cols'][j] = (colr, inner, extra)
                            with xf(P['mb'], S(side, 1, 1)):
                                hull_plank(P['mb'], j, cuts[k], cuts[k + 1], colr, extra, inner)

    # Swept keel + cutwater stem
    path = [(Z_STERN - 0.25, -1.10), (3.0, -1.10), (-1.5, -1.10), (-5.40, -1.10)]
    for i in range(8, 241, 8):
        path.append((_SB[i][1], _SB[i][0]))
    for y in (1.55, 1.90, 2.25, 2.60, 2.90, 3.12):
        path.append((zstem(y), y))
    secs = []; scols = []
    for i, (z, y) in enumerate(path):
        a = path[max(i - 1, 0)]; b = path[min(i + 1, len(path) - 1)]
        t = Vector((b[0] - a[0], b[1] - a[1])).normalized(); n = Vector((-t.y, t.x))
        do = 0.22 if y < -0.95 else 0.28; di = 0.11; w = 0.145; c = 0.038
        o = Vector((0, y + n.y * do, z + n.x * do))
        o2 = Vector((0, y + n.y * (do - c), z + n.x * (do - c)))
        q = Vector((0, y - n.y * di, z - n.x * di))
        secs.append([q + Vector((-w, 0, 0)), q + Vector((w, 0, 0)), o2 + Vector((w, 0, 0)),
                     o + Vector((w - c, 0, 0)), o + Vector((-(w - c), 0, 0)), o2 + Vector((-w, 0, 0))])
        scols.append(C_TAR if y < 0.10 else C_GOLD)
    loft(mb, secs, 'wood', C_TAR, True, (True, True), 'flat', scols=scols)
    box2(mb, (-0.145, -1.32, Z_STERN - 0.35), (0.145, -0.05, Z_STERN - 0.08), 'wood', C_TAR, 0.03)  # sternpost

    # Ornate raked transom with 3 tall gilded stern windows & carved compass-star medallion
    ang = math.degrees(math.atan(0.22))
    def tplank(y0, y1, col, extra=0.0, th=0.15):
        secs = []
        for sg in (-1, 0, 1):
            def P(y, dz): return Vector((sg * wtrans(y), y, zstern(y) + dz))
            d = min(0.02, (y1 - y0) * 0.2)
            secs.append([P(y0, -0.02), P(y0 + d, extra), P(y1 - d, extra), P(y1, -0.02), P(y1, -th), P(y0, -th)])
        inner = jit(C_INNER, rng, 0.08)
        loft(mb, secs, 'wood', col, True, (True, True), 'flat',
             ecols=[mul(col, 0.55), col, mul(col, 0.55), col, inner, inner])
    yts = ytop(Z_STERN)
    for (y0, y1, c, ex) in (
        (YT, 0.10, C_TAR, 0), (0.10, 0.40, C_HULL, 0), (0.40, 0.56, C_GOLD, 0.035), (0.56, 0.70, C_TEAL, 0),
        (1.60, 1.74, C_TEAL, 0), (1.74, 1.90, C_GOLD, 0.035), (1.90, 2.25, C_HULL, 0),
        (2.25, 2.65, C_INDIGO, 0), (2.65, yts - 0.16, C_HULL, 0), (yts - 0.16, yts, C_GOLD, 0.035),
    ):
        tplank(y0, y1, jit(c, rng, 0.06), ex)

    def tpier(xa, xb):
        X = lambda f, y: f(y) if callable(f) else f
        pts = [(X(x, y), y, zstern(y) + dz) for y in (0.70, 1.60)
               for (x, dz) in ((xa, -0.15), (xb, -0.15), (xb, 0.0), (xa, 0.0))]
        c = jit(C_TEAL, rng, 0.06); cen = sum((Vector(q) for q in pts), Vector()) / 8; mb.newoff()
        for q, cc in (((0, 1, 2, 3), c), ((4, 5, 6, 7), c), ((0, 1, 5, 4), jit(C_INNER, rng, 0.08)),
                      ((1, 2, 6, 5), c), ((2, 3, 7, 6), c), ((3, 0, 4, 7), c)):
            mb.fp([pts[i] for i in q], 'wood', cc, (0, 1, 0), cen)
    tpier(lambda y: -wtrans(y), -1.44); tpier(-0.66, -0.42); tpier(0.42, 0.66); tpier(1.44, lambda y: wtrans(y))

    with xf(mb, T(0, DECK_Y, Z_STERN) @ R('X', ang)):
        ca = cos(radians(ang))
        def ly(y): return (y - DECK_Y) / ca
        for wx in (-1.05, 0.0, 1.05):
            y0, y1 = ly(0.70), ly(1.60); hw = 0.39
            mb.newoff()
            mb.fp([(wx - hw, y0, -0.075), (wx + hw, y0, -0.075), (wx + hw, y1, -0.075), (wx - hw, y1, -0.075)],
                  'window', (0.85, 0.94, 0.88), None, (wx, 0, -5))
            for zf, dz in ((0.04, 0.08), (-0.18, 0.05)):
                mat_f = 'brass' if zf > 0 else 'wood'
                col_f = C_BRASS if zf > 0 else C_DARK
                for (cx, cy, sx, sy) in (
                    (wx, y0, hw * 2 + 0.14, 0.095), (wx, y1, hw * 2 + 0.14, 0.095),
                    (wx - hw, (y0 + y1) / 2, 0.095, y1 - y0), (wx + hw, (y0 + y1) / 2, 0.095, y1 - y0),
                    (wx, (y0 + y1) / 2, 0.05, y1 - y0), (wx, (y0 + y1) / 2, hw * 2, 0.05),
                ):
                    cbox(mb, (cx, cy, zf), (sx, sy, dz), mat_f, col_f, 0.015)

        # Carved gilded 8-point Compass-Star medallion on the stern frieze
        sy = ly(2.42)
        with xf(mb, T(0, sy, 0.01) @ M_Y2Z):
            lathe(mb, [(0, 0), (0.36, 0), (0.36, 0.045), (0.30, 0.075), (0, 0.08)], 16, 'paint', C_INDIGO)
            torus(mb, 0.34, 0.032, 16, 6, 'brass', C_BRASS)
        for k in range(8):
            major = (k % 2 == 0)
            L_pt = 0.56 if major else 0.40
            W_pt = 0.085 if major else 0.055
            col_a = C_GOLD if major else C_TEAL
            with xf(mb, T(0, sy, 0.04) @ R('Z', k * 45)):
                mb.newoff()
                mb.fp([(-W_pt, 0.14, 0.0), (0, 0.16, 0.06), (0, L_pt, 0.0)], 'paint', col_a, None, (0, 0.3, -1))
                mb.fp([(W_pt, 0.14, 0.0), (0, 0.16, 0.06), (0, L_pt, 0.0)], 'paint', mul(col_a, 1.15), None, (0, 0.3, -1))
                mb.fp([(-W_pt, 0.14, 0.0), (W_pt, 0.14, 0.0), (0, 0.16, 0.06)], 'paint', mul(col_a, 0.8), None, (0, 0.5, -1))
        ellipsoid(mb, (0, sy, 0.09), (0.11, 0.11, 0.05), 'brass', C_BRASS, 10, 5)

    # Gilded quarter pilasters covering hull/transom seam + stern side sconces
    for sg in (-1, 1):
        pts = [Vector((sg * (wtrans(y) + 0.01), y, zstern(y))) for y in [YT + 0.12 + (yts - YT - 0.12) * i / 10 for i in range(11)]]
        secs = []
        for p in pts:
            secs.append([p + Vector((-0.09 * sg, 0, -0.11)), p + Vector((0.06 * sg, 0, -0.11)),
                         p + Vector((0.06 * sg, 0, 0.05)), p + Vector((0.025 * sg, 0, 0.085)),
                         p + Vector((-0.09 * sg, 0, 0.085))])
        loft(mb, secs, 'brass', C_BRASS, True, (True, True), 'flat',
             scols=[C_TAR if p.y < 0.1 else C_BRASS for p in pts])

    # Amidships boarding ladder rungs on outer hull at z = -0.50
    lad_z = STATIONS['Station_Ladder_Starboard'][0][2]
    for sg in (-1, 1):
        for y in (-0.35, -0.05, 0.25, 0.55, 0.85, 1.15, 1.42):
            x = hull_b(lad_z, y)
            cbox(mb, (sg * (x + 0.075), y, lad_z), (0.15, 0.07, 0.66), 'wood', C_CREAM if y > 0.1 else C_DARK, 0.02)
        for dz in (-0.35, 0.35):
            pts = [(sg * (hull_b(lad_z, y) + 0.03), y, lad_z + dz) for y in (-0.45, 0.0, 0.45, 0.90, 1.32)]
            tube(mb, pts, 0.036, 5, 'wood', C_DARK)

    # Rope fenders hung along the broadside
    for sg in (-1, 1):
        for z in (-5.2, -1.4, 2.2, 5.2):
            yy = 0.96; x = hull_b(z, yy) + 0.21
            with xf(mb, T(sg * x, yy, z)):
                ellipsoid(mb, (0, 0, 0), (0.15, 0.30, 0.15), 'rope', C_ROPE, 10, 7)
                for dy in (-0.11, 0.11):
                    with xf(mb, T(0, dy, 0)):
                        torus(mb, 0.145, 0.02, 10, 4, 'rope', C_ROPE_D)
            tube(mb, [(sg * x, yy + 0.28, z), (sg * (hull_b(z, 1.75) + 0.06), 1.75, z),
                      (sg * (hull_b(z, ytop(z)) + 0.03), ytop(z) + 0.08, z)], 0.017, 4, 'rope', C_ROPE)

    # Heavy catheads at the bow + outboard shroud channels (signature Brigantine detail!)
    for sg in (-1, 1):
        yc = ytop(-7.2) + 0.20
        cbox(mb, (sg * 1.52, yc, -7.2), (1.16, 0.22, 0.26), 'wood', C_DARK, 0.03)
        cbox(mb, (sg * 2.11, yc, -7.2), (0.07, 0.26, 0.30), 'brass', C_BRASS, 0.02)
        # Shroud channels (fore & main) projecting outboard to anchor deadeyes cleanly
        for zc0, zc1 in ((-3.68, -2.96), (2.22, 3.22)):
            zc = (zc0 + zc1) / 2; ych = ytop(zc) - 0.10; xch = hull_b(zc, ych) + 0.15
            cbox(mb, (sg * xch, ych, zc), (0.36, 0.10, zc1 - zc0), 'wood', C_DARK, 0.02)
            cbox(mb, (sg * (xch + 0.17), ych, zc), (0.04, 0.12, zc1 - zc0 + 0.02), 'brass', C_BRASS, 0.01)

# ---------------------------------------------------------------- DECKS & STAIRS
def deck_outline(yb, yt, z0, z1, n=48, pw=1.6, margin=0.07, inner=False):
    zs = [z0 + (z1 - z0) * (i / n) ** pw for i in range(n + 1)]
    if inner:
        right = [(max(min(inner_half(z, yt) + 0.06, hull_b(z, yb) - 0.02), 0.0), z) for z in zs]
    else:
        right = [(max(min(hull_b(z, yb), hull_b(z, yt)) - margin, 0.0), z) for z in zs]
    return poly_clean(right + [(-x, z) for x, z in reversed(right)])

def deck_planks(mb, poly, z0, z1, y1, th, pw, holes, colfn):
    rng = mb.rng
    xmax = max(x for x, _ in poly)
    nstr = int(ceil((xmax - pw / 2) / pw))
    for k in range(-nstr, nstr + 1):
        xa = k * pw - pw / 2; xb = xa + pw
        iv = [(z0, z1)]
        for (hx0, hx1, hz0, hz1) in holes:
            if xb > hx0 + 1e-4 and xa < hx1 - 1e-4:
                nv = []
                for (a, b) in iv:
                    if hz0 > a:
                        nv.append((a, min(b, hz0)))
                    if hz1 < b:
                        nv.append((max(a, hz1), b))
                iv = [(a, b) for a, b in nv if b - a > 1e-3]
        for (a, b) in iv:
            strip = clip_rect(poly, xa, xb, a, b)
            if not strip:
                continue
            zmin = min(q[1] for q in strip); zmax = max(q[1] for q in strip)
            z = zmin - rng.uniform(0, 2.5); cuts = []
            while z < zmax:
                z += rng.uniform(2.2, 4.0)
                if zmin + 0.5 < z < zmax - 0.5:
                    cuts.append(z)
            bounds = [zmin] + cuts + [zmax]
            for i in range(len(bounds) - 1):
                p = clip_rect(strip, xa, xb, bounds[i], bounds[i + 1])
                if p:
                    prism(mb, p, y1 - th, y1, 'wood', colfn(), 0.014)

def build_decks(mb):
    rng = mb.rng
    def deck_col():
        c = jit(C_DECK, rng, 0.12, 0.03)
        return mul(c, 0.80) if rng.random() < 0.12 else c

    main = deck_outline(DECK_Y - 0.1, DECK_Y, Z_BOW - 0.05, QDECK_Z + 0.10, 52, 1.7)
    deck_planks(mb, main, Z_BOW - 0.1, QDECK_Z + 0.10, DECK_Y, 0.10, 0.22, [HATCH], deck_col)

    zq1 = zstern(QDECK_Y) - 0.10
    quarter = deck_outline(QDECK_Y - 0.1, QDECK_Y, QDECK_Z - 0.06, zq1, 14, 1.0)
    qx0, qx1, qz0, qz1 = QSTAIR
    deck_planks(mb, quarter, QDECK_Z - 0.06, zq1, QDECK_Y, 0.10, 0.22,
                [(qx0, 9, QDECK_Z - 0.1, qz1), (-9, -qx0, QDECK_Z - 0.1, qz1)], deck_col)

    # Waterways hiding stepped plank ends against the bulwark
    for (yd, z0, z1, n) in ((DECK_Y, Z_BOW, QDECK_Z, 44), (QDECK_Y, qz1, zq1, 10)):
        for sg in (-1, 1):
            secs = []
            for i in range(n + 1):
                z = z0 + (z1 - z0) * (i / n) ** (1.6 if yd == DECK_Y else 1.0)
                h = max(min(hull_b(z, yd), hull_b(z, yd + 0.05)) - 0.10, 0.0)
                a = max(h - 0.28, 0.0)
                secs.append([(sg * a, yd - 0.02, z), (sg * h, yd - 0.02, z),
                             (sg * h, yd + 0.045, z), (sg * (a + 0.03 if a > 0 else 0), yd + 0.045, z)])
            loft(mb, secs, 'wood', jit(C_DARK, rng, 0.05), True, (True, True), 'len')

    # Chunky bow breasthook
    bh = deck_outline(DECK_Y, 2.5, Z_BOW - 0.15, Z_BOW + 0.90, 10, 1.0, 0.10)
    prism(mb, bh, DECK_Y, ytop(Z_BOW + 0.3) - 0.02, 'wood', C_DARK, 0.03, (1, 0, 0))

    # Quarterdeck break: teal cabin bulkhead, gilded double cabin door, twin side flights
    hb = qx0; nb = 10
    for i in range(nb):
        x0 = -hb + 2 * hb * i / nb; x1 = -hb + 2 * hb * (i + 1) / nb
        door = i in (4, 5)
        cbox(mb, ((x0 + x1) / 2, (DECK_Y + QDECK_Y - 0.1) / 2 - 0.05, QDECK_Z + 0.06),
             (x1 - x0, QDECK_Y - DECK_Y, 0.10), 'wood', jit(C_DARK if door else C_TEAL, rng, 0.07), 0.014, (0, 1, 0))
    for (cx, cy, sx, sy) in ((-0.52, DECK_Y + 0.44, 0.10, 0.86), (0.52, DECK_Y + 0.44, 0.10, 0.86),
                             (0, DECK_Y + 0.86, 1.14, 0.10)):
        cbox(mb, (cx, cy, QDECK_Z), (sx, sy, 0.075), 'brass', C_BRASS, 0.02)
    for cy in (DECK_Y + 0.24, DECK_Y + 0.66):
        cbox(mb, (0, cy, QDECK_Z), (0.94, 0.06, 0.04), 'iron', C_IRON, 0.01)
    with xf(mb, T(0.32, DECK_Y + 0.42, QDECK_Z - 0.01) @ M_Y2Z):
        torus(mb, 0.055, 0.015, 10, 5, 'brass', C_BRASS)
    cbox(mb, (0, QDECK_Y - 0.11, QDECK_Z - 0.01), (2 * hb + 0.06, 0.16, 0.22), 'wood', C_GOLD, 0.03)
    cbox(mb, (0, DECK_Y - 0.17, QDECK_Z + 0.04), (2 * hull_b(QDECK_Z, 1.0) - 0.34, 0.14, 0.16), 'wood', C_DARK, 0.02)

    nq = 6; run = (qz1 - qz0) / nq; rise = (QDECK_Y - DECK_Y) / nq
    for sg in (-1, 1):
        with xf(mb, T(sg * (qx0 + qx1) / 2, 0, 0) @ M_ZY):
            prism(mb, [(qz0 + 0.02, DECK_Y - 0.05), (QDECK_Z + 0.05, DECK_Y - 0.1),
                       (qz1, QDECK_Y - 0.42), (qz1, QDECK_Y - 0.04)],
                  -(qx1 - qx0) / 2, (qx1 - qx0) / 2, 'wood', jit(C_DARK, rng, 0.06), 0.0, (1, 0, 0))
        for i in range(nq):
            top = DECK_Y + rise * (i + 1)
            box2(mb, (sg * qx0, top - rise - 0.02, qz0 + run * i),
                 (sg * qx1, top, qz0 + run * (i + 1) + 0.03), 'wood', deck_col(), 0.02, (1, 0, 0))
        xi = sg * (qx0 - 0.035)
        with xf(mb, T(xi, 0, 0) @ M_ZY):
            prism(mb, [(qz0 - 0.12, DECK_Y), (QDECK_Z, DECK_Y), (QDECK_Z, DECK_Y + 0.55), (qz0 - 0.12, DECK_Y + 0.2)],
                  -0.035, 0.035, 'wood', C_GOLD, 0.0, (1, 0, 0.8))
            prism(mb, [(QDECK_Z, DECK_Y - 0.1), (qz1 + 0.04, DECK_Y - 0.1), (qz1 + 0.04, QDECK_Y + 0.05),
                       (QDECK_Z, QDECK_Y + 0.05)], -0.035, 0.035, 'wood', C_GOLD, 0.0, (1, 0, 0.8))

    # Hatch coaming (3 sides, open aft at hz1) and gentle hold stair descending forward
    hx0, hx1, hz0, hz1 = HATCH
    for sg in (-1, 1):
        cbox(mb, (sg * (hx1 + 0.06), DECK_Y + 0.04, (hz0 + hz1) / 2 - 0.04),
             (0.16, 0.34, hz1 - hz0 + 0.16), 'wood', C_TEAL, 0.025)
    cbox(mb, (0, DECK_Y + 0.04, hz0 - 0.05), (hx1 - hx0 + 0.22, 0.34, 0.16), 'wood', C_TEAL, 0.025)
    cbox(mb, (0, DECK_Y - 0.06, hz1 + 0.05), (hx1 - hx0 + 0.26, 0.12, 0.10), 'wood', C_DARK, 0.015)

    zt, zb = HOLD_STAIR; nst = 11; H = DECK_Y - HOLD_Y
    for sg in (-1, 1):
        x = sg * (hx1 - 0.07)
        d = Vector((0, -H, zb - zt)); nrm = Vector((0, d.z, H)).normalized() * 0.135
        a = Vector((x, DECK_Y, zt + 0.02)); b = Vector((x, HOLD_Y, zb + 0.02))
        hexa(mb, [a - nrm + Vector((-0.035, 0, 0)), a - nrm + Vector((0.035, 0, 0)),
                  b - nrm + Vector((0.035, 0, 0)), b - nrm + Vector((-0.035, 0, 0)),
                  a + nrm + Vector((-0.035, 0, 0)), a + nrm + Vector((0.035, 0, 0)),
                  b + nrm + Vector((0.035, 0, 0)), b + nrm + Vector((-0.035, 0, 0))],
             'wood', jit(C_DARK, rng, 0.05), d)
    for i in range(1, nst):
        y = DECK_Y - H * i / nst; z = zt + (zb - zt) * i / nst
        cbox(mb, (0, y - 0.03, z + 0.02), (hx1 - hx0 - 0.20, 0.06, 0.30), 'wood', deck_col(), 0.015, (1, 0, 0))

    # Grand Helm pedestal & brass binnacle
    hz = STATIONS['Station_Helm'][0][2]
    cbox(mb, (0, QDECK_Y + 0.05, hz - 0.32), (0.62, 0.10, 0.54), 'wood', C_DARK, 0.025)
    hexa(mb, [(-0.22, QDECK_Y + 0.1, hz - 0.50), (0.22, QDECK_Y + 0.1, hz - 0.50),
              (0.22, QDECK_Y + 0.1, hz - 0.14), (-0.22, QDECK_Y + 0.1, hz - 0.14),
              (-0.15, QDECK_Y + 1.14, hz - 0.44), (0.15, QDECK_Y + 1.14, hz - 0.44),
              (0.15, QDECK_Y + 1.14, hz - 0.16), (-0.15, QDECK_Y + 1.14, hz - 0.16)],
         'wood', C_TEAL, (0, 1, 0))
    cbox(mb, (0, QDECK_Y + 1.17, hz - 0.30), (0.40, 0.075, 0.40), 'wood', C_DARK, 0.02)
    with xf(mb, T(0, QDECK_Y + 1.20, hz - 0.30)):
        lathe(mb, [(0, 0), (0.14, 0), (0.14, 0.045), (0.12, 0.10), (0.065, 0.145), (0, 0.155)], 12, 'brass', C_BRASS)
    with xf(mb, T(0, QDECK_Y + 0.95, hz - 0.15) @ M_Y2Z):
        cyl(mb, 0.048, 0, 0.14, 8, 'brass', C_BRASS)

# ---------------------------------------------------------------- RAILS & BALUSTRADES
def rail_frame(s):
    u = umap(s); p = hull_pt(u, 1.0); n = hull_n(u, 1.0); nh = Vector((n.x, 0, n.z))
    if nh.length < 1e-6:
        nh = Vector((1, 0, 0))
    return p, nh.normalized()

def baluster(mb, base, h, col, mat='wood'):
    with xf(mb, T(base)):
        lathe(mb, [(0.055, 0), (0.055, 0.05), (0.034, 0.08), (0.062, h * 0.34),
                   (0.030, h * 0.64), (0.046, h - 0.07), (0.052, h)], 8, mat, col, True)

def build_rails(mb):
    rng = mb.rng
    sq = s_of_z(QDECK_Z)
    for sg in (-1, 1):
        with xf(mb, S(sg, 1, 1)):
            # Main cap rail on bulwark, broken cleanly at the 4 gunports and 2 ladders
            for (a, b) in top_intervals(NS - 1.3):
                ss = [a] + [float(s) for s in range(int(ceil(a + 0.2)), int(floor(b - 0.2)) + 1)] + [b]
                secs = []
                for s in ss:
                    p, nh = rail_frame(s); c = p - nh * (TH / 2 - 0.01); up = Vector((0, 1, 0)); w = 0.165
                    secs.append([c - nh * w - up * 0.01, c + nh * w - up * 0.01, c + nh * w + up * 0.065,
                                 c + nh * (w - 0.035) + up * 0.105, c - nh * (w - 0.035) + up * 0.105,
                                 c - nh * w + up * 0.065])
                loft(mb, secs, 'wood', jit(C_DARK, rng, 0.05), True, (True, True), 'len')

            # Bold brass-capped stanchions flanking each gunport & ladder gap
            for (g0, g1) in gap_ranges():
                for s, dz in ((g0, 0.10), (g1, -0.10)):
                    p, nh = rail_frame(s); sill = hull_pt(umap(s), VS[J_SILL]).y
                    c = p - nh * (TH / 2)
                    box2(mb, (c.x - 0.145, sill - 0.02, c.z + dz - 0.105),
                         (c.x + 0.145, p.y + 0.18, c.z + dz + 0.105), 'wood', C_CREAM, 0.03, (0, 1, 0))
                    cbox(mb, (c.x, p.y + 0.21, c.z + dz), (0.35, 0.075, 0.27), 'brass', C_BRASS, 0.02)

            # Timberheads along main-deck bulwark
            for s in range(int(sq) + 3, NS - 3, 4):
                z = hull_pt(umap(s), 1.0).z
                if any(z0 - 0.40 < z < z1 + 0.40 for z0, z1 in GAPS):
                    continue
                p, nh = rail_frame(s); c = p - nh * (TH / 2)
                cbox(mb, (c.x, p.y + 0.19, c.z), (0.17, 0.20, 0.17), 'wood', C_CREAM, 0.035, (0, 1, 0))
                cbox(mb, (c.x, p.y + 0.30, c.z), (0.19, 0.04, 0.19), 'brass', C_BRASS, 0.01)

            # Quarterdeck open gilded-brass & cream balustrade
            n = 11; secs = []
            for i in range(n + 1):
                s = sq - sq * i / n
                p, nh = rail_frame(s); c = p - nh * (TH / 2 - 0.01); base = Vector((c.x, p.y + 0.105, c.z))
                hgt = 0.48
                if i in (0, n // 2, n):
                    cbox(mb, (base.x, base.y + (hgt + 0.16) / 2, base.z), (0.18, hgt + 0.16, 0.18), 'wood', C_CREAM, 0.03, (0, 1, 0))
                    with xf(mb, T(base.x, base.y + hgt + 0.16, base.z)):
                        lathe(mb, [(0, 0), (0.075, 0.02), (0.095, 0.095), (0.06, 0.17), (0, 0.19)], 8, 'brass', C_BRASS, True, True)
                else:
                    baluster(mb, base, hgt, C_BRASS, 'brass')
                    q0, n0 = rail_frame(s + sq / n / 2); c0 = q0 - n0 * (TH / 2 - 0.01)
                    baluster(mb, (c0.x, q0.y + 0.105, c0.z), hgt, C_CREAM, 'wood')
                top = base + Vector((0, hgt, 0)); w = 0.105
                secs.append([top - nh * w, top + nh * w, top + nh * w + Vector((0, 0.05, 0)),
                             top + nh * (w - 0.03) + Vector((0, 0.085, 0)), top - nh * (w - 0.03) + Vector((0, 0.085, 0)),
                             top - nh * w + Vector((0, 0.05, 0))])
            loft(mb, secs, 'brass', C_BRASS, True, (True, True), 'len')

    # Pin rails inside bulwark by both foremast and mainmast shrouds
    for z_pin in (-3.45, 2.95):
        for sg in (-1, 1):
            x = sg * (hull_b(z_pin, 1.95) - TH - 0.08); yy = DECK_Y + 0.78
            cbox(mb, (x, yy, z_pin), (0.14, 0.06, 0.62), 'wood', C_DARK, 0.015)
            for zz in (z_pin - 0.24, z_pin + 0.24):
                cbox(mb, (x + sg * 0.03, yy - 0.09, zz), (0.10, 0.14, 0.05), 'wood', C_DARK, 0.012)
            for i in range(4):
                with xf(mb, T(x, yy, z_pin - 0.21 + 0.14 * i)):
                    lathe(mb, [(0.012, -0.14), (0.016, -0.03), (0.016, 0.03), (0.028, 0.05),
                               (0.03, 0.13), (0.02, 0.16), (0, 0.165)], 6, 'brass', C_BRASS)
            with xf(mb, T(x - sg * 0.05, yy - 0.25, z_pin - 0.06) @ M_Y2X):
                torus(mb, 0.13, 0.025, 10, 4, 'rope', C_ROPE)

    # Quarterdeck front gilded balustrade & stairwell guards
    qx0, qx1, qz0, qz1 = QSTAIR
    xs = [-qx0 + 0.04 + (2 * qx0 - 0.08) * i / 8 for i in range(9)]
    for i, x in enumerate(xs):
        if i in (0, 8):
            cbox(mb, (x, QDECK_Y + 0.46, QDECK_Z + 0.02), (0.18, 0.92, 0.18), 'wood', C_CREAM, 0.03, (0, 1, 0))
            with xf(mb, T(x, QDECK_Y + 0.92, QDECK_Z + 0.02)):
                lathe(mb, [(0, 0), (0.075, 0.02), (0.095, 0.095), (0.06, 0.17), (0, 0.19)], 8, 'brass', C_BRASS, True, True)
        else:
            baluster(mb, (x, QDECK_Y, QDECK_Z + 0.02), 0.78, C_BRASS if i % 2 == 0 else C_CREAM, 'brass' if i % 2 == 0 else 'wood')
    cbox(mb, (0, QDECK_Y + 0.83, QDECK_Z + 0.02), (2 * qx0 - 0.20, 0.095, 0.21), 'brass', C_BRASS, 0.03)
    for sg in (-1, 1):
        x = sg * (qx0 - 0.04)
        for i in range(1, 6):
            z = QDECK_Z + 0.02 + (qz1 - QDECK_Z) * i / 5
            if i == 5:
                cbox(mb, (x, QDECK_Y + 0.44, z), (0.16, 0.88, 0.16), 'wood', C_CREAM, 0.03, (0, 1, 0))
                with xf(mb, T(x, QDECK_Y + 0.88, z)):
                    lathe(mb, [(0, 0), (0.065, 0.02), (0.08, 0.08), (0, 0.15)], 8, 'brass', C_BRASS, True, True)
            else:
                baluster(mb, (x, QDECK_Y + 0.05, z), 0.74, C_BRASS if i % 2 else C_CREAM, 'brass' if i % 2 else 'wood')
        cbox(mb, (x, QDECK_Y + 0.83, (QDECK_Z + qz1) / 2 + 0.05), (0.16, 0.095, qz1 - QDECK_Z + 0.10), 'brass', C_BRASS, 0.03)

    # Stern taffrail + twin decorative side stern lanterns
    yt = ytop(Z_STERN); zt = zstern(yt) - 0.07; wt = wtrans(yt) - 0.02
    cbox(mb, (0, yt + 0.05, zt), (2 * wt + 0.34, 0.105, 0.32), 'wood', C_DARK, 0.03)
    nb = 11
    for i in range(1, nb):
        x = -wt + 2 * wt * i / nb
        if abs(x) < 0.01:
            continue
        baluster(mb, (x, yt + 0.105, zt + 0.03), 0.48, C_BRASS if i % 2 else C_CREAM, 'brass' if i % 2 else 'wood')
    yr = yt + 0.58
    cbox(mb, (0, yr + 0.045, zt + 0.05), (2 * wt + 0.24, 0.09, 0.22), 'brass', C_BRASS, 0.03)
    for sg in (-1, 1):
        lx = sg * (wt - 0.12); ly = yt + 1.15; lz = zt + 0.06
        tube(mb, [(lx, yr + 0.06, zt + 0.05), (lx, ly - 0.20, lz)], 0.032, 6, 'iron', C_IRON)
        build_lantern(mb, (lx, ly, lz), 0.95, False)

# ---------------------------------------------------------------- INTERIOR HOLD & CAPTAIN'S CABIN
def build_interior(mb):
    rng = mb.rng
    zf0, zf1 = -5.65, 7.30
    def dcol(): return jit(mul(C_INNER, 0.90), rng, 0.12)
    floor_poly = deck_outline(HOLD_Y - 0.06, HOLD_Y, zf0, zf1, 36, 1.0, inner=True)
    deck_planks(mb, floor_poly, zf0, zf1, HOLD_Y, 0.06, 0.30, [], dcol)

    # Curved internal structural ribs along the hold planking
    s = s_of_z(7.1, 0.5)
    send = s_of_z(-5.4, 0.5)
    while s < send:
        u = umap(s); z = hull_pt(u, 0.5).z
        ytopr = (QDECK_Y - 0.10) if z > QDECK_Z + 0.10 else (DECK_Y - 0.10)
        ys = [HOLD_Y - 0.08 + (ytopr - HOLD_Y + 0.08) * i / 7 for i in range(8)]
        tu = (hull_pt(min(u + 0.01, 1), 0.5) - hull_pt(max(u - 0.01, 0), 0.5)).normalized() * 0.08
        for sg in (-1, 1):
            secs = []
            for y in ys:
                v = v_of_y(u, y); n = hull_n(u, v)
                p = hull_pt(u, v) - n * (hull_th(y) - 0.01); q = p - n * 0.13
                secs.append([p - tu, p + tu, q + tu, q - tu])
            with xf(mb, S(sg, 1, 1)):
                loft(mb, secs, 'wood', jit(C_DARK, rng, 0.10), True, (True, True), 'flat')
        s += 2.6 if z > -1.5 else 3.6

    # Forward bulkhead closing off the forepeak
    z = zf0; nb = 10
    hbk = hull_b(z, DECK_Y - 0.1) - 0.1
    def ysec(x):
        lo, hi = -1.10, 1.0
        for _ in range(30):
            m = (lo + hi) / 2
            if hull_b(z, m) - 0.1 < abs(x):
                lo = m
            else:
                hi = m
        return max(hi, HOLD_Y - 0.05)
    for i in range(nb):
        x0 = -hbk + 2 * hbk * i / nb; x1 = -hbk + 2 * hbk * (i + 1) / nb
        y0a, y0b = ysec(x0), ysec(x1); yt = DECK_Y - 0.1
        hexa(mb, [(x0, y0a, z - 0.05), (x1, y0b, z - 0.05), (x1, y0b, z + 0.05), (x0, y0a, z + 0.05),
                  (x0, yt, z - 0.05), (x1, yt, z - 0.05), (x1, yt, z + 0.05), (x0, yt, z + 0.05)],
             'wood', dcol(), (0, 1, 0))

    # Overhead beams under the lofty quarterdeck cabin
    for zb in (4.8, 5.9, 7.0):
        hbm = hull_b(zb, QDECK_Y - 0.2) - 0.14
        cbox(mb, (0, QDECK_Y - 0.17, zb), (2 * hbm, 0.15, 0.17), 'wood', jit(C_DARK, rng, 0.08), 0.02)

    # Bilge grate + both mast steps
    build_bilge(mb, STATIONS['Station_Bilge'][0])
    cbox(mb, (0, HOLD_Y + 0.07, MAST_Z), (0.84, 0.14, 0.84), 'wood', C_DARK, 0.04)
    cbox(mb, (0, HOLD_Y + 0.07, MAST_FORE_Z), (0.74, 0.14, 0.74), 'wood', C_DARK, 0.04)

# ---------------------------------------------------------------- PROPS & FURNISHINGS
def barrel(mb, pos, r=0.3, h=0.85, M=None, band=C_IRON, tone=C_HULL):
    rng = mb.rng
    cols = [jit(tone, rng, 0.14) for _ in range(12)]
    X = T(pos) @ (M if M is not None else Matrix.Identity(4))
    with xf(mb, X):
        prof = [(0, 0.035), (0.8 * r, 0.035), (0.8 * r, 0), (0.86 * r, 0), (0.96 * r, 0.2 * h), (r, 0.5 * h),
                (0.96 * r, 0.8 * h), (0.86 * r, h), (0.8 * r, h), (0.8 * r, h - 0.035), (0, h - 0.035)]
        lathe(mb, prof, 12, 'wood', C_HULL, False, False, lambda i, k: mul(cols[k], 0.8 if i in (0, 9) else 1.0))
        for f, rr in ((0.07, 0.885), (0.27, 0.975), (0.73, 0.975), (0.93, 0.885)):
            y = f * h; r0 = rr * r + 0.012
            lathe(mb, [(r0 - 0.02, y - 0.03), (r0, y - 0.03), (r0, y + 0.03), (r0 - 0.02, y + 0.03)],
                  12, 'brass' if band == C_BRASS else 'iron', band, False)

def crate(mb, c, size, M=None, tone=C_DECK):
    rng = mb.rng; sx, sy, sz = size
    X = T(c) @ (M if M is not None else Matrix.Identity(4))
    with xf(mb, X):
        cbox(mb, (0, sy / 2, 0), (sx - 0.05, sy - 0.05, sz - 0.05), 'wood', jit(tone, rng, 0.1), 0.01, (1, 0, 0))
        b = 0.075; dk = jit(mul(tone, 0.62), rng, 0.08)
        for ax in (-1, 1):
            for az in (-1, 1):
                cbox(mb, (ax * (sx - b) / 2, sy / 2, az * (sz - b) / 2), (b, sy, b), 'wood', dk, 0.012)
            for ay in (0, 1):
                cbox(mb, (ax * (sx - b) / 2, b / 2 + ay * (sy - b), 0), (b, b, sz - b), 'wood', dk, 0.012)
        for az in (-1, 1):
            for ay in (0, 1):
                cbox(mb, (0, b / 2 + ay * (sy - b), az * (sz - b) / 2), (sx - b, b, b), 'wood', dk, 0.012)

def rope_coil(mb, c, r=0.22, turns=4, col=C_ROPE):
    with xf(mb, T(c)):
        for i in range(turns):
            with xf(mb, T(0, 0.035 + i * 0.055, 0)):
                torus(mb, r - (i % 2) * 0.02, 0.034, 10, 5, 'rope', mul(col, 0.9 + 0.1 * (i % 2)))

def build_props_deck(mb):
    # Forward deck supplies tucked cleanly near bow bulwarks
    barrel(mb, (-1.25, DECK_Y, -5.6), 0.30, 0.85)
    barrel(mb, (-0.70, DECK_Y, -6.0), 0.27, 0.78, tone=C_DARK, band=C_BRASS)
    crate(mb, (1.20, DECK_Y, -5.65), (0.72, 0.56, 0.62), R('Y', 16))
    crate(mb, (1.15, DECK_Y + 0.56, -5.68), (0.46, 0.36, 0.44), R('Y', -14), C_HULL)
    rope_coil(mb, (1.65, DECK_Y, -4.45), 0.26, 3)
    rope_coil(mb, (-1.55, QDECK_Y, 5.4), 0.25, 3)
    barrel(mb, (1.42, QDECK_Y, 7.65), 0.26, 0.75, tone=C_DARK, band=C_BRASS)
    barrel(mb, (-1.42, QDECK_Y, 7.65), 0.25, 0.72, tone=C_HULL)
    # Cannonball racks beside all four deck cannons
    for zc in (-1.55, 0.55):
        for sg in (-1, 1):
            cbox(mb, (sg * 1.98, DECK_Y + 0.05, zc), (0.52, 0.10, 0.22), 'wood', C_DARK, 0.02)
            for i in range(3):
                ellipsoid(mb, (sg * (1.82 + 0.16 * i), DECK_Y + 0.165, zc), (0.078, 0.078, 0.078), 'iron', C_IRON, 8, 5)
    # Aft powder kegs tucked beside the aft cannons
    for sg in (-1, 1):
        build_powder_keg(mb, (sg * 1.95, DECK_Y, 2.25))

def build_props_hold(mb):
    y = HOLD_Y
    # Fore hold cargo around foremast
    barrel(mb, (-0.82, y, -5.05), 0.32, 0.90)
    barrel(mb, (0.78, y, -5.05), 0.32, 0.88, tone=C_DARK, band=C_BRASS)
    barrel(mb, (1.10, y + 0.31, -3.90), 0.30, 0.85, R('Y', 22) @ R('X', 90))
    crate(mb, (-1.15, y, -3.95), (0.72, 0.62, 0.72), R('Y', 8))
    crate(mb, (-1.12, y + 0.62, -3.97), (0.48, 0.40, 0.48), R('Y', -15), C_HULL)
    barrel(mb, (1.25, y, -0.30), 0.30, 0.84, tone=C_HULL)
    barrel(mb, (-1.28, y, -0.35), 0.29, 0.82, tone=C_DARK, band=C_BRASS)
    rope_coil(mb, (0.95, y, 1.05), 0.26, 3)

    # Crew hammocks slung fore and aft in midship berthing (clear of shot=cabin), anchored to hull ribs with hemp clew ropes
    for sg in (-1, 1):
        pts = [(sg * 1.82, 0.84, 2.35), (sg * 1.78, 0.56, 2.85), (sg * 1.76, 0.45, 3.35),
               (sg * 1.74, 0.56, 3.85), (sg * 1.66, 0.84, 4.30)]
        secs = [[Vector(q) + Vector((-0.24 if i not in (0, 4) else -0.02, 0.0 if i in (0, 4) else 0.10, 0)),
                 Vector(q),
                 Vector(q) + Vector((0.24 if i not in (0, 4) else 0.02, 0.0 if i in (0, 4) else 0.10, 0))]
                for i, q in enumerate(pts)]
        loft(mb, secs, 'cloth', srgb('#e9dcb8'), False, (False, False), 'smooth', flip=False)
        tube(mb, [pts[0], (sg * 2.15, 1.06, 1.98)], 0.017, 6, 'rope', C_ROPE)
        tube(mb, [pts[-1], (sg * 2.02, 1.06, 4.65)], 0.017, 6, 'rope', C_ROPE)
    build_cabin(mb)

def build_cabin(mb):
    """Grand Brigantine stern cabin under the quarterdeck."""
    rng = mb.rng; y = HOLD_Y; seat = y + 0.52
    poly = deck_outline(y + 0.2, seat, 6.75, 7.65, 8, 1.0, inner=True)
    prism(mb, poly, y - 0.02, seat, 'wood', jit(C_HULL, rng, 0.06), 0.02, (1, 0, 0))
    cush = [(x * 0.88, 6.82 + (z - 6.75) * 0.82) for x, z in poly]
    prism(mb, cush, seat, seat + 0.10, 'cloth', C_INDIGO, 0.03, (1, 0, 0))
    for sx in (-0.42, 0.0, 0.42):
        col = C_GOLD if sx == 0.0 else (C_TEAL if sx < 0 else C_RED)
        ellipsoid(mb, (sx, seat + 0.21, 7.25), (0.21, 0.13, 0.17), 'cloth', col, 8, 5, R('Y', sx * 45))
    # Layered nautical rug
    cbox(mb, (0, y + 0.004, 5.75), (1.65, 0.008, 1.40), 'cloth', C_CREAM, 0.0)
    cbox(mb, (0, y + 0.010, 5.75), (1.42, 0.008, 1.18), 'cloth', C_INDIGO, 0.0)
    cbox(mb, (0, y + 0.016, 5.75), (0.62, 0.008, 0.56), 'cloth', C_GOLD, 0.0, None, R('Y', 45))
    # Captain's brass-bound sea chest
    with xf(mb, T(0.68, y, 6.20) @ R('Y', -14)):
        cbox(mb, (0, 0.18, 0), (0.68, 0.36, 0.42), 'wood', C_DARK, 0.02, (1, 0, 0))
        with xf(mb, T(0, 0.36, 0) @ M_Y2X):
            lathe(mb, [(0, -0.34), (0.21, -0.34), (0.21, 0.34), (0, 0.34)], 12, 'wood', C_HULL, True)
        for sx in (-0.22, 0.22):
            cbox(mb, (sx, 0.20, 0), (0.055, 0.42, 0.44), 'brass', C_BRASS, 0.008)
        cbox(mb, (0, 0.31, -0.22), (0.09, 0.10, 0.03), 'brass', C_BRASS, 0.008)
    # Navigator's stool
    with xf(mb, T(-0.62, y, 6.15)):
        lathe(mb, [(0, 0.42), (0.18, 0.42), (0.18, 0.47), (0, 0.47)], 10, 'wood', C_HULL)
        for k in range(3):
            a = 2 * pi * k / 3
            tube(mb, [(0.085 * cos(a), 0.42, 0.085 * sin(a)), (0.17 * cos(a), 0, 0.17 * sin(a))], 0.025, 5, 'wood', C_DARK)
    # Velvet curtains flanking the 3 tall stern windows
    ang = math.degrees(math.atan(0.22))
    with xf(mb, T(0, DECK_Y, Z_STERN) @ R('X', ang)):
        yy = lambda v: (v - DECK_Y) / cos(radians(ang))
        tube(mb, [(-1.55, yy(1.66), -0.24), (1.55, yy(1.66), -0.24)], 0.02, 5, 'brass', C_BRASS)
        for cx in (-1.50, -0.54, 0.54, 1.50):
            for i in range(3):
                cbox(mb, (cx + (i - 1) * 0.06, yy(1.16), -0.235 - 0.012 * (i % 2)),
                     (0.065, yy(1.66) - yy(0.68), 0.022), 'cloth', jit(C_INDIGO, rng, 0.08), 0.008)

def build_map_table(mb):
    o = Vector(STATIONS['Station_MapTable'][0]); rng = mb.rng
    with xf(mb, T(o)):
        cbox(mb, (0, 0.82, 0), (1.48, 0.095, 0.96), 'wood', C_HULL, 0.025, (1, 0, 0))
        for sx in (-1, 1):
            for sz in (-1, 1):
                cbox(mb, (sx * 0.60, 0.39, sz * 0.36), (0.125, 0.78, 0.125), 'wood', C_DARK, 0.025)
            cbox(mb, (sx * 0.60, 0.20, 0), (0.08, 0.08, 0.66), 'wood', C_DARK, 0.015)
        cbox(mb, (0, 0.20, 0), (1.16, 0.075, 0.085), 'wood', C_DARK, 0.015)
        with xf(mb, T(0.04, 0.868, 0) @ R('Y', 5)):
            cbox(mb, (0, 0.008, 0), (1.04, 0.016, 0.68), 'paint', C_CREAM, 0.0)
            cbox(mb, (0, 0.005, 0), (1.08, 0.008, 0.72), 'paint', mul(C_CREAM, 0.72), 0.0)
            for (ix, iz, r, c) in ((-0.26, 0.09, 0.12, srgb('#5d944c')), (0.22, -0.14, 0.09, srgb('#5d944c')),
                                   (0.11, 0.19, 0.055, srgb('#c8a75e')), (-0.34, -0.19, 0.05, srgb('#c8a75e'))):
                poly = [(ix + r * (0.7 + 0.5 * rng.random()) * cos(a * pi / 4),
                         iz + r * (0.7 + 0.5 * rng.random()) * sin(a * pi / 4)) for a in range(8)]
                mb.newoff(); mb.fp([(x, 0.02, z) for x, z in poly], 'paint', c, None, (ix, -1, iz))
            for a in (45, -45):
                cbox(mb, (0.25, 0.021, -0.11), (0.10, 0.004, 0.022), 'paint', C_RED, 0.0, None, R('Y', a))
            for i in range(6):
                cbox(mb, (-0.20 + i * 0.07, 0.02, 0.02 - i * 0.02), (0.032, 0.003, 0.013), 'paint', C_BLACK, 0.0, None, R('Y', 18))
        with xf(mb, T(-0.50, 0.868, -0.28)):
            lathe(mb, [(0, 0), (0.09, 0), (0.09, 0.032), (0.068, 0.044), (0, 0.044)], 10, 'brass', C_BRASS)
        with xf(mb, T(0.58, 0.868, 0.30)):
            lathe(mb, [(0, 0), (0.075, 0), (0.075, 0.016), (0.032, 0.022), (0.032, 0.13), (0, 0.13)], 8, 'paint', C_CREAM)
            lathe(mb, [(0, 0.13), (0.016, 0.155), (0, 0.21)], 5, 'glass', C_GLASS)

# ---------------------------------------------------------------- TWO MASTS, BOWSPRIT & FIGUREHEAD
def build_mainmast(mb):
    """Tall mainmast at z = +0.5 rising to y = 17.5 with big stave crow's nest & brass truck."""
    D = DECK_Y
    lathe(mb, [(0, HOLD_Y), (0.34, HOLD_Y), (0.34, D + 0.02), (0.32, D + 3.5), (0.29, D + 7.5),
               (0.26, 12.0), (0.22, 13.55), (0.18, 13.60), (0, 13.60)], 16, 'wood', mul(C_DECK, 0.92), True, True)
    lathe(mb, [(0.34, D), (0.43, D), (0.43, D + 0.11), (0.38, D + 0.24), (0.34, D + 0.24)], 16, 'wood', C_TEAL)
    for y in (3.2, 5.8, 8.4, 10.6):
        r = 0.34 - (y - D) * 0.007
        lathe(mb, [(r - 0.01, y - 0.075), (r + 0.022, y - 0.075), (r + 0.022, y + 0.075), (r - 0.01, y + 0.075)], 16, 'brass', C_BRASS)
    # Doubled topmast to y = 17.5 + brass truck
    lathe(mb, [(0, 11.8), (0.17, 11.8), (0.155, 14.4), (0.095, MAST_TOP - 0.05), (0, MAST_TOP - 0.05)], 10, 'wood', mul(C_DECK, 0.88), True, True)
    lathe(mb, [(0.21, 13.48), (0.32, 13.48), (0.32, 13.68), (0.21, 13.68)], 12, 'wood', C_GOLD)
    with xf(mb, T(0, MAST_TOP - 0.05, 0)):
        lathe(mb, [(0, 0), (0.11, 0.025), (0.155, 0.11), (0.105, 0.21), (0, 0.24)], 10, 'brass', C_BRASS, True, True)
    # Big stave crow's nest at y = 12.1..13.15
    rng = mb.rng; cols = [jit(C_HULL, rng, 0.14) for _ in range(14)]
    y0 = 12.1
    prof = [(0.26, y0), (0.86, y0), (0.98, y0 + 0.48), (1.02, y0 + 0.96), (1.02, y0 + 1.04),
            (0.92, y0 + 1.04), (0.92, y0 + 0.96), (0.88, y0 + 0.48), (0.80, y0 + 0.10), (0.26, y0 + 0.10)]
    lathe(mb, prof, 14, 'wood', C_HULL, False, False, lambda i, k: mul(cols[k], 0.75 if i >= 5 else 1.0))
    for (yy, rr) in ((y0 + 0.16, 0.915), (y0 + 0.78, 1.025)):
        lathe(mb, [(rr - 0.02, yy - 0.04), (rr, yy - 0.04), (rr, yy + 0.04), (rr - 0.02, yy + 0.04)], 14, 'brass', C_BRASS, False)
    lathe(mb, [(0.93, y0 + 0.96), (1.06, y0 + 0.96), (1.06, y0 + 1.08), (0.93, y0 + 1.08)], 14, 'wood', C_TEAL, False)
    for k in range(4):
        with xf(mb, R('Y', 45 + k * 90) @ M_ZY):
            prism(mb, [(0.24, y0 - 0.80), (0.37, y0 - 0.80), (0.80, y0), (0.24, y0)], -0.055, 0.055, 'wood', C_DARK, 0.0, (1, 0, 1))

def build_foremast(mb):
    """Foremast at z = -4.6 rising to y = 15.0 with crosstrees fighting top & brass truck."""
    D = DECK_Y
    lathe(mb, [(0, HOLD_Y), (0.28, HOLD_Y), (0.28, D + 0.02), (0.265, D + 3.0), (0.24, D + 6.5),
               (0.21, 10.6), (0.18, 11.75), (0.145, 11.80), (0, 11.80)], 14, 'wood', mul(C_DECK, 0.92), True, True)
    lathe(mb, [(0.28, D), (0.36, D), (0.36, D + 0.10), (0.31, D + 0.22), (0.28, D + 0.22)], 14, 'wood', C_TEAL)
    for y in (3.0, 5.4, 7.8):
        r = 0.28 - (y - D) * 0.007
        lathe(mb, [(r - 0.01, y - 0.065), (r + 0.02, y - 0.065), (r + 0.02, y + 0.065), (r - 0.01, y + 0.065)], 14, 'brass', C_BRASS)
    # Fore topmast to y = 15.0 + brass truck
    lathe(mb, [(0, 10.4), (0.145, 10.4), (0.13, 12.6), (0.08, MAST_FORE_TOP - 0.05), (0, MAST_FORE_TOP - 0.05)], 10, 'wood', mul(C_DECK, 0.88), True, True)
    lathe(mb, [(0.17, 11.68), (0.27, 11.68), (0.27, 11.86), (0.17, 11.86)], 12, 'wood', C_GOLD)
    with xf(mb, T(0, MAST_FORE_TOP - 0.05, 0)):
        lathe(mb, [(0, 0), (0.095, 0.02), (0.13, 0.095), (0.09, 0.18), (0, 0.21)], 10, 'brass', C_BRASS, True, True)
    # Foremast fighting platform / crosstrees at y = 10.95 (compact rimmed top distinct from main crow's nest)
    y0 = 10.95
    lathe(mb, [(0.21, y0), (0.72, y0), (0.76, y0 + 0.10), (0.76, y0 + 0.24), (0.68, y0 + 0.24), (0.68, y0 + 0.10), (0.21, y0 + 0.10)],
          12, 'wood', C_DARK, False)
    lathe(mb, [(0.72, y0 + 0.16), (0.79, y0 + 0.16), (0.79, y0 + 0.26), (0.72, y0 + 0.26)], 12, 'brass', C_BRASS, False)
    for k in range(4):
        with xf(mb, R('Y', 45 + k * 90) @ M_ZY):
            prism(mb, [(0.19, y0 - 0.58), (0.30, y0 - 0.58), (0.66, y0), (0.19, y0)], -0.045, 0.045, 'wood', C_DARK, 0.0, (1, 0, 1))

def build_bowsprit(mb):
    heel = Vector(BS_HEEL); tip = Vector(BS_TIP)
    n = 8; path = [heel.lerp(tip, i / n) for i in range(n + 1)]
    tube(mb, path, [0.21 - 0.09 * i / n for i in range(n + 1)], 12, 'wood', mul(C_DECK, 0.92))
    d = (tip - heel).normalized()
    for f, mat, col in ((0.28, 'iron', C_IRON), (0.62, 'brass', C_BRASS), (0.96, 'brass', C_BRASS)):
        p = heel.lerp(tip, f); r = 0.21 - 0.09 * f + 0.018
        tube(mb, [p - d * 0.075, p + d * 0.075], r, 12, mat, col, mode='len')
    # Ornate gilded finial cap at the bowsprit tip
    with xf(mb, T(tip)):
        ellipsoid(mb, (0, 0, 0), (0.14, 0.14, 0.18), 'brass', C_BRASS, 10, 6)
    # Dolphin striker (martingale boom) & bobstay under the bowsprit for authentic Brigantine profile
    p_mid = heel.lerp(tip, 0.58)
    p_drop = p_mid + Vector((0, -1.05, 0.15))
    tube(mb, [p_mid, p_drop], [0.065, 0.038], 8, 'wood', C_DARK)
    tube(mb, [Vector((0, 0.72, zstem(0.72) - 0.20)), p_drop, tip - Vector((0, 0.05, -0.08))], 0.028, 5, 'rope', C_ROPE_D)
    # Bitts holding the bowsprit heel on the foredeck
    for sg in (-1, 1):
        cbox(mb, (sg * 0.34, (DECK_Y + 3.20) / 2, -7.75), (0.22, 3.20 - DECK_Y, 0.22), 'wood', C_TEAL, 0.035, (0, 1, 0))
        cbox(mb, (sg * 0.34, 3.24, -7.75), (0.26, 0.08, 0.26), 'brass', C_BRASS, 0.015)
    cbox(mb, (0, 3.04, -7.75), (1.00, 0.17, 0.17), 'wood', C_DARK, 0.03)
    # Gammoning ropes lashing bowsprit to the stem head
    for i in range(5):
        p = heel.lerp(tip, 0.20 + i * 0.013)
        with xf(mb, T(p) @ R('X', 72)):
            torus(mb, 0.205, 0.032, 10, 5, 'rope', C_ROPE)

def build_figurehead(mb):
    """Original 'Gilded Crowned Sea-Griffin' figurehead carved boldly onto the prow beneath the bowsprit."""
    # Ornate brass scroll collar hugging the cutwater
    with xf(mb, T(0, 1.82, -9.56) @ R('X', 58)):
        torus(mb, 0.42, 0.095, 14, 6, 'brass', C_BRASS)
    # Broad heroic muscular chest & proud compact arched neck (no scrawny snake neck!)
    ellipsoid(mb, (0, 2.02, -9.82), (0.38, 0.56, 0.48), 'brass', C_BRASS, 12, 8, R('X', -32))
    neck = [(0, 2.18, -9.96), (0, 2.48, -10.16), (0, 2.74, -10.28)]
    tube(mb, neck, [0.34, 0.29, 0.25], 12, 'paint', C_GOLD)
    # Sculpted layered mane ruff (golden + turquoise heraldic crest plates)
    for k in range(7):
        ang = -90 + k * 30
        with xf(mb, T(0, 2.52, -10.14) @ R('Z', ang) @ T(0, 0.28, 0.04) @ R('X', -35)):
            ellipsoid(mb, (0, 0, 0), (0.11, 0.20, 0.24), 'brass' if k % 2 == 0 else 'paint',
                      C_BRASS if k % 2 == 0 else C_TEAL, 8, 5)
    # Dramatic swept-back layered wings framing the bow cheeks
    for sg in (-1, 1):
        ellipsoid(mb, (sg * 0.40, 2.22, -9.55), (0.12, 0.46, 0.72), 'paint', C_TEAL, 10, 6, R('X', -18) @ R('Y', sg * -20))
        ellipsoid(mb, (sg * 0.48, 2.08, -9.28), (0.09, 0.34, 0.54), 'brass', C_BRASS, 8, 5, R('X', -16) @ R('Y', sg * -22))
        ellipsoid(mb, (sg * 0.52, 1.92, -9.05), (0.07, 0.22, 0.36), 'paint', C_GOLD, 8, 5, R('X', -14) @ R('Y', sg * -24))
    # Fierce carved lion-griffin head: broad skull, bold brow ridge, hooked eagle-dragon beak/snout & roaring jaw
    ellipsoid(mb, (0, 2.84, -10.42), (0.28, 0.27, 0.30), 'paint', C_GOLD, 12, 7)
    # Sculpted brow & crown crest
    cbox(mb, (0, 3.04, -10.52), (0.44, 0.10, 0.24), 'brass', C_BRASS, 0.025, None, R('X', 12))
    cbox(mb, (0, 3.16, -10.36), (0.14, 0.22, 0.30), 'brass', C_BRASS, 0.025, None, R('X', -25))
    # Compact fierce hooked snout & open roaring lower jaw
    snout = [(0, 2.90, -10.60), (0, 2.86, -10.88), (0, 2.72, -11.08)]
    tube(mb, snout, [0.22, 0.16, 0.065], 10, 'brass', C_BRASS)
    jaw = [(0, 2.66, -10.58), (0, 2.52, -10.84), (0, 2.50, -10.98)]
    tube(mb, jaw, [0.16, 0.11, 0.05], 8, 'paint', mul(C_GOLD, 0.85))
    for sg in (-1, 1):
        # Swept carved royal horns
        tube(mb, [(sg * 0.18, 3.04, -10.36), (sg * 0.34, 3.24, -10.08), (sg * 0.38, 3.36, -9.76)],
             [0.075, 0.052, 0.020], 6, 'brass', C_BRASS)
        # Fierce recessed eyes beneath the brow ridge
        ellipsoid(mb, (sg * 0.22, 2.92, -10.58), (0.052, 0.055, 0.062), 'paint', C_CREAM, 8, 5)
        ellipsoid(mb, (sg * 0.25, 2.92, -10.61), (0.030, 0.036, 0.036), 'paint', C_INDIGO, 6, 4)

# ---------------------------------------------------------------- STANDING RIGGING (BOTH MASTS)
def main_shroud_pts():
    out = []
    for sg in (-1, 1):
        for k, z in enumerate((2.38, 2.72, 3.06)):
            s = s_of_z(z); p, _ = rail_frame(s)
            bot = Vector((sg * (p.x + 0.18), p.y - 0.04, z))
            top = Vector((sg * 0.13, 12.02, MAST_Z + 0.32 + 0.03 * k))
            out.append((sg, k, bot, top))
    return out

def fore_shroud_pts():
    out = []
    for sg in (-1, 1):
        for k, z in enumerate((-3.56, -3.31, -3.06)):
            s = s_of_z(z); p, _ = rail_frame(s)
            bot = Vector((sg * (p.x + 0.18), p.y - 0.04, z))
            top = Vector((sg * 0.12, 10.90, MAST_FORE_Z + 0.40 + 0.03 * k))
            out.append((sg, k, bot, top))
    return out

def standing_stays():
    """All stays & backstays as (a, b, rad) tuples in game coords."""
    tip = Vector(BS_TIP); mid = Vector(BS_HEEL).lerp(tip, 0.50)
    stays = [
        # Foremast forestay to bowsprit tip + inner forestay high enough for Yard_Fore to swing clear underneath
        (Vector((0, MAST_FORE_TOP - 0.35, MAST_FORE_Z - 0.08)), tip + Vector((0, 0.10, 0.10)), 0.032),
        (Vector((0, 12.75, MAST_FORE_Z - 0.18)), mid + Vector((0, 0.20, 0.0)), 0.030),
        # Inter-mast stays (main topmast stay + main stay to foremast head, clear above both yards!)
        (Vector((0, MAST_TOP - 0.40, MAST_Z - 0.08)), Vector((0, MAST_FORE_TOP - 0.55, MAST_FORE_Z + 0.10)), 0.030),
        (Vector((0, 13.45, MAST_Z - 0.20)), Vector((0, 11.82, MAST_FORE_Z + 0.18)), 0.032),
    ]
    # Mainmast backstays to outboard stern quarterdeck rail cleat (clear of balusters)
    p_aft, _ = rail_frame(2.2)
    for sg in (-1, 1):
        stays.append((Vector((sg * 0.10, MAST_TOP - 0.50, MAST_Z + 0.08)),
                      Vector((sg * (p_aft.x + 0.06), p_aft.y + 0.68, p_aft.z)), 0.028))
    return stays

def build_rigging(mb):
    for sh, y_rat_top in ((main_shroud_pts(), 11.5), (fore_shroud_pts(), 10.35)):
        for sg, k, bot, top in sh:
            lo = bot + (top - bot).normalized() * 0.58
            tube(mb, [lo, top], 0.032, 5, 'rope', C_ROPE_D)
            for f in (0.10, 0.44):
                c = bot + (top - bot).normalized() * f
                with xf(mb, T(c) @ M_Y2X):
                    cyl(mb, 0.09, -0.036, 0.036, 8, 'wood', C_DARK, True, 0.012)
            tube(mb, [bot + Vector((0, -0.22, 0)), lo], 0.020, 4, 'rope', C_ROPE)
        for sg in (-1, 1):
            a = [(b, t) for s, k, b, t in sh if s == sg]
            y = 2.95
            while y < y_rat_top:
                pts = [b.lerp(t, (y - b.y) / (t.y - b.y)) for (b, t) in a]
                tube(mb, pts, 0.017, 3, 'rope', C_ROPE, (False, False), 'flat')
                y += 0.50
    for a, b, rad in standing_stays():
        tube(mb, [a, b], rad, 5, 'rope', C_ROPE_D)

# ---------------------------------------------------------------- YARDS, SAILS, FURLED SAILS & FLAGS
def build_yard(mb, mast_z, yard_y, yard_fwd, half_w):
    y = yard_y; z = mast_z - yard_fwd; n = 10
    path = [(-half_w + 2 * half_w * i / n, y, z) for i in range(n + 1)]
    rad = [0.08 + 0.068 * (1 - abs(2 * i / n - 1) ** 1.5) for i in range(n + 1)]
    tube(mb, path, rad, 10, 'wood', mul(C_DECK, 0.85))
    for sg in (-1, 1):
        tube(mb, [(sg * (half_w - 0.06), y, z), (sg * (half_w + 0.06), y, z)], 0.10, 10, 'brass', C_BRASS, mode='len')
        tube(mb, [(sg * 0.55, y, z), (sg * 0.68, y, z)], 0.16, 10, 'iron', C_IRON, mode='len')
    cbox(mb, (0, y, mast_z - yard_fwd * 0.62), (0.46, 0.28, 0.28), 'wood', C_DARK, 0.03)
    with xf(mb, T(0, y, mast_z)):
        lathe(mb, [(0.28, -0.11), (0.38, -0.11), (0.38, 0.11), (0.28, 0.11)], 14, 'rope', C_ROPE)
    for i in range(15):
        x = -(half_w - 0.25) + 2 * (half_w - 0.25) * i / 14
        if abs(x) < 0.72:
            continue
        r = 0.08 + 0.068 * (1 - abs(x / half_w) ** 1.5) + 0.013
        tube(mb, [(x - 0.03, y, z), (x + 0.03, y, z)], r, 8, 'rope', C_ROPE, mode='len')

def make_sail_point_fn(mast_z, yard_y, yard_fwd, half_w, foot_y, belly_depth):
    hw_top = half_w - 0.20
    hw_grow = 0.24
    head_y = yard_y - 0.14
    def pt(xn, yn):
        hw = hw_top + hw_grow * yn
        x = xn * hw
        yfoot = foot_y + 0.45 * (1 - xn * xn)
        y = head_y + (yfoot - head_y) * yn
        belly = belly_depth * cos(xn * pi / 2) ** 0.85 * (0.10 + 0.90 * sin(pi * min(1.0, yn * 0.83)) ** 0.9)
        belly *= min(1.0, yn * 6 + 0.12)
        scallop = 0.04 * (1 - cos(xn * 6 * pi)) * min(1.0, yn * 3) * (1 if abs(xn) < 0.999 else 0)
        z = mast_z - yard_fwd - 0.02 - belly - scallop
        return Vector((x, y, z))
    return pt

def make_sail_weight_fn(yard_y, half_w, foot_y):
    """UV2 wind weights: UV2.x = 0 at yard & side bolt ropes, 1 in belly, ~0.65 along foot; UV2.y = 0..1 down sail."""
    hw_top = half_w - 0.20
    hw_grow = 0.24
    head_y = yard_y - 0.14
    def wfn(p):
        yn = 0.5; xn = 0.0
        for _ in range(4):
            xn = max(-1.0, min(1.0, p.x / (hw_top + hw_grow * yn)))
            yn = max(0.0, min(1.0, (head_y - p.y) / max(head_y - (foot_y + 0.45 * (1 - xn * xn)), 1e-4)))
        w = (1 - abs(xn) ** 4) * smooth01(yn / 0.30) * (1 - 0.35 * smooth01((yn - 0.80) / 0.20))
        return (w, yn)
    return wfn

main_sail_pt = make_sail_point_fn(MAST_Z, YARD_Y, YARD_FWD, YARD_HALF, SAIL_FOOT_Y, 1.32)
fore_sail_pt = make_sail_point_fn(MAST_FORE_Z, YARD_FORE_Y, YARD_FORE_FWD, YARD_FORE_HALF, SAIL_FORE_FOOT_Y, 1.12)
main_sail_wfn = make_sail_weight_fn(YARD_Y, YARD_HALF, SAIL_FOOT_Y)
fore_sail_wfn = make_sail_weight_fn(YARD_FORE_Y, YARD_FORE_HALF, SAIL_FORE_FOOT_Y)

def build_sail(mb, pt_fn, w_fn, nx=32, ny=20):
    mb.wfn = w_fn
    pts = [[pt_fn(-1 + 2 * i / nx, j / ny) for i in range(nx + 1)] for j in range(ny + 1)]
    front = [[mb.v(q) for q in row] for row in pts]
    back = [[mb.v(q + Vector((0, 0, 0.015))) for q in row] for row in pts]
    for j in range(ny):
        for i in range(nx):
            uvs = [(i / nx, 1 - j / ny), ((i + 1) / nx, 1 - j / ny),
                   ((i + 1) / nx, 1 - (j + 1) / ny), (i / nx, 1 - (j + 1) / ny)]
            sh = [mix(C_WHITE, (0.80, 0.78, 0.74), 0.5 * abs(-1 + 2 * ii / nx) ** 3 + 0.25 * (jj / ny) ** 2)
                  for ii, jj in ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))]
            mb.f([front[j][i], front[j][i + 1], front[j + 1][i + 1], front[j + 1][i]], 'canvas', sh, uvs, True)
            mb.f([back[j][i], back[j][i + 1], back[j + 1][i + 1], back[j + 1][i]][::-1], 'canvas_back', sh[::-1], uvs[::-1], True)
    edge = ([pt_fn(-1, j / ny) for j in range(ny + 1)] +
            [pt_fn(-1 + 2 * i / nx, 1) for i in range(1, nx + 1)] +
            [pt_fn(1, 1 - j / ny) for j in range(1, ny + 1)])
    tube(mb, [q + Vector((0, 0, 0.007)) for q in edge], 0.034, 5, 'rope', C_ROPE, (True, True), 'smooth')
    for sg in (-1, 1):
        with xf(mb, T(pt_fn(sg, 1) + Vector((sg * 0.055, -0.055, 0.0))) @ M_Y2Z):
            torus(mb, 0.065, 0.022, 8, 4, 'iron', C_IRON)

def build_sail_furled(mb, mast_z, yard_y, yard_fwd, half_w):
    n = 36; segs = 10; z0 = mast_z - yard_fwd - 0.04; hw = half_w - 0.20; ids = []
    for i in range(n + 1):
        xn = -1 + 2 * i / n; x = xn * hw
        r = 0.22 + 0.038 * sin(i * 1.7) + 0.026 * cos(i * 0.9)
        g = abs(((i + 3) % 6) - 3) / 3.0
        r *= (1 - 0.3 * g ** 3) * (1 - 0.5 * abs(xn) ** 6)
        yc = yard_y - 0.22 - r * 0.75 - 0.05 * (1 - g)
        ring = []
        for k in range(segs):
            a = 2 * pi * k / segs
            ring.append(mb.v((x, yc + r * 1.15 * cos(a) + 0.02 * sin(a * 3 + i), z0 + r * sin(a) * 0.95)))
        ids.append(ring)
    def col(k):
        sh = 0.80 + 0.2 * (0.5 + 0.5 * cos(2 * pi * k / segs))
        return (sh, sh * 0.985, sh * 0.96)
    for i in range(n):
        for k in range(segs):
            k1 = (k + 1) % segs
            uv = lambda ii, kk: (0.03 + 0.94 * ii / n, 0.845 + 0.13 * kk / segs)
            mb.f([ids[i][k], ids[i][k1], ids[i + 1][k1], ids[i + 1][k]], 'canvas',
                 [col(k), col(k + 1), col(k + 1), col(k)], [uv(i, k), uv(i, k + 1), uv(i + 1, k + 1), uv(i + 1, k)], True)
    for ring, ii in ((ids[0], 0), (ids[-1], n)):
        mb.f(ring if ii else ring[::-1], 'canvas', (0.85, 0.83, 0.8), [(0.5, 0.9)] * segs, False)
    for i in range(3, n, 6):
        x = (-1 + 2 * i / n) * hw
        pts = [(x, yard_y - 0.15 + 0.31 * cos(a * pi / 6), z0 + 0.03 + 0.22 * sin(a * pi / 6)) for a in range(13)]
        tube(mb, pts, 0.024, 4, 'rope', C_ROPE, (False, False))

def build_flag(mb, mast_z, top_y, h=1.25, L=3.6, nx=28, ny=8):
    """Long dramatic forked masthead pennant extending along local -Z with UV2 wind weights 0..1."""
    z_hoist = mast_z - 0.10
    mb.wfn = lambda p: (
        max(0.0, min(1.0, (z_hoist - p.z) / (L * 0.92))),
        max(0.0, min(1.0, (top_y - p.y) / max(h, 1e-4))),
    )
    def P(i, j):
        t = i / nx; f = j / ny
        # Taper smoothly into a dramatic long forked pennant tail
        taper = 1.0 - 0.42 * t ** 1.2
        y_center = top_y - 0.5 * h - 0.22 * t * t + 0.09 * sin(t * 7.0)
        y = y_center + (0.5 - f) * h * taper
        x = 0.22 * sin(t * 8.2) * t ** 0.75 + 0.06 * sin(t * 16.0 + f * 2.2)
        notch = 0.48 * (1.0 - abs(2 * f - 1)) * max(0.0, (t - 0.68) / 0.32)
        z = z_hoist - t * L * (1.0 - notch * 0.34)
        return Vector((x, y, z))
    ids = [[mb.v(P(i, j)) for i in range(nx + 1)] for j in range(ny + 1)]
    for j in range(ny):
        for i in range(nx):
            idx = [ids[j][i], ids[j][i + 1], ids[j + 1][i + 1], ids[j + 1][i]]
            uvs = [(i / nx, 1 - j / ny), ((i + 1) / nx, 1 - j / ny),
                   ((i + 1) / nx, 1 - (j + 1) / ny), (i / nx, 1 - (j + 1) / ny)]
            mb.f(idx, 'flag', C_WHITE, uvs, True)

def rope_object(name, a, b):
    a = Vector(a); b = Vector(b); d = b - a; L = d.length; z = d / L
    x = Vector((0, 1, 0)).cross(z)
    if x.length < 1e-4:
        x = Vector((1, 0, 0))
    x.normalize(); y = z.cross(x)
    mb = MB(name)
    tube(mb, [(0, 0, 0), (0, 0, 0.5), (0, 0, 1)], 0.024, 6, 'rope', C_ROPE)
    mb.gmatrix = Matrix(((x.x, y.x, d.x, a.x), (x.y, y.y, d.y, a.y), (x.z, y.z, d.z, a.z), (0, 0, 0, 1)))
    build(mb)

# ---------------------------------------------------------------- MOVING MECHANISMS
def build_wheel(mb, o):
    with xf(mb, T(o) @ M_Y2Z):
        for (r0, r1, hh, c) in ((0.44, 0.54, 0.055, C_DARK), (0.19, 0.24, 0.038, C_DARK)):
            lathe(mb, [(r0, -hh), (r1 - 0.015, -hh), (r1, -hh + 0.015), (r1, hh - 0.015),
                       (r1 - 0.015, hh), (r0, hh), (r0, -hh)], 24, 'wood', c)
        # Brass rim ring accent
        torus(mb, 0.49, 0.016, 24, 5, 'brass', C_BRASS)
        for k in range(8):
            with xf(mb, R('Y', k * 45) @ M_Y2X):
                mat_s = 'brass' if k == 6 else 'wood'
                col_s = C_BRASS if k == 6 else C_HULL
                lathe(mb, [(0.032, 0.09), (0.042, 0.22), (0.032, 0.44), (0.048, 0.47), (0.048, 0.52),
                           (0.030, 0.55), (0.042, 0.62), (0.050, 0.69), (0.032, 0.75), (0, 0.76)], 7, mat_s, col_s, True, True)
        lathe(mb, [(0, -0.095), (0.12, -0.095), (0.135, -0.05), (0.135, 0.05), (0.10, 0.11), (0.045, 0.13), (0, 0.13)], 12, 'brass', C_BRASS)
        for k in range(8):
            with xf(mb, R('Y', k * 45 + 22.5) @ T(0.49, 0.056, 0)):
                ellipsoid(mb, (0, 0, 0), (0.022, 0.014, 0.022), 'brass', C_BRASS, 6, 3)

def build_rudder(mb, o):
    z0 = Z_STERN - 0.08
    with xf(mb, M_ZY):
        prism(mb, [(z0, -1.28), (z0 + 0.92, -1.28), (z0 + 1.02, -0.65),
                   (z0 + 0.66, 0.08), (z0 + 0.28, 0.48), (z0, 0.48)], -0.085, 0.085, 'wood', C_HULL, 0.022, (0, 0, 1))
    for y, L in ((-0.92, 0.86), (-0.32, 0.70), (0.22, 0.40)):
        cbox(mb, (0, y, z0 + L / 2 - 0.04), (0.21, 0.095, L), 'brass', C_BRASS, 0.012)
    cbox(mb, (0, -0.36, z0), (0.11, 1.84, 0.11), 'iron', C_IRON, 0.02)
    cbox(mb, (0, -1.04, z0 + 0.48), (0.18, 0.46, 0.86), 'wood', C_TAR, 0.02)

def build_capstan(mb, o):
    with xf(mb, T(o)):
        lathe(mb, [(0, 0), (0.50, 0), (0.50, 0.065), (0.44, 0.11), (0.32, 0.11)], 12, 'wood', C_DARK)
        lathe(mb, [(0.29, 0.11), (0.22, 0.45), (0.23, 0.76)], 12, 'wood', C_HULL, True, True)
        for k in range(6):
            with xf(mb, R('Y', k * 60 + 30)):
                hexa(mb, [(0.22, 0.11, -0.055), (0.41, 0.11, -0.055), (0.41, 0.11, 0.055), (0.22, 0.11, 0.055),
                          (0.20, 0.76, -0.055), (0.30, 0.76, -0.055), (0.30, 0.76, 0.055), (0.20, 0.76, 0.055)],
                     'wood', C_TEAL, (0, 1, 0))
        lathe(mb, [(0.22, 0.76), (0.44, 0.76), (0.46, 0.80), (0.46, 1.01), (0.40, 1.07), (0.14, 1.09), (0, 1.09)], 12, 'wood', C_DARK)
        lathe(mb, [(0, 1.09), (0.16, 1.09), (0.16, 1.125), (0.07, 1.17), (0, 1.17)], 10, 'brass', C_BRASS)
        for k in range(6):
            with xf(mb, R('Y', k * 60)):
                cbox(mb, (0.60, 0.90, 0), (0.48, 0.075, 0.075), 'wood', C_DECK, 0.015)
        lathe(mb, [(0.265, 0.32), (0.288, 0.32), (0.288, 0.56), (0.265, 0.56)], 12, 'rope', C_ROPE)

def build_anchor(mb, o):
    """Admiralty anchor catted at 42 deg under starboard cathead so both stock and flukes hang completely clear of bow."""
    with xf(mb, T(o) @ R('Y', 42)):
        for i in range(4):
            with xf(mb, T(0, 0.22 + 0.09 * i, 0) @ (M_Y2X if i % 2 else M_Y2Z)):
                torus(mb, 0.05, 0.015, 8, 4, 'iron', C_IRON)
        cbox(mb, (0, -0.76, 0), (0.11, 1.44, 0.11), 'iron', C_IRON, 0.025)
        with xf(mb, T(0, 0.11, 0) @ M_Y2X):
            torus(mb, 0.135, 0.032, 12, 6, 'iron', C_IRON)
        cbox(mb, (0, -0.18, 0), (0.98, 0.14, 0.14), 'wood', C_DARK, 0.03)
        for sx in (-0.36, 0.36):
            cbox(mb, (sx, -0.18, 0), (0.065, 0.17, 0.17), 'brass', C_BRASS, 0.01)
        Rr = 0.56; cy = -1.48 + Rr
        for sg in (-1, 1):
            secs = []
            for i in range(7):
                t = radians(i * 13.0); w = 0.062 - 0.020 * i / 6
                c = Vector((0, cy - Rr * cos(t), sg * Rr * sin(t))); rad = Vector((0, -cos(t), sg * sin(t)))
                secs.append([c - rad * w + Vector((-w, 0, 0)), c - rad * w + Vector((w, 0, 0)),
                             c + rad * w + Vector((w, 0, 0)), c + rad * w + Vector((-w, 0, 0))])
            loft(mb, secs, 'iron', C_IRON, True, (True, True), 'flat')
            t = radians(78); c = Vector((0, cy - Rr * cos(t), sg * Rr * sin(t)))
            tip = c + Vector((0, 0.22, sg * 0.06))
            for sx in (-1, 1):
                mb.newoff()
                mb.fp([c + Vector((sx * 0.034, -0.20, -sg * 0.15)), c + Vector((sx * 0.034, -0.05, sg * 0.13)), tip],
                      'iron', mul(C_IRON, 1.2), None, c)
            mb.fp([c + Vector((-0.034, -0.20, -sg * 0.15)), c + Vector((0.034, -0.20, -sg * 0.15)), tip], 'iron', C_IRON, None, c)
            mb.fp([c + Vector((-0.034, -0.05, sg * 0.13)), c + Vector((0.034, -0.05, sg * 0.13)), tip], 'iron', C_IRON, None, c)
            mb.fp([c + Vector((-0.034, -0.20, -sg * 0.15)), c + Vector((0.034, -0.20, -sg * 0.15)),
                   c + Vector((0.034, -0.05, sg * 0.13)), c + Vector((-0.034, -0.05, sg * 0.13))], 'iron', C_IRON, None, tip)

CANNON_TRUNNION = (0.05, 0.64, 0.0)
def build_cannon(mb, o, yaw):
    with xf(mb, T(o) @ R('Y', yaw)):
        for sz in (-1, 1):
            with xf(mb, T(0, 0, sz * 0.26) @ Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))):
                prism(mb, [(-0.58, 0.20), (0.52, 0.20), (0.52, 0.58), (0.20, 0.64), (-0.06, 0.64), (-0.58, 0.37)],
                      -0.058, 0.058, 'wood', C_INDIGO, 0.012, (1, 0, 0))
            cbox(mb, (0.05, 0.65, sz * 0.26), (0.21, 0.038, 0.13), 'brass', C_BRASS, 0.008)
        cbox(mb, (-0.03, 0.20, 0), (1.04, 0.095, 0.44), 'wood', mul(C_INDIGO, 0.85), 0.02)
        cbox(mb, (-0.43, 0.31, 0), (0.13, 0.145, 0.42), 'wood', C_DARK, 0.02)
        for sx in (-0.35, 0.33):
            cbox(mb, (sx, 0.155, 0), (0.135, 0.135, 0.86), 'wood', C_DARK, 0.02)
            for sz in (-1, 1):
                with xf(mb, T(sx, 0.155, sz * 0.41) @ M_Y2Z):
                    cyl(mb, 0.16, -0.058, 0.058, 14, 'wood', C_DARK, True, 0.02)
                    cyl(mb, 0.052, -0.072, 0.072, 6, 'brass', C_BRASS)
        for sz in (-1, 1):
            with xf(mb, T(-0.52, 0.31, sz * 0.31) @ M_Y2X):
                torus(mb, 0.052, 0.015, 8, 4, 'iron', C_IRON)

def build_cannon_barrel(mb, o, yaw):
    with xf(mb, T(o) @ R('Y', yaw)):
        with xf(mb, T(CANNON_TRUNNION) @ M_Y2X):
            k = 1.15
            prof = [(0, -0.92), (0.062, -0.91), (0.088, -0.85), (0.052, -0.79), (0.195, -0.76), (0.22, -0.71),
                    (0.22, -0.65), (0.195, -0.63), (0.19, -0.30), (0.21, -0.28), (0.21, -0.21), (0.18, -0.19),
                    (0.152, 0.52), (0.172, 0.54), (0.172, 0.60), (0.145, 0.62), (0.135, 0.94), (0.18, 0.99),
                    (0.185, 1.08), (0.168, 1.11), (0.102, 1.11), (0.102, 0.88), (0, 0.88)]
            brass_seg = {8, 9, 10, 12, 13, 14, 16, 17, 18, 19}
            for i in range(len(prof) - 1):
                seg = [(prof[i][0] * k, prof[i][1]), (prof[i + 1][0] * k, prof[i + 1][1])]
                isb = i in brass_seg
                lathe(mb, seg, 16, 'brass' if isb else 'iron', C_BRASS if isb else (C_BLACK if i >= 20 else C_IRON))
            with xf(mb, T(0, -0.68, 0.0)):
                cbox(mb, (0, 0, -0.255), (0.032, 0.032, 0.042), 'iron', C_BLACK, 0.005)
        with xf(mb, T(CANNON_TRUNNION) @ M_Y2Z):
            cyl(mb, 0.062, -0.34, 0.34, 8, 'iron', C_IRON)

def build_lantern(mb, c, s=1.0, hang=True):
    with xf(mb, T(c) @ S(s)):
        lathe(mb, [(0, -0.2), (0.13, -0.2), (0.15, -0.16), (0.12, -0.13)], 6, 'brass', C_BRASS, False)
        lathe(mb, [(0.11, -0.13), (0.15, 0.12)], 6, 'glass', C_GLASS, False)
        lathe(mb, [(0.15, 0.12), (0.19, 0.12), (0.19, 0.15), (0.07, 0.27), (0.07, 0.31), (0.03, 0.33), (0, 0.33)], 6, 'brass', C_BRASS, False)
        for k in range(6):
            a = 2 * pi * k / 6
            tube(mb, [(0.115 * cos(a), -0.13, 0.115 * sin(a)), (0.155 * cos(a), 0.12, 0.155 * sin(a))], 0.014, 4, 'brass', C_BRASS, mode='flat')
        if hang:
            with xf(mb, T(0, 0.38, 0) @ M_Y2X):
                torus(mb, 0.05, 0.012, 8, 4, 'brass', C_BRASS)

def build_winch(mb, o, band):
    sg = 1 if o[0] > 0 else -1
    with xf(mb, T(o) @ S(sg, 1, 1)):
        cbox(mb, (-0.02, 0.04, 0), (0.44, 0.08, 0.72), 'wood', C_DARK, 0.02)
        for sz in (-1, 1):
            hexa(mb, [(-0.19, 0.08, sz * 0.27 - 0.05), (0.15, 0.08, sz * 0.27 - 0.05),
                      (0.15, 0.08, sz * 0.27 + 0.05), (-0.19, 0.08, sz * 0.27 + 0.05),
                      (-0.10, 0.80, sz * 0.27 - 0.05), (0.06, 0.80, sz * 0.27 - 0.05),
                      (0.06, 0.80, sz * 0.27 + 0.05), (-0.10, 0.80, sz * 0.27 + 0.05)], 'wood', band, (0, 1, 0))
        with xf(mb, T(-0.02, 0.62, 0) @ M_Y2Z):
            lathe(mb, [(0, -0.22), (0.155, -0.22), (0.155, -0.18), (0.105, -0.16), (0.105, 0.16),
                       (0.155, 0.18), (0.155, 0.22), (0, 0.22)], 10, 'wood', C_HULL)
            lathe(mb, [(0.105, -0.15), (0.13, -0.15), (0.13, 0.15), (0.105, 0.15)], 10, 'rope', C_ROPE)
            cyl(mb, 0.032, -0.42, 0.42, 6, 'brass', C_BRASS)
        for sz in (-1, 1):
            cbox(mb, (-0.02, 0.51, sz * 0.41), (0.05, 0.27, 0.04), 'iron', C_IRON, 0.008)
            cbox(mb, (-0.02, 0.40, sz * 0.48), (0.05, 0.05, 0.16), 'wood', C_CREAM, 0.012)
        cbox(mb, (0.10, 0.86, 0), (0.075, 0.075, 0.52), 'wood', C_CREAM, 0.02)
        for z in (-0.14, 0.14):
            cbox(mb, (0.10, 0.86, z), (0.035, 0.26, 0.035), 'brass', C_BRASS, 0.01)
    with xf(mb, T(o)):
        rope_coil(mb, (-sg * 0.44, 0, -0.44), 0.19, 3)

def build_powder_keg(mb, o):
    barrel(mb, o, 0.20, 0.46, tone=C_DARK, band=C_BRASS)
    with xf(mb, T(o)):
        lathe(mb, [(0.20, 0.17), (0.212, 0.17), (0.212, 0.29), (0.20, 0.29)], 12, 'paint', C_RED, False)
        cyl(mb, 0.035, 0.44, 0.50, 6, 'wood', C_CREAM)

def build_bell(mb, o):
    x, y, z = o
    cbox(mb, (x + 0.22, y + 0.06, z), (0.54, 0.065, 0.065), 'iron', C_IRON, 0.012)
    hexa(mb, [(x + 0.45, y - 0.30, z - 0.025), (x + 0.39, y - 0.30, z - 0.025),
              (x + 0.39, y - 0.30, z + 0.025), (x + 0.45, y - 0.30, z + 0.025),
              (x + 0.45, y + 0.04, z - 0.025), (x + 0.14, y + 0.04, z - 0.025),
              (x + 0.14, y + 0.04, z + 0.025), (x + 0.45, y + 0.04, z + 0.025)], 'iron', C_IRON)
    with xf(mb, T(o)):
        lathe(mb, [(0, 0.02), (0.032, 0.02), (0.038, -0.02), (0.065, -0.055), (0.11, -0.10),
                   (0.13, -0.22), (0.148, -0.31), (0.185, -0.36), (0.19, -0.39), (0.16, -0.39),
                   (0.13, -0.32), (0.11, -0.22), (0, -0.13)], 14, 'brass', C_BRASS)
        tube(mb, [(0, -0.13, 0), (0, -0.35, 0)], 0.013, 4, 'iron', C_IRON)
        ellipsoid(mb, (0, -0.37, 0), (0.038, 0.038, 0.038), 'iron', C_IRON, 6, 4)
        tube(mb, [(0, -0.39, 0), (0.0, -0.58, 0.02), (0.01, -0.65, 0.02)], 0.015, 4, 'rope', C_ROPE)

def build_bucket(mb, o):
    rng = mb.rng; cols = [jit(C_HULL, rng, 0.14) for _ in range(10)]
    with xf(mb, T(o)):
        lathe(mb, [(0, 0), (0.13, 0), (0.165, 0.30), (0.145, 0.30), (0.118, 0.03), (0, 0.03)],
              10, 'wood', C_HULL, False, False, lambda i, k: mul(cols[k], 0.7 if i >= 3 else 1.0))
        for yy, rr in ((0.06, 0.142), (0.24, 0.163)):
            lathe(mb, [(rr - 0.01, yy - 0.02), (rr + 0.006, yy - 0.02), (rr + 0.006, yy + 0.02), (rr - 0.01, yy + 0.02)],
                  10, 'brass', C_BRASS, False)
        tube(mb, [(0.155 * cos(a * pi / 8), 0.28 + 0.16 * sin(a * pi / 8), 0.02) for a in range(9)], 0.013, 4, 'rope', C_ROPE)

def build_plank_stack(mb, o):
    rng = mb.rng
    with xf(mb, T(o)):
        for sz in (-0.5, 0.5):
            cbox(mb, (0, 0.03, sz), (0.62, 0.06, 0.08), 'wood', C_DARK, 0.012)
        for layer in range(4):
            for i in range(3 if layer < 3 else 2):
                cbox(mb, (-0.18 + 0.18 * i + rng.uniform(-0.015, 0.015) + (0.09 if layer == 3 else 0),
                          0.085 + layer * 0.05, rng.uniform(-0.06, 0.06)),
                     (0.165, 0.045, 1.55 + rng.uniform(-0.1, 0.1)),
                     'wood', jit(C_DECK, rng, 0.12), 0.01, None, R('Y', rng.uniform(-2, 2)))
        with xf(mb, T(0.05, 0.285, 0.30) @ R('Y', 35)):
            cbox(mb, (0, 0.04, 0), (0.10, 0.08, 0.20), 'wood', C_DARK, 0.015)
            cbox(mb, (0.18, 0.04, 0), (0.30, 0.035, 0.035), 'wood', C_HULL, 0.008)

def build_hatch_cover(mb, o, sg):
    hx0, hx1, hz0, hz1 = HATCH; L = hz1 - hz0 + 0.10; W = hx1 + 0.12
    with xf(mb, T(o) @ S(sg, 1, 1) @ R('Z', -12)):
        for yy in (0.04, W - 0.04):
            cbox(mb, (0, yy, 0), (0.06, 0.08, L), 'wood', C_DARK, 0.015)
        for zz in (-L / 2 + 0.04, 0, L / 2 - 0.04):
            cbox(mb, (0, W / 2, zz), (0.062, W, 0.08), 'wood', C_DARK, 0.015)
        nsl = 5
        for i in range(nsl):
            cbox(mb, (0.0, 0.08 + (W - 0.16) * (i + 0.5) / nsl, 0), (0.035, 0.06, L - 0.10),
                 'wood', jit(C_DECK, mb.rng, 0.1), 0.01)
        for zz in (-L / 2 + 0.30, L / 2 - 0.30):
            cbox(mb, (-0.035, 0.03, zz), (0.02, 0.10, 0.12), 'brass', C_BRASS, 0.004)

def build_bilge(mb, c):
    x, y, z = c
    for (cx, cz, sx, sz) in ((0, -0.35, 0.78, 0.08), (0, 0.35, 0.78, 0.08),
                             (-0.35, 0, 0.08, 0.62), (0.35, 0, 0.08, 0.62)):
        cbox(mb, (x + cx, y + 0.03, z + cz), (sx, 0.07, sz), 'wood', C_DARK, 0.015)
    cbox(mb, (x, y + 0.006, z), (0.64, 0.012, 0.64), 'paint', srgb('#0b2a33'), 0.0)
    for i in range(5):
        cbox(mb, (x - 0.25 + 0.125 * i, y + 0.035, z), (0.05, 0.035, 0.64), 'wood', jit(C_INNER, mb.rng, 0.1), 0.008)
    for i in range(2):
        cbox(mb, (x, y + 0.02, z - 0.16 + 0.32 * i), (0.64, 0.03, 0.05), 'wood', C_DARK, 0.006)

# ---------------------------------------------------------------- BREACH HOLES & PATCHES
def build_holes():
    for P in PANELS:
        idx = P['idx']; sg = P['side']; jb = P['jb']
        build(P['mb'])
        hb = MB('Hole_%02d' % (idx + 1), P['origin'], seed=idx, yaw=P['yaw']); rng = hb.rng
        lo = (VS[jb] - VS[jb - 1]) * P['mpv']; hi = (VS[jb + 1] - VS[jb]) * P['mpv']
        def pt(a, b, depth):
            u = umap(P['sc'] + a / P['mps']); v = P['v'] + b / P['mpv']
            q = hull_pt(u, v) - hull_n(u, v) * depth; q.x = max(q.x, 0.0)
            return q
        K = 24; ra = 0.28; rb = min(0.22, 0.74 * min(lo, hi))
        ang = [2 * pi * k / K for k in range(K)]
        rad = []
        for k, t in enumerate(ang):
            r = 1.0 / sqrt((cos(t) / ra) ** 2 + (sin(t) / rb) ** 2)
            rad.append(r * (0.62 + 0.5 * rng.random()) * (1.12 if k % 3 == 0 else 0.92))
        H = [(rad[k] * cos(t), rad[k] * sin(t)) for k, t in enumerate(ang)]
        def edge(t):
            c, sn = cos(t), sin(t)
            f = min(PANEL_HALF / abs(c) if abs(c) > 1e-9 else 1e9,
                    (hi if sn > 0 else lo) / abs(sn) if abs(sn) > 1e-9 else 1e9)
            return (f * c, f * sn)
        Rr = [edge(t) for t in ang]
        corners = [(PANEL_HALF, hi), (-PANEL_HALF, hi), (-PANEL_HALF, -lo), (PANEL_HALF, -lo)]
        cang = [atan2(c[1], c[0]) % (2 * pi) for c in corners]
        tu = (pt(0.05, 0, 0) - pt(-0.05, 0, 0)).normalized()
        c0 = pt(0, 0, TH / 2)
        splinter = jit(mix(C_HULL, C_DECK, 0.7), rng, 0.1)
        with xf(hb, S(sg, 1, 1)):
            for k in range(K):
                k1 = (k + 1) % K; t0 = ang[k]; t1 = ang[k1] if k1 else 2 * pi
                j = jb if sin((t0 + t1) / 2) > 0 else jb - 1
                colr, inner, extra = P['cols'].get(j, (C_HULL, C_INNER, 0.0))
                ring = [Rr[k]] + [corners[i] for i in range(4) if t0 < cang[i] < t1] + [Rr[k1]]
                hb.newoff()
                for depth, cc in ((-extra, colr), (TH, inner)):
                    poly = [pt(H[k][0], H[k][1], depth)] + [pt(a, b, depth) for a, b in ring] + [pt(H[k1][0], H[k1][1], depth)]
                    hb.fp(poly, 'wood', cc, tu, c0)
                wall = [pt(H[k][0], H[k][1], -extra), pt(H[k1][0], H[k1][1], -extra),
                        pt(H[k1][0], H[k1][1], TH), pt(H[k][0], H[k][1], TH)]
                mid = pt((H[k][0] + H[k1][0]) * 0.8, (H[k][1] + H[k1][1]) * 0.8, TH / 2)
                hb.fp(wall, 'wood', jit(splinter, rng, 0.12), tu, mid)
                if rng.random() < 0.45:
                    a = pt(H[k][0], H[k][1], TH); b = pt(H[k1][0], H[k1][1], TH)
                    tip = pt(H[k][0] * 0.55, H[k][1] * 0.55, TH + rng.uniform(0.05, 0.16))
                    hb.fp([a, b, tip], 'wood', splinter, tu, c0)
                    hb.fp([b, a, tip], 'wood', mul(splinter, 0.75), tu, tip + (tip - c0))
        build(hb)

        pb = MB('HolePatch_%02d' % (idx + 1), P['origin'], seed=idx, yaw=P['yaw']); rng = pb.rng
        p = pt(0, 0, 0); n = (pt(0, 0, 0) - pt(0, 0, 0.1)).normalized(); tv = n.cross(tu)
        if tv.y < 0:
            tv = -tv
        c = p - n * (TH + 0.155)
        M = Matrix(((tu.x, tv.x, -n.x, c.x), (tu.y, tv.y, -n.y, c.y), (tu.z, tv.z, -n.z, c.z), (0, 0, 0, 1)))
        with xf(pb, S(sg, 1, 1) @ M):
            for i in range(4):
                yy = -0.27 + 0.18 * i + rng.uniform(-0.01, 0.01)
                L = 0.88 + rng.uniform(-0.08, 0.12); rz = rng.uniform(-7, 7)
                with xf(pb, T(rng.uniform(-0.06, 0.06), yy, 0.006 * (i % 2)) @ R('Z', rz)):
                    cbox(pb, (0, 0, 0), (L, 0.17, 0.04), 'wood', jit(mix(C_DECK, C_CREAM, 0.25), rng, 0.14), 0.012)
                    for sx in (-1, 1):
                        cbox(pb, (sx * (L / 2 - 0.07), 0.0, 0.024), (0.03, 0.03, 0.012), 'iron', C_IRON, 0.004)
        build(pb)

def extras(hull):
    sf = MB('Sail_Furled', (0, YARD_Y, MAST_Z))
    build_sail_furled(sf, MAST_Z, YARD_Y, YARD_FWD, YARD_HALF); build(sf)
    sff = MB('Sail_Furled_Fore', (0, YARD_FORE_Y, MAST_FORE_Z))
    build_sail_furled(sff, MAST_FORE_Z, YARD_FORE_Y, YARD_FORE_FWD, YARD_FORE_HALF); build(sff)

    o = (-0.68, 3.15, MAST_Z); b = MB('Bell', o); build_bell(b, o); build(b)
    o = (0.64, HOLD_Y, 2.25); bk = MB('Bucket', o); build_bucket(bk, o); hull.merge(bk); empty_anchor('Bucket', o)
    o = (-1.15, HOLD_Y, 1.75); ps = MB('PlankStack', o); build_plank_stack(ps, o); hull.merge(ps); empty_anchor('PlankStack', o)

    hx0, hx1, hz0, hz1 = HATCH
    for name, sg in (('HatchCover_Starboard', 1), ('HatchCover_Port', -1)):
        o = (sg * (hx1 + 0.13), DECK_Y + 0.21, (hz0 + hz1) / 2 - 0.04)
        h = MB(name, o); build_hatch_cover(h, o, sg); build(h)

    build_holes()

    # Water cutout polygon inside the flared hull waterline (for Ocean hull mask)
    wm = MB('mask_water')
    poly = deck_outline(0.50, 0.50, zstem(0.50) + 0.14, zstern(0.50) - 0.04, 24, 1.3, 0.04)
    wm.newoff(); wm.fp([(x, 0.0, z) for x, z in poly], 'col', C_WHITE, None, (0, -5, 0))
    build(wm)

def rig_clearance():
    """Verify BOTH yards (main & fore) clear ALL standing rigging & the other mast over +-1.2 rad trim."""
    segs = [(b, t, 0.032) for _, _, b, t in main_shroud_pts() + fore_shroud_pts()]
    segs += standing_stays()
    # Also verify each yard clears the opposite mast pole
    mast_segs = {
        'main': [(Vector((0, DECK_Y, MAST_FORE_Z)), Vector((0, MAST_FORE_TOP, MAST_FORE_Z)), 0.26)],
        'fore': [(Vector((0, DECK_Y, MAST_Z)), Vector((0, MAST_TOP, MAST_Z)), 0.32)],
    }
    worst = {}
    for label, mz, yy, yf, hw in (('main', MAST_Z, YARD_Y, YARD_FWD, YARD_HALF),
                                  ('fore', MAST_FORE_Z, YARD_FORE_Y, YARD_FORE_FWD, YARD_FORE_HALF)):
        best = 9.0
        check_segs = segs + mast_segs[label]
        for i in range(97):
            th = -1.2 + 2.4 * i / 96
            for k in range(81):
                x = -(hw + 0.06) + 2 * (hw + 0.06) * k / 80
                r = 0.08 + 0.068 * (1 - abs(x / hw) ** 1.5) if abs(x) < hw else 0.10
                q = Vector((x * cos(th) - yf * sin(th), yy, mz - x * sin(th) - yf * cos(th)))
                for a, b, rr in check_segs:
                    d = b - a; f = max(0.0, min(1.0, (q - a).dot(d) / d.dot(d)))
                    best = min(best, (q - (a + d * f)).length - r - rr)
        worst[label] = best
    return worst

# ---------------------------------------------------------------- COLLISION (WALKABLE BY PAWN)
def col_wall(name, s0, s1, y0, y1fn, thick=TH, extra_out=0.0, ns=3, ny=3):
    for sg, tag in ((1, 'S'), (-1, 'P')):
        pts = []
        for i in range(ns):
            s = s0 + (s1 - s0) * i / (ns - 1); u = umap(s); yt = y1fn(hull_pt(u, 1.0).z, u)
            for j in range(ny):
                y = y0 + (yt - y0) * j / (ny - 1); v = v_of_y(u, y)
                p = hull_pt(u, min(v, 1.0)); n = hull_n(u, min(v, 1.0))
                if v > 1.0:
                    p.y = y; n = Vector((n.x, 0, n.z)).normalized()
                a = p + n * extra_out
                b = p - n * (hull_th(p.y) if thick == TH else thick); b.x = max(b.x, 0.0)
                pts += [(sg * a.x, a.y, a.z), (sg * b.x, b.y, b.z)]
        col_piece('col_%s_%s' % (name, tag), pts)

def build_collision():
    # Hull below the hold floor
    zb = [Z_STERN - 0.25, 5.8, 3.2, 0.4, -2.4, -5.0, -6.8, -8.1]
    for i in range(len(zb) - 1):
        pts = []
        for z in (zb[i], (zb[i] + zb[i + 1]) / 2, zb[i + 1]):
            for y in (-1.10, (HOLD_Y - 1.10) / 2, HOLD_Y - 0.005):
                x = hull_b(z, y)
                if z > zstem(y) + 0.01:
                    pts += [(x, y, z), (-x, y, z)]
            if z > -5.5:
                pts += [(0.14, -1.32, z), (-0.14, -1.32, z)]
            elif z > zstem(-1.05):
                pts += [(0, -1.10, z)]
        if len(pts) >= 4:
            col_piece('col_hull_bottom_%d' % i, pts)

    # Curved hull sides from hold floor to main deck in 3 vertical bands (keeps hold hollow!)
    zs = [8.2, 6.8, 5.2, 3.6, 1.8, 0.0, -1.8, -3.6, -5.4, -7.0, -8.2, -9.1]
    bands = [('low', HOLD_Y - 0.03, -0.45), ('mid', -0.45, 0.35), ('high', 0.35, DECK_Y - 0.02)]
    for i in range(len(zs) - 1):
        s0 = 0.0 if i == 0 else s_of_z(zs[i], 0.45)
        s1 = s_of_z(zs[i + 1], 0.45)
        for nm, ya, yb in bands:
            col_wall('hull_side_%s_%d' % (nm, i), s0, s1, ya, lambda z, u, yb=yb: yb)

    # Bulwarks & rails (leaving all 4 gunports & 2 boarding ladders open!)
    sq = s_of_z(QDECK_Z)
    def top(z, u): return ytop(z) + (0.68 if z > QDECK_Z - 0.01 else 0.12)
    k = 0
    for (a, b) in top_intervals(NS - 0.5):
        cuts = [a] + [c for c in (sq, s_of_z(6.0), s_of_z(2.8), s_of_z(-4.5), s_of_z(-6.5), s_of_z(-8.0))
                      if a + 0.5 < c < b - 0.5] + [b]
        cuts.sort()
        for i in range(len(cuts) - 1):
            col_wall('rail_%d' % k, cuts[i], cuts[i + 1], DECK_Y - 0.02, top, 0.21)
            k += 1

    # Stem & Transom
    col_piece('col_stem', [(sx * 0.145, y, zstem(y) + dz) for y in (-0.7, 0.3, 1.4, 3.10) for sx in (-1, 1) for dz in (-0.28, 0.32)])
    pts = []; yt = ytop(Z_STERN) + 0.68
    for y in (YT, 0.2, 0.8, 1.6, 2.3, yt):
        for sg in (-1, 1):
            for dz in (0.04, -0.17):
                pts.append((sg * max(wtrans(y), 0.12), y, zstern(y) + dz))
    col_piece('col_transom', pts)

    # Decks & Hold floor slabs
    main = deck_outline(DECK_Y - 0.1, DECK_Y, Z_BOW - 0.05, QDECK_Z + 0.10, 44, 1.7)
    hx0, hx1, hz0, hz1 = HATCH; qx0, qx1, qz0, qz1 = QSTAIR
    def slab(name, poly, y0, y1):
        if poly:
            col_piece(name, [(x, y, z) for x, z in poly for y in (y0, y1)])
    slab('col_deck_main_fore', clip_rect(main, -9, 9, -10, hz0), DECK_Y - 0.1, DECK_Y)
    slab('col_deck_main_port', clip_rect(main, -9, hx0, hz0, hz1), DECK_Y - 0.1, DECK_Y)
    slab('col_deck_main_starboard', clip_rect(main, hx1, 9, hz0, hz1), DECK_Y - 0.1, DECK_Y)
    slab('col_deck_main_aft', clip_rect(main, -9, 9, hz1, QDECK_Z + 0.10), DECK_Y - 0.1, DECK_Y)

    zq1 = zstern(QDECK_Y) - 0.10
    quarter = deck_outline(QDECK_Y - 0.1, QDECK_Y, QDECK_Z - 0.06, zq1, 12, 1.0)
    slab('col_quarterdeck_fore', clip_rect(quarter, -qx0, qx0, QDECK_Z - 0.06, qz1), QDECK_Y - 0.1, QDECK_Y)
    slab('col_quarterdeck_aft', clip_rect(quarter, -9, 9, qz1, 10), QDECK_Y - 0.1, QDECK_Y)
    slab('col_hold_floor', deck_outline(HOLD_Y - 0.06, HOLD_Y, -5.65, 7.30, 18, 1.0, inner=True), HOLD_Y - 0.1, HOLD_Y)

    # Quarterdeck twin ramps & hold stair ramp
    for sg, tag in ((1, 'S'), (-1, 'P')):
        col_piece('col_stairs_quarter_%s' % tag,
                  [(sg * x, y, z) for x in (qx0, qx1)
                   for (y, z) in ((DECK_Y, qz0), (DECK_Y - 0.1, qz0), (DECK_Y - 0.1, QDECK_Z + 0.05),
                                  (QDECK_Y - 0.42, qz1), (QDECK_Y, qz1))])
        col_piece('col_stairwell_%s' % tag,
                  [(sg * x, y, z) for x in (qx0 - 0.08, qx0) for y in (DECK_Y - 0.1, QDECK_Y + 0.92)
                   for z in (QDECK_Z, qz1 + 0.06)])
    zt, zbm = HOLD_STAIR[0] + 0.03, HOLD_STAIR[1]
    col_piece('col_stairs_hold',
              [(sx * 0.45, y + dy, z) for sx in (-1, 1) for (y, z) in ((DECK_Y, zt), (HOLD_Y, zbm)) for dy in (0.0, -0.16)])

    # Quarterdeck break bulkhead, front balustrade & forward hold bulkhead
    col_piece('col_bulkhead_quarter',
              [(sx * qx0, y, z) for sx in (-1, 1) for y in (DECK_Y - 0.1, QDECK_Y) for z in (QDECK_Z, QDECK_Z + 0.12)])
    col_piece('col_rail_quarter_front',
              [(sx * qx0, y, z) for sx in (-1, 1) for y in (QDECK_Y, QDECK_Y + 0.92) for z in (QDECK_Z - 0.03, QDECK_Z + 0.10)])
    hbk = hull_b(-5.65, DECK_Y - 0.1) - 0.1
    col_piece('col_bulkhead_hold',
              [(sx * x, y, -5.65 + dz) for sx in (-1, 1)
               for (x, y) in ((hull_b(-5.65, HOLD_Y) - 0.1, HOLD_Y), (hbk, DECK_Y - 0.1)) for dz in (-0.06, 0.06)])

    # Both masts, crow's nest & bowsprit
    col_piece('col_mast', [(0.34 * cos(k * pi / 4), y, MAST_Z + 0.34 * sin(k * pi / 4)) for k in range(8) for y in (HOLD_Y, 12.1)])
    col_piece('col_mast_top', [(r * cos(k * pi / 4), y, MAST_Z + r * sin(k * pi / 4)) for k in range(8) for (y, r) in ((12.1, 0.96), (13.15, 1.04))])
    col_piece('col_mast_fore', [(0.28 * cos(k * pi / 4), y, MAST_FORE_Z + 0.28 * sin(k * pi / 4)) for k in range(8) for y in (HOLD_Y, 11.1)])
    col_piece('col_bowsprit',
              [(sx * 0.16, BS_HEEL[1] + dy + (BS_TIP[1] - BS_HEEL[1]) * f, BS_HEEL[2] + (BS_TIP[2] - BS_HEEL[2]) * f)
               for sx in (-1, 1) for dy in (-0.16, 0.16) for f in (0, 1)])

# ================================================================ DISTANT LOD (< 2500 TRIS)
def build_lod(outdir):
    """Under 2500 triangles preserving the dramatic 2-masted Brigantine silhouette, colours & all moving sail/yard/flag nodes."""
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me, do_unlink=True)
    OBJS.clear()

    mb = MB('Hull'); NL = 14
    rows = [0, 3, J_BOOT, J_BOOT + 1, J_WALE, J_WALE + 1, J_SILL, J_SHEER, len(YS) - 1]
    ss = [NS * (i / NL) for i in range(NL)] + [NS - 0.05]
    for sg in (-1, 1):
        with xf(mb, S(sg, 1, 1)):
            for r in range(len(rows) - 1):
                colr, _ = strake_look(rows[r]) if rows[r + 1] - rows[r] == 1 or rows[r] in (0, J_SILL) else (C_HULL, 0)
                for i in range(len(ss) - 1):
                    zmid = hull_pt(umap((ss[i] + ss[i + 1]) / 2), 1.0).z
                    if rows[r] >= J_SILL and any(z0 < zmid < z1 for z0, z1 in GAPS):
                        continue
                    q = [hull_pt(umap(ss[i]), VS[rows[r]]), hull_pt(umap(ss[i + 1]), VS[rows[r]]),
                         hull_pt(umap(ss[i + 1]), VS[rows[r + 1]]), hull_pt(umap(ss[i]), VS[rows[r + 1]])]
                    c = sum(q, Vector()) / 4
                    mb.fp(q, 'paint', mul(colr, 0.93 + 0.07 * ((i + r) % 2)), None, (0, c.y, c.z))
                    if rows[r] > J_WALE:
                        mb.fp([Vector((p.x - 0.14, p.y, p.z)) for p in q], 'paint', mul(C_HULL, 0.8), None, (9, c.y, c.z))
            ss2 = ss[:-1] + [NS - 1.0]
            for i in range(len(ss2) - 1):
                a, na = rail_frame(ss2[i]); b, nb = rail_frame(ss2[i + 1])
                zmid = (a.z + b.z) / 2
                if any(z0 < zmid < z1 for z0, z1 in GAPS):
                    continue
                mb.fp([a - na * 0.22 + Vector((0, 0.06, 0)), a + na * 0.06 + Vector((0, 0.06, 0)),
                       b + nb * 0.06 + Vector((0, 0.06, 0)), b - nb * 0.22 + Vector((0, 0.06, 0))], 'paint', C_DARK, None, (0, -5, 0))
                if zmid > QDECK_Z:
                    up = Vector((0, 0.62, 0))
                    for inside in ((0, 0, zmid), (9, 0, zmid)):
                        mb.fp([a + up - Vector((0, 0.10, 0)), b + up - Vector((0, 0.10, 0)), b + up, a + up], 'brass', C_BRASS, None, inside)

    # Decks, bulkhead, transom + glowing windows + compass medallion
    main = deck_outline(DECK_Y, DECK_Y, Z_BOW, QDECK_Z, 8, 1.6, 0.10)
    quarter = deck_outline(QDECK_Y, QDECK_Y, QDECK_Z, zstern(QDECK_Y) - 0.10, 3, 1.0, 0.10)
    mb.fp([(x, DECK_Y, z) for x, z in main], 'paint', C_DECK, None, (0, -5, 0))
    mb.fp([(x, QDECK_Y, z) for x, z in quarter], 'paint', C_DECK, None, (0, -5, 0))
    hb = hull_b(QDECK_Z, QDECK_Y) - 0.10
    mb.fp([(-hb, DECK_Y, QDECK_Z), (hb, DECK_Y, QDECK_Z), (hb, QDECK_Y, QDECK_Z), (-hb, QDECK_Y, QDECK_Z)], 'paint', C_TEAL, None, (0, 1.5, 12))

    yts = ytop(Z_STERN)
    for (y0, y1, c) in ((YT, 0.10, C_TAR), (0.10, 0.56, C_HULL), (0.56, 1.74, C_TEAL),
                        (1.74, yts - 0.16, C_HULL), (yts - 0.16, yts, C_GOLD)):
        mb.fp([(-wtrans(y0), y0, zstern(y0)), (wtrans(y0), y0, zstern(y0)),
               (wtrans(y1), y1, zstern(y1)), (-wtrans(y1), y1, zstern(y1))], 'paint', c, None, (0, 1, 0))
    for wx in (-1.05, 0.0, 1.05):
        mb.fp([(wx - 0.34, 0.72, zstern(0.72) + 0.025), (wx + 0.34, 0.72, zstern(0.72) + 0.025),
               (wx + 0.34, 1.58, zstern(1.58) + 0.025), (wx - 0.34, 1.58, zstern(1.58) + 0.025)], 'glass', C_GLASS, None, (0, 1, 0))
    with xf(mb, T(0, 2.42, zstern(2.42) + 0.02) @ M_Y2Z):
        lathe(mb, [(0, 0), (0.48, 0), (0, 0.06)], 8, 'brass', C_BRASS, False)
    cbox(mb, (0, yts + 0.62, zstern(yts) - 0.05), (2 * wtrans(yts), 0.10, 0.14), 'brass', C_BRASS, 0.0)

    # Keel, stem, rudder
    path = [(Z_STERN - 0.25, -1.10), (-5.4, -1.10)] + [(_SB[i][1], _SB[i][0]) for i in range(48, 241, 48)] + [(zstem(2.2), 2.2), (zstem(3.0), 3.0)]
    secs = []; scols = []
    for i, (z, y) in enumerate(path):
        a = path[max(i - 1, 0)]; b = path[min(i + 1, len(path) - 1)]
        t = Vector((b[0] - a[0], b[1] - a[1])).normalized(); n = Vector((-t.y, t.x))
        o = Vector((0, y + n.y * 0.24, z + n.x * 0.24)); q = Vector((0, y - n.y * 0.10, z - n.x * 0.10))
        secs.append([q + Vector((-0.14, 0, 0)), q + Vector((0.14, 0, 0)), o + Vector((0.14, 0, 0)), o + Vector((-0.14, 0, 0))])
        scols.append(C_TAR if y < 0.10 else C_GOLD)
    loft(mb, secs, 'paint', C_TAR, True, (True, True), 'flat', scols=scols)
    box2(mb, (-0.08, -1.28, Z_STERN - 0.15), (0.08, 0.45, Z_STERN + 0.90), 'paint', C_HULL, 0.0)

    # Both masts, crow's nest, fore fighting top, bowsprit & figurehead
    with xf(mb, T(0, 0, MAST_Z)):
        lathe(mb, [(0.34, DECK_Y), (0.26, 12.1), (0.17, 13.6), (0.095, MAST_TOP), (0, MAST_TOP + 0.22)], 6, 'paint', mul(C_DECK, 0.92))
        lathe(mb, [(0.26, 12.1), (0.86, 12.1), (1.02, 13.06), (1.06, 13.06), (1.06, 13.18), (0, 13.18)],
              8, 'paint', C_HULL, False, False, lambda i, k: C_TEAL if i >= 2 else C_HULL)
    with xf(mb, T(0, 0, MAST_FORE_Z)):
        lathe(mb, [(0.28, DECK_Y), (0.21, 10.95), (0.14, 11.8), (0.08, MAST_FORE_TOP), (0, MAST_FORE_TOP + 0.20)], 5, 'paint', mul(C_DECK, 0.92))
        lathe(mb, [(0.21, 10.95), (0.76, 10.95), (0.76, 11.20), (0, 11.20)], 6, 'paint', C_DARK, False)
    tube(mb, [BS_HEEL, BS_TIP], [0.21, 0.11], 5, 'paint', mul(C_DECK, 0.92), mode='flat')
    # Stylized figurehead silhouette
    tube(mb, [(0, 1.80, -9.60), (0, 2.55, -10.25), (0, 3.04, -10.72), (0, 2.94, -11.45)], [0.32, 0.22, 0.20, 0.07], 5, 'paint', C_GOLD, mode='flat')

    # Silhouette fittings: 4 broadside cannons, wheel, capstan, stern lantern
    for zc in (-2.4, 1.4):
        for sg in (-1, 1):
            cbox(mb, (sg * 2.25, DECK_Y + 0.64, zc), (1.6, 0.30, 0.30), 'paint', C_IRON, 0.0)
            cbox(mb, (sg * 1.85, DECK_Y + 0.30, zc), (0.95, 0.40, 0.56), 'paint', C_INDIGO, 0.0)
    cbox(mb, (0, QDECK_Y + 0.60, 6.50), (0.36, 1.20, 0.36), 'paint', C_TEAL, 0.0)
    with xf(mb, T(0, QDECK_Y + 0.95, 6.80) @ M_Y2Z):
        lathe(mb, [(0, -0.04), (0.54, -0.04), (0.54, 0.04), (0, 0.04)], 8, 'paint', C_DARK, False)
    with xf(mb, T(0, DECK_Y, -6.5)):
        lathe(mb, [(0.44, 0), (0.26, 0.52), (0.45, 0.80), (0.45, 1.08), (0, 1.12)], 6, 'paint', C_DARK, False)
    yl = yts + 1.65
    cbox(mb, (0, yl, zstern(yts) - 0.02), (0.40, 0.54, 0.40), 'glass', C_GLASS, 0.0)
    cbox(mb, (0, yl - 0.80, zstern(yts) - 0.02), (0.10, 1.15, 0.10), 'paint', C_IRON, 0.0)

    # Sparse standing rigging silhouette (3-sided ropes)
    lines = [(a, b) for a, b, _ in standing_stays()]
    for sg, k, bot, top in main_shroud_pts() + fore_shroud_pts():
        if k in (0, 2):
            lines.append((bot, top))
    for a, b in lines:
        tube(mb, [a, b], 0.042, 3, 'paint', C_ROPE_D, (False, False), 'flat')
    build(mb)

    # Separate moving LOD yards, sails, furled sails & flags (exact pivots & names!)
    for (suf, mz, yy, yf, hw, pt_fn, w_fn, top_y, fh, fl) in (
        ('', MAST_Z, YARD_Y, YARD_FWD, YARD_HALF, main_sail_pt, main_sail_wfn, MAST_TOP - 0.12, 1.25, 3.6),
        ('_Fore', MAST_FORE_Z, YARD_FORE_Y, YARD_FORE_FWD, YARD_FORE_HALF, fore_sail_pt, fore_sail_wfn, MAST_FORE_TOP - 0.10, 0.96, 2.65),
    ):
        z = mz - yf
        yd = MB('Yard' + suf, (0, yy, mz))
        tube(yd, [(-hw, yy, z), (0, yy, z), (hw, yy, z)], [0.08, 0.145, 0.08], 5, 'paint', mul(C_DECK, 0.85), mode='flat')
        build(yd)

        sl = MB('Sail' + suf, (0, yy, mz)); sl.wfn = w_fn; nx, ny = 6, 4
        pts = [[pt_fn(-1 + 2 * i / nx, j / ny) for i in range(nx + 1)] for j in range(ny + 1)]
        front = [[sl.v(q) for q in row] for row in pts]
        back = [[sl.v(q + Vector((0, 0, 0.015))) for q in row] for row in pts]
        for j in range(ny):
            for i in range(nx):
                qf = [front[j][i], front[j][i + 1], front[j + 1][i + 1], front[j + 1][i]]
                qb = [back[j][i], back[j][i + 1], back[j + 1][i + 1], back[j + 1][i]][::-1]
                uq = [(i / nx, 1 - j / ny), ((i + 1) / nx, 1 - j / ny),
                      ((i + 1) / nx, 1 - (j + 1) / ny), (i / nx, 1 - (j + 1) / ny)]
                sl.f(qf, 'canvas_lod', C_WHITE, uq, True)
                sl.f(qb, 'canvas_back_lod', C_WHITE, uq[::-1], True)
        build(sl)

        sf = MB('Sail_Furled' + suf, (0, yy, mz))
        tube(sf, [(-(hw - 0.25), yy - 0.34, z), (0, yy - 0.38, z), (hw - 0.25, yy - 0.34, z)],
             [0.14, 0.23, 0.14], 5, 'paint', srgb('#e6dbbd'), mode='flat')
        build(sf)

        flg = MB('Flag' + suf, (0, top_y, mz))
        build_flag(flg, mz, top_y, fh, fl, 5, 2)
        build(flg)

    total = sum(OBJS[n][1] for n in OBJS)
    print('brigantine_lod: %d triangles, %d objects' % (total, len(OBJS)))
    assert total < 2500, 'LOD exceeded 2500 triangles: %d' % total
    path = os.path.join(outdir, 'ship', 'brigantine_lod.glb')
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', export_yup=True, export_apply=False,
        export_vertex_color='MATERIAL', export_all_vertex_colors=False,
        export_cameras=False, export_lights=False, export_animations=False,
        export_extras=False, export_tangents=False,
    )
    print('wrote', path)

# ================================================================ MAIN
def main():
    argv = sys.argv
    outdir = argv[-1] if '--' in argv else os.path.join(os.getcwd(), 'assets', 'generated')
    random.seed(SEED); np.random.seed(SEED)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    make_materials(outdir)

    # Static ship structure & decorative sub-parts are authored in their own MBs (preserving per-part RNG)
    # and batched into one `Hull` MeshInstance3D so Godot draws 1 surface per static material across all shadow cascades.
    hull = MB('Hull'); build_hull(hull)
    decks = MB('Decks'); build_decks(decks); hull.merge(decks)
    rails = MB('Rails'); build_rails(rails); hull.merge(rails)
    inter = MB('Interior'); build_interior(inter); hull.merge(inter)

    mast = MB('Mast')
    with xf(mast, T(0, 0, MAST_Z)):
        build_mainmast(mast)
    with xf(mast, T(0, 0, MAST_FORE_Z)):
        build_foremast(mast)
    build_bowsprit(mast)
    hull.merge(mast)

    rig = MB('Rigging'); build_rigging(rig); hull.merge(rig)
    fig = MB('Figurehead', (0, 2.3, -9.8)); build_figurehead(fig); hull.merge(fig); empty_anchor('Figurehead', fig.origin)

    # Mainmast Yard, Sail, Flag
    yard = MB('Yard', (0, YARD_Y, MAST_Z)); build_yard(yard, MAST_Z, YARD_Y, YARD_FWD, YARD_HALF); build(yard)
    sail = MB('Sail', (0, YARD_Y, MAST_Z)); build_sail(sail, main_sail_pt, main_sail_wfn); build(sail)
    flag = MB('Flag', (0, MAST_TOP - 0.12, MAST_Z)); build_flag(flag, MAST_Z, MAST_TOP - 0.12, 1.25, 3.6); build(flag)

    # Foremast Yard_Fore, Sail_Fore, Flag_Fore
    yard_f = MB('Yard_Fore', (0, YARD_FORE_Y, MAST_FORE_Z))
    build_yard(yard_f, MAST_FORE_Z, YARD_FORE_Y, YARD_FORE_FWD, YARD_FORE_HALF); build(yard_f)
    sail_f = MB('Sail_Fore', (0, YARD_FORE_Y, MAST_FORE_Z))
    build_sail(sail_f, fore_sail_pt, fore_sail_wfn); build(sail_f)
    flag_f = MB('Flag_Fore', (0, MAST_FORE_TOP - 0.10, MAST_FORE_Z))
    build_flag(flag_f, MAST_FORE_Z, MAST_FORE_TOP - 0.10, 0.96, 2.65); build(flag_f)

    # Helm Wheel, Rudder, Capstan, Anchor
    hz = STATIONS['Station_Helm'][0][2]
    o = (0, QDECK_Y + 0.95, hz); wheel = MB('Wheel', o); build_wheel(wheel, o); build(wheel)
    o = (0, 0, Z_STERN - 0.08); rud = MB('Rudder', o); build_rudder(rud, o); build(rud)
    o = STATIONS['Station_Anchor'][0]; cap = MB('Capstan', o); build_capstan(cap, o); build(cap)
    o = (2.06, ytop(-7.2) - 0.45, -7.2); anc = MB('Anchor', o); build_anchor(anc, o); build(anc)

    # Four deck cannons (2 per broadside): fore at z = -2.4, aft at z = +1.4
    cannon_specs = (
        ('Cannon_Starboard', 1, 0, -2.4, 1.84, 'PowderKeg_Starboard'),
        ('Cannon_Port', -1, 180, -2.4, 1.84, 'PowderKeg_Port'),
        ('Cannon_Starboard_Aft', 1, 0, 1.4, 1.90, None),
        ('Cannon_Port_Aft', -1, 180, 1.4, 1.90, None),
    )
    for name, sg, yaw, cz, cx, keg_name in cannon_specs:
        o = Vector((sg * cx, DECK_Y, cz))
        c = MB(name, o, seed=1, yaw=yaw - 90); build_cannon(c, o, yaw); build(c)  # object -Z = muzzle
        ob = o + R('Y', yaw).to_3x3() @ Vector(CANNON_TRUNNION)
        cb = MB(name + '_Barrel', ob, seed=1, yaw=yaw - 90, parent=c); build_cannon_barrel(cb, o, yaw); build(cb)
        if keg_name:
            k = MB(keg_name, (sg * 1.86, DECK_Y, cz - 0.95)); build_powder_keg(k, k.origin); hull.merge(k)

    extras(hull)

    # Five standard lanterns (Stern, Mast, Hold, Hold_Fore, Helm)
    yts = ytop(Z_STERN); zts = zstern(yts) - 0.02
    for name, c, s, hang in (
        ('Lantern_Stern', (0, yts + 1.65, zts), 1.65, False),
        ('Lantern_Mast', (0, 3.65, MAST_Z + 0.56), 1.0, True),
        ('Lantern_Hold', (0, 1.62, 5.2), 1.0, True),
        ('Lantern_Hold_Fore', (0.56, 0.62, -4.3), 0.95, True),
    ):
        l = MB(name, c); build_lantern(l, c, s, hang)
        if name == 'Lantern_Stern':
            tube(l, [(0, yts + 0.10, zts), (0, yts + 1.28, zts)], 0.048, 6, 'iron', C_IRON)
            cbox(l, (0, yts + 0.48, zts), (0.22, 0.96, 0.17), 'wood', C_CREAM, 0.03, (0, 1, 0))
        elif name == 'Lantern_Mast':
            cbox(l, (0, c[1] + 0.42, MAST_Z + 0.44), (0.05, 0.05, 0.38), 'iron', C_IRON, 0.01)
        elif name == 'Lantern_Hold':
            tube(l, [(0, c[1] + 0.42, c[2]), (0, QDECK_Y - 0.10, c[2])], 0.013, 4, 'iron', C_IRON)
        else:
            cbox(l, (0.42, c[1] + 0.38, c[2]), (0.34, 0.05, 0.05), 'iron', C_IRON, 0.01)
        hull.merge(l); empty_anchor(name, c)

    c = (-0.40, QDECK_Y + 1.38, hz - 0.30); l = MB('Lantern_Helm', c); build_lantern(l, c, 0.62, False)
    tube(l, [(-0.16, QDECK_Y + 1.02, hz - 0.30), (-0.40, QDECK_Y + 1.07, hz - 0.30), (-0.40, QDECK_Y + 1.25, hz - 0.30)],
         0.019, 5, 'iron', C_IRON)
    with xf(l, T(-0.40, QDECK_Y + 1.08, hz - 0.30)):
        lathe(l, [(0, -0.03), (0.036, -0.03), (0.036, 0.03), (0, 0.03)], 8, 'brass', C_BRASS)
    hull.merge(l); empty_anchor('Lantern_Helm', c)

    # Sail-control winches & deck bucket
    for name, key, band in (('Winch_SailLength', 'Station_SailLength', C_INDIGO),
                            ('Winch_SailAngle', 'Station_SailAngle', C_TEAL)):
        o = STATIONS[key][0]; o = (o[0] * 0.955, o[1], o[2]); w = MB(name, o); build_winch(w, o, band); hull.merge(w)

    o = (-1.92, DECK_Y, -4.35); bd = MB('Bucket_Deck', o); build_bucket(bd, o)
    rope_coil(bd, (-1.92, DECK_Y, -4.82), 0.18, 3)
    rp, _ = rail_frame(s_of_z(-4.35))
    tube(bd, [(-1.92, DECK_Y + 0.44, -4.33), (-2.05, DECK_Y + 0.62, -4.40),
              (-(rp.x - 0.10), rp.y + 0.12, -4.46), (-(rp.x - 0.22), DECK_Y + 0.42, -4.72),
              (-1.95, DECK_Y + 0.14, -4.82)], 0.015, 4, 'rope', C_ROPE)
    hull.merge(bd); empty_anchor('Bucket_Deck', o)

    mt = MB('MapTable', STATIONS['Station_MapTable'][0]); build_map_table(mt); hull.merge(mt); empty_anchor('MapTable', mt.origin)
    pd = MB('Props_Deck'); build_props_deck(pd); hull.merge(pd)
    ph = MB('Props_Hold'); build_props_hold(ph); hull.merge(ph)
    build(hull)

    build_collision()

    # Verify strict standing rigging clearance for BOTH yards over +-1.2 rad trim!
    gaps = rig_clearance()
    for label, g in gaps.items():
        print('%s yard to standing rigging, smallest gap over +-1.2 rad trim: %.3f m' % (label, g))
        assert g > 0.05, '%s yard fouls standing rigging (%.3f m)' % (label, g)

    # Rope attachment helpers & unit ropes for mainmast + foremast
    bp, _ = rail_frame(s_of_z(6.2))
    ya_z = MAST_Z - YARD_FWD
    ya_fz = MAST_FORE_Z - YARD_FORE_FWD
    bp_f, _ = rail_frame(s_of_z(2.1))
    sp_f_x = hull_b(-1.35, DECK_Y) - TH - 0.16
    marks = {
        # Standard SHIP_ART.md mainmast rope empties
        'Clew_Port': (main_sail_pt(-1, 1), 'Sail', (0, YARD_Y, MAST_Z)),
        'Clew_Starboard': (main_sail_pt(1, 1), 'Sail', (0, YARD_Y, MAST_Z)),
        'Yardarm_Port': (Vector((-YARD_HALF, YARD_Y, ya_z)), 'Yard', (0, YARD_Y, MAST_Z)),
        'Yardarm_Starboard': (Vector((YARD_HALF, YARD_Y, ya_z)), 'Yard', (0, YARD_Y, MAST_Z)),
        'SheetPoint_Port': (Vector((-2.25, DECK_Y + 0.62, 2.55)), None, None),
        'SheetPoint_Starboard': (Vector((2.25, DECK_Y + 0.62, 2.55)), None, None),
        'BracePoint_Port': (Vector((-(bp.x + 0.24), bp.y + 0.90, bp.z - 0.15)), None, None),
        'BracePoint_Starboard': (Vector((bp.x + 0.24, bp.y + 0.90, bp.z - 0.15)), None, None),
        'AnchorCablePoint': (Vector((2.06, ytop(-7.2) + 0.10, -7.2)), None, None),
        # Foremast rope empties
        'Clew_Fore_Port': (fore_sail_pt(-1, 1), 'Sail_Fore', (0, YARD_FORE_Y, MAST_FORE_Z)),
        'Clew_Fore_Starboard': (fore_sail_pt(1, 1), 'Sail_Fore', (0, YARD_FORE_Y, MAST_FORE_Z)),
        'Yardarm_Fore_Port': (Vector((-YARD_FORE_HALF, YARD_FORE_Y, ya_fz)), 'Yard_Fore', (0, YARD_FORE_Y, MAST_FORE_Z)),
        'Yardarm_Fore_Starboard': (Vector((YARD_FORE_HALF, YARD_FORE_Y, ya_fz)), 'Yard_Fore', (0, YARD_FORE_Y, MAST_FORE_Z)),
        'SheetPoint_Fore_Port': (Vector((-sp_f_x, DECK_Y + 0.78, -1.35)), None, None),
        'SheetPoint_Fore_Starboard': (Vector((sp_f_x, DECK_Y + 0.78, -1.35)), None, None),
        'BracePoint_Fore_Port': (Vector((-(bp_f.x - 0.07), bp_f.y + 0.12, bp_f.z)), None, None),
        'BracePoint_Fore_Starboard': (Vector((bp_f.x - 0.07, bp_f.y + 0.12, bp_f.z)), None, None),
    }
    for name, (p, par, par_org) in marks.items():
        e = bpy.data.objects.new(name, None); e.empty_display_size = 0.2
        if par:
            e.parent = OBJS[par][0]
            e.location = conv(p - Vector(par_org))
        else:
            e.location = conv(p)
        bpy.context.scene.collection.objects.link(e)

    for side in ('Port', 'Starboard'):
        rope_object('Rope_Sheet_' + side, marks['SheetPoint_' + side][0], marks['Clew_' + side][0])
        rope_object('Rope_Brace_' + side, marks['BracePoint_' + side][0], marks['Yardarm_' + side][0])
        rope_object('Rope_Sheet_Fore_' + side, marks['SheetPoint_Fore_' + side][0], marks['Clew_Fore_' + side][0])
        rope_object('Rope_Brace_Fore_' + side, marks['BracePoint_Fore_' + side][0], marks['Yardarm_Fore_' + side][0])

    for name, (p, yaw) in STATIONS.items():
        e = bpy.data.objects.new(name, None); e.empty_display_size = 0.3
        e.location = conv(p); e.rotation_euler = (0, 0, radians(yaw))
        bpy.context.scene.collection.objects.link(e)

    total = 0
    for n in OBJS:
        if not n.startswith(('col_', 'mask_')):
            total += OBJS[n][1]; print('  %-24s %6d tris' % (n, OBJS[n][1]))
    print('brigantine: %d visual triangles, %d objects, %d collision pieces' % (
        total,
        len([n for n in OBJS if not n.startswith('col_')]),
        len([n for n in OBJS if n.startswith('col_')]),
    ))
    os.makedirs(os.path.join(outdir, 'ship'), exist_ok=True)
    path = os.path.join(outdir, 'ship', 'brigantine.glb')
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', export_yup=True, export_apply=False,
        export_vertex_color='MATERIAL', export_all_vertex_colors=False,
        export_cameras=False, export_lights=False, export_animations=False,
        export_extras=False, export_tangents=True,
    )
    print('wrote', path)
    build_lod(outdir)

main()
