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
			&"sword_clash", &"parry_ring", &"hit_flesh", &"skeleton_rattle", &"pistol_shot", &"footstep_wood",
			&"footstep_sand", &"footstep_water", &"chest_thump", &"coin_jingle", &"dig_sand", &"ui_tick",
			&"thunder_near", &"thunder_far", &"seagull", &"spyglass_slide", &"lantern_click", &"grog_gulp", &"burp"]:
		check(a.has_sound(sound), "catalogue should list '%s'" % sound)
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
