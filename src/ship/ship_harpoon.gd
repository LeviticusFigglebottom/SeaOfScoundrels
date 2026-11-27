class_name ShipHarpoon
extends Node3D
## Bow-mounted interactive sculpted Sea-of-Scoundrels harpoon launcher.
##
## Features 100% sculpted flat-faceted `SurfaceTool` `ArrayMesh` geometry (zero raw
## `PrimitiveMesh`es) with WeakRef-cached shared ship PBR textures (object-space
## triplanar mapping, zero extra VRAM) and ref-counted leak-free cache teardown.
##
## Mechanics (host-authoritative where `Net.is_host()`):
## - Aim limits: yaw [-1.02, +1.02] rad (~+/-58 deg), pitch [-0.50, +0.38] rad.
## - `fire(shooter_pawn)`: 2.6 m magnetic loot cone up to 38.0 m for floating/shoreline
##   Carryable treasures, SupplyBarrels, and FlotsamClusters; falls back to swept
##   physics raycast (world layer 1 + other ships layer 2, Godot 4.7/4.8 dual-compat)
##   to tether piers, cliffs, or rival hulls.
## - `reel(active, delta)`: smoothly shortens active tether (11.0 m/s) and pulls the
##   ship's bow gently toward the anchor with bounded horizontal-emphasized traction.
## - `release()`: cleanly snaps active tether and stows the harpoon spear.

signal fired(result: Dictionary)
signal tethered(world_pos: Vector3)
signal released
signal loot_snagged(item_label: String)

enum State { IDLE, EXTENDING, REELING_LOOT, TETHERED, RETRACTING }

const MAX_RANGE := 38.0
const AUTO_RELEASE_MAX_DIST := 44.0
const AUTO_RELEASE_MIN_DIST := 3.5
const LOOT_CONE_RADIUS := 2.6
const FIRE_COOLDOWN := 0.65
const LOOT_REEL_DURATION := 0.42
const MISS_FLIGHT_DURATION := 0.32
const MUZZLE_SPARK_DURATION := 0.20
const LOCK_GLINT_POLL_INTERVAL := 0.10
const REEL_SPEED := 11.0
const YAW_MIN := -1.02
const YAW_MAX := 1.02
const PITCH_MIN := -0.50
const PITCH_MAX := 0.38

## World static (layer 1) + ships (layer 2).
const TETHER_HIT_MASK := 1 | (1 << 1)

const TEX_OAK_NORMAL := "res://assets/generated/textures/ship_oak_normal.png"
const TEX_OAK_ROUGH := "res://assets/generated/textures/ship_oak_rough.png"
const TEX_IRON_NORMAL := "res://assets/generated/textures/ship_iron_normal.png"
const TEX_IRON_ROUGH := "res://assets/generated/textures/ship_iron_rough.png"
const TEX_BRASS_NORMAL := "res://assets/generated/textures/ship_brass_normal.png"
const TEX_BRASS_ROUGH := "res://assets/generated/textures/ship_brass_rough.png"
const TEX_ROPE_NORMAL := "res://assets/generated/textures/ship_rope_normal.png"
const TEX_ROPE_ROUGH := "res://assets/generated/textures/ship_rope_rough.png"

# sRGB-calibrated painterly nautical palette (seasoned oak, forged iron, turned brass, braided hemp).
const COL_OAK_HI := Color(0.56, 0.39, 0.22)
const COL_OAK_MID := Color(0.42, 0.28, 0.15)
const COL_OAK_LO := Color(0.24, 0.15, 0.08)
const COL_IRON_HI := Color(0.32, 0.34, 0.38)
const COL_IRON_MID := Color(0.18, 0.19, 0.23)
const COL_IRON_LO := Color(0.09, 0.10, 0.13)
const COL_BRASS_HI := Color(0.96, 0.79, 0.32)
const COL_BRASS_MID := Color(0.76, 0.57, 0.19)
const COL_BRASS_LO := Color(0.44, 0.31, 0.10)
const COL_ROPE_HI := Color(0.80, 0.67, 0.44)
const COL_ROPE_MID := Color(0.62, 0.50, 0.31)
const COL_ROPE_LO := Color(0.38, 0.29, 0.17)

## Mounting side: &"port" or &"starboard".
@export var side: StringName = &"port"
## Visual scale matched to the owning ship's hull_scale.
@export var visual_scale: float = 1.0

## Owning ship (`Ship` / `RigidBody3D`).
var ship: Node3D = null
var state: State = State.IDLE
var aim_yaw: float = 0.0
var aim_pitch: float = 0.0
var cooldown: float = 0.0

var tether_world_pos: Vector3 = Vector3.ZERO
var tether_target_ship: Node3D = null
var tether_local_offset: Vector3 = Vector3.ZERO
var tether_length: float = 0.0
var is_reeling: bool = false

# Visual hierarchy refs
var _visual_root: Node3D = null
var _pedestal_oak_mi: MeshInstance3D = null
var _pedestal_iron_mi: MeshInstance3D = null
var _yaw_pivot: Node3D = null
var _yoke_mi: MeshInstance3D = null
var _pitch_pivot: Node3D = null
var _launcher_iron_mi: MeshInstance3D = null
var _launcher_brass_mi: MeshInstance3D = null
var _winch_pivot: Node3D = null
var _winch_drum_mi: MeshInstance3D = null
var _winch_crank_mi: MeshInstance3D = null
var _muzzle_point: Node3D = null
var _muzzle_spark_mi: MeshInstance3D = null
var _muzzle_spark_mat: StandardMaterial3D = null
var _spear_node: Node3D = null
var _spear_mi: MeshInstance3D = null
var _lock_glint_mi: MeshInstance3D = null
var _lock_glint_mat: StandardMaterial3D = null
var _rope_mi: MeshInstance3D = null

# Runtime animation & physics state
var _snagged_carryable: Carryable = null
var _reel_start_pos: Vector3 = Vector3.ZERO
var _reel_elapsed: float = 0.0
var _reel_duration: float = LOOT_REEL_DURATION
var _flight_target_pos: Vector3 = Vector3.ZERO
var _flight_elapsed: float = 0.0
var _flight_duration: float = MISS_FLIGHT_DURATION
var _tether_spear_dir: Vector3 = Vector3.FORWARD
var _recoil: float = 0.0
var _winch_spin_vel: float = 0.0
var _reel_sfx_accum: float = 0.0
var _reeled_this_tick: bool = false
var _muzzle_spark_timer: float = 0.0
var _lock_glint_poll_accum: float = 0.0
var _lock_glint_clock: float = 0.0
var _has_loot_lock: bool = false

var _ray_params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _ray_result: Variant = ClassDB.instantiate(&"PhysicsIntersectRayResult3D") if ClassDB.class_exists(&"PhysicsIntersectRayResult3D") else null
var _exclude_rids: Array[RID] = []

# Ref-counted static sculpted ArrayMesh & shared PBR material caches (zero ObjectDB leaks).
static var _active_instances: int = 0
static var _pbr_tex_cache: Dictionary = {}  # String path -> WeakRef(Texture2D)
static var _pedestal_oak_mesh: ArrayMesh = null
static var _pedestal_iron_mesh: ArrayMesh = null
static var _yoke_mesh: ArrayMesh = null
static var _launcher_iron_mesh: ArrayMesh = null
static var _launcher_brass_mesh: ArrayMesh = null
static var _winch_drum_mesh: ArrayMesh = null
static var _winch_crank_mesh: ArrayMesh = null
static var _spear_mesh: ArrayMesh = null
static var _rope_tube_mesh: ArrayMesh = null
static var _muzzle_spark_mesh: ArrayMesh = null
static var _lock_glint_mesh: ArrayMesh = null
static var _oak_mat: StandardMaterial3D = null
static var _iron_mat: StandardMaterial3D = null
static var _brass_mat: StandardMaterial3D = null
static var _rope_mat: StandardMaterial3D = null


## Release all statically cached sculpted ArrayMeshes, PBR materials, and WeakRef textures cleanly.
static func clear_shared_cache() -> void:
	for mat: StandardMaterial3D in [_oak_mat, _iron_mat, _brass_mat, _rope_mat]:
		if mat != null:
			mat.normal_texture = null
			mat.roughness_texture = null
	_pedestal_oak_mesh = null
	_pedestal_iron_mesh = null
	_yoke_mesh = null
	_launcher_iron_mesh = null
	_launcher_brass_mesh = null
	_winch_drum_mesh = null
	_winch_crank_mesh = null
	_spear_mesh = null
	_rope_tube_mesh = null
	_muzzle_spark_mesh = null
	_lock_glint_mesh = null
	_oak_mat = null
	_iron_mat = null
	_brass_mat = null
	_rope_mat = null
	_pbr_tex_cache.clear()


func _enter_tree() -> void:
	_active_instances += 1


func _ready() -> void:
	_ensure_shared_assets()
	_build_visuals()
	_ray_params.collision_mask = TETHER_HIT_MASK
	_ray_params.collide_with_areas = false
	_ray_params.collide_with_bodies = true
	_apply_aim_transforms()
	_sync_spear_and_rope_visuals()
	_sync_muzzle_spark_visual()
	_sync_lock_glint_visual()


func _exit_tree() -> void:
	if _snagged_carryable != null and is_instance_valid(_snagged_carryable) and Net.is_host():
		_finish_carryable_drop(_snagged_carryable)
	_snagged_carryable = null
	tether_target_ship = null
	ship = null
	for mi: MeshInstance3D in [
		_pedestal_oak_mi, _pedestal_iron_mi, _yoke_mi,
		_launcher_iron_mi, _launcher_brass_mi,
		_winch_drum_mi, _winch_crank_mi, _spear_mi, _rope_mi,
		_muzzle_spark_mi, _lock_glint_mi
	]:
		if mi != null and is_instance_valid(mi):
			mi.material_override = null
			mi.mesh = null
	_pedestal_oak_mi = null
	_pedestal_iron_mi = null
	_yoke_mi = null
	_launcher_iron_mi = null
	_launcher_brass_mi = null
	_winch_drum_mi = null
	_winch_crank_mi = null
	_spear_mi = null
	_rope_mi = null
	_muzzle_spark_mi = null
	_muzzle_spark_mat = null
	_lock_glint_mi = null
	_lock_glint_mat = null
	_muzzle_spark_timer = 0.0
	_has_loot_lock = false
	_visual_root = null
	_yaw_pivot = null
	_pitch_pivot = null
	_winch_pivot = null
	_muzzle_point = null
	_spear_node = null
	_ray_params = null
	_ray_result = null
	_exclude_rids.clear()
	_active_instances = maxi(0, _active_instances - 1)
	if _active_instances == 0:
		clear_shared_cache()


# ==============================================================================
# Public API
# ==============================================================================

## Host only. Directly set harpoon aim yaw ([-1.02, +1.02]) and pitch ([-0.50, +0.38]) in radians.
func aim(yaw_rad: float, pitch_rad: float) -> void:
	if not Net.is_host():
		return
	aim_yaw = clampf(yaw_rad, YAW_MIN, YAW_MAX)
	aim_pitch = clampf(pitch_rad, PITCH_MIN, PITCH_MAX)
	_apply_aim_transforms()


## Host only. Incrementally adjust harpoon aim by (dyaw, dpitch) radians.
func aim_delta(dyaw: float, dpitch: float) -> void:
	if not Net.is_host():
		return
	aim(aim_yaw + dyaw, aim_pitch + dpitch)


## World-space muzzle position at the tip of the harpoon barrel.
func get_muzzle_world_pos() -> Vector3:
	if _muzzle_point != null and is_instance_valid(_muzzle_point) and _muzzle_point.is_inside_tree():
		return _muzzle_point.global_position
	return global_transform * Vector3(0.0, 0.94 * visual_scale, -0.78 * visual_scale)


## Unit world-space aim direction (-Z of the pitched harpoon barrel).
func get_aim_direction_world() -> Vector3:
	if _pitch_pivot != null and is_instance_valid(_pitch_pivot) and _pitch_pivot.is_inside_tree():
		var d := -_pitch_pivot.global_basis.z
		if d.length_squared() > 1e-6:
			return d.normalized()
	var local_b := Basis(Vector3.UP, aim_yaw) * Basis(Vector3.RIGHT, aim_pitch)
	return (global_basis * (-local_b.z)).normalized()


## Return the sculpted additive HarpoonMuzzleSpark MeshInstance3D mounted at _muzzle_point.
func get_muzzle_spark_node() -> MeshInstance3D:
	return _muzzle_spark_mi


## Return the sculpted additive HarpoonLockGlint MeshInstance3D mounted near the stowed spear tip.
func get_lock_glint_node() -> MeshInstance3D:
	return _lock_glint_mi


## True when a snag-able Carryable, SupplyBarrel, or FlotsamCluster sits in the 2.6 m loot cone
## up to 38.0 m while the harpoon is stowed in State.IDLE (read-only, zero side effects).
func has_magnetic_loot_target() -> bool:
	if not is_inside_tree() or state != State.IDLE:
		return false
	var muzzle := get_muzzle_world_pos()
	var aim_dir := get_aim_direction_world()
	return not _find_cone_loot_target(muzzle, aim_dir).is_empty()


## Immediately evaluate the magnetic loot cone and update HarpoonLockGlint visibility.
func refresh_lock_glint() -> bool:
	_lock_glint_poll_accum = 0.0
	_has_loot_lock = has_magnetic_loot_target()
	_sync_lock_glint_visual()
	return _has_loot_lock


## Total sculpted triangle count across all MeshInstance3D nodes in this ShipHarpoon.
func get_triangle_count() -> int:
	var tris := 0
	for mi: MeshInstance3D in [
		_pedestal_oak_mi, _pedestal_iron_mi, _yoke_mi,
		_launcher_iron_mi, _launcher_brass_mi,
		_winch_drum_mi, _winch_crank_mi, _spear_mi, _rope_mi,
		_muzzle_spark_mi, _lock_glint_mi
	]:
		if mi != null and mi.mesh is ArrayMesh:
			var am := mi.mesh as ArrayMesh
			for si in am.get_surface_count():
				var ilen := am.surface_get_array_index_len(si)
				if ilen > 0:
					tris += floori(float(ilen) / 3.0)
				else:
					tris += floori(float(am.surface_get_array_len(si)) / 3.0)
	return tris


## Host only. Fire the bow harpoon: snags floating loot inside a 2.6 m cone up to 38.0 m,
## or tethers solid terrain/piers/other ship hulls via swept raycast.
func fire(shooter_pawn: Node = null) -> Dictionary:
	if not Net.is_host() or not is_inside_tree():
		return {"hit": false, "kind": &"none"}
	if cooldown > 0.0:
		return {"hit": false, "kind": &"cooldown"}
	if state == State.REELING_LOOT or state == State.EXTENDING or state == State.RETRACTING:
		return {"hit": false, "kind": &"busy"}
	if state == State.TETHERED:
		release(false)

	cooldown = FIRE_COOLDOWN
	_recoil = 0.14
	_winch_spin_vel = 18.0
	_apply_aim_transforms()
	_trigger_muzzle_spark()
	_has_loot_lock = false
	_lock_glint_poll_accum = 0.0
	_sync_lock_glint_visual()

	var muzzle := get_muzzle_world_pos()
	var aim_dir := get_aim_direction_world()

	# 1. Generous 2.6 m magnetic grab cone along the aim ray up to 38.0 m for loot & supplies.
	var loot_hit := _find_cone_loot_target(muzzle, aim_dir)
	if not loot_hit.is_empty():
		var hit_kind: StringName = loot_hit["kind"]
		var hit_node: Node3D = loot_hit["node"] as Node3D
		Audio.play_sfx(&"pistol_shot", muzzle, -1.5)
		Audio.play_sfx(&"rope_creak", muzzle, -2.0)

		if hit_kind == &"carryable" and hit_node is Carryable:
			var item := hit_node as Carryable
			var label := _ascii_clean(String(item.get_meta(&"treasure_name", item.item_name)))
			if label == "":
				label = "Treasure"
			_begin_carryable_reel(item, aim_dir)
			_emit_ocean_splash_foam(_reel_start_pos, false)
			loot_snagged.emit(label)
			var res_loot := {
				"hit": true,
				"kind": &"loot",
				"target": item,
				"label": label,
				"position": _reel_start_pos,
			}
			fired.emit(res_loot)
			return res_loot

		elif hit_kind == &"supply_barrel" and hit_node != null:
			var label := _collect_supply_barrel(hit_node, shooter_pawn)
			var barrel_pos := hit_node.global_position
			_begin_quick_retract(barrel_pos + Vector3.UP * 0.45, aim_dir)
			_emit_ocean_splash_foam(barrel_pos, false)
			loot_snagged.emit(label)
			var res_barrel := {
				"hit": true,
				"kind": &"supply_barrel",
				"target": hit_node,
				"label": label,
				"position": barrel_pos,
			}
			fired.emit(res_barrel)
			return res_barrel

		elif hit_kind == &"flotsam" and hit_node != null:
			var label := _collect_flotsam_cluster(hit_node, shooter_pawn)
			var flotsam_pos := hit_node.global_position
			_begin_quick_retract(flotsam_pos + Vector3.UP * 0.25, aim_dir)
			_emit_ocean_splash_foam(flotsam_pos, true)
			loot_snagged.emit(label)
			var res_flotsam := {
				"hit": true,
				"kind": &"flotsam",
				"target": hit_node,
				"label": label,
				"position": flotsam_pos,
			}
			fired.emit(res_flotsam)
			return res_flotsam

	# 2. Swept physics raycast against terrain/piers (layer 1) + other ships (layer 2).
	var world := get_world_3d()
	if world != null and _ray_params != null:
		_exclude_rids.clear()
		if ship is CollisionObject3D and is_instance_valid(ship):
			_exclude_rids.append((ship as CollisionObject3D).get_rid())
		if shooter_pawn is CollisionObject3D and is_instance_valid(shooter_pawn):
			_exclude_rids.append((shooter_pawn as CollisionObject3D).get_rid())
		_ray_params.exclude = _exclude_rids
		_ray_params.from = muzzle
		_ray_params.to = muzzle + aim_dir * MAX_RANGE

		var space := world.direct_space_state
		var got_hit := false
		var hit_pos := Vector3.ZERO
		var hit_collider: Object = null
		if _ray_result != null and space.has_method(&"intersect_ray_into"):
			if bool(space.call(&"intersect_ray_into", _ray_params, _ray_result)):
				got_hit = true
				hit_pos = _ray_result.get(&"position") as Vector3
				hit_collider = _ray_result.get(&"collider") as Object
		else:
			var hit_dict := space.intersect_ray(_ray_params)
			if not hit_dict.is_empty():
				got_hit = true
				hit_pos = hit_dict["position"] as Vector3
				hit_collider = hit_dict["collider"] as Object

		if got_hit:
			var hit_ship := _find_other_ship(hit_collider as Node)
			state = State.TETHERED
			tether_target_ship = hit_ship
			tether_world_pos = hit_pos
			if hit_ship != null:
				tether_local_offset = hit_ship.global_transform.affine_inverse() * hit_pos
			else:
				tether_local_offset = Vector3.ZERO
			tether_length = clampf(muzzle.distance_to(hit_pos), AUTO_RELEASE_MIN_DIST, MAX_RANGE)
			_tether_spear_dir = aim_dir
			is_reeling = false
			_sync_spear_and_rope_visuals()
			Audio.play_sfx(&"pistol_shot", muzzle, -1.5)
			Audio.play_sfx(&"capstan_clank", hit_pos, -0.5)
			tethered.emit(hit_pos)
			var res_tether := {
				"hit": true,
				"kind": &"tether",
				"position": hit_pos,
				"collider": hit_collider,
				"target_ship": hit_ship,
			}
			fired.emit(res_tether)
			return res_tether

	# 3. Miss in open water/air: shoot out briefly (0.32 s) with splash_small & wave foam, then retract cleanly.
	var miss_dist := 22.0
	var hit_waves := false
	if aim_dir.y < -0.04:
		var sea_y := Sea.height(muzzle.x + aim_dir.x * 12.0, muzzle.z + aim_dir.z * 12.0) if Sea != null else 0.0
		var t_water := (sea_y - muzzle.y) / aim_dir.y
		if t_water > 1.5 and t_water < MAX_RANGE:
			miss_dist = t_water
			hit_waves = true
	_flight_target_pos = muzzle + aim_dir * minf(miss_dist, MAX_RANGE)
	_flight_elapsed = 0.0
	_flight_duration = MISS_FLIGHT_DURATION
	_tether_spear_dir = aim_dir
	state = State.EXTENDING
	_sync_spear_and_rope_visuals()
	_emit_ocean_splash_foam(_flight_target_pos, hit_waves)
	Audio.play_sfx(&"pistol_shot", muzzle, -2.0)
	Audio.play_sfx(&"splash_small", _flight_target_pos, -1.0)
	var res_miss := {
		"hit": false,
		"kind": &"miss",
		"position": _flight_target_pos,
	}
	fired.emit(res_miss)
	return res_miss


## Host only. Reel an active tether (`[Hold RMB]`), pulling the ship's bow smoothly toward the anchor.
func reel(active: bool, delta: float) -> void:
	is_reeling = active and state == State.TETHERED
	if not Net.is_host() or state != State.TETHERED:
		return
	_reeled_this_tick = true
	_step_tether_physics(active, delta)


## Host only. Snap and release any active tether cleanly, returning spear to loaded IDLE state.
func release(play_audio: bool = true) -> void:
	if not Net.is_host():
		return
	var was_active := state != State.IDLE
	if _snagged_carryable != null and is_instance_valid(_snagged_carryable):
		_finish_carryable_drop(_snagged_carryable)
	_snagged_carryable = null
	tether_target_ship = null
	tether_local_offset = Vector3.ZERO
	tether_world_pos = Vector3.ZERO
	tether_length = 0.0
	is_reeling = false
	state = State.IDLE
	_has_loot_lock = false
	_lock_glint_poll_accum = 0.0
	_sync_spear_and_rope_visuals()
	_sync_lock_glint_visual()
	if was_active:
		if play_audio and is_inside_tree():
			Audio.play_sfx(&"rope_creak", get_muzzle_world_pos(), -2.0)
		released.emit()


# ==============================================================================
# Simulation & Visual Tick
# ==============================================================================

## Deterministic simulation & VFX tick (called from _physics_process and directly testable).
func step_harpoon(delta: float) -> void:
	if cooldown > 0.0:
		cooldown = maxf(0.0, cooldown - delta)

	if _muzzle_spark_timer > 0.0:
		_muzzle_spark_timer = maxf(0.0, _muzzle_spark_timer - delta)
		if _muzzle_spark_timer <= 0.0001:
			_muzzle_spark_timer = 0.0
		_sync_muzzle_spark_visual()

	if state == State.IDLE:
		_lock_glint_poll_accum += delta
		if _lock_glint_poll_accum >= LOCK_GLINT_POLL_INTERVAL:
			_lock_glint_poll_accum = 0.0
			_has_loot_lock = has_magnetic_loot_target()
		if _has_loot_lock:
			_lock_glint_clock += delta
	else:
		_lock_glint_poll_accum = 0.0
		_has_loot_lock = false
	_sync_lock_glint_visual()

	if not Net.is_host():
		return

	match state:
		State.REELING_LOOT:
			_step_loot_reel(delta)
		State.EXTENDING:
			_flight_elapsed += delta
			if _flight_elapsed >= _flight_duration:
				state = State.RETRACTING
				_flight_elapsed = 0.0
				_flight_duration = 0.24
		State.RETRACTING:
			_flight_elapsed += delta
			if _flight_elapsed >= _flight_duration:
				state = State.IDLE
		State.TETHERED:
			if not _reeled_this_tick:
				is_reeling = false
				_step_tether_physics(false, delta)
			_reeled_this_tick = false


func _physics_process(delta: float) -> void:
	step_harpoon(delta)


func _process(delta: float) -> void:
	_recoil = move_toward(_recoil, 0.0, delta * 0.72)
	if absf(_winch_spin_vel) > 0.05:
		if _winch_pivot != null and is_instance_valid(_winch_pivot):
			_winch_pivot.rotate_x(_winch_spin_vel * delta)
		_winch_spin_vel = move_toward(_winch_spin_vel, 0.0, delta * 24.0)
	_apply_aim_transforms()
	_sync_spear_and_rope_visuals()


func _step_loot_reel(delta: float) -> void:
	_reel_elapsed += delta
	_winch_spin_vel = -15.0
	var t := clampf(_reel_elapsed / maxf(_reel_duration, 0.01), 0.0, 1.0)
	var ease_t := smoothstep(0.0, 1.0, t)
	var deck_world := _get_foredeck_drop_world()
	# Graceful arc clearing the bow gunwale rail smoothly onto the foredeck.
	var arc_h := sin(t * PI) * 1.15
	var cur_pos := _reel_start_pos.lerp(deck_world, ease_t) + Vector3.UP * arc_h
	_flight_target_pos = cur_pos

	if _snagged_carryable != null and is_instance_valid(_snagged_carryable) and _snagged_carryable.is_inside_tree():
		_snagged_carryable.global_position = cur_pos
	else:
		_snagged_carryable = null

	if t >= 1.0:
		if _snagged_carryable != null and is_instance_valid(_snagged_carryable):
			_finish_carryable_drop(_snagged_carryable)
		_snagged_carryable = null
		state = State.IDLE
		Audio.play_sfx(&"capstan_clank", deck_world, -4.5)


func _step_tether_physics(active_reel: bool, delta: float) -> void:
	if tether_target_ship != null:
		if not is_instance_valid(tether_target_ship) or not tether_target_ship.is_inside_tree():
			release(true)
			return
		tether_world_pos = tether_target_ship.global_transform * tether_local_offset

	var muzzle := get_muzzle_world_pos()
	var to_anchor := tether_world_pos - muzzle
	var dist := to_anchor.length()
	if dist > AUTO_RELEASE_MAX_DIST or dist < AUTO_RELEASE_MIN_DIST:
		release(true)
		return

	if active_reel:
		tether_length = maxf(AUTO_RELEASE_MIN_DIST, tether_length - REEL_SPEED * delta)
		_winch_spin_vel = -14.0
		_reel_sfx_accum += delta
		if _reel_sfx_accum >= 0.42:
			_reel_sfx_accum = 0.0
			Audio.play_sfx(&"rope_creak", muzzle, -3.0)
	else:
		_reel_sfx_accum = 0.0

	if not (ship is RigidBody3D) or not is_instance_valid(ship):
		return
	var rb := ship as RigidBody3D
	if bool(rb.get(&"is_sinking")):
		release(false)
		return

	var horiz := Vector3(to_anchor.x, clampf(to_anchor.y * 0.12, -0.18, 0.18), to_anchor.z)
	if horiz.length_squared() < 1e-6:
		return
	var pull_dir := horiz.normalized()

	var max_force := rb.mass * 6.5
	var force_mag := 0.0
	if active_reel:
		# Smooth bounded traction pulling the ship's bow cleanly toward tether_world_pos.
		var closing_spd := rb.linear_velocity.dot(pull_dir)
		var speed_scale := clampf(1.0 - maxf(0.0, closing_spd - 4.5) / 5.0, 0.18, 1.0)
		force_mag = minf(rb.mass * 5.2 * speed_scale, max_force)
	elif dist > tether_length + 0.35:
		# Taut hawser snubbing keeps a docked/tethered ship pivoting cleanly without snapping.
		var stretch := dist - (tether_length + 0.35)
		force_mag = minf(stretch * rb.mass * 1.4, rb.mass * 3.5)

	if force_mag > 1.0:
		var rel_pos := muzzle - rb.global_position
		# Keep vertical lever arm modest so harpoon traction turns & pulls without rolling/flipping.
		rel_pos.y = clampf(rel_pos.y, -0.35, 0.35)
		rb.apply_force(pull_dir * force_mag, rel_pos)

		# Equal-and-opposite mild reaction on a tethered rival ship so ship-to-ship grappling feels alive!
		if tether_target_ship is RigidBody3D and is_instance_valid(tether_target_ship):
			var other_rb := tether_target_ship as RigidBody3D
			var other_max := other_rb.mass * 4.0
			var other_f := minf(force_mag * 0.55, other_max)
			var other_rel := tether_world_pos - other_rb.global_position
			other_rel.y = clampf(other_rel.y, -0.35, 0.35)
			other_rb.apply_force(-pull_dir * other_f, other_rel)


# ==============================================================================
# Loot Discovery & Landing Helpers
# ==============================================================================

func _find_cone_loot_target(muzzle: Vector3, aim_dir: Vector3) -> Dictionary:
	var tree := get_tree()
	if tree == null:
		return {}
	var best_score := INF
	var best_result: Dictionary = {}
	var seen_ids: Dictionary = {}

	# 1. Floating / shoreline Carryable treasures (check carryables, treasure, and Interactable parents).
	var carry_candidates: Array[Carryable] = []
	for grp: StringName in [&"carryables", &"treasure"]:
		for n in tree.get_nodes_in_group(grp):
			if n is Carryable:
				carry_candidates.append(n as Carryable)
	for it_node in tree.get_nodes_in_group(Interactable.GROUP):
		if it_node != null and it_node.get_parent() is Carryable:
			carry_candidates.append(it_node.get_parent() as Carryable)

	for item in carry_candidates:
		if item == null or not is_instance_valid(item) or not item.is_inside_tree():
			continue
		var iid := item.get_instance_id()
		if seen_ids.has(iid):
			continue
		seen_ids[iid] = true
		if not item.visible or item.is_held() or item.stored_in != null:
			continue
		var target_pos := item.global_position + Vector3.UP * 0.25
		var score := _cone_score(muzzle, aim_dir, target_pos)
		if score < best_score:
			best_score = score
			best_result = {"kind": &"carryable", "node": item}

	# 2. SupplyBarrels on shoreline / piers.
	for b_node in tree.get_nodes_in_group(&"supply_barrels"):
		if not (b_node is Node3D) or not is_instance_valid(b_node) or not b_node.is_inside_tree():
			continue
		var bn := b_node as Node3D
		if not bn.visible or bool(bn.get(&"looted")):
			continue
		var score := _cone_score(muzzle, aim_dir, bn.global_position + Vector3.UP * 0.45)
		if score < best_score:
			best_score = score
			best_result = {"kind": &"supply_barrel", "node": bn}

	# 3. Floating FlotsamClusters (check both &"flotsam" and &"flotsam_clusters").
	for grp_f: StringName in [&"flotsam", &"flotsam_clusters"]:
		for f_node in tree.get_nodes_in_group(grp_f):
			if not (f_node is Node3D) or not is_instance_valid(f_node) or not f_node.is_inside_tree():
				continue
			var fn := f_node as Node3D
			var fid := fn.get_instance_id()
			if seen_ids.has(fid):
				continue
			seen_ids[fid] = true
			if not fn.visible or bool(fn.get(&"salvaged")):
				continue
			var score := _cone_score(muzzle, aim_dir, fn.global_position + Vector3.UP * 0.25)
			if score < best_score:
				best_score = score
				best_result = {"kind": &"flotsam", "node": fn}

	return best_result


static func _cone_score(muzzle: Vector3, aim_dir: Vector3, target_pos: Vector3) -> float:
	var to_target := target_pos - muzzle
	var along := to_target.dot(aim_dir)
	if along < 1.2 or along > MAX_RANGE:
		return INF
	var perp := (to_target - aim_dir * along).length()
	if perp > LOOT_CONE_RADIUS:
		return INF
	return perp + along * 0.04


func _begin_carryable_reel(item: Carryable, aim_dir: Vector3) -> void:
	_snagged_carryable = item
	_reel_start_pos = item.global_position
	_reel_elapsed = 0.0
	_reel_duration = LOOT_REEL_DURATION
	_flight_target_pos = _reel_start_pos
	_tether_spear_dir = aim_dir
	state = State.REELING_LOOT

	item.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	item.freeze = true
	item.collision_layer = 0
	item.collision_mask = 0
	if item.interactable != null and is_instance_valid(item.interactable):
		item.interactable.enabled = false
	_sync_spear_and_rope_visuals()


func _finish_carryable_drop(item: Carryable) -> void:
	if item == null or not is_instance_valid(item) or not item.is_inside_tree():
		return
	var deck_world := _get_foredeck_drop_world()
	item.global_position = deck_world
	item.freeze = false
	item.collision_layer = Carryable.LAYER
	item.collision_mask = Carryable.MASK
	if item.interactable != null and is_instance_valid(item.interactable):
		item.interactable.enabled = true
	if ship is RigidBody3D and is_instance_valid(ship):
		var rb := ship as RigidBody3D
		var rel := deck_world - rb.global_position
		item.linear_velocity = rb.linear_velocity + rb.angular_velocity.cross(rel)
	else:
		item.linear_velocity = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO


func _get_foredeck_drop_world() -> Vector3:
	var side_sign := -1.0 if side == &"port" else 1.0
	var is_brig := ship != null and is_instance_valid(ship) \
		and ship.has_method(&"is_brigantine") and bool(ship.call(&"is_brigantine"))
	var unscaled := Vector3(side_sign * 1.15, 1.42, -5.50) if is_brig else Vector3(side_sign * 0.95, 1.25, -3.55)
	if ship != null and is_instance_valid(ship):
		var local_pt: Vector3 = ship.call(&"ship_point", unscaled) if ship.has_method(&"ship_point") else (unscaled * visual_scale)
		return ship.global_transform * local_pt
	return global_position + Vector3(0.0, 0.25, 0.8)


func _collect_supply_barrel(barrel: Node3D, shooter_pawn: Node) -> String:
	var loot: Dictionary = {}
	if barrel.has_method(&"take_all"):
		var raw: Variant = barrel.call(&"take_all", shooter_pawn)
		if raw is Dictionary:
			loot = raw as Dictionary
	var balls := int(loot.get("cannonballs", 0))
	var planks := int(loot.get("planks", 0))
	_grant_ship_supplies(balls, planks, 0)
	if balls > 0 or planks > 0:
		return "Supplies (+%d balls, +%d planks)" % [balls, planks]
	return "Supply Barrel"


func _collect_flotsam_cluster(cluster: Node3D, shooter_pawn: Node) -> String:
	var loot: Dictionary = {}
	if cluster.has_method(&"salvage"):
		var raw: Variant = cluster.call(&"salvage", shooter_pawn)
		if raw is Dictionary:
			loot = raw as Dictionary
	var balls := int(loot.get("cannonballs", 0))
	var planks := int(loot.get("planks", 0))
	var gold := int(loot.get("gold", 0))
	_grant_ship_supplies(balls, planks, gold)
	if gold > 0:
		return "Flotsam (+%d gold, +%d balls)" % [gold, balls]
	return "Flotsam Salvage"


func _grant_ship_supplies(balls: int, planks: int, gold: int) -> void:
	if ship != null and is_instance_valid(ship):
		if balls > 0 and ship.get(&"cannonballs_remaining") != null:
			ship.set(&"cannonballs_remaining", int(ship.get(&"cannonballs_remaining")) + balls)
		if planks > 0 and ship.get(&"planks_remaining") != null:
			ship.set(&"planks_remaining", int(ship.get(&"planks_remaining")) + planks)
	if gold > 0 and Game != null and Game.profile != null and Game.profile.has_method(&"add_gold"):
		Game.profile.call(&"add_gold", gold)


func _begin_quick_retract(target_world: Vector3, aim_dir: Vector3) -> void:
	_flight_target_pos = target_world
	_flight_elapsed = 0.0
	_flight_duration = 0.34
	_tether_spear_dir = aim_dir
	state = State.RETRACTING
	_sync_spear_and_rope_visuals()


func _find_other_ship(node: Node) -> Node3D:
	var n := node
	while n != null:
		if n is Node3D and n != ship and (n.is_in_group(&"ship") or n.has_method(&"apply_hull_damage")):
			return n as Node3D
		n = n.get_parent()
	return null


static func _ascii_clean(txt: String) -> String:
	var out := ""
	for i in txt.length():
		var c := txt.unicode_at(i)
		if c >= 32 and c < 127:
			out += txt[i]
		else:
			out += " "
	return out.strip_edges()


# ==============================================================================
# Visual Transforms & Rope Stretching
# ==============================================================================

func _apply_aim_transforms() -> void:
	if _yaw_pivot != null and is_instance_valid(_yaw_pivot):
		_yaw_pivot.rotation.y = aim_yaw
	if _pitch_pivot != null and is_instance_valid(_pitch_pivot):
		_pitch_pivot.rotation.x = aim_pitch
		_pitch_pivot.position = Vector3(0.0, 0.14, _recoil)


func _sync_spear_and_rope_visuals() -> void:
	if _spear_node == null or not is_instance_valid(_spear_node):
		return
	if _rope_mi == null or not is_instance_valid(_rope_mi):
		return
	if not is_inside_tree():
		_rope_mi.visible = false
		return

	var muzzle := get_muzzle_world_pos()
	if state == State.IDLE:
		_spear_node.visible = true
		var aim_dir := get_aim_direction_world()
		_orient_spear_world(muzzle, aim_dir)
		_rope_mi.visible = false
		return

	var spear_world := muzzle
	match state:
		State.TETHERED:
			spear_world = tether_world_pos
		State.REELING_LOOT:
			spear_world = _flight_target_pos
		State.EXTENDING:
			var t_ext := clampf(_flight_elapsed / maxf(_flight_duration, 0.01), 0.0, 1.0)
			spear_world = muzzle.lerp(_flight_target_pos, smoothstep(0.0, 1.0, t_ext))
		State.RETRACTING:
			var t_ret := clampf(_flight_elapsed / maxf(_flight_duration, 0.01), 0.0, 1.0)
			spear_world = _flight_target_pos.lerp(muzzle, smoothstep(0.0, 1.0, t_ret))

	_spear_node.visible = true
	var seg := spear_world - muzzle
	var dist := seg.length()
	var dir := seg / dist if dist > 0.01 else _tether_spear_dir
	_orient_spear_world(spear_world, dir)

	if dist > 0.08:
		_rope_mi.visible = true
		var ref_up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
		var rx := ref_up.cross(dir).normalized()
		var ry := dir.cross(rx).normalized()
		_rope_mi.global_transform = Transform3D(Basis(rx, ry, seg), muzzle)
	else:
		_rope_mi.visible = false


func _orient_spear_world(pos: Vector3, forward_dir: Vector3) -> void:
	var f := forward_dir.normalized() if forward_dir.length_squared() > 1e-6 else Vector3.FORWARD
	var ref_up := Vector3.UP if absf(f.y) < 0.98 else Vector3.RIGHT
	var x := f.cross(ref_up).normalized()
	var y := x.cross(f).normalized()
	# Spear mesh extends forward along local -Z, so Basis(x, y, -f).
	_spear_node.global_transform = Transform3D(Basis(x, y, -f) * Basis.from_scale(Vector3.ONE * visual_scale), pos)


func _trigger_muzzle_spark() -> void:
	_muzzle_spark_timer = MUZZLE_SPARK_DURATION
	_sync_muzzle_spark_visual()


func _sync_muzzle_spark_visual() -> void:
	if _muzzle_spark_mi == null or not is_instance_valid(_muzzle_spark_mi):
		return
	if _muzzle_spark_timer <= 0.0:
		_muzzle_spark_mi.visible = false
		_muzzle_spark_mi.scale = Vector3.ONE * 0.1
		if _muzzle_spark_mat != null:
			_muzzle_spark_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
		return
	var u := clampf(1.0 - _muzzle_spark_timer / MUZZLE_SPARK_DURATION, 0.0, 1.0)
	var expand := lerpf(0.72, 1.38, smoothstep(0.0, 0.28, u))
	var taper := lerpf(1.0, 0.58, smoothstep(0.45, 1.0, u))
	var sc := expand * taper
	var energy := 1.48 * pow(1.0 - u, 1.45)
	_muzzle_spark_mi.visible = true
	_muzzle_spark_mi.scale = Vector3(sc, sc, sc)
	if _muzzle_spark_mat != null:
		_muzzle_spark_mat.albedo_color = Color(energy, energy, energy, 1.0)


func _sync_lock_glint_visual() -> void:
	if _lock_glint_mi == null or not is_instance_valid(_lock_glint_mi):
		return
	var active := _has_loot_lock and state == State.IDLE and is_inside_tree()
	if not active:
		_lock_glint_mi.visible = false
		if _lock_glint_mat != null:
			_lock_glint_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
		return
	var pulse := 0.5 + 0.5 * sin(_lock_glint_clock * 7.5)
	var energy := lerpf(0.78, 1.38, pulse)
	var sc := lerpf(0.86, 1.18, pulse)
	_lock_glint_mi.visible = true
	_lock_glint_mi.scale = Vector3(sc, sc, sc)
	if _lock_glint_mat != null:
		_lock_glint_mat.albedo_color = Color(energy, energy, energy, 1.0)


func _emit_ocean_splash_foam(hit_pos: Vector3, force_water: bool) -> void:
	if Ocean.current == null or not is_instance_valid(Ocean.current):
		return
	if not Ocean.current.has_method(&"add_foam"):
		return
	if not force_water:
		var sea_y := Sea.height(hit_pos.x, hit_pos.z) if Sea != null else 0.0
		if hit_pos.y > sea_y + 2.8:
			return
	Ocean.current.add_foam(hit_pos, 1.35, 0.58)


# ==============================================================================
# Scene Construction & Shared WeakRef PBR Asset Builders (0 Primitives)
# ==============================================================================

func _build_visuals() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "HarpoonVisualRoot"
	_visual_root.scale = Vector3.ONE * visual_scale
	add_child(_visual_root)

	_pedestal_oak_mi = MeshInstance3D.new()
	_pedestal_oak_mi.name = "HarpoonPedestalOak"
	_pedestal_oak_mi.mesh = _pedestal_oak_mesh
	_pedestal_oak_mi.material_override = _oak_mat
	_visual_root.add_child(_pedestal_oak_mi)

	_pedestal_iron_mi = MeshInstance3D.new()
	_pedestal_iron_mi.name = "HarpoonPedestalIron"
	_pedestal_iron_mi.mesh = _pedestal_iron_mesh
	_pedestal_iron_mi.material_override = _iron_mat
	_visual_root.add_child(_pedestal_iron_mi)

	_yaw_pivot = Node3D.new()
	_yaw_pivot.name = "HarpoonYawPivot"
	_yaw_pivot.position = Vector3(0.0, 0.80, 0.0)
	_visual_root.add_child(_yaw_pivot)

	_yoke_mi = MeshInstance3D.new()
	_yoke_mi.name = "HarpoonSwivelYoke"
	_yoke_mi.mesh = _yoke_mesh
	_yoke_mi.material_override = _iron_mat
	_yaw_pivot.add_child(_yoke_mi)

	_pitch_pivot = Node3D.new()
	_pitch_pivot.name = "HarpoonPitchPivot"
	_pitch_pivot.position = Vector3(0.0, 0.14, 0.0)
	_yaw_pivot.add_child(_pitch_pivot)

	_launcher_iron_mi = MeshInstance3D.new()
	_launcher_iron_mi.name = "HarpoonLauncherIron"
	_launcher_iron_mi.mesh = _launcher_iron_mesh
	_launcher_iron_mi.material_override = _iron_mat
	_pitch_pivot.add_child(_launcher_iron_mi)

	_launcher_brass_mi = MeshInstance3D.new()
	_launcher_brass_mi.name = "HarpoonLauncherBrass"
	_launcher_brass_mi.mesh = _launcher_brass_mesh
	_launcher_brass_mi.material_override = _brass_mat
	_pitch_pivot.add_child(_launcher_brass_mi)

	_winch_pivot = Node3D.new()
	_winch_pivot.name = "HarpoonWinchPivot"
	_winch_pivot.position = Vector3(0.20, -0.04, 0.12)
	_pitch_pivot.add_child(_winch_pivot)

	_winch_drum_mi = MeshInstance3D.new()
	_winch_drum_mi.name = "HarpoonWinchRope"
	_winch_drum_mi.mesh = _winch_drum_mesh
	_winch_drum_mi.material_override = _rope_mat
	_winch_pivot.add_child(_winch_drum_mi)

	_winch_crank_mi = MeshInstance3D.new()
	_winch_crank_mi.name = "HarpoonWinchCrank"
	_winch_crank_mi.mesh = _winch_crank_mesh
	_winch_crank_mi.material_override = _brass_mat
	_winch_pivot.add_child(_winch_crank_mi)

	_muzzle_point = Node3D.new()
	_muzzle_point.name = "MuzzlePoint"
	_muzzle_point.position = Vector3(0.0, 0.04, -0.78)
	_pitch_pivot.add_child(_muzzle_point)

	_muzzle_spark_mat = _make_vfx_billboard_mat()
	_muzzle_spark_mi = MeshInstance3D.new()
	_muzzle_spark_mi.name = "HarpoonMuzzleSpark"
	_muzzle_spark_mi.mesh = _muzzle_spark_mesh
	_muzzle_spark_mi.material_override = _muzzle_spark_mat
	_muzzle_spark_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_muzzle_spark_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_muzzle_spark_mi.visible = false
	_muzzle_point.add_child(_muzzle_spark_mi)

	_spear_node = Node3D.new()
	_spear_node.name = "HarpoonSpear"
	add_child(_spear_node)

	_spear_mi = MeshInstance3D.new()
	_spear_mi.name = "HarpoonSpearMesh"
	_spear_mi.mesh = _spear_mesh
	_spear_mi.material_override = _iron_mat
	_spear_node.add_child(_spear_mi)

	_lock_glint_mat = _make_vfx_billboard_mat()
	_lock_glint_mi = MeshInstance3D.new()
	_lock_glint_mi.name = "HarpoonLockGlint"
	_lock_glint_mi.position = Vector3(0.0, 0.0, -0.72)
	_lock_glint_mi.mesh = _lock_glint_mesh
	_lock_glint_mi.material_override = _lock_glint_mat
	_lock_glint_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lock_glint_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_lock_glint_mi.visible = false
	_spear_node.add_child(_lock_glint_mi)

	_rope_mi = MeshInstance3D.new()
	_rope_mi.name = "HarpoonRopeLine"
	_rope_mi.mesh = _rope_tube_mesh
	_rope_mi.material_override = _rope_mat
	_rope_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rope_mi.visible = false
	add_child(_rope_mi)


static func _make_vfx_billboard_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = false
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	return mat


static func _load_pbr_tex(path: String) -> Texture2D:
	if path == "":
		return null
	if _pbr_tex_cache.has(path):
		var wr: Variant = _pbr_tex_cache[path]
		if wr is WeakRef:
			var obj: Variant = (wr as WeakRef).get_ref()
			if obj is Texture2D:
				return obj as Texture2D
	if not ResourceLoader.exists(path):
		return null
	var loaded: Variant = ResourceLoader.load(path)
	if loaded is Texture2D:
		var tex := loaded as Texture2D
		_pbr_tex_cache[path] = weakref(tex)
		return tex
	return null


static func _make_pbr_mat(roughness: float, metallic: float, norm_path: String, rough_path: String,
		tri_scale: Vector3, norm_scale: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = roughness
	mat.metallic = metallic
	# Object-space triplanar mapping prevents texture swimming on rotating harpoon parts.
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = false
	mat.uv1_scale = tri_scale
	var ntex := _load_pbr_tex(norm_path)
	var rtex := _load_pbr_tex(rough_path)
	if ntex != null:
		mat.normal_enabled = true
		mat.normal_scale = norm_scale
		mat.normal_texture = ntex
	if rtex != null:
		mat.roughness_texture = rtex
	return mat


static func _ensure_shared_assets() -> void:
	if _oak_mat == null:
		_oak_mat = _make_pbr_mat(0.78, 0.04, TEX_OAK_NORMAL, TEX_OAK_ROUGH, Vector3(1.8, 1.8, 1.8), 0.72)
	if _iron_mat == null:
		_iron_mat = _make_pbr_mat(0.44, 0.78, TEX_IRON_NORMAL, TEX_IRON_ROUGH, Vector3(2.4, 2.4, 2.4), 0.80)
	if _brass_mat == null:
		_brass_mat = _make_pbr_mat(0.28, 0.86, TEX_BRASS_NORMAL, TEX_BRASS_ROUGH, Vector3(2.6, 2.6, 2.6), 0.55)
	if _rope_mat == null:
		_rope_mat = _make_pbr_mat(0.90, 0.02, TEX_ROPE_NORMAL, TEX_ROPE_ROUGH, Vector3(3.2, 3.2, 3.2), 0.92)

	if _pedestal_oak_mesh == null:
		_pedestal_oak_mesh = _build_pedestal_oak_mesh()
	if _pedestal_iron_mesh == null:
		_pedestal_iron_mesh = _build_pedestal_iron_mesh()
	if _yoke_mesh == null:
		_yoke_mesh = _build_yoke_mesh()
	if _launcher_iron_mesh == null:
		_launcher_iron_mesh = _build_launcher_iron_mesh()
	if _launcher_brass_mesh == null:
		_launcher_brass_mesh = _build_launcher_brass_mesh()
	if _winch_drum_mesh == null:
		_winch_drum_mesh = _build_winch_drum_mesh()
	if _winch_crank_mesh == null:
		_winch_crank_mesh = _build_winch_crank_mesh()
	if _spear_mesh == null:
		_spear_mesh = _build_spear_mesh()
	if _rope_tube_mesh == null:
		_rope_tube_mesh = _build_rope_tube_mesh()
	if _muzzle_spark_mesh == null:
		_muzzle_spark_mesh = _build_muzzle_spark_mesh()
	if _lock_glint_mesh == null:
		_lock_glint_mesh = _build_lock_glint_mesh()


static func _emit_billboard_tri(st: SurfaceTool, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color) -> void:
	const FRONT_NORMAL := Vector3(0.0, 0.0, 1.0)
	st.set_normal(FRONT_NORMAL)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_normal(FRONT_NORMAL)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_normal(FRONT_NORMAL)
	st.set_color(cc)
	st.add_vertex(c)


static func _build_star_billboard_mesh(
	mid_tip_x: float,
	mid_tip_y: float,
	mid_val: float,
	out_tip_x: float,
	out_tip_y: float,
	out_val: float,
	col_core: Color,
	col_mid_tip: Color,
	col_mid_val: Color
) -> ArrayMesh:
	# Exact 24-tri 2-ring 4-point star billboard (8 inner core tris + 16 feathered outer skirt tris)
	# with finite unit (0, 0, 1) normals and zero-edge Color(0, 0, 0, 1) outer rim.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ctr := Vector3.ZERO
	var col_zero := Color(0.0, 0.0, 0.0, 1.0)
	var mid_ring: Array[Vector3] = [
		Vector3(0.0, mid_tip_y, 0.0),
		Vector3(mid_val, mid_val, 0.0),
		Vector3(mid_tip_x, 0.0, 0.0),
		Vector3(mid_val, -mid_val, 0.0),
		Vector3(0.0, -mid_tip_y, 0.0),
		Vector3(-mid_val, -mid_val, 0.0),
		Vector3(-mid_tip_x, 0.0, 0.0),
		Vector3(-mid_val, mid_val, 0.0),
	]
	var out_ring: Array[Vector3] = [
		Vector3(0.0, out_tip_y, 0.0),
		Vector3(out_val, out_val, 0.0),
		Vector3(out_tip_x, 0.0, 0.0),
		Vector3(out_val, -out_val, 0.0),
		Vector3(0.0, -out_tip_y, 0.0),
		Vector3(-out_val, -out_val, 0.0),
		Vector3(-out_tip_x, 0.0, 0.0),
		Vector3(-out_val, out_val, 0.0),
	]
	for k in 8:
		var nk := (k + 1) % 8
		var ck := col_mid_tip if (k % 2 == 0) else col_mid_val
		var cnk := col_mid_tip if (nk % 2 == 0) else col_mid_val
		_emit_billboard_tri(st, ctr, col_core, mid_ring[k], ck, mid_ring[nk], cnk)
		_emit_billboard_tri(st, mid_ring[k], ck, out_ring[k], col_zero, out_ring[nk], col_zero)
		_emit_billboard_tri(st, mid_ring[k], ck, out_ring[nk], col_zero, mid_ring[nk], cnk)
	return st.commit()


static func _build_muzzle_spark_mesh() -> ArrayMesh:
	# 24-tri 4-point brass-gold launch spark fading smoothly to black rim.
	return _build_star_billboard_mesh(
		0.22, 0.24, 0.075,
		0.52, 0.56, 0.20,
		Color(1.0, 0.98, 0.84, 1.0),
		Color(1.0, 0.78, 0.24, 1.0),
		Color(0.92, 0.60, 0.14, 1.0)
	)


static func _build_lock_glint_mesh() -> ArrayMesh:
	# 24-tri turquoise-gold diamond star magnetic-loot lock glint fading smoothly to black rim.
	return _build_star_billboard_mesh(
		0.13, 0.16, 0.055,
		0.32, 0.38, 0.14,
		Color(0.96, 1.0, 0.92, 1.0),
		Color(0.30, 0.98, 0.86, 1.0),
		Color(1.0, 0.84, 0.30, 1.0)
	)


static func _build_pedestal_oak_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Heavy tapered octagonal seasoned oak gunwale post seated from deck (-0.34) to rail crest (+0.78).
	_add_lathe(st, [
		Vector2(0.0, -0.34),
		Vector2(0.23, -0.34),
		Vector2(0.22, -0.22),
		Vector2(0.175, -0.10),
		Vector2(0.155, 0.24),
		Vector2(0.145, 0.62),
		Vector2(0.172, 0.70),
		Vector2(0.168, 0.78),
		Vector2(0.0, 0.78),
	], 8, COL_OAK_LO, COL_OAK_HI)

	# Four chamfered oak deck-knee buttresses bracing the gunwale post squarely onto the foredeck.
	for k in 4:
		var ang := float(k) * PI * 0.5 + PI * 0.25
		var b := Basis(Vector3.UP, ang)
		_add_oriented_box(st, b, b * Vector3(0.0, -0.16, 0.19), Vector3(0.075, 0.34, 0.14),
			COL_OAK_HI, COL_OAK_MID, COL_OAK_LO)

	st.generate_normals()
	return st.commit()


static func _build_pedestal_iron_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Forged-iron cinching hoop bands & top pintle socket collar gripping the oak post.
	for band_y: float in [-0.24, 0.18, 0.66]:
		var r_b := 0.236 if band_y < 0.0 else (0.166 if band_y < 0.4 else 0.182)
		_add_lathe(st, [
			Vector2(r_b - 0.014, band_y - 0.032),
			Vector2(r_b, band_y - 0.024),
			Vector2(r_b, band_y + 0.024),
			Vector2(r_b - 0.014, band_y + 0.032),
		], 8, COL_IRON_LO, COL_IRON_HI)

	# Heavy top iron swivel pintle bearing collar.
	_add_lathe(st, [
		Vector2(0.0, 0.77),
		Vector2(0.150, 0.77),
		Vector2(0.142, 0.81),
		Vector2(0.088, 0.82),
		Vector2(0.082, 0.86),
		Vector2(0.0, 0.86),
	], 10, COL_IRON_MID, COL_IRON_HI)

	st.generate_normals()
	return st.commit()


static func _build_yoke_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Forged-iron U-shaped swivel cradle yoke & trunnion cheeks supporting the launcher barrel.
	_add_lathe(st, [
		Vector2(0.0, 0.0),
		Vector2(0.105, 0.0),
		Vector2(0.112, 0.035),
		Vector2(0.095, 0.058),
		Vector2(0.0, 0.058),
	], 8, COL_IRON_LO, COL_IRON_HI)

	# Horizontal yoke bridge bar.
	_add_box(st, Vector3(0.0, 0.068, 0.0), Vector3(0.30, 0.048, 0.095), COL_IRON_HI, COL_IRON_MID, COL_IRON_LO)

	# Twin vertical forged trunnion cheeks & axle lock caps.
	for sx: float in [-1.0, 1.0]:
		_add_box(st, Vector3(sx * 0.132, 0.125, 0.0), Vector3(0.042, 0.145, 0.092),
			COL_IRON_HI, COL_IRON_MID, COL_IRON_LO)
		_add_tube(st, Vector3(sx * 0.11, 0.14, 0.0), Vector3(sx * 0.175, 0.14, 0.0),
			0.034, 0.028, 8, COL_IRON_HI, COL_IRON_LO)

	st.generate_normals()
	return st.commit()


static func _build_launcher_iron_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Main forged-iron breech cradle & slotted harpoon guide trough extending forward along -Z.
	_add_box(st, Vector3(0.0, -0.02, -0.10), Vector3(0.19, 0.13, 0.88), COL_IRON_HI, COL_IRON_MID, COL_IRON_LO)
	# Upper twin slotted barrel rails framing the brass jacket.
	for sx: float in [-1.0, 1.0]:
		_add_box(st, Vector3(sx * 0.072, 0.068, -0.24), Vector3(0.038, 0.062, 0.82),
			COL_IRON_HI, COL_IRON_MID, COL_IRON_LO)

	# Flared forged-iron muzzle ring collar at z = -0.68..-0.76.
	_add_tube(st, Vector3(0.0, 0.04, -0.64), Vector3(0.0, 0.04, -0.77), 0.096, 0.112, 10, COL_IRON_HI, COL_IRON_LO)

	# Aft heavy breech block, twin flared aiming spade handles & trigger guard.
	_add_box(st, Vector3(0.0, 0.01, 0.34), Vector3(0.17, 0.15, 0.14), COL_IRON_HI, COL_IRON_MID, COL_IRON_LO)
	for sx: float in [-1.0, 1.0]:
		_add_tube(st, Vector3(sx * 0.065, 0.03, 0.39), Vector3(sx * 0.165, 0.05, 0.56),
			0.022, 0.020, 6, COL_IRON_HI, COL_IRON_LO)
		_add_tube(st, Vector3(sx * 0.165, 0.05, 0.56), Vector3(sx * 0.165, -0.09, 0.56),
			0.022, 0.022, 6, COL_OAK_HI, COL_OAK_LO)
		_add_tube(st, Vector3(sx * 0.165, -0.09, 0.56), Vector3(sx * 0.065, -0.04, 0.39),
			0.020, 0.020, 6, COL_IRON_MID, COL_IRON_LO)

	# Trigger bar & side winch axle bracket.
	_add_box(st, Vector3(0.0, -0.08, 0.44), Vector3(0.024, 0.055, 0.09), COL_IRON_HI, COL_IRON_MID, COL_IRON_LO)
	_add_box(st, Vector3(0.14, -0.04, 0.12), Vector3(0.12, 0.075, 0.12), COL_IRON_HI, COL_IRON_MID, COL_IRON_LO)

	st.generate_normals()
	return st.commit()


static func _build_launcher_brass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Turned banded burnished-brass harpoon barrel cylinder along -Z.
	_add_tube(st, Vector3(0.0, 0.04, 0.28), Vector3(0.0, 0.04, -0.66), 0.076, 0.068, 10, COL_BRASS_HI, COL_BRASS_LO)
	# Three ornamental turned brass reinforcing rings along the barrel jacket.
	for rz: float in [0.16, -0.18, -0.50]:
		_add_tube(st, Vector3(0.0, 0.04, rz + 0.032), Vector3(0.0, 0.04, rz - 0.032),
			0.090, 0.090, 10, COL_BRASS_HI, COL_BRASS_MID)

	# Front ring foresight post atop muzzle & rear V-notch brass sight at breech.
	_add_box(st, Vector3(0.0, 0.155, -0.66), Vector3(0.024, 0.085, 0.026), COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)
	_add_box(st, Vector3(0.0, 0.145, 0.22), Vector3(0.082, 0.052, 0.024), COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)
	# Brass breech pommel knob.
	_add_tube(st, Vector3(0.0, 0.03, 0.40), Vector3(0.0, 0.03, 0.47), 0.046, 0.024, 8, COL_BRASS_HI, COL_BRASS_LO)

	st.generate_normals()
	return st.commit()


static func _build_winch_drum_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Wound hemp hawser coils wrapped snugly around the side winch drum (local +X axis).
	for ci in 5:
		var x0 := -0.055 + float(ci) * 0.027
		var x1 := x0 + 0.024
		var r_coil := 0.076 + (0.008 if (ci % 2 == 0) else 0.0)
		_add_tube(st, Vector3(x0, 0.0, 0.0), Vector3(x1, 0.0, 0.0),
			r_coil, r_coil, 10, COL_ROPE_HI, COL_ROPE_LO)

	st.generate_normals()
	return st.commit()


static func _build_winch_crank_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Twin circular brass winch end-flanges & offset hand crank arm.
	for fx: float in [-0.068, 0.072]:
		_add_tube(st, Vector3(fx - 0.012, 0.0, 0.0), Vector3(fx + 0.012, 0.0, 0.0),
			0.102, 0.102, 10, COL_BRASS_HI, COL_BRASS_LO)
	# Crank shaft, radial arm, and grip spindle.
	_add_tube(st, Vector3(0.072, 0.0, 0.0), Vector3(0.115, 0.0, 0.0), 0.022, 0.022, 6, COL_BRASS_HI, COL_BRASS_MID)
	_add_box(st, Vector3(0.115, 0.068, 0.0), Vector3(0.022, 0.145, 0.030), COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)
	_add_tube(st, Vector3(0.115, 0.128, 0.0), Vector3(0.205, 0.128, 0.0), 0.018, 0.016, 6, COL_OAK_HI, COL_OAK_LO)

	st.generate_normals()
	return st.commit()


static func _build_spear_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Forged-iron harpoon shaft (z = +0.28 tail eye -> z = -0.68 barbed spearpoint).
	_add_tube(st, Vector3(0.0, 0.0, 0.26), Vector3(0.0, 0.0, -0.44), 0.024, 0.021, 8, COL_IRON_HI, COL_IRON_LO)
	# Brass reinforcing collar & aft rope tow-ring.
	_add_tube(st, Vector3(0.0, 0.0, 0.29), Vector3(0.0, 0.0, 0.22), 0.034, 0.030, 8, COL_BRASS_HI, COL_BRASS_LO)
	_add_tube(st, Vector3(0.0, 0.0, -0.36), Vector3(0.0, 0.0, -0.44), 0.032, 0.028, 8, COL_BRASS_HI, COL_BRASS_LO)

	# Sharp diamond-section double-edged spearhead (z = -0.42 -> tip z = -0.74).
	var tip := Vector3(0.0, 0.0, -0.74)
	var base := Vector3(0.0, 0.0, -0.42)
	var ring: Array[Vector3] = [
		Vector3(0.0, 0.042, -0.47),
		Vector3(0.064, 0.0, -0.45),
		Vector3(0.0, -0.042, -0.47),
		Vector3(-0.064, 0.0, -0.45),
	]
	var head_ref := Vector3(0.0, 0.0, -0.54)
	for i in 4:
		var i1 := (i + 1) % 4
		_emit_outward_tri(st, ring[i], ring[i1], tip, head_ref, COL_IRON_HI, COL_IRON_MID, COL_IRON_HI)
		_emit_outward_tri(st, ring[i1], ring[i], base, head_ref, COL_IRON_MID, COL_IRON_LO, COL_IRON_LO)

	# Twin vicious swept backward-hooking forged barbs flaring port & starboard!
	for sx: float in [-1.0, 1.0]:
		var b_root := Vector3(sx * 0.044, 0.0, -0.50)
		var b_tip := Vector3(sx * 0.125, 0.0, -0.29)
		var b_up := b_root + Vector3(0.0, 0.024, 0.06)
		var b_dn := b_root + Vector3(0.0, -0.024, 0.06)
		var b_in := Vector3(sx * 0.024, 0.0, -0.39)
		var b_ref := (b_root + b_tip + b_in) / 3.0
		_emit_outward_tri(st, b_root, b_up, b_tip, b_ref, COL_IRON_HI, COL_IRON_HI, COL_IRON_MID)
		_emit_outward_tri(st, b_root, b_tip, b_dn, b_ref, COL_IRON_MID, COL_IRON_LO, COL_IRON_LO)
		_emit_outward_tri(st, b_up, b_in, b_tip, b_ref, COL_IRON_HI, COL_IRON_MID, COL_IRON_MID)
		_emit_outward_tri(st, b_dn, b_tip, b_in, b_ref, COL_IRON_LO, COL_IRON_MID, COL_IRON_LO)

	st.generate_normals()
	return st.commit()


static func _build_rope_tube_mesh() -> ArrayMesh:
	# Unit braided hemp rope along +Z (0.0 -> 1.0) with subtle helical twist modulation.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGS := 6
	const RINGS := 8
	const BASE_R := 0.021
	for ri in RINGS:
		var z0 := float(ri) / float(RINGS)
		var z1 := float(ri + 1) / float(RINGS)
		var tw0 := z0 * TAU * 3.0
		var tw1 := z1 * TAU * 3.0
		var mid := Vector3(0.0, 0.0, (z0 + z1) * 0.5)
		for si in SEGS:
			var a0 := TAU * float(si) / float(SEGS)
			var a1 := TAU * float(si + 1) / float(SEGS)
			var r00 := BASE_R * (1.0 + 0.14 * sin(a0 * 3.0 + tw0))
			var r01 := BASE_R * (1.0 + 0.14 * sin(a1 * 3.0 + tw0))
			var r10 := BASE_R * (1.0 + 0.14 * sin(a0 * 3.0 + tw1))
			var r11 := BASE_R * (1.0 + 0.14 * sin(a1 * 3.0 + tw1))
			var p00 := Vector3(cos(a0) * r00, sin(a0) * r00, z0)
			var p01 := Vector3(cos(a1) * r01, sin(a1) * r01, z0)
			var p10 := Vector3(cos(a0) * r10, sin(a0) * r10, z1)
			var p11 := Vector3(cos(a1) * r11, sin(a1) * r11, z1)
			var c0 := COL_ROPE_HI if ((si + ri) % 2 == 0) else COL_ROPE_MID
			var c1 := COL_ROPE_MID if ((si + ri) % 2 == 0) else COL_ROPE_LO
			_emit_outward_quad(st, p00, p10, p11, p01, mid, c0, c1, c1, c0)

	st.generate_normals()
	return st.commit()


# ==============================================================================
# Sculpted Flat-Faceted Geometry Primitives (Outward-Wound SurfaceTool Helpers)
# ==============================================================================

static func _add_lathe(st: SurfaceTool, profile: Array[Vector2], segs: int,
		col_bot: Color, col_top: Color) -> void:
	if profile.size() < 2:
		return
	var y_mid := (profile[0].y + profile[profile.size() - 1].y) * 0.5
	var ref_c := Vector3(0.0, y_mid, 0.0)
	for pi in range(profile.size() - 1):
		var r0 := profile[pi].x
		var y0 := profile[pi].y
		var r1 := profile[pi + 1].x
		var y1 := profile[pi + 1].y
		var t0 := float(pi) / maxf(float(profile.size() - 1), 1.0)
		var t1 := float(pi + 1) / maxf(float(profile.size() - 1), 1.0)
		var c0 := col_bot.lerp(col_top, t0)
		var c1 := col_bot.lerp(col_top, t1)
		for s in segs:
			var a0 := TAU * float(s) / float(segs)
			var a1 := TAU * float(s + 1) / float(segs)
			var p00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p10 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p01 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			if r0 <= 0.0004 and r1 > 0.0004:
				_emit_outward_tri(st, p00, p01, p11, ref_c, c0, c1, c1)
			elif r1 <= 0.0004 and r0 > 0.0004:
				_emit_outward_tri(st, p00, p10, p01, ref_c, c0, c0, c1)
			elif r0 > 0.0004 and r1 > 0.0004:
				_emit_outward_quad(st, p00, p10, p11, p01, ref_c, c0, c0, c1, c1)


static func _add_tube(st: SurfaceTool, p0: Vector3, p1: Vector3, r0: float, r1: float,
		segs: int, col_hi: Color, col_lo: Color) -> void:
	var axis := p1 - p0
	if axis.length_squared() < 1e-10:
		return
	var dir := axis.normalized()
	var up_ref := Vector3.UP if absf(dir.y) < 0.92 else Vector3.RIGHT
	var u := dir.cross(up_ref).normalized()
	var v := dir.cross(u).normalized()
	var mid := (p0 + p1) * 0.5
	for s in segs:
		var a0 := TAU * float(s) / float(segs)
		var a1 := TAU * float(s + 1) / float(segs)
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		var c0 := col_lo.lerp(col_hi, clampf(0.5 + 0.5 * d0.y, 0.0, 1.0))
		var c1 := col_lo.lerp(col_hi, clampf(0.5 + 0.5 * d1.y, 0.0, 1.0))
		var v00 := p0 + d0 * r0
		var v10 := p0 + d1 * r0
		var v01 := p1 + d0 * r1
		var v11 := p1 + d1 * r1
		_emit_outward_quad(st, v00, v10, v11, v01, mid, c0, c1, c1, c0)
		_emit_outward_tri(st, p0, v00, v10, mid, col_lo, c0, c1)
		_emit_outward_tri(st, p1, v11, v01, mid, col_hi, c1, c0)


static func _add_box(st: SurfaceTool, center: Vector3, size: Vector3,
		col_top: Color, col_side: Color, col_bot: Color) -> void:
	_add_oriented_box(st, Basis.IDENTITY, center, size, col_top, col_side, col_bot)


static func _add_oriented_box(st: SurfaceTool, rot_basis: Basis, center: Vector3, size: Vector3,
		col_top: Color, col_side: Color, col_bot: Color) -> void:
	var h := size * 0.5
	var c: Array[Vector3] = [
		center + rot_basis * Vector3(-h.x, -h.y, -h.z),
		center + rot_basis * Vector3(h.x, -h.y, -h.z),
		center + rot_basis * Vector3(h.x, h.y, -h.z),
		center + rot_basis * Vector3(-h.x, h.y, -h.z),
		center + rot_basis * Vector3(-h.x, -h.y, h.z),
		center + rot_basis * Vector3(h.x, -h.y, h.z),
		center + rot_basis * Vector3(h.x, h.y, h.z),
		center + rot_basis * Vector3(-h.x, h.y, h.z),
	]
	_emit_outward_quad(st, c[3], c[2], c[6], c[7], center, col_top, col_top, col_top, col_top)
	_emit_outward_quad(st, c[4], c[5], c[1], c[0], center, col_bot, col_bot, col_bot, col_bot)
	_emit_outward_quad(st, c[0], c[1], c[2], c[3], center, col_bot, col_bot, col_side, col_side)
	_emit_outward_quad(st, c[5], c[4], c[7], c[6], center, col_bot, col_bot, col_side, col_side)
	_emit_outward_quad(st, c[4], c[0], c[3], c[7], center, col_bot, col_bot, col_side, col_side)
	_emit_outward_quad(st, c[1], c[5], c[6], c[2], center, col_bot, col_bot, col_side, col_side)


static func _emit_outward_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_emit_outward_tri(st, a, b, c, ref_center, ca, cb, cc)
	_emit_outward_tri(st, a, c, d, ref_center, ca, cc, cd)


static func _emit_outward_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
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
