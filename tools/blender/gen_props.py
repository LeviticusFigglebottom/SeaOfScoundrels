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
        if len(idx) > 4:
            # Triangulate n-gons (e.g. 5..16-sided loft/tube caps) so MikkTSpace calc_tangents succeeds on every mesh!
            for k in range(1, len(idx) - 1):
                t_idx = (idx[0], idx[k], idx[k + 1])
                t_uvs = [uvs[0], uvs[k], uvs[k + 1]]
                t_col = [col[0], col[k], col[k + 1]] if isinstance(col, list) else col
                t_uv2 = [uv2[0], uv2[k], uv2[k + 1]] if uv2 is not None else None
                self.faces.append(t_idx)
                self.fmat.append(mat)
                self.fsm.append(smooth)
                self.fcol.append(t_col)
                self.fuv.append(t_uvs)
                if t_uv2 is not None:
                    self.has_uv2 = True
                    self.fuv2.append(t_uv2)
                else:
                    self.fuv2.append(None)
            return
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

    def fp(self, pts, mat, col, grain=None, inside=None, smooth=False, uv2=None, uv_scale=1.0):
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
        uvs = [(p.dot(gu) * SU * uv_scale + o[0], p.dot(gv) * SV * uv_scale + o[1]) for p in pts]
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

def loft(mb, secs, mat, col, closed=True, caps=(True, True), mode='flat', scols=None, flip=None, suv2=None, swap_uv=False):
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
        if swap_uv:
            return (W[i][j] * SV + o[0], L[i] * SU + o[1])
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

def bevel_slab(mb, center, size, mat, col, bev=0.032, M=None, top_col=None, bot_col=None):
    """Lean 28-tri chamfered masonry quoin / coping slab with crisp sunlit top bevel & shadowed overhang lip."""
    hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    b = min(bev, hx * 0.38, hy * 0.42, hz * 0.38)
    c_top = top_col if top_col is not None else mul(col, 1.05)
    c_bot = bot_col if bot_col is not None else mul(col, 0.78)
    X = T(center) @ M if M is not None else T(center)
    with xf(mb, X):
        secs = [
            [(-(hx - b), -hy, -(hz - b)), ((hx - b), -hy, -(hz - b)), ((hx - b), -hy, (hz - b)), (-(hx - b), -hy, (hz - b))],
            [(-hx, -hy + b, -hz), (hx, -hy + b, -hz), (hx, -hy + b, hz), (-hx, -hy + b, hz)],
            [(-hx, hy - b, -hz), (hx, hy - b, -hz), (hx, hy - b, hz), (-hx, hy - b, hz)],
            [(-(hx - b), hy, -(hz - b)), ((hx - b), hy, -(hz - b)), ((hx - b), hy, (hz - b)), (-(hx - b), hy, (hz - b))],
        ]
        loft(mb, secs, mat, col, closed=True, caps=(True, True), mode='flat',
             scols=[c_bot, col, c_top, c_top], swap_uv=True)

def stepped_corbel(mb, pos, rot_y_deg, width, height, depth, mat, col):
    """Sculpted chamfered oak roof-eave timber corbel bracket (projects along local -Z beneath eave at local y=0)."""
    hw = width * 0.5
    prof = [
        (0.0, 0.0),
        (-depth, 0.0),
        (-depth, -height * 0.24),
        (-depth * 0.64, -height * 0.44),
        (-depth * 0.44, -height * 0.70),
        (-depth * 0.16, -height),
        (0.0, -height),
    ]
    with xf(mb, T(pos) @ R('Y', rot_y_deg)):
        secs = [
            [(-hw, py, pz) for (pz, py) in prof],
            [(hw, py, pz) for (pz, py) in prof],
        ]
        loft(mb, secs, mat, col, closed=True, caps=(True, True), mode='flat', scols=[col])

def faceted_rock(mb, center, radii, mat, col_top, col_mid, col_bot, rng, subdiv=2, warp=0.24, strata=0.14, flat_top=0.0, rot_deg=(0, 0, 0), moss_cap=False, ledge_sharp=0.0, tide_band=False, uv_scale=1.0):
    """Sculpted chunky faceted coastal rock with horizontal strata & sunlit limestone vertex colour gradients."""
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
    X_rot = X.to_3x3()
    out_pts = []
    for v in bm.verts:
        p = v.co.copy()
        n = p.normalized()
        d = 1.0
        for idx, dv in enumerate(dirs):
            d += warp * 0.45 * sin(n.dot(dv) * 3.1 + ph[idx])
        # Horizontal sedimentary ledges
        d += strata * sin(p.y * 5.2 + ph[5] + 0.8 * sin(p.x * 2.5 + p.z * 2.2))
        if ledge_sharp > 0.0:
            # Stepped coastal limestone stratification shelves & chiseled fracture ribs
            s_ph = p.y * 6.8 + ph[5] + 0.45 * sin(p.x * 3.1 - p.z * 2.7)
            d += ledge_sharp * (0.65 * sin(s_ph) + 0.35 * sin(s_ph * 2.0 + 0.6))
            d -= ledge_sharp * 0.25 * abs(sin(atan2(p.z, p.x) * 3.0 + ph[7]))
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
            if fn.dot(fc) < 0.0:
                fn = -fn
            wp = X @ fc
            wn = (X_rot @ fn).normalized()
            h01 = smooth01((fc.y / max(radii[1], 0.1) + 0.85) * 0.55)
            # Sunlit upper/side coastal limestone, rich emerald moss on upward shelves, warm shaded overhangs
            if wn.y > 0.36:
                base = mix(col_mid, col_top, smooth01((wn.y - 0.36) / 0.52))
                if moss_cap and h01 > 0.38 and wn.y > 0.54 and (not tide_band or wp.y > 0.55):
                    m_patch = 0.72 + 0.28 * sin(wp.x * 2.3 + wp.z * 1.9 + ph[8])
                    m_blend = smooth01((wn.y - 0.54) / 0.32) * smooth01((h01 - 0.38) / 0.40) * m_patch
                    base = mix(base, mix(C_MOSS, C_LEAF_MID, 0.35), min(0.85, m_blend * 0.85))
            elif wn.y < -0.14:
                base = mul(col_bot, 0.84 if tide_band else 0.78)
            else:
                base = mix(col_bot, col_mid, 0.35 + 0.65 * h01 if tide_band else h01)
            # Subtle warm sedimentary strata ribboning per face
            st_wave = sin(wp.y * 3.1 + 0.5 * sin(wp.x * 1.4 - wp.z * 1.2) + ph[6])
            if tide_band:
                if st_wave > 0.25:
                    base = mix(base, C_STONE_PALE, (st_wave - 0.25) * 0.24)
                elif st_wave < -0.25:
                    base = mix(base, C_STONE_OCHRE, (-st_wave - 0.25) * 0.22)
                st = 0.96 + 0.07 * st_wave
                # Subtle dark wet-slate / barnacle tide band ONLY near the very bottom waterline base (y < 0.25)
                if wp.y < 0.25:
                    tide_t = smooth01((0.25 - wp.y) / 0.46)
                    wet_col = mix(C_STONE_DARK, C_SEA_MOSS, 0.26)
                    if wp.y > -0.04:
                        # Faint pale barnacle rim speckle right at the tidal wash line
                        barn = max(0.0, sin(wp.x * 11.0 + wp.z * 9.5))
                        wet_col = mix(wet_col, C_STONE_SHADE, barn * 0.32)
                    base = mix(base, wet_col, tide_t * 0.68)
            else:
                st = 0.92 + 0.12 * sin(fc.y * 2.6 + ph[6])
            c = jit(mul(base, st), rng, 0.045, 0.018)
            mb.fp(pts, mat, c, (1, 0, 0), Vector((0, 0, 0)), smooth=False, uv_scale=uv_scale)
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

def _fbm_tile(rs, w, h, octaves):
    acc = np.zeros((h, w), dtype=np.float64)
    tot = 0.0
    for gx, gy, amp in octaves:
        acc += amp * tile_noise(rs, w, h, gx, gy)
        tot += amp
    return acc / max(tot, 1e-6)

def height_to_normal(hf, strength=3.5):
    """Convert a seamless tileable heightfield (H, W) into an OpenGL tangent-space Normal Map RGB [0..1]."""
    dh_dx = (np.roll(hf, -1, axis=1) - np.roll(hf, 1, axis=1)) * 0.5 * strength
    dh_dy = (np.roll(hf, -1, axis=0) - np.roll(hf, 1, axis=0)) * 0.5 * strength
    nx = -dh_dx
    ny = -dh_dy
    nz = np.ones_like(hf)
    inv = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx * inv * 0.5 + 0.5, ny * inv * 0.5 + 0.5, nz * inv * 0.5 + 0.5], axis=-1)

def make_image(name, arr):
    h, w = arr.shape[:2]
    rgba = np.ones((h, w, 4), dtype=np.float32)
    rgba[..., :3] = np.clip(arr, 0.0, 1.0)
    img = bpy.data.images.new(name, w, h, alpha=False)
    img.pixels.foreach_set(rgba.ravel())
    img.file_format = 'PNG'
    img.pack()
    return img

def make_normal_image(name, rgb):
    h, w = rgb.shape[:2]
    rgba = np.ones((h, w, 4), dtype=np.float32)
    rgba[..., :3] = np.clip(rgb, 0.0, 1.0)
    img = bpy.data.images.new(name, w, h, alpha=False, is_data=True)
    img.colorspace_settings.name = 'Non-Color'
    img.pixels.foreach_set(rgba.ravel())
    img.file_format = 'PNG'
    img.pack()
    return img

def make_gray_image(name, gray):
    h, w = gray.shape[:2]
    g = np.clip(gray, 0.0, 1.0).astype(np.float32)
    rgba = np.ones((h, w, 4), dtype=np.float32)
    rgba[..., 0] = g
    rgba[..., 1] = g
    rgba[..., 2] = g
    img = bpy.data.images.new(name, w, h, alpha=False, is_data=True)
    img.colorspace_settings.name = 'Non-Color'
    img.pixels.foreach_set(rgba.ravel())
    img.file_format = 'PNG'
    img.pack()
    return img

def _voronoi_tile(rs, w, h, n_pts):
    """Seamless tiled 2D Voronoi (f1, f2 - f1 edge distance, cell_id) for genuine angular rock fractures."""
    yy, xx = np.mgrid[0:h, 0:w] / float(w)
    pts_x = rs.rand(n_pts)
    pts_y = rs.rand(n_pts)
    f1 = np.full((h, w), 1e9, dtype=np.float64)
    f2 = np.full((h, w), 1e9, dtype=np.float64)
    cid = np.zeros((h, w), dtype=np.int32)
    for i in range(n_pts):
        dx = ((xx - pts_x[i] + 0.5) % 1.0) - 0.5
        dy = ((yy - pts_y[i] + 0.5) % 1.0) - 0.5
        d = np.sqrt(dx * dx + dy * dy)
        closer1 = d < f1
        closer2 = (~closer1) & (d < f2)
        f2 = np.where(closer1, f1, np.where(closer2, d, f2))
        f1 = np.where(closer1, d, f1)
        cid = np.where(closer1, i, cid)
    return f1, f2 - f1, cid

def _smoothstep_np(e0, e1, x):
    t = np.clip((x - e0) / np.maximum(e1 - e0, 1e-6), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)

def _worley_grid_tile(rs, w, h, gx, gy, jitter=0.78, warp_x=None, warp_y=None):
    """Seamless periodic jittered-grid Worley Voronoi returning (f1, edge_dist, cid01, lx, ly)."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64) / float(w)
    u = (xx + (warp_x if warp_x is not None else 0.0)) % 1.0
    v = (yy + (warp_y if warp_y is not None else 0.0)) % 1.0
    pu = u * gx
    pv = v * gy
    iu = np.floor(pu).astype(np.int32)
    iv = np.floor(pv).astype(np.int32)
    ox = 0.5 + (rs.rand(gy, gx) - 0.5) * jitter
    oy = 0.5 + (rs.rand(gy, gx) - 0.5) * jitter
    cell_val = rs.rand(gy, gx)
    f1 = np.full((h, w), 1e9, dtype=np.float64)
    f2 = np.full((h, w), 1e9, dtype=np.float64)
    cid = np.zeros((h, w), dtype=np.float64)
    best_lx = np.zeros((h, w), dtype=np.float64)
    best_ly = np.zeros((h, w), dtype=np.float64)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            nu = (iu + dx) % gx
            nv = (iv + dy) % gy
            rx = (iu + dx) + ox[nv, nu] - pu
            ry = (iv + dy) + oy[nv, nu] - pv
            d = np.sqrt(rx * rx + ry * ry)
            c1 = d < f1
            c2 = (~c1) & (d < f2)
            f2 = np.where(c1, f1, np.where(c2, d, f2))
            f1 = np.where(c1, d, f1)
            cid = np.where(c1, cell_val[nv, nu], cid)
            best_lx = np.where(c1, -rx, best_lx)
            best_ly = np.where(c1, -ry, best_ly)
    return f1, f2 - f1, cid, best_lx, best_ly

def _multi_normal(hf_macro, hf_detail, str_macro=5.8, str_detail=2.6):
    """Multi-scale OpenGL tangent-space Normal Map combining wide bevels and crisp micro-relief."""
    dh_xw = (np.roll(hf_macro, -3, axis=1) - np.roll(hf_macro, 3, axis=1)) / 6.0 * str_macro
    dh_yw = (np.roll(hf_macro, -3, axis=0) - np.roll(hf_macro, 3, axis=0)) / 6.0 * str_macro
    dh_xn = (np.roll(hf_macro, -1, axis=1) - np.roll(hf_macro, 1, axis=1)) * 0.5 * (str_macro * 0.52)
    dh_yn = (np.roll(hf_macro, -1, axis=0) - np.roll(hf_macro, 1, axis=0)) * 0.5 * (str_macro * 0.52)
    dh_xd = (np.roll(hf_detail, -1, axis=1) - np.roll(hf_detail, 1, axis=1)) * 0.5 * str_detail
    dh_yd = (np.roll(hf_detail, -1, axis=0) - np.roll(hf_detail, 1, axis=0)) * 0.5 * str_detail
    nx = -(dh_xw + dh_xn + dh_xd)
    ny = -(dh_yw + dh_yn + dh_yd)
    nz = np.ones_like(hf_macro)
    inv = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx * inv * 0.5 + 0.5, ny * inv * 0.5 + 0.5, nz * inv * 0.5 + 0.5], axis=-1)

def pbr_bark_palm(rs):
    """512x512 horizontal scaly coconut-palm leaf-scar rings (rings run across V, stacked along trunk U)."""
    w = h = 512
    yy, xx = np.mgrid[0:h, 0:w] / float(w)
    warp_u = _fbm_tile(rs, w, h, ((4, 4, 0.65), (10, 10, 0.35)))
    # Horizontal palm leaf-scar rings (loft U = trunk height, V = circumference)
    n_rings = 9.0
    ring_phase = (xx * n_rings + (warp_u - 0.5) * 0.48) % 1.0
    groove = np.exp(-((ring_phase - 0.08) / 0.068) ** 2) + np.exp(-((ring_phase - 1.08) / 0.068) ** 2)
    lip = np.clip(1.0 - np.abs(ring_phase - 0.24) * 3.5, 0.0, 1.0)
    # Diamond overlapping fibrous leaf-base scales tucked cleanly beneath each palm ring collar
    diam = 0.5 + 0.5 * np.sin((yy * 16.0 + xx * 9.0) * 2.0 * pi) * np.sin((yy * 16.0 - xx * 9.0) * 2.0 * pi)
    fibers = tile_noise(rs, w, h, 42, 10) * 0.55 + tile_noise(rs, w, h, 96, 20) * 0.45
    splits = np.clip((tile_noise(rs, w, h, 28, 8) - 0.74) * 4.5, 0.0, 1.0)
    hf = 0.52 + 0.32 * lip + 0.18 * diam + 0.12 * (fibers - 0.5) - 0.50 * groove - 0.16 * splits
    hf = np.clip(hf, 0.0, 1.0)
    val = 0.85 + 0.14 * lip + 0.09 * (diam - 0.5) + 0.08 * (fibers - 0.5) - 0.32 * groove - 0.10 * splits
    bleach = np.clip(lip * 0.65 + (warp_u - 0.5) * 0.25, 0.0, 1.0)
    alb = np.stack([
        val * (1.01 + 0.02 * bleach),
        val * (0.96 + 0.02 * bleach),
        val * (0.89 + 0.04 * bleach),
    ], axis=-1)
    rough = 0.94 - 0.10 * lip + 0.06 * groove + 0.04 * (fibers - 0.5)
    return alb, height_to_normal(hf, 4.8), np.clip(rough, 0.80, 0.97)

def pbr_bark_banyan(rs):
    """512x512 deeply vertically furrowed gnarled hardwood root bark with subtle crevice lichen."""
    w = h = 512
    yy, xx = np.mgrid[0:h, 0:w] / float(w)
    # Loft/tube U (xx) runs along trunk/root length -> long sweeping longitudinal bark ribs along xx!
    warp_long = _fbm_tile(rs, w, h, ((2, 6, 0.65), (5, 14, 0.35)))
    sway = (warp_long - 0.5) * 1.45 + 0.22 * np.sin(xx * 2.0 * pi * 2.0)
    r1 = 0.5 + 0.5 * np.sin((yy * 9.0 + sway) * 2.0 * pi)
    r2 = 0.5 + 0.5 * np.sin((yy * 18.0 - sway * 0.8 + 0.7) * 2.0 * pi)
    # Sharp crested ridge profile (1 - |2r - 1|) for rugged braided bark fissures
    ridge = 0.65 * np.power(r1, 0.75) + 0.35 * np.power(r2, 0.85)
    cleft = np.clip((0.36 - ridge) * 3.4, 0.0, 1.0)
    plates = tile_noise(rs, w, h, 6, 36) * 0.60 + tile_noise(rs, w, h, 14, 72) * 0.40
    micro = tile_noise(rs, w, h, 32, 96)
    # Soft muted sage-moss flecks nestled inside the deepest gnarled bark furrows
    lichen_n = _fbm_tile(rs, w, h, ((6, 10, 0.55), (18, 22, 0.45)))
    lichen = np.clip((lichen_n - 0.58) * 4.2, 0.0, 1.0) * np.clip(cleft * 1.5 + 0.15, 0.0, 1.0)
    hf = np.clip(0.22 + 0.62 * ridge + 0.18 * (plates - 0.5) - 0.36 * cleft + 0.06 * (micro - 0.5), 0.0, 1.0)
    val = 0.82 + 0.20 * (ridge - 0.35) + 0.12 * (plates - 0.5) - 0.28 * cleft + 0.05 * (micro - 0.5)
    r = val * 1.01 * (1.0 - 0.22 * lichen) + 0.58 * lichen * 0.22
    g = val * 0.96 * (1.0 - 0.14 * lichen) + 0.76 * lichen * 0.22
    b = val * 0.89 * (1.0 - 0.22 * lichen) + 0.52 * lichen * 0.22
    alb = np.stack([r, g, b], axis=-1)
    rough = 0.88 - 0.09 * ridge + 0.08 * cleft + 0.05 * lichen
    return alb, height_to_normal(hf, 5.4), np.clip(rough, 0.78, 0.96)

def pbr_wood(rs):
    """512x512 staggered weathered oak plank courses with knots, swirling grain, tar seams & nail dimples."""
    w = h = 512
    yy, xx = np.mgrid[0:h, 0:w] / float(w)
    n_planks = 6
    row = np.floor(yy * n_planks).astype(int) % n_planks
    row_v = (yy * n_planks) % 1.0

    # Per-plank staggered butt-joints & warm oak/honey/driftwood tonal personality (never greenish!)
    joint_x = np.array([0.14, 0.62, 0.34, 0.82, 0.48, 0.08])[row]
    board_id = ((xx - joint_x) % 1.0 > 0.50).astype(int) + row * 2
    tone_lut = np.array([0.97, 0.87, 0.93, 1.00, 0.89, 0.95, 0.98, 0.86, 0.94, 0.97, 0.88, 0.95])
    # All boards stay warm timber (R >= G >= B) ranging from sunlit amber-oak to sun-bleached driftwood
    r_lut = np.array([1.03, 0.99, 1.01, 1.04, 0.98, 1.02, 1.00, 0.98, 1.03, 1.01, 0.99, 1.02])
    g_lut = np.array([0.97, 0.95, 0.96, 0.98, 0.95, 0.97, 0.96, 0.95, 0.97, 0.96, 0.95, 0.97])
    b_lut = np.array([0.88, 0.90, 0.89, 0.87, 0.91, 0.89, 0.91, 0.90, 0.88, 0.89, 0.90, 0.88])
    b_tone = tone_lut[board_id]
    br_t = r_lut[board_id]
    bg_t = g_lut[board_id]
    bb_t = b_lut[board_id]

    d_h = np.minimum(row_v, 1.0 - row_v)
    butt_u = (xx - joint_x) % 0.50
    d_v = np.minimum(butt_u, 0.50 - butt_u)
    h_seam = np.clip(1.0 - d_h / 0.044, 0.0, 1.0)
    v_seam = np.clip(1.0 - d_v / 0.0085, 0.0, 1.0)
    seam = np.maximum(h_seam, v_seam)
    bevel = np.clip(d_h / 0.095, 0.0, 1.0) * np.clip(d_v / 0.018, 0.0, 1.0)

    # Organic swirled wood knots (5 knots placed seamlessly across the plank courses)
    knot_disp = np.zeros((h, w), dtype=np.float64)
    knot_dark = np.zeros((h, w), dtype=np.float64)
    for kx, ky, kr in ((0.24, 0.09, 0.036), (0.74, 0.25, 0.040), (0.42, 0.42, 0.034), (0.16, 0.74, 0.038), (0.86, 0.91, 0.035)):
        dx = ((xx - kx + 0.5) % 1.0) - 0.5
        dy = (((yy - ky + 0.5) % 1.0) - 0.5) * 2.2
        dist = np.sqrt(dx * dx + dy * dy)
        inf = np.exp(-(dist / (kr * 2.5)) ** 2)
        knot_disp += inf * 0.25 * np.sign(dy + 1e-6)
        knot_dark = np.maximum(knot_dark, np.exp(-(dist / kr) ** 2))

    # Expressive painterly swirling oak grain running along U (xx)
    phase_lut = np.linspace(0.0, 5.7, 12)
    b_ph = phase_lut[board_id]
    warp = _fbm_tile(rs, w, h, ((4, 8, 0.65), (10, 20, 0.35))) * 0.16 + knot_disp
    gy = (yy * 20.0 + warp * 4.8 + b_ph) * 2.0 * pi
    rings = 0.50 * (0.5 + 0.5 * np.sin(gy)) + 0.32 * (0.5 + 0.5 * np.sin(gy * 2.2 + 1.1)) + 0.18 * (0.5 + 0.5 * np.sin(gy * 4.9))
    streak = tile_noise(rs, w, h, 4, 64) * 0.62 + tile_noise(rs, w, h, 8, 128) * 0.38

    # Paired forged nail / treenail dimples flanking every staggered butt-joint
    nail_mask = np.zeros((h, w), dtype=np.float64)
    for nv in (0.26, 0.74):
        for sgn in (-0.022, 0.022):
            ndx = np.minimum(np.abs(butt_u - (sgn % 0.50)), 0.50 - np.abs(butt_u - (sgn % 0.50)))
            ndy = (row_v - nv) / float(n_planks)
            nd = np.sqrt(ndx * ndx + ndy * ndy)
            nail_mask = np.maximum(nail_mask, np.clip(1.0 - nd / 0.008, 0.0, 1.0))

    hf = 0.66 * bevel + 0.20 * rings + 0.12 * (streak - 0.5) - 0.55 * seam - 0.20 * knot_dark - 0.32 * nail_mask
    hf = np.clip(hf, 0.0, 1.0)
    val = b_tone * (0.85 + 0.18 * (rings - 0.35) + 0.11 * (streak - 0.5)) - 0.44 * seam - 0.25 * knot_dark - 0.30 * nail_mask
    alb = np.stack([val * br_t, val * bg_t, val * bb_t], axis=-1)
    rough = 0.80 - 0.10 * rings + 0.14 * seam + 0.08 * knot_dark + 0.06 * (1.0 - bevel)
    return alb, height_to_normal(hf, 4.4), np.clip(rough, 0.68, 0.95)

def pbr_shingle(rs):
    """512x512 overlapping split cedar roof shingles with staggered gaps, stepped shadow laps & grain."""
    w = h = 512
    yy, xx = np.mgrid[0:h, 0:w] / float(w)
    n_rows = 8
    n_cols = 7
    row = np.floor(yy * n_rows).astype(int) % n_rows
    row_v = (yy * n_rows) % 1.0
    row_shift = ((row * 0.37 + 0.11) % 1.0)
    col_u = ((xx + row_shift) * n_cols) % 1.0
    col = np.floor(((xx + row_shift) * n_cols)).astype(int) % n_cols
    sid = (row * 13 + col * 7) % 16

    tone_lut = np.array([0.98, 0.86, 0.93, 0.89, 1.00, 0.84, 0.95, 0.91, 0.97, 0.85, 0.92, 0.99, 0.87, 0.94, 0.90, 0.96])
    s_tone = tone_lut[sid]
    edge_j = (tile_noise(rs, w, h, 24, 8) - 0.5) * 0.07
    rv_j = np.clip(row_v + edge_j, 0.0, 1.0)

    lap_shadow = np.exp(-((rv_j - 0.04) / 0.065) ** 2)
    step_h = 0.25 + 0.65 * (1.0 - rv_j)
    d_gap = np.minimum(col_u, 1.0 - col_u)
    v_gap = np.clip(1.0 - d_gap / 0.042, 0.0, 1.0)

    grain = tile_noise(rs, w, h, 64, 8) * 0.60 + tile_noise(rs, w, h, 128, 16) * 0.40
    moss_n = _fbm_tile(rs, w, h, ((8, 8, 0.5), (24, 24, 0.5)))
    moss = np.clip((moss_n - 0.66) * 4.5, 0.0, 1.0) * np.clip(lap_shadow * 1.4 + 0.18, 0.0, 1.0)

    hf = np.clip(step_h + 0.14 * (grain - 0.5) - 0.52 * v_gap - 0.35 * lap_shadow, 0.0, 1.0)
    val = s_tone * (0.86 + 0.14 * (grain - 0.5)) - 0.38 * v_gap - 0.28 * lap_shadow
    alb = np.stack([
        val * (1.01 - 0.18 * moss) + 0.52 * moss * 0.18,
        val * (0.96 - 0.06 * moss) + 0.68 * moss * 0.18,
        val * (0.90 - 0.18 * moss) + 0.42 * moss * 0.18,
    ], axis=-1)
    rough = 0.84 + 0.10 * lap_shadow + 0.08 * v_gap + 0.05 * (grain - 0.5)
    return alb, height_to_normal(hf, 5.2), np.clip(rough, 0.76, 0.96)

def pbr_thatch(rs):
    """512x512 overlapping woven tropical palm-thatch reed bundles with ragged fringed eaves."""
    w = h = 512
    yy, xx = np.mgrid[0:h, 0:w] / float(w)
    n_tiers = 6
    tier_v = (yy * n_tiers) % 1.0
    fringe = (tile_noise(rs, w, h, 48, 6) - 0.5) * 0.14
    tv = np.clip(tier_v + fringe, 0.0, 1.0)
    reeds = 0.55 * tile_noise(rs, w, h, 96, 8) + 0.45 * tile_noise(rs, w, h, 180, 16)
    bundles = 0.5 + 0.5 * np.sin((xx * 14.0 + tile_noise(rs, w, h, 6, 6) * 0.6) * 2.0 * pi)
    tier_shadow = np.exp(-((tv - 0.05) / 0.075) ** 2)
    step_h = 0.22 + 0.55 * (1.0 - tv) + 0.24 * reeds + 0.10 * bundles - 0.34 * tier_shadow
    hf = np.clip(step_h, 0.0, 1.0)
    val = 0.84 + 0.18 * (reeds - 0.5) + 0.08 * (bundles - 0.5) - 0.28 * tier_shadow
    alb = np.stack([val * 1.02, val * 0.98, val * 0.86], axis=-1)
    rough = 0.90 + 0.06 * tier_shadow + 0.05 * (0.5 - reeds)
    return alb, height_to_normal(hf, 4.8), np.clip(rough, 0.82, 0.97)

def pbr_stone(rs):
    """512x512 weathered hand-chiseled coral-limestone ashlar masonry with mortar seams & muted coastal moss."""
    w = h = 512
    yy, xx = np.mgrid[0:h, 0:w] / float(w)
    n_rows = 6
    n_cols = 4
    wob = (_fbm_tile(rs, w, h, ((8, 8, 0.6), (24, 24, 0.4))) - 0.5) * 0.018
    yy_w = (yy + wob) % 1.0
    xx_w = (xx + wob) % 1.0
    row = np.floor(yy_w * n_rows).astype(int) % n_rows
    row_v = (yy_w * n_rows) % 1.0
    stagger = (row % 2) * 0.50 + ((row * 0.17) % 0.22)
    col_u = ((xx_w + stagger) * n_cols) % 1.0
    col = np.floor((xx_w + stagger) * n_cols).astype(int) % n_cols
    bid = (row * 7 + col * 5) % 12

    tone_lut = np.array([0.98, 0.88, 0.94, 0.91, 1.00, 0.86, 0.95, 0.89, 0.97, 0.92, 0.87, 0.96])
    r_lut = np.array([1.02, 1.00, 1.01, 0.99, 1.03, 0.99, 1.01, 1.00, 1.02, 0.99, 1.00, 1.01])
    b_tone = tone_lut[bid]
    b_warm = r_lut[bid]

    d_h = np.minimum(row_v, 1.0 - row_v)
    d_v = np.minimum(col_u, 1.0 - col_u)
    mortar_h = np.clip(1.0 - d_h / 0.056, 0.0, 1.0)
    mortar_v = np.clip(1.0 - d_v / 0.042, 0.0, 1.0)
    mortar = np.maximum(mortar_h, mortar_v)
    bevel = np.clip(d_h / 0.13, 0.0, 1.0) * np.clip(d_v / 0.10, 0.0, 1.0)

    macro = _fbm_tile(rs, w, h, ((8, 8, 0.5), (20, 20, 0.5)))
    pits = np.clip((0.25 - tile_noise(rs, w, h, 48, 48)) * 4.2, 0.0, 1.0)
    chisel = tile_noise(rs, w, h, 36, 72)
    moss_n = _fbm_tile(rs, w, h, ((8, 8, 0.55), (24, 24, 0.45)))
    moss = np.clip((moss_n - 0.58) * 3.4, 0.0, 1.0) * np.clip(mortar * 1.25 + (1.0 - bevel) * 0.30, 0.0, 1.0)

    hf = 0.25 + 0.58 * bevel + 0.16 * (macro - 0.5) + 0.08 * (chisel - 0.5) - 0.42 * mortar - 0.22 * pits
    hf = np.clip(hf, 0.0, 1.0)
    val = b_tone * (0.87 + 0.14 * (macro - 0.5) + 0.06 * (chisel - 0.5)) - 0.34 * mortar - 0.14 * pits
    # Warm sunlit limestone + subtle olive-sage crevice moss (never neon green)
    alb = np.stack([
        val * b_warm * (1.0 - 0.22 * moss) + 0.54 * moss * 0.22,
        val * (0.985 - 0.08 * moss) + 0.66 * moss * 0.22,
        val * (0.935 - 0.24 * moss) + 0.42 * moss * 0.22,
    ], axis=-1)
    rough = 0.80 + 0.14 * mortar + 0.08 * pits + 0.05 * moss + 0.04 * (macro - 0.5)
    return alb, height_to_normal(hf, 4.8), np.clip(rough, 0.74, 0.96)

def pbr_rock(rs):
    """512x512 warm sunlit coastal limestone/sandstone Voronoi stratification harmonizing with Q3A terrain_cliff."""
    w = h = 512
    # Local deterministic RNG so upgrading pbr_rock never perturbs downstream material RNG streams
    rl = np.random.RandomState(SEED + 701)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64) / float(w)

    macro = _fbm_tile(rl, w, h, ((4, 4, 0.6), (10, 10, 0.4)))
    mid = _fbm_tile(rl, w, h, ((8, 8, 0.55), (20, 20, 0.45)))
    grit = tile_noise(rl, w, h, 96, 96) * 0.55 + tile_noise(rl, w, h, 180, 180) * 0.45

    # 1. Stepped horizontal sedimentary sandstone/limestone strata shelves (mod-4 periodic -> bold cliff-scale beds!)
    strata_warp = (_fbm_tile(rl, w, h, ((3, 4, 0.65), (7, 8, 0.35))) - 0.5) * 0.68 + (mid - 0.5) * 0.16
    bed_phase = yy * 4.0 + 0.25 + strata_warp
    bed_id = np.floor(bed_phase).astype(np.int32) % 4
    bed_f = bed_phase - np.floor(bed_phase)  # 0..1 across each horizontal strata shelf

    bed_hard = np.array([0.90, 0.58, 0.96, 0.64])[bed_id]
    bed_warm = np.array([0.20, 0.86, 0.14, 0.72])[bed_id]

    joint_gate = 0.36 + 0.64 * _fbm_tile(rl, w, h, ((5, 6, 0.6), (12, 12, 0.4)))
    bed_joint = np.maximum(
        1.0 - _smoothstep_np(0.008, 0.044, bed_f),
        _smoothstep_np(0.950, 0.994, bed_f),
    ) * joint_gate
    shelf_cast = _smoothstep_np(0.78, 0.96, bed_f) * (0.35 + 0.65 * bed_hard)
    shelf_lip = _smoothstep_np(0.025, 0.10, bed_f) * (1.0 - _smoothstep_np(0.10, 0.26, bed_f))

    # Fine horizontal sedimentary sandstone laminations
    lam = 0.55 * _fbm_tile(rl, w, h, ((4, 20, 0.6), (8, 40, 0.4))) + 0.45 * tile_noise(rl, w, h, 16, 112)

    # 2. Broad interlocked angular warped Voronoi limestone blocks (4x3 macro + 8x6 secondary) with chiseled facets
    bed_jog = (bed_hard - 0.72) * 0.065
    wx1 = (_fbm_tile(rl, w, h, ((4, 4, 0.65), (10, 10, 0.35))) - 0.5) * 0.085 + bed_jog
    wy1 = (_fbm_tile(rl, w, h, ((4, 4, 0.65), (10, 10, 0.35))) - 0.5) * 0.052
    _, ed_a, cid_a, lx_a, ly_a = _worley_grid_tile(rl, w, h, 4, 3, jitter=0.76, warp_x=wx1, warp_y=wy1)

    wx2 = (_fbm_tile(rl, w, h, ((8, 8, 0.6), (16, 16, 0.4))) - 0.5) * 0.04
    wy2 = (_fbm_tile(rl, w, h, ((8, 8, 0.6), (16, 16, 0.4))) - 0.5) * 0.032
    _, ed_b, cid_b, lx_b, ly_b = _worley_grid_tile(rl, w, h, 8, 6, jitter=0.78, warp_x=wx2, warp_y=wy2)

    ang_a = cid_a * 6.283185
    facet_a = np.clip(0.5 + (lx_a * np.cos(ang_a) + ly_a * np.sin(ang_a)) * 0.64, 0.0, 1.0)
    ang_b = cid_b * 6.283185
    facet_b = np.clip(0.5 + (lx_b * np.cos(ang_b) + ly_b * np.sin(ang_b)) * 0.48, 0.0, 1.0)
    plane_lit = np.clip(0.54 * facet_a + 0.30 * cid_a + 0.16 * facet_b, 0.0, 1.0)

    # Crisp selective broken rock joints (broad clean chiseled faces, never dense cracked-mud!)
    open_a = _smoothstep_np(0.28, 0.76, _fbm_tile(rl, w, h, ((5, 5, 0.65), (12, 12, 0.35))))
    open_b = _smoothstep_np(0.56, 0.88, _fbm_tile(rl, w, h, ((8, 8, 0.6), (16, 16, 0.4)))) * _smoothstep_np(0.38, 0.76, cid_a)
    crack_a = (1.0 - _smoothstep_np(0.005, 0.015 + 0.020 * open_a, ed_a)) * (0.22 + 0.78 * open_a)
    crack_b = (1.0 - _smoothstep_np(0.004, 0.016, ed_b)) * open_b * 0.36
    crevice = np.clip(np.maximum(np.maximum(bed_joint, crack_a), crack_b), 0.0, 1.0)

    # Crisp chiseled upper bevel catchlights along Voronoi block shoulders & shelf lips
    ed_up = np.roll(ed_a, -3, axis=0)
    ed_left = np.roll(ed_a, 3, axis=1)
    chisel_hi = np.clip((ed_a - ed_up) * 3.6 + (ed_a - ed_left) * 2.6, 0.0, 1.0) * _smoothstep_np(0.014, 0.090, ed_a) * (1.0 - _smoothstep_np(0.090, 0.26, ed_a))

    # 3. Bright warm sunlit buff/limestone/ochre albedo calibrated for vertex-color multiplication
    lit_k = _smoothstep_np(0.12, 0.88, 0.60 * plane_lit + 0.40 * bed_hard)
    r = 0.80 + 0.19 * lit_k
    g = 0.74 + 0.21 * lit_k
    b = 0.64 + 0.23 * lit_k

    # Warm golden-ochre sandstone strata bands
    ochre_w = _smoothstep_np(0.28, 0.80, 0.68 * bed_warm + 0.32 * _fbm_tile(rl, w, h, ((3, 6, 0.6), (7, 14, 0.4)))) * 0.34
    r = r * (1.0 - ochre_w) + 0.97 * ochre_w
    g = g * (1.0 - ochre_w) + 0.80 * ochre_w
    b = b * (1.0 - ochre_w) + 0.57 * ochre_w

    # Tactile sandstone laminations & stony micro-grain
    grain_mul = 0.89 + 0.12 * lam + 0.10 * grit
    r *= grain_mul
    g *= grain_mul
    b *= grain_mul

    # Subtle bright quartz speckles & fine dark mineral grains
    sp_bright = _smoothstep_np(0.84, 0.96, tile_noise(rl, w, h, 144, 144)) * 0.12
    sp_dark = _smoothstep_np(0.87, 0.97, tile_noise(rl, w, h, 128, 128)) * 0.20
    r = r * (1.0 - sp_dark) + sp_bright
    g = g * (1.0 - sp_dark) + sp_bright * 0.96
    b = b * (1.0 - sp_dark) + sp_bright * 0.88

    # Shelf underside warm shadow + bright chiseled upper bevel catchlights
    sh_w = shelf_cast * 0.20
    r = r * (1.0 - sh_w) + 0.50 * sh_w
    g = g * (1.0 - sh_w) + 0.44 * sh_w
    b = b * (1.0 - sh_w) + 0.37 * sh_w

    lip_hi = np.clip(shelf_lip * (0.64 + 0.36 * bed_hard) + chisel_hi * 0.82, 0.0, 1.0) * 0.44
    r = r * (1.0 - lip_hi) + 1.00 * lip_hi
    g = g * (1.0 - lip_hi) + 0.97 * lip_hi
    b = b * (1.0 - lip_hi) + 0.89 * lip_hi

    # Crisp warm deep-umber fracture crevices & bedding joints
    cr_w = np.clip(crevice * 0.74, 0.0, 0.78)
    r = r * (1.0 - cr_w) + 0.28 * cr_w
    g = g * (1.0 - cr_w) + 0.23 * cr_w
    b = b * (1.0 - cr_w) + 0.19 * cr_w

    alb = np.clip(np.stack([r, g, b], axis=-1), 0.0, 1.0)

    # 4. Crisp sculpted multi-scale normal map + sandstone roughness
    block_bevel = _smoothstep_np(0.014, 0.13, ed_a)
    hf_macro = np.clip(
        0.34 * bed_hard * (1.0 - 0.28 * bed_f)
        + 0.30 * block_bevel * (0.42 + 0.58 * cid_a)
        + 0.22 * facet_a
        + 0.08 * facet_b * open_b
        + 0.10 * shelf_lip
        - 0.40 * crevice,
        0.0, 1.0,
    )
    hf_detail = np.clip(0.46 * lam + 0.42 * grit - 0.42 * crevice, 0.0, 1.0)
    nrm = _multi_normal(hf_macro, hf_detail, str_macro=5.8, str_detail=2.5)
    rough = 0.78 + 0.15 * crevice + 0.06 * (0.5 - lam) + 0.05 * (grit - 0.5) - 0.06 * lip_hi
    return alb, nrm, np.clip(rough, 0.70, 0.96)

def pbr_plaster(rs):
    """512x512 sun-baked Caribbean coastal lime stucco with sweeping hand-trowel relief, hairline cracks & warm ochre salt-weathering."""
    w = h = 512
    rl = np.random.RandomState(SEED + 702)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64) / float(w)

    # 1. Broad curved hand-trowel plaster sweeps + overlapping crescent trowel ridge arcs
    warp_t = (_fbm_tile(rl, w, h, ((4, 4, 0.6), (10, 10, 0.4))) - 0.5) * 0.24
    arc_a = 0.5 + 0.5 * np.sin((xx * 4.0 + yy * 3.0 + warp_t * 3.4) * 2.0 * pi)
    arc_b = 0.5 + 0.5 * np.sin((xx * 3.0 - yy * 5.0 - warp_t * 2.8) * 2.0 * pi)
    trowel_ridge = np.power(np.clip(1.0 - np.abs(arc_a - 0.5) * 2.0, 0.0, 1.0), 1.6) * 0.55 + np.power(np.clip(1.0 - np.abs(arc_b - 0.5) * 2.0, 0.0, 1.0), 1.8) * 0.45
    trowel_broad = 0.55 * tile_noise(rl, w, h, 5, 14) + 0.45 * tile_noise(rl, w, h, 14, 5)
    trowel = 0.52 * trowel_broad + 0.48 * trowel_ridge

    # Fine lime-sand stucco grit & tiny weathered pinholes
    stucco = _fbm_tile(rl, w, h, ((8, 8, 0.42), (24, 24, 0.34), (64, 64, 0.24)))
    fine_grit = tile_noise(rl, w, h, 128, 128) * 0.6 + tile_noise(rl, w, h, 220, 220) * 0.4
    pinholes = _smoothstep_np(0.84, 0.96, tile_noise(rl, w, h, 96, 96))

    # 2. Crisp angular warped Voronoi hairline plaster age cracks (broken natural patches, never loops!)
    c_wx = (_fbm_tile(rl, w, h, ((6, 6, 0.6), (14, 14, 0.4))) - 0.5) * 0.055
    c_wy = (_fbm_tile(rl, w, h, ((6, 6, 0.6), (14, 14, 0.4))) - 0.5) * 0.055
    _, edge_v, cid_v, _, _ = _worley_grid_tile(rl, w, h, 5, 5, jitter=0.82, warp_x=c_wx, warp_y=c_wy)
    crack_zone = _smoothstep_np(0.46, 0.78, _fbm_tile(rl, w, h, ((4, 4, 0.65), (9, 9, 0.35))))
    cracks = (1.0 - _smoothstep_np(0.004, 0.022, edge_v)) * crack_zone
    crack_lip = _smoothstep_np(0.012, 0.036, edge_v) * (1.0 - _smoothstep_np(0.036, 0.085, edge_v)) * crack_zone

    # Subtle weathered plaster spall / salt-blister patches exposing warm coral-ochre lime underlay
    spall = _smoothstep_np(0.73, 0.87, _fbm_tile(rl, w, h, ((7, 7, 0.55), (18, 18, 0.45))))
    salt_wash = _fbm_tile(rl, w, h, ((10, 3, 0.55), (22, 6, 0.45)))
    ochre_bloom = _smoothstep_np(0.42, 0.82, salt_wash) * 0.55 + spall * 0.45

    # 3. Sun-baked warm lime stucco albedo + coastal salt-ochre weathering (keeps red/cream tints vibrant!)
    val = (
        0.925
        + 0.085 * (trowel - 0.5)
        + 0.065 * (stucco - 0.5)
        + 0.035 * (fine_grit - 0.5)
        + 0.045 * crack_lip
        - 0.22 * cracks
        - 0.08 * spall
        - 0.09 * pinholes
    )
    r = val * (1.005 + 0.015 * ochre_bloom)
    g = val * (0.985 - 0.020 * ochre_bloom)
    b = val * (0.940 - 0.065 * ochre_bloom)
    alb = np.clip(np.stack([r, g, b], axis=-1), 0.0, 1.0)

    # 4. Crisp micro-relief stucco normal map & tactile roughness
    hf_macro = np.clip(0.54 + 0.28 * (trowel - 0.5) + 0.14 * (stucco - 0.5) - 0.38 * cracks - 0.18 * spall + 0.06 * crack_lip, 0.0, 1.0)
    hf_detail = np.clip(0.50 + 0.28 * (stucco - 0.5) + 0.24 * (fine_grit - 0.5) - 0.35 * cracks - 0.22 * pinholes, 0.0, 1.0)
    nrm = _multi_normal(hf_macro, hf_detail, str_macro=3.8, str_detail=2.2)
    rough = 0.77 + 0.09 * (stucco - 0.5) + 0.12 * cracks + 0.09 * spall + 0.05 * ochre_bloom
    return alb, nrm, np.clip(rough, 0.68, 0.95)

def pbr_foliage_palm(rs):
    """512x512 veined tropical palm & fern frond texture (midrib along U, curved diagonal pinnae veins across V)."""
    w = h = 512
    yy, xx = np.mgrid[0:h, 0:w] / float(w)
    dist_mid = np.abs(yy - 0.5) * 2.0
    midrib = np.exp(-((dist_mid) / 0.075) ** 2)
    vein_ph = (xx * 18.0 - np.power(dist_mid, 0.85) * 4.2) * 2.0 * pi
    veins = 0.5 + 0.5 * np.sin(vein_ph)
    fine_vein = 0.5 + 0.5 * np.sin(vein_ph * 3.0)
    serr = 0.5 + 0.5 * np.sin(xx * 18.0 * 2.0 * pi) * np.clip(dist_mid * 1.4 - 0.3, 0.0, 1.0)
    brush = _fbm_tile(rs, w, h, ((6, 12, 0.55), (22, 28, 0.45)))
    dapple = _fbm_tile(rs, w, h, ((5, 5, 0.6), (14, 14, 0.4)))
    hf = np.clip(0.45 + 0.34 * midrib + 0.22 * veins + 0.08 * fine_vein + 0.08 * (brush - 0.5), 0.0, 1.0)
    val = 0.85 + 0.12 * midrib + 0.11 * (veins - 0.5) + 0.10 * (brush - 0.5) + 0.08 * (dapple - 0.5) + 0.05 * serr
    alb = np.stack([
        val * (0.94 + 0.09 * midrib + 0.05 * dapple),
        val * (1.01 + 0.04 * midrib),
        val * (0.85 - 0.05 * midrib),
    ], axis=-1)
    rough = 0.58 - 0.10 * midrib - 0.06 * veins + 0.08 * (0.5 - brush)
    return alb, height_to_normal(hf, 3.8), np.clip(rough, 0.44, 0.70)

def pbr_foliage_broad(rs):
    """512x512 dense hand-painted overlapping tropical banyan broadleaf & jungle ivy clusters with feather veins."""
    w = h = 512
    yy, xx = np.mgrid[0:h, 0:w] / float(w)
    hf = np.full((h, w), 0.12, dtype=np.float64)
    val = np.full((h, w), 0.58, dtype=np.float64)
    sun = np.zeros((h, w), dtype=np.float64)
    # Stamp 88 dense overlapping pointed tropical broadleaf silhouettes (100% lush coverage, seamless wrap!)
    for li in range(88):
        cx = rs.rand()
        cy = rs.rand()
        ang = rs.rand() * 2.0 * pi
        ca, sa = cos(ang), sin(ang)
        len_l = rs.uniform(0.085, 0.160)
        wid_l = len_l * rs.uniform(0.48, 0.64)
        layer_h = 0.24 + 0.68 * (li / 87.0)
        leaf_tone = rs.uniform(0.80, 1.04)
        leaf_sun = rs.uniform(0.32, 1.0) if li > 48 else rs.uniform(0.0, 0.42)

        dx = ((xx - cx + 0.5) % 1.0) - 0.5
        dy = ((yy - cy + 0.5) % 1.0) - 0.5
        lu = (dx * ca + dy * sa) / len_l
        lv = (-dx * sa + dy * ca) / wid_l
        env = np.clip(1.0 - lu * lu, 0.0, 1.0) * (1.0 - 0.20 * lu)
        inside = (np.abs(lu) < 1.0) & (np.abs(lv) < env)
        if not np.any(inside):
            continue
        iu = lu[inside]
        iv = lv[inside]
        ie = np.maximum(env[inside], 1e-4)
        dist_rib = np.abs(iv) / ie
        midrib = np.exp(-((dist_rib) / 0.14) ** 2)
        vein = 0.5 + 0.5 * np.sin((iu * 7.5 - dist_rib * 3.0) * pi)
        cup = (1.0 - dist_rib * dist_rib) * np.sqrt(np.clip(1.0 - iu * iu, 0.0, 1.0))
        lh = layer_h + 0.13 * cup + 0.08 * midrib + 0.04 * vein
        lv_val = leaf_tone * (0.85 + 0.13 * midrib + 0.08 * (vein - 0.5) + 0.07 * cup)
        win = lh > hf[inside]
        cur_h = hf[inside]
        cur_v = val[inside]
        cur_s = sun[inside]
        cur_h[win] = lh[win]
        cur_v[win] = lv_val[win]
        cur_s[win] = (leaf_sun * (0.65 + 0.35 * cup))[win]
        hf[inside] = cur_h
        val[inside] = cur_v
        sun[inside] = cur_s

    micro = tile_noise(rs, w, h, 48, 48)
    val = val + 0.05 * (micro - 0.5)
    alb = np.stack([
        val * (0.91 + 0.11 * sun),
        val * (1.00 + 0.05 * sun),
        val * (0.85 - 0.06 * sun),
    ], axis=-1)
    rough = 0.68 - 0.18 * sun - 0.06 * hf
    return alb, height_to_normal(np.clip(hf, 0.0, 1.0), 4.4), np.clip(rough, 0.46, 0.74)

def pbr_awning(rs):
    """512x512 heavy woven maritime sailcloth with warp/weft thread grid, subtle sail seams & salt weathering."""
    w = h = 512
    yy, xx = np.mgrid[0:h, 0:w] / float(w)
    warp_t = 0.5 + 0.5 * np.sin(xx * 2.0 * pi * 96.0)
    weft_t = 0.5 + 0.5 * np.sin(yy * 2.0 * pi * 96.0)
    weave = 0.5 * (warp_t + weft_t) + 0.25 * (warp_t * weft_t)
    # Single clean sailmaker horizontal panel seam + subtle double-stitch dash
    d_seam = np.abs(((yy * 1.0) % 1.0) - 0.5)
    seam_ridge = np.exp(-((d_seam) / 0.010) ** 2)
    stitch = np.exp(-((np.abs(d_seam - 0.015)) / 0.0035) ** 2) * (0.5 + 0.5 * np.sin(xx * 2.0 * pi * 56.0))
    creases = _fbm_tile(rs, w, h, ((4, 6, 0.6), (12, 16, 0.4)))
    hf = np.clip(0.46 + 0.24 * weave + 0.16 * seam_ridge - 0.12 * stitch + 0.22 * (creases - 0.5), 0.0, 1.0)
    val = 0.90 + 0.08 * (weave - 0.5) + 0.11 * (creases - 0.5) - 0.07 * seam_ridge - 0.09 * stitch
    alb = np.stack([val * 1.00, val * 0.99, val * 0.94], axis=-1)
    rough = 0.88 + 0.06 * (0.5 - creases) + 0.04 * seam_ridge
    return alb, height_to_normal(hf, 2.5), np.clip(rough, 0.82, 0.96)

def pbr_rope(rs):
    """256x256 braided diagonal twisted 3-strand hemp rope."""
    w = h = 256
    yy, xx = np.mgrid[0:h, 0:w] / float(w)
    diag = (xx * 6.0 + yy * 6.0) * 2.0 * pi
    strands = np.abs(np.sin(diag * 0.5))
    fibers = 0.5 + 0.5 * np.sin((xx * 42.0 - yy * 42.0) * 2.0 * pi + tile_noise(rs, w, h, 16, 16) * 2.2)
    fuzz = tile_noise(rs, w, h, 48, 48)
    hf = np.clip(0.18 + 0.64 * strands + 0.14 * fibers + 0.08 * (fuzz - 0.5), 0.0, 1.0)
    val = 0.78 + 0.24 * strands + 0.08 * (fibers - 0.5) + 0.06 * (fuzz - 0.5)
    alb = np.stack([val * 1.02, val * 0.97, val * 0.88], axis=-1)
    rough = 0.94 - 0.06 * strands + 0.04 * fuzz
    return alb, height_to_normal(hf, 4.6), np.clip(rough, 0.86, 0.98)

def pbr_iron(rs):
    """256x256 forged hand-hammered wrought iron with anvil dimples & dark mill-scale variation."""
    w = h = 256
    yy, xx = np.mgrid[0:h, 0:w] / float(w)
    dimples = np.ones((h, w), dtype=np.float64) * 0.65
    for _ in range(42):
        cx, cy = rs.rand(), rs.rand()
        rad = rs.uniform(0.055, 0.115)
        dx = ((xx - cx + 0.5) % 1.0) - 0.5
        dy = ((yy - cy + 0.5) % 1.0) - 0.5
        d2 = (dx * dx + dy * dy) / (rad * rad)
        dent = 0.28 + 0.42 * np.clip(d2, 0.0, 1.0)
        dimples = np.minimum(dimples, dent)
    scale_n = _fbm_tile(rs, w, h, ((8, 8, 0.55), (24, 24, 0.45)))
    rust_n = _fbm_tile(rs, w, h, ((12, 12, 0.5), (32, 32, 0.5)))
    rust = np.clip((rust_n - 0.66) * 5.0, 0.0, 1.0) * np.clip(0.75 - dimples, 0.0, 1.0)
    hf = np.clip(dimples + 0.16 * (scale_n - 0.5), 0.0, 1.0)
    val = 0.78 + 0.24 * (dimples - 0.45) + 0.14 * (scale_n - 0.5)
    alb = np.stack([
        val * (1.0 + 0.18 * rust),
        val * (0.99 - 0.06 * rust),
        val * (1.02 - 0.24 * rust),
    ], axis=-1)
    rough = 0.44 + 0.16 * (0.65 - dimples) + 0.22 * rust + 0.08 * (scale_n - 0.5)
    return alb, height_to_normal(hf, 3.2), np.clip(rough, 0.34, 0.68)

def pbr_brass(rs):
    """256x256 brushed aged marine brass with directional polish grain & fine antique tarnish streaks."""
    w = h = 256
    brush = tile_noise(rs, w, h, 4, 96) * 0.65 + tile_noise(rs, w, h, 8, 160) * 0.35
    wear = _fbm_tile(rs, w, h, ((10, 20, 0.55), (28, 48, 0.45)))
    patina = np.clip((wear - 0.68) * 3.8, 0.0, 1.0)
    hf = np.clip(0.54 + 0.20 * (brush - 0.5) + 0.14 * (wear - 0.5) - 0.12 * patina, 0.0, 1.0)
    val = 0.91 + 0.13 * (brush - 0.5) + 0.07 * (wear - 0.5) - 0.12 * patina
    alb = np.stack([
        val * (1.02 - 0.08 * patina),
        val * (0.99 - 0.02 * patina),
        val * (0.90 - 0.02 * patina),
    ], axis=-1)
    rough = 0.25 + 0.10 * (0.5 - brush) + 0.18 * patina
    return alb, height_to_normal(hf, 2.2), np.clip(rough, 0.20, 0.46)

def pbr_paint(rs):
    """256x256 subtle hand-painted impasto brush-stroke tooth preserving vibrant vertex colors."""
    w = h = 256
    s1 = tile_noise(rs, w, h, 8, 28)
    s2 = tile_noise(rs, w, h, 28, 8)
    fine = tile_noise(rs, w, h, 48, 48)
    hf = np.clip(0.50 + 0.24 * (s1 - 0.5) + 0.20 * (s2 - 0.5) + 0.08 * (fine - 0.5), 0.0, 1.0)
    val = 0.93 + 0.08 * (s1 - 0.5) + 0.06 * (s2 - 0.5)
    alb = np.stack([val, val * 0.995, val * 0.98], axis=-1)
    rough = 0.70 + 0.10 * (0.5 - s1) + 0.06 * (fine - 0.5)
    return alb, height_to_normal(hf, 1.4), np.clip(rough, 0.58, 0.84)

MATS = {}
_FOL_NODES = {}
_FOL_IMGS = {}
MAT_NAMES = {
    'wood': 'mat_wood',
    'bark_palm': 'mat_bark_palm',
    'bark_banyan': 'mat_bark_banyan',
    'shingle': 'mat_shingle',
    'thatch': 'mat_thatch',
    'paint': 'mat_paint',
    'plaster': 'mat_plaster',
    'stone': 'mat_stone',
    'rock': 'mat_rock',
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

def set_foliage_style(style):
    """Swap MATS['foliage'] PBR image triplet between 'palm' and 'broad' while keeping exact name 'mat_foliage'."""
    if style in _FOL_IMGS and _FOL_NODES:
        alb_i, norm_i, rough_i = _FOL_IMGS[style]
        _FOL_NODES['alb'].image = alb_i
        _FOL_NODES['norm'].image = norm_i
        _FOL_NODES['rough'].image = rough_i

def make_materials():
    rs = np.random.RandomState(SEED)

    def pack_pbr(prefix, triple):
        alb, nrm, rgh = triple
        return (
            make_image(prefix + '_alb', alb),
            make_normal_image(prefix + '_nrm', nrm),
            make_gray_image(prefix + '_rgh', rgh),
        )

    pbr_sets = {
        'wood': pack_pbr('prop_wood', pbr_wood(rs)),
        'bark_palm': pack_pbr('prop_bark_palm', pbr_bark_palm(rs)),
        'bark_banyan': pack_pbr('prop_bark_banyan', pbr_bark_banyan(rs)),
        'shingle': pack_pbr('prop_shingle', pbr_shingle(rs)),
        'thatch': pack_pbr('prop_thatch', pbr_thatch(rs)),
        'stone': pack_pbr('prop_stone', pbr_stone(rs)),
        'rock': pack_pbr('prop_rock', pbr_rock(rs)),
        'plaster': pack_pbr('prop_plaster', pbr_plaster(rs)),
        'awning': pack_pbr('prop_awning', pbr_awning(rs)),
        'rope': pack_pbr('prop_rope', pbr_rope(rs)),
        'iron': pack_pbr('prop_iron', pbr_iron(rs)),
        'brass': pack_pbr('prop_brass', pbr_brass(rs)),
        'paint': pack_pbr('prop_paint', pbr_paint(rs)),
    }
    _FOL_IMGS['palm'] = pack_pbr('prop_foliage_palm', pbr_foliage_palm(rs))
    _FOL_IMGS['broad'] = pack_pbr('prop_foliage_broad', pbr_foliage_broad(rs))

    def mk(key, pbr=None, rough=0.8, metal=0.0, emit=0.0, two=False, emit_col=(1.0, 0.64, 0.22, 1.0), norm_str=1.0):
        m = bpy.data.materials.new(MAT_NAMES[key])
        m.use_nodes = True
        nt = m.node_tree
        b = nt.nodes['Principled BSDF']
        b.inputs['Roughness'].default_value = rough
        b.inputs['Metallic'].default_value = metal
        ca = nt.nodes.new('ShaderNodeVertexColor')
        ca.layer_name = 'Color'
        nodes_out = {}
        if pbr is not None:
            alb_img, nrm_img, rgh_img = pbr
            t_alb = nt.nodes.new('ShaderNodeTexImage')
            t_alb.image = alb_img
            mx = nt.nodes.new('ShaderNodeMix')
            mx.data_type = 'RGBA'
            mx.blend_type = 'MULTIPLY'
            mx.inputs[0].default_value = 1.0
            nt.links.new(t_alb.outputs['Color'], mx.inputs[6])
            nt.links.new(ca.outputs['Color'], mx.inputs[7])
            nt.links.new(mx.outputs[2], b.inputs['Base Color'])
            nodes_out['alb'] = t_alb

            if nrm_img is not None:
                t_nrm = nt.nodes.new('ShaderNodeTexImage')
                t_nrm.image = nrm_img
                nmap = nt.nodes.new('ShaderNodeNormalMap')
                nmap.inputs['Strength'].default_value = norm_str
                nt.links.new(t_nrm.outputs['Color'], nmap.inputs['Color'])
                nt.links.new(nmap.outputs['Normal'], b.inputs['Normal'])
                nodes_out['norm'] = t_nrm

            if rgh_img is not None:
                t_rgh = nt.nodes.new('ShaderNodeTexImage')
                t_rgh.image = rgh_img
                nt.links.new(t_rgh.outputs['Color'], b.inputs['Roughness'])
                nodes_out['rough'] = t_rgh
        else:
            nt.links.new(ca.outputs['Color'], b.inputs['Base Color'])
        if emit > 0.0:
            b.inputs['Emission Color'].default_value = emit_col
            b.inputs['Emission Strength'].default_value = emit
        m.use_backface_culling = not two
        MATS[key] = m
        return nodes_out

    mk('wood', pbr_sets['wood'], 0.82, norm_str=1.0)
    mk('bark_palm', pbr_sets['bark_palm'], 0.88, norm_str=1.05)
    mk('bark_banyan', pbr_sets['bark_banyan'], 0.88, norm_str=1.10)
    mk('shingle', pbr_sets['shingle'], 0.86, norm_str=1.05)
    mk('thatch', pbr_sets['thatch'], 0.90, norm_str=1.0)
    mk('stone', pbr_sets['stone'], 0.86, norm_str=1.12)
    mk('rock', pbr_sets['rock'], 0.88, norm_str=1.18)
    mk('plaster', pbr_sets['plaster'], 0.82, norm_str=1.02)
    mk('paint', pbr_sets['paint'], 0.72, norm_str=0.65)
    fol_nodes = mk('foliage', _FOL_IMGS['palm'], 0.60, two=True, norm_str=0.90)
    _FOL_NODES.update(fol_nodes)
    mk('awning', pbr_sets['awning'], 0.90, two=True, norm_str=0.80)
    mk('rope', pbr_sets['rope'], 0.94, norm_str=1.0)
    mk('iron', pbr_sets['iron'], 0.48, 0.72, norm_str=0.90)
    mk('brass', pbr_sets['brass'], 0.30, 0.86, norm_str=0.70)
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
        export_extras=False, export_tangents=True
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

def _add_palm_frond(
    mb, crown, azimuth, pitch_deg, length, width, droop, tier_tint, phase, rng,
    n_segs=12, n_leaflets=17, leaflet_sweep_deg=41.0, stem_width=0.048,
    t_start=0.11, is_fern=False
):
    """Sculpted pinnate tropical palm/fern frond: smooth arched midrib rachis + individual curved spear leaflets with real open sky slits and UV2 wind weights."""
    mb.newoff()
    ca, sa = cos(azimuth), sin(azimuth)
    fwd = Vector((ca, 0.0, sa))
    side = Vector((-sa, 0.0, ca))
    up = Vector((0.0, 1.0, 0.0))
    pitch = radians(pitch_deg)
    lat_sway = rng.uniform(-0.07, 0.07) * length * (0.45 if is_fern else 1.0)
    arch_pow = 1.95 if is_fern else 2.08

    def spine(t):
        r = length * t
        y = sin(pitch) * r - droop * (t ** arch_pow) * length
        h = cos(pitch) * r * (1.0 - (0.10 if is_fern else 0.14) * t * t)
        return crown + fwd * h + up * y + side * (lat_sway * t * t)

    def spine_frame(t):
        t_a = max(0.0, t - 0.012)
        t_b = min(1.0, t + 0.012)
        p = spine(t)
        tan = (spine(t_b) - spine(t_a))
        if tan.length < 1e-6:
            tan = fwd
        else:
            tan.normalize()
        ls = side - tan * side.dot(tan)
        if ls.length < 1e-5:
            ls = Vector((-tan.z, 0.0, tan.x))
        ls.normalize()
        lu = ls.cross(tan).normalized()
        return p, tan, ls, lu

    # 1. Smooth arched tapering midrib rachis (12-seg V-beam on palms; slender curved stem on ferns)
    stem_base_col = mix(C_LEAF_DEEP, C_TRUNK_LIGHT, 0.24 if not is_fern else 0.14)
    stem_tip_col = mix(C_LEAF_MID, C_LEAF_SUN, 0.52)
    r_left = []
    r_mid = []
    r_right = []
    r_cols = []
    r_uv2 = []
    r_t = []
    for i in range(n_segs + 1):
        t = i / float(n_segs)
        p, tan, ls, lu = spine_frame(t)
        sw = stem_width * (1.0 - 0.88 * pow(t, 0.90))
        r_t.append(t)
        r_cols.append(mix(stem_base_col, stem_tip_col, pow(t, 1.05)))
        w_wind = min(1.0, 0.05 + 0.90 * pow(t, 1.28))
        r_uv2.append((w_wind, phase))
        if is_fern:
            r_left.append(mb.v(p - ls * sw))
            r_right.append(mb.v(p + ls * sw))
        else:
            r_left.append(mb.v(p - ls * sw - lu * (sw * 0.42)))
            r_mid.append(mb.v(p + lu * (sw * 0.38)))
            r_right.append(mb.v(p + ls * sw - lu * (sw * 0.42)))

    u_stem_scale = 1.6 if is_fern else 2.6
    for i in range(n_segs):
        u0 = r_t[i] * u_stem_scale
        u1 = r_t[i + 1] * u_stem_scale
        c0, c1 = r_cols[i], r_cols[i + 1]
        w0, w1 = r_uv2[i], r_uv2[i + 1]
        if is_fern:
            mb.f(
                [r_left[i], r_left[i + 1], r_right[i + 1], r_right[i]],
                'foliage', [c0, c1, c1, c0],
                [(u0, 0.46), (u1, 0.46), (u1, 0.54), (u0, 0.54)],
                smooth=True, uv2=[w0, w1, w1, w0]
            )
        else:
            # Left slope of V-beam rachis
            mb.f(
                [r_left[i], r_left[i + 1], r_mid[i + 1], r_mid[i]],
                'foliage', [mul(c0, 0.92), mul(c1, 0.92), c1, c0],
                [(u0, 0.44), (u1, 0.44), (u1, 0.50), (u0, 0.50)],
                smooth=True, uv2=[w0, w1, w1, w0]
            )
            # Right slope of V-beam rachis
            mb.f(
                [r_mid[i], r_mid[i + 1], r_right[i + 1], r_right[i]],
                'foliage', [c0, c1, mul(c1, 0.92), mul(c0, 0.92)],
                [(u0, 0.50), (u1, 0.50), (u1, 0.56), (u0, 0.56)],
                smooth=True, uv2=[w0, w1, w1, w0]
            )

    # 2. Individual sculpted pinnate spear leaflets along BOTH sides + forked terminal tip pair
    frond_shift = rng.uniform(-0.07, 0.09)
    base_tier = max(0.0, min(1.0, tier_tint * 0.88 + frond_shift))
    t_end = 0.955
    span_len = (t_end - t_start) * length
    step_len = span_len / float(max(1, n_leaflets - 1))

    def emit_leaflet(t_pos, sgn, l_len, hw_max, fwd_ang_rad, li_idx, frac):
        if l_len < 0.04 or hw_max < 0.008:
            return
        p_r, tan, ls, lu = spine_frame(t_pos)
        sw = stem_width * (1.0 - 0.88 * pow(t_pos, 0.90))
        p0 = p_r + ls * (sgn * sw * 0.55)
        dir_out = (ls * (sgn * cos(fwd_ang_rad)) + tan * sin(fwd_ang_rad)).normalized()
        w_base = lu.cross(dir_out)
        if w_base.length < 1e-5:
            w_base = tan
        else:
            w_base.normalize()
        # Subtle dihedral blade cant so sunlit sides & shaded edges read crisply
        cant = radians((12.0 if is_fern else 15.0) + 6.0 * sin(li_idx * 1.15)) * (1.0 if sgn > 0 else -1.0)
        w_vec = (w_base * cos(cant) + lu * sin(cant)).normalized()

        # Graceful 3-station curved tropical arch: lifts softly off rachis, crests, then droops to spear tip
        lift_1 = (0.10 if is_fern else 0.14) * l_len
        crest_2 = (0.04 if is_fern else 0.02) * l_len
        droop_loc = (0.13 if is_fern else 0.28) * l_len
        droop_grav = (0.05 if is_fern else 0.17) * l_len * (0.65 + 0.55 * frac)

        p1 = p0 + dir_out * (l_len * 0.30) + lu * lift_1
        p2 = p0 + dir_out * (l_len * 0.66) + lu * crest_2 - up * (droop_grav * 0.28)
        p3 = p0 + dir_out * (l_len * 1.00) - lu * droop_loc - up * droop_grav

        hw1 = hw_max
        hw2 = hw_max * (0.58 if is_fern else 0.62)
        v0 = mb.v(p0)
        v1a = mb.v(p1 - w_vec * hw1)
        v1b = mb.v(p1 + w_vec * hw1)
        v2a = mb.v(p2 - w_vec * hw2)
        v2b = mb.v(p2 + w_vec * hw2)
        v3 = mb.v(p3)

        # Rich painterly emerald -> lush mid-green -> sunlit chartreuse tip with subtle per-leaflet hue jitter
        c_deep = mix(C_LEAF_DEEP, C_LEAF_MID, base_tier * 0.42 + frac * 0.18)
        c_mid = jit(mix(C_LEAF_DEEP, C_LEAF_MID, 0.52 + 0.38 * base_tier + 0.18 * frac), rng, 0.065, 0.035)
        c_m2 = mix(c_mid, C_LEAF_SUN, 0.24 + 0.28 * frac + 0.22 * base_tier)
        c_tip = mix(c_m2, C_LEAF_SUN, 0.50 + 0.26 * base_tier + 0.16 * frac)

        # Smooth UV2 wind weights increasing from rachis base (0.05) to outer frond & leaflet tips (0.95..1.0)
        w_r = 0.05 + 0.78 * pow(t_pos, 1.25)
        l_ph = (phase + 0.022 * sin(li_idx * 1.7 + sgn)) % 1.0
        u2_0 = (min(1.0, w_r), l_ph)
        u2_1 = (min(1.0, w_r + 0.07), l_ph)
        u2_2 = (min(1.0, w_r + 0.15), l_ph)
        u2_3 = (min(1.0, max(0.32, w_r + 0.24)), l_ph)

        # Explicit positive-area UVs aligned with pbr_foliage_palm midrib (V = 0.50) & diagonal veins
        u_off = (li_idx * 0.137 + (0.0 if sgn > 0 else 0.07)) % 1.0
        uv0 = (u_off, 0.50)
        uv1a = (u_off + 0.24, 0.36)
        uv1b = (u_off + 0.24, 0.64)
        uv2a = (u_off + 0.52, 0.42)
        uv2b = (u_off + 0.52, 0.58)
        uv3 = (u_off + 0.76, 0.50)

        # 4-tri smooth curved spear blade (1 base flare tri + 1 mid-belly quad + 1 drooping spear tip tri)
        mb.f([v0, v1a, v1b], 'foliage', [c_deep, c_mid, c_mid], [uv0, uv1a, uv1b], smooth=True, uv2=[u2_0, u2_1, u2_1])
        mb.f([v1a, v2a, v2b, v1b], 'foliage', [c_mid, c_m2, c_m2, c_mid], [uv1a, uv2a, uv2b, uv1b], smooth=True, uv2=[u2_1, u2_2, u2_2, u2_1])
        mb.f([v2a, v3, v2b], 'foliage', [c_m2, c_tip, c_m2], [uv2a, uv3, uv2b], smooth=True, uv2=[u2_2, u2_3, u2_2])

    for li in range(n_leaflets):
        frac = li / float(max(1, n_leaflets - 1))
        t_nom = t_start + (t_end - t_start) * frac
        for sgn in (-1.0, 1.0):
            # Subtle botanical stagger between left and right pinnae
            t_s = max(t_start, min(0.96, t_nom + (0.008 if sgn > 0 else -0.008)))
            env = pow(sin(pi * pow(max(0.05, t_s), 0.68)), 0.80)
            l_len = width * env * rng.uniform(0.92, 1.08)
            # Lush broad spear blades with crisp ~26-32% open sky slits between adjacent leaflets!
            hw_cap = step_len * (0.315 if is_fern else 0.305)
            hw_max = min(l_len * (0.245 if is_fern else 0.165), hw_cap) * (0.78 + 0.28 * env)
            fwd_deg = (26.0 if is_fern else leaflet_sweep_deg) + (16.0 if is_fern else 9.0) * frac + rng.uniform(-3.2, 3.2)
            emit_leaflet(t_s, sgn, l_len, hw_max, radians(fwd_deg), li, frac)

    # Forked terminal tip pair anchored right at the rachis tip (zero protruding stick!)
    tip_len = min(width * 0.42, length * 0.22)
    tip_hw = min(tip_len * 0.19, step_len * 0.24)
    for sgn in (-1.0, 1.0):
        emit_leaflet(0.985, sgn, tip_len * rng.uniform(0.92, 1.08), tip_hw, radians(70.0 + rng.uniform(-3.0, 3.0)), n_leaflets, 1.0)


def _add_dried_skirt_frond(mb, crown, azimuth, length, rng):
    """Short dried tawny palm skirt frond drooping beneath coconuts (double-sided for backface-culled bark_palm)."""
    mb.newoff()
    ca, sa = cos(azimuth), sin(azimuth)
    fwd = Vector((ca, 0.0, sa))
    side = Vector((-sa, 0.0, ca))
    up = Vector((0.0, 1.0, 0.0))
    pitch = radians(rng.uniform(-24.0, -10.0))
    droop = rng.uniform(0.55, 0.72)
    segs = 4

    def sp(t):
        r = length * t
        return crown + fwd * (cos(pitch) * r * (1.0 - 0.22 * t * t)) + up * (sin(pitch) * r - droop * t * t * length)

    pts = [sp(i / float(segs)) for i in range(segs + 1)]
    rads = [0.025 * (1.0 - 0.68 * (i / float(segs))) for i in range(segs + 1)]
    suv2 = [(0.11 + 0.14 * (i / float(segs)), 0.0) for i in range(segs + 1)]
    c_stem = jit(mix(C_TRUNK_DARK, C_TRUNK_LIGHT, 0.45), rng, 0.07)
    tube(mb, pts, rads, 4, 'bark_palm', c_stem, caps=(False, True), mode='flat', suv2=suv2)

    c_dry_top = jit(mix(C_THATCH, C_DRIFT, 0.38), rng, 0.08, 0.02)
    c_dry_bot = mul(c_dry_top, 0.72)
    for li in range(4):
        frac = (li + 0.5) / 4.0
        t = 0.18 + 0.76 * frac
        p0 = sp(t)
        tan = (sp(min(1.0, t + 0.04)) - sp(max(0.0, t - 0.04))).normalized()
        ls = (side - tan * side.dot(tan)).normalized()
        lu = ls.cross(tan).normalized()
        blen = length * 0.26 * (0.65 + 0.55 * sin(pi * frac)) * rng.uniform(0.75, 1.18)
        bw = 0.042 * rng.uniform(0.85, 1.2)
        u2_b = (0.12 + 0.15 * t, 0.0)
        u2_t = (0.14 + 0.18 * t, 0.0)
        for sgn in (-1.0, 1.0):
            ang = radians(48.0 + 14.0 * frac + rng.uniform(-6.0, 6.0))
            d_out = (ls * (sgn * cos(ang)) + tan * sin(ang)).normalized()
            wv = lu.cross(d_out).normalized()
            pm = p0 + d_out * (blen * 0.48) - up * (blen * 0.16)
            pt = p0 + d_out * blen - up * (blen * 0.44)
            # Double-sided 2-tri tattered tawny blade (visible from both above and below!)
            v0, vma, vmb, vt = mb.v(p0), mb.v(pm - wv * bw), mb.v(pm + wv * bw), mb.v(pt)
            mb.f([v0, vma, vmb], 'bark_palm', [c_stem, c_dry_top, c_dry_top], [(0.0, 0.5), (0.4, 0.35), (0.4, 0.65)], smooth=False, uv2=[u2_b, u2_t, u2_t])
            mb.f([vma, vt, vmb], 'bark_palm', [c_dry_top, mul(c_dry_top, 0.88), c_dry_top], [(0.4, 0.35), (0.85, 0.5), (0.4, 0.65)], smooth=False, uv2=[u2_t, u2_t, u2_t])
            # Underside backfaces (reversed winding, shaded dark tawny)
            u0, uma, umb, ut = mb.v(p0), mb.v(pm - wv * bw), mb.v(pm + wv * bw), mb.v(pt)
            mb.f([u0, umb, uma], 'bark_palm', [mul(c_stem, 0.72), c_dry_bot, c_dry_bot], [(0.0, 0.5), (0.4, 0.65), (0.4, 0.35)], smooth=False, uv2=[u2_b, u2_t, u2_t])
            mb.f([uma, umb, ut], 'bark_palm', [c_dry_bot, c_dry_bot, mul(c_dry_bot, 0.85)], [(0.4, 0.35), (0.4, 0.65), (0.85, 0.5)], smooth=False, uv2=[u2_t, u2_t, u2_t])


def _build_palm_tree(name, height, lean_x, lean_z, s_curve, n_rings, frond_count, seed_off):
    clear_scene()
    set_foliage_style('palm')
    rng = random.Random(SEED + seed_off)
    mb_trunk = MB('Trunk', seed=seed_off)
    mb_fronds = MB('Fronds', seed=seed_off + 100)

    def trunk_pt(t):
        # Smooth sweeping tropical trunk curve; embeds deeply to y = -0.95 so zero floating on steep slopes
        y = -0.95 + (height + 0.95) * t
        bend = (t ** 1.65)
        sw = sin(t * pi * 1.15) * s_curve
        return Vector((lean_x * bend + sw, y, lean_z * bend + sw * 0.35))

    # 1. 12-sided ringed coconut-palm trunk with pronounced watertight overlapping bark collars & 5-lobed root buttress!
    sides = 12
    col_pts_a = []
    col_pts_b = []
    prev_lip_sec = None
    for i in range(n_rings):
        t0 = i / float(n_rings)
        t1 = (i + 1) / float(n_rings)
        tm = 0.5 * (t0 + t1)
        p0 = trunk_pt(t0)
        p1 = trunk_pt(t1)
        # Flared 5-lobed root buttress over lower 26% of trunk, tapering cleanly to crown
        root_k0 = pow(max(0.0, 1.0 - t0 / 0.26), 1.45)
        root_k1 = pow(max(0.0, 1.0 - t1 / 0.26), 1.45)
        r_base = (0.31 * (1.0 - 0.45 * t0)) + 0.19 * root_k0
        r_lip = ((0.31 * (1.0 - 0.45 * t1)) + 0.16 * root_k1) * (1.105 if i > 0 else 1.05)
        tan = (p1 - p0).normalized()
        ref = Vector((1, 0, 0)) if abs(tan.x) < 0.8 else Vector((0, 0, 1))
        nx = (ref - tan * ref.dot(tan)).normalized()
        nz = tan.cross(nx)
        sec0 = []
        sec1 = []
        ring_twist = i * 0.11
        for k in range(sides):
            ang = 2.0 * pi * k / sides + ring_twist
            # 5-lobed flared root buttress gripping into beach slopes + subtle organic bark asymmetry
            lobe0 = 1.0 + 0.25 * root_k0 * (0.45 + 0.55 * cos(ang * 5.0 + 0.35)) + 0.025 * sin(ang * 3.0 + i * 0.7)
            lobe1 = 1.0 + 0.22 * root_k1 * (0.45 + 0.55 * cos(ang * 5.0 + 0.35)) + 0.030 * sin(ang * 3.0 + i * 0.7)
            off = nx * cos(ang) + nz * sin(ang)
            v0 = p0 + off * (r_base * lobe0)
            v1 = p1 + off * (r_lip * lobe1)
            sec0.append(v0)
            sec1.append(v1)
            if t0 < 0.55:
                col_pts_a.extend([v0, v1])
            else:
                col_pts_b.extend([v0, v1])
        c_ring = jit(mix(C_TRUNK_DARK, C_TRUNK_LIGHT, smooth01(tm)), rng, 0.07, 0.02)
        if i % 2 == 1:
            c_ring = mul(c_ring, 0.90)
        w0 = (0.12 * t0 * t0, 0.0)
        w1 = (0.12 * t1 * t1, 0.0)
        # Watertight darkened underside collar lip return so looking up from below shows crisp bark shadow rings
        if prev_lip_sec is not None:
            loft(mb_trunk, [prev_lip_sec, sec0], 'bark_palm', mul(c_ring, 0.68), closed=True, caps=(False, False), mode='flat', suv2=[w0, w0])
        loft(mb_trunk, [sec0, sec1], 'bark_palm', c_ring, closed=True, caps=(i == 0, i == n_rings - 1), mode='smooth', suv2=[w0, w1])
        prev_lip_sec = sec1

    crown = trunk_pt(1.0)
    # 2. Sculpted fibrous diamond-patterned palm crown shaft wrapping the frond bases
    crown_rings = []
    crown_cols = []
    crown_specs = [
        (-0.26, 0.22, 0.04, C_TRUNK_DARK),
        (-0.08, 0.30, 0.09, mul(C_TRUNK_DARK, 0.92)),
        ( 0.10, 0.32, 0.08, mix(C_TRUNK_DARK, C_LEAF_DEEP, 0.22)),
        ( 0.26, 0.24, 0.05, mix(C_TRUNK_DARK, C_LEAF_DEEP, 0.38)),
        ( 0.38, 0.11, 0.02, mix(C_TRUNK_DARK, C_LEAF_DEEP, 0.45)),
    ]
    for ri, (dy, rad, diam_amp, ccol) in enumerate(crown_specs):
        ring = []
        for k in range(sides):
            ang = 2.0 * pi * k / sides + (ri % 2) * (pi / sides)
            sc = 1.0 + diam_amp * (1.0 if (k + ri) % 2 == 0 else -0.5)
            ring.append(crown + Vector((cos(ang) * rad * sc, dy, sin(ang) * rad * sc)))
        crown_rings.append(ring)
        crown_cols.append(jit(ccol, rng, 0.06, 0.02))
    loft(mb_trunk, crown_rings, 'bark_palm', C_TRUNK_DARK, closed=True, caps=(True, True), mode='flat', scols=crown_cols, suv2=[(0.12, 0.0)] * len(crown_rings))

    # 3. Four short dried tawny skirt fronds drooping underneath the coconuts
    for si in range(4):
        s_az = si * (2.0 * pi / 4.0) + rng.uniform(-0.34, 0.34) + 0.4
        _add_dried_skirt_frond(mb_trunk, crown + Vector((0.0, -0.16, 0.0)), s_az, rng.uniform(1.15, 1.50), rng)

    # 4. Seven irregular coconuts clustered snugly under the palm crown shaft
    for ci in range(7):
        ang = ci * (2.0 * pi / 7.0) + rng.uniform(-0.20, 0.20)
        cr = 0.25 + rng.uniform(-0.03, 0.05) + (0.04 if ci % 3 == 0 else 0.0)
        cy = -0.20 - (ci % 3) * 0.085 + rng.uniform(-0.02, 0.02)
        cpos = crown + Vector((cos(ang) * cr, cy, sin(ang) * cr))
        ccol = jit(mix(C_COCONUT, C_LEAF_DEEP, 0.30 if ci in (1, 5) else 0.0), rng, 0.09, 0.025)
        rx = rng.uniform(0.12, 0.155)
        ry = rng.uniform(0.15, 0.195)
        rz = rng.uniform(0.12, 0.155)
        rot_m = R('Y', rng.uniform(0, 360)) @ R('Z', rng.uniform(-28, 28))
        ellipsoid(mb_trunk, cpos, (rx, ry, rz), 'paint', ccol, 6, 4, rot_m)

    # 5. Lush 3-tier pinnate palm crown (14-15 full fronds with 16-17 leaflets/side + 3 upright young crown spear shoots)
    if frond_count == 15:
        tier_counts = (6, 5, 4)
    elif frond_count == 14:
        tier_counts = (5, 5, 4)
    else:
        t1 = max(4, frond_count // 3 + 1)
        t2 = max(4, frond_count // 3)
        t3 = max(3, frond_count - t1 - t2)
        tier_counts = (t1, t2, t3)

    # Tier 1: Lower lush drooping umbrella skirt
    n1 = tier_counts[0]
    for i in range(n1):
        az = i * (2.0 * pi / n1) + rng.uniform(-0.18, 0.18)
        _add_palm_frond(
            mb_fronds, crown + Vector((0.0, 0.02, 0.0)), az,
            pitch_deg=rng.uniform(10.0, 22.0),
            length=rng.uniform(4.40, 5.25),
            width=rng.uniform(1.06, 1.26),
            droop=rng.uniform(0.54, 0.65),
            tier_tint=0.18, phase=rng.random(), rng=rng,
            n_segs=12, n_leaflets=17, leaflet_sweep_deg=40.0
        )
    # Tier 2: Mid spreading sunlit canopy ring
    n2 = tier_counts[1]
    for i in range(n2):
        az = (i + 0.45) * (2.0 * pi / n2) + rng.uniform(-0.18, 0.18)
        _add_palm_frond(
            mb_fronds, crown + Vector((0.0, 0.12, 0.0)), az,
            pitch_deg=rng.uniform(26.0, 38.0),
            length=rng.uniform(3.95, 4.65),
            width=rng.uniform(0.96, 1.15),
            droop=rng.uniform(0.45, 0.55),
            tier_tint=0.52, phase=rng.random(), rng=rng,
            n_segs=12, n_leaflets=16, leaflet_sweep_deg=42.0
        )
    # Tier 3: Upper arching golden-lime crown
    n3 = tier_counts[2]
    for i in range(n3):
        az = (i + 0.85) * (2.0 * pi / n3) + rng.uniform(-0.20, 0.20)
        _add_palm_frond(
            mb_fronds, crown + Vector((0.0, 0.20, 0.0)), az,
            pitch_deg=rng.uniform(42.0, 55.0),
            length=rng.uniform(3.20, 3.90),
            width=rng.uniform(0.84, 1.02),
            droop=rng.uniform(0.35, 0.45),
            tier_tint=0.82, phase=rng.random(), rng=rng,
            n_segs=11, n_leaflets=16, leaflet_sweep_deg=44.0
        )
    # 3 upright young crown spear shoots catching sunlit chartreuse highlights
    for i in range(3):
        az = i * (2.0 * pi / 3.0) + rng.uniform(-0.35, 0.35)
        _add_palm_frond(
            mb_fronds, crown + Vector((0.0, 0.26, 0.0)), az,
            pitch_deg=rng.uniform(62.0, 76.0),
            length=rng.uniform(2.05, 2.75),
            width=rng.uniform(0.56, 0.72),
            droop=rng.uniform(0.22, 0.32),
            tier_tint=1.0, phase=rng.random(), rng=rng,
            n_segs=8, n_leaflets=10, leaflet_sweep_deg=46.0, stem_width=0.036
        )

    build(mb_trunk)
    build(mb_fronds)
    col_piece('col_trunk_lower', col_pts_a)
    col_piece('col_trunk_upper', col_pts_b)


def gen_palm_tall(outdir):
    _build_palm_tree('palm_tall', height=11.4, lean_x=1.15, lean_z=-0.55, s_curve=0.32, n_rings=20, frond_count=15, seed_off=11)
    export_glb(outdir, 'palm_tall.glb')


def gen_palm_curved(outdir):
    _build_palm_tree('palm_curved', height=9.0, lean_x=3.15, lean_z=-1.05, s_curve=0.68, n_rings=18, frond_count=14, seed_off=23)
    export_glb(outdir, 'palm_curved.glb')


def _add_fiddlehead(mb, root, azimuth, height, curl_r, phase, rng):
    """Sculpted coiled tropical fern fiddlehead crozier shoot curling upward in the mossy root heart."""
    ca, sa = cos(azimuth), sin(azimuth)
    fwd = Vector((ca, 0.0, sa))
    side = Vector((-sa, 0.0, ca))
    up = Vector((0.0, 1.0, 0.0))
    pts = []
    rads = []
    scols = []
    suv2 = []
    # Rising stem (4 stations) + tight inward logarithmic spiral crozier (6 stations)
    stem_top = Vector(root) + fwd * (height * 0.26) + up * height
    for i in range(4):
        t = i / 3.0
        p = Vector(root) + fwd * (height * 0.26 * (t ** 1.3)) + up * (height * t)
        pts.append(p)
        rads.append(0.024 * (1.0 - 0.30 * t))
        scols.append(mix(C_LEAF_MID, C_LEAF_SUN, 0.28 + 0.45 * t))
        suv2.append((0.05 + 0.32 * t, phase))
    curl_center = stem_top - fwd * curl_r
    for i in range(1, 7):
        u = i / 6.0
        ang = u * 2.0 * pi * 1.18  # > 1 full spiral turn!
        rad_s = curl_r * (1.0 - 0.72 * u)
        p = curl_center + fwd * (cos(ang) * rad_s) + up * (sin(ang) * rad_s)
        pts.append(p)
        rads.append(0.017 * (1.0 - 0.52 * u))
        scols.append(jit(mix(C_LEAF_MID, C_LEAF_SUN, 0.72 + 0.26 * u), rng, 0.05))
        suv2.append((0.38 + 0.30 * u, phase))
    # Build singularity-free loft using constant plane normal `side` perpendicular to the (fwd, up) spiral plane
    secs = []
    n_p = len(pts)
    for i in range(n_p):
        tan = (pts[min(i + 1, n_p - 1)] - pts[max(i - 1, 0)]).normalized()
        bn = side.cross(tan).normalized()
        r_i = rads[i]
        secs.append([pts[i] + (side * cos(2 * pi * k / 4.0) + bn * sin(2 * pi * k / 4.0)) * r_i for k in range(4)])
    loft(mb, secs, 'foliage', C_LEAF_SUN, closed=True, caps=(False, True), mode='smooth', scols=scols, suv2=suv2)


def _add_hibiscus_blossom(mb, stem_base, head_pos, tilt_dir, scale, phase, rng):
    """Multi-petal sculpted tropical hibiscus: arched stem, calyx, 5 curved overlapping crimson/coral petals & projecting golden stamen spike."""
    base_v = Vector(stem_base)
    head_v = Vector(head_pos)
    mid_v = base_v.lerp(head_v, 0.52) + Vector(tilt_dir).normalized() * (0.06 * scale) + Vector((0.0, 0.04 * scale, 0.0))
    tube(mb, [base_v, mid_v, head_v], [0.020 * scale, 0.015 * scale, 0.012 * scale], 4, 'foliage', C_LEAF_MID, caps=(False, True), mode='smooth', suv2=[(0.02, phase), (0.28, phase), (0.52, phase)])

    # Blossom orientation frame: flower faces upward & gently outward along tilt_dir
    f_up = (Vector((0.0, 1.0, 0.0)) * 0.78 + Vector(tilt_dir).normalized() * 0.62).normalized()
    ref = Vector((1.0, 0.0, 0.0)) if abs(f_up.x) < 0.8 else Vector((0.0, 0.0, 1.0))
    f_x = (ref - f_up * ref.dot(f_up)).normalized()
    f_z = f_up.cross(f_x).normalized()

    # Small green 5-sided calyx cup cradling the petals
    c_bot = [head_v - f_up * (0.045 * scale) + (f_x * cos(2 * pi * k / 5.0) + f_z * sin(2 * pi * k / 5.0)) * (0.018 * scale) for k in range(5)]
    c_top = [head_v + f_up * (0.012 * scale) + (f_x * cos(2 * pi * k / 5.0) + f_z * sin(2 * pi * k / 5.0)) * (0.046 * scale) for k in range(5)]
    loft(mb, [c_bot, c_top], 'foliage', C_LEAF_DEEP, closed=True, caps=(True, False), mode='flat', suv2=[(0.50, phase), (0.54, phase)])

    # 5 overlapping curved & cupped crimson/coral hibiscus petals (double-sided so visible from all angles on culled 'paint')
    base_rot = rng.uniform(0.0, 2.0 * pi)
    p_len = 0.165 * scale
    p_hw = 0.068 * scale
    c_throat = mul(C_FLOWER, 0.44)
    c_body = jit(C_FLOWER, rng, 0.09, 0.04)
    c_rim = mix(c_body, C_CREAM, 0.26)
    c_back = mul(c_body, 0.78)
    for pi_idx in range(5):
        ang = base_rot + pi_idx * (2.0 * pi / 5.0)
        p_dir = (f_x * cos(ang) + f_z * sin(ang)).normalized()
        p_tan = f_up.cross(p_dir).normalized()
        # Slight pinwheel overlap twist so adjacent petals nestle over each other cleanly
        twist = radians(12.0)
        w_vec = (p_tan * cos(twist) + f_up * sin(twist)).normalized()

        p0 = head_v + f_up * (0.008 * scale) + p_dir * (0.012 * scale)
        p1 = p0 + p_dir * (p_len * 0.42) + f_up * (p_len * 0.34)
        p2 = p0 + p_dir * (p_len * 0.80) + f_up * (p_len * 0.40)
        p3 = p0 + p_dir * (p_len * 1.00) + f_up * (p_len * 0.26)

        # Front (inner cup) face: normal points toward +f_up
        v0 = mb.v(p0)
        v1a = mb.v(p1 - w_vec * (p_hw * 0.78))
        v1b = mb.v(p1 + w_vec * (p_hw * 0.78))
        v2a = mb.v(p2 - w_vec * p_hw)
        v2b = mb.v(p2 + w_vec * p_hw)
        v3 = mb.v(p3)
        uv0, uv1a, uv1b, uv2a, uv2b, uv3 = (0.0, 0.5), (0.38, 0.20), (0.38, 0.80), (0.76, 0.12), (0.76, 0.88), (1.0, 0.5)
        mb.f([v0, v1a, v1b], 'paint', [c_throat, c_body, c_body], [uv0, uv1a, uv1b], smooth=True)
        mb.f([v1a, v2a, v2b, v1b], 'paint', [c_body, c_rim, c_rim, c_body], [uv1a, uv2a, uv2b, uv1b], smooth=True)
        mb.f([v2a, v3, v2b], 'paint', [c_rim, mix(c_rim, C_CREAM, 0.20), c_rim], [uv2a, uv3, uv2b], smooth=True)
        # Back (outer cup) face: reversed winding for 100% solid silhouette from beneath
        b0, b1a, b1b, b2a, b2b, b3 = mb.v(p0), mb.v(p1 - w_vec * (p_hw * 0.78)), mb.v(p1 + w_vec * (p_hw * 0.78)), mb.v(p2 - w_vec * p_hw), mb.v(p2 + w_vec * p_hw), mb.v(p3)
        mb.f([b0, b1b, b1a], 'paint', [mul(c_throat, 0.8), c_back, c_back], [uv0, uv1b, uv1a], smooth=True)
        mb.f([b1b, b2b, b2a, b1a], 'paint', [c_back, mul(c_rim, 0.82), mul(c_rim, 0.82), c_back], [uv1b, uv2b, uv2a, uv1a], smooth=True)
        mb.f([b2b, b3, b2a], 'paint', [mul(c_rim, 0.82), mul(c_rim, 0.78), mul(c_rim, 0.82)], [uv2b, uv3, uv2a], smooth=True)

    # Projecting golden stamen column & pollen anther buds rising cleanly out of the hibiscus throat
    st0 = head_v + f_up * (0.012 * scale)
    st1 = st0 + f_up * (0.095 * scale) + f_x * (0.012 * scale)
    st2 = st0 + f_up * (0.185 * scale) + f_x * (0.024 * scale)
    tube(mb, [st0, st1, st2], [0.013 * scale, 0.009 * scale, 0.006 * scale], 4, 'paint', C_GOLD, caps=(False, True), mode='smooth', scols=[mix(C_FLOWER, C_GOLD, 0.45), C_GOLD, C_CREAM])
    for ai in range(3):
        a_ang = ai * (2.0 * pi / 3.0) + base_rot
        apos = st2 + (f_x * cos(a_ang) + f_z * sin(a_ang)) * (0.016 * scale) + f_up * (0.010 * scale)
        ellipsoid(mb, apos, (0.014 * scale, 0.014 * scale, 0.014 * scale), 'paint', C_GOLD if ai % 2 == 0 else C_CREAM, 5, 3)


def gen_bush_fern(outdir):
    clear_scene()
    set_foliage_style('palm')
    rng = random.Random(SEED + 37)
    mb = MB('BushFern', seed=37)

    # 1. Earthy mossy root heart mound (embedded cleanly below y = 0 for sloped ground)
    ellipsoid(mb, (0.0, 0.05, 0.0), (0.38, 0.24, 0.38), 'bark_banyan', mix(C_TRUNK_DARK, C_MOSS, 0.22), 10, 5)

    # 2. Three lush rosette tiers (10 outer + 7 mid + 5 upright inner = 22 pinnate fern fronds!)
    tiers = [
        # (count, pmin, pmax, lmin, lmax, width, droop, tint, n_segs, n_leaflets, stem_w)
        (10, 12.0, 23.0, 1.18, 1.52, 0.46, 0.37, 0.16, 7, 9, 0.022),
        ( 7, 32.0, 46.0, 0.88, 1.16, 0.38, 0.30, 0.56, 6, 8, 0.019),
        ( 5, 52.0, 68.0, 0.58, 0.82, 0.29, 0.22, 0.96, 5, 6, 0.016),
    ]
    for count, pmin, pmax, lmin, lmax, w0, drp, tint, segs, n_leaf, stw in tiers:
        for i in range(count):
            az = i * (2.0 * pi / count) + rng.uniform(-0.18, 0.18) + tint * 0.55
            _add_palm_frond(
                mb, Vector((cos(az) * 0.06, 0.10 + tint * 0.04, sin(az) * 0.06)), az,
                pitch_deg=rng.uniform(pmin, pmax),
                length=rng.uniform(lmin, lmax),
                width=w0 * rng.uniform(0.90, 1.12),
                droop=drp, tier_tint=tint, phase=rng.random(), rng=rng,
                n_segs=segs, n_leaflets=n_leaf, stem_width=stw, t_start=0.07, is_fern=True
            )

    # 3. Three sculpted coiled fiddlehead shoots curling prominently upward in the mossy root heart
    for fi in range(3):
        faz = fi * (2.0 * pi / 3.0) + 0.65 + rng.uniform(-0.20, 0.20)
        froot = (cos(faz) * 0.12, 0.12, sin(faz) * 0.12)
        _add_fiddlehead(mb, froot, faz, rng.uniform(0.39, 0.52), rng.uniform(0.066, 0.082), rng.random(), rng)

    # 4. Four multi-petal sculpted tropical hibiscus blossoms for vibrant painterly colour accents
    for bi in range(4):
        baz = bi * (2.0 * pi / 4.0) + 0.35 + rng.uniform(-0.24, 0.24)
        s_base = (cos(baz) * 0.12, 0.14, sin(baz) * 0.12)
        h_rad = rng.uniform(0.30, 0.44)
        h_pos = (cos(baz) * h_rad, rng.uniform(0.56, 0.78), sin(baz) * h_rad)
        _add_hibiscus_blossom(mb, s_base, h_pos, (cos(baz), 0.15, sin(baz)), rng.uniform(0.92, 1.15), rng.random(), rng)

    build(mb)
    export_glb(outdir, 'bush_fern.glb')


def gen_rock_boulder(outdir):
    clear_scene()
    rng = random.Random(SEED + 51)
    mb = MB('RockBoulder', seed=51)
    pts = []
    # Sculpted sunlit coastal-limestone boulder cluster harmonizing with Q3A cliffs (emerald moss cap + waterline tide band only at y < 0.25!)
    pts += faceted_rock(mb, (0.0, 0.56, 0.0), (1.78, 1.38, 1.58), 'rock', C_STONE_PALE, C_STONE_WARM, C_STONE_OCHRE, rng, subdiv=3, warp=0.25, strata=0.14, moss_cap=True, ledge_sharp=0.13, tide_band=True, uv_scale=0.68)
    pts += faceted_rock(mb, (1.26, 0.14, 0.72), (0.96, 0.80, 0.88), 'rock', C_STONE_PALE, mix(C_STONE_WARM, C_STONE_PALE, 0.25), C_STONE_OCHRE, rng, subdiv=2, warp=0.24, strata=0.12, rot_deg=(8, 42, -5), moss_cap=True, ledge_sharp=0.10, tide_band=True, uv_scale=0.68)
    pts += faceted_rock(mb, (-1.12, -0.04, -0.68), (0.90, 0.68, 0.82), 'rock', C_STONE_PALE, C_STONE_WARM, C_STONE_OCHRE, rng, subdiv=2, warp=0.22, strata=0.10, rot_deg=(-6, -30, 9), moss_cap=True, ledge_sharp=0.10, tide_band=True, uv_scale=0.68)
    pts += faceted_rock(mb, (0.32, -0.14, -1.16), (0.64, 0.44, 0.56), 'rock', C_STONE_PALE, C_STONE_WARM, C_STONE_OCHRE, rng, subdiv=2, warp=0.20, strata=0.09, rot_deg=(5, 118, -7), ledge_sharp=0.08, tide_band=True, uv_scale=0.68)
    build(mb)
    col_piece('col_rock_boulder', pts)
    export_glb(outdir, 'rock_boulder.glb')

def _limestone_monolith(mb, ring_specs, sides, rng, rot_y=0.0, twist=0.18, apex_y=None, apex_off=(0.0, 0.0), uv_scale=0.32):
    """Build a continuous tapered faceted sunlit limestone spire harmonizing with Q3A coastal cliffs."""
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
        # Warm sunlit sandstone/limestone cliffs blending upward into pale ivory crests
        pale_t = smooth01((fc.y - 1.2) / 11.0)
        facet_var = max(-0.5, min(0.5, fn.x * 0.35 - fn.z * 0.30 + fn.y * 0.40))
        ivory_t = max(0.0, min(1.0, pale_t * 0.72 + 0.24 + facet_var * 0.16))
        base = mix(C_STONE_WARM, C_STONE_PALE, ivory_t)
        # Subtle warm ochre sedimentary strata bands across the tall monolith face
        st_wave = sin(fc.y * 0.85 + 0.4 * sin(fc.x * 0.5 - fc.z * 0.5))
        if st_wave < -0.20:
            base = mix(base, C_STONE_OCHRE, (-st_wave - 0.20) * 0.28)
        if fn.y < -0.10:
            base = mix(base, C_STONE_OCHRE, 0.30)
        elif fn.y > 0.48:
            base = mix(base, C_STONE_PALE, 0.25)
            # Rich emerald coastal moss cap accents on upward-facing spire shoulders
            if fc.y > 1.2 and fn.y > 0.56:
                m_t = smooth01((fn.y - 0.56) / 0.35)
                base = mix(base, mix(C_MOSS, C_LEAF_MID, 0.30), m_t * 0.72)
        # Subtle dark wet-slate / barnacle tide band ONLY near the very bottom waterline base (y < 0.25)
        if fc.y < 0.25:
            tide_t = smooth01((0.25 - fc.y) / 1.10)
            wet_col = mix(C_STONE_DARK, C_SEA_MOSS, 0.30)
            base = mix(base, wet_col, tide_t * 0.65)
        return jit(base, rng, 0.042, 0.015)

    mb.newoff()
    for ri in range(n_rings - 1):
        r0, r1 = rings[ri], rings[ri + 1]
        inside = 0.5 * (centers[ri] + centers[ri + 1])
        for k in range(sides):
            kn = (k + 1) % sides
            q = [r0[k], r0[kn], r1[kn], r1[k]]
            mb.fp(q, 'rock', _stone_face_col(q, inside), (1, 0, 0), inside, smooth=False, uv_scale=uv_scale)

    # Bottom cap
    mb.fp(rings[0], 'rock', C_STONE_SHADE, (1, 0, 0), centers[0] + Vector((0, 1.0, 0)), smooth=False, uv_scale=uv_scale)

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
            mb.fp(tri, 'rock', _stone_face_col(tri, inside_top), (1, 0, 0), inside_top, smooth=False, uv_scale=uv_scale)
    else:
        inside_top = top_c - Vector((0, 1.0, 0))
        mb.fp(top_ring, 'rock', _stone_face_col(top_ring, inside_top), (1, 0, 0), inside_top, smooth=False, uv_scale=uv_scale)

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
    all_pts = _limestone_monolith(mb, main_rings, sides=12, rng=rng, rot_y=0.22, twist=0.26, apex_y=19.2, apex_off=(-0.10, -0.04), uv_scale=0.32)

    # Fused secondary limestone shoulder fin for an iconic asymmetric horizon silhouette
    fin_rings = [
        (-4.0, 2.45, 2.15, 1.70, -0.45),
        (-0.8, 2.20, 1.92, 1.85, -0.50),
        ( 2.4, 1.88, 1.62, 2.05, -0.58),
        ( 5.6, 1.46, 1.24, 2.22, -0.68),
        ( 8.4, 0.95, 0.78, 2.38, -0.76),
        (10.4, 0.44, 0.34, 2.50, -0.82),
    ]
    all_pts += _limestone_monolith(mb, fin_rings, sides=9, rng=rng, rot_y=-0.45, twist=-0.18, apex_y=11.3, apex_off=(0.08, -0.04), uv_scale=0.35)

    # Wave-cut limestone base buttress anchoring the opposite flank into the surf
    spur_rings = [
        (-3.8, 2.10, 1.85, -1.75, 1.05),
        (-1.0, 1.85, 1.60, -1.82, 1.08),
        ( 1.6, 1.42, 1.22, -1.70, 0.98),
        ( 3.6, 0.78, 0.66, -1.52, 0.85),
    ]
    all_pts += _limestone_monolith(mb, spur_rings, sides=9, rng=rng, rot_y=0.85, twist=0.12, apex_y=4.4, apex_off=(0.12, -0.06), uv_scale=0.40)

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
    # Dramatic sunlit stratified coastal limestone arch (~16 m span, ~12.5 m tall, open passable central vault!)
    pts_l = []
    pts_r = []
    pts_b = []
    c_mid_hi = mix(C_STONE_WARM, C_STONE_PALE, 0.32)
    # Left & right sea-pillars extending to y = -3.0 m (wet tide band ONLY at y < 0.25!)
    pts_l += faceted_rock(mb, (-6.2, 0.8, 0.0), (2.8, 4.2, 2.9), 'rock', C_STONE_PALE, C_STONE_WARM, C_STONE_OCHRE, rng, subdiv=2, warp=0.22, strata=0.15, rot_deg=(0, 15, -6), ledge_sharp=0.11, tide_band=True, uv_scale=0.40)
    pts_l += faceted_rock(mb, (-5.4, 5.6, 0.1), (2.3, 3.6, 2.4), 'rock', C_STONE_PALE, c_mid_hi, C_STONE_WARM, rng, subdiv=2, warp=0.22, strata=0.15, rot_deg=(2, -10, -14), moss_cap=True, ledge_sharp=0.11, tide_band=True, uv_scale=0.40)
    pts_r += faceted_rock(mb, (6.2, 0.8, 0.1), (2.9, 4.3, 2.8), 'rock', C_STONE_PALE, C_STONE_WARM, C_STONE_OCHRE, rng, subdiv=2, warp=0.22, strata=0.15, rot_deg=(0, -22, 7), ledge_sharp=0.11, tide_band=True, uv_scale=0.40)
    pts_r += faceted_rock(mb, (5.3, 5.8, -0.1), (2.2, 3.8, 2.3), 'rock', C_STONE_PALE, c_mid_hi, C_STONE_WARM, rng, subdiv=2, warp=0.22, strata=0.15, rot_deg=(-3, 18, 15), moss_cap=True, ledge_sharp=0.11, tide_band=True, uv_scale=0.40)
    # Vaulted keystone arch span (5 chunky interlocking sunlit limestone masses with emerald moss crown!)
    span_specs = [
        (-3.6, 9.2, 0.0, (2.2, 2.1, 2.2), (0, 8, -24)),
        (-1.2, 10.6, 0.05, (2.3, 1.9, 2.1), (2, -12, -8)),
        (1.3, 10.7, -0.05, (2.4, 2.0, 2.2), (-2, 14, 10)),
        (3.6, 9.3, 0.0, (2.1, 2.0, 2.1), (0, -9, 26)),
        (-0.2, 12.1, 0.0, (1.8, 1.15, 1.5), (0, 5, -4)),  # emerald moss-crowned crest crag
    ]
    for x, y, z, rad, rot in span_specs:
        top_c = mix(C_MOSS, C_LEAF_MID, 0.30) if y > 11.2 else C_STONE_PALE
        pts_b += faceted_rock(mb, (x, y, z), rad, 'rock', top_c, c_mid_hi, C_STONE_WARM, rng, subdiv=2, warp=0.20, strata=0.12, rot_deg=rot, moss_cap=True, ledge_sharp=0.10, tide_band=True, uv_scale=0.40)
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

    # Heavy longitudinal stringers under deck + outer harbour fascia rub-rails
    for sx in (-1.45, -0.50, 0.50, 1.45):
        box2(mb, (sx - 0.11, DECK_Y - 0.34, -L + 0.15), (sx + 0.11, DECK_Y - 0.10, 0.2), 'wood', jit(C_DARK, rng, 0.05), 0.018, (0, 0, 1))
    # Weathered outer timber fascia skirts along +/-X pier edges (just inside ±1.80 m)
    for sx in (-1.75, 1.75):
        box2(mb, (sx - 0.04, DECK_Y - 0.30, -L + 0.08), (sx + 0.04, DECK_Y - 0.08, 0.08), 'wood', jit(C_WEATH, rng, 0.06), 0.012, (0, 0, 1))

    # Cross-beams & deep timber pilings every 3.2 m (seaward port bollard top strictly at (-1.58, 2.23, -15.6) for PierFogBell!)
    z_bents = [0.0, -3.2, -6.4, -9.6, -12.8, -15.6]
    for bi, zb in enumerate(z_bents):
        # Cross cap timber + forged iron end-clamp plates
        cbox(mb, (0.0, DECK_Y - 0.36, zb), (W + 0.10, 0.24, 0.24), 'wood', jit(C_DARK, rng, 0.06), 0.02, (1, 0, 0))
        for sx in (-1.58, 1.58):
            cbox(mb, (sx, DECK_Y - 0.36, zb), (0.42, 0.26, 0.27), 'iron', C_IRON, 0.0)
        # Diagonal sway brace between pilings
        for sgn in (-1, 1):
            tube(mb, [(sgn * 1.56, DECK_Y - 0.45, zb), (-sgn * 1.56, DECK_Y - 2.35, zb)], 0.075, 5, 'wood', C_WEATH, mode='flat')
        for sx in (-1.58, 1.58):
            # Piling rises above deck as mooring post on alternate & end bents
            is_bollard = (bi in (0, 2, 4, 5))
            top_y = DECK_Y + (0.88 if is_bollard else -0.10)  # 2.23 m exact on bollards!
            # Underwater tarred base + dark wet tidal collar + crusted barnacle waterline ring + dry weathered timber above
            with xf(mb, T(sx, 0.0, zb)):
                cyl(mb, 0.20, PILING_BOT, -0.32, 8, 'wood', C_TAR, False, 0.0, 0.195)
                # Dark wet splash-zone timber collar (y = -0.32..+0.44)
                cyl(mb, 0.196, -0.32, 0.44, 8, 'wood', mix(C_TAR, C_SEA_MOSS, 0.24), False, 0.0, 0.190)
                # Crisp barnacle-encrusted waterline collar ring right around tidal wash (y = -0.05..+0.28)
                lathe(mb, [
                    (0.192, -0.06), (0.228, 0.03), (0.238, 0.12),
                    (0.218, 0.22), (0.188, 0.30),
                ], 8, 'stone', jit(mix(C_STONE_WARM, C_STONE_PALE, 0.58), rng, 0.06), False)
                # 4 irregular protruding pale coral-barnacle crust clusters around each piling's waterline
                for bk in range(4):
                    bang = bk * (pi * 0.5) + rng.uniform(-0.32, 0.32) + bi * 0.6
                    by = rng.uniform(0.02, 0.24)
                    bcol = jit(C_STONE_PALE if bk % 2 == 0 else C_STONE_WARM, rng, 0.05)
                    cbox(mb, (cos(bang) * 0.21, by, sin(bang) * 0.21),
                         (rng.uniform(0.09, 0.13), rng.uniform(0.07, 0.12), rng.uniform(0.09, 0.13)),
                         'stone', bcol, 0.0, M=R('Y', degrees_of(bang)))
                # Dry sun-bleached weathered harbour piling above tidal splash collar
                cyl(mb, 0.190, 0.42, top_y, 8, 'wood', jit(C_WEATH, rng, 0.07), False, 0.02, 0.175)
                if is_bollard:
                    # Forged iron collar + beveled timber cap + wrapped mooring rope
                    cyl(mb, 0.188, top_y - 0.16, top_y - 0.06, 8, 'iron', C_IRON, False, 0.0)
                    with xf(mb, T(0, DECK_Y + 0.34, 0)):
                        for ri in range(3):
                            with xf(mb, T(0, ri * 0.048, 0)):
                                torus(mb, 0.185, 0.024, 10, 4, 'rope', C_ROPE, True)
            if is_bollard:
                col_box('col_post_%d_%s' % (bi, 'R' if sx > 0 else 'L'),
                        (sx - 0.20, DECK_Y, zb - 0.20), (sx + 0.20, top_y, zb + 0.20))

    # Individual chunky weathered deck planks with subtle beveled plank variation (top right at y = +1.35 m)
    z = 0.05
    plank_idx = 0
    plank_tones = (C_DECK, C_HULL, C_WEATH, C_DECK, C_DRIFT)
    while z > -L:
        pw = rng.uniform(0.31, 0.41)
        z0 = max(-L, z - pw + rng.uniform(0.018, 0.028))
        z1 = z
        yc = DECK_Y - 0.05 + rng.uniform(-0.007, 0.007)
        zm = 0.5 * (z0 + z1)
        p_ch = rng.uniform(0.014, 0.022)
        # Every 5th course is a staggered twin-butt plank pair with subtle bevel & colour shift
        if plank_idx % 5 == 2 and (z1 - z0) > 0.24:
            split_x = rng.uniform(-0.55, 0.55)
            w_l = (split_x + HW) - 0.02 + rng.uniform(-0.03, 0.04)
            w_r = (HW - split_x) - 0.02 + rng.uniform(-0.03, 0.04)
            c_l = jit(plank_tones[plank_idx % len(plank_tones)], rng, 0.08, 0.025)
            c_r = jit(plank_tones[(plank_idx + 2) % len(plank_tones)], rng, 0.08, 0.025)
            cbox(mb, (-HW + w_l * 0.5, yc, zm), (w_l, 0.10, z1 - z0), 'wood', c_l, p_ch, (1, 0, 0))
            cbox(mb, (HW - w_r * 0.5, yc + rng.uniform(-0.004, 0.004), zm), (w_r, 0.10, z1 - z0), 'wood', c_r, p_ch, (1, 0, 0))
        else:
            w_jit = W + rng.uniform(-0.07, 0.09)
            pcol = jit(plank_tones[plank_idx % len(plank_tones)], rng, 0.085, 0.025)
            cbox(mb, (rng.uniform(-0.025, 0.025), yc, zm), (w_jit, 0.10, z1 - z0), 'wood', pcol, p_ch, (1, 0, 0))
        # Subtle forged iron bolt heads along outer stringer lines on every 4th plank
        if plank_idx % 4 == 1:
            for bx in (-1.45, 1.45):
                cbox(mb, (bx, DECK_Y + 0.004, zm), (0.045, 0.016, 0.045), 'iron', C_IRON, 0.0)
        z -= pw
        plank_idx += 1

    # Low beveled timber curb rails along outer edges (with generous mooring gaps & iron strap ties!)
    for sx in (-1.68, 1.68):
        for seg_z0, seg_z1 in ((-0.4, -2.8), (-3.6, -6.0), (-6.8, -9.2), (-10.0, -12.4), (-13.2, -15.2)):
            cbox(mb, (sx, DECK_Y + 0.07, 0.5 * (seg_z0 + seg_z1)), (0.14, 0.12, abs(seg_z1 - seg_z0)), 'wood', C_DARK, 0.018, (0, 0, 1))
            for tz in (seg_z0 - 0.18, seg_z1 + 0.18):
                cbox(mb, (sx, DECK_Y + 0.075, tz), (0.16, 0.13, 0.06), 'iron', C_IRON, 0.0)

    # Landward timber ramp (z = 0.0 to +2.2, descending smoothly from y = 1.35 to y = 0.12 so pawns walk straight on!)
    ramp_steps = 6
    for i in range(ramp_steps):
        t0 = i / float(ramp_steps)
        t1 = (i + 1) / float(ramp_steps)
        rz0 = t0 * 2.2
        rz1 = t1 * 2.2
        ry = DECK_Y - 0.05 - (DECK_Y - 0.12) * (0.5 * (t0 + t1))
        cbox(mb, (0.0, ry, 0.5 * (rz0 + rz1)), (W - 0.08, 0.12, (rz1 - rz0) * 0.96), 'wood', jit(C_DECK, rng, 0.07), 0.016, (1, 0, 0))
    for sx in (-1.45, 0.0, 1.45):
        tube(mb, [(sx, DECK_Y - 0.18, 0.0), (sx, -0.05, 2.3)], 0.12, 4, 'wood', C_DARK, mode='flat')

    # Heavy coiled hemp mooring ropes around TWO prominent bollards (starboard -6.4 & port -12.8; keeps PierFogBell bollard clear!)
    for bx, bz, dx_in in ((1.58, -6.4, -0.42), (-1.58, -12.8, 0.42)):
        # Thick 4-turn hawser wraps gripping the bollard shaft
        with xf(mb, T(bx, DECK_Y + 0.14, bz)):
            for ri in range(4):
                with xf(mb, T(0.0, ri * 0.064, 0.0)):
                    torus(mb, 0.210, 0.036, 10, 4, 'rope', mul(C_ROPE, 0.90 + 0.10 * (ri % 2)), True)
        # Heavy 3-turn coiled mooring hawser pile resting on the pier deck right beside the bollard
        for ti in range(3):
            rr = 0.32 * (1.0 - 0.18 * ti)
            with xf(mb, T(bx + dx_in, DECK_Y + 0.034 * (1.0 + ti * 1.65), bz + 0.36)):
                torus(mb, rr, 0.034, 10, 4, 'rope', mul(C_ROPE, 0.92 + 0.08 * (ti % 2)), True)
        # Connecting hawser lead running from deck coil up onto the bollard wrap
        tube(mb, [
            (bx + dx_in * 0.85, DECK_Y + 0.06, bz + 0.30),
            (bx + dx_in * 0.45, DECK_Y + 0.14, bz + 0.18),
            (bx + dx_in * 0.28, DECK_Y + 0.26, bz + 0.04),
        ], 0.032, 5, 'rope', C_ROPE, mode='smooth')

    # 2 chunky braided rope ship-fenders hanging cleanly along the ship-mooring (+X starboard) side!
    # Outer edge reaches x = 1.85 + 0.135 = 1.985 m, safely clear of moored Sloop (2.72 m) & Brigantine (2.10 m).
    for fz in (-7.8, -13.8):
        fx = 1.85
        # Lanyard rope looped over starboard curb rail & dropping over fascia to fender crown
        tube(mb, [
            (1.64, DECK_Y + 0.06, fz),
            (1.74, DECK_Y + 0.14, fz),
            (1.84, DECK_Y + 0.02, fz),
            (fx, 0.94, fz),
        ], 0.026, 5, 'rope', C_ROPE, mode='smooth')
        # Woven barrel-shaped braided hemp ship-fender body with ribbed hemp lacing & Turk's-head collar bands
        with xf(mb, T(fx, 0.0, fz)):
            lathe(mb, [
                (0.0, 0.26), (0.068, 0.29), (0.115, 0.38),
                (0.134, 0.56), (0.134, 0.74),
                (0.112, 0.88), (0.064, 0.94), (0.0, 0.96),
            ], 8, 'rope', jit(C_ROPE, rng, 0.05), True)
            # Top & bottom Turk's-head braided collar rings + center wear band
            for fy, fr, fcol in ((0.87, 0.116, mul(C_ROPE, 0.80)), (0.64, 0.134, mul(C_ROPE, 0.86)), (0.39, 0.118, mul(C_ROPE, 0.78))):
                with xf(mb, T(0.0, fy, 0.0)):
                    torus(mb, fr, 0.022, 8, 4, 'rope', fcol, True)

    # Extra deck mooring coil & forged iron dock cleats
    rope_coil(mb, (-1.28, DECK_Y, -4.4), 0.25, 3, r=0.028)
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

    # 1. Stepped dressed sunlit coral-limestone foundation plinth (plunges to y = -1.85 m for sloped harbour terraces!)
    # Lower broad battered footing skirt (y = -1.85..-0.10)
    loft(mb, [
        [(-5.08, -1.85, -3.88), (5.08, -1.85, -3.88), (5.08, -1.85, 4.08), (-5.08, -1.85, 4.08)],
        [(-4.96, -0.10, -3.76), (4.96, -0.10, -3.76), (4.96, -0.10, 3.96), (-4.96, -0.10, 3.96)],
    ], 'stone', C_STONE_OCHRE, closed=True, caps=(True, True), mode='flat',
        scols=[mix(C_STONE_OCHRE, C_STONE_SHADE, 0.42), mix(C_STONE_WARM, C_STONE_OCHRE, 0.45)], swap_uv=True)
    # Upper stepped dressed ashlar foundation course (y = -0.10..FLOOR_Y - 0.10)
    box2(mb, (-4.82, -0.12, -3.62), (4.82, FLOOR_Y - 0.10, 3.82), 'stone', C_STONE_WARM, 0.04)
    # Crisp beveled pale-limestone water-table coping sill capping the stone plinth
    bevel_slab(mb, (0.0, FLOOR_Y - 0.03, 0.10), (9.84, 0.18, 7.64), 'stone', C_STONE_PALE, 0.035,
               top_col=C_STONE_PALE, bot_col=mul(C_STONE_WARM, 0.78))
    # Alternating short/long dressed corner stone quoins on all 4 foundation corners
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            cx = sx * 4.78
            cz = -3.58 if sz < 0 else 3.78
            for yi in range(3):
                long_x = (yi % 2 == 0)
                qw = 0.72 if long_x else 0.50
                qd = 0.50 if long_x else 0.72
                qcol = jit(mix(C_STONE_WARM, C_STONE_PALE, 0.55 if long_x else 0.28), rng, 0.05)
                bevel_slab(mb, (cx, -0.45 + yi * 0.40, cz), (qw, 0.34, qd), 'stone', qcol, 0.028)
    # Stepped dressed stone foundation piers anchoring the front porch corners cleanly below y = -1.75 m
    for px in (-4.38, -1.55, 1.55, 4.38):
        box2(mb, (px - 0.34, -1.75, -5.74), (px + 0.34, FLOOR_Y - 0.08, -5.12), 'stone', jit(C_STONE_WARM, rng, 0.06), 0.03)
        bevel_slab(mb, (px, FLOOR_Y - 0.04, -5.43), (0.76, 0.12, 0.70), 'stone', C_STONE_PALE, 0.024)

    # 2. Slightly flared whimsical pirate stucco walls with subtle warm ochre coastal salt-weathering near base!
    MID_W_Y = FLOOR_Y + 0.78
    t_mid = (MID_W_Y - FLOOR_Y) / (EAVE_Y - FLOOR_Y)
    secs = [
        [(-4.55, FLOOR_Y, -3.35), (4.55, FLOOR_Y, -3.35), (4.55, FLOOR_Y, 3.55), (-4.55, FLOOR_Y, 3.55)],
        [(-(4.55 + 0.27 * t_mid), MID_W_Y, -(3.35 + 0.21 * t_mid)), (4.55 + 0.27 * t_mid, MID_W_Y, -(3.35 + 0.21 * t_mid)),
         (4.55 + 0.27 * t_mid, MID_W_Y, 3.55 + 0.21 * t_mid), (-(4.55 + 0.27 * t_mid), MID_W_Y, 3.55 + 0.21 * t_mid)],
        [(-4.82, EAVE_Y, -3.56), (4.82, EAVE_Y, -3.56), (4.82, EAVE_Y, 3.76), (-4.82, EAVE_Y, 3.76)],
    ]
    c_plaster_base = mix(C_PLASTER, C_STONE_WARM, 0.24)
    loft(mb, secs, 'plaster', C_PLASTER, closed=True, caps=(True, True), mode='flat', scols=[c_plaster_base, C_PLASTER, C_PLASTER])

    # Gable triangles (left & right ends along X)
    for sx in (-1, 1):
        gx = sx * 4.80
        g_pts = [(gx, EAVE_Y - 0.05, -3.56), (gx, EAVE_Y - 0.05, 3.76), (gx, RIDGE_Y - 0.15, 0.10)]
        mb.fp(g_pts, 'plaster', C_PLASTER_SH, (0, 0, 1), (0, EAVE_Y, 0))

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

    # Chamfered oak timber roof-eave corbels tucked cleanly beneath front porch ledger, rear eaves & gable verges!
    for cx in (-4.40, -2.95, -1.48, 0.0, 1.48, 2.95, 4.40):
        stepped_corbel(mb, (cx, 3.38, -3.56), 0.0, 0.16, 0.36, 0.38, 'wood', C_DARK)
        stepped_corbel(mb, (cx, 3.56,  3.76), 180.0, 0.16, 0.42, 0.44, 'wood', C_DARK)
    for sx in (-1.0, 1.0):
        rot_g = 90.0 if sx < 0 else -90.0
        for gy, gz in ((EAVE_Y + 0.95, -2.20), (EAVE_Y + 0.95, 2.40), (RIDGE_Y - 0.45, 0.10)):
            stepped_corbel(mb, (sx * 4.80, gy, gz), rot_g, 0.16, 0.40, 0.52, 'wood', C_DARK)

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
                mb.fp(p_top, 'shingle', c_sh, (1, 0, 0), (xm, y0 - 2.0, 0.10))
                mb.fp(p_bot, 'wood', mul(c_sh, 0.65), (1, 0, 0), (xm, y0 + 2.0, 0.10))
                # Front lip edge of shake course
                mb.fp([p_bot[3], p_bot[2], p_top[2], p_top[3]], 'shingle', mul(c_sh, 0.78), (1, 0, 0), (xm, y0, 0.10))
    # Heavy ridge cap timber + crimson bargeboards
    cbox(mb, (0.0, RIDGE_Y + 0.12, 0.10), (11.6, 0.32, 0.34), 'wood', C_DARK, 0.03)
    for sx in (-5.62, 5.62):
        for side_z in (-1, 1):
            tube(mb, [(sx, RIDGE_Y + 0.05, 0.10), (sx, EAVE_Y - 0.38, 0.10 + side_z * 4.65)], 0.14, 4, 'wood', C_RED, mode='flat')

    # Rustic crooked warm-sandstone chimney on +X rear roof slope
    chim_x, chim_z = 3.25, 1.85
    box2(mb, (chim_x - 0.62, EAVE_Y - 0.5, chim_z - 0.62), (chim_x + 0.62, RIDGE_Y + 0.65, chim_z + 0.62), 'stone', C_STONE_WARM, 0.05)
    bevel_slab(mb, (chim_x + 0.04, RIDGE_Y + 0.72, chim_z), (1.36, 0.16, 1.36), 'stone', mul(C_STONE_WARM, 0.85), 0.03)
    bevel_slab(mb, (chim_x + 0.05, RIDGE_Y + 0.88, chim_z), (1.46, 0.22, 1.46), 'stone', C_STONE_PALE, 0.035)
    cbox(mb, (chim_x + 0.05, RIDGE_Y + 1.06, chim_z), (0.90, 0.18, 0.90), 'stone', C_CHAR, 0.02)

    # Welcoming covered front timber porch (z = -3.4..-5.65, floor y = 0.58)
    box2(mb, (-4.55, -1.6, -5.65), (4.55, FLOOR_Y, -3.45), 'wood', C_DECK, 0.025)
    # Wide welcoming wooden steps down to ground (z = -5.65..-6.75)
    for si in range(3):
        sy = FLOOR_Y - (si + 1) * 0.19
        sz = -5.85 - si * 0.34
        cbox(mb, (0.0, sy, sz), (2.75, 0.20, 0.36), 'wood', jit(C_DECK, rng, 0.06), 0.02)
    # Porch posts, chamfered porch eave corbels & railing (leaving center doorway lane & TavernSignboard clear!)
    for px in (-4.30, -1.55, 1.55, 4.30):
        cbox(mb, (px, FLOOR_Y + 1.26, -5.42), (0.24, 2.52, 0.24), 'wood', C_DARK, 0.02)
        stepped_corbel(mb, (px, 2.96, -5.46), 0.0, 0.15, 0.36, 0.32, 'wood', C_DARK)
        col_box('col_porch_post_%d' % int(px * 10), (px - 0.14, FLOOR_Y, -5.56), (px + 0.14, FLOOR_Y + 2.8, -5.28))
    for rx in (-2.92, 2.92):
        cbox(mb, (rx, FLOOR_Y + 0.92, -5.42), (2.60, 0.12, 0.14), 'wood', C_HULL, 0.015)
        for bi in range(4):
            bx = rx - 0.95 + bi * 0.63
            cbox(mb, (bx, FLOOR_Y + 0.46, -5.42), (0.09, 0.82, 0.09), 'wood', C_WEATH, 0.01)
    # Slanted porch overhang roof (shelters porch from rain!)
    p_r_top = [(-4.75, 3.72, -3.45), (4.75, 3.72, -3.45), (4.75, 3.12, -6.05), (-4.75, 3.12, -6.05)]
    p_r_bot = [(p[0], p[1] - 0.18, p[2]) for p in p_r_top]
    mb.fp(p_r_top, 'thatch', C_THATCH, (1, 0, 0), (0, 1.0, -4.5))
    mb.fp(p_r_bot, 'wood', mul(C_DARK, 0.8), (1, 0, 0), (0, 5.0, -4.5))
    mb.fp([p_r_bot[3], p_r_bot[2], p_r_top[2], p_r_top[3]], 'wood', C_RED, (1, 0, 0), (0, 3.4, -3.0))

    # Heavy pirate plank front door with brass ring & iron hinges
    cbox(mb, (0.0, FLOOR_Y + 1.15, -3.46), (1.42, 2.26, 0.18), 'wood', C_HULL, 0.025)
    cbox(mb, (0.0, FLOOR_Y + 2.34, -3.50), (1.72, 0.20, 0.26), 'wood', C_DARK, 0.02)
    for hy in (FLOOR_Y + 0.65, FLOOR_Y + 1.72):
        cbox(mb, (-0.36, hy, -3.56), (0.62, 0.09, 0.04), 'iron', C_IRON, 0.008)
    with xf(mb, T(0.42, FLOOR_Y + 1.08, -3.58) @ M_Y2Z):
        torus(mb, 0.08, 0.02, 10, 5, 'brass', C_BRASS, True)

    # Glowing warm multi-pane tavern windows with weathered battened shutter trim, iron hinges & sill brackets!
    def add_window(pos, rot_y, w=1.25, h=1.18):
        with xf(mb, T(pos) @ R('Y', rot_y)):
            # Beveled projecting timber sill, mini sill corbel brackets & drip-hood lintel
            cbox(mb, (0, -h * 0.5 - 0.06, -0.06), (w + 0.38, 0.14, 0.28), 'wood', C_DARK, 0.022)
            for bx in (-w * 0.42, w * 0.42):
                cbox(mb, (bx, -h * 0.5 - 0.18, -0.06), (0.12, 0.14, 0.18), 'wood', C_DARK, 0.0)
            cbox(mb, (0, h * 0.5 + 0.06, -0.05), (w + 0.36, 0.15, 0.26), 'wood', C_DARK, 0.022)
            for sx in (-w * 0.5 - 0.07, w * 0.5 + 0.07):
                cbox(mb, (sx, 0, -0.04), (0.14, h + 0.12, 0.20), 'wood', C_DARK, 0.02)
            # Weathered coastal teal battened shutters with dark-oak cross-rails & forged iron strap hinges
            c_shutter = mix(C_TEAL, C_DRIFT, 0.16)
            for sx in (-1, 1):
                sh_x = sx * (w * 0.5 + 0.34)
                cbox(mb, (sh_x, 0, -0.04), (0.38, h, 0.065), 'wood', c_shutter, 0.014)
                for by in (-h * 0.34, 0.0, h * 0.34):
                    cbox(mb, (sh_x, by, -0.075), (0.36, 0.08, 0.032), 'wood', C_DARK, 0.0)
                for hy in (-h * 0.34, h * 0.34):
                    cbox(mb, (sh_x - sx * 0.08, hy, -0.092), (0.24, 0.042, 0.022), 'iron', C_IRON, 0.0)
            # Glowing warm glass pane
            cbox(mb, (0, 0, 0.0), (w, h, 0.06), 'window', C_GLASS, 0.0)
            # Mullion crossbars
            cbox(mb, (0, 0, -0.04), (w, 0.07, 0.06), 'wood', C_DARK, 0.0)
            cbox(mb, (0, 0, -0.04), (0.07, h, 0.06), 'wood', C_DARK, 0.0)

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
    # 1. Stepped dressed sunlit coral-limestone octagonal foundation plinth (plunges to y = -2.55 m!)
    # Lower broad battered footing plinth (y = -2.55..-0.12)
    lathe(mb, [(0, -2.55), (3.82, -2.55), (3.66, -0.12), (0, -0.12)], 8, 'stone', mix(C_STONE_OCHRE, C_STONE_SHADE, 0.36), False)
    # Projecting beveled pale-limestone water-table collar ring (y = -0.14..+0.34)
    cyl(mb, 3.62, -0.14, 0.34, 8, 'stone', C_STONE_PALE, False, 0.06, 3.44)
    # Main battered warm sunlit limestone base shaft (y = 0.30..6.02)
    lathe(mb, [(0, 0.30), (3.38, 0.30), (2.86, 3.40), (2.48, 6.02), (0, 6.02)], 8, 'stone', C_STONE_WARM, False)
    # 4 heavy stepped stone buttress ribs with alternating dressed corner quoins & beveled sloped cap stones
    for k in range(4):
        ang = k * 90.0 + 45.0
        with xf(mb, R('Y', ang)):
            cbox(mb, (0.0, 1.55, 2.95), (0.86, 6.5, 1.12), 'stone', jit(C_STONE_WARM, rng, 0.05), 0.045, M=R('X', -12))
            # Alternating dressed limestone quoin stones stepping up each battered buttress face
            for qi in range(4):
                qy = 0.55 + qi * 1.18
                qz = 3.50 - qi * 0.25
                qw = 0.96 if qi % 2 == 0 else 0.72
                bevel_slab(mb, (0.0, qy, qz), (qw, 0.42, 0.32), 'stone', jit(C_STONE_PALE if qi % 2 == 0 else C_STONE_WARM, rng, 0.05), 0.03)
            # Sloped beveled coping cap crowning the buttress shoulder
            bevel_slab(mb, (0.0, 4.92, 2.55), (0.98, 0.24, 1.16), 'stone', C_STONE_PALE, 0.035, M=R('X', 22))
    # Two-tier stepped beveled stone cornice collar at y = 5.84..6.42 + 8 chamfered stone/oak soffit corbels
    cyl(mb, 2.66, 5.84, 6.04, 8, 'stone', mul(C_STONE_WARM, 0.80), False, 0.03, 2.74)
    cyl(mb, 2.82, 6.02, 6.42, 8, 'stone', C_STONE_PALE, False, 0.06, 2.66)
    for k in range(8):
        ang = k * 45.0
        with xf(mb, R('Y', ang)):
            stepped_corbel(mb, (0.0, 5.88, -2.38), 0.0, 0.24, 0.52, 0.36, 'stone', C_STONE_WARM)

    # Dressed stone portal surround, quoined jambs & heavy arched timber entry door on -Z face
    for sx in (-0.82, 0.82):
        for qi in range(3):
            bevel_slab(mb, (sx, 0.45 + qi * 0.72, -3.26), (0.38 if qi % 2 == 0 else 0.28, 0.46, 0.44), 'stone', C_STONE_PALE, 0.025)
    bevel_slab(mb, (0.0, 2.62, -3.14), (1.92, 0.34, 0.52), 'stone', C_STONE_PALE, 0.035)
    cbox(mb, (0.0, 1.30, -3.22), (1.35, 2.40, 0.35), 'wood', C_DARK, 0.03)
    cbox(mb, (0.0, 1.30, -3.32), (1.05, 2.10, 0.22), 'wood', C_HULL, 0.02)
    for hy in (0.76, 1.84):
        cbox(mb, (-0.22, hy, -3.44), (0.56, 0.09, 0.04), 'iron', C_IRON, 0.008)

    # 2. Bold maritime banded sun-baked stucco tower shaft (y = 6.35..16.2) with crimson/cream bands & belt collars!
    bands = [
        (6.35, 8.8, 2.38, 2.18, 'plaster', mix(C_CREAM, C_STONE_WARM, 0.14)),
        (8.8, 11.4, 2.18, 1.98, 'plaster', C_RED),
        (11.4, 13.9, 1.98, 1.80, 'plaster', C_CREAM),
        (13.9, 16.2, 1.80, 1.66, 'plaster', C_RED),
    ]
    for y0, y1, r0, r1, mat, col in bands:
        cyl(mb, r0, y0, y1, 8, mat, col, False, 0.03, r1)
    # Subtle dressed stone/timber horizontal stringcourse rings separating tower bands
    for by, br in ((8.8, 2.24), (11.4, 2.04), (13.9, 1.86)):
        cyl(mb, br, by - 0.09, by + 0.09, 8, 'stone', C_STONE_PALE, False, 0.025, br)
    # Exterior chunky dark-oak corner ribs
    for k in range(8):
        ang = 2.0 * pi * k / 8.0 + pi / 8.0
        p0 = Vector((cos(ang) * 2.42, 6.2, sin(ang) * 2.42))
        p1 = Vector((cos(ang) * 1.72, 16.2, sin(ang) * 1.72))
        tube(mb, [p0, p1], 0.13, 4, 'wood', C_DARK, mode='flat')
    # Warm tower slit windows with beveled timber sills, drip-hoods & weathered teal shutter trim
    c_shutter = mix(C_TEAL, C_DRIFT, 0.18)
    for wy, wang in ((8.0, 0), (10.5, 90), (13.0, 180), (14.8, -90)):
        r_at = 2.40 - (wy - 6.2) * 0.072
        with xf(mb, R('Y', wang) @ T(0, wy, -r_at - 0.04)):
            cbox(mb, (0, 0, 0), (0.66, 1.08, 0.16), 'wood', C_DARK, 0.02)
            cbox(mb, (0, -0.58, -0.05), (0.86, 0.12, 0.24), 'wood', C_DARK, 0.018)
            cbox(mb, (0,  0.58, -0.05), (0.86, 0.13, 0.24), 'wood', C_DARK, 0.018)
            for sx in (-1, 1):
                cbox(mb, (sx * 0.46, 0.0, -0.04), (0.24, 0.94, 0.06), 'wood', c_shutter, 0.012)
                for by in (-0.30, 0.30):
                    cbox(mb, (sx * 0.46, by, -0.075), (0.22, 0.07, 0.025), 'wood', C_DARK, 0.006)
            cbox(mb, (0, 0, -0.05), (0.42, 0.82, 0.10), 'window', C_GLASS, 0.0)

    # 3. Cantilevered wooden watch gallery deck (y = 16.2, radius 3.05 m!) with chamfered oak corbels!
    cyl(mb, 3.08, 16.0, 16.32, 8, 'wood', C_DECK, False, 0.04, 3.08)
    for k in range(8):
        ang = 2.0 * pi * k / 8.0
        c, s = cos(ang), sin(ang)
        # Sculpted chamfered oak gallery corbel + heavy diagonal knee-brace
        with xf(mb, R('Y', -degrees_of(ang) - 90.0)):
            stepped_corbel(mb, (0.0, 16.00, -1.68), 0.0, 0.22, 0.78, 1.18, 'wood', C_DARK)
        tube(mb, [(c * 1.65, 14.3, s * 1.65), (c * 2.90, 16.05, s * 2.90)], 0.13, 4, 'wood', C_DARK, mode='flat')
        # Gallery balustrade posts & crimson top handrail
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
    # 8 forged iron lantern mullions + chamfered lantern roof-eave corbel brackets
    for k in range(8):
        ang = 2.0 * pi * k / 8.0
        cbox(mb, (cos(ang) * 1.46, 17.80, sin(ang) * 1.46), (0.14, 2.05, 0.14), 'iron', C_IRON, 0.015)
        with xf(mb, R('Y', -degrees_of(ang) - 90.0)):
            stepped_corbel(mb, (0.0, 18.72, -1.46), 0.0, 0.14, 0.36, 0.62, 'iron', C_IRON)
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
        faceted_rock(mb, (cos(ang) * rr, py, sin(ang) * rr), (sr * 1.2, sr * 0.7, sr), 'rock',
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
                mb.newoff()
                # Port side strake
                q = [(-b0, y0, z0), (-b1, y0, z1), (-b1 * 0.98, y1, z1), (-b0 * 0.98, y1, z0)]
                mb.fp(q, 'wood', p_col, (0, 0, 1), (0, 0, 0.5 * (z0 + z1)))
                mb.fp(q[::-1], 'wood', mul(p_col, 0.72), (0, 0, 1), (-6.0, 0, 0.5 * (z0 + z1)))
                # Starboard lower strakes only
                if si <= 1 or seg <= 2:
                    mb.newoff()
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
    cyl(mb, 0.56, -0.05, 0.08, 10, 'rock', C_CHAR, False, 0.02, 0.44)
    # Ring of 10 chunky faceted beach stones
    for i in range(10):
        ang = i * (2.0 * pi / 10.0) + rng.uniform(-0.14, 0.14)
        rr = rng.uniform(0.56, 0.66)
        sx = rng.uniform(0.18, 0.25)
        sy = rng.uniform(0.13, 0.21)
        sz = rng.uniform(0.17, 0.24)
        faceted_rock(mb, (cos(ang) * rr, sy * 0.55, sin(ang) * rr), (sx, sy, sz), 'rock',
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
        tube(mb, [p0, p1], [0.068, 0.052], 6, 'bark_banyan', jit(C_DARK if i % 2 == 0 else C_CHAR, rng, 0.08), mode='flat')

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
        mb.newoff()
        q = [(-1.35, 2.52, 0.0), (1.35, 2.52, 0.0), (1.35, 2.20, sz * 0.58), (-1.35, 2.20, sz * 0.58)]
        mb.fp(q, 'shingle', C_SHINGLE, (1, 0, 0), (0, 1.8, 0))
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
    mb.newoff()
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

def _add_broad_leaf_blade(
    mb, root, dir_out, up_hint, length, width, droop,
    c_base, c_mid, c_tip, w_base, w_tip, phase, rng, rounded=True
):
    """Smooth 4-tri curved rounded-ovate tropical broad-leaf blade with explicit positive-area UVs & UV2 wind weights."""
    d = Vector(dir_out)
    if d.length < 1e-6:
        return
    d.normalize()
    uh = Vector(up_hint)
    if uh.length < 1e-6:
        uh = Vector((0.0, 1.0, 0.0))
    else:
        uh.normalize()
    w_axis = uh.cross(d)
    if w_axis.length < 1e-4:
        ref = Vector((0.0, 0.0, 1.0)) if abs(d.z) < 0.8 else Vector((1.0, 0.0, 0.0))
        w_axis = ref.cross(d)
    w_axis.normalize()
    u_axis = d.cross(w_axis).normalized()

    # Subtle organic leaf roll so shingled overlapping broad leaves catch varied sunlight planes
    roll = rng.uniform(-0.34, 0.34)
    wv = (w_axis * cos(roll) + u_axis * sin(roll)).normalized()
    uv_n = d.cross(wv).normalized()
    up_w = Vector((0.0, 1.0, 0.0))

    p0 = Vector(root)
    if rounded:
        # Smooth quadratic arch for plump tropical banyan/ficus broadleaf (zero sharp mid-blade kink)
        p1 = p0 + d * (length * 0.30) + uv_n * (length * 0.10) - up_w * (droop * length * 0.09)
        p2 = p0 + d * (length * 0.68) + uv_n * (length * 0.04) - up_w * (droop * length * 0.44)
        p3 = p0 + d * length - uv_n * (length * 0.08) - up_w * (droop * length)
        hw1 = width * 0.46
        hw2 = width * 0.42
    else:
        # Pointed trailing jungle vine leaf
        p1 = p0 + d * (length * 0.32) + uv_n * (length * 0.10) - up_w * (droop * length * 0.10)
        p2 = p0 + d * (length * 0.68) + uv_n * (length * 0.03) - up_w * (droop * length * 0.45)
        p3 = p0 + d * length - uv_n * (length * 0.10) - up_w * (droop * length)
        hw1 = width * 0.48
        hw2 = width * 0.34

    cup = uv_n * (width * 0.075)
    v0 = mb.v(p0)
    v1a = mb.v(p1 - wv * hw1 + cup)
    v1b = mb.v(p1 + wv * hw1 + cup)
    v2a = mb.v(p2 - wv * hw2 + cup * 0.45)
    v2b = mb.v(p2 + wv * hw2 + cup * 0.45)
    v3 = mb.v(p3)

    c_m2 = mix(c_mid, c_tip, 0.56)
    w1 = w_base + (w_tip - w_base) * 0.32
    w2 = w_base + (w_tip - w_base) * 0.70
    u2_0 = (max(0.0, min(1.0, w_base)), phase)
    u2_1 = (max(0.0, min(1.0, w1)), phase)
    u2_2 = (max(0.0, min(1.0, w2)), phase)
    u2_3 = (max(0.0, min(1.0, w_tip)), phase)

    ou, ov = rng.random(), rng.random()
    uv0 = (ou, ov + 0.12)
    uv1a = (ou + 0.11, ov)
    uv1b = (ou + 0.11, ov + 0.24)
    uv2a = (ou + 0.26, ov + 0.02)
    uv2b = (ou + 0.26, ov + 0.22)
    uv3 = (ou + 0.38, ov + 0.12)

    mb.f([v0, v1a, v1b], 'foliage', [c_base, c_mid, c_mid], [uv0, uv1a, uv1b], smooth=True, uv2=[u2_0, u2_1, u2_1])
    mb.f([v1a, v2a, v2b, v1b], 'foliage', [c_mid, c_m2, c_m2, c_mid], [uv1a, uv2a, uv2b, uv1b], smooth=True, uv2=[u2_1, u2_2, u2_2, u2_1])
    mb.f([v2a, v3, v2b], 'foliage', [c_m2, c_tip, c_m2], [uv2a, uv3, uv2b], smooth=True, uv2=[u2_2, u2_3, u2_2])


def _add_sculpted_canopy_cluster(mb, center, radii, rng, phase, base_w=0.18, tip_w=0.94, tint=0.5, leaf_count=26):
    """Layered tropical leaf-sprig canopy cluster: deep shaded subdiv=2 heart shrouded by dense shingled rounded broad leaves."""
    cx, cy, cz = center
    rx, ry, rz = radii
    c_vec = Vector(center)
    avg_r = (rx + rz) * 0.5
    mb.newoff()

    # 1. Inner shaded foliage heart (smooth subdiv=2 deep interior shadow core — completely veiled by outer leaf shingles!)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
    ph = [rng.uniform(0.0, 6.28) for _ in range(4)]
    heart_scale = 0.68
    v_ids = []
    v_pos = []
    for v in bm.verts:
        p = v.co.copy()
        wob = 1.0 + 0.15 * sin(p.x * 3.2 + ph[0]) * cos(p.z * 2.9 + ph[1]) + 0.10 * sin(p.y * 4.1 + ph[2])
        py = p.y * (0.48 if p.y < 0.0 else 0.98)
        wp = Vector((cx + p.x * rx * heart_scale * wob, cy + py * ry * heart_scale * wob, cz + p.z * rz * heart_scale * wob))
        v.co = wp
        v_ids.append(mb.v(wp))
        v_pos.append(wp)

    bm.faces.ensure_lookup_table()
    o = mb.off
    deep_shadow = mix(C_LEAF_DEEP, C_TEAL, 0.16)
    for f in bm.faces:
        idxs = [v.index for v in f.verts]
        pts = [v_pos[vi] for vi in idxs]
        fn = newell(pts)
        if fn.length < 1e-8:
            continue
        fn.normalize()
        fc = sum(pts, Vector()) / len(pts)
        if fn.dot(fc - c_vec) < 0.0:
            idxs.reverse()
            pts.reverse()
            fn = -fn
        ref = Vector((1.0, 0.0, 0.0)) if abs(fn.x) < 0.8 else Vector((0.0, 1.0, 0.0))
        gu = (ref - fn * ref.dot(fn)).normalized()
        gv = fn.cross(gu)
        uvs = [(p.dot(gu) * SU + o[0], p.dot(gv) * SV + o[1]) for p in pts]

        cols = []
        uv2s = []
        for p in pts:
            ny = max(-1.0, min(1.0, (p.y - cy) / max(0.2, ry * heart_scale)))
            if ny < 0.0:
                cc = mul(deep_shadow, 0.62 + 0.16 * max(0.0, 1.0 + ny))
            else:
                h_k = smooth01(ny * 0.78 + (tint - 0.5) * 0.22)
                cc = mul(mix(C_LEAF_DEEP, C_LEAF_MID, 0.15 + 0.45 * h_k), 0.84)
            cols.append(jit(cc, rng, 0.04, 0.02))
            r_out = sqrt((p.x - cx) ** 2 + (p.z - cz) ** 2) / max(0.1, max(rx, rz))
            w = base_w + (tip_w - base_w) * min(0.54, r_out * 0.48 + max(0.0, ny) * 0.16)
            uv2s.append((max(0.0, min(1.0, w)), phase))
        mb.f([v_ids[vi] for vi in idxs], 'foliage', cols, uvs, smooth=True, uv2=uv2s)
    bm.free()

    # 2. Dense 4-band shingled rounded-ovate tropical leaf cloud shrouding 100% of the outer dome & underside rim!
    golden = 2.39996323
    az_off = rng.uniform(0.0, 2.0 * pi)
    n_eave = max(5, int(round(leaf_count * 0.24)))
    n_rim = max(7, int(round(leaf_count * 0.32)))
    n_mid = max(6, int(round(leaf_count * 0.26)))
    n_cap = max(4, leaf_count - n_eave - n_rim - n_mid)

    def spawn_band(n_items, band_idx, el_min, el_max, pitch_min, pitch_max, len_mul, wid_ratio, droop_rng, sun_bias):
        for li in range(n_items):
            frac = (li + 0.5) / float(max(1, n_items))
            az = az_off + (li + band_idx * 4.3) * golden + rng.uniform(-0.24, 0.24)
            ca, sa = cos(az), sin(az)
            el = el_min + (el_max - el_min) * frac + rng.uniform(-0.07, 0.07)
            # Root snugly inside outer edge of inner heart shell so leaves drape outward smoothly over the core
            r_h = cos(el) * rng.uniform(0.52, 0.68)
            y_h = sin(el) * (0.42 if el < 0.0 else 0.72)
            root = Vector((cx + ca * rx * r_h, cy + ry * y_h, cz + sa * rz * r_h))

            # Shingled tangential sweep (gently arching outward & drooping — never vertical porcupine spikes!)
            p_ang = radians(rng.uniform(pitch_min, pitch_max))
            # Slight tangential yaw fan so adjacent broad leaves overlap like real banyan bough sprays
            yaw_fan = rng.uniform(-0.26, 0.26)
            laz = az + yaw_fan
            dir_out = Vector((cos(laz) * cos(p_ang), sin(p_ang), sin(laz) * cos(p_ang))).normalized()

            l_len = avg_r * len_mul * rng.uniform(0.86, 1.15)
            l_wid = l_len * wid_ratio * rng.uniform(0.90, 1.12)
            droop = rng.uniform(droop_rng[0], droop_rng[1])

            sun_k = max(0.0, min(1.0, sun_bias + (tint - 0.5) * 0.38 + rng.uniform(-0.10, 0.12)))
            if band_idx == 0:
                # Shaded teal-emerald underside eaves
                c_b = mul(deep_shadow, 0.72)
                c_m = jit(mix(deep_shadow, C_LEAF_DEEP, 0.55 + 0.35 * sun_k), rng, 0.07, 0.03)
                c_t = mix(c_m, C_LEAF_MID, 0.38 + 0.35 * sun_k)
            elif band_idx == 1:
                # Lush mid-emerald equatorial umbrella rim
                c_b = mix(deep_shadow, C_LEAF_DEEP, 0.65)
                c_m = jit(mix(C_LEAF_DEEP, C_LEAF_MID, 0.55 + 0.38 * sun_k), rng, 0.07, 0.035)
                c_t = mix(c_m, C_LEAF_SUN, 0.20 + 0.35 * sun_k)
            else:
                # Sunlit layered dome crown catching golden-lime highlights!
                c_b = mix(C_LEAF_DEEP, C_LEAF_MID, 0.42 + 0.35 * sun_k)
                c_m = jit(mix(C_LEAF_MID, C_LEAF_SUN, 0.20 + 0.42 * sun_k), rng, 0.07, 0.035)
                c_t = mix(c_m, C_LEAF_SUN, 0.46 + 0.42 * sun_k)

            l_ph = (phase + 0.04 * sin(li * 2.1 + band_idx)) % 1.0
            w_b = min(0.84, base_w + (tip_w - base_w) * (0.24 + 0.16 * band_idx))
            w_t = min(0.98, max(0.56, tip_w - rng.uniform(0.0, 0.08)))
            _add_broad_leaf_blade(mb, root, dir_out, Vector((0.0, 1.0, 0.0)), l_len, l_wid, droop, c_b, c_m, c_t, w_b, w_t, l_ph, rng, rounded=True)

    # Band 0: Under-rim drooping eaves veiling the cluster underside & bough joins
    spawn_band(n_eave, 0, -0.36, -0.02, -24.0, -4.0, 0.46, 0.68, (0.34, 0.48), 0.12)
    # Band 1: Outer equatorial umbrella rim breaking up the entire horizontal silhouette
    spawn_band(n_rim,  1,  0.00,  0.34,  -6.0, 14.0, 0.48, 0.66, (0.26, 0.38), 0.38)
    # Band 2: Upper-mid shingled shoulder hugging the dome contour smoothly
    spawn_band(n_mid,  2,  0.36,  0.76,   8.0, 26.0, 0.44, 0.68, (0.22, 0.34), 0.70)
    # Band 3: Sunlit billowing crown cap fanning gently across the apex (zero vertical horns!)
    spawn_band(n_cap,  3,  0.76,  1.24,   2.0, 18.0, 0.40, 0.72, (0.20, 0.30), 0.94)


def _add_leafy_jungle_vine(mb, anchor, length, out_dir, rng, phase, n_leaves=12):
    """Lush hanging jungle vine: sinuous swaying stem adorned with alternating sculpted pointed jungle leaves."""
    mb.newoff()
    od = Vector(out_dir)
    od.y = 0.0
    od = od.normalized() if od.length > 1e-5 else Vector((1.0, 0.0, 0.0))
    side = Vector((-od.z, 0.0, od.x)).normalized()
    segs = 8

    def v_pos(t):
        sway_s = sin(t * pi * 1.85 + phase * 6.28) * 0.14
        sway_o = 0.06 * sin(t * pi * 1.15)
        return Vector(anchor) + od * sway_o + side * sway_s + Vector((0.0, -length * t, 0.0))

    # 1. Slender sinuous hanging vine stem anchored cleanly inside bough/canopy (t=0 -> UV2.x = 0.04)
    v_l = []
    v_r = []
    v_c = []
    v_u2 = []
    for i in range(segs + 1):
        t = i / float(segs)
        c = v_pos(t)
        sw = 0.024 * (1.0 - 0.55 * t)
        v_l.append(mb.v(c - side * sw))
        v_r.append(mb.v(c + side * sw))
        v_c.append(mix(C_LEAF_DEEP, C_LEAF_MID, 0.25 + 0.45 * t))
        v_u2.append((min(0.95, 0.04 + 0.90 * pow(t, 1.20)), phase))
    for i in range(segs):
        t0, t1 = i / float(segs), (i + 1) / float(segs)
        mb.f(
            [v_l[i], v_r[i], v_r[i + 1], v_l[i + 1]],
            'foliage', [v_c[i], v_c[i], v_c[i + 1], v_c[i + 1]],
            [(0.45, t0 * 2.0), (0.55, t0 * 2.0), (0.55, t1 * 2.0), (0.45, t1 * 2.0)],
            smooth=True, uv2=[v_u2[i], v_u2[i], v_u2[i + 1], v_u2[i + 1]]
        )

    # 2. Alternating pairs of sculpted pointed jungle leaves sprouting outward along the vine
    for li in range(n_leaves):
        frac = (li + 0.5) / float(n_leaves)
        t = 0.10 + 0.86 * frac
        sgn = 1.0 if li % 2 == 0 else -1.0
        root = v_pos(t)
        out_ang = radians(rng.uniform(-22.0, 26.0))
        d_leaf = (side * (sgn * 0.72) + od * (0.55 + 0.25 * cos(out_ang)) + Vector((0.0, -0.35 + 0.18 * sin(li), 0.0))).normalized()
        l_len = rng.uniform(0.28, 0.44) * (1.05 - 0.35 * frac)
        l_wid = l_len * rng.uniform(0.56, 0.70)
        w_b = min(0.92, 0.06 + 0.84 * pow(t, 1.20))
        w_t = min(0.98, w_b + 0.10)
        c_b = C_LEAF_DEEP
        c_m = jit(mix(C_LEAF_DEEP, C_LEAF_MID, 0.48 + 0.34 * frac), rng, 0.07, 0.03)
        c_t = mix(c_m, C_LEAF_SUN, 0.26 + 0.44 * frac)
        _add_broad_leaf_blade(mb, root, d_leaf, Vector((0.0, 1.0, 0.0)), l_len, l_wid, 0.28, c_b, c_m, c_t, w_b, w_t, phase, rng, rounded=False)


def gen_jungle_banyan(outdir):
    clear_scene()
    set_foliage_style('broad')
    rng = random.Random(SEED + 431)
    mb_wood = MB('BanyanWood', seed=431)
    mb_leaf = MB('BanyanCanopy', seed=531)

    # 1. Twisted 12-sided deeply fluted dark-bark main trunk (y = -0.95..+4.75 m, smooth-shaded organic bark!)
    trunk_pts = [
        ( 0.00, -0.95,  0.00, 1.04),
        ( 0.03, -0.15, -0.02, 0.90),
        ( 0.07,  0.70, -0.05, 0.76),
        ( 0.11,  1.55, -0.06, 0.67),
        ( 0.08,  2.40,  0.00, 0.60),
        ( 0.01,  3.20,  0.06, 0.60),
        (-0.04,  4.00,  0.07, 0.65),
        (-0.02,  4.75,  0.04, 0.72),
    ]
    sides = 12
    secs = []
    scols = []
    col_pts = []
    for i, (tx, ty, tz, tr) in enumerate(trunk_pts):
        t = i / float(len(trunk_pts) - 1)
        ring = []
        for k in range(sides):
            ang = 2.0 * pi * k / sides + t * 0.62
            # Deep 6-lobe organic root fluting aligning with the 6 splayed buttress roots
            flute = 1.0 + 0.22 * sin(ang * 6.0 + 0.4) * (1.0 - 0.55 * t) + 0.06 * cos(ang * 3.0 - t * 2.5)
            v = Vector((tx + cos(ang) * tr * flute, ty, tz + sin(ang) * tr * flute))
            ring.append(v)
            col_pts.append(v)
        secs.append(ring)
        scols.append(jit(mix(C_TRUNK_DARK, C_DARK, 0.30 + 0.35 * t), rng, 0.06, 0.02))
    loft(mb_wood, secs, 'bark_banyan', C_TRUNK_DARK, closed=True, caps=(True, True), mode='smooth', scols=scols)

    # 2. Six dramatic splayed curling buttress roots seamlessly emerging from trunk core & plunging to y = -0.95 m!
    for ri in range(6):
        ang = ri * (2.0 * pi / 6.0) + rng.uniform(-0.14, 0.14)
        ca, sa = cos(ang), sin(ang)
        sx, sz = -sa, ca
        curl = rng.uniform(-0.30, 0.30)
        reach = rng.uniform(2.05, 2.65)
        r_path = [
            Vector((ca * 0.14, 2.75 + rng.uniform(-0.18, 0.22), sa * 0.14)),
            Vector((ca * (reach * 0.34) + sx * curl * 0.35, 1.55, sa * (reach * 0.34) + sz * curl * 0.35)),
            Vector((ca * (reach * 0.66) + sx * curl * 0.75, 0.62, sa * (reach * 0.66) + sz * curl * 0.75)),
            Vector((ca * (reach * 0.89) + sx * curl, -0.15, sa * (reach * 0.89) + sz * curl)),
            Vector((ca * reach + sx * curl * 0.85, -0.95, sa * reach + sz * curl * 0.85)),
        ]
        tube(mb_wood, r_path, [0.34, 0.31, 0.26, 0.21, 0.15], 7, 'bark_banyan', jit(C_TRUNK_DARK, rng, 0.07), caps=(False, True), mode='smooth')
        for p in r_path[:3]:
            col_pts.append(p)

    # 3. Five heavy gnarled spreading primary boughs (8-sided smooth) splitting into secondary & tertiary limbs!
    bough_specs = [
        (0.18, 3.65, 6.75, 0.42, 0.17),
        (1.42, 3.40, 7.20, 0.40, 0.16),
        (2.68, 3.55, 6.55, 0.41, 0.17),
        (3.94, 3.35, 7.30, 0.39, 0.16),
        (5.20, 3.45, 6.95, 0.40, 0.17),
    ]
    primary_tips = []
    secondary_tips = []
    aerial_anchors = []
    vine_anchors = []
    for bi, (az, reach, top_y, r0, r1) in enumerate(bough_specs):
        ca, sa = cos(az), sin(az)
        sx, sz = -sa, ca
        sw = rng.uniform(-0.36, 0.36)
        b_path = [
            Vector((ca * 0.16, 4.10 + 0.14 * (bi % 2), sa * 0.16)),
            Vector((ca * (reach * 0.30) + sx * sw * 0.4, 4.95, sa * (reach * 0.30) + sz * sw * 0.4)),
            Vector((ca * (reach * 0.62) + sx * sw * 0.9, 5.85 + 0.15 * (bi % 2), sa * (reach * 0.62) + sz * sw * 0.9)),
            Vector((ca * (reach * 0.86) + sx * sw * 0.6, top_y - 0.36, sa * (reach * 0.86) + sz * sw * 0.6)),
            Vector((ca * reach, top_y, sa * reach)),
        ]
        tube(mb_wood, b_path, [r0, r0 * 0.84, r0 * 0.68, r0 * 0.50, r1], 8, 'bark_banyan', jit(C_DARK, rng, 0.07), mode='smooth')
        primary_tips.append(b_path[-1])
        aerial_anchors.append((b_path[1].lerp(b_path[2], 0.65), True))
        if bi < 4:
            aerial_anchors.append((b_path[2].lerp(b_path[3], 0.55), False))
        # Anchor a leafy hanging vine right inside the outer bough canopy underside!
        vine_anchors.append((b_path[3].lerp(b_path[4], 0.55) + Vector((0.0, 0.15, 0.0)), Vector((ca, 0.0, sa))))

        # Two forked secondary limbs per primary bough
        for sgn in (-1.0, 1.0):
            fork_az = az + sgn * 0.54 + rng.uniform(-0.07, 0.07)
            fca, fsa = cos(fork_az), sin(fork_az)
            f_start = b_path[2]
            f_mid = f_start + Vector((fca * 0.72, 0.45 + rng.uniform(-0.08, 0.14), fsa * 0.72))
            f_end = f_start + Vector((fca * 1.44, 0.96 + rng.uniform(-0.14, 0.22), fsa * 1.44))
            tube(mb_wood, [f_start, f_mid, f_end], [r0 * 0.44, r0 * 0.30, r1 * 0.60], 6, 'bark_banyan', jit(C_TRUNK_LIGHT, rng, 0.07), mode='smooth')
            secondary_tips.append(f_end)
            if sgn > 0 and bi < 3:
                vine_anchors.append((f_mid.lerp(f_end, 0.65) + Vector((0.0, 0.12, 0.0)), Vector((fca, 0.0, fsa))))

        # Tertiary upward canopy spur rising off bough elbow
        t_start = b_path[3]
        t_end = t_start + Vector((ca * 0.50 + sx * 0.22, 1.02 + rng.uniform(-0.1, 0.18), sa * 0.50 + sz * 0.22))
        tube(mb_wood, [t_start, t_end], [r1 * 0.75, r1 * 0.42], 5, 'bark_banyan', jit(C_TRUNK_DARK, rng, 0.06), mode='smooth')

    # Nine hanging banyan aerial root tendrils (5 rooted cleanly into ground y=-0.85, 4 swaying mid-air!)
    for ai, (a_anc, rooted) in enumerate(aerial_anchors[:9]):
        a_end_y = -0.85 if rooted else rng.uniform(1.15, 2.65)
        wob_x = rng.uniform(-0.14, 0.14)
        wob_z = rng.uniform(-0.14, 0.14)
        a_p1 = Vector((a_anc.x * 1.03 + wob_x * 0.5, a_anc.y * 0.68 + a_end_y * 0.32, a_anc.z * 1.03 + wob_z * 0.5))
        a_p2 = Vector((a_anc.x * 1.06 + wob_x, a_anc.y * 0.34 + a_end_y * 0.66, a_anc.z * 1.06 + wob_z))
        a_bot = Vector((a_anc.x * 1.04 + wob_x * 0.6, a_end_y, a_anc.z * 1.04 + wob_z * 0.6))
        r_top = 0.072 if rooted else 0.054
        r_bot = 0.048 if rooted else 0.026
        tube(mb_wood, [a_anc, a_p1, a_p2, a_bot], [r_top, r_top * 0.85, r_top * 0.74, r_bot], 5, 'bark_banyan', jit(C_WEATH, rng, 0.08), mode='smooth')

    # Towering central crown trunk limb splitting into twin sunlit crown forks (~10.5 m apex!)
    crown_limb = [Vector((-0.02, 4.50, 0.04)), Vector((0.16, 6.20, -0.10)), Vector((0.08, 7.95, -0.05))]
    tube(mb_wood, crown_limb, [0.44, 0.30, 0.18], 7, 'bark_banyan', C_TRUNK_DARK, mode='smooth')
    tube(mb_wood, [crown_limb[1], Vector((-0.95, 7.65, 0.72))], [0.24, 0.13], 6, 'bark_banyan', C_TRUNK_DARK, mode='smooth')
    tube(mb_wood, [crown_limb[1], Vector((0.95, 7.58, -0.78))], [0.24, 0.13], 6, 'bark_banyan', C_TRUNK_DARK, mode='smooth')

    # 4. Lush sculpted shingled multi-leaf canopy clusters ('foliage' -> wind shader, ZERO subdiv=1 icospheres!)
    # Seated directly around each bough tip (+0.26..+0.30 y) so zero bare wooden branch tips poke underneath!
    for tip in primary_tips:
        _add_sculpted_canopy_cluster(
            mb_leaf,
            (tip.x, tip.y + 0.28, tip.z),
            (rng.uniform(2.10, 2.52), rng.uniform(1.28, 1.56), rng.uniform(2.04, 2.46)),
            rng, phase=rng.random(), base_w=0.18, tip_w=0.90, tint=0.48, leaf_count=30
        )
    for tip in secondary_tips:
        _add_sculpted_canopy_cluster(
            mb_leaf,
            (tip.x, tip.y + 0.26, tip.z),
            (rng.uniform(1.62, 1.98), rng.uniform(1.06, 1.32), rng.uniform(1.56, 1.92)),
            rng, phase=rng.random(), base_w=0.20, tip_w=0.92, tint=0.64, leaf_count=24
        )
    # Upper crowning sunlit umbrella clusters pushing tree silhouette cleanly to ~10.6 m!
    _add_sculpted_canopy_cluster(mb_leaf, ( 0.06, 8.75, -0.05), (2.80, 1.62, 2.72), rng, phase=rng.random(), base_w=0.24, tip_w=0.96, tint=0.94, leaf_count=36)
    _add_sculpted_canopy_cluster(mb_leaf, (-1.15, 8.15,  0.84), (2.02, 1.26, 1.92), rng, phase=rng.random(), base_w=0.22, tip_w=0.92, tint=0.80, leaf_count=30)
    _add_sculpted_canopy_cluster(mb_leaf, ( 1.10, 8.08, -0.88), (1.98, 1.24, 1.88), rng, phase=rng.random(), base_w=0.22, tip_w=0.92, tint=0.84, leaf_count=30)

    # 5. Eight lush leaf-bearing hanging jungle vines anchored directly inside real outer boughs & canopy!
    for v_anc, v_dir in vine_anchors[:8]:
        _add_leafy_jungle_vine(mb_leaf, v_anc, rng.uniform(2.05, 3.15), v_dir, rng, phase=rng.random(), n_leaves=12)

    build(mb_wood)
    build(mb_leaf)
    col_piece('col_banyan_trunk', col_pts)
    export_glb(outdir, 'jungle_banyan.glb')

def gen_ruin_arch(outdir):
    clear_scene()
    set_foliage_style('broad')
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
    set_foliage_style('broad')
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
        scols=[mix(C_STONE_WARM, C_SEA_MOSS, 0.18), C_STONE_WARM, C_STONE_PALE], swap_uv=True)

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
        scols=[C_STONE_WARM, C_STONE_PALE, jit(C_STONE_PALE, rng, 0.04)], swap_uv=True)

    # Jagged chipped limestone fracture shards crowning the diagonal break & 2 fallen stones at foot
    faceted_rock(mb, (-0.18, 5.18, 0.10), (0.34, 0.24, 0.30), 'rock', C_STONE_PALE, C_STONE_WARM, C_STONE_SHADE, rng, subdiv=1, warp=0.18, strata=0.06)
    faceted_rock(mb, (0.86, 0.16, -0.78), (0.34, 0.24, 0.28), 'rock', C_STONE_OCHRE, C_STONE_MID, C_STONE_DARK, rng, subdiv=1, warp=0.22, strata=0.08, rot_deg=(12, 35, -8))
    faceted_rock(mb, (-0.95, 0.12, 0.62), (0.28, 0.19, 0.25), 'rock', C_MOSS, C_STONE_MID, C_STONE_DARK, rng, subdiv=1, warp=0.20, strata=0.06, rot_deg=(-8, -42, 10))

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

    # 1. Stepped dressed sunlit coral-limestone foundation plinth (plunges to y = -1.85 m!) + corner quoins + loading apron!
    # Broad lower battered footing skirt (y = -1.85..-0.10)
    loft(mb, [
        [(-4.62, -1.85, -3.32), (4.62, -1.85, -3.32), (4.62, -1.85, 3.32), (-4.62, -1.85, 3.32)],
        [(-4.46, -0.10, -3.16), (4.46, -0.10, -3.16), (4.46, -0.10, 3.16), (-4.46, -0.10, 3.16)],
    ], 'stone', C_STONE_OCHRE, closed=True, caps=(True, True), mode='flat',
        scols=[mix(C_STONE_OCHRE, C_STONE_SHADE, 0.38), mix(C_STONE_WARM, C_STONE_OCHRE, 0.40)], swap_uv=True)
    # Stepped upper dressed sandstone foundation plinth (y = -0.10..FLOOR_Y - 0.10)
    loft(mb, [
        [(-4.34, -0.12, -3.04), (4.34, -0.12, -3.04), (4.34, -0.12, 3.04), (-4.34, -0.12, 3.04)],
        [(-4.24, FLOOR_Y - 0.08, -2.94), (4.24, FLOOR_Y - 0.08, -2.94), (4.24, FLOOR_Y - 0.08, 2.94), (-4.24, FLOOR_Y - 0.08, 2.94)],
    ], 'stone', C_STONE_WARM, closed=True, caps=(True, True), mode='flat',
        scols=[C_STONE_WARM, mix(C_STONE_WARM, C_STONE_PALE, 0.28)], swap_uv=True)
    # Beveled pale-limestone water-table coping ledge capping the stone plinth
    bevel_slab(mb, (0.0, FLOOR_Y - 0.02, 0.0), (8.72, 0.16, 6.12), 'stone', C_STONE_PALE, 0.032,
               top_col=C_STONE_PALE, bot_col=mul(C_STONE_WARM, 0.78))
    # Alternating short/long dressed corner stone quoins on all 4 corners
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            cx, cz = sx * 4.24, sz * 2.94
            for yi in range(3):
                long_x = (yi % 2 == 0)
                qw = 0.68 if long_x else 0.46
                qd = 0.46 if long_x else 0.68
                qcol = jit(mix(C_STONE_WARM, C_STONE_PALE, 0.56 if long_x else 0.28), rng, 0.05)
                bevel_slab(mb, (cx, -0.34 + yi * 0.36, cz), (qw, 0.30, qd), 'stone', qcol, 0.026)
    # Warm sunlit limestone cargo-loading porch apron & beveled threshold step (-Z)
    box2(mb, (-4.14, -1.45, -3.98), (4.14, 0.06, -2.90), 'stone', mix(C_STONE_WARM, C_STONE_OCHRE, 0.32), 0.035)
    bevel_slab(mb, (0.0, 0.11, -3.44), (8.36, 0.12, 1.12), 'stone', C_STONE_PALE, 0.024)
    bevel_slab(mb, (0.0, 0.36, -3.35), (2.78, 0.24, 0.66), 'stone', C_STONE_WARM, 0.026)

    # 2. Timber-framed sun-baked stucco upper walls with subtle warm ochre coastal salt-weathering near base!
    MID_W_Y = FLOOR_Y + 0.72
    t_mid = (MID_W_Y - FLOOR_Y) / (EAVE_Y - FLOOR_Y)
    loft(mb, [
        [(-4.15, FLOOR_Y, -2.86), (4.15, FLOOR_Y, -2.86), (4.15, FLOOR_Y, 2.86), (-4.15, FLOOR_Y, 2.86)],
        [(-(4.15 + 0.15 * t_mid), MID_W_Y, -(2.86 + 0.10 * t_mid)), (4.15 + 0.15 * t_mid, MID_W_Y, -(2.86 + 0.10 * t_mid)),
         (4.15 + 0.15 * t_mid, MID_W_Y, 2.86 + 0.10 * t_mid), (-(4.15 + 0.15 * t_mid), MID_W_Y, 2.86 + 0.10 * t_mid)],
        [(-4.30, EAVE_Y, -2.96), (4.30, EAVE_Y, -2.96), (4.30, EAVE_Y, 2.96), (-4.30, EAVE_Y, 2.96)],
    ], 'plaster', C_PLASTER, closed=True, caps=(True, True), mode='flat',
        scols=[mix(C_PLASTER, C_STONE_WARM, 0.24), C_PLASTER, C_PLASTER])
    for sz in (-1.0, 1.0):
        gz = sz * 2.94
        g_pts = [(-4.28, EAVE_Y - 0.04, gz), (4.28, EAVE_Y - 0.04, gz), (0.0, RIDGE_Y - 0.12, gz)]
        mb.fp(g_pts, 'plaster', C_PLASTER_SH, (1, 0, 0), (0.0, EAVE_Y, 0.0))

    # Heavy dark-oak half-timber framing (corner posts, horizontals, diagonal X-braces)
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            tube(mb, [(sx * 4.20, FLOOR_Y, sz * 2.90), (sx * 4.34, EAVE_Y - 0.14, sz * 3.00)], 0.16, 4, 'wood', C_DARK, mode='flat')
    for y_beam in (FLOOR_Y + 0.08, 2.15, EAVE_Y - 0.05):
        t = (y_beam - FLOOR_Y) / (EAVE_Y - FLOOR_Y)
        bx = 4.18 + 0.16 * t
        bz = 2.88 + 0.10 * t
        y_side = 3.40 if y_beam > 3.0 else y_beam
        cbox(mb, (0.0, y_beam, -bz), (bx * 2.0 + 0.24, 0.20, 0.20), 'wood', C_DARK, 0.02)
        cbox(mb, (0.0, y_beam,  bz), (bx * 2.0 + 0.24, 0.20, 0.20), 'wood', C_DARK, 0.02)
        cbox(mb, (-bx, y_side, 0.0), (0.20, 0.20, bz * 2.0 + 0.24), 'wood', C_DARK, 0.02)
        cbox(mb, ( bx, y_side, 0.0), (0.20, 0.20, bz * 2.0 + 0.24), 'wood', C_DARK, 0.02)
    for sx in (-1.65, 1.65):
        cbox(mb, (sx, 2.12, -2.96), (0.20, 3.05, 0.20), 'wood', C_DARK, 0.02)
    for sz in (-1.0, 1.0):
        for sx in (-4.28, 4.28):
            tube(mb, [(sx, FLOOR_Y + 0.15, sz * 2.85), (sx, EAVE_Y - 0.15, sz * 1.10)], 0.08, 4, 'wood', C_DARK, mode='flat')

    # Chamfered oak timber roof-eave corbels tucked cleanly beneath +/-X side eaves & front/rear gable verges!
    for cz in (-2.40, -1.20, 0.0, 1.20, 2.40):
        stepped_corbel(mb, (-4.30, 3.34, cz),  90.0, 0.15, 0.38, 0.36, 'wood', C_DARK)
        stepped_corbel(mb, ( 4.30, 3.34, cz), -90.0, 0.15, 0.38, 0.36, 'wood', C_DARK)
    for sz in (-1.0, 1.0):
        rot_g = 0.0 if sz < 0 else 180.0
        for gx, gy in ((-2.40, EAVE_Y + 0.92), (2.40, EAVE_Y + 0.92)):
            stepped_corbel(mb, (gx, gy, sz * 2.94), rot_g, 0.15, 0.36, 0.48, 'wood', C_DARK)

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
                mb.newoff()
                p_top = [(x0, y0 + th, z0), (x0, y0 + th, z1), (x1, y1 + th, z1), (x1, y1 + th, z0)]
                p_bot = [(x0, y0, z0), (x0, y0, z1), (x1, y1, z1), (x1, y1, z0)]
                mb.fp(p_top, 'shingle', c_sh, (0, 0, 1), (0.0, y0 - 2.0, 0.5 * (z0 + z1)))
                mb.fp(p_bot, 'wood', mul(c_sh, 0.68), (0, 0, 1), (0.0, y0 + 2.0, 0.5 * (z0 + z1)))
                mb.fp([p_bot[3], p_bot[2], p_top[2], p_top[3]], 'shingle', mul(c_sh, 0.78), (0, 0, 1), (0.0, y0, 0.5 * (z0 + z1)))
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

    # Upper cargo loft hatch doors (swung open beneath hoist beam, with battened weathered shutter trim!)
    cbox(mb, (0.0, 4.35, -2.96), (1.42, 1.38, 0.16), 'wood', C_DARK, 0.02)
    cbox(mb, (0.0, 4.35, -2.90), (1.16, 1.14, 0.10), 'wood', C_TAR, 0.01)
    c_shutter = mix(C_TEAL, C_DRIFT, 0.16)
    for sx in (-1.0, 1.0):
        with xf(mb, T(sx * 0.94, 4.35, -3.14) @ R('Y', sx * 28)):
            cbox(mb, (0.0, 0.0, 0.0), (0.58, 1.18, 0.08), 'wood', c_shutter, 0.014)
            for by in (-0.38, 0.38):
                cbox(mb, (0.0, by, -0.045), (0.54, 0.08, 0.028), 'wood', C_DARK, 0.0)
                cbox(mb, (-sx * 0.10, by, -0.062), (0.34, 0.045, 0.02), 'iron', C_IRON, 0.0)

    # 5. Double heavy timber warehouse cargo doors (-Z) with iron strap hinges & brass ring pulls!
    cbox(mb, (0.0, FLOOR_Y + 1.24, -2.96), (2.48, 2.48, 0.22), 'wood', C_DARK, 0.025)
    for sx in (-1.0, 1.0):
        dx = sx * 0.56
        cbox(mb, (dx, FLOOR_Y + 1.18, -3.02), (1.06, 2.28, 0.12), 'wood', jit(C_HULL, rng, 0.06), 0.018)
        cbox(mb, (dx, FLOOR_Y + 1.18, -3.08), (0.92, 0.12, 0.05), 'wood', C_DARK, 0.0, M=R('Z', sx * 42))
        for hy in (FLOOR_Y + 0.56, FLOOR_Y + 1.78):
            cbox(mb, (dx + sx * 0.20, hy, -3.10), (0.58, 0.09, 0.04), 'iron', C_IRON, 0.0)
        with xf(mb, T(sx * 0.16, FLOOR_Y + 1.08, -3.12) @ M_Y2Z):
            torus(mb, 0.072, 0.018, 8, 5, 'brass', C_BRASS, True)

    # 6. Warm glowing mullioned warehouse windows with weathered battened shutter trim & sill brackets!
    def add_wh_window(pos, rot_y, w=1.18, h=1.08):
        with xf(mb, T(pos) @ R('Y', rot_y)):
            cbox(mb, (0, -h * 0.5 - 0.06, -0.06), (w + 0.34, 0.13, 0.25), 'wood', C_DARK, 0.02)
            for bx in (-w * 0.40, w * 0.40):
                cbox(mb, (bx, -h * 0.5 - 0.17, -0.06), (0.11, 0.13, 0.16), 'wood', C_DARK, 0.0)
            cbox(mb, (0, h * 0.5 + 0.05, -0.05), (w + 0.32, 0.14, 0.24), 'wood', C_DARK, 0.02)
            for sx in (-w * 0.5 - 0.06, w * 0.5 + 0.06):
                cbox(mb, (sx, 0, -0.04), (0.12, h + 0.10, 0.18), 'wood', C_DARK, 0.02)
            for sx in (-1, 1):
                sh_x = sx * (w * 0.5 + 0.30)
                cbox(mb, (sh_x, 0, -0.04), (0.34, h, 0.06), 'wood', c_shutter, 0.012)
                for by in (-h * 0.34, 0.0, h * 0.34):
                    cbox(mb, (sh_x, by, -0.072), (0.32, 0.075, 0.028), 'wood', C_DARK, 0.0)
                for hy in (-h * 0.34, h * 0.34):
                    cbox(mb, (sh_x - sx * 0.07, hy, -0.088), (0.21, 0.038, 0.02), 'iron', C_IRON, 0.0)
            cbox(mb, (0, 0, 0.0), (w, h, 0.06), 'window', C_GLASS, 0.0)
            cbox(mb, (0, 0, -0.04), (w, 0.065, 0.05), 'wood', C_DARK, 0.0)
            cbox(mb, (0, 0, -0.04), (0.065, h, 0.05), 'wood', C_DARK, 0.0)

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
            cbox(mb, (0, 0, -csz * 0.48), (csz * 0.92, 0.08, 0.04), 'wood', C_HULL, 0.0, M=R('Z', 38))
            cbox(mb, (0, csz * 0.49, 0), (csz * 0.72, 0.025, 0.12), 'paint', C_TEAL, 0.0)

    # 8. Porch hoist bracket lantern + Lantern_Warehouse empty anchor!
    lantern_pos = (-1.65, 2.95, -3.48)
    cbox(mb, (-1.65, 3.24, -3.22), (0.08, 0.08, 0.62), 'iron', C_IRON, 0.0)
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
    set_foliage_style('broad')
    rng = random.Random(SEED + 587)
    mb = MB('SeawallBastion', seed=587)

    # Hand-crafted weathered Caribbean sandstone fort bastion segment (~1,600-2,300 sculpted tris):
    # Preserves exact footprint (X = -4.5..+4.5, Z = -2.18..+1.80, DECK_Y = 3.00, parapet y = 4.22, plunging to y = -2.40)!
    DECK_Y = 3.00
    c_warm_hi = mix(C_STONE_WARM, C_STONE_PALE, 0.42)
    c_pale_warm = mix(C_STONE_WARM, C_STONE_PALE, 0.72)
    c_ochre_cap = mix(C_STONE_WARM, C_STONE_PALE, 0.56)
    c_overhang_sh = mul(C_STONE_OCHRE, 0.68)
    c_tide_dark = mix(C_STONE_DARK, C_SEA_MOSS, 0.34)
    c_tide_mid = mix(C_STONE_OCHRE, C_STONE_DARK, 0.48)

    # 1. Deep battered footing + recessed darker tide-worn plinth course (plunges cleanly to y = -2.40 m!)
    loft(mb, [
        [(-4.60, -2.40, -2.26), (4.60, -2.40, -2.26), (4.60, -2.40, 1.88), (-4.60, -2.40, 1.88)],
        [(-4.52, -0.68, -2.12), (4.52, -0.68, -2.12), (4.52, -0.68, 1.84), (-4.52, -0.68, 1.84)],
    ], 'stone', c_tide_dark, closed=True, caps=(True, False), mode='flat', scols=[c_tide_dark], swap_uv=True)
    # Recessed darker tide-worn plinth course (inset 0.10 m under the overhanging water-table belt!)
    loft(mb, [
        [(-4.42, -0.68, -1.98), (4.42, -0.68, -1.98), (4.42, -0.68, 1.74), (-4.42, -0.68, 1.74)],
        [(-4.38,  0.42, -1.92), (4.38,  0.42, -1.92), (4.38,  0.42, 1.72), (-4.38,  0.42, 1.72)],
    ], 'stone', c_tide_mid, closed=True, caps=(False, False), mode='flat', scols=[c_tide_mid], swap_uv=True)
    # Crisp protruding beveled water-table belt course separating dark tidal plinth from sunlit fort masonry
    bevel_slab(mb, (0.0, 0.53, -0.10), (9.08, 0.24, 3.88), 'stone', C_STONE_PALE, 0.04,
               top_col=C_STONE_PALE, bot_col=c_overhang_sh)

    # 2. Battered warm sunlit limestone/sandstone main curtain wall (y = 0.64..2.76, tapering inward toward top!)
    loft(mb, [
        [(-4.46, 0.64, -2.02), (4.46, 0.64, -2.02), (4.46, 0.64, 1.78), (-4.46, 0.64, 1.78)],
        [(-4.40, 1.38, -1.91), (4.40, 1.38, -1.91), (4.40, 1.38, 1.75), (-4.40, 1.38, 1.75)],
        [(-4.34, 2.08, -1.80), (4.34, 2.08, -1.80), (4.34, 2.08, 1.72), (-4.34, 2.08, 1.72)],
        [(-4.28, 2.76, -1.69), (4.28, 2.76, -1.69), (4.28, 2.76, 1.70), (-4.28, 2.76, 1.70)],
    ], 'stone', C_STONE_WARM, closed=True, caps=(False, True), mode='flat',
        scols=[C_STONE_WARM, c_warm_hi, c_pale_warm, c_warm_hi], swap_uv=True)

    # Two-tier projecting beveled stone cordon / stringcourse molding crowning the seaward & side walls (y = 2.72..3.02)
    bevel_slab(mb, (0.0, 2.79, -0.02), (8.82, 0.14, 3.60), 'stone', c_overhang_sh, 0.024,
               top_col=C_STONE_WARM, bot_col=mul(C_STONE_OCHRE, 0.60))
    bevel_slab(mb, (0.0, 2.94, -0.04), (9.08, 0.18, 3.80), 'stone', C_STONE_PALE, 0.036,
               top_col=C_STONE_PALE, bot_col=mul(C_STONE_WARM, 0.78))

    # Hand-chiseled protruding dressed ashlar relief stones along seaward (-Z) & landward (+Z) battered faces
    sea_relief = [
        (-2.35, 2.18, 1.24, 0.46),
        ( 0.05, 1.36, 1.38, 0.46),
        ( 2.35, 2.08, 1.20, 0.44),
    ]
    for rx, ry, rw, rh in sea_relief:
        t_bat = (ry - 0.64) / (2.76 - 0.64)
        rz = -2.02 + 0.33 * t_bat - 0.04
        bevel_slab(mb, (rx, ry, rz), (rw, rh, 0.14), 'stone', jit(c_pale_warm, rng, 0.05), 0.026, M=R('X', 8.8))
    for rx, ry, rw, rh in ((-1.95, 1.92, 1.24, 0.44), (1.85, 1.45, 1.28, 0.44)):
        cbox(mb, (rx, ry, 1.76), (rw, rh, 0.12), 'stone', jit(c_warm_hi, rng, 0.05), 0.0, skip=('-z',))

    # 3. Heavy battered corner bastion piers + staggered alternating short/long dressed corner quoins up EVERY corner!
    for sx in (-1.0, 1.0):
        bx = sx * 4.02
        # Seaward battered corner bastion pier (plunges cleanly to y = -2.40 m!)
        loft(mb, [
            [(bx - 0.68, -2.40, -2.42), (bx + 0.68, -2.40, -2.42), (bx + 0.68, -2.40, -0.78), (bx - 0.68, -2.40, -0.78)],
            [(bx - 0.60,  0.42, -2.16), (bx + 0.60,  0.42, -2.16), (bx + 0.60,  0.42, -0.80), (bx - 0.60,  0.42, -0.80)],
            [(bx - 0.56,  1.65, -2.04), (bx + 0.56,  1.65, -2.04), (bx + 0.56,  1.65, -0.82), (bx - 0.56,  1.65, -0.82)],
            [(bx - 0.52,  2.98, -1.92), (bx + 0.52,  2.98, -1.92), (bx + 0.52,  2.98, -0.84), (bx - 0.52,  2.98, -0.84)],
        ], 'stone', C_STONE_WARM, closed=True, caps=(True, True), mode='flat',
            scols=[c_tide_dark, C_STONE_WARM, c_warm_hi, c_pale_warm], swap_uv=True)
        # Beveled cornice cap collar around seaward corner pier (y = 2.94..3.16)
        bevel_slab(mb, (bx, 3.06, -1.40), (1.22, 0.22, 1.24), 'stone', C_STONE_PALE, 0.036,
                   top_col=C_STONE_PALE, bot_col=c_overhang_sh)

        # Alternating short/long protruding dressed corner quoins climbing BOTH seaward corners (4 bold courses!)
        for qi in range(4):
            qy = 0.90 + qi * 0.52
            t_q = (qy - 0.42) / (2.98 - 0.42)
            qx_edge = bx + sx * (0.60 - 0.08 * t_q)
            qz_edge = -2.16 + 0.24 * t_q
            long_x = (qi % 2 == 0)
            qw = 0.72 if long_x else 0.42
            qd = 0.42 if long_x else 0.72
            qx_c = qx_edge - sx * (qw * 0.5 - 0.07)
            qz_c = qz_edge + (qd * 0.5 - 0.07)
            qcol = jit(C_STONE_PALE if long_x else c_warm_hi, rng, 0.04)
            bevel_slab(mb, (qx_c, qy, qz_c), (qw, 0.42, qd), 'stone', qcol, 0.03)

        # Alternating short/long protruding dressed corner quoins climbing BOTH rear landward corners (+Z, 4 courses!)
        for qi in range(4):
            qy = 0.92 + qi * 0.50
            long_x = (qi % 2 == 1)
            qw = 0.68 if long_x else 0.40
            qd = 0.40 if long_x else 0.68
            qx_c = sx * (4.42 - qw * 0.5 + 0.07)
            qz_c = 1.76 - qd * 0.5 + 0.07
            qcol = jit(c_pale_warm if long_x else C_STONE_WARM, rng, 0.04)
            cbox(mb, (qx_c, qy, qz_c), (qw, 0.40, qd), 'stone', qcol, 0.0)

    # 4. Sculpted crenellated parapet: 4 merlons crowned with stepped beveled ochre coping slabs + splayed cannon embrasure!
    def _add_stepped_merlon(cx, cz, mw, mh, md, y_base):
        # Slightly battered merlon body
        hw0, hd0 = mw * 0.5, md * 0.5
        hw1, hd1 = hw0 * 0.95, hd0 * 0.94
        y_top = y_base + mh
        loft(mb, [
            [(cx - hw0, y_base, cz - hd0), (cx + hw0, y_base, cz - hd0), (cx + hw0, y_base, cz + hd0), (cx - hw0, y_base, cz + hd0)],
            [(cx - hw1, y_top,  cz - hd1), (cx + hw1, y_top,  cz - hd1), (cx + hw1, y_top,  cz + hd1), (cx - hw1, y_top,  cz + hd1)],
        ], 'stone', jit(C_STONE_WARM, rng, 0.04), closed=True, caps=(False, True), mode='flat',
            scols=[jit(c_warm_hi, rng, 0.04)], swap_uv=True)
        # Unified 2-tier stepped beveled parapet coping slab (shadowed overhang lip + stepped sunlit ochre bevel crown!)
        oh_w, oh_d = hw1 + 0.09, hd1 + 0.09
        st_w, st_d = hw1 + 0.04, hd1 + 0.04
        cr_w, cr_d = hw1 - 0.06, hd1 - 0.06
        loft(mb, [
            [(cx - hw1,  y_top - 0.02, cz - hd1),  (cx + hw1,  y_top - 0.02, cz - hd1),  (cx + hw1,  y_top - 0.02, cz + hd1),  (cx - hw1,  y_top - 0.02, cz + hd1)],
            [(cx - oh_w, y_top + 0.03, cz - oh_d), (cx + oh_w, y_top + 0.03, cz - oh_d), (cx + oh_w, y_top + 0.03, cz + oh_d), (cx - oh_w, y_top + 0.03, cz + oh_d)],
            [(cx - oh_w, y_top + 0.11, cz - oh_d), (cx + oh_w, y_top + 0.11, cz - oh_d), (cx + oh_w, y_top + 0.11, cz + oh_d), (cx - oh_w, y_top + 0.11, cz + oh_d)],
            [(cx - st_w, y_top + 0.14, cz - st_d), (cx + st_w, y_top + 0.14, cz - st_d), (cx + st_w, y_top + 0.14, cz + st_d), (cx - st_w, y_top + 0.14, cz + st_d)],
            [(cx - cr_w, y_top + 0.23, cz - cr_d), (cx + cr_w, y_top + 0.23, cz - cr_d), (cx + cr_w, y_top + 0.23, cz + cr_d), (cx - cr_w, y_top + 0.23, cz + cr_d)],
        ], 'stone', c_ochre_cap, closed=True, caps=(True, True), mode='flat',
            scols=[c_overhang_sh, C_STONE_WARM, c_ochre_cap, C_STONE_PALE, C_STONE_PALE], swap_uv=True)

    # Corner bastion merlons (x = +/-3.96, crowning to y = 4.24 m) + flanking central merlons (x = +/-2.14, crowning to y = 4.21 m)
    for sx in (-1.0, 1.0):
        _add_stepped_merlon(sx * 3.96, -1.36, 1.12, 0.86, 1.04, 3.15)
        _add_stepped_merlon(sx * 2.14, -1.32, 1.46, 0.96, 0.90, 3.02)
        # Beveled narrow musket-loophole sill between corner pier & inner merlon
        bevel_slab(mb, (sx * 3.12, 3.24, -1.32), (0.64, 0.42, 0.84), 'stone', c_warm_hi, 0.03)

    # Central splayed beveled stone cannon embrasure (x = -1.42..+1.42): seaward-sloping glacis sill + flush trapezoidal cheek walls!
    loft(mb, [
        [(-1.44, 3.00, -1.76), (1.44, 3.00, -1.76), (1.44, 3.00, -0.88), (-1.44, 3.00, -0.88)],
        [(-1.44, 3.24, -1.76), (1.44, 3.24, -1.76), (1.44, 3.44, -0.88), (-1.44, 3.44, -0.88)],
    ], 'stone', C_STONE_PALE, closed=True, caps=(False, True), mode='flat', scols=[c_warm_hi, C_STONE_PALE], swap_uv=True)
    # Flush-seated trapezoidal splayed cheek walls widening cleanly outward toward the sea (zero detached gaps!)
    for sx in (-1.0, 1.0):
        loft(mb, [
            [(sx * 1.46, 3.02, -1.74), (sx * 1.46, 3.02, -0.90), (sx * 1.12, 3.02, -0.90), (sx * 1.38, 3.02, -1.74)],
            [(sx * 1.45, 3.90, -1.72), (sx * 1.45, 3.90, -0.91), (sx * 1.14, 3.90, -0.91), (sx * 1.39, 3.90, -1.72)],
            [(sx * 1.43, 3.96, -1.68), (sx * 1.43, 3.96, -0.95), (sx * 1.18, 3.96, -0.95), (sx * 1.39, 3.96, -1.68)],
        ], 'stone', c_warm_hi, closed=True, caps=(False, True), mode='flat',
            scols=[c_warm_hi, c_pale_warm, C_STONE_PALE], swap_uv=True)

    # 5. Oak timber cannon firing platform & elevated firing banquette step inside the bastion (DECK_Y = 3.00)!
    for sz in (-0.56, 0.42, 1.38):
        cbox(mb, (0.0, DECK_Y + 0.015, sz), (5.20, 0.06, 0.14), 'wood', C_DARK, 0.0, skip=('-y',))
    plank_pal = (C_DECK, C_HULL, C_WEATH, C_DECK, C_DRIFT, C_HULL)
    for pi in range(6):
        pz = -0.62 + pi * 0.41
        cbox(mb, (0.0, DECK_Y + 0.055, pz), (5.28 + rng.uniform(-0.04, 0.04), 0.065, 0.36),
             'wood', jit(plank_pal[pi], rng, 0.07, 0.02), 0.0, (1, 0, 0), skip=('-y',))
    # Raised beveled oak gunner firing step / banquette right behind the central cannon embrasure
    bevel_slab(mb, (0.0, DECK_Y + 0.18, -0.60), (2.72, 0.22, 0.48), 'wood', C_HULL, 0.018)
    for sx in (-1.10, 1.10):
        cbox(mb, (sx, DECK_Y + 0.12, -0.60), (0.16, 0.18, 0.50), 'wood', C_DARK, 0.0, skip=('-y',))
    # Warm coral-limestone flagstone slabs paving the left & right bastion wings around the bollards
    for sx in (-1.0, 1.0):
        for fz in (-0.16, 0.96):
            cbox(mb, (sx * 3.45, DECK_Y + 0.04, fz), (1.46, 0.09, 1.06), 'stone', jit(c_warm_hi, rng, 0.04), 0.0, skip=('-y',))

    # 6. Two forged iron harbour mooring rings bolted cleanly to the seaward masonry face!
    for sx in (-1.0, 1.0):
        rx = sx * 2.18
        ry = 1.66
        t_bat = (ry - 0.64) / (2.76 - 0.64)
        rz = -2.02 + 0.33 * t_bat
        with xf(mb, T(rx, ry, rz - 0.02) @ R('X', 8.8)):
            # Forged-iron wall escutcheon plate + 2 heavy forged bolts
            cbox(mb, (0.0, 0.0, -0.02), (0.38, 0.38, 0.055), 'iron', C_IRON, 0.0, skip=('+z',))
            for by in (-0.13, 0.13):
                cbox(mb, (0.0, by, -0.052), (0.07, 0.06, 0.032), 'iron', mul(C_IRON, 1.25), 0.0, skip=('+z',))
            # Projecting forged-iron staple bracket + hanging heavy iron mooring ring!
            cbox(mb, (0.0, 0.03, -0.085), (0.09, 0.09, 0.12), 'iron', C_IRON, 0.0, skip=('+z',))
            with xf(mb, T(0.0, -0.15, -0.14) @ R('X', 72.0)):
                torus(mb, 0.19, 0.036, 8, 4, 'iron', C_IRON, False)

    # 7. Twin heavy forged-iron harbour mooring bollards on the seawall deck + braided hemp mooring rope!
    for sx in (-1.0, 1.0):
        px = sx * 3.30
        pz = 1.02
        with xf(mb, T(px, DECK_Y + 0.07, pz)):
            lathe(mb, [(0.0, 0.0), (0.26, 0.0), (0.22, 0.08), (0.16, 0.08), (0.18, 0.56), (0.23, 0.58), (0.21, 0.68), (0.0, 0.68)], 6, 'iron', C_IRON, False)
            with xf(mb, T(0, 0.46, 0) @ M_Y2X):
                cyl(mb, 0.06, -0.32, 0.32, 6, 'iron', C_IRON, False, 0.0)
            with xf(mb, T(0.0, 0.12, 0.0)):
                torus(mb, 0.21, 0.032, 8, 4, 'rope', C_ROPE, True)

    # 8. Trailing emerald sea-ivy drape ('foliage' material with UV2 wind weights!) cascading down weathered +X/-Z corner!
    # Lush overlapping curved broad emerald ivy crown hugging the +X/-Z cornice edge (zero pancake dome!)
    crown_specs = [
        ((4.18, 3.16, -1.94), ( 0.15, -0.08, -0.98), 0.46, 0.34, 0.20),
        ((4.42, 3.15, -1.86), ( 0.68, -0.10, -0.72), 0.48, 0.36, 0.22),
        ((4.54, 3.14, -1.64), ( 0.94, -0.12, -0.32), 0.44, 0.32, 0.22),
        ((3.92, 3.14, -1.96), (-0.18, -0.08, -0.98), 0.42, 0.30, 0.18),
        ((3.68, 3.10, -1.94), (-0.34, -0.12, -0.93), 0.38, 0.28, 0.18),
        ((4.30, 3.20, -1.78), ( 0.42,  0.12, -0.90), 0.40, 0.30, 0.16),
        ((4.46, 3.19, -1.72), ( 0.80,  0.10, -0.58), 0.38, 0.28, 0.16),
        ((4.06, 3.19, -1.84), ( 0.04,  0.14, -0.99), 0.36, 0.28, 0.14),
        ((4.56, 3.08, -1.42), ( 0.98, -0.16,  0.08), 0.38, 0.28, 0.24),
        ((4.38, 3.04, -1.98), ( 0.52, -0.36, -0.77), 0.42, 0.30, 0.26),
    ]
    crown_ph = rng.random()
    for ci, (c_root, c_dir, c_len, c_wid, c_droop) in enumerate(crown_specs):
        c_m = jit(mix(C_LEAF_DEEP, C_LEAF_MID, 0.42 + 0.38 * (ci % 3) * 0.5), rng, 0.06, 0.03)
        c_t = mix(c_m, C_LEAF_SUN, 0.38)
        _add_broad_leaf_blade(mb, c_root, c_dir, (0.0, 1.0, 0.0), c_len, c_wid, c_droop,
                              C_LEAF_DEEP, c_m, c_t, 0.06, 0.26, crown_ph, rng, rounded=True)

    # 3 cascading wind-swaying emerald sea-ivy vine runners draping over the sunlit corner quoins (UV2.x: 0.05 -> 0.94!)
    ivy_runners = [
        ((4.22, 3.08, -2.00), 2.18, (0.28, 0.0, -0.96), 7),
        ((4.54, 3.02, -1.76), 1.90, (0.86, 0.0, -0.50), 6),
        ((3.68, 3.02, -1.95), 1.58, (0.06, 0.0, -1.00), 5),
    ]
    for anc, v_len, v_dir, n_lv in ivy_runners:
        v_ph = rng.random()
        od = Vector(v_dir).normalized()
        side = Vector((-od.z, 0.0, od.x)).normalized()
        segs = 4
        st_l, st_r, st_c, st_u2 = [], [], [], []
        pts_v = []
        for si in range(segs + 1):
            t = si / float(segs)
            c_pt = Vector(anc) + od * (0.04 + 0.19 * t + 0.04 * sin(t * pi)) + side * (sin(t * pi * 1.7 + v_ph * 6.28) * 0.11) + Vector((0.0, -v_len * t, 0.0))
            pts_v.append(c_pt)
            sw = 0.028 * (1.0 - 0.50 * t)
            st_l.append(mb.v(c_pt - side * sw))
            st_r.append(mb.v(c_pt + side * sw))
            st_c.append(mix(C_LEAF_DEEP, C_LEAF_MID, 0.30 + 0.45 * t))
            st_u2.append((min(0.92, 0.05 + 0.86 * pow(t, 1.18)), v_ph))
        for si in range(segs):
            t0, t1 = si / float(segs), (si + 1) / float(segs)
            mb.f([st_l[si], st_r[si], st_r[si + 1], st_l[si + 1]], 'foliage',
                 [st_c[si], st_c[si], st_c[si + 1], st_c[si + 1]],
                 [(0.44, t0 * 2.0), (0.56, t0 * 2.0), (0.56, t1 * 2.0), (0.44, t1 * 2.0)],
                 smooth=True, uv2=[st_u2[si], st_u2[si], st_u2[si + 1], st_u2[si + 1]])
        for li in range(n_lv):
            frac = (li + 0.5) / float(n_lv)
            t = 0.08 + 0.86 * frac
            idx_f = t * segs
            i0 = min(segs - 1, int(idx_f))
            root = pts_v[i0].lerp(pts_v[i0 + 1], idx_f - i0)
            sgn = 1.0 if li % 2 == 0 else -1.0
            d_leaf = (side * (sgn * 0.68) + od * 0.64 + Vector((0.0, -0.32 + 0.14 * sin(li), 0.0))).normalized()
            l_len = rng.uniform(0.28, 0.40) * (1.08 - 0.32 * frac)
            l_wid = l_len * rng.uniform(0.64, 0.80)
            w_b = min(0.88, 0.08 + 0.78 * pow(t, 1.15))
            w_t = min(0.96, w_b + 0.12)
            c_m = jit(mix(C_LEAF_DEEP, C_LEAF_MID, 0.48 + 0.32 * frac), rng, 0.06, 0.03)
            c_t = mix(c_m, C_LEAF_SUN, 0.30 + 0.42 * frac)
            _add_broad_leaf_blade(mb, root, d_leaf, Vector((0.0, 1.0, 0.0)), l_len, l_wid, 0.24, C_LEAF_DEEP, c_m, c_t, w_b, w_t, v_ph, rng, rounded=True)

    # 9. Hanging forged-iron wall lantern bracket + Lantern_Seawall empty anchor!
    lantern_pos = (-3.95, 2.42, -2.42)
    cbox(mb, (-3.95, 2.74, -2.14), (0.10, 0.10, 0.68), 'iron', C_IRON, 0.0)
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
        ], 'thatch', tcol, closed=True, caps=(True, True), mode='flat', scols=[mul(tcol, 0.88), tcol])
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
    user_args = argv[argv.index('--') + 1:] if '--' in argv else []
    outdir = os.path.join(os.getcwd(), 'assets', 'generated')
    only_filter = None
    i = 0
    while i < len(user_args):
        arg = user_args[i]
        if arg.startswith('--only='):
            only_filter = only_filter or set()
            only_filter.update(s.strip().removesuffix('.glb').removeprefix('gen_') for s in arg.split('=', 1)[1].split(',') if s.strip())
        elif arg == '--only':
            only_filter = only_filter or set()
            while i + 1 < len(user_args) and not user_args[i + 1].startswith('--'):
                i += 1
                only_filter.update(s.strip().removesuffix('.glb').removeprefix('gen_') for s in user_args[i].split(',') if s.strip())
        else:
            outdir = arg
        i += 1

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
    if only_filter is not None:
        generators = [fn for fn in generators if fn.__name__.removeprefix('gen_') in only_filter]
    for fn in generators:
        fn(outdir)
    print('gen_props: exported %d props cleanly.' % len(generators))

if __name__ == '__main__':
    main()
