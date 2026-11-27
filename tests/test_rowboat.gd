extends TestCase
## Headless tests for sculpted stern-docked rowable Rowboat, 4-point 24-wave
## buoyancy, oar rowing kinematics, cargo stowage, stern davit docking/launching,
## and CrewBrain rowboat persona callouts.

const SLOOP_SCENE: PackedScene = preload("res://src/ship/sloop.tscn")
const BRIG_SCENE: PackedScene = preload("res://src/ship/brigantine.tscn")
const PAWN_SCENE: PackedScene = preload("res://src/characters/pawn.tscn")
const SPEEDUP := 4

var _root: Node3D
var _saved_weather: Dictionary
var _saved_amp: float = 1.0
var _saved_time: float = 0.0


func _fast(on: bool) -> void:
	Engine.physics_ticks_per_second = 60 * (SPEEDUP if on else 1)
	Engine.time_scale = float(SPEEDUP) if on else 1.0
	Engine.max_physics_steps_per_frame = 8 * (SPEEDUP if on else 1)


func _begin() -> void:
	_saved_weather = Weather.get_state()
	_saved_amp = Sea.amp_scale
	_saved_time = Sea.time
	Net.start_single_player()
	Weather.day_length_seconds = 0.0
	Weather.lightning_enabled = false
	Weather.set_weather(0.0, 8.0, 0.0)
	Sea.amp_scale = 0.0
	Sea.time = 0.0
	_fast(true)
	_root = Node3D.new()
	add_child(_root)


func _end() -> void:
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	await physics_frames(3)
	Rowboat.clear_shared_cache()
	_fast(false)
	Weather.apply_state(_saved_weather)
	Sea.amp_scale = _saved_amp
	Sea.time = _saved_time


static func _is_strict_ascii(txt: String) -> bool:
	for i in txt.length():
		var code := txt.unicode_at(i)
		if code >= 128:
			return false
	return true


func _make_test_chest(label: String = "Wayfarer's Chest") -> Carryable:
	var item := Carryable.new()
	item.name = "TestChest"
	item.item_name = label
	item.add_to_group(&"carryables")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.56, 0.40, 0.40)
	cs.shape = box
	item.add_child(cs)
	_root.add_child(item)
	return item


func test_rowboat_sculpted_geometry_pbr_and_zero_primitives() -> void:
	_begin()
	var rb := Rowboat.new()
	rb.name = "SculptedRowboat"
	_root.add_child(rb)
	await physics_frames(4)

	# 1. Verify >= 1,100 sculpted triangles, 0 PrimitiveMeshes, finite unit normals, and object-space triplanar PBR.
	var tris := rb.get_triangle_count()
	print("    Rowboat sculpted triangle count: %d tris" % tris)
	check(tris >= 1100, "Rowboat sculpted geometry must have >= 1100 tris (got %d)" % tris)

	var mesh_count := 0
	var prim_count := 0
	var bad_norms := 0
	var bad_mats := 0
	for n in rb.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		mesh_count += 1
		if mi.mesh is PrimitiveMesh:
			prim_count += 1
		var am := mi.mesh as ArrayMesh
		check(am != null, "MeshInstance3D '%s' uses sculpted ArrayMesh" % mi.name)
		if am != null:
			for si in am.get_surface_count():
				var arr := am.surface_get_arrays(si)
				var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				for nv in norms:
					if not nv.is_finite() or nv.length_squared() < 0.5:
						bad_norms += 1
		if mi.name == "LanternHalo":
			var smat := mi.material_override as ShaderMaterial
			check(smat != null and smat.shader != null, "LanternHalo uses zero-texture additive ShaderMaterial")
		else:
			var mat := mi.material_override as StandardMaterial3D
			check(mat != null, "MeshInstance3D '%s' has PBR StandardMaterial3D override" % mi.name)
			if mat != null:
				if not mat.vertex_color_use_as_albedo or not mat.vertex_color_is_srgb \
						or not mat.uv1_triplanar or mat.uv1_world_triplanar:
					bad_mats += 1

	check(mesh_count >= 7, "Rowboat builds multi-material sculpted mesh assembly (got %d)" % mesh_count)
	check_eq(prim_count, 0, "Rowboat must contain ZERO PrimitiveMeshes")
	check_eq(bad_norms, 0, "All Rowboat sculpted normals must be finite unit vectors")
	check_eq(bad_mats, 0, "All Rowboat materials must enable sRGB vertex colors + object-space triplanar PBR")

	# 2. Twin articulated oar pivots mounted at port & starboard midship gunwales.
	var port_piv := rb.get_node_or_null(^"RowboatVisualRoot/PortOarPivot") as Node3D
	var stbd_piv := rb.get_node_or_null(^"RowboatVisualRoot/StarboardOarPivot") as Node3D
	check(port_piv != null and stbd_piv != null, "Rowboat exposes twin PortOarPivot & StarboardOarPivot")
	if port_piv != null and stbd_piv != null:
		check_near(port_piv.position.x, -0.72, 0.02, "Port oarlock mounted at port midship gunwale")
		check_near(stbd_piv.position.x, 0.72, 0.02, "Starboard oarlock mounted at starboard midship gunwale")
		check_near(port_piv.position.y, 0.64, 0.05, "Oarlocks sit cleanly atop 0.62 m gunwale rail")
		check(port_piv.get_node_or_null(^"PortOarMesh") is MeshInstance3D, "Port oar pivot carries sculpted ash oar")
		check(stbd_piv.get_node_or_null(^"StarboardOarMesh") is MeshInstance3D, "Starboard oar pivot carries sculpted ash oar")

	# 3. Sculpted stern brass boat lantern + warm OmniLight3D + toggle API.
	var lglass := rb.get_node_or_null(^"RowboatVisualRoot/SternLanternGlass") as MeshInstance3D
	var llight := rb.get_node_or_null(^"RowboatVisualRoot/SternLanternLight") as OmniLight3D
	check(lglass != null and llight != null, "Rowboat mounts sculpted stern lantern glass & OmniLight3D")
	if llight != null:
		check(not llight.shadow_enabled, "Stern lantern OmniLight3D disables expensive shadows")
		check_near(llight.omni_range, 10.0, 0.1, "Stern lantern OmniLight3D omni_range is 10.0 m")
		check(llight.visible, "Stern lantern starts lit")
		rb.set_lantern_lit(false)
		check(not rb.lantern_lit and not llight.visible, "set_lantern_lit(false) douses stern lantern cleanly")
		var lg_mat := lglass.material_override as StandardMaterial3D if lglass != null else null
		if lg_mat != null:
			check_near(lg_mat.emission_energy_multiplier, 0.0, 0.01, "Doused lantern glass kills emission")
		rb.set_lantern_lit(true)
		check(rb.lantern_lit and llight.visible, "set_lantern_lit(true) relights stern lantern cleanly")
		if lg_mat != null:
			check(lg_mat.emission_energy_multiplier > 1.0, "Lit lantern glass glows warmly")

	# 4. Strict-ASCII prompts across station & interactables.
	check(rb.oar_station != null, "Rowboat creates built-in oar_station")
	check_eq(rb.oar_station.kind, &"rowboat_oars", "oar_station kind is &'rowboat_oars'")
	check_eq(rb.oar_station.get_focus_prompt(), "Row dinghy", "oar_station focus prompt returns 'Row dinghy'")
	for txt: String in [
		rb.get_dock_prompt(),
		rb.oar_station.get_focus_prompt(),
		rb.oar_station.get_active_prompt(),
		rb.cargo_interactable.prompt if rb.cargo_interactable != null else "",
	]:
		check(txt.length() > 0 and _is_strict_ascii(txt), "Rowboat prompt must be non-empty strict ASCII: '%s'" % txt)

	# 5. Leak-free static cache teardown.
	await _end()
	check_eq(Rowboat._active_instances, 0, "Rowboat _active_instances returns to 0 on teardown")
	check(Rowboat._hull_oak_mesh == null and Rowboat._oar_mesh == null and Rowboat._slings_mesh == null,
		"Rowboat clears static sculpted ArrayMesh caches cleanly")
	check(Rowboat._oak_mat == null and Rowboat._iron_mat == null and Rowboat._brass_mat == null and Rowboat._rope_mat == null,
		"Rowboat clears static PBR material caches cleanly")
	check(Rowboat._pbr_tex_cache.is_empty(), "Rowboat clears WeakRef PBR texture cache cleanly")


func test_rowboat_stern_docking_launch_oar_rowing_cargo_and_crew_callouts() -> void:
	_begin()
	var sloop := SLOOP_SCENE.instantiate() as Ship
	sloop.enable_effects = false
	_root.add_child(sloop)
	sloop.global_position = Vector3(0.0, 0.0, 0.0)
	sloop.set_anchor(true)
	sloop.anchor_progress = 1.0

	var brig := BRIG_SCENE.instantiate() as Ship
	brig.enable_effects = false
	_root.add_child(brig)
	brig.global_position = Vector3(45.0, 0.0, 0.0)
	brig.set_anchor(true)
	brig.anchor_progress = 1.0

	var rb := Rowboat.new()
	rb.name = "SternRowboat"
	_root.add_child(rb)
	await physics_frames(8)

	var slings_mi := rb.get_node_or_null(^"RowboatVisualRoot/DavitHoistSlings") as MeshInstance3D
	check(slings_mi != null, "Rowboat has DavitHoistSlings mesh")

	# ------------------------------------------------------------------
	# 1. Broadside Stern Docking on Sloop & Brigantine (Cleanly Below ShipNameplate)
	# ------------------------------------------------------------------
	rb.attach_to_ship(sloop)
	await physics_frames(4)
	check(rb.is_docked() and not rb.is_launched(), "Rowboat enters DOCKED state on Sloop attach")
	check(slings_mi != null and slings_mi.visible, "Davit hoist slings visible while docked")
	check(not rb.oar_station.interactable.enabled, "oar_station disabled while docked")
	check_eq(rb.dock_interactable.prompt, "Launch rowboat", "dock prompt says 'Launch rowboat' when docked")

	var sloop_dock_local := sloop.global_transform.affine_inverse() * rb.global_position
	var sloop_plate_bottom_y := (ShipNameplate.SLOOP_POS.y - ShipNameplate.SLOOP_SIZE.y * 0.5) * sloop.hull_scale
	var sloop_rowboat_gunwale_y := sloop_dock_local.y + Rowboat.HULL_GUNWALE_H
	print("    Sloop docked local=%s (gunwale_y=%.2f < nameplate_bot=%.2f)" % [
		sloop_dock_local, sloop_rowboat_gunwale_y, sloop_plate_bottom_y])
	check_near(sloop_dock_local.y, Rowboat.SLOOP_DOCK_LOCAL.y * sloop.hull_scale, 0.05,
		"Sloop docked Y matches SLOOP_DOCK_LOCAL * hull_scale")
	check_near(sloop_dock_local.z, Rowboat.SLOOP_DOCK_LOCAL.z * sloop.hull_scale, 0.05,
		"Sloop docked Z matches SLOOP_DOCK_LOCAL * hull_scale")
	check(sloop_rowboat_gunwale_y < sloop_plate_bottom_y,
		"Sloop docked rowboat gunwale sits cleanly BELOW ShipNameplate (%.2f < %.2f)" % [
			sloop_rowboat_gunwale_y, sloop_plate_bottom_y])

	# Verify docked stern lantern auto-syncs with mother_ship.lanterns_lit.
	sloop.set_lanterns_lit(false)
	await physics_frames(3)
	check(not rb.lantern_lit, "Docked rowboat stern lantern douses automatically with mother_ship.lanterns_lit")
	sloop.set_lanterns_lit(true)
	await physics_frames(3)
	check(rb.lantern_lit, "Docked rowboat stern lantern relights automatically with mother_ship.lanterns_lit")

	# Verify Brigantine stern dock clearance below Brigantine ShipNameplate!
	rb.attach_to_ship(brig)
	await physics_frames(4)
	var brig_dock_local := brig.global_transform.affine_inverse() * rb.global_position
	var brig_plate_bottom_y := (ShipNameplate.BRIG_POS.y - ShipNameplate.BRIG_SIZE.y * 0.5) * brig.hull_scale
	var brig_rowboat_gunwale_y := brig_dock_local.y + Rowboat.HULL_GUNWALE_H
	print("    Brigantine docked local=%s (gunwale_y=%.2f < nameplate_bot=%.2f)" % [
		brig_dock_local, brig_rowboat_gunwale_y, brig_plate_bottom_y])
	check_near(brig_dock_local.y, Rowboat.BRIG_DOCK_LOCAL.y * brig.hull_scale, 0.05,
		"Brigantine docked Y matches BRIG_DOCK_LOCAL * hull_scale")
	check_near(brig_dock_local.z, Rowboat.BRIG_DOCK_LOCAL.z * brig.hull_scale, 0.05,
		"Brigantine docked Z matches BRIG_DOCK_LOCAL * hull_scale")
	check(brig_rowboat_gunwale_y < brig_plate_bottom_y,
		"Brigantine docked rowboat gunwale sits cleanly BELOW ShipNameplate (%.2f < %.2f)" % [
			brig_rowboat_gunwale_y, brig_plate_bottom_y])

	# ------------------------------------------------------------------
	# 2. Launch onto Live 24-Wave Ocean & 4-Point Buoyancy
	# ------------------------------------------------------------------
	rb.attach_to_ship(sloop)
	await physics_frames(4)
	Sea.amp_scale = 1.0  # Real 24-wave Gerstner sea!
	Sea.time = 1.5

	var pawn := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(pawn)
	pawn.board(sloop, sloop.ship_point(Vector3(0.0, 2.02, 5.2)))

	var launched_events := [0]
	var docked_events := [0]
	rb.launched.connect(func(_p: Node) -> void: launched_events[0] += 1)
	rb.docked.connect(func(_p: Node) -> void: docked_events[0] += 1)

	var dock_world_before := rb.get_dock_world_transform(sloop).origin
	var launch_ok := rb.launch(pawn)
	check(launch_ok, "launch() succeeds from DOCKED state on host")
	check_eq(launched_events[0], 1, "launch() emits launched signal once")
	check(rb.is_launched() and not rb.is_docked(), "Rowboat transitions DOCKED -> LAUNCHED")
	check(slings_mi != null and not slings_mi.visible, "Davit hoist slings hidden while launched")
	check(rb.oar_station.interactable.enabled, "oar_station enabled once launched")

	var astern_dist := Vector2(rb.global_position.x - dock_world_before.x, rb.global_position.z - dock_world_before.z).length()
	check_near(astern_dist, Rowboat.LAUNCH_ASTERN_OFFSET, 0.35,
		"Launched dinghy deploys ~2.8 m astern of stern dock (got %.2f m)" % astern_dist)
	var sea_y_launch := Sea.height(rb.global_position.x, rb.global_position.z)
	check_near(rb.global_position.y, sea_y_launch, 0.20,
		"Launched dinghy lands on live 24-wave Sea.height() (y=%.2f vs sea=%.2f)" % [rb.global_position.y, sea_y_launch])

	# Step 4-point ocean buoyancy over active swells and confirm bounded pitch/roll <= 24 deg.
	await physics_frames(24)
	var live_sea_y := Sea.height(rb.global_position.x, rb.global_position.z)
	check_near(rb.global_position.y, live_sea_y, 0.45,
		"4-point buoyancy tracks live 24-wave Sea.height() (y=%.2f vs sea=%.2f)" % [rb.global_position.y, live_sea_y])
	check(absf(rb.rotation.x) <= Rowboat.MAX_TILT_RAD + 0.02 and absf(rb.rotation.z) <= Rowboat.MAX_TILT_RAD + 0.02,
		"Wave buoyancy pitch/roll stays cleanly clamped within +/-24 deg")

	# ------------------------------------------------------------------
	# 3. Oar Rowing Physics ([W] Forward Surge, [A] Port Yaw, [D] Starboard Yaw, [S] Brake)
	# ------------------------------------------------------------------
	pawn.teleport(rb.oar_station.get_stand_global().origin)
	check(pawn.enter_station(rb.oar_station), "Pawn boards Rowboat oar_station cleanly")
	check_eq(pawn.station, rb.oar_station, "Pawn occupies oar_station")

	var port_piv := rb.get_node(^"RowboatVisualRoot/PortOarPivot") as Node3D
	var stbd_piv := rb.get_node(^"RowboatVisualRoot/StarboardOarPivot") as Node3D
	var start_pos := rb.global_position
	var fwd_dir := -rb.global_basis.z
	fwd_dir.y = 0.0
	fwd_dir = fwd_dir.normalized()

	var max_oar_sweep := 0.0
	for _i in 90:
		pawn.drive_station(Vector2(0.0, 1.0), false, false, 1.0 / 60.0)
		await physics_frames(1)
		max_oar_sweep = maxf(max_oar_sweep, maxf(absf(port_piv.rotation.y), absf(stbd_piv.rotation.y)))

	var surge_speed := rb.get_speed()
	var surge_travel := (rb.global_position - start_pos).dot(fwd_dir)
	print("    Rowboat [W] surge: speed=%.2f m/s, travel=%.2f m, max_oar_sweep=%.2f rad" % [
		surge_speed, surge_travel, max_oar_sweep])
	check(surge_speed > 3.2, "Rowing [W] achieves crisp forward surge > 3.2 m/s (got %.2f m/s)" % surge_speed)
	check(surge_travel > 3.0, "Rowing [W] propels dinghy cleanly along -global_basis.z (travel=%.2f m)" % surge_travel)
	check(max_oar_sweep > 0.25, "Articulated port & starboard oars animate through pull strokes (sweep=%.2f rad)" % max_oar_sweep)

	# [S] Backwater brake slows the dinghy swiftly.
	var speed_before_brake := rb.get_speed()
	for _i in 32:
		pawn.drive_station(Vector2(0.0, -1.0), false, false, 1.0 / 60.0)
		await physics_frames(1)
	var speed_after_brake := rb.get_speed()
	print("    Rowboat [S] backwater brake: %.2f -> %.2f m/s" % [speed_before_brake, speed_after_brake])
	check(speed_after_brake < speed_before_brake - 2.0,
		"[S] backwater brake decelerates dinghy rapidly (%.2f -> %.2f m/s)" % [speed_before_brake, speed_after_brake])

	# [A] Port yaw turns bow left (+rotation.y).
	rb.linear_velocity = Vector3.ZERO
	rb.angular_velocity_y = 0.0
	var yaw_before_port := rb.rotation.y
	for _i in 45:
		pawn.drive_station(Vector2(-1.0, 0.0), false, false, 1.0 / 60.0)
		await physics_frames(1)
	var dyaw_port := angle_difference(yaw_before_port, rb.rotation.y)
	print("    Rowboat [A] port yaw delta: %+.2f rad" % dyaw_port)
	check(dyaw_port > 0.45, "[A] turns dinghy briskly to port (+yaw, got %.2f rad)" % dyaw_port)

	# [D] Starboard yaw turns bow right (-rotation.y).
	rb.angular_velocity_y = 0.0
	var yaw_before_stbd := rb.rotation.y
	for _i in 45:
		pawn.drive_station(Vector2(1.0, 0.0), false, false, 1.0 / 60.0)
		await physics_frames(1)
	var dyaw_stbd := angle_difference(yaw_before_stbd, rb.rotation.y)
	print("    Rowboat [D] starboard yaw delta: %+.2f rad" % dyaw_stbd)
	check(dyaw_stbd < -0.45, "[D] turns dinghy briskly to starboard (-yaw, got %.2f rad)" % dyaw_stbd)

	# [LMB] primary pull surges forward, and [RMB] secondary brakes cleanly.
	rb.linear_velocity = Vector3.ZERO
	for _i in 50:
		pawn.drive_station(Vector2.ZERO, true, false, 1.0 / 60.0)
		await physics_frames(1)
	var lmb_speed := rb.get_speed()
	check(lmb_speed > 2.2, "[LMB] primary pull propels dinghy forward (got %.2f m/s)" % lmb_speed)
	for _i in 30:
		pawn.drive_station(Vector2.ZERO, false, true, 1.0 / 60.0)
		await physics_frames(1)
	check(rb.get_speed() < lmb_speed - 1.5, "[RMB] feather brake slows dinghy smoothly")

	pawn.leave_station()
	check(pawn.station == null, "Pawn steps off oar_station cleanly")

	# ------------------------------------------------------------------
	# 4. Bow Thwart Cargo Stowage, Capacity Limit (4), hand_to(), & Retrieval
	# ------------------------------------------------------------------
	var cargo_counts: Array[int] = []
	rb.cargo_changed.connect(func(c: int) -> void: cargo_counts.append(c))

	var chest := _make_test_chest("Corsair's War-Chest")
	await physics_frames(2)
	check(rb.stow_carryable(chest), "stow_carryable() stows Carryable chest on bow thwart")
	check_eq(rb.get_cargo_count(), 1, "cargo count increments to 1")
	check(chest.visible and chest.stored_in == rb, "Stowed chest stays visible and bound to rowboat")

	# Confirm stowed chest rides along with rowboat motion!
	rb.global_position += Vector3(2.0, 0.0, 1.5)
	rb.step_physics(1.0 / 60.0)
	var expected_chest_pos := rb.global_transform * Rowboat.BOW_CARGO_SLOTS[0]
	check(chest.global_position.distance_to(expected_chest_pos) < 0.08,
		"Stowed chest tracks bow thwart cargo slot across rowboat movement")

	# Retrieve chest back into empty-handed Pawn's hands via pop_carryable().
	var popped := rb.pop_carryable(pawn)
	check_eq(popped, chest, "pop_carryable() returns the stowed chest")
	check_eq(rb.get_cargo_count(), 0, "cargo count returns to 0 after retrieval")
	check_eq(pawn.carried, chest, "pop_carryable(pawn) hands chest directly to empty-handed Pawn")
	check(cargo_counts == [1, 0], "cargo_changed emitted [1, 0] cleanly (got %s)" % str(cargo_counts))

	# Verify Carryable.hand_to(rowboat) container flow keeps chest visible on bow thwart!
	check(chest.hand_to(rb), "Carryable.hand_to(rowboat) stows carried chest via accept_carryable()")
	await physics_frames(2)
	check_eq(rb.get_cargo_count(), 1, "hand_to(rowboat) adds chest to rowboat cargo")
	check(chest.visible, "Chest stowed via hand_to() stays visible on bow thwart")
	check(pawn.carried == null, "hand_to(rowboat) clears Pawn.carried cleanly")

	# Verify MAX_CARGO = 4 limit and cargo_interactable empty-handed retrieval.
	var extra_chests: Array[Carryable] = []
	for ci in 4:
		var ec := _make_test_chest("Extra Chest %d" % ci)
		extra_chests.append(ec)
	await physics_frames(1)
	check(rb.stow_carryable(extra_chests[0]), "2nd chest stows cleanly")
	check(rb.stow_carryable(extra_chests[1]), "3rd chest stows cleanly")
	check(rb.stow_carryable(extra_chests[2]), "4th chest stows cleanly")
	check_eq(rb.get_cargo_count(), Rowboat.MAX_CARGO, "Rowboat holds up to MAX_CARGO (4) items")
	check(not rb.stow_carryable(extra_chests[3]), "5th chest is rejected once MAX_CARGO (4) is full")

	pawn.teleport(rb.cargo_interactable.global_position + Vector3(0.0, 0.0, 0.4))
	rb.cargo_interactable.interact(pawn)
	check_eq(rb.get_cargo_count(), 3, "cargo_interactable pops top stowed chest for empty-handed Pawn")
	check_eq(pawn.carried, extra_chests[2], "cargo_interactable hands top chest directly to Pawn")
	pawn.drop_carried(0.0)
	while rb.get_cargo_count() > 0:
		rb.pop_carryable(null)

	# ------------------------------------------------------------------
	# 5. CrewBrain Rowboat Launch & Dock Callouts (All 3 Personas, Strict ASCII)
	# ------------------------------------------------------------------
	for persona_id: StringName in [&"helmsman", &"lookout", &"carpenter"]:
		var cpawn := PAWN_SCENE.instantiate() as Pawn
		_root.add_child(cpawn)
		cpawn.board(sloop, sloop.ship_point(Vector3(0.0, 1.12, 0.4)))
		var brain := CrewBrain.new()
		brain.setup(sloop, pawn, persona_id)
		cpawn.add_child(brain)
		await physics_frames(2)

		var spoken: Array[Dictionary] = []
		brain.callout_spoken.connect(func(sp: String, txt: String, cat: StringName) -> void:
			spoken.append({"speaker": sp, "text": txt, "category": cat})
		)
		check(brain.notify_rowboat_launched(), "%s notify_rowboat_launched() fires callout" % persona_id)
		check(not brain.notify_rowboat_launched(), "%s notify_rowboat_launched() respects cooldown" % persona_id)
		check(brain.notify_rowboat_docked(), "%s notify_rowboat_docked() fires callout" % persona_id)
		check(not brain.notify_rowboat_docked(), "%s notify_rowboat_docked() respects cooldown" % persona_id)
		check_eq(spoken.size(), 2, "%s emitted both rowboat callouts" % persona_id)
		if spoken.size() == 2:
			check_eq(spoken[0]["category"], &"rowboat_launched", "%s first callout category is rowboat_launched" % persona_id)
			check_eq(spoken[1]["category"], &"rowboat_docked", "%s second callout category is rowboat_docked" % persona_id)
			for entry in spoken:
				var line_txt := String(entry["text"])
				check(line_txt.length() > 6 and _is_strict_ascii(line_txt),
					"%s callout is non-empty strict ASCII: '%s'" % [persona_id, line_txt])

		# Verify every dialogue bank entry for rowboat_launched & rowboat_docked is strict ASCII.
		for cat: StringName in [&"rowboat_launched", &"rowboat_docked"]:
			var lines: Array = CrewDialogue.LINES[persona_id].get(cat, [])
			check(lines.size() >= 2, "%s has >= 2 dialogue variations for %s" % [persona_id, cat])
			for raw_line in lines:
				check(_is_strict_ascii(String(raw_line)), "CrewDialogue %s/%s strict ASCII: '%s'" % [persona_id, cat, String(raw_line)])

	# ------------------------------------------------------------------
	# 6. Re-Docking Range Check & Quarterdeck Occupant Handoff
	# ------------------------------------------------------------------
	var stern_dock_world := rb.get_dock_world_transform(sloop).origin
	rb.global_position = stern_dock_world + Vector3(0.0, 0.0, Rowboat.DOCK_RANGE + 5.0)
	check(not rb.can_dock_to(sloop), "can_dock_to() rejects rowboat beyond DOCK_RANGE (8.5 m)")
	check(not rb.dock_to_ship(sloop, pawn), "dock_to_ship() refuses dock when out of range")

	# Move within DOCK_RANGE, seat Pawn at oars, and hoist cleanly back onto Sloop davits!
	rb.global_position = stern_dock_world + Vector3(0.0, 0.0, 4.2)
	rb.step_physics(1.0 / 60.0)
	check(rb.can_dock_to(sloop), "can_dock_to() accepts rowboat within 8.5 m of stern dock")
	check_eq(rb.get_dock_prompt(), "Dock rowboat", "get_dock_prompt() updates to 'Dock rowboat' when in range")

	pawn.teleport(rb.oar_station.get_stand_global().origin)
	check(pawn.enter_station(rb.oar_station), "Pawn sits back at oars prior to docking")
	check(rb.dock_to_ship(sloop, pawn), "dock_to_ship() hoists rowboat cleanly within 8.5 m")
	check_eq(docked_events[0], 1, "dock_to_ship() emits docked signal once")
	check(rb.is_docked() and not rb.is_launched(), "Rowboat returns cleanly to DOCKED state")
	check(slings_mi != null and slings_mi.visible, "Davit hoist slings reappear on re-dock")
	check_near(rb.get_speed(), 0.0, 0.001, "Re-docking zeroes rowboat velocity")
	check(pawn.station == null, "Re-docking releases rowing occupant from oar_station")
	check_eq(pawn.platform, sloop, "Re-docking steps occupant cleanly onto mother ship quarterdeck")

	# ------------------------------------------------------------------
	# 7. Clean 0-Leak Teardown & Shared Cache Verification
	# ------------------------------------------------------------------
	await _end()
	check_eq(Rowboat._active_instances, 0, "Rowboat _active_instances is 0 after full scenario teardown")
	check(Rowboat._hull_oak_mesh == null and Rowboat._trim_oak_mesh == null and Rowboat._oar_mesh == null \
		and Rowboat._oak_mat == null and Rowboat._pbr_tex_cache.is_empty(),
		"Rowboat.clear_shared_cache() leaves zero cached meshes, materials, or WeakRef textures")


func test_q10b_rowboat_lantern_halo_and_oar_splash_bursts() -> void:
	_begin()

	# 1. Static source guard: zero raw PrimitiveMesh allocations in rowboat.gd.
	var rb_src := FileAccess.get_file_as_string("res://src/ship/rowboat.gd")
	for bad_prim: String in ["QuadMesh.new", "BoxMesh.new", "SphereMesh.new", "CylinderMesh.new"]:
		check(not rb_src.contains(bad_prim), "rowboat.gd contains zero %s calls" % bad_prim)

	var rb := Rowboat.new()
	rb.name = "Q10BRowboat"
	_root.add_child(rb)
	rb.set_physics_process(false)
	await physics_frames(2)

	# 2. Verify zero-primitive additive stern LanternHalo & reusable Port/StbdOarSplash emitters.
	check(rb.has_lantern_halo(), "Rowboat mounts stern LanternHalo billboard")
	var halo := rb.get_node_or_null(^"RowboatVisualRoot/LanternHalo") as MeshInstance3D
	check(halo != null, "RowboatVisualRoot mounts LanternHalo MeshInstance3D")
	if halo != null:
		check_eq(halo.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"LanternHalo disables shadow casting")
		check_eq(halo.gi_mode, GeometryInstance3D.GI_MODE_DISABLED,
			"LanternHalo disables GI mode")
		check(halo.mesh is ArrayMesh and not (halo.mesh is PrimitiveMesh),
			"LanternHalo uses zero-primitive SurfaceTool ArrayMesh")
		if halo.mesh is ArrayMesh:
			check_eq((halo.mesh as ArrayMesh).get_faces().size(), 6,
				"LanternHalo quad uses exact 2 triangles (6 face vertices)")
		var hmat := halo.material_override as ShaderMaterial
		check(hmat != null and hmat.shader != null, "LanternHalo uses zero-texture additive ShaderMaterial")
		if hmat != null:
			check_near(float(hmat.get_shader_parameter(&"halo_scale")), 0.72, 0.01,
				"LanternHalo uses 0.72 m halo_scale")

	var port_sp := rb.get_node_or_null(^"RowboatVisualRoot/PortOarSplash") as GPUParticles3D
	var stbd_sp := rb.get_node_or_null(^"RowboatVisualRoot/StbdOarSplash") as GPUParticles3D
	check(port_sp != null and stbd_sp != null, "Rowboat mounts reusable PortOarSplash & StbdOarSplash GPUParticles3D")
	for sp: GPUParticles3D in [port_sp, stbd_sp]:
		if sp == null:
			continue
		check(not sp.one_shot, "%s keeps one_shot = false for timer-gated bursts" % sp.name)
		check_eq(sp.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"%s disables shadow casting" % sp.name)
		check(sp.draw_pass_1 is ArrayMesh and not (sp.draw_pass_1 is PrimitiveMesh),
			"%s draw_pass_1 uses zero-primitive 2-tri ArrayMesh" % sp.name)
		if sp.draw_pass_1 is ArrayMesh:
			check_eq((sp.draw_pass_1 as ArrayMesh).get_faces().size(), 6,
				"%s droplet card has exact 2 triangles (6 face vertices)" % sp.name)
		check(sp.material_override is ShaderMaterial, "%s uses zero-texture alpha ShaderMaterial" % sp.name)
		var sp_proc := sp.process_material as ParticleProcessMaterial
		check(sp_proc != null and sp_proc.scale_curve == null and sp_proc.color_ramp == null,
			"%s avoids CurveTexture/GradientTexture1D leak risks" % sp.name)

	# 3. Verify smooth daylight -> midnight (> 3x) -> storm night halo intensity + douse toggle!
	Weather.time_of_day = 12.0
	Weather.set_weather(0.0, 8.0, 0.0)
	for _i in 40:
		rb.step_physics(1.0 / 60.0)
	var noon_e := rb.get_lantern_halo_energy()
	check(noon_e >= 0.12 and noon_e <= 0.22,
		"Rowboat midday stern lantern halo stays crisp and subtle (got %.3f)" % noon_e)

	Weather.time_of_day = 23.0
	Weather.set_weather(0.0, 8.0, 0.0)
	for _i in 45:
		rb.step_physics(1.0 / 60.0)
	var night_e := rb.get_lantern_halo_energy()
	check(night_e > noon_e * 3.0 and night_e >= 0.95,
		"Rowboat midnight stern lantern halo exceeds 3x midday (noon=%.3f -> night=%.3f)" % [noon_e, night_e])

	Weather.time_of_day = 23.0
	Weather.set_weather(1.0, 14.0, 0.0)
	for _i in 45:
		rb.step_physics(1.0 / 60.0)
	var storm_e := rb.get_lantern_halo_energy()
	check(storm_e > night_e and storm_e >= 1.12,
		"Rowboat storm-night stern lantern halo rises further (night=%.3f -> storm=%.3f)" % [night_e, storm_e])

	rb.set_lantern_lit(false)
	check_near(rb.get_lantern_halo_energy(), 0.0, 0.0001,
		"set_lantern_lit(false) drops LanternHalo energy cleanly to 0.0")
	check(halo != null and not halo.visible, "set_lantern_lit(false) hides LanternHalo cleanly")

	rb.set_lantern_lit(true)
	check(rb.get_lantern_halo_energy() > 0.90 and halo != null and halo.visible,
		"set_lantern_lit(true) restores LanternHalo glow & visibility cleanly")

	# 4. Launch rowboat and drive forward rowing strokes -> oar-dip splashes & droplet bursts!
	check_eq(rb.get_oar_splash_count(), 0, "Docked rowboat starts with 0 oar splashes")
	check(rb.launch(), "Rowboat launches onto open sea cleanly")
	var saw_port_emitting := false
	var saw_stbd_emitting := false
	for _i in 90:
		rb.oar_station.drive(Vector2(0.0, 1.0), false, false, 1.0 / 60.0)
		rb.step_physics(1.0 / 60.0)
		if port_sp != null and port_sp.emitting:
			saw_port_emitting = true
		if stbd_sp != null and stbd_sp.emitting:
			saw_stbd_emitting = true

	var splash_cnt := rb.get_oar_splash_count()
	check(splash_cnt >= 2,
		"Forward rowing strokes trigger >= 2 oar-dip splashes (got %d)" % splash_cnt)
	check(saw_port_emitting and saw_stbd_emitting,
		"Both PortOarSplash and StbdOarSplash emit droplet bursts on oar dips")

	# Once rowing stops, timer-gated emitters settle back to emitting = false cleanly.
	for _i in 24:
		rb.step_physics(1.0 / 60.0)
	if port_sp != null and stbd_sp != null:
		check(not port_sp.emitting and not stbd_sp.emitting,
			"Oar splash emitters stop emitting cleanly once rowing pauses")

	print("    Q10B rowboat halo & oar splashes: noon=%.3f, night=%.3f (%.1fx), storm=%.3f, splashes=%d" % [
		noon_e, night_e, night_e / maxf(noon_e, 0.001), storm_e, splash_cnt
	])

	# 5. Clean zero-leak teardown!
	await _end()
	check_eq(Rowboat._active_instances, 0, "Rowboat _active_instances == 0 after Q10B teardown")
	check(Rowboat._lantern_halo_mesh == null and Rowboat._lantern_halo_shader == null \
		and Rowboat._oar_splash_mesh == null and Rowboat._oar_splash_shader == null \
		and Rowboat._oar_splash_mat == null and Rowboat._oar_splash_proc == null,
		"Rowboat clears all lantern halo & oar splash static caches cleanly with zero leaks")

