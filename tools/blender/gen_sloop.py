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
HOLD_Y = float(os.environ.get('SLOOP_HOLD_Y', '-0.85'))  # hold floor: 1.85 m clear under the main deck. Everything below deck follows it
                      # (stairs, table and bilge markers, props, ribs, collision).
MAST_Z = -1.0
YARD_Y = 9.0
MAST_TOP = DECK_Y + 14.0
YARD_FWD = 0.52       # the yard hangs this far forward of the mast axis (far enough to swing clear of the shrouds)
TH = 0.16             # hull plank thickness
STATIONS = {
    "Station_Bilge": ((0, HOLD_Y, -2.1), 0),            # extra (not in the spec): the bail/pump spot in the hold

    "Station_Helm": ((0, 2.0, 5.2), 0),
    "Station_SailLength": ((-1.9, 1.1, 0.5), 0),
    "Station_SailAngle": ((1.9, 1.1, 0.5), 0),
    "Station_Anchor": ((0, 1.1, -4.6), 0),
    "Station_CannonPort": ((-2.0, 1.1, -1.5), 90),        # yaw so that -Z faces -X
    "Station_CannonStarboard": ((2.0, 1.1, -1.5), -90),   # -Z faces +X
    "Station_MapTable": ((0, HOLD_Y, 2.5), 0),
    "Station_Ladder_Port": ((-2.3, 0, 2.0), 0),
    "Station_Ladder_Starboard": ((2.3, 0, 2.0), 0),
}
GAPS = [(-1.95, -1.05), (1.55, 2.45)]   # z ranges cut out of the bulwark: gun ports, ladders
HOLD_STAIR = (2.2, -0.25)                # z at the top (main deck) and at the foot (hold floor) of the stairs down
HATCH = (-0.5, 0.5, -0.6, 2.25)           # x0, x1, z0, z1 hole in the main deck (long, so the stairs down are as shallow as the mast and the quarterdeck allow)
QSTAIR = (0.9, 1.95, 2.6, 3.9)           # x0, x1, z0, z1 of the starboard quarterdeck flight (port is mirrored); it is let into the quarterdeck
BS_HEEL = (0, 2.5, -5.45); BS_TIP = (0, 4.15, -10.4)   # bowsprit

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
    def __init__(self, name, origin=(0, 0, 0), seed=0, yaw=0.0, parent=None):
        self.name = name; self.origin = Vector(origin); self.yaw = yaw; self.parent = parent
        self.verts = []; self.faces = []; self.fmat = []; self.fsm = []; self.fcol = []; self.fuv = []
        self.stack = [Matrix.Identity(4)]; self.flip = False
        self.rng = random.Random(SEED * 7919 + seed + sum(ord(c) for c in name))
        self.off = (0.0, 0.0)
        self.wfn = None       # optional pos -> (weight, aux): written to UV2 for wind shaders (vertex colour stays the albedo tint)
        self.gmatrix = None   # optional full object matrix in game coords (verts are then object-local)

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

def loft(mb, secs, mat, col, closed=True, caps=(True, True), mode='flat', ecols=None, scols=None, flip=None, grain_caps=None, uniform_w=False):
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
    if uniform_w: W = [W[n // 2]] * n          # one across-the-grain mapping for every section: no skew where a section is pinched
    if flip is None:                       # orient outward: area-weighted vote over every quad (ends may be pinched or twisted)
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
            if abs(y0 - y1) < 1e-6:        # flat disc or annulus: planar UVs, no pinwheel
                uvs = [(r * cos(2 * pi * kk / segs) * SU + o[0], r * sin(2 * pi * kk / segs) * SV + o[1]) for r, kk in ((r0, k), (r1, k), (r1, k + 1), (r0, k + 1))]
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
# strake edges at midship. The first two are the wide flat bottom planks and the turn of the bilge; bulwark top 0.9 m + cap rail = 1.0 m
YS = [-1.0, -0.975, -0.91, -0.74, -0.48, -0.22, 0.05, 0.30, 0.55, 0.80, 1.02, 1.24, 1.50, 1.76, 2.0]
VS = [(y + 1.0) / 3.0 for y in YS]
J_CREAM = YS.index(0.05); J_WALE = YS.index(0.80); J_SILL = YS.index(1.24)     # boot stripe, wale, lowest strake cut by the gun ports

def hull_th(y):
    """Planking thickness: thinner across the bottom so the hold floor can sit 1.85 m under the main deck."""
    return 0.10 + (TH - 0.10) * smooth01((y + 0.95) / 0.4)
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
    return 2.2 * (1 - (1 - h) ** 3.0) ** (1 / 3.6) * tumble(y)   # full, flat-floored midsection: room to walk in the hold

def wtrans(y):
    if y <= YT: return 0.0
    h = min(1.0, (y - YT) / (1.1 - YT))
    return 1.62 * (1 - (1 - h) ** 2.4) ** (1 / 2.2) * tumble(y)

def hull_b(z, y):
    """Half breadth of the outer hull surface at (z, y)."""
    bm = bmid(y)
    if z >= 0:
        t = min(1.0, z / zstern(y)); return bm - (bm - wtrans(y)) * t ** 3.0
    t = min(1.0, z / zstem(y)); return bm * max(0.0, 1 - t ** 2.4) ** 0.7

def ytop(z):
    """Sheer: top of the hull planking."""
    if z < 0: return 2.0 + 0.5 * (-z / 6.5) ** 2
    return 2.0 + 0.55 * smooth01((z - 1.0) / 3.5) + 0.1 * (z / 6.5) ** 2

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

def hull_in(u, v):
    p = hull_pt(u, v); p = p - hull_n(u, v) * hull_th(p.y)
    p.x = max(p.x, 0.0); return p

def inner_half(z, y):
    """Half breadth of the inside face of the planking at height y near station z (found on the offset surface itself)."""
    lo, hi = 0.0, 1.0
    for _ in range(26):
        v = (lo + hi) / 2
        if hull_in(umap(s_of_z(z, v)), v).y < y: lo = v
        else: hi = v
    v = (lo + hi) / 2
    return hull_in(umap(s_of_z(z, v)), v).x

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
# Stable material names for game shaders (wetness, wind, night glow): every surface in both glbs uses one of these.
MAT_NAMES = {'wood': 'mat_wood', 'paint': 'mat_paint', 'rope': 'mat_rope', 'iron': 'mat_iron', 'brass': 'mat_brass', 'glass': 'mat_lantern_glass',
             'window': 'mat_window_glass', 'canvas': 'mat_canvas', 'canvas_back': 'mat_canvas_back', 'cloth': 'mat_cloth', 'flag': 'mat_flag',
             'canvas_lod': 'mat_canvas_lod', 'canvas_back_lod': 'mat_canvas_back_lod', 'col': 'mat_collision'}

def make_materials():
    rs = np.random.RandomState(SEED)
    sail_px = tex_sail(rs)
    wood = make_image('sloop_wood', tex_wood(rs)); sail = make_image('sloop_sail', sail_px); flag = make_image('sloop_flag', tex_flag(rs))
    # the aft face of the sail: seams, patches and emblem ghosted through sunlit cloth
    back = sail_px * 0.42 + np.array([1.0, 0.95, 0.80]) * 0.60
    sail_back = make_image('sloop_sail_back', back)
    def mk(name, tex=None, rough=0.8, metal=0.0, emit=0.0, two=False, alpha=1.0, emit_col=(1.0, 0.62, 0.22, 1)):
        m = bpy.data.materials.new(MAT_NAMES[name]); m.use_nodes = True
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
            b.inputs['Emission Color'].default_value = emit_col; b.inputs['Emission Strength'].default_value = emit
        if alpha < 1.0:
            b.inputs['Alpha'].default_value = alpha; m.surface_render_method = 'BLENDED'
        m.use_backface_culling = not two
        MATS[name] = m
    mk('wood', wood, 0.82)
    mk('paint', None, 0.6)           # painted or plain surfaces (vertex colour only)
    mk('rope', None, 0.95)
    mk('iron', None, 0.5, 0.55)
    mk('brass', None, 0.32, 0.85)
    mk('glass', None, 0.25, 0.0, 2.2)                                   # lantern glass: emissive
    mk('window', None, 0.08, 0.0, 0.35, two=True, alpha=0.3)            # stern glazing: see-through, faint warm glow to raise at night
    mk('canvas', sail, 0.95)                                            # forward face of the sail
    mk('canvas_back', sail_back, 0.95, emit=0.22, emit_col=(1.0, 0.86, 0.6, 1))   # aft face: ghosted print, a little back-lit glow
    mk('cloth', None, 0.95, two=True)
    mk('flag', flag, 0.9, two=True)
    mk('col', None, 1.0)
    small = sail_px.reshape(128, 4, 128, 4, 3).mean(axis=(1, 3))
    mk('canvas_lod', make_image('sloop_sail_lod', small), 0.95)
    mk('canvas_back_lod', make_image('sloop_sail_back_lod', small * 0.42 + np.array([1.0, 0.95, 0.80]) * 0.60), 0.95, emit=0.22, emit_col=(1.0, 0.86, 0.6, 1))

# ---------------------------------------------------------------- object creation
def conv(p):
    return (p[0], -p[2], p[1])

OBJS = {}
def build(mb):
    me = bpy.data.meshes.new(mb.name)
    rinv = Matrix.Rotation(radians(-mb.yaw), 3, 'Y')
    if mb.gmatrix is not None: me.from_pydata([conv(v) for v in mb.verts], [], mb.faces)
    else: me.from_pydata([conv(rinv @ (v - mb.origin)) for v in mb.verts], [], mb.faces)
    names = sorted(set(mb.fmat))
    for n in names: me.materials.append(MATS[n])
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
            if wv: uv2.extend(wv[f[k]])
    uvl.data.foreach_set('uv', uvs); ca.data.foreach_set('color', cols)
    if wv:
        u2 = me.uv_layers.new(name='Wind'); u2.data.foreach_set('uv', uv2)
    me.polygons.foreach_set('material_index', [mi[m] for m in mb.fmat])
    me.polygons.foreach_set('use_smooth', mb.fsm)
    me.update()
    ob = bpy.data.objects.new(mb.name, me)
    if mb.gmatrix is not None:
        C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
        ob.matrix_world = C @ mb.gmatrix @ C.inverted()
    elif mb.parent is not None:
        po = mb.parent; pr = Matrix.Rotation(radians(-po.yaw), 3, 'Y')
        ob.parent = OBJS[po.name][0]; ob.location = conv(pr @ (mb.origin - po.origin)); ob.rotation_euler = (0, 0, radians(mb.yaw - po.yaw))
    else:
        ob.location = conv(mb.origin); ob.rotation_euler = (0, 0, radians(mb.yaw))
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
    if j == J_CREAM: return C_CREAM, 0.012
    if j == J_WALE: return C_RED, 0.05
    if j == len(YS) - 2: return C_TEAL, 0.012
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
        E = p1 - n1 * hull_th(p1.y); F = p0 - n0 * hull_th(p0.y)
        for q in (A, Bp, Cp, D, E, F): q.x = max(q.x, 0.0)
        secs.append([A, Bp, Cp, D, E, F])
    dk = mul(col, 0.55)
    loft(mb, secs, 'wood', col, True, (True, True), 'len', ecols=[dk, col, dk, mul(col, 0.9), inner_col, inner_col], uniform_w=True)

# Hull damage. Each hole sits on the seam between two strakes; the two short plank lengths around it are built as a
# separate removable HullPanel_NN (in place by default: the hull is seamless, it just has two more butt joints there).
# (side, z, index of the strake edge the hole is centred on): J_LOW is below the waterline, J_HIGH above it.
J_LOW = YS.index(-0.22); J_HIGH = YS.index(0.55)
HOLES = [(1, -3.3, J_LOW), (1, -1.9, J_HIGH), (1, 0.3, J_LOW), (1, 1.15, J_HIGH), (1, 3.6, J_LOW),
         (-1, -2.8, J_HIGH), (-1, -0.9, J_LOW), (-1, 0.9, J_HIGH), (-1, 2.9, J_LOW), (-1, 4.1, J_HIGH)]
PANEL_HALF = 0.46          # half length of a panel along the hull, metres
PANELS = []                # filled by plan_panels(): dicts with the parametric window of each panel

def plan_panels():
    PANELS.clear()
    for idx, (sg, z, jb) in enumerate(HOLES):
        v = VS[jb]; sc = s_of_z(z, v); e = 0.01
        mps = (hull_pt(umap(sc + e), v) - hull_pt(umap(sc - e), v)).length / (2 * e)      # metres per unit s
        u = umap(sc); p = hull_pt(u, v); n = hull_n(u, v)
        mpv = (hull_pt(u, v + 1e-3) - hull_pt(u, v - 1e-3)).length / 2e-3                # metres per unit v
        org = p - n * (TH / 2); org.x *= sg
        PANELS.append(dict(idx=idx, side=sg, jb=jb, sc=sc, sa=sc - PANEL_HALF / mps, sb=sc + PANEL_HALF / mps, mps=mps, mpv=mpv, v=v,
                           origin=org, yaw=math.degrees(atan2(-n.x * sg, -n.z)), cols={},
                           mb=None))
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
                        s += rng.uniform(7, 13)
                        if s > bnd - 3: break
                        if s > a + 3: cuts.append(float(round(s)))
                    cuts.append(bnd)
                    for P in here:                                  # force butt joints at the panel ends
                        cuts = [c for c in cuts if c in (a, bnd) or not (P['sa'] - 2.2 < c < P['sb'] + 2.2)] + [P['sa'], P['sb']]
                    cuts.sort()
                    for k in range(len(cuts) - 1):
                        amt = 0.05 if base in (C_RED, C_TEAL, C_CREAM) else 0.13
                        inner = jit(C_INNER if j <= J_WALE else C_HULL, rng, 0.10); colr = jit(base, rng, amt)
                        P = next((P for P in here if abs(cuts[k] - P['sa']) < 1e-9 and abs(cuts[k + 1] - P['sb']) < 1e-9), None)
                        if P is None:
                            hull_plank(mb, j, cuts[k], cuts[k + 1], colr, extra, inner)
                        else:
                            P['cols'][j] = (colr, inner, extra)
                            with xf(P['mb'], S(side, 1, 1)): hull_plank(P['mb'], j, cuts[k], cuts[k + 1], colr, extra, inner)
    # keel + stem as one swept timber
    path = [(6.25, -1.0), (2.0, -1.0), (-2.0, -1.0), (-3.4, -1.0)]
    for i in range(8, 241, 8): path.append((_SB[i][1], _SB[i][0]))
    for y in (1.4, 1.7, 2.0, 2.3, 2.52, 2.68): path.append((zstem(y), y))
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
    for (y0, y1, c, ex) in ((YT, 0.12, C_TAR, 0), (0.12, 0.36, C_HULL, 0), (0.36, 0.54, C_CREAM, 0.03), (0.54, 0.64, C_TEAL, 0), (1.36, 1.46, C_TEAL, 0), (1.46, 1.6, C_CREAM, 0.03),
                            (1.6, 1.9, C_HULL, 0), (1.9, 2.2, C_HULL, 0), (2.2, yts - 0.14, C_HULL, 0), (yts - 0.14, yts, C_RED, 0.03)):
        tplank(y0, y1, jit(c, rng, 0.06), ex)
    def tpier(xa, xb):                                         # the wall between and beside the stern windows
        X = lambda f, y: f(y) if callable(f) else f
        pts = [(X(x, y), y, zstern(y) + dz) for y in (0.64, 1.36) for (x, dz) in ((xa, -0.14), (xb, -0.14), (xb, 0.0), (xa, 0.0))]
        c = jit(C_TEAL, rng, 0.06); cen = sum((Vector(q) for q in pts), Vector()) / 8; mb.newoff()
        for q, cc in (((0, 1, 2, 3), c), ((4, 5, 6, 7), c), ((0, 1, 5, 4), jit(C_INNER, rng, 0.08)), ((1, 2, 6, 5), c), ((2, 3, 7, 6), c), ((3, 0, 4, 7), c)):
            mb.fp([pts[i] for i in q], 'wood', cc, (0, 1, 0), cen)
    tpier(lambda y: -wtrans(y), -1.19); tpier(-0.53, -0.33); tpier(0.33, 0.53); tpier(1.19, lambda y: wtrans(y))
    with xf(mb, T(0, 1.1, 6.5) @ R('X', a)):
        ca = cos(radians(a))
        def ly(y): return (y - 1.1) / ca
        for wx in (-0.86, 0.0, 0.86):                          # stern windows: real openings, glazed with mat_window_glass
            y0, y1 = ly(0.64), ly(1.36); hw = 0.33
            mb.newoff(); mb.fp([(wx - hw, y0, -0.07), (wx + hw, y0, -0.07), (wx + hw, y1, -0.07), (wx - hw, y1, -0.07)], 'window', (0.80, 0.93, 0.88), None, (wx, 0, -5))
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
            pts = [(sg * (hull_b(2.0, y) + 0.03), y, 2.0 + dz) for y in (-0.4, 0.0, 0.4, 0.8, 1.14)]
            tube(mb, pts, 0.035, 5, 'wood', C_DARK)
    # rope fenders hung over the side
    for sg in (-1, 1):
        for z in (-3.7, 0.1, 3.3):
            yy = 0.88; x = hull_b(z, yy) + 0.2
            with xf(mb, T(sg * x, yy, z)):
                ellipsoid(mb, (0, 0, 0), (0.15, 0.28, 0.15), 'rope', C_ROPE, 10, 7)
                for dy in (-0.1, 0.1):
                    with xf(mb, T(0, dy, 0)): torus(mb, 0.145, 0.02, 10, 4, 'rope', C_ROPE_D)
            tube(mb, [(sg * x, yy + 0.26, z), (sg * (hull_b(z, 1.6) + 0.06), 1.6, z), (sg * (hull_b(z, ytop(z)) + 0.03), ytop(z) + 0.08, z)], 0.016, 4, 'rope', C_ROPE)
    # catheads
    for sg in (-1, 1):
        cbox(mb, (sg * 1.3, ytop(-5.1) + 0.2, -5.1), (0.9, 0.2, 0.24), 'wood', C_DARK, 0.03)
        cbox(mb, (sg * 1.77, ytop(-5.1) + 0.2, -5.1), (0.06, 0.24, 0.28), 'wood', C_RED, 0.02)

def deck_outline(yb, yt, z0, z1, n=44, pw=1.7, margin=0.07, inner=False):
    zs = [z0 + (z1 - z0) * (i / n) ** pw for i in range(n + 1)]
    if inner:   # sloping hull: reach just past the inside face of the planking, never through the outside
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
    deck_planks(mb, main, -6.6, QDECK_Z + 0.1, DECK_Y, 0.1, 0.2, [HATCH], deck_col)
    zq1 = zstern(QDECK_Y) - 0.1
    quarter = deck_outline(QDECK_Y - 0.1, QDECK_Y, QDECK_Z - 0.06, zq1, 12, 1.0)
    qx0, qx1, qz0, qz1 = QSTAIR
    deck_planks(mb, quarter, QDECK_Z - 0.06, zq1, QDECK_Y, 0.1, 0.2, [(qx0, 9, QDECK_Z - 0.1, qz1), (-9, -qx0, QDECK_Z - 0.1, qz1)], deck_col)
    # waterways (margin planks) hide the stepped plank ends against the bulwark
    for (yd, z0, z1, n) in ((DECK_Y, -6.5, QDECK_Z, 40), (QDECK_Y, qz1, zq1, 8)):
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
    # ---- quarterdeck break: bulkhead with a cabin door, beam, twin side flights let into the quarterdeck
    hb = qx0
    nb = 8
    for i in range(nb):
        x0 = -hb + 2 * hb * i / nb; x1 = -hb + 2 * hb * (i + 1) / nb
        door = i in (3, 4)
        cbox(mb, ((x0 + x1) / 2, (DECK_Y + QDECK_Y - 0.1) / 2 - 0.05, QDECK_Z + 0.06), (x1 - x0, QDECK_Y - 0.1 - DECK_Y + 0.1, 0.1), 'wood', jit(C_DARK if door else C_TEAL, rng, 0.07), 0.014, (0, 1, 0))
    for (cx, cy, sx, sy) in ((-0.45, 1.48, 0.09, 0.78), (0.45, 1.48, 0.09, 0.78), (0, 1.86, 0.99, 0.09)):                  # door frame
        cbox(mb, (cx, cy, QDECK_Z - 0.0), (sx, sy, 0.07), 'wood', C_GOLD, 0.02)
    for cy in (1.3, 1.68): cbox(mb, (0, cy, QDECK_Z + 0.0), (0.8, 0.06, 0.04), 'iron', C_IRON, 0.01)                      # strap hinges
    with xf(mb, T(0.28, 1.45, QDECK_Z - 0.01) @ M_Y2Z): torus(mb, 0.05, 0.014, 10, 5, 'brass', C_BRASS)                 # ring handle
    cbox(mb, (0, QDECK_Y - 0.11, QDECK_Z - 0.01), (2 * hb + 0.04, 0.16, 0.2), 'wood', C_RED, 0.03)
    cbox(mb, (0, DECK_Y - 0.17, QDECK_Z + 0.04), (2 * hull_b(QDECK_Z, 0.9) - 0.3, 0.14, 0.16), 'wood', C_DARK, 0.02)   # beam under the deck edge
    nq = 5; run = (qz1 - qz0) / nq; rise = (QDECK_Y - DECK_Y) / nq
    for sg in (-1, 1):
        with xf(mb, T(sg * (qx0 + qx1) / 2, 0, 0) @ M_ZY):
            prism(mb, [(qz0 + 0.02, DECK_Y - 0.05), (QDECK_Z + 0.05, DECK_Y - 0.1), (qz1, QDECK_Y - 0.4), (qz1, QDECK_Y - 0.04)], -(qx1 - qx0) / 2, (qx1 - qx0) / 2, 'wood', jit(C_DARK, rng, 0.06), 0.0, (1, 0, 0))
        for i in range(nq):
            top = DECK_Y + rise * (i + 1)
            box2(mb, (sg * qx0, top - rise - 0.02, qz0 + run * i), (sg * qx1, top, qz0 + run * (i + 1) + 0.03), 'wood', deck_col(), 0.02, (1, 0, 0))
        xi = sg * (qx0 - 0.035)                                                # inboard cheek: also the wall of the stairwell
        with xf(mb, T(xi, 0, 0) @ M_ZY):
            prism(mb, [(qz0 - 0.12, DECK_Y), (QDECK_Z, DECK_Y), (QDECK_Z, DECK_Y + 0.5), (qz0 - 0.12, DECK_Y + 0.2)], -0.035, 0.035, 'wood', C_RED, 0.0, (1, 0, 0.8))
            prism(mb, [(QDECK_Z, DECK_Y - 0.1), (qz1 + 0.04, DECK_Y - 0.1), (qz1 + 0.04, QDECK_Y + 0.05), (QDECK_Z, QDECK_Y + 0.05)], -0.035, 0.035, 'wood', C_RED, 0.0, (1, 0, 0.8))
    # ---- hatch: coaming on three sides (open aft where the stairs start) and the stairs down
    hx0, hx1, hz0, hz1 = HATCH
    for sg in (-1, 1):
        cbox(mb, (sg * (hx1 + 0.05), DECK_Y + 0.04, (hz0 + hz1) / 2 - 0.05), (0.16, 0.34, hz1 - hz0 + 0.16), 'wood', C_RED, 0.025)
    cbox(mb, (0, DECK_Y + 0.04, hz0 - 0.05), (hx1 - hx0 + 0.2, 0.34, 0.16), 'wood', C_RED, 0.025)
    cbox(mb, (0, DECK_Y - 0.068, hz1 + 0.05), (hx1 - hx0 + 0.25, 0.12, 0.1), 'wood', C_DARK, 0.015)
    zt, zb = HOLD_STAIR; nst = 10; H = DECK_Y - HOLD_Y
    for sg in (-1, 1):
        x = sg * (hx1 - 0.07)
        d = Vector((0, -H, zb - zt)); nrm = Vector((0, d.z, H)).normalized() * 0.13
        a = Vector((x, DECK_Y, zt + 0.02)); b = Vector((x, HOLD_Y, zb + 0.02))
        hexa(mb, [a - nrm + Vector((-0.035, 0, 0)), a - nrm + Vector((0.035, 0, 0)), b - nrm + Vector((0.035, 0, 0)), b - nrm + Vector((-0.035, 0, 0)),
                  a + nrm + Vector((-0.035, 0, 0)), a + nrm + Vector((0.035, 0, 0)), b + nrm + Vector((0.035, 0, 0)), b + nrm + Vector((-0.035, 0, 0))], 'wood', jit(C_DARK, rng, 0.05), d)
    for i in range(1, nst):
        y = DECK_Y - H * i / nst; z = zt + (zb - zt) * i / nst
        cbox(mb, (0, y - 0.03, z + 0.02), (hx1 - hx0 - 0.2, 0.06, 0.3), 'wood', deck_col(), 0.015, (1, 0, 0))
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
                    p, nh = rail_frame(s); sill = hull_pt(umap(s), VS[J_SILL]).y
                    c = p - nh * (TH / 2)
                    box2(mb, (c.x - 0.14, sill - 0.02, c.z + dz - 0.1), (c.x + 0.14, p.y + 0.17, c.z + dz + 0.1), 'wood', C_CREAM, 0.03, (0, 1, 0))
                    cbox(mb, (c.x, p.y + 0.2, c.z + dz), (0.34, 0.07, 0.26), 'wood', C_RED, 0.02)
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
                hgt = 0.45
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
    # pin rails inside the bulwark by the shrouds, with belaying pins and a coil of line
    for sg in (-1, 1):
        x = sg * (hull_b(1.2, 1.85) - TH - 0.07); yy = DECK_Y + 0.74
        cbox(mb, (x, yy, 1.2), (0.13, 0.06, 0.56), 'wood', C_DARK, 0.015)
        for zz in (0.98, 1.42): cbox(mb, (x + sg * 0.03, yy - 0.09, zz), (0.1, 0.14, 0.05), 'wood', C_DARK, 0.012)
        for i in range(4):
            with xf(mb, T(x, yy, 1.02 + 0.12 * i)):
                lathe(mb, [(0.012, -0.14), (0.016, -0.03), (0.016, 0.03), (0.028, 0.05), (0.03, 0.13), (0.02, 0.16), (0, 0.165)], 6, 'wood', C_CREAM)
        with xf(mb, T(x - sg * 0.05, yy - 0.24, 1.14) @ M_Y2X): torus(mb, 0.13, 0.025, 10, 4, 'rope', C_ROPE)
        with xf(mb, T(x - sg * 0.065, yy - 0.26, 1.14) @ M_Y2X): torus(mb, 0.11, 0.025, 10, 4, 'rope', mul(C_ROPE, 0.9))
    # front rail of the quarterdeck between the two flights, and a guard rail along each stairwell
    qx0, qx1, qz0, qz1 = QSTAIR
    xs = [-qx0 + 0.04 + (2 * qx0 - 0.08) * i / 6 for i in range(7)]
    for i, x in enumerate(xs):
        if i in (0, 6):
            cbox(mb, (x, QDECK_Y + 0.46, QDECK_Z + 0.02), (0.17, 0.92, 0.17), 'wood', C_CREAM, 0.03, (0, 1, 0))
            with xf(mb, T(x, QDECK_Y + 0.92, QDECK_Z + 0.02)):
                lathe(mb, [(0, 0), (0.07, 0.02), (0.09, 0.09), (0.06, 0.16), (0, 0.18)], 8, 'brass', C_BRASS, True, True)
        else:
            baluster(mb, (x, QDECK_Y, QDECK_Z + 0.02), 0.78, C_CREAM)
        if i < 6: baluster(mb, (x + (xs[1] - xs[0]) / 2, QDECK_Y, QDECK_Z + 0.02), 0.78, C_CREAM)
    cbox(mb, (0, QDECK_Y + 0.82, QDECK_Z + 0.02), (2 * qx0 - 0.2, 0.09, 0.2), 'wood', C_RED, 0.03)
    for sg in (-1, 1):
        x = sg * (qx0 - 0.04)
        for i in range(1, 5):
            z = QDECK_Z + 0.02 + (qz1 - QDECK_Z) * i / 4
            if i == 4:
                cbox(mb, (x, QDECK_Y + 0.44, z), (0.15, 0.88, 0.15), 'wood', C_CREAM, 0.03, (0, 1, 0))
            else:
                baluster(mb, (x, QDECK_Y + 0.05, z), 0.73, C_CREAM)
        cbox(mb, (x, QDECK_Y + 0.82, (QDECK_Z + qz1) / 2 + 0.06), (0.16, 0.09, qz1 - QDECK_Z + 0.1), 'wood', C_RED, 0.03)
    # taffrail across the stern
    yt = ytop(6.5); zt = zstern(yt) - 0.07; wt = wtrans(yt) - 0.02
    cbox(mb, (0, yt + 0.05, zt), (2 * wt + 0.3, 0.1, 0.3), 'wood', C_DARK, 0.03)
    nb = 9
    for i in range(1, nb):
        x = -wt + 2 * wt * i / nb
        if abs(x) < 0.01: continue
        baluster(mb, (x, yt + 0.1, zt + 0.03), 0.45, C_CREAM)
    yr = yt + 0.55; zr = zstern(yr) - 0.07
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
                v = v_of_y(u, y); n = hull_n(u, v); p = hull_pt(u, v) - n * (hull_th(y) - 0.01); q = p - n * 0.13
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
    build_bilge(mb, (0.0, HOLD_Y, -2.1))
    # mast step
    cbox(mb, (0, HOLD_Y + 0.07, MAST_Z), (0.76, 0.14, 0.76), 'wood', C_DARK, 0.04)

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
    barrel(mb, (-0.35, DECK_Y, -3.05), 0.28, 0.8); crate(mb, (0.3, DECK_Y, -2.85), (0.6, 0.5, 0.5), R('Y', 4))
    rope_coil(mb, (1.25, DECK_Y, -2.55), 0.26, 3); rope_coil(mb, (-1.2, QDECK_Y, 3.6), 0.24, 3)
    barrel(mb, (1.25, QDECK_Y, 6.15), 0.25, 0.72, tone=C_DARK)
    # cannonball rack beside each gun
    for sg in (-1, 1):
        cbox(mb, (sg * 1.55, DECK_Y + 0.05, -0.75), (0.5, 0.1, 0.2), 'wood', C_DARK, 0.02)
        for i in range(3):
            ellipsoid(mb, (sg * (1.39 + 0.16 * i), DECK_Y + 0.16, -0.75), (0.075, 0.075, 0.075), 'iron', C_IRON, 8, 5)

def build_props_hold(mb):
    y = HOLD_Y
    barrel(mb, (-0.52, y, -3.5), 0.33, 0.9); barrel(mb, (0.18, y, -3.85), 0.33, 0.9, tone=C_DARK); barrel(mb, (0.7, y, -3.25), 0.3, 0.85)
    barrel(mb, (-0.17, y + 0.9, -3.7), 0.27, 0.75, band=C_BRASS)
    barrel(mb, (0.8, y + 0.31, -2.75), 0.3, 0.85, R('Y', 20) @ R('X', 90))          # one on its side
    crate(mb, (-0.85, y, -2.5), (0.7, 0.6, 0.7), R('Y', 8)); crate(mb, (-0.82, y + 0.6, -2.52), (0.5, 0.4, 0.5), R('Y', -15), C_HULL)
    rope_coil(mb, (0.0, y, 0.25), 0.25, 3)
    # hammock slung fore and aft along the port side of the cabin
    pts = [(-1.2, 0.72, 3.25), (-1.12, 0.42, 3.7), (-1.1, 0.3, 4.2), (-1.05, 0.42, 4.7), (-0.95, 0.72, 5.1)]
    secs = [[Vector(q) + Vector((-0.3 if i not in (0, 4) else -0.02, 0.0 if i in (0, 4) else 0.1, 0)), Vector(q), Vector(q) + Vector((0.3 if i not in (0, 4) else 0.02, 0.0 if i in (0, 4) else 0.1, 0))] for i, q in enumerate(pts)]
    loft(mb, secs, 'cloth', srgb('#e9dcb8'), False, (False, False), 'smooth', flip=False)
    build_cabin(mb)

def build_cabin(mb):
    """The stern cabin under the quarterdeck: window seat with cushions, sea chest, rug, stool, curtains."""
    rng = mb.rng; y = HOLD_Y; seat = y + 0.5
    poly = deck_outline(y + 0.2, seat, 5.3, 6.12, 6, 1.0, inner=True)
    prism(mb, poly, y - 0.02, seat, 'wood', jit(C_HULL, rng, 0.06), 0.02, (1, 0, 0))
    cush = [(x * 0.86, 5.36 + (z - 5.3) * 0.82) for x, z in poly]
    prism(mb, cush, seat, seat + 0.09, 'cloth', C_RED, 0.03, (1, 0, 0))
    for sx in (-0.25, 0.25):
        ellipsoid(mb, (sx, seat + 0.2, 5.75), (0.2, 0.12, 0.16), 'cloth', C_TEAL if sx < 0 else C_GOLD, 8, 5, R('Y', sx * 60))
    cbox(mb, (0, y + 0.004, 3.95), (1.25, 0.008, 1.15), 'cloth', C_CREAM, 0.0); cbox(mb, (0, y + 0.01, 3.95), (1.05, 0.008, 0.95), 'cloth', C_RED, 0.0)
    cbox(mb, (0, y + 0.016, 3.95), (0.5, 0.008, 0.45), 'cloth', C_GOLD, 0.0, None, R('Y', 45))
    with xf(mb, T(0.42, y, 4.75) @ R('Y', -12)):                                # sea chest
        cbox(mb, (0, 0.17, 0), (0.62, 0.34, 0.4), 'wood', C_DARK, 0.02, (1, 0, 0))
        with xf(mb, T(0, 0.34, 0) @ M_Y2X @ S(1, 1, 1)):
            lathe(mb, [(0, -0.31), (0.2, -0.31), (0.2, 0.31), (0, 0.31)], 12, 'wood', C_HULL, True)
        for sx in (-0.2, 0.2):
            cbox(mb, (sx, 0.19, 0), (0.05, 0.4, 0.42), 'brass', C_BRASS, 0.008)
        cbox(mb, (0, 0.3, -0.21), (0.08, 0.1, 0.03), 'brass', C_BRASS, 0.008)
    with xf(mb, T(-0.42, y, 4.7)):                                              # stool
        lathe(mb, [(0, 0.4), (0.17, 0.4), (0.17, 0.45), (0, 0.45)], 10, 'wood', C_HULL)
        for k in range(3):
            a = 2 * pi * k / 3
            tube(mb, [(0.08 * cos(a), 0.4, 0.08 * sin(a)), (0.16 * cos(a), 0, 0.16 * sin(a))], 0.025, 5, 'wood', C_DARK)
    ang = math.degrees(math.atan(0.2))                                          # curtains inside the stern windows
    with xf(mb, T(0, 1.1, 6.5) @ R('X', ang)):
        yy = lambda v: (v - 1.1) / cos(radians(ang))
        tube(mb, [(-1.3, yy(1.42), -0.24), (1.3, yy(1.42), -0.24)], 0.018, 5, 'brass', C_BRASS)
        for cx in (-1.26, -0.43, 0.43, 1.26):
            for i in range(3):
                cbox(mb, (cx + (i - 1) * 0.055, yy(1.02), -0.235 - 0.012 * (i % 2)), (0.06, yy(1.42) - yy(0.62), 0.02), 'cloth', jit(C_RED, rng, 0.08), 0.008)

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
    lathe(mb, [(0.3, D), (0.38, D), (0.38, D + 0.1), (0.33, D + 0.22), (0.3, D + 0.22)], 16, 'wood', C_RED)       # mast coat
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
    heel = Vector(BS_HEEL); tip = Vector(BS_TIP)
    n = 6; path = [heel.lerp(tip, i / n) for i in range(n + 1)]
    tube(mb, path, [0.17 - 0.07 * i / n for i in range(n + 1)], 12, 'wood', mul(C_DECK, 0.95))
    d = (tip - heel).normalized()
    for f in (0.34, 0.97):
        p = heel.lerp(tip, f); r = 0.17 - 0.07 * f + 0.015
        tube(mb, [p - d * 0.06, p + d * 0.06], r, 12, 'iron' if f < 0.9 else 'brass', C_IRON if f < 0.9 else C_BRASS, mode='len')
    # bitts holding the heel
    for sg in (-1, 1):
        cbox(mb, (sg * 0.3, (DECK_Y + 2.9) / 2, -5.4), (0.2, 2.9 - DECK_Y, 0.2), 'wood', C_RED, 0.035, (0, 1, 0))
    cbox(mb, (0, 2.76, -5.4), (0.9, 0.16, 0.16), 'wood', C_DARK, 0.03)
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
        for k, z in enumerate((0.76, 1.03, 1.3)):          # chainplates well aft so the yard clears the shrouds at full trim
            s = s_of_z(z); p, nh = rail_frame(s)
            bot = Vector((sg * (p.x + 0.04), p.y + 0.12, z)); top = Vector((sg * 0.1, 10.42, MAST_Z + 0.28 + 0.02 * k))
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
    tip = Vector(BS_TIP); mid = Vector(BS_HEEL).lerp(tip, 0.34)
    tube(mb, [(0, MAST_TOP - 0.35, MAST_Z - 0.08), tip + Vector((0, 0.1, 0.1))], 0.03, 5, 'rope', C_ROPE_D)       # forestay
    tube(mb, [(0, 11.7, MAST_Z - 0.2), mid + Vector((0, 0.19, 0))], 0.03, 5, 'rope', C_ROPE_D)                   # inner stay (set high: the yard swings under it)
    for sg in (-1, 1):                                                                                            # backstays
        s = 2.0; p, nh = rail_frame(s)
        tube(mb, [(sg * 0.08, MAST_TOP - 0.5, MAST_Z + 0.08), (sg * (p.x - 0.05), p.y + 0.95, p.z)], 0.028, 5, 'rope', C_ROPE_D)

def build_yard(mb):
    y = YARD_Y; z = MAST_Z - YARD_FWD; n = 8
    path = [(-3.25 + 6.5 * i / n, y, z) for i in range(n + 1)]
    rad = [0.075 + 0.06 * (1 - abs(2 * i / n - 1) ** 1.5) for i in range(n + 1)]
    tube(mb, path, rad, 10, 'wood', mul(C_DECK, 0.85))
    for sg in (-1, 1):
        tube(mb, [(sg * 3.19, y, z), (sg * 3.3, y, z)], 0.095, 10, 'wood', C_RED, mode='len')
        tube(mb, [(sg * 0.5, y, z), (sg * 0.62, y, z)], 0.15, 10, 'iron', C_IRON, mode='len')
    cbox(mb, (0, y, MAST_Z - 0.34), (0.42, 0.26, 0.26), 'wood', C_DARK, 0.03)
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
    z = MAST_Z - YARD_FWD - 0.02 - belly - scallop
    return Vector((x, y, z))

def sail_weight_at(p):
    """(billow weight, distance down the sail 0..1) for a point on or near the set sail. Weight is 0 at the yard and the
    side bolt ropes, about 1 in the belly, and eases off towards the foot so the clews stay put."""
    head_y = YARD_Y - 0.13; yn = 0.5; xn = 0.0
    for _ in range(4):
        xn = max(-1.0, min(1.0, p.x / (3.05 + 0.2 * yn)))
        yn = max(0.0, min(1.0, (head_y - p.y) / (head_y - (3.35 + 0.4 * (1 - xn * xn)))))
    w = (1 - abs(xn) ** 4) * smooth01(yn / 0.3) * (1 - 0.35 * smooth01((yn - 0.8) / 0.2))
    return (w, yn)

def build_sail(mb):
    nx, ny = 32, 20
    mb.wfn = sail_weight_at
    pts = [[sail_point(-1 + 2 * i / nx, j / ny) for i in range(nx + 1)] for j in range(ny + 1)]
    front = [[mb.v(q) for q in row] for row in pts]
    back = [[mb.v(q + Vector((0, 0, 0.014))) for q in row] for row in pts]
    for j in range(ny):
        for i in range(nx):
            uvs = [(i / nx, 1 - j / ny), ((i + 1) / nx, 1 - j / ny), ((i + 1) / nx, 1 - (j + 1) / ny), (i / nx, 1 - (j + 1) / ny)]
            sh = [mix(C_WHITE, (0.80, 0.78, 0.74), 0.5 * abs(-1 + 2 * ii / nx) ** 3 + 0.25 * (jj / ny) ** 2) for ii, jj in ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))]
            mb.f([front[j][i], front[j][i + 1], front[j + 1][i + 1], front[j + 1][i]], 'canvas', sh, uvs, True)
            mb.f([back[j][i], back[j][i + 1], back[j + 1][i + 1], back[j + 1][i]][::-1], 'canvas_back', sh[::-1], uvs[::-1], True)
    # bolt rope round the edge
    edge = [sail_point(-1, j / ny) for j in range(ny + 1)] + [sail_point(-1 + 2 * i / nx, 1) for i in range(1, nx + 1)] + [sail_point(1, 1 - j / ny) for j in range(1, ny + 1)]
    tube(mb, [q + Vector((0, 0, 0.007)) for q in edge], 0.032, 5, 'rope', C_ROPE, (True, True), 'smooth')
    for sg in (-1, 1):                                                      # clew cringles
        with xf(mb, T(sail_point(sg, 1) + Vector((sg * 0.05, -0.05, 0.0))) @ M_Y2Z): torus(mb, 0.06, 0.02, 8, 4, 'iron', C_IRON)

def build_flag(mb, nx=24, ny=8):
    top = MAST_TOP - 0.12; h = 1.15; L = 2.3
    mb.wfn = lambda p: (max(0.0, min(1.0, (MAST_Z - 0.1 - p.z) / (L * 0.95))), max(0.0, min(1.0, (top - p.y) / h)))   # weight grows toward the fly
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

def rope_object(name, a, b):
    """Running rigging for runtime animation: a unit-length rope along local +Z with its origin at one end. Posed from a to b
    here; game code re-aims and re-scales it (Z scale = length) between the two documented empties every frame."""
    a = Vector(a); b = Vector(b); d = b - a; L = d.length; z = d / L
    x = Vector((0, 1, 0)).cross(z)
    if x.length < 1e-4: x = Vector((1, 0, 0))
    x.normalize(); y = z.cross(x)
    mb = MB(name)
    tube(mb, [(0, 0, 0), (0, 0, 0.5), (0, 0, 1)], 0.022, 6, 'rope', C_ROPE)
    mb.gmatrix = Matrix(((x.x, y.x, d.x, a.x), (x.y, y.y, d.y, a.y), (x.z, y.z, d.z, a.z), (0, 0, 0, 1)))
    build(mb)

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
        for i in range(4):                                                    # short chain up to the cathead
            with xf(mb, T(0, 0.2 + 0.085 * i, 0) @ (M_Y2X if i % 2 else M_Y2Z)):
                torus(mb, 0.045, 0.014, 8, 4, 'iron', C_IRON)
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

CANNON_TRUNNION = (0.05, 0.62, 0.0)
def build_cannon(mb, o, yaw):
    """Carriage (yaw pivot on the deck). Built pointing +X, then yawed."""
    with xf(mb, T(o) @ R('Y', yaw)):
        for sz in (-1, 1):
            with xf(mb, T(0, 0, sz * 0.25)):
                with xf(mb, Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))):   # local (x, y, z) -> world (x, z, -y)
                    prism(mb, [(-0.56, 0.2), (0.5, 0.2), (0.5, 0.56), (0.2, 0.62), (-0.06, 0.62), (-0.56, 0.36)], -0.055, 0.055, 'wood', C_RED, 0.012, (1, 0, 0))
            cbox(mb, (0.05, 0.63, sz * 0.25), (0.2, 0.035, 0.12), 'iron', C_IRON, 0.008)                 # cap squares over the trunnions
        cbox(mb, (-0.03, 0.2, 0), (1.0, 0.09, 0.42), 'wood', mul(C_RED, 0.85), 0.02)
        cbox(mb, (-0.42, 0.3, 0), (0.12, 0.14, 0.4), 'wood', C_DARK, 0.02)                               # quoin block under the breech
        for sx in (-0.34, 0.32):
            cbox(mb, (sx, 0.15, 0), (0.13, 0.13, 0.84), 'wood', C_DARK, 0.02)
            for sz in (-1, 1):
                with xf(mb, T(sx, 0.15, sz * 0.4) @ M_Y2Z):
                    cyl(mb, 0.155, -0.055, 0.055, 14, 'wood', C_DARK, True, 0.02)
                    cyl(mb, 0.05, -0.07, 0.07, 6, 'iron', C_IRON)
        for sz in (-1, 1):                                                                               # breeching rope ring bolts
            with xf(mb, T(-0.5, 0.3, sz * 0.3) @ M_Y2X):
                torus(mb, 0.05, 0.014, 8, 4, 'iron', C_IRON)

def build_cannon_barrel(mb, o, yaw):
    """Barrel with its origin on the trunnion axis (pitch pivot)."""
    with xf(mb, T(o) @ R('Y', yaw)):
        with xf(mb, T(CANNON_TRUNNION) @ M_Y2X):
            k = 1.12
            prof = [(0, -0.9), (0.06, -0.89), (0.085, -0.84), (0.05, -0.78), (0.19, -0.75), (0.215, -0.7), (0.215, -0.64), (0.19, -0.62), (0.185, -0.3), (0.205, -0.28), (0.205, -0.21), (0.175, -0.19),
                    (0.15, 0.5), (0.168, 0.52), (0.168, 0.58), (0.14, 0.6), (0.132, 0.9), (0.175, 0.95), (0.18, 1.04), (0.165, 1.07), (0.1, 1.07), (0.1, 0.85), (0, 0.85)]
            brass_seg = {8, 9, 10, 12, 13, 14, 16, 17, 18, 19}
            for i in range(len(prof) - 1):
                seg = [(prof[i][0] * k, prof[i][1]), (prof[i + 1][0] * k, prof[i + 1][1])]
                isb = i in brass_seg
                lathe(mb, seg, 16, 'brass' if isb else 'iron', C_BRASS if isb else (C_BLACK if i >= 20 else C_IRON))
            with xf(mb, T(0, -0.66, 0.0)):
                cbox(mb, (0, 0, -0.245), (0.03, 0.03, 0.04), 'iron', C_BLACK, 0.005)                     # touch hole
        with xf(mb, T(CANNON_TRUNNION) @ M_Y2Z):
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

def build_powder_keg(mb, o):
    barrel(mb, o, 0.2, 0.46, tone=C_DARK, band=C_BRASS)
    with xf(mb, T(o)):
        lathe(mb, [(0.2, 0.17), (0.212, 0.17), (0.212, 0.29), (0.2, 0.29)], 12, 'paint', C_RED, False)
        cyl(mb, 0.035, 0.44, 0.5, 6, 'wood', C_CREAM)                           # bung

def build_sail_furled(mb):
    """The mainsail gathered up under the yard and tied with gaskets. Same origin as Sail: show one, hide the other."""
    n = 36; segs = 10; z0 = MAST_Z - YARD_FWD - 0.04; ids = []
    for i in range(n + 1):
        xn = -1 + 2 * i / n; x = xn * 3.05
        r = 0.2 + 0.035 * sin(i * 1.7) + 0.025 * cos(i * 0.9)
        g = abs(((i + 3) % 6) - 3) / 3.0                                       # 1 at a gasket, 0 between
        r *= (1 - 0.3 * g ** 3) * (1 - 0.5 * abs(xn) ** 6)
        yc = YARD_Y - 0.2 - r * 0.75 - 0.05 * (1 - g)
        ring = []
        for k in range(segs):
            a = 2 * pi * k / segs
            ring.append(mb.v((x, yc + r * 1.15 * cos(a) + 0.02 * sin(a * 3 + i), z0 + r * sin(a) * 0.95)))
        ids.append(ring)
    def col(k):
        sh = 0.80 + 0.2 * (0.5 + 0.5 * cos(2 * pi * k / segs)); return (sh, sh * 0.985, sh * 0.96)
    for i in range(n):
        for k in range(segs):
            k1 = (k + 1) % segs
            uv = lambda ii, kk: (0.03 + 0.94 * ii / n, 0.845 + 0.13 * kk / segs)
            mb.f([ids[i][k], ids[i][k1], ids[i + 1][k1], ids[i + 1][k]], 'canvas', [col(k), col(k + 1), col(k + 1), col(k)], [uv(i, k), uv(i, k + 1), uv(i + 1, k + 1), uv(i + 1, k)], True)
    for ring, ii in ((ids[0], 0), (ids[-1], n)):
        mb.f(ring if ii else ring[::-1], 'canvas', (0.85, 0.83, 0.8), [(0.5, 0.9)] * segs, False)
    for i in range(3, n, 6):                                                   # gaskets round sail and yard
        x = (-1 + 2 * i / n) * 3.05
        pts = [(x, YARD_Y - 0.14 + 0.29 * cos(a * pi / 6), z0 + 0.03 + 0.2 * sin(a * pi / 6)) for a in range(13)]
        tube(mb, pts, 0.022, 4, 'rope', C_ROPE, (False, False))

def build_bell(mb, o):
    x, y, z = o
    cbox(mb, (x + 0.2, y + 0.06, z), (0.5, 0.06, 0.06), 'iron', C_IRON, 0.012)
    hexa(mb, [(x + 0.42, y - 0.3, z - 0.025), (x + 0.36, y - 0.3, z - 0.025), (x + 0.36, y - 0.3, z + 0.025), (x + 0.42, y - 0.3, z + 0.025),
              (x + 0.42, y + 0.04, z - 0.025), (x + 0.12, y + 0.04, z - 0.025), (x + 0.12, y + 0.04, z + 0.025), (x + 0.42, y + 0.04, z + 0.025)], 'iron', C_IRON)
    with xf(mb, T(o)):
        lathe(mb, [(0, 0.02), (0.03, 0.02), (0.035, -0.02), (0.06, -0.05), (0.1, -0.09), (0.12, -0.2), (0.135, -0.29), (0.17, -0.34), (0.175, -0.37), (0.15, -0.37), (0.12, -0.3), (0.1, -0.2), (0, -0.12)], 14, 'brass', C_BRASS)
        tube(mb, [(0, -0.12, 0), (0, -0.33, 0)], 0.012, 4, 'iron', C_IRON)
        ellipsoid(mb, (0, -0.35, 0), (0.035, 0.035, 0.035), 'iron', C_IRON, 6, 4)
        tube(mb, [(0, -0.37, 0), (0.0, -0.55, 0.02), (0.01, -0.62, 0.02)], 0.014, 4, 'rope', C_ROPE)

def build_bucket(mb, o):
    rng = mb.rng; cols = [jit(C_HULL, rng, 0.14) for _ in range(10)]
    with xf(mb, T(o)):
        lathe(mb, [(0, 0), (0.13, 0), (0.165, 0.3), (0.145, 0.3), (0.118, 0.03), (0, 0.03)], 10, 'wood', C_HULL, False, False, lambda i, k: mul(cols[k], 0.7 if i >= 3 else 1.0))
        for yy, rr in ((0.06, 0.142), (0.24, 0.163)):
            lathe(mb, [(rr - 0.01, yy - 0.02), (rr + 0.006, yy - 0.02), (rr + 0.006, yy + 0.02), (rr - 0.01, yy + 0.02)], 10, 'iron', C_IRON, False)
        tube(mb, [(0.155 * cos(a * pi / 8), 0.28 + 0.16 * sin(a * pi / 8), 0.02) for a in range(9)], 0.013, 4, 'rope', C_ROPE)

def build_plank_stack(mb, o):
    rng = mb.rng
    with xf(mb, T(o)):
        for sz in (-0.5, 0.5):
            cbox(mb, (0, 0.03, sz), (0.6, 0.06, 0.08), 'wood', C_DARK, 0.012)
        for layer in range(4):
            for i in range(3 if layer < 3 else 2):
                cbox(mb, (-0.18 + 0.18 * i + rng.uniform(-0.015, 0.015) + (0.09 if layer == 3 else 0), 0.085 + layer * 0.05, rng.uniform(-0.06, 0.06)), (0.165, 0.045, 1.5 + rng.uniform(-0.1, 0.1)),
                     'wood', jit(C_DECK, rng, 0.12), 0.01, None, R('Y', rng.uniform(-2, 2)))
        with xf(mb, T(0.05, 0.285, 0.3) @ R('Y', 35)):                           # mallet on top
            cbox(mb, (0, 0.04, 0), (0.1, 0.08, 0.2), 'wood', C_DARK, 0.015)
            cbox(mb, (0.18, 0.04, 0), (0.3, 0.035, 0.035), 'wood', C_HULL, 0.008)

def build_hatch_cover(mb, o, sg):
    """Grating leaf hinged on the outer edge of the hatch coaming, shown open (standing). Local +Z is the hinge line."""
    hx0, hx1, hz0, hz1 = HATCH; L = hz1 - hz0 + 0.1; W = hx1 + 0.12
    with xf(mb, T(o) @ S(sg, 1, 1) @ R('Z', -12)):
        for yy in (0.04, W - 0.04):
            cbox(mb, (0, yy, 0), (0.06, 0.08, L), 'wood', C_DARK, 0.015)
        for zz in (-L / 2 + 0.04, 0, L / 2 - 0.04):
            cbox(mb, (0, W / 2, zz), (0.062, W, 0.08), 'wood', C_DARK, 0.015)
        nsl = 5
        for i in range(nsl):
            cbox(mb, (0.0, 0.08 + (W - 0.16) * (i + 0.5) / nsl, 0), (0.035, 0.06, L - 0.1), 'wood', jit(C_DECK, mb.rng, 0.1), 0.01)
        for zz in (-L / 2 + 0.25, L / 2 - 0.25):
            cbox(mb, (-0.035, 0.03, zz), (0.02, 0.1, 0.12), 'iron', C_IRON, 0.004)                 # hinge straps

def build_bilge(mb, c):
    x, y, z = c
    for (cx, cz, sx, sz) in ((0, -0.33, 0.74, 0.08), (0, 0.33, 0.74, 0.08), (-0.33, 0, 0.08, 0.58), (0.33, 0, 0.08, 0.58)):
        cbox(mb, (x + cx, y + 0.03, z + cz), (sx, 0.07, sz), 'wood', C_DARK, 0.015)
    cbox(mb, (x, y + 0.006, z), (0.6, 0.012, 0.6), 'paint', srgb('#0b2a33'), 0.0)                    # dark bilge water glimpsed below
    for i in range(5):
        cbox(mb, (x - 0.24 + 0.12 * i, y + 0.035, z), (0.05, 0.035, 0.6), 'wood', jit(C_INNER, mb.rng, 0.1), 0.008)
    for i in range(2):
        cbox(mb, (x, y + 0.02, z - 0.15 + 0.3 * i), (0.6, 0.03, 0.05), 'wood', C_DARK, 0.006)

def build_holes():
    """Damage set per hole position: HullPanel_NN (the intact planking, shown by default), Hole_NN (the same planking with a
    real splintered breach through it; swap it in for the panel) and HolePatch_NN (planks nailed over from inside)."""
    for P in PANELS:
        idx = P['idx']; sg = P['side']; jb = P['jb']
        build(P['mb'])
        hb = MB('Hole_%02d' % (idx + 1), P['origin'], seed=idx, yaw=P['yaw']); rng = hb.rng
        lo = (VS[jb] - VS[jb - 1]) * P['mpv']; hi = (VS[jb + 1] - VS[jb]) * P['mpv']        # strake heights in metres
        def pt(a, b, depth):
            u = umap(P['sc'] + a / P['mps']); v = P['v'] + b / P['mpv']
            q = hull_pt(u, v) - hull_n(u, v) * depth; q.x = max(q.x, 0.0); return q
        K = 24; ra = 0.27; rb = min(0.2, 0.74 * min(lo, hi))
        ang = [2 * pi * k / K for k in range(K)]
        rad = []
        for k, t in enumerate(ang):
            r = 1.0 / sqrt((cos(t) / ra) ** 2 + (sin(t) / rb) ** 2)
            rad.append(r * (0.62 + 0.5 * rng.random()) * (1.12 if k % 3 == 0 else 0.92))
        H = [(rad[k] * cos(t), rad[k] * sin(t)) for k, t in enumerate(ang)]
        def edge(t):
            c, sn = cos(t), sin(t)
            f = min(PANEL_HALF / abs(c) if abs(c) > 1e-9 else 1e9, (hi if sn > 0 else lo) / abs(sn) if abs(sn) > 1e-9 else 1e9)
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
                for depth, cc, face in ((-extra, colr, 1), (TH, inner, -1)):
                    poly = [pt(H[k][0], H[k][1], depth)] + [pt(a, b, depth) for a, b in ring] + [pt(H[k1][0], H[k1][1], depth)]
                    hb.fp(poly, 'wood', cc, tu, c0)
                wall = [pt(H[k][0], H[k][1], -extra), pt(H[k1][0], H[k1][1], -extra), pt(H[k1][0], H[k1][1], TH), pt(H[k][0], H[k][1], TH)]
                mid = pt((H[k][0] + H[k1][0]) * 0.8, (H[k][1] + H[k1][1]) * 0.8, TH / 2)      # a point outside the hole wall
                hb.fp(wall, 'wood', jit(splinter, rng, 0.12), tu, mid)
                if rng.random() < 0.45:                                                       # a splinter bent into the hold
                    a = pt(H[k][0], H[k][1], TH); b = pt(H[k1][0], H[k1][1], TH)
                    tip = pt(H[k][0] * 0.55, H[k][1] * 0.55, TH + rng.uniform(0.05, 0.16))
                    hb.fp([a, b, tip], 'wood', splinter, tu, c0); hb.fp([b, a, tip], 'wood', mul(splinter, 0.75), tu, tip + (tip - c0))
        build(hb)
        pb = MB('HolePatch_%02d' % (idx + 1), P['origin'], seed=idx, yaw=P['yaw']); rng = pb.rng
        p = pt(0, 0, 0); n = (pt(0, 0, 0) - pt(0, 0, 0.1)).normalized(); tv = n.cross(tu)
        if tv.y < 0: tv = -tv
        c = p - n * (TH + 0.155)
        M = Matrix(((tu.x, tv.x, -n.x, c.x), (tu.y, tv.y, -n.y, c.y), (tu.z, tv.z, -n.z, c.z), (0, 0, 0, 1)))
        with xf(pb, S(sg, 1, 1) @ M):
            for i in range(4):
                yy = -0.27 + 0.18 * i + rng.uniform(-0.01, 0.01); L = 0.86 + rng.uniform(-0.08, 0.12); rz = rng.uniform(-7, 7)
                with xf(pb, T(rng.uniform(-0.06, 0.06), yy, 0.006 * (i % 2)) @ R('Z', rz)):
                    cbox(pb, (0, 0, 0), (L, 0.17, 0.04), 'wood', jit(mix(C_DECK, C_CREAM, 0.25), rng, 0.14), 0.012)
                    for sx in (-1, 1):
                        cbox(pb, (sx * (L / 2 - 0.07), 0.0, 0.024), (0.03, 0.03, 0.012), 'iron', C_IRON, 0.004)
        build(pb)

def extras(hull):
    """Everything the mechanics need as separate, pivot-correct parts beyond the first-pass fittings."""
    sf = MB('Sail_Furled', (0, YARD_Y, MAST_Z)); build_sail_furled(sf); build(sf)
    o = (-0.62, 2.9, MAST_Z); b = MB('Bell', o); build_bell(b, o); build(b)
    bc = (0.0, HOLD_Y, -2.1)
    o = (0.52, HOLD_Y, -1.75); bk = MB('Bucket', o); build_bucket(bk, o); hull.merge(bk); empty_anchor('Bucket', o)
    o = (0.0, HOLD_Y, 1.25); ps = MB('PlankStack', o); build_plank_stack(ps, o); hull.merge(ps); empty_anchor('PlankStack', o)
    hx0, hx1, hz0, hz1 = HATCH
    for name, sg in (('HatchCover_Starboard', 1), ('HatchCover_Port', -1)):
        o = (sg * (hx1 + 0.13), DECK_Y + 0.21, (hz0 + hz1) / 2 - 0.05); h = MB(name, o); build_hatch_cover(h, o, sg); build(h)
    build_holes()
    # where the sea surface must be cut away inside the hull (hide like col_*; for the ocean shader/stencil)
    # Trace at y = +0.50 m so the flared stern transom stays watertight even when pitching with bilge water.
    wm = MB('mask_water'); poly = deck_outline(0.50, 0.50, -6.32, zstern(0.50) - 0.02, 20, 1.3, 0.02)
    wm.newoff(); wm.fp([(x, 0.0, z) for x, z in poly], 'col', C_WHITE, None, (0, -5, 0)); build(wm)

def rig_clearance():
    """Smallest gap (surface to surface) between the yard and the standing rigging over the whole +-1.2 rad trim range."""
    segs = [(b, t, 0.032) for _, _, b, t in shroud_pts()]
    tip = Vector(BS_TIP); mid = Vector(BS_HEEL).lerp(tip, 0.34)
    segs += [(Vector((0, MAST_TOP - 0.35, MAST_Z - 0.08)), tip, 0.03), (Vector((0, 11.7, MAST_Z - 0.2)), mid, 0.03)]
    for sg in (-1, 1):
        p, _ = rail_frame(2.0); segs.append((Vector((sg * 0.08, MAST_TOP - 0.5, MAST_Z + 0.08)), Vector((sg * (p.x - 0.05), p.y + 0.95, p.z)), 0.028))
    best = 9.0
    for i in range(97):
        th = -1.2 + 2.4 * i / 96
        for k in range(81):
            x = -3.3 + 6.6 * k / 80; r = 0.075 + 0.06 * (1 - abs(x / 3.25) ** 1.5) if abs(x) < 3.25 else 0.095
            q = Vector((x * cos(th) - YARD_FWD * sin(th), YARD_Y, MAST_Z - x * sin(th) - YARD_FWD * cos(th)))
            for a, b, rr in segs:
                d = b - a; f = max(0.0, min(1.0, (q - a).dot(d) / d.dot(d)))
                best = min(best, (q - (a + d * f)).length - r - rr)
    return best

# ---------------------------------------------------------------- collision
def col_wall(name, s0, s1, y0, y1fn, thick=TH, extra_out=0.0, ns=3, ny=3):
    for sg, tag in ((1, 'S'), (-1, 'P')):
        pts = []
        for i in range(ns):
            s = s0 + (s1 - s0) * i / (ns - 1); u = umap(s); yt = y1fn(hull_pt(u, 1.0).z, u)
            for j in range(ny):
                y = y0 + (yt - y0) * j / (ny - 1); v = v_of_y(u, y)
                p = hull_pt(u, min(v, 1.0)); n = hull_n(u, min(v, 1.0))
                if v > 1.0: p.y = y; n = Vector((n.x, 0, n.z)).normalized()      # rails stand straight up from the hull top
                a = p + n * extra_out; b = p - n * (hull_th(p.y) if thick == TH else thick); b.x = max(b.x, 0.0)
                pts += [(sg * a.x, a.y, a.z), (sg * b.x, b.y, b.z)]
        col_piece('col_%s_%s' % (name, tag), pts)

def build_collision():
    # hull below the hold floor
    zb = [6.25, 4.2, 1.8, -0.6, -3.0, -4.6, -5.75]
    for i in range(len(zb) - 1):
        pts = []
        for z in (zb[i], (zb[i] + zb[i + 1]) / 2, zb[i + 1]):
            for y in (-1.0, (HOLD_Y - 1.0) / 2, HOLD_Y - 0.005):
                x = hull_b(z, y)
                if z > zstem(y) + 0.01: pts += [(x, y, z), (-x, y, z)]
            if z > -3.6: pts += [(0.12, -1.2, z), (-0.12, -1.2, z)]
            elif z > zstem(-0.95): pts += [(0, -1.0, z)]
        if len(pts) >= 4: col_piece('col_hull_bottom_%d' % i, pts)
    # hull sides from the hold floor to the deck in three bands, so the convex pieces hug the curved planking and the hold stays hollow
    zs = [6.6, 5.4, 4.2, 2.8, 1.2, -0.4, -2.0, -3.6, -4.9, -5.8, -6.45]
    bands = [('low', HOLD_Y - 0.03, -0.45), ('mid', -0.45, 0.2), ('high', 0.2, DECK_Y - 0.02)]
    for i in range(len(zs) - 1):
        s0, s1 = (0.0 if i == 0 else s_of_z(zs[i], 0.45)), s_of_z(zs[i + 1], 0.45)
        for nm, ya, yb in bands:
            col_wall('hull_side_%s_%d' % (nm, i), s0, s1, ya, lambda z, u, yb=yb: yb)
    # bulwarks and rails, leaving the gun ports and ladder gaps open
    sq = s_of_z(QDECK_Z)
    def top(z, u): return ytop(z) + (0.65 if z > QDECK_Z - 0.01 else 0.12)
    k = 0
    for (a, b) in top_intervals(NS - 0.5):
        cuts = [a] + [c for c in (sq, s_of_z(4.8), s_of_z(-3.3), s_of_z(-4.8), s_of_z(-5.8)) if a + 0.5 < c < b - 0.5] + [b]
        cuts.sort()
        for i in range(len(cuts) - 1):
            col_wall('rail_%d' % k, cuts[i], cuts[i + 1], DECK_Y - 0.02, top, 0.2); k += 1
    # stem
    col_piece('col_stem', [(sx * 0.13, y, zstem(y) + dz) for y in (-0.6, 0.3, 1.2, 2.66) for sx in (-1, 1) for dz in (-0.25, 0.3)])
    # transom + taffrail
    pts = []
    yt = ytop(6.5) + 0.65
    for y in (YT, 0.2, 0.7, 1.4, 2.0, yt):
        for sg in (-1, 1):
            for dz in (0.03, -0.16): pts.append((sg * max(wtrans(y), 0.12), y, zstern(y) + dz))
    col_piece('col_transom', pts)
    # decks
    main = deck_outline(DECK_Y - 0.1, DECK_Y, -6.52, QDECK_Z + 0.1)
    hx0, hx1, hz0, hz1 = HATCH; qx0, qx1, qz0, qz1 = QSTAIR
    def slab(name, poly, y0, y1):
        if poly: col_piece(name, [(x, y, z) for x, z in poly for y in (y0, y1)])
    slab('col_deck_main_fore', clip_rect(main, -9, 9, -7, hz0), DECK_Y - 0.1, DECK_Y)
    slab('col_deck_main_port', clip_rect(main, -9, hx0, hz0, hz1), DECK_Y - 0.1, DECK_Y)
    slab('col_deck_main_starboard', clip_rect(main, hx1, 9, hz0, hz1), DECK_Y - 0.1, DECK_Y)
    slab('col_deck_main_aft', clip_rect(main, -9, 9, hz1, QDECK_Z + 0.1), DECK_Y - 0.1, DECK_Y)
    zq1 = zstern(QDECK_Y) - 0.1
    quarter = deck_outline(QDECK_Y - 0.1, QDECK_Y, QDECK_Z - 0.06, zq1, 10, 1.0)
    slab('col_quarterdeck_fore', clip_rect(quarter, -qx0, qx0, QDECK_Z - 0.06, qz1), QDECK_Y - 0.1, QDECK_Y)
    slab('col_quarterdeck_aft', clip_rect(quarter, -9, 9, qz1, 9), QDECK_Y - 0.1, QDECK_Y)
    slab('col_hold_floor', deck_outline(HOLD_Y - 0.06, HOLD_Y, -4.3, 5.75, 16, 1.0, inner=True), HOLD_Y - 0.1, HOLD_Y)
    # stairs as ramps (quarterdeck flights 35 degrees, hold flight 38)
    for sg, tag in ((1, 'S'), (-1, 'P')):
        col_piece('col_stairs_quarter_%s' % tag, [(sg * x, y, z) for x in (qx0, qx1) for (y, z) in ((DECK_Y, qz0), (DECK_Y - 0.1, qz0), (DECK_Y - 0.1, QDECK_Z + 0.05), (QDECK_Y - 0.4, qz1), (QDECK_Y, qz1))])
        col_piece('col_stairwell_%s' % tag, [(sg * x, y, z) for x in (qx0 - 0.08, qx0) for y in (DECK_Y - 0.1, QDECK_Y + 0.9) for z in (QDECK_Z, qz1 + 0.06)])
    zt, zbm = HOLD_STAIR[0] + 0.03, HOLD_STAIR[1]
    col_piece('col_stairs_hold', [(sx * 0.45, y + dy, z) for sx in (-1, 1) for (y, z) in ((DECK_Y, zt), (HOLD_Y, zbm)) for dy in (0.0, -0.16)])
    # quarterdeck break: bulkhead (above the main deck) and the front rail between the flights
    col_piece('col_bulkhead_quarter', [(sx * qx0, y, z) for sx in (-1, 1) for y in (DECK_Y - 0.1, QDECK_Y) for z in (QDECK_Z, QDECK_Z + 0.12)])
    col_piece('col_rail_quarter_front', [(sx * qx0, y, z) for sx in (-1, 1) for y in (QDECK_Y, QDECK_Y + 0.9) for z in (QDECK_Z - 0.03, QDECK_Z + 0.1)])
    hbk = hull_b(-4.3, DECK_Y - 0.1) - 0.1
    col_piece('col_bulkhead_hold', [(sx * x, y, -4.3 + dz) for sx in (-1, 1) for (x, y) in ((hull_b(-4.3, HOLD_Y) - 0.1, HOLD_Y), (hbk, DECK_Y - 0.1)) for dz in (-0.06, 0.06)])
    # mast, bowsprit
    col_piece('col_mast', [(0.3 * cos(k * pi / 4), y, MAST_Z + 0.3 * sin(k * pi / 4)) for k in range(8) for y in (HOLD_Y, 10.5)])
    col_piece('col_mast_top', [(r * cos(k * pi / 4), y, MAST_Z + r * sin(k * pi / 4)) for k in range(8) for (y, r) in ((10.5, 0.9), (11.5, 0.95))])
    col_piece('col_bowsprit', [(sx * 0.14, BS_HEEL[1] + dy + (BS_TIP[1] - BS_HEEL[1]) * f, BS_HEEL[2] + (BS_TIP[2] - BS_HEEL[2]) * f) for sx in (-1, 1) for dy in (-0.14, 0.14) for f in (0, 1)])

# ================================================================ distant LOD
def build_lod(outdir):
    """A few thousand triangles with the same silhouette and colours, for ships on the horizon. Sail, Yard and Flag stay
    separate objects with the same names and pivots so the same trim/furl code can drive them."""
    for ob in list(bpy.data.objects): bpy.data.objects.remove(ob, do_unlink=True)
    OBJS.clear()
    mb = MB('Hull'); NL = 16
    rows = [0, 3, J_CREAM, J_CREAM + 1, J_WALE, J_WALE + 1, J_SILL, len(YS) - 2, len(YS) - 1]
    ss = [NS * (i / NL) for i in range(NL)] + [NS - 0.05]
    for sg in (-1, 1):
        with xf(mb, S(sg, 1, 1)):
            for r in range(len(rows) - 1):
                colr, _ = strake_look(rows[r]) if rows[r + 1] - rows[r] == 1 or rows[r] == 0 else (C_HULL, 0)
                for i in range(len(ss) - 1):
                    zmid = hull_pt(umap((ss[i] + ss[i + 1]) / 2), 1.0).z
                    if rows[r] >= J_SILL and any(z0 < zmid < z1 for z0, z1 in GAPS): continue
                    q = [hull_pt(umap(ss[i]), VS[rows[r]]), hull_pt(umap(ss[i + 1]), VS[rows[r]]), hull_pt(umap(ss[i + 1]), VS[rows[r + 1]]), hull_pt(umap(ss[i]), VS[rows[r + 1]])]
                    c = sum(q, Vector()) / 4
                    mb.fp(q, 'paint', mul(colr, 0.92 + 0.08 * ((i + r) % 2)), None, (0, c.y, c.z))
                    if rows[r] > J_WALE:                                        # inside of the bulwark
                        mb.fp([Vector((p.x - 0.12, p.y, p.z)) for p in q], 'paint', mul(C_HULL, 0.8), None, (9, c.y, c.z))
            ss2 = ss[:-1] + [NS - 1.0]
            for i in range(len(ss2) - 1):                                       # cap rail
                a, na = rail_frame(ss2[i]); b, nb = rail_frame(ss2[i + 1])
                zmid = (a.z + b.z) / 2
                if any(z0 < zmid < z1 for z0, z1 in GAPS): continue
                mb.fp([a - na * 0.2 + Vector((0, 0.06, 0)), a + na * 0.06 + Vector((0, 0.06, 0)), b + nb * 0.06 + Vector((0, 0.06, 0)), b - nb * 0.2 + Vector((0, 0.06, 0))], 'paint', C_DARK, None, (0, -5, 0))
                if zmid > QDECK_Z:                                              # quarterdeck balustrade as a slatted band
                    up = Vector((0, 0.63, 0))
                    for inside in ((0, 0, zmid), (9, 0, zmid)):
                        mb.fp([a + up - Vector((0, 0.1, 0)), b + up - Vector((0, 0.1, 0)), b + up, a + up], 'paint', C_RED, None, inside)
                    for f in (0.0, 0.5):
                        m = a.lerp(b, f); cbox(mb, (m.x - 0.05, m.y + 0.32, m.z), (0.07, 0.52, 0.07), 'paint', C_CREAM, 0.0)
    # decks, bulkhead, transom
    main = deck_outline(DECK_Y, DECK_Y, -6.5, QDECK_Z, 10, 1.6, 0.1); quarter = deck_outline(QDECK_Y, QDECK_Y, QDECK_Z, zstern(QDECK_Y) - 0.1, 3, 1.0, 0.1)
    mb.fp([(x, DECK_Y, z) for x, z in main], 'paint', C_DECK, None, (0, -5, 0)); mb.fp([(x, QDECK_Y, z) for x, z in quarter], 'paint', C_DECK, None, (0, -5, 0))
    hb = hull_b(QDECK_Z, QDECK_Y) - 0.1
    mb.fp([(-hb, DECK_Y, QDECK_Z), (hb, DECK_Y, QDECK_Z), (hb, QDECK_Y, QDECK_Z), (-hb, QDECK_Y, QDECK_Z)], 'paint', C_TEAL, None, (0, 1.5, 9))
    yts = ytop(6.5)
    for (y0, y1, c) in ((YT, 0.12, C_TAR), (0.12, 0.54, C_HULL), (0.54, 1.46, C_TEAL), (1.46, yts - 0.14, C_HULL), (yts - 0.14, yts, C_RED)):
        mb.fp([(-wtrans(y0), y0, zstern(y0)), (wtrans(y0), y0, zstern(y0)), (wtrans(y1), y1, zstern(y1)), (-wtrans(y1), y1, zstern(y1))], 'paint', c, None, (0, 1, 0))
    for wx in (-0.86, 0, 0.86):
        mb.fp([(wx - 0.3, 0.66, zstern(0.66) + 0.02), (wx + 0.3, 0.66, zstern(0.66) + 0.02), (wx + 0.3, 1.34, zstern(1.34) + 0.02), (wx - 0.3, 1.34, zstern(1.34) + 0.02)], 'glass', C_GLASS, None, (0, 1, 0))
    with xf(mb, T(0, 2.03, zstern(2.03) + 0.01) @ M_Y2Z):
        lathe(mb, [(0, 0), (0.42, 0), (0, 0.06)], 8, 'paint', C_GOLD, False)
    yr = yts + 0.6
    cbox(mb, (0, yr, zstern(yts) - 0.05), (2 * wtrans(yts), 0.1, 0.12), 'paint', C_RED, 0.0)
    for i in range(5): cbox(mb, (-1.2 + 0.6 * i, yts + 0.3, zstern(yts) - 0.05), (0.08, 0.55, 0.08), 'paint', C_CREAM, 0.0)
    # keel, stem, rudder
    path = [(6.25, -1.0), (-3.4, -1.0)] + [(_SB[i][1], _SB[i][0]) for i in range(40, 241, 40)] + [(zstem(1.8), 1.8), (zstem(2.5), 2.5)]
    secs = []; scols = []
    for i, (z, y) in enumerate(path):
        a = path[max(i - 1, 0)]; b = path[min(i + 1, len(path) - 1)]
        t = Vector((b[0] - a[0], b[1] - a[1])).normalized(); n = Vector((-t.y, t.x))
        o = Vector((0, y + n.y * 0.22, z + n.x * 0.22)); q = Vector((0, y - n.y * 0.1, z - n.x * 0.1))
        secs.append([q + Vector((-0.13, 0, 0)), q + Vector((0.13, 0, 0)), o + Vector((0.13, 0, 0)), o + Vector((-0.13, 0, 0))]); scols.append(C_TAR if y < 0.12 else C_CREAM)
    loft(mb, secs, 'paint', C_TAR, True, (True, True), 'flat', scols=scols)
    box2(mb, (-0.07, -1.17, 6.3), (0.07, 0.4, 7.2), 'paint', C_HULL, 0.0)
    # mast, nest, bowsprit
    with xf(mb, T(0, 0, MAST_Z)):
        lathe(mb, [(0.3, DECK_Y), (0.24, 10.5), (0.15, 11.8), (0.09, MAST_TOP), (0, MAST_TOP + 0.2)], 6, 'paint', mul(C_DECK, 0.95))
        lathe(mb, [(0.24, 10.5), (0.8, 10.5), (0.93, 11.4), (0.97, 11.4), (0.97, 11.5), (0, 11.5)], 8, 'paint', C_HULL, False, False, lambda i, k: C_RED if i >= 2 else C_HULL)
        lathe(mb, [(0.25, 9.6), (0.8, 10.5)], 4, 'paint', C_DARK, False)
    tube(mb, [BS_HEEL, BS_TIP], [0.17, 0.1], 5, 'paint', mul(C_DECK, 0.95), mode='flat')
    # figurehead: white body, teal wings, orange beak
    ellipsoid(mb, (0, 1.78, -7.08), (0.33, 0.5, 0.42), 'paint', srgb('#f4ead2'), 6, 4, R('X', -28))
    ellipsoid(mb, (0, 2.4, -7.55), (0.2, 0.26, 0.24), 'paint', srgb('#f4ead2'), 6, 4)
    for sg in (-1, 1): cbox(mb, (sg * 0.33, 1.75, -6.8), (0.1, 0.7, 0.8), 'paint', C_TEAL, 0.0, None, R('X', -20))
    hexa(mb, [(-0.1, 2.36, -7.74), (0.1, 2.36, -7.74), (0.1, 2.5, -7.74), (-0.1, 2.5, -7.74), (-0.02, 2.1, -8.5), (0.02, 2.1, -8.5), (0.02, 2.2, -8.5), (-0.02, 2.2, -8.5)], 'paint', srgb('#f0a224'))
    # fittings that read at distance
    for sg in (-1, 1):
        cbox(mb, (sg * 1.75, DECK_Y + 0.62, -1.5), (1.5, 0.3, 0.3), 'paint', C_IRON, 0.0); cbox(mb, (sg * 1.4, DECK_Y + 0.3, -1.5), (0.9, 0.4, 0.6), 'paint', C_RED, 0.0)
    cbox(mb, (0, QDECK_Y + 0.6, 4.95), (0.34, 1.2, 0.34), 'paint', C_RED, 0.0)
    with xf(mb, T(0, QDECK_Y + 0.95, 5.2) @ M_Y2Z): lathe(mb, [(0, -0.04), (0.5, -0.04), (0.5, 0.04), (0, 0.04)], 8, 'paint', C_DARK, False)
    with xf(mb, T(0, DECK_Y, -4.6)): lathe(mb, [(0.4, 0), (0.24, 0.5), (0.42, 0.75), (0.42, 1.0), (0, 1.05)], 6, 'paint', C_DARK, False)
    cbox(mb, (0, DECK_Y + 0.12, 1.0), (1.4, 0.3, 3.0), 'paint', C_RED, 0.0, skip=('-y',))
    yl = ytop(6.5) + 1.55
    cbox(mb, (0, yl, zstern(yts) - 0.02), (0.36, 0.5, 0.36), 'glass', C_GLASS, 0.0); cbox(mb, (0, yl - 0.75, zstern(yts) - 0.02), (0.1, 1.1, 0.1), 'paint', C_IRON, 0.0)
    cbox(mb, (1.62, 1.0, -5.1), (0.12, 1.5, 0.12), 'paint', C_IRON, 0.0); cbox(mb, (1.62, 0.4, -5.1), (0.12, 0.14, 1.0), 'paint', C_IRON, 0.0)
    # rigging: thin three-sided ropes
    tip = Vector(BS_TIP)
    lines = [((0, MAST_TOP - 0.35, MAST_Z - 0.08), tip), ((0, 11.7, MAST_Z - 0.2), Vector(BS_HEEL).lerp(tip, 0.34))]
    for sg in (-1, 1):
        p, nh = rail_frame(2.0); lines.append(((sg * 0.08, MAST_TOP - 0.5, MAST_Z + 0.08), (sg * (p.x - 0.05), p.y + 0.95, p.z)))
    for sg, k, bot, top in shroud_pts(): lines.append((bot, top))
    for a, b in lines: tube(mb, [a, b], 0.04, 3, 'paint', C_ROPE_D, (False, False), 'flat')
    build(mb)
    y = YARD_Y; z = MAST_Z - YARD_FWD
    yd = MB('Yard', (0, YARD_Y, MAST_Z)); tube(yd, [(-3.25, y, z), (0, y, z), (3.25, y, z)], [0.08, 0.14, 0.08], 5, 'paint', mul(C_DECK, 0.85), mode='flat'); build(yd)
    sl = MB('Sail', (0, YARD_Y, MAST_Z)); nx, ny = 8, 5
    ids = [[sl.v(sail_point(-1 + 2 * i / nx, j / ny)) for i in range(nx + 1)] for j in range(ny + 1)]
    for j in range(ny):
        for i in range(nx):
            q = [ids[j][i], ids[j][i + 1], ids[j + 1][i + 1], ids[j + 1][i]]; uq = [(i / nx, 1 - j / ny), ((i + 1) / nx, 1 - j / ny), ((i + 1) / nx, 1 - (j + 1) / ny), (i / nx, 1 - (j + 1) / ny)]
            sl.f(q, 'canvas_lod', C_WHITE, uq, True); sl.f(q[::-1], 'canvas_back_lod', C_WHITE, uq[::-1], True)
    build(sl)
    sf = MB('Sail_Furled', (0, YARD_Y, MAST_Z)); tube(sf, [(-3.0, y - 0.32, z), (0, y - 0.36, z), (3.0, y - 0.32, z)], [0.14, 0.22, 0.14], 5, 'paint', srgb('#e6dbbd'), mode='flat'); build(sf)
    fl = MB('Flag', (0, MAST_TOP - 0.12, MAST_Z)); build_flag(fl, 6, 2); build(fl)
    total = sum(OBJS[n][1] for n in OBJS)
    print('sloop_lod: %d triangles, %d objects' % (total, len(OBJS)))
    path = os.path.join(outdir, 'ship', 'sloop_lod.glb')
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_yup=True, export_apply=False, export_vertex_color='MATERIAL',
                              export_all_vertex_colors=False, export_cameras=False, export_lights=False, export_animations=False,
                              export_extras=False, export_tangents=False)
    print('wrote', path)

# ================================================================ main
def main():
    argv = sys.argv; outdir = argv[-1] if '--' in argv else os.path.join(os.getcwd(), 'assets', 'generated')
    random.seed(SEED); np.random.seed(SEED)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    make_materials()
    # Static ship structure & decorative sub-parts are authored in their own MBs (preserving per-part RNG)
    # and batched into one `Hull` MeshInstance3D so Godot draws 1 surface per static material across all shadow cascades.
    hull = MB('Hull'); build_hull(hull)
    decks = MB('Decks'); build_decks(decks); hull.merge(decks)
    rails = MB('Rails'); build_rails(rails); hull.merge(rails)
    inter = MB('Interior'); build_interior(inter); hull.merge(inter)
    mast = MB('Mast');
    with xf(mast, T(0, 0, MAST_Z)): build_mast(mast)
    build_bowsprit(mast); hull.merge(mast)
    rig = MB('Rigging'); build_rigging(rig); hull.merge(rig)
    fig = MB('Figurehead', (0, 1.8, -7.0)); build_figurehead(fig); hull.merge(fig); empty_anchor('Figurehead', fig.origin)
    yard = MB('Yard', (0, YARD_Y, MAST_Z)); build_yard(yard); build(yard)
    sail = MB('Sail', (0, YARD_Y, MAST_Z)); build_sail(sail); build(sail)
    flag = MB('Flag', (0, MAST_TOP - 0.12, MAST_Z)); build_flag(flag); build(flag)
    hz = STATIONS['Station_Helm'][0][2]
    o = (0, QDECK_Y + 0.95, hz); wheel = MB('Wheel', o); build_wheel(wheel, o); build(wheel)
    o = (0, 0, 6.41); rud = MB('Rudder', o); build_rudder(rud, o); build(rud)
    o = STATIONS['Station_Anchor'][0]; cap = MB('Capstan', o); build_capstan(cap, o); build(cap)
    o = (1.62, ytop(-5.1) - 0.4, -5.1); anc = MB('Anchor', o); build_anchor(anc, o); build(anc)
    for name, sg, yaw in (('Cannon_Starboard', 1, 0), ('Cannon_Port', -1, 180)):
        o = Vector((sg * 1.38, DECK_Y, -1.5)); c = MB(name, o, seed=1, yaw=yaw - 90); build_cannon(c, o, yaw); build(c)   # object -Z = muzzle
        ob = o + R('Y', yaw).to_3x3() @ Vector(CANNON_TRUNNION)
        cb = MB(name + '_Barrel', ob, seed=1, yaw=yaw - 90, parent=c); build_cannon_barrel(cb, o, yaw); build(cb)
        k = MB('PowderKeg_' + name.split('_')[1], (sg * 1.5, DECK_Y, -2.45)); build_powder_keg(k, k.origin); hull.merge(k)
    extras(hull)
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
        hull.merge(l); empty_anchor(name, c)
    for name, key, band in (('Winch_SailLength', 'Station_SailLength', C_RED), ('Winch_SailAngle', 'Station_SailAngle', C_TEAL)):
        o = STATIONS[key][0]; o = (o[0] * 0.955, o[1], o[2]); w = MB(name, o); build_winch(w, o, band); hull.merge(w)
    c = (-0.36, QDECK_Y + 1.36, hz - 0.28); l = MB('Lantern_Helm', c); build_lantern(l, c, 0.6, False)      # swivel lamp on the binnacle for night steering
    tube(l, [(-0.15, QDECK_Y + 1.0, hz - 0.28), (-0.36, QDECK_Y + 1.05, hz - 0.28), (-0.36, QDECK_Y + 1.24, hz - 0.28)], 0.018, 5, 'iron', C_IRON)
    with xf(l, T(-0.36, QDECK_Y + 1.06, hz - 0.28)): lathe(l, [(0, -0.03), (0.035, -0.03), (0.035, 0.03), (0, 0.03)], 8, 'brass', C_BRASS)
    hull.merge(l); empty_anchor('Lantern_Helm', c)
    o = (-1.6, DECK_Y, -2.85); bd = MB('Bucket_Deck', o); build_bucket(bd, o); rope_coil(bd, (-1.62, DECK_Y, -3.3), 0.17, 3)
    rp, _ = rail_frame(s_of_z(-2.85))
    tube(bd, [(-1.6, DECK_Y + 0.44, -2.83), (-1.75, DECK_Y + 0.6, -2.9), (-(rp.x - 0.1), rp.y + 0.12, -2.95), (-(rp.x - 0.2), DECK_Y + 0.4, -3.2), (-1.66, DECK_Y + 0.14, -3.3)], 0.014, 4, 'rope', C_ROPE)
    hull.merge(bd); empty_anchor('Bucket_Deck', o)
    mt = MB('MapTable', STATIONS['Station_MapTable'][0]); build_map_table(mt); hull.merge(mt); empty_anchor('MapTable', mt.origin)
    pd = MB('Props_Deck'); build_props_deck(pd); hull.merge(pd)
    ph = MB('Props_Hold'); build_props_hold(ph); hull.merge(ph)
    build(hull)
    build_collision()
    gap = rig_clearance(); print('yard to standing rigging, smallest gap over +-1.2 rad trim: %.3f m' % gap)
    assert gap > 0.05, 'the yard fouls the standing rigging'
    # rope attachment helpers: clews ride on the Sail (they follow furl scaling and trim), yardarms on the Yard;
    # sheets end at the winches and braces on the quarterdeck rail. Rope_* objects are posed between them.
    bp, _ = rail_frame(s_of_z(5.7)); ya_z = MAST_Z - YARD_FWD
    marks = {'Clew_Port': (sail_point(-1, 1), 'Sail'), 'Clew_Starboard': (sail_point(1, 1), 'Sail'),
             'Yardarm_Port': (Vector((-3.25, YARD_Y, ya_z)), 'Yard'), 'Yardarm_Starboard': (Vector((3.25, YARD_Y, ya_z)), 'Yard'),
             'SheetPoint_Port': (Vector((-1.83, DECK_Y + 0.62, 0.5)), None), 'SheetPoint_Starboard': (Vector((1.83, DECK_Y + 0.62, 0.5)), None),
             'BracePoint_Port': (Vector((-(bp.x - 0.07), bp.y + 0.66, bp.z)), None), 'BracePoint_Starboard': (Vector((bp.x - 0.07, bp.y + 0.66, bp.z)), None),
             'AnchorCablePoint': (Vector((1.62, ytop(-5.1) + 0.1, -5.1)), None)}
    for name, (p, par) in marks.items():
        e = bpy.data.objects.new(name, None); e.empty_display_size = 0.2
        if par: e.parent = OBJS[par][0]; e.location = conv(p - Vector((0, YARD_Y, MAST_Z)))
        else: e.location = conv(p)
        bpy.context.scene.collection.objects.link(e)
    for side in ('Port', 'Starboard'):
        rope_object('Rope_Sheet_' + side, marks['SheetPoint_' + side][0], marks['Clew_' + side][0])
        rope_object('Rope_Brace_' + side, marks['BracePoint_' + side][0], marks['Yardarm_' + side][0])
    for name, (p, yaw) in STATIONS.items():
        e = bpy.data.objects.new(name, None); e.empty_display_size = 0.3
        e.location = conv(p); e.rotation_euler = (0, 0, radians(yaw))
        bpy.context.scene.collection.objects.link(e)
    total = 0
    for n in OBJS:
        if not n.startswith(('col_', 'mask_')):
            total += OBJS[n][1]; print('  %-20s %6d tris' % (n, OBJS[n][1]))
    print('sloop: %d visual triangles, %d objects, %d collision pieces' % (total, len([n for n in OBJS if not n.startswith('col_')]), len([n for n in OBJS if n.startswith('col_')])))
    os.makedirs(os.path.join(outdir, 'ship'), exist_ok=True)
    path = os.path.join(outdir, 'ship', 'sloop.glb')
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_yup=True, export_apply=False, export_vertex_color='MATERIAL',
                              export_all_vertex_colors=False, export_cameras=False, export_lights=False, export_animations=False,
                              export_extras=False, export_tangents=False)
    print('wrote', path)
    build_lod(outdir)

main()
