class_name SunkenShipwreck
extends Node3D
## Dynamic half-submerged barnacle-crusted Sunken Shipwreck ocean dive encounter.
##
## Features:
## - 100% sculpted flat-faceted `SurfaceTool` `ArrayMesh` hull (>= 1,400 tris, zero
##   raw `PrimitiveMesh`es) using WeakRef-cached shared ship BC7 PBR normal/roughness
##   textures (`uv1_triplanar = true`, `uv1_world_triplanar = false`, zero extra VRAM).
## - Upright wave-tracking root (gentle damped wallow ~0.05 rad) hosting a circling
##   7-gull `SeabirdFlock` loot marker overhead, while `_hull_pivot` lists dramatically
##   at 32 deg roll and -18 deg pitch so the broken stern castle, snapped mainmast stump,
##   and exposed oak ribs jut 3.5..6.5 m above the waves while the breached lower
##   captain's cabin extends -2.2..-5.2 m beneath the surface for diving.
## - Simplified `StaticBody3D` outer hull collider (layer 1) leaving the gaping port
##   hull breach and underwater cabin 100% open and swimmable.
## - 2..3 high-tier diveable `Carryable` treasures anchored inside the flooded cabin
##   with turquoise underwater `OmniLight3D` shimmer guide glow (hidden when cleared
##   or beyond 120 m) and ref-counted zero-leak static cache teardown.

signal shipwreck_looted(wreck: SunkenShipwreck, item: Node)
signal shipwreck_cleared(wreck: SunkenShipwreck)

const GROUP := &"sunken_shipwrecks"

const LIST_ROLL_DEG := 32.0
const LIST_PITCH_DEG := -18.0
const HULL_PIVOT_OFFSET_Y := -0.35
const GLOW_CULL_DIST := 120.0
const GLOW_CULL_DIST_SQ := GLOW_CULL_DIST * GLOW_CULL_DIST

const TEX_HULL_NORMAL := "res://assets/generated/textures/ship_oak_normal.png"
const TEX_HULL_ROUGH := "res://assets/generated/textures/ship_oak_rough.png"
const TEX_HULL_NORMAL_ALT := "res://assets/generated/textures/ship/ship_hull_normal.png"
const TEX_HULL_ROUGH_ALT := "res://assets/generated/textures/ship/ship_hull_roughness.png"
const TEX_IRON_NORMAL := "res://assets/generated/textures/ship_iron_normal.png"
const TEX_IRON_ROUGH := "res://assets/generated/textures/ship_iron_rough.png"

# High-tier dive treasure catalogue pools (verified TreasureCatalog IDs).
const HIGH_TIER_LOOT_POOL: Array[StringName] = [
	&"sovereign_chest",
	&"archive_chalice",
	&"ledger_coffer",
	&"captains_skull",
	&"corsair_chest",
]
const CURSED_LOOT_POOL: Array[StringName] = [
	&"weeping_bilge_chest",
	&"blazing_rage_chest",
]

# Hull-local interior cabin floor slots (under `_hull_pivot`) mapping cleanly to sea_y - 2.6..-3.8 m.
const CABIN_LOOT_SLOTS_LOCAL: Array[Vector3] = [
	Vector3(-0.30, -1.85, -2.20),
	Vector3(-0.60, -1.95, -3.20),
	Vector3(-0.90, -2.05, -4.10),
]

# Painterly sRGB-calibrated waterlogged shipwreck palette.
const COL_OAK_BLEACHED := Color(0.50, 0.41, 0.29)
const COL_OAK_MID := Color(0.36, 0.26, 0.16)
const COL_OAK_WET := Color(0.18, 0.14, 0.10)
const COL_OAK_ALGAE := Color(0.17, 0.27, 0.19)
const COL_SPLINTER := Color(0.66, 0.52, 0.32)
const COL_TAR_MAST := Color(0.16, 0.12, 0.09)
const COL_TAR_HI := Color(0.28, 0.21, 0.15)
const COL_IRON_RUST := Color(0.28, 0.21, 0.17)
const COL_IRON_DARK := Color(0.16, 0.17, 0.19)
const COL_HEMP_HI := Color(0.65, 0.55, 0.37)
const COL_HEMP_LO := Color(0.42, 0.34, 0.22)
const COL_SAIL_TATTER_HI := Color(0.76, 0.72, 0.60)
const COL_SAIL_TATTER_LO := Color(0.46, 0.45, 0.38)
const COL_BARNACLE_HI := Color(0.84, 0.82, 0.74)
const COL_BARNACLE_BASE := Color(0.42, 0.48, 0.44)
const COL_KELP_HI := Color(0.20, 0.46, 0.28)
const COL_KELP_LO := Color(0.09, 0.24, 0.18)
const COL_TRANSOM_GLOW := Color(0.26, 0.88, 0.82)

# Ref-counted static sculpted ArrayMesh, shared PBR materials & WeakRef texture cache.
static var _active_wrecks: int = 0
static var _hull_mesh: ArrayMesh = null
static var _hull_mat: StandardMaterial3D = null
static var _accent_mat: StandardMaterial3D = null
static var _glow_mat: StandardMaterial3D = null
static var _pbr_tex_cache: Dictionary = {}  # String path -> WeakRef(Texture2D)

@export var seed_val: int = 1
@export var wreck_name: String = "Sunken Galleon"
@export var auto_spawn_loot: bool = true

var base_x: float = 0.0
var base_z: float = 0.0
var loot_items: Array[Node3D] = []

var _hull_pivot: Node3D = null
var _hull_mi: MeshInstance3D = null
var _hull_collider: StaticBody3D = null
var _gull_flock: SeabirdFlock = null
var _cabin_light: OmniLight3D = null
var _loot_spawned: bool = false
var _cleared: bool = false
var _looted_ids: Dictionary = {}  # int instance_id -> true
var _bob_clock: float = 0.0
var _base_yaw: float = 0.0


## Spawn a half-submerged barnacle-crusted SunkenShipwreck dive encounter at `world_pos`.
static func spawn_at(parent: Node, world_pos: Vector3, p_seed: int = 1) -> SunkenShipwreck:
	var wreck := SunkenShipwreck.new()
	wreck.name = "SunkenShipwreck_%d" % absi(p_seed)
	wreck.seed_val = p_seed
	wreck.base_x = world_pos.x
	wreck.base_z = world_pos.z
	var sy := Sea.height(world_pos.x, world_pos.z) if Sea != null else world_pos.y
	wreck.position = Vector3(world_pos.x, sy, world_pos.z)
	if parent != null:
		parent.add_child(wreck)
		wreck.global_position = Vector3(world_pos.x, sy, world_pos.z)
	return wreck


## Release all statically cached wreck meshes, PBR materials, and WeakRef textures cleanly.
static func clear_shared_cache() -> void:
	for mat: StandardMaterial3D in [_hull_mat, _accent_mat, _glow_mat]:
		if mat != null:
			mat.albedo_texture = null
			mat.normal_texture = null
			mat.roughness_texture = null
	_hull_mesh = null
	_hull_mat = null
	_accent_mat = null
	_glow_mat = null
	_pbr_tex_cache.clear()


func _enter_tree() -> void:
	_active_wrecks += 1
	add_to_group(GROUP)


func _ready() -> void:
	if base_x == 0.0 and base_z == 0.0:
		base_x = global_position.x
		base_z = global_position.z

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0x5419EC
	_base_yaw = rng.randf_range(0.0, TAU)
	_bob_clock = rng.randf_range(0.0, TAU)
	rotation.y = _base_yaw

	_ensure_shared_assets()
	_build_hierarchy()
	step_buoyancy(0.0)

	# Circling 7-gull seabird loot marker mounted on the upright root (level in the sky).
	_gull_flock = SeabirdFlock.spawn_over(self, global_position, 16.0, 22.0, 7)

	if auto_spawn_loot:
		spawn_cabin_loot()


func _exit_tree() -> void:
	_release_refs()
	_active_wrecks = maxi(0, _active_wrecks - 1)
	if _active_wrecks == 0:
		clear_shared_cache()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_release_refs()


func _physics_process(delta: float) -> void:
	step_buoyancy(delta)


# ==============================================================================
# Public Dive Loot, State & Introspection API
# ==============================================================================

## Host-authoritative idempotent underwater cabin treasure spawner (2..3 high-tier Carryables).
func spawn_cabin_loot(parent_node: Node = null) -> Array[Carryable]:
	if not Net.is_host():
		return []
	if _loot_spawned:
		var existing: Array[Carryable] = []
		for item in loot_items:
			if item is Carryable and is_instance_valid(item):
				existing.append(item as Carryable)
		return existing

	_loot_spawned = true
	loot_items.clear()
	_looted_ids.clear()
	_cleared = false

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0xCA81B7
	var count := rng.randi_range(2, 3)

	var pool := HIGH_TIER_LOOT_POOL.duplicate()
	var chosen_ids: Array[StringName] = []
	for i in count:
		if i == count - 1 and rng.randf() < 0.35:
			var c_idx := rng.randi_range(0, CURSED_LOOT_POOL.size() - 1)
			chosen_ids.append(CURSED_LOOT_POOL[c_idx])
		else:
			var p_idx := rng.randi_range(0, pool.size() - 1)
			chosen_ids.append(pool[p_idx])
			pool.remove_at(p_idx)

	var target_parent: Node = parent_node if parent_node != null else self
	var sea_y := Sea.height(base_x, base_z) if Sea != null else global_position.y
	var spawned: Array[Carryable] = []

	for i in chosen_ids.size():
		var tid: StringName = chosen_ids[i]
		var slot_local: Vector3 = CABIN_LOOT_SLOTS_LOCAL[i % CABIN_LOOT_SLOTS_LOCAL.size()]
		var world_pos := _compute_cabin_slot_world_pos(slot_local, sea_y)
		var item := TreasureCatalog.create_treasure_carryable(tid, world_pos)
		item.name = "WreckLoot_%d_%s" % [i, String(tid)]
		item.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		item.freeze = true

		target_parent.add_child(item)
		if item.is_inside_tree():
			item.global_position = world_pos
			item.rotation = Vector3(
				rng.randf_range(-0.18, 0.18),
				rng.randf_range(0.0, TAU),
				rng.randf_range(-0.22, 0.22)
			)

		var cb_pick := Callable(self, &"_on_loot_picked_up").bind(item)
		if not item.picked_up.is_connected(cb_pick):
			item.picked_up.connect(cb_pick)
		var cb_store := Callable(self, &"_on_loot_picked_up").bind(item)
		if not item.stored.is_connected(cb_store):
			item.stored.connect(cb_store)

		loot_items.append(item)
		spawned.append(item)

	_update_cabin_light()
	return spawned


## Count how many dive treasures remain unrecovered inside the underwater cabin.
func get_remaining_loot_count() -> int:
	var remaining := 0
	for item in loot_items:
		if item == null or not is_instance_valid(item) or item.is_queued_for_deletion():
			continue
		if _looted_ids.has(item.get_instance_id()):
			continue
		if item is Carryable:
			var c := item as Carryable
			if c.is_held() or c.stored_in != null:
				continue
		remaining += 1
	return remaining


## True once all spawned cabin treasures have been salvaged.
func is_cleared() -> bool:
	if _cleared:
		return true
	if _loot_spawned and get_remaining_loot_count() == 0:
		_cleared = true
		_update_cabin_light()
		return true
	return false


func get_hull_pivot() -> Node3D:
	return _hull_pivot


func get_hull_mesh_instance() -> MeshInstance3D:
	return _hull_mi


func get_gull_flock() -> SeabirdFlock:
	return _gull_flock


func get_cabin_light() -> OmniLight3D:
	return _cabin_light


## Return total sculpted triangle count across the shared hull ArrayMesh.
func get_triangle_count() -> int:
	_ensure_shared_assets()
	return _count_mesh_tris(_hull_mesh)


## Heavy damped wave wallow (~0.05 rad) on the upright root + underwater light distance culling.
func step_buoyancy(delta: float) -> void:
	_bob_clock += maxf(0.0, delta)
	var sea_y := Sea.height(base_x, base_z) if Sea != null else 0.0
	var sx0 := Sea.height(base_x - 3.0, base_z) if Sea != null else sea_y
	var sx1 := Sea.height(base_x + 3.0, base_z) if Sea != null else sea_y
	var sz0 := Sea.height(base_x, base_z - 3.0) if Sea != null else sea_y
	var sz1 := Sea.height(base_x, base_z + 3.0) if Sea != null else sea_y

	var slope_x := clampf((sx1 - sx0) / 6.0, -0.04, 0.04)
	var slope_z := clampf((sz1 - sz0) / 6.0, -0.04, 0.04)
	var pitch := clampf(-slope_z * 0.75 + sin(_bob_clock * 0.62) * 0.022, -0.055, 0.055)
	var roll := clampf(slope_x * 0.75 + cos(_bob_clock * 0.51) * 0.024, -0.055, 0.055)
	var heave := sin(_bob_clock * 0.78) * 0.065

	var target_pos := Vector3(base_x, sea_y + heave, base_z)
	if is_inside_tree():
		global_position = target_pos
	else:
		position = target_pos
	rotation = Vector3(pitch, _base_yaw, roll)

	# Keep circling gull flock level in the sky even as the heavy hull wallows beneath.
	if _gull_flock != null and is_instance_valid(_gull_flock):
		_gull_flock.position = Vector3.ZERO
		_gull_flock.rotation = Vector3(-pitch, 0.0, -roll)

	_update_cabin_light()


# ==============================================================================
# Internal Loot Tracking, Hierarchy & Collision Construction
# ==============================================================================

func _compute_cabin_slot_world_pos(slot_local: Vector3, sea_y: float) -> Vector3:
	var world_pos: Vector3
	if _hull_pivot != null and is_instance_valid(_hull_pivot) and _hull_pivot.is_inside_tree():
		world_pos = _hull_pivot.to_global(slot_local)
	else:
		var list_basis := Basis.from_euler(Vector3(deg_to_rad(LIST_PITCH_DEG), 0.0, deg_to_rad(LIST_ROLL_DEG)))
		var root_basis := Basis(Vector3.UP, _base_yaw)
		var local_in_root := Vector3(0.0, HULL_PIVOT_OFFSET_Y, 0.0) + list_basis * slot_local
		world_pos = Vector3(base_x, sea_y, base_z) + root_basis * local_in_root
	world_pos.y = clampf(world_pos.y, sea_y - 3.80, sea_y - 2.60)
	return world_pos


func _on_loot_picked_up(_actor: Node, item: Carryable) -> void:
	if item == null or not is_instance_valid(item):
		return
	var iid := item.get_instance_id()
	if _looted_ids.has(iid):
		return
	_looted_ids[iid] = true

	# Detach world transform from wreck wave bobbing without firing tree_exiting on cursed chests.
	if item.get_parent() == self and item.is_inside_tree() and not item.top_level:
		var cur_xf := item.global_transform
		item.top_level = true
		item.global_transform = cur_xf

	shipwreck_looted.emit(self, item)

	if get_remaining_loot_count() == 0 and not _cleared:
		_cleared = true
		_update_cabin_light()
		shipwreck_cleared.emit(self)


func _update_cabin_light() -> void:
	if _cabin_light == null or not is_instance_valid(_cabin_light):
		return
	if _cleared or (_loot_spawned and get_remaining_loot_count() == 0):
		_cabin_light.visible = false
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() and get_viewport() != null else null
	if cam != null and global_position.distance_squared_to(cam.global_position) > GLOW_CULL_DIST_SQ:
		_cabin_light.visible = false
		return
	_cabin_light.visible = true
	_cabin_light.light_energy = 1.40 + sin(_bob_clock * 2.3) * 0.24 + sin(_bob_clock * 4.9) * 0.09


func _build_hierarchy() -> void:
	_hull_pivot = Node3D.new()
	_hull_pivot.name = "HullPivot"
	_hull_pivot.position = Vector3(0.0, HULL_PIVOT_OFFSET_Y, 0.0)
	_hull_pivot.rotation = Vector3(deg_to_rad(LIST_PITCH_DEG), 0.0, deg_to_rad(LIST_ROLL_DEG))
	add_child(_hull_pivot)

	_hull_mi = MeshInstance3D.new()
	_hull_mi.name = "SunkenHullMesh"
	_hull_mi.mesh = _hull_mesh
	_hull_mi.set_surface_override_material(0, _hull_mat)
	if _hull_mesh.get_surface_count() > 1:
		_hull_mi.set_surface_override_material(1, _accent_mat)
	if _hull_mesh.get_surface_count() > 2:
		_hull_mi.set_surface_override_material(2, _glow_mat)
	_hull_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_hull_mi.visibility_range_end = 1800.0
	_hull_pivot.add_child(_hull_mi)

	# Turquoise underwater cabin shimmer guide glow (shadowless, 9.0 m range).
	_cabin_light = OmniLight3D.new()
	_cabin_light.name = "CabinGuideLight"
	_cabin_light.position = Vector3(-0.35, -1.65, -2.55)
	_cabin_light.light_color = Color(0.22, 0.92, 0.84)
	_cabin_light.light_energy = 1.40
	_cabin_light.omni_range = 9.0
	_cabin_light.omni_attenuation = 1.4
	_cabin_light.shadow_enabled = false
	_hull_pivot.add_child(_cabin_light)

	_build_hull_collider()


func _build_hull_collider() -> void:
	# Simplified outer hull ribs StaticBody3D on layer 1, keeping port breach & dive cabin 100% open!
	_hull_collider = StaticBody3D.new()
	_hull_collider.name = "HullCollider"
	_hull_collider.collision_layer = 1
	_hull_collider.collision_mask = 0
	_hull_pivot.add_child(_hull_collider)

	var boxes: Array[Array] = [
		# [name, local_pos, size]
		["KeelFloor", Vector3(0.0, -2.48, -0.1), Vector3(3.3, 0.34, 10.2)],
		["StarboardWall", Vector3(2.02, -0.70, 0.0), Vector3(0.36, 3.10, 10.2)],
		["SternTransom", Vector3(0.0, 0.25, 5.22), Vector3(3.60, 4.40, 0.36)],
		["BowBulkhead", Vector3(0.0, -0.95, -5.25), Vector3(2.50, 2.70, 0.36)],
		["QuarterdeckFloor", Vector3(0.0, 1.68, 3.85), Vector3(3.55, 0.28, 2.70)],
		["PortAftWall", Vector3(-2.02, -0.45, 2.95), Vector3(0.36, 3.15, 4.30)],
		["PortBowStub", Vector3(-1.85, -1.10, -4.65), Vector3(0.36, 2.15, 1.15)],
		["MainmastStump", Vector3(0.0, 2.10, 0.85), Vector3(0.56, 8.20, 0.56)],
	]
	for spec in boxes:
		var cs := CollisionShape3D.new()
		cs.name = String(spec[0])
		var bx := BoxShape3D.new()
		bx.size = spec[2] as Vector3
		cs.shape = bx
		cs.position = spec[1] as Vector3
		_hull_collider.add_child(cs)


func _release_refs() -> void:
	for item in loot_items:
		if item is Carryable and is_instance_valid(item):
			var c := item as Carryable
			var cb := Callable(self, &"_on_loot_picked_up").bind(c)
			if c.picked_up.is_connected(cb):
				c.picked_up.disconnect(cb)
			if c.stored.is_connected(cb):
				c.stored.disconnect(cb)
	loot_items.clear()
	_looted_ids.clear()
	if _hull_mi != null and is_instance_valid(_hull_mi):
		if _hull_mi.mesh != null:
			for si in _hull_mi.mesh.get_surface_count():
				_hull_mi.set_surface_override_material(si, null)
		_hull_mi.mesh = null
		_hull_mi.material_override = null
	_hull_mi = null
	_hull_collider = null
	_hull_pivot = null
	_gull_flock = null
	_cabin_light = null


# ==============================================================================
# WeakRef Shared BC7 Ship PBR Texture & Material Cache (Zero Extra VRAM)
# ==============================================================================

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


static func _load_first_pbr_tex(paths: Array[String]) -> Texture2D:
	for p in paths:
		var tex := _load_pbr_tex(p)
		if tex != null:
			return tex
	return null


static func _make_pbr_mat(roughness: float, metallic: float, norm_paths: Array[String],
		rough_paths: Array[String], tri_scale: Vector3, norm_scale: float,
		double_sided: bool = false) -> StandardMaterial3D:
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
	var ntex := _load_first_pbr_tex(norm_paths)
	var rtex := _load_first_pbr_tex(rough_paths)
	if ntex != null:
		mat.normal_enabled = true
		mat.normal_scale = norm_scale
		mat.normal_texture = ntex
	if rtex != null:
		mat.roughness_texture = rtex
	return mat


static func _ensure_shared_assets() -> void:
	if _hull_mat == null:
		_hull_mat = _make_pbr_mat(
			0.84, 0.04,
			[TEX_HULL_NORMAL, TEX_HULL_NORMAL_ALT],
			[TEX_HULL_ROUGH, TEX_HULL_ROUGH_ALT],
			Vector3(0.42, 0.42, 0.42), 0.85, false
		)
	if _accent_mat == null:
		_accent_mat = _make_pbr_mat(
			0.66, 0.16,
			[TEX_IRON_NORMAL, TEX_HULL_NORMAL],
			[TEX_IRON_ROUGH, TEX_HULL_ROUGH],
			Vector3(0.85, 0.85, 0.85), 0.72, true
		)
	if _glow_mat == null:
		_glow_mat = StandardMaterial3D.new()
		_glow_mat.vertex_color_use_as_albedo = true
		_glow_mat.vertex_color_is_srgb = true
		_glow_mat.roughness = 0.24
		_glow_mat.metallic = 0.08
		_glow_mat.uv1_triplanar = true
		_glow_mat.uv1_world_triplanar = false
		_glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_glow_mat.emission_enabled = true
		_glow_mat.emission = Color(0.18, 0.78, 0.72)
		_glow_mat.emission_energy_multiplier = 1.65
	if _hull_mesh == null:
		_hull_mesh = _build_hull_mesh()


static func _count_mesh_tris(am: ArrayMesh) -> int:
	if am == null:
		return 0
	var tris := 0
	for si in am.get_surface_count():
		var ilen := am.surface_get_array_index_len(si)
		if ilen > 0:
			tris += floori(float(ilen) / 3.0)
		else:
			tris += floori(float(am.surface_get_array_len(si)) / 3.0)
	return tris


# ==============================================================================
# Sculpted Half-Capsized Barnacle-Crusted Wreck Hull Builder (Zero Primitives)
# ==============================================================================

static func _hull_station_half_beam(z: float) -> float:
	if z <= -4.4:
		var t_bow := clampf((z + 5.4) / 1.0, 0.0, 1.0)
		return lerpf(0.42, 1.24, t_bow)
	if z <= -2.1:
		var t_fwd := clampf((z + 4.4) / 2.3, 0.0, 1.0)
		return lerpf(1.24, 2.04, t_fwd)
	if z <= 1.5:
		return 2.10 - absf(z - 0.1) * 0.03
	var t_aft := clampf((z - 1.5) / 3.7, 0.0, 1.0)
	return lerpf(2.04, 1.66, t_aft)


static func _hull_station_keel_y(z: float) -> float:
	if z < -4.2:
		var t := clampf((-4.2 - z) / 1.2, 0.0, 1.0)
		return lerpf(-2.44, -1.62, t)
	if z > 3.9:
		var t := clampf((z - 3.9) / 1.3, 0.0, 1.0)
		return lerpf(-2.44, -2.08, t)
	return -2.44


static func _hull_station_sheer_y(z: float) -> float:
	if z >= 2.5:
		var t := clampf((z - 2.5) / 2.7, 0.0, 1.0)
		return lerpf(1.88, 2.35, t)
	if z < -3.6:
		var t := clampf((-3.6 - z) / 1.8, 0.0, 1.0)
		return lerpf(1.06, 1.26, t)
	return 1.06


static func _hull_profile_pt(z: float, strake_idx: int, side_sign: float,
		inward_offset: float = 0.0, lap_push: float = 0.0) -> Vector3:
	const X_FRACS: Array[float] = [0.08, 0.56, 0.88, 1.00, 0.96, 0.89]
	const Y_FRACS: Array[float] = [0.00, 0.15, 0.36, 0.58, 0.80, 1.00]
	var hb := _hull_station_half_beam(z)
	var ky := _hull_station_keel_y(z)
	var sy := _hull_station_sheer_y(z)
	var xf: float = X_FRACS[clampi(strake_idx, 0, 5)]
	var yf: float = Y_FRACS[clampi(strake_idx, 0, 5)]
	var x_abs := maxf(0.06, hb * xf - inward_offset + lap_push)
	var y := lerpf(ky, sy, yf) + (inward_offset * 0.25 if strake_idx == 0 else 0.0)
	return Vector3(side_sign * x_abs, y, z)


static func _is_port_breach_panel(bay_idx: int, strake_idx: int) -> bool:
	# Gaping port-side breach hole (bay 2..4 = z -3.3..+0.3, strakes 1..4; bay 1 = z -4.4..-3.3, strakes 2..4).
	if bay_idx >= 2 and bay_idx <= 4 and strake_idx >= 1 and strake_idx <= 4:
		return true
	if bay_idx == 1 and strake_idx >= 2 and strake_idx <= 4:
		return true
	return false


static func _strake_oak_color(strake_idx: int, z: float) -> Color:
	if strake_idx == 0:
		return COL_OAK_WET
	if strake_idx == 1:
		return COL_OAK_WET.lerp(COL_OAK_ALGAE, 0.52)
	if strake_idx == 2:
		return COL_OAK_ALGAE.lerp(COL_OAK_MID, 0.55)
	if strake_idx == 3:
		return COL_OAK_MID
	return COL_OAK_MID.lerp(COL_OAK_BLEACHED, 0.65 if z > 2.2 else 0.40)


static func _build_hull_mesh() -> ArrayMesh:
	var wood_st := SurfaceTool.new()
	wood_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var accent_st := SurfaceTool.new()
	accent_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow_st := SurfaceTool.new()
	glow_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	const HULL_ZS: Array[float] = [-5.4, -4.4, -3.3, -2.1, -0.9, 0.3, 1.5, 2.7, 3.9, 5.2]

	# 1. Clinker-planked curved hull shell (double-sided thickness) with gaping port breach.
	for side_sign: float in [1.0, -1.0]:
		for bi in range(HULL_ZS.size() - 1):
			var z0: float = HULL_ZS[bi]
			var z1: float = HULL_ZS[bi + 1]
			for si in 5:
				if side_sign < 0.0 and _is_port_breach_panel(bi, si):
					continue
				var col_lo := _strake_oak_color(si, (z0 + z1) * 0.5)
				var col_hi := _strake_oak_color(si + 1, (z0 + z1) * 0.5)
				var col_in_lo := col_lo.darkened(0.24)
				var col_in_hi := col_hi.darkened(0.22)

				# Outer clinker-stepped strake quad.
				var o00 := _hull_profile_pt(z0, si, side_sign, 0.0, 0.036)
				var o10 := _hull_profile_pt(z1, si, side_sign, 0.0, 0.036)
				var o11 := _hull_profile_pt(z1, si + 1, side_sign, 0.0, 0.0)
				var o01 := _hull_profile_pt(z0, si + 1, side_sign, 0.0, 0.0)
				var out_dir := Vector3(side_sign, -0.25 if si == 0 else 0.10, 0.0).normalized()
				_emit_directed_quad(wood_st, o00, o10, o11, o01, out_dir, col_lo, col_lo, col_hi, col_hi)

				# Clinker under-lap bevel lip along the bottom edge of each strake.
				var u00 := _hull_profile_pt(z0, si, side_sign, 0.0, 0.0)
				var u10 := _hull_profile_pt(z1, si, side_sign, 0.0, 0.0)
				_emit_directed_quad(wood_st, u00, u10, o10, o00, Vector3(0.0, -1.0, 0.0),
					col_in_lo, col_in_lo, col_lo, col_lo)

				# Inner hull ceiling plank quad so underwater dive interior is fully solid.
				var i00 := _hull_profile_pt(z0, si, side_sign, 0.14, 0.0)
				var i10 := _hull_profile_pt(z1, si, side_sign, 0.14, 0.0)
				var i11 := _hull_profile_pt(z1, si + 1, side_sign, 0.14, 0.0)
				var i01 := _hull_profile_pt(z0, si + 1, side_sign, 0.14, 0.0)
				_emit_directed_quad(wood_st, i00, i01, i11, i10, -out_dir,
					col_in_lo, col_in_hi, col_in_hi, col_in_lo)

				# Top gunwale cap timber on uppermost strake.
				if si == 4:
					_emit_directed_quad(wood_st, o01, o11, i11, i01, Vector3.UP,
						COL_OAK_BLEACHED, COL_OAK_BLEACHED, COL_OAK_MID, COL_OAK_MID)

		# Heavy rubbing wale beam running along the outer hull waist.
		for bi in range(HULL_ZS.size() - 1):
			if side_sign < 0.0 and _is_port_breach_panel(bi, 3):
				continue
			var wa := _hull_profile_pt(HULL_ZS[bi], 3, side_sign, -0.05, 0.0)
			var wb := _hull_profile_pt(HULL_ZS[bi + 1], 3, side_sign, -0.05, 0.0)
			_add_beam(wood_st, wa, wb, 0.14, 0.18, COL_TAR_HI, COL_TAR_MAST)

	# 2. Jagged splintered plank tongues & snapped hull edges framing the gaping port breach.
	for si in range(1, 5):
		# Aft breach edge (z = +0.3 jutting forward toward -Z).
		var p_aft := _hull_profile_pt(0.30, si, -1.0, 0.05, 0.0)
		var l_aft := 0.58 + float((si * 7) % 3) * 0.22
		_add_splinter_shard(wood_st, p_aft, p_aft + Vector3(0.06, 0.08 * float(si - 2), -l_aft),
			0.11, 0.16, COL_OAK_MID, COL_SPLINTER)
		_add_splinter_shard(wood_st, p_aft + Vector3(0.0, 0.22, 0.0),
			p_aft + Vector3(-0.08, 0.18, -l_aft * 0.72), 0.08, 0.12, COL_OAK_WET, COL_SPLINTER)

		# Forward breach edge (z = -3.3 / -4.4 jutting aft toward +Z).
		var z_fwd := -4.4 if si >= 2 else -3.3
		var p_fwd := _hull_profile_pt(z_fwd, si, -1.0, 0.05, 0.0)
		var l_fwd := 0.52 + float((si * 5) % 3) * 0.20
		_add_splinter_shard(wood_st, p_fwd, p_fwd + Vector3(-0.05, -0.06, l_fwd),
			0.10, 0.15, COL_OAK_MID, COL_SPLINTER)

	# Lower breach rim splinter teeth jutting upward from the shattered bilge strake.
	for zp: float in [-3.1, -2.35, -1.55, -0.75, -0.05]:
		var bp := _hull_profile_pt(zp, 1, -1.0, 0.04, 0.0)
		_add_splinter_shard(wood_st, bp, bp + Vector3(-0.18, 0.42, 0.12),
			0.09, 0.12, COL_OAK_ALGAE, COL_SPLINTER)

	# 3. Heavy keel spine, sweeping stempost, vertical sternpost, shattered bowsprit & crooked rudder.
	_add_box(wood_st, Vector3(0.0, -2.52, -0.10), Vector3(0.36, 0.38, 10.1),
		COL_OAK_WET, COL_TAR_MAST, COL_TAR_MAST)
	# Sweeping stempost & shattered bow bulkhead planks.
	_add_beam(wood_st, Vector3(0.0, -2.44, -4.4), Vector3(0.0, -1.62, -5.4), 0.34, 0.42, COL_TAR_HI, COL_TAR_MAST)
	_add_beam(wood_st, Vector3(0.0, -1.62, -5.4), Vector3(0.0, 1.35, -5.85), 0.32, 0.40, COL_OAK_MID, COL_TAR_MAST)
	# Snapped bowsprit spar jutting forward from the shattered prow + splinter shards.
	var bs_a := Vector3(0.0, 0.95, -5.35)
	var bs_b := Vector3(0.12, 1.48, -7.25)
	_add_tube(wood_st, bs_a, bs_b, 0.16, 0.11, 7, COL_TAR_HI, COL_TAR_MAST)
	for sh_off: Vector3 in [
		Vector3(0.06, 0.05, -0.45),
		Vector3(-0.06, 0.02, -0.38),
		Vector3(0.01, -0.06, -0.32),
	]:
		_add_splinter_shard(wood_st, bs_b, bs_b + sh_off, 0.055, 0.055, COL_TAR_MAST, COL_SPLINTER)

	# Sternpost & crooked broken rudder hanging off rusted iron pintle straps.
	_add_beam(wood_st, Vector3(0.0, -2.18, 5.20), Vector3(0.0, 1.10, 5.32), 0.34, 0.38, COL_OAK_WET, COL_TAR_MAST)
	var rud_basis := Basis(Vector3.UP, 0.42) * Basis(Vector3.FORWARD, -0.14)
	_add_oriented_box(wood_st, rud_basis, Vector3(0.14, -1.10, 5.72), Vector3(0.16, 2.25, 0.86),
		COL_OAK_ALGAE, COL_OAK_WET, COL_TAR_MAST)
	for py: float in [-1.75, -0.95, -0.25]:
		_add_oriented_box(accent_st, rud_basis, Vector3(0.08, py, 5.42), Vector3(0.22, 0.11, 0.56),
			COL_IRON_RUST, COL_IRON_DARK, COL_IRON_DARK)

	# 4. Curved internal oak hull ribs (skeleton frames) + broken ribs inside port breach.
	const RIB_ZS: Array[float] = [-4.3, -3.3, -2.3, -1.3, -0.3, 0.7, 1.7, 2.8, 4.0]
	for rz: float in RIB_ZS:
		var in_breach := (rz >= -3.4 and rz <= 0.2)
		# Starboard full curved internal oak rib (4 curved segments).
		for si in 4:
			var ra := _hull_profile_pt(rz, si, 1.0, 0.20, 0.0)
			var rb := _hull_profile_pt(rz, si + 1, 1.0, 0.20, 0.0)
			_add_beam(wood_st, ra, rb, 0.15, 0.17, COL_OAK_MID, COL_OAK_WET)
		# Port rib: intact outside breach, snapped jagged lower/upper rib stubs inside breach!
		if in_breach:
			var pa := _hull_profile_pt(rz, 0, -1.0, 0.20, 0.0)
			var pb := _hull_profile_pt(rz, 1, -1.0, 0.20, 0.0)
			_add_beam(wood_st, pa, pb, 0.15, 0.17, COL_OAK_ALGAE, COL_OAK_WET)
			_add_splinter_shard(wood_st, pb, pb + Vector3(-0.14, 0.42, 0.05),
				0.09, 0.09, COL_OAK_MID, COL_SPLINTER)
		else:
			for si in 4:
				var pa := _hull_profile_pt(rz, si, -1.0, 0.20, 0.0)
				var pb := _hull_profile_pt(rz, si + 1, -1.0, 0.20, 0.0)
				_add_beam(wood_st, pa, pb, 0.15, 0.17, COL_OAK_MID, COL_OAK_WET)

	# 5. Flooded lower cabin sole planks, broken main deck beams & open dive companionway.
	for pi in 6:
		var px := -1.10 + float(pi) * 0.44
		var plank_len := 7.4 if (pi % 2 == 0) else 6.6
		var plank_z := -0.85 if (pi % 2 == 0) else -1.15
		_add_box(wood_st, Vector3(px, -2.20, plank_z), Vector3(0.36, 0.12, plank_len),
			COL_OAK_ALGAE, COL_OAK_WET, COL_TAR_MAST)

	# Aft intact main deck beams & broken hanging deck planks (leaving forward cabin wide open!).
	for dz: float in [0.4, 1.35, 2.35]:
		var hb_d := _hull_station_half_beam(dz) * 0.88
		_add_box(wood_st, Vector3(0.0, 0.15, dz), Vector3(hb_d * 1.92, 0.18, 0.22),
			COL_OAK_MID, COL_OAK_WET, COL_TAR_MAST)
	# Snapped half-deck beams projecting from starboard across the open dive hold.
	for dz_b: float in [-2.4, -1.1]:
		var hb_b := _hull_station_half_beam(dz_b) * 0.88
		_add_beam(wood_st, Vector3(hb_b, 0.15, dz_b), Vector3(0.45, -0.05, dz_b + 0.10),
			0.18, 0.20, COL_OAK_MID, COL_OAK_WET)
		_add_splinter_shard(wood_st, Vector3(0.45, -0.05, dz_b + 0.10),
			Vector3(-0.08, -0.16, dz_b + 0.16), 0.10, 0.12, COL_OAK_MID, COL_SPLINTER)
	# Partial main deck planking aft of mainmast.
	for pi in 5:
		var px := -1.30 + float(pi) * 0.65
		_add_box(wood_st, Vector3(px, 0.28, 1.45), Vector3(0.54, 0.10, 2.25),
			COL_OAK_BLEACHED, COL_OAK_MID, COL_OAK_WET)

	# 6. Shattered Quarterdeck, Stern Castle Transom, Open Cabin Doorway & Glowing Transom Windows.
	# Quarterdeck deck planking (z = +2.55..+5.15, y = +1.70).
	for pi in 5:
		var px := -1.32 + float(pi) * 0.66
		var qlen := 2.65 if pi != 1 else 1.85
		var qz := 3.85 if pi != 1 else 4.25
		_add_box(wood_st, Vector3(px, 1.72, qz), Vector3(0.58, 0.14, qlen),
			COL_OAK_BLEACHED, COL_OAK_MID, COL_OAK_WET)

	# Forward quarterdeck bulkhead with wide shattered cabin doorway opening in center.
	for sx: float in [-1.0, 1.0]:
		_add_box(wood_st, Vector3(sx * 1.28, 0.96, 2.55), Vector3(1.12, 1.48, 0.18),
			COL_OAK_MID, COL_OAK_WET, COL_TAR_MAST)
	_add_box(wood_st, Vector3(0.0, 1.56, 2.55), Vector3(1.48, 0.28, 0.22),
		COL_OAK_BLEACHED, COL_OAK_MID, COL_OAK_WET)

	# Stern transom wall + carved ornate oak stern gallery molding.
	_add_box(wood_st, Vector3(0.0, -0.42, 5.18), Vector3(3.30, 3.05, 0.24),
		COL_OAK_MID, COL_OAK_WET, COL_TAR_MAST)
	_add_box(wood_st, Vector3(0.0, 1.78, 5.24), Vector3(3.48, 0.22, 0.28),
		COL_OAK_BLEACHED, COL_OAK_MID, COL_OAK_WET)
	_add_box(wood_st, Vector3(0.0, 2.48, 5.24), Vector3(3.38, 0.20, 0.24),
		COL_OAK_BLEACHED, COL_OAK_MID, COL_OAK_WET)

	# 3 Weathered stern transom windows with oak mullions & warm ghostly turquoise glow panes.
	for wx: float in [-0.92, 0.0, 0.92]:
		var wy := 1.18
		var wz := 5.30
		# Frame surround + cross-mullions.
		_add_box(wood_st, Vector3(wx, wy + 0.38, wz), Vector3(0.68, 0.09, 0.12), COL_OAK_BLEACHED, COL_OAK_MID, COL_OAK_WET)
		_add_box(wood_st, Vector3(wx, wy - 0.38, wz), Vector3(0.68, 0.09, 0.12), COL_OAK_BLEACHED, COL_OAK_MID, COL_OAK_WET)
		_add_box(wood_st, Vector3(wx - 0.30, wy, wz), Vector3(0.09, 0.72, 0.12), COL_OAK_MID, COL_OAK_WET, COL_TAR_MAST)
		_add_box(wood_st, Vector3(wx + 0.30, wy, wz), Vector3(0.09, 0.72, 0.12), COL_OAK_MID, COL_OAK_WET, COL_TAR_MAST)
		_add_box(wood_st, Vector3(wx, wy, wz + 0.02), Vector3(0.06, 0.68, 0.08), COL_OAK_MID, COL_OAK_WET, COL_TAR_MAST)
		_add_box(wood_st, Vector3(wx, wy, wz + 0.02), Vector3(0.56, 0.06, 0.08), COL_OAK_MID, COL_OAK_WET, COL_TAR_MAST)
		# Ghostly turquoise transom window glass pane (Surface 2: _glow_mat).
		_add_box(glow_st, Vector3(wx, wy, wz - 0.01), Vector3(0.54, 0.66, 0.04),
			COL_TRANSOM_GLOW, COL_TRANSOM_GLOW.darkened(0.18), COL_TRANSOM_GLOW.darkened(0.28))

	# Underwater cabin lantern glass / bioluminescent shimmer crystals guiding divers inside the hold!
	_add_diamond_shard(glow_st, Vector3(-0.32, -1.55, -2.35), Vector3(0.16, 0.24, 0.16),
		COL_TRANSOM_GLOW, COL_TRANSOM_GLOW.darkened(0.22))
	_add_diamond_shard(glow_st, Vector3(-0.68, -1.78, -3.55), Vector3(0.14, 0.20, 0.14),
		COL_TRANSOM_GLOW, COL_TRANSOM_GLOW.darkened(0.22))

	# Shattered quarterdeck baluster stanchions & broken upper taffrail timbers.
	for sx: float in [-1.0, 1.0]:
		var rail_zs: Array[float] = [2.75, 3.45, 4.15, 4.85]
		for ri in rail_zs.size():
			var rz: float = rail_zs[ri]
			var post_h := 0.82 if (sx > 0.0 or ri >= 2) else 0.42
			var px := sx * (_hull_station_half_beam(rz) * 0.87)
			_add_box(wood_st, Vector3(px, 1.78 + post_h * 0.5, rz), Vector3(0.11, post_h, 0.11),
				COL_OAK_BLEACHED, COL_OAK_MID, COL_OAK_WET)
		# Intact starboard handrail; snapped tilted port handrail!
		if sx > 0.0:
			_add_beam(wood_st, Vector3(1.66, 2.58, 2.70), Vector3(1.48, 2.66, 5.18),
				0.14, 0.12, COL_OAK_BLEACHED, COL_OAK_MID)
		else:
			_add_beam(wood_st, Vector3(-1.56, 2.58, 3.90), Vector3(-1.48, 2.66, 5.18),
				0.14, 0.12, COL_OAK_BLEACHED, COL_OAK_MID)
			_add_splinter_shard(wood_st, Vector3(-1.56, 2.58, 3.90), Vector3(-1.65, 2.38, 3.35),
				0.08, 0.08, COL_OAK_MID, COL_SPLINTER)

	# Stern taffrail balusters along z = +5.18.
	for tx: float in [-1.10, -0.55, 0.0, 0.55, 1.10]:
		_add_box(wood_st, Vector3(tx, 2.15, 5.18), Vector3(0.10, 0.72, 0.10),
			COL_OAK_BLEACHED, COL_OAK_MID, COL_OAK_WET)

	# 7. Snapped tarred mainmast stump (reaches 5.5..6.1 m above waves!), broken yardarm,
	#    dangling hemp shrouds & tattered shredded sail remnant!
	var mast_base := Vector3(0.0, -2.20, 0.85)
	var mast_top := Vector3(0.0, 6.25, 0.85)
	_add_tube(wood_st, mast_base, mast_top, 0.28, 0.18, 8, COL_TAR_HI, COL_TAR_MAST)
	# Jagged splintered wood break crown atop the snapped mainmast stump.
	for mi in 6:
		var ma := TAU * float(mi) / 6.0
		var m_off := Vector3(cos(ma) * 0.11, 0.0, sin(ma) * 0.11)
		var m_h := 0.45 + float((mi * 3) % 4) * 0.18
		_add_splinter_shard(wood_st, mast_top + m_off,
			mast_top + m_off * 1.15 + Vector3(0.0, m_h, 0.0), 0.06, 0.06, COL_TAR_MAST, COL_SPLINTER)

	# 3 Rusted iron mast hoops clasping the mast stump.
	for hy: float in [1.15, 3.05, 4.95]:
		var hr := lerpf(0.28, 0.19, (hy + 2.2) / 8.45) + 0.025
		_add_tube(accent_st, Vector3(0.0, hy - 0.07, 0.85), Vector3(0.0, hy + 0.07, 0.85),
			hr, hr, 8, COL_IRON_RUST, COL_IRON_DARK)

	# Canted broken lower yardarm lashed diagonally across the mast stump.
	var yd_stbd := Vector3(2.45, 4.55, 0.62)
	var yd_port := Vector3(-1.45, 3.65, 0.62)
	_add_tube(wood_st, yd_port, yd_stbd, 0.11, 0.09, 7, COL_TAR_HI, COL_TAR_MAST)
	_add_splinter_shard(wood_st, yd_port, yd_port + Vector3(-0.46, -0.14, 0.04),
		0.07, 0.07, COL_TAR_MAST, COL_SPLINTER)

	# Dangling catenary hemp shroud cables hanging from the mast collar down to the hull chains.
	var shroud_specs: Array[Array] = [
		[Vector3(0.18, 5.10, 0.85), Vector3(1.88, 1.15, 0.25), 0.35],
		[Vector3(0.18, 5.10, 0.95), Vector3(1.86, 1.18, 1.15), 0.42],
		[Vector3(0.18, 5.10, 1.05), Vector3(1.80, 1.35, 2.05), 0.38],
		[Vector3(-0.18, 5.10, 0.85), Vector3(-1.62, 1.20, 1.45), 0.55],
		[Vector3(-0.18, 4.95, 0.78), Vector3(-1.20, 1.55, 0.15), 0.68],
		[Vector3(0.0, 5.20, 0.68), Vector3(0.15, 1.32, -4.75), 0.72],
	]
	for sh in shroud_specs:
		_add_drooping_rope(accent_st, sh[0] as Vector3, sh[1] as Vector3, float(sh[2]),
			0.036, 4, 5, COL_HEMP_HI, COL_HEMP_LO)

	# Tattered shredded canvas sailcloth remnant hanging limp off the broken yardarm.
	_add_tattered_sail(accent_st, yd_port.lerp(yd_stbd, 0.08), yd_stbd.lerp(yd_port, 0.06), 1.85)

	# 8. Clustered sculpted limestone barnacles along waterline, keel, breach & sternpost.
	var barnacle_sites: Array[Array] = [
		# [pos, outward_normal, radius, height]
		[Vector3(1.98, -0.75, -2.4), Vector3(1.0, -0.1, 0.0), 0.22, 0.17],
		[Vector3(2.04, -0.58, -2.1), Vector3(1.0, 0.0, 0.0), 0.16, 0.13],
		[Vector3(2.06, -1.05, -0.6), Vector3(0.95, -0.25, 0.0), 0.25, 0.19],
		[Vector3(2.08, -0.82, -0.3), Vector3(1.0, -0.1, 0.0), 0.18, 0.14],
		[Vector3(2.05, -1.18, 1.4), Vector3(0.92, -0.3, 0.0), 0.24, 0.18],
		[Vector3(1.96, -0.65, 2.8), Vector3(0.98, -0.1, 0.1), 0.21, 0.16],
		[Vector3(1.86, -0.95, 3.6), Vector3(0.95, -0.2, 0.15), 0.23, 0.17],
		[Vector3(1.74, -0.40, 4.5), Vector3(0.92, 0.0, 0.25), 0.19, 0.14],
		[Vector3(-1.94, -1.35, -3.5), Vector3(-0.9, -0.35, 0.0), 0.24, 0.18],
		[Vector3(-1.86, -1.62, -2.2), Vector3(-0.85, -0.45, 0.0), 0.26, 0.19],
		[Vector3(-1.90, -1.55, -0.8), Vector3(-0.85, -0.45, 0.0), 0.23, 0.17],
		[Vector3(-2.02, -0.88, 0.6), Vector3(-1.0, -0.15, 0.0), 0.24, 0.18],
		[Vector3(-2.04, -0.52, 1.2), Vector3(-1.0, 0.0, 0.0), 0.17, 0.13],
		[Vector3(-1.98, -1.02, 2.4), Vector3(-0.95, -0.25, 0.0), 0.25, 0.19],
		[Vector3(-1.88, -0.72, 3.8), Vector3(-0.95, -0.1, 0.1), 0.20, 0.15],
		[Vector3(-1.35, -1.98, -4.1), Vector3(-0.6, -0.75, -0.2), 0.22, 0.16],
		[Vector3(0.45, -2.42, -3.0), Vector3(0.3, -0.95, 0.0), 0.24, 0.18],
		[Vector3(-0.35, -2.44, -1.4), Vector3(-0.25, -0.96, 0.0), 0.26, 0.19],
		[Vector3(0.30, -2.44, 0.8), Vector3(0.2, -0.98, 0.0), 0.25, 0.18],
		[Vector3(-0.28, -2.42, 2.7), Vector3(-0.2, -0.98, 0.0), 0.22, 0.16],
		[Vector3(0.24, -1.45, 5.58), Vector3(0.7, 0.0, 0.7), 0.18, 0.14],
		[Vector3(-0.78, -1.42, 5.28), Vector3(-0.2, -0.2, 0.95), 0.21, 0.16],
		[Vector3(0.84, -1.10, 5.28), Vector3(0.2, -0.1, 0.96), 0.20, 0.15],
		[Vector3(1.52, 0.35, -3.9), Vector3(0.9, 0.1, -0.4), 0.18, 0.14],
	]
	for b in barnacle_sites:
		_add_barnacle_cone(accent_st, b[0] as Vector3, (b[1] as Vector3).normalized(),
			float(b[2]), float(b[3]), COL_BARNACLE_BASE, COL_BARNACLE_HI)

	# 9. Draped undulating emerald/olive kelp ribbons hanging off the breach rim, keel & stern!
	var kelp_anchors: Array[Array] = [
		# [start_pos, length, width, sway_phase]
		[Vector3(-1.95, -0.25, 0.25), 2.15, 0.24, 0.2],
		[Vector3(-1.82, -1.48, -0.55), 1.85, 0.22, 1.1],
		[Vector3(-1.76, -1.55, -1.65), 2.10, 0.25, 2.0],
		[Vector3(-1.74, -1.52, -2.75), 1.95, 0.23, 2.9],
		[Vector3(-1.68, -0.95, -3.95), 2.25, 0.24, 3.8],
		[Vector3(-2.02, -0.35, 1.65), 2.05, 0.22, 0.7],
		[Vector3(2.04, -0.65, -1.50), 1.90, 0.23, 1.5],
		[Vector3(2.06, -0.82, 0.65), 2.15, 0.25, 2.4],
		[Vector3(1.92, -0.60, 2.95), 1.80, 0.21, 3.3],
		[Vector3(0.18, -2.35, -2.40), 1.75, 0.24, 4.1],
		[Vector3(-0.15, -2.35, 0.35), 1.95, 0.25, 4.9],
		[Vector3(0.24, -1.65, 5.75), 2.00, 0.22, 5.5],
		[Vector3(-0.95, -0.95, 5.28), 1.85, 0.23, 0.4],
		[Vector3(0.06, 0.92, -6.15), 1.65, 0.19, 1.9],
	]
	for k in kelp_anchors:
		_add_kelp_ribbon(accent_st, k[0] as Vector3, float(k[1]), float(k[2]), float(k[3]))

	var mesh := ArrayMesh.new()
	wood_st.commit(mesh)
	accent_st.commit(mesh)
	glow_st.commit(mesh)
	return mesh


# ==============================================================================
# Flat-Faceted SurfaceTool Sculpting Primitives (Exact Outward Normals)
# ==============================================================================

static func _add_tattered_sail(st: SurfaceTool, p_port: Vector3, p_stbd: Vector3, drop: float) -> void:
	const COLS := 6
	const ROWS := 4
	var span := p_stbd - p_port
	var side_dir := span.normalized()
	var back_dir := Vector3(0.0, 0.0, -1.0)
	var down_dir := Vector3(-0.18, -0.96, 0.16).normalized()
	var grid: Array = []

	for ci in range(COLS + 1):
		var u := float(ci) / float(COLS)
		var base := p_port.lerp(p_stbd, u)
		# Uneven ragged torn bottom hem so the sail looks storm-shredded.
		var hem_scale := 0.58 + 0.42 * absf(sin(u * PI * 2.6 + 0.45))
		var col_pts: Array[Vector3] = []
		for ri in range(ROWS + 1):
			var v := float(ri) / float(ROWS)
			var billow := sin(v * PI) * 0.24 * (0.65 + 0.35 * sin(u * PI * 1.8))
			var pt := base + down_dir * (v * drop * hem_scale) + back_dir * billow \
				+ side_dir * (sin(v * 3.1 + u * 4.2) * 0.05)
			col_pts.append(pt)
		grid.append(col_pts)

	for ci in COLS:
		for ri in ROWS:
			# Leave a ragged tear notch along one lower fringe column.
			if ri == ROWS - 1 and ci == 2:
				continue
			var v0 := float(ri) / float(ROWS)
			var v1 := float(ri + 1) / float(ROWS)
			var c0 := COL_SAIL_TATTER_HI.lerp(COL_SAIL_TATTER_LO, v0)
			var c1 := COL_SAIL_TATTER_HI.lerp(COL_SAIL_TATTER_LO, v1)
			var p00: Vector3 = grid[ci][ri]
			var p10: Vector3 = grid[ci + 1][ri]
			var p11: Vector3 = grid[ci + 1][ri + 1]
			var p01: Vector3 = grid[ci][ri + 1]
			_emit_directed_quad(st, p00, p10, p11, p01, back_dir, c0, c0, c1, c1)


static func _add_kelp_ribbon(st: SurfaceTool, anchor: Vector3, length: float,
		width: float, phase: float) -> void:
	const SEGS := 4
	var prev_l := anchor + Vector3(-width * 0.5, 0.0, 0.0)
	var prev_r := anchor + Vector3(width * 0.5, 0.0, 0.0)
	var prev_c := COL_KELP_LO
	for si in range(1, SEGS + 1):
		var t := float(si) / float(SEGS)
		var w := width * lerpf(1.0, 0.22, t)
		var sway_x := sin(t * PI * 1.8 + phase) * 0.22 * t
		var sway_z := cos(t * PI * 1.5 + phase) * 0.16 * t
		var mid := anchor + Vector3(sway_x, -t * length, sway_z)
		var cur_l := mid + Vector3(-w * 0.5, 0.0, 0.04 * sin(phase + t * 2.5))
		var cur_r := mid + Vector3(w * 0.5, 0.0, -0.04 * sin(phase + t * 2.5))
		var cur_c := COL_KELP_LO.lerp(COL_KELP_HI, t)
		_emit_directed_quad(st, prev_l, prev_r, cur_r, cur_l, Vector3.FORWARD, prev_c, prev_c, cur_c, cur_c)
		prev_l = cur_l
		prev_r = cur_r
		prev_c = cur_c


static func _add_barnacle_cone(st: SurfaceTool, center: Vector3, normal_dir: Vector3,
		radius: float, height: float, col_base: Color, col_tip: Color) -> void:
	const SIDES := 5
	var up_ref := Vector3.UP if absf(normal_dir.y) < 0.90 else Vector3.RIGHT
	var u := normal_dir.cross(up_ref).normalized()
	var v := normal_dir.cross(u).normalized()
	var rim_r := radius * 0.44
	var crater_c := center + normal_dir * (height * 0.72)
	var ref_c := center - normal_dir * 0.05

	for s in SIDES:
		var a0 := TAU * float(s) / float(SIDES)
		var a1 := TAU * float(s + 1) / float(SIDES)
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		var b0 := center + d0 * radius
		var b1 := center + d1 * radius
		var t0 := center + normal_dir * height + d0 * rim_r
		var t1 := center + normal_dir * height + d1 * rim_r
		_emit_outward_quad(st, b0, b1, t1, t0, ref_c, col_base, col_base, col_tip, col_tip)
		_emit_directed_tri(st, t0, t1, crater_c, normal_dir, col_tip, col_tip, col_base.darkened(0.28))


static func _add_drooping_rope(st: SurfaceTool, p0: Vector3, p1: Vector3, sag: float,
		radius: float, segs: int, sides: int, col_hi: Color, col_lo: Color) -> void:
	var prev := p0
	for i in range(1, segs + 1):
		var t := float(i) / float(segs)
		var pt := p0.lerp(p1, t)
		pt.y -= sin(t * PI) * sag
		_add_tube(st, prev, pt, radius, radius, sides, col_hi, col_lo)
		prev = pt


static func _add_splinter_shard(st: SurfaceTool, base: Vector3, tip: Vector3,
		half_w: float, half_h: float, col_base: Color, col_tip: Color) -> void:
	var axis := tip - base
	if axis.length_squared() < 1e-8:
		return
	var dir := axis.normalized()
	var up_ref := Vector3.UP if absf(dir.y) < 0.90 else Vector3.RIGHT
	var u := dir.cross(up_ref).normalized()
	var v := dir.cross(u).normalized()
	var ring: Array[Vector3] = [
		base + u * half_w + v * half_h,
		base - u * half_w + v * half_h,
		base - u * half_w - v * half_h,
		base + u * half_w - v * half_h,
	]
	var ref_c := base.lerp(tip, 0.30)
	for i in 4:
		var i1 := (i + 1) % 4
		_emit_outward_tri(st, ring[i], ring[i1], tip, ref_c, col_base, col_base, col_tip)
	_emit_outward_quad(st, ring[0], ring[3], ring[2], ring[1], ref_c, col_base, col_base, col_base, col_base)


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


static func _add_beam(st: SurfaceTool, p0: Vector3, p1: Vector3, width: float, height: float,
		col_hi: Color, col_lo: Color) -> void:
	var axis := p1 - p0
	var length := axis.length()
	if length < 1e-5:
		return
	var z_dir := axis / length
	var up_ref := Vector3.UP if absf(z_dir.y) < 0.92 else Vector3.RIGHT
	var x_dir := up_ref.cross(z_dir).normalized()
	var y_dir := z_dir.cross(x_dir).normalized()
	var rot := Basis(x_dir, y_dir, z_dir)
	var mid := (p0 + p1) * 0.5
	_add_oriented_box(st, rot, mid, Vector3(width, height, length), col_hi, col_hi.lerp(col_lo, 0.45), col_lo)


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
		n = -n
	n = n.normalized()
	st.set_normal(n)
	st.set_color(ca)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(cb)
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(b)
	st.set_normal(n)
	st.set_color(cc)
	st.set_uv(Vector2(0.5, 1.0))
	st.add_vertex(c)


static func _emit_directed_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		outward_dir: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_emit_directed_tri(st, a, b, c, outward_dir, ca, cb, cc)
	_emit_directed_tri(st, a, c, d, outward_dir, ca, cc, cd)


static func _emit_directed_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		outward_dir: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	if n.dot(outward_dir) < 0.0:
		var tv := b
		b = c
		c = tv
		var tc := cb
		cb = cc
		cc = tc
		n = -n
	n = n.normalized()
	st.set_normal(n)
	st.set_color(ca)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(cb)
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(b)
	st.set_normal(n)
	st.set_color(cc)
	st.set_uv(Vector2(0.5, 1.0))
	st.add_vertex(c)
