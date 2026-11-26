#!/usr/bin/env python3
"""Ship and gameplay sound effects, all synthesised. Usage: gen_sfx.py <outdir>

Each recipe is a function (rng, v) -> mono signal, where v is the variation
index. The table at the bottom names every sound, how many variations it
gets, its loudness target (loudest 400 ms, LUFS) and how far it carries.
Output: <outdir>/audio/sfx/<name>_<n>.wav, mono 16-bit 44.1 kHz.
"""
from __future__ import annotations

import multiprocessing
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import synth as S  # noqa: E402
from synth import bp_shape, hp_shape, lp_shape, tilt  # noqa: E402


# ----------------------------------------------------------------------------
# Building blocks
# ----------------------------------------------------------------------------
def buf(dur: float) -> np.ndarray:
	return np.zeros(S.sec(dur))


def nz(dur: float, gain, rng, **kw) -> np.ndarray:
	"""Mono time-frequency painted noise of a given duration."""
	return S.fade(S.tf_noise(S.sec(dur), gain, rng, **kw), 0.001, 0.01)


def thump(f0: float, f1: float, dur: float, t60: float, glide: float = 0.03) -> np.ndarray:
	"""Low body hit: a sine that drops from f0 to f1 while it dies."""
	n = S.sec(dur)
	t = S.tgrid(n)
	x = np.sin(S.phase(f1 + (f0 - f1) * np.exp(-t / glide), n)) * S.exp_decay(n, t60)
	k = S.sec(0.002)
	x[:k] *= np.linspace(0, 1, k)
	return x


def click(rng, dur: float = 0.004, lo: float = 1500.0, hi: float = 9000.0) -> np.ndarray:
	n = S.sec(max(dur * 6, 0.02))
	return S.bandpass(S.white(n, rng), lo, hi) * np.exp(-S.tgrid(n) / dur)


def env_ad(t, attack: float, decay: float):
	"""Attack-decay envelope for gain functions (t in seconds from the event)."""
	tp = np.maximum(t, 0.0)
	return (t >= 0) * (1.0 - np.exp(-tp / attack)) * np.exp(-tp / decay)


def room(x: np.ndarray, wet: float, t60: float, damp: float = 0.6, seed: int = 1, predelay: float = 0.01) -> np.ndarray:
	"""Mono reverb with tail."""
	return S.to_mono(S.reverb(x, wet=wet, t60=t60, damp=damp, seed=seed, predelay=predelay))


def splash(rng, size: float, dur: float | None = None) -> np.ndarray:
	"""Something hits water. size 0..1 from a pebble to a cannonball: a low
	thump, a burst of spray that darkens fast, bubbles, and for big ones the
	plume falling back as hiss."""
	dur = dur or (0.35 + 1.5 * size)
	out = buf(dur)
	dec = 0.06 + 0.35 * size

	def gain(fc, t):
		cut = (2500.0 + 5000.0 * (1 - 0.3 * size)) * np.exp(-t / (0.05 + 0.2 * size)) + 500.0 + 300.0 * (1 - size)
		g = env_ad(t, 0.004 + 0.02 * size, dec) * lp_shape(fc, cut, 1.5) * hp_shape(fc, 150.0 - 80.0 * size) * tilt(fc, -2.0)
		if size > 0.4:
			back = np.exp(-0.5 * ((t - (0.45 + 0.4 * size)) / (0.16 + 0.15 * size)) ** 2)
			g = g + 0.22 * size * back * bp_shape(fc, 3500.0, 2.2)
		return g

	S.place(out, nz(dur, gain, rng), 0.0)
	if size > 0.4:
		hi = S.highpass(out, 1800.0)
		out += hi * (S.grain_env(len(out), 700.0, rng, 0.003, 1.0) - 1.0) * np.clip(S.tgrid(len(out)) / 0.5, 0, 1) * 0.6
	S.place(out, thump(90.0 + 110.0 * (1 - size), 45.0 + 50.0 * (1 - size), min(dur, 0.6), 0.1 + 0.3 * size), 0.0,
			0.5 * (0.3 + size))
	bub = S.bubbles(dur, int(10 + 70 * size), rng, 260.0 + 500.0 * (1 - size), 2200.0 + 1500.0 * (1 - size),
					t60=(0.015, 0.05 + 0.08 * size), density_env=lambda u: np.exp(-u / 0.35) * (u > 0.03))
	return out + bub * (0.16 + 0.1 * size)


def wood_hit(rng, base: float, t60: float = 0.09, modes: int = 7, spread: float = 5.0, dur: float = 0.35,
			 knock: float = 0.3) -> np.ndarray:
	fr, td, am = S.wood_modes(rng, base, modes, spread, t60)
	x = S.modal(fr, td, am, dur, rng)
	S.place(x, S.lowpass(click(rng, 0.003, 300, 5000), 3500), 0.0, knock)
	return x


def metal_hit(rng, base: float, t60: float = 0.4, modes: int = 10, bright: float = 0.4, dur: float | None = None,
			  tick: float = 0.2) -> np.ndarray:
	fr, td, am = S.metal_modes(rng, base, modes, t60, bright)
	x = S.modal(fr, td, am, dur or t60 * 1.3 + 0.05, rng)
	S.place(x, click(rng, 0.0015, 2000, 10000), 0.0, tick)
	return x


# ----------------------------------------------------------------------------
# Ship
# ----------------------------------------------------------------------------
def hull_creak(rng, v):
	x = S.creak(rng.uniform(0.8, 1.7), rng, pitch=(rng.uniform(22, 38), rng.uniform(60, 105)),
				body_lo=rng.uniform(170, 260), body_hi=rng.uniform(1700, 2600), groan=0.7)
	return room(x, 0.15, 0.5)


def sail_flap(rng, v):
	out = buf(1.0)
	t = 0.0
	for i in range(int(rng.integers(3, 6))):
		d = rng.uniform(0.09, 0.15)
		cut = rng.uniform(1600, 3200)
		g = lambda fc, tt, cut=cut: env_ad(tt, 0.003, 0.035) * lp_shape(fc, cut, 1.5) * hp_shape(fc, 110.0) * tilt(fc, -2.2)
		a = rng.uniform(0.5, 1.0)
		S.place(out, nz(d, g, rng), t, a)
		S.place(out, thump(110.0, 65.0, 0.12, 0.08), t, a * 0.25)
		t += rng.uniform(0.09, 0.2)
	return out


def sail_fill(rng, v):
	out = buf(1.3)

	def gain(fc, t):
		e = np.clip(t / 0.16, 0, 1) ** 1.6 * np.exp(-np.maximum(t - 0.16, 0) / 0.22)
		low = e * lp_shape(fc, 140.0 + 700.0 * e, 1.5) * tilt(fc, -3.0) * 1.3
		cloth = env_ad(t - 0.1, 0.03, 0.12) * bp_shape(fc, 1500.0, 2.4) * 0.5
		return low + cloth

	S.place(out, nz(1.0, gain, rng, fmin=30.0), 0.0)
	S.place(out, thump(85.0, 48.0, 0.7, 0.5, 0.08), 0.13, 0.9)
	c = S.creak(0.4, rng, pitch=(70, 140), body_lo=500, body_hi=3000, groan=0.2)
	S.place(out, c / (np.abs(c).max() + 1e-9), 0.4 + 0.1 * rng.uniform(), 0.1)
	return out


def rope_creak(rng, v):
	x = S.creak(rng.uniform(0.35, 0.75), rng, pitch=(rng.uniform(60, 90), rng.uniform(120, 190)),
				body_lo=rng.uniform(450, 700), body_hi=rng.uniform(2600, 3600), groan=0.15, bursts=3.0)
	return x


def capstan_clank(rng, v):
	out = buf(0.6)
	S.place(out, metal_hit(rng, rng.uniform(480, 700), 0.28, 9, 0.55, 0.45), 0.0, 1.3)
	S.place(out, wood_hit(rng, rng.uniform(110, 150), 0.12, 6, 5.0, 0.3), 0.004, 0.9)
	return out


def wheel_creak(rng, v):
	out = buf(0.75)
	c = S.creak(rng.uniform(0.3, 0.5), rng, pitch=(rng.uniform(45, 70), rng.uniform(100, 150)),
				body_lo=300, body_hi=rng.uniform(1800, 2600), groan=0.4, bursts=2.5)
	S.place(out, c / (np.abs(c).max() + 1e-9), 0.0, 0.8)
	S.place(out, wood_hit(rng, rng.uniform(380, 520), 0.05, 5, 4.0, 0.15), len(c) / S.SR - 0.02, 0.5)
	return out


def anchor_drop(rng, v):
	"""Chain running out through the hawse: clanks that speed up, then stop dead."""
	dur = 2.3
	out = buf(dur + 0.4)
	t = 0.0
	while t < dur:
		u = t / dur
		link = metal_hit(rng, rng.uniform(650, 1150), rng.uniform(0.05, 0.1), 7, 0.5, 0.18)
		S.place(out, link, t, rng.uniform(0.5, 1.0) * (0.6 + 0.4 * u))
		t += 1.0 / (8.0 + 16.0 * u ** 0.7) * rng.uniform(0.75, 1.25)
	rum = nz(dur, lambda fc, tt: np.clip(tt / dur, 0, 1) ** 0.5 * (tt < dur - 0.05) * lp_shape(fc, 260.0, 2) * tilt(fc, -3.0),
			 rng, fmin=30, fmax=2000)
	S.place(out, rum, 0.0, 0.6)
	S.place(out, wood_hit(rng, 85.0, 0.2, 7, 6.0, 0.4), dur, 1.6)
	S.place(out, metal_hit(rng, 420.0, 0.2, 8, 0.6, 0.35), dur, 0.9)
	return room(out, 0.1, 0.5)


def anchor_splash(rng, v):
	return splash(rng, 1.0, 2.6)


def hold_slosh(rng, v):
	"""Bilge water rolling across the hold: two overlapping laps and gurgles."""
	dur = rng.uniform(1.1, 1.6)
	a, b = rng.uniform(260, 360), rng.uniform(650, 950)
	c2 = rng.uniform(0.55, 0.7)

	def gain(fc, t):
		u = np.clip(t / dur, 0, 1)
		e1 = np.exp(-0.5 * ((u - 0.25) / 0.13) ** 2)
		e2 = 0.8 * np.exp(-0.5 * ((u - c2) / 0.16) ** 2)
		return (e1 * bp_shape(fc, a + (b - a) * np.clip(u / 0.3, 0, 1), 2.0)
				+ e2 * bp_shape(fc, b - (b - a) * 0.6 * np.clip((u - 0.4) / 0.5, 0, 1), 2.4)) * tilt(fc, -2.0)

	out = nz(dur, gain, rng)
	out /= np.abs(out).max()
	lap = lambda u: np.exp(-0.5 * ((u - 0.3) / 0.12) ** 2) + np.exp(-0.5 * ((u - c2 - 0.05) / 0.14) ** 2)
	out += S.bubbles(dur, 34, rng, 200, 1300, t60=(0.03, 0.11), density_env=lap) * 0.8
	return room(out, 0.22, 0.6, 0.7, 3)


def bucket_splash(rng, v):
	out = buf(1.5)
	sw = nz(0.3, lambda fc, t: np.sin(np.pi * np.clip(t / 0.3, 0, 1)) ** 2 * bp_shape(fc, 500.0 + 3000.0 * t, 2.0) * tilt(fc, -1.5), rng)
	S.place(out, sw, 0.0, 0.5)
	S.place(out, splash(rng, rng.uniform(0.45, 0.6), 1.1), 0.24, 1.0)
	return out


def hammer_plank(rng, v):
	out = buf(0.5)
	S.place(out, wood_hit(rng, rng.uniform(170, 250), 0.12, 8, 6.0, 0.4, knock=0.6), 0.0, 1.0)
	S.place(out, metal_hit(rng, rng.uniform(2100, 3100), 0.1, 4, 0.8, 0.2, tick=0.4), 0.0, 0.12)
	S.place(out, thump(120.0, 70.0, 0.2, 0.12), 0.0, 0.5)
	return room(out, 0.08, 0.4)


# ----------------------------------------------------------------------------
# Guns
# ----------------------------------------------------------------------------
def cannon_fire(rng, v):
	"""Sharp broadband crack, a blast that darkens within 100 ms, a boom that
	slides down to 40 Hz, then the report rolling away over open water."""
	k = rng.uniform(0.92, 1.08)
	out = buf(1.6)
	n = len(out)
	t = S.tgrid(n)
	crack = S.highpass(S.white(n, rng), 700.0) * np.exp(-t / 0.011)
	blast = nz(1.2, lambda fc, tt: env_ad(tt, 0.002, 0.16) * lp_shape(fc, 350.0 + 6000.0 * np.exp(-tt / 0.045), 1.5)
			   * tilt(fc, -3.0), rng, fmin=30.0)
	out += crack * 0.9
	S.place(out, blast, 0.0, 2.2)
	S.place(out, thump(160.0 * k, 41.0 * k, 1.5, 1.0, 0.07), 0.0, 1.5)
	S.place(out, thump(95.0 * k, 33.0 * k, 1.5, 0.7, 0.12), 0.012, 0.8)
	out = S.soft_clip(out, 2.4)
	wet = S.to_mono(S.reverb(out, wet=1.0, dry=0.0, t60=3.0, damp=0.8, predelay=0.07, seed=11 + v))
	wet = S.lowpass(wet, 1800.0, 1)
	full = buf(3.6)
	S.place(full, out, 0.0)
	S.place(full, wet, 0.0, 0.55)
	for d, g, cut in ((0.42 + 0.05 * v, 0.3, 800.0), (0.95, 0.16, 450.0)):
		S.place(full, S.lowpass(out, cut, 2), d, g)
	return full


def pistol_shot(rng, v):
	"""Flintlock: the flint snaps, the pan fizzes, then the bang."""
	out = buf(0.9)
	S.place(out, metal_hit(rng, rng.uniform(2600, 3400), 0.03, 5, 0.5, 0.06, tick=0.6), 0.0, 0.12)
	S.place(out, nz(0.05, lambda fc, tt: np.clip(tt / 0.04, 0, 1) ** 2 * hp_shape(fc, 2500.0), rng), 0.004, 0.05)
	b = buf(0.6)
	n = len(b)
	t = S.tgrid(n)
	b += S.highpass(S.white(n, rng), 900.0) * np.exp(-t / 0.006) * 0.9
	S.place(b, nz(0.5, lambda fc, tt: env_ad(tt, 0.001, 0.06) * lp_shape(fc, 500.0 + 7000.0 * np.exp(-tt / 0.03), 1.5)
			  * tilt(fc, -2.5), rng), 0.0, 1.6)
	S.place(b, thump(230.0, 85.0, 0.4, 0.2, 0.03), 0.0, 0.9)
	S.place(out, S.soft_clip(b, 2.0), 0.045)
	wet = S.lowpass(S.to_mono(S.reverb(out, wet=1.0, dry=0.0, t60=1.4, damp=0.7, predelay=0.04, seed=21)), 3000.0, 1)
	full = buf(2.0)
	S.place(full, out, 0.0)
	S.place(full, wet, 0.0, 0.35)
	return full


def cannonball_whistle(rng, v):
	dur = rng.uniform(1.0, 1.3)
	f_hi, f_lo = rng.uniform(1000, 1250), rng.uniform(520, 640)
	n = S.sec(dur)
	u = S.tgrid(n) / dur
	f = f_lo + (f_hi - f_lo) / (1.0 + np.exp((u - 0.62) * 9.0))
	amp = np.exp(-0.5 * ((u - 0.62) / 0.2) ** 2) * np.clip((1.0 - u) / 0.2, 0, 1)
	fn = lambda fc, t: np.interp(t, S.tgrid(n)[::32], amp[::32]) * (
		bp_shape(fc, np.interp(t, S.tgrid(n)[::32], f[::32]), 0.6) + 0.12 * bp_shape(fc, 500.0, 3.0))
	x = S.tf_noise(n, fn, rng, per_oct=6.0)
	x /= np.abs(x).max()
	tone = np.sin(S.phase(f * (1.0 + 0.004 * S.lfo_noise(n, 25, rng, False)), n)) * amp
	return x + 0.25 * tone


def hull_impact(rng, v):
	out = buf(0.9)
	S.place(out, thump(120.0, 52.0, 0.5, 0.3, 0.04), 0.0, 1.3)
	S.place(out, nz(0.25, lambda fc, t: env_ad(t, 0.002, 0.035) * lp_shape(fc, 3200.0, 1.5) * tilt(fc, -2.0), rng), 0.0, 1.2)
	cnt = int(rng.integers(10, 16))
	for i in range(cnt):
		t = rng.exponential(0.07) if i else 0.0
		if t > 0.55:
			continue
		S.place(out, wood_hit(rng, rng.uniform(230, 950), rng.uniform(0.03, 0.07), 6, 5.0, 0.2, knock=0.5), t,
				rng.uniform(0.3, 1.0) * np.exp(-t / 0.2))
	return room(S.soft_clip(out, 1.6), 0.12, 0.6)


# ----------------------------------------------------------------------------
# Water
# ----------------------------------------------------------------------------
def splash_large(rng, v):
	return splash(rng, rng.uniform(0.85, 1.0))


def splash_small(rng, v):
	return splash(rng, rng.uniform(0.12, 0.3))


# ----------------------------------------------------------------------------
# Combat
# ----------------------------------------------------------------------------
def sword_swing(rng, v):
	dur = rng.uniform(0.26, 0.36)
	lo, hi = rng.uniform(320, 480), rng.uniform(1500, 2100)

	def gain(fc, t):
		u = np.clip(t / dur, 0, 1)
		e = np.sin(np.pi * u ** 0.8) ** 2
		c = lo * (hi / lo) ** (np.sin(np.pi * u ** 0.9) ** 1.5)
		return e * (bp_shape(fc, c, 1.3) + 0.15 * bp_shape(fc, 2.6 * c, 1.5))

	return nz(dur, gain, rng, per_oct=5.0)


def sword_clash(rng, v):
	out = buf(0.9)
	b = rng.uniform(850, 1300)
	S.place(out, metal_hit(rng, b, rng.uniform(0.35, 0.6), 13, 0.5, 0.85, tick=0.5), 0.0, 1.0)
	S.place(out, metal_hit(rng, b * rng.uniform(1.2, 1.45), rng.uniform(0.3, 0.5), 11, 0.55, 0.85, tick=0.3), 0.0015, 0.7)
	scr = nz(0.09, lambda fc, t: env_ad(t, 0.005, 0.03) * bp_shape(fc, 4200.0, 1.4), rng)
	S.place(out, scr * S.grain_env(len(scr), 500.0, rng, 0.001, 0.8), 0.01, 0.12)
	S.place(out, thump(300.0, 180.0, 0.05, 0.03), 0.0, 0.3)
	return out


def parry_ring(rng, v):
	out = buf(1.7)
	b = rng.uniform(1450, 1850)
	fr, td, am = S.metal_modes(rng, b, 9, 1.5, 0.95)
	fr = np.concatenate([fr, fr * 1.004])
	S.place(out, S.modal(fr, np.tile(td, 2), np.tile(am, 2), 1.6, rng), 0.0, 0.8)
	shing = nz(0.16, lambda fc, t: np.sin(np.pi * np.clip(t / 0.16, 0, 1)) ** 2 * bp_shape(fc, 2800.0 * 2.0 ** (t / 0.16), 0.9), rng, per_oct=5.0)
	S.place(out, shing, 0.0, 0.3)
	S.place(out, click(rng, 0.002, 1500, 8000), 0.0, 0.5)
	return out


def ship_bell(rng, v):
	"""Cast-bronze maritime ship's bell: rich minor-third bell partials, crisp
	brass clapper strike click, gentle bronze beating shimmer, and sea-air tail."""
	dur = 2.65
	out = buf(dur)
	f0 = rng.uniform(620.0, 690.0)
	ratios = np.array([0.50, 1.00, 1.188, 1.50, 2.00, 2.51, 3.01]) * rng.uniform(0.996, 1.004, 7)
	t60 = np.array([2.45, 2.15, 1.75, 1.25, 1.55, 0.72, 0.45]) * rng.uniform(0.92, 1.08, 7)
	amps = np.array([0.52, 1.00, 0.74, 0.46, 0.82, 0.34, 0.22])
	fr = f0 * ratios
	# Pair slightly detuned cast-bronze doublets for authentic maritime shimmer beating.
	fr_pair = np.concatenate([fr, fr * rng.uniform(1.0012, 1.0032, len(fr))])
	td_pair = np.concatenate([t60, t60 * 0.88])
	am_pair = np.concatenate([amps, amps * 0.42])
	S.place(out, S.modal(fr_pair, td_pair, am_pair, dur - 0.05, rng), 0.0, 0.92)
	S.place(out, click(rng, 0.0022, 1800, 7500), 0.0, 0.65)
	S.place(out, thump(520.0, 220.0, 0.04, 0.025), 0.0, 0.22)
	return room(out, 0.14, 0.65)


def hit_flesh(rng, v):
	out = buf(0.4)
	S.place(out, thump(rng.uniform(130, 170), rng.uniform(55, 70), 0.3, 0.14, 0.025), 0.0, 1.2)
	S.place(out, nz(0.15, lambda fc, t: env_ad(t, 0.002, 0.022) * lp_shape(fc, 1100.0, 1.5) * hp_shape(fc, 120.0) * tilt(fc, -2.0), rng), 0.0, 1.3)
	if v % 2:  # bone
		S.place(out, wood_hit(rng, rng.uniform(800, 1100), 0.035, 4, 3.0, 0.12, knock=0.6), 0.004, 0.35)
	return out


def skeleton_rattle(rng, v):
	out = buf(0.75)
	for i in range(int(rng.integers(7, 12))):
		base = rng.uniform(650, 1700)
		x = S.modal(base * np.array([1.0, 2.76, 5.4]), [rng.uniform(0.03, 0.06), 0.025, 0.012], [1.0, 0.45, 0.2], 0.1, rng)
		S.place(x, click(rng, 0.001, 1000, 6000), 0.0, 0.25)
		S.place(out, x, rng.uniform(0, 0.5) ** 1.2, rng.uniform(0.3, 1.0))
	return room(out, 0.1, 0.3)


# ----------------------------------------------------------------------------
# Feet, loot, tools
# ----------------------------------------------------------------------------
def footstep_wood(rng, v):
	out = buf(0.4)
	S.place(out, wood_hit(rng, rng.uniform(90, 130), 0.1, 6, 6.0, 0.25, knock=0.25), 0.0, 1.0)
	S.place(out, S.lowpass(click(rng, 0.012, 150, 1200), 900.0), 0.0, 0.4)
	S.place(out, wood_hit(rng, rng.uniform(150, 210), 0.06, 5, 5.0, 0.15, knock=0.2), rng.uniform(0.07, 0.1), 0.4)
	return out


def footstep_sand(rng, v):
	out = buf(0.4)
	for t0, a in ((0.0, 1.0), (rng.uniform(0.08, 0.11), 0.6)):
		c = rng.uniform(1100, 1900)
		x = nz(0.2, lambda fc, t, c=c: env_ad(t, 0.012, 0.045) * bp_shape(fc, c, 3.0) * tilt(fc, -1.5), rng)
		S.place(out, x * S.grain_env(len(x), 1400.0, rng, 0.0015, 0.85), t0, a)
	S.place(out, thump(95.0, 60.0, 0.12, 0.07), 0.0, 0.25)
	return out


def footstep_water(rng, v):
	out = buf(0.7)
	S.place(out, splash(rng, rng.uniform(0.14, 0.24), 0.6), 0.0, 1.0)
	S.place(out, S.bubble(S.sec(0.12), rng.uniform(280, 480), rng, 0.8, 0.08), 0.02, 0.35)
	return out


def chest_thump(rng, v):
	out = buf(0.8)
	S.place(out, wood_hit(rng, rng.uniform(68, 90), 0.2, 8, 7.0, 0.45, knock=0.4), 0.0, 1.0)
	S.place(out, thump(95.0, 48.0, 0.3, 0.2), 0.0, 0.7)
	for i in range(3):
		S.place(out, metal_hit(rng, rng.uniform(1500, 2400), 0.06, 5, 0.7, 0.12), rng.uniform(0.02, 0.16), rng.uniform(0.05, 0.14))
	for i in range(5):
		S.place(out, coin(rng), rng.uniform(0.03, 0.3), rng.uniform(0.01, 0.035))
	return out


def coin(rng) -> np.ndarray:
	base = rng.uniform(4300, 6400)
	r = np.array([1.0, 2.32, 3.9, 5.7]) * rng.uniform(0.98, 1.02, 4)
	return S.modal(base * r, np.array([1.0, 0.6, 0.4, 0.25]) * rng.uniform(0.12, 0.26), [1.0, 0.5, 0.25, 0.1], 0.3, rng)


def coin_jingle(rng, v):
	out = buf(0.8)
	for i in range(int(rng.integers(6, 11))):
		S.place(out, coin(rng), rng.uniform(0, 0.38) ** 1.3 * 1.2, rng.uniform(0.3, 1.0))
	return out


def dig_sand(rng, v):
	out = buf(1.1)
	d = rng.uniform(0.3, 0.4)
	scr = nz(d, lambda fc, t: np.clip(t / d, 0, 1) ** 1.5 * (t < d) * bp_shape(fc, 800.0 + 1600.0 * t / d, 2.2) * tilt(fc, -1.5), rng)
	S.place(out, scr * S.grain_env(len(scr), 700.0, rng, 0.002, 0.9), 0.0, 1.0)
	S.place(out, thump(125.0, 68.0, 0.2, 0.11), d - 0.03, 0.8)
	S.place(out, metal_hit(rng, rng.uniform(900, 1300), 0.07, 6, 0.9, 0.12), d - 0.03, 0.08)
	toss = nz(0.4, lambda fc, t: env_ad(t, 0.04, 0.1) * hp_shape(fc, 1800.0) * lp_shape(fc, 7000.0), rng)
	S.place(out, toss * S.grain_env(len(toss), 500.0, rng, 0.002, 1.0), d + 0.22, 0.3)
	return out


def spyglass_slide(rng, v):
	"""v even: extend (tube lengthens, pitch falls). v odd: collapse."""
	d = rng.uniform(0.2, 0.26)
	a, b = (2700.0, 1300.0) if v % 2 == 0 else (1300.0, 2700.0)
	out = buf(d + 0.2)
	fr = nz(d, lambda fc, t: np.sin(np.pi * np.clip(t / d, 0.02, 0.98)) ** 0.5 * (bp_shape(fc, a * (b / a) ** (t / d), 0.7)
			+ 0.15 * bp_shape(fc, 3000.0, 3.0)), rng, per_oct=6.0)
	S.place(out, fr * S.grain_env(len(fr), 450.0, rng, 0.002, 0.7), 0.0, 1.0)
	S.place(out, metal_hit(rng, rng.uniform(2000, 2600), 0.05, 5, 0.8, 0.1, tick=0.5), d - 0.01, 0.5)
	S.place(out, thump(260.0, 170.0, 0.06, 0.04), d - 0.01, 0.5)
	return out


def lantern_click(rng, v):
	out = buf(0.5)
	S.place(out, metal_hit(rng, rng.uniform(2300, 2900), 0.035, 5, 0.7, 0.08, tick=0.6), 0.0, 0.8)
	S.place(out, metal_hit(rng, rng.uniform(1700, 2100), 0.045, 5, 0.7, 0.08, tick=0.5), 0.055, 1.0)
	if v % 2 == 0:  # lit: the wick catches
		S.place(out, nz(0.3, lambda fc, t: np.sin(np.pi * np.clip(t / 0.3, 0, 1)) ** 2 * lp_shape(fc, 700.0, 1.5) * tilt(fc, -2.0), rng), 0.1, 0.25)
	else:  # snuffed
		S.place(out, nz(0.12, lambda fc, t: env_ad(t, 0.01, 0.03) * bp_shape(fc, 1800.0, 2.5), rng), 0.1, 0.12)
	return out


def ui_tick(rng, v):
	return S.modal(np.array([1150.0, 2480.0, 3900.0]) * (1.0 + 0.12 * v), [0.035, 0.02, 0.012], [1.0, 0.4, 0.15], 0.08, rng)


def _ui_pluck(notes, rng):
	out = buf(0.5)
	for i, nme in enumerate(notes):
		S.place(out, S.karplus_strong(float(S.midi_hz(S.note_midi(nme))), 0.4, rng, t60=0.5, bright=0.28), i * 0.075, 0.9)
	return out


def ui_select(rng, v):
	return _ui_pluck(["D5", "A5"], rng)


def ui_back(rng, v):
	return _ui_pluck(["A5", "D5"], rng)


def ui_open(rng, v):
	"""Parchment unrolled."""
	x = nz(0.3, lambda fc, t: np.sin(np.pi * np.clip(t / 0.3, 0, 1)) ** 1.5 * bp_shape(fc, 1300.0 + 1800.0 * t, 2.2) * tilt(fc, -1.5), rng)
	return x * S.grain_env(len(x), 350.0, rng, 0.0015, 1.0)


# ----------------------------------------------------------------------------
# Weather and wildlife
# ----------------------------------------------------------------------------
def _rumble(dur: float, rng, cut0: float, cut1: float, humps: int, attack: float) -> np.ndarray:
	centres = np.sort(rng.uniform(0.0, 0.6, humps)) * dur
	widths = rng.uniform(0.25, 0.7, humps)
	amps = rng.uniform(0.4, 1.0, humps) * np.exp(-centres / (dur * 0.45))

	def gain(fc, t):
		e = sum(a * np.exp(-0.5 * ((t - c) / w) ** 2) for a, c, w in zip(amps, centres, widths))
		e = e * np.clip(t / attack, 0, 1) + 0.25 * np.exp(-t / (dur * 0.3)) * np.clip(t / attack, 0, 1)
		e = e * np.clip((dur - t) / (dur * 0.35), 0, 1)
		return e * lp_shape(fc, cut1 + (cut0 - cut1) * np.exp(-t / 0.7), 1.5) * tilt(fc, -4.0)

	return nz(dur, gain, rng, fmin=25.0, fmax=8000.0)


def thunder_near(rng, v):
	dur = 6.5
	out = buf(dur)
	n = S.sec(0.6)
	t = S.tgrid(n)
	crack = np.zeros(n)
	for i in range(int(rng.integers(3, 6))):
		t0 = rng.uniform(0, 0.3) if i else 0.0
		crack += S.highpass(S.white(n, rng), 250.0) * (t >= t0) * np.exp(-np.maximum(t - t0, 0) / rng.uniform(0.02, 0.06)) * rng.uniform(0.5, 1.0)
	S.place(out, S.lowpass(crack, 7000.0), 0.0, 0.8)
	r = _rumble(dur, rng, 3000.0, 220.0, 6, 0.03)
	S.place(out, r / np.abs(r).max(), 0.0, 1.6)
	S.place(out, thump(90.0, 38.0, 1.2, 1.0, 0.1), 0.02, 0.6)
	out = S.soft_clip(out, 1.8)
	return S.fade(room(out, 0.3, 3.0, 0.8, 5, 0.05)[:S.sec(dur + 1.5)], 0.001, 1.5)


def thunder_far(rng, v):
	dur = 8.0
	r = _rumble(dur, rng, 500.0, 160.0, 5, 0.7)
	return S.fade(room(r, 0.4, 3.0, 0.9, 6, 0.08)[:S.sec(dur + 1.0)], 0.3, 2.0)


def gull_note(rng, dur: float, peak_hz: float, vel: float = 1.0) -> np.ndarray:
	"""One gull cry: pitch jumps up fast then slides down (the falling 'keow'),
	a pulse-like source with its energy between 1.5 and 4 kHz, and a rasp."""
	n = S.sec(dur)
	u = S.tgrid(n) / dur
	rise = 0.16
	f = np.where(u < rise, peak_hz * (0.72 + 0.28 * np.sin(0.5 * np.pi * u / rise)),
				 peak_hz * (1.0 - 0.42 * (np.maximum(u - rise, 0) / (1 - rise)) ** 1.4))
	f = f * (1.0 + 0.012 * S.lfo_noise(n, 30.0, rng, False))

	def spec(k, fk, t):
		return (0.5 / k + 0.8 * bp_shape(fk, 2100.0, 1.2) + 0.5 * bp_shape(fk, 1200.0, 0.9)) * lp_shape(fk, 4500.0, 2)

	x = S.additive(f, n, spec, kmax=14, phases=rng.uniform(0, S.TAU, 14))
	rasp = 1.0 + 0.35 * np.sin(S.phase(rng.uniform(55, 85), n)) * np.clip(u * 3, 0, 1)
	env = np.clip(u / 0.08, 0, 1) ** 0.7 * np.clip((1 - u) / 0.3, 0, 1) ** 1.2
	x = x * env * rasp
	x += S.bandpass(S.white(n, rng), 1800, 5000) * env * 0.03 * np.abs(x).max()
	return x / (np.abs(x).max() + 1e-9) * vel


def seagull(rng, v):
	out = buf(3.0)
	base = rng.uniform(820, 1000)
	if v % 4 == 0:  # long call then a run of short ones
		S.place(out, gull_note(rng, 0.55, base * 1.05), 0.0)
		t = 0.7
		for i in range(4):
			S.place(out, gull_note(rng, 0.2, base * (0.98 - 0.03 * i), 0.85 - 0.1 * i), t)
			t += 0.26
	elif v % 4 == 1:  # laughing run that speeds up and sinks
		t = 0.0
		for i in range(7):
			S.place(out, gull_note(rng, 0.17 - 0.008 * i, base * (1.08 - 0.035 * i), 1.0 - 0.07 * i), t)
			t += 0.24 - 0.018 * i
	elif v % 4 == 2:  # two long mews
		S.place(out, gull_note(rng, 0.7, base * 0.92), 0.0)
		S.place(out, gull_note(rng, 0.8, base * 0.86, 0.8), 0.95)
	else:  # one distant cry
		S.place(out, gull_note(rng, 0.65, base), 0.0)
	out = S.lowpass(out, 6000.0, 1)
	return room(out, 0.25, 1.2, 0.5, 9, 0.03)


def whale_call(rng, v):
	"""Haunting deep-ocean humpback song phrase: smooth biological pitch contour,
	warm rolling harmonics, muffled water-column breath, and spacious ocean reverb."""
	dur = rng.uniform(2.50, 2.95)
	n = S.sec(dur)
	t = S.tgrid(n)
	u = t / dur
	scale = rng.uniform(0.95, 1.05)

	# Smoothly interpolated organic humpback glide contour varied by variation index.
	if v % 2 == 0:
		knots_u = np.array([0.0, 0.18, 0.42, 0.70, 1.0])
		knots_f = np.array([155.0, 245.0, 340.0, 215.0, 140.0]) * scale
	else:
		knots_u = np.array([0.0, 0.22, 0.50, 0.76, 1.0])
		knots_f = np.array([134.0, 265.0, 305.0, 182.0, 122.0]) * scale

	# Cosine-smooth interpolation between contour knots for natural vocal glide.
	f_curve = np.interp(u, knots_u, knots_f)
	win = max(5, S.sec(0.14) | 1)
	k_sm = np.hanning(win)
	k_sm /= k_sm.sum()
	f_smooth = np.convolve(np.pad(f_curve, win // 2, mode="edge"), k_sm, mode="valid")[:n]

	# Gentle biological vibrato (~4.5 Hz) + subtle slow organic drift.
	vib_rate = rng.uniform(4.2, 4.8)
	vib_env = np.sin(np.pi * u) ** 0.85
	drift = S.lfo_noise(n, 2.2, rng, False) * 0.014
	f_inst = f_smooth * (1.0 + 0.018 * vib_env * np.sin(2.0 * np.pi * vib_rate * t) + drift)

	# Warm harmonic series (1x..4x) whose overtones bloom gently around the phrase crest.
	phi = S.phase(f_inst, n)
	crest = np.sin(np.pi * u) ** 1.6
	voice = (
		1.00 * np.sin(phi)
		+ (0.46 + 0.18 * crest) * np.sin(2.0 * phi + 0.25)
		+ (0.18 + 0.10 * crest) * np.sin(3.0 * phi + 0.70)
		+ 0.07 * np.sin(4.0 * phi + 1.15)
	)
	amp_env = (np.clip(u / 0.16, 0.0, 1.0) ** 1.4) * (np.clip((1.0 - u) / 0.28, 0.0, 1.0) ** 1.35)
	amp_env *= 0.74 + 0.26 * crest
	voice = S.highpass(S.lowpass(voice * amp_env, 1450.0, 2), 45.0, 1)
	voice /= np.abs(voice).max() + 1e-9

	# Subtle muffled ocean breath resonance (280..650 Hz) following the phrase swell.
	bp_center = rng.uniform(320.0, 560.0)

	def breath_gain(fc, tt):
		uu = np.clip(tt / dur, 0.0, 1.0)
		be = (np.clip(uu / 0.18, 0.0, 1.0) ** 1.3) * (np.clip((1.0 - uu) / 0.30, 0.0, 1.0) ** 1.4)
		return be * bp_shape(fc, bp_center, 1.9) * lp_shape(fc, 1300.0, 2.0)

	breath = nz(dur, breath_gain, rng, fmin=80.0, fmax=2200.0)
	breath /= np.abs(breath).max() + 1e-9

	dry = buf(dur + 0.65)
	S.place(dry, voice + 0.11 * breath, 0.02)
	wet = room(dry, 0.34, 1.35, damp=0.72, seed=41 + v, predelay=0.025)
	wet = S.lowpass(wet, 1800.0, 1)
	return S.fade(wet, 0.04, 0.12)


# ----------------------------------------------------------------------------
# Crew: grog, burps, shouts
# ----------------------------------------------------------------------------
def grog_gulp(rng, v):
	out = buf(1.3)
	t = 0.0
	for i in range(int(rng.integers(2, 4))):
		n = S.sec(0.13)
		u = S.tgrid(n) / 0.13
		f = rng.uniform(170, 210) * (1.0 + 0.9 * u ** 1.5)
		g = np.sin(S.phase(f, n)) * np.sin(np.pi * u) ** 1.2 * (1.0 + 0.3 * np.sin(S.phase(38.0, n)))
		S.place(out, g, t, 1.0)
		S.place(out, nz(0.12, lambda fc, tt: np.sin(np.pi * np.clip(tt / 0.12, 0, 1)) ** 2 * bp_shape(fc, 900.0, 1.6), rng), t + 0.02, 0.12)
		S.place(out, S.bubbles(0.12, 4, rng, 400, 1200), t, 0.25)
		t += rng.uniform(0.21, 0.29)
	if v % 2 == 0:  # satisfied sigh
		n = S.sec(0.4)
		br = S.formant_bank(S.white(n, rng), [(730, 5, 1.0), (1090, 6, 0.6), (2440, 8, 0.25)])
		S.place(out, br / np.abs(br).max() * np.sin(np.pi * S.tgrid(n) / 0.4) ** 1.5, t + 0.05, 0.25)
	return out


def burp(rng, v):
	dur = rng.uniform(0.45, 0.65) if v % 2 == 0 else rng.uniform(0.8, 1.0)
	n = S.sec(dur)
	u = S.tgrid(n) / dur
	f0 = rng.uniform(78, 96)
	f = f0 * (1.0 - 0.25 * u + (0.35 * np.clip((u - 0.75) / 0.25, 0, 1) ** 2 if v % 2 else 0.0))
	f = f * (1.0 + 0.06 * S.lfo_noise(n, 9.0, rng, False))
	x = S.voice(f, n, [(0.0, "uh"), (0.5, "o"), (1.0, "u")], rng, rough=1.0, breath=0.12, size=1.12, tilt_exp=0.9)
	env = np.clip(u / 0.06, 0, 1) * np.clip((1 - u) / 0.25, 0, 1) ** 0.8
	flutter = 1.0 + 0.35 * np.sin(S.phase(rng.uniform(24, 32), n))
	x = x * env * flutter
	x = x / np.abs(x).max()
	x += S.bubbles(dur, 8, rng, 180, 500, t60=(0.03, 0.07)) * 0.2 * env
	return x


def shout(rng, word: str, voices: int = 4, dur: float = 0.42) -> np.ndarray:
	"""A few sailors shouting one syllable roughly together."""
	vow = {"hey": [(0.0, "e"), (0.55, "e"), (1.0, "i")], "ho": [(0.0, "o"), (0.6, "o"), (1.0, "u")],
		   "aye": [(0.0, "a"), (0.45, "a"), (1.0, "i")], "heave": [(0.0, "i"), (1.0, "i")]}[word]
	out = buf(dur + 0.25)
	for i in range(voices):
		d = dur * rng.uniform(0.85, 1.1)
		n = S.sec(d)
		u = S.tgrid(n) / d
		f0 = rng.uniform(118, 185)
		f = f0 * (0.9 + 0.32 * np.sin(np.pi * np.clip(u / 0.5, 0, 1) * 0.5) - 0.3 * np.clip((u - 0.4) / 0.6, 0, 1) ** 1.5)
		x = S.voice(f, n, vow, rng, rough=rng.uniform(0.15, 0.45), breath=0.06, size=rng.uniform(0.94, 1.1), tilt_exp=0.85)
		env = np.clip(u / 0.07, 0, 1) * np.clip((1 - u) / 0.35, 0, 1)
		x = x * env
		x /= np.abs(x).max() + 1e-9
		if word in ("hey", "ho", "heave"):  # the breathy 'h'
			h = S.formant_bank(S.white(S.sec(0.07), rng), [(S.FORMANTS[vow[0][1]][0], 4, 1.0), (S.FORMANTS[vow[0][1]][1], 5, 0.8)])
			h = S.fade(h / (np.abs(h).max() + 1e-9), 0.01, 0.03)
			x[:len(h)] += h * 0.2
		S.place(out, x, rng.uniform(0.0, 0.045), rng.uniform(0.6, 1.0))
	return out


def crew_shout(rng, v):
	return room(shout(rng, ["hey", "ho", "aye"][v % 3]), 0.12, 0.6)


# ----------------------------------------------------------------------------
# name: (recipe, variations, target LUFS (loudest 400 ms), unit_size m, max_distance m, bus)
# unit_size/max_distance are hints for AudioStreamPlayer3D; 0 means not positional.
SOUNDS = {
	"hull_creak": (hull_creak, 5, -24, 4, 40, "SFX"),
	"sail_flap": (sail_flap, 4, -20, 6, 70, "SFX"),
	"sail_fill": (sail_fill, 3, -18, 8, 90, "SFX"),
	"rope_creak": (rope_creak, 4, -26, 3, 25, "SFX"),
	"capstan_clank": (capstan_clank, 4, -24, 5, 50, "SFX"),
	"wheel_creak": (wheel_creak, 4, -26, 3, 25, "SFX"),
	"anchor_drop": (anchor_drop, 2, -19, 8, 120, "SFX"),
	"anchor_splash": (anchor_splash, 2, -16, 8, 120, "SFX"),
	"hold_slosh": (hold_slosh, 4, -24, 3, 25, "SFX"),
	"bucket_splash": (bucket_splash, 3, -20, 4, 40, "SFX"),
	"hammer_plank": (hammer_plank, 4, -25, 5, 60, "SFX"),
	"cannon_fire": (cannon_fire, 3, -12, 40, 1500, "SFX"),
	"cannonball_whistle": (cannonball_whistle, 3, -20, 8, 120, "SFX"),
	"hull_impact": (hull_impact, 3, -15, 15, 300, "SFX"),
	"splash_large": (splash_large, 3, -16, 10, 200, "SFX"),
	"splash_small": (splash_small, 4, -24, 3, 30, "SFX"),
	"sword_swing": (sword_swing, 4, -23, 3, 25, "SFX"),
	"sword_clash": (sword_clash, 4, -20, 5, 60, "SFX"),
	"parry_ring": (parry_ring, 2, -17, 5, 60, "SFX"),
	"ship_bell": (ship_bell, 3, -17, 10, 140, "SFX"),
	"hit_flesh": (hit_flesh, 4, -24, 4, 35, "SFX"),
	"skeleton_rattle": (skeleton_rattle, 4, -21, 4, 35, "SFX"),
	"pistol_shot": (pistol_shot, 3, -13, 20, 400, "SFX"),
	"footstep_wood": (footstep_wood, 6, -27, 2.5, 20, "SFX"),
	"footstep_sand": (footstep_sand, 6, -29, 2.5, 18, "SFX"),
	"footstep_water": (footstep_water, 6, -27, 2.5, 20, "SFX"),
	"chest_thump": (chest_thump, 3, -23, 4, 35, "SFX"),
	"coin_jingle": (coin_jingle, 4, -23, 3, 25, "SFX"),
	"dig_sand": (dig_sand, 4, -22, 3, 30, "SFX"),
	"spyglass_slide": (spyglass_slide, 2, -26, 0, 0, "SFX"),
	"lantern_click": (lantern_click, 2, -26, 2, 15, "SFX"),
	"ui_tick": (ui_tick, 3, -28, 0, 0, "SFX"),
	"ui_select": (ui_select, 1, -24, 0, 0, "SFX"),
	"ui_back": (ui_back, 1, -24, 0, 0, "SFX"),
	"ui_open": (ui_open, 2, -27, 0, 0, "SFX"),
	"thunder_near": (thunder_near, 2, -13, 0, 0, "SFX"),
	"thunder_far": (thunder_far, 2, -22, 0, 0, "SFX"),
	"seagull": (seagull, 4, -25, 12, 200, "SFX"),
	"whale_call": (whale_call, 2, -21, 25, 340, "SFX"),
	"grog_gulp": (grog_gulp, 3, -23, 2.5, 18, "Voice"),
	"burp": (burp, 3, -19, 3, 25, "Voice"),
	"crew_shout": (crew_shout, 3, -17, 6, 80, "Voice"),
}


def trim(x: np.ndarray, floor_db: float = -66.0) -> np.ndarray:
	"""Drop trailing near-silence (keeps files small) and fade the new end."""
	env = np.abs(x)
	idx = np.where(env > S.db(floor_db) * env.max())[0]
	end = min(len(x), (idx[-1] if len(idx) else 0) + S.sec(0.03))
	return x[:max(end, S.sec(0.05))]


def render(job) -> str:
	name, v, root = job
	fn, count, target = SOUNDS[name][:3]
	x = fn(S.seed_rng("sfx_" + name, v), v)
	x = S.dc_block(np.concatenate([x, np.zeros(64)]))
	x = S.fade(trim(x), 0.0005, 0.03)
	x = S.normalize(x, target, "peak400", ceiling_db=-1.0)
	x = S.fade(x, 0.0005, 0.005)
	S.write_wav(os.path.join(root, "sfx", "%s_%d.wav" % (name, v + 1)), x)
	return "  sfx/%s_%d.wav  %.2fs" % (name, v + 1, len(x) / S.SR)


def main() -> None:
	outdir = sys.argv[-1]
	man = S.Manifest(outdir)
	only = sys.argv[1:-1]
	jobs = [(name, v, man.root) for name, e in SOUNDS.items() if not only or name in only for v in range(e[1])]
	with multiprocessing.Pool(min(4, os.cpu_count() or 1)) as pool:
		for line in pool.imap(render, jobs, chunksize=2):
			print(line)
	for name, (fn, count, target, unit, maxd, bus) in SOUNDS.items():
		man.add("sfx", name, files=["sfx/%s_%d.wav" % (name, i + 1) for i in range(count)],
				lufs=target, unit_size=unit, max_distance=maxd, bus=bus)
	man.save()


if __name__ == "__main__":
	main()
