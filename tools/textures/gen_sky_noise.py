#!/usr/bin/env python3
"""Generate the tileable noise texture used by the sky shader's clouds.

Usage: gen_sky_noise.py <assets/generated dir>
Writes <out>/sky/cloud_noise.png (512x512 RGBA, seamless):
  R  chunky cumulus shapes (Perlin fbm sculpted by inverted Worley), histogram-equalised
     so a threshold t in the shader gives roughly (1 - t) coverage
  G  billowy detail (inverted Worley fbm, higher frequency)
  B  soft wisps (ridged Perlin fbm) for cirrus streaks
  A  plain Perlin fbm (warping, moon surface blotches)
Everything is computed here from seeded random numbers; no external data.
"""
import os
import sys

import numpy as np
from PIL import Image

SIZE = 512


def perlin(freq: int, seed: int) -> np.ndarray:
    """Seamless 2D gradient noise with `freq` lattice cells per tile, roughly -1..1."""
    rng = np.random.default_rng(seed)
    ang = rng.uniform(0.0, 2.0 * np.pi, (freq, freq))
    gx, gy = np.cos(ang), np.sin(ang)
    lin = np.arange(SIZE) / SIZE * freq
    x, y = np.meshgrid(lin, lin)
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = x - x0, y - y0

    def corner(ix, iy, dx, dy):
        return gx[iy % freq, ix % freq] * dx + gy[iy % freq, ix % freq] * dy

    def fade(t):
        return t * t * t * (t * (t * 6 - 15) + 10)

    u, v = fade(fx), fade(fy)
    n00 = corner(x0, y0, fx, fy)
    n10 = corner(x0 + 1, y0, fx - 1, fy)
    n01 = corner(x0, y0 + 1, fx, fy - 1)
    n11 = corner(x0 + 1, y0 + 1, fx - 1, fy - 1)
    return (n00 * (1 - u) + n10 * u) * (1 - v) + (n01 * (1 - u) + n11 * u) * v * 1.0


def worley(freq: int, seed: int) -> np.ndarray:
    """Seamless F1 cellular noise, 0 at feature points, about 1 at cell borders."""
    rng = np.random.default_rng(seed)
    pts = rng.uniform(0.0, 1.0, (freq, freq, 2))
    lin = np.arange(SIZE) / SIZE * freq
    x, y = np.meshgrid(lin, lin)
    cx, cy = np.floor(x).astype(int), np.floor(y).astype(int)
    best = np.full((SIZE, SIZE), 9.0)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            nx, ny = cx + ox, cy + oy
            p = pts[ny % freq, nx % freq]
            dx = nx + p[..., 0] - x
            dy = ny + p[..., 1] - y
            best = np.minimum(best, np.sqrt(dx * dx + dy * dy))
    return np.clip(best, 0.0, 1.0)


def fbm(fn, freq: int, octaves: int, seed: int, gain: float = 0.5) -> np.ndarray:
    total = np.zeros((SIZE, SIZE))
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        total += amp * fn(freq * 2 ** o, seed + o * 17)
        norm += amp
        amp *= gain
    return total / norm


def norm01(a: np.ndarray) -> np.ndarray:
    lo, hi = np.percentile(a, 0.5), np.percentile(a, 99.5)
    return np.clip((a - lo) / (hi - lo), 0.0, 1.0)


def equalise(a: np.ndarray) -> np.ndarray:
    """Map values to their rank so the histogram is flat."""
    flat = a.ravel()
    order = np.argsort(flat, kind="stable")
    ranks = np.empty_like(order)
    ranks[order] = np.arange(flat.size)
    return (ranks / (flat.size - 1)).reshape(a.shape)


def main() -> None:
    out_root = sys.argv[1] if len(sys.argv) > 1 else "assets/generated"
    out_dir = os.path.join(out_root, "sky")
    os.makedirs(out_dir, exist_ok=True)

    # Few octaves on purpose: round, chunky masses rather than ragged ones.
    p_shape = norm01(fbm(perlin, 3, 2, 11, 0.4))
    w_puff = 1.0 - norm01(fbm(worley, 5, 2, 23, 0.4))
    # Perlin lays out where clouds are; Worley carves them into rounded puffs.
    r = equalise(p_shape * 0.62 + w_puff * 0.38)
    g = norm01(1.0 - fbm(worley, 7, 2, 37, 0.45))
    ridged = 1.0 - np.abs(fbm(perlin, 5, 5, 53))
    b = norm01(ridged ** 2.0)
    a = norm01(fbm(perlin, 4, 5, 71))

    img = np.stack([r, g, b, a], axis=-1)
    Image.fromarray((img * 255.0 + 0.5).astype(np.uint8), "RGBA").save(
        os.path.join(out_dir, "cloud_noise.png"), optimize=True)
    print("wrote", os.path.join(out_dir, "cloud_noise.png"))


if __name__ == "__main__":
    main()
