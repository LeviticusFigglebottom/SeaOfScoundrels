# Sea of Scoundrels: procedural stylized character generator.
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
from math import sin, cos, pi, sqrt, radians
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
C_SHIRT = srgb('#efe2c2')
C_TROUSER = srgb('#453d38')
C_LEATHER = srgb('#5a3520')
C_LEATHER_DARK = srgb('#362015')
C_LEATHER_LIGHT = srgb('#7e4e2e')
C_HAIR = srgb('#4a2c1a')
C_HAIR_LIGHT = srgb('#6b4126')
C_BRASS = srgb('#e8b546')
C_IRON = srgb('#3d424c')
C_EYE_WHITE = srgb('#f6f1e4')
C_EYE_DARK = srgb('#1a1614')

# Neutral shaded cloth base for tintable primary/secondary materials (tints multiply cleanly in Godot)
C_TINT_HI = srgb('#f5f3ee')
C_TINT_MID = srgb('#dcd8d0')
C_TINT_LO = srgb('#b5afa5')

# Drowned palette
C_BONE = srgb('#dfd5be')
C_BONE_DARK = srgb('#9e9278')
C_BONE_GREEN = srgb('#b9bf9e')
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
C_ROBE_DEEP = srgb('#124a59')
C_ROBE_TRIM = srgb('#d4a94e')
C_CORAL_BASE = srgb('#d94646')
C_CORAL_MID = srgb('#f07254')
C_CORAL_TIP = srgb('#ffc285')
C_SHELL = srgb('#7d9c99')
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
        # Distance along UpperArm -> Forearm -> Hand
        tu = proj(p, ua_p, el_p)
        tf = proj(p, el_p, wr_p)
        du = (p - ua_p.lerp(el_p, tu)).length
        df = (p - el_p.lerp(wr_p, tf)).length
        dh = (p - wr_p.lerp(ft_p, proj(p, wr_p, ft_p))).length
        # Elbow blend zone
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
        self.faces.append(tuple(idx))
        self.fmat.append(mat)
        self.fsm.append(smooth)
        self.fcol.append(col)
        self.fuv.append(uvs)

    def fp(self, pts, mat, col, inside=None, wspec=None):
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
        self.f([self.v(p, wspec) for p in pts], mat, col, uvs, False)

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
    """Bevelled painterly box centred at c."""
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

def loft(mb, secs, mat, col, closed=True, caps=(True, True), smooth=False,
         scols=None, flip=None, wspec=None, shade_dir=True):
    """Connect consecutive cross-section rings with painterly directional shading."""
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
    for i in range(n - 1):
        base_c = scols[i] if scols else col
        for j in range(ne):
            j1 = (j + 1) % k
            idx = [ids[i][j], ids[i][j1], ids[i + 1][j1], ids[i + 1][j]]
            uvs = [
                (L[i] * SU + o[0], W[i][j] * SV + o[1]),
                (L[i] * SU + o[0], W[i][j + 1] * SV + o[1]),
                (L[i + 1] * SU + o[0], W[i + 1][j + 1] * SV + o[1]),
                (L[i + 1] * SU + o[0], W[i + 1][j] * SV + o[1]),
            ]
            if flip:
                idx = idx[::-1]
                uvs = uvs[::-1]
            keep, kuv = [], []
            for a, b in zip(idx, uvs):
                if all((mb.verts[a] - mb.verts[q]).length > 1e-6 for q in keep):
                    keep.append(a)
                    kuv.append(b)
            if len(keep) >= 3:
                fc = base_c
                if shade_dir:
                    nrm = newell([mb.verts[q] for q in keep])
                    if nrm.length > 1e-7:
                        nrm.normalize()
                        # Painterly top-warm / under-cool shading
                        f = 0.90 + 0.14 * nrm.y - 0.05 * nrm.z
                        fc = mul(base_c, max(0.72, min(1.12, f)))
                mb.f(keep, mat, fc, kuv, smooth)
    if closed and caps[0] and n > 1:
        mb.fp(secs[0], mat, mul(scols[0] if scols else col, 0.85), cents[1], wspec)
    if closed and caps[1] and n > 1:
        mb.fp(secs[-1], mat, mul(scols[-1] if scols else col, 1.04), cents[-2], wspec)

def ring_ellipse(c, rx, rz, segs=10, front_bias=0.0, sq=0.0, rot_y=0.0, tilt_x=0.0, tilt_z=0.0):
    """Create a horizontal sculpted cross-section ring around center c (Godot coords)."""
    pts = []
    c0 = Vector(c)
    M = R('Y', rot_y) @ R('X', tilt_x) @ R('Z', tilt_z)
    for k in range(segs):
        a = 2.0 * pi * k / segs
        ca, sa = cos(a), sin(a)
        # Optional superellipse squaring (for chunky boots, shoulders, jaws)
        if sq > 0.0:
            p = 1.0 - 0.35 * sq
            ca = math.copysign(abs(ca) ** p, ca)
            sa = math.copysign(abs(sa) ** p, sa)
        z = sa * rz
        if z < 0.0 and front_bias != 0.0:
            z *= (1.0 + front_bias)
        pts.append(c0 + (M @ Vector((ca * rx, 0.0, z))))
    return pts

def tube(mb, path, rad, sides, mat, col, caps=(True, True), smooth=False, scols=None, wspec=None):
    path = [Vector(p) for p in path]
    n = len(path)
    rads = rad if isinstance(rad, (list, tuple)) else [rad] * n
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
    loft(mb, secs, mat, col, True, caps, smooth, scols=scols, wspec=wspec)

def ellipsoid(mb, c, radii, mat, col, segs=8, rings=5, M=None, smooth=False, wspec=None):
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
    # Add poles via tiny rings
    bot = [X @ Vector((rx * 0.03 * cos(2 * pi * k / segs), -ry, rz * 0.03 * sin(2 * pi * k / segs)))
           for k in range(segs)]
    top = [X @ Vector((rx * 0.03 * cos(2 * pi * k / segs), ry, rz * 0.03 * sin(2 * pi * k / segs)))
           for k in range(segs)]
    loft(mb, [bot] + secs + [top], mat, col, True, (True, True), smooth, wspec=wspec)

def cone(mb, base, tip, r0, r1, segs, mat, col, smooth=False, wspec=None):
    tube(mb, [base, tip], [r0, max(r1, 0.002)], segs, mat, col, (True, r1 > 0.003), smooth, wspec=wspec)

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
    return (a * (1 - FX) + b * FX) * (1 - FY) + (c * (1 - FX) + d * FX) * FY

def make_image(name, arr):
    h, w = arr.shape[:2]
    rgba = np.ones((h, w, 4), dtype=np.float32)
    rgba[..., :3] = np.clip(arr, 0.0, 1.0)
    img = bpy.data.images.new(name, w, h, alpha=False)
    img.pixels.foreach_set(rgba.ravel())
    img.file_format = 'PNG'
    img.pack()
    return img

def tex_cloth(rs):
    w = h = 256
    yy, xx = np.mgrid[0:h, 0:w] / float(w)
    weave = 0.96 + 0.04 * np.sin(xx * 2 * pi * 64) * np.sin(yy * 2 * pi * 64)
    slub = 0.95 + 0.08 * tile_noise(rs, w, h, 8, 24) + 0.05 * tile_noise(rs, w, h, 24, 8)
    blot = 0.93 + 0.11 * tile_noise(rs, w, h, 5, 5)
    v = np.clip(weave * slub * blot, 0.72, 1.0)
    return np.stack([v, v * 0.99, v * 0.97], axis=-1)

def tex_leather(rs):
    w = h = 256
    pebble = tile_noise(rs, w, h, 28, 28) * 0.55 + tile_noise(rs, w, h, 64, 64) * 0.45
    crease = tile_noise(rs, w, h, 6, 14)
    v = 0.80 + 0.16 * pebble + 0.10 * (crease - 0.5)
    v = np.clip(v, 0.65, 1.0)
    return np.stack([v, v * 0.97, v * 0.93], axis=-1)

def tex_bone(rs):
    w = h = 256
    grain = tile_noise(rs, w, h, 6, 36) * 0.5 + tile_noise(rs, w, h, 18, 18) * 0.3 + tile_noise(rs, w, h, 48, 48) * 0.2
    pits = np.clip((0.26 - tile_noise(rs, w, h, 40, 40)) * 4.5, 0.0, 1.0) * 0.18
    v = np.clip(0.84 + 0.18 * (grain - 0.5) - pits, 0.62, 1.0)
    return np.stack([v, v * 0.99, v * 0.94], axis=-1)

MATS = {}

def make_materials():
    MATS.clear()
    rs = np.random.RandomState(SEED)
    img_cloth = make_image('char_cloth', tex_cloth(rs))
    img_leather = make_image('char_leather', tex_leather(rs))
    img_bone = make_image('char_bone', tex_bone(rs))

    def mk(key, mat_name, tex=None, rough=0.8, metal=0.0, emit=0.0, emit_col=(0.2, 1.0, 0.8, 1.0), two=False):
        m = bpy.data.materials.new(mat_name)
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

    mk('skin', 'mat_skin', None, rough=0.72)
    mk('cloth_base', 'mat_cloth_base', img_cloth, rough=0.88, two=True)
    mk('cloth_primary', 'mat_cloth_primary', img_cloth, rough=0.86, two=True)
    mk('cloth_secondary', 'mat_cloth_secondary', img_cloth, rough=0.85, two=True)
    mk('leather', 'mat_leather', img_leather, rough=0.62)
    mk('brass', 'mat_brass', None, rough=0.30, metal=0.82)
    mk('iron', 'mat_iron', None, rough=0.48, metal=0.60)
    mk('hair', 'mat_hair', None, rough=0.86)
    mk('bone', 'mat_bone', img_bone, rough=0.78)
    mk('coral', 'mat_coral', img_bone, rough=0.68, two=True)
    mk('emissive_sea', 'mat_emissive_sea', None, rough=0.25, emit=3.2, emit_col=(0.20, 1.0, 0.78, 1.0))
    mk('emissive_keg', 'mat_emissive_keg', None, rough=0.30, emit=3.0, emit_col=(1.0, 0.34, 0.08, 1.0))

def build_skinned(mb, arm_obj):
    me = bpy.data.meshes.new(mb.name)
    me.from_pydata([conv(v) for v in mb.verts], [], mb.faces)
    names = sorted(set(mb.fmat))
    for n in names:
        me.materials.append(MATS[n])
    mi = {n: i for i, n in enumerate(names)}
    uvl = me.uv_layers.new(name='UVMap')
    ca = me.color_attributes.new('Color', 'FLOAT_COLOR', 'CORNER')
    uvs = []
    cols = []
    for fi, f in enumerate(mb.faces):
        c = mb.fcol[fi]
        for k in range(len(f)):
            uvs.extend(mb.fuv[fi][k])
            cc = c[k] if isinstance(c, list) else c
            cols.extend((cc[0], cc[1], cc[2], 1.0))
    uvl.data.foreach_set('uv', uvs)
    ca.data.foreach_set('color', cols)
    me.polygons.foreach_set('material_index', [mi[m] for m in mb.fmat])
    me.polygons.foreach_set('use_smooth', mb.fsm)
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
    return ob, mb.tris()

# ================================================================ 1. PIRATE
def _build_pirate_boot_and_leg(mb, side):
    sx = -1.0 if side == "L" else 1.0
    wl = w_leg(side)
    with wctx(mb, wl):
        # Chunky boot sole + foot planted cleanly at y = 0.0
        # Sculpted thick sole & leather vamp pointing toward -Z
        fx = sx * 0.118
        # Boot sole slab (y = 0.0 .. 0.032)
        cbox(mb, (fx, 0.016, -0.055), (0.118, 0.032, 0.255), 'leather', C_LEATHER_DARK, 0.008)
        # Heel block (y = 0.0 .. 0.042)
        cbox(mb, (fx, 0.021, 0.042), (0.110, 0.042, 0.088), 'leather', C_LEATHER_DARK, 0.007)
        # Chunky upturned toe & vamp loft from heel to toe
        foot_secs = [
            ring_ellipse((fx, 0.075, 0.055), 0.052, 0.044, 8, sq=0.45),
            ring_ellipse((fx, 0.080, -0.025), 0.058, 0.052, 8, sq=0.45),
            ring_ellipse((fx, 0.068, -0.115), 0.056, 0.040, 8, sq=0.55),
            ring_ellipse((fx, 0.054, -0.178), 0.040, 0.024, 8, sq=0.60),
        ]
        # Rearrange into vertical rings along -Z by building cleanly around Y-Z
        cbox(mb, (fx, 0.062, -0.068), (0.108, 0.076, 0.205), 'leather', C_LEATHER, 0.022)
        cbox(mb, (fx, 0.056, -0.145), (0.098, 0.064, 0.095), 'leather', mul(C_LEATHER, 1.08), 0.024)
        # Brass boot strap & buckle on outer side
        cbox(mb, (fx + sx * 0.058, 0.115, -0.005), (0.018, 0.032, 0.046), 'brass', C_BRASS, 0.004)

        # Lower boot shaft -> flared rolled pirate cuff (y = 0.07 .. 0.41)
        shaft = [
            ring_ellipse((fx, 0.075, 0.015), 0.055, 0.060, 8, sq=0.3),
            ring_ellipse((fx, 0.18, 0.010), 0.060, 0.065, 8, sq=0.25),
            ring_ellipse((fx, 0.29, 0.002), 0.068, 0.072, 8, sq=0.25),
            ring_ellipse((fx, 0.34, 0.0), 0.074, 0.078, 8, sq=0.25),
        ]
        loft(mb, shaft, 'leather', C_LEATHER, True, (False, True), False,
             scols=[C_LEATHER_DARK, C_LEATHER, mul(C_LEATHER, 1.05)])

        # Folded-over thick pirate boot cuff (iconic silhouette!)
        cuff = [
            ring_ellipse((fx, 0.30, 0.0), 0.088, 0.092, 8, sq=0.35),
            ring_ellipse((fx, 0.365, -0.005), 0.092, 0.096, 8, sq=0.35),
            ring_ellipse((fx, 0.415, -0.008), 0.084, 0.088, 8, sq=0.3),
            ring_ellipse((fx, 0.412, -0.005), 0.068, 0.072, 8, sq=0.2),
        ]
        loft(mb, cuff, 'leather', C_LEATHER_LIGHT, True, (True, False), False,
             scols=[mul(C_LEATHER_LIGHT, 0.88), C_LEATHER_LIGHT, mul(C_LEATHER_LIGHT, 1.08)])

        # Baggy pirate trousers bloused over boot cuff -> knee -> thigh -> hip
        # Extra edge loop around knee (y=0.45) for crisp bending!
        leg = [
            ring_ellipse((fx, 0.40, 0.0), 0.068, 0.070, 8, sq=0.2),
            ring_ellipse((fx, 0.45, -0.010), 0.086, 0.088, 8, sq=0.2),
            ring_ellipse((fx, 0.53, -0.006), 0.094, 0.096, 8, sq=0.2),
            ring_ellipse((fx, 0.67, 0.0), 0.096, 0.100, 8, sq=0.2),
            ring_ellipse((fx, 0.80, 0.0), 0.098, 0.104, 8, sq=0.2),
            ring_ellipse((sx * 0.095, 0.89, 0.0), 0.092, 0.102, 8, sq=0.25),
        ]
        loft(mb, leg, 'cloth_base', C_TROUSER, True, (False, True), False,
             scols=[mul(C_TROUSER, 0.85), C_TROUSER, mul(C_TROUSER, 1.06), C_TROUSER, mul(C_TROUSER, 0.94)])

def _build_pirate_arm_and_hand(mb, side):
    sx = -1.0 if side == "L" else 1.0
    wa = w_arm(side)
    sh, ua, el, wr, ft = [Vector(q) for q in _arm_pts(sx)]
    with wctx(mb, wa):
        # Billowing pirate shirt sleeve from shoulder -> bicep -> elbow -> puffed cuff -> wrist
        path = [
            ua.lerp(sh, 0.25),
            ua,
            ua.lerp(el, 0.42),
            ua.lerp(el, 0.82),
            el,
            el.lerp(wr, 0.22),
            el.lerp(wr, 0.68),
            el.lerp(wr, 0.92),
            wr,
        ]
        rads = [0.072, 0.076, 0.070, 0.062, 0.058, 0.064, 0.070, 0.046, 0.040]
        scols = [
            mul(C_SHIRT, 0.92), C_SHIRT, mul(C_SHIRT, 1.04), mul(C_SHIRT, 0.95),
            mul(C_SHIRT, 0.92), C_SHIRT, mul(C_SHIRT, 1.05), mul(C_SHIRT, 0.86),
        ]
        tube(mb, path, rads, 8, 'cloth_base', C_SHIRT, (True, True), False, scols=scols)

        # Proud leather wrist bracer/cuff band (cleanly outside sleeve to avoid Z-fighting)
        tube(mb, [el.lerp(wr, 0.84), wr], [0.058, 0.054], 8, 'leather', C_LEATHER, (True, True), False)

        # Big expressive sculpted pirate hand! (weighted 100% to Hand_side, matching image_3.png)
        h_dir = (ft - wr).normalized()
        up_ref = Vector((0, 0, -1))
        side_v = h_dir.cross(up_ref).normalized()
        fwd_v = side_v.cross(h_dir).normalized()
        H = Matrix((
            (side_v.x, h_dir.x, fwd_v.x, wr.x),
            (side_v.y, h_dir.y, fwd_v.y, wr.y),
            (side_v.z, h_dir.z, fwd_v.z, wr.z),
            (0.0, 0.0, 0.0, 1.0),
        ))
        with wctx(mb, "Hand_" + side):
            with xf(mb, H):
                # Big chunky palm (~1.35x scale for bold stylized silhouette)
                cbox(mb, (0.0, 0.062, 0.0), (0.062, 0.108, 0.102), 'skin', C_SKIN, 0.018)
                # Slightly curled chunky finger block
                cbox(mb, (-sx * 0.018, 0.138, -0.010), (0.048, 0.072, 0.094), 'skin', C_SKIN_WARM, 0.015,
                     R('Z', sx * 24))
                # Knuckle ridge highlight
                cbox(mb, (sx * 0.026, 0.104, 0.0), (0.018, 0.028, 0.092), 'skin', mul(C_SKIN, 1.08), 0.006)
                # Bold expressive thumb angled forward/inward
                cbox(mb, (-sx * 0.024, 0.072, -0.068), (0.042, 0.066, 0.044), 'skin', C_SKIN_WARM, 0.012,
                     R('X', -32) @ R('Z', sx * 18))

def _build_pirate_head(mb):
    with wctx(mb, "Head"):
        # Sculpted chunky pirate head (y = 1.48 .. 1.73, facing -Z)
        head_secs = [
            ring_ellipse((0, 1.485, 0.005), 0.058, 0.062, 10, sq=0.25),   # under-chin / jaw base
            ring_ellipse((0, 1.520, -0.012), 0.084, 0.095, 10, front_bias=0.14, sq=0.45),  # strong jaw & chin
            ring_ellipse((0, 1.568, -0.008), 0.096, 0.104, 10, front_bias=0.10, sq=0.35),  # cheeks
            ring_ellipse((0, 1.622, -0.006), 0.100, 0.110, 10, front_bias=0.06, sq=0.30),  # brow / temples
            ring_ellipse((0, 1.678, 0.004), 0.098, 0.110, 10, sq=0.25),                    # forehead / cranium
            ring_ellipse((0, 1.718, 0.010), 0.074, 0.084, 10, sq=0.20),                    # crown
            ring_ellipse((0, 1.734, 0.012), 0.034, 0.040, 10, sq=0.15),                    # top of head (~1.734 m)
        ]
        loft(mb, head_secs, 'skin', C_SKIN, True, (True, True), False,
             scols=[C_SKIN_DARK, C_SKIN_WARM, C_SKIN, C_SKIN, mul(C_SKIN, 1.04), C_SKIN])

        # Prominent overhanging brow ridge
        cbox(mb, (0.0, 1.630, -0.100), (0.145, 0.026, 0.036), 'skin', C_SKIN_WARM, 0.008)

        # Chunky beveled pirate nose (slightly proud & warm-tinted)
        cbox(mb, (0.0, 1.588, -0.118), (0.034, 0.052, 0.044), 'skin', C_SKIN_WARM, 0.010, R('X', 14))
        cbox(mb, (0.0, 1.572, -0.132), (0.038, 0.026, 0.028), 'skin', mul(C_SKIN_WARM, 1.06), 0.008)

        # Expressive eyes (recessed shadow + sclera + bold iris/pupil) & chunky angled eyebrows
        for sx in (-1.0, 1.0):
            # Eyebrow (jaunty slight cocked-brow asymmetry!)
            ang = 12.0 if sx > 0 else -18.0
            cbox(mb, (sx * 0.044, 1.634, -0.112), (0.050, 0.016, 0.022), 'hair', C_HAIR, 0.004, R('Z', ang))
            # Sclera & pupil
            cbox(mb, (sx * 0.042, 1.608, -0.102), (0.034, 0.022, 0.016), 'skin', C_EYE_WHITE, 0.004)
            cbox(mb, (sx * 0.042, 1.608, -0.111), (0.016, 0.016, 0.008), 'skin', C_EYE_DARK, 0.002)
            # Cheekbone warm facet
            cbox(mb, (sx * 0.068, 1.574, -0.092), (0.040, 0.028, 0.032), 'skin', C_SKIN_WARM, 0.008)
            # Chunky stylized ears
            cbox(mb, (sx * 0.102, 1.594, 0.006), (0.028, 0.054, 0.036), 'skin', C_SKIN_WARM, 0.008, R('Y', sx * 18))

        # Gold pirate hoop earring on left ear!
        cbox(mb, (-0.112, 1.564, 0.004), (0.012, 0.026, 0.026), 'brass', C_BRASS, 0.004)

        # Subtle mouth crease & chin cleft
        cbox(mb, (0.0, 1.542, -0.104), (0.056, 0.010, 0.012), 'skin', C_SKIN_DARK, 0.002)
        cbox(mb, (0.0, 1.514, -0.104), (0.052, 0.024, 0.026), 'skin', C_SKIN_WARM, 0.008)

        # Sculpted tousled sailor hair cap & sideburns (sits cleanly under hats)
        hair_secs = [
            ring_ellipse((0, 1.580, 0.026), 0.096, 0.096, 8, sq=0.25),
            ring_ellipse((0, 1.655, 0.020), 0.108, 0.114, 8, sq=0.25),
            ring_ellipse((0, 1.712, 0.016), 0.094, 0.100, 8, sq=0.2),
            ring_ellipse((0, 1.740, 0.014), 0.045, 0.050, 8, sq=0.15),
        ]
        loft(mb, hair_secs, 'hair', C_HAIR, True, (True, True), False,
             scols=[C_HAIR, C_HAIR_LIGHT, C_HAIR])
        # Back hair tufts & sideburns
        cbox(mb, (0.0, 1.545, 0.104), (0.140, 0.075, 0.048), 'hair', C_HAIR, 0.014, R('X', -12))
        for sx in (-1.0, 1.0):
            cbox(mb, (sx * 0.094, 1.588, -0.028), (0.024, 0.068, 0.036), 'hair', C_HAIR, 0.006)

def build_pirate_meshes(arm_obj):
    meshes = []

    # ---- 1. Base Body (always visible)
    body = MB('Body', seed=10)
    # Torso: broad barrel-chested sailor trunk (y = 0.84 .. 1.49)
    with wctx(body, w_torso):
        pelvis = [
            ring_ellipse((0, 0.835, 0.0), 0.165, 0.120, 10, sq=0.35),
            ring_ellipse((0, 0.905, 0.0), 0.185, 0.132, 10, sq=0.35),
            ring_ellipse((0, 0.965, 0.0), 0.174, 0.126, 10, sq=0.30),
        ]
        loft(body, pelvis, 'cloth_base', C_TROUSER, True, (True, False), False,
             scols=[mul(C_TROUSER, 0.88), C_TROUSER])

        shirt_trunk = [
            ring_ellipse((0, 0.955, 0.0), 0.172, 0.126, 10, sq=0.25),
            ring_ellipse((0, 1.045, -0.005), 0.178, 0.132, 10, sq=0.25),
            ring_ellipse((0, 1.155, -0.010), 0.205, 0.148, 10, front_bias=0.10, sq=0.30),
            ring_ellipse((0, 1.285, -0.008), 0.232, 0.156, 10, front_bias=0.12, sq=0.35),
            ring_ellipse((0, 1.385, 0.004), 0.220, 0.134, 10, sq=0.40),
            ring_ellipse((0, 1.425, 0.006), 0.105, 0.088, 10, sq=0.25),
        ]
        loft(body, shirt_trunk, 'cloth_base', C_SHIRT, True, (False, True), False,
             scols=[mul(C_SHIRT, 0.88), mul(C_SHIRT, 0.96), C_SHIRT, mul(C_SHIRT, 1.04), mul(C_SHIRT, 0.95)])

        # Open shirt collar V-flaps & tanned throat/neck
        for sx in (-1.0, 1.0):
            cbox(body, (sx * 0.068, 1.375, -0.118), (0.072, 0.092, 0.032), 'cloth_base', C_SHIRT, 0.007,
                 R('Z', sx * 22) @ R('Y', -sx * 24))
        # Neck column (y = 1.38 .. 1.50)
        neck = [
            ring_ellipse((0, 1.370, -0.012), 0.072, 0.072, 8, sq=0.2),
            ring_ellipse((0, 1.435, -0.004), 0.062, 0.064, 8, sq=0.2),
            ring_ellipse((0, 1.505, 0.0), 0.060, 0.064, 8, sq=0.2),
        ]
        loft(body, neck, 'skin', C_SKIN_WARM, True, (False, False), False,
             scols=[C_SKIN_DARK, C_SKIN_WARM])

    for side in ("L", "R"):
        _build_pirate_boot_and_leg(body, side)
        _build_pirate_arm_and_hand(body, side)
    _build_pirate_head(body)
    meshes.append(build_skinned(body, arm_obj))

    # ---- 2. Hat_Tricorne (bold wide-brimmed captain's tricorne + gold trim + plume!)
    hat_tri = MB('Hat_Tricorne', seed=20)
    with wctx(hat_tri, "Head"):
        with xf(hat_tri, T(0, 1.695, 0.004) @ R('X', -7)):
            # Crown dome (dark weathered pirate leather)
            crown = [
                ring_ellipse((0, -0.015, 0.0), 0.114, 0.124, 10, sq=0.2),
                ring_ellipse((0, 0.055, 0.0), 0.110, 0.118, 10, sq=0.2),
                ring_ellipse((0, 0.118, 0.005), 0.090, 0.098, 10, sq=0.2),
                ring_ellipse((0, 0.140, 0.006), 0.042, 0.046, 10, sq=0.15),
            ]
            loft(hat_tri, crown, 'leather', C_LEATHER_DARK, True, (True, True), False,
                 scols=[C_LEATHER_DARK, C_LEATHER, mul(C_LEATHER, 1.06)])

            # Folded upturned 3-cornered brim (front prow at -Z, two wide swept wings!)
            segs = 18
            inner_b = []
            outer_b = []
            outer_t = []
            trim_in = []
            trim_out = []
            for k in range(segs):
                a = 2.0 * pi * k / segs
                # 3-lobed tricorne profile: corners at -Z (a=-pi/2 -> sin=-1), +X/+Z, -X/+Z
                # cos(3*(a + pi/2)) peaks at -pi/2, +pi/6, +5*pi/6
                lobe = 0.5 + 0.5 * cos(3.0 * (a + pi * 0.5))
                r_in = 0.110
                r_out = 0.175 + 0.095 * (lobe ** 1.3)
                # Upturned height is highest on the flat sides and curls stylishly at corners
                y_up = 0.095 + 0.055 * (1.0 - 0.55 * lobe)
                ca, sa = cos(a), sin(a)
                inner_b.append(Vector((ca * r_in, -0.005, sa * r_in * 1.08)))
                outer_b.append(Vector((ca * r_out, y_up - 0.022, sa * r_out * 1.08)))
                outer_t.append(Vector((ca * (r_out - 0.012), y_up + 0.005, sa * (r_out - 0.012) * 1.08)))
                trim_in.append(Vector((ca * (r_out - 0.018), y_up - 0.006, sa * (r_out - 0.018) * 1.08)))
                trim_out.append(Vector((ca * (r_out + 0.006), y_up - 0.002, sa * (r_out + 0.006) * 1.08)))
            loft(hat_tri, [inner_b, outer_b, outer_t], 'leather', C_LEATHER, True, (False, False), False,
                 scols=[C_LEATHER_DARK, C_LEATHER])
            # Gleaming brass/gold brim trim ribbon
            loft(hat_tri, [trim_in, trim_out, [p + Vector((0, 0.015, 0)) for p in trim_out]],
                 'brass', C_BRASS, True, (False, False), False)

            # Bold swept plume feather tucked on the left side (primary/secondary accent!)
            plume_path = [
                (-0.115, 0.055, -0.035),
                (-0.155, 0.115, 0.010),
                (-0.175, 0.175, 0.085),
                (-0.160, 0.215, 0.165),
                (-0.135, 0.205, 0.220),
            ]
            tube(hat_tri, plume_path, [(0.016, 0.012), (0.034, 0.018), (0.044, 0.020), (0.032, 0.014), (0.008, 0.006)],
                 6, 'cloth_secondary', C_TINT_HI, (True, True), False,
                 scols=[C_TINT_LO, C_TINT_MID, C_TINT_HI, C_TINT_HI])
            # Gold brooch holding feather
            cbox(hat_tri, (-0.115, 0.058, -0.045), (0.028, 0.034, 0.028), 'brass', C_BRASS, 0.006)
    meshes.append(build_skinned(hat_tri, arm_obj))

    # ---- 3. Hat_Bandana (knotted pirate kerchief + trailing tails)
    hat_ban = MB('Hat_Bandana', seed=21)
    with wctx(hat_ban, "Head"):
        dome = [
            ring_ellipse((0, 1.648, 0.004), 0.107, 0.118, 10, front_bias=0.05, sq=0.25),
            ring_ellipse((0, 1.685, 0.008), 0.112, 0.122, 10, sq=0.22),
            ring_ellipse((0, 1.724, 0.012), 0.095, 0.104, 10, sq=0.2),
            ring_ellipse((0, 1.750, 0.014), 0.042, 0.046, 10, sq=0.15),
        ]
        loft(hat_ban, dome, 'cloth_secondary', C_TINT_HI, True, (True, True), False,
             scols=[C_TINT_LO, C_TINT_HI, C_TINT_MID])
        # Thick folded forehead brow band
        band = [
            ring_ellipse((0, 1.634, 0.004), 0.112, 0.124, 10, front_bias=0.06, sq=0.25),
            ring_ellipse((0, 1.662, 0.006), 0.115, 0.126, 10, front_bias=0.04, sq=0.25),
        ]
        loft(hat_ban, band, 'cloth_secondary', C_TINT_MID, True, (False, False), False)
        # Knot & two trailing cloth tails on back-right
        cbox(hat_ban, (0.065, 1.648, 0.118), (0.046, 0.044, 0.044), 'cloth_secondary', C_TINT_HI, 0.012)
        tube(hat_ban, [(0.072, 1.640, 0.124), (0.096, 1.585, 0.155), (0.110, 1.515, 0.168)],
             [(0.022, 0.010), (0.028, 0.010), (0.014, 0.006)], 5, 'cloth_secondary', C_TINT_HI, (True, True), False)
        tube(hat_ban, [(0.055, 1.640, 0.125), (0.040, 1.575, 0.160), (0.025, 1.515, 0.178)],
             [(0.020, 0.009), (0.024, 0.009), (0.012, 0.005)], 5, 'cloth_secondary', C_TINT_MID, (True, True), False)
    meshes.append(build_skinned(hat_ban, arm_obj))

    # ---- 4. Hat_Cap (knitted sailor's cap with thick rolled cuff)
    hat_cap = MB('Hat_Cap', seed=22)
    with wctx(hat_cap, "Head"):
        # Ribbed rolled brim cuff
        cuff = [
            ring_ellipse((0, 1.644, 0.004), 0.112, 0.122, 10, sq=0.25),
            ring_ellipse((0, 1.666, 0.006), 0.122, 0.132, 10, sq=0.25),
            ring_ellipse((0, 1.696, 0.008), 0.118, 0.128, 10, sq=0.22),
        ]
        loft(hat_cap, cuff, 'cloth_secondary', C_TINT_HI, True, (True, False), False,
             scols=[C_TINT_LO, C_TINT_HI])
        # Slouchy knit crown tipping gently backward
        crown = [
            ring_ellipse((0, 1.690, 0.008), 0.112, 0.120, 10, sq=0.2),
            ring_ellipse((0, 1.740, 0.022), 0.106, 0.112, 10, sq=0.2),
            ring_ellipse((0, 1.782, 0.044), 0.074, 0.080, 10, sq=0.2),
            ring_ellipse((0, 1.798, 0.064), 0.028, 0.032, 10, sq=0.15),
        ]
        loft(hat_cap, crown, 'cloth_primary', C_TINT_HI, True, (False, True), False,
             scols=[C_TINT_LO, C_TINT_MID, C_TINT_HI])
        # Knitted pom button on tip
        ellipsoid(hat_cap, (0.0, 1.802, 0.072), (0.024, 0.022, 0.024), 'cloth_secondary', C_TINT_HI, 6, 4)
    meshes.append(build_skinned(hat_cap, arm_obj))

    # ---- 5. Coat_Captain (flared long pirate frock coat + wide cuffs + lapels + epaulettes)
    coat = MB('Coat_Captain', seed=23)
    with wctx(coat, w_coat_skirt):
        # Open-front U-shaped torso & dramatic flared coat-tails (y = 0.50 .. 1.40)
        # Open front gap angles around -Z (a = -pi/2)
        def coat_arc(y, rx, rz, gap_deg=34.0, flare_z=0.0):
            pts = []
            # Sweep from front-right around back to front-left (11 points)
            a0 = radians(-90.0 + gap_deg)
            a1 = radians(270.0 - gap_deg)
            n = 11
            for k in range(n):
                a = a0 + (a1 - a0) * k / (n - 1)
                ca, sa = cos(a), sin(a)
                pts.append(Vector((ca * rx, y, sa * rz + (flare_z if sa > 0 else 0.0))))
            return pts

        coat_secs = [
            coat_arc(0.50, 0.275, 0.215, 42.0, 0.04),
            coat_arc(0.68, 0.245, 0.185, 36.0, 0.02),
            coat_arc(0.86, 0.212, 0.156, 30.0, 0.0),
            coat_arc(0.98, 0.194, 0.145, 28.0, 0.0),
            coat_arc(1.14, 0.222, 0.162, 30.0, 0.0),
            coat_arc(1.30, 0.248, 0.170, 34.0, 0.0),
            coat_arc(1.395, 0.228, 0.145, 42.0, 0.0),
        ]
        loft(coat, coat_secs, 'cloth_primary', C_TINT_HI, closed=False, caps=(False, False), smooth=False,
             scols=[C_TINT_LO, C_TINT_MID, C_TINT_MID, C_TINT_MID, C_TINT_HI, C_TINT_HI])

        # Wide turned-back notched lapels & tall standing captain collar (secondary accent + brass buttons!)
        for sx in (-1.0, 1.0):
            cbox(coat, (sx * 0.128, 1.245, -0.158), (0.088, 0.255, 0.034), 'cloth_secondary', C_TINT_HI, 0.008,
                 R('Y', -sx * 24) @ R('Z', -sx * 8))
            # Lower coat hem trim edge
            cbox(coat, (sx * 0.155, 0.72, -0.155), (0.050, 0.38, 0.028), 'cloth_secondary', C_TINT_MID, 0.006,
                 R('Y', -sx * 28) @ R('Z', sx * 8))
            # Brass buttons down front chest
            for bi in range(4):
                by = 1.07 + bi * 0.068
                cbox(coat, (sx * 0.132, by, -0.172), (0.020, 0.020, 0.016), 'brass', C_BRASS, 0.004)
            # Broad padded captain's epaulettes with brass fringe
            cbox(coat, (sx * 0.215, 1.425, 0.008), (0.125, 0.036, 0.112), 'brass', C_BRASS, 0.009, R('Z', -sx * 14))
            cbox(coat, (sx * 0.210, 1.438, 0.008), (0.100, 0.020, 0.090), 'cloth_secondary', C_TINT_HI, 0.005,
                 R('Z', -sx * 14))
        # High sweeping captain's back collar
        collar = [
            coat_arc(1.385, 0.140, 0.115, 58.0, 0.0),
            coat_arc(1.475, 0.158, 0.135, 62.0, 0.02),
        ]
        loft(coat, collar, 'cloth_secondary', C_TINT_HI, closed=False, caps=(False, False), smooth=False)

    # Coat sleeves + huge flared captain cuffs (weighted cleanly to arms!)
    for side in ("L", "R"):
        sx = -1.0 if side == "L" else 1.0
        sh, ua, el, wr, _ = [Vector(q) for q in _arm_pts(sx)]
        with wctx(coat, w_arm(side)):
            sl_path = [ua.lerp(sh, 0.20), ua, ua.lerp(el, 0.5), el, el.lerp(wr, 0.52), el.lerp(wr, 0.72)]
            sl_rads = [0.086, 0.090, 0.082, 0.076, 0.082, 0.086]
            tube(coat, sl_path, sl_rads, 8, 'cloth_primary', C_TINT_HI, (True, False), False,
                 scols=[C_TINT_MID, C_TINT_HI, C_TINT_MID, C_TINT_MID, C_TINT_HI])
            # Massive flared captain's cuff + gold band
            cf_path = [el.lerp(wr, 0.62), el.lerp(wr, 0.78), el.lerp(wr, 0.94)]
            tube(coat, cf_path, [0.096, 0.104, 0.096], 8, 'cloth_secondary', C_TINT_HI, (True, True), False)
            tube(coat, [el.lerp(wr, 0.68), el.lerp(wr, 0.76)], [0.107, 0.107], 8, 'brass', C_BRASS, (False, False), False)
    meshes.append(build_skinned(coat, arm_obj))

    # ---- 6. Vest_Crew (bold open sailor's waistcoat cleanly clearing the white shirt!)
    vest = MB('Vest_Crew', seed=24)
    with wctx(vest, w_torso):
        def vest_arc(y, rx, rz, gap_deg=18.0, front_bias=0.14):
            pts = []
            a0 = radians(-90.0 + gap_deg)
            a1 = radians(270.0 - gap_deg)
            for k in range(13):
                a = a0 + (a1 - a0) * k / 12.0
                ca, sa = cos(a), sin(a)
                sx_s = (1.0 if ca >= 0 else -1.0) * (abs(ca) ** 0.72)
                sz_s = (1.0 if sa >= 0 else -1.0) * (abs(sa) ** 0.72)
                z_val = sz_s * rz * (1.0 + front_bias if sz_s < 0 else 1.0)
                pts.append(Vector((sx_s * rx, y, z_val)))
            return pts
        v_secs = [
            vest_arc(0.91, 0.222, 0.168, 16.0),
            vest_arc(1.04, 0.220, 0.170, 15.0),
            vest_arc(1.18, 0.248, 0.186, 17.0),
            vest_arc(1.32, 0.268, 0.190, 22.0),
            vest_arc(1.41, 0.236, 0.158, 30.0),
        ]
        loft(vest, v_secs, 'cloth_primary', C_TINT_HI, closed=False, caps=(False, False), smooth=False,
             scols=[C_TINT_LO, C_TINT_MID, C_TINT_HI, C_TINT_HI])
        # Trim front placket & brass buttons + shoulder straps
        for sx in (-1.0, 1.0):
            cbox(vest, (sx * 0.085, 1.155, -0.198), (0.044, 0.42, 0.024), 'leather', C_LEATHER, 0.006,
                 R('Y', -sx * 16))
            for bi in range(4):
                cbox(vest, (sx * 0.084, 1.00 + bi * 0.078, -0.212), (0.020, 0.020, 0.012), 'brass', C_BRASS, 0.003)
            # Chunky shoulder vest cap
            cbox(vest, (sx * 0.190, 1.418, 0.004), (0.108, 0.036, 0.128), 'cloth_primary', C_TINT_MID, 0.008,
                 R('Z', -sx * 12))
    meshes.append(build_skinned(vest, arm_obj))

    # ---- 7. Beard_Full (big chunky sculpted pirate beard & handlebar mustache!)
    beard = MB('Beard_Full', seed=25)
    with wctx(beard, "Head"):
        # Full jaw-hugging chunky sculpted beard mass
        b_secs = [
            ring_ellipse((0, 1.568, -0.056), 0.104, 0.068, 8, sq=0.4),
            ring_ellipse((0, 1.515, -0.088), 0.102, 0.068, 8, sq=0.45),
            ring_ellipse((0, 1.455, -0.102), 0.088, 0.056, 8, sq=0.45),
            ring_ellipse((0, 1.398, -0.108), 0.056, 0.036, 8, sq=0.4),
            ring_ellipse((0, 1.360, -0.104), 0.024, 0.018, 8, sq=0.3),
        ]
        loft(beard, b_secs, 'hair', C_HAIR, True, (True, True), False,
             scols=[C_HAIR_LIGHT, C_HAIR, mul(C_HAIR, 0.90), mul(C_HAIR, 0.80)])
        # Sweeping bushy mustache wings
        for sx in (-1.0, 1.0):
            tube(beard, [
                (sx * 0.012, 1.555, -0.120),
                (sx * 0.056, 1.546, -0.122),
                (sx * 0.102, 1.530, -0.098),
                (sx * 0.116, 1.544, -0.082),
            ], [0.022, 0.024, 0.016, 0.008], 6, 'hair', C_HAIR_LIGHT, (True, True), False)
            # Twin braided side locks with brass beard beads!
            cbox(beard, (sx * 0.064, 1.425, -0.118), (0.028, 0.062, 0.028), 'hair', C_HAIR_LIGHT, 0.007, R('Z', sx * 10))
            cbox(beard, (sx * 0.068, 1.404, -0.120), (0.032, 0.018, 0.032), 'brass', C_BRASS, 0.004)
    meshes.append(build_skinned(beard, arm_obj))

    # ---- 8. Eyepatch (strap + beveled leather patch over left eye!)
    patch = MB('Eyepatch', seed=26)
    with wctx(patch, "Head"):
        # Patch over left eye (-X, -Z)
        cbox(patch, (-0.044, 1.608, -0.114), (0.046, 0.040, 0.018), 'leather', C_LEATHER_DARK, 0.006, R('Y', 18))
        # Diagonal strap wrapping cleanly around head
        strap_pts = []
        segs = 14
        for k in range(segs + 1):
            a = -pi * 0.62 + 2.0 * pi * k / segs
            ca, sa = cos(a), sin(a)
            # Tilts up across right forehead and down behind left ear
            y = 1.630 + 0.032 * ca - 0.014 * sa
            strap_pts.append((ca * 0.108, y, sa * 0.118))
        tube(patch, strap_pts, 0.008, 4, 'leather', C_LEATHER_DARK, (False, False), False)
    meshes.append(build_skinned(patch, arm_obj))

    # ---- 9. Belt_Sash (wide colorful pirate waist sash + hanging tail + leather belt & brass buckle!)
    sash = MB('Belt_Sash', seed=27)
    with wctx(sash, w_belt_sash):
        # Thick wrapped cloth sash around waist (y = 0.89 .. 1.03)
        s_secs = [
            ring_ellipse((0, 0.895, 0.0), 0.210, 0.156, 10, sq=0.35),
            ring_ellipse((0, 0.945, -0.004), 0.218, 0.162, 10, sq=0.35),
            ring_ellipse((0, 1.005, -0.004), 0.208, 0.154, 10, sq=0.32),
            ring_ellipse((0, 1.032, -0.002), 0.194, 0.144, 10, sq=0.30),
        ]
        loft(sash, s_secs, 'cloth_secondary', C_TINT_HI, True, (True, True), False,
             scols=[C_TINT_LO, C_TINT_HI, C_TINT_MID])
        # Draped sash tail hanging off left hip (-X)
        tube(sash, [
            (-0.202, 0.925, -0.045),
            (-0.228, 0.800, -0.038),
            (-0.238, 0.660, -0.025),
            (-0.232, 0.560, -0.018),
        ], [(0.022, 0.054), (0.024, 0.062), (0.022, 0.068), (0.012, 0.056)],
             6, 'cloth_secondary', C_TINT_HI, (True, True), False,
             scols=[C_TINT_MID, C_TINT_HI, C_TINT_LO])
        # Heavy leather pirate belt over sash + oversized brass buckle in front!
        b_secs = [
            ring_ellipse((0, 0.925, -0.004), 0.224, 0.168, 10, sq=0.36),
            ring_ellipse((0, 0.985, -0.004), 0.222, 0.166, 10, sq=0.36),
        ]
        loft(sash, b_secs, 'leather', C_LEATHER_DARK, True, (True, True), False)
        # Chunky brass buckle frame at center front (-Z)
        for dx, dy, sx_b, sy_b in ((0, 0.036, 0.092, 0.022), (0, -0.036, 0.092, 0.022),
                                   (-0.038, 0, 0.022, 0.088), (0.038, 0, 0.022, 0.088),
                                   (0, 0, 0.014, 0.068)):
            cbox(sash, (dx, 0.955 + dy, -0.178), (sx_b, sy_b, 0.024), 'brass', C_BRASS, 0.004)
    meshes.append(build_skinned(sash, arm_obj))

    return meshes

# ================================================================ 2. DROWNED (SKELETAL PIRATE)
def _barnacle_cluster(mb, center, normal_dir, count, scale=1.0, wspec=None):
    rng = mb.rng
    c0 = Vector(center)
    n = Vector(normal_dir).normalized()
    ref = Vector((0, 1, 0)) if abs(n.y) < 0.85 else Vector((1, 0, 0))
    u = n.cross(ref).normalized()
    v = n.cross(u).normalized()
    for i in range(count):
        ang = 2.0 * pi * i / max(count, 1) + rng.uniform(-0.4, 0.4)
        rad = (0.0 if i == 0 else rng.uniform(0.018, 0.042)) * scale
        pos = c0 + (u * cos(ang) + v * sin(ang)) * rad
        h = rng.uniform(0.020, 0.038) * scale
        r0 = rng.uniform(0.016, 0.028) * scale
        col = C_BARNACLE_TIP if (i % 2 == 0) else C_BARNACLE
        cone(mb, pos - n * 0.005, pos + n * h, r0, r0 * 0.42, 5, 'coral', col, False, wspec=wspec)

def _seaweed_tuft(mb, start, length=0.22, strands=2, wspec=None):
    rng = mb.rng
    s0 = Vector(start)
    for i in range(strands):
        dx = rng.uniform(-0.04, 0.04)
        dz = rng.uniform(-0.04, 0.04)
        pts = [
            s0 + Vector((dx * 0.3, 0.0, dz * 0.3)),
            s0 + Vector((dx * 0.9, -length * 0.35, dz * 0.8)),
            s0 + Vector((dx * 1.4, -length * 0.72, dz * 1.1)),
            s0 + Vector((dx * 1.1, -length, dz * 0.9)),
        ]
        tube(mb, pts, [(0.016, 0.005), (0.020, 0.006), (0.015, 0.005), (0.005, 0.003)],
             4, 'coral', C_KELP if i % 2 == 0 else C_KELP_HI, (True, True), False, wspec=wspec)

def _bone_segment(mb, a, b, r_mid, r_end, wspec):
    a = Vector(a)
    b = Vector(b)
    pts = [a, a.lerp(b, 0.16), a.lerp(b, 0.50), a.lerp(b, 0.84), b]
    rads = [r_end, r_mid * 0.92, r_mid, r_mid * 0.92, r_end]
    scols = [C_BONE_DARK, C_BONE, C_BONE, C_BONE_DARK]
    tube(mb, pts, rads, 6, 'bone', C_BONE, (True, True), False, scols=scols, wspec=wspec)

def build_drowned_meshes(arm_obj):
    meshes = []

    # ---- 1. Drowned_Body (chunky skeleton + glowing eyes + barnacles & seaweed!)
    body = MB('Drowned_Body', seed=40)

    # Skull (y = 1.48 .. 1.72, weighted to Head)
    with wctx(body, "Head"):
        # Chunky weathered cranium
        cranium = [
            ring_ellipse((0, 1.545, 0.012), 0.072, 0.084, 8, sq=0.35),
            ring_ellipse((0, 1.595, -0.004), 0.095, 0.108, 8, front_bias=0.10, sq=0.40),
            ring_ellipse((0, 1.652, 0.0), 0.104, 0.114, 8, sq=0.32),
            ring_ellipse((0, 1.700, 0.008), 0.088, 0.098, 8, sq=0.25),
            ring_ellipse((0, 1.724, 0.012), 0.042, 0.048, 8, sq=0.20),
        ]
        loft(body, cranium, 'bone', C_BONE, True, (True, True), False,
             scols=[C_BONE_DARK, C_BONE_GREEN, C_BONE, mul(C_BONE, 1.05)])

        # Heavy menacing brow ridge & cheekbones
        cbox(body, (0.0, 1.635, -0.106), (0.155, 0.030, 0.042), 'bone', C_BONE, 0.009)
        for sx in (-1.0, 1.0):
            cbox(body, (sx * 0.076, 1.576, -0.096), (0.046, 0.034, 0.044), 'bone', C_BONE_GREEN, 0.009)
            # Deep black recessed eye socket
            cbox(body, (sx * 0.042, 1.606, -0.106), (0.044, 0.038, 0.024), 'bone', C_SOCKET, 0.006)
            # GLOWING SEA-GREEN EMISSIVE EYE PIP!
            ellipsoid(body, (sx * 0.042, 1.606, -0.115), (0.016, 0.014, 0.012), 'emissive_sea', C_SEA_GLOW, 6, 4)
        # Nasal cavity & maxilla teeth + hinged lower jaw
        cbox(body, (0.0, 1.576, -0.114), (0.026, 0.028, 0.018), 'bone', C_SOCKET, 0.004)
        cbox(body, (0.0, 1.544, -0.094), (0.096, 0.034, 0.068), 'bone', C_BONE, 0.008)
        # Chunky skull grin teeth row
        for ti in range(-2, 3):
            cbox(body, (ti * 0.018, 1.525, -0.120), (0.013, 0.022, 0.014), 'bone', mul(C_BONE, 1.08), 0.002)
        # Strong bony lower jaw
        cbox(body, (0.0, 1.500, -0.076), (0.094, 0.032, 0.088), 'bone', C_BONE_DARK, 0.008)
        # Barnacles encrusted on skull temple!
        _barnacle_cluster(body, (0.085, 1.665, -0.035), (0.8, 0.5, -0.3), 3, 0.85, "Head")

    # Vertebrae column + chunky ribcage + clavicles + pelvis
    with wctx(body, w_torso):
        # Segmented chunky spine column (y = 0.92 .. 1.48)
        for i in range(7):
            sy = 0.95 + i * 0.082
            cbox(body, (0.0, sy, 0.032), (0.056, 0.054, 0.062), 'bone', C_BONE_DARK if i % 2 else C_BONE, 0.012)
            # Dorsal spine ridge knob
            cbox(body, (0.0, sy, 0.072), (0.026, 0.032, 0.034), 'bone', C_BONE, 0.006)

        # Sternum plate
        cbox(body, (0.0, 1.275, -0.106), (0.062, 0.190, 0.034), 'bone', C_BONE, 0.009)

        # 4 pairs of bold chunky curved ribs wrapping around hollow chest
        for ri, (ry, rx, rz) in enumerate(((1.355, 0.175, 0.118), (1.290, 0.190, 0.128),
                                           (1.225, 0.178, 0.122), (1.160, 0.150, 0.105))):
            for sx in (-1.0, 1.0):
                pts = [
                    (sx * 0.025, ry + 0.01, 0.045),
                    (sx * rx * 0.72, ry + 0.012, 0.040),
                    (sx * rx, ry, -0.022),
                    (sx * rx * 0.68, ry - 0.015, -rz),
                    (sx * 0.028, ry - 0.018, -rz * 0.90),
                ]
                tube(body, pts, 0.019, 5, 'bone', C_BONE if ri % 2 == 0 else C_BONE_GREEN, (True, True), False)

        # Clavicles & chunky shoulder blades
        for sx in (-1.0, 1.0):
            tube(body, [(sx * 0.03, 1.385, -0.075), (sx * 0.13, 1.395, -0.045), (sx * 0.21, 1.385, 0.012)],
                 0.022, 5, 'bone', C_BONE, (True, True), False)
            cbox(body, (sx * 0.115, 1.315, 0.075), (0.088, 0.125, 0.030), 'bone', C_BONE_DARK, 0.008)

        # Sculpted lumbar spine column + bold vertebrae closing waist gap cleanly
        tube(body, [(0.0, 0.93, 0.016), (0.0, 1.03, 0.024), (0.0, 1.14, 0.026)],
             [0.042, 0.038, 0.040], 6, 'bone', C_BONE, (True, True), False)
        for vy in (0.985, 1.045, 1.105):
            cbox(body, (0.0, vy, 0.022), (0.082, 0.034, 0.068), 'bone', C_BONE_DARK, 0.008)

        # Pelvis bone + sea-rotted tattered breeches & rope waist tie
        pelvis_secs = [
            ring_ellipse((0, 0.835, 0.0), 0.145, 0.102, 8, sq=0.45),
            ring_ellipse((0, 0.905, 0.0), 0.168, 0.116, 8, sq=0.45),
            ring_ellipse((0, 0.960, 0.0), 0.152, 0.104, 8, sq=0.40),
        ]
        loft(body, pelvis_secs, 'bone', C_BONE_DARK, True, (True, True), False)
        # Ragged briny breeches loincloth / tatters over hips
        tatter_secs = [
            ring_ellipse((0, 0.785, 0.0), 0.166, 0.126, 8, sq=0.35),
            ring_ellipse((0, 0.895, 0.0), 0.180, 0.130, 8, sq=0.35),
            ring_ellipse((0, 0.968, 0.0), 0.168, 0.122, 8, sq=0.30),
        ]
        loft(body, tatter_secs, 'cloth_primary', C_TINT_MID, True, (False, True), False,
             scols=[C_TINT_LO, C_TINT_MID])
        # Thick rope belt around skeletal waist
        tube(body, [(0.175 * cos(2 * pi * k / 10), 0.955, 0.128 * sin(2 * pi * k / 10)) for k in range(11)],
             0.018, 5, 'leather', C_WOOD_ROT, (False, False), False)

        # Encrusted barnacles & draping seaweed on chest & shoulder!
        _barnacle_cluster(body, (-0.155, 1.365, -0.055), (-0.7, 0.6, -0.4), 4, 1.0, w_torso)
        _barnacle_cluster(body, (0.145, 1.235, -0.095), (0.6, 0.2, -0.7), 3, 0.9, w_torso)
        _seaweed_tuft(body, (-0.170, 1.345, -0.020), 0.24, 2, w_torso)
        _seaweed_tuft(body, (0.140, 1.180, 0.085), 0.20, 2, w_torso)

    # Bony arms & chunky skeletal claw hands
    for side in ("L", "R"):
        sx = -1.0 if side == "L" else 1.0
        _, ua, el, wr, ft = [Vector(q) for q in _arm_pts(sx)]
        wa = w_arm(side)
        with wctx(body, wa):
            _bone_segment(body, ua, el, 0.030, 0.044, wa)
            _bone_segment(body, el, wr, 0.026, 0.038, wa)
            # Enlarged shoulder & elbow bone knuckles
            ellipsoid(body, ua, (0.048, 0.048, 0.048), 'bone', C_BONE_GREEN, 6, 4)
            ellipsoid(body, el, (0.040, 0.040, 0.040), 'bone', C_BONE_DARK, 6, 4)
            # Tattered cuff cloth strip around forearm
            if side == "R":
                _seaweed_tuft(body, el.lerp(wr, 0.5), 0.16, 2, wa)
        with wctx(body, "Hand_" + side):
            h_dir = (ft - wr).normalized()
            side_v = h_dir.cross(Vector((0, 0, -1))).normalized()
            fwd_v = side_v.cross(h_dir).normalized()
            H = Matrix((
                (side_v.x, h_dir.x, fwd_v.x, wr.x),
                (side_v.y, h_dir.y, fwd_v.y, wr.y),
                (side_v.z, h_dir.z, fwd_v.z, wr.z),
                (0.0, 0.0, 0.0, 1.0),
            ))
            with xf(body, H):
                cbox(body, (0.0, 0.048, 0.0), (0.036, 0.076, 0.074), 'bone', C_BONE, 0.010)
                # 3 chunky bony claw fingers + thumb
                for fi, fz in enumerate((-0.026, 0.0, 0.026)):
                    cbox(body, (-sx * 0.014, 0.110, fz), (0.022, 0.056, 0.018), 'bone', C_BONE_DARK, 0.005,
                         R('Z', sx * 26))
                cbox(body, (-sx * 0.018, 0.052, -0.050), (0.024, 0.048, 0.024), 'bone', C_BONE_DARK, 0.006,
                     R('X', -32))

    # Bony legs + mismatched pirate boot (right) & wrappings/bony foot (left), both planted cleanly at y = 0.0!
    for side in ("L", "R"):
        sx = -1.0 if side == "L" else 1.0
        hp, kn, an, to = [Vector(q) for q in _leg_pts(sx)]
        wl = w_leg(side)
        with wctx(body, wl):
            _bone_segment(body, hp, kn, 0.038, 0.054, wl)
            _bone_segment(body, kn, an, 0.032, 0.046, wl)
            ellipsoid(body, kn, (0.048, 0.046, 0.048), 'bone', C_BONE_GREEN, 6, 4)
            # Tattered trouser shorts upper thigh
            short_secs = [
                ring_ellipse((sx * 0.115, 0.62, 0.0), 0.088, 0.090, 7, sq=0.25),
                ring_ellipse((sx * 0.115, 0.78, 0.0), 0.094, 0.098, 7, sq=0.25),
                ring_ellipse((sx * 0.100, 0.88, 0.0), 0.088, 0.096, 7, sq=0.25),
            ]
            loft(body, short_secs, 'cloth_primary', C_TINT_LO, True, (False, True), False)

            fx = sx * 0.118
            if side == "R":
                # Weathered sea-rotted pirate boot planted at y = 0.0
                cbox(body, (fx, 0.018, -0.055), (0.114, 0.036, 0.245), 'leather', C_LEATHER_DARK, 0.008)
                cbox(body, (fx, 0.062, -0.072), (0.104, 0.074, 0.195), 'leather', C_WOOD_ROT, 0.020)
                shaft = [
                    ring_ellipse((fx, 0.075, 0.015), 0.054, 0.058, 7, sq=0.25),
                    ring_ellipse((fx, 0.28, 0.005), 0.066, 0.070, 7, sq=0.25),
                    ring_ellipse((fx, 0.34, 0.0), 0.082, 0.086, 7, sq=0.30),
                ]
                loft(body, shaft, 'leather', C_WOOD_ROT, True, (False, True), False)
                _barnacle_cluster(body, (fx + 0.065, 0.22, -0.03), (0.8, 0.2, -0.5), 3, 0.8, wl)
            else:
                # Bare skeletal foot with thick heel & bony toes planted flat at y = 0.0 + barnacles on shin!
                cbox(body, (fx, 0.026, 0.018), (0.078, 0.052, 0.105), 'bone', C_BONE_DARK, 0.010)
                for ti, tx in enumerate((-0.030, 0.0, 0.030)):
                    cbox(body, (fx + tx, 0.022, -0.095), (0.024, 0.044, 0.145), 'bone', C_BONE, 0.007)
                _barnacle_cluster(body, (fx - 0.042, 0.26, -0.025), (-0.8, 0.1, -0.5), 3, 0.85, wl)
                _seaweed_tuft(body, (fx - 0.045, 0.34, 0.02), 0.18, 1, wl)

    meshes.append(build_skinned(body, arm_obj))

    # ---- 2. Drowned_Bandana (tattered sea-stained kerchief)
    dban = MB('Drowned_Bandana', seed=41)
    with wctx(dban, "Head"):
        dome = [
            ring_ellipse((0, 1.644, 0.004), 0.108, 0.118, 9, sq=0.25),
            ring_ellipse((0, 1.685, 0.008), 0.114, 0.122, 9, sq=0.25),
            ring_ellipse((0, 1.724, 0.012), 0.092, 0.100, 9, sq=0.20),
            ring_ellipse((0, 1.748, 0.014), 0.038, 0.042, 9, sq=0.15),
        ]
        loft(dban, dome, 'cloth_secondary', C_TINT_MID, True, (True, True), False,
             scols=[C_TINT_LO, C_TINT_MID, C_TINT_LO])
        cbox(dban, (-0.068, 1.646, 0.115), (0.044, 0.040, 0.042), 'cloth_secondary', C_TINT_LO, 0.010)
        tube(dban, [(-0.072, 1.638, 0.122), (-0.098, 1.565, 0.155), (-0.112, 1.485, 0.168)],
             [(0.020, 0.008), (0.026, 0.008), (0.010, 0.004)], 5, 'cloth_secondary', C_TINT_MID, (True, True), False)
        tube(dban, [(-0.052, 1.638, 0.122), (-0.035, 1.568, 0.162), (-0.020, 1.500, 0.176)],
             [(0.018, 0.008), (0.022, 0.008), (0.008, 0.004)], 5, 'cloth_secondary', C_TINT_LO, (True, True), False)
    meshes.append(build_skinned(dban, arm_obj))

    # ---- 3. Drowned_CaptainHat (barnacle-crusted skewed captain tricorne)
    dhat = MB('Drowned_CaptainHat', seed=42)
    with wctx(dhat, "Head"):
        with xf(dhat, T(0, 1.692, 0.005) @ R('X', -9) @ R('Z', 6)):
            crown = [
                ring_ellipse((0, -0.015, 0.0), 0.112, 0.122, 9, sq=0.25),
                ring_ellipse((0, 0.062, 0.002), 0.108, 0.116, 9, sq=0.22),
                ring_ellipse((0, 0.126, 0.008), 0.086, 0.094, 9, sq=0.20),
                ring_ellipse((0, 0.148, 0.010), 0.038, 0.042, 9, sq=0.15),
            ]
            loft(dhat, crown, 'cloth_primary', C_TINT_LO, True, (True, True), False)
            segs = 16
            in_b, out_b, out_t, trim_r = [], [], [], []
            for k in range(segs):
                a = 2.0 * pi * k / segs
                lobe = 0.5 + 0.5 * cos(3.0 * (a + pi * 0.5))
                # Weathered notched asymmetry
                notch = 0.86 if k in (5, 12) else 1.0
                r_out = (0.178 + 0.098 * (lobe ** 1.25)) * notch
                y_up = 0.090 + 0.056 * (1.0 - 0.5 * lobe) + (0.018 if k % 4 == 0 else -0.008)
                ca, sa = cos(a), sin(a)
                in_b.append(Vector((ca * 0.108, -0.006, sa * 0.116)))
                out_b.append(Vector((ca * r_out, y_up - 0.022, sa * r_out * 1.08)))
                out_t.append(Vector((ca * (r_out - 0.012), y_up + 0.006, sa * (r_out - 0.012) * 1.08)))
                trim_r.append(Vector((ca * (r_out + 0.006), y_up, sa * (r_out + 0.006) * 1.08)))
            loft(dhat, [in_b, out_b, out_t], 'cloth_primary', C_TINT_MID, True, (False, False), False)
            loft(dhat, [out_t, trim_r], 'brass', mul(C_BRASS, 0.82), True, (False, False), False)
            _barnacle_cluster(dhat, (0.115, 0.088, -0.075), (0.6, 0.7, -0.4), 4, 0.95, "Head")
            _seaweed_tuft(dhat, (-0.165, 0.090, 0.040), 0.22, 2, "Head")
    meshes.append(build_skinned(dhat, arm_obj))

    # ---- 4. Drowned_Coat (tattered captain coat tails + torn cuffs + barnacle epaulettes)
    dcoat = MB('Drowned_Coat', seed=43)
    with wctx(dcoat, w_coat_skirt):
        def dcoat_arc(y, rx, rz, gap_deg=38.0, jag=0.0):
            pts = []
            a0 = radians(-90.0 + gap_deg)
            a1 = radians(270.0 - gap_deg)
            for k in range(11):
                a = a0 + (a1 - a0) * k / 10.0
                dy = jag * (0.045 if k % 2 == 0 else -0.035)
                pts.append(Vector((cos(a) * rx, y + dy, sin(a) * rz)))
            return pts
        secs = [
            dcoat_arc(0.50, 0.275, 0.210, 48.0, 1.0),
            dcoat_arc(0.72, 0.240, 0.180, 40.0, 0.3),
            dcoat_arc(0.95, 0.200, 0.148, 34.0, 0.0),
            dcoat_arc(1.18, 0.225, 0.162, 36.0, 0.0),
            dcoat_arc(1.38, 0.232, 0.148, 46.0, 0.0),
        ]
        loft(dcoat, secs, 'cloth_primary', C_TINT_MID, closed=False, caps=(False, False), smooth=False,
             scols=[C_TINT_LO, C_TINT_MID, C_TINT_MID, C_TINT_HI])
        for sx in (-1.0, 1.0):
            cbox(dcoat, (sx * 0.132, 1.24, -0.154), (0.076, 0.23, 0.028), 'cloth_secondary', C_TINT_MID, 0.007,
                 R('Y', -sx * 24))
            cbox(dcoat, (sx * 0.215, 1.42, 0.008), (0.122, 0.034, 0.108), 'brass', mul(C_BRASS, 0.78), 0.008,
                 R('Z', -sx * 14))
        _barnacle_cluster(dcoat, (0.23, 1.44, -0.01), (0.4, 0.9, -0.2), 3, 0.9, w_torso)
    for side in ("L", "R"):
        sx = -1.0 if side == "L" else 1.0
        sh, ua, el, wr, _ = [Vector(q) for q in _arm_pts(sx)]
        with wctx(dcoat, w_arm(side)):
            tube(dcoat, [ua, ua.lerp(el, 0.55), el, el.lerp(wr, 0.55)],
                 [0.082, 0.072, 0.068, 0.078], 7, 'cloth_primary', C_TINT_MID, (True, False), False)
            tube(dcoat, [el.lerp(wr, 0.52), el.lerp(wr, 0.80)], [0.090, 0.086],
                 7, 'cloth_secondary', C_TINT_MID, (True, True), False)
    meshes.append(build_skinned(dcoat, arm_obj))

    # ---- 5. Drowned_Shield (heavy barnacle-studded wooden buckler strapped to LEFT forearm!)
    dshield = MB('Drowned_Shield', seed=44)
    _, _, el_l, wr_l, _ = [Vector(q) for q in _arm_pts(-1.0)]
    sh_c = el_l.lerp(wr_l, 0.52)
    f_dir = (wr_l - el_l).normalized()
    # Outward normal pointing out/forward from left forearm (-X, -Z)
    out_n = Vector((-0.78, 0.12, -0.62)).normalized()
    u_ax = f_dir - out_n * f_dir.dot(out_n)
    u_ax.normalize()
    v_ax = out_n.cross(u_ax).normalized()
    MSH = Matrix((
        (u_ax.x, out_n.x, v_ax.x, sh_c.x + out_n.x * 0.055),
        (u_ax.y, out_n.y, v_ax.y, sh_c.y + out_n.y * 0.055),
        (u_ax.z, out_n.z, v_ax.z, sh_c.z + out_n.z * 0.055),
        (0.0, 0.0, 0.0, 1.0),
    ))
    with wctx(dshield, "Forearm_L"):
        with xf(dshield, MSH):
            # Thick 10-sided convex wooden plank buckler (diameter ~0.56 m!)
            r_sh = 0.285
            sh_secs = [
                ring_ellipse((0, -0.020, 0), r_sh * 0.94, r_sh * 0.94, 10),
                ring_ellipse((0, 0.018, 0), r_sh, r_sh, 10),
                ring_ellipse((0, 0.036, 0), r_sh * 0.88, r_sh * 0.88, 10),
            ]
            loft(dshield, sh_secs, 'leather', C_WOOD_ROT, True, (True, True), False,
                 scols=[mul(C_WOOD_ROT, 0.82), C_WOOD_ROT])
            # Heavy riveted iron outer rim
            rim_secs = [
                ring_ellipse((0, -0.024, 0), r_sh * 1.03, r_sh * 1.03, 10),
                ring_ellipse((0, 0.024, 0), r_sh * 1.04, r_sh * 1.04, 10),
                ring_ellipse((0, 0.040, 0), r_sh * 0.90, r_sh * 0.90, 10),
            ]
            loft(dshield, rim_secs, 'iron', C_IRON, True, (False, False), False)
            # Chunky central iron dome boss & diagonal iron brace bars
            ellipsoid(dshield, (0, 0.044, 0), (0.088, 0.048, 0.088), 'iron', mul(C_IRON, 1.18), 8, 4)
            cbox(dshield, (0, 0.034, 0), (r_sh * 1.82, 0.018, 0.044), 'iron', C_IRON, 0.004)
            cbox(dshield, (0, 0.034, 0), (0.044, 0.018, r_sh * 1.82), 'iron', C_IRON, 0.004)
            # Leather forearm grip straps on inner side
            cbox(dshield, (0, -0.034, 0), (0.065, 0.028, 0.16), 'leather', C_LEATHER_DARK, 0.005)
            # Barnacle crusts on shield face!
            _barnacle_cluster(dshield, (0.14, 0.038, 0.10), (0.15, 1.0, 0.1), 4, 1.0, "Forearm_L")
            _barnacle_cluster(dshield, (-0.15, 0.038, -0.09), (-0.1, 1.0, -0.1), 3, 0.9, "Forearm_L")
    meshes.append(build_skinned(dshield, arm_obj))

    # ---- 6. Drowned_PowderKeg (red-banded glowing gunpowder keg perched boldly on right shoulder!)
    dkeg = MB('Drowned_PowderKeg', seed=45)
    with wctx(dkeg, "Chest"):
        # Perched prominently on the right shoulder, angled slightly forward-outward so it reads
        # cleanly at distance AND keeps total height around ~1.88 m!
        MK = T(0.245, 1.605, 0.015) @ R('Z', -16) @ R('X', 82)
        with xf(dkeg, MK):
            # Chubby red-staved gunpowder barrel (length ~0.46 m, max radius ~0.185 m)
            keg_secs = [
                ring_ellipse((0, -0.22, 0), 0.142, 0.142, 10),
                ring_ellipse((0, -0.12, 0), 0.178, 0.178, 10),
                ring_ellipse((0, 0.00, 0), 0.192, 0.192, 10),
                ring_ellipse((0, 0.12, 0), 0.178, 0.178, 10),
                ring_ellipse((0, 0.22, 0), 0.142, 0.142, 10),
            ]
            loft(dkeg, keg_secs, 'cloth_secondary', C_KEG_RED, True, (True, True), False,
                 scols=[mul(C_KEG_RED, 0.85), C_KEG_RED, mul(C_KEG_RED, 1.08), C_KEG_RED])
            # 4 dark iron barrel hoops
            for hy, hr in ((-0.17, 0.168), (-0.075, 0.192), (0.075, 0.192), (0.17, 0.168)):
                h_secs = [
                    ring_ellipse((0, hy - 0.020, 0), hr, hr, 10),
                    ring_ellipse((0, hy + 0.020, 0), hr, hr, 10),
                ]
                loft(dkeg, h_secs, 'iron', C_IRON, True, (True, True), False)
            # Glowing powder cracks & sizzling lit fuse! (Emissive fiery orange-red!)
            cbox(dkeg, (0.0, 0.0, -0.190), (0.048, 0.160, 0.024), 'emissive_keg', C_KEG_GLOW, 0.005)
            cbox(dkeg, (0.175, 0.02, -0.07), (0.024, 0.130, 0.042), 'emissive_keg', C_KEG_GLOW, 0.005, R('Y', 25))
            # Lit sizzling fuse & spark bulb on the front cap
            tube(dkeg, [(0, 0.22, 0), (0.02, 0.28, -0.03), (0.05, 0.31, -0.07)],
                 0.014, 5, 'leather', C_WOOD_ROT, (True, True), False)
            ellipsoid(dkeg, (0.055, 0.315, -0.075), (0.038, 0.038, 0.038), 'emissive_keg', C_KEG_GLOW, 6, 4)
    meshes.append(build_skinned(dkeg, arm_obj))

    return meshes

# ================================================================ 3. TIDECALLER (CORAL SEA CULTIST)
def _coral_branch(mb, pts, r0, r1, wspec):
    n = len(pts)
    rads = [r0 + (r1 - r0) * (i / max(n - 1, 1)) for i in range(n)]
    scols = [mix(C_CORAL_BASE, C_CORAL_TIP, i / max(n - 2, 1)) for i in range(max(n - 1, 1))]
    tube(mb, pts, rads, 5, 'coral', C_CORAL_MID, (True, True), False, scols=scols, wspec=wspec)

def build_tidecaller_meshes(arm_obj):
    meshes = []
    body = MB('Tidecaller_Body', seed=70)

    # ---- Flowing layered mystic cultist robe (ankle-length skirt to shoulders, y = 0.06 .. 1.43)
    with wctx(body, w_coat_skirt):
        robe_secs = [
            ring_ellipse((0, 0.075, 0.010), 0.275, 0.220, 12, front_bias=0.06, sq=0.25),
            ring_ellipse((0, 0.280, 0.006), 0.248, 0.196, 12, sq=0.25),
            ring_ellipse((0, 0.520, 0.002), 0.218, 0.168, 12, sq=0.25),
            ring_ellipse((0, 0.780, 0.0), 0.190, 0.142, 12, sq=0.28),
            ring_ellipse((0, 0.960, 0.0), 0.175, 0.132, 12, sq=0.28),
            ring_ellipse((0, 1.150, -0.008), 0.205, 0.150, 12, sq=0.30),
            ring_ellipse((0, 1.320, -0.006), 0.232, 0.158, 12, sq=0.35),
            ring_ellipse((0, 1.420, 0.0), 0.152, 0.122, 12, sq=0.25),
        ]
        loft(body, robe_secs, 'cloth_primary', C_TINT_HI, True, (False, True), False,
             scols=[C_TINT_LO, C_TINT_MID, C_TINT_MID, C_TINT_LO, C_TINT_MID, C_TINT_HI, C_TINT_HI])

        # Wide sea-ochre hem trim band around bottom of robe
        hem_secs = [
            ring_ellipse((0, 0.068, 0.010), 0.282, 0.226, 12, front_bias=0.06, sq=0.25),
            ring_ellipse((0, 0.145, 0.008), 0.274, 0.218, 12, front_bias=0.04, sq=0.25),
        ]
        loft(body, hem_secs, 'cloth_secondary', C_TINT_HI, True, (True, False), False)

        # Draped ritual sash & carved stole down front & back with GLOWING AQUAMARINE RUNES!
        stole_f = [
            [Vector((-0.072, 0.22, -0.210)), Vector((0.072, 0.22, -0.210)),
             Vector((0.072, 0.22, -0.192)), Vector((-0.072, 0.22, -0.192))],
            [Vector((-0.078, 0.62, -0.172)), Vector((0.078, 0.62, -0.172)),
             Vector((0.078, 0.62, -0.154)), Vector((-0.078, 0.62, -0.154))],
            [Vector((-0.074, 0.96, -0.148)), Vector((0.074, 0.96, -0.148)),
             Vector((0.074, 0.96, -0.130)), Vector((-0.074, 0.96, -0.130))],
            [Vector((-0.088, 1.32, -0.172)), Vector((0.088, 1.32, -0.172)),
             Vector((0.088, 1.32, -0.152)), Vector((-0.088, 1.32, -0.152))],
        ]
        loft(body, stole_f, 'cloth_secondary', C_TINT_MID, True, (True, True), False)

        # Glowing carved aquamarine sea-runes down chest & stole!
        for ry, rz, rw, rh in ((1.26, -0.175, 0.072, 0.022), (1.20, -0.172, 0.022, 0.088),
                               (1.14, -0.168, 0.056, 0.020), (0.82, -0.162, 0.054, 0.054),
                               (0.56, -0.180, 0.062, 0.022), (0.48, -0.188, 0.022, 0.078)):
            cbox(body, (0.0, ry, rz), (rw, rh, 0.016), 'emissive_sea', C_AQUA_GLOW, 0.003)

        # Heavy braided kelp/rope ritual belt with glowing sea-orb medallion
        tube(body, [(0.190 * cos(2 * pi * k / 10), 0.965, 0.145 * sin(2 * pi * k / 10)) for k in range(11)],
             0.022, 5, 'coral', C_KELP, (False, False), False)
        ellipsoid(body, (0.0, 0.965, -0.158), (0.042, 0.046, 0.028), 'emissive_sea', C_AQUA_GLOW, 6, 4)

    # ---- Sturdy sea-wrappings / boots cleanly planted at y = 0.0 under robe hem
    for side in ("L", "R"):
        sx = -1.0 if side == "L" else 1.0
        wl = w_leg(side)
        with wctx(body, wl):
            fx = sx * 0.118
            cbox(body, (fx, 0.020, -0.050), (0.112, 0.040, 0.240), 'leather', C_LEATHER_DARK, 0.008)
            cbox(body, (fx, 0.055, -0.065), (0.100, 0.066, 0.190), 'leather', C_MASK_DARK, 0.018)
            # Lower shin leg hidden inside skirt so movement stays anchored cleanly
            tube(body, [(fx, 0.08, 0.01), (fx, 0.45, -0.01)], [0.052, 0.056], 6, 'leather', C_MASK_DARK, (False, False), False)

    # ---- Asymmetric Barnacle & Coral Pauldrons on Shoulders!
    # Left pauldron: huge jagged reef-coral & barnacle mantle
    with wctx(body, "Shoulder_L"):
        cbox(body, (-0.235, 1.410, 0.005), (0.175, 0.092, 0.185), 'coral', C_SHELL, 0.022, R('Z', 20))
        _barnacle_cluster(body, (-0.265, 1.455, -0.015), (-0.4, 0.9, -0.2), 5, 1.15, "Shoulder_L")
        _coral_branch(body, [(-0.24, 1.44, 0.02), (-0.31, 1.52, 0.04), (-0.36, 1.59, 0.02)], 0.026, 0.010, "Shoulder_L")
        _coral_branch(body, [(-0.29, 1.49, 0.03), (-0.34, 1.51, -0.04)], 0.018, 0.008, "Shoulder_L")
        _seaweed_tuft(body, (-0.285, 1.365, 0.04), 0.28, 2, "Shoulder_L")
    # Right pauldron: layered overlapping sea-shell plates + barnacles
    with wctx(body, "Shoulder_R"):
        cbox(body, (0.222, 1.405, 0.008), (0.155, 0.072, 0.165), 'coral', C_SHELL, 0.018, R('Z', -16))
        cbox(body, (0.255, 1.352, 0.010), (0.120, 0.052, 0.145), 'coral', mul(C_SHELL, 0.85), 0.014, R('Z', -28))
        _barnacle_cluster(body, (0.235, 1.445, -0.020), (0.3, 0.9, -0.2), 3, 0.95, "Shoulder_R")

    # ---- Wide mystic sleeves, gnarled forearms & clutching ritual hands with glowing rune rings
    for side in ("L", "R"):
        sx = -1.0 if side == "L" else 1.0
        sh, ua, el, wr, ft = [Vector(q) for q in _arm_pts(sx)]
        wa = w_arm(side)
        with wctx(body, wa):
            # Draped wide robe sleeve down to mid-forearm
            tube(body, [ua.lerp(sh, 0.15), ua, ua.lerp(el, 0.55), el, el.lerp(wr, 0.48)],
                 [0.082, 0.090, 0.086, 0.094, 0.102], 7, 'cloth_primary', C_TINT_HI, (True, True), False,
                 scols=[C_TINT_MID, C_TINT_HI, C_TINT_MID, C_TINT_LO])
            # Trim ring on sleeve hem
            tube(body, [el.lerp(wr, 0.36), el.lerp(wr, 0.50)], [0.104, 0.108], 7, 'cloth_secondary', C_TINT_HI, (False, True), False)
            # Weathered briny forearm + barnacle wrist cuff
            tube(body, [el.lerp(wr, 0.42), wr], [0.048, 0.040], 6, 'bone', C_MASK_DARK, (False, True), False)
            tube(body, [el.lerp(wr, 0.82), wr], [0.050, 0.048], 6, 'coral', C_SHELL, (True, True), False)
        with wctx(body, "Hand_" + side):
            h_dir = (ft - wr).normalized()
            side_v = h_dir.cross(Vector((0, 0, -1))).normalized()
            fwd_v = side_v.cross(h_dir).normalized()
            H = Matrix((
                (side_v.x, h_dir.x, fwd_v.x, wr.x),
                (side_v.y, h_dir.y, fwd_v.y, wr.y),
                (side_v.z, h_dir.z, fwd_v.z, wr.z),
                (0.0, 0.0, 0.0, 1.0),
            ))
            with xf(body, H):
                cbox(body, (0.0, 0.050, 0.0), (0.040, 0.084, 0.078), 'bone', C_MASK, 0.012)
                cbox(body, (-sx * 0.014, 0.114, -0.008), (0.032, 0.058, 0.072), 'bone', C_MASK_DARK, 0.010, R('Z', sx * 24))
                cbox(body, (-sx * 0.018, 0.054, -0.052), (0.028, 0.050, 0.030), 'bone', C_MASK_DARK, 0.008, R('X', -30))
                # Glowing aquamarine mystic band across knuckles
                cbox(body, (sx * 0.018, 0.084, 0.0), (0.012, 0.018, 0.074), 'emissive_sea', C_AQUA_GLOW, 0.003)

    # ---- Hooded/Masked Head & Dramatic Asymmetric Branching Coral Crown! (y = 1.48 .. 1.90)
    with wctx(body, "Head"):
        # Thick cowl hood wrapping back & sides of head
        hood = [
            ring_ellipse((0, 1.440, 0.015), 0.125, 0.118, 9, sq=0.30),
            ring_ellipse((0, 1.545, 0.015), 0.132, 0.138, 9, sq=0.30),
            ring_ellipse((0, 1.655, 0.015), 0.136, 0.145, 9, sq=0.28),
            ring_ellipse((0, 1.728, 0.022), 0.102, 0.114, 9, sq=0.22),
            ring_ellipse((0, 1.755, 0.032), 0.042, 0.048, 9, sq=0.18),
        ]
        loft(body, hood, 'cloth_primary', C_TINT_MID, True, (True, True), False,
             scols=[C_TINT_LO, C_TINT_MID, C_TINT_HI, C_TINT_MID])

        # Carved driftwood/bone cultist face mask set into hood front (-Z)
        cbox(body, (0.0, 1.595, -0.105), (0.148, 0.188, 0.068), 'bone', C_MASK, 0.020)
        # Bevelled nasal bridge & hollow shadowed chin
        cbox(body, (0.0, 1.588, -0.138), (0.030, 0.078, 0.028), 'bone', C_MASK_DARK, 0.007)
        # Glowing aquamarine mystic eyes & forehead rune diamond!
        for sx in (-1.0, 1.0):
            cbox(body, (sx * 0.040, 1.615, -0.136), (0.038, 0.022, 0.016), 'bone', C_SOCKET, 0.004, R('Z', -sx * 14))
            cbox(body, (sx * 0.040, 1.615, -0.144), (0.028, 0.013, 0.010), 'emissive_sea', C_AQUA_GLOW, 0.002,
                 R('Z', -sx * 14))
        cbox(body, (0.0, 1.658, -0.138), (0.028, 0.028, 0.014), 'emissive_sea', C_AQUA_GLOW, 0.003, R('Z', 45))
        # Kelp beard/tendrils hanging from mask jaw
        _seaweed_tuft(body, (0.0, 1.505, -0.115), 0.16, 3, "Head")

        # ICONIC ASYMMETRIC BRANCHING CORAL CROWN! (sweeps boldly up to y = 1.90 m!)
        # Right major sweeping staghorn antler + sub-tines
        _coral_branch(body, [
            (0.055, 1.690, -0.020),
            (0.115, 1.760, -0.010),
            (0.165, 1.835, 0.010),
            (0.195, 1.902, 0.028),
        ], 0.032, 0.010, "Head")
        _coral_branch(body, [
            (0.115, 1.760, -0.010),
            (0.175, 1.795, -0.045),
            (0.220, 1.845, -0.060),
        ], 0.022, 0.009, "Head")
        _coral_branch(body, [
            (0.155, 1.825, 0.008),
            (0.125, 1.878, -0.028),
        ], 0.018, 0.008, "Head")

        # Center-right curved crest tine
        _coral_branch(body, [
            (0.015, 1.725, -0.045),
            (0.040, 1.800, -0.055),
            (0.068, 1.862, -0.040),
        ], 0.024, 0.009, "Head")

        # Left counter-balancing shorter splayed coral antlers (asymmetric!)
        _coral_branch(body, [
            (-0.065, 1.685, -0.015),
            (-0.125, 1.745, 0.005),
            (-0.160, 1.825, 0.022),
        ], 0.028, 0.010, "Head")
        _coral_branch(body, [
            (-0.115, 1.738, 0.002),
            (-0.178, 1.765, -0.035),
            (-0.205, 1.805, -0.048),
        ], 0.020, 0.008, "Head")
        _coral_branch(body, [
            (-0.055, 1.710, 0.035),
            (-0.088, 1.780, 0.075),
        ], 0.019, 0.008, "Head")

        # Coral crown base ridge hugging brow
        _barnacle_cluster(body, (0.0, 1.715, -0.075), (0.0, 0.85, -0.5), 4, 0.9, "Head")

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
        export_tangents=False,
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
