#!/usr/bin/env python3
"""Generate the noise the volumetric clouds are sculpted from.

Usage: gen_cloud_volume.py <assets/generated dir>
Writes two seamless textures, all from seeded random numbers (no external data):

<out>/sky/cloud_volume.png   64x64x64 RGBA volume stored as an 8x8 atlas of slices
                             (imported as a Texture3D, see the .import next to it)
  R  billows: spherical caps over Worley cells (three octaves), cauliflower lumps
  G  finer caps, erodes edges into smaller puffs
  B  Perlin fbm, soft wisps and warping
  A  very low frequency lumps, makes whole clouds lopsided

<out>/sky/cloud_map.png      512x512 RGBA, the "weather map" sampled over world XZ
  R  cumulus footprints (Perlin layout carved by Worley), histogram-equalised so a
     threshold t leaves roughly (1 - t) of the sky covered
  G  large-scale variation (fields of cloud and open sky), equalised
  B  tower height variation, so neighbouring clouds differ in height
  A  streaks stretched along V: rain shafts
"""
import os
import sys

import numpy as np
from PIL import Image

N3 = 64
N2 = 512


def _fade(t):
    return t * t * t * (t * (t * 6 - 15) + 10)


def perlin3(freq: int, seed: int, n: int = N3) -> np.ndarray:
    rng = np.random.default_rng(seed)
    g = rng.normal(size=(freq, freq, freq, 3))
    g /= np.linalg.norm(g, axis=-1, keepdims=True)
    lin = np.arange(n) / n * freq
    z, y, x = np.meshgrid(lin, lin, lin, indexing="ij")
    x0, y0, z0 = np.floor(x).astype(int), np.floor(y).astype(int), np.floor(z).astype(int)
    fx, fy, fz = x - x0, y - y0, z - z0
    u, v, w = _fade(fx), _fade(fy), _fade(fz)
    total = np.zeros_like(x)
    for dz in (0, 1):
        for dy in (0, 1):
            for dx in (0, 1):
                gr = g[(z0 + dz) % freq, (y0 + dy) % freq, (x0 + dx) % freq]
                d = gr[..., 0] * (fx - dx) + gr[..., 1] * (fy - dy) + gr[..., 2] * (fz - dz)
                wx = u if dx else 1 - u
                wy = v if dy else 1 - v
                wz = w if dz else 1 - w
                total += d * wx * wy * wz
    return total


def worley3(freq: int, seed: int, n: int = N3) -> np.ndarray:
    rng = np.random.default_rng(seed)
    pts = rng.uniform(0.0, 1.0, (freq, freq, freq, 3))
    lin = np.arange(n) / n * freq
    z, y, x = np.meshgrid(lin, lin, lin, indexing="ij")
    cx, cy, cz = np.floor(x).astype(int), np.floor(y).astype(int), np.floor(z).astype(int)
    best = np.full(x.shape, 9.0)
    for oz in (-1, 0, 1):
        for oy in (-1, 0, 1):
            for ox in (-1, 0, 1):
                nx, ny, nz = cx + ox, cy + oy, cz + oz
                p = pts[nz % freq, ny % freq, nx % freq]
                d = np.sqrt((nx + p[..., 0] - x) ** 2 + (ny + p[..., 1] - y) ** 2 + (nz + p[..., 2] - z) ** 2)
                best = np.minimum(best, d)
    return np.clip(best, 0.0, 1.0)


def perlin2(fx_: int, fy_: int, seed: int, n: int = N2) -> np.ndarray:
    rng = np.random.default_rng(seed)
    ang = rng.uniform(0.0, 2.0 * np.pi, (fy_, fx_))
    gx, gy = np.cos(ang), np.sin(ang)
    y, x = np.meshgrid(np.arange(n) / n * fy_, np.arange(n) / n * fx_, indexing="ij")
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = x - x0, y - y0
    u, v = _fade(fx), _fade(fy)

    def corner(ix, iy, dx, dy):
        return gx[iy % fy_, ix % fx_] * dx + gy[iy % fy_, ix % fx_] * dy

    return ((corner(x0, y0, fx, fy) * (1 - u) + corner(x0 + 1, y0, fx - 1, fy) * u) * (1 - v)
            + (corner(x0, y0 + 1, fx, fy - 1) * (1 - u) + corner(x0 + 1, y0 + 1, fx - 1, fy - 1) * u) * v)


def worley2(freq: int, seed: int, n: int = N2) -> np.ndarray:
    rng = np.random.default_rng(seed)
    pts = rng.uniform(0.0, 1.0, (freq, freq, 2))
    y, x = np.meshgrid(np.arange(n) / n * freq, np.arange(n) / n * freq, indexing="ij")
    cx, cy = np.floor(x).astype(int), np.floor(y).astype(int)
    best = np.full(x.shape, 9.0)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            nx, ny = cx + ox, cy + oy
            p = pts[ny % freq, nx % freq]
            best = np.minimum(best, np.sqrt((nx + p[..., 0] - x) ** 2 + (ny + p[..., 1] - y) ** 2))
    return np.clip(best, 0.0, 1.0)


def fbm(fn, freq: int, octaves: int, seed: int, gain: float = 0.5) -> np.ndarray:
    total, amp, norm = 0.0, 1.0, 0.0
    for o in range(octaves):
        total = total + amp * fn(freq * 2 ** o, seed + o * 17)
        norm += amp
        amp *= gain
    return total / norm


def norm01(a: np.ndarray) -> np.ndarray:
    lo, hi = np.percentile(a, 0.5), np.percentile(a, 99.5)
    return np.clip((a - lo) / (hi - lo), 0.0, 1.0)


def equalise(a: np.ndarray) -> np.ndarray:
    flat = a.ravel()
    order = np.argsort(flat, kind="stable")
    ranks = np.empty_like(order)
    ranks[order] = np.arange(flat.size)
    return (ranks / (flat.size - 1)).reshape(a.shape)


def to_u8(a: np.ndarray) -> np.ndarray:
    return (np.clip(a, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def main() -> None:
    out_root = sys.argv[1] if len(sys.argv) > 1 else "assets/generated"
    out_dir = os.path.join(out_root, "sky")
    os.makedirs(out_dir, exist_ok=True)

    # --- Volume ---------------------------------------------------------
    # Spherical caps over Worley cells: round puffs with sharp creases between
    # them, which is what makes a cumulus read as a cauliflower.
    def puff(freq, seed):
        return np.sqrt(np.clip(1.0 - (worley3(freq, seed) * 1.12) ** 2, 0.0, 1.0))

    soft = norm01(fbm(perlin3, 3, 3, 131, 0.5))
    r = norm01(0.56 * puff(4, 101) + 0.26 * puff(8, 118) + 0.08 * puff(16, 135) + 0.10 * soft)
    g = norm01(0.6 * puff(10, 151) + 0.4 * puff(20, 168))
    b = norm01(fbm(perlin3, 4, 3, 171, 0.5))
    a = norm01(1.0 - fbm(worley3, 2, 2, 191, 0.35))
    vol = np.stack([r, g, b, a], axis=-1)  # z, y, x, c
    atlas = np.zeros((8 * N3, 8 * N3, 4), dtype=np.uint8)
    for i in range(N3):
        ty, tx = divmod(i, 8)
        atlas[ty * N3:(ty + 1) * N3, tx * N3:(tx + 1) * N3] = to_u8(vol[i])
    Image.fromarray(atlas, "RGBA").save(os.path.join(out_dir, "cloud_volume.png"), optimize=True)
    print("wrote", os.path.join(out_dir, "cloud_volume.png"))

    # --- Weather map ----------------------------------------------------
    layout = norm01(fbm(lambda f, s: perlin2(f, f, s), 4, 2, 211, 0.45))
    puffs = 1.0 - norm01(fbm(worley2, 7, 2, 223, 0.4))
    mr = equalise(layout * 0.5 + puffs * 0.5)
    mg = equalise(fbm(lambda f, s: perlin2(f, f, s), 3, 3, 241, 0.5))
    mb = norm01(0.6 * (1.0 - worley2(5, 257)) + 0.4 * norm01(fbm(lambda f, s: perlin2(f, f, s), 6, 2, 263)))
    streak = norm01(fbm(lambda f, s: perlin2(f * 8, f, s), 5, 3, 281, 0.55))
    img = np.stack([mr, mg, mb, streak], axis=-1)
    Image.fromarray(to_u8(img), "RGBA").save(os.path.join(out_dir, "cloud_map.png"), optimize=True)
    print("wrote", os.path.join(out_dir, "cloud_map.png"))


if __name__ == "__main__":
    main()
