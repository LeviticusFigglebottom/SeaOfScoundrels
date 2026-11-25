#!/usr/bin/env python3
"""Listen with maths: measure every generated sound and draw its spectrogram.

Nobody on this project can audition the audio, so this is the ear.

  python3 tools/audio/analyze.py                  # table + flags for everything
  python3 tools/audio/analyze.py --png            # also spectrogram PNGs and family sheets
  python3 tools/audio/analyze.py --only cannon    # filter by substring
  python3 tools/audio/analyze.py --music          # pitch-track music against the score
  python3 tools/audio/analyze.py --strict         # exit 1 if any flag is raised

Reports per file: duration, peak, RMS, loudness (integrated LUFS for loops and
music, loudest-400-ms for one-shots), DC offset, clipped samples, spectral
centroid, the share of energy in the harsh 2-5 kHz band, start/end levels
(click risk) and, for loops, three seam tests across the wrap point.
Output goes to build/audio_report/ (git-ignored).
"""
from __future__ import annotations

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import synth as S  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
AUDIO = os.path.join(ROOT, "assets", "generated", "audio")
REPORT = os.path.join(ROOT, "build", "audio_report")


# ----------------------------------------------------------------------------
# Metrics
# ----------------------------------------------------------------------------
def stft_db(m: np.ndarray, win: int, hop: int) -> np.ndarray:
	if len(m) < win:
		m = np.concatenate([m, np.zeros(win - len(m))])
	w = np.hanning(win)
	idx = np.arange(0, len(m) - win + 1, hop)
	frames = np.stack([m[i:i + win] * w for i in idx])
	mag = np.abs(np.fft.rfft(frames, axis=1)) / (w.sum() / 2)
	return 20 * np.log10(np.maximum(mag, 1e-7))


def band_fraction(m: np.ndarray, lo: float, hi: float) -> float:
	p = np.abs(np.fft.rfft(m)) ** 2
	f = np.fft.rfftfreq(len(m), 1 / S.SR)
	return float(p[(f >= lo) & (f < hi)].sum() / (p.sum() + 1e-20))


def seam_metrics(x: np.ndarray) -> dict:
	"""How audible is the wrap from the last sample back to the first?"""
	m = S.to_mono(x)
	d = np.abs(np.diff(m))
	jump = abs(m[0] - m[-1]) / (np.percentile(d, 99) + 1e-9)
	k = S.sec(0.05)
	rms = lambda a: 20 * np.log10(np.sqrt(np.mean(a * a)) + 1e-9)
	nb = len(m) // k
	lv = np.array([rms(m[i * k:(i + 1) * k]) for i in range(nb)])
	adj = np.abs(np.diff(lv))
	e_seam = abs(rms(m[-k:]) - rms(m[:k]))
	win = 2048
	nf = len(m) // win
	fr = np.stack([m[i * win:(i + 1) * win] for i in range(nf)]) * np.hanning(win)
	sp = 20 * np.log10(np.abs(np.fft.rfft(fr, axis=1)) + 1e-5)
	sm = np.stack([np.convolve(r, np.ones(9) / 9, mode="same") for r in sp])
	dist = np.sqrt(np.mean((sm[1:] - sm[:-1]) ** 2, axis=1))
	last = m[-win:] * np.hanning(win)
	first = m[:win] * np.hanning(win)
	sl = np.convolve(20 * np.log10(np.abs(np.fft.rfft(last)) + 1e-5), np.ones(9) / 9, mode="same")
	sf = np.convolve(20 * np.log10(np.abs(np.fft.rfft(first)) + 1e-5), np.ones(9) / 9, mode="same")
	s_seam = np.sqrt(np.mean((sl - sf) ** 2))
	# a click at the seam is a broadband spike in the frame that straddles it
	wrapped = np.concatenate([m[-win // 2:], m[:win // 2]]) * np.hanning(win)
	f = np.fft.rfftfreq(win, 1 / S.SR)
	hf = lambda frame: 10 * np.log10(np.sum(np.abs(np.fft.rfft(frame))[f > 9000] ** 2) + 1e-12)
	hfs = np.array([hf(r) for r in fr])
	return {
		"seam_jump": float(jump),  # sample step at wrap / typical 99th pct step; <= 1 is invisible
		"seam_energy_db": float(e_seam),  # level change across wrap (50 ms windows)
		"seam_energy_typ": float(np.percentile(adj, 90)),  # what adjacent windows normally do
		"seam_spec": float(s_seam),  # spectral distance across wrap (dB rms)
		"seam_spec_typ": float(np.percentile(dist, 90)),
		"seam_hf_excess_db": float(hf(wrapped) - np.percentile(hfs, 95)),  # > 6 means a click...
		# ...if it is also loud enough to hear: its level against the loop's own broadband level
		"seam_hf_rel_db": float(hf(wrapped) - 10 * np.log10(np.mean(np.sum(np.abs(np.fft.rfft(fr, axis=1)) ** 2, axis=1)) + 1e-12)),
	}


def measure(path: str, loop: bool, kind: str) -> dict:
	x = S.read_audio(path)
	m = S.to_mono(x)
	n = len(m)
	spec = np.abs(np.fft.rfft(m)) ** 2
	f = np.fft.rfftfreq(n, 1 / S.SR)
	k1 = max(1, S.sec(0.001))
	peak = float(np.max(np.abs(x)))
	out = {
		"file": os.path.relpath(path, AUDIO), "kind": kind, "loop": loop,
		"dur": n / S.SR, "ch": 1 if x.ndim == 1 else x.shape[1],
		"peak_db": float(S.to_db(peak)),
		"rms_db": float(S.to_db(np.sqrt(np.mean(m * m)))),
		"lufs": S.lufs(x) if (loop or kind in ("music", "ambience")) else S.lufs_peak(x),
		"dc": float(np.mean(m)),
		"clipped": int(np.sum(np.abs(x) >= 0.9999)),
		"centroid": float(np.sum(f * spec) / (np.sum(spec) + 1e-20)),
		"harsh": band_fraction(m, 2000, 5000),
		"low": band_fraction(m, 0, 200),
		"start_db": float(S.to_db(np.max(np.abs(m[:2])))),  # first samples: a jump from silence clicks
		"end_db": float(S.to_db(np.max(np.abs(m[-k1:])))),
		"bytes": os.path.getsize(path),
	}
	if x.ndim == 2:
		a, b = x[:, 0], x[:, 1]
		out["lr_corr"] = float(np.sum(a * b) / (np.sqrt(np.sum(a * a) * np.sum(b * b)) + 1e-12))
	if loop:
		out.update(seam_metrics(x))
	flags = []
	if out["clipped"]:
		flags.append("CLIP")
	if out["peak_db"] > -0.5:
		flags.append("NO_HEADROOM")
	if abs(out["dc"]) > 0.003:
		flags.append("DC")
	if not loop:
		if out["start_db"] > -40:
			flags.append("CLICK_START")
		if out["end_db"] > -45:
			flags.append("CLICK_END")
	elif kind == "music":
		# music changes across the wrap by design (a cadence, then a downbeat), so only
		# a raw sample step can be judged; the reverb tail is folded round by construction
		if out["seam_jump"] > 3:
			flags.append("SEAM_CLICK")
	else:
		if out["seam_jump"] > 3 or (out["seam_hf_excess_db"] > 6 and out["seam_hf_rel_db"] > -50):
			flags.append("SEAM_CLICK")
		if out["seam_energy_db"] > max(3.0, 2.0 * out["seam_energy_typ"]):
			flags.append("SEAM_LEVEL")
		if out["seam_spec"] > 1.6 * out["seam_spec_typ"]:
			flags.append("SEAM_SPECTRUM")
	if out["harsh"] > 0.55:
		flags.append("HARSH")
	out["flags"] = flags
	return out


# ----------------------------------------------------------------------------
# Spectrogram pictures
# ----------------------------------------------------------------------------
_STOPS = np.array([[0, 0, 4], [40, 11, 84], [101, 21, 110], [159, 42, 99], [212, 72, 66],
				   [245, 125, 21], [250, 193, 39], [252, 255, 164]], dtype=float)


def _colour(v: np.ndarray) -> np.ndarray:
	v = np.clip(v, 0, 1) * (len(_STOPS) - 1)
	i = np.minimum(v.astype(int), len(_STOPS) - 2)
	u = (v - i)[..., None]
	return (_STOPS[i] * (1 - u) + _STOPS[i + 1] * u).astype(np.uint8)


def spectrogram_image(x: np.ndarray, title: str, width: int = 760, height: int = 300,
					  fmin: float = 40.0, fmax: float = 20000.0, floor: float = -85.0) -> Image.Image:
	"""Waveform strip on top, log-frequency spectrogram below, with axes."""
	m = S.to_mono(x)
	dur = len(m) / S.SR
	win = 1024 if dur < 1.5 else 2048 if dur < 12 else 4096
	hop = max(16, int(len(m) / width / 2))
	hop = min(hop, win // 2)
	sp = stft_db(np.concatenate([np.zeros(win // 2), m, np.zeros(win // 2)]), win, hop)
	freqs = np.fft.rfftfreq(win, 1 / S.SR)
	rows = fmin * (fmax / fmin) ** (np.arange(height)[::-1] / (height - 1))
	cols = np.linspace(0, sp.shape[0] - 1, width)
	ci = np.clip(np.round(cols).astype(int), 0, sp.shape[0] - 1)
	spc = sp[ci]
	img = np.empty((height, width))
	binw = S.SR / win
	for r, fr in enumerate(rows):
		# take the max over the bins a row spans so thin high rows do not alias
		lo = int(np.floor(fr * 0.985 / binw))
		hi = int(np.ceil(fr * 1.015 / binw))
		lo = min(lo, len(freqs) - 1)
		hi = min(max(hi, lo + 1), len(freqs))
		if hi - lo == 1:
			i = min(lo, len(freqs) - 2)
			u = fr / binw - i
			img[r] = spc[:, i] * (1 - u) + spc[:, i + 1] * u if 0 <= u <= 1 else spc[:, lo]
		else:
			img[r] = spc[:, lo:hi].max(axis=1)
	rgb = _colour((img - floor) / (0.0 - floor))
	wave_h = 60
	pad_l, pad_b, pad_t = 44, 16, 14
	canvas = Image.new("RGB", (width + pad_l + 6, height + wave_h + pad_b + pad_t + 4), (18, 18, 22))
	canvas.paste(Image.fromarray(rgb), (pad_l, pad_t + wave_h + 4))
	d = ImageDraw.Draw(canvas)
	d.text((pad_l, 1), title, fill=(230, 230, 230))
	# waveform envelope (min/max per column)
	seg = np.array_split(m, width)
	for c, s in enumerate(seg):
		if len(s) == 0:
			continue
		y0 = pad_t + wave_h / 2 - s.max() * wave_h / 2
		y1 = pad_t + wave_h / 2 - s.min() * wave_h / 2
		d.line([(pad_l + c, y0), (pad_l + c, y1)], fill=(120, 200, 255))
	d.line([(pad_l, pad_t + wave_h / 2), (pad_l + width, pad_t + wave_h / 2)], fill=(60, 60, 70))
	top = pad_t + wave_h + 4
	for fr, lab in [(50, "50"), (100, "100"), (200, "200"), (500, "500"), (1000, "1k"), (2000, "2k"),
					(5000, "5k"), (10000, "10k")]:
		y = top + (height - 1) * (1 - np.log(fr / fmin) / np.log(fmax / fmin))
		d.line([(pad_l - 4, y), (pad_l, y)], fill=(200, 200, 200))
		for xx in range(pad_l, pad_l + width, 8):
			d.point((xx, y), fill=(90, 90, 100))
		d.text((2, y - 5), lab, fill=(200, 200, 200))
	step = [0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 20][int(np.searchsorted([0.3, 0.6, 1.2, 3, 6, 12, 30, 60], dur))]
	tt = 0.0
	while tt <= dur + 1e-9:
		xx = pad_l + tt / dur * width
		d.line([(xx, top + height), (xx, top + height + 3)], fill=(200, 200, 200))
		d.text((xx + 1, top + height + 3), ("%g" % tt), fill=(200, 200, 200))
		tt += step
	return canvas


def sheet(images: list, cols: int = 2) -> Image.Image:
	w = max(i.width for i in images)
	h = max(i.height for i in images)
	rows = (len(images) + cols - 1) // cols
	out = Image.new("RGB", (w * cols, h * rows), (0, 0, 0))
	for k, im in enumerate(images):
		out.paste(im, ((k % cols) * w, (k // cols) * h))
	return out


# ----------------------------------------------------------------------------
# Pitch tracking against the score
# ----------------------------------------------------------------------------
def track_f0(seg: np.ndarray, expect: float, wide: bool) -> tuple:
	"""Fundamental of a segment. wide=True searches two octaves either side by
	normalised autocorrelation (honest about octave errors, monophonic lines);
	wide=False finds the strongest spectral peak within 70 cents of the
	expected pitch (melody inside chords). Returns (hz, confidence)."""
	seg = seg - seg.mean()
	if wide:
		n = len(seg)
		w = seg * np.hanning(n)
		spec = np.abs(np.fft.rfft(w, 1 << int(np.ceil(np.log2(2 * n))))) ** 2
		ac = np.fft.irfft(spec)
		ac /= ac[0] + 1e-12
		lo = int(S.SR / (expect * 2.3))
		hi = min(int(S.SR / (expect / 2.3)), n - 2)
		# pick the first lag whose peak is within 10% of the best (avoids sub-octaves)
		best = np.max(ac[lo:hi])
		lag = None
		for i in range(max(lo, 2), hi):
			if ac[i] > ac[i - 1] and ac[i] >= ac[i + 1] and ac[i] > 0.9 * best:
				lag = i
				break
		if lag is None:
			return 0.0, 0.0
		a, b, c = ac[lag - 1], ac[lag], ac[lag + 1]
		off = 0.5 * (a - c) / (a - 2 * b + c + 1e-12)
		return S.SR / (lag + off), float(b)
	n = len(seg)
	nfft = 1 << int(np.ceil(np.log2(n)) + 3)
	sp = np.abs(np.fft.rfft(seg * np.hanning(n), nfft))
	f = np.fft.rfftfreq(nfft, 1 / S.SR)
	m = (f > expect * 2 ** (-0.7 / 12)) & (f < expect * 2 ** (0.7 / 12))
	i = np.argmax(sp * m)
	a, b, c = np.log(sp[i - 1] + 1e-12), np.log(sp[i] + 1e-12), np.log(sp[i + 1] + 1e-12)
	off = 0.5 * (a - c) / (a - 2 * b + c + 1e-12)
	near = (f > expect * 0.7) & (f < expect * 1.4)
	return f[i] + off * (f[1] - f[0]), float(sp[i] / (np.max(sp[near]) + 1e-12))


def onset_strength(m: np.ndarray, hop: int = 256, win: int = 1024) -> np.ndarray:
	sp = stft_db(m, win, hop)
	sp = np.maximum(sp, -70)
	return np.maximum(np.diff(sp, axis=0), 0).sum(axis=1)


def verify_music() -> bool:
	import gen_music
	ok = True
	for chk in gen_music.pitch_checks():
		path = os.path.join(AUDIO, chk["file"])
		if not os.path.exists(path):
			print("MISSING", chk["file"])
			ok = False
			continue
		m = S.to_mono(S.read_audio(path))
		errs, bad, conf = [], [], []
		for (t0, dur, midi) in chk["notes"]:
			if dur < 0.11:
				continue
			a = S.sec(t0 + min(0.06, dur * 0.3))
			b = S.sec(t0 + dur - min(0.03, dur * 0.15))
			seg = m[a:b]
			if len(seg) < 256 or np.max(np.abs(seg)) < 1e-4:
				bad.append((t0, midi, "silent"))
				continue
			exp = float(S.midi_hz(midi))
			hz, c = track_f0(seg, exp, chk["mono"])
			cents = 1200 * np.log2(hz / exp) if hz > 0 else 9999
			errs.append(cents)
			conf.append(c)
			if abs(cents) > 25:
				bad.append((round(t0, 3), midi, "%.0f cents" % cents))
		errs = np.array(errs)
		good = np.abs(errs) <= 25
		line = "%-34s %-14s notes %3d  in tune %3d  median %+5.1fc  max|err| %5.1fc  conf %.2f" % (
			chk["file"], chk["label"], len(errs), int(good.sum()), float(np.median(errs)),
			float(np.max(np.abs(errs[good]))) if good.any() else -1, float(np.mean(conf)))
		# onsets: every articulated note start should sit on a rise in spectral flux
		if chk.get("onsets"):
			os_ = onset_strength(m)
			thr = np.percentile(os_, 75)
			hit, offs = 0, []
			for t0 in chk["onsets"]:
				c = int(t0 * S.SR / 256)
				lo, hi = max(0, c - 14), min(len(os_), c + 14)
				if hi <= lo:
					continue
				j = lo + int(np.argmax(os_[lo:hi]))
				if os_[j] > thr:
					hit += 1
					offs.append((j * 256 + 512) / S.SR - t0)
			line += "  onsets %d/%d (mean offset %+.0f ms)" % (hit, len(chk["onsets"]), 1000 * float(np.mean(offs)) if offs else 0)
			if hit < 0.9 * len(chk["onsets"]):
				ok = False
		print(line)
		if bad:
			ok = False
			print("   OFF:", bad[:12])
	return ok


# ----------------------------------------------------------------------------
def catalogue() -> list:
	"""(path, kind, loop, family) for every file in the manifest."""
	with open(os.path.join(AUDIO, "manifest.json")) as fh:
		man = json.load(fh)
	out = []
	for name, e in sorted(man.get("sfx", {}).items()):
		for fl in e["files"]:
			out.append((fl, "sfx", False, name))
	for name, e in sorted(man.get("ambience", {}).items()):
		out.append((e["file"], "ambience", True, name))
	for name, e in sorted(man.get("music", {}).items()):
		out.append((e["file"], "music", bool(e.get("loop", True)), name))
		for sname, sf in sorted(e.get("stems", {}).items()):
			out.append((sf, "music", bool(e.get("loop", True)), name + ":" + sname))
	for name, e in sorted(man.get("stingers", {}).items()):
		out.append((e["file"], "stinger", False, name))
	return out


def main() -> int:
	ap = argparse.ArgumentParser()
	ap.add_argument("--png", action="store_true")
	ap.add_argument("--only", default="")
	ap.add_argument("--music", action="store_true")
	ap.add_argument("--strict", action="store_true")
	ap.add_argument("--quiet", action="store_true", help="only print the summary and flags")
	args = ap.parse_args()
	os.makedirs(REPORT, exist_ok=True)
	if args.music:
		return 0 if verify_music() else 1
	rows, total = [], 0
	sheets: dict = {}
	ap_quiet = args.quiet
	hdr = "%-40s %6s %6s %6s %6s %7s %5s %6s %5s %6s %6s  %s" % (
		"file", "dur", "peak", "rms", "LUFS", "dc", "clip", "centr", "harsh", "start", "end", "flags/seam")
	if not ap_quiet:
		print(hdr)
	for fl, kind, loop, family in catalogue():
		if args.only and args.only not in fl:
			continue
		path = os.path.join(AUDIO, fl)
		if not os.path.exists(path):
			print("%-40s MISSING" % fl)
			rows.append({"file": fl, "flags": ["MISSING"]})
			continue
		r = measure(path, loop, kind)
		r["family"] = family
		rows.append(r)
		total += r["bytes"]
		extra = " ".join(r["flags"])
		if loop:
			extra += " seam[jump %.2f lvl %.1f/%.1fdB spec %.1f/%.1f hf %+.1fdB (%.0f rel)]" % (
				r["seam_jump"], r["seam_energy_db"], r["seam_energy_typ"], r["seam_spec"], r["seam_spec_typ"],
				r["seam_hf_excess_db"], r["seam_hf_rel_db"])
		if not ap_quiet:
			print("%-40s %6.2f %6.1f %6.1f %6.1f %7.4f %5d %6.0f %5.2f %6.0f %6.0f  %s" % (
				fl, r["dur"], r["peak_db"], r["rms_db"], r["lufs"], r["dc"], r["clipped"], r["centroid"],
				r["harsh"], r["start_db"], r["end_db"], extra))
		if args.png:
			x = S.read_audio(path)
			im = spectrogram_image(x, "%s  %.2fs  pk %.1f  L %.1f" % (fl, r["dur"], r["peak_db"], r["lufs"]))
			sheets.setdefault(kind + "_" + family.split(":")[0], []).append(im)
	if args.png:
		for name, ims in sheets.items():
			sheet(ims, 2 if len(ims) > 1 else 1).save(os.path.join(REPORT, name + ".png"))
	with open(os.path.join(REPORT, "report.json"), "w") as fh:
		json.dump(rows, fh, indent=1)
	# family consistency: one-shots of one family should sit within a few dB
	fam: dict = {}
	for r in rows:
		if r.get("kind") == "sfx":
			fam.setdefault(r["family"], []).append(r["lufs"])
	spread = {k: max(v) - min(v) for k, v in fam.items() if len(v) > 1}
	worst = sorted(spread.items(), key=lambda kv: -kv[1])[:5]
	flagged = [r for r in rows if r.get("flags")]
	print("\n%d files, %.2f MB. Flagged: %d. Largest loudness spread inside a family: %s" % (
		len(rows), total / 1e6, len(flagged), ", ".join("%s %.1f dB" % kv for kv in worst)))
	for r in flagged:
		print("  FLAG %-40s %s" % (r["file"], " ".join(r["flags"])))
	return 1 if (args.strict and flagged) else 0


if __name__ == "__main__":
	sys.exit(main())
