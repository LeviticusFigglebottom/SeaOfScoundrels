#!/usr/bin/env python3
"""Generate high-resolution 1024x1024 seamless hand-crafted PBR textures for
Sea of Scoundrels (5 terrain biomes + 6 ship & prop material sets).

100% original procedural generation (numpy + scipy.ndimage + PIL), deterministic seeded.
Usage: python3 tools/textures/gen_world_textures.py [assets/generated dir]
Writes 27 seamless 1024x1024 PBR PNGs into <out>/textures/.

Conventions:
- Every texture is 1024x1024 and tiles seamlessly on both X and Y (toroidal wrap).
- Normal maps use OpenGL tangent-space convention (+X right, +Y up, +Z out; flat = 128,128,255).
- Ship albedo maps are calibrated to neutral-bright luminance (~0.82..0.93 mean) so multiplying
  with Blender vertex colours keeps hull timber, paint, brass, iron, rope, and cloth vibrant.
"""
from concurrent.futures import ProcessPoolExecutor
import os
import sys
import time

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter


SEED = 2507
TEX_SIZE = 1024


# ==============================================================================
# Core Seamless Tileable Procedural Primitives (Periodic Float32 on X and Y)
# ==============================================================================

def _fade(t: np.ndarray) -> np.ndarray:
    return t * t * t * (t * (t * np.float32(6.0) - np.float32(15.0)) + np.float32(10.0))


def perlin_tile(size: int, fx: int, fy: int, rng: np.random.Generator) -> np.ndarray:
    """Seamless periodic 2D gradient noise in roughly [-1, 1] (float32)."""
    ang = rng.uniform(0.0, 2.0 * np.pi, (fy, fx)).astype(np.float32)
    gx = np.cos(ang)
    gy = np.sin(ang)
    xs = np.arange(size, dtype=np.float32) * (np.float32(fx) / np.float32(size))
    ys = np.arange(size, dtype=np.float32) * (np.float32(fy) / np.float32(size))
    x0 = np.floor(xs).astype(np.int32)
    y0 = np.floor(ys).astype(np.int32)
    dx = (xs - x0)[None, :]
    dy = (ys - y0)[:, None]
    x1 = (x0 + 1) % fx
    y1 = (y0 + 1) % fy
    x0m = x0 % fx
    y0m = y0 % fy

    def dot_corner(yi, xi, ox, oy):
        return gx[np.ix_(yi, xi)] * (dx - np.float32(ox)) + gy[np.ix_(yi, xi)] * (dy - np.float32(oy))

    n00 = dot_corner(y0m, x0m, 0.0, 0.0)
    n10 = dot_corner(y0m, x1, 1.0, 0.0)
    n01 = dot_corner(y1, x0m, 0.0, 1.0)
    n11 = dot_corner(y1, x1, 1.0, 1.0)
    u = _fade(dx)
    v = _fade(dy)
    nx0 = n00 * (np.float32(1.0) - u) + n10 * u
    nx1 = n01 * (np.float32(1.0) - u) + n11 * u
    return (nx0 * (np.float32(1.0) - v) + nx1 * v) * np.float32(1.4142135)


def value_tile(size: int, fx: int, fy: int, rng: np.random.Generator) -> np.ndarray:
    """Fast seamless periodic smoothstep value noise in [0, 1] for crisp high-freq grit."""
    grid = rng.random((fy, fx), dtype=np.float32)
    xs = np.arange(size, dtype=np.float32) * (np.float32(fx) / np.float32(size))
    ys = np.arange(size, dtype=np.float32) * (np.float32(fy) / np.float32(size))
    x0 = np.floor(xs).astype(np.int32)
    y0 = np.floor(ys).astype(np.int32)
    dx = (xs - x0)[None, :]
    dy = (ys - y0)[:, None]
    x1 = (x0 + 1) % fx
    y1 = (y0 + 1) % fy
    x0m = x0 % fx
    y0m = y0 % fy
    u = dx * dx * (np.float32(3.0) - np.float32(2.0) * dx)
    v = dy * dy * (np.float32(3.0) - np.float32(2.0) * dy)
    c00 = grid[np.ix_(y0m, x0m)]
    c10 = grid[np.ix_(y0m, x1)]
    c01 = grid[np.ix_(y1, x0m)]
    c11 = grid[np.ix_(y1, x1)]
    return (c00 * (1.0 - u) + c10 * u) * (1.0 - v) + (c01 * (1.0 - u) + c11 * u) * v


def fbm_tile(size: int, fx: int, fy: int, octaves: int, rng: np.random.Generator,
             gain: float = 0.5) -> np.ndarray:
    """Normalized periodic fBM in [0, 1] (float32)."""
    out = np.zeros((size, size), dtype=np.float32)
    amp = np.float32(1.0)
    tot = np.float32(0.0)
    for o in range(octaves):
        mul = 1 << o
        out += amp * perlin_tile(size, fx * mul, fy * mul, rng)
        tot += amp
        amp *= np.float32(gain)
    return np.clip(np.float32(0.5) + np.float32(0.5) * (out / max(tot, np.float32(1e-6))), 0.0, 1.0)


def ridged_tile(size: int, fx: int, fy: int, octaves: int, rng: np.random.Generator,
                gain: float = 0.52, power: float = 2.0) -> np.ndarray:
    """Normalized periodic ridged noise in [0, 1] for crisp cracks & sharp rock ridges."""
    out = np.zeros((size, size), dtype=np.float32)
    amp = np.float32(1.0)
    tot = np.float32(0.0)
    for o in range(octaves):
        mul = 1 << o
        n = np.clip(np.float32(1.0) - np.abs(perlin_tile(size, fx * mul, fy * mul, rng)), 0.0, 1.0)
        out += amp * (n ** np.float32(power))
        tot += amp
        amp *= np.float32(gain)
    return np.clip(out / max(tot, np.float32(1e-6)), 0.0, 1.0)


def micro_grit_tile(size: int, rng: np.random.Generator) -> np.ndarray:
    """Crisp multi-scale pixel-level mineral/sand grit in [0, 1] (100% periodic)."""
    g1 = value_tile(size, 64, 64, rng)
    g2 = value_tile(size, 128, 128, rng)
    g3 = value_tile(size, 256, 256, rng)
    g4 = value_tile(size, 512, 512, rng)
    return np.clip(0.28 * g1 + 0.30 * g2 + 0.26 * g3 + 0.16 * g4, 0.0, 1.0)


def worley_exact_tile(size: int, nx: int, ny: int, rng: np.random.Generator,
                      jitter: float = 0.85, warp_x: np.ndarray = None,
                      warp_y: np.ndarray = None, need_edges: bool = True):
    """Exact seamless periodic Voronoi cellular noise with uniform-width bisector edges.

    Computes nearest & second-nearest cell vectors in a single 3x3 pass and evaluates the exact
    perpendicular distance to the Voronoi bisector plane (2x faster at full 1024x1024 sharpness!).
    Returns (f1, edge_dist, cell_id, local_x, local_y) each shape (size, size) float32.
    """
    pts_x = ((np.arange(nx, dtype=np.float32)[None, :] + 0.5
              + (rng.random((ny, nx)).astype(np.float32) - 0.5) * np.float32(jitter)) / np.float32(nx))
    pts_y = ((np.arange(ny, dtype=np.float32)[:, None] + 0.5
              + (rng.random((ny, nx)).astype(np.float32) - 0.5) * np.float32(jitter)) / np.float32(ny))
    cell_val = rng.random((ny, nx)).astype(np.float32)

    u = (np.arange(size, dtype=np.float32) + 0.5) / np.float32(size)
    ux, vy = np.meshgrid(u, u)
    if warp_x is not None:
        ux = (ux + warp_x.astype(np.float32)) % np.float32(1.0)
    if warp_y is not None:
        vy = (vy + warp_y.astype(np.float32)) % np.float32(1.0)

    cx = np.floor(ux * nx).astype(np.int32) % nx
    cy = np.floor(vy * ny).astype(np.int32) % ny

    d2_1 = np.full((size, size), np.float32(1e9), dtype=np.float32)
    dx1 = np.zeros((size, size), dtype=np.float32)
    dy1 = np.zeros((size, size), dtype=np.float32)
    cid = np.zeros((size, size), dtype=np.float32)
    if need_edges:
        d2_2 = np.full((size, size), np.float32(1e9), dtype=np.float32)
        dx2 = np.zeros((size, size), dtype=np.float32)
        dy2 = np.zeros((size, size), dtype=np.float32)

    fnx = np.float32(nx)
    fny = np.float32(ny)

    for dy in (-1, 0, 1):
        ny_idx = (cy + dy) % ny
        for dx in (-1, 0, 1):
            nx_idx = (cx + dx) % nx
            ddx = pts_x[ny_idx, nx_idx] - ux
            ddx -= np.round(ddx)
            ddy = pts_y[ny_idx, nx_idx] - vy
            ddy -= np.round(ddy)
            vx = ddx * fnx
            vy_c = ddy * fny
            d2 = vx * vx + vy_c * vy_c
            b1 = d2 < d2_1
            if need_edges:
                b2 = (~b1) & (d2 < d2_2)
                d2_2 = np.where(b1, d2_1, np.where(b2, d2, d2_2))
                dx2 = np.where(b1, dx1, np.where(b2, vx, dx2))
                dy2 = np.where(b1, dy1, np.where(b2, vy_c, dy2))
            d2_1 = np.where(b1, d2, d2_1)
            dx1 = np.where(b1, vx, dx1)
            dy1 = np.where(b1, vy_c, dy1)
            cid = np.where(b1, cell_val[ny_idx, nx_idx], cid)

    f1 = np.sqrt(d2_1)
    if not need_edges:
        return f1, None, cid, -dx1, -dy1

    rx = dx2 - dx1
    ry = dy2 - dy1
    rlen = np.sqrt(rx * rx + ry * ry)
    edge_dist = np.maximum(np.float32(0.5) * (d2_2 - d2_1) / np.maximum(rlen, np.float32(1e-5)), np.float32(0.0))
    return f1, edge_dist, cid, -dx1, -dy1


def smoothstep(e0, e1, x: np.ndarray) -> np.ndarray:
    e0f = np.float32(e0)
    e1f = np.float32(e1)
    denom = e1f - e0f
    safe_denom = np.where(np.abs(denom) < np.float32(1e-7), np.float32(1e-7), denom)
    t = np.clip((x - e0f) / safe_denom, np.float32(0.0), np.float32(1.0))
    return t * t * (np.float32(3.0) - np.float32(2.0) * t)


def lerp3(a, b, t: np.ndarray) -> np.ndarray:
    a_arr = np.asarray(a, dtype=np.float32)
    b_arr = np.asarray(b, dtype=np.float32)
    if a_arr.ndim == 1:
        a_arr = a_arr[None, None, :]
    if b_arr.ndim == 1:
        b_arr = b_arr[None, None, :]
    tf = np.asarray(t, dtype=np.float32)[..., None]
    return a_arr * (np.float32(1.0) - tf) + b_arr * tf


def _scharr_grad_periodic(h: np.ndarray):
    """Periodic Scharr gradient (dh/dcol, dh/drow)."""
    hx_l = np.roll(h, 1, axis=1)
    hx_r = np.roll(h, -1, axis=1)
    dh_dcol = (
        np.float32(3.0) * (np.roll(hx_r, 1, axis=0) - np.roll(hx_l, 1, axis=0))
        + np.float32(10.0) * (hx_r - hx_l)
        + np.float32(3.0) * (np.roll(hx_r, -1, axis=0) - np.roll(hx_l, -1, axis=0))
    ) / np.float32(32.0)

    hy_u = np.roll(h, 1, axis=0)
    hy_d = np.roll(h, -1, axis=0)
    dh_drow = (
        np.float32(3.0) * (np.roll(hy_d, 1, axis=1) - np.roll(hy_u, 1, axis=1))
        + np.float32(10.0) * (hy_d - hy_u)
        + np.float32(3.0) * (np.roll(hy_d, -1, axis=1) - np.roll(hy_u, -1, axis=1))
    ) / np.float32(32.0)
    return dh_dcol, dh_drow


def height_to_normal(height: np.ndarray, strength: float = 3.5) -> np.ndarray:
    """Convert periodic height field in [0, 1] to OpenGL tangent-space normal RGB in [0, 1].

    OpenGL convention: R = +X right, G = +Y up (top of bump bright green), B = +Z out.
    """
    h = np.asarray(height, dtype=np.float32)
    dh_dcol, dh_drow = _scharr_grad_periodic(h)
    nx = -dh_dcol * np.float32(strength)
    ny = dh_drow * np.float32(strength)
    nz = np.ones_like(h)
    inv_len = np.float32(1.0) / np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([nx * inv_len * 0.5 + 0.5, ny * inv_len * 0.5 + 0.5, nz * inv_len * 0.5 + 0.5], axis=-1)
    return np.clip(rgb, 0.0, 1.0)


def multi_scale_normal(height_macro: np.ndarray, height_detail: np.ndarray,
                       strength_macro: float = 6.0, strength_detail: float = 3.0,
                       sigma_macro: float = 1.2, wide_step: int = 3,
                       wide_weight: float = 0.42) -> np.ndarray:
    """Crisp multi-octave OpenGL tangent-space normal map combining broad sculpted slopes
    with sharp unblurred 1-pixel micro-detail (zero blurry smudge normals!)."""
    hm = np.asarray(height_macro, dtype=np.float32)
    hd = np.asarray(height_detail, dtype=np.float32)
    hm_n = (hm - hm.min()) / max(hm.max() - hm.min(), np.float32(1e-6))
    hm_s = gaussian_filter(hm_n, sigma=sigma_macro, mode="wrap") if sigma_macro > 0.05 else hm_n

    gx_m, gy_m = _scharr_grad_periodic(hm_s)
    gx_w = (np.roll(hm_s, -wide_step, axis=1) - np.roll(hm_s, wide_step, axis=1)) / np.float32(2.0 * wide_step)
    gy_w = (np.roll(hm_s, -wide_step, axis=0) - np.roll(hm_s, wide_step, axis=0)) / np.float32(2.0 * wide_step)
    gx_d, gy_d = _scharr_grad_periodic(hd)

    nx = -(gx_m * np.float32(1.0 - wide_weight) + gx_w * np.float32(wide_weight)) * np.float32(strength_macro) - gx_d * np.float32(strength_detail)
    ny = (gy_m * np.float32(1.0 - wide_weight) + gy_w * np.float32(wide_weight)) * np.float32(strength_macro) + gy_d * np.float32(strength_detail)
    nz = np.ones_like(hm)
    inv_len = np.float32(1.0) / np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([nx * inv_len * 0.5 + 0.5, ny * inv_len * 0.5 + 0.5, nz * inv_len * 0.5 + 0.5], axis=-1)
    return np.clip(rgb, 0.0, 1.0)


def _calibrate_rgb(arr: np.ndarray, target_rgb: tuple, strength: float = 1.0,
                   lo: float = 0.04, hi: float = 1.0) -> np.ndarray:
    """Preserve calibrated mean RGB for vertex-color-multiplied ship textures."""
    cur = arr.mean(axis=(0, 1))
    tgt = np.asarray(target_rgb, dtype=np.float32)
    scale = 1.0 + (tgt / np.maximum(cur, np.float32(1e-4)) - 1.0) * np.float32(strength)
    return np.clip(arr * scale[None, None, :], lo, hi)


def save_rgb(path: str, arr: np.ndarray) -> None:
    arr = np.nan_to_num(arr, nan=0.5, posinf=1.0, neginf=0.0)
    u8 = np.clip(np.rint(arr * 255.0), 0, 255).astype(np.uint8)
    Image.fromarray(u8, mode="RGB").save(path, compress_level=3)


def save_gray(path: str, arr: np.ndarray) -> None:
    arr = np.nan_to_num(arr, nan=0.5, posinf=1.0, neginf=0.0)
    u8 = np.clip(np.rint(arr * 255.0), 0, 255).astype(np.uint8)
    Image.fromarray(u8, mode="L").save(path, compress_level=3)


# ==============================================================================
# High-Craft Vectorized Periodic Stampers (Stones, Shells, Grass Tufts, Clovers)
# ==============================================================================

def _blend_patch_periodic(canvas_rgb: np.ndarray, canvas_h: np.ndarray,
                          x0: int, y0: int, patch_rgb: np.ndarray,
                          patch_alpha: np.ndarray, patch_h: np.ndarray,
                          h_mode: str = "max", ao_mul: np.ndarray = None,
                          h_delta: np.ndarray = None) -> None:
    """Fast periodic patch compositor with optional contact-AO darkening & artifact-free height update."""
    size = canvas_rgb.shape[0]
    ph, pw = patch_alpha.shape
    x1 = x0 + pw
    y1 = y0 + ph
    if x0 >= 0 and y0 >= 0 and x1 <= size and y1 <= size:
        sub_c = canvas_rgb[y0:y1, x0:x1]
        if ao_mul is not None:
            sub_c *= ao_mul[..., None]
        a = patch_alpha[..., None]
        sub_c[:] = sub_c * (np.float32(1.0) - a) + patch_rgb * a
        sub_h = canvas_h[y0:y1, x0:x1]
        if h_delta is not None:
            sub_h += h_delta
        if h_mode == "max":
            target_h = np.maximum(sub_h, patch_h)
            sub_h[:] = sub_h * (np.float32(1.0) - patch_alpha) + target_h * patch_alpha
        elif h_mode == "blend":
            sub_h[:] = sub_h * (np.float32(1.0) - patch_alpha) + patch_h * patch_alpha
    else:
        ix = np.arange(x0, x1, dtype=np.int32) % size
        iy = np.arange(y0, y1, dtype=np.int32) % size
        gy, gx = np.ix_(iy, ix)
        sub_c = canvas_rgb[gy, gx]
        if ao_mul is not None:
            sub_c = sub_c * ao_mul[..., None]
        a = patch_alpha[..., None]
        canvas_rgb[gy, gx] = sub_c * (np.float32(1.0) - a) + patch_rgb * a
        sub_h = canvas_h[gy, gx]
        if h_delta is not None:
            sub_h = sub_h + h_delta
        if h_mode == "max":
            target_h = np.maximum(sub_h, patch_h)
            canvas_h[gy, gx] = sub_h * (np.float32(1.0) - patch_alpha) + target_h * patch_alpha
        elif h_mode == "blend":
            canvas_h[gy, gx] = sub_h * (np.float32(1.0) - patch_alpha) + patch_h * patch_alpha


def _stamp_stones_periodic(size: int, canvas_rgb: np.ndarray, canvas_h: np.ndarray,
                           rng: np.random.Generator, count: int,
                           rad_range: tuple, aspect_range: tuple,
                           palette: list, h_amp: float,
                           flat_top: bool = True, ao_strength: float = 0.42,
                           min_sep_factor: float = 0.0,
                           weight_map: np.ndarray = None,
                           existing_centers: list = None,
                           dust_tint: tuple = None) -> list:
    """Stamp crisp embedded worn polygonal stones / gravel pebbles with dark AO rim shadows."""
    centers = list(existing_centers) if existing_centers else []
    placed = 0
    attempts = 0
    max_attempts = count * 8

    while placed < count and attempts < max_attempts:
        attempts += 1
        cx = float(rng.uniform(0.0, size))
        cy = float(rng.uniform(0.0, size))
        if weight_map is not None:
            if rng.random() > float(weight_map[int(cy) % size, int(cx) % size]):
                continue

        rx = float(rng.uniform(rad_range[0], rad_range[1]))
        ry = rx * float(rng.uniform(aspect_range[0], aspect_range[1]))
        r_eff = max(rx, ry)

        if min_sep_factor > 0.0 and centers:
            ok = True
            for ox, oy, orad in centers:
                dx = cx - ox
                if dx > size * 0.5:
                    dx -= size
                elif dx < -size * 0.5:
                    dx += size
                dy = cy - oy
                if dy > size * 0.5:
                    dy -= size
                elif dy < -size * 0.5:
                    dy += size
                min_d = (r_eff + orad) * min_sep_factor
                if dx * dx + dy * dy < min_d * min_d:
                    ok = False
                    break
            if not ok:
                continue

        placed += 1
        if min_sep_factor > 0.0:
            centers.append((cx, cy, r_eff))

        ang = float(rng.uniform(0.0, np.pi))
        ca, sa = np.float32(np.cos(ang)), np.float32(np.sin(ang))
        h2 = np.float32(rng.uniform(0.04, 0.14))
        p2 = np.float32(rng.uniform(0.0, 2.0 * np.pi))
        h3 = np.float32(rng.uniform(0.05, 0.15))
        p3 = np.float32(rng.uniform(0.0, 2.0 * np.pi))
        h5 = np.float32(rng.uniform(0.02, 0.08))
        p5 = np.float32(rng.uniform(0.0, 2.0 * np.pi))

        pad = int(np.ceil(r_eff * 1.45 + 4.0))
        lx = np.arange(-pad, pad + 1, dtype=np.float32)
        gx, gy = np.meshgrid(lx, lx)
        u = (gx * ca + gy * sa) / np.float32(max(rx, 1.0))
        v = (-gx * sa + gy * ca) / np.float32(max(ry, 1.0))
        theta = np.arctan2(v, u)
        rad_mod = (np.float32(1.0)
                   + h2 * np.cos(np.float32(2.0) * theta + p2)
                   + h3 * np.cos(np.float32(3.0) * theta + p3)
                   + h5 * np.cos(np.float32(5.0) * theta + p5))
        dist = np.hypot(u, v) / np.maximum(rad_mod, np.float32(0.55))

        edge_soft = np.float32(min(0.14, 1.45 / max(r_eff, 2.0)))
        mask = np.float32(1.0) - smoothstep(1.0 - edge_soft, 1.0 + edge_soft * 0.4, dist)
        if mask.max() < 0.05:
            continue

        u_sh = ((gx - 1.2) * ca + (gy - 1.5) * sa) / np.float32(max(rx, 1.0))
        v_sh = (-(gx - 1.2) * sa + (gy - 1.5) * ca) / np.float32(max(ry, 1.0))
        dist_sh = np.hypot(u_sh, v_sh) / np.maximum(rad_mod, np.float32(0.55))
        ao_ring = (smoothstep(1.36, 0.96, dist) * 0.72 + smoothstep(1.26, 0.92, dist_sh) * 0.48) * (1.0 - mask * 0.85)
        ao_mul = np.clip(np.float32(1.0) - ao_ring * np.float32(ao_strength), 0.42, 1.0)

        if flat_top:
            bevel = smoothstep(1.02, 0.68, dist)
            crown = np.float32(0.74) * bevel + np.float32(0.26) * np.sqrt(np.clip(1.0 - dist * dist, 0.0, 1.0))
        else:
            crown = np.sqrt(np.clip(1.0 - dist * dist * 0.92, 0.0, 1.0))

        tilt_x = np.float32(rng.uniform(-0.18, 0.18))
        tilt_y = np.float32(rng.uniform(-0.18, 0.18))
        dir_lit = np.clip((-gx * 0.65 - gy * 0.75) / np.float32(max(r_eff, 2.0)), -1.0, 1.0)
        speck = rng.uniform(-0.065, 0.065, gx.shape).astype(np.float32)
        base_col = np.array(palette[int(rng.integers(0, len(palette)))], dtype=np.float32)
        base_col *= np.float32(rng.uniform(0.87, 1.13))

        shade = (np.float32(0.85) + np.float32(0.18) * crown
                 + np.float32(0.14) * dir_lit * (np.float32(1.0) - crown * np.float32(0.45))
                 + speck)
        rim_hi = smoothstep(0.62, 0.88, dist) * smoothstep(1.02, 0.88, dist) * np.clip(dir_lit, 0.0, 1.0)
        stone_rgb = np.clip(base_col[None, None, :] * shade[..., None] + rim_hi[..., None] * np.float32(0.11), 0.04, 0.98)

        # Optional dusty trail-earth grounding clinging to stone perimeter edges!
        if dust_tint is not None:
            dust_edge = smoothstep(0.62, 0.98, dist) * np.float32(0.32)
            stone_rgb = lerp3(stone_rgb, dust_tint, dust_edge)

        base_h = float(canvas_h[int(cy) % size, int(cx) % size])
        plane_tilt = (u * tilt_x + v * tilt_y) * np.float32(0.16)
        stone_h = np.float32(base_h) + mask * (np.float32(h_amp) * (crown + plane_tilt))
        h_delta = -ao_ring * np.float32(h_amp * 0.28)

        _blend_patch_periodic(
            canvas_rgb, canvas_h,
            int(round(cx)) - pad, int(round(cy)) - pad,
            stone_rgb, np.clip(mask * np.float32(0.96), 0.0, 1.0),
            stone_h, h_mode="max", ao_mul=ao_mul, h_delta=h_delta
        )
    return centers


def _stamp_blade_periodic(size: int, canvas_rgb: np.ndarray, canvas_h: np.ndarray,
                          cx: float, cy: float, length: float, width: float,
                          ang: float, bend: float, c0: np.ndarray, c1: np.ndarray,
                          h_base: float, h_amp: float, ao_str: float = 0.25) -> None:
    """Stamp a single crisp curved tapered grass blade or gnarled twig with subtle shadow."""
    ca, sa = np.float32(np.cos(ang)), np.float32(np.sin(ang))
    pad = int(np.ceil(length * 0.58 + abs(bend) * length * 0.4 + width + 3.0))
    lx = np.arange(-pad, pad + 1, dtype=np.float32)
    gx, gy = np.meshgrid(lx, lx)

    u = (gx * ca + gy * sa) / np.float32(max(length, 1.0))
    v = (-gx * sa + gy * ca) - np.float32(bend * length) * (u * u)
    t = np.clip(u + np.float32(0.5), 0.0, 1.0)
    # Clamp sin >= 0 to avoid float32 sin(pi) == -8.7e-8 -> NaN on fractional power!
    sin_t = np.maximum(np.sin(t * np.float32(np.pi)), np.float32(0.0))
    half_w = np.float32(width) * (np.float32(0.22) + np.float32(0.78) * (sin_t ** np.float32(0.65))) * (np.float32(1.05) - np.float32(0.55) * t)
    in_len = (u >= -0.5) & (u <= 0.5)
    dist_v = np.abs(v) / np.maximum(half_w, np.float32(0.45))
    mask = np.where(in_len, np.float32(1.0) - smoothstep(0.60, 1.04, dist_v), np.float32(0.0))
    if mask.max() < 0.05:
        return

    ao_mask = np.where(in_len, np.float32(1.0) - smoothstep(0.85, 1.65, np.abs(v - np.float32(1.3)) / np.maximum(half_w, np.float32(0.6))), np.float32(0.0))
    ao_mul = np.clip(np.float32(1.0) - ao_mask * (np.float32(1.0) - mask) * np.float32(ao_str), 0.55, 1.0)

    ridge = np.clip(np.float32(1.0) - dist_v, 0.0, 1.0)
    blade_rgb = c0[None, None, :] * (np.float32(1.0) - t[..., None]) + c1[None, None, :] * t[..., None]
    blade_rgb = np.clip(blade_rgb * (np.float32(0.88) + np.float32(0.22) * ridge[..., None]), 0.02, 1.0)
    blade_h = np.float32(h_base) + mask * (np.float32(0.25) + np.float32(0.75) * t) * (np.float32(0.7) + np.float32(0.3) * ridge) * np.float32(h_amp)

    _blend_patch_periodic(
        canvas_rgb, canvas_h,
        int(round(cx)) - pad, int(round(cy)) - pad,
        blade_rgb, np.clip(mask * np.float32(0.95), 0.0, 1.0),
        blade_h, h_mode="max", ao_mul=ao_mul
    )


def _stamp_grass_tufts_periodic(size: int, canvas_rgb: np.ndarray, canvas_h: np.ndarray,
                                rng: np.random.Generator, n_tufts: int,
                                blades_per_tuft: tuple, len_range: tuple, wid_range: tuple,
                                c_base_fn, c_tip_fn, h_base: float, h_amp: float,
                                root_ao: float = 0.34, wind_dir: float = -np.pi * 0.42) -> None:
    """Stamp authentic radiating multi-blade grass tufts with dark rooted loam shadow."""
    for _ in range(n_tufts):
        tx = float(rng.uniform(0.0, size))
        ty = float(rng.uniform(0.0, size))
        n_blades = int(rng.integers(blades_per_tuft[0], blades_per_tuft[1] + 1))

        if root_ao > 0.01:
            rr = int(rng.uniform(7.0, 13.0))
            lx = np.arange(-rr, rr + 1, dtype=np.float32)
            gx, gy = np.meshgrid(lx, lx)
            d = np.hypot(gx, gy) / np.float32(max(rr, 1))
            r_ao = np.clip(np.float32(1.0) - (np.float32(1.0) - smoothstep(0.0, 1.0, d)) * np.float32(root_ao), 0.58, 1.0)
            x0, y0 = int(round(tx)) - rr, int(round(ty)) - rr
            x1, y1 = x0 + 2 * rr + 1, y0 + 2 * rr + 1
            if x0 >= 0 and y0 >= 0 and x1 <= size and y1 <= size:
                canvas_rgb[y0:y1, x0:x1] *= r_ao[..., None]
            else:
                ix = np.arange(x0, x1, dtype=np.int32) % size
                iy = np.arange(y0, y1, dtype=np.int32) % size
                gy_i, gx_i = np.ix_(iy, ix)
                canvas_rgb[gy_i, gx_i] *= r_ao[..., None]

        tuft_bias = wind_dir + float(rng.uniform(-0.85, 0.85))
        for b in range(n_blades):
            fan = (b / max(n_blades - 1, 1) - 0.5) * float(rng.uniform(1.6, 2.8))
            ang = tuft_bias + fan + float(rng.uniform(-0.26, 0.26))
            length = float(rng.uniform(len_range[0], len_range[1]))
            width = float(rng.uniform(wid_range[0], wid_range[1]))
            bend = float(rng.uniform(-0.36, 0.36))
            cx = (tx + np.cos(ang) * length * 0.35 + rng.uniform(-2.5, 2.5)) % size
            cy = (ty + np.sin(ang) * length * 0.35 + rng.uniform(-2.5, 2.5)) % size
            _stamp_blade_periodic(
                size, canvas_rgb, canvas_h,
                cx, cy, length, width, ang, bend,
                c_base_fn(rng), c_tip_fn(rng),
                h_base, h_amp, ao_str=0.22
            )


def _stamp_clovers_periodic(size: int, canvas_rgb: np.ndarray, canvas_h: np.ndarray,
                            rng: np.random.Generator, count: int) -> None:
    """Stamp crisp 3-leaf tropical clover clusters with subtle pale V-markings & drop shadow."""
    for _ in range(count):
        cx = float(rng.uniform(0.0, size))
        cy = float(rng.uniform(0.0, size))
        scale = float(rng.uniform(6.5, 11.5))
        rot0 = float(rng.uniform(0.0, 2.0 * np.pi))
        k = float(rng.uniform(0.88, 1.14))
        col_leaf = np.array([0.20 * k, 0.46 * k, 0.13 * k], dtype=np.float32)
        col_mark = np.array([0.42 * k, 0.65 * k, 0.22 * k], dtype=np.float32)

        pad = int(np.ceil(scale * 1.9 + 3.0))
        lx = np.arange(-pad, pad + 1, dtype=np.float32)
        gx, gy = np.meshgrid(lx, lx)
        mask = np.zeros_like(gx)
        mark = np.zeros_like(gx)
        dome = np.zeros_like(gx)

        for k_leaf in range(3):
            a = rot0 + k_leaf * (2.0 * np.pi / 3.0) + float(rng.uniform(-0.14, 0.14))
            ca, sa = np.float32(np.cos(a)), np.float32(np.sin(a))
            ox = gx - ca * np.float32(scale * 0.68)
            oy = gy - sa * np.float32(scale * 0.68)
            u = (ox * ca + oy * sa) / np.float32(scale * 0.66)
            v = (-ox * sa + oy * ca) / np.float32(scale * 0.56)
            notch = np.float32(0.18) * np.exp(-v * v * np.float32(6.0)) * np.clip(u, 0.0, 1.0)
            d = np.hypot(u + notch, v)
            lm = np.float32(1.0) - smoothstep(0.76, 1.02, d)
            mask = np.maximum(mask, lm)
            dome = np.maximum(dome, lm * np.sqrt(np.clip(1.0 - d * d * 0.8, 0.0, 1.0)))
            chevron = lm * smoothstep(0.16, 0.03, np.abs(d - np.float32(0.55))) * smoothstep(-0.2, 0.3, u)
            mark = np.maximum(mark, chevron)

        if mask.max() < 0.05:
            continue
        sh_mask = np.roll(np.roll(mask, 2, axis=0), 2, axis=1)
        ao_mul = np.clip(np.float32(1.0) - sh_mask * (np.float32(1.0) - mask) * np.float32(0.36), 0.55, 1.0)
        rgb = lerp3(col_leaf, col_mark, mark * np.float32(0.65))
        rgb = np.clip(rgb * (np.float32(0.86) + np.float32(0.24) * dome)[..., None], 0.02, 1.0)
        h_val = np.float32(0.78) + dome * np.float32(0.24)

        _blend_patch_periodic(
            canvas_rgb, canvas_h,
            int(round(cx)) - pad, int(round(cy)) - pad,
            rgb, np.clip(mask * np.float32(0.95), 0.0, 1.0),
            h_val, h_mode="max", ao_mul=ao_mul
        )


def _stamp_shells_periodic(size: int, canvas_rgb: np.ndarray, canvas_h: np.ndarray,
                           rng: np.random.Generator, count: int,
                           weight_map: np.ndarray) -> None:
    """Stamp hundreds of crisp tiny bleached coral chips & scalloped shell fragments in sand troughs."""
    palette = [
        (0.96, 0.93, 0.85),  # bleached coral ivory
        (0.92, 0.85, 0.72),  # sun-worn cream shell
        (0.90, 0.74, 0.66),  # tropical pink conch shard
        (0.85, 0.77, 0.64),  # warm calcified shell
        (0.95, 0.88, 0.77),  # pearlescent white-gold
    ]
    placed = 0
    attempts = 0
    while placed < count and attempts < count * 8:
        attempts += 1
        cx = float(rng.uniform(0.0, size))
        cy = float(rng.uniform(0.0, size))
        if rng.random() > float(weight_map[int(cy) % size, int(cx) % size]):
            continue
        placed += 1

        rx = float(rng.uniform(2.2, 6.2))
        ry = rx * float(rng.uniform(0.45, 0.88))
        ang = float(rng.uniform(0.0, 2.0 * np.pi))
        ca, sa = np.float32(np.cos(ang)), np.float32(np.sin(ang))
        pad = int(np.ceil(rx * 1.4 + 2.5))
        lx = np.arange(-pad, pad + 1, dtype=np.float32)
        gx, gy = np.meshgrid(lx, lx)
        u = (gx * ca + gy * sa) / np.float32(max(rx, 1.0))
        v = (-gx * sa + gy * ca) / np.float32(max(ry, 1.0))
        theta = np.arctan2(v, u)
        jagged = np.float32(1.0) + np.float32(0.18) * np.cos(np.float32(3.0) * theta + np.float32(rng.uniform(0, 6.28)))
        d = np.hypot(u, v) / jagged
        mask = np.float32(1.0) - smoothstep(0.68, 1.04, d)
        if mask.max() < 0.08:
            continue
        flute = np.float32(0.5) + np.float32(0.5) * np.sin(theta * np.float32(7.0))
        sh_mask = np.roll(np.roll(mask, 1, axis=0), 1, axis=1)
        ao_mul = np.clip(np.float32(1.0) - sh_mask * (np.float32(1.0) - mask) * np.float32(0.28), 0.65, 1.0)

        col = np.array(palette[int(rng.integers(0, len(palette)))], dtype=np.float32) * np.float32(rng.uniform(0.90, 1.06))
        lit = np.float32(0.88) + np.float32(0.16) * flute * mask
        rgb = np.clip(col[None, None, :] * lit[..., None], 0.0, 1.0)
        base_h = float(canvas_h[int(cy) % size, int(cx) % size])
        h_val = np.float32(base_h) + mask * np.float32(0.065 + 0.025 * flute)

        _blend_patch_periodic(
            canvas_rgb, canvas_h,
            int(round(cx)) - pad, int(round(cy)) - pad,
            rgb, np.clip(mask * np.float32(0.92), 0.0, 1.0),
            h_val, h_mode="max", ao_mul=ao_mul
        )


# ==============================================================================
# 1-5. Terrain Seamless Hand-Crafted 1024x1024 PBR Pairs
# ==============================================================================

def gen_terrain_cliff(out_dir: str, rng: np.random.Generator) -> None:
    """Chiseled Coastal Limestone / Sandstone Strata: stepped horizontal sedimentary rock
    shelves interlocked with sculpted angular warped Voronoi cliff blocks, natural broken dark
    bedding joints & tapering fracture crevices (NEVER a cartoon spiderweb!), sunlit chiseled
    upper bevels, gritty sandstone laminations, and coastal sea-lichen speckles."""
    N = TEX_SIZE
    u = np.arange(N, dtype=np.float32) / np.float32(N)
    ux, vy = np.meshgrid(u, u)

    macro = fbm_tile(N, 3, 3, 4, rng)
    mid = fbm_tile(N, 8, 8, 4, rng)
    grit = micro_grit_tile(N, rng)

    # 1. Stepped horizontal sedimentary strata shelves (exact mod-8 periodicity -> ZERO TB seam!)
    strata_warp = (fbm_tile(N, 3, 4, 3, rng) - np.float32(0.5)) * np.float32(1.15) + (mid - np.float32(0.5)) * np.float32(0.24)
    bed_phase = vy * np.float32(8.0) + np.float32(0.5) + strata_warp
    bed_id = np.floor(bed_phase).astype(np.int32) & 7  # exact period 8 matches vy * 8.0!
    bed_f = bed_phase - np.floor(bed_phase)  # 0 (top of shelf, +Y up in shader) .. 1 (bottom undercut)

    bed_table = rng.uniform(0.32, 1.0, 8).astype(np.float32)
    bed_warm_tbl = rng.uniform(0.0, 1.0, 8).astype(np.float32)
    bed_hard = bed_table[bed_id]
    bed_warm = bed_warm_tbl[bed_id]

    # Sharp horizontal bedding joints (stronger where protruding hard shelf overhangs recessed bed)
    joint_gate = np.float32(0.42) + np.float32(0.58) * fbm_tile(N, 6, 8, 3, rng)
    bed_undercut = np.maximum(
        np.float32(1.0) - smoothstep(0.008, 0.052, bed_f),
        smoothstep(0.93, 0.992, bed_f),
    ) * joint_gate
    # Broad underside shadow cast beneath each protruding shelf ledge
    shelf_cast = smoothstep(0.76, 0.97, bed_f) * (np.float32(0.35) + np.float32(0.65) * bed_hard)
    # Bright sunlit upper bevel lip along the top edge of each sedimentary shelf
    shelf_lip = smoothstep(0.025, 0.09, bed_f) * smoothstep(0.26, 0.09, bed_f)

    # Fine crisp horizontal sedimentary sandstone bedding laminations
    lam_broad = fbm_tile(N, 4, 32, 3, rng)
    lam_fine = value_tile(N, 12, 128, rng) * np.float32(0.55) + value_tile(N, 24, 256, rng) * np.float32(0.45)
    lamination = np.float32(0.55) * lam_broad + np.float32(0.45) * lam_fine

    # 2. Interlocked angular warped Voronoi cliff rock blocks (sculpted planes, NOT thick wireframes!)
    bed_jog_x = (bed_table[(bed_id + 3) & 7] - np.float32(0.5)) * np.float32(0.048)
    wx1 = (fbm_tile(N, 5, 5, 3, rng) - np.float32(0.5)) * np.float32(0.085) + bed_jog_x
    wy1 = (fbm_tile(N, 5, 5, 3, rng) - np.float32(0.5)) * np.float32(0.050)
    _, ed_a, cid_a, lx_a, ly_a = worley_exact_tile(N, 6, 5, rng, jitter=0.78, warp_x=wx1, warp_y=wy1)

    wx2 = (fbm_tile(N, 9, 9, 3, rng) - np.float32(0.5)) * np.float32(0.045)
    wy2 = (fbm_tile(N, 9, 9, 3, rng) - np.float32(0.5)) * np.float32(0.035)
    _, ed_b, cid_b, lx_b, ly_b = worley_exact_tile(N, 12, 9, rng, jitter=0.82, warp_x=wx2, warp_y=wy2)

    # Strong chiseled planar rock facets: each block tilts toward/away from upper-left sun!
    ang_a = cid_a * np.float32(6.283185)
    facet_a = np.clip(np.float32(0.5) + (lx_a * np.cos(ang_a) + ly_a * np.sin(ang_a)) * np.float32(0.62), 0.0, 1.0)
    ang_b = cid_b * np.float32(6.283185)
    facet_b = np.clip(np.float32(0.5) + (lx_b * np.cos(ang_b) + ly_b * np.sin(ang_b)) * np.float32(0.52), 0.0, 1.0)
    # Sculpted planar sun-catch factor: crisp tonal step between adjacent chiseled cliff faces!
    plane_lit = np.clip(np.float32(0.52) * facet_a + np.float32(0.28) * cid_a + np.float32(0.20) * facet_b, 0.0, 1.0)

    # Organic BROKEN tapering fracture crevices (modulated by crack_open so lines pinch & break naturally!)
    crack_open_a = smoothstep(0.22, 0.72, fbm_tile(N, 7, 7, 3, rng))
    crack_open_b = smoothstep(0.45, 0.85, fbm_tile(N, 10, 10, 2, rng)) * smoothstep(0.32, 0.72, cid_a)
    crack_w_a = np.float32(0.012) + np.float32(0.022) * crack_open_a
    crack_a = (np.float32(1.0) - smoothstep(0.004, crack_w_a, ed_a)) * (np.float32(0.25) + np.float32(0.75) * crack_open_a)
    crack_b = (np.float32(1.0) - smoothstep(0.003, 0.020, ed_b)) * crack_open_b * np.float32(0.72)

    # Sharp vertical geological stress splits (naturally broken, non-polygonal)
    v_fissure = smoothstep(0.84, 0.96, ridged_tile(N, 11, 5, 3, rng, power=2.8)) * smoothstep(0.38, 0.78, mid) * np.float32(0.78)
    crevice = np.clip(np.maximum(np.maximum(bed_undercut, crack_a), np.maximum(crack_b, v_fissure)), 0.0, 1.0)

    # Crisp sunlit chiseled bevel catchlights along upper/left block edges & shelf lips
    ed_up = np.roll(ed_a, 3, axis=0)
    ed_left = np.roll(ed_a, 3, axis=1)
    chisel_hi = np.clip((ed_a - ed_up) * np.float32(3.8) + (ed_a - ed_left) * np.float32(2.6), 0.0, 1.0) * smoothstep(0.012, 0.08, ed_a) * smoothstep(0.22, 0.08, ed_a)

    # 3. Sunlit Coastal Limestone & Warm Sandstone Ochre Palette (calibrated lum ~0.58!)
    col = lerp3((0.53, 0.44, 0.34), (0.87, 0.79, 0.65), smoothstep(0.14, 0.86, plane_lit * np.float32(0.62) + bed_hard * np.float32(0.38)))
    # Warm golden-ochre & terracotta sedimentary bands
    ochre_w = smoothstep(0.28, 0.78, bed_warm * np.float32(0.68) + fbm_tile(N, 2, 8, 3, rng) * np.float32(0.32))
    col = lerp3(col, (0.77, 0.54, 0.32), ochre_w * np.float32(0.46))
    # Cool weathered slate-taupe rock shadow planes & mineral rainwater wash
    rain_wash = fbm_tile(N, 12, 2, 3, rng)
    slate_w = smoothstep(0.54, 0.88, (np.float32(1.0) - facet_a) * np.float32(0.58) + (np.float32(1.0) - rain_wash) * np.float32(0.42))
    col = lerp3(col, (0.48, 0.46, 0.43), slate_w * np.float32(0.34))

    # Rich gritty sedimentary striations & stony micro-grain (zero plastic smoothness!)
    col *= (np.float32(0.83) + np.float32(0.18) * lamination + np.float32(0.16) * grit)[..., None]

    # Shelf underside shadow + bright chiseled sunlit upper shelf lips & block edge catchlights
    col = lerp3(col, (0.34, 0.28, 0.23), shelf_cast * np.float32(0.34))
    lip_hi = np.clip(shelf_lip * (np.float32(0.62) + np.float32(0.38) * bed_hard) + chisel_hi * np.float32(0.75), 0.0, 1.0)
    col = lerp3(col, (0.96, 0.90, 0.77), lip_hi * np.float32(0.46))

    # Subtle coastal sea-lichen speckles nestled on sunlit upper shelf ledges
    lichen_zone = smoothstep(0.02, 0.13, bed_f) * smoothstep(0.34, 0.14, bed_f) * smoothstep(0.54, 0.80, fbm_tile(N, 10, 10, 3, rng))
    lichen_sage = smoothstep(0.64, 0.82, value_tile(N, 112, 112, rng)) * lichen_zone
    col = lerp3(col, (0.49, 0.56, 0.33), lichen_sage * np.float32(0.54))
    lichen_gold = smoothstep(0.76, 0.90, value_tile(N, 144, 144, rng)) * lichen_zone
    col = lerp3(col, (0.80, 0.73, 0.36), lichen_gold * np.float32(0.44))

    # Crisp dark fracture crevices & bedding joints
    col = lerp3(col, (0.19, 0.15, 0.13), np.clip(crevice * np.float32(0.82), 0.0, 0.86))

    # 4. Multi-scale rock heightfield -> razor-sharp sculpted cliff tangent normal map!
    block_bevel = smoothstep(0.014, 0.12, ed_a)
    height_macro = (
        np.float32(0.34) * bed_hard * (np.float32(1.0) - np.float32(0.34) * bed_f)
        + np.float32(0.28) * block_bevel * (np.float32(0.40) + np.float32(0.60) * cid_a)
        + np.float32(0.22) * facet_a
        + np.float32(0.12) * facet_b * crack_open_b
        + np.float32(0.10) * shelf_lip
        - np.float32(0.42) * crevice
    )
    height_detail = (
        np.float32(0.38) * lamination
        + np.float32(0.42) * grit
        - np.float32(0.52) * crevice
    )

    nrm = multi_scale_normal(height_macro, height_detail, strength_macro=11.0, strength_detail=3.8, sigma_macro=0.80, wide_step=3, wide_weight=0.40)
    save_rgb(os.path.join(out_dir, "terrain_cliff_albedo.png"), np.clip(col, 0.0, 1.0))
    save_rgb(os.path.join(out_dir, "terrain_cliff_normal.png"), nrm)


def gen_terrain_sand(out_dir: str, rng: np.random.Generator) -> None:
    """Tactile Wind-Rippled Tropical Beach Sand: organically meandering & bifurcating asymmetric
    wind ripples, crisp sparkling quartz/coral sand-grain micro-noise across the entire surface,
    plus hundreds of bleached coral chips, blush/ivory shell fragments & smooth trough pebbles."""
    N = TEX_SIZE
    u = np.arange(N, dtype=np.float32) / np.float32(N)
    ux, vy = np.meshgrid(u, u)

    macro = fbm_tile(N, 3, 3, 4, rng)
    mid = fbm_tile(N, 7, 7, 3, rng)
    grain_mid = fbm_tile(N, 48, 48, 3, rng)
    grit = micro_grit_tile(N, rng)
    sparkle = value_tile(N, 384, 384, rng)
    sparkle2 = value_tile(N, 512, 512, rng)

    # Organically meandering & Y-bifurcating wind ripples (integer wave vectors -> 100% periodic!)
    warp_a = (macro - np.float32(0.5)) * np.float32(5.6) + (mid - np.float32(0.5)) * np.float32(1.75)
    warp_b = (fbm_tile(N, 3, 3, 3, rng) - np.float32(0.5)) * np.float32(5.0) + (mid - np.float32(0.5)) * np.float32(1.5)
    phase_a = np.float32(2.0 * np.pi) * (np.float32(5.0) * ux + np.float32(10.0) * vy) + warp_a
    phase_b = np.float32(2.0 * np.pi) * (np.float32(6.0) * ux + np.float32(12.0) * vy) + warp_b

    def _asymmetric_ripple(ph: np.ndarray) -> np.ndarray:
        s1 = np.sin(ph)
        ph_skew = ph + np.float32(0.50) * s1 + np.float32(0.16) * np.sin(np.float32(2.0) * ph)
        w = np.float32(0.5) + np.float32(0.5) * np.sin(ph_skew)
        return np.power(np.clip(w, 0.0, 1.0), np.float32(0.82))

    rip_a = _asymmetric_ripple(phase_a)
    rip_b = _asymmetric_ripple(phase_b)
    bifurc_w = smoothstep(0.22, 0.78, fbm_tile(N, 2, 2, 3, rng))
    ripple = rip_a * (np.float32(1.0) - bifurc_w) + rip_b * bifurc_w

    rip_grad = (np.roll(ripple, -2, axis=0) - np.roll(ripple, 2, axis=0)) + (np.roll(ripple, -2, axis=1) - np.roll(ripple, 2, axis=1)) * np.float32(0.45)
    lee_shade = smoothstep(0.015, 0.22, -rip_grad)
    crest_hi = smoothstep(0.78, 0.98, ripple)

    amp_mod = np.float32(0.60) + np.float32(0.40) * fbm_tile(N, 3, 3, 3, rng)
    sand_h = np.float32(0.50) + (ripple - np.float32(0.5)) * amp_mod * np.float32(0.66) + (macro - np.float32(0.5)) * np.float32(0.14)

    # Warm tropical golden-ivory crests to honey-amber lee troughs
    col = lerp3((0.71, 0.56, 0.35), (0.95, 0.86, 0.63), smoothstep(0.12, 0.88, sand_h))
    col = lerp3(col, (0.64, 0.49, 0.30), lee_shade * amp_mod * np.float32(0.40))
    col = lerp3(col, (0.98, 0.92, 0.72), crest_hi * amp_mod * np.float32(0.26))

    # Crisp sparkling fine sand grain across the entire surface!
    grain_contrast = (grit - np.float32(0.5)) * np.float32(0.20) + (grain_mid - np.float32(0.5)) * np.float32(0.08)
    col = np.clip(col * (np.float32(1.0) + grain_contrast)[..., None], 0.0, 1.0)
    coral_fleck = smoothstep(0.76, 0.94, value_tile(N, 224, 224, rng))
    col = lerp3(col, (0.87, 0.67, 0.54), coral_fleck * np.float32(0.28))
    quartz = (smoothstep(0.86, 0.99, sparkle) * np.float32(0.095) + smoothstep(0.88, 0.995, sparkle2) * np.float32(0.085)) * (np.float32(0.45) + np.float32(0.55) * ripple)
    col = np.clip(col + quartz[..., None], 0.0, 1.0)

    # Concentrate bleached coral chips, shell shards & wave-tumbled pebbles inside ripple troughs
    trough_w = np.clip(np.float32(0.06) + np.float32(0.94) * smoothstep(0.54, 0.12, ripple), 0.0, 1.0)
    _stamp_shells_periodic(N, col, sand_h, rng, count=640, weight_map=trough_w)

    pebble_pal = [
        (0.79, 0.69, 0.52),  # sun-bleached coral limestone
        (0.68, 0.56, 0.42),  # warm sea-worn sandstone
        (0.75, 0.60, 0.47),  # rose-terracotta shell stone
        (0.65, 0.60, 0.53),  # warm weathered coastal pebble
        (0.84, 0.76, 0.60),  # pale golden quartz pebble
    ]
    _stamp_stones_periodic(
        N, col, sand_h, rng, count=195,
        rad_range=(2.8, 7.8), aspect_range=(0.56, 0.92),
        palette=pebble_pal, h_amp=0.10, flat_top=False,
        ao_strength=0.30, min_sep_factor=0.65, weight_map=trough_w,
        dust_tint=(0.82, 0.70, 0.48)
    )

    height_detail = (grit - np.float32(0.5)) * np.float32(0.22) + (grain_mid - np.float32(0.5)) * np.float32(0.08) + (sand_h - gaussian_filter(sand_h, sigma=1.6, mode="wrap")) * np.float32(1.4)
    nrm = multi_scale_normal(sand_h, height_detail, strength_macro=11.0, strength_detail=4.0, sigma_macro=0.90, wide_step=3, wide_weight=0.45)
    save_rgb(os.path.join(out_dir, "terrain_sand_albedo.png"), np.clip(col, 0.0, 1.0))
    save_rgb(os.path.join(out_dir, "terrain_sand_normal.png"), nrm)


def gen_terrain_grass(out_dir: str, rng: np.random.Generator) -> None:
    """Lush Multi-Layered Tropical Island Turf: rich mottled dark-emerald & warm forest-loam
    soil base, dense overlapping radiating grass tufts with rooted shadows & sunlit chartreuse
    tips, 3-leaf tropical clover clusters, dry golden stalks, tiny petals & mossy pebbles."""
    N = TEX_SIZE
    macro = fbm_tile(N, 3, 3, 4, rng)
    mid = fbm_tile(N, 9, 9, 4, rng)
    grit = micro_grit_tile(N, rng)
    w1, _, _, _, _ = worley_exact_tile(N, 14, 14, rng, jitter=0.88, need_edges=False)

    # Rich mottled forest-loam & vibrant sunlit emerald underpainting (zero flat green!)
    col = lerp3((0.15, 0.31, 0.08), (0.35, 0.56, 0.15), smoothstep(0.16, 0.84, macro * np.float32(0.55) + mid * np.float32(0.45)))
    loam_mask = smoothstep(0.54, 0.88, w1) * smoothstep(0.36, 0.80, fbm_tile(N, 6, 6, 3, rng))
    col = lerp3(col, (0.24, 0.19, 0.10), loam_mask * np.float32(0.50))
    warm_patch = smoothstep(0.54, 0.86, fbm_tile(N, 4, 4, 3, rng))
    col = lerp3(col, (0.48, 0.58, 0.18), warm_patch * np.float32(0.38))
    col *= (np.float32(0.90) + np.float32(0.20) * grit)[..., None]

    height = np.float32(0.18) * macro + np.float32(0.12) * mid + np.float32(0.08) * grit + np.float32(0.08) * (np.float32(1.0) - np.clip(w1, 0.0, 1.0))

    # Mossy pebbles nestled in the loam beneath grass tufts
    moss_stone_pal = [
        (0.38, 0.42, 0.28),
        (0.46, 0.47, 0.35),
        (0.43, 0.40, 0.31),
    ]
    _stamp_stones_periodic(
        N, col, height, rng, count=48,
        rad_range=(5.0, 11.0), aspect_range=(0.6, 0.9),
        palette=moss_stone_pal, h_amp=0.18, flat_top=False,
        ao_strength=0.42, min_sep_factor=1.2
    )

    # Layer 1: Dense dark-emerald rooted under-tufts (~280 tufts -> fuller ground coverage!)
    _stamp_grass_tufts_periodic(
        N, col, height, rng, n_tufts=280, blades_per_tuft=(5, 7),
        len_range=(26.0, 54.0), wid_range=(3.6, 6.2),
        c_base_fn=lambda r: np.array([0.11 + r.uniform(-0.02, 0.02), 0.26 + r.uniform(-0.03, 0.03), 0.07 + r.uniform(-0.01, 0.02)], dtype=np.float32),
        c_tip_fn=lambda r: np.array([0.27 + r.uniform(-0.03, 0.04), 0.51 + r.uniform(-0.04, 0.05), 0.13 + r.uniform(-0.02, 0.02)], dtype=np.float32),
        h_base=0.22, h_amp=0.42, root_ao=0.28
    )

    # Layer 2: Lush vibrant mid-canopy emerald tufts (~310 tufts -> crisp overlapping curved blades!)
    _stamp_grass_tufts_periodic(
        N, col, height, rng, n_tufts=310, blades_per_tuft=(5, 7),
        len_range=(24.0, 50.0), wid_range=(2.8, 5.0),
        c_base_fn=lambda r: np.array([0.18 + r.uniform(-0.02, 0.03), 0.39 + r.uniform(-0.03, 0.04), 0.10 + r.uniform(-0.02, 0.02)], dtype=np.float32),
        c_tip_fn=lambda r: np.array([0.42 + r.uniform(-0.05, 0.07), 0.68 + r.uniform(-0.05, 0.06), 0.18 + r.uniform(-0.03, 0.03)], dtype=np.float32),
        h_base=0.38, h_amp=0.52, root_ao=0.20
    )

    # Layer 3: Sunlit golden-chartreuse upper tuft tips (~195 tufts -> sunlit highlights!)
    _stamp_grass_tufts_periodic(
        N, col, height, rng, n_tufts=195, blades_per_tuft=(4, 6),
        len_range=(18.0, 44.0), wid_range=(2.2, 4.0),
        c_base_fn=lambda r: np.array([0.28 + r.uniform(-0.03, 0.04), 0.54 + r.uniform(-0.04, 0.04), 0.14 + r.uniform(-0.02, 0.02)], dtype=np.float32),
        c_tip_fn=lambda r: np.array([0.60 + r.uniform(-0.05, 0.08), 0.79 + r.uniform(-0.05, 0.06), 0.23 + r.uniform(-0.03, 0.04)], dtype=np.float32),
        h_base=0.54, h_amp=0.46, root_ao=0.08
    )

    # Layer 4: Crisp dry golden tropical grass stalks
    for _ in range(160):
        cx = float(rng.uniform(0.0, N))
        cy = float(rng.uniform(0.0, N))
        _stamp_blade_periodic(
            N, col, height, cx, cy,
            length=float(rng.uniform(20.0, 44.0)),
            width=float(rng.uniform(1.8, 3.0)),
            ang=float(rng.uniform(-np.pi, np.pi)),
            bend=float(rng.uniform(-0.38, 0.38)),
            c0=np.array([0.44, 0.39, 0.17], dtype=np.float32),
            c1=np.array([0.74, 0.66, 0.28], dtype=np.float32),
            h_base=0.60, h_amp=0.38, ao_str=0.18
        )

    # Layer 5: Crisp 3-leaf tropical clover clusters
    _stamp_clovers_periodic(N, col, height, rng, count=140)

    # Layer 6: Subtle tiny fallen tropical wildflower petals
    petal_pal = [
        (0.92, 0.89, 0.68),  # warm cream blossom
        (0.92, 0.76, 0.24),  # golden buttercup
        (0.86, 0.46, 0.34),  # tropical hibiscus petal
    ]
    for _ in range(85):
        px = float(rng.uniform(0.0, N))
        py = float(rng.uniform(0.0, N))
        col_p = np.array(petal_pal[int(rng.integers(0, len(petal_pal)))], dtype=np.float32) * np.float32(rng.uniform(0.9, 1.06))
        _stamp_blade_periodic(
            N, col, height, px, py,
            length=float(rng.uniform(5.0, 9.5)),
            width=float(rng.uniform(2.5, 4.5)),
            ang=float(rng.uniform(-np.pi, np.pi)),
            bend=float(rng.uniform(-0.15, 0.15)),
            c0=col_p * np.float32(0.82), c1=col_p,
            h_base=0.82, h_amp=0.20, ao_str=0.26
        )

    height_detail = height - gaussian_filter(height, sigma=2.2, mode="wrap") + (grit - np.float32(0.5)) * np.float32(0.06)
    nrm = multi_scale_normal(height, height_detail, strength_macro=6.2, strength_detail=4.8, sigma_macro=0.65, wide_step=2, wide_weight=0.35)
    save_rgb(os.path.join(out_dir, "terrain_grass_albedo.png"), np.clip(col, 0.0, 1.0))
    save_rgb(os.path.join(out_dir, "terrain_grass_normal.png"), nrm)


def gen_terrain_dirt(out_dir: str, rng: np.random.Generator) -> None:
    """Crisp Packed-Earth Footpath & Trail Ground: compacted warm-ochre & sun-baked umber earth,
    embedded flat worn river stepping stones & coastal gravel pebbles with crisp AO rim shadows,
    fine dried-earth micro-cracks, granular soil grit, and scattered gnarled rootlets/twigs."""
    N = TEX_SIZE
    macro = fbm_tile(N, 3, 3, 4, rng)
    mid = fbm_tile(N, 8, 8, 4, rng)
    fine = fbm_tile(N, 26, 26, 3, rng)
    grit = micro_grit_tile(N, rng)

    # 1. Compacted warm-ochre & sun-baked umber trail earth base
    soil_mix = smoothstep(0.16, 0.86, macro * np.float32(0.54) + mid * np.float32(0.32) + fine * np.float32(0.14))
    col = lerp3((0.38, 0.26, 0.15), (0.67, 0.51, 0.33), soil_mix)
    dusty = smoothstep(0.50, 0.84, fbm_tile(N, 4, 4, 3, rng) * np.float32(0.65) + mid * np.float32(0.35))
    col = lerp3(col, (0.76, 0.61, 0.41), dusty * np.float32(0.38))
    damp = smoothstep(0.62, 0.90, np.float32(1.0) - macro * np.float32(0.6) - mid * np.float32(0.4))
    col = lerp3(col, (0.28, 0.19, 0.11), damp * np.float32(0.34))

    # Crisp fine packed-earth granular micro-grit (never airbrushed smooth!)
    col *= (np.float32(0.80) + np.float32(0.18) * fine + np.float32(0.24) * grit)[..., None]

    height = np.float32(0.42) + np.float32(0.14) * (macro - np.float32(0.5)) + np.float32(0.10) * (mid - np.float32(0.5)) + np.float32(0.06) * (fine - np.float32(0.5)) + np.float32(0.06) * (grit - np.float32(0.5))

    # 2. Localized fine dried-earth micro-cracks in dry sun-baked clay patches
    dry_zone = smoothstep(0.42, 0.78, fbm_tile(N, 3, 3, 2, rng))
    wx = (fbm_tile(N, 8, 8, 2, rng) - np.float32(0.5)) * np.float32(0.055)
    wy = (fbm_tile(N, 8, 8, 2, rng) - np.float32(0.5)) * np.float32(0.055)
    _, ed_c, cid_c, _, _ = worley_exact_tile(N, 12, 12, rng, jitter=0.86, warp_x=wx, warp_y=wy)
    _, ed_c2, _, _, _ = worley_exact_tile(N, 24, 24, rng, jitter=0.88, warp_x=wx * np.float32(0.6), warp_y=wy * np.float32(0.6))
    crack_a = (np.float32(1.0) - smoothstep(0.010, 0.042, ed_c)) * dry_zone
    crack_b = (np.float32(1.0) - smoothstep(0.008, 0.036, ed_c2)) * dry_zone * smoothstep(0.48, 0.80, cid_c) * np.float32(0.60)
    crack = np.clip(np.maximum(crack_a, crack_b), 0.0, 1.0)
    crack_lip = smoothstep(0.032, 0.085, ed_c) * smoothstep(0.16, 0.085, ed_c) * dry_zone
    col = lerp3(col, (0.78, 0.64, 0.45), crack_lip * np.float32(0.24))
    col = lerp3(col, (0.17, 0.11, 0.07), crack * np.float32(0.74))
    height += crack_lip * np.float32(0.03) - crack * np.float32(0.16)

    # 3. Embedded flat worn river stepping stones (non-overlapping, crisp AO soil rings & dusty rims!)
    step_stone_pal = [
        (0.64, 0.57, 0.47),  # warm worn coastal limestone
        (0.55, 0.51, 0.46),  # river slate grey
        (0.68, 0.53, 0.39),  # warm buff sandstone
        (0.60, 0.46, 0.35),  # weathered terracotta cobble
        (0.70, 0.63, 0.51),  # pale sunlit flagstone
    ]
    stone_centers = _stamp_stones_periodic(
        N, col, height, rng, count=44,
        rad_range=(20.0, 36.0), aspect_range=(0.58, 0.88),
        palette=step_stone_pal, h_amp=0.28, flat_top=True,
        ao_strength=0.50, min_sep_factor=1.20,
        dust_tint=(0.52, 0.39, 0.25)
    )

    # 4. Embedded coastal gravel pebbles
    gravel_pal = [
        (0.63, 0.55, 0.44),
        (0.51, 0.47, 0.41),
        (0.67, 0.51, 0.37),
        (0.72, 0.63, 0.49),
        (0.46, 0.38, 0.29),
    ]
    _stamp_stones_periodic(
        N, col, height, rng, count=280,
        rad_range=(5.8, 14.0), aspect_range=(0.55, 0.90),
        palette=gravel_pal, h_amp=0.20, flat_top=False,
        ao_strength=0.44, min_sep_factor=0.82, existing_centers=stone_centers,
        dust_tint=(0.50, 0.37, 0.23)
    )

    # 5. Crisp fine trail grit pebbles embedded across the compacted soil
    _stamp_stones_periodic(
        N, col, height, rng, count=640,
        rad_range=(2.0, 5.0), aspect_range=(0.58, 0.94),
        palette=gravel_pal, h_amp=0.11, flat_top=False,
        ao_strength=0.34, min_sep_factor=0.0
    )

    # 6. Scattered gnarled rootlets & snapped trail twigs
    for _ in range(90):
        cx = float(rng.uniform(0.0, N))
        cy = float(rng.uniform(0.0, N))
        _stamp_blade_periodic(
            N, col, height, cx, cy,
            length=float(rng.uniform(20.0, 58.0)),
            width=float(rng.uniform(1.6, 3.0)),
            ang=float(rng.uniform(-np.pi, np.pi)),
            bend=float(rng.uniform(-0.52, 0.52)),
            c0=np.array([0.25, 0.17, 0.10], dtype=np.float32),
            c1=np.array([0.45, 0.32, 0.19], dtype=np.float32),
            h_base=0.48, h_amp=0.16, ao_str=0.36
        )

    height_detail = (height - gaussian_filter(height, sigma=2.0, mode="wrap")) * np.float32(1.25) + (grit - np.float32(0.5)) * np.float32(0.18) - crack * np.float32(0.24)
    nrm = multi_scale_normal(height, height_detail, strength_macro=9.5, strength_detail=4.4, sigma_macro=0.80, wide_step=3, wide_weight=0.38)
    save_rgb(os.path.join(out_dir, "terrain_dirt_albedo.png"), np.clip(col, 0.0, 1.0))
    save_rgb(os.path.join(out_dir, "terrain_dirt_normal.png"), nrm)


def gen_terrain_volcanic(out_dir: str, rng: np.random.Generator) -> None:
    """Angular Fractured Basalt & Scoria: organically warped hexagonal-ish cooled basalt rock
    plates with strong sculpted planar facets, razor-sharp obsidian cooling fissures (varied widths,
    never cobblestone grids!), rough pitted vesicular scoria micro-surface, and localized warm
    rusty iron-ochre volcanic ash tucked in crevices."""
    N = TEX_SIZE
    macro = fbm_tile(N, 4, 4, 4, rng)
    mid = fbm_tile(N, 10, 10, 4, rng)
    grit = micro_grit_tile(N, rng)

    # 1. Irregular fractured hexagonal-ish cooled basalt plates (higher warp + natural jitter breaks grid!)
    wx = (fbm_tile(N, 5, 5, 3, rng) - np.float32(0.5)) * np.float32(0.068) + (mid - np.float32(0.5)) * np.float32(0.016)
    wy = (fbm_tile(N, 5, 5, 3, rng) - np.float32(0.5)) * np.float32(0.068) + (fbm_tile(N, 9, 9, 2, rng) - np.float32(0.5)) * np.float32(0.016)
    _, ed_a, cid_a, lx_a, ly_a = worley_exact_tile(N, 8, 8, rng, jitter=0.72, warp_x=wx, warp_y=wy)

    # Secondary angular basalt sub-fractures shattering large plates into sharp chiseled shards
    wx2 = (fbm_tile(N, 12, 12, 2, rng) - np.float32(0.5)) * np.float32(0.032)
    wy2 = (fbm_tile(N, 12, 12, 2, rng) - np.float32(0.5)) * np.float32(0.032)
    _, ed_b, cid_b, lx_b, ly_b = worley_exact_tile(N, 16, 16, rng, jitter=0.80, warp_x=wx2, warp_y=wy2)

    # Bold tilted crystalline basalt planar facets (strong light/shadow angle contrast per shard!)
    ang_a = cid_a * np.float32(6.283185)
    facet_a = np.clip(np.float32(0.5) + (lx_a * np.cos(ang_a) + ly_a * np.sin(ang_a)) * np.float32(0.68), 0.0, 1.0)
    ang_b = cid_b * np.float32(6.283185)
    facet_b = np.clip(np.float32(0.5) + (lx_b * np.cos(ang_b) + ly_b * np.sin(ang_b)) * np.float32(0.58), 0.0, 1.0)
    sub_mask = smoothstep(0.30, 0.72, cid_a * np.float32(0.55) + macro * np.float32(0.45))

    # Varied-width razor-sharp obsidian fissures (some tight hairline cracks, some deep broken clefts!)
    fiss_open = smoothstep(0.18, 0.78, fbm_tile(N, 6, 6, 3, rng))
    fiss_w = np.float32(0.016) + np.float32(0.032) * fiss_open
    fissure_main = np.float32(1.0) - smoothstep(0.006, fiss_w, ed_a)
    fissure_sub = (np.float32(1.0) - smoothstep(0.005, 0.026, ed_b)) * sub_mask * np.float32(0.82)
    # Jagged volcanic cooling stress cracks slicing diagonally across plates
    stress_crack = smoothstep(0.83, 0.96, ridged_tile(N, 10, 10, 3, rng, power=3.0)) * np.float32(0.85)
    fissure = np.clip(np.maximum(np.maximum(fissure_main, fissure_sub), stress_crack), 0.0, 1.0)

    # Crisp angular glassy-obsidian catchlights on sunlit broken plate edges
    ed_up = np.roll(ed_a, 3, axis=0)
    ed_left = np.roll(ed_a, 3, axis=1)
    rim_glint = np.clip((ed_a - ed_up) * np.float32(5.2) + (ed_a - ed_left) * np.float32(3.8), 0.0, 1.0) * smoothstep(0.014, 0.08, ed_a) * smoothstep(0.20, 0.08, ed_a)
    # Sub-shard rim highlight
    ed_b_up = np.roll(ed_b, 2, axis=0)
    rim_sub = np.clip((ed_b - ed_b_up) * np.float32(4.0), 0.0, 1.0) * smoothstep(0.01, 0.06, ed_b) * smoothstep(0.16, 0.06, ed_b) * sub_mask

    # 2. Rough pitted vesicular scoria pores (fast pass-1-only Worley!)
    pf1, _, pcid1, _, _ = worley_exact_tile(N, 52, 52, rng, jitter=0.92, need_edges=False)
    pf2, _, pcid2, _, _ = worley_exact_tile(N, 96, 96, rng, jitter=0.94, need_edges=False)
    scoria_zone = smoothstep(0.26, 0.72, mid * np.float32(0.6) + (np.float32(1.0) - cid_a) * np.float32(0.4))
    pores_lg = (np.float32(1.0) - smoothstep(0.08, 0.25, pf1)) * smoothstep(0.48, 0.78, pcid1) * scoria_zone
    pores_sm = (np.float32(1.0) - smoothstep(0.10, 0.30, pf2)) * smoothstep(0.36, 0.70, pcid2) * (np.float32(0.40) + np.float32(0.60) * scoria_zone)
    scoria_pits = np.clip(pores_lg * np.float32(0.85) + pores_sm * np.float32(0.62), 0.0, 1.0)

    # 3. Basalt-obsidian palette calibrated around lum ~0.185 (matching baseline 0.184!)
    plate_val = np.clip(np.float32(0.42) * facet_a + np.float32(0.36) * cid_a + np.float32(0.22) * facet_b * sub_mask, 0.0, 1.0)
    col = lerp3((0.13, 0.125, 0.15), (0.34, 0.325, 0.36), smoothstep(0.14, 0.88, plate_val))
    # Crisp angular obsidian edge glints
    col = lerp3(col, (0.44, 0.43, 0.48), np.clip(rim_glint * np.float32(0.62) + rim_sub * np.float32(0.35), 0.0, 0.75))

    # Localized warm rusty iron-ochre volcanic ash (ONLY in patchy sheltered pockets — NOT neon ring around every cell!)
    ash_patch = smoothstep(0.56, 0.84, fbm_tile(N, 4, 4, 3, rng))
    rust_pocket = smoothstep(0.015, 0.075, ed_a) * smoothstep(0.22, 0.075, ed_a) * ash_patch * smoothstep(0.35, 0.75, mid)
    col = lerp3(col, (0.44, 0.25, 0.16), rust_pocket * np.float32(0.62))
    pale_ash = smoothstep(0.015, 0.065, ed_a) * smoothstep(0.16, 0.065, ed_a) * smoothstep(0.58, 0.86, macro)
    col = lerp3(col, (0.40, 0.38, 0.37), pale_ash * np.float32(0.44))

    # Crisp crystalline basalt micro-grit
    col *= (np.float32(0.80) + np.float32(0.38) * grit)[..., None]

    # Deep razor-sharp black obsidian fissures & dark scoria vesicle pits
    col = lerp3(col, (0.020, 0.018, 0.026), np.clip(fissure * np.float32(0.95) + scoria_pits * np.float32(0.68), 0.0, 0.96))

    # 4. Crisp faceted heightfield + sharp multi-scale basalt normal map
    plate_chamfer = smoothstep(0.016, 0.10, ed_a)
    height_macro = (
        np.float32(0.34) * plate_chamfer * (np.float32(0.42) + np.float32(0.58) * cid_a)
        + np.float32(0.30) * facet_a
        + np.float32(0.16) * facet_b * sub_mask
        - np.float32(0.56) * fissure
    )
    height_detail = (
        np.float32(0.34) * grit
        - np.float32(0.44) * scoria_pits
        - np.float32(0.62) * fissure
    )
    nrm = multi_scale_normal(height_macro, height_detail, strength_macro=12.5, strength_detail=4.8, sigma_macro=0.65, wide_step=3, wide_weight=0.35)
    save_rgb(os.path.join(out_dir, "terrain_volcanic_albedo.png"), np.clip(col, 0.0, 1.0))
    save_rgb(os.path.join(out_dir, "terrain_volcanic_normal.png"), nrm)


# ==============================================================================
# 6-11. Ship & Prop Hand-Crafted 1024x1024 PBR Sets (Calibrated Neutral-Bright!)
# ==============================================================================

def gen_ship_oak(out_dir: str, rng: np.random.Generator) -> None:
    """1024x1024 staggered hand-hewn nautical oak planking (8 courses along V, grain along U).

    High-frequency crisp fibrous wood grain, longitudinal drying splits, varied off-center swirling
    knots with realistic streamline deflection, deep tar-caulked seams with warm upper bevels,
    salt-weathered end-grain darkening, irregular hand-forged square iron treenails with subtle
    tannin halos, and rich glossy-tar/worn-center vs matte-joint roughness contrast.
    Calibrated to baseline mean RGB (0.860, 0.841, 0.799)!
    """
    N = TEX_SIZE
    N_PLANKS = 8

    u = np.arange(N, dtype=np.float32) / np.float32(N)
    ux, vy = np.meshgrid(u, u)

    v_shift = np.float32(0.5 / N_PLANKS)
    seam_wobble = (fbm_tile(N, 8, 8, 2, rng) - np.float32(0.5)) * np.float32(0.0018)
    vy_w = (vy + v_shift + seam_wobble) % np.float32(1.0)
    row_idx = (np.floor(vy_w * np.float32(N_PLANKS)).astype(np.int32)) % N_PLANKS
    row_local_v = (vy_w * np.float32(N_PLANKS)) % np.float32(1.0)

    row_joints = [
        [0.11, 0.57],
        [0.37, 0.79],
        [0.04, 0.44, 0.73],
        [0.24, 0.68],
        [0.15, 0.51, 0.86],
        [0.31, 0.77],
        [0.08, 0.47, 0.82],
        [0.27, 0.64],
    ]

    plank_id = np.zeros((N, N), dtype=np.int32)
    plank_u_local = np.zeros((N, N), dtype=np.float32)
    dist_butt = np.ones((N, N), dtype=np.float32)
    plank_meta = []
    pid_counter = 0

    for r in range(N_PLANKS):
        rmask = row_idx == r
        joints = sorted(row_joints[r])
        nj = len(joints)
        for j_i in range(nj):
            j_start = joints[j_i]
            j_end = joints[(j_i + 1) % nj]
            plen = (j_end - j_start) % 1.0
            if j_i < nj - 1:
                in_seg = rmask & (ux >= j_start) & (ux < j_end)
            else:
                in_seg = rmask & ((ux >= j_start) | (ux < j_end))
            plank_id[in_seg] = pid_counter
            u_loc = (ux - np.float32(j_start)) % np.float32(1.0)
            plank_u_local[in_seg] = u_loc[in_seg]
            plank_meta.append((r, j_start, plen, pid_counter))
            pid_counter += 1
        for ju in joints:
            du = ux - np.float32(ju)
            du -= np.round(du)
            adu = np.abs(du)
            closer = rmask & (adu < dist_butt)
            dist_butt = np.where(closer, adu, dist_butt)

    plank_lum = rng.uniform(0.91, 1.06, pid_counter).astype(np.float32)
    plank_warm = rng.uniform(-0.032, 0.035, pid_counter).astype(np.float32)
    plank_phase = rng.uniform(0.0, 2.0 * np.pi, pid_counter).astype(np.float32)
    plank_freq = rng.uniform(3.6, 6.8, pid_counter).astype(np.float32)
    plank_slope = rng.uniform(-0.22, 0.22, pid_counter).astype(np.float32)
    plank_cathedral = rng.uniform(0.0, 1.0, pid_counter).astype(np.float32)

    p_lum = plank_lum[plank_id]
    p_warm = plank_warm[plank_id]
    p_phase = plank_phase[plank_id]
    p_freq = plank_freq[plank_id]
    p_slope = plank_slope[plank_id]
    p_cath = plank_cathedral[plank_id]

    # Varied off-center swirling wood knots (evaluated on fast local row slice!)
    knot_warp = np.zeros((N, N), dtype=np.float32)
    knot_dark = np.zeros((N, N), dtype=np.float32)
    knot_crack = np.zeros((N, N), dtype=np.float32)
    knot_dip = np.zeros((N, N), dtype=np.float32)

    half_row_px = N // (2 * N_PLANKS)
    for r, u_start, plen, _ in plank_meta:
        if rng.random() > 0.48 or plen < 0.24:
            continue
        frac_u = float(rng.choice([rng.uniform(0.17, 0.36), rng.uniform(0.64, 0.83)]))
        ku = (u_start + plen * frac_u) % 1.0
        kv = ((r + float(rng.choice([rng.uniform(0.24, 0.42), rng.uniform(0.58, 0.76)]))) / N_PLANKS - float(v_shift)) % 1.0
        kr_u = float(rng.uniform(0.014, 0.038))
        kr_v = float(rng.uniform(0.006, 0.014))
        tilt = float(rng.uniform(-0.20, 0.20))
        ct, st = np.float32(np.cos(tilt)), np.float32(np.sin(tilt))

        ry0 = int(r * (N // N_PLANKS)) - half_row_px - 8
        ry1 = int((r + 1) * (N // N_PLANKS)) - half_row_px + 8
        iy = np.arange(ry0, ry1, dtype=np.int32) % N
        du = ux[iy, :] - np.float32(ku)
        du -= np.round(du)
        dv = vy[iy, :] - np.float32(kv)
        dv -= np.round(dv)
        du_r = du * ct + dv * st
        dv_r = -du * st + dv * ct
        er = np.hypot(du_r / np.float32(kr_u), dv_r / np.float32(kr_v))
        same_row = (row_idx[iy, :] == r).astype(np.float32)

        deflect = np.exp(-np.float32(0.55) * (er / np.float32(1.55)) ** np.float32(2.0)) * (dv_r / np.float32(max(kr_v, 1e-4))) * same_row
        knot_warp[iy, :] += deflect * np.float32(0.24)
        ring_pat = np.float32(0.5) + np.float32(0.5) * np.sin(er * np.float32(16.0) + np.arctan2(dv_r, du_r))
        k_mask = smoothstep(1.06, 0.20, er) * same_row
        knot_dark[iy, :] = np.maximum(knot_dark[iy, :], k_mask * (np.float32(0.45) + np.float32(0.45) * ring_pat))
        check_line = smoothstep(0.30, 0.05, np.abs(dv_r / np.float32(max(kr_v, 1e-4)))) * smoothstep(0.68, 0.15, er) * same_row
        knot_crack[iy, :] = np.maximum(knot_crack[iy, :], check_line * np.float32(0.80))
        knot_dip[iy, :] = np.maximum(knot_dip[iy, :], smoothstep(0.95, 0.18, er) * same_row * np.float32(0.24))

    # Crisp high-frequency fibrous oak wood grain (strong tactile oak character!)
    base_warp = (fbm_tile(N, 3, 8, 3, rng) - np.float32(0.5)) * np.float32(0.16)
    fine_warp = perlin_tile(N, 8, 32, rng) * np.float32(0.032)
    arch = np.sin(plank_u_local * np.float32(np.pi * 2.2) + p_phase) * np.float32(0.14) * p_cath
    gv = row_local_v + p_slope * plank_u_local + arch + base_warp + fine_warp + knot_warp

    ring_phase = gv * np.float32(2.0 * np.pi) * p_freq + p_phase
    ring_raw = np.float32(0.5) + np.float32(0.5) * np.sin(ring_phase + np.float32(0.40) * np.sin(ring_phase))
    ring_dark = smoothstep(0.72, 0.97, ring_raw)
    ring_sub = np.float32(0.5) + np.float32(0.5) * np.sin(ring_phase * np.float32(2.8) + base_warp * np.float32(10.0))

    # Crisp anisotropic oak wood fibers & open dark vessel pores!
    fibers_a = fbm_tile(N, 4, 96, 3, rng)
    fibers_b = value_tile(N, 16, 256, rng)
    fibers_micro = value_tile(N, 32, 512, rng)
    oak_pores = smoothstep(0.74, 0.94, value_tile(N, 36, 320, rng)) * smoothstep(0.28, 0.80, fibers_a)
    med_rays = smoothstep(0.82, 0.96, value_tile(N, 20, 160, rng)) * np.float32(0.042)

    # Crisp longitudinal drying splits / seasoning checks running along the grain
    split_n = ridged_tile(N, 4, 64, 2, rng, power=3.4)
    split_gate = smoothstep(0.68, 0.90, fbm_tile(N, 5, 16, 2, rng))
    drying_split = smoothstep(0.82, 0.96, split_n) * split_gate * smoothstep(0.06, 0.14, np.minimum(row_local_v, np.float32(1.0) - row_local_v))

    grain_val = (
        np.float32(1.01)
        - np.float32(0.125) * ring_dark
        + np.float32(0.070) * (ring_sub - np.float32(0.5))
        + np.float32(0.145) * (fibers_a - np.float32(0.5))
        + np.float32(0.095) * (fibers_b - np.float32(0.5))
        + np.float32(0.060) * (fibers_micro - np.float32(0.5))
        - np.float32(0.155) * oak_pores
        + med_rays
        - np.float32(0.38) * drying_split
    )

    # Salt-weathered end-grain darkening near butt joints
    end_wick = (np.float32(1.0) - smoothstep(0.004, 0.046, dist_butt)) * (np.float32(0.52) + np.float32(0.48) * fibers_a)

    # Tight deep dark tar-caulked seams + crisp sunlit warm upper plank bevel catchlights
    dist_h_edge = np.minimum(row_local_v, np.float32(1.0) - row_local_v)
    seam_h = np.float32(1.0) - smoothstep(0.012, 0.030, dist_h_edge)
    seam_v = np.float32(1.0) - smoothstep(0.0015, 0.0038, dist_butt)
    seam = np.maximum(seam_h, seam_v)

    upper_bevel = smoothstep(0.020, 0.050, row_local_v) * smoothstep(0.13, 0.050, row_local_v)
    lower_shade = smoothstep(0.980, 0.950, row_local_v) * smoothstep(0.88, 0.950, row_local_v)
    butt_bevel = smoothstep(0.0025, 0.007, dist_butt) * smoothstep(0.018, 0.007, dist_butt)
    edge_hi = np.clip(upper_bevel * np.float32(0.90) + butt_bevel * np.float32(0.55), 0.0, 1.0)

    # Irregular hand-forged square iron treenails / deck spikes (FAST local bounding box!)
    spike_mask = np.zeros((N, N), dtype=np.float32)
    spike_cap = np.zeros((N, N), dtype=np.float32)
    spike_ring = np.zeros((N, N), dtype=np.float32)
    spike_patina = np.zeros((N, N), dtype=np.float32)

    def _add_forged_spike_fast(su: float, sv: float, sr: float):
        rot = float(rng.uniform(-0.35, 0.35))
        cr, sr_a = np.float32(np.cos(rot)), np.float32(np.sin(rot))
        cx = int(round(su * N))
        cy = int(round(sv * N))
        pad_x = int(np.ceil(sr * 4.2 * N)) + 2
        pad_y = int(np.ceil(sr * 2.4 * N)) + 2
        ix = np.arange(cx - pad_x, cx + pad_x + 1, dtype=np.int32) % N
        iy = np.arange(cy - pad_y, cy + pad_y + 1, dtype=np.int32) % N
        lx = (np.arange(-pad_x, pad_x + 1, dtype=np.float32) / np.float32(N))[None, :]
        ly = (np.arange(-pad_y, pad_y + 1, dtype=np.float32) / np.float32(N))[:, None]
        ru = np.abs(lx * cr + ly * sr_a)
        rv = np.abs(-lx * sr_a + ly * cr)
        sd = np.power(ru ** np.float32(4.0) + rv ** np.float32(4.0), np.float32(0.25))
        sm = np.float32(1.0) - smoothstep(sr * 0.72, sr * 1.08, sd)
        cap = sm * np.clip(np.float32(0.65) - (lx + ly) / np.float32(max(sr * 2.2, 1e-4)), 0.0, 1.0)
        ring = smoothstep(sr * 1.75, sr * 1.05, sd) * smoothstep(sr * 0.65, sr * 1.05, sd)
        halo_d = np.hypot(lx / np.float32(sr * 3.8), ly / np.float32(sr * 1.9))
        pat = (np.float32(1.0) - smoothstep(0.32, 1.05, halo_d)) * (np.float32(1.0) - sm)
        gy, gx = np.ix_(iy, ix)
        spike_mask[gy, gx] = np.maximum(spike_mask[gy, gx], sm)
        spike_cap[gy, gx] = np.maximum(spike_cap[gy, gx], cap)
        spike_ring[gy, gx] = np.maximum(spike_ring[gy, gx], ring)
        spike_patina[gy, gx] = np.maximum(spike_patina[gy, gx], pat)

    for r in range(N_PLANKS):
        for ju in row_joints[r]:
            for side_u in (-0.014, 0.014):
                for nv_loc in (0.28, 0.72):
                    su = (ju + side_u + rng.uniform(-0.0020, 0.0020)) % 1.0
                    sv = ((r + nv_loc + rng.uniform(-0.035, 0.035)) / N_PLANKS - float(v_shift)) % 1.0
                    _add_forged_spike_fast(su, sv, float(rng.uniform(0.0033, 0.0044)))
        for r_m, u_s, plen, _ in plank_meta:
            if r_m == r and plen > 0.38:
                rib_u = (u_s + plen * 0.50 + rng.uniform(-0.02, 0.02)) % 1.0
                for nv_loc in (0.28, 0.72):
                    su = (rib_u + rng.uniform(-0.002, 0.002)) % 1.0
                    sv = ((r + nv_loc + rng.uniform(-0.03, 0.03)) / N_PLANKS - float(v_shift)) % 1.0
                    _add_forged_spike_fast(su, sv, float(rng.uniform(0.0030, 0.0040)))

    # Compose neutral-bright warm oak albedo (calibrated to mean RGB ~ (0.860, 0.841, 0.799)!)
    base_l = grain_val * p_lum + np.float32(0.072) * edge_hi - np.float32(0.048) * lower_shade - np.float32(0.105) * end_wick
    albedo = np.stack([
        base_l * (np.float32(1.022) + p_warm),
        base_l * np.float32(0.996),
        base_l * (np.float32(0.944) - p_warm * np.float32(0.85)),
    ], axis=-1)
    albedo = lerp3(albedo, (0.22, 0.16, 0.11), np.clip(knot_dark * np.float32(0.60) + knot_crack * np.float32(0.45), 0.0, 0.86))
    albedo = lerp3(albedo, (0.46, 0.37, 0.29), spike_patina * np.float32(0.32))
    albedo *= (np.float32(1.0) - np.float32(0.28) * spike_ring)[..., None]
    spike_col = lerp3((0.15, 0.15, 0.16), (0.34, 0.33, 0.34), spike_cap)
    albedo = albedo * (np.float32(1.0) - np.float32(0.85) * spike_mask[..., None]) + spike_col * (np.float32(0.85) * spike_mask[..., None])
    albedo = lerp3(albedo, (0.10, 0.085, 0.07), seam * np.float32(0.86))
    albedo = _calibrate_rgb(np.clip(albedo, 0.05, 1.0), (0.860, 0.841, 0.799), strength=0.92, lo=0.05, hi=1.0)

    plank_crown = np.sqrt(np.clip(smoothstep(0.015, 0.11, dist_h_edge), 0.0, 1.0)) * np.sqrt(np.clip(smoothstep(0.002, 0.012, dist_butt), 0.0, 1.0))
    height_macro = (
        np.float32(0.52) * plank_crown
        + np.float32(0.11) * (np.float32(1.0) - ring_dark)
        - np.float32(0.44) * seam
        - knot_dip
        - np.float32(0.12) * spike_ring
        + np.float32(0.10) * spike_mask
    )
    height_detail = (
        np.float32(0.32) * fibers_a
        + np.float32(0.24) * fibers_b
        + np.float32(0.14) * fibers_micro
        - np.float32(0.32) * oak_pores
        - np.float32(0.52) * drying_split
        - np.float32(0.48) * knot_crack
        - np.float32(0.46) * seam
        + np.float32(0.20) * spike_cap
    )
    nrm = multi_scale_normal(height_macro, height_detail, strength_macro=7.8, strength_detail=4.6, sigma_macro=0.60, wide_step=2, wide_weight=0.35)

    # Rich PBR roughness contrast: glossy pine-tar seams (0.44..0.52) & foot-worn centers (0.58)
    # vs matte weathered butt joints, open pores, drying splits, knots & forged iron spikes (0.84..0.96)
    center_wear = plank_crown * smoothstep(0.05, 0.25, row_local_v) * smoothstep(0.95, 0.75, row_local_v)
    rough = (
        np.float32(0.79)
        - np.float32(0.17) * center_wear * (np.float32(0.5) + np.float32(0.5) * ring_sub)
        + np.float32(0.14) * oak_pores
        + np.float32(0.16) * drying_split
        + np.float32(0.13) * end_wick
        + np.float32(0.12) * knot_dark
        + np.float32(0.16) * spike_mask
    )
    rough = rough * (np.float32(1.0) - seam) + (np.float32(0.45) + np.float32(0.10) * fibers_b) * seam
    rough = np.clip(rough, 0.44, 0.96)

    save_rgb(os.path.join(out_dir, "ship_oak_albedo.png"), albedo)
    save_rgb(os.path.join(out_dir, "ship_oak_normal.png"), nrm)
    save_gray(os.path.join(out_dir, "ship_oak_rough.png"), rough)


def gen_ship_paint(out_dir: str, rng: np.random.Generator) -> None:
    """1024x1024 crisp brush-stroked marine paint showing subtle underlying oak plank seams,
    fine hog-bristle relief, and gentle sea-spray edge wear (calibrated bright neutral ~0.885!)."""
    N = TEX_SIZE
    u = np.arange(N, dtype=np.float32) / np.float32(N)
    _, vy = np.meshgrid(u, u)

    plank_v = (vy * np.float32(8.0) + np.float32(0.5)) % np.float32(1.0)
    dist_seam = np.minimum(plank_v, np.float32(1.0) - plank_v)
    plank_seam = np.float32(1.0) - smoothstep(0.012, 0.036, dist_seam)
    plank_edge = smoothstep(0.022, 0.072, dist_seam) * smoothstep(0.15, 0.072, dist_seam)

    brush_broad = fbm_tile(N, 3, 18, 3, rng)
    brush_mid = fbm_tile(N, 6, 48, 3, rng)
    bristles = value_tile(N, 12, 224, rng) * np.float32(0.58) + value_tile(N, 24, 448, rng) * np.float32(0.42)
    wood_grain = fbm_tile(N, 4, 72, 3, rng)

    patina = fbm_tile(N, 6, 6, 3, rng)
    wear_noise = fbm_tile(N, 16, 28, 3, rng)
    edge_wear = plank_edge * smoothstep(0.50, 0.78, wear_noise * np.float32(0.65) + patina * np.float32(0.35))
    flake_wear = smoothstep(0.74, 0.89, ridged_tile(N, 10, 14, 3, rng)) * smoothstep(0.50, 0.80, patina) * np.float32(0.78)
    wear = np.clip(edge_wear * np.float32(0.85) + flake_wear, 0.0, 1.0)
    salt_dust = smoothstep(0.62, 0.88, fbm_tile(N, 10, 10, 3, rng)) * plank_edge * np.float32(0.45)

    val = (
        np.float32(0.915)
        + np.float32(0.12) * (brush_broad - np.float32(0.5))
        + np.float32(0.10) * (brush_mid - np.float32(0.5))
        + np.float32(0.075) * (bristles - np.float32(0.5))
        - np.float32(0.15) * plank_seam
        - np.float32(0.18) * wear
        + np.float32(0.055) * salt_dust
    )
    albedo = np.stack([
        val * (np.float32(1.007) + np.float32(0.022) * wear),
        val * np.float32(0.998),
        val * (np.float32(0.985) - np.float32(0.024) * wear),
    ], axis=-1)
    albedo = _calibrate_rgb(np.clip(albedo, 0.45, 1.0), (0.890, 0.881, 0.869), strength=0.92, lo=0.45, hi=1.0)

    height_macro = np.float32(0.45) * brush_broad + np.float32(0.25) * wood_grain - np.float32(0.34) * plank_seam - np.float32(0.24) * wear
    height_detail = np.float32(0.48) * bristles + np.float32(0.30) * brush_mid - np.float32(0.42) * wear - np.float32(0.30) * plank_seam
    nrm = multi_scale_normal(height_macro, height_detail, strength_macro=4.8, strength_detail=3.8, sigma_macro=0.70, wide_step=2, wide_weight=0.35)

    rough = np.float32(0.55) + np.float32(0.13) * (np.float32(1.0) - brush_broad) + np.float32(0.08) * (np.float32(1.0) - bristles) + np.float32(0.24) * wear + np.float32(0.15) * plank_seam + np.float32(0.10) * salt_dust
    rough = np.clip(rough, 0.40, 0.86)

    save_rgb(os.path.join(out_dir, "ship_paint_albedo.png"), albedo)
    save_rgb(os.path.join(out_dir, "ship_paint_normal.png"), nrm)
    save_gray(os.path.join(out_dir, "ship_paint_rough.png"), rough)


def gen_ship_brass(out_dir: str, rng: np.random.Generator) -> None:
    """1024x1024 burnished hand-hammered nautical brass: subtle circular/directional lathe-polish
    sheen, smooth planishing hammer dimples, organic warm antique-bronze micro-crevice patina
    (ZERO blocky noise!), and crisp hammered roughness variation.
    Calibrated to baseline mean RGB (0.889, 0.895, 0.871)!"""
    N = TEX_SIZE
    u = np.arange(N, dtype=np.float32) / np.float32(N)
    ux, vy = np.meshgrid(u, u)

    # Smooth shallow hand-peened brass planishing dimples (fast pass-1-only Worley!)
    f1_a, _, _, _, _ = worley_exact_tile(N, 12, 12, rng, jitter=0.86, need_edges=False)
    f1_b, _, _, _, _ = worley_exact_tile(N, 24, 24, rng, jitter=0.90, need_edges=False)
    hammer_cup = np.float32(0.62) * (smoothstep(0.0, 0.92, f1_a) ** np.float32(1.35)) + np.float32(0.38) * (smoothstep(0.0, 0.94, f1_b) ** np.float32(1.35))
    hammer_cup = gaussian_filter(hammer_cup, sigma=1.6, mode="wrap")

    # Fine circular-arced + directional lathe-polish sheen lines
    lathe_warp = (fbm_tile(N, 4, 4, 3, rng) - np.float32(0.5)) * np.float32(0.14)
    # Periodic multi-ring circular buffing sheen (exact periodic cosines!)
    swirl = np.float32(0.5) + np.float32(0.5) * np.sin(
        np.float32(2.0 * np.pi) * (np.float32(4.0) * ux + np.float32(2.0) * vy)
        + np.sin(np.float32(2.0 * np.pi) * (np.float32(2.0) * ux - np.float32(4.0) * vy)) * np.float32(1.6)
        + lathe_warp * np.float32(5.0)
    )
    lathe_fine = value_tile(N, 8, 256, rng) * np.float32(0.55) + value_tile(N, 16, 512, rng) * np.float32(0.45)
    polish_arc = fbm_tile(N, 5, 64, 3, rng)
    scratches = smoothstep(0.84, 0.96, ridged_tile(N, 14, 52, 2, rng, power=2.6)) * np.float32(0.32)

    # Organic smooth tarnish patina nestled subtly in micro-crevices (smooth fBM, zero pixel blocks!)
    patina_macro = smoothstep(0.46, 0.84, fbm_tile(N, 6, 6, 4, rng))
    patina_micro = fbm_tile(N, 24, 24, 3, rng)
    crevice_tarnish = patina_macro * smoothstep(0.54, 0.14, hammer_cup) * smoothstep(0.34, 0.78, patina_micro)

    val = (
        np.float32(0.915)
        + np.float32(0.11) * (hammer_cup - np.float32(0.5))
        + np.float32(0.065) * (polish_arc - np.float32(0.5))
        + np.float32(0.048) * (lathe_fine - np.float32(0.5))
        + np.float32(0.032) * (swirl - np.float32(0.5))
        + np.float32(0.028) * scratches
        - np.float32(0.22) * crevice_tarnish
    )
    # Warm antique-bronze patina shift inside recessed dimples (subtle, authentic, never pixelated green!)
    albedo = np.stack([
        val * (np.float32(1.000) - np.float32(0.05) * crevice_tarnish),
        val * (np.float32(1.005) - np.float32(0.02) * crevice_tarnish),
        val * (np.float32(0.976) - np.float32(0.06) * crevice_tarnish),
    ], axis=-1)
    albedo = _calibrate_rgb(np.clip(albedo, 0.45, 1.0), (0.889, 0.895, 0.871), strength=0.92, lo=0.45, hi=1.0)

    height_macro = np.float32(0.70) * hammer_cup + np.float32(0.20) * polish_arc + np.float32(0.10) * swirl - np.float32(0.14) * crevice_tarnish
    height_detail = np.float32(0.48) * lathe_fine + np.float32(0.26) * polish_arc - np.float32(0.32) * scratches - np.float32(0.16) * crevice_tarnish
    nrm = multi_scale_normal(height_macro, height_detail, strength_macro=4.2, strength_detail=2.8, sigma_macro=0.9, wide_step=2, wide_weight=0.35)

    rough = np.float32(0.34) - np.float32(0.13) * (hammer_cup - np.float32(0.5)) + np.float32(0.06) * (np.float32(1.0) - polish_arc) + np.float32(0.22) * crevice_tarnish
    rough = np.clip(rough, 0.22, 0.56)

    save_rgb(os.path.join(out_dir, "ship_brass_albedo.png"), albedo)
    save_rgb(os.path.join(out_dir, "ship_brass_normal.png"), nrm)
    save_gray(os.path.join(out_dir, "ship_brass_rough.png"), rough)


def gen_ship_iron(out_dir: str, rng: np.random.Generator) -> None:
    """1024x1024 hand-forged blacksmith wrought iron: authentic overlapping concave anvil hammer
    dimples (ZERO white Voronoi caustic webs!), brushed directional forging streaks, crisp dark
    pitted forge-scale & weathered roughness contrast.
    Calibrated to baseline mean RGB (0.817, 0.816, 0.816)!"""
    N = TEX_SIZE
    f1_a, _, cid_a, lx_a, ly_a = worley_exact_tile(N, 11, 11, rng, jitter=0.86, need_edges=False)
    f1_b, _, cid_b, _, _ = worley_exact_tile(N, 23, 23, rng, jitter=0.90, need_edges=False)
    scale_n = fbm_tile(N, 9, 9, 4, rng)
    grain_iron = fbm_tile(N, 6, 48, 3, rng)
    brush_fine = value_tile(N, 12, 224, rng)
    grit = micro_grit_tile(N, rng)

    # Authentic concave blacksmith hammer strikes + subtle directional metallic bevel catchlight per dimple
    cup_a = smoothstep(0.0, 0.92, f1_a) ** np.float32(1.45)
    cup_b = smoothstep(0.0, 0.94, f1_b) ** np.float32(1.40)
    # Directional top-left highlight inside hammered bevels (NO white Voronoi outline!)
    bevel_lit = np.clip((-lx_a * np.float32(0.65) - ly_a * np.float32(0.75)) * np.float32(0.5) + np.float32(0.5), 0.0, 1.0)
    hammer_h = np.float32(0.54) * cup_a + np.float32(0.26) * cup_b + np.float32(0.20) * scale_n
    hammer_h = gaussian_filter(hammer_h, sigma=1.4, mode="wrap")

    # Crisp dark pitted black-oxide forge scale & subtle warm rust-oxide flecks inside deeper hollows
    scale_pits = smoothstep(0.68, 0.90, np.float32(1.0) - grit) * smoothstep(0.32, 0.78, np.float32(1.0) - cup_a)
    rust_zone = smoothstep(0.58, 0.86, fbm_tile(N, 5, 5, 3, rng))
    rust_flecks = rust_zone * smoothstep(0.42, 0.84, np.float32(1.0) - cup_a) * smoothstep(0.44, 0.80, np.float32(1.0) - scale_n)

    val = (
        np.float32(0.83)
        + np.float32(0.15) * (hammer_h - np.float32(0.5))
        + np.float32(0.075) * (bevel_lit - np.float32(0.5)) * (np.float32(0.4) + np.float32(0.6) * cup_a)
        + np.float32(0.09) * (grain_iron - np.float32(0.5))
        + np.float32(0.055) * (brush_fine - np.float32(0.5))
        + np.float32(0.09) * (grit - np.float32(0.5))
        - np.float32(0.22) * scale_pits
    )
    albedo = np.stack([
        val * (np.float32(1.0) + np.float32(0.16) * rust_flecks),
        val * (np.float32(1.0) - np.float32(0.02) * rust_flecks),
        val * (np.float32(1.0) - np.float32(0.16) * rust_flecks),
    ], axis=-1)
    albedo = _calibrate_rgb(np.clip(albedo, 0.36, 1.0), (0.817, 0.816, 0.816), strength=0.92, lo=0.36, hi=1.0)

    height_macro = np.float32(0.66) * hammer_h + np.float32(0.18) * scale_n + np.float32(0.16) * grain_iron
    height_detail = np.float32(0.40) * grit + np.float32(0.24) * brush_fine - np.float32(0.50) * scale_pits
    nrm = multi_scale_normal(height_macro, height_detail, strength_macro=6.5, strength_detail=4.0, sigma_macro=0.85, wide_step=2, wide_weight=0.35)

    rough = np.float32(0.60) - np.float32(0.17) * (hammer_h - np.float32(0.5)) - np.float32(0.06) * (bevel_lit - np.float32(0.5)) + np.float32(0.22) * scale_pits + np.float32(0.16) * rust_flecks
    rough = np.clip(rough, 0.38, 0.80)

    save_rgb(os.path.join(out_dir, "ship_iron_albedo.png"), albedo)
    save_rgb(os.path.join(out_dir, "ship_iron_normal.png"), nrm)
    save_gray(os.path.join(out_dir, "ship_iron_rough.png"), rough)


def gen_ship_rope(out_dir: str, rng: np.random.Generator) -> None:
    """1024x1024 ultra-crisp 3-strand twisted braided hemp rope: bold helical rope strands,
    deep inter-strand shadow crevices, crisp counter-twisted hemp yarn sub-bundles & micro-fibers.
    Calibrated to baseline mean RGB (0.874, 0.848, 0.800)!"""
    N = TEX_SIZE
    u = np.arange(N, dtype=np.float32) / np.float32(N)
    ux, vy = np.meshgrid(u, u)

    warp = (fbm_tile(N, 6, 6, 3, rng) - np.float32(0.5)) * np.float32(0.36)
    strand_phase = np.float32(2.0 * np.pi) * (np.float32(6.0) * ux + np.float32(3.0) * vy) + warp
    strand_raw = np.abs(np.sin(strand_phase * np.float32(0.5)))
    strand_h = np.power(np.clip(strand_raw, 0.0, 1.0), np.float32(0.66))
    # Directional tubular highlight across each rounded hemp strand
    strand_slope = np.cos(strand_phase * np.float32(0.5)) * np.sign(np.sin(strand_phase * np.float32(0.5)))
    groove = smoothstep(0.32, 0.02, strand_raw)
    groove_deep = smoothstep(0.14, 0.0, strand_raw)

    f_warp = (fbm_tile(N, 12, 12, 3, rng) - np.float32(0.5)) * np.float32(2.6)
    f_warp2 = (fbm_tile(N, 24, 24, 2, rng) - np.float32(0.5)) * np.float32(1.8)
    yarn_1 = np.float32(0.5) + np.float32(0.5) * np.sin(np.float32(2.0 * np.pi) * (np.float32(18.0) * ux - np.float32(12.0) * vy) + f_warp)
    yarn_2 = np.float32(0.5) + np.float32(0.5) * np.sin(np.float32(2.0 * np.pi) * (np.float32(36.0) * ux - np.float32(24.0) * vy) + f_warp * np.float32(1.5) + f_warp2)
    micro_fib = np.float32(0.5) + np.float32(0.5) * np.sin(np.float32(2.0 * np.pi) * (np.float32(96.0) * ux - np.float32(64.0) * vy) + f_warp * np.float32(2.4))
    husk = micro_grit_tile(N, rng)
    fibers = np.float32(0.42) * yarn_1 + np.float32(0.34) * yarn_2 + np.float32(0.24) * micro_fib

    # Stray organic hemp fiber wisps slightly breaking up hard shadow grooves
    wisp = smoothstep(0.72, 0.94, micro_fib * np.float32(0.6) + husk * np.float32(0.4)) * groove * np.float32(0.14)

    val = (
        np.float32(0.76)
        + np.float32(0.24) * strand_h
        + np.float32(0.05) * strand_slope
        + np.float32(0.16) * (fibers - np.float32(0.5))
        + np.float32(0.11) * (husk - np.float32(0.5))
        - np.float32(0.32) * groove
        - np.float32(0.24) * groove_deep
        + wisp
    )
    albedo = np.stack([
        val * np.float32(1.028),
        val * np.float32(0.996),
        val * np.float32(0.940),
    ], axis=-1)
    albedo = _calibrate_rgb(np.clip(albedo, 0.14, 1.0), (0.874, 0.848, 0.800), strength=0.90, lo=0.14, hi=1.0)

    height_macro = np.float32(0.72) * strand_h + np.float32(0.18) * yarn_1 - np.float32(0.42) * groove_deep
    height_detail = np.float32(0.45) * yarn_2 + np.float32(0.35) * micro_fib + np.float32(0.20) * husk - np.float32(0.35) * groove_deep
    nrm = multi_scale_normal(height_macro, height_detail, strength_macro=10.5, strength_detail=4.8, sigma_macro=0.6, wide_step=2, wide_weight=0.35)

    rough = np.float32(0.84) + np.float32(0.12) * groove + np.float32(0.08) * (np.float32(1.0) - fibers) + np.float32(0.05) * (np.float32(1.0) - husk)
    rough = np.clip(rough, 0.80, 0.98)

    save_rgb(os.path.join(out_dir, "ship_rope_albedo.png"), albedo)
    save_rgb(os.path.join(out_dir, "ship_rope_normal.png"), nrm)
    save_gray(os.path.join(out_dir, "ship_rope_rough.png"), rough)


def gen_ship_cloth(out_dir: str, rng: np.random.Generator) -> None:
    """1024x1024 tactile heavy maritime sailcloth: crisp woven warp/weft canvas grid,
    organic hand-spun flax thread slubs, gentle cloth tension ripples, and a subtle double-stitched
    vertical panel seam. Calibrated to baseline mean RGB (0.937, 0.927, 0.909)!"""
    N = TEX_SIZE
    u = np.arange(N, dtype=np.float32) / np.float32(N)
    ux, vy = np.meshgrid(u, u)

    # 96 even threads per 1024px tile, +0.5 phase offset so tile borders sit mid-thread (ultra-low border diff!)
    THREADS = 96
    w_warp = (fbm_tile(N, 8, 8, 2, rng) - np.float32(0.5)) * np.float32(0.008)
    w_weft = (fbm_tile(N, 8, 8, 2, rng) - np.float32(0.5)) * np.float32(0.008)
    t_u = (ux + w_warp) * np.float32(THREADS) + np.float32(0.5)
    t_v = (vy + w_weft) * np.float32(THREADS) + np.float32(0.5)

    iu = np.floor(t_u).astype(np.int32) % THREADS
    iv = np.floor(t_v).astype(np.int32) % THREADS
    parity = ((iu + iv) & 1).astype(np.float32)

    warp_thick = rng.uniform(0.84, 1.18, THREADS).astype(np.float32)[iu]
    weft_thick = rng.uniform(0.84, 1.18, THREADS).astype(np.float32)[iv]
    warp_tone = rng.uniform(-0.032, 0.032, THREADS).astype(np.float32)[iu]
    weft_tone = rng.uniform(-0.032, 0.032, THREADS).astype(np.float32)[iv]

    fu = np.maximum(np.sin((t_u % np.float32(1.0)) * np.float32(np.pi)), np.float32(0.0))
    fv = np.maximum(np.sin((t_v % np.float32(1.0)) * np.float32(np.pi)), np.float32(0.0))

    thread_u = (np.clip(fu * warp_thick, 0.0, 1.0) ** np.float32(0.68)) * (np.float32(0.55) + np.float32(0.45) * fv)
    thread_v = (np.clip(fv * weft_thick, 0.0, 1.0) ** np.float32(0.68)) * (np.float32(0.55) + np.float32(0.45) * fu)
    weave_h = np.where(parity < 0.5, thread_u, thread_v)
    thread_tone = np.where(parity < 0.5, warp_tone, weft_tone)
    pore = smoothstep(0.32, 0.04, weave_h)

    du_seam = np.abs(ux - np.float32(0.50))
    panel_step = smoothstep(0.016, 0.002, du_seam) * np.sign(ux - np.float32(0.50))
    seam_fold = smoothstep(0.014, 0.004, du_seam) * (np.float32(1.0) - smoothstep(0.004, 0.0005, du_seam))
    stitch_y = np.sin(vy * np.float32(2.0 * np.pi * 64.0))
    stitch_dash = smoothstep(0.15, 0.72, stitch_y)
    stitch_hole = smoothstep(-0.65, -0.96, stitch_y)
    stitch_x = np.maximum(
        smoothstep(0.0032, 0.0008, np.abs(ux - np.float32(0.491))),
        smoothstep(0.0032, 0.0008, np.abs(ux - np.float32(0.509))),
    )
    stitch_thread = stitch_x * stitch_dash
    stitch_pin = stitch_x * stitch_hole

    soft_fold = fbm_tile(N, 4, 4, 3, rng)
    flax_fiber = micro_grit_tile(N, rng)

    val = (
        np.float32(0.865)
        + np.float32(0.14) * weave_h
        + thread_tone
        + np.float32(0.045) * (soft_fold - np.float32(0.5))
        + np.float32(0.04) * (flax_fiber - np.float32(0.5))
        - np.float32(0.095) * pore
        - np.float32(0.055) * seam_fold
        - np.float32(0.12) * stitch_pin
        + np.float32(0.05) * stitch_thread
    )
    albedo = np.stack([
        val * np.float32(1.010),
        val * np.float32(1.000),
        val * np.float32(0.980),
    ], axis=-1)
    albedo = _calibrate_rgb(np.clip(albedo, 0.58, 1.0), (0.937, 0.927, 0.909), strength=0.92, lo=0.58, hi=1.0)

    height_macro = np.float32(0.58) * weave_h + np.float32(0.22) * soft_fold + np.float32(0.10) * panel_step
    height_detail = np.float32(0.65) * weave_h + np.float32(0.15) * flax_fiber + np.float32(0.32) * stitch_thread - np.float32(0.35) * stitch_pin - np.float32(0.25) * seam_fold
    nrm = multi_scale_normal(height_macro, height_detail, strength_macro=3.6, strength_detail=3.8, sigma_macro=0.6, wide_step=2, wide_weight=0.30)

    save_rgb(os.path.join(out_dir, "ship_cloth_albedo.png"), albedo)
    save_rgb(os.path.join(out_dir, "ship_cloth_normal.png"), nrm)


GENERATORS = [
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


def _run_one(args):
    idx, label, tex_dir = args
    ts = time.perf_counter()
    rng = np.random.default_rng(SEED + idx * 1009)
    GENERATORS[idx][1](tex_dir, rng)
    return idx, label, time.perf_counter() - ts


def main() -> None:
    t0 = time.perf_counter()
    outdir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.getcwd(), "assets", "generated")
    tex_dir = os.path.join(outdir, "textures")
    os.makedirs(tex_dir, exist_ok=True)

    tasks = [(idx, label, tex_dir) for idx, (label, _) in enumerate(GENERATORS)]
    workers = min(os.cpu_count() or 2, 4)
    if workers > 1:
        with ProcessPoolExecutor(max_workers=workers) as ex:
            results = list(ex.map(_run_one, tasks))
    else:
        results = [_run_one(t) for t in tasks]

    for idx, label, dt in sorted(results):
        print(f"  [{idx + 1:2d}/{len(GENERATORS)}] {label:<18s} ({dt:.2f} s)")

    print(f"wrote 27 seamless 1024x1024 PBR textures into {tex_dir} in {time.perf_counter() - t0:.2f} s")


if __name__ == "__main__":
    main()
