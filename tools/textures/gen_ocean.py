#!/usr/bin/env python3
"""Generate the ocean's tileable procedural textures using 2D Inverse-FFT
directional JONSWAP/Phillips spectra with Tessendorf horizontal chop advection.
All content is 100% original and deterministic.

Usage: gen_ocean.py <assets/generated dir>
Writes <out>/ocean/:
  ocean_fft_chop.png  1024x1024 RGBA — mid-band JONSWAP/Tessendorf choppy wavelets:
                        R,G = steep choppy normal slope (0.5 = flat)
                        B   = normalized choppy wavelet ridge elevation (0 trough..1 peak)
                        A   = Jacobian crest fold / choppiness pinch (0 hollow..1 crest)
  water_detail.png    1024x1024 RGB — high-frequency capillary wind-chop & caustics:
                        R,G = crisp 2D-FFT capillary wind-chop normal (0.5 = flat)
                        B   = refracted shallow-water caustic filament network
  foam.png            512x512 RGB — curl-warped organic frothy foam:
                        R   = primary frothy lace erosion map
                        G   = soft organic blotch noise (break-up / warping)
                        B   = secondary finer micro-bubble lace map
Every channel tiles seamlessly.
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, map_coordinates
from scipy.spatial import cKDTree

N_FOAM = 512
N_FFT = 1024
GRAVITY = 9.81


def grid(n):
    a = (np.arange(n) + 0.5) / n
    return np.meshgrid(a, a)  # x, y in 0..1


def normalize_range(a, lo_pct=0.4, hi_pct=99.6):
    lo = np.percentile(a, lo_pct)
    hi = np.percentile(a, hi_pct)
    return np.clip((a - lo) / max(hi - lo, 1e-6), 0.0, 1.0)


def equalize(a):
    """Histogram-equalise to 0..1 so a threshold maps linearly to coverage."""
    flat = a.ravel()
    order = np.argsort(flat, kind="stable")
    out = np.empty_like(flat)
    out[order] = np.linspace(0.0, 1.0, flat.size)
    return out.reshape(a.shape)


def jonswap_phillips_fft(
    rng,
    n=N_FFT,
    tile_size=32.0,
    wind_speed=13.5,
    wind_dir=(0.82, 0.57),
    cross_dir=(-0.48, 0.88),
    cross_weight=0.34,
    k_min_cycles=2.0,
    k_max_cycles=180.0,
    small_damp=0.055,
    gamma=3.3,
    chop_lambda=0.82,
    height_scale=0.38,
):
    """Synthesize a periodic 2D inverse-FFT directional JONSWAP/Phillips ocean patch
    with Tessendorf horizontal chop advection mapped cleanly into Eulerian tile space.

    Returns (nx_u, ny_u, ridge_h, fold_mask) in 0..1.
    """
    # Integer wavevector lattice on periodic tile of side `tile_size` metres.
    freq = np.fft.fftfreq(n, d=1.0 / n)  # cycles per tile: 0..n/2-1, -n/2..-1
    kx_c, kz_c = np.meshgrid(freq, freq)
    kc = np.hypot(kx_c, kz_c)
    dk = 2.0 * np.pi / tile_size
    kx = kx_c * dk
    kz = kz_c * dk
    k = np.maximum(np.hypot(kx, kz), 1e-8)

    # Phillips + JONSWAP peak enhancement spectrum P(k).
    l_peak = (wind_speed * wind_speed) / GRAVITY
    omega = np.sqrt(GRAVITY * k)
    omega_p = np.sqrt(GRAVITY / max(l_peak * 0.32, 0.25))
    sigma = np.where(omega <= omega_p, 0.07, 0.09)
    r_jon = np.exp(-0.5 * ((omega - omega_p) / np.maximum(sigma * omega_p, 1e-6)) ** 2)
    jonswap = gamma ** r_jon

    phillips = (np.exp(-1.0 / np.maximum((k * l_peak * 0.45) ** 2, 1e-6)) / (k ** 4)) * np.exp(
        -((k * small_damp) ** 2)
    )

    # Broad directional spreading with secondary oblique crossing wind-sea lobe
    # so peaks form turbulent short-crested 3D chop rather than parallel stripes.
    wx, wz = wind_dir[0], wind_dir[1]
    wn = max(np.hypot(wx, wz), 1e-6)
    wx, wz = wx / wn, wz / wn
    cx, cz = cross_dir[0], cross_dir[1]
    cn = max(np.hypot(cx, cz), 1e-6)
    cx, cz = cx / cn, cz / cn

    khat_x = kx / k
    khat_z = kz / k
    cos_w = khat_x * wx + khat_z * wz
    cos_c = khat_x * cx + khat_z * cz
    # Forward-biased directional cone + cross-swell + isotropic short-wave chop floor.
    dir_main = (np.maximum(cos_w, 0.0) ** 2.4) + 0.16 * (np.maximum(-cos_w, 0.0) ** 2.0)
    dir_cross = (np.maximum(cos_c, 0.0) ** 2.2) + 0.14 * (np.maximum(-cos_c, 0.0) ** 2.0)
    dir_spread = 0.20 + 0.80 * (dir_main + cross_weight * dir_cross)

    # Smooth band-pass window in cycle space for crisp seamless tiling without DC drift.
    band = (
        np.clip((kc - k_min_cycles) / max(k_min_cycles * 0.75, 1.0), 0.0, 1.0)
        * np.clip((k_max_cycles - kc) / max(k_max_cycles * 0.18, 2.0), 0.0, 1.0)
    )
    band = band * band * (3.0 - 2.0 * band)
    band[0, 0] = 0.0

    spectrum = phillips * jonswap * dir_spread * band

    # Random Gaussian complex Fourier amplitudes; real part of IFFT gives exact
    # periodic real wave field without needing explicit conjugate bookkeeping.
    xi = (rng.standard_normal((n, n)) + 1j * rng.standard_normal((n, n))) * (1.0 / np.sqrt(2.0))
    h_hat = xi * np.sqrt(np.maximum(spectrum, 0.0))

    # Height field normalized to target physical RMS amplitude (metres).
    h_raw = np.fft.ifft2(h_hat).real
    rms = max(float(np.std(h_raw)), 1e-8)
    scale = height_scale / rms
    h_hat = h_hat * scale
    h = h_raw * scale

    # Exact spectral height gradient (dh/dx, dh/dz) and Tessendorf horizontal chop D = IFFT(-i * (k/|k|) * h_hat).
    dh_dx = np.fft.ifft2(1j * kx * h_hat).real
    dh_dz = np.fft.ifft2(1j * kz * h_hat).real
    disp_x = np.fft.ifft2((-1j * khat_x) * h_hat).real
    disp_z = np.fft.ifft2((-1j * khat_z) * h_hat).real

    # Spatial derivatives of D for exact surface Jacobian J = det(I + lambda * dD/dx).
    dDx_dx = np.fft.ifft2((khat_x * kx) * h_hat).real
    dDz_dz = np.fft.ifft2((khat_z * kz) * h_hat).real
    dDx_dz = np.fft.ifft2((khat_x * kz) * h_hat).real

    # Auto-clamp chop_lambda so min(J) stays safely positive (pinched sharp crests, zero self-overlap).
    j_try = (1.0 + chop_lambda * dDx_dx) * (1.0 + chop_lambda * dDz_dz) - (chop_lambda * dDx_dz) ** 2
    j_p05 = float(np.percentile(j_try, 0.2))
    eff_lambda = chop_lambda
    if j_p05 < 0.14:
        # Scale lambda down linearly until the steepest 0.2% crests pinch cleanly to J ~= 0.16.
        for _ in range(8):
            eff_lambda *= 0.86
            j_try = (1.0 + eff_lambda * dDx_dx) * (1.0 + eff_lambda * dDz_dz) - (eff_lambda * dDx_dz) ** 2
            if float(np.percentile(j_try, 0.2)) >= 0.14:
                break

    jxx = 1.0 + eff_lambda * dDx_dx
    jzz = 1.0 + eff_lambda * dDz_dz
    jxz = eff_lambda * dDx_dz
    jac = jxx * jzz - jxz * jxz

    # Exact choppy tangent-plane surface normal on the displaced surface:
    # Tx = (jxx, dh_dx, jxz), Tz = (jxz, dh_dz, jzz) -> N = normalize(Tz x Tx).
    nx_r = dh_dz * jxz - dh_dx * jzz
    ny_r = jxx * jzz - jxz * jxz
    nz_r = dh_dx * jxz - dh_dz * jxx
    ny_safe = np.maximum(ny_r, 0.12)
    slope_x = nx_r / ny_safe
    slope_z = nz_r / ny_safe

    # Invert horizontal Tessendorf displacement x' = x + eff_lambda * D(x) into Eulerian
    # tile coordinates using 5 periodic fixed-point iterations so crests become physically
    # sharp pinched pyramids and troughs become broad smooth hollows!
    iy, ix = np.indices((n, n), dtype=np.float64)
    px_per_m = n / tile_size
    dx_px = eff_lambda * disp_x * px_per_m
    dz_px = eff_lambda * disp_z * px_per_m

    rx = ix.copy()
    rz = iy.copy()
    for _ in range(5):
        coords = np.array([rz % n, rx % n])
        ox = map_coordinates(dx_px, coords, order=1, mode="wrap")
        oz = map_coordinates(dz_px, coords, order=1, mode="wrap")
        rx = ix - ox
        rz = iy - oz

    final_coords = np.array([rz % n, rx % n])
    h_chop = map_coordinates(h, final_coords, order=1, mode="wrap")
    sx_chop = map_coordinates(slope_x, final_coords, order=1, mode="wrap")
    sz_chop = map_coordinates(slope_z, final_coords, order=1, mode="wrap")
    j_chop = map_coordinates(jac, final_coords, order=1, mode="wrap")

    # Encode steep choppy slope cleanly into 0..1 (0.5 = flat) preserving full dynamic contrast.
    slope_mag = np.hypot(sx_chop, sz_chop)
    sc = 0.88 / max(float(np.percentile(slope_mag, 98.5)), 1e-6)
    nx_u = np.clip(sx_chop * sc, -1.0, 1.0) * 0.5 + 0.5
    ny_u = np.clip(sz_chop * sc, -1.0, 1.0) * 0.5 + 0.5

    # Normalized choppy ridge height (0 = deep hollow trough, 1 = pinched choppy crest).
    ridge_h = normalize_range(h_chop, 0.8, 99.2)

    # Jacobian crest fold intensity (0 = broad trough, 1 = sharply pinched breaking ridge).
    fold_raw = np.clip((1.02 - j_chop) / 0.86, 0.0, 1.0)
    # Weight gently by upper crest elevation so fold peaks strictly highlight choppy ridges.
    fold_mask = np.clip(fold_raw * (0.45 + 0.55 * np.clip((ridge_h - 0.35) / 0.55, 0.0, 1.0)), 0.0, 1.0)
    fold_mask = normalize_range(fold_mask, 2.0, 99.5) ** 1.15
    # Keep alpha >= 0.02 so Godot's default fix_alpha_border never smears trough R,G,B normals/height.
    fold_alpha = 0.02 + 0.98 * fold_mask
    return nx_u, ny_u, ridge_h, fold_alpha


def periodic_waves(rng, n_waves, kmin, kmax, falloff, n):
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
    s = max(float(h.std()), 1e-8)
    return h / s, gx / s, gy / s


def directional_waves(rng, n_waves, kmin, kmax, falloff, n, prefer_angles=None):
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
    s = max(float(h.std()), 1e-8)
    return h / s, gx / s, gy / s


def caustics(rng, n=N_FFT):
    """Light focused by a wavy surface: splat refracted rays into a periodic 1024x1024 grid."""
    ss = 2  # 2048x2048 rays -> crisp 1024x1024 refracted caustic network
    nr = n * ss
    # Synthesize smooth multi-band wave slope cleanly via 2D FFT for fast 2048x2048 ray splatting.
    freq = np.fft.fftfreq(nr, d=1.0 / nr)
    kx_c, ky_c = np.meshgrid(freq, freq)
    kc = np.hypot(kx_c, ky_c)
    band = np.where((kc >= 2.0) & (kc <= 20.0), (np.maximum(kc, 1.0) ** -1.95), 0.0)
    band[0, 0] = 0.0
    xi = (rng.standard_normal((nr, nr)) + 1j * rng.standard_normal((nr, nr))) * (1.0 / np.sqrt(2.0))
    h_hat = xi * np.sqrt(band)
    gx = np.fft.ifft2(1j * 2.0 * np.pi * kx_c * h_hat).real
    gy = np.fft.ifft2(1j * 2.0 * np.pi * ky_c * h_hat).real
    s = max(float(np.hypot(gx, gy).std()), 1e-8)
    gx /= s
    gy /= s

    x, y = grid(nr)
    depth = 0.0112  # focal strength; tuned for crisp shimmering shallow-water filaments
    px = (x + depth * gx) % 1.0
    py = (y + depth * gy) % 1.0
    hist, _, _ = np.histogram2d(py.ravel(), px.ravel(), bins=n, range=[[0, 1], [0, 1]])
    hist = gaussian_filter(hist / (ss * ss), 1.15, mode="wrap")
    c = np.clip((hist - 0.50) / 2.85, 0.0, 1.0) ** 0.78
    return c


def worley_edges(rng, cells, warp=None, n=N_FOAM):
    """Distance-to-cell-wall map (F2 - F1) of a periodic Voronoi pattern."""
    count = cells * cells
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


def foam(rng, n=N_FOAM):
    # Strong multi-octave divergence-free (curl) turbulent domain warp (0.065..0.11)
    # so zero straight geometric Voronoi borders can ever survive.
    _, wx1, wy1 = periodic_waves(rng, 26, 1, 4, 1.05, n)
    _, wx2, wy2 = periodic_waves(rng, 34, 4, 10, 1.15, n)
    _, wx3, wy3 = periodic_waves(rng, 38, 10, 22, 1.25, n)
    cx_lo = wy1 / max(float(np.percentile(np.abs(wy1), 99.0)), 1e-6)
    cy_lo = -wx1 / max(float(np.percentile(np.abs(wx1), 99.0)), 1e-6)
    cx_mid = wy2 / max(float(np.percentile(np.abs(wy2), 99.0)), 1e-6)
    cy_mid = -wx2 / max(float(np.percentile(np.abs(wx2), 99.0)), 1e-6)
    cx_hi = wy3 / max(float(np.percentile(np.abs(wy3), 99.0)), 1e-6)
    cy_hi = -wx3 / max(float(np.percentile(np.abs(wx3), 99.0)), 1e-6)

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

    b1, _, _ = periodic_waves(rng, 36, 1, 5, 1.10, n)
    b2, _, _ = periodic_waves(rng, 44, 5, 14, 1.20, n)
    b3, _, _ = periodic_waves(rng, 40, 14, 30, 1.30, n)
    blotch = equalize(gaussian_filter(b1 + 0.42 * b2 + 0.16 * b3, 1.4, mode="wrap"))

    streak_h, _, _ = directional_waves(rng, 44, 3, 14, 1.05, n, prefer_angles=(0.45,))
    streak_n = normalize_range(gaussian_filter(streak_h, 1.2, mode="wrap"))

    e_14, f1_14 = worley_edges(rng, 14, warp_big, n)
    e_32, _ = worley_edges(rng, 32, warp_mid, n)
    e_68, _ = worley_edges(rng, 68, warp_fine, n)
    w_14 = np.clip(e_14 * 1.55, 0.0, 1.0) ** 0.78
    w_32 = np.clip(e_32 * 1.45, 0.0, 1.0) ** 0.82
    w_68 = np.clip(e_68 * 1.35, 0.0, 1.0) ** 0.86
    breakup = 0.22 * (blotch - 0.5) + 0.18 * (streak_n - 0.5) + 0.10 * np.clip(f1_14, 0.0, 1.0)
    lace = np.minimum(w_14 * 0.85 + 0.15 * w_32, 0.18 + 0.82 * w_32)
    lace = np.minimum(lace, 0.40 + 0.60 * w_68)
    lace = gaussian_filter(lace + breakup, 0.65, mode="wrap")
    lace = normalize_range(lace) ** 0.88

    e2_a, _ = worley_edges(rng, 28, warp_mid, n)
    e2_b, _ = worley_edges(rng, 60, warp_fine, n)
    e2_c, _ = worley_edges(rng, 110, (0.014 * cx_mid, 0.014 * cy_mid), n)
    f_a = np.clip(e2_a * 1.50, 0.0, 1.0) ** 0.80
    f_b = np.clip(e2_b * 1.40, 0.0, 1.0) ** 0.85
    f_c = np.clip(e2_c * 1.30, 0.0, 1.0) ** 0.90
    lace2 = np.minimum(f_a, 0.22 + 0.78 * f_b)
    lace2 = np.minimum(lace2, 0.45 + 0.55 * f_c)
    lace2 = gaussian_filter(lace2 + 0.14 * (blotch - 0.5), 0.55, mode="wrap")
    lace2 = normalize_range(lace2) ** 0.90
    return lace, blotch, lace2


def save_rgb(path, *channels):
    arr = np.stack([np.clip(c * 255.0 + 0.5, 0, 255).astype(np.uint8) for c in channels], -1)
    Image.fromarray(arr, "RGB").save(path, optimize=True)
    print(f"  wrote {path} ({arr.shape[1]}x{arr.shape[0]} RGB)")


def save_rgba(path, *channels):
    arr = np.stack([np.clip(c * 255.0 + 0.5, 0, 255).astype(np.uint8) for c in channels], -1)
    Image.fromarray(arr, "RGBA").save(path, optimize=True)
    print(f"  wrote {path} ({arr.shape[1]}x{arr.shape[0]} RGBA)")


def main():
    out = os.path.join(sys.argv[-1], "ocean")
    os.makedirs(out, exist_ok=True)
    rng = np.random.default_rng(0x0CEA25)

    # 1. 1024x1024 RGBA mid-band JONSWAP/Phillips + Tessendorf choppy wavelets
    #    (sharp pinched peaks, wide smooth hollows, zero parallel sine bands).
    c_nx, c_ny, c_h, c_fold = jonswap_phillips_fft(
        rng,
        n=N_FFT,
        tile_size=32.0,
        wind_speed=14.0,
        wind_dir=(0.84, 0.54),
        cross_dir=(-0.56, 0.83),
        cross_weight=0.42,
        k_min_cycles=2.0,
        k_max_cycles=145.0,
        small_damp=0.065,
        gamma=3.3,
        chop_lambda=0.92,
        height_scale=0.40,
    )
    save_rgba(os.path.join(out, "ocean_fft_chop.png"), c_nx, c_ny, c_h, c_fold)

    # 2. 1024x1024 RGB high-frequency 2D-FFT capillary wind-chop normal (R,G) + caustics (B).
    d_nx, d_ny, _, _ = jonswap_phillips_fft(
        rng,
        n=N_FFT,
        tile_size=8.0,
        wind_speed=8.5,
        wind_dir=(0.62, -0.78),
        cross_dir=(0.86, 0.51),
        cross_weight=0.52,
        k_min_cycles=4.0,
        k_max_cycles=240.0,
        small_damp=0.012,
        gamma=2.4,
        chop_lambda=0.68,
        height_scale=0.095,
    )
    caus = caustics(rng, N_FFT)
    save_rgb(os.path.join(out, "water_detail.png"), d_nx, d_ny, caus)

    # 3. 512x512 RGB curl-warped organic frothy foam maps.
    save_rgb(os.path.join(out, "foam.png"), *foam(rng, N_FOAM))


if __name__ == "__main__":
    main()
