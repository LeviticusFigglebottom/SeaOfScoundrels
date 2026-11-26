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


def directional_waves(rng, n_waves, kmin, kmax, falloff, n=N, prefer_angles=None):
    """Sum of periodic sinusoids with optional directional wave-train bias."""
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
        dir_w = 1.0
        if prefer_angles is not None:
            ang = np.arctan2(ky, kx)
            best = max(abs(np.cos(ang - a)) for a in prefer_angles)
            dir_w = 0.45 + 0.55 * (best ** 2)
        amp = (m ** -falloff) * dir_w
        ph = rng.uniform(0, 2 * np.pi)
        th = 2 * np.pi * (kx * x + ky * y) + ph
        h += amp * np.sin(th)
        gx += amp * 2 * np.pi * kx * np.cos(th)
        gy += amp * 2 * np.pi * ky * np.cos(th)
    s = h.std()
    return h / s, gx / s, gy / s


def ripple_normal(rng):
    # Three-band wind chop with subtle crossing wave-train bias and trochoidal
    # crest sharpening so wavelets have sculpted ridges and crisp glint facets.
    angles = (0.35, -0.75)
    h1, gx1, gy1 = directional_waves(rng, 38, 2, 8, 0.95, prefer_angles=angles)
    h2, gx2, gy2 = directional_waves(rng, 52, 8, 20, 1.15, prefer_angles=angles)
    h3, gx3, gy3 = directional_waves(rng, 64, 20, 44, 1.35)
    h = h1 + 0.42 * h2 + 0.16 * h3
    h_norm = h / max(h.std(), 1e-6)
    # Sharpen crests and widen troughs (periodic, smooth, zero discontinuities).
    sharp = np.clip(1.0 + 0.30 * np.tanh(h_norm * 0.9), 0.55, 1.60)
    gx = (gx1 + 0.36 * gx2 + 0.18 * gx3) * sharp
    gy = (gy1 + 0.36 * gy2 + 0.18 * gy3) * sharp
    # Texture-space slope -> normal. Scale picked so slopes use the 8-bit range well.
    sc = 0.52 / np.percentile(np.hypot(gx, gy), 99.4)
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
    depth = 0.0108  # focal strength; tuned for crisp bright filaments
    px = (x + depth * gx / (2 * np.pi)) % 1.0
    py = (y + depth * gy / (2 * np.pi)) % 1.0
    hist, _, _ = np.histogram2d(py.ravel(), px.ravel(), bins=N, range=[[0, 1], [0, 1]])
    hist = gaussian_filter(hist / (ss * ss), 0.75, mode="wrap")
    c = np.clip((hist - 0.52) / 3.0, 0, 1) ** 0.78
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


def normalize_range(a, lo_pct=0.4, hi_pct=99.6):
    lo = np.percentile(a, lo_pct)
    hi = np.percentile(a, hi_pct)
    return np.clip((a - lo) / max(hi - lo, 1e-6), 0.0, 1.0)


def foam(rng):
    # Divergence-free (curl) warp so foam webbing flows and curves like painted strokes.
    _, wx, wy = periodic_waves(rng, 28, 1, 5, 1.05)
    curl_x = wy / max(np.abs(wy).max(), 1e-6)
    curl_y = -wx / max(np.abs(wx).max(), 1e-6)
    warp_big = (0.018 * curl_x, 0.018 * curl_y)
    warp_mid = (0.011 * curl_x, 0.011 * curl_y)

    # Soft multi-octave organic blotch noise for domain warping & foam modulation.
    b1, _, _ = periodic_waves(rng, 36, 1, 5, 1.15)
    b2, _, _ = periodic_waves(rng, 40, 5, 13, 1.25)
    blotch = equalize(gaussian_filter(b1 + 0.35 * b2, 1.8, mode="wrap"))

    # Primary foam webbing (R): nested Voronoi filaments. Low values are crisp
    # bubble walls so even light fair-weather coverage traces delicate lacy webbing.
    e_big, _ = worley_edges(rng, 6, warp_big)
    e_mid, _ = worley_edges(rng, 15, warp_mid)
    e_small, _ = worley_edges(rng, 35)
    w_big = np.clip(e_big * 1.45, 0.0, 1.0) ** 0.72
    w_mid = np.clip(e_mid * 1.35, 0.0, 1.0) ** 0.78
    w_small = np.clip(e_small * 1.25, 0.0, 1.0) ** 0.85
    lace = np.minimum(w_big, 0.24 + 0.76 * w_mid)
    lace = np.minimum(lace, 0.48 + 0.52 * w_small)
    lace = gaussian_filter(lace + 0.06 * (blotch - 0.5), 0.55, mode="wrap")
    lace = normalize_range(lace) ** 0.86

    # Secondary fine bubble webbing (B): denser frothy lace inside breaking crests & surf.
    e2a, _ = worley_edges(rng, 17, warp_mid)
    e2b, _ = worley_edges(rng, 39)
    e2c, _ = worley_edges(rng, 75)
    f_a = np.clip(e2a * 1.40, 0.0, 1.0) ** 0.74
    f_b = np.clip(e2b * 1.30, 0.0, 1.0) ** 0.82
    f_c = np.clip(e2c * 1.25, 0.0, 1.0) ** 0.88
    lace2 = np.minimum(f_a, 0.26 + 0.74 * f_b)
    lace2 = np.minimum(lace2, 0.52 + 0.48 * f_c)
    lace2 = gaussian_filter(lace2, 0.50, mode="wrap")
    lace2 = normalize_range(lace2) ** 0.88
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
