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
    # Three-band wind chop with crossing wave-train bias and sharp trochoidal
    # ridges so near water has glossy, sculpted micro-facets and crisp glints.
    angles = (0.35, -0.75)
    h1, gx1, gy1 = directional_waves(rng, 40, 2, 8, 0.90, prefer_angles=angles)
    h2, gx2, gy2 = directional_waves(rng, 56, 8, 22, 1.08, prefer_angles=angles)
    h3, gx3, gy3 = directional_waves(rng, 72, 22, 52, 1.25)
    h = h1 + 0.48 * h2 + 0.22 * h3
    h_norm = h / max(h.std(), 1e-6)
    # Sharpen crests and widen troughs (periodic, smooth, zero discontinuities).
    sharp = np.clip(1.0 + 0.42 * np.tanh(h_norm * 1.05), 0.48, 1.78)
    gx = (gx1 + 0.44 * gx2 + 0.24 * gx3) * sharp
    gy = (gy1 + 0.44 * gy2 + 0.24 * gy3) * sharp
    # Texture-space slope -> normal with strong contrast for lively micro-facets.
    sc = 0.85 / np.percentile(np.hypot(gx, gy), 97.5)
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
    # Jittered grid points: organic irregular cluster sizes.
    gx, gy = np.meshgrid(np.arange(cells), np.arange(cells))
    pts = np.stack([gx.ravel(), gy.ravel()], 1) + rng.uniform(0.03, 0.97, (count, 2))
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
    # Strong multi-octave divergence-free (curl) turbulent domain warp (0.065..0.11)
    # so zero straight geometric Voronoi borders can ever survive.
    _, wx1, wy1 = periodic_waves(rng, 26, 1, 4, 1.05)
    _, wx2, wy2 = periodic_waves(rng, 34, 4, 10, 1.15)
    _, wx3, wy3 = periodic_waves(rng, 38, 10, 22, 1.25)
    cx_lo = wy1 / max(np.percentile(np.abs(wy1), 99.0), 1e-6)
    cy_lo = -wx1 / max(np.percentile(np.abs(wx1), 99.0), 1e-6)
    cx_mid = wy2 / max(np.percentile(np.abs(wy2), 99.0), 1e-6)
    cy_mid = -wx2 / max(np.percentile(np.abs(wx2), 99.0), 1e-6)
    cx_hi = wy3 / max(np.percentile(np.abs(wy3), 99.0), 1e-6)
    cy_hi = -wx3 / max(np.percentile(np.abs(wx3), 99.0), 1e-6)

    warp_big = (
        0.072 * cx_lo + 0.026 * cx_mid + 0.008 * cx_hi,
        0.072 * cy_lo + 0.026 * cy_mid + 0.008 * cy_hi,
    )
    warp_mid = (
        0.054 * cx_lo + 0.024 * cx_mid + 0.009 * cx_hi,
        0.054 * cy_lo + 0.024 * cy_mid + 0.009 * cy_hi,
    )
    warp_fine = (
        0.032 * cx_lo + 0.018 * cx_mid + 0.008 * cx_hi,
        0.032 * cy_lo + 0.018 * cy_mid + 0.008 * cy_hi,
    )

    # Soft multi-octave organic blotch noise (G) for domain warping & frothy clustering.
    b1, _, _ = periodic_waves(rng, 36, 1, 5, 1.10)
    b2, _, _ = periodic_waves(rng, 44, 5, 14, 1.20)
    b3, _, _ = periodic_waves(rng, 40, 14, 30, 1.30)
    blotch = equalize(gaussian_filter(b1 + 0.42 * b2 + 0.16 * b3, 1.4, mode="wrap"))

    # Organic frothy ribbon noise so foam gathers in streaky painterly patches
    # rather than uniform webs.
    streak_h, _, _ = directional_waves(rng, 44, 3, 14, 1.05, prefer_angles=(0.45,))
    streak_n = normalize_range(gaussian_filter(streak_h, 1.2, mode="wrap"))

    # Primary organic foam lace erosion map (R): high-density 14 / 32 / 68 bubble
    # clusters under strong turbulent curl warp, broken up by blotch & frothy streaks.
    e_14, f1_14 = worley_edges(rng, 14, warp_big)
    e_32, _ = worley_edges(rng, 32, warp_mid)
    e_68, _ = worley_edges(rng, 68, warp_fine)
    w_14 = np.clip(e_14 * 1.55, 0.0, 1.0) ** 0.78
    w_32 = np.clip(e_32 * 1.45, 0.0, 1.0) ** 0.82
    w_68 = np.clip(e_68 * 1.35, 0.0, 1.0) ** 0.86
    # Modulate cluster wall thickness organically with blotch + streaks so thin
    # filaments taper and break naturally instead of forming closed polygonal loops.
    breakup = 0.22 * (blotch - 0.5) + 0.18 * (streak_n - 0.5) + 0.10 * np.clip(f1_14, 0.0, 1.0)
    lace = np.minimum(w_14 * 0.85 + 0.15 * w_32, 0.18 + 0.82 * w_32)
    lace = np.minimum(lace, 0.40 + 0.60 * w_68)
    lace = gaussian_filter(lace + breakup, 0.65, mode="wrap")
    lace = normalize_range(lace) ** 0.88

    # Secondary fine frothy micro-bubble lace (B): dense curled clusters (28 / 60 / 110)
    # for breaking crests, surf, and high-frequency spray droplet breakup.
    e2_a, _ = worley_edges(rng, 28, warp_mid)
    e2_b, _ = worley_edges(rng, 60, warp_fine)
    e2_c, _ = worley_edges(rng, 110, (0.014 * cx_mid, 0.014 * cy_mid))
    f_a = np.clip(e2_a * 1.50, 0.0, 1.0) ** 0.80
    f_b = np.clip(e2_b * 1.40, 0.0, 1.0) ** 0.85
    f_c = np.clip(e2_c * 1.30, 0.0, 1.0) ** 0.90
    lace2 = np.minimum(f_a, 0.22 + 0.78 * f_b)
    lace2 = np.minimum(lace2, 0.45 + 0.55 * f_c)
    lace2 = gaussian_filter(lace2 + 0.14 * (blotch - 0.5), 0.55, mode="wrap")
    lace2 = normalize_range(lace2) ** 0.90
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
