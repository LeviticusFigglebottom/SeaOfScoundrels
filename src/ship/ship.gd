class_name Ship
extends RigidBody3D
## Sloop physics, stations, sails, cannons, hull damage, flooding, and replication.
##
## Origin sits at the waterline, midship, on the centreline (-Z bow, +Y up, +X starboard).
## Reads all station markers, moving-part pivots, damage panels/holes, water mask, and
## convex collision shapes directly from `assets/generated/ship/sloop.glb` (see docs/SHIP_ART.md).
##
## Host-authoritative: control setters, damage, flooding, bailing, patching, and cannon
## firing mutate state only where `Net.is_host()`. Clients interpolate from `apply_net_state()`.

signal hull_breached(slot_index: int, world_pos: Vector3)
signal hull_impacted(world_pos: Vector3, intensity: float)
signal hole_patched(slot_index: int)
signal bailed(amount: float)
signal sunk
signal cannon_fired(side: StringName, cannonball: Cannonball)
signal bell_rung(pawn: Node)
signal ship_bell_rung(by_pawn: Node)
signal supplies_taken(pawn: Node)
signal wind_caught(efficiency: float)
signal anchor_turn_triggered(speed: float, yaw_dir: float)
signal anchor_raised()

const SLOOP_SCENE: PackedScene = preload("res://assets/generated/ship/sloop.glb")
const SLOOP_LOD_SCENE: PackedScene = preload("res://assets/generated/ship/sloop_lod.glb")
const SAIL_WIND_SHADER: Shader = preload("res://src/ship/sail_wind.gdshader")
const HOLD_WATER_SHADER: Shader = preload("res://src/ship/hold_water.gdshader")
const GHOST_HULL_SHADER: Shader = preload("res://src/ship/ghost_hull.gdshader")
const SHIP_NAMEPLATE_PATH := "res://src/ship/ship_nameplate.gd"
const HULL_CREST_PATH := "res://src/ship/hull_crest.gd"

## Collision layer 2 (ships). Mask deliberately excludes layer 3 (pawns) so
## CharacterBody3D pawns never shove the hull (docs/ARCHITECTURE.md).
const LAYER_SHIP := 1 << 1
const MASK_SHIP := 1 | (1 << 1)

## Spacious deck scale (+54% walkable deck area while preserving unit-scale sloop.glb assets).
const DEFAULT_HULL_SCALE := 1.24

const BASE_MASS := 9000.0
const FLOOD_EXTRA_MASS := 5400.0
const GRAVITY := 9.81
const MAX_TRIM_RAD := 1.2
const LOD_SWITCH_DIST := 180.0
const HOLE_SLOTS := 10
const CANNON_MUZZLE_SPEED := 58.0
const CANNON_RELOAD_TIME := 2.6
const MAX_CANNONBALLS := 40
const MAX_PLANKS := 24

# 16 distributed buoyancy probes in ship-local space: [Vector3(x, y, z), weight].
# Sum of weights = 1.0. Average probe y ~= -0.58 m so equilibrium sits at y ~= 0.0 m.
const BUOYANCY_PROBES: Array[Array] = [
	# Keel spine
	[Vector3(0.0, -0.95, -4.8), 0.065],
	[Vector3(0.0, -0.95, -2.4), 0.075],
	[Vector3(0.0, -0.95, 0.0), 0.080],
	[Vector3(0.0, -0.95, 2.4), 0.075],
	[Vector3(0.0, -0.95, 4.8), 0.065],
	# Bow stem lift probe
	[Vector3(0.0, -0.25, -6.0), 0.050],
	# Port chines
	[Vector3(-1.15, -0.45, -4.4), 0.050],
	[Vector3(-1.75, -0.55, -2.0), 0.065],
	[Vector3(-1.95, -0.55, 0.4), 0.070],
	[Vector3(-1.75, -0.55, 2.8), 0.060],
	[Vector3(-1.35, -0.35, 5.2), 0.050],
	# Starboard chines
	[Vector3(1.15, -0.45, -4.4), 0.050],
	[Vector3(1.75, -0.55, -2.0), 0.065],
	[Vector3(1.95, -0.55, 0.4), 0.070],
	[Vector3(1.75, -0.55, 2.8), 0.060],
	[Vector3(1.35, -0.35, 5.2), 0.050],
]

# ------------------------------------------------------------------ control state

## Wheel position in -1..1 (positive turns bow to starboard).
var helm: float = 0.0
var helm_target: float = 0.0
## Sail length in 0..1 (0 = furled, 1 = full mainsail).
var sail_set: float = 0.0
var sail_target: float = 0.0
## Yard angle relative to the hull in radians (-1.2..1.2).
var sail_trim: float = 0.0
var trim_target: float = 0.0
## Whether the anchor is commanded down.
var anchor_down: bool = false
## 0 = stowed at bow, 1 = resting on bottom.
var anchor_progress: float = 0.0

# ------------------------------------------------------------------ status & supplies

## Hold flooding fraction, 0 (dry) to 1 (foundering threshold).
var water_level: float = 0.0
## True once flooding crosses the sinking threshold.
var is_sinking: bool = false
## Per-slot hull damage records (10 entries for HullPanel_01..10).
## Each entry: {index, name, breached, patched, severity, local_pos, panel, hole, patch, jet, interactable}.
var holes: Array[Dictionary] = []

var cannonballs_remaining: int = MAX_CANNONBALLS
var planks_remaining: int = MAX_PLANKS

## Sidegrade stat multipliers (applied from Economy.get_ship_modifiers when equipped).
var speed_modifier: float = 1.0
var close_hauled_modifier: float = 1.0
var breach_resist_modifier: float = 1.0
var reload_modifier: float = 1.0
var cannon_radius_modifier: float = 1.0

## Ship class: &"sloop" (1 mast, 2 cannons) or &"brigantine" (2 masts, 4 cannons, higher top speed).
@export var ship_class: StringName = &"sloop"
## Uniform scale applied to hull models, collision points, buoyancy probes, and ship props.
@export var hull_scale: float = DEFAULT_HULL_SCALE
## Optional faction tag (&"player", &"drowned", &"ghost", &"corsair").
@export var faction: StringName = &"player"
## Optional starting anchor state.
@export var start_anchored: bool = false
## Build lights and particle emitters (set false only if a micro-benchmark wants bare physics).
@export var enable_effects: bool = true

# ------------------------------------------------------------------ internal refs

var _hull_mass: float = BASE_MASS
var _probe_scale: Vector3 = Vector3.ONE
var _class_thrust_mult: float = 1.24

var _model: Node3D = null
var _lod_model: Node3D = null
var _using_lod: bool = false
var _mask_water: MeshInstance3D = null
var _mask_registered: bool = false
var _hold_water_mesh: MeshInstance3D = null
var _hold_water_mat: ShaderMaterial = null

var _wheel: Node3D = null
var _rudder: Node3D = null
var _yards: Array[Node3D] = []
var _sails: Array[MeshInstance3D] = []
var _sails_furled: Array[Node3D] = []
var _flags: Array[MeshInstance3D] = []
var _emissary_streamer: MeshInstance3D = null
var _capstan: Node3D = null
var _anchor_node: Node3D = null
var _anchor_base_pos: Vector3 = Vector3.ZERO
var _bell: Node3D = null
var _bell_swing: float = 0.0
var _bell_vel: float = 0.0

var _lod_yards: Array[Node3D] = []
var _lod_sails: Array[Node3D] = []
var _lod_sails_furled: Array[Node3D] = []
var _lod_flags: Array[Node3D] = []

var _sail_mats: Array[ShaderMaterial] = []
var _flag_mats: Array[ShaderMaterial] = []
var _window_mats: Array[BaseMaterial3D] = []
var _lantern_lights: Array[OmniLight3D] = []
var _rope_pairs: Array[Array] = []  # [rope_node, point_a, point_b]

var _stations: Array[Station] = []
var _stations_by_kind: Dictionary = {}  # StringName -> Array[Station]
var _cannons: Dictionary = {}  # StringName (&"port" / &"starboard" / &"port_aft" / &"starboard_aft") -> Dictionary state

var _sink_timer: float = 0.0
var _sink_list_dir: float = 1.0
var _sink_foam_accum: float = 0.0
var _sail_time: float = 0.0
var _slosh_time: float = 0.0
var _slosh_tilt: Vector2 = Vector2.ZERO
var _last_wind_catch: float = 0.0
var _last_submerged_frac: float = 0.0
var _anchor_swing_dir: float = 0.0
var _anchor_swing_timer: float = 0.0

# Sea-of-Thieves tactile capstan heave & helm center-detent state
var _manual_capstan_heave: bool = false
var _capstan_heaving_this_tick: bool = false
var _capstan_assist_hands: int = 0
var _helm_detent_timer: float = 0.0

# Audio pacing timers
var _creak_cooldown: float = 0.0
var _flap_cooldown: float = 0.0
var _slosh_cooldown: float = 0.0
var _wheel_sfx_accum: float = 0.0
var _rope_sfx_accum: float = 0.0
var _capstan_sfx_accum: float = 0.0
var _was_anchor_submerged: bool = false
var _was_drawing_wind: bool = false
var _was_peak_wind: bool = false

# Client interpolation target state
var _net_target_xform: Transform3D = Transform3D.IDENTITY
var _net_has_state: bool = false
var _livery_sail_tint: Color = Color.WHITE
var _livery_flag_tint: Color = Color.WHITE
var _livery_glow_accent: Color = Color.BLACK
var _livery_hull_tint: Color = Color.WHITE
var _livery_emblem_mode: int = -1
var _effective_glow_accent: Color = Color.BLACK
var _hull_mats_duplicated: bool = false
var _hull_mat_entries: Array[Dictionary] = []
var _ghost_hull_mats: Array[ShaderMaterial] = []
var _spectral_phase: float = 1.0
var _spectral_flare: float = 0.0
var _wisp_time: float = 0.0

var _bow_spray_port: GPUParticles3D = null
var _bow_spray_starboard: GPUParticles3D = null
var _spray_tex: GradientTexture2D = null
var _active_muzzle_vfx: Array[Node] = []

var cabin_furnishings: CaptainCabinFurnishings = null
var ship_nameplate: Node3D = null
var hull_crest: Node3D = null
var wind_ribbons: WindRibbons = null
var crows_nest_ladder: Ladder = null
var _crows_nest_rungs_mi: MeshInstance3D = null
var ship_name: String = "The Gilded Scoundrel"
var ship_bell_node: Node3D = null
var ship_bell_interactable: Interactable = null
var _bell_frame_mi: MeshInstance3D = null
var _bell_cup_pivot: Node3D = null
var _bell_cup_mi: MeshInstance3D = null
var _lookout_glint: MeshInstance3D = null
var _lookout_glint_mat: ShaderMaterial = null
var _lookout_glint_phase: float = 0.0

static var _active_ship_count: int = 0
static var _smoke_puff_tex: ImageTexture = null
static var _muzzle_flash_tex: GradientTexture2D = null
static var _muzzle_spark_tex: ImageTexture = null
static var _streamer_mesh_sloop: ArrayMesh = null
static var _streamer_mesh_brig: ArrayMesh = null
static var _lookout_glint_mesh: ArrayMesh = null
static var _lookout_glint_shader: Shader = null
static var _bell_frame_mesh: ArrayMesh = null
static var _bell_cup_mesh: ArrayMesh = null
static var _bell_iron_mat: StandardMaterial3D = null
static var _bell_bronze_mat: StandardMaterial3D = null
static var _crows_nest_rungs_sloop: ArrayMesh = null
static var _crows_nest_rungs_brig: ArrayMesh = null
static var _crows_nest_rungs_mat: StandardMaterial3D = null


## Convert an unscaled GLB ship-local coordinate into this ship's scaled local space.
func ship_point(unscaled_local: Vector3) -> Vector3:
	return unscaled_local * hull_scale


func _init() -> void:
	mass = BASE_MASS
	gravity_scale = 1.0
	linear_damp = 0.0
	angular_damp = 0.0
	can_sleep = false
	continuous_cd = false
	collision_layer = LAYER_SHIP
	collision_mask = MASK_SHIP
	inertia = Vector3(135000.0, 175000.0, 42000.0)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, -0.35, 0.15)


func _enter_tree() -> void:
	_active_ship_count += 1
	add_to_group(&"ship")


func _ready() -> void:
	collision_layer = LAYER_SHIP
	collision_mask = MASK_SHIP
	if ship_class == &"brigantine":
		_hull_mass = 13500.0
		_probe_scale = Vector3(1.22, 1.05, 1.32) * hull_scale
		_class_thrust_mult = 2.28
		mass = _hull_mass
		inertia = Vector3(245000.0, 315000.0, 74000.0)
	else:
		_hull_mass = BASE_MASS
		_probe_scale = Vector3.ONE * hull_scale
		_class_thrust_mult = 1.24
	if start_anchored:
		anchor_down = true
		anchor_progress = 1.0
		_was_anchor_submerged = true
	_build_models()
	_build_collision()
	_build_stations()
	_build_ladders()
	_build_shelters()
	_build_damage_slots()
	_build_hold_water()
	_setup_ship_bell()
	_build_deck_extras()
	_setup_cabin_furnishings()
	_setup_ship_nameplate()
	_setup_hull_crest()
	if enable_effects:
		_build_bow_spray()
		_setup_lookout_glint()
		if faction == &"player":
			_setup_wind_ribbons()
	_setup_sail_shaders()
	_setup_lights_and_glass()
	_apply_current_livery()
	_cache_ropes()
	_register_ocean_mask()
	_last_wind_catch = wind_catch()
	_update_visuals(0.0)


func _exit_tree() -> void:
	_cleanup_all_muzzle_vfx()
	for spray: GPUParticles3D in [_bow_spray_port, _bow_spray_starboard]:
		if spray != null and is_instance_valid(spray):
			spray.emitting = false
			spray.visible = false
			spray.draw_pass_1 = null
			spray.process_material = null
	_bow_spray_port = null
	_bow_spray_starboard = null
	_spray_tex = null
	if _hold_water_mesh != null and is_instance_valid(_hold_water_mesh):
		_hold_water_mesh.material_override = null
		_hold_water_mesh.mesh = null
	_hold_water_mesh = null
	_hold_water_mat = null
	for h in holes:
		var jet := h.get("jet") as GPUParticles3D
		if jet != null and is_instance_valid(jet):
			jet.emitting = false
			jet.visible = false
			jet.draw_pass_1 = null
			jet.process_material = null
	for entry in _hull_mat_entries:
		for target_pair: Array in entry.get("targets", []):
			var target_mi := target_pair[0] as MeshInstance3D
			var target_si := int(target_pair[1])
			if target_mi != null and is_instance_valid(target_mi):
				target_mi.set_surface_override_material(target_si, null)
	_hull_mat_entries.clear()
	for gm in _ghost_hull_mats:
		if gm != null:
			gm.set_shader_parameter(&"albedo_tex", null)
	_ghost_hull_mats.clear()
	for sm in _sail_mats:
		if sm != null:
			sm.set_shader_parameter(&"albedo_tex", null)
	for fmat in _flag_mats:
		if fmat != null:
			fmat.set_shader_parameter(&"albedo_tex", null)
	if _emissary_streamer != null and is_instance_valid(_emissary_streamer):
		_emissary_streamer.material_override = null
		_emissary_streamer.mesh = null
	_emissary_streamer = null
	if _lookout_glint != null and is_instance_valid(_lookout_glint):
		_lookout_glint.material_override = null
		_lookout_glint.mesh = null
	_lookout_glint = null
	_lookout_glint_mat = null
	if _bell_frame_mi != null and is_instance_valid(_bell_frame_mi):
		_bell_frame_mi.material_override = null
		_bell_frame_mi.mesh = null
	if _bell_cup_mi != null and is_instance_valid(_bell_cup_mi):
		_bell_cup_mi.material_override = null
		_bell_cup_mi.mesh = null
	_bell_frame_mi = null
	_bell_cup_mi = null
	_bell_cup_pivot = null
	if _crows_nest_rungs_mi != null and is_instance_valid(_crows_nest_rungs_mi):
		_crows_nest_rungs_mi.material_override = null
		_crows_nest_rungs_mi.mesh = null
	_crows_nest_rungs_mi = null
	crows_nest_ladder = null
	ship_bell_interactable = null
	ship_bell_node = null
	ship_nameplate = null
	hull_crest = null
	wind_ribbons = null
	cabin_furnishings = null
	_unregister_ocean_mask()
	_active_ship_count = maxi(0, _active_ship_count - 1)
	if _active_ship_count == 0:
		_smoke_puff_tex = null
		_muzzle_flash_tex = null
		_muzzle_spark_tex = null
		_streamer_mesh_sloop = null
		_streamer_mesh_brig = null
		_lookout_glint_mesh = null
		_lookout_glint_shader = null
		_bell_frame_mesh = null
		_bell_cup_mesh = null
		_bell_iron_mat = null
		_bell_bronze_mat = null
		_crows_nest_rungs_sloop = null
		_crows_nest_rungs_brig = null
		_crows_nest_rungs_mat = null


# ------------------------------------------------------------------ construction

func _build_models() -> void:
	var model_scene: PackedScene = SLOOP_SCENE
	var lod_scene: PackedScene = SLOOP_LOD_SCENE
	if ship_class == &"brigantine" and ResourceLoader.exists("res://assets/generated/ship/brigantine.glb"):
		model_scene = load("res://assets/generated/ship/brigantine.glb") as PackedScene
		if ResourceLoader.exists("res://assets/generated/ship/brigantine_lod.glb"):
			lod_scene = load("res://assets/generated/ship/brigantine_lod.glb") as PackedScene

	_model = model_scene.instantiate() as Node3D
	_model.name = "BrigantineModel" if ship_class == &"brigantine" else "SloopModel"
	_model.scale = Vector3.ONE * hull_scale
	add_child(_model)

	_lod_model = lod_scene.instantiate() as Node3D
	_lod_model.name = "BrigantineLOD" if ship_class == &"brigantine" else "SloopLOD"
	_lod_model.scale = Vector3.ONE * hull_scale
	_lod_model.visible = false
	add_child(_lod_model)

	_wheel = _n("Wheel")
	_rudder = _n("Rudder")
	_yards.clear()
	_sails.clear()
	_sails_furled.clear()
	_flags.clear()
	for suffix: String in ["", "_Fore"]:
		var y := _n("Yard" + suffix)
		if y != null:
			_yards.append(y)
		var s := _n("Sail" + suffix) as MeshInstance3D
		if s != null:
			_sails.append(s)
		var sf := _n("Sail_Furled" + suffix)
		if sf != null:
			_sails_furled.append(sf)
		var fl := _n("Flag" + suffix) as MeshInstance3D
		if fl != null:
			_flags.append(fl)
	_build_emissary_streamer()

	_capstan = _n("Capstan")
	_anchor_node = _n("Anchor")
	if _anchor_node != null:
		_anchor_base_pos = _anchor_node.position
	_bell = _n("Bell")
	_mask_water = _n("mask_water") as MeshInstance3D

	_lod_yards.clear()
	_lod_sails.clear()
	_lod_sails_furled.clear()
	_lod_flags.clear()
	if _lod_model != null:
		for suffix: String in ["", "_Fore"]:
			var ly := _lod_model.get_node_or_null("Yard" + suffix) as Node3D
			if ly != null:
				_lod_yards.append(ly)
			var ls := _lod_model.get_node_or_null("Sail" + suffix) as Node3D
			if ls != null:
				_lod_sails.append(ls)
			var lsf := _lod_model.get_node_or_null("Sail_Furled" + suffix) as Node3D
			if lsf != null:
				_lod_sails_furled.append(lsf)
			var lfl := _lod_model.get_node_or_null("Flag" + suffix) as Node3D
			if lfl != null:
				_lod_flags.append(lfl)

	# Hide non-visual helper nodes per docs/SHIP_ART.md.
	for child in _model.get_children():
		var nm := String(child.name)
		if nm.begins_with("col_") or nm.begins_with("mask_") \
				or nm.begins_with("Hole_") or nm.begins_with("HolePatch_") \
				or nm.begins_with("Sail_Furled"):
			child.visible = false


func _build_collision() -> void:
	if _model == null:
		return
	for node in _model.find_children("col_*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		mi.visible = false
		var faces := mi.mesh.get_faces()
		if faces.size() < 3:
			continue
		var xf := _local_to_ship(mi)
		var scl := xf.basis.get_scale()
		var pts := PackedVector3Array()
		pts.resize(faces.size())
		for fi in faces.size():
			pts[fi] = faces[fi] * scl
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		var cs := CollisionShape3D.new()
		cs.name = "Col_" + String(mi.name)
		cs.shape = shape
		cs.transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
		add_child(cs)


func _build_stations() -> void:
	var specs: Array[Array] = [
		["Station_Helm", &"helm", "Take the helm", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.78)), Vector3(0.0, 0.95, 0.0), 0.65, &""],
		["Station_SailLength", &"sail_length", "Raise / lower sail", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.62, 0.0, 0.0)), Vector3(0.0, 0.85, 0.0), 0.6, &""],
		["Station_SailAngle", &"sail_angle", "Trim sail angle", Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-0.62, 0.0, 0.0)), Vector3(0.0, 0.85, 0.0), 0.6, &""],
		["Station_Anchor", &"anchor", "Use capstan (anchor)", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 1.08)), Vector3(0.0, 0.85, 0.0), 0.7, &""],
		["Station_CannonPort", &"cannon", "Man port cannon", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 1.12)), Vector3(0.0, 0.85, 0.2), 0.7, &"port"],
		["Station_CannonStarboard", &"cannon", "Man starboard cannon", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 1.12)), Vector3(0.0, 0.85, 0.2), 0.7, &"starboard"],
		["Station_CannonPortAft", &"cannon", "Man aft port cannon", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 1.12)), Vector3(0.0, 0.85, 0.2), 0.7, &"port_aft"],
		["Station_CannonStarboardAft", &"cannon", "Man aft starboard cannon", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 1.12)), Vector3(0.0, 0.85, 0.2), 0.7, &"starboard_aft"],
		["Station_MapTable", &"map_table", "Inspect map table", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.90)), Vector3(0.0, 0.9, 0.0), 0.7, &""],
		["Station_Bilge", &"bilge", "Bail bilge water", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.35)), Vector3(0.0, 0.75, 0.0), 0.7, &""],
	]
	for spec in specs:
		var marker := _n(String(spec[0]))
		if marker == null:
			continue
		var xf := _local_to_ship(marker)
		var st := Station.new()
		st.name = String(spec[0]) + "_Node"
		st.transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
		st.configure(self, spec[1], spec[2], spec[3], spec[4], spec[5], spec[6])
		add_child(st)
		_stations.append(st)
		var kind: StringName = spec[1]
		if not _stations_by_kind.has(kind):
			_stations_by_kind[kind] = []
		(_stations_by_kind[kind] as Array).append(st)

	# Wire cannon carriages and barrels from the model (2 on Sloop, 4 on Brigantine).
	var cannon_specs: Array[Array] = [
		[&"port", "Cannon_Port"],
		[&"starboard", "Cannon_Starboard"],
		[&"port_aft", "Cannon_Port_Aft"],
		[&"starboard_aft", "Cannon_Starboard_Aft"],
	]
	for side_pair: Array in cannon_specs:
		var side_key: StringName = side_pair[0]
		var cname: String = side_pair[1]
		var carriage := _n(cname)
		var barrel := _n(cname + "/" + cname + "_Barrel")
		if carriage != null:
			_cannons[side_key] = {
				"carriage": carriage,
				"barrel": barrel,
				"base_pos": carriage.position,
				"base_rot_y": carriage.rotation.y,
				"base_barrel_rot_x": barrel.rotation.x if barrel != null else 0.0,
				"yaw": 0.0,
				"pitch": 0.08,
				"reload": 0.0,
				"recoil": 0.0,
			}


func _build_ladders() -> void:
	# Hull ladders from Station_Ladder_Port (-X outboard) and Station_Ladder_Starboard (+X outboard).
	# Ladder local +Y = up, +Z = outboard (climber hangs on +Z facing -Z into hull).
	var ladder_specs: Array[Array] = [
		["Station_Ladder_Port", "Ladder_Port", -PI * 0.5],
		["Station_Ladder_Starboard", "Ladder_Starboard", PI * 0.5],
	]
	for spec in ladder_specs:
		var marker := _n(String(spec[0]))
		if marker == null:
			continue
		var lp := _local_to_ship(marker).origin
		var lad := Ladder.new()
		lad.name = String(spec[1])
		lad.height = 2.75 * hull_scale
		lad.width = 0.85
		lad.standoff = 0.42
		lad.reach_below = 1.6 * hull_scale
		lad.exit_offset = Vector3(0.0, 0.1, -0.92)
		# Place foot below the waterline marker so the top aligns with the scaled main deck.
		lad.transform = Transform3D(Basis(Vector3.UP, float(spec[2])), Vector3(lp.x, lp.y - 1.6 * hull_scale, lp.z))
		add_child(lad)

	_build_crows_nest_ladder()


func _build_crows_nest_ladder() -> void:
	# Climbable mainmast Crow's Nest ladder positioned on the starboard-aft face of the mainmast:
	# clears the swinging yard/sail forward, Lantern_Mast aft, and Sloop's open hold hatch so
	# bottom dismount always lands on solid main deck and top exit steps safely onto col_mast_top!
	var is_brig := ship_class == &"brigantine"
	var mast_z := (0.50 if is_brig else -1.00) * hull_scale
	var deck_y := (1.25 if is_brig else 1.10) * hull_scale
	var nest_top_y := (13.17 if is_brig else 11.52) * hull_scale
	var mast_r := (0.37 if is_brig else 0.33) * hull_scale
	var yaw_rad := deg_to_rad(32.0) if is_brig else deg_to_rad(80.0)
	var lad_h := nest_top_y - deck_y
	var out_dir := Vector3(sin(yaw_rad), 0.0, cos(yaw_rad))
	var foot_pos := Vector3(out_dir.x * mast_r, deck_y, mast_z + out_dir.z * mast_r)
	var lad_xf := Transform3D(Basis(Vector3.UP, yaw_rad), foot_pos)

	var cn := Ladder.new()
	cn.name = "Ladder_CrowsNest"
	cn.height = lad_h
	cn.width = 0.68
	cn.standoff = 0.42
	cn.reach_below = 0.15
	cn.require_direct_approach = true
	cn.allow_ai_grab = false
	# Step inward across the topmast onto the solid circular col_mast_top platform.
	cn.exit_offset = Vector3(0.0, 0.10, (-0.88 if is_brig else -0.80) * hull_scale)
	cn.transform = lad_xf
	add_child(cn)
	crows_nest_ladder = cn

	_ensure_crows_nest_rungs_assets()
	var rungs_mi := MeshInstance3D.new()
	rungs_mi.name = "CrowsNestRungs"
	rungs_mi.mesh = _crows_nest_rungs_brig if is_brig else _crows_nest_rungs_sloop
	rungs_mi.material_override = _crows_nest_rungs_mat
	rungs_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rungs_mi.transform = lad_xf
	rungs_mi.scale = Vector3.ONE * hull_scale
	add_child(rungs_mi)
	_crows_nest_rungs_mi = rungs_mi


static func _ensure_crows_nest_rungs_assets() -> void:
	if _crows_nest_rungs_mat == null:
		_crows_nest_rungs_mat = StandardMaterial3D.new()
		_crows_nest_rungs_mat.vertex_color_use_as_albedo = true
		_crows_nest_rungs_mat.vertex_color_is_srgb = true
		_crows_nest_rungs_mat.roughness = 0.84
		_crows_nest_rungs_mat.metallic = 0.04
	if _crows_nest_rungs_sloop == null:
		_crows_nest_rungs_sloop = _build_crows_nest_rungs_mesh(false)
	if _crows_nest_rungs_brig == null:
		_crows_nest_rungs_brig = _build_crows_nest_rungs_mesh(true)


static func _build_crows_nest_rungs_mesh(is_brig: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var height := (13.17 - 1.25) if is_brig else (11.52 - 1.10)
	var flare_start_y := (11.35 - 1.25) if is_brig else (9.75 - 1.10)
	var tub_bot_y := (12.10 - 1.25) if is_brig else (10.50 - 1.10)
	var rim_out_z := 0.70 if is_brig else 0.65
	var tub_out_z := 0.52 if is_brig else 0.49
	var half_w := 0.22

	var col_rope_hi := Color(0.32, 0.25, 0.18)
	var col_rope_lo := Color(0.15, 0.11, 0.08)
	var col_oak_top := Color(0.68, 0.48, 0.26)
	var col_oak_side := Color(0.48, 0.31, 0.16)
	var col_oak_bot := Color(0.26, 0.16, 0.08)
	var col_lash_hi := Color(0.24, 0.19, 0.14)
	var col_lash_lo := Color(0.12, 0.09, 0.07)

	# Helper closure computing futtock-shroud +Z flare around the Crow's Nest stave tub.
	var z_at := func(y: float) -> float:
		if y <= flare_start_y:
			return 0.02
		if y <= tub_bot_y:
			var t0 := clampf((y - flare_start_y) / maxf(tub_bot_y - flare_start_y, 0.01), 0.0, 1.0)
			return lerpf(0.02, tub_out_z, t0)
		var t1 := clampf((y - tub_bot_y) / maxf(height - tub_bot_y, 0.01), 0.0, 1.0)
		return lerpf(tub_out_z, rim_out_z, t1)

	# 1. Twin taut tarred vertical hemp side-ropes running from main deck up & flaring over the nest rim.
	var rope_ys: Array[float] = [0.06, flare_start_y, tub_bot_y, height - 0.02]
	for sx: float in [-1.0, 1.0]:
		var rx := sx * half_w
		for i in rope_ys.size() - 1:
			var ya := rope_ys[i]
			var yb := rope_ys[i + 1]
			var pa := Vector3(rx, ya, float(z_at.call(ya)))
			var pb := Vector3(rx, yb, float(z_at.call(yb)))
			_cn_add_tube(st, pa, pb, 0.022, 6, col_rope_hi, col_rope_lo)

	# 2. Evenly spaced chunky beveled oak ratline rungs + hemp seizing collars gripping both side-ropes.
	var step_y := 0.36
	var y_cur := 0.28
	while y_cur < height - 0.12:
		var rz := float(z_at.call(y_cur))
		# Main beveled oak rung bar.
		_cn_add_box(st, Vector3(0.0, y_cur, rz), Vector3(half_w * 2.0 + 0.08, 0.040, 0.036),
			col_oak_top, col_oak_side, col_oak_bot)
		# Pair of tarred hemp lashing collars clamping rung to left/right side-ropes.
		for sx: float in [-1.0, 1.0]:
			_cn_add_box(st, Vector3(sx * half_w, y_cur, rz), Vector3(0.056, 0.052, 0.052),
				col_lash_hi, col_lash_hi, col_lash_lo)
		y_cur += step_y

	# 3. Mast seizure lashing straps anchoring the side-ropes cleanly against the mast barrel.
	var strap_y := 1.6
	while strap_y < flare_start_y - 0.5:
		_cn_add_box(st, Vector3(0.0, strap_y, -0.005), Vector3(half_w * 2.0 + 0.06, 0.048, 0.046),
			col_lash_hi, col_lash_lo, col_lash_lo)
		strap_y += 2.2

	st.generate_normals()
	return st.commit()


static func _cn_add_box(st: SurfaceTool, center: Vector3, size: Vector3,
		col_top: Color, col_side: Color, col_bot: Color) -> void:
	var h := size * 0.5
	var c: Array[Vector3] = [
		center + Vector3(-h.x, -h.y, -h.z),
		center + Vector3(h.x, -h.y, -h.z),
		center + Vector3(h.x, h.y, -h.z),
		center + Vector3(-h.x, h.y, -h.z),
		center + Vector3(-h.x, -h.y, h.z),
		center + Vector3(h.x, -h.y, h.z),
		center + Vector3(h.x, h.y, h.z),
		center + Vector3(-h.x, h.y, h.z),
	]
	_cn_outward_quad(st, c[3], c[2], c[6], c[7], center, col_top, col_top, col_top, col_top)
	_cn_outward_quad(st, c[4], c[5], c[1], c[0], center, col_bot, col_bot, col_bot, col_bot)
	_cn_outward_quad(st, c[0], c[1], c[2], c[3], center, col_bot, col_bot, col_side, col_side)
	_cn_outward_quad(st, c[5], c[4], c[7], c[6], center, col_bot, col_bot, col_side, col_side)
	_cn_outward_quad(st, c[4], c[0], c[3], c[7], center, col_bot, col_bot, col_side, col_side)
	_cn_outward_quad(st, c[1], c[5], c[6], c[2], center, col_bot, col_bot, col_side, col_side)


static func _cn_add_tube(st: SurfaceTool, a: Vector3, b: Vector3, radius: float, segs: int,
		col_hi: Color, col_lo: Color) -> void:
	var axis := b - a
	var length := axis.length()
	if length < 0.0001:
		return
	var dir := axis / length
	var ref := Vector3.FORWARD if absf(dir.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var u := dir.cross(ref).normalized()
	var v := dir.cross(u).normalized()
	var mid := (a + b) * 0.5
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var o0 := (u * cos(a0) + v * sin(a0)) * radius
		var o1 := (u * cos(a1) + v * sin(a1)) * radius
		var c0 := col_lo.lerp(col_hi, clampf(0.5 + 0.5 * o0.normalized().z, 0.0, 1.0))
		var c1 := col_lo.lerp(col_hi, clampf(0.5 + 0.5 * o1.normalized().z, 0.0, 1.0))
		_cn_outward_quad(st, a + o0, b + o0, b + o1, a + o1, mid, c0, c0, c1, c1)
		_cn_outward_tri(st, a, a + o0, a + o1, mid, col_lo, c0, c1)
		_cn_outward_tri(st, b, b + o1, b + o0, mid, col_hi, c1, c0)


static func _cn_outward_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_cn_outward_tri(st, a, b, c, ref_center, ca, cb, cc)
	_cn_outward_tri(st, a, c, d, ref_center, ca, cc, cd)


static func _cn_outward_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	var centroid := (a + b + c) / 3.0
	if n.dot(centroid - ref_center) < 0.0:
		var tv := b
		b = c
		c = tv
		var tc := cb
		cb = cc
		cc = tc
	st.set_smooth_group(-1)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_smooth_group(-1)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_smooth_group(-1)
	st.set_color(cc)
	st.add_vertex(c)


func _build_shelters() -> void:
	# Shelter boxes in group `shelter` tell SkyRig to stop rain/mist below deck.
	var shelter_area := Area3D.new()
	shelter_area.name = "HoldShelter"
	shelter_area.add_to_group(&"shelter")
	shelter_area.collision_layer = 0
	shelter_area.collision_mask = 0
	shelter_area.monitoring = false
	shelter_area.monitorable = false
	add_child(shelter_area)

	var hold_box := BoxShape3D.new()
	hold_box.size = Vector3(3.7, 2.05, 8.6) * hull_scale
	var cs_hold := CollisionShape3D.new()
	cs_hold.name = "HoldBox"
	cs_hold.shape = hold_box
	cs_hold.position = Vector3(0.0, 0.12, 0.2) * hull_scale
	shelter_area.add_child(cs_hold)

	var cabin_box := BoxShape3D.new()
	cabin_box.size = Vector3(3.4, 2.8, 3.3) * hull_scale
	var cs_cabin := CollisionShape3D.new()
	cs_cabin.name = "SternCabinBox"
	cs_cabin.shape = cabin_box
	cs_cabin.position = Vector3(0.0, 0.55, 4.6) * hull_scale
	shelter_area.add_child(cs_cabin)


func _build_damage_slots() -> void:
	holes.clear()
	for i in range(1, HOLE_SLOTS + 1):
		var num := "%02d" % i
		var panel := _n("HullPanel_" + num)
		var hole := _n("Hole_" + num)
		var patch := _n("HolePatch_" + num)
		var local_pos := Vector3.ZERO
		var hole_basis := Basis.IDENTITY
		if hole != null:
			var xf := _local_to_ship(hole)
			local_pos = xf.origin
			hole_basis = xf.basis.orthonormalized()
		elif panel != null:
			var xf2 := _local_to_ship(panel)
			local_pos = xf2.origin
			hole_basis = xf2.basis.orthonormalized()

		if panel != null:
			panel.visible = true
		if hole != null:
			hole.visible = false
		if patch != null:
			patch.visible = false

		# Inward water-spray particle jet (activated when breached & submerged).
		var jet: GPUParticles3D = null
		if enable_effects:
			jet = _make_leak_jet(local_pos, hole_basis)
			add_child(jet)

		# Interactable inside the hold for direct manual/AI patching.
		var it := Interactable.create("Patch hull breach", 0.72)
		it.name = "PatchPoint_" + num
		it.enabled = false
		# Offset slightly inboard (+Z in hole-local space since -Z points outboard per SHIP_ART.md).
		it.position = local_pos + hole_basis.z * 0.42
		var slot_idx := i - 1
		it.interacted.connect(func(pawn: Node) -> void:
			_on_hole_interacted(slot_idx, pawn)
		)
		add_child(it)

		holes.append({
			"index": slot_idx,
			"name": num,
			"breached": false,
			"patched": false,
			"severity": 0.0,
			"local_pos": local_pos,
			"panel": panel,
			"hole": hole,
			"patch": patch,
			"jet": jet,
			"interactable": it,
		})


func _get_spray_texture() -> GradientTexture2D:
	if _spray_tex != null:
		return _spray_tex
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.30, 0.68, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.94),
		Color(0.95, 0.99, 1.0, 0.62),
		Color(0.86, 0.96, 1.0, 0.18),
		Color(0.84, 0.95, 1.0, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.gradient = grad
	_spray_tex = tex
	return _spray_tex


func _make_spray_material(tint: Color, emit_tint: Color, emit_energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _get_spray_texture()
	mat.albedo_color = tint
	mat.roughness = 0.85
	mat.backlight_enabled = true
	mat.backlight = Color(0.78, 0.88, 0.92)
	if emit_energy > 0.001:
		mat.emission_enabled = true
		mat.emission = emit_tint
		mat.emission_energy_multiplier = emit_energy
	return mat


static func _make_color_ramp(offsets: PackedFloat32Array, colors: PackedColorArray) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = offsets
	grad.colors = colors
	var tex := GradientTexture1D.new()
	tex.width = 32
	tex.gradient = grad
	return tex


static func _make_scale_curve(points: Array[Vector2]) -> CurveTexture:
	var curve := Curve.new()
	var max_y := 1.0
	for pt in points:
		max_y = maxf(max_y, pt.y)
	curve.min_value = 0.0
	curve.max_value = max_y
	for pt in points:
		curve.add_point(pt)
	var tex := CurveTexture.new()
	tex.curve = curve
	return tex


func _make_leak_jet(local_pos: Vector3, hole_basis: Basis) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "LeakJet"
	p.emitting = false
	p.visible = false
	p.amount = 44
	p.lifetime = 0.34
	p.local_coords = true
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = local_pos + hole_basis.z * 0.08

	var proc := ParticleProcessMaterial.new()
	# Hole -Z points outboard, so +Z sprays inward and arcs naturally down into the bilge.
	var inward := (hole_basis.z + Vector3(0.0, 0.12, 0.0)).normalized()
	proc.direction = inward
	proc.spread = 11.0
	proc.initial_velocity_min = 1.8
	proc.initial_velocity_max = 3.0
	proc.gravity = Vector3(0.0, -13.5, 0.0)
	proc.damping_min = 0.6
	proc.damping_max = 1.4
	proc.scale_min = 0.65
	proc.scale_max = 1.15
	proc.scale_curve = _make_scale_curve([Vector2(0.0, 0.65), Vector2(0.35, 1.05), Vector2(1.0, 0.55)])
	proc.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.18, 0.65, 1.0]),
		PackedColorArray([
			Color(0.88, 0.97, 1.0, 0.72),
			Color(0.80, 0.95, 0.99, 0.78),
			Color(0.74, 0.93, 0.97, 0.42),
			Color(0.70, 0.90, 0.96, 0.0),
		])
	)
	p.process_material = proc

	var streak := QuadMesh.new()
	streak.size = Vector2(0.095, 0.24)
	streak.material = _make_spray_material(
		Color(0.78, 0.95, 0.98, 0.84),
		Color(0.55, 0.82, 0.88),
		0.14
	)
	p.draw_pass_1 = streak
	return p


func _build_bow_spray() -> void:
	var is_brig := ship_class == &"brigantine"
	var x_off := (1.75 if is_brig else 1.35) * hull_scale
	var y_off := (0.45 if is_brig else 0.35) * hull_scale
	var z_off := (-7.6 if is_brig else -5.4) * hull_scale
	_bow_spray_port = _make_bow_cheek_spray("BowSprayPort", Vector3(-x_off, y_off, z_off), -1.0)
	_bow_spray_starboard = _make_bow_cheek_spray("BowSprayStarboard", Vector3(x_off, y_off, z_off), 1.0)
	add_child(_bow_spray_port)
	add_child(_bow_spray_starboard)


func _make_bow_cheek_spray(node_name: String, pos: Vector3, side_sign: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = node_name
	p.emitting = false
	p.amount = 38
	p.lifetime = 0.56
	p.local_coords = false
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = pos
	p.visibility_aabb = AABB(Vector3(-6.0, -3.0, -8.0), Vector3(12.0, 8.0, 16.0))

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(0.08, 0.12, 0.48)
	# Flare spray dramatically outboard & upward off the bow wave so it never enters the hull.
	proc.direction = Vector3(side_sign * 0.78, 0.62, 0.12).normalized()
	proc.spread = 18.0
	proc.initial_velocity_min = 3.4
	proc.initial_velocity_max = 5.6
	proc.inherit_velocity_ratio = 0.45
	proc.damping_min = 0.7
	proc.damping_max = 1.5
	proc.gravity = Vector3(0.0, -9.8, 0.0)
	proc.scale_min = 0.70
	proc.scale_max = 1.45
	proc.scale_curve = _make_scale_curve([Vector2(0.0, 0.60), Vector2(0.35, 1.15), Vector2(1.0, 1.50)])
	proc.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.14, 0.62, 1.0]),
		PackedColorArray([
			Color(0.95, 0.99, 1.0, 0.0),
			Color(0.92, 0.98, 1.0, 0.82),
			Color(0.86, 0.96, 0.99, 0.44),
			Color(0.82, 0.94, 0.98, 0.0),
		])
	)
	p.process_material = proc

	var drop := QuadMesh.new()
	drop.size = Vector2(0.28, 0.40)
	drop.material = _make_spray_material(
		Color(0.90, 0.97, 0.99, 0.84),
		Color(0.76, 0.90, 0.94),
		0.10
	)
	p.draw_pass_1 = drop
	return p


func _build_hold_water() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(4.0, 10.2)
	pm.subdivide_width = 14
	pm.subdivide_depth = 28

	_hold_water_mat = ShaderMaterial.new()
	_hold_water_mat.shader = HOLD_WATER_SHADER
	_hold_water_mat.set_shader_parameter(&"water_level", 0.0)

	_hold_water_mesh = MeshInstance3D.new()
	_hold_water_mesh.name = "HoldWater"
	_hold_water_mesh.mesh = pm
	_hold_water_mesh.material_override = _hold_water_mat
	_hold_water_mesh.scale = Vector3.ONE * hull_scale
	_hold_water_mesh.position = Vector3(0.0, 0.0, 0.75 * hull_scale)
	_hold_water_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hold_water_mesh.visible = false
	add_child(_hold_water_mesh)


func _build_deck_extras() -> void:
	# Ship's bell interactable (fallback only if sculpted player ShipBell was not mounted).
	if ship_bell_interactable == null and _bell != null:
		var bell_it := Interactable.create("Ring ship's bell", 0.55)
		bell_it.name = "BellInteractable"
		bell_it.position = _local_to_ship(_bell).origin
		bell_it.interacted.connect(func(pawn: Node) -> void:
			ring_bell(pawn)
		)
		add_child(bell_it)

	# One-press supply refill barrel interactable on deck (DESIGN.md: "Tedium cuts").
	var supply_pos := Vector3(1.15, 1.55, -2.55) * hull_scale
	var plank_node := _n("PlankStack")
	if plank_node != null:
		supply_pos = _local_to_ship(plank_node).origin + Vector3(0.0, 0.45, 0.0)
	var supply_it := Interactable.create("Restock supplies (ammo & planks)", 0.75)
	supply_it.name = "SupplyBarrelsInteractable"
	supply_it.position = supply_pos
	supply_it.interacted.connect(func(pawn: Node) -> void:
		if not Net.is_host():
			return
		restock_supplies()
		Audio.play_sfx(&"chest_thump", supply_it.global_position, -4.0)
		supplies_taken.emit(pawn)
	)
	add_child(supply_it)


func _setup_sail_shaders() -> void:
	_sail_mats.clear()
	_flag_mats.clear()
	for sail_node in _sails:
		if sail_node == null or sail_node.mesh == null:
			continue
		var m := sail_node.mesh.duplicate() as Mesh
		sail_node.mesh = m
		for surf_i in m.get_surface_count():
			var orig := m.surface_get_material(surf_i) as BaseMaterial3D
			var mat_name := orig.resource_name if orig != null else ""
			var sm := ShaderMaterial.new()
			sm.shader = SAIL_WIND_SHADER
			var is_back := mat_name == "mat_canvas_back" or surf_i > 0
			sm.set_shader_parameter(&"is_flag", 0.0)
			sm.set_shader_parameter(&"is_back_face", 1.0 if is_back else 0.0)
			if orig != null and orig.albedo_texture != null:
				sm.set_shader_parameter(&"albedo_tex", orig.albedo_texture)
				sm.set_shader_parameter(&"use_albedo_tex", 1.0)
			else:
				sm.set_shader_parameter(&"use_albedo_tex", 0.0)
			sm.set_shader_parameter(&"albedo_tint", _livery_sail_tint)
			sm.set_shader_parameter(&"emission_strength", 0.08 if is_back else 0.0)
			m.surface_set_material(surf_i, sm)
			_sail_mats.append(sm)

	for flag_node in _flags:
		if flag_node == null or flag_node.mesh == null:
			continue
		var fm := flag_node.mesh.duplicate() as Mesh
		flag_node.mesh = fm
		if fm.get_surface_count() > 0:
			var orig_f := fm.surface_get_material(0) as BaseMaterial3D
			var fmat := ShaderMaterial.new()
			fmat.shader = SAIL_WIND_SHADER
			fmat.set_shader_parameter(&"is_flag", 1.0)
			fmat.set_shader_parameter(&"is_back_face", 0.0)
			if orig_f != null and orig_f.albedo_texture != null:
				fmat.set_shader_parameter(&"albedo_tex", orig_f.albedo_texture)
				fmat.set_shader_parameter(&"use_albedo_tex", 1.0)
			else:
				fmat.set_shader_parameter(&"use_albedo_tex", 0.0)
			fmat.set_shader_parameter(&"albedo_tint", _livery_flag_tint)
			fm.surface_set_material(0, fmat)
			_flag_mats.append(fmat)

	if _emissary_streamer != null and is_instance_valid(_emissary_streamer):
		var smat := ShaderMaterial.new()
		smat.shader = SAIL_WIND_SHADER
		smat.set_shader_parameter(&"is_flag", 1.0)
		smat.set_shader_parameter(&"is_back_face", 0.0)
		smat.set_shader_parameter(&"use_albedo_tex", 0.0)
		smat.set_shader_parameter(&"albedo_tint", _livery_flag_tint)
		_emissary_streamer.material_override = smat
		_flag_mats.append(smat)


func _build_emissary_streamer() -> void:
	if _flags.is_empty() or _flags[0] == null:
		return
	var main_flag := _flags[0]
	var parent_node := main_flag.get_parent() as Node3D
	if parent_node == null:
		parent_node = _model
	if parent_node == null:
		return

	var is_brig := ship_class == &"brigantine"
	var streamer_mesh := _get_streamer_mesh(is_brig)
	_emissary_streamer = MeshInstance3D.new()
	_emissary_streamer.name = "EmissaryStreamer"
	_emissary_streamer.mesh = streamer_mesh
	_emissary_streamer.position = main_flag.position + Vector3(0.0, 0.55, 0.0)
	_emissary_streamer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent_node.add_child(_emissary_streamer)


static func _get_streamer_mesh(is_brigantine: bool) -> ArrayMesh:
	if is_brigantine:
		if _streamer_mesh_brig == null:
			_streamer_mesh_brig = _build_emissary_streamer_mesh(5.4)
		return _streamer_mesh_brig
	if _streamer_mesh_sloop == null:
		_streamer_mesh_sloop = _build_emissary_streamer_mesh(4.4)
	return _streamer_mesh_sloop


static func _build_emissary_streamer_mesh(length_m: float) -> ArrayMesh:
	# Long tapering twin-tailed masthead emissary streamer extending along local -Z
	# with a rigid gilded brass finial staff extension anchored down into the mast truck.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Rigid 5-sided gilded brass finial spire (UV.x = -1.0 marks brass staff, UV2.x = 0.0 pinned!).
	const STAFF_SEGS := 5
	var staff_y0 := -0.58
	var staff_y1 := 0.28
	var staff_r0 := 0.026
	var staff_r1 := 0.015
	var staff_uv := Vector2(-1.0, 0.5)
	var staff_uv2 := Vector2(0.0, 0.5)
	var col_brass := Color(0.92, 0.74, 0.28)
	var col_brass_lo := Color(0.68, 0.50, 0.16)
	for k in STAFF_SEGS:
		var a0 := float(k) / float(STAFF_SEGS) * TAU
		var a1 := float((k + 1) % STAFF_SEGS) / float(STAFF_SEGS) * TAU
		var p00 := Vector3(cos(a0) * staff_r0, staff_y0, sin(a0) * staff_r0)
		var p01 := Vector3(cos(a1) * staff_r0, staff_y0, sin(a1) * staff_r0)
		var p10 := Vector3(cos(a0) * staff_r1, staff_y1, sin(a0) * staff_r1)
		var p11 := Vector3(cos(a1) * staff_r1, staff_y1, sin(a1) * staff_r1)
		_emit_streamer_tri(st, p00, p11, p10, col_brass_lo, col_brass, col_brass, staff_uv, staff_uv, staff_uv, staff_uv2, staff_uv2, staff_uv2, -1)
		_emit_streamer_tri(st, p00, p01, p11, col_brass_lo, col_brass_lo, col_brass, staff_uv, staff_uv, staff_uv, staff_uv2, staff_uv2, staff_uv2, -1)
		# Pointed brass finial cap atop the staff.
		var tip := Vector3(0.0, staff_y1 + 0.09, 0.0)
		_emit_streamer_tri(st, p10, p11, tip, col_brass, col_brass, col_brass, staff_uv, staff_uv, staff_uv, staff_uv2, staff_uv2, staff_uv2, -1)

	# 2. Subdivided 16-segment tapering streamer ribbon (segments 0..12 solid, 13..15 twin swallowtail forks).
	const TOTAL_SEGS := 16
	const FORK_START := 13
	var col_light := Color(0.98, 0.96, 0.90)
	var col_stripe := Color(0.70, 0.68, 0.66)

	for i in FORK_START:
		var t0 := float(i) / float(TOTAL_SEGS)
		var t1 := float(i + 1) / float(TOTAL_SEGS)
		var z0 := -t0 * length_m
		var z1 := -t1 * length_m
		var yc0 := 0.36 * pow(t0, 1.25) + 0.05 * sin(t0 * TAU)
		var yc1 := 0.36 * pow(t1, 1.25) + 0.05 * sin(t1 * TAU)
		var hh0 := lerpf(0.23, 0.092, pow(t0, 0.85))
		var hh1 := lerpf(0.23, 0.092, pow(t1, 0.85))
		var c0 := col_light if (i % 2 == 0) else col_stripe
		var c1 := c0

		var top0 := Vector3(0.0, yc0 + hh0, z0)
		var mid0 := Vector3(0.0, yc0, z0)
		var bot0 := Vector3(0.0, yc0 - hh0, z0)
		var top1 := Vector3(0.0, yc1 + hh1, z1)
		var mid1 := Vector3(0.0, yc1, z1)
		var bot1 := Vector3(0.0, yc1 - hh1, z1)

		var u_t0 := Vector2(t0, 0.0)
		var u_m0 := Vector2(t0, 0.5)
		var u_b0 := Vector2(t0, 1.0)
		var u_t1 := Vector2(t1, 0.0)
		var u_m1 := Vector2(t1, 0.5)
		var u_b1 := Vector2(t1, 1.0)

		# Upper ribbon strip.
		_emit_streamer_tri(st, top0, top1, mid1, c0, c1, c1, u_t0, u_t1, u_m1, u_t0, u_t1, u_m1, 1)
		_emit_streamer_tri(st, top0, mid1, mid0, c0, c1, c0, u_t0, u_m1, u_m0, u_t0, u_m1, u_m0, 1)
		# Lower ribbon strip.
		_emit_streamer_tri(st, mid0, mid1, bot1, c0, c1, c1, u_m0, u_m1, u_b1, u_m0, u_m1, u_b1, 1)
		_emit_streamer_tri(st, mid0, bot1, bot0, c0, c1, c0, u_m0, u_b1, u_b0, u_m0, u_b1, u_b0, 1)

	# 3. Twin notched swallowtail fork tips (upper & lower whipping tails, t = FORK_START/16 .. 1.0).
	var fork_segs := TOTAL_SEGS - FORK_START
	for tail_sgn: float in [1.0, -1.0]:
		for fi in fork_segs:
			var idx0 := FORK_START + fi
			var idx1 := idx0 + 1
			var t0 := float(idx0) / float(TOTAL_SEGS)
			var t1 := float(idx1) / float(TOTAL_SEGS)
			var frac0 := float(fi) / float(fork_segs)
			var frac1 := float(fi + 1) / float(fork_segs)
			var z0 := -t0 * length_m
			var z1 := -t1 * length_m
			var yc0 := 0.36 * pow(t0, 1.25) + 0.05 * sin(t0 * TAU)
			var yc1 := 0.36 * pow(t1, 1.25) + 0.05 * sin(t1 * TAU)
			var base_hh0 := lerpf(0.23, 0.092, pow(t0, 0.85))
			var base_hh1 := lerpf(0.23, 0.092, pow(t1, 0.85))

			# Outer edge flares slightly outward; inner notch edge sweeps sharply away from centerline!
			var out_y0 := yc0 + tail_sgn * (base_hh0 + 0.038 * frac0)
			var out_y1 := yc1 + tail_sgn * (base_hh1 + 0.038 * frac1)
			var in_y0 := yc0 + tail_sgn * (base_hh0 * lerpf(0.0, 0.96, frac0) + 0.026 * frac0)
			var in_y1 := yc1 + tail_sgn * (base_hh1 * lerpf(0.0, 0.96, frac1) + 0.026 * frac1)

			var c := col_light if (idx0 % 2 == 0) else col_stripe
			var v_out := 0.0 if tail_sgn > 0.0 else 1.0
			var v_in0 := lerpf(0.5, v_out, frac0 * 0.85)
			var v_in1 := lerpf(0.5, v_out, frac1 * 0.85)

			var po0 := Vector3(0.0, out_y0, z0)
			var pi0 := Vector3(0.0, in_y0, z0)
			var po1 := Vector3(0.0, out_y1, z1)
			var pi1 := Vector3(0.0, in_y1, z1)

			var uo0 := Vector2(t0, v_out)
			var ui0 := Vector2(t0, v_in0)
			var uo1 := Vector2(t1, v_out)
			var ui1 := Vector2(t1, v_in1)

			# Order top-to-bottom (hi above lo) so both upper and lower forks share identical winding.
			var hi0 := po0 if tail_sgn > 0.0 else pi0
			var lo0 := pi0 if tail_sgn > 0.0 else po0
			var hi1 := po1 if tail_sgn > 0.0 else pi1
			var lo1 := pi1 if tail_sgn > 0.0 else po1
			var uhi0 := uo0 if tail_sgn > 0.0 else ui0
			var ulo0 := ui0 if tail_sgn > 0.0 else uo0
			var uhi1 := uo1 if tail_sgn > 0.0 else ui1
			var ulo1 := ui1 if tail_sgn > 0.0 else uo1

			if fi == fork_segs - 1:
				var tip_pt := Vector3(0.0, 0.5 * (out_y1 + in_y1), z1)
				var u_tip := Vector2(t1, v_out)
				_emit_streamer_tri(st, hi0, tip_pt, lo0, c, c, c, uhi0, u_tip, ulo0, uhi0, u_tip, ulo0, 1)
			else:
				_emit_streamer_tri(st, hi0, hi1, lo1, c, c, c, uhi0, uhi1, ulo1, uhi0, uhi1, ulo1, 1)
				_emit_streamer_tri(st, hi0, lo1, lo0, c, c, c, uhi0, ulo1, ulo0, uhi0, ulo1, ulo0, 1)

	st.generate_normals()
	return st.commit()


static func _emit_streamer_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color, uva: Vector2, uvb: Vector2, uvc: Vector2,
		uv2a: Vector2, uv2b: Vector2, uv2c: Vector2, smooth_grp: int) -> void:
	if (c - a).cross(b - a).length_squared() < 1e-12:
		return
	st.set_smooth_group(smooth_grp)
	st.set_color(ca)
	st.set_uv(uva)
	st.set_uv2(uv2a)
	st.add_vertex(a)

	st.set_smooth_group(smooth_grp)
	st.set_color(cb)
	st.set_uv(uvb)
	st.set_uv2(uv2b)
	st.add_vertex(b)

	st.set_smooth_group(smooth_grp)
	st.set_color(cc)
	st.set_uv(uvc)
	st.set_uv2(uv2c)
	st.add_vertex(c)


func _setup_ship_bell() -> void:
	if faction != &"player":
		return
	_ensure_ship_bell_assets()

	var root := Node3D.new()
	root.name = "ShipBell"
	root.position = (Vector3(0.0, 3.08, 3.98) if ship_class == &"brigantine" else Vector3(0.0, 2.86, 2.98)) * hull_scale
	root.scale = Vector3.ONE * hull_scale
	add_child(root)
	ship_bell_node = root

	_bell_frame_mi = MeshInstance3D.new()
	_bell_frame_mi.name = "ShipBellFrame"
	_bell_frame_mi.mesh = _bell_frame_mesh
	_bell_frame_mi.material_override = _bell_iron_mat
	root.add_child(_bell_frame_mi)

	_bell_cup_pivot = Node3D.new()
	_bell_cup_pivot.name = "ShipBellPivot"
	_bell_cup_pivot.position = Vector3(0.0, 0.36, 0.0)
	root.add_child(_bell_cup_pivot)

	_bell_cup_mi = MeshInstance3D.new()
	_bell_cup_mi.name = "ShipBellCup"
	_bell_cup_mi.mesh = _bell_cup_mesh
	_bell_cup_mi.material_override = _bell_bronze_mat
	_bell_cup_pivot.add_child(_bell_cup_mi)

	ship_bell_interactable = Interactable.create("Ring ship's bell", 0.55)
	ship_bell_interactable.name = "ShipBellInteractable"
	ship_bell_interactable.reach = 1.65
	ship_bell_interactable.position = Vector3(0.0, 0.22, 0.0)
	ship_bell_interactable.interacted.connect(func(p: Node) -> void:
		ring_bell(p)
	)
	root.add_child(ship_bell_interactable)


func _setup_ship_nameplate() -> void:
	if faction != &"player" or not ResourceLoader.exists(SHIP_NAMEPLATE_PATH):
		return
	var np_gd := load(SHIP_NAMEPLATE_PATH) as GDScript
	if np_gd != null and np_gd.has_method(&"mount_to_ship"):
		ship_nameplate = np_gd.call(&"mount_to_ship", self, ship_name) as Node3D


func _setup_hull_crest() -> void:
	if not ResourceLoader.exists(HULL_CREST_PATH):
		return
	var crest_gd := load(HULL_CREST_PATH) as GDScript
	if crest_gd != null and crest_gd.has_method(&"mount_to_ship"):
		hull_crest = crest_gd.call(&"mount_to_ship", self) as Node3D
		if hull_crest != null and hull_crest.has_method(&"apply_emblem"):
			hull_crest.call(&"apply_emblem", get_emblem_mode(), _effective_glow_accent)


## Update the ship's display name and live gilded transom nameplate (if mounted).
func set_ship_name(new_name: String) -> void:
	var cleaned := new_name.strip_edges()
	if cleaned == "":
		return
	ship_name = cleaned
	if ship_nameplate != null and is_instance_valid(ship_nameplate) and ship_nameplate.has_method(&"set_ship_name"):
		ship_nameplate.call(&"set_ship_name", ship_name)


static func _ensure_ship_bell_assets() -> void:
	if _bell_iron_mat == null:
		_bell_iron_mat = StandardMaterial3D.new()
		_bell_iron_mat.vertex_color_use_as_albedo = true
		_bell_iron_mat.vertex_color_is_srgb = true
		_bell_iron_mat.roughness = 0.44
		_bell_iron_mat.metallic = 0.78
	if _bell_bronze_mat == null:
		_bell_bronze_mat = StandardMaterial3D.new()
		_bell_bronze_mat.vertex_color_use_as_albedo = true
		_bell_bronze_mat.vertex_color_is_srgb = true
		_bell_bronze_mat.roughness = 0.24
		_bell_bronze_mat.metallic = 0.86
	if _bell_frame_mesh == null:
		_bell_frame_mesh = _build_ship_bell_frame_mesh()
	if _bell_cup_mesh == null:
		_bell_cup_mesh = _build_ship_bell_cup_mesh()


static func _build_ship_bell_frame_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var col_hi := Color(0.24, 0.24, 0.27)
	var col_mid := Color(0.14, 0.14, 0.17)
	var col_lo := Color(0.08, 0.08, 0.10)
	var col_brass := Color(0.86, 0.66, 0.22)

	# Heavy riveted iron rail-mounting flange flush at y = 0.0.
	_bell_add_box(st, Vector3(0.0, 0.018, 0.0), Vector3(0.30, 0.036, 0.13), 0.006, col_hi, col_mid, col_lo)
	for sx: float in [-0.115, 0.115]:
		_bell_add_box(st, Vector3(sx, 0.040, 0.0), Vector3(0.038, 0.016, 0.044), 0.004, col_brass, col_brass, col_lo)

	# Sculpted arched forged-iron belfry yoke curving smoothly over the bell crown.
	var arch_pts: Array[Vector3] = []
	var arch_segs := 10
	for i in arch_segs + 1:
		var u := float(i) / float(arch_segs)
		var ang := lerpf(PI, 0.0, u)
		var ax := cos(ang) * 0.132
		var ay := 0.29 + sin(ang) * 0.145
		arch_pts.append(Vector3(ax, ay, 0.0))
	for sgn: float in [-1.0, 1.0]:
		_bell_add_tube(st, Vector3(sgn * 0.132, 0.034, 0.0), Vector3(sgn * 0.132, 0.295, 0.0), 0.017, 0.016, 8, col_hi, col_lo)
		_bell_add_box(st, Vector3(sgn * 0.132, 0.356, 0.0), Vector3(0.042, 0.038, 0.042), 0.005, col_hi, col_mid, col_lo)
	for i in arch_segs:
		_bell_add_tube(st, arch_pts[i], arch_pts[i + 1], 0.016, 0.016, 8, col_hi, col_mid)

	# Horizontal trunnion axle rod supporting the hanging bell pivot at y = 0.36.
	_bell_add_tube(st, Vector3(-0.145, 0.36, 0.0), Vector3(0.145, 0.36, 0.0), 0.011, 0.011, 8, col_brass, col_mid)
	# Crown finial spike atop the arch.
	_bell_add_lathe(st, [
		Vector2(0.0, 0.43),
		Vector2(0.028, 0.43),
		Vector2(0.022, 0.455),
		Vector2(0.010, 0.49),
		Vector2(0.0, 0.515),
	], 8, col_brass, col_hi)

	st.generate_normals()
	return st.commit()


static func _build_ship_bell_cup_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var col_hi := Color(0.96, 0.78, 0.32)
	var col_mid := Color(0.78, 0.57, 0.18)
	var col_lo := Color(0.46, 0.32, 0.10)
	var col_iron := Color(0.16, 0.16, 0.19)
	var col_rope := Color(0.74, 0.60, 0.38)

	# Lathed flared burnished-bronze maritime bell cup hanging from pivot y = 0.0 down to y = -0.26.
	_bell_add_lathe(st, [
		Vector2(0.0, 0.012),
		Vector2(0.024, 0.012),
		Vector2(0.030, -0.018),
		Vector2(0.048, -0.034),
		Vector2(0.062, -0.064),
		Vector2(0.072, -0.072),
		Vector2(0.066, -0.080),
		Vector2(0.076, -0.145),
		Vector2(0.092, -0.180),
		Vector2(0.098, -0.188),
		Vector2(0.094, -0.196),
		Vector2(0.118, -0.238),
		Vector2(0.126, -0.256),
		Vector2(0.114, -0.262),
		Vector2(0.096, -0.252),
		Vector2(0.068, -0.185),
		Vector2(0.046, -0.080),
		Vector2(0.0, -0.055),
	], 14, col_hi, col_lo)

	# Hanging forged-iron clapper stem & strike ball inside the sound bow.
	_bell_add_tube(st, Vector3(0.0, -0.055, 0.0), Vector3(0.0, -0.245, 0.0), 0.008, 0.009, 6, col_iron, col_iron)
	_bell_add_lathe(st, [
		Vector2(0.0, -0.215),
		Vector2(0.022, -0.228),
		Vector2(0.026, -0.248),
		Vector2(0.018, -0.266),
		Vector2(0.0, -0.272),
	], 8, col_mid, col_iron)

	# Braided hemp bell-pull lanyard & monkey's-fist pull knot hanging below the clapper.
	_bell_add_tube(st, Vector3(0.0, -0.268, 0.0), Vector3(0.0, -0.395, 0.0), 0.009, 0.008, 6, col_rope, col_lo)
	_bell_add_lathe(st, [
		Vector2(0.0, -0.382),
		Vector2(0.020, -0.394),
		Vector2(0.022, -0.410),
		Vector2(0.014, -0.424),
		Vector2(0.0, -0.428),
	], 8, col_rope, col_lo)

	st.generate_normals()
	return st.commit()


static func _bell_add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-10:
		return
	n = n.normalized()
	st.set_normal(n)
	st.set_color(col)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(col)
	st.add_vertex(b)
	st.set_normal(n)
	st.set_color(col)
	st.add_vertex(c)


static func _bell_add_lathe(
	st: SurfaceTool,
	profile: Array[Vector2],
	segs: int,
	col_top: Color,
	col_bot: Color
) -> void:
	for pi in range(profile.size() - 1):
		var r0 := profile[pi].x
		var y0 := profile[pi].y
		var r1 := profile[pi + 1].x
		var y1 := profile[pi + 1].y
		var t := float(pi) / maxf(float(profile.size() - 2), 1.0)
		var col := col_top.lerp(col_bot, t)
		var going_up := y1 >= y0
		for s in segs:
			var a0 := float(s) / float(segs) * TAU
			var a1 := float(s + 1) / float(segs) * TAU
			var p00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p10 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p01 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			if going_up:
				if r0 > 0.0004:
					_bell_add_tri(st, p00, p10, p01, col)
				if r1 > 0.0004:
					_bell_add_tri(st, p10, p11, p01, col)
			else:
				if r0 > 0.0004:
					_bell_add_tri(st, p00, p01, p10, col)
				if r1 > 0.0004:
					_bell_add_tri(st, p10, p01, p11, col)


static func _bell_add_tube(
	st: SurfaceTool,
	p0: Vector3,
	p1: Vector3,
	r0: float,
	r1: float,
	segs: int,
	col0: Color,
	col1: Color
) -> void:
	var axis := p1 - p0
	if axis.length_squared() < 1e-8:
		return
	var dir := axis.normalized()
	var up_ref := Vector3.UP if absf(dir.y) < 0.92 else Vector3.RIGHT
	var side_x := dir.cross(up_ref).normalized()
	var side_z := side_x.cross(dir).normalized()
	var col := col0.lerp(col1, 0.5)
	for s in segs:
		var a0 := float(s) / float(segs) * TAU
		var a1 := float(s + 1) / float(segs) * TAU
		var d0 := side_x * cos(a0) + side_z * sin(a0)
		var d1 := side_x * cos(a1) + side_z * sin(a1)
		var v00 := p0 + d0 * r0
		var v10 := p0 + d1 * r0
		var v01 := p1 + d0 * r1
		var v11 := p1 + d1 * r1
		_bell_add_tri(st, v00, v10, v01, col)
		_bell_add_tri(st, v10, v11, v01, col)


static func _bell_add_box(
	st: SurfaceTool,
	center: Vector3,
	dims: Vector3,
	bevel: float,
	col_top: Color,
	col_side: Color,
	col_bot: Color
) -> void:
	var hx := dims.x * 0.5
	var hy := dims.y * 0.5
	var hz := dims.z * 0.5
	var bx := maxf(0.001, hx - bevel)
	var bz := maxf(0.001, hz - bevel)
	var ty := center.y + hy
	var by := center.y - hy
	var t0 := Vector3(center.x - bx, ty, center.z - bz)
	var t1 := Vector3(center.x + bx, ty, center.z - bz)
	var t2 := Vector3(center.x + bx, ty, center.z + bz)
	var t3 := Vector3(center.x - bx, ty, center.z + bz)
	var b0 := Vector3(center.x - hx, by, center.z - hz)
	var b1 := Vector3(center.x + hx, by, center.z - hz)
	var b2 := Vector3(center.x + hx, by, center.z + hz)
	var b3 := Vector3(center.x - hx, by, center.z + hz)
	_bell_add_tri(st, t0, t1, t2, col_top)
	_bell_add_tri(st, t0, t2, t3, col_top)
	_bell_add_tri(st, b0, b2, b1, col_bot)
	_bell_add_tri(st, b0, b3, b2, col_bot)
	var quads: Array[Array] = [
		[b0, b1, t1, t0],
		[b1, b2, t2, t1],
		[b2, b3, t3, t2],
		[b3, b0, t0, t3],
	]
	for q in quads:
		_bell_add_tri(st, q[0] as Vector3, q[1] as Vector3, q[2] as Vector3, col_side)
		_bell_add_tri(st, q[0] as Vector3, q[2] as Vector3, q[3] as Vector3, col_side)


func _setup_cabin_furnishings() -> void:
	if faction != &"player":
		return
	var furn := CaptainCabinFurnishings.new()
	furn.name = "CaptainCabinFurnishings"
	furn.ship_class = ship_class
	furn.scale = Vector3.ONE * hull_scale
	add_child(furn)
	cabin_furnishings = furn
	sync_cabin_renown(Game.profile if Game != null else null, false)


## Sync the Captain's Cabin Trading Company Renown Trophy Stand medallions from `profile`.
func sync_cabin_renown(profile: Profile = null, force_all: bool = false) -> void:
	if cabin_furnishings == null or not is_instance_valid(cabin_furnishings):
		return
	var prof: Profile = profile if profile != null else (Game.profile if Game != null else null)
	cabin_furnishings.sync_renown(prof, force_all)


func _setup_wind_ribbons() -> void:
	if faction != &"player":
		return
	var wr := WindRibbons.new()
	wr.name = "WindRibbons"
	add_child(wr)
	wind_ribbons = wr


func _setup_lookout_glint() -> void:
	if faction == &"player":
		return
	if _lookout_glint_mesh == null:
		_lookout_glint_mesh = _build_lookout_glint_quad()
	if _lookout_glint_shader == null:
		_lookout_glint_shader = _build_lookout_glint_shader()

	_lookout_glint_mat = ShaderMaterial.new()
	_lookout_glint_mat.shader = _lookout_glint_shader
	_lookout_glint_mat.set_shader_parameter(&"glint_intensity", 0.0)
	_lookout_glint_mat.set_shader_parameter(&"glint_scale", 2.8)

	_lookout_glint = MeshInstance3D.new()
	_lookout_glint.name = "LookoutGlint"
	_lookout_glint.mesh = _lookout_glint_mesh
	_lookout_glint.material_override = _lookout_glint_mat
	_lookout_glint.position = (Vector3(0.0, 12.2, 0.4) if ship_class == &"brigantine" else Vector3(0.0, 9.6, -0.35)) * hull_scale
	_lookout_glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lookout_glint.visible = false
	add_child(_lookout_glint)
	_lookout_glint_phase = fmod(float(get_instance_id() % 97) * 0.37, TAU)


static func _build_lookout_glint_quad() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p0 := Vector3(-0.5, -0.5, 0.0)
	var p1 := Vector3(0.5, -0.5, 0.0)
	var p2 := Vector3(0.5, 0.5, 0.0)
	var p3 := Vector3(-0.5, 0.5, 0.0)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(p0)
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(p1)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(p2)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(p0)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(p2)
	st.set_uv(Vector2(0.0, 1.0))
	st.add_vertex(p3)
	st.generate_normals()
	return st.commit()


static func _build_lookout_glint_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float glint_intensity = 0.0;
uniform float glint_scale = 2.8;
uniform vec3 glint_color : source_color = vec3(1.0, 0.94, 0.76);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(INV_VIEW_MATRIX[0].xyz * glint_scale, 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz * glint_scale, 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz * glint_scale, 0.0),
		MODEL_MATRIX[3]
	);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float core = exp(-r * r * 28.0);
	float ray_h = exp(-abs(q.y) * 18.0) * smoothstep(1.0, 0.04, abs(q.x));
	float ray_v = exp(-abs(q.x) * 22.0) * smoothstep(0.85, 0.04, abs(q.y));
	vec2 dq = vec2(q.x + q.y, q.y - q.x) * 0.70710678;
	float ray_d = (exp(-abs(dq.y) * 24.0) + exp(-abs(dq.x) * 24.0)) * 0.35 * smoothstep(0.70, 0.05, r);
	float edge_fade = smoothstep(1.0, 0.72, r);
	float star = clamp((core * 1.45 + ray_h * 0.85 + ray_v * 0.65 + ray_d) * edge_fade, 0.0, 2.0);
	vec3 col = mix(glint_color, vec3(1.0, 0.99, 0.95), clamp(core, 0.0, 1.0));
	ALBEDO = col * (star * glint_intensity);
}
"""
	return sh


func _setup_lights_and_glass() -> void:
	_window_mats.clear()
	_lantern_lights.clear()
	if _model == null:
		return

	# Duplicate window glass materials so night glow never mutates shared glTF resources.
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var touched := false
		for si in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(si) as BaseMaterial3D
			if mat != null and mat.resource_name == "mat_window_glass":
				if not touched:
					mi.mesh = mi.mesh.duplicate() as Mesh
					touched = true
				var dup := mat.duplicate() as BaseMaterial3D
				dup.emission_enabled = true
				dup.emission = Color(1.0, 0.72, 0.34)
				mi.mesh.surface_set_material(si, dup)
				_window_mats.append(dup)

	if not enable_effects:
		return

	for child in _model.get_children():
		var nm := String(child.name)
		if not nm.begins_with("Lantern_"):
			continue
		var l := OmniLight3D.new()
		l.name = "Glow"
		l.light_color = Color(1.0, 0.74, 0.42)
		var is_hold := nm.contains("Hold")
		l.light_energy = 1.45 if is_hold else 0.75
		l.omni_range = (7.5 if is_hold else 6.0) * hull_scale
		l.omni_attenuation = 1.4
		l.shadow_enabled = false
		child.add_child(l)
		_lantern_lights.append(l)


func _cache_ropes() -> void:
	_rope_pairs.clear()
	var specs := [
		["Rope_Sheet_Port", "SheetPoint_Port", "Sail/Clew_Port"],
		["Rope_Sheet_Starboard", "SheetPoint_Starboard", "Sail/Clew_Starboard"],
		["Rope_Brace_Port", "BracePoint_Port", "Yard/Yardarm_Port"],
		["Rope_Brace_Starboard", "BracePoint_Starboard", "Yard/Yardarm_Starboard"],
		["Rope_Sheet_Fore_Port", "SheetPoint_Fore_Port", "Sail_Fore/Clew_Fore_Port"],
		["Rope_Sheet_Fore_Starboard", "SheetPoint_Fore_Starboard", "Sail_Fore/Clew_Fore_Starboard"],
		["Rope_Brace_Fore_Port", "BracePoint_Fore_Port", "Yard_Fore/Yardarm_Fore_Port"],
		["Rope_Brace_Fore_Starboard", "BracePoint_Fore_Starboard", "Yard_Fore/Yardarm_Fore_Starboard"],
	]
	for spec in specs:
		var r := _n(spec[0])
		var a := _n(spec[1])
		var b := _n(spec[2])
		if r != null and a != null and b != null:
			_rope_pairs.append([r, a, b])


func _register_ocean_mask() -> void:
	if _mask_registered:
		return
	if Ocean.current != null and Ocean.current.has_method(&"register_hull_mask"):
		Ocean.current.call(&"register_hull_mask", self, _mask_water, water_level)
		_mask_registered = true


func _unregister_ocean_mask() -> void:
	if not _mask_registered:
		return
	if Ocean.current != null and Ocean.current.has_method(&"unregister_hull_mask"):
		Ocean.current.call(&"unregister_hull_mask", self)
	_mask_registered = false


func _n(path: String) -> Node3D:
	return _model.get_node_or_null(path) as Node3D if _model != null else null


func _local_to_ship(node: Node3D) -> Transform3D:
	var xf := node.transform
	var p := node.get_parent()
	while p != null and p != self and p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


# ------------------------------------------------------------------ public API

## Host only. Set target wheel position in -1..1 (positive turns starboard).
func set_helm_target(v: float) -> void:
	if not Net.is_host():
		return
	helm_target = clampf(v, -1.0, 1.0)


## Host only. Set target sail extension in 0..1.
func set_sail_target(v: float) -> void:
	if not Net.is_host():
		return
	sail_target = clampf(v, 0.0, 1.0)


## Host only. Set target yard trim angle in radians (-1.2..1.2).
func set_trim_target(v: float) -> void:
	if not Net.is_host():
		return
	trim_target = clampf(v, -MAX_TRIM_RAD, MAX_TRIM_RAD)


## Host only. Drop or raise the anchor.
func set_anchor(down: bool) -> void:
	if not Net.is_host():
		return
	var was_manual := _manual_capstan_heave
	_manual_capstan_heave = false
	_capstan_heaving_this_tick = false
	_capstan_assist_hands = 0
	if anchor_down == down:
		if down and was_manual and anchor_progress < 0.90:
			Audio.play_sfx(&"anchor_drop", _anchor_world_pos())
		return
	anchor_down = down
	if down:
		Audio.play_sfx(&"anchor_drop", _anchor_world_pos())
	else:
		_anchor_swing_timer = 0.0
		_anchor_swing_dir = 0.0


## Forward speed along the ship's -Z bow axis in m/s (negative = astern).
func forward_speed() -> float:
	var fwd := -global_basis.z
	return linear_velocity.dot(fwd)


## Horizontal speed in knots (1 m/s ~= 1.94384 knots).
func speed_knots() -> float:
	var hv := Vector2(linear_velocity.x, linear_velocity.z).length()
	return hv * 1.94384


## Horizontal apparent wind experienced by the ship in world space (m/s).
## Blends true wind with a light velocity shift so fast downwind vessels keep full sail billow.
func apparent_wind() -> Vector3:
	var w := Weather.wind_vector()
	return Vector3(w.x - linear_velocity.x * 0.25, 0.0, w.z - linear_velocity.z * 0.25)


## 0..1 measure of how cleanly the mainsail catches the current apparent wind.
func wind_catch() -> float:
	var aw := apparent_wind()
	if aw.length_squared() < 0.04:
		return 0.0
	var aw_local := global_basis.inverse() * aw
	var w2 := Vector2(aw_local.x, aw_local.z)
	if w2.length_squared() < 0.001:
		return 0.0
	w2 = w2.normalized()
	# Yard normal when rotated by sail_trim around +Y: push direction is (-sin(trim), -cos(trim)).
	var push := Vector2(-sin(sail_trim), -cos(sail_trim))
	var align := w2.dot(push)
	var base := clampf(align, 0.0, 1.0)
	return pow(base, 2.2)


## Optimal sail_trim (radians) for the current apparent wind.
func ideal_sail_trim() -> float:
	var aw := apparent_wind()
	if aw.length_squared() < 0.04:
		return 0.0
	var aw_local := global_basis.inverse() * aw
	# Push direction (-sin(trim), -cos(trim)) matches (aw_local.x, aw_local.z).
	var desired := atan2(-aw_local.x, -aw_local.z)
	return clampf(desired, -MAX_TRIM_RAD, MAX_TRIM_RAD)


## First station of a given kind (&"helm", &"sail_length", &"sail_angle", &"anchor",
## &"cannon", &"map_table", &"bilge"), or null.
func get_station(kind: StringName, meta_id: StringName = &"") -> Station:
	var list: Array = _stations_by_kind.get(kind, [])
	for st: Station in list:
		if meta_id == &"" or st.meta_id == meta_id:
			return st
	return null


## All stations of a given kind.
func get_stations(kind: StringName) -> Array[Station]:
	var out: Array[Station] = []
	for st: Station in _stations_by_kind.get(kind, []):
		out.append(st)
	return out


## All currently open (breached and unpatched) hole records.
func get_open_holes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for h in holes:
		if bool(h["breached"]) and not bool(h["patched"]):
			out.append(h)
	return out


## Number of open hull breaches right now.
func open_hole_count() -> int:
	var n := 0
	for h in holes:
		if bool(h["breached"]) and not bool(h["patched"]):
			n += 1
	return n


## Refill ship ammo and repair planks (quartermaster auto-stock or supply barrel).
func restock_supplies() -> void:
	if not Net.is_host():
		return
	cannonballs_remaining = MAX_CANNONBALLS
	planks_remaining = MAX_PLANKS


## Apply sidegrade multipliers from Economy.get_ship_modifiers(profile).
func apply_modifiers(mods: Dictionary) -> void:
	speed_modifier = float(mods.get("speed_scale", 1.0))
	close_hauled_modifier = float(mods.get("close_hauled_scale", 1.0))
	breach_resist_modifier = float(mods.get("breach_resist", 1.0))
	reload_modifier = float(mods.get("reload_scale", 1.0))
	cannon_radius_modifier = float(mods.get("cannon_radius_scale", 1.0))


## Customize sail/flag/hull colours, optional spectral glow, and procedural heraldic sail emblem mode.
## Pass `sail_emblem_mode = -1` to preserve faction defaults (0=standard, 1=corsair, 2=drowned, 3=ghost),
## or 4..7 for Trading Company crests (4=Gilded Compass, 5=Sunken Archive, 6=Iron Tide, 7=Sovereign Sunburst).
func apply_livery(
		sail_tint: Color,
		flag_tint: Color,
		glow_accent: Color = Color.BLACK,
		hull_tint: Color = Color.WHITE,
		sail_emblem_mode: int = -1
) -> void:
	_livery_sail_tint = sail_tint
	_livery_flag_tint = flag_tint
	_livery_glow_accent = glow_accent
	_livery_hull_tint = hull_tint
	_livery_emblem_mode = sail_emblem_mode
	if is_node_ready():
		_apply_current_livery()


## Return the active procedural `emblem_mode` integer driving sails & emissary streamer.
func get_emblem_mode() -> int:
	if _livery_emblem_mode >= 0:
		return _livery_emblem_mode
	if faction == &"ghost":
		return 3
	if faction == &"drowned":
		return 2
	if faction == &"corsair":
		return 1
	return 0


## Drive spectral visibility, ectoplasmic dissolve, and phase flare on Ghost Ships.
func set_spectral_phase(alpha: float, flare: float = 0.0) -> void:
	_spectral_phase = clampf(alpha, 0.0, 1.0)
	_spectral_flare = clampf(flare, 0.0, 2.0)
	for gm in _ghost_hull_mats:
		gm.set_shader_parameter(&"phase_alpha", _spectral_phase)
		gm.set_shader_parameter(&"phase_flare", _spectral_flare)
	for sm in _sail_mats:
		sm.set_shader_parameter(&"phase_alpha", _spectral_phase)
		sm.set_shader_parameter(&"phase_flare", _spectral_flare)
	for fmat in _flag_mats:
		fmat.set_shader_parameter(&"phase_alpha", _spectral_phase)
		fmat.set_shader_parameter(&"phase_flare", _spectral_flare)
	for l in _lantern_lights:
		if is_instance_valid(l):
			l.visible = _spectral_phase > 0.02
	if hull_crest != null and is_instance_valid(hull_crest) and hull_crest.has_method(&"set_spectral_alpha"):
		hull_crest.call(&"set_spectral_alpha", _spectral_phase)
	visible = _spectral_phase > 0.02


func _apply_current_livery() -> void:
	var is_ghost := faction == &"ghost"
	var eff_glow := _livery_glow_accent
	var eff_hull := _livery_hull_tint
	var eff_paint := _livery_hull_tint.lerp(Color.WHITE, 0.15)
	var eff_rough_add := 0.06 if _livery_hull_tint != Color.WHITE and _livery_hull_tint.get_luminance() < 0.5 else 0.0
	var eff_hull_emit := Color.BLACK
	var eff_hull_emit_energy := 0.0

	if _livery_hull_tint == Color.WHITE:
		if faction == &"drowned":
			# Charred barnacle-slate / waterlogged oak hull + tarnished verdigris carvings + eerie sea-green glow.
			eff_hull = Color(0.42, 0.48, 0.49)
			eff_paint = Color(0.38, 0.50, 0.48)
			eff_rough_add = 0.14
			if eff_glow.get_luminance() <= 0.01:
				eff_glow = Color(0.14, 0.92, 0.52)
		elif is_ghost:
			eff_hull = Color(0.06, 0.22, 0.26)
			eff_paint = Color(0.08, 0.28, 0.30)
			eff_rough_add = 0.04
			if eff_glow.get_luminance() <= 0.01:
				eff_glow = Color(0.24, 1.0, 0.90)
		elif faction == &"corsair":
			eff_hull = Color(0.58, 0.46, 0.44)
			eff_paint = Color(0.64, 0.42, 0.38)
			eff_rough_add = 0.08
		else:
			eff_paint = Color.WHITE

	_effective_glow_accent = eff_glow
	var emblem_mode := get_emblem_mode()
	var glow_mag := eff_glow.get_luminance()
	var sail_glow_strength := 0.0
	if glow_mag > 0.01 and emblem_mode < 4:
		# Ghost sails drive their own Fresnel + drifting wisp emission in sail_wind.gdshader;
		# Trading Company sails (emblem_mode >= 4) glow strictly on their crests/hems so dark
		# obsidian & crimson fields never wash out.
		if is_ghost:
			sail_glow_strength = 0.04
		elif faction == &"drowned":
			sail_glow_strength = 0.015
		else:
			sail_glow_strength = clampf(glow_mag * 0.78, 0.14, 0.82)

	for sm in _sail_mats:
		sm.set_shader_parameter(&"albedo_tint", _livery_sail_tint)
		sm.set_shader_parameter(&"emblem_mode", emblem_mode)
		sm.set_shader_parameter(&"phase_alpha", _spectral_phase)
		sm.set_shader_parameter(&"phase_flare", _spectral_flare)
		if glow_mag > 0.01 and emblem_mode < 4:
			sm.set_shader_parameter(&"emission_tint", eff_glow)
			sm.set_shader_parameter(&"emission_strength", sail_glow_strength)
		elif glow_mag > 0.01 and emblem_mode == 5:
			# Pass archive accent tint for crest/hem emission while shader masks flat sail glow to 0.
			sm.set_shader_parameter(&"emission_tint", eff_glow)
			sm.set_shader_parameter(&"emission_strength", 0.25)
		else:
			var is_back := float(sm.get_shader_parameter(&"is_back_face")) > 0.5
			sm.set_shader_parameter(&"emission_tint", Color(1.0, 0.86, 0.6))
			sm.set_shader_parameter(&"emission_strength", 0.08 if is_back else 0.0)
	for fmat in _flag_mats:
		fmat.set_shader_parameter(&"albedo_tint", _livery_flag_tint)
		fmat.set_shader_parameter(&"emblem_mode", emblem_mode)
		fmat.set_shader_parameter(&"phase_alpha", _spectral_phase)
		fmat.set_shader_parameter(&"phase_flare", _spectral_flare)
		if glow_mag > 0.01 and emblem_mode < 4:
			fmat.set_shader_parameter(&"emission_tint", eff_glow)
			fmat.set_shader_parameter(&"emission_strength", sail_glow_strength)
		else:
			fmat.set_shader_parameter(&"emission_strength", 0.0)

	var lantern_col := eff_glow.lerp(Color.WHITE, 0.28) if glow_mag > 0.01 else Color(1.0, 0.74, 0.42)
	for l in _lantern_lights:
		l.light_color = lantern_col
	for wm in _window_mats:
		if glow_mag > 0.01:
			wm.emission = eff_glow
			wm.albedo_color = Color(eff_glow.r * 0.65, eff_glow.g * 0.88, eff_glow.b * 0.72, 0.58)
		else:
			wm.emission = Color(1.0, 0.72, 0.34)
			wm.albedo_color = Color(1.0, 1.0, 1.0, 0.30)

	if hull_crest != null and is_instance_valid(hull_crest) and hull_crest.has_method(&"apply_emblem"):
		hull_crest.call(&"apply_emblem", emblem_mode, eff_glow)

	var need_hull_livery := (
		is_ghost
		or eff_hull != Color.WHITE
		or glow_mag > 0.01
		or _livery_sail_tint != Color.WHITE
		or _livery_flag_tint != Color.WHITE
		or _hull_mats_duplicated
	)
	if not need_hull_livery:
		return

	_ensure_hull_livery_mats()
	_ghost_hull_mats.clear()

	if is_ghost:
		for entry in _hull_mat_entries:
			var kind: StringName = entry["kind"]
			var gm := entry["ghost_mat"] as ShaderMaterial
			if gm == null:
				gm = ShaderMaterial.new()
				gm.shader = GHOST_HULL_SHADER
				# Draw cleanly after the ocean screen-reading pass (priority 0) so waves show through phantom planks.
				gm.render_priority = 1
				var orig_tex := entry["orig_tex"] as Texture2D
				if orig_tex != null:
					gm.set_shader_parameter(&"albedo_tex", orig_tex)
					gm.set_shader_parameter(&"use_albedo_tex", 1.0)
				else:
					gm.set_shader_parameter(&"use_albedo_tex", 0.0)
				entry["ghost_mat"] = gm
			var base_col := Color(0.06, 0.22, 0.26)
			var rim_col := Color(0.24, 1.0, 0.90)
			match kind:
				&"paint", &"brass":
					base_col = Color(0.08, 0.28, 0.30)
					rim_col = Color(0.32, 1.0, 0.92)
				&"iron":
					base_col = Color(0.04, 0.16, 0.21)
					rim_col = Color(0.20, 0.95, 0.88)
				&"lantern", &"window", &"lod_window":
					base_col = Color(0.22, 0.96, 0.88)
					rim_col = Color(0.68, 1.0, 0.96)
				&"lod_canvas", &"lod_flag":
					base_col = Color(0.06, 0.24, 0.28)
					rim_col = Color(0.26, 1.0, 0.92)
			gm.set_shader_parameter(&"base_color", base_col)
			gm.set_shader_parameter(&"rim_color", rim_col)
			gm.set_shader_parameter(&"phase_alpha", _spectral_phase)
			gm.set_shader_parameter(&"phase_flare", _spectral_flare)
			gm.set_shader_parameter(&"wisp_time", _wisp_time)
			for target_pair: Array in entry["targets"]:
				var target_mi := target_pair[0] as MeshInstance3D
				var target_si := int(target_pair[1])
				if target_mi != null and is_instance_valid(target_mi):
					target_mi.set_surface_override_material(target_si, gm)
			_ghost_hull_mats.append(gm)
		return

	for entry in _hull_mat_entries:
		var mat: BaseMaterial3D = entry["mat"]
		var kind: StringName = entry["kind"]
		var orig_albedo: Color = entry["orig_albedo"]
		var orig_rough: float = float(entry["orig_rough"])
		for target_pair: Array in entry["targets"]:
			var target_mi := target_pair[0] as MeshInstance3D
			var target_si := int(target_pair[1])
			if target_mi != null and is_instance_valid(target_mi):
				target_mi.set_surface_override_material(target_si, mat)
		match kind:
			&"wood":
				mat.albedo_color = orig_albedo * eff_hull
				mat.roughness = clampf(orig_rough + eff_rough_add, 0.0, 0.98)
				if eff_hull_emit_energy > 0.01:
					mat.emission_enabled = true
					mat.emission = eff_hull_emit
					mat.emission_energy_multiplier = eff_hull_emit_energy
				else:
					mat.emission_enabled = bool(entry["orig_emit_on"])
					mat.emission = entry["orig_emit"] as Color
					mat.emission_energy_multiplier = float(entry["orig_emit_e"])
			&"paint":
				mat.albedo_color = orig_albedo * eff_paint
				mat.roughness = clampf(orig_rough + eff_rough_add * 1.35, 0.0, 0.96)
				if eff_hull_emit_energy > 0.01:
					mat.emission_enabled = true
					mat.emission = eff_hull_emit
					mat.emission_energy_multiplier = eff_hull_emit_energy
				else:
					mat.emission_enabled = bool(entry["orig_emit_on"])
					mat.emission = entry["orig_emit"] as Color
					mat.emission_energy_multiplier = float(entry["orig_emit_e"])
			&"iron":
				mat.albedo_color = orig_albedo * eff_hull.lerp(Color.WHITE, 0.55)
				mat.roughness = clampf(orig_rough + eff_rough_add * 1.2, 0.0, 0.95)
			&"cloth", &"furled_canvas":
				mat.albedo_color = orig_albedo * (_livery_sail_tint if kind == &"furled_canvas" else eff_hull.lerp(Color.WHITE, 0.10))
			&"rope":
				mat.albedo_color = orig_albedo * eff_hull.lerp(Color.WHITE, 0.35)
			&"brass":
				mat.albedo_color = orig_albedo * eff_paint.lerp(Color.WHITE, 0.22)
				mat.roughness = clampf(orig_rough + eff_rough_add * 1.6, 0.0, 0.95)
			&"lantern":
				if glow_mag > 0.01:
					mat.albedo_color = eff_glow.lerp(Color.WHITE, 0.22)
					mat.emission_enabled = true
					mat.emission = eff_glow
					mat.emission_energy_multiplier = 2.8
				else:
					mat.albedo_color = orig_albedo
					mat.emission_enabled = bool(entry["orig_emit_on"])
					mat.emission = entry["orig_emit"] as Color
					mat.emission_energy_multiplier = float(entry["orig_emit_e"])
			&"window":
				if glow_mag > 0.01:
					mat.albedo_color = Color(eff_glow.r * 0.65, eff_glow.g * 0.88, eff_glow.b * 0.72, 0.58)
					mat.emission_enabled = true
					mat.emission = eff_glow
				else:
					mat.albedo_color = Color(1.0, 1.0, 1.0, 0.30)
					mat.emission = Color(1.0, 0.72, 0.34)
			&"lod_window":
				if glow_mag > 0.01:
					mat.albedo_color = Color(eff_glow.r * 0.65, eff_glow.g * 0.88, eff_glow.b * 0.72, 0.65)
					mat.emission_enabled = true
					mat.emission = eff_glow
					mat.emission_energy_multiplier = 2.0
				else:
					mat.albedo_color = orig_albedo
					mat.emission_enabled = bool(entry["orig_emit_on"])
					mat.emission = entry["orig_emit"] as Color
					mat.emission_energy_multiplier = float(entry["orig_emit_e"])
			&"lod_canvas":
				mat.albedo_color = orig_albedo * _livery_sail_tint
				if glow_mag > 0.01:
					mat.emission_enabled = true
					mat.emission = eff_glow
					mat.emission_energy_multiplier = sail_glow_strength
				else:
					mat.emission_enabled = bool(entry["orig_emit_on"])
					mat.emission = entry["orig_emit"] as Color
					mat.emission_energy_multiplier = float(entry["orig_emit_e"])
			&"lod_flag":
				mat.albedo_color = orig_albedo * _livery_flag_tint
				if glow_mag > 0.01:
					mat.emission_enabled = true
					mat.emission = eff_glow
					mat.emission_energy_multiplier = sail_glow_strength
				else:
					mat.emission_enabled = bool(entry["orig_emit_on"])
					mat.emission = entry["orig_emit"] as Color
					mat.emission_energy_multiplier = float(entry["orig_emit_e"])


func _ensure_hull_livery_mats() -> void:
	if _hull_mats_duplicated:
		return
	_hull_mats_duplicated = true
	_hull_mat_entries.clear()
	var mat_cache: Dictionary = {}  # orig BaseMaterial3D -> entry Dictionary
	var roots: Array[Node3D] = []
	if _model != null:
		roots.append(_model)
	if _lod_model != null:
		roots.append(_lod_model)
	for root in roots:
		var is_lod := root == _lod_model
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var nname := String(mi.name)
			if nname.begins_with("col_") or nname.begins_with("mask_"):
				continue
			for si in mi.mesh.get_surface_count():
				var orig := mi.mesh.surface_get_material(si) as BaseMaterial3D
				if orig == null:
					continue
				var kind := _classify_livery_material(orig.resource_name, is_lod)
				if kind == &"":
					continue
				var entry: Dictionary
				if mat_cache.has(orig):
					entry = mat_cache[orig] as Dictionary
				else:
					# Main-model mat_window_glass was already duplicated per ship in _setup_lights_and_glass().
					var dup := orig if (kind == &"window" and not is_lod) else orig.duplicate() as BaseMaterial3D
					entry = {
						"mat": dup,
						"ghost_mat": null,
						"orig_tex": orig.albedo_texture,
						"kind": kind,
						"orig_albedo": orig.albedo_color,
						"orig_rough": orig.roughness,
						"orig_emit_on": orig.emission_enabled,
						"orig_emit": orig.emission,
						"orig_emit_e": orig.emission_energy_multiplier,
						"targets": [],
					}
					mat_cache[orig] = entry
					_hull_mat_entries.append(entry)
				(entry["targets"] as Array).append([mi, si])
				mi.set_surface_override_material(si, entry["mat"] as Material)


static func _classify_livery_material(mat_name: String, is_lod: bool) -> StringName:
	if mat_name == "mat_wood" or mat_name == "mat_hull_wood":
		return &"wood"
	if mat_name == "mat_paint":
		return &"paint"
	if mat_name == "mat_iron":
		return &"iron"
	if mat_name == "mat_cloth":
		return &"cloth"
	if mat_name == "mat_rope":
		return &"rope"
	if mat_name == "mat_brass":
		return &"brass"
	if mat_name == "mat_lantern_glass":
		return &"lantern"
	if is_lod:
		if mat_name == "mat_window_glass":
			return &"lod_window"
		if mat_name == "mat_canvas_lod" or mat_name == "mat_canvas_back_lod" \
				or mat_name == "mat_canvas" or mat_name == "mat_canvas_back":
			return &"lod_canvas"
		if mat_name == "mat_flag":
			return &"lod_flag"
	else:
		if mat_name == "mat_window_glass":
			return &"window"
		if mat_name == "mat_canvas" or mat_name == "mat_canvas_back":
			return &"furled_canvas"
	return &""


## Ring the ship's bell (pendulum impulse, maritime bronze bell cue & signals).
func ring_bell(by_pawn: Node = null) -> void:
	_bell_vel += 9.5
	var sfx_pos := global_position
	if ship_bell_node != null and is_instance_valid(ship_bell_node) and ship_bell_node.is_inside_tree():
		sfx_pos = ship_bell_node.global_position
	elif _bell != null and is_instance_valid(_bell) and _bell.is_inside_tree():
		sfx_pos = _bell.global_position
	var sfx_id := &"ship_bell" if Audio.has_sound(&"ship_bell") else &"parry_ring"
	Audio.play_sfx(sfx_id, sfx_pos, -1.0 if sfx_id == &"ship_bell" else -4.0, 0.03)
	if Game != null:
		Game.post_notice("Clang! The ship's bell rings across the deck!")
	bell_rung.emit(by_pawn)
	ship_bell_rung.emit(by_pawn)


# ------------------------------------------------------------------ damage & flooding

## Host only. Breach the nearest hull panel to `world_pos`. Returns slot index (0..9) or -1.
func apply_hull_damage(world_pos: Vector3, radius: float = 0.45) -> int:
	if not Net.is_host() or holes.is_empty():
		return -1
	var local_hit := global_transform.affine_inverse() * world_pos
	# Prefer the nearest slot that is not yet open; if all are open, widen the closest one.
	var best_open := -1
	var best_open_d := INF
	var best_any := 0
	var best_any_d := INF
	for h in holes:
		var d := local_hit.distance_to(h["local_pos"] as Vector3)
		var idx: int = h["index"]
		if d < best_any_d:
			best_any_d = d
			best_any = idx
		if not bool(h["breached"]) or bool(h["patched"]):
			if d < best_open_d:
				best_open_d = d
				best_open = idx
	var chosen := best_open if best_open >= 0 else best_any
	var slot: Dictionary = holes[chosen]
	var eff_sev := clampf((radius / 0.45) / maxf(breach_resist_modifier, 0.4), 0.35, 1.8)
	slot["breached"] = true
	slot["patched"] = false
	slot["severity"] = maxf(float(slot["severity"]), eff_sev)
	_sync_hole_visuals(slot)
	var breach_world := global_transform * (slot["local_pos"] as Vector3)
	hull_breached.emit(chosen, breach_world)
	hull_impacted.emit(world_pos, clampf(radius / 0.5, 0.35, 1.0))
	return chosen


## Host only. Patch hull breach `index` (0..9). Returns true if an open hole was patched.
func patch_hole(index: int) -> bool:
	if not Net.is_host() or index < 0 or index >= holes.size():
		return false
	var slot: Dictionary = holes[index]
	if not bool(slot["breached"]) or bool(slot["patched"]):
		return false
	if planks_remaining > 0:
		planks_remaining -= 1
	slot["patched"] = true
	slot["severity"] = 0.0
	_sync_hole_visuals(slot)
	var local_pos: Vector3 = slot["local_pos"] as Vector3
	var pos := global_transform * local_pos
	if enable_effects:
		_spawn_patch_burst(local_pos)
	Audio.play_sfx(&"hammer_plank", pos)
	hole_patched.emit(index)
	return true


## Host only. Bail `amount` (0..1 fraction of hold capacity) of flood water out.
## Returns the amount actually removed.
func bail(amount: float = 0.14) -> float:
	if not Net.is_host() or is_sinking or amount <= 0.0:
		return 0.0
	var before := water_level
	water_level = maxf(0.0, water_level - amount)
	var removed := before - water_level
	if removed > 0.001:
		var bilge := get_station(&"bilge")
		var pos := bilge.global_position if bilge != null else global_position
		if enable_effects:
			var bilge_local := to_local(bilge.global_position) + Vector3(0.0, 0.55, 0.0) if bilge != null else Vector3(0.0, -0.35, -2.1)
			_spawn_bail_splash(bilge_local)
		if Ocean.current != null:
			Ocean.current.add_foam(global_transform * (Vector3(2.8, 0.0, 1.0) * hull_scale), 1.35 * hull_scale, 0.55)
		Audio.play_sfx(&"bucket_splash", pos)
		bailed.emit(removed)
	return removed


## Host only. Add flood water directly (e.g. from Cursed Bilge-Weep Chests or heavy wave overtopping).
func add_water(amount: float) -> void:
	if not Net.is_host() or is_sinking or amount <= 0.0:
		return
	water_level = minf(1.0, water_level + amount)
	if water_level >= 1.0:
		_begin_sinking()


func _on_hole_interacted(slot_idx: int, _pawn: Node) -> void:
	patch_hole(slot_idx)


func _sync_hole_visuals(slot: Dictionary) -> void:
	var breached: bool = slot["breached"]
	var patched: bool = slot["patched"]
	var panel: Node3D = slot["panel"]
	var hole: Node3D = slot["hole"]
	var patch: Node3D = slot["patch"]
	var it: Interactable = slot["interactable"]
	if panel != null:
		panel.visible = not breached
	if hole != null:
		hole.visible = breached
	if patch != null:
		patch.visible = breached and patched
	if it != null:
		it.enabled = breached and not patched
	var jet: GPUParticles3D = slot["jet"]
	if jet != null and (not breached or patched):
		jet.emitting = false
		jet.visible = false


# ------------------------------------------------------------------ cannons

## Host only. Aim cannon (`&"port"`, `&"starboard"`, `&"port_aft"`, `&"starboard_aft"`) directly.
func aim_cannon(side: StringName, yaw_rad: float, pitch_rad: float) -> void:
	if not Net.is_host() or not _cannons.has(side):
		return
	var c: Dictionary = _cannons[side]
	c["yaw"] = clampf(yaw_rad, -0.58, 0.58)
	c["pitch"] = clampf(pitch_rad, -0.18, 0.42)
	var carriage: Node3D = c["carriage"]
	var barrel: Node3D = c["barrel"]
	if carriage != null:
		carriage.rotation.y = float(c["base_rot_y"]) + float(c["yaw"])
	if barrel != null:
		barrel.rotation.x = float(c["base_barrel_rot_x"]) + float(c["pitch"])


## Host only. Incrementally aim cannon by (dyaw, dpitch) radians (for mouse-aim & fine adjustment).
func aim_cannon_delta(side: StringName, dyaw: float, dpitch: float) -> void:
	if not Net.is_host() or not _cannons.has(side):
		return
	var c: Dictionary = _cannons[side]
	aim_cannon(side, float(c["yaw"]) + dyaw, float(c["pitch"]) + dpitch)


## Host only. Fire the port or starboard cannon. Returns the spawned Cannonball, or null.
func fire_cannon(side: StringName, shooter_pawn: Node = null) -> Cannonball:
	if not Net.is_host() or is_sinking or not _cannons.has(side):
		return null
	var c: Dictionary = _cannons[side]
	if float(c["reload"]) > 0.0 or cannonballs_remaining <= 0:
		return null
	var carriage: Node3D = c["carriage"]
	var barrel: Node3D = c["barrel"]
	if carriage == null:
		return null
	cannonballs_remaining -= 1
	c["reload"] = CANNON_RELOAD_TIME * reload_modifier
	c["recoil"] = 0.34

	# Muzzle world position and aim direction (-Z of barrel/carriage).
	var aim_node := barrel if barrel != null else carriage
	var muzzle_dir := (-aim_node.global_basis.z).normalized()
	var muzzle_pos := aim_node.global_position + muzzle_dir * (1.15 * hull_scale)

	var ball := Cannonball.new()
	ball.name = "Cannonball"
	ball.shooter_ship = self
	ball.shooter_pawn = shooter_pawn
	ball.hull_damage_radius = 0.45 * cannon_radius_modifier
	var host_parent := get_parent() if get_parent() != null else self
	host_parent.add_child(ball)
	ball.global_position = muzzle_pos
	ball.velocity = muzzle_dir * CANNON_MUZZLE_SPEED + linear_velocity * 0.6

	# Subtle ship recoil impulse.
	apply_impulse(-muzzle_dir * 2600.0, muzzle_pos - global_position)

	if shooter_pawn != null:
		var pc := shooter_pawn.get_node_or_null(^"PlayerController") as PlayerController
		if pc == null:
			for child in shooter_pawn.get_children():
				if child is PlayerController:
					pc = child as PlayerController
					break
		if pc != null:
			pc.add_camera_trauma(0.36)

	if enable_effects:
		_spawn_muzzle_flash(muzzle_pos, muzzle_dir)
	Audio.play_sfx(&"cannon_fire", muzzle_pos)
	cannon_fired.emit(side, ball)
	return ball


static func _get_smoke_puff_texture() -> ImageTexture:
	if _smoke_puff_tex != null:
		return _smoke_puff_tex
	var sz := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var half := float(sz - 1) * 0.5
	# Soft Gaussian core blended with organic billowing cloud lobes for feathered gunpowder smoke.
	var lobes: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.86),
		Vector3(-0.25, -0.10, 0.54),
		Vector3(0.24, -0.08, 0.52),
		Vector3(0.05, 0.24, 0.50),
		Vector3(-0.18, 0.20, 0.44),
		Vector3(0.20, 0.18, 0.40),
	]
	for y in sz:
		for x in sz:
			var nx := (float(x) - half) / half
			var ny := (float(y) - half) / half
			var rad := sqrt(nx * nx + ny * ny)
			var gauss := exp(-rad * rad * 3.2)
			var billow := 0.0
			for lobe in lobes:
				var dx := nx - lobe.x
				var dy := ny - lobe.y
				var r := sqrt(dx * dx + dy * dy) / lobe.z
				if r < 1.0:
					var w := 1.0 - r * r
					billow = maxf(billow, w * w)
			var outer_fade := smoothstep(0.0, 0.48, clampf(1.0 - rad, 0.0, 1.0))
			var density := clampf(lerpf(gauss, billow, 0.62) * outer_fade, 0.0, 1.0)
			# Subtle top-lit painterly shading inside each puff so billowing smoke has volume.
			var top_lit := clampf(0.92 - ny * 0.08 + density * 0.08, 0.80, 1.0)
			img.set_pixel(x, y, Color(top_lit, top_lit, top_lit, density))
	_smoke_puff_tex = ImageTexture.create_from_image(img)
	return _smoke_puff_tex


static func _get_muzzle_flash_texture() -> GradientTexture2D:
	if _muzzle_flash_tex != null:
		return _muzzle_flash_tex
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.22, 0.58, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.99, 0.90, 1.0),
		Color(1.0, 0.76, 0.26, 0.88),
		Color(0.98, 0.36, 0.06, 0.28),
		Color(0.80, 0.12, 0.02, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.width = 48
	tex.height = 48
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.gradient = grad
	_muzzle_flash_tex = tex
	return _muzzle_flash_tex


static func _get_muzzle_spark_texture() -> ImageTexture:
	if _muzzle_spark_tex != null:
		return _muzzle_spark_tex
	var sz := 32
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var half := float(sz - 1) * 0.5
	for y in sz:
		for x in sz:
			var dx := absf(float(x) - half) / half
			var dy := absf(float(y) - half) / half
			var d := sqrt(dx * dx * 3.0 + dy * dy * 1.05)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 1.6)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_muzzle_spark_tex = ImageTexture.create_from_image(img)
	return _muzzle_spark_tex


func _cleanup_muzzle_vfx_node(fx_node: Node) -> void:
	_active_muzzle_vfx.erase(fx_node)
	if fx_node == null or not is_instance_valid(fx_node):
		return
	for child in fx_node.get_children():
		if child is GPUParticles3D:
			var gp := child as GPUParticles3D
			gp.emitting = false
			if gp.draw_pass_1 is QuadMesh:
				var qm := gp.draw_pass_1 as QuadMesh
				if qm.material is StandardMaterial3D:
					(qm.material as StandardMaterial3D).albedo_texture = null
				qm.material = null
			if gp.process_material is ParticleProcessMaterial:
				var pm := gp.process_material as ParticleProcessMaterial
				pm.color_ramp = null
				pm.scale_curve = null
			gp.draw_pass_1 = null
			gp.process_material = null
	fx_node.queue_free()


func _cleanup_all_muzzle_vfx() -> void:
	var pending := _active_muzzle_vfx.duplicate()
	_active_muzzle_vfx.clear()
	for fx in pending:
		_cleanup_muzzle_vfx_node(fx)


func _spawn_patch_burst(local_pos: Vector3) -> void:
	if not is_inside_tree():
		return
	var fx_root := Node3D.new()
	fx_root.name = "PatchBurstVFX"
	fx_root.position = local_pos

	var inward_x := -signf(local_pos.x) if absf(local_pos.x) > 0.05 else 0.0
	var burst_dir := Vector3(inward_x, 0.35, 0.0).normalized()

	# 1. Warm oak sawdust puff burst right at the nailed plank patch (0.45 s).
	var sawdust := GPUParticles3D.new()
	sawdust.name = "PatchSawdust"
	sawdust.emitting = false
	sawdust.one_shot = true
	sawdust.explosiveness = 0.92
	sawdust.amount = 10
	sawdust.lifetime = 0.45
	sawdust.local_coords = true
	sawdust.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	sawdust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sawdust.visibility_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3.0, 3.0, 3.0))

	var s_proc := ParticleProcessMaterial.new()
	s_proc.direction = burst_dir
	s_proc.spread = 58.0
	s_proc.initial_velocity_min = 0.75
	s_proc.initial_velocity_max = 1.90
	s_proc.damping_min = 2.6
	s_proc.damping_max = 4.4
	s_proc.gravity = Vector3(0.0, -1.8, 0.0)
	s_proc.scale_min = 0.65
	s_proc.scale_max = 1.20
	s_proc.scale_curve = _make_scale_curve([Vector2(0.0, 0.45), Vector2(0.35, 1.15), Vector2(1.0, 1.45)])
	s_proc.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.18, 0.65, 1.0]),
		PackedColorArray([
			Color(0.88, 0.68, 0.38, 0.0),
			Color(0.84, 0.60, 0.30, 0.74),
			Color(0.72, 0.48, 0.24, 0.34),
			Color(0.60, 0.40, 0.20, 0.0),
		])
	)
	sawdust.process_material = s_proc

	var s_quad := QuadMesh.new()
	s_quad.size = Vector2(0.24, 0.24)
	var s_mat := StandardMaterial3D.new()
	s_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	s_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	s_mat.vertex_color_use_as_albedo = true
	s_mat.albedo_texture = _get_smoke_puff_texture()
	s_quad.material = s_mat
	sawdust.draw_pass_1 = s_quad
	fx_root.add_child(sawdust)

	# 2. 7 bright additive hammer-nail spark motes flying off the iron nailhead.
	var sparks := GPUParticles3D.new()
	sparks.name = "HammerSparks"
	sparks.emitting = false
	sparks.one_shot = true
	sparks.explosiveness = 0.96
	sparks.amount = 7
	sparks.lifetime = 0.38
	sparks.local_coords = true
	sparks.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sparks.visibility_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3.0, 3.0, 3.0))

	var sp_proc := ParticleProcessMaterial.new()
	sp_proc.direction = burst_dir
	sp_proc.spread = 65.0
	sp_proc.initial_velocity_min = 1.6
	sp_proc.initial_velocity_max = 3.6
	sp_proc.damping_min = 1.4
	sp_proc.damping_max = 2.6
	sp_proc.gravity = Vector3(0.0, -7.2, 0.0)
	sp_proc.scale_min = 0.75
	sp_proc.scale_max = 1.25
	sp_proc.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.30, 0.72, 1.0]),
		PackedColorArray([
			Color(1.0, 0.98, 0.86, 1.0),
			Color(1.0, 0.74, 0.22, 0.95),
			Color(0.96, 0.38, 0.06, 0.45),
			Color(0.75, 0.14, 0.02, 0.0),
		])
	)
	sparks.process_material = sp_proc

	var sp_quad := QuadMesh.new()
	sp_quad.size = Vector2(0.11, 0.11)
	var sp_mat := StandardMaterial3D.new()
	sp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sp_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sp_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	sp_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	sp_mat.vertex_color_use_as_albedo = true
	sp_mat.albedo_texture = _get_muzzle_flash_texture()
	sp_quad.material = sp_mat
	sparks.draw_pass_1 = sp_quad
	fx_root.add_child(sparks)

	add_child(fx_root)
	sawdust.restart()
	sparks.restart()
	sawdust.emitting = true
	sparks.emitting = true
	_active_muzzle_vfx.append(fx_root)

	var cleanup := Timer.new()
	cleanup.wait_time = 0.55
	cleanup.one_shot = true
	cleanup.autostart = true
	cleanup.timeout.connect(_cleanup_muzzle_vfx_node.bind(fx_root))
	fx_root.add_child(cleanup)


func _spawn_bail_splash(local_pos: Vector3) -> void:
	if not is_inside_tree():
		return
	var fx_root := Node3D.new()
	fx_root.name = "BilgeBailSplashVFX"
	fx_root.position = local_pos

	var splash := GPUParticles3D.new()
	splash.name = "BailSplashPuff"
	splash.emitting = false
	splash.one_shot = true
	splash.explosiveness = 0.90
	splash.amount = 12
	splash.lifetime = 0.42
	splash.local_coords = true
	splash.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	splash.visibility_aabb = AABB(Vector3(-1.8, -1.2, -1.8), Vector3(3.6, 3.0, 3.6))

	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0.25, 1.0, 0.0).normalized()
	proc.spread = 48.0
	proc.initial_velocity_min = 1.4
	proc.initial_velocity_max = 3.1
	proc.damping_min = 1.0
	proc.damping_max = 2.0
	proc.gravity = Vector3(0.0, -7.8, 0.0)
	proc.scale_min = 0.65
	proc.scale_max = 1.25
	proc.scale_curve = _make_scale_curve([Vector2(0.0, 0.45), Vector2(0.32, 1.15), Vector2(1.0, 0.55)])
	proc.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.16, 0.65, 1.0]),
		PackedColorArray([
			Color(0.95, 0.99, 1.0, 0.0),
			Color(0.92, 0.98, 1.0, 0.84),
			Color(0.70, 0.92, 0.96, 0.45),
			Color(0.60, 0.86, 0.92, 0.0),
		])
	)
	splash.process_material = proc

	var quad := QuadMesh.new()
	quad.size = Vector2(0.26, 0.26)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _get_smoke_puff_texture()
	quad.material = mat
	splash.draw_pass_1 = quad
	fx_root.add_child(splash)

	add_child(fx_root)
	splash.restart()
	splash.emitting = true
	_active_muzzle_vfx.append(fx_root)

	var cleanup := Timer.new()
	cleanup.wait_time = 0.55
	cleanup.one_shot = true
	cleanup.autostart = true
	cleanup.timeout.connect(_cleanup_muzzle_vfx_node.bind(fx_root))
	fx_root.add_child(cleanup)


func _spawn_muzzle_flash(pos: Vector3, dir: Vector3) -> void:
	var host := get_parent()
	if host == null:
		return
	var aim_dir := dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	var fx_root := Node3D.new()
	fx_root.name = "CannonMuzzleVFX"

	# 1. Billowing feathered radial gunpowder smoke puffs on billboarded QuadMesh.
	var smoke := GPUParticles3D.new()
	smoke.name = "CannonSmoke"
	smoke.emitting = false
	smoke.one_shot = true
	smoke.explosiveness = 0.88
	smoke.amount = 30
	smoke.lifetime = 1.35
	smoke.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.visibility_aabb = AABB(Vector3(-10.0, -5.0, -10.0), Vector3(20.0, 14.0, 20.0))

	var s_proc := ParticleProcessMaterial.new()
	s_proc.direction = aim_dir
	s_proc.spread = 28.0
	s_proc.initial_velocity_min = 3.5
	s_proc.initial_velocity_max = 11.5
	s_proc.damping_min = 3.4
	s_proc.damping_max = 6.2
	s_proc.gravity = Vector3(0.0, 1.45, 0.0)
	s_proc.scale_min = 0.90
	s_proc.scale_max = 1.45
	s_proc.scale_curve = _make_scale_curve([Vector2(0.0, 0.40), Vector2(0.35, 1.55), Vector2(1.0, 2.40)])
	s_proc.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.36, 1.0]),
		PackedColorArray([
			Color(1.0, 0.92, 0.75, 0.88),
			Color(0.72, 0.70, 0.68, 0.58),
			Color(0.55, 0.56, 0.58, 0.0),
		])
	)
	smoke.process_material = s_proc

	var smoke_quad := QuadMesh.new()
	smoke_quad.size = Vector2(1.15, 1.15)
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	smoke_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	smoke_mat.vertex_color_use_as_albedo = true
	smoke_mat.render_priority = 1
	smoke_mat.albedo_texture = _get_smoke_puff_texture()
	smoke_quad.material = smoke_mat
	smoke.draw_pass_1 = smoke_quad
	fx_root.add_child(smoke)

	# 2. Brief blazing additive golden-orange muzzle flash core (0.28 s).
	var flash := GPUParticles3D.new()
	flash.name = "MuzzleFlashCore"
	flash.emitting = false
	flash.one_shot = true
	flash.explosiveness = 0.98
	flash.amount = 10
	flash.lifetime = 0.28
	flash.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.visibility_aabb = AABB(Vector3(-6.0, -4.0, -6.0), Vector3(12.0, 8.0, 12.0))

	var f_proc := ParticleProcessMaterial.new()
	f_proc.direction = aim_dir
	f_proc.spread = 22.0
	f_proc.initial_velocity_min = 2.5
	f_proc.initial_velocity_max = 8.5
	f_proc.damping_min = 4.8
	f_proc.damping_max = 7.5
	f_proc.gravity = Vector3(0.0, 0.6, 0.0)
	f_proc.scale_min = 0.95
	f_proc.scale_max = 1.55
	f_proc.scale_curve = _make_scale_curve([Vector2(0.0, 0.55), Vector2(0.24, 1.55), Vector2(1.0, 0.14)])
	f_proc.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.28, 0.68, 1.0]),
		PackedColorArray([
			Color(1.0, 0.98, 0.86, 1.0),
			Color(1.0, 0.72, 0.22, 0.96),
			Color(0.95, 0.32, 0.05, 0.48),
			Color(0.70, 0.10, 0.02, 0.0),
		])
	)
	flash.process_material = f_proc

	var flash_quad := QuadMesh.new()
	flash_quad.size = Vector2(1.75, 1.75)
	var flash_mat := StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	flash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flash_mat.vertex_color_use_as_albedo = true
	flash_mat.render_priority = 2
	flash_mat.albedo_texture = _get_muzzle_flash_texture()
	flash_quad.material = flash_mat
	flash.draw_pass_1 = flash_quad
	fx_root.add_child(flash)

	# 3. Flying burning ember sparks streaking out of the barrel.
	var sparks := GPUParticles3D.new()
	sparks.name = "MuzzleEmbers"
	sparks.emitting = false
	sparks.one_shot = true
	sparks.explosiveness = 0.96
	sparks.amount = 28
	sparks.lifetime = 0.30
	sparks.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sparks.visibility_aabb = AABB(Vector3(-10.0, -5.0, -10.0), Vector3(20.0, 10.0, 20.0))

	var e_proc := ParticleProcessMaterial.new()
	e_proc.direction = aim_dir
	e_proc.spread = 32.0
	e_proc.initial_velocity_min = 9.5
	e_proc.initial_velocity_max = 20.5
	e_proc.damping_min = 2.2
	e_proc.damping_max = 4.6
	e_proc.gravity = Vector3(0.0, -8.5, 0.0)
	e_proc.scale_min = 0.75
	e_proc.scale_max = 1.45
	e_proc.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.28, 0.70, 1.0]),
		PackedColorArray([
			Color(1.0, 0.98, 0.84, 1.0),
			Color(1.0, 0.64, 0.16, 0.95),
			Color(0.95, 0.26, 0.04, 0.55),
			Color(0.65, 0.08, 0.02, 0.0),
		])
	)
	sparks.process_material = e_proc

	var spark_quad := QuadMesh.new()
	spark_quad.size = Vector2(0.09, 0.40)
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	spark_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	spark_mat.vertex_color_use_as_albedo = true
	spark_mat.render_priority = 2
	spark_mat.albedo_texture = _get_muzzle_spark_texture()
	spark_quad.material = spark_mat
	sparks.draw_pass_1 = spark_quad
	fx_root.add_child(sparks)

	host.add_child(fx_root)
	fx_root.global_position = pos
	smoke.restart()
	flash.restart()
	sparks.restart()
	smoke.emitting = true
	flash.emitting = true
	sparks.emitting = true
	_active_muzzle_vfx.append(fx_root)

	var cleanup := Timer.new()
	cleanup.wait_time = 1.55
	cleanup.one_shot = true
	cleanup.autostart = true
	cleanup.timeout.connect(_cleanup_muzzle_vfx_node.bind(fx_root))
	fx_root.add_child(cleanup)


# ------------------------------------------------------------------ station driving

## Host only. Instant one-tap quick-use for ship stations (e.g. dropping a raised anchor
## without locking into the capstan). Returns true if consumed.
func try_station_quick_use(st: Station, _pawn: Node) -> bool:
	if not Net.is_host() or st == null:
		return false
	if st.kind == &"anchor" and not anchor_down and anchor_progress <= 0.06:
		_manual_capstan_heave = false
		_capstan_heaving_this_tick = false
		_capstan_assist_hands = 0
		set_anchor(true)
		Audio.play_sfx(&"capstan_clank", st.global_position, -1.0)
		return true
	return false


## Contextual focus prompt shown when looking at a station handle on this ship (strict ASCII).
func get_station_focus_prompt(st: Station) -> String:
	if st == null:
		return ""
	match st.kind:
		&"anchor":
			if not anchor_down and anchor_progress <= 0.06:
				return "Drop anchor"
			return "Heave anchor (%d%%)" % int(roundf(anchor_progress * 100.0))
		&"sail_length":
			if sail_set < 0.08:
				return "Lower sails"
			return "Raise / lower sails (%d%%)" % int(roundf(sail_set * 100.0))
		&"sail_angle":
			if _last_wind_catch >= 0.85 and sail_set >= 0.15:
				return "Trim sails (FULL WIND)"
			return "Angle sails"
	return st.prompt


## Contextual live control-hint prompt shown while crewing a station (strict ASCII, starts with '[').
func get_station_active_prompt(st: Station) -> String:
	if st == null:
		return ""
	match st.kind:
		&"helm":
			var helm_txt := "CENTER"
			if helm < -0.06:
				helm_txt = "PORT"
			elif helm > 0.06:
				helm_txt = "STBD"
			return "[A/D] Steer (%s) | [S/RMB] Center | [F] Step Off" % helm_txt
		&"anchor":
			return "[Hold W] Heave Anchor (%d%%) | [S] Drop | [F] Let Go" % int(roundf((1.0 - anchor_progress) * 100.0))
		&"sail_length":
			return "[S] Lower / [W] Raise Sail (%d%%) | [F] Let Go" % int(roundf(sail_set * 100.0))
		&"sail_angle":
			var wind_txt := "FULL WIND" if (_last_wind_catch >= 0.85 and sail_set >= 0.15) else (
				"GOOD" if _last_wind_catch >= 0.55 else (
					"SQUARE" if absf(sail_trim) < 0.12 else "LUFFING"
				)
			)
			return "[A/D] Angle Sail (%s) | [RMB] Square | [F] Let Go" % wind_txt
		&"cannon":
			return "[WASD/Mouse] Aim | [LMB] Fire (%d) | [F] Step Off" % cannonballs_remaining
		&"map_table":
			return "[WASD] Pan | [LMB/RMB] Zoom | [Space] Pin | [F] Step Off"
		&"bilge":
			return "[Hold LMB/W] Bail Bilge | [F] Step Off"
	return "[F] Step Off"


func _count_capstan_assist_hands(st: Station) -> int:
	if st == null or not is_inside_tree():
		return 0
	var cap_pos := st.global_position
	var max_dist_sq := 2.6 * 2.6
	var seen: Dictionary = {}
	var extra := 0
	var candidates: Array[Pawn] = []
	var parent_node := get_parent()
	if parent_node != null:
		for ch in parent_node.get_children():
			if ch is Pawn:
				candidates.append(ch as Pawn)
	var tree := get_tree()
	if tree != null:
		for cb in tree.get_nodes_in_group(&"crew_brains"):
			var p := cb.get_parent() as Pawn
			if p != null:
				candidates.append(p)
		for cc in tree.get_nodes_in_group(&"combatants"):
			var p2 := cc.get_parent() as Pawn
			if p2 != null:
				candidates.append(p2)
	for p in candidates:
		if p == null or not is_instance_valid(p) or p == st.occupant or p.dead:
			continue
		var iid := p.get_instance_id()
		if seen.has(iid):
			continue
		seen[iid] = true
		if p.platform != self:
			continue
		if p.station != null and p.station != st:
			continue
		if p.global_position.distance_squared_to(cap_pos) <= max_dist_sq:
			extra += 1
			if extra >= 3:
				break
	return extra


func _drive_station(st: Station, axis: Vector2, primary: bool, secondary: bool, delta: float) -> void:
	match st.kind:
		&"helm":
			if absf(axis.x) > 0.05:
				if _helm_detent_timer > 0.0:
					_helm_detent_timer = maxf(0.0, _helm_detent_timer - delta)
				else:
					var rate := 1.25 if ship_class == &"brigantine" else 1.55
					var prev_t := helm_target
					var next_t := clampf(helm_target + axis.x * rate * delta, -1.0, 1.0)
					# Subtle golden center-spoke detent pause when turning across 0.0.
					if (prev_t < -0.02 and next_t >= 0.0) or (prev_t > 0.02 and next_t <= 0.0):
						next_t = 0.0
						_helm_detent_timer = 0.07
					set_helm_target(next_t)
			elif axis.y < -0.35 or secondary:
				_helm_detent_timer = 0.0
				set_helm_target(move_toward(helm_target, 0.0, 2.4 * delta))
			else:
				_helm_detent_timer = 0.0
		&"sail_length":
			# Sea of Thieves standard polarity: [S] lowers/unfurls sail (faster), [W] raises/furls sail (slower).
			var lower_delta := 0.0
			if axis.y < -0.05:
				lower_delta = absf(axis.y)
			elif axis.y > 0.05:
				lower_delta = -absf(axis.y)
			elif primary:
				lower_delta = 1.0
			elif secondary:
				lower_delta = -1.0
			if absf(lower_delta) > 0.05:
				set_sail_target(sail_target + lower_delta * 0.65 * delta)
				_rope_sfx_accum += absf(lower_delta) * delta
				if _rope_sfx_accum > 0.42:
					_rope_sfx_accum = 0.0
					Audio.play_sfx(&"rope_creak", st.global_position, -3.0)
		&"sail_angle":
			if absf(axis.x) > 0.05:
				set_trim_target(trim_target + axis.x * 1.38 * delta)
				_rope_sfx_accum += absf(axis.x) * delta
				if _rope_sfx_accum > 0.45:
					_rope_sfx_accum = 0.0
					Audio.play_sfx(&"rope_creak", st.global_position, -3.0)
			elif secondary:
				# Smoothly square sails flat forward for Sea-of-Thieves headwind dummy sails.
				var before_trim := trim_target
				set_trim_target(move_toward(trim_target, 0.0, 2.2 * delta))
				if absf(trim_target - before_trim) > 0.001:
					_rope_sfx_accum += delta
					if _rope_sfx_accum > 0.45:
						_rope_sfx_accum = 0.0
						Audio.play_sfx(&"rope_creak", st.global_position, -3.0)
		&"anchor":
			_manual_capstan_heave = true
			if axis.y < -0.35 or (secondary and axis.y <= 0.15):
				# Release pawl -> drop anchor and step off capstan.
				_manual_capstan_heave = false
				_capstan_heaving_this_tick = false
				_capstan_assist_hands = 0
				set_anchor(true)
				st.release()
			elif axis.y > 0.15 or primary:
				# Physical capstan heave-up (faster with nearby crew/co-op hands!).
				_capstan_heaving_this_tick = true
				var extra_hands := _count_capstan_assist_hands(st)
				_capstan_assist_hands = extra_hands
				var heave_rate := 0.25 * (1.0 + 0.72 * float(extra_hands))
				var prev_p := anchor_progress
				anchor_progress = maxf(0.0, anchor_progress - heave_rate * delta)
				if absf(anchor_progress - prev_p) > 0.0005:
					_capstan_sfx_accum += absf(anchor_progress - prev_p)
					if _capstan_sfx_accum > 0.14:
						_capstan_sfx_accum = 0.0
						Audio.play_sfx(&"capstan_clank", st.global_position, -2.5)
				if anchor_progress <= 0.005:
					anchor_progress = 0.0
					anchor_down = false
					_manual_capstan_heave = false
					_capstan_heaving_this_tick = false
					_capstan_assist_hands = 0
					_anchor_swing_timer = 0.0
					_anchor_swing_dir = 0.0
					Audio.play_sfx(&"capstan_clank", st.global_position, 0.5)
					Audio.play_sfx(&"parry_ring", st.global_position, -5.0)
					anchor_raised.emit()
					st.release()
		&"cannon":
			var side := st.meta_id
			if _cannons.has(side):
				var c: Dictionary = _cannons[side]
				c["yaw"] = clampf(float(c["yaw"]) - axis.x * 0.85 * delta, -0.58, 0.58)
				c["pitch"] = clampf(float(c["pitch"]) + axis.y * 0.65 * delta, -0.18, 0.42)
				if primary:
					fire_cannon(side, st.occupant)
		&"bilge":
			if primary or axis.y > 0.3:
				bail(0.28 * delta)
		&"map_table":
			pass


# ------------------------------------------------------------------ simulation

func _physics_process(delta: float) -> void:
	if not Net.is_host():
		_tick_client_interp(delta)
		return
	_tick_controls(delta)
	_tick_flooding(delta)
	_tick_cannons(delta)
	_tick_hydrodynamics(delta)
	_tick_audio(delta)


func _tick_controls(delta: float) -> void:
	var prev_helm := helm
	helm = move_toward(helm, helm_target, 2.4 * delta)
	if absf(helm - prev_helm) > 0.0005:
		_wheel_sfx_accum += absf(helm - prev_helm)
		var hst := get_station(&"helm")
		var hpos := hst.global_position if hst != null else global_position
		if absf(prev_helm) >= 0.04 and absf(helm) < 0.04:
			# Golden center-spoke CLUNK detent cue.
			var detent_sfx := &"wood_clunk" if Audio.has_sound(&"wood_clunk") else &"wheel_creak"
			var snd := Audio.play_sfx(detent_sfx, hpos, -1.5, 0.02)
			if detent_sfx == &"wheel_creak" and snd is AudioStreamPlayer3D:
				(snd as AudioStreamPlayer3D).pitch_scale *= 1.24
			_wheel_sfx_accum = 0.0
		elif absf(prev_helm) < 0.985 and absf(helm) >= 0.985:
			# Solid hard-over end-stop thud.
			Audio.play_sfx(&"hull_creak", hpos, -6.0)
			_wheel_sfx_accum = 0.0
		elif _wheel_sfx_accum > 0.30:
			_wheel_sfx_accum = 0.0
			Audio.play_sfx(&"wheel_creak", hpos, -4.0)

	var prev_sail := sail_set
	sail_set = move_toward(sail_set, sail_target, 1.85 * delta)
	var prev_trim := sail_trim
	sail_trim = move_toward(sail_trim, trim_target, 2.8 * delta)
	if (prev_trim * sail_trim < 0.0) or (absf(prev_trim) >= 0.04 and absf(sail_trim) < 0.04):
		var st_angle := get_station(&"sail_angle")
		Audio.play_sfx(&"rope_creak", st_angle.global_position if st_angle != null else global_position, -5.0)

	var prev_anc := anchor_progress
	if _manual_capstan_heave:
		if not _capstan_heaving_this_tick:
			# Gravity slip-back if the pirate stops heaving before locking the capstan at top!
			if anchor_progress < 1.0:
				anchor_down = true
				anchor_progress = minf(1.0, anchor_progress + 0.44 * delta)
				if absf(anchor_progress - prev_anc) > 0.0005:
					_capstan_sfx_accum += absf(anchor_progress - prev_anc)
					if _capstan_sfx_accum > 0.14:
						_capstan_sfx_accum = 0.0
						var ast_slip := get_station(&"anchor")
						Audio.play_sfx(&"capstan_clank", ast_slip.global_position if ast_slip != null else global_position, -2.5)
			else:
				var ast_done := get_station(&"anchor")
				if ast_done == null or not ast_done.is_occupied():
					_manual_capstan_heave = false
		_capstan_heaving_this_tick = false
	else:
		var target_anc := 1.0 if anchor_down else 0.0
		var anc_rate := 0.88 if anchor_down else 0.42
		anchor_progress = move_toward(anchor_progress, target_anc, anc_rate * delta)
		if absf(anchor_progress - prev_anc) > 0.0005:
			_capstan_sfx_accum += absf(anchor_progress - prev_anc)
			if _capstan_sfx_accum > 0.16:
				_capstan_sfx_accum = 0.0
				var ast := get_station(&"anchor")
				Audio.play_sfx(&"capstan_clank", ast.global_position if ast != null else global_position, -3.0)
	var anc_sub := anchor_progress > 0.55
	if anc_sub and not _was_anchor_submerged:
		Audio.play_sfx(&"anchor_splash", _anchor_world_pos())
	_was_anchor_submerged = anc_sub

	# Signature DESIGN.md Anchor-Turn Swinging Stop: when anchor hits bottom at speed with wheel turned!
	if prev_anc < 0.96 and anchor_progress >= 0.96 and not is_sinking:
		var fwd_spd := forward_speed()
		if fwd_spd >= 3.0 and absf(helm) >= 0.14:
			var yaw_dir := -signf(helm)
			var speed_frac := clampf((fwd_spd - 2.2) / 5.2, 0.38, 1.0)
			var turn_frac := clampf(absf(helm), 0.25, 1.0)
			var max_yaw := 0.85 if ship_class == &"brigantine" else 1.05
			var yaw_impulse := yaw_dir * max_yaw * speed_frac * (0.65 + 0.35 * turn_frac)
			angular_velocity.y = clampf(angular_velocity.y + yaw_impulse, -1.25, 1.25)
			# Brief lateral stern skid outward around the taut bow anchor hawser.
			var skid_spd := clampf(fwd_spd * 0.28, 0.85, 2.2) * (0.85 if ship_class == &"brigantine" else 1.0)
			linear_velocity += global_basis.x * (yaw_dir * skid_spd)
			_anchor_swing_dir = signf(helm)
			_anchor_swing_timer = 1.95
			Audio.play_sfx(&"hull_creak", global_position, 1.0)
			hull_impacted.emit(_anchor_world_pos(), 0.28)
			_stamp_anchor_turn_foam(1.0)
			anchor_turn_triggered.emit(fwd_spd, yaw_dir)

	if _anchor_swing_timer > 0.0:
		_anchor_swing_timer = maxf(0.0, _anchor_swing_timer - delta)

	# Sail fill cue when catching wind strongly after lowering sail.
	_last_wind_catch = wind_catch()
	var drawing := sail_set > 0.35 and _last_wind_catch > 0.65
	var played_fill := drawing and not _was_drawing_wind and prev_sail <= sail_set
	if played_fill:
		Audio.play_sfx(&"sail_fill", global_position + Vector3.UP * 6.0, -3.0)
	_was_drawing_wind = drawing

	# Full-wind sweet-spot cue & signal with clean hysteresis (no spam).
	var at_peak_wind := sail_set >= 0.45 and _last_wind_catch >= 0.88
	if at_peak_wind and not _was_peak_wind:
		_was_peak_wind = true
		if not played_fill:
			Audio.play_sfx(&"sail_fill", global_position + Vector3.UP * 6.0, -2.0)
		wind_caught.emit(_last_wind_catch)
	elif _was_peak_wind and (sail_set < 0.35 or _last_wind_catch < 0.75):
		_was_peak_wind = false


func _tick_flooding(delta: float) -> void:
	var inflow := 0.0
	for h in holes:
		var is_open := bool(h["breached"]) and not bool(h["patched"])
		var jet: GPUParticles3D = h["jet"]
		if not is_open:
			if jet != null and jet.emitting:
				jet.emitting = false
				jet.visible = false
			continue
		var world_p := global_transform * (h["local_pos"] as Vector3)
		var sub := Sea.height(world_p.x, world_p.z) - world_p.y
		# Even holes just above calm waterline take wash when rolling or flooding deepens the hull.
		var head := maxf(sub + 0.12, 0.0)
		var active_leak := head > 0.01
		if jet != null:
			jet.visible = active_leak
			jet.emitting = active_leak
		if active_leak:
			var sev: float = h["severity"]
			# One deep hole floods the sloop in roughly ~45-55 s; three holes in ~15-20 s.
			inflow += (0.010 + 0.014 * minf(head, 1.5)) * sev

	if inflow > 0.0 and not is_sinking:
		water_level = minf(1.0, water_level + inflow * delta)
		if water_level >= 1.0:
			_begin_sinking()

	if is_sinking:
		_sink_timer += delta
		water_level = 1.0

	# Water weight increases ship mass and slows handling.
	mass = _hull_mass + water_level * FLOOD_EXTRA_MASS * (_hull_mass / BASE_MASS)


func _begin_sinking() -> void:
	if is_sinking:
		return
	is_sinking = true
	_sink_timer = 0.0
	_sink_foam_accum = 0.18
	_sink_list_dir = 1.0 if global_basis.x.y <= 0.0 else -1.0
	Audio.play_sfx(&"hull_creak", global_position, 2.0)
	if faction == &"player":
		Audio.play_stinger(&"sunk")
	sunk.emit()


func _tick_cannons(delta: float) -> void:
	for c: Dictionary in _cannons.values():
		c["reload"] = maxf(0.0, float(c["reload"]) - delta)
		c["recoil"] = move_toward(float(c["recoil"]), 0.0, 0.72 * delta)


func _tick_hydrodynamics(delta: float) -> void:
	var xf := global_transform
	var b := xf.basis
	var origin := xf.origin
	var sub_accum := 0.0
	var mass_ratio := _hull_mass / BASE_MASS

	# Buoyancy reduction as the hull founders.
	var sink_buoy := 1.0
	if is_sinking:
		sink_buoy = maxf(0.08, 1.0 - _sink_timer * 0.16)
	else:
		# Flooded hold drags the hull deeper cleanly (without capsizing early).
		sink_buoy = lerpf(1.0, 0.76, water_level)

	# 1. Multi-point buoyancy & per-probe damping (cross-version Godot 4.7+/4.8+ rigid-body point velocity).
	var probe_span := 1.15 * hull_scale
	const BUOY_GAIN := 1.98
	var com_world := xf * center_of_mass
	for entry in BUOYANCY_PROBES:
		var local_p: Vector3 = (entry[0] as Vector3) * _probe_scale
		var w: float = entry[1]
		var world_p := xf * local_p
		var sea_y := Sea.height(world_p.x, world_p.z)
		var sub := sea_y - world_p.y
		if sub <= 0.0:
			continue
		var frac := clampf(sub / probe_span, 0.0, 1.85)
		var damp_frac := minf(frac, 1.0)
		sub_accum += w * damp_frac

		var buoy_f := _hull_mass * GRAVITY * BUOY_GAIN * w * frac * sink_buoy
		var v_p := linear_velocity + angular_velocity.cross(world_p - com_world)
		var v_damp := -v_p.y * (20500.0 * mass_ratio * w * damp_frac)
		var rel := world_p - origin
		# Keep vertical application arm modest so steep waves pitch/roll smoothly without flipping.
		rel.y = clampf(rel.y, -0.5, 0.5)
		apply_force(Vector3(0.0, buoy_f + v_damp, 0.0), rel)

	_last_submerged_frac = clampf(sub_accum, 0.0, 1.0)

	# 2. Metacentric righting torque & local-frame angular damping.
	var up_now := b.y
	var righting_axis := up_now.cross(Vector3.UP)
	var righting_strength := 142000.0 * mass_ratio * (0.35 if is_sinking else 1.0)
	apply_torque(righting_axis * righting_strength)

	if is_sinking:
		# List gracefully to one side while settling below the waves.
		apply_torque(b.z * (_sink_list_dir * 26000.0 * mass_ratio * minf(_sink_timer * 0.4, 1.0)))

	var ang_local := b.inverse() * angular_velocity
	var ang_damp_local := Vector3(
		-ang_local.x * 64000.0 * mass_ratio,
		-ang_local.y * 52000.0 * mass_ratio,
		-ang_local.z * 29000.0 * mass_ratio
	)
	apply_torque(b * ang_damp_local)

	# 3. Anisotropic hull hydrodynamic drag (low forward resistance, strong keel resistance).
	# Longer sleeker Brigantine waterline carries lower wave-making Froude drag per tonne than Sloop.
	if _last_submerged_frac > 0.04:
		var wet := lerpf(0.3, 1.0, _last_submerged_frac)
		var v_loc := b.inverse() * linear_velocity
		var flood_drag := 1.0 + water_level * 0.55
		var hull_drag_mult := 0.78 if ship_class == &"brigantine" else 1.0
		var f_z := -(v_loc.z * 460.0 + v_loc.z * absf(v_loc.z) * 415.0) * hull_drag_mult * flood_drag * mass_ratio
		var f_x := -(v_loc.x * 6800.0 + v_loc.x * absf(v_loc.x) * 2900.0) * mass_ratio
		var f_y := -v_loc.y * 5200.0 * mass_ratio
		apply_central_force((b * Vector3(f_x, f_y, f_z)) * wet)

	# 4. Sail aerodynamics, Sea-of-Thieves wind curve & gust heel (disabled once sinking).
	if not is_sinking and sail_set > 0.01:
		var aw := apparent_wind()
		var aw_local := b.inverse() * aw
		var wind_spd := lerpf(Weather.wind_vector().length(), aw.length(), 0.25)
		var wind_factor := clampf(wind_spd / 8.0, 0.55, 1.75)
		var catch := _last_wind_catch
		var min_headway: float
		if aw_local.z > 0.15:
			# Headwind (blowing aft toward +Z in ship local space): Sea-of-Thieves dummy sails squared forward.
			var square_fac := clampf(1.0 - absf(sail_trim) / 0.95, 0.0, 1.0)
			if ship_class == &"brigantine":
				min_headway = lerpf(0.14, 0.23, square_fac) * close_hauled_modifier
			else:
				min_headway = lerpf(0.24, 0.44, square_fac) * close_hauled_modifier
		else:
			# Crosswind / tailwind: poor trim noticeably loses speed vs full billow.
			min_headway = 0.18 * close_hauled_modifier
		var drive_coeff := lerpf(min_headway, 1.0, catch)
		var billow_surge := 1.12 if (catch >= 0.85 and sail_set >= 0.35) else 1.0
		var flood_slow := lerpf(1.0, 0.65, water_level)
		var anchor_hold := 1.0 - clampf((anchor_progress - 0.92) / 0.08, 0.0, 0.94)
		var thrust := sail_set * wind_factor * drive_coeff * billow_surge * 17500.0 * _class_thrust_mult * speed_modifier * flood_slow * anchor_hold
		var fwd_horiz := Vector3(-b.z.x, 0.0, -b.z.z)
		if fwd_horiz.length_squared() > 0.001:
			apply_central_force(fwd_horiz.normalized() * thrust)

		# Beam-wind heel torque about ship Z axis.
		var side_wind := clampf(aw_local.x / 12.0, -1.6, 1.6)
		apply_torque(b.z * (-side_wind * sail_set * 16500.0 * mass_ratio))

	# 5. Rudder torque (positive helm -> starboard turn -> negative Y torque).
	if not is_sinking and _last_submerged_frac > 0.05:
		var fwd := forward_speed()
		var dir_sign := 1.0 if fwd >= -0.35 else -1.0
		var speed_auth := clampf(absf(fwd) / 4.2, 0.0, 1.45)
		var base_low := 0.85 if (sail_set < 0.08 and anchor_progress < 0.5) else 0.30
		var low_speed_auth := base_low * (1.0 - anchor_progress)
		var half_sail_agility := lerpf(1.36, 1.0, smoothstep(0.42, 0.95, sail_set))
		var turn_torque := -helm * dir_sign * (speed_auth + low_speed_auth) * half_sail_agility * 38000.0 * (1.18 if ship_class == &"brigantine" else 1.0) * speed_modifier
		apply_torque(Vector3.UP * turn_torque)

	# 6. Anchor drag and swinging stop.
	if anchor_progress > 0.65:
		var hv := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
		if anchor_progress < 0.94:
			# Gentle water drag while anchor chain & flukes sink toward the seabed.
			var fall_frac := clampf((anchor_progress - 0.65) / 0.29, 0.0, 1.0)
			apply_central_force(-hv * (2200.0 * fall_frac * mass_ratio))
		else:
			# Full seabed anchor bite braking!
			var bite_frac := clampf((anchor_progress - 0.94) / 0.06, 0.35, 1.0)
			apply_central_force(-hv * (21000.0 * bite_frac * mass_ratio))
		if _anchor_swing_timer > 0.0 and anchor_progress >= 0.94:
			var swing_env := clampf(_anchor_swing_timer / 1.95, 0.0, 1.0)
			var swing := -_anchor_swing_dir * (0.35 + 0.65 * swing_env) * 36000.0 * mass_ratio
			apply_torque(Vector3.UP * swing)

	# Update hold water slosh target from local roll/pitch & angular motion.
	var roll_slope := clampf(-b.x.y * 0.45 - ang_local.z * 0.14, -0.35, 0.35)
	var pitch_slope := clampf(-b.z.y * 0.35 + ang_local.x * 0.10, -0.28, 0.28)
	_slosh_tilt = _slosh_tilt.lerp(Vector2(roll_slope, pitch_slope), clampf(delta * 5.0, 0.0, 1.0))


func _tick_audio(delta: float) -> void:
	_creak_cooldown = maxf(0.0, _creak_cooldown - delta)
	_flap_cooldown = maxf(0.0, _flap_cooldown - delta)
	_slosh_cooldown = maxf(0.0, _slosh_cooldown - delta)

	# Hull creak on pronounced roll rate.
	var roll_rate := absf((global_basis.inverse() * angular_velocity).z)
	if roll_rate > 0.22 and _creak_cooldown <= 0.0:
		_creak_cooldown = 3.2
		Audio.play_sfx(&"hull_creak", global_position, -6.0)

	# Sail flap when sail is set but poorly trimmed / luffing.
	var luff := (1.0 - _last_wind_catch) * sail_set
	if luff > 0.55 and _flap_cooldown <= 0.0:
		_flap_cooldown = 2.1
		Audio.play_sfx(&"sail_flap", global_position + Vector3.UP * 6.5, -5.0)

	# Hold slosh when carrying water in rough motion.
	if water_level > 0.12 and _slosh_cooldown <= 0.0:
		_slosh_cooldown = 3.8
		Audio.play_sfx(&"hold_slosh", global_position + Vector3.DOWN * 0.4, -4.0)


func _tick_client_interp(delta: float) -> void:
	if not _net_has_state:
		return
	var k := clampf(delta * 10.0, 0.0, 1.0)
	global_transform = global_transform.interpolate_with(_net_target_xform, k)


# ------------------------------------------------------------------ visuals

func _process(delta: float) -> void:
	_register_ocean_mask()
	_update_lod()
	_update_visuals(delta)
	_update_wake(delta)


func _update_lod() -> void:
	if _model == null or _lod_model == null:
		return
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null:
		return
	var dist := cam.global_position.distance_to(global_position)
	var want_lod := dist > LOD_SWITCH_DIST
	if want_lod != _using_lod:
		_using_lod = want_lod
		_model.visible = not want_lod
		_lod_model.visible = want_lod
		if cabin_furnishings != null and is_instance_valid(cabin_furnishings):
			cabin_furnishings.visible = not want_lod
		if ship_bell_node != null and is_instance_valid(ship_bell_node):
			ship_bell_node.visible = not want_lod
		if ship_nameplate != null and is_instance_valid(ship_nameplate):
			ship_nameplate.visible = not want_lod
		if hull_crest != null and is_instance_valid(hull_crest):
			hull_crest.visible = (not want_lod) and (_spectral_phase > 0.05)
		if _crows_nest_rungs_mi != null and is_instance_valid(_crows_nest_rungs_mi):
			_crows_nest_rungs_mi.visible = not want_lod


func _update_visuals(delta: float) -> void:
	_sail_time += delta
	_slosh_time += delta

	# Wheel & rudder.
	if _wheel != null:
		var turns := 1.5 if ship_class == &"brigantine" else 1.0
		_wheel.rotation.z = -helm * TAU * turns
	if _rudder != null:
		_rudder.rotation.y = helm * deg_to_rad(32.0)

	# Yards, sails & furled rolls (1 mast on Sloop, 2 masts on Brigantine).
	var show_sail := sail_set > 0.06
	for y in _yards:
		y.rotation.y = sail_trim
	for s in _sails:
		s.visible = show_sail
		s.rotation.y = sail_trim
		s.scale.y = maxf(sail_set, 0.08)
	for sf in _sails_furled:
		sf.visible = not show_sail
		sf.rotation.y = sail_trim

	# Sync LOD sails/yards too.
	for ly in _lod_yards:
		ly.rotation.y = sail_trim
	for ls in _lod_sails:
		ls.visible = show_sail
		ls.rotation.y = sail_trim
		ls.scale.y = maxf(sail_set, 0.08)
	for lsf in _lod_sails_furled:
		lsf.visible = not show_sail
		lsf.rotation.y = sail_trim

	# Masthead flags weathervane to apparent wind.
	var aw := apparent_wind()
	var wind_spd := aw.length()
	if not _flags.is_empty() and wind_spd > 0.2:
		var aw_loc := global_basis.inverse() * aw
		# Flag extends along local -Z from masthead, so aim -Z along aw_loc.
		var target_yaw := atan2(-aw_loc.x, -aw_loc.z)
		for idx in _flags.size():
			_flags[idx].rotation.y = lerp_angle(_flags[idx].rotation.y, target_yaw, clampf(delta * 6.0, 0.0, 1.0))
			if idx < _lod_flags.size():
				_lod_flags[idx].rotation.y = _flags[idx].rotation.y
		if _emissary_streamer != null and is_instance_valid(_emissary_streamer):
			_emissary_streamer.rotation.y = lerp_angle(_emissary_streamer.rotation.y, target_yaw, clampf(delta * 5.2, 0.0, 1.0))

	# Update wind-billow shader uniforms across all sails and flags.
	var ws := clampf(wind_spd / 10.0, 0.1, 2.4)
	var luff := clampf((1.0 - _last_wind_catch) * (0.4 + 0.6 * sail_set), 0.0, 1.0)
	for sm in _sail_mats:
		sm.set_shader_parameter(&"wind_catch", _last_wind_catch * sail_set)
		sm.set_shader_parameter(&"luff_amount", luff)
		sm.set_shader_parameter(&"wind_strength", ws)
		sm.set_shader_parameter(&"sail_time", _sail_time)
	for fmat in _flag_mats:
		fmat.set_shader_parameter(&"wind_strength", ws)
		fmat.set_shader_parameter(&"sail_time", _sail_time)

	# Distant rival crow's nest spyglass optics glint (daylight horizon signal, 55..550 m).
	if _lookout_glint != null and is_instance_valid(_lookout_glint):
		_lookout_glint_phase += delta
		var vp := get_viewport()
		var cam := vp.get_camera_3d() if vp != null else null
		var day_amt := Weather.daylight()
		var cam_dist := cam.global_position.distance_to(global_position) if cam != null else 0.0
		var eligible := (not is_sinking) and (_spectral_phase > 0.35) and (cam != null) \
			and (cam_dist >= 55.0) and (cam_dist <= 550.0) and (day_amt > 0.15)
		if eligible:
			var dist_env := smoothstep(55.0, 88.0, cam_dist) * smoothstep(550.0, 440.0, cam_dist)
			var pulse_main := pow(maxf(0.0, sin(_lookout_glint_phase * 1.38)), 10.0)
			var pulse_shimmer := 0.22 * pow(maxf(0.0, sin(_lookout_glint_phase * 2.76 + 0.9)), 4.0)
			var intensity := clampf((pulse_main + pulse_shimmer) * dist_env * clampf(day_amt, 0.0, 1.0) * 1.45, 0.0, 1.6)
			_lookout_glint.visible = intensity > 0.015
			if _lookout_glint.visible and _lookout_glint_mat != null:
				_lookout_glint_mat.set_shader_parameter(&"glint_intensity", intensity)
				var g_scale := lerpf(2.2, 5.2, clampf((cam_dist - 55.0) / 450.0, 0.0, 1.0))
				_lookout_glint_mat.set_shader_parameter(&"glint_scale", g_scale)
		else:
			_lookout_glint.visible = false

	# Capstan spin & anchor drop.
	if _capstan != null:
		_capstan.rotation.y = anchor_progress * TAU * 4.5
	if _anchor_node != null:
		_anchor_node.position = _anchor_base_pos + Vector3(0.0, -anchor_progress * 4.2, 0.0)

	# Cannons (yaw, pitch, recoil).
	for c: Dictionary in _cannons.values():
		var carriage: Node3D = c["carriage"]
		var barrel: Node3D = c["barrel"]
		if carriage != null:
			carriage.rotation.y = float(c["base_rot_y"]) + float(c["yaw"])
			# Recoil pushes carriage inboard (+Z in carriage local space since -Z is muzzle).
			var local_back := Basis(Vector3.UP, carriage.rotation.y).z
			carriage.position = (c["base_pos"] as Vector3) + local_back * float(c["recoil"])
		if barrel != null:
			barrel.rotation.x = float(c["base_barrel_rot_x"]) + float(c["pitch"])

	# Ship's bell damped pendulum (drives both sculpted ShipBellPivot and any GLB Bell).
	if (_bell_cup_pivot != null or _bell != null) and (absf(_bell_swing) > 0.001 or absf(_bell_vel) > 0.001):
		_bell_vel += (-_bell_swing * 36.0 - _bell_vel * 2.4) * delta
		_bell_swing = clampf(_bell_swing + _bell_vel * delta, -0.78, 0.78)
		if _bell_cup_pivot != null and is_instance_valid(_bell_cup_pivot):
			_bell_cup_pivot.rotation.x = _bell_swing
		if _bell != null and is_instance_valid(_bell):
			_bell.rotation.x = _bell_swing

	# Running rigging ropes (SHIP_ART.md contract).
	if not _using_lod:
		_aim_ropes()

	if not _ghost_hull_mats.is_empty():
		_wisp_time += delta
		for gm in _ghost_hull_mats:
			gm.set_shader_parameter(&"wisp_time", _wisp_time)

	# Night cabin glass glow & lantern flicker (cursed vessels keep eerie glow even by day).
	var night := 1.0 - Weather.daylight()
	var has_curse_glow := _effective_glow_accent.get_luminance() > 0.01
	var window_em := (lerpf(1.45, 2.8, night) if has_curse_glow else lerpf(0.22, 2.2, night)) * _spectral_phase
	for wm in _window_mats:
		wm.emission_energy_multiplier = window_em
	var flicker := 0.94 + 0.06 * sin(_sail_time * 9.3) * cos(_sail_time * 6.1)
	var phase_light_scale := _spectral_phase * (1.0 + _spectral_flare * 0.45)
	for idx in _lantern_lights.size():
		var l := _lantern_lights[idx]
		var base_e := 1.45 if l.get_parent().name.contains("Hold") else (lerpf(0.95, 1.85, night) if has_curse_glow else lerpf(0.35, 1.35, night))
		l.light_energy = base_e * flicker * phase_light_scale

	# Rising hold bilge water & ocean hull mask flood update.
	if _hold_water_mesh != null:
		_hold_water_mesh.visible = water_level > 0.015 and not _using_lod
		if _hold_water_mesh.visible and _hold_water_mat != null:
			_hold_water_mat.set_shader_parameter(&"water_level", water_level)
			_hold_water_mat.set_shader_parameter(&"slosh_time", _slosh_time)
			_hold_water_mat.set_shader_parameter(&"slosh_tilt", _slosh_tilt)
			var dist_amt := clampf(0.18 + open_hole_count() * 0.25 + angular_velocity.length() * 0.6, 0.15, 1.0)
			_hold_water_mat.set_shader_parameter(&"disturbance", dist_amt)

	if _mask_registered and Ocean.current != null and Ocean.current.has_method(&"update_hull_mask"):
		# HoldWater renders interior flooding cleanly; keep external ocean carved out until foundering.
		var mask_flood := 1.0 if is_sinking else clampf((water_level - 0.78) / 0.22, 0.0, 1.0)
		Ocean.current.call(&"update_hull_mask", self, mask_flood)


func _aim_ropes() -> void:
	for pair in _rope_pairs:
		var rope: Node3D = pair[0]
		var a_node: Node3D = pair[1]
		var b_node: Node3D = pair[2]
		var a := a_node.global_position
		var b := b_node.global_position
		var d := b - a
		var len_sq := d.length_squared()
		if len_sq < 0.0001:
			continue
		var dir := d / sqrt(len_sq)
		var ref_up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
		var x := ref_up.cross(dir).normalized()
		var y := dir.cross(x)
		rope.global_transform = Transform3D(Basis(x, y, d), a)


func _update_wake(delta: float) -> void:
	var spd := Vector2(linear_velocity.x, linear_velocity.z).length()
	var phased_present := visible and _spectral_phase > 0.15
	var spray_on := phased_present and (not is_sinking) and (spd > 2.4) and (_last_submerged_frac > 0.12)
	var spray_ratio := clampf((spd - 2.0) / 5.5, 0.15, 1.0)
	for spray: GPUParticles3D in [_bow_spray_port, _bow_spray_starboard]:
		if spray != null:
			spray.emitting = spray_on
			spray.amount_ratio = spray_ratio
	if Ocean.current == null or not phased_present:
		return
	var is_brig := (ship_class == &"brigantine")
	var len_sc := (1.32 if is_brig else 1.0) * hull_scale
	var beam_sc := (1.24 if is_brig else 1.0) * hull_scale
	if is_sinking:
		if enable_effects and global_position.y > -5.5:
			_sink_foam_accum += delta
			if _sink_foam_accum >= 0.18:
				_sink_foam_accum = 0.0
				var xf_sink := global_transform
				var pulse := 0.5 + 0.5 * sin(_sink_timer * 5.2)
				var wobble := sin(_sink_timer * 7.1) * 1.15 * beam_sc
				# Boiling white sinking-bubble foam rings around bow, midship, and stern.
				Ocean.current.add_foam(xf_sink * Vector3(wobble * 0.45, 0.0, -4.8 * len_sc), lerpf(4.2, 4.9, pulse), 0.92)
				Ocean.current.add_foam(xf_sink * Vector3(-wobble * 0.55, 0.0, 0.2 * len_sc), lerpf(4.8, 5.5, 1.0 - pulse), 0.92)
				Ocean.current.add_foam(xf_sink * Vector3(wobble * 0.35, 0.0, 5.0 * len_sc), lerpf(4.3, 5.0, pulse), 0.92)
		return
	if _anchor_swing_timer > 0.0:
		_stamp_anchor_turn_foam(clampf(_anchor_swing_timer / 1.95, 0.15, 0.85))
	if spd < 0.35:
		# Subtle waterline collar foam even while gently bobbing at anchor.
		Ocean.current.add_foam(global_transform * Vector3(0.0, 0.0, -5.6 * len_sc), 1.4 * beam_sc, 0.14)
		return
	var s_norm := clampf(spd / 7.5, 0.0, 1.2)
	var xf := global_transform
	# Foaming bow wave & diverging bow shoulders (scaled cleanly for Sloop & Brigantine).
	Ocean.current.add_foam(xf * Vector3(0.0, 0.0, -6.2 * len_sc), 1.65 * beam_sc, 0.45 * s_norm)
	Ocean.current.add_foam(xf * Vector3(-1.85 * beam_sc, 0.0, -3.9 * len_sc), 1.45 * beam_sc, 0.38 * s_norm)
	Ocean.current.add_foam(xf * Vector3(1.85 * beam_sc, 0.0, -3.9 * len_sc), 1.45 * beam_sc, 0.38 * s_norm)
	# Mid-hull wash & churned stern wake seated behind rudder.
	Ocean.current.add_foam(xf * Vector3(-2.1 * beam_sc, 0.0, 0.8 * len_sc), 1.3 * beam_sc, 0.25 * s_norm)
	Ocean.current.add_foam(xf * Vector3(2.1 * beam_sc, 0.0, 0.8 * len_sc), 1.3 * beam_sc, 0.25 * s_norm)
	Ocean.current.add_foam(xf * Vector3(0.0, 0.0, 6.7 * len_sc), 2.5 * beam_sc, 0.56 * s_norm)


func _stamp_anchor_turn_foam(strength: float) -> void:
	if Ocean.current == null or strength <= 0.01:
		return
	var is_brig := (ship_class == &"brigantine")
	var len_sc := (1.32 if is_brig else 1.0) * hull_scale
	var beam_sc := (1.24 if is_brig else 1.0) * hull_scale
	var xf := global_transform
	# Outward drifting flank sweeps a broad curved arc of churning white foam!
	var out_side := -_anchor_swing_dir if absf(_anchor_swing_dir) > 0.1 else 1.0
	Ocean.current.add_foam(_anchor_world_pos(), 2.2 * beam_sc, 0.72 * strength)
	Ocean.current.add_foam(xf * Vector3(out_side * 2.2 * beam_sc, 0.0, 1.2 * len_sc), 2.4 * beam_sc, 0.65 * strength)
	Ocean.current.add_foam(xf * Vector3(out_side * 2.8 * beam_sc, 0.0, 4.0 * len_sc), 3.0 * beam_sc, 0.82 * strength)
	Ocean.current.add_foam(xf * Vector3(out_side * 2.0 * beam_sc, 0.0, 6.6 * len_sc), 3.4 * beam_sc, 0.88 * strength)


func _anchor_world_pos() -> Vector3:
	if _anchor_node != null:
		return _anchor_node.global_position
	return global_transform * (Vector3(1.6, 0.0, -5.1) * hull_scale)


# ------------------------------------------------------------------ replication

## Snapshot of ship physics, controls, damage, and cannon pose for co-op clients.
func get_net_state() -> Dictionary:
	var hole_bits: Array[int] = []
	for h in holes:
		var code := 0
		if bool(h["breached"]):
			code = 2 if bool(h["patched"]) else 1
		hole_bits.append(code)
	var cannon_state := {}
	for side: StringName in _cannons:
		var c: Dictionary = _cannons[side]
		cannon_state[String(side)] = [float(c["yaw"]), float(c["pitch"]), float(c["recoil"])]
	return {
		"origin": global_transform.origin,
		"quat": global_transform.basis.get_rotation_quaternion(),
		"lin_vel": linear_velocity,
		"ang_vel": angular_velocity,
		"helm": helm,
		"helm_target": helm_target,
		"sail_set": sail_set,
		"sail_target": sail_target,
		"sail_trim": sail_trim,
		"trim_target": trim_target,
		"anchor_down": anchor_down,
		"anchor_progress": anchor_progress,
		"water_level": water_level,
		"is_sinking": is_sinking,
		"holes": hole_bits,
		"cannons": cannon_state,
		"cannonballs": cannonballs_remaining,
		"planks": planks_remaining,
		"emblem_mode": get_emblem_mode(),
		"sail_tint": _livery_sail_tint,
		"flag_tint": _livery_flag_tint,
		"hull_tint": _livery_hull_tint,
		"glow_accent": _livery_glow_accent,
		"ship_name": ship_name,
	}


## Apply a host snapshot (called on clients, or in tests for state restoration).
func apply_net_state(state: Dictionary) -> void:
	if state.has("origin") and state.has("quat"):
		var q: Quaternion = state["quat"]
		var xf := Transform3D(Basis(q).orthonormalized(), state["origin"] as Vector3)
		_net_target_xform = xf
		if not _net_has_state or Net.is_host() or global_position.distance_to(xf.origin) > 8.0:
			global_transform = xf
		_net_has_state = true
	if state.has("lin_vel"):
		linear_velocity = state["lin_vel"]
	if state.has("ang_vel"):
		angular_velocity = state["ang_vel"]
	helm = float(state.get("helm", helm))
	helm_target = float(state.get("helm_target", helm_target))
	sail_set = float(state.get("sail_set", sail_set))
	sail_target = float(state.get("sail_target", sail_target))
	sail_trim = float(state.get("sail_trim", sail_trim))
	trim_target = float(state.get("trim_target", trim_target))
	anchor_down = bool(state.get("anchor_down", anchor_down))
	anchor_progress = float(state.get("anchor_progress", anchor_progress))
	water_level = float(state.get("water_level", water_level))
	is_sinking = bool(state.get("is_sinking", is_sinking))
	cannonballs_remaining = int(state.get("cannonballs", cannonballs_remaining))
	planks_remaining = int(state.get("planks", planks_remaining))

	var hole_bits: Array = state.get("holes", [])
	for i in mini(hole_bits.size(), holes.size()):
		var code := int(hole_bits[i])
		var slot: Dictionary = holes[i]
		slot["breached"] = code > 0
		slot["patched"] = code == 2
		slot["severity"] = 1.0 if code == 1 else 0.0
		_sync_hole_visuals(slot)

	var cannon_state: Dictionary = state.get("cannons", {})
	for side_str: String in cannon_state:
		var side := StringName(side_str)
		if _cannons.has(side):
			var arr: Array = cannon_state[side_str]
			if arr.size() >= 3:
				_cannons[side]["yaw"] = float(arr[0])
				_cannons[side]["pitch"] = float(arr[1])
				_cannons[side]["recoil"] = float(arr[2])

	# Replicate full company livery only when any tint or emblem_mode differs (zero steady-state cost).
	if state.has("emblem_mode") or state.has("sail_tint") or state.has("flag_tint") \
			or state.has("hull_tint") or state.has("glow_accent"):
		var s_tint: Color = state.get("sail_tint", _livery_sail_tint) as Color
		var f_tint: Color = state.get("flag_tint", _livery_flag_tint) as Color
		var h_tint: Color = state.get("hull_tint", _livery_hull_tint) as Color
		var g_acc: Color = state.get("glow_accent", _livery_glow_accent) as Color
		var e_mode: int = int(state.get("emblem_mode", get_emblem_mode()))
		var livery_changed := e_mode != get_emblem_mode() \
			or not s_tint.is_equal_approx(_livery_sail_tint) \
			or not f_tint.is_equal_approx(_livery_flag_tint) \
			or not h_tint.is_equal_approx(_livery_hull_tint) \
			or not g_acc.is_equal_approx(_livery_glow_accent)
		if livery_changed:
			apply_livery(s_tint, f_tint, g_acc, h_tint, e_mode)

	# Replicate custom ship_name only when non-empty and changed (avoids needless ShipNameplate repaints).
	if state.has("ship_name"):
		var incoming_name := String(state["ship_name"]).strip_edges()
		if incoming_name != "" and incoming_name != ship_name:
			set_ship_name(incoming_name)
