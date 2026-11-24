#!/usr/bin/env python3
"""Generate the ocean's tileable helper textures. All content is procedural.

Usage: gen_ocean.py <assets/generated dir>
Writes <out>/ocean/:
  water_detail.png  R,G = ripple normal xy (0.5 = flat), B = caustic light pattern
  foam.png          R = foam "lace" erosion map (low on bubble walls, high in the
                        holes, so `amount > R` grows from thin lace to solid foam)
                    G = soft blotch noise (break-up / warping)
                    B = a second, unrelated and finer lace map
Every channel tiles seamlessly.
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter
from scipy.spatial import cKDTree

N = 512


def grid(n=N):
    a = (np.arange(n) + 0.5) / n
    return np.meshgrid(a, a)  # x, y in 0..1


def periodic_waves(rng, n_waves, kmin, kmax, falloff, n=N):
    """Sum of sinusoids with integer wave vectors: tileable height + gradient."""
    x, y = grid(n)
    h = np.zeros((n, n))
    gx = np.zeros((n, n))
    gy = np.zeros((n, n))
    for _ in range(n_waves):
        while True:
            kx, ky = rng.integers(-kmax, kmax + 1, size=2)
            m = np.hypot(kx, ky)
            if kmin <= m <= kmax:
                break
        amp = m ** -falloff
        ph = rng.uniform(0, 2 * np.pi)
        th = 2 * np.pi * (kx * x + ky * y) + ph
        h += amp * np.sin(th)
        gx += amp * 2 * np.pi * kx * np.cos(th)
        gy += amp * 2 * np.pi * ky * np.cos(th)
    s = h.std()
    return h / s, gx / s, gy / s


def equalize(a):
    """Histogram-equalise to 0..1 so a threshold maps linearly to coverage."""
    flat = a.ravel()
    order = np.argsort(flat, kind="stable")
    out = np.empty_like(flat)
    out[order] = np.linspace(0.0, 1.0, flat.size)
    return out.reshape(a.shape)


def ripple_normal(rng):
    # Wind chop: mid and high frequencies, slightly sharpened crests.
    h1, gx1, gy1 = periodic_waves(rng, 40, 2, 9, 1.0)
    h2, gx2, gy2 = periodic_waves(rng, 48, 8, 22, 1.3)
    gx = gx1 + 0.30 * gx2
    gy = gy1 + 0.30 * gy2
    # Texture-space slope -> normal. Scale picked so slopes use the 8-bit range well.
    sc = 0.5 / np.percentile(np.hypot(gx, gy), 99.5)
    nx = np.clip(-gx * sc, -1, 1)
    ny = np.clip(-gy * sc, -1, 1)
    return nx * 0.5 + 0.5, ny * 0.5 + 0.5


def caustics(rng):
    """Light focused by a wavy surface: splat refracted rays into a periodic grid."""
    ss = 3  # rays per texel per axis
    n = N * ss
    _, gx, gy = periodic_waves(rng, 40, 2, 7, 1.0, n)
    _, gx2, gy2 = periodic_waves(rng, 40, 6, 16, 1.2, n)
    gx = gx + 0.35 * gx2
    gy = gy + 0.35 * gy2
    x, y = grid(n)
    depth = 0.0105  # focal strength; tuned for thin bright filaments
    px = (x + depth * gx / (2 * np.pi)) % 1.0
    py = (y + depth * gy / (2 * np.pi)) % 1.0
    hist, _, _ = np.histogram2d(py.ravel(), px.ravel(), bins=N, range=[[0, 1], [0, 1]])
    hist = gaussian_filter(hist / (ss * ss), 0.8, mode="wrap")
    c = np.clip((hist - 0.55) / 3.2, 0, 1) ** 0.8
    return c


def worley_edges(rng, cells, warp=None, n=N):
    """Distance-to-cell-wall map (F2 - F1) of a periodic Voronoi pattern."""
    count = cells * cells
    # Jittered grid points: even bubble sizes, organic placement.
    gx, gy = np.meshgrid(np.arange(cells), np.arange(cells))
    pts = np.stack([gx.ravel(), gy.ravel()], 1) + rng.uniform(0.08, 0.92, (count, 2))
    pts = (pts / cells) % 1.0
    tree = cKDTree(pts, boxsize=1.0)
    x, y = grid(n)
    if warp is not None:
        x = (x + warp[0]) % 1.0
        y = (y + warp[1]) % 1.0
    d, _ = tree.query(np.stack([x.ravel(), y.ravel()], 1), k=2)
    f1 = d[:, 0].reshape(n, n) * cells
    f2 = d[:, 1].reshape(n, n) * cells
    return f2 - f1, f1


def foam(rng):
    # Low-frequency warp so the bubble walls wander like brush strokes.
    _, wx, wy = periodic_waves(rng, 24, 1, 5, 1.0)
    warp = (0.012 * wx / np.abs(wx).max(), 0.012 * wy / np.abs(wy).max())
    e_big, f_big = worley_edges(rng, 7, warp)
    e_mid, _ = worley_edges(rng, 17, warp)
    e_small, _ = worley_edges(rng, 41)
    blotch, _, _ = periodic_waves(rng, 40, 1, 6, 1.2)
    blotch = equalize(gaussian_filter(blotch, 2.0, mode="wrap"))
    # Lace: walls of big bubbles survive longest, holes fill with smaller bubbles.
    lace = 0.55 * np.clip(e_big, 0, 1) + 0.30 * np.clip(e_mid, 0, 1) + 0.15 * np.clip(e_small, 0, 1)
    lace = equalize(gaussian_filter(lace + 0.10 * (blotch - 0.5), 0.7, mode="wrap"))
    e2a, _ = worley_edges(rng, 23, warp)
    e2b, _ = worley_edges(rng, 53)
    lace2 = equalize(gaussian_filter(0.65 * np.clip(e2a, 0, 1) + 0.35 * np.clip(e2b, 0, 1), 0.6, mode="wrap"))
    return lace, blotch, lace2


def save(path, *channels):
    arr = np.stack([np.clip(c * 255.0 + 0.5, 0, 255).astype(np.uint8) for c in channels], -1)
    Image.fromarray(arr, "RGB").save(path, optimize=True)
    print("  wrote", path)


def main():
    out = os.path.join(sys.argv[-1], "ocean")
    os.makedirs(out, exist_ok=True)
    rng = np.random.default_rng(0x0CEA2)
    nx, ny = ripple_normal(rng)
    save(os.path.join(out, "water_detail.png"), nx, ny, caustics(rng))
    save(os.path.join(out, "foam.png"), *foam(rng))


if __name__ == "__main__":
    main()
