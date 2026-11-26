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
	for n in c1.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if mi.mesh is PrimitiveMesh:
			raw_prims += 1
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
	check(absf(c1.global_position.y - expected_y) < 0.12,
		"FlotsamCluster rides live Sea.height() (y=%.2f vs sea=%.2f)" % [c1.global_position.y, expected_y])
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




