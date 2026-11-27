class_name Leviathan
extends Node3D
## World-event sea monster: an abyssal multi-tentacle Leviathan that encircles a ship
## in deep water, boils the sea with an ink-black bioluminescent vortex and white foam,
## raises a central abyssal crown with glowing amber-aqua eyes, telegraphs coiled hull
## slams with pulsing cyan bio-veins, and drops Sunken Archive salvage when defeated.

signal tentacle_defeated(index: int, remaining: int)
signal leviathan_defeated(pos: Vector3, salvage: Array)

const TENTACLE_COUNT := 4
const TENTACLE_HP := 95.0
const SLAM_INTERVAL := 7.5
const SEGMENT_COUNT := 7
const BASE_RADIUS := 0.95
const TIP_RADIUS := 0.14
const SLAM_WINDUP_TIME := 2.2
const EMERGE_DURATION := 0.85
const RETREAT_DURATION := 2.0
const INK_POOL_RADIUS := 19.5
const MAX_ACTIVE_BURSTS := 16

const FOAM_TEX: Texture2D = preload("res://assets/generated/ocean/foam.png")

# Palette constants matching Sea of Scoundrels stylized painterly direction.
const COL_HIDE_DORSAL_BASE := Color(0.042, 0.088, 0.155)
const COL_HIDE_DORSAL_TIP := Color(0.068, 0.165, 0.235)
const COL_HIDE_FLANK := Color(0.085, 0.215, 0.285)
const COL_HIDE_VENTRAL := Color(0.225, 0.175, 0.295)
const COL_FIN_ROOT := Color(0.040, 0.085, 0.145)
const COL_FIN_EDGE := Color(0.145, 0.455, 0.515)
const COL_SUCKER_STALK := Color(0.60, 0.37, 0.48)
const COL_SUCKER_RIM := Color(0.88, 0.60, 0.68)
const COL_SUCKER_LIP := Color(0.95, 0.74, 0.79)
const COL_SUCKER_CUP := Color(0.32, 0.14, 0.25)
const COL_BEAK_DARK := Color(0.075, 0.065, 0.105)
const COL_BEAK_EDGE := Color(0.19, 0.16, 0.24)
const COL_VEIN_IDLE := Color(0.10, 0.86, 0.90)
const COL_VEIN_TELEGRAPH := Color(0.46, 1.0, 0.96)
const COL_VEIN_HIT := Color(1.0, 0.44, 0.64)
const COL_EYE_AMBER := Color(1.0, 0.72, 0.14)
const COL_EYE_AQUA := Color(0.16, 0.96, 0.88)

# Q17A AbyssalEyeHalos & swirling VortexBiolumMotes constants (sRGB).
const COL_EYE_HALO_CORE := Color(1.0, 0.92, 0.56, 1.0)
const COL_EYE_HALO_MID := Color(0.26, 0.54, 0.48, 1.0)
const COL_EYE_HALO_RIM := Color(0.0, 0.0, 0.0, 1.0)
const COL_MOTE_CORE := Color(0.84, 1.00, 0.98, 1.0)
const COL_MOTE_EDGE := Color(0.10, 0.92, 0.94, 1.0)

const EYE_HALO_VISIBILITY_END := 300.0
const VORTEX_MOTE_COUNT := 24
const VORTEX_MOTE_MIN_R := 5.5
const VORTEX_MOTE_MAX_R := 17.5
const VORTEX_MOTE_MIN_Y := 0.25
const VORTEX_MOTE_MAX_Y := 5.4
const VORTEX_MOTE_VISIBILITY_END := 260.0

const VEIN_IDLE_ENERGY_BASE := 1.45

# Wave-conformal swirling abyssal ink pool with bioluminescent filaments and ship-hold cutout.
const INK_POOL_SHADER_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, unshaded;

#include "res://src/ocean/waves.gdshaderinc"
#include "res://src/sky/cloud_shadow.gdshaderinc"

global uniform vec3 sun_dir;
global uniform vec3 sun_color;
global uniform vec3 sky_horizon_color;
global uniform vec3 ambient_color;

uniform sampler2D foam_tex : repeat_enable, filter_linear_mipmap;
uniform float pool_radius = 19.5;
uniform float pool_alpha = 1.0;
uniform float rage_pulse = 0.0;
uniform float swirl_clock = 0.0;
uniform vec3 ship_pos = vec3(0.0);
uniform vec2 ship_fwd = vec2(0.0, -1.0);
uniform vec2 ship_half_extents = vec2(2.15, 6.4);
uniform float ship_cutout_on = 0.0;

varying vec2 v_local_xz;
varying vec2 v_world_xz;

float ink_cloud_light(vec2 xz) {
	float cl = cloud_light(xz);
	if (cloud_shadow_params.w >= 0.999 && cl < 0.05) {
		return 1.0;
	}
	return clamp(cl, 0.25, 4.0);
}

void vertex() {
	v_local_xz = VERTEX.xz;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_xz = wp.xz;
	float sy = sea_height(wp.xz);
	VERTEX.y += (sy - wp.y) + 0.12;
}

void fragment() {
	vec2 p_norm = v_local_xz / max(pool_radius, 0.1);
	float r = length(p_norm);
	if (r > 1.0) {
		discard;
	}
	float hull_mask = 1.0;
	if (ship_cutout_on > 0.5) {
		vec2 rel = v_world_xz - ship_pos.xz;
		vec2 fwd = normalize(ship_fwd);
		vec2 right = vec2(-fwd.y, fwd.x);
		float lx = dot(rel, right) / max(ship_half_extents.x, 0.5);
		float lz = dot(rel, fwd) / max(ship_half_extents.y, 0.5);
		float taper = mix(0.94, 0.52, clamp(abs(lz), 0.0, 1.0) * clamp(abs(lz), 0.0, 1.0));
		float d_hull = length(vec2(lx / max(taper, 0.35), lz));
		hull_mask = smoothstep(0.84, 1.04, d_hull);
		if (hull_mask < 0.01) {
			discard;
		}
	}

	// Seamless spiral-rotated UV coordinates (zero atan branch-cut seam or pole artifact).
	float rot1 = (1.0 - r) * 2.85 - swirl_clock * 0.42;
	float c1 = cos(rot1);
	float s1 = sin(rot1);
	vec2 uv1 = vec2(p_norm.x * c1 - p_norm.y * s1, p_norm.x * s1 + p_norm.y * c1) * 1.45
		+ vec2(swirl_clock * 0.028, -swirl_clock * 0.022);
	float rot2 = (1.0 - r) * 4.40 - swirl_clock * 0.68 + 1.1;
	float c2 = cos(rot2);
	float s2 = sin(rot2);
	vec2 uv2 = vec2(p_norm.x * c2 - p_norm.y * s2, p_norm.x * s2 + p_norm.y * c2) * 2.35
		- vec2(swirl_clock * 0.042, swirl_clock * 0.031);
	vec3 f1 = texture(foam_tex, uv1 * 0.5 + 0.5).rgb;
	vec3 f2 = texture(foam_tex, uv2 * 0.5 + 0.5).rgb;

	float ang = atan(p_norm.y, p_norm.x);
	float ang_mask = smoothstep(0.02, 0.14, r);
	float edge_noise = (f1.g - 0.5) * 0.22 + (f2.g - 0.5) * 0.14 + sin(ang * 5.0 - swirl_clock * 0.85) * 0.045 * ang_mask;
	float rn = r + edge_noise;
	float outer_mask = 1.0 - smoothstep(0.66, 0.98, rn);

	float cl = ink_cloud_light(v_world_xz);
	vec3 sun_l = sun_color * max(sun_dir.y, 0.08) * cl;
	vec3 light_env = ambient_color * 0.62 + sun_l * 0.36;
	// Deep midnight-indigo abyssal stain that stays blue-teal and readable at night.
	vec3 ink_core = vec3(0.008, 0.018, 0.045) + vec3(0.012, 0.036, 0.068) * light_env;
	float oily_sheen = pow(max(1.0 - r, 0.0), 1.6) * (0.35 + 0.65 * f1.g);
	ink_core += vec3(0.012, 0.048, 0.075) * oily_sheen;

	// Swirling bioluminescent cyan-aqua vortex filaments pulsing with boss rage.
	float spiral_arms = (sin(ang * 4.0 + r * 9.5 - swirl_clock * 1.85) * 0.5 + 0.5) * ang_mask;
	float ring_outer = exp(-pow((r - 0.65) / 0.15, 2.0)) * 0.90;
	float ring_inner = exp(-pow((r - 0.35) / 0.14, 2.0)) * 0.58;
	float lace_vein = (1.0 - smoothstep(0.16, 0.56, f1.r)) * (0.42 + 0.58 * f2.g);
	float biolum = (ring_outer + ring_inner) * (0.32 + 0.68 * spiral_arms) * lace_vein;
	float pulse = 0.78 + 0.22 * sin(swirl_clock * 2.7 - r * 5.2) + rage_pulse * (0.90 + 0.38 * sin(swirl_clock * 12.0));
	vec3 glow_col = mix(vec3(0.05, 0.74, 0.84), vec3(0.32, 1.0, 0.95), clamp(rage_pulse, 0.0, 1.0));

	// Frothy lacy perimeter ring blending seamlessly into Ocean.add_foam.
	float rim_band = smoothstep(0.55, 0.78, rn) * (1.0 - smoothstep(0.80, 0.99, rn));
	float foam_lace = (1.0 - smoothstep(0.20, 0.64, f2.r)) * rim_band;
	vec3 foam_col = vec3(0.76, 0.95, 0.96) * (ambient_color * 0.85 + sun_l * 0.65);

	vec3 col = mix(ink_core, foam_col, clamp(foam_lace * 0.75, 0.0, 0.78));
	col += glow_col * biolum * pulse * 1.45;
	float cam_dist = length(CAMERA_POSITION_WORLD.xz - v_world_xz);
	col = mix(col, sky_horizon_color, smoothstep(140.0, 420.0, cam_dist) * 0.55);
	float alpha = clamp((outer_mask * 0.84 + foam_lace * 0.44 + biolum * 0.42) * hull_mask * pool_alpha, 0.0, 0.88);
	if (alpha < 0.01) {
		discard;
	}
	ALBEDO = col;
	ALPHA = alpha;
}
"""

var target_ship: Ship = null
var active: bool = true
var _tentacles: Array[Dictionary] = []
var _clock: float = 0.0
var _center: Vector3 = Vector3.ZERO
var _defeated: bool = false
var _first_tick: bool = true
var _emerge_progress: float = 0.50
var _retreat_progress: float = 0.0

var _crown_root: Node3D = null
var _crown_vein_mat: StandardMaterial3D = null
var _eye_iris_mat: StandardMaterial3D = null
var _eye_rim_mat: StandardMaterial3D = null
var _eye_halo_l: MeshInstance3D = null
var _eye_halo_r: MeshInstance3D = null
var _eye_halo_mat: StandardMaterial3D = null
var _abyssal_eye_halo_energy: float = 0.0
var _eye_halo_retreat_base: float = 0.52
var _crown_emerge_sprayed: bool = false
var _crown_retreat_start_y: float = 0.0

var _ink_mesh: MeshInstance3D = null
var _ink_mat: ShaderMaterial = null
var _vortex_motes_mmi: MultiMeshInstance3D = null

var _fin_mat: StandardMaterial3D = null
var _sucker_mat: StandardMaterial3D = null
var _spray_tex: ImageTexture = null
var _spray_mat: StandardMaterial3D = null
var _seg_body_meshes: Array[ArrayMesh] = []
var _seg_vein_meshes: Array[ArrayMesh] = []
var _eye_meshes: Array[MeshInstance3D] = []
var _active_bursts: Array[GPUParticles3D] = []

# Preallocated VortexBiolumMotes buffers (zero per-frame heap allocations).
var _mote_angle: PackedFloat32Array = PackedFloat32Array()
var _mote_radius: PackedFloat32Array = PackedFloat32Array()
var _mote_height_phase: PackedFloat32Array = PackedFloat32Array()
var _mote_rise_speed: PackedFloat32Array = PackedFloat32Array()
var _mote_ang_speed: PackedFloat32Array = PackedFloat32Array()
var _mote_scale: PackedFloat32Array = PackedFloat32Array()
var _mote_twinkle_phase: PackedFloat32Array = PackedFloat32Array()
var _mote_pos: PackedVector3Array = PackedVector3Array()

static var _active_leviathans: int = 0
static var _eye_rim_mesh: ArrayMesh = null
static var _eye_iris_mesh: ArrayMesh = null
static var _eye_pupil_mesh: ArrayMesh = null
static var _eye_halo_mesh: ArrayMesh = null
static var _vortex_mote_mesh: ArrayMesh = null
static var _vortex_mote_mat: StandardMaterial3D = null


## Release statically cached sculpted Leviathan eye, halo & vortex mote caches cleanly.
static func clear_shared_cache() -> void:
	_eye_rim_mesh = null
	_eye_iris_mesh = null
	_eye_pupil_mesh = null
	_eye_halo_mesh = null
	_vortex_mote_mesh = null
	_vortex_mote_mat = null


func _enter_tree() -> void:
	_active_leviathans += 1


func _ready() -> void:
	name = "Leviathan"
	add_to_group(&"world_events")
	if global_position.is_zero_approx() and target_ship != null and is_instance_valid(target_ship):
		global_position = Vector3(target_ship.global_position.x, 0.0, target_ship.global_position.z)
	_center = Vector3(global_position.x, 0.0, global_position.z)
	_build_shared_assets()
	_build_ink_pool()
	_build_vortex_motes()
	_build_crown()
	_build_tentacles()
	_update_visual_positions(0.0)
	Audio.play_stinger(&"danger")
	Game.post_notice("Dark waters! The Abyssal Leviathan rises around the hull!")


func _exit_tree() -> void:
	_release_local_refs()
	_active_leviathans = maxi(0, _active_leviathans - 1)
	if _active_leviathans == 0:
		clear_shared_cache()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_release_local_refs()


func _release_local_refs() -> void:
	for p in _active_bursts:
		if p != null and is_instance_valid(p):
			_release_spray_burst_refs(p)
			if p.get_parent() == self:
				remove_child(p)
			p.queue_free()
	_active_bursts.clear()
	for emi in _eye_meshes:
		if emi != null and is_instance_valid(emi):
			emi.mesh = null
			emi.material_override = null
	_eye_meshes.clear()
	for hmi: MeshInstance3D in [_eye_halo_l, _eye_halo_r]:
		if hmi != null and is_instance_valid(hmi):
			hmi.visible = false
			hmi.mesh = null
			hmi.material_override = null
	_eye_halo_l = null
	_eye_halo_r = null
	_eye_halo_mat = null
	_abyssal_eye_halo_energy = 0.0
	if _vortex_motes_mmi != null and is_instance_valid(_vortex_motes_mmi):
		_vortex_motes_mmi.visible = false
		_vortex_motes_mmi.material_override = null
		_vortex_motes_mmi.multimesh = null
	_vortex_motes_mmi = null
	if _ink_mat != null:
		_ink_mat.set_shader_parameter(&"foam_tex", null)
		_ink_mat = null
	if _ink_mesh != null and is_instance_valid(_ink_mesh):
		_ink_mesh.material_override = null
		_ink_mesh = null
	if _spray_mat != null:
		_spray_mat.albedo_texture = null
		_spray_mat = null
	_spray_tex = null
	_fin_mat = null
	_sucker_mat = null
	_crown_vein_mat = null
	_eye_iris_mat = null
	_eye_rim_mat = null
	_seg_body_meshes.clear()
	_seg_vein_meshes.clear()


## Return 0..1 telegraph/windup intensity for tentacle `index`.
func get_tentacle_telegraph(index: int) -> float:
	if index < 0 or index >= _tentacles.size():
		return 0.0
	return float(_tentacles[index].get("telegraph", 0.0))


## True when tentacle `index` is actively rearing/pulsing in slam telegraph windup.
func is_tentacle_telegraphing(index: int) -> bool:
	return get_tentacle_telegraph(index) > 0.01


## Return current bioluminescent vein emission energy multiplier for tentacle `index`.
func get_tentacle_vein_energy(index: int) -> float:
	if index < 0 or index >= _tentacles.size():
		return 0.0
	var vm := _tentacles[index].get("vein_mat") as StandardMaterial3D
	return vm.emission_energy_multiplier if vm != null else 0.0


## Return the central Abyssal Maw / Head Crown node.
func get_crown_node() -> Node3D:
	return _crown_root


## Return the bioluminescent ink-pool surface mesh node.
func get_ink_pool_node() -> MeshInstance3D:
	return _ink_mesh


## Return the count of currently active spray burst particle nodes.
func active_spray_burst_count() -> int:
	return _active_bursts.size()


## Return the pair of sculpted additive abyssal eye glare halo MeshInstance3Ds.
func get_abyssal_eye_halos() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if _eye_halo_l != null and is_instance_valid(_eye_halo_l):
		out.append(_eye_halo_l)
	if _eye_halo_r != null and is_instance_valid(_eye_halo_r):
		out.append(_eye_halo_r)
	return out


## Return the current brightness energy of AbyssalEyeHalos (0.0 when retreating/hidden).
func get_abyssal_eye_halo_energy() -> float:
	return _abyssal_eye_halo_energy


## Return the MultiMeshInstance3D rendering swirling VortexBiolumMotes spores.
func get_vortex_motes_node() -> MultiMeshInstance3D:
	return _vortex_motes_mmi


## Return the current local-space positions of all 24 swirling VortexBiolumMotes spores.
func get_vortex_mote_positions() -> PackedVector3Array:
	return _mote_pos.duplicate()


## Apply damage to a specific tentacle (or the nearest living tentacle if index < 0).
func damage_tentacle(index: int, amount: float) -> bool:
	if not Net.is_host() or _defeated:
		return false
	var t_dict: Dictionary = {}
	if index >= 0 and index < _tentacles.size() and bool(_tentacles[index]["alive"]):
		t_dict = _tentacles[index]
	else:
		for entry in _tentacles:
			if bool(entry["alive"]):
				t_dict = entry
				break
	if t_dict.is_empty():
		return false
	t_dict["hp"] = float(t_dict["hp"]) - amount
	t_dict["hit_flash"] = 1.0
	var root: Node3D = t_dict["root"]
	Audio.play_sfx(&"hit_flesh", root.global_position, 2.0)
	if float(t_dict["hp"]) <= 0.0:
		t_dict["alive"] = false
		t_dict["telegraph"] = 0.0
		t_dict["sink_t"] = 0.001
		var hitbox := t_dict.get("hitbox") as StaticBody3D
		if hitbox != null and is_instance_valid(hitbox):
			hitbox.collision_layer = 0
		var hshape := t_dict.get("hitbox_shape") as CollisionShape3D
		if hshape != null and is_instance_valid(hshape):
			hshape.disabled = true
		var splash_pos := Vector3(
			root.global_position.x,
			Sea.height(root.global_position.x, root.global_position.z),
			root.global_position.z
		)
		Audio.play_sfx(&"splash_large", splash_pos, 2.0)
		_spawn_spray_burst(splash_pos, 1.45, 56)
		if Ocean.current != null:
			Ocean.current.add_foam(splash_pos, 4.6, 1.0)
		var rem := living_tentacles()
		tentacle_defeated.emit(int(t_dict["index"]), rem)
		if rem == 0:
			_on_defeated()
	return true


func living_tentacles() -> int:
	var n := 0
	for t in _tentacles:
		if bool(t["alive"]):
			n += 1
	return n


func is_defeated() -> bool:
	return _defeated


func get_health_ratio() -> float:
	if _defeated or _tentacles.is_empty():
		return 0.0
	var hp_sum := 0.0
	for t in _tentacles:
		if bool(t["alive"]):
			hp_sum += maxf(float(t["hp"]), 0.0)
	return clampf(hp_sum / (float(_tentacles.size()) * TENTACLE_HP), 0.0, 1.0)


func _physics_process(delta: float) -> void:
	_clock += delta
	if _first_tick:
		_first_tick = false
		if global_position.distance_squared_to(_center) > 1.0:
			_center = Vector3(global_position.x, 0.0, global_position.z)
		elif target_ship != null and is_instance_valid(target_ship) and _center.length_squared() < 0.01:
			_center = Vector3(target_ship.global_position.x, 0.0, target_ship.global_position.z)
			global_position = _center

	if _defeated:
		_retreat_progress = minf(1.0, _retreat_progress + delta / RETREAT_DURATION)
		_update_retreat(delta)
		if _retreat_progress >= 1.0:
			queue_free()
		return

	_emerge_progress = minf(1.0, _emerge_progress + delta / EMERGE_DURATION)

	if target_ship != null and is_instance_valid(target_ship) and not target_ship.is_sinking:
		_center = _center.lerp(target_ship.global_position, clampf(delta * 1.8, 0.0, 1.0))
		global_position = Vector3(_center.x, 0.0, _center.z)
		# Heavy ink-water drag while gripped by the Leviathan!
		if Net.is_host() and living_tentacles() > 0:
			target_ship.apply_central_force(-target_ship.linear_velocity * 3200.0)

	_update_visual_positions(delta)


func _update_visual_positions(delta: float) -> void:
	var max_rage := 0.0
	var emerge_ease := 1.0 - pow(1.0 - _emerge_progress, 2.4)

	for t in _tentacles:
		var idx: int = int(t["index"])
		var root: Node3D = t["root"]
		var is_alive: bool = bool(t["alive"])
		if not is_alive:
			_step_sinking_tentacle(t, delta)
			continue

		var hit_flash := maxf(0.0, float(t["hit_flash"]) - delta * 3.6)
		t["hit_flash"] = hit_flash

		var slam_anim := maxf(0.0, float(t["slam_anim"]) - delta * 1.55)
		t["slam_anim"] = slam_anim

		var ang := float(t["angle"]) + _clock * 0.14
		var base_rad := 12.2 + sin(_clock * 0.9 + float(idx)) * 1.55

		# Compute slam countdown & host-authoritative hull strike (exact original cadence).
		var slam_cd := float(t["slam_cd"])
		if delta > 0.0 and Net.is_host() and target_ship != null and is_instance_valid(target_ship) and not target_ship.is_sinking:
			slam_cd -= delta
			t["slam_cd"] = slam_cd
			if slam_cd <= 0.0:
				t["slam_cd"] = SLAM_INTERVAL
				slam_cd = SLAM_INTERVAL
				slam_anim = 1.0
				t["slam_anim"] = 1.0
				var slam_wx := _center.x + cos(ang) * base_rad
				var slam_wz := _center.z + sin(ang) * base_rad
				var slam_base := Vector3(slam_wx, Sea.height(slam_wx, slam_wz), slam_wz)
				var to_tent := slam_base - target_ship.global_position
				to_tent.y = 0.0
				var radial_dir := to_tent.normalized() if to_tent.length_squared() > 0.01 else Vector3(cos(ang), 0.0, sin(ang))
				var slam_pt := target_ship.global_position + radial_dir * 2.2
				slam_pt.y = target_ship.global_position.y - 0.35
				target_ship.apply_hull_damage(slam_pt, 0.42)
				Audio.play_sfx(&"hull_impact", slam_pt, 1.0)
				var impact_surf := Sea.height(slam_pt.x, slam_pt.z)
				var splash_pt := Vector3(slam_pt.x, impact_surf, slam_pt.z)
				_spawn_spray_burst(splash_pt, 1.35, 52)
				_spawn_spray_burst(slam_base, 1.05, 34)
				if Ocean.current != null:
					Ocean.current.add_foam(splash_pt, 4.6, 1.0)
					Ocean.current.add_foam(slam_base, 4.4, 0.95)

		# Diegetic telegraph ramps smoothly across the final SLAM_WINDUP_TIME seconds before slam.
		var telegraph := 0.0
		if slam_anim <= 0.05 and slam_cd > 0.0 and slam_cd <= SLAM_WINDUP_TIME:
			telegraph = clampf(1.0 - slam_cd / SLAM_WINDUP_TIME, 0.0, 1.0)
		t["telegraph"] = telegraph
		max_rage = maxf(max_rage, maxf(telegraph, slam_anim))

		var windup := smoothstep(0.0, 1.0, telegraph)
		var strike := pow(slam_anim, 0.72)
		# Pull slightly back when rearing high, then lunge fiercely inward on hull slam.
		var radius := base_rad + windup * 0.85 - strike * 2.65
		var wx := _center.x + cos(ang) * radius
		var wz := _center.z + sin(ang) * radius
		var surf := Sea.height(wx, wz)
		var y_base := lerpf(surf - 4.8, surf - 1.50, emerge_ease) + windup * 1.65 - strike * 0.55
		root.global_position = Vector3(wx, y_base, wz)
		var look_target := Vector3(_center.x, y_base, _center.z)
		if Vector2(_center.x - wx, _center.z - wz).length_squared() > 0.01:
			root.look_at(look_target, Vector3.UP)

		# Trigger dramatic feathered water-spray geyser as each tentacle emerges.
		if delta > 0.0 and not bool(t["emerge_sprayed"]) and _clock >= float(t["emerge_delay"]):
			t["emerge_sprayed"] = true
			_spawn_spray_burst(Vector3(wx, surf, wz), 1.15, 40)
			if Ocean.current != null:
				Ocean.current.add_foam(Vector3(wx, surf, wz), 4.5, 0.95)

		# Articulated 7-segment organic S-curve writhing, coiled rearing telegraph, and slam whip.
		var segs: Array = t["segs"]
		var seg_count := segs.size()
		for s in seg_count:
			var piv: Node3D = segs[s]
			var u := float(s) / float(maxi(seg_count - 1, 1))
			var wave_phase := _clock * 2.35 + float(idx) * 1.65 - float(s) * 0.85
			var idle_x := _idle_segment_pitch(s) + cos(wave_phase * 0.85 + 0.6) * lerpf(0.05, 0.14, u)
			var windup_x := _windup_segment_pitch_delta(s) * windup
			var slam_x := _slam_segment_pitch_delta(s) * strike
			var tremor := sin(_clock * 28.0 + float(idx) * 2.1 + float(s)) * 0.036 * windup * u
			var sway_damp := 1.0 - strike * 0.65
			var sway_z := sin(wave_phase) * lerpf(0.08, 0.30, u) * sway_damp + tremor
			var twist_y := sin(wave_phase * 0.72 + 1.1) * lerpf(0.04, 0.22, u) * sway_damp
			piv.rotation = Vector3(idle_x + windup_x + slam_x, twist_y, sway_z)

		# Update per-tentacle bioluminescent cyan/aqua vein pulse & hit feedback.
		_update_tentacle_materials(t, idx, telegraph, slam_anim, hit_flash)

		# Continuously churn boiling white ocean foam around every surfaced tentacle base!
		if Ocean.current != null:
			Ocean.current.add_foam(Vector3(wx, surf, wz), 3.8, 0.72)

	_update_crown(delta, emerge_ease, max_rage)
	_update_ink_pool(emerge_ease, max_rage)
	_update_vortex_motes(delta, emerge_ease, max_rage)


func _step_sinking_tentacle(t: Dictionary, delta: float) -> void:
	var root: Node3D = t["root"]
	if not root.visible:
		return
	var sink_t := minf(1.0, float(t.get("sink_t", 1.0)) + delta * 1.25)
	t["sink_t"] = sink_t
	root.global_position.y -= delta * 10.5 * (0.35 + sink_t)
	var segs: Array = t["segs"]
	for s in segs.size():
		var piv: Node3D = segs[s]
		piv.rotation.x = lerpf(piv.rotation.x, 0.35, clampf(delta * 4.0, 0.0, 1.0))
	var vein_mat := t.get("vein_mat") as StandardMaterial3D
	if vein_mat != null:
		vein_mat.emission_energy_multiplier = lerpf(vein_mat.emission_energy_multiplier, 0.05, clampf(delta * 6.0, 0.0, 1.0))
	if sink_t >= 1.0:
		root.visible = false


func _update_tentacle_materials(t: Dictionary, idx: int, telegraph: float, slam_anim: float, hit_flash: float) -> void:
	var vein_mat := t.get("vein_mat") as StandardMaterial3D
	if vein_mat != null:
		var idle_pulse := VEIN_IDLE_ENERGY_BASE + sin(_clock * 2.6 + float(idx) * 1.4) * 0.35
		var energy := idle_pulse
		var em_col := COL_VEIN_IDLE
		if telegraph > 0.01:
			var warn_freq := lerpf(8.5, 22.0, telegraph)
			var warn_pulse := 0.5 + 0.5 * sin(_clock * warn_freq + float(idx) * 1.1)
			var tele_energy := lerpf(2.85, 7.6, telegraph) + warn_pulse * lerpf(0.65, 2.1, telegraph)
			energy = maxf(energy, tele_energy)
			em_col = COL_VEIN_IDLE.lerp(COL_VEIN_TELEGRAPH, clampf(telegraph * 1.15, 0.0, 1.0))
		if slam_anim > 0.01:
			energy = maxf(energy, lerpf(VEIN_IDLE_ENERGY_BASE, 8.4, slam_anim))
			em_col = em_col.lerp(COL_VEIN_TELEGRAPH, slam_anim)
		if hit_flash > 0.01:
			em_col = em_col.lerp(COL_VEIN_HIT, hit_flash * 0.85)
			energy = maxf(energy, lerpf(VEIN_IDLE_ENERGY_BASE, 6.2, hit_flash))
		vein_mat.emission = em_col
		vein_mat.emission_energy_multiplier = energy

	var hide_mat := t.get("hide_mat") as StandardMaterial3D
	if hide_mat != null:
		if hit_flash > 0.01:
			hide_mat.emission_enabled = true
			hide_mat.emission = COL_VEIN_HIT * 0.55
			hide_mat.emission_energy_multiplier = hit_flash * 1.35
		else:
			hide_mat.emission_enabled = false


func _update_crown(delta: float, emerge_ease: float, rage: float) -> void:
	if _crown_root == null or not is_instance_valid(_crown_root):
		return
	var crown_xz := Vector2(_center.x, _center.z)
	var look_at_ship := false
	if target_ship != null and is_instance_valid(target_ship) and not target_ship.is_sinking:
		var ship_fwd := Vector3(-target_ship.global_basis.z.x, 0.0, -target_ship.global_basis.z.z)
		if ship_fwd.length_squared() < 0.001:
			ship_fwd = Vector3(0.0, 0.0, -1.0)
		else:
			ship_fwd = ship_fwd.normalized()
		var ship_right := Vector3(-ship_fwd.z, 0.0, ship_fwd.x)
		var is_brig := target_ship.ship_class == &"brigantine"
		var lat_r := 9.4 if is_brig else 8.2
		var fwd_r := 10.6 if is_brig else 8.4
		# Loom inside the inner ink ring off the ship's port-bow quarter (clear of hull & bowsprit)
		# so its glowing amber-aqua eyes stare menacingly across the bow at the crew and camera.
		var prowl_ang := -0.78 + sin(_clock * 0.22) * 0.22
		var off := ship_right * (sin(prowl_ang) * lat_r) + ship_fwd * (cos(prowl_ang) * fwd_r)
		crown_xz = Vector2(_center.x + off.x, _center.z + off.z)
		look_at_ship = true

	var surf := Sea.height(crown_xz.x, crown_xz.y)
	var breath := sin(_clock * 1.25) * 0.24 + rage * 0.35
	var sub_y := lerpf(surf - 3.6, surf + 0.26, emerge_ease) + breath
	_crown_root.global_position = Vector3(crown_xz.x, sub_y, crown_xz.y)

	var wave_n := Sea.normal(crown_xz.x, crown_xz.y)
	var tilt_up := Vector3.UP.lerp(wave_n, 0.32).normalized()
	if look_at_ship and Vector2(_center.x - crown_xz.x, _center.z - crown_xz.y).length_squared() > 0.05:
		_crown_root.look_at(Vector3(_center.x, sub_y + 0.35, _center.z), tilt_up)
	else:
		var yaw := _clock * 0.16
		_crown_root.rotation = Vector3(sin(_clock * 0.9) * 0.06, yaw, cos(_clock * 0.7) * 0.05)

	if delta > 0.0 and not _crown_emerge_sprayed and _clock >= 0.12:
		_crown_emerge_sprayed = true
		_spawn_spray_burst(Vector3(crown_xz.x, surf, crown_xz.y), 1.30, 44)
		if Ocean.current != null:
			Ocean.current.add_foam(Vector3(crown_xz.x, surf, crown_xz.y), 4.8, 0.95)

	# Pulse glowing amber-aqua eyes & temple veins with boss breathing and slam rage.
	var eye_pulse := 0.85 + 0.15 * sin(_clock * 3.1) + rage * 1.15
	if _eye_iris_mat != null:
		_eye_iris_mat.emission_energy_multiplier = 3.6 * eye_pulse
	if _eye_rim_mat != null:
		_eye_rim_mat.emission_energy_multiplier = 2.8 * (0.85 + 0.15 * cos(_clock * 2.4) + rage * 1.45)
	if _crown_vein_mat != null:
		_crown_vein_mat.emission = COL_VEIN_IDLE.lerp(COL_VEIN_TELEGRAPH, clampf(rage, 0.0, 1.0))
		_crown_vein_mat.emission_energy_multiplier = 1.65 + sin(_clock * 2.3) * 0.35 + rage * 4.4

	# Pulse additive amber-aqua AbyssalEyeHalos with nocturnal darkness & tentacle slam rage.
	var daylight := clampf(Weather.daylight(), 0.0, 1.0) if Weather != null else 1.0
	var night := clampf(1.0 - daylight, 0.0, 1.0)
	var storm := 0.0
	if Weather != null:
		storm = clampf(
			Weather.local_storminess(global_position) if is_inside_tree() else Weather.storminess,
			0.0,
			1.0
		)
	var dark_fac := clampf(maxf(night, storm * 0.45), 0.0, 1.0)
	var emerge_fac := lerpf(0.75, 1.0, emerge_ease)
	var calm_e := lerpf(0.52, 1.05, dark_fac) * (0.97 + 0.03 * sin(_clock * 2.8))
	var rage_t := smoothstep(0.0, 1.0, clampf(rage, 0.0, 1.0))
	var rage_throb := 1.0 + 0.04 * sin(_clock * 14.0) * rage_t
	var halo_e := lerpf(calm_e, 1.55 + dark_fac * 0.14, rage_t) * rage_throb * emerge_fac
	var halo_s := lerpf(lerpf(0.68, 0.88, dark_fac), 1.12 + dark_fac * 0.06, rage_t)
	var halo_tint := Color(1.0, 0.90, 0.62).lerp(Color(0.86, 0.98, 0.84), dark_fac * 0.35)
	halo_tint = halo_tint.lerp(Color(0.78, 1.0, 0.90), rage_t * 0.55)
	_apply_abyssal_eye_halos(halo_e, halo_s, halo_tint)

	if Ocean.current != null:
		Ocean.current.add_foam(Vector3(crown_xz.x, surf, crown_xz.y), 4.2, 0.68)


func _apply_abyssal_eye_halos(energy: float, halo_scale: float, tint: Color) -> void:
	if _eye_halo_l == null or _eye_halo_r == null or _eye_halo_mat == null:
		return
	if not is_instance_valid(_eye_halo_l) or not is_instance_valid(_eye_halo_r):
		return
	var show_halos := energy > 0.005
	_abyssal_eye_halo_energy = energy if show_halos else 0.0
	_eye_halo_l.visible = show_halos
	_eye_halo_r.visible = show_halos
	if show_halos:
		var sv := Vector3(halo_scale, halo_scale, halo_scale)
		_eye_halo_l.scale = sv
		_eye_halo_r.scale = sv
		_eye_halo_mat.albedo_color = Color(
			tint.r * _abyssal_eye_halo_energy,
			tint.g * _abyssal_eye_halo_energy,
			tint.b * _abyssal_eye_halo_energy,
			1.0
		)
	else:
		_eye_halo_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)


func _update_ink_pool(emerge_ease: float, rage: float) -> void:
	if _ink_mesh == null or not is_instance_valid(_ink_mesh) or _ink_mat == null:
		return
	var center_surf := Sea.height(_center.x, _center.z)
	_ink_mesh.global_position = Vector3(_center.x, center_surf, _center.z)
	_ink_mat.set_shader_parameter(&"pool_alpha", emerge_ease)
	_ink_mat.set_shader_parameter(&"rage_pulse", rage)
	_ink_mat.set_shader_parameter(&"swirl_clock", _clock)

	if target_ship != null and is_instance_valid(target_ship) and not target_ship.is_sinking:
		var fwd := Vector2(-target_ship.global_basis.z.x, -target_ship.global_basis.z.z)
		if fwd.length_squared() < 0.001:
			fwd = Vector2(0.0, -1.0)
		else:
			fwd = fwd.normalized()
		var is_brig := target_ship.ship_class == &"brigantine"
		var half_ext := Vector2(2.65, 8.55) if is_brig else Vector2(2.15, 6.40)
		_ink_mat.set_shader_parameter(&"ship_cutout_on", 1.0)
		_ink_mat.set_shader_parameter(&"ship_pos", target_ship.global_position)
		_ink_mat.set_shader_parameter(&"ship_fwd", fwd)
		_ink_mat.set_shader_parameter(&"ship_half_extents", half_ext)
	else:
		_ink_mat.set_shader_parameter(&"ship_cutout_on", 0.0)

	# Stamp rotating vortex foam arcs around the ink ring so real ocean waves churn!
	if Ocean.current != null:
		for k in 2:
			var a := _clock * 0.48 + float(k) * PI
			var fx := _center.x + cos(a) * 14.5
			var fz := _center.z + sin(a) * 14.5
			Ocean.current.add_foam(Vector3(fx, Sea.height(fx, fz), fz), 3.8, 0.55)


func _update_vortex_motes(delta: float, alpha_mult: float, rage: float) -> void:
	if _vortex_motes_mmi == null or not is_instance_valid(_vortex_motes_mmi):
		return
	var mm := _vortex_motes_mmi.multimesh
	if mm == null or _mote_pos.size() != VORTEX_MOTE_COUNT:
		return
	if alpha_mult <= 0.01:
		_vortex_motes_mmi.visible = false
		return
	_vortex_motes_mmi.visible = true

	var rage_clamped := clampf(rage, 0.0, 1.0)
	var swirl_boost := 1.0 + rage_clamped * 1.45
	var rise_boost := 1.0 + rage_clamped * 1.25
	var daylight := clampf(Weather.daylight(), 0.0, 1.0) if Weather != null else 1.0
	var night := clampf(1.0 - daylight, 0.0, 1.0)
	var bright_mult := (lerpf(0.68, 1.25, night) + rage_clamped * 0.85) * alpha_mult
	var tint := COL_VEIN_IDLE.lerp(COL_VEIN_TELEGRAPH, rage_clamped * 0.85)

	for i in VORTEX_MOTE_COUNT:
		var ang := _mote_angle[i]
		var h_phase := _mote_height_phase[i]
		if delta > 0.0:
			ang = wrapf(ang + _mote_ang_speed[i] * swirl_boost * delta, -PI, PI)
			_mote_angle[i] = ang
			h_phase = fposmod(h_phase + _mote_rise_speed[i] * rise_boost * delta, 1.0)
			_mote_height_phase[i] = h_phase

		var wobble := sin(_clock * 1.8 + _mote_twinkle_phase[i]) * 0.45
		var rad := clampf(_mote_radius[i] + wobble - h_phase * 0.65, VORTEX_MOTE_MIN_R, VORTEX_MOTE_MAX_R)
		var lx := cos(ang) * rad
		var lz := sin(ang) * rad
		var surf := Sea.height(_center.x + lx, _center.z + lz) if Sea != null else 0.0
		var ly := surf + lerpf(VORTEX_MOTE_MIN_Y, VORTEX_MOTE_MAX_Y, h_phase)
		var pos := Vector3(lx, ly, lz)
		_mote_pos[i] = pos

		var fade_in := smoothstep(0.0, 0.14, h_phase)
		var fade_out := 1.0 - smoothstep(0.76, 1.0, h_phase)
		var env := clampf(fade_in * fade_out, 0.0, 1.0)
		var sc := _mote_scale[i] * lerpf(0.32, 1.0, env) * (1.0 + rage_clamped * 0.35)
		var spin := ang * 1.4 + _clock * 2.2
		var mb := Basis(Vector3.UP, spin) * Basis.from_scale(Vector3(sc, sc * 1.35, sc))
		mm.set_instance_transform(i, Transform3D(mb, pos))

		var twinkle := 0.80 + 0.20 * sin(_clock * 6.5 + _mote_twinkle_phase[i])
		var glow := bright_mult * env * twinkle
		mm.set_instance_color(i, Color(tint.r * glow, tint.g * glow, tint.b * glow, 1.0))


func _update_retreat(delta: float) -> void:
	var ease_t := lerpf(_retreat_progress, smoothstep(0.0, 1.0, _retreat_progress), 0.45)
	for t in _tentacles:
		_step_sinking_tentacle(t, delta)

	if _crown_root != null and is_instance_valid(_crown_root):
		var cx := _crown_root.global_position.x
		var cz := _crown_root.global_position.z
		var surf := Sea.height(cx, cz)
		_crown_root.global_position.y = lerpf(_crown_retreat_start_y, surf - 5.5, ease_t)
		_crown_root.rotation.x = lerpf(_crown_root.rotation.x, -0.35, clampf(delta * 2.5, 0.0, 1.0))
		if Ocean.current != null and _retreat_progress < 0.75:
			Ocean.current.add_foam(Vector3(cx, surf, cz), 4.6, 0.72 * (1.0 - ease_t))

	var fade := maxf(0.0, 1.0 - ease_t)
	if _eye_iris_mat != null:
		_eye_iris_mat.emission_energy_multiplier = 3.2 * fade * fade
	if _eye_rim_mat != null:
		_eye_rim_mat.emission_energy_multiplier = 2.4 * fade * fade
	if _crown_vein_mat != null:
		_crown_vein_mat.emission_energy_multiplier = 1.6 * fade * fade
	if _ink_mat != null:
		_ink_mat.set_shader_parameter(&"pool_alpha", fade)
		_ink_mat.set_shader_parameter(&"rage_pulse", 0.0)
		_ink_mat.set_shader_parameter(&"swirl_clock", _clock)

	var halo_fade := fade * fade if fade > 0.04 else 0.0
	_apply_abyssal_eye_halos(_eye_halo_retreat_base * halo_fade, lerpf(0.35, 0.85, fade), Color(0.86, 0.96, 0.82))
	_update_vortex_motes(delta, fade * fade, 0.0)


func _on_defeated() -> void:
	_defeated = true
	active = false
	_retreat_progress = 0.0
	_eye_halo_retreat_base = maxf(_abyssal_eye_halo_energy, 0.52)
	var salvage: Array = []
	var parent := get_parent()
	if parent != null:
		var surf := Sea.height(_center.x, _center.z)
		var loot_ids: Array[StringName] = [&"archive_chalice", &"sovereign_chest"]
		for i in loot_ids.size():
			var pos := Vector3(_center.x + (float(i) - 0.5) * 4.0, surf + 0.35, _center.z)
			var item := TreasureCatalog.create_treasure_carryable(loot_ids[i], pos)
			parent.add_child(item)
			item.global_position = pos
			salvage.append(item)
	if _crown_root != null and is_instance_valid(_crown_root):
		var cpos := _crown_root.global_position
		_crown_retreat_start_y = cpos.y
		var csurf := Sea.height(cpos.x, cpos.z)
		_spawn_spray_burst(Vector3(cpos.x, csurf, cpos.z), 1.5, 54)
		if Ocean.current != null:
			Ocean.current.add_foam(Vector3(cpos.x, csurf, cpos.z), 5.2, 1.0)
	Audio.play_stinger(&"victory")
	Game.post_notice("The Abyssal Leviathan retreats to the deep! Treasure rises to the surface!")
	leviathan_defeated.emit(_center, salvage)


# ------------------------------------------------------------------ posture curves

static func _tentacle_radius(t: float) -> float:
	return lerpf(BASE_RADIUS, TIP_RADIUS, pow(clampf(t, 0.0, 1.0), 0.88))


static func _segment_length(seg_idx: int) -> float:
	return lerpf(2.15, 1.45, float(seg_idx) / float(maxi(SEGMENT_COUNT - 1, 1)))


static func _idle_segment_pitch(seg_idx: int) -> float:
	const PITCHES := [0.16, 0.06, -0.14, -0.24, -0.22, 0.16, -0.34]
	return float(PITCHES[clampi(seg_idx, 0, PITCHES.size() - 1)])


static func _windup_segment_pitch_delta(seg_idx: int) -> float:
	# Lower segments rear powerfully backward (+X); upper whip coils tightly inward (-X).
	const DELTAS := [0.26, 0.20, 0.08, -0.28, -0.44, -0.52, -0.46]
	return float(DELTAS[clampi(seg_idx, 0, DELTAS.size() - 1)])


static func _slam_segment_pitch_delta(seg_idx: int) -> float:
	# Explosive whipping slash forward across the ship hull.
	const DELTAS := [-0.46, -0.34, -0.22, -0.14, -0.06, 0.06, -0.10]
	return float(DELTAS[clampi(seg_idx, 0, DELTAS.size() - 1)])


# ------------------------------------------------------------------ procedural builders

func _build_shared_assets() -> void:
	_fin_mat = StandardMaterial3D.new()
	_fin_mat.vertex_color_use_as_albedo = true
	_fin_mat.roughness = 0.26
	_fin_mat.metallic = 0.12
	_fin_mat.clearcoat_enabled = true
	_fin_mat.clearcoat = 0.82
	_fin_mat.clearcoat_roughness = 0.18
	_fin_mat.rim_enabled = true
	_fin_mat.rim = 0.35
	_fin_mat.rim_tint = 0.55

	_sucker_mat = StandardMaterial3D.new()
	_sucker_mat.vertex_color_use_as_albedo = true
	_sucker_mat.roughness = 0.44
	_sucker_mat.clearcoat_enabled = true
	_sucker_mat.clearcoat = 0.36
	_sucker_mat.clearcoat_roughness = 0.32

	_spray_tex = _build_spray_texture()
	_spray_mat = StandardMaterial3D.new()
	_spray_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spray_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_spray_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_spray_mat.vertex_color_use_as_albedo = true
	_spray_mat.albedo_texture = _spray_tex
	_spray_mat.albedo_color = Color(0.90, 0.98, 1.0, 0.90)
	_spray_mat.roughness = 0.85
	_spray_mat.backlight_enabled = true
	_spray_mat.backlight = Color(0.80, 0.94, 0.96)
	_spray_mat.emission_enabled = true
	_spray_mat.emission = Color(0.45, 0.82, 0.88)
	_spray_mat.emission_energy_multiplier = 0.14

	_seg_body_meshes.clear()
	_seg_vein_meshes.clear()
	for s in SEGMENT_COUNT:
		_seg_body_meshes.append(_build_tentacle_segment_mesh(s))
		_seg_vein_meshes.append(_build_tentacle_vein_mesh(s))


func _make_hide_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.35
	mat.metallic = 0.08
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.68
	mat.clearcoat_roughness = 0.22
	mat.rim_enabled = true
	mat.rim = 0.35
	mat.rim_tint = 0.45
	return mat


func _make_vein_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.95, 0.92)
	mat.roughness = 0.20
	mat.emission_enabled = true
	mat.emission = COL_VEIN_IDLE
	mat.emission_energy_multiplier = VEIN_IDLE_ENERGY_BASE
	return mat


func _build_tentacles() -> void:
	for i in TENTACLE_COUNT:
		var root := Node3D.new()
		root.name = "Tentacle_%d" % i
		add_child(root)

		var hide_mat := _make_hide_material()
		var vein_mat := _make_vein_material()

		var segs: Array[Node3D] = []
		var parent_node: Node3D = root
		for s in SEGMENT_COUNT:
			var pivot := Node3D.new()
			pivot.name = "Seg_%d" % s
			pivot.position = Vector3(0.0, _segment_length(s - 1) if s > 0 else 0.0, 0.0)
			parent_node.add_child(pivot)

			var body_inst := MeshInstance3D.new()
			body_inst.name = "BodyMesh"
			body_inst.mesh = _seg_body_meshes[s]
			body_inst.set_surface_override_material(0, hide_mat)
			body_inst.set_surface_override_material(1, _fin_mat)
			body_inst.set_surface_override_material(2, _sucker_mat)
			pivot.add_child(body_inst)

			var vein_inst := MeshInstance3D.new()
			vein_inst.name = "BiolumVeins"
			vein_inst.mesh = _seg_vein_meshes[s]
			vein_inst.material_override = vein_mat
			vein_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pivot.add_child(vein_inst)

			segs.append(pivot)
			parent_node = pivot

		# Hittable collider body so cannonballs & pistol shots can strike each tentacle!
		var body := StaticBody3D.new()
		body.name = "TentacleHitbox_%d" % i
		body.collision_layer = Pawn.LAYER_PAWN
		body.collision_mask = 0
		body.set_meta("leviathan", self)
		body.set_meta("tentacle_index", i)
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.95
		cap.height = 10.6
		cs.shape = cap
		cs.position = Vector3(0.0, 5.2, 0.0)
		body.add_child(cs)
		root.add_child(body)

		_tentacles.append({
			"index": i,
			"root": root,
			"segs": segs,
			"hp": TENTACLE_HP,
			"alive": true,
			"angle": float(i) * TAU / float(TENTACLE_COUNT) + 0.4,
			"slam_cd": 3.5 + float(i) * 1.9,
			"slam_anim": 0.0,
			"telegraph": 0.0,
			"hit_flash": 0.0,
			"sink_t": 0.0,
			"emerge_delay": 0.04 + float(i) * 0.14,
			"emerge_sprayed": false,
			"hide_mat": hide_mat,
			"vein_mat": vein_mat,
			"hitbox": body,
			"hitbox_shape": cs,
		})


## Build a multi-surface sculpted ArrayMesh for tentacle segment `seg_idx`:
##   Surface 0: muscular organic hide (seamless 360-deg smooth normals + mottled vertex color)
##   Surface 1: raised jagged dorsal spine fin ridges along +Z
##   Surface 2: staggered twin rows of cupped lavender-coral sucker discs along -Z
func _build_tentacle_segment_mesh(seg_idx: int) -> ArrayMesh:
	var seg_len := _segment_length(seg_idx)
	var t0 := float(seg_idx) / float(SEGMENT_COUNT)
	var t1 := float(seg_idx + 1) / float(SEGMENT_COUNT)
	var is_tip := (seg_idx == SEGMENT_COUNT - 1)
	var out_mesh := ArrayMesh.new()

	# --- Surface 0: sculpted organic tapered hide ---
	var radial := 16
	var u_samples: PackedFloat32Array = PackedFloat32Array(
		[-0.14, 0.0, 0.20, 0.42, 0.65, 0.85, 1.0, 1.14] if not is_tip else [-0.14, 0.0, 0.22, 0.48, 0.72, 0.90, 1.04, 1.16]
	)
	var ring_count := u_samples.size()
	var grid: Array = []
	var col_grid: Array = []
	for r_i in ring_count:
		var u := u_samples[r_i]
		var t_glob := clampf(lerpf(t0, t1, clampf(u, 0.0, 1.0)), 0.0, 1.0)
		var base_r := _tentacle_radius(t_glob)
		var r_mul := 1.0
		var z_curl := 0.0
		if u < 0.0:
			# Rounded basal socket overlap so joint never cracks on steep bend.
			r_mul = lerpf(0.76, 1.0, (u + 0.14) / 0.14)
		elif is_tip and u > 0.72:
			# Curling whip-like needle tip.
			var tip_f := clampf((u - 0.72) / (1.16 - 0.72), 0.0, 1.0)
			base_r = lerpf(TIP_RADIUS, 0.022, pow(tip_f, 1.15))
			z_curl = -0.26 * tip_f * tip_f
		elif u > 1.0:
			# Rounded distal knuckle dome nesting inside child segment.
			r_mul = lerpf(1.0, 0.74, (u - 1.0) / 0.14)
		else:
			# Muscular swell + subtle organic skin annulations.
			r_mul = 1.0 + 0.045 * sin(u * PI) + 0.018 * sin(u * TAU * 2.0)

		var y := u * seg_len
		var ring_pts: Array[Vector3] = []
		var ring_cols: Array[Color] = []
		for k in radial:
			var a := float(k) / float(radial) * TAU
			var ca := cos(a)
			var sa := sin(a)
			# +Z (sa > 0) = dorsal armored keel; -Z (sa < 0) = ventral sucker track.
			var dorsal := maxf(0.0, sa)
			var ventral := maxf(0.0, -sa)
			var lip := exp(-pow((sa + 0.62) / 0.24, 2.0))
			var shape_mod := 1.0 + 0.16 * pow(dorsal, 2.3) - 0.11 * pow(ventral, 1.8) + 0.055 * lip
			var rad := base_r * r_mul * shape_mod
			ring_pts.append(Vector3(ca * rad, y, sa * rad + z_curl))

			var dorsal_col := COL_HIDE_DORSAL_BASE.lerp(COL_HIDE_DORSAL_TIP, t_glob)
			var c := dorsal_col.lerp(COL_HIDE_FLANK, clampf(absf(ca) * 0.85, 0.0, 1.0))
			c = c.lerp(COL_HIDE_VENTRAL, pow(ventral, 1.4) * 0.88)
			var mottle := 1.0 + 0.11 * sin(a * 5.0 + t_glob * 16.0) * cos(t_glob * 24.0 + a * 3.0)
			if seg_idx == 0 and u < 0.35:
				mottle *= lerpf(0.76, 1.0, clampf((u + 0.14) / 0.49, 0.0, 1.0))
			ring_cols.append(Color(c.r * mottle, c.g * mottle, c.b * mottle, 1.0))
		grid.append(ring_pts)
		col_grid.append(ring_cols)

	var st_hide := SurfaceTool.new()
	st_hide.begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_smooth_loft(st_hide, grid, col_grid, true, true)
	st_hide.commit(out_mesh)

	# --- Surface 1: raised jagged dorsal spine fin ridges along +Z ---
	var st_fins := SurfaceTool.new()
	st_fins.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fin_fracs: PackedFloat32Array = PackedFloat32Array([0.34]) if is_tip else PackedFloat32Array([0.27, 0.72])
	for f_u in fin_fracs:
		var t_f := lerpf(t0, t1, f_u)
		var r_f := _tentacle_radius(t_f)
		var fin_y := f_u * seg_len
		var fin_h := seg_len * (0.44 if not is_tip else 0.38)
		var fin_depth := r_f * (0.86 if not is_tip else 0.78)
		var fin_hw := maxf(r_f * 0.22, 0.025)
		_append_dorsal_fin(st_fins, Vector3(0.0, fin_y, r_f * 0.94), fin_h, fin_depth, fin_hw)
	st_fins.generate_normals()
	st_fins.commit(out_mesh)

	# --- Surface 2: staggered twin rows of pale lavender-coral cupped sucker discs along -Z ---
	var st_suckers := SurfaceTool.new()
	st_suckers.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pair_count := 3 if seg_idx <= 2 else (2 if seg_idx <= 5 else 1)
	for p_i in pair_count:
		var u_base := (float(p_i) + 0.5) / float(pair_count)
		if is_tip:
			# Single tapered pair near base of tip segment.
			for side_s: float in [-1.0, 1.0]:
				var u_s := clampf(0.24 + (0.20 if side_s > 0.0 else 0.0), 0.10, 0.62)
				var r_here := _tentacle_radius(lerpf(t0, t1, u_s))
				var ang_s := -PI * 0.5 + side_s * 0.30
				var pos := Vector3(cos(ang_s) * r_here * 0.88, u_s * seg_len, sin(ang_s) * r_here * 0.88)
				var out_d := Vector3(cos(ang_s), 0.0, sin(ang_s))
				_append_sucker_cup(st_suckers, pos, out_d, r_here * 0.34, 8)
		else:
			for side_s: float in [-1.0, 1.0]:
				var stagger := 0.075 * side_s
				var u_s := clampf(u_base + stagger, 0.12, 0.88)
				var r_here := _tentacle_radius(lerpf(t0, t1, u_s))
				var ang_s := -PI * 0.5 + side_s * 0.44
				var pos := Vector3(cos(ang_s) * r_here * 0.89, u_s * seg_len, sin(ang_s) * r_here * 0.89)
				var out_d := Vector3(cos(ang_s), 0.0, sin(ang_s))
				_append_sucker_cup(st_suckers, pos, out_d, r_here * 0.35, 10)
	st_suckers.generate_normals()
	st_suckers.commit(out_mesh)

	return out_mesh


## Build lateral bioluminescent cyan/aqua vein nodes & connecting filaments for segment `seg_idx`.
func _build_tentacle_vein_mesh(seg_idx: int) -> ArrayMesh:
	var seg_len := _segment_length(seg_idx)
	var t0 := float(seg_idx) / float(SEGMENT_COUNT)
	var t1 := float(seg_idx + 1) / float(SEGMENT_COUNT)
	var is_tip := (seg_idx == SEGMENT_COUNT - 1)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for side_s: float in [-1.0, 1.0]:
		# Positioned slightly ventral-lateral so veins shine toward BOTH deck & broadside views.
		var flank_ang := (0.0 if side_s > 0.0 else PI) - side_s * 0.26
		var ca := cos(flank_ang)
		var sa := sin(flank_ang)
		var out_d := Vector3(ca, 0.0, sa)

		var node_fracs: PackedFloat32Array = PackedFloat32Array([0.30]) if is_tip else PackedFloat32Array([0.28, 0.72])
		for u_n in node_fracs:
			var r_here := _tentacle_radius(lerpf(t0, t1, u_n))
			var pos := Vector3(ca * r_here * 0.99, u_n * seg_len, sa * r_here * 0.99)
			_append_vein_pod(st, pos, out_d, r_here * 0.22, seg_len * 0.14, r_here * 0.13)

		# Sleek continuous bioluminescent vein filament tracing vertically up each flank.
		var r_lo := _tentacle_radius(lerpf(t0, t1, 0.08))
		var r_hi := _tentacle_radius(lerpf(t0, t1, 0.92 if not is_tip else 0.72))
		var p_lo := Vector3(ca * r_lo * 0.99, 0.08 * seg_len, sa * r_lo * 0.99)
		var p_hi := Vector3(ca * r_hi * 0.99, (0.92 if not is_tip else 0.72) * seg_len, sa * r_hi * 0.99)
		_append_vein_filament(st, p_lo, p_hi, out_d, maxf(r_lo * 0.055, 0.016), maxf(r_hi * 0.045, 0.012))

	st.generate_normals()
	return st.commit()


## Build the menacing partially-submerged Central Abyssal Maw / Head Crown with
## armored dorsal mantle, serrated crest spines, curved beak prow, and amber-aqua eyes.
func _build_crown() -> void:
	_crown_root = Node3D.new()
	_crown_root.name = "AbyssalCrown"
	add_child(_crown_root)

	var crown_hide_mat := _make_hide_material()
	crown_hide_mat.roughness = 0.32
	crown_hide_mat.clearcoat = 0.74

	# 1. Sculpted cranial mantle dome & overhanging armored supraorbital brow hoods.
	var dome_inst := MeshInstance3D.new()
	dome_inst.name = "CrownMantle"
	dome_inst.mesh = _build_crown_mantle_mesh()
	dome_inst.material_override = crown_hide_mat
	_crown_root.add_child(dome_inst)

	# 2. Towering serrated dorsal crown crest fins & swept cheek horns.
	var spine_inst := MeshInstance3D.new()
	spine_inst.name = "CrownSpines"
	spine_inst.mesh = _build_crown_spines_mesh()
	spine_inst.material_override = _fin_mat
	_crown_root.add_child(spine_inst)

	# 3. Curved obsidian-chitin abyssal beak & serrated lower mandible prow.
	var beak_mat := StandardMaterial3D.new()
	beak_mat.vertex_color_use_as_albedo = true
	beak_mat.roughness = 0.22
	beak_mat.metallic = 0.18
	beak_mat.clearcoat_enabled = true
	beak_mat.clearcoat = 0.85
	var beak_inst := MeshInstance3D.new()
	beak_inst.name = "AbyssalBeak"
	beak_inst.mesh = _build_crown_beak_mesh()
	beak_inst.material_override = beak_mat
	_crown_root.add_child(beak_inst)

	# 4. Pair of 100% sculpted flat-faceted abyssal kraken eyes nestled beneath the brow ridges.
	if _eye_rim_mesh == null:
		_eye_rim_mesh = _build_eye_socket_rim_mesh()
	if _eye_iris_mesh == null:
		_eye_iris_mesh = _build_eye_iris_dome_mesh()
	if _eye_pupil_mesh == null:
		_eye_pupil_mesh = _build_eye_slit_pupil_mesh()
	if _eye_halo_mesh == null:
		_eye_halo_mesh = _build_eye_halo_mesh()

	_eye_iris_mat = StandardMaterial3D.new()
	_eye_iris_mat.albedo_color = Color.WHITE
	_eye_iris_mat.vertex_color_use_as_albedo = true
	_eye_iris_mat.vertex_color_is_srgb = true
	_eye_iris_mat.roughness = 0.14
	_eye_iris_mat.clearcoat_enabled = true
	_eye_iris_mat.clearcoat = 0.85
	_eye_iris_mat.emission_enabled = true
	_eye_iris_mat.emission = COL_EYE_AMBER
	_eye_iris_mat.emission_energy_multiplier = 3.2

	_eye_rim_mat = StandardMaterial3D.new()
	_eye_rim_mat.albedo_color = Color.WHITE
	_eye_rim_mat.vertex_color_use_as_albedo = true
	_eye_rim_mat.vertex_color_is_srgb = true
	_eye_rim_mat.roughness = 0.24
	_eye_rim_mat.metallic = 0.14
	_eye_rim_mat.clearcoat_enabled = true
	_eye_rim_mat.clearcoat = 0.65
	_eye_rim_mat.emission_enabled = true
	_eye_rim_mat.emission = COL_EYE_AQUA
	_eye_rim_mat.emission_energy_multiplier = 1.4

	_eye_halo_mat = StandardMaterial3D.new()
	_eye_halo_mat.vertex_color_use_as_albedo = true
	_eye_halo_mat.vertex_color_is_srgb = true
	_eye_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_eye_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_eye_halo_mat.billboard_keep_scale = true
	_eye_halo_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_eye_halo_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_eye_halo_mat.render_priority = 2
	_eye_halo_mat.albedo_color = Color(0.52, 0.52, 0.52, 1.0)

	var pupil_mat := StandardMaterial3D.new()
	pupil_mat.albedo_color = Color.WHITE
	pupil_mat.vertex_color_use_as_albedo = true
	pupil_mat.vertex_color_is_srgb = true
	pupil_mat.roughness = 0.08
	pupil_mat.clearcoat_enabled = true
	pupil_mat.clearcoat = 0.95

	for side_i in 2:
		var sx := -1.0 if side_i == 0 else 1.0
		var eye_pivot := Node3D.new()
		eye_pivot.name = "EyeLeft" if side_i == 0 else "EyeRight"
		eye_pivot.position = Vector3(sx * 1.12, 0.48, -1.16)
		eye_pivot.rotation_degrees = Vector3(-6.0, -sx * 32.0, 0.0)
		_crown_root.add_child(eye_pivot)

		# Sculpted 12-segment flanged armored kraken eye-socket bezel.
		var rim_inst := MeshInstance3D.new()
		rim_inst.name = "AquaRim"
		rim_inst.mesh = _eye_rim_mesh
		rim_inst.material_override = _eye_rim_mat
		eye_pivot.add_child(rim_inst)
		_eye_meshes.append(rim_inst)

		# Sculpted 12-segment faceted convex crystal cat-iris dome.
		var iris_inst := MeshInstance3D.new()
		iris_inst.name = "AmberIris"
		iris_inst.mesh = _eye_iris_mesh
		iris_inst.position = Vector3(0.0, 0.0, -0.08)
		iris_inst.material_override = _eye_iris_mat
		eye_pivot.add_child(iris_inst)
		_eye_meshes.append(iris_inst)

		# Sculpted tapered 6-facet vertical abyssal diamond-slit pupil lens.
		var pupil_inst := MeshInstance3D.new()
		pupil_inst.name = "SlitPupil"
		pupil_inst.mesh = _eye_pupil_mesh
		pupil_inst.position = Vector3(0.0, 0.0, -0.29)
		pupil_inst.material_override = pupil_mat
		eye_pivot.add_child(pupil_inst)
		_eye_meshes.append(pupil_inst)

		# Additive 48-tri amber-aqua predator glare halo mounted right over the eye surface.
		var halo_inst := MeshInstance3D.new()
		halo_inst.name = "AbyssalEyeHaloL" if side_i == 0 else "AbyssalEyeHaloR"
		halo_inst.position = eye_pivot.transform * Vector3(0.0, 0.0, -0.35)
		halo_inst.mesh = _eye_halo_mesh
		halo_inst.material_override = _eye_halo_mat
		halo_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		halo_inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		halo_inst.visibility_range_end = EYE_HALO_VISIBILITY_END
		_crown_root.add_child(halo_inst)
		if side_i == 0:
			_eye_halo_l = halo_inst
		else:
			_eye_halo_r = halo_inst

	# 5. Glowing cyan-aqua temple veins sweeping back behind the eyes.
	_crown_vein_mat = _make_vein_material()
	var crown_vein_inst := MeshInstance3D.new()
	crown_vein_inst.name = "CrownVeins"
	crown_vein_inst.mesh = _build_crown_veins_mesh()
	crown_vein_inst.material_override = _crown_vein_mat
	crown_vein_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_crown_root.add_child(crown_vein_inst)


static func _build_eye_socket_rim_mesh() -> ArrayMesh:
	# 12-segment flanged hexagonal-oval ridged armored kraken eye-socket bezel facing -Z.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGS := 12
	var col_chitin_dark := Color(0.045, 0.115, 0.150)
	var col_chitin_mid := Color(0.085, 0.215, 0.255)
	var col_aqua_inner := COL_EYE_AQUA

	# 4 profile rings from rear socket mount -> outer armored ridge -> front flanged lip -> inner glowing sclera rim.
	var prof: Array[Array] = [
		[0.54, 0.42, 0.14, col_chitin_dark],
		[0.50, 0.39, -0.05, col_chitin_mid],
		[0.42, 0.33, -0.17, col_chitin_mid.lerp(col_aqua_inner, 0.45)],
		[0.31, 0.24, -0.10, col_aqua_inner],
	]
	var rings: Array[Array] = []
	var cols: Array[Array] = []
	for pi in prof.size():
		var row: Array = prof[pi]
		var rx := float(row[0])
		var ry := float(row[1])
		var z0 := float(row[2])
		var base_c: Color = row[3] as Color
		var ring: Array[Vector3] = []
		var rcols: Array[Color] = []
		for k in SEGS:
			var a := float(k) / float(SEGS) * TAU
			var ca := cos(a)
			var sa := sin(a)
			# Hexagonal-oval armor flanging + heavier overhanging upper brow hood (sa > 0).
			var ridge := 1.0 + 0.085 * cos(a * 6.0)
			var brow := 0.08 * maxf(sa, 0.0) if (pi == 1 or pi == 2) else 0.0
			var z_hood := -0.07 * maxf(sa, 0.0) if pi == 2 else 0.0
			ring.append(Vector3(ca * rx * ridge, sa * ry * ridge + brow, z0 + z_hood))
			var c := base_c.lightened(0.08) if (k % 2 == 0 and pi == 1) else base_c
			rcols.append(c)
		rings.append(ring)
		cols.append(rcols)

	var center_ref := Vector3(0.0, 0.0, 0.18)
	for pi in range(rings.size() - 1):
		var r0: Array = rings[pi]
		var r1: Array = rings[pi + 1]
		var c0: Array = cols[pi]
		var c1: Array = cols[pi + 1]
		for k in SEGS:
			var nk := (k + 1) % SEGS
			_emit_eye_quad(st, r0[k] as Vector3, r1[k] as Vector3, r1[nk] as Vector3, r0[nk] as Vector3,
				center_ref, c0[k] as Color, c1[k] as Color, c1[nk] as Color, c0[nk] as Color)

	# Close back of socket cleanly so there are zero open seams.
	var back_c := Vector3(0.0, 0.0, 0.18)
	var r_back: Array = rings[0]
	var c_back: Array = cols[0]
	for k in SEGS:
		var nk := (k + 1) % SEGS
		_emit_eye_tri(st, back_c, r_back[nk] as Vector3, r_back[k] as Vector3, Vector3(0.0, 0.0, -0.10),
			col_chitin_dark, c_back[nk] as Color, c_back[k] as Color)

	st.generate_normals()
	return st.commit()


static func _build_eye_iris_dome_mesh() -> ArrayMesh:
	# 12-segment faceted convex crystal eyeball dome glowing fierce amber-gold to aqua rim!
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGS := 12
	var col_core := Color(1.00, 0.86, 0.24)
	var col_mid := COL_EYE_AMBER
	var col_edge := COL_EYE_AMBER.lerp(COL_EYE_AQUA, 0.55)
	var col_rim := COL_EYE_AQUA

	# Latitudinal rings from outer back equator toward convex front apex (-Z).
	var rings_spec: Array[Array] = [
		[0.33, 0.255, 0.04, col_rim],
		[0.31, 0.240, -0.07, col_edge],
		[0.24, 0.185, -0.16, col_mid],
		[0.13, 0.105, -0.21, col_core],
	]
	var rings: Array[Array] = []
	var rcols: Array[Color] = []
	for spec in rings_spec:
		var rx := float(spec[0])
		var ry := float(spec[1])
		var z := float(spec[2])
		var ring: Array[Vector3] = []
		for k in SEGS:
			var a := float(k) / float(SEGS) * TAU
			ring.append(Vector3(cos(a) * rx, sin(a) * ry, z))
		rings.append(ring)
		rcols.append(spec[3] as Color)

	var ctr := Vector3(0.0, 0.0, 0.06)
	for ri in range(rings.size() - 1):
		var r0: Array = rings[ri]
		var r1: Array = rings[ri + 1]
		var c0 := rcols[ri]
		var c1 := rcols[ri + 1]
		for k in SEGS:
			var nk := (k + 1) % SEGS
			_emit_eye_quad(st, r0[k] as Vector3, r1[k] as Vector3, r1[nk] as Vector3, r0[nk] as Vector3,
				ctr, c0, c1, c1, c0)

	var front_apex := Vector3(0.0, 0.0, -0.232)
	var r_front: Array = rings[rings.size() - 1]
	for k in SEGS:
		var nk := (k + 1) % SEGS
		_emit_eye_tri(st, front_apex, r_front[k] as Vector3, r_front[nk] as Vector3, ctr, col_core, col_core, col_core)

	st.generate_normals()
	return st.commit()


static func _build_eye_slit_pupil_mesh() -> ArrayMesh:
	# Tapered 6-facet vertical abyssal diamond-slit lens protruding cleanly in front of the iris!
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col_void := Color(0.014, 0.012, 0.024)
	var col_edge := Color(0.045, 0.032, 0.072)

	var top_pt := Vector3(0.0, 0.225, 0.048)
	var bot_pt := Vector3(0.0, -0.225, 0.048)
	# Upper, mid, and lower 6-facet curved vertical slit cross-sections hugging the convex dome!
	var stations: Array[Array] = [
		[0.125, 0.028, -0.020, 0.035],
		[0.000, 0.044, -0.038, 0.028],
		[-0.125, 0.028, -0.020, 0.035],
	]
	var rings: Array[Array] = []
	for s in stations:
		var y := float(s[0])
		var hw := float(s[1])
		var zf := float(s[2])
		var zb := float(s[3])
		var zm := lerpf(zf, zb, 0.45)
		rings.append([
			Vector3(0.0, y, zf),
			Vector3(hw, y, zm),
			Vector3(hw * 0.65, y, zb),
			Vector3(0.0, y, zb + 0.012),
			Vector3(-hw * 0.65, y, zb),
			Vector3(-hw, y, zm),
		])

	var ctr := Vector3(0.0, 0.0, 0.015)
	for ri in range(rings.size() - 1):
		var r0: Array = rings[ri]
		var r1: Array = rings[ri + 1]
		for k in 6:
			var nk := (k + 1) % 6
			var c := col_void if (k == 0 or k == 5) else col_edge
			_emit_eye_quad(st, r0[k] as Vector3, r1[k] as Vector3, r1[nk] as Vector3, r0[nk] as Vector3, ctr, c, c, c, c)

	var r_top: Array = rings[0]
	var r_bot: Array = rings[rings.size() - 1]
	for k in 6:
		var nk := (k + 1) % 6
		_emit_eye_tri(st, top_pt, r_top[nk] as Vector3, r_top[k] as Vector3, ctr, col_edge, col_void, col_void)
		_emit_eye_tri(st, bot_pt, r_bot[k] as Vector3, r_bot[nk] as Vector3, ctr, col_edge, col_void, col_void)

	st.generate_normals()
	return st.commit()


## Sculpted 48-tri 16-wedge radial-gradient billboard disc for AbyssalEyeHalos (0 primitives).
## Incandescent amber-white core -> deep feathered amber-aqua mid -> pure Color(0, 0, 0, 1) black rim.
static func _build_eye_halo_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const WEDGES := 16
	const INNER_R := 0.24
	const OUTER_R := 1.00
	var n := Vector3(0.0, 0.0, 1.0)
	var ctr := Vector3.ZERO
	for i in WEDGES:
		var a0 := TAU * float(i) / float(WEDGES)
		var a1 := TAU * float(i + 1) / float(WEDGES)
		var m0 := Vector3(cos(a0) * INNER_R, sin(a0) * INNER_R, 0.0)
		var m1 := Vector3(cos(a1) * INNER_R, sin(a1) * INNER_R, 0.0)
		var o0 := Vector3(cos(a0) * OUTER_R, sin(a0) * OUTER_R, 0.0)
		var o1 := Vector3(cos(a1) * OUTER_R, sin(a1) * OUTER_R, 0.0)

		st.set_normal(n)
		st.set_color(COL_EYE_HALO_CORE)
		st.add_vertex(ctr)
		st.set_normal(n)
		st.set_color(COL_EYE_HALO_MID)
		st.add_vertex(m1)
		st.set_normal(n)
		st.set_color(COL_EYE_HALO_MID)
		st.add_vertex(m0)

		st.set_normal(n)
		st.set_color(COL_EYE_HALO_MID)
		st.add_vertex(m0)
		st.set_normal(n)
		st.set_color(COL_EYE_HALO_MID)
		st.add_vertex(m1)
		st.set_normal(n)
		st.set_color(COL_EYE_HALO_RIM)
		st.add_vertex(o1)

		st.set_normal(n)
		st.set_color(COL_EYE_HALO_MID)
		st.add_vertex(m0)
		st.set_normal(n)
		st.set_color(COL_EYE_HALO_RIM)
		st.add_vertex(o1)
		st.set_normal(n)
		st.set_color(COL_EYE_HALO_RIM)
		st.add_vertex(o0)

	return st.commit()


static func _emit_eye_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_emit_eye_tri(st, a, b, c, ref_center, ca, cb, cc)
	_emit_eye_tri(st, a, c, d, ref_center, ca, cc, cd)


static func _emit_eye_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
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


func _build_crown_mantle_mesh() -> ArrayMesh:
	var radial := 24
	var lat_rows := 10
	var grid: Array = []
	var col_grid: Array = []

	for j in lat_rows:
		var v := float(j) / float(lat_rows - 1)  # 0 = deep skirt, 1 = dorsal apex
		var y := lerpf(-1.75, 1.85, pow(v, 0.92))
		# Broad underwater skirt -> wide armored brow cheeks -> tapered cranial crest.
		var lat_r := lerpf(1.12, 0.04, pow(v, 1.55)) * (0.90 + 0.22 * sin(v * PI))
		var ring_pts: Array[Vector3] = []
		var ring_cols: Array[Color] = []

		for k in radial:
			var a := float(k) / float(radial) * TAU
			var ca := cos(a)
			var sa := sin(a)
			# Elongated cephalopod cranium: narrower fierce prow (-Z), swept mantle tail (+Z).
			var rx := 2.18 * lat_r * (0.86 if sa < 0.0 else 1.05)
			var rz := (2.68 if sa < 0.0 else 3.05) * lat_r
			var px := ca * rx
			var pz := sa * rz
			var py := y

			# Overhanging armored supraorbital brow hoods above the eye sockets.
			var brow_x := exp(-pow((absf(ca) - 0.78) / 0.24, 2.0))
			var brow_z := exp(-pow((sa + 0.56) / 0.24, 2.0))
			var brow_v := exp(-pow((v - 0.64) / 0.16, 2.0))
			var brow_bulge := brow_x * brow_z * brow_v
			px += signf(ca) * brow_bulge * 0.42
			py += brow_bulge * 0.22
			pz -= brow_bulge * 0.20

			# Prominent central sagittal ridge sweeping from prow to mantle tail.
			var ridge := exp(-pow(ca / 0.26, 2.0)) * smoothstep(0.25, 0.85, v)
			py += ridge * 0.34
			# Slight forward slope down toward the predatory prow.
			py -= maxf(0.0, -sa) * 0.35 * (1.0 - v * 0.5)

			ring_pts.append(Vector3(px, py, pz))

			var c := COL_HIDE_DORSAL_BASE.lerp(COL_HIDE_FLANK, clampf(absf(ca) * 0.72, 0.0, 1.0))
			c = c.lerp(COL_HIDE_DORSAL_TIP, smoothstep(0.45, 0.95, v) * 0.65)
			var mottle := 1.0 + 0.10 * sin(a * 6.0 + v * 11.0) * cos(v * 15.0 - a * 4.0)
			ring_cols.append(Color(c.r * mottle, c.g * mottle, c.b * mottle, 1.0))
		grid.append(ring_pts)
		col_grid.append(ring_cols)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_smooth_loft(st, grid, col_grid, false, true)
	return st.commit()


func _build_crown_spines_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 5 sweeping serrated dorsal crown fins seated firmly into the sagittal mantle ridge.
	var spine_specs := [
		[Vector3(0.0, 0.92, -1.35), 0.78, 0.88, 0.18],
		[Vector3(0.0, 1.48, -0.62), 1.08, 1.25, 0.24],
		[Vector3(0.0, 1.76, 0.18), 1.24, 1.48, 0.26],
		[Vector3(0.0, 1.42, 0.96), 1.02, 1.22, 0.22],
		[Vector3(0.0, 0.90, 1.68), 0.78, 0.92, 0.18],
	]
	for sp: Array in spine_specs:
		var base_p: Vector3 = sp[0]
		_append_crown_crest_fin(st, base_p, float(sp[1]), float(sp[2]), float(sp[3]))

	# Paired swept-back lateral brow horn crests framing the amber-aqua eyes.
	for sx: float in [-1.0, 1.0]:
		_append_swept_horn(
			st,
			Vector3(sx * 1.16, 0.84, -1.04),
			Vector3(sx * 1.88, 1.18, -0.10),
			Vector3(sx * 2.06, 0.96, 0.96),
			0.26
		)
	st.generate_normals()
	return st.commit()


func _build_crown_beak_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Hooked obsidian upper beak ridge jutting forward (-Z) out of the frothing ink.
	_append_beak_fang(st, Vector3(0.0, 0.44, -1.88), Vector3(0.0, 0.16, -3.16), 0.68, 0.52)
	# Flanking serrated upper & lower jaw plates embedded into the prow.
	for sx: float in [-1.0, 1.0]:
		_append_beak_fang(st, Vector3(sx * 0.54, 0.26, -1.78), Vector3(sx * 0.92, 0.04, -2.74), 0.36, 0.34)
		_append_beak_fang(st, Vector3(sx * 0.38, -0.18, -1.94), Vector3(sx * 0.64, 0.14, -2.68), 0.26, 0.24)
	st.generate_normals()
	return st.commit()


func _build_crown_veins_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sx: float in [-1.0, 1.0]:
		var pts: Array[Vector3] = [
			Vector3(sx * 1.24, 0.46, -0.58),
			Vector3(sx * 1.56, 0.50, 0.28),
			Vector3(sx * 1.30, 0.44, 1.18),
			Vector3(sx * 0.80, 0.32, 1.90),
		]
		var out_d := Vector3(sx, 0.22, 0.0).normalized()
		for i in range(pts.size() - 1):
			_append_vein_filament(st, pts[i], pts[i + 1], out_d, 0.095, 0.075)
			_append_vein_pod(st, pts[i], out_d, 0.16, 0.24, 0.10)
		_append_vein_pod(st, pts[pts.size() - 1], out_d, 0.12, 0.18, 0.08)
	st.generate_normals()
	return st.commit()


func _build_ink_pool() -> void:
	var sh := Shader.new()
	sh.code = INK_POOL_SHADER_CODE
	_ink_mat = ShaderMaterial.new()
	_ink_mat.shader = sh
	_ink_mat.render_priority = 2
	_ink_mat.set_shader_parameter(&"foam_tex", FOAM_TEX)
	_ink_mat.set_shader_parameter(&"pool_radius", INK_POOL_RADIUS)
	_ink_mat.set_shader_parameter(&"pool_alpha", 1.0)
	_ink_mat.set_shader_parameter(&"rage_pulse", 0.0)
	_ink_mat.set_shader_parameter(&"swirl_clock", 0.0)
	Sea.bind_material(_ink_mat)

	_ink_mesh = MeshInstance3D.new()
	_ink_mesh.name = "InkPool"
	_ink_mesh.mesh = _build_disc_mesh(INK_POOL_RADIUS, 36, 16)
	_ink_mesh.material_override = _ink_mat
	_ink_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ink_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var aabb_ext := INK_POOL_RADIUS + 2.0
	_ink_mesh.custom_aabb = AABB(Vector3(-aabb_ext, -12.0, -aabb_ext), Vector3(aabb_ext * 2.0, 24.0, aabb_ext * 2.0))
	add_child(_ink_mesh)


func _build_vortex_motes() -> void:
	if _vortex_mote_mesh == null:
		_vortex_mote_mesh = _build_vortex_mote_mesh()
	if _vortex_mote_mat == null:
		_vortex_mote_mat = StandardMaterial3D.new()
		_vortex_mote_mat.albedo_color = Color.WHITE
		_vortex_mote_mat.vertex_color_use_as_albedo = true
		_vortex_mote_mat.vertex_color_is_srgb = true
		_vortex_mote_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_vortex_mote_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_vortex_mote_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_vortex_mote_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_vortex_mote_mat.render_priority = 2

	_mote_angle.resize(VORTEX_MOTE_COUNT)
	_mote_radius.resize(VORTEX_MOTE_COUNT)
	_mote_height_phase.resize(VORTEX_MOTE_COUNT)
	_mote_rise_speed.resize(VORTEX_MOTE_COUNT)
	_mote_ang_speed.resize(VORTEX_MOTE_COUNT)
	_mote_scale.resize(VORTEX_MOTE_COUNT)
	_mote_twinkle_phase.resize(VORTEX_MOTE_COUNT)
	_mote_pos.resize(VORTEX_MOTE_COUNT)

	var rng := RandomNumberGenerator.new()
	rng.seed = 0x1E71A7A1
	for i in VORTEX_MOTE_COUNT:
		var frac := float(i) / float(VORTEX_MOTE_COUNT)
		_mote_angle[i] = wrapf(frac * TAU + rng.randf_range(-0.18, 0.18), -PI, PI)
		_mote_radius[i] = rng.randf_range(VORTEX_MOTE_MIN_R + 0.9, VORTEX_MOTE_MAX_R - 0.8)
		_mote_height_phase[i] = fposmod(frac * 3.0 + rng.randf_range(0.0, 0.25), 1.0)
		_mote_rise_speed[i] = rng.randf_range(0.18, 0.34)
		_mote_ang_speed[i] = rng.randf_range(0.42, 0.78)
		_mote_scale[i] = rng.randf_range(0.72, 1.38)
		_mote_twinkle_phase[i] = rng.randf() * TAU
		_mote_pos[i] = Vector3(
			cos(_mote_angle[i]) * _mote_radius[i],
			lerpf(VORTEX_MOTE_MIN_Y, VORTEX_MOTE_MAX_Y, _mote_height_phase[i]),
			sin(_mote_angle[i]) * _mote_radius[i]
		)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = false
	mm.mesh = _vortex_mote_mesh
	mm.instance_count = VORTEX_MOTE_COUNT
	for i in VORTEX_MOTE_COUNT:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_color(i, Color(0.10, 0.92, 0.94, 1.0))

	_vortex_motes_mmi = MultiMeshInstance3D.new()
	_vortex_motes_mmi.name = "VortexBiolumMotes"
	_vortex_motes_mmi.multimesh = mm
	_vortex_motes_mmi.material_override = _vortex_mote_mat
	_vortex_motes_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vortex_motes_mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_vortex_motes_mmi.visibility_range_end = VORTEX_MOTE_VISIBILITY_END
	var m_ext := VORTEX_MOTE_MAX_R + 2.5
	_vortex_motes_mmi.custom_aabb = AABB(Vector3(-m_ext, -4.0, -m_ext), Vector3(m_ext * 2.0, 14.0, m_ext * 2.0))
	add_child(_vortex_motes_mmi)


## Sculpted exact 8-tri faceted diamond octahedron spore for VortexBiolumMotes (0 primitives).
static func _build_vortex_mote_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const R_EQ := 0.14
	const R_TOP := 0.24
	var top := Vector3(0.0, R_TOP, 0.0)
	var bot := Vector3(0.0, -R_TOP, 0.0)
	var ring: Array[Vector3] = [
		Vector3(R_EQ, 0.0, 0.0),
		Vector3(0.0, 0.0, R_EQ),
		Vector3(-R_EQ, 0.0, 0.0),
		Vector3(0.0, 0.0, -R_EQ),
	]
	for k in 4:
		var nk := (k + 1) % 4
		_emit_eye_tri(st, top, ring[k], ring[nk], Vector3.ZERO, COL_MOTE_CORE, COL_MOTE_EDGE, COL_MOTE_EDGE)
		_emit_eye_tri(st, bot, ring[nk], ring[k], Vector3.ZERO, COL_MOTE_CORE, COL_MOTE_EDGE, COL_MOTE_EDGE)
	st.generate_normals()
	return st.commit()


static func _build_disc_mesh(radius: float, angular_segs: int, radial_rings: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3.ZERO
	var nrm := Vector3.UP

	# Inner fan from center to ring 1 (clockwise viewed from +Y so normal = +Y).
	var r1 := radius / float(radial_rings)
	for i in angular_segs:
		var a0 := float(i) / float(angular_segs) * TAU
		var a1 := float(i + 1) / float(angular_segs) * TAU
		var p0 := Vector3(cos(a0) * r1, 0.0, sin(a0) * r1)
		var p1 := Vector3(cos(a1) * r1, 0.0, sin(a1) * r1)
		st.set_normal(nrm); st.set_uv(Vector2(0.5, 0.5)); st.add_vertex(center)
		st.set_normal(nrm); st.set_uv(Vector2(0.5 + cos(a0) * 0.5 / float(radial_rings), 0.5 + sin(a0) * 0.5 / float(radial_rings))); st.add_vertex(p0)
		st.set_normal(nrm); st.set_uv(Vector2(0.5 + cos(a1) * 0.5 / float(radial_rings), 0.5 + sin(a1) * 0.5 / float(radial_rings))); st.add_vertex(p1)

	for r_i in range(1, radial_rings):
		var ra := radius * float(r_i) / float(radial_rings)
		var rb := radius * float(r_i + 1) / float(radial_rings)
		var fa := 0.5 * float(r_i) / float(radial_rings)
		var fb := 0.5 * float(r_i + 1) / float(radial_rings)
		for i in angular_segs:
			var a0 := float(i) / float(angular_segs) * TAU
			var a1 := float(i + 1) / float(angular_segs) * TAU
			var ca0 := cos(a0); var sa0 := sin(a0)
			var ca1 := cos(a1); var sa1 := sin(a1)
			var p00 := Vector3(ca0 * ra, 0.0, sa0 * ra)
			var p10 := Vector3(ca0 * rb, 0.0, sa0 * rb)
			var p11 := Vector3(ca1 * rb, 0.0, sa1 * rb)
			var p01 := Vector3(ca1 * ra, 0.0, sa1 * ra)
			var uv00 := Vector2(0.5 + ca0 * fa, 0.5 + sa0 * fa)
			var uv10 := Vector2(0.5 + ca0 * fb, 0.5 + sa0 * fb)
			var uv11 := Vector2(0.5 + ca1 * fb, 0.5 + sa1 * fb)
			var uv01 := Vector2(0.5 + ca1 * fa, 0.5 + sa1 * fa)
			st.set_normal(nrm); st.set_uv(uv00); st.add_vertex(p00)
			st.set_normal(nrm); st.set_uv(uv10); st.add_vertex(p10)
			st.set_normal(nrm); st.set_uv(uv11); st.add_vertex(p11)
			st.set_normal(nrm); st.set_uv(uv00); st.add_vertex(p00)
			st.set_normal(nrm); st.set_uv(uv11); st.add_vertex(p11)
			st.set_normal(nrm); st.set_uv(uv01); st.add_vertex(p01)

	return st.commit()


# ------------------------------------------------------------------ spray VFX

func _build_spray_texture() -> ImageTexture:
	var sz := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for py in sz:
		var vy := ((float(py) + 0.5) / float(sz)) * 2.0 - 1.0
		for px in sz:
			var vx := ((float(px) + 0.5) / float(sz)) * 2.0 - 1.0
			var dist := sqrt(vx * vx + vy * vy)
			if dist >= 1.0:
				img.set_pixel(px, py, Color(0.95, 0.99, 1.0, 0.0))
				continue
			var radial := smoothstep(1.0, 0.06, dist)
			# Soft organic sea-mist breakup so spray puffs never look like flat geometric circles.
			var wisp := 0.74 + 0.24 * sin(vx * 4.4 + vy * 3.2) * cos(vy * 5.0 - vx * 2.9)
			wisp += 0.12 * sin((vx * vx - vy * vy) * 5.6 + vx * 2.4)
			var alpha := clampf(pow(radial, 1.42) * clampf(wisp, 0.36, 1.14), 0.0, 0.94)
			var bright := lerpf(0.90, 1.0, radial)
			img.set_pixel(px, py, Color(bright * 0.96, bright * 0.99, 1.0, alpha))
	return ImageTexture.create_from_image(img)


func _spawn_spray_burst(world_pos: Vector3, intensity: float = 1.0, amount: int = 40) -> void:
	if _spray_mat == null or not is_inside_tree():
		return
	if _active_bursts.size() >= MAX_ACTIVE_BURSTS:
		var oldest := _active_bursts[0]
		_active_bursts.remove_at(0)
		if oldest != null and is_instance_valid(oldest):
			_release_spray_burst_refs(oldest)
			oldest.queue_free()

	var p := GPUParticles3D.new()
	p.name = "LeviathanSprayBurst"
	p.one_shot = true
	p.explosiveness = 0.88
	p.amount = maxi(amount, 12)
	p.lifetime = lerpf(0.95, 1.35, clampf(intensity - 0.6, 0.0, 1.0))
	p.local_coords = false
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-22.0, -8.0, -22.0), Vector3(44.0, 32.0, 44.0))

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	proc.emission_ring_axis = Vector3.UP
	proc.emission_ring_height = 0.35
	proc.emission_ring_radius = 0.85 * intensity
	proc.emission_ring_inner_radius = 0.15 * intensity
	proc.direction = Vector3.UP
	proc.spread = 38.0
	proc.initial_velocity_min = 5.2 * intensity
	proc.initial_velocity_max = 12.6 * intensity
	proc.damping_min = 0.85
	proc.damping_max = 1.85
	proc.gravity = Vector3(0.0, -16.2, 0.0)
	proc.scale_min = 0.68
	proc.scale_max = 1.48
	proc.scale_curve = _make_scale_curve([Vector2(0.0, 0.52), Vector2(0.30, 1.15), Vector2(1.0, 1.65)])
	proc.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.14, 0.58, 1.0]),
		PackedColorArray([
			Color(0.96, 1.0, 1.0, 0.0),
			Color(0.90, 0.98, 1.0, 0.86),
			Color(0.76, 0.94, 0.98, 0.48),
			Color(0.68, 0.88, 0.94, 0.0),
		])
	)
	p.process_material = proc

	p.draw_pass_1 = _build_quad_card_mesh(Vector2(0.95 * intensity, 1.65 * intensity), _spray_mat)

	add_child(p)
	p.global_position = world_pos + Vector3(0.0, 0.15, 0.0)
	p.emitting = true
	_active_bursts.append(p)
	p.finished.connect(_on_spray_burst_finished.bind(p))


func _on_spray_burst_finished(p: GPUParticles3D) -> void:
	var idx := _active_bursts.find(p)
	if idx >= 0:
		_active_bursts.remove_at(idx)
	if p != null and is_instance_valid(p):
		_release_spray_burst_refs(p)
		p.queue_free()


static func _release_spray_burst_refs(p: GPUParticles3D) -> void:
	if p == null or not is_instance_valid(p):
		return
	p.emitting = false
	p.visible = false
	if p.draw_pass_1 is ArrayMesh:
		var am := p.draw_pass_1 as ArrayMesh
		if am.get_surface_count() > 0:
			am.surface_set_material(0, null)
	if p.process_material is ParticleProcessMaterial:
		var pm := p.process_material as ParticleProcessMaterial
		pm.color_ramp = null
		pm.scale_curve = null
	p.draw_pass_1 = null
	p.process_material = null


static func _build_quad_card_mesh(size: Vector2, mat: Material = null) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := size.x * 0.5
	var hh := size.y * 0.5
	const NORM := Vector3(0.0, 0.0, 1.0)
	var v0 := Vector3(-hw, -hh, 0.0)
	var v1 := Vector3(hw, -hh, 0.0)
	var v2 := Vector3(hw, hh, 0.0)
	var v3 := Vector3(-hw, hh, 0.0)
	st.set_normal(NORM); st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(v0)
	st.set_normal(NORM); st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(v2)
	st.set_normal(NORM); st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(v1)
	st.set_normal(NORM); st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(v0)
	st.set_normal(NORM); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(v3)
	st.set_normal(NORM); st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(v2)
	var mesh := st.commit()
	if mat != null:
		mesh.surface_set_material(0, mat)
	return mesh


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


# ------------------------------------------------------------------ geometry primitives

## Emit a closed smooth loft from ring position/color grids with seamless 360-deg vertex normals.
static func _emit_smooth_loft(
	st: SurfaceTool,
	grid: Array,
	col_grid: Array,
	close_bottom: bool,
	close_top: bool
) -> void:
	var ring_count := grid.size()
	if ring_count < 2:
		return
	var radial := (grid[0] as Array).size()
	var nrm_grid: Array = []

	for r in ring_count:
		var row: Array = grid[r]
		var n_row: Array[Vector3] = []
		for k in radial:
			var prev_k := (k - 1 + radial) % radial
			var next_k := (k + 1) % radial
			var t_ang: Vector3 = (row[next_k] as Vector3) - (row[prev_k] as Vector3)
			var t_ax: Vector3
			if r == 0:
				t_ax = (grid[1][k] as Vector3) - (row[k] as Vector3)
			elif r == ring_count - 1:
				t_ax = (row[k] as Vector3) - (grid[r - 1][k] as Vector3)
			else:
				t_ax = (grid[r + 1][k] as Vector3) - (grid[r - 1][k] as Vector3)
			var n := t_ax.cross(t_ang)
			if n.length_squared() < 1e-8:
				var p: Vector3 = row[k]
				n = Vector3(p.x, 0.25 if r == ring_count - 1 else -0.25, p.z)
			n_row.append(n.normalized())
		nrm_grid.append(n_row)

	for r in range(ring_count - 1):
		var r0: Array = grid[r]
		var r1: Array = grid[r + 1]
		var n0: Array = nrm_grid[r]
		var n1: Array = nrm_grid[r + 1]
		var c0: Array = col_grid[r]
		var c1: Array = col_grid[r + 1]
		var v0 := float(r) / float(ring_count - 1)
		var v1 := float(r + 1) / float(ring_count - 1)
		for k in radial:
			var nk := (k + 1) % radial
			var u0 := float(k) / float(radial)
			var u1 := float(k + 1) / float(radial)
			# CW viewed from outside: (p11, p10, p00) and (p11, p00, p01).
			_emit_tri_vc(
				st,
				r1[nk], n1[nk], c1[nk], Vector2(u1, v1),
				r1[k], n1[k], c1[k], Vector2(u0, v1),
				r0[k], n0[k], c0[k], Vector2(u0, v0)
			)
			_emit_tri_vc(
				st,
				r1[nk], n1[nk], c1[nk], Vector2(u1, v1),
				r0[k], n0[k], c0[k], Vector2(u0, v0),
				r0[nk], n0[nk], c0[nk], Vector2(u1, v0)
			)

	if close_bottom:
		var first: Array = grid[0]
		var fc: Array = col_grid[0]
		var ctr := Vector3.ZERO
		for p: Vector3 in first:
			ctr += p
		ctr /= float(radial)
		var cc: Color = fc[0]
		for k in radial:
			var nk := (k + 1) % radial
			_emit_tri_vc(
				st,
				ctr, Vector3.DOWN, cc, Vector2(0.5, 0.5),
				first[nk], Vector3.DOWN, fc[nk], Vector2(1.0, 0.0),
				first[k], Vector3.DOWN, fc[k], Vector2(0.0, 0.0)
			)

	if close_top:
		var last: Array = grid[ring_count - 1]
		var lc: Array = col_grid[ring_count - 1]
		var ctr := Vector3.ZERO
		for p: Vector3 in last:
			ctr += p
		ctr /= float(radial)
		var cc: Color = lc[0]
		for k in radial:
			var nk := (k + 1) % radial
			_emit_tri_vc(
				st,
				ctr, Vector3.UP, cc, Vector2(0.5, 0.5),
				last[k], Vector3.UP, lc[k], Vector2(0.0, 1.0),
				last[nk], Vector3.UP, lc[nk], Vector2(1.0, 1.0)
			)


static func _emit_tri_vc(
	st: SurfaceTool,
	p0: Vector3, n0: Vector3, c0: Color, uv0: Vector2,
	p1: Vector3, n1: Vector3, c1: Color, uv1: Vector2,
	p2: Vector3, n2: Vector3, c2: Color, uv2: Vector2
) -> void:
	st.set_normal(n0); st.set_color(c0); st.set_uv(uv0); st.add_vertex(p0)
	st.set_normal(n1); st.set_color(c1); st.set_uv(uv1); st.add_vertex(p1)
	st.set_normal(n2); st.set_color(c2); st.set_uv(uv2); st.add_vertex(p2)


static func _emit_flat_tri(st: SurfaceTool, a: Vector3, ca: Color, b: Vector3, cb: Color, c: Vector3, cc: Color) -> void:
	st.set_color(ca); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(a)
	st.set_color(cb); st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(b)
	st.set_color(cc); st.set_uv(Vector2(0.5, 1.0)); st.add_vertex(c)


## Sculpt a chunky beveled swept-back dorsal spine fin along +Z of a tentacle segment.
static func _append_dorsal_fin(st: SurfaceTool, root_pos: Vector3, fin_h: float, depth: float, half_w: float) -> void:
	var bot_l := root_pos + Vector3(-half_w, -fin_h * 0.48, -depth * 0.16)
	var bot_r := root_pos + Vector3(half_w, -fin_h * 0.48, -depth * 0.16)
	var top_l := root_pos + Vector3(-half_w * 0.72, fin_h * 0.52, -depth * 0.12)
	var top_r := root_pos + Vector3(half_w * 0.72, fin_h * 0.52, -depth * 0.12)
	var mid_crest := root_pos + Vector3(0.0, fin_h * 0.18, depth * 0.72)
	var tip := root_pos + Vector3(0.0, -fin_h * 0.22, depth)

	# Right (+X) faces -- CW viewed from +X.
	_emit_flat_tri(st, top_r, COL_FIN_ROOT, bot_r, COL_FIN_ROOT, mid_crest, COL_FIN_EDGE)
	_emit_flat_tri(st, mid_crest, COL_FIN_EDGE, bot_r, COL_FIN_ROOT, tip, COL_FIN_EDGE)
	# Left (-X) faces -- CW viewed from -X.
	_emit_flat_tri(st, top_l, COL_FIN_ROOT, mid_crest, COL_FIN_EDGE, bot_l, COL_FIN_ROOT)
	_emit_flat_tri(st, mid_crest, COL_FIN_EDGE, tip, COL_FIN_EDGE, bot_l, COL_FIN_ROOT)
	# Upper leading bevel -- CW viewed from +Y/+Z.
	_emit_flat_tri(st, top_l, COL_FIN_ROOT, top_r, COL_FIN_ROOT, mid_crest, COL_FIN_EDGE)
	# Lower trailing bevel -- CW viewed from -Y/+Z.
	_emit_flat_tri(st, bot_l, COL_FIN_ROOT, tip, COL_FIN_EDGE, bot_r, COL_FIN_ROOT)


## Sculpt a dorsal crest blade rising along +Y and sweeping back along +Z on the Abyssal Crown.
static func _append_crown_crest_fin(st: SurfaceTool, base_pos: Vector3, height: float, back_len: float, half_w: float) -> void:
	var fl := base_pos + Vector3(-half_w, -0.18, -back_len * 0.36)
	var fr := base_pos + Vector3(half_w, -0.18, -back_len * 0.36)
	var bl := base_pos + Vector3(-half_w * 0.75, -0.22, back_len * 0.58)
	var br := base_pos + Vector3(half_w * 0.75, -0.22, back_len * 0.58)
	var apex := base_pos + Vector3(0.0, height, back_len * 0.28)
	var spur := base_pos + Vector3(0.0, height * 0.42, back_len * 0.82)

	# Right (+X) side -- CW viewed from +X.
	_emit_flat_tri(st, apex, COL_FIN_EDGE, fr, COL_FIN_ROOT, br, COL_FIN_ROOT)
	_emit_flat_tri(st, apex, COL_FIN_EDGE, br, COL_FIN_ROOT, spur, COL_FIN_EDGE)
	# Left (-X) side -- CW viewed from -X.
	_emit_flat_tri(st, apex, COL_FIN_EDGE, bl, COL_FIN_ROOT, fl, COL_FIN_ROOT)
	_emit_flat_tri(st, apex, COL_FIN_EDGE, spur, COL_FIN_EDGE, bl, COL_FIN_ROOT)
	# Leading arch (-Z/+Y).
	_emit_flat_tri(st, fl, COL_FIN_ROOT, fr, COL_FIN_ROOT, apex, COL_FIN_EDGE)
	# Trailing edge (+Z/-Y).
	_emit_flat_tri(st, spur, COL_FIN_EDGE, br, COL_FIN_ROOT, bl, COL_FIN_ROOT)


## Sculpt a curved armored lateral horn sweeping from `p0 -> p1 -> p2`.
static func _append_swept_horn(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, base_r: float) -> void:
	var pts: Array[Vector3] = [p0, p1, p2]
	var rads: PackedFloat32Array = PackedFloat32Array([base_r, base_r * 0.56, 0.03])
	var cols: Array[Color] = [COL_FIN_ROOT, COL_HIDE_FLANK, COL_FIN_EDGE]
	var segs := 6
	var rings: Array = []
	for i in 3:
		var tang := (pts[mini(i + 1, 2)] - pts[maxi(i - 1, 0)]).normalized()
		var ref := Vector3.UP if absf(tang.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var bx := tang.cross(ref).normalized()
		var bz := bx.cross(tang).normalized()
		var ring: Array[Vector3] = []
		for k in segs:
			var a := float(k) / float(segs) * TAU
			ring.append(pts[i] + (bx * cos(a) + bz * sin(a)) * rads[i])
		rings.append(ring)
	for r in 2:
		var r0: Array = rings[r]
		var r1: Array = rings[r + 1]
		var c0: Color = cols[r]
		var c1: Color = cols[r + 1]
		for k in segs:
			var nk := (k + 1) % segs
			_emit_flat_tri(st, r1[nk], c1, r1[k], c1, r0[k], c0)
			_emit_flat_tri(st, r1[nk], c1, r0[k], c0, r0[nk], c0)
	var tip_ring: Array = rings[2]
	for k in segs:
		var nk := (k + 1) % segs
		_emit_flat_tri(st, p2, cols[2], tip_ring[k], cols[2], tip_ring[nk], cols[2])


## Sculpt a sharp hooked chitinous beak fang pointing from `base_p` to `tip_p`.
static func _append_beak_fang(st: SurfaceTool, base_p: Vector3, tip_p: Vector3, half_w: float, half_h: float) -> void:
	var top := base_p + Vector3(0.0, half_h, 0.0)
	var bot := base_p + Vector3(0.0, -half_h, 0.0)
	var right := base_p + Vector3(half_w, 0.0, 0.0)
	var left := base_p + Vector3(-half_w, 0.0, 0.0)
	# Pointing toward -Z: CW viewed from outside.
	_emit_flat_tri(st, tip_p, COL_BEAK_EDGE, right, COL_BEAK_DARK, top, COL_BEAK_DARK)
	_emit_flat_tri(st, tip_p, COL_BEAK_EDGE, top, COL_BEAK_DARK, left, COL_BEAK_DARK)
	_emit_flat_tri(st, tip_p, COL_BEAK_EDGE, left, COL_BEAK_DARK, bot, COL_BEAK_DARK)
	_emit_flat_tri(st, tip_p, COL_BEAK_EDGE, bot, COL_BEAK_DARK, right, COL_BEAK_DARK)
	_emit_flat_tri(st, top, COL_BEAK_DARK, right, COL_BEAK_DARK, bot, COL_BEAK_DARK)
	_emit_flat_tri(st, top, COL_BEAK_DARK, bot, COL_BEAK_DARK, left, COL_BEAK_DARK)


## Sculpt a cupped cephalopod sucker disc oriented along `out_dir` with lavender-coral rim & recessed cup.
static func _append_sucker_cup(st: SurfaceTool, origin: Vector3, out_dir: Vector3, rad: float, segs: int) -> void:
	var by := out_dir.normalized()
	var bz := Vector3.UP.cross(by)
	if bz.length_squared() < 1e-6:
		bz = Vector3.RIGHT.cross(by)
	bz = bz.normalized()
	var bx := by.cross(bz).normalized()

	var prof_r: PackedFloat32Array = PackedFloat32Array([
		rad * 0.46,
		rad * 0.64,
		rad * 1.06,
		rad * 0.90,
		rad * 0.56,
		rad * 0.03,
	])
	var prof_h: PackedFloat32Array = PackedFloat32Array([
		-rad * 0.06,
		rad * 0.22,
		rad * 0.46,
		rad * 0.56,
		rad * 0.34,
		rad * 0.25,
	])
	var prof_c: Array[Color] = [
		COL_HIDE_VENTRAL,
		COL_SUCKER_STALK,
		COL_SUCKER_RIM,
		COL_SUCKER_LIP,
		COL_SUCKER_CUP,
		COL_SUCKER_CUP * 0.72,
	]

	for j in range(prof_r.size() - 1):
		var r0 := prof_r[j]
		var r1 := prof_r[j + 1]
		var h0 := prof_h[j]
		var h1 := prof_h[j + 1]
		var c0 := prof_c[j]
		var c1 := prof_c[j + 1]
		for k in segs:
			var a0 := float(k) / float(segs) * TAU
			var a1 := float(k + 1) / float(segs) * TAU
			var d0 := bx * cos(a0) + bz * sin(a0)
			var d1 := bx * cos(a1) + bz * sin(a1)
			var p00 := origin + d0 * r0 + by * h0
			var p01 := origin + d1 * r0 + by * h0
			var p10 := origin + d0 * r1 + by * h1
			var p11 := origin + d1 * r1 + by * h1
			_emit_flat_tri(st, p11, c1, p10, c1, p00, c0)
			_emit_flat_tri(st, p11, c1, p00, c0, p01, c0)


## Sculpt a beveled diamond-lens bioluminescent vein node hugging a flank along `out_dir`.
static func _append_vein_pod(st: SurfaceTool, origin: Vector3, out_dir: Vector3, half_w: float, half_h: float, height: float) -> void:
	var by := out_dir.normalized()
	var bz := Vector3.UP.cross(by)
	if bz.length_squared() < 1e-6:
		bz = Vector3.RIGHT.cross(by)
	bz = bz.normalized()
	var bx := by.cross(bz).normalized()  # Vertical-ish tangent

	var apex := origin + by * height
	var ring: Array[Vector3] = [
		origin + bx * half_h - by * 0.02,
		origin + bz * half_w - by * 0.02,
		origin - bx * half_h - by * 0.02,
		origin - bz * half_w - by * 0.02,
	]
	for k in 4:
		var nk := (k + 1) % 4
		_emit_flat_tri(st, apex, Color.WHITE, ring[k], Color.WHITE, ring[nk], Color.WHITE)


## Sculpt a thin raised bioluminescent vein ridge connecting `p0` to `p1`.
static func _append_vein_filament(st: SurfaceTool, p0: Vector3, p1: Vector3, out_dir: Vector3, w0: float, w1: float) -> void:
	var by := out_dir.normalized()
	var seg_d := p1 - p0
	if seg_d.length_squared() < 1e-6:
		return
	var side := seg_d.normalized().cross(by).normalized()
	var a0 := p0 - side * w0
	var b0 := p0 + side * w0
	var c0 := p0 + by * (w0 * 1.15)
	var a1 := p1 - side * w1
	var b1 := p1 + side * w1
	var c1 := p1 + by * (w1 * 1.15)
	_emit_flat_tri(st, c1, Color.WHITE, c0, Color.WHITE, a0, Color.WHITE)
	_emit_flat_tri(st, c1, Color.WHITE, a0, Color.WHITE, a1, Color.WHITE)
	_emit_flat_tri(st, b1, Color.WHITE, b0, Color.WHITE, c0, Color.WHITE)
	_emit_flat_tri(st, b1, Color.WHITE, c0, Color.WHITE, c1, Color.WHITE)
