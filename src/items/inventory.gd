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
const COMPASS_16: PackedStringArray = [
	"N", "NNE", "NE", "ENE",
	"E", "ESE", "SE", "SSE",
	"S", "SSW", "SW", "WSW",
	"W", "WNW", "NW", "NNW",
]

## First-person rest & secondary-raised poses relative to Camera3D:
## [rest_pos, rest_rot_deg, raise_pos, raise_rot_deg, scale].
const FP_POSES := {
	&"cutlass": [Vector3(0.32, -0.34, -0.52), Vector3(-16.0, 14.0, 12.0), Vector3(0.08, -0.18, -0.44), Vector3(-14.0, 62.0, 68.0), 0.85],
	&"boarding_axe": [Vector3(0.35, -0.38, -0.54), Vector3(-14.0, 12.0, 10.0), Vector3(0.06, -0.20, -0.44), Vector3(-10.0, 68.0, 74.0), 0.86],
	&"pistol": [Vector3(0.28, -0.26, -0.46), Vector3(2.0, 4.0, 0.0), Vector3(0.0, -0.145, -0.40), Vector3(0.0, 0.0, 0.0), 0.92],
	&"blunderbuss": [Vector3(0.30, -0.28, -0.48), Vector3(3.0, 6.0, -2.0), Vector3(0.0, -0.155, -0.42), Vector3(0.0, 0.0, 0.0), 0.90],
	&"compass": [Vector3(0.23, -0.23, -0.40), Vector3(26.0, -14.0, -8.0), Vector3(0.0, -0.17, -0.35), Vector3(56.0, 0.0, 0.0), 0.72],
	&"spyglass": [Vector3(0.26, -0.24, -0.44), Vector3(8.0, 16.0, -6.0), Vector3(0.0, -0.02, -0.18), Vector3(0.0, 0.0, 0.0), 0.95],
	&"lantern": [Vector3(0.34, 0.04, -0.48), Vector3(4.0, -10.0, -4.0), Vector3(0.18, 0.22, -0.56), Vector3(-8.0, -6.0, 2.0), 0.92],
	&"map": [Vector3(0.26, -0.30, -0.46), Vector3(-18.0, -18.0, 6.0), Vector3(0.0, -0.04, -0.36), Vector3(-4.0, 0.0, 0.0), 1.0],
	&"shovel": [Vector3(0.34, -0.38, -0.56), Vector3(-24.0, 12.0, 10.0), Vector3(0.22, -0.24, -0.50), Vector3(-34.0, 18.0, 16.0), 0.85],
	&"bucket": [Vector3(0.32, 0.02, -0.48), Vector3(8.0, -18.0, 6.0), Vector3(0.14, 0.06, -0.44), Vector3(20.0, -8.0, 0.0), 0.88],
	&"planks": [Vector3(0.30, -0.30, -0.50), Vector3(-12.0, -24.0, 10.0), Vector3(0.08, -0.16, -0.44), Vector3(-6.0, -10.0, 4.0), 0.86],
	&"tankard": [Vector3(0.28, -0.22, -0.40), Vector3(6.0, -14.0, 4.0), Vector3(0.06, -0.08, -0.26), Vector3(26.0, -8.0, -10.0), 0.95],
	&"instrument": [Vector3(0.0, -0.26, -0.42), Vector3(14.0, 0.0, 0.0), Vector3(0.0, -0.16, -0.36), Vector3(6.0, 0.0, 0.0), 0.95],
	&"hurdy_gurdy": [Vector3(0.04, -0.28, -0.46), Vector3(12.0, -14.0, 4.0), Vector3(0.02, -0.19, -0.40), Vector3(6.0, -8.0, 2.0), 0.92],
	&"whistle": [Vector3(0.14, -0.22, -0.38), Vector3(8.0, -12.0, 6.0), Vector3(0.02, -0.11, -0.28), Vector3(-4.0, 0.0, 0.0), 0.95],
}

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
var _bob_phase: float = 0.0
var _clock: float = 0.0
var _needle_angle: float = 0.0
var _needle_vel: float = 0.0
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
var _started_shanty: bool = false
var _shanty_phase: float = 0.0
var _last_shanty_audio_beat: float = -1.0
var _whistle_rot_deg: Vector3 = Vector3.ZERO
var _shanty_motes: GPUParticles3D = null
var _rng := RandomNumberGenerator.new()

# Statically cached zero-primitive sculpted particle ArrayMeshes (released when _active_inventories hits 0).
static var _active_inventories: int = 0
static var _clod_mesh: ArrayMesh = null
static var _clod_mat: StandardMaterial3D = null
static var _splash_drop_mesh: ArrayMesh = null
static var _splash_drop_mat: StandardMaterial3D = null


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


func _exit_tree() -> void:
	_detach_captain_shanty_motes(false)
	if playing_shanty:
		set_playing_shanty(false)
	treasure_map_texture = null
	map_table = null
	_active_inventories = maxi(0, _active_inventories - 1)
	if _active_inventories == 0:
		_clod_mesh = null
		_clod_mat = null
		_splash_drop_mesh = null
		_splash_drop_mat = null


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
	if combat != null and not combat.attack_started.is_connected(_on_combat_attack_started):
		combat.attack_started.connect(_on_combat_attack_started)
	if visual != null and not visual.rig_changed.is_connected(_on_visual_rig_changed):
		visual.rig_changed.connect(_on_visual_rig_changed)


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
	_equip_dip = 1.0
	_primary_hold_time = 0.0
	_heavy_fired_this_hold = false
	if item_id != &"compass" and (_compass_pace_active or compass_paces != 0):
		_reset_compass_pacing(false)
	if item_id != &"spyglass" and spyglass_zoom > 0.001:
		_set_spyglass_zoom(0.0)
		_was_zooming_spyglass = false

	_discover_siblings()
	if (item_id == &"cutlass" or item_id == &"pistol") and combat != null:
		combat.equip_weapon(get_resolved_tool_id(item_id))

	if changed:
		_rebuild_tool_meshes()
		if not silent:
			Audio.play_sfx(&"ui_tick", Vector3.INF, -5.0, 0.06)
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
	if fp_tool_node != null and is_instance_valid(fp_tool_node):
		fp_tool_node.queue_free()
		fp_tool_node = null
	if tp_tool_node != null and is_instance_valid(tp_tool_node):
		tp_tool_node.queue_free()
		tp_tool_node = null

	var mesh_id := get_resolved_tool_id(active_item)
	if viewmodel_root != null and is_instance_valid(viewmodel_root):
		fp_tool_node = ToolMeshes.build_tool(mesh_id)
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
		&"compass":
			var needle := node.get_node_or_null(^"Needle") as Node3D
			if needle != null:
				needle.rotation.y = _needle_angle
	ToolMeshes.apply_tool_variant_visual(active_item, node, tool_variant_id)


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
		if was_pin:
			compass_mode_changed.emit(false)
		_start_swing(&"inspect", 0.26)
		return false
	compass_pin_mode = not compass_pin_mode
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


## Toggle oil lantern flame & OmniLight3D on or off.
func toggle_lantern() -> bool:
	lantern_lit = not lantern_lit
	_use_cooldown = 0.20
	if not lantern_lit:
		_lantern_flare_blend = 0.0
		_lantern_signal_flash = 0.0
	if active_item == &"lantern":
		_sync_tool_visual_state(fp_tool_node)
		_sync_tool_visual_state(tp_tool_node)
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
	_use_cooldown = 0.55
	_start_swing(&"hammer", 0.48)
	_play_anim(&"hammer", 0.50)
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


# ==============================================================================
# Frame updates & input routing
# ==============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if not _can_read_player_input():
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
	if _burp_timer > 0.0:
		_burp_timer -= delta
		if _burp_timer <= 0.0:
			_burp_timer = -1.0
			var pos := pawn.eye_position() if pawn != null else Vector3.INF
			Audio.play_sfx(&"burp", pos, -2.5)

	if pawn == null or player_controller == null or viewmodel_root == null:
		_discover_siblings()

	_poll_input(delta)
	_tick_tipsy(delta)
	_tick_spyglass(delta)
	_tick_compass(delta)
	_tick_concertina(delta)
	_tick_lantern_flicker(delta)
	_tick_viewmodel_pose(delta)
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
	# Damped magnetic spring physics for realistic fluid needle settling!
	var err := wrapf(target_angle - _needle_angle, -PI, PI)
	var dt := minf(delta, 0.05)
	_needle_vel += (err * 42.0 - _needle_vel * 6.5) * dt
	_needle_angle = wrapf(_needle_angle + _needle_vel * dt, -PI, PI)
	for n in [fp_tool_node, tp_tool_node]:
		if n != null and is_instance_valid(n):
			var needle := (n as Node3D).get_node_or_null(^"Needle") as Node3D
			if needle != null:
				needle.rotation.y = _needle_angle


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
		&"hurdy_gurdy":
			_whistle_rot_deg = Vector3.ZERO
			if playing_shanty:
				var crank_rad := _shanty_phase * TAU * 0.5
				ToolMeshes.set_hurdy_gurdy_crank(fp_tool_node, crank_rad)
				ToolMeshes.set_hurdy_gurdy_crank(tp_tool_node, crank_rad)
		&"whistle":
			if playing_shanty:
				var sway_deg := sin(_shanty_phase * PI) * 9.0
				var nod_deg := sin(_shanty_phase * TAU) * 4.8
				_whistle_rot_deg = Vector3(nod_deg, sway_deg, sway_deg * 0.5)
			else:
				_whistle_rot_deg = Vector3.ZERO
			if tp_tool_node != null and is_instance_valid(tp_tool_node):
				tp_tool_node.rotation_degrees = _whistle_rot_deg


func _tick_lantern_flicker(delta: float = 0.0) -> void:
	_lantern_signal_cd = maxf(0.0, _lantern_signal_cd - delta)
	_lantern_signal_flash = move_toward(_lantern_signal_flash, 0.0, delta / 0.35)
	var want_flare := (active_item == &"lantern") and lantern_lit and _secondary_held
	if delta > 0.0:
		_lantern_flare_blend = lerpf(_lantern_flare_blend, 1.0 if want_flare else 0.0, 1.0 - exp(-8.5 * delta))
	elif not want_flare:
		_lantern_flare_blend = 0.0
	if active_item != &"lantern" or not lantern_lit:
		return
	var flick := 0.93 + 0.07 * sin(_clock * 11.4) * cos(_clock * 7.3)
	var base_energy := lerpf(2.4, 4.3, _lantern_flare_blend) * flick
	var final_energy := lerpf(base_energy, 6.5, _lantern_signal_flash)
	var final_range := lerpf(12.0, 22.0, maxf(_lantern_flare_blend, _lantern_signal_flash))
	var flame_boost := 1.0 + _lantern_flare_blend * 0.24 + _lantern_signal_flash * 0.55
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
	var pose_id := get_resolved_tool_id(active_item)
	var pose: Array = FP_POSES.get(pose_id, FP_POSES.get(active_item, FP_POSES[&"cutlass"]))
	var rest_pos: Vector3 = pose[0]
	var rest_rot: Vector3 = pose[1]
	var raise_pos: Vector3 = pose[2]
	var raise_rot: Vector3 = pose[3]
	var sc: float = float(pose[4])

	var want_raise := playing_shanty if active_item == &"instrument" else _secondary_held
	_raise_blend = lerpf(_raise_blend, 1.0 if want_raise else 0.0, 1.0 - exp(-11.0 * delta))
	_equip_dip = move_toward(_equip_dip, 0.0, delta * 3.8)

	# Walk / breathing bob.
	var move_spd := 0.0
	if pawn != null:
		var rv := pawn.get_relative_velocity()
		move_spd = Vector2(rv.x, rv.z).length()
	if move_spd > 0.35 and pawn != null and pawn.is_grounded():
		_bob_phase = fmod(_bob_phase + move_spd * delta * 3.4, TAU)
	var bob_amp := lerpf(1.0, 0.18, _raise_blend)
	var idle_breath := sin(_clock * 2.1) * 0.005 * bob_amp
	var walk_x := cos(_bob_phase) * 0.014 * clampf(move_spd / 4.0, 0.0, 1.0) * bob_amp
	var walk_y := absf(sin(_bob_phase)) * 0.014 * clampf(move_spd / 4.0, 0.0, 1.0) * bob_amp

	var pos := rest_pos.lerp(raise_pos, _raise_blend)
	var rot_deg := rest_rot.lerp(raise_rot, _raise_blend)
	pos += Vector3(walk_x, idle_breath - walk_y - _equip_dip * 0.24, _equip_dip * 0.08)
	rot_deg.x -= _equip_dip * 38.0
	if active_item == &"compass" and _compass_pace_dip > 0.001:
		var dip_pulse := sin(_compass_pace_dip * PI)
		pos += Vector3(0.0, -0.018 * dip_pulse, 0.006 * dip_pulse)
		rot_deg += Vector3(-5.5 * dip_pulse, 0.0, 0.0)
	if active_item == &"instrument" and shanty_instrument == &"whistle":
		rot_deg += _whistle_rot_deg

	# Active swing / dig / recoil / drink offset!
	if _swing_timer > 0.0:
		_swing_timer = maxf(0.0, _swing_timer - delta)
		var u := 1.0 - (_swing_timer / maxf(_swing_dur, 0.001))
		var pulse := sin(u * PI)
		match _swing_kind:
			&"slash", &"slash_1", &"slash_2", &"slash_3":
				var side_dir := -1.0 if _swing_kind == &"slash_2" else 1.0
				pos += Vector3(-0.22 * side_dir * pulse, -0.06 * pulse, -0.14 * pulse)
				rot_deg += Vector3(-48.0 * pulse, 42.0 * side_dir * pulse, 36.0 * side_dir * pulse)
			&"heavy":
				pos += Vector3(-0.26 * pulse, 0.04 * pulse, -0.22 * pulse)
				rot_deg += Vector3(-68.0 * pulse, 58.0 * pulse, 52.0 * pulse)
			&"pistol":
				pos += Vector3(0.0, 0.055 * pulse, 0.095 * pulse)
				rot_deg += Vector3(28.0 * pulse, 0.0, 0.0)
			&"blunderbuss":
				pos += Vector3(0.0, 0.085 * pulse, 0.145 * pulse)
				rot_deg += Vector3(40.0 * pulse, 0.0, -5.0 * pulse)
			&"dig":
				pos += Vector3(-0.08 * pulse, -0.18 * pulse, -0.18 * pulse)
				rot_deg += Vector3(-52.0 * pulse, 12.0 * pulse, 8.0 * pulse)
			&"scoop", &"splash":
				pos += Vector3(-0.08 * pulse, -0.12 * pulse, -0.16 * pulse)
				rot_deg += Vector3(-45.0 * pulse if _swing_kind == &"splash" else 34.0 * pulse, 0.0, 0.0)
			&"hammer":
				var double_tap := absf(sin(u * PI * 2.0))
				pos += Vector3(-0.06 * double_tap, -0.05 * double_tap, -0.16 * double_tap)
				rot_deg += Vector3(-34.0 * double_tap, 8.0 * double_tap, 0.0)
			&"drink":
				pos = pos.lerp(Vector3(0.04, -0.02, -0.20), pulse)
				rot_deg = rot_deg.lerp(Vector3(56.0, -8.0, -14.0), pulse)
			&"toast":
				pos += Vector3(-0.04 * pulse, 0.08 * pulse, -0.10 * pulse)
				rot_deg += Vector3(-16.0 * pulse, -6.0 * pulse, -14.0 * pulse)
			_:
				pos += Vector3(0.0, 0.03 * pulse, -0.04 * pulse)

	# Charge windup feedback when holding primary with melee weapon.
	if active_item == &"cutlass" and _primary_was_down and not _heavy_fired_this_hold and _primary_hold_time > 0.08:
		var ch := clampf((_primary_hold_time - 0.08) / (HEAVY_HOLD_TIME - 0.08), 0.0, 1.0)
		pos += Vector3(0.10 * ch, 0.06 * ch, 0.08 * ch)
		rot_deg += Vector3(22.0 * ch, -24.0 * ch, -18.0 * ch)

	fp_tool_node.position = pos
	fp_tool_node.rotation_degrees = rot_deg
	fp_tool_node.scale = Vector3.ONE * sc


func _sync_visibility() -> void:
	var hide_tools := pawn != null and (pawn.dead or pawn.station != null or pawn.carried != null)
	if fp_tool_node != null and is_instance_valid(fp_tool_node):
		var hide_for_lens := (active_item == &"spyglass" and spyglass_zoom > 0.62)
		fp_tool_node.visible = (not hide_tools) and (not hide_for_lens)
	if tp_tool_node != null and is_instance_valid(tp_tool_node):
		var fp_hidden := visual != null and visual.first_person_hidden
		tp_tool_node.visible = (not hide_tools) and (not fp_hidden)


# ==============================================================================
# Helpers
# ==============================================================================

func _on_combat_attack_started(kind: StringName) -> void:
	if kind == &"heavy":
		_start_swing(&"heavy", 0.58)
	elif kind == &"blunderbuss":
		_start_swing(&"blunderbuss", 0.42)
	elif kind == &"pistol":
		_start_swing(&"pistol", 0.30)
	else:
		_start_swing(kind, 0.36)


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
