class_name Outpost
extends Island
## Friendly pirate port outpost with a deep-water timber dock pier, glowing
## coastal beacon tower, rain-sheltered tavern, Merchant Buyer stall, Voyage
## Notice Board, and Quartermaster ship restocking.

signal treasure_sold(item: Node, gold: int, renown: int)
signal voyage_board_used(pawn: Node)
signal ship_restocked(ship: Node)

const DOCK_PIER_SCENE: PackedScene = preload("res://assets/generated/props/dock_pier.glb")
const TAVERN_SCENE: PackedScene = preload("res://assets/generated/props/outpost_tavern.glb")
const STALL_SCENE: PackedScene = preload("res://assets/generated/props/outpost_stall.glb")
const BEACON_SCENE: PackedScene = preload("res://assets/generated/props/beacon_tower.glb")
const NOTICE_BOARD_SCENE: PackedScene = preload("res://assets/generated/props/notice_board.glb")
const CAMPFIRE_SCENE: PackedScene = preload("res://assets/generated/props/campfire.glb")
const BARREL_SCENE: PackedScene = preload("res://assets/generated/props/barrel_prop.glb")
const CRATE_SCENE: PackedScene = preload("res://assets/generated/props/crate_supply.glb")

## Pier local geometry constants (must match tools/blender/gen_props.py).
const PIER_LENGTH := 16.0
const PIER_HALF_WIDTH := 1.80
## Distance abeam of pier centerline to moored sloop centerline (half-pier 1.80 +
## half-beam 2.20 = 4.00 m, leaving ~0.45 m clean water clearance).
const MOORING_ABEAM_OFFSET := 4.45
const MOORING_ALONG_PIER := -11.5

var dock_yaw: float = 0.0
var dock_node: Node3D = null
var dock_local_transform: Transform3D = Transform3D.IDENTITY
var dock_pier_end_local: Vector3 = Vector3.ZERO
var tavern_node: Node3D = null
var tavern_shelter: Area3D = null
var beacon_node: Node3D = null
var beacon_light: OmniLight3D = null
var merchant_stall: MerchantStall = null
var notice_board_node: Node3D = null
var voyage_board_interactable: Interactable = null
var quartermaster_interactable: Interactable = null
var _harbour_npcs: Array[Dictionary] = []  # {visual, driver, phase}


func _init() -> void:
	is_outpost = true
	kind = &"outpost"
	archetype = &"outpost"


func _process(delta: float) -> void:
	super._process(delta)
	if _harbour_npcs.is_empty():
		return
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam != null and global_position.distance_squared_to(cam.global_position) > 95.0 * 95.0:
		return
	for npc: Dictionary in _harbour_npcs:
		var drv: AnimationDriver = npc.get("driver") as AnimationDriver
		var cv: CharacterVisual = npc.get("visual") as CharacterVisual
		if drv == null or not is_instance_valid(drv) or cv == null or not is_instance_valid(cv):
			continue
		if not bool(npc.get("bound", false)):
			if cv.skeleton == null:
				continue
			drv.bind(cv)
			cv.set_tint(npc.get("primary") as Color, npc.get("accent") as Color)
			npc["bound"] = true
		var phase: float = float(npc.get("phase", 0.0)) + delta
		npc["phase"] = phase
		drv.set(&"override_state", {
			"speed": 0.0,
			"grounded": true,
			"look_pitch": sin(phase * 0.7) * 0.08,
		})
		drv.update_pose(delta)


func _exit_tree() -> void:
	_harbour_npcs.clear()


## Build all outpost structures on the sculpted harbour terrain.
## Called by `IslandGenerator` right after the terrain mesh & height grid exist.
func build_outpost_structures(p_dock_yaw: float, rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D) -> void:
	dock_yaw = p_dock_yaw
	var dock_basis := Basis(Vector3.UP, dock_yaw)

	# Helper to transform from dock-aligned harbour coordinates (u = starboard, v = inland/+Z, -v = seaward)
	# into island-local coordinates.
	var harbour_pt := func(u: float, v: float) -> Vector3:
		return dock_basis * Vector3(u, 0.0, v)

	# 1. Deep-water timber dock pier extending straight seaward along -Z of dock_basis.
	var shore_v := -28.0
	var dock_origin: Vector3 = harbour_pt.call(0.0, shore_v)
	dock_origin.y = 0.0
	dock_local_transform = Transform3D(dock_basis, dock_origin)
	dock_pier_end_local = dock_local_transform * Vector3(0.0, 0.0, -PIER_LENGTH)

	dock_node = _place_outpost_prop(
		DOCK_PIER_SCENE, "DockPier", dock_local_transform, prop_body, props_root)
	_attach_lantern_from_empty(dock_node, "Lantern_Dock", Color(1.0, 0.72, 0.34), 2.8, 18.0, 0.10, rng.randf() * TAU)

	# Safe deep-water mooring berth ~4.45 m starboard abeam of pier, bow facing open sea (-Z).
	var mooring_origin := dock_local_transform * Vector3(MOORING_ABEAM_OFFSET, 0.0, MOORING_ALONG_PIER)
	mooring_origin.y = 0.0
	mooring_transform = Transform3D(dock_basis, mooring_origin)

	# 2. Outpost Tavern on the harbour village terrace, porch facing the dock plaza.
	var tav_pos: Vector3 = harbour_pt.call(-11.0, -7.5)
	tav_pos.y = surface_height(tav_pos.x, tav_pos.z)
	var tav_xform := Transform3D(Basis(Vector3.UP, dock_yaw + 0.24), tav_pos)
	tavern_node = _place_outpost_prop(
		TAVERN_SCENE, "OutpostTavern", tav_xform, prop_body, props_root)
	_attach_lantern_from_empty(tavern_node, "Lantern_Tavern", Color(1.0, 0.70, 0.30), 3.0, 20.0, 0.12, rng.randf() * TAU)
	_build_tavern_shelter(tav_xform)

	# 3. Tall iconic Beacon Tower crowning the rocky harbour headland.
	var bcn_pos: Vector3 = harbour_pt.call(24.0, -6.5)
	bcn_pos.y = surface_height(bcn_pos.x, bcn_pos.z)
	var bcn_xform := Transform3D(Basis(Vector3.UP, dock_yaw - 0.35), bcn_pos)
	beacon_node = _place_outpost_prop(
		BEACON_SCENE, "BeaconTower", bcn_xform, prop_body, props_root)
	beacon_light = _attach_lantern_from_empty(
		beacon_node, "Lantern_Beacon", Color(1.0, 0.74, 0.30), 6.0, 48.0, 0.06, rng.randf() * TAU)
	_build_beacon_halo(beacon_node)

	# 4. Merchant Buyer Stall right beside the pier approach for effortless chest selling.
	var stall_pos: Vector3 = harbour_pt.call(9.2, -18.5)
	stall_pos.y = surface_height(stall_pos.x, stall_pos.z)
	var stall_xform := Transform3D(Basis(Vector3.UP, dock_yaw - 0.34), stall_pos)
	merchant_stall = MerchantStall.new()
	merchant_stall.name = "MerchantStall"
	merchant_stall.merchant_name = "%s Factor" % display_name
	merchant_stall.transform = stall_xform
	merchant_stall.treasure_sold.connect(_on_merchant_treasure_sold)
	props_root.add_child(merchant_stall)

	var stall_mesh := _place_outpost_prop(
		STALL_SCENE, "OutpostStallMesh", Transform3D.IDENTITY, prop_body, merchant_stall, stall_xform)
	_attach_lantern_from_empty(stall_mesh, "Lantern_Stall", Color(1.0, 0.72, 0.32), 2.5, 16.0, 0.10, rng.randf() * TAU)

	# 5. Voyage Notice Board along the dock plaza path.
	var nb_pos: Vector3 = harbour_pt.call(-6.6, -19.5)
	nb_pos.y = surface_height(nb_pos.x, nb_pos.z)
	var nb_xform := Transform3D(Basis(Vector3.UP, dock_yaw + 0.30), nb_pos)
	notice_board_node = _place_outpost_prop(
		NOTICE_BOARD_SCENE, "NoticeBoard", nb_xform, prop_body, props_root)
	voyage_board_interactable = Interactable.create("Inspect Voyage Board", 1.25)
	voyage_board_interactable.name = "VoyageBoardInteractable"
	voyage_board_interactable.position = Vector3(0.0, 1.45, -0.25)
	voyage_board_interactable.reach = 3.2
	voyage_board_interactable.target = self
	voyage_board_interactable.interacted.connect(_on_voyage_board_interacted)
	notice_board_node.add_child(voyage_board_interactable)

	# 6. Harbour Campfire in the square.
	var fire_pos: Vector3 = harbour_pt.call(1.8, -14.0)
	fire_pos.y = surface_height(fire_pos.x, fire_pos.z)
	var fire_node := _place_outpost_prop(
		CAMPFIRE_SCENE, "OutpostCampfire", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), fire_pos),
		prop_body, props_root)
	_attach_lantern_from_empty(fire_node, "Lantern_Fire", Color(1.0, 0.56, 0.18), 3.2, 16.0, 0.22, rng.randf() * TAU)

	# 7. Quartermaster Supply Crates & Barrels near the dock ramp head.
	var qm_pos: Vector3 = harbour_pt.call(-3.8, -23.0)
	qm_pos.y = surface_height(qm_pos.x, qm_pos.z)
	var qm_xform := Transform3D(Basis(Vector3.UP, dock_yaw + 0.18), qm_pos)
	var qm_crate := _place_outpost_prop(
		CRATE_SCENE, "QuartermasterCrate", qm_xform, prop_body, props_root)
	quartermaster_interactable = Interactable.create("Quartermaster: Restock nearby ship", 1.15)
	quartermaster_interactable.name = "QuartermasterInteractable"
	quartermaster_interactable.position = Vector3(0.0, 0.65, 0.0)
	quartermaster_interactable.reach = 3.0
	quartermaster_interactable.target = self
	quartermaster_interactable.interacted.connect(_on_quartermaster_interacted)
	qm_crate.add_child(quartermaster_interactable)

	# Accent barrels and supply crates around the plaza and pier entrance.
	var clutter_specs: Array[Array] = [
		[BARREL_SCENE, "DockBarrel_A", -2.9, -23.6, 0.4],
		[BARREL_SCENE, "DockBarrel_B", -4.7, -22.2, 1.8],
		[CRATE_SCENE, "StallCrate_A", 12.2, -16.8, -0.5],
		[BARREL_SCENE, "TavernBarrel_A", -5.4, -10.8, 0.9],
		[CRATE_SCENE, "TavernCrate_A", -4.4, -9.8, 0.2],
	]
	for spec in clutter_specs:
		var cp: Vector3 = harbour_pt.call(float(spec[2]), float(spec[3]))
		cp.y = surface_height(cp.x, cp.z)
		var cxform := Transform3D(Basis(Vector3.UP, dock_yaw + float(spec[4])), cp)
		_place_outpost_prop(spec[0] as PackedScene, String(spec[1]), cxform, prop_body, props_root)

	# 8. Living Outpost Harbour NPCs (Merchant Factor & Pier Quartermaster).
	var merch_pos: Vector3 = harbour_pt.call(7.6, -18.8)
	merch_pos.y = surface_height(merch_pos.x, merch_pos.z)
	_spawn_harbour_npc(
		"MerchantFactorNPC", props_root, merch_pos, dock_yaw + PI * 0.45,
		&"captain", Color(0.56, 0.14, 0.16), Color(0.92, 0.74, 0.24), rng.randf() * TAU)

	var qm_npc_pos: Vector3 = harbour_pt.call(-5.3, -22.2)
	qm_npc_pos.y = surface_height(qm_npc_pos.x, qm_npc_pos.z)
	_spawn_harbour_npc(
		"QuartermasterNPC", props_root, qm_npc_pos, dock_yaw - 0.55,
		&"carpenter", Color(0.14, 0.44, 0.46), Color(0.88, 0.62, 0.20), rng.randf() * TAU)


func _spawn_harbour_npc(npc_name: String, parent_node: Node3D, local_pos: Vector3, yaw_rad: float,
		arch: StringName, primary: Color, accent: Color, phase: float) -> void:
	var holder := Node3D.new()
	holder.name = npc_name
	holder.position = local_pos
	holder.rotation.y = yaw_rad
	parent_node.add_child(holder)

	var cv := CharacterVisual.new()
	cv.name = "CharacterVisual"
	cv.archetype = arch
	holder.add_child(cv)
	cv.set_tint(primary, accent)

	var drv := AnimationDriver.new()
	drv.name = "AnimationDriver"
	drv.set(&"auto_update", false)
	holder.add_child(drv)
	_harbour_npcs.append({
		"visual": cv,
		"driver": drv,
		"phase": phase,
		"primary": primary,
		"accent": accent,
		"bound": false,
	})


## Quartermaster auto-stock: refills a ship's cannonballs and repair planks (host-only).
func restock_ship(ship: Node) -> bool:
	if not Net.is_host() or ship == null or not is_instance_valid(ship):
		return false
	var restocked := false
	if ship.has_method("restock_supplies"):
		ship.call("restock_supplies")
		restocked = true
	else:
		if ship.get(&"cannonballs_remaining") != null:
			ship.set(&"cannonballs_remaining", Ship.MAX_CANNONBALLS)
			restocked = true
		if ship.get(&"planks_remaining") != null:
			ship.set(&"planks_remaining", Ship.MAX_PLANKS)
			restocked = true
	if not restocked:
		return false
	var sfx_pos := (ship as Node3D).global_position if ship is Node3D and ship.is_inside_tree() else global_position
	Audio.play_sfx(&"chest_thump", sfx_pos, -4.0)
	Game.post_notice("Quartermaster restocked cannonballs & repair planks.")
	ship_restocked.emit(ship)
	return true


## Convenience helper returning world-space position of the pier seaward tip.
func get_world_pier_end() -> Vector3:
	var xform := global_transform if is_inside_tree() else transform
	return xform * dock_pier_end_local


func _on_merchant_treasure_sold(item: Node, gold: int, renown: int) -> void:
	treasure_sold.emit(item, gold, renown)


func _on_voyage_board_interacted(pawn: Node) -> void:
	if not Net.is_host():
		return
	Audio.play_sfx(&"ui_open", voyage_board_interactable.global_position)
	voyage_board_used.emit(pawn)


func _on_quartermaster_interacted(_pawn: Node) -> void:
	if not Net.is_host():
		return
	var best_ship: Node = null
	var best_dist := 90.0
	var origin := global_position
	for s in get_tree().get_nodes_in_group(&"ship"):
		if s is Node3D:
			var d := (s as Node3D).global_position.distance_to(origin)
			if d < best_dist:
				best_dist = d
				best_ship = s
	if best_ship != null:
		restock_ship(best_ship)
	else:
		Game.post_notice("Quartermaster: Bring your ship to the pier to restock.")


func _build_tavern_shelter(tav_xform: Transform3D) -> void:
	# Shelter Area3D in group `shelter` per docs/ARCHITECTURE.md (covers main hall + covered porch).
	tavern_shelter = Area3D.new()
	tavern_shelter.name = "TavernShelter"
	tavern_shelter.collision_layer = 1 << 6
	tavern_shelter.collision_mask = 0
	tavern_shelter.monitoring = false
	tavern_shelter.monitorable = false
	tavern_shelter.add_to_group(&"shelter")
	tavern_shelter.transform = tav_xform * Transform3D(Basis.IDENTITY, Vector3(0.0, 2.25, -1.15))

	var cs := CollisionShape3D.new()
	cs.name = "ShelterBox"
	var box := BoxShape3D.new()
	box.size = Vector3(9.8, 4.4, 9.8)
	cs.shape = box
	tavern_shelter.add_child(cs)
	add_child(tavern_shelter)


func _build_beacon_halo(beacon_root: Node3D) -> void:
	if beacon_root == null:
		return
	var marker := beacon_root.find_child("Lantern_Beacon", true, false) as Node3D
	var local_pos := Vector3(0.0, 17.8, 0.0)
	if marker != null:
		local_pos = _relative_transform(marker, beacon_root).origin
	var halo := MeshInstance3D.new()
	halo.name = "BeaconGlowCore"
	var sph := SphereMesh.new()
	sph.radius = 1.25
	sph.height = 2.5
	sph.radial_segments = 10
	sph.rings = 6
	halo.mesh = sph
	halo.position = local_pos
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.86, 0.50)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.72, 0.25)
	mat.emission_energy_multiplier = 4.5
	halo.material_override = mat
	beacon_root.add_child(halo)


func _place_outpost_prop(scene: PackedScene, node_name: String, local_xform: Transform3D,
		prop_body: StaticBody3D, parent_node: Node3D,
		collider_override_xform: Variant = null) -> Node3D:
	var inst := scene.instantiate() as Node3D
	inst.name = node_name
	inst.transform = local_xform
	parent_node.add_child(inst)
	var base_xform: Transform3D = collider_override_xform if collider_override_xform is Transform3D else local_xform
	_extract_prop_colliders(inst, base_xform, prop_body)
	return inst


func _attach_lantern_from_empty(prop_root: Node3D, empty_name: String, color: Color,
		energy: float, light_range: float, flicker_amp: float, phase: float) -> OmniLight3D:
	if prop_root == null:
		return null
	var marker := prop_root.find_child(empty_name, true, false) as Node3D
	var light := OmniLight3D.new()
	light.name = empty_name + "_Light"
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	if marker != null:
		light.transform = _relative_transform(marker, prop_root)
	else:
		light.position = Vector3(0.0, 2.5, 0.0)
	prop_root.add_child(light)
	register_flicker_light(light, energy, flicker_amp, phase)
	return light


static func _extract_prop_colliders(prop_root: Node3D, root_to_island: Transform3D,
		target_body: StaticBody3D) -> void:
	if prop_root == null or target_body == null:
		return
	for node in prop_root.find_children("col_*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh == null:
			continue
		var faces := mi.mesh.get_faces()
		if faces.size() < 3:
			continue
		var shape := ConvexPolygonShape3D.new()
		shape.points = faces
		var cs := CollisionShape3D.new()
		cs.name = "Col_%s_%s" % [prop_root.name, mi.name]
		cs.shape = shape
		cs.transform = root_to_island * _relative_transform(mi, prop_root)
		target_body.add_child(cs)


static func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != ancestor:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
