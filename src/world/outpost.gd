class_name Outpost
extends Island
## Friendly pirate port outpost with a deep-water timber dock pier, glowing
## coastal beacon tower, rain-sheltered tavern, interactive Tavern Grog Keg,
## wind-blown nautical bunting garlands, Merchant Buyer stall, Voyage Notice
## Board, Quartermaster ship restocking, and living harbour NPCs (including a
## campfire shanty bard).

signal treasure_sold(item: Node, gold: int, renown: int)
signal voyage_board_used(pawn: Node)
signal ship_restocked(ship: Node)
signal tavern_toast(pawn: Node)
signal pier_bell_rung(pawn: Node)

const DOCK_PIER_SCENE: PackedScene = preload("res://assets/generated/props/dock_pier.glb")
const TAVERN_SCENE: PackedScene = preload("res://assets/generated/props/outpost_tavern.glb")
const STALL_SCENE: PackedScene = preload("res://assets/generated/props/outpost_stall.glb")
const BEACON_SCENE: PackedScene = preload("res://assets/generated/props/beacon_tower.glb")
const NOTICE_BOARD_SCENE: PackedScene = preload("res://assets/generated/props/notice_board.glb")
const CAMPFIRE_SCENE: PackedScene = preload("res://assets/generated/props/campfire.glb")
const BARREL_SCENE: PackedScene = preload("res://assets/generated/props/barrel_prop.glb")
const CRATE_SCENE: PackedScene = preload("res://assets/generated/props/crate_supply.glb")
const BUNTING_SHADER: Shader = preload("res://src/world/bunting_wind.gdshader")
const LIGHTHOUSE_BEAM_SHADER: Shader = preload("res://src/world/lighthouse_beam.gdshader")

## Pier local geometry constants (must match tools/blender/gen_props.py).
const PIER_LENGTH := 16.0
const PIER_HALF_WIDTH := 1.80
## Distance abeam of pier centerline to moored ship centerline (half-pier 1.80 +
## 1.24x Sloop half-beam 2.73 m = 4.53 m, 1.24x Brigantine half-beam 3.35 m = 5.15 m,
## leaving clean water clearance with zero piling clipping for both ship classes).
const MOORING_ABEAM_OFFSET := 5.45
const MOORING_ALONG_PIER := -11.5

const BUNTING_WIND_CULL_DIST := 160.0
const TAVERN_SIGN_SWAY_CULL_DIST := 120.0
const MIN_BUNTING_ROPE_CLEARANCE := 4.75
const TAVERN_KEG_HEAL := 35.0
const SIGN_TEX_W := 256
const SIGN_TEX_H := 160

# Painterly maritime bunting palette (authored in sRGB).
const BUNTING_PALETTE: Array[Color] = [
	Color(0.710, 0.157, 0.133),  # Crimson (#b52822)
	Color(0.878, 0.627, 0.141),  # Marigold (#e0a024)
	Color(0.114, 0.235, 0.353),  # Deep navy (#1d3c5a)
	Color(0.941, 0.894, 0.784),  # Sun-bleached cream (#f0e4c8)
	Color(0.125, 0.439, 0.424),  # Tropical teal (#20706c)
]
const COL_ROPE_HEMP := Color(0.64, 0.52, 0.34)
const COL_POST_OAK := Color(0.28, 0.19, 0.12)
const COL_POST_IRON := Color(0.18, 0.20, 0.23)
const COL_POST_BRASS := Color(0.84, 0.64, 0.22)

# Sculpted Tavern Grog Keg palette (authored in sRGB).
const COL_KEG_OAK_A := Color(0.46, 0.28, 0.15)
const COL_KEG_OAK_B := Color(0.39, 0.23, 0.12)
const COL_KEG_OAK_C := Color(0.52, 0.33, 0.18)
const COL_KEG_HEAD := Color(0.56, 0.38, 0.21)
const COL_KEG_CRADLE := Color(0.27, 0.17, 0.10)
const COL_KEG_IRON := Color(0.18, 0.20, 0.24)
const COL_KEG_BRASS := Color(0.86, 0.66, 0.22)
const COL_KEG_BRASS_DARK := Color(0.62, 0.44, 0.14)
const COL_PEWTER := Color(0.62, 0.66, 0.70)
const COL_PEWTER_SHADE := Color(0.42, 0.46, 0.51)
const COL_GROG_AMBER := Color(0.58, 0.26, 0.06)
const COL_GROG_FOAM := Color(0.95, 0.91, 0.80)

# Sculpted Tavern Signboard & Seaward Pier Fog-Bell palette (authored in sRGB).
const COL_SIGN_IRON_HI := Color(0.24, 0.25, 0.28)
const COL_SIGN_IRON_LO := Color(0.11, 0.12, 0.14)
const COL_SIGN_MAHOGANY_HI := Color(0.36, 0.17, 0.085)
const COL_SIGN_MAHOGANY_MID := Color(0.24, 0.105, 0.052)
const COL_SIGN_MAHOGANY_LO := Color(0.13, 0.055, 0.026)
const COL_SIGN_BRASS_HI := Color(0.96, 0.78, 0.28)
const COL_SIGN_BRASS_LO := Color(0.62, 0.44, 0.12)
const COL_BELL_BRONZE_HI := Color(0.86, 0.67, 0.28)
const COL_BELL_BRONZE_MID := Color(0.66, 0.49, 0.21)
const COL_BELL_BRONZE_DARK := Color(0.34, 0.24, 0.11)
const COL_BELL_VERDIGRIS := Color(0.36, 0.48, 0.34)

const TAVERN_TOASTS: Array[String] = [
	"To fair winds and full holds! (+35 HP)",
	"Raise a mug to Port Scoundrel — may the Kraken take the hindmost! (+35 HP)",
	"Warm grog for salt-chilled bones! Drink up, Captain! (+35 HP)",
	"Here's to calm seas, stout planks, and gold by the chestful! (+35 HP)",
	"May your compass stay true and your powder stay dry! (+35 HP)",
]

# Statically cached procedural ArrayMeshes, textures & materials shared across Outposts.
static var _active_outposts: int = 0
static var _keg_mesh: ArrayMesh = null
static var _keg_mat: StandardMaterial3D = null
static var _beacon_halo_mesh: ArrayMesh = null
static var _beacon_halo_mat: StandardMaterial3D = null
static var _beacon_beam_mesh: ArrayMesh = null
static var _beacon_beam_mat: ShaderMaterial = null
static var _tavern_sign_bracket_mesh: ArrayMesh = null
static var _tavern_sign_board_mesh: ArrayMesh = null
static var _tavern_sign_face_mesh: ArrayMesh = null
static var _tavern_sign_iron_mat: StandardMaterial3D = null
static var _tavern_sign_board_mat: StandardMaterial3D = null
static var _tavern_sign_face_mat: StandardMaterial3D = null
static var _tavern_sign_albedo_tex: ImageTexture = null
static var _tavern_sign_emit_tex: ImageTexture = null
static var _pier_bell_frame_mesh: ArrayMesh = null
static var _pier_bell_cup_mesh: ArrayMesh = null
static var _pier_bell_iron_mat: StandardMaterial3D = null
static var _pier_bell_bronze_mat: StandardMaterial3D = null

var dock_yaw: float = 0.0
var dock_node: Node3D = null
var dock_local_transform: Transform3D = Transform3D.IDENTITY
var dock_pier_end_local: Vector3 = Vector3.ZERO
var tavern_node: Node3D = null
var tavern_shelter: Area3D = null
var tavern_sign_node: Node3D = null
var tavern_sign_pivot: Node3D = null
var pier_bell_node: Node3D = null
var pier_bell_pivot: Node3D = null
var pier_bell_interactable: Interactable = null
var beacon_node: Node3D = null
var beacon_light: OmniLight3D = null
var beacon_beam: MeshInstance3D = null
var merchant_stall: MerchantStall = null
var notice_board_node: Node3D = null
var voyage_board_interactable: Interactable = null
var quartermaster_interactable: Interactable = null
var harbour_bunting: MeshInstance3D = null
var tavern_keg_node: Node3D = null
var tavern_keg_interactable: Interactable = null
var tavern_bard_node: Node3D = null
var tavern_bard_interactable: Interactable = null
var tavern_bard_playing: bool = false
var campfire_cooking_stove: CookingStove = null

var _harbour_npcs: Array[Dictionary] = []  # {visual, driver, phase, primary, accent, bound, instrument_id, instrument_node, action_timer}
var _bard_shanty_motes: GPUParticles3D = null
var _bunting_mat: ShaderMaterial = null
var _bunting_clock: float = 0.0
var _bunting_wind_accum: float = 0.25
var _toast_index: int = 0
var _tavern_sign_phase: float = 0.0
var _tavern_sign_light: OmniLight3D = null
var _tavern_sign_bracket_mi: MeshInstance3D = null
var _tavern_sign_board_mi: MeshInstance3D = null
var _tavern_sign_face_mi: MeshInstance3D = null
var _pier_bell_frame_mi: MeshInstance3D = null
var _pier_bell_cup_mi: MeshInstance3D = null
var _pier_bell_angle: float = 0.0
var _pier_bell_vel: float = 0.0


func _init() -> void:
	is_outpost = true
	kind = &"outpost"
	archetype = &"outpost"


func _enter_tree() -> void:
	super._enter_tree()
	_active_outposts += 1


func _process(delta: float) -> void:
	super._process(delta)
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	var dist_sq := global_position.distance_squared_to(cam.global_position) if cam != null else 0.0

	# Distance-gated wind flutter updates for overhead nautical bunting garlands (<= 160 m).
	if _bunting_mat != null and dist_sq <= BUNTING_WIND_CULL_DIST * BUNTING_WIND_CULL_DIST:
		_bunting_clock += delta
		_bunting_mat.set_shader_parameter(&"wind_time", _bunting_clock)
		_bunting_wind_accum += delta
		if _bunting_wind_accum >= 0.16:
			_bunting_wind_accum = 0.0
			var wind := Weather.wind_vector()
			var spd := wind.length()
			var dir2 := Vector2(wind.x, wind.z)
			if dir2.length_squared() > 0.0001:
				dir2 = dir2.normalized()
			else:
				dir2 = Vector2(0.707, -0.707)
			_bunting_mat.set_shader_parameter(&"wind_dir", dir2)
			_bunting_mat.set_shader_parameter(&"wind_speed", spd)

	# Rotating volumetric lighthouse beacon beam (active at dusk/night or heavy storm mist; 0 ms in clear midday!).
	_update_beacon_beam(delta)

	# Distance-gated wind-driven pendulum sway for the hanging Tavern Signboard (<= 120 m).
	if tavern_sign_pivot != null and is_instance_valid(tavern_sign_pivot) \
			and dist_sq <= TAVERN_SIGN_SWAY_CULL_DIST * TAVERN_SIGN_SWAY_CULL_DIST:
		var wind_spd := maxf(2.0, Weather.wind_speed if Weather != null else 6.0)
		var wind_factor := clampf(wind_spd / 12.0, 0.35, 2.2)
		_tavern_sign_phase += delta * (1.85 + wind_factor * 0.55)
		var gust := 0.75 + 0.25 * sin(_tavern_sign_phase * 0.43 + dock_yaw)
		var sway_amp := clampf(0.045 + wind_factor * 0.085, 0.05, 0.24) * gust
		tavern_sign_pivot.rotation.x = sin(_tavern_sign_phase) * sway_amp
		tavern_sign_pivot.rotation.z = sin(_tavern_sign_phase * 0.67 + 1.1) * sway_amp * 0.28

	# Damped harmonic pendulum swing for the seaward Pier Fog-Bell (zero cost when at rest).
	if pier_bell_pivot != null and is_instance_valid(pier_bell_pivot):
		if absf(_pier_bell_angle) > 0.0005 or absf(_pier_bell_vel) > 0.0005:
			var step_dt := minf(delta, 0.05)
			var accel := -34.0 * _pier_bell_angle - 2.35 * _pier_bell_vel
			_pier_bell_vel += accel * step_dt
			_pier_bell_angle = clampf(_pier_bell_angle + _pier_bell_vel * step_dt, -0.78, 0.78)
			pier_bell_pivot.rotation.x = _pier_bell_angle
		elif pier_bell_pivot.rotation.x != 0.0:
			_pier_bell_angle = 0.0
			_pier_bell_vel = 0.0
			pier_bell_pivot.rotation.x = 0.0

	if _harbour_npcs.is_empty():
		return
	if cam != null and dist_sq > 95.0 * 95.0:
		return
	for npc: Dictionary in _harbour_npcs:
		var drv: AnimationDriver = npc.get("driver") as AnimationDriver
		var cv: CharacterVisual = npc.get("visual") as CharacterVisual
		if drv == null or not is_instance_valid(drv) or cv == null or not is_instance_valid(cv):
			continue
		if not bool(npc.get("bound", false)):
			if not _try_bind_harbour_npc(npc):
				continue
		var phase: float = float(npc.get("phase", 0.0)) + delta
		npc["phase"] = phase

		var inst_id: StringName = npc.get("instrument_id", &"") as StringName
		if inst_id != &"":
			var act_timer: float = float(npc.get("action_timer", 0.0)) - delta
			if act_timer <= 0.0:
				drv.play_action(&"play_instrument", 1.60)
				act_timer = 1.54
			npc["action_timer"] = act_timer
			var inst_node := npc.get("instrument_node") as Node3D
			if inst_node != null and is_instance_valid(inst_node):
				if inst_id == &"instrument":
					var squeeze_rate := 6.4 if tavern_bard_playing else 3.8
					ToolMeshes.set_concertina_stretch(inst_node, 0.50 + 0.46 * sin(phase * squeeze_rate))
				elif inst_id == &"hurdy_gurdy":
					ToolMeshes.set_hurdy_gurdy_crank(inst_node, phase * 4.2)
			drv.set(&"override_state", {
				"speed": 0.0,
				"grounded": true,
				"look_pitch": sin(phase * 1.4) * 0.10,
			})
		else:
			drv.set(&"override_state", {
				"speed": 0.0,
				"grounded": true,
				"look_pitch": sin(phase * 0.7) * 0.08,
			})
		drv.update_pose(delta)


func _exit_tree() -> void:
	if harbour_bunting != null and is_instance_valid(harbour_bunting):
		harbour_bunting.material_override = null
		harbour_bunting.mesh = null
	harbour_bunting = null
	_bunting_mat = null
	if beacon_beam != null and is_instance_valid(beacon_beam):
		beacon_beam.material_override = null
		beacon_beam.mesh = null
	beacon_beam = null
	_detach_bard_shanty_motes(false)
	if tavern_bard_playing:
		tavern_bard_playing = false
		if Audio != null:
			Audio.set_shanty_emitter(&"concertina", null)
			Audio.stop_shanty(0.05)
	for mi: MeshInstance3D in [
		_tavern_sign_bracket_mi,
		_tavern_sign_board_mi,
		_tavern_sign_face_mi,
		_pier_bell_frame_mi,
		_pier_bell_cup_mi,
	]:
		if mi != null and is_instance_valid(mi):
			mi.material_override = null
			mi.mesh = null
	_tavern_sign_bracket_mi = null
	_tavern_sign_board_mi = null
	_tavern_sign_face_mi = null
	_pier_bell_frame_mi = null
	_pier_bell_cup_mi = null
	tavern_sign_node = null
	tavern_sign_pivot = null
	_tavern_sign_light = null
	pier_bell_node = null
	pier_bell_pivot = null
	pier_bell_interactable = null
	tavern_keg_node = null
	tavern_keg_interactable = null
	tavern_bard_interactable = null
	tavern_bard_node = null
	campfire_cooking_stove = null
	for npc: Dictionary in _harbour_npcs:
		npc["instrument_node"] = null
	_harbour_npcs.clear()
	_active_outposts = maxi(0, _active_outposts - 1)
	if _active_outposts == 0:
		clear_shared_cache()


## Release statically cached procedural Outpost meshes, textures & materials cleanly.
static func clear_shared_cache() -> void:
	_keg_mesh = null
	_keg_mat = null
	_beacon_halo_mesh = null
	_beacon_halo_mat = null
	_beacon_beam_mesh = null
	_beacon_beam_mat = null
	if _tavern_sign_face_mat != null:
		_tavern_sign_face_mat.albedo_texture = null
		_tavern_sign_face_mat.emission_texture = null
	_tavern_sign_bracket_mesh = null
	_tavern_sign_board_mesh = null
	_tavern_sign_face_mesh = null
	_tavern_sign_iron_mat = null
	_tavern_sign_board_mat = null
	_tavern_sign_face_mat = null
	_tavern_sign_albedo_tex = null
	_tavern_sign_emit_tex = null
	_pier_bell_frame_mesh = null
	_pier_bell_cup_mesh = null
	_pier_bell_iron_mat = null
	_pier_bell_bronze_mat = null


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
	# Interactive sculpted bronze harbour fog-bell crowning the seaward port bollard piling!
	var bell_xform := dock_local_transform * Transform3D(Basis.IDENTITY, Vector3(-1.58, 2.23, -15.6))
	_build_pier_fog_bell(bell_xform, props_root)

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
	# Sculpted wind-swinging carved tavern hanging signboard off the front-left porch fascia!
	var sign_xform := tav_xform * Transform3D(Basis.IDENTITY, Vector3(-3.10, 3.12, -5.62))
	_build_tavern_signboard(sign_xform, props_root, rng)

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

	# 6. Harbour Campfire in the square with an interactive forged-iron tripod cooking skillet!
	var fire_pos: Vector3 = harbour_pt.call(1.8, -14.0)
	fire_pos.y = surface_height(fire_pos.x, fire_pos.z)
	var fire_node := _place_outpost_prop(
		CAMPFIRE_SCENE, "OutpostCampfire", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), fire_pos),
		prop_body, props_root)
	_attach_lantern_from_empty(fire_node, "Lantern_Fire", Color(1.0, 0.56, 0.18), 3.2, 16.0, 0.22, rng.randf() * TAU)

	var campfire_stove := CookingStove.new()
	campfire_stove.name = "CampfireCookingStove"
	campfire_stove.build_hearth = false
	campfire_stove.build_campfire_tripod = true
	campfire_stove.position = fire_pos
	campfire_stove.rotation.y = dock_yaw + 0.35
	props_root.add_child(campfire_stove)
	campfire_cooking_stove = campfire_stove

	# 7. Quartermaster Supply Crates & Barrels on dry golden sand beside the dock ramp head.
	var qm_v := -21.2
	var qm_pos: Vector3 = harbour_pt.call(-3.9, qm_v)
	for _dry_step in 4:
		if surface_height(qm_pos.x, qm_pos.z) >= 0.72:
			break
		qm_v += 0.5
		qm_pos = harbour_pt.call(-3.9, qm_v)
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
		[BARREL_SCENE, "DockBarrel_A", -3.0, qm_v + 0.6, 0.4],
		[BARREL_SCENE, "DockBarrel_B", -4.8, qm_v + 0.2, 1.8],
		[CRATE_SCENE, "StallCrate_A", 12.2, -16.8, -0.5],
		[BARREL_SCENE, "TavernBarrel_A", -5.4, -10.8, 0.9],
		[CRATE_SCENE, "TavernCrate_A", -4.4, -9.8, 0.2],
	]
	for spec in clutter_specs:
		var cp: Vector3 = harbour_pt.call(float(spec[2]), float(spec[3]))
		cp.y = surface_height(cp.x, cp.z)
		var cxform := Transform3D(Basis(Vector3.UP, dock_yaw + float(spec[4])), cp)
		_place_outpost_prop(spec[0] as PackedScene, String(spec[1]), cxform, prop_body, props_root)

	# 8. Interactive Sculpted Tavern Porch Grog Keg right beside the Tavern front steps!
	var keg_pos: Vector3 = tav_xform * Vector3(2.75, 0.0, -6.55)
	keg_pos.y = surface_height(keg_pos.x, keg_pos.z)
	var keg_xform := Transform3D(Basis(Vector3.UP, dock_yaw + 0.24), keg_pos)
	_build_tavern_grog_keg(keg_xform, prop_body, props_root)

	# 9. Festive overhead wind-blown nautical bunting garlands across the harbour plaza (1 batched draw call!).
	_build_harbour_bunting(dock_local_transform, stall_xform, tav_xform, nb_xform, props_root)

	# 10. Living Outpost Harbour NPCs (Merchant Factor, Pier Quartermaster & Campfire Shanty Bard).
	var merch_pos: Vector3 = harbour_pt.call(7.6, -18.8)
	merch_pos.y = surface_height(merch_pos.x, merch_pos.z)
	_spawn_harbour_npc(
		"MerchantFactorNPC", props_root, merch_pos, dock_yaw + PI * 0.45,
		&"captain", Color(0.56, 0.14, 0.16), Color(0.92, 0.74, 0.24), rng.randf() * TAU)

	var qm_npc_pos: Vector3 = harbour_pt.call(-5.3, qm_v)
	qm_npc_pos.y = surface_height(qm_npc_pos.x, qm_npc_pos.z)
	_spawn_harbour_npc(
		"QuartermasterNPC", props_root, qm_npc_pos, dock_yaw - 0.55,
		&"carpenter", Color(0.14, 0.44, 0.46), Color(0.88, 0.62, 0.20), rng.randf() * TAU)

	var bard_pos: Vector3 = harbour_pt.call(3.6, -13.2)
	bard_pos.y = surface_height(bard_pos.x, bard_pos.z)
	var to_fire := fire_pos - bard_pos
	to_fire.y = 0.0
	var bard_yaw := atan2(-to_fire.x, -to_fire.z) if to_fire.length_squared() > 0.001 else dock_yaw + 0.65
	tavern_bard_node = _spawn_harbour_npc(
		"TavernBardNPC", props_root, bard_pos, bard_yaw,
		&"lookout", Color(0.74, 0.16, 0.14), Color(0.95, 0.74, 0.22), rng.randf() * TAU,
		&"instrument")
	tavern_bard_interactable = Interactable.create("Request a tavern shanty", 1.1)
	tavern_bard_interactable.name = "TavernBardInteractable"
	tavern_bard_interactable.reach = 2.8
	tavern_bard_interactable.position = Vector3(0.0, 1.05, 0.0)
	tavern_bard_interactable.target = self
	tavern_bard_interactable.interacted.connect(func(p: Node) -> void:
		toggle_tavern_bard_shanty(p)
	)
	tavern_bard_node.add_child(tavern_bard_interactable)


## Toggle the campfire TavernBardNPC's 3D-spatialized hearthside shanty & golden rising musical motes.
func toggle_tavern_bard_shanty(_pawn: Node = null) -> bool:
	tavern_bard_playing = not tavern_bard_playing
	if tavern_bard_playing:
		if tavern_bard_interactable != null and is_instance_valid(tavern_bard_interactable):
			tavern_bard_interactable.prompt = "Silence tavern shanty"
		if Audio != null:
			Audio.play_shanty([&"concertina", &"whistle"])
			if tavern_bard_node != null and is_instance_valid(tavern_bard_node):
				Audio.set_shanty_emitter(&"concertina", tavern_bard_node)
		_attach_bard_shanty_motes()
		if Game != null:
			Game.post_notice("Tavern Bard: Raise a tankard, Captain - here's a shanty for the harbour!")
	else:
		if tavern_bard_interactable != null and is_instance_valid(tavern_bard_interactable):
			tavern_bard_interactable.prompt = "Request a tavern shanty"
		if Audio != null:
			Audio.set_shanty_emitter(&"concertina", null)
			Audio.stop_shanty(0.5)
		_detach_bard_shanty_motes(true)
	return tavern_bard_playing


## Toll the sculpted seaward harbour pier fog-bell, impulse its damped harmonic
## pendulum swing, play spatial bronze chime audio, post a harbour greeting, and emit `pier_bell_rung`.
func ring_pier_bell(pawn: Node = null) -> void:
	_pier_bell_vel += 9.2
	if pier_bell_pivot != null and is_instance_valid(pier_bell_pivot):
		_pier_bell_angle = clampf(_pier_bell_angle + 0.04, -0.78, 0.78)
		pier_bell_pivot.rotation.x = _pier_bell_angle
	var sfx_pos := global_position
	if pier_bell_node != null and is_instance_valid(pier_bell_node) and pier_bell_node.is_inside_tree():
		sfx_pos = pier_bell_node.global_position
	if Audio != null:
		var sfx_id := &"ship_bell" if Audio.has_sound(&"ship_bell") else &"parry_ring"
		Audio.play_sfx(sfx_id, sfx_pos, -1.0 if sfx_id == &"ship_bell" else -4.0, 0.04)
	if Game != null:
		var harbour_name := display_name if not display_name.is_empty() else "the harbour"
		Game.post_notice("Harbour fog-bell tolls across %s! Fair winds, Captain!" % harbour_name)
	pier_bell_rung.emit(pawn)


func _attach_bard_shanty_motes() -> void:
	_detach_bard_shanty_motes(true)
	if tavern_bard_node == null or not is_instance_valid(tavern_bard_node):
		return
	var p := _build_bard_shanty_motes()
	tavern_bard_node.add_child(p)
	_bard_shanty_motes = p


func _detach_bard_shanty_motes(detach_from_parent: bool = true) -> void:
	if _bard_shanty_motes != null and is_instance_valid(_bard_shanty_motes):
		_bard_shanty_motes.emitting = false
		_bard_shanty_motes.visible = false
		_bard_shanty_motes.draw_pass_1 = null
		_bard_shanty_motes.process_material = null
		if detach_from_parent and _bard_shanty_motes.get_parent() != null:
			_bard_shanty_motes.get_parent().remove_child(_bard_shanty_motes)
		_bard_shanty_motes.queue_free()
	_bard_shanty_motes = null


static func _build_bard_shanty_motes() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "BardShantyMotes"
	p.position = Vector3(0.0, 1.38, -0.24)
	p.amount = 8
	p.lifetime = 1.45
	p.explosiveness = 0.16
	p.randomness = 0.35
	p.local_coords = false
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3.0, 3.0, 3.0))

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.24
	proc.direction = Vector3(0.0, 1.0, 0.0)
	proc.spread = 36.0
	proc.initial_velocity_min = 0.28
	proc.initial_velocity_max = 0.62
	proc.gravity = Vector3(0.0, 0.18, 0.0)
	proc.damping_min = 0.35
	proc.damping_max = 0.65
	proc.scale_min = 0.55
	proc.scale_max = 1.10
	var sc_curve := Curve.new()
	sc_curve.add_point(Vector2(0.0, 0.25))
	sc_curve.add_point(Vector2(0.28, 1.0))
	sc_curve.add_point(Vector2(1.0, 0.05))
	var sc_tex := CurveTexture.new()
	sc_tex.curve = sc_curve
	proc.scale_curve = sc_tex
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.22, 0.68, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.94, 0.68, 0.0),
		Color(1.0, 0.85, 0.38, 0.78),
		Color(1.0, 0.68, 0.22, 0.42),
		Color(0.95, 0.50, 0.12, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.width = 24
	ramp.gradient = grad
	proc.color_ramp = ramp
	p.process_material = proc

	var radial_grad := Gradient.new()
	radial_grad.offsets = PackedFloat32Array([0.0, 0.38, 0.76, 1.0])
	radial_grad.colors = PackedColorArray([
		Color(1.0, 0.98, 0.86, 1.0),
		Color(1.0, 0.88, 0.44, 0.68),
		Color(1.0, 0.70, 0.24, 0.18),
		Color(1.0, 0.55, 0.12, 0.0),
	])
	var mote_tex := GradientTexture2D.new()
	mote_tex.width = 24
	mote_tex.height = 24
	mote_tex.fill = GradientTexture2D.FILL_RADIAL
	mote_tex.fill_from = Vector2(0.5, 0.5)
	mote_tex.fill_to = Vector2(0.5, 0.0)
	mote_tex.gradient = radial_grad

	# Zero-primitive sculpted 2-triangle billboard ArrayMesh card.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 0.055
	var n := Vector3(0.0, 0.0, 1.0)
	var v0 := Vector3(-h, -h, 0.0)
	var v1 := Vector3(h, -h, 0.0)
	var v2 := Vector3(h, h, 0.0)
	var v3 := Vector3(-h, h, 0.0)
	st.set_normal(n); st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(v0)
	st.set_normal(n); st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(v1)
	st.set_normal(n); st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(v2)
	st.set_normal(n); st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(v0)
	st.set_normal(n); st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(v2)
	st.set_normal(n); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(v3)
	var card_mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = mote_tex
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	card_mesh.surface_set_material(0, mat)
	p.draw_pass_1 = card_mesh
	p.emitting = true
	return p


func _spawn_harbour_npc(npc_name: String, parent_node: Node3D, local_pos: Vector3, yaw_rad: float,
		arch: StringName, primary: Color, accent: Color, phase: float,
		instrument_id: StringName = &"") -> Node3D:
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
	var npc_entry: Dictionary = {
		"visual": cv,
		"driver": drv,
		"phase": phase,
		"primary": primary,
		"accent": accent,
		"bound": false,
		"instrument_id": instrument_id,
		"instrument_node": null,
		"action_timer": 0.0,
	}
	_try_bind_harbour_npc(npc_entry)
	_harbour_npcs.append(npc_entry)
	return holder


func _try_bind_harbour_npc(npc: Dictionary) -> bool:
	var drv := npc.get("driver") as AnimationDriver
	var cv := npc.get("visual") as CharacterVisual
	if drv == null or not is_instance_valid(drv) or cv == null or not is_instance_valid(cv):
		return false
	if cv.skeleton == null:
		return false
	drv.bind(cv)
	cv.set_tint(npc.get("primary") as Color, npc.get("accent") as Color)
	var inst_id: StringName = npc.get("instrument_id", &"") as StringName
	if inst_id != &"" and cv.hand_right != null and is_instance_valid(cv.hand_right):
		var existing := npc.get("instrument_node") as Node3D
		if existing == null or not is_instance_valid(existing):
			var prop := ToolMeshes.build_tool(inst_id)
			prop.name = "ShantyInstrument_" + String(inst_id)
			if inst_id == &"hurdy_gurdy":
				prop.position = Vector3(-0.05, 0.13, -0.09)
				prop.rotation_degrees = Vector3(8.0, -14.0, -84.0)
			else:
				prop.position = Vector3(-0.04, 0.08, -0.08)
				prop.rotation_degrees = Vector3(12.0, -18.0, -78.0)
			prop.scale = Vector3.ONE * 0.95
			cv.hand_right.add_child(prop)
			npc["instrument_node"] = prop
		drv.play_action(&"play_instrument", 1.60)
		npc["action_timer"] = 1.54
	npc["bound"] = true
	return true


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


func _on_tavern_keg_interacted(pawn: Node) -> void:
	if not Net.is_host():
		return
	if pawn is Pawn:
		(pawn as Pawn).heal(TAVERN_KEG_HEAL)
	var sfx_pos := global_position
	if tavern_keg_interactable != null and is_instance_valid(tavern_keg_interactable) and tavern_keg_interactable.is_inside_tree():
		sfx_pos = tavern_keg_interactable.global_position
	Audio.play_sfx(&"grog_gulp", sfx_pos, -1.5)
	var toast := TAVERN_TOASTS[_toast_index % TAVERN_TOASTS.size()]
	_toast_index += 1
	Game.post_notice(toast)
	tavern_toast.emit(pawn)


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
	_ensure_shared_outpost_assets()
	var marker := beacon_root.find_child("Lantern_Beacon", true, false) as Node3D
	var local_pos := Vector3(0.0, 17.8, 0.0)
	if marker != null:
		local_pos = _relative_transform(marker, beacon_root).origin
	var halo := MeshInstance3D.new()
	halo.name = "BeaconGlowCore"
	halo.mesh = _beacon_halo_mesh
	halo.position = local_pos
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.material_override = _beacon_halo_mat
	beacon_root.add_child(halo)

	# Rotating opposing dual-cone volumetric lighthouse beam mounted right at the Fresnel lantern aperture!
	beacon_beam = MeshInstance3D.new()
	beacon_beam.name = "LighthouseBeam"
	beacon_beam.mesh = _beacon_beam_mesh
	beacon_beam.position = local_pos
	beacon_beam.rotation.y = fposmod(absf(dock_yaw) * 2.1 + 0.65, TAU)
	beacon_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beacon_beam.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	beacon_beam.extra_cull_margin = 80.0
	beacon_beam.material_override = _beacon_beam_mat
	beacon_beam.visible = false
	beacon_root.add_child(beacon_beam)
	_update_beacon_beam(0.0)


func _update_beacon_beam(delta: float) -> void:
	if beacon_beam == null or not is_instance_valid(beacon_beam):
		return
	var night := 1.0 - Weather.daylight()
	var storm_mist := smoothstep(0.32, 0.82, Weather.storminess)
	var target_beam := clampf(maxf(night * 1.15, storm_mist * 0.85), 0.0, 1.15)
	if target_beam > 0.02:
		beacon_beam.visible = true
		beacon_beam.rotation.y = wrapf(beacon_beam.rotation.y + delta * 0.42, 0.0, TAU)
		if _beacon_beam_mat != null:
			_beacon_beam_mat.set_shader_parameter(&"beam_intensity", target_beam)
	else:
		beacon_beam.visible = false
		if _beacon_beam_mat != null:
			_beacon_beam_mat.set_shader_parameter(&"beam_intensity", 0.0)


# ------------------------------------------------------------------ Interactive Tavern Grog Keg

func _build_tavern_grog_keg(keg_xform: Transform3D, prop_body: StaticBody3D, props_root: Node3D) -> void:
	_ensure_shared_outpost_assets()

	tavern_keg_node = Node3D.new()
	tavern_keg_node.name = "TavernGrogKeg"
	tavern_keg_node.transform = keg_xform
	props_root.add_child(tavern_keg_node)

	var keg_mi := MeshInstance3D.new()
	keg_mi.name = "TavernGrogKegMesh"
	keg_mi.mesh = _keg_mesh
	keg_mi.material_override = _keg_mat
	tavern_keg_node.add_child(keg_mi)

	# Solid low-profile collider so captains walk neatly up to the tap without clipping through.
	if prop_body != null:
		var cs := CollisionShape3D.new()
		cs.name = "Col_TavernGrogKeg"
		var box := BoxShape3D.new()
		box.size = Vector3(0.84, 1.12, 1.10)
		cs.shape = box
		cs.transform = keg_xform * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.56, -0.04))
		prop_body.add_child(cs)

	tavern_keg_interactable = Interactable.create("Tap tavern grog keg", 1.1)
	tavern_keg_interactable.name = "TavernGrogKegInteractable"
	tavern_keg_interactable.position = Vector3(0.0, 0.85, -0.32)
	tavern_keg_interactable.reach = 3.0
	tavern_keg_interactable.target = self
	tavern_keg_interactable.interacted.connect(_on_tavern_keg_interacted)
	tavern_keg_node.add_child(tavern_keg_interactable)


# ------------------------------------------------------------------ Swinging Carved Tavern Signboard

func _build_tavern_signboard(sign_xform: Transform3D, props_root: Node3D, rng: RandomNumberGenerator) -> void:
	_ensure_shared_outpost_assets()

	tavern_sign_node = Node3D.new()
	tavern_sign_node.name = "TavernSignboard"
	tavern_sign_node.transform = sign_xform
	props_root.add_child(tavern_sign_node)

	_tavern_sign_bracket_mi = MeshInstance3D.new()
	_tavern_sign_bracket_mi.name = "TavernSignBracket"
	_tavern_sign_bracket_mi.mesh = _tavern_sign_bracket_mesh
	_tavern_sign_bracket_mi.material_override = _tavern_sign_iron_mat
	tavern_sign_node.add_child(_tavern_sign_bracket_mi)

	tavern_sign_pivot = Node3D.new()
	tavern_sign_pivot.name = "TavernSignPivot"
	tavern_sign_pivot.position = Vector3(0.0, -0.16, -0.56)
	tavern_sign_node.add_child(tavern_sign_pivot)

	_tavern_sign_board_mi = MeshInstance3D.new()
	_tavern_sign_board_mi.name = "TavernSignBoard"
	_tavern_sign_board_mi.mesh = _tavern_sign_board_mesh
	_tavern_sign_board_mi.material_override = _tavern_sign_board_mat
	tavern_sign_pivot.add_child(_tavern_sign_board_mi)

	_tavern_sign_face_mi = MeshInstance3D.new()
	_tavern_sign_face_mi.name = "TavernSignFace"
	_tavern_sign_face_mi.mesh = _tavern_sign_face_mesh
	_tavern_sign_face_mi.material_override = _tavern_sign_face_mat
	tavern_sign_pivot.add_child(_tavern_sign_face_mi)

	_tavern_sign_phase = rng.randf() * TAU

	# Soft warm porch-doorway spill light kissing the tavern signboard & front porch at dusk/night.
	_tavern_sign_light = OmniLight3D.new()
	_tavern_sign_light.name = "TavernSignSpillLight"
	_tavern_sign_light.light_color = Color(1.0, 0.70, 0.32)
	_tavern_sign_light.light_energy = 1.45
	_tavern_sign_light.omni_range = 8.0
	_tavern_sign_light.omni_attenuation = 1.5
	_tavern_sign_light.shadow_enabled = false
	_tavern_sign_light.position = Vector3(0.18, -0.42, -0.95)
	tavern_sign_node.add_child(_tavern_sign_light)
	register_flicker_light(_tavern_sign_light, 1.45, 0.08, rng.randf() * TAU)


# ------------------------------------------------------------------ Interactive Seaward Pier Fog-Bell

func _build_pier_fog_bell(bell_xform: Transform3D, props_root: Node3D) -> void:
	_ensure_shared_outpost_assets()

	pier_bell_node = Node3D.new()
	pier_bell_node.name = "PierFogBell"
	pier_bell_node.transform = bell_xform
	props_root.add_child(pier_bell_node)

	_pier_bell_frame_mi = MeshInstance3D.new()
	_pier_bell_frame_mi.name = "PierBellFrame"
	_pier_bell_frame_mi.mesh = _pier_bell_frame_mesh
	_pier_bell_frame_mi.material_override = _pier_bell_iron_mat
	pier_bell_node.add_child(_pier_bell_frame_mi)

	pier_bell_pivot = Node3D.new()
	pier_bell_pivot.name = "PierBellPivot"
	pier_bell_pivot.position = Vector3(0.0, 0.56, 0.0)
	pier_bell_node.add_child(pier_bell_pivot)

	_pier_bell_cup_mi = MeshInstance3D.new()
	_pier_bell_cup_mi.name = "PierBellCup"
	_pier_bell_cup_mi.mesh = _pier_bell_cup_mesh
	_pier_bell_cup_mi.material_override = _pier_bell_bronze_mat
	pier_bell_pivot.add_child(_pier_bell_cup_mi)

	pier_bell_interactable = Interactable.create("Ring harbour fog-bell", 0.72)
	pier_bell_interactable.name = "PierFogBellInteractable"
	pier_bell_interactable.position = Vector3(0.0, 0.36, 0.0)
	pier_bell_interactable.reach = 2.4
	pier_bell_interactable.target = self
	pier_bell_interactable.interacted.connect(func(p: Node) -> void:
		ring_pier_bell(p)
	)
	pier_bell_node.add_child(pier_bell_interactable)


# ------------------------------------------------------------------ Wind-Blown Harbour Bunting (1 Draw Call)

func _build_harbour_bunting(dock_xform: Transform3D, stall_xform: Transform3D,
		tav_xform: Transform3D, nb_xform: Transform3D, props_root: Node3D) -> void:
	# 4 real harbour architectural anchors framing the entire plaza canopy:
	#   0: Pier Approach festoon post (starboard ramp head)
	#   1: Merchant Stall front-left corner timber mast
	#   2: Outpost Tavern right front crimson gable bargeboard beam
	#   3: Voyage Notice Board / Dock West festoon post
	var pier_base := dock_xform * Vector3(1.66, 0.0, 0.28)
	var pier_ground := surface_height(pier_base.x, pier_base.z)
	var anchor_pier := Vector3(pier_base.x, maxf(pier_ground + 5.35, 5.75), pier_base.z)

	var stall_base := stall_xform * Vector3(-2.22, 0.0, -1.15)
	var stall_ground := surface_height(stall_base.x, stall_base.z)
	var anchor_stall := Vector3(stall_base.x, maxf(stall_ground, stall_xform.origin.y) + 5.35, stall_base.z)

	var tav_gable := tav_xform * Vector3(5.58, 6.04, -1.34)
	var tav_ground := surface_height(tav_gable.x, tav_gable.z)
	var anchor_tav := Vector3(tav_gable.x, maxf(tav_gable.y, tav_ground + 5.50), tav_gable.z)

	var nb_base := nb_xform * Vector3(1.12, 0.0, -0.15)
	var nb_ground := surface_height(nb_base.x, nb_base.z)
	var anchor_nb := Vector3(nb_base.x, maxf(nb_ground, nb_xform.origin.y) + 5.35, nb_base.z)

	var anchors: Array[Vector3] = [anchor_pier, anchor_stall, anchor_tav, anchor_nb]
	# Three festive overhead garlands: [idx_a, idx_b, catenary_sag]
	var spans: Array[Array] = [
		[0, 1, 0.58],  # Pier Approach -> Merchant Stall
		[1, 2, 0.85],  # Merchant Stall -> Tavern Gable (sweeps across Harbour Campfire plaza)
		[2, 3, 0.56],  # Tavern Gable -> Notice Board / Dock West post
	]

	# Guarantee every point along every sagging catenary stays strictly >= 4.75 m above terrain
	# so even the lowest dangling pennant tips hang cleanly >= 4.25 m overhead!
	for span in spans:
		var ia: int = int(span[0])
		var ib: int = int(span[1])
		var sag: float = float(span[2])
		var pa := anchors[ia]
		var pb := anchors[ib]
		var min_clear := INF
		for si in 17:
			var t := float(si) / 16.0
			var pt := _eval_catenary(pa, pb, sag, t)
			min_clear = minf(min_clear, pt.y - surface_height(pt.x, pt.z))
		if min_clear < MIN_BUNTING_ROPE_CLEARANCE:
			var lift := (MIN_BUNTING_ROPE_CLEARANCE - min_clear) + 0.08
			anchors[ia].y += lift
			anchors[ib].y += lift

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Three chunky weathered dark-oak harbour festoon posts with iron collars & brass finials (UV.y = 0 pinned).
	_append_festoon_post(st, Vector3(pier_base.x, minf(pier_ground, 0.2) - 1.2, pier_base.z), anchors[0])
	_append_festoon_post(st, Vector3(stall_base.x, stall_ground - 0.6, stall_base.z), anchors[1])
	_append_festoon_post(st, Vector3(nb_base.x, nb_ground - 0.7, nb_base.z), anchors[3])

	# 2. Three sagging hemp catenary ropes + crisp fluttering maritime triangular pennants!
	var color_idx := 0
	for g_idx in spans.size():
		var span: Array = spans[g_idx]
		var pa := anchors[int(span[0])]
		var pb := anchors[int(span[1])]
		var sag: float = float(span[2])
		color_idx = _append_bunting_garland(st, pa, pb, sag, g_idx, color_idx)

	st.generate_normals()
	var bunting_mesh := st.commit()

	_bunting_mat = ShaderMaterial.new()
	_bunting_mat.shader = BUNTING_SHADER
	_bunting_mat.set_shader_parameter(&"wind_dir", Vector2(0.707, -0.707))
	_bunting_mat.set_shader_parameter(&"wind_speed", 6.5)
	_bunting_mat.set_shader_parameter(&"wind_time", 0.0)
	_bunting_mat.set_shader_parameter(&"flutter_strength", 1.0)

	harbour_bunting = MeshInstance3D.new()
	harbour_bunting.name = "HarbourBunting"
	harbour_bunting.mesh = bunting_mesh
	harbour_bunting.material_override = _bunting_mat
	harbour_bunting.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	props_root.add_child(harbour_bunting)


static func _eval_catenary(a: Vector3, b: Vector3, sag: float, t: float) -> Vector3:
	var p := a.lerp(b, t)
	p.y -= 4.0 * sag * t * (1.0 - t)
	return p


static func _append_festoon_post(st: SurfaceTool, base_pt: Vector3, top_pt: Vector3) -> void:
	# Chunky 6-sided tapered weathered oak mast with forged iron collar & golden finial cap.
	var shaft_top := top_pt + Vector3(0.0, 0.16, 0.0)
	_append_tapered_prism(st, base_pt, shaft_top, 0.115, 0.082, 6, COL_POST_OAK, COL_POST_OAK.lightened(0.08), Vector2.ZERO)
	# Forged iron mooring band right where the bunting ropes tie off.
	_append_tapered_prism(st, top_pt - Vector3(0.0, 0.08, 0.0), top_pt + Vector3(0.0, 0.08, 0.0),
		0.094, 0.094, 6, COL_POST_IRON, COL_POST_IRON, Vector2.ZERO)
	# Beveled warm brass finial cap crowning the post.
	_append_tapered_prism(st, shaft_top, shaft_top + Vector3(0.0, 0.18, 0.0),
		0.088, 0.020, 6, COL_POST_BRASS, COL_POST_BRASS.lightened(0.12), Vector2.ZERO)


static func _append_bunting_garland(st: SurfaceTool, a: Vector3, b: Vector3, sag: float,
		garland_idx: int, start_color_idx: int) -> int:
	# 1. Sagging 4-sided hemp rope between anchor A and anchor B.
	const ROPE_SEGS := 14
	const ROPE_R := 0.022
	var rope_rings: Array[Array] = []
	var rope_ctrs: Array[Vector3] = []
	var rope_uvs: Array[Vector2] = []

	for i in range(ROPE_SEGS + 1):
		var t := float(i) / float(ROPE_SEGS)
		var pt := _eval_catenary(a, b, sag, t)
		var pt_prev := _eval_catenary(a, b, sag, maxf(0.0, t - 0.02))
		var pt_next := _eval_catenary(a, b, sag, minf(1.0, t + 0.02))
		var tang := (pt_next - pt_prev).normalized()
		var side := tang.cross(Vector3.UP)
		if side.length_squared() < 0.001:
			side = Vector3.RIGHT
		else:
			side = side.normalized()
		var up_v := side.cross(tang).normalized()
		# Subtle mid-span rope sway (0.0 strictly pinned at both ends, 0.08 max at center).
		var rope_w := sin(t * PI) * 0.08
		rope_uvs.append(Vector2(fmod(t + float(garland_idx) * 0.31, 1.0), rope_w))
		rope_rings.append([
			pt + up_v * ROPE_R,
			pt + side * ROPE_R,
			pt - up_v * ROPE_R,
			pt - side * ROPE_R,
		])
		rope_ctrs.append(pt)

	for i in ROPE_SEGS:
		var r0: Array = rope_rings[i]
		var r1: Array = rope_rings[i + 1]
		var ctr := (rope_ctrs[i] + rope_ctrs[i + 1]) * 0.5
		var uv0 := rope_uvs[i]
		var uv1 := rope_uvs[i + 1]
		for k in 4:
			var nk := (k + 1) % 4
			_add_outward_quad_uv(st, r0[k], r1[k], r1[nk], r0[nk], ctr,
				COL_ROPE_HEMP, COL_ROPE_HEMP, COL_ROPE_HEMP, COL_ROPE_HEMP,
				uv0, uv1, uv1, uv0)

	# 2. Crisp alternating triangular maritime cloth pennants hanging along the catenary.
	var span_len := a.distance_to(b)
	var pennant_count := clampi(int(roundf(span_len / 0.68)), 8, 24)
	var margin_t := clampf(0.45 / maxf(span_len, 2.0), 0.03, 0.10)
	var usable_t := 1.0 - margin_t * 2.0
	var c_idx := start_color_idx

	for pi in pennant_count:
		var f0 := margin_t + usable_t * (float(pi) + 0.08) / float(pennant_count)
		var f1 := margin_t + usable_t * (float(pi) + 0.92) / float(pennant_count)
		var fm := 0.5 * (f0 + f1)
		var top_l := _eval_catenary(a, b, sag, f0) - Vector3(0.0, 0.015, 0.0)
		var top_r := _eval_catenary(a, b, sag, f1) - Vector3(0.0, 0.015, 0.0)
		var mid_top := _eval_catenary(a, b, sag, fm) - Vector3(0.0, 0.015, 0.0)
		var penn_len := 0.44 + (0.04 if pi % 2 == 0 else 0.0)
		var tip := mid_top + Vector3(0.0, -penn_len, 0.0)
		var ml := top_l.lerp(tip, 0.48)
		var mr := top_r.lerp(tip, 0.48)

		var col := BUNTING_PALETTE[c_idx % BUNTING_PALETTE.size()]
		var col_hem := col.darkened(0.09)
		var col_tip := col.lightened(0.05)
		c_idx += 1

		var phase_u := fmod(float(pi) * 0.17 + float(garland_idx) * 0.37, 1.0)
		var uv_pin := Vector2(phase_u, 0.0)
		var uv_mid := Vector2(phase_u, 0.46)
		var uv_tip := Vector2(phase_u, 1.0)

		# 3-triangle subdivided cloth pennant so fabric bends gracefully from pinned rope edge to tip.
		_add_flat_tri_uv(st, top_l, top_r, mr, col_hem, col_hem, col, uv_pin, uv_pin, uv_mid)
		_add_flat_tri_uv(st, top_l, mr, ml, col_hem, col, col, uv_pin, uv_mid, uv_mid)
		_add_flat_tri_uv(st, ml, mr, tip, col, col, col_tip, uv_mid, uv_mid, uv_tip)

	return c_idx


# ------------------------------------------------------------------ Shared Procedural Outpost Meshes

static func _ensure_shared_outpost_assets() -> void:
	if _keg_mat == null:
		_keg_mat = StandardMaterial3D.new()
		_keg_mat.vertex_color_use_as_albedo = true
		_keg_mat.vertex_color_is_srgb = true
		_keg_mat.roughness = 0.68
		_keg_mat.metallic = 0.08
	if _keg_mesh == null:
		_keg_mesh = _build_tavern_grog_keg_mesh()

	if _beacon_halo_mat == null:
		_beacon_halo_mat = StandardMaterial3D.new()
		_beacon_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beacon_halo_mat.albedo_color = Color(1.0, 0.86, 0.50)
		_beacon_halo_mat.emission_enabled = true
		_beacon_halo_mat.emission = Color(1.0, 0.72, 0.25)
		_beacon_halo_mat.emission_energy_multiplier = 4.5
	if _beacon_halo_mesh == null:
		_beacon_halo_mesh = _build_beacon_halo_mesh()
	if _beacon_beam_mat == null:
		_beacon_beam_mat = ShaderMaterial.new()
		_beacon_beam_mat.shader = LIGHTHOUSE_BEAM_SHADER
		_beacon_beam_mat.set_shader_parameter(&"beam_color", Color(1.0, 0.80, 0.38))
		_beacon_beam_mat.set_shader_parameter(&"beam_intensity", 0.0)
	if _beacon_beam_mesh == null:
		_beacon_beam_mesh = _build_beacon_beam_mesh()

	if _tavern_sign_iron_mat == null:
		_tavern_sign_iron_mat = StandardMaterial3D.new()
		_tavern_sign_iron_mat.vertex_color_use_as_albedo = true
		_tavern_sign_iron_mat.vertex_color_is_srgb = true
		_tavern_sign_iron_mat.roughness = 0.46
		_tavern_sign_iron_mat.metallic = 0.74
	if _tavern_sign_board_mat == null:
		_tavern_sign_board_mat = StandardMaterial3D.new()
		_tavern_sign_board_mat.vertex_color_use_as_albedo = true
		_tavern_sign_board_mat.vertex_color_is_srgb = true
		_tavern_sign_board_mat.roughness = 0.56
		_tavern_sign_board_mat.metallic = 0.18
	if _tavern_sign_albedo_tex == null or _tavern_sign_emit_tex == null:
		var painted: Array[ImageTexture] = _paint_tavern_sign_textures()
		_tavern_sign_albedo_tex = painted[0]
		_tavern_sign_emit_tex = painted[1]
	if _tavern_sign_face_mat == null:
		_tavern_sign_face_mat = StandardMaterial3D.new()
		_tavern_sign_face_mat.albedo_color = Color.WHITE
		_tavern_sign_face_mat.albedo_texture = _tavern_sign_albedo_tex
		_tavern_sign_face_mat.roughness = 0.40
		_tavern_sign_face_mat.metallic = 0.20
		_tavern_sign_face_mat.emission_enabled = true
		_tavern_sign_face_mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		_tavern_sign_face_mat.emission = Color(1.0, 0.86, 0.48)
		_tavern_sign_face_mat.emission_texture = _tavern_sign_emit_tex
		_tavern_sign_face_mat.emission_energy_multiplier = 0.48
	if _tavern_sign_bracket_mesh == null:
		_tavern_sign_bracket_mesh = _build_tavern_sign_bracket_mesh()
	if _tavern_sign_board_mesh == null:
		_tavern_sign_board_mesh = _build_tavern_sign_board_mesh()
	if _tavern_sign_face_mesh == null:
		_tavern_sign_face_mesh = _build_tavern_sign_face_mesh()

	if _pier_bell_iron_mat == null:
		_pier_bell_iron_mat = StandardMaterial3D.new()
		_pier_bell_iron_mat.vertex_color_use_as_albedo = true
		_pier_bell_iron_mat.vertex_color_is_srgb = true
		_pier_bell_iron_mat.roughness = 0.48
		_pier_bell_iron_mat.metallic = 0.72
	if _pier_bell_bronze_mat == null:
		_pier_bell_bronze_mat = StandardMaterial3D.new()
		_pier_bell_bronze_mat.vertex_color_use_as_albedo = true
		_pier_bell_bronze_mat.vertex_color_is_srgb = true
		_pier_bell_bronze_mat.roughness = 0.34
		_pier_bell_bronze_mat.metallic = 0.80
	if _pier_bell_frame_mesh == null:
		_pier_bell_frame_mesh = _build_pier_bell_frame_mesh()
	if _pier_bell_cup_mesh == null:
		_pier_bell_cup_mesh = _build_pier_bell_cup_mesh()


static func _build_tavern_grog_keg_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Curved dark-oak timber trestle cradle (two splayed end frames + tie beams).
	var barrel_cy := 0.72
	for sz: float in [-0.26, 0.26]:
		# Left & right splayed oak trestle legs grounded cleanly below y = 0.
		for sx: float in [-1.0, 1.0]:
			_append_tapered_prism(
				st,
				Vector3(sx * 0.36, -0.14, sz),
				Vector3(sx * 0.28, 0.54, sz),
				0.068, 0.056, 4, COL_KEG_CRADLE, COL_KEG_CRADLE.lightened(0.06), Vector2.ZERO
			)
		# Sculpted curved timber saddle block cradling the horizontal barrel belly.
		const SADDLE_SEGS := 6
		for si in SADDLE_SEGS:
			var a0 := lerpf(-0.95, 0.95, float(si) / float(SADDLE_SEGS))
			var a1 := lerpf(-0.95, 0.95, float(si + 1) / float(SADDLE_SEGS))
			var p0 := Vector3(sin(a0) * 0.355, barrel_cy - cos(a0) * 0.355, sz)
			var p1 := Vector3(sin(a1) * 0.355, barrel_cy - cos(a1) * 0.355, sz)
			var mid := (p0 + p1) * 0.5 - Vector3(0.0, 0.05, 0.0)
			var seg_len := p0.distance_to(p1) + 0.02
			var yaw_z := atan2(p1.y - p0.y, p1.x - p0.x)
			_append_box_xform(st, Transform3D(Basis(Vector3.BACK, yaw_z), mid),
				Vector3(seg_len, 0.11, 0.11), COL_KEG_CRADLE)

	# Two longitudinal trestle stretcher beams.
	for sx: float in [-0.28, 0.28]:
		_append_box_xform(st, Transform3D(Basis.IDENTITY, Vector3(sx, 0.18, 0.0)),
			Vector3(0.08, 0.09, 0.62), COL_KEG_CRADLE.lightened(0.05))

	# 2. Horizontal bulging oak grog keg (12 staves along Z, recessed oak heads, 4 iron hoops).
	const STAVES := 12
	var keg_stations: Array[Array] = [
		[-0.46, 0.282],
		[-0.33, 0.336],
		[0.00, 0.366],
		[0.33, 0.336],
		[0.46, 0.282],
	]
	var rings: Array[Array] = []
	for row in keg_stations:
		var z: float = float(row[0])
		var r: float = float(row[1])
		var ring: Array[Vector3] = []
		for k in STAVES:
			var a := float(k) / float(STAVES) * TAU
			ring.append(Vector3(cos(a) * r, barrel_cy + sin(a) * r, z))
		rings.append(ring)

	var stave_cols: Array[Color] = [COL_KEG_OAK_A, COL_KEG_OAK_B, COL_KEG_OAK_C]
	for j in range(rings.size() - 1):
		var r0: Array = rings[j]
		var r1: Array = rings[j + 1]
		var zm := 0.5 * (float(keg_stations[j][0]) + float(keg_stations[j + 1][0]))
		var ctr := Vector3(0.0, barrel_cy, zm)
		for k in STAVES:
			var nk := (k + 1) % STAVES
			var col := stave_cols[k % stave_cols.size()]
			_add_outward_quad(st, r0[k], r1[k], r1[nk], r0[nk], ctr, col, col, col, col)

	# Recessed flat oak barrel heads inside chunky chime rims (front -Z & rear +Z).
	for end_pair: Array in [[-1.0, 0], [1.0, rings.size() - 1]]:
		var sz: float = float(end_pair[0])
		var rim_r: Array = rings[int(end_pair[1])]
		var z_head := sz * 0.432
		var head_ctr := Vector3(0.0, barrel_cy, z_head)
		var ref_in := Vector3(0.0, barrel_cy, sz * 0.28)
		var inner_r: Array[Vector3] = []
		for k in STAVES:
			var a := float(k) / float(STAVES) * TAU
			inner_r.append(Vector3(cos(a) * 0.258, barrel_cy + sin(a) * 0.258, z_head))
		for k in STAVES:
			var nk := (k + 1) % STAVES
			var am := (float(k) + 0.5) / float(STAVES) * TAU
			var rim_ref := Vector3(cos(am) * 0.42, barrel_cy + sin(am) * 0.42, sz * 0.34)
			_add_outward_quad(st, rim_r[k], inner_r[k], inner_r[nk], rim_r[nk],
				rim_ref, COL_KEG_OAK_B, COL_KEG_OAK_B, COL_KEG_OAK_B, COL_KEG_OAK_B)
			_add_outward_tri(st, head_ctr, inner_r[k], inner_r[nk], ref_in,
				COL_KEG_HEAD, COL_KEG_HEAD.darkened(0.06), COL_KEG_HEAD.darkened(0.06))

	# 4 forged dark-iron barrel hoops with beveled side edges wrapping tightly around the oak staves.
	for hoop: Array in [[-0.38, 0.326], [-0.15, 0.365], [0.15, 0.365], [0.38, 0.326]]:
		var hz: float = float(hoop[0])
		var hr: float = float(hoop[1]) + 0.013
		var hr_in: float = float(hoop[1]) - 0.008
		var hw := 0.026
		var h0: Array[Vector3] = []
		var h1: Array[Vector3] = []
		var hi0: Array[Vector3] = []
		var hi1: Array[Vector3] = []
		for k in STAVES:
			var a := float(k) / float(STAVES) * TAU
			var ca := cos(a)
			var sa := sin(a)
			h0.append(Vector3(ca * hr, barrel_cy + sa * hr, hz - hw))
			h1.append(Vector3(ca * hr, barrel_cy + sa * hr, hz + hw))
			hi0.append(Vector3(ca * hr_in, barrel_cy + sa * hr_in, hz - hw))
			hi1.append(Vector3(ca * hr_in, barrel_cy + sa * hr_in, hz + hw))
		var hctr := Vector3(0.0, barrel_cy, hz)
		for k in STAVES:
			var nk := (k + 1) % STAVES
			_add_outward_quad(st, h0[k], h1[k], h1[nk], h0[nk], hctr,
				COL_KEG_IRON, COL_KEG_IRON, COL_KEG_IRON, COL_KEG_IRON)
			_add_outward_quad(st, hi0[k], h0[k], h0[nk], hi0[nk], Vector3(0.0, barrel_cy, hz + 0.04),
				COL_KEG_IRON, COL_KEG_IRON, COL_KEG_IRON, COL_KEG_IRON)
			_add_outward_quad(st, h1[k], hi1[k], hi1[nk], h1[nk], Vector3(0.0, barrel_cy, hz - 0.04),
				COL_KEG_IRON, COL_KEG_IRON, COL_KEG_IRON, COL_KEG_IRON)

	# Chunky oak bung stopper atop the keg.
	_append_tapered_prism(st, Vector3(0.0, barrel_cy + 0.34, 0.12), Vector3(0.0, barrel_cy + 0.41, 0.12),
		0.044, 0.036, 6, COL_KEG_HEAD, COL_KEG_HEAD.lightened(0.08), Vector2.ZERO)

	# 3. Ornate brass front tap spigot protruding from front head (-Z) with T-handle valve!
	var tap_y := barrel_cy - 0.12
	# Hexagonal brass flange collar seated in front head.
	_append_tapered_prism(st, Vector3(0.0, tap_y, -0.41), Vector3(0.0, tap_y, -0.49),
		0.056, 0.038, 6, COL_KEG_BRASS_DARK, COL_KEG_BRASS, Vector2.ZERO)
	# Horizontal brass tap barrel.
	_append_tapered_prism(st, Vector3(0.0, tap_y, -0.48), Vector3(0.0, tap_y, -0.64),
		0.024, 0.020, 6, COL_KEG_BRASS, COL_KEG_BRASS.lightened(0.08), Vector2.ZERO)
	# Downward brass pouring nozzle.
	_append_tapered_prism(st, Vector3(0.0, tap_y + 0.005, -0.625), Vector3(0.0, tap_y - 0.085, -0.645),
		0.020, 0.014, 6, COL_KEG_BRASS, COL_KEG_BRASS_DARK, Vector2.ZERO)
	# Valve stem & chunky brass T-handle.
	_append_tapered_prism(st, Vector3(0.0, tap_y + 0.015, -0.56), Vector3(0.0, tap_y + 0.095, -0.56),
		0.014, 0.012, 6, COL_KEG_BRASS_DARK, COL_KEG_BRASS, Vector2.ZERO)
	_append_box_xform(st, Transform3D(Basis(Vector3.UP, 0.25), Vector3(0.0, tap_y + 0.095, -0.56)),
		Vector3(0.12, 0.024, 0.026), COL_KEG_BRASS.lightened(0.10))

	# 4. Sculpted wooden drip-catch tub beneath the front brass tap with visible amber grog pool!
	var tub_pos := Vector3(0.0, 0.0, -0.63)
	_append_tapered_prism(st, tub_pos + Vector3(0.0, -0.08, 0.0), tub_pos + Vector3(0.0, 0.22, 0.0),
		0.145, 0.180, 8, COL_KEG_OAK_B, COL_KEG_OAK_A, Vector2.ZERO)
	_append_tapered_prism(st, tub_pos + Vector3(0.0, 0.13, 0.0), tub_pos + Vector3(0.0, 0.17, 0.0),
		0.174, 0.179, 8, COL_KEG_IRON, COL_KEG_IRON, Vector2.ZERO)
	_append_tapered_prism(st, tub_pos + Vector3(0.0, 0.215, 0.0), tub_pos + Vector3(0.0, 0.236, 0.0),
		0.162, 0.158, 8, COL_GROG_AMBER, COL_GROG_AMBER.lightened(0.12), Vector2.ZERO)

	# 5. Tiny sculpted pewter grog mug perched jauntily on top of the oak keg!
	var mug_base := Vector3(0.08, barrel_cy + 0.355, -0.14)
	_append_tapered_prism(st, mug_base, mug_base + Vector3(0.0, 0.022, 0.0),
		0.062, 0.056, 8, COL_PEWTER_SHADE, COL_PEWTER, Vector2.ZERO)
	_append_tapered_prism(st, mug_base + Vector3(0.0, 0.020, 0.0), mug_base + Vector3(0.0, 0.168, 0.0),
		0.055, 0.048, 8, COL_PEWTER, COL_PEWTER.lightened(0.08), Vector2.ZERO)
	_append_tapered_prism(st, mug_base + Vector3(0.0, 0.156, 0.0), mug_base + Vector3(0.0, 0.174, 0.0),
		0.053, 0.053, 8, COL_PEWTER_SHADE, COL_PEWTER, Vector2.ZERO)
	# Frothy cream foam cap crowning the mug!
	_append_tapered_prism(st, mug_base + Vector3(0.0, 0.168, 0.0), mug_base + Vector3(0.0, 0.205, 0.0),
		0.046, 0.024, 8, COL_GROG_FOAM, COL_GROG_FOAM.lightened(0.04), Vector2.ZERO)
	# D-shaped pewter mug handle on +X side.
	_append_box_xform(st, Transform3D(Basis.IDENTITY, mug_base + Vector3(0.072, 0.132, 0.0)),
		Vector3(0.048, 0.018, 0.018), COL_PEWTER_SHADE)
	_append_box_xform(st, Transform3D(Basis.IDENTITY, mug_base + Vector3(0.072, 0.052, 0.0)),
		Vector3(0.048, 0.018, 0.018), COL_PEWTER_SHADE)
	_append_box_xform(st, Transform3D(Basis.IDENTITY, mug_base + Vector3(0.092, 0.092, 0.0)),
		Vector3(0.018, 0.096, 0.018), COL_PEWTER)

	st.generate_normals()
	return st.commit()


static func _build_beacon_halo_mesh() -> ArrayMesh:
	# Faceted 1x subdivided crystal icosphere (80 tris, radius = 1.25 m) — zero raw SphereMesh!
	var phi := (1.0 + sqrt(5.0)) * 0.5
	var raw_v: Array[Vector3] = [
		Vector3(-1.0, phi, 0.0), Vector3(1.0, phi, 0.0), Vector3(-1.0, -phi, 0.0), Vector3(1.0, -phi, 0.0),
		Vector3(0.0, -1.0, phi), Vector3(0.0, 1.0, phi), Vector3(0.0, -1.0, -phi), Vector3(0.0, 1.0, -phi),
		Vector3(phi, 0.0, -1.0), Vector3(phi, 0.0, 1.0), Vector3(-phi, 0.0, -1.0), Vector3(-phi, 0.0, 1.0),
	]
	for i in raw_v.size():
		raw_v[i] = raw_v[i].normalized()

	var base_faces: Array[Array] = [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radius := 1.25
	var col := Color(1.0, 0.94, 0.72)

	for f in base_faces:
		var a: Vector3 = raw_v[int(f[0])]
		var b: Vector3 = raw_v[int(f[1])]
		var c: Vector3 = raw_v[int(f[2])]
		var ab := (a + b).normalized()
		var bc := (b + c).normalized()
		var ca := (c + a).normalized()
		_add_outward_tri(st, a * radius, ab * radius, ca * radius, Vector3.ZERO, col, col, col)
		_add_outward_tri(st, b * radius, bc * radius, ab * radius, Vector3.ZERO, col, col, col)
		_add_outward_tri(st, c * radius, ca * radius, bc * radius, Vector3.ZERO, col, col, col)
		_add_outward_tri(st, ab * radius, bc * radius, ca * radius, Vector3.ZERO, col, col, col)

	st.generate_normals()
	return st.commit()


static func _build_beacon_beam_mesh() -> ArrayMesh:
	# Dual opposing open 16-sided volumetric cones shooting along +Z and -Z, pitched -3.5 deg toward the horizon!
	# Uses explicit smooth radial normals & axial UV.y (0.0 at aperture -> 1.0 at 74 m far cone tip) for silky Fresnel edges.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	const SEGS := 16
	const NEAR_DIST := 0.45
	const FAR_DIST := 74.0
	const NEAR_R := 0.55
	const FAR_R := 6.80
	const PITCH_RAD := deg_to_rad(-3.5)
	const RING_TS: Array[float] = [0.0, 0.08, 0.35, 1.0]

	var cos_p := cos(PITCH_RAD)
	var sin_p := sin(PITCH_RAD)
	var slope_tan := (FAR_R - NEAR_R) / (FAR_DIST - NEAR_DIST)
	var cone_cos := 1.0 / sqrt(1.0 + slope_tan * slope_tan)
	var cone_sin := slope_tan * cone_cos

	for sgn: float in [-1.0, 1.0]:
		var axis := Vector3(0.0, sin_p, sgn * cos_p).normalized()
		var right := Vector3(sgn, 0.0, 0.0)
		var up := axis.cross(right).normalized()

		for ri in range(RING_TS.size() - 1):
			var t0: float = RING_TS[ri]
			var t1: float = RING_TS[ri + 1]
			var d0 := lerpf(NEAR_DIST, FAR_DIST, t0)
			var d1 := lerpf(NEAR_DIST, FAR_DIST, t1)
			var r0 := lerpf(NEAR_R, FAR_R, t0)
			var r1 := lerpf(NEAR_R, FAR_R, t1)
			var c0 := axis * d0
			var c1 := axis * d1

			for k in SEGS:
				var u0 := float(k) / float(SEGS)
				var u1 := float(k + 1) / float(SEGS)
				var a0 := u0 * TAU
				var a1 := u1 * TAU
				var rad0 := right * cos(a0) + up * sin(a0)
				var rad1 := right * cos(a1) + up * sin(a1)
				var n0 := (rad0 * cone_cos - axis * cone_sin).normalized()
				var n1 := (rad1 * cone_cos - axis * cone_sin).normalized()

				var p00 := c0 + rad0 * r0
				var p01 := c0 + rad1 * r0
				var p10 := c1 + rad0 * r1
				var p11 := c1 + rad1 * r1

				st.set_normal(n0)
				st.set_uv(Vector2(u0, t0))
				st.add_vertex(p00)
				st.set_normal(n0)
				st.set_uv(Vector2(u0, t1))
				st.add_vertex(p10)
				st.set_normal(n1)
				st.set_uv(Vector2(u1, t1))
				st.add_vertex(p11)

				st.set_normal(n0)
				st.set_uv(Vector2(u0, t0))
				st.add_vertex(p00)
				st.set_normal(n1)
				st.set_uv(Vector2(u1, t1))
				st.add_vertex(p11)
				st.set_normal(n1)
				st.set_uv(Vector2(u1, t0))
				st.add_vertex(p01)

	return st.commit()


# ------------------------------------------------------------------ Tavern Signboard & Pier Fog-Bell Meshes

static func _build_tavern_sign_bracket_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Beveled forged-iron wall mounting plate & 4 chunky forged dome bolts gripping porch fascia.
	_append_box_xform(st, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.06, 0.06)),
		Vector3(0.20, 0.38, 0.045), COL_SIGN_IRON_LO)
	_append_box_xform(st, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.06, 0.036)),
		Vector3(0.165, 0.33, 0.022), COL_SIGN_IRON_HI)
	for bx: float in [-0.062, 0.062]:
		for by: float in [-0.18, 0.06]:
			_append_tapered_prism(st, Vector3(bx, by, 0.042), Vector3(bx, by, 0.012),
				0.020, 0.012, 6, COL_SIGN_IRON_HI, COL_SIGN_IRON_HI.lightened(0.14), Vector2.ZERO)

	# 2. Heavy forged cantilevered arm reaching forward clear of the porch roof lip + curled scroll tip.
	_append_box_xform(st, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.04, -0.32)),
		Vector3(0.046, 0.052, 0.76), COL_SIGN_IRON_HI)
	var tip_scroll: Array[Vector3] = [
		Vector3(0.0, -0.04, -0.68),
		Vector3(0.0, -0.02, -0.76),
		Vector3(0.0, 0.04, -0.80),
		Vector3(0.0, 0.10, -0.77),
		Vector3(0.0, 0.12, -0.71),
		Vector3(0.0, 0.08, -0.68),
	]
	_append_tube_path(st, tip_scroll, [0.024, 0.022, 0.020, 0.018, 0.016, 0.013], 6,
		COL_SIGN_IRON_HI, COL_SIGN_IRON_LO)

	# 3. Sweeping diagonal wrought-iron S-scroll brace & tucked interior scroll volute.
	var brace_pts: Array[Vector3] = [
		Vector3(0.0, -0.24, 0.04),
		Vector3(0.0, -0.22, -0.10),
		Vector3(0.0, -0.17, -0.24),
		Vector3(0.0, -0.10, -0.36),
		Vector3(0.0, -0.05, -0.46),
	]
	_append_tube_path(st, brace_pts, [0.022, 0.020, 0.019, 0.018, 0.018], 6,
		COL_SIGN_IRON_LO, COL_SIGN_IRON_HI)
	var volute_pts: Array[Vector3] = [
		Vector3(0.0, -0.18, -0.18),
		Vector3(0.0, -0.24, -0.25),
		Vector3(0.0, -0.22, -0.33),
		Vector3(0.0, -0.15, -0.33),
		Vector3(0.0, -0.14, -0.27),
	]
	_append_tube_path(st, volute_pts, [0.015, 0.015, 0.014, 0.013, 0.012], 5,
		COL_SIGN_IRON_HI, COL_SIGN_IRON_LO)

	# 4. Horizontal hanging crossbar along X at z = -0.56 with forged spear-point finials & twin rings.
	_append_box_xform(st, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.08, -0.56)),
		Vector3(0.92, 0.042, 0.042), COL_SIGN_IRON_HI)
	for sgn: float in [-1.0, 1.0]:
		_append_tapered_prism(st, Vector3(sgn * 0.46, -0.08, -0.56), Vector3(sgn * 0.54, -0.08, -0.56),
			0.028, 0.006, 6, COL_SIGN_IRON_HI, COL_SIGN_IRON_LO, Vector2.ZERO)
		# Small side cheek scroll bracing crossbar to main cantilever arm.
		_append_tapered_prism(st, Vector3(sgn * 0.24, -0.08, -0.56), Vector3(0.0, -0.05, -0.34),
			0.014, 0.014, 5, COL_SIGN_IRON_LO, COL_SIGN_IRON_HI, Vector2.ZERO)
		# Hanging iron ring collar & loop at x = +/-0.31.
		_append_tapered_prism(st, Vector3(sgn * 0.31, -0.055, -0.56), Vector3(sgn * 0.31, -0.105, -0.56),
			0.030, 0.028, 6, COL_SIGN_IRON_HI, COL_SIGN_IRON_LO, Vector2.ZERO)
		_append_torus_ring(st, Vector3(sgn * 0.31, -0.135, -0.56), Vector3.RIGHT,
			0.036, 0.010, 8, 5, COL_SIGN_IRON_HI, COL_SIGN_IRON_LO)

	st.generate_normals()
	return st.commit()


static func _build_tavern_sign_board_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Coordinates relative to TavernSignPivot (0, 0, 0) at bottom of bracket hanging rings.
	# 1. Twin forged-iron hanging chains (3 interlocking oval links per side) + brass top eye-collars.
	for sgn: float in [-1.0, 1.0]:
		var cx := sgn * 0.31
		_append_torus_ring(st, Vector3(cx, -0.03, 0.0), Vector3.FORWARD,
			0.026, 0.008, 8, 5, COL_SIGN_IRON_HI, COL_SIGN_IRON_LO)
		_append_torus_ring(st, Vector3(cx, -0.08, 0.0), Vector3.RIGHT,
			0.026, 0.008, 8, 5, COL_SIGN_IRON_HI, COL_SIGN_IRON_LO)
		_append_torus_ring(st, Vector3(cx, -0.13, 0.0), Vector3.FORWARD,
			0.026, 0.008, 8, 5, COL_SIGN_IRON_HI, COL_SIGN_IRON_LO)
		_append_tapered_prism(st, Vector3(cx, -0.155, 0.0), Vector3(cx, -0.185, 0.0),
			0.024, 0.030, 6, COL_SIGN_BRASS_HI, COL_SIGN_BRASS_LO, Vector2.ZERO)

	# 2. Chunky beveled dark-mahogany hanging plaque (0.96 m wide x 0.60 m tall x 0.06 m thick, y=-0.16..-0.76).
	var cy := -0.46
	# Inner core slab.
	_append_box_xform(st, Transform3D(Basis.IDENTITY, Vector3(0.0, cy, 0.0)),
		Vector3(0.92, 0.56, 0.056), COL_SIGN_MAHOGANY_MID)
	# Chunky beveled outer hardwood molding rails (top, bottom, left, right) for rich sculpted relief!
	_append_box_xform(st, Transform3D(Basis.IDENTITY, Vector3(0.0, cy + 0.285, 0.0)),
		Vector3(0.96, 0.044, 0.064), COL_SIGN_MAHOGANY_HI)
	_append_box_xform(st, Transform3D(Basis.IDENTITY, Vector3(0.0, cy - 0.285, 0.0)),
		Vector3(0.96, 0.044, 0.064), COL_SIGN_MAHOGANY_LO)
	for sgn: float in [-1.0, 1.0]:
		_append_box_xform(st, Transform3D(Basis.IDENTITY, Vector3(sgn * 0.462, cy, 0.0)),
			Vector3(0.044, 0.58, 0.064), COL_SIGN_MAHOGANY_MID)

	# Decorative pub-sign scalloped crest crown arching at top center + brass accent drop below!
	_append_box_xform(st, Transform3D(Basis.IDENTITY, Vector3(0.0, cy + 0.322, 0.0)),
		Vector3(0.42, 0.044, 0.054), COL_SIGN_MAHOGANY_HI)
	_append_tapered_prism(st, Vector3(0.0, cy + 0.34, 0.0), Vector3(0.0, cy + 0.385, 0.0),
		0.085, 0.025, 6, COL_SIGN_BRASS_HI, COL_SIGN_BRASS_LO, Vector2.ZERO)
	_append_tapered_prism(st, Vector3(0.0, cy - 0.305, 0.0), Vector3(0.0, cy - 0.365, 0.0),
		0.036, 0.008, 6, COL_SIGN_BRASS_HI, COL_SIGN_BRASS_LO, Vector2.ZERO)

	# 3. Four ornate gilded-brass corner brackets with embossed corner studs on both faces.
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var bx := sx * 0.445
			var by := cy + sy * 0.265
			_append_box_xform(st, Transform3D(Basis.IDENTITY, Vector3(bx - sx * 0.04, by + sy * 0.02, 0.0)),
				Vector3(0.14, 0.038, 0.072), COL_SIGN_BRASS_HI)
			_append_box_xform(st, Transform3D(Basis.IDENTITY, Vector3(bx + sx * 0.018, by - sy * 0.032, 0.0)),
				Vector3(0.038, 0.13, 0.072), COL_SIGN_BRASS_LO)
			for sz: float in [-1.0, 1.0]:
				_append_tapered_prism(st, Vector3(bx, by, sz * 0.034), Vector3(bx, by, sz * 0.048),
					0.016, 0.008, 6, COL_SIGN_BRASS_HI, COL_SIGN_BRASS_HI.lightened(0.12), Vector2.ZERO)

	st.generate_normals()
	return st.commit()


static func _build_tavern_sign_face_mesh() -> ArrayMesh:
	# Clean double-sided UV-mapped plaque faces proud of the beveled mahogany body (zero z-fighting,
	# readable left-to-right on BOTH seaward -Z and porch-facing +Z sides!).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var hw := 0.435
	var y_top := -0.46 + 0.258
	var y_bot := -0.46 - 0.258
	var z_off := 0.031

	# Front face (-Z outward: viewer looking toward +Z sees +X on left, -X on right).
	_add_oriented_quad_uv(st,
		Vector3(hw, y_top, -z_off),
		Vector3(-hw, y_top, -z_off),
		Vector3(-hw, y_bot, -z_off),
		Vector3(hw, y_bot, -z_off),
		Vector3(0.0, 0.0, -1.0),
		Color.WHITE,
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0))

	# Rear face (+Z outward: viewer looking toward -Z sees -X on left, +X on right).
	_add_oriented_quad_uv(st,
		Vector3(-hw, y_top, z_off),
		Vector3(hw, y_top, z_off),
		Vector3(hw, y_bot, z_off),
		Vector3(-hw, y_bot, z_off),
		Vector3(0.0, 0.0, 1.0),
		Color.WHITE,
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0))

	st.generate_normals()
	return st.commit()


static func _paint_tavern_sign_textures() -> Array[ImageTexture]:
	var albedo := Image.create(SIGN_TEX_W, SIGN_TEX_H, false, Image.FORMAT_RGBA8)
	var emit_img := Image.create(SIGN_TEX_W, SIGN_TEX_H, false, Image.FORMAT_RGBA8)
	emit_img.fill(Color(0.0, 0.0, 0.0, 1.0))

	# 1. Warm dark mahogany plank woodgrain background (zero emission -> stays rich dark wood at night!).
	for y in SIGN_TEX_H:
		var vy := float(y) / float(SIGN_TEX_H - 1)
		var bevel_y := 1.0 - 0.36 * pow(absf(vy * 2.0 - 1.0), 2.8)
		var seam := 0.72 if (y == 38 or y == 78 or y == 118) else (1.07 if (y == 39 or y == 79 or y == 119) else 1.0)
		var sheen := 0.06 * exp(-pow((vy - 0.28) * 4.2, 2.0))
		for x in SIGN_TEX_W:
			var vx := float(x) / float(SIGN_TEX_W - 1)
			var bevel_x := 1.0 - 0.30 * pow(absf(vx * 2.0 - 1.0), 3.4)
			var grain := sin(float(y) * 0.42 + sin(float(x) * 0.045) * 2.4) * 0.5 + 0.5
			var fine := sin(float(y) * 1.35 + float(x) * 0.02) * 0.5 + 0.5
			var wood_k := (0.64 + 0.24 * grain + 0.12 * fine) * bevel_y * bevel_x * seam
			var r := clampf(0.27 * wood_k + sheen, 0.0, 1.0)
			var g := clampf(0.118 * wood_k + sheen * 0.65, 0.0, 1.0)
			var b := clampf(0.056 * wood_k + sheen * 0.35, 0.0, 1.0)
			albedo.set_pixel(x, y, Color(r, g, b, 1.0))

	# 2. Gilded double-line border frame + 4 corner brass rivets (subtle gold glint mask).
	var gold_hi := Color(1.0, 0.92, 0.56, 1.0)
	var gold_mid := Color(0.92, 0.71, 0.22, 1.0)
	var gold_lo := Color(0.66, 0.45, 0.11, 1.0)
	var dark_groove := Color(0.07, 0.03, 0.012, 1.0)
	var emit_frame := Color(0.56, 0.46, 0.22, 1.0)
	var emit_gold := Color(0.96, 0.82, 0.42, 1.0)
	var emit_text := Color(1.0, 0.90, 0.52, 1.0)

	_sign_rect_outline(albedo, emit_img, 5, 5, SIGN_TEX_W - 6, SIGN_TEX_H - 6, 3, gold_mid, emit_frame)
	_sign_rect_outline(albedo, emit_img, 9, 9, SIGN_TEX_W - 10, SIGN_TEX_H - 10, 1, dark_groove, Color.BLACK)
	_sign_rect_outline(albedo, emit_img, 11, 11, SIGN_TEX_W - 12, SIGN_TEX_H - 12, 1, gold_lo, emit_frame * 0.7)
	for cx: int in [17, SIGN_TEX_W - 18]:
		for cy: int in [17, SIGN_TEX_H - 18]:
			_sign_fill_circle(albedo, emit_img, cx, cy, 4, gold_hi, emit_gold)

	# 3. Crossed pirate cutlasses behind the central tankard (x = 76..180, y = 20..88).
	var steel_hi := Color(0.92, 0.94, 0.96, 1.0)
	var steel_mid := Color(0.68, 0.72, 0.78, 1.0)
	var emit_steel := Color(0.64, 0.58, 0.40, 1.0)
	var grip_col := Color(0.18, 0.09, 0.04, 1.0)
	for sgn: float in [-1.0, 1.0]:
		# Curved cutlass blade sweeping diagonally from brass guard up to tip.
		for ti in 46:
			var t := float(ti) / 45.0
			var bx := 128.0 + sgn * lerpf(-40.0, 44.0, t)
			var by := lerpf(78.0, 22.0, t) - sin(t * PI) * 8.5
			var half_w := lerpf(3.2, 4.8, sin(t * PI * 0.78))
			if t > 0.86:
				half_w *= (1.0 - t) / 0.14
			_sign_fill_circle(albedo, emit_img, int(roundf(bx)), int(roundf(by)), maxi(1, int(roundf(half_w))),
				steel_mid, emit_steel * 0.55)
			_sign_fill_circle(albedo, emit_img, int(roundf(bx)), int(roundf(by - 1.5)), maxi(1, int(roundf(half_w * 0.55))),
				steel_hi, emit_steel)
		# Brass basket handguard, dark leather grip & gold pommel knob.
		var gx := int(roundf(128.0 - sgn * 40.0))
		var gy := 78
		_sign_fill_circle(albedo, emit_img, gx, gy, 7, gold_mid, emit_gold)
		_sign_fill_circle(albedo, emit_img, gx - int(sgn * 6.0), gy + 5, 4, grip_col, Color.BLACK)
		_sign_fill_circle(albedo, emit_img, gx - int(sgn * 11.0), gy + 9, 4, gold_hi, emit_gold)

	# 4. Foaming Golden Tavern Tankard centered over the crossed cutlasses (x = 110..146, y = 26..90).
	# Dark silhouette shadow halo behind mug so it stands out cleanly against the steel blades.
	_sign_fill_rect(albedo, emit_img, 108, 42, 148, 91, dark_groove, Color.BLACK)
	# Curved brass-rimmed tankard D-handle on +X side.
	_sign_fill_circle(albedo, emit_img, 150, 66, 11, gold_lo, emit_frame)
	_sign_fill_circle(albedo, emit_img, 149, 66, 6, Color(0.18, 0.08, 0.04, 1.0), Color.BLACK)
	# Tapered oak tankard barrel body with sunlit warm wood staves.
	for y in range(44, 89):
		var ty := float(y - 44) / 44.0
		var half_w := lerpf(15.0, 18.0, ty)
		for x in range(int(128.0 - half_w), int(128.0 + half_w) + 1):
			var u := (float(x) - (128.0 - half_w)) / maxf(1.0, half_w * 2.0)
			var cyl_lit := 0.58 + 0.42 * sin(u * PI)
			var stave := 0.88 if (int(u * 5.0) % 2 == 0) else 1.0
			var c := Color(0.62 * cyl_lit * stave, 0.36 * cyl_lit * stave, 0.14 * cyl_lit * stave, 1.0)
			albedo.set_pixel(x, y, c)
			emit_img.set_pixel(x, y, Color(0.18 * cyl_lit, 0.11 * cyl_lit, 0.03 * cyl_lit, 1.0))
	# Two gleaming horizontal brass tankard bands.
	_sign_fill_rect(albedo, emit_img, 111, 52, 145, 56, gold_hi, emit_gold)
	_sign_fill_rect(albedo, emit_img, 110, 76, 146, 80, gold_mid, emit_gold * 0.88)
	# Billowy creamy-white & pale-gold beer foam crown spilling over the tankard lip!
	var foam_hi := Color(0.99, 0.96, 0.86, 1.0)
	var foam_mid := Color(0.92, 0.86, 0.70, 1.0)
	var emit_foam := Color(0.76, 0.68, 0.44, 1.0)
	for puff: Array in [[116, 40, 9], [128, 35, 11], [140, 40, 9], [122, 43, 8], [134, 43, 8]]:
		_sign_fill_circle(albedo, emit_img, int(puff[0]), int(puff[1]), int(puff[2]), foam_mid, emit_foam * 0.8)
		_sign_fill_circle(albedo, emit_img, int(puff[0]) - 1, int(puff[1]) - 2, maxi(2, int(puff[2]) - 3), foam_hi, emit_foam)
	# Playful foam drips running down front lip of mug.
	_sign_fill_rect(albedo, emit_img, 117, 44, 121, 59, foam_hi, emit_foam)
	_sign_fill_circle(albedo, emit_img, 119, 60, 2, foam_hi, emit_foam)
	_sign_fill_rect(albedo, emit_img, 134, 44, 137, 54, foam_mid, emit_foam * 0.85)

	# 5. Deep crimson heraldic scroll ribbon banner with gold trim + bold "SCOUNDREL'S REST" lettering!
	var banner_bg := Color(0.42, 0.09, 0.075, 1.0)
	var banner_hi := Color(0.54, 0.13, 0.10, 1.0)
	_sign_fill_rect(albedo, emit_img, 16, 100, SIGN_TEX_W - 17, 140, banner_bg, Color.BLACK)
	_sign_fill_rect(albedo, emit_img, 18, 104, SIGN_TEX_W - 19, 112, banner_hi, Color.BLACK)
	_sign_rect_outline(albedo, emit_img, 16, 100, SIGN_TEX_W - 17, 140, 2, gold_mid, emit_frame)
	# Carved gold-leaf serif lettering "SCOUNDREL'S REST" (16 chars x 10 px + 15 x 3 px = 205 px -> centered!).
	var title := "SCOUNDREL'S REST"
	var scale_px := 2
	var char_adv := 5 * scale_px + 3
	var total_w := title.length() * (5 * scale_px) + (title.length() - 1) * 3
	var start_x := int((SIGN_TEX_W - total_w) * 0.5)
	var start_y := 113
	# Drop shadow pass (pure umber, zero emission).
	for ci in title.length():
		var ch := title.substr(ci, 1)
		var rows: Array = ShipNameplate.GLYPHS.get(ch, ShipNameplate.GLYPHS[" "])
		_sign_draw_glyph(albedo, emit_img, rows, start_x + ci * char_adv + 2, start_y + 2, scale_px,
			dark_groove, dark_groove, dark_groove, Color.BLACK)
	# Gilded beveled gold-leaf face pass (lights up cleanly through EMISSION_OP_MULTIPLY at night!).
	for ci in title.length():
		var ch := title.substr(ci, 1)
		var rows: Array = ShipNameplate.GLYPHS.get(ch, ShipNameplate.GLYPHS[" "])
		_sign_draw_glyph(albedo, emit_img, rows, start_x + ci * char_adv, start_y, scale_px,
			gold_hi, gold_mid, gold_lo, emit_text)

	return [ImageTexture.create_from_image(albedo), ImageTexture.create_from_image(emit_img)]


static func _sign_fill_rect(albedo: Image, emit_img: Image, x0: int, y0: int, x1: int, y1: int,
		col: Color, ecol: Color) -> void:
	for y in range(maxi(0, y0), mini(SIGN_TEX_H, y1 + 1)):
		for x in range(maxi(0, x0), mini(SIGN_TEX_W, x1 + 1)):
			albedo.set_pixel(x, y, col)
			emit_img.set_pixel(x, y, ecol)


static func _sign_rect_outline(albedo: Image, emit_img: Image, x0: int, y0: int, x1: int, y1: int,
		thick: int, col: Color, ecol: Color) -> void:
	for t in thick:
		for x in range(maxi(0, x0 + t), mini(SIGN_TEX_W, x1 - t + 1)):
			if y0 + t >= 0 and y0 + t < SIGN_TEX_H:
				albedo.set_pixel(x, y0 + t, col)
				emit_img.set_pixel(x, y0 + t, ecol)
			if y1 - t >= 0 and y1 - t < SIGN_TEX_H:
				albedo.set_pixel(x, y1 - t, col)
				emit_img.set_pixel(x, y1 - t, ecol)
		for y in range(maxi(0, y0 + t), mini(SIGN_TEX_H, y1 - t + 1)):
			if x0 + t >= 0 and x0 + t < SIGN_TEX_W:
				albedo.set_pixel(x0 + t, y, col)
				emit_img.set_pixel(x0 + t, y, ecol)
			if x1 - t >= 0 and x1 - t < SIGN_TEX_W:
				albedo.set_pixel(x1 - t, y, col)
				emit_img.set_pixel(x1 - t, y, ecol)


static func _sign_fill_circle(albedo: Image, emit_img: Image, cx: int, cy: int, rad: int,
		col: Color, ecol: Color) -> void:
	var r2 := rad * rad
	for dy in range(-rad, rad + 1):
		var py := cy + dy
		if py < 0 or py >= SIGN_TEX_H:
			continue
		for dx in range(-rad, rad + 1):
			if dx * dx + dy * dy <= r2:
				var px := cx + dx
				if px >= 0 and px < SIGN_TEX_W:
					albedo.set_pixel(px, py, col)
					emit_img.set_pixel(px, py, ecol)


static func _sign_draw_glyph(albedo: Image, emit_img: Image, rows: Array, ox: int, oy: int, s: int,
		col_hi: Color, col_mid: Color, col_lo: Color, ecol: Color) -> void:
	for ry in rows.size():
		var mask := int(rows[ry])
		if mask == 0:
			continue
		for rx in 5:
			if (mask & (1 << (4 - rx))) == 0:
				continue
			var bx := ox + rx * s
			var by := oy + ry * s
			for dy in s:
				var py := by + dy
				if py < 0 or py >= SIGN_TEX_H:
					continue
				var c := col_mid
				if dy == 0 and ry <= 2:
					c = col_hi
				elif dy == s - 1 and ry >= 4:
					c = col_lo
				for dx in s:
					var px := bx + dx
					if px >= 0 and px < SIGN_TEX_W:
						albedo.set_pixel(px, py, c)
						emit_img.set_pixel(px, py, ecol)


static func _build_pier_bell_frame_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Heavy riveted forged-iron piling collar cap gripping atop the 0.175 m bollard piling (y=-0.14..+0.065).
	_append_tapered_prism(st, Vector3(0.0, -0.14, 0.0), Vector3(0.0, 0.042, 0.0),
		0.215, 0.205, 10, COL_SIGN_IRON_LO, COL_SIGN_IRON_HI, Vector2.ZERO)
	_append_tapered_prism(st, Vector3(0.0, 0.032, 0.0), Vector3(0.0, 0.068, 0.0),
		0.232, 0.218, 10, COL_SIGN_IRON_HI, COL_SIGN_IRON_HI.lightened(0.08), Vector2.ZERO)
	# Eight forged perimeter cap bolts.
	for bi in 8:
		var a := float(bi) / 8.0 * TAU
		var bp := Vector3(cos(a) * 0.185, 0.064, sin(a) * 0.185)
		_append_tapered_prism(st, bp, bp + Vector3(0.0, 0.022, 0.0),
			0.016, 0.011, 6, COL_SIGN_BRASS_LO, COL_SIGN_BRASS_HI, Vector2.ZERO)

	# 2. Sweeping forged-iron arched harbour bell gallows yoke framing the bronze bell cleanly along X.
	var arch_pts: Array[Vector3] = [
		Vector3(-0.175, 0.055, 0.0),
		Vector3(-0.215, 0.19, 0.0),
		Vector3(-0.245, 0.36, 0.0),
		Vector3(-0.245, 0.56, 0.0),
		Vector3(-0.210, 0.70, 0.0),
		Vector3(-0.115, 0.79, 0.0),
		Vector3(0.0, 0.825, 0.0),
		Vector3(0.115, 0.79, 0.0),
		Vector3(0.210, 0.70, 0.0),
		Vector3(0.245, 0.56, 0.0),
		Vector3(0.245, 0.36, 0.0),
		Vector3(0.215, 0.19, 0.0),
		Vector3(0.175, 0.055, 0.0),
	]
	var arch_rads: Array[float] = [
		0.030, 0.028, 0.026, 0.028, 0.026, 0.025, 0.028,
		0.025, 0.026, 0.028, 0.026, 0.028, 0.030,
	]
	_append_tube_path(st, arch_pts, arch_rads, 6, COL_SIGN_IRON_LO, COL_SIGN_IRON_HI)

	# 3. Twin lower forged cheek scroll braces & trunnion axle bearing bosses at y = 0.56.
	for sgn: float in [-1.0, 1.0]:
		var brace: Array[Vector3] = [
			Vector3(sgn * 0.125, 0.062, 0.0),
			Vector3(sgn * 0.165, 0.13, 0.0),
			Vector3(sgn * 0.228, 0.25, 0.0),
		]
		_append_tube_path(st, brace, [0.018, 0.016, 0.015], 5, COL_SIGN_IRON_HI, COL_SIGN_IRON_LO)
		# Trunnion axle journal cap + brass grease nut.
		_append_tapered_prism(st, Vector3(sgn * 0.215, 0.56, 0.0), Vector3(sgn * 0.285, 0.56, 0.0),
			0.044, 0.036, 6, COL_SIGN_IRON_HI, COL_SIGN_IRON_LO, Vector2.ZERO)
		_append_tapered_prism(st, Vector3(sgn * 0.282, 0.56, 0.0), Vector3(sgn * 0.304, 0.56, 0.0),
			0.020, 0.014, 6, COL_SIGN_BRASS_HI, COL_SIGN_BRASS_LO, Vector2.ZERO)

	# Cross-axle iron shaft spanning through PierBellPivot at y = 0.56.
	_append_tapered_prism(st, Vector3(-0.24, 0.56, 0.0), Vector3(0.24, 0.56, 0.0),
		0.018, 0.018, 6, COL_SIGN_IRON_LO, COL_SIGN_IRON_HI, Vector2.ZERO)

	# 4. Sculpted forged-iron crown finial spire & mooring ring atop the gallows arch.
	_append_tapered_prism(st, Vector3(0.0, 0.815, 0.0), Vector3(0.0, 0.915, 0.0),
		0.036, 0.010, 6, COL_SIGN_IRON_HI, COL_SIGN_BRASS_HI, Vector2.ZERO)
	_append_torus_ring(st, Vector3(0.0, 0.935, 0.0), Vector3.FORWARD,
		0.026, 0.008, 8, 5, COL_SIGN_BRASS_HI, COL_SIGN_BRASS_LO)

	st.generate_normals()
	return st.commit()


static func _build_pier_bell_cup_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Coordinates relative to PierBellPivot (0, 0, 0) right on the iron yoke axle!
	# 1. Heavy cast headstock counterweight yoke block & twin bronze crown cannon loops.
	_append_box_xform(st, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.008, 0.0)),
		Vector3(0.32, 0.062, 0.072), COL_SIGN_IRON_HI)
	_append_box_xform(st, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.048, 0.0)),
		Vector3(0.20, 0.034, 0.056), COL_SIGN_IRON_LO)
	for sgn: float in [-1.0, 1.0]:
		_append_tapered_prism(st, Vector3(sgn * 0.055, 0.01, 0.0), Vector3(sgn * 0.044, -0.055, 0.0),
			0.022, 0.018, 6, COL_BELL_BRONZE_MID, COL_BELL_BRONZE_DARK, Vector2.ZERO)

	# 2. Lathe-turned weathered-bronze marine fog-bell (16 radial segs, outer profile + hollow interior!).
	var bell_profile: Array[Array] = [
		[-0.042, 0.054, COL_BELL_BRONZE_MID],
		[-0.078, 0.098, COL_BELL_BRONZE_HI],
		[-0.096, 0.108, COL_BELL_BRONZE_HI.lightened(0.10)],  # Raised shoulder bead ring
		[-0.114, 0.100, COL_BELL_BRONZE_MID.lerp(COL_BELL_VERDIGRIS, 0.35)],
		[-0.175, 0.098, COL_BELL_BRONZE_MID.lerp(COL_BELL_VERDIGRIS, 0.45)],  # Verdigris concave waist
		[-0.238, 0.124, COL_BELL_BRONZE_MID],
		[-0.292, 0.162, COL_BELL_BRONZE_HI],
		[-0.326, 0.178, COL_BELL_BRONZE_HI.lightened(0.12)],  # Gleaming flared sound-bow rim
		[-0.346, 0.168, COL_BELL_BRONZE_MID],                  # Thick beveled lip edge
		[-0.330, 0.146, COL_BELL_BRONZE_DARK],                 # Inner sound-bow chamber
		[-0.215, 0.092, COL_BELL_BRONZE_DARK],
		[-0.088, 0.048, COL_BELL_BRONZE_DARK],                 # Inner crown dome
	]
	_append_lathe_profile(st, bell_profile, 16)
	# Cap inner top dome & outer top crown disc cleanly so mesh is watertight.
	var crown_ctr := Vector3(0.0, -0.040, 0.0)
	var dome_ctr := Vector3(0.0, -0.086, 0.0)
	for k in 16:
		var a0 := float(k) / 16.0 * TAU
		var a1 := float(k + 1) / 16.0 * TAU
		var p0 := Vector3(cos(a0) * 0.054, -0.042, sin(a0) * 0.054)
		var p1 := Vector3(cos(a1) * 0.054, -0.042, sin(a1) * 0.054)
		_add_outward_tri(st, crown_ctr, p0, p1, Vector3(0.0, -0.10, 0.0),
			COL_BELL_BRONZE_MID, COL_BELL_BRONZE_MID, COL_BELL_BRONZE_MID)
		var d0 := Vector3(cos(a0) * 0.048, -0.088, sin(a0) * 0.048)
		var d1 := Vector3(cos(a1) * 0.048, -0.088, sin(a1) * 0.048)
		_add_outward_tri(st, dome_ctr, d0, d1, Vector3(0.0, -0.02, 0.0),
			COL_BELL_BRONZE_DARK, COL_BELL_BRONZE_DARK, COL_BELL_BRONZE_DARK)

	# 3. Hanging forged-brass clapper rod, chunky strike-ball, knotted hemp lanyard & brass pull-ring!
	_append_tapered_prism(st, Vector3(0.0, -0.085, 0.0), Vector3(0.0, -0.31, 0.0),
		0.011, 0.013, 6, COL_SIGN_BRASS_LO, COL_SIGN_BRASS_HI, Vector2.ZERO)
	# Faceted 8-sided brass strike ball right at the flared sound-bow rim.
	_append_tapered_prism(st, Vector3(0.0, -0.296, 0.0), Vector3(0.0, -0.326, 0.0),
		0.018, 0.038, 8, COL_SIGN_BRASS_LO, COL_SIGN_BRASS_HI, Vector2.ZERO)
	_append_tapered_prism(st, Vector3(0.0, -0.326, 0.0), Vector3(0.0, -0.356, 0.0),
		0.038, 0.014, 8, COL_SIGN_BRASS_HI, COL_SIGN_BRASS_LO, Vector2.ZERO)
	# Knotted hemp bell-pull lanyard & captain's brass pull-ring (clears piling cap by 8+ cm!).
	_append_tapered_prism(st, Vector3(0.0, -0.354, 0.0), Vector3(0.0, -0.435, 0.0),
		0.012, 0.016, 6, COL_ROPE_HEMP, COL_ROPE_HEMP.darkened(0.12), Vector2.ZERO)
	_append_torus_ring(st, Vector3(0.0, -0.462, 0.0), Vector3.FORWARD,
		0.028, 0.008, 8, 5, COL_SIGN_BRASS_HI, COL_SIGN_BRASS_LO)

	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ SurfaceTool Geometry Helpers

static func _append_torus_ring(st: SurfaceTool, center: Vector3, axis_n: Vector3,
		major_r: float, minor_r: float, major_segs: int, minor_segs: int,
		col_hi: Color, col_lo: Color) -> void:
	var n := axis_n.normalized()
	var ref := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.85 else Vector3.RIGHT
	var u := n.cross(ref).normalized()
	var v := n.cross(u).normalized()
	var rings: Array[Array] = []
	var ctrs: Array[Vector3] = []
	for i in major_segs:
		var a := float(i) / float(major_segs) * TAU
		var radial := u * cos(a) + v * sin(a)
		var ring_c := center + radial * major_r
		ctrs.append(ring_c)
		var ring: Array[Vector3] = []
		for j in minor_segs:
			var b := float(j) / float(minor_segs) * TAU
			var off := (radial * cos(b) + n * sin(b)) * minor_r
			ring.append(ring_c + off)
		rings.append(ring)
	for i in major_segs:
		var ni := (i + 1) % major_segs
		var r0: Array = rings[i]
		var r1: Array = rings[ni]
		var seg_ctr := (ctrs[i] + ctrs[ni]) * 0.5
		var col := col_hi if i % 2 == 0 else col_lo
		for j in minor_segs:
			var nj := (j + 1) % minor_segs
			_add_outward_quad(st, r0[j], r1[j], r1[nj], r0[nj], seg_ctr, col, col, col, col)


static func _append_tube_path(st: SurfaceTool, pts: Array[Vector3], radii: Array[float],
		sides: int, col_a: Color, col_b: Color) -> void:
	var count := mini(pts.size(), radii.size())
	if count < 2:
		return
	for i in count - 1:
		var t0 := float(i) / float(count - 1)
		var t1 := float(i + 1) / float(count - 1)
		_append_tapered_prism(st, pts[i], pts[i + 1], radii[i], radii[i + 1], sides,
			col_a.lerp(col_b, t0), col_a.lerp(col_b, t1), Vector2.ZERO)


static func _append_lathe_profile(st: SurfaceTool, stations: Array[Array], radial_segs: int) -> void:
	var rings: Array[Array] = []
	var ys: Array[float] = []
	var rs: Array[float] = []
	var cols: Array[Color] = []
	for row in stations:
		var py: float = float(row[0])
		var pr: float = float(row[1])
		var pc: Color = row[2] as Color
		ys.append(py)
		rs.append(pr)
		cols.append(pc)
		var ring: Array[Vector3] = []
		for k in radial_segs:
			var a := float(k) / float(radial_segs) * TAU
			ring.append(Vector3(cos(a) * pr, py, sin(a) * pr))
		rings.append(ring)
	for i in range(rings.size() - 1):
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		var dy := ys[i + 1] - ys[i]
		var dr := rs[i + 1] - rs[i]
		var c0 := cols[i]
		var c1 := cols[i + 1]
		for k in radial_segs:
			var nk := (k + 1) % radial_segs
			var am := (float(k) + 0.5) / float(radial_segs) * TAU
			var rad_dir := Vector3(cos(am), 0.0, sin(am))
			var desired_n := rad_dir * (-dy) + Vector3.UP * dr
			if desired_n.length_squared() < 1e-10:
				desired_n = rad_dir
			_add_oriented_quad_uv(st, r0[k], r1[k], r1[nk], r0[nk], desired_n, c0,
				Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, c1, c1, c0)


static func _add_oriented_quad_uv(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		desired_n: Vector3, ca: Color, uva: Vector2, uvb: Vector2, uvc: Vector2, uvd: Vector2,
		cb: Color = Color(-1.0, -1.0, -1.0), cc: Color = Color(-1.0, -1.0, -1.0), cd: Color = Color(-1.0, -1.0, -1.0)) -> void:
	var c_b := ca if cb.r < 0.0 else cb
	var c_c := ca if cc.r < 0.0 else cc
	var c_d := ca if cd.r < 0.0 else cd
	var n1 := (c - a).cross(b - a)
	if n1.dot(desired_n) >= 0.0:
		_add_flat_tri_uv(st, a, b, c, ca, c_b, c_c, uva, uvb, uvc)
		_add_flat_tri_uv(st, a, c, d, ca, c_c, c_d, uva, uvc, uvd)
	else:
		_add_flat_tri_uv(st, a, c, b, ca, c_c, c_b, uva, uvc, uvb)
		_add_flat_tri_uv(st, a, d, c, ca, c_d, c_c, uva, uvd, uvc)

static func _append_tapered_prism(st: SurfaceTool, p0: Vector3, p1: Vector3,
		r0: float, r1: float, sides: int, c0: Color, c1: Color, uv: Vector2) -> void:
	var axis := p1 - p0
	if axis.length_squared() < 1e-8:
		return
	var dir := axis.normalized()
	var ref := Vector3.RIGHT if absf(dir.dot(Vector3.RIGHT)) < 0.85 else Vector3.FORWARD
	var u := dir.cross(ref).normalized()
	var v := u.cross(dir).normalized()

	var ring0: Array[Vector3] = []
	var ring1: Array[Vector3] = []
	for k in sides:
		var a := float(k) / float(sides) * TAU
		var radial := u * cos(a) + v * sin(a)
		ring0.append(p0 + radial * r0)
		ring1.append(p1 + radial * r1)

	var mid := (p0 + p1) * 0.5
	for k in sides:
		var nk := (k + 1) % sides
		_add_outward_quad_uv(st, ring0[k], ring1[k], ring1[nk], ring0[nk], mid, c0, c1, c1, c0, uv, uv, uv, uv)
		_add_outward_tri_uv(st, p0, ring0[nk], ring0[k], mid, c0, c0, c0, uv, uv, uv)
		_add_outward_tri_uv(st, p1, ring1[k], ring1[nk], mid, c1, c1, c1, uv, uv, uv)


static func _append_box_xform(st: SurfaceTool, xform: Transform3D, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var corners: Array[Vector3] = [
		xform * Vector3(-h.x, -h.y, -h.z),
		xform * Vector3(h.x, -h.y, -h.z),
		xform * Vector3(h.x, h.y, -h.z),
		xform * Vector3(-h.x, h.y, -h.z),
		xform * Vector3(-h.x, -h.y, h.z),
		xform * Vector3(h.x, -h.y, h.z),
		xform * Vector3(h.x, h.y, h.z),
		xform * Vector3(-h.x, h.y, h.z),
	]
	var ctr := xform.origin
	var faces: Array[Array] = [
		[0, 1, 2, 3], [5, 4, 7, 6],
		[4, 0, 3, 7], [1, 5, 6, 2],
		[3, 2, 6, 7], [4, 5, 1, 0],
	]
	for f in faces:
		_add_outward_quad(st, corners[int(f[0])], corners[int(f[1])], corners[int(f[2])], corners[int(f[3])],
			ctr, col, col, col, col)


static func _add_outward_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_add_outward_tri_uv(st, a, b, c, ref_center, ca, cb, cc, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	_add_outward_tri_uv(st, a, c, d, ref_center, ca, cc, cd, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)


static func _add_outward_quad_uv(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color, cd: Color,
		uva: Vector2, uvb: Vector2, uvc: Vector2, uvd: Vector2) -> void:
	_add_outward_tri_uv(st, a, b, c, ref_center, ca, cb, cc, uva, uvb, uvc)
	_add_outward_tri_uv(st, a, c, d, ref_center, ca, cc, cd, uva, uvc, uvd)


static func _add_outward_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	_add_outward_tri_uv(st, a, b, c, ref_center, ca, cb, cc, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)


static func _add_outward_tri_uv(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color,
		uva: Vector2, uvb: Vector2, uvc: Vector2) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-10:
		return
	var centroid := (a + b + c) / 3.0
	if n.dot(centroid - ref_center) < 0.0:
		var tmp_v := b
		b = c
		c = tmp_v
		var tmp_c := cb
		cb = cc
		cc = tmp_c
		var tmp_uv := uvb
		uvb = uvc
		uvc = tmp_uv
	_add_flat_tri_uv(st, a, b, c, ca, cb, cc, uva, uvb, uvc)


static func _add_flat_tri_uv(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color, uva: Vector2, uvb: Vector2, uvc: Vector2) -> void:
	if (c - a).cross(b - a).length_squared() < 1e-10:
		return
	st.set_smooth_group(-1)
	st.set_color(ca)
	st.set_uv(uva)
	st.add_vertex(a)

	st.set_smooth_group(-1)
	st.set_color(cb)
	st.set_uv(uvb)
	st.add_vertex(b)

	st.set_smooth_group(-1)
	st.set_color(cc)
	st.set_uv(uvc)
	st.add_vertex(c)


# ------------------------------------------------------------------ GLB Prop Helpers

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
