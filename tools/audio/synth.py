"""Sea of Scoundrels synthesis toolkit.

Everything the game plays is computed here from maths: no samples, no soundfonts.
Shared by the tools/audio/gen_*.py generators and by analyze.py.

Conventions
- Sample rate SR = 44100. Mono signals are 1-D float arrays, stereo are (n, 2).
- Every random choice takes an explicit numpy Generator; use seed_rng(name) so
  output is deterministic per sound name.
- Times are seconds, frequencies Hz, levels dB unless a name says otherwise.
"""
from __future__ import annotations

import json
import os
import subprocess
import tempfile
import zlib

import numpy as np
from scipy import signal
from scipy.io import wavfile
from scipy.ndimage import convolve1d, maximum_filter1d

SR = 44100
TAU = 2.0 * np.pi


# ----------------------------------------------------------------------------
# Basics
# ----------------------------------------------------------------------------
def seed_rng(name: str, salt: int = 0) -> np.random.Generator:
	return np.random.default_rng((zlib.crc32(name.encode()) + salt * 7919) & 0xFFFFFFFF)


def db(x: float) -> float:
	"""dB to linear amplitude."""
	return 10.0 ** (x / 20.0)


def to_db(x) -> float:
	return 20.0 * np.log10(np.maximum(np.abs(x), 1e-12))


def sec(t: float) -> int:
	return int(round(t * SR))


def tgrid(n: int) -> np.ndarray:
	return np.arange(n) / SR


def midi_hz(m) -> float:
	return 440.0 * 2.0 ** ((np.asarray(m, dtype=float) - 69.0) / 12.0)


_NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def note_midi(name: str) -> int:
	"""'F#5' -> 78, 'Bb3' -> 58. Middle C is C4 = 60."""
	n = _NOTE[name[0].upper()]
	i = 1
	while i < len(name) and name[i] in "#b":
		n += 1 if name[i] == "#" else -1
		i += 1
	return 12 * (int(name[i:]) + 1) + n


def as_array(f, n: int) -> np.ndarray:
	f = np.asarray(f, dtype=float)
	if f.ndim == 0:
		return np.full(n, float(f))
	if len(f) != n:
		return np.interp(np.linspace(0, 1, n), np.linspace(0, 1, len(f)), f)
	return f


# ----------------------------------------------------------------------------
# Envelopes and control signals
# ----------------------------------------------------------------------------
def segments(points, n: int | None = None, curve: float = 1.0) -> np.ndarray:
	"""Piecewise envelope through [(time_s, value), ...]. curve > 1 bends each
	segment towards its end value late (exponential-ish), < 1 early."""
	pts = sorted(points)
	if n is None:
		n = sec(pts[-1][0])
	t = tgrid(n)
	ts = np.array([p[0] for p in pts], dtype=float)
	vs = np.array([p[1] for p in pts], dtype=float)
	if curve == 1.0:
		return np.interp(t, ts, vs)
	out = np.full(n, vs[-1])
	out[t < ts[0]] = vs[0]
	for i in range(len(pts) - 1):
		m = (t >= ts[i]) & (t < ts[i + 1])
		if not m.any():
			continue
		u = (t[m] - ts[i]) / max(ts[i + 1] - ts[i], 1e-9)
		out[m] = vs[i] + (vs[i + 1] - vs[i]) * u ** curve
	return out


def adsr(n: int, a: float, d: float, s: float, r: float) -> np.ndarray:
	"""Attack/decay/sustain/release with raised-cosine attack and release.
	The release occupies the last r seconds of the n samples."""
	t = tgrid(n)
	dur = n / SR
	env = np.ones(n) * s
	if a > 0:
		m = t < a
		env[m] = 0.5 - 0.5 * np.cos(np.pi * t[m] / a)
	if d > 0:
		m = (t >= a) & (t < a + d)
		env[m] = s + (1 - s) * np.exp(-5.0 * (t[m] - a) / d)
	else:
		env[t >= a] = s
	if r > 0:
		m = t > dur - r
		env[m] *= 0.5 + 0.5 * np.cos(np.pi * (t[m] - (dur - r)) / r)
	return env


def exp_decay(n: int, t60: float) -> np.ndarray:
	"""Exponential decay reaching -60 dB at t60 seconds."""
	return np.exp(-6.9078 * tgrid(n) / max(t60, 1e-6))


def fade(x: np.ndarray, t_in: float = 0.002, t_out: float = 0.01) -> np.ndarray:
	"""Raised-cosine fade in and out (kills clicks at both ends)."""
	x = np.array(x, dtype=float)
	n = len(x)
	a = min(sec(t_in), n // 2)
	b = min(sec(t_out), n // 2)
	if a > 0:
		w = 0.5 - 0.5 * np.cos(np.pi * np.arange(a) / a)
		x[:a] = (x[:a].T * w).T
	if b > 0:
		w = 0.5 + 0.5 * np.cos(np.pi * (np.arange(b) + 1) / b)
		x[-b:] = (x[-b:].T * w).T
	return x


def lfo_noise(n: int, rate_hz: float, rng, periodic: bool = True) -> np.ndarray:
	"""Smooth random wander in about -1..1, roughly rate_hz wiggles per second.
	Fourier-interpolated from random control points, so it is exactly periodic
	over n samples (safe inside seamless loops)."""
	k = max(4, int(round(n / SR * rate_hz * 2)))
	pts = rng.uniform(-1, 1, k)
	if not periodic:
		pts = np.concatenate([pts, pts[::-1]])
		return signal.resample(pts, 2 * n)[:n]
	return signal.resample(pts, n)


def smooth(x: np.ndarray, t: float) -> np.ndarray:
	"""Zero-phase smoothing with a Hann window of t seconds."""
	k = max(3, sec(t) | 1)
	w = np.hanning(k)
	return np.convolve(x, w / w.sum(), mode="same")


# ----------------------------------------------------------------------------
# Oscillators
# ----------------------------------------------------------------------------
def phase(f, n: int) -> np.ndarray:
	"""Running phase (radians) for a constant or per-sample frequency."""
	return TAU * np.cumsum(as_array(f, n)) / SR


def sine(f, n: int, ph0: float = 0.0) -> np.ndarray:
	return np.sin(phase(f, n) + ph0)


def _polyblep(t, dt):
	out = np.zeros_like(t)
	m = t < dt
	x = t[m] / dt[m]
	out[m] = x + x - x * x - 1.0
	m = t > 1.0 - dt
	x = (t[m] - 1.0) / dt[m]
	out[m] = x * x + x + x + 1.0
	return out


def saw(f, n: int, ph0: float = 0.0) -> np.ndarray:
	"""Band-limited (polyBLEP) sawtooth."""
	dt = as_array(f, n) / SR
	t = (np.cumsum(dt) + ph0) % 1.0
	return 2.0 * t - 1.0 - _polyblep(t, dt)


def pulse(f, n: int, width: float = 0.5) -> np.ndarray:
	"""Band-limited pulse wave as the difference of two saws."""
	return 0.5 * (saw(f, n) - saw(f, n, width))


def triangle(f, n: int) -> np.ndarray:
	return 2.0 / np.pi * np.arcsin(np.sin(phase(f, n)))


def additive(f, n: int, spec_fn, kmax: int = 64, ctrl_hz: float = 200.0,
			 phases=None, stretch: float = 0.0) -> np.ndarray:
	"""Band-limited harmonic synthesis with a time-varying spectral envelope.

	spec_fn(k, fk, t) -> amplitude of harmonic k, where fk (Hz) and t (s) are
	arrays at control rate. Harmonics above 19 kHz are faded out, so nothing
	aliases whatever the pitch does. stretch adds string-like inharmonicity.
	"""
	f = as_array(f, n)
	ph = TAU * np.cumsum(f) / SR
	nc = max(2, int(n / SR * ctrl_hz) + 2)
	tc = np.linspace(0, n / SR, nc)
	fc = np.interp(tc, tgrid(n), f)
	t = tgrid(n)
	out = np.zeros(n)
	fmin = max(float(f.min()), 1.0)
	kmax = int(min(kmax, 19000.0 / fmin))
	for k in range(1, kmax + 1):
		ratio = k * np.sqrt(1.0 + stretch * k * k)
		fk = fc * ratio
		a = np.asarray(spec_fn(k, fk, tc), dtype=float) * np.clip((19000.0 - fk) / 2000.0, 0.0, 1.0)
		if not np.any(a > 1e-6):
			continue
		p0 = 0.0 if phases is None else phases[(k - 1) % len(phases)]
		out += np.interp(t, tc, a) * np.sin(ratio * ph + p0)
	return out


# ----------------------------------------------------------------------------
# Noise
# ----------------------------------------------------------------------------
def white(n: int, rng) -> np.ndarray:
	return rng.standard_normal(n)


def _log_edge(f, lo, hi, soft=0.33):
	"""Raised-cosine band mask in log frequency, edges soft octaves wide."""
	lf = np.log2(np.maximum(f, 1e-3))
	g = np.ones_like(f)
	if lo is not None and lo > 0:
		g *= np.clip((lf - np.log2(lo)) / soft + 0.5, 0, 1)
	if hi is not None:
		g *= np.clip((np.log2(hi) - lf) / soft + 0.5, 0, 1)
	return 0.5 - 0.5 * np.cos(np.pi * g)


def shaped_noise(n: int, rng, lo: float | None = 20.0, hi: float | None = 18000.0,
				 slope: float = 0.0, gain_fn=None) -> np.ndarray:
	"""Band-limited noise built in the frequency domain: flat between lo and hi
	with a slope in dB/octave (-3 pink, -6 brown), unit RMS. Exactly periodic
	over n samples, so it loops with no seam."""
	freqs = np.fft.rfftfreq(n, 1.0 / SR)
	mag = _log_edge(freqs, lo, hi)
	if slope != 0.0:
		mag *= (np.maximum(freqs, 10.0) / 1000.0) ** (slope / 6.0206)
	if gain_fn is not None:
		mag *= gain_fn(freqs)
	mag[0] = 0.0
	spec = mag * np.exp(1j * rng.uniform(0, TAU, len(freqs)))
	x = np.fft.irfft(spec, n)
	return x / (np.sqrt(np.mean(x * x)) + 1e-12)


def spectral_filter(x: np.ndarray, gain_fn) -> np.ndarray:
	"""Zero-phase circular filter: multiply the spectrum by gain_fn(freqs).
	Keeps a periodic signal periodic."""
	if x.ndim == 2:
		return np.stack([spectral_filter(x[:, c], gain_fn) for c in range(x.shape[1])], axis=1)
	n = len(x)
	spec = np.fft.rfft(x)
	return np.fft.irfft(spec * gain_fn(np.fft.rfftfreq(n, 1.0 / SR)), n)


def band_centers(fmin: float = 40.0, fmax: float = 16000.0, per_oct: float = 3.0) -> np.ndarray:
	k = int(np.floor(np.log2(fmax / fmin) * per_oct)) + 1
	return fmin * 2.0 ** (np.arange(k) / per_oct)


def tf_noise(n: int, gain_fn, rng, fmin: float = 40.0, fmax: float = 16000.0,
			 per_oct: float = 3.0, ctrl_hz: float = 200.0, channels: int = 1,
			 width: float = 1.0) -> np.ndarray:
	"""Noise painted on the time-frequency plane (a noise channel vocoder).

	White noise is split into overlapping log-spaced bands and each band gets
	its own envelope: gain_fn(fc, t) -> linear gain, with fc the band centre
	and t control-rate times. Gains are relative to white noise, so include
	any tilt you want. The result is periodic over n if gain_fn is.
	channels=2 gives a stereo field; width 0..1 sets decorrelation.
	"""
	centers = band_centers(fmin, fmax, per_oct)
	freqs = np.fft.rfftfreq(n, 1.0 / SR)
	lf = np.log2(np.maximum(freqs, 1e-3))
	nc = max(2, int(n / SR * ctrl_hz) + 1)
	tc = np.arange(nc) / nc * (n / SR)
	t = tgrid(n)
	norm = np.sqrt(n / 2.0)
	nsrc = 1 if channels == 1 else 3
	specs = [np.exp(1j * rng.uniform(0, TAU, len(freqs))) * norm for _ in range(nsrc)]
	out = np.zeros((n, channels))
	for fc in centers:
		g = np.asarray(gain_fn(float(fc), tc), dtype=float)
		if g.ndim == 0:
			g = np.full(nc, float(g))
		if not np.any(g > 1e-5):
			continue
		d = np.abs(lf - np.log2(fc)) * per_oct
		w = np.where(d < 1.0, np.cos(0.5 * np.pi * np.minimum(d, 1.0)) ** 2, 0.0)
		w[0] = 0.0
		env = np.interp(t, tc, g, period=n / SR)
		bands = [np.fft.irfft(s * w, n) for s in specs]
		if channels == 1:
			out[:, 0] += bands[0] * env
		else:
			m = np.sqrt(1.0 - 0.5 * width * width)
			s = width * np.sqrt(0.5)
			out[:, 0] += (m * bands[0] + s * bands[1]) * env
			out[:, 1] += (m * bands[0] + s * bands[2]) * env
	return out[:, 0] if channels == 1 else out


def tilt(fc: float, slope_db_oct: float, ref: float = 1000.0) -> float:
	"""Gain for a spectral slope, for use inside tf_noise gain functions."""
	return (fc / ref) ** (slope_db_oct / 6.0206)


def lp_shape(fc, cutoff, order: float = 2.0):
	"""Smooth low-pass magnitude (Butterworth-like) for gain functions."""
	return 1.0 / np.sqrt(1.0 + (fc / np.maximum(cutoff, 1.0)) ** (2.0 * order))


def hp_shape(fc, cutoff, order: float = 2.0):
	return 1.0 / np.sqrt(1.0 + (np.maximum(cutoff, 1.0) / fc) ** (2.0 * order))


def bp_shape(fc, center, octaves: float = 1.0):
	"""Gaussian band in log frequency, `octaves` wide at about -4 dB."""
	return np.exp(-0.5 * (np.log2(fc / np.maximum(center, 1.0)) / (0.5 * octaves)) ** 2)


def grain_env(n: int, rate_hz: float, rng, grain_s: float = 0.004, depth: float = 1.0) -> np.ndarray:
	"""Crackly amplitude texture (sand, gravel, foam, fizz): a Poisson train
	of tiny grains. Multiply noise by it. Mean is about 1."""
	cnt = max(1, int(n / SR * rate_hz))
	env = np.zeros(n)
	pos = rng.integers(0, n, cnt)
	np.add.at(env, pos, rng.exponential(1.0, cnt))
	k = max(2, sec(grain_s))
	env = convolve1d(env, np.hanning(k * 2 + 1), mode="wrap")  # wrap: loop-safe
	env /= np.mean(env) + 1e-9
	return 1.0 - depth + depth * env


# ----------------------------------------------------------------------------
# Filters
# ----------------------------------------------------------------------------
def lowpass(x, fc: float, order: int = 2) -> np.ndarray:
	sos = signal.butter(order, min(fc, SR * 0.49), "low", fs=SR, output="sos")
	return signal.sosfilt(sos, x, axis=0)


def highpass(x, fc: float, order: int = 2) -> np.ndarray:
	sos = signal.butter(order, fc, "high", fs=SR, output="sos")
	return signal.sosfilt(sos, x, axis=0)


def bandpass(x, lo: float, hi: float, order: int = 2) -> np.ndarray:
	sos = signal.butter(order, [lo, min(hi, SR * 0.49)], "band", fs=SR, output="sos")
	return signal.sosfilt(sos, x, axis=0)


def _biquad(kind: str, fc: float, q: float, gain_db: float = 0.0):
	a = 10.0 ** (gain_db / 40.0)
	w = TAU * fc / SR
	al = np.sin(w) / (2.0 * q)
	c = np.cos(w)
	if kind == "peak":
		b = [1 + al * a, -2 * c, 1 - al * a]
		den = [1 + al / a, -2 * c, 1 - al / a]
	elif kind == "bp":  # constant 0 dB peak gain
		b = [al, 0.0, -al]
		den = [1 + al, -2 * c, 1 - al]
	elif kind == "lowshelf":
		s = 2 * np.sqrt(a) * al
		b = [a * ((a + 1) - (a - 1) * c + s), 2 * a * ((a - 1) - (a + 1) * c), a * ((a + 1) - (a - 1) * c - s)]
		den = [(a + 1) + (a - 1) * c + s, -2 * ((a - 1) + (a + 1) * c), (a + 1) + (a - 1) * c - s]
	elif kind == "highshelf":
		s = 2 * np.sqrt(a) * al
		b = [a * ((a + 1) + (a - 1) * c + s), -2 * a * ((a - 1) + (a + 1) * c), a * ((a + 1) + (a - 1) * c - s)]
		den = [(a + 1) - (a - 1) * c + s, 2 * ((a - 1) - (a + 1) * c), (a + 1) - (a - 1) * c - s]
	else:
		raise ValueError(kind)
	return np.array(b) / den[0], np.array(den) / den[0]


def resonator(x, fc: float, q: float) -> np.ndarray:
	"""Two-pole band-pass resonance with unity gain at fc."""
	b, a = _biquad("bp", fc, q)
	return signal.lfilter(b, a, x, axis=0)


def peak_eq(x, fc: float, q: float, gain_db: float) -> np.ndarray:
	b, a = _biquad("peak", fc, q, gain_db)
	return signal.lfilter(b, a, x, axis=0)


def shelf(x, fc: float, gain_db: float, kind: str = "high") -> np.ndarray:
	b, a = _biquad(kind + "shelf", fc, 0.707, gain_db)
	return signal.lfilter(b, a, x, axis=0)


def formant_bank(x, formants) -> np.ndarray:
	"""Parallel resonators [(freq, q, gain), ...]: bodies, boxes, mouths."""
	out = np.zeros_like(np.asarray(x, dtype=float))
	for f, q, g in formants:
		out += g * resonator(x, f, q)
	return out


def svf(x, fc, q: float = 0.707, mode: str = "lp") -> np.ndarray:
	"""Time-varying state-variable filter (TPT form). fc may be an array.
	A Python loop: use on short sounds; use tf_noise for long sweeps."""
	n = len(x)
	g = np.tan(np.pi * np.clip(as_array(fc, n), 10.0, SR * 0.45) / SR)
	k = 1.0 / q
	a1 = 1.0 / (1.0 + g * (g + k))
	a2 = g * a1
	a3 = g * a2
	out = np.empty(n)
	ic1 = ic2 = 0.0
	xl = x.tolist(); a1l = a1.tolist(); a2l = a2.tolist(); a3l = a3.tolist()
	sel = {"lp": 0, "bp": 1, "hp": 2}[mode]
	for i in range(n):
		v3 = xl[i] - ic2
		v1 = a1l[i] * ic1 + a2l[i] * v3
		v2 = ic2 + a2l[i] * ic1 + a3l[i] * v3
		ic1 = 2.0 * v1 - ic1
		ic2 = 2.0 * v2 - ic2
		out[i] = v2 if sel == 0 else (v1 if sel == 1 else xl[i] - k * v1 - v2)
	return out


def dc_block(x) -> np.ndarray:
	return signal.lfilter([1.0, -1.0], [1.0, -0.9995], x, axis=0)


def soft_clip(x, drive: float = 1.0) -> np.ndarray:
	"""tanh saturation; drive > 1 thickens."""
	return np.tanh(np.asarray(x) * drive) / np.tanh(drive)


# ----------------------------------------------------------------------------
# Physical-ish models
# ----------------------------------------------------------------------------
def modal(freqs, t60s, amps, dur: float, rng=None, attack: float = 0.0004) -> np.ndarray:
	"""Struck object as a sum of exponentially decaying sine modes."""
	n = sec(dur)
	t = tgrid(n)
	out = np.zeros(n)
	for i, (f, t60, a) in enumerate(zip(freqs, t60s, amps)):
		if f >= SR * 0.45:
			continue
		ph = 0.0 if rng is None else rng.uniform(0, TAU)
		out += a * np.exp(-6.9078 * t / t60) * np.sin(TAU * f * t + ph)
	k = max(1, sec(attack))
	out[:k] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(k) / k)
	return out


def excite(exc, freqs, qs, amps) -> np.ndarray:
	"""Drive a bank of resonances with an arbitrary excitation (scrape, creak)."""
	out = np.zeros(len(exc))
	for f, q, a in zip(freqs, qs, amps):
		out += a * resonator(exc, f, q)
	return out


def wood_modes(rng, base: float, count: int = 7, spread: float = 5.0, t60: float = 0.09):
	"""Mode set for a plank or box: inharmonic, short, upper modes die faster."""
	ratios = np.sort(np.concatenate([[1.0], 1.0 + rng.uniform(0.35, spread, count - 1)]))
	freqs = base * ratios
	t60s = t60 * ratios ** -0.7 * rng.uniform(0.7, 1.3, count)
	amps = ratios ** -0.9 * rng.uniform(0.5, 1.0, count)
	return freqs, t60s, amps


def metal_modes(rng, base: float, count: int = 12, t60: float = 0.6, bright: float = 0.4):
	"""Mode set for a bar or blade: stiff-bar ratios with a little disorder."""
	k = np.arange(count)
	ratios = ((k + 1.5) / 1.5) ** 1.9 * rng.uniform(0.96, 1.04, count)
	ratios[0] = 1.0
	freqs = base * ratios
	t60s = t60 * ratios ** -0.55 * rng.uniform(0.6, 1.2, count)
	amps = ratios ** -bright * rng.uniform(0.4, 1.0, count)
	return freqs, t60s, amps


def karplus_strong(f: float, dur: float, rng, t60: float = 2.5, bright: float = 0.5,
				   pluck_pos: float = 0.18, vel: float = 1.0) -> np.ndarray:
	"""Plucked string: a noise burst circulating in a tuned, damped delay
	loop (extended Karplus-Strong with an all-pass for exact tuning)."""
	n = sec(dur)
	b_lp = 0.5 * (1.0 - bright * 0.9)  # loop low-pass weight, delay about b_lp
	period = SR / f
	big_n = int(np.floor(period - b_lp - 0.2))
	d = period - b_lp - big_n
	c = (1.0 - d) / (1.0 + d)
	g = 10.0 ** (-3.0 / (t60 * f))
	# loop filter g * ((1-b) + b z^-1) * (c + z^-1) / (1 + c z^-1)
	fb = g * np.convolve([1.0 - b_lp, b_lp], [c, 1.0])
	fa = np.array([1.0, c])
	exc = rng.uniform(-1, 1, big_n)
	exc = lowpass(exc, 1200.0 + 9000.0 * bright * vel, 1)
	pp = max(1, int(big_n * pluck_pos))
	exc = exc - np.roll(exc, pp)
	exc -= exc.mean()
	exc *= np.hanning(big_n) ** 0.25
	out = np.zeros(n + big_n)
	out[:big_n] = exc
	zi = np.zeros(2)
	pos = big_n
	prev = exc
	while pos < n:
		blk, zi = signal.lfilter(fb, fa, prev, zi=zi)
		out[pos:pos + big_n] = blk
		prev = blk
		pos += big_n
	out = out[:n]
	return out / (np.max(np.abs(out)) + 1e-9) * vel


def concertina(f, n: int, rng, vel: float = 1.0, bright: float = 1.0, release: float = 0.05) -> np.ndarray:
	"""Free-reed (concertina) tone.

	A beating reed chops the air stream into a pulse: every harmonic is
	present, rolling off about 6 dB/octave, shaped here by the reed chamber
	(broad bumps near 900 Hz and 2.3 kHz) and a 4 kHz roll-off. Upper
	harmonics speak a little later than the fundamental, the bellows adds a
	slow pressure wobble, and a second reed 5 cents off adds a gentle beat.
	"""
	f = as_array(f, n)
	wob = 1.0 + 0.04 * lfo_noise(n, 3.0, rng, periodic=False)
	tot = n / SR

	def spec(k, fk, t):
		src = 1.0 / k ** 0.95 * (1.0 if k % 2 else 0.8)
		body = (0.55 + 0.6 * bp_shape(fk, 900.0, 1.6) + 0.45 * bp_shape(fk, 2300.0, 1.0)) \
			* lp_shape(fk, 3800.0 * bright, 1.5)
		speak = 1.0 - np.exp(-t / (0.008 + 0.004 * k))
		return src * body * speak

	x = additive(f, n, spec, kmax=48, phases=rng.uniform(0, TAU, 48))
	x += 0.28 * additive(f * 2.0 ** (5.0 / 1200.0), n, spec, kmax=24, phases=rng.uniform(0, TAU, 24))
	env = adsr(n, 0.022, 0.12, 0.86, min(release, tot * 0.4)) * wob
	x *= env
	# button click and a breath of bellows air
	click = bandpass(white(n, rng), 1500, 5000) * np.exp(-tgrid(n) / 0.004) * 0.05
	air = bandpass(white(n, rng), 2500, 7000) * env * 0.006
	return (x * 0.5 + click + air) * vel


def hurdy_gurdy(f, n: int, rng, vel: float = 1.0, wheel: np.ndarray | None = None,
				buzz: np.ndarray | None = None) -> np.ndarray:
	"""Wheel-bowed string (hurdy-gurdy).

	Continuous bowing gives a saw-like source; the small soundbox adds nasal
	formants near 1.1 and 2.7 kHz. `wheel` (0..1 per sample) is the crank
	speed and scales loudness and brightness. `buzz` (0..1 per sample) drives
	the trompette: the buzzing bridge adds a harsh pulse rich in upper
	harmonics whenever the crank is jerked.
	"""
	f = as_array(f, n)
	wheel = np.ones(n) if wheel is None else as_array(wheel, n)
	flutter = 1.0 + 0.05 * np.sin(TAU * 3.7 * tgrid(n) + rng.uniform(0, TAU)) \
		+ 0.03 * lfo_noise(n, 8.0, rng, periodic=False)
	nc_t = tgrid(n)

	def spec(k, fk, t):
		w = np.interp(t, nc_t[::64], wheel[::64])
		src = 1.0 / k ** (1.25 - 0.25 * w)
		body = 0.5 + 0.9 * bp_shape(fk, 1100.0, 0.9) + 0.6 * bp_shape(fk, 2700.0, 0.7) \
			+ 0.5 * bp_shape(fk, 420.0, 1.0)
		return src * body * lp_shape(fk, 5200.0, 2.0)

	x = additive(f * (1.0 + 0.0015 * lfo_noise(n, 5.0, rng, periodic=False)), n, spec,
				 kmax=56, phases=rng.uniform(0, TAU, 56))
	x *= wheel * flutter
	x += bandpass(white(n, rng), 2000, 6000) * wheel * 0.012  # rosin hiss
	if buzz is not None:
		bz = as_array(buzz, n)

		def bspec(k, fk, t):
			return bp_shape(fk, 1700.0, 2.2) * lp_shape(fk, 4200.0, 2.0) / k ** 0.2

		x += 0.5 * bz * additive(f, n, bspec, kmax=40)
	return x * 0.4 * vel


def membrane(f0: float, dur: float, rng, vel: float = 1.0, t60: float = 0.35,
			 bend: float = 0.18, slap: float = 0.3, tone: float = 1.0) -> np.ndarray:
	"""Struck drum skin: circular-membrane mode ratios, a pitch that drops as
	the skin relaxes after the hit, and a short beater noise."""
	n = sec(dur)
	t = tgrid(n)
	ratios = np.array([1.0, 1.593, 2.136, 2.296, 2.653, 2.918, 3.156, 3.501])
	gl = 1.0 + bend * vel * np.exp(-t / 0.035)
	out = np.zeros(n)
	for i, r in enumerate(ratios):
		a = tone * (1.0 if i == 0 else 0.55 / (i ** 0.8)) * rng.uniform(0.7, 1.0)
		out += a * np.exp(-6.9078 * t / (t60 / r ** 1.1)) * np.sin(TAU * np.cumsum(f0 * r * gl) / SR)
	beater = lowpass(white(n, rng), 900.0 + 2500.0 * vel, 2) * np.exp(-t / 0.006) * slap
	skin = bandpass(white(n, rng), 300, 2500) * np.exp(-t / 0.03) * slap * 0.25
	out = out + beater + skin
	k = sec(0.0008)
	out[:k] *= np.linspace(0, 1, k)
	return out * vel


def whistle_voice(f, amp, rng, breath: float = 1.0, bright: float = 1.0) -> np.ndarray:
	"""Tin whistle line from per-sample pitch and loudness curves.

	An air jet on an edge: nearly a sine with weak 2nd and 3rd harmonics that
	grow with blowing pressure, plus breath noise coloured by the tube (bands
	round the played note and its overtones) and a little jet turbulence.
	"""
	n = len(f)
	amp = as_array(amp, n)
	tt = tgrid(n)

	def spec(k, fk, t):
		a = np.interp(t, tt[::64], amp[::64])
		return [1.0, 0.22 * bright, 0.09 * bright, 0.03 * bright, 0.012, 0.006][k - 1] * (a ** (0.5 * (k - 1)))

	x = additive(f, n, spec, kmax=6) * amp
	# breath: noise through resonances that follow the fingered note
	nz = white(n, rng)
	fmean = float(np.median(f[amp > 0.05])) if np.any(amp > 0.05) else 800.0
	br = bandpass(nz, fmean * 0.8, min(fmean * 3.5, 9000), 1) * 0.6 + bandpass(nz, 4000, 9000, 1) * 0.5
	turb = 1.0 + 0.3 * lfo_noise(n, 30.0, rng, periodic=False)
	x += br * amp ** 0.7 * 0.035 * breath * turb
	return x * 0.5


FORMANTS = {
	# vowel: F1, F2, F3 (adult male, Hz)
	"a": (730, 1090, 2440), "o": (570, 840, 2410), "e": (530, 1840, 2480),
	"i": (280, 2250, 2900), "u": (310, 870, 2250), "uh": (640, 1190, 2390),
	"m": (250, 1000, 2200),
}


def voice(f, n: int, vowels, rng, vel: float = 1.0, rough: float = 0.0, breath: float = 0.05,
		  size: float = 1.0, tilt_exp: float = 1.1) -> np.ndarray:
	"""Formant voice: a glottal pulse source (about -12 dB/octave, +6 for lip
	radiation, with jitter and shimmer) through a cascade of three moving
	formants and two fixed upper ones. `vowels` is one vowel name or a list of (time 0..1, name)
	to glide between. `size` scales the vocal tract (bigger = lower formants).
	`rough` adds growl (subharmonic amplitude modulation and jitter)."""
	f = as_array(f, n)
	if isinstance(vowels, str):
		vowels = [(0.0, vowels), (1.0, vowels)]
	vt = np.array([v[0] for v in vowels]) * (n / SR)
	vf = np.array([FORMANTS[v[1]] for v in vowels], dtype=float) / size
	jit = 1.0 + (0.004 + 0.03 * rough) * lfo_noise(n, 40.0, rng, periodic=False)
	fj = f * jit

	def spec(k, fk, t):
		env = 1.0 / k ** tilt_exp
		for i, bw in enumerate((80.0, 100.0, 150.0)):
			fi = np.interp(t, vt, vf[:, i])
			env = env * fi * fi / np.sqrt((fi * fi - fk * fk) ** 2 + (bw * fk) ** 2)
		for fi, bw in ((3300.0 / size, 250.0), (3750.0 / size, 300.0)):
			env = env * fi * fi / np.sqrt((fi * fi - fk * fk) ** 2 + (bw * fk) ** 2)
		return env

	x = additive(fj, n, spec, kmax=60, phases=rng.uniform(0, TAU, 60))
	shimmer = 1.0 + (0.05 + 0.3 * rough) * lfo_noise(n, 25.0, rng, periodic=False)
	if rough > 0:
		shimmer *= 1.0 + 0.5 * rough * np.sin(0.5 * phase(fj, n))
	x *= shimmer
	if breath > 0:
		nz = white(n, rng)
		f1, f2, f3 = vf[0]
		x += breath * (resonator(nz, f1, 5) + 0.6 * resonator(nz, f2, 7) + 0.4 * resonator(nz, f3, 8)) \
			* np.sqrt(np.mean(x * x) + 1e-12) * 3.0
	return x * vel


def bubble(n: int, f0: float, rng, rise: float = 0.6, t60: float = 0.05) -> np.ndarray:
	"""One air bubble: a damped sine whose pitch rises as it nears the surface."""
	t = tgrid(n)
	fr = f0 * (1.0 + rise * t / max(t60, 1e-3))
	x = np.sin(phase(fr, n)) * np.exp(-6.9078 * t / t60)
	k = min(n, sec(0.0015))
	x[:k] *= np.linspace(0, 1, k)
	return x


def bubbles(dur: float, count: int, rng, f_lo: float = 400.0, f_hi: float = 3000.0,
			t60: tuple = (0.02, 0.09), density_env=None, wrap: bool = False) -> np.ndarray:
	"""A scatter of bubbles; bigger (lower) ones are louder and ring longer.
	density_env(t01) -> relative probability shapes where they fall."""
	n = sec(dur)
	out = np.zeros(n)
	if density_env is None:
		starts = rng.uniform(0, 1, count)
	else:
		grid = np.linspace(0, 1, 512)
		p = np.maximum(density_env(grid), 0)
		starts = np.interp(rng.uniform(0, 1, count), np.cumsum(p) / p.sum(), grid)
	for s in starts:
		u = rng.uniform(0, 1)
		f0 = f_lo * (f_hi / f_lo) ** u
		d = t60[1] + (t60[0] - t60[1]) * u
		b = bubble(sec(d * 1.3), f0, rng, rise=rng.uniform(0.2, 0.9), t60=d) * (1.0 - 0.6 * u) * rng.uniform(0.3, 1.0)
		place(out, b, s * dur, wrap=wrap)
	return out


def stick_slip(dur: float, rng, rate=(30.0, 80.0), jitter: float = 0.25, amp_fn=None) -> np.ndarray:
	"""Stick-slip friction (the heart of a creak): a train of sharp slips whose
	rate wanders. rate is (start, end) Hz or a per-sample array."""
	n = sec(dur)
	r = as_array(np.linspace(rate[0], rate[1], 64) if isinstance(rate, tuple) else rate, n)
	out = np.zeros(n)
	pos = 0.0
	while pos < n - 1:
		i = int(pos)
		a = rng.uniform(0.4, 1.0) * (1.0 if amp_fn is None else amp_fn(i / n))
		out[i] += a
		pos += SR / r[i] * (1.0 + jitter * rng.uniform(-1, 1))
	return out


def creak(dur: float, rng, pitch=(35.0, 80.0), body_lo: float = 250.0, body_hi: float = 2600.0,
		  modes: int = 6, groan: float = 0.5, bursts: float = 1.5) -> np.ndarray:
	"""Wooden creak: stick-slip pulses whose rate wanders inside `pitch` (Hz),
	ringing a handful of timber resonances between body_lo and body_hi.
	`groan` mixes in the bare low pulse train; `bursts` is how many times per
	second the joint catches and lets go."""
	n = sec(dur)
	wander = lfo_noise(n, 2.5, rng, periodic=False) * 0.5 + 0.5
	glide = np.linspace(rng.uniform(0, 0.4), rng.uniform(0.6, 1.0), n)
	if rng.uniform() < 0.5:
		glide = glide[::-1]
	rate = pitch[0] * (pitch[1] / pitch[0]) ** np.clip(0.6 * glide + 0.4 * wander, 0, 1)
	catch = np.clip(lfo_noise(n, bursts * 2.0, rng, periodic=False) * 1.6 + 0.55, 0, 1)
	catch *= np.sin(np.pi * np.linspace(0, 1, n)) ** 0.5
	slips = stick_slip(dur, rng, rate=rate, jitter=0.12) * catch
	slips = lowpass(slips, 3500.0, 1)
	freqs = np.sort(body_lo * (body_hi / body_lo) ** rng.uniform(0, 1, modes))
	qs = rng.uniform(9, 26, modes)
	amps = (freqs / body_lo) ** -0.5 * rng.uniform(0.5, 1.0, modes)
	out = excite(slips, freqs, qs, amps) + groan * lowpass(slips, 600.0, 2) * 0.6
	return fade(out, 0.01, 0.03)


def periodic_tone(f: np.ndarray) -> np.ndarray:
	"""Sine following the frequency curve f, nudged so it completes a whole
	number of cycles: it joins itself exactly when looped."""
	ph = np.cumsum(f) / SR
	ph *= np.round(ph[-1]) / ph[-1]
	return np.sin(TAU * ph)


# ----------------------------------------------------------------------------
# Space: reverb and stereo
# ----------------------------------------------------------------------------
_IR_CACHE: dict = {}


def reverb_ir(t60: float = 1.2, damp: float = 0.5, predelay: float = 0.01, seed: int = 1,
			  early: float = 0.5) -> np.ndarray:
	"""Synthetic stereo impulse response: a handful of early reflections then
	an exponentially decaying diffuse tail whose highs die sooner (damp)."""
	key = (t60, damp, predelay, seed, early)
	if key in _IR_CACHE:
		return _IR_CACHE[key]
	rng = np.random.default_rng(1000 + seed)
	n = sec(t60 * 1.15 + predelay)
	ir = np.zeros((n, 2))
	t = tgrid(n)
	for c in range(2):
		tail = np.zeros(n)
		edges = [(None, 400), (400, 1600), (1600, 5000), (5000, 16000)]
		for bi, (lo, hi) in enumerate(edges):
			band = shaped_noise(n, rng, lo, hi)
			tail += band * np.exp(-6.9078 * t / (t60 * (1.0 - damp * bi / 3.6))) * (0.9 ** bi)
		build = 1.0 - np.exp(-t / 0.012)
		tail = np.roll(tail * build, sec(predelay))
		tail[:sec(predelay)] = 0.0
		ir[:, c] = tail
		for _ in range(7):
			d = predelay + rng.uniform(0.004, 0.06)
			ir[min(sec(d), n - 1), c] += early * rng.choice([-1, 1]) * rng.uniform(0.3, 0.9) * 40.0
	ir /= np.sqrt(np.sum(ir ** 2, axis=0)).mean()
	_IR_CACHE[key] = ir
	return ir


def reverb(x: np.ndarray, wet: float = 0.2, t60: float = 1.2, damp: float = 0.5, predelay: float = 0.01,
		   seed: int = 1, tail: bool = True, circular: bool = False, dry: float = 1.0) -> np.ndarray:
	"""Convolution reverb, mono or stereo in, stereo out. tail=True extends the
	output by the reverb tail; circular=True wraps it (for seamless loops)."""
	ir = reverb_ir(t60, damp, predelay, seed)
	st = to_stereo(x)
	n = len(st)
	if circular:
		pad = np.zeros((max(n, len(ir)), 2))
		pad[:len(ir)] = ir[:len(pad)]
		spec_ir = np.fft.rfft(pad[:n], axis=0) if len(pad) == n else None
		if spec_ir is None:
			raise ValueError("loop shorter than reverb tail")
		w = np.fft.irfft(np.fft.rfft(st, axis=0) * spec_ir, n, axis=0)
		return dry * st + wet * w
	w = np.stack([signal.fftconvolve(st[:, c], ir[:, c]) for c in range(2)], axis=1)
	out = np.zeros_like(w)
	out[:n] = dry * st
	out += wet * w
	return out if tail else out[:n]


def to_stereo(x: np.ndarray) -> np.ndarray:
	x = np.asarray(x, dtype=float)
	return x if x.ndim == 2 else np.stack([x, x], axis=1)


def to_mono(x: np.ndarray) -> np.ndarray:
	return x if x.ndim == 1 else x.mean(axis=1)


def pan(x: np.ndarray, p: float) -> np.ndarray:
	"""Equal-power pan of a mono signal, p in -1 (left) .. 1 (right)."""
	a = (p + 1.0) * np.pi / 4.0
	return np.stack([x * np.cos(a), x * np.sin(a)], axis=1) * np.sqrt(2.0)


def stereo_width(x: np.ndarray, w: float) -> np.ndarray:
	"""Mid/side width: 0 mono, 1 unchanged, >1 wider."""
	m = x.mean(axis=1)
	s = (x[:, 0] - x[:, 1]) * 0.5 * w
	return np.stack([m + s, m - s], axis=1)


def place(buf: np.ndarray, y: np.ndarray, t: float, gain: float = 1.0, wrap: bool = False,
		  p: float | None = None) -> None:
	"""Mix y into buf at time t (in place). wrap=True folds anything past the
	end back to the start, which keeps event layers seamless. p pans a mono y
	into a stereo buf."""
	n = len(buf)
	i = sec(t)
	if buf.ndim == 2:
		y = pan(y, p) if (y.ndim == 1 and p is not None) else to_stereo(y)
	y = y * gain
	if wrap:
		idx = (i + np.arange(len(y))) % n
		np.add.at(buf, idx, y)
		return
	if i >= n or i + len(y) <= 0:
		return
	a = max(0, -i)
	b = min(len(y), n - i)
	buf[i + a:i + b] += y[a:b]


# ----------------------------------------------------------------------------
# Loops
# ----------------------------------------------------------------------------
def loop_crossfade(x: np.ndarray, loop_len: int, equal_power: bool = True) -> np.ndarray:
	"""Make a seamless loop from a longer take: the overhang past loop_len is
	crossfaded into the head. equal_power suits noise; linear suits tones."""
	extra = len(x) - loop_len
	if extra <= 0:
		raise ValueError("need material beyond loop_len to crossfade")
	out = np.array(x[:loop_len], dtype=float)
	u = (np.arange(extra) + 0.5) / extra
	a, b = (np.sin(0.5 * np.pi * u), np.cos(0.5 * np.pi * u)) if equal_power else (u, 1.0 - u)
	out[:extra] = (out[:extra].T * a).T + (x[loop_len:].T * b).T
	return out


def fold_tail(x: np.ndarray, loop_len: int) -> np.ndarray:
	"""Make a seamless loop of music: whatever rings on past loop_len (reverb,
	releases) is added back onto the start, as it would be on the repeat."""
	out = np.array(x[:loop_len], dtype=float)
	rest = x[loop_len:]
	while len(rest) > 0:
		k = min(len(rest), loop_len)
		out[:k] += rest[:k]
		rest = rest[k:]
	return out


# ----------------------------------------------------------------------------
# Loudness and output
# ----------------------------------------------------------------------------
def _k_weight(x: np.ndarray) -> np.ndarray:
	"""ITU-R BS.1770 K-weighting (shelf + high-pass) at SR."""
	f0, g, q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
	k = np.tan(np.pi * f0 / SR)
	vh = 10.0 ** (g / 20.0)
	vb = vh ** 0.4996667741545416
	a0 = 1.0 + k / q + k * k
	b = np.array([(vh + vb * k / q + k * k), 2.0 * (k * k - vh), (vh - vb * k / q + k * k)]) / a0
	a = np.array([1.0, 2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0])
	y = signal.lfilter(b, a, x, axis=0)
	f0, q = 38.13547087602444, 0.5003270373238773
	k = np.tan(np.pi * f0 / SR)
	a0 = 1.0 + k / q + k * k
	a = np.array([1.0, 2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0])
	return signal.lfilter([1.0, -2.0, 1.0], a, y, axis=0)


def _block_powers(x: np.ndarray, win: float = 0.4, hop: float = 0.1) -> np.ndarray:
	y = _k_weight(to_stereo(x) if x.ndim == 1 else x)
	if x.ndim == 1:
		y = y[:, :1]
	p = np.sum(y * y, axis=1)
	w = sec(win)
	if len(p) < w:
		p = np.concatenate([p, np.zeros(w - len(p))])
	cs = np.concatenate([[0.0], np.cumsum(p)])
	idx = np.arange(0, len(p) - w + 1, sec(hop))
	return (cs[idx + w] - cs[idx]) / w


def lufs(x: np.ndarray) -> float:
	"""Integrated loudness (BS.1770 gating) in LUFS. Mono counts as one channel."""
	bp = _block_powers(x)
	l = -0.691 + 10.0 * np.log10(np.maximum(bp, 1e-12))
	keep = bp[l > -70.0]
	if len(keep) == 0:
		return -120.0
	rel = -0.691 + 10.0 * np.log10(np.mean(keep)) - 10.0
	keep = bp[(l > -70.0) & (l > rel)]
	return float(-0.691 + 10.0 * np.log10(np.mean(keep)))


def lufs_peak(x: np.ndarray) -> float:
	"""Loudest 400 ms window (max momentary loudness): the right yardstick for
	short one-shot effects."""
	return float(-0.691 + 10.0 * np.log10(max(np.max(_block_powers(x, 0.4, 0.02)), 1e-12)))


def limit(x: np.ndarray, ceiling_db: float = -1.0, release: float = 0.08) -> np.ndarray:
	"""Look-ahead peak limiter: transparent below the ceiling."""
	c = db(ceiling_db)
	pk = np.abs(x) if x.ndim == 1 else np.abs(x).max(axis=1)
	if pk.max() <= c:
		return x
	look = sec(0.004)
	need = np.minimum(1.0, c / np.maximum(pk, 1e-9))
	need = -maximum_filter1d(-need, size=2 * look + 1, mode="nearest")
	# instant attack (the minimum filter already looked ahead), exponential release
	coef = np.exp(-1.0 / (release * SR))
	cur = 1.0
	nl = need.tolist()
	gl = [1.0] * len(nl)
	for i, v in enumerate(nl):
		cur = 1.0 - (1.0 - cur) * coef
		if v < cur:
			cur = v
		gl[i] = cur
	# smoothing over less than the look-ahead cannot rise above what is needed
	w = np.hanning(2 * look + 1)
	g = np.convolve(np.array(gl), w / w.sum(), mode="same")
	return (x.T * g).T


def normalize(x: np.ndarray, target: float, mode: str = "peak400", ceiling_db: float = -1.0) -> np.ndarray:
	"""Scale to a loudness target (LUFS). mode 'integrated' for beds and music,
	'peak400' (loudest 400 ms) for one-shots. Peaks over the ceiling are
	caught by the limiter, so there is always headroom and never clipping."""
	x = np.asarray(x, dtype=float)
	x = x - np.mean(x, axis=0)
	cur = lufs(x) if mode == "integrated" else lufs_peak(x)
	x = x * db(target - cur)
	x = limit(x, ceiling_db)
	return x


def write_wav(path: str, x: np.ndarray) -> None:
	os.makedirs(os.path.dirname(path), exist_ok=True)
	y = np.clip(np.asarray(x, dtype=float), -1.0, 1.0)
	wavfile.write(path, SR, np.round(y * 32767.0).astype(np.int16))


def write_ogg(path: str, x: np.ndarray, quality: float = 4.0) -> None:
	"""Encode to Ogg Vorbis with ffmpeg, bit-exact so rebuilds are identical."""
	os.makedirs(os.path.dirname(path), exist_ok=True)
	with tempfile.TemporaryDirectory() as td:
		tmp = os.path.join(td, "t.wav")
		write_wav(tmp, x)
		subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-map_metadata", "-1",
						"-fflags", "+bitexact", "-flags:a", "+bitexact", "-c:a", "libvorbis",
						"-q:a", str(quality), path], check=True)


def read_audio(path: str) -> np.ndarray:
	"""Read WAV or Ogg to float arrays (mono 1-D or stereo (n, 2))."""
	if path.endswith(".wav"):
		sr, d = wavfile.read(path)
	else:
		with tempfile.TemporaryDirectory() as td:
			tmp = os.path.join(td, "t.wav")
			subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", path, "-c:a", "pcm_s16le", tmp], check=True)
			sr, d = wavfile.read(tmp)
	assert sr == SR, path
	return d.astype(float) / 32768.0


class Manifest:
	"""The sound catalogue (<outdir>/audio/manifest.json) the game loads.
	Each generator owns some top-level sections and rewrites only those."""

	def __init__(self, outdir: str):
		self.root = os.path.join(outdir, "audio")
		self.path = os.path.join(self.root, "manifest.json")
		self.sections: dict = {}

	def add(self, section: str, name: str, **entry) -> None:
		self.sections.setdefault(section, {})[name] = entry

	def save(self) -> None:
		os.makedirs(self.root, exist_ok=True)
		data = {}
		if os.path.exists(self.path):
			with open(self.path) as fh:
				data = json.load(fh)
		data.update(self.sections)
		with open(self.path, "w") as fh:
			json.dump(data, fh, indent="\t", sort_keys=True)
			fh.write("\n")
