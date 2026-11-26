extends TestCase
## Headless tests for Living World Beasts:
## - SeabirdFlock: articulated gull meshes, elliptical orbiting, wing flapping, distance culling.
## - IslandCrab: guard anchor, hostile Pawn detection, 0.55 s raised-claw telegraph & lunge,
##   windup-interrupt stagger, apply_damage, defeated signal & edible/cookable crab-claw drop.
## - ReefEel: 7-segment underwater ambush predator, sinusoidal body undulation, swimmer
##   detection & bite + retreat, retreat on damage, apply_damage & defeated signal.
## - CoralReef: strictly 3 batched MultiMeshInstance3D draw calls, distance culling,
##   underwater depth placement, mooring keepout, static mesh sharing, clean teardown.

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
	Weather.set_weather(0.0, 8.0, 0.0)
	Sea.amp_scale = 0.0
	_fast(true)
	_root = Node3D.new()
	add_child(_root)


func _end() -> void:
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	await physics_frames(2)
	_fast(false)
	Weather.apply_state(_saved_weather)
	Sea.amp_scale = _saved_amp


func _ground(y_center: float = 4.5) -> StaticBody3D:
	var g := StaticBody3D.new()
	g.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(120.0, 1.0, 120.0)
	cs.shape = bx
	g.add_child(cs)
	_root.add_child(g)
	g.global_position = Vector3(0.0, y_center, 0.0)
	return g


func _spawn_pawn(pos: Vector3, faction: StringName = &"player") -> Pawn:
	var p := PAWN_SCENE.instantiate() as Pawn
	var cc := CombatComponent.new()
	cc.name = "CombatComponent"
	cc.faction = faction
	p.add_child(cc)
	_root.add_child(p)
	p.global_position = pos
	return p


func test_seabird_flock_orbits_flaps_and_culls() -> void:
	_begin()
	var anchor := Vector3(24.0, 0.0, -18.0)
	var flock := SeabirdFlock.spawn_over(_root, anchor, 14.0, 16.0, 6)
	var birds := flock.get_birds()

	check(flock.is_loot_marker, "spawn_over marks flock as a loot marker")
	check(flock.is_in_group(SeabirdFlock.GROUP), "flock registers in seabird_flocks group")
	check_eq(birds.size(), 6, "flock spawns requested gull count")

	var start_positions: Array[Vector3] = []
	var max_wing_delta := 0.0
	var prev_wing_z: Array[float] = []

	for b in birds:
		var wl := b.get_node_or_null(^"WingL") as Node3D
		var wr := b.get_node_or_null(^"WingR") as Node3D
		var body_mi := b.get_node_or_null(^"Body") as MeshInstance3D
		check(wl != null and wr != null, "gull has articulated WingL and WingR pivots")
		check(body_mi != null and body_mi.mesh != null and body_mi.mesh.get_surface_count() > 0,
			"gull body has procedural mesh surfaces")
		start_positions.append(b.global_position)
		prev_wing_z.append(wr.rotation.z if wr != null else 0.0)

	# Advance 2.5 s of flight and check orbital movement + wing articulation.
	for _step in 50:
		flock.step_flock(0.05)
		for i in birds.size():
			var wr := birds[i].get_node_or_null(^"WingR") as Node3D
			if wr != null:
				max_wing_delta = maxf(max_wing_delta, absf(wr.rotation.z - prev_wing_z[i]))

	var moved_count := 0
	for i in birds.size():
		var dist_moved := birds[i].global_position.distance_to(start_positions[i])
		if dist_moved > 3.0:
			moved_count += 1
		var horiz := Vector2(birds[i].global_position.x - anchor.x, birds[i].global_position.z - anchor.z).length()
		check(horiz > 5.0 and horiz < 32.0, "gull stays in elliptical orbit around anchor (horiz=%.2f)" % horiz)
		check(birds[i].global_position.y > 9.0 and birds[i].global_position.y < 24.0,
			"gull maintains orbit height band (y=%.2f)" % birds[i].global_position.y)

	check_eq(moved_count, birds.size(), "all gulls orbit smoothly over time")
	check(max_wing_delta > 0.20, "articulated gull wings visibly flap (delta=%.3f)" % max_wing_delta)

	# Verify > 320 m distance culling skips wing animation updates cleanly.
	var cam := Camera3D.new()
	_root.add_child(cam)
	cam.global_position = anchor + Vector3(420.0, 20.0, 0.0)
	cam.current = true
	var wr0 := birds[0].get_node(^"WingR") as Node3D
	var wing_before_cull := wr0.rotation.z
	flock.step_flock(0.08)
	check(flock.wing_anim_culled, "flock culls wing updates beyond 320 m from camera")
	check_near(wr0.rotation.z, wing_before_cull, 0.0001, "culled wing rotation remains frozen")

	cam.global_position = anchor + Vector3(60.0, 12.0, 0.0)
	flock.step_flock(0.08)
	check(not flock.wing_anim_culled, "flock resumes wing updates within 320 m of camera")
	await _end()


func test_island_crab_guards_telegraphs_strikes_staggers_and_dies() -> void:
	_begin()
	_ground(4.5)

	var crab := IslandCrab.spawn_at(_root, Vector3(0.0, 5.05, -2.2), 12.0)
	check_near(crab.health, 45.0, 0.01, "crab spawns with 45.0 health")
	check_eq(crab.faction, &"beast", "crab uses beast faction")
	check_eq(crab.collision_layer, Pawn.LAYER_PAWN, "crab sits on LAYER_PAWN for combat hit detection")
	check(not crab.dead, "crab starts alive")
	check(crab.get_node_or_null(^"ClawL") != null and crab.get_node_or_null(^"ClawR") != null,
		"crab builds articulated ClawL and ClawR pincers")

	var hero := _spawn_pawn(Vector3(0.0, 5.05, 0.0), &"player")
	var telegraphed := [false]
	var max_telegraph_claw_pitch := [0.0]
	var struck_dmg := [0.0]
	var staggered_seen := [false]
	var defeated_crab: Array = [null]
	var dropped_item: Array = [{}]

	crab.attack_telegraphed.connect(func(_c: IslandCrab, _t: Node3D) -> void:
		telegraphed[0] = true
	)
	crab.lunge_struck.connect(func(_t: Node3D, dmg: float) -> void:
		struck_dmg[0] = dmg
	)
	crab.staggered.connect(func(_dur: float) -> void:
		staggered_seen[0] = true
	)
	crab.defeated.connect(func(c: IslandCrab, _pos: Vector3) -> void:
		defeated_crab[0] = c
	)
	crab.loot_dropped.connect(func(payload: Dictionary, _pos: Vector3) -> void:
		dropped_item[0] = payload
	)

	var hero_hp0 := hero.health
	for _i in 180:
		await physics_frames(1)
		if crab.is_telegraphing() and crab.claw_r != null:
			max_telegraph_claw_pitch[0] = maxf(max_telegraph_claw_pitch[0], crab.claw_r.rotation.x)
		if struck_dmg[0] > 0.0:
			break

	check(telegraphed[0], "crab detects hostile Pawn and enters pincer telegraph")
	check(max_telegraph_claw_pitch[0] > 0.35,
		"crab raises pincers high during 0.55 s telegraph (pitch=%.2f)" % max_telegraph_claw_pitch[0])
	check_near(struck_dmg[0], 14.0, 0.01, "crab lunge deals 14.0 damage")
	check_near(hero_hp0 - hero.health, 14.0, 0.01, "hostile Pawn takes 14.0 damage from pincer lunge")

	# Striking the crab during its windup staggers it cleanly!
	crab.state = IslandCrab.State.TELEGRAPH
	crab._state_timer = 0.45
	crab.apply_damage(15.0, hero)
	check(staggered_seen[0] and crab.is_staggered(), "striking crab during telegraph windup triggers stagger")
	check_near(crab.health, 30.0, 0.01, "apply_damage reduces crab health accurately")

	# Lethal damage kills crab, emits defeated, and drops a cookable/edible crab claw.
	crab.apply_damage(60.0, hero)
	check(crab.dead, "lethal damage marks crab dead")
	check_near(crab.health, 0.0, 0.01, "dead crab health clamps to 0")
	check_eq(defeated_crab[0], crab, "defeated signal emits defeated crab reference")
	var item: Dictionary = dropped_item[0]
	check(not item.is_empty(), "defeated crab emits loot_dropped payload")
	check(bool(item.get("cookable", false)) and bool(item.get("edible", false)),
		"dropped crab claw is marked cookable and edible")
	check(float(item.get("heal", 0.0)) > 0.0, "dropped crab claw restores health")

	# Verify guard-anchor return when displaced outside guard_radius with no targets.
	hero.queue_free()
	await physics_frames(2)
	var guard_crab := IslandCrab.spawn_at(_root, Vector3(30.0, 5.05, 0.0), 10.0)
	guard_crab.global_position = Vector3(50.0, 5.05, 0.0)
	var dist_before := guard_crab.global_position.distance_to(guard_crab.guard_origin)
	await physics_frames(45)
	var dist_after := guard_crab.global_position.distance_to(guard_crab.guard_origin)
	check(dist_after < dist_before - 1.5,
		"displaced crab returns toward guard_origin (%.2f -> %.2f)" % [dist_before, dist_after])
	await _end()


func test_reef_eel_lurks_ambushes_swimmer_retreats_and_dies() -> void:
	_begin()
	var lair_pos := Vector3(32.0, -3.2, 32.0)
	var eel := ReefEel.spawn_at(_root, lair_pos, 18.0, 3.2)

	check_near(eel.health, 35.0, 0.01, "eel spawns with 35.0 health")
	check_eq(eel.faction, &"beast", "eel uses beast faction")
	check(not eel.dead, "eel starts alive")
	check_eq(eel.segments.size(), 7, "eel builds 7 undulating body segments")
	check(eel.lower_jaw != null, "eel head has articulated snapping lower jaw")
	var surf := Sea.height(eel.global_position.x, eel.global_position.z)
	var depth := surf - eel.global_position.y
	check(depth >= 1.5 and depth <= 8.0, "eel lurks underwater in 1.5..8.0 m reef shallows (depth=%.2f)" % depth)

	# Verify sinusoidal undulation animates segments smoothly over ~0.53 s.
	var tail_x_samples: Array[float] = []
	for _k in 32:
		await physics_frames(1)
		tail_x_samples.append(eel.segments[6].position.x)
	var min_x := tail_x_samples[0]
	var max_x := tail_x_samples[0]
	for v in tail_x_samples:
		min_x = minf(min_x, v)
		max_x = maxf(max_x, v)
	check(max_x - min_x > 0.08, "eel tail undulates sinusoidally (span=%.3f)" % (max_x - min_x))

	# Connect signals before spawning the swimmer so ambush_started is never missed.
	var ambushed := [false]
	var bite_dmg := [0.0]
	eel.ambush_started.connect(func(_e: ReefEel, _t: Pawn) -> void:
		ambushed[0] = true
	)
	eel.bit_target.connect(func(_t: Pawn, dmg: float) -> void:
		bite_dmg[0] = dmg
	)

	var swimmer := _spawn_pawn(Vector3(36.0, -1.35, 32.0), &"player")
	var hp0 := swimmer.health
	var saw_swimming := false
	for _i in 260:
		await physics_frames(1)
		if swimmer.is_swimming():
			saw_swimming = true
		if bite_dmg[0] > 0.0:
			break

	check(saw_swimming, "target Pawn enters swimming mode in coastal water")
	check(ambushed[0], "eel detects swimming Pawn and starts ambush")
	check_near(bite_dmg[0], 16.0, 0.01, "eel bite deals 16.0 damage")
	check_near(hp0 - swimmer.health, 16.0, 0.01, "swimming Pawn takes 16.0 damage from reef eel")
	check_eq(eel.state, ReefEel.State.RETREAT, "eel retreats to reef crevice after biting")

	# Taking damage forces a lurking eel to retreat; lethal damage kills it and emits defeated.
	var eel2 := ReefEel.spawn_at(_root, Vector3(80.0, -3.5, 80.0), 18.0, 3.5)
	var defeated_eel: Array = [null]
	eel2.defeated.connect(func(e: ReefEel, _pos: Vector3) -> void:
		defeated_eel[0] = e
	)
	await physics_frames(4)
	check_eq(eel2.state, ReefEel.State.LURK, "undisturbed eel lurks in its reef lair")
	eel2.apply_damage(12.0, swimmer)
	check_near(eel2.health, 23.0, 0.01, "apply_damage reduces eel health accurately")
	check_eq(eel2.state, ReefEel.State.RETREAT, "damaged eel immediately retreats toward its crevice")

	eel2.apply_damage(40.0, swimmer)
	check(eel2.dead, "lethal damage marks eel dead")
	check_near(eel2.health, 0.0, 0.01, "dead eel health clamps to 0")
	check_eq(defeated_eel[0], eel2, "defeated signal emits defeated eel reference")
	await _end()


func test_coral_reef_multimesh_budget_and_depth_placement() -> void:
	_begin()

	var lagoon := IslandGenerator.build_island({
		"id": "test_crescent_reef",
		"name": "Crescent Reef",
		"archetype": &"crescent_lagoon",
		"seed": 8803,
	})
	_root.add_child(lagoon)

	var reef := CoralReef.populate_for_island(lagoon, 4242, 1.0)
	check(reef != null, "populate_for_island returns a valid CoralReef node")
	check_eq(reef.get_parent(), lagoon, "CoralReef attaches cleanly as child of Island")
	check(reef.is_in_group(CoralReef.GROUP), "CoralReef registers in coral_reefs group")
	check_eq(reef.get_multimesh_count(), 3, "CoralReef uses strictly 3 MultiMeshInstance3D draw calls")
	check(reef.find_children("*", "MeshInstance3D", true, false).is_empty(),
		"CoralReef spawns zero per-coral MeshInstance3D nodes")

	var total := reef.get_total_instance_count()
	check(total >= 100, "CoralReef populates >= 100 underwater instances (got %d)" % total)
	check(reef.get_staghorn_count() >= 30,
		"StaghornCorals populates rich branching clusters (got %d)" % reef.get_staghorn_count())
	check(reef.get_brain_coral_count() >= 24,
		"BrainTableCorals populates fluted reef mounds (got %d)" % reef.get_brain_coral_count())
	check(reef.get_kelp_count() >= 70,
		"KelpFronds populates swaying kelp tufts (got %d)" % reef.get_kelp_count())

	var depth_range := reef.get_reef_bounds_depth_range()
	check(depth_range.y <= -0.55,
		"all reef roots sit strictly underwater (max_y=%.2f <= -0.55)" % depth_range.y)
	check(depth_range.x >= -11.0,
		"all reef roots stay above deep abyss (min_y=%.2f >= -11.0)" % depth_range.x)
	check(depth_range.x < depth_range.y,
		"reef spans natural underwater depth shelf (%.2f .. %.2f)" % [depth_range.x, depth_range.y])

	# Inspect all 3 MultiMeshes directly: culling, shadows, mesh surfaces, shader binding.
	var mooring_xz := Vector2(lagoon.mooring_transform.origin.x, lagoon.mooring_transform.origin.z)
	var expected_names: Array[String] = ["StaghornCorals", "BrainTableCorals", "KelpFronds"]
	var mm_instance_sum := 0

	for mm_name in expected_names:
		var mmi := reef.get_node_or_null(NodePath(mm_name)) as MultiMeshInstance3D
		check(mmi != null, "CoralReef creates MultiMeshInstance3D '%s'" % mm_name)
		if mmi == null:
			continue
		check_eq(mmi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"%s disables shadow casting for zero shadow-pass cost" % mm_name)
		check_near(mmi.visibility_range_end, 155.0, 0.01,
			"%s culls cleanly at 155 m visibility range" % mm_name)
		check_eq(mmi.visibility_range_fade_mode, GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED,
			"%s uses hard visibility range cutoff" % mm_name)
		check(mmi.multimesh != null and mmi.multimesh.mesh != null,
			"%s owns a valid MultiMesh with sculpted procedural mesh" % mm_name)
		check(mmi.multimesh.use_colors, "%s enables per-instance MultiMesh color tinting" % mm_name)
		check(mmi.multimesh.mesh.get_surface_count() == 1,
			"%s procedural mesh has 1 batched surface" % mm_name)
		if mm_name == "KelpFronds":
			var sm := mmi.material_override as ShaderMaterial
			check(sm != null and sm.shader == CoralReef.KELP_SHADER,
				"KelpFronds uses coral_kelp.gdshader")
		mm_instance_sum += mmi.multimesh.instance_count

	check_eq(mm_instance_sum, total, "MultiMesh instance_count sum matches get_total_instance_count()")

	# Inspect every single placed instance transform for depth, grounding, slope, mooring keepout, handedness.
	var placed := reef.get_placed_transforms()
	check_eq(placed.size(), total, "get_placed_transforms() matches total MultiMesh instance count")
	var max_root_y := -INF
	var min_root_y := INF
	var min_mooring_dist := INF
	var max_ground_err := 0.0
	var min_normal_y := INF
	var inverted_count := 0

	for xf in placed:
		var p := xf.origin
		max_root_y = maxf(max_root_y, p.y)
		min_root_y = minf(min_root_y, p.y)
		min_mooring_dist = minf(min_mooring_dist, Vector2(p.x, p.z).distance_to(mooring_xz))
		var expected_y := lagoon.surface_height(p.x, p.z) - CoralReef.ROOT_EMBED_Y
		max_ground_err = maxf(max_ground_err, absf(p.y - expected_y))
		min_normal_y = minf(min_normal_y, lagoon.surface_normal(p.x, p.z).y)
		if xf.basis.determinant() <= 0.0:
			inverted_count += 1

	check(max_root_y <= -0.55, "every single coral/kelp instance root <= -0.55 (max=%.2f)" % max_root_y)
	check(min_root_y >= -11.0, "every single coral/kelp instance root >= -11.0 (min=%.2f)" % min_root_y)
	check(min_mooring_dist >= 9.49,
		"all reef instances respect 9.5 m mooring keepout (min=%.2f m)" % min_mooring_dist)
	check(max_ground_err < 0.02,
		"all reef roots are grounded into seabed heightfield (max_err=%.4f m)" % max_ground_err)
	check(min_normal_y >= CoralReef.MIN_NORMAL_Y - 0.01,
		"all reef roots rest on gentle seabed slopes (min_ny=%.3f)" % min_normal_y)
	check_eq(inverted_count, 0, "all MultiMesh instance transforms have positive determinant")
	if DisplayServer.get_name() != "headless":
		var stag_mmi := reef.get_node(^"StaghornCorals") as MultiMeshInstance3D
		if stag_mmi != null and stag_mmi.multimesh.instance_count > 0:
			var gpu_origin := stag_mmi.multimesh.get_instance_transform(0).origin
			check(gpu_origin.distance_to(placed[0].origin) < 0.001,
				"GPU MultiMesh buffer transform matches placed transform")

	# Verify a second archetype (wreck_shoal) shares the exact 3 static cached meshes and is deterministic.
	var shoal := IslandGenerator.build_island({
		"id": "test_wreck_shoal_reef",
		"name": "Wrecker Reef",
		"archetype": &"wreck_shoal",
		"seed": 10903,
	})
	_root.add_child(shoal)
	var shoal_reef := CoralReef.populate_for_island(shoal, 7777, 1.0)
	check_eq(shoal_reef.get_multimesh_count(), 3, "wreck_shoal reef uses strictly 3 MultiMeshes")
	check(shoal_reef.get_total_instance_count() >= 100,
		"wreck_shoal reef populates >= 100 instances (got %d)" % shoal_reef.get_total_instance_count())
	var shoal_depth := shoal_reef.get_reef_bounds_depth_range()
	check(shoal_depth.y <= -0.55 and shoal_depth.x >= -11.0,
		"wreck_shoal reef depth range stays strictly underwater (%.2f .. %.2f)" % [shoal_depth.x, shoal_depth.y])

	for mm_name in expected_names:
		var mmi_a := reef.get_node(NodePath(mm_name)) as MultiMeshInstance3D
		var mmi_b := shoal_reef.get_node(NodePath(mm_name)) as MultiMeshInstance3D
		check_eq(mmi_a.multimesh.mesh, mmi_b.multimesh.mesh,
			"islands share static cached ArrayMesh for %s" % mm_name)

	var shoal_reef_dup := CoralReef.populate_for_island(shoal, 7777, 1.0)
	check_eq(shoal_reef_dup.get_total_instance_count(), shoal_reef.get_total_instance_count(),
		"identical rng_seed yields deterministic instance count")
	check_near(shoal_reef_dup.get_reef_bounds_depth_range().x, shoal_depth.x, 0.0001,
		"identical rng_seed yields deterministic min depth")
	check_near(shoal_reef_dup.get_reef_bounds_depth_range().y, shoal_depth.y, 0.0001,
		"identical rng_seed yields deterministic max depth")

	await _end()

