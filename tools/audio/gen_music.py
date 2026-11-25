#!/usr/bin/env python3
"""Original music for Sea of Scoundrels, written as note data and performed by
the synthesised instruments in synth.py. Usage: gen_music.py <outdir>

Everything here is composed for this game; no existing tune is quoted.

Score notation (one string per track per section):
  D5:1      note name : length in beats        r:2      rest
  [D4 F#4 A4]:1   chord                         |        bar line (checked!)
  prefixes  ~ cut (a flick up to a grace note, whistle ornament)   > accent
  suffixes  ' staccato     _ slur into the next note
Drum and hurdy-gurdy buzz patterns are one character per subdivision, 8 or 16
characters per bar: D/d low drum loud/soft, T/t high 'tak', k rim tick,
B/b trompette buzz strong/weak, - nothing.

To edit a tune, change the strings and rebuild. tools/audio/analyze.py --music
pitch-tracks the rendered audio against these same scores.
"""
from __future__ import annotations

import multiprocessing
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import synth as S  # noqa: E402

# ----------------------------------------------------------------------------
# THE SCORES
# ----------------------------------------------------------------------------
# chord name: (bass note, alternate bass, triad)
CHORDS = {
	"D": ("D3", "A2", "[D4 F#4 A4]"), "G": ("G2", "D3", "[D4 G4 B4]"), "A": ("A2", "E3", "[C#4 E4 A4]"),
	"Bm": ("B2", "F#3", "[D4 F#4 B4]"), "Em": ("E3", "B2", "[E4 G4 B4]"), "C": ("C3", "G2", "[E4 G4 C5]"),
	"Am": ("A2", "E3", "[E4 A4 C5]"), "Dm": ("D3", "A2", "[D4 F4 A4]"), "Bb": ("Bb2", "F3", "[D4 F4 Bb4]"),
	"F": ("F2", "C3", "[C4 F4 A4]"), "Gm": ("G2", "D3", "[D4 G4 Bb4]"),
}

# --- "The Scoundrel's Reel" : shanty, D major, 4/4, 120 bpm -------------------
# Form: verse A1 (8 bars) - chorus B1 (8) - verse A2 (8, whistle leads) -
#       chorus B2 (8, everyone) - tag (4) = 36 bars = 72 s, loops back to A1.
SH_VERSE = ("F#5:.75 E5:.25 D5:.5 A4:.5 D5:1 F#5:1 | A5:1 F#5:.5 A5:.5 B5:1 A5:1 | "
			"G5:.75 F#5:.25 G5:.5 B5:.5 A5:1 G5:1 | F#5:.5 E5:.5 C#5:.5 E5:.5 E5:2 | "
			"F#5:.75 E5:.25 D5:.5 A4:.5 D5:1 F#5:1 | B5:1 A5:.5 F#5:.5 D5:1 B4:1 | "
			"G5:.5 B5:.5 A5:.5 G5:.5 F#5:.5 E5:.5 C#5:.5 E5:.5 | D5:1.5 D5:.5 D5:1 r:1")
SH_CHORUS = (">B5:1.5 B5:.5 B5:.5 A5:.5 G5:1 | A5:1 F#5:1 D5:1 r:1 | "
			 "E5:.75 F#5:.25 E5:.5 C#5:.5 E5:1 A5:1 | F#5:1.5 E5:.5 D5:2 | "
			 ">B5:1.5 B5:.5 B5:.5 A5:.5 G5:1 | A5:1 D6:1 A5:1 F#5:1 | "
			 "G5:.5 F#5:.5 E5:.5 D5:.5 C#5:1 E5:1 | D5:2 D5:1 r:1")
SH_TAG = ("B5:.5 G5:.5 B5:.5 D6:.5 B5:1 G5:1 | A5:.5 F#5:.5 A5:.5 D6:.5 A5:1 F#5:1 | "
		  "G5:.5 E5:.5 G5:.5 B5:.5 A5:.5 G5:.5 E5:.5 C#5:.5 | D5:1 F#5:.5 A5:.5 >D6:1 r:1")
# verse 2: concertina steps back to a slow counter-line under the whistle
SH_COUNTER = "D5:2 A4:2 | F#5:2 D5:2 | B4:2 D5:2 | C#5:2 A4:2 | D5:2 A4:2 | D5:2 B4:2 | B4:2 C#5:2 | D5:3 r:1"
# whistle: pick-up into the chorus, a descant over it, then the tune with cuts
SH_WH_A1 = "r:4 | r:4 | r:4 | r:4 | r:4 | r:4 | r:4 | r:2 F#5:.5 A5:.5 B5:.5 C#6:.5"
SH_WH_CHORUS = ("~D6:1.5 D6:.5 D6:.5 E6:.5 D6:1 | F#6:1 D6:1 A5:.5 B5:.5 A5:1 | "
				"~C#6:1.5 A5:.5 C#6:1 E6:1 | ~D6:1.5 C#6:.5 D6:.5 A5:.5 F#5:.5 A5:.5 | "
				"~D6:1.5 D6:.5 D6:.5 E6:.5 D6:1 | ~F#6:1 F#6:1 ~F#6:1 D6:1 | "
				"E6:.5 D6:.5 C#6:.5 B5:.5 ~A5:1 C#6:1 | ~D6:2 D6:1 r:1")
SH_WH_A2 = ("~F#5:.75 E5:.25 D5:.5 A4:.5 ~D5:1 F#5:1 | ~A5:1 F#5:.5 A5:.5 ~B5:1 A5:1 | "
			"~G5:.75 F#5:.25 G5:.5 B5:.5 ~A5:1 G5:1 | F#5:.5 E5:.5 C#5:.5 E5:.5 ~E5:1 A5:.5 G5:.5 | "
			"~F#5:.75 E5:.25 D5:.5 A4:.5 ~D5:1 F#5:1 | ~B5:1 A5:.5 F#5:.5 ~D5:1 B4:1 | "
			"G5:.5 B5:.5 A5:.5 G5:.5 F#5:.5 E5:.5 C#5:.5 E5:.5 | ~D5:1.5 D5:.5 D5:1 F#5:.5 A5:.5")
SH_CH_A = ["D", "D", "D", "D", "G", "G", "A", "A", "D", "D", "Bm", "Bm", "G", "A", "D", "D"]  # two per bar
SH_CH_B = ["G", "G", "D", "D", "A", "A", "D", "D", "G", "G", "D", "D", "A", "A", "D", "D"]
SH_CH_TAG = ["G", "G", "D", "D", "Em", "A", "D", "D"]
SH_DR_VERSE = "D-k-t-kk D-k-tk-k D-k-t-kk D-k-tk-k D-k-t-kk D-k-tk-k D-k-t-kk D---k---t-t-TtTt"
SH_DR_QUIET = "D---t--- D---t-k- D---t--- D---t-k- D-k-t-k- D-k-t-kk D-k-t-kk D---k---t-t-TtTt"
SH_DR_CHORUS = "D-ktD-kt D-ktDDkt D-ktD-kt D-ktDDkt D-ktD-kt D-ktDDkt D-ktD-kt D-ktD-ttTtTtD-t-"
SH_DR_TAG = "D-ktD-kt D-ktDDkt D-ktDDkt D--tD--tD-D-T---"
SH_BUZZ_CHORUS = "B-b-B-bb " * 8
SH_BUZZ_TAG = "B-b-B-bb B-b-B-bb B-bbB-bb B---B---"

SHANTY = {
	"name": "shanty", "title": "The Scoundrel's Reel", "key": "D major", "bpm": 120.0, "beats_per_bar": 4,
	"form": [("A1", 8), ("B1", 8), ("A2", 8), ("B2", 8), ("TAG", 4)], "loop": True,
	"reverb": dict(wet=0.16, t60=0.9, damp=0.55, seed=2), "lufs": -16.0,
	"stems": ["concertina", "drum", "whistle", "hurdy_gurdy", "crew"],
	"tracks": [
		{"id": "concertina_melody", "stem": "concertina", "inst": "concertina", "gain": 0.0, "pan": -0.25,
		 "parts": {"A1": SH_VERSE, "B1": SH_CHORUS, "A2": SH_COUNTER, "B2": SH_CHORUS, "TAG": SH_TAG},
		 "vel": {"A2": 0.6}},
		{"id": "concertina_chords", "stem": "concertina", "inst": "concertina", "gain": -7.0, "pan": -0.35,
		 "oompah": {"A1": SH_CH_A, "B1": SH_CH_B, "A2": SH_CH_A, "B2": SH_CH_B, "TAG": SH_CH_TAG}, "bright": 0.75},
		{"id": "whistle", "stem": "whistle", "inst": "whistle", "gain": -2.5, "pan": 0.3,
		 "parts": {"A1": SH_WH_A1, "B1": SH_WH_CHORUS, "A2": SH_WH_A2, "B2": SH_WH_CHORUS, "TAG": SH_TAG}},
		{"id": "drum", "stem": "drum", "inst": "drum", "gain": -3.0, "pan": 0.0,
		 "patterns": {"A1": SH_DR_QUIET, "B1": SH_DR_CHORUS, "A2": SH_DR_VERSE, "B2": SH_DR_CHORUS, "TAG": SH_DR_TAG}},
		{"id": "hurdy_drone", "stem": "hurdy_gurdy", "inst": "hurdy_drone", "gain": -9.0, "pan": 0.12,
		 "notes": ["D3", "A3", "D2"], "levels": {"A1": (0.0, 0.0, 0.5), "B1": 1.0, "A2": 0.55, "B2": 1.0, "TAG": 1.0},
		 "buzz": {"B1": SH_BUZZ_CHORUS, "B2": SH_BUZZ_CHORUS, "TAG": SH_BUZZ_TAG}},
		{"id": "hurdy_melody", "stem": "hurdy_gurdy", "inst": "hurdy_melody", "gain": -8.0, "pan": 0.12,
		 "parts": {"B2": SH_CHORUS, "TAG": SH_TAG}, "transpose": -12},
		{"id": "crew_hum", "stem": "crew", "inst": "hum", "gain": -9.0, "pan": 0.0,
		 "parts": {"B2": SH_CHORUS}, "transpose": -24},
		{"id": "crew_shouts", "stem": "crew", "inst": "shouts", "gain": -5.0, "pan": 0.0,
		 "shouts": {"B1": [(7.0, "hey"), (31.0, "ho")], "B2": [(7.0, "hey"), (15.0, "hey"), (31.0, "ho")],
					"TAG": [(15.0, "hey")]}},
	],
}

# --- "Fair Wind Home" : calm sailing theme, G major, 6/8, eighth = 0.36 s -------
# (dotted quarter about 56 bpm). Form A A B A, 8 bars each = 32 bars = 69.1 s.
SA_A = ("D5:3 G5:2 A5:1 | B5:3 G5:3 | E5:2 G5:1 C6:2 B5:1 | A5:5 F#5:1 | "
		"D5:3 G5:2 A5:1 | B5:2 D6:1 B5:3 | C6:2 B5:1 A5:2 F#5:1 | G5:6")
SA_B = ("E5:2 G5:1 B5:3 | C6:3 G5:2 E5:1 | D5:2 G5:1 B5:2 A5:1 | A5:3 F#5:3 | "
		"E5:2 G5:1 B5:3 | C6:2 D6:1 E6:3 | C6:2 A5:1 E5:2 A5:1 | F#5:3 A5:2 D5:1")
SA_CH_A = ["G", "G", "Em", "Em", "C", "C", "D", "D", "G", "G", "Em", "Em", "C", "D", "G", "G"]
SA_CH_B = ["Em", "Em", "C", "C", "G", "G", "D", "D", "Em", "Em", "C", "C", "Am", "Am", "D", "D"]

SAILING = {
	"name": "sailing", "title": "Fair Wind Home", "key": "G major", "bpm": 60.0 / 0.36, "beats_per_bar": 6,
	"form": [("A1", 8), ("A2", 8), ("B", 8), ("A3", 8)], "loop": True,
	"reverb": dict(wet=0.26, t60=1.7, damp=0.5, seed=4), "lufs": -18.0, "stems": [],
	"tracks": [
		{"id": "whistle", "stem": "whistle", "inst": "whistle", "gain": -5.0, "pan": 0.2, "soft": True,
		 "parts": {"A1": SA_A, "B": SA_B, "A3": SA_A}},
		{"id": "concertina_melody", "stem": "concertina", "inst": "concertina", "gain": -5.0, "pan": -0.2,
		 "parts": {"A2": SA_A, "A3": SA_A}, "transpose_by": {"A3": -12}, "vel": {"A2": 0.7, "A3": 0.5}, "bright": 0.7,
		 "legato": True},
		{"id": "concertina_pad", "stem": "concertina", "inst": "concertina", "gain": -15.0, "pan": -0.1,
		 "pad": {"B": SA_CH_B, "A3": SA_CH_A}, "bright": 0.55},
		{"id": "cittern", "stem": "pluck", "inst": "pluck", "gain": -6.0, "pan": 0.0,
		 "arp": {"A1": SA_CH_A, "A2": SA_CH_A, "B": SA_CH_B, "A3": SA_CH_A}},
	],
}

# --- "Black Flag Rising" : combat loop, D minor, 4/4, 150 bpm -------------------
# Form A (8 bars) B (8) A' (8) = 24 bars = 38.4 s.
CO_A = ("D5:1.5 F5:.5 A5:1 G5:.5 F5:.5 | E5:.5 F5:.5 D5:1 r:1 A4:.5 D5:.5 | "
		"F5:1.5 D5:.5 Bb5:1 A5:.5 G5:.5 | A5:1 E5:1 C#5:1 E5:1 | "
		"D5:1.5 F5:.5 A5:1 G5:.5 F5:.5 | E5:.5 F5:.5 D5:1 r:1 D5:.5 F5:.5 | "
		"Bb5:.5 A5:.5 G5:.5 F5:.5 E5:.5 C#5:.5 E5:.5 G5:.5 | >D5:2 r:1 A4:1")
CO_A2 = CO_A.rsplit("|", 1)[0] + "| >D5:2 r:2"
CO_B = ("A5:1 C6:1 A5:.5 G5:.5 F5:1 | G5:1 E5:1 C5:1 E5:1 | F5:1 A5:1 D6:1.5 A5:.5 | C#6:1 A5:1 E5:2 | "
		"A5:1 C6:1 A5:.5 G5:.5 F5:1 | G5:1 C6:1 E6:1.5 D6:.5 | D6:1 Bb5:1 F5:1 D5:1 | E5:.5 A5:.5 C#6:.5 E6:.5 >A5:2")
CO_CH_A = ["Dm", "Dm", "Dm", "Dm", "Bb", "Bb", "A", "A", "Dm", "Dm", "Dm", "Dm", "Bb", "A", "Dm", "Dm"]
CO_CH_B = ["F", "F", "C", "C", "Dm", "Dm", "A", "A", "F", "F", "C", "C", "Bb", "Bb", "A", "A"]
CO_DR_A = "D-dtDdt- D-dtDdtt D-dtDdt- D-dtDdtt D-dtDdt- D-dtDdtt D-dtDdt- D-dtD-ttTtTtDDDD"
CO_DR_B = "DdtdDdtd DdtdDdtt DdtdDdtd DdtdDdtt DdtdDdtd DdtdDdtt DdtdDdtd D-t-D-t-DtDtTTTT"

COMBAT = {
	"name": "combat", "title": "Black Flag Rising", "key": "D minor", "bpm": 150.0, "beats_per_bar": 4,
	"form": [("A", 8), ("B", 8), ("A2", 8)], "loop": True,
	"reverb": dict(wet=0.14, t60=1.0, damp=0.6, seed=5), "lufs": -15.0, "stems": [],
	"tracks": [
		{"id": "concertina_melody", "stem": "concertina", "inst": "concertina", "gain": 0.0, "pan": -0.25,
		 "parts": {"A": CO_A, "B": CO_B, "A2": CO_A2}},
		{"id": "whistle", "stem": "whistle", "inst": "whistle", "gain": -6.0, "pan": 0.3,
		 "parts": {"B": CO_B, "A2": CO_A2}, "transpose_by": {"A2": 12}},
		{"id": "concertina_stabs", "stem": "concertina", "inst": "concertina", "gain": -6.0, "pan": -0.35,
		 "stabs": {"A": CO_CH_A, "B": CO_CH_B, "A2": CO_CH_A}, "bright": 0.8},
		{"id": "bass", "stem": "pluck", "inst": "pluck", "gain": -3.0, "pan": 0.05,
		 "riff": {"A": CO_CH_A, "B": CO_CH_B, "A2": CO_CH_A}, "ring": 0.12},
		{"id": "drum", "stem": "drum", "inst": "drum", "gain": -2.0, "pan": 0.0, "war": True,
		 "patterns": {"A": CO_DR_A, "B": CO_DR_B, "A2": CO_DR_B}},
		{"id": "hurdy_drone", "stem": "hurdy_gurdy", "inst": "hurdy_drone", "gain": -9.0, "pan": 0.1,
		 "notes": ["D2", "A2", "D3"], "levels": {"A": 0.8, "B": 1.0, "A2": 1.0},
		 "buzz": {"A": "B-bbB-bb " * 8, "B": "B-bbBbbb " * 8, "A2": "BbbbBbbb " * 8}},
	],
}

# --- Stingers: one or two bars each, not looped ---------------------------------
STINGERS = [
	{"name": "ship_sighted", "key": "D major", "bpm": 150.0, "beats_per_bar": 4, "form": [("X", 2)],
	 "reverb": dict(wet=0.22, t60=1.3, damp=0.5, seed=4), "lufs": -17.0, "tail": 1.6,
	 "tracks": [
		 {"id": "whistle", "inst": "whistle", "gain": -2.0, "pan": 0.2, "parts": {"X": "D5:.5 A5:.5 ~D6:1.5 A5:.5 ~D6:1 | F#6:4"}},
		 {"id": "concertina", "inst": "concertina", "gain": -8.0, "pan": -0.2, "parts": {"X": "r:1 [D4 A4]:3 | [D4 F#4 A4 D5]:4"}},
		 {"id": "drum", "inst": "drum", "gain": -6.0, "pan": 0.0, "patterns": {"X": "--t-t--- D-------"}},
	 ]},
	{"name": "treasure_found", "key": "G major", "bpm": 132.0, "beats_per_bar": 4, "form": [("X", 2)],
	 "reverb": dict(wet=0.26, t60=1.6, damp=0.4, seed=4), "lufs": -17.0, "tail": 2.2, "sparkle": 1.0,
	 "tracks": [
		 {"id": "pluck", "inst": "pluck", "gain": -3.0, "pan": 0.0,
		  "parts": {"X": "G4:.25 B4:.25 D5:.25 G5:.25 B5:.25 D6:.25 G6:.5 D6:.5 B5:.5 G5:1 | [G3 D4 G4 B4 D5 G5]:4"}},
		 {"id": "whistle", "inst": "whistle", "gain": -5.0, "pan": 0.25, "parts": {"X": "r:1.5 B5:.5 D6:.5 ~G6:1.5 | ~G6:.5 F#6:.5 ~G6:3"}},
		 {"id": "concertina", "inst": "concertina", "gain": -9.0, "pan": -0.2, "parts": {"X": "r:2 [B4 D5]:2 | [G4 B4 D5 G5]:4"}},
	 ]},
	{"name": "danger", "key": "D minor", "bpm": 80.0, "beats_per_bar": 4, "form": [("X", 1)],
	 "reverb": dict(wet=0.25, t60=1.8, damp=0.6, seed=5), "lufs": -16.0, "tail": 1.8,
	 "tracks": [
		 {"id": "hurdy_drone", "inst": "hurdy_drone", "gain": -5.0, "pan": 0.0, "notes": ["D2", "A2", "Eb3"],
		  "levels": {"X": (0.3, 1.0, 1.0)}, "buzz": {"X": "B---b---B-b-BbBb"}},
		 {"id": "concertina", "inst": "concertina", "gain": -5.0, "pan": -0.15, "bright": 0.7,
		  "parts": {"X": "[D3 A3 D4]:1.5 [D3 Ab3 Eb4]:.5 [D3 Ab3 D4 F4]:2"}},
		 {"id": "drum", "inst": "drum", "gain": -2.0, "pan": 0.0, "war": True, "patterns": {"X": "D-----D-D-------"}},
	 ]},
	{"name": "victory", "key": "D major", "bpm": 144.0, "beats_per_bar": 4, "form": [("X", 3)],
	 "reverb": dict(wet=0.2, t60=1.2, damp=0.5, seed=2), "lufs": -16.0, "tail": 1.6,
	 "tracks": [
		 {"id": "concertina", "inst": "concertina", "gain": 0.0, "pan": -0.2,
		  "parts": {"X": "A5:.75 A5:.25 >D6:1 F#5:.5 A5:.5 D6:.5 F#6:.5 | E6:1 C#6:.5 E6:.5 >D6:2 | [D5 F#5 A5 D6]:4"}},
		 {"id": "chords", "inst": "concertina", "gain": -7.0, "pan": -0.3, "bright": 0.75,
		  "oompah": {"X": ["D", "D", "A", "D", "D", "D"]}},
		 {"id": "whistle", "inst": "whistle", "gain": -4.0, "pan": 0.25,
		  "parts": {"X": "r:1 ~F#6:1 D6:.5 F#6:.5 A6:1 | G6:1 E6:.5 G6:.5 ~F#6:2 | ~F#6:4"}},
		 {"id": "drum", "inst": "drum", "gain": -3.0, "pan": 0.0, "patterns": {"X": "D-ktD-kt D-ktTtTt D---------------"}},
		 {"id": "crew", "inst": "shouts", "gain": -5.0, "pan": 0.0, "shouts": {"X": [(8.0, "hey")]}},
	 ]},
	{"name": "sunk", "key": "D minor", "bpm": 66.0, "beats_per_bar": 4, "form": [("X", 3)],
	 "reverb": dict(wet=0.3, t60=2.2, damp=0.6, seed=5), "lufs": -18.0, "tail": 2.4,
	 "tracks": [
		 {"id": "concertina", "inst": "concertina", "gain": 0.0, "pan": -0.15, "bright": 0.6, "legato": True,
		  "parts": {"X": "A5:1 F5:1 D5:1.5 E5:.5 | F5:1 D5:1 Bb4:1 A4:1 | [D4 F4 A4]:4"}},
		 {"id": "low", "inst": "concertina", "gain": -6.0, "pan": -0.3, "bright": 0.5, "legato": True,
		  "parts": {"X": "[D3 A3]:4 | [Bb2 F3]:2 [A2 E3]:2 | [D2 D3]:4"}},
		 {"id": "hurdy_drone", "inst": "hurdy_drone", "gain": -9.0, "pan": 0.1, "notes": ["D3", "A3"],
		  "levels": {"X": (0.8, 0.6, 0.0)}, "droop": 2.0},
		 {"id": "drum", "inst": "drum", "gain": -6.0, "pan": 0.0, "war": True, "patterns": {"X": "d------- d------- d-------"}},
	 ]},
]

SONGS = [SHANTY, SAILING, COMBAT]

# ----------------------------------------------------------------------------
# Score parsing
# ----------------------------------------------------------------------------
_TOKEN = re.compile(r"^(?P<pre>[~>]*)(?P<p>r|\[[^\]]+\]|[A-G][#b]?\d):(?P<d>\d*\.?\d+)(?P<suf>['_]*)$")


def parse(score: str, beats_per_bar: int) -> list:
	"""Score string -> [dict(beat, dur, midis, flags)] and total beats. Raises
	if a bar line does not fall on a bar boundary: typos fail loudly."""
	notes, pos = [], 0.0
	for tok in re.findall(r"\[[^\]]+\]:\S+|\S+", score.replace("|", " | ")):
		if tok == "|":
			if abs(pos / beats_per_bar - round(pos / beats_per_bar)) > 1e-6:
				raise ValueError("bar line at beat %.3f is not on a bar boundary: ...%s" % (pos, score[:60]))
			continue
		m = _TOKEN.match(tok)
		if not m:
			raise ValueError("bad token %r" % tok)
		d = float(m.group("d"))
		p = m.group("p")
		if p != "r":
			names = p.strip("[]").split() if p.startswith("[") else [p]
			notes.append({"beat": pos, "dur": d, "midis": [S.note_midi(n) for n in names],
						  "cut": "~" in m.group("pre"), "accent": ">" in m.group("pre"),
						  "stacc": "'" in m.group("suf"), "slur": "_" in m.group("suf")})
		pos += d
	return notes, pos


def section_starts(song: dict) -> dict:
	out, bar = {}, 0
	for name, bars in song["form"]:
		out[name] = (bar * song["beats_per_bar"], bars)
		bar += bars
	return out


def total_beats(song: dict) -> float:
	return sum(b for _, b in song["form"]) * song["beats_per_bar"]


def track_notes(song: dict, track: dict) -> list:
	"""All of a track's notes in song time (beats), from whichever kind of
	part description the track uses."""
	bpb = song["beats_per_bar"]
	starts = section_starts(song)
	out = []
	for sec_name, (b0, bars) in starts.items():
		vel = track.get("vel", {}).get(sec_name, 1.0)
		tr = track.get("transpose", 0) + track.get("transpose_by", {}).get(sec_name, 0)
		if sec_name in track.get("parts", {}):
			notes, total = parse(track["parts"][sec_name], bpb)
			if abs(total - bars * bpb) > 1e-6:
				raise ValueError("%s/%s/%s is %.2f beats, expected %d" % (song["name"], track["id"], sec_name, total, bars * bpb))
			for n in notes:
				out.append(dict(n, beat=n["beat"] + b0, midis=[m + tr for m in n["midis"]], vel=vel * (1.2 if n["accent"] else 1.0)))
		for kind in ("oompah", "pad", "arp", "stabs", "riff"):
			if sec_name in track.get(kind, {}):
				chords = track[kind][sec_name]
				if len(chords) != bars * 2:
					raise ValueError("%s/%s/%s needs two chords per bar" % (song["name"], track["id"], sec_name))
				out.extend(_accompany(kind, chords, b0, bpb))
	out.sort(key=lambda n: n["beat"])
	return out


def _n(beat, dur, names, vel=1.0, stacc=False):
	if isinstance(names, str):
		names = names.strip("[]").split()
	return {"beat": beat, "dur": dur, "midis": [S.note_midi(x) for x in names], "cut": False, "accent": False,
			"stacc": stacc, "slur": False, "vel": vel}


def _accompany(kind: str, chords: list, b0: float, bpb: int) -> list:
	"""Expand a chord chart (two chords per bar) into an accompaniment figure."""
	out = []
	half = bpb / 2.0
	for i, ch in enumerate(chords):
		bass, alt, triad = CHORDS[ch]
		t = b0 + i * half
		first = i % 2 == 0
		tri = triad.strip("[]").split()
		if kind == "oompah":  # bass on the beat, chord on the off-beat
			out.append(_n(t, 0.9, bass if first else alt, 1.0 if first else 0.85))
			out.append(_n(t + 1.0, 0.45, triad, 0.75, True))
			if not first:
				out.append(_n(t + 1.5, 0.3, triad, 0.5, True))
		elif kind == "pad":  # held chord, re-bellowed each half bar
			out.append(_n(t, half, triad, 0.8))
			if first:
				out.append(_n(t, bpb if (i + 1 < len(chords) and chords[i + 1] == ch) else half, bass, 0.8))
		elif kind == "arp":  # 6/8 broken chord: bass, fifth, third up, and down again
			lo = S.note_midi(bass)
			tm = [S.note_midi(x) for x in tri]
			pat = [lo, tm[0], tm[1], tm[2], tm[1], tm[0]] if (first and i + 1 < len(chords) and chords[i + 1] == ch) else None
			if pat and first:
				for k, m in enumerate(pat):
					out.append({"beat": t + k, "dur": 2.5, "midis": [m], "cut": False, "accent": False, "stacc": False,
								"slur": False, "vel": 1.0 if k == 0 else 0.6})
			elif first or chords[i - 1] != ch:
				for k, m in enumerate([lo, tm[1], tm[2]]):
					out.append({"beat": t + k, "dur": 2.5, "midis": [m], "cut": False, "accent": False, "stacc": False,
								"slur": False, "vel": 1.0 if k == 0 else 0.6})
		elif kind == "stabs":  # syncopated low chords: on 1, the and-of-2, and 4
			if first:
				out.append(_n(t, 0.4, triad, 1.0, True))
				out.append(_n(t + 1.5, 0.4, triad, 0.8, True))
			else:
				out.append(_n(t + 1.0, 0.4, triad, 0.9, True))
		elif kind == "riff":  # driving eighths: root root fifth root | octave root fifth third
			r = S.note_midi(bass)
			fifth = r + 7
			third = r + (3 if "m" in ch else 4)
			pat = [r, r, fifth, r] if first else [r + 12, r, fifth, third]
			for k, m in enumerate(pat):
				out.append({"beat": t + k * 0.5, "dur": 0.5, "midis": [m], "cut": False, "accent": False, "stacc": False,
							"slur": False, "vel": 1.0 if k == 0 else 0.7})
	return out


# ----------------------------------------------------------------------------
# Performers
# ----------------------------------------------------------------------------
_CACHE: dict = {}


def play_poly(notes, n_total, beat_s, rng, kind, track):
	"""Concertina or plucked strings: one voice per note."""
	out = np.zeros(n_total + S.sec(4.0))
	bright = track.get("bright", 1.0)
	for nt in notes:
		t0 = nt["beat"] * beat_s + rng.uniform(-0.005, 0.005)
		gate = nt["dur"] * beat_s * (0.5 if nt["stacc"] else (1.0 if track.get("legato") else 0.9))
		vel = nt["vel"] * rng.uniform(0.92, 1.05)
		for m in nt["midis"]:
			f = float(S.midi_hz(m))
			if kind == "concertina":
				nn = S.sec(gate + 0.05)
				key = ("c", m, nn, round(bright, 2))
				if key not in _CACHE:
					_CACHE[key] = S.concertina(f, nn, S.seed_rng("conc%d_%d" % (m, nn)), 1.0, bright)
				y = _CACHE[key] * vel
			else:
				dur = max(gate, 0.25) + track.get("ring", 1.2)
				key = ("p", m, round(dur, 2))
				if key not in _CACHE:
					t60 = 3.2 * (220.0 / f) ** 0.35
					y0 = S.karplus_strong(f, dur, S.seed_rng("pluck%d" % m), t60=t60, bright=0.42)
					# cittern body: two soft resonances and a little low cut
					y0 = y0 + 0.35 * S.resonator(y0, 190.0, 3.0) + 0.25 * S.resonator(y0, 420.0, 4.0)
					_CACHE[key] = S.fade(S.highpass(y0, 60.0), 0.0005, 0.15)
				y = _CACHE[key] * vel
			S.place(out, y, max(t0, 0.0), 1.0 / np.sqrt(len(nt["midis"])) if len(nt["midis"]) > 2 else 1.0)
	return out


def line_curves(notes, n, beat_s, rng, attack=0.014, release=0.035, tongued=True, vib=(5.3, 0.0035)):
	"""Pitch and loudness curves for a one-voice instrument (whistle, hurdy
	chanter, voice). Returns (hz per sample, amp per sample, tongued onset times)."""
	f = np.zeros(n)
	amp = np.zeros(n)
	onsets = []
	t = S.tgrid(n)
	notes = [x for x in notes if x["beat"] * beat_s < n / S.SR]
	for i, nt in enumerate(notes):
		t0 = nt["beat"] * beat_s
		dur = nt["dur"] * beat_s
		nxt = notes[i + 1]["beat"] * beat_s if i + 1 < len(notes) else n / S.SR
		joined = (not tongued) and abs(nxt - (t0 + dur)) < 1e-6
		gate = dur * (0.5 if nt["stacc"] else 1.0) - (0.0 if (nt["slur"] or joined) else min(0.04, dur * 0.2))
		i0, i1, i2 = S.sec(t0), min(n, S.sec(t0 + gate)), min(n, S.sec(nxt))
		hz = float(S.midi_hz(nt["midis"][0]))
		seg = np.full(i2 - i0, hz)
		tt = t[i0:i2] - t0
		if nt["cut"]:  # grace note a tone up, a twentieth of a second
			k = min(len(seg), S.sec(0.04))
			seg[:k] = hz * 2.0 ** (2.0 / 12.0)
		if dur > 0.34 and vib:
			seg *= 1.0 + vib[1] * np.clip((tt - 0.16) / 0.25, 0, 1) * np.sin(S.TAU * vib[0] * tt + rng.uniform(0, S.TAU))
		f[i0:i2] = seg
		prev_slur = i > 0 and (notes[i - 1]["slur"] or ((not tongued) and abs(t0 - (notes[i - 1]["beat"] + notes[i - 1]["dur"]) * beat_s) < 1e-6))
		e = np.ones(i1 - i0)
		a = S.sec(attack)
		r = S.sec(release)
		if not prev_slur:
			k = min(a, len(e))
			e[:k] = 0.5 - 0.5 * np.cos(np.pi * np.arange(k) / a)
			onsets.append(t0)
		v = nt["vel"] * rng.uniform(0.93, 1.04)
		amp[i0:i1] = np.maximum(amp[i0:i1], e * v)
		if not (nt["slur"] or joined):  # release tail after the gate
			k = min(r, n - i1)
			amp[i1:i1 + k] = np.maximum(amp[i1:i1 + k], v * (0.5 + 0.5 * np.cos(np.pi * np.arange(k) / r)))
	# fill silent stretches with the neighbouring pitch so the oscillator never sees 0 Hz
	idx = np.where(f > 0)[0]
	if len(idx):
		f = np.interp(np.arange(n), idx, f[idx])
		f = np.exp(S.smooth(np.log(f), 0.008))
	return f, amp, onsets


def play_whistle(notes, n_total, beat_s, rng, track):
	n = n_total + S.sec(0.5)
	soft = track.get("soft", False)
	f, amp, onsets = line_curves(notes, n, beat_s, rng)
	# upper octave needs more breath: louder and a touch brighter
	amp = amp * np.clip(0.75 + 0.25 * np.log2(np.maximum(f, 1.0) / 587.0), 0.6, 1.15)
	x = S.whistle_voice(f, amp, rng, breath=2.2 if soft else 1.0, bright=0.6 if soft else 1.0)
	for t0 in onsets:  # chiff: a puff of noise as the note is tongued
		i = S.sec(t0)
		if i >= n - 10:
			continue
		k = min(S.sec(0.03), n - i)
		hz = f[min(i + k, n - 1)]
		puff = S.bandpass(S.white(k, rng), hz * 0.9, min(hz * 4.0, 9000.0), 1) * np.exp(-S.tgrid(k) / 0.008)
		x[i:i + k] += puff * (0.05 if soft else 0.08) * amp[min(i + k, n - 1)]
	return x


def play_hurdy_melody(notes, n_total, beat_s, rng, track):
	n = n_total + S.sec(0.5)
	if not notes:
		return np.zeros(n)
	f, amp, _ = line_curves(notes, n, beat_s, rng, attack=0.03, release=0.08, tongued=False, vib=None)
	a = max(0, S.sec(notes[0]["beat"] * beat_s) - 100)
	b = min(n, S.sec((notes[-1]["beat"] + notes[-1]["dur"]) * beat_s + 0.3))
	out = np.zeros(n)
	out[a:b] = S.hurdy_gurdy(f[a:b], b - a, rng, wheel=S.smooth(amp[a:b], 0.03))
	return out


def play_hurdy_drone(song, track, n_total, beat_s, rng):
	"""Drone strings under a crank whose speed follows the section levels, and
	the buzzing bridge following the buzz pattern."""
	n = n_total + S.sec(1.0)
	bpb = song["beats_per_bar"]
	wheel = np.zeros(n)
	buzz = np.zeros(n)
	t = S.tgrid(n)
	for sec_name, (b0, bars) in section_starts(song).items():
		lv = track.get("levels", {}).get(sec_name, 0.0)
		i0, i1 = S.sec(b0 * beat_s), min(n, S.sec((b0 + bars * bpb) * beat_s))
		if isinstance(lv, tuple):
			wheel[i0:i1] = np.interp(np.linspace(0, 1, i1 - i0), np.linspace(0, 1, len(lv)), lv)
		else:
			wheel[i0:i1] = lv
		pat = track.get("buzz", {}).get(sec_name)
		if pat:
			for bi, bar in enumerate(pat.split()):
				step = bpb / len(bar)
				for k, ch in enumerate(bar):
					if ch in "Bb":
						tb = (b0 + bi * bpb + k * step) * beat_s
						j0, j1 = S.sec(tb), min(n, S.sec(tb + step * beat_s))
						u = np.linspace(0, 1, j1 - j0, endpoint=False)
						buzz[j0:j1] += (1.0 if ch == "B" else 0.5) * np.exp(-u / 0.35) * np.clip(u / 0.06, 0, 1)
	wheel = S.smooth(wheel, 0.25)
	wheel[:S.sec(0.02)] *= np.linspace(0, 1, S.sec(0.02))
	wheel = wheel * (1.0 + 0.4 * np.minimum(buzz, 1.0))  # the crank jerk that makes the buzz
	droop = track.get("droop", 0.0)
	bend = 2.0 ** (-droop / 12.0 * np.clip(t / (n_total / S.SR), 0, 1) ** 2) if droop else 1.0
	out = np.zeros(n)
	for k, name in enumerate(track["notes"]):
		hz = float(S.midi_hz(S.note_midi(name)))
		out += S.hurdy_gurdy(hz * bend * np.ones(n), n, rng, wheel=wheel, buzz=buzz if k == 0 else None) * (1.0 if k < 2 else 0.8)
	return out


def play_drum(song, track, n_total, beat_s, rng):
	out = np.zeros(n_total + S.sec(1.5))
	bpb = song["beats_per_bar"]
	war = track.get("war", False)
	kit = {}

	def hit(ch, v):
		key = (ch, v)
		if key not in kit:
			r = S.seed_rng("drum_%s_%d_%d" % (ch, v, int(war)))
			if ch in "Dd":
				y = S.membrane(62.0 if war else 86.0, 0.8, r, vel=1.0 if ch == "D" else 0.55, t60=0.55 if war else 0.34,
							   bend=0.2, slap=0.35)
			elif ch in "Tt":
				y = S.membrane(150.0 if war else 235.0, 0.3, r, vel=1.0 if ch == "T" else 0.6, t60=0.16 if war else 0.1,
							   bend=0.1, slap=0.8, tone=0.75)
				fr, td, am = S.wood_modes(r, 1100.0, 4, 3.0, 0.02)
				S.place(y, S.modal(fr, td, am, 0.05, r), 0.0, 0.25)
				k = len(y)
				S.place(y, S.bandpass(S.white(k, r), 2000, 9000) * np.exp(-S.tgrid(k) / 0.012), 0.0, 0.22)
			else:  # k: stick on the rim
				fr, td, am = S.wood_modes(r, 780.0, 5, 4.0, 0.035)
				y = S.modal(fr, td, am, 0.1, r) * 0.45
			kit[key] = y
		return kit[key]

	for sec_name, (b0, bars) in section_starts(song).items():
		pat = track.get("patterns", {}).get(sec_name)
		if not pat:
			continue
		bar_list = pat.split()
		if len(bar_list) != bars:
			raise ValueError("%s drum %s: %d bars, expected %d" % (song["name"], sec_name, len(bar_list), bars))
		for bi, bar in enumerate(bar_list):
			step = bpb / len(bar)
			for k, ch in enumerate(bar):
				if ch == "-":
					continue
				tb = (b0 + bi * bpb + k * step) * beat_s + rng.uniform(-0.004, 0.004)
				S.place(out, hit(ch, int(rng.integers(0, 3))), max(tb, 0.0), rng.uniform(0.88, 1.0))
	return out


def play_hum(notes, n_total, beat_s, rng, track):
	"""The crew humming along: three voices in rough unison on 'oh'."""
	n = n_total + S.sec(0.5)
	if not notes:
		return np.zeros(n)
	a = max(0, S.sec(notes[0]["beat"] * beat_s) - 100)
	b = min(n, S.sec((notes[-1]["beat"] + notes[-1]["dur"]) * beat_s + 0.4))
	out = np.zeros(n)
	for v in range(3):
		f, amp, _ = line_curves(notes, n, beat_s, rng, attack=0.06, release=0.12, tongued=True, vib=(5.0, 0.006))
		det = 2.0 ** (rng.uniform(-9, 9) / 1200.0)
		x = S.voice(f[a:b] * det, b - a, "o", rng, rough=0.05, breath=0.03, size=rng.uniform(0.95, 1.08), tilt_exp=1.35)
		out[a:b] += x / (np.abs(x).max() + 1e-9) * S.smooth(amp[a:b], 0.02)
	return out


def play_shouts(song, track, n_total, beat_s, rng):
	import gen_sfx
	out = np.zeros(n_total + S.sec(1.5))
	for sec_name, (b0, bars) in section_starts(song).items():
		for beat, word in track.get("shouts", {}).get(sec_name, []):
			y = gen_sfx.shout(rng, word, voices=4, dur=0.36)
			S.place(out, y / np.abs(y).max(), (b0 + beat) * beat_s - 0.02, 1.0)
	return out


def render_track(song: dict, track: dict, rng) -> np.ndarray:
	beat_s = 60.0 / song["bpm"]
	n_total = S.sec(total_beats(song) * beat_s)
	inst = track["inst"]
	notes = track_notes(song, track)
	if inst in ("concertina", "pluck"):
		x = play_poly(notes, n_total, beat_s, rng, inst, track)
	elif inst == "whistle":
		x = play_whistle(notes, n_total, beat_s, rng, track)
	elif inst == "hurdy_melody":
		x = play_hurdy_melody(notes, n_total, beat_s, rng, track)
	elif inst == "hurdy_drone":
		x = play_hurdy_drone(song, track, n_total, beat_s, rng)
	elif inst == "drum":
		x = play_drum(song, track, n_total, beat_s, rng)
	elif inst == "hum":
		x = play_hum(notes, n_total, beat_s, rng, track)
	elif inst == "shouts":
		x = play_shouts(song, track, n_total, beat_s, rng)
	else:
		raise ValueError(inst)
	return x


# reference level each instrument is brought to before its track gain (LUFS)
_INST_REF = -20.0


def render_song(song: dict) -> dict:
	"""Returns {'mix': stereo, 'stems': {name: stereo}, 'n': loop length}. Stems
	share one master gain, so playing them together reproduces the mix."""
	beat_s = 60.0 / song["bpm"]
	n_total = S.sec(total_beats(song) * beat_s)
	tail = S.sec(song.get("tail", 0.0))
	length = n_total + tail
	stems: dict = {}
	for track in song["tracks"]:
		x = render_track(song, track, S.seed_rng(song["name"] + "/" + track["id"]))
		if not np.any(np.abs(x) > 1e-9):
			continue
		x = x * S.db(_INST_REF - S.lufs(x) + track["gain"])
		st = S.reverb(S.pan(x, track["pan"]) / np.sqrt(2.0), **song["reverb"])
		if song.get("loop"):
			st = S.fold_tail(st, n_total)
		else:
			lead = S.sec(0.008)  # a breath of silence so the codec has no onset at sample 0
			pad = np.zeros((max(length, len(st) + lead), 2))
			pad[lead:lead + len(st)] = st
			st = S.fade(pad[:length], 0.0, min(1.0, song.get("tail", 1.0) * 0.6))
		name = track.get("stem", track["id"])
		stems[name] = stems.get(name, 0.0) + st
	if song.get("sparkle"):
		import gen_sfx
		r = S.seed_rng(song["name"] + "/sparkle")
		sp = np.zeros((length, 2))
		for i in range(9):
			S.place(sp, gen_sfx.coin(r), 0.9 + r.uniform(0, 1.6), r.uniform(0.01, 0.03) * song["sparkle"], p=r.uniform(-0.7, 0.7))
		stems["sparkle"] = sp
	# remove DC and subsonics; circular for loops so the seam stays exact
	for k in stems:
		if song.get("loop"):
			stems[k] = S.spectral_filter(stems[k], lambda f: S.hp_shape(np.maximum(f, 1e-3), 24.0, 2.0))
		else:
			stems[k] = S.fade(S.highpass(stems[k], 24.0), 0.002, 0.0)
	mix = sum(stems.values())
	g = S.db(song["lufs"] - S.lufs(mix))
	stems = {k: v * g for k, v in stems.items()}
	mix = S.limit(mix * g, -1.5)
	for k in stems:  # a lone stem can peak higher than it does inside the mix
		stems[k] = S.limit(stems[k], -1.5)
	return {"mix": mix, "stems": stems, "n": n_total}


def _job(args) -> str:
	kind, idx, root = args
	song = SONGS[idx] if kind == "song" else STINGERS[idx]
	res = render_song(song)
	lines = []
	if kind == "song":
		S.write_ogg(os.path.join(root, "music", song["name"] + ".ogg"), res["mix"], quality=5.0)
		lines.append("  music/%s.ogg  %.1fs" % (song["name"], len(res["mix"]) / S.SR))
		for st in song["stems"]:
			S.write_ogg(os.path.join(root, "music", "%s_%s.ogg" % (song["name"], st)), res["stems"][st], quality=4.0)
			lines.append("  music/%s_%s.ogg" % (song["name"], st))
	else:
		S.write_ogg(os.path.join(root, "music", "stinger_" + song["name"] + ".ogg"), res["mix"], quality=5.0)
		lines.append("  music/stinger_%s.ogg  %.1fs" % (song["name"], len(res["mix"]) / S.SR))
	return "\n".join(lines)


def pitch_checks() -> list:
	"""What analyze.py --music should find in the rendered files: for each
	file, the notes (seconds, midi) of one line of the score."""
	out = []

	def notes_of(song, track_id, sections=None):
		beat_s = 60.0 / song["bpm"]
		tr = next(t for t in song["tracks"] if t["id"] == track_id)
		starts = section_starts(song)
		res = []
		for n in track_notes(song, tr):
			if sections:
				ok = any(starts[s][0] <= n["beat"] < starts[s][0] + starts[s][1] * song["beats_per_bar"] for s in sections)
				if not ok:
					continue
			gate = n["dur"] * (0.5 if n["stacc"] else 1.0)
			res.append((n["beat"] * beat_s, gate * beat_s, n["midis"][0]))
		return res

	wh = notes_of(SHANTY, "whistle")
	out.append({"file": "music/shanty_whistle.ogg", "label": "whistle", "notes": wh, "mono": True,
				"onsets": [n[0] for n in wh]})
	out.append({"file": "music/shanty_concertina.ogg", "label": "melody", "notes": notes_of(SHANTY, "concertina_melody"),
				"mono": False})
	out.append({"file": "music/shanty.ogg", "label": "concertina", "notes": notes_of(SHANTY, "concertina_melody"), "mono": False})
	out.append({"file": "music/shanty.ogg", "label": "whistle", "notes": wh, "mono": False})
	out.append({"file": "music/sailing.ogg", "label": "whistle", "notes": notes_of(SAILING, "whistle"), "mono": False})
	out.append({"file": "music/sailing.ogg", "label": "concertina", "notes": notes_of(SAILING, "concertina_melody"), "mono": False})
	out.append({"file": "music/combat.ogg", "label": "concertina", "notes": notes_of(COMBAT, "concertina_melody"), "mono": False})
	out.append({"file": "music/combat.ogg", "label": "whistle", "notes": notes_of(COMBAT, "whistle"), "mono": False})
	for st in STINGERS:
		tid = next(t["id"] for t in st["tracks"] if "parts" in t)
		out.append({"file": "music/stinger_%s.ogg" % st["name"], "label": tid, "notes": notes_of(st, tid), "mono": False})
	return out


def main() -> None:
	outdir = sys.argv[-1]
	man = S.Manifest(outdir)
	only = sys.argv[1:-1]
	jobs = [("song", i, man.root) for i, s in enumerate(SONGS) if not only or s["name"] in only]
	jobs += [("stinger", i, man.root) for i, s in enumerate(STINGERS) if not only or s["name"] in only]
	with multiprocessing.Pool(min(4, os.cpu_count() or 1)) as pool:
		for line in pool.imap(_job, jobs):
			print(line)
	for s in SONGS:
		beat_s = 60.0 / s["bpm"]
		man.add("music", s["name"], file="music/%s.ogg" % s["name"], loop=True, title=s["title"], key=s["key"],
				bpm=round(s["bpm"], 3), beats_per_bar=s["beats_per_bar"], bars=sum(b for _, b in s["form"]),
				length=round(total_beats(s) * beat_s, 4),
				stems={st: "music/%s_%s.ogg" % (s["name"], st) for st in s["stems"]})
	for s in STINGERS:
		man.add("stingers", s["name"], file="music/stinger_%s.ogg" % s["name"], key=s["key"])
	man.save()


if __name__ == "__main__":
	main()
