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
signal hole_patched(slot_index: int)
signal bailed(amount: float)
signal sunk
signal cannon_fired(side: StringName, cannonball: Cannonball)
signal bell_rung(pawn: Node)
signal supplies_taken(pawn: Node)

const SLOOP_SCENE: PackedScene = preload("res://assets/generated/ship/sloop.glb")
const SLOOP_LOD_SCENE: PackedScene = preload("res://assets/generated/ship/sloop_lod.glb")
const SAIL_WIND_SHADER: Shader = preload("res://src/ship/sail_wind.gdshader")
const HOLD_WATER_SHADER: Shader = preload("res://src/ship/hold_water.gdshader")

## Collision layer 2 (ships). Mask deliberately excludes layer 3 (pawns) so
## CharacterBody3D pawns never shove the hull (docs/ARCHITECTURE.md).
const LAYER_SHIP := 1 << 1
const MASK_SHIP := 1 | (1 << 1)

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
## Optional faction tag (&"player", &"drowned", &"ghost", &"corsair").
@export var faction: StringName = &"player"
## Optional starting anchor state.
@export var start_anchored: bool = false
## Build lights and particle emitters (set false only if a micro-benchmark wants bare physics).
@export var enable_effects: bool = true

# ------------------------------------------------------------------ internal refs

var _hull_mass: float = BASE_MASS
var _probe_scale: Vector3 = Vector3.ONE
var _class_thrust_mult: float = 1.0

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
var _sail_time: float = 0.0
var _slosh_time: float = 0.0
var _slosh_tilt: Vector2 = Vector2.ZERO
var _last_wind_catch: float = 0.0
var _last_submerged_frac: float = 0.0
var _anchor_swing_dir: float = 0.0
var _anchor_swing_timer: float = 0.0

# Audio pacing timers
var _creak_cooldown: float = 0.0
var _flap_cooldown: float = 0.0
var _slosh_cooldown: float = 0.0
var _wheel_sfx_accum: float = 0.0
var _rope_sfx_accum: float = 0.0
var _capstan_sfx_accum: float = 0.0
var _was_anchor_submerged: bool = false
var _was_drawing_wind: bool = false

# Client interpolation target state
var _net_target_xform: Transform3D = Transform3D.IDENTITY
var _net_has_state: bool = false
var _livery_sail_tint: Color = Color.WHITE
var _livery_flag_tint: Color = Color.WHITE
var _livery_glow_accent: Color = Color.BLACK
var _livery_hull_tint: Color = Color.WHITE
var _effective_glow_accent: Color = Color.BLACK
var _hull_mats_duplicated: bool = false
var _hull_mat_entries: Array[Dictionary] = []

var _bow_spray_port: GPUParticles3D = null
var _bow_spray_starboard: GPUParticles3D = null
var _spray_tex: GradientTexture2D = null


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
	add_to_group(&"ship")


func _ready() -> void:
	collision_layer = LAYER_SHIP
	collision_mask = MASK_SHIP
	if ship_class == &"brigantine":
		_hull_mass = 13500.0
		_probe_scale = Vector3(1.22, 1.05, 1.32)
		_class_thrust_mult = 1.68
		mass = _hull_mass
		inertia = Vector3(245000.0, 315000.0, 74000.0)
	else:
		_hull_mass = BASE_MASS
		_probe_scale = Vector3.ONE
		_class_thrust_mult = 1.0
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
	_build_deck_extras()
	if enable_effects:
		_build_bow_spray()
	_setup_sail_shaders()
	_setup_lights_and_glass()
	_apply_current_livery()
	_cache_ropes()
	_register_ocean_mask()
	_last_wind_catch = wind_catch()
	_update_visuals(0.0)


func _exit_tree() -> void:
	_unregister_ocean_mask()


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
	add_child(_model)

	_lod_model = lod_scene.instantiate() as Node3D
	_lod_model.name = "BrigantineLOD" if ship_class == &"brigantine" else "SloopLOD"
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
		var shape := ConvexPolygonShape3D.new()
		shape.points = faces
		var cs := CollisionShape3D.new()
		cs.name = "Col_" + String(mi.name)
		cs.shape = shape
		cs.transform = _local_to_ship(mi)
		add_child(cs)


func _build_stations() -> void:
	var specs: Array[Array] = [
		["Station_Helm", &"helm", "Take the helm", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.72)), Vector3(0.0, 0.95, 0.0), 0.65, &""],
		["Station_SailLength", &"sail_length", "Raise / lower sail", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.58, 0.0, 0.0)), Vector3(0.0, 0.85, 0.0), 0.6, &""],
		["Station_SailAngle", &"sail_angle", "Trim sail angle", Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-0.58, 0.0, 0.0)), Vector3(0.0, 0.85, 0.0), 0.6, &""],
		["Station_Anchor", &"anchor", "Use capstan (anchor)", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.95)), Vector3(0.0, 0.85, 0.0), 0.7, &""],
		["Station_CannonPort", &"cannon", "Man port cannon", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 1.05)), Vector3(0.0, 0.85, 0.2), 0.7, &"port"],
		["Station_CannonStarboard", &"cannon", "Man starboard cannon", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 1.05)), Vector3(0.0, 0.85, 0.2), 0.7, &"starboard"],
		["Station_CannonPortAft", &"cannon", "Man aft port cannon", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 1.05)), Vector3(0.0, 0.85, 0.2), 0.7, &"port_aft"],
		["Station_CannonStarboardAft", &"cannon", "Man aft starboard cannon", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 1.05)), Vector3(0.0, 0.85, 0.2), 0.7, &"starboard_aft"],
		["Station_MapTable", &"map_table", "Inspect map table", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.82)), Vector3(0.0, 0.9, 0.0), 0.7, &""],
		["Station_Bilge", &"bilge", "Bail bilge water", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.35)), Vector3(0.0, 0.75, 0.0), 0.7, &""],
	]
	for spec in specs:
		var marker := _n(String(spec[0]))
		if marker == null:
			continue
		var st := Station.new()
		st.name = String(spec[0]) + "_Node"
		st.transform = _local_to_ship(marker)
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
		lad.height = 2.75
		lad.width = 0.85
		lad.standoff = 0.42
		lad.reach_below = 1.6
		lad.exit_offset = Vector3(0.0, 0.1, -0.82)
		# Place foot 1.6 m below the waterline marker so the top aligns with the main deck (y ~= 1.15).
		lad.transform = Transform3D(Basis(Vector3.UP, float(spec[2])), Vector3(lp.x, lp.y - 1.6, lp.z))
		add_child(lad)


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
	hold_box.size = Vector3(3.7, 2.05, 8.6)
	var cs_hold := CollisionShape3D.new()
	cs_hold.name = "HoldBox"
	cs_hold.shape = hold_box
	cs_hold.position = Vector3(0.0, 0.12, 0.2)
	shelter_area.add_child(cs_hold)

	var cabin_box := BoxShape3D.new()
	cabin_box.size = Vector3(3.4, 2.8, 3.3)
	var cs_cabin := CollisionShape3D.new()
	cs_cabin.name = "SternCabinBox"
	cs_cabin.shape = cabin_box
	cs_cabin.position = Vector3(0.0, 0.55, 4.6)
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
			hole_basis = xf.basis
		elif panel != null:
			var xf2 := _local_to_ship(panel)
			local_pos = xf2.origin
			hole_basis = xf2.basis

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
	var x_off := 1.75 if is_brig else 1.35
	var y_off := 0.45 if is_brig else 0.35
	var z_off := -7.6 if is_brig else -5.4
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
	_hold_water_mesh.position = Vector3(0.0, 0.0, 0.75)
	_hold_water_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hold_water_mesh.visible = false
	add_child(_hold_water_mesh)


func _build_deck_extras() -> void:
	# Ship's bell interactable.
	if _bell != null:
		var bell_it := Interactable.create("Ring ship's bell", 0.55)
		bell_it.name = "BellInteractable"
		bell_it.position = _local_to_ship(_bell).origin
		bell_it.interacted.connect(func(pawn: Node) -> void:
			ring_bell(pawn)
		)
		add_child(bell_it)

	# One-press supply refill barrel interactable on deck (DESIGN.md: "Tedium cuts").
	var supply_pos := Vector3(1.15, 1.55, -2.55)
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
		l.omni_range = 7.5 if is_hold else 6.0
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
	if anchor_down == down:
		return
	anchor_down = down
	if down:
		Audio.play_sfx(&"anchor_drop", _anchor_world_pos())
		if forward_speed() > 1.8:
			_anchor_swing_dir = 1.0 if helm >= 0.0 else -1.0
			_anchor_swing_timer = 2.6


## Forward speed along the ship's -Z bow axis in m/s (negative = astern).
func forward_speed() -> float:
	var fwd := -global_basis.z
	return linear_velocity.dot(fwd)


## Horizontal speed in knots (1 m/s ~= 1.94384 knots).
func speed_knots() -> float:
	var hv := Vector2(linear_velocity.x, linear_velocity.z).length()
	return hv * 1.94384


## Horizontal apparent wind experienced by the ship in world space (m/s).
func apparent_wind() -> Vector3:
	var w := Weather.wind_vector()
	return Vector3(w.x - linear_velocity.x, 0.0, w.z - linear_velocity.z)


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


## Customize sail/flag/hull colours and optional spectral glow (player cosmetics, Drowned/Ghost/Corsair ships).
func apply_livery(
		sail_tint: Color,
		flag_tint: Color,
		glow_accent: Color = Color.BLACK,
		hull_tint: Color = Color.WHITE
) -> void:
	_livery_sail_tint = sail_tint
	_livery_flag_tint = flag_tint
	_livery_glow_accent = glow_accent
	_livery_hull_tint = hull_tint
	if is_node_ready():
		_apply_current_livery()


func _apply_current_livery() -> void:
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
		elif faction == &"ghost":
			eff_hull = Color(0.42, 0.86, 0.84)
			eff_paint = Color(0.48, 0.92, 0.90)
			eff_rough_add = 0.04
			eff_hull_emit = Color(0.14, 0.88, 0.82)
			eff_hull_emit_energy = 0.35
			if eff_glow.get_luminance() <= 0.01:
				eff_glow = Color(0.22, 0.98, 0.84)
		elif faction == &"corsair":
			eff_hull = Color(0.58, 0.46, 0.44)
			eff_paint = Color(0.64, 0.42, 0.38)
			eff_rough_add = 0.08
		else:
			eff_paint = Color.WHITE

	_effective_glow_accent = eff_glow
	var glow_mag := eff_glow.get_luminance()
	var sail_glow_strength := 0.0
	if glow_mag > 0.01:
		# Keep Drowned sails dark & weathered with a faint eerie sheen; let Ghost sails glow brightly.
		sail_glow_strength = 0.08 if faction == &"drowned" else clampf(glow_mag * 0.78, 0.14, 0.82)

	for sm in _sail_mats:
		sm.set_shader_parameter(&"albedo_tint", _livery_sail_tint)
		if glow_mag > 0.01:
			sm.set_shader_parameter(&"emission_tint", eff_glow)
			sm.set_shader_parameter(&"emission_strength", sail_glow_strength)
		else:
			var is_back := float(sm.get_shader_parameter(&"is_back_face")) > 0.5
			sm.set_shader_parameter(&"emission_tint", Color(1.0, 0.86, 0.6))
			sm.set_shader_parameter(&"emission_strength", 0.08 if is_back else 0.0)
	for fmat in _flag_mats:
		fmat.set_shader_parameter(&"albedo_tint", _livery_flag_tint)
		if glow_mag > 0.01:
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

	var need_hull_livery := (
		eff_hull != Color.WHITE
		or glow_mag > 0.01
		or _livery_sail_tint != Color.WHITE
		or _livery_flag_tint != Color.WHITE
		or _hull_mats_duplicated
	)
	if not need_hull_livery:
		return

	_ensure_hull_livery_mats()
	for entry in _hull_mat_entries:
		var mat: BaseMaterial3D = entry["mat"]
		var kind: StringName = entry["kind"]
		var orig_albedo: Color = entry["orig_albedo"]
		var orig_rough: float = float(entry["orig_rough"])
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
			&"cloth":
				mat.albedo_color = orig_albedo * eff_hull.lerp(Color.WHITE, 0.10)
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
	var mat_cache: Dictionary = {}  # orig BaseMaterial3D -> duplicated per-ship BaseMaterial3D
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
				var dup: BaseMaterial3D
				if mat_cache.has(orig):
					dup = mat_cache[orig] as BaseMaterial3D
				else:
					dup = orig.duplicate() as BaseMaterial3D
					mat_cache[orig] = dup
					_hull_mat_entries.append({
						"mat": dup,
						"kind": kind,
						"orig_albedo": orig.albedo_color,
						"orig_rough": orig.roughness,
						"orig_emit_on": orig.emission_enabled,
						"orig_emit": orig.emission,
						"orig_emit_e": orig.emission_energy_multiplier,
					})
				mi.set_surface_override_material(si, dup)


static func _classify_livery_material(mat_name: String, is_lod: bool) -> StringName:
	if mat_name == "mat_wood" or mat_name == "mat_hull_wood":
		return &"wood"
	if mat_name == "mat_paint":
		return &"paint"
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
	return &""


## Ring the ship's bell (swing + cue).
func ring_bell(pawn: Node = null) -> void:
	_bell_vel += 7.5
	Audio.play_sfx(&"parry_ring", _bell.global_position if _bell != null else global_position, -4.0, 0.03)
	bell_rung.emit(pawn)


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
	var pos := global_transform * (slot["local_pos"] as Vector3)
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
	var muzzle_pos := aim_node.global_position + muzzle_dir * 1.15

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

	if enable_effects:
		_spawn_muzzle_flash(muzzle_pos, muzzle_dir)
	Audio.play_sfx(&"cannon_fire", muzzle_pos)
	cannon_fired.emit(side, ball)
	return ball


func _spawn_muzzle_flash(pos: Vector3, dir: Vector3) -> void:
	var host := get_parent()
	if host == null:
		return
	var p := GPUParticles3D.new()
	p.name = "CannonSmoke"
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = 22
	p.lifetime = 1.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var proc := ParticleProcessMaterial.new()
	proc.direction = dir
	proc.spread = 26.0
	proc.initial_velocity_min = 4.0
	proc.initial_velocity_max = 11.0
	proc.damping_min = 4.0
	proc.damping_max = 7.0
	proc.gravity = Vector3(0.0, 1.4, 0.0)
	proc.scale_min = 0.5
	proc.scale_max = 1.6
	p.process_material = proc

	var sphere := SphereMesh.new()
	sphere.radius = 0.32
	sphere.height = 0.64
	sphere.radial_segments = 7
	sphere.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.92, 0.88, 0.80, 0.72)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material = mat
	p.draw_pass_1 = sphere

	host.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


# ------------------------------------------------------------------ station driving

func _drive_station(st: Station, axis: Vector2, primary: bool, secondary: bool, delta: float) -> void:
	match st.kind:
		&"helm":
			if absf(axis.x) > 0.05:
				set_helm_target(helm_target + axis.x * 1.15 * delta)
			elif secondary:
				# Secondary gently centres the wheel.
				set_helm_target(move_toward(helm_target, 0.0, 1.5 * delta))
		&"sail_length":
			var change := axis.y
			if primary and absf(change) < 0.05:
				change = 1.0
			elif secondary and absf(change) < 0.05:
				change = -1.0
			if absf(change) > 0.05:
				set_sail_target(sail_target + change * 0.48 * delta)
				_rope_sfx_accum += absf(change) * delta
				if _rope_sfx_accum > 0.55:
					_rope_sfx_accum = 0.0
					Audio.play_sfx(&"rope_creak", st.global_position, -3.0)
		&"sail_angle":
			if absf(axis.x) > 0.05:
				set_trim_target(trim_target + axis.x * 0.95 * delta)
				_rope_sfx_accum += absf(axis.x) * delta
				if _rope_sfx_accum > 0.55:
					_rope_sfx_accum = 0.0
					Audio.play_sfx(&"rope_creak", st.global_position, -3.0)
		&"anchor":
			if primary or axis.y < -0.3:
				set_anchor(true)
			elif secondary or axis.y > 0.3:
				set_anchor(false)
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
	helm = move_toward(helm, helm_target, 0.95 * delta)
	if absf(helm - prev_helm) > 0.0005:
		_wheel_sfx_accum += absf(helm - prev_helm)
		if _wheel_sfx_accum > 0.32:
			_wheel_sfx_accum = 0.0
			var st := get_station(&"helm")
			Audio.play_sfx(&"wheel_creak", st.global_position if st != null else global_position, -4.0)

	var prev_sail := sail_set
	sail_set = move_toward(sail_set, sail_target, 0.45 * delta)
	sail_trim = move_toward(sail_trim, trim_target, 0.85 * delta)

	var target_anc := 1.0 if anchor_down else 0.0
	var anc_rate := 0.72 if anchor_down else 0.30
	var prev_anc := anchor_progress
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

	if _anchor_swing_timer > 0.0:
		_anchor_swing_timer = maxf(0.0, _anchor_swing_timer - delta)

	# Sail fill cue when catching wind strongly after raising sail.
	_last_wind_catch = wind_catch()
	var drawing := sail_set > 0.35 and _last_wind_catch > 0.65
	if drawing and not _was_drawing_wind and prev_sail <= sail_set:
		Audio.play_sfx(&"sail_fill", global_position + Vector3.UP * 6.0, -3.0)
	_was_drawing_wind = drawing


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
			# One deep hole floods the sloop in roughly ~45–55 s; three holes in ~15–20 s.
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

	# 1. Multi-point buoyancy & per-probe damping (using Godot 4.8 get_velocity_at_position).
	const PROBE_SPAN := 1.15
	const BUOY_GAIN := 1.98
	for entry in BUOYANCY_PROBES:
		var local_p: Vector3 = (entry[0] as Vector3) * _probe_scale
		var w: float = entry[1]
		var world_p := xf * local_p
		var sea_y := Sea.height(world_p.x, world_p.z)
		var sub := sea_y - world_p.y
		if sub <= 0.0:
			continue
		var frac := clampf(sub / PROBE_SPAN, 0.0, 1.85)
		var damp_frac := minf(frac, 1.0)
		sub_accum += w * damp_frac

		var buoy_f := _hull_mass * GRAVITY * BUOY_GAIN * w * frac * sink_buoy
		var v_p := get_velocity_at_position(world_p)
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
	if _last_submerged_frac > 0.04:
		var wet := lerpf(0.3, 1.0, _last_submerged_frac)
		var v_loc := b.inverse() * linear_velocity
		var flood_drag := 1.0 + water_level * 0.55
		var f_z := -(v_loc.z * 260.0 + v_loc.z * absf(v_loc.z) * 162.0) * flood_drag * mass_ratio
		var f_x := -(v_loc.x * 6800.0 + v_loc.x * absf(v_loc.x) * 2900.0) * mass_ratio
		var f_y := -v_loc.y * 5200.0 * mass_ratio
		apply_central_force((b * Vector3(f_x, f_y, f_z)) * wet)

	# 4. Sail aerodynamics & gust heel (disabled once sinking).
	if not is_sinking and sail_set > 0.01:
		var aw := apparent_wind()
		var wind_spd := lerpf(Weather.wind_vector().length(), aw.length(), 0.25)
		var wind_factor := clampf(wind_spd / 8.0, 0.55, 1.75)
		var catch := _last_wind_catch
		# Believable, not realistic: full trim screams; head-to-wind still creeps slowly.
		var min_headway := 0.16 * close_hauled_modifier
		var drive_coeff := lerpf(min_headway, 1.0, catch)
		var flood_slow := lerpf(1.0, 0.65, water_level)
		var thrust := sail_set * wind_factor * drive_coeff * 17500.0 * _class_thrust_mult * speed_modifier * flood_slow
		var fwd_horiz := Vector3(-b.z.x, 0.0, -b.z.z)
		if fwd_horiz.length_squared() > 0.001:
			apply_central_force(fwd_horiz.normalized() * thrust)

		# Beam-wind heel torque about ship Z axis.
		var aw_local := b.inverse() * aw
		var side_wind := clampf(aw_local.x / 12.0, -1.6, 1.6)
		apply_torque(b.z * (-side_wind * sail_set * 16500.0 * mass_ratio))

	# 5. Rudder torque (positive helm -> starboard turn -> negative Y torque).
	if not is_sinking and _last_submerged_frac > 0.05:
		var fwd := forward_speed()
		var dir_sign := 1.0 if fwd >= -0.35 else -1.0
		var speed_auth := clampf(absf(fwd) / 4.2, 0.0, 1.45)
		var low_speed_auth := 0.30 * (1.0 - anchor_progress)
		var turn_torque := -helm * dir_sign * (speed_auth + low_speed_auth) * 38000.0 * (1.18 if ship_class == &"brigantine" else 1.0) * speed_modifier
		apply_torque(Vector3.UP * turn_torque)

	# 6. Anchor drag and swinging stop.
	if anchor_progress > 0.65:
		var hold_frac := clampf((anchor_progress - 0.65) / 0.35, 0.0, 1.0)
		var hv := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
		apply_central_force(-hv * (18500.0 * hold_frac))
		if _anchor_swing_timer > 0.0 and hv.length() > 0.45:
			var swing := -_anchor_swing_dir * clampf(hv.length() / 5.0, 0.2, 1.2) * 34000.0 * hold_frac
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
	_update_wake()


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


func _update_visuals(delta: float) -> void:
	_sail_time += delta
	_slosh_time += delta

	# Wheel & rudder.
	if _wheel != null:
		_wheel.rotation.z = -helm * TAU * 1.75
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

	# Ship's bell damped pendulum.
	if _bell != null and (absf(_bell_swing) > 0.001 or absf(_bell_vel) > 0.001):
		_bell_vel += (-_bell_swing * 36.0 - _bell_vel * 2.4) * delta
		_bell_swing = clampf(_bell_swing + _bell_vel * delta, -0.7, 0.7)
		_bell.rotation.x = _bell_swing

	# Running rigging ropes (SHIP_ART.md contract).
	if not _using_lod:
		_aim_ropes()

	# Night cabin glass glow & lantern flicker (cursed vessels keep eerie glow even by day).
	var night := 1.0 - Weather.daylight()
	var has_curse_glow := _effective_glow_accent.get_luminance() > 0.01
	var window_em := lerpf(1.45, 2.8, night) if has_curse_glow else lerpf(0.22, 2.2, night)
	for wm in _window_mats:
		wm.emission_energy_multiplier = window_em
	var flicker := 0.94 + 0.06 * sin(_sail_time * 9.3) * cos(_sail_time * 6.1)
	for idx in _lantern_lights.size():
		var l := _lantern_lights[idx]
		var base_e := 1.45 if l.get_parent().name.contains("Hold") else (lerpf(0.95, 1.85, night) if has_curse_glow else lerpf(0.35, 1.35, night))
		l.light_energy = base_e * flicker

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


func _update_wake() -> void:
	var spd := Vector2(linear_velocity.x, linear_velocity.z).length()
	var spray_on := (not is_sinking) and (spd > 2.4) and (_last_submerged_frac > 0.12)
	var spray_ratio := clampf((spd - 2.0) / 5.5, 0.15, 1.0)
	for spray: GPUParticles3D in [_bow_spray_port, _bow_spray_starboard]:
		if spray != null:
			spray.emitting = spray_on
			spray.amount_ratio = spray_ratio
	if Ocean.current == null or is_sinking:
		return
	var is_brig := (ship_class == &"brigantine")
	var len_sc := 1.32 if is_brig else 1.0
	var beam_sc := 1.24 if is_brig else 1.0
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


func _anchor_world_pos() -> Vector3:
	if _anchor_node != null:
		return _anchor_node.global_position
	return global_transform * Vector3(1.6, 0.0, -5.1)


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
