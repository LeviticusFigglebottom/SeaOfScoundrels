extends TestCase
## Audio manager and catalogue. Runs headless (Dummy audio driver): nothing is
## heard, but streams load, players start and the mixer maths run.

const AudioManager := preload("res://src/audio/audio_manager.gd")

var audio: Node


func _manager() -> Node:
	# The lead registers the autoload `Audio`; until then (and in this test) build our own.
	if audio == null:
		audio = AudioManager.new()
		audio.name = "AudioUnderTest"
		add_child(audio)
	return audio


func test_catalogue_loads() -> void:
	var a := _manager()
	check(not a.catalogue.is_empty(), "manifest.json should load")
	for section in ["sfx", "ambience", "music", "stingers"]:
		check(a.catalogue.has(section), "catalogue section '%s'" % section)
	for sound in [&"cannon_fire", &"hull_creak", &"sail_flap", &"sail_fill", &"rope_creak", &"capstan_clank",
			&"wheel_creak", &"anchor_drop", &"anchor_splash", &"hold_slosh", &"bucket_splash", &"hammer_plank",
			&"cannonball_whistle", &"hull_impact", &"splash_large", &"splash_small", &"sword_swing",
			&"sword_clash", &"parry_ring", &"ship_bell", &"hit_flesh", &"skeleton_rattle", &"pistol_shot", &"footstep_wood",
			&"footstep_sand", &"footstep_water", &"chest_thump", &"coin_jingle", &"dig_sand", &"ui_tick",
			&"thunder_near", &"thunder_far", &"seagull", &"whale_call", &"spyglass_slide", &"lantern_click", &"grog_gulp", &"burp"]:
		check(a.has_sound(sound), "catalogue should list '%s'" % sound)
	check(a.catalogue["sfx"].has("ship_bell"), "sfx catalogue registers ship_bell")
	check(a.catalogue["sfx"].has("whale_call"), "sfx catalogue registers whale_call")
	for layer in ["sea_calm", "sea_rough", "wind_light", "wind_storm", "rain", "underwater", "shore_surf", "below_deck"]:
		check(a.catalogue["ambience"].has(layer), "ambience layer '%s'" % layer)
	for m in ["shanty", "sailing", "combat", "sail_day", "sail_night", "storm"]:
		check(a.catalogue["music"].has(m), "music '%s'" % m)
	for s in ["ship_sighted", "treasure_found", "danger", "victory", "sunk", "discovery"]:
		check(a.catalogue["stingers"].has(s), "stinger '%s'" % s)
	for stem in ["concertina", "drum", "whistle"]:
		check(a.catalogue["music"]["shanty"]["stems"].has(stem), "shanty stem '%s'" % stem)


func test_every_file_loads_as_stream() -> void:
	var a := _manager()
	var files: Array[Dictionary] = a.catalogue_files()
	check(files.size() > 100, "expected a full catalogue, got %d files" % files.size())
	for f in files:
		var path: String = a.AUDIO_ROOT + f["file"]
		check(FileAccess.file_exists(path), "file on disk: " + path)
		var stream: AudioStream = a.load_stream(f["file"], f["loop"])
		check(stream != null, "loads as AudioStream: " + path)
		if stream == null:
			continue
		check(stream.get_length() > 0.02, "has length: " + path)
		if stream is AudioStreamOggVorbis:
			check_eq((stream as AudioStreamOggVorbis).loop, f["loop"], "loop flag " + path)
		elif stream is AudioStreamWAV:
			check_eq((stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED, f["loop"], "loop flag " + path)


func test_stems_match_the_mix_length() -> void:
	var a := _manager()
	var e: Dictionary = a.catalogue["music"]["shanty"]
	var mix: AudioStream = a.load_stream(e["file"], true)
	check_near(mix.get_length(), float(e["length"]), 0.01, "shanty length")
	for stem: String in e["stems"]:
		var s: AudioStream = a.load_stream(e["stems"][stem], true)
		check_near(s.get_length(), mix.get_length(), 0.001, "stem %s must be exactly as long as the mix" % stem)


func test_buses() -> void:
	_manager()
	for bus in [&"Master", &"Music", &"Ambience", &"SFX", &"Voice"]:
		check(AudioServer.get_bus_index(bus) >= 0, "bus %s exists" % bus)
	for bus in [&"Music", &"Ambience", &"SFX", &"Voice"]:
		check_eq(AudioServer.get_bus_send(AudioServer.get_bus_index(bus)), &"Master", "%s sends to Master" % bus)
	var limiter := false
	for i in AudioServer.get_bus_effect_count(0):
		limiter = limiter or AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter
	check(limiter, "limiter on Master")
	# building a second manager must not duplicate buses or effects
	var count := AudioServer.bus_count
	var fx := AudioServer.get_bus_effect_count(0)
	var second := AudioManager.new()
	add_child(second)
	check_eq(AudioServer.bus_count, count, "bus setup is idempotent")
	check_eq(AudioServer.get_bus_effect_count(0), fx, "effect setup is idempotent")
	second.queue_free()


func test_play_sfx() -> void:
	var a := _manager()
	for sound: StringName in a.sound_names():
		var p: Node = a.play_sfx(sound, Vector3(3, 1, -2))
		check(p != null, "play_sfx('%s') returns a player" % sound)
	check(a.active_sfx_count() > 0, "pool is playing")
	var flat: Node = a.play_sfx(&"ui_tick")
	check(flat is AudioStreamPlayer, "no position -> non-positional player")
	var spatial: Node = a.play_sfx(&"cannon_fire", Vector3(50, 0, 0), -3.0, 0.1)
	check(spatial is AudioStreamPlayer3D, "position -> 3D player")
	if spatial is AudioStreamPlayer3D:
		check_near((spatial as AudioStreamPlayer3D).global_position.x, 50.0, 0.001)
		check((spatial as AudioStreamPlayer3D).max_distance >= 1000.0, "cannon carries far")
	var bell_p: Node = a.play_sfx(&"ship_bell", Vector3(12, 2, -8))
	check(bell_p is AudioStreamPlayer3D and (bell_p as AudioStreamPlayer3D).max_distance >= 120.0,
		"ship_bell plays spatially across deck & harbour")
	var whale_p: Node = a.play_sfx(&"whale_call", Vector3(45, -4, -90))
	check(whale_p is AudioStreamPlayer3D and (whale_p as AudioStreamPlayer3D).max_distance >= 300.0,
		"whale_call plays spatially with deep-ocean carry distance")
	# more calls than pool slots: voices are stolen, never an error
	for i in 80:
		a.play_sfx(&"footstep_wood", Vector3(i, 0, 0))
	check(a.active_sfx_count() <= a.POOL_3D + a.POOL_2D)
	# variation never repeats back to back
	var last: AudioStream = null
	var repeats := 0
	for i in 30:
		var q := a.play_sfx(&"footstep_sand") as AudioStreamPlayer
		if q.stream == last:
			repeats += 1
		last = q.stream
	check_eq(repeats, 0, "same variation twice in a row")
	# unknown names fail soft
	check(a.play_sfx(&"no_such_sound") == null, "unknown sound returns null")
	await physics_frames(2)


func test_music_and_stingers() -> void:
	var a := _manager()
	a.play_music(&"sailing", 0.05)
	check_eq(a.current_music(), &"sailing")
	await physics_frames(10)
	a.play_music(&"combat", 0.05)
	await physics_frames(10)
	check_eq(a.current_music(), &"combat")
	for s in [&"ship_sighted", &"treasure_found", &"danger", &"victory", &"sunk", &"discovery"]:
		a.play_stinger(s)
	a.play_stinger(&"no_such_stinger")
	a.play_music(&"no_such_music")
	check_eq(a.current_music(), &"combat", "unknown music leaves the current one playing")
	a.stop_music(0.02)
	await physics_frames(10)
	check_eq(a.current_music(), &"")


func test_shanty_stems() -> void:
	var a := _manager()
	a.play_shanty([&"concertina"], 0.02)
	check(a.is_shanty_playing(), "shanty started")
	a.set_shanty_instrument(&"drum", true, 0.02)
	a.set_shanty_instrument(&"whistle", true, 0.02)
	a.set_shanty_instrument(&"kazoo", true)
	var emitter := Node3D.new()
	add_child(emitter)
	a.set_shanty_emitter(&"whistle", emitter)
	await physics_frames(6)
	check(a.shanty_beat() >= 0.0)
	emitter.queue_free()  # the player walks off with the whistle: must not crash
	await physics_frames(3)
	a.set_shanty_emitter(&"drum", null)
	a.stop_shanty(0.02)
	await physics_frames(10)
	check(not a.is_shanty_playing(), "shanty stopped and cleaned up")


func test_ambience_mixer() -> void:
	var a := _manager()
	a.set_sea_state(0.0)
	a.set_wind(0.0)
	a.set_rain(0.0)
	a.set_shore(0.0)
	a.set_ship_speed(0.0)
	a.set_below_deck(0.0)
	a.set_underwater(false)
	a.snap_ambience()
	var lv: Dictionary = a.ambience_levels()
	check_near(lv[&"sea_calm"], 1.0, 0.001)
	check_near(lv[&"sea_rough"], 0.0, 0.001)
	check_near(lv[&"wind_storm"], 0.0, 0.001)
	check(not a.is_underwater_filter_on(), "filter off on the surface")
	# equal-power crossfade keeps the sea's power constant on the way up
	for s in [0.0, 0.25, 0.5, 0.75, 1.0]:
		a.set_sea_state(s)
		a.snap_ambience()
		lv = a.ambience_levels()
		check_near(lv[&"sea_calm"] ** 2 + lv[&"sea_rough"] ** 2, 1.0, 0.001, "sea power at %.2f" % s)
	a.set_wind(1.0)
	a.set_rain(1.0)
	a.snap_ambience()
	lv = a.ambience_levels()
	check_near(lv[&"wind_storm"], 1.0, 0.001)
	check_near(lv[&"wind_light"], 0.0, 0.001)
	check_near(lv[&"rain"], 1.0, 0.001)
	# below deck: weather ducks, creaks come up
	a.set_below_deck(1.0)
	a.snap_ambience()
	lv = a.ambience_levels()
	check_near(lv[&"below_deck"], 1.0, 0.001)
	check(lv[&"rain"] < 0.6, "rain is quieter in the hold")
	# under water: surface layers gone, filter on, and it eases rather than snaps
	a.set_underwater(true)
	await physics_frames(3)
	lv = a.ambience_levels()
	check(lv[&"underwater"] > 0.0 and lv[&"underwater"] < 1.0, "underwater blend is smoothed")
	check(a.is_underwater_filter_on(), "low-pass engages")
	a.snap_ambience()
	lv = a.ambience_levels()
	check_near(lv[&"underwater"], 1.0, 0.001)
	check_near(lv[&"sea_rough"], 0.0, 0.001)
	a.set_underwater(false)
	a.snap_ambience()
	check(not a.is_underwater_filter_on(), "low-pass releases")
	# out-of-range input is clamped
	a.set_sea_state(7.0)
	a.set_wind(-3.0)
	a.snap_ambience()
	lv = a.ambience_levels()
	check_near(lv[&"sea_rough"], 1.0 * (1.0 - 0.5), 0.001)
	a.set_below_deck(0.0)
	a.set_sea_state(0.2)
	a.set_wind(0.2)
	a.set_rain(0.0)
	a.snap_ambience()
	await physics_frames(2)


func test_q21b_sea_soundscape_heavy_swell_hull_groans_and_underwater_bubbles() -> void:
	var a := _manager()
	var saved_weather := Weather.get_state()
	var saved_amp := Sea.amp_scale
	var warned_before := Audio._warned.size()
	Weather.day_length_seconds = 0.0
	Weather.lightning_enabled = false

	# 1. Verify Q21B SFX constants resolve to registered manifest keys with zero unknown-SFX warnings.
	check_eq(SeaSoundscape.SFX_HULL_GROAN, &"hull_creak",
		"SFX_HULL_GROAN maps to manifest-verified &'hull_creak'")
	check_eq(SeaSoundscape.SFX_UNDERWATER_BUBBLE, &"hold_slosh",
		"SFX_UNDERWATER_BUBBLE maps to manifest-verified &'hold_slosh'")
	for key: StringName in [SeaSoundscape.SFX_HULL_GROAN, SeaSoundscape.SFX_UNDERWATER_BUBBLE]:
		check(Audio.has_sound(key) and a.has_sound(key),
			"manifest registers verified sound '%s'" % String(key))

	var ship_proxy := Node3D.new()
	ship_proxy.name = "Q21BShipProxy"
	add_child(ship_proxy)
	var listener_node := Node3D.new()
	listener_node.name = "Q21BListener"
	add_child(listener_node)

	var soundscape := SeaSoundscape.new()
	soundscape.set_physics_process(false)
	add_child(soundscape)
	soundscape.bind_ship(ship_proxy)
	soundscape.bind_listener(listener_node)

	var emitted_keys: Array[StringName] = []
	var emitted_vols: Dictionary = {}
	soundscape.sfx_triggered.connect(func(k: StringName, vol_db: float) -> void:
		emitted_keys.append(k)
		emitted_vols[k] = vol_db
	)

	# 2. Flat calm sea & above-water listener stay completely silent for both Q21B layers.
	Sea.amp_scale = 0.0
	Weather.set_weather(0.0, 6.0, 0.0)
	Weather.time_of_day = 12.0
	ship_proxy.global_position = Vector3(-900.0, 0.0, 0.0)
	ship_proxy.rotation = Vector3.ZERO
	listener_node.global_position = Vector3(-900.0, 3.0, 0.0)

	soundscape.tick_soundscape(0.1)
	soundscape.tick_soundscape(6.0)
	check_eq(soundscape.get_hull_groan_count(), 0, "flat calm sea emits zero heavy-swell hull groans")
	check_eq(soundscape.get_underwater_bubble_count(), 0, "above-water listener emits zero underwater bubbles")

	# Level deck in calm weather with waves active stays silent too.
	Sea.amp_scale = 1.0
	soundscape.tick_soundscape(0.1)
	check_eq(soundscape.get_hull_groan_count(), 0, "level calm ship emits zero heavy-swell hull groans")

	# 3. Heavy-swell hull timber groans on rolling ship in active waves (5.5..9.5 s cooldown).
	Sea.amp_scale = 0.90
	ship_proxy.rotation = Vector3(0.0, 0.0, 0.18)  # abs(roll) >= 0.12
	soundscape.tick_soundscape(0.1)
	check_eq(soundscape.get_hull_groan_count(), 1,
		"rolling ship (0.18 rad) in active swell emits heavy-swell hull timber groan")
	check_eq(soundscape.hull_groan_count, 1, "hull_groan_count matches getter")
	var groan_db := float(emitted_vols.get(SeaSoundscape.SFX_HULL_GROAN, 0.0))
	check(groan_db >= -11.51 and groan_db <= -2.49,
		"hull groan volume stays within nautical mix bounds (got %.2f dB)" % groan_db)

	# Cooldown gating prevents spam over 4.0 s (< 5.5 s min cooldown).
	for _i in 4:
		soundscape.tick_soundscape(1.0)
	check_eq(soundscape.get_hull_groan_count(), 1,
		"heavy-swell hull groan 5.5..9.5 s cooldown prevents rapid spam")

	# Advancing past max cooldown (total 10.5 s > 9.5 s) re-triggers cleanly.
	soundscape.tick_soundscape(6.5)
	check_eq(soundscape.get_hull_groan_count(), 2,
		"heavy-swell hull groan re-triggers after 5.5..9.5 s cooldown")

	# Stormy active sea triggers hull groan even on level deck, and pitching bow triggers in calm waves.
	soundscape.reset_state()
	ship_proxy.rotation = Vector3.ZERO
	Weather.set_weather(0.65, 18.0, 0.0)  # storminess >= 0.45
	Sea.amp_scale = 0.85
	soundscape.tick_soundscape(0.1)
	check_eq(soundscape.get_hull_groan_count(), 1,
		"stormy sea (0.65 >= 0.45) with active waves emits heavy-swell hull groan")

	Weather.set_weather(0.05, 8.0, 0.0)
	ship_proxy.rotation = Vector3(0.16, 0.0, 0.0)  # abs(pitch) >= 0.12
	soundscape.tick_soundscape(10.0)
	check_eq(soundscape.get_hull_groan_count(), 2,
		"pitching ship (0.16 rad >= 0.12) in active waves emits heavy-swell hull groan")

	# Flat waves (Sea.amp_scale < 0.55) suppress heavy-swell hull groans.
	Sea.amp_scale = 0.0
	Weather.set_weather(0.75, 20.0, 0.0)
	ship_proxy.rotation = Vector3(0.0, 0.0, 0.20)
	soundscape.tick_soundscape(10.0)
	check_eq(soundscape.get_hull_groan_count(), 2,
		"inactive waves (Sea.amp_scale=0.0 < 0.55) suppress heavy-swell hull groans")

	# 4. Underwater submersion bubble ambiance (depth >= 0.65 m, not in dry hull, 3.2..5.8 s cooldown).
	Sea.amp_scale = 0.0
	Weather.set_weather(0.0, 6.0, 0.0)
	ship_proxy.rotation = Vector3.ZERO
	soundscape.reset_state()
	emitted_vols.clear()

	# Above water and shallow dip (< 0.65 m) emit zero bubbles.
	listener_node.global_position = Vector3(-900.0, 2.0, 0.0)
	soundscape.tick_soundscape(0.1)
	soundscape.tick_soundscape(6.0)
	check_eq(soundscape.get_underwater_bubble_count(), 0, "above water emits zero underwater bubbles")

	soundscape.tick_soundscape(0.1, 0.40, false)
	check_eq(soundscape.get_underwater_bubble_count(), 0,
		"shallow submersion (0.40 m < 0.65 m) emits zero underwater bubbles")

	# Submerged inside a dry hull suppresses underwater bubbles completely.
	soundscape.tick_soundscape(0.1, 1.50, true)
	soundscape.tick_soundscape(6.0, 1.50, true)
	check_eq(soundscape.get_underwater_bubble_count(), 0,
		"dry hull interior suppresses underwater submersion bubble ambiance")

	# Submerged listener (depth = 1.40 m >= 0.65 m) triggers soft muffled bubbles with cooldown gating.
	listener_node.global_position = Vector3(-900.0, -1.40, 0.0)
	soundscape.tick_soundscape(0.1)
	check_eq(soundscape.get_underwater_bubble_count(), 1,
		"submerged listener (1.40 m >= 0.65 m) triggers underwater bubble ambiance")
	check_eq(soundscape.underwater_bubble_count, 1, "underwater_bubble_count matches getter")
	var bubble_db := float(emitted_vols.get(SeaSoundscape.SFX_UNDERWATER_BUBBLE, 0.0))
	check(bubble_db >= -16.51 and bubble_db <= -12.49,
		"underwater bubble volume stays quietly muffled in -16.5..-12.5 dB (got %.2f dB)" % bubble_db)

	# Cooldown gating prevents spam over 2.5 s (< 3.2 s min cooldown).
	soundscape.tick_soundscape(2.5)
	check_eq(soundscape.get_underwater_bubble_count(), 1,
		"underwater bubble 3.2..5.8 s cooldown prevents rapid spam")

	# Advancing past max cooldown (total 6.5 s > 5.8 s) re-triggers cleanly.
	soundscape.tick_soundscape(4.0)
	check_eq(soundscape.get_underwater_bubble_count(), 2,
		"underwater bubble re-triggers cleanly after 3.2..5.8 s cooldown")

	# Surfacing stops underwater bubbles immediately.
	listener_node.global_position = Vector3(-900.0, 1.20, 0.0)
	soundscape.tick_soundscape(7.0)
	check_eq(soundscape.get_underwater_bubble_count(), 2,
		"surfacing above water silences underwater bubble ambiance")

	# Still works when diving away from any ship (ship == null).
	soundscape.ship = null
	soundscape.tick_soundscape(0.1, 2.0, false)
	check_eq(soundscape.get_underwater_bubble_count(), 3,
		"underwater bubble ambiance works even when not aboard a ship")

	# 5. Audit all emitted keys against Audio manifest & confirm zero unknown-SFX warnings!
	check(emitted_keys.size() >= 6, "emitted at least 6 Q21B soundscape events (got %d)" % emitted_keys.size())
	for k: StringName in emitted_keys:
		check(Audio.has_sound(k), "emitted SFX key '%s' is registered in manifest.json" % String(k))
	check_eq(Audio._warned.size(), warned_before, "zero unknown-SFX warnings emitted during Q21B soundscape test")

	# 6. Clean zero-leak teardown.
	soundscape.queue_free()
	ship_proxy.queue_free()
	listener_node.queue_free()
	await physics_frames(2)
	check(not is_instance_valid(soundscape), "Q21B SeaSoundscape frees cleanly with 0 leaks")
	check(not is_instance_valid(ship_proxy) and not is_instance_valid(listener_node),
		"Q21B helper nodes free cleanly with 0 leaks")
	Weather.apply_state(saved_weather)
	Sea.amp_scale = saved_amp


func test_zz_shutdown_is_clean() -> void:
	# Last on purpose: free the manager and give the audio thread a few mix
	# cycles to let go of its playbacks, so the run exits without leak reports.
	var a := _manager()
	a.play_music(&"sailing", 0.0)
	a.play_shanty()
	await physics_frames(2)
	a.queue_free()
	audio = null
	for i in 12:
		await get_tree().process_frame
		OS.delay_msec(10)
	check(not is_instance_valid(a), "manager freed")
