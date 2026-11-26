class_name ShipDamageVisuals
extends Node3D
## Sculpted physical ship combat damage, animated bilge pump, and cannon fuse visuals.
##
## Features 100% sculpted flat-faceted `SurfaceTool` `ArrayMesh` geometry (zero raw
## `PrimitiveMesh`es) using WeakRef-cached shared ship BC7 PBR normal/roughness maps
## (object-space triplanar mapping, zero extra VRAM) and ref-counted leak-free teardown.
##
## Mounted visuals:
## 1. Animated Bilge Pump (`BilgePumpRoot`) seated cleanly at `Station_Bilge`:
##    - Seasoned-oak framed stand plinth & coopered barrel casing (`_pump_oak_mi`)
##    - Heavy forged-iron pump cylinder, bolted flange collar & fulcrum yoke (`_pump_iron_mi`)
##    - Turned brass discharge spout trough & cap finial (`_pump_brass_mi`)
##    - Articulated `_pump_handle_pivot` (forged-iron clevis/rod + oak lever + brass pommel)
##    - Translucent sculpted arched water-stream spout plume (`_pump_water_mi`)
## 2. Reusable Chainshot Spar Splinter & Tattered Canvas Shred Burst Pool (`SPLINTER_POOL_SIZE`)
##    with zero per-hit node/mesh allocations.
## 3. Sculpted Multi-Pointed Cannon Priming Fuse Spark Star (`_fuse_spark_mi`).

const SLOOP_BILGE_POS := Vector3(0.0, -0.85, -2.1)
const BRIG_BILGE_POS := Vector3(0.0, -0.95, 2.0)

const PUMP_HOLD_TIME := 0.55
const PUMP_CYCLE_SPEED := 10.5
const PUMP_MAX_ANGLE := 0.50
const SPLINTER_POOL_SIZE := 14
const SPLINTER_WOOD_COUNT := 9
const SPLINTER_BURST_DURATION := 1.45
const FUSE_FLASH_DURATION := 0.24

const TEX_OAK_NORMAL := "res://assets/generated/textures/ship_oak_normal.png"
const TEX_OAK_ROUGH := "res://assets/generated/textures/ship_oak_rough.png"
const TEX_IRON_NORMAL := "res://assets/generated/textures/ship_iron_normal.png"
const TEX_IRON_ROUGH := "res://assets/generated/textures/ship_iron_rough.png"
const TEX_BRASS_NORMAL := "res://assets/generated/textures/ship_brass_normal.png"
const TEX_BRASS_ROUGH := "res://assets/generated/textures/ship_brass_rough.png"
const TEX_CLOTH_NORMAL := "res://assets/generated/textures/ship_cloth_normal.png"
const TEX_ROPE_ROUGH := "res://assets/generated/textures/ship_rope_rough.png"

# sRGB-calibrated painterly nautical palette (seasoned oak, forged iron, brass, sailcloth, splash, spark).
const COL_OAK_HI := Color(0.58, 0.40, 0.23)
const COL_OAK_MID := Color(0.42, 0.28, 0.15)
const COL_OAK_LO := Color(0.24, 0.15, 0.08)

const COL_SPLINTER_HI := Color(0.76, 0.58, 0.34)
const COL_SPLINTER_MID := Color(0.54, 0.37, 0.20)
const COL_SPLINTER_LO := Color(0.30, 0.19, 0.10)

const COL_IRON_HI := Color(0.32, 0.34, 0.38)
const COL_IRON_MID := Color(0.18, 0.19, 0.23)
const COL_IRON_LO := Color(0.09, 0.10, 0.13)

const COL_BRASS_HI := Color(0.96, 0.79, 0.32)
const COL_BRASS_MID := Color(0.76, 0.57, 0.19)
const COL_BRASS_LO := Color(0.44, 0.31, 0.10)

const COL_CANVAS_HI := Color(0.90, 0.85, 0.73)
const COL_CANVAS_MID := Color(0.74, 0.67, 0.54)
const COL_CANVAS_LO := Color(0.50, 0.43, 0.34)

const COL_WATER_FOAM := Color(0.86, 0.98, 0.99)
const COL_WATER_MID := Color(0.38, 0.84, 0.88)
const COL_WATER_DEEP := Color(0.16, 0.60, 0.72)

const COL_SPARK_CORE := Color(1.0, 0.97, 0.80)
const COL_SPARK_GOLD := Color(1.0, 0.74, 0.20)
const COL_SPARK_EMBER := Color(0.96, 0.38, 0.08)

## Visual scale matched to the owning ship's hull_scale.
@export var visual_scale: float = 1.0

## Owning ship (`Ship` / `RigidBody3D`).
var ship: Node3D = null

# Scene hierarchy refs
var _pump_root: Node3D = null
var _pump_oak_mi: MeshInstance3D = null
var _pump_iron_mi: MeshInstance3D = null
var _pump_brass_mi: MeshInstance3D = null
var _pump_handle_pivot: Node3D = null
var _pump_handle_iron_mi: MeshInstance3D = null
var _pump_handle_oak_mi: MeshInstance3D = null
var _pump_handle_brass_mi: MeshInstance3D = null
var _pump_water_mi: MeshInstance3D = null

var _splinter_root: Node3D = null
var _splinter_pool: Array[Dictionary] = []
var _fuse_spark_mi: MeshInstance3D = null
var _all_mesh_instances: Array[MeshInstance3D] = []

# Runtime animation state
var _pump_active_timer: float = 0.0
var _pump_phase: float = 0.0
var _pump_handle_angle: float = 0.0
var _pump_stream_strength: float = 0.0

var _splinter_burst_timer: float = 0.0
var _fuse_flash_timer: float = 0.0
var _fuse_spin: float = 0.0

# Ref-counted static sculpted ArrayMesh & shared PBR material caches (zero ObjectDB leaks).
static var _active_instances: int = 0
static var _pbr_tex_cache: Dictionary = {}  # String path -> WeakRef(Texture2D)
static var _pump_oak_mesh: ArrayMesh = null
static var _pump_iron_mesh: ArrayMesh = null
static var _pump_brass_mesh: ArrayMesh = null
static var _pump_handle_iron_mesh: ArrayMesh = null
static var _pump_handle_oak_mesh: ArrayMesh = null
static var _pump_handle_brass_mesh: ArrayMesh = null
static var _pump_water_mesh: ArrayMesh = null
static var _splinter_mesh: ArrayMesh = null
static var _canvas_shred_mesh: ArrayMesh = null
static var _fuse_spark_mesh: ArrayMesh = null
static var _oak_mat: StandardMaterial3D = null
static var _iron_mat: StandardMaterial3D = null
static var _brass_mat: StandardMaterial3D = null
static var _canvas_mat: StandardMaterial3D = null
static var _water_mat: StandardMaterial3D = null
static var _fuse_mat: StandardMaterial3D = null


## Release all statically cached sculpted ArrayMeshes, PBR materials, and WeakRef textures cleanly.
static func clear_shared_cache() -> void:
	for mat: StandardMaterial3D in [_oak_mat, _iron_mat, _brass_mat, _canvas_mat, _water_mat, _fuse_mat]:
		if mat != null:
			mat.normal_texture = null
			mat.roughness_texture = null
	_pump_oak_mesh = null
	_pump_iron_mesh = null
	_pump_brass_mesh = null
	_pump_handle_iron_mesh = null
	_pump_handle_oak_mesh = null
	_pump_handle_brass_mesh = null
	_pump_water_mesh = null
	_splinter_mesh = null
	_canvas_shred_mesh = null
	_fuse_spark_mesh = null
	_oak_mat = null
	_iron_mat = null
	_brass_mat = null
	_canvas_mat = null
	_water_mat = null
	_fuse_mat = null
	_pbr_tex_cache.clear()


func _enter_tree() -> void:
	_active_instances += 1


func _ready() -> void:
	_ensure_shared_assets()
	_build_visuals()
	_sync_pump_visuals()


func _exit_tree() -> void:
	for mi: MeshInstance3D in _all_mesh_instances:
		if mi != null and is_instance_valid(mi):
			mi.material_override = null
			mi.mesh = null
	_all_mesh_instances.clear()
	_splinter_pool.clear()
	_pump_oak_mi = null
	_pump_iron_mi = null
	_pump_brass_mi = null
	_pump_handle_iron_mi = null
	_pump_handle_oak_mi = null
	_pump_handle_brass_mi = null
	_pump_water_mi = null
	_pump_handle_pivot = null
	_pump_root = null
	_splinter_root = null
	_fuse_spark_mi = null
	ship = null
	_active_instances = maxi(0, _active_instances - 1)
	if _active_instances == 0:
		clear_shared_cache()


# ==============================================================================
# Public API & Introspection
# ==============================================================================

## Energize the bilge pump rocker handle and overboard water spout plume.
func trigger_pump_stroke() -> void:
	var was_idle := _pump_active_timer <= 0.01
	_pump_active_timer = PUMP_HOLD_TIME
	_pump_stream_strength = maxf(_pump_stream_strength, 0.72)
	if was_idle:
		_pump_phase += 0.55
		_pump_handle_angle = sin(_pump_phase) * PUMP_MAX_ANGLE * _pump_stream_strength
	_sync_pump_visuals()


## Launch a reusable pool of sculpted wooden spar splinters & tattered canvas shreds from `origin_local`.
func trigger_sail_damage_burst(origin_local: Vector3) -> void:
	_splinter_burst_timer = SPLINTER_BURST_DURATION
	var sc := maxf(visual_scale, 0.5)
	for i in _splinter_pool.size():
		var entry: Dictionary = _splinter_pool[i]
		var mi: MeshInstance3D = entry["node"] as MeshInstance3D
		if mi == null or not is_instance_valid(mi):
			continue
		var is_wood := bool(entry["is_wood"])
		var frac := float(i) / maxf(float(_splinter_pool.size()), 1.0)
		var az := frac * TAU * 1.6180339 + 0.35
		var span_x := ((frac * 2.0) - 1.0) * 1.55 * sc
		var spread_y := (0.25 if (i % 2 == 0) else -0.22) * sc
		mi.position = origin_local + Vector3(span_x, spread_y, ((float(i % 3) - 1.0) * 0.25) * sc)
		mi.rotation = Vector3(az * 0.7, az, az * 0.45)
		var base_sc: Vector3 = entry["base_scale"] as Vector3
		mi.scale = base_sc * sc
		mi.visible = true

		var radial_spd := (3.4 + float(i % 4) * 0.85) if is_wood else (2.4 + float(i % 3) * 0.65)
		var lift_spd := (2.6 + float(i % 3) * 0.95) if is_wood else (1.9 + float(i % 2) * 0.75)
		entry["vel"] = Vector3(cos(az) * radial_spd, lift_spd, sin(az) * radial_spd)
		entry["ang_vel"] = Vector3(
			(4.8 if (i % 2 == 0) else -5.4) + float(i % 3) * 1.2,
			(6.2 if (i % 3 == 0) else -4.6),
			(3.9 if (i % 2 == 1) else -6.1)
		)
		entry["age"] = 0.0
		entry["lifetime"] = SPLINTER_BURST_DURATION * (0.78 + 0.22 * float((i * 5) % 4) / 3.0)


## Briefly flare the sculpted multi-pointed fiery amber-gold priming fuse spark at `local_pos`.
func trigger_cannon_fuse_flash(local_pos: Vector3) -> void:
	_fuse_flash_timer = FUSE_FLASH_DURATION
	_fuse_spin = fmod(_fuse_spin + 1.1, TAU)
	if _fuse_spark_mi != null and is_instance_valid(_fuse_spark_mi):
		_fuse_spark_mi.position = local_pos
		_fuse_spark_mi.rotation = Vector3(_fuse_spin * 0.5, _fuse_spin, _fuse_spin * 0.35)
		_fuse_spark_mi.scale = Vector3.ONE * (1.15 * maxf(visual_scale, 0.5))
		_fuse_spark_mi.transparency = 0.0
		_fuse_spark_mi.visible = true


## Total sculpted triangle count across all mounted MeshInstance3D nodes in this ShipDamageVisuals.
func get_triangle_count() -> int:
	var tris := 0
	for mi: MeshInstance3D in _all_mesh_instances:
		if mi != null and is_instance_valid(mi) and mi.mesh is ArrayMesh:
			var am := mi.mesh as ArrayMesh
			for si in am.get_surface_count():
				var ilen := am.surface_get_array_index_len(si)
				if ilen > 0:
					tris += floori(float(ilen) / 3.0)
				else:
					tris += floori(float(am.surface_get_array_len(si)) / 3.0)
	return tris


## Current rocking pitch angle (radians) of the articulated bilge pump handle pivot.
func get_pump_handle_angle() -> float:
	return _pump_handle_angle


## True while the sculpted arched bilge pump water plume is actively streaming.
func is_pump_streaming() -> bool:
	return _pump_stream_strength > 0.08 and _pump_water_mi != null \
		and is_instance_valid(_pump_water_mi) and _pump_water_mi.visible


## True while the chainshot wooden spar splinter & tattered canvas burst is actively tumbling.
func is_splinter_burst_active() -> bool:
	return _splinter_burst_timer > 0.0


## True while the sculpted cannon priming fuse spark star is flaring.
func is_fuse_flash_active() -> bool:
	return _fuse_flash_timer > 0.0 and _fuse_spark_mi != null \
		and is_instance_valid(_fuse_spark_mi) and _fuse_spark_mi.visible


# ==============================================================================
# Per-Frame Animation Update
# ==============================================================================

func _process(delta: float) -> void:
	step(delta)


## Advance pump lever rocking, water plume surge/fade, splinter tumbling, and fuse flash.
func step(delta: float) -> void:
	if delta <= 0.0:
		return

	# 1. Bilge pump handle oscillation & overboard water plume surge/fade.
	if _pump_active_timer > 0.0:
		_pump_active_timer = maxf(0.0, _pump_active_timer - delta)
		_pump_stream_strength = move_toward(_pump_stream_strength, 1.0, delta * 5.2)
		_pump_phase = fmod(_pump_phase + PUMP_CYCLE_SPEED * delta, TAU * 100.0)
		var stroke_env := clampf(_pump_stream_strength, 0.25, 1.0)
		_pump_handle_angle = sin(_pump_phase) * PUMP_MAX_ANGLE * stroke_env
		_sync_pump_visuals()
	elif _pump_stream_strength > 0.0 or absf(_pump_handle_angle) > 0.001:
		_pump_stream_strength = move_toward(_pump_stream_strength, 0.0, delta * 2.8)
		_pump_handle_angle = move_toward(_pump_handle_angle, 0.0, delta * 3.2)
		_sync_pump_visuals()

	# 2. Reusable chainshot spar splinter & tattered canvas burst pool.
	if _splinter_burst_timer > 0.0:
		_splinter_burst_timer = maxf(0.0, _splinter_burst_timer - delta)
		var sc := maxf(visual_scale, 0.5)
		var any_alive := false
		for entry: Dictionary in _splinter_pool:
			var mi: MeshInstance3D = entry["node"] as MeshInstance3D
			if mi == null or not is_instance_valid(mi) or not mi.visible:
				continue
			var age := float(entry["age"]) + delta
			var life := maxf(float(entry["lifetime"]), 0.05)
			entry["age"] = age
			if age >= life:
				mi.visible = false
				continue
			any_alive = true
			var is_wood := bool(entry["is_wood"])
			var vel: Vector3 = entry["vel"] as Vector3
			var ang_vel: Vector3 = entry["ang_vel"] as Vector3
			vel.y -= (9.4 if is_wood else 3.6) * delta
			if not is_wood:
				vel.x *= maxf(0.0, 1.0 - 1.35 * delta)
				vel.z *= maxf(0.0, 1.0 - 1.35 * delta)
			entry["vel"] = vel
			mi.position += vel * delta
			mi.rotation += ang_vel * delta
			var fade_rem := clampf((life - age) / 0.35, 0.0, 1.0)
			var base_sc: Vector3 = entry["base_scale"] as Vector3
			mi.scale = base_sc * (sc * (0.25 + 0.75 * fade_rem))
		if not any_alive:
			_splinter_burst_timer = 0.0

	# 3. Sculpted cannon priming fuse spark flare.
	if _fuse_flash_timer > 0.0:
		_fuse_flash_timer = maxf(0.0, _fuse_flash_timer - delta)
		if _fuse_spark_mi != null and is_instance_valid(_fuse_spark_mi):
			if _fuse_flash_timer <= 0.0:
				_fuse_spark_mi.visible = false
			else:
				var t := clampf(_fuse_flash_timer / FUSE_FLASH_DURATION, 0.0, 1.0)
				var pop := sin(t * PI) * 0.45 + t * 0.85
				_fuse_spin += delta * 18.0
				_fuse_spark_mi.rotation = Vector3(_fuse_spin * 0.6, _fuse_spin, _fuse_spin * 0.4)
				_fuse_spark_mi.scale = Vector3.ONE * (maxf(0.2, pop) * maxf(visual_scale, 0.5))
				_fuse_spark_mi.transparency = clampf(1.0 - t * 1.25, 0.0, 1.0)
				_fuse_spark_mi.visible = true


func _sync_pump_visuals() -> void:
	if _pump_handle_pivot != null and is_instance_valid(_pump_handle_pivot):
		_pump_handle_pivot.rotation.x = _pump_handle_angle
	if _pump_water_mi != null and is_instance_valid(_pump_water_mi):
		var streaming := _pump_stream_strength > 0.03
		_pump_water_mi.visible = streaming
		if streaming:
			var pulse := 0.90 + 0.14 * absf(sin(_pump_phase * 2.0))
			_pump_water_mi.scale = Vector3(
				lerpf(0.65, 1.08, _pump_stream_strength) * pulse,
				lerpf(0.70, 1.04, _pump_stream_strength),
				lerpf(0.70, 1.06, _pump_stream_strength) * pulse
			)
			_pump_water_mi.transparency = clampf(1.0 - _pump_stream_strength * 0.92, 0.0, 1.0)


# ==============================================================================
# Scene Construction & Shared WeakRef PBR Asset Builders (0 Primitives)
# ==============================================================================

func _build_visuals() -> void:
	_all_mesh_instances.clear()
	_splinter_pool.clear()

	var is_brig := ship != null and is_instance_valid(ship) \
		and ship.has_method(&"is_brigantine") and bool(ship.call(&"is_brigantine"))
	var unscaled_bilge := BRIG_BILGE_POS if is_brig else SLOOP_BILGE_POS
	var bilge_pos := unscaled_bilge * visual_scale
	if ship != null and is_instance_valid(ship) and ship.has_method(&"ship_point"):
		bilge_pos = ship.call(&"ship_point", unscaled_bilge) as Vector3

	_pump_root = Node3D.new()
	_pump_root.name = "BilgePumpRoot"
	_pump_root.position = bilge_pos
	_pump_root.scale = Vector3.ONE * visual_scale
	add_child(_pump_root)

	_pump_oak_mi = _add_mesh_node(_pump_root, "BilgePumpOakStand", _pump_oak_mesh, _oak_mat)
	_pump_iron_mi = _add_mesh_node(_pump_root, "BilgePumpIronBarrel", _pump_iron_mesh, _iron_mat)
	_pump_brass_mi = _add_mesh_node(_pump_root, "BilgePumpBrassSpout", _pump_brass_mesh, _brass_mat)

	_pump_handle_pivot = Node3D.new()
	_pump_handle_pivot.name = "BilgePumpHandlePivot"
	_pump_handle_pivot.position = Vector3(0.0, 0.96, 0.04)
	_pump_root.add_child(_pump_handle_pivot)

	_pump_handle_iron_mi = _add_mesh_node(_pump_handle_pivot, "BilgePumpFulcrumIron", _pump_handle_iron_mesh, _iron_mat)
	_pump_handle_oak_mi = _add_mesh_node(_pump_handle_pivot, "BilgePumpLeverOak", _pump_handle_oak_mesh, _oak_mat)
	_pump_handle_brass_mi = _add_mesh_node(_pump_handle_pivot, "BilgePumpGripBrass", _pump_handle_brass_mesh, _brass_mat)

	_pump_water_mi = _add_mesh_node(_pump_root, "BilgePumpWaterJet", _pump_water_mesh, _water_mat)
	_pump_water_mi.position = Vector3(0.32, 0.67, -0.06)
	_pump_water_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pump_water_mi.visible = false

	# Reusable chainshot wooden spar splinter & tattered canvas shred pool (0 per-hit allocations).
	_splinter_root = Node3D.new()
	_splinter_root.name = "SailSplinterBurstRoot"
	add_child(_splinter_root)

	for i in SPLINTER_POOL_SIZE:
		var is_wood := i < SPLINTER_WOOD_COUNT
		var mi := _add_mesh_node(
			_splinter_root,
			("SparSplinter_%02d" % i) if is_wood else ("CanvasShred_%02d" % (i - SPLINTER_WOOD_COUNT)),
			_splinter_mesh if is_wood else _canvas_shred_mesh,
			_oak_mat if is_wood else _canvas_mat
		)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		var b_sc := Vector3(
			0.85 + 0.35 * float(i % 3) / 2.0,
			0.80 + 0.45 * float((i + 1) % 3) / 2.0,
			0.85 + 0.35 * float((i + 2) % 3) / 2.0
		)
		_splinter_pool.append({
			"node": mi,
			"is_wood": is_wood,
			"vel": Vector3.ZERO,
			"ang_vel": Vector3.ZERO,
			"age": 0.0,
			"lifetime": SPLINTER_BURST_DURATION,
			"base_scale": b_sc,
		})

	# Sculpted multi-pointed fiery amber-gold cannon priming fuse spark star.
	_fuse_spark_mi = _add_mesh_node(self, "CannonFuseSpark", _fuse_spark_mesh, _fuse_mat)
	_fuse_spark_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fuse_spark_mi.visible = false


func _add_mesh_node(parent: Node3D, node_name: String, mesh_res: ArrayMesh, mat_res: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh_res
	mi.material_override = mat_res
	parent.add_child(mi)
	_all_mesh_instances.append(mi)
	return mi


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
		tri_scale: Vector3, norm_scale: float, double_sided: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = roughness
	mat.metallic = metallic
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = false
	mat.uv1_scale = tri_scale
	if double_sided:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
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
	if _canvas_mat == null:
		_canvas_mat = _make_pbr_mat(0.88, 0.02, TEX_CLOTH_NORMAL, TEX_ROPE_ROUGH, Vector3(2.5, 2.5, 2.5), 0.65, true)
	if _water_mat == null:
		var wm := StandardMaterial3D.new()
		wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wm.vertex_color_use_as_albedo = true
		wm.vertex_color_is_srgb = true
		wm.uv1_triplanar = true
		wm.uv1_world_triplanar = false
		wm.cull_mode = BaseMaterial3D.CULL_DISABLED
		wm.roughness = 0.14
		wm.metallic = 0.0
		wm.albedo_color = Color(1.0, 1.0, 1.0, 0.84)
		wm.emission_enabled = true
		wm.emission = Color(0.26, 0.74, 0.80)
		wm.emission_energy_multiplier = 0.25
		_water_mat = wm
	if _fuse_mat == null:
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.vertex_color_use_as_albedo = true
		fm.vertex_color_is_srgb = true
		fm.uv1_triplanar = true
		fm.uv1_world_triplanar = false
		fm.cull_mode = BaseMaterial3D.CULL_DISABLED
		fm.albedo_color = Color(1.0, 1.0, 1.0, 0.96)
		_fuse_mat = fm

	if _pump_oak_mesh == null:
		_pump_oak_mesh = _build_pump_oak_mesh()
	if _pump_iron_mesh == null:
		_pump_iron_mesh = _build_pump_iron_mesh()
	if _pump_brass_mesh == null:
		_pump_brass_mesh = _build_pump_brass_mesh()
	if _pump_handle_iron_mesh == null:
		_pump_handle_iron_mesh = _build_pump_handle_iron_mesh()
	if _pump_handle_oak_mesh == null:
		_pump_handle_oak_mesh = _build_pump_handle_oak_mesh()
	if _pump_handle_brass_mesh == null:
		_pump_handle_brass_mesh = _build_pump_handle_brass_mesh()
	if _pump_water_mesh == null:
		_pump_water_mesh = _build_pump_water_mesh()
	if _splinter_mesh == null:
		_splinter_mesh = _build_splinter_mesh()
	if _canvas_shred_mesh == null:
		_canvas_shred_mesh = _build_canvas_shred_mesh()
	if _fuse_spark_mesh == null:
		_fuse_spark_mesh = _build_fuse_spark_mesh()


static func _build_pump_oak_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Heavy chamfered oak stand plinth straddling the bilge sump grating, seated dead-flush at y = 0.000.
	_add_box(st, Vector3(0.0, 0.045, -0.06), Vector3(0.56, 0.09, 0.44), COL_OAK_HI, COL_OAK_MID, COL_OAK_LO)
	_add_box(st, Vector3(0.0, 0.110, -0.06), Vector3(0.42, 0.048, 0.36), COL_OAK_HI, COL_OAK_MID, COL_OAK_LO)

	# Coopered 10-sided oak pump barrel jacket rising from plinth to upper collar.
	_add_lathe_at(st, Vector3(0.0, 0.0, -0.06), [
		Vector2(0.0, 0.12),
		Vector2(0.158, 0.12),
		Vector2(0.146, 0.24),
		Vector2(0.132, 0.56),
		Vector2(0.138, 0.78),
		Vector2(0.122, 0.84),
		Vector2(0.0, 0.84),
	], 10, COL_OAK_LO, COL_OAK_HI)

	# Twin mortised seasoned-oak stanchion cheeks & diagonal knee braces flanking the barrel.
	for sx: float in [-1.0, 1.0]:
		_add_box(st, Vector3(sx * 0.185, 0.44, -0.06), Vector3(0.065, 0.68, 0.12),
			COL_OAK_HI, COL_OAK_MID, COL_OAK_LO)
		var b_knee := Basis(Vector3.FORWARD, sx * 0.42)
		_add_oriented_box(st, b_knee, Vector3(sx * 0.23, 0.22, -0.06), Vector3(0.055, 0.26, 0.095),
			COL_OAK_HI, COL_OAK_MID, COL_OAK_LO)
		# Aft timber foot strut anchoring toward the operator stance.
		var b_aft := Basis(Vector3.RIGHT, -0.34)
		_add_oriented_box(st, b_aft, Vector3(sx * 0.175, 0.22, 0.055), Vector3(0.055, 0.26, 0.075),
			COL_OAK_MID, COL_OAK_MID, COL_OAK_LO)

	# Upper oak collar cross-yoke tie bar.
	_add_box(st, Vector3(0.0, 0.76, -0.06), Vector3(0.45, 0.065, 0.14), COL_OAK_HI, COL_OAK_MID, COL_OAK_LO)

	st.generate_normals()
	return st.commit()


static func _build_pump_iron_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Cast-iron suction base flange seated on the plinth & upper forged-iron pump barrel throat.
	_add_lathe_at(st, Vector3(0.0, 0.0, -0.06), [
		Vector2(0.0, 0.13),
		Vector2(0.185, 0.13),
		Vector2(0.185, 0.175),
		Vector2(0.155, 0.195),
		Vector2(0.140, 0.195),
		Vector2(0.0, 0.195),
	], 10, COL_IRON_LO, COL_IRON_HI)

	# Heavy forged-iron upper pump cylinder collar & flared rim crown (y = 0.78..0.94).
	_add_lathe_at(st, Vector3(0.0, 0.0, -0.06), [
		Vector2(0.118, 0.78),
		Vector2(0.146, 0.80),
		Vector2(0.148, 0.89),
		Vector2(0.162, 0.92),
		Vector2(0.152, 0.95),
		Vector2(0.095, 0.95),
		Vector2(0.088, 0.88),
		Vector2(0.0, 0.88),
	], 10, COL_IRON_LO, COL_IRON_HI)

	# Three forged-iron cinching hoop bands gripping the coopered oak pump barrel.
	for band_y: float in [0.27, 0.48, 0.68]:
		var r_b := 0.146 if band_y < 0.35 else 0.140
		_add_lathe_at(st, Vector3(0.0, 0.0, -0.06), [
			Vector2(r_b - 0.012, band_y - 0.024),
			Vector2(r_b, band_y - 0.018),
			Vector2(r_b, band_y + 0.018),
			Vector2(r_b - 0.012, band_y + 0.024),
		], 10, COL_IRON_LO, COL_IRON_HI)

	# Six hexagonal cast-iron anchor bolt heads ringing the base collar flange.
	for bi in 6:
		var ang := TAU * float(bi) / 6.0 + 0.26
		var bp := Vector3(cos(ang) * 0.166, 0.175, -0.06 + sin(ang) * 0.166)
		_add_tube(st, bp, bp + Vector3(0.0, 0.028, 0.0), 0.017, 0.015, 6, COL_IRON_HI, COL_IRON_LO)

	# Aft forged-iron fulcrum tower bracket & twin pivot ears supporting _pump_handle_pivot at (0, 0.96, 0.04).
	_add_box(st, Vector3(0.0, 0.84, 0.03), Vector3(0.14, 0.16, 0.08), COL_IRON_HI, COL_IRON_MID, COL_IRON_LO)
	for sx: float in [-1.0, 1.0]:
		_add_box(st, Vector3(sx * 0.056, 0.94, 0.04), Vector3(0.028, 0.13, 0.075),
			COL_IRON_HI, COL_IRON_MID, COL_IRON_LO)
	# Horizontal forged fulcrum axle pin.
	_add_tube(st, Vector3(-0.082, 0.96, 0.04), Vector3(0.082, 0.96, 0.04),
		0.020, 0.020, 8, COL_IRON_HI, COL_IRON_LO)

	st.generate_normals()
	return st.commit()


static func _build_pump_brass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Turned-brass discharge mounting collar on the starboard (+X) upper pump barrel.
	_add_tube(st, Vector3(0.11, 0.68, -0.06), Vector3(0.195, 0.68, -0.06),
		0.072, 0.060, 10, COL_BRASS_HI, COL_BRASS_LO)
	_add_tube(st, Vector3(0.135, 0.68, -0.06), Vector3(0.165, 0.68, -0.06),
		0.082, 0.082, 10, COL_BRASS_HI, COL_BRASS_MID)

	# Sculpted open U-channel turned-brass discharge spout trough & upturned lip extending to x = +0.34.
	_add_box(st, Vector3(0.26, 0.645, -0.06), Vector3(0.16, 0.022, 0.095), COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)
	for sz: float in [-1.0, 1.0]:
		_add_box(st, Vector3(0.255, 0.678, -0.06 + sz * 0.044), Vector3(0.155, 0.062, 0.018),
			COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)
	# Flared curved spout discharge lip collar & under-spout support strut.
	var lip_b := Basis(Vector3.FORWARD, -0.26)
	_add_oriented_box(st, lip_b, Vector3(0.34, 0.652, -0.06), Vector3(0.036, 0.024, 0.112),
		COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)
	_add_tube(st, Vector3(0.14, 0.56, -0.06), Vector3(0.28, 0.64, -0.06),
		0.016, 0.014, 6, COL_BRASS_MID, COL_BRASS_LO)

	# Ornamental turned-brass pressure rim & domed valve finial atop the barrel rim.
	_add_lathe_at(st, Vector3(0.0, 0.0, -0.06), [
		Vector2(0.154, 0.90),
		Vector2(0.168, 0.915),
		Vector2(0.168, 0.935),
		Vector2(0.154, 0.945),
	], 10, COL_BRASS_MID, COL_BRASS_HI)
	_add_lathe_at(st, Vector3(0.0, 0.0, -0.16), [
		Vector2(0.0, 0.92),
		Vector2(0.032, 0.92),
		Vector2(0.036, 0.955),
		Vector2(0.024, 0.99),
		Vector2(0.0, 1.01),
	], 8, COL_BRASS_LO, COL_BRASS_HI)

	st.generate_normals()
	return st.commit()


static func _build_pump_handle_iron_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Forged-iron fulcrum hub, twin clevis side-straps, and plunger link dipping into the pump barrel.
	_add_tube(st, Vector3(-0.044, 0.0, 0.0), Vector3(0.044, 0.0, 0.0), 0.036, 0.036, 8, COL_IRON_HI, COL_IRON_LO)
	for sx: float in [-1.0, 1.0]:
		_add_box(st, Vector3(sx * 0.034, 0.008, 0.025), Vector3(0.018, 0.048, 0.28),
			COL_IRON_HI, COL_IRON_MID, COL_IRON_LO)
	# Forward plunger eye & vertical forged-iron piston rod plunging into the cylinder (-Z = -0.10).
	_add_box(st, Vector3(0.0, 0.010, -0.10), Vector3(0.055, 0.045, 0.065), COL_IRON_HI, COL_IRON_MID, COL_IRON_LO)
	_add_tube(st, Vector3(0.0, 0.0, -0.10), Vector3(0.0, -0.24, -0.10),
		0.022, 0.019, 8, COL_IRON_HI, COL_IRON_LO)
	# Aft socket ferrule clamping the oak lever shaft.
	_add_tube(st, Vector3(0.0, 0.012, 0.09), Vector3(0.0, 0.024, 0.19),
		0.032, 0.029, 8, COL_IRON_HI, COL_IRON_LO)

	st.generate_normals()
	return st.commit()


static func _build_pump_handle_oak_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Tapered octagonal seasoned-oak pump handle lever extending aft (+Z) toward the operator.
	_add_tube(st, Vector3(0.0, 0.022, 0.16), Vector3(0.0, 0.062, 0.56),
		0.026, 0.021, 8, COL_OAK_HI, COL_OAK_LO)
	# Sculpted ergonomic hand-grip swell near the aft end.
	_add_tube(st, Vector3(0.0, 0.056, 0.48), Vector3(0.0, 0.068, 0.62),
		0.024, 0.027, 8, COL_OAK_HI, COL_OAK_MID)

	st.generate_normals()
	return st.commit()


static func _build_pump_handle_brass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Turned brass grip collar ring & rounded pommel finial capping the oak pump handle.
	_add_tube(st, Vector3(0.0, 0.052, 0.45), Vector3(0.0, 0.057, 0.49),
		0.029, 0.029, 8, COL_BRASS_HI, COL_BRASS_MID)
	_add_tube(st, Vector3(0.0, 0.068, 0.61), Vector3(0.0, 0.074, 0.665),
		0.030, 0.016, 8, COL_BRASS_HI, COL_BRASS_LO)
	_add_tube(st, Vector3(0.0, 0.074, 0.665), Vector3(0.0, 0.076, 0.682),
		0.016, 0.004, 8, COL_BRASS_HI, COL_BRASS_MID)

	st.generate_normals()
	return st.commit()


static func _build_pump_water_mesh() -> ArrayMesh:
	# Sculpted parabolic arched turquoise-white water jet plume + splash crown & droplets (0 primitives).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	const RINGS := 10
	const SEGS := 8
	var centers: Array[Vector3] = []
	var radii: Array[float] = []
	for ri in range(RINGS + 1):
		var t := float(ri) / float(RINGS)
		var x := t * 0.64
		var y := 0.05 * t - 0.66 * t * t
		var z := sin(t * PI * 2.0) * 0.012
		centers.append(Vector3(x, y, z))
		var r := lerpf(0.028, 0.052, t) * (1.0 + 0.14 * sin(t * PI * 3.0))
		radii.append(r)

	for ri in RINGS:
		var p0 := centers[ri]
		var p1 := centers[ri + 1]
		var r0 := radii[ri]
		var r1 := radii[ri + 1]
		var dir := (p1 - p0).normalized()
		var up_ref := Vector3.UP if absf(dir.y) < 0.92 else Vector3.FORWARD
		var u := dir.cross(up_ref).normalized()
		var v := dir.cross(u).normalized()
		var mid := (p0 + p1) * 0.5
		var t0 := float(ri) / float(RINGS)
		var t1 := float(ri + 1) / float(RINGS)
		var c0 := COL_WATER_FOAM.lerp(COL_WATER_MID, clampf(t0 * 1.15, 0.0, 1.0))
		var c1 := COL_WATER_MID.lerp(COL_WATER_DEEP, clampf(t1, 0.0, 1.0))
		for s in SEGS:
			var a0 := TAU * float(s) / float(SEGS)
			var a1 := TAU * float(s + 1) / float(SEGS)
			var d0 := u * cos(a0) + v * sin(a0)
			var d1 := u * cos(a1) + v * sin(a1)
			var v00 := p0 + d0 * r0
			var v10 := p0 + d1 * r0
			var v01 := p1 + d0 * r1
			var v11 := p1 + d1 * r1
			var col_a := COL_WATER_FOAM if d0.y > 0.35 else c0
			var col_b := COL_WATER_FOAM if d1.y > 0.35 else c0
			var col_c := COL_WATER_FOAM if d1.y > 0.35 else c1
			var col_d := COL_WATER_FOAM if d0.y > 0.35 else c1
			_emit_outward_quad(st, v00, v10, v11, v01, mid, col_a, col_b, col_c, col_d)

	# Frothy flared splash crown at the stream landing point + 4 sculpted flying spray droplets.
	var land := centers[RINGS]
	_add_lathe_at(st, land + Vector3(0.0, -0.02, 0.0), [
		Vector2(0.0, 0.0),
		Vector2(0.11, 0.01),
		Vector2(0.145, 0.055),
		Vector2(0.095, 0.075),
		Vector2(0.035, 0.035),
		Vector2(0.0, 0.02),
	], 8, COL_WATER_MID, COL_WATER_FOAM)

	var drop_offsets: Array[Vector3] = [
		Vector3(0.24, 0.04, 0.07),
		Vector3(0.38, -0.03, -0.08),
		Vector3(0.52, -0.18, 0.09),
		Vector3(0.58, -0.34, -0.06),
	]
	for d_off: Vector3 in drop_offsets:
		_add_diamond_shard(st, d_off, Vector3(0.024, 0.038, 0.024), COL_WATER_FOAM, COL_WATER_MID)

	st.generate_normals()
	return st.commit()


static func _build_splinter_mesh() -> ArrayMesh:
	# Jagged broken wooden spar splinter shard with beveled grain & snapped tips (0 primitives).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Main fractured timber wedge body along X.
	var b_main := Basis(Vector3.UP, 0.14)
	_add_oriented_box(st, b_main, Vector3(0.0, 0.0, 0.0), Vector3(0.52, 0.065, 0.095),
		COL_SPLINTER_HI, COL_SPLINTER_MID, COL_SPLINTER_LO)
	# Twin jagged split-grain needle tips protruding from opposite ends.
	_add_diamond_shard(st, Vector3(0.32, 0.012, 0.018), Vector3(0.16, 0.028, 0.038),
		COL_SPLINTER_HI, COL_SPLINTER_MID)
	_add_diamond_shard(st, Vector3(-0.31, -0.010, -0.015), Vector3(0.15, 0.026, 0.034),
		COL_SPLINTER_MID, COL_SPLINTER_LO)
	# Secondary peeled bark/grain sliver offset along the shard.
	var b_sliv := Basis(Vector3.FORWARD, 0.24)
	_add_oriented_box(st, b_sliv, Vector3(0.05, 0.032, -0.030), Vector3(0.34, 0.032, 0.042),
		COL_SPLINTER_HI, COL_SPLINTER_MID, COL_SPLINTER_LO)

	st.generate_normals()
	return st.commit()


static func _build_canvas_shred_mesh() -> ArrayMesh:
	# Twisted tattered sailcloth strip ribbon with jagged ripped notch tail (0 primitives).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	const STRIPS := 4
	var prev_a := Vector3(-0.28, 0.0, -0.10)
	var prev_b := Vector3(-0.28, 0.0, 0.11)
	var prev_c := COL_CANVAS_HI
	for si in range(1, STRIPS + 1):
		var t := float(si) / float(STRIPS)
		var x := lerpf(-0.28, 0.30, t)
		var wave_y := sin(t * PI * 1.65) * 0.075
		var half_w := lerpf(0.11, 0.032, t)
		var twist := t * 0.72
		var cur_a := Vector3(x, wave_y + sin(twist) * half_w, -cos(twist) * half_w)
		var cur_b := Vector3(x, wave_y - sin(twist) * half_w, cos(twist) * half_w)
		var cur_c := COL_CANVAS_HI.lerp(COL_CANVAS_LO, t)
		var ref_p := (prev_a + prev_b + cur_a + cur_b) * 0.25 + Vector3(0.0, -0.12, 0.0)
		_emit_outward_quad(st, prev_a, cur_a, cur_b, prev_b, ref_p, prev_c, cur_c, cur_c, prev_c)
		prev_a = cur_a
		prev_b = cur_b
		prev_c = cur_c

	# Jagged ripped twin tail pennants at the trailing edge.
	var tip_a := prev_a + Vector3(0.14, 0.025, -0.025)
	var tip_b := prev_b + Vector3(0.12, -0.028, 0.022)
	var mid_tail := (prev_a + prev_b) * 0.5 + Vector3(0.03, 0.0, 0.0)
	var tail_ref := mid_tail + Vector3(0.0, -0.1, 0.0)
	_emit_outward_tri(st, prev_a, tip_a, mid_tail, tail_ref, COL_CANVAS_MID, COL_CANVAS_LO, COL_CANVAS_MID)
	_emit_outward_tri(st, mid_tail, tip_b, prev_b, tail_ref, COL_CANVAS_MID, COL_CANVAS_LO, COL_CANVAS_MID)

	st.generate_normals()
	return st.commit()


static func _build_fuse_spark_mesh() -> ArrayMesh:
	# Sculpted multi-pointed fiery amber-gold 3D spark star bursting at the cannon breech (0 primitives).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Bright central octahedron spark core.
	_add_diamond_shard(st, Vector3.ZERO, Vector3(0.068, 0.068, 0.068), COL_SPARK_CORE, COL_SPARK_GOLD)

	# 12 radiating multi-pointed fiery golden-amber & ember spikes in 3D.
	var dirs: Array[Vector3] = [
		Vector3(1.0, 0.15, 0.0),
		Vector3(-1.0, -0.10, 0.0),
		Vector3(0.0, 1.0, 0.12),
		Vector3(0.0, -1.0, -0.10),
		Vector3(0.08, 0.10, 1.0),
		Vector3(-0.08, -0.08, -1.0),
		Vector3(0.72, 0.68, 0.42),
		Vector3(-0.70, 0.66, -0.44),
		Vector3(0.68, -0.64, -0.45),
		Vector3(-0.72, -0.62, 0.48),
		Vector3(0.42, 0.62, -0.68),
		Vector3(-0.44, 0.60, 0.66),
	]
	for di in dirs.size():
		var dir := dirs[di].normalized()
		var spike_len := 0.24 if (di < 6) else 0.19
		var base_r := 0.032 if (di < 6) else 0.025
		var up_ref := Vector3.UP if absf(dir.y) < 0.92 else Vector3.RIGHT
		var u := dir.cross(up_ref).normalized() * base_r
		var v := dir.cross(u).normalized() * base_r
		var base_c := dir * 0.035
		var tip := dir * spike_len
		var ring: Array[Vector3] = [base_c + u, base_c + v, base_c - u, base_c - v]
		var tip_col := COL_SPARK_GOLD if (di % 2 == 0) else COL_SPARK_EMBER
		for k in 4:
			var k1 := (k + 1) % 4
			_emit_outward_tri(st, ring[k], ring[k1], tip, Vector3.ZERO, COL_SPARK_CORE, COL_SPARK_GOLD, tip_col)

	st.generate_normals()
	return st.commit()


# ==============================================================================
# Sculpted Flat-Faceted Geometry Primitives (Outward-Wound SurfaceTool Helpers)
# ==============================================================================

static func _add_diamond_shard(st: SurfaceTool, center: Vector3, half_ext: Vector3,
		col_hi: Color, col_lo: Color) -> void:
	var top := center + Vector3(0.0, half_ext.y, 0.0)
	var bot := center + Vector3(0.0, -half_ext.y, 0.0)
	var ring: Array[Vector3] = [
		center + Vector3(half_ext.x, 0.0, 0.0),
		center + Vector3(0.0, 0.0, half_ext.z),
		center + Vector3(-half_ext.x, 0.0, 0.0),
		center + Vector3(0.0, 0.0, -half_ext.z),
	]
	for i in 4:
		var i1 := (i + 1) % 4
		_emit_outward_tri(st, ring[i], ring[i1], top, center, col_hi, col_hi, col_hi)
		_emit_outward_tri(st, ring[i1], ring[i], bot, center, col_lo, col_lo, col_lo)


static func _add_lathe_at(st: SurfaceTool, offset: Vector3, profile: Array[Vector2], segs: int,
		col_bot: Color, col_top: Color) -> void:
	if profile.size() < 2:
		return
	var y_mid := (profile[0].y + profile[profile.size() - 1].y) * 0.5
	var ref_c := offset + Vector3(0.0, y_mid, 0.0)
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
			var p00 := offset + Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p10 := offset + Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p01 := offset + Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := offset + Vector3(cos(a1) * r1, y1, sin(a1) * r1)
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
