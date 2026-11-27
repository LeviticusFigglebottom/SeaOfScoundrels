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

	# 2. Verify strictly 1 MultiMeshInstance3D draw call, zero raw primitives, sRGB material & distance cull.
	var mmis := school.find_children("*", "MultiMeshInstance3D", true, false)
	var mis := school.find_children("*", "MeshInstance3D", true, false)
	check_eq(mmis.size(), 1, "ReefFishSchool renders in strictly 1 MultiMeshInstance3D draw call")
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
