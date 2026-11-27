class_name Inventory
extends Node
## Held tool & weapon inventory, first-person viewmodel rig, third-person hand
## attachment, and tactile diegetic tool mechanics. Attach as a child of a `Pawn`.
##
## Works seamlessly alongside `PlayerController`, `CombatComponent`,
## `CharacterVisual`, `AnimationDriver`, `Ship`, `DigSite`, and `Audio`.

signal item_equipped(item_id: StringName)
signal spyglass_zoom_changed(amount: float)
signal lantern_toggled(on: bool)
signal lantern_signaled(world_pos: Vector3)
signal tipsy_changed(amount: float)
signal sighting_updated(label: String, distance_m: float)
signal spyglass_callout_made(label: String, distance_m: float, bearing: String, target_pos: Vector3)
signal bucket_changed(full: bool)
signal shanty_playing_changed(playing: bool)
signal shanty_instrument_changed(instrument: StringName)
signal weapon_loadout_changed(melee_id: StringName, ranged_id: StringName)
signal compass_pace_counted(paces: int, heading_str: String)
signal compass_mode_changed(pin_mode: bool)
signal grog_toast_raised()
signal speaking_trumpet_hailed(origin: Vector3, radius: float, crew_acked: int)

const DEFAULT_SLOTS: Array[StringName] = [
	&"cutlass",
	&"pistol",
	&"compass",
	&"spyglass",
	&"lantern",
	&"map",
	&"shovel",
	&"bucket",
	&"planks",
	&"tankard",
	&"instrument",
]

const VALID_MELEE_WEAPONS: Array[StringName] = [&"cutlass", &"boarding_axe"]
const VALID_RANGED_WEAPONS: Array[StringName] = [&"pistol", &"blunderbuss"]
const SHANTY_INSTRUMENTS: Array[StringName] = [&"concertina", &"hurdy_gurdy", &"whistle"]
const SHANTY_INSTRUMENT_NAMES := {
	&"concertina": "Concertina",
	&"hurdy_gurdy": "Hurdy-Gurdy",
	&"whistle": "Bosun's Whistle",
}

const BASE_FOV := 80.0
const SPYGLASS_FOV := 18.0
const PISTOL_ADS_FOV := 62.0
const BLUNDERBUSS_ADS_FOV := 68.0
const HEAVY_HOLD_TIME := 0.30
const SHOVEL_REACH := 2.6
const PLANK_REACH := 3.8
const BAIL_AMOUNT := 0.16
const GROG_HEAL := 15.0
const SPYGLASS_CALLOUT_COOLDOWN := 2.5
const LANTERN_SIGNAL_COOLDOWN := 2.5
const COMPASS_PACE_METRES := 0.95
const GROG_TOAST_COOLDOWN := 4.0
const SPEAKING_TRUMPET_HAIL_RADIUS := 110.0
const SPEAKING_TRUMPET_COOLDOWN := 3.5
const SPEAKING_TRUMPET_DISPLAY_SECONDS := 0.85
const CUTLASS_GLEAM_DURATION := 0.42
const COMPASS_16: PackedStringArray = [
	"N", "NNE", "NE", "ENE",
	"E", "ESE", "SE", "SSE",
	"S", "SSW", "SW", "WSW",
	"W", "WNW", "NW", "NNW",
]

## First-person rest & secondary-raised poses relative to Camera3D:
## [rest_pos, rest_rot_deg, raise_pos, raise_rot_deg, scale].
const FP_POSES := {
	&"cutlass": [Vector3(0.30, -0.26, -0.50), Vector3(-14.0, 14.0, 10.0), Vector3(0.06, -0.16, -0.44), Vector3(-14.0, 64.0, 70.0), 0.86],
	&"boarding_axe": [Vector3(0.32, -0.29, -0.52), Vector3(-12.0, 12.0, 8.0), Vector3(0.05, -0.17, -0.44), Vector3(-10.0, 68.0, 74.0), 0.86],
	&"pistol": [Vector3(0.26, -0.23, -0.46), Vector3(2.0, 4.0, 0.0), Vector3(0.0, -0.145, -0.40), Vector3(0.0, 0.0, 0.0), 0.92],
	&"blunderbuss": [Vector3(0.24, -0.25, -0.50), Vector3(3.0, 6.0, -2.0), Vector3(0.0, -0.155, -0.44), Vector3(0.0, 0.0, 0.0), 0.90],
	&"compass": [Vector3(0.22, -0.21, -0.42), Vector3(26.0, -14.0, -8.0), Vector3(0.0, -0.16, -0.36), Vector3(56.0, 0.0, 0.0), 0.74],
	&"spyglass": [Vector3(0.20, -0.23, -0.46), Vector3(8.0, 16.0, -6.0), Vector3(0.0, -0.02, -0.24), Vector3(0.0, 0.0, 0.0), 0.95],
	&"lantern": [Vector3(0.32, 0.02, -0.50), Vector3(4.0, -10.0, -4.0), Vector3(0.18, 0.20, -0.56), Vector3(-8.0, -6.0, 2.0), 0.92],
	&"map": [Vector3(0.08, -0.26, -0.48), Vector3(-14.0, -8.0, 2.0), Vector3(0.0, -0.04, -0.40), Vector3(-4.0, 0.0, 0.0), 0.96],
	&"shovel": [Vector3(0.24, -0.28, -0.54), Vector3(-22.0, 14.0, 10.0), Vector3(0.18, -0.20, -0.50), Vector3(-34.0, 18.0, 16.0), 0.85],
	&"bucket": [Vector3(0.22, 0.02, -0.50), Vector3(8.0, -14.0, 4.0), Vector3(0.12, 0.06, -0.44), Vector3(20.0, -8.0, 0.0), 0.88],
	&"planks": [Vector3(0.22, -0.28, -0.50), Vector3(-10.0, -16.0, 8.0), Vector3(0.06, -0.16, -0.44), Vector3(-6.0, -10.0, 4.0), 0.86],
	&"tankard": [Vector3(0.26, -0.21, -0.42), Vector3(6.0, -14.0, 4.0), Vector3(0.05, -0.08, -0.30), Vector3(26.0, -8.0, -10.0), 0.95],
	&"instrument": [Vector3(0.0, -0.25, -0.44), Vector3(14.0, 0.0, 0.0), Vector3(0.0, -0.16, -0.38), Vector3(6.0, 0.0, 0.0), 0.95],
	&"hurdy_gurdy": [Vector3(0.03, -0.27, -0.48), Vector3(12.0, -14.0, 4.0), Vector3(0.01, -0.18, -0.42), Vector3(6.0, -8.0, 2.0), 0.92],
	&"whistle": [Vector3(0.14, -0.21, -0.40), Vector3(8.0, -12.0, 6.0), Vector3(0.02, -0.11, -0.30), Vector3(-4.0, 0.0, 0.0), 0.95],
	&"speaking_trumpet": [Vector3(0.20, -0.21, -0.40), Vector3(8.0, -10.0, 4.0), Vector3(0.0, -0.10, -0.28), Vector3(-3.0, 0.0, 0.0), 0.92],
}

## Ship/dinghy station kinds that display sculpted dynamic first-person action hands.
const ACTION_HAND_STATIONS: Array[StringName] = [
	&"helm",
	&"anchor",
	&"sail_length",
	&"sail_angle",
	&"bilge",
	&"rowboat_oars",
]

## Ordered tool/weapon slots in the player's belt.
var slots: Array[StringName] = DEFAULT_SLOTS.duplicate()
var active_index: int = 0
var active_item: StringName = &"cutlass"
## Selected armory weapons mapped to the melee (&"cutlass") and ranged (&"pistol") slots.
var melee_weapon: StringName = &"cutlass"
var ranged_weapon: StringName = &"pistol"

## Read keyboard/mouse input directly. Set false for AI or scripted showcases/tests.
@export var input_enabled: bool = true

var pawn: Pawn = null
var player_controller: PlayerController = null
var combat: CombatComponent = null
var visual: CharacterVisual = null
var anim_driver: AnimationDriver = null
var map_table: MapTableView = null

var viewmodel_root: Node3D = null
var fp_tool_node: Node3D = null
var fp_action_hands: Node3D = null
var tp_mount: Node3D = null
var tp_tool_node: Node3D = null

## Live tool states.
var lantern_lit: bool = true
var bucket_full: bool = false
var compass_paces: int = 0
var compass_pin_mode: bool = false
var spyglass_zoom: float = 0.0
var spyglass_zoomed: bool:
	get:
		return active_item == &"spyglass" and (_secondary_held or spyglass_zoom > 0.45)
var spyglass_sighting: String = ""
var spyglass_sighting_dist: float = 0.0
var spyglass_sighting_bearing: String = ""
var tipsy: float = 0.0
var playing_shanty: bool = false
var shanty_instrument: StringName = &"concertina"

## Tool Variant sidegrade modifiers synced from Economy via `apply_tool_modifiers()`.
var tool_variant_id: StringName = &""
var spyglass_zoom_scale: float = 1.0
var sighting_range_scale: float = 1.0
var dig_power: int = 1
var bail_power_scale: float = 1.0

## Cached held parchment mode (&"treasure", &"riddle", &"bounty") & rendered ImageTexture.
var map_mode: StringName = &"treasure"
var map_island_name: String = "Cutlass Cay"
var map_contour: PackedVector2Array = PackedVector2Array()
var map_dig_local: Vector2 = Vector2(26.0, -18.0)
var map_island_radius: float = 120.0
var treasure_map_texture: ImageTexture = null

# Internal animation & input timers
var _secondary_held: bool = false
var _primary_was_down: bool = false
var _primary_hold_time: float = 0.0
var _heavy_fired_this_hold: bool = false
var _raise_blend: float = 0.0
var _equip_dip: float = 0.0
var _swing_timer: float = 0.0
var _swing_dur: float = 0.35
var _swing_kind: StringName = &""
var _reload_timer: float = 0.0
var _reload_dur: float = 1.45
var _bob_phase: float = 0.0
var _sprint_blend: float = 0.0
var _prev_look_yaw: float = 0.0
var _prev_look_pitch: float = 0.0
var _look_tracking_init: bool = false
var _sway_yaw: float = 0.0
var _sway_pitch: float = 0.0
var _ship_roll_lag: float = 0.0
var _lantern_pendulum_x: float = 0.0
var _lantern_pendulum_z: float = 0.0
var _lantern_pendulum_vx: float = 0.0
var _lantern_pendulum_vz: float = 0.0
var _clock: float = 0.0
var _compass_needle_angle: float = 0.0
var _compass_needle_vel: float = 0.0
var _compass_needle_init: bool = false
var _compass_prev_yaw: float = 0.0
var _compass_pace_accum: float = 0.0
var _compass_last_pos: Vector2 = Vector2.ZERO
var _compass_last_platform: PhysicsBody3D = null
var _compass_pace_active: bool = false
var _compass_pace_dip: float = 0.0
var _grog_toast_cd: float = 0.0
var _use_cooldown: float = 0.0
var _burp_timer: float = -1.0
var _sighting_timer: float = 0.0
var _spyglass_callout_cd: float = 0.0
var _spyglass_target_pos: Vector3 = Vector3.ZERO
var _was_zooming_spyglass: bool = false
var _lantern_flare_blend: float = 0.0
var _lantern_signal_flash: float = 0.0
var _lantern_signal_cd: float = 0.0
var _lantern_halo_energy: float = 0.0
var _cutlass_gleam_timer: float = 0.0
var _cutlass_gleam_peak: float = 0.0
var _barrel_smoke_timer: float = 0.0
var _barrel_smoke: GPUParticles3D = null
var _started_shanty: bool = false
var _shanty_phase: float = 0.0
var _last_shanty_audio_beat: float = -1.0
var _whistle_rot_deg: Vector3 = Vector3.ZERO
var _shanty_motes: GPUParticles3D = null
var _trumpet_cooldown: float = 0.0
var _trumpet_display_timer: float = 0.0
var _fp_trumpet_node: Node3D = null
var _trumpet_pulses: Array[Dictionary] = []
var _fp_action_left: Node3D = null
var _fp_action_right: Node3D = null
var _action_mode: StringName = &""
var _action_pose_init: bool = false
var _action_enter_blend: float = 0.0
var _action_prev_helm: float = 0.0
var _action_helm_vel: float = 0.0
var _action_helm_cycle: float = 0.0
var _action_prev_anchor: float = 0.0
var _action_anchor_phase: float = 0.0
var _action_anchor_effort: float = 0.0
var _action_prev_sail_set: float = 0.0
var _action_prev_sail_trim: float = 0.0
var _action_rope_phase: float = 0.0
var _action_rope_effort: float = 0.0
var _action_bilge_phase: float = 0.0
var _action_bilge_effort: float = 0.0
var _action_prev_water: float = 0.0
var _action_oar_phase_l: float = 0.0
var _action_oar_phase_r: float = 0.0
var _action_oar_effort_l: float = 0.0
var _action_oar_effort_r: float = 0.0
var _action_swim_phase: float = 0.0
var _action_swim_blend: float = 0.0
var _action_ladder_phase: float = 0.0
var _action_prev_ladder_y: float = 0.0
var _action_ladder_effort: float = 0.0
var _rng := RandomNumberGenerator.new()

# Statically cached zero-primitive sculpted particle ArrayMeshes (released when _active_inventories hits 0).
static var _active_inventories: int = 0
static var _clod_mesh: ArrayMesh = null
static var _clod_mat: StandardMaterial3D = null
static var _splash_drop_mesh: ArrayMesh = null
static var _splash_drop_mat: StandardMaterial3D = null
static var _trumpet_ring_mesh: ArrayMesh = null
static var _barrel_smoke_mesh: ArrayMesh = null
static var _barrel_smoke_shader: Shader = null
static var _barrel_smoke_mat: ShaderMaterial = null
static var _barrel_smoke_proc: ParticleProcessMaterial = null


func _init() -> void:
	# Run after PlayerController._process (0) so camera FOV and subtle tipsy sway layer cleanly.
	process_priority = 10


func _enter_tree() -> void:
	_active_inventories += 1


func _ready() -> void:
	_rng.randomize()
	_load_weapon_loadout_from_profile()
	_discover_siblings()
	if treasure_map_texture == null:
		treasure_map_texture = MapPainter.render_treasure_map(
			map_island_name, map_contour, map_dig_local, map_island_radius)
	equip(slots[active_index] if not slots.is_empty() else &"cutlass", true)


func _load_weapon_loadout_from_profile() -> void:
	if Game == null or Game.profile == null:
		return
	var saved_melee := StringName(String(Game.profile.data.get("melee_weapon", "cutlass")))
	if VALID_MELEE_WEAPONS.has(saved_melee):
		melee_weapon = saved_melee
	var saved_ranged := StringName(String(Game.profile.data.get("ranged_weapon", "pistol")))
	if VALID_RANGED_WEAPONS.has(saved_ranged):
		ranged_weapon = saved_ranged
	apply_tool_modifiers(Economy.get_ship_modifiers(Game.profile))


## Apply Tool Variant sidegrade modifiers from `Economy.get_ship_modifiers(profile)`.
func apply_tool_modifiers(mods: Dictionary) -> void:
	spyglass_zoom_scale = clampf(float(mods.get("spyglass_zoom_scale", 1.0)), 0.45, 1.5)
	sighting_range_scale = clampf(float(mods.get("sighting_range_scale", 1.0)), 0.5, 2.5)
	dig_power = clampi(roundi(float(mods.get("dig_power", 1.0))), 1, 3)
	bail_power_scale = clampf(float(mods.get("bail_power_scale", 1.0)), 0.5, 2.5)
	if mods.has("tool_variant_id"):
		tool_variant_id = StringName(String(mods.get("tool_variant_id", &"")))
	elif spyglass_zoom_scale < 0.90 or sighting_range_scale > 1.10:
		tool_variant_id = &"tool_far_spyglass"
	elif dig_power >= 2:
		tool_variant_id = &"tool_relic_shovel"
	elif bail_power_scale > 1.15:
		tool_variant_id = &"tool_heavy_bailer"
	else:
		tool_variant_id = &""
	_sync_tool_visual_state(fp_tool_node)
	_sync_tool_visual_state(tp_tool_node)
	if active_item == &"lantern":
		_tick_lantern_flicker(0.0)


func _exit_tree() -> void:
	_clear_speaking_trumpet_fx(false)
	_detach_captain_shanty_motes(false)
	_detach_barrel_smoke(false)
	_clear_tool_node_materials(fp_tool_node)
	_clear_tool_node_materials(tp_tool_node)
	if pawn != null and is_instance_valid(pawn):
		if pawn.station_changed.is_connected(_on_pawn_action_state_changed):
			pawn.station_changed.disconnect(_on_pawn_action_state_changed)
		if pawn.carried_changed.is_connected(_on_pawn_action_state_changed):
			pawn.carried_changed.disconnect(_on_pawn_action_state_changed)
		if pawn.mode_changed.is_connected(_on_pawn_mode_changed):
			pawn.mode_changed.disconnect(_on_pawn_mode_changed)
	if combat != null and is_instance_valid(combat):
		if combat.attack_started.is_connected(_on_combat_attack_started):
			combat.attack_started.disconnect(_on_combat_attack_started)
		if combat.parried.is_connected(_on_combat_parried):
			combat.parried.disconnect(_on_combat_parried)
		if combat.blocked.is_connected(_on_combat_blocked):
			combat.blocked.disconnect(_on_combat_blocked)
	if fp_action_hands != null and is_instance_valid(fp_action_hands):
		fp_action_hands.queue_free()
	fp_action_hands = null
	_fp_action_left = null
	_fp_action_right = null
	if playing_shanty:
		set_playing_shanty(false)
	treasure_map_texture = null
	map_table = null
	_lantern_halo_energy = 0.0
	_cutlass_gleam_timer = 0.0
	_cutlass_gleam_peak = 0.0
	_active_inventories = maxi(0, _active_inventories - 1)
	if _active_inventories == 0:
		_clod_mesh = null
		_clod_mat = null
		_splash_drop_mesh = null
		_splash_drop_mat = null
		_trumpet_ring_mesh = null
		if _barrel_smoke_mat != null:
			_barrel_smoke_mat.shader = null
		_barrel_smoke_mat = null
		_barrel_smoke_shader = null
		_barrel_smoke_mesh = null
		_barrel_smoke_proc = null


## Explicitly bind references if constructing dynamically before tree entry.
func bind(
	p_pawn: Pawn,
	p_controller: PlayerController = null,
	p_combat: CombatComponent = null,
	p_visual: CharacterVisual = null
) -> void:
	pawn = p_pawn
	player_controller = p_controller
	combat = p_combat
	visual = p_visual
	_connect_bindings()
	_ensure_mounts()
	_rebuild_tool_meshes()


func _discover_siblings() -> void:
	if pawn == null:
		pawn = get_parent() as Pawn
	if pawn == null:
		return
	if player_controller == null:
		for c in pawn.get_children():
			if c is PlayerController:
				player_controller = c as PlayerController
				break
	if combat == null:
		for c in pawn.get_children():
			if c is CombatComponent:
				combat = c as CombatComponent
				break
	if visual == null:
		var v := pawn.get_node_or_null(^"Visual/CharacterVisual") as CharacterVisual
		if v == null:
			var found := pawn.find_children("*", "CharacterVisual", true, false)
			if not found.is_empty():
				v = found[0] as CharacterVisual
		visual = v
	if anim_driver == null:
		anim_driver = pawn.get_node_or_null(^"Visual/AnimationDriver") as AnimationDriver
		if anim_driver == null:
			anim_driver = pawn.get_node_or_null(^"AnimationDriver") as AnimationDriver
	_connect_bindings()
	_ensure_mounts()


func _connect_bindings() -> void:
	if pawn != null and is_instance_valid(pawn):
		if not pawn.station_changed.is_connected(_on_pawn_action_state_changed):
			pawn.station_changed.connect(_on_pawn_action_state_changed)
		if not pawn.carried_changed.is_connected(_on_pawn_action_state_changed):
			pawn.carried_changed.connect(_on_pawn_action_state_changed)
		if not pawn.mode_changed.is_connected(_on_pawn_mode_changed):
			pawn.mode_changed.connect(_on_pawn_mode_changed)
	if combat != null:
		if not combat.attack_started.is_connected(_on_combat_attack_started):
			combat.attack_started.connect(_on_combat_attack_started)
		if not combat.parried.is_connected(_on_combat_parried):
			combat.parried.connect(_on_combat_parried)
		if not combat.blocked.is_connected(_on_combat_blocked):
			combat.blocked.connect(_on_combat_blocked)
	if visual != null and not visual.rig_changed.is_connected(_on_visual_rig_changed):
		visual.rig_changed.connect(_on_visual_rig_changed)


func _on_pawn_action_state_changed(_arg: Node3D) -> void:
	_ensure_mounts()
	_tick_barrel_smoke(0.0)
	_tick_action_hands(0.0)
	_sync_visibility()


func _on_pawn_mode_changed(_mode: int) -> void:
	_ensure_mounts()
	_tick_barrel_smoke(0.0)
	_tick_action_hands(0.0)
	_sync_visibility()


func _on_visual_rig_changed(_skel: Skeleton3D) -> void:
	tp_mount = null
	_ensure_mounts()
	_rebuild_tool_meshes()


func _ensure_mounts() -> void:
	if player_controller != null and player_controller.camera != null:
		if viewmodel_root == null or not is_instance_valid(viewmodel_root):
			viewmodel_root = player_controller.camera.get_node_or_null(^"ViewmodelRig") as Node3D
			if viewmodel_root == null:
				viewmodel_root = Node3D.new()
				viewmodel_root.name = "ViewmodelRig"
				player_controller.camera.add_child(viewmodel_root)
		if fp_action_hands == null or not is_instance_valid(fp_action_hands):
			fp_action_hands = viewmodel_root.get_node_or_null(^"FPActionHands") as Node3D
			if fp_action_hands == null:
				fp_action_hands = ToolMeshes.build_fp_hand_pair(&"fist_grip")
				_configure_fp_node(fp_action_hands)
				fp_action_hands.visible = false
				viewmodel_root.add_child(fp_action_hands)
			else:
				_configure_fp_node(fp_action_hands)
			_fp_action_left = fp_action_hands.get_node_or_null(^"LeftHand") as Node3D
			_fp_action_right = fp_action_hands.get_node_or_null(^"RightHand") as Node3D
	if visual != null and visual.hand_right != null:
		if tp_mount == null or not is_instance_valid(tp_mount):
			tp_mount = visual.hand_right.get_node_or_null(^"ToolMount") as Node3D
			if tp_mount == null:
				tp_mount = Node3D.new()
				tp_mount.name = "ToolMount"
				# Match CharacterVisual Hand_R palm orientation (+Y along fingers, -X forward).
				tp_mount.position = Vector3(0.0, 0.075, -0.015)
				tp_mount.rotation_degrees = Vector3(0.0, 0.0, -82.0)
				visual.hand_right.add_child(tp_mount)


# ==============================================================================
# Slot selection & equipment
# ==============================================================================

## Resolve a slot ID (`&"cutlass"`, `&"pistol"`, `&"instrument"`) to the captain's active tool/weapon mesh ID.
func get_resolved_tool_id(slot_id: StringName = &"") -> StringName:
	var target := active_item if slot_id == &"" else slot_id
	if target == &"cutlass":
		return melee_weapon
	if target == &"pistol":
		return ranged_weapon
	if target == &"instrument":
		if shanty_instrument == &"hurdy_gurdy":
			return &"hurdy_gurdy"
		if shanty_instrument == &"whistle":
			return &"whistle"
		return &"instrument"
	return target


## Switch the captain's armory melee (`&"cutlass"` / `&"boarding_axe"`) and ranged
## (`&"pistol"` / `&"blunderbuss"`) weapons, persisting to `Game.profile` and updating live meshes.
func set_weapon_loadout(melee_id: StringName, ranged_id: StringName) -> void:
	var next_melee := melee_id if VALID_MELEE_WEAPONS.has(melee_id) else melee_weapon
	var next_ranged := ranged_id if VALID_RANGED_WEAPONS.has(ranged_id) else ranged_weapon
	var changed := (next_melee != melee_weapon) or (next_ranged != ranged_weapon)
	melee_weapon = next_melee
	ranged_weapon = next_ranged
	if Game != null and Game.profile != null:
		Game.profile.data["melee_weapon"] = String(melee_weapon)
		Game.profile.data["ranged_weapon"] = String(ranged_weapon)

	_discover_siblings()
	if active_item == &"cutlass" or active_item == &"pistol":
		if combat != null:
			combat.equip_weapon(get_resolved_tool_id(active_item))
		_rebuild_tool_meshes()
		_equip_dip = 0.65
		item_equipped.emit(active_item)
	if changed:
		weapon_loadout_changed.emit(melee_weapon, ranged_weapon)


## Equip a specific tool by ID (returns true if valid and equipped).
func equip(item_id: StringName, silent: bool = false) -> bool:
	if item_id == &"boarding_axe":
		set_weapon_loadout(&"boarding_axe", ranged_weapon)
		item_id = &"cutlass"
	elif item_id == &"blunderbuss":
		set_weapon_loadout(melee_weapon, &"blunderbuss")
		item_id = &"pistol"

	var idx := slots.find(item_id)
	if idx < 0:
		if ToolMeshes.ALL_TOOLS.has(item_id):
			slots.append(item_id)
			idx = slots.size() - 1
		else:
			return false

	var changed := (item_id != active_item) or (fp_tool_node == null and tp_tool_node == null)
	if playing_shanty and item_id != &"instrument":
		set_playing_shanty(false)
	if active_item == &"cutlass" and item_id != &"cutlass" and combat != null and combat.is_blocking:
		combat.set_blocking(false)

	active_index = idx
	active_item = item_id
	_equip_dip = 0.0 if silent else 1.0
	_reload_timer = 0.0
	_barrel_smoke_timer = 0.0
	if _barrel_smoke != null and is_instance_valid(_barrel_smoke):
		_barrel_smoke.emitting = false
	_primary_hold_time = 0.0
	_heavy_fired_this_hold = false
	if item_id != &"compass" and (_compass_pace_active or compass_paces != 0):
		_reset_compass_pacing(false)
	if item_id != &"spyglass" and spyglass_zoom > 0.001:
		_set_spyglass_zoom(0.0)
		_was_zooming_spyglass = false
	if item_id != &"cutlass":
		_cutlass_gleam_timer = 0.0
		_cutlass_gleam_peak = 0.0

	_discover_siblings()
	if (item_id == &"cutlass" or item_id == &"pistol") and combat != null:
		combat.equip_weapon(get_resolved_tool_id(item_id))

	if changed:
		_rebuild_tool_meshes()
		if not silent:
			Audio.play_sfx(&"ui_tick", Vector3.INF, -5.0, 0.06)
	_tick_viewmodel_pose(0.0)
	if item_id == &"compass":
		_compass_needle_init = false
		_tick_compass(0.0)
	elif item_id == &"lantern":
		_tick_lantern_flicker(0.0)
	else:
		_lantern_halo_energy = 0.0
	if item_id == &"spyglass":
		ToolMeshes.update_spyglass_glint(fp_tool_node, spyglass_zoom, spyglass_sighting != "", _clock)
		ToolMeshes.update_spyglass_glint(tp_tool_node, spyglass_zoom, spyglass_sighting != "", _clock)
	elif item_id == &"cutlass":
		_tick_cutlass_gleam(0.0)
	elif item_id == &"instrument":
		if shanty_instrument == &"concertina" or shanty_instrument == &"hurdy_gurdy":
			ToolMeshes.update_shanty_notes(fp_tool_node, 0.0, playing_shanty, _clock)
			ToolMeshes.update_shanty_notes(tp_tool_node, 0.0, playing_shanty, _clock)
	_tick_action_hands(0.0)
	_sync_visibility()
	item_equipped.emit(active_item)
	return true


## Cycle forward to the next tool in `slots`.
func next_item() -> StringName:
	if slots.is_empty():
		return active_item
	var next_idx := (active_index + 1) % slots.size()
	equip(slots[next_idx])
	return active_item


## Cycle backward to the previous tool in `slots`.
func prev_item() -> StringName:
	if slots.is_empty():
		return active_item
	var prev_idx := (active_index - 1 + slots.size()) % slots.size()
	equip(slots[prev_idx])
	return active_item


## Return the currently visible tool mesh node (first-person preferred, else third-person).
func get_active_tool_node() -> Node3D:
	if fp_tool_node != null and is_instance_valid(fp_tool_node):
		return fp_tool_node
	if tp_tool_node != null and is_instance_valid(tp_tool_node):
		return tp_tool_node
	return null


func _rebuild_tool_meshes() -> void:
	_detach_barrel_smoke(true)
	if fp_tool_node != null and is_instance_valid(fp_tool_node):
		_clear_tool_node_materials(fp_tool_node)
		fp_tool_node.queue_free()
		fp_tool_node = null
	if tp_tool_node != null and is_instance_valid(tp_tool_node):
		_clear_tool_node_materials(tp_tool_node)
		tp_tool_node.queue_free()
		tp_tool_node = null

	var mesh_id := get_resolved_tool_id(active_item)
	if viewmodel_root != null and is_instance_valid(viewmodel_root):
		fp_tool_node = ToolMeshes.build_tool(mesh_id)
		var fp_hands := ToolMeshes.build_fp_hands_for_tool(mesh_id)
		fp_hands.name = "FPHands"
		fp_tool_node.add_child(fp_hands)
		_configure_fp_node(fp_tool_node)
		viewmodel_root.add_child(fp_tool_node)
		_sync_tool_visual_state(fp_tool_node)

	if tp_mount != null and is_instance_valid(tp_mount):
		tp_tool_node = ToolMeshes.build_tool(mesh_id)
		# Avoid double OmniLight3D when both FP and TP lanterns exist on the local player.
		if fp_tool_node != null and active_item == &"lantern":
			var tp_light := tp_tool_node.get_node_or_null(^"LanternLight") as OmniLight3D
			if tp_light != null:
				tp_light.visible = false
				tp_light.light_energy = 0.0
		tp_mount.add_child(tp_tool_node)
		_sync_tool_visual_state(tp_tool_node)


func _configure_fp_node(node: Node3D) -> void:
	for child in node.find_children("*", "GeometryInstance3D", true, false):
		var gi := child as GeometryInstance3D
		if gi != null:
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _sync_tool_visual_state(node: Node3D) -> void:
	if node == null:
		return
	ToolMeshes.apply_tool_variant_visual(active_item, node, tool_variant_id)
	match active_item:
		&"lantern":
			var is_tp_dup := (node == tp_tool_node and fp_tool_node != null)
			ToolMeshes.set_lantern_lit(node, lantern_lit)
			if is_tp_dup:
				var l := node.get_node_or_null(^"LanternLight") as OmniLight3D
				if l != null:
					l.visible = false
					l.light_energy = 0.0
		&"bucket":
			ToolMeshes.set_bucket_full(node, bucket_full)
		&"map":
			if treasure_map_texture != null:
				ToolMeshes.apply_map_texture(node, treasure_map_texture)
		&"spyglass":
			ToolMeshes.set_spyglass_extension(node, spyglass_zoom)
			ToolMeshes.update_spyglass_glint(node, spyglass_zoom, spyglass_sighting != "", _clock)
		&"compass":
			var needle := node.get_node_or_null(^"Needle") as Node3D
			if needle != null:
				needle.rotation.y = _compass_needle_angle
			ToolMeshes.set_compass_pin_mode(node, compass_pin_mode)
		&"cutlass":
			if melee_weapon == &"cutlass":
				var slide := clampf(1.0 - (_cutlass_gleam_timer / CUTLASS_GLEAM_DURATION), 0.0, 1.0) if _cutlass_gleam_timer > 0.0 else 0.0
				ToolMeshes.update_cutlass_gleam(node, get_cutlass_gleam_strength(), slide)
		&"instrument":
			if shanty_instrument == &"concertina" or shanty_instrument == &"hurdy_gurdy":
				ToolMeshes.update_shanty_notes(node, 0.0, playing_shanty, _clock)


# ==============================================================================
# Public tool actions (playable via input, HUD, or direct calls in tests)
# ==============================================================================

## Programmatically hold or release `secondary` (raise compass/map/lantern,
## zoom spyglass, block with cutlass, ADS with pistol, toast tankard, splash bucket, cycle shanty instrument).
func set_secondary_held(held: bool) -> void:
	var was_held := _secondary_held
	_secondary_held = held
	if active_item == &"cutlass" and combat != null:
		combat.set_blocking(held)
	elif active_item == &"compass":
		if held and not was_held:
			_reset_compass_pacing(true)
		elif not held:
			_reset_compass_pacing(false)
	elif active_item == &"tankard" and held and not was_held:
		if pawn != null and not pawn.dead and pawn.station == null and pawn.carried == null:
			raise_grog_toast()
	elif active_item == &"bucket" and held and not was_held and bucket_full:
		if pawn != null and not pawn.dead and pawn.station == null and pawn.carried == null:
			splash_bucket_forward()
	elif active_item == &"instrument" and held and not was_held:
		cycle_shanty_instrument(true)


## Return the current number of counted steps while raising the compass in pace mode.
func get_compass_paces() -> int:
	return compass_paces


## Return the Captain's current 16-point compass heading string (N, NNE, NE, ...).
func get_compass_heading_label() -> String:
	if pawn == null:
		return "N"
	return format_compass_bearing(Vector3.ZERO, pawn.facing())


## True while the compass is raised in tactile step-counting pace mode (RMB held).
func is_compass_pacing() -> bool:
	return active_item == &"compass" and _secondary_held


## Return the cached held-lantern atmospheric halo glow intensity (0.0 when doused or unequipped).
func get_lantern_halo_energy() -> float:
	return _lantern_halo_energy


## Trigger a luminous metallic gleam pulse sweeping from hilt to tip along the cutlass blade.
func trigger_cutlass_gleam(strength: float = 1.0) -> void:
	var s := clampf(strength, 0.0, 1.5)
	if s <= 0.01:
		return
	var current_s := get_cutlass_gleam_strength()
	_cutlass_gleam_peak = maxf(current_s, s)
	_cutlass_gleam_timer = CUTLASS_GLEAM_DURATION
	if active_item == &"cutlass" and melee_weapon == &"cutlass":
		ToolMeshes.update_cutlass_gleam(fp_tool_node, _cutlass_gleam_peak, 0.0)
		ToolMeshes.update_cutlass_gleam(tp_tool_node, _cutlass_gleam_peak, 0.0)


## Return the current decaying cutlass steel blade gleam strength (0.0 when idle).
func get_cutlass_gleam_strength() -> float:
	if _cutlass_gleam_timer <= 0.0 or _cutlass_gleam_peak <= 0.0:
		return 0.0
	var frac := clampf(_cutlass_gleam_timer / CUTLASS_GLEAM_DURATION, 0.0, 1.0)
	return _cutlass_gleam_peak * frac * (0.45 + 0.55 * frac)


## Return the current damped harmonic magnetic compass needle yaw angle in radians.
func get_compass_needle_angle() -> float:
	return _compass_needle_angle


## Return the current magnetic compass needle angular velocity in rad/s.
func get_compass_needle_velocity() -> float:
	return _compass_needle_vel


## True while post-shot flintlock pistol or blunderbuss barrel smoke wisps are actively emitting.
func is_firearm_barrel_smoking() -> bool:
	return active_item == &"pistol" \
		and _barrel_smoke_timer > 0.0 \
		and _barrel_smoke != null \
		and is_instance_valid(_barrel_smoke) \
		and _barrel_smoke.emitting


## Return the mounted FirearmBarrelSmoke GPUParticles3D emitter (or null if not yet spawned).
func get_firearm_barrel_smoke() -> GPUParticles3D:
	if _barrel_smoke != null and is_instance_valid(_barrel_smoke):
		return _barrel_smoke
	return null


## Resolve the active MapTableView gracefully without allocating.
func _resolve_map_table() -> MapTableView:
	if map_table != null and is_instance_valid(map_table):
		return map_table
	if pawn != null and is_instance_valid(pawn) and pawn.platform != null and is_instance_valid(pawn.platform):
		var named := pawn.platform.find_child("MapTableView", true, false) as MapTableView
		if named != null and is_instance_valid(named):
			return named
	if is_inside_tree():
		var tree := get_tree()
		if tree != null:
			var fallback: MapTableView = null
			var plat: Node = pawn.platform if (pawn != null and is_instance_valid(pawn) and is_instance_valid(pawn.platform)) else null
			for n in tree.get_nodes_in_group(&"map_tables"):
				var mtv := n as MapTableView
				if mtv == null or not is_instance_valid(mtv):
					continue
				if plat != null and mtv.tracked_ship == plat:
					return mtv
				if fallback == null:
					fallback = mtv
			if fallback != null:
				return fallback
	return null


## Return a strict-ASCII bearing & distance readout to the active chart pin (e.g. "Pin: NNE 310 m"), or "".
func get_compass_pin_summary() -> String:
	if pawn == null or not is_instance_valid(pawn):
		return ""
	var mtv := _resolve_map_table()
	if mtv == null or not mtv.has_active_pin():
		return ""
	var raw := MapTableView.format_course_bearing(pawn.global_position, mtv.get_active_pin())
	var norm := raw.replace("  ", " ").strip_edges()
	return "Pin: " + norm


## Toggle compass tracking between True North and the active MapTableView chart pin.
func toggle_compass_pin_mode() -> bool:
	var mtv := _resolve_map_table()
	if mtv == null or not mtv.has_active_pin():
		var was_pin := compass_pin_mode
		compass_pin_mode = false
		if active_item == &"compass":
			ToolMeshes.set_compass_pin_mode(fp_tool_node, false)
			ToolMeshes.set_compass_pin_mode(tp_tool_node, false)
		if was_pin:
			compass_mode_changed.emit(false)
		_start_swing(&"inspect", 0.26)
		return false
	compass_pin_mode = not compass_pin_mode
	if active_item == &"compass":
		ToolMeshes.set_compass_pin_mode(fp_tool_node, compass_pin_mode)
		ToolMeshes.set_compass_pin_mode(tp_tool_node, compass_pin_mode)
	Audio.play_sfx(&"ui_tick", Vector3.INF, -4.5, 0.05)
	_start_swing(&"inspect", 0.26)
	compass_mode_changed.emit(compass_pin_mode)
	if Game != null:
		Game.post_notice("Compass locked onto chart pin!" if compass_pin_mode else "Compass returned to True North.")
	return compass_pin_mode


## Render & bind a dynamic parchment-and-ink treasure map for the active voyage.
## `dig_local_pos` accepts either `Vector2(x, z)` or `Vector3(x, y, z)`.
func set_treasure_map(
	island_name: String,
	contour_points: PackedVector2Array,
	dig_local_pos: Variant,
	island_radius: float = 120.0
) -> ImageTexture:
	map_mode = &"treasure"
	map_island_name = island_name
	map_contour = contour_points.duplicate()
	if dig_local_pos is Vector3:
		var v3 := dig_local_pos as Vector3
		map_dig_local = Vector2(v3.x, v3.z)
	elif dig_local_pos is Vector2:
		map_dig_local = dig_local_pos as Vector2
	map_island_radius = maxf(island_radius, 12.0)
	treasure_map_texture = MapPainter.render_treasure_map(
		map_island_name, map_contour, map_dig_local, map_island_radius)
	if active_item == &"map":
		ToolMeshes.apply_map_texture(fp_tool_node, treasure_map_texture)
		ToolMeshes.apply_map_texture(tp_tool_node, treasure_map_texture)
	return treasure_map_texture


## Render & bind a hand-inked rhyming Riddle Scroll onto the held 3D parchment map.
func set_riddle_scroll(
	island_name: String,
	stanzas: Array,
	revealed_count: int = 1,
	seed_val: int = 1
) -> ImageTexture:
	map_mode = &"riddle"
	map_island_name = island_name
	treasure_map_texture = MapPainter.paint_riddle_scroll(island_name, stanzas, revealed_count, seed_val)
	if active_item == &"map":
		ToolMeshes.apply_map_texture(fp_tool_node, treasure_map_texture)
		ToolMeshes.apply_map_texture(tp_tool_node, treasure_map_texture)
	return treasure_map_texture


## Render & bind an illustrated Skull-Portrait WANTED Bounty Poster onto the held 3D parchment map.
func set_bounty_poster(
	captain_name: String,
	island_name: String,
	gold_reward: int,
	seed_val: int = 1
) -> ImageTexture:
	map_mode = &"bounty"
	map_island_name = island_name
	treasure_map_texture = MapPainter.paint_bounty_poster(captain_name, island_name, gold_reward, seed_val)
	if active_item == &"map":
		ToolMeshes.apply_map_texture(fp_tool_node, treasure_map_texture)
		ToolMeshes.apply_map_texture(tp_tool_node, treasure_map_texture)
	return treasure_map_texture


## Trigger the primary action of the currently equipped tool or weapon.
func use_primary() -> Variant:
	if pawn == null or pawn.dead or pawn.station != null or pawn.carried != null:
		return false
	if _use_cooldown > 0.0 and active_item != &"cutlass" and active_item != &"pistol":
		return false
	match active_item:
		&"cutlass", &"pistol":
			if combat != null:
				combat.equip_weapon(get_resolved_tool_id(active_item))
				return combat.primary_attack()
			if active_item == &"pistol":
				var gun_id := get_resolved_tool_id(&"pistol")
				_start_swing(gun_id, 0.46 if gun_id == &"blunderbuss" else 0.34)
				_reload_dur = 1.85 if gun_id == &"blunderbuss" else 1.45
				_reload_timer = _reload_dur
				_start_barrel_smoke(gun_id)
				return true
			_start_swing(&"slash", 0.34)
			return true
		&"lantern":
			if lantern_lit and _secondary_held:
				return trigger_lantern_signal()
			return toggle_lantern()
		&"shovel":
			return use_shovel()
		&"bucket":
			return use_bucket()
		&"planks":
			return use_planks()
		&"tankard":
			return use_tankard()
		&"instrument":
			return toggle_shanty()
		&"compass":
			return toggle_compass_pin_mode()
		&"map":
			# Quick glance lift when clicking primary on navigation tools.
			_start_swing(&"inspect", 0.32)
			return true
		&"spyglass":
			if spyglass_zoomed and spyglass_sighting != "":
				return callout_spyglass_sighting()
			set_secondary_held(not _secondary_held)
			return _secondary_held
	return false


## Call out the currently sighted spyglass horizon target to nearby crewmates (2.5 s cooldown).
func callout_spyglass_sighting() -> bool:
	if active_item != &"spyglass" or not spyglass_zoomed or spyglass_sighting == "":
		return false
	if _spyglass_callout_cd > 0.0:
		return false
	_spyglass_callout_cd = SPYGLASS_CALLOUT_COOLDOWN
	var bearing := spyglass_sighting_bearing if spyglass_sighting_bearing != "" else "ahead"
	var dist_m := int(roundf(spyglass_sighting_dist))
	var line := "Captain: %s off the %s - %d m!" % [spyglass_sighting, bearing, dist_m]
	if Game != null:
		Game.post_notice(line)
	var sfx_pos := pawn.eye_position() if pawn != null else Vector3.INF
	Audio.play_sfx(&"spyglass_slide", sfx_pos, -2.0)
	spyglass_callout_made.emit(spyglass_sighting, spyglass_sighting_dist, bearing, _spyglass_target_pos)

	if is_inside_tree():
		var nearest_brain: CrewBrain = null
		var best_d := INF
		var my_pos := pawn.global_position if pawn != null else Vector3.ZERO
		for node in get_tree().get_nodes_in_group(&"crew_brains"):
			var br := node as CrewBrain
			if br == null or not is_instance_valid(br) or br.pawn == null or br.pawn.dead:
				continue
			var d := my_pos.distance_to(br.pawn.global_position)
			if d < best_d:
				best_d = d
				nearest_brain = br
		if nearest_brain != null:
			nearest_brain.acknowledge_captain_sighting(spyglass_sighting, bearing, _spyglass_target_pos)
	return true


## Trigger a heavy melee strike (cutlass or boarding axe).
func use_heavy() -> bool:
	if pawn == null or pawn.dead or pawn.station != null or combat == null:
		return false
	if active_item == &"cutlass":
		combat.equip_weapon(melee_weapon)
		return combat.heavy_attack()
	return false


## True while the held oil lantern is lit and raised/flared into bright beacon mode (RMB).
func is_lantern_beacon_flared() -> bool:
	return active_item == &"lantern" and lantern_lit and (_secondary_held or _lantern_flare_blend > 0.35)


## Flash a bright Mariner's Signal beacon across the water (LMB while raising lit Lantern, 2.5 s cooldown).
func trigger_lantern_signal() -> bool:
	if active_item != &"lantern" or not lantern_lit:
		return false
	if _lantern_signal_cd > 0.0:
		return false
	_lantern_signal_cd = LANTERN_SIGNAL_COOLDOWN
	_lantern_signal_flash = 1.0
	_use_cooldown = 0.25
	var world_pos := pawn.eye_position() if pawn != null else Vector3.ZERO
	Audio.play_sfx(&"lantern_click", world_pos, -1.5)
	_start_swing(&"click", 0.24)
	_tick_lantern_flicker(0.0)
	if Game != null:
		Game.post_notice("Lantern signal flashed across the water!")
	lantern_signaled.emit(world_pos)
	if is_inside_tree():
		var nearest_brain: CrewBrain = null
		var best_d := INF
		var my_pos := pawn.global_position if pawn != null else Vector3.ZERO
		for node in get_tree().get_nodes_in_group(&"crew_brains"):
			var br := node as CrewBrain
			if br == null or not is_instance_valid(br) or br.pawn == null or br.pawn.dead:
				continue
			var d := my_pos.distance_to(br.pawn.global_position)
			if d < best_d:
				best_d = d
				nearest_brain = br
		if nearest_brain != null and nearest_brain.current_task == &"idle":
			nearest_brain._speak(&"banter", {}, "lantern_signal", 6.0)
	return true


## Explicitly light or douse the held oil lantern, syncing FlameHalo & OmniLight3D immediately.
func set_lantern_lit(lit: bool) -> bool:
	var changed := (lantern_lit != lit)
	lantern_lit = lit
	if not lantern_lit:
		_lantern_flare_blend = 0.0
		_lantern_signal_flash = 0.0
		_lantern_halo_energy = 0.0
	if active_item == &"lantern":
		_sync_tool_visual_state(fp_tool_node)
		_sync_tool_visual_state(tp_tool_node)
		_tick_lantern_flicker(0.0)
	if changed:
		lantern_toggled.emit(lantern_lit)
	return lantern_lit


## Toggle oil lantern flame, FlameHalo, & OmniLight3D on or off.
func toggle_lantern() -> bool:
	lantern_lit = not lantern_lit
	_use_cooldown = 0.20
	if not lantern_lit:
		_lantern_flare_blend = 0.0
		_lantern_signal_flash = 0.0
		_lantern_halo_energy = 0.0
	if active_item == &"lantern":
		_sync_tool_visual_state(fp_tool_node)
		_sync_tool_visual_state(tp_tool_node)
		_tick_lantern_flicker(0.0)
	var pos := pawn.eye_position() if pawn != null else Vector3.INF
	Audio.play_sfx(&"lantern_click", pos, -2.0)
	_start_swing(&"click", 0.22)
	lantern_toggled.emit(lantern_lit)
	return lantern_lit


## Swing the shovel and attempt to dig any nearby `DigSite` within SHOVEL_REACH (2.6 m).
func use_shovel() -> Dictionary:
	_use_cooldown = 0.58
	_start_swing(&"dig", 0.56)
	_play_anim(&"dig", 0.65)
	if pawn == null:
		return {"hit": false, "reason": "no_pawn"}

	var dig_origin := pawn.global_position + pawn.facing() * 1.0
	var best_site: Node3D = null
	var best_dist := SHOVEL_REACH

	if is_inside_tree():
		for node in get_tree().get_nodes_in_group(&"dig_sites"):
			if not (node is Node3D) or not node.has_method(&"dig"):
				continue
			var site := node as Node3D
			var d_pawn := Vector2(site.global_position.x - pawn.global_position.x,
				site.global_position.z - pawn.global_position.z).length()
			var d_tip := Vector2(site.global_position.x - dig_origin.x,
				site.global_position.z - dig_origin.z).length()
			var d := minf(d_pawn, d_tip)
			if d <= best_dist:
				best_dist = d
				best_site = site

	if best_site != null:
		# Pass a dig point cleanly within DigSite's DIG_RADIUS when pawn is within SHOVEL_REACH.
		var offset := dig_origin - best_site.global_position
		var flat := Vector2(offset.x, offset.z)
		var strike_pos := best_site.global_position
		if flat.length() > 0.01:
			var clamped := flat.limit_length(2.0)
			strike_pos = Vector3(best_site.global_position.x + clamped.x, best_site.global_position.y, best_site.global_position.z + clamped.y)
		spawn_shovel_dirt_vfx(strike_pos)
		var strikes := maxi(1, dig_power)
		var last_res: Dictionary = {}
		for _si in strikes:
			var res: Variant = best_site.call(&"dig", strike_pos, pawn)
			if not (res is Dictionary):
				return {"hit": true}
			last_res = res as Dictionary
			if not bool(last_res.get("hit", false)) or bool(last_res.get("unearthed", false)):
				break
		if not bool(last_res.get("hit", false)):
			Audio.play_sfx(&"dig_sand", dig_origin, -3.0)
		elif not bool(last_res.get("unearthed", false)):
			Audio.play_sfx(&"chest_thump", strike_pos, -2.5)
		return last_res

	spawn_shovel_dirt_vfx(dig_origin)
	Audio.play_sfx(&"dig_sand", dig_origin, -3.0)
	return {"hit": false, "reason": "no_dig_site"}


## Scoop water from a flooded `Ship` (or shallow sea / deck rail), or splash carried water out!
func use_bucket() -> Dictionary:
	_use_cooldown = 0.38
	_play_anim(&"bail", 0.55)
	if pawn == null:
		return {"action": &"none", "full": bucket_full}

	if bucket_full:
		# Splash carried water out!
		bucket_full = false
		_start_swing(&"splash", 0.42)
		if active_item == &"bucket":
			ToolMeshes.set_bucket_full(fp_tool_node, false)
			ToolMeshes.set_bucket_full(tp_tool_node, false)
		var view := pawn.view_dir()
		var splash_pos := pawn.eye_position() + view * 0.9
		Audio.play_sfx(&"bucket_splash", splash_pos, -1.0)
		_spawn_water_splash_puff(splash_pos, view)
		var fires_doused := _douse_nearby_ship_fire(splash_pos, 4.8)
		var rage_chests_cooled := _cool_nearby_rage_chests(splash_pos, 4.8)
		var throw_overboard := false
		if pawn.platform is Ship:
			var s_plat := pawn.platform as Ship
			var hs_v: Variant = s_plat.get(&"hull_scale")
			var hs := float(hs_v) if (hs_v != null and float(hs_v) > 0.01) else 1.0
			var loc := pawn.platform_local_position()
			var in_hold := (loc.y / hs) < 0.25
			var horiz_v := Vector3(view.x, 0.0, view.z)
			var hdir := horiz_v.normalized() if horiz_v.length_squared() > 0.01 else pawn.facing()
			var proj_w := pawn.eye_position() + hdir * (3.6 * hs)
			var proj_l := s_plat.global_transform.affine_inverse() * proj_w
			var beam_half := (2.25 if s_plat.ship_class == &"brigantine" else 1.85) * hs
			var len_half := (7.8 if s_plat.ship_class == &"brigantine" else 5.6) * hs
			var outside_hull := absf(proj_l.x) > beam_half or absf(proj_l.z) > len_half
			throw_overboard = (not in_hold) and (outside_hull or view.y > -0.35)
		elif pawn.is_swimming() or Sea.depth(pawn.global_position) > -0.6:
			throw_overboard = true
		if throw_overboard and Ocean.current != null:
			var horiz_f := Vector3(view.x, 0.0, view.z)
			var fdir := horiz_f.normalized() if horiz_f.length_squared() > 0.01 else pawn.facing()
			var foam_pt := pawn.global_position + fdir * 3.6
			foam_pt.y = Sea.height(foam_pt.x, foam_pt.z)
			Ocean.current.add_foam(foam_pt, 1.35, 0.68)
		bucket_changed.emit(false)
		return {
			"action": &"splash",
			"full": false,
			"overboard": throw_overboard,
			"fires_doused": fires_doused,
			"rage_chests_cooled": rage_chests_cooled,
		}

	# Attempt to bail from current or adjacent flooded Ship.
	var ship := _find_nearby_ship(5.5)
	if ship != null and ship.water_level > 0.005:
		var removed := ship.bail(BAIL_AMOUNT * bail_power_scale)
		if removed > 0.0005:
			bucket_full = true
			_start_swing(&"scoop", 0.42)
			if active_item == &"bucket":
				ToolMeshes.set_bucket_full(fp_tool_node, true)
				ToolMeshes.set_bucket_full(tp_tool_node, true)
			Audio.play_sfx(&"splash_small", pawn.global_position, -3.0)
			bucket_changed.emit(true)
			return {"action": &"bail", "removed": removed, "full": true}

	# Otherwise scoop seawater if wading, swimming, or leaning over a ship's deck rail near the sea!
	var near_rail_water := false
	if pawn.platform is Ship:
		var s_rail := pawn.platform as Ship
		var hs_v: Variant = s_rail.get(&"hull_scale")
		var hs := float(hs_v) if (hs_v != null and float(hs_v) > 0.01) else 1.0
		var loc := pawn.platform_local_position()
		var beam_edge := (1.55 if s_rail.ship_class == &"brigantine" else 1.25) * hs
		var on_upper_deck := (loc.y / hs) >= 0.45
		var sea_y := Sea.height(pawn.global_position.x, pawn.global_position.z)
		if on_upper_deck and absf(loc.x) >= beam_edge and (pawn.global_position.y - sea_y) <= 3.6:
			near_rail_water = true
	if pawn.is_swimming() or Sea.depth(pawn.global_position) > 0.05 or near_rail_water:
		bucket_full = true
		_start_swing(&"scoop", 0.42)
		if active_item == &"bucket":
			ToolMeshes.set_bucket_full(fp_tool_node, true)
			ToolMeshes.set_bucket_full(tp_tool_node, true)
		Audio.play_sfx(&"splash_small", pawn.global_position, -2.0)
		if near_rail_water and Ocean.current != null:
			var rail_foam := pawn.global_position + pawn.facing() * 1.6
			rail_foam.y = Sea.height(rail_foam.x, rail_foam.z)
			Ocean.current.add_foam(rail_foam, 0.95, 0.45)
		bucket_changed.emit(true)
		return {"action": &"scoop_sea", "full": true}

	_start_swing(&"scoop", 0.34)
	return {"action": &"empty_swing", "full": false}


## Throw carried bucket water straight ahead along view direction (RMB on full bucket).
## Empties bucket, spawns sculpted splash droplets, adds ocean foam near waterline,
## extinguishes nearby deck fire flames, cools nearby BlazingRageChests, and prompts
## a lighthearted bark from any AI crewmate caught within 4.5 m ahead!
func splash_bucket_forward() -> Dictionary:
	if pawn == null or pawn.dead or pawn.station != null or pawn.carried != null or not bucket_full:
		return {
			"action": &"none",
			"full": bucket_full,
			"splashed_crew": false,
			"fires_doused": 0,
			"rage_chests_cooled": 0,
		}
	_use_cooldown = 0.38
	bucket_full = false
	_start_swing(&"splash", 0.44)
	_play_anim(&"bail", 0.55)
	if active_item == &"bucket":
		ToolMeshes.set_bucket_full(fp_tool_node, false)
		ToolMeshes.set_bucket_full(tp_tool_node, false)
	var view := pawn.view_dir()
	var splash_pos := pawn.eye_position() + view * 0.95
	Audio.play_sfx(&"bucket_splash", splash_pos, -0.5)
	_spawn_water_splash_puff(splash_pos, view)
	var fires_doused := _douse_nearby_ship_fire(splash_pos, 4.8)
	var rage_chests_cooled := _cool_nearby_rage_chests(splash_pos, 4.8)

	var horiz_v := Vector3(view.x, 0.0, view.z)
	var fdir := horiz_v.normalized() if horiz_v.length_squared() > 0.01 else pawn.facing()
	var land_pt := pawn.global_position + fdir * 3.6
	var sea_y := Sea.height(land_pt.x, land_pt.z)
	var near_waterline := pawn.is_swimming() \
		or absf(pawn.global_position.y - sea_y) <= 3.8 \
		or Sea.depth(land_pt) > -0.6
	if near_waterline and Ocean.current != null:
		var foam_pt := Vector3(land_pt.x, sea_y, land_pt.z)
		Ocean.current.add_foam(foam_pt, 1.35, 0.68)

	var splashed_crew := false
	var splashed_name := ""
	if is_inside_tree():
		var best_brain: CrewBrain = null
		var best_d := 4.5
		var my_pos := pawn.global_position
		for node in get_tree().get_nodes_in_group(&"crew_brains"):
			var br := node as CrewBrain
			if br == null or not is_instance_valid(br) or br.pawn == null or br.pawn.dead:
				continue
			var to_crew := br.pawn.global_position - my_pos
			var dist := to_crew.length()
			if dist < 0.05 or dist > best_d:
				continue
			var flat_to := Vector3(to_crew.x, 0.0, to_crew.z)
			if flat_to.length_squared() > 0.001 and flat_to.normalized().dot(fdir) >= 0.45:
				best_d = dist
				best_brain = br
		if best_brain != null and best_brain.react_to_water_splash():
			splashed_crew = true
			splashed_name = best_brain.crew_name()

	bucket_changed.emit(false)
	return {
		"action": &"splash_forward",
		"full": false,
		"splashed_crew": splashed_crew,
		"splashed_name": splashed_name,
		"fires_doused": fires_doused,
		"rage_chests_cooled": rage_chests_cooled,
	}


func _douse_nearby_ship_fire(splash_pos: Vector3, radius: float = 4.8) -> int:
	if pawn == null:
		return 0
	var target_ship: Ship = null
	if pawn.platform is Ship:
		var plat_ship := pawn.platform as Ship
		if plat_ship.has_deck_fire():
			target_ship = plat_ship
	if target_ship == null and is_inside_tree():
		var best_d := 6.5
		for node in get_tree().get_nodes_in_group(&"ship"):
			var s := node as Ship
			if s == null or not is_instance_valid(s) or not s.has_deck_fire():
				continue
			var d_ship := splash_pos.distance_to(s.global_position)
			var eff_d := d_ship
			var sf := s.get_ship_fire()
			if sf != null:
				var near_fire := sf.get_nearest_fire_world_pos(splash_pos)
				if near_fire.is_finite():
					eff_d = minf(eff_d, splash_pos.distance_to(near_fire))
			if eff_d <= best_d:
				best_d = eff_d
				target_ship = s
	if target_ship != null and target_ship.has_deck_fire():
		return target_ship.douse_deck_fire(splash_pos, radius)
	return 0


func _cool_nearby_rage_chests(splash_pos: Vector3, radius: float = 4.8) -> int:
	if pawn == null or not is_inside_tree():
		return 0
	var cooled := 0
	for node in get_tree().get_nodes_in_group(TreasureCatalog.TREASURE_GROUP):
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		if node.has_meta(&"_merchant_sold"):
			continue
		if float(node.get_meta(&"curse_heat_rate", 0.0)) <= 0.0:
			continue
		var chest_node := node as Node3D
		var dist := minf(
			splash_pos.distance_to(chest_node.global_position),
			pawn.global_position.distance_to(chest_node.global_position)
		)
		if dist <= radius and TreasureCatalog.cool_rage_chest(chest_node, 0.75):
			cooled += 1
	if cooled > 0 and Game != null:
		Game.post_notice("Splashed the Chest of Blazing Rage - steam hisses off its iron bands!")
	return cooled


## Patch the nearest open hull breach on the current `Ship` within PLANK_REACH (3.8 m).
func use_planks() -> bool:
	_use_cooldown = 0.56
	_start_swing(&"hammer", 0.56)
	_play_anim(&"hammer", 0.56)
	if pawn == null:
		return false
	var ship := _find_nearby_ship(6.5)
	if ship == null:
		return false
	var open_holes := ship.get_open_holes()
	if open_holes.is_empty():
		return false

	var best_idx := -1
	var best_dist := PLANK_REACH
	for h in open_holes:
		var h_world := ship.global_transform * (h["local_pos"] as Vector3)
		var d := pawn.global_position.distance_to(h_world)
		var d_eye := pawn.eye_position().distance_to(h_world)
		var eff := minf(d, d_eye)
		if eff <= best_dist:
			best_dist = eff
			best_idx = int(h["index"])

	if best_idx >= 0:
		return ship.patch_hole(best_idx)
	return false


## Take a hearty swig of grog: +15 HP, playful tipsy camera sway, and occasional burp!
func use_tankard() -> bool:
	_use_cooldown = 1.05
	_start_swing(&"drink", 0.95)
	_play_anim(&"drink", 1.05)
	if pawn == null:
		return false
	if Net.is_host():
		pawn.heal(GROG_HEAL)
	Audio.play_sfx(&"grog_gulp", pawn.eye_position(), -1.5)
	tipsy = clampf(tipsy + 0.42, 0.0, 1.0)
	tipsy_changed.emit(tipsy)
	if tipsy > 0.55 or _rng.randf() < 0.35:
		_burp_timer = 0.95
	return true


## Raise the held grog tankard in a pirate "Cheers!" toast (4.0 s cooldown) and rally nearby crew.
func raise_grog_toast() -> bool:
	if active_item != &"tankard":
		return false
	if pawn == null or pawn.dead or pawn.station != null or pawn.carried != null:
		return false
	if _grog_toast_cd > 0.0:
		return false
	_grog_toast_cd = GROG_TOAST_COOLDOWN
	_start_swing(&"toast", 0.55)
	_play_anim(&"drink", 0.65)
	var sfx_pos := pawn.eye_position()
	Audio.play_sfx(&"parry_ring", sfx_pos, -12.0, 0.08)
	Audio.play_sfx(&"crew_shout", sfx_pos, -5.0, 0.06)
	if Game != null:
		Game.post_notice("Captain raises a tankard: To fair winds and fat coffers!")
	grog_toast_raised.emit()

	if is_inside_tree():
		var nearest_brain: CrewBrain = null
		var best_d := 14.0
		var my_pos := pawn.global_position
		for node in get_tree().get_nodes_in_group(&"crew_brains"):
			var br := node as CrewBrain
			if br == null or not is_instance_valid(br) or br.pawn == null or br.pawn.dead:
				continue
			var d := my_pos.distance_to(br.pawn.global_position)
			if d <= best_d:
				best_d = d
				nearest_brain = br
		if nearest_brain != null:
			nearest_brain.acknowledge_captain_toast()
	return true


## Cycle forward through the captain's 3 sculpted shanty instruments (Concertina -> Hurdy-Gurdy -> Bosun's Whistle).
func cycle_shanty_instrument(announce: bool = true) -> StringName:
	var idx := SHANTY_INSTRUMENTS.find(shanty_instrument)
	var next_inst: StringName = SHANTY_INSTRUMENTS[(idx + 1) % SHANTY_INSTRUMENTS.size()]
	set_shanty_instrument(next_inst, announce)
	return shanty_instrument


## Select a specific shanty instrument (`&"concertina"`, `&"hurdy_gurdy"`, `&"whistle"`).
## Smoothly crossfades shanty stems without breaking beat-sync if currently playing.
func set_shanty_instrument(inst: StringName, announce: bool = false) -> void:
	if not SHANTY_INSTRUMENTS.has(inst):
		return
	if inst == shanty_instrument:
		return
	var old_inst := shanty_instrument
	shanty_instrument = inst
	_whistle_rot_deg = Vector3.ZERO
	if playing_shanty:
		if Audio.is_shanty_playing():
			Audio.set_shanty_instrument(old_inst, false, 0.25)
			Audio.set_shanty_instrument(shanty_instrument, true, 0.25)
		else:
			Audio.play_shanty([shanty_instrument])
			_started_shanty = true
	if active_item == &"instrument":
		_discover_siblings()
		_rebuild_tool_meshes()
		_equip_dip = 0.55
		Audio.play_sfx(&"ui_tick", Vector3.INF, -5.0, 0.06)
	if announce and Game != null:
		var disp := String(SHANTY_INSTRUMENT_NAMES.get(shanty_instrument, String(shanty_instrument).capitalize()))
		Game.post_notice("Instrument: %s" % disp)
	shanty_instrument_changed.emit(shanty_instrument)


## Return the captain's active rising golden shanty motes particle node (or null when idle).
func get_shanty_motes() -> GPUParticles3D:
	if _shanty_motes != null and is_instance_valid(_shanty_motes):
		return _shanty_motes
	return null


## Toggle shanty playback on the captain's active instrument (AI crewmates automatically join in!).
func toggle_shanty() -> bool:
	set_playing_shanty(not playing_shanty)
	return playing_shanty


func set_playing_shanty(on: bool) -> void:
	if playing_shanty == on:
		return
	playing_shanty = on
	if on:
		_last_shanty_audio_beat = -1.0
		_shanty_phase = Audio.shanty_beat() if Audio.is_shanty_playing() else (_clock * 2.0)
		if not Audio.is_shanty_playing():
			Audio.play_shanty([shanty_instrument])
			_started_shanty = true
		else:
			Audio.set_shanty_instrument(shanty_instrument, true, 0.35)
			_started_shanty = false
		_attach_captain_shanty_motes()
		_play_anim(&"play_instrument", 1.2)
		if active_item == &"instrument" and (shanty_instrument == &"concertina" or shanty_instrument == &"hurdy_gurdy"):
			ToolMeshes.update_shanty_notes(fp_tool_node, 0.0, true, _clock)
			ToolMeshes.update_shanty_notes(tp_tool_node, 0.0, true, _clock)
	else:
		_detach_captain_shanty_motes(true)
		_last_shanty_audio_beat = -1.0
		_whistle_rot_deg = Vector3.ZERO
		if _started_shanty:
			Audio.stop_shanty(0.5)
			_started_shanty = false
		else:
			Audio.set_shanty_instrument(shanty_instrument, false, 0.35)
		if active_item == &"instrument":
			if shanty_instrument == &"concertina":
				ToolMeshes.set_concertina_stretch(fp_tool_node, 0.5)
				ToolMeshes.set_concertina_stretch(tp_tool_node, 0.5)
				ToolMeshes.update_shanty_notes(fp_tool_node, 0.0, false, _clock)
				ToolMeshes.update_shanty_notes(tp_tool_node, 0.0, false, _clock)
			elif shanty_instrument == &"hurdy_gurdy":
				ToolMeshes.update_shanty_notes(fp_tool_node, 0.0, false, _clock)
				ToolMeshes.update_shanty_notes(tp_tool_node, 0.0, false, _clock)
			elif shanty_instrument == &"whistle" and tp_tool_node != null and is_instance_valid(tp_tool_node):
				tp_tool_node.rotation_degrees = Vector3.ZERO
	shanty_playing_changed.emit(playing_shanty)


func _attach_captain_shanty_motes() -> void:
	_detach_captain_shanty_motes(true)
	if pawn == null or not is_instance_valid(pawn):
		return
	var p := CrewBrain._build_shanty_motes()
	p.name = "CaptainShantyMotes"
	pawn.add_child(p)
	_shanty_motes = p


func _detach_captain_shanty_motes(detach_from_parent: bool = true) -> void:
	if _shanty_motes != null and is_instance_valid(_shanty_motes):
		_shanty_motes.emitting = false
		_shanty_motes.visible = false
		_shanty_motes.draw_pass_1 = null
		_shanty_motes.process_material = null
		if detach_from_parent and _shanty_motes.get_parent() != null:
			_shanty_motes.get_parent().remove_child(_shanty_motes)
		_shanty_motes.queue_free()
	_shanty_motes = null


## Hail all AI crewmates within 110 m through the sculpted brass Speaking Trumpet,
## recalling ashore crew back to ship with a booming horn SFX and acoustic wave pulse.
func hail_with_speaking_trumpet() -> Dictionary:
	if pawn == null or not is_instance_valid(pawn) or pawn.dead or pawn.station != null:
		return {
			"ok": false,
			"reason": "unavailable",
			"radius": SPEAKING_TRUMPET_HAIL_RADIUS,
			"crew_acked": 0,
		}
	if _trumpet_cooldown > 0.0:
		return {
			"ok": false,
			"reason": "cooldown",
			"cooldown_left": _trumpet_cooldown,
			"radius": SPEAKING_TRUMPET_HAIL_RADIUS,
			"crew_acked": 0,
		}

	_trumpet_cooldown = SPEAKING_TRUMPET_COOLDOWN
	var origin := pawn.global_position
	var eye_pos := pawn.eye_position()
	Audio.play_sfx(&"ship_bell", eye_pos, -2.0, 0.04)
	Audio.play_sfx(&"crew_shout", eye_pos, -1.0, 0.06)

	_start_swing(&"inspect", 0.55)
	_play_anim(&"shout", 0.75)
	_show_speaking_trumpet_briefly(SPEAKING_TRUMPET_DISPLAY_SECONDS)
	_spawn_trumpet_pulse(eye_pos + pawn.view_dir() * 0.52, pawn.view_dir())

	if Game != null:
		Game.post_notice("Captain hails across the waves (110 m): 'All hands return to ship!'")

	var target_ship := _resolve_rally_ship()
	var crew_acked := 0
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group(&"crew_brains"):
			var br := node as CrewBrain
			if br == null or not is_instance_valid(br) or br.pawn == null or not is_instance_valid(br.pawn) or br.pawn.dead:
				continue
			var horiz_dist := Vector2(br.pawn.global_position.x - origin.x, br.pawn.global_position.z - origin.z).length()
			if horiz_dist <= SPEAKING_TRUMPET_HAIL_RADIUS:
				if br.receive_trumpet_hail(origin, target_ship):
					crew_acked += 1

	speaking_trumpet_hailed.emit(origin, SPEAKING_TRUMPET_HAIL_RADIUS, crew_acked)
	return {
		"ok": true,
		"radius": SPEAKING_TRUMPET_HAIL_RADIUS,
		"crew_acked": crew_acked,
	}


func _resolve_rally_ship() -> Ship:
	if pawn == null or not is_instance_valid(pawn):
		return null
	if pawn.platform is Ship and is_instance_valid(pawn.platform):
		return pawn.platform as Ship
	if not is_inside_tree():
		return null
	var best_player: Ship = null
	var best_player_d := 260.0
	var fallback: Ship = null
	var fallback_d := 260.0
	for node in get_tree().get_nodes_in_group(&"ship"):
		var s := node as Ship
		if s == null or not is_instance_valid(s) or s.is_sinking:
			continue
		var d := pawn.global_position.distance_to(s.global_position)
		if s.faction == &"player" and d < best_player_d:
			best_player_d = d
			best_player = s
		if d < fallback_d:
			fallback_d = d
			fallback = s
	return best_player if best_player != null else fallback


func _show_speaking_trumpet_briefly(duration: float) -> void:
	_trumpet_display_timer = maxf(duration, 0.25)
	_ensure_mounts()
	if viewmodel_root == null or not is_instance_valid(viewmodel_root):
		return
	if _fp_trumpet_node == null or not is_instance_valid(_fp_trumpet_node):
		_fp_trumpet_node = ToolMeshes.build_tool(&"speaking_trumpet")
		_fp_trumpet_node.name = "BriefSpeakingTrumpet"
		var trumpet_hands := ToolMeshes.build_fp_hands_for_tool(&"speaking_trumpet")
		trumpet_hands.name = "FPHands"
		_fp_trumpet_node.add_child(trumpet_hands)
		_configure_fp_node(_fp_trumpet_node)
		viewmodel_root.add_child(_fp_trumpet_node)
	var pose: Array = FP_POSES[&"speaking_trumpet"]
	_fp_trumpet_node.position = pose[2] as Vector3
	_fp_trumpet_node.rotation_degrees = pose[3] as Vector3
	_fp_trumpet_node.scale = Vector3.ONE * float(pose[4])
	_fp_trumpet_node.visible = true


func _spawn_trumpet_pulse(world_pos: Vector3, dir: Vector3) -> void:
	if pawn == null or not is_instance_valid(pawn):
		return
	var host := pawn.get_parent()
	if host == null or not is_instance_valid(host):
		return
	if _trumpet_ring_mesh == null:
		_trumpet_ring_mesh = _build_trumpet_ring_mesh()
	var mi := MeshInstance3D.new()
	mi.name = "TrumpetAcousticPulse"
	mi.mesh = _trumpet_ring_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.uv1_world_triplanar = false
	mat.albedo_color = Color(0.98, 0.84, 0.44, 0.65)
	mi.material_override = mat
	host.add_child(mi)
	var fwd := dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	var up_ref := Vector3.UP if absf(fwd.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
	var right := up_ref.cross(-fwd).normalized()
	var up := (-fwd).cross(right).normalized()
	mi.global_transform = Transform3D(Basis(right, up, -fwd), world_pos)
	mi.scale = Vector3.ONE * 0.25
	_trumpet_pulses.append({
		"node": mi,
		"mat": mat,
		"dir": fwd,
		"elapsed": 0.0,
		"duration": 0.62,
	})


func _tick_speaking_trumpet_fx(delta: float) -> void:
	if _trumpet_display_timer > 0.0:
		_trumpet_display_timer = maxf(0.0, _trumpet_display_timer - delta)
		if _fp_trumpet_node != null and is_instance_valid(_fp_trumpet_node):
			var u := 1.0 - (_trumpet_display_timer / SPEAKING_TRUMPET_DISPLAY_SECONDS)
			var pose: Array = FP_POSES[&"speaking_trumpet"]
			var rest_pos: Vector3 = pose[0]
			var raise_pos: Vector3 = pose[2]
			var rest_rot: Vector3 = pose[1]
			var raise_rot: Vector3 = pose[3]
			var lift := sin(clampf(u, 0.0, 1.0) * PI)
			_fp_trumpet_node.position = rest_pos.lerp(raise_pos, clampf(lift * 1.45, 0.0, 1.0))
			_fp_trumpet_node.rotation_degrees = rest_rot.lerp(raise_rot, clampf(lift * 1.45, 0.0, 1.0))
		if _trumpet_display_timer <= 0.0 and _fp_trumpet_node != null:
			if is_instance_valid(_fp_trumpet_node):
				if _fp_trumpet_node.get_parent() != null:
					_fp_trumpet_node.get_parent().remove_child(_fp_trumpet_node)
				_fp_trumpet_node.queue_free()
			_fp_trumpet_node = null

	var i := _trumpet_pulses.size() - 1
	while i >= 0:
		var entry: Dictionary = _trumpet_pulses[i]
		var mi := entry["node"] as MeshInstance3D
		if mi == null or not is_instance_valid(mi):
			_trumpet_pulses.remove_at(i)
			i -= 1
			continue
		var el: float = float(entry["elapsed"]) + delta
		var dur: float = float(entry["duration"])
		entry["elapsed"] = el
		if el >= dur:
			if mi.get_parent() != null:
				mi.get_parent().remove_child(mi)
			mi.queue_free()
			_trumpet_pulses.remove_at(i)
		else:
			var t := clampf(el / dur, 0.0, 1.0)
			var sc := lerpf(0.28, 3.8, 1.0 - pow(1.0 - t, 2.0))
			mi.scale = Vector3(sc, sc, 1.0)
			var dir_v: Vector3 = entry["dir"]
			mi.global_position += dir_v * delta * 5.2
			var mat := entry["mat"] as StandardMaterial3D
			if mat != null:
				mat.albedo_color.a = 0.65 * (1.0 - t) * (1.0 - t)
		i -= 1


func _clear_speaking_trumpet_fx(detach_from_parent: bool = true) -> void:
	_trumpet_display_timer = 0.0
	if _fp_trumpet_node != null and is_instance_valid(_fp_trumpet_node):
		if detach_from_parent and _fp_trumpet_node.get_parent() != null:
			_fp_trumpet_node.get_parent().remove_child(_fp_trumpet_node)
		_fp_trumpet_node.queue_free()
	_fp_trumpet_node = null
	for entry: Dictionary in _trumpet_pulses:
		var mi := entry.get("node") as MeshInstance3D
		if mi != null and is_instance_valid(mi):
			if detach_from_parent and mi.get_parent() != null:
				mi.get_parent().remove_child(mi)
			mi.queue_free()
	_trumpet_pulses.clear()


static func _build_trumpet_ring_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 24
	var r_in := 0.86
	var r_out := 1.0
	var col_in := Color(1.0, 0.90, 0.52, 0.95)
	var col_out := Color(0.92, 0.72, 0.28, 0.20)
	for i in segs:
		var a0 := float(i) / float(segs) * TAU
		var a1 := float(i + 1) / float(segs) * TAU
		var p0_in := Vector3(cos(a0) * r_in, sin(a0) * r_in, 0.0)
		var p1_in := Vector3(cos(a1) * r_in, sin(a1) * r_in, 0.0)
		var p0_out := Vector3(cos(a0) * r_out, sin(a0) * r_out, 0.0)
		var p1_out := Vector3(cos(a1) * r_out, sin(a1) * r_out, 0.0)
		st.set_color(col_in); st.add_vertex(p0_in)
		st.set_color(col_out); st.add_vertex(p0_out)
		st.set_color(col_out); st.add_vertex(p1_out)
		st.set_color(col_in); st.add_vertex(p0_in)
		st.set_color(col_out); st.add_vertex(p1_out)
		st.set_color(col_in); st.add_vertex(p1_in)
	st.generate_normals()
	return st.commit()


# ==============================================================================
# Frame updates & input routing
# ==============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if not _can_read_player_input():
		return
	if event is InputEventKey:
		var kev := event as InputEventKey
		if kev.pressed and not kev.echo and (kev.physical_keycode == KEY_T or kev.keycode == KEY_T):
			var vp := get_viewport()
			var focus_owner: Control = vp.gui_get_focus_owner() if vp != null else null
			if not (focus_owner is LineEdit or focus_owner is TextEdit):
				hail_with_speaking_trumpet()
				if vp != null:
					vp.set_input_as_handled()
				return
	if event.is_action_pressed(&"item_next"):
		next_item()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			next_item()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			prev_item()


func _process(delta: float) -> void:
	_clock += delta
	_use_cooldown = maxf(0.0, _use_cooldown - delta)
	_spyglass_callout_cd = maxf(0.0, _spyglass_callout_cd - delta)
	_grog_toast_cd = maxf(0.0, _grog_toast_cd - delta)
	_trumpet_cooldown = maxf(0.0, _trumpet_cooldown - delta)
	if _burp_timer > 0.0:
		_burp_timer -= delta
		if _burp_timer <= 0.0:
			_burp_timer = -1.0
			var pos := pawn.eye_position() if pawn != null else Vector3.INF
			Audio.play_sfx(&"burp", pos, -2.5)

	if pawn == null or player_controller == null or viewmodel_root == null or (viewmodel_root != null and fp_action_hands == null):
		_discover_siblings()

	_poll_input(delta)
	_tick_tipsy(delta)
	_tick_spyglass(delta)
	_tick_compass(delta)
	_tick_concertina(delta)
	_tick_lantern_flicker(delta)
	_tick_cutlass_gleam(delta)
	_tick_barrel_smoke(delta)
	_tick_speaking_trumpet_fx(delta)
	_tick_viewmodel_pose(delta)
	_tick_action_hands(delta)
	_sync_visibility()


func _can_read_player_input() -> bool:
	if not input_enabled or pawn == null or pawn.dead:
		return false
	if pawn.station != null or pawn.carried != null:
		return false
	if player_controller == null or not player_controller.input_enabled or player_controller.look_paused:
		return false
	return true


func _poll_input(delta: float) -> void:
	if not _can_read_player_input():
		if _primary_was_down:
			_primary_was_down = false
			_primary_hold_time = 0.0
			_heavy_fired_this_hold = false
		if input_enabled and _secondary_held:
			set_secondary_held(false)
		return

	var sec := Input.is_action_pressed(&"secondary")
	if sec != _secondary_held:
		set_secondary_held(sec)

	var pri := Input.is_action_pressed(&"primary")
	if active_item == &"cutlass":
		# Tap primary for snappy light combo; hold >= HEAVY_HOLD_TIME for heavy guard-break slash!
		if pri:
			if not _primary_was_down:
				_primary_hold_time = 0.0
				_heavy_fired_this_hold = false
			else:
				_primary_hold_time += delta
				if not _heavy_fired_this_hold and _primary_hold_time >= HEAVY_HOLD_TIME:
					_heavy_fired_this_hold = true
					use_heavy()
		elif _primary_was_down:
			if not _heavy_fired_this_hold:
				use_primary()
			_primary_hold_time = 0.0
			_heavy_fired_this_hold = false
	else:
		if pri and not _primary_was_down:
			use_primary()
	_primary_was_down = pri


func _tick_tipsy(delta: float) -> void:
	if tipsy > 0.0:
		tipsy = maxf(0.0, tipsy - delta * 0.075)
		tipsy_changed.emit(tipsy)
	# Layer playful tipsy sway cleanly onto PlayerController.camera (Inventory runs at priority 10).
	if tipsy > 0.005 and player_controller != null and player_controller.camera != null:
		var roll := sin(_clock * 1.9) * 0.085 * tipsy
		var pitch := cos(_clock * 2.6) * 0.032 * tipsy
		var sway_x := sin(_clock * 1.35) * 0.045 * tipsy
		var xf := player_controller.camera.transform
		xf.basis = xf.basis * Basis(Vector3.BACK, roll) * Basis(Vector3.RIGHT, pitch)
		xf.origin += xf.basis.x * sway_x
		player_controller.camera.transform = xf


func _tick_spyglass(delta: float) -> void:
	var want_zoom := (active_item == &"spyglass") and _secondary_held and pawn != null and pawn.station == null and not pawn.dead
	if want_zoom != _was_zooming_spyglass:
		_was_zooming_spyglass = want_zoom
		Audio.play_sfx(&"spyglass_slide", Vector3.INF, -3.0)

	var target_z := 1.0 if want_zoom else 0.0
	var next_z := lerpf(spyglass_zoom, target_z, 1.0 - exp(-10.5 * delta))
	if absf(next_z - target_z) < 0.003:
		next_z = target_z
	if absf(next_z - spyglass_zoom) > 0.0005:
		_set_spyglass_zoom(next_z)

	# Drive camera FOV smoothly in exact lockstep with spyglass_zoom (or pistol ADS).
	if player_controller != null and player_controller.camera != null:
		var base := player_controller.fov if player_controller.fov > 10.0 else BASE_FOV
		if spyglass_zoom > 0.002 or active_item == &"spyglass":
			var target_spy_fov := clampf(SPYGLASS_FOV * spyglass_zoom_scale, 8.0, base)
			player_controller.camera.fov = lerpf(base, target_spy_fov, spyglass_zoom)
		else:
			var ads_fov := BLUNDERBUSS_ADS_FOV if ranged_weapon == &"blunderbuss" else PISTOL_ADS_FOV
			var target_fov := ads_fov if (active_item == &"pistol" and _secondary_held) else base
			player_controller.camera.fov = lerpf(player_controller.camera.fov, target_fov, 1.0 - exp(-12.0 * delta))

	if active_item == &"spyglass":
		ToolMeshes.set_spyglass_extension(fp_tool_node, spyglass_zoom)
		ToolMeshes.set_spyglass_extension(tp_tool_node, spyglass_zoom)

	# Horizon sighting scan while peering through the spyglass.
	if spyglass_zoom > 0.45:
		_sighting_timer -= delta
		if _sighting_timer <= 0.0:
			_sighting_timer = 0.15
			_scan_spyglass_sighting()
	elif spyglass_sighting != "" or spyglass_sighting_bearing != "":
		spyglass_sighting = ""
		spyglass_sighting_dist = 0.0
		spyglass_sighting_bearing = ""
		_spyglass_target_pos = Vector3.ZERO
		sighting_updated.emit("", 0.0)

	if active_item == &"spyglass":
		var has_sight := spyglass_sighting != ""
		ToolMeshes.update_spyglass_glint(fp_tool_node, spyglass_zoom, has_sight, _clock)
		ToolMeshes.update_spyglass_glint(tp_tool_node, spyglass_zoom, has_sight, _clock)


func _set_spyglass_zoom(v: float) -> void:
	spyglass_zoom = clampf(v, 0.0, 1.0)
	spyglass_zoom_changed.emit(spyglass_zoom)


## Format horizontal heading from `from_pos` toward `to_pos` as a 16-point maritime compass bearing
## (-Z = N, +X = E, matching `MapTableView.format_course_bearing`).
static func format_compass_bearing(from_pos: Vector3, to_pos: Vector3) -> String:
	var dx := to_pos.x - from_pos.x
	var dz := to_pos.z - from_pos.z
	if dx * dx + dz * dz < 0.25:
		return "N"
	var ang := fposmod(atan2(dx, -dz), TAU)
	var idx := int(roundf(ang / (TAU / 16.0))) % 16
	return COMPASS_16[idx]


func _scan_spyglass_sighting() -> void:
	if pawn == null or not is_inside_tree():
		return
	var eye := pawn.eye_position()
	var dir := pawn.view_dir()
	var my_ship := pawn.platform
	var best_label := ""
	var best_dist := 0.0
	var best_pos := Vector3.ZERO
	var best_score := cos(deg_to_rad(6.5))
	var r_scale := maxf(sighting_range_scale, 0.5)

	# 1. Distant ships (excluding our own), distinguishing faction & ship class.
	var max_ship_dist := 2600.0 * r_scale
	for node in get_tree().get_nodes_in_group(&"ship"):
		if not (node is Node3D) or node == my_ship:
			continue
		var s := node as Node3D
		var target_pos := s.global_position + Vector3.UP * 3.5
		var to := target_pos - eye
		var dist := to.length()
		if dist < 12.0 or dist > max_ship_dist:
			continue
		var score := to.dot(dir) / dist
		if score > best_score:
			best_score = score
			best_dist = dist
			best_pos = target_pos
			var fac: Variant = s.get(&"faction")
			var s_cls: Variant = s.get(&"ship_class")
			var is_brig: bool = (s_cls == &"brigantine")
			if fac == &"ghost":
				best_label = "Spectral Ghost Ship"
			elif fac == &"corsair":
				best_label = "Corsair Brigantine" if is_brig else "Corsair Raider"
			elif fac == &"drowned":
				best_label = "Drowned Brigantine" if is_brig else "Drowned Sloop"
			else:
				best_label = "Brigantine" if is_brig else "Sloop"

	# 2. Abyssal Leviathan world boss (group `world_events` or `leviathan`; ignore defeated).
	var max_boss_dist := 2200.0 * r_scale
	var boss_nodes: Array[Node] = []
	boss_nodes.append_array(get_tree().get_nodes_in_group(&"world_events"))
	boss_nodes.append_array(get_tree().get_nodes_in_group(&"leviathan"))
	for node in boss_nodes:
		if not (node is Node3D):
			continue
		var is_lev := (node is Leviathan) or node.is_in_group(&"leviathan")
		if not is_lev:
			continue
		var active_v: Variant = node.get(&"active")
		var defeated_v: Variant = node.get(&"_defeated")
		if (active_v is bool and not bool(active_v)) or (defeated_v is bool and bool(defeated_v)):
			continue
		var target_pos := (node as Node3D).global_position + Vector3.UP * 6.0
		var to := target_pos - eye
		var dist := to.length()
		if dist < 15.0 or dist > max_boss_dist:
			continue
		var score := to.dot(dir) / dist
		if score > best_score:
			best_score = score
			best_dist = dist
			best_pos = target_pos
			best_label = "Abyssal Leviathan"

	# 2b. Ancient Megalodon open-sea apex boss (group `megalodons`; ignore defeated).
	var max_mega_dist := 2200.0 * r_scale
	for node in get_tree().get_nodes_in_group(&"megalodons"):
		if not (node is Node3D):
			continue
		var dead_v: Variant = node.get(&"dead")
		if dead_v is bool and bool(dead_v):
			continue
		var target_pos := (node as Node3D).global_position + Vector3.UP * 3.5
		var to := target_pos - eye
		var dist := to.length()
		if dist < 12.0 or dist > max_mega_dist:
			continue
		var score := to.dot(dir) / dist
		if score > best_score:
			best_score = score
			best_dist = dist
			best_pos = target_pos
			best_label = "Ancient Megalodon"

	# 3. Living sea wildlife: Dolphin Pods, Humpback Whales, Giant Manta Rays & Ocean Sharks.
	var max_dolphin_dist := 1200.0 * r_scale
	for node in get_tree().get_nodes_in_group(&"dolphins"):
		if not (node is Node3D):
			continue
		var target_pos := (node as Node3D).global_position + Vector3.UP * 1.0
		var to := target_pos - eye
		var dist := to.length()
		if dist < 10.0 or dist > max_dolphin_dist:
			continue
		var score := to.dot(dir) / dist
		if score > best_score:
			best_score = score
			best_dist = dist
			best_pos = target_pos
			best_label = "Dolphin Pod"

	var max_whale_dist := 520.0 * r_scale
	for node in get_tree().get_nodes_in_group(&"whales"):
		if not (node is Node3D):
			continue
		var target_pos := (node as Node3D).global_position + Vector3.UP * 2.5
		var to := target_pos - eye
		var dist := to.length()
		if dist < 12.0 or dist > max_whale_dist:
			continue
		var score := to.dot(dir) / dist
		var req := 0.978 if best_label == "" else best_score
		if score >= req and (best_label == "" or score > best_score):
			best_score = score
			best_dist = dist
			best_pos = target_pos
			best_label = "Humpback Whale"

	var max_manta_dist := 120.0 * r_scale
	for node in get_tree().get_nodes_in_group(&"manta_rays"):
		if not (node is Node3D):
			continue
		var target_pos := (node as Node3D).global_position + Vector3.UP * 0.4
		var to := target_pos - eye
		var dist := to.length()
		if dist < 4.0 or dist > max_manta_dist:
			continue
		var score := to.dot(dir) / dist
		var req := 0.972 if best_label == "" else best_score
		if score >= req and (best_label == "" or score > best_score):
			best_score = score
			best_dist = dist
			best_pos = target_pos
			best_label = "Giant Manta Ray"

	var max_shark_dist := 900.0 * r_scale
	for node in get_tree().get_nodes_in_group(&"sharks"):
		if not (node is Node3D):
			continue
		var dead_v: Variant = node.get(&"dead")
		if dead_v is bool and bool(dead_v):
			continue
		var target_pos := (node as Node3D).global_position + Vector3.UP * 0.5
		var to := target_pos - eye
		var dist := to.length()
		if dist < 8.0 or dist > max_shark_dist:
			continue
		var score := to.dot(dir) / dist
		if score > best_score:
			best_score = score
			best_dist = dist
			best_pos = target_pos
			best_label = "Ocean Shark"

	# 4. Castaway Rafts (ignore rescued) & active Ironwatch Fort Batteries.
	var max_raft_dist := 1600.0 * r_scale
	for node in get_tree().get_nodes_in_group(&"castaway_rafts"):
		if not (node is Node3D):
			continue
		var rescued_v: Variant = node.get(&"is_rescued")
		if rescued_v is bool and bool(rescued_v):
			continue
		var target_pos := (node as Node3D).global_position + Vector3.UP * 2.0
		var to := target_pos - eye
		var dist := to.length()
		if dist < 10.0 or dist > max_raft_dist:
			continue
		var score := to.dot(dir) / dist
		if score > best_score:
			best_score = score
			best_dist = dist
			best_pos = target_pos
			best_label = "Castaway Raft"

	var max_wreck_dist := 2000.0 * r_scale
	for node in get_tree().get_nodes_in_group(&"sunken_shipwrecks"):
		if not (node is Node3D):
			continue
		if node.has_method(&"is_cleared") and bool(node.call(&"is_cleared")):
			continue
		var target_pos := (node as Node3D).global_position + Vector3.UP * 5.0
		var to := target_pos - eye
		var dist := to.length()
		if dist < 12.0 or dist > max_wreck_dist:
			continue
		var score := to.dot(dir) / dist
		if score > best_score:
			best_score = score
			best_dist = dist
			best_pos = target_pos
			best_label = "Sunken Shipwreck"

	var max_fort_dist := 1800.0 * r_scale
	for node in get_tree().get_nodes_in_group(&"fort_batteries"):
		if not (node is Node3D):
			continue
		var dest_v: Variant = node.get(&"destroyed")
		var siege_v: Variant = node.get(&"siege_active")
		if (dest_v is bool and bool(dest_v)) or not (siege_v is bool and bool(siege_v)):
			continue
		var target_pos := (node as Node3D).global_position + Vector3.UP * 2.0
		var to := target_pos - eye
		var dist := to.length()
		if dist < 15.0 or dist > max_fort_dist:
			continue
		var score := to.dot(dir) / dist
		if score > best_score:
			best_score = score
			best_dist = dist
			best_pos = target_pos
			best_label = "Ironwatch Fort Battery"

	# 5. All 11 Archipelago Islands (group `islands`).
	var max_island_dist := 3500.0 * r_scale
	for node in get_tree().get_nodes_in_group(&"islands"):
		if not (node is Node3D):
			continue
		var isl := node as Node3D
		var target_pos := isl.global_position + Vector3.UP * 14.0
		var to := target_pos - eye
		var dist := to.length()
		if dist < 25.0 or dist > max_island_dist:
			continue
		var score := to.dot(dir) / dist
		if score > best_score:
			best_score = score
			best_dist = dist
			best_pos = target_pos
			var nm: Variant = isl.get(&"display_name")
			if nm == null:
				nm = isl.get(&"island_name")
			if nm == null and isl.has_meta("display_name"):
				nm = isl.get_meta("display_name")
			best_label = String(nm) if nm != null else String(isl.name)

	# 6. High-altitude World Event Sky Beacons (group `world_event_clouds`).
	var max_cloud_dist := 2600.0 * r_scale
	var cloud_cone := cos(deg_to_rad(10.0))
	for node in get_tree().get_nodes_in_group(&"world_event_clouds"):
		if not (node is Node3D):
			continue
		var cloud := node as Node3D
		if not cloud.visible:
			continue
		if cloud.has_method(&"is_fading_out") and bool(cloud.call(&"is_fading_out")):
			continue
		var target_pos := cloud.global_position
		var to := target_pos - eye
		var dist := to.length()
		if dist < 25.0 or dist > max_cloud_dist:
			continue
		var score := to.dot(dir) / dist
		var req := cloud_cone if best_label == "" else best_score
		if score >= req and (best_label == "" or score > best_score):
			best_score = score
			best_dist = dist
			best_pos = target_pos
			var lbl: Variant = cloud.get(&"display_label")
			if lbl != null and String(lbl).strip_edges() != "":
				best_label = String(lbl)
			else:
				var kind_v: Variant = cloud.get(&"event_kind")
				best_label = WorldEventCloud.label_for_kind(StringName(String(kind_v))) if kind_v != null else "Fort Skull Cloud"

	var best_bearing := format_compass_bearing(eye, best_pos) if best_label != "" else ""
	_spyglass_target_pos = best_pos if best_label != "" else Vector3.ZERO
	if best_label != spyglass_sighting \
			or best_bearing != spyglass_sighting_bearing \
			or absf(best_dist - spyglass_sighting_dist) > 5.0:
		spyglass_sighting = best_label
		spyglass_sighting_dist = best_dist
		spyglass_sighting_bearing = best_bearing
		sighting_updated.emit(spyglass_sighting, spyglass_sighting_dist)


func _compass_sample_xz() -> Vector2:
	if pawn == null:
		return Vector2.ZERO
	if pawn.platform != null and is_instance_valid(pawn.platform):
		var loc := pawn.platform_local_position()
		return Vector2(loc.x, loc.z)
	return Vector2(pawn.global_position.x, pawn.global_position.z)


func _reset_compass_pacing(start_active: bool) -> void:
	compass_paces = 0
	_compass_pace_accum = 0.0
	_compass_pace_dip = 0.0
	_compass_pace_active = start_active and pawn != null
	if _compass_pace_active:
		_compass_last_platform = pawn.platform if is_instance_valid(pawn.platform) else null
		_compass_last_pos = _compass_sample_xz()
	else:
		_compass_last_platform = null
		_compass_last_pos = Vector2.ZERO


func _tick_compass(delta: float) -> void:
	_compass_pace_dip = move_toward(_compass_pace_dip, 0.0, delta * 5.5)
	if active_item != &"compass" or pawn == null:
		if _compass_pace_active or compass_paces != 0:
			_reset_compass_pacing(false)
		return

	# Step-counting pace mode while RMB is held and the Captain walks on ground/deck.
	var can_pace := _secondary_held and not pawn.dead and pawn.station == null and pawn.carried == null
	if can_pace:
		if not _compass_pace_active:
			_reset_compass_pacing(true)
		var cur_plat: PhysicsBody3D = pawn.platform if is_instance_valid(pawn.platform) else null
		var cur_xz := _compass_sample_xz()
		if cur_plat != _compass_last_platform:
			_compass_last_platform = cur_plat
			_compass_last_pos = cur_xz
		else:
			var step_dist := cur_xz.distance_to(_compass_last_pos)
			_compass_last_pos = cur_xz
			if pawn.is_grounded() and step_dist > 0.002 and step_dist < 4.0:
				var rv := pawn.get_relative_velocity()
				var horiz_spd := Vector2(rv.x, rv.z).length()
				if horiz_spd > 0.12 or step_dist > 0.006:
					_compass_pace_accum += step_dist
					while _compass_pace_accum >= COMPASS_PACE_METRES:
						_compass_pace_accum -= COMPASS_PACE_METRES
						compass_paces += 1
						_compass_pace_dip = 1.0
						var heading_str := get_compass_heading_label()
						Audio.play_sfx(&"footstep_wood", pawn.eye_position(), -11.0)
						compass_pace_counted.emit(compass_paces, heading_str)
	elif _compass_pace_active or compass_paces != 0:
		_reset_compass_pacing(false)

	# Resolve target world direction: True North (-Z) or flattened XZ vector to active chart pin.
	var target_dir_world := Vector3(0.0, 0.0, -1.0)
	if compass_pin_mode:
		var mtv := _resolve_map_table()
		if mtv == null or not mtv.has_active_pin():
			compass_pin_mode = false
			compass_mode_changed.emit(false)
		else:
			var to_pin := mtv.get_active_pin() - pawn.global_position
			to_pin.y = 0.0
			if to_pin.length_squared() > 0.0004:
				target_dir_world = to_pin.normalized()

	# Rotate target world direction into the compass node's local XZ frame!
	var ref_node := get_active_tool_node()
	var bearing_cw := atan2(target_dir_world.x, -target_dir_world.z)
	var target_angle := wrapf(-pawn.look_yaw - bearing_cw, -PI, PI)
	if ref_node != null and ref_node.is_inside_tree():
		var dir_local := ref_node.global_transform.basis.orthonormalized().inverse() * target_dir_world
		if Vector2(dir_local.x, dir_local.z).length_squared() > 0.0004:
			target_angle = atan2(-dir_local.x, -dir_local.z)

	# 2nd-order damped harmonic magnetic spring (k = 48.0, c = 6.2); snap on frame-0 / initial equip.
	if delta <= 0.0 or not _compass_needle_init:
		_compass_needle_angle = target_angle
		_compass_needle_vel = 0.0
		_compass_needle_init = true
		_compass_prev_yaw = pawn.look_yaw
	else:
		var dt := minf(delta, 0.05)
		var turn_dyaw := angle_difference(_compass_prev_yaw, pawn.look_yaw)
		_compass_prev_yaw = pawn.look_yaw

		# Gentle physical perturbation when sprinting or snapping camera turns quickly.
		var perturb_accel := 0.0
		var rv_c := pawn.get_relative_velocity()
		var h_spd := Vector2(rv_c.x, rv_c.z).length()
		if h_spd > 4.2 and pawn.is_grounded():
			var sprint_w := clampf((h_spd - 4.2) / 3.0, 0.0, 1.0)
			perturb_accel += sin(_bob_phase * 2.0) * 3.8 * sprint_w
		var turn_rate := clampf(turn_dyaw / maxf(dt, 0.008), -12.0, 12.0)
		if absf(turn_rate) > 1.2:
			perturb_accel += clampf(-turn_rate * 0.45, -4.5, 4.5)

		# Subtle Sea-of-Thieves storm magnetic interference when Weather.storminess > 0.55.
		var storm_wobble := 0.0
		if Weather != null and Weather.storminess > 0.55:
			var storm_t := clampf((Weather.storminess - 0.55) / 0.45, 0.0, 1.0)
			storm_wobble = (
				sin(_clock * 3.7) * 0.18
				+ cos(_clock * 7.1 + 1.3) * 0.11
				+ sin(_clock * 11.9 - 0.7) * 0.06
			) * storm_t

		var desired_angle := wrapf(target_angle + storm_wobble, -PI, PI)
		var err := wrapf(desired_angle - _compass_needle_angle, -PI, PI)
		_compass_needle_vel += (err * 48.0 - _compass_needle_vel * 6.2 + perturb_accel) * dt
		_compass_needle_angle = wrapf(_compass_needle_angle + _compass_needle_vel * dt, -PI, PI)

	for n in [fp_tool_node, tp_tool_node]:
		if n != null and is_instance_valid(n):
			var comp_node := n as Node3D
			var needle := comp_node.get_node_or_null(^"Needle") as Node3D
			if needle != null:
				needle.rotation.y = _compass_needle_angle
			ToolMeshes.set_compass_pin_mode(comp_node, compass_pin_mode)


func _tick_concertina(delta: float) -> void:
	if active_item != &"instrument":
		_whistle_rot_deg = Vector3.ZERO
		return
	if playing_shanty:
		var audio_beat := Audio.shanty_beat() if Audio.is_shanty_playing() else -1.0
		if audio_beat >= 0.0 and absf(audio_beat - _last_shanty_audio_beat) > 0.0001:
			var wrapped := _last_shanty_audio_beat >= 0.0 and audio_beat < _last_shanty_audio_beat - 1.0
			_last_shanty_audio_beat = audio_beat
			if wrapped or audio_beat > _shanty_phase:
				_shanty_phase = audio_beat
			else:
				_shanty_phase += delta * 2.0
		else:
			_shanty_phase += delta * 2.0

	match shanty_instrument:
		&"concertina":
			_whistle_rot_deg = Vector3.ZERO
			var stretch := 0.5 + 0.48 * sin(_shanty_phase * PI) if playing_shanty else 0.5
			ToolMeshes.set_concertina_stretch(fp_tool_node, stretch)
			ToolMeshes.set_concertina_stretch(tp_tool_node, stretch)
			ToolMeshes.update_shanty_notes(fp_tool_node, delta, playing_shanty, _clock)
			ToolMeshes.update_shanty_notes(tp_tool_node, delta, playing_shanty, _clock)
		&"hurdy_gurdy":
			_whistle_rot_deg = Vector3.ZERO
			if playing_shanty:
				var crank_rad := _shanty_phase * TAU * 0.5
				ToolMeshes.set_hurdy_gurdy_crank(fp_tool_node, crank_rad)
				ToolMeshes.set_hurdy_gurdy_crank(tp_tool_node, crank_rad)
			ToolMeshes.update_shanty_notes(fp_tool_node, delta, playing_shanty, _clock)
			ToolMeshes.update_shanty_notes(tp_tool_node, delta, playing_shanty, _clock)
		&"whistle":
			if playing_shanty:
				var sway_deg := sin(_shanty_phase * PI) * 9.0
				var nod_deg := sin(_shanty_phase * TAU) * 4.8
				_whistle_rot_deg = Vector3(nod_deg, sway_deg, sway_deg * 0.5)
			else:
				_whistle_rot_deg = Vector3.ZERO
			if tp_tool_node != null and is_instance_valid(tp_tool_node):
				tp_tool_node.rotation_degrees = _whistle_rot_deg


func _tick_cutlass_gleam(delta: float) -> void:
	var pawn_dead := pawn != null and is_instance_valid(pawn) and pawn.dead
	if pawn_dead:
		_cutlass_gleam_timer = 0.0
		_cutlass_gleam_peak = 0.0
	elif _cutlass_gleam_timer > 0.0:
		_cutlass_gleam_timer = maxf(0.0, _cutlass_gleam_timer - maxf(delta, 0.0))
		if _cutlass_gleam_timer <= 0.0:
			_cutlass_gleam_peak = 0.0
	if active_item == &"cutlass" and melee_weapon == &"cutlass":
		var strength := get_cutlass_gleam_strength()
		var slide := clampf(1.0 - (_cutlass_gleam_timer / CUTLASS_GLEAM_DURATION), 0.0, 1.0) if _cutlass_gleam_timer > 0.0 else 1.0
		ToolMeshes.update_cutlass_gleam(fp_tool_node, strength, slide)
		ToolMeshes.update_cutlass_gleam(tp_tool_node, strength, slide)


func _tick_lantern_flicker(delta: float = 0.0) -> void:
	_lantern_signal_cd = maxf(0.0, _lantern_signal_cd - delta)
	_lantern_signal_flash = move_toward(_lantern_signal_flash, 0.0, delta / 0.35)
	var want_flare := (active_item == &"lantern") and lantern_lit and _secondary_held
	if delta > 0.0:
		_lantern_flare_blend = lerpf(_lantern_flare_blend, 1.0 if want_flare else 0.0, 1.0 - exp(-8.5 * delta))
	else:
		_lantern_flare_blend = 1.0 if want_flare else 0.0
	var halo_tint := Color(1.0, 0.90, 0.68) if tool_variant_id == &"tool_storm_lantern" else Color(1.0, 0.72, 0.30)
	if active_item != &"lantern" or not lantern_lit:
		_lantern_halo_energy = 0.0
		if active_item == &"lantern":
			if fp_tool_node != null and is_instance_valid(fp_tool_node):
				ToolMeshes.set_lantern_halo_style(fp_tool_node, 0.0, halo_tint, 0.24)
			if tp_tool_node != null and is_instance_valid(tp_tool_node):
				ToolMeshes.set_lantern_halo_style(tp_tool_node, 0.0, halo_tint, 0.42)
		return
	var flick := 0.93 + 0.07 * sin(_clock * 11.4) * cos(_clock * 7.3)
	var base_energy := lerpf(2.4, 4.3, _lantern_flare_blend) * flick
	var final_energy := lerpf(base_energy, 6.5, _lantern_signal_flash)
	var final_range := lerpf(12.0, 22.0, maxf(_lantern_flare_blend, _lantern_signal_flash))
	var flame_boost := 1.0 + _lantern_flare_blend * 0.24 + _lantern_signal_flash * 0.55

	# Smooth atmospheric FlameHalo intensity driven by darkness + storminess + raised lantern flare.
	var day_f := Weather.daylight() if Weather != null else 1.0
	var storm_f := Weather.storminess if Weather != null else 0.0
	var night := clampf(1.0 - day_f, 0.0, 1.0)
	var atmos := clampf(night + storm_f * 0.35, 0.0, 1.25)
	var target_halo := (0.12 + atmos * 0.72 + _lantern_flare_blend * 0.32 + _lantern_signal_flash * 0.45) * flick
	if delta > 0.0:
		_lantern_halo_energy = lerpf(_lantern_halo_energy, target_halo, 1.0 - exp(-10.0 * delta))
	else:
		_lantern_halo_energy = target_halo
	var fp_halo_scale := lerpf(0.24, 0.32, clampf(_lantern_flare_blend * 0.75 + _lantern_signal_flash * 0.50, 0.0, 1.0))
	if fp_tool_node != null and is_instance_valid(fp_tool_node):
		ToolMeshes.set_lantern_halo_style(fp_tool_node, _lantern_halo_energy, halo_tint, fp_halo_scale)
	if tp_tool_node != null and is_instance_valid(tp_tool_node):
		ToolMeshes.set_lantern_halo_style(tp_tool_node, _lantern_halo_energy, halo_tint, 0.42)

	var target_node: Node3D = fp_tool_node if (fp_tool_node != null and is_instance_valid(fp_tool_node)) else tp_tool_node
	if target_node != null and is_instance_valid(target_node):
		var light := target_node.get_node_or_null(^"LanternLight") as OmniLight3D
		if light != null:
			light.light_energy = final_energy
			light.omni_range = final_range
		var flame := target_node.get_node_or_null(^"Flame") as Node3D
		if flame != null:
			flame.scale = Vector3(flame_boost, (0.92 + 0.14 * sin(_clock * 15.0)) * flame_boost, flame_boost)


func _tick_viewmodel_pose(delta: float) -> void:
	if fp_tool_node == null or not is_instance_valid(fp_tool_node):
		return
	var dt := clampf(delta, 0.0001, 0.05)
	var pose_id := get_resolved_tool_id(active_item)
	var pose: Array = FP_POSES.get(pose_id, FP_POSES.get(active_item, FP_POSES[&"cutlass"]))
	var rest_pos: Vector3 = pose[0]
	var rest_rot: Vector3 = pose[1]
	var raise_pos: Vector3 = pose[2]
	var raise_rot: Vector3 = pose[3]
	var sc: float = float(pose[4])

	var want_raise := playing_shanty if active_item == &"instrument" else _secondary_held
	# Snappy parry guard raise for melee; smooth deliberate lift for ADS/spyglass/map/lantern.
	var raise_rate := 18.0 if (active_item == &"cutlass" and want_raise) else 11.5
	_raise_blend = lerpf(_raise_blend, 1.0 if want_raise else 0.0, 1.0 - exp(-raise_rate * dt))
	_equip_dip = move_toward(_equip_dip, 0.0, dt * 3.1)

	# 1. Inertial Mouse-Look Sway (angle_difference wrapped) & Ship-Roll Lean!
	if pawn != null and is_instance_valid(pawn):
		if not _look_tracking_init:
			_prev_look_yaw = pawn.look_yaw
			_prev_look_pitch = pawn.look_pitch
			_look_tracking_init = true
		var dyaw := angle_difference(_prev_look_yaw, pawn.look_yaw)
		var dpitch := pawn.look_pitch - _prev_look_pitch
		_prev_look_yaw = pawn.look_yaw
		_prev_look_pitch = pawn.look_pitch
		var target_sway_y := clampf(dyaw / dt * 0.14, -1.0, 1.0)
		var target_sway_p := clampf(dpitch / dt * 0.14, -1.0, 1.0)
		var sway_k := 1.0 - exp(-11.5 * dt)
		_sway_yaw = lerpf(_sway_yaw, target_sway_y, sway_k)
		_sway_pitch = lerpf(_sway_pitch, target_sway_p, sway_k)
	else:
		var decay_k := 1.0 - exp(-10.0 * dt)
		_sway_yaw = lerpf(_sway_yaw, 0.0, decay_k)
		_sway_pitch = lerpf(_sway_pitch, 0.0, decay_k)

	var target_ship_roll := 0.0
	if pawn != null and is_instance_valid(pawn) and pawn.platform is Ship and is_instance_valid(pawn.platform):
		var ship_node := pawn.platform as Node3D
		var ship_up := ship_node.global_basis.y.normalized()
		var cam_right := Basis(Vector3.UP, pawn.look_yaw).x
		var deck_tilt := clampf(ship_up.dot(cam_right), -0.45, 0.45)
		var z_roll := clampf(ship_node.rotation.z, -0.45, 0.45)
		target_ship_roll = deck_tilt if absf(deck_tilt) > 0.005 else z_roll
	_ship_roll_lag = lerpf(_ship_roll_lag, target_ship_roll, 1.0 - exp(-6.5 * dt))

	# 2. Organic 2-Harmonic Idle Breathing, Classic Figure-8 Walk/Sprint Stride & Sprint Cant.
	var move_spd := 0.0
	var grounded := false
	if pawn != null and is_instance_valid(pawn):
		var rv := pawn.get_relative_velocity()
		move_spd = Vector2(rv.x, rv.z).length()
		grounded = pawn.is_grounded()
	var is_moving := move_spd > 0.35 and grounded
	if is_moving:
		var stride_freq := lerpf(3.2, 4.1, clampf((move_spd - 3.0) / 3.5, 0.0, 1.0))
		_bob_phase = fmod(_bob_phase + move_spd * dt * stride_freq, TAU)
	var want_sprint := (move_spd > 4.6 and is_moving and _raise_blend < 0.15 and _swing_timer <= 0.0)
	_sprint_blend = lerpf(_sprint_blend, 1.0 if want_sprint else 0.0, 1.0 - exp(-8.0 * dt))

	var is_aim_tool := active_item == &"pistol" or active_item == &"spyglass" or active_item == &"map"
	var bob_amp := lerpf(1.0, 0.12 if is_aim_tool else 0.24, _raise_blend)
	var sway_amp := lerpf(1.0, 0.20 if is_aim_tool else 0.48, _raise_blend)

	var breath_wave := sin(_clock * 1.9) + 0.35 * sin(_clock * 3.8 + 0.4)
	var move_w := clampf(move_spd / 4.2, 0.0, 1.25) if is_moving else 0.0
	var fig8_x := cos(_bob_phase) * 0.016 * move_w * bob_amp
	var fig8_y := sin(_bob_phase * 2.0) * 0.011 * move_w * bob_amp
	var fig8_roll := -cos(_bob_phase) * 2.3 * move_w * bob_amp
	var fig8_pitch := sin(_bob_phase * 2.0) * 1.4 * move_w * bob_amp

	# Base rest-to-raise S-curve blend.
	var raise_s := smoothstep(0.0, 1.0, _raise_blend)
	var pos := rest_pos.lerp(raise_pos, raise_s)
	var rot_deg := rest_rot.lerp(raise_rot, raise_s)
	var scale_vec := Vector3.ONE * sc

	# Layer breathing, figure-8 stride, sprint cant, inertial mouse sway, and ship-roll lean!
	pos += Vector3(
		cos(_clock * 0.95) * 0.0022 * bob_amp + fig8_x + _sway_yaw * 0.032 * sway_amp + _ship_roll_lag * 0.048 * bob_amp,
		breath_wave * 0.0042 * bob_amp + fig8_y - _sway_pitch * 0.024 * sway_amp - absf(_ship_roll_lag) * 0.014 * bob_amp,
		0.0
	)
	rot_deg += Vector3(
		breath_wave * 0.65 * bob_amp + fig8_pitch - _sway_pitch * 5.5 * sway_amp,
		_sway_yaw * 6.5 * sway_amp,
		fig8_roll - _sway_yaw * 5.2 * sway_amp - _ship_roll_lag * 11.5 * bob_amp
	)
	if _sprint_blend > 0.001:
		pos += Vector3(-0.046, -0.042, 0.020) * _sprint_blend
		rot_deg += Vector3(-11.0, 14.0, 13.0) * _sprint_blend

	# 3. Elastic Overshoot Equip Draw-Up (_equip_dip 1 -> 0).
	if _equip_dip > 0.0005:
		var draw_t := 1.0 - clampf(_equip_dip, 0.0, 1.0)
		var drop := 1.0 - smoothstep(0.0, 0.84, draw_t)
		var settle_u := clampf((draw_t - 0.52) / 0.48, 0.0, 1.0)
		var overshoot := sin(settle_u * PI) * 0.022
		pos += Vector3(0.042 * drop, -0.26 * drop + overshoot, 0.095 * drop)
		rot_deg += Vector3(-44.0 * drop + overshoot * 155.0, -14.0 * drop, -12.0 * drop)

	# 4. Bespoke Continuous Per-Tool Polish (Spyglass twist, Compass tilt/pace, Map flutter, Lantern pendulum, Shanty sway).
	match active_item:
		&"cutlass":
			if _raise_blend > 0.02:
				var guard_snap := sin(clampf(_raise_blend, 0.0, 1.0) * PI)
				rot_deg.z += guard_snap * 6.5
		&"spyglass":
			var twist := sin(clampf(_raise_blend, 0.0, 1.0) * PI)
			rot_deg.z += twist * 18.0
			pos.z -= twist * 0.025
		&"compass":
			rot_deg.z -= sin(clampf(_raise_blend, 0.0, 1.0) * PI) * 8.5
			if _compass_pace_dip > 0.001:
				var pu := 1.0 - clampf(_compass_pace_dip, 0.0, 1.0)
				var dip := sin(pu * PI) - 0.25 * sin(pu * TAU) * (1.0 - pu)
				pos += Vector3(0.0, -0.022 * dip, 0.008 * dip)
				rot_deg += Vector3(-7.0 * dip, 0.0, 2.2 * dip)
		&"map":
			var wind_f := 1.0
			if Weather != null:
				wind_f = clampf(Weather.wind_speed / 8.0, 0.65, 2.1)
			var flutter := (sin(_clock * 4.7) * 0.95 + sin(_clock * 8.3 + 0.8) * 0.42) * wind_f
			rot_deg.x += flutter
			rot_deg.z += cos(_clock * 3.9) * 0.65 * wind_f
			scale_vec.x = sc * lerpf(0.95, 1.04, raise_s)
		&"lantern":
			_tick_lantern_pendulum(dt, move_w)
			rot_deg.z += _lantern_pendulum_z
			rot_deg.x += _lantern_pendulum_x
		&"instrument":
			if playing_shanty:
				var beat_sway := sin(_shanty_phase * PI * 0.5)
				var beat_bounce := absf(sin(_shanty_phase * PI))
				pos += Vector3(beat_sway * 0.024, beat_bounce * 0.014, 0.0)
				rot_deg += Vector3(sin(_shanty_phase * PI) * 3.5, cos(_shanty_phase * PI * 0.5) * 4.8, beat_sway * 7.2)
			if shanty_instrument == &"whistle":
				rot_deg += _whistle_rot_deg

	# 5. Smooth Post-Shot Reload Dip Cycle for Flintlock Pistol / Blunderbuss.
	if _reload_timer > 0.0:
		_reload_timer = maxf(0.0, _reload_timer - dt)
		if active_item == &"pistol":
			var r_elapsed := _reload_dur - _reload_timer
			var dip_delay := 0.26 if pose_id == &"blunderbuss" else 0.20
			if r_elapsed > dip_delay and _reload_dur > dip_delay + 0.05:
				var ru := clampf((r_elapsed - dip_delay) / (_reload_dur - dip_delay), 0.0, 1.0)
				var rel_off := _eval_reload_pose(ru, pose_id == &"blunderbuss")
				pos += rel_off[0] as Vector3
				rot_deg += rel_off[1] as Vector3

	# 6. Multi-Phase Bespoke Per-Tool Action Curves (Anticipation -> Snap -> Follow-Through -> Elastic Settle).
	if _swing_timer > 0.0:
		_swing_timer = maxf(0.0, _swing_timer - dt)
		var u := clampf(1.0 - (_swing_timer / maxf(_swing_dur, 0.001)), 0.0, 1.0)
		var sw := _eval_tool_swing(_swing_kind, u, pose_id, pos, rot_deg)
		pos = sw[0] as Vector3
		rot_deg = sw[1] as Vector3

	# 7. Coiled-Back Heavy Lunge Charge Windup with Muscular Tension Tremble!
	if active_item == &"cutlass" and _primary_was_down and not _heavy_fired_this_hold and _primary_hold_time > 0.06:
		var ch := clampf((_primary_hold_time - 0.06) / (HEAVY_HOLD_TIME - 0.06), 0.0, 1.0)
		var ch_e := smoothstep(0.0, 1.0, ch)
		var tremble := sin(_clock * 58.0) * 0.0055 * ch_e * ch_e
		pos += Vector3(0.12 * ch_e + tremble, 0.055 * ch_e + tremble * 0.6, 0.13 * ch_e)
		rot_deg += Vector3(22.0 * ch_e, -32.0 * ch_e, -26.0 * ch_e + tremble * 220.0)

	fp_tool_node.position = pos
	fp_tool_node.rotation_degrees = rot_deg
	fp_tool_node.scale = scale_vec


func _tick_lantern_pendulum(dt: float, move_w: float) -> void:
	var target_z := clampf(-_sway_yaw * 16.0 - cos(_bob_phase) * 7.5 * move_w - _ship_roll_lag * 22.0, -24.0, 24.0)
	var target_x := clampf(-_sway_pitch * 11.0 + sin(_bob_phase * 2.0) * 4.5 * move_w, -18.0, 18.0)
	var acc_z := (target_z - _lantern_pendulum_z) * 28.0 - _lantern_pendulum_vz * 5.2
	var acc_x := (target_x - _lantern_pendulum_x) * 28.0 - _lantern_pendulum_vx * 5.2
	_lantern_pendulum_vz += acc_z * dt
	_lantern_pendulum_vx += acc_x * dt
	_lantern_pendulum_z = clampf(_lantern_pendulum_z + _lantern_pendulum_vz * dt, -28.0, 28.0)
	_lantern_pendulum_x = clampf(_lantern_pendulum_x + _lantern_pendulum_vx * dt, -22.0, 22.0)


static func _eval_reload_pose(ru: float, is_blunderbuss: bool) -> Array:
	var heavy := 1.20 if is_blunderbuss else 1.0
	var dip_p := Vector3(-0.085, -0.175, 0.060) * heavy
	var dip_r := Vector3(-28.0, 24.0, 28.0) * heavy
	var p := Vector3.ZERO
	var r := Vector3.ZERO
	if ru < 0.22:
		var t := smoothstep(0.0, 1.0, ru / 0.22)
		p = Vector3.ZERO.lerp(dip_p, t)
		r = Vector3.ZERO.lerp(dip_r, t)
	elif ru < 0.72:
		var t := (ru - 0.22) / 0.50
		# Two tactile ramrod/powder-tamp nods plus subtle flint-cock twist.
		var tamp := sin(t * PI * 2.0)
		var cock := sin(clampf((t - 0.62) / 0.38, 0.0, 1.0) * PI)
		p = dip_p + Vector3(0.012 * cock, -0.028 * absf(tamp) + 0.016 * cock, 0.018 * tamp)
		r = dip_r + Vector3(-10.0 * absf(tamp) + 12.0 * cock, -6.0 * cock, -8.0 * cock)
	elif ru < 0.89:
		var t := smoothstep(0.0, 1.0, (ru - 0.72) / 0.17)
		var over_p := Vector3(0.0, 0.018, -0.012)
		var over_r := Vector3(4.5, -2.0, -3.0)
		p = dip_p.lerp(over_p, t)
		r = dip_r.lerp(over_r, t)
	else:
		var t := smoothstep(0.0, 1.0, (ru - 0.89) / 0.11)
		p = Vector3(0.0, 0.018, -0.012).lerp(Vector3.ZERO, t)
		r = Vector3(4.5, -2.0, -3.0).lerp(Vector3.ZERO, t)
	return [p, r]


static func _eval_keyed_curve(
	u: float,
	t1: float, p1: Vector3, r1: Vector3,
	t2: float, p2: Vector3, r2: Vector3,
	t3: float, p3: Vector3, r3: Vector3
) -> Array:
	if u < t1:
		var k1 := smoothstep(0.0, 1.0, u / maxf(t1, 0.001))
		return [Vector3.ZERO.lerp(p1, k1), Vector3.ZERO.lerp(r1, k1)]
	if u < t2:
		# Fast explosive strike transition!
		var k2 := pow(clampf((u - t1) / maxf(t2 - t1, 0.001), 0.0, 1.0), 0.56)
		return [p1.lerp(p2, k2), r1.lerp(r2, k2)]
	if u < t3:
		var k3 := smoothstep(0.0, 1.0, (u - t2) / maxf(t3 - t2, 0.001))
		return [p2.lerp(p3, k3), r2.lerp(r3, k3)]
	var k4 := smoothstep(0.0, 1.0, (u - t3) / maxf(1.0 - t3, 0.001))
	return [p3.lerp(Vector3.ZERO, k4), r3.lerp(Vector3.ZERO, k4)]


static func _eval_tool_swing(
	kind: StringName,
	u: float,
	pose_id: StringName,
	base_pos: Vector3,
	base_rot: Vector3
) -> Array:
	var pos := base_pos
	var rot := base_rot
	var axe_w := 1.22 if pose_id == &"boarding_axe" else 1.0

	match kind:
		&"slash", &"slash_1":
			# High-right diagonal cleave: windup up-right -> explosive cleave down-left -> heavy drag -> settle.
			var res := _eval_keyed_curve(
				u,
				0.24, Vector3(0.11, 0.11, 0.06) * axe_w, Vector3(26.0, -24.0, -28.0) * axe_w,
				0.52, Vector3(-0.34, -0.13, -0.18) * axe_w, Vector3(-60.0, 54.0, 48.0) * axe_w,
				0.74, Vector3(-0.26, -0.17, -0.10) * axe_w, Vector3(-48.0, 44.0, 36.0) * axe_w
			)
			pos += res[0] as Vector3
			rot += res[1] as Vector3
		&"slash_2":
			# Snappy low-left backhand sweep: coil low-left -> whip diagonally up-right -> flourish -> settle.
			var res := _eval_keyed_curve(
				u,
				0.22, Vector3(-0.24, -0.10, 0.04) * axe_w, Vector3(-14.0, 48.0, 44.0) * axe_w,
				0.50, Vector3(0.16, 0.07, -0.18) * axe_w, Vector3(-34.0, -52.0, -46.0) * axe_w,
				0.72, Vector3(0.11, 0.04, -0.09) * axe_w, Vector3(-22.0, -38.0, -32.0) * axe_w
			)
			pos += res[0] as Vector3
			rot += res[1] as Vector3
		&"slash_3":
			# Wide cross-cut finisher: deep horizontal windup -> tearing cross-screen cut -> dramatic hold -> settle.
			var res := _eval_keyed_curve(
				u,
				0.28, Vector3(0.16, 0.07, 0.09) * axe_w, Vector3(16.0, -44.0, -58.0) * axe_w,
				0.58, Vector3(-0.42, -0.02, -0.24) * axe_w, Vector3(-36.0, 78.0, 76.0) * axe_w,
				0.78, Vector3(-0.33, -0.06, -0.14) * axe_w, Vector3(-28.0, 64.0, 60.0) * axe_w
			)
			pos += res[0] as Vector3
			rot += res[1] as Vector3
		&"heavy":
			# Coiled heavy lunge: deep pull-back -> explosive forward thrust/cleave -> extended follow -> breath recovery.
			var strike_p := Vector3(-0.14, -0.04, -0.32) if pose_id == &"boarding_axe" else Vector3(-0.18, 0.03, -0.34)
			var strike_r := Vector3(-84.0, 32.0, 26.0) if pose_id == &"boarding_axe" else Vector3(-74.0, 24.0, 18.0)
			var res := _eval_keyed_curve(
				u,
				0.22, Vector3(0.14, 0.07, 0.14) * axe_w, Vector3(26.0, -36.0, -30.0) * axe_w,
				0.48, strike_p, strike_r,
				0.72, Vector3(-0.22, -0.06, -0.22), Vector3(-62.0, 34.0, 28.0)
			)
			pos += res[0] as Vector3
			rot += res[1] as Vector3
		&"parry_clang":
			var res := _eval_keyed_curve(
				u,
				0.18, Vector3(0.05, 0.04, 0.08), Vector3(16.0, -14.0, -18.0),
				0.52, Vector3(-0.02, 0.01, -0.03), Vector3(-6.0, 6.0, 8.0),
				0.78, Vector3(0.01, 0.0, 0.01), Vector3(2.0, -2.0, -2.0)
			)
			pos += res[0] as Vector3
			rot += res[1] as Vector3
		&"pistol", &"blunderbuss":
			# Sharp recoil snap-back + muzzle flip + controlled spring dip settle.
			var kick := 1.45 if kind == &"blunderbuss" else 1.0
			var res := _eval_keyed_curve(
				u,
				0.15, Vector3(0.008 * kick, 0.062 * kick, 0.105 * kick), Vector3(34.0 * kick, 0.0, -5.0 * kick),
				0.56, Vector3(0.0, -0.012 * kick, 0.018 * kick), Vector3(-4.5 * kick, 0.0, 2.0 * kick),
				0.82, Vector3(0.0, 0.004 * kick, -0.004), Vector3(1.5, 0.0, 0.0)
			)
			pos += res[0] as Vector3
			rot += res[1] as Vector3
		&"dig":
			# Deep back-swing anticipation -> forceful downward plunge -> upward dirt-heave flick!
			var res := _eval_keyed_curve(
				u,
				0.24, Vector3(0.08, 0.11, 0.12), Vector3(26.0, -16.0, -14.0),
				0.52, Vector3(-0.11, -0.24, -0.24), Vector3(-66.0, 14.0, 12.0),
				0.78, Vector3(-0.15, 0.07, -0.14), Vector3(22.0, 28.0, 22.0)
			)
			pos += res[0] as Vector3
			rot += res[1] as Vector3
		&"scoop":
			# Low scoop dip -> heavy water-laden lift -> sloshing settle.
			var res := _eval_keyed_curve(
				u,
				0.36, Vector3(-0.07, -0.22, -0.16), Vector3(42.0, 4.0, 6.0),
				0.70, Vector3(-0.02, 0.05, -0.04), Vector3(-12.0, -4.0, -5.0),
				0.88, Vector3(0.0, -0.02, 0.0), Vector3(5.0, 0.0, 2.0)
			)
			pos += res[0] as Vector3
			rot += res[1] as Vector3
		&"splash":
			# Back coil -> snappy forward water-throw arc -> follow-through.
			var res := _eval_keyed_curve(
				u,
				0.22, Vector3(0.04, -0.06, 0.10), Vector3(22.0, -6.0, 4.0),
				0.54, Vector3(-0.10, 0.04, -0.24), Vector3(-58.0, 6.0, -6.0),
				0.78, Vector3(-0.08, -0.04, -0.14), Vector3(-36.0, 4.0, -4.0)
			)
			pos += res[0] as Vector3
			rot += res[1] as Vector3
		&"hammer":
			# Two-handed board-press + rhythmic 3-beat hammering recoil!
			var press_env := smoothstep(0.0, 0.14, u) * (1.0 - smoothstep(0.84, 1.0, u))
			var beat_u := clampf((u - 0.10) / 0.74, 0.0, 1.0) * 3.0
			var frac := fmod(beat_u, 1.0)
			# Asymmetric strike-and-recoil spike per hammer beat!
			var strike := pow(sin(clampf(frac / 0.45, 0.0, 1.0) * PI), 1.6) if frac < 0.45 else -sin((frac - 0.45) / 0.55 * PI) * 0.22
			pos += Vector3(-0.06 * press_env, -0.02 * press_env - 0.045 * strike * press_env, -0.14 * press_env - 0.075 * strike * press_env)
			rot += Vector3(-12.0 * press_env - 26.0 * strike * press_env, 8.0 * press_env, -5.0 * strike * press_env)
		&"drink":
			# Hearty raise-and-tilt chug with rhythmic gulp nods!
			var target_p := Vector3(0.04, -0.01, -0.24)
			var target_r := Vector3(60.0, -8.0, -16.0)
			var lift := smoothstep(0.0, 0.24, u) * (1.0 - smoothstep(0.74, 1.0, u))
			var gulp := 0.0
			if u > 0.24 and u < 0.74:
				gulp = sin((u - 0.24) / 0.50 * TAU * 1.5)
			pos = pos.lerp(target_p + Vector3(0.0, 0.010 * gulp, -0.008 * gulp), lift)
			rot = rot.lerp(target_r + Vector3(5.5 * gulp, 0.0, -3.5 * gulp), lift)
		&"toast":
			# Quick dip -> celebratory high toast thrust -> proud cheer hold -> settle.
			var res := _eval_keyed_curve(
				u,
				0.20, Vector3(0.02, -0.05, 0.04), Vector3(10.0, 2.0, 4.0),
				0.52, Vector3(-0.09, 0.12, -0.16), Vector3(-20.0, -10.0, -18.0),
				0.76, Vector3(-0.08, 0.11, -0.14), Vector3(-16.0, -8.0, -15.0)
			)
			pos += res[0] as Vector3
			rot += res[1] as Vector3
		&"click":
			var res := _eval_keyed_curve(
				u,
				0.25, Vector3(0.0, 0.026, -0.020), Vector3(14.0, -4.0, -6.0),
				0.60, Vector3(0.0, -0.010, 0.006), Vector3(-5.0, 2.0, 3.0),
				0.82, Vector3.ZERO, Vector3.ZERO
			)
			pos += res[0] as Vector3
			rot += res[1] as Vector3
		_:
			# Inspect / glance lift (compass pin toggle, map glance, trumpet hail).
			var res := _eval_keyed_curve(
				u,
				0.32, Vector3(-0.03, 0.055, -0.055), Vector3(14.0, -6.0, -5.0),
				0.68, Vector3(-0.02, 0.040, -0.040), Vector3(10.0, -4.0, -3.0),
				0.86, Vector3.ZERO, Vector3.ZERO
			)
			pos += res[0] as Vector3
			rot += res[1] as Vector3
	return [pos, rot]


func _get_station_kind() -> StringName:
	if pawn == null or not is_instance_valid(pawn) or pawn.station == null or not is_instance_valid(pawn.station):
		return &""
	var kind_v: Variant = pawn.station.get(&"kind")
	return StringName(kind_v) if kind_v != null else &""


func _get_station_ship() -> Node3D:
	if pawn == null or not is_instance_valid(pawn) or pawn.station == null or not is_instance_valid(pawn.station):
		return null
	var st_ship: Variant = pawn.station.get(&"ship")
	if st_ship is Node3D and is_instance_valid(st_ship):
		return st_ship as Node3D
	if pawn.platform is Node3D and is_instance_valid(pawn.platform):
		return pawn.platform as Node3D
	return null


func _get_action_hand_mode() -> StringName:
	if pawn == null or not is_instance_valid(pawn) or pawn.dead:
		return &""
	var showing_trumpet := _fp_trumpet_node != null and is_instance_valid(_fp_trumpet_node) and _trumpet_display_timer > 0.0
	if showing_trumpet and pawn.station == null:
		return &""
	if pawn.carried != null and is_instance_valid(pawn.carried):
		return &"carry"
	if pawn.station != null and is_instance_valid(pawn.station):
		var sk := _get_station_kind()
		if ACTION_HAND_STATIONS.has(sk):
			return sk
	if pawn.station == null and pawn.carried == null:
		if pawn.mode == Pawn.Mode.SWIM:
			return &"swim"
		if pawn.mode == Pawn.Mode.LADDER:
			return &"ladder"
	return &""


func _tick_action_hands(delta: float) -> void:
	if fp_action_hands == null or not is_instance_valid(fp_action_hands):
		return
	if _fp_action_left == null or not is_instance_valid(_fp_action_left):
		_fp_action_left = fp_action_hands.get_node_or_null(^"LeftHand") as Node3D
	if _fp_action_right == null or not is_instance_valid(_fp_action_right):
		_fp_action_right = fp_action_hands.get_node_or_null(^"RightHand") as Node3D
	if _fp_action_left == null or _fp_action_right == null:
		return

	var mode := _get_action_hand_mode()
	if mode == &"":
		_action_mode = &""
		_action_pose_init = false
		_action_enter_blend = 0.0
		return

	var dt := clampf(delta, 0.0, 0.05)
	var st_ship := _get_station_ship()
	if mode != _action_mode or not _action_pose_init:
		_action_mode = mode
		_action_pose_init = true
		_action_enter_blend = 0.0
		_action_helm_vel = 0.0
		_action_helm_cycle = 0.0
		_action_anchor_phase = 0.0
		_action_anchor_effort = 0.0
		_action_rope_phase = 0.0
		_action_rope_effort = 0.0
		_action_bilge_phase = 0.0
		_action_bilge_effort = 0.0
		_action_oar_phase_l = 0.0
		_action_oar_phase_r = 0.0
		_action_oar_effort_l = 0.0
		_action_oar_effort_r = 0.0
		_action_swim_phase = 0.0
		_action_swim_blend = 0.0
		_action_ladder_phase = 0.45
		_action_ladder_effort = 0.0
		if pawn != null and is_instance_valid(pawn):
			_action_prev_ladder_y = pawn.global_position.y if pawn.is_inside_tree() else pawn.position.y
		else:
			_action_prev_ladder_y = 0.0
		if st_ship != null:
			var h_v: Variant = st_ship.get(&"helm")
			_action_prev_helm = float(h_v) if h_v != null else 0.0
			var a_v: Variant = st_ship.get(&"anchor_progress")
			_action_prev_anchor = float(a_v) if a_v != null else 0.0
			var ss_v: Variant = st_ship.get(&"sail_set")
			_action_prev_sail_set = float(ss_v) if ss_v != null else 0.0
			var st_v: Variant = st_ship.get(&"sail_trim")
			_action_prev_sail_trim = float(st_v) if st_v != null else 0.0
			var w_v: Variant = st_ship.get(&"water_level")
			_action_prev_water = float(w_v) if w_v != null else 0.0
		else:
			_action_prev_helm = 0.0
			_action_prev_anchor = 0.0
			_action_prev_sail_set = 0.0
			_action_prev_sail_trim = 0.0
			_action_prev_water = 0.0

	if dt > 0.0:
		_action_enter_blend = move_toward(_action_enter_blend, 1.0, dt * 7.2)
	else:
		_action_enter_blend = 1.0
	var enter_s := smoothstep(0.0, 1.0, _action_enter_blend)
	var enter_drop := (1.0 - enter_s) * 0.082
	var breath := sin(_clock * 1.9) + 0.35 * sin(_clock * 3.8 + 0.4)
	var smooth_dt := maxf(dt, 0.016)

	var l_pos := Vector3(-0.24, -0.26, -0.46)
	var r_pos := Vector3(0.24, -0.26, -0.46)
	var l_rot := Vector3(12.0, -14.0, 0.0)
	var r_rot := Vector3(12.0, 14.0, 0.0)

	match mode:
		&"helm":
			# 1. Ship's Wheel: grip left & right rim cleanly in lower corners so the
			#    center King Spoke & fixed brass rudder-indicator arch stay 100% clear.
			var helm_val := 0.0
			if st_ship != null:
				var hv: Variant = st_ship.get(&"helm")
				if hv != null:
					helm_val = clampf(float(hv), -1.0, 1.0)
			var d_helm := clampf(helm_val - _action_prev_helm, -0.35, 0.35)
			_action_prev_helm = helm_val
			var inst_vel := (d_helm / maxf(dt, 0.008)) if dt > 0.0 else 0.0
			_action_helm_vel = lerpf(_action_helm_vel, clampf(inst_vel, -1.6, 1.6), 1.0 - exp(-10.0 * smooth_dt))
			_action_helm_cycle = wrapf(_action_helm_cycle + d_helm * 15.0, -PI, PI)

			var turn_dir := clampf(_action_helm_vel / 0.55, -1.0, 1.0)
			var turn_mag := absf(turn_dir)
			var s_turn := 1.0 if turn_dir >= 0.0 else -1.0
			var rim_r := 0.240
			var wheel_center := Vector3(0.0, -0.305, -0.455)

			var theta_r := clampf(helm_val * 0.16 + sin(_action_helm_cycle) * 0.22 * turn_mag + turn_dir * 0.05, -0.36, 0.36)
			var theta_l := clampf(helm_val * 0.16 + sin(_action_helm_cycle + PI) * 0.22 * turn_mag + turn_dir * 0.05, -0.36, 0.36)
			var reach_r := clampf(-cos(_action_helm_cycle) * s_turn, 0.0, 1.0) * turn_mag
			var reach_l := clampf(cos(_action_helm_cycle) * s_turn, 0.0, 1.0) * turn_mag

			var roll_x := clampf(_ship_roll_lag * 0.022, -0.018, 0.018)
			var roll_z_deg := -_ship_roll_lag * 10.5
			var sway_x := clampf(_sway_yaw * 0.012, -0.015, 0.015)
			var sway_y := clampf(-_sway_pitch * 0.010, -0.012, 0.012)
			var breath_y := breath * 0.0032

			l_pos = Vector3(
				wheel_center.x - rim_r * cos(theta_l) - 0.020 * reach_l + roll_x + sway_x,
				wheel_center.y + rim_r * sin(theta_l) + breath_y + sway_y,
				wheel_center.z + 0.022 * reach_l - 0.010 * turn_mag * (1.0 - reach_l)
			)
			r_pos = Vector3(
				wheel_center.x + rim_r * cos(theta_r) + 0.020 * reach_r + roll_x + sway_x,
				wheel_center.y - rim_r * sin(theta_r) + breath_y + sway_y,
				wheel_center.z + 0.022 * reach_r - 0.010 * turn_mag * (1.0 - reach_r)
			)
			l_rot = Vector3(
				14.0 + rad_to_deg(theta_l) * 0.28 - reach_l * 6.0,
				-14.0 + _sway_yaw * 3.0,
				-18.0 - rad_to_deg(theta_l) * 0.65 + roll_z_deg
			)
			r_rot = Vector3(
				14.0 - rad_to_deg(theta_r) * 0.28 - reach_r * 6.0,
				14.0 + _sway_yaw * 3.0,
				18.0 - rad_to_deg(theta_r) * 0.65 + roll_z_deg
			)

		&"anchor":
			# 2. Anchor Capstan: both hands braced forward over wooden capstan bar with
			#    rhythmic forward heaving-strain thrusts synced to Ship.anchor_progress.
			var anc := _action_prev_anchor
			var heaving := false
			if st_ship != null:
				var av: Variant = st_ship.get(&"anchor_progress")
				if av != null:
					anc = clampf(float(av), 0.0, 1.0)
				var hv: Variant = st_ship.get(&"_capstan_heaving_this_tick")
				if hv is bool and (hv as bool):
					heaving = true
			var d_anc := absf(anc - _action_prev_anchor)
			_action_prev_anchor = anc
			if d_anc > 0.00005:
				heaving = true
			if heaving:
				_action_anchor_effort = lerpf(_action_anchor_effort, 1.0, 1.0 - exp(-10.0 * smooth_dt))
				_action_anchor_phase = fmod(_action_anchor_phase + clampf(d_anc * 34.0, 0.0, 0.9) + dt * 5.2, TAU)
			else:
				_action_anchor_effort = lerpf(_action_anchor_effort, 0.0, 1.0 - exp(-7.0 * smooth_dt))

			var brace := pow(maxf(0.0, sin(_action_anchor_phase)), 1.5) * _action_anchor_effort
			var rock := cos(_action_anchor_phase * 0.5) * 0.016 * _action_anchor_effort
			var tremor := sin(_clock * 42.0) * 0.0022 * brace
			var push_z := -0.056 * brace
			var heave_y := -0.028 * brace + breath * 0.0038
			var roll_x := _ship_roll_lag * 0.020

			l_pos = Vector3(-0.19 + rock + tremor + roll_x, -0.22 + heave_y, -0.44 + push_z)
			r_pos = Vector3(0.19 + rock - tremor + roll_x, -0.22 + heave_y, -0.44 + push_z)
			l_rot = Vector3(12.0 - 13.0 * brace, -8.0 + _sway_yaw * 2.5, -76.0 - _ship_roll_lag * 8.0)
			r_rot = Vector3(12.0 - 13.0 * brace, 8.0 + _sway_yaw * 2.5, 76.0 - _ship_roll_lag * 8.0)

		&"sail_length", &"sail_angle":
			# 3. Sail Hoist / Sail Braces: alternating opposite-phase hand-over-hand rope pulling
			#    driven by Ship.sail_set or Ship.sail_trim, resting gripped when belayed.
			var is_brace := (mode == &"sail_angle")
			var d_val := 0.0
			if st_ship != null:
				if is_brace:
					var tv: Variant = st_ship.get(&"sail_trim")
					if tv != null:
						var cur_t := float(tv)
						d_val = cur_t - _action_prev_sail_trim
						_action_prev_sail_trim = cur_t
				else:
					var sv: Variant = st_ship.get(&"sail_set")
					if sv != null:
						var cur_s := float(sv)
						d_val = cur_s - _action_prev_sail_set
						_action_prev_sail_set = cur_s
			if absf(d_val) > 0.00005:
				var dir_s := 1.0 if d_val >= 0.0 else -1.0
				_action_rope_effort = lerpf(_action_rope_effort, 1.0, 1.0 - exp(-11.0 * smooth_dt))
				_action_rope_phase = wrapf(_action_rope_phase + dir_s * (clampf(absf(d_val) * 28.0, 0.0, 0.85) + dt * 5.8), -PI, PI)
			else:
				_action_rope_effort = lerpf(_action_rope_effort, 0.0, 1.0 - exp(-7.5 * smooth_dt))

			var eff := _action_rope_effort
			var pl := _action_rope_phase
			var pr := _action_rope_phase + PI
			var l_base := Vector3(-0.21, -0.21, -0.45) if is_brace else Vector3(-0.18, -0.19, -0.44)
			var r_base := Vector3(0.21, -0.25, -0.44) if is_brace else Vector3(0.18, -0.27, -0.45)
			var y_amp := 0.072 if is_brace else 0.088
			var roll_x := _ship_roll_lag * 0.020

			var l_dx := -(maxf(0.0, cos(pl)) * 0.026 + (absf(sin(pl)) * 0.020 if is_brace else 0.0)) * eff
			var r_dx := (maxf(0.0, cos(pr)) * 0.026 + (absf(sin(pr)) * 0.020 if is_brace else 0.0)) * eff
			l_pos = l_base + Vector3(l_dx + roll_x, sin(pl) * y_amp * eff + breath * 0.0035, cos(pl) * 0.044 * eff)
			r_pos = r_base + Vector3(r_dx + roll_x, sin(pr) * y_amp * eff + breath * 0.0035, cos(pr) * 0.044 * eff)
			var base_roll := 34.0 if is_brace else 24.0
			var base_yaw := 18.0 if is_brace else 24.0
			l_rot = Vector3(15.0 + sin(pl) * 14.0 * eff, -base_yaw + _sway_yaw * 3.0, -base_roll - _ship_roll_lag * 8.0)
			r_rot = Vector3(13.0 + sin(pr) * 14.0 * eff, base_yaw + _sway_yaw * 3.0, base_roll - _ship_roll_lag * 8.0)

		&"bilge":
			# 4. Bilge Pump: both hands gripping the oak pump lever, synced to ShipDamageVisuals
			#    pump stroke angle or active bailing / swing timer.
			var pump_active := _swing_timer > 0.0
			if input_enabled and Input.is_action_pressed(&"primary"):
				pump_active = true
			var pump_angle := 0.0
			var has_live_pump := false
			if st_ship != null:
				var wv: Variant = st_ship.get(&"water_level")
				if wv != null:
					var w_cur := float(wv)
					if _action_prev_water - w_cur > 0.00005:
						pump_active = true
					_action_prev_water = w_cur
				if st_ship.has_method(&"get_damage_visuals"):
					var dv: Variant = st_ship.call(&"get_damage_visuals")
					if dv is Node and is_instance_valid(dv):
						var t_v: Variant = (dv as Object).get(&"_pump_active_timer")
						var a_v: Variant = (dv as Object).get(&"_pump_handle_angle")
						if t_v != null and float(t_v) > 0.001:
							pump_active = true
						if a_v != null:
							pump_angle = float(a_v)
							has_live_pump = true

			var lever_y := 0.0
			var arc_z := 0.0
			var pitch_off := 0.0
			if has_live_pump and absf(pump_angle) > 0.002:
				var stroke := clampf(-pump_angle / 0.50, -1.0, 1.0)
				lever_y = stroke * 0.095
				arc_z = (1.0 - cos(pump_angle)) * 0.055
				pitch_off = stroke * 18.0
			else:
				if pump_active:
					_action_bilge_effort = lerpf(_action_bilge_effort, 1.0, 1.0 - exp(-12.0 * smooth_dt))
					_action_bilge_phase = fmod(_action_bilge_phase + dt * 10.5, TAU)
				else:
					_action_bilge_effort = lerpf(_action_bilge_effort, 0.0, 1.0 - exp(-7.5 * smooth_dt))
				var stroke := sin(_action_bilge_phase) * _action_bilge_effort
				lever_y = stroke * 0.090
				arc_z = (1.0 - absf(cos(_action_bilge_phase))) * 0.032 * _action_bilge_effort
				pitch_off = stroke * 18.0

			var roll_x := _ship_roll_lag * 0.016
			l_pos = Vector3(-0.165 + roll_x, -0.23 + lever_y + breath * 0.0035, -0.45 + arc_z)
			r_pos = Vector3(0.165 + roll_x, -0.23 + lever_y + breath * 0.0035, -0.41 + arc_z)
			l_rot = Vector3(12.0 + pitch_off, -14.0 + _sway_yaw * 2.5, -72.0 - _ship_roll_lag * 7.0)
			r_rot = Vector3(10.0 + pitch_off, 14.0 + _sway_yaw * 2.5, 72.0 - _ship_roll_lag * 7.0)

		&"rowboat_oars":
			# 5. Rowboat Oars: wide-set twin oar handles tracking independent port/starboard oar phase.
			if st_ship != null:
				var pp_v: Variant = st_ship.get(&"_port_oar_phase")
				var sp_v: Variant = st_ship.get(&"_stbd_oar_phase")
				var pe_v: Variant = st_ship.get(&"_port_oar_effort")
				var se_v: Variant = st_ship.get(&"_stbd_oar_effort")
				if pp_v != null:
					_action_oar_phase_l = float(pp_v)
				if sp_v != null:
					_action_oar_phase_r = float(sp_v)
				var k_oar := 1.0 - exp(-11.0 * smooth_dt)
				_action_oar_effort_l = lerpf(_action_oar_effort_l, absf(float(pe_v)) if pe_v != null else 0.0, k_oar)
				_action_oar_effort_r = lerpf(_action_oar_effort_r, absf(float(se_v)) if se_v != null else 0.0, k_oar)

			var el := clampf(_action_oar_effort_l, 0.0, 1.0)
			var er := clampf(_action_oar_effort_r, 0.0, 1.0)
			var l_dx := -(1.0 - cos(_action_oar_phase_l)) * 0.016 * el
			var r_dx := (1.0 - cos(_action_oar_phase_r)) * 0.016 * er
			l_pos = Vector3(
				-0.28 + l_dx + _sway_yaw * 0.014,
				-0.24 + cos(_action_oar_phase_l) * 0.036 * el + breath * 0.004,
				-0.42 + sin(_action_oar_phase_l) * 0.082 * el
			)
			r_pos = Vector3(
				0.28 + r_dx + _sway_yaw * 0.014,
				-0.24 + cos(_action_oar_phase_r) * 0.036 * er + breath * 0.004,
				-0.42 + sin(_action_oar_phase_r) * 0.082 * er
			)
			l_rot = Vector3(
				10.0 - cos(_action_oar_phase_l) * 15.0 * el,
				-12.0 + sin(_action_oar_phase_l) * 10.0 * el + _sway_yaw * 3.0,
				-78.0
			)
			r_rot = Vector3(
				10.0 - cos(_action_oar_phase_r) * 15.0 * er,
				12.0 - sin(_action_oar_phase_r) * 10.0 * er + _sway_yaw * 3.0,
				78.0
			)

		&"carry":
			# 6. Heavy Carry: symmetrical pirate hands gripping the left & right sides/handles
			#    of carried Treasure Chests, Relics, Powder Kegs, and Supply/Trade Crates.
			var grip_x := 0.318
			var grip_y := -0.245
			var grip_z := -0.49
			if pawn != null and pawn.carried != null and is_instance_valid(pawn.carried):
				if pawn.carried is PowderKeg:
					grip_x = 0.235
					grip_y = -0.245
					grip_z = -0.46
				elif pawn.carried.has_meta(&"treasure_id"):
					var tid := StringName(pawn.carried.get_meta(&"treasure_id"))
					var entry := TreasureCatalog.get_entry(tid)
					var shape_v: Variant = entry.get("shape", &"chest")
					var shape_k := StringName(shape_v) if shape_v != null else &"chest"
					if shape_k == &"skull" or shape_k == &"chalice":
						grip_x = 0.185
						grip_y = -0.235
						grip_z = -0.46
					elif shape_k == &"crate":
						grip_x = 0.305

			var move_spd := 0.0
			var grounded := false
			if pawn != null and is_instance_valid(pawn):
				var rv := pawn.get_relative_velocity()
				move_spd = Vector2(rv.x, rv.z).length()
				grounded = pawn.is_grounded()
			var is_moving := move_spd > 0.30 and grounded
			var move_w := clampf(move_spd / 3.4, 0.0, 1.15) if is_moving else 0.0
			var fig8_x := cos(_bob_phase) * 0.016 * move_w
			var fig8_y := sin(_bob_phase * 2.0) * 0.014 * move_w
			var fig8_roll := -cos(_bob_phase) * 2.4 * move_w
			var fig8_pitch := sin(_bob_phase * 2.0) * 1.6 * move_w
			var heavy_breath := sin(_clock * 2.15) + 0.35 * sin(_clock * 4.3 + 0.5)
			var pitch_follow := clampf(-pawn.look_pitch * 0.06, -0.045, 0.055) if pawn != null else 0.0

			var common_off := Vector3(
				fig8_x + _sway_yaw * 0.026 + _ship_roll_lag * 0.036,
				heavy_breath * 0.0052 + fig8_y - _sway_pitch * 0.020 - absf(_ship_roll_lag) * 0.012 + pitch_follow,
				0.0
			)
			var common_rot := Vector3(
				heavy_breath * 0.85 + fig8_pitch - _sway_pitch * 4.5,
				_sway_yaw * 5.2,
				fig8_roll - _sway_yaw * 4.0 - _ship_roll_lag * 9.5
			)
			l_pos = Vector3(-grip_x, grip_y, grip_z) + common_off
			r_pos = Vector3(grip_x, grip_y, grip_z) + common_off
			l_rot = Vector3(14.0, -16.0, 24.0) + common_rot
			r_rot = Vector3(14.0, 16.0, -24.0) + common_rot

		&"swim":
			# 7. Swimming: alternating crawl/breaststroke sweep when swimming forward,
			#    blending smoothly to calm wide figure-8 sculling when treading water.
			var swim_spd := Vector2(pawn.velocity.x, pawn.velocity.z).length() if (pawn != null and is_instance_valid(pawn)) else 0.0
			var is_fwd := swim_spd > 0.45
			var target_fwd := maxf(0.55, clampf((swim_spd - 0.45) / 1.85, 0.0, 1.0)) if is_fwd else 0.0
			_action_swim_blend = lerpf(_action_swim_blend, target_fwd, 1.0 - exp(-9.0 * smooth_dt))
			var swim_rate := lerpf(2.2, clampf(3.6 + swim_spd * 1.45, 4.2, 8.8), _action_swim_blend)
			_action_swim_phase = wrapf(_action_swim_phase + dt * swim_rate, -PI, PI)

			var pt := _action_swim_phase
			var l_tread_pos := Vector3(
				-0.27 - 0.026 * sin(pt),
				-0.27 + 0.015 * sin(pt * 2.0) + breath * 0.004,
				-0.44 + 0.018 * cos(pt)
			)
			var r_tread_pos := Vector3(
				0.27 + 0.026 * sin(pt),
				-0.27 + 0.015 * sin(pt * 2.0) + breath * 0.004,
				-0.44 + 0.018 * cos(pt)
			)
			var l_tread_rot := Vector3(10.0 + 7.0 * cos(pt), -12.0 - 8.0 * sin(pt), -74.0 + 10.0 * cos(pt))
			var r_tread_rot := Vector3(10.0 + 7.0 * cos(pt), 12.0 + 8.0 * sin(pt), 74.0 - 10.0 * cos(pt))

			var pl := _action_swim_phase
			var pr := _action_swim_phase + PI
			var cl := cos(pl)
			var sl := sin(pl)
			var cr := cos(pr)
			var sr := sin(pr)
			var l_abs_x := 0.248 - 0.055 * cl + 0.068 * sl - 0.028 * cos(2.0 * pl)
			var r_abs_x := 0.248 - 0.055 * cr + 0.068 * sr - 0.028 * cos(2.0 * pr)
			var l_fwd_pos := Vector3(
				-l_abs_x,
				-0.235 + 0.050 * cl - 0.025 * sl + breath * 0.003,
				-0.460 - 0.115 * cl + 0.015 * sl
			)
			var r_fwd_pos := Vector3(
				r_abs_x,
				-0.235 + 0.050 * cr - 0.025 * sr + breath * 0.003,
				-0.460 - 0.115 * cr + 0.015 * sr
			)
			var l_fwd_rot := Vector3(8.0 + 18.0 * cl - 12.0 * sl, -12.0 + 16.0 * cl - 18.0 * sl, -64.0 - 18.0 * sl + 12.0 * cl)
			var r_fwd_rot := Vector3(8.0 + 18.0 * cr - 12.0 * sr, 12.0 - 16.0 * cr + 18.0 * sr, 64.0 + 18.0 * sr - 12.0 * cr)

			var sway_off := Vector3(clampf(_sway_yaw * 0.014, -0.018, 0.018), clampf(-_sway_pitch * 0.012, -0.015, 0.015), 0.0)
			var sway_rot := Vector3(-_sway_pitch * 3.0, _sway_yaw * 3.5, 0.0)
			var fwd_w := _action_swim_blend
			l_pos = l_tread_pos.lerp(l_fwd_pos, fwd_w) + sway_off
			r_pos = r_tread_pos.lerp(r_fwd_pos, fwd_w) + sway_off
			l_rot = l_tread_rot.lerp(l_fwd_rot, fwd_w) + sway_rot
			r_rot = r_tread_rot.lerp(r_fwd_rot, fwd_w) + sway_rot

		&"ladder":
			# 8. Ladder Climbing: opposite-phase vertical hand-over-hand rung grasping
			#    driven directly by vertical climb delta, holding steadily gripped when stationary.
			var cur_y := _action_prev_ladder_y
			if pawn != null and is_instance_valid(pawn):
				cur_y = pawn.global_position.y if pawn.is_inside_tree() else pawn.position.y
			var dy := clampf(cur_y - _action_prev_ladder_y, -1.5, 1.5)
			_action_prev_ladder_y = cur_y
			if absf(dy) > 0.0001:
				_action_ladder_phase = wrapf(_action_ladder_phase + dy * 3.8, -PI, PI)
				_action_ladder_effort = lerpf(_action_ladder_effort, 1.0, 1.0 - exp(-12.0 * smooth_dt))
			else:
				_action_ladder_effort = lerpf(_action_ladder_effort, 0.0, 1.0 - exp(-8.0 * smooth_dt))

			var pl := _action_ladder_phase
			var pr := _action_ladder_phase + PI
			var sl := sin(pl)
			var cl := cos(pl)
			var sr := sin(pr)
			var cr := cos(pr)
			var eff := _action_ladder_effort
			var sway_x := clampf(_sway_yaw * 0.010, -0.014, 0.014)

			l_pos = Vector3(
				-0.19 - maxf(0.0, cl) * 0.012 * eff + sway_x,
				-0.18 + sl * 0.115 + breath * 0.003,
				-0.45 - sl * 0.018 + cl * 0.014 * eff
			)
			r_pos = Vector3(
				0.19 + maxf(0.0, cr) * 0.012 * eff + sway_x,
				-0.18 + sr * 0.115 + breath * 0.003,
				-0.45 - sr * 0.018 + cr * 0.014 * eff
			)
			l_rot = Vector3(14.0 + sl * 14.0 - cl * 6.0 * eff, -10.0 + _sway_yaw * 2.5, -78.0 + sl * 7.0)
			r_rot = Vector3(14.0 + sr * 14.0 - cr * 6.0 * eff, 10.0 + _sway_yaw * 2.5, 78.0 - sr * 7.0)

	if enter_drop > 0.0001:
		var drop_v := Vector3(0.0, -enter_drop, enter_drop * 0.38)
		l_pos += drop_v
		r_pos += drop_v
		l_rot.x -= enter_drop * 145.0
		r_rot.x -= enter_drop * 145.0

	fp_action_hands.position = Vector3.ZERO
	fp_action_hands.rotation_degrees = Vector3.ZERO
	fp_action_hands.scale = Vector3.ONE
	_fp_action_left.position = l_pos
	_fp_action_left.rotation_degrees = l_rot
	_fp_action_right.position = r_pos
	_fp_action_right.rotation_degrees = r_rot


func _sync_visibility() -> void:
	var has_pawn := pawn != null and is_instance_valid(pawn)
	var hide_tools := has_pawn and (
		pawn.dead
		or pawn.station != null
		or pawn.carried != null
		or pawn.mode == Pawn.Mode.SWIM
		or pawn.mode == Pawn.Mode.LADDER
	)
	var showing_trumpet := _fp_trumpet_node != null and is_instance_valid(_fp_trumpet_node) and _trumpet_display_timer > 0.0
	if _fp_trumpet_node != null and is_instance_valid(_fp_trumpet_node):
		var hide_trumpet := has_pawn and (pawn.dead or pawn.station != null)
		_fp_trumpet_node.visible = showing_trumpet and (not hide_trumpet)
	if fp_tool_node != null and is_instance_valid(fp_tool_node):
		var hide_for_lens := (active_item == &"spyglass" and spyglass_zoom > 0.62)
		fp_tool_node.visible = (not hide_tools) and (not hide_for_lens) and (not showing_trumpet)
	if fp_action_hands != null and is_instance_valid(fp_action_hands):
		fp_action_hands.visible = _get_action_hand_mode() != &""
	if tp_tool_node != null and is_instance_valid(tp_tool_node):
		var fp_hidden := visual != null and visual.first_person_hidden
		tp_tool_node.visible = (not hide_tools) and (not fp_hidden)


# ==============================================================================
# Helpers
# ==============================================================================

func _on_combat_attack_started(kind: StringName) -> void:
	if kind == &"heavy":
		_start_swing(&"heavy", 0.76 if melee_weapon == &"boarding_axe" else 0.64)
		if active_item == &"cutlass" and melee_weapon == &"cutlass":
			trigger_cutlass_gleam(1.0)
	elif kind == &"blunderbuss":
		_start_swing(&"blunderbuss", 0.46)
		_reload_dur = 1.85
		_reload_timer = _reload_dur
		_start_barrel_smoke(&"blunderbuss")
	elif kind == &"pistol":
		_start_swing(&"pistol", 0.34)
		_reload_dur = 1.45
		_reload_timer = _reload_dur
		_start_barrel_smoke(&"pistol")
	else:
		_start_swing(kind, 0.50 if melee_weapon == &"boarding_axe" else 0.40)
		if kind == &"slash_3" and active_item == &"cutlass" and melee_weapon == &"cutlass":
			trigger_cutlass_gleam(0.88)


func _on_combat_parried(_attacker: Pawn) -> void:
	if active_item == &"cutlass":
		_start_swing(&"parry_clang", 0.26)
		if melee_weapon == &"cutlass":
			trigger_cutlass_gleam(1.0)


func _on_combat_blocked(_attacker: Pawn) -> void:
	if active_item == &"cutlass":
		_start_swing(&"parry_clang", 0.22)
		if melee_weapon == &"cutlass":
			trigger_cutlass_gleam(0.82)


func _start_swing(kind: StringName, dur: float) -> void:
	_swing_kind = kind
	_swing_dur = maxf(dur, 0.05)
	_swing_timer = _swing_dur


func _play_anim(action: StringName, duration: float) -> void:
	if anim_driver != null and is_instance_valid(anim_driver):
		anim_driver.play_action(action, duration)


func _find_nearby_ship(max_dist: float) -> Ship:
	if pawn == null:
		return null
	if pawn.platform is Ship:
		return pawn.platform as Ship
	if not is_inside_tree():
		return null
	var best: Ship = null
	var best_d := max_dist
	for node in get_tree().get_nodes_in_group(&"ship"):
		var s := node as Ship
		if s == null:
			continue
		var d := pawn.global_position.distance_to(s.global_position)
		if d < best_d:
			best_d = d
			best = s
	return best


## Spawn a sculpted zero-primitive flat-faceted earth clod burst when swinging the shovel.
func spawn_shovel_dirt_vfx(pos: Vector3) -> CPUParticles3D:
	var host := pawn.get_parent() if pawn != null else null
	if host == null:
		return null
	_ensure_particle_meshes()
	var p := CPUParticles3D.new()
	p.name = "ShovelDirtBurst"
	p.one_shot = true
	p.explosiveness = 0.90
	p.amount = 14
	p.lifetime = 0.52
	p.direction = Vector3(0.0, 1.0, 0.0)
	p.spread = 42.0
	p.initial_velocity_min = 2.2
	p.initial_velocity_max = 4.6
	p.gravity = Vector3(0.0, -11.5, 0.0)
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.13
	p.mesh = _clod_mesh
	host.add_child(p)
	p.global_position = pos + Vector3(0.0, 0.12, 0.0)
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


func _spawn_water_splash_puff(pos: Vector3, dir: Vector3) -> void:
	var host := pawn.get_parent() if pawn != null else null
	if host == null:
		return
	_ensure_particle_meshes()
	var p := CPUParticles3D.new()
	p.name = "BucketSplashPuff"
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = 16
	p.lifetime = 0.55
	p.direction = (dir + Vector3(0.0, 0.35, 0.0)).normalized()
	p.spread = 34.0
	p.initial_velocity_min = 3.2
	p.initial_velocity_max = 6.2
	p.gravity = Vector3(0.0, -11.0, 0.0)
	p.scale_amount_min = 0.07
	p.scale_amount_max = 0.16
	p.mesh = _splash_drop_mesh
	host.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


static func _ensure_particle_meshes() -> void:
	if _clod_mat == null:
		_clod_mat = StandardMaterial3D.new()
		_clod_mat.vertex_color_use_as_albedo = true
		_clod_mat.vertex_color_is_srgb = true
		_clod_mat.roughness = 0.92
		_clod_mat.metallic = 0.0
	if _clod_mesh == null:
		_clod_mesh = _build_faceted_clod_mesh(
			Color(0.76, 0.62, 0.38), Color(0.56, 0.42, 0.24), Color(0.36, 0.26, 0.14),
			_clod_mat, Vector3(0.52, 0.42, 0.46)
		)
	if _splash_drop_mat == null:
		_splash_drop_mat = StandardMaterial3D.new()
		_splash_drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_splash_drop_mat.vertex_color_use_as_albedo = true
		_splash_drop_mat.vertex_color_is_srgb = true
		_splash_drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if _splash_drop_mesh == null:
		_splash_drop_mesh = _build_faceted_clod_mesh(
			Color(0.82, 0.96, 0.98, 0.84), Color(0.62, 0.90, 0.94, 0.78), Color(0.42, 0.80, 0.86, 0.72),
			_splash_drop_mat, Vector3(0.45, 0.50, 0.45)
		)


static func _build_faceted_clod_mesh(
	col_top: Color,
	col_mid: Color,
	col_bot: Color,
	mat: StandardMaterial3D,
	radii: Vector3
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var top := Vector3(0.0, radii.y, 0.0)
	var bot := Vector3(0.0, -radii.y * 0.92, 0.0)
	var ring: Array[Vector3] = []
	var segs := 6
	for i in segs:
		var a := float(i) / float(segs) * TAU
		var j := 1.0 + 0.16 * sin(float(i) * 2.3 + 0.5)
		ring.append(Vector3(cos(a) * radii.x * j, sin(float(i) * 1.9) * radii.y * 0.18, sin(a) * radii.z * j))
	for i in segs:
		var v0 := ring[i]
		var v1 := ring[(i + 1) % segs]
		var c_up := col_top.lerp(col_mid, float(i % 2) * 0.45)
		var c_dn := col_mid.lerp(col_bot, 0.55 + float(i % 2) * 0.30)
		var nu := (v1 - top).cross(v0 - top).normalized()
		for v: Vector3 in [top, v0, v1]:
			st.set_normal(nu)
			st.set_color(c_up)
			st.add_vertex(v)
		var nd := (v0 - bot).cross(v1 - bot).normalized()
		for v: Vector3 in [bot, v1, v0]:
			st.set_normal(nd)
			st.set_color(c_dn)
			st.add_vertex(v)
	var am := st.commit()
	am.surface_set_material(0, mat)
	return am


func _start_barrel_smoke(kind: StringName) -> void:
	if active_item != &"pistol":
		return
	if pawn != null and is_instance_valid(pawn) and (pawn.dead or pawn.station != null):
		return
	_barrel_smoke_timer = minf(_reload_dur * 0.85, 1.35)
	if fp_tool_node == null or not is_instance_valid(fp_tool_node):
		return
	if _barrel_smoke == null or not is_instance_valid(_barrel_smoke) or _barrel_smoke.get_parent() != fp_tool_node:
		_detach_barrel_smoke(true)
		_barrel_smoke_timer = minf(_reload_dur * 0.85, 1.35)
		_ensure_barrel_smoke_assets()
		var smoke := GPUParticles3D.new()
		smoke.name = "FirearmBarrelSmoke"
		smoke.amount = 10
		smoke.lifetime = 0.75
		smoke.randomness = 0.35
		smoke.local_coords = false
		smoke.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
		smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		smoke.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		smoke.visibility_aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3.0, 3.0, 3.0))
		smoke.process_material = _barrel_smoke_proc
		smoke.draw_pass_1 = _barrel_smoke_mesh
		smoke.material_override = _barrel_smoke_mat
		fp_tool_node.add_child(smoke)
		_barrel_smoke = smoke
	_barrel_smoke.position = Vector3(0.0, 0.076, -0.468) if kind == &"blunderbuss" else Vector3(0.0, 0.066, -0.332)
	_barrel_smoke.visible = true
	_barrel_smoke.emitting = true


func _tick_barrel_smoke(delta: float) -> void:
	var has_pawn := pawn != null and is_instance_valid(pawn)
	var can_smoke := active_item == &"pistol" \
		and fp_tool_node != null and is_instance_valid(fp_tool_node) \
		and (not has_pawn or (
			not pawn.dead
			and pawn.station == null
			and pawn.carried == null
			and pawn.mode != Pawn.Mode.SWIM
			and pawn.mode != Pawn.Mode.LADDER
		))
	if not can_smoke:
		_barrel_smoke_timer = 0.0
		if _barrel_smoke != null and is_instance_valid(_barrel_smoke):
			_barrel_smoke.emitting = false
		return
	if _barrel_smoke_timer > 0.0:
		_barrel_smoke_timer = maxf(0.0, _barrel_smoke_timer - maxf(delta, 0.0))
		if _barrel_smoke != null and is_instance_valid(_barrel_smoke):
			_barrel_smoke.emitting = (_barrel_smoke_timer > 0.0)
	elif _barrel_smoke != null and is_instance_valid(_barrel_smoke) and _barrel_smoke.emitting:
		_barrel_smoke.emitting = false


func _detach_barrel_smoke(detach_from_parent: bool = true) -> void:
	_barrel_smoke_timer = 0.0
	if _barrel_smoke != null and is_instance_valid(_barrel_smoke):
		_barrel_smoke.emitting = false
		_barrel_smoke.visible = false
		_barrel_smoke.draw_pass_1 = null
		_barrel_smoke.process_material = null
		_barrel_smoke.material_override = null
		if detach_from_parent and _barrel_smoke.get_parent() != null:
			_barrel_smoke.get_parent().remove_child(_barrel_smoke)
		_barrel_smoke.queue_free()
	_barrel_smoke = null


static func _clear_tool_node_materials(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	for child in node.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := child as MultiMeshInstance3D
		if mmi != null:
			mmi.visible = false
			mmi.material_override = null
			mmi.multimesh = null
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi != null:
			if mi.material_override is ShaderMaterial:
				(mi.material_override as ShaderMaterial).shader = null
			mi.material_override = null


static func _ensure_barrel_smoke_assets() -> void:
	if _barrel_smoke_mesh == null:
		_barrel_smoke_mesh = _build_barrel_smoke_card_mesh()
	if _barrel_smoke_shader == null:
		_barrel_smoke_shader = _build_barrel_smoke_shader()
	if _barrel_smoke_mat == null:
		_barrel_smoke_mat = ShaderMaterial.new()
		_barrel_smoke_mat.shader = _barrel_smoke_shader
	if _barrel_smoke_proc == null:
		var proc := ParticleProcessMaterial.new()
		proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		proc.emission_sphere_radius = 0.012
		proc.direction = Vector3(0.0, 1.0, -0.18)
		proc.spread = 22.0
		proc.initial_velocity_min = 0.14
		proc.initial_velocity_max = 0.30
		proc.gravity = Vector3(0.0, 0.38, 0.0)
		proc.tangential_accel_min = -0.18
		proc.tangential_accel_max = 0.18
		proc.damping_min = 0.45
		proc.damping_max = 0.85
		proc.angle_min = -180.0
		proc.angle_max = 180.0
		proc.scale_min = 0.75
		proc.scale_max = 1.25
		_barrel_smoke_proc = proc


static func _build_barrel_smoke_card_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 0.048
	var p0 := Vector3(-h, -h, 0.0)
	var p1 := Vector3(h, -h, 0.0)
	var p2 := Vector3(h, h, 0.0)
	var p3 := Vector3(-h, h, 0.0)
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


static func _build_barrel_smoke_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;

varying float v_age;
varying float v_seed;

void vertex() {
	v_age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_seed = INSTANCE_CUSTOM.x;
	float grow = mix(0.45, 1.85, pow(v_age, 0.70));
	VERTEX *= grow;
	float curl = sin(TIME * 4.4 + v_seed * 6.2831853 + v_age * 5.2) * 0.022 * v_age;
	VERTEX.x += curl;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float spin = v_seed * 6.2831853 + v_age * 2.6;
	float cs = cos(spin);
	float sn = sin(spin);
	vec2 rq = vec2(q.x * cs - q.y * sn, q.x * sn + q.y * cs);
	float r = length(q);
	float edge = smoothstep(1.0, 0.16, r);
	float wisp = 0.72 + 0.28 * sin(rq.x * 5.2 + v_age * 4.5 + TIME * 2.1) * cos(rq.y * 4.6 - v_age * 3.8);
	float fade_in = smoothstep(0.0, 0.16, v_age);
	float fade_out = pow(1.0 - v_age, 1.35);
	float alpha = clamp(edge * edge * wisp * fade_in * fade_out * 0.56, 0.0, 1.0);
	vec3 col_hot = vec3(0.88, 0.85, 0.80);
	vec3 col_cool = vec3(0.68, 0.72, 0.76);
	ALBEDO = mix(col_hot, col_cool, smoothstep(0.05, 0.85, v_age));
	ALPHA = alpha;
}
"""
	return sh

