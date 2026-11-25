extends Node
## Game audio. Meant to be the autoload `Audio` (the lead registers it):
##   Audio="*res://src/audio/audio_manager.gd"
##
## - Builds the bus layout in code: Master (limiter) <- Music, Ambience, SFX, Voice,
##   plus AmbienceOutdoor -> Ambience so the hold can muffle the weather without
##   muffling its own creaks. Ambience, SFX and Voice carry a low-pass named
##   "Underwater" that set_underwater() sweeps in.
## - One-shots: play_sfx() from a pool, random variation, never the same twice running.
## - Music: play_music()/stop_music() crossfade; play_stinger() ducks the music.
## - Shanty stems: play_shanty() starts every instrument stem in sync; switch
##   instruments on and off as crew pick them up, optionally from 3D emitters.
## - Ambience: plain setters (sea state, wind, rain, shore, ship speed, below deck,
##   underwater), smoothed and crossfaded every frame.
##
## Every sound comes from the catalogue res://assets/generated/audio/manifest.json,
## written by tools/audio/gen_*.py. Unknown names and missing files warn once and
## are otherwise ignored, so gameplay code never has to guard a call.

const AUDIO_ROOT := "res://assets/generated/audio/"
const MANIFEST_PATH := AUDIO_ROOT + "manifest.json"

const BUS_MASTER := &"Master"
const BUS_MUSIC := &"Music"
const BUS_AMBIENCE := &"Ambience"
const BUS_OUTDOOR := &"AmbienceOutdoor"
const BUS_SFX := &"SFX"
const BUS_VOICE := &"Voice"
const UNDERWATER_EFFECT := "Underwater"

const POOL_3D := 24
const POOL_2D := 10
const SILENT_DB := -80.0
## Low-pass cutoffs: open air, fully under water, fully below deck.
const CUTOFF_OPEN := 20500.0
const CUTOFF_UNDERWATER := 650.0
const CUTOFF_BELOW_DECK := 1700.0

## Ambience layer -> bus. Outdoor layers are muffled below deck.
const AMBIENCE_BUS := {
	&"sea_calm": BUS_OUTDOOR, &"sea_rough": BUS_OUTDOOR, &"wind_light": BUS_OUTDOOR,
	&"wind_storm": BUS_OUTDOOR, &"rain": BUS_OUTDOOR, &"shore_surf": BUS_OUTDOOR,
	&"hull_wash": BUS_OUTDOOR, &"below_deck": BUS_AMBIENCE, &"underwater": BUS_AMBIENCE,
}

## The parsed manifest: sections "sfx", "ambience", "music", "stingers".
var catalogue: Dictionary = {}

# --- ambience targets (set by the game) and smoothed values ---
var _target := {&"sea": 0.2, &"wind": 0.2, &"rain": 0.0, &"shore": 0.0, &"speed": 0.0, &"below": 0.0, &"under": 0.0}
var _value := {&"sea": 0.2, &"wind": 0.2, &"rain": 0.0, &"shore": 0.0, &"speed": 0.0, &"below": 0.0, &"under": 0.0}
var _ambience_players: Dictionary = {}  # StringName -> AudioStreamPlayer
var ambience_enabled := true

# --- one-shots ---
var _sfx: Dictionary = {}  # StringName -> {streams: Array, last: int, ...}
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_2d: Array[AudioStreamPlayer] = []
var _started_3d: PackedInt64Array = []
var _started_2d: PackedInt64Array = []
var _warned: Dictionary = {}
var _rng := RandomNumberGenerator.new()

# --- music ---
var _music_players: Array[AudioStreamPlayer] = []
var _music_gain: PackedFloat32Array = [0.0, 0.0]
var _music_goal: PackedFloat32Array = [0.0, 0.0]
var _music_rate: PackedFloat32Array = [1.0, 1.0]
var _music_active := 0
var _music_name: StringName = &""
var _stinger_player: AudioStreamPlayer
var _duck := 1.0

# --- shanty stems ---
var _shanty_song: StringName = &""
var _stems: Dictionary = {}  # StringName -> {player, player3d, gain, goal, rate}
var _shanty_stopping := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_setup_buses()
	_load_catalogue()
	_build_players()


# ----------------------------------------------------------------------------
# Buses
# ----------------------------------------------------------------------------
func _setup_buses() -> void:
	_ensure_bus(BUS_MUSIC, BUS_MASTER)
	_ensure_bus(BUS_AMBIENCE, BUS_MASTER)
	_ensure_bus(BUS_OUTDOOR, BUS_AMBIENCE)
	_ensure_bus(BUS_SFX, BUS_MASTER)
	_ensure_bus(BUS_VOICE, BUS_MASTER)
	var master := AudioServer.get_bus_index(BUS_MASTER)
	if _find_effect(master, "Limiter") < 0:
		var lim := AudioEffectHardLimiter.new()
		lim.resource_name = "Limiter"
		lim.ceiling_db = -0.5
		lim.pre_gain_db = 0.0
		lim.release = 0.12
		AudioServer.add_bus_effect(master, lim)
	for bus: StringName in [BUS_AMBIENCE, BUS_SFX, BUS_VOICE]:
		_ensure_lowpass(bus, UNDERWATER_EFFECT)
	_ensure_lowpass(BUS_OUTDOOR, "BelowDeck")


func _ensure_bus(bus: StringName, send: StringName) -> void:
	if AudioServer.get_bus_index(bus) >= 0:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus)
	AudioServer.set_bus_send(idx, send)


func _find_effect(bus_idx: int, effect_name: String) -> int:
	for i in AudioServer.get_bus_effect_count(bus_idx):
		if AudioServer.get_bus_effect(bus_idx, i).resource_name == effect_name:
			return i
	return -1


func _ensure_lowpass(bus: StringName, effect_name: String) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if _find_effect(idx, effect_name) >= 0:
		return
	var lp := AudioEffectLowPassFilter.new()
	lp.resource_name = effect_name
	lp.cutoff_hz = CUTOFF_OPEN
	lp.resonance = 0.6
	AudioServer.add_bus_effect(idx, lp)
	AudioServer.set_bus_effect_enabled(idx, AudioServer.get_bus_effect_count(idx) - 1, false)


func _set_lowpass(bus: StringName, effect_name: String, amount: float, closed_hz: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	var fx := _find_effect(idx, effect_name)
	if fx < 0:
		return
	var on := amount > 0.004
	if AudioServer.is_bus_effect_enabled(idx, fx) != on:
		AudioServer.set_bus_effect_enabled(idx, fx, on)
	if on:
		var lp := AudioServer.get_bus_effect(idx, fx) as AudioEffectLowPassFilter
		# sweep on a log scale so it sounds even
		lp.cutoff_hz = CUTOFF_OPEN * pow(closed_hz / CUTOFF_OPEN, clampf(amount, 0.0, 1.0))


## Linear 0..1 volume for a bus (for the options menu).
func set_bus_volume(bus: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0001, 1.0)))
		AudioServer.set_bus_mute(idx, linear <= 0.0001)


func is_underwater_filter_on() -> bool:
	var idx := AudioServer.get_bus_index(BUS_SFX)
	var fx := _find_effect(idx, UNDERWATER_EFFECT)
	return fx >= 0 and AudioServer.is_bus_effect_enabled(idx, fx)


# ----------------------------------------------------------------------------
# Catalogue
# ----------------------------------------------------------------------------
func _load_catalogue() -> void:
	catalogue = {}
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_warning("Audio: no catalogue at %s (run tools/build_assets.sh); the game will be silent." % MANIFEST_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Audio: %s is not valid JSON." % MANIFEST_PATH)
		return
	catalogue = parsed
	for sfx_name: String in catalogue.get("sfx", {}):
		var e: Dictionary = catalogue["sfx"][sfx_name]
		_sfx[StringName(sfx_name)] = {
			"files": e.get("files", []), "streams": [], "loaded": false, "last": -1,
			"unit_size": float(e.get("unit_size", 4.0)), "max_distance": float(e.get("max_distance", 60.0)),
			"bus": StringName(e.get("bus", "SFX")),
		}


func _warn_once(key: String, msg: String) -> void:
	if not _warned.has(key):
		_warned[key] = true
		push_warning("Audio: " + msg)


## Load a catalogue file as a stream, setting its loop flag. Null (with one warning) if missing.
func load_stream(rel_path: String, loop: bool = false) -> AudioStream:
	var path := AUDIO_ROOT + rel_path
	if not ResourceLoader.exists(path):
		_warn_once(path, "missing file %s" % path)
		return null
	var stream := load(path) as AudioStream
	if stream == null:
		_warn_once(path, "%s is not an audio stream" % path)
		return null
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if loop:
			wav.loop_begin = 0
			wav.loop_end = int(wav.get_length() * wav.mix_rate)
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		else:
			wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


func has_sound(sound: StringName) -> bool:
	return _sfx.has(sound)


func sound_names() -> Array:
	return _sfx.keys()


## Every file the catalogue lists, as paths relative to AUDIO_ROOT, with whether it should loop.
func catalogue_files() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in catalogue.get("sfx", {}).values():
		for f: String in e.get("files", []):
			out.append({"file": f, "loop": false})
	for e: Dictionary in catalogue.get("ambience", {}).values():
		out.append({"file": e["file"], "loop": true})
	for e: Dictionary in catalogue.get("music", {}).values():
		out.append({"file": e["file"], "loop": bool(e.get("loop", true))})
		for f: String in e.get("stems", {}).values():
			out.append({"file": f, "loop": bool(e.get("loop", true))})
	for e: Dictionary in catalogue.get("stingers", {}).values():
		out.append({"file": e["file"], "loop": false})
	return out


## Load every one-shot now (call behind a loading screen to avoid first-play hitches).
func preload_sfx() -> void:
	for sound: StringName in _sfx:
		_streams_for(sound)


func _streams_for(sound: StringName) -> Array:
	var e: Dictionary = _sfx[sound]
	if not e["loaded"]:
		e["loaded"] = true
		for f: String in e["files"]:
			var s := load_stream(f, false)
			if s != null:
				e["streams"].append(s)
	return e["streams"]


# ----------------------------------------------------------------------------
# Players
# ----------------------------------------------------------------------------
func _build_players() -> void:
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.name = "Sfx3D_%d" % i
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.attenuation_filter_cutoff_hz = 9000.0
		p.attenuation_filter_db = -18.0
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(p)
		_pool_3d.append(p)
		_started_3d.append(0)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx2D_%d" % i
		add_child(p)
		_pool_2d.append(p)
		_started_2d.append(0)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.name = "Music_%d" % i
		m.bus = BUS_MUSIC
		m.volume_db = SILENT_DB
		add_child(m)
		_music_players.append(m)
	_stinger_player = AudioStreamPlayer.new()
	_stinger_player.name = "Stinger"
	_stinger_player.bus = BUS_MUSIC
	add_child(_stinger_player)
	for layer: String in catalogue.get("ambience", {}):
		var e: Dictionary = catalogue["ambience"][layer]
		var stream := load_stream(e["file"], true)
		if stream == null:
			continue
		var a := AudioStreamPlayer.new()
		a.name = "Amb_" + layer
		a.stream = stream
		a.bus = AMBIENCE_BUS.get(StringName(layer), BUS_AMBIENCE)
		a.volume_db = SILENT_DB
		add_child(a)
		_ambience_players[StringName(layer)] = a


# ----------------------------------------------------------------------------
# One-shots
# ----------------------------------------------------------------------------
## Play a catalogue sound. With a position it is 3D and attenuates with distance;
## without (Vector3.INF) it plays flat, for UI and first-person tools.
## Returns the player (reposition it, or stop it early) or null if nothing played.
func play_sfx(sound: StringName, position: Vector3 = Vector3.INF, volume_db: float = 0.0,
		pitch_jitter: float = 0.05) -> Node:
	if not _sfx.has(sound):
		_warn_once("sfx:" + sound, "unknown sound '%s'" % sound)
		return null
	var e: Dictionary = _sfx[sound]
	var streams := _streams_for(sound)
	if streams.is_empty():
		return null
	var pick := _rng.randi_range(0, streams.size() - 1)
	if streams.size() > 1 and pick == e["last"]:
		pick = (pick + 1 + _rng.randi_range(0, streams.size() - 2)) % streams.size()
	e["last"] = pick
	var pitch := 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter) if pitch_jitter > 0.0 else 1.0
	var now := Time.get_ticks_usec()
	if position.is_finite() and e["max_distance"] > 0.0:
		var i := _free_slot(_pool_3d, _started_3d)
		var p := _pool_3d[i]
		_started_3d[i] = now
		p.stream = streams[pick]
		p.bus = e["bus"]
		p.unit_size = e["unit_size"]
		p.max_distance = e["max_distance"]
		p.volume_db = volume_db
		p.pitch_scale = pitch
		p.global_position = position
		p.play()
		return p
	var j := _free_slot(_pool_2d, _started_2d)
	var q := _pool_2d[j]
	_started_2d[j] = now
	q.stream = streams[pick]
	q.bus = e["bus"]
	q.volume_db = volume_db
	q.pitch_scale = pitch
	q.play()
	return q


# First idle player, else steal the one that has been playing longest.
func _free_slot(pool: Array, started: PackedInt64Array) -> int:
	var oldest := 0
	for i in pool.size():
		if not pool[i].playing:
			return i
		if started[i] < started[oldest]:
			oldest = i
	return oldest


## How many pooled one-shot players are sounding right now.
func active_sfx_count() -> int:
	var n := 0
	for p in _pool_3d:
		if p.playing:
			n += 1
	for p in _pool_2d:
		if p.playing:
			n += 1
	return n


# ----------------------------------------------------------------------------
# Music
# ----------------------------------------------------------------------------
## Crossfade to a looping theme from the catalogue ("sailing", "combat", "shanty").
func play_music(music: StringName, fade: float = 1.5) -> void:
	if music == _music_name and _music_players[_music_active].playing:
		_music_goal[_music_active] = 1.0
		return
	var e: Dictionary = catalogue.get("music", {}).get(String(music), {})
	if e.is_empty():
		_warn_once("music:" + music, "unknown music '%s'" % music)
		return
	var stream := load_stream(e["file"], bool(e.get("loop", true)))
	if stream == null:
		return
	var old := _music_active
	_music_active = 1 - old
	_music_goal[old] = 0.0
	_music_rate[old] = 1.0 / maxf(fade, 0.01)
	var p := _music_players[_music_active]
	p.stream = stream
	_music_gain[_music_active] = 0.0 if fade > 0.0 else 1.0
	_music_goal[_music_active] = 1.0
	_music_rate[_music_active] = 1.0 / maxf(fade, 0.01)
	p.volume_db = _gain_db(_music_gain[_music_active])
	p.play()
	_music_name = music


func stop_music(fade: float = 1.5) -> void:
	for i in 2:
		_music_goal[i] = 0.0
		_music_rate[i] = 1.0 / maxf(fade, 0.01)
	_music_name = &""


func current_music() -> StringName:
	return _music_name


## Play a short musical sting ("ship_sighted", "treasure_found", "danger",
## "victory", "sunk") over whatever is playing; the music ducks under it.
func play_stinger(stinger: StringName, volume_db: float = 0.0) -> void:
	var e: Dictionary = catalogue.get("stingers", {}).get(String(stinger), {})
	if e.is_empty():
		_warn_once("stinger:" + stinger, "unknown stinger '%s'" % stinger)
		return
	var stream := load_stream(e["file"], false)
	if stream == null:
		return
	_stinger_player.stream = stream
	_stinger_player.volume_db = volume_db
	_stinger_player.play()


# ----------------------------------------------------------------------------
# Shanty stems
# ----------------------------------------------------------------------------
## Start the shanty with every instrument stem running in sync. Only the
## listed instruments are audible (empty = all): "concertina", "drum",
## "whistle", "hurdy_gurdy", "crew". Others stay silent but keep time, so a
## crewmate can join in mid-tune with set_shanty_instrument().
func play_shanty(instruments: Array = [], fade: float = 0.4, song: StringName = &"shanty") -> void:
	var e: Dictionary = catalogue.get("music", {}).get(String(song), {})
	var stems: Dictionary = e.get("stems", {})
	if stems.is_empty():
		_warn_once("shanty:" + song, "music '%s' has no stems" % song)
		return
	_clear_stems()
	_shanty_song = song
	_shanty_stopping = false
	for stem_name: String in stems:
		var stream := load_stream(stems[stem_name], true)
		if stream == null:
			continue
		var p := AudioStreamPlayer.new()
		p.name = "Stem_" + stem_name
		p.stream = stream
		p.bus = BUS_MUSIC
		p.volume_db = SILENT_DB
		add_child(p)
		var on := instruments.is_empty() or instruments.has(stem_name) or instruments.has(StringName(stem_name))
		_stems[StringName(stem_name)] = {"player": p, "player3d": null, "gain": 0.0, "goal": 1.0 if on else 0.0,
			"rate": 1.0 / maxf(fade, 0.01)}
	# start them in the same frame so they share one mix block: sample-aligned
	for s: Dictionary in _stems.values():
		(s["player"] as AudioStreamPlayer).play()


func set_shanty_instrument(instrument: StringName, active: bool, fade: float = 0.3) -> void:
	if not _stems.has(instrument):
		if _shanty_song != &"":
			_warn_once("stem:" + instrument, "shanty has no instrument '%s'" % instrument)
		return
	_stems[instrument]["goal"] = 1.0 if active else 0.0
	_stems[instrument]["rate"] = 1.0 / maxf(fade, 0.01)


## Make an instrument come from a place in the world (the crewmate playing it).
## Pass null to return it to the flat mix. The 3D player is a child of `emitter`.
func set_shanty_emitter(instrument: StringName, emitter: Node3D) -> void:
	if not _stems.has(instrument):
		return
	var s: Dictionary = _stems[instrument]
	var flat := s["player"] as AudioStreamPlayer
	if is_instance_valid(s["player3d"]):
		(s["player3d"] as Node).queue_free()
	s["player3d"] = null
	if emitter == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.name = "ShantyStem_" + instrument
	p.stream = flat.stream
	p.bus = BUS_MUSIC
	p.unit_size = 6.0
	p.max_distance = 80.0
	p.volume_db = SILENT_DB
	emitter.add_child(p)
	p.play(flat.get_playback_position() + AudioServer.get_time_since_last_mix())
	s["player3d"] = p


func stop_shanty(fade: float = 0.6) -> void:
	_shanty_stopping = true
	for s: Dictionary in _stems.values():
		s["goal"] = 0.0
		s["rate"] = 1.0 / maxf(fade, 0.01)


func is_shanty_playing() -> bool:
	return _shanty_song != &"" and not _stems.is_empty()


## Seconds into the shanty loop (all stems share it).
func shanty_position() -> float:
	for s: Dictionary in _stems.values():
		return (s["player"] as AudioStreamPlayer).get_playback_position()
	return 0.0


## Position in beats, for animating players in time (bpm comes from the catalogue).
func shanty_beat() -> float:
	var bpm := float(catalogue.get("music", {}).get(String(_shanty_song), {}).get("bpm", 120.0))
	return shanty_position() * bpm / 60.0


func _clear_stems() -> void:
	for s: Dictionary in _stems.values():
		(s["player"] as Node).queue_free()
		if is_instance_valid(s["player3d"]):
			(s["player3d"] as Node).queue_free()
	_stems.clear()
	_shanty_song = &""


# ----------------------------------------------------------------------------
# Ambience
# ----------------------------------------------------------------------------
## 0 flat calm .. 1 storm swell. Crossfades the calm and rough sea beds.
func set_sea_state(v: float) -> void:
	_target[&"sea"] = clampf(v, 0.0, 1.0)


## 0 still air .. 1 gale. Light wind fades in first, then gives way to the storm wind.
func set_wind(v: float) -> void:
	_target[&"wind"] = clampf(v, 0.0, 1.0)


func set_rain(v: float) -> void:
	_target[&"rain"] = clampf(v, 0.0, 1.0)


## 0 open sea .. 1 standing on a beach: brings in the surf.
func set_shore(v: float) -> void:
	_target[&"shore"] = clampf(v, 0.0, 1.0)


## 0 stopped .. 1 full speed: water rushing past the hull.
func set_ship_speed(v: float) -> void:
	_target[&"speed"] = clampf(v, 0.0, 1.0)


## 0 on deck .. 1 down in the hold: weather is muffled, timbers creak.
func set_below_deck(v: float) -> void:
	_target[&"below"] = clampf(v, 0.0, 1.0)


## Listener's head is under the surface: low-pass on world sound, underwater bed.
func set_underwater(on: bool) -> void:
	_target[&"under"] = 1.0 if on else 0.0


## Skip the smoothing (after a teleport or scene change).
func snap_ambience() -> void:
	for k: StringName in _target:
		_value[k] = _target[k]
	_apply_ambience()


## Current linear gain of each ambience layer (also handy for debugging HUDs and tests).
func ambience_levels() -> Dictionary:
	var sea: float = _value[&"sea"]
	var wind: float = _value[&"wind"]
	var under: float = _value[&"under"]
	var below: float = _value[&"below"]
	var surface := 1.0 - under
	var outdoor := surface * lerpf(1.0, 0.5, below)
	var storm := clampf((wind - 0.45) / 0.55, 0.0, 1.0)
	return {
		&"sea_calm": cos(sea * PI * 0.5) * outdoor,
		&"sea_rough": sin(sea * PI * 0.5) * outdoor,
		&"wind_light": sin(clampf(wind / 0.4, 0.0, 1.0) * PI * 0.5) * cos(storm * PI * 0.5) * outdoor,
		&"wind_storm": sin(storm * PI * 0.5) * outdoor,
		&"rain": sqrt(_value[&"rain"]) * outdoor,
		&"shore_surf": _value[&"shore"] * outdoor,
		&"hull_wash": _value[&"speed"] * outdoor,
		&"below_deck": below * surface,
		&"underwater": under,
	}


func _apply_ambience() -> void:
	var levels := ambience_levels()
	for layer: StringName in _ambience_players:
		var p: AudioStreamPlayer = _ambience_players[layer]
		var g: float = levels.get(layer, 0.0) if ambience_enabled else 0.0
		if g < 0.002:
			if p.playing:
				p.stream_paused = true
			continue
		p.volume_db = _gain_db(g)
		if not p.playing:
			p.play(_rng.randf() * p.stream.get_length())  # layers never line up the same way twice
		elif p.stream_paused:
			p.stream_paused = false
	var under: float = _value[&"under"]
	for bus: StringName in [BUS_AMBIENCE, BUS_SFX, BUS_VOICE]:
		_set_lowpass(bus, UNDERWATER_EFFECT, under, CUTOFF_UNDERWATER)
	_set_lowpass(BUS_OUTDOOR, "BelowDeck", _value[&"below"], CUTOFF_BELOW_DECK)


func _gain_db(g: float) -> float:
	return maxf(linear_to_db(maxf(g, 0.0)), SILENT_DB)


# ----------------------------------------------------------------------------
func _process(delta: float) -> void:
	# ambience: ease towards targets; diving is quick, weather is slow
	for k: StringName in _target:
		var rate := 7.0 if k == &"under" else (3.0 if k == &"below" else 1.2)
		_value[k] = lerpf(_value[k], _target[k], 1.0 - exp(-rate * delta))
		if absf(_value[k] - _target[k]) < 0.0005:
			_value[k] = _target[k]
	_apply_ambience()
	# music crossfade, ducked while a stinger plays
	var duck_goal := 0.35 if _stinger_player.playing else 1.0
	_duck = move_toward(_duck, duck_goal, delta * (4.0 if duck_goal < _duck else 0.8))
	for i in 2:
		var p := _music_players[i]
		_music_gain[i] = move_toward(_music_gain[i], _music_goal[i], _music_rate[i] * delta)
		if p.playing:
			p.volume_db = _gain_db(_music_gain[i] * _duck)
			if _music_gain[i] <= 0.0 and _music_goal[i] <= 0.0:
				p.stop()
	# shanty stems
	var any_audible := false
	for s: Dictionary in _stems.values():
		s["gain"] = move_toward(s["gain"], s["goal"], s["rate"] * delta)
		any_audible = any_audible or s["gain"] > 0.0 or s["goal"] > 0.0
		var db := _gain_db(s["gain"] * _duck)
		var p3: Variant = s["player3d"]
		if is_instance_valid(p3):
			(p3 as AudioStreamPlayer3D).volume_db = db
			(s["player"] as AudioStreamPlayer).volume_db = SILENT_DB
		else:
			s["player3d"] = null
			(s["player"] as AudioStreamPlayer).volume_db = db
	if _shanty_stopping and not any_audible:
		_clear_stems()
		_shanty_stopping = false
