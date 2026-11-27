class_name Rowboat
extends Node3D
## Sculpted clinker-built stern-docked, rowable pirate dinghy.
##
## Features 100% sculpted flat-faceted `SurfaceTool` `ArrayMesh` geometry (zero raw
## `PrimitiveMesh`es) with WeakRef-cached shared ship PBR textures (object-space
## triplanar mapping, zero extra VRAM) and ref-counted leak-free cache teardown.
##
## Mechanics (host-authoritative where `Net.is_host()`):
## - Stern davit docking (`attach_to_ship`, `launch`, `can_dock_to`, `dock_to_ship`)
##   riding broadside cleanly below `ShipNameplate` on Sloop & Brigantine hulls.
## - Authentic Sea-of-Thieves rowing via built-in `oar_station` (`&"rowboat_oars"`)
##   with articulated twin ash oars, wake foam, and rhythmic oar/splash SFX.
## - 4-point 24-wave `Sea.height()` ocean buoyancy with bounded storm pitch/roll
##   and gentle shoreline beaching.
## - Bow thwart & duckboard cargo stowage for up to 4 `Carryable` items.

signal launched(by_pawn: Node)
signal docked(by_pawn: Node)
signal cargo_changed(count: int)

enum State { DOCKED, LAUNCHED }

## Broadside stern dock points in unscaled ship-local coordinates (cleanly below ShipNameplate).
const SLOOP_DOCK_LOCAL := Vector3(0.0, 0.74, 7.90)
const BRIG_DOCK_LOCAL := Vector3(0.0, 0.84, 9.88)
const DOCK_RANGE := 8.5
const LAUNCH_ASTERN_OFFSET := 2.8

## Hull dimensions (metres, -Z bow to +Z stern, +X starboard, +Y up).
const HULL_LENGTH := 3.40
const HULL_HALF_LEN := 1.70
const HULL_HALF_BEAM := 0.72
const HULL_GUNWALE_H := 0.62

## Rowing & buoyancy tuning.
const OAR_THRUST_ACCEL := 7.4
const OAR_BACK_ACCEL := 4.4
const OAR_BRAKE_DECEL := 9.2
const WATER_LIN_DRAG := 0.62
const WATER_QUAD_DRAG := 0.13
const MAX_SPEED := 5.6
const MAX_YAW_RATE := 1.35
const MAX_TILT_RAD := 0.418879  # 24 degrees
const OAR_STROKE_RATE := 5.4

## Up to 4 Carryable items ride visibly on the bow cargo thwart & forward duckboards.
const MAX_CARGO := 4
const BOW_CARGO_SLOTS: Array[Vector3] = [
	Vector3(0.0, 0.44, -1.06),
	Vector3(-0.26, 0.16, -0.58),
	Vector3(0.26, 0.16, -0.58),
	Vector3(0.0, 0.16, -0.82),
]

const TEX_OAK_NORMAL := "res://assets/generated/textures/ship_oak_normal.png"
const TEX_OAK_ROUGH := "res://assets/generated/textures/ship_oak_rough.png"
const TEX_IRON_NORMAL := "res://assets/generated/textures/ship_iron_normal.png"
const TEX_IRON_ROUGH := "res://assets/generated/textures/ship_iron_rough.png"
const TEX_BRASS_NORMAL := "res://assets/generated/textures/ship_brass_normal.png"
const TEX_BRASS_ROUGH := "res://assets/generated/textures/ship_brass_rough.png"
const TEX_ROPE_NORMAL := "res://assets/generated/textures/ship_rope_normal.png"
const TEX_ROPE_ROUGH := "res://assets/generated/textures/ship_rope_rough.png"

# sRGB-calibrated painterly nautical palette (clinker oak, mahogany gunwale, ash oars, iron, brass, hemp).
const COL_OAK_HI := Color(0.58, 0.40, 0.22)
const COL_OAK_MID := Color(0.43, 0.28, 0.14)
const COL_OAK_LO := Color(0.25, 0.15, 0.07)
const COL_INNER_HI := Color(0.64, 0.46, 0.27)
const COL_INNER_LO := Color(0.36, 0.24, 0.13)
const COL_MAHOGANY_HI := Color(0.38, 0.17, 0.09)
const COL_MAHOGANY_MID := Color(0.26, 0.11, 0.055)
const COL_MAHOGANY_LO := Color(0.15, 0.06, 0.03)
const COL_ASH_HI := Color(0.76, 0.62, 0.40)
const COL_ASH_MID := Color(0.60, 0.47, 0.28)
const COL_ASH_LO := Color(0.42, 0.31, 0.18)
const COL_LEATHER_HI := Color(0.34, 0.17, 0.08)
const COL_LEATHER_LO := Color(0.18, 0.08, 0.04)
const COL_IRON_HI := Color(0.32, 0.34, 0.38)
const COL_IRON_MID := Color(0.18, 0.19, 0.23)
const COL_IRON_LO := Color(0.09, 0.10, 0.13)
const COL_BRASS_HI := Color(0.96, 0.79, 0.32)
const COL_BRASS_MID := Color(0.76, 0.57, 0.19)
const COL_BRASS_LO := Color(0.44, 0.31, 0.10)
const COL_ROPE_HI := Color(0.80, 0.67, 0.44)
const COL_ROPE_MID := Color(0.62, 0.50, 0.31)
const COL_ROPE_LO := Color(0.38, 0.29, 0.17)
const COL_GLASS_LIT := Color(1.0, 0.86, 0.52)
const COL_GLASS_DIM := Color(0.55, 0.48, 0.38)

# Sculpted 96-tri concentric launch splash & nocturnal bioluminescent rowing wake ring.
const SPLASH_RING_Y_LOCAL := 0.14
const SPLASH_RING_VISIBILITY_END := 180.0
const SPLASH_RING_BURST_DURATION := 0.95
const SPLASH_RING_BURST_SCALE_START := 0.65
const SPLASH_RING_BURST_SCALE_END := 2.35
const SPLASH_RING_BURST_PEAK_ENERGY := 1.25
const SPLASH_RING_WAKE_SPEED_MIN := 1.0
const SPLASH_RING_WAKE_SPEED_FULL := 4.4
const COL_SPLASH_RIM_BLACK := Color(0.0, 0.0, 0.0, 1.0)
const COL_SPLASH_CREST_WHITE := Color(0.32, 0.44, 0.48, 1.0)
const COL_SPLASH_DAY := Color(0.88, 0.96, 0.99)
const COL_SPLASH_NIGHT_BIOLUM := Color(0.20, 0.92, 0.96)

## Visual scale (dinghy stays realistic 1.0x human size regardless of mother ship hull_scale).
@export var visual_scale: float = 1.0
## Whether the stern boat lantern is currently lit.
@export var lantern_lit: bool = true

var state: State = State.DOCKED
var mother_ship: Ship = null
var linear_velocity: Vector3 = Vector3.ZERO
var angular_velocity_y: float = 0.0

var oar_station: Station = null
var dock_interactable: Interactable = null
var cargo_interactable: Interactable = null

# Visual hierarchy refs
var _visual_root: Node3D = null
var _hull_oak_mi: MeshInstance3D = null
var _trim_oak_mi: MeshInstance3D = null
var _fittings_iron_mi: MeshInstance3D = null
var _fittings_brass_mi: MeshInstance3D = null
var _lantern_glass_mi: MeshInstance3D = null
var _lantern_glass_mat: StandardMaterial3D = null
var _lantern_light: OmniLight3D = null
var _lantern_halo_mi: MeshInstance3D = null
var _lantern_halo_mat: ShaderMaterial = null
var _port_oar_pivot: Node3D = null
var _port_oar_mi: MeshInstance3D = null
var _starboard_oar_pivot: Node3D = null
var _starboard_oar_mi: MeshInstance3D = null
var _port_oar_splash: GPUParticles3D = null
var _stbd_oar_splash: GPUParticles3D = null
var _slings_mi: MeshInstance3D = null
var _splash_ring_mi: MeshInstance3D = null
var _splash_ring_mat: StandardMaterial3D = null

# Runtime buoyancy, rowing & cargo state
var _cargo: Array[Carryable] = []
var _yaw: float = 0.0
var _pitch: float = 0.0
var _roll: float = 0.0
var _vy_spring: float = 0.0
var _port_oar_phase: float = 0.0
var _stbd_oar_phase: float = 0.0
var _port_oar_effort: float = 0.0
var _stbd_oar_effort: float = 0.0
var _stroke_phase: float = 0.0
var _driven_this_tick: bool = false
var _turn_driven_this_tick: bool = false
var _oar_sfx_cooldown: float = 0.0
var _foam_accum: float = 0.0
var _lantern_clock: float = 0.0
var _last_lantern_halo_energy: float = 0.0
var _port_oar_in_water: bool = false
var _stbd_oar_in_water: bool = false
var _port_splash_timer: float = 0.0
var _stbd_splash_timer: float = 0.0
var _port_splash_cd: float = 0.0
var _stbd_splash_cd: float = 0.0
var _oar_splash_count: int = 0
var _splash_burst_timer: float = 0.0
var _splash_ring_energy: float = 0.0
var _splash_ring_biolum_blend: float = 0.0
var _splash_ring_clock: float = 0.0

var _ray_params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _ray_result: Variant = ClassDB.instantiate(&"PhysicsIntersectRayResult3D") if ClassDB.class_exists(&"PhysicsIntersectRayResult3D") else null

# Ref-counted static sculpted ArrayMesh & shared PBR material caches (zero ObjectDB leaks).
static var _active_instances: int = 0
static var _pbr_tex_cache: Dictionary = {}  # String path -> WeakRef(Texture2D)
static var _hull_oak_mesh: ArrayMesh = null
static var _trim_oak_mesh: ArrayMesh = null
static var _fittings_iron_mesh: ArrayMesh = null
static var _fittings_brass_mesh: ArrayMesh = null
static var _lantern_glass_mesh: ArrayMesh = null
static var _lantern_halo_mesh: ArrayMesh = null
static var _lantern_halo_shader: Shader = null
static var _oar_splash_mesh: ArrayMesh = null
static var _oar_splash_shader: Shader = null
static var _oar_splash_mat: ShaderMaterial = null
static var _oar_splash_proc: ParticleProcessMaterial = null
static var _oar_mesh: ArrayMesh = null
static var _slings_mesh: ArrayMesh = null
static var _splash_ring_mesh: ArrayMesh = null
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
	if _oar_splash_mat != null:
		_oar_splash_mat.shader = null
	_hull_oak_mesh = null
	_trim_oak_mesh = null
	_fittings_iron_mesh = null
	_fittings_brass_mesh = null
	_lantern_glass_mesh = null
	_lantern_halo_mesh = null
	_lantern_halo_shader = null
	_oar_splash_mesh = null
	_oar_splash_shader = null
	_oar_splash_mat = null
	_oar_splash_proc = null
	_oar_mesh = null
	_slings_mesh = null
	_splash_ring_mesh = null
	_oak_mat = null
	_iron_mat = null
	_brass_mat = null
	_rope_mat = null
	_pbr_tex_cache.clear()


func _enter_tree() -> void:
	_active_instances += 1
	add_to_group(&"rowboats")


func _ready() -> void:
	_ensure_shared_assets()
	_build_visuals()
	_build_interactions()
	_ray_params.collision_mask = 1  # World static terrain/beaches
	_ray_params.collide_with_areas = false
	_ray_params.collide_with_bodies = true
	_yaw = rotation.y
	set_lantern_lit(lantern_lit)
	_sync_state_visuals()
	if state == State.DOCKED and mother_ship != null and is_instance_valid(mother_ship):
		_sync_docked_transform()


func _exit_tree() -> void:
	if oar_station != null and is_instance_valid(oar_station) and Net.is_host():
		if oar_station.is_occupied():
			var occ := oar_station.occupant
			if occ is Pawn and is_instance_valid(occ):
				(occ as Pawn).leave_station()
			else:
				oar_station.release()
	if Net.is_host():
		for item: Carryable in _cargo:
			if item != null and is_instance_valid(item):
				if item.stored_in == self:
					item.stored_in = null
					item.visible = true
					item.freeze = false
					item.collision_layer = Carryable.LAYER
					item.collision_mask = Carryable.MASK
					if item.interactable != null and is_instance_valid(item.interactable):
						item.interactable.enabled = true
	_cargo.clear()
	mother_ship = null

	for mi: MeshInstance3D in [
		_hull_oak_mi, _trim_oak_mi, _fittings_iron_mi, _fittings_brass_mi,
		_lantern_glass_mi, _lantern_halo_mi, _port_oar_mi, _starboard_oar_mi, _slings_mi,
		_splash_ring_mi
	]:
		if mi != null and is_instance_valid(mi):
			mi.material_override = null
			mi.mesh = null
	for gp: GPUParticles3D in [_port_oar_splash, _stbd_oar_splash]:
		if gp != null and is_instance_valid(gp):
			gp.emitting = false
			gp.draw_pass_1 = null
			gp.process_material = null
			gp.material_override = null
	if _lantern_glass_mat != null:
		_lantern_glass_mat.normal_texture = null
		_lantern_glass_mat.roughness_texture = null
		_lantern_glass_mat = null
	if _lantern_halo_mat != null:
		_lantern_halo_mat.shader = null
		_lantern_halo_mat = null
	_splash_ring_mat = null
	_hull_oak_mi = null
	_trim_oak_mi = null
	_fittings_iron_mi = null
	_fittings_brass_mi = null
	_lantern_glass_mi = null
	_lantern_halo_mi = null
	_lantern_light = null
	_port_oar_pivot = null
	_port_oar_mi = null
	_starboard_oar_pivot = null
	_starboard_oar_mi = null
	_port_oar_splash = null
	_stbd_oar_splash = null
	_slings_mi = null
	_splash_ring_mi = null
	_visual_root = null
	_last_lantern_halo_energy = 0.0
	_splash_burst_timer = 0.0
	_splash_ring_energy = 0.0
	_splash_ring_biolum_blend = 0.0
	_splash_ring_clock = 0.0
	oar_station = null
	dock_interactable = null
	cargo_interactable = null
	_ray_params = null
	_ray_result = null

	_active_instances = maxi(0, _active_instances - 1)
	if _active_instances == 0:
		clear_shared_cache()


# ==============================================================================
# Public Query & State API
# ==============================================================================

func is_docked() -> bool:
	return state == State.DOCKED


func is_launched() -> bool:
	return state == State.LAUNCHED


func get_speed() -> float:
	return Vector2(linear_velocity.x, linear_velocity.z).length()


func get_cargo_count() -> int:
	_prune_cargo()
	return _cargo.size()


## Current cached stern lantern atmospheric halo intensity (0.0 when doused).
func get_lantern_halo_energy() -> float:
	return _last_lantern_halo_energy


## True when the zero-primitive additive stern LanternHalo billboard is mounted.
func has_lantern_halo() -> bool:
	return _lantern_halo_mi != null and is_instance_valid(_lantern_halo_mi) \
		and _lantern_halo_mi.mesh is ArrayMesh and not (_lantern_halo_mi.mesh is PrimitiveMesh)


## Total oar-dip sea spray & blade foam bursts triggered while rowing this dinghy.
func get_oar_splash_count() -> int:
	return _oar_splash_count


## Sculpted 96-tri concentric launch splash & nocturnal bioluminescent wake ring node.
func get_splash_ring() -> MeshInstance3D:
	if _splash_ring_mi != null and is_instance_valid(_splash_ring_mi):
		return _splash_ring_mi
	return null


## Current launch splash / active rowing wake ring additive intensity (0.0 when docked or idle).
func get_splash_ring_energy() -> float:
	return _splash_ring_energy


## Current 0..1 nocturnal bioluminescent tint blend (0.0 midday seafoam -> 1.0 night cyan).
func get_splash_ring_biolum_blend() -> float:
	return _splash_ring_biolum_blend


## Trigger the dramatic expanding seafoam launch splash ring burst & ocean foam stamp.
func trigger_launch_splash() -> void:
	if state == State.DOCKED:
		_hide_splash_ring(false)
		return
	_splash_burst_timer = SPLASH_RING_BURST_DURATION
	_splash_ring_energy = SPLASH_RING_BURST_PEAK_ENERGY
	_splash_ring_clock = 0.0
	var biolum := _compute_nocturnal_biolum_blend()
	_splash_ring_biolum_blend = biolum
	if Ocean.current != null and is_instance_valid(Ocean.current):
		Ocean.current.add_foam(global_position, 3.6, 0.90)
	var burst_tint := COL_SPLASH_DAY.lerp(COL_SPLASH_NIGHT_BIOLUM, biolum * 0.65)
	_apply_splash_ring_visual(SPLASH_RING_BURST_SCALE_START, _splash_ring_energy, burst_tint, 0.0)


## Deterministic splash burst & nocturnal bioluminescent rowing wake tick.
func step_splash_ring(delta: float) -> void:
	var dt := maxf(delta, 0.0)
	if state == State.DOCKED:
		_hide_splash_ring(false)
		return

	_splash_ring_clock += dt
	var biolum := _compute_nocturnal_biolum_blend()
	_splash_ring_biolum_blend = biolum

	if _splash_burst_timer > 0.0:
		_splash_burst_timer = maxf(0.0, _splash_burst_timer - dt)
		if _splash_burst_timer > 0.0:
			var u := 1.0 - clampf(_splash_burst_timer / SPLASH_RING_BURST_DURATION, 0.0, 1.0)
			var expand_t := 1.0 - (1.0 - u) * (1.0 - u)
			var burst_scale := lerpf(SPLASH_RING_BURST_SCALE_START, SPLASH_RING_BURST_SCALE_END, expand_t)
			var burst_energy := SPLASH_RING_BURST_PEAK_ENERGY * pow(1.0 - u, 1.45)
			var burst_tint := COL_SPLASH_DAY.lerp(COL_SPLASH_NIGHT_BIOLUM, biolum * 0.65)
			_splash_ring_energy = burst_energy
			_apply_splash_ring_visual(burst_scale, burst_energy, burst_tint, 0.0)
			return
		# Hold full expanded scale when the launch burst completes cleanly at 0.95 s.
		if _splash_ring_mi != null and is_instance_valid(_splash_ring_mi):
			_splash_ring_mi.scale = Vector3.ONE * (SPLASH_RING_BURST_SCALE_END * visual_scale)

	var spd := get_speed()
	if spd >= SPLASH_RING_WAKE_SPEED_MIN:
		var speed_t := clampf(
			(spd - SPLASH_RING_WAKE_SPEED_MIN) / (SPLASH_RING_WAKE_SPEED_FULL - SPLASH_RING_WAKE_SPEED_MIN),
			0.0, 1.0
		)
		var pulse := 0.94 + 0.06 * sin(_splash_ring_clock * 4.2)
		var night_lift := lerpf(1.0, 1.10, biolum)
		var wake_energy := clampf(lerpf(0.17, 0.47, speed_t) * pulse * night_lift, 0.15, 0.52)
		var wake_scale := clampf(lerpf(1.08, 1.30, speed_t) + 0.045 * sin(_splash_ring_clock * 3.6 + 0.7), 1.05, 1.35)
		var wake_tint := COL_SPLASH_DAY.lerp(COL_SPLASH_NIGHT_BIOLUM, biolum)
		var wake_z := lerpf(0.12, 0.34, speed_t)
		_splash_ring_energy = wake_energy
		_apply_splash_ring_visual(wake_scale, wake_energy, wake_tint, wake_z)
		return

	_hide_splash_ring(true)


func _compute_nocturnal_biolum_blend() -> float:
	var day_f := Weather.daylight() if Weather != null else 1.0
	return clampf(1.0 - day_f, 0.0, 1.0)


func _apply_splash_ring_visual(ring_scale: float, energy: float, tint: Color, local_z: float) -> void:
	if _splash_ring_mi != null and is_instance_valid(_splash_ring_mi):
		var ring_y := SPLASH_RING_Y_LOCAL
		if Sea != null and is_inside_tree():
			var sea_y := Sea.height(global_position.x, global_position.z)
			ring_y = clampf((sea_y - global_position.y) + SPLASH_RING_Y_LOCAL, 0.10, 0.42)
		_splash_ring_mi.position = Vector3(0.0, ring_y, local_z * visual_scale)
		_splash_ring_mi.scale = Vector3.ONE * (ring_scale * visual_scale)
		_splash_ring_mi.visible = energy > 0.0005
	if _splash_ring_mat != null:
		_splash_ring_mat.albedo_color = Color(
			tint.r * energy,
			tint.g * energy,
			tint.b * energy,
			1.0
		)


func _hide_splash_ring(preserve_scale: bool) -> void:
	_splash_ring_energy = 0.0
	if not preserve_scale:
		_splash_burst_timer = 0.0
		_splash_ring_biolum_blend = 0.0
	if _splash_ring_mi != null and is_instance_valid(_splash_ring_mi):
		_splash_ring_mi.visible = false
		if not preserve_scale:
			_splash_ring_mi.position = Vector3(0.0, SPLASH_RING_Y_LOCAL, 0.0)
			_splash_ring_mi.scale = Vector3.ONE * (SPLASH_RING_BURST_SCALE_START * visual_scale)
	if _splash_ring_mat != null:
		_splash_ring_mat.albedo_color = COL_SPLASH_RIM_BLACK


## Total sculpted triangle count across all MeshInstance3D nodes in this Rowboat.
func get_triangle_count() -> int:
	var tris := 0
	for mi: MeshInstance3D in [
		_hull_oak_mi, _trim_oak_mi, _fittings_iron_mi, _fittings_brass_mi,
		_lantern_glass_mi, _port_oar_mi, _starboard_oar_mi, _slings_mi
	]:
		if mi != null and is_instance_valid(mi) and mi.mesh is ArrayMesh:
			var am := mi.mesh as ArrayMesh
			for si in am.get_surface_count():
				var ilen := am.surface_get_array_index_len(si)
				if ilen > 0:
					tris += floori(float(ilen) / 3.0)
				else:
					tris += floori(float(am.surface_get_array_len(si)) / 3.0)
	return tris


## Toggle the sculpted stern brass boat lantern (glass emission, atmospheric halo & warm OmniLight3D).
func set_lantern_lit(on: bool) -> void:
	lantern_lit = on
	if _lantern_light != null and is_instance_valid(_lantern_light):
		_lantern_light.visible = on
	if _lantern_glass_mat != null:
		_lantern_glass_mat.emission_enabled = true
		_lantern_glass_mat.emission = Color(1.0, 0.72, 0.28)
		_lantern_glass_mat.emission_energy_multiplier = 2.8 if on else 0.0
		_lantern_glass_mat.albedo_color = COL_GLASS_LIT if on else COL_GLASS_DIM
	_update_lantern_halo(0.0)


func _update_lantern_halo(dt: float) -> void:
	if dt > 0.0:
		_lantern_clock += dt
	if not lantern_lit:
		_last_lantern_halo_energy = 0.0
		if _lantern_halo_mi != null and is_instance_valid(_lantern_halo_mi):
			_lantern_halo_mi.visible = false
		if _lantern_halo_mat != null:
			_lantern_halo_mat.set_shader_parameter(&"halo_intensity", 0.0)
		return

	var day_f := Weather.daylight() if Weather != null else 1.0
	var storm_f := Weather.storminess if Weather != null else 0.0
	var night := clampf(1.0 - day_f, 0.0, 1.0)
	var atmos_raw := night + storm_f * 0.35
	var base_e := lerpf(0.16, 1.10, clampf(atmos_raw, 0.0, 1.0))
	var storm_night_boost := clampf((atmos_raw - 1.0) / 0.35, 0.0, 1.0) * 0.15
	var flick := 0.95 + 0.05 * sin(_lantern_clock * 9.8) * cos(_lantern_clock * 6.3)
	var target_e := (base_e + storm_night_boost) * flick
	if dt > 0.0:
		_last_lantern_halo_energy = lerpf(_last_lantern_halo_energy, target_e, 1.0 - exp(-10.0 * dt))
	else:
		_last_lantern_halo_energy = target_e

	if _lantern_light != null and is_instance_valid(_lantern_light):
		_lantern_light.light_energy = 1.65 * flick
	if _lantern_halo_mi != null and is_instance_valid(_lantern_halo_mi):
		_lantern_halo_mi.visible = true
	if _lantern_halo_mat != null:
		_lantern_halo_mat.set_shader_parameter(&"halo_intensity", _last_lantern_halo_energy)


## Unscaled ship-local stern dock offset for `target_ship` (Sloop or Brigantine).
func get_dock_local(target_ship: Ship = null) -> Vector3:
	var sh := target_ship if target_ship != null else mother_ship
	if sh != null and is_instance_valid(sh) and sh.is_brigantine():
		return BRIG_DOCK_LOCAL
	return SLOOP_DOCK_LOCAL


## World-space broadside stern dock transform on `target_ship`.
func get_dock_world_transform(target_ship: Ship = null) -> Transform3D:
	var sh := target_ship if target_ship != null else mother_ship
	if sh == null or not is_instance_valid(sh):
		return global_transform
	var dock_local := get_dock_local(sh)
	var scaled_pt := sh.ship_point(dock_local)
	return sh.global_transform * Transform3D(Basis(Vector3.UP, PI * 0.5), scaled_pt)


## Strict-ASCII dynamic prompt for the launch/dock interactable.
func get_dock_prompt() -> String:
	if state == State.DOCKED:
		return "Launch rowboat"
	if can_dock_to():
		return "Dock rowboat"
	return "Rowboat (launch/dock)"


## Station focus prompt callback used by Station.get_focus_prompt() (strict ASCII).
func get_station_focus_prompt(st: Station) -> String:
	if st == oar_station:
		return "Row dinghy"
	return st.prompt if st != null else "Row dinghy"


## Station active control hint shown while rowing (strict ASCII).
func get_station_active_prompt(st: Station) -> String:
	if st == oar_station:
		return "[W/LMB] Row | [A/D] Steer | [S/RMB] Brake | [F] Step Off"
	return "[F] Step Off"


# ==============================================================================
# Stern Davit Docking & Launching (Host-Authoritative)
# ==============================================================================

## Attach this rowboat broadside to `ship`'s stern davits cleanly below ShipNameplate.
func attach_to_ship(ship: Ship) -> void:
	mother_ship = ship
	state = State.DOCKED
	linear_velocity = Vector3.ZERO
	angular_velocity_y = 0.0
	_pitch = 0.0
	_roll = 0.0
	_vy_spring = 0.0
	scale = Vector3.ONE
	if oar_station != null and is_instance_valid(oar_station) and Net.is_host():
		if oar_station.is_occupied():
			var occ := oar_station.occupant
			if occ is Pawn and is_instance_valid(occ):
				(occ as Pawn).leave_station()
			else:
				oar_station.release()
	if mother_ship != null and is_instance_valid(mother_ship):
		_sync_docked_transform()
		set_lantern_lit(mother_ship.lanterns_lit)
	_sync_state_visuals()
	_update_oar_visuals(0.0, true)
	_sync_stowed_cargo()


## Host only. Release rowboat from stern davits onto the ocean 2.8 m astern of `mother_ship`.
func launch(by_pawn: Node = null, seat_pawn: bool = false) -> bool:
	if not Net.is_host():
		return false
	if state != State.DOCKED:
		return false

	state = State.LAUNCHED
	linear_velocity = Vector3.ZERO
	angular_velocity_y = 0.0
	_pitch = 0.0
	_roll = 0.0
	_vy_spring = 0.0

	if mother_ship != null and is_instance_valid(mother_ship):
		var dock_world := get_dock_world_transform(mother_ship).origin
		var stern_out := mother_ship.global_basis.z
		stern_out.y = 0.0
		if stern_out.length_squared() < 1e-6:
			stern_out = Vector3.BACK
		else:
			stern_out = stern_out.normalized()
		var launch_xz := dock_world + stern_out * LAUNCH_ASTERN_OFFSET
		var sea_y := Sea.height(launch_xz.x, launch_xz.z) if Sea != null else 0.0
		_yaw = atan2(-stern_out.x, -stern_out.z)
		global_transform = Transform3D(Basis(Vector3.UP, _yaw), Vector3(launch_xz.x, sea_y, launch_xz.z))
	else:
		var sea_y := Sea.height(global_position.x, global_position.z) if Sea != null else 0.0
		_yaw = rotation.y
		global_transform = Transform3D(Basis(Vector3.UP, _yaw), Vector3(global_position.x, sea_y, global_position.z))

	_sync_state_visuals()
	_sync_stowed_cargo()

	if is_inside_tree():
		Audio.play_sfx(&"splash_large", global_position, -1.0)
		Audio.play_sfx(&"rope_creak", global_position, -2.0)
	trigger_launch_splash()

	if seat_pawn and by_pawn is Pawn and is_instance_valid(by_pawn) and oar_station != null:
		var p := by_pawn as Pawn
		if p.station != null:
			p.leave_station()
		p.teleport(oar_station.get_stand_global().origin)
		p.look_yaw = _yaw
		p.enter_station(oar_station)

	launched.emit(by_pawn)
	return true


## True when launched and horizontally within DOCK_RANGE (8.5 m) of `target_ship`'s stern dock.
func can_dock_to(target_ship: Ship = null) -> bool:
	if state != State.LAUNCHED:
		return false
	var sh := target_ship if target_ship != null else mother_ship
	if sh == null or not is_instance_valid(sh) or sh.is_sinking:
		return false
	var dock_pos := get_dock_world_transform(sh).origin
	var horiz_dist := Vector2(global_position.x - dock_pos.x, global_position.z - dock_pos.z).length()
	return horiz_dist <= DOCK_RANGE


## Host only. Hoist rowboat back onto `target_ship`'s stern davits, stepping occupant onto quarterdeck.
func dock_to_ship(target_ship: Ship = null, by_pawn: Node = null) -> bool:
	if not Net.is_host():
		return false
	var sh := target_ship if target_ship != null else mother_ship
	if not can_dock_to(sh):
		return false

	var qdeck_local := Vector3(0.0, 2.25, 6.2) if sh.is_brigantine() else Vector3(0.0, 2.02, 5.2)
	var board_local := sh.ship_point(qdeck_local)

	var occ: Node = oar_station.occupant if (oar_station != null and is_instance_valid(oar_station)) else null
	if occ != null and is_instance_valid(occ):
		if occ is Pawn:
			var occ_pawn := occ as Pawn
			occ_pawn.leave_station()
			occ_pawn.board(sh, board_local)
		elif oar_station != null:
			oar_station.release()

	if by_pawn is Pawn and is_instance_valid(by_pawn) and by_pawn != occ:
		var bp := by_pawn as Pawn
		if bp.platform != sh:
			if bp.station != null:
				bp.leave_station()
			bp.board(sh, board_local)

	linear_velocity = Vector3.ZERO
	angular_velocity_y = 0.0
	attach_to_ship(sh)

	if is_inside_tree():
		Audio.play_sfx(&"rope_creak", global_position, -1.5)
		Audio.play_sfx(&"chest_thump", global_position, -1.5)

	docked.emit(by_pawn)
	return true


# ==============================================================================
# Cargo Stowage (Up to 4 Carryables on Bow Thwart & Duckboards)
# ==============================================================================

## Container contract hook for `Carryable.hand_to(rowboat)` & `Pawn._container_of()`.
func accept_carryable(item: Carryable) -> bool:
	var ok := stow_carryable(item)
	if ok:
		# Carryable.hand_to() sets visible=false after accept_carryable(); restore visibly on bow thwart.
		call_deferred(&"_sync_stowed_cargo")
	return ok


## Host only. Stow a Carryable visibly on the bow cargo thwart / duckboards (max 4).
func stow_carryable(item: Carryable) -> bool:
	if not Net.is_host() or item == null or not is_instance_valid(item):
		return false
	_prune_cargo()
	if _cargo.size() >= MAX_CARGO or _cargo.has(item):
		return false

	var prev_holder := item.holder
	item.holder = null
	if prev_holder != null and is_instance_valid(prev_holder) and prev_holder.has_method(&"release_carried"):
		prev_holder.call(&"release_carried", item)

	item.stored_in = self
	item.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	item.freeze = true
	item.collision_layer = 0
	item.collision_mask = 0
	if item.interactable != null and is_instance_valid(item.interactable):
		item.interactable.enabled = false
	item.visible = true

	_cargo.append(item)
	_sync_stowed_cargo()
	_refresh_cargo_prompt()
	if is_inside_tree():
		Audio.play_sfx(&"chest_thump", item.global_position, -3.5)
	cargo_changed.emit(_cargo.size())
	return true


## Host only. Retrieve the top stowed Carryable (handing directly to `by_pawn` when empty-handed).
func pop_carryable(by_pawn: Node = null) -> Carryable:
	if not Net.is_host():
		return null
	_prune_cargo()
	if _cargo.is_empty():
		return null

	var slot_idx := _cargo.size() - 1
	var item: Carryable = _cargo.pop_back()
	var slot_local := BOW_CARGO_SLOTS[mini(slot_idx, BOW_CARGO_SLOTS.size() - 1)]
	var release_pos := global_transform * (slot_local + Vector3.UP * 0.25)
	item.take_out(release_pos)

	if by_pawn != null and is_instance_valid(by_pawn) and by_pawn.has_method(&"pick_up"):
		if by_pawn.get(&"carried") == null and by_pawn.get(&"station") == null:
			by_pawn.call(&"pick_up", item)

	_sync_stowed_cargo()
	_refresh_cargo_prompt()
	if is_inside_tree():
		Audio.play_sfx(&"chest_thump", release_pos, -4.5)
	cargo_changed.emit(_cargo.size())
	return item


func _prune_cargo() -> void:
	for i in range(_cargo.size() - 1, -1, -1):
		var it := _cargo[i]
		if it == null or not is_instance_valid(it) or it.stored_in != self:
			_cargo.remove_at(i)


func _sync_stowed_cargo() -> void:
	_prune_cargo()
	var base_xf := global_transform
	for i in _cargo.size():
		var item := _cargo[i]
		if item == null or not is_instance_valid(item) or not item.is_inside_tree():
			continue
		var slot := BOW_CARGO_SLOTS[mini(i, BOW_CARGO_SLOTS.size() - 1)]
		item.visible = true
		item.global_transform = Transform3D(base_xf.basis, base_xf * slot)


# ==============================================================================
# Simulation & Rowing Physics
# ==============================================================================

func _physics_process(delta: float) -> void:
	step_physics(delta)


## Deterministic physics tick (also callable directly in headless tests).
func step_physics(delta: float) -> void:
	var dt := clampf(delta, 0.0, 0.05)
	if dt <= 0.0:
		return

	if state == State.DOCKED:
		if mother_ship != null and is_instance_valid(mother_ship):
			_sync_docked_transform()
			if lantern_lit != mother_ship.lanterns_lit:
				set_lantern_lit(mother_ship.lanterns_lit)
		_update_lantern_halo(dt)
		_update_oar_visuals(dt, true)
		step_splash_ring(dt)
		_sync_stowed_cargo()
		return

	if Net.is_host():
		_step_launched_physics(dt)
	_update_lantern_halo(dt)
	_update_oar_visuals(dt, false)
	step_splash_ring(dt)
	_sync_stowed_cargo()


func _drive_oars(_st: Station, axis: Vector2, primary: bool, secondary: bool, delta: float) -> void:
	if not Net.is_host() or state != State.LAUNCHED:
		return
	var dt := clampf(delta, 0.0, 0.05)
	if dt <= 0.0:
		return

	_driven_this_tick = true
	# PlayerController convention: move_forward ([W]) -> axis.y = +1.0, move_back ([S]) -> axis.y = -1.0;
	# move_right ([D]) -> axis.x = +1.0, move_left ([A]) -> axis.x = -1.0.
	var forward_cmd := clampf(axis.y + (1.0 if primary else 0.0), -1.0, 1.0)
	var turn_cmd := clampf(axis.x, -1.0, 1.0)
	var brake := secondary

	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var horiz := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var v_fwd := horiz.dot(fwd)
	var v_lat := horiz.dot(right)

	var rowing_effort := maxf(absf(forward_cmd), absf(turn_cmd))
	if rowing_effort > 0.05:
		_stroke_phase = fposmod(_stroke_phase + OAR_STROKE_RATE * dt, TAU)

	# Rhythmic pull-stroke thrust along -global_basis.z, plus quick [S] backwater / [RMB] feather brake.
	if brake:
		v_fwd = move_toward(v_fwd, 0.0, OAR_BRAKE_DECEL * dt)
	elif forward_cmd > 0.05:
		var pulse := 0.84 + 0.24 * maxf(0.0, cos(_stroke_phase))
		v_fwd += OAR_THRUST_ACCEL * forward_cmd * pulse * dt
	elif forward_cmd < -0.05:
		if v_fwd > 0.15:
			v_fwd = move_toward(v_fwd, 0.0, OAR_BRAKE_DECEL * absf(forward_cmd) * dt)
		else:
			v_fwd = maxf(v_fwd + OAR_BACK_ACCEL * forward_cmd * dt, -2.4)

	# Crisp yaw turning: [A] (turn_cmd=-1) -> +yaw (port), [D] (turn_cmd=+1) -> -yaw (starboard).
	if absf(turn_cmd) > 0.05:
		_turn_driven_this_tick = true
		var pivot_boost := 1.15 if brake else 1.0
		var target_yaw_rate := -turn_cmd * MAX_YAW_RATE * pivot_boost
		angular_velocity_y = move_toward(angular_velocity_y, target_yaw_rate, 6.2 * dt)

	# Recompose clamped horizontal velocity.
	v_fwd = clampf(v_fwd, -2.5, MAX_SPEED)
	linear_velocity = fwd * v_fwd + right * v_lat

	# Differential port/starboard oar animation drive (port pushes harder to turn starboard, vice versa).
	_port_oar_effort = clampf(forward_cmd + turn_cmd * 0.85, -1.0, 1.0)
	_stbd_oar_effort = clampf(forward_cmd - turn_cmd * 0.85, -1.0, 1.0)
	if brake:
		_port_oar_effort *= 0.25
		_stbd_oar_effort *= 0.25
	_port_oar_phase = wrapf(_port_oar_phase + _port_oar_effort * OAR_STROKE_RATE * dt, -PI, PI)
	_stbd_oar_phase = wrapf(_stbd_oar_phase + _stbd_oar_effort * OAR_STROKE_RATE * dt, -PI, PI)

	# Cooldown-gated oar dip splash & oarlock creak SFX.
	_oar_sfx_cooldown = maxf(0.0, _oar_sfx_cooldown - dt)
	if rowing_effort > 0.12 and _oar_sfx_cooldown <= 0.0 and is_inside_tree():
		_oar_sfx_cooldown = 0.62
		Audio.play_sfx(&"splash_small", global_position, -4.5)
		Audio.play_sfx(&"rope_creak", global_position, -9.5)


func _step_launched_physics(dt: float) -> void:
	var prev_pos := global_position
	var prev_yaw := _yaw

	# Relax angular velocity when no steering input is held.
	if not _turn_driven_this_tick:
		angular_velocity_y = move_toward(angular_velocity_y, 0.0, 5.2 * dt)
	_yaw = wrapf(_yaw + angular_velocity_y * dt, -PI, PI)

	# Smooth hydrodynamic linear + quadratic drag + lateral keel resistance.
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var horiz := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var v_fwd := horiz.dot(fwd)
	var v_lat := horiz.dot(right)

	var drag_decel := (WATER_LIN_DRAG * absf(v_fwd) + WATER_QUAD_DRAG * v_fwd * v_fwd) * dt
	v_fwd = move_toward(v_fwd, 0.0, drag_decel)
	v_lat = move_toward(v_lat, 0.0, (4.8 + absf(v_lat) * 2.2) * dt)

	# Advance XZ position.
	linear_velocity = fwd * clampf(v_fwd, -2.5, MAX_SPEED) + right * v_lat
	global_position.x += linear_velocity.x * dt
	global_position.z += linear_velocity.z * dt

	# 4-point 24-wave Sea.height() ocean buoyancy: bow (-1.4), stern (+1.4), port (-0.65), starboard (+0.65).
	var yaw_basis := Basis(Vector3.UP, _yaw)
	var bow_w := global_position + yaw_basis * Vector3(0.0, 0.0, -1.4)
	var stern_w := global_position + yaw_basis * Vector3(0.0, 0.0, 1.4)
	var port_w := global_position + yaw_basis * Vector3(-0.65, 0.0, 0.0)
	var stbd_w := global_position + yaw_basis * Vector3(0.65, 0.0, 0.0)

	var h_bow := Sea.height(bow_w.x, bow_w.z) if Sea != null else 0.0
	var h_stern := Sea.height(stern_w.x, stern_w.z) if Sea != null else 0.0
	var h_port := Sea.height(port_w.x, port_w.z) if Sea != null else 0.0
	var h_stbd := Sea.height(stbd_w.x, stbd_w.z) if Sea != null else 0.0

	var target_y := (h_bow + h_stern + h_port + h_stbd) * 0.25
	var target_pitch := clampf(atan2(h_bow - h_stern, 2.8), -MAX_TILT_RAD, MAX_TILT_RAD)
	var target_roll := clampf(atan2(h_stbd - h_port, 1.3), -MAX_TILT_RAD, MAX_TILT_RAD)

	# Gentle shallow-water beach slide: keep keel above solid sand/terrain without sinking through.
	var ground_y := _sample_beach_ground_y(global_position.x, global_position.z)
	if is_finite(ground_y) and ground_y > target_y - 0.04:
		var beach_depth := clampf(ground_y - target_y + 0.04, 0.0, 0.65)
		target_y = maxf(target_y, ground_y + 0.03)
		linear_velocity *= maxf(0.0, 1.0 - (2.6 + beach_depth * 5.0) * dt)

	# Critically damped vertical spring + smooth pitch/roll wave alignment.
	var y_err := target_y - global_position.y
	_vy_spring += (y_err * 38.0 - _vy_spring * 11.0) * dt
	global_position.y += _vy_spring * dt
	var k_att := 1.0 - exp(-8.5 * dt)
	_pitch = lerpf(_pitch, target_pitch, k_att)
	_roll = lerpf(_roll, target_roll, k_att)

	global_transform.basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch) * Basis(Vector3.BACK, _roll)

	# Carry seated rowing Pawn smoothly with boat translation & yaw delta (keeps mouse-look free).
	if oar_station != null and is_instance_valid(oar_station) and oar_station.is_occupied():
		var occ := oar_station.occupant
		if occ is Pawn and is_instance_valid(occ):
			var p := occ as Pawn
			var dpos := global_position - prev_pos
			var dyaw := angle_difference(prev_yaw, _yaw)
			p.global_position += dpos
			p.look_yaw = wrapf(p.look_yaw + dyaw, -PI, PI)

	# Wake foam trail on the live ocean when moving.
	if get_speed() > 0.55 and Ocean.current != null and is_instance_valid(Ocean.current):
		_foam_accum += dt
		if _foam_accum >= 0.10:
			_foam_accum = 0.0
			Ocean.current.add_foam(global_position, 0.45)

	if not _driven_this_tick:
		_port_oar_effort = move_toward(_port_oar_effort, 0.0, dt * 3.5)
		_stbd_oar_effort = move_toward(_stbd_oar_effort, 0.0, dt * 3.5)
	_driven_this_tick = false
	_turn_driven_this_tick = false

	# Keep dock prompt live as proximity to mother ship changes.
	if dock_interactable != null and is_instance_valid(dock_interactable):
		dock_interactable.prompt = get_dock_prompt()


func _sample_beach_ground_y(wx: float, wz: float) -> float:
	if not is_inside_tree() or _ray_params == null:
		return -INF
	var world := get_world_3d()
	if world == null:
		return -INF
	var space := world.direct_space_state
	_ray_params.from = Vector3(wx, global_position.y + 1.8, wz)
	_ray_params.to = Vector3(wx, global_position.y - 1.2, wz)
	if _ray_result != null and space.has_method(&"intersect_ray_into"):
		if bool(space.call(&"intersect_ray_into", _ray_params, _ray_result)):
			var hp: Vector3 = _ray_result.get(&"position") as Vector3
			return hp.y
		return -INF
	var hit := space.intersect_ray(_ray_params)
	if not hit.is_empty():
		return (hit["position"] as Vector3).y
	return -INF


func _sync_docked_transform() -> void:
	if mother_ship == null or not is_instance_valid(mother_ship):
		return
	var xf := get_dock_world_transform(mother_ship)
	global_transform = xf
	_yaw = rotation.y


func _sync_state_visuals() -> void:
	var docked_now := state == State.DOCKED
	if _slings_mi != null and is_instance_valid(_slings_mi):
		_slings_mi.visible = docked_now
	if docked_now:
		_hide_splash_ring(false)
	if oar_station != null and is_instance_valid(oar_station) and oar_station.interactable != null:
		oar_station.interactable.enabled = (not docked_now) and (not oar_station.is_occupied())
	if dock_interactable != null and is_instance_valid(dock_interactable):
		dock_interactable.prompt = get_dock_prompt()
		# When docked broadside (+X faces mother ship transom), place handle right beside stern rail.
		dock_interactable.position = Vector3(0.55, 0.82, 0.0) if docked_now else Vector3(0.0, 0.58, 1.28)
	_refresh_cargo_prompt()


func _refresh_cargo_prompt() -> void:
	if cargo_interactable == null or not is_instance_valid(cargo_interactable):
		return
	var cnt := get_cargo_count()
	if cnt > 0:
		cargo_interactable.prompt = "Stow/take rowboat cargo (%d/%d)" % [cnt, MAX_CARGO]
	else:
		cargo_interactable.prompt = "Stow/take rowboat cargo"


func _update_oar_visuals(dt: float, stowed: bool) -> void:
	if _port_oar_pivot == null or _starboard_oar_pivot == null:
		return
	if not is_instance_valid(_port_oar_pivot) or not is_instance_valid(_starboard_oar_pivot):
		return

	var k := 1.0 - exp(-12.0 * dt)
	if stowed:
		# Neatly shipped aft parallel along the gunwales while hoisted on stern davits.
		var p_tgt := Vector3(0.0, 1.48, -0.04)
		var s_tgt := Vector3(0.0, -1.48, 0.04)
		if dt <= 0.0:
			_port_oar_pivot.rotation = p_tgt
			_starboard_oar_pivot.rotation = s_tgt
		else:
			_port_oar_pivot.rotation = _port_oar_pivot.rotation.lerp(p_tgt, k)
			_starboard_oar_pivot.rotation = _starboard_oar_pivot.rotation.lerp(s_tgt, k)
		_update_oar_splashes(dt, true)
		return

	var p_act := clampf(absf(_port_oar_effort), 0.0, 1.0)
	var s_act := clampf(absf(_stbd_oar_effort), 0.0, 1.0)

	# Smooth pull -> lift -> feather recovery kinematics around each oarlock pivot.
	var p_sweep := sin(_port_oar_phase) * 0.56 * p_act
	var p_dip := lerpf(0.18, 0.26 + cos(_port_oar_phase) * 0.22, p_act)
	var p_feather := -maxf(0.0, -cos(_port_oar_phase)) * 1.05 * p_act

	var s_sweep := -sin(_stbd_oar_phase) * 0.56 * s_act
	var s_dip := lerpf(-0.18, -0.26 - cos(_stbd_oar_phase) * 0.22, s_act)
	var s_feather := maxf(0.0, -cos(_stbd_oar_phase)) * 1.05 * s_act

	_port_oar_pivot.rotation = _port_oar_pivot.rotation.lerp(Vector3(p_feather, p_sweep, p_dip), k)
	_starboard_oar_pivot.rotation = _starboard_oar_pivot.rotation.lerp(Vector3(s_feather, s_sweep, s_dip), k)
	_update_oar_splashes(dt, false)


func _update_oar_splashes(dt: float, stowed: bool) -> void:
	if stowed or state != State.LAUNCHED:
		_port_oar_in_water = false
		_stbd_oar_in_water = false
		_port_splash_timer = 0.0
		_stbd_splash_timer = 0.0
		_port_splash_cd = 0.0
		_stbd_splash_cd = 0.0
		if _port_oar_splash != null and is_instance_valid(_port_oar_splash):
			_port_oar_splash.emitting = false
		if _stbd_oar_splash != null and is_instance_valid(_stbd_oar_splash):
			_stbd_oar_splash.emitting = false
		return

	if dt > 0.0:
		_port_splash_cd = maxf(0.0, _port_splash_cd - dt)
		_stbd_splash_cd = maxf(0.0, _stbd_splash_cd - dt)
		_port_splash_timer = maxf(0.0, _port_splash_timer - dt)
		_stbd_splash_timer = maxf(0.0, _stbd_splash_timer - dt)

	var port_active := absf(_port_oar_effort) > 0.25
	var port_in := port_active and cos(_port_oar_phase) >= 0.25
	if port_in and not _port_oar_in_water and _port_splash_cd <= 0.0:
		_trigger_oar_splash(true)
	_port_oar_in_water = port_in

	var stbd_active := absf(_stbd_oar_effort) > 0.25
	var stbd_in := stbd_active and cos(_stbd_oar_phase) >= 0.25
	if stbd_in and not _stbd_oar_in_water and _stbd_splash_cd <= 0.0:
		_trigger_oar_splash(false)
	_stbd_oar_in_water = stbd_in

	if _port_oar_splash != null and is_instance_valid(_port_oar_splash):
		_port_oar_splash.emitting = _port_splash_timer > 0.0
	if _stbd_oar_splash != null and is_instance_valid(_stbd_oar_splash):
		_stbd_oar_splash.emitting = _stbd_splash_timer > 0.0


func _trigger_oar_splash(is_port: bool) -> void:
	var blade_w := _compute_oar_blade_world_pos(is_port)
	var sea_y := Sea.height(blade_w.x, blade_w.z) if Sea != null else global_position.y
	blade_w.y = sea_y + 0.04

	if Ocean.current != null and is_instance_valid(Ocean.current):
		Ocean.current.add_foam(blade_w, 0.95, 0.42)

	var gp: GPUParticles3D = _port_oar_splash if is_port else _stbd_oar_splash
	if gp != null and is_instance_valid(gp):
		if is_inside_tree():
			gp.global_position = blade_w
		else:
			gp.position = Vector3(-1.95 if is_port else 1.95, 0.04, 0.05)
		gp.emitting = true

	if is_port:
		_port_splash_timer = 0.22
		_port_splash_cd = 0.28
	else:
		_stbd_splash_timer = 0.22
		_stbd_splash_cd = 0.28
	_oar_splash_count += 1


func _compute_oar_blade_world_pos(is_port: bool) -> Vector3:
	var mi: MeshInstance3D = _port_oar_mi if is_port else _starboard_oar_mi
	if mi != null and is_instance_valid(mi) and mi.is_inside_tree():
		return mi.to_global(Vector3(1.50, 0.0, 0.0))
	return global_transform * Vector3((-1.95 if is_port else 1.95) * visual_scale, 0.04, 0.05 * visual_scale)


# ==============================================================================
# Interactables & Station Wiring
# ==============================================================================

func _build_interactions() -> void:
	oar_station = Station.new()
	oar_station.name = "Station_RowboatOars"
	oar_station.configure(
		self,
		&"rowboat_oars",
		"Row dinghy",
		Transform3D(Basis.IDENTITY, Vector3(0.0, 0.24, 0.12)),
		Vector3(0.0, 0.65, 0.0),
		0.72,
		&"",
		3.0
	)
	oar_station.drive_callback = _drive_oars
	add_child(oar_station)

	dock_interactable = Interactable.create(get_dock_prompt(), 0.62)
	dock_interactable.name = "DockInteractable"
	dock_interactable.reach = 3.2
	dock_interactable.target = self
	dock_interactable.position = Vector3(0.55, 0.82, 0.0)
	dock_interactable.interacted.connect(_on_dock_interacted)
	add_child(dock_interactable)

	cargo_interactable = Interactable.create("Stow/take rowboat cargo", 0.55)
	cargo_interactable.name = "CargoInteractable"
	cargo_interactable.reach = 2.8
	cargo_interactable.target = self
	cargo_interactable.position = Vector3(0.0, 0.48, -1.02)
	cargo_interactable.interacted.connect(_on_cargo_interacted)
	add_child(cargo_interactable)


func _on_dock_interacted(pawn: Node) -> void:
	if not Net.is_host():
		return
	if state == State.DOCKED:
		launch(pawn, false)
	elif can_dock_to():
		dock_to_ship(mother_ship, pawn)


func _on_cargo_interacted(pawn: Node) -> void:
	if not Net.is_host():
		return
	if pawn != null and is_instance_valid(pawn):
		var carried_v: Variant = pawn.get(&"carried")
		if carried_v is Carryable:
			stow_carryable(carried_v as Carryable)
			return
	pop_carryable(pawn)


# ==============================================================================
# Visual Scene Construction & Shared WeakRef PBR Asset Builders (0 Primitives)
# ==============================================================================

func _build_visuals() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "RowboatVisualRoot"
	_visual_root.scale = Vector3.ONE * visual_scale
	add_child(_visual_root)

	_hull_oak_mi = MeshInstance3D.new()
	_hull_oak_mi.name = "RowboatHullOak"
	_hull_oak_mi.mesh = _hull_oak_mesh
	_hull_oak_mi.material_override = _oak_mat
	_visual_root.add_child(_hull_oak_mi)

	_trim_oak_mi = MeshInstance3D.new()
	_trim_oak_mi.name = "RowboatTrimOak"
	_trim_oak_mi.mesh = _trim_oak_mesh
	_trim_oak_mi.material_override = _oak_mat
	_visual_root.add_child(_trim_oak_mi)

	_fittings_iron_mi = MeshInstance3D.new()
	_fittings_iron_mi.name = "RowboatFittingsIron"
	_fittings_iron_mi.mesh = _fittings_iron_mesh
	_fittings_iron_mi.material_override = _iron_mat
	_visual_root.add_child(_fittings_iron_mi)

	_fittings_brass_mi = MeshInstance3D.new()
	_fittings_brass_mi.name = "RowboatFittingsBrass"
	_fittings_brass_mi.mesh = _fittings_brass_mesh
	_fittings_brass_mi.material_override = _brass_mat
	_visual_root.add_child(_fittings_brass_mi)

	_lantern_glass_mat = StandardMaterial3D.new()
	_lantern_glass_mat.vertex_color_use_as_albedo = true
	_lantern_glass_mat.vertex_color_is_srgb = true
	_lantern_glass_mat.roughness = 0.22
	_lantern_glass_mat.metallic = 0.05
	_lantern_glass_mat.uv1_triplanar = true
	_lantern_glass_mat.uv1_world_triplanar = false
	_lantern_glass_mat.emission_enabled = true
	_lantern_glass_mat.emission = Color(1.0, 0.72, 0.28)
	_lantern_glass_mat.emission_energy_multiplier = 2.8 if lantern_lit else 0.0

	_lantern_glass_mi = MeshInstance3D.new()
	_lantern_glass_mi.name = "SternLanternGlass"
	_lantern_glass_mi.mesh = _lantern_glass_mesh
	_lantern_glass_mi.material_override = _lantern_glass_mat
	_lantern_glass_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual_root.add_child(_lantern_glass_mi)

	_lantern_light = OmniLight3D.new()
	_lantern_light.name = "SternLanternLight"
	_lantern_light.position = Vector3(0.0, 0.80, 1.72)
	_lantern_light.light_color = Color(1.0, 0.78, 0.42)
	_lantern_light.light_energy = 1.65
	_lantern_light.omni_range = 10.0
	_lantern_light.omni_attenuation = 1.35
	_lantern_light.shadow_enabled = false
	_lantern_light.visible = lantern_lit
	_visual_root.add_child(_lantern_light)

	_lantern_halo_mat = ShaderMaterial.new()
	_lantern_halo_mat.shader = _lantern_halo_shader
	_lantern_halo_mat.set_shader_parameter(&"halo_intensity", 0.0)
	_lantern_halo_mat.set_shader_parameter(&"halo_scale", 0.72 * visual_scale)
	_lantern_halo_mat.set_shader_parameter(&"halo_color", Color(1.0, 0.74, 0.30))
	_lantern_halo_mat.set_shader_parameter(&"halo_phase", float(get_instance_id() % 97) * 0.29)

	_lantern_halo_mi = MeshInstance3D.new()
	_lantern_halo_mi.name = "LanternHalo"
	_lantern_halo_mi.position = Vector3(0.0, 0.80, 1.72)
	_lantern_halo_mi.mesh = _lantern_halo_mesh
	_lantern_halo_mi.material_override = _lantern_halo_mat
	_lantern_halo_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lantern_halo_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_lantern_halo_mi.extra_cull_margin = 1.0 * visual_scale
	_lantern_halo_mi.visible = lantern_lit
	_visual_root.add_child(_lantern_halo_mi)

	_port_oar_pivot = Node3D.new()
	_port_oar_pivot.name = "PortOarPivot"
	_port_oar_pivot.position = Vector3(-0.72, 0.64, 0.05)
	_visual_root.add_child(_port_oar_pivot)

	_port_oar_mi = MeshInstance3D.new()
	_port_oar_mi.name = "PortOarMesh"
	_port_oar_mi.mesh = _oar_mesh
	_port_oar_mi.material_override = _oak_mat
	# Pure +PI Y rotation mirrors the +X oar mesh cleanly outboard to -X without negative scaling.
	_port_oar_mi.rotation.y = PI
	_port_oar_pivot.add_child(_port_oar_mi)

	_starboard_oar_pivot = Node3D.new()
	_starboard_oar_pivot.name = "StarboardOarPivot"
	_starboard_oar_pivot.position = Vector3(0.72, 0.64, 0.05)
	_visual_root.add_child(_starboard_oar_pivot)

	_starboard_oar_mi = MeshInstance3D.new()
	_starboard_oar_mi.name = "StarboardOarMesh"
	_starboard_oar_mi.mesh = _oar_mesh
	_starboard_oar_mi.material_override = _oak_mat
	_starboard_oar_pivot.add_child(_starboard_oar_mi)

	_port_oar_splash = _make_oar_splash_emitter("PortOarSplash", Vector3(-1.95, 0.04, 0.05))
	_visual_root.add_child(_port_oar_splash)
	_stbd_oar_splash = _make_oar_splash_emitter("StbdOarSplash", Vector3(1.95, 0.04, 0.05))
	_visual_root.add_child(_stbd_oar_splash)

	_slings_mi = MeshInstance3D.new()
	_slings_mi.name = "DavitHoistSlings"
	_slings_mi.mesh = _slings_mesh
	_slings_mi.material_override = _rope_mat
	_slings_mi.visible = (state == State.DOCKED)
	_visual_root.add_child(_slings_mi)

	# Sculpted 96-tri concentric launch splash & nocturnal bioluminescent rowing wake ring
	# mounted directly on Rowboat (outside _visual_root, excluded from hull triangle counts).
	_splash_ring_mat = StandardMaterial3D.new()
	_splash_ring_mat.vertex_color_use_as_albedo = true
	_splash_ring_mat.vertex_color_is_srgb = true
	_splash_ring_mat.uv1_triplanar = true
	_splash_ring_mat.uv1_world_triplanar = false
	_splash_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_splash_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_splash_ring_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_splash_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_splash_ring_mat.render_priority = 2
	_splash_ring_mat.albedo_color = COL_SPLASH_RIM_BLACK

	_splash_ring_mi = MeshInstance3D.new()
	_splash_ring_mi.name = "RowboatSplashRing"
	_splash_ring_mi.position = Vector3(0.0, SPLASH_RING_Y_LOCAL, 0.0)
	_splash_ring_mi.scale = Vector3.ONE * (SPLASH_RING_BURST_SCALE_START * visual_scale)
	_splash_ring_mi.mesh = _splash_ring_mesh
	_splash_ring_mi.material_override = _splash_ring_mat
	_splash_ring_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_splash_ring_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_splash_ring_mi.visibility_range_end = SPLASH_RING_VISIBILITY_END
	_splash_ring_mi.extra_cull_margin = 3.5 * visual_scale
	_splash_ring_mi.visible = false
	add_child(_splash_ring_mi)


static func _make_oar_splash_emitter(node_name: String, local_pos: Vector3) -> GPUParticles3D:
	var gp := GPUParticles3D.new()
	gp.name = node_name
	gp.position = local_pos
	gp.amount = 14
	gp.lifetime = 0.48
	gp.one_shot = false
	gp.explosiveness = 0.65
	gp.randomness = 0.35
	gp.local_coords = false
	gp.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gp.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	gp.visibility_aabb = AABB(Vector3(-2.0, -0.8, -2.0), Vector3(4.0, 2.8, 4.0))
	gp.process_material = _oar_splash_proc
	gp.draw_pass_1 = _oar_splash_mesh
	gp.material_override = _oar_splash_mat
	gp.emitting = false
	return gp


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
	# Object-space triplanar mapping prevents texture swimming as the dinghy pitches, rolls, and turns.
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
		_oak_mat = _make_pbr_mat(0.76, 0.04, TEX_OAK_NORMAL, TEX_OAK_ROUGH, Vector3(1.6, 1.6, 1.6), 0.72)
	if _iron_mat == null:
		_iron_mat = _make_pbr_mat(0.44, 0.78, TEX_IRON_NORMAL, TEX_IRON_ROUGH, Vector3(2.4, 2.4, 2.4), 0.80)
	if _brass_mat == null:
		_brass_mat = _make_pbr_mat(0.28, 0.86, TEX_BRASS_NORMAL, TEX_BRASS_ROUGH, Vector3(2.6, 2.6, 2.6), 0.55)
	if _rope_mat == null:
		_rope_mat = _make_pbr_mat(0.90, 0.02, TEX_ROPE_NORMAL, TEX_ROPE_ROUGH, Vector3(3.2, 3.2, 3.2), 0.92)

	if _hull_oak_mesh == null:
		_hull_oak_mesh = _build_hull_oak_mesh()
	if _trim_oak_mesh == null:
		_trim_oak_mesh = _build_trim_oak_mesh()
	if _fittings_iron_mesh == null:
		_fittings_iron_mesh = _build_fittings_iron_mesh()
	if _fittings_brass_mesh == null:
		_fittings_brass_mesh = _build_fittings_brass_mesh()
	if _lantern_glass_mesh == null:
		_lantern_glass_mesh = _build_lantern_glass_mesh()
	if _lantern_halo_mesh == null:
		_lantern_halo_mesh = _build_lantern_halo_quad()
	if _lantern_halo_shader == null:
		_lantern_halo_shader = _build_lantern_halo_shader()
	if _oar_splash_mesh == null:
		_oar_splash_mesh = _build_oar_splash_card_mesh()
	if _oar_splash_shader == null:
		_oar_splash_shader = _build_oar_splash_shader()
	if _oar_splash_mat == null:
		_oar_splash_mat = ShaderMaterial.new()
		_oar_splash_mat.shader = _oar_splash_shader
	if _oar_splash_proc == null:
		var proc := ParticleProcessMaterial.new()
		proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		proc.emission_sphere_radius = 0.14
		proc.direction = Vector3(0.0, 1.0, 0.25)
		proc.spread = 42.0
		proc.initial_velocity_min = 1.4
		proc.initial_velocity_max = 2.9
		proc.gravity = Vector3(0.0, -7.8, 0.0)
		proc.damping_min = 0.4
		proc.damping_max = 0.9
		proc.scale_min = 0.65
		proc.scale_max = 1.30
		_oar_splash_proc = proc
	if _oar_mesh == null:
		_oar_mesh = _build_oar_mesh()
	if _slings_mesh == null:
		_slings_mesh = _build_slings_mesh()
	if _splash_ring_mesh == null:
		_splash_ring_mesh = _build_splash_ring_mesh()


static func _build_splash_ring_mesh() -> ArrayMesh:
	# Exact 96-tri concentric horizontal elliptical splash & wake ring
	# (24 radial segments x 2 tapered annular ribbons, finite +Y normals, pure black zero-rim edges).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGS := 24
	const RX_IN := 0.92
	const RX_MID := 1.08
	const RX_OUT := 1.28
	const RZ_IN := 1.60
	const RZ_MID := 1.80
	const RZ_OUT := 2.04
	const UP_NORMAL := Vector3(0.0, 1.0, 0.0)
	for i in SEGS:
		var u0 := float(i) / float(SEGS)
		var u1 := float(i + 1) / float(SEGS)
		var a0 := TAU * u0
		var a1 := TAU * u1
		var w0 := 1.0 + 0.035 * sin(a0 * 6.0) + 0.020 * cos(a0 * 4.0)
		var w1 := 1.0 + 0.035 * sin(a1 * 6.0) + 0.020 * cos(a1 * 4.0)
		var c0 := cos(a0)
		var s0 := sin(a0)
		var c1 := cos(a1)
		var s1 := sin(a1)

		var in0 := Vector3(c0 * RX_IN * w0, 0.0, s0 * RZ_IN * w0)
		var in1 := Vector3(c1 * RX_IN * w1, 0.0, s1 * RZ_IN * w1)
		var m0 := Vector3(c0 * RX_MID * w0, 0.0, s0 * RZ_MID * w0)
		var m1 := Vector3(c1 * RX_MID * w1, 0.0, s1 * RZ_MID * w1)
		var o0 := Vector3(c0 * RX_OUT * w0, 0.0, s0 * RZ_OUT * w0)
		var o1 := Vector3(c1 * RX_OUT * w1, 0.0, s1 * RZ_OUT * w1)

		# Inner annular half-ribbon (pure zero-rim black -> bright crest ridge, 2 tris/seg).
		st.set_normal(UP_NORMAL)
		st.set_uv(Vector2(u0, 0.0))
		st.set_color(COL_SPLASH_RIM_BLACK)
		st.add_vertex(in0)
		st.set_normal(UP_NORMAL)
		st.set_uv(Vector2(u0, 0.5))
		st.set_color(COL_SPLASH_CREST_WHITE)
		st.add_vertex(m0)
		st.set_normal(UP_NORMAL)
		st.set_uv(Vector2(u1, 0.5))
		st.set_color(COL_SPLASH_CREST_WHITE)
		st.add_vertex(m1)

		st.set_normal(UP_NORMAL)
		st.set_uv(Vector2(u0, 0.0))
		st.set_color(COL_SPLASH_RIM_BLACK)
		st.add_vertex(in0)
		st.set_normal(UP_NORMAL)
		st.set_uv(Vector2(u1, 0.5))
		st.set_color(COL_SPLASH_CREST_WHITE)
		st.add_vertex(m1)
		st.set_normal(UP_NORMAL)
		st.set_uv(Vector2(u1, 0.0))
		st.set_color(COL_SPLASH_RIM_BLACK)
		st.add_vertex(in1)

		# Outer annular half-ribbon (bright crest ridge -> pure zero-rim black, 2 tris/seg).
		st.set_normal(UP_NORMAL)
		st.set_uv(Vector2(u0, 0.5))
		st.set_color(COL_SPLASH_CREST_WHITE)
		st.add_vertex(m0)
		st.set_normal(UP_NORMAL)
		st.set_uv(Vector2(u0, 1.0))
		st.set_color(COL_SPLASH_RIM_BLACK)
		st.add_vertex(o0)
		st.set_normal(UP_NORMAL)
		st.set_uv(Vector2(u1, 1.0))
		st.set_color(COL_SPLASH_RIM_BLACK)
		st.add_vertex(o1)

		st.set_normal(UP_NORMAL)
		st.set_uv(Vector2(u0, 0.5))
		st.set_color(COL_SPLASH_CREST_WHITE)
		st.add_vertex(m0)
		st.set_normal(UP_NORMAL)
		st.set_uv(Vector2(u1, 1.0))
		st.set_color(COL_SPLASH_RIM_BLACK)
		st.add_vertex(o1)
		st.set_normal(UP_NORMAL)
		st.set_uv(Vector2(u1, 0.5))
		st.set_color(COL_SPLASH_CREST_WHITE)
		st.add_vertex(m1)

	return st.commit()


static func _build_lantern_halo_quad() -> ArrayMesh:
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


static func _build_lantern_halo_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float halo_intensity = 0.0;
uniform float halo_scale = 0.72;
uniform vec3 halo_color : source_color = vec3(1.0, 0.74, 0.30);
uniform float halo_phase = 0.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(INV_VIEW_MATRIX[0].xyz * halo_scale, 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz * halo_scale, 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz * halo_scale, 0.0),
		MODEL_MATRIX[3]
	);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float edge_mask = smoothstep(1.0, 0.72, r);
	float shimmer = 0.94 + 0.06 * sin(TIME * 6.8 + halo_phase) * cos(TIME * 4.3 - halo_phase * 0.7);
	float core = exp(-r * r * 14.5) * 0.76;
	float bloom = exp(-r * r * 3.8) * 0.42;
	float glow = (core + bloom) * edge_mask * shimmer;
	vec3 col = mix(halo_color, vec3(1.0, 0.96, 0.84), clamp(core * 1.15, 0.0, 1.0));
	ALBEDO = col * (glow * halo_intensity);
}
"""
	return sh


static func _build_oar_splash_card_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 0.068
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


static func _build_oar_splash_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;

varying float v_age;
varying float v_seed;

void vertex() {
	v_age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_seed = INSTANCE_CUSTOM.x;
	float sc = mix(0.60, 1.35, sin(v_age * 3.14159265) * 0.70 + v_age * 0.30);
	VERTEX *= sc;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float drop = smoothstep(1.0, 0.22, r);
	float core = smoothstep(0.65, 0.0, r);
	float fade_in = smoothstep(0.0, 0.14, v_age);
	float fade_out = pow(1.0 - v_age, 1.45);
	float alpha = clamp((drop * 0.72 + core * 0.28) * fade_in * fade_out * 0.78, 0.0, 1.0);
	vec3 foam_col = mix(vec3(0.76, 0.92, 0.96), vec3(0.96, 0.99, 1.0), core);
	ALBEDO = foam_col;
	ALPHA = alpha;
}
"""
	return sh


# ==============================================================================
# Parametric Clinker Dinghy Hull Profile & Sculpted Geometry Builders
# ==============================================================================

static func _plan_width_factor(u: float) -> float:
	# u = 0.0 (pointed bow stem at z = -1.70) .. 1.0 (wineglass stern transom at z = +1.70).
	if u < 0.52:
		var bt := clampf(u / 0.52, 0.0, 1.0)
		return maxf(0.045, pow(sin(bt * PI * 0.5), 0.74))
	var at := clampf((u - 0.52) / 0.48, 0.0, 1.0)
	return lerpf(1.0, 0.66, at * at)


static func _sheer_height(u: float) -> float:
	# Classic boat sheer curve: 0.62 m midship, +0.10 m bow rise, +0.05 m stern rise.
	var bow_rise := pow(maxf(0.0, 1.0 - u * 2.0), 2.1) * 0.10
	var stern_rise := pow(maxf(0.0, (u - 0.5) * 2.0), 2.0) * 0.05
	return HULL_GUNWALE_H + bow_rise + stern_rise


static func _keel_rocker(u: float) -> float:
	# Subtle bottom rocker rising toward stem & transom skeg.
	var bow_rock := pow(maxf(0.0, 1.0 - u * 2.2), 2.2) * 0.14
	var stern_rock := pow(maxf(0.0, (u - 0.65) / 0.35), 2.0) * 0.06
	return 0.02 + bow_rock + stern_rock


static func _hull_station_point(u: float, strake_idx: int, side_sign: float, inner: bool, clinker_lip: float = 0.0) -> Vector3:
	# 6 profile rings (5 clinker strakes from garboard keel to flared sheer strake).
	const X_FRACS: Array[float] = [0.06, 0.44, 0.70, 0.85, 0.94, 1.00]
	const Y_FRACS: Array[float] = [0.00, 0.09, 0.24, 0.46, 0.73, 1.00]
	var si := clampi(strake_idx, 0, 5)
	var z := lerpf(-HULL_HALF_LEN, HULL_HALF_LEN, u)
	var pw := _plan_width_factor(u)
	var half_x := HULL_HALF_BEAM * pw * X_FRACS[si] + clinker_lip
	var y_bot := _keel_rocker(u)
	var y_top := _sheer_height(u)
	var y := lerpf(y_bot, y_top, Y_FRACS[si])
	if inner:
		var wall := 0.045
		half_x = maxf(0.015, half_x - wall * (0.45 + 0.55 * X_FRACS[si]))
		y += wall * (1.0 - Y_FRACS[si]) * 0.85
		z = clampf(z, -HULL_HALF_LEN + 0.06, HULL_HALF_LEN - 0.045)
	return Vector3(side_sign * half_x, y, z)


static func _build_hull_oak_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	const N_LONG := 14
	const N_STRAKES := 5

	# 1. Flared clinker-built outer hull planking with overlapping lapstrake ledges & inner hull skin.
	for side_sign: float in [-1.0, 1.0]:
		for s in N_STRAKES:
			var t_s := float(s) / float(N_STRAKES)
			var col_lo := COL_OAK_LO.lerp(COL_OAK_MID, t_s)
			var col_hi := COL_OAK_MID.lerp(COL_OAK_HI, t_s * 0.85 + 0.15)
			var col_ledge := COL_OAK_LO.darkened(0.22)
			var in_lo := COL_INNER_LO.lerp(COL_INNER_HI, t_s * 0.8)
			var in_hi := COL_INNER_LO.lerp(COL_INNER_HI, t_s * 0.8 + 0.2)
			var lip := 0.015 if s > 0 else 0.0

			for li in N_LONG:
				var u0 := float(li) / float(N_LONG)
				var u1 := float(li + 1) / float(N_LONG)

				# Outer clinker plank strake (bottom edge flares outward slightly over strake below).
				var p00 := _hull_station_point(u0, s, side_sign, false, lip)
				var p10 := _hull_station_point(u1, s, side_sign, false, lip)
				var p01 := _hull_station_point(u0, s + 1, side_sign, false, 0.0)
				var p11 := _hull_station_point(u1, s + 1, side_sign, false, 0.0)
				var out_n := Vector3(side_sign, -0.35 if s < 2 else -0.10, 0.0)
				_emit_dir_quad(st, p00, p10, p11, p01, out_n, col_lo, col_lo, col_hi, col_hi)

				# Crisp downward-facing clinker lapstrake step ledge catching ocean specular & sun shadow.
				if s > 0:
					var b00 := _hull_station_point(u0, s, side_sign, false, 0.0)
					var b10 := _hull_station_point(u1, s, side_sign, false, 0.0)
					_emit_dir_quad(st, b00, b10, p10, p00, Vector3(0.0, -1.0, 0.0),
						col_ledge, col_ledge, col_lo, col_lo)

				# Inner seasoned-oak hull lining facing cleanly inward toward the cockpit.
				var i00 := _hull_station_point(u0, s, side_sign, true, 0.0)
				var i10 := _hull_station_point(u1, s, side_sign, true, 0.0)
				var i01 := _hull_station_point(u0, s + 1, side_sign, true, 0.0)
				var i11 := _hull_station_point(u1, s + 1, side_sign, true, 0.0)
				var in_n := Vector3(-side_sign, 0.38 if s < 2 else 0.14, 0.0)
				_emit_dir_quad(st, i00, i10, i11, i01, in_n, in_lo, in_lo, in_hi, in_hi)

		# Hull sheer top lip joining outer & inner planking beneath the gunwale cap rail.
		for li in N_LONG:
			var u0 := float(li) / float(N_LONG)
			var u1 := float(li + 1) / float(N_LONG)
			var o0 := _hull_station_point(u0, N_STRAKES, side_sign, false, 0.0)
			var o1 := _hull_station_point(u1, N_STRAKES, side_sign, false, 0.0)
			var i0 := _hull_station_point(u0, N_STRAKES, side_sign, true, 0.0)
			var i1 := _hull_station_point(u1, N_STRAKES, side_sign, true, 0.0)
			_emit_dir_quad(st, o0, o1, i1, i0, Vector3.UP, COL_OAK_MID, COL_OAK_MID, COL_INNER_HI, COL_INNER_HI)

	# 2. Bottom keel garboard closure (outer underside & inner bilge floor seam).
	for li in N_LONG:
		var u0 := float(li) / float(N_LONG)
		var u1 := float(li + 1) / float(N_LONG)
		var ol0 := _hull_station_point(u0, 0, -1.0, false, 0.0)
		var or0 := _hull_station_point(u0, 0, 1.0, false, 0.0)
		var ol1 := _hull_station_point(u1, 0, -1.0, false, 0.0)
		var or1 := _hull_station_point(u1, 0, 1.0, false, 0.0)
		_emit_dir_quad(st, ol0, ol1, or1, or0, Vector3.DOWN, COL_OAK_LO, COL_OAK_LO, COL_OAK_LO, COL_OAK_LO)

		var il0 := _hull_station_point(u0, 0, -1.0, true, 0.0)
		var ir0 := _hull_station_point(u0, 0, 1.0, true, 0.0)
		var il1 := _hull_station_point(u1, 0, -1.0, true, 0.0)
		var ir1 := _hull_station_point(u1, 0, 1.0, true, 0.0)
		_emit_dir_quad(st, il0, ir0, ir1, il1, Vector3.UP, COL_INNER_LO, COL_INNER_LO, COL_INNER_LO, COL_INNER_LO)

	# 3. Squared wineglass stern transom (outer aft planks, inner face, and top cap).
	for s in N_STRAKES:
		var t_s := float(s) / float(N_STRAKES)
		var col_b := COL_OAK_LO.lerp(COL_OAK_MID, t_s)
		var col_t := COL_OAK_MID.lerp(COL_OAK_HI, t_s * 0.8 + 0.2)
		var ol0 := _hull_station_point(1.0, s, -1.0, false, 0.0)
		var or0 := _hull_station_point(1.0, s, 1.0, false, 0.0)
		var ol1 := _hull_station_point(1.0, s + 1, -1.0, false, 0.0)
		var or1 := _hull_station_point(1.0, s + 1, 1.0, false, 0.0)
		_emit_dir_quad(st, ol0, or0, or1, ol1, Vector3.BACK, col_b, col_b, col_t, col_t)

		var il0 := _hull_station_point(1.0, s, -1.0, true, 0.0)
		var ir0 := _hull_station_point(1.0, s, 1.0, true, 0.0)
		var il1 := _hull_station_point(1.0, s + 1, -1.0, true, 0.0)
		var ir1 := _hull_station_point(1.0, s + 1, 1.0, true, 0.0)
		_emit_dir_quad(st, il0, ir0, ir1, il1, Vector3.FORWARD, COL_INNER_LO, COL_INNER_LO, COL_INNER_HI, COL_INNER_HI)

	# 4. External oak keel bar, stern skeg, and sweeping curved bow stem post.
	for li in N_LONG:
		var u0 := float(li) / float(N_LONG)
		var u1 := float(li + 1) / float(N_LONG)
		var z0 := lerpf(-HULL_HALF_LEN + 0.04, HULL_HALF_LEN - 0.02, u0)
		var z1 := lerpf(-HULL_HALF_LEN + 0.04, HULL_HALF_LEN - 0.02, u1)
		var y0 := _keel_rocker(u0) - 0.03
		var y1 := _keel_rocker(u1) - 0.03
		var seg_c := Vector3(0.0, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
		var seg_dir := Vector3(0.0, y1 - y0, z1 - z0)
		var seg_len := seg_dir.length()
		if seg_len > 0.01:
			var f := seg_dir / seg_len
			var u_up := Vector3.RIGHT.cross(f).normalized()
			var rot := Basis(Vector3.RIGHT, u_up, f)
			_add_oriented_box(st, rot, seg_c, Vector3(0.075, 0.085, seg_len + 0.012),
				COL_OAK_MID, COL_OAK_LO, COL_OAK_LO)

	# Sweeping curved oak bow stem post rising from keel forefoot up past the bow sheer.
	var stem_pts: Array[Vector3] = [
		Vector3(0.0, 0.14, -1.62),
		Vector3(0.0, 0.28, -1.69),
		Vector3(0.0, 0.45, -1.73),
		Vector3(0.0, 0.62, -1.75),
		Vector3(0.0, 0.77, -1.73),
	]
	for k in range(stem_pts.size() - 1):
		_add_beam(st, stem_pts[k], stem_pts[k + 1], 0.082, 0.095, COL_OAK_HI, COL_OAK_MID, COL_OAK_LO)

	# Carved oak stern transom knee bracing keel & stern transom centrally.
	_add_box(st, Vector3(0.0, 0.36, 1.56), Vector3(0.09, 0.52, 0.16), COL_OAK_HI, COL_OAK_MID, COL_OAK_LO)
	_add_beam(st, Vector3(0.0, 0.14, 1.32), Vector3(0.0, 0.54, 1.62), 0.085, 0.095,
		COL_OAK_HI, COL_OAK_MID, COL_OAK_LO)

	# 5. Seven steam-bent curved interior oak hull frame ribs.
	for ri in 7:
		var u_r := lerpf(0.16, 0.86, float(ri) / 6.0)
		for side_sign: float in [-1.0, 1.0]:
			for s in N_STRAKES:
				var p0 := _hull_station_point(u_r, s, side_sign, true, 0.0) + Vector3(-side_sign * 0.014, 0.012, 0.0)
				var p1 := _hull_station_point(u_r, s + 1, side_sign, true, 0.0) + Vector3(-side_sign * 0.014, 0.012, 0.0)
				_add_beam(st, p0, p1, 0.036, 0.038, COL_OAK_HI, COL_OAK_MID, COL_OAK_LO)

	st.generate_normals()
	return st.commit()


static func _build_trim_oak_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	const N_LONG := 14

	# 1. Dark mahogany continuous gunwale cap rail wrapping port & starboard sheer lines.
	for side_sign: float in [-1.0, 1.0]:
		for li in N_LONG:
			var u0 := float(li) / float(N_LONG)
			var u1 := float(li + 1) / float(N_LONG)
			var p0 := _hull_station_point(u0, 5, side_sign, false, 0.0) + Vector3(-side_sign * 0.015, 0.022, 0.0)
			var p1 := _hull_station_point(u1, 5, side_sign, false, 0.0) + Vector3(-side_sign * 0.015, 0.022, 0.0)
			_add_beam(st, p0, p1, 0.088, 0.056, COL_MAHOGANY_HI, COL_MAHOGANY_MID, COL_MAHOGANY_LO)
			# Outer mahogany rubbing strake fender molding right beneath the sheer rail.
			var r0 := _hull_station_point(u0, 5, side_sign, false, 0.024) + Vector3(0.0, -0.028, 0.0)
			var r1 := _hull_station_point(u1, 5, side_sign, false, 0.024) + Vector3(0.0, -0.028, 0.0)
			_add_beam(st, r0, r1, 0.036, 0.036, COL_MAHOGANY_HI, COL_MAHOGANY_MID, COL_MAHOGANY_LO)

	# Mahogany stern transom cap rail & carved triangular bow breasthook decklet.
	var tr_l := _hull_station_point(1.0, 5, -1.0, false, 0.0) + Vector3(0.0, 0.022, -0.015)
	var tr_r := _hull_station_point(1.0, 5, 1.0, false, 0.0) + Vector3(0.0, 0.022, -0.015)
	_add_beam(st, tr_l, tr_r, 0.092, 0.060, COL_MAHOGANY_HI, COL_MAHOGANY_MID, COL_MAHOGANY_LO)

	# Carved bow breasthook wedge locking port & starboard gunwales at the stem.
	_add_box(st, Vector3(0.0, 0.66, -1.52), Vector3(0.36, 0.052, 0.28),
		COL_MAHOGANY_HI, COL_MAHOGANY_MID, COL_MAHOGANY_LO)

	# 2. Inner floor slatted oak duckboards + transverse bilge support battens.
	for bi in 4:
		var bz := lerpf(-0.92, 0.92, float(bi) / 3.0)
		var u_b := (bz + HULL_HALF_LEN) / HULL_LENGTH
		var bw := HULL_HALF_BEAM * _plan_width_factor(u_b) * 0.96
		_add_box(st, Vector3(0.0, 0.105, bz), Vector3(bw, 0.032, 0.065),
			COL_OAK_MID, COL_OAK_LO, COL_OAK_LO)

	for di in 7:
		var dx := lerpf(-0.34, 0.34, float(di) / 6.0)
		var d_len := 2.02 - absf(dx) * 1.45
		var c_top := COL_ASH_HI if (di % 2 == 0) else COL_ASH_MID
		_add_box(st, Vector3(dx, 0.132, 0.0), Vector3(0.088, 0.026, d_len),
			c_top, COL_ASH_LO, COL_OAK_LO)

	# Rower's angled wooden footrest stretcher bar across the forward floor.
	_add_box(st, Vector3(0.0, 0.185, -0.34), Vector3(0.84, 0.058, 0.065),
		COL_MAHOGANY_HI, COL_MAHOGANY_MID, COL_MAHOGANY_LO)

	# 3. Three sculpted thwart benches (bow cargo thwart, midship rower's thwart, stern bench).
	# Bow cargo thwart bench (z = -1.06, y = 0.40) + front locker coaming lip + side hanging knees.
	_add_box(st, Vector3(0.0, 0.40, -1.06), Vector3(0.90, 0.048, 0.48),
		COL_OAK_HI, COL_OAK_MID, COL_OAK_LO)
	_add_box(st, Vector3(0.0, 0.27, -0.85), Vector3(0.76, 0.24, 0.036),
		COL_OAK_MID, COL_OAK_LO, COL_OAK_LO)
	for sx: float in [-1.0, 1.0]:
		_add_box(st, Vector3(sx * 0.42, 0.46, -1.06), Vector3(0.065, 0.14, 0.12),
			COL_MAHOGANY_HI, COL_MAHOGANY_MID, COL_MAHOGANY_LO)

	# Midship rower's thwart bench (z = +0.08, y = 0.36) built from twin planks + center stanchion + knees.
	for pz: float in [-0.085, 0.085]:
		_add_box(st, Vector3(0.0, 0.36, 0.08 + pz), Vector3(1.26, 0.048, 0.152),
			COL_OAK_HI, COL_OAK_MID, COL_OAK_LO)
	_add_box(st, Vector3(0.0, 0.23, 0.08), Vector3(0.085, 0.22, 0.11),
		COL_OAK_MID, COL_OAK_LO, COL_OAK_LO)
	for sx: float in [-1.0, 1.0]:
		_add_box(st, Vector3(sx * 0.60, 0.43, 0.08), Vector3(0.070, 0.16, 0.13),
			COL_MAHOGANY_HI, COL_MAHOGANY_MID, COL_MAHOGANY_LO)

	# Stern bench (z = +1.26, y = 0.41) + twin stern knees.
	_add_box(st, Vector3(0.0, 0.41, 1.26), Vector3(0.96, 0.048, 0.44),
		COL_OAK_HI, COL_OAK_MID, COL_OAK_LO)
	for sx: float in [-1.0, 1.0]:
		_add_box(st, Vector3(sx * 0.45, 0.47, 1.26), Vector3(0.068, 0.14, 0.12),
			COL_MAHOGANY_HI, COL_MAHOGANY_MID, COL_MAHOGANY_LO)

	st.generate_normals()
	return st.commit()


static func _build_fittings_iron_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Twin forged-iron oarlock gunwale reinforcement plates & vertical socket collars at (x=+-0.72, y=0.62, z=0.05).
	for sx: float in [-1.0, 1.0]:
		_add_box(st, Vector3(sx * 0.72, 0.62, 0.05), Vector3(0.095, 0.032, 0.22),
			COL_IRON_HI, COL_IRON_MID, COL_IRON_LO)
		_add_tube(st, Vector3(sx * 0.72, 0.56, 0.05), Vector3(sx * 0.72, 0.66, 0.05),
			0.028, 0.030, 8, COL_IRON_HI, COL_IRON_LO)
		# Iron thwart knee reinforcing straps.
		_add_box(st, Vector3(sx * 0.58, 0.39, 0.08), Vector3(0.09, 0.024, 0.05),
			COL_IRON_HI, COL_IRON_MID, COL_IRON_LO)

	# 2. Bow stem forged-iron nose-band & bow/stern davit hoist ringbolt plates.
	_add_beam(st, Vector3(0.0, 0.36, -1.74), Vector3(0.0, 0.75, -1.76), 0.038, 0.045,
		COL_IRON_HI, COL_IRON_MID, COL_IRON_LO)
	for rz: float in [-1.38, 1.38]:
		var ry := 0.52 if rz < 0.0 else 0.50
		_add_box(st, Vector3(0.0, ry, rz), Vector3(0.11, 0.032, 0.11),
			COL_IRON_HI, COL_IRON_MID, COL_IRON_LO)
		# Heavy iron lifting eyebolt ring (6-segment loop).
		_add_ring(st, Vector3(0.0, ry + 0.065, rz), Vector3.FORWARD, 0.048, 0.013, 8, COL_IRON_HI, COL_IRON_LO)

	# 3. Forged-iron curved stern gooseneck lantern stanchion supporting the stern boat lantern.
	var goose: Array[Vector3] = [
		Vector3(0.0, 0.66, 1.66),
		Vector3(0.0, 0.84, 1.66),
		Vector3(0.0, 0.99, 1.67),
		Vector3(0.0, 1.03, 1.72),
		Vector3(0.0, 0.97, 1.72),
	]
	for gi in range(goose.size() - 1):
		_add_tube(st, goose[gi], goose[gi + 1], 0.018, 0.016, 6, COL_IRON_HI, COL_IRON_LO)
	_add_box(st, Vector3(0.0, 0.66, 1.66), Vector3(0.12, 0.038, 0.09),
		COL_IRON_HI, COL_IRON_MID, COL_IRON_LO)

	st.generate_normals()
	return st.commit()


static func _build_fittings_brass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Twin turned-brass U-crutch oarlock horns at port & starboard midship gunwales (x=+-0.72, y=0.62, z=0.05).
	for sx: float in [-1.0, 1.0]:
		var base := Vector3(sx * 0.72, 0.64, 0.05)
		_add_tube(st, base + Vector3(0.0, -0.02, 0.0), base + Vector3(0.0, 0.04, 0.0),
			0.020, 0.022, 8, COL_BRASS_HI, COL_BRASS_LO)
		# Forward & aft curved crutch horns cradling the oar collar.
		for sz: float in [-1.0, 1.0]:
			_add_tube(st, base + Vector3(0.0, 0.035, 0.0), base + Vector3(0.0, 0.065, sz * 0.048),
				0.015, 0.014, 6, COL_BRASS_HI, COL_BRASS_MID)
			_add_tube(st, base + Vector3(0.0, 0.065, sz * 0.048), base + Vector3(0.0, 0.132, sz * 0.052),
				0.014, 0.011, 6, COL_BRASS_HI, COL_BRASS_LO)

	# 2. Sculpted stern brass boat lantern housing hanging at (0.0, 0.80, 1.72).
	var lc := Vector3(0.0, 0.80, 1.72)
	# Turned octagonal oil fount base & lower collar.
	_add_lathe_at(st, lc, [
		Vector2(0.0, -0.14),
		Vector2(0.075, -0.14),
		Vector2(0.095, -0.11),
		Vector2(0.088, -0.075),
		Vector2(0.068, -0.065),
		Vector2(0.0, -0.065),
	], 8, COL_BRASS_LO, COL_BRASS_HI)
	# Tiered domed brass vent hood & chimney crown above the glass.
	_add_lathe_at(st, lc, [
		Vector2(0.0, 0.065),
		Vector2(0.092, 0.065),
		Vector2(0.082, 0.095),
		Vector2(0.054, 0.122),
		Vector2(0.042, 0.145),
		Vector2(0.050, 0.155),
		Vector2(0.0, 0.162),
	], 8, COL_BRASS_MID, COL_BRASS_HI)
	# Four vertical brass protective corner cage bars framing the glass core.
	for ci in 4:
		var ang := float(ci) * PI * 0.5 + PI * 0.25
		var off := Vector3(cos(ang) * 0.074, 0.0, sin(ang) * 0.074)
		_add_tube(st, lc + off + Vector3(0.0, -0.075, 0.0), lc + off + Vector3(0.0, 0.075, 0.0),
			0.009, 0.009, 6, COL_BRASS_HI, COL_BRASS_LO)
	# Top brass suspension bail ring hooking onto the iron gooseneck.
	_add_ring(st, lc + Vector3(0.0, 0.165, 0.0), Vector3.RIGHT, 0.024, 0.006, 6, COL_BRASS_HI, COL_BRASS_LO)

	# 3. Four horned brass mooring cleats along bow & stern mahogany gunwales.
	for sx: float in [-1.0, 1.0]:
		for cz: float in [-1.05, 1.15]:
			var u_c := (cz + HULL_HALF_LEN) / HULL_LENGTH
			var gx := sx * (HULL_HALF_BEAM * _plan_width_factor(u_c) - 0.02)
			var gy := _sheer_height(u_c) + 0.052
			_add_box(st, Vector3(gx, gy, cz), Vector3(0.032, 0.026, 0.055),
				COL_BRASS_MID, COL_BRASS_LO, COL_BRASS_LO)
			_add_tube(st, Vector3(gx, gy + 0.022, cz - 0.075), Vector3(gx, gy + 0.022, cz + 0.075),
				0.011, 0.011, 6, COL_BRASS_HI, COL_BRASS_MID)

	st.generate_normals()
	return st.commit()


static func _build_lantern_glass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Faceted hexagonal lantern glass chimney core at (0.0, 0.80, 1.72).
	var lc := Vector3(0.0, 0.80, 1.72)
	_add_lathe_at(st, lc, [
		Vector2(0.0, -0.068),
		Vector2(0.056, -0.068),
		Vector2(0.066, -0.025),
		Vector2(0.066, 0.030),
		Vector2(0.054, 0.068),
		Vector2(0.0, 0.068),
	], 6, COL_GLASS_LIT.darkened(0.08), COL_GLASS_LIT)

	st.generate_normals()
	return st.commit()


static func _build_oar_mesh() -> ArrayMesh:
	# Articulated sculpted ash oar along +X (x=0.0 sits squarely inside the oarlock crutch).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Turned grip handle (inboard, x = -0.46..-0.30).
	_add_tube(st, Vector3(-0.46, 0.0, 0.0), Vector3(-0.30, 0.0, 0.0), 0.017, 0.020, 8, COL_ASH_HI, COL_ASH_MID)
	# Tapered inboard ash loom (x = -0.30..-0.07).
	_add_tube(st, Vector3(-0.30, 0.0, 0.0), Vector3(-0.07, 0.0, 0.0), 0.021, 0.027, 8, COL_ASH_HI, COL_ASH_LO)

	# Ribbed stitched-leather oarlock sleeve & thrust collar button (x = -0.07..+0.09).
	_add_tube(st, Vector3(-0.07, 0.0, 0.0), Vector3(0.09, 0.0, 0.0), 0.031, 0.031, 8, COL_LEATHER_HI, COL_LEATHER_LO)
	_add_tube(st, Vector3(-0.055, 0.0, 0.0), Vector3(-0.025, 0.0, 0.0), 0.042, 0.042, 8, COL_LEATHER_HI, COL_LEATHER_LO)

	# Tapered outboard ash shaft (x = +0.09..+1.16).
	_add_tube(st, Vector3(0.09, 0.0, 0.0), Vector3(1.16, 0.0, 0.0), 0.027, 0.021, 8, COL_ASH_HI, COL_ASH_LO)

	# Sculpted flat-beveled paddle blade (x = +1.16..+1.74, vertical paddle face in X-Y plane).
	# Blade profile stations: [x, half_height_y, half_thickness_z]
	var blade: Array[Array] = [
		[1.14, 0.024, 0.020],
		[1.24, 0.054, 0.016],
		[1.42, 0.076, 0.013],
		[1.62, 0.078, 0.011],
		[1.74, 0.062, 0.008],
	]
	for bi in range(blade.size() - 1):
		var x0: float = blade[bi][0]
		var h0: float = blade[bi][1]
		var t0: float = blade[bi][2]
		var x1: float = blade[bi + 1][0]
		var h1: float = blade[bi + 1][1]
		var t1: float = blade[bi + 1][2]
		# 6-vertex diamond-beveled cross-section with raised central spine rib!
		var ring0: Array[Vector3] = [
			Vector3(x0, h0, 0.0),
			Vector3(x0, h0 * 0.45, t0),
			Vector3(x0, -h0 * 0.45, t0),
			Vector3(x0, -h0, 0.0),
			Vector3(x0, -h0 * 0.45, -t0),
			Vector3(x0, h0 * 0.45, -t0),
		]
		var ring1: Array[Vector3] = [
			Vector3(x1, h1, 0.0),
			Vector3(x1, h1 * 0.45, t1),
			Vector3(x1, -h1 * 0.45, t1),
			Vector3(x1, -h1, 0.0),
			Vector3(x1, -h1 * 0.45, -t1),
			Vector3(x1, h1 * 0.45, -t1),
		]
		var seg_mid := Vector3((x0 + x1) * 0.5, 0.0, 0.0)
		var c0 := COL_ASH_HI if bi < 3 else COL_MAHOGANY_HI
		var c1 := COL_ASH_MID if bi < 3 else COL_MAHOGANY_MID
		for k in 6:
			var k1 := (k + 1) % 6
			_emit_outward_quad(st, ring0[k], ring1[k], ring1[k1], ring0[k1], seg_mid, c0, c1, c1, c0)

	# Closed flat tip bevel at blade end (x = 1.74).
	var tip_c := Vector3(1.755, 0.0, 0.0)
	var end_r: Array[Vector3] = [
		Vector3(1.74, 0.062, 0.0),
		Vector3(1.74, 0.028, 0.008),
		Vector3(1.74, -0.028, 0.008),
		Vector3(1.74, -0.062, 0.0),
		Vector3(1.74, -0.028, -0.008),
		Vector3(1.74, 0.028, -0.008),
	]
	for k in 6:
		var k1 := (k + 1) % 6
		_emit_dir_tri(st, end_r[k], end_r[k1], tip_c, Vector3.RIGHT, COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_HI)

	st.generate_normals()
	return st.commit()


static func _build_slings_mesh() -> ArrayMesh:
	# Twin braided hemp davit hoist slings visible ONLY while docked to mother_ship.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for end_z: float in [-1.34, 1.34]:
		var anchor_y := 0.58 if end_z < 0.0 else 0.56
		var apex := Vector3(0.16, 1.06, end_z * 0.92)
		# Local +X points forward into the mother ship's stern transom rail when broadside-docked!
		var davit_top := Vector3(1.02, 1.46, end_z * 0.76)
		var u_e := (end_z + HULL_HALF_LEN) / HULL_LENGTH
		var gun_x := HULL_HALF_BEAM * _plan_width_factor(u_e) * 0.72
		var gun_y := _sheer_height(u_e)

		# Center hoist bridle leg from lifting ringbolt to tackle apex.
		_add_braided_rope(st, Vector3(0.0, anchor_y, end_z), apex, 0.022, 6, 4)
		# Port & starboard steadying V-bridle straps from gunwale cleats up to apex.
		for sx: float in [-1.0, 1.0]:
			_add_braided_rope(st, Vector3(sx * gun_x, gun_y, end_z * 0.90), apex, 0.017, 6, 3)
		# Upper double-fall tackle rope sweeping forward into the ship's stern rail davits.
		_add_braided_rope(st, apex + Vector3(0.0, 0.0, -0.022), davit_top + Vector3(0.0, 0.0, -0.022), 0.019, 6, 3)
		_add_braided_rope(st, apex + Vector3(0.0, 0.0, 0.022), davit_top + Vector3(0.0, 0.0, 0.022), 0.019, 6, 3)
		# Braided tackle splice knot collar at apex.
		_add_ring(st, apex, Vector3.UP, 0.044, 0.018, 8, COL_ROPE_HI, COL_ROPE_LO)

	st.generate_normals()
	return st.commit()


# ==============================================================================
# Sculpted Flat-Faceted SurfaceTool Primitives (100% Outward-Wound)
# ==============================================================================

static func _add_braided_rope(st: SurfaceTool, p0: Vector3, p1: Vector3, radius: float,
		segs: int, rings: int) -> void:
	var axis := p1 - p0
	if axis.length_squared() < 1e-8:
		return
	var dir := axis.normalized()
	var up_ref := Vector3.UP if absf(dir.y) < 0.92 else Vector3.RIGHT
	var u := dir.cross(up_ref).normalized()
	var v := dir.cross(u).normalized()
	for ri in rings:
		var t0 := float(ri) / float(rings)
		var t1 := float(ri + 1) / float(rings)
		var c_p0 := p0.lerp(p1, t0)
		var c_p1 := p0.lerp(p1, t1)
		var mid := (c_p0 + c_p1) * 0.5
		var tw0 := t0 * TAU * 2.5
		var tw1 := t1 * TAU * 2.5
		for si in segs:
			var a0 := TAU * float(si) / float(segs)
			var a1 := TAU * float(si + 1) / float(segs)
			var r00 := radius * (1.0 + 0.14 * sin(a0 * 3.0 + tw0))
			var r01 := radius * (1.0 + 0.14 * sin(a1 * 3.0 + tw0))
			var r10 := radius * (1.0 + 0.14 * sin(a0 * 3.0 + tw1))
			var r11 := radius * (1.0 + 0.14 * sin(a1 * 3.0 + tw1))
			var d0 := u * cos(a0) + v * sin(a0)
			var d1 := u * cos(a1) + v * sin(a1)
			var v00 := c_p0 + d0 * r00
			var v01 := c_p0 + d1 * r01
			var v10 := c_p1 + d0 * r10
			var v11 := c_p1 + d1 * r11
			var col0 := COL_ROPE_HI if ((si + ri) % 2 == 0) else COL_ROPE_MID
			var col1 := COL_ROPE_MID if ((si + ri) % 2 == 0) else COL_ROPE_LO
			_emit_outward_quad(st, v00, v10, v11, v01, mid, col0, col1, col1, col0)


static func _add_ring(st: SurfaceTool, center: Vector3, normal_axis: Vector3, major_r: float,
		minor_r: float, segs: int, col_hi: Color, col_lo: Color) -> void:
	var n := normal_axis.normalized()
	var ref := Vector3.UP if absf(n.y) < 0.92 else Vector3.RIGHT
	var u := n.cross(ref).normalized()
	var v := n.cross(u).normalized()
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var q0 := center + (u * cos(a0) + v * sin(a0)) * major_r
		var q1 := center + (u * cos(a1) + v * sin(a1)) * major_r
		_add_tube(st, q0, q1, minor_r, minor_r, 5, col_hi, col_lo)


static func _add_beam(st: SurfaceTool, p0: Vector3, p1: Vector3, width: float, height: float,
		col_top: Color, col_side: Color, col_bot: Color) -> void:
	var seg := p1 - p0
	var slen := seg.length()
	if slen < 1e-5:
		return
	var f := seg / slen
	var ref_up := Vector3.UP if absf(f.y) < 0.92 else Vector3.BACK
	var r := ref_up.cross(f).normalized()
	var u := f.cross(r).normalized()
	_add_oriented_box(st, Basis(r, u, f), (p0 + p1) * 0.5, Vector3(width, height, slen + 0.012),
		col_top, col_side, col_bot)


static func _add_lathe_at(st: SurfaceTool, origin: Vector3, profile: Array[Vector2], segs: int,
		col_bot: Color, col_top: Color) -> void:
	if profile.size() < 2:
		return
	var y_mid := (profile[0].y + profile[profile.size() - 1].y) * 0.5
	var ref_c := origin + Vector3(0.0, y_mid, 0.0)
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
			var p00 := origin + Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p10 := origin + Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p01 := origin + Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := origin + Vector3(cos(a1) * r1, y1, sin(a1) * r1)
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
	var centroid := (a + b + c) / 3.0
	_emit_dir_tri(st, a, b, c, centroid - ref_center, ca, cb, cc)


static func _emit_dir_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		expected_normal: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_emit_dir_tri(st, a, b, c, expected_normal, ca, cb, cc)
	_emit_dir_tri(st, a, c, d, expected_normal, ca, cc, cd)


static func _emit_dir_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		expected_normal: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	if n.dot(expected_normal) < 0.0:
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
