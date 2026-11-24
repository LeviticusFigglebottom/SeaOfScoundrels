#!/usr/bin/env python3
"""Ambience beds: seamless stereo loops the game crossfades by sea state, wind,
rain, depth and where the listener stands. Usage: gen_ambience.py <outdir>

Every loop is exactly periodic by construction: the noise is synthesised in the
frequency domain over the loop length, every modulator completes whole cycles,
and events (waves, creaks, drips) are mixed in with wrap-around.
"""
from __future__ import annotations

import multiprocessing
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import synth as S  # noqa: E402
from synth import bp_shape, hp_shape, lp_shape, tilt  # noqa: E402

LOOP_S = 30.0
N = S.sec(LOOP_S)


def swell(n: int, rng, cycles=(4, 7, 11), depth=(0.5, 0.3, 0.2)) -> np.ndarray:
	"""Periodic 0..1 swell: a few sines that each fit the loop a whole number of times."""
	t = np.arange(n) / n
	x = sum(d * np.sin(S.TAU * (c * t + rng.uniform())) for c, d in zip(cycles, depth))
	x = x / sum(depth)
	return 0.5 + 0.5 * x


def wave_event(rng, strength: float = 1.0, pre: float = 2.0, crash: float = 0.5, wash: float = 2.5,
			   bright: float = 1.0, fizz: float = 0.0, onset: float = 0.12) -> tuple:
	"""One breaking wave: a low roar that builds, a broadband crash, then a
	hiss that climbs in pitch as the foam thins. Returns (stereo clip, time of
	the crash inside the clip)."""
	dur = pre + crash * 2 + wash * 2.2 + (3.0 if fizz > 0 else 0.0)
	n = S.sec(dur)

	def gain(fc, t):
		dt = t - pre
		build = np.clip(1.0 + dt / pre, 0.0, 1.0) ** 2.2
		after = np.where(dt > 0, np.exp(-np.maximum(dt, 0) / (0.6 + crash)), 1.0)
		roar = build * after * lp_shape(fc, 180.0 + 650.0 * build * bright) * tilt(fc, -3.0) * 2.4
		pos = np.maximum(dt, 0.0)
		on = (dt > 0) * (1.0 - np.exp(-pos / onset))
		cr = on * np.exp(-pos / crash) * lp_shape(fc, 5500.0 * bright, 1.5) * hp_shape(fc, 120.0) * tilt(fc, -2.8) * 1.6
		centre = np.minimum(1300.0 * 2.0 ** (pos / (wash * 0.8)), 5200.0) * bright
		ws = on * (1.0 - np.exp(-pos / 0.25)) * np.exp(-pos / wash) * bp_shape(fc, centre, 2.6) * tilt(fc, -2.0) * 0.9
		fz = 0.0
		if fizz > 0:
			late = np.maximum(dt - wash * 0.6, 0.0)
			fz = fizz * (1.0 - np.exp(-late / 0.6)) * np.exp(-late / 1.6) * hp_shape(fc, 2600.0, 2) \
				* lp_shape(fc, 9000.0, 2) * 0.22
		return strength * (roar + cr + ws + fz)

	clip = S.tf_noise(n, gain, rng, channels=2, width=0.9)
	if fizz > 0:
		# retreating water over shingle: make the hiss granular late in the event
		t = S.tgrid(n) - pre
		g = S.grain_env(n, 900.0, rng, 0.003, 1.0)
		mix = np.clip((t - wash * 0.5) / 1.0, 0, 1) * 0.75
		hi = S.highpass(clip, 2200.0)
		clip = clip + (hi.T * (mix * (g - 1.0))).T
	return S.fade(clip, 0.05, 0.3), pre


def sea_calm(rng) -> np.ndarray:
	sw = swell(4096, rng)
	sw_fn = lambda t: np.interp(t, np.linspace(0, LOOP_S, len(sw), endpoint=False), sw, period=LOOP_S)

	def gain(fc, t):
		s = sw_fn(t)
		wash = (0.45 + 0.55 * s) * bp_shape(fc, 700.0 + 900.0 * s, 4.0) * tilt(fc, -3.0) * hp_shape(fc, 160.0, 1.0)
		deep = 0.1 * lp_shape(fc, 110.0, 2) * tilt(fc, -3.0)
		air = 0.05 * hp_shape(fc, 3000.0) * lp_shape(fc, 9000.0)
		return wash + deep + air

	bed = S.tf_noise(N, gain, rng, channels=2, width=1.0)
	out = bed / np.sqrt(np.mean(bed ** 2))
	# small laps against the hull: quick brightening swishes
	for _ in range(13):
		clip, t0 = wave_event(rng, strength=rng.uniform(0.25, 0.6), pre=rng.uniform(0.5, 1.0), crash=0.12,
							  wash=rng.uniform(0.5, 0.9), bright=rng.uniform(0.55, 0.85), onset=0.06)
		S.place(out, S.stereo_width(clip, 0.7) * np.array([rng.uniform(0.6, 1.0), rng.uniform(0.6, 1.0)]),
				rng.uniform(0, LOOP_S), 1.1, wrap=True)
	bub = S.bubbles(LOOP_S, 60, rng, 700, 3200, wrap=True)
	out += S.to_stereo(bub) * 0.05 + S.pan(S.bubbles(LOOP_S, 40, rng, 900, 3600, wrap=True), 0.5) * 0.03
	return out


def sea_rough(rng) -> np.ndarray:
	sw = swell(4096, rng, cycles=(3, 5, 8), depth=(0.5, 0.35, 0.25))
	sw_fn = lambda t: np.interp(t, np.linspace(0, LOOP_S, len(sw), endpoint=False), sw, period=LOOP_S)

	def gain(fc, t):
		s = sw_fn(t)
		roar = (0.5 + 0.5 * s) * lp_shape(fc, 500.0 + 500.0 * s, 1.2) * hp_shape(fc, 45.0) * tilt(fc, -3.2) * 1.3
		hiss = (0.25 + 0.5 * s * s) * bp_shape(fc, 2400.0, 3.0) * tilt(fc, -2.5) * 0.45
		return roar + hiss

	bed = S.tf_noise(N, gain, rng, channels=2, width=1.0)
	out = bed / np.sqrt(np.mean(bed ** 2))
	times = np.cumsum(rng.uniform(3.2, 5.6, 7))
	times = times / times[-1] * LOOP_S
	for i, t in enumerate(times):
		clip, t0 = wave_event(rng, strength=rng.uniform(0.7, 1.15), pre=rng.uniform(1.4, 2.4),
							  crash=rng.uniform(0.35, 0.7), wash=rng.uniform(1.6, 2.6), bright=rng.uniform(0.9, 1.2))
		bal = rng.uniform(-0.35, 0.35)
		S.place(out, clip * np.array([1.0 - max(bal, 0), 1.0 + min(bal, 0)]), t - t0, 1.5, wrap=True)
	return out


def _lfo_ctrl(rng, rate_hz: float, points: int = 6000):
	"""Periodic control-rate wander and a lookup function for tf_noise."""
	v = S.lfo_noise(points, rate_hz * LOOP_S / points * S.SR, rng)
	grid = np.linspace(0, LOOP_S, points, endpoint=False)
	return lambda t: np.interp(t, grid, v, period=LOOP_S)


def wind_light(rng) -> np.ndarray:
	out = np.zeros((N, 2))
	for p, centre in ((-0.7, 420.0), (0.0, 560.0), (0.7, 700.0)):
		wander = _lfo_ctrl(rng, 0.22)
		gust = _lfo_ctrl(rng, 0.3)

		def gain(fc, t, wander=wander, gust=gust, centre=centre):
			g = np.clip(0.55 + 0.45 * gust(t), 0.05, 1.2)
			c = centre * 2.0 ** (0.55 * wander(t) + 0.3 * (g - 0.5))
			return g * (bp_shape(fc, c, 2.4) * tilt(fc, -2.0) + 0.05 * hp_shape(fc, 2500.0) * lp_shape(fc, 8000.0))

		v = S.tf_noise(N, gain, rng, fmin=60.0)
		out += S.pan(v, p)
	return out


def wind_storm(rng) -> np.ndarray:
	out = np.zeros((N, 2))
	gust_all = _lfo_ctrl(rng, 0.25)
	for p, centre in ((-0.8, 300.0), (-0.25, 520.0), (0.3, 410.0), (0.8, 680.0)):
		wander = _lfo_ctrl(rng, 0.35)
		gust = _lfo_ctrl(rng, 0.5)

		def gain(fc, t, wander=wander, gust=gust, centre=centre):
			g = np.clip(0.65 + 0.3 * gust(t) + 0.3 * gust_all(t), 0.35, 1.4)
			c = centre * 2.0 ** (0.6 * wander(t) + 0.5 * (g - 0.6))
			howl = bp_shape(fc, c, 0.7) * 1.6  # narrow: the moan
			roar = lp_shape(fc, 900.0 + 1400.0 * g, 1.0) * hp_shape(fc, 50.0) * tilt(fc, -3.0) * 0.9
			return g * g * (howl + roar)

		out += S.pan(S.tf_noise(N, gain, rng, per_oct=4.0), p)
	# rigging whistle: thin tones that sing in the gusts
	t = S.tgrid(N)
	for p, base in ((-0.5, 880.0), (0.6, 1240.0)):
		wander = _lfo_ctrl(rng, 0.4)(t)
		g = np.clip(0.2 + 0.6 * _lfo_ctrl(rng, 0.45)(t) + 0.4 * gust_all(t), 0, 1) ** 3
		tone = S.periodic_tone(base * 2.0 ** (0.12 * wander + 0.1 * g))
		nb = S.shaped_noise(N, rng, None, 12.0)  # slow random amplitude: breathy, not pure
		out += S.pan(tone * g * (0.6 + 0.4 * nb / (np.abs(nb).max() + 1e-9)), p) * 0.05
	return out


def rain(rng) -> np.ndarray:
	dens = _lfo_ctrl(rng, 0.2)

	def gain(fc, t):
		d = 0.85 + 0.15 * dens(t)
		hiss = d * hp_shape(fc, 1500.0, 1.5) * lp_shape(fc, 8500.0, 1.5) * tilt(fc, -1.0)
		body = 0.25 * bp_shape(fc, 450.0, 2.0)
		return hiss + body

	out = S.tf_noise(N, gain, rng, channels=2, width=1.0)
	for c in range(2):
		out[:, c] *= S.grain_env(N, 5000.0, rng, 0.0012, 0.6)
	out /= np.sqrt(np.mean(out ** 2))
	# individual drops: near ones tick on wood and plip in water
	drops = np.zeros((N, 2))
	for _ in range(520):
		f0 = rng.uniform(1400, 5200)
		b = S.bubble(S.sec(0.03), f0, rng, rise=rng.uniform(-0.1, 0.5), t60=rng.uniform(0.006, 0.022))
		S.place(drops, b, rng.uniform(0, LOOP_S), rng.uniform(0.05, 0.5) ** 1.5, wrap=True, p=rng.uniform(-1, 1))
	for _ in range(90):
		fr, t60, am = S.wood_modes(rng, rng.uniform(260, 700), 5, 4.0, 0.035)
		S.place(drops, S.modal(fr, t60, am, 0.08, rng), rng.uniform(0, LOOP_S), rng.uniform(0.1, 0.4), wrap=True,
				p=rng.uniform(-1, 1))
	return out + drops * 0.9


def underwater(rng) -> np.ndarray:
	slow = _lfo_ctrl(rng, 0.15)

	def gain(fc, t):
		s = 0.7 + 0.3 * slow(t)
		rumble = s * lp_shape(fc, 140.0, 1.5) * tilt(fc, -4.0) * 1.0
		wash = 0.25 * bp_shape(fc, 380.0, 1.6) * (1.2 - s)
		return rumble + wash

	out = S.tf_noise(N, gain, rng, fmin=25.0, fmax=3000.0, channels=2, width=1.0)
	out /= np.sqrt(np.mean(out ** 2))
	t = S.tgrid(N)
	# the pressure in your ears: low tones that slowly breathe
	for f0, p in ((55.0, -0.3), (82.5, 0.3), (123.0, 0.0)):
		a = 0.5 + 0.5 * _lfo_ctrl(rng, 0.12)(t)
		out += S.pan(S.periodic_tone(np.full(N, f0) * (1.0 + 0.004 * _lfo_ctrl(rng, 0.3)(t))) * a, p) * 0.22
	# bubble streams in a few bursts
	centres = rng.uniform(0, 1, 5)
	dens = lambda u: sum(np.exp(-0.5 * ((((u - c + 0.5) % 1.0) - 0.5) / 0.035) ** 2) for c in centres) + 0.15
	for p in (-0.6, 0.6):
		b = S.bubbles(LOOP_S, 150, rng, 220, 1500, t60=(0.03, 0.14), density_env=dens, wrap=True)
		out += S.pan(b, p) * 0.8
	out = S.spectral_filter(out, lambda f: lp_shape(f, 1500.0, 2.0))
	return S.reverb(out, wet=0.5, t60=2.2, damp=0.85, seed=7, circular=True)


def shore_surf(rng) -> np.ndarray:
	def gain(fc, t):
		return lp_shape(fc, 500.0, 1.0) * hp_shape(fc, 60.0) * tilt(fc, -3.0) + 0.15 * bp_shape(fc, 2500.0, 2.5)

	bed = S.tf_noise(N, gain, rng, channels=2, width=1.0)
	out = bed / np.sqrt(np.mean(bed ** 2)) * 0.35
	for t, strength, bal in ((3.0, 1.0, -0.25), (10.4, 0.7, 0.3), (17.6, 0.92, 0.1), (25.3, 0.62, -0.1)):
		clip, t0 = wave_event(rng, strength=strength, pre=2.6, crash=0.55, wash=2.4, bright=1.0 + 0.15 * strength,
							  fizz=1.0, onset=0.2)
		S.place(out, clip * np.array([1.0 - max(bal, 0), 1.0 + min(bal, 0)]), t - t0, 1.6, wrap=True)
	return out


def below_deck(rng) -> np.ndarray:
	slow = _lfo_ctrl(rng, 0.2)

	def gain(fc, t):
		return (0.7 + 0.3 * slow(t)) * (lp_shape(fc, 170.0, 1.5) * hp_shape(fc, 50.0) * tilt(fc, -3.0) * 0.6
			+ 0.5 * bp_shape(fc, 450.0, 2.2))

	bed = S.tf_noise(N, gain, rng, fmin=28.0, fmax=4000.0, channels=2, width=1.0)
	out = bed / np.sqrt(np.mean(bed ** 2)) * 0.3
	dry = np.zeros((N, 2))
	# timbers working: long low groans and shorter knocks of strain
	for _ in range(9):
		c = S.creak(rng.uniform(0.9, 2.4), rng, pitch=(rng.uniform(18, 30), rng.uniform(45, 85)),
					body_lo=rng.uniform(140, 260), body_hi=rng.uniform(1100, 2200), groan=0.8)
		S.place(dry, c / (np.abs(c).max() + 1e-9), rng.uniform(0, LOOP_S), rng.uniform(0.9, 2.0), wrap=True,
				p=rng.uniform(-0.8, 0.8))
	for _ in range(7):
		fr, t60, am = S.wood_modes(rng, rng.uniform(70, 130), 6, 6.0, 0.16)
		S.place(dry, S.modal(fr, t60, am, 0.4, rng, attack=0.004), rng.uniform(0, LOOP_S), rng.uniform(0.4, 0.9),
				wrap=True, p=rng.uniform(-0.8, 0.8))
	# water slapping the outside of the hull
	for _ in range(8):
		d = rng.uniform(0.5, 0.9)
		g = lambda fc, t, d=d: np.sin(np.pi * np.clip(t / d, 0, 1)) ** 2 * lp_shape(fc, 260.0, 2) * tilt(fc, -3.0)
		S.place(dry, S.tf_noise(S.sec(d), g, rng, fmin=30, fmax=1500), rng.uniform(0, LOOP_S),
				rng.uniform(0.6, 1.2), wrap=True, p=rng.uniform(-0.9, 0.9))
	for _ in range(10):
		S.place(dry, S.bubble(S.sec(0.06), rng.uniform(1100, 2400), rng, 0.5, 0.03), rng.uniform(0, LOOP_S),
				rng.uniform(0.03, 0.08), wrap=True, p=rng.uniform(-0.6, 0.6))
	return out + S.reverb(dry, wet=0.35, t60=0.6, damp=0.7, seed=3, circular=True)


def hull_wash(rng) -> np.ndarray:
	gurgle = _lfo_ctrl(rng, 2.2)
	slow = _lfo_ctrl(rng, 0.25)

	def gain(fc, t):
		s = 0.8 + 0.2 * slow(t)
		rush = s * bp_shape(fc, 1100.0, 3.2) * tilt(fc, -2.5)
		gur = np.clip(0.5 + 0.5 * gurgle(t), 0, 1) * bp_shape(fc, 320.0, 1.4) * 0.8
		return rush + gur

	out = S.tf_noise(N, gain, rng, channels=2, width=1.0)
	out /= np.sqrt(np.mean(out ** 2))
	out += S.pan(S.bubbles(LOOP_S, 260, rng, 500, 2600, wrap=True), -0.4) * 0.08
	out += S.pan(S.bubbles(LOOP_S, 260, rng, 500, 2600, wrap=True), 0.4) * 0.08
	return out


# name: (function, target integrated LUFS, description)
LOOPS = {
	"sea_calm": (sea_calm, -27.0, "gentle wash and laps; fades out as sea state rises"),
	"sea_rough": (sea_rough, -21.0, "heavy rollers breaking; fades in with sea state"),
	"wind_light": (wind_light, -28.0, "soft moving air; low wind"),
	"wind_storm": (wind_storm, -21.0, "howling gusts and singing rigging; high wind"),
	"rain": (rain, -25.0, "steady rain with near drops"),
	"underwater": (underwater, -24.0, "muffled rumble, pressure tones, bubbles"),
	"shore_surf": (shore_surf, -23.0, "surf breaking on a beach, four waves per loop"),
	"below_deck": (below_deck, -27.0, "hold interior: timbers working, water on the hull"),
	"hull_wash": (hull_wash, -27.0, "water rushing past the hull; scales with ship speed"),
}


def _render(job) -> str:
	name, root = job
	fn, target, _ = LOOPS[name]
	x = fn(S.seed_rng("amb_" + name))
	x = S.normalize(x, target, "integrated", ceiling_db=-3.0)
	S.write_ogg(os.path.join(root, "ambience", name + ".ogg"), x, quality=4.0)
	return "  ambience/%s.ogg  %.1fs" % (name, len(x) / S.SR)


def main() -> None:
	outdir = sys.argv[-1]
	man = S.Manifest(outdir)
	only = [a for a in sys.argv[1:-1]]
	names = [n for n in LOOPS if not only or n in only]
	with multiprocessing.Pool(min(4, os.cpu_count() or 1)) as pool:
		for line in pool.imap(_render, [(n, man.root) for n in names]):
			print(line)
	for name, (fn, target, desc) in LOOPS.items():
		man.add("ambience", name, file="ambience/%s.ogg" % name, loop=True, lufs=target, about=desc)
	man.save()


if __name__ == "__main__":
	main()
