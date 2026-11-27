extends TestCase
## Headless tests for Living World Beasts:
## - SeabirdFlock: articulated gull meshes, elliptical orbiting, wing flapping, distance culling.
## - IslandCrab: guard anchor, hostile Pawn detection, 0.55 s raised-claw telegraph & lunge,
##   windup-interrupt stagger, apply_damage, defeated signal & edible/cookable crab-claw drop.
## - ReefEel: 7-segment underwater ambush predator, sinusoidal body undulation, swimmer
##   detection & bite + retreat, retreat on damage, apply_damage & defeated signal.
## - CoralReef: strictly 3 batched MultiMeshInstance3D draw calls, distance culling,
##   underwater depth placement, mooring keepout, static mesh sharing, clean teardown.
## - Shark: sculpted countershaded ArrayMesh anatomy (zero raw primitives), static mesh
##   sharing across packs, 2-segment traveling S-wave tail & snapping toothed jaw on CHARGE.

const PAWN_SCENE: PackedScene = preload("res://src/characters/pawn.tscn")
const SPEEDUP := 6


class MockBrigantine:
	extends Node3D
	var ship_class: StringName = &"brigantine"


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
		var expected_vis := maxf(CoralReef.VISIBILITY_RANGE_END, lagoon.seabed_radius + 110.0)
		check_near(mmi.visibility_range_end, expected_vis, 0.05,
			"%s scales cull range with island seabed radius (%.1f m)" % [mm_name, expected_vis])
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


func test_shark_sculpted_meshes_caching_and_charge_animation() -> void:
	_begin()

	var shark_a := Shark.new()
	shark_a.name = "SharkA"
	shark_a.circle_radius = 8.0
	_root.add_child(shark_a)
	shark_a.global_position = Vector3(12.0, -0.35, 12.0)

	var shark_b := Shark.new()
	shark_b.name = "SharkB"
	shark_b.circle_radius = 8.0
	_root.add_child(shark_b)
	shark_b.global_position = Vector3(-12.0, -0.35, 12.0)

	check_near(shark_a.health, shark_a.max_health, 0.01, "shark spawns at full health")
	check_eq(shark_a.faction, &"beast", "shark preserves beast faction")
	check(shark_a.is_in_group(&"sharks") and shark_a.is_in_group(&"beasts"),
		"shark registers in sharks and beasts groups")
	var hitbox := shark_a.get_node_or_null(^"SharkHitbox") as StaticBody3D
	check(hitbox != null and hitbox.collision_layer == Pawn.LAYER_PAWN,
		"shark preserves SharkHitbox on Pawn.LAYER_PAWN")

	# Verify articulated pivots exist with sculpted ArrayMesh children.
	check(shark_a._jaw_node != null, "shark builds articulated hinged _jaw_node")
	check(shark_a._tail_mid_node != null, "shark builds articulated mid-tail _tail_mid_node")
	check(shark_a._tail_node != null, "shark builds articulated caudal fin _tail_node")
	check_eq(shark_a._tail_node.get_parent(), shark_a._tail_mid_node,
		"caudal fin _tail_node chains cleanly as child of _tail_mid_node")

	# Walk every MeshInstance3D on SharkA: strictly sculpted ArrayMeshes, zero raw primitives!
	var mesh_nodes := shark_a.find_children("*", "MeshInstance3D", true, false)
	check(mesh_nodes.size() >= 5,
		"shark builds sculpted body/eyes/jaw/tail_mid/tail_fin meshes (got %d)" % mesh_nodes.size())

	var raw_primitive_count := 0
	var total_tris := 0
	var bad_normals := 0
	var part_summary: PackedStringArray = []
	for n in mesh_nodes:
		var mi := n as MeshInstance3D
		if mi == null:
			continue
		var m := mi.mesh
		var is_raw_prim := (m is PrimitiveMesh) \
			or (m is CapsuleMesh) \
			or (m is BoxMesh) \
			or (m is PrismMesh) \
			or (m is SphereMesh) \
			or (m is CylinderMesh)
		if is_raw_prim:
			raw_primitive_count += 1
		check(m is ArrayMesh, "shark part '%s' uses sculpted ArrayMesh" % mi.name)
		if m is ArrayMesh:
			var am := m as ArrayMesh
			check(am.get_surface_count() > 0, "shark ArrayMesh '%s' has surface geometry" % mi.name)
			if am.get_surface_count() > 0:
				var arrays := am.surface_get_arrays(0)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var tris := floori(float(indices.size()) / 3.0) if indices.size() > 0 else floori(float(verts.size()) / 3.0)
				check(tris > 0, "shark ArrayMesh '%s' has non-zero triangles (%d)" % [mi.name, tris])
				for nv in norms:
					if not nv.is_finite() or nv.length_squared() < 0.5:
						bad_normals += 1
				total_tris += tris
				part_summary.append("%s=%d" % [mi.name, tris])

	print("    shark sculpted meshes: %s (total=%d tris)" % [", ".join(part_summary), total_tris])
	check_eq(raw_primitive_count, 0,
		"shark has zero raw primitive CapsuleMesh/BoxMesh/PrismMesh/SphereMesh meshes")
	check_eq(bad_normals, 0, "all sculpted shark mesh normals are finite unit vectors")
	check(total_tris >= 900,
		"shark has richly sculpted faceted triangle budget (got %d tris)" % total_tris)

	# Verify static ArrayMesh caching shares identical resources across shark pack instances.
	var part_names: Array[String] = ["BodyMesh", "EyesMesh", "JawMesh", "TailMidMesh", "TailFinMesh"]
	for part in part_names:
		var mi_a := shark_a.find_child(part, true, false) as MeshInstance3D
		var mi_b := shark_b.find_child(part, true, false) as MeshInstance3D
		check(mi_a != null and mi_b != null, "both sharks contain sculpted '%s'" % part)
		if mi_a != null and mi_b != null:
			check_eq(mi_a.mesh, mi_b.mesh,
				"shark pack shares static cached ArrayMesh for '%s'" % part)

	# Step CIRCLE state for ~1.15 s (70 physics ticks) and record baseline undulation + closed jaw.
	shark_a.state = Shark.State.CIRCLE
	shark_a._state_timer = 10.0
	var circle_mid_min := INF
	var circle_mid_max := -INF
	var circle_fin_min := INF
	var circle_fin_max := -INF
	for _i in 70:
		await physics_frames(1)
		circle_mid_min = minf(circle_mid_min, shark_a._tail_mid_node.rotation.y)
		circle_mid_max = maxf(circle_mid_max, shark_a._tail_mid_node.rotation.y)
		circle_fin_min = minf(circle_fin_min, shark_a._tail_node.rotation.y)
		circle_fin_max = maxf(circle_fin_max, shark_a._tail_node.rotation.y)

	var circle_mid_span := circle_mid_max - circle_mid_min
	var circle_fin_span := circle_fin_max - circle_fin_min
	var circle_jaw_x := shark_a._jaw_node.rotation.x
	check(circle_mid_span > 0.25,
		"shark _tail_mid_node undulates during CIRCLE (span=%.3f)" % circle_mid_span)
	check(circle_fin_span > 0.45,
		"shark _tail_node undulates during CIRCLE (span=%.3f)" % circle_fin_span)
	check(absf(circle_jaw_x) < 0.12,
		"shark lower jaw stays nearly closed during CIRCLE (rot_x=%.3f)" % circle_jaw_x)

	# Switch into State.CHARGE and verify faster/wider S-wave tail undulation + wide open toothed jaw!
	shark_a.state = Shark.State.CHARGE
	shark_a._state_timer = 10.0
	var charge_mid_min := INF
	var charge_mid_max := -INF
	var charge_fin_min := INF
	var charge_fin_max := -INF
	var charge_jaw_min := INF
	var max_phase_diff := 0.0
	for _i in 42:
		await physics_frames(1)
		var mid_y := shark_a._tail_mid_node.rotation.y
		var fin_y := shark_a._tail_node.rotation.y
		charge_mid_min = minf(charge_mid_min, mid_y)
		charge_mid_max = maxf(charge_mid_max, mid_y)
		charge_fin_min = minf(charge_fin_min, fin_y)
		charge_fin_max = maxf(charge_fin_max, fin_y)
		charge_jaw_min = minf(charge_jaw_min, shark_a._jaw_node.rotation.x)
		max_phase_diff = maxf(max_phase_diff, absf(fin_y - mid_y))

	var charge_mid_span := charge_mid_max - charge_mid_min
	var charge_fin_span := charge_fin_max - charge_fin_min
	check(charge_mid_span > circle_mid_span + 0.15,
		"shark _tail_mid_node beats wider during CHARGE (%.3f > %.3f)" % [charge_mid_span, circle_mid_span])
	check(charge_fin_span > circle_fin_span + 0.25,
		"shark _tail_node beats wider during CHARGE (%.3f > %.3f)" % [charge_fin_span, circle_fin_span])
	check(max_phase_diff > 0.30,
		"shark 2-segment tail exhibits traveling S-wave phase lag (max_diff=%.3f)" % max_phase_diff)
	check(charge_jaw_min < -0.38 and absf(charge_jaw_min - Shark.JAW_OPEN_ANGLE) < 0.08,
		"shark _jaw_node snaps wide open (~-0.46 rad) during CHARGE (min_x=%.3f)" % charge_jaw_min)

	# Switch to RETREAT and confirm jaw smoothly closes again.
	shark_a.state = Shark.State.RETREAT
	shark_a._state_timer = 10.0
	await physics_frames(36)
	check(absf(shark_a._jaw_node.rotation.x - Shark.JAW_CLOSED_ANGLE) < 0.08,
		"shark _jaw_node closes smoothly during RETREAT (rot_x=%.3f)" % shark_a._jaw_node.rotation.x)

	await _end()
	check(Shark._mesh_cache.is_empty(),
		"Shark releases static mesh cache cleanly when last active shark exits tree")


func test_dolphin_pod_sculpted_meshes_leaps_and_teardown() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Sea.time = 0.0

	var pod := DolphinPod.spawn_alongside(_root, null, 3, 18.0)
	check(pod != null, "DolphinPod.spawn_alongside spawns pod cleanly without ship")
	check(pod.is_in_group(&"dolphins") and pod.is_in_group(&"beasts"),
		"DolphinPod registers in dolphins and beasts groups")

	var dolphins := pod.get_dolphin_nodes()
	check_eq(dolphins.size(), 3, "DolphinPod spawns 3 sculpted dolphins")

	# 1. Verify zero raw primitives, finite unit normals, sRGB materials, and static ArrayMesh sharing.
	var raw_prims := 0
	var bad_normals := 0
	var body_tris := 0
	var tail_tris := 0
	var first_body_mesh: ArrayMesh = null
	var first_tail_mesh: ArrayMesh = null

	for d in dolphins:
		var bmi := d.get_node_or_null(^"BodyMesh") as MeshInstance3D
		var tp := d.get_node_or_null(^"TailPivot") as Node3D
		var tmi := tp.get_node_or_null(^"TailFlukeMesh") as MeshInstance3D if tp != null else null
		check(bmi != null and bmi.mesh is ArrayMesh, "dolphin '%s' has sculpted BodyMesh" % d.name)
		check(tp != null and tmi != null and tmi.mesh is ArrayMesh, "dolphin '%s' has articulated TailPivot + TailFlukeMesh" % d.name)

		for mi: MeshInstance3D in [bmi, tmi]:
			if mi == null:
				continue
			if mi.mesh is PrimitiveMesh:
				raw_prims += 1
			var am := mi.mesh as ArrayMesh
			var mesh_tris := 0
			for si in am.get_surface_count():
				var arr := am.surface_get_arrays(si)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				mesh_tris += floori(float(verts.size()) / 3.0)
				for nv in norms:
					if not nv.is_finite() or nv.length_squared() < 0.5:
						bad_normals += 1
			if mi == bmi:
				body_tris = mesh_tris
				if first_body_mesh == null:
					first_body_mesh = am
				else:
					check_eq(am, first_body_mesh, "pod shares static BodyMesh ArrayMesh")
				var smat := bmi.get_surface_override_material(0) as StandardMaterial3D
				check(smat != null and smat.vertex_color_is_srgb, "BodyMesh uses sRGB vertex-colored material")
			else:
				tail_tris = mesh_tris
				if first_tail_mesh == null:
					first_tail_mesh = am
				else:
					check_eq(am, first_tail_mesh, "pod shares static TailFlukeMesh ArrayMesh")

	print("    dolphin sculpted meshes: BodyMesh=%d, TailFlukeMesh=%d (total=%d tris/dolphin)" % [
		body_tris, tail_tris, body_tris + tail_tris])
	check_eq(raw_prims, 0, "DolphinPod contains zero raw primitive meshes")
	check_eq(bad_normals, 0, "all sculpted dolphin mesh normals are finite unit vectors")
	check(body_tris >= 550 and body_tris <= 900, "BodyMesh triangle count within target sculpted budget (%d)" % body_tris)
	check(tail_tris >= 130 and tail_tris <= 240, "TailFlukeMesh triangle count within target sculpted budget (%d)" % tail_tris)

	# 2. Verify vertical mammalian tail-fluke oscillation (rotation.x beats, rotation.y stays 0) & wave leaps!
	var d0 := dolphins[0]
	var tp0 := d0.get_node(^"TailPivot") as Node3D
	var tail_x_min := INF
	var tail_x_max := -INF
	var max_leap_y := -INF
	var min_sub_y := INF
	for _i in 120:
		await physics_frames(1)
		tail_x_min = minf(tail_x_min, tp0.rotation.x)
		tail_x_max = maxf(tail_x_max, tp0.rotation.x)
		var sea_y := Sea.height(d0.global_position.x, d0.global_position.z)
		var rel_y := d0.global_position.y - sea_y
		max_leap_y = maxf(max_leap_y, rel_y)
		min_sub_y = minf(min_sub_y, rel_y)
		check_near(tp0.rotation.y, 0.0, 0.001, "dolphin tail flukes beat vertically (rotation.y == 0)")

	var tail_x_span := tail_x_max - tail_x_min
	check(tail_x_span > 0.45, "dolphin horizontal tail flukes oscillate vertically (span=%.3f rad)" % tail_x_span)
	check(max_leap_y > 1.75, "dolphin leaps high above Sea.height() during wave arc (peak=%.2f m)" % max_leap_y)
	check(min_sub_y < -0.35, "dolphin dives cleanly beneath waves between leaps (min=%.2f m)" % min_sub_y)

	# 3. Verify force_leap_phase() deterministically frames breach pitch-up, mid-air apex, and nose-first dive!
	pod.force_leap_phase(PI * 0.5)
	var apex_sea := Sea.height(d0.global_position.x, d0.global_position.z)
	check(d0.global_position.y - apex_sea >= 1.95,
		"force_leap_phase(PI * 0.5) places leader dolphin high at leap apex (%.2f m)" % (d0.global_position.y - apex_sea))
	check(absf(d0.rotation.x) < 0.12, "dolphin levels smoothly at leap apex (pitch=%.3f)" % d0.rotation.x)

	pod.force_leap_phase(PI * 0.16)
	check(d0.rotation.x > 0.20, "dolphin pitches nose-up on upward breach (pitch=%.3f)" % d0.rotation.x)

	pod.force_leap_phase(PI * 0.84)
	check(d0.rotation.x < -0.20, "dolphin pitches nose-down on dive re-entry (pitch=%.3f)" % d0.rotation.x)

	# 4. Verify Brigantine hull-size-aware bow-wave clearance (>= 5.5 m beam clearance, forward beside bow)
	#    and force_leap_phase(1.25) putting 2 dolphins cleanly airborne near 1.8-2.3 m peak crest!
	var mock_brig := MockBrigantine.new()
	_root.add_child(mock_brig)
	mock_brig.global_position = Vector3(40.0, 0.0, -20.0)
	var brig_pod := DolphinPod.spawn_alongside(_root, mock_brig, 3, 18.0)
	brig_pod.force_leap_phase(1.25)
	var peak_count := 0
	for bd in brig_pod.get_dolphin_nodes():
		var beam_clear := absf(bd.global_position.x - mock_brig.global_position.x)
		var bow_ahead := mock_brig.global_position.z - bd.global_position.z
		var rel_h := bd.global_position.y - Sea.height(bd.global_position.x, bd.global_position.z)
		check(beam_clear >= 5.5, "Brigantine dolphin '%s' clears hull centerline >= 5.5 m (got %.2f m)" % [bd.name, beam_clear])
		check(bow_ahead >= 5.0, "Brigantine dolphin '%s' rides forward beside bow wave (ahead=%.2f m)" % [bd.name, bow_ahead])
		if rel_h >= 1.80 and rel_h <= 2.35:
			peak_count += 1
	check(peak_count >= 2, "force_leap_phase(1.25) places >= 2 dolphins near 1.8-2.3 m peak crest (got %d)" % peak_count)
	brig_pod.queue_free()
	mock_brig.queue_free()
	await physics_frames(2)

	# 5. Verify lifetime expiry auto-frees cleanly and releases all static caches with ZERO leaks!
	pod.age = pod.lifetime - 0.05
	await physics_frames(8)
	check(not is_instance_valid(pod), "DolphinPod cleanly queue_free()s after lifetime expires")
	check(DolphinPod._body_mesh == null and DolphinPod._tail_mesh == null and DolphinPod._skin_mat == null,
		"DolphinPod releases static mesh & material caches cleanly when last pod exits tree")

	await _end()


func test_flotsam_cluster_sculpted_debris_and_salvage() -> void:
	_begin()
	var flotsam_gd: GDScript = preload("res://src/world/flotsam_cluster.gd")
	Sea.amp_scale = Sea.AMP_STORM
	Sea.time = 1.2

	var c1: Node3D = flotsam_gd.call(&"spawn_at", _root, Vector3(16.0, 0.0, -24.0), 42) as Node3D
	var c2: Node3D = flotsam_gd.call(&"spawn_at", _root, Vector3(-18.0, 0.0, -28.0), 99) as Node3D
	check(c1 != null and c2 != null, "FlotsamCluster.spawn_at creates buoyant clusters")
	check(c1.is_in_group(&"flotsam"), "FlotsamCluster registers in group 'flotsam'")

	# 1. Verify sculpted zero-primitive ShipwreckDebrisMesh, static mesh sharing, sRGB mats, and finite normals.
	var dmi1 := c1.get_node_or_null(^"ShipwreckDebrisMesh") as MeshInstance3D
	var dmi2 := c2.get_node_or_null(^"ShipwreckDebrisMesh") as MeshInstance3D
	check(dmi1 != null and dmi1.mesh is ArrayMesh, "FlotsamCluster builds sculpted ShipwreckDebrisMesh ArrayMesh")
	check(dmi2 != null and dmi1.mesh == dmi2.mesh, "FlotsamClusters share statically cached debris ArrayMesh")

	var raw_prims := 0
	var bad_normals := 0
	var debris_tris := 0
	var col_meshes: Array[String] = []
	for n in c1.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null:
			continue
		if mi.name.begins_with("col_"):
			col_meshes.append(mi.name)
		if mi.mesh == null:
			continue
		if mi.mesh is PrimitiveMesh:
			raw_prims += 1
	check(col_meshes.is_empty(), "FlotsamCluster strips all col_* collision helper meshes (found: %s)" % str(col_meshes))
	if dmi1 != null and dmi1.mesh is ArrayMesh:
		var am := dmi1.mesh as ArrayMesh
		check(am.get_surface_count() >= 2, "ShipwreckDebrisMesh has timber/hemp + painted float/iron surfaces")
		for si in am.get_surface_count():
			var arr := am.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			debris_tris += floori(float(verts.size()) / 3.0)
			for nv in norms:
				if not nv.is_finite() or nv.length_squared() < 0.5:
					bad_normals += 1
		var wmat := dmi1.get_surface_override_material(0) as StandardMaterial3D
		check(wmat != null and wmat.vertex_color_is_srgb, "ShipwreckDebrisMesh uses sRGB vertex-colored material")

	var fb_barrel := flotsam_gd.get(&"_fallback_barrel_mesh") as ArrayMesh
	var fb_tris := 0
	if fb_barrel != null:
		for si in fb_barrel.get_surface_count():
			fb_tris += floori(float((fb_barrel.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3.0)
	print("    flotsam sculpted meshes: ShipwreckDebrisMesh=%d tris, fallback_barrel=%d tris" % [debris_tris, fb_tris])
	check_eq(raw_prims, 0, "FlotsamCluster contains zero raw PrimitiveMeshes")
	check_eq(bad_normals, 0, "all ShipwreckDebrisMesh normals are finite unit vectors")
	check(debris_tris >= 1200, "ShipwreckDebrisMesh has detailed planks/spar/netting/floats (%d tris)" % debris_tris)

	# 2. Verify realistic Sea.height() wave bobbing and slope pitch/roll response.
	for _i in 20:
		Sea.time += 0.12
		c1.call(&"step_buoyancy", 0.12)
	var expected_y := Sea.height(16.0, -24.0)
	check(c1.global_position.y > expected_y and absf(c1.global_position.y - expected_y) < 0.35,
		"FlotsamCluster rides cleanly dry-top on live Sea.height() (y=%.2f vs sea=%.2f)" % [c1.global_position.y, expected_y])
	check(absf(c1.rotation.x) + absf(c1.rotation.z) > 0.01, "FlotsamCluster pitches/rolls naturally with wave chop")

	# 3. Verify host-authoritative idempotent salvage via Interactable.
	var it := c1.get(&"interactable") as Interactable
	check(it != null and it.enabled and it.prompt == "Salvage flotsam supplies", "FlotsamCluster exposes Salvage Interactable")
	var barrel := c1.get_node_or_null(^"CargoBarrel") as Node3D
	check(barrel != null and barrel.visible, "CargoBarrel starts visible before salvage")

	var salvaged_events: Array[Dictionary] = []
	c1.connect(&"flotsam_salvaged", func(_cl: Node, _p: Node, loot: Dictionary) -> void:
		salvaged_events.append(loot)
	)
	it.interact(null)
	check_eq(salvaged_events.size(), 1, "flotsam_salvaged emits once on interact")
	check(bool(c1.get(&"salvaged")), "FlotsamCluster marks salvaged = true")
	check(not it.enabled, "salvaged FlotsamCluster disables Interactable")
	check(not barrel.visible, "salvaged FlotsamCluster hides CargoBarrel")
	if salvaged_events.size() == 1:
		check_eq(int(salvaged_events[0].get("cannonballs", 0)), 6, "salvage awards 6 cannonballs")
		check_eq(int(salvaged_events[0].get("planks", 0)), 4, "salvage awards 4 planks")
		check_eq(int(salvaged_events[0].get("gold", 0)), 35, "salvage awards 35 gold")

	# Repeat salvage must be strictly idempotent.
	var repeat_loot: Dictionary = c1.call(&"salvage", null) as Dictionary
	check(repeat_loot.is_empty() and salvaged_events.size() == 1, "repeat salvage() is strictly idempotent")

	# 4. Zero-leak teardown releases all static caches cleanly when last FlotsamCluster exits tree!
	await _end()
	check(not is_instance_valid(c1) and not is_instance_valid(c2), "FlotsamClusters freed cleanly")
	check(flotsam_gd.get(&"_debris_mesh") == null and flotsam_gd.get(&"_wood_mat") == null and flotsam_gd.get(&"_accent_mat") == null,
		"FlotsamCluster releases static mesh & material caches cleanly with zero leaks")


func test_reef_fish_school_single_dc_orbit_scatter_and_teardown() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Sea.time = 0.0

	# 1. Populate a Crescent Lagoon island with CoralReef + ReefFishSchool and verify island placement.
	var isl := IslandGenerator.build_island({
		"id": "test_crescent_fish",
		"name": "Test Crescent Fish",
		"archetype": &"crescent_lagoon",
		"radius": 62.0,
		"peak_height": 34.0,
		"landing_yaw": 0.72,
		"seed": 8803,
	})
	_root.add_child(isl)
	CoralReef.populate_for_island(isl, 8880, 1.15)
	var school := ReefFishSchool.populate_for_island(isl, 8934)
	check(school != null, "ReefFishSchool.populate_for_island spawns school on crescent_lagoon")
	check(school.is_in_group(ReefFishSchool.GROUP), "ReefFishSchool registers in reef_fish group")

	# Spawn a second school to confirm static ArrayMesh & material sharing.
	var school2 := ReefFishSchool.new()
	school2.position = Vector3(20.0, -2.8, 0.0)
	school2.fish_count = 22
	_root.add_child(school2)
	await physics_frames(1)

	# 2. Verify strictly 1 visible MultiMeshInstance3D draw call while cruising (ScatterBubbleBurst stays hidden),
	#    zero raw primitives, sRGB material & distance cull.
	var mmis := school.find_children("*", "MultiMeshInstance3D", true, false)
	var mis := school.find_children("*", "MeshInstance3D", true, false)
	var visible_mmis := 0
	for n in mmis:
		if (n as MultiMeshInstance3D).visible:
			visible_mmis += 1
	check_eq(visible_mmis, 1, "ReefFishSchool renders in strictly 1 visible MultiMeshInstance3D draw call while cruising")
	check_eq(mmis.size(), 2, "ReefFishSchool owns FishSchoolMultiMesh plus preallocated hidden ScatterBubbleBurst")
	check_eq(mis.size(), 0, "ReefFishSchool adds zero extra MeshInstance3D draw calls")

	var mmi := school.get_multimesh_instance()
	var mmi2 := school2.get_multimesh_instance()
	check(mmi != null and mmi.name == "FishSchoolMultiMesh", "MultiMeshInstance3D named FishSchoolMultiMesh")
	check_eq(mmi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "ReefFishSchool disables shadows")
	check(mmi.visibility_range_end > 0.0 and mmi.visibility_range_end <= 80.0,
		"ReefFishSchool visibility_range_end <= 80 m (got %.1f)" % mmi.visibility_range_end)
	check_eq(mmi.visibility_range_fade_mode, GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF,
		"ReefFishSchool uses self fade mode")

	var mm := mmi.multimesh
	check(mm != null and mm.use_colors, "MultiMesh enables per-instance tropical species colors")
	check(mm.instance_count >= 20 and mm.instance_count <= 26,
		"ReefFishSchool spawns 20..26 tropical fish (got %d)" % mm.instance_count)
	check(mm.mesh is ArrayMesh and not (mm.mesh is PrimitiveMesh),
		"ReefFishSchool uses sculpted ArrayMesh (zero PrimitiveMesh)")
	check_eq(mm.mesh, mmi2.multimesh.mesh, "ReefFishSchools share statically cached fish ArrayMesh")

	var mat := mmi.material_override as StandardMaterial3D
	check(mat != null and mat.vertex_color_use_as_albedo and mat.vertex_color_is_srgb,
		"ReefFishSchool uses sRGB vertex-colored material")

	var arr := (mm.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var fish_tris := floori(float(verts.size()) / 3.0)
	var bad_norms := 0
	for nv in norms:
		if not nv.is_finite() or nv.length_squared() < 0.5:
			bad_norms += 1
	check_eq(bad_norms, 0, "all sculpted reef fish normals are finite unit vectors")
	check(fish_tris >= 100, "sculpted tropical reef fish has body, fins & tail (%d tris)" % fish_tris)
	print("    ReefFishSchool: 1 DC, %d fish, %d tris/fish, center=%s" % [mm.instance_count, fish_tris, str(school.position)])

	# 3. Verify all fish stay strictly submerged (y <= -0.95 m) and advance smoothly along swim loop.
	var pos0 := school.get_fish_world_positions()
	for p in pos0:
		check(p.y <= -0.95, "initial reef fish strictly submerged (y=%.2f <= -0.95)" % p.y)

	for _step in 4:
		school.step_school(0.25)
	var pos1 := school.get_fish_world_positions()
	var moved_sum := 0.0
	for i in pos1.size():
		check(pos1[i].y <= -0.95, "swimming reef fish strictly submerged (y=%.2f <= -0.95)" % pos1[i].y)
		moved_sum += pos1[i].distance_to(pos0[i])
	var avg_move := moved_sum / float(maxi(1, pos1.size()))
	check(avg_move > 0.35, "reef fish advance smoothly along curving reef loops (avg_move=%.2f m)" % avg_move)

	# 4. Verify playful scatter away from a nearby swimming threat within 4.5 m while staying submerged!
	var threat := pos1[0] + Vector3(0.2, 0.0, 0.2)
	var dist_before := pos1[0].distance_to(threat)
	for _s in 6:
		school.step_school(0.15, threat)
	var pos_after := school.get_fish_world_positions()
	var dist_after := pos_after[0].distance_to(threat)
	check(dist_after > dist_before + 1.4,
		"fish scatters briskly away from nearby swimmer (%.2f -> %.2f m)" % [dist_before, dist_after])
	for p in pos_after:
		check(p.y <= -0.95, "scattering fish never pokes above sea surface (y=%.2f <= -0.95)" % p.y)

	# 5. Zero-leak teardown releases all static caches cleanly when last school exits tree!
	await _end()
	check_eq(ReefFishSchool._active_schools, 0, "all ReefFishSchools exited cleanly")
	check(ReefFishSchool._fish_mesh == null and ReefFishSchool._fish_mat == null,
		"ReefFishSchool releases static fish mesh & material caches cleanly to null")


func test_manta_ray_sculpted_wing_glide_submerged_and_teardown() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Sea.time = 0.0

	# 1. Populate a Crescent Lagoon island with CoralReef + MantaRay, plus a second MantaRay to verify sharing.
	var isl := IslandGenerator.build_island({
		"id": "test_crescent_manta",
		"name": "Test Crescent Manta",
		"archetype": &"crescent_lagoon",
		"radius": 62.0,
		"peak_height": 34.0,
		"landing_yaw": 0.72,
		"seed": 8803,
	})
	_root.add_child(isl)
	CoralReef.populate_for_island(isl, 8880, 1.15)
	var manta := MantaRay.populate_for_island(isl, 9014)
	check(manta != null, "MantaRay.populate_for_island spawns MantaRay on crescent_lagoon")
	check(manta.is_in_group(MantaRay.GROUP) and manta.is_in_group(MantaRay.GROUP_BEASTS),
		"MantaRay registers in manta_rays and beasts groups")

	var manta2 := MantaRay.new()
	manta2.position = Vector3(30.0, -3.2, 0.0)
	_root.add_child(manta2)
	await physics_frames(1)

	# 2. Verify sculpted ArrayMeshes (zero PrimitiveMeshes), sRGB material, distance culling, & static sharing.
	var mis := manta.get_mesh_instances()
	var mis2 := manta2.get_mesh_instances()
	check_eq(mis.size(), 3, "MantaRay builds 3 sculpted MeshInstance3Ds (BodyMesh + Left/Right wings)")

	var raw_prims := 0
	var bad_normals := 0
	var total_tris := 0
	var part_tris: Array[int] = []
	for idx in mis.size():
		var mi := mis[idx]
		var mi2 := mis2[idx]
		check(mi.mesh is ArrayMesh and not (mi.mesh is PrimitiveMesh),
			"MantaRay '%s' uses sculpted ArrayMesh (zero PrimitiveMesh)" % mi.name)
		if mi.mesh is PrimitiveMesh:
			raw_prims += 1
		check_eq(mi.mesh, mi2.mesh, "MantaRays share statically cached '%s' ArrayMesh" % mi.name)
		check_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"MantaRay '%s' disables shadows" % mi.name)
		check(mi.visibility_range_end > 0.0 and mi.visibility_range_end <= 90.0,
			"MantaRay '%s' visibility_range_end <= 90 m (got %.1f)" % [mi.name, mi.visibility_range_end])
		var mat := mi.material_override as StandardMaterial3D
		check(mat != null and mat.vertex_color_use_as_albedo and mat.vertex_color_is_srgb,
			"MantaRay '%s' uses sRGB vertex-colored PBR material" % mi.name)
		var arr := (mi.mesh as ArrayMesh).surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var tris := floori(float(verts.size()) / 3.0)
		part_tris.append(tris)
		total_tris += tris
		for nv in norms:
			if not nv.is_finite() or nv.length_squared() < 0.5:
				bad_normals += 1

	print("    MantaRay sculpted meshes: Body=%d, LeftWing=%d, RightWing=%d (total=%d tris)" % [
		part_tris[0], part_tris[1], part_tris[2], total_tris])
	check_eq(raw_prims, 0, "MantaRay contains zero raw PrimitiveMeshes")
	check_eq(bad_normals, 0, "all MantaRay mesh normals are finite unit vectors")
	check(total_tris >= 420 and total_tris <= 720,
		"MantaRay sculpted triangle count within target budget (%d tris)" % total_tris)

	# 3. Verify graceful wing-flap oscillation, curving lagoon glide travel, and strict submersion (y <= -1.2 m).
	var pivots := manta.get_wing_pivots()
	check_eq(pivots.size(), 2, "MantaRay exposes LeftWingPivot & RightWingPivot")
	var lp := pivots[0]
	var rp := pivots[1]

	var min_z := INF
	var max_z := -INF
	var prev_pos := manta.get_glide_world_position()
	var total_travel := 0.0
	for _step in 26:
		manta.step_glide(0.15)
		var cur_pos := manta.get_glide_world_position()
		check(cur_pos.y <= -1.2, "gliding MantaRay stays strictly submerged (y=%.2f <= -1.2)" % cur_pos.y)
		total_travel += cur_pos.distance_to(prev_pos)
		prev_pos = cur_pos
		min_z = minf(min_z, rp.rotation.z)
		max_z = maxf(max_z, rp.rotation.z)
		check_near(lp.rotation.z, -rp.rotation.z, 0.001, "left and right wings flap symmetrically")

	var flap_span := max_z - min_z
	check(flap_span > 0.55, "MantaRay pectoral wings oscillate gracefully (span=%.3f rad)" % flap_span)
	check(total_travel > 5.0, "MantaRay glides smoothly along its lagoon path (travel=%.2f m)" % total_travel)

	# 4. Zero-leak teardown releases all static caches cleanly to null when last MantaRay exits tree!
	await _end()
	check_eq(MantaRay._active_mantas, 0, "all MantaRays exited cleanly")
	check(MantaRay._body_mesh == null and MantaRay._wing_left_mesh == null \
			and MantaRay._wing_right_mesh == null and MantaRay._manta_mat == null,
		"MantaRay releases all static mesh & material caches cleanly to null")


func test_ocean_whale_sculpted_breach_cycle_and_teardown() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Sea.time = 0.0

	var whale_a := OceanWhale.spawn_breach(_root, Vector3(0.0, 0.0, -40.0), 0.2)
	whale_a.auto_despawn = false
	var whale_b := OceanWhale.spawn_breach(_root, Vector3(36.0, 0.0, -45.0), -0.3)
	whale_b.auto_despawn = false

	check(whale_a != null and whale_b != null, "OceanWhale.spawn_breach spawns whales cleanly")
	check(whale_a.is_in_group(&"whales") and whale_a.is_in_group(&"beasts"),
		"OceanWhale registers in whales and beasts groups")

	# 1. Verify zero raw primitives, finite unit normals, sRGB clearcoat skin & static mesh sharing across 2 whales!
	var raw_prims := 0
	var bad_normals := 0
	var total_tris := 0
	var srgb_missing := 0
	var part_names: Array[String] = ["BodyMesh", "LeftFlipperMesh", "RightFlipperMesh", "TailFlukeMesh"]
	var part_summary: PackedStringArray = []

	for part_nm in part_names:
		var mi_a := whale_a.find_child(part_nm, true, false) as MeshInstance3D
		var mi_b := whale_b.find_child(part_nm, true, false) as MeshInstance3D
		check(mi_a != null and mi_b != null, "both whales build sculpted %s" % part_nm)
		if mi_a == null:
			continue
		if mi_a.mesh is PrimitiveMesh:
			raw_prims += 1
		if mi_b != null:
			check_eq(mi_a.mesh, mi_b.mesh, "whales share static cached ArrayMesh for %s" % part_nm)
		check_eq(mi_a.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
			"%s casts dramatic sunlit shadow on sea" % part_nm)
		check_near(mi_a.visibility_range_end, 420.0, 0.1, "%s sets visibility_range_end = 420 m" % part_nm)
		var mat := mi_a.material_override as StandardMaterial3D
		if mat == null or not mat.vertex_color_is_srgb:
			srgb_missing += 1
		var am := mi_a.mesh as ArrayMesh
		if am != null:
			var p_tris := 0
			for si in am.get_surface_count():
				var arr := am.surface_get_arrays(si)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				p_tris += floori(float(verts.size()) / 3.0)
				for nv in norms:
					if not nv.is_finite() or nv.length_squared() < 0.5:
						bad_normals += 1
			total_tris += p_tris
			part_summary.append("%s=%d" % [part_nm, p_tris])

	print("    OceanWhale sculpted meshes: %s (total=%d tris)" % [", ".join(part_summary), total_tris])
	check_eq(raw_prims, 0, "OceanWhale contains zero raw PrimitiveMeshes")
	check_eq(bad_normals, 0, "all sculpted OceanWhale normals are finite unit vectors")
	check_eq(srgb_missing, 0, "OceanWhale material enables vertex_color_is_srgb = true")
	check(total_tris >= 900 and total_tris <= 1600,
		"OceanWhale total sculpted triangles within target budget (%d tris)" % total_tris)

	# 2. Step deterministically through full 6-phase breach cycle: APPROACH -> BREACH_RISE -> APEX_TWIST -> SPLASH_REENTRY -> SUBMERGE -> DONE!
	var seen_phases: Dictionary = {}
	var splash_positions: Array[Vector3] = []
	whale_a.whale_splashed.connect(func(wp: Vector3) -> void: splash_positions.append(wp))

	var peak_rel_y := -INF
	var max_abs_roll := 0.0
	seen_phases[whale_a.phase] = true
	for _i in 45:
		whale_a.step_breach(0.20)
		seen_phases[whale_a.phase] = true
		var sea_y := Sea.height(whale_a.global_position.x, whale_a.global_position.z)
		peak_rel_y = maxf(peak_rel_y, whale_a.global_position.y - sea_y)
		if whale_a.phase == OceanWhale.Phase.APEX_TWIST and whale_a.body_root != null:
			max_abs_roll = maxf(max_abs_roll, absf(whale_a.body_root.rotation.z))

	for req_phase: OceanWhale.Phase in [
		OceanWhale.Phase.APPROACH,
		OceanWhale.Phase.BREACH_RISE,
		OceanWhale.Phase.APEX_TWIST,
		OceanWhale.Phase.SPLASH_REENTRY,
		OceanWhale.Phase.SUBMERGE,
		OceanWhale.Phase.DONE,
	]:
		check(seen_phases.has(req_phase), "OceanWhale steps cleanly through phase %d" % int(req_phase))
	check(peak_rel_y > 4.5, "OceanWhale crests high above Sea.height() during breach (peak=%.2f m)" % peak_rel_y)
	check(max_abs_roll > 0.70, "OceanWhale executes twisting roll through APEX_TWIST (max_roll=%.2f rad)" % max_abs_roll)
	check_eq(splash_positions.size(), 1, "OceanWhale emits whale_splashed exactly once on splash re-entry")

	# 3. Verify force_breach_apex() positions whale majestically airborne for showcase captures!
	whale_b.force_breach_apex()
	var apex_sea := Sea.height(whale_b.global_position.x, whale_b.global_position.z)
	check_eq(whale_b.phase, OceanWhale.Phase.APEX_TWIST, "force_breach_apex sets Phase.APEX_TWIST")
	check(whale_b.global_position.y - apex_sea >= 5.0,
		"force_breach_apex places whale soaring >= 5.0 m above Sea.height() (got %.2f m)" % (whale_b.global_position.y - apex_sea))

	# 4. Zero-leak teardown releases ALL static caches cleanly to null when last OceanWhale exits tree!
	await _end()
	check_eq(OceanWhale._active_whales, 0, "all OceanWhales exited cleanly")
	check(OceanWhale._body_mesh == null and OceanWhale._flipper_l_mesh == null \
			and OceanWhale._flipper_r_mesh == null and OceanWhale._fluke_mesh == null \
			and OceanWhale._whale_mat == null and OceanWhale._spray_tex == null,
		"OceanWhale releases all static mesh, material & spray caches cleanly to null")


func test_wave34_sunken_shipwreck_sculpted_hull_dive_loot_spyglass_director_and_crew() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Sea.time = 0.0

	# 1. Spawn two SunkenShipwrecks and verify sculpted ArrayMesh, zero primitives, PBR materials,
	#    dramatic 32-deg roll / -18-deg pitch hull list, layer-1 collider, & level SeabirdFlock!
	var wreck_a := SunkenShipwreck.spawn_at(_root, Vector3(180.0, 0.0, -180.0), 3401)
	var wreck_far := SunkenShipwreck.spawn_at(_root, Vector3(0.0, 0.0, -650.0), 3402)
	await physics_frames(1)

	check(wreck_a != null and wreck_far != null, "SunkenShipwreck.spawn_at spawns wrecks cleanly")
	check(wreck_a.is_in_group(SunkenShipwreck.GROUP), "SunkenShipwreck registers in sunken_shipwrecks group")

	var pivot_a := wreck_a.get_hull_pivot()
	check(pivot_a != null, "SunkenShipwreck creates _hull_pivot child")
	if pivot_a != null:
		check_near(rad_to_deg(pivot_a.rotation.z), 32.0, 0.05,
			"SunkenShipwreck lists dramatically at 32 deg roll (got %.2f)" % rad_to_deg(pivot_a.rotation.z))
		check_near(rad_to_deg(pivot_a.rotation.x), -18.0, 0.05,
			"SunkenShipwreck pitches at -18 deg stern-up (got %.2f)" % rad_to_deg(pivot_a.rotation.x))

	var mi_a := wreck_a.get_hull_mesh_instance()
	var mi_b := wreck_far.get_hull_mesh_instance()
	check(mi_a != null and mi_b != null, "both wrecks mount SunkenHullMesh MeshInstance3D")
	check(mi_a.mesh is ArrayMesh and not (mi_a.mesh is PrimitiveMesh),
		"SunkenShipwreck hull uses sculpted ArrayMesh (zero PrimitiveMesh)")
	check_eq(mi_a.mesh, mi_b.mesh, "SunkenShipwrecks share statically cached hull ArrayMesh")

	var raw_prims := 0
	for mi_node in wreck_a.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_node as MeshInstance3D
		if mi != null and mi.mesh is PrimitiveMesh:
			raw_prims += 1
	check_eq(raw_prims, 0, "SunkenShipwreck hierarchy contains zero raw PrimitiveMeshes")

	var hull_am := mi_a.mesh as ArrayMesh
	var total_tris := 0
	var bad_normals := 0
	var surf_report: PackedStringArray = []
	for si in hull_am.get_surface_count():
		var arr := hull_am.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var s_tris := floori(float(verts.size()) / 3.0)
		total_tris += s_tris
		surf_report.append("s%d=%d" % [si, s_tris])
		for nv in norms:
			if not nv.is_finite() or nv.length_squared() < 0.5:
				bad_normals += 1
		var smat := mi_a.get_surface_override_material(si) as StandardMaterial3D
		check(smat != null, "surface %d binds StandardMaterial3D override" % si)
		if smat != null:
			check(smat.vertex_color_use_as_albedo and smat.vertex_color_is_srgb,
				"surface %d enables sRGB vertex_color_use_as_albedo" % si)
			check(smat.uv1_triplanar and not smat.uv1_world_triplanar,
				"surface %d uses object-space triplanar (uv1_world_triplanar == false)" % si)
			if si == 0:
				check(smat.normal_enabled and smat.normal_texture != null,
					"hull surface 0 binds WeakRef-cached BC7 ship normal texture")

	print("    SunkenShipwreck sculpted hull: %s (total=%d tris)" % [", ".join(surf_report), total_tris])
	check_eq(bad_normals, 0, "all sculpted SunkenShipwreck hull normals are finite unit vectors")
	check(total_tris >= 1400, "SunkenShipwreck sculpted hull >= 1,400 tris (got %d)" % total_tris)
	check_eq(wreck_a.get_triangle_count(), total_tris, "get_triangle_count() matches ArrayMesh surface count")

	# Verify simplified outer hull collider exists on layer 1.
	var col_body := pivot_a.get_node_or_null(^"HullCollider") as StaticBody3D if pivot_a != null else null
	check(col_body != null and col_body.collision_layer == 1,
		"SunkenShipwreck mounts simplified StaticBody3D outer hull collider on layer 1")

	# Verify circling SeabirdFlock loot marker overhead attached to upright root (NOT _hull_pivot!).
	var flock := wreck_a.get_gull_flock()
	check(flock != null and is_instance_valid(flock), "SunkenShipwreck spawns overhead SeabirdFlock")
	if flock != null:
		check_eq(flock.get_parent(), wreck_a, "SeabirdFlock attaches to upright root (not tilted _hull_pivot)")
		check(flock.get_birds().size() >= 5,
			"overhead SeabirdFlock spawns >= 5 circling gulls (got %d)" % flock.get_birds().size())

	# Verify wave wallow stays gently damped (~0.05 rad) on the upright root.
	wreck_a.step_buoyancy(0.5)
	check(absf(wreck_a.rotation.x) <= 0.06 and absf(wreck_a.rotation.z) <= 0.06,
		"upright root wave wallow stays damped (~0.05 rad)")

	# 2. Verify 2..3 diveable underwater cabin treasures, idempotent spawn, turquoise glow,
	#    and pickup tracking (shipwreck_looted + shipwreck_cleared).
	var init_count := wreck_a.get_remaining_loot_count()
	check(init_count >= 2 and init_count <= 3,
		"SunkenShipwreck spawns 2..3 underwater cabin treasures (got %d)" % init_count)
	check(not wreck_a.is_cleared(), "fresh SunkenShipwreck is not cleared")

	var repeat_loot := wreck_a.spawn_cabin_loot()
	check_eq(repeat_loot.size(), init_count, "spawn_cabin_loot() is strictly idempotent")

	var sea_y_a := Sea.height(wreck_a.base_x, wreck_a.base_z)
	for item_node in wreck_a.loot_items:
		check(item_node is Carryable and is_instance_valid(item_node), "cabin loot item is a valid Carryable")
		var c := item_node as Carryable
		check(c.freeze, "anchored cabin treasure starts frozen underwater inside flooded cabin")
		check(c.global_position.y < sea_y_a - 2.2,
			"cabin treasure sits submerged below Sea.height (y=%.2f vs sea=%.2f)" % [c.global_position.y, sea_y_a])

	var guide_light := wreck_a.get_cabin_light()
	check(guide_light != null and not guide_light.shadow_enabled and is_equal_approx(guide_light.omni_range, 9.0),
		"underwater cabin mounts shadowless 9.0 m turquoise OmniLight3D guide glow")
	check(guide_light.visible, "underwater cabin glow is visible before clearing")

	var looted_events: Array[Node] = []
	var cleared_events: Array[SunkenShipwreck] = []
	wreck_a.shipwreck_looted.connect(func(_w: SunkenShipwreck, item: Node) -> void: looted_events.append(item))
	wreck_a.shipwreck_cleared.connect(func(w: SunkenShipwreck) -> void: cleared_events.append(w))

	# 3. Verify Brass Spyglass identifies distant uncleared wreck at 650 m as "Sunken Shipwreck"
	#    and ignores it once cleared!
	var captain := _spawn_pawn(Vector3(0.0, 4.0, 0.0), &"player")
	var inv := Inventory.new()
	inv.input_enabled = false
	captain.add_child(inv)
	await physics_frames(1)

	inv.equip(&"spyglass", true)
	inv.set_secondary_held(true)

	var aim_at := func(world_pt: Vector3) -> void:
		var delta := world_pt - captain.eye_position()
		var horiz := maxf(Vector2(delta.x, delta.z).length(), 0.001)
		captain.look_yaw = atan2(-delta.x, -delta.z)
		captain.look_pitch = atan2(delta.y, horiz)
		inv.call(&"_scan_spyglass_sighting")

	aim_at.call(wreck_far.global_position + Vector3.UP * 5.0)
	check_eq(inv.spyglass_sighting, "Sunken Shipwreck",
		"spyglass identifies uncleared wreck at 650 m as 'Sunken Shipwreck' (got '%s')" % inv.spyglass_sighting)
	check(inv.spyglass_sighting_dist >= 635.0 and inv.spyglass_sighting_dist <= 665.0,
		"spyglass reports accurate 650 m wreck sighting distance (got %.1f m)" % inv.spyglass_sighting_dist)

	# Salvage all treasures from wreck_a via Pawn.pick_up() and verify signals + cleared state!
	var diver := _spawn_pawn(wreck_a.global_position + Vector3(0.0, -2.8, 0.0), &"player")
	await physics_frames(1)
	var remaining_expected := init_count
	for item_node in wreck_a.loot_items.duplicate():
		var c := item_node as Carryable
		check(diver.pick_up(c), "diver picks up submerged treasure '%s'" % c.item_name)
		remaining_expected -= 1
		check_eq(wreck_a.get_remaining_loot_count(), remaining_expected,
			"get_remaining_loot_count() decrements to %d after pickup" % remaining_expected)
		diver.drop_carried(0.0)
	check_eq(looted_events.size(), init_count, "shipwreck_looted emitted once per cabin treasure")
	check_eq(cleared_events.size(), 1, "shipwreck_cleared emitted once when last treasure is salvaged")
	check(wreck_a.is_cleared(), "SunkenShipwreck.is_cleared() is true after all loot recovered")
	check(not guide_light.visible, "underwater cabin glow hides automatically once wreck is cleared")

	# Clear wreck_far as well and confirm spyglass ignores cleared wrecks!
	for item_node in wreck_far.loot_items.duplicate():
		var c := item_node as Carryable
		diver.pick_up(c)
		diver.drop_carried(0.0)
	check(wreck_far.is_cleared(), "wreck_far cleared after salvaging its cabin treasures")
	aim_at.call(wreck_far.global_position + Vector3.UP * 5.0)
	check_eq(inv.spyglass_sighting, "", "spyglass ignores cleared SunkenShipwrecks")
	inv.set_secondary_held(false)

	# 4. Verify WorldDirector.force_spawn_shipwreck() emits spawn_shipwreck + strict-ASCII warning!
	var director := WorldDirector.new(0x34A01)
	director.post_notices = false
	director.weather_integration = false
	director.player_ship_pos = Vector3(200.0, 0.0, -150.0)
	_root.add_child(director)

	var dir_spawns: Array[Dictionary] = []
	var dir_warnings: Array[Dictionary] = []
	director.spawn_shipwreck.connect(func(pos: Vector3, sval: int) -> void:
		dir_spawns.append({"pos": pos, "seed": sval})
	)
	director.sighting_warning.connect(func(msg: String, pos: Vector3, kind: StringName, brg: String, dist: float) -> void:
		dir_warnings.append({"msg": msg, "pos": pos, "kind": kind, "bearing": brg, "dist": dist})
	)

	var dir_evt := director.force_spawn_shipwreck(Vector3.FORWARD)
	check(not dir_evt.is_empty(), "WorldDirector.force_spawn_shipwreck() returns event dict")
	check_eq(dir_spawns.size(), 1, "WorldDirector.force_spawn_shipwreck() emits spawn_shipwreck")
	check_eq(dir_warnings.size(), 1, "WorldDirector.force_spawn_shipwreck() emits sighting_warning")
	if not dir_warnings.is_empty():
		var w_msg := String(dir_warnings[0]["msg"])
		var w_dist := float(dir_warnings[0]["dist"])
		check_eq(dir_warnings[0]["kind"], &"sunken_shipwreck", "sighting_warning kind is sunken_shipwreck")
		check(WorldDirector.COMPASS_POINTS.has(String(dir_warnings[0]["bearing"])),
			"shipwreck sighting_warning has valid compass bearing")
		check(w_dist >= WorldDirector.SHIPWRECK_MIN_RANGE and w_dist <= WorldDirector.SHIPWRECK_MAX_RANGE,
			"shipwreck sighting distance within 180..320 m (got %.1f)" % w_dist)
		for ci in w_msg.length():
			check(w_msg.unicode_at(ci) < 128, "WorldDirector shipwreck warning is strict ASCII")

	# 5. Verify CrewBrain.notify_shipwreck_sighted() (all 3 personas, strict ASCII)
	#    and _tick_lookout() deduplicated auto-detection of uncleared sunken_shipwrecks!
	var wreck_crew := SunkenShipwreck.spawn_at(_root, Vector3(120.0, 0.0, -320.0), 3403)
	await physics_frames(1)

	for pid: StringName in [&"helmsman", &"lookout", &"carpenter"]:
		var cp := _spawn_pawn(Vector3(0.0, 4.0, 0.0), &"player")
		var cb := CrewBrain.new()
		cb.persona_id = pid
		cp.add_child(cb)
		cb.setup(null, captain, pid)
		await physics_frames(1)

		var spoken: Array[Dictionary] = []
		cb.callout_spoken.connect(func(speaker: String, text: String, cat: StringName) -> void:
			spoken.append({"speaker": speaker, "text": text, "cat": cat})
		)

		check(cb.notify_shipwreck_sighted("Sunken Galleon", "NNE"),
			"%s notify_shipwreck_sighted returns true" % pid)
		check_eq(spoken.size(), 1, "%s emits shipwreck_sighted callout" % pid)
		if not spoken.is_empty():
			var line := String(spoken[0]["text"])
			check_eq(spoken[0]["cat"], &"shipwreck_sighted", "%s callout category matches" % pid)
			check(line.contains("NNE"), "%s shipwreck callout references bearing (got '%s')" % [pid, line])
			for ci in line.length():
				check(line.unicode_at(ci) < 128, "%s shipwreck_sighted line is strict ASCII" % pid)
		check(not cb.notify_shipwreck_sighted("Sunken Galleon", "NNE"),
			"%s SHIPWRECK_COOLDOWN prevents immediate duplicate callout" % pid)

		# Verify _tick_lookout() auto-detects uncleared wreck_crew within lookout_range * 1.15 once!
		if pid == &"lookout":
			spoken.clear()
			cb._scan_timer = 0.0
			cb._tick_lookout(0.1)
			check_eq(spoken.size(), 1, "lookout _tick_lookout() auto-detects uncleared SunkenShipwreck")
			cb._scan_timer = 0.0
			cb._tick_lookout(0.1)
			check_eq(spoken.size(), 1, "lookout _tick_lookout() deduplicates shipwreck callout per instance ID")

	# 6. Zero-leak teardown releases all static caches cleanly!
	await _end()
	SunkenShipwreck.clear_shared_cache()
	TreasureCatalog.clear_mesh_cache()
	check(not is_instance_valid(wreck_a) and not is_instance_valid(wreck_far) and not is_instance_valid(wreck_crew),
		"all SunkenShipwrecks freed cleanly")
	check_eq(SunkenShipwreck._active_wrecks, 0, "SunkenShipwreck._active_wrecks == 0 after teardown")
	check(SunkenShipwreck._hull_mesh == null and SunkenShipwreck._hull_mat == null \
			and SunkenShipwreck._accent_mat == null and SunkenShipwreck._glow_mat == null \
			and SunkenShipwreck._pbr_tex_cache.is_empty(),
		"SunkenShipwreck.clear_shared_cache() clears all static caches with zero leaks")


func test_wave35_sea_mermaid_sculpted_beacon_stranded_check_return_warp_and_crew_callouts() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Sea.time = 0.0

	# 1. Spawn two SeaMermaids and verify >= 950 sculpted tris, 0 PrimitiveMeshes,
	#    sRGB vertex-colored materials, 0 extra texture VRAM, finite unit normals,
	#    static mesh sharing, 16-tri diamond mist mote, shadowless 10.5 m light, & upright SmokePlume.
	var sloop_scene := preload("res://src/ship/sloop.tscn") as PackedScene
	var sloop := sloop_scene.instantiate() as Ship
	sloop.enable_effects = false
	_root.add_child(sloop)
	sloop.global_position = Vector3(0.0, 0.0, 0.0)
	await physics_frames(8)

	var m_a := SeaMermaid.spawn_at(_root, Vector3(72.0, 0.0, -20.0), sloop)
	var m_b := SeaMermaid.spawn_at(_root, Vector3(-72.0, 0.0, -20.0), sloop)
	await physics_frames(1)

	check(m_a != null and m_b != null, "SeaMermaid.spawn_at spawns sculpted mermaids cleanly")
	check(m_a.is_in_group(SeaMermaid.GROUP), "SeaMermaid registers in sea_mermaids group")

	var fig_mi_a := m_a.get_figure_mesh_instance()
	var fig_mi_b := m_b.get_figure_mesh_instance()
	var smk_mi_a := m_a.get_smoke_mesh_instance()
	var smk_mi_b := m_b.get_smoke_mesh_instance()
	check(fig_mi_a != null and fig_mi_b != null, "both SeaMermaids mount MerfolkFigure MeshInstance3D")
	check(smk_mi_a != null and smk_mi_b != null, "both SeaMermaids mount SmokeBeaconMesh MeshInstance3D")
	check(fig_mi_a.mesh is ArrayMesh and not (fig_mi_a.mesh is PrimitiveMesh),
		"MerfolkFigure uses sculpted ArrayMesh (zero PrimitiveMesh)")
	check(smk_mi_a.mesh is ArrayMesh and not (smk_mi_a.mesh is PrimitiveMesh),
		"SmokeBeaconMesh uses sculpted ArrayMesh (zero PrimitiveMesh)")
	check_eq(fig_mi_a.mesh, fig_mi_b.mesh, "SeaMermaids share statically cached _figure_mesh")
	check_eq(smk_mi_a.mesh, smk_mi_b.mesh, "SeaMermaids share statically cached _smoke_mesh")

	var raw_prims := 0
	for n in m_a.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh is PrimitiveMesh:
			raw_prims += 1
	var mist := m_a.get_mist_particles()
	check(mist != null and mist.mesh is ArrayMesh and not (mist.mesh is PrimitiveMesh),
		"SeaMistSparkles CPUParticles3D uses sculpted ArrayMesh (zero PrimitiveMesh)")
	if mist != null and mist.mesh is PrimitiveMesh:
		raw_prims += 1
	check_eq(raw_prims, 0, "SeaMermaid hierarchy contains zero PrimitiveMeshes")
	check_eq(m_a.get_mote_triangle_count(), 16, "sculpted diamond mist mote has exactly 16 triangles")

	var bad_normals := 0
	var fig_tris := 0
	var smoke_tris := 0
	for pair: Array in [[fig_mi_a.mesh as ArrayMesh, "figure"], [smk_mi_a.mesh as ArrayMesh, "smoke"]]:
		var am: ArrayMesh = pair[0] as ArrayMesh
		var tag := String(pair[1])
		var tris := 0
		for si in am.get_surface_count():
			var arr := am.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			tris += floori(float(verts.size()) / 3.0)
			for nv in norms:
				if not nv.is_finite() or nv.length_squared() < 0.5:
					bad_normals += 1
		if tag == "figure":
			fig_tris = tris
		else:
			smoke_tris = tris

	var total_tris := fig_tris + smoke_tris
	print("    SeaMermaid sculpted meshes: figure=%d tris, smoke=%d tris, mote=%d tris (total=%d tris)" % [
		fig_tris, smoke_tris, m_a.get_mote_triangle_count(), total_tris])
	check_eq(bad_normals, 0, "all SeaMermaid sculpted normals are finite unit vectors")
	check(total_tris >= 950, "SeaMermaid sculpted figure + emerald smoke >= 950 tris (got %d)" % total_tris)
	check_eq(m_a.get_triangle_count(), total_tris, "get_triangle_count() matches ArrayMesh totals")

	# Verify all 3 shared materials enable sRGB vertex colors and allocate 0 extra texture VRAM.
	for mat: StandardMaterial3D in [SeaMermaid._body_mat, SeaMermaid._glow_mat, SeaMermaid._smoke_mat]:
		check(mat != null and mat.vertex_color_use_as_albedo and mat.vertex_color_is_srgb,
			"SeaMermaid material enables sRGB vertex_color_use_as_albedo")
		if mat != null:
			check(mat.albedo_texture == null and mat.normal_texture == null and mat.roughness_texture == null,
				"SeaMermaid material allocates 0 extra texture VRAM")

	var light := m_a.get_conch_light()
	check(light != null and not light.shadow_enabled and is_equal_approx(light.omni_range, 10.5),
		"SeaMermaid mounts shadowless 10.5 m turquoise ConchLight")

	# Verify graceful emergence animation and strictly upright SmokePlume!
	var rise0 := m_a.rise_offset
	for _step in 30:
		m_a.step_mermaid(0.05)
	check(m_a.rise_offset > rise0 + 1.5 and is_equal_approx(m_a.rise_offset, 0.0),
		"SeaMermaid smoothly rises from -2.4 -> 0.0 (start=%.2f, now=%.2f)" % [rise0, m_a.rise_offset])
	var plume := m_a.get_smoke_plume()
	check(plume != null and plume.global_basis.y.distance_to(Vector3.UP) < 0.001,
		"SmokePlume stays strictly upright in world space")

	var it := m_a.interactable
	check(it != null and it.enabled and it.prompt == "Return to ship" \
			and is_equal_approx(it.reach, SeaMermaid.INTERACT_REACH),
		"SeaMermaid exposes enabled 'Return to ship' Interactable with 4.5 m reach")

	# 2. Verify SeaMermaid.should_spawn_for_pawn() across aboard, close swimmer (< 55 m), & stranded (>= 65 m)!
	var captain := _spawn_pawn(Vector3(0.0, 2.0, 0.0), &"player")
	captain.board(sloop, sloop.ship_point(Vector3(0.0, 1.25, -1.5)))
	await physics_frames(2)
	check(not SeaMermaid.should_spawn_for_pawn(captain, sloop),
		"should_spawn_for_pawn() returns false while captain is aboard ship")

	# Move swimmer into water 30 m from ship (< 55 m STRANDED_DISTANCE).
	captain.unboard()
	captain.global_position = Vector3(30.0, -1.35, 0.0)
	await physics_frames(4)
	check(captain.is_swimming(), "captain enters SWIM mode in open water")
	check(not SeaMermaid.should_spawn_for_pawn(captain, sloop),
		"should_spawn_for_pawn() returns false when swimming < 55 m away")

	# Move swimmer 70 m from ship (>= 65 m).
	captain.global_position = Vector3(70.0, -1.35, 0.0)
	await physics_frames(2)
	check(SeaMermaid.should_spawn_for_pawn(captain, sloop),
		"should_spawn_for_pawn() returns true when swimming >= 65 m away from ship")

	# Verify spawn_near_swimmer() spawns ~12 m ahead of the stranded swimmer.
	captain.look_yaw = 0.0  # facing -Z
	var m_near := SeaMermaid.spawn_near_swimmer(_root, captain, sloop)
	check(m_near != null, "spawn_near_swimmer() creates SeaMermaid ahead of swimmer")
	if m_near != null:
		var horiz_ahead := Vector2(
			m_near.global_position.x - captain.global_position.x,
			m_near.global_position.z - captain.global_position.z
		).length()
		check_near(horiz_ahead, SeaMermaid.SPAWN_AHEAD_DISTANCE, 0.25,
			"spawn_near_swimmer() spawns ~12 m ahead of swimmer (got %.2f m)" % horiz_ahead)

	# 3. Verify return_pawn_to_ship() warps stranded swimmer back onto deck, drops carried cargo,
	#    emits pawn_returned_to_ship, notifies onboard CrewBrain, and dismisses the mermaid!
	var crew_pawn := _spawn_pawn(Vector3(0.0, 2.0, 0.0), &"player")
	crew_pawn.board(sloop, sloop.ship_point(Vector3(0.8, 1.15, 0.5)))
	var crew_brain := CrewBrain.new()
	crew_brain.persona_id = &"helmsman"
	crew_pawn.add_child(crew_brain)
	crew_brain.setup(sloop, captain, &"helmsman")
	await physics_frames(2)

	var deck_callouts: Array[Dictionary] = []
	crew_brain.callout_spoken.connect(func(speaker: String, text: String, cat: StringName) -> void:
		deck_callouts.append({"speaker": speaker, "text": text, "cat": cat})
	)

	var chest := TreasureCatalog.create_treasure_carryable(&"sovereign_chest", captain.global_position)
	_root.add_child(chest)
	check(captain.pick_up(chest), "stranded swimmer picks up treasure chest before mermaid warp")
	check_eq(captain.carried, chest, "captain is carrying chest prior to warp")

	var return_events: Array[Dictionary] = []
	m_near.pawn_returned_to_ship.connect(func(mm: SeaMermaid, p: Pawn, s: Node3D) -> void:
		return_events.append({"mermaid": mm, "pawn": p, "ship": s})
	)

	check(m_near.return_pawn_to_ship(captain), "return_pawn_to_ship() succeeds for stranded swimmer")
	check_eq(captain.platform, sloop, "warped captain boards target ship (platform == ship)")
	check_eq(captain.mode, Pawn.Mode.WALK, "warped captain transitions cleanly to Mode.WALK")
	check(captain.carried == null, "mermaid warp drops carried item cleanly into the sea")
	check(not chest.is_held(), "dropped treasure chest is no longer held after warp")
	check(chest.global_position.distance_to(sloop.global_position) > 40.0,
		"dropped treasure stays behind in the sea instead of teleporting aboard")
	check_eq(return_events.size(), 1, "pawn_returned_to_ship signal emits once")
	if return_events.size() == 1:
		check_eq(return_events[0]["pawn"], captain, "signal passes warped pawn")
		check_eq(return_events[0]["ship"], sloop, "signal passes destination ship")
	check(m_near.dismissed and not m_near.interactable.enabled,
		"mermaid dismisses itself and disables interactable after warp")
	check_eq(deck_callouts.size(), 1, "crew aboard ship welcomes Captain back with mermaid_return callout")
	if deck_callouts.size() == 1:
		check_eq(deck_callouts[0]["cat"], &"mermaid_return", "crew welcome callout uses mermaid_return category")

	# Confirm captain remains solidly on deck across physics frames.
	await physics_frames(4)
	check_eq(captain.platform, sloop, "captain remains solidly aboard ship across physics ticks")
	check_eq(captain.mode, Pawn.Mode.WALK, "captain remains in Mode.WALK on main deck")

	# Verify RECALL_DISTANCE (< 38 m) auto-dismisses and gracefully submerges the mermaid.
	var swimmer2 := _spawn_pawn(Vector3(70.0, -1.35, 0.0), &"player")
	await physics_frames(4)
	var m_recall := SeaMermaid.spawn_near_swimmer(_root, swimmer2, sloop)
	check(m_recall != null and not m_recall.dismissed, "spawn_near_swimmer creates active mermaid for second swimmer")
	swimmer2.global_position = Vector3(24.0, -1.35, 0.0)
	m_recall.step_mermaid(0.05)
	check(m_recall.dismissed, "mermaid auto-dismisses when tracked swimmer swims within RECALL_DISTANCE (38 m)")
	for _s in 20:
		if is_instance_valid(m_recall):
			m_recall.step_mermaid(0.2)
	await physics_frames(2)
	check(not is_instance_valid(m_recall), "dismissed mermaid gracefully submerges and queue_free()s")

	# 4. Verify CrewBrain.notify_mermaid_return() and notify_megalodon_sighted() across all 3 personas
	#    (strict ASCII < 128, cooldown enforcement) AND _tick_lookout() auto-detecting megalodons group!
	var mock_meg := Node3D.new()
	mock_meg.name = "AncientMegalodonMock"
	mock_meg.add_to_group(&"megalodons")
	mock_meg.set_meta(&"display_name", "The Hungering Leviathan")
	_root.add_child(mock_meg)
	mock_meg.global_position = Vector3(140.0, -1.0, -340.0)
	await physics_frames(1)

	for pid: StringName in [&"helmsman", &"lookout", &"carpenter"]:
		var cp := _spawn_pawn(Vector3(0.0, 4.0, 0.0), &"player")
		var cb := CrewBrain.new()
		cb.persona_id = pid
		cp.add_child(cb)
		cb.setup(sloop, captain, pid)
		await physics_frames(1)

		var spoken: Array[Dictionary] = []
		cb.callout_spoken.connect(func(speaker: String, text: String, cat: StringName) -> void:
			spoken.append({"speaker": speaker, "text": text, "cat": cat})
		)

		check(cb.notify_mermaid_return(), "%s notify_mermaid_return() returns true" % pid)
		check(not cb.notify_mermaid_return(), "%s MERMAID_RETURN_COOLDOWN prevents immediate repeat" % pid)
		check(cb.notify_megalodon_sighted("Ancient Megalodon", "starboard quarter"),
			"%s notify_megalodon_sighted() returns true" % pid)
		check(not cb.notify_megalodon_sighted("Ancient Megalodon", "starboard quarter"),
			"%s MEGALODON_SIGHTED_COOLDOWN prevents immediate repeat" % pid)
		check_eq(spoken.size(), 2, "%s emits both mermaid_return and megalodon_sighted callouts" % pid)

		if spoken.size() == 2:
			check_eq(spoken[0]["cat"], &"mermaid_return", "%s first callout is mermaid_return" % pid)
			check_eq(spoken[1]["cat"], &"megalodon_sighted", "%s second callout is megalodon_sighted" % pid)
			var meg_line := String(spoken[1]["text"])
			check(meg_line.contains("Ancient Megalodon") and meg_line.contains("starboard quarter"),
				"%s megalodon callout includes target & bearing (got '%s')" % [pid, meg_line])
			for entry in spoken:
				var line := String(entry["text"])
				for ci in line.length():
					check(line.unicode_at(ci) < 128, "%s callout is strict ASCII ('%s')" % [pid, line])

		# Verify _tick_lookout() auto-detects live megalodons within lookout_range * 1.25 once!
		if pid == &"lookout":
			spoken.clear()
			cb._scan_timer = 0.0
			cb._tick_lookout(0.1)
			check_eq(spoken.size(), 1, "lookout _tick_lookout() auto-detects live megalodons group node")
			if spoken.size() == 1:
				check_eq(spoken[0]["cat"], &"megalodon_sighted", "auto-detected callout uses megalodon_sighted")
				check(String(spoken[0]["text"]).contains("The Hungering Leviathan"),
					"auto-detected callout resolves Megalodon display name")
			cb._scan_timer = 0.0
			cb._tick_lookout(0.1)
			check_eq(spoken.size(), 1, "lookout _tick_lookout() deduplicates Megalodon callout per instance ID")

	# 5. Clean zero-leak teardown releases all static caches cleanly!
	await _end()
	SeaMermaid.clear_shared_cache()
	TreasureCatalog.clear_mesh_cache()
	check(not is_instance_valid(m_a) and not is_instance_valid(m_b), "all SeaMermaids freed cleanly")
	check_eq(SeaMermaid._active_mermaids, 0, "SeaMermaid._active_mermaids == 0 after teardown")
	check(SeaMermaid._figure_mesh == null and SeaMermaid._smoke_mesh == null \
			and SeaMermaid._mote_mesh == null and SeaMermaid._body_mat == null \
			and SeaMermaid._glow_mat == null and SeaMermaid._smoke_mat == null,
		"SeaMermaid.clear_shared_cache() releases all static caches cleanly with zero leaks")


func test_q8b_seabird_flock_ship_slipstream_escort_and_return() -> void:
	_begin()
	var anchor := Vector3(0.0, 0.0, 0.0)
	var flock := SeabirdFlock.spawn_over(_root, anchor, 14.0, 16.0, 5)
	var birds := flock.get_birds()
	check_eq(birds.size(), 5, "flock spawns 5 coastal gulls")
	check(flock.get_escort_target_ship() == null, "no escort ship initially")
	check_eq(flock.get_escorting_bird_count(), 0, "zero gulls escorting before a moving ship arrives")

	# Spawn a sailing Sloop passing 70 m away (within 135 m enter radius) at 5.0 m/s (>= 1.6 m/s).
	var sloop_scene := preload("res://src/ship/sloop.tscn") as PackedScene
	var ship := sloop_scene.instantiate() as Ship
	ship.enable_effects = false
	ship.start_anchored = false
	_root.add_child(ship)
	ship.global_position = Vector3(70.0, 0.0, 0.0)
	ship.linear_velocity = Vector3(0.0, 0.0, -5.0)

	# Advance 2.5 s in 0.1 s steps so 2 gulls smoothly join the ship's trailing slipstream.
	for _step in 25:
		flock.step_flock(0.1)

	check_eq(flock.get_escort_target_ship(), ship, "flock locks onto passing sailing ship within 135 m")
	check_eq(flock.get_escorting_bird_count(), 2,
		"up to 2 gulls escort ship while 3 remain circling home loot marker (got %d)" % flock.get_escorting_bird_count())
	check(flock.get_bird_escort_blend(0) >= 0.95 and flock.get_bird_escort_blend(1) >= 0.95,
		"escort gulls reach full slipstream blend (b0=%.2f, b1=%.2f)" % [
			flock.get_bird_escort_blend(0), flock.get_bird_escort_blend(1)
		])

	# Verify the 2 escort gulls position cleanly in the trailing slipstream astern (+Z) of the ship.
	for idx in 2:
		var gp := birds[idx].global_position
		var aft_off := gp.z - ship.global_position.z
		var lat_off := absf(gp.x - ship.global_position.x)
		check(aft_off >= 9.0 and aft_off <= 25.0,
			"escort gull %d trails astern of ship (aft_off=%.2f m)" % [idx, aft_off])
		check(lat_off <= 11.5,
			"escort gull %d stays within slipstream weave width (lat_off=%.2f m)" % [idx, lat_off])
		check(gp.y >= 6.0 and gp.y <= 17.0,
			"escort gull %d rides masthead updraft altitude (y=%.2f m)" % [idx, gp.y])

	# Verify the remaining 3 gulls faithfully continue circling the home loot marker!
	for idx in range(2, 5):
		check_near(flock.get_bird_escort_blend(idx), 0.0, 0.001,
			"home loot-marker gull %d keeps zero escort blend" % idx)
		var hp := birds[idx].global_position
		var home_horiz := Vector2(hp.x - anchor.x, hp.z - anchor.z).length()
		check(home_horiz > 5.0 and home_horiz < 32.0,
			"home gull %d stays orbiting anchor beacon (horiz=%.2f m)" % [idx, home_horiz])

	# Hysteresis check: ship moves to 185 m (between 135 m enter and 240 m exit) and slows to 1.1 m/s
	# (between 0.75 m/s exit and 1.6 m/s enter) -> gulls stay smoothly locked without flicker!
	ship.global_position = Vector3(185.0, 0.0, 0.0)
	ship.linear_velocity = Vector3(0.0, 0.0, -1.1)
	for _step in 6:
		flock.step_flock(0.1)
	check_eq(flock.get_escort_target_ship(), ship,
		"distance & speed hysteresis retains escort target inside 240 m and >= 0.75 m/s")
	check_eq(flock.get_escorting_bird_count(), 2, "escort count remains 2 inside hysteresis band")

	# Move ship 300 m away (> 240 m exit radius) and advance 3.0 s -> smooth return to home flock!
	ship.global_position = Vector3(300.0, 0.0, 0.0)
	for _step in 30:
		flock.step_flock(0.1)
	check(flock.get_escort_target_ship() == null, "flock releases escort target beyond 240 m exit radius")
	check_eq(flock.get_escorting_bird_count(), 0, "all escort gulls disengage after ship sails away")
	check(flock.get_bird_escort_blend(0) <= 0.001 and flock.get_bird_escort_blend(1) <= 0.001,
		"escort blend returns smoothly to 0.0")
	for idx in 5:
		var bp := birds[idx].global_position
		var horiz := Vector2(bp.x - anchor.x, bp.z - anchor.z).length()
		check(horiz > 5.0 and horiz < 32.0,
			"gull %d returned smoothly to home elliptical orbit (horiz=%.2f m)" % [idx, horiz])

	# Verify anchored / slow speed (< 0.75 m/s) also releases escorts cleanly!
	ship.global_position = Vector3(70.0, 0.0, 0.0)
	ship.linear_velocity = Vector3(0.0, 0.0, -5.0)
	for _step in 25:
		flock.step_flock(0.1)
	check_eq(flock.get_escorting_bird_count(), 2, "gulls re-engage when ship sails back within 135 m")
	ship.linear_velocity = Vector3(0.0, 0.0, -0.2)
	for _step in 25:
		flock.step_flock(0.1)
	check(flock.get_escort_target_ship() == null, "flock releases escort target when ship drops below 0.75 m/s")
	check_eq(flock.get_escorting_bird_count(), 0, "escort gulls return home when ship anchors/stops")

	print("    Q8B seabird slipstream escort: enter/hysteresis/exit/anchor verified across all 5 gulls")
	await _end()


func test_q10b_shipwreck_bubbles_dive_halo_and_castaway_night_beacon() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Sea.time = 0.0
	ToolMeshes.clear_shared_cache()

	# 1. Static source guard: zero raw PrimitiveMesh allocations in shipwreck & castaway scripts.
	var wreck_src := FileAccess.get_file_as_string("res://src/world/sunken_shipwreck.gd")
	var raft_src := FileAccess.get_file_as_string("res://src/world/castaway_raft.gd")
	for bad_prim: String in ["QuadMesh.new", "BoxMesh.new", "SphereMesh.new", "CylinderMesh.new"]:
		check(not wreck_src.contains(bad_prim), "sunken_shipwreck.gd contains zero %s calls" % bad_prim)
		check(not raft_src.contains(bad_prim), "castaway_raft.gd contains zero %s calls" % bad_prim)

	# 2. SunkenShipwreck rising 12-tri underwater air-bubble streams + 2.4 m UnderwaterDiveHalo.
	var wreck := SunkenShipwreck.spawn_at(_root, Vector3(48.0, 0.0, -48.0), 10801)
	await physics_frames(2)

	check(wreck.has_bubble_streams(), "SunkenShipwreck mounts rising WreckBubbleStreams GPUParticles3D")
	var bubbles := wreck.get_bubble_stream_node()
	check(bubbles != null and bubbles.name == "WreckBubbleStreams",
		"get_bubble_stream_node() returns WreckBubbleStreams GPUParticles3D")
	if bubbles != null:
		check_eq(bubbles.amount, 24, "WreckBubbleStreams emits 24 rising air bubbles")
		check_near(bubbles.lifetime, 2.6, 0.01, "WreckBubbleStreams lifetime is 2.6 s")
		check_eq(bubbles.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"WreckBubbleStreams disables shadow casting")
		check(bubbles.draw_pass_1 is ArrayMesh and not (bubbles.draw_pass_1 is PrimitiveMesh),
			"WreckBubbleStreams draw_pass_1 uses sculpted ArrayMesh (zero SphereMesh)")
		if bubbles.draw_pass_1 is ArrayMesh:
			check_eq((bubbles.draw_pass_1 as ArrayMesh).get_faces().size(), 36,
				"sculpted faceted bubble ArrayMesh has exact 12 triangles (36 face vertices)")
		var bmat := bubbles.material_override as StandardMaterial3D
		check(bmat != null and bmat.rim_enabled and bmat.emission_enabled,
			"WreckBubbleStreams uses rim-shimmering translucent pearl-cyan StandardMaterial3D")
		if bmat != null:
			check(bmat.albedo_texture == null and bmat.normal_texture == null and bmat.roughness_texture == null,
				"WreckBubbleStreams bubble material allocates 0 extra VRAM textures")
		var bproc := bubbles.process_material as ParticleProcessMaterial
		check(bproc != null and bproc.scale_curve == null and bproc.color_ramp == null,
			"WreckBubbleStreams avoids CurveTexture/GradientTexture1D leak risks")
		check(bubbles.emitting, "WreckBubbleStreams stays active in headless when no camera exists")

	# Verify <= 95 m camera distance gate for WreckBubbleStreams.
	var cam := Camera3D.new()
	_root.add_child(cam)
	cam.current = true
	cam.global_position = wreck.global_position + Vector3(140.0, 12.0, 0.0)
	wreck.step_buoyancy(0.05)
	if bubbles != null:
		check(not bubbles.emitting, "WreckBubbleStreams pauses beyond 95 m camera cull range")
	cam.global_position = wreck.global_position + Vector3(45.0, 6.0, 0.0)
	wreck.step_buoyancy(0.05)
	if bubbles != null:
		check(bubbles.emitting, "WreckBubbleStreams resumes cleanly within 95 m of active camera")

	# Verify UnderwaterDiveHalo zero-primitive 2-tri billboard + turquoise-amber ShaderMaterial.
	var dive_halo := wreck.get_dive_beacon_halo_node()
	check(dive_halo != null and dive_halo.name == "UnderwaterDiveHalo",
		"SunkenShipwreck mounts UnderwaterDiveHalo MeshInstance3D")
	if dive_halo != null:
		check_eq(dive_halo.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"UnderwaterDiveHalo disables shadow casting")
		check_eq(dive_halo.gi_mode, GeometryInstance3D.GI_MODE_DISABLED,
			"UnderwaterDiveHalo disables GI mode")
		check(dive_halo.mesh is ArrayMesh and not (dive_halo.mesh is PrimitiveMesh),
			"UnderwaterDiveHalo uses zero-primitive SurfaceTool ArrayMesh")
		if dive_halo.mesh is ArrayMesh:
			check_eq((dive_halo.mesh as ArrayMesh).get_faces().size(), 6,
				"UnderwaterDiveHalo quad has exact 2 triangles (6 face vertices)")
		var hmat := dive_halo.material_override as ShaderMaterial
		check(hmat != null and hmat.shader != null, "UnderwaterDiveHalo uses zero-texture additive ShaderMaterial")
		if hmat != null:
			check_near(float(hmat.get_shader_parameter(&"halo_scale")), 2.4, 0.01,
				"UnderwaterDiveHalo uses 2.4 m underwater cabin beacon scale")
			check(float(hmat.get_shader_parameter(&"halo_intensity")) > 0.5,
				"UnderwaterDiveHalo glows visibly while cabin treasure remains")
		check(dive_halo.visible, "UnderwaterDiveHalo is visible within 120 m while uncleared")

	var wreck_prims := 0
	for n in wreck.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh is PrimitiveMesh:
			wreck_prims += 1
	check_eq(wreck_prims, 0, "SunkenShipwreck hierarchy contains zero raw PrimitiveMeshes")

	# 3. CastawayRaft Q9B ToolMeshes distress lantern halo: midday -> midnight (> 3x) -> storm night!
	var raft := CastawayRaft.new()
	raft.auto_buoyancy = false
	_root.add_child(raft)
	raft.set_process(false)
	await physics_frames(2)

	check(raft.lantern_node != null, "CastawayRaft hangs ToolMeshes SignalLantern")
	var raft_halo := raft.lantern_node.get_node_or_null(^"FlameHalo") as MeshInstance3D if raft.lantern_node != null else null
	check(raft_halo != null and raft_halo.mesh is ArrayMesh and not (raft_halo.mesh is PrimitiveMesh),
		"CastawayRaft distress lantern exposes zero-primitive ToolMeshes FlameHalo")

	Weather.time_of_day = 12.0
	Weather.set_weather(0.0, 8.0, 0.0)
	raft._process(1.0 / 60.0)
	var noon_e := raft.get_signal_halo_energy()
	check(noon_e >= 0.16 and noon_e <= 0.26,
		"CastawayRaft midday distress halo stays crisp and subtle (got %.3f)" % noon_e)

	Weather.time_of_day = 23.0
	Weather.set_weather(0.0, 8.0, 0.0)
	raft._process(1.0 / 60.0)
	var night_e := raft.get_signal_halo_energy()
	check(night_e > noon_e * 3.0 and night_e >= 1.05,
		"CastawayRaft night distress halo exceeds 3x midday (noon=%.3f -> night=%.3f)" % [noon_e, night_e])

	Weather.time_of_day = 23.0
	Weather.set_weather(1.0, 14.0, 0.0)
	raft._process(1.0 / 60.0)
	var storm_e := raft.get_signal_halo_energy()
	check(storm_e > night_e and storm_e >= 1.24,
		"CastawayRaft storm-night distress halo intensifies further (night=%.3f -> storm=%.3f)" % [night_e, storm_e])

	if raft_halo != null and raft_halo.material_override is ShaderMaterial:
		var rmat := raft_halo.material_override as ShaderMaterial
		check_near(float(rmat.get_shader_parameter(&"halo_scale")), 1.35, 0.01,
			"CastawayRaft distress lantern halo uses 1.35 m sea-horizon scale")
		check_near(float(rmat.get_shader_parameter(&"halo_intensity")), storm_e, 0.001,
			"CastawayRaft FlameHalo uniform matches get_signal_halo_energy()")

	print("    Q10B shipwreck bubbles/dive halo + castaway beacon: noon=%.3f, night=%.3f (%.1fx), storm=%.3f" % [
		noon_e, night_e, night_e / maxf(noon_e, 0.001), storm_e
	])

	# 4. Clean zero-leak teardown!
	await _end()
	SunkenShipwreck.clear_shared_cache()
	TreasureCatalog.clear_mesh_cache()
	ToolMeshes.clear_shared_cache()
	check_eq(SunkenShipwreck._active_wrecks, 0, "SunkenShipwreck._active_wrecks == 0 after Q10B teardown")
	check(SunkenShipwreck._bubble_mesh == null and SunkenShipwreck._bubble_mat == null \
			and SunkenShipwreck._bubble_proc == null and SunkenShipwreck._dive_halo_mesh == null \
			and SunkenShipwreck._dive_halo_shader == null,
		"SunkenShipwreck releases all bubble & dive halo static caches cleanly with zero leaks")


func test_q11a_reef_atmosphere_sun_shafts_sea_fans_clams_bubbles_and_biolum() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Sea.time = 0.0

	# 1. Static source guard: zero raw PrimitiveMesh allocations in reef_atmosphere.gd.
	var atmo_src := FileAccess.get_file_as_string("res://src/world/reef_atmosphere.gd")
	for bad_prim: String in [
		"BoxMesh.new", "SphereMesh.new", "CylinderMesh.new",
		"QuadMesh.new", "CapsuleMesh.new", "PrismMesh.new",
	]:
		check(not atmo_src.contains(bad_prim), "reef_atmosphere.gd contains zero %s calls" % bad_prim)

	# 2. Populate Crescent Lagoon reef and confirm CoralReef invariants + sibling ReefAtmosphere!
	var lagoon := IslandGenerator.build_island({
		"id": "test_q11a_crescent_lagoon",
		"name": "Q11A Crescent Lagoon",
		"archetype": &"crescent_lagoon",
		"seed": 11103,
	})
	_root.add_child(lagoon)

	var reef := CoralReef.populate_for_island(lagoon, 11107, 1.0)
	check(reef != null and reef.get_parent() == lagoon, "CoralReef attaches cleanly to Island")
	check_eq(reef.get_multimesh_count(), 3, "CoralReef preserves strictly 3 MultiMesh draw calls")
	check(reef.find_children("*", "MeshInstance3D", true, false).is_empty(),
		"CoralReef preserves zero MeshInstance3D children invariant")

	var brain_mmi := reef.get_node_or_null(^"BrainTableCorals") as MultiMeshInstance3D
	check(brain_mmi != null and brain_mmi.multimesh != null and brain_mmi.multimesh.mesh != null,
		"CoralReef preserves BrainTableCorals MultiMesh")
	if brain_mmi != null and brain_mmi.multimesh != null and brain_mmi.multimesh.mesh != null:
		var brain_tris := int(brain_mmi.multimesh.mesh.get_faces().size() / 3.0)
		check(brain_tris > 0 and brain_tris <= 420,
			"BrainTableCorals stays <= 420 tris (got %d)" % brain_tris)

	var atmo := lagoon.get_node_or_null(^"ReefAtmosphere") as ReefAtmosphere
	check(atmo != null, "CoralReef.populate_for_island auto-attaches sibling ReefAtmosphere on Island")
	if atmo == null:
		await _end()
		return
	check_eq(atmo.get_parent(), lagoon, "ReefAtmosphere is attached as sibling on Island")
	check(atmo.is_in_group(ReefAtmosphere.GROUP), "ReefAtmosphere registers in reef_atmosphere group")
	check_eq(atmo.get_child_count(), 3, "ReefAtmosphere owns strictly 3 GPU-batched procedural children")

	# 3. Inspect all 3 children: UnderwaterSunShafts, SeaFanClamBeds, ReefBubblePlumes.
	var shafts := atmo.get_node_or_null(^"UnderwaterSunShafts") as MeshInstance3D
	var seafans := atmo.get_node_or_null(^"SeaFanClamBeds") as MultiMeshInstance3D
	var bubbles := atmo.get_node_or_null(^"ReefBubblePlumes") as MultiMeshInstance3D
	check(shafts != null, "ReefAtmosphere owns UnderwaterSunShafts MeshInstance3D")
	check(seafans != null, "ReefAtmosphere owns SeaFanClamBeds MultiMeshInstance3D")
	check(bubbles != null, "ReefAtmosphere owns ReefBubblePlumes MultiMeshInstance3D")

	var raw_prims := 0
	var bad_normals := 0
	var shaft_tris := 0
	var seafan_tris := 0
	var bubble_tris := 0

	if shafts != null:
		check_eq(shafts.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"UnderwaterSunShafts disables shadow casting")
		var expected_shaft_vis := maxf(165.0, lagoon.seabed_radius + 115.0)
		check_near(shafts.visibility_range_end, expected_shaft_vis, 0.05,
			"UnderwaterSunShafts visibility_range_end matches maxf(165, seabed_radius + 115)")
		check(shafts.mesh is ArrayMesh and not (shafts.mesh is PrimitiveMesh),
			"UnderwaterSunShafts uses batched SurfaceTool ArrayMesh (zero PrimitiveMesh)")
		if shafts.mesh is PrimitiveMesh:
			raw_prims += 1
		elif shafts.mesh is ArrayMesh:
			var arr := (shafts.mesh as ArrayMesh).surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			shaft_tris = floori(float(verts.size()) / 3.0)
			for nv in norms:
				if not nv.is_finite() or nv.length_squared() < 0.5:
					bad_normals += 1
		check(atmo.get_sun_shaft_count() >= 10 and atmo.get_sun_shaft_count() <= 14,
			"UnderwaterSunShafts batches 10..14 slanted god-rays (got %d)" % atmo.get_sun_shaft_count())
		var smat := shafts.material_override as ShaderMaterial
		check(smat != null and smat.shader != null, "UnderwaterSunShafts uses cached custom ShaderMaterial")

	if seafans != null:
		check_eq(seafans.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"SeaFanClamBeds disables shadow casting")
		var expected_reef_vis := maxf(CoralReef.VISIBILITY_RANGE_END, lagoon.seabed_radius + 110.0)
		check_near(seafans.visibility_range_end, expected_reef_vis, 0.05,
			"SeaFanClamBeds visibility_range_end matches CoralReef")
		check(seafans.multimesh != null and seafans.multimesh.mesh is ArrayMesh \
				and not (seafans.multimesh.mesh is PrimitiveMesh),
			"SeaFanClamBeds uses sculpted ArrayMesh (zero PrimitiveMesh)")
		if seafans.multimesh != null and seafans.multimesh.mesh is PrimitiveMesh:
			raw_prims += 1
		elif seafans.multimesh != null and seafans.multimesh.mesh is ArrayMesh:
			var am := seafans.multimesh.mesh as ArrayMesh
			var arr := am.surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			seafan_tris = floori(float(verts.size()) / 3.0)
			for nv in norms:
				if not nv.is_finite() or nv.length_squared() < 0.5:
					bad_normals += 1
			check(seafan_tris >= 180 and seafan_tris <= 320,
				"SeaFanClam sculpted mesh stays crisp within 180..320 tris (got %d)" % seafan_tris)
		var sf_mat := seafans.material_override as StandardMaterial3D
		check(sf_mat != null and sf_mat.vertex_color_use_as_albedo and sf_mat.vertex_color_is_srgb,
			"SeaFanClamBeds uses sRGB vertex-colored StandardMaterial3D")
		if sf_mat != null:
			check(sf_mat.albedo_texture == null and sf_mat.normal_texture == null and sf_mat.roughness_texture == null,
				"SeaFanClamBeds material allocates 0 extra VRAM textures")

	if bubbles != null:
		check_eq(bubbles.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"ReefBubblePlumes disables shadow casting")
		check_near(bubbles.visibility_range_end, 115.0, 0.05,
			"ReefBubblePlumes visibility_range_end is 115.0 m")
		check(bubbles.multimesh != null and bubbles.multimesh.mesh is ArrayMesh \
				and not (bubbles.multimesh.mesh is PrimitiveMesh),
			"ReefBubblePlumes uses sculpted ArrayMesh (zero SphereMesh)")
		if bubbles.multimesh != null and bubbles.multimesh.mesh is PrimitiveMesh:
			raw_prims += 1
		elif bubbles.multimesh != null and bubbles.multimesh.mesh is ArrayMesh:
			var am := bubbles.multimesh.mesh as ArrayMesh
			var arr := am.surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			bubble_tris = floori(float(verts.size()) / 3.0)
			for nv in norms:
				if not nv.is_finite() or nv.length_squared() < 0.5:
					bad_normals += 1
			check_eq(bubble_tris, 12, "sculpted gem micro-bubble mesh has exact 12 triangles")
		var b_mat := bubbles.material_override as StandardMaterial3D
		check(b_mat != null and b_mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
				and b_mat.rim_enabled,
			"ReefBubblePlumes uses translucent rim-shimmering pearl-cyan material")
		if b_mat != null:
			check(b_mat.albedo_texture == null and b_mat.normal_texture == null and b_mat.roughness_texture == null,
				"ReefBubblePlumes material allocates 0 extra VRAM textures")

	check_eq(raw_prims, 0, "ReefAtmosphere contains zero raw PrimitiveMeshes")
	check_eq(bad_normals, 0, "all ReefAtmosphere procedural normals are finite unit vectors")

	# Verify SeaFanClamBeds count, underwater grounding, mooring keepout, and positive determinant.
	var sf_count := atmo.get_sea_fan_clam_count()
	check(sf_count >= 12 and sf_count <= 32,
		"SeaFanClamBeds populates >= 12 sculpted Giant Pearl-Clams & Sea-Fans (got %d)" % sf_count)
	var sf_xforms := atmo.get_placed_sea_fan_transforms()
	check_eq(sf_xforms.size(), sf_count, "get_placed_sea_fan_transforms() matches count")
	var mooring_xz := Vector2(lagoon.mooring_transform.origin.x, lagoon.mooring_transform.origin.z)
	var max_sf_y := -INF
	var min_sf_y := INF
	var min_sf_moor := INF
	var max_sf_ground_err := 0.0
	var bad_sf_det := 0
	for xf in sf_xforms:
		var p := xf.origin
		max_sf_y = maxf(max_sf_y, p.y)
		min_sf_y = minf(min_sf_y, p.y)
		min_sf_moor = minf(min_sf_moor, Vector2(p.x, p.z).distance_to(mooring_xz))
		var expected_y := lagoon.surface_height(p.x, p.z) - CoralReef.ROOT_EMBED_Y
		max_sf_ground_err = maxf(max_sf_ground_err, absf(p.y - expected_y))
		if xf.basis.determinant() <= 0.0:
			bad_sf_det += 1
	check(max_sf_y <= -1.15, "all SeaFanClam roots sit strictly underwater (max_y=%.2f)" % max_sf_y)
	check(min_sf_y >= -8.50, "all SeaFanClam roots sit in shallow reef shelf (min_y=%.2f)" % min_sf_y)
	check(min_sf_moor >= CoralReef.MOORING_CLEAR_RADIUS - 0.01,
		"all SeaFanClams clear mooring keepout >= 9.5 m (min=%.2f m)" % min_sf_moor)
	check(max_sf_ground_err < 0.02,
		"all SeaFanClams ground cleanly into seabed heightfield (max_err=%.4f m)" % max_sf_ground_err)
	check_eq(bad_sf_det, 0, "all SeaFanClam transforms have positive determinant")

	# Verify Outpost pier keepout + static mesh/shader sharing across a second island.
	var outpost := IslandGenerator.build_island({
		"id": "test_q11a_outpost",
		"name": "Q11A Outpost",
		"archetype": &"outpost",
		"seed": 11119,
	}) as Outpost
	_root.add_child(outpost)
	CoralReef.populate_for_island(outpost, 11123, 1.0)
	var op_atmo := outpost.get_node_or_null(^"ReefAtmosphere") as ReefAtmosphere
	check(op_atmo != null, "Outpost island also auto-attaches sibling ReefAtmosphere")
	if op_atmo != null:
		var pier_a := Vector2(outpost.dock_local_transform.origin.x, outpost.dock_local_transform.origin.z)
		var pier_b := Vector2(outpost.dock_pier_end_local.x, outpost.dock_pier_end_local.z)
		var min_pier_d := INF
		for xf in op_atmo.get_placed_sea_fan_transforms():
			var pt := Vector2(xf.origin.x, xf.origin.z)
			var ab := pier_b - pier_a
			var t := clampf((pt - pier_a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			min_pier_d = minf(min_pier_d, pt.distance_to(pier_a + ab * t))
		if op_atmo.get_sea_fan_clam_count() > 0:
			check(min_pier_d >= CoralReef.PIER_CLEAR_RADIUS - 0.01,
				"Outpost SeaFanClams clear dock pier >= 5.0 m (min=%.2f m)" % min_pier_d)
		var op_sf := op_atmo.get_node_or_null(^"SeaFanClamBeds") as MultiMeshInstance3D
		var op_bub := op_atmo.get_node_or_null(^"ReefBubblePlumes") as MultiMeshInstance3D
		if op_sf != null and seafans != null:
			check_eq(op_sf.multimesh.mesh, seafans.multimesh.mesh,
				"islands share static cached SeaFanClam ArrayMesh")
		if op_bub != null and bubbles != null:
			check_eq(op_bub.multimesh.mesh, bubbles.multimesh.mesh,
				"islands share static cached ReefBubble ArrayMesh")

	# 4. Verify sun-shaft intensity ordering: clear noon > heavy storm > midnight, plus golden sunset tint!
	Weather.time_of_day = 12.5
	Weather.set_weather(0.0, 7.0, 0.0)
	atmo.tick_atmosphere(0.05, false)
	var noon_shaft := atmo.get_sun_shaft_intensity()
	var noon_col := atmo.get_sun_shaft_color()
	var noon_biolum := atmo.get_biolum_strength()
	var noon_coral_e := CoralReef._coral_material.emission_energy_multiplier

	Weather.time_of_day = 18.0
	Weather.set_weather(0.0, 7.0, 0.0)
	atmo.tick_atmosphere(0.05, false)
	var sunset_col := atmo.get_sun_shaft_color()

	Weather.time_of_day = 12.5
	Weather.set_weather(0.9, 18.0, 0.0)
	atmo.tick_atmosphere(0.05, false)
	var storm_shaft := atmo.get_sun_shaft_intensity()

	Weather.time_of_day = 0.5
	Weather.set_weather(0.0, 6.0, 0.0)
	atmo.tick_atmosphere(0.05, false)
	var midnight_shaft := atmo.get_sun_shaft_intensity()
	var midnight_biolum := atmo.get_biolum_strength()
	var midnight_coral_e := CoralReef._coral_material.emission_energy_multiplier
	var midnight_seafan_e := ReefAtmosphere._seafan_clam_material.emission_energy_multiplier

	check(noon_shaft > storm_shaft and storm_shaft > midnight_shaft,
		"sun-shaft intensity orders noon (%.3f) > storm (%.3f) > midnight (%.3f)" % [
			noon_shaft, storm_shaft, midnight_shaft
		])
	check(midnight_shaft >= 0.03 and midnight_shaft <= 0.07,
		"midnight sun-shafts settle to soft moonlit cyan (~0.045, got %.3f)" % midnight_shaft)
	check(sunset_col.r > noon_col.r + 0.15,
		"sunset sun-shafts warm into golden-amber (noon.r=%.2f -> sunset.r=%.2f)" % [noon_col.r, sunset_col.r])

	# 5. Verify nocturnal coral bioluminescence rises cleanly at midnight on CoralReef & SeaFanClamBeds!
	check(midnight_biolum > noon_biolum + 0.85,
		"nocturnal bioluminescence rises at midnight (noon=%.3f -> midnight=%.3f)" % [noon_biolum, midnight_biolum])
	check(midnight_coral_e > noon_coral_e + 0.45,
		"CoralReef._coral_material.emission_energy_multiplier rises at night (%.3f -> %.3f)" % [
			noon_coral_e, midnight_coral_e
		])
	check(midnight_seafan_e > 0.50,
		"SeaFanClamBeds material glows softly at night (energy=%.3f)" % midnight_seafan_e)

	# 6. Verify rising reef micro-bubble plumes, <= 95 m camera distance gate & clean wrap under y = -0.15!
	var bub_count := atmo.get_bubble_count()
	check(bub_count >= 30 and bub_count <= 48,
		"ReefBubblePlumes spawns >= 30 micro-bubbles (got %d)" % bub_count)

	# Without camera (or far camera), non-forced tick_atmosphere keeps bubbles paused (0.00 ms far CPU).
	var h_before_far := atmo.get_bubble_heights()
	atmo.tick_atmosphere(0.25, false)
	var h_after_no_cam := atmo.get_bubble_heights()
	check_eq(h_after_no_cam, h_before_far, "bubbles skip updates when no camera is within 95 m")

	var cam := Camera3D.new()
	_root.add_child(cam)
	cam.current = true
	cam.global_position = lagoon.global_position + Vector3(360.0, 12.0, 0.0)
	atmo.tick_atmosphere(0.25, false)
	check_eq(atmo.get_bubble_heights(), h_before_far, "bubbles pause beyond 95 m camera cull range")

	# Forced tick advances bubble heights smoothly upward & wraps cleanly under y = -0.15!
	atmo.tick_atmosphere(0.25, true)
	var h_after_step := atmo.get_bubble_heights()
	var rose_count := 0
	var wrapped_count := 0
	var max_bub_y := -INF
	for i in bub_count:
		max_bub_y = maxf(max_bub_y, h_after_step[i])
		if h_after_step[i] > h_before_far[i] + 0.05:
			rose_count += 1
		elif h_after_step[i] < h_before_far[i] - 0.30:
			wrapped_count += 1
	check(rose_count >= int(float(bub_count) * 0.6),
		"forced tick_atmosphere(0.25, true) rises bubbles upward (rose=%d, wrapped=%d / %d)" % [
			rose_count, wrapped_count, bub_count
		])
	check(max_bub_y < -0.15, "all bubbles stay strictly under y = -0.15 after step (max=%.3f)" % max_bub_y)

	# Run 25 more forced ticks (~6.25 s) to verify repeated wraps stay strictly under y = -0.15.
	var saw_wrap := wrapped_count > 0
	var prev_h := h_after_step
	for _s in 25:
		atmo.tick_atmosphere(0.25, true)
		var cur_h := atmo.get_bubble_heights()
		for i in bub_count:
			max_bub_y = maxf(max_bub_y, cur_h[i])
			if cur_h[i] < prev_h[i] - 0.35:
				saw_wrap = true
		prev_h = cur_h
	check(saw_wrap, "bubbles wrap smoothly back to seabed vents over multi-second plume cycle")
	check(max_bub_y < -0.15, "bubbles never breach y = -0.15 across full plume cycles (max=%.3f)" % max_bub_y)

	# Verify close camera within <= 95 m animates bubbles without force_bubbles.
	if not atmo._vent_positions.is_empty():
		cam.global_position = lagoon.to_global(atmo._vent_positions[0]) + Vector3(12.0, 2.0, 0.0)
		var h_before_cam := atmo.get_bubble_heights()
		atmo.tick_atmosphere(0.25, false)
		var h_after_cam := atmo.get_bubble_heights()
		var moved_cam := 0
		for i in bub_count:
			if absf(h_after_cam[i] - h_before_cam[i]) > 0.01:
				moved_cam += 1
		check(moved_cam == bub_count,
			"active camera within <= 95 m drives all %d bubbles without force flag (moved=%d)" % [
				bub_count, moved_cam
			])

	print("    Q11A reef atmosphere: shafts=%d (%d tris, noon=%.3f/storm=%.3f/night=%.3f), seafan_clams=%d (%d tris), bubbles=%d (%d tris), biolum=%.2f->%.2f" % [
		atmo.get_sun_shaft_count(), shaft_tris, noon_shaft, storm_shaft, midnight_shaft,
		sf_count, seafan_tris, bub_count, bubble_tris, noon_coral_e, midnight_coral_e
	])

	# 7. Clean zero-leak teardown releases ALL static caches cleanly!
	await _end()
	CoralReef.clear_shared_cache()
	check(not is_instance_valid(atmo), "ReefAtmosphere frees cleanly with Island")
	check_eq(ReefAtmosphere._active_count, 0, "ReefAtmosphere._active_count == 0 after teardown")
	check(ReefAtmosphere._sun_shaft_shader == null \
			and ReefAtmosphere._seafan_clam_mesh == null \
			and ReefAtmosphere._seafan_clam_material == null \
			and ReefAtmosphere._bubble_mesh == null \
			and ReefAtmosphere._bubble_material == null,
		"ReefAtmosphere releases all static shader, mesh & material caches cleanly with zero leaks")


func test_q13b_flotsam_salvage_glint_supply_barrel_glint_and_shark_spray() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Sea.time = 0.0

	# 1. Static source guard: zero raw PrimitiveMesh allocations & safe Vulkan MultiMesh teardown.
	var flotsam_src := FileAccess.get_file_as_string("res://src/world/flotsam_cluster.gd")
	var barrel_src := FileAccess.get_file_as_string("res://src/world/supply_barrel.gd")
	var shark_src := FileAccess.get_file_as_string("res://src/combat/shark.gd")
	for bad_prim: String in [
		"BoxMesh.new", "SphereMesh.new", "CylinderMesh.new",
		"QuadMesh.new", "CapsuleMesh.new", "PrismMesh.new",
	]:
		check(not flotsam_src.contains(bad_prim), "flotsam_cluster.gd contains zero %s calls" % bad_prim)
		check(not barrel_src.contains(bad_prim), "supply_barrel.gd contains zero %s calls" % bad_prim)
		check(not shark_src.contains(bad_prim), "shark.gd contains zero %s calls" % bad_prim)
	check(not shark_src.contains("multimesh.mesh = null") and not shark_src.contains("mm.mesh = null"),
		"shark.gd follows Godot 4.8 Vulkan rule (never nulls .mesh on a live MultiMesh)")

	# 2. FlotsamCluster: sculpted zero-primitive additive SalvageGlint (24..32 tris), distance gate & salvage hide!
	var fc_a := FlotsamCluster.spawn_at(_root, Vector3(24.0, 0.0, -32.0), 1301)
	var fc_b := FlotsamCluster.spawn_at(_root, Vector3(-24.0, 0.0, -36.0), 1302)
	var f_glint := fc_a.get_salvage_glint_node()
	var f_glint_b := fc_b.get_salvage_glint_node()
	check(f_glint != null and f_glint.name == "SalvageGlint",
		"FlotsamCluster mounts SalvageGlint MeshInstance3D via get_salvage_glint_node()")
	check(f_glint_b != null and f_glint.mesh == f_glint_b.mesh,
		"FlotsamClusters share statically cached _glint_mesh ArrayMesh")

	var flotsam_glint_tris := 0
	var flotsam_bad_normals := 0
	var flotsam_has_black_tip := false
	var flotsam_has_gold_core := false
	if f_glint != null:
		check_eq(f_glint.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"SalvageGlint disables shadow casting")
		check(f_glint.mesh is ArrayMesh and not (f_glint.mesh is PrimitiveMesh),
			"SalvageGlint uses sculpted ArrayMesh (zero PrimitiveMesh)")
		if f_glint.mesh is ArrayMesh:
			var arr := (f_glint.mesh as ArrayMesh).surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			flotsam_glint_tris = floori(float(verts.size()) / 3.0)
			for nv in norms:
				if not nv.is_finite() or nv.distance_to(Vector3(0.0, 0.0, 1.0)) > 0.001:
					flotsam_bad_normals += 1
			for cv in cols:
				if cv.r <= 0.001 and cv.g <= 0.001 and cv.b <= 0.001 and cv.a >= 0.99:
					flotsam_has_black_tip = true
				if cv.r >= 0.95 and cv.g >= 0.85 and cv.b >= 0.65:
					flotsam_has_gold_core = true
		check(flotsam_glint_tris >= 24 and flotsam_glint_tris <= 32,
			"SalvageGlint 4-point star flare has 24..32 tris (got %d)" % flotsam_glint_tris)
		check_eq(flotsam_bad_normals, 0, "SalvageGlint normals are all finite (0, 0, 1) unit vectors")
		check(flotsam_has_gold_core and flotsam_has_black_tip,
			"SalvageGlint fades from warm golden-amber core to Color(0, 0, 0, 1) tips")

		var f_mat := f_glint.material_override as StandardMaterial3D
		check(f_mat != null and f_mat.vertex_color_use_as_albedo and f_mat.vertex_color_is_srgb \
				and f_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
				and f_mat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD \
				and f_mat.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED \
				and f_mat.billboard_keep_scale \
				and f_mat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED,
			"SalvageGlint uses unshaded additive scale-preserving billboard StandardMaterial3D")
		if f_mat != null:
			check(f_mat.albedo_texture == null and f_mat.normal_texture == null and f_mat.roughness_texture == null,
				"SalvageGlint allocates 0 extra VRAM textures")

		# Distance gating: shows at 40 m, hides at 2 m and 180 m, twinkles smoothly over time.
		fc_a.tick_glint(0.05, 40.0)
		check(f_glint.visible and f_glint.scale.x > 0.25, "SalvageGlint shows brightly at 40 m")
		var s40_a := f_glint.scale.x
		fc_a.tick_glint(0.55, 40.0)
		var s40_b := f_glint.scale.x
		check(absf(s40_b - s40_a) > 0.01, "SalvageGlint twinkles smoothly across time (%.3f -> %.3f)" % [s40_a, s40_b])
		fc_a.tick_glint(0.05, 2.0)
		check(not f_glint.visible, "SalvageGlint hides inside 5.5 m near threshold (2 m)")
		fc_a.tick_glint(0.05, 180.0)
		check(not f_glint.visible, "SalvageGlint hides beyond 155 m far threshold (180 m)")
		fc_a.tick_glint(0.05, 40.0)
		check(f_glint.visible, "SalvageGlint re-appears cleanly at 40 m before salvage")

		# Step buoyancy > 1.25 s to exercise rate-limited ocean foam ripple path cleanly.
		for _b in 8:
			fc_a.step_buoyancy(0.20)

		# Salvaging immediately hides SalvageGlint and keeps it hidden!
		var f_loot := fc_a.salvage(null)
		check(not f_loot.is_empty(), "FlotsamCluster.salvage() returns loot payload")
		check(not f_glint.visible, "SalvageGlint hides immediately on salvage()")
		fc_a.tick_glint(0.10, 40.0)
		check(not f_glint.visible, "SalvageGlint stays hidden on tick_glint() after salvage")

	# 3. SupplyBarrel: sculpted zero-primitive additive LidGlint (24..32 tris), distance gate & take_all hide!
	var sb_a := SupplyBarrel.new()
	sb_a.name = "SupplyBarrelA"
	sb_a.position = Vector3(10.0, 2.0, -14.0)
	_root.add_child(sb_a)

	var sb_b := SupplyBarrel.new()
	sb_b.name = "SupplyBarrelB"
	sb_b.position = Vector3(-10.0, 2.0, -14.0)
	_root.add_child(sb_b)

	var l_glint := sb_a.get_lid_glint_node()
	var l_glint_b := sb_b.get_lid_glint_node()
	check(l_glint != null and l_glint.name == "LidGlint",
		"SupplyBarrel mounts LidGlint MeshInstance3D via get_lid_glint_node()")
	check(l_glint_b != null and l_glint.mesh == l_glint_b.mesh,
		"SupplyBarrels share statically cached _glint_mesh ArrayMesh")

	var lid_glint_tris := 0
	var lid_bad_normals := 0
	var lid_has_black_tip := false
	var lid_has_brass_core := false
	if l_glint != null:
		check(l_glint.position.distance_to(Vector3(0.0, SupplyBarrel.LID_HEIGHT_Y + 0.14, 0.0)) < 0.001,
			"LidGlint mounts right above the golden lid seal at y = LID_HEIGHT_Y + 0.14")
		check_eq(l_glint.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"LidGlint disables shadow casting")
		check(l_glint.mesh is ArrayMesh and not (l_glint.mesh is PrimitiveMesh),
			"LidGlint uses sculpted ArrayMesh (zero PrimitiveMesh)")
		if l_glint.mesh is ArrayMesh:
			var arr := (l_glint.mesh as ArrayMesh).surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			lid_glint_tris = floori(float(verts.size()) / 3.0)
			for nv in norms:
				if not nv.is_finite() or nv.distance_to(Vector3(0.0, 0.0, 1.0)) > 0.001:
					lid_bad_normals += 1
			for cv in cols:
				if cv.r <= 0.001 and cv.g <= 0.001 and cv.b <= 0.001 and cv.a >= 0.99:
					lid_has_black_tip = true
				if cv.r >= 0.95 and cv.g >= 0.85 and cv.b >= 0.60:
					lid_has_brass_core = true
		check(lid_glint_tris >= 24 and lid_glint_tris <= 32,
			"LidGlint 4-point star flare has 24..32 tris (got %d)" % lid_glint_tris)
		check_eq(lid_bad_normals, 0, "LidGlint normals are all finite (0, 0, 1) unit vectors")
		check(lid_has_brass_core and lid_has_black_tip,
			"LidGlint fades from sunlit brass-gold core to Color(0, 0, 0, 1) edge")

		var l_mat := l_glint.material_override as StandardMaterial3D
		check(l_mat != null and l_mat.vertex_color_use_as_albedo and l_mat.vertex_color_is_srgb \
				and l_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
				and l_mat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD \
				and l_mat.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED \
				and l_mat.billboard_keep_scale \
				and l_mat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED,
			"LidGlint uses unshaded additive scale-preserving billboard StandardMaterial3D")
		if l_mat != null:
			check(l_mat.albedo_texture == null and l_mat.normal_texture == null and l_mat.roughness_texture == null,
				"LidGlint allocates 0 extra VRAM textures")

		# Distance gating: shows at 22 m, hides at 1.5 m and 90 m, pulses softly over time.
		sb_a.tick_glint(0.05, 22.0)
		check(l_glint.visible and l_glint.scale.x > 0.25, "LidGlint shows clearly at 22 m")
		var s22_a := l_glint.scale.x
		sb_a.tick_glint(0.65, 22.0)
		var s22_b := l_glint.scale.x
		check(absf(s22_b - s22_a) > 0.01, "LidGlint pulses softly over time (%.3f -> %.3f)" % [s22_a, s22_b])
		sb_a.tick_glint(0.05, 1.5)
		check(not l_glint.visible, "LidGlint hides inside 4.0 m near threshold (1.5 m)")
		sb_a.tick_glint(0.05, 90.0)
		check(not l_glint.visible, "LidGlint hides beyond 75.0 m far threshold (90 m)")
		sb_a.tick_glint(0.05, 22.0)
		check(l_glint.visible, "LidGlint re-appears cleanly at 22 m before looting")

		# take_all() hides LidGlint immediately via _apply_looted_visuals().
		var sb_loot := sb_a.take_all(null)
		check(not sb_loot.is_empty(), "SupplyBarrel.take_all() returns loot payload")
		check(not l_glint.visible, "LidGlint hides immediately on take_all()")
		sb_a.tick_glint(0.10, 22.0)
		check(not l_glint.visible, "LidGlint stays hidden on tick_glint() after take_all()")

	# 4. Shark: sculpted zero-primitive SharkSplashSpray (16 instances, 12-tri droplets) + nocturnal eye sheen!
	var sh_a := Shark.new()
	sh_a.name = "SharkQ13B_A"
	_root.add_child(sh_a)
	sh_a.global_position = Vector3(14.0, -0.35, 14.0)

	var sh_b := Shark.new()
	sh_b.name = "SharkQ13B_B"
	_root.add_child(sh_b)
	sh_b.global_position = Vector3(-14.0, -0.35, 14.0)

	var spray_a := sh_a.get_splash_spray_node()
	var spray_b := sh_b.get_splash_spray_node()
	check(spray_a != null and spray_a.name == "SharkSplashSpray",
		"Shark mounts SharkSplashSpray MultiMeshInstance3D via get_splash_spray_node()")
	check(not sh_a.is_splash_active() and (spray_a == null or not spray_a.visible),
		"SharkSplashSpray starts hidden when circling calmly")

	var droplet_tris := 0
	var droplet_bad_normals := 0
	if spray_a != null:
		check_eq(spray_a.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"SharkSplashSpray disables shadow casting")
		check_near(spray_a.visibility_range_end, 110.0, 0.05,
			"SharkSplashSpray sets visibility_range_end = 110.0 m")
		var mm := spray_a.multimesh
		check(mm != null and mm.instance_count == 16 and mm.use_colors,
			"SharkSplashSpray configures 16 per-instance colored droplets")
		check(mm != null and mm.mesh is ArrayMesh and not (mm.mesh is PrimitiveMesh),
			"SharkSplashSpray uses sculpted ArrayMesh (zero SphereMesh)")
		if spray_b != null and spray_b.multimesh != null and mm != null:
			check_eq(mm.mesh, spray_b.multimesh.mesh,
				"Sharks share statically cached 12-tri spray droplet ArrayMesh")
		if mm != null and mm.mesh is ArrayMesh:
			var arr := (mm.mesh as ArrayMesh).surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			droplet_tris = floori(float(verts.size()) / 3.0)
			for nv in norms:
				if not nv.is_finite() or nv.length_squared() < 0.5:
					droplet_bad_normals += 1
		check_eq(droplet_tris, 12, "sculpted spray droplet mesh has exact 12 triangles")
		check_eq(droplet_bad_normals, 0, "all spray droplet normals are finite unit vectors")

		var sp_mat := spray_a.material_override as StandardMaterial3D
		check(sp_mat != null and sp_mat.vertex_color_use_as_albedo and sp_mat.vertex_color_is_srgb \
				and sp_mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
				and is_equal_approx(sp_mat.roughness, 0.15) and sp_mat.rim_enabled,
			"SharkSplashSpray uses translucent white-aqua sRGB StandardMaterial3D with rim & 0.15 roughness")
		if sp_mat != null:
			check(sp_mat.albedo_texture == null and sp_mat.normal_texture == null and sp_mat.roughness_texture == null,
				"SharkSplashSpray allocates 0 extra VRAM textures")

		# Verify trigger_splash_burst() activates, arcs droplets upward, and decays smoothly to hidden over 0.65 s!
		sh_a.state = Shark.State.CIRCLE
		sh_a._state_timer = 10.0
		sh_a.trigger_splash_burst(1.0)
		check(sh_a.is_splash_active() and spray_a.visible,
			"trigger_splash_burst() immediately activates SharkSplashSpray")
		var pts0 := sh_a.get_splash_droplet_positions()
		var sum_y0 := 0.0
		var max_y0 := -INF
		for p in pts0:
			sum_y0 += p.y
			max_y0 = maxf(max_y0, p.y)
		var mean_y0 := sum_y0 / float(maxi(1, pts0.size()))

		await physics_frames(9)  # ~0.15 s into ballistic upward arc
		check(sh_a.is_splash_active() and spray_a.visible,
			"SharkSplashSpray remains active mid-arc (~0.15 s)")
		var pts_mid := sh_a.get_splash_droplet_positions()
		var sum_ym := 0.0
		var max_ym := -INF
		for p in pts_mid:
			sum_ym += p.y
			max_ym = maxf(max_ym, p.y)
		var mean_ym := sum_ym / float(maxi(1, pts_mid.size()))
		check(mean_ym > mean_y0 + 0.25 and max_ym > max_y0 + 0.30,
			"spray droplets arc energetically upward (mean %.2f->%.2f, max %.2f->%.2f)" % [
				mean_y0, mean_ym, max_y0, max_ym
			])
		if DisplayServer.get_name() != "headless" and mm != null:
			check(mm.get_instance_transform(0).origin.distance_to(pts_mid[0]) < 0.001,
				"GPU MultiMesh transform matches cached droplet position")

		await physics_frames(36)  # total ~0.75 s > 0.65 s SPLASH_DURATION
		check(not sh_a.is_splash_active() and not spray_a.visible,
			"SharkSplashSpray decays cleanly back to hidden after 0.65 s")

	# Verify CIRCLE -> CHARGE transition triggers SharkSplashSpray automatically & decays on RETREAT!
	sh_b.state = Shark.State.CIRCLE
	sh_b._state_timer = 10.0
	await physics_frames(2)
	check(not sh_b.is_splash_active() and (spray_b == null or not spray_b.visible),
		"SharkB spray stays hidden during calm CIRCLE")
	sh_b.state = Shark.State.CHARGE
	sh_b._state_timer = 5.0
	await physics_frames(2)
	check(sh_b.is_splash_active() and spray_b != null and spray_b.visible,
		"CIRCLE -> CHARGE transition activates SharkSplashSpray automatically")
	sh_b.state = Shark.State.RETREAT
	sh_b._state_timer = 5.0
	await physics_frames(44)
	check(not sh_b.is_splash_active() and (spray_b == null or not spray_b.visible),
		"CHARGE burst finishes ballistic arc and hides cleanly after entering RETREAT")

	# Verify nocturnal _eye_mat moonlight glint/sheen rises cleanly at night!
	Weather.time_of_day = 12.0
	await physics_frames(1)
	var noon_eye_e := Shark._eye_mat.emission_energy_multiplier
	var noon_eye_rim := Shark._eye_mat.rim
	Weather.time_of_day = 0.5
	await physics_frames(1)
	var night_eye_e := Shark._eye_mat.emission_energy_multiplier
	var night_eye_rim := Shark._eye_mat.rim
	check(night_eye_e > noon_eye_e + 0.35 and night_eye_rim > noon_eye_rim + 0.30,
		"Shark _eye_mat boosts subtle nocturnal moonlight sheen at night (e %.2f->%.2f, rim %.2f->%.2f)" % [
			noon_eye_e, night_eye_e, noon_eye_rim, night_eye_rim
		])

	print("    Q13B maritime life: SalvageGlint=%d tris, LidGlint=%d tris, SharkSplashSpray=16x%d tris, eye_night=%.2f->%.2f" % [
		flotsam_glint_tris, lid_glint_tris, droplet_tris, noon_eye_e, night_eye_e
	])

	# 5. Full teardown releases ALL static caches cleanly with 0 ObjectDB leaks!
	await _end()
	check_eq(FlotsamCluster._active_clusters, 0, "FlotsamCluster._active_clusters == 0 after teardown")
	check(FlotsamCluster._glint_mesh == null and FlotsamCluster._glint_mat == null \
			and FlotsamCluster._debris_mesh == null and FlotsamCluster._wood_mat == null \
			and FlotsamCluster._accent_mat == null and FlotsamCluster._fallback_barrel_mesh == null,
		"FlotsamCluster releases all static meshes & materials cleanly (0 leaks)")
	check_eq(SupplyBarrel._active_barrels, 0, "SupplyBarrel._active_barrels == 0 after teardown")
	check(SupplyBarrel._glint_mesh == null and SupplyBarrel._glint_mat == null \
			and SupplyBarrel._emblem_mesh == null and SupplyBarrel._brass_mat == null \
			and SupplyBarrel._wood_mat == null and SupplyBarrel._fallback_barrel_mesh == null \
			and SupplyBarrel._barrel_scene == null,
		"SupplyBarrel releases all static meshes & materials cleanly (0 leaks)")
	check_eq(Shark._active_sharks, 0, "Shark._active_sharks == 0 after teardown")
	check(Shark._mesh_cache.is_empty() and Shark._skin_mat == null and Shark._eye_mat == null \
			and Shark._splash_mesh == null and Shark._splash_mat == null,
		"Shark releases all static meshes, spray MultiMesh asset & materials cleanly (0 leaks)")


func test_q14b_whale_blowhole_spout_and_dolphin_biolum_breach_rings() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Sea.time = 0.0
	Weather.time_of_day = 12.0
	Weather.set_weather(0.0, 12.0, PI * 0.5)  # Steady breeze blowing toward +X

	# 1. Static source guard: Vulkan-safe MultiMesh teardown (never null .mesh on a live MultiMesh).
	var whale_src := FileAccess.get_file_as_string("res://src/world/ocean_whale.gd")
	var pod_src := FileAccess.get_file_as_string("res://src/world/dolphin_pod.gd")
	for src_pair: Array in [[whale_src, "ocean_whale.gd"], [pod_src, "dolphin_pod.gd"]]:
		var txt := String(src_pair[0])
		var fname := String(src_pair[1])
		check(not txt.contains("multimesh.mesh = null") and not txt.contains("mm.mesh = null"),
			"%s follows Godot 4.8 Vulkan rule (never nulls .mesh on a live MultiMesh)" % fname)

	# 2. OceanWhale: sculpted zero-primitive WhaleBlowholeSpout (18x24-tri puffs, 0 VRAM, twin V-plume, wind drift).
	var whale_a := OceanWhale.spawn_breach(_root, Vector3(0.0, 0.0, -40.0), 0.0)
	whale_a.auto_despawn = false
	var whale_b := OceanWhale.spawn_breach(_root, Vector3(45.0, 0.0, -40.0), 0.0)
	whale_b.auto_despawn = false

	var spout_a := whale_a.get_blowhole_spout_node()
	var spout_b := whale_b.get_blowhole_spout_node()
	check(spout_a != null and spout_a.name == "WhaleBlowholeSpout",
		"OceanWhale mounts WhaleBlowholeSpout MultiMeshInstance3D via get_blowhole_spout_node()")
	check(spout_a != null and spout_a.top_level, "WhaleBlowholeSpout uses top_level = true")

	var puff_tris := 0
	var puff_bad_normals := 0
	if spout_a != null:
		check_eq(spout_a.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"WhaleBlowholeSpout disables shadow casting")
		check_near(spout_a.visibility_range_end, 420.0, 0.05,
			"WhaleBlowholeSpout sets visibility_range_end = 420.0 m")
		var smm := spout_a.multimesh
		check(smm != null and smm.instance_count == 18 and smm.use_colors,
			"WhaleBlowholeSpout configures 18 per-instance colored mist puffs")
		check(smm != null and smm.mesh is ArrayMesh and not (smm.mesh is PrimitiveMesh),
			"WhaleBlowholeSpout uses sculpted ArrayMesh (zero raw PrimitiveMesh)")
		if spout_b != null and spout_b.multimesh != null and smm != null:
			check_eq(smm.mesh, spout_b.multimesh.mesh,
				"OceanWhales share statically cached 24-tri blowhole mist-puff ArrayMesh")
		if smm != null and smm.mesh is ArrayMesh:
			var arr := (smm.mesh as ArrayMesh).surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			puff_tris = floori(float(verts.size()) / 3.0)
			for nv in norms:
				if not nv.is_finite() or nv.length_squared() < 0.5:
					puff_bad_normals += 1
		check_eq(puff_tris, 24, "sculpted organic blowhole mist-puff mesh has exact 24 triangles")
		check_eq(puff_bad_normals, 0, "all blowhole mist-puff normals are finite unit vectors")

		var sp_mat := spout_a.material_override as StandardMaterial3D
		check(sp_mat != null and sp_mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
				and sp_mat.vertex_color_use_as_albedo and sp_mat.vertex_color_is_srgb \
				and is_equal_approx(sp_mat.roughness, 0.85),
			"WhaleBlowholeSpout uses translucent sRGB vertex-colored StandardMaterial3D (roughness=0.85)")
		if sp_mat != null:
			check(sp_mat.albedo_texture == null and sp_mat.normal_texture == null and sp_mat.roughness_texture == null,
				"WhaleBlowholeSpout allocates 0 extra VRAM textures")

	# Verify APPROACH activation, upward rise, +X vs -X downwind drift along Weather.wind_vector(),
	# day->night moonlit aqua tint shift, BREACH_RISE full crest, and clean fade by SUBMERGE/DONE!
	whale_a.step_breach(0.20)
	check_eq(whale_a.phase, OceanWhale.Phase.APPROACH, "whale_a is in Phase.APPROACH at 0.20 s")
	check(whale_a.is_blowhole_spout_active() and spout_a != null and spout_a.visible,
		"WhaleBlowholeSpout activates during Phase.APPROACH")
	var pts_app := whale_a.get_spout_puff_positions()
	check_eq(pts_app.size(), 18, "get_spout_puff_positions() returns pre-allocated 18 puff positions")
	var app_max_y := -INF
	var app_min_y := INF
	for p in pts_app:
		app_max_y = maxf(app_max_y, p.y)
		app_min_y = minf(app_min_y, p.y)
	check(app_min_y >= 0.12, "all APPROACH spout puffs stay safely above Sea.height() + 0.12 m (min_y=%.2f)" % app_min_y)

	# Step into Phase.BREACH_RISE (~2.0 s) and measure towering 4.8 m V-plume & +X downwind drift.
	for _s in 9:
		whale_a.step_breach(0.20)
	check_eq(whale_a.phase, OceanWhale.Phase.BREACH_RISE, "whale_a reaches Phase.BREACH_RISE at 2.0 s")
	check(whale_a.is_blowhole_spout_active() and spout_a != null and spout_a.visible,
		"WhaleBlowholeSpout stays active at full height during Phase.BREACH_RISE")
	var bh_origin_pos := spout_a.global_position
	var pts_rise_pos_x := whale_a.get_spout_puff_positions()
	var wind_pos_x := Weather.wind_vector()
	var wind_dir_pos_x := Vector3(wind_pos_x.x, 0.0, wind_pos_x.z).normalized()
	var rise_max_y := -INF
	var mean_pos_x := Vector3.ZERO
	for p in pts_rise_pos_x:
		rise_max_y = maxf(rise_max_y, p.y)
		mean_pos_x += p
	mean_pos_x /= float(pts_rise_pos_x.size())
	var drift_dot_pos := (mean_pos_x - bh_origin_pos).dot(wind_dir_pos_x)
	var crest_height := rise_max_y - bh_origin_pos.y
	check(rise_max_y > app_max_y + 2.5,
		"spout puffs rise dramatically upward from APPROACH to BREACH_RISE (%.2f -> %.2f m)" % [app_max_y, rise_max_y])
	check(crest_height >= 4.2 and crest_height <= 5.0,
		"BREACH_RISE twin V-plume crests near 4.8 m above blowhole (got %.2f m)" % crest_height)
	check(drift_dot_pos > 0.75,
		"spout puffs drift downwind along +X Weather.wind_vector() (dot=%.2f m)" % drift_dot_pos)

	# Flip wind heading to -X and verify puffs immediately drift cleanly toward -X!
	Weather.set_weather(0.0, 12.0, -PI * 0.5)
	whale_a.step_breach(0.05)
	var bh_origin_neg := spout_a.global_position
	var pts_rise_neg_x := whale_a.get_spout_puff_positions()
	var wind_neg_x := Weather.wind_vector()
	var wind_dir_neg_x := Vector3(wind_neg_x.x, 0.0, wind_neg_x.z).normalized()
	var mean_neg_x := Vector3.ZERO
	for p in pts_rise_neg_x:
		mean_neg_x += p
	mean_neg_x /= float(pts_rise_neg_x.size())
	var drift_dot_neg := (mean_neg_x - bh_origin_neg).dot(wind_dir_neg_x)
	check(drift_dot_neg > 0.75 and mean_neg_x.x < bh_origin_neg.x - 0.5,
		"reversing Weather.wind_vector() flips downwind plume drift cleanly to -X (dot=%.2f m)" % drift_dot_neg)

	# Verify day -> night blowhole mist tint shift (sunlit pearl -> moonlit pale-aqua).
	Weather.time_of_day = 12.0
	whale_a.step_breach(0.02)
	var day_tint := whale_a._spout_tint
	var day_spout_emit := OceanWhale._spout_puff_mat.emission_energy_multiplier
	Weather.time_of_day = 0.5
	whale_a.step_breach(0.02)
	var night_tint := whale_a._spout_tint
	var night_spout_emit := OceanWhale._spout_puff_mat.emission_energy_multiplier
	check(night_tint.r < day_tint.r - 0.15 and night_tint.b > night_tint.r + 0.15,
		"blowhole mist shifts from sunlit pearl (%.2f,%.2f,%.2f) to moonlit pale-aqua (%.2f,%.2f,%.2f)" % [
			day_tint.r, day_tint.g, day_tint.b, night_tint.r, night_tint.g, night_tint.b
		])
	check(night_spout_emit > day_spout_emit + 0.15,
		"moonlit spout emission lifts gently at night (%.2f -> %.2f)" % [day_spout_emit, night_spout_emit])

	# Step through APEX_TWIST -> SPLASH_REENTRY -> SUBMERGE -> DONE and verify clean fade-out!
	var saw_submerge_inactive := false
	var saw_done_inactive := false
	for _s in 36:
		whale_a.step_breach(0.20)
		if whale_a.phase == OceanWhale.Phase.SUBMERGE:
			if not whale_a.is_blowhole_spout_active() and not spout_a.visible:
				saw_submerge_inactive = true
		elif whale_a.phase == OceanWhale.Phase.DONE:
			if not whale_a.is_blowhole_spout_active() and not spout_a.visible:
				saw_done_inactive = true
	check(saw_submerge_inactive, "WhaleBlowholeSpout fades cleanly inactive during Phase.SUBMERGE")
	check(saw_done_inactive, "WhaleBlowholeSpout remains inactive and hidden in Phase.DONE")

	# Verify force_breach_apex() activates dramatic mid-plume blowhole silhouette on whale_b!
	Weather.time_of_day = 12.0
	whale_b.force_breach_apex()
	check(whale_b.is_blowhole_spout_active() and spout_b != null and spout_b.visible,
		"force_breach_apex() activates dramatic mid-plume blowhole silhouette")
	var apex_pts := whale_b.get_spout_puff_positions()
	var apex_max_y := -INF
	for p in apex_pts:
		apex_max_y = maxf(apex_max_y, p.y)
	check(apex_max_y > whale_b.global_position.y + 3.0,
		"force_breach_apex() blowhole plume towers above soaring whale (max_y=%.2f vs whale_y=%.2f)" % [
			apex_max_y, whale_b.global_position.y
		])

	# 3. DolphinPod: sculpted zero-primitive DolphinBreachRings (pod_count instances, (0,1,0) normals,
	#    force_leap_phase stamping, live crossing stamping, clean decay to 0, nocturnal biolum tinting).
	var pod_a := DolphinPod.spawn_alongside(_root, null, 3, 24.0)
	var pod_b := DolphinPod.spawn_alongside(_root, null, 2, 24.0)

	var rings_a := pod_a.get_breach_rings_node()
	var rings_b := pod_b.get_breach_rings_node()
	check(rings_a != null and rings_a.name == "DolphinBreachRings",
		"DolphinPod mounts DolphinBreachRings MultiMeshInstance3D via get_breach_rings_node()")
	check(rings_a != null and rings_a.top_level, "DolphinBreachRings uses top_level = true")
	check_eq(pod_a.get_active_ring_count(), 0, "DolphinPod starts with 0 active breach rings")
	check(rings_a != null and not rings_a.visible, "DolphinBreachRings starts hidden when 0 rings active")

	var ring_tris := 0
	var ring_bad_normals := 0
	var ring_non_flat_verts := 0
	if rings_a != null:
		check_eq(rings_a.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"DolphinBreachRings disables shadow casting")
		check_near(rings_a.visibility_range_end, 260.0, 0.05,
			"DolphinBreachRings sets visibility_range_end = 260.0 m")
		var rmm := rings_a.multimesh
		check(rmm != null and rmm.instance_count == 3 and rmm.use_colors,
			"DolphinBreachRings allocates pod_count (3) per-instance colored rings")
		if rings_b != null and rings_b.multimesh != null:
			check_eq(rings_b.multimesh.instance_count, 2,
				"pod_b DolphinBreachRings matches its pod_count (2)")
			if rmm != null:
				check_eq(rmm.mesh, rings_b.multimesh.mesh,
					"DolphinPods share statically cached concentric breach-ring ArrayMesh")
		check(rmm != null and rmm.mesh is ArrayMesh and not (rmm.mesh is PrimitiveMesh),
			"DolphinBreachRings uses sculpted ArrayMesh (zero raw PrimitiveMesh)")
		if rmm != null and rmm.mesh is ArrayMesh:
			var arr := (rmm.mesh as ArrayMesh).surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			ring_tris = floori(float(verts.size()) / 3.0)
			for v in verts:
				if absf(v.y) > 0.0001:
					ring_non_flat_verts += 1
			for nv in norms:
				if not nv.is_finite() or nv.distance_to(Vector3.UP) > 0.001:
					ring_bad_normals += 1
		check(ring_tris >= 120, "sculpted 2-ring concentric ripple mesh has rich geometry (%d tris)" % ring_tris)
		check_eq(ring_non_flat_verts, 0, "all breach-ring vertices lie flat in the horizontal XZ plane")
		check_eq(ring_bad_normals, 0, "all breach-ring normals are exact finite (0, 1, 0) upward unit vectors")

		var r_mat := rings_a.material_override as StandardMaterial3D
		check(r_mat != null and r_mat.vertex_color_use_as_albedo and r_mat.vertex_color_is_srgb \
				and r_mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
				and r_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
				and r_mat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED \
				and r_mat.cull_mode == BaseMaterial3D.CULL_DISABLED,
			"DolphinBreachRings uses unshaded sRGB double-sided translucent depth-draw-disabled StandardMaterial3D")
		if r_mat != null:
			check(r_mat.albedo_texture == null and r_mat.normal_texture == null and r_mat.roughness_texture == null,
				"DolphinBreachRings allocates 0 extra VRAM textures")

	# Verify force_leap_phase(PI * 0.5) immediately stamps glowing rings beneath airborne dolphins!
	pod_a.force_leap_phase(PI * 0.5)
	check(pod_a.get_active_ring_count() >= 2 and rings_a != null and rings_a.visible,
		"force_leap_phase() stamps crisp concentric rings beneath airborne dolphins (active=%d)" % pod_a.get_active_ring_count())

	# Verify normal live breach exit & plunge re-entry crossings stamp rings cleanly on pod_b!
	var saw_live_rings := false
	for _f in 90:
		await physics_frames(1)
		if pod_b.get_active_ring_count() > 0:
			saw_live_rings = true
			break
	check(saw_live_rings and rings_b != null and rings_b.visible,
		"normal dolphin breach/plunge crossings stamp concentric breach rings automatically")

	# Verify rings decay cleanly back to 0 active & hidden MMI over > 1.15 s without new crossings!
	pod_a.force_leap_phase(PI * 0.5)
	check(pod_a.get_active_ring_count() > 0, "pod_a has active rings right before decay check")
	# Put pod_a into its smooth dive-out window (dive_out > 0.35 suppresses new stamps) and step 1.35 s!
	pod_a.age = pod_a.lifetime - 1.5
	for _d in 9:
		pod_a._update_dolphins(0.15, true)
	check_eq(pod_a.get_active_ring_count(), 0,
		"concentric breach rings decay cleanly back to 0 active rings after 1.15 s")
	check(rings_a != null and not rings_a.visible,
		"DolphinBreachRings hides MMI cleanly when 0 rings remain active")

	# Verify nocturnal bioluminescent tint strength rises cleanly from noon -> dusk -> midnight!
	Weather.time_of_day = 12.0
	pod_b._update_dolphins(0.0, false)
	var noon_biolum := pod_b.get_breach_ring_biolum()

	Weather.time_of_day = 18.0
	pod_b._update_dolphins(0.0, false)
	var dusk_biolum := pod_b.get_breach_ring_biolum()

	Weather.time_of_day = 0.5
	pod_b._update_dolphins(0.0, false)
	var midnight_biolum := pod_b.get_breach_ring_biolum()

	check(noon_biolum < 0.05, "noon breach ring bioluminescence stays near 0.0 (got %.3f)" % noon_biolum)
	check(midnight_biolum > 0.95, "midnight breach ring bioluminescence rises to ~1.0 (got %.3f)" % midnight_biolum)
	check(midnight_biolum > dusk_biolum and dusk_biolum > noon_biolum,
		"breach ring bioluminescence orders midnight (%.2f) > dusk (%.2f) > noon (%.2f)" % [
			midnight_biolum, dusk_biolum, noon_biolum
		])

	print("    Q14B open-sea wonder VFX: WhaleBlowholeSpout=18x%d tris (crest=%.2f m, drift=%.2f m), DolphinBreachRings=%d tris (biolum=%.2f->%.2f)" % [
		puff_tris, crest_height, drift_dot_pos, ring_tris, noon_biolum, midnight_biolum
	])

	# 4. Full teardown releases ALL static caches cleanly with 0 ObjectDB leaks!
	await _end()
	check_eq(OceanWhale._active_whales, 0, "OceanWhale._active_whales == 0 after Q14B teardown")
	check(OceanWhale._spout_puff_mesh == null and OceanWhale._spout_puff_mat == null \
			and OceanWhale._body_mesh == null and OceanWhale._whale_mat == null,
		"OceanWhale releases spout & whale static caches cleanly (0 leaks)")
	check_eq(DolphinPod._active_pods, 0, "DolphinPod._active_pods == 0 after Q14B teardown")
	check(DolphinPod._breach_ring_mesh == null and DolphinPod._breach_ring_mat == null \
			and DolphinPod._body_mesh == null and DolphinPod._skin_mat == null,
		"DolphinPod releases breach-ring & dolphin static caches cleanly (0 leaks)")


func test_q16b_sea_mermaid_ripples_conch_halo_and_manta_wingtip_bubbles() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Sea.time = 0.0
	Weather.time_of_day = 12.0
	Weather.set_weather(0.0, 8.0, 0.0)

	# 1. Static source guards: zero raw PrimitiveMesh allocations & Vulkan-safe MultiMesh teardown.
	var mermaid_src := FileAccess.get_file_as_string("res://src/world/sea_mermaid.gd")
	var manta_src := FileAccess.get_file_as_string("res://src/world/manta_ray.gd")
	for bad_prim: String in [
		"BoxMesh.new", "SphereMesh.new", "CylinderMesh.new",
		"QuadMesh.new", "CapsuleMesh.new", "PrismMesh.new",
	]:
		check(not mermaid_src.contains(bad_prim), "sea_mermaid.gd contains zero %s calls" % bad_prim)
		check(not manta_src.contains(bad_prim), "manta_ray.gd contains zero %s calls" % bad_prim)
	check(not manta_src.contains("multimesh.mesh = null") and not manta_src.contains("mm.mesh = null"),
		"manta_ray.gd follows Godot 4.8 Vulkan rule (never nulls .mesh on a live MultiMesh)")

	# 2. SeaMermaid: MermaidRippleHalo (176 tris) + ConchOrbHalo (48 tris), weather boost & dismiss fade!
	var m_a := SeaMermaid.spawn_at(_root, Vector3(44.0, 0.0, -32.0))
	var m_b := SeaMermaid.spawn_at(_root, Vector3(-44.0, 0.0, -32.0))
	m_a.force_emerged()
	m_b.force_emerged()

	var ripple_a := m_a.get_ripple_halo_node()
	var ripple_b := m_b.get_ripple_halo_node()
	var conch_a := m_a.get_conch_halo_node()
	var conch_b := m_b.get_conch_halo_node()

	check(ripple_a != null and ripple_a.name == "MermaidRippleHalo",
		"SeaMermaid mounts MermaidRippleHalo via get_ripple_halo_node()")
	check(conch_a != null and conch_a.name == "ConchOrbHalo",
		"SeaMermaid mounts ConchOrbHalo via get_conch_halo_node()")

	var ripple_tris := 0
	var ripple_bad_normals := 0
	var ripple_non_flat := 0
	if ripple_a != null:
		check_eq(ripple_a.get_parent(), m_a, "MermaidRippleHalo mounts directly under SeaMermaid")
		check(ripple_a.position.distance_to(Vector3(0.0, 0.06, 0.0)) < 0.001,
			"MermaidRippleHalo mounts at waterline (0.0, 0.06, 0.0)")
		check_eq(ripple_a.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"MermaidRippleHalo disables shadow casting")
		check_eq(ripple_a.gi_mode, GeometryInstance3D.GI_MODE_DISABLED,
			"MermaidRippleHalo disables GI mode")
		check_near(ripple_a.visibility_range_end, 260.0, 0.05,
			"MermaidRippleHalo sets visibility_range_end = 260.0 m")
		check(ripple_a.mesh is ArrayMesh and not (ripple_a.mesh is PrimitiveMesh),
			"MermaidRippleHalo uses sculpted ArrayMesh (zero PrimitiveMesh)")
		if ripple_b != null:
			check_eq(ripple_a.mesh, ripple_b.mesh, "SeaMermaids share statically cached _ripple_mesh")
			check(ripple_a.material_override != ripple_b.material_override,
				"MermaidRippleHalo uses per-instance StandardMaterial3D")
		if ripple_a.mesh is ArrayMesh:
			var arr := (ripple_a.mesh as ArrayMesh).surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			ripple_tris = floori(float(verts.size()) / 3.0)
			for v in verts:
				if absf(v.y) > 0.0001:
					ripple_non_flat += 1
			for nv in norms:
				if not nv.is_finite() or nv.distance_to(Vector3.UP) > 0.001:
					ripple_bad_normals += 1
		check_eq(ripple_tris, 176, "MermaidRippleHalo has exact 176 triangles (22 segs x 2 rings)")
		check_eq(ripple_non_flat, 0, "MermaidRippleHalo vertices lie flat on y = 0.0")
		check_eq(ripple_bad_normals, 0, "MermaidRippleHalo normals are all finite (0, 1, 0) unit vectors")

		var r_mat := ripple_a.material_override as StandardMaterial3D
		check(r_mat != null and r_mat.vertex_color_use_as_albedo and r_mat.vertex_color_is_srgb \
				and r_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
				and r_mat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD \
				and r_mat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED \
				and r_mat.cull_mode == BaseMaterial3D.CULL_DISABLED,
			"MermaidRippleHalo uses unshaded additive sRGB double-sided depth-draw-disabled material")
		if r_mat != null:
			check(r_mat.albedo_texture == null and r_mat.normal_texture == null and r_mat.roughness_texture == null,
				"MermaidRippleHalo allocates 0 extra VRAM textures")

	var conch_tris := 0
	var conch_bad_normals := 0
	var conch_has_core := false
	var conch_has_black_rim := false
	if conch_a != null:
		check_eq(conch_a.get_parent(), m_a.get_figure_mesh_instance().get_parent(),
			"ConchOrbHalo mounts inside FigurePivot alongside MerfolkFigure")
		check(conch_a.position.distance_to(SeaMermaid.CONCH_ORB_LOCAL) < 0.001,
			"ConchOrbHalo mounts directly at CONCH_ORB_LOCAL")
		check_eq(conch_a.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"ConchOrbHalo disables shadow casting")
		check_eq(conch_a.gi_mode, GeometryInstance3D.GI_MODE_DISABLED,
			"ConchOrbHalo disables GI mode")
		check_near(conch_a.visibility_range_end, 420.0, 0.05,
			"ConchOrbHalo sets visibility_range_end = 420.0 m")
		check(conch_a.mesh is ArrayMesh and not (conch_a.mesh is PrimitiveMesh),
			"ConchOrbHalo uses sculpted ArrayMesh (zero PrimitiveMesh)")
		if conch_b != null:
			check_eq(conch_a.mesh, conch_b.mesh, "SeaMermaids share statically cached _conch_halo_mesh")
			check(conch_a.material_override != conch_b.material_override,
				"ConchOrbHalo uses per-instance StandardMaterial3D")
		if conch_a.mesh is ArrayMesh:
			var arr := (conch_a.mesh as ArrayMesh).surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			conch_tris = floori(float(verts.size()) / 3.0)
			for nv in norms:
				if not nv.is_finite() or nv.distance_to(Vector3(0.0, 0.0, 1.0)) > 0.001:
					conch_bad_normals += 1
			for cv in cols:
				if cv.r <= 0.001 and cv.g <= 0.001 and cv.b <= 0.001 and cv.a >= 0.99:
					conch_has_black_rim = true
				if cv.r >= 0.75 and cv.g >= 0.95 and cv.b >= 0.90:
					conch_has_core = true
		check_eq(conch_tris, 48, "ConchOrbHalo has exact 48 triangles (16 radial wedges)")
		check_eq(conch_bad_normals, 0, "ConchOrbHalo normals are all finite (0, 0, 1) unit vectors")
		check(conch_has_core and conch_has_black_rim,
			"ConchOrbHalo fades from aquamarine-white core to pure Color(0, 0, 0, 1) rim")

		var c_mat := conch_a.material_override as StandardMaterial3D
		check(c_mat != null and c_mat.vertex_color_use_as_albedo and c_mat.vertex_color_is_srgb \
				and c_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
				and c_mat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD \
				and c_mat.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED \
				and c_mat.billboard_keep_scale \
				and c_mat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED \
				and c_mat.cull_mode == BaseMaterial3D.CULL_DISABLED,
			"ConchOrbHalo uses unshaded additive scale-preserving billboard StandardMaterial3D")
		if c_mat != null:
			check(c_mat.albedo_texture == null and c_mat.normal_texture == null and c_mat.roughness_texture == null,
				"ConchOrbHalo allocates 0 extra VRAM textures")

	# Verify daylight -> night -> storm energy boost on both halos!
	Weather.time_of_day = 12.0
	Weather.set_weather(0.0, 8.0, 0.0)
	m_a.step_mermaid(0.0)
	var noon_ripple_e := m_a.get_ripple_halo_energy()
	var noon_conch_e := m_a.get_conch_halo_energy()

	Weather.time_of_day = 0.5
	Weather.set_weather(0.0, 8.0, 0.0)
	m_a.step_mermaid(0.0)
	var night_ripple_e := m_a.get_ripple_halo_energy()
	var night_conch_e := m_a.get_conch_halo_energy()

	Weather.time_of_day = 0.5
	Weather.set_weather(1.0, 16.0, 0.0)
	m_a.step_mermaid(0.0)
	var storm_ripple_e := m_a.get_ripple_halo_energy()
	var storm_conch_e := m_a.get_conch_halo_energy()

	check(noon_ripple_e >= 0.30 and noon_ripple_e <= 0.45,
		"MermaidRippleHalo stays subtle in bright midday (~0.38, got %.3f)" % noon_ripple_e)
	check(night_ripple_e > noon_ripple_e * 2.0 and night_ripple_e >= 0.80,
		"MermaidRippleHalo rises dramatically at night (noon=%.3f -> night=%.3f)" % [noon_ripple_e, night_ripple_e])
	check(storm_ripple_e > night_ripple_e,
		"MermaidRippleHalo intensifies further in storm (night=%.3f -> storm=%.3f)" % [night_ripple_e, storm_ripple_e])

	check(noon_conch_e >= 0.42 and noon_conch_e <= 0.65,
		"ConchOrbHalo glows crisply at midday (~0.52, got %.3f)" % noon_conch_e)
	check(night_conch_e > noon_conch_e * 2.0 and night_conch_e >= 1.05,
		"ConchOrbHalo blooms radiantly at night (noon=%.3f -> night=%.3f)" % [noon_conch_e, night_conch_e])
	check(storm_conch_e > night_conch_e,
		"ConchOrbHalo intensifies further in storm (night=%.3f -> storm=%.3f)" % [night_conch_e, storm_conch_e])

	# Verify concentric ripple pulsing expansion (0.88..1.34) & slow rotation across 5 s (also triggers foam interval).
	var min_rip_s := INF
	var max_rip_s := -INF
	var rot0 := ripple_a.rotation.y if ripple_a != null else 0.0
	for _s in 20:
		m_a.step_mermaid(0.25)
		if ripple_a != null:
			min_rip_s = minf(min_rip_s, ripple_a.scale.x)
			max_rip_s = maxf(max_rip_s, ripple_a.scale.x)
	var rot1 := ripple_a.rotation.y if ripple_a != null else 0.0
	check(min_rip_s >= 0.87 and max_rip_s <= 1.35 and (max_rip_s - min_rip_s) > 0.35,
		"MermaidRippleHalo pulses smoothly across 0.88..1.34 scale (min=%.3f, max=%.3f)" % [min_rip_s, max_rip_s])
	check(rot1 > rot0 + 0.5, "MermaidRippleHalo rotates gently around Y (%.2f -> %.2f rad)" % [rot0, rot1])

	# Verify clean fade & hide on dismiss() when submerged (emerge <= 0.04).
	var pre_dismiss_ripple_e := m_a.get_ripple_halo_energy()
	var pre_dismiss_conch_e := m_a.get_conch_halo_energy()
	m_a.dismiss()
	m_a.step_mermaid(0.45)  # partway submerged
	check(m_a.get_ripple_halo_energy() < pre_dismiss_ripple_e * 0.75,
		"MermaidRippleHalo fades smoothly while submerging after dismiss()")
	check(m_a.get_conch_halo_energy() < pre_dismiss_conch_e * 0.75,
		"ConchOrbHalo fades smoothly while submerging after dismiss()")
	# Step just past emerge <= 0.04 (rise_offset ~ -2.35, before queue_free at -2.78).
	m_a.step_mermaid(0.55)
	check(is_instance_valid(m_a), "dismissed mermaid still valid at emerge <= 0.04 check")
	check_near(m_a.get_ripple_halo_energy(), 0.0, 0.0001,
		"MermaidRippleHalo energy fades to 0.0 when dismissed & submerged")
	check_near(m_a.get_conch_halo_energy(), 0.0, 0.0001,
		"ConchOrbHalo energy fades to 0.0 when dismissed & submerged")
	check(ripple_a != null and not ripple_a.visible, "MermaidRippleHalo hides when dismissed & submerged")
	check(conch_a != null and not conch_a.visible, "ConchOrbHalo hides when dismissed & submerged")

	# 3. MantaRay: sculpted 12x12-tri WingtipBubbles, prime-frame trails, upward drift, surface clamp!
	var manta_a := MantaRay.new()
	manta_a.name = "MantaQ16B_A"
	manta_a.position = Vector3(0.0, -3.2, 0.0)
	_root.add_child(manta_a)

	var manta_b := MantaRay.new()
	manta_b.name = "MantaQ16B_B"
	manta_b.position = Vector3(28.0, -1.6, 0.0)  # shallow lagoon placement to stress surface clamp
	_root.add_child(manta_b)

	check_eq(manta_a.get_mesh_instances().size(), 3,
		"MantaRay.get_mesh_instances() stays strictly 3 (WingtipBubbles excluded)")

	var bub_a := manta_a.get_wingtip_bubbles_node()
	var bub_b := manta_b.get_wingtip_bubbles_node()
	check(bub_a != null and bub_a.name == "WingtipBubbles",
		"MantaRay mounts WingtipBubbles MultiMeshInstance3D via get_wingtip_bubbles_node()")
	if bub_a != null:
		check_eq(bub_a.get_parent(), manta_a,
			"WingtipBubbles mounts directly under MantaRay (not inside GlideRoot)")
		check_eq(bub_a.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"WingtipBubbles disables shadow casting")
		check_eq(bub_a.gi_mode, GeometryInstance3D.GI_MODE_DISABLED,
			"WingtipBubbles disables GI mode")
		check_near(bub_a.visibility_range_end, MantaRay.VISIBILITY_END, 0.05,
			"WingtipBubbles uses VISIBILITY_END")
		check_near(bub_a.visibility_range_end_margin, MantaRay.VISIBILITY_MARGIN, 0.05,
			"WingtipBubbles uses VISIBILITY_MARGIN")

		var mm_a := bub_a.multimesh
		check(mm_a != null and mm_a.instance_count == 12 and mm_a.use_colors,
			"WingtipBubbles configures 12 per-instance colored micro-bubbles (6 port + 6 starboard)")
		check(mm_a != null and mm_a.mesh is ArrayMesh and not (mm_a.mesh is PrimitiveMesh),
			"WingtipBubbles uses sculpted ArrayMesh (zero SphereMesh)")
		if bub_b != null and bub_b.multimesh != null and mm_a != null:
			check_eq(mm_a.mesh, bub_b.multimesh.mesh,
				"MantaRays share statically cached 12-tri micro-bubble ArrayMesh")

		var bubble_tris := 0
		var bubble_bad_normals := 0
		if mm_a != null and mm_a.mesh is ArrayMesh:
			var arr := (mm_a.mesh as ArrayMesh).surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			bubble_tris = floori(float(verts.size()) / 3.0)
			for nv in norms:
				if not nv.is_finite() or nv.length_squared() < 0.5:
					bubble_bad_normals += 1
		check_eq(bubble_tris, 12, "sculpted 6-sided bipyramid bubble mesh has exact 12 triangles")
		check_eq(bubble_bad_normals, 0, "all wingtip bubble mesh normals are finite unit vectors")

		var b_mat := bub_a.material_override as StandardMaterial3D
		check(b_mat != null and b_mat.vertex_color_use_as_albedo and b_mat.vertex_color_is_srgb \
				and b_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
				and b_mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
				and b_mat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED,
			"WingtipBubbles uses unshaded translucent sRGB depth-draw-disabled StandardMaterial3D")
		if b_mat != null:
			check(b_mat.albedo_texture == null and b_mat.normal_texture == null and b_mat.roughness_texture == null,
				"WingtipBubbles allocates 0 extra VRAM textures")

	# Verify prime-frame initialization places 12 distinct bubbles along both wingtip trails & strictly submerged.
	var bp0 := manta_a.get_wingtip_bubble_positions()
	check_eq(bp0.size(), 12, "get_wingtip_bubble_positions() returns all 12 wingtip bubbles")
	var port_stbd_sep := bp0[0].distance_to(bp0[6])
	check(port_stbd_sep > 3.2 and port_stbd_sep < 5.0,
		"port and starboard wingtip bubble trails span ~4.1 m across wingtips (sep=%.2f m)" % port_stbd_sep)

	# Step 0.20 s and verify bubbles drift cleanly upward!
	manta_a.step_glide(0.20)
	var bp1 := manta_a.get_wingtip_bubble_positions()
	var rose_n := 0
	for i in 12:
		if bp1[i].y > bp0[i].y + 0.05:
			rose_n += 1
	check(rose_n >= 9, "step_glide(0.20) drifts wingtip bubbles upward (rose=%d / 12)" % rose_n)

	# Step 24 frames (3.6 s > max 2.4 s cycle) on both mantas and verify strict submersion & cycle wrap!
	var max_world_y_a := -INF
	var max_world_y_b := -INF
	var saw_wrap := false
	var prev_y_a := PackedFloat32Array()
	prev_y_a.resize(12)
	for i in 12:
		prev_y_a[i] = bp1[i].y
	for _step in 24:
		manta_a.step_glide(0.15)
		manta_b.step_glide(0.15)
		var pa := manta_a.get_wingtip_bubble_positions()
		var pb := manta_b.get_wingtip_bubble_positions()
		for i in 12:
			var wy_a := manta_a.global_position.y + pa[i].y
			var wy_b := manta_b.global_position.y + pb[i].y
			max_world_y_a = maxf(max_world_y_a, wy_a)
			max_world_y_b = maxf(max_world_y_b, wy_b)
			if pa[i].y < prev_y_a[i] - 0.35:
				saw_wrap = true
			prev_y_a[i] = pa[i].y

	check(saw_wrap, "wingtip bubbles continuously wrap and re-seed at moving wingtips")
	check(max_world_y_a <= -0.15 and max_world_y_a <= MantaRay.MAX_MANTA_Y + 0.901,
		"MantaA wingtip bubbles stay strictly submerged below ocean surface (max_y=%.3f)" % max_world_y_a)
	check(max_world_y_b <= -0.15 and max_world_y_b <= MantaRay.MAX_MANTA_Y + 0.901,
		"shallow MantaB wingtip bubbles stay strictly clamped below ocean surface (max_y=%.3f)" % max_world_y_b)

	print("    Q16B marine sanctuary: MermaidRippleHalo=%d tris (%.2f->%.2f->%.2f), ConchOrbHalo=%d tris (%.2f->%.2f->%.2f), WingtipBubbles=12x12 tris (max_y=%.2f/%.2f)" % [
		ripple_tris, noon_ripple_e, night_ripple_e, storm_ripple_e,
		conch_tris, noon_conch_e, night_conch_e, storm_conch_e,
		max_world_y_a, max_world_y_b,
	])

	# 4. Full zero-leak teardown releases ALL static caches cleanly to null!
	await _end()
	check_eq(SeaMermaid._active_mermaids, 0, "SeaMermaid._active_mermaids == 0 after Q16B teardown")
	check(SeaMermaid._figure_mesh == null and SeaMermaid._smoke_mesh == null \
			and SeaMermaid._mote_mesh == null and SeaMermaid._ripple_mesh == null \
			and SeaMermaid._conch_halo_mesh == null and SeaMermaid._body_mat == null \
			and SeaMermaid._glow_mat == null and SeaMermaid._smoke_mat == null,
		"SeaMermaid releases all static meshes including _ripple_mesh & _conch_halo_mesh (0 leaks)")
	check_eq(MantaRay._active_mantas, 0, "MantaRay._active_mantas == 0 after Q16B teardown")
	check(MantaRay._body_mesh == null and MantaRay._wing_left_mesh == null \
			and MantaRay._wing_right_mesh == null and MantaRay._manta_mat == null \
			and MantaRay._bubble_mesh == null and MantaRay._bubble_mat == null,
		"MantaRay releases all static meshes & materials including _bubble_mesh & _bubble_mat (0 leaks)")


func test_q17a_megalodon_and_leviathan_boss_halos_spray_and_vortex_motes() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Sea.time = 0.0
	Weather.time_of_day = 12.0
	Weather.set_weather(0.0, 8.0, 0.0)

	# 1. Static source guards: zero raw PrimitiveMesh allocations on megalodon.gd & Vulkan-safe teardown on both!
	var mega_src := FileAccess.get_file_as_string("res://src/combat/megalodon.gd")
	var lev_src := FileAccess.get_file_as_string("res://src/combat/leviathan.gd")
	for bad_prim: String in [
		"BoxMesh.new", "SphereMesh.new", "CylinderMesh.new",
		"QuadMesh.new", "CapsuleMesh.new", "PrismMesh.new",
	]:
		check(not mega_src.contains(bad_prim), "megalodon.gd contains zero %s calls" % bad_prim)
	for src_pair: Array in [[mega_src, "megalodon.gd"], [lev_src, "leviathan.gd"]]:
		var txt := String(src_pair[0])
		var fname := String(src_pair[1])
		check(not txt.contains("multimesh.mesh = null") and not txt.contains("mm.mesh = null"),
			"%s follows Godot 4.8 Vulkan rule (never nulls .mesh on a live MultiMesh)" % fname)
	check(not mega_src.contains("drops.mesh = null"),
		"megalodon.gd follows Godot 4.8 Vulkan rule (never nulls .mesh on a live CPUParticles3D)")

	# 2. AncientMegalodon: 2x48-tri PredatorEyeHalos & 20x12-tri DorsalWakeSpray!
	var dummy_ship := Node3D.new()
	dummy_ship.name = "Q17ADummyShip"
	_root.add_child(dummy_ship)
	dummy_ship.global_position = Vector3.ZERO

	var mega_a := AncientMegalodon.spawn_near_ship(_root, dummy_ship, Vector3(40.0, 0.0, -35.0))
	var mega_b := AncientMegalodon.spawn_near_ship(_root, null, Vector3(-40.0, 0.0, -35.0))
	mega_a.enable_effects = false
	mega_b.enable_effects = false
	mega_a.set_physics_process(false)
	mega_b.set_physics_process(false)

	var m_halos_a := mega_a.get_predator_eye_halos()
	var m_halos_b := mega_b.get_predator_eye_halos()
	check_eq(m_halos_a.size(), 2, "AncientMegalodon mounts 2 PredatorEyeHalos via get_predator_eye_halos()")
	check_eq(m_halos_b.size(), 2, "second AncientMegalodon mounts 2 PredatorEyeHalos")

	var mega_halo_tris := 0
	var mega_halo_bad_normals := 0
	var mega_halo_has_core := false
	var mega_halo_has_black_rim := false
	if m_halos_a.size() == 2 and m_halos_b.size() == 2:
		var hl := m_halos_a[0]
		var hr := m_halos_a[1]
		check_eq(hl.name, "PredatorEyeHaloL", "left Megalodon halo named PredatorEyeHaloL")
		check_eq(hr.name, "PredatorEyeHaloR", "right Megalodon halo named PredatorEyeHaloR")
		check_eq(hl.get_parent(), mega_a._visual_root, "PredatorEyeHaloL mounts inside _visual_root")
		check_eq(hr.get_parent(), mega_a._visual_root, "PredatorEyeHaloR mounts inside _visual_root")
		check(hl.position.x < -1.4 and hr.position.x > 1.4 and is_equal_approx(hl.position.x, -hr.position.x),
			"PredatorEyeHalos mount symmetrically over sculpted left/right eyes (+/- X)")
		check(hl.position.distance_to(AncientMegalodon.EYE_HALO_POS_L) < 0.001,
			"PredatorEyeHaloL matches sculpted left eye offset")
		check(hr.position.distance_to(AncientMegalodon.EYE_HALO_POS_R) < 0.001,
			"PredatorEyeHaloR matches sculpted right eye offset")
		check_eq(hl.mesh, hr.mesh, "left and right PredatorEyeHalos share static _eye_halo_mesh")
		check_eq(hl.mesh, m_halos_b[0].mesh, "AncientMegalodons share statically cached _eye_halo_mesh")
		check_eq(hl.material_override, hr.material_override,
			"left and right PredatorEyeHalos share per-instance material")
		check(hl.material_override != m_halos_b[0].material_override,
			"distinct AncientMegalodons use isolated per-instance halo materials")
		for hmi: MeshInstance3D in m_halos_a:
			check_eq(hmi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"%s disables shadow casting" % hmi.name)
			check_eq(hmi.gi_mode, GeometryInstance3D.GI_MODE_DISABLED,
				"%s disables GI mode" % hmi.name)
			check_near(hmi.visibility_range_end, 260.0, 0.05,
				"%s sets visibility_range_end = 260.0 m" % hmi.name)
			check(hmi.mesh is ArrayMesh and not (hmi.mesh is PrimitiveMesh),
				"%s uses sculpted ArrayMesh (zero PrimitiveMesh)" % hmi.name)

		if hl.mesh is ArrayMesh:
			var arr := (hl.mesh as ArrayMesh).surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			mega_halo_tris = floori(float(verts.size()) / 3.0)
			for nv in norms:
				if not nv.is_finite() or nv.distance_to(Vector3(0.0, 0.0, 1.0)) > 0.001:
					mega_halo_bad_normals += 1
			for cv in cols:
				if cv.r <= 0.001 and cv.g <= 0.001 and cv.b <= 0.001 and cv.a >= 0.99:
					mega_halo_has_black_rim = true
				if cv.r >= 0.95 and cv.g >= 0.90 and cv.b >= 0.50:
					mega_halo_has_core = true
		check_eq(mega_halo_tris, 48, "PredatorEyeHalo mesh has exact 48 triangles (16 radial wedges)")
		check_eq(mega_halo_bad_normals, 0, "PredatorEyeHalo normals are all finite (0, 0, 1) unit vectors")
		check(mega_halo_has_core and mega_halo_has_black_rim,
			"PredatorEyeHalo fades from incandescent gold-white core to pure Color(0, 0, 0, 1) rim")

		var mh_mat := hl.material_override as StandardMaterial3D
		check(mh_mat != null and mh_mat.vertex_color_use_as_albedo and mh_mat.vertex_color_is_srgb \
				and mh_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
				and mh_mat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD \
				and mh_mat.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED \
				and mh_mat.billboard_keep_scale \
				and mh_mat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED \
				and mh_mat.cull_mode == BaseMaterial3D.CULL_DISABLED,
			"PredatorEyeHalos use unshaded additive scale-preserving billboard sRGB StandardMaterial3D")
		if mh_mat != null:
			check(mh_mat.albedo_texture == null and mh_mat.normal_texture == null and mh_mat.roughness_texture == null,
				"PredatorEyeHalos allocate 0 extra VRAM textures")

	# Verify Megalodon calm midday -> night -> WINDUP -> CHARGE & showcase eye halo escalation!
	mega_a.state = AncientMegalodon.State.CIRCLE
	mega_a._state_timer = 10.0
	mega_a._hit_flash = 0.0
	Weather.time_of_day = 12.0
	Weather.set_weather(0.0, 8.0, 0.0)
	mega_a.step_ai(0.0)
	var m_noon_e := mega_a.get_eye_halo_energy()
	var m_noon_s := m_halos_a[0].scale.x if m_halos_a.size() > 0 else 0.0

	Weather.time_of_day = 0.5
	mega_a.step_ai(0.0)
	var m_night_e := mega_a.get_eye_halo_energy()
	var m_night_s := m_halos_a[0].scale.x if m_halos_a.size() > 0 else 0.0

	Weather.time_of_day = 12.0
	mega_a.state = AncientMegalodon.State.WINDUP
	mega_a._state_timer = AncientMegalodon.CHARGE_WINDUP * 0.35
	mega_a.step_ai(0.0)
	var m_windup_e := mega_a.get_eye_halo_energy()
	var m_windup_s := m_halos_a[0].scale.x if m_halos_a.size() > 0 else 0.0

	mega_a.state = AncientMegalodon.State.CHARGE
	mega_a._state_timer = AncientMegalodon.CHARGE_TIMEOUT
	mega_a.step_ai(0.0)
	var m_charge_e := mega_a.get_eye_halo_energy()
	var m_charge_s := m_halos_a[0].scale.x if m_halos_a.size() > 0 else 0.0

	check(m_noon_e >= 0.30 and m_noon_e <= 0.45 and m_noon_s >= 0.38 and m_noon_s <= 0.46,
		"Megalodon midday calm halo stays subtle amber (e=%.3f, s=%.2f m)" % [m_noon_e, m_noon_s])
	check(m_night_e > m_noon_e * 1.9 and m_night_e >= 0.78 and m_night_s >= 0.54,
		"Megalodon night circling halo blazes eerie amber (e=%.3f, s=%.2f m)" % [m_night_e, m_night_s])
	check(m_windup_e > m_night_e and m_windup_s > m_night_s,
		"Megalodon WINDUP halo intensifies beyond night circling (e=%.3f, s=%.2f m)" % [m_windup_e, m_windup_s])
	check(m_charge_e > m_windup_e and m_charge_e >= 1.32 and m_charge_s >= 0.72,
		"Megalodon CHARGE halo surges fiercely molten (e=%.3f, s=%.2f m)" % [m_charge_e, m_charge_s])

	# Verify DorsalWakeSpray MultiMesh (20x12-tri sculpted droplets, 0 primitives, 0 VRAM textures).
	var spray_a := mega_a.get_dorsal_wake_spray_node()
	var spray_b := mega_b.get_dorsal_wake_spray_node()
	check(spray_a != null and spray_a.name == "DorsalWakeSpray",
		"AncientMegalodon mounts DorsalWakeSpray MultiMeshInstance3D via get_dorsal_wake_spray_node()")

	var mega_drop_tris := 0
	var mega_drop_bad_normals := 0
	if spray_a != null:
		check_eq(spray_a.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"DorsalWakeSpray disables shadow casting")
		check_eq(spray_a.gi_mode, GeometryInstance3D.GI_MODE_DISABLED,
			"DorsalWakeSpray disables GI mode")
		check_near(spray_a.visibility_range_end, 220.0, 0.05,
			"DorsalWakeSpray sets visibility_range_end = 220.0 m")
		var dmm := spray_a.multimesh
		check(dmm != null and dmm.instance_count == 20 and dmm.use_colors,
			"DorsalWakeSpray configures 20 per-instance colored droplets")
		check(dmm != null and dmm.mesh is ArrayMesh and not (dmm.mesh is PrimitiveMesh),
			"DorsalWakeSpray uses sculpted ArrayMesh (zero PrimitiveMesh)")
		if spray_b != null and spray_b.multimesh != null and dmm != null:
			check_eq(dmm.mesh, spray_b.multimesh.mesh,
				"AncientMegalodons share statically cached 12-tri _wake_spray_mesh")
		if dmm != null and dmm.mesh is ArrayMesh:
			var arr := (dmm.mesh as ArrayMesh).surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			mega_drop_tris = floori(float(verts.size()) / 3.0)
			for nv in norms:
				if not nv.is_finite() or nv.length_squared() < 0.5:
					mega_drop_bad_normals += 1
		check_eq(mega_drop_tris, 12, "sculpted DorsalWakeSpray droplet mesh has exact 12 triangles")
		check_eq(mega_drop_bad_normals, 0, "all DorsalWakeSpray droplet normals are finite unit vectors")

		var ds_mat := spray_a.material_override as StandardMaterial3D
		check(ds_mat != null and ds_mat.vertex_color_use_as_albedo and ds_mat.vertex_color_is_srgb \
				and ds_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
				and ds_mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
				and ds_mat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED,
			"DorsalWakeSpray uses unshaded translucent sRGB depth-draw-disabled StandardMaterial3D")
		if ds_mat != null:
			check(ds_mat.albedo_texture == null and ds_mat.normal_texture == null and ds_mat.roughness_texture == null,
				"DorsalWakeSpray allocates 0 extra VRAM textures")

	# Verify DorsalWakeSpray ballistic advancement in CIRCLE & ~2.2x height/width surge in CHARGE!
	mega_a.state = AncientMegalodon.State.CIRCLE
	mega_a._state_timer = 10.0
	mega_a.step_ai(0.0)
	check(spray_a != null and spray_a.visible, "DorsalWakeSpray is active and visible while circling")
	var sp_circle_0 := mega_a.get_dorsal_spray_positions()
	check_eq(sp_circle_0.size(), 20, "get_dorsal_spray_positions() returns all 20 droplet positions")

	mega_a.step_ai(0.12)
	var sp_circle_1 := mega_a.get_dorsal_spray_positions()
	var sp_moved := 0
	var circle_max_y := -INF
	var circle_max_x := 0.0
	for i in 20:
		if sp_circle_1[i].distance_to(sp_circle_0[i]) > 0.15:
			sp_moved += 1
		circle_max_y = maxf(circle_max_y, sp_circle_1[i].y)
		circle_max_x = maxf(circle_max_x, absf(sp_circle_1[i].x))
	check_eq(sp_moved, 20, "all 20 DorsalWakeSpray droplets advance along ballistic arcs on step_ai(0.12)")

	# Switch to CHARGE on identical droplet ages and verify ~2.2x taller & wider parabolic spray surge!
	mega_a.state = AncientMegalodon.State.CHARGE
	mega_a._state_timer = AncientMegalodon.CHARGE_TIMEOUT
	mega_a.step_ai(0.0)
	var sp_charge := mega_a.get_dorsal_spray_positions()
	var charge_max_y := -INF
	var charge_max_x := 0.0
	for p in sp_charge:
		charge_max_y = maxf(charge_max_y, p.y)
		charge_max_x = maxf(charge_max_x, absf(p.x))
	check(charge_max_y > circle_max_y + 0.55 and charge_max_x > circle_max_x * 1.55,
		"DorsalWakeSpray surges taller & wider on CHARGE (y %.2f->%.2f, |x| %.2f->%.2f)" % [
			circle_max_y, charge_max_y, circle_max_x, charge_max_x
		])

	# Verify force_pose_for_showcase() primes blazing eyes & dramatic active 20-droplet dorsal spray!
	mega_b.force_pose_for_showcase(0.85, 1.0)
	check(mega_b.get_eye_halo_energy() >= 1.35,
		"force_pose_for_showcase() surges PredatorEyeHalos fiercely (e=%.3f)" % mega_b.get_eye_halo_energy())
	check(spray_b != null and spray_b.visible,
		"force_pose_for_showcase() activates DorsalWakeSpray immediately")
	var sp_show := mega_b.get_dorsal_spray_positions()
	var show_max_y := -INF
	for p in sp_show:
		show_max_y = maxf(show_max_y, p.y)
	check(show_max_y > 2.5, "showcase DorsalWakeSpray arcs high above dorsal base (max_y=%.2f m)" % show_max_y)

	# Verify DEFEATED hides DorsalWakeSpray and smoothly fades PredatorEyeHalos to 0.0 / hidden!
	mega_a.dead = true
	mega_a.state = AncientMegalodon.State.DEFEATED
	mega_a.sink_and_free()
	mega_a.step_ai(0.6)
	check(spray_a != null and not spray_a.visible, "DorsalWakeSpray hides cleanly when Megalodon is DEFEATED")
	var m_defeat_mid_e := mega_a.get_eye_halo_energy()
	check(m_defeat_mid_e < m_charge_e * 0.65,
		"PredatorEyeHalos fade smoothly while sinking (mid_e=%.3f)" % m_defeat_mid_e)
	mega_a.step_ai(2.2)  # past 0.65 * SINK_DURATION (~2.47 s) but before 3.8 s queue_free
	check(is_instance_valid(mega_a), "sinking Megalodon still valid right after eye halo fade-out")
	check_near(mega_a.get_eye_halo_energy(), 0.0, 0.0001,
		"PredatorEyeHalos reach 0.0 energy once defeated Megalodon submerges")
	check(m_halos_a.size() == 2 and not m_halos_a[0].visible and not m_halos_a[1].visible,
		"PredatorEyeHalos hide cleanly once defeated Megalodon submerges")

	# 3. Leviathan: 2x48-tri AbyssalEyeHalos & 24x8-tri spiraling VortexBiolumMotes!
	Weather.time_of_day = 12.0
	Weather.set_weather(0.0, 8.0, 0.0)
	var lev_a := Leviathan.new()
	lev_a.position = Vector3(-90.0, 0.0, -90.0)
	_root.add_child(lev_a)
	lev_a.set_physics_process(false)

	var lev_b := Leviathan.new()
	lev_b.position = Vector3(90.0, 0.0, -90.0)
	_root.add_child(lev_b)
	lev_b.set_physics_process(false)

	var l_halos_a := lev_a.get_abyssal_eye_halos()
	var l_halos_b := lev_b.get_abyssal_eye_halos()
	check_eq(l_halos_a.size(), 2, "Leviathan mounts 2 AbyssalEyeHalos via get_abyssal_eye_halos()")
	check_eq(l_halos_b.size(), 2, "second Leviathan mounts 2 AbyssalEyeHalos")

	var lev_halo_tris := 0
	var lev_halo_bad_normals := 0
	var lev_halo_has_core := false
	var lev_halo_has_black_rim := false
	if l_halos_a.size() == 2 and l_halos_b.size() == 2:
		var ahl := l_halos_a[0]
		var ahr := l_halos_a[1]
		check_eq(ahl.name, "AbyssalEyeHaloL", "left Leviathan halo named AbyssalEyeHaloL")
		check_eq(ahr.name, "AbyssalEyeHaloR", "right Leviathan halo named AbyssalEyeHaloR")
		check_eq(ahl.get_parent(), lev_a.get_crown_node(), "AbyssalEyeHaloL mounts inside _crown_root")
		check_eq(ahr.get_parent(), lev_a.get_crown_node(), "AbyssalEyeHaloR mounts inside _crown_root")
		check(ahl.position.x < -1.0 and ahr.position.x > 1.0 and is_equal_approx(ahl.position.x, -ahr.position.x),
			"AbyssalEyeHalos mount symmetrically over sculpted left/right crown eyes (+/- X)")
		check_eq(ahl.mesh, ahr.mesh, "left and right AbyssalEyeHalos share static _eye_halo_mesh")
		check_eq(ahl.mesh, l_halos_b[0].mesh, "Leviathans share statically cached _eye_halo_mesh")
		check_eq(ahl.material_override, ahr.material_override,
			"left and right AbyssalEyeHalos share per-instance material")
		check(ahl.material_override != l_halos_b[0].material_override,
			"distinct Leviathans use isolated per-instance halo materials")
		for hmi: MeshInstance3D in l_halos_a:
			check_eq(hmi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"%s disables shadow casting" % hmi.name)
			check_eq(hmi.gi_mode, GeometryInstance3D.GI_MODE_DISABLED,
				"%s disables GI mode" % hmi.name)
			check_near(hmi.visibility_range_end, 300.0, 0.05,
				"%s sets visibility_range_end = 300.0 m" % hmi.name)
			check(hmi.mesh is ArrayMesh and not (hmi.mesh is PrimitiveMesh),
				"%s uses sculpted ArrayMesh (zero PrimitiveMesh)" % hmi.name)

		if ahl.mesh is ArrayMesh:
			var arr := (ahl.mesh as ArrayMesh).surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			lev_halo_tris = floori(float(verts.size()) / 3.0)
			for nv in norms:
				if not nv.is_finite() or nv.distance_to(Vector3(0.0, 0.0, 1.0)) > 0.001:
					lev_halo_bad_normals += 1
			for cv in cols:
				if cv.r <= 0.001 and cv.g <= 0.001 and cv.b <= 0.001 and cv.a >= 0.99:
					lev_halo_has_black_rim = true
				if cv.r >= 0.95 and cv.g >= 0.88 and cv.b >= 0.50:
					lev_halo_has_core = true
		check_eq(lev_halo_tris, 48, "AbyssalEyeHalo mesh has exact 48 triangles (16 radial wedges)")
		check_eq(lev_halo_bad_normals, 0, "AbyssalEyeHalo normals are all finite (0, 0, 1) unit vectors")
		check(lev_halo_has_core and lev_halo_has_black_rim,
			"AbyssalEyeHalo fades from incandescent amber-white core to pure Color(0, 0, 0, 1) rim")

		var lh_mat := ahl.material_override as StandardMaterial3D
		check(lh_mat != null and lh_mat.vertex_color_use_as_albedo and lh_mat.vertex_color_is_srgb \
				and lh_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
				and lh_mat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD \
				and lh_mat.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED \
				and lh_mat.billboard_keep_scale \
				and lh_mat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED \
				and lh_mat.cull_mode == BaseMaterial3D.CULL_DISABLED,
			"AbyssalEyeHalos use unshaded additive scale-preserving billboard sRGB StandardMaterial3D")
		if lh_mat != null:
			check(lh_mat.albedo_texture == null and lh_mat.normal_texture == null and lh_mat.roughness_texture == null,
				"AbyssalEyeHalos allocate 0 extra VRAM textures")

	# Verify Leviathan calm daylight -> night -> tentacle slam windup rage escalation!
	lev_a._emerge_progress = 1.0
	for ti in Leviathan.TENTACLE_COUNT:
		lev_a._tentacles[ti]["slam_cd"] = 6.0
		lev_a._tentacles[ti]["slam_anim"] = 0.0

	Weather.time_of_day = 12.0
	Weather.set_weather(0.0, 8.0, 0.0)
	lev_a._update_visual_positions(0.0)
	var l_noon_e := lev_a.get_abyssal_eye_halo_energy()

	Weather.time_of_day = 0.5
	lev_a._update_visual_positions(0.0)
	var l_night_e := lev_a.get_abyssal_eye_halo_energy()

	Weather.time_of_day = 12.0
	lev_a._tentacles[0]["slam_cd"] = 0.12
	lev_a._update_visual_positions(0.0)
	var l_rage_e := lev_a.get_abyssal_eye_halo_energy()

	check(l_noon_e >= 0.44 and l_noon_e <= 0.60,
		"Leviathan calm daylight eye halo glows near ~0.52 (got %.3f)" % l_noon_e)
	check(l_night_e > l_noon_e * 1.8 and l_night_e >= 0.96,
		"Leviathan night eye halo flares near ~1.05 (noon=%.3f -> night=%.3f)" % [l_noon_e, l_night_e])
	check(l_rage_e > l_night_e and l_rage_e >= 1.42,
		"Leviathan slam-windup rage eye halo blazes near ~1.55 (night=%.3f -> rage=%.3f)" % [l_night_e, l_rage_e])

	# Verify VortexBiolumMotes MultiMesh (24x8-tri octahedron spores, 0 primitives, 0 VRAM textures).
	var motes_a := lev_a.get_vortex_motes_node()
	var motes_b := lev_b.get_vortex_motes_node()
	check(motes_a != null and motes_a.name == "VortexBiolumMotes",
		"Leviathan mounts VortexBiolumMotes MultiMeshInstance3D via get_vortex_motes_node()")

	var mote_tris := 0
	var mote_bad_normals := 0
	if motes_a != null:
		check_eq(motes_a.get_parent(), lev_a, "VortexBiolumMotes mounts directly under Leviathan")
		check_eq(motes_a.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"VortexBiolumMotes disables shadow casting")
		check_eq(motes_a.gi_mode, GeometryInstance3D.GI_MODE_DISABLED,
			"VortexBiolumMotes disables GI mode")
		check_near(motes_a.visibility_range_end, 260.0, 0.05,
			"VortexBiolumMotes sets visibility_range_end = 260.0 m")
		var vmm := motes_a.multimesh
		check(vmm != null and vmm.instance_count == 24 and vmm.use_colors,
			"VortexBiolumMotes configures 24 per-instance colored abyssal spores")
		check(vmm != null and vmm.mesh is ArrayMesh and not (vmm.mesh is PrimitiveMesh),
			"VortexBiolumMotes uses sculpted ArrayMesh (zero PrimitiveMesh)")
		if motes_b != null and motes_b.multimesh != null and vmm != null:
			check_eq(vmm.mesh, motes_b.multimesh.mesh,
				"Leviathans share statically cached 8-tri _vortex_mote_mesh")
			check_eq(motes_a.material_override, motes_b.material_override,
				"Leviathans share statically cached _vortex_mote_mat")
		if vmm != null and vmm.mesh is ArrayMesh:
			var arr := (vmm.mesh as ArrayMesh).surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			mote_tris = floori(float(verts.size()) / 3.0)
			for nv in norms:
				if not nv.is_finite() or nv.length_squared() < 0.5:
					mote_bad_normals += 1
		check_eq(mote_tris, 8, "sculpted VortexBiolumMotes diamond octahedron mesh has exact 8 triangles")
		check_eq(mote_bad_normals, 0, "all VortexBiolumMotes normals are finite unit vectors")

		var vm_mat := motes_a.material_override as StandardMaterial3D
		check(vm_mat != null and vm_mat.vertex_color_use_as_albedo and vm_mat.vertex_color_is_srgb \
				and vm_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
				and vm_mat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD \
				and vm_mat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED \
				and vm_mat.cull_mode == BaseMaterial3D.CULL_DISABLED,
			"VortexBiolumMotes uses unshaded additive sRGB double-sided depth-draw-disabled material")
		if vm_mat != null:
			check(vm_mat.albedo_texture == null and vm_mat.normal_texture == null and vm_mat.roughness_texture == null,
				"VortexBiolumMotes allocates 0 extra VRAM textures")

	# Verify upward spiraling vortex kinematics strictly inside perimeter r = 5.5..17.5 m & y = 0.25..5.4 m!
	for ti in Leviathan.TENTACLE_COUNT:
		lev_a._tentacles[ti]["slam_cd"] = 6.0
	lev_a._update_visual_positions(0.0)
	var mp0 := lev_a.get_vortex_mote_positions()
	check_eq(mp0.size(), 24, "get_vortex_mote_positions() returns all 24 vortex spore positions")

	lev_a._clock += 0.25
	lev_a._update_visual_positions(0.25)
	var mp1 := lev_a.get_vortex_mote_positions()
	var mote_rose := 0
	var mote_rotated := 0
	var mote_min_r := INF
	var mote_max_r := 0.0
	var mote_min_y := INF
	var mote_max_y := -INF
	var calm_travel := 0.0
	for i in 24:
		var p0 := mp0[i]
		var p1 := mp1[i]
		var r1 := Vector2(p1.x, p1.z).length()
		mote_min_r = minf(mote_min_r, r1)
		mote_max_r = maxf(mote_max_r, r1)
		mote_min_y = minf(mote_min_y, p1.y)
		mote_max_y = maxf(mote_max_y, p1.y)
		if p1.y > p0.y + 0.10:
			mote_rose += 1
		var ang0 := atan2(p0.z, p0.x)
		var ang1 := atan2(p1.z, p1.x)
		if absf(wrapf(ang1 - ang0, -PI, PI)) > 0.05:
			mote_rotated += 1
		calm_travel += Vector2(p1.x - p0.x, p1.z - p0.z).length()

	check(mote_rose >= 16, "VortexBiolumMotes spiral upward continuously (rose=%d / 24)" % mote_rose)
	check_eq(mote_rotated, 24, "all 24 VortexBiolumMotes swirl azimuthally around the ink vortex")
	check(mote_min_r >= 5.49 and mote_max_r <= 17.51,
		"all VortexBiolumMotes keep clear of ship deck in r=5.5..17.5 m (got %.2f..%.2f m)" % [mote_min_r, mote_max_r])
	check(mote_min_y >= 0.24 and mote_max_y <= 5.41,
		"all VortexBiolumMotes stay within y=0.25..5.4 m band (got %.2f..%.2f m)" % [mote_min_y, mote_max_y])

	# Verify tentacle slam windup rage accelerates vortex swirling!
	lev_a._tentacles[0]["slam_cd"] = 0.12
	var mp_pre_rage := lev_a.get_vortex_mote_positions()
	lev_a._clock += 0.25
	lev_a._update_visual_positions(0.25)
	var mp_post_rage := lev_a.get_vortex_mote_positions()
	var rage_travel := 0.0
	for i in 24:
		rage_travel += Vector2(mp_post_rage[i].x - mp_pre_rage[i].x, mp_post_rage[i].z - mp_pre_rage[i].z).length()
	check(rage_travel > calm_travel * 1.6,
		"VortexBiolumMotes accelerate during tentacle slam windup rage (%.2f -> %.2f m)" % [calm_travel, rage_travel])

	# Verify clean retreat/defeat fade & hide on both AbyssalEyeHalos & VortexBiolumMotes!
	var pre_defeat_l_e := lev_a.get_abyssal_eye_halo_energy()
	lev_a._on_defeated()
	lev_a._retreat_progress = 0.50
	lev_a._update_retreat(0.05)
	check(lev_a.get_abyssal_eye_halo_energy() < pre_defeat_l_e * 0.50,
		"AbyssalEyeHalos fade smoothly during defeat retreat (%.3f -> %.3f)" % [
			pre_defeat_l_e, lev_a.get_abyssal_eye_halo_energy()
		])
	lev_a._retreat_progress = 0.98
	lev_a._update_retreat(0.05)
	check_near(lev_a.get_abyssal_eye_halo_energy(), 0.0, 0.0001,
		"AbyssalEyeHalos reach 0.0 energy on retreat completion")
	check(l_halos_a.size() == 2 and not l_halos_a[0].visible and not l_halos_a[1].visible,
		"AbyssalEyeHalos hide cleanly on retreat completion")
	check(motes_a != null and not motes_a.visible,
		"VortexBiolumMotes hide cleanly on defeat retreat completion")

	print("    Q17A apex sea-bosses: MegaHalos=2x%d tris (%.2f->%.2f->%.2f->%.2f), DorsalWakeSpray=20x%d tris (y %.2f->%.2f), LevHalos=2x%d tris (%.2f->%.2f->%.2f), VortexMotes=24x%d tris (r %.1f..%.1f)" % [
		mega_halo_tris, m_noon_e, m_night_e, m_windup_e, m_charge_e,
		mega_drop_tris, circle_max_y, charge_max_y,
		lev_halo_tris, l_noon_e, l_night_e, l_rage_e,
		mote_tris, mote_min_r, mote_max_r,
	])

	# 4. Full Vulkan-safe zero-leak teardown releases ALL static caches cleanly to null!
	await _end()
	TreasureCatalog.clear_mesh_cache()
	check_eq(AncientMegalodon._active_megas, 0, "AncientMegalodon._active_megas == 0 after Q17A teardown")
	check(AncientMegalodon._mesh_cache.is_empty() \
			and AncientMegalodon._hide_mat == null and AncientMegalodon._scar_mat == null \
			and AncientMegalodon._eye_mat == null and AncientMegalodon._splash_mat == null \
			and AncientMegalodon._eye_halo_mesh == null and AncientMegalodon._wake_spray_mesh == null \
			and AncientMegalodon._wake_spray_mat == null,
		"AncientMegalodon releases all static caches including _eye_halo_mesh, _wake_spray_mesh & _wake_spray_mat (0 leaks)")
	check_eq(Leviathan._active_leviathans, 0, "Leviathan._active_leviathans == 0 after Q17A teardown")
	check(Leviathan._eye_rim_mesh == null and Leviathan._eye_iris_mesh == null \
			and Leviathan._eye_pupil_mesh == null and Leviathan._eye_halo_mesh == null \
			and Leviathan._vortex_mote_mesh == null and Leviathan._vortex_mote_mat == null,
		"Leviathan releases all static caches including _eye_halo_mesh, _vortex_mote_mesh & _vortex_mote_mat (0 leaks)")


func test_q18b_merchant_sale_halo_island_crab_telegraph_and_reef_eel_ambush_vfx() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Sea.time = 0.0
	Weather.time_of_day = 12.0
	Weather.set_weather(0.0, 8.0, 0.0)
	var saved_profile: Dictionary = Game.profile.data.duplicate(true)

	# 1. Static source guards: zero raw PrimitiveMesh allocations & strict Vulkan teardown compliance!
	var stall_src := FileAccess.get_file_as_string("res://src/world/merchant_stall.gd")
	var crab_src := FileAccess.get_file_as_string("res://src/combat/island_crab.gd")
	var eel_src := FileAccess.get_file_as_string("res://src/combat/reef_eel.gd")
	for src_pair: Array in [
		[stall_src, "merchant_stall.gd"],
		[crab_src, "island_crab.gd"],
		[eel_src, "reef_eel.gd"],
	]:
		var txt := String(src_pair[0])
		var fname := String(src_pair[1])
		for bad_prim: String in [
			"BoxMesh.new", "SphereMesh.new", "CylinderMesh.new",
			"QuadMesh.new", "CapsuleMesh.new", "PrismMesh.new",
		]:
			check(not txt.contains(bad_prim), "%s contains zero %s calls" % [fname, bad_prim])
	check(not stall_src.contains("_coin_burst.mesh = null") and not stall_src.contains(".mesh = null"),
		"merchant_stall.gd follows Godot 4.8 Vulkan rule (never nulls .mesh on CPUParticles3D teardown)")
	check(stall_src.contains("_coin_burst.visible = false"),
		"merchant_stall.gd hides CPUParticles3D cleanly on teardown")
	check(not eel_src.contains("multimesh.mesh = null") and not eel_src.contains("mm.mesh = null"),
		"reef_eel.gd follows Godot 4.8 Vulkan rule (never nulls .mesh on a live MultiMesh)")

	# 2. MerchantStall: 48-tri celebratory SaleGoldHalo flash + decay & live sale trigger!
	var stall_a := MerchantStall.new()
	stall_a.name = "MerchantStallQ18B_A"
	var stall_b := MerchantStall.new()
	stall_b.name = "MerchantStallQ18B_B"
	_root.add_child(stall_a)
	_root.add_child(stall_b)
	stall_a.set_process(false)
	stall_b.set_process(false)

	var sh_a := stall_a.get_sale_halo_node()
	var sh_b := stall_b.get_sale_halo_node()
	check(sh_a != null and sh_a.name == "SaleGoldHalo",
		"MerchantStall mounts SaleGoldHalo MeshInstance3D via get_sale_halo_node()")
	var sale_halo_tris := 0
	var sale_halo_bad_normals := 0
	var sale_halo_has_core := false
	var sale_halo_has_black_rim := false
	if sh_a != null and sh_b != null:
		check(sh_a.position.distance_to(Vector3(0.0, 1.48, 0.0)) < 0.001,
			"SaleGoldHalo mounts above merchant counter at (0.0, 1.48, 0.0)")
		check_eq(sh_a.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"SaleGoldHalo disables shadow casting")
		check_eq(sh_a.gi_mode, GeometryInstance3D.GI_MODE_DISABLED,
			"SaleGoldHalo disables GI mode")
		check_near(sh_a.visibility_range_end, 110.0, 0.05,
			"SaleGoldHalo sets visibility_range_end = 110.0 m")
		check(sh_a.mesh is ArrayMesh and not (sh_a.mesh is PrimitiveMesh),
			"SaleGoldHalo uses sculpted ArrayMesh (zero PrimitiveMesh)")
		check_eq(sh_a.mesh, sh_b.mesh, "MerchantStalls share statically cached _sale_halo_mesh")
		check(sh_a.material_override != sh_b.material_override,
			"distinct MerchantStalls use isolated per-instance SaleGoldHalo materials")

		if sh_a.mesh is ArrayMesh:
			var arr := (sh_a.mesh as ArrayMesh).surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			sale_halo_tris = floori(float(verts.size()) / 3.0)
			for nv in norms:
				if not nv.is_finite() or nv.distance_to(Vector3(0.0, 0.0, 1.0)) > 0.001:
					sale_halo_bad_normals += 1
			for cv in cols:
				if cv.r <= 0.001 and cv.g <= 0.001 and cv.b <= 0.001 and cv.a >= 0.99:
					sale_halo_has_black_rim = true
				if cv.r >= 0.95 and cv.g >= 0.90 and cv.b >= 0.50:
					sale_halo_has_core = true
		check_eq(sale_halo_tris, 48, "SaleGoldHalo mesh has exact 48 triangles (16 radial wedges)")
		check_eq(sale_halo_bad_normals, 0, "SaleGoldHalo normals are all finite (0, 0, 1) unit vectors")
		check(sale_halo_has_core and sale_halo_has_black_rim,
			"SaleGoldHalo grades doubloon-gold core to pure Color(0, 0, 0, 1) black rim")

		var smat := sh_a.material_override as StandardMaterial3D
		check(smat != null and smat.vertex_color_use_as_albedo and smat.vertex_color_is_srgb \
				and smat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
				and smat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD \
				and smat.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED \
				and smat.billboard_keep_scale \
				and smat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED \
				and smat.cull_mode == BaseMaterial3D.CULL_DISABLED,
			"SaleGoldHalo uses unshaded additive scale-preserving billboard sRGB StandardMaterial3D")
		if smat != null:
			check(smat.albedo_texture == null and smat.normal_texture == null and smat.roughness_texture == null,
				"SaleGoldHalo allocates 0 extra VRAM textures")

	check(sh_a != null and not sh_a.visible and is_equal_approx(stall_a.get_sale_halo_energy(), 0.0),
		"SaleGoldHalo starts hidden at 0.0 energy when idle")

	stall_a.trigger_sale_flash()
	var sale_peak_e := stall_a.get_sale_halo_energy()
	var sale_start_s := sh_a.scale.x if sh_a != null else 0.0
	check(sh_a != null and sh_a.visible and sale_peak_e >= 1.40 and sale_peak_e <= 1.50,
		"trigger_sale_flash() ignites SaleGoldHalo peak (~1.45, got %.3f)" % sale_peak_e)
	check_near(sale_start_s, 0.75, 0.01, "SaleGoldHalo starts expanding from 0.75 m scale")
	check(sh_b != null and not sh_b.visible and is_equal_approx(stall_b.get_sale_halo_energy(), 0.0),
		"trigger_sale_flash() on stall_a does not affect idle stall_b")

	stall_a.step_vfx(0.45)
	var sale_mid_e := stall_a.get_sale_halo_energy()
	var sale_mid_s := sh_a.scale.x if sh_a != null else 0.0
	check(sh_a != null and sh_a.visible and sale_mid_e > 0.20 and sale_mid_e < sale_peak_e * 0.65,
		"SaleGoldHalo decays smoothly mid-flash (%.3f -> %.3f)" % [sale_peak_e, sale_mid_e])
	check(sale_mid_s > 1.35 and sale_mid_s < 1.85,
		"SaleGoldHalo blooms outward toward 1.85 m during flash (mid_scale=%.2f m)" % sale_mid_s)

	stall_a.step_vfx(0.50)
	check_near(stall_a.get_sale_halo_energy(), 0.0, 0.0001,
		"SaleGoldHalo decays cleanly to 0.0 energy after 0.90 s")
	check(sh_a != null and not sh_a.visible, "SaleGoldHalo hides cleanly once sale flash completes")

	# Verify real treasure sale via accept_carryable() fires SaleGoldHalo automatically!
	var crate := Carryable.new()
	crate.item_name = "Golden Chalice"
	_root.add_child(crate)
	check(stall_b.accept_carryable(crate), "stall_b accepts Carryable treasure sale")
	check(sh_b != null and sh_b.visible and stall_b.get_sale_halo_energy() >= 1.40,
		"accept_carryable() triggers celebratory SaleGoldHalo flash automatically (e=%.3f)" % stall_b.get_sale_halo_energy())
	stall_b.step_vfx(0.95)
	check(sh_b != null and not sh_b.visible and is_equal_approx(stall_b.get_sale_halo_energy(), 0.0),
		"stall_b SaleGoldHalo decays cleanly to hidden after sale")

	# 3. IslandCrab: 24-tri 4-point ClawTelegraphHalo danger glint!
	var crab_a := IslandCrab.spawn_at(_root, Vector3(12.0, 5.0, 0.0), 12.0)
	var crab_b := IslandCrab.spawn_at(_root, Vector3(-12.0, 5.0, 0.0), 12.0)
	crab_a.set_physics_process(false)
	crab_b.set_physics_process(false)

	var ch_a := crab_a.get_telegraph_halo_node()
	var ch_b := crab_b.get_telegraph_halo_node()
	check(ch_a != null and ch_a.name == "ClawTelegraphHalo",
		"IslandCrab mounts ClawTelegraphHalo MeshInstance3D via get_telegraph_halo_node()")
	var crab_halo_tris := 0
	var crab_halo_bad_normals := 0
	var crab_halo_has_core := false
	var crab_halo_has_black_tip := false
	if ch_a != null and ch_b != null:
		check_eq(ch_a.get_parent(), crab_a._body_root,
			"ClawTelegraphHalo mounts inside IslandCrab _body_root")
		check(ch_a.position.distance_to(Vector3(0.0, 0.56, -0.34)) < 0.001,
			"ClawTelegraphHalo mounts above raised front pincers at (0.0, 0.56, -0.34)")
		check_eq(ch_a.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"ClawTelegraphHalo disables shadow casting")
		check_eq(ch_a.gi_mode, GeometryInstance3D.GI_MODE_DISABLED,
			"ClawTelegraphHalo disables GI mode")
		check_near(ch_a.visibility_range_end, 75.0, 0.05,
			"ClawTelegraphHalo sets visibility_range_end = 75.0 m")
		check(ch_a.mesh is ArrayMesh and not (ch_a.mesh is PrimitiveMesh),
			"ClawTelegraphHalo uses sculpted ArrayMesh (zero PrimitiveMesh)")
		check_eq(ch_a.mesh, ch_b.mesh, "IslandCrabs share statically cached _telegraph_halo_mesh")
		check(ch_a.material_override != ch_b.material_override,
			"distinct IslandCrabs use isolated per-instance ClawTelegraphHalo materials")

		if ch_a.mesh is ArrayMesh:
			var arr := (ch_a.mesh as ArrayMesh).surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			crab_halo_tris = floori(float(verts.size()) / 3.0)
			for nv in norms:
				if not nv.is_finite() or nv.distance_to(Vector3(0.0, 0.0, 1.0)) > 0.001:
					crab_halo_bad_normals += 1
			for cv in cols:
				if cv.r <= 0.001 and cv.g <= 0.001 and cv.b <= 0.001 and cv.a >= 0.99:
					crab_halo_has_black_tip = true
				if cv.r >= 0.95 and cv.g >= 0.90 and cv.b >= 0.65:
					crab_halo_has_core = true
		check_eq(crab_halo_tris, 24, "ClawTelegraphHalo 4-point star has exact 24 triangles")
		check_eq(crab_halo_bad_normals, 0, "ClawTelegraphHalo normals are all finite (0, 0, 1) unit vectors")
		check(crab_halo_has_core and crab_halo_has_black_tip,
			"ClawTelegraphHalo fades from bright star core to pure Color(0, 0, 0, 1) black tips")

		var cmat := ch_a.material_override as StandardMaterial3D
		check(cmat != null and cmat.vertex_color_use_as_albedo and cmat.vertex_color_is_srgb \
				and cmat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
				and cmat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD \
				and cmat.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED \
				and cmat.billboard_keep_scale \
				and cmat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED \
				and cmat.cull_mode == BaseMaterial3D.CULL_DISABLED,
			"ClawTelegraphHalo uses unshaded additive scale-preserving billboard sRGB StandardMaterial3D")
		if cmat != null:
			check(cmat.albedo_texture == null and cmat.normal_texture == null and cmat.roughness_texture == null,
				"ClawTelegraphHalo allocates 0 extra VRAM textures")

	var crab_raw_prims := 0
	for n in crab_a.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh is PrimitiveMesh:
			crab_raw_prims += 1
	check_eq(crab_raw_prims, 0, "IslandCrab contains zero raw PrimitiveMeshes")

	check(ch_a != null and not ch_a.visible and is_equal_approx(crab_a.get_telegraph_halo_energy(), 0.0),
		"ClawTelegraphHalo starts hidden when crab is GUARD_IDLE")

	# Escalating amber-crimson flash across 0.55 s raised-claw TELEGRAPH windup!
	crab_a.state = IslandCrab.State.TELEGRAPH
	crab_a._state_timer = 0.53
	crab_a._update_telegraph_halo()
	var c_early_e := crab_a.get_telegraph_halo_energy()
	var c_early_s := ch_a.scale.x if ch_a != null else 0.0

	crab_a._state_timer = 0.27
	crab_a._update_telegraph_halo()
	var c_mid_e := crab_a.get_telegraph_halo_energy()
	var c_mid_s := ch_a.scale.x if ch_a != null else 0.0

	crab_a._state_timer = 0.02
	crab_a._update_telegraph_halo()
	var c_late_e := crab_a.get_telegraph_halo_energy()
	var c_late_s := ch_a.scale.x if ch_a != null else 0.0

	check(ch_a != null and ch_a.visible and c_early_e >= 0.64 and c_early_e <= 0.80,
		"ClawTelegraphHalo activates on early TELEGRAPH (~0.65, got %.3f)" % c_early_e)
	check(c_mid_e > c_early_e and c_mid_s > c_early_s,
		"ClawTelegraphHalo escalates through mid TELEGRAPH (e %.2f->%.2f, s %.2f->%.2f)" % [
			c_early_e, c_mid_e, c_early_s, c_mid_s
		])
	check(c_late_e > c_mid_e and c_late_e >= 1.44 and c_late_e <= 1.56 \
			and c_late_s >= 0.58 and c_late_s <= 0.63,
		"ClawTelegraphHalo peaks brightly right before lunge strike (e=%.3f, s=%.2f m)" % [c_late_e, c_late_s])

	# Verify sharp fade on LUNGE completion -> RECOVER, immediate hide on STAGGERED & DEAD!
	crab_a.state = IslandCrab.State.LUNGE
	crab_a._state_timer = IslandCrab.LUNGE_DURATION * 0.40
	crab_a._update_telegraph_halo()
	var c_lunge_e := crab_a.get_telegraph_halo_energy()
	check(c_lunge_e < c_late_e * 0.35,
		"ClawTelegraphHalo fades sharply during LUNGE (%.3f -> %.3f)" % [c_late_e, c_lunge_e])

	crab_a.state = IslandCrab.State.RECOVER
	crab_a._update_telegraph_halo()
	check(ch_a != null and not ch_a.visible and is_equal_approx(crab_a.get_telegraph_halo_energy(), 0.0),
		"ClawTelegraphHalo hides cleanly after LUNGE completion")

	crab_a.state = IslandCrab.State.TELEGRAPH
	crab_a._state_timer = 0.25
	crab_a._update_telegraph_halo()
	check(ch_a != null and ch_a.visible, "ClawTelegraphHalo re-illuminates during TELEGRAPH")
	crab_a.apply_stagger(1.35)
	check(ch_a != null and not ch_a.visible and is_equal_approx(crab_a.get_telegraph_halo_energy(), 0.0),
		"ClawTelegraphHalo hides immediately on windup interrupt STAGGERED")

	crab_b.state = IslandCrab.State.TELEGRAPH
	crab_b._state_timer = 0.20
	crab_b._update_telegraph_halo()
	check(ch_b != null and ch_b.visible, "crab_b ClawTelegraphHalo visible before lethal blow")
	crab_b.apply_damage(999.0)
	check(crab_b.dead and ch_b != null and not ch_b.visible \
			and is_equal_approx(crab_b.get_telegraph_halo_energy(), 0.0),
		"ClawTelegraphHalo hides immediately on IslandCrab defeat")

	# 4. ReefEel: 48-tri EelEyeGlint (day < night < ambush lunge) & 10x12-tri AmbushBubbleBurst!
	Weather.time_of_day = 12.0
	Weather.set_weather(0.0, 8.0, 0.0)
	var eel_a := ReefEel.spawn_at(_root, Vector3(24.0, -3.2, 24.0), 18.0, 3.2)
	var eel_b := ReefEel.spawn_at(_root, Vector3(-24.0, -1.5, 24.0), 18.0, 1.5)
	eel_a.set_physics_process(false)
	eel_b.set_physics_process(false)

	var eg_a := eel_a.get_eye_glint_node()
	var eg_b := eel_b.get_eye_glint_node()
	check(eg_a != null and eg_a.name == "EelEyeGlint",
		"ReefEel mounts EelEyeGlint MeshInstance3D via get_eye_glint_node()")

	var eel_glint_tris := 0
	var eel_glint_bad_normals := 0
	var eel_glint_has_core := false
	var eel_glint_has_black_rim := false
	if eg_a != null and eg_b != null:
		check_eq(eg_a.get_parent(), eel_a.segments[0],
			"EelEyeGlint mounts on sculpted head Segment_0")
		check_eq(eg_a.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"EelEyeGlint disables shadow casting")
		check_eq(eg_a.gi_mode, GeometryInstance3D.GI_MODE_DISABLED,
			"EelEyeGlint disables GI mode")
		check_near(eg_a.visibility_range_end, 70.0, 0.05,
			"EelEyeGlint sets visibility_range_end = 70.0 m")
		check(eg_a.mesh is ArrayMesh and not (eg_a.mesh is PrimitiveMesh),
			"EelEyeGlint uses sculpted ArrayMesh (zero PrimitiveMesh)")
		check_eq(eg_a.mesh, eg_b.mesh, "ReefEels share statically cached _eye_glint_mesh")
		check(eg_a.material_override != eg_b.material_override,
			"distinct ReefEels use isolated per-instance EelEyeGlint materials")

		if eg_a.mesh is ArrayMesh:
			var arr := (eg_a.mesh as ArrayMesh).surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			eel_glint_tris = floori(float(verts.size()) / 3.0)
			for nv in norms:
				if not nv.is_finite() or nv.distance_to(Vector3(0.0, 0.0, 1.0)) > 0.001:
					eel_glint_bad_normals += 1
			for cv in cols:
				if cv.r <= 0.001 and cv.g <= 0.001 and cv.b <= 0.001 and cv.a >= 0.99:
					eel_glint_has_black_rim = true
				if cv.r >= 0.80 and cv.g >= 0.95 and cv.b >= 0.25:
					eel_glint_has_core = true
		check_eq(eel_glint_tris, 48, "EelEyeGlint mesh has exact 48 triangles (16 radial wedges)")
		check_eq(eel_glint_bad_normals, 0, "EelEyeGlint normals are all finite (0, 0, 1) unit vectors")
		check(eel_glint_has_core and eel_glint_has_black_rim,
			"EelEyeGlint grades chartreuse-emerald core to pure Color(0, 0, 0, 1) black rim")

		var emat := eg_a.material_override as StandardMaterial3D
		check(emat != null and emat.vertex_color_use_as_albedo and emat.vertex_color_is_srgb \
				and emat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
				and emat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD \
				and emat.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED \
				and emat.billboard_keep_scale \
				and emat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED \
				and emat.cull_mode == BaseMaterial3D.CULL_DISABLED,
			"EelEyeGlint uses unshaded additive scale-preserving billboard sRGB StandardMaterial3D")
		if emat != null:
			check(emat.albedo_texture == null and emat.normal_texture == null and emat.roughness_texture == null,
				"EelEyeGlint allocates 0 extra VRAM textures")

	# Verify EelEyeGlint day < night < ambush lunge flare -> 0.0 hidden on defeat!
	eel_a.state = ReefEel.State.LURK
	Weather.time_of_day = 12.0
	eel_a.step_vfx(0.0)
	var e_day := eel_a.get_eye_glint_energy()

	Weather.time_of_day = 0.5
	eel_a.step_vfx(0.0)
	var e_night := eel_a.get_eye_glint_energy()

	Weather.time_of_day = 12.0
	eel_a.state = ReefEel.State.DART
	eel_a.step_vfx(0.0)
	var e_lunge := eel_a.get_eye_glint_energy()

	check(e_day >= 0.24 and e_day <= 0.32,
		"EelEyeGlint glows subtly while lurking in daytime coral (~0.28, got %.3f)" % e_day)
	check(e_night > e_day * 1.9 and e_night >= 0.58 and e_night <= 0.72,
		"EelEyeGlint brightens eerily at night (~0.65, day=%.3f -> night=%.3f)" % [e_day, e_night])
	check(e_lunge > e_night * 1.8 and e_lunge >= 1.28 and e_lunge <= 1.42,
		"EelEyeGlint flares fiercely chartreuse-gold during ambush lunge (~1.35, got %.3f)" % e_lunge)

	eel_a.apply_damage(999.0)
	check(eel_a.dead and eg_a != null and not eg_a.visible \
			and is_equal_approx(eel_a.get_eye_glint_energy(), 0.0),
		"EelEyeGlint hides at 0.0 energy immediately upon ReefEel defeat")

	# Verify AmbushBubbleBurst: 10x12-tri sculpted bubbles, hidden idle, rising & strictly submerged!
	var bub_a := eel_a.get_ambush_bubbles_node()
	var bub_b := eel_b.get_ambush_bubbles_node()
	check(bub_b != null and bub_b.name == "AmbushBubbleBurst",
		"ReefEel mounts AmbushBubbleBurst MultiMeshInstance3D via get_ambush_bubbles_node()")

	var eel_bub_tris := 0
	var eel_bub_bad_normals := 0
	if bub_b != null and bub_a != null:
		check_eq(bub_b.get_parent(), eel_b,
			"AmbushBubbleBurst mounts directly under ReefEel")
		check_eq(bub_b.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"AmbushBubbleBurst disables shadow casting")
		check_eq(bub_b.gi_mode, GeometryInstance3D.GI_MODE_DISABLED,
			"AmbushBubbleBurst disables GI mode")
		check_near(bub_b.visibility_range_end, 70.0, 0.05,
			"AmbushBubbleBurst sets visibility_range_end = 70.0 m")
		var bmm := bub_b.multimesh
		check(bmm != null and bmm.instance_count == 10 and bmm.use_colors,
			"AmbushBubbleBurst configures 10 per-instance colored underwater bubbles")
		check(bmm != null and bmm.mesh is ArrayMesh and not (bmm.mesh is PrimitiveMesh),
			"AmbushBubbleBurst uses sculpted ArrayMesh (zero SphereMesh)")
		if bub_a.multimesh != null and bmm != null:
			check_eq(bmm.mesh, bub_a.multimesh.mesh,
				"ReefEels share statically cached 12-tri _bubble_mesh")
			check_eq(bub_b.material_override, bub_a.material_override,
				"ReefEels share statically cached _bubble_mat")
		if bmm != null and bmm.mesh is ArrayMesh:
			var arr := (bmm.mesh as ArrayMesh).surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			eel_bub_tris = floori(float(verts.size()) / 3.0)
			for nv in norms:
				if not nv.is_finite() or nv.length_squared() < 0.5:
					eel_bub_bad_normals += 1
		check_eq(eel_bub_tris, 12, "sculpted 6-sided faceted bubble mesh has exact 12 triangles")
		check_eq(eel_bub_bad_normals, 0, "all AmbushBubbleBurst bubble normals are finite unit vectors")

		var bmat := bub_b.material_override as StandardMaterial3D
		check(bmat != null and bmat.vertex_color_use_as_albedo and bmat.vertex_color_is_srgb \
				and bmat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
				and bmat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
				and bmat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED,
			"AmbushBubbleBurst uses unshaded translucent sRGB depth-draw-disabled StandardMaterial3D")
		if bmat != null:
			check(bmat.albedo_texture == null and bmat.normal_texture == null and bmat.roughness_texture == null,
				"AmbushBubbleBurst allocates 0 extra VRAM textures")

	check(bub_b != null and not bub_b.visible,
		"AmbushBubbleBurst stays hidden when ReefEel is calm/lurking")

	# Pitch shallow ReefEel upward (stressing world-aligned upward drift & y <= -0.15 m surface clamp!).
	eel_b.rotation = Vector3(0.45, 0.7, 0.0)
	eel_b.trigger_ambush_bubbles()
	check(bub_b != null and bub_b.visible,
		"trigger_ambush_bubbles() activates AmbushBubbleBurst immediately")
	var bp0 := eel_b.get_ambush_bubble_positions()
	check_eq(bp0.size(), 10, "get_ambush_bubble_positions() returns all 10 bubbles")

	eel_b.step_vfx(0.25)
	var bp1 := eel_b.get_ambush_bubble_positions()
	var rose_count := 0
	for i in 10:
		if bp1[i].y > bp0[i].y + 0.15:
			rose_count += 1
	check_eq(rose_count, 10, "all 10 AmbushBubbleBurst bubbles drift cleanly upward on step_vfx(0.25)")

	var max_world_bub_y := -INF
	for _s in 6:
		eel_b.step_vfx(0.14)
		var bps := eel_b.get_ambush_bubble_positions()
		for i in 10:
			var wy_add := eel_b.global_position.y + bps[i].y
			var wy_xf := (bub_b.global_transform * bps[i]).y
			max_world_bub_y = maxf(max_world_bub_y, maxf(wy_add, wy_xf))
	check(max_world_bub_y <= -0.15 + 0.001,
		"all AmbushBubbleBurst bubbles stay strictly submerged y <= -0.15 m (max_y=%.3f)" % max_world_bub_y)

	# Step past 1.15 s lifetime -> decays cleanly to hidden!
	eel_b.step_vfx(0.20)
	check(bub_b != null and not bub_b.visible,
		"AmbushBubbleBurst decays cleanly to hidden after 1.15 s lifetime")

	print("    Q18B polish: SaleGoldHalo=%d tris (%.2f->%.2f->0.0), ClawTelegraphHalo=%d tris (%.2f->%.2f->%.2f), EelEyeGlint=%d tris (%.2f->%.2f->%.2f), AmbushBubbles=10x%d tris (max_y=%.2f)" % [
		sale_halo_tris, sale_peak_e, sale_mid_e,
		crab_halo_tris, c_early_e, c_mid_e, c_late_e,
		eel_glint_tris, e_day, e_night, e_lunge,
		eel_bub_tris, max_world_bub_y,
	])

	# 5. Full Vulkan-safe zero-leak teardown releases ALL static caches cleanly to null!
	await _end()
	Game.profile.data = saved_profile
	check_eq(MerchantStall._active_stalls, 0, "MerchantStall._active_stalls == 0 after Q18B teardown")
	check(MerchantStall._doubloon_mesh == null and MerchantStall._doubloon_mat == null \
			and MerchantStall._sale_halo_mesh == null,
		"MerchantStall releases all static caches including _sale_halo_mesh (0 leaks)")
	check_eq(IslandCrab._active_crabs, 0, "IslandCrab._active_crabs == 0 after Q18B teardown")
	check(IslandCrab._telegraph_halo_mesh == null,
		"IslandCrab releases _telegraph_halo_mesh cleanly (0 leaks)")
	check_eq(ReefEel._active_eels, 0, "ReefEel._active_eels == 0 after Q18B teardown")
	check(ReefEel._eye_glint_mesh == null and ReefEel._bubble_mesh == null \
			and ReefEel._bubble_mat == null,
		"ReefEel releases all static caches including _eye_glint_mesh, _bubble_mesh & _bubble_mat (0 leaks)")


func test_q23b_reef_fish_nocturnal_biolum_and_scatter_bubbles() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Sea.time = 0.0
	Weather.time_of_day = 12.0
	Weather.set_weather(0.0, 8.0, 0.0)

	# 1. Static source hygiene: zero PrimitiveMeshes & strict Godot 4.8 Vulkan MultiMesh teardown!
	var fish_src := FileAccess.get_file_as_string("res://src/world/reef_fish.gd")
	check(fish_src.length() > 1000, "loaded src/world/reef_fish.gd cleanly")
	for bad_prim: String in [
		"BoxMesh.new", "SphereMesh.new", "CylinderMesh.new",
		"QuadMesh.new", "CapsuleMesh.new", "PrismMesh.new",
	]:
		check(not fish_src.contains(bad_prim), "reef_fish.gd contains zero %s calls" % bad_prim)
	check(not fish_src.contains(".multimesh.mesh = null") and not fish_src.contains("mm.mesh = null") \
			and not fish_src.contains("bmm.mesh = null") and not fish_src.contains(".instance_count = 0"),
		"reef_fish.gd follows Godot 4.8 Vulkan rule (never nulls mesh or zeros instance_count on MultiMesh)")
	check(fish_src.contains("_bubbles_mmi.visible = false") and fish_src.contains("_bubbles_mmi.multimesh = null"),
		"reef_fish.gd hides and detaches ScatterBubbleBurst cleanly on teardown")

	# 2. Spawn two ReefFishSchools (including a shallow shelf school stressing y <= -0.35 m clamp!).
	var school_a := ReefFishSchool.new()
	school_a.name = "ReefFishQ23B_A"
	school_a.position = Vector3(14.0, -1.35, 10.0)
	school_a.min_depth_y = -2.2
	school_a.max_depth_y = -1.05
	school_a.fish_count = 22
	school_a.seed_val = 2301

	var school_b := ReefFishSchool.new()
	school_b.name = "ReefFishQ23B_B"
	school_b.position = Vector3(-18.0, -2.8, 12.0)
	school_b.fish_count = 20
	school_b.seed_val = 2302

	_root.add_child(school_a)
	_root.add_child(school_b)
	school_a.set_physics_process(false)
	school_b.set_physics_process(false)
	await physics_frames(1)

	# 3. Verify nocturnal bioluminescent flank/tail sheen on _fish_mat (daylight ~0.0 -> midnight >= 0.35).
	var fish_mmi := school_a.get_multimesh_instance()
	var fish_mat := fish_mmi.material_override as StandardMaterial3D if fish_mmi != null else null
	check(fish_mat != null and fish_mat.emission_enabled,
		"ReefFishSchool _fish_mat enables nocturnal bioluminescence emission")
	if fish_mat != null:
		check(fish_mat.emission.is_equal_approx(Color(0.18, 0.88, 0.92)),
			"ReefFishSchool _fish_mat uses aqua-cyan bioluminescent tint (0.18, 0.88, 0.92)")

	Weather.time_of_day = 12.0
	school_a.step_school(0.05)
	var day_biolum := school_a.get_biolum_energy()
	check(day_biolum < 0.01, "ReefFishSchool daylight biolum_energy stays ~0.0 (got %.3f)" % day_biolum)
	if fish_mat != null:
		check(fish_mat.emission_energy_multiplier < 0.01,
			"ReefFishSchool _fish_mat emission_energy_multiplier stays ~0.0 in bright daylight")

	Weather.time_of_day = 0.5
	school_a.step_school(0.05)
	var night_biolum := school_a.get_biolum_energy()
	check(night_biolum >= 0.35 and night_biolum <= 0.44,
		"ReefFishSchool midnight biolum_energy rises to ~0.42 (got %.3f)" % night_biolum)
	if fish_mat != null:
		check_near(fish_mat.emission_energy_multiplier, night_biolum, 0.002,
			"ReefFishSchool _fish_mat emission_energy_multiplier tracks midnight biolum_energy")

	Weather.time_of_day = 12.0
	school_a.step_school(0.05)
	check(school_a.get_biolum_energy() < 0.01,
		"ReefFishSchool biolum_energy returns cleanly to ~0.0 in daylight")

	# 4. Verify ScatterBubbleBurst geometry (12 instances x 12-tri sculpted ArrayMesh, zero primitives, 0 VRAM).
	var bub_a := school_a.get_scatter_bubbles()
	var bub_b := school_b.get_scatter_bubbles()
	check(bub_a != null and bub_a.name == "ScatterBubbleBurst",
		"ReefFishSchool mounts ScatterBubbleBurst via get_scatter_bubbles()")
	var bub_tris := 0
	var bub_bad_normals := 0
	if bub_a != null and bub_b != null:
		check_eq(bub_a.get_parent(), school_a, "ScatterBubbleBurst mounts directly under ReefFishSchool")
		check_eq(bub_a.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"ScatterBubbleBurst disables shadow casting")
		check_eq(bub_a.gi_mode, GeometryInstance3D.GI_MODE_DISABLED,
			"ScatterBubbleBurst disables GI mode")
		check(bub_a.visibility_range_end > 0.0 and bub_a.visibility_range_end <= 80.0,
			"ScatterBubbleBurst respects visibility range <= 80 m (got %.1f)" % bub_a.visibility_range_end)

		var bmm_a := bub_a.multimesh
		var bmm_b := bub_b.multimesh
		check(bmm_a != null and bmm_a.instance_count == 12 and bmm_a.use_colors,
			"ScatterBubbleBurst allocates exact 12 per-instance colored micro-bubbles")
		check(bmm_a != null and bmm_a.mesh is ArrayMesh and not (bmm_a.mesh is PrimitiveMesh),
			"ScatterBubbleBurst uses sculpted ArrayMesh (zero SphereMesh)")
		if bmm_a != null and bmm_b != null:
			check_eq(bmm_a.mesh, bmm_b.mesh, "ReefFishSchools share statically cached 12-tri _bubble_mesh")
			check_eq(bub_a.material_override, bub_b.material_override,
				"ReefFishSchools share statically cached _bubble_mat")
		if bmm_a != null and bmm_a.mesh is ArrayMesh:
			var arr := (bmm_a.mesh as ArrayMesh).surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			bub_tris = floori(float(verts.size()) / 3.0)
			for nv in norms:
				if not nv.is_finite() or nv.length_squared() < 0.5:
					bub_bad_normals += 1
		check_eq(bub_tris, 12, "sculpted 6-sided scatter micro-bubble has exact 12 triangles")
		check_eq(bub_bad_normals, 0, "all ScatterBubbleBurst bubble normals are finite unit vectors")

		var bmat := bub_a.material_override as StandardMaterial3D
		check(bmat != null and bmat.vertex_color_use_as_albedo and bmat.vertex_color_is_srgb \
				and bmat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
				and bmat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
				and bmat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED \
				and bmat.albedo_texture == null,
			"ScatterBubbleBurst uses zero-VRAM unshaded translucent sRGB StandardMaterial3D")

	# 5. Strictly hidden during calm cruising; bursts cleanly on swimmer scatter with 0.65 s cooldown!
	check(bub_a != null and not bub_a.visible and is_equal_approx(school_a.get_scatter_bubble_active_ratio(), 0.0),
		"ScatterBubbleBurst stays strictly hidden during calm cruising")
	for _calm in 4:
		school_a.step_school(0.20)
	check(bub_a != null and not bub_a.visible and is_equal_approx(school_a.get_scatter_bubble_active_ratio(), 0.0),
		"ScatterBubbleBurst remains hidden across calm cruising steps")

	var fish_pts := school_a.get_fish_world_positions()
	check(fish_pts.size() >= 1, "school_a exposes fish world positions")
	var swimmer_threat := fish_pts[0] + Vector3(0.15, 0.0, 0.15)
	school_a.step_school(0.05, swimmer_threat)
	var peak_ratio := school_a.get_scatter_bubble_active_ratio()
	check(bub_a != null and bub_a.visible and peak_ratio >= 0.95,
		"Swimmer entering SCATTER_RADIUS triggers ScatterBubbleBurst immediately (ratio=%.3f)" % peak_ratio)
	check(bub_b != null and not bub_b.visible and is_equal_approx(school_b.get_scatter_bubble_active_ratio(), 0.0),
		"Scatter on school_a leaves calm school_b ScatterBubbleBurst hidden")

	var bp0 := school_a.get_scatter_bubble_world_positions()
	check_eq(bp0.size(), 12, "get_scatter_bubble_world_positions() returns all 12 bubbles")

	# Re-step inside 0.65 s cooldown with threat still present -> must NOT spam-reset burst!
	school_a.step_school(0.25, swimmer_threat)
	var mid_ratio := school_a.get_scatter_bubble_active_ratio()
	check(bub_a != null and bub_a.visible and mid_ratio < peak_ratio - 0.15 and mid_ratio > 0.50,
		"ScatterBubbleBurst respects 0.65 s rate-limit cooldown without spamming (%.3f -> %.3f)" % [
			peak_ratio, mid_ratio
		])
	var bp1 := school_a.get_scatter_bubble_world_positions()
	var rose_count := 0
	var wobble_moved := 0
	for i in 12:
		if bp1[i].y > bp0[i].y + 0.08:
			rose_count += 1
		if Vector2(bp1[i].x - bp0[i].x, bp1[i].z - bp0[i].z).length() > 0.005:
			wobble_moved += 1
	check_eq(rose_count, 12, "all 12 scatter bubbles rise upward cleanly over 0.25 s")
	check(wobble_moved >= 10, "scatter bubbles drift with helical lateral wobble (%d/12)" % wobble_moved)

	# Advance across remaining burst lifetime (~1.3 s total without threat) checking strict y <= -0.35 m clamp!
	var max_world_bub_y := -INF
	for p in bp0:
		max_world_bub_y = maxf(max_world_bub_y, p.y)
	for p in bp1:
		max_world_bub_y = maxf(max_world_bub_y, p.y)
	for _step in 5:
		school_a.step_school(0.16)
		if bub_a != null and bub_a.visible:
			for p in school_a.get_scatter_bubble_world_positions():
				max_world_bub_y = maxf(max_world_bub_y, p.y)
	check(max_world_bub_y <= -0.35 + 0.001,
		"every active ScatterBubbleBurst bubble stays strictly submerged y <= -0.35 m (max_y=%.3f)" % max_world_bub_y)

	# Step past 1.3 s total elapsed -> fades cleanly back to hidden!
	school_a.step_school(0.30)
	check(bub_a != null and not bub_a.visible and is_equal_approx(school_a.get_scatter_bubble_active_ratio(), 0.0),
		"ScatterBubbleBurst fades cleanly back to hidden after 1.3 s")

	# Verify a real swimming Pawn entering SCATTER_RADIUS triggers school_b via _find_nearby_swimmer()!
	var fish_b_pts := school_b.get_fish_world_positions()
	var swimmer := _spawn_pawn(fish_b_pts[0] + Vector3(0.0, -0.6, 0.2), &"player")
	await physics_frames(1)
	var detected_threat := school_b._find_nearby_swimmer()
	check(detected_threat.is_finite(), "ReefFishSchool._find_nearby_swimmer() detects nearby swimming Pawn")
	school_b.step_school(0.05, detected_threat)
	check(bub_b != null and bub_b.visible and school_b.get_scatter_bubble_active_ratio() >= 0.95,
		"Swimming Pawn within SCATTER_RADIUS triggers ScatterBubbleBurst on school_b")
	swimmer.queue_free()

	print("    Q23B reef fish polish: biolum=%.2f->%.2f, ScatterBubbleBurst=12x%d tris (ratio %.2f->%.2f->0.0, max_y=%.2f)" % [
		day_biolum, night_biolum, bub_tris, peak_ratio, mid_ratio, max_world_bub_y,
	])

	# 6. Full Vulkan-safe zero-leak teardown releases ALL static caches cleanly to null!
	await _end()
	check_eq(ReefFishSchool._active_schools, 0, "ReefFishSchool._active_schools == 0 after Q23B teardown")
	check(ReefFishSchool._fish_mesh == null and ReefFishSchool._fish_mat == null \
			and ReefFishSchool._bubble_mesh == null and ReefFishSchool._bubble_mat == null,
		"ReefFishSchool releases _fish_mesh, _fish_mat, _bubble_mesh & _bubble_mat cleanly (0 leaks)")


func test_q25b_seabird_shared_mesh_cache_and_storm_soaring_dynamics() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Sea.time = 0.0
	Weather.set_weather(0.0, 8.0, 0.0)

	# 1. Static source hygiene: zero raw PrimitiveMesh constructors and 0 non-ASCII lines.
	var src := FileAccess.get_file_as_string("res://src/world/seabirds.gd")
	check(src.length() > 1000, "loaded src/world/seabirds.gd cleanly")
	for bad_prim: String in [
		"BoxMesh.new", "SphereMesh.new", "CylinderMesh.new",
		"QuadMesh.new", "CapsuleMesh.new", "PrismMesh.new",
		"TorusMesh.new", "PlaneMesh.new",
	]:
		check(not src.contains(bad_prim), "seabirds.gd contains zero %s calls" % bad_prim)
	var non_ascii_lines := 0
	for line: String in src.split("\n"):
		var raw_bytes := line.to_utf8_buffer()
		for b in raw_bytes:
			if b >= 128:
				non_ascii_lines += 1
				break
	check_eq(non_ascii_lines, 0, "src/world/seabirds.gd contains 0 non-ASCII code lines")

	check_eq(SeabirdFlock.get_active_flock_count(), 0,
		"SeabirdFlock active count starts at 0 before spawning flocks")
	check(SeabirdFlock._shared_body_mesh == null and SeabirdFlock._shared_wing_l_mesh == null \
			and SeabirdFlock._shared_wing_r_mesh == null and SeabirdFlock._shared_plumage_mat == null,
		"SeabirdFlock static shared caches start empty before first flock enters tree")

	# 2. Spawn two independent SeabirdFlock instances and verify exact shared GPU Mesh/Material refs.
	var anchor_a := Vector3(18.0, 0.0, -14.0)
	var anchor_b := Vector3(-28.0, 0.0, 22.0)
	var flock_a := SeabirdFlock.spawn_over(_root, anchor_a, 14.0, 16.0, 6)
	var flock_b := SeabirdFlock.spawn_over(_root, anchor_b, 12.0, 15.0, 5)
	flock_a.set_process(false)
	flock_b.set_process(false)

	check_eq(SeabirdFlock.get_active_flock_count(), 2,
		"SeabirdFlock tracks 2 active flocks in scene tree")

	var birds_a := flock_a.get_birds()
	var birds_b := flock_b.get_birds()
	check_eq(birds_a.size(), 6, "flock_a spawns 6 gulls")
	check_eq(birds_b.size(), 5, "flock_b spawns 5 gulls")

	var body_mi_a := birds_a[0].get_node_or_null(^"Body") as MeshInstance3D
	var body_mi_b := birds_b[0].get_node_or_null(^"Body") as MeshInstance3D
	var wl_mi_a := birds_a[0].get_node_or_null(^"WingL/WingLMesh") as MeshInstance3D
	var wl_mi_b := birds_b[0].get_node_or_null(^"WingL/WingLMesh") as MeshInstance3D
	var wr_mi_a := birds_a[0].get_node_or_null(^"WingR/WingRMesh") as MeshInstance3D
	var wr_mi_b := birds_b[0].get_node_or_null(^"WingR/WingRMesh") as MeshInstance3D
	check(body_mi_a != null and body_mi_b != null and wl_mi_a != null and wl_mi_b != null \
			and wr_mi_a != null and wr_mi_b != null,
		"both independent flocks mount Body, WingLMesh, and WingRMesh MeshInstance3D nodes")

	var body_a := body_mi_a.mesh as ArrayMesh
	var body_b := body_mi_b.mesh as ArrayMesh
	var wing_l_a := wl_mi_a.mesh as ArrayMesh
	var wing_l_b := wl_mi_b.mesh as ArrayMesh
	var wing_r_a := wr_mi_a.mesh as ArrayMesh
	var wing_r_b := wr_mi_b.mesh as ArrayMesh
	var mat_a := body_mi_a.material_override as StandardMaterial3D
	var mat_b := body_mi_b.material_override as StandardMaterial3D

	check(body_a != null and body_a == body_b and body_a.get_rid() == body_b.get_rid(),
		"two SeabirdFlock instances share exact same body ArrayMesh and GPU RID")
	check(wing_l_a != null and wing_l_a == wing_l_b and wing_l_a.get_rid() == wing_l_b.get_rid(),
		"two SeabirdFlock instances share exact same left-wing ArrayMesh and GPU RID")
	check(wing_r_a != null and wing_r_a == wing_r_b and wing_r_a.get_rid() == wing_r_b.get_rid(),
		"two SeabirdFlock instances share exact same right-wing ArrayMesh and GPU RID")
	check(mat_a != null and mat_a == mat_b and mat_a.get_rid() == mat_b.get_rid(),
		"two SeabirdFlock instances share exact same plumage StandardMaterial3D and GPU RID")
	check(flock_a._body_mesh == SeabirdFlock._shared_body_mesh \
			and flock_a._wing_l_mesh == SeabirdFlock._shared_wing_l_mesh \
			and flock_a._wing_r_mesh == SeabirdFlock._shared_wing_r_mesh \
			and flock_a._plumage_mat == SeabirdFlock._shared_plumage_mat,
		"instance aliases point directly to static shared SeabirdFlock GPU resources")
	check(mat_a != null and mat_a.vertex_color_use_as_albedo and mat_a.vertex_color_is_srgb \
			and mat_a.albedo_texture == null,
		"shared plumage material uses sRGB vertex colors with zero extra VRAM textures")

	var raw_prims := 0
	var bad_normals := 0
	var checked_meshes := 0
	for fl: SeabirdFlock in [flock_a, flock_b]:
		for n in fl.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			checked_meshes += 1
			if mi.mesh is PrimitiveMesh:
				raw_prims += 1
			if mi.mesh is ArrayMesh:
				var am := mi.mesh as ArrayMesh
				var arr := am.surface_get_arrays(0)
				var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				for nv in norms:
					if not nv.is_finite() or nv.length_squared() < 0.5:
						bad_normals += 1
	check(checked_meshes == (6 + 5) * 3, "verified all %d gull MeshInstance3D parts across both flocks" % checked_meshes)
	check_eq(raw_prims, 0, "SeabirdFlock uses zero raw PrimitiveMeshes")
	check_eq(bad_normals, 0, "all sculpted gull ArrayMesh normals are finite unit vectors")

	# 3. Calm weather baseline (storm = 0.0, wind = 8.0 m/s).
	var calm_phase_before: float = float(flock_a._birds[0]["flap_phase"])
	for _s in 20:
		flock_a.step_flock(0.05)
	var calm_phase_delta: float = float(flock_a._birds[0]["flap_phase"]) - calm_phase_before
	var calm_alt_factor := flock_a.get_effective_altitude_factor()
	var calm_flap_mult := flock_a.get_effective_flap_rate_mult()
	check_near(calm_alt_factor, 1.0, 0.005, "calm weather altitude factor stays 1.0")
	check_near(calm_flap_mult, 1.0, 0.005, "calm weather flap rate multiplier stays 1.0")

	var calm_y_sum := 0.0
	var calm_horiz_sum := 0.0
	for b in birds_a:
		calm_y_sum += b.global_position.y
		calm_horiz_sum += Vector2(b.global_position.x - anchor_a.x, b.global_position.z - anchor_a.z).length()
	var calm_mean_y := calm_y_sum / float(birds_a.size())
	var calm_mean_horiz := calm_horiz_sum / float(birds_a.size())

	# 4. Brisk trade winds (storm = 0.0, wind = 19.0 m/s): direct A/B check of wind-facing bank lean
	#    & vertical thermal heave modulation while altitude/flap storm factors stay 1.0.
	Weather.set_weather(0.0, 8.0, 1.1)
	flock_b.step_flock(0.0)
	var calm_b_y: Array[float] = []
	var calm_b_bank: Array[float] = []
	for idx_b in birds_b.size():
		calm_b_y.append(birds_b[idx_b].global_position.y)
		calm_b_bank.append(float(flock_b._birds[idx_b]["bank"]))

	Weather.set_weather(0.0, 19.0, 1.1)
	flock_b.step_flock(0.0)
	var max_wind_bank_delta := 0.0
	var max_thermal_heave_delta := 0.0
	for idx_b in birds_b.size():
		max_thermal_heave_delta = maxf(max_thermal_heave_delta, absf(birds_b[idx_b].global_position.y - calm_b_y[idx_b]))
		max_wind_bank_delta = maxf(max_wind_bank_delta, absf(float(flock_b._birds[idx_b]["bank"]) - calm_b_bank[idx_b]))
	for _s in 10:
		flock_b.step_flock(0.05)
	check_near(flock_b.get_effective_altitude_factor(), 1.0, 0.005,
		"brisk fair trade winds keep altitude factor at 1.0 when storm == 0.0")
	check(max_wind_bank_delta >= 0.04,
		"brisk trade winds add wind-facing roll bank lean (max_delta=%.3f rad)" % max_wind_bank_delta)
	check(max_thermal_heave_delta >= 0.20,
		"brisk trade winds add vertical thermal heave modulation (max_delta=%.3f m)" % max_thermal_heave_delta)

	# 5. Heavy storm hunkering (storm = 0.95, wind = 21.0 m/s, storm swells): smooth descent,
	#    tightened orbit, accelerated wingbeat rate (>= 1.35x), shortened glide windows, and >= Sea.height + 3.0 m floor!
	Sea.amp_scale = Sea.AMP_STORM
	Sea.time = 2.4
	Weather.set_weather(0.95, 21.0, 0.8)

	# Verify smooth transition (intermediate step at 0.25 s is mid-descent, not instant snap).
	for _s in 5:
		flock_a.step_flock(0.05)
	var mid_alt_factor := flock_a.get_effective_altitude_factor()
	check(mid_alt_factor < 0.95 and mid_alt_factor > 0.65,
		"storm hunkering transitions smoothly over time (0.25 s alt_factor=%.3f)" % mid_alt_factor)

	# Finish settling into heavy storm over another 2.25 s.
	for _s in 45:
		flock_a.step_flock(0.05)
	var storm_alt_factor := flock_a.get_effective_altitude_factor()
	var storm_flap_mult := flock_a.get_effective_flap_rate_mult()
	check(storm_alt_factor <= 0.63 and storm_alt_factor >= 0.58,
		"heavy storm lowers effective altitude factor toward 0.58 (got %.3f)" % storm_alt_factor)
	check(storm_flap_mult >= 1.35 and storm_flap_mult <= 1.43,
		"heavy storm accelerates effective flap rate >= 1.35x (got %.3fx)" % storm_flap_mult)

	# Verify calm glide windows shorten sharply in heavy storms (<= 2.0 s vs calm 2.6..4.6 s).
	flock_a._birds[0]["flapping"] = true
	flock_a._birds[0]["mode_timer"] = 0.01
	flock_a.step_flock(0.05)
	var storm_glide_dur: float = float(flock_a._birds[0]["mode_timer"])
	check(not bool(flock_a._birds[0]["flapping"]) and storm_glide_dur > 0.5 and storm_glide_dur <= 2.0,
		"heavy storm shortens calm glide window (got %.2f s <= 2.0 s)" % storm_glide_dur)

	# Measure actual wingbeat phase advance over 1.0 s in heavy storm vs 1.0 s calm baseline.
	var storm_phase_before: float = float(flock_a._birds[0]["flap_phase"])
	for _s in 20:
		flock_a.step_flock(0.05)
	var storm_phase_delta: float = float(flock_a._birds[0]["flap_phase"]) - storm_phase_before
	var observed_flap_ratio := storm_phase_delta / maxf(calm_phase_delta, 0.001)
	check(observed_flap_ratio >= 1.35,
		"actual gull wingbeat phase advances >= 1.35x faster in storm (ratio=%.3fx)" % observed_flap_ratio)

	var storm_y_sum := 0.0
	var storm_horiz_sum := 0.0
	var min_sea_clearance := INF
	for b in birds_a:
		var gp := b.global_position
		storm_y_sum += gp.y
		storm_horiz_sum += Vector2(gp.x - anchor_a.x, gp.z - anchor_a.z).length()
		var sea_y := Sea.height(gp.x, gp.z)
		min_sea_clearance = minf(min_sea_clearance, gp.y - sea_y)
	var storm_mean_y := storm_y_sum / float(birds_a.size())
	var storm_mean_horiz := storm_horiz_sum / float(birds_a.size())

	check(storm_mean_y < calm_mean_y - 2.5,
		"storm hunkering lowers mean gull altitude by > 2.5 m (calm=%.2f -> storm=%.2f)" % [
			calm_mean_y, storm_mean_y
		])
	check(storm_mean_horiz < calm_mean_horiz - 1.0,
		"storm hunkering tightens elliptical orbit radius (calm=%.2f -> storm=%.2f)" % [
			calm_mean_horiz, storm_mean_horiz
		])
	check(min_sea_clearance >= 3.0,
		"storm-hunkered gulls stay safely above Sea.height + 3.0 m (min_clear=%.2f m)" % min_sea_clearance)

	# Low-orbit stress check right over storm swells: floor strictly protects >= Sea.height + 3.5 m!
	var low_flock := SeabirdFlock.spawn_over(_root, Vector3(4.0, 0.0, 4.0), 10.0, 5.0, 5)
	low_flock.set_process(false)
	check_eq(SeabirdFlock.get_active_flock_count(), 3, "low-orbit stress flock increments active count to 3")
	var low_min_clear := INF
	for _s in 16:
		Sea.time += 0.15
		low_flock.step_flock(0.10)
		for b in low_flock.get_birds():
			var gp := b.global_position
			low_min_clear = minf(low_min_clear, gp.y - Sea.height(gp.x, gp.z))
	check(low_min_clear >= 3.49,
		"low-orbit gulls in full storm swell never dip below Sea.height + 3.5 m (min=%.2f m)" % low_min_clear)

	print("    Q25B seabird cache & storm flight: active=%d shared RIDs OK, wind_bank=%.3f rad, thermal=%.2f m, alt=%.2f->%.2f m (factor=%.3f), orbit=%.2f->%.2f m, flap=%.3fx, glide=%.2f s, min_clear=%.2f m (low=%.2f m)" % [
		SeabirdFlock.get_active_flock_count(),
		max_wind_bank_delta,
		max_thermal_heave_delta,
		calm_mean_y,
		storm_mean_y,
		storm_alt_factor,
		calm_mean_horiz,
		storm_mean_horiz,
		storm_flap_mult,
		storm_glide_dur,
		min_sea_clearance,
		low_min_clear,
	])

	# 6. Ref-counted teardown: partial free keeps shared cache alive; final teardown releases ALL caches!
	flock_b.queue_free()
	low_flock.queue_free()
	await physics_frames(2)
	check_eq(SeabirdFlock.get_active_flock_count(), 1,
		"active flock count decrements accurately to 1 while flock_a remains alive")
	check(SeabirdFlock._shared_body_mesh != null and SeabirdFlock._shared_plumage_mat != null,
		"static shared caches remain alive while >= 1 SeabirdFlock is active")

	await _end()
	check_eq(SeabirdFlock.get_active_flock_count(), 0,
		"SeabirdFlock.get_active_flock_count() drops to 0 after teardown")
	check(SeabirdFlock._shared_body_mesh == null and SeabirdFlock._shared_wing_l_mesh == null \
			and SeabirdFlock._shared_wing_r_mesh == null and SeabirdFlock._shared_plumage_mat == null,
		"SeabirdFlock releases all static shared meshes and plumage material cleanly (0 leaks)")

