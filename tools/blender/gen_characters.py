# Sea of Scoundrels: procedural stylized character generator (Q10A Sculpted Anatomy & High-Relief PBR).
# Usage: blender --background --factory-startup --python tools/blender/gen_characters.py -- <outdir>
# Writes <outdir>/characters/{pirate,drowned,tidecaller}.glb. Deterministic (seeded).
# Everything is authored in *game* coordinates (Godot: -Z forward, +Y up, +X starboard/right, metres)
# with feet planted at y = 0 and standing height ~1.75 m, converted to Blender's Z-up frame at mesh
# and armature creation, matching tools/blender/gen_sloop.py.
import bpy
import sys
import os
import math
import random
import numpy as np
from contextlib import contextmanager
from math import sin, cos, pi, sqrt, radians, exp
from mathutils import Vector, Matrix

SEED = 1723

# ---------------------------------------------------------------- colour helpers
def srgb(h):
    h = h.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c)

def mul(c, f):
    return (c[0] * f, c[1] * f, c[2] * f)

def mix(a, b, t):
    return tuple(a[i] * (1.0 - t) + b[i] * t for i in range(3))

def jit(c, rng, amt=0.06, hue=0.02):
    f = 1.0 + rng.uniform(-amt, amt)
    return (
        max(0.0, min(1.0, c[0] * f * (1.0 + rng.uniform(-hue, hue)))),
        max(0.0, min(1.0, c[1] * f)),
        max(0.0, min(1.0, c[2] * f * (1.0 + rng.uniform(-hue, hue)))),
    )

def smooth01(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)

# Shared painterly palette (sRGB -> linear, matching gen_sloop.py warmth & saturation)
C_SKIN = srgb('#d9986c')
C_SKIN_WARM = srgb('#cf7f5a')
C_SKIN_DARK = srgb('#a66848')
C_SKIN_LIP = srgb('#b56652')
C_SKIN_CHEEK = srgb('#d68466')
C_SHIRT = srgb('#efe2c2')
C_TROUSER = srgb('#453d38')
C_LEATHER = srgb('#5a3520')
C_LEATHER_DARK = srgb('#362015')
C_LEATHER_LIGHT = srgb('#7e4e2e')
C_HAIR = srgb('#4a2c1a')
C_HAIR_LIGHT = srgb('#6b4126')
C_HAIR_DARK = srgb('#331c0f')
C_BRASS = srgb('#e8b546')
C_BRASS_DARK = srgb('#b3842c')
C_IRON = srgb('#3d424c')
C_EYE_WHITE = srgb('#f6f1e4')
C_EYE_IRIS = srgb('#2f2218')
C_EYE_DARK = srgb('#141110')

# Neutral shaded cloth base for tintable primary/secondary materials (tints multiply cleanly in Godot)
C_TINT_HI = srgb('#f5f3ee')
C_TINT_MID = srgb('#dcd8d0')
C_TINT_LO = srgb('#b5afa5')

# Drowned palette
C_BONE = srgb('#dfd5be')
C_BONE_DARK = srgb('#9e9278')
C_BONE_GREEN = srgb('#b9bf9e')
C_BONE_TEETH = srgb('#ece4cf')
C_SOCKET = srgb('#141a18')
C_BARNACLE = srgb('#8ca196')
C_BARNACLE_TIP = srgb('#d4d9cc')
C_KELP = srgb('#27593e')
C_KELP_HI = srgb('#3e7e56')
C_SEA_GLOW = srgb('#38ffc8')
C_KEG_RED = srgb('#c8281c')
C_KEG_GLOW = srgb('#ff5a18')
C_WOOD_ROT = srgb('#664a32')

# Tidecaller palette
C_MASK = srgb('#c8cbb8')
C_MASK_DARK = srgb('#6c7a72')
C_MASK_HI = srgb('#dce0cf')
C_ROBE_DEEP = srgb('#124a59')
C_ROBE_TRIM = srgb('#d4a94e')
C_CORAL_BASE = srgb('#d94646')
C_CORAL_MID = srgb('#f07254')
C_CORAL_TIP = srgb('#ffc285')
C_SHELL = srgb('#7d9c99')
C_SHELL_HI = srgb('#a6c0bc')
C_SHELL_DARK = srgb('#4f6968')
C_AQUA_GLOW = srgb('#2ef2ec')

SU, SV = 1.6, 1.6

# ---------------------------------------------------------------- transforms (game coords)
def T(x, y=None, z=None):
    return Matrix.Translation(Vector(x) if y is None else Vector((x, y, z)))

def R(axis, deg):
    return Matrix.Rotation(radians(deg), 4, axis)

def S(x, y=None, z=None):
    if y is None:
        y = z = x
    return Matrix.Diagonal((x, y, z, 1.0))

def conv(p):
    """Godot (+X right, +Y up, -Z forward) -> Blender (+X right, +Y forward, +Z up)."""
    return (p[0], -p[2], p[1])

def newell(pts):
    n = Vector((0.0, 0.0, 0.0))
    for i in range(len(pts)):
        a = pts[i]
        b = pts[(i + 1) % len(pts)]
        n.x += (a.y - b.y) * (a.z + b.z)
        n.y += (a.z - b.z) * (a.x + b.x)
        n.z += (a.x - b.x) * (a.y + b.y)
    return n

# ---------------------------------------------------------------- shared 19-bone skeleton spec
# All coordinates in Godot metres: feet at y = 0.0, top of bare skull/head ~1.73 m, facing -Z.
# Tuple: (name, parent, head_godot, tail_godot, roll_align_godot)
P_HIPS = (0.0, 0.90, 0.0)
P_SPINE = (0.0, 1.04, 0.0)
P_CHEST = (0.0, 1.21, 0.0)
P_NECK = (0.0, 1.41, 0.0)
P_HEAD = (0.0, 1.49, 0.0)
P_HEAD_TOP = (0.0, 1.73, 0.0)

def _arm_pts(sx):
    # Clean A-pose (~40 deg down from horizontal, slight forward elbow bend)
    return (
        (sx * 0.07, 1.36, 0.01),   # Shoulder head
        (sx * 0.21, 1.37, 0.01),   # UpperArm head (glenohumeral joint)
        (sx * 0.38, 1.15, 0.03),   # Forearm head (elbow)
        (sx * 0.52, 0.95, -0.03),  # Hand head (wrist)
        (sx * 0.60, 0.83, -0.06),  # Hand tail (fingertips)
    )

def _leg_pts(sx):
    return (
        (sx * 0.115, 0.86, 0.0),   # Thigh head (hip socket)
        (sx * 0.115, 0.45, -0.01), # Shin head (knee)
        (sx * 0.115, 0.09, 0.02),  # Foot head (ankle)
        (sx * 0.120, 0.04, -0.16), # Foot tail (toes pointing -Z)
    )

BONE_SPECS = [
    ("Hips", None, P_HIPS, P_SPINE, (0, 0, 1)),
    ("Spine", "Hips", P_SPINE, P_CHEST, (0, 0, 1)),
    ("Chest", "Spine", P_CHEST, P_NECK, (0, 0, 1)),
    ("Neck", "Chest", P_NECK, P_HEAD, (0, 0, 1)),
    ("Head", "Neck", P_HEAD, P_HEAD_TOP, (0, 0, 1)),
]
for _side, _sx in (("L", -1.0), ("R", 1.0)):
    _sh, _ua, _el, _wr, _ft = _arm_pts(_sx)
    BONE_SPECS.extend([
        ("Shoulder_" + _side, "Chest", _sh, _ua, (0, 0, 1)),
        ("UpperArm_" + _side, "Shoulder_" + _side, _ua, _el, (0, 0, 1)),
        ("Forearm_" + _side, "UpperArm_" + _side, _el, _wr, (0, 0, 1)),
        ("Hand_" + _side, "Forearm_" + _side, _wr, _ft, (0, 0, 1)),
    ])
for _side, _sx in (("L", -1.0), ("R", 1.0)):
    _hp, _kn, _an, _to = _leg_pts(_sx)
    BONE_SPECS.extend([
        ("Thigh_" + _side, "Hips", _hp, _kn, (0, 0, -1)),
        ("Shin_" + _side, "Thigh_" + _side, _kn, _an, (0, 0, -1)),
        ("Foot_" + _side, "Shin_" + _side, _an, _to, (0, 1, 0)),
    ])

assert len(BONE_SPECS) == 19

def make_armature(name):
    arm_data = bpy.data.armatures.new(name)
    arm_obj = bpy.data.objects.new(name, arm_data)
    bpy.context.scene.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode='EDIT')
    ebones = arm_data.edit_bones
    for bname, parent, hd, tl, roll_axis in BONE_SPECS:
        eb = ebones.new(bname)
        eb.head = Vector(conv(hd))
        eb.tail = Vector(conv(tl))
        eb.use_deform = True
        eb.use_connect = False
        eb.align_roll(Vector(conv(roll_axis)))
        if parent is not None:
            eb.parent = ebones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    return arm_obj

# ---------------------------------------------------------------- semantic skin weight functions
def norm_weights(w):
    items = [(k, float(v)) for k, v in w.items() if v > 1e-4]
    items.sort(key=lambda kv: -kv[1])
    items = items[:4]
    s = sum(v for _, v in items)
    if s <= 1e-8:
        return {"Hips": 1.0}
    return {k: v / s for k, v in items}

def eval_weight(spec, p):
    if isinstance(spec, str):
        return {spec: 1.0}
    if isinstance(spec, dict):
        return norm_weights(spec)
    return norm_weights(spec(p))

def w_torso(p):
    y = p.y
    if y <= 0.96:
        return {"Hips": 1.0}
    if y < 1.10:
        t = smooth01((y - 0.96) / 0.14)
        return {"Hips": 1.0 - t, "Spine": t}
    if y <= 1.15:
        return {"Spine": 1.0}
    if y < 1.27:
        t = smooth01((y - 1.15) / 0.12)
        return {"Spine": 1.0 - t, "Chest": t}
    if y <= 1.38:
        return {"Chest": 1.0}
    if y < 1.45:
        t = smooth01((y - 1.38) / 0.07)
        return {"Chest": 1.0 - t, "Neck": t}
    if y < 1.52:
        t = smooth01((y - 1.45) / 0.07)
        return {"Neck": 1.0 - t, "Head": t}
    return {"Head": 1.0}

def w_leg(side):
    th = "Thigh_" + side
    sh = "Shin_" + side
    ft = "Foot_" + side
    def fn(p):
        y = p.y
        if y >= 0.91:
            return {"Hips": 1.0}
        if y > 0.80:
            t = smooth01((y - 0.80) / 0.11)
            return {th: 1.0 - t, "Hips": t}
        if y >= 0.51:
            return {th: 1.0}
        if y > 0.39:
            t = smooth01((y - 0.39) / 0.12)
            return {sh: 1.0 - t, th: t}
        if y >= 0.14:
            return {sh: 1.0}
        if y > 0.07:
            t = smooth01((y - 0.07) / 0.07)
            return {ft: 1.0 - t, sh: t}
        return {ft: 1.0}
    return fn

def w_arm(side):
    sx = -1.0 if side == "L" else 1.0
    sh_p, ua_p, el_p, wr_p, ft_p = [Vector(q) for q in _arm_pts(sx)]
    sh_b = "Shoulder_" + side
    ua_b = "UpperArm_" + side
    fa_b = "Forearm_" + side
    hd_b = "Hand_" + side

    def proj(p, a, b):
        d = b - a
        l2 = d.length_squared
        if l2 < 1e-8:
            return 0.0
        return max(0.0, min(1.0, (p - a).dot(d) / l2))

    def fn(p):
        ax = p.x * sx
        if ax < 0.15:
            t = smooth01((ax - 0.09) / 0.06)
            return {"Chest": 1.0 - t, sh_b: t}
        if ax < 0.24:
            t = smooth01((ax - 0.17) / 0.07)
            return {sh_b: 1.0 - t, ua_b: t}
        tu = proj(p, ua_p, el_p)
        tf = proj(p, el_p, wr_p)
        du = (p - ua_p.lerp(el_p, tu)).length
        df = (p - el_p.lerp(wr_p, tf)).length
        dh = (p - wr_p.lerp(ft_p, proj(p, wr_p, ft_p))).length
        d_el = (p - el_p).length
        d_wr = (p - wr_p).length
        if d_wr < 0.055 and (dh <= df + 0.03):
            t = smooth01(proj(p, el_p.lerp(wr_p, 0.78), wr_p.lerp(ft_p, 0.28)))
            return {fa_b: 1.0 - t, hd_b: t}
        if dh < df and dh < du and (p - wr_p).dot(ft_p - wr_p) > 0:
            return {hd_b: 1.0}
        if d_el < 0.07:
            t = smooth01(proj(p, ua_p.lerp(el_p, 0.72), el_p.lerp(wr_p, 0.28)))
            return {ua_b: 1.0 - t, fa_b: t}
        if du <= df:
            return {ua_b: 1.0}
        return {fa_b: 1.0}
    return fn

def w_coat_skirt(p):
    """Smooth torso + split lower coat tails / robe skirt following thighs and shins."""
    if p.y >= 0.97:
        return w_torso(p)
    v = smooth01((0.97 - p.y) / 0.36)
    side_mix = max(-1.0, min(1.0, p.x / 0.09))
    w = {"Hips": 1.0 - 0.56 * v}
    if side_mix >= 0.0:
        leg_w = 0.56 * v * (0.5 + 0.5 * side_mix)
        other_w = 0.56 * v - leg_w
        if p.y < 0.48:
            shin_t = smooth01((0.48 - p.y) / 0.28) * 0.55
            w["Thigh_R"] = leg_w * (1.0 - shin_t)
            w["Shin_R"] = leg_w * shin_t
            w["Thigh_L"] = other_w * (1.0 - shin_t)
            w["Shin_L"] = other_w * shin_t
        else:
            w["Thigh_R"] = leg_w
            w["Thigh_L"] = other_w
    else:
        leg_w = 0.56 * v * (0.5 - 0.5 * side_mix)
        other_w = 0.56 * v - leg_w
        if p.y < 0.48:
            shin_t = smooth01((0.48 - p.y) / 0.28) * 0.55
            w["Thigh_L"] = leg_w * (1.0 - shin_t)
            w["Shin_L"] = leg_w * shin_t
            w["Thigh_R"] = other_w * (1.0 - shin_t)
            w["Shin_R"] = other_w * shin_t
        else:
            w["Thigh_L"] = leg_w
            w["Thigh_R"] = other_w
    return w

def w_belt_sash(p):
    if p.y < 0.86 and p.x < -0.05:
        t = smooth01((0.86 - p.y) / 0.22)
        return {"Hips": 1.0 - 0.55 * t, "Thigh_L": 0.55 * t}
    t = smooth01((p.y - 0.94) / 0.14)
    return {"Hips": 1.0 - 0.4 * t, "Spine": 0.4 * t}

# ---------------------------------------------------------------- mesh builder with weights
class MB:
    def __init__(self, name, seed=0):
        self.name = name
        self.verts = []
        self.weights = []
        self.faces = []
        self.fmat = []
        self.fsm = []
        self.fcol = []
        self.fuv = []
        self.stack = [Matrix.Identity(4)]
        self.flip = False
        self.rng = random.Random(SEED * 7919 + seed + sum(ord(c) for c in name))
        self.off = (0.0, 0.0)
        self.cur_w = "Hips"

    def push(self, M):
        self.stack.append(self.stack[-1] @ M)
        self.flip = self.stack[-1].to_3x3().determinant() < 0

    def pop(self):
        self.stack.pop()
        self.flip = self.stack[-1].to_3x3().determinant() < 0

    def newoff(self):
        self.off = (self.rng.random(), self.rng.random())
        return self.off

    def v(self, p, wspec=None):
        wp = self.stack[-1] @ Vector(p)
        self.verts.append(wp)
        self.weights.append(eval_weight(self.cur_w if wspec is None else wspec, wp))
        return len(self.verts) - 1

    def f(self, idx, mat, col, uvs, smooth=False):
        if len(set(idx)) < 3:
            return
        if self.flip:
            idx = idx[::-1]
            uvs = uvs[::-1]
            if isinstance(col, list):
                col = col[::-1]
        self.faces.append(tuple(idx))
        self.fmat.append(mat)
        self.fsm.append(smooth)
        self.fcol.append(col)
        self.fuv.append(uvs)

    def fp(self, pts, mat, col, inside=None, wspec=None, smooth=False):
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
        g = Vector((0, 1, 0)) if abs(n.y) < 0.85 else Vector((0, 0, 1))
        gu = (g - n * g.dot(n)).normalized()
        gv = n.cross(gu)
        o = self.off
        uvs = [(p.dot(gu) * SU + o[0], p.dot(gv) * SV + o[1]) for p in pts]
        self.f([self.v(p, wspec) for p in pts], mat, col, uvs, smooth)

    def tris(self):
        return sum(len(f) - 2 for f in self.faces)

@contextmanager
def xf(mb, M):
    mb.push(M)
    try:
        yield
    finally:
        mb.pop()

@contextmanager
def wctx(mb, wspec):
    prev = mb.cur_w
    mb.cur_w = wspec
    try:
        yield
    finally:
        mb.cur_w = prev

# ---------------------------------------------------------------- sculptural primitives
def cbox(mb, c, size, mat, col, ch=0.012, M=None, skip=(), wspec=None):
    """Bevelled painterly box centred at c (reserved for crisp hardware/buckles/woodwork)."""
    h = [size[0] / 2.0, size[1] / 2.0, size[2] / 2.0]
    ch = min(ch, min(h) * 0.42)
    mb.newoff()
    X = T(c) @ M if M is not None else T(c)
    names = 'xyz'
    with xf(mb, X):
        O = Vector((0, 0, 0))
        def fv(a, s, s1, s2):
            p = [0.0, 0.0, 0.0]
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
                shade = 1.06 if (a == 1 and s > 0) else (0.82 if (a == 1 and s < 0) else 1.0)
                mb.fp([fv(a, s, -1, -1), fv(a, s, 1, -1), fv(a, s, 1, 1), fv(a, s, -1, 1)],
                      mat, mul(col, shade), O, wspec)
        if ch > 1e-5:
            dk = mul(col, 0.87)
            def on(a, sa, b, sb, sc):
                cc = 3 - a - b
                p = [0.0, 0.0, 0.0]
                p[a] = sa * h[a]
                p[b] = sb * (h[b] - ch)
                p[cc] = sc * (h[cc] - ch)
                return Vector(p)
            for a in range(3):
                for b in range(a + 1, 3):
                    for sa in (-1, 1):
                        for sb in (-1, 1):
                            mb.fp([on(a, sa, b, sb, -1), on(a, sa, b, sb, 1),
                                   on(b, sb, a, sa, 1), on(b, sb, a, sa, -1)], mat, dk, O, wspec)
            for sx in (-1, 1):
                for sy in (-1, 1):
                    for sz in (-1, 1):
                        mb.fp([
                            Vector((sx * h[0], sy * (h[1] - ch), sz * (h[2] - ch))),
                            Vector((sx * (h[0] - ch), sy * h[1], sz * (h[2] - ch))),
                            Vector((sx * (h[0] - ch), sy * (h[1] - ch), sz * h[2])),
                        ], mat, dk, O, wspec)

def _dir_shade_factor(nrm):
    f = 0.92 + 0.12 * nrm.y - 0.04 * nrm.z
    return max(0.76, min(1.12, f))

def loft(mb, secs, mat, col, closed=True, caps=(True, True), smooth=True,
         scols=None, flip=None, wspec=None, shade_dir=True, cap_poles=(False, False)):
    """Connect consecutive cross-section rings with smooth per-vertex painterly shading."""
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
    ids = [[mb.v(p, wspec) for p in s] for s in secs]

    # Build smooth per-ring colors and smooth per-vertex normals (no flat color faceting!)
    if scols:
        if len(scols) >= n:
            rcols = [scols[i] for i in range(n)]
        else:
            rcols = [scols[0]]
            for i in range(1, n - 1):
                rcols.append(mix(scols[i - 1], scols[min(i, len(scols) - 1)], 0.5))
            rcols.append(scols[-1])
    else:
        rcols = [col] * n

    vcols = None
    if smooth and shade_dir:
        vn = [[Vector((0.0, 0.0, 0.0)) for _ in range(k)] for _ in range(n)]
        for i in range(n - 1):
            for j in range(ne):
                j1 = (j + 1) % k
                q = [mb.verts[ids[i][j]], mb.verts[ids[i][j1]], mb.verts[ids[i + 1][j1]], mb.verts[ids[i + 1][j]]]
                if flip:
                    q = q[::-1]
                fn = newell(q)
                if fn.length > 1e-8:
                    fn.normalize()
                    vn[i][j] += fn
                    vn[i][j1] += fn
                    vn[i + 1][j1] += fn
                    vn[i + 1][j] += fn
        vcols = []
        for i in range(n):
            row = []
            for j in range(k):
                nv = vn[i][j]
                if nv.length > 1e-8:
                    nv = nv.normalized()
                    row.append(mul(rcols[i], _dir_shade_factor(nv)))
                else:
                    row.append(rcols[i])
            vcols.append(row)
    elif smooth:
        vcols = [[rcols[i] for _ in range(k)] for i in range(n)]

    for i in range(n - 1):
        base_c = scols[min(i, len(scols) - 1)] if scols else col
        for j in range(ne):
            j1 = (j + 1) % k
            idx = [ids[i][j], ids[i][j1], ids[i + 1][j1], ids[i + 1][j]]
            uvs = [
                (L[i] * SU + o[0], W[i][j] * SV + o[1]),
                (L[i] * SU + o[0], W[i][j + 1] * SV + o[1]),
                (L[i + 1] * SU + o[0], W[i + 1][j + 1] * SV + o[1]),
                (L[i + 1] * SU + o[0], W[i + 1][j] * SV + o[1]),
            ]
            ccols = [vcols[i][j], vcols[i][j1], vcols[i + 1][j1], vcols[i + 1][j]] if vcols is not None else None
            if flip:
                idx = idx[::-1]
                uvs = uvs[::-1]
                if ccols is not None:
                    ccols = ccols[::-1]
            keep, kuv, kcol = [], [], []
            for m_i, (a, b) in enumerate(zip(idx, uvs)):
                if all((mb.verts[a] - mb.verts[q]).length > 1e-6 for q in keep):
                    keep.append(a)
                    kuv.append(b)
                    if ccols is not None:
                        kcol.append(ccols[m_i])
            if len(keep) >= 3:
                if vcols is not None:
                    fc = kcol
                else:
                    fc = base_c
                    if shade_dir:
                        nrm = newell([mb.verts[q] for q in keep])
                        if nrm.length > 1e-7:
                            nrm.normalize()
                            fc = mul(base_c, _dir_shade_factor(nrm))
                mb.f(keep, mat, fc, kuv, smooth)

    def _emit_pole_cap(ring_i, ref_i, l_sign, col_mul):
        ring_pts = secs[ring_i]
        pole_p = cents[ring_i]
        r_avg = max(0.008, sum((p - pole_p).length for p in ring_pts) / k)
        pole_id = mb.v(pole_p, wspec)
        pole_col = mul(rcols[ring_i], col_mul)
        l_pole = L[ring_i] + l_sign * r_avg
        for j in range(k):
            j1 = (j + 1) % k
            pa, pb = ring_pts[j], ring_pts[j1]
            if (pa - pb).length < 1e-6:
                continue
            tri_pts = [pole_p, pa, pb]
            nrm = newell(tri_pts)
            if nrm.length < 1e-9:
                continue
            tri_c = (pole_p + pa + pb) / 3.0
            ca_c = vcols[ring_i][j] if vcols is not None else rcols[ring_i]
            cb_c = vcols[ring_i][j1] if vcols is not None else rcols[ring_i]
            uva = (L[ring_i] * SU + o[0], W[ring_i][j] * SV + o[1])
            uvb = (L[ring_i] * SU + o[0], W[ring_i][j + 1] * SV + o[1])
            uvp = (l_pole * SU + o[0], 0.5 * (W[ring_i][j] + W[ring_i][j + 1]) * SV + o[1])
            if nrm.dot(tri_c - cents[ref_i]) < 0:
                mb.f([pole_id, ids[ring_i][j1], ids[ring_i][j]], mat, [pole_col, cb_c, ca_c], [uvp, uvb, uva], smooth)
            else:
                mb.f([pole_id, ids[ring_i][j], ids[ring_i][j1]], mat, [pole_col, ca_c, cb_c], [uvp, uva, uvb], smooth)

    if closed and caps[0] and n > 1:
        if cap_poles[0]:
            _emit_pole_cap(0, 1, -1.0, 0.88)
        else:
            mb.fp(secs[0], mat, mul(rcols[0], 0.86), cents[1], wspec)
    if closed and caps[1] and n > 1:
        if cap_poles[1]:
            _emit_pole_cap(n - 1, n - 2, 1.0, 1.05)
        else:
            mb.fp(secs[-1], mat, mul(rcols[-1], 1.04), cents[-2], wspec)

def ring_ellipse(c, rx, rz, segs=14, front_bias=0.0, sq=0.0, rot_y=0.0, tilt_x=0.0, tilt_z=0.0,
                 back_bias=0.0, mod_fn=None):
    """Create a horizontal sculpted cross-section ring around center c (Godot coords)."""
    pts = []
    c0 = Vector(c)
    M = R('Y', rot_y) @ R('X', tilt_x) @ R('Z', tilt_z)
    for k in range(segs):
        a = 2.0 * pi * k / segs
        ca, sa = cos(a), sin(a)
        if sq > 0.0:
            p = 1.0 - 0.35 * sq
            ca = math.copysign(abs(ca) ** p, ca)
            sa = math.copysign(abs(sa) ** p, sa)
        x = ca * rx
        y = 0.0
        z = sa * rz
        if z < 0.0 and front_bias != 0.0:
            z *= (1.0 + front_bias)
        elif z > 0.0 and back_bias != 0.0:
            z *= (1.0 + back_bias)
        if mod_fn is not None:
            rm, dy, dz = mod_fn(a)
            x *= rm
            z = z * rm + dz
            y += dy
        pts.append(c0 + (M @ Vector((x, y, z))))
    return pts

def tube(mb, path, rad, sides, mat, col, caps=(True, True), smooth=True, scols=None, wspec=None,
         cap_poles=(False, False), shade_dir=True):
    path = [Vector(p) for p in path]
    n = len(path)
    if isinstance(rad, tuple) and len(rad) == 2 and all(isinstance(v, (int, float)) for v in rad):
        rads = [rad] * n
    elif isinstance(rad, (list, tuple)):
        rads = rad
    else:
        rads = [rad] * n
    secs = []
    nrm = None
    for i in range(n):
        t = (path[min(i + 1, n - 1)] - path[max(i - 1, 0)])
        if t.length < 1e-7:
            t = Vector((0, 1, 0))
        else:
            t.normalize()
        if nrm is None:
            ref = Vector((0, 1, 0)) if abs(t.y) < 0.9 else Vector((1, 0, 0))
            nrm = ref - t * ref.dot(t)
        else:
            nrm = nrm - t * nrm.dot(t)
        if nrm.length < 1e-7:
            nrm = Vector((1, 0, 0))
        nrm.normalize()
        bn = t.cross(nrm)
        r = rads[i]
        rx, rz = (r[0], r[1]) if isinstance(r, (list, tuple)) else (r, r)
        secs.append([
            path[i] + nrm * (rx * cos(2 * pi * k / sides)) + bn * (rz * sin(2 * pi * k / sides))
            for k in range(sides)
        ])
    loft(mb, secs, mat, col, True, caps, smooth, scols=scols, wspec=wspec,
         shade_dir=shade_dir, cap_poles=cap_poles)

def ellipsoid(mb, c, radii, mat, col, segs=12, rings=6, M=None, smooth=True, wspec=None, shade_dir=True):
    c0 = Vector(c)
    rx, ry, rz = radii
    X = T(c0) @ (M if M is not None else Matrix.Identity(4))
    secs = []
    for i in range(1, rings):
        th = pi * i / rings
        y = -cos(th) * ry
        r = sin(th)
        secs.append([X @ Vector((rx * r * cos(2 * pi * k / segs), y, rz * r * sin(2 * pi * k / segs)))
                     for k in range(segs)])
    bot = [X @ Vector((rx * 0.04 * cos(2 * pi * k / segs), -ry, rz * 0.04 * sin(2 * pi * k / segs)))
           for k in range(segs)]
    top = [X @ Vector((rx * 0.04 * cos(2 * pi * k / segs), ry, rz * 0.04 * sin(2 * pi * k / segs)))
           for k in range(segs)]
    loft(mb, [bot] + secs + [top], mat, col, True, (True, True), smooth, wspec=wspec,
         shade_dir=shade_dir, cap_poles=(True, True))

def cone(mb, base, tip, r0, r1, segs, mat, col, smooth=True, wspec=None, cap_poles=(False, True)):
    tube(mb, [base, tip], [r0, max(r1, 0.002)], segs, mat, col, (True, r1 > 0.0025),
         smooth, wspec=wspec, cap_poles=cap_poles)

def torus(mb, c, major_r, minor_r, segs=18, psegs=10, mat='brass', col=C_BRASS,
          M=None, smooth=True, wspec=None, shade_dir=True):
    """Seamless smooth circular torus centred at c (lying in local X-Z plane by default)."""
    X = T(c) @ (M if M is not None else Matrix.Identity(4))
    o = mb.newoff()
    u_len = 2.0 * pi * major_r * SU
    v_len = 2.0 * pi * minor_r * SV
    ids = []
    vcols = []
    ring_pts = []
    ring_cents = []
    for i in range(segs):
        a = 2.0 * pi * i / segs
        ca, sa = cos(a), sin(a)
        rc = X @ Vector((ca * major_r, 0.0, sa * major_r))
        ring_cents.append(rc)
        row_id = []
        row_col = []
        row_p = []
        for j in range(psegs):
            b = 2.0 * pi * j / psegs
            cb, sb = cos(b), sin(b)
            rad = major_r + minor_r * cb
            lp = Vector((ca * rad, minor_r * sb, sa * rad))
            wp = X @ lp
            row_id.append(mb.v(wp, wspec))
            row_p.append(wp)
            if shade_dir:
                wn = (wp - rc)
                if wn.length > 1e-8:
                    wn.normalize()
                    row_col.append(mul(col, _dir_shade_factor(wn)))
                else:
                    row_col.append(col)
            else:
                row_col.append(col)
        ids.append(row_id)
        vcols.append(row_col)
        ring_pts.append(row_p)
    # Determine outward winding once
    q0 = [ring_pts[0][0], ring_pts[1 % segs][0], ring_pts[1 % segs][1 % psegs], ring_pts[0][1 % psegs]]
    rc_mid = 0.5 * (ring_cents[0] + ring_cents[1 % segs])
    flip = newell(q0).dot(sum(q0, Vector()) * 0.25 - rc_mid) < 0
    for i in range(segs):
        i1 = (i + 1) % segs
        u0 = (i / float(segs)) * u_len + o[0]
        u1 = ((i + 1) / float(segs)) * u_len + o[0]
        for j in range(psegs):
            j1 = (j + 1) % psegs
            v0 = (j / float(psegs)) * v_len + o[1]
            v1 = ((j + 1) / float(psegs)) * v_len + o[1]
            idx = [ids[i][j], ids[i1][j], ids[i1][j1], ids[i][j1]]
            uvs = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
            cols = [vcols[i][j], vcols[i1][j], vcols[i1][j1], vcols[i][j1]]
            if flip:
                idx = idx[::-1]
                uvs = uvs[::-1]
                cols = cols[::-1]
            mb.f(idx, mat, cols if smooth else cols[0], uvs, smooth)

def feather_plume(mb, spine_pts, w_left, w_right, thick, mat_vane, mat_quill, col_base, col_tip,
                  notches=(), wspec=None):
    """Sculpted smooth curving ostrich feather plume with central rachis quill & notched vanes."""
    pts = [Vector(p) for p in spine_pts]
    n = len(pts)
    # Central smooth rachis quill
    q_rads = [0.0055 * (1.0 - 0.65 * (i / max(n - 1, 1))) for i in range(n)]
    tube(mb, pts, q_rads, 8, mat_quill, C_TINT_HI, (True, True), True, wspec=wspec, cap_poles=(True, True))

    # Cambered 6-vertex cross-section blade along spine with stylized notches
    secs = []
    scols = []
    nrm = None
    for i in range(n):
        u = i / max(n - 1, 1)
        t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)])
        t = t.normalized() if t.length > 1e-7 else Vector((0, 1, 0))
        if nrm is None:
            ref = Vector((0, 1, 0)) if abs(t.y) < 0.85 else Vector((1, 0, 0))
            nrm = (ref - t * ref.dot(t)).normalized()
        else:
            nrm = (nrm - t * nrm.dot(t)).normalized()
        side = t.cross(nrm).normalized()
        wl = w_left[i]
        wr = w_right[i]
        th = thick[i]
        # Optional stylized barb notch pinch
        for nu, ns, depth in notches:
            d = abs(u - nu)
            if d < 0.08:
                pinch = 1.0 - depth * (1.0 - d / 0.08) ** 2
                if ns < 0:
                    wl *= pinch
                else:
                    wr *= pinch
        p = pts[i]
        # Cambered feather profile drooping gently at edges
        c_drop = -nrm * (th * 1.4)
        ring = [
            p - side * wl + c_drop,
            p - side * (wl * 0.45) + nrm * (th * 0.85),
            p + nrm * th,
            p + side * (wr * 0.45) + nrm * (th * 0.85),
            p + side * wr + c_drop,
            p - nrm * (th * 0.55),
        ]
        secs.append(ring)
        scols.append(mix(col_base, col_tip, u ** 0.8))
    loft(mb, secs, mat_vane, col_tip, True, (True, True), True, scols=scols, wspec=wspec, cap_poles=(True, True))

# ---------------------------------------------------------------- sculpted anatomical hands (all 3 rigs)
def _hand_frame(wr, ft):
    """Build right-handed local hand frame at wrist:
    +Y = distal (wrist->fingertips), +X*sx = dorsal (back of hand), -X*sx = palmar,
    +Z = radial/forward (thumb & index side, Godot -Z), -Z = ulnar/pinky side."""
    h_dir = (ft - wr).normalized()
    up_ref = Vector((0, 0, -1))
    side_v = h_dir.cross(up_ref).normalized()
    fwd_v = side_v.cross(h_dir).normalized()
    return Matrix((
        (side_v.x, h_dir.x, fwd_v.x, wr.x),
        (side_v.y, h_dir.y, fwd_v.y, wr.y),
        (side_v.z, h_dir.z, fwd_v.z, wr.z),
        (0.0, 0.0, 0.0, 1.0),
    ))

def sculpt_hand(mb, wr, ft, side, style='pirate'):
    """Flagship stylized anatomical hand with cupped palm, 4 separated curled fingers & opposable thumb.
    Weighted 100% cleanly to Hand_L / Hand_R."""
    sx = -1.0 if side == "L" else 1.0
    H = _hand_frame(wr, ft)

    with wctx(mb, "Hand_" + side):
        with xf(mb, H):
            if style == 'pirate':
                # Sculpted stylized Sea-of-Thieves pirate hand (~1.25x bold readable heroic proportions)
                # 1. Anatomical cupped palm loft (wrist -> heel of hand -> mid-palm -> arched knuckle line)
                palm_specs = [
                    (0.000, -0.002, 0.025, 0.032, 0.000),  # wrist root
                    (0.024,  0.002, 0.029, 0.044, -0.002), # heel of palm
                    (0.056,  0.004, 0.030, 0.052, -0.004), # mid palm (broad & cupped)
                    (0.088,  0.000, 0.027, 0.051, -0.005), # metacarpal knuckle bar
                    (0.104, -0.004, 0.020, 0.046, -0.004), # distal knuckle ridge
                ]
                p_secs = []
                for py, pz, rx, rz, cup in palm_specs:
                    ring = []
                    for k in range(12):
                        a = 2.0 * pi * k / 12.0
                        ca, sa = cos(a), sin(a)
                        # Cup palmar side (-sx*X) slightly inward, arch dorsal side (+sx*X) subtly outward
                        x_v = ca * rx + sx * cup * (1.0 - sa * sa)
                        # Slight knuckle-arch taper toward pinky (-Z)
                        y_v = py + (0.005 * sa if py > 0.06 else 0.0)
                        z_v = pz + sa * rz
                        ring.append(Vector((x_v, y_v, z_v)))
                    p_secs.append(ring)
                loft(mb, p_secs, 'skin', C_SKIN, True, (True, True), True,
                     scols=[C_SKIN_DARK, C_SKIN, C_SKIN, mul(C_SKIN, 1.04), C_SKIN_WARM],
                     cap_poles=(True, True))

                # Subtle sculpted knuckle domes across dorsal metacarpal ridge
                kn_data = [
                    (0.033, 0.095, 0.0135),  # index
                    (0.011, 0.098, 0.0145),  # middle
                    (-0.011, 0.095, 0.0135), # ring
                    (-0.033, 0.089, 0.0120), # pinky
                ]
                for fz, ky, kr in kn_data:
                    ellipsoid(mb, (sx * 0.015, ky, fz), (kr * 0.85, kr * 0.95, kr * 0.95),
                              'skin', mul(C_SKIN, 1.05), segs=8, rings=4, smooth=True)

                # 4 individually separated gently-curled anatomical fingers (Index -> Pinky)
                fingers = [
                    # (z_base, y_start, len1, len2, len3, r_base, curl_scale)
                    ( 0.033, 0.094, 0.030, 0.022, 0.018, 0.0118, 0.92), # Index
                    ( 0.011, 0.097, 0.033, 0.024, 0.019, 0.0122, 1.00), # Middle
                    (-0.011, 0.094, 0.031, 0.022, 0.018, 0.0115, 1.08), # Ring
                    (-0.033, 0.088, 0.025, 0.018, 0.015, 0.0102, 1.16), # Pinky
                ]
                for fz, y0, l1, l2, l3, r0, cs in fingers:
                    a1 = radians(16.0 * cs)
                    a2 = radians(40.0 * cs)
                    a3 = radians(64.0 * cs)
                    p0 = Vector((sx * 0.004, y0, fz))
                    p1 = p0 + Vector((-sx * sin(a1) * l1, cos(a1) * l1, 0.0))
                    p2 = p1 + Vector((-sx * sin(a2) * l2, cos(a2) * l2, 0.0))
                    p3 = p2 + Vector((-sx * sin(a3) * l3, cos(a3) * l3, 0.0))
                    rads = [r0, r0 * 0.92, r0 * 0.82, r0 * 0.62]
                    tube(mb, [p0, p1, p2, p3], rads, 8, 'skin', C_SKIN, (True, True), True,
                         scols=[C_SKIN, C_SKIN_WARM, C_SKIN_WARM], cap_poles=(False, True))

                # Sculpted thenar muscle pad + opposable thumb on anatomical +Z (radial/forward) side!
                ellipsoid(mb, (-sx * 0.010, 0.044, 0.036), (0.022, 0.032, 0.026),
                          'skin', C_SKIN_WARM, segs=10, rings=5, M=R('X', 18), smooth=True)
                th_pts = [
                    Vector((-sx * 0.008, 0.042, 0.042)),
                    Vector((-sx * 0.022, 0.070, 0.062)),
                    Vector((-sx * 0.034, 0.098, 0.072)),
                    Vector((-sx * 0.040, 0.118, 0.064)),
                ]
                tube(mb, th_pts, [0.0165, 0.0145, 0.0128, 0.0095], 8, 'skin', C_SKIN_WARM,
                     (True, True), True, scols=[C_SKIN, C_SKIN_WARM, mul(C_SKIN_WARM, 1.04)],
                     cap_poles=(False, True))

            elif style == 'drowned':
                # Sculpted skeletal hand: carpal block + 4 dorsal metacarpal shafts + articulated phalanges
                ellipsoid(mb, (0.0, 0.020, 0.0), (0.016, 0.020, 0.028), 'bone', C_BONE_DARK, segs=10, rings=5, smooth=True)
                # 4 separated skeletal fingers (metacarpal + 3 phalanx segments with subtle joint knuckles!)
                skel_fingers = [
                    ( 0.028, 0.076, 0.026, 0.020, 0.016, 0.0072, 0.95), # Index
                    ( 0.009, 0.080, 0.029, 0.022, 0.017, 0.0076, 1.02), # Middle
                    (-0.010, 0.077, 0.027, 0.020, 0.016, 0.0070, 1.12), # Ring
                    (-0.028, 0.070, 0.022, 0.016, 0.014, 0.0062, 1.20), # Pinky
                ]
                for fz, y_kn, l1, l2, l3, r0, cs in skel_fingers:
                    # Metacarpal bone from carpal wrist to knuckle
                    p_wr = Vector((0.0, 0.018, fz * 0.52))
                    p_kn = Vector((sx * 0.004, y_kn, fz))
                    tube(mb, [p_wr, p_wr.lerp(p_kn, 0.5), p_kn], [r0 * 1.15, r0 * 0.85, r0 * 1.35],
                         8, 'bone', C_BONE, (True, True), True, scols=[C_BONE_DARK, C_BONE], cap_poles=(False, True))
                    # Curled phalanx chain with subtle knuckle flares
                    a1 = radians(22.0 * cs)
                    a2 = radians(50.0 * cs)
                    a3 = radians(76.0 * cs)
                    p1 = p_kn + Vector((-sx * sin(a1) * l1, cos(a1) * l1, 0.0))
                    p2 = p1 + Vector((-sx * sin(a2) * l2, cos(a2) * l2, 0.0))
                    p3 = p2 + Vector((-sx * sin(a3) * l3, cos(a3) * l3, 0.0))
                    pts_f = [p_kn, p_kn.lerp(p1, 0.5), p1, p1.lerp(p2, 0.5), p2, p3]
                    rads_f = [r0 * 1.25, r0 * 0.78, r0 * 1.12, r0 * 0.72, r0 * 0.95, r0 * 0.55]
                    tube(mb, pts_f, rads_f, 8, 'bone', C_BONE_DARK, (True, True), True,
                         scols=[C_BONE, C_BONE_DARK, C_BONE, C_BONE_DARK, C_BONE_DARK], cap_poles=(False, True))
                # Articulated skeletal opposable thumb on +Z (radial) side
                th_pts = [
                    Vector((-sx * 0.004, 0.024, 0.022)),
                    Vector((-sx * 0.016, 0.056, 0.048)),
                    Vector((-sx * 0.028, 0.084, 0.058)),
                    Vector((-sx * 0.036, 0.104, 0.050)),
                ]
                tube(mb, th_pts, [0.0095, 0.0080, 0.0092, 0.0058], 8, 'bone', C_BONE,
                     (True, True), True, scols=[C_BONE_DARK, C_BONE, C_BONE_DARK], cap_poles=(False, True))

            else:
                # Tidecaller: gnarled elongated weathered-stone/bone mystic ritual hand + glowing aqua rings!
                palm_specs = [
                    (0.000, -0.001, 0.020, 0.028),
                    (0.030,  0.002, 0.022, 0.038),
                    (0.068,  0.002, 0.021, 0.042),
                    (0.094, -0.002, 0.016, 0.038),
                ]
                p_secs = []
                for py, pz, rx, rz in palm_specs:
                    p_secs.append([
                        Vector((cos(2 * pi * k / 12.0) * rx, py, pz + sin(2 * pi * k / 12.0) * rz))
                        for k in range(12)
                    ])
                loft(mb, p_secs, 'bone', C_MASK, True, (True, True), True,
                     scols=[C_MASK_DARK, C_MASK, C_MASK_HI], cap_poles=(True, True))

                # 4 slightly longer gnarled ritual fingers
                rfingers = [
                    ( 0.028, 0.088, 0.032, 0.024, 0.020, 0.0092, 0.90, True),  # Index (aqua ring)
                    ( 0.009, 0.092, 0.036, 0.026, 0.021, 0.0096, 0.98, False), # Middle
                    (-0.010, 0.088, 0.033, 0.024, 0.020, 0.0090, 1.06, True),  # Ring (aqua ring)
                    (-0.029, 0.082, 0.027, 0.020, 0.016, 0.0080, 1.14, False), # Pinky
                ]
                for fz, y0, l1, l2, l3, r0, cs, has_ring in rfingers:
                    a1 = radians(18.0 * cs)
                    a2 = radians(44.0 * cs)
                    a3 = radians(68.0 * cs)
                    p0 = Vector((sx * 0.003, y0, fz))
                    p1 = p0 + Vector((-sx * sin(a1) * l1, cos(a1) * l1, 0.0))
                    p2 = p1 + Vector((-sx * sin(a2) * l2, cos(a2) * l2, 0.0))
                    p3 = p2 + Vector((-sx * sin(a3) * l3, cos(a3) * l3, 0.0))
                    tube(mb, [p0, p1, p2, p3], [r0, r0 * 0.94, r0 * 0.78, r0 * 0.52], 8, 'bone', C_MASK_DARK,
                         (True, True), True, scols=[C_MASK, C_MASK_DARK, C_MASK_DARK], cap_poles=(False, True))
                    if has_ring:
                        rp = p0.lerp(p1, 0.52)
                        torus(mb, rp, r0 * 1.12, 0.0032, segs=12, psegs=6, mat='emissive_sea',
                              col=C_AQUA_GLOW, M=R('Z', sx * 18.0 * cs), smooth=True, shade_dir=False)

                # Gnarled opposable thumb on +Z side
                th_pts = [
                    Vector((-sx * 0.006, 0.036, 0.034)),
                    Vector((-sx * 0.020, 0.068, 0.054)),
                    Vector((-sx * 0.032, 0.096, 0.064)),
                    Vector((-sx * 0.038, 0.116, 0.056)),
                ]
                tube(mb, th_pts, [0.0125, 0.0110, 0.0096, 0.0068], 8, 'bone', C_MASK_DARK,
                     (True, True), True, scols=[C_MASK, C_MASK_DARK, C_MASK_DARK], cap_poles=(False, True))

                # Curved glowing aquamarine mystic glyph band across dorsal knuckles
                rune_pts = [
                    Vector((sx * 0.018, 0.076, -0.034)),
                    Vector((sx * 0.022, 0.080, -0.012)),
                    Vector((sx * 0.023, 0.082,  0.012)),
                    Vector((sx * 0.018, 0.078,  0.034)),
                ]
                tube(mb, rune_pts, 0.0055, 6, 'emissive_sea', C_AQUA_GLOW, (True, True), True,
                     shade_dir=False, cap_poles=(True, True))

# ---------------------------------------------------------------- 512x512 seamless high-relief PBR textures
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

def tile_worley(rs, w, h, gx, gy):
    """Fast seamless periodic grid-jittered Worley/Voronoi returning (f1, edge=f2-f1, cell_tone)."""
    px = rs.uniform(0.14, 0.86, (gy, gx)).astype(np.float32)
    py = rs.uniform(0.14, 0.86, (gy, gx)).astype(np.float32)
    ct = rs.rand(gy, gx).astype(np.float32)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    ux = xx * (gx / float(w))
    uy = yy * (gy / float(h))
    cx = np.floor(ux).astype(np.int32)
    cy = np.floor(uy).astype(np.int32)
    fx = ux - cx
    fy = uy - cy
    f1 = np.full((h, w), 1e9, dtype=np.float32)
    f2 = np.full((h, w), 1e9, dtype=np.float32)
    best_t = np.zeros((h, w), dtype=np.float32)
    for oy in (-1, 0, 1):
        ny = (cy + oy) % gy
        for ox in (-1, 0, 1):
            nx = (cx + ox) % gx
            dx = (ox + px[ny, nx]) - fx
            dy = (oy + py[ny, nx]) - fy
            d = np.sqrt(dx * dx + dy * dy)
            c1 = d < f1
            c2 = (~c1) & (d < f2)
            f2 = np.where(c1, f1, np.where(c2, d, f2))
            f1 = np.where(c1, d, f1)
            best_t = np.where(c1, ct[ny, nx], best_t)
    return f1, f2 - f1, best_t

def height_to_normal(height_map, strength=3.6):
    """Convert seamless scalar heightfield (0..1) into OpenGL (+Y up) tangent-space normal RGB (0..1)."""
    dh_dx = (np.roll(height_map, -1, axis=1) - np.roll(height_map, 1, axis=1)) * 0.5 * strength
    dh_dy = (np.roll(height_map, -1, axis=0) - np.roll(height_map, 1, axis=0)) * 0.5 * strength
    nx = -dh_dx
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
    img = bpy.data.images.new(name, w, h, alpha=False, is_data=non_color)
    if non_color:
        img.colorspace_settings.name = 'Non-Color'
    img.pixels.foreach_set(rgba.ravel())
    img.file_format = 'PNG'
    img.pack()
    return img

def synth_cloth_pbr(rs, size=512):
    """512x512 seamless crisp woven herringbone/twill wool-linen weave, yarn slub & organic fabric fold grain.
    Keeps neutral warm-white luminance (~0.94 sRGB) so live CharacterVisual tinting stays vivid and bright."""
    w = h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32) / float(size)
    # Crisp alternating herringbone + 2x2 diagonal twill rib with defined yarn crossover pockets
    chevron_band = np.where(((xx * 16.0) % 1.0) < 0.5, 1.0, -1.0)
    twill_diag = 0.5 + 0.5 * np.sin((xx * 68.0 * chevron_band + yy * 68.0) * 2.0 * pi)
    twill_rib = np.power(twill_diag, 0.78)
    warp = np.power(0.5 + 0.5 * np.sin(xx * 68.0 * 2.0 * pi), 0.85)
    weft = np.power(0.5 + 0.5 * np.sin(yy * 68.0 * 2.0 * pi), 0.85)
    yarn_cross = np.maximum(warp, weft)
    weave = 0.48 * twill_rib + 0.28 * yarn_cross + 0.12 * warp + 0.12 * weft
    # Tactile woven yarn slub along warp & weft
    slub_u = tile_noise(rs, w, h, 8, 56)
    slub_v = tile_noise(rs, w, h, 56, 8)
    slub = 0.55 * slub_u + 0.45 * slub_v
    # Painterly billowing fabric fold grain & soft diagonal drape creases
    folds = tile_fbm(rs, w, h, [(4, 6, 0.48), (8, 12, 0.32), (20, 24, 0.20)])
    drape = 0.5 + 0.5 * np.sin((xx * 3.0 - yy * 2.0 + (folds - 0.5) * 1.35) * 2.0 * pi)
    micro_fuzz = tile_noise(rs, w, h, 112, 112)

    hf = np.clip(0.26 + 0.42 * weave + 0.16 * slub + 0.22 * folds + 0.14 * drape + 0.06 * (micro_fuzz - 0.5), 0.0, 1.0)
    # Neutral warm-white luminance for bright vivid live CharacterVisual tinting
    val = 0.948 + 0.064 * (weave - 0.5) + 0.060 * (slub - 0.5) + 0.075 * (folds - 0.5) + 0.040 * (drape - 0.5)
    val = np.clip(val, 0.82, 1.0)
    albedo = np.stack([val, val * 0.992, val * 0.978], axis=-1)
    rough = np.clip(0.86 - 0.070 * (weave - 0.5) - 0.050 * (slub - 0.5) + 0.075 * (0.5 - folds) + 0.045 * (micro_fuzz - 0.5), 0.72, 0.96)
    normal = height_to_normal(hf, strength=3.8)
    return albedo, normal, rough

def synth_leather_pbr(rs, size=512):
    """512x512 seamless high-relief pebbled oiled saddle leather with worn flex creases & burnished highlights."""
    w = h = size
    f1_a, ed_a, ct_a = tile_worley(rs, w, h, 38, 38)
    f1_b, ed_b, _ = tile_worley(rs, w, h, 72, 72)
    pebble_dome = np.clip(1.0 - f1_a * 1.48, 0.0, 1.0) ** 0.72
    pebble_groove = np.clip(1.0 - ed_a / 0.15, 0.0, 1.0)
    micro_pebble = np.clip(1.0 - f1_b * 1.55, 0.0, 1.0) ** 0.85
    micro_pore = np.clip(1.0 - ed_b / 0.11, 0.0, 1.0)

    # Worn edge flex creases & supple oiled wear mottling
    macro = tile_fbm(rs, w, h, [(5, 5, 0.52), (12, 12, 0.30), (26, 26, 0.18)])
    crease_a = tile_ridged(rs, w, h, 6, 16)
    crease_b = tile_ridged(rs, w, h, 16, 8)
    crease_c = tile_ridged(rs, w, h, 24, 24)
    creases = np.clip((0.50 * crease_a + 0.35 * crease_b + 0.15 * crease_c - 0.58) * 3.3, 0.0, 1.0)
    fine = tile_noise(rs, w, h, 112, 112)

    hf = np.clip(0.36 + 0.42 * pebble_dome + 0.14 * micro_pebble + 0.14 * (macro - 0.5)
                 - 0.28 * pebble_groove - 0.10 * micro_pore - 0.34 * creases + 0.05 * (fine - 0.5), 0.0, 1.0)
    val = (0.890 + 0.115 * (pebble_dome - 0.5) + 0.080 * (ct_a - 0.5) + 0.12 * (macro - 0.5)
           - 0.13 * pebble_groove - 0.19 * creases)
    val = np.clip(val, 0.62, 1.0)
    albedo = np.stack([val * 1.015, val * 0.978, val * 0.928], axis=-1)
    # Tactile oiled leather specular contrast: burnished crowns (~0.38..0.48) vs matte pores/creases (~0.74..0.86)
    rough = np.clip(0.58 - 0.17 * pebble_dome - 0.11 * (macro - 0.5) + 0.14 * pebble_groove + 0.20 * creases + 0.05 * (fine - 0.5), 0.38, 0.86)
    normal = height_to_normal(hf, strength=4.8)
    return albedo, normal, rough

def synth_bone_pbr(rs, size=512):
    """512x512 seamless salted porous sea-weathered osteon bone grain, longitudinal fissures & chalky crevices."""
    w = h = size
    # Crisp longitudinal osteon fibrous striations & weathered bone fissures
    osteon = tile_fbm(rs, w, h, [(6, 32, 0.42), (16, 64, 0.34), (36, 112, 0.24)])
    fissure_r = tile_ridged(rs, w, h, 8, 44)
    fissures = np.clip((fissure_r - 0.66) * 3.8, 0.0, 1.0)
    macro = tile_fbm(rs, w, h, [(5, 5, 0.52), (12, 12, 0.32), (28, 28, 0.16)])
    # Angular Voronoi hairline stress cracks
    _, ed_cr, _ = tile_worley(rs, w, h, 8, 8)
    crack_wob = (tile_noise(rs, w, h, 28, 28) - 0.5) * 0.028
    crack_mask = np.clip((tile_noise(rs, w, h, 4, 4) - 0.32) * 3.2, 0.0, 1.0)
    cracks = np.clip(1.0 - np.clip(ed_cr + crack_wob, 0.0, 1.0) / 0.032, 0.0, 1.0) * crack_mask
    # Salted calcium micro-pores & sea-weathered pits
    fine = tile_noise(rs, w, h, 72, 72)
    fine2 = tile_noise(rs, w, h, 144, 144)
    pores = np.clip((0.32 - (0.60 * fine + 0.40 * fine2)) * 4.8, 0.0, 1.0)

    hf = np.clip(0.56 + 0.30 * (osteon - 0.5) + 0.18 * (macro - 0.5)
                 - 0.36 * fissures - 0.48 * cracks - 0.34 * pores, 0.0, 1.0)
    val = 0.868 + 0.16 * (osteon - 0.5) + 0.12 * (macro - 0.5) - 0.22 * fissures - 0.34 * cracks - 0.22 * pores
    val = np.clip(val, 0.48, 1.0)
    albedo = np.stack([val * 1.012, val * 0.996, val * 0.942], axis=-1)
    # Worn calcium shafts (~0.54) vs chalky weathered fissures & salted pores (~0.96)
    rough = np.clip(0.72 - 0.14 * (osteon - 0.5) - 0.08 * (macro - 0.5) + 0.16 * fissures + 0.20 * cracks + 0.18 * pores, 0.54, 0.96)
    normal = height_to_normal(hf, strength=5.4)
    return albedo, normal, rough

def synth_coral_pbr(rs, size=512):
    """512x512 seamless calcified reef pores, multi-scale corallite polyp craters & marine shell ridges."""
    w = h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32) / float(size)
    warp = tile_fbm(rs, w, h, [(5, 5, 0.52), (12, 12, 0.32), (26, 26, 0.16)])
    ridge_ph = (xx * 10.0 + yy * 4.0 + (warp - 0.5) * 2.4) * 2.0 * pi
    ridges = np.power(0.5 + 0.5 * np.sin(ridge_ph), 0.82)
    carved = 0.5 + 0.5 * np.sin((yy * 16.0 + (warp - 0.5) * 0.95) * 2.0 * pi)
    # Primary & secondary calcified reef polyp pores
    f1_p, ed_p, ct_p = tile_worley(rs, w, h, 28, 28)
    f1_s, _, _ = tile_worley(rs, w, h, 64, 64)
    polyp_pit = np.clip(1.0 - f1_p * 2.55, 0.0, 1.0) ** 1.35
    polyp_rim = np.clip(1.0 - np.abs(f1_p - 0.37) * 5.6, 0.0, 1.0)
    micro_pit = np.clip(1.0 - f1_s * 2.75, 0.0, 1.0) ** 1.4
    grit = tile_noise(rs, w, h, 96, 96)

    hf = np.clip(0.42 + 0.30 * ridges + 0.16 * carved + 0.24 * polyp_rim
                 - 0.40 * polyp_pit - 0.22 * micro_pit + 0.12 * (grit - 0.5), 0.0, 1.0)
    val = (0.855 + 0.14 * (ridges - 0.5) + 0.09 * (carved - 0.5) + 0.12 * polyp_rim
           + 0.07 * (ct_p - 0.5) - 0.26 * polyp_pit - 0.12 * micro_pit)
    val = np.clip(val, 0.50, 1.0)
    albedo = np.stack([val * 1.018, val * 0.988, val * 0.952], axis=-1)
    rough = np.clip(0.68 - 0.16 * ridges - 0.10 * polyp_rim + 0.24 * polyp_pit + 0.12 * micro_pit + 0.08 * (grit - 0.5), 0.46, 0.96)
    normal = height_to_normal(hf, strength=5.8)
    return albedo, normal, rough

def synth_skin_pbr(rs, size=512):
    """512x512 seamless warm painterly skin pore micro-grain & gentle oil-brushstroke warmth.
    High neutral luminance (~0.96 sRGB) keeps facial features warm, clean, and expressive."""
    w = h = size
    brush_a = tile_fbm(rs, w, h, [(6, 16, 0.52), (14, 34, 0.30), (30, 68, 0.18)])
    brush_b = tile_fbm(rs, w, h, [(16, 6, 0.52), (34, 14, 0.30), (68, 30, 0.18)])
    brush = 0.55 * brush_a + 0.45 * brush_b
    f1_pore, _, _ = tile_worley(rs, w, h, 60, 60)
    micro_pores = np.clip(1.0 - f1_pore * 2.2, 0.0, 1.0) * 0.45 + tile_noise(rs, w, h, 96, 96) * 0.55
    warmth = tile_fbm(rs, w, h, [(4, 4, 0.58), (10, 10, 0.42)])

    hf = np.clip(0.52 + 0.30 * (brush - 0.5) - 0.16 * (micro_pores - 0.5) + 0.12 * (warmth - 0.5), 0.0, 1.0)
    val = np.clip(0.964 + 0.052 * (brush - 0.5) + 0.044 * (warmth - 0.5) - 0.024 * (micro_pores - 0.5), 0.89, 1.0)
    albedo = np.stack([
        np.clip(val * (1.006 + 0.014 * (warmth - 0.5)), 0.0, 1.0),
        np.clip(val * 0.995, 0.0, 1.0),
        np.clip(val * (0.984 - 0.012 * (warmth - 0.5)), 0.0, 1.0),
    ], axis=-1)
    rough = np.clip(0.66 + 0.10 * (0.5 - brush) + 0.08 * (micro_pores - 0.5) + 0.05 * (warmth - 0.5), 0.52, 0.82)
    normal = height_to_normal(hf, strength=2.6)
    return albedo, normal, rough

def synth_hair_pbr(rs, size=512):
    """512x512 seamless silky combed directional hair & beard fiber strands with sheen bands."""
    w = h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32) / float(size)
    sway = (tile_fbm(rs, w, h, [(3, 6, 0.58), (6, 14, 0.42)]) - 0.5) * 1.45 + 0.20 * np.sin(xx * 2.0 * pi * 2.0)
    locks = np.power(0.5 + 0.5 * np.sin((yy * 28.0 + sway) * 2.0 * pi), 0.82)
    strands = np.power(0.5 + 0.5 * np.sin((yy * 92.0 + sway * 1.9) * 2.0 * pi), 0.85)
    fine_strands = 0.5 + 0.5 * np.sin((yy * 184.0 + sway * 2.4) * 2.0 * pi)
    fibers = tile_noise(rs, w, h, 5, 80) * 0.55 + tile_noise(rs, w, h, 10, 160) * 0.45
    sheen_band = tile_noise(rs, w, h, 4, 28)

    hf = np.clip(0.20 + 0.36 * locks + 0.26 * strands + 0.12 * fine_strands + 0.22 * fibers, 0.0, 1.0)
    val = 0.935 + 0.11 * (locks - 0.5) + 0.08 * (strands - 0.5) + 0.09 * (fibers - 0.5) + 0.055 * (sheen_band - 0.5)
    val = np.clip(val, 0.76, 1.0)
    albedo = np.stack([val * 1.006, val * 0.996, val * 0.984], axis=-1)
    # Silky hair sheen bands (~0.52) vs deeper fiber troughs (~0.92)
    rough = np.clip(0.74 - 0.16 * locks - 0.08 * strands + 0.10 * (0.5 - fibers) + 0.06 * (0.5 - sheen_band), 0.52, 0.92)
    normal = height_to_normal(hf, strength=4.5)
    return albedo, normal, rough

def synth_brass_pbr(rs, size=512):
    """512x512 seamless brushed & hammered antique marine brass patina (roughness 0.18..0.44)."""
    w = h = size
    brush = tile_noise(rs, w, h, 6, 108) * 0.58 + tile_noise(rs, w, h, 12, 192) * 0.42
    f1_h, ed_h, ct_h = tile_worley(rs, w, h, 14, 14)
    hammer_dish = np.clip(f1_h * 1.38, 0.0, 1.0) ** 1.25
    wear = tile_fbm(rs, w, h, [(8, 8, 0.50), (20, 20, 0.32), (48, 48, 0.18)])
    patina = np.clip((wear - 0.54) * 2.6, 0.0, 1.0)

    hf = np.clip(0.42 + 0.28 * hammer_dish + 0.18 * (brush - 0.5) + 0.14 * (wear - 0.5) - 0.14 * patina, 0.0, 1.0)
    val = 0.905 + 0.11 * (brush - 0.5) + 0.08 * (ct_h - 0.5) + 0.09 * (hammer_dish - 0.5) - 0.14 * patina
    val = np.clip(val, 0.68, 1.0)
    albedo = np.stack([
        np.clip(val * (1.016 - 0.08 * patina), 0.0, 1.0),
        np.clip(val * (0.992 + 0.015 * patina), 0.0, 1.0),
        np.clip(val * (0.935 + 0.045 * patina), 0.0, 1.0),
    ], axis=-1)
    rough = np.clip(0.24 + 0.07 * (0.5 - brush) + 0.05 * (0.5 - hammer_dish) + 0.15 * patina, 0.18, 0.44)
    normal = height_to_normal(hf, strength=3.3)
    return albedo, normal, rough

def synth_iron_pbr(rs, size=512):
    """512x512 seamless forged sea-pitted dark iron/steel with hammered micro-facets (roughness 0.34..0.62)."""
    w = h = size
    f1_h, ed_h, ct_h = tile_worley(rs, w, h, 18, 18)
    facet_rim = np.clip(1.0 - ed_h / 0.16, 0.0, 1.0)
    hammer_cup = np.clip(f1_h * 1.38, 0.0, 1.0) ** 1.15
    scale = tile_fbm(rs, w, h, [(8, 8, 0.45), (24, 24, 0.35), (56, 56, 0.20)])
    pit_n = tile_noise(rs, w, h, 52, 52) * 0.6 + tile_noise(rs, w, h, 108, 108) * 0.4
    pits = np.clip((0.31 - pit_n) * 4.4, 0.0, 1.0)
    rust = np.clip((scale - 0.56) * 2.8, 0.0, 1.0) * np.clip(pits * 0.8 + (1.0 - hammer_cup) * 0.45, 0.0, 1.0)

    hf = np.clip(0.40 + 0.30 * hammer_cup + 0.16 * facet_rim + 0.18 * (scale - 0.5) - 0.38 * pits, 0.0, 1.0)
    val = 0.84 + 0.15 * (hammer_cup - 0.5) + 0.10 * facet_rim + 0.10 * (ct_h - 0.5) - 0.22 * pits
    val = np.clip(val, 0.54, 1.0)
    albedo = np.stack([
        np.clip(val * (0.99 + 0.14 * rust), 0.0, 1.0),
        np.clip(val * (0.99 - 0.04 * rust), 0.0, 1.0),
        np.clip(val * (1.02 - 0.18 * rust), 0.0, 1.0),
    ], axis=-1)
    rough = np.clip(0.44 - 0.08 * facet_rim - 0.06 * (hammer_cup - 0.5) + 0.12 * pits + 0.11 * rust + 0.05 * (scale - 0.5), 0.34, 0.62)
    normal = height_to_normal(hf, strength=4.5)
    return albedo, normal, rough

MATS = {}

def make_materials():
    MATS.clear()
    rs = np.random.RandomState(SEED)

    def pack_pbr(family, triple):
        alb, nrm, rgh = triple
        return (
            make_image('char_%s_albedo' % family, alb, non_color=False),
            make_image('char_%s_normal' % family, nrm, non_color=True),
            make_image('char_%s_rough' % family, rgh, non_color=True),
        )

    pbr_cloth = pack_pbr('cloth', synth_cloth_pbr(rs))
    pbr_leather = pack_pbr('leather', synth_leather_pbr(rs))
    pbr_bone = pack_pbr('bone', synth_bone_pbr(rs))
    pbr_coral = pack_pbr('coral', synth_coral_pbr(rs))
    pbr_skin = pack_pbr('skin', synth_skin_pbr(rs))
    pbr_hair = pack_pbr('hair', synth_hair_pbr(rs))
    pbr_brass = pack_pbr('brass', synth_brass_pbr(rs))
    pbr_iron = pack_pbr('iron', synth_iron_pbr(rs))

    def mk(key, mat_name, pbr=None, rough=0.8, metal=0.0, emit=0.0,
           emit_col=(0.2, 1.0, 0.8, 1.0), two=False, normal_str=0.65):
        m = bpy.data.materials.new(mat_name)
        m.use_nodes = True
        nt = m.node_tree
        b = nt.nodes['Principled BSDF']
        b.inputs['Roughness'].default_value = rough
        b.inputs['Metallic'].default_value = metal
        ca = nt.nodes.new('ShaderNodeVertexColor')
        ca.layer_name = 'Color'
        if pbr is not None:
            img_alb, img_nrm, img_rgh = pbr
            t_alb = nt.nodes.new('ShaderNodeTexImage')
            t_alb.image = img_alb
            mx = nt.nodes.new('ShaderNodeMix')
            mx.data_type = 'RGBA'
            mx.blend_type = 'MULTIPLY'
            mx.inputs[0].default_value = 1.0
            nt.links.new(t_alb.outputs['Color'], mx.inputs[6])
            nt.links.new(ca.outputs['Color'], mx.inputs[7])
            nt.links.new(mx.outputs[2], b.inputs['Base Color'])

            t_nrm = nt.nodes.new('ShaderNodeTexImage')
            t_nrm.image = img_nrm
            nmap = nt.nodes.new('ShaderNodeNormalMap')
            nmap.space = 'TANGENT'
            nmap.inputs['Strength'].default_value = normal_str
            nt.links.new(t_nrm.outputs['Color'], nmap.inputs['Color'])
            nt.links.new(nmap.outputs['Normal'], b.inputs['Normal'])

            t_rgh = nt.nodes.new('ShaderNodeTexImage')
            t_rgh.image = img_rgh
            nt.links.new(t_rgh.outputs['Color'], b.inputs['Roughness'])
        else:
            nt.links.new(ca.outputs['Color'], b.inputs['Base Color'])
        if emit > 0.0:
            b.inputs['Emission Color'].default_value = emit_col
            b.inputs['Emission Strength'].default_value = emit
        m.use_backface_culling = not two
        MATS[key] = m

    mk('skin', 'mat_skin', pbr_skin, rough=0.66, normal_str=0.32)
    mk('cloth_base', 'mat_cloth_base', pbr_cloth, rough=0.86, two=True, normal_str=0.68)
    mk('cloth_primary', 'mat_cloth_primary', pbr_cloth, rough=0.85, two=True, normal_str=0.68)
    mk('cloth_secondary', 'mat_cloth_secondary', pbr_cloth, rough=0.84, two=True, normal_str=0.68)
    mk('leather', 'mat_leather', pbr_leather, rough=0.58, normal_str=0.80)
    mk('brass', 'mat_brass', pbr_brass, rough=0.28, metal=0.84, normal_str=0.54)
    mk('iron', 'mat_iron', pbr_iron, rough=0.46, metal=0.64, normal_str=0.72)
    mk('hair', 'mat_hair', pbr_hair, rough=0.74, normal_str=0.68)
    mk('bone', 'mat_bone', pbr_bone, rough=0.72, normal_str=0.84)
    mk('coral', 'mat_coral', pbr_coral, rough=0.66, two=True, normal_str=0.86)
    mk('emissive_sea', 'mat_emissive_sea', None, rough=0.25, emit=3.2, emit_col=(0.20, 1.0, 0.78, 1.0))
    mk('emissive_keg', 'mat_emissive_keg', None, rough=0.30, emit=3.0, emit_col=(1.0, 0.34, 0.08, 1.0))

def build_skinned(mb, arm_obj):
    # Fan-triangulate any n-gon (len(f) > 4) so MikkTSpace tangent export produces zero warnings!
    faces = []
    fmat = []
    fsm = []
    fcol = []
    fuv = []
    for fi, f in enumerate(mb.faces):
        m = mb.fmat[fi]
        sm = mb.fsm[fi]
        c = mb.fcol[fi]
        uv = mb.fuv[fi]
        if len(f) <= 4:
            faces.append(f)
            fmat.append(m)
            fsm.append(sm)
            fcol.append(c)
            fuv.append(uv)
        else:
            is_list_c = isinstance(c, list)
            for k in range(1, len(f) - 1):
                tri = (f[0], f[k], f[k + 1])
                if len({tri[0], tri[1], tri[2]}) < 3:
                    continue
                faces.append(tri)
                fmat.append(m)
                fsm.append(sm)
                fcol.append([c[0], c[k], c[k + 1]] if is_list_c else c)
                fuv.append([uv[0], uv[k], uv[k + 1]])

    me = bpy.data.meshes.new(mb.name)
    me.from_pydata([conv(v) for v in mb.verts], [], faces)
    names = sorted(set(fmat))
    for n in names:
        me.materials.append(MATS[n])
    mi = {n: i for i, n in enumerate(names)}
    uvl = me.uv_layers.new(name='UVMap')
    ca = me.color_attributes.new('Color', 'FLOAT_COLOR', 'CORNER')
    uvs = []
    cols = []
    for fi, f in enumerate(faces):
        c = fcol[fi]
        for k in range(len(f)):
            uvs.extend(fuv[fi][k])
            cc = c[k] if isinstance(c, list) else c
            cols.extend((cc[0], cc[1], cc[2], 1.0))
    uvl.data.foreach_set('uv', uvs)
    ca.data.foreach_set('color', cols)
    me.polygons.foreach_set('material_index', [mi[m] for m in fmat])
    me.polygons.foreach_set('use_smooth', fsm)
    me.update()

    ob = bpy.data.objects.new(mb.name, me)
    bpy.context.scene.collection.objects.link(ob)

    # Create vertex groups only for bones used by this mesh
    used = sorted({b for wd in mb.weights for b in wd})
    vgs = {b: ob.vertex_groups.new(name=b) for b in used}
    for vi, wd in enumerate(mb.weights):
        for b, w in wd.items():
            if w > 1e-4:
                vgs[b].add([vi], w, 'REPLACE')

    ob.parent = arm_obj
    mod = ob.modifiers.new(name='Armature', type='ARMATURE')
    mod.object = arm_obj
    return ob, sum(len(f) - 2 for f in faces)

# ================================================================ 1. PIRATE
def _build_buccaneer_boot_vamp(mb, fx, sx, col_upper, col_sole, segs=14):
    """Smooth sculpted buccaneer boot sole, heel block, stitched welt & rounded toe vamp planted at y = 0.0."""
    # 1. Thick rounded stitched sole planted FLAT at y = 0.000 .. 0.028
    sole_mod = lambda a: (1.0 + 0.06 * cos(2.0 * a), 0.0, 0.0)
    sole_secs = [
        ring_ellipse((fx, 0.000, -0.056), 0.058, 0.130, segs, front_bias=0.06, sq=0.30, mod_fn=sole_mod),
        ring_ellipse((fx, 0.012, -0.056), 0.062, 0.134, segs, front_bias=0.06, sq=0.28, mod_fn=sole_mod),
        ring_ellipse((fx, 0.028, -0.056), 0.061, 0.132, segs, front_bias=0.05, sq=0.28, mod_fn=sole_mod),
        ring_ellipse((fx, 0.032, -0.054), 0.055, 0.124, segs, front_bias=0.04, sq=0.25),
    ]
    loft(mb, sole_secs, 'leather', col_sole, True, (True, True), True,
         scols=[mul(col_sole, 0.82), col_sole, mul(col_sole, 1.15), col_sole])

    # Defined thick heel block under rear foot (y = 0.000 .. 0.040)
    heel_secs = [
        ring_ellipse((fx, 0.000, 0.040), 0.053, 0.048, 12, sq=0.35),
        ring_ellipse((fx, 0.022, 0.040), 0.055, 0.050, 12, sq=0.32),
        ring_ellipse((fx, 0.040, 0.038), 0.052, 0.048, 12, sq=0.30),
    ]
    loft(mb, heel_secs, 'leather', mul(col_sole, 0.90), True, (True, True), True)

    # 2. Smooth sculpted leather boot vamp sweeping along -Z from heel -> arch -> rounded slightly-upturned toe
    # Build vertical elliptical cross-sections oriented perpendicular to Z
    vamp_specs = [
        # (z, y_center, rx, ry)
        ( 0.068, 0.072, 0.048, 0.044),
        ( 0.025, 0.080, 0.056, 0.052),
        (-0.028, 0.076, 0.058, 0.048),
        (-0.082, 0.068, 0.056, 0.040),
        (-0.135, 0.060, 0.051, 0.033),
        (-0.172, 0.056, 0.040, 0.024),
        (-0.188, 0.057, 0.022, 0.014),
    ]
    vamp_secs = []
    for vz, vy, rx, ry in vamp_specs:
        ring = []
        for k in range(segs):
            a = 2.0 * pi * k / segs
            ca, sa = cos(a), sin(a)
            # Flatter bottom seated cleanly on sole, gently domed upper instep
            y_off = sa * ry if sa >= 0 else sa * ry * 0.72
            ring.append(Vector((fx + ca * rx, max(0.022, vy + y_off), vz)))
        vamp_secs.append(ring)
    loft(mb, vamp_secs, 'leather', col_upper, True, (True, True), True,
         scols=[mul(col_upper, 0.88), col_upper, col_upper, mul(col_upper, 1.05),
                mul(col_upper, 1.08), mul(col_upper, 1.10)],
         cap_poles=(True, True))

def _build_pirate_boot_and_leg(mb, side):
    sx = -1.0 if side == "L" else 1.0
    wl = w_leg(side)
    with wctx(mb, wl):
        fx = sx * 0.118
        _build_buccaneer_boot_vamp(mb, fx, sx, C_LEATHER, C_LEATHER_DARK, segs=14)

        # Smooth 14-sided lower boot shaft with subtle leather ankle-bend crease rings (y = 0.07 .. 0.35)
        shaft = [
            ring_ellipse((fx, 0.072, 0.015), 0.056, 0.062, 14, sq=0.22),
            ring_ellipse((fx, 0.125, 0.013), 0.059, 0.065, 14, sq=0.20),
            ring_ellipse((fx, 0.155, 0.012), 0.056, 0.061, 14, sq=0.18),  # ankle crease dip
            ring_ellipse((fx, 0.195, 0.010), 0.062, 0.067, 14, sq=0.20),
            ring_ellipse((fx, 0.275, 0.004), 0.068, 0.073, 14, sq=0.20),
            ring_ellipse((fx, 0.345, 0.000), 0.074, 0.078, 14, sq=0.20),
        ]
        loft(mb, shaft, 'leather', C_LEATHER, True, (False, True), True,
             scols=[C_LEATHER_DARK, C_LEATHER, mul(C_LEATHER, 0.92), C_LEATHER, mul(C_LEATHER, 1.06)])

        # Leather ankle strap band & sculpted brass side buckle on outer ankle!
        strap = [
            ring_ellipse((fx, 0.112, 0.010), 0.062, 0.068, 14, sq=0.22),
            ring_ellipse((fx, 0.142, 0.010), 0.063, 0.069, 14, sq=0.22),
        ]
        loft(mb, strap, 'leather', C_LEATHER_DARK, True, (True, True), True)
        # Open brass buckle frame + tongue on outer boot side
        bx = fx + sx * 0.062
        with xf(mb, T(bx, 0.127, 0.002) @ R('Y', -sx * 8)):
            for dy, dz, sy_b, sz_b in ((0.014, 0.0, 0.007, 0.036), (-0.014, 0.0, 0.007, 0.036),
                                       (0.0, 0.015, 0.034, 0.007), (0.0, -0.015, 0.034, 0.007),
                                       (0.0, 0.0, 0.024, 0.005)):
                cbox(mb, (0.0, dy, dz), (0.010, sy_b, sz_b), 'brass', C_BRASS, 0.002)

        # Iconic folded turn-down leather buccaneer boot cuff with sculpted side notch & rolled top lip
        def cuff_dip(a):
            # Subtle swashbuckler V-dip at outer side
            side_a = 0.0 if sx > 0 else pi
            d = cos(a - side_a)
            return (1.0 + 0.04 * max(0.0, d), -0.018 * max(0.0, d) ** 2, 0.0)

        cuff = [
            ring_ellipse((fx, 0.285, 0.002), 0.082, 0.086, 14, sq=0.25, mod_fn=cuff_dip),
            ring_ellipse((fx, 0.315, 0.000), 0.090, 0.094, 14, sq=0.25, mod_fn=cuff_dip),
            ring_ellipse((fx, 0.375, -0.005), 0.093, 0.097, 14, sq=0.25),
            ring_ellipse((fx, 0.414, -0.008), 0.087, 0.091, 14, sq=0.22),
            ring_ellipse((fx, 0.420, -0.006), 0.078, 0.082, 14, sq=0.20),
            ring_ellipse((fx, 0.398, -0.004), 0.068, 0.072, 14, sq=0.18),
        ]
        loft(mb, cuff, 'leather', C_LEATHER_LIGHT, True, (True, False), True,
             scols=[mul(C_LEATHER_LIGHT, 0.84), C_LEATHER_LIGHT, mul(C_LEATHER_LIGHT, 1.08),
                    mul(C_LEATHER_LIGHT, 1.04), mul(C_LEATHER_DARK, 0.90)])

        # 14-sided smooth knee-tapered sailor trousers with soft fabric crease rings!
        def fabric_fold(amp, phase):
            return lambda a: (1.0 + amp * cos(3.0 * a + phase), 0.0, 0.0)

        leg = [
            ring_ellipse((fx, 0.390, 0.000), 0.066, 0.068, 14, sq=0.16),
            ring_ellipse((fx, 0.425, -0.006), 0.084, 0.088, 14, sq=0.18, mod_fn=fabric_fold(0.04, 0.4)),  # bloused above boot
            ring_ellipse((fx, 0.455, -0.011), 0.079, 0.082, 14, sq=0.16),                                  # knee joint loop
            ring_ellipse((fx, 0.500, -0.008), 0.092, 0.095, 14, sq=0.18, mod_fn=fabric_fold(0.035, 1.2)), # soft crease fold
            ring_ellipse((fx, 0.585, -0.004), 0.095, 0.099, 14, sq=0.18),
            ring_ellipse((fx, 0.700, 0.000), 0.098, 0.103, 14, sq=0.20, mod_fn=fabric_fold(0.025, 2.0)),
            ring_ellipse((fx, 0.815, 0.000), 0.099, 0.105, 14, sq=0.20),
            ring_ellipse((sx * 0.095, 0.895, 0.000), 0.093, 0.102, 14, sq=0.22),
        ]
        loft(mb, leg, 'cloth_base', C_TROUSER, True, (False, True), True,
             scols=[mul(C_TROUSER, 0.84), mul(C_TROUSER, 1.04), mul(C_TROUSER, 0.94),
                    mul(C_TROUSER, 1.06), C_TROUSER, mul(C_TROUSER, 1.02), mul(C_TROUSER, 0.94)])

def _build_pirate_arm_and_hand(mb, side):
    sx = -1.0 if side == "L" else 1.0
    wa = w_arm(side)
    sh, ua, el, wr, ft = [Vector(q) for q in _arm_pts(sx)]
    with wctx(mb, wa):
        # 14-sided smooth puffed billowing pirate shirt sleeve with elbow crease & wrist gather!
        path = [
            ua.lerp(sh, 0.28),
            ua,
            ua.lerp(el, 0.30),
            ua.lerp(el, 0.65),
            ua.lerp(el, 0.90),
            el,
            el.lerp(wr, 0.18),
            el.lerp(wr, 0.52),
            el.lerp(wr, 0.76),
            el.lerp(wr, 0.88),
            wr,
        ]
        rads = [0.070, 0.078, 0.075, 0.068, 0.060, 0.056, 0.065, 0.074, 0.068, 0.044, 0.036]
        scols = [
            mul(C_SHIRT, 0.90), C_SHIRT, mul(C_SHIRT, 1.05), mul(C_SHIRT, 0.98),
            mul(C_SHIRT, 0.92), mul(C_SHIRT, 0.94), C_SHIRT, mul(C_SHIRT, 1.06),
            mul(C_SHIRT, 0.96), mul(C_SHIRT, 0.86),
        ]
        tube(mb, path, rads, 14, 'cloth_base', C_SHIRT, (True, True), True, scols=scols)

        # Buckled leather wrist bracer (14-sided smooth cuff + twin raised strap ridges + brass buckle!)
        br_p0 = el.lerp(wr, 0.78)
        br_p1 = el.lerp(wr, 0.96)
        tube(mb, [br_p0, br_p0.lerp(br_p1, 0.5), br_p1], [0.056, 0.053, 0.051], 14,
             'leather', C_LEATHER, (True, True), True, scols=[C_LEATHER_DARK, C_LEATHER])
        for bt in (0.81, 0.91):
            p_a = el.lerp(wr, bt)
            p_b = el.lerp(wr, bt + 0.035)
            tube(mb, [p_a, p_b], [0.059, 0.058], 14, 'leather', C_LEATHER_DARK, (True, True), True)
        # Small gleaming brass bracer buckle on dorsal/outer side of wrist
        f_dir = (wr - el).normalized()
        out_v = Vector((sx, 0.25, 0.0)).normalized()
        out_v = (out_v - f_dir * out_v.dot(f_dir)).normalized()
        b_pos = el.lerp(wr, 0.86) + out_v * 0.058
        ellipsoid(mb, b_pos, (0.010, 0.012, 0.012), 'brass', C_BRASS, segs=8, rings=4, smooth=True)

        # Gathered ruffled linen wrist cuff flaring gently between bracer and sculpted hand!
        rf_secs = []
        u_dir = (wr - el).normalized()
        ref = Vector((0, 0, -1))
        ru = (ref - u_dir * ref.dot(u_dir)).normalized()
        rv = u_dir.cross(ru).normalized()
        for t_r, r_base, f_amp in ((0.95, 0.039, 0.002), (0.985, 0.048, 0.005), (1.02, 0.052, 0.006)):
            cp = el.lerp(wr, t_r)
            ring = []
            for k in range(14):
                a = 2.0 * pi * k / 14.0
                rr = r_base + f_amp * sin(7.0 * a)
                ring.append(cp + ru * (rr * cos(a)) + rv * (rr * sin(a)))
            rf_secs.append(ring)
        loft(mb, rf_secs, 'cloth_base', mul(C_SHIRT, 1.04), True, (False, False), True,
             scols=[mul(C_SHIRT, 0.94), mul(C_SHIRT, 1.05)])

    # Sculpted anatomical pirate hand (weighted 100% to Hand_side)
    sculpt_hand(mb, wr, ft, side, style='pirate')

def _build_pirate_head(mb):
    with wctx(mb, "Head"):
        # 16-sided smooth anatomically sculpted stylized pirate head (y = 1.482 .. 1.734, facing -Z)
        def face_mod(y_val):
            def fn(a):
                # a = -pi/2 is front (-Z), a = +pi/2 is back (+Z), a = 0/+pi are right/left (+X/-X)
                front = max(0.0, -sin(a))
                ca = cos(a)
                # Cheekbones around ±42 deg from front (-Z)
                cheek_ang = exp(-((abs(abs(a + pi * 0.5) - 0.72)) ** 2) / 0.14) if sin(a) < 0.2 else 0.0
                # Eye socket mild recess around ±26 deg from front
                eye_rec = exp(-((abs(abs(a + pi * 0.5) - 0.42)) ** 2) / 0.07) if sin(a) < 0.0 else 0.0
                rm = 1.0
                dz = 0.0
                if 1.500 <= y_val <= 1.542:
                    # Sculpted smooth rounded chin & tapering jawline
                    dz -= 0.013 * (front ** 2.0)
                    rm += 0.035 * (abs(ca) ** 2) * (1.0 - front)
                elif 1.555 <= y_val <= 1.595:
                    # Organic sculpted cheekbones (built directly into head loft)
                    rm += 0.068 * cheek_ang
                    dz -= 0.005 * cheek_ang
                elif 1.596 <= y_val <= 1.622:
                    # Gentle recessed orbital eye plane + slight temple hollow
                    rm -= 0.050 * eye_rec
                elif 1.625 <= y_val <= 1.650:
                    # Bold Sea-of-Thieves sculpted brow arch overhang
                    dz -= 0.013 * (front ** 1.5)
                return (rm, 0.0, dz)
            return fn

        head_specs = [
            (1.482,  0.005, 0.052, 0.056, 0.00, 0.15, C_SKIN_DARK),
            (1.504, -0.010, 0.067, 0.083, 0.14, 0.28, C_SKIN_WARM),  # rounded chin & lower jaw
            (1.532, -0.010, 0.084, 0.094, 0.10, 0.28, C_SKIN_WARM),  # jaw / mouth plane
            (1.572, -0.008, 0.094, 0.102, 0.08, 0.20, C_SKIN),       # organic cheekbones
            (1.608, -0.006, 0.097, 0.106, 0.04, 0.18, C_SKIN),       # eye orbital plane
            (1.636, -0.006, 0.099, 0.109, 0.08, 0.20, C_SKIN),       # sculpted brow
            (1.678,  0.003, 0.098, 0.110, 0.00, 0.16, mul(C_SKIN, 1.04)), # forehead / cranium
            (1.716,  0.010, 0.076, 0.086, 0.00, 0.12, C_SKIN),       # crown
            (1.734,  0.012, 0.036, 0.042, 0.00, 0.08, C_SKIN),       # top dome (~1.734 m)
        ]
        head_secs = [
            ring_ellipse((0, yv, zv), rx, rz, 16, front_bias=fb, sq=sq, mod_fn=face_mod(yv))
            for yv, zv, rx, rz, fb, sq, _ in head_specs
        ]
        head_cols = [c for *_, c in head_specs]
        loft(mb, head_secs, 'skin', C_SKIN, True, (True, True), True,
             scols=head_cols, cap_poles=(True, True))

        # Smooth sculpted pirate nose: expressive bridge + rounded tip + subtle nostril wings (ZERO boxes!)
        nose_pts = [
            (0.0, 1.628, -0.102),  # glabella root between brows
            (0.0, 1.608, -0.116),  # upper bridge
            (0.0, 1.586, -0.130),  # mid bridge
            (0.0, 1.573, -0.138),  # rounded nose tip
            (0.0, 1.563, -0.118),  # philtrum base tuck
        ]
        nose_rads = [(0.013, 0.012), (0.012, 0.014), (0.014, 0.016), (0.0165, 0.0155), (0.010, 0.009)]
        tube(mb, nose_pts, nose_rads, 10, 'skin', C_SKIN_WARM, (True, True), True,
             scols=[C_SKIN, C_SKIN_WARM, mul(C_SKIN_WARM, 1.05), C_SKIN_CHEEK], cap_poles=(True, True))
        # Rounded nasal tip bulb + twin subtle nostril wings (alae)
        ellipsoid(mb, (0.0, 1.573, -0.137), (0.016, 0.014, 0.015), 'skin', C_SKIN_CHEEK, segs=10, rings=6, smooth=True)
        for sx in (-1.0, 1.0):
            ellipsoid(mb, (sx * 0.0145, 1.568, -0.125), (0.010, 0.008, 0.010),
                      'skin', C_SKIN_WARM, segs=8, rings=5, smooth=True)

        # Expressive sculpted eyes (rounded eyeballs + dark iris + eyelid folds + decisive pirate brows) & ears!
        for sx in (-1.0, 1.0):
            # Rounded smooth eyeball sclera
            ellipsoid(mb, (sx * 0.040, 1.606, -0.097), (0.0170, 0.0125, 0.0130),
                      'skin', C_EYE_WHITE, segs=12, rings=7, M=R('Y', -sx * 14), smooth=True, shade_dir=False)
            # Smooth dark iris & pupil nestled cleanly on sclera front
            ellipsoid(mb, (sx * 0.040, 1.606, -0.107), (0.0085, 0.0088, 0.0048),
                      'skin', C_EYE_IRIS, segs=10, rings=5, M=R('Y', -sx * 14), smooth=True, shade_dir=False)
            ellipsoid(mb, (sx * 0.040, 1.606, -0.111), (0.0048, 0.0050, 0.0028),
                      'skin', C_EYE_DARK, segs=8, rings=4, M=R('Y', -sx * 14), smooth=True, shade_dir=False)

            # Sculpted upper & lower eyelid folds curving naturally around the eyeball
            up_lid = [
                (sx * 0.023, 1.608, -0.105),
                (sx * 0.036, 1.617, -0.109),
                (sx * 0.050, 1.616, -0.105),
                (sx * 0.059, 1.607, -0.095),
            ]
            tube(mb, up_lid, [0.0036, 0.0052, 0.0050, 0.0034], 8, 'skin', C_SKIN_WARM,
                 (True, True), True, cap_poles=(True, True))
            lo_lid = [
                (sx * 0.025, 1.600, -0.105),
                (sx * 0.040, 1.595, -0.107),
                (sx * 0.056, 1.600, -0.096),
            ]
            tube(mb, lo_lid, [0.0028, 0.0038, 0.0026], 6, 'skin', C_SKIN_DARK,
                 (True, True), True, cap_poles=(True, True))

            # Decisive sculpted roguish pirate eyebrow (low confident angle with jaunty cocked right brow!)
            brow_lift = 0.005 if sx > 0 else -0.003
            brow_pts = [
                (sx * 0.015, 1.622, -0.114),
                (sx * 0.035, 1.628 + brow_lift, -0.115),
                (sx * 0.056, 1.630 + brow_lift * 0.8, -0.107),
                (sx * 0.070, 1.624 + brow_lift * 0.2, -0.092),
            ]
            tube(mb, brow_pts, [0.0095, 0.0102, 0.0084, 0.0048], 8, 'hair', C_HAIR,
                 (True, True), True, scols=[C_HAIR_DARK, C_HAIR, C_HAIR_LIGHT], cap_poles=(True, True))

            # Smooth contoured sculpted ear (curved outer helix + recessed ear cup + soft earlobe!)
            with xf(mb, T(sx * 0.098, 1.594, 0.006) @ R('Y', sx * 22)):
                # Inner ear cup backing
                ellipsoid(mb, (-sx * 0.003, 0.000, 0.000), (0.008, 0.023, 0.015),
                          'skin', C_SKIN_DARK, segs=10, rings=5, smooth=True)
                # Curved C-shaped outer helix rim wrapping top -> back -> earlobe
                helix = [
                    (sx * 0.001,  0.016, -0.008),
                    (sx * 0.008,  0.027,  0.000),
                    (sx * 0.011,  0.016,  0.013),
                    (sx * 0.010, -0.004,  0.014),
                    (sx * 0.007, -0.021,  0.006),
                    (sx * 0.002, -0.025, -0.005),
                ]
                tube(mb, helix, [0.0060, 0.0072, 0.0074, 0.0068, 0.0076, 0.0070], 8,
                     'skin', C_SKIN_WARM, (True, True), True, cap_poles=(True, True))
                # Rounded earlobe
                ellipsoid(mb, (sx * 0.004, -0.024, -0.001), (0.0075, 0.0095, 0.0085),
                          'skin', C_SKIN_WARM, segs=8, rings=5, smooth=True)

        # Genuine sculpted circular GOLD HOOP EARRING (smooth torus ring hanging from left earlobe!)
        torus(mb, (-0.106, 1.556, 0.004), major_r=0.0155, minor_r=0.0036, segs=18, psegs=10,
              mat='brass', col=C_BRASS, M=R('Y', -16) @ R('X', 90), smooth=True)

        # Expressive sculpted pirate mouth (clean subtle confident smirk along smooth jaw plane)
        lip_up = [
            (-0.026, 1.544, -0.094),
            (-0.010, 1.546, -0.102),
            ( 0.000, 1.545, -0.104),
            ( 0.011, 1.547, -0.102),
            ( 0.028, 1.549, -0.093), # subtle confident smirk lift on right corner!
        ]
        tube(mb, lip_up, [0.0026, 0.0042, 0.0040, 0.0042, 0.0026], 8, 'skin', C_SKIN_LIP,
             (True, True), True, cap_poles=(True, True))
        lip_lo = [
            (-0.022, 1.541, -0.094),
            ( 0.000, 1.538, -0.102),
            ( 0.024, 1.544, -0.093),
        ]
        tube(mb, lip_lo, [0.0028, 0.0048, 0.0028], 8, 'skin', C_SKIN_WARM,
             (True, True), True, cap_poles=(True, True))

        # Expressive sculpted tousled hair cap (14-sided smooth) + sweeping hair locks & sideburns!
        # Radius kept snugly fitted to cranium so Hat_Tricorne / Hat_Bandana / Hat_Cap wrap cleanly without clipping
        def hair_wave(a):
            return (1.0 + 0.03 * cos(5.0 * a), 0.0, 0.0)
        hair_secs = [
            ring_ellipse((0, 1.584, 0.028), 0.092, 0.092, 14, sq=0.18, mod_fn=hair_wave),
            ring_ellipse((0, 1.652, 0.020), 0.104, 0.111, 14, sq=0.18, mod_fn=hair_wave),
            ring_ellipse((0, 1.708, 0.015), 0.091, 0.098, 14, sq=0.16),
            ring_ellipse((0, 1.737, 0.013), 0.044, 0.048, 14, sq=0.12),
        ]
        loft(mb, hair_secs, 'hair', C_HAIR, True, (True, True), True,
             scols=[C_HAIR_DARK, C_HAIR, C_HAIR_LIGHT, C_HAIR], cap_poles=(True, True))

        # Carved sweeping tousled nape & temple hair locks (staying cleanly under hat brim line!)
        nape_locks = [
            # (x0, x1, x2, z_off, r0, col)
            (-0.068, -0.082, -0.072, 0.088, 0.022, C_HAIR),
            (-0.036, -0.042, -0.034, 0.104, 0.024, C_HAIR_LIGHT),
            ( 0.000,  0.006,  0.014, 0.110, 0.025, C_HAIR),
            ( 0.038,  0.044,  0.036, 0.104, 0.024, C_HAIR_LIGHT),
            ( 0.068,  0.080,  0.070, 0.088, 0.022, C_HAIR),
        ]
        for x0, x1, x2, z0, r0, hc in nape_locks:
            pts = [
                (x0, 1.622, z0 * 0.90),
                (x1, 1.570, z0 * 1.06),
                (x2, 1.518, z0 * 0.98),
                (x2 * 0.95, 1.486, z0 * 0.84),
            ]
            tube(mb, pts, [(r0, r0 * 0.65), (r0 * 0.95, r0 * 0.62), (r0 * 0.68, r0 * 0.45), (r0 * 0.25, r0 * 0.20)],
                 8, 'hair', hc, (True, True), True, scols=[hc, mul(hc, 0.92), C_HAIR_DARK], cap_poles=(False, True))

        # Sweeping sculpted sideburns & rogue temple wisps framing the face
        for sx in (-1.0, 1.0):
            sb_pts = [
                (sx * 0.094, 1.632, -0.022),
                (sx * 0.096, 1.594, -0.028),
                (sx * 0.090, 1.554, -0.036),
                (sx * 0.080, 1.530, -0.046),
            ]
            tube(mb, sb_pts, [(0.013, 0.018), (0.012, 0.017), (0.010, 0.013), (0.005, 0.007)],
                 8, 'hair', C_HAIR, (True, True), True, scols=[C_HAIR_LIGHT, C_HAIR, C_HAIR_DARK], cap_poles=(False, True))
            # Swept temple hair lock tucking over ear top
            tl_pts = [
                (sx * 0.080, 1.646, -0.050),
                (sx * 0.100, 1.630, -0.012),
                (sx * 0.096, 1.592,  0.036),
                (sx * 0.082, 1.550,  0.068),
            ]
            tube(mb, tl_pts, [0.013, 0.015, 0.013, 0.007], 8, 'hair', C_HAIR_LIGHT,
                 (True, True), True, scols=[C_HAIR_LIGHT, C_HAIR, C_HAIR_DARK], cap_poles=(True, True))

def build_pirate_meshes(arm_obj):
    meshes = []

    # ---- 1. Body (always visible)
    body = MB('Body', seed=10)
    with wctx(body, w_torso):
        # 14-sided smooth tailored pelvis & broad barrel-chested pirate shirt trunk (y = 0.835 .. 1.425)
        pelvis = [
            ring_ellipse((0, 0.835, 0.0), 0.165, 0.120, 14, sq=0.28),
            ring_ellipse((0, 0.905, 0.0), 0.184, 0.132, 14, sq=0.28),
            ring_ellipse((0, 0.965, 0.0), 0.174, 0.126, 14, sq=0.25),
        ]
        loft(body, pelvis, 'cloth_base', C_TROUSER, True, (True, False), True,
             scols=[mul(C_TROUSER, 0.86), C_TROUSER, mul(C_TROUSER, 0.95)])

        def shirt_crease(amp, ph):
            return lambda a: (1.0 + amp * cos(4.0 * a + ph), 0.0, 0.0)

        shirt_trunk = [
            ring_ellipse((0, 0.955, 0.000), 0.172, 0.126, 14, sq=0.22),
            ring_ellipse((0, 1.025, -0.004), 0.182, 0.134, 14, sq=0.22, mod_fn=shirt_crease(0.022, 0.5)), # bloused above belt
            ring_ellipse((0, 1.095, -0.006), 0.188, 0.138, 14, sq=0.22),
            ring_ellipse((0, 1.185, -0.010), 0.212, 0.150, 14, front_bias=0.10, sq=0.26),
            ring_ellipse((0, 1.290, -0.008), 0.232, 0.156, 14, front_bias=0.12, sq=0.30),
            ring_ellipse((0, 1.385,  0.004), 0.218, 0.134, 14, sq=0.32),
            ring_ellipse((0, 1.422,  0.006), 0.104, 0.088, 14, sq=0.20),
        ]
        loft(body, shirt_trunk, 'cloth_base', C_SHIRT, True, (False, True), True,
             scols=[mul(C_SHIRT, 0.88), mul(C_SHIRT, 0.98), C_SHIRT, C_SHIRT,
                    mul(C_SHIRT, 1.05), mul(C_SHIRT, 0.98), mul(C_SHIRT, 0.92)])

        # Tanned chest V-triangle & smooth sculpted folded open pirate shirt collar!
        chest_v = [
            ring_ellipse((0, 1.305, -0.108), 0.022, 0.020, 10),
            ring_ellipse((0, 1.355, -0.095), 0.052, 0.036, 10),
            ring_ellipse((0, 1.400, -0.058), 0.066, 0.052, 10),
        ]
        loft(body, chest_v, 'skin', C_SKIN_WARM, True, (True, False), True,
             scols=[C_SKIN_DARK, C_SKIN_WARM, C_SKIN])

        for sx in (-1.0, 1.0):
            # Tailored flat folded open shirt collar lapel hugging chest & neck cleanly
            col_pts = [
                (sx * 0.022, 1.318, -0.132),
                (sx * 0.062, 1.362, -0.116),
                (sx * 0.082, 1.404, -0.056),
                (sx * 0.064, 1.418,  0.036),
                (0.0,        1.422,  0.072),
            ]
            tube(body, col_pts, [(0.008, 0.004), (0.015, 0.005), (0.017, 0.006), (0.014, 0.005), (0.012, 0.005)],
                 8, 'cloth_base', mul(C_SHIRT, 1.04), (True, True), True, cap_poles=(True, True))

        # 14-sided smooth tanned sailor neck column (y = 1.37 .. 1.505)
        neck = [
            ring_ellipse((0, 1.370, -0.012), 0.074, 0.074, 14, sq=0.14),
            ring_ellipse((0, 1.420, -0.006), 0.063, 0.065, 14, sq=0.12),
            ring_ellipse((0, 1.465, -0.002), 0.060, 0.063, 14, sq=0.12),
            ring_ellipse((0, 1.505,  0.000), 0.059, 0.063, 14, sq=0.12),
        ]
        loft(body, neck, 'skin', C_SKIN_WARM, True, (False, False), True,
             scols=[C_SKIN_DARK, C_SKIN_WARM, C_SKIN, C_SKIN_WARM])

    for side in ("L", "R"):
        _build_pirate_boot_and_leg(body, side)
        _build_pirate_arm_and_hand(body, side)
    _build_pirate_head(body)
    meshes.append(build_skinned(body, arm_obj))

    # ---- 2. Hat_Tricorne (28-seg smooth curled 3-cornered brim + 16-seg crown + gold braid + brooch + multi-vane ostrich plume!)
    hat_tri = MB('Hat_Tricorne', seed=20)
    with wctx(hat_tri, "Head"):
        with xf(hat_tri, T(0, 1.695, 0.004) @ R('X', -7)):
            # 16-sided smooth weathered leather crown dome
            crown = [
                ring_ellipse((0, -0.016, 0.000), 0.114, 0.124, 16, sq=0.18),
                ring_ellipse((0,  0.032, 0.000), 0.113, 0.122, 16, sq=0.18),
                ring_ellipse((0,  0.082, 0.002), 0.105, 0.113, 16, sq=0.16),
                ring_ellipse((0,  0.122, 0.005), 0.084, 0.092, 16, sq=0.14),
                ring_ellipse((0,  0.142, 0.006), 0.038, 0.042, 16, sq=0.10),
            ]
            loft(hat_tri, crown, 'leather', C_LEATHER_DARK, True, (True, True), True,
                 scols=[C_LEATHER_DARK, C_LEATHER, C_LEATHER, mul(C_LEATHER, 1.08), mul(C_LEATHER, 1.04)],
                 cap_poles=(False, True))
            # Leather hatband around base of crown
            hband = [
                ring_ellipse((0, -0.006, 0.0), 0.117, 0.127, 16, sq=0.18),
                ring_ellipse((0,  0.022, 0.0), 0.116, 0.126, 16, sq=0.18),
            ]
            loft(hat_tri, hband, 'leather', C_LEATHER_LIGHT, True, (False, False), True)

            # 28-segment smooth curled 3-cornered brim (solid 4-ring profile: crown -> underside -> rolled edge -> inner face!)
            segs = 28
            in_b, mid_b, out_b, out_t, in_t = [], [], [], [], []
            braid_pts = []
            for k in range(segs):
                a = 2.0 * pi * k / segs
                lobe = 0.5 + 0.5 * cos(3.0 * (a + pi * 0.5))
                r_in = 0.110
                r_out = 0.176 + 0.100 * (lobe ** 1.35)
                y_up = 0.096 + 0.056 * (1.0 - 0.54 * lobe)
                ca, sa = cos(a), sin(a)
                r_mid = 0.5 * (r_in + r_out)
                in_b.append(Vector((ca * r_in, -0.008, sa * r_in * 1.08)))
                mid_b.append(Vector((ca * r_mid, y_up * 0.28 - 0.010, sa * r_mid * 1.08)))
                out_b.append(Vector((ca * r_out, y_up - 0.018, sa * r_out * 1.08)))
                out_t.append(Vector((ca * (r_out - 0.010), y_up + 0.007, sa * (r_out - 0.010) * 1.08)))
                in_t.append(Vector((ca * (r_in + 0.006), 0.014, sa * (r_in + 0.006) * 1.08)))
                braid_pts.append(Vector((ca * (r_out - 0.002), y_up - 0.002, sa * (r_out - 0.002) * 1.08)))
            loft(hat_tri, [in_b, mid_b, out_b, out_t, in_t], 'leather', C_LEATHER, True, (False, False), True,
                 scols=[C_LEATHER_DARK, C_LEATHER_DARK, C_LEATHER, mul(C_LEATHER, 1.08), C_LEATHER_DARK])
            # Gleaming smooth gold braid cord hugging entire 28-seg tricorne brim rim!
            braid_pts.append(braid_pts[0])
            tube(hat_tri, braid_pts, 0.0082, 8, 'brass', C_BRASS, (False, False), True)

            # Ornate brass brooch rosette clasping the feather plume on the left side!
            with xf(hat_tri, T(-0.114, 0.056, -0.044) @ R('Y', -62)):
                ellipsoid(hat_tri, (0, 0, 0), (0.016, 0.022, 0.011), 'brass', mul(C_BRASS, 1.08), segs=12, rings=6, smooth=True)
                torus(hat_tri, (0, 0, -0.002), 0.018, 0.0045, segs=14, psegs=6, mat='brass', col=C_BRASS_DARK,
                      M=R('X', 90), smooth=True)

            # Lush multi-vane sculpted curving ostrich feather plume sweeping boldly up & back (max height ~1.96 m!)
            plume_spine = [
                (-0.114, 0.056, -0.040),
                (-0.156, 0.112, -0.008),
                (-0.188, 0.174,  0.042),
                (-0.202, 0.222,  0.104),
                (-0.194, 0.242,  0.168),
                (-0.172, 0.232,  0.222),
                (-0.152, 0.204,  0.256),
            ]
            feather_plume(
                hat_tri, plume_spine,
                w_left=[0.010, 0.036, 0.052, 0.056, 0.046, 0.028, 0.009],
                w_right=[0.010, 0.028, 0.042, 0.046, 0.038, 0.022, 0.008],
                thick=[0.006, 0.010, 0.011, 0.010, 0.008, 0.006, 0.003],
                mat_vane='cloth_secondary', mat_quill='brass',
                col_base=C_TINT_LO, col_tip=C_TINT_HI,
                notches=[(0.36, -1, 0.44), (0.62, 1, 0.40), (0.76, -1, 0.46)],
            )
            # Secondary curling plume frond tucked alongside for lush multi-vane depth
            plume2 = [
                (-0.114, 0.052, -0.036),
                (-0.152, 0.096,  0.014),
                (-0.168, 0.144,  0.076),
                (-0.162, 0.172,  0.140),
                (-0.144, 0.164,  0.186),
            ]
            feather_plume(
                hat_tri, plume2,
                w_left=[0.008, 0.024, 0.034, 0.026, 0.008],
                w_right=[0.008, 0.022, 0.028, 0.022, 0.007],
                thick=[0.005, 0.008, 0.008, 0.006, 0.003],
                mat_vane='cloth_secondary', mat_quill='brass',
                col_base=C_TINT_MID, col_tip=C_TINT_HI,
                notches=[(0.55, -1, 0.40)],
            )
    meshes.append(build_skinned(hat_tri, arm_obj))

    # ---- 3. Hat_Bandana (16-seg smooth fabric folds + realistic rear kerchief knot & waving tails)
    hat_ban = MB('Hat_Bandana', seed=21)
    with wctx(hat_ban, "Head"):
        def ban_fold(a):
            return (1.0 + 0.018 * sin(6.0 * a + 0.5), 0.003 * cos(4.0 * a), 0.0)
        dome = [
            ring_ellipse((0, 1.646, 0.004), 0.109, 0.120, 16, front_bias=0.05, sq=0.20, mod_fn=ban_fold),
            ring_ellipse((0, 1.682, 0.008), 0.114, 0.124, 16, sq=0.18, mod_fn=ban_fold),
            ring_ellipse((0, 1.720, 0.012), 0.098, 0.106, 16, sq=0.16),
            ring_ellipse((0, 1.748, 0.014), 0.048, 0.052, 16, sq=0.12),
        ]
        loft(hat_ban, dome, 'cloth_secondary', C_TINT_HI, True, (True, True), True,
             scols=[C_TINT_LO, C_TINT_HI, C_TINT_MID, C_TINT_HI], cap_poles=(False, True))
        # Thick folded & creased forehead brow wrap band
        band = [
            ring_ellipse((0, 1.630, 0.004), 0.112, 0.124, 16, front_bias=0.06, sq=0.22),
            ring_ellipse((0, 1.646, 0.005), 0.118, 0.129, 16, front_bias=0.05, sq=0.22, mod_fn=ban_fold),
            ring_ellipse((0, 1.665, 0.006), 0.115, 0.126, 16, front_bias=0.04, sq=0.22),
        ]
        loft(hat_ban, band, 'cloth_secondary', C_TINT_MID, True, (True, True), True,
             scols=[C_TINT_LO, C_TINT_HI, C_TINT_MID])
        # Realistic sculpted double-lobe kerchief knot at back-right
        ellipsoid(hat_ban, (0.062, 1.648, 0.118), (0.026, 0.022, 0.022), 'cloth_secondary', C_TINT_HI,
                  segs=10, rings=6, M=R('Z', 24), smooth=True)
        ellipsoid(hat_ban, (0.074, 1.642, 0.122), (0.020, 0.019, 0.018), 'cloth_secondary', C_TINT_MID,
                  segs=10, rings=6, M=R('Z', -20), smooth=True)
        # Two smooth flowing tapered kerchief tails
        tube(hat_ban, [
            (0.072, 1.642, 0.124), (0.092, 1.600, 0.148),
            (0.112, 1.548, 0.164), (0.122, 1.498, 0.166),
        ], [(0.018, 0.008), (0.028, 0.009), (0.026, 0.008), (0.008, 0.004)],
             10, 'cloth_secondary', C_TINT_HI, (True, True), True,
             scols=[C_TINT_MID, C_TINT_HI, C_TINT_LO], cap_poles=(False, True))
        tube(hat_ban, [
            (0.056, 1.640, 0.125), (0.044, 1.592, 0.154),
            (0.032, 1.540, 0.172), (0.020, 1.500, 0.180),
        ], [(0.016, 0.007), (0.024, 0.008), (0.022, 0.007), (0.007, 0.003)],
             10, 'cloth_secondary', C_TINT_MID, (True, True), True,
             scols=[C_TINT_LO, C_TINT_MID, C_TINT_LO], cap_poles=(False, True))
    meshes.append(build_skinned(hat_ban, arm_obj))

    # ---- 4. Hat_Cap (16-seg smooth slouchy sailor beanie + ribbed knit cuff + braided top tassel!)
    hat_cap = MB('Hat_Cap', seed=22)
    with wctx(hat_cap, "Head"):
        # Ribbed knit rolled beanie cuff (24-seg periodic rib fluting!)
        def knit_rib(a):
            return (1.0 + 0.026 * cos(12.0 * a), 0.0, 0.0)
        cuff = [
            ring_ellipse((0, 1.642, 0.004), 0.112, 0.122, 24, sq=0.18, mod_fn=knit_rib),
            ring_ellipse((0, 1.662, 0.006), 0.124, 0.134, 24, sq=0.18, mod_fn=knit_rib),
            ring_ellipse((0, 1.686, 0.008), 0.123, 0.133, 24, sq=0.18, mod_fn=knit_rib),
            ring_ellipse((0, 1.700, 0.009), 0.115, 0.125, 24, sq=0.16),
        ]
        loft(hat_cap, cuff, 'cloth_secondary', C_TINT_HI, True, (True, False), True,
             scols=[C_TINT_LO, C_TINT_HI, C_TINT_HI, C_TINT_MID])
        # 16-sided smooth slouchy knit crown tipping gently backward
        crown = [
            ring_ellipse((0, 1.692, 0.008), 0.114, 0.122, 16, sq=0.16),
            ring_ellipse((0, 1.728, 0.016), 0.112, 0.119, 16, sq=0.15),
            ring_ellipse((0, 1.762, 0.030), 0.094, 0.100, 16, sq=0.14),
            ring_ellipse((0, 1.788, 0.048), 0.064, 0.070, 16, sq=0.12),
            ring_ellipse((0, 1.802, 0.066), 0.026, 0.030, 16, sq=0.10),
        ]
        loft(hat_cap, crown, 'cloth_primary', C_TINT_HI, True, (False, True), True,
             scols=[C_TINT_LO, C_TINT_MID, C_TINT_HI, C_TINT_HI, C_TINT_MID], cap_poles=(False, True))
        # Braided tassel cord & textured knitted pom on slouch tip
        torus(hat_cap, (0.0, 1.801, 0.068), 0.018, 0.0055, segs=14, psegs=6,
              mat='cloth_secondary', col=C_TINT_MID, M=R('X', 34), smooth=True)
        ellipsoid(hat_cap, (0.0, 1.810, 0.076), (0.025, 0.023, 0.025), 'cloth_secondary', C_TINT_HI,
                  segs=12, rings=6, smooth=True)
    meshes.append(build_skinned(hat_cap, arm_obj))

    # ---- 5. Coat_Captain (16-seg smooth flared split frock coat + rolled hem + folded lapels + braided epaulettes + brass buttons + diagonal cross-baldric!)
    coat = MB('Coat_Captain', seed=23)
    with wctx(coat, w_coat_skirt):
        def coat_arc(y, rx, rz, gap_deg=34.0, flare_z=0.0, ripple=0.0):
            pts = []
            a0 = radians(-90.0 + gap_deg)
            a1 = radians(270.0 - gap_deg)
            n = 17
            for k in range(n):
                u = k / float(n - 1)
                a = a0 + (a1 - a0) * u
                ca, sa = cos(a), sin(a)
                # Natural hanging drapery ripples along lower flared coat skirt
                wave = 1.0 + ripple * sin(u * pi * 5.0)
                pts.append(Vector((ca * rx * wave, y, sa * rz * wave + (flare_z if sa > 0 else 0.0))))
            return pts

        # Fits cleanly OUTSIDE Belt_Sash at sides/back while leaving front belt buckle open!
        coat_secs = [
            coat_arc(0.49, 0.292, 0.228, 44.0, 0.048, 0.045),
            coat_arc(0.64, 0.264, 0.204, 38.0, 0.026, 0.030),
            coat_arc(0.80, 0.242, 0.184, 34.0, 0.010, 0.015),
            coat_arc(0.95, 0.232, 0.176, 32.0, 0.000, 0.000),
            coat_arc(1.10, 0.228, 0.168, 32.0, 0.000, 0.000),
            coat_arc(1.26, 0.252, 0.175, 34.0, 0.000, 0.000),
            coat_arc(1.37, 0.246, 0.162, 38.0, 0.000, 0.000),
            coat_arc(1.41, 0.218, 0.142, 44.0, 0.000, 0.000),
        ]
        loft(coat, coat_secs, 'cloth_primary', C_TINT_HI, closed=False, caps=(False, False), smooth=True,
             scols=[C_TINT_LO, C_TINT_MID, C_TINT_MID, C_TINT_LO, C_TINT_MID, C_TINT_HI, C_TINT_HI, C_TINT_MID])

        # Crisp rolled contrasting hem trim cord tracing bottom hem & both front coat openings!
        hem_rim = coat_secs[0]
        tube(coat, hem_rim, 0.012, 8, 'cloth_secondary', C_TINT_HI, (True, True), True, cap_poles=(True, True))
        # Left & right front opening trim pipes + brass piping
        for edge_idx in (0, -1):
            edge_pts = [sec[edge_idx] for sec in coat_secs]
            tube(coat, edge_pts, 0.011, 8, 'cloth_secondary', C_TINT_HI, (True, True), True, cap_poles=(True, True))

        # Sculpted folded notched captain lapels hugging the chest curvature!
        for sx in (-1.0, 1.0):
            lap_secs = []
            for ly, lw, lz_in, lz_out in (
                (1.04, 0.036, -0.148, -0.162),
                (1.14, 0.056, -0.156, -0.172),
                (1.25, 0.072, -0.164, -0.180),
                (1.34, 0.068, -0.150, -0.166),
                (1.40, 0.046, -0.122, -0.136),
            ):
                x0 = sx * 0.118
                x1 = sx * (0.118 + lw)
                lap_secs.append([
                    Vector((x0, ly, lz_in)),
                    Vector((x1, ly, lz_out + 0.016)),
                    Vector((x1, ly, lz_out)),
                    Vector((x0, ly, lz_in - 0.014)),
                ])
            loft(coat, lap_secs, 'cloth_secondary', C_TINT_HI, True, (True, True), True,
                 scols=[C_TINT_MID, C_TINT_HI, C_TINT_HI, C_TINT_HI, C_TINT_MID])

            # Row of gleaming rounded brass coat buttons down front chest
            for bi in range(5):
                by = 1.03 + bi * 0.068
                bz = -0.176 - (0.008 if bi in (2, 3) else 0.0)
                ellipsoid(coat, (sx * 0.146, by, bz), (0.012, 0.012, 0.0075), 'brass', C_BRASS,
                          segs=10, rings=5, smooth=True)

            # Sculpted twin braided brass-tasseled captain epaulettes!
            with wctx(coat, "Shoulder_" + ("L" if sx < 0 else "R")):
                ep_secs = []
                for ei, (ex, ey, ez, ew) in enumerate((
                    (sx * 0.125, 1.425, 0.006, 0.044),
                    (sx * 0.185, 1.434, 0.007, 0.052),
                    (sx * 0.245, 1.424, 0.008, 0.058),
                    (sx * 0.278, 1.404, 0.008, 0.054),
                )):
                    ep_secs.append([
                        Vector((ex, ey - 0.010, ez - ew)),
                        Vector((ex, ey + 0.014, ez - ew * 0.85)),
                        Vector((ex, ey + 0.020, ez)),
                        Vector((ex, ey + 0.014, ez + ew * 0.85)),
                        Vector((ex, ey - 0.010, ez + ew)),
                    ])
                loft(coat, ep_secs, 'cloth_secondary', C_TINT_HI, True, (True, True), True,
                     scols=[C_TINT_MID, C_TINT_HI, C_TINT_HI, C_TINT_MID])
                # Braided gold rim cord outlining the epaulette pad
                rim_ep = [
                    (sx * 0.128, 1.434, -0.042),
                    (sx * 0.245, 1.434, -0.055),
                    (sx * 0.282, 1.410, -0.036),
                    (sx * 0.286, 1.404,  0.008),
                    (sx * 0.282, 1.410,  0.052),
                    (sx * 0.245, 1.434,  0.068),
                    (sx * 0.128, 1.434,  0.054),
                ]
                tube(coat, rim_ep, 0.0085, 8, 'brass', C_BRASS, (True, True), True)
                # Epaulette inner brass button
                ellipsoid(coat, (sx * 0.148, 1.445, 0.007), (0.011, 0.007, 0.011), 'brass', C_BRASS,
                          segs=10, rings=5, smooth=True)
                # Sculpted hanging gold bullion fringe tassels along outer shoulder curve!
                for ti in range(7):
                    tz = -0.044 + ti * (0.096 / 6.0)
                    tx0 = sx * 0.282
                    ty0 = 1.402 - 0.008 * abs(tz / 0.048)
                    tube(coat, [(tx0, ty0, tz), (tx0 + sx * 0.012, ty0 - 0.034, tz), (tx0 + sx * 0.016, ty0 - 0.062, tz)],
                         [0.0075, 0.0068, 0.0045], 6, 'brass', C_BRASS if ti % 2 == 0 else C_BRASS_DARK,
                         (True, True), True, cap_poles=(False, True))

        # High sweeping 16-segment smooth captain's standing collar
        collar = [
            coat_arc(1.385, 0.140, 0.116, 56.0, 0.0),
            coat_arc(1.435, 0.152, 0.128, 58.0, 0.012),
            coat_arc(1.478, 0.162, 0.138, 62.0, 0.024),
        ]
        loft(coat, collar, 'cloth_secondary', C_TINT_HI, closed=False, caps=(False, False), smooth=True,
             scols=[C_TINT_MID, C_TINT_HI, C_TINT_HI])
        tube(coat, collar[-1], 0.0065, 8, 'brass', C_BRASS, (True, True), True)

        # Diagonal leather cross-baldric with gleaming brass buckle! (weighted smoothly to torso)
        with wctx(coat, w_torso):
            bal_loop = [
                # Left shoulder -> across chest -> right hip -> across back -> left shoulder
                (-0.145, 1.425, -0.020),
                (-0.085, 1.335, -0.176),
                ( 0.015, 1.215, -0.194),
                ( 0.125, 1.090, -0.186),
                ( 0.218, 0.975, -0.120),
                ( 0.244, 0.945,  0.000),
                ( 0.210, 0.990,  0.145),
                ( 0.095, 1.135,  0.184),
                (-0.035, 1.285,  0.184),
                (-0.130, 1.395,  0.112),
                (-0.145, 1.425, -0.020),
            ]
            tube(coat, bal_loop, (0.032, 0.0085), 8, 'leather', C_LEATHER_DARK, (False, False), True)
            # Gleaming sculpted brass baldric buckle on front-left chest
            with xf(coat, T(-0.055, 1.298, -0.194) @ R('Z', -42) @ R('Y', 12)):
                for dx, dy, sx_b, sy_b in ((0, 0.028, 0.068, 0.012), (0, -0.028, 0.068, 0.012),
                                           (-0.030, 0, 0.012, 0.064), (0.030, 0, 0.012, 0.064),
                                           (0, 0, 0.009, 0.054)):
                    cbox(coat, (dx, dy, 0.0), (sx_b, sy_b, 0.015), 'brass', C_BRASS, 0.003)

    # Smooth 14-sided coat sleeves + wide flared captain cuffs with double gold braid & cuff buttons!
    for side in ("L", "R"):
        sx = -1.0 if side == "L" else 1.0
        sh, ua, el, wr, _ = [Vector(q) for q in _arm_pts(sx)]
        with wctx(coat, w_arm(side)):
            sl_path = [ua.lerp(sh, 0.22), ua, ua.lerp(el, 0.48), el, el.lerp(wr, 0.45), el.lerp(wr, 0.70)]
            sl_rads = [0.086, 0.092, 0.083, 0.075, 0.082, 0.088]
            tube(coat, sl_path, sl_rads, 14, 'cloth_primary', C_TINT_HI, (True, False), True,
                 scols=[C_TINT_MID, C_TINT_HI, C_TINT_MID, C_TINT_MID, C_TINT_HI])
            # Massive smooth flared turn-back captain cuff
            cf_path = [el.lerp(wr, 0.58), el.lerp(wr, 0.70), el.lerp(wr, 0.84), el.lerp(wr, 0.93)]
            tube(coat, cf_path, [0.094, 0.105, 0.106, 0.098], 14, 'cloth_secondary', C_TINT_HI,
                 (True, True), True, scols=[C_TINT_MID, C_TINT_HI, C_TINT_HI])
            # Twin gleaming gold braid rings around captain's cuff
            for bt in (0.64, 0.74):
                tube(coat, [el.lerp(wr, bt), el.lerp(wr, bt + 0.032)], [0.109, 0.109], 14,
                     'brass', C_BRASS, (False, False), True)
    meshes.append(build_skinned(coat, arm_obj))

    # ---- 6. Vest_Crew (16-seg smooth tailored sailor waistcoat + beveled brass buttons + stitched pocket welts + back cinch!)
    vest = MB('Vest_Crew', seed=24)
    with wctx(vest, w_torso):
        def vest_arc(y, rx, rz, gap_deg=18.0, front_bias=0.14):
            pts = []
            a0 = radians(-90.0 + gap_deg)
            a1 = radians(270.0 - gap_deg)
            n = 17
            for k in range(n):
                a = a0 + (a1 - a0) * k / float(n - 1)
                ca, sa = cos(a), sin(a)
                sx_s = (1.0 if ca >= 0 else -1.0) * (abs(ca) ** 0.78)
                sz_s = (1.0 if sa >= 0 else -1.0) * (abs(sa) ** 0.78)
                z_val = sz_s * rz * (1.0 + front_bias if sz_s < 0 else 1.0)
                pts.append(Vector((sx_s * rx, y, z_val)))
            return pts

        v_secs = [
            vest_arc(0.92, 0.206, 0.155, 16.0),
            vest_arc(1.03, 0.214, 0.162, 15.0),
            vest_arc(1.14, 0.236, 0.178, 16.0),
            vest_arc(1.26, 0.258, 0.186, 20.0),
            vest_arc(1.36, 0.254, 0.174, 24.0),
            vest_arc(1.41, 0.228, 0.152, 30.0),
        ]
        loft(vest, v_secs, 'cloth_primary', C_TINT_HI, closed=False, caps=(False, False), smooth=True,
             scols=[C_TINT_LO, C_TINT_MID, C_TINT_HI, C_TINT_HI, C_TINT_HI, C_TINT_MID])

        # Contoured smooth front leather binding trim along both vest openings + bottom hem piping
        for edge_idx in (0, -1):
            tube(vest, [sec[edge_idx] for sec in v_secs], 0.012, 8, 'leather', C_LEATHER, (True, True), True)
        tube(vest, v_secs[0], 0.009, 8, 'leather', C_LEATHER_DARK, (True, True), True)

        for sx in (-1.0, 1.0):
            # Gleaming domed brass waistcoat buttons
            for bi in range(5):
                by = 1.02 + bi * 0.068
                bz = -0.184 - (0.022 if bi in (2, 3) else 0.008)
                ellipsoid(vest, (sx * 0.088, by, bz), (0.011, 0.011, 0.007), 'brass', C_BRASS,
                          segs=10, rings=5, smooth=True)
            # Stitched welt pockets hugging lower sides of waistcoat
            pk_pts = [
                (sx * 0.105, 1.085, -0.182),
                (sx * 0.152, 1.082, -0.162),
                (sx * 0.194, 1.086, -0.122),
            ]
            tube(vest, pk_pts, (0.011, 0.007), 8, 'leather', C_LEATHER_LIGHT, (True, True), True, cap_poles=(True, True))
            # Smooth flat tailored shoulder vest straps hugging trapezius cleanly
            sh_pts = [
                (sx * 0.145, 1.384, -0.105),
                (sx * 0.180, 1.408, -0.015),
                (sx * 0.172, 1.404,  0.082),
                (sx * 0.145, 1.370,  0.140),
            ]
            tube(vest, sh_pts, (0.036, 0.008), 10, 'cloth_primary', C_TINT_HI, (True, True), True, cap_poles=(True, True))

        # Tailored waistcoat back cinch strap & small brass cinch buckle on lower back (+Z)!
        cinch_pts = [
            (-0.145, 1.055, 0.148),
            (-0.070, 1.055, 0.172),
            ( 0.000, 1.055, 0.178),
            ( 0.070, 1.055, 0.172),
            ( 0.145, 1.055, 0.148),
        ]
        tube(vest, cinch_pts, (0.014, 0.006), 8, 'leather', C_LEATHER_DARK, (True, True), True)
        cbox(vest, (0.0, 1.055, 0.182), (0.036, 0.028, 0.012), 'brass', C_BRASS, 0.003)
    meshes.append(build_skinned(vest, arm_obj))

    # ---- 7. Beard_Full (lush multi-layered sculpted full pirate beard + curled handlebar mustache + braided brass-ringed locks!)
    beard = MB('Beard_Full', seed=25)
    with wctx(beard, "Head"):
        # Smooth 14-sided core sculpted beard volume hugging jaw & chin
        def beard_flute(a):
            return (1.0 + 0.055 * cos(6.0 * a), 0.0, 0.0)
        b_secs = [
            ring_ellipse((0, 1.568, -0.056), 0.102, 0.066, 14, sq=0.30, mod_fn=beard_flute),
            ring_ellipse((0, 1.515, -0.086), 0.104, 0.068, 14, sq=0.32, mod_fn=beard_flute),
            ring_ellipse((0, 1.456, -0.102), 0.088, 0.056, 14, sq=0.30, mod_fn=beard_flute),
            ring_ellipse((0, 1.400, -0.108), 0.056, 0.036, 14, sq=0.25),
            ring_ellipse((0, 1.362, -0.103), 0.022, 0.016, 14, sq=0.18),
        ]
        loft(beard, b_secs, 'hair', C_HAIR, True, (True, True), True,
             scols=[C_HAIR_LIGHT, C_HAIR, C_HAIR, mul(C_HAIR, 0.88), C_HAIR_DARK], cap_poles=(True, True))

        # Multi-layered overlapping sculpted flowing beard locks!
        beard_locks = [
            ( 0.000, -0.118, 0.024, 1.344, C_HAIR_LIGHT),
            (-0.034, -0.114, 0.022, 1.362, C_HAIR),
            ( 0.034, -0.114, 0.022, 1.362, C_HAIR),
            (-0.068, -0.096, 0.020, 1.404, C_HAIR_LIGHT),
            ( 0.068, -0.096, 0.020, 1.404, C_HAIR_LIGHT),
            (-0.092, -0.064, 0.017, 1.462, C_HAIR),
            ( 0.092, -0.064, 0.017, 1.462, C_HAIR),
        ]
        for bx, bz, br, y_end, bc in beard_locks:
            pts = [
                (bx * 0.90, 1.545, bz * 0.84),
                (bx * 1.04, 1.485, bz * 1.06),
                (bx * 0.98, 0.5 * (1.485 + y_end), bz * 1.08),
                (bx * 0.88, y_end, bz * 0.96),
            ]
            tube(beard, pts, [br, br * 0.95, br * 0.68, br * 0.24], 8, 'hair', bc,
                 (True, True), True, scols=[bc, mul(bc, 0.92), C_HAIR_DARK], cap_poles=(False, True))

        # Lush sweeping curled handlebar mustache!
        for sx in (-1.0, 1.0):
            must_pts = [
                (sx * 0.008, 1.556, -0.118),
                (sx * 0.038, 1.554, -0.125),
                (sx * 0.074, 1.542, -0.116),
                (sx * 0.106, 1.532, -0.096),
                (sx * 0.124, 1.544, -0.080),
                (sx * 0.120, 1.560, -0.074), # jaunty upturned handlebar curl!
            ]
            tube(beard, must_pts, [0.020, 0.024, 0.021, 0.015, 0.010, 0.005], 10, 'hair', C_HAIR_LIGHT,
                 (True, True), True, scols=[C_HAIR, C_HAIR_LIGHT, C_HAIR_LIGHT, C_HAIR, C_HAIR_DARK],
                 cap_poles=(True, True))
            # Twin braided side beard tails cinched with genuine smooth brass torus rings!
            braid_pts = [
                (sx * 0.058, 1.462, -0.116),
                (sx * 0.066, 1.422, -0.122),
                (sx * 0.072, 1.380, -0.118),
            ]
            tube(beard, braid_pts, [0.016, 0.015, 0.009], 8, 'hair', C_HAIR_LIGHT,
                 (True, True), True, cap_poles=(False, True))
            torus(beard, (sx * 0.067, 1.412, -0.121), 0.0165, 0.0048, segs=14, psegs=8,
                  mat='brass', col=C_BRASS, M=R('Z', sx * 8), smooth=True)
    meshes.append(build_skinned(beard, arm_obj))

    # ---- 8. Eyepatch (smooth contoured domed leather cup + 24-seg snug strap)
    patch = MB('Eyepatch', seed=26)
    with wctx(patch, "Head"):
        with xf(patch, T(-0.042, 1.608, -0.112) @ R('Y', 18) @ R('X', 4)):
            # Smooth contoured oval domed eyepatch cup (ZERO blocky bricks!)
            ellipsoid(patch, (0.0, 0.0, 0.0), (0.026, 0.022, 0.011), 'leather', C_LEATHER_DARK,
                      segs=14, rings=7, smooth=True)
            # Subtle raised stitched leather rim
            torus(patch, (0.0, 0.0, 0.002), 0.0235, 0.0042, segs=16, psegs=6,
                  mat='leather', col=C_LEATHER, M=R('X', 90), smooth=True)
        # Smooth 24-segment diagonal leather strap hugging sculpted head cleanly
        strap_pts = []
        segs = 24
        for k in range(segs + 1):
            a = -pi * 0.62 + 2.0 * pi * k / segs
            ca, sa = cos(a), sin(a)
            y = 1.630 + 0.032 * ca - 0.014 * sa
            r_x = 0.107 if sa < 0 else 0.109
            r_z = 0.116 if sa < 0 else 0.120
            strap_pts.append((ca * r_x, y, sa * r_z))
        tube(patch, strap_pts, (0.0075, 0.0045), 8, 'leather', C_LEATHER_DARK, (False, False), True)
    meshes.append(build_skinned(patch, arm_obj))

    # ---- 9. Belt_Sash (16-seg smooth folded waist sash + waving tail + heavy leather belt + ornate beveled brass buckle!)
    sash = MB('Belt_Sash', seed=27)
    with wctx(sash, w_belt_sash):
        def sash_wrap(ph):
            return lambda a: (1.0 + 0.018 * sin(3.0 * a + ph), 0.005 * sin(2.0 * a + ph), 0.0)
        s_secs = [
            ring_ellipse((0, 0.892,  0.000), 0.214, 0.160, 16, sq=0.30),
            ring_ellipse((0, 0.928, -0.004), 0.224, 0.168, 16, sq=0.30, mod_fn=sash_wrap(0.4)),
            ring_ellipse((0, 0.968, -0.004), 0.220, 0.164, 16, sq=0.28, mod_fn=sash_wrap(1.6)),
            ring_ellipse((0, 1.008, -0.004), 0.212, 0.158, 16, sq=0.26, mod_fn=sash_wrap(2.8)),
            ring_ellipse((0, 1.036, -0.002), 0.196, 0.146, 16, sq=0.24),
        ]
        loft(sash, s_secs, 'cloth_secondary', C_TINT_HI, True, (True, True), True,
             scols=[C_TINT_LO, C_TINT_HI, C_TINT_MID, C_TINT_HI, C_TINT_MID])
        # Draped flowing sash tail hanging off left hip (-X) with subtle cloth wave
        tube(sash, [
            (-0.206, 0.930, -0.045),
            (-0.232, 0.825, -0.036),
            (-0.244, 0.705, -0.024),
            (-0.240, 0.605, -0.016),
            (-0.232, 0.545, -0.014),
        ], [(0.020, 0.052), (0.022, 0.062), (0.020, 0.068), (0.015, 0.062), (0.008, 0.044)],
             10, 'cloth_secondary', C_TINT_HI, (True, True), True,
             scols=[C_TINT_MID, C_TINT_HI, C_TINT_HI, C_TINT_LO], cap_poles=(False, True))
        # Heavy 16-sided smooth leather pirate belt over sash + leather keeper loop
        b_secs = [
            ring_ellipse((0, 0.922, -0.004), 0.228, 0.172, 16, sq=0.30),
            ring_ellipse((0, 0.955, -0.004), 0.231, 0.174, 16, sq=0.30),
            ring_ellipse((0, 0.988, -0.004), 0.228, 0.171, 16, sq=0.30),
        ]
        loft(sash, b_secs, 'leather', C_LEATHER_DARK, True, (True, True), True,
             scols=[C_LEATHER_DARK, C_LEATHER, C_LEATHER_DARK])
        # Ornate beveled brass pirate belt buckle at center front (-Z)
        for dx, dy, sx_b, sy_b in ((0, 0.036, 0.096, 0.020), (0, -0.036, 0.096, 0.020),
                                   (-0.040, 0, 0.020, 0.088), (0.040, 0, 0.020, 0.088),
                                   (0, 0, 0.012, 0.068)):
            cbox(sash, (dx, 0.955 + dy, -0.184), (sx_b, sy_b, 0.022), 'brass', C_BRASS, 0.004)
        # Decorative brass corner studs on buckle frame
        for sx_d in (-0.038, 0.038):
            for sy_d in (-0.034, 0.034):
                ellipsoid(sash, (sx_d, 0.955 + sy_d, -0.194), (0.007, 0.007, 0.006), 'brass',
                          mul(C_BRASS, 1.12), segs=8, rings=4, smooth=True)
    meshes.append(build_skinned(sash, arm_obj))

    return meshes

# ================================================================ 2. DROWNED (SKELETAL PIRATE)
def _barnacle_cluster(mb, center, normal_dir, count, scale=1.0, wspec=None):
    """Smooth volcano-crater calcified barnacle clusters (8-sided smooth cones with recessed open rim)."""
    rng = mb.rng
    c0 = Vector(center)
    n = Vector(normal_dir).normalized()
    ref = Vector((0, 1, 0)) if abs(n.y) < 0.85 else Vector((1, 0, 0))
    u = n.cross(ref).normalized()
    v = n.cross(u).normalized()
    for i in range(count):
        ang = 2.0 * pi * i / max(count, 1) + rng.uniform(-0.35, 0.35)
        rad = (0.0 if i == 0 else rng.uniform(0.017, 0.040)) * scale
        pos = c0 + (u * cos(ang) + v * sin(ang)) * rad
        h = rng.uniform(0.020, 0.038) * scale
        r0 = rng.uniform(0.016, 0.028) * scale
        col = C_BARNACLE_TIP if (i % 2 == 0) else C_BARNACLE
        # Smooth volcano profile: wide ribbed base -> tapered calcareous wall -> recessed dark aperture
        b_secs = []
        for t_h, r_s in ((-0.15, r0 * 1.08), (0.45, r0 * 0.78), (1.0, r0 * 0.46), (0.82, r0 * 0.24)):
            cp = pos + n * (h * t_h)
            ring = []
            for k in range(8):
                a = 2.0 * pi * k / 8.0
                fl = 1.0 + 0.08 * sin(4.0 * a)
                ring.append(cp + (u * cos(a) + v * sin(a)) * (r_s * fl))
            b_secs.append(ring)
        loft(mb, b_secs, 'coral', col, True, (True, True), True,
             scols=[C_BARNACLE, col, C_BARNACLE_TIP, C_SOCKET], wspec=wspec, cap_poles=(False, True))

def _seaweed_tuft(mb, start, length=0.22, strands=2, wspec=None):
    """Smooth wavy organic seaweed kelp ribbons."""
    rng = mb.rng
    s0 = Vector(start)
    for i in range(strands):
        dx = rng.uniform(-0.042, 0.042)
        dz = rng.uniform(-0.042, 0.042)
        sw = rng.uniform(-0.025, 0.025)
        pts = [
            s0 + Vector((dx * 0.25, 0.0, dz * 0.25)),
            s0 + Vector((dx * 0.85 + sw, -length * 0.28, dz * 0.75)),
            s0 + Vector((dx * 1.35 - sw, -length * 0.58, dz * 1.05)),
            s0 + Vector((dx * 1.15 + sw * 0.7, -length * 0.84, dz * 0.92)),
            s0 + Vector((dx * 0.95, -length, dz * 0.85)),
        ]
        tube(mb, pts, [(0.014, 0.004), (0.021, 0.005), (0.018, 0.005), (0.012, 0.004), (0.004, 0.002)],
             6, 'coral', C_KELP if i % 2 == 0 else C_KELP_HI, (True, True), True,
             scols=[C_KELP, C_KELP_HI, C_KELP, mul(C_KELP, 0.85)], wspec=wspec, cap_poles=(False, True))

def _bone_segment(mb, a, b, r_mid, r_end, wspec, sides=10):
    """10-sided smooth anatomical long bone with slender diaphysis shaft & flared double-condyle epiphyses."""
    a = Vector(a)
    b = Vector(b)
    pts = [
        a,
        a.lerp(b, 0.08),
        a.lerp(b, 0.20),
        a.lerp(b, 0.50),
        a.lerp(b, 0.80),
        a.lerp(b, 0.92),
        b,
    ]
    rads = [
        (r_end * 0.95, r_end * 0.85),
        (r_end * 1.15, r_end * 0.92),
        (r_mid * 0.98, r_mid * 0.94),
        (r_mid * 0.92, r_mid * 0.90),
        (r_mid * 0.98, r_mid * 0.94),
        (r_end * 1.14, r_end * 0.92),
        (r_end * 0.92, r_end * 0.84),
    ]
    scols = [C_BONE_DARK, C_BONE, C_BONE, C_BONE_GREEN, C_BONE, C_BONE, C_BONE_DARK]
    tube(mb, pts, rads, sides, 'bone', C_BONE, (True, True), True, scols=scols, wspec=wspec, cap_poles=(True, True))

def build_drowned_meshes(arm_obj):
    meshes = []

    # ---- 1. Drowned_Body (anatomically stylized smooth skull & skeleton + glowing eyes + barnacles & seaweed!)
    body = MB('Drowned_Body', seed=40)

    # Anatomically Stylized Smooth 16-sided Skull (y = 1.482 .. 1.726, weighted to Head)
    with wctx(body, "Head"):
        def skull_mod(y_val):
            def fn(a):
                front = max(0.0, -sin(a))
                ca = cos(a)
                # Hollow temporal depressions above zygoma, broader parietal cranium at back
                temple = exp(-((abs(abs(a + pi * 0.5) - 1.05)) ** 2) / 0.14) if sin(a) < 0.2 else 0.0
                socket_ang = exp(-((abs(abs(a + pi * 0.5) - 0.44)) ** 2) / 0.08) if sin(a) < 0.0 else 0.0
                rm = 1.0
                dz = 0.0
                if 1.540 <= y_val <= 1.575:
                    # Narrowed hollow under-cheekbone skull base
                    rm -= 0.12 * temple
                elif 1.585 <= y_val <= 1.622:
                    # Deep contoured orbital socket hollows + temple pinch
                    rm -= 0.11 * socket_ang + 0.07 * temple
                elif 1.628 <= y_val <= 1.648:
                    # Pronounced cranial brow shelf
                    dz -= 0.008 * (front ** 1.5)
                elif y_val >= 1.655:
                    # Rounded fuller parietal dome in rear
                    rm += 0.04 * max(0.0, sin(a))
                return (rm, 0.0, dz)
            return fn

        cran_specs = [
            (1.538,  0.020, 0.062, 0.072, 0.00, 0.22, C_BONE_DARK),
            (1.568,  0.008, 0.076, 0.092, 0.04, 0.26, C_BONE_DARK),
            (1.602, -0.004, 0.092, 0.106, 0.08, 0.28, C_BONE_GREEN),
            (1.636, -0.004, 0.100, 0.112, 0.06, 0.25, C_BONE),
            (1.672,  0.004, 0.102, 0.114, 0.00, 0.20, C_BONE),
            (1.706,  0.010, 0.084, 0.095, 0.00, 0.16, mul(C_BONE, 1.05)),
            (1.726,  0.012, 0.038, 0.044, 0.00, 0.12, C_BONE),
        ]
        cran_secs = [
            ring_ellipse((0, yv, zv), rx, rz, 16, front_bias=fb, sq=sq, mod_fn=skull_mod(yv))
            for yv, zv, rx, rz, fb, sq, _ in cran_specs
        ]
        loft(body, cran_secs, 'bone', C_BONE, True, (True, True), True,
             scols=[c for *_, c in cran_specs], cap_poles=(True, True))

        # Carved menacing supraorbital brow ridge (smooth curved bony arch dipping at glabella!)
        brow_arch = [
            (-0.082, 1.622, -0.078),
            (-0.056, 1.637, -0.106),
            (-0.022, 1.635, -0.118),
            ( 0.000, 1.628, -0.114),
            ( 0.022, 1.635, -0.118),
            ( 0.056, 1.637, -0.106),
            ( 0.082, 1.622, -0.078),
        ]
        tube(body, brow_arch, [0.011, 0.016, 0.015, 0.013, 0.015, 0.016, 0.011], 10,
             'bone', C_BONE, (True, True), True, cap_poles=(True, True))

        # Sculpted zygomatic cheekbones, deep dark contoured oval eye sockets & 10x6 GLOWING SEA-GREEN EYES!
        for sx in (-1.0, 1.0):
            # Sweeping zygomatic cheekbone arch from nasal flank around under orbit to temporal arch!
            zyg_pts = [
                (sx * 0.020, 1.584, -0.116),
                (sx * 0.058, 1.578, -0.108),
                (sx * 0.088, 1.584, -0.078),
                (sx * 0.094, 1.594, -0.032),
                (sx * 0.082, 1.600,  0.010),
            ]
            tube(body, zyg_pts, [0.011, 0.016, 0.017, 0.012, 0.009], 8, 'bone', C_BONE_GREEN,
                 (True, True), True, scols=[C_BONE, C_BONE_GREEN, C_BONE_DARK, C_BONE_DARK], cap_poles=(True, True))
            # Outer orbital pillar connecting brow down to zygoma
            tube(body, [(sx * 0.076, 1.626, -0.088), (sx * 0.082, 1.604, -0.092), (sx * 0.078, 1.584, -0.094)],
                 [0.011, 0.010, 0.012], 8, 'bone', C_BONE, (True, True), True)

            # Deep dark contoured oval eye socket recess (smooth elliptical dish + socket rim!)
            with xf(body, T(sx * 0.040, 1.606, -0.102) @ R('Y', -sx * 16) @ R('Z', sx * 8)):
                ellipsoid(body, (0.0, 0.0, 0.002), (0.025, 0.021, 0.012), 'bone', C_SOCKET,
                          segs=12, rings=6, smooth=True, shade_dir=False)
                # GLOWING SEA-GREEN EMISSIVE EYE (10x6 smooth ellipsoid!)
                ellipsoid(body, (0.0, 0.0, -0.011), (0.014, 0.012, 0.010), 'emissive_sea', C_SEA_GLOW,
                          segs=10, rings=6, smooth=True, shade_dir=False)

        # Carved piriform nasal cavity (dark inverted-teardrop recess + slim bone nasal bridge & septum!)
        tube(body, [(0.0, 1.622, -0.114), (0.0, 1.598, -0.120)], [0.011, 0.008], 8, 'bone', C_BONE, (True, True), True)
        nas_secs = [
            ring_ellipse((0.0, 1.564, -0.112), 0.014, 0.009, 10),
            ring_ellipse((0.0, 1.578, -0.114), 0.013, 0.009, 10),
            ring_ellipse((0.0, 1.594, -0.114), 0.006, 0.007, 10),
        ]
        loft(body, nas_secs, 'bone', C_SOCKET, True, (True, True), True, shade_dir=False, cap_poles=(True, True))

        # Sculpted horseshoe upper maxilla arch + individual rounded grinning skull teeth!
        maxilla_pts = [
            (-0.056, 1.548, -0.072),
            (-0.044, 1.546, -0.104),
            (-0.020, 1.545, -0.118),
            ( 0.000, 1.545, -0.122),
            ( 0.020, 1.545, -0.118),
            ( 0.044, 1.546, -0.104),
            ( 0.056, 1.548, -0.072),
        ]
        tube(body, maxilla_pts, [0.014, 0.017, 0.018, 0.019, 0.018, 0.017, 0.014], 10,
             'bone', C_BONE, (True, True), True, cap_poles=(True, True))
        # Dark interior mouth shadow behind teeth
        ellipsoid(body, (0.0, 1.522, -0.088), (0.040, 0.020, 0.032), 'bone', C_SOCKET, segs=10, rings=5, smooth=True, shade_dir=False)
        # 7 sculpted rounded upper teeth along curved maxilla arc
        for ti in range(-3, 4):
            ta = ti * 0.25
            tx = sin(ta) * 0.048
            tz = -0.084 - cos(ta) * 0.044
            th = 0.012 if abs(ti) <= 1 else (0.0135 if abs(ti) == 2 else 0.010) # slightly sharper canines!
            ellipsoid(body, (tx, 1.528, tz), (0.0062, th, 0.0062), 'bone', C_BONE_TEETH, segs=8, rings=4, smooth=True)

        # Strong sculpted U-shaped hinged mandible (lower jawbone sweeping from temporal condyles to chin!)
        jaw_pts = [
            (-0.068, 1.564, -0.028),
            (-0.062, 1.512, -0.042),
            (-0.044, 1.494, -0.084),
            (-0.018, 1.488, -0.112),
            ( 0.000, 1.486, -0.116),
            ( 0.018, 1.488, -0.112),
            ( 0.044, 1.494, -0.084),
            ( 0.062, 1.512, -0.042),
            ( 0.068, 1.564, -0.028),
        ]
        jaw_rads = [0.012, 0.016, 0.016, 0.018, 0.019, 0.018, 0.016, 0.016, 0.012]
        tube(body, jaw_pts, jaw_rads, 10, 'bone', C_BONE_DARK, (True, True), True,
             scols=[C_BONE_DARK, C_BONE_DARK, C_BONE, C_BONE, C_BONE, C_BONE, C_BONE_DARK, C_BONE_DARK],
             cap_poles=(True, True))
        # Subtle lower teeth row
        for ti in range(-2, 3):
            ta = ti * 0.25
            tx = sin(ta) * 0.042
            tz = -0.082 - cos(ta) * 0.038
            ellipsoid(body, (tx, 1.506, tz), (0.0052, 0.0085, 0.0052), 'bone', C_BONE, segs=8, rings=4, smooth=True)

        # Organic temple barnacle cluster encrusted on skull!
        _barnacle_cluster(body, (0.086, 1.652, -0.036), (0.8, 0.45, -0.35), 4, 0.82, "Head")

    # Continuous cervical-to-thoracic-to-lumbar spine, smooth 10-sided ribs, sculpted sternum, clavicles & contoured pelvis
    with wctx(body, w_torso):
        # Continuous smooth 10-sided cervical-to-lumbar spine column seated solidly into skull base & pelvis!
        spine_path = [
            (0.0, 0.920, 0.016),
            (0.0, 1.020, 0.022),
            (0.0, 1.130, 0.028),
            (0.0, 1.245, 0.032),
            (0.0, 1.350, 0.028),
            (0.0, 1.415, 0.022),
            (0.0, 1.472, 0.014),
            (0.0, 1.522, 0.008),
            (0.0, 1.585, 0.010),
        ]
        spine_rads = [
            (0.042, 0.038), (0.038, 0.036), (0.038, 0.038), (0.036, 0.036),
            (0.038, 0.038), (0.042, 0.042), (0.044, 0.046), (0.044, 0.050), (0.048, 0.054),
        ]
        tube(body, spine_path, spine_rads, 10, 'bone', C_BONE, (True, True), True,
             scols=[C_BONE_DARK, C_BONE, C_BONE_DARK, C_BONE, C_BONE, C_BONE_DARK, C_BONE, C_BONE_DARK],
             cap_poles=(True, True))

        # Sculpted individual vertebral discs & dorsal spinous processes (smooth, NO square bricks!)
        for i in range(9):
            vy = 0.96 + i * 0.068
            vz = 0.026 + 0.008 * sin(i * 0.55)
            vw = 0.040 if i < 3 else (0.034 if i < 7 else 0.032)
            ellipsoid(body, (0.0, vy, vz), (vw, 0.024, 0.036), 'bone',
                      C_BONE_DARK if i % 2 else C_BONE, segs=10, rings=5, smooth=True)
            # Dorsal spinous process fin projecting backward (+Z)
            tube(body, [(0.0, vy + 0.004, vz + 0.022), (0.0, vy - 0.012, vz + 0.056)],
                 [(0.011, 0.014), (0.006, 0.009)], 6, 'bone', C_BONE, (True, True), True, cap_poles=(False, True))

        # Sculpted anatomical sternum (manubrium -> sternal body -> tapered xiphoid tip!)
        stern_secs = [
            ring_ellipse((0.0, 1.168, -0.104), 0.014, 0.011, 10),
            ring_ellipse((0.0, 1.215, -0.112), 0.026, 0.016, 10, sq=0.25),
            ring_ellipse((0.0, 1.285, -0.114), 0.030, 0.017, 10, sq=0.28),
            ring_ellipse((0.0, 1.350, -0.102), 0.042, 0.018, 10, sq=0.30),
            ring_ellipse((0.0, 1.384, -0.090), 0.030, 0.015, 10, sq=0.25),
        ]
        loft(body, stern_secs, 'bone', C_BONE, True, (True, True), True,
             scols=[C_BONE_DARK, C_BONE, mul(C_BONE, 1.05), C_BONE, C_BONE_DARK], cap_poles=(True, True))

        # 5 pairs of curved smooth 10-sided bone ribs wrapping gracefully around hollow chest!
        rib_specs = [
            (1.362, 0.168, 0.110, True),
            (1.306, 0.190, 0.126, True),
            (1.250, 0.188, 0.128, True),
            (1.196, 0.172, 0.118, True),
            (1.142, 0.146, 0.092, False), # 5th floating false rib!
        ]
        for ri, (ry, rx, rz, joins_sternum) in enumerate(rib_specs):
            for sx in (-1.0, 1.0):
                if joins_sternum:
                    pts = [
                        (sx * 0.024, ry + 0.012,  0.044),
                        (sx * rx * 0.68, ry + 0.014,  0.048),
                        (sx * rx,        ry + 0.002, -0.018),
                        (sx * rx * 0.72, ry - 0.014, -rz),
                        (sx * 0.026,     ry - 0.018, -rz * 0.90),
                    ]
                    rads = [(0.014, 0.011), (0.016, 0.012), (0.017, 0.012), (0.015, 0.011), (0.012, 0.010)]
                else:
                    pts = [
                        (sx * 0.024, ry + 0.010,  0.042),
                        (sx * rx * 0.70, ry + 0.008,  0.036),
                        (sx * rx,        ry - 0.006, -0.018),
                        (sx * rx * 0.66, ry - 0.020, -rz),
                    ]
                    rads = [(0.013, 0.010), (0.015, 0.011), (0.014, 0.010), (0.007, 0.006)]
                tube(body, pts, rads, 10, 'bone', C_BONE if ri % 2 == 0 else C_BONE_GREEN,
                     (True, True), True, cap_poles=(False, True))

        # S-curved sculpted 10-sided clavicles & contoured triangular scapulae (shoulder blades)
        for sx in (-1.0, 1.0):
            tube(body, [
                (sx * 0.026, 1.376, -0.084),
                (sx * 0.088, 1.394, -0.072),
                (sx * 0.155, 1.398, -0.028),
                (sx * 0.212, 1.384,  0.012),
            ], [0.019, 0.017, 0.018, 0.022], 10, 'bone', C_BONE, (True, True), True, cap_poles=(True, True))
            # Contoured smooth scapula plate on upper back
            scap_secs = [
                ring_ellipse((sx * 0.088, 1.242, 0.078), 0.022, 0.010, 10, rot_y=sx * 16),
                ring_ellipse((sx * 0.116, 1.310, 0.078), 0.046, 0.013, 10, rot_y=sx * 20),
                ring_ellipse((sx * 0.132, 1.368, 0.064), 0.048, 0.014, 10, rot_y=sx * 22),
            ]
            loft(body, scap_secs, 'bone', C_BONE_DARK, True, (True, True), True, cap_poles=(True, True))

        # Contoured anatomical 14-sided pelvis (iliac wings + sacrum + pubis)
        def pelvis_wing(a):
            # Flared lateral iliac crests around a=0, pi and sculpted front pubis hollow
            return (1.0 + 0.10 * (cos(a) ** 2) - 0.08 * max(0.0, -sin(a)), 0.0, 0.0)
        pelvis_secs = [
            ring_ellipse((0, 0.832, 0.002), 0.138, 0.096, 14, sq=0.30),
            ring_ellipse((0, 0.892, 0.000), 0.168, 0.112, 14, sq=0.30, mod_fn=pelvis_wing),
            ring_ellipse((0, 0.946, 0.002), 0.174, 0.114, 14, sq=0.28, mod_fn=pelvis_wing),
            ring_ellipse((0, 0.968, 0.004), 0.138, 0.094, 14, sq=0.25),
        ]
        loft(body, pelvis_secs, 'bone', C_BONE_DARK, True, (True, True), True,
             scols=[C_BONE_DARK, C_BONE, C_BONE_GREEN, C_BONE_DARK])

        # Ragged briny breeches loincloth / tatters over hips (14-sided smooth with jagged lower hem!)
        def tatter_hem(a):
            return (1.0 + 0.04 * cos(5.0 * a), 0.022 * sin(7.0 * a + 0.6), 0.0)
        tatter_secs = [
            ring_ellipse((0, 0.780, 0.0), 0.168, 0.126, 14, sq=0.28, mod_fn=tatter_hem),
            ring_ellipse((0, 0.845, 0.0), 0.176, 0.130, 14, sq=0.28),
            ring_ellipse((0, 0.915, 0.0), 0.184, 0.132, 14, sq=0.28),
            ring_ellipse((0, 0.962, 0.0), 0.168, 0.120, 14, sq=0.24),
        ]
        loft(body, tatter_secs, 'cloth_primary', C_TINT_MID, True, (False, False), True,
             scols=[C_TINT_LO, C_TINT_MID, C_TINT_MID, C_TINT_LO])

        # Twisted nautical rope belt around skeletal waist (18-seg smooth rope + front knot!)
        rope_pts = [(0.178 * cos(2 * pi * k / 18), 0.958 + 0.005 * sin(6 * pi * k / 18), 0.132 * sin(2 * pi * k / 18))
                    for k in range(19)]
        tube(body, rope_pts, 0.017, 8, 'leather', C_WOOD_ROT, (False, False), True)
        ellipsoid(body, (0.045, 0.955, -0.136), (0.024, 0.022, 0.020), 'leather', C_WOOD_ROT, segs=10, rings=5, smooth=True)
        tube(body, [(0.048, 0.945, -0.142), (0.062, 0.865, -0.152), (0.068, 0.790, -0.146)],
             [0.014, 0.012, 0.007], 8, 'leather', C_WOOD_ROT, (True, True), True, cap_poles=(False, True))

        # Encrusted barnacles & flowing seaweed ribbons on chest & shoulder!
        _barnacle_cluster(body, (-0.155, 1.365, -0.055), (-0.7, 0.6, -0.4), 4, 0.95, w_torso)
        _barnacle_cluster(body, (0.145, 1.235, -0.095), (0.6, 0.2, -0.7), 3, 0.85, w_torso)
        _seaweed_tuft(body, (-0.170, 1.345, -0.020), 0.24, 2, w_torso)
        _seaweed_tuft(body, (0.140, 1.180, 0.085), 0.20, 2, w_torso)

    # Smooth 10-sided bone arms with flared joint epiphyses & separated skeletal finger phalanges!
    for side in ("L", "R"):
        sx = -1.0 if side == "L" else 1.0
        _, ua, el, wr, ft = [Vector(q) for q in _arm_pts(sx)]
        wa = w_arm(side)
        with wctx(body, wa):
            # Humerus (upper arm bone with smooth flared humeral head & distal condyles)
            _bone_segment(body, ua, el, 0.028, 0.042, wa, sides=10)
            # Paired forearm radius + slender ulna for unmistakable skeletal silhouette!
            f_dir = (wr - el).normalized()
            f_off = f_dir.cross(Vector((0, 0, -1))).normalized()
            _bone_segment(body, el + f_off * 0.008, wr + f_off * 0.010, 0.018, 0.027, wa, sides=10)
            _bone_segment(body, el - f_off * 0.010, wr - f_off * 0.008, 0.015, 0.022, wa, sides=8)
            # Smooth sculpted glenohumeral shoulder ball & elbow olecranon joint knuckles
            ellipsoid(body, ua, (0.046, 0.044, 0.044), 'bone', C_BONE_GREEN, segs=10, rings=6, smooth=True)
            ellipsoid(body, el, (0.036, 0.034, 0.036), 'bone', C_BONE_DARK, segs=10, rings=6, smooth=True)
            if side == "R":
                _seaweed_tuft(body, el.lerp(wr, 0.5), 0.16, 2, wa)
        # Articulated skeletal hand with separated finger phalanges (weighted 100% to Hand_side)
        sculpt_hand(body, wr, ft, side, style='drowned')

    # Smooth 10-sided bone legs + mismatched weathered boot (R) & articulated bare skeletal foot (L), planted at y = 0.0!
    for side in ("L", "R"):
        sx = -1.0 if side == "L" else 1.0
        hp, kn, an, to = [Vector(q) for q in _leg_pts(sx)]
        wl = w_leg(side)
        with wctx(body, wl):
            _bone_segment(body, hp, kn, 0.036, 0.052, wl, sides=10)
            _bone_segment(body, kn, an, 0.028, 0.042, wl, sides=10)
            # Slender fibula alongside bare left shin tibia!
            if side == "L":
                _bone_segment(body, kn + Vector((-0.024, -0.02, 0.010)), an + Vector((-0.020, 0.02, 0.008)),
                              0.011, 0.016, wl, sides=8)
            # Smooth sculpted patella (kneecap) & femoral condyles
            ellipsoid(body, kn, (0.046, 0.044, 0.046), 'bone', C_BONE_GREEN, segs=10, rings=6, smooth=True)
            ellipsoid(body, kn + Vector((0.0, 0.006, -0.034)), (0.024, 0.026, 0.015), 'bone', C_BONE, segs=10, rings=5, smooth=True)

            # Tattered smooth 12-sided trouser shorts over upper thighs
            def rag_hem(a):
                return (1.0 + 0.05 * cos(4.0 * a), 0.018 * sin(5.0 * a), 0.0)
            short_secs = [
                ring_ellipse((sx * 0.115, 0.615, 0.0), 0.088, 0.090, 12, sq=0.22, mod_fn=rag_hem),
                ring_ellipse((sx * 0.115, 0.770, 0.0), 0.094, 0.098, 12, sq=0.22),
                ring_ellipse((sx * 0.100, 0.885, 0.0), 0.088, 0.096, 12, sq=0.22),
            ]
            loft(body, short_secs, 'cloth_primary', C_TINT_LO, True, (False, True), True,
                 scols=[C_TINT_LO, C_TINT_MID, C_TINT_LO])

            fx = sx * 0.118
            if side == "R":
                # Smooth weathered sea-rotted pirate boot planted flat at y = 0.0!
                _build_buccaneer_boot_vamp(body, fx, sx, C_WOOD_ROT, C_LEATHER_DARK, segs=14)
                shaft = [
                    ring_ellipse((fx, 0.072, 0.015), 0.055, 0.060, 14, sq=0.20),
                    ring_ellipse((fx, 0.195, 0.010), 0.062, 0.066, 14, sq=0.20),
                    ring_ellipse((fx, 0.290, 0.004), 0.070, 0.074, 14, sq=0.22),
                    ring_ellipse((fx, 0.348, 0.000), 0.084, 0.088, 14, sq=0.24, mod_fn=rag_hem),
                ]
                loft(body, shaft, 'leather', C_WOOD_ROT, True, (False, True), True,
                     scols=[C_LEATHER_DARK, C_WOOD_ROT, C_WOOD_ROT, mul(C_WOOD_ROT, 0.90)])
                _barnacle_cluster(body, (fx + 0.066, 0.22, -0.03), (0.8, 0.2, -0.5), 3, 0.8, wl)
            else:
                # Articulated bare skeletal foot planted flat at y = 0.0!
                # Sculpted calcaneus heel & talus ankle arch (bottom rests at y = 0.000)
                heel = [
                    ring_ellipse((fx, 0.000, 0.022), 0.034, 0.044, 10, sq=0.25),
                    ring_ellipse((fx, 0.026, 0.020), 0.038, 0.048, 10, sq=0.25),
                    ring_ellipse((fx, 0.062, 0.018), 0.034, 0.040, 10, sq=0.20),
                ]
                loft(body, heel, 'bone', C_BONE_DARK, True, (True, True), True, cap_poles=(False, True))
                # 4 distinct splayed skeletal metatarsal + toe bones resting cleanly at y = 0.000!
                toe_specs = [
                    (-0.032, -0.158, 0.0105), # big toe / outer
                    (-0.010, -0.172, 0.0095),
                    ( 0.012, -0.165, 0.0090),
                    ( 0.032, -0.148, 0.0082),
                ]
                for tx, tz_end, tr in toe_specs:
                    t_pts = [
                        (fx + tx * 0.45, 0.046,  0.002),
                        (fx + tx * 0.82, 0.030, -0.058),
                        (fx + tx,        0.016, -0.118),
                        (fx + tx,        tr,     tz_end),
                    ]
                    tube(body, t_pts, [tr * 1.15, tr * 0.95, tr * 1.12, tr * 0.82], 8, 'bone', C_BONE,
                         (True, True), True, scols=[C_BONE_DARK, C_BONE, C_BONE], cap_poles=(False, True))
                _barnacle_cluster(body, (fx - 0.044, 0.26, -0.025), (-0.8, 0.1, -0.5), 3, 0.82, wl)
                _seaweed_tuft(body, (fx - 0.045, 0.34, 0.02), 0.18, 2, wl)

    meshes.append(build_skinned(body, arm_obj))

    # ---- 2. Drowned_Bandana (16-seg smooth tattered sea-stained kerchief + knotted tails)
    dban = MB('Drowned_Bandana', seed=41)
    with wctx(dban, "Head"):
        def dban_fold(a):
            return (1.0 + 0.022 * sin(5.0 * a + 1.1), 0.004 * cos(3.0 * a), 0.0)
        dome = [
            ring_ellipse((0, 1.642, 0.004), 0.110, 0.120, 16, sq=0.20, mod_fn=dban_fold),
            ring_ellipse((0, 1.682, 0.008), 0.115, 0.124, 16, sq=0.18, mod_fn=dban_fold),
            ring_ellipse((0, 1.720, 0.012), 0.095, 0.104, 16, sq=0.16),
            ring_ellipse((0, 1.746, 0.014), 0.042, 0.046, 16, sq=0.12),
        ]
        loft(dban, dome, 'cloth_secondary', C_TINT_MID, True, (True, True), True,
             scols=[C_TINT_LO, C_TINT_MID, C_TINT_MID, C_TINT_LO], cap_poles=(False, True))
        band = [
            ring_ellipse((0, 1.630, 0.004), 0.113, 0.123, 16, sq=0.20),
            ring_ellipse((0, 1.656, 0.006), 0.117, 0.126, 16, sq=0.20, mod_fn=dban_fold),
        ]
        loft(dban, band, 'cloth_secondary', C_TINT_LO, True, (True, True), True)
        ellipsoid(dban, (-0.068, 1.646, 0.115), (0.024, 0.021, 0.021), 'cloth_secondary', C_TINT_LO,
                  segs=10, rings=5, smooth=True)
        tube(dban, [(-0.072, 1.638, 0.122), (-0.098, 1.568, 0.154), (-0.116, 1.485, 0.168)],
             [(0.018, 0.007), (0.025, 0.008), (0.007, 0.003)], 8, 'cloth_secondary', C_TINT_MID,
             (True, True), True, cap_poles=(False, True))
        tube(dban, [(-0.052, 1.638, 0.122), (-0.036, 1.570, 0.162), (-0.018, 1.500, 0.178)],
             [(0.016, 0.007), (0.022, 0.007), (0.006, 0.003)], 8, 'cloth_secondary', C_TINT_LO,
             (True, True), True, cap_poles=(False, True))
    meshes.append(build_skinned(dban, arm_obj))

    # ---- 3. Drowned_CaptainHat (24-seg smooth weathered torn tricorne + tarnished trim + barnacles & kelp!)
    dhat = MB('Drowned_CaptainHat', seed=42)
    with wctx(dhat, "Head"):
        with xf(dhat, T(0, 1.692, 0.005) @ R('X', -9) @ R('Z', 6)):
            crown = [
                ring_ellipse((0, -0.015, 0.000), 0.113, 0.123, 14, sq=0.20),
                ring_ellipse((0,  0.045, 0.002), 0.110, 0.118, 14, sq=0.18),
                ring_ellipse((0,  0.105, 0.006), 0.094, 0.102, 14, sq=0.16),
                ring_ellipse((0,  0.144, 0.010), 0.042, 0.046, 14, sq=0.12),
            ]
            loft(dhat, crown, 'cloth_primary', C_TINT_LO, True, (True, True), True,
                 scols=[C_TINT_LO, C_TINT_MID, C_TINT_LO, C_TINT_LO], cap_poles=(False, True))
            segs = 24
            in_b, mid_b, out_b, out_t, in_t = [], [], [], [], []
            trim_pts = []
            for k in range(segs):
                a = 2.0 * pi * k / segs
                lobe = 0.5 + 0.5 * cos(3.0 * (a + pi * 0.5))
                # Weathered ragged bite notches in the soaked tricorne brim!
                notch = 0.80 if k in (7, 8, 18) else (0.91 if k in (6, 9, 17, 19) else 1.0)
                r_in = 0.109
                r_out = (0.178 + 0.098 * (lobe ** 1.3)) * notch
                y_up = 0.092 + 0.056 * (1.0 - 0.5 * lobe) + 0.014 * sin(5.0 * a)
                ca, sa = cos(a), sin(a)
                r_mid = 0.5 * (r_in + r_out)
                in_b.append(Vector((ca * r_in, -0.006, sa * r_in * 1.08)))
                mid_b.append(Vector((ca * r_mid, y_up * 0.30 - 0.008, sa * r_mid * 1.08)))
                out_b.append(Vector((ca * r_out, y_up - 0.018, sa * r_out * 1.08)))
                out_t.append(Vector((ca * (r_out - 0.010), y_up + 0.006, sa * (r_out - 0.010) * 1.08)))
                in_t.append(Vector((ca * (r_in + 0.006), 0.014, sa * (r_in + 0.006) * 1.08)))
                trim_pts.append(Vector((ca * (r_out - 0.001), y_up - 0.002, sa * (r_out - 0.001) * 1.08)))
            loft(dhat, [in_b, mid_b, out_b, out_t, in_t], 'cloth_primary', C_TINT_MID, True, (False, False), True,
                 scols=[C_TINT_LO, C_TINT_LO, C_TINT_MID, C_TINT_MID, C_TINT_LO])
            trim_pts.append(trim_pts[0])
            tube(dhat, trim_pts, 0.0072, 6, 'brass', mul(C_BRASS, 0.80), (False, False), True)
            _barnacle_cluster(dhat, (0.112, 0.088, -0.072), (0.6, 0.7, -0.4), 4, 0.92, "Head")
            _seaweed_tuft(dhat, (-0.165, 0.090, 0.040), 0.22, 2, "Head")
    meshes.append(build_skinned(dhat, arm_obj))

    # ---- 4. Drowned_Coat (16-seg smooth tattered flared coat + weathered lapels & barnacle epaulettes)
    dcoat = MB('Drowned_Coat', seed=43)
    with wctx(dcoat, w_coat_skirt):
        def dcoat_arc(y, rx, rz, gap_deg=38.0, jag=0.0):
            pts = []
            a0 = radians(-90.0 + gap_deg)
            a1 = radians(270.0 - gap_deg)
            n = 17
            for k in range(n):
                u = k / float(n - 1)
                a = a0 + (a1 - a0) * u
                dy = jag * (0.042 * sin(k * 1.85) + 0.024 * cos(k * 3.1))
                w_fl = 1.0 + jag * 0.05 * sin(u * pi * 6.0)
                pts.append(Vector((cos(a) * rx * w_fl, y + dy, sin(a) * rz * w_fl)))
            return pts
        secs = [
            dcoat_arc(0.50, 0.282, 0.214, 48.0, 1.0),
            dcoat_arc(0.66, 0.256, 0.192, 42.0, 0.45),
            dcoat_arc(0.84, 0.224, 0.166, 36.0, 0.15),
            dcoat_arc(0.98, 0.206, 0.152, 34.0, 0.0),
            dcoat_arc(1.18, 0.228, 0.164, 36.0, 0.0),
            dcoat_arc(1.38, 0.232, 0.148, 46.0, 0.0),
        ]
        loft(dcoat, secs, 'cloth_primary', C_TINT_MID, closed=False, caps=(False, False), smooth=True,
             scols=[C_TINT_LO, C_TINT_MID, C_TINT_MID, C_TINT_LO, C_TINT_MID, C_TINT_HI])
        # High tattered back collar
        dcol = [dcoat_arc(1.375, 0.136, 0.114, 58.0, 0.0), dcoat_arc(1.458, 0.150, 0.128, 62.0, 0.18)]
        loft(dcoat, dcol, 'cloth_secondary', C_TINT_MID, closed=False, caps=(False, False), smooth=True)
        for sx in (-1.0, 1.0):
            # Sculpted smooth weathered lapels
            lap_s = []
            for ly, lw, lz in ((1.06, 0.042, -0.152), (1.20, 0.064, -0.166), (1.34, 0.058, -0.148)):
                lap_s.append([
                    Vector((sx * 0.118, ly, lz + 0.012)),
                    Vector((sx * (0.118 + lw), ly, lz + 0.004)),
                    Vector((sx * (0.118 + lw), ly, lz - 0.010)),
                    Vector((sx * 0.118, ly, lz - 0.006)),
                ])
            loft(dcoat, lap_s, 'cloth_secondary', C_TINT_MID, True, (True, True), True)
            # Weathered tarnished brass epaulette pads
            with wctx(dcoat, "Shoulder_" + ("L" if sx < 0 else "R")):
                ep_pts = [(sx * 0.132, 1.422, 0.006), (sx * 0.215, 1.428, 0.008), (sx * 0.268, 1.408, 0.008)]
                tube(dcoat, ep_pts, [(0.044, 0.014), (0.054, 0.016), (0.046, 0.013)], 10,
                     'brass', mul(C_BRASS, 0.78), (True, True), True, cap_poles=(True, True))
        _barnacle_cluster(dcoat, (0.23, 1.44, -0.01), (0.4, 0.9, -0.2), 3, 0.9, w_torso)
    for side in ("L", "R"):
        sx = -1.0 if side == "L" else 1.0
        sh, ua, el, wr, _ = [Vector(q) for q in _arm_pts(sx)]
        with wctx(dcoat, w_arm(side)):
            tube(dcoat, [ua, ua.lerp(el, 0.45), el, el.lerp(wr, 0.56)],
                 [0.084, 0.074, 0.068, 0.078], 12, 'cloth_primary', C_TINT_MID, (True, False), True)
            tube(dcoat, [el.lerp(wr, 0.50), el.lerp(wr, 0.68), el.lerp(wr, 0.82)], [0.090, 0.094, 0.086],
                 12, 'cloth_secondary', C_TINT_MID, (True, True), True)
    meshes.append(build_skinned(dcoat, arm_obj))

    # ---- 5. Drowned_Shield (curved planked buckler with riveted iron rim & sculpted dome boss!)
    dshield = MB('Drowned_Shield', seed=44)
    _, _, el_l, wr_l, _ = [Vector(q) for q in _arm_pts(-1.0)]
    sh_c = el_l.lerp(wr_l, 0.52)
    f_dir = (wr_l - el_l).normalized()
    out_n = Vector((-0.78, 0.12, -0.62)).normalized()
    u_ax = (f_dir - out_n * f_dir.dot(out_n)).normalized()
    v_ax = out_n.cross(u_ax).normalized()
    MSH = Matrix((
        (u_ax.x, out_n.x, v_ax.x, sh_c.x + out_n.x * 0.055),
        (u_ax.y, out_n.y, v_ax.y, sh_c.y + out_n.y * 0.055),
        (u_ax.z, out_n.z, v_ax.z, sh_c.z + out_n.z * 0.055),
        (0.0, 0.0, 0.0, 1.0),
    ))
    with wctx(dshield, "Forearm_L"):
        with xf(dshield, MSH):
            r_sh = 0.285
            # 20-sided smooth convex curved wooden buckler dish!
            sh_secs = [
                ring_ellipse((0, -0.022, 0), r_sh * 0.94, r_sh * 0.94, 20),
                ring_ellipse((0,  0.008, 0), r_sh * 0.99, r_sh * 0.99, 20),
                ring_ellipse((0,  0.032, 0), r_sh * 0.86, r_sh * 0.86, 20),
                ring_ellipse((0,  0.048, 0), r_sh * 0.50, r_sh * 0.50, 20),
                ring_ellipse((0,  0.054, 0), r_sh * 0.16, r_sh * 0.16, 20),
            ]
            loft(dshield, sh_secs, 'leather', C_WOOD_ROT, True, (True, True), True,
                 scols=[mul(C_WOOD_ROT, 0.78), C_WOOD_ROT, mul(C_WOOD_ROT, 1.04), mul(C_WOOD_ROT, 1.08), C_WOOD_ROT],
                 cap_poles=(False, True))
            # Individual bevelled wooden plank seams across the curved shield face (clear of central boss)
            for pz in (-0.175, -0.105, 0.105, 0.175):
                half_l = sqrt(max(0.001, (r_sh * 0.94) ** 2 - pz * pz))
                r_mid = abs(pz)
                y_mid = 0.052 - 0.036 * ((r_mid / r_sh) ** 2)
                y_q = 0.052 - 0.036 * (((half_l * 0.5) ** 2 + pz * pz) / (r_sh ** 2))
                p_arc = [(-half_l * 0.92, 0.016, pz), (-half_l * 0.50, y_q, pz),
                         (0.0, y_mid, pz), (half_l * 0.50, y_q, pz), (half_l * 0.92, 0.016, pz)]
                tube(dshield, p_arc, (0.0045, 0.0035), 6, 'leather', C_LEATHER_DARK, (True, True), True)

            # Heavy 20-sided smooth riveted iron rim hoop
            torus(dshield, (0.0, 0.008, 0.0), r_sh * 0.995, 0.024, segs=20, psegs=10,
                  mat='iron', col=C_IRON, smooth=True)
            # 12 domed iron rim rivets around shield perimeter!
            for rk in range(12):
                ra = 2.0 * pi * rk / 12.0
                ellipsoid(dshield, (cos(ra) * r_sh * 0.94, 0.032, sin(ra) * r_sh * 0.94),
                          (0.012, 0.009, 0.012), 'iron', mul(C_IRON, 1.25), segs=8, rings=4, smooth=True)

            # Sculpted central iron dome boss with flanged riveted collar + curved iron cross braces!
            ellipsoid(dshield, (0.0, 0.052, 0.0), (0.084, 0.048, 0.084), 'iron', mul(C_IRON, 1.20),
                      segs=14, rings=7, smooth=True)
            torus(dshield, (0.0, 0.052, 0.0), 0.086, 0.012, segs=16, psegs=8, mat='iron', col=C_IRON, smooth=True)
            for rot_b in (0.0, 90.0):
                with xf(dshield, R('Y', rot_b)):
                    br_arc = [
                        (-r_sh * 0.96, 0.014, 0.0),
                        (-r_sh * 0.55, 0.046, 0.0),
                        ( 0.0,         0.056, 0.0),
                        ( r_sh * 0.55, 0.046, 0.0),
                        ( r_sh * 0.96, 0.014, 0.0),
                    ]
                    tube(dshield, br_arc, (0.018, 0.008), 8, 'iron', C_IRON, (True, True), True)

            # Leather forearm grip straps on inner side
            for dz_s in (-0.055, 0.055):
                tube(dshield, [(-0.075, -0.024, dz_s), (0.0, -0.048, dz_s), (0.075, -0.024, dz_s)],
                     (0.014, 0.007), 8, 'leather', C_LEATHER_DARK, (True, True), True)
            # Encrusted reef barnacles on shield face!
            _barnacle_cluster(dshield, (0.14, 0.042, 0.10), (0.15, 1.0, 0.1), 4, 0.95, "Forearm_L")
            _barnacle_cluster(dshield, (-0.15, 0.042, -0.09), (-0.1, 1.0, -0.1), 3, 0.85, "Forearm_L")
    meshes.append(build_skinned(dshield, arm_obj))

    # ---- 6. Drowned_PowderKeg (16-sided smooth coopered red explosive barrel + iron hoops + glowing fuse cord!)
    dkeg = MB('Drowned_PowderKeg', seed=45)
    with wctx(dkeg, "Chest"):
        MK = T(0.245, 1.605, 0.015) @ R('Y', -20) @ R('Z', -16) @ R('X', 74)
        with xf(dkeg, MK):
            # 16-sided coopered red explosive barrel with subtle stave ridges & recessed chime rims!
            def stave_rib(a):
                return (1.0 + 0.018 * abs(cos(8.0 * a)), 0.0, 0.0)
            keg_secs = [
                ring_ellipse((0, -0.225, 0), 0.144, 0.144, 16, mod_fn=stave_rib),
                ring_ellipse((0, -0.195, 0), 0.155, 0.155, 16, mod_fn=stave_rib),
                ring_ellipse((0, -0.110, 0), 0.180, 0.180, 16, mod_fn=stave_rib),
                ring_ellipse((0,  0.000, 0), 0.192, 0.192, 16, mod_fn=stave_rib),
                ring_ellipse((0,  0.110, 0), 0.180, 0.180, 16, mod_fn=stave_rib),
                ring_ellipse((0,  0.195, 0), 0.155, 0.155, 16, mod_fn=stave_rib),
                ring_ellipse((0,  0.225, 0), 0.144, 0.144, 16, mod_fn=stave_rib),
            ]
            loft(dkeg, keg_secs, 'cloth_secondary', C_KEG_RED, True, (True, True), True,
                 scols=[mul(C_KEG_RED, 0.80), mul(C_KEG_RED, 0.90), C_KEG_RED, mul(C_KEG_RED, 1.08),
                        C_KEG_RED, mul(C_KEG_RED, 0.90), mul(C_KEG_RED, 0.80)])
            # Raised chime rings on both wooden keg ends
            for ey in (-0.222, 0.222):
                torus(dkeg, (0.0, ey, 0.0), 0.141, 0.009, segs=16, psegs=6, mat='leather', col=C_WOOD_ROT, smooth=True)
            # 4 smooth 16-sided iron barrel hoops with rivets
            for hy, hr in ((-0.172, 0.168), (-0.074, 0.191), (0.074, 0.191), (0.172, 0.168)):
                h_secs = [
                    ring_ellipse((0, hy - 0.018, 0), hr, hr, 16),
                    ring_ellipse((0, hy,         0), hr + 0.004, hr + 0.004, 16),
                    ring_ellipse((0, hy + 0.018, 0), hr, hr, 16),
                ]
                loft(dkeg, h_secs, 'iron', C_IRON, True, (True, True), True,
                     scols=[C_IRON, mul(C_IRON, 1.15), C_IRON])
                for rk in range(6):
                    ra = 2.0 * pi * rk / 6.0
                    ellipsoid(dkeg, (cos(ra) * (hr + 0.005), hy, sin(ra) * (hr + 0.005)),
                              (0.007, 0.007, 0.007), 'iron', mul(C_IRON, 1.25), segs=6, rings=4, smooth=True)

            # Glowing fiery powder fissures along explosive staves & front head!
            tube(dkeg, [(0.0, -0.075, -0.190), (0.014, 0.0, -0.196), (-0.010, 0.075, -0.190)],
                 [0.008, 0.016, 0.008], 8, 'emissive_keg', C_KEG_GLOW, (True, True), True,
                 shade_dir=False, cap_poles=(True, True))
            tube(dkeg, [(0.176, -0.055, -0.072), (0.184, 0.015, -0.068), (0.172, 0.075, -0.074)],
                 [0.007, 0.014, 0.007], 8, 'emissive_keg', C_KEG_GLOW, (True, True), True,
                 shade_dir=False, cap_poles=(True, True))

            # Sizzling braided fuse cord curving out of front bung + blazing fiery ember core!
            torus(dkeg, (0.0, 0.226, 0.0), 0.024, 0.007, segs=12, psegs=6, mat='iron', col=C_IRON, smooth=True)
            tube(dkeg, [(0.0, 0.222, 0.0), (0.015, 0.264, -0.020), (0.042, 0.295, -0.054), (0.068, 0.312, -0.095)],
                 [0.014, 0.013, 0.012, 0.011], 8, 'leather', C_WOOD_ROT, (True, True), True)
            ellipsoid(dkeg, (0.072, 0.315, -0.100), (0.040, 0.040, 0.040), 'emissive_keg', C_KEG_GLOW,
                      segs=10, rings=6, smooth=True, shade_dir=False)
            # Radiating fiery fuse sparks
            for sp_d in ((0.038, 0.030, -0.018), (-0.032, 0.038, -0.015), (0.014, -0.028, -0.038)):
                p0 = Vector((0.072, 0.315, -0.100))
                cone(dkeg, p0, p0 + Vector(sp_d), 0.012, 0.002, 6, 'emissive_keg', C_KEG_GLOW, True)
    meshes.append(build_skinned(dkeg, arm_obj))

    return meshes

# ================================================================ 3. TIDECALLER (ABYSSAL SEA-CULTIST)
def _coral_branch(mb, pts, r0, r1, wspec, sides=10):
    """Smooth 10-sided organic tapering branching coral antler with subtle calcified reef nodes & rounded tips."""
    pts = [Vector(p) for p in pts]
    n = len(pts)
    rads = []
    for i in range(n):
        u = i / max(n - 1, 1)
        base_r = r0 + (r1 - r0) * (u ** 0.85)
        # Subtle organic reef swelling nodes along branch
        node = 1.0 + (0.10 * sin(u * pi * 3.0) if 0 < i < n - 1 else 0.0)
        rads.append(base_r * node)
    scols = [mix(C_CORAL_BASE, C_CORAL_TIP, (i / max(n - 1, 1)) ** 0.85) for i in range(n)]
    tube(mb, pts, rads, sides, 'coral', C_CORAL_MID, (True, True), True,
         scols=scols, wspec=wspec, cap_poles=(True, True))

def _fluted_shell_pauldron(mb, center, M_rot, length, width, arch_h, flutes=7, col=C_SHELL, wspec=None):
    """Sculpted fluted giant sea-shell (scallop/nautilus) shoulder pauldron curving organically over shoulder."""
    with xf(mb, T(center) @ M_rot):
        secs = []
        scols = []
        n_rows = 6
        n_cols = 15
        for i in range(n_rows):
            u = i / float(n_rows - 1) # 0 = shell umbo (neck/top), 1 = scalloped outer lip
            # Fan width widens gracefully from shell hinge umbo out to fluted rim
            w = width * (0.28 + 0.72 * sin(u * pi * 0.62))
            x = (u - 0.35) * length
            # Domed longitudinal curve wrapping smoothly over shoulder deltoid
            y_curve = arch_h * sin(u * pi * 0.85) - 0.032 * (u ** 2.2)
            row = []
            for j in range(n_cols):
                v = (j / float(n_cols - 1)) * 2.0 - 1.0 # -1 .. +1 front-to-back
                z = v * w
                # Radial scalloped sea-shell ribs deepening cleanly toward outer rim!
                rib = 0.0095 * (u ** 1.1) * cos(v * flutes * pi * 0.5)
                dom = -0.028 * (v * v) * (0.4 + 0.6 * u)
                row.append(Vector((x, y_curve + dom + rib, z)))
            secs.append(row)
            scols.append(mix(C_SHELL_DARK, C_SHELL_HI, smooth01(u * 0.9)))
        # Build top and slightly offset inner underside for solid sculpted shell thickness
        loft(mb, secs, 'coral', col, closed=False, caps=(False, False), smooth=True, scols=scols, wspec=wspec)
        # Curled scalloped rim lip along the outer edge (last row)
        tube(mb, secs[-1], 0.0085, 8, 'coral', C_SHELL_HI, (True, True), True, wspec=wspec, cap_poles=(True, True))

def build_tidecaller_meshes(arm_obj):
    meshes = []
    body = MB('Tidecaller_Body', seed=70)

    # ---- Flowing 20-sided smooth pleated ankle-length mystic robe + layered shoulder mantle (y = 0.06 .. 1.43)
    with wctx(body, w_coat_skirt):
        def robe_pleat(depth, phase=0.0):
            def fn(a):
                # Soft vertical drapery folds (stronger toward hem, subtle toward waist/chest)
                pl = depth * (0.65 * cos(8.0 * a + phase) + 0.35 * sin(5.0 * a - phase))
                return (1.0 + pl, 0.0, 0.0)
            return fn

        robe_specs = [
            (0.070,  0.010, 0.282, 0.226, 0.06, 0.18, 0.055, C_TINT_LO),
            (0.210,  0.008, 0.264, 0.210, 0.04, 0.18, 0.048, C_TINT_MID),
            (0.380,  0.005, 0.240, 0.188, 0.02, 0.18, 0.038, C_TINT_MID),
            (0.560,  0.002, 0.216, 0.166, 0.00, 0.20, 0.028, C_TINT_MID),
            (0.760,  0.000, 0.194, 0.146, 0.00, 0.22, 0.018, C_TINT_LO),
            (0.955,  0.000, 0.176, 0.132, 0.00, 0.24, 0.010, C_TINT_LO),
            (1.140, -0.008, 0.206, 0.150, 0.04, 0.26, 0.012, C_TINT_MID),
            (1.310, -0.006, 0.232, 0.158, 0.04, 0.28, 0.010, C_TINT_HI),
            (1.422,  0.000, 0.150, 0.120, 0.00, 0.20, 0.000, C_TINT_HI),
        ]
        robe_secs = [
            ring_ellipse((0, yv, zv), rx, rz, 20, front_bias=fb, sq=sq, mod_fn=robe_pleat(pl))
            for yv, zv, rx, rz, fb, sq, pl, _ in robe_specs
        ]
        loft(body, robe_secs, 'cloth_primary', C_TINT_HI, True, (False, True), True,
             scols=[c for *_, c in robe_specs])

        # Wide sea-ochre embroidered lower hem band matching the 20-seg robe pleat wave!
        hem_secs = [
            ring_ellipse((0, 0.064, 0.010), 0.288, 0.232, 20, front_bias=0.06, sq=0.18, mod_fn=robe_pleat(0.055)),
            ring_ellipse((0, 0.110, 0.009), 0.284, 0.228, 20, front_bias=0.05, sq=0.18, mod_fn=robe_pleat(0.052)),
            ring_ellipse((0, 0.152, 0.008), 0.276, 0.220, 20, front_bias=0.04, sq=0.18, mod_fn=robe_pleat(0.048)),
        ]
        loft(body, hem_secs, 'cloth_secondary', C_TINT_HI, True, (True, False), True,
             scols=[C_TINT_LO, C_TINT_HI, C_TINT_MID])

        # Layered draped ceremonial shoulder mantle / capelet (18-sided smooth scalloped edge!)
        def mantle_scallop(a):
            return (1.0 + 0.032 * cos(6.0 * a), -0.022 * abs(cos(3.0 * a)), 0.0)
        mantle_secs = [
            ring_ellipse((0, 1.215, 0.002), 0.256, 0.186, 18, sq=0.22, mod_fn=mantle_scallop),
            ring_ellipse((0, 1.320, 0.000), 0.248, 0.174, 18, sq=0.24),
            ring_ellipse((0, 1.405, 0.002), 0.205, 0.146, 18, sq=0.22),
            ring_ellipse((0, 1.438, 0.004), 0.140, 0.122, 18, sq=0.18),
        ]
        loft(body, mantle_secs, 'cloth_primary', C_TINT_MID, True, (False, False), True,
             scols=[C_TINT_LO, C_TINT_MID, C_TINT_HI, C_TINT_MID])
        # Gold-ochre ceremonial piping tracing the scalloped shoulder mantle hem
        m_rim = mantle_secs[0] + [mantle_secs[0][0]]
        tube(body, m_rim, 0.009, 8, 'cloth_secondary', C_TINT_HI, (False, False), True)

        # Draped rune-inscribed FRONT & BACK ceremonial ritual stoles hugging the pleated robe!
        def build_stole(sign_z):
            # sign_z = -1 for front (-Z), +1 for back (+Z)
            st_specs = [
                (0.18, 0.044, 0.228),
                (0.26, 0.076, 0.218),
                (0.54, 0.080, 0.182),
                (0.84, 0.076, 0.156),
                (0.96, 0.072, 0.148),
                (1.18, 0.084, 0.168),
                (1.36, 0.092, 0.172),
            ]
            st_secs = []
            for sy, sw, sdist in st_specs:
                z_out = sign_z * (sdist + 0.012)
                z_in = sign_z * (sdist - 0.008)
                st_secs.append([
                    Vector((-sw, sy, z_out)),
                    Vector((0.0, sy, z_out + sign_z * 0.008)),
                    Vector(( sw, sy, z_out)),
                    Vector(( sw, sy, z_in)),
                    Vector((-sw, sy, z_in)),
                ])
            loft(body, st_secs, 'cloth_secondary', C_TINT_MID, True, (True, True), True,
                 scols=[C_TINT_LO, C_TINT_MID, C_TINT_HI, C_TINT_MID, C_TINT_LO, C_TINT_HI, C_TINT_HI],
                 cap_poles=(True, True))

        build_stole(-1.0) # Front ritual stole
        build_stole( 1.0) # Back ritual stole

        # Glowing carved aquamarine sea-runes down FRONT stole & BACK stole!
        front_runes = [
            # Upper chest trident glyph
            [(-0.044, 1.28, -0.186), (0.0, 1.25, -0.190), (0.044, 1.28, -0.186)],
            [( 0.000, 1.30, -0.188), (0.0, 1.15, -0.182)],
            [(-0.036, 1.19, -0.184), (0.036, 1.19, -0.184)],
            # Mid diamond tide-rune
            [(0.0, 0.85, -0.172), (0.036, 0.80, -0.174), (0.0, 0.75, -0.178), (-0.036, 0.80, -0.174), (0.0, 0.85, -0.172)],
            # Lower wave-trident rune
            [(-0.042, 0.56, -0.196), (0.0, 0.59, -0.196), (0.042, 0.56, -0.196)],
            [( 0.000, 0.58, -0.196), (0.0, 0.44, -0.208)],
            [(-0.032, 0.48, -0.204), (0.032, 0.48, -0.204)],
        ]
        for r_pts in front_runes:
            tube(body, r_pts, 0.0085, 6, 'emissive_sea', C_AQUA_GLOW, (True, True), True,
                 shade_dir=False, cap_poles=(True, True))

        back_runes = [
            [(-0.040, 1.26, 0.186), (0.0, 1.22, 0.190), (0.040, 1.26, 0.186)],
            [( 0.000, 1.28, 0.188), (0.0, 1.14, 0.182)],
            [( 0.000, 0.78, 0.176), (0.032, 0.73, 0.180), (0.0, 0.68, 0.184), (-0.032, 0.73, 0.180), (0.0, 0.78, 0.176)],
            [( 0.000, 0.56, 0.196), (0.0, 0.42, 0.210)],
        ]
        for r_pts in back_runes:
            tube(body, r_pts, 0.0080, 6, 'emissive_sea', C_AQUA_GLOW, (True, True), True,
                 shade_dir=False, cap_poles=(True, True))

        # Braided twin-strand kelp cord ritual belt + glowing aquamarine sea-orb medallion in coral bezel!
        for strand_i in (0, 1):
            ph = strand_i * pi
            belt_pts = []
            for k in range(25):
                a = 2.0 * pi * k / 24.0
                twist = 7.0 * a + ph
                r_off = 0.009 * cos(twist)
                y_off = 0.009 * sin(twist)
                belt_pts.append(((0.192 + r_off) * cos(a), 0.965 + y_off, (0.148 + r_off) * sin(a)))
            tube(body, belt_pts, 0.013, 8, 'coral', C_KELP if strand_i == 0 else C_KELP_HI, (False, False), True)
        # Hanging braided kelp cord ends off belt front-left
        _seaweed_tuft(body, (-0.085, 0.945, -0.152), 0.26, 2, w_coat_skirt)
        # Carved coral bezel ring + glowing aquamarine sea-orb medallion
        torus(body, (0.0, 0.965, -0.160), 0.044, 0.012, segs=16, psegs=8, mat='coral', col=C_SHELL,
              M=R('X', 90), smooth=True)
        ellipsoid(body, (0.0, 0.965, -0.164), (0.036, 0.038, 0.024), 'emissive_sea', C_AQUA_GLOW,
                  segs=12, rings=6, smooth=True, shade_dir=False)

    # ---- Smooth sea-wrapped boots cleanly planted at y = 0.0 under pleated robe hem
    for side in ("L", "R"):
        sx = -1.0 if side == "L" else 1.0
        wl = w_leg(side)
        with wctx(body, wl):
            fx = sx * 0.118
            _build_buccaneer_boot_vamp(body, fx, sx, C_MASK_DARK, C_LEATHER_DARK, segs=12)
            tube(body, [(fx, 0.075, 0.01), (fx, 0.45, -0.01)], [0.052, 0.056], 10, 'leather', C_MASK_DARK,
                 (False, False), True)

    # ---- Sculpted Fluted Sea-Shell Shoulder Pauldrons + Multi-Pronged Branching Coral!
    # Left pauldron: huge sculpted fluted scallop sea-shell mantle + branching shoulder coral antlers + kelp!
    with wctx(body, "Shoulder_L"):
        _fluted_shell_pauldron(body, (-0.232, 1.422, 0.002), R('X', -12) @ R('Z', 24) @ R('Y', 180),
                               length=0.235, width=0.125, arch_h=0.062, flutes=7, col=C_SHELL, wspec="Shoulder_L")
        _barnacle_cluster(body, (-0.255, 1.456, -0.014), (-0.4, 0.9, -0.2), 5, 1.10, "Shoulder_L")
        # Multi-pronged branching coral rising from left shell pauldron
        _coral_branch(body, [(-0.235, 1.442, 0.018), (-0.295, 1.515, 0.036), (-0.348, 1.588, 0.022), (-0.372, 1.635, 0.008)],
                      0.024, 0.007, "Shoulder_L", sides=10)
        _coral_branch(body, [(-0.285, 1.500, 0.032), (-0.335, 1.525, -0.038), (-0.365, 1.560, -0.062)],
                      0.017, 0.006, "Shoulder_L", sides=10)
        _coral_branch(body, [(-0.320, 1.552, 0.028), (-0.295, 1.605, 0.068)],
                      0.014, 0.006, "Shoulder_L", sides=8)
        _seaweed_tuft(body, (-0.285, 1.365, 0.035), 0.28, 3, "Shoulder_L")

    # Right pauldron: twin overlapping sculpted fluted sea-shell armor plates + barnacles!
    with wctx(body, "Shoulder_R"):
        _fluted_shell_pauldron(body, (0.218, 1.418, 0.004), R('X', -12) @ R('Z', -20),
                               length=0.205, width=0.112, arch_h=0.054, flutes=6, col=C_SHELL, wspec="Shoulder_R")
        _fluted_shell_pauldron(body, (0.256, 1.350, 0.006), R('X', -10) @ R('Z', -36),
                               length=0.162, width=0.094, arch_h=0.040, flutes=5, col=mul(C_SHELL, 0.88), wspec="Shoulder_R")
        _barnacle_cluster(body, (0.230, 1.448, -0.018), (0.3, 0.9, -0.2), 4, 0.92, "Shoulder_R")

    # ---- Smooth 14-sided Flared Mystic Sleeves, Gnarled Forearms & Articulated Ritual Hands with Glowing Rings!
    for side in ("L", "R"):
        sx = -1.0 if side == "L" else 1.0
        sh, ua, el, wr, ft = [Vector(q) for q in _arm_pts(sx)]
        wa = w_arm(side)
        with wctx(body, wa):
            # Smooth 14-sided flared bell robe sleeve down to mid-forearm
            sl_pts = [ua.lerp(sh, 0.18), ua, ua.lerp(el, 0.45), el, el.lerp(wr, 0.28), el.lerp(wr, 0.52)]
            sl_rads = [0.082, 0.090, 0.086, 0.095, 0.106, 0.118]
            tube(body, sl_pts, sl_rads, 14, 'cloth_primary', C_TINT_HI, (True, True), True,
                 scols=[C_TINT_MID, C_TINT_HI, C_TINT_MID, C_TINT_MID, C_TINT_LO])
            # Sea-ochre embroidered cuff trim ring on sleeve flare
            tube(body, [el.lerp(wr, 0.42), el.lerp(wr, 0.54)], [0.116, 0.122], 14,
                 'cloth_secondary', C_TINT_HI, (False, True), True)
            # Weathered briny forearm + sculpted coral/shell wrist bracer
            tube(body, [el.lerp(wr, 0.40), el.lerp(wr, 0.72), wr], [0.048, 0.043, 0.038], 10,
                 'bone', C_MASK_DARK, (False, True), True, scols=[C_MASK_DARK, C_MASK])
            tube(body, [el.lerp(wr, 0.78), el.lerp(wr, 0.88), wr], [0.050, 0.053, 0.048], 12,
                 'coral', C_SHELL, (True, True), True, scols=[C_SHELL_DARK, C_SHELL_HI])
        # Gnarled articulated ritual hand with glowing aquamarine finger rings & dorsal rune glyph!
        sculpt_hand(body, wr, ft, side, style='tidecaller')

    # ---- Smooth 16-sided Hooded Cowl, Carved Sea-Stone Ritual Mask & Multi-Pronged Branching Coral Antlers! (y = 1.48 .. 1.92)
    with wctx(body, "Head"):
        # Smooth 16-sided draped mystic cowl hood wrapping cranium & neck
        def cowl_fold(a):
            return (1.0 + 0.025 * cos(5.0 * a), 0.0, 0.0)
        hood = [
            ring_ellipse((0, 1.438, 0.015), 0.126, 0.118, 16, sq=0.22),
            ring_ellipse((0, 1.520, 0.015), 0.132, 0.136, 16, sq=0.22, mod_fn=cowl_fold),
            ring_ellipse((0, 1.615, 0.015), 0.136, 0.144, 16, sq=0.22, mod_fn=cowl_fold),
            ring_ellipse((0, 1.692, 0.018), 0.126, 0.134, 16, sq=0.18),
            ring_ellipse((0, 1.736, 0.024), 0.092, 0.104, 16, sq=0.15),
            ring_ellipse((0, 1.758, 0.034), 0.040, 0.046, 16, sq=0.12),
        ]
        loft(body, hood, 'cloth_primary', C_TINT_MID, True, (True, True), True,
             scols=[C_TINT_LO, C_TINT_MID, C_TINT_HI, C_TINT_HI, C_TINT_MID, C_TINT_LO], cap_poles=(False, True))
        # Thick sculpted rolled front cowl rim framing the carved ritual mask!
        cowl_rim = [
            (-0.088, 1.495, -0.072),
            (-0.118, 1.565, -0.082),
            (-0.114, 1.650, -0.082),
            (-0.068, 1.714, -0.080),
            ( 0.000, 1.732, -0.086),
            ( 0.068, 1.714, -0.080),
            ( 0.114, 1.650, -0.082),
            ( 0.118, 1.565, -0.082),
            ( 0.088, 1.495, -0.072),
        ]
        tube(body, cowl_rim, 0.018, 10, 'cloth_secondary', C_TINT_MID, (True, True), True, cap_poles=(True, True))

        # Carved Weathered Sea-Stone Ritual Mask (front face sits cleanly at z = -0.130 so eyes & runes blaze proud!)
        def mask_carve(y_val):
            def fn(a):
                front = max(0.0, -sin(a))
                cheek = exp(-((abs(abs(a + pi * 0.5) - 0.52)) ** 2) / 0.10) if sin(a) < 0 else 0.0
                dz = -0.004 * (front ** 2.0)
                if 1.650 <= y_val <= 1.685:
                    dz -= 0.006 * (front ** 1.4)
                return (1.0 - 0.05 * cheek, 0.0, dz)
            return fn

        mask_specs = [
            (1.494, -0.084, 0.032, 0.022, C_MASK_DARK),
            (1.528, -0.088, 0.056, 0.030, C_MASK_DARK),
            (1.576, -0.090, 0.076, 0.036, C_MASK),
            (1.622, -0.090, 0.082, 0.038, C_MASK_HI),
            (1.666, -0.086, 0.076, 0.036, C_MASK),
            (1.702, -0.082, 0.050, 0.026, C_MASK_DARK),
        ]
        mask_secs = [
            ring_ellipse((0.0, yv, zv), rx, rz, 14, front_bias=0.10, sq=0.22, mod_fn=mask_carve(yv))
            for yv, zv, rx, rz, _ in mask_specs
        ]
        loft(body, mask_secs, 'bone', C_MASK, True, (True, True), True,
             scols=[c for *_, c in mask_specs], cap_poles=(True, True))

        # Carved overhanging brow crest & sculpted sea-stone nasal ridge
        tube(body, [
            (-0.072, 1.650, -0.112), (-0.038, 1.664, -0.130), (0.0, 1.672, -0.138),
            ( 0.038, 1.664, -0.130), ( 0.072, 1.650, -0.112),
        ], [0.009, 0.013, 0.015, 0.013, 0.009], 8, 'bone', C_MASK_HI, (True, True), True, cap_poles=(True, True))
        tube(body, [(0.0, 1.648, -0.134), (0.0, 1.608, -0.144), (0.0, 1.564, -0.138), (0.0, 1.538, -0.126)],
             [(0.011, 0.009), (0.012, 0.011), (0.010, 0.010), (0.006, 0.007)], 8,
             'bone', C_MASK_DARK, (True, True), True, cap_poles=(True, True))

        # Recessed glowing aquamarine rune eyes, cheek rune slits & forehead diamond crest (boldly proud of mask face!)
        for sx in (-1.0, 1.0):
            with xf(body, T(sx * 0.038, 1.618, -0.132) @ R('Y', -sx * 18) @ R('Z', -sx * 15)):
                # Recessed dark carved eye socket frame
                ellipsoid(body, (0.0, 0.0, 0.002), (0.026, 0.014, 0.008), 'bone', C_SOCKET,
                          segs=10, rings=5, smooth=True, shade_dir=False)
                # Glowing aquamarine rune eye lens!
                ellipsoid(body, (0.0, 0.0, -0.007), (0.019, 0.009, 0.007), 'emissive_sea', C_AQUA_GLOW,
                          segs=10, rings=5, smooth=True, shade_dir=False)
            # Glowing carved cheek glyph below each eye
            tube(body, [(sx * 0.025, 1.578, -0.135), (sx * 0.048, 1.558, -0.124)],
                 0.0052, 6, 'emissive_sea', C_AQUA_GLOW, (True, True), True, shade_dir=False, cap_poles=(True, True))
        # Forehead glowing aquamarine rune crest (diamond + glowing center jewel)
        tube(body, [
            (0.0, 1.688, -0.138), (0.019, 1.666, -0.144), (0.0, 1.644, -0.145),
            (-0.019, 1.666, -0.144), (0.0, 1.688, -0.138),
        ], 0.0058, 6, 'emissive_sea', C_AQUA_GLOW, (False, False), True, shade_dir=False)
        ellipsoid(body, (0.0, 1.666, -0.146), (0.010, 0.014, 0.008), 'emissive_sea', C_AQUA_GLOW,
                  segs=8, rings=5, smooth=True, shade_dir=False)

        # Flowing kelp beard tendrils draping from beneath mask jaw
        _seaweed_tuft(body, (0.0, 1.500, -0.112), 0.18, 4, "Head")

        # ICONIC MULTI-PRONGED SMOOTH ORGANIC BRANCHING CORAL ANTLERS! (10-sided smooth + secondary forks, max y <= 1.93 m!)
        # Right major sweeping staghorn antler + 3 branching sub-forks
        _coral_branch(body, [
            (0.052, 1.688, -0.022),
            (0.112, 1.755, -0.012),
            (0.165, 1.832,  0.008),
            (0.198, 1.908,  0.028),
        ], 0.030, 0.008, "Head", sides=10)
        _coral_branch(body, [
            (0.112, 1.755, -0.012),
            (0.172, 1.792, -0.044),
            (0.222, 1.844, -0.062),
            (0.244, 1.878, -0.058),
        ], 0.021, 0.007, "Head", sides=10)
        _coral_branch(body, [
            (0.178, 1.798, -0.046),
            (0.215, 1.785, -0.088),
        ], 0.013, 0.006, "Head", sides=8) # secondary coral fork!
        _coral_branch(body, [
            (0.152, 1.820,  0.006),
            (0.126, 1.878, -0.032),
            (0.116, 1.912, -0.052),
        ], 0.017, 0.006, "Head", sides=10)

        # Center-right curved crest coral tine + secondary fork
        _coral_branch(body, [
            (0.014, 1.724, -0.046),
            (0.038, 1.798, -0.056),
            (0.068, 1.868, -0.040),
        ], 0.022, 0.007, "Head", sides=10)
        _coral_branch(body, [
            (0.036, 1.792, -0.055),
            (0.004, 1.844, -0.072),
        ], 0.013, 0.006, "Head", sides=8)

        # Left counter-balancing asymmetric splayed coral antlers + secondary forks!
        _coral_branch(body, [
            (-0.062, 1.685, -0.016),
            (-0.124, 1.748,  0.004),
            (-0.164, 1.832,  0.022),
            (-0.184, 1.884,  0.034),
        ], 0.027, 0.008, "Head", sides=10)
        _coral_branch(body, [
            (-0.115, 1.738,  0.002),
            (-0.178, 1.768, -0.036),
            (-0.214, 1.815, -0.052),
        ], 0.019, 0.007, "Head", sides=10)
        _coral_branch(body, [
            (-0.168, 1.762, -0.032),
            (-0.206, 1.748, -0.074),
        ], 0.012, 0.005, "Head", sides=8) # secondary coral fork!
        _coral_branch(body, [
            (-0.055, 1.710,  0.034),
            (-0.090, 1.785,  0.074),
            (-0.105, 1.838,  0.095),
        ], 0.018, 0.007, "Head", sides=10)

        # Calcified coral crown base ridge & barnacles hugging brow
        _barnacle_cluster(body, (0.0, 1.716, -0.078), (0.0, 0.85, -0.5), 5, 0.88, "Head")

    meshes.append(build_skinned(body, arm_obj))
    return meshes

# ================================================================ export pipeline
def export_character(outdir, filename, arm_name, builder_fn):
    random.seed(SEED)
    np.random.seed(SEED)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    make_materials()
    arm_obj = make_armature(arm_name)
    results = builder_fn(arm_obj)
    total = sum(t for _, t in results)
    print(f"=== {filename} ({total} total tris, {len(results)} meshes, {len(arm_obj.data.bones)} bones) ===")
    for ob, tris in results:
        bb = [ob.matrix_world @ Vector(b) for b in ob.bound_box]
        # Convert Blender Z-up back to Godot Y-up for readable bounds printout
        ys = [v.z for v in bb]
        print(f"  {ob.name:<22s} {tris:5d} tris   godot_y=[{min(ys):.3f}, {max(ys):.3f}]")
    char_dir = os.path.join(outdir, 'characters')
    os.makedirs(char_dir, exist_ok=True)
    path = os.path.join(char_dir, filename)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        export_yup=True,
        export_apply=False,
        export_skins=True,
        export_all_influences=False,
        export_vertex_color='MATERIAL',
        export_all_vertex_colors=False,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
        export_extras=False,
        export_tangents=True,
    )
    print("wrote", path)

def main():
    argv = sys.argv
    outdir = argv[-1] if '--' in argv else os.path.join(os.getcwd(), 'assets', 'generated')
    export_character(outdir, 'pirate.glb', 'Armature_Pirate', build_pirate_meshes)
    export_character(outdir, 'drowned.glb', 'Armature_Drowned', build_drowned_meshes)
    export_character(outdir, 'tidecaller.glb', 'Armature_Tidecaller', build_tidecaller_meshes)

if __name__ == '__main__':
    main()
