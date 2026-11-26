extends TestCase
## Headless tests for AI CrewBrain: survival priority (patch & bail), captain orders
## (helm, trim, anchor, cannons), lookout callouts, shanty joining, and co-op yield.

const SLOOP_SCENE: PackedScene = preload("res://src/ship/sloop.tscn")
const PAWN_SCENE: PackedScene = preload("res://src/characters/pawn.tscn")
const SPEEDUP := 6

var _root: Node3D
var _saved_weather: Dictionary
var _saved_amp: float = 1.0


func _fast(on: bool) -> void:
	Engine.physics_ticks_per_second = 60 * (SPEEDUP if on else 1)
	Engine.time_scale = float(SPEEDUP) if on else 1.0
	Engine.max_physics_steps_per_frame = 8 * (SPEEDUP if on else 1)


func _begin() -> void:
	_saved_weather = Weather.get_state()
	_saved_amp = Sea.amp_scale
	Net.start_single_player()
	Weather.day_length_seconds = 0.0
	Weather.lightning_enabled = false
	Weather.set_weather(0.0, 10.0, 0.0)
	Sea.amp_scale = 0.0
	_fast(true)
	_root = Node3D.new()
	add_child(_root)


func _end() -> void:
	Audio.stop_shanty(0.01)
	_root.queue_free()
	_root = null
	await physics_frames(2)
	_fast(false)
	Weather.apply_state(_saved_weather)
	Sea.amp_scale = _saved_amp


func _make_crew(s: Ship, captain: Pawn, persona: StringName, local_pos: Vector3) -> Array:
	var p := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(p)
	p.board(s, local_pos)
	var brain := CrewBrain.new()
	brain.setup(s, captain, persona)
	p.add_child(brain)
	return [p, brain]


func test_survival_priority_patches_breach_and_bails_hold() -> void:
	_begin()
	var s := SLOOP_SCENE.instantiate() as Ship
	s.enable_effects = false
	_root.add_child(s)
	await physics_frames(20)

	var pair := _make_crew(s, null, &"carpenter", Vector3(0.0, 1.12, 1.8))
	var brain: CrewBrain = pair[1]
	# Even when ordered to trim sails, a hull breach must preempt everything!
	s.set_sail_target(1.0)
	s.sail_set = 1.0
	s.sail_trim = 1.1
	brain.give_order(&"trim")
	await physics_frames(10)

	var slot := s.apply_hull_damage(s.global_transform * Vector3(2.0, -0.45, 0.4), 0.5)
	s.water_level = 0.25
	check_eq(s.open_hole_count(), 1, "breach created")

	var patched := false
	for _i in 650:
		await physics_frames(1)
		if s.open_hole_count() == 0:
			patched = true
			break
	print("    crew patched breach slot %d: %s, water_level=%.3f" % [slot, str(patched), s.water_level])
	check(patched, "AI crewmate must navigate to hold and patch open breach")

	# Now crewmate should bail the remaining bilge water down near zero.
	var water_before := s.water_level
	for _i in 500:
		await physics_frames(1)
		if s.water_level < 0.03:
			break
	print("    crew bailed water from %.3f -> %.3f" % [water_before, s.water_level])
	check(s.water_level < water_before - 0.12, "AI crewmate must bail hold water after patching")
	await _end()


func test_autonomous_trim_and_anchor_orders() -> void:
	_begin()
	Weather.set_weather(0.0, 11.0, 0.6)
	var s := SLOOP_SCENE.instantiate() as Ship
	s.enable_effects = false
	_root.add_child(s)
	await physics_frames(20)

	var pair := _make_crew(s, null, &"helmsman", Vector3(0.5, 1.12, 0.5))
	var brain: CrewBrain = pair[1]

	# Sail is raised but trimmed way off ideal; crewmate should autonomously trim it.
	s.set_sail_target(1.0)
	s.sail_set = 1.0
	s.set_trim_target(0.9)
	s.sail_trim = 0.9
	var err_before := absf(s.sail_trim - s.ideal_sail_trim())
	check(err_before > 0.6, "initial trim should be far from ideal")

	for _i in 450:
		await physics_frames(1)
		if absf(s.sail_trim - s.ideal_sail_trim()) < 0.14:
			break
	var err_after := absf(s.sail_trim - s.ideal_sail_trim())
	print("    autonomous trim error: %.2f -> %.2f rad" % [err_before, err_after])
	check(err_after < 0.22, "AI crewmate should trim sails close to ideal wind angle")

	# Captain orders drop anchor -> crewmate runs to capstan and drops it.
	brain.give_order(&"anchor_drop")
	for _i in 450:
		await physics_frames(1)
		if s.anchor_down and s.anchor_progress > 0.9:
			break
	check(s.anchor_down and s.anchor_progress > 0.9, "anchor_drop order must drop anchor")

	# Captain orders raise anchor -> crewmate winds it back up.
	brain.give_order(&"anchor_raise")
	for _i in 520:
		await physics_frames(1)
		if not s.anchor_down and s.anchor_progress < 0.1:
			break
	check(not s.anchor_down and s.anchor_progress < 0.1, "anchor_raise order must raise anchor")
	await _end()


func test_lookout_callouts_cannon_gunnery_and_shanty() -> void:
	_begin()
	var s := SLOOP_SCENE.instantiate() as Ship
	s.enable_effects = false
	_root.add_child(s)
	var enemy := SLOOP_SCENE.instantiate() as Ship
	enemy.enable_effects = false
	enemy.faction = &"drowned"
	_root.add_child(enemy)
	enemy.global_position = Vector3(36.0, 0.0, -1.5)

	var fake_island := Node3D.new()
	fake_island.name = "CutlassCay"
	fake_island.add_to_group(&"islands")
	fake_island.set_meta("display_name", "Cutlass Cay")
	_root.add_child(fake_island)
	fake_island.global_position = Vector3(0.0, 0.0, -260.0)
	await physics_frames(15)

	var pair := _make_crew(s, null, &"lookout", Vector3(1.1, 1.12, -1.5))
	var pawn: Pawn = pair[0]
	var brain: CrewBrain = pair[1]

	var spoken: Array[StringName] = []
	brain.callout_spoken.connect(func(_sp: String, _txt: String, cat: StringName) -> void:
		spoken.append(cat)
	)
	var fired := [false]
	s.cannon_fired.connect(func(_side: StringName, _b: Cannonball) -> void: fired[0] = true)

	for _i in 320:
		await physics_frames(1)
		if fired[0] and spoken.has(&"sail_sighted") and spoken.has(&"land_ho"):
			break
	print("    lookout callouts=%s cannon_fired=%s" % [str(spoken), str(fired[0])])
	check(spoken.has(&"land_ho"), "crewmate must call out nearby island")
	check(spoken.has(&"sail_sighted"), "crewmate must call out hostile ship")
	check(fired[0], "crewmate must man cannon and fire on hostile sloop in broadside")

	# Remove enemy & verify shanty join + co-op yield.
	enemy.queue_free()
	await physics_frames(5)
	brain.give_order(&"shanty")
	await physics_frames(20)
	check(Audio.is_shanty_playing(), "shanty order starts/joins shanty")

	brain.yield_to_human_player()
	check(pawn.station == null, "yielding to human releases station")
	await _end()
