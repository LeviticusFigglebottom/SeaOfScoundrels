# Sea of Scoundrels: procedural sloop generator.
# Usage: blender --background --factory-startup --python tools/blender/gen_sloop.py -- <outdir>
# Writes <outdir>/ship/sloop.glb. Deterministic (seeded). Everything is built in *game*
# coordinates (Godot: -Z bow, +Y up, +X starboard, metres) and converted to Blender's Z-up
# frame only when the meshes are created, so numbers here match docs/ARCHITECTURE.md.
import bpy, bmesh, sys, os, math, random
import numpy as np
from contextlib import contextmanager
from math import sin, cos, pi, sqrt, atan2, radians, ceil, floor
from mathutils import Vector, Matrix

SEED = 1717
# ---------------------------------------------------------------- spec constants
DECK_Y = 1.1          # main deck
QDECK_Y = 2.0         # quarterdeck (aft of QDECK_Z)
QDECK_Z = 3.0
HOLD_Y = -0.6         # hold floor (one constant: stairs, table, props and collision follow it)
MAST_Z = -1.0
YARD_Y = 9.0
MAST_TOP = DECK_Y + 14.0
TH = 0.16             # hull plank thickness
STATIONS = {
    "Station_Helm": ((0, 2.0, 5.2), 0),
    "Station_SailLength": ((-1.9, 1.1, 0.5), 0),
    "Station_SailAngle": ((1.9, 1.1, 0.5), 0),
    "Station_Anchor": ((0, 1.1, -4.6), 0),
    "Station_CannonPort": ((-2.0, 1.1, -1.5), 90),        # yaw so that -Z faces -X
    "Station_CannonStarboard": ((2.0, 1.1, -1.5), -90),   # -Z faces +X
    "Station_MapTable": ((0, -0.6, 2.5), 0),
    "Station_Ladder_Port": ((-2.3, 0, 2.0), 0),
    "Station_Ladder_Starboard": ((2.3, 0, 2.0), 0),
}
GAPS = [(-1.95, -1.05), (1.55, 2.45)]   # z ranges cut out of the bulwark: gun ports, ladders
HATCH = (-0.6, 0.6, -0.6, 1.4)           # x0, x1, z0, z1 hole in the main deck

# ---------------------------------------------------------------- colour
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

C_HULL = srgb('#b06e3c'); C_DECK = srgb('#d2a468'); C_DARK = srgb('#6e4428'); C_INNER = srgb('#946238')
C_TAR = srgb('#2d2622'); C_CREAM = srgb('#f0dfb2'); C_RED = srgb('#c9281e'); C_TEAL = srgb('#1c8088')
C_GOLD = srgb('#e9ae2c'); C_IRON = srgb('#30313a'); C_ROPE = srgb('#cdb07c'); C_ROPE_D = srgb('#5c4731')
C_WHITE = (1, 1, 1); C_GLASS = srgb('#ffc061'); C_BRASS = srgb('#e2b04a'); C_BLACK = srgb('#15120f')

SU, SV = 1 / 1.8, 1 / 0.9     # wood texture tiling: metres per tile along / across the grain

# ---------------------------------------------------------------- transforms (game coords)
def T(x, y=None, z=None):
    return Matrix.Translation(Vector(x) if y is None else Vector((x, y, z)))

def R(axis, deg):
    return Matrix.Rotation(radians(deg), 4, axis)

def S(x, y=None, z=None):
    if y is None: y = z = x
    return Matrix.Diagonal((x, y, z, 1.0))

M_ZY = Matrix(((0, 1, 0, 0), (0, 0, 1, 0), (1, 0, 0, 0), (0, 0, 0, 1)))  # local (x,y,z) -> world (y,z,x): prism poly (z,y) extruded along x
M_Y2Z = R('X', 90)     # local +Y axis -> world +Z
M_Y2X = R('Z', -90)    # local +Y axis -> world +X

def newell(pts):
    n = Vector((0, 0, 0))
    for i in range(len(pts)):
        a = pts[i]; b = pts[(i + 1) % len(pts)]
        n.x += (a.y - b.y) * (a.z + b.z); n.y += (a.z - b.z) * (a.x + b.x); n.z += (a.x - b.x) * (a.y + b.y)
    return n

def smooth01(t):
    t = max(0.0, min(1.0, t)); return t * t * (3 - 2 * t)

# ---------------------------------------------------------------- mesh builder
class MB:
    def __init__(self, name, origin=(0, 0, 0), seed=0):
        self.name = name; self.origin = Vector(origin)
        self.verts = []; self.faces = []; self.fmat = []; self.fsm = []; self.fcol = []; self.fuv = []
        self.stack = [Matrix.Identity(4)]; self.flip = False
        self.rng = random.Random(SEED * 7919 + seed + sum(ord(c) for c in name))
        self.off = (0.0, 0.0)

    def push(self, M):
        self.stack.append(self.stack[-1] @ M)
        self.flip = self.stack[-1].to_3x3().determinant() < 0

    def pop(self):
        self.stack.pop(); self.flip = self.stack[-1].to_3x3().determinant() < 0

    def newoff(self):
        self.off = (self.rng.random(), self.rng.random()); return self.off

    def v(self, p):
        self.verts.append(self.stack[-1] @ Vector(p)); return len(self.verts) - 1

    def f(self, idx, mat, col, uvs, smooth=False):
        if len(set(idx)) < 3: return
        if self.flip:
            idx = idx[::-1]; uvs = uvs[::-1]
        self.faces.append(tuple(idx)); self.fmat.append(mat); self.fsm.append(smooth)
        self.fcol.append(col); self.fuv.append(uvs)

    def fp(self, pts, mat, col, grain=None, inside=None):
        """Flat polygon with its own verts and planar wood-grain UVs. `inside` orients it outward."""
        pts = [Vector(p) for p in pts]
        n = newell(pts)
        if n.length < 1e-10: return
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

@contextmanager
def xf(mb, M):
    mb.push(M)
    try: yield
    finally: mb.pop()

# ---------------------------------------------------------------- primitives
def cbox(mb, c, size, mat, col, ch=0.015, grain=None, M=None, skip=()):
    """Chamfered box centred at c. grain defaults to the longest axis. skip: set of '+x','-y'.. faces to omit."""
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
            p[a] = s * h[a]; p[b] = s1 * (h[b] - ch); p[cc] = s2 * (h[cc] - ch); return Vector(p)
        for a in range(3):
            for s in (-1, 1):
                if (('+' if s > 0 else '-') + names[a]) in skip: continue
                mb.fp([fv(a, s, -1, -1), fv(a, s, 1, -1), fv(a, s, 1, 1), fv(a, s, -1, 1)], mat, col, grain, O)
        if ch > 1e-5:
            dk = mul(col, 0.86)
            def on(a, sa, b, sb, sc):   # vert of face (a,sa) nearest face (b,sb), third-axis sign sc
                cc = 3 - a - b
                p = [0, 0, 0]; p[a] = sa * h[a]; p[b] = sb * (h[b] - ch); p[cc] = sc * (h[cc] - ch); return Vector(p)
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
    """Hexahedron from 8 points: bottom loop 0-3, top loop 4-7."""
    p = [Vector(q) for q in p]; c = sum(p, Vector()) / 8; mb.newoff()
    for q in ((0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
        mb.fp([p[i] for i in q], mat, col, grain, c)

def loft(mb, secs, mat, col, closed=True, caps=(True, True), mode='flat', ecols=None, scols=None, flip=None, grain_caps=None):
    """Connect consecutive sections (lists of points). mode: flat | len (smooth along, hard across) | smooth."""
    secs = [[Vector(p) for p in s] for s in secs]
    n = len(secs); k = len(secs[0])
    cents = [sum(s, Vector()) / k for s in secs]
    L = [0.0]
    for i in range(1, n): L.append(L[-1] + (cents[i] - cents[i - 1]).length)
    ne = k if closed else k - 1
    W = []
    for s in secs:
        w = [0.0]
        for j in range(1, k + 1): w.append(w[-1] + (s[j % k] - s[j - 1]).length)
        W.append(w)
    if flip is None:
        flip = False; done = False
        for i in range(n - 1):
            for j in range(ne):
                q = [secs[i][j], secs[i][(j + 1) % k], secs[i + 1][(j + 1) % k], secs[i + 1][j]]
                nn = newell(q)
                qc = sum(q, Vector()) / 4; cc = (cents[i] + cents[i + 1]) / 2
                if nn.length > 1e-9 and (qc - cc).length > 1e-6:
                    flip = nn.dot(qc - cc) < 0; done = True; break
            if done: break
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
            if shared: idx = [ids[i][j], ids[i][j1], ids[i + 1][j1], ids[i + 1][j]]
            else: idx = [e0[i], e1[i], e1[i + 1], e0[i + 1]]
            uvs = [uv(i, j), uv(i, j + 1), uv(i + 1, j + 1), uv(i + 1, j)]
            c = scols[i] if scols else (ecols[j] if ecols else col)
            if flip: idx = idx[::-1]; uvs = uvs[::-1]
            # drop repeated positions (degenerate quads at collapsed ends)
            keep = []; kuv = []
            for a, b in zip(idx, uvs):
                if all((mb.verts[a] - mb.verts[q]).length > 1e-7 for q in keep):
                    keep.append(a); kuv.append(b)
            if len(keep) >= 3: mb.f(keep, mat, c, kuv, sm)
    g = grain_caps
    if closed and caps[0] and n > 1:
        mb.fp(secs[0], mat, scols[0] if scols else (ecols[0] if ecols else col), g or (cents[1] - cents[0]), cents[1])
    if closed and caps[1] and n > 1:
        mb.fp(secs[-1], mat, scols[-2] if scols else (ecols[0] if ecols else col), g or (cents[-1] - cents[-2]), cents[-2])

def lathe(mb, prof, segs, mat, col, smooth=True, sp=False, colfn=None, axial=True, inside=False):
    """Revolve profile [(r, y)] about local +Y. Profile order bottom-centre -> out -> up -> in faces outward."""
    o = mb.newoff()
    rmax = max(r for r, _ in prof)
    pl = [0.0]
    for i in range(1, len(prof)):
        pl.append(pl[-1] + sqrt((prof[i][0] - prof[i - 1][0]) ** 2 + (prof[i][1] - prof[i - 1][1]) ** 2))
    def ring(r, y):
        if r < 1e-6: return [mb.v((0, y, 0))] * segs
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
        if (r0 < 1e-6 and r1 < 1e-6) or (abs(r0 - r1) < 1e-9 and abs(y0 - y1) < 1e-9): continue
        a = shared[i] if sp else ring(r0, y0); b = shared[i + 1] if sp else ring(r1, y1)
        for k in range(segs):
            k1 = (k + 1) % segs
            idx = [a[k], b[k], b[k1], a[k1]]; uvs = [uv(i, k), uv(i + 1, k), uv(i + 1, k + 1), uv(i, k + 1)]
            if r0 < 1e-6: idx = idx[:3]; uvs = uvs[:3]
            elif r1 < 1e-6: idx = [idx[0], idx[1], idx[3]]; uvs = [uvs[0], uvs[1], uvs[3]]
            if inside: idx = idx[::-1]; uvs = uvs[::-1]
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
    with xf(mb, X): lathe(mb, prof, segs, mat, col, True, True)

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
        if not out or abs(q[0] - out[-1][0]) + abs(q[1] - out[-1][1]) > eps: out.append(q)
    if len(out) > 1 and abs(out[0][0] - out[-1][0]) + abs(out[0][1] - out[-1][1]) <= eps: out.pop()
    res = []
    for i in range(len(out)):
        a = out[i - 1]; b = out[i]; c = out[(i + 1) % len(out)]
        if abs((b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])) > 1e-7: res.append(b)
    return res

def clip_half(p, a, b, c):
    """Keep the part of polygon p where a*x + b*z <= c."""
    out = []
    for i in range(len(p)):
        s = p[i]; e = p[(i + 1) % len(p)]
        ds = a * s[0] + b * s[1] - c; de = a * e[0] + b * e[1] - c
        if ds <= 0: out.append(s)
        if (ds < 0 < de) or (de < 0 < ds):
            t = ds / (ds - de); out.append((s[0] + (e[0] - s[0]) * t, s[1] + (e[1] - s[1]) * t))
    return out

def clip_rect(p, x0, x1, z0, z1):
    for a, b, c in ((-1, 0, -x0), (1, 0, x1), (0, -1, -z0), (0, 1, z1)):
        p = clip_half(p, a, b, c)
        if len(p) < 3: return []
    p = poly_clean(p)
    return p if len(p) >= 3 and abs(poly_area(p)) > 1e-4 else []

def inset_convex(p, d):
    if poly_area(p) < 0: p = p[::-1]
    n = len(p); lines = []
    for i in range(n):
        a = p[i]; b = p[(i + 1) % n]
        dx, dz = b[0] - a[0], b[1] - a[1]; l = sqrt(dx * dx + dz * dz)
        nx, nz = -dz / l, dx / l       # inward normal for CCW
        lines.append((a[0] + nx * d, a[1] + nz * d, dx / l, dz / l))
    out = []
    for i in range(n):
        x1, z1, dx1, dz1 = lines[i - 1]; x2, z2, dx2, dz2 = lines[i]
        den = dx1 * dz2 - dz1 * dx2
        if abs(den) < 1e-5: out.append((x2, z2)); continue
        t = ((x2 - x1) * dz2 - (z2 - z1) * dx2) / den
        out.append((x1 + dx1 * t, z1 + dz1 * t))
    if poly_area(out) <= 1e-5: return None
    for i in range(n):
        a = p[i]; b = p[(i + 1) % n]; c = out[i]; e = out[(i + 1) % n]
        if (b[0] - a[0]) * (e[0] - c[0]) + (b[1] - a[1]) * (e[1] - c[1]) <= 0: return None
    return out

def prism(mb, poly, y0, y1, mat, col, ch=0.0, grain=(0, 0, 1), bottom=True):
    """Extrude convex polygon [(x,z)] from y0 to y1, optional chamfer on the top edge."""
    poly = poly_clean(poly)
    if len(poly) < 3: return
    if poly_area(poly) < 0: poly = poly[::-1]
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
            mb.fp([(poly[i][0], ys, poly[i][1]), (poly[j][0], ys, poly[j][1]), (top[j][0], y1, top[j][1]), (top[i][0], y1, top[i][1])], mat, dk, grain, C)
    for i in range(n):
        j = (i + 1) % n
        mb.fp([(poly[i][0], y0, poly[i][1]), (poly[j][0], y0, poly[j][1]), (poly[j][0], ys, poly[j][1]), (poly[i][0], ys, poly[i][1])], mat, col, grain, C)
    if bottom: mb.fp([(x, y0, z) for x, z in poly], mat, col, grain, C)

# ---------------------------------------------------------------- hull form
NS = 48                                     # samples along the hull
YS = [-1.0, -0.74, -0.48, -0.22, 0.05, 0.30, 0.55, 0.80, 1.02, 1.24, 1.50, 1.75]   # strake edges at midship
VS = [(y + 1.0) / 2.75 for y in YS]
YT = -0.15                                  # bottom of the transom
_SB = []
for _i in range(241):
    _t = _i / 240.0
    _b = ((1 - _t) ** 3, 3 * (1 - _t) ** 2 * _t, 3 * (1 - _t) * _t * _t, _t ** 3)
    _SB.append((-1.0 * _b[0] - 1.0 * _b[1] + 0.0 * _b[2] + 1.1 * _b[3], -3.4 * _b[0] - 5.7 * _b[1] - 6.4 * _b[2] - 6.5 * _b[3]))

def zstem(y):
    """Stem contour: z of the bow profile at height y."""
    if y <= -1.0: return -3.4
    if y >= 1.1:
        d = y - 1.1; return -6.5 - 0.09 * d - 0.12 * d * d
    lo, hi = 0, 240
    while hi - lo > 1:
        m = (lo + hi) // 2
        if _SB[m][0] < y: lo = m
        else: hi = m
    (y0, z0), (y1, z1) = _SB[lo], _SB[hi]
    return z0 + (z1 - z0) * (y - y0) / max(y1 - y0, 1e-9)

def zstern(y):
    return 6.5 + 0.2 * (max(y, YT) - 1.1)

def tumble(y):
    return 1.0 if y <= 0.9 else 1.0 - 0.05 * ((y - 0.9) / 1.1) ** 1.3

def bmid(y):
    h = max(0.0, min(1.0, (y + 1.0) / 1.9))
    return 2.2 * (1 - (1 - h) ** 2.2) ** (1 / 2.6) * tumble(y)

def wtrans(y):
    if y <= YT: return 0.0
    h = min(1.0, (y - YT) / (1.1 - YT))
    return 1.62 * (1 - (1 - h) ** 2.4) ** (1 / 2.2) * tumble(y)

def hull_b(z, y):
    """Half breadth of the outer hull surface at (z, y)."""
    bm = bmid(y)
    if z >= 0:
        t = min(1.0, z / zstern(y)); return bm - (bm - wtrans(y)) * t ** 2.2
    t = min(1.0, z / zstem(y)); return bm * max(0.0, 1 - t ** 2.4) ** 0.7

def ytop(z):
    """Sheer: top of the hull planking."""
    if z < 0: return 1.75 + 0.6 * (-z / 6.5) ** 2
    return 1.75 + 0.75 * smooth01((z - 1.0) / 3.5) + 0.1 * (z / 6.5) ** 2

def umap(s):
    return 1.0 - (1.0 - min(max(s / NS, 0.0), 1.0)) ** 1.4

def hull_pt(u, v):
    yt = ytop(6.5 - 13.0 * u)
    y = -1.0 + v * (yt + 1.0)
    zs = zstern(y); z = zs + (zstem(y) - zs) * u
    return Vector((hull_b(z, y), y, z))

def hull_n(u, v):
    e = 2e-3
    pu = hull_pt(min(u + e, 1.0), v) - hull_pt(max(u - e, 0.0), v)
    pv = hull_pt(u, v + e) - hull_pt(u, max(v - e, 0.0))
    n = pu.cross(pv)
    if n.length < 1e-12: return Vector((1, 0, 0))
    return n.normalized()

def v_of_y(u, y):
    return (y + 1.0) / (ytop(6.5 - 13.0 * u) + 1.0)

def s_of_z(z, v=1.0):
    lo, hi = 0.0, float(NS)
    for _ in range(40):
        m = (lo + hi) / 2
        if hull_pt(umap(m), v).z > z: lo = m
        else: hi = m
    return (lo + hi) / 2

def inner_half(z, y):
    """Half breadth of the inside face of the planking at (z, y)."""
    v = 0.5; s = 0.0
    for _ in range(3):
        s = s_of_z(z, v); v = v_of_y(umap(s), y)
    n = hull_n(umap(s), v)
    return hull_b(z, y) - TH / max(n.x, 0.3)

def hull_in(u, v, d=TH):
    p = hull_pt(u, v) - hull_n(u, v) * d
    p.x = max(p.x, 0.0); return p

# ---------------------------------------------------------------- textures and materials
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
    rgba = np.ones((h, w, 4), dtype=np.float32); rgba[..., :3] = np.clip(arr, 0, 1)
    img = bpy.data.images.new(name, w, h, alpha=False)
    img.pixels.foreach_set(rgba.ravel()); img.file_format = 'PNG'; img.pack()
    return img

def tex_wood(rs):
    w = h = 256
    warp = tile_noise(rs, w, h, 3, 4) * 0.08
    yy = (np.arange(h)[:, None] / h + warp) % 1.0
    lines = np.zeros((h, w))
    for freq, amp in ((9, 0.5), (23, 0.3), (51, 0.2)):
        ph = rs.rand() * 6.28
        lines += amp * (0.5 + 0.5 * np.sin(yy * 2 * pi * freq + ph + tile_noise(rs, w, h, 2, 6) * 3.0))
    streak = tile_noise(rs, w, h, 3, 48) * 0.6 + tile_noise(rs, w, h, 6, 96) * 0.4
    val = 0.80 + 0.12 * lines + 0.10 * (streak - 0.5) * 2
    dark = np.clip((0.30 - streak) * 6, 0, 1) * 0.16          # occasional dark grain lines
    val = val - dark + (tile_noise(rs, w, h, 64, 64) - 0.5) * 0.04
    return np.stack([val, val * 0.975, val * 0.93], axis=-1)

def sun_mask(X, Y):
    """Original 'winking sun' emblem in unit coordinates (disc radius 1). Returns bool mask of paint."""
    r = np.hypot(X, Y); th = np.arctan2(Y, X)
    disc = r < 1.0
    tri = np.abs(((th / (2 * pi) * 12 + 0.5) % 1.0) - 0.5) * 2
    rays = (r > 1.14) & (tri < 0.72) & (r < 1.2 + 0.62 * (1 - tri / 0.72))
    eye = np.hypot(X + 0.38, Y - 0.24) < 0.14
    wink = (np.abs(np.hypot(X - 0.38, Y - 0.10) - 0.21) < 0.055) & (Y > 0.13)
    grin = (np.abs(np.hypot(X, Y - 0.12) - 0.62) < 0.085) & (Y < -0.14)
    tooth = (X > 0.10) & (X < 0.27) & (Y < -0.3)
    c, s = cos(0.35), sin(0.35)
    bx = (X + 0.40) * c + (Y - 0.52) * s; by = -(X + 0.40) * s + (Y - 0.52) * c
    brow = (np.abs(bx) < 0.2) & (np.abs(by) < 0.045)
    return (disc | rays) & ~(eye | wink | (grin & ~tooth) | brow)

def tex_sail(rs):
    W = 512; ss = 2; w = W * ss
    yy, xx = np.mgrid[0:w, 0:w] / float(w)
    weave = 0.975 + 0.02 * np.sin(xx * 2 * pi * 128) * np.sin(yy * 2 * pi * 128) + 0.03 * (tile_noise(rs, w, w, 256, 256) - 0.5)
    blot = 0.90 + 0.10 * tile_noise(rs, w, w, 5, 5)
    base = np.array([0.95, 0.89, 0.74])
    img = base[None, None, :] * (weave * blot)[..., None]
    img *= (1.0 - 0.10 * np.clip((0.22 - yy) / 0.22, 0, 1))[..., None]           # grubby foot
    img *= (1.0 - 0.06 * np.clip((np.abs(xx - 0.5) - 0.42) / 0.08, 0, 1))[..., None]
    def rect(x0, x1, y0, y1): return (xx > x0) & (xx < x1) & (yy > y0) & (yy < y1)
    for (x0, x1, y0, y1, tint) in ((0.07, 0.22, 0.60, 0.78, (0.90, 0.93, 0.97)), (0.70, 0.90, 0.10, 0.27, (1.0, 0.93, 0.80)), (0.76, 0.87, 0.66, 0.80, (0.86, 0.84, 0.80)), (0.20, 0.32, 0.08, 0.19, (0.98, 0.90, 0.84))):
        m = rect(x0, x1, y0, y1); img[m] *= np.array(tint)
        edge = rect(x0 - 0.006, x1 + 0.006, y0 - 0.006, y1 + 0.006) & ~rect(x0 + 0.004, x1 - 0.004, y0 + 0.004, y1 - 0.004)
        dash = (np.sin((xx + yy) * 2 * pi * 60) > -0.2)
        img[edge & dash] *= 0.55
    for kx in range(1, 6):                                                      # panel seams
        d = np.abs(xx - kx / 6.0)
        img[d < 0.0030] *= 0.74
        img[(d > 0.006) & (d < 0.008) & (np.sin(yy * 2 * pi * 70) > 0)] *= 0.86
    for ry in (0.30, 0.74):                                                     # reef bands
        d = np.abs(yy - ry)
        img[d < 0.008] *= 0.86
        img[(d < 0.03) & (yy < ry) & (np.abs(((xx * 24) % 1.0) - 0.5) < 0.05)] *= 0.62
    R0 = 0.185
    X = (xx - 0.5) / R0; Y = (yy - 0.50) / R0
    edge_n = (tile_noise(rs, w, w, 40, 40) - 0.5) * 0.06
    m = sun_mask(X * (1 + edge_n), Y * (1 + edge_n))
    paint = np.array([0.80, 0.17, 0.12]) * (0.84 + 0.2 * tile_noise(rs, w, w, 9, 9))[..., None] * weave[..., None]
    img[m] = paint[m]
    img = img.reshape(W, ss, W, ss, 3).mean(axis=(1, 3))
    return img

def tex_flag(rs):
    W, H, ss = 256, 128, 2; w, h = W * ss, H * ss
    yy, xx = np.mgrid[0:h, 0:w]; xx = xx / float(w); yy = yy / float(h)
    img = np.array([0.80, 0.15, 0.11])[None, None, :] * (0.88 + 0.12 * tile_noise(rs, w, h, 6, 4))[..., None]
    img[(xx < 0.035)] = (0.93, 0.86, 0.68)
    X = (xx - 0.40) * 2.0 / 0.29; Y = (yy - 0.5) / 0.29
    m = sun_mask(X, Y)
    img[m] = (0.97, 0.90, 0.70)
    return img.reshape(H, ss, W, ss, 3).mean(axis=(1, 3))

MATS = {}
def make_materials():
    rs = np.random.RandomState(SEED)
    wood = make_image('sloop_wood', tex_wood(rs)); sail = make_image('sloop_sail', tex_sail(rs)); flag = make_image('sloop_flag', tex_flag(rs))
    def mk(name, tex=None, rough=0.8, metal=0.0, emit=0.0, two=False):
        m = bpy.data.materials.new(name); m.use_nodes = True
        nt = m.node_tree; b = nt.nodes['Principled BSDF']
        b.inputs['Roughness'].default_value = rough; b.inputs['Metallic'].default_value = metal
        ca = nt.nodes.new('ShaderNodeVertexColor'); ca.layer_name = 'Color'
        if tex is not None:
            t = nt.nodes.new('ShaderNodeTexImage'); t.image = tex
            mx = nt.nodes.new('ShaderNodeMix'); mx.data_type = 'RGBA'; mx.blend_type = 'MULTIPLY'; mx.inputs[0].default_value = 1.0
            nt.links.new(t.outputs['Color'], mx.inputs[6]); nt.links.new(ca.outputs['Color'], mx.inputs[7])
            nt.links.new(mx.outputs[2], b.inputs['Base Color'])
        else:
            nt.links.new(ca.outputs['Color'], b.inputs['Base Color'])
        if emit > 0:
            b.inputs['Emission Color'].default_value = (1.0, 0.62, 0.22, 1); b.inputs['Emission Strength'].default_value = emit
        m.use_backface_culling = not two
        MATS[name] = m
    mk('wood', wood, 0.82)
    mk('paint', None, 0.6)           # painted or plain surfaces (vertex colour only)
    mk('rope', None, 0.95)
    mk('iron', None, 0.5, 0.55)
    mk('brass', None, 0.32, 0.85)
    mk('glass', None, 0.25, 0.0, 2.2)
    mk('canvas', sail, 0.95, two=True)
    mk('flag', flag, 0.9, two=True)
    mk('col', None, 1.0)

# ---------------------------------------------------------------- object creation
def conv(p):
    return (p[0], -p[2], p[1])

OBJS = {}
def build(mb):
    me = bpy.data.meshes.new(mb.name)
    me.from_pydata([conv(v - mb.origin) for v in mb.verts], [], mb.faces)
    names = sorted(set(mb.fmat))
    for n in names: me.materials.append(MATS[n])
    mi = {n: i for i, n in enumerate(names)}
    uvl = me.uv_layers.new(name='UVMap')
    ca = me.color_attributes.new('Color', 'FLOAT_COLOR', 'CORNER')
    uvs = []; cols = []
    for fi, f in enumerate(mb.faces):
        c = mb.fcol[fi]
        for k in range(len(f)):
            uvs.extend(mb.fuv[fi][k])
            cc = c[k] if isinstance(c, list) else c
            cols.extend((cc[0], cc[1], cc[2], 1.0))
    uvl.data.foreach_set('uv', uvs); ca.data.foreach_set('color', cols)
    me.polygons.foreach_set('material_index', [mi[m] for m in mb.fmat])
    me.polygons.foreach_set('use_smooth', mb.fsm)
    me.update()
    ob = bpy.data.objects.new(mb.name, me); ob.location = conv(mb.origin)
    bpy.context.scene.collection.objects.link(ob)
    OBJS[mb.name] = (ob, mb.tris())
    return ob

def col_piece(name, pts):
    """Convex collision mesh from a point cloud (game coords)."""
    bm = bmesh.new()
    seen = set()
    for p in pts:
        k = tuple(round(c, 4) for c in conv(p))
        if k not in seen: seen.add(k); bm.verts.new(k)
    bm.verts.index_update()
    r = bmesh.ops.convex_hull(bm, input=bm.verts)
    junk = list({e for e in r['geom_interior'] + r['geom_unused'] if isinstance(e, bmesh.types.BMVert)})
    junk.sort(key=lambda e: e.index)
    if junk: bmesh.ops.delete(bm, geom=junk, context='VERTS')
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    me.materials.append(MATS['col'])
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    OBJS[name] = (ob, 0)

# ================================================================ SHIP PARTS
def strake_look(j):
    """(outer colour, extra outward offset) for strake j."""
    if YS[j + 1] <= 0.06: return C_TAR, 0.0
    if j == 4: return C_CREAM, 0.012
    if j == 7: return C_RED, 0.05
    if j == 10: return C_TEAL, 0.012
    return C_HULL, 0.0

def gap_ranges():
    out = []
    for (z0, z1) in GAPS:
        out.append((s_of_z(z1), s_of_z(z0)))      # s grows toward the bow (z falls)
    return sorted(out)

def top_intervals(s_end=NS):
    iv = []; a = 0.0
    for (g0, g1) in gap_ranges():
        iv.append((a, g0)); a = g1
    iv.append((a, float(s_end)))
    return iv

def hull_plank(mb, j, s0, s1, col, extra, inner_col):
    v0, v1 = VS[j], VS[j + 1]; dv = 0.02 / 2.75; b = 0.022
    ss = [s0, s0 + 0.07] + [float(s) for s in range(int(ceil(s0 + 0.35)), int(floor(s1 - 0.35)) + 1)] + [s1 - 0.07, s1]
    secs = []
    for i, s in enumerate(ss):
        u = umap(s); end = i in (0, len(ss) - 1)
        n0 = hull_n(u, v0); n1 = hull_n(u, v1); p0 = hull_pt(u, v0); p1 = hull_pt(u, v1)
        e = -b if end else extra
        A = p0 - n0 * b; D = p1 - n1 * b
        Bp = hull_pt(u, v0 + dv) + hull_n(u, v0 + dv) * e; Cp = hull_pt(u, v1 - dv) + hull_n(u, v1 - dv) * e
        E = p1 - n1 * TH; F = p0 - n0 * TH
        for q in (A, Bp, Cp, D, E, F): q.x = max(q.x, 0.0)
        secs.append([A, Bp, Cp, D, E, F])
    dk = mul(col, 0.55)
    loft(mb, secs, 'wood', col, True, (True, True), 'len', ecols=[dk, col, dk, mul(col, 0.9), inner_col, inner_col])

def build_hull(mb):
    rng = mb.rng
    for side in (1, -1):
        with xf(mb, S(side, 1, 1)):
            for j in range(len(YS) - 1):
                base, extra = strake_look(j)
                ivs = top_intervals(NS - 0.05) if j >= 9 else [(0.0, NS - 0.05)]
                for (a, bnd) in ivs:
                    cuts = [a]; s = a - rng.uniform(0, 6)
                    while True:
                        s += rng.uniform(7, 13)
                        if s > bnd - 3: break
                        if s > a + 3: cuts.append(float(round(s)))
                    cuts.append(bnd)
                    for k in range(len(cuts) - 1):
                        amt = 0.05 if base in (C_RED, C_TEAL, C_CREAM) else 0.13
                        inner = jit(C_INNER if j < 8 else C_HULL, rng, 0.10)
                        hull_plank(mb, j, cuts[k], cuts[k + 1], jit(base, rng, amt), extra, inner)
    # keel + stem as one swept timber
    path = [(6.25, -1.0), (2.0, -1.0), (-2.0, -1.0), (-3.4, -1.0)]
    for i in range(8, 241, 8): path.append((_SB[i][1], _SB[i][0]))
    for y in (1.4, 1.7, 2.0, 2.3, 2.52): path.append((zstem(y), y))
    secs = []; scols = []
    for i, (z, y) in enumerate(path):
        a = path[max(i - 1, 0)]; b = path[min(i + 1, len(path) - 1)]
        t = Vector((b[0] - a[0], b[1] - a[1])).normalized(); n = Vector((-t.y, t.x))
        do = 0.2 if y < -0.9 else 0.24; di = 0.1; w = 0.13; c = 0.035
        o = Vector((0, y + n.y * do, z + n.x * do)); o2 = Vector((0, y + n.y * (do - c), z + n.x * (do - c))); q = Vector((0, y - n.y * di, z - n.x * di))
        secs.append([q + Vector((-w, 0, 0)), q + Vector((w, 0, 0)), o2 + Vector((w, 0, 0)), o + Vector((w - c, 0, 0)), o + Vector((-(w - c), 0, 0)), o2 + Vector((-w, 0, 0))])
        scols.append(C_TAR if y < 0.12 else C_CREAM)
    loft(mb, secs, 'wood', C_TAR, True, (True, True), 'flat', scols=scols)
    box2(mb, (-0.13, -1.2, 6.12), (0.13, -0.05, 6.4), 'wood', C_TAR, 0.03)       # sternpost
    # ---- transom
    a = math.degrees(math.atan(0.2))
    def tplank(y0, y1, col, extra=0.0, th=0.14):
        secs = []
        for sg in (-1, 0, 1):
            def P(y, dz): return Vector((sg * wtrans(y), y, zstern(y) + dz))
            d = min(0.02, (y1 - y0) * 0.2)
            secs.append([P(y0, -0.02), P(y0 + d, extra), P(y1 - d, extra), P(y1, -0.02), P(y1, -th), P(y0, -th)])
        inner = jit(C_INNER, rng, 0.08)
        loft(mb, secs, 'wood', col, True, (True, True), 'flat', ecols=[mul(col, 0.55), col, mul(col, 0.55), col, inner, inner])
    yts = ytop(6.5)
    for (y0, y1, c, ex) in ((YT, 0.12, C_TAR, 0), (0.12, 0.36, C_HULL, 0), (0.36, 0.54, C_CREAM, 0.03), (0.54, 1.46, C_TEAL, 0), (1.46, 1.6, C_CREAM, 0.03),
                            (1.6, 1.9, C_HULL, 0), (1.9, 2.2, C_HULL, 0), (2.2, yts - 0.14, C_HULL, 0), (yts - 0.14, yts, C_RED, 0.03)):
        tplank(y0, y1, jit(c, rng, 0.06), ex)
    with xf(mb, T(0, 1.1, 6.5) @ R('X', a)):
        ca = cos(radians(a))
        def ly(y): return (y - 1.1) / ca
        for wx in (-0.86, 0.0, 0.86):                          # stern windows (opaque glowing panes, both faces)
            y0, y1 = ly(0.64), ly(1.36); hw = 0.33
            for zf in (0.02, -0.16):
                cbox(mb, (wx, (y0 + y1) / 2, zf), (hw * 2, y1 - y0, 0.03), 'glass', C_GLASS, 0.0)
            for zf, dz in ((0.035, 0.07), (-0.175, 0.05)):
                for (cx, cy, sx, sy) in ((wx, y0, hw * 2 + 0.12, 0.09), (wx, y1, hw * 2 + 0.12, 0.09), (wx - hw, (y0 + y1) / 2, 0.09, y1 - y0), (wx + hw, (y0 + y1) / 2, 0.09, y1 - y0),
                                         (wx, (y0 + y1) / 2, 0.05, y1 - y0), (wx, (y0 + y1) / 2, hw * 2, 0.05)):
                    cbox(mb, (cx, cy, zf), (sx, sy, dz), 'wood', C_GOLD if zf > 0 else C_DARK, 0.015)
        # the winking sun, carved and gilded
        sy = ly(2.03)
        with xf(mb, T(0, sy, 0.0) @ M_Y2Z):
            lathe(mb, [(0, 0), (0.30, 0), (0.30, 0.05), (0.24, 0.09), (0, 0.10)], 16, 'paint', C_GOLD)
        for k in range(12):
            with xf(mb, T(0, sy, 0.03) @ R('Z', k * 30 + 15)):
                mb.newoff()
                mb.fp([(-0.06, 0.33, 0.0), (0.06, 0.33, 0.0), (0, 0.5, 0.0)], 'paint', mul(C_GOLD, 0.8), None, (0, 0.4, -1))
                mb.fp([(-0.06, 0.33, 0.0), (0, 0.38, 0.05), (0, 0.5, 0.0)], 'paint', C_GOLD, None, (0, 0.4, -1))
                mb.fp([(0.06, 0.33, 0.0), (0, 0.38, 0.05), (0, 0.5, 0.0)], 'paint', mul(C_GOLD, 1.1), None, (0, 0.4, -1))
                mb.fp([(-0.06, 0.33, 0.0), (0, 0.38, 0.05), (0.06, 0.33, 0.0)], 'paint', C_GOLD, None, (0, 0.6, -1))
        ellipsoid(mb, (-0.1, sy + 0.07, 0.1), (0.04, 0.045, 0.02), 'paint', C_BLACK, 8, 4)
        cbox(mb, (0.11, sy + 0.06, 0.1), (0.1, 0.03, 0.02), 'paint', C_BLACK, 0.005)
        tube(mb, [(0.17 * cos(radians(t)), sy + 0.02 + 0.17 * sin(radians(t)), 0.095) for t in range(-155, -24, 26)], 0.018, 4, 'paint', C_BLACK)
    for sg in (-1, 1):                                          # quarter trim covering the hull/transom seam
        pts = [Vector((sg * (wtrans(y) + 0.01), y, zstern(y) + 0.0)) for y in [YT + 0.12 + (yts - YT - 0.12) * i / 9 for i in range(10)]]
        secs = []
        for p in pts:
            secs.append([p + Vector((-0.08 * sg, 0, -0.1)), p + Vector((0.05 * sg, 0, -0.1)), p + Vector((0.05 * sg, 0, 0.04)), p + Vector((0.02 * sg, 0, 0.07)), p + Vector((-0.08 * sg, 0, 0.07))])
        loft(mb, secs, 'wood', C_GOLD, True, (True, True), 'flat', scols=[C_TAR if p.y < 0.1 else C_GOLD for p in pts])
    # ladder rungs on the hull sides at the ladder stations
    for sg in (-1, 1):
        for y in (-0.3, 0.0, 0.3, 0.6, 0.9, 1.2):
            x = hull_b(2.0, y)
            cbox(mb, (sg * (x + 0.07), y, 2.0), (0.14, 0.07, 0.62), 'wood', C_CREAM if y > 0.1 else C_DARK, 0.02)
        for dz in (-0.33, 0.33):
            pts = [(sg * (hull_b(2.0, y) + 0.03), y, 2.0 + dz) for y in (-0.4, 0.0, 0.4, 0.8, 1.26)]
            tube(mb, pts, 0.035, 5, 'wood', C_DARK)
    # catheads
    for sg in (-1, 1):
        cbox(mb, (sg * 1.3, ytop(-5.1) + 0.2, -5.1), (0.9, 0.2, 0.24), 'wood', C_DARK, 0.03)
        cbox(mb, (sg * 1.77, ytop(-5.1) + 0.2, -5.1), (0.06, 0.24, 0.28), 'wood', C_RED, 0.02)

def deck_outline(yb, yt, z0, z1, n=44, pw=1.7, margin=0.07, inner=False):
    zs = [z0 + (z1 - z0) * (i / n) ** pw for i in range(n + 1)]
    if inner:   # sloping hull: reach just past the inside face of the planking, never through the outside
        right = [(max(min(inner_half(z, yt) + 0.05, hull_b(z, yb) - 0.02), 0.0), z) for z in zs]
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
                    if hz0 > a: nv.append((a, min(b, hz0)))
                    if hz1 < b: nv.append((max(a, hz1), b))
                iv = [(a, b) for a, b in nv if b - a > 1e-3]
        for (a, b) in iv:
            strip = clip_rect(poly, xa, xb, a, b)
            if not strip: continue
            zmin = min(q[1] for q in strip); zmax = max(q[1] for q in strip)
            z = zmin - rng.uniform(0, 2.5); cuts = []
            while z < zmax:
                z += rng.uniform(2.0, 3.8)
                if zmin + 0.5 < z < zmax - 0.5: cuts.append(z)
            bounds = [zmin] + cuts + [zmax]
            for i in range(len(bounds) - 1):
                p = clip_rect(strip, xa, xb, bounds[i], bounds[i + 1])
                if p: prism(mb, p, y1 - th, y1, 'wood', colfn(), 0.014)

def build_decks(mb):
    rng = mb.rng
    def deck_col():
        c = jit(C_DECK, rng, 0.12, 0.03)
        return mul(c, 0.8) if rng.random() < 0.12 else c
    main = deck_outline(DECK_Y - 0.1, DECK_Y, -6.52, QDECK_Z + 0.1)
    deck_planks(mb, main, -6.6, QDECK_Z + 0.1, DECK_Y, 0.1, 0.24, [HATCH], deck_col)
    zq1 = zstern(QDECK_Y) - 0.1
    quarter = deck_outline(QDECK_Y - 0.1, QDECK_Y, QDECK_Z - 0.06, zq1, 12, 1.0)
    deck_planks(mb, quarter, QDECK_Z - 0.06, zq1, QDECK_Y, 0.1, 0.24, [], deck_col)
    # waterways (margin planks) hide the stepped plank ends against the bulwark
    for (yd, z0, z1, n) in ((DECK_Y, -6.5, QDECK_Z, 40), (QDECK_Y, QDECK_Z, zq1, 10)):
        for sg in (-1, 1):
            secs = []
            for i in range(n + 1):
                z = z0 + (z1 - z0) * (i / n) ** (1.6 if yd == DECK_Y else 1.0)
                h = max(min(hull_b(z, yd), hull_b(z, yd + 0.05)) - 0.1, 0.0)
                a = max(h - 0.26, 0.0)
                secs.append([(sg * a, yd - 0.02, z), (sg * h, yd - 0.02, z), (sg * h, yd + 0.04, z), (sg * (a + 0.03 if a > 0 else 0), yd + 0.04, z)])
            loft(mb, secs, 'wood', jit(C_DARK, rng, 0.05), True, (True, True), 'len')
    # breasthook: chunky knee filling the bow tip
    bh = [q for q in deck_outline(DECK_Y, 2.2, -6.62, -5.95, 8, 1.0, 0.1)]
    prism(mb, bh, DECK_Y, ytop(-6.3) - 0.02, 'wood', C_DARK, 0.03, (1, 0, 0))
    # ---- quarterdeck break: bulkhead, beam, stairs
    hb = min(hull_b(QDECK_Z + 0.05, DECK_Y), hull_b(QDECK_Z + 0.05, QDECK_Y)) - 0.08
    nb = 12
    for i in range(nb):
        x0 = -hb + 2 * hb * i / nb; x1 = -hb + 2 * hb * (i + 1) / nb
        cbox(mb, ((x0 + x1) / 2, (DECK_Y + QDECK_Y - 0.1) / 2 - 0.05, QDECK_Z + 0.06), (x1 - x0, QDECK_Y - 0.1 - DECK_Y + 0.1, 0.1), 'wood', jit(C_TEAL, rng, 0.07), 0.014, (0, 1, 0))
    cbox(mb, (0, QDECK_Y - 0.11, QDECK_Z - 0.01), (2 * hb, 0.16, 0.2), 'wood', C_RED, 0.03)
    cbox(mb, (0, DECK_Y - 0.17, QDECK_Z + 0.04), (2 * hull_b(QDECK_Z, 0.9) - 0.3, 0.14, 0.16), 'wood', C_DARK, 0.02)   # beam under the deck edge
    sw = 0.62; z0 = 1.95; run = (QDECK_Z - z0) / 3.0; rise = (QDECK_Y - DECK_Y) / 4.0
    for i in range(3):
        top = DECK_Y + rise * (i + 1)
        box2(mb, (-sw + 0.04, DECK_Y - 0.02, z0 + run * i + 0.03), (sw - 0.04, top - 0.06, QDECK_Z + 0.02), 'wood', jit(C_DARK, rng, 0.06), 0.01, (1, 0, 0))
        box2(mb, (-sw, top - 0.07, z0 + run * i - 0.03), (sw, top, z0 + run * (i + 1) + 0.02), 'wood', deck_col(), 0.02, (1, 0, 0))
    for sg in (-1, 1):
        with xf(mb, T(sg * (sw + 0.035), 0, 0) @ M_ZY):
            prism(mb, [(z0 - 0.12, DECK_Y), (QDECK_Z, DECK_Y), (QDECK_Z, QDECK_Y + 0.06), (QDECK_Z - 0.16, QDECK_Y + 0.06), (z0 - 0.12, DECK_Y + 0.2)], -0.035, 0.035, 'wood', C_RED, 0.0, (1, 0, 0.8))
    # ---- hatch: coaming on three sides (open aft where the stairs start) and the stairs down
    hx0, hx1, hz0, hz1 = HATCH
    for sg in (-1, 1):
        cbox(mb, (sg * (hx1 + 0.05), DECK_Y + 0.04, (hz0 + hz1) / 2 - 0.05), (0.16, 0.34, hz1 - hz0 + 0.16), 'wood', C_RED, 0.025)
    cbox(mb, (0, DECK_Y + 0.04, hz0 - 0.05), (hx1 - hx0 + 0.2, 0.34, 0.16), 'wood', C_RED, 0.025)
    cbox(mb, (0, DECK_Y - 0.06, hz1 + 0.05), (hx1 - hx0 + 0.25, 0.12, 0.1), 'wood', C_DARK, 0.015)
    zt, zb = hz1 - 0.05, hz0 + 0.05; nst = 8; H = DECK_Y - HOLD_Y
    for sg in (-1, 1):
        x = sg * (hx1 - 0.07)
        d = Vector((0, -H, zb - zt)); nrm = Vector((0, d.z, H)).normalized() * 0.13
        a = Vector((x, DECK_Y, zt + 0.02)); b = Vector((x, HOLD_Y, zb + 0.02))
        hexa(mb, [a - nrm + Vector((-0.035, 0, 0)), a - nrm + Vector((0.035, 0, 0)), b - nrm + Vector((0.035, 0, 0)), b - nrm + Vector((-0.035, 0, 0)),
                  a + nrm + Vector((-0.035, 0, 0)), a + nrm + Vector((0.035, 0, 0)), b + nrm + Vector((0.035, 0, 0)), b + nrm + Vector((-0.035, 0, 0))], 'wood', jit(C_DARK, rng, 0.05), d)
    for i in range(1, nst):
        y = DECK_Y - H * i / nst; z = zt + (zb - zt) * i / nst
        cbox(mb, (0, y - 0.03, z + 0.02), (hx1 - hx0 - 0.2, 0.06, 0.27), 'wood', deck_col(), 0.015, (1, 0, 0))
    # ---- helm pedestal + binnacle (static; the Wheel object spins in front of it)
    hz = STATIONS['Station_Helm'][0][2]
    cbox(mb, (0, QDECK_Y + 0.05, hz - 0.3), (0.56, 0.1, 0.5), 'wood', C_DARK, 0.025)
    hexa(mb, [(-0.2, QDECK_Y + 0.1, hz - 0.48), (0.2, QDECK_Y + 0.1, hz - 0.48), (0.2, QDECK_Y + 0.1, hz - 0.12), (-0.2, QDECK_Y + 0.1, hz - 0.12),
              (-0.14, QDECK_Y + 1.12, hz - 0.42), (0.14, QDECK_Y + 1.12, hz - 0.42), (0.14, QDECK_Y + 1.12, hz - 0.14), (-0.14, QDECK_Y + 1.12, hz - 0.14)], 'wood', C_RED, (0, 1, 0))
    cbox(mb, (0, QDECK_Y + 1.15, hz - 0.28), (0.36, 0.07, 0.36), 'wood', C_DARK, 0.02)
    with xf(mb, T(0, QDECK_Y + 1.18, hz - 0.28)):
        lathe(mb, [(0, 0), (0.13, 0), (0.13, 0.04), (0.11, 0.09), (0.06, 0.13), (0, 0.14)], 10, 'brass', C_BRASS)
    with xf(mb, T(0, QDECK_Y + 0.95, hz - 0.14) @ M_Y2Z):
        cyl(mb, 0.045, 0, 0.12, 8, 'iron', C_IRON)

def rail_frame(s):
    """Point on the hull top edge and horizontal outward normal."""
    u = umap(s); p = hull_pt(u, 1.0); n = hull_n(u, 1.0); nh = Vector((n.x, 0, n.z))
    if nh.length < 1e-6: nh = Vector((1, 0, 0))
    return p, nh.normalized()

def baluster(mb, base, h, col):
    with xf(mb, T(base)):
        lathe(mb, [(0.055, 0), (0.055, 0.05), (0.035, 0.08), (0.06, h * 0.33), (0.03, h * 0.62), (0.045, h - 0.07), (0.05, h)], 8, 'wood', col, True)

def build_rails(mb):
    rng = mb.rng
    sq = s_of_z(QDECK_Z)
    for sg in (-1, 1):
        with xf(mb, S(sg, 1, 1)):
            # cap rail on the bulwark, broken at the gaps
            for (a, b) in top_intervals(NS - 1.3):
                ss = [a] + [float(s) for s in range(int(ceil(a + 0.2)), int(floor(b - 0.2)) + 1)] + [b]
                secs = []
                for s in ss:
                    p, nh = rail_frame(s); c = p - nh * (TH / 2 - 0.01); up = Vector((0, 1, 0)); w = 0.15
                    secs.append([c - nh * w - up * 0.01, c + nh * w - up * 0.01, c + nh * w + up * 0.06, c + nh * (w - 0.035) + up * 0.1, c - nh * (w - 0.035) + up * 0.1, c - nh * w + up * 0.06])
                loft(mb, secs, 'wood', jit(C_DARK, rng, 0.05), True, (True, True), 'len')
            # stanchions at each gap edge
            for (g0, g1) in gap_ranges():
                for s, dz in ((g0, 0.1), (g1, -0.1)):
                    p, nh = rail_frame(s); sill = hull_pt(umap(s), VS[9]).y
                    c = p - nh * (TH / 2)
                    box2(mb, (c.x - 0.14, sill - 0.02, c.z + dz - 0.1), (c.x + 0.14, p.y + 0.3, c.z + dz + 0.1), 'wood', C_CREAM, 0.03, (0, 1, 0))
                    cbox(mb, (c.x, p.y + 0.33, c.z + dz), (0.34, 0.07, 0.26), 'wood', C_RED, 0.02)
            # timberheads along the main deck rail
            for s in range(int(sq) + 3, NS - 3, 3):
                z = hull_pt(umap(s), 1.0).z
                if any(z0 - 0.35 < z < z1 + 0.35 for z0, z1 in GAPS): continue
                p, nh = rail_frame(s); c = p - nh * (TH / 2)
                cbox(mb, (c.x, p.y + 0.19, c.z), (0.17, 0.2, 0.17), 'wood', C_CREAM, 0.035, (0, 1, 0))
            # quarterdeck: open balustrade on top of the cap rail
            n = 9; secs = []
            for i in range(n + 1):
                s = sq * (1 - i / n) if i < n else 0.0
                s = sq - (sq - 0.0) * i / n
                p, nh = rail_frame(s); c = p - nh * (TH / 2 - 0.01); base = Vector((c.x, p.y + 0.1, c.z))
                hgt = 0.62
                if i in (0, n):
                    cbox(mb, (base.x, base.y + (hgt + 0.16) / 2, base.z), (0.17, hgt + 0.16, 0.17), 'wood', C_CREAM, 0.03, (0, 1, 0))
                    with xf(mb, T(base.x, base.y + hgt + 0.16, base.z)):
                        lathe(mb, [(0, 0), (0.07, 0.02), (0.09, 0.09), (0.06, 0.16), (0, 0.18)], 8, 'brass', C_BRASS, True, True)
                else:
                    baluster(mb, base, hgt, C_CREAM)
                    q0, n0 = rail_frame(s + sq / n / 2); c0 = q0 - n0 * (TH / 2 - 0.01)
                    baluster(mb, (c0.x, q0.y + 0.1, c0.z), hgt, C_CREAM)
                top = base + Vector((0, hgt, 0)); w = 0.1
                secs.append([top - nh * w, top + nh * w, top + nh * w + Vector((0, 0.05, 0)), top + nh * (w - 0.03) + Vector((0, 0.08, 0)), top - nh * (w - 0.03) + Vector((0, 0.08, 0)), top - nh * w + Vector((0, 0.05, 0))])
            loft(mb, secs, 'wood', C_RED, True, (True, True), 'len')
    # front rail of the quarterdeck, either side of the stairs
    hq = min(hull_b(QDECK_Z, QDECK_Y), hull_b(QDECK_Z, QDECK_Y + 0.9)) - 0.3
    for sg in (-1, 1):
        xs = [0.72 + (hq - 0.72) * i / 3 for i in range(4)]
        for i, x in enumerate(xs):
            if i == 0:
                cbox(mb, (sg * x, QDECK_Y + 0.46, QDECK_Z + 0.02), (0.17, 0.92, 0.17), 'wood', C_CREAM, 0.03, (0, 1, 0))
                with xf(mb, T(sg * x, QDECK_Y + 0.92, QDECK_Z + 0.02)):
                    lathe(mb, [(0, 0), (0.07, 0.02), (0.09, 0.09), (0.06, 0.16), (0, 0.18)], 8, 'brass', C_BRASS, True, True)
            else:
                baluster(mb, (sg * x, QDECK_Y, QDECK_Z + 0.02), 0.78, C_CREAM)
            if i < 3: baluster(mb, (sg * (x + (xs[1] - xs[0]) / 2), QDECK_Y, QDECK_Z + 0.02), 0.78, C_CREAM)
        cbox(mb, (sg * (0.72 + hq + 0.12) / 2, QDECK_Y + 0.82, QDECK_Z + 0.02), (hq + 0.12 - 0.72, 0.09, 0.2), 'wood', C_RED, 0.03)
    # taffrail across the stern
    yt = ytop(6.5); zt = zstern(yt) - 0.07; wt = wtrans(yt) - 0.02
    cbox(mb, (0, yt + 0.05, zt), (2 * wt + 0.3, 0.1, 0.3), 'wood', C_DARK, 0.03)
    nb = 9
    for i in range(1, nb):
        x = -wt + 2 * wt * i / nb
        if abs(x) < 0.01: continue
        baluster(mb, (x, yt + 0.1, zt + 0.03), 0.62, C_CREAM)
    yr = yt + 0.72; zr = zstern(yr) - 0.07
    cbox(mb, (0, yr + 0.04, zt + 0.05), (2 * wt + 0.22, 0.08, 0.2), 'wood', C_RED, 0.03)

def build_interior(mb):
    rng = mb.rng
    zf0, zf1 = -4.3, 5.75
    def dcol(): return jit(mul(C_INNER, 0.9), rng, 0.12)
    floor_poly = deck_outline(HOLD_Y - 0.06, HOLD_Y, zf0, zf1, 30, 1.0, inner=True)
    deck_planks(mb, floor_poly, zf0, zf1, HOLD_Y, 0.06, 0.3, [], dcol)
    # ribs (frames) on the inside of the planking
    s = s_of_z(5.6, 0.5)
    send = s_of_z(-4.1, 0.5)
    while s < send:
        u = umap(s); z = hull_pt(u, 0.5).z
        ytopr = (QDECK_Y - 0.1) if z > QDECK_Z + 0.1 else (DECK_Y - 0.1)
        ys = [HOLD_Y - 0.1 + (ytopr - HOLD_Y + 0.1) * i / 7 for i in range(8)]
        tu = (hull_pt(min(u + 0.01, 1), 0.5) - hull_pt(u - 0.01, 0.5)).normalized() * 0.075
        for sg in (-1, 1):
            secs = []
            for y in ys:
                v = v_of_y(u, y); n = hull_n(u, v); p = hull_pt(u, v) - n * (TH - 0.01); q = p - n * 0.13
                secs.append([p - tu, p + tu, q + tu, q - tu])
            with xf(mb, S(sg, 1, 1)):
                loft(mb, secs, 'wood', jit(C_DARK, rng, 0.1), True, (True, True), 'flat')
        s += 2.4 if z > -1 else 3.4
    # forward bulkhead of the hold
    z = zf0; nb = 10
    hbk = hull_b(z, DECK_Y - 0.1) - 0.1
    def ysec(x):
        lo, hi = -1.0, 0.9
        for _ in range(30):
            m = (lo + hi) / 2
            if hull_b(z, m) - 0.1 < abs(x): lo = m
            else: hi = m
        return max(hi, HOLD_Y - 0.05)
    for i in range(nb):
        x0 = -hbk + 2 * hbk * i / nb; x1 = -hbk + 2 * hbk * (i + 1) / nb
        y0a, y0b = ysec(x0), ysec(x1); yt = DECK_Y - 0.1
        hexa(mb, [(x0, y0a, z - 0.05), (x1, y0b, z - 0.05), (x1, y0b, z + 0.05), (x0, y0a, z + 0.05), (x0, yt, z - 0.05), (x1, yt, z - 0.05), (x1, yt, z + 0.05), (x0, yt, z + 0.05)], 'wood', dcol(), (0, 1, 0))
    # beams under the quarterdeck (there is headroom there)
    for zb in (3.9, 4.8, 5.7):
        hbm = hull_b(zb, QDECK_Y - 0.2) - 0.12
        cbox(mb, (0, QDECK_Y - 0.17, zb), (2 * hbm, 0.14, 0.16), 'wood', jit(C_DARK, rng, 0.08), 0.02)
    # mast step
    cbox(mb, (0, HOLD_Y + 0.09, MAST_Z), (0.9, 0.18, 0.9), 'wood', C_DARK, 0.04)

def barrel(mb, pos, r=0.3, h=0.85, M=None, band=C_IRON, tone=C_HULL):
    rng = mb.rng
    cols = [jit(tone, rng, 0.14) for _ in range(12)]
    X = T(pos) @ (M if M is not None else Matrix.Identity(4))
    with xf(mb, X):
        prof = [(0, 0.035), (0.8 * r, 0.035), (0.8 * r, 0), (0.86 * r, 0), (0.96 * r, 0.2 * h), (r, 0.5 * h), (0.96 * r, 0.8 * h), (0.86 * r, h), (0.8 * r, h), (0.8 * r, h - 0.035), (0, h - 0.035)]
        lathe(mb, prof, 12, 'wood', C_HULL, False, False, lambda i, k: mul(cols[k], 0.8 if i in (0, 9) else 1.0))
        for f, rr in ((0.07, 0.885), (0.27, 0.975), (0.73, 0.975), (0.93, 0.885)):
            y = f * h; r0 = rr * r + 0.012
            lathe(mb, [(r0 - 0.02, y - 0.03), (r0, y - 0.03), (r0, y + 0.03), (r0 - 0.02, y + 0.03)], 12, 'iron', band, False)

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
    barrel(mb, (-1.05, DECK_Y, -3.3)); barrel(mb, (-0.55, DECK_Y, -3.75), 0.27, 0.78, tone=C_DARK, band=C_BRASS)
    crate(mb, (1.0, DECK_Y, -3.5), (0.7, 0.55, 0.6), R('Y', 14)); crate(mb, (0.95, DECK_Y + 0.55, -3.52), (0.45, 0.35, 0.42), R('Y', -12), C_HULL)
    barrel(mb, (-1.5, DECK_Y, 2.72), 0.28, 0.8); crate(mb, (1.45, DECK_Y, 2.68), (0.6, 0.5, 0.5), R('Y', 4))
    rope_coil(mb, (1.25, DECK_Y, -2.55), 0.26, 3); rope_coil(mb, (-1.2, QDECK_Y, 3.6), 0.24, 3)
    barrel(mb, (1.25, QDECK_Y, 6.15), 0.25, 0.72, tone=C_DARK)
    # cannonball rack beside each gun
    for sg in (-1, 1):
        cbox(mb, (sg * 1.55, DECK_Y + 0.05, -0.75), (0.5, 0.1, 0.2), 'wood', C_DARK, 0.02)
        for i in range(3):
            ellipsoid(mb, (sg * (1.39 + 0.16 * i), DECK_Y + 0.16, -0.75), (0.075, 0.075, 0.075), 'iron', C_IRON, 8, 5)

def build_props_hold(mb):
    y = HOLD_Y
    barrel(mb, (-0.85, y, -3.6), 0.33, 0.9); barrel(mb, (-0.1, y, -3.8), 0.33, 0.9, tone=C_DARK); barrel(mb, (0.75, y, -3.55), 0.3, 0.85)
    barrel(mb, (-0.45, y + 0.9, -3.75), 0.27, 0.75, band=C_BRASS)
    barrel(mb, (1.0, y + 0.31, -2.4), 0.3, 0.85, R('Y', 20) @ R('X', 90))          # one on its side
    crate(mb, (-1.0, y, -2.4), (0.7, 0.6, 0.7), R('Y', 8)); crate(mb, (-0.95, y + 0.6, -2.42), (0.5, 0.4, 0.5), R('Y', -15), C_HULL)
    crate(mb, (0.95, y, 4.3), (0.6, 0.5, 0.55), R('Y', -6)); barrel(mb, (-0.8, y, 4.5), 0.28, 0.8)
    rope_coil(mb, (0.9, y, 0.9), 0.25, 3)
    # hammock under the quarterdeck, a touch of life
    pts = [(-1.0, 0.95, 5.2 - 0.0), (-0.5, 0.62, 5.25), (0.0, 0.52, 5.3), (0.5, 0.62, 5.25), (1.0, 0.95, 5.2)]
    secs = [[Vector(p) + Vector((0, 0.0 if i in (0, 4) else 0.1, -0.3 if i not in (0, 4) else -0.02)), Vector(p), Vector(p) + Vector((0, 0.0 if i in (0, 4) else 0.1, 0.3 if i not in (0, 4) else 0.02))] for i, p in enumerate(pts)]
    loft(mb, secs, 'canvas', C_WHITE, False, (False, False), 'smooth', flip=False)
    for f in mb.fuv[-12:]: pass

def build_map_table(mb):
    o = Vector(STATIONS['Station_MapTable'][0]); rng = mb.rng
    with xf(mb, T(o)):
        cbox(mb, (0, 0.8, 0), (1.35, 0.09, 0.9), 'wood', C_HULL, 0.025, (1, 0, 0))
        for sx in (-1, 1):
            for sz in (-1, 1):
                cbox(mb, (sx * 0.55, 0.38, sz * 0.33), (0.12, 0.76, 0.12), 'wood', C_DARK, 0.025)
            cbox(mb, (sx * 0.55, 0.2, 0), (0.08, 0.08, 0.6), 'wood', C_DARK, 0.015)
        cbox(mb, (0, 0.2, 0), (1.05, 0.07, 0.08), 'wood', C_DARK, 0.015)
        with xf(mb, T(0.05, 0.845, 0) @ R('Y', 6)):
            cbox(mb, (0, 0.008, 0), (0.95, 0.016, 0.64), 'paint', C_CREAM, 0.0)
            cbox(mb, (0, 0.005, 0), (0.99, 0.008, 0.68), 'paint', mul(C_CREAM, 0.7), 0.0)
            for (ix, iz, r, c) in ((-0.22, 0.08, 0.11, srgb('#6e9a4a')), (0.2, -0.12, 0.08, srgb('#6e9a4a')), (0.1, 0.17, 0.05, srgb('#c7a55c')), (-0.3, -0.18, 0.045, srgb('#c7a55c'))):
                poly = [(ix + r * (0.7 + 0.5 * rng.random()) * cos(a * pi / 4), iz + r * (0.7 + 0.5 * rng.random()) * sin(a * pi / 4)) for a in range(8)]
                mb.newoff(); mb.fp([(x, 0.02, z) for x, z in poly], 'paint', c, None, (ix, -1, iz))
            for a in (45, -45):
                cbox(mb, (0.22, 0.021, -0.1), (0.09, 0.004, 0.02), 'paint', C_RED, 0.0, None, R('Y', a))
            for i in range(6):
                cbox(mb, (-0.18 + i * 0.065, 0.02, 0.02 - i * 0.02), (0.03, 0.003, 0.012), 'paint', C_BLACK, 0.0, None, R('Y', 18))
        with xf(mb, T(-0.45, 0.845, -0.25)):
            lathe(mb, [(0, 0), (0.08, 0), (0.08, 0.03), (0.06, 0.04), (0, 0.04)], 10, 'brass', C_BRASS)
        with xf(mb, T(0.52, 0.845, 0.28)):                                       # candle
            lathe(mb, [(0, 0), (0.07, 0), (0.07, 0.015), (0.03, 0.02), (0.03, 0.12), (0, 0.12)], 8, 'paint', C_CREAM)
            lathe(mb, [(0, 0.12), (0.015, 0.14), (0, 0.19)], 5, 'glass', C_GLASS)

def build_mast(mb):
    D = DECK_Y
    lathe(mb, [(0, HOLD_Y), (0.3, HOLD_Y), (0.3, D + 0.02), (0.29, D + 3.0), (0.27, D + 6.0), (0.24, 10.5), (0.21, 11.75), (0.17, 11.8), (0, 11.8)], 16, 'wood', mul(C_DECK, 0.95), True, True)
    lathe(mb, [(0.3, D), (0.42, D), (0.42, D + 0.1), (0.34, D + 0.22), (0.3, D + 0.22)], 16, 'wood', C_RED)       # mast coat
    for y in (2.9, 5.4, 7.6):
        r = 0.3 - (y - D) * 0.0065
        lathe(mb, [(r - 0.01, y - 0.07), (r + 0.02, y - 0.07), (r + 0.02, y + 0.07), (r - 0.01, y + 0.07)], 16, 'iron', C_IRON)
    # topmast (doubled alongside the mast head) and truck
    with xf(mb, T(0, 0, MAST_Z - 0.0)):
        pass
    lathe(mb, [(0, 10.2), (0.15, 10.2), (0.14, 12.2), (0.09, MAST_TOP - 0.05), (0, MAST_TOP - 0.05)], 10, 'wood', mul(C_DECK, 0.9), True, True)
    lathe(mb, [(0.2, 11.72), (0.3, 11.72), (0.3, 11.9), (0.2, 11.9)], 12, 'wood', C_RED)
    with xf(mb, T(0, MAST_TOP - 0.05, 0)):
        lathe(mb, [(0, 0), (0.1, 0.02), (0.14, 0.1), (0.1, 0.19), (0, 0.22)], 10, 'brass', C_BRASS, True, True)
    # crow's nest: a big stave tub
    rng = mb.rng; cols = [jit(C_HULL, rng, 0.14) for _ in range(14)]
    y0 = 10.5
    prof = [(0.24, y0), (0.8, y0), (0.9, y0 + 0.45), (0.93, y0 + 0.9), (0.93, y0 + 0.97), (0.84, y0 + 0.97), (0.84, y0 + 0.9), (0.81, y0 + 0.45), (0.74, y0 + 0.09), (0.24, y0 + 0.09)]
    lathe(mb, prof, 14, 'wood', C_HULL, False, False, lambda i, k: mul(cols[k], 0.75 if i >= 5 else 1.0))
    for (yy, rr, c) in ((y0 + 0.14, 0.845, C_IRON), (y0 + 0.74, 0.935, C_IRON)):
        lathe(mb, [(rr - 0.02, yy - 0.035), (rr, yy - 0.035), (rr, yy + 0.035), (rr - 0.02, yy + 0.035)], 14, 'iron', c, False)
    lathe(mb, [(0.86, y0 + 0.9), (0.97, y0 + 0.9), (0.97, y0 + 1.0), (0.86, y0 + 1.0)], 14, 'wood', C_RED, False)
    for k in range(4):
        with xf(mb, R('Y', 45 + k * 90)):
            with xf(mb, M_ZY):
                prism(mb, [(0.22, y0 - 0.75), (0.34, y0 - 0.75), (0.74, y0), (0.22, y0)], -0.05, 0.05, 'wood', C_DARK, 0.0, (1, 0, 1))

def build_bowsprit(mb):
    heel = Vector((0, 2.25, -5.45)); tip = Vector((0, 3.95, -10.4))
    n = 6; path = [heel.lerp(tip, i / n) for i in range(n + 1)]
    tube(mb, path, [0.17 - 0.07 * i / n for i in range(n + 1)], 12, 'wood', mul(C_DECK, 0.95))
    d = (tip - heel).normalized()
    for f in (0.34, 0.97):
        p = heel.lerp(tip, f); r = 0.17 - 0.07 * f + 0.015
        tube(mb, [p - d * 0.06, p + d * 0.06], r, 12, 'iron' if f < 0.9 else 'brass', C_IRON if f < 0.9 else C_BRASS, mode='len')
    # bitts holding the heel
    for sg in (-1, 1):
        cbox(mb, (sg * 0.3, (DECK_Y + 2.6) / 2, -5.4), (0.2, 2.6 - DECK_Y, 0.2), 'wood', C_RED, 0.035, (0, 1, 0))
    cbox(mb, (0, 2.5, -5.4), (0.9, 0.16, 0.16), 'wood', C_DARK, 0.03)
    # gammoning rope lashing the bowsprit to the stem head
    for i in range(4):
        p = heel.lerp(tip, 0.265 + i * 0.012)
        with xf(mb, T(p) @ R('X', 71)):
            torus(mb, 0.165, 0.03, 10, 5, 'rope', C_ROPE)

def build_figurehead(mb):
    """'The Plucky Pelican': an original chunky carved pelican under the bowsprit."""
    white = srgb('#f4ead2'); beak = srgb('#f0a224'); pouch = srgb('#e8642a')
    ellipsoid(mb, (0, 1.78, -7.08), (0.33, 0.5, 0.42), 'paint', white, 12, 8, R('X', -28))             # body
    neck = [(0, 2.05, -7.22), (0, 2.22, -7.42), (0, 2.38, -7.5), (0, 2.47, -7.56)]
    tube(mb, neck, [0.2, 0.15, 0.14, 0.14], 10, 'paint', white)
    ellipsoid(mb, (0, 2.47, -7.6), (0.19, 0.185, 0.22), 'paint', white, 12, 7)                          # head
    for sg in (-1, 1):
        ellipsoid(mb, (sg * 0.3, 1.78, -6.86), (0.09, 0.4, 0.5), 'paint', C_TEAL, 10, 6, R('X', -20) @ R('Y', sg * -14))   # wings
        ellipsoid(mb, (sg * 0.36, 1.6, -6.62), (0.06, 0.2, 0.3), 'paint', C_CREAM, 8, 5, R('X', -20) @ R('Y', sg * -14))
        ellipsoid(mb, (sg * 0.16, 2.53, -7.68), (0.04, 0.05, 0.05), 'paint', C_BLACK, 8, 5)             # eyes
        ellipsoid(mb, (sg * 0.15, 2.535, -7.67), (0.045, 0.065, 0.065), 'paint', C_GOLD, 8, 5)
    # beak: long wedge with a hooked tip, and the pouch below
    top = [(0, 2.5, -7.74), (0, 2.42, -8.05), (0, 2.3, -8.36), (0, 2.2, -8.5)]
    secs = []
    for i, p in enumerate(top):
        w = (0.12, 0.1, 0.07, 0.015)[i]; hgt = (0.1, 0.085, 0.06, 0.03)[i]
        P = Vector(p); secs.append([P + Vector((-w, -hgt, 0)), P + Vector((-w * 0.6, 0.02, 0)), P + Vector((w * 0.6, 0.02, 0)), P + Vector((w, -hgt, 0))])
    loft(mb, secs, 'paint', beak, True, (True, True), 'flat')
    ellipsoid(mb, (0, 2.2, -8.06), (0.095, 0.17, 0.36), 'paint', pouch, 10, 6, R('X', 20))
    # red neckerchief
    with xf(mb, T(0, 2.12, -7.3) @ R('X', -50)):
        torus(mb, 0.19, 0.06, 12, 6, 'paint', C_RED)
    ellipsoid(mb, (0.0, 2.02, -7.5), (0.07, 0.07, 0.07), 'paint', C_RED, 8, 5)
    # gilded scroll collar where the carving meets the stem
    with xf(mb, T(0, 1.55, -6.82) @ R('X', 60)):
        torus(mb, 0.3, 0.07, 12, 6, 'paint', C_GOLD)

def shroud_pts():
    out = []
    for sg in (-1, 1):
        for k, z in enumerate((-0.72, -0.27, 0.18)):
            s = s_of_z(z); p, nh = rail_frame(s)
            bot = Vector((sg * (p.x + 0.04), p.y + 0.12, z)); top = Vector((sg * 0.2, 10.42, MAST_Z + 0.02 + 0.1 * k))
            out.append((sg, k, bot, top))
    return out

def build_rigging(mb):
    sh = shroud_pts()
    for sg, k, bot, top in sh:
        lo = bot + (top - bot).normalized() * 0.55
        tube(mb, [lo, top], 0.032, 5, 'rope', C_ROPE_D)
        for f in (0.08, 0.42):                                        # deadeyes + lanyards
            c = bot + (top - bot).normalized() * f
            with xf(mb, T(c) @ M_Y2X):
                cyl(mb, 0.085, -0.035, 0.035, 8, 'wood', C_DARK, True, 0.012)
        tube(mb, [bot + Vector((0, -0.25, 0)), lo], 0.02, 4, 'rope', C_ROPE)
    for sg in (-1, 1):                                                # ratlines
        a = [(b, t) for s, k, b, t in sh if s == sg]
        y = 2.75
        while y < 9.9:
            pts = []
            for (b, t) in a:
                f = (y - b.y) / (t.y - b.y); pts.append(b.lerp(t, f))
            tube(mb, pts, 0.017, 3, 'rope', C_ROPE, (False, False), 'flat')
            y += 0.47
    tip = Vector((0, 3.95, -10.4)); mid = Vector((0, 2.25, -5.45)).lerp(tip, 0.34)
    tube(mb, [(0, MAST_TOP - 0.35, MAST_Z - 0.08), tip + Vector((0, 0.1, 0.1))], 0.03, 5, 'rope', C_ROPE_D)       # forestay
    tube(mb, [(0, 10.35, MAST_Z - 0.25), mid + Vector((0, 0.19, 0))], 0.03, 5, 'rope', C_ROPE_D)                 # inner stay
    for sg in (-1, 1):                                                                                            # backstays
        s = 2.0; p, nh = rail_frame(s)
        tube(mb, [(sg * 0.08, MAST_TOP - 0.5, MAST_Z + 0.08), (sg * (p.x - 0.05), p.y + 0.95, p.z)], 0.028, 5, 'rope', C_ROPE_D)
    # halyard / brace falls from the two sail stations up to the mast (static; makes the stations readable)
    for sg, c in ((-1, C_ROPE), (1, C_ROPE)):
        tube(mb, [(sg * 1.83, DECK_Y + 0.62, 0.5), (sg * 0.27, 8.3, MAST_Z + 0.12)], 0.022, 4, 'rope', c)
    with xf(mb, T(0, 8.3, MAST_Z)):
        lathe(mb, [(0.25, -0.08), (0.33, -0.08), (0.33, 0.08), (0.25, 0.08)], 12, 'iron', C_IRON)

def build_yard(mb):
    y = YARD_Y; z = MAST_Z - 0.42; n = 8
    path = [(-3.25 + 6.5 * i / n, y, z) for i in range(n + 1)]
    rad = [0.075 + 0.06 * (1 - abs(2 * i / n - 1) ** 1.5) for i in range(n + 1)]
    tube(mb, path, rad, 10, 'wood', mul(C_DECK, 0.85))
    for sg in (-1, 1):
        tube(mb, [(sg * 3.19, y, z), (sg * 3.3, y, z)], 0.095, 10, 'wood', C_RED, mode='len')
        tube(mb, [(sg * 0.5, y, z), (sg * 0.62, y, z)], 0.15, 10, 'iron', C_IRON, mode='len')
    cbox(mb, (0, y, MAST_Z - 0.3), (0.42, 0.26, 0.2), 'wood', C_DARK, 0.03)
    with xf(mb, T(0, y, MAST_Z)):
        lathe(mb, [(0.26, -0.1), (0.35, -0.1), (0.35, 0.1), (0.26, 0.1)], 14, 'rope', C_ROPE)                 # parrel
    for i in range(13):                                                                                      # robands lashing the sail head
        x = -3.0 + 6.0 * i / 12
        if abs(x) < 0.7: continue
        r = 0.075 + 0.06 * (1 - abs(x / 3.25) ** 1.5) + 0.012
        tube(mb, [(x - 0.03, y, z), (x + 0.03, y, z)], r, 8, 'rope', C_ROPE, mode='len')

def sail_point(xn, yn):
    """xn -1..1 across, yn 0 (head) .. 1 (foot)."""
    head_y = YARD_Y - 0.13; foot_c = 3.35
    hw = 3.05 + 0.2 * yn
    x = xn * hw
    yfoot = foot_c + 0.4 * (1 - xn * xn)
    y = head_y + (yfoot - head_y) * yn
    belly = 1.05 * cos(xn * pi / 2) ** 0.85 * (0.10 + 0.90 * sin(pi * min(1.0, yn * 0.83)) ** 0.9)
    belly *= min(1.0, yn * 6 + 0.12)
    scallop = 0.035 * (1 - cos(xn * 6 * pi)) * min(1.0, yn * 3) * (1 if abs(xn) < 0.999 else 0)
    z = MAST_Z - 0.44 - belly - scallop
    return Vector((x, y, z))

def build_sail(mb):
    nx, ny = 24, 14
    ids = [[mb.v(sail_point(-1 + 2 * i / nx, j / ny)) for i in range(nx + 1)] for j in range(ny + 1)]
    for j in range(ny):
        for i in range(nx):
            idx = [ids[j][i], ids[j][i + 1], ids[j + 1][i + 1], ids[j + 1][i]]
            uvs = [(i / nx, 1 - j / ny), ((i + 1) / nx, 1 - j / ny), ((i + 1) / nx, 1 - (j + 1) / ny), (i / nx, 1 - (j + 1) / ny)]
            sh = [mix(C_WHITE, (0.80, 0.78, 0.74), 0.5 * abs(-1 + 2 * ii / nx) ** 3 + 0.25 * (jj / ny) ** 2) for ii, jj in ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))]
            mb.f(idx, 'canvas', sh, uvs, True)
    # bolt rope round the edge
    edge = [sail_point(-1, j / ny) for j in range(ny + 1)] + [sail_point(-1 + 2 * i / nx, 1) for i in range(1, nx + 1)] + [sail_point(1, 1 - j / ny) for j in range(1, ny + 1)]
    tube(mb, edge, 0.03, 4, 'rope', C_ROPE, (True, True), 'smooth')

def build_flag(mb):
    top = MAST_TOP - 0.12; h = 1.15; L = 2.3; nx, ny = 12, 4
    def P(i, j):
        t = i / nx; f = j / ny
        x = 0.16 * sin(t * 7.5) * t ** 0.7 + 0.05 * sin(t * 15 + f * 2)
        notch = 0.42 * (1 - abs(2 * f - 1)) * max(0.0, (t - 0.72) / 0.28)
        return Vector((x, top - f * h - 0.18 * t * t + 0.06 * sin(t * 6), MAST_Z - 0.1 - t * L * (1 - notch * 0.3) + notch * 0.0))
    ids = [[mb.v(P(i, j)) for i in range(nx + 1)] for j in range(ny + 1)]
    for j in range(ny):
        for i in range(nx):
            idx = [ids[j][i], ids[j][i + 1], ids[j + 1][i + 1], ids[j + 1][i]]
            uvs = [(i / nx, 1 - j / ny), ((i + 1) / nx, 1 - j / ny), ((i + 1) / nx, 1 - (j + 1) / ny), (i / nx, 1 - (j + 1) / ny)]
            mb.f(idx, 'flag', C_WHITE, uvs, True)

def build_wheel(mb, o):
    with xf(mb, T(o) @ M_Y2Z):
        for (r0, r1, hh, c) in ((0.40, 0.49, 0.05, C_DARK), (0.17, 0.215, 0.035, C_DARK)):
            lathe(mb, [(r0, -hh), (r1 - 0.015, -hh), (r1, -hh + 0.015), (r1, hh - 0.015), (r1 - 0.015, hh), (r0, hh), (r0, -hh)], 24, 'wood', c)
        for k in range(8):
            with xf(mb, R('Y', k * 45) @ M_Y2X):
                col = C_RED if k == 6 else C_HULL
                lathe(mb, [(0.03, 0.08), (0.04, 0.2), (0.03, 0.4), (0.045, 0.42), (0.045, 0.47), (0.028, 0.5), (0.04, 0.56), (0.047, 0.62), (0.03, 0.68), (0, 0.69)], 7, 'wood', col, True, True)
        lathe(mb, [(0, -0.09), (0.11, -0.09), (0.125, -0.05), (0.125, 0.05), (0.09, 0.1), (0.04, 0.12), (0, 0.12)], 12, 'brass', C_BRASS)
        for k in range(8):
            with xf(mb, R('Y', k * 45 + 22.5) @ T(0.445, 0.05, 0)):
                ellipsoid(mb, (0, 0, 0), (0.02, 0.012, 0.02), 'brass', C_BRASS, 6, 3)

def build_rudder(mb, o):
    with xf(mb, T(0, 0, 0) @ M_ZY):
        prism(mb, [(6.42, -1.17), (7.22, -1.17), (7.3, -0.6), (7.0, 0.05), (6.66, 0.42), (6.42, 0.42)], -0.075, 0.075, 'wood', C_HULL, 0.02, (0, 0, 1))
    for y, L in ((-0.85, 0.75), (-0.3, 0.62), (0.2, 0.36)):
        cbox(mb, (0, y, 6.4 + L / 2 - 0.04), (0.19, 0.09, L), 'iron', C_IRON, 0.012)
    cbox(mb, (0, -0.32, 6.42), (0.1, 1.7, 0.1), 'iron', C_IRON, 0.02)
    cbox(mb, (0, -0.95, 6.85), (0.16, 0.42, 0.75), 'wood', C_TAR, 0.02)

def build_capstan(mb, o):
    with xf(mb, T(o)):
        lathe(mb, [(0, 0), (0.46, 0), (0.46, 0.06), (0.4, 0.1), (0.3, 0.1)], 12, 'wood', C_DARK)
        lathe(mb, [(0.27, 0.1), (0.2, 0.42), (0.21, 0.72)], 12, 'wood', C_HULL, True, True)
        for k in range(6):
            with xf(mb, R('Y', k * 60 + 30)):
                hexa(mb, [(0.2, 0.1, -0.05), (0.38, 0.1, -0.05), (0.38, 0.1, 0.05), (0.2, 0.1, 0.05), (0.18, 0.72, -0.05), (0.27, 0.72, -0.05), (0.27, 0.72, 0.05), (0.18, 0.72, 0.05)], 'wood', C_RED, (0, 1, 0))
        lathe(mb, [(0.2, 0.72), (0.4, 0.72), (0.42, 0.76), (0.42, 0.96), (0.36, 1.02), (0.12, 1.04), (0, 1.04)], 12, 'wood', C_DARK)
        lathe(mb, [(0, 1.04), (0.14, 1.04), (0.14, 1.07), (0.06, 1.11), (0, 1.11)], 10, 'brass', C_BRASS)
        for k in range(6):
            with xf(mb, R('Y', k * 60) @ M_Y2X):
                with xf(mb, T(0, 0, 0)):
                    pass
            with xf(mb, R('Y', k * 60)):
                cbox(mb, (0.56, 0.86, 0), (0.44, 0.07, 0.07), 'wood', C_DECK, 0.015)
        lathe(mb, [(0.245, 0.3), (0.265, 0.3), (0.265, 0.52), (0.245, 0.52)], 12, 'rope', C_ROPE)

def build_anchor(mb, o):
    with xf(mb, T(o)):
        cbox(mb, (0, -0.72, 0), (0.1, 1.36, 0.1), 'iron', C_IRON, 0.025)
        with xf(mb, T(0, 0.1, 0) @ M_Y2X):
            torus(mb, 0.12, 0.03, 12, 6, 'iron', C_IRON)
        cbox(mb, (0, -0.16, 0), (1.05, 0.13, 0.13), 'wood', C_DARK, 0.03)
        for sx in (-0.38, 0.38):
            cbox(mb, (sx, -0.16, 0), (0.06, 0.16, 0.16), 'iron', C_IRON, 0.01)
        Rr = 0.6; cy = -1.42 + Rr
        for sg in (-1, 1):
            secs = []
            for i in range(7):
                t = radians(i * 13.0); w = 0.06 - 0.02 * i / 6
                c = Vector((0, cy - Rr * cos(t), sg * Rr * sin(t))); rad = Vector((0, -cos(t), sg * sin(t)))
                secs.append([c - rad * w + Vector((-w, 0, 0)), c - rad * w + Vector((w, 0, 0)), c + rad * w + Vector((w, 0, 0)), c + rad * w + Vector((-w, 0, 0))])
            loft(mb, secs, 'iron', C_IRON, True, (True, True), 'flat')
            t = radians(78); c = Vector((0, cy - Rr * cos(t), sg * Rr * sin(t)))
            tip = c + Vector((0, 0.22, sg * 0.06))
            for sx in (-1, 1):
                mb.newoff()
                mb.fp([c + Vector((sx * 0.03, -0.2, -sg * 0.16)), c + Vector((sx * 0.03, -0.05, sg * 0.13)), tip], 'iron', mul(C_IRON, 1.2), None, c + Vector((0, 0, 0)))
            mb.fp([c + Vector((-0.03, -0.2, -sg * 0.16)), c + Vector((0.03, -0.2, -sg * 0.16)), tip], 'iron', C_IRON, None, c)
            mb.fp([c + Vector((-0.03, -0.05, sg * 0.13)), c + Vector((0.03, -0.05, sg * 0.13)), tip], 'iron', C_IRON, None, c)
            mb.fp([c + Vector((-0.03, -0.2, -sg * 0.16)), c + Vector((0.03, -0.2, -sg * 0.16)), c + Vector((0.03, -0.05, sg * 0.13)), c + Vector((-0.03, -0.05, sg * 0.13))], 'iron', C_IRON, None, tip)

def build_cannon(mb, o, yaw):
    """Built pointing +X, then yawed."""
    with xf(mb, T(o) @ R('Y', yaw)):
        for sz in (-1, 1):
            with xf(mb, T(0, 0, sz * 0.25) @ R('X', -90)):
                pass
            with xf(mb, T(0, 0, sz * 0.25)):
                # stepped cheek: profile in (x, y) extruded along z
                with xf(mb, Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))):   # local (x, y, z) -> world (x, z, -y)
                    prism(mb, [(-0.56, 0.2), (0.5, 0.2), (0.5, 0.6), (0.2, 0.68), (0.0, 0.68), (-0.56, 0.34)], -0.055, 0.055, 'wood', C_RED, 0.012, (1, 0, 0))
        cbox(mb, (-0.03, 0.2, 0), (1.0, 0.09, 0.42), 'wood', mul(C_RED, 0.85), 0.02)
        for sx in (-0.34, 0.32):
            cbox(mb, (sx, 0.15, 0), (0.13, 0.13, 0.84), 'wood', C_DARK, 0.02)
            for sz in (-1, 1):
                with xf(mb, T(sx, 0.15, sz * 0.4) @ M_Y2Z):
                    cyl(mb, 0.155, -0.055, 0.055, 12, 'wood', C_DARK, True, 0.02)
                    cyl(mb, 0.05, -0.07, 0.07, 6, 'iron', C_IRON)
        with xf(mb, T(0.05, 0.62, 0) @ M_Y2X):
            k = 1.12
            prof = [(0, -0.9), (0.06, -0.89), (0.085, -0.84), (0.05, -0.78), (0.19, -0.75), (0.215, -0.7), (0.215, -0.64), (0.19, -0.62), (0.185, -0.3), (0.205, -0.28), (0.205, -0.21), (0.175, -0.19),
                    (0.15, 0.5), (0.168, 0.52), (0.168, 0.58), (0.14, 0.6), (0.132, 0.9), (0.175, 0.95), (0.18, 1.04), (0.165, 1.07), (0.1, 1.07), (0.1, 0.85), (0, 0.85)]
            brass_seg = {8, 9, 10, 12, 13, 14, 16, 17, 18, 19}
            for i in range(len(prof) - 1):
                seg = [(prof[i][0] * k, prof[i][1]), (prof[i + 1][0] * k, prof[i + 1][1])]
                isb = i in brass_seg
                lathe(mb, seg, 14, 'brass' if isb else 'iron', C_BRASS if isb else (C_BLACK if i >= 20 else C_IRON))
        with xf(mb, T(0.05, 0.62, 0) @ M_Y2Z):
            cyl(mb, 0.06, -0.33, 0.33, 8, 'iron', C_IRON)

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
    """Sail-control winch: horizontal drum between two cheeks, crank inboard, coloured band so the two stations differ."""
    sg = 1 if o[0] > 0 else -1
    with xf(mb, T(o) @ S(sg, 1, 1)):
        cbox(mb, (-0.02, 0.04, 0), (0.42, 0.08, 0.7), 'wood', C_DARK, 0.02)
        for sz in (-1, 1):
            hexa(mb, [(-0.19, 0.08, sz * 0.27 - 0.05), (0.15, 0.08, sz * 0.27 - 0.05), (0.15, 0.08, sz * 0.27 + 0.05), (-0.19, 0.08, sz * 0.27 + 0.05),
                      (-0.1, 0.78, sz * 0.27 - 0.05), (0.06, 0.78, sz * 0.27 - 0.05), (0.06, 0.78, sz * 0.27 + 0.05), (-0.1, 0.78, sz * 0.27 + 0.05)], 'wood', band, (0, 1, 0))
        with xf(mb, T(-0.02, 0.6, 0) @ M_Y2Z):
            lathe(mb, [(0, -0.22), (0.15, -0.22), (0.15, -0.18), (0.1, -0.16), (0.1, 0.16), (0.15, 0.18), (0.15, 0.22), (0, 0.22)], 10, 'wood', C_HULL)
            lathe(mb, [(0.1, -0.15), (0.125, -0.15), (0.125, 0.15), (0.1, 0.15)], 10, 'rope', C_ROPE)
            cyl(mb, 0.03, -0.4, 0.4, 6, 'iron', C_IRON)
        for sz in (-1, 1):
            cbox(mb, (-0.02, 0.5, sz * 0.4), (0.05, 0.26, 0.04), 'iron', C_IRON, 0.008)
            cbox(mb, (-0.02, 0.39, sz * 0.47), (0.05, 0.05, 0.16), 'wood', C_CREAM, 0.012)
        cbox(mb, (0.1, 0.84, 0), (0.07, 0.07, 0.5), 'wood', C_CREAM, 0.02)          # belaying rail on top
        for z in (-0.14, 0.14):
            cbox(mb, (0.1, 0.84, z), (0.035, 0.26, 0.035), 'wood', C_DARK, 0.01)
    with xf(mb, T(o)):
        rope_coil(mb, (-sg * 0.42, 0, -0.42), 0.19, 3)

# ---------------------------------------------------------------- collision
def col_wall(name, s0, s1, y0, y1fn, thick=TH, extra_out=0.0, ns=3, ny=3):
    for sg, tag in ((1, 'S'), (-1, 'P')):
        pts = []
        for i in range(ns):
            s = s0 + (s1 - s0) * i / (ns - 1); u = umap(s); yt = y1fn(hull_pt(u, 1.0).z, u)
            for j in range(ny):
                y = y0 + (yt - y0) * j / (ny - 1); v = v_of_y(u, y)
                p = hull_pt(u, v); n = hull_n(u, v)
                a = p + n * extra_out; b = p - n * thick; b.x = max(b.x, 0.0)
                pts += [(sg * a.x, a.y, a.z), (sg * b.x, b.y, b.z)]
        col_piece('col_%s_%s' % (name, tag), pts)

def build_collision():
    # hull below the hold floor
    zb = [6.25, 4.2, 1.8, -0.6, -3.0, -4.6, -5.75]
    for i in range(len(zb) - 1):
        pts = []
        for z in (zb[i], (zb[i] + zb[i + 1]) / 2, zb[i + 1]):
            for y in (-1.0, -0.9, -0.75, HOLD_Y):
                x = hull_b(z, y)
                if z > zstem(y) + 0.01: pts += [(x, y, z), (-x, y, z)]
            if z > -3.6: pts += [(0.12, -1.2, z), (-0.12, -1.2, z)]
            elif z > zstem(-0.95): pts += [(0, -1.0, z)]
        if len(pts) >= 4: col_piece('col_hull_bottom_%d' % i, pts)
    # hull sides from the hold floor to the deck, two bands so the hold stays hollow
    zs = [6.6, 5.4, 4.2, 2.8, 1.2, -0.4, -2.0, -3.6, -4.9, -5.8, -6.45]
    for i in range(len(zs) - 1):
        s0, s1 = (0.0 if i == 0 else s_of_z(zs[i], 0.45)), s_of_z(zs[i + 1], 0.45)
        col_wall('hull_side_low_%d' % i, s0, s1, HOLD_Y - 0.1, lambda z, u: 0.25)
        col_wall('hull_side_mid_%d' % i, s0, s1, 0.25, lambda z, u: DECK_Y - 0.02)
    # bulwarks and rails, leaving the gun ports and ladder gaps open
    sq = s_of_z(QDECK_Z)
    def top(z, u): return ytop(z) + (0.8 if z > QDECK_Z - 0.01 else 0.12)
    k = 0
    for (a, b) in top_intervals(NS - 0.5):
        cuts = [a] + [c for c in (sq, s_of_z(4.8), s_of_z(-3.3), s_of_z(-4.8), s_of_z(-5.8)) if a + 0.5 < c < b - 0.5] + [b]
        cuts.sort()
        for i in range(len(cuts) - 1):
            mid_z = hull_pt(umap((cuts[i] + cuts[i + 1]) / 2), 1.0).z
            col_wall('rail_%d' % k, cuts[i], cuts[i + 1], DECK_Y - 0.02, top, 0.2); k += 1
    # stem
    col_piece('col_stem', [(sx * 0.13, y, zstem(y) + dz) for y in (-0.6, 0.3, 1.2, 2.5) for sx in (-1, 1) for dz in (-0.25, 0.3)])
    # transom + taffrail
    pts = []
    yt = ytop(6.5) + 0.8
    for y in (YT, 0.2, 0.7, 1.4, 2.0, yt):
        for sg in (-1, 1):
            for dz in (0.03, -0.16): pts.append((sg * max(wtrans(y), 0.12), y, zstern(y) + dz))
    col_piece('col_transom', pts)
    # decks
    main = deck_outline(DECK_Y - 0.12, DECK_Y, -6.52, QDECK_Z + 0.1)
    hx0, hx1, hz0, hz1 = HATCH
    def slab(name, poly, y0, y1):
        if poly: col_piece(name, [(x, y, z) for x, z in poly for y in (y0, y1)])
    slab('col_deck_main_fore', clip_rect(main, -9, 9, -7, hz0), DECK_Y - 0.12, DECK_Y)
    slab('col_deck_main_port', clip_rect(main, -9, hx0, hz0, hz1), DECK_Y - 0.12, DECK_Y)
    slab('col_deck_main_starboard', clip_rect(main, hx1, 9, hz0, hz1), DECK_Y - 0.12, DECK_Y)
    slab('col_deck_main_aft', clip_rect(main, -9, 9, hz1, QDECK_Z + 0.1), DECK_Y - 0.12, DECK_Y)
    zq1 = zstern(QDECK_Y) - 0.1
    slab('col_quarterdeck', deck_outline(QDECK_Y - 0.12, QDECK_Y, QDECK_Z - 0.06, zq1, 10, 1.0), QDECK_Y - 0.12, QDECK_Y)
    slab('col_hold_floor', deck_outline(HOLD_Y - 0.06, HOLD_Y, -4.3, 5.75, 16, 1.0), HOLD_Y - 0.2, HOLD_Y)
    # stairs as ramps
    col_piece('col_stairs_quarter', [(sx * 0.66, y, z) for sx in (-1, 1) for (y, z) in ((DECK_Y, 1.9), (DECK_Y, QDECK_Z), (QDECK_Y, QDECK_Z), (QDECK_Y, QDECK_Z - 0.2))])
    zt, zbm = hz1 - 0.02, hz0 + 0.05
    col_piece('col_stairs_hold', [(sx * 0.58, y + dy, z) for sx in (-1, 1) for (y, z) in ((DECK_Y, zt), (HOLD_Y, zbm)) for dy in (0.0, -0.16)])
    # quarterdeck break: bulkhead (above the main deck) and front rail either side of the stairs
    hb = hull_b(QDECK_Z + 0.05, QDECK_Y) - 0.08
    col_piece('col_bulkhead_quarter', [(sx * hb, y, z) for sx in (-1, 1) for y in (DECK_Y - 0.12, QDECK_Y) for z in (QDECK_Z, QDECK_Z + 0.12)])
    for sg, tag in ((1, 'S'), (-1, 'P')):
        col_piece('col_rail_quarter_front_%s' % tag, [(sg * x, y, z) for x in (0.64, hb) for y in (QDECK_Y, QDECK_Y + 0.9) for z in (QDECK_Z - 0.06, QDECK_Z + 0.12)])
    hbk = hull_b(-4.3, DECK_Y - 0.1) - 0.1
    col_piece('col_bulkhead_hold', [(sx * x, y, -4.3 + dz) for sx in (-1, 1) for (x, y) in ((hull_b(-4.3, HOLD_Y) - 0.1, HOLD_Y), (hbk, DECK_Y - 0.1)) for dz in (-0.06, 0.06)])
    # mast, bowsprit
    col_piece('col_mast', [(0.3 * cos(k * pi / 4), y, MAST_Z + 0.3 * sin(k * pi / 4)) for k in range(8) for y in (HOLD_Y, 10.5)])
    col_piece('col_mast_top', [(r * cos(k * pi / 4), y, MAST_Z + r * sin(k * pi / 4)) for k in range(8) for (y, r) in ((10.5, 0.9), (11.5, 0.95))])
    col_piece('col_bowsprit', [(sx * 0.14, 2.25 + dy + 1.7 * f, -5.45 - 4.95 * f) for sx in (-1, 1) for dy in (-0.14, 0.14) for f in (0, 1)])

# ================================================================ main
def main():
    argv = sys.argv; outdir = argv[-1] if '--' in argv else os.path.join(os.getcwd(), 'assets', 'generated')
    random.seed(SEED); np.random.seed(SEED)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    make_materials()
    hull = MB('Hull'); build_hull(hull); build(hull)
    decks = MB('Decks'); build_decks(decks); build(decks)
    rails = MB('Rails'); build_rails(rails); build(rails)
    inter = MB('Interior'); build_interior(inter); build(inter)
    mast = MB('Mast');
    with xf(mast, T(0, 0, MAST_Z)): build_mast(mast)
    build_bowsprit(mast); build(mast)
    rig = MB('Rigging'); build_rigging(rig); build(rig)
    fig = MB('Figurehead', (0, 1.8, -7.0)); build_figurehead(fig); build(fig)
    yard = MB('Yard', (0, YARD_Y, MAST_Z)); build_yard(yard); build(yard)
    sail = MB('Sail', (0, YARD_Y, MAST_Z)); build_sail(sail); build(sail)
    flag = MB('Flag', (0, MAST_TOP - 0.12, MAST_Z)); build_flag(flag); build(flag)
    hz = STATIONS['Station_Helm'][0][2]
    o = (0, QDECK_Y + 0.95, hz); wheel = MB('Wheel', o); build_wheel(wheel, o); build(wheel)
    o = (0, 0, 6.41); rud = MB('Rudder', o); build_rudder(rud, o); build(rud)
    o = STATIONS['Station_Anchor'][0]; cap = MB('Capstan', o); build_capstan(cap, o); build(cap)
    o = (1.62, ytop(-5.1) - 0.05, -5.1); anc = MB('Anchor', o); build_anchor(anc, o); build(anc)
    for name, sg, yaw in (('Cannon_Starboard', 1, 0), ('Cannon_Port', -1, 180)):
        o = (sg * 1.38, DECK_Y, -1.5); c = MB(name, o, seed=1); build_cannon(c, o, yaw); build(c)
    for name, c, s, hang in (('Lantern_Stern', (0, ytop(6.5) + 1.55, zstern(ytop(6.5)) - 0.02), 1.5, False), ('Lantern_Mast', (0, 3.45, MAST_Z + 0.52), 1.0, True),
                             ('Lantern_Hold', (0, 1.42, 3.7), 1.0, True), ('Lantern_Hold_Fore', (0.5, 0.45, MAST_Z), 0.9, True)):
        l = MB(name, c); build_lantern(l, c, s, hang);
        if name == 'Lantern_Stern':
            yt = ytop(6.5); zt = zstern(yt) - 0.02
            tube(l, [(0, yt + 0.1, zt), (0, yt + 1.22, zt)], 0.045, 6, 'iron', C_IRON)
            cbox(l, (0, yt + 0.45, zt), (0.2, 0.9, 0.16), 'wood', C_CREAM, 0.03, (0, 1, 0))
        elif name == 'Lantern_Mast':
            cbox(l, (0, c[1] + 0.42, MAST_Z + 0.4), (0.05, 0.05, 0.36), 'iron', C_IRON, 0.01)
        elif name == 'Lantern_Hold':
            tube(l, [(0, c[1] + 0.42, c[2]), (0, QDECK_Y - 0.1, c[2])], 0.012, 4, 'iron', C_IRON)
        else:
            cbox(l, (0.4, c[1] + 0.38, MAST_Z), (0.3, 0.05, 0.05), 'iron', C_IRON, 0.01)
        build(l)
    for name, key, band in (('Winch_SailLength', 'Station_SailLength', C_RED), ('Winch_SailAngle', 'Station_SailAngle', C_TEAL)):
        o = STATIONS[key][0]; o = (o[0] * 0.955, o[1], o[2]); w = MB(name, o); build_winch(w, o, band); build(w)
    mt = MB('MapTable', STATIONS['Station_MapTable'][0]); build_map_table(mt); build(mt)
    pd = MB('Props_Deck'); build_props_deck(pd); build(pd)
    ph = MB('Props_Hold'); build_props_hold(ph); build(ph)
    build_collision()
    for name, (p, yaw) in STATIONS.items():
        e = bpy.data.objects.new(name, None); e.empty_display_size = 0.3
        e.location = conv(p); e.rotation_euler = (0, 0, radians(yaw))
        bpy.context.scene.collection.objects.link(e)
    total = 0
    for n in OBJS:
        if not n.startswith('col_'):
            total += OBJS[n][1]; print('  %-20s %6d tris' % (n, OBJS[n][1]))
    print('sloop: %d visual triangles, %d objects, %d collision pieces' % (total, len([n for n in OBJS if not n.startswith('col_')]), len([n for n in OBJS if n.startswith('col_')])))
    os.makedirs(os.path.join(outdir, 'ship'), exist_ok=True)
    path = os.path.join(outdir, 'ship', 'sloop.glb')
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_yup=True, export_apply=False, export_vertex_color='MATERIAL',
                              export_all_vertex_colors=False, export_cameras=False, export_lights=False, export_animations=False,
                              export_extras=False, export_tangents=False)
    print('wrote', path)

main()
