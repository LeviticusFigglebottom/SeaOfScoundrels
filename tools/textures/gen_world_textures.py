#!/usr/bin/env python3
"""Generate high-resolution seamless hand-painted painterly PBR textures for
Sea of Scoundrels (terrain biomes + ship timber, lacquer, metals, rope, cloth).

100% original procedural generation (numpy + scipy.ndimage + PIL), deterministic seeded.
Usage: python3 tools/textures/gen_world_textures.py <assets/generated dir>
Writes 27 seamless PBR PNGs into <out>/textures/.

Conventions:
- Every texture tiles seamlessly on both X and Y.
- Normal maps use OpenGL tangent-space convention (+X right, +Y up, +Z out; flat = 128,128,255).
- Ship albedo maps are calibrated to neutral-bright luminance (~0.86..0.95 mean) so multiplying
  with Blender vertex colours keeps hull timber, paint, brass, and iron liveries rich and vibrant.
"""
import os
import sys
import time

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter


SEED = 2507


# ==============================================================================
# Core Seamless Tileable Procedural Primitives (Periodic on X and Y)
# ==============================================================================

def _fade(t: np.ndarray) -> np.ndarray:
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


def perlin_tile(size: int, fx: int, fy: int, rng: np.random.Generator) -> np.ndarray:
    """Seamless periodic 2D gradient noise in roughly [-1, 1]."""
    ang = rng.uniform(0.0, 2.0 * np.pi, (fy, fx))
    gx = np.cos(ang)
    gy = np.sin(ang)
    xs = np.arange(size, dtype=np.float64) * (fx / size)
    ys = np.arange(size, dtype=np.float64) * (fy / size)
    x0 = np.floor(xs).astype(np.int32)
    y0 = np.floor(ys).astype(np.int32)
    dx = (xs - x0)[None, :]
    dy = (ys - y0)[:, None]
    x1 = (x0 + 1) % fx
    y1 = (y0 + 1) % fy
    x0m = x0 % fx
    y0m = y0 % fy

    def dot_corner(yi, xi, ox, oy):
        return gx[np.ix_(yi, xi)] * (dx - ox) + gy[np.ix_(yi, xi)] * (dy - oy)

    n00 = dot_corner(y0m, x0m, 0.0, 0.0)
    n10 = dot_corner(y0m, x1, 1.0, 0.0)
    n01 = dot_corner(y1, x0m, 0.0, 1.0)
    n11 = dot_corner(y1, x1, 1.0, 1.0)
    u = _fade(dx)
    v = _fade(dy)
    nx0 = n00 * (1.0 - u) + n10 * u
    nx1 = n01 * (1.0 - u) + n11 * u
    return (nx0 * (1.0 - v) + nx1 * v) * 1.4142


def fbm_tile(size: int, fx: int, fy: int, octaves: int, rng: np.random.Generator,
             gain: float = 0.5) -> np.ndarray:
    """Normalized periodic fBM in [0, 1]."""
    out = np.zeros((size, size), dtype=np.float64)
    amp = 1.0
    tot = 0.0
    for o in range(octaves):
        mul = 1 << o
        out += amp * perlin_tile(size, fx * mul, fy * mul, rng)
        tot += amp
        amp *= gain
    return np.clip(0.5 + 0.5 * (out / max(tot, 1e-6)), 0.0, 1.0)


def ridged_tile(size: int, fx: int, fy: int, octaves: int, rng: np.random.Generator,
                gain: float = 0.52) -> np.ndarray:
    """Normalized periodic ridged noise in [0, 1] for sharp cracks & ridges."""
    out = np.zeros((size, size), dtype=np.float64)
    amp = 1.0
    tot = 0.0
    for o in range(octaves):
        mul = 1 << o
        n = 1.0 - np.abs(perlin_tile(size, fx * mul, fy * mul, rng))
        out += amp * (n * n)
        tot += amp
        amp *= gain
    return np.clip(out / max(tot, 1e-6), 0.0, 1.0)


def worley_tile(size: int, nx: int, ny: int, rng: np.random.Generator,
                jitter: float = 0.85, warp_x: np.ndarray = None,
                warp_y: np.ndarray = None):
    """Exact seamless periodic Worley/Voronoi cellular noise (F1, F2, cell_id).

    Returns (f1, f2, cell_hash) each shape (size, size) in float64.
    """
    pts_x = (np.arange(nx)[None, :] + 0.5 + (rng.random((ny, nx)) - 0.5) * jitter) / nx
    pts_y = (np.arange(ny)[:, None] + 0.5 + (rng.random((ny, nx)) - 0.5) * jitter) / ny
    cell_val = rng.random((ny, nx))

    u = (np.arange(size, dtype=np.float64) + 0.5) / size
    v = (np.arange(size, dtype=np.float64) + 0.5) / size
    ux, vy = np.meshgrid(u, v)
    if warp_x is not None:
        ux = (ux + warp_x) % 1.0
    if warp_y is not None:
        vy = (vy + warp_y) % 1.0

    cx = np.floor(ux * nx).astype(np.int32) % nx
    cy = np.floor(vy * ny).astype(np.int32) % ny

    f1 = np.full((size, size), 1e9, dtype=np.float64)
    f2 = np.full((size, size), 1e9, dtype=np.float64)
    cid = np.zeros((size, size), dtype=np.float64)

    for dy in (-1, 0, 1):
        ny_idx = (cy + dy) % ny
        for dx in (-1, 0, 1):
            nx_idx = (cx + dx) % nx
            px = pts_x[ny_idx, nx_idx]
            py = pts_y[ny_idx, nx_idx]
            ddx = ux - px
            ddx -= np.round(ddx)
            ddy = vy - py
            ddy -= np.round(ddy)
            dist = np.hypot(ddx * nx, ddy * ny)
            better1 = dist < f1
            better2 = (~better1) & (dist < f2)
            f2 = np.where(better1, f1, np.where(better2, dist, f2))
            f1 = np.where(better1, dist, f1)
            cid = np.where(better1, cell_val[ny_idx, nx_idx], cid)

    return f1, f2, cid


def smoothstep(e0, e1, x: np.ndarray) -> np.ndarray:
    denom = e1 - e0
    safe_denom = np.where(np.abs(denom) < 1e-8, 1e-8, denom)
    t = np.clip((x - e0) / safe_denom, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def lerp3(a, b, t: np.ndarray) -> np.ndarray:
    a_arr = np.asarray(a, dtype=np.float64)
    b_arr = np.asarray(b, dtype=np.float64)
    if a_arr.ndim == 1:
        a_arr = a_arr[None, None, :]
    if b_arr.ndim == 1:
        b_arr = b_arr[None, None, :]
    return a_arr * (1.0 - t[..., None]) + b_arr * t[..., None]


def height_to_normal(height: np.ndarray, strength: float = 3.5) -> np.ndarray:
    """Convert periodic height field in [0, 1] to OpenGL tangent-space normal RGB in [0, 1].

    Uses Scharr-weighted periodic wrap gradient for crisp, seamless, artifact-free bevels.
    OpenGL convention: R = +X right, G = +Y up (top of bump bright green), B = +Z out.
    """
    h = np.asarray(height, dtype=np.float64)
    # Periodic Scharr kernel along X (+col = right) and Y (+row = down).
    hx_l = np.roll(h, 1, axis=1)
    hx_r = np.roll(h, -1, axis=1)
    dh_dcol = (
        3.0 * (np.roll(hx_r, 1, axis=0) - np.roll(hx_l, 1, axis=0))
        + 10.0 * (hx_r - hx_l)
        + 3.0 * (np.roll(hx_r, -1, axis=0) - np.roll(hx_l, -1, axis=0))
    ) / 32.0

    hy_u = np.roll(h, 1, axis=0)
    hy_d = np.roll(h, -1, axis=0)
    dh_drow = (
        3.0 * (np.roll(hy_d, 1, axis=1) - np.roll(hy_u, 1, axis=1))
        + 10.0 * (hy_d - hy_u)
        + 3.0 * (np.roll(hy_d, -1, axis=1) - np.roll(hy_u, -1, axis=1))
    ) / 32.0

    nx = -dh_dcol * strength
    ny = dh_drow * strength
    nz = np.ones_like(h)
    inv_len = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([nx * inv_len * 0.5 + 0.5, ny * inv_len * 0.5 + 0.5, nz * inv_len * 0.5 + 0.5], axis=-1)
    return np.clip(rgb, 0.0, 1.0)


def save_rgb(path: str, arr: np.ndarray) -> None:
    u8 = np.clip(np.rint(arr * 255.0), 0, 255).astype(np.uint8)
    Image.fromarray(u8, mode="RGB").save(path, compress_level=6)


def save_gray(path: str, arr: np.ndarray) -> None:
    u8 = np.clip(np.rint(arr * 255.0), 0, 255).astype(np.uint8)
    Image.fromarray(u8, mode="L").save(path, compress_level=6)


def _stamp_strokes_periodic(size: int, canvas_rgb: np.ndarray, canvas_h: np.ndarray,
                            rng: np.random.Generator, count: int,
                            len_range: tuple, wid_range: tuple,
                            col_base_fn, col_tip_fn, h_amp: float,
                            angle_bias: float = None, angle_spread: float = np.pi,
                            curve_amp: float = 0.25) -> None:
    """Vectorized painterly curved brushstroke / grass blade stamper (periodic wrap)."""
    # Process in small spatial boxes per stroke so 3,000+ rich blades run in < 0.8 s!
    for _ in range(count):
        cx = rng.uniform(0.0, size)
        cy = rng.uniform(0.0, size)
        length = rng.uniform(len_range[0], len_range[1])
        width = rng.uniform(wid_range[0], wid_range[1])
        ang = rng.uniform(-np.pi, np.pi) if angle_bias is None else (angle_bias + rng.uniform(-angle_spread, angle_spread))
        bend = rng.uniform(-curve_amp, curve_amp)
        ca, sa = np.cos(ang), np.sin(ang)

        pad = int(np.ceil(length * 0.65 + width + 2.0))
        lx = np.arange(-pad, pad + 1, dtype=np.float64)
        ly = np.arange(-pad, pad + 1, dtype=np.float64)
        gx, gy = np.meshgrid(lx, ly)
        # Rotate into stroke frame: u along length [-0.5..0.5], v across width
        u = (gx * ca + gy * sa) / max(length, 1.0)
        v = (-gx * sa + gy * ca) - bend * length * (u * u)
        # Tapered leaf / painterly brush blade silhouette
        t_along = np.clip(u + 0.5, 0.0, 1.0)
        half_w = width * (0.28 + 0.72 * np.sin(t_along * np.pi) ** 0.75) * (1.0 - 0.35 * t_along)
        in_len = (u >= -0.5) & (u <= 0.5)
        dist_v = np.abs(v) / np.maximum(half_w, 0.35)
        mask = np.where(in_len, np.clip(1.0 - dist_v * dist_v, 0.0, 1.0), 0.0)
        if mask.max() <= 0.01:
            continue

        c0 = col_base_fn(rng)
        c1 = col_tip_fn(rng)
        stroke_col = c0[None, None, :] * (1.0 - t_along[..., None]) + c1[None, None, :] * t_along[..., None]
        # Slight center ridge sheen along each blade/stroke
        ridge = np.clip(1.0 - dist_v, 0.0, 1.0)
        stroke_col = np.clip(stroke_col * (0.90 + 0.16 * ridge[..., None]), 0.0, 1.0)
        stroke_h = mask * (0.35 + 0.65 * t_along) * h_amp

        x0 = int(round(cx)) - pad
        y0 = int(round(cy)) - pad
        x1 = x0 + 2 * pad + 1
        y1 = y0 + 2 * pad + 1
        alpha = np.clip(mask * 0.88, 0.0, 1.0)
        if x0 >= 0 and y0 >= 0 and x1 <= size and y1 <= size:
            sub_c = canvas_rgb[y0:y1, x0:x1]
            sub_c[:] = sub_c * (1.0 - alpha[..., None]) + stroke_col * alpha[..., None]
            sub_h = canvas_h[y0:y1, x0:x1]
            np.maximum(sub_h, stroke_h, out=sub_h)
        else:
            ix = np.arange(x0, x1, dtype=np.int32) % size
            iy = np.arange(y0, y1, dtype=np.int32) % size
            grid_y, grid_x = np.ix_(iy, ix)
            canvas_rgb[grid_y, grid_x] = canvas_rgb[grid_y, grid_x] * (1.0 - alpha[..., None]) + stroke_col * alpha[..., None]
            canvas_h[grid_y, grid_x] = np.maximum(canvas_h[grid_y, grid_x], stroke_h)


# ==============================================================================
# 1-5. Terrain Seamless Hand-Painted PBR Pairs (1024x1024)
# ==============================================================================

def gen_terrain_grass(out_dir: str, rng: np.random.Generator) -> None:
    N = 1024
    macro = fbm_tile(N, 4, 4, 4, rng)
    mid = fbm_tile(N, 10, 10, 3, rng)
    fine = fbm_tile(N, 28, 28, 3, rng)
    w1, w2, wid = worley_tile(N, 16, 16, rng, 0.9)

    # Rich tropical Sea-of-Scoundrels turf underpainting (deep shade -> sunlit emerald -> warm olive patch)
    col = lerp3((0.15, 0.34, 0.12), (0.36, 0.57, 0.17), smoothstep(0.22, 0.82, macro * 0.6 + mid * 0.4))
    dry_patch = smoothstep(0.62, 0.88, fbm_tile(N, 5, 5, 3, rng))
    col = lerp3(col, (0.52, 0.56, 0.21), dry_patch * 0.34)
    # Soft earthy moss/humus pockets under tuft clusters
    tuft_shadow = smoothstep(0.55, 0.95, w1)
    col = lerp3(col, (0.12, 0.22, 0.09), tuft_shadow * 0.28)
    col *= (0.93 + 0.14 * fine)[..., None]

    height = 0.22 * macro + 0.14 * mid + 0.08 * (1.0 - np.clip(w1, 0.0, 1.0))

    # Layer 1: deep shadow under-blades
    _stamp_strokes_periodic(
        N, col, height, rng, count=1150,
        len_range=(28.0, 58.0), wid_range=(3.5, 6.8),
        col_base_fn=lambda r: np.array([0.11 + r.uniform(-0.02, 0.03), 0.25 + r.uniform(-0.03, 0.04), 0.09 + r.uniform(-0.02, 0.02)]),
        col_tip_fn=lambda r: np.array([0.24 + r.uniform(-0.03, 0.04), 0.45 + r.uniform(-0.04, 0.05), 0.13 + r.uniform(-0.02, 0.03)]),
        h_amp=0.55, angle_bias=-np.pi * 0.45, angle_spread=1.35, curve_amp=0.35
    )
    # Layer 2: vibrant sunlit emerald & warm chartreuse-gold grass blades
    _stamp_strokes_periodic(
        N, col, height, rng, count=1350,
        len_range=(24.0, 52.0), wid_range=(3.0, 6.0),
        col_base_fn=lambda r: np.array([0.19 + r.uniform(-0.03, 0.04), 0.41 + r.uniform(-0.04, 0.05), 0.12 + r.uniform(-0.02, 0.03)]),
        col_tip_fn=lambda r: np.array([0.46 + r.uniform(-0.06, 0.09), 0.68 + r.uniform(-0.05, 0.07), 0.20 + r.uniform(-0.03, 0.05)]),
        h_amp=0.90, angle_bias=-np.pi * 0.48, angle_spread=1.25, curve_amp=0.40
    )
    # Layer 3: small clover / tropical leaf litter specks
    _stamp_strokes_periodic(
        N, col, height, rng, count=320,
        len_range=(11.0, 20.0), wid_range=(4.8, 8.5),
        col_base_fn=lambda r: np.array([0.28 + r.uniform(-0.04, 0.06), 0.52 + r.uniform(-0.05, 0.05), 0.17 + r.uniform(-0.02, 0.03)]),
        col_tip_fn=lambda r: np.array([0.56 + r.uniform(-0.05, 0.08), 0.64 + r.uniform(-0.04, 0.06), 0.25 + r.uniform(-0.03, 0.04)]),
        h_amp=0.95, angle_bias=None, curve_amp=0.12
    )

    height = gaussian_filter(height, sigma=0.75, mode="wrap")
    save_rgb(os.path.join(out_dir, "terrain_grass_albedo.png"), np.clip(col, 0.0, 1.0))
    save_rgb(os.path.join(out_dir, "terrain_grass_normal.png"), height_to_normal(height, strength=4.2))


def gen_terrain_dirt(out_dir: str, rng: np.random.Generator) -> None:
    N = 1024
    macro = fbm_tile(N, 3, 3, 4, rng)
    mid = fbm_tile(N, 8, 8, 4, rng)
    fine = fbm_tile(N, 28, 28, 3, rng)
    grit = perlin_tile(N, 72, 72, rng)

    # Organic painterly brushed coastal clay base (warm sunlit earth -> packed trail umber -> dusty sandy pockets)
    brush_a = fbm_tile(N, 5, 14, 3, rng)
    brush_b = fbm_tile(N, 14, 5, 3, rng)
    soil_mix = smoothstep(0.18, 0.84, macro * 0.48 + mid * 0.30 + brush_a * 0.22)
    col = lerp3((0.40, 0.28, 0.17), (0.66, 0.50, 0.32), soil_mix)
    # Warm dry sandy trail dust patches
    sandy = smoothstep(0.56, 0.88, fbm_tile(N, 4, 4, 3, rng) * 0.65 + brush_b * 0.35)
    col = lerp3(col, (0.78, 0.64, 0.44), sandy * 0.40)
    # Damp rich humus shade pockets
    damp = smoothstep(0.62, 0.90, 1.0 - macro * 0.6 - mid * 0.4)
    col = lerp3(col, (0.28, 0.19, 0.11), damp * 0.38)
    col *= (0.91 + 0.16 * fine + 0.04 * grit)[..., None]

    height = 0.50 + 0.18 * (macro - 0.5) + 0.12 * (mid - 0.5) + 0.08 * (fine - 0.5) + 0.03 * grit

    # Localized, organically broken sun-baked clay desiccation cracks (ONLY in dry clay patches, never a global web!)
    dry_zone = smoothstep(0.54, 0.80, fbm_tile(N, 3, 3, 2, rng))
    wx = (fbm_tile(N, 8, 8, 2, rng) - 0.5) * 0.06
    wy = (fbm_tile(N, 8, 8, 2, rng) - 0.5) * 0.06
    c1, c2, _ = worley_tile(N, 9, 9, rng, 0.92, wx, wy)
    crack = (1.0 - smoothstep(0.008, 0.045, c2 - c1)) * dry_zone * smoothstep(0.32, 0.72, ridged_tile(N, 8, 8, 2, rng))
    col = lerp3(col, (0.20, 0.13, 0.08), crack * 0.58)
    height -= 0.18 * crack

    # Organic painterly soil clumps & scattered irregular earthy pebbles (correlated warm earth/stone palette!)
    def _earth_clump_col(r, hi: bool):
        k = r.uniform(0.84, 1.16)
        base = np.array([0.58, 0.44, 0.28]) if hi else np.array([0.44, 0.32, 0.19])
        return np.clip(base * k, 0.0, 1.0)

    def _pebble_col(r, hi: bool):
        k = r.uniform(0.82, 1.14)
        warm = r.uniform(-0.03, 0.04)
        base = np.array([0.64 + warm, 0.57 + warm * 0.5, 0.45 - warm * 0.5]) if hi else np.array([0.46 + warm, 0.40, 0.31])
        return np.clip(base * k, 0.0, 1.0)

    _stamp_strokes_periodic(
        N, col, height, rng, count=420,
        len_range=(28.0, 74.0), wid_range=(10.0, 24.0),
        col_base_fn=lambda r: _earth_clump_col(r, False),
        col_tip_fn=lambda r: _earth_clump_col(r, True),
        h_amp=0.58, angle_bias=0.35, angle_spread=0.85, curve_amp=0.22
    )
    _stamp_strokes_periodic(
        N, col, height, rng, count=240,
        len_range=(10.0, 26.0), wid_range=(6.0, 15.0),
        col_base_fn=lambda r: _pebble_col(r, False),
        col_tip_fn=lambda r: _pebble_col(r, True),
        h_amp=0.86, angle_bias=None, curve_amp=0.14
    )
    # Fine exposed coastal root tendrils & twigs
    _stamp_strokes_periodic(
        N, col, height, rng, count=110,
        len_range=(32.0, 84.0), wid_range=(1.8, 4.0),
        col_base_fn=lambda r: np.array([0.27, 0.18, 0.10]),
        col_tip_fn=lambda r: np.array([0.44, 0.31, 0.18]),
        h_amp=0.78, angle_bias=None, curve_amp=0.55
    )

    height = gaussian_filter(height, sigma=0.75, mode="wrap")
    height = (height - height.min()) / max(height.max() - height.min(), 1e-6)
    save_rgb(os.path.join(out_dir, "terrain_dirt_albedo.png"), np.clip(col, 0.0, 1.0))
    save_rgb(os.path.join(out_dir, "terrain_dirt_normal.png"), height_to_normal(height, strength=5.8))


def gen_terrain_sand(out_dir: str, rng: np.random.Generator) -> None:
    N = 1024
    u = np.arange(N, dtype=np.float64) / N
    ux, vy = np.meshgrid(u, u)

    macro = fbm_tile(N, 3, 3, 4, rng)
    mid = fbm_tile(N, 8, 8, 3, rng)
    grain = fbm_tile(N, 44, 44, 3, rng)
    sparkle = perlin_tile(N, 96, 96, rng)

    # Wind-sculpted asymmetric periodic sand ripples (10 diagonal waves per tile, organically branching)
    phase = 2.0 * np.pi * (5.0 * ux + 10.0 * vy) + (macro - 0.5) * 5.2 + (mid - 0.5) * 2.1
    ripple = 0.5 + 0.38 * np.sin(phase) + 0.15 * np.sin(2.0 * phase - 0.50) + 0.05 * np.sin(3.0 * phase - 1.0)
    ripple = np.clip(ripple, 0.0, 1.0)
    amp_mod = 0.55 + 0.45 * fbm_tile(N, 4, 4, 3, rng)
    sand_h = 0.5 + (ripple - 0.5) * amp_mod * 0.72 + (macro - 0.5) * 0.16 + (grain - 0.5) * 0.09

    # Warm golden-ivory crests to sun-baked honey-amber troughs
    col = lerp3((0.74, 0.59, 0.37), (0.95, 0.86, 0.62), smoothstep(0.14, 0.88, sand_h))
    col *= (0.94 + 0.12 * grain)[..., None]

    # Natural irregular crushed coral/shell flecks & tiny tan beach pebbles nestled in ripple troughs
    trough_w = 0.35 + 0.65 * (1.0 - ripple)
    shell_n = smoothstep(0.76, 0.94, fbm_tile(N, 42, 42, 2, rng)) * trough_w
    coral_n = smoothstep(0.80, 0.95, fbm_tile(N, 52, 52, 2, rng)) * trough_w
    col = lerp3(col, (0.97, 0.93, 0.84), shell_n * 0.45)
    col = lerp3(col, (0.88, 0.68, 0.56), coral_n * 0.35)
    quartz = smoothstep(0.68, 0.95, sparkle) * 0.06
    col = np.clip(col + quartz[..., None], 0.0, 1.0)
    sand_h += 0.04 * shell_n

    sand_h = gaussian_filter(sand_h, sigma=0.75, mode="wrap")
    sand_h = (sand_h - sand_h.min()) / max(sand_h.max() - sand_h.min(), 1e-6)
    save_rgb(os.path.join(out_dir, "terrain_sand_albedo.png"), np.clip(col, 0.0, 1.0))
    save_rgb(os.path.join(out_dir, "terrain_sand_normal.png"), height_to_normal(sand_h, strength=10.5))


def gen_terrain_cliff(out_dir: str, rng: np.random.Generator) -> None:
    N = 1024
    u = np.arange(N, dtype=np.float64) / N
    ux, vy = np.meshgrid(u, u)

    macro = fbm_tile(N, 3, 3, 4, rng)
    mid = fbm_tile(N, 8, 8, 4, rng)
    fine = fbm_tile(N, 28, 28, 3, rng)

    # Non-periodic horizontally-stretched geological strata via anisotropic fBM (zero regular zebra stripes!)
    strata_broad = fbm_tile(N, 2, 7, 3, rng)
    strata_detail = fbm_tile(N, 3, 16, 3, rng)
    strata = np.clip(strata_broad * 0.65 + strata_detail * 0.35 + (macro - 0.5) * 0.14, 0.0, 1.0)
    shelf_step = smoothstep(0.26, 0.74, strata)
    # Natural broken horizontal bedding crevices where strata transition steeply
    shelf_crease = smoothstep(0.10, 0.015, np.abs(strata - 0.42)) * (0.45 + 0.55 * mid)
    shelf_crease = np.maximum(shelf_crease, smoothstep(0.08, 0.012, np.abs(strata - 0.68)) * 0.65 * mid)

    # Chiseled painterly rock fracture planes & broken vertical joints (organic ridged noise, NOT a closed polygon grid!)
    v_crack_a = smoothstep(0.76, 0.96, ridged_tile(N, 8, 3, 3, rng))
    v_crack_b = smoothstep(0.80, 0.97, ridged_tile(N, 15, 6, 2, rng))
    diag_chisel = fbm_tile(N, 6, 12, 3, rng)
    fracture = np.clip(v_crack_a * 0.72 + v_crack_b * 0.42, 0.0, 1.0)

    # Vertical mineral rainwater wash & warm ochre-terracotta mineral bands
    rain_wash = fbm_tile(N, 14, 2, 3, rng)
    ochre_band = smoothstep(0.46, 0.84, fbm_tile(N, 2, 9, 3, rng) * 0.7 + (1.0 - strata_broad) * 0.3)

    # Sea-of-Scoundrels sunlit coastal cliff palette (ivory limestone + warm sandstone ochre + cool weathered crevices)
    col = lerp3((0.64, 0.49, 0.35), (0.87, 0.79, 0.64), shelf_step * 0.68 + diag_chisel * 0.32)
    col = lerp3(col, (0.76, 0.53, 0.31), ochre_band * 0.48)
    sun_lip = smoothstep(0.42, 0.56, strata) * smoothstep(0.76, 0.56, strata)
    col = lerp3(col, (0.94, 0.88, 0.75), sun_lip * 0.28)
    col = lerp3(col, (0.46, 0.40, 0.34), smoothstep(0.55, 0.88, 1.0 - rain_wash) * 0.28)
    col = lerp3(col, (0.28, 0.23, 0.20), np.clip(shelf_crease * 0.64 + fracture * 0.55, 0.0, 0.82))
    col *= (0.91 + 0.16 * fine)[..., None]

    height = (
        0.42 * shelf_step
        + 0.22 * diag_chisel
        + 0.14 * (mid - 0.5)
        + 0.10 * fine
        - 0.34 * shelf_crease
        - 0.30 * fracture
    )
    height = gaussian_filter(height, sigma=0.75, mode="wrap")
    height = (height - height.min()) / max(height.max() - height.min(), 1e-6)
    save_rgb(os.path.join(out_dir, "terrain_cliff_albedo.png"), np.clip(col, 0.0, 1.0))
    save_rgb(os.path.join(out_dir, "terrain_cliff_normal.png"), height_to_normal(height, strength=7.5))


def gen_terrain_volcanic(out_dir: str, rng: np.random.Generator) -> None:
    N = 1024
    macro = fbm_tile(N, 4, 4, 4, rng)
    mid = fbm_tile(N, 10, 10, 4, rng)
    fine = fbm_tile(N, 36, 36, 3, rng)

    # Sharp jagged fractured obsidian-basalt slabs via multi-directional ridged fractures (NO convex honeycomb dots!)
    r1 = ridged_tile(N, 6, 6, 4, rng)
    r2 = ridged_tile(N, 12, 8, 3, rng)
    r3 = ridged_tile(N, 22, 22, 3, rng)

    # Deep jagged cooling fissures where ridged bands peak sharply
    main_fissure = smoothstep(0.70, 0.94, r1)
    branch_crack = smoothstep(0.74, 0.95, r2) * 0.65
    fissure = np.clip(main_fissure + branch_crack, 0.0, 1.0)

    # Chiseled overlapping obsidian slab facets (stepped domain-warped rock planes)
    slab_raw = fbm_tile(N, 6, 6, 3, rng) * 0.55 + (1.0 - r2) * 0.45
    slab_step = smoothstep(0.24, 0.78, slab_raw)
    scoria_pores = smoothstep(0.68, 0.92, 1.0 - fine) * smoothstep(0.35, 0.80, r3)

    # Rich dark basalt-obsidian ridges -> charcoal rock faces -> pale ash dusted fissure rims -> deep black cracks
    col = lerp3((0.11, 0.10, 0.13), (0.31, 0.27, 0.28), slab_step * 0.65 + (1.0 - r1) * 0.35)
    # Warm oxidized iron-basalt catchlights on sharp fractured crests
    crest = smoothstep(0.55, 0.85, slab_step) * smoothstep(0.45, 0.78, mid)
    col = lerp3(col, (0.39, 0.30, 0.26), crest * 0.42)
    # Fine grey volcanic ash settling in jagged mid-crevices
    ash_dust = smoothstep(0.54, 0.74, r1) * (1.0 - main_fissure * 0.8) * (0.40 + 0.60 * macro)
    col = lerp3(col, (0.48, 0.45, 0.43), ash_dust * 0.45)
    # Deep obsidian cooling trenches & vesicular scoria pits
    col = lerp3(col, (0.04, 0.035, 0.05), np.clip(fissure * 0.88 + scoria_pores * 0.50, 0.0, 0.92))
    col *= (0.88 + 0.22 * fine)[..., None]

    height = (
        0.44 * slab_step
        + 0.24 * (1.0 - r2)
        + 0.12 * fine
        - 0.48 * main_fissure
        - 0.22 * branch_crack
        - 0.16 * scoria_pores
    )
    height = gaussian_filter(height, sigma=0.65, mode="wrap")
    height = (height - height.min()) / max(height.max() - height.min(), 1e-6)
    save_rgb(os.path.join(out_dir, "terrain_volcanic_albedo.png"), np.clip(col, 0.0, 1.0))
    save_rgb(os.path.join(out_dir, "terrain_volcanic_normal.png"), height_to_normal(height, strength=8.2))


# ==============================================================================
# 6-11. Ship Hand-Painted PBR Texture Sets (Neutral-Bright for Vertex-Colour Multiply)
# ==============================================================================

def gen_ship_oak(out_dir: str, rng: np.random.Generator) -> None:
    """1024x1024 staggered weathered oak hull/deck planking (8 courses along V, grain along U).

    Features per-plank tonal & grain variation, staggered butt joints, tarred caulking seams,
    organic grain-deflecting wood knots, hammered iron trunnel nail pairs aligned to exact joints,
    salt-bleached bevels, tangent-space normal map, and worn-wood vs matte-caulk roughness map.
    """
    N = 1024
    N_PLANKS = 8

    u = np.arange(N, dtype=np.float64) / N  # along grain / plank length
    v = np.arange(N, dtype=np.float64) / N  # across plank courses
    ux, vy = np.meshgrid(u, v)

    row_idx = (np.floor(vy * N_PLANKS).astype(np.int32)) % N_PLANKS
    row_local_v = (vy * N_PLANKS) % 1.0  # 0..1 across each plank's width

    # Per-row staggered butt joints (stored so nail pairs ALWAYS sit cleanly beside the exact seam!)
    butt_offsets = [0.13, 0.61, 0.34, 0.82, 0.22, 0.71, 0.46, 0.91]
    row_joints = []
    plank_id = np.zeros((N, N), dtype=np.int32)
    dist_butt = np.ones((N, N), dtype=np.float64)

    for r in range(N_PLANKS):
        rmask = row_idx == r
        j0 = butt_offsets[r]
        j1 = (j0 + 0.50 + rng.uniform(-0.04, 0.04)) % 1.0
        joints = sorted([j0, j1])
        row_joints.append(joints)
        seg = np.where((ux >= joints[0]) & (ux < joints[1]), 0, 1)
        plank_id[rmask] = r * 2 + seg[rmask]
        for ju in joints:
            du = ux - ju
            du -= np.round(du)
            adu = np.abs(du)
            closer = rmask & (adu < dist_butt)
            dist_butt = np.where(closer, adu, dist_butt)

    # Distinct per-plank warm/cool tint, luminance & grain phase so zero planks look copy-pasted!
    n_unique = N_PLANKS * 2
    plank_lum = rng.uniform(0.90, 1.04, n_unique)
    plank_warm = rng.uniform(-0.036, 0.036, n_unique)
    plank_phase = rng.uniform(0.0, 2.0 * np.pi, n_unique)
    plank_slope = rng.uniform(-0.18, 0.18, n_unique)

    p_lum = plank_lum[plank_id]
    p_warm = plank_warm[plank_id]
    p_phase = plank_phase[plank_id]
    p_slope = plank_slope[plank_id]

    # Organic wood knots (1-2 knots per course) that physically deflect grain lines!
    knot_warp = np.zeros((N, N), dtype=np.float64)
    knot_dark = np.zeros((N, N), dtype=np.float64)
    knot_dip = np.zeros((N, N), dtype=np.float64)
    for r in range(N_PLANKS):
        joints = row_joints[r]
        n_knots = 2 if (r % 2 == 0) else 1
        for k in range(n_knots):
            # Place knots squarely inside plank middles, safely away from butt joints & nails
            mid_u = 0.5 * (joints[0] + joints[1]) if k == 0 else ((0.5 * (joints[0] + joints[1]) + 0.5) % 1.0)
            ku = (mid_u + rng.uniform(-0.08, 0.08)) % 1.0
            kv = (r + rng.uniform(0.30, 0.70)) / N_PLANKS
            kr_u = rng.uniform(0.028, 0.048)
            kr_v = rng.uniform(0.011, 0.018)
            du = ux - ku
            du -= np.round(du)
            dv = vy - kv
            dv -= np.round(dv)
            er = np.hypot(du / kr_u, dv / kr_v)
            deflect = np.exp(-0.5 * (er / 1.35) ** 2) * (dv / max(kr_v, 1e-4))
            knot_warp += deflect * 0.15
            ring_pattern = 0.5 + 0.5 * np.sin(er * 11.5)
            k_mask = smoothstep(1.15, 0.32, er)
            knot_dark = np.maximum(knot_dark, k_mask * (0.45 + 0.32 * ring_pattern))
            knot_dip = np.maximum(knot_dip, smoothstep(1.0, 0.2, er) * 0.24)

    # Rich cathedral oak wood grain flowing along U (horizontal) with knot deflection & fine fibers
    base_warp = (fbm_tile(N, 3, 6, 3, rng) - 0.5) * 0.14
    fine_warp = perlin_tile(N, 8, 24, rng) * 0.036
    gv_coord = row_local_v + p_slope * ux + base_warp + fine_warp + knot_warp
    grain_broad = 0.5 + 0.5 * np.sin(gv_coord * 2.0 * np.pi * 3.5 + p_phase)
    grain_mid = 0.5 + 0.5 * np.sin(gv_coord * 2.0 * np.pi * 9.0 + p_phase * 1.7 + base_warp * 8.0)
    fibers = fbm_tile(N, 4, 64, 3, rng)
    micro_pores = perlin_tile(N, 12, 128, rng)
    brush = fbm_tile(N, 6, 18, 2, rng)

    grain_val = 0.93 + 0.10 * (grain_broad - 0.5) + 0.08 * (grain_mid - 0.5) + 0.12 * (fibers - 0.5)
    pore_lines = smoothstep(0.32, 0.08, fibers) * 0.14 + smoothstep(0.55, 0.90, -micro_pores) * 0.06
    grain_val -= pore_lines

    # Horizontal & vertical tarred caulking seams + salt-bleached chamfered edge highlights
    dist_h_edge = np.minimum(row_local_v, 1.0 - row_local_v)
    seam_h = 1.0 - smoothstep(0.018, 0.044, dist_h_edge)
    seam_v = 1.0 - smoothstep(0.0022, 0.0055, dist_butt)
    seam = np.maximum(seam_h, seam_v)

    bevel_h = smoothstep(0.025, 0.065, dist_h_edge) * smoothstep(0.14, 0.065, dist_h_edge)
    bevel_v = smoothstep(0.003, 0.009, dist_butt) * smoothstep(0.022, 0.009, dist_butt)
    edge_bleach = np.maximum(bevel_h, bevel_v) * (0.55 + 0.45 * brush)

    # Pairs of hammered iron trunnel nail heads flanking EVERY exact butt joint!
    nail_mask = np.zeros((N, N), dtype=np.float64)
    nail_ring = np.zeros((N, N), dtype=np.float64)
    nail_r = 0.0052
    for r in range(N_PLANKS):
        for ju in row_joints[r]:
            for side_u in (-0.016, 0.016):
                nu = (ju + side_u) % 1.0
                for nv_loc in (0.28, 0.72):
                    nv = (r + nv_loc) / N_PLANKS
                    du = ux - nu
                    du -= np.round(du)
                    dv = vy - nv
                    dv -= np.round(dv)
                    nd = np.hypot(du, dv)
                    nail_mask = np.maximum(nail_mask, smoothstep(nail_r, nail_r * 0.55, nd))
                    nail_ring = np.maximum(nail_ring, smoothstep(nail_r * 1.65, nail_r * 0.95, nd) * smoothstep(nail_r * 0.55, nail_r * 0.95, nd))

    # Neutral-bright warm oak modulation (mean ~0.84 so C_HULL / C_DECK / C_DARK stay rich & vibrant!)
    base_l = grain_val * p_lum + 0.055 * edge_bleach
    albedo = np.stack([
        base_l * (1.018 + p_warm),
        base_l * 0.994,
        base_l * (0.942 - p_warm * 0.8),
    ], axis=-1)
    albedo = albedo * (1.0 - 0.52 * knot_dark[..., None]) + np.array([0.28, 0.20, 0.14])[None, None, :] * (0.52 * knot_dark[..., None])
    albedo = albedo * (1.0 - 0.74 * seam[..., None]) + np.array([0.14, 0.11, 0.09])[None, None, :] * (0.74 * seam[..., None])
    albedo *= (1.0 - 0.22 * nail_ring[..., None])
    albedo = albedo * (1.0 - 0.72 * nail_mask[..., None]) + np.array([0.22, 0.21, 0.22])[None, None, :] * (0.72 * nail_mask[..., None])
    albedo = np.clip(albedo, 0.05, 1.0)

    plank_crown = np.sqrt(np.clip(smoothstep(0.02, 0.14, dist_h_edge), 0.0, 1.0)) * np.sqrt(np.clip(smoothstep(0.002, 0.015, dist_butt), 0.0, 1.0))
    height = (
        0.52 * plank_crown
        + 0.18 * grain_val
        + 0.06 * (fibers - 0.5)
        - 0.36 * seam
        - knot_dip
        - 0.10 * nail_ring
        + 0.08 * nail_mask
    )
    height = gaussian_filter(height, sigma=0.65, mode="wrap")
    height = (height - height.min()) / max(height.max() - height.min(), 1e-6)

    rough = 0.78 - 0.16 * np.clip(grain_broad * plank_crown, 0.0, 1.0) + 0.12 * pore_lines + 0.18 * seam + 0.10 * knot_dark - 0.14 * nail_mask
    rough = np.clip(rough, 0.54, 0.96)

    save_rgb(os.path.join(out_dir, "ship_oak_albedo.png"), albedo)
    save_rgb(os.path.join(out_dir, "ship_oak_normal.png"), height_to_normal(height, strength=5.8))
    save_gray(os.path.join(out_dir, "ship_oak_rough.png"), rough)


def gen_ship_paint(out_dir: str, rng: np.random.Generator) -> None:
    """512x512 hand-brushed marine lacquer over subtle timber grain (neutral-bright ~0.89)."""
    N = 512
    brush_broad = fbm_tile(N, 2, 12, 3, rng)
    brush_long = fbm_tile(N, 4, 34, 3, rng)
    wood_under = fbm_tile(N, 2, 24, 3, rng)
    patina = fbm_tile(N, 5, 5, 3, rng)
    weather_wear = smoothstep(0.64, 0.88, ridged_tile(N, 8, 8, 3, rng)) * smoothstep(0.45, 0.82, patina)

    # Tactile overlapping painterly marine lacquer brushwork (mean ~0.89, crisp std ~0.05)
    val = (
        0.89
        + 0.16 * (brush_broad - 0.5)
        + 0.12 * (brush_long - 0.5)
        + 0.08 * (patina - 0.5)
        - 0.22 * weather_wear
    )
    albedo = np.stack([
        val * (1.008 + 0.025 * weather_wear),
        val * 0.998,
        val * (0.985 - 0.025 * weather_wear),
    ], axis=-1)
    albedo = np.clip(albedo, 0.52, 1.0)

    height = 0.42 * wood_under + 0.34 * brush_broad + 0.24 * brush_long - 0.34 * weather_wear
    height = gaussian_filter(height, sigma=0.65, mode="wrap")
    height = (height - height.min()) / max(height.max() - height.min(), 1e-6)

    rough = 0.52 + 0.16 * (1.0 - brush_broad) + 0.12 * (patina - 0.5) + 0.26 * weather_wear
    rough = np.clip(rough, 0.36, 0.84)

    save_rgb(os.path.join(out_dir, "ship_paint_albedo.png"), albedo)
    save_rgb(os.path.join(out_dir, "ship_paint_normal.png"), height_to_normal(height, strength=4.2))
    save_gray(os.path.join(out_dir, "ship_paint_rough.png"), rough)


def gen_ship_iron(out_dir: str, rng: np.random.Generator) -> None:
    """512x512 hand-forged naval wrought iron: hammered anvil dimples, forge scale & subtle rust."""
    N = 512
    f1, f2, cid = worley_tile(N, 10, 10, rng, 0.90)
    f1_s, _, _ = worley_tile(N, 22, 22, rng, 0.92)
    scale_n = fbm_tile(N, 8, 8, 4, rng)
    micro_n = fbm_tile(N, 28, 28, 3, rng)
    rust_field = smoothstep(0.60, 0.86, fbm_tile(N, 5, 5, 3, rng))

    # Authentic soft hammered anvil dimples (NO caustic white Voronoi web lines!)
    # Smooth concave bowl inside each hammer strike + gentle organic forge-scale mottling
    dimple_cup = smoothstep(0.0, 0.92, f1) ** 1.45
    fine_cup = smoothstep(0.0, 0.95, f1_s) ** 1.4
    hammer_h = 0.55 * dimple_cup + 0.25 * fine_cup + 0.20 * scale_n
    hammer_h = gaussian_filter(hammer_h, sigma=1.6, mode="wrap")

    # Subtle warm rust-oxide speckles tucked in deeper anvil dimple centers & scale pits
    rust_pits = rust_field * smoothstep(0.45, 0.90, 1.0 - dimple_cup) * smoothstep(0.42, 0.78, 1.0 - micro_n) * 0.55

    # Neutral-bright mottled hammered metal modulation (~0.85 mean, smooth without hard Voronoi polygon steps!)
    val = 0.84 + 0.18 * (hammer_h - 0.5) + 0.16 * (scale_n - 0.5) + 0.08 * (micro_n - 0.5)
    albedo = np.stack([
        val * (1.0 + 0.26 * rust_pits),
        val * (1.0 - 0.02 * rust_pits),
        val * (1.0 - 0.28 * rust_pits),
    ], axis=-1)
    albedo = np.clip(albedo, 0.45, 1.0)

    height = 0.65 * hammer_h + 0.20 * scale_n + 0.15 * micro_n - 0.12 * rust_pits
    height = (height - height.min()) / max(height.max() - height.min(), 1e-6)

    # Burnished forged metal highs (0.36) vs matte forge scale & rust crevices (0.70)
    rough = 0.52 - 0.16 * (hammer_h - 0.5) + 0.16 * (1.0 - scale_n) + 0.22 * rust_pits
    rough = np.clip(rough, 0.34, 0.72)

    save_rgb(os.path.join(out_dir, "ship_iron_albedo.png"), albedo)
    save_rgb(os.path.join(out_dir, "ship_iron_normal.png"), height_to_normal(height, strength=5.0))
    save_gray(os.path.join(out_dir, "ship_iron_rough.png"), rough)


def gen_ship_brass(out_dir: str, rng: np.random.Generator) -> None:
    """512x512 brushed marine brass with directional lathe polish & authentic muted sea-salt patina."""
    N = 512
    brush = fbm_tile(N, 3, 44, 3, rng)
    fine_lathe = perlin_tile(N, 6, 88, rng)
    patina_n = fbm_tile(N, 6, 6, 3, rng)
    tarnish = smoothstep(0.60, 0.88, ridged_tile(N, 9, 9, 2, rng)) * smoothstep(0.42, 0.82, patina_n)

    # Warm brushed marine brass modulation (~0.90 mean) with subtle muted olive-bronze sea-salt patina
    val = 0.91 + 0.12 * (brush - 0.5) + 0.05 * fine_lathe + 0.06 * (patina_n - 0.5) - 0.26 * tarnish
    albedo = np.stack([
        val * (1.0 - 0.18 * tarnish),
        val * (1.0 - 0.02 * tarnish),
        val * (0.97 + 0.04 * tarnish),
    ], axis=-1)
    albedo = np.clip(albedo, 0.48, 1.0)

    height = 0.52 * brush + 0.26 * (0.5 + 0.5 * fine_lathe) + 0.22 * patina_n - 0.26 * tarnish
    height = gaussian_filter(height, sigma=0.65, mode="wrap")
    height = (height - height.min()) / max(height.max() - height.min(), 1e-6)

    rough = 0.28 + 0.12 * (1.0 - brush) + 0.26 * tarnish
    rough = np.clip(rough, 0.20, 0.52)

    save_rgb(os.path.join(out_dir, "ship_brass_albedo.png"), albedo)
    save_rgb(os.path.join(out_dir, "ship_brass_normal.png"), height_to_normal(height, strength=3.2))
    save_gray(os.path.join(out_dir, "ship_brass_rough.png"), rough)


def gen_ship_rope(out_dir: str, rng: np.random.Generator) -> None:
    """512x512 twisted 3-strand braided maritime hemp rope (seamless diagonal helical strands)."""
    N = 512
    u = np.arange(N, dtype=np.float64) / N
    ux, vy = np.meshgrid(u, u)

    # Organic slight warp so braided strands feel hand-laid hemp, not mechanical stripes
    warp = (fbm_tile(N, 6, 6, 3, rng) - 0.5) * 0.42
    strand_phase = 2.0 * np.pi * (6.0 * ux + 3.0 * vy) + warp
    strand_h = np.abs(np.sin(strand_phase * 0.5)) ** 0.78
    groove = smoothstep(0.36, 0.02, strand_h)

    # Rich twisted flax yarn fibers running diagonally across each braided strand
    f_warp = (fbm_tile(N, 12, 12, 2, rng) - 0.5) * 3.0
    fiber_a = 0.5 + 0.5 * np.sin(2.0 * np.pi * (18.0 * ux - 12.0 * vy) + f_warp)
    fiber_b = 0.5 + 0.5 * np.sin(2.0 * np.pi * (36.0 * ux - 24.0 * vy) + f_warp * 1.6)
    fibers = fiber_a * 0.65 + fiber_b * 0.35
    flax_noise = fbm_tile(N, 24, 24, 3, rng)

    val = 0.72 + 0.24 * strand_h + 0.14 * (fibers - 0.5) + 0.10 * (flax_noise - 0.5) - 0.36 * groove
    albedo = np.stack([
        val * 1.025,
        val * 0.992,
        val * 0.935,
    ], axis=-1)
    albedo = np.clip(albedo, 0.20, 1.0)

    height = 0.64 * strand_h + 0.22 * fibers + 0.14 * flax_noise - 0.28 * groove
    height = gaussian_filter(height, sigma=0.55, mode="wrap")
    height = (height - height.min()) / max(height.max() - height.min(), 1e-6)

    rough = 0.85 + 0.12 * groove + 0.07 * (1.0 - fibers)
    rough = np.clip(rough, 0.80, 0.98)

    save_rgb(os.path.join(out_dir, "ship_rope_albedo.png"), albedo)
    save_rgb(os.path.join(out_dir, "ship_rope_normal.png"), height_to_normal(height, strength=6.8))
    save_gray(os.path.join(out_dir, "ship_rope_rough.png"), rough)


def gen_ship_cloth(out_dir: str, rng: np.random.Generator) -> None:
    """512x512 heavy woven sailor canvas / linen cloth (crisp warp/weft weave + subtle folds)."""
    N = 512
    u = np.arange(N, dtype=np.float64) / N
    ux, vy = np.meshgrid(u, u)

    # Slightly irregular hand-loomed warp & weft thread frequencies (64 threads per tile)
    w_warp = (fbm_tile(N, 8, 8, 2, rng) - 0.5) * 0.012
    w_weft = (fbm_tile(N, 8, 8, 2, rng) - 0.5) * 0.012
    t_u = (ux + w_warp) * 64.0
    t_v = (vy + w_weft) * 64.0

    # Authentic over-under plain linen weave (alternating parity per thread cell!)
    cell_parity = ((np.floor(t_u).astype(np.int32) + np.floor(t_v).astype(np.int32)) & 1).astype(np.float64)
    fu = np.sin((t_u % 1.0) * np.pi)
    fv = np.sin((t_v % 1.0) * np.pi)
    # Thread dome along warp when parity==0, weft when parity==1
    thread_u = (fu ** 0.75) * (0.65 + 0.35 * fv)
    thread_v = (fv ** 0.75) * (0.65 + 0.35 * fu)
    weave_h = np.where(cell_parity < 0.5, thread_u, thread_v)

    soft_fold = fbm_tile(N, 4, 4, 3, rng)
    slub = fbm_tile(N, 16, 48, 2, rng) * 0.5 + fbm_tile(N, 48, 16, 2, rng) * 0.5

    # Neutral-bright linen (~0.93 mean) so dyed cushions, curtains, rugs & hammocks stay vivid
    val = 0.85 + 0.13 * weave_h + 0.06 * (soft_fold - 0.5) + 0.05 * (slub - 0.5)
    albedo = np.stack([val * 1.01, val * 1.00, val * 0.98], axis=-1)
    albedo = np.clip(albedo, 0.65, 1.0)

    height = 0.62 * weave_h + 0.24 * soft_fold + 0.14 * slub
    height = gaussian_filter(height, sigma=0.55, mode="wrap")

    save_rgb(os.path.join(out_dir, "ship_cloth_albedo.png"), albedo)
    save_rgb(os.path.join(out_dir, "ship_cloth_normal.png"), height_to_normal(height, strength=3.4))


def main() -> None:
    t0 = time.perf_counter()
    outdir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.getcwd(), "assets", "generated")
    tex_dir = os.path.join(outdir, "textures")
    os.makedirs(tex_dir, exist_ok=True)

    generators = [
        ("terrain_grass", gen_terrain_grass),
        ("terrain_dirt", gen_terrain_dirt),
        ("terrain_sand", gen_terrain_sand),
        ("terrain_cliff", gen_terrain_cliff),
        ("terrain_volcanic", gen_terrain_volcanic),
        ("ship_oak", gen_ship_oak),
        ("ship_paint", gen_ship_paint),
        ("ship_iron", gen_ship_iron),
        ("ship_brass", gen_ship_brass),
        ("ship_rope", gen_ship_rope),
        ("ship_cloth", gen_ship_cloth),
    ]
    for idx, (label, fn) in enumerate(generators):
        ts = time.perf_counter()
        rng = np.random.default_rng(SEED + idx * 1009)
        fn(tex_dir, rng)
        print(f"  [{idx + 1:2d}/{len(generators)}] {label:<18s} ({time.perf_counter() - ts:.2f} s)")

    print(f"wrote 27 seamless PBR textures into {tex_dir} in {time.perf_counter() - t0:.2f} s")


if __name__ == "__main__":
    main()
