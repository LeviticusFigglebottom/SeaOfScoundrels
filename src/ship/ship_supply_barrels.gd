class_name ShipSupplyBarrels
extends Node3D
## Lower-deck sculpted one-press supply barrel cluster mounted along the port hold bulkhead.
##
## Features 100% sculpted flat-faceted `SurfaceTool` `ArrayMesh` geometry (zero raw
## `PrimitiveMesh`es) using WeakRef-cached shared ship BC7 PBR normal/roughness maps
## (object-space triplanar mapping, zero extra VRAM) and ref-counted leak-free teardown.
##
## Three distinct coopered-oak barrels:
## 1. `CannonballBarrel`: dark-oak barrel with 4 forged-iron hoops & open-top roundshot stack
##    (`_ammo_fill_mi`) scaled/tiered by `ship.cannonballs_remaining / max_cannonballs`.
## 2. `PlankBarrel`: seasoned-oak barrel with 4 forged-iron hoops & jutting beveled oak repair
##    planks (`_plank_fill_mi`) scaled/tiered by `ship.planks_remaining / max_planks`.
## 3. `RationsBarrel`: warm-oak cask with 4 turned brass hoops, inboard brass tap spigot,
##    brass drip mug & carved ration plank lid; one-press `[F]` heals interacting Pawn +25 HP.

signal barrel_used(kind: StringName, pawn: Node)

const RATIONS_HEAL_AMOUNT := 25.0
const DEFAULT_MAX_CANNONBALLS := 40
const DEFAULT_MAX_PLANKS := 24

# Unscaled hold-bulkhead local coordinates (transformed via ship.ship_point + visual_scale).
# Seated cleanly inside floor_in so barrel chines rest 100% flush on hold planks with zero hull-wall clipping.
const SLOOP_POSITIONS := {
	&"cannonball": Vector3(-0.86, -0.85, -0.15),
	&"planks": Vector3(-0.88, -0.85, 0.72),
	&"rations": Vector3(-0.85, -0.85, 1.58),
}
const BRIG_POSITIONS := {
	&"cannonball": Vector3(-1.02, -0.95, 0.72),
	&"planks": Vector3(-1.02, -0.95, 1.62),
	&"rations": Vector3(-0.98, -0.95, 2.52),
}

const TEX_OAK_NORMAL := "res://assets/generated/textures/ship_oak_normal.png"
const TEX_OAK_ROUGH := "res://assets/generated/textures/ship_oak_rough.png"
const TEX_IRON_NORMAL := "res://assets/generated/textures/ship_iron_normal.png"
const TEX_IRON_ROUGH := "res://assets/generated/textures/ship_iron_rough.png"
const TEX_BRASS_NORMAL := "res://assets/generated/textures/ship_brass_normal.png"
const TEX_BRASS_ROUGH := "res://assets/generated/textures/ship_brass_rough.png"

# sRGB-calibrated painterly coopered oak, cast-iron, and turned-brass palettes.
const COL_DARK_OAK_HI := Color(0.40, 0.27, 0.16)
const COL_DARK_OAK_MID := Color(0.28, 0.18, 0.10)
const COL_DARK_OAK_LO := Color(0.16, 0.10, 0.06)

const COL_OAK_HI := Color(0.56, 0.39, 0.22)
const COL_OAK_MID := Color(0.42, 0.28, 0.15)
const COL_OAK_LO := Color(0.24, 0.15, 0.08)

const COL_WARM_OAK_HI := Color(0.64, 0.42, 0.20)
const COL_WARM_OAK_MID := Color(0.48, 0.30, 0.14)
const COL_WARM_OAK_LO := Color(0.29, 0.17, 0.08)

const COL_PLANK_HI := Color(0.72, 0.54, 0.30)
const COL_PLANK_MID := Color(0.58, 0.41, 0.22)
const COL_PLANK_LO := Color(0.38, 0.25, 0.13)

const COL_IRON_HI := Color(0.32, 0.34, 0.38)
const COL_IRON_MID := Color(0.18, 0.19, 0.23)
const COL_IRON_LO := Color(0.09, 0.10, 0.13)

const COL_SHOT_HI := Color(0.27, 0.29, 0.33)
const COL_SHOT_MID := Color(0.14, 0.15, 0.18)
const COL_SHOT_LO := Color(0.07, 0.08, 0.10)

const COL_BRASS_HI := Color(0.96, 0.79, 0.32)
const COL_BRASS_MID := Color(0.76, 0.57, 0.19)
const COL_BRASS_LO := Color(0.44, 0.31, 0.10)

const COL_RATION_CLOTH_HI := Color(0.84, 0.74, 0.54)
const COL_RATION_CLOTH_LO := Color(0.58, 0.48, 0.32)

## Visual scale matched to the owning ship's hull_scale.
@export var visual_scale: float = 1.0
## Maximum cannonball capacity synchronized from Ship.MAX_CANNONBALLS.
@export var max_cannonballs: int = DEFAULT_MAX_CANNONBALLS
## Maximum oak plank capacity synchronized from Ship.MAX_PLANKS.
@export var max_planks: int = DEFAULT_MAX_PLANKS

## Owning ship (`Ship` / `RigidBody3D`).
var ship: Node3D = null

var _barrel_nodes: Dictionary = {}  # StringName -> Node3D
var _interactables: Dictionary = {}  # StringName -> Interactable
var _all_mesh_instances: Array[MeshInstance3D] = []
var _ammo_fill_mi: MeshInstance3D = null
var _plank_fill_mi: MeshInstance3D = null

# Ref-counted static sculpted ArrayMesh & shared PBR material caches (zero ObjectDB leaks).
static var _active_instances: int = 0
static var _pbr_tex_cache: Dictionary = {}  # String path -> WeakRef(Texture2D)
static var _cannon_oak_mesh: ArrayMesh = null
static var _plank_oak_mesh: ArrayMesh = null
static var _rations_oak_mesh: ArrayMesh = null
static var _iron_hoops_mesh: ArrayMesh = null
static var _rations_brass_mesh: ArrayMesh = null
static var _ammo_fill_mesh: ArrayMesh = null
static var _plank_fill_mesh: ArrayMesh = null
static var _oak_mat: StandardMaterial3D = null
static var _iron_mat: StandardMaterial3D = null
static var _brass_mat: StandardMaterial3D = null


## Release all statically cached sculpted ArrayMeshes, PBR materials, and WeakRef textures cleanly.
static func clear_shared_cache() -> void:
	for mat: StandardMaterial3D in [_oak_mat, _iron_mat, _brass_mat]:
		if mat != null:
			mat.normal_texture = null
			mat.roughness_texture = null
	_cannon_oak_mesh = null
	_plank_oak_mesh = null
	_rations_oak_mesh = null
	_iron_hoops_mesh = null
	_rations_brass_mesh = null
	_ammo_fill_mesh = null
	_plank_fill_mesh = null
	_oak_mat = null
	_iron_mat = null
	_brass_mat = null
	_pbr_tex_cache.clear()


func _enter_tree() -> void:
	_active_instances += 1


func _ready() -> void:
	_ensure_shared_assets()
	_build_barrels()
	sync_fill_visuals()


func _exit_tree() -> void:
	for kind_key in _interactables:
		var it := _interactables[kind_key] as Interactable
		if it != null and is_instance_valid(it):
			for conn: Dictionary in it.interacted.get_connections():
				var cb: Callable = conn["callable"]
				if cb.get_object() == self and it.interacted.is_connected(cb):
					it.interacted.disconnect(cb)
	_interactables.clear()
	_barrel_nodes.clear()
	for mi: MeshInstance3D in _all_mesh_instances:
		if mi != null and is_instance_valid(mi):
			mi.material_override = null
			mi.mesh = null
	_all_mesh_instances.clear()
	_ammo_fill_mi = null
	_plank_fill_mi = null
	ship = null
	_active_instances = maxi(0, _active_instances - 1)
	if _active_instances == 0:
		clear_shared_cache()


# ==============================================================================
# Public API
# ==============================================================================

## Synchronize sculpted roundshot / plank fill tier meshes and dynamic stock prompts.
func sync_fill_visuals() -> void:
	var ammo_cur := _get_cannonballs_remaining()
	var ammo_cap := maxi(max_cannonballs, 1)
	var ammo_ratio := get_fill_ratio(&"cannonball")
	if _ammo_fill_mi != null and is_instance_valid(_ammo_fill_mi):
		if ammo_cur <= 0:
			_ammo_fill_mi.visible = false
		else:
			_ammo_fill_mi.visible = true
			if ammo_ratio >= 0.67:
				_ammo_fill_mi.position = Vector3(0.0, 0.0, 0.0)
				_ammo_fill_mi.scale = Vector3(1.0, 1.0, 1.0)
			elif ammo_ratio >= 0.34:
				_ammo_fill_mi.position = Vector3(0.0, -0.10, 0.0)
				_ammo_fill_mi.scale = Vector3(0.94, 0.84, 0.94)
			else:
				_ammo_fill_mi.position = Vector3(0.0, -0.20, 0.0)
				_ammo_fill_mi.scale = Vector3(0.86, 0.68, 0.86)

	var plank_cur := _get_planks_remaining()
	var plank_cap := maxi(max_planks, 1)
	var plank_ratio := get_fill_ratio(&"planks")
	if _plank_fill_mi != null and is_instance_valid(_plank_fill_mi):
		if plank_cur <= 0:
			_plank_fill_mi.visible = false
		else:
			_plank_fill_mi.visible = true
			if plank_ratio >= 0.67:
				_plank_fill_mi.position = Vector3(0.0, 0.0, 0.0)
				_plank_fill_mi.scale = Vector3(1.0, 1.0, 1.0)
			elif plank_ratio >= 0.34:
				_plank_fill_mi.position = Vector3(0.0, -0.09, 0.0)
				_plank_fill_mi.scale = Vector3(0.92, 0.82, 0.92)
			else:
				_plank_fill_mi.position = Vector3(0.0, -0.18, 0.0)
				_plank_fill_mi.scale = Vector3(0.84, 0.64, 0.84)

	var ammo_it := get_barrel_interactable(&"cannonball")
	if ammo_it != null:
		ammo_it.prompt = ("Restock cannonballs (%d/%d)" % [ammo_cur, ammo_cap]) if ammo_cur < ammo_cap \
			else ("Take cannonballs (%d/%d)" % [ammo_cur, ammo_cap])

	var plank_it := get_barrel_interactable(&"planks")
	if plank_it != null:
		plank_it.prompt = ("Restock oak planks (%d/%d)" % [plank_cur, plank_cap]) if plank_cur < plank_cap \
			else ("Take oak planks (%d/%d)" % [plank_cur, plank_cap])

	var rations_it := get_barrel_interactable(&"rations")
	if rations_it != null:
		rations_it.prompt = "Grab rations & grog (+25 HP)"


## Total sculpted triangle count across all MeshInstance3D nodes in this 3-barrel cluster.
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


## Return the Interactable handle for `&"cannonball"`, `&"planks"`, or `&"rations"`.
func get_barrel_interactable(kind: StringName) -> Interactable:
	var key := _normalize_kind(kind)
	var it: Variant = _interactables.get(key, null)
	if it is Interactable and is_instance_valid(it):
		return it as Interactable
	return null


## Return normalized fill ratio in [0.0, 1.0] for `&"cannonball"`, `&"planks"`, or `&"rations"`.
func get_fill_ratio(kind: StringName) -> float:
	var key := _normalize_kind(kind)
	match key:
		&"cannonball":
			return clampf(float(_get_cannonballs_remaining()) / float(maxi(max_cannonballs, 1)), 0.0, 1.0)
		&"planks":
			return clampf(float(_get_planks_remaining()) / float(maxi(max_planks, 1)), 0.0, 1.0)
		&"rations":
			return 1.0
	return 0.0


## Host-authoritative one-press barrel interaction (`&"cannonball"`, `&"planks"`, or `&"rations"`).
func use_barrel(kind: StringName, pawn: Node = null) -> bool:
	if not Net.is_host():
		return false
	var key := _normalize_kind(kind)
	var sfx_pos := _get_barrel_world_pos(key)
	match key:
		&"cannonball":
			var before := _get_cannonballs_remaining()
			if ship != null and is_instance_valid(ship):
				ship.set(&"cannonballs_remaining", max_cannonballs)
			sync_fill_visuals()
			Audio.play_sfx(&"chest_thump", sfx_pos, -3.5)
			if Game != null:
				if before < max_cannonballs:
					Game.post_notice("Cannonballs restocked (%d/%d)." % [max_cannonballs, max_cannonballs])
				else:
					Game.post_notice("Cannonballs full (%d/%d)." % [max_cannonballs, max_cannonballs])
			barrel_used.emit(&"cannonball", pawn)
			if ship != null and is_instance_valid(ship) and ship.has_signal(&"supplies_taken"):
				ship.emit_signal(&"supplies_taken", pawn)
			return true

		&"planks":
			var before := _get_planks_remaining()
			if ship != null and is_instance_valid(ship):
				ship.set(&"planks_remaining", max_planks)
			sync_fill_visuals()
			Audio.play_sfx(&"hammer_plank", sfx_pos, -3.5)
			if Game != null:
				if before < max_planks:
					Game.post_notice("Oak planks restocked (%d/%d)." % [max_planks, max_planks])
				else:
					Game.post_notice("Oak planks full (%d/%d)." % [max_planks, max_planks])
			barrel_used.emit(&"planks", pawn)
			if ship != null and is_instance_valid(ship) and ship.has_signal(&"supplies_taken"):
				ship.emit_signal(&"supplies_taken", pawn)
			return true

		&"rations":
			var healed := 0.0
			if pawn is Pawn and is_instance_valid(pawn):
				var p := pawn as Pawn
				if p.dead:
					return false
				if p.health < p.max_health:
					var before_hp := p.health
					p.heal(RATIONS_HEAL_AMOUNT)
					healed = maxf(0.0, p.health - before_hp)
			Audio.play_sfx(&"grog_gulp", sfx_pos, -1.5)
			if Game != null:
				if healed > 0.01:
					Game.post_notice("Grabbed rations & grog (+%d HP)." % int(roundf(healed)))
				else:
					Game.post_notice("Shared a hearty mug of ship's grog (full HP).")
			barrel_used.emit(&"rations", pawn)
			return true

	return false


# ==============================================================================
# Internal Helpers & Construction
# ==============================================================================

static func _normalize_kind(kind: StringName) -> StringName:
	match kind:
		&"cannonball", &"cannonballs", &"ammo":
			return &"cannonball"
		&"planks", &"plank", &"wood":
			return &"planks"
		&"rations", &"grog", &"food":
			return &"rations"
	return kind


func _is_brigantine_ship() -> bool:
	if ship != null and is_instance_valid(ship) and ship.has_method(&"is_brigantine"):
		return bool(ship.call(&"is_brigantine"))
	return false


func _resolve_local_pos(unscaled: Vector3) -> Vector3:
	if ship != null and is_instance_valid(ship) and ship.has_method(&"ship_point"):
		return ship.call(&"ship_point", unscaled) as Vector3
	return unscaled * visual_scale


func _get_cannonballs_remaining() -> int:
	if ship != null and is_instance_valid(ship):
		var v: Variant = ship.get(&"cannonballs_remaining")
		if v != null:
			return maxi(0, int(v))
	return max_cannonballs


func _get_planks_remaining() -> int:
	if ship != null and is_instance_valid(ship):
		var v: Variant = ship.get(&"planks_remaining")
		if v != null:
			return maxi(0, int(v))
	return max_planks


func _get_barrel_world_pos(kind: StringName) -> Vector3:
	var n: Variant = _barrel_nodes.get(kind, null)
	if n is Node3D and is_instance_valid(n) and (n as Node3D).is_inside_tree():
		return (n as Node3D).global_position + Vector3.UP * (0.45 * visual_scale)
	return global_position if is_inside_tree() else Vector3.ZERO


func _build_barrels() -> void:
	var positions: Dictionary = BRIG_POSITIONS if _is_brigantine_ship() else SLOOP_POSITIONS

	# 1. Cannonball Barrel (dark coopered oak + 4 forged-iron hoops + tiered roundshot stack)
	var cannon_root := _make_barrel_root(
		"CannonballBarrel",
		&"cannonball",
		positions[&"cannonball"] as Vector3,
		"Take cannonballs (%d/%d)" % [max_cannonballs, max_cannonballs]
	)
	_attach_mesh(cannon_root, "CannonballBarrelOak", _cannon_oak_mesh, _oak_mat)
	_attach_mesh(cannon_root, "CannonballBarrelHoops", _iron_hoops_mesh, _iron_mat)
	_ammo_fill_mi = _attach_mesh(cannon_root, "AmmoFill", _ammo_fill_mesh, _iron_mat)

	# 2. Oak Plank Barrel (seasoned coopered oak + 4 forged-iron hoops + jutting beveled repair planks)
	var plank_root := _make_barrel_root(
		"PlankBarrel",
		&"planks",
		positions[&"planks"] as Vector3,
		"Take oak planks (%d/%d)" % [max_planks, max_planks]
	)
	_attach_mesh(plank_root, "PlankBarrelOak", _plank_oak_mesh, _oak_mat)
	_attach_mesh(plank_root, "PlankBarrelHoops", _iron_hoops_mesh, _iron_mat)
	_plank_fill_mi = _attach_mesh(plank_root, "PlankFill", _plank_fill_mesh, _oak_mat)

	# 3. Grog & Rations Barrel (warm coopered oak + carved ration lid + turned brass hoops, tap spigot & drip mug)
	var rations_root := _make_barrel_root(
		"RationsBarrel",
		&"rations",
		positions[&"rations"] as Vector3,
		"Grab rations & grog (+25 HP)"
	)
	_attach_mesh(rations_root, "RationsBarrelOak", _rations_oak_mesh, _oak_mat)
	_attach_mesh(rations_root, "RationsBarrelBrass", _rations_brass_mesh, _brass_mat)


func _make_barrel_root(node_name: String, kind: StringName, unscaled_pos: Vector3, prompt_text: String) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.position = _resolve_local_pos(unscaled_pos)
	root.scale = Vector3.ONE * visual_scale
	add_child(root)
	_barrel_nodes[kind] = root

	var it := Interactable.create(prompt_text, 0.42)
	it.name = node_name + "Interactable"
	it.reach = 2.6
	it.position = Vector3(0.0, 0.50, 0.0)
	it.interacted.connect(_on_barrel_interacted.bind(kind))
	root.add_child(it)
	_interactables[kind] = it
	return root


func _attach_mesh(parent: Node3D, node_name: String, am: ArrayMesh, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = am
	mi.material_override = mat
	parent.add_child(mi)
	_all_mesh_instances.append(mi)
	return mi


func _on_barrel_interacted(pawn: Node, kind: StringName) -> void:
	use_barrel(kind, pawn)


# ==============================================================================
# Shared WeakRef BC7 PBR Materials & Sculpted SurfaceTool ArrayMeshes (0 Primitives)
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


static func _make_pbr_mat(roughness: float, metallic: float, norm_path: String, rough_path: String,
		tri_scale: Vector3, norm_scale: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = roughness
	mat.metallic = metallic
	# Object-space triplanar mapping keeps wood/iron/brass grain locked cleanly to the moving hull.
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
		_oak_mat = _make_pbr_mat(0.78, 0.04, TEX_OAK_NORMAL, TEX_OAK_ROUGH, Vector3(1.9, 1.9, 1.9), 0.72)
	if _iron_mat == null:
		_iron_mat = _make_pbr_mat(0.44, 0.78, TEX_IRON_NORMAL, TEX_IRON_ROUGH, Vector3(2.4, 2.4, 2.4), 0.80)
	if _brass_mat == null:
		_brass_mat = _make_pbr_mat(0.28, 0.86, TEX_BRASS_NORMAL, TEX_BRASS_ROUGH, Vector3(2.6, 2.6, 2.6), 0.56)

	if _cannon_oak_mesh == null:
		_cannon_oak_mesh = _build_coopered_barrel_oak_mesh(COL_DARK_OAK_HI, COL_DARK_OAK_MID, COL_DARK_OAK_LO, true)
	if _plank_oak_mesh == null:
		_plank_oak_mesh = _build_coopered_barrel_oak_mesh(COL_OAK_HI, COL_OAK_MID, COL_OAK_LO, true)
	if _rations_oak_mesh == null:
		_rations_oak_mesh = _build_rations_barrel_oak_mesh()
	if _iron_hoops_mesh == null:
		_iron_hoops_mesh = _build_barrel_hoops_mesh(COL_IRON_HI, COL_IRON_MID, COL_IRON_LO)
	if _rations_brass_mesh == null:
		_rations_brass_mesh = _build_rations_brass_mesh()
	if _ammo_fill_mesh == null:
		_ammo_fill_mesh = _build_ammo_fill_mesh()
	if _plank_fill_mesh == null:
		_plank_fill_mesh = _build_plank_fill_mesh()


static func _barrel_radius_at(y: float) -> float:
	# Smooth bulging coopered bilge profile from chine (y=0.0) to belly (y=0.38) to rim (y=0.76).
	var t := clampf(y / 0.76, 0.0, 1.0)
	return 0.236 + 0.056 * sin(t * PI)


static func _append_coopered_stave_shell(
	st: SurfaceTool,
	col_hi: Color,
	col_mid: Color,
	col_lo: Color,
	open_top: bool
) -> void:
	const STAVES := 12
	const RAD_VERTS := STAVES * 2  # Alternating stave ridge & beveled seam groove
	const HEIGHTS: Array[float] = [0.0, 0.14, 0.38, 0.62, 0.76]

	# 1. Outer fluted coopered oak staves with per-stave subtle tonal warmth and vertical AO gradient.
	for hi in range(HEIGHTS.size() - 1):
		var y0 := HEIGHTS[hi]
		var y1 := HEIGHTS[hi + 1]
		var r0_base := _barrel_radius_at(y0)
		var r1_base := _barrel_radius_at(y1)
		var v0_t := y0 / 0.76
		var v1_t := y1 / 0.76
		for si in RAD_VERTS:
			var si1 := (si + 1) % RAD_VERTS
			var a0 := TAU * float(si) / float(RAD_VERTS)
			var a1 := TAU * float(si + 1) / float(RAD_VERTS)
			var am := (a0 + a1) * 0.5
			var mod0 := 1.016 if (si % 2 == 0) else 0.968
			var mod1 := 1.016 if (si1 % 2 == 0) else 0.968
			var p00 := Vector3(cos(a0) * r0_base * mod0, y0, sin(a0) * r0_base * mod0)
			var p10 := Vector3(cos(a1) * r0_base * mod1, y0, sin(a1) * r0_base * mod1)
			var p01 := Vector3(cos(a0) * r1_base * mod0, y1, sin(a0) * r1_base * mod0)
			var p11 := Vector3(cos(a1) * r1_base * mod1, y1, sin(a1) * r1_base * mod1)

			var stave_idx := floori(float(si) * 0.5)
			var stave_tint := col_hi if (stave_idx % 2 == 0) else col_mid
			var seam_dark := 0.84 if (si % 2 == 1) else 1.0
			var c0 := col_lo.lerp(stave_tint, 0.25 + 0.75 * v0_t) * seam_dark
			var c1 := col_lo.lerp(stave_tint, 0.25 + 0.75 * v1_t) * seam_dark
			c0.a = 1.0
			c1.a = 1.0
			var out_dir := Vector3(cos(am), 0.0, sin(am))
			_emit_quad_facing(st, p00, p10, p11, p01, out_dir, c0, c0, c1, c1)

	# 2. Bottom chine base disc (normal facing -Y).
	var bot_center := Vector3(0.0, 0.0, 0.0)
	var r_bot := _barrel_radius_at(0.0) * 0.985
	for i in STAVES:
		var a0 := TAU * float(i) / float(STAVES)
		var a1 := TAU * float(i + 1) / float(STAVES)
		var p0 := Vector3(cos(a0) * r_bot, 0.0, sin(a0) * r_bot)
		var p1 := Vector3(cos(a1) * r_bot, 0.0, sin(a1) * r_bot)
		_emit_tri_facing(st, bot_center, p0, p1, Vector3.DOWN, col_lo, col_lo, col_lo)

	# 3. Beveled top chine rim ring & recessed barrel interior (deep open well vs shallow cask head).
	var r_rim_out := _barrel_radius_at(0.76) * 0.995
	var r_rim_in := 0.200
	var inner_floor_y := 0.34 if open_top else 0.70
	var col_rim := col_hi.lerp(col_mid, 0.25)
	var col_in_top := col_mid.lerp(col_lo, 0.45)
	var col_in_bot := col_lo * 0.62
	col_in_bot.a = 1.0

	for i in STAVES:
		var a0 := TAU * float(i) / float(STAVES)
		var a1 := TAU * float(i + 1) / float(STAVES)
		var am := (a0 + a1) * 0.5
		var c_a0 := cos(a0)
		var s_a0 := sin(a0)
		var c_a1 := cos(a1)
		var s_a1 := sin(a1)

		# Flat beveled top chine ledge facing +Y.
		var ro0 := Vector3(c_a0 * r_rim_out, 0.76, s_a0 * r_rim_out)
		var ro1 := Vector3(c_a1 * r_rim_out, 0.76, s_a1 * r_rim_out)
		var ri0 := Vector3(c_a0 * r_rim_in, 0.755, s_a0 * r_rim_in)
		var ri1 := Vector3(c_a1 * r_rim_in, 0.755, s_a1 * r_rim_in)
		_emit_quad_facing(st, ro0, ro1, ri1, ri0, Vector3.UP, col_rim, col_rim, col_in_top, col_in_top)

		# Inner stave wall facing INWARD toward center axis!
		var rb0 := Vector3(c_a0 * (r_rim_in - 0.008), inner_floor_y, s_a0 * (r_rim_in - 0.008))
		var rb1 := Vector3(c_a1 * (r_rim_in - 0.008), inner_floor_y, s_a1 * (r_rim_in - 0.008))
		var in_dir := Vector3(-cos(am), 0.0, -sin(am))
		_emit_quad_facing(st, ri0, ri1, rb1, rb0, in_dir, col_in_top, col_in_top, col_in_bot, col_in_bot)

		# Interior floor / recessed cask head disc facing +Y.
		var fl_c := Vector3(0.0, inner_floor_y, 0.0)
		var fl_col := col_in_bot if open_top else col_mid
		_emit_tri_facing(st, fl_c, rb0, rb1, Vector3.UP, fl_col, fl_col, fl_col)


static func _build_coopered_barrel_oak_mesh(col_hi: Color, col_mid: Color, col_lo: Color, open_top: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_coopered_stave_shell(st, col_hi, col_mid, col_lo, open_top)
	st.generate_normals()
	return st.commit()


static func _build_rations_barrel_oak_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_coopered_stave_shell(st, COL_WARM_OAK_HI, COL_WARM_OAK_MID, COL_WARM_OAK_LO, false)

	# Carved circular-chamfered oak ration plank lid resting cleanly atop the rim (y = 0.76..0.798).
	_add_beveled_plank(st, Basis(Vector3.UP, 0.08), Vector3(0.0, 0.779, -0.095),
		Vector3(0.39, 0.036, 0.175), 0.008, COL_PLANK_HI, COL_WARM_OAK_MID, COL_WARM_OAK_LO)
	_add_beveled_plank(st, Basis(Vector3.UP, 0.08), Vector3(0.0, 0.779, 0.095),
		Vector3(0.39, 0.036, 0.175), 0.008, COL_WARM_OAK_HI, COL_WARM_OAK_MID, COL_WARM_OAK_LO)
	# Twin carved oak lid cross-battens & central grip rail.
	for bx: float in [-0.125, 0.125]:
		_add_oriented_box(st, Basis(Vector3.UP, 0.08), Vector3(bx, 0.806, 0.0), Vector3(0.038, 0.022, 0.32),
			COL_WARM_OAK_HI, COL_WARM_OAK_MID, COL_WARM_OAK_LO)
	# Carved oak hardtack & salt-pork ration crate / wrapped parcel resting on the aft half of the lid.
	_add_beveled_plank(st, Basis(Vector3.UP, -0.24), Vector3(-0.04, 0.842, -0.075),
		Vector3(0.165, 0.068, 0.125), 0.012, COL_RATION_CLOTH_HI, COL_RATION_CLOTH_LO, COL_WARM_OAK_LO)
	# Small chamfered oak tap-block cleat reinforcing the +X spigot boss.
	_add_oriented_box(st, Basis.IDENTITY, Vector3(0.285, 0.36, 0.0), Vector3(0.026, 0.095, 0.095),
		COL_WARM_OAK_HI, COL_WARM_OAK_MID, COL_WARM_OAK_LO)

	st.generate_normals()
	return st.commit()


static func _append_barrel_hoops(st: SurfaceTool, col_hi: Color, col_mid: Color, col_lo: Color) -> void:
	const HOOP_YS: Array[float] = [0.08, 0.25, 0.51, 0.68]
	const SEGS := 12
	for hy: float in HOOP_YS:
		var r_base := _barrel_radius_at(hy)
		var r_in := r_base + 0.002
		var r_out := r_base + 0.014
		var hh := 0.022
		# Beveled 3-band ring profile around the coopered barrel waist.
		var prof: Array[Vector2] = [
			Vector2(r_in, hy - hh),
			Vector2(r_out, hy - hh * 0.70),
			Vector2(r_out, hy + hh * 0.70),
			Vector2(r_in, hy + hh),
		]
		for pi in range(prof.size() - 1):
			var r0 := prof[pi].x
			var y0 := prof[pi].y
			var r1 := prof[pi + 1].x
			var y1 := prof[pi + 1].y
			var c0 := col_lo if pi == 0 else (col_mid if pi == 1 else col_hi)
			var c1 := col_mid if pi == 0 else col_hi
			for s in SEGS:
				var a0 := TAU * float(s) / float(SEGS)
				var a1 := TAU * float(s + 1) / float(SEGS)
				var am := (a0 + a1) * 0.5
				var p00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
				var p10 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
				var p01 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
				var p11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
				var out_dir := Vector3(cos(am), 0.35 if pi == 2 else (-0.35 if pi == 0 else 0.0), sin(am)).normalized()
				_emit_quad_facing(st, p00, p10, p11, p01, out_dir, c0, c0, c1, c1)

		# Twin forged rivet-seam overlap lugs gripping opposite sides of each hoop.
		for lug_ang: float in [0.45, PI + 0.45]:
			var b := Basis(Vector3.UP, lug_ang)
			var lug_pos := b * Vector3(r_out + 0.004, hy, 0.0)
			_add_oriented_box(st, b, lug_pos, Vector3(0.014, 0.048, 0.036), col_hi, col_mid, col_lo)


static func _build_barrel_hoops_mesh(col_hi: Color, col_mid: Color, col_lo: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_barrel_hoops(st, col_hi, col_mid, col_lo)
	st.generate_normals()
	return st.commit()


static func _build_rations_brass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Four gleaming turned brass cask hoops with rivet seam lugs.
	_append_barrel_hoops(st, COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)

	# 2. Turned brass tap spigot mounted on the inboard +X belly (facing the hold walkway!).
	# Escutcheon rosette collar flush against the oak tap block.
	_add_tube(st, Vector3(0.288, 0.36, 0.0), Vector3(0.315, 0.36, 0.0), 0.042, 0.032, 8, COL_BRASS_HI, COL_BRASS_LO)
	# Horizontal tapered spigot barrel extending cleanly outboard into the aisle.
	_add_tube(st, Vector3(0.312, 0.36, 0.0), Vector3(0.425, 0.36, 0.0), 0.022, 0.017, 8, COL_BRASS_HI, COL_BRASS_MID)
	# Vertical valve housing + turned T-handle crossbar atop the spigot.
	_add_tube(st, Vector3(0.375, 0.365, 0.0), Vector3(0.375, 0.435, 0.0), 0.016, 0.012, 8, COL_BRASS_HI, COL_BRASS_LO)
	_add_tube(st, Vector3(0.375, 0.435, -0.048), Vector3(0.375, 0.435, 0.048), 0.010, 0.010, 6, COL_BRASS_HI, COL_BRASS_MID)
	# Downward curved pour spout nose.
	_add_tube(st, Vector3(0.418, 0.360, 0.0), Vector3(0.432, 0.312, 0.0), 0.015, 0.011, 8, COL_BRASS_HI, COL_BRASS_LO)

	# 3. Sculpted brass drip mug resting cleanly atop the carved ration lid (+X, +Z side).
	var mug_base := Vector3(0.085, 0.798, 0.068)
	var mug_prof: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(0.056, 0.0),
		Vector2(0.060, 0.012),
		Vector2(0.054, 0.024),
		Vector2(0.058, 0.082),
		Vector2(0.052, 0.128),
		Vector2(0.058, 0.138),
		Vector2(0.046, 0.138),
	]
	_add_lathe_at(st, mug_base, mug_prof, 10, COL_BRASS_LO, COL_BRASS_HI)
	# Recessed mug interior floor + wall so the tankard reads hollow from above.
	var mug_in_y := mug_base.y + 0.092
	var mug_top_y := mug_base.y + 0.138
	for i in 10:
		var a0 := TAU * float(i) / 10.0
		var a1 := TAU * float(i + 1) / 10.0
		var am := (a0 + a1) * 0.5
		var p0t := mug_base + Vector3(cos(a0) * 0.046, mug_top_y - mug_base.y, sin(a0) * 0.046)
		var p1t := mug_base + Vector3(cos(a1) * 0.046, mug_top_y - mug_base.y, sin(a1) * 0.046)
		var p0b := mug_base + Vector3(cos(a0) * 0.042, mug_in_y - mug_base.y, sin(a0) * 0.042)
		var p1b := mug_base + Vector3(cos(a1) * 0.042, mug_in_y - mug_base.y, sin(a1) * 0.042)
		_emit_quad_facing(st, p0t, p1t, p1b, p0b, Vector3(-cos(am), 0.0, -sin(am)),
			COL_BRASS_LO, COL_BRASS_LO, COL_WARM_OAK_LO, COL_WARM_OAK_LO)
		_emit_tri_facing(st, Vector3(mug_base.x, mug_in_y, mug_base.z), p0b, p1b, Vector3.UP,
			COL_WARM_OAK_LO, COL_WARM_OAK_LO, COL_WARM_OAK_LO)
	# Curved brass D-handle on the +X side of the drip mug.
	var h0 := mug_base + Vector3(0.052, 0.112, 0.0)
	var h1 := mug_base + Vector3(0.095, 0.104, 0.0)
	var h2 := mug_base + Vector3(0.096, 0.042, 0.0)
	var h3 := mug_base + Vector3(0.055, 0.032, 0.0)
	_add_tube(st, h0, h1, 0.0085, 0.0085, 6, COL_BRASS_HI, COL_BRASS_MID)
	_add_tube(st, h1, h2, 0.0085, 0.0085, 6, COL_BRASS_HI, COL_BRASS_MID)
	_add_tube(st, h2, h3, 0.0085, 0.0085, 6, COL_BRASS_MID, COL_BRASS_LO)

	# Decorative brass lid straps pinning the carved ration lid boards.
	for sx: float in [-0.125, 0.125]:
		_add_oriented_box(st, Basis(Vector3.UP, 0.08), Vector3(sx, 0.819, 0.0), Vector3(0.022, 0.008, 0.30),
			COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)

	st.generate_normals()
	return st.commit()


static func _build_ammo_fill_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 7 sculpted faceted cast-iron cannonballs nested in a tight 2-tier pyramid crowning the barrel mouth.
	var ball_r := 0.084
	# Lower ring of 4 roundshot nestled inside the upper barrel mouth (y = 0.655).
	for i in 4:
		var a := float(i) * PI * 0.5 + 0.35
		var pos := Vector3(cos(a) * 0.102, 0.655, sin(a) * 0.102)
		_add_faceted_sphere(st, pos, ball_r, 8, 4, COL_SHOT_HI, COL_SHOT_MID, COL_SHOT_LO)

	# Upper crown of 3 roundshot peeking proudly above the coopered rim (y = 0.775).
	for i in 3:
		var a := float(i) * (TAU / 3.0) + 0.55
		var pos := Vector3(cos(a) * 0.072, 0.775, sin(a) * 0.072)
		_add_faceted_sphere(st, pos, ball_r * 0.96, 8, 4, COL_SHOT_HI, COL_SHOT_MID, COL_SHOT_LO)

	st.generate_normals()
	return st.commit()


static func _build_plank_fill_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 6 distinct beveled oak repair planks angled cleanly out of the open top in a varied shipwright sheaf.
	var plank_specs: Array[Array] = [
		# [center, size, rot_deg, shade_idx]
		[Vector3(-0.075, 0.74, -0.055), Vector3(0.115, 0.72, 0.032), Vector3(11.0, 18.0, 9.0), 0],
		[Vector3(0.068, 0.77, -0.068), Vector3(0.118, 0.76, 0.032), Vector3(13.0, -24.0, -10.0), 1],
		[Vector3(-0.062, 0.79, 0.072), Vector3(0.112, 0.80, 0.030), Vector3(-12.0, 34.0, 8.0), 2],
		[Vector3(0.078, 0.73, 0.062), Vector3(0.116, 0.70, 0.032), Vector3(-10.0, -32.0, -12.0), 0],
		[Vector3(0.008, 0.82, 0.005), Vector3(0.122, 0.84, 0.034), Vector3(6.0, 62.0, -5.0), 1],
		[Vector3(-0.015, 0.75, -0.095), Vector3(0.106, 0.73, 0.028), Vector3(14.0, 84.0, 6.0), 2],
	]
	for spec: Array in plank_specs:
		var pos: Vector3 = spec[0] as Vector3
		var sz: Vector3 = spec[1] as Vector3
		var rdeg: Vector3 = spec[2] as Vector3
		var shade_i: int = int(spec[3])
		var plank_basis := Basis.from_euler(Vector3(deg_to_rad(rdeg.x), deg_to_rad(rdeg.y), deg_to_rad(rdeg.z)))
		var c_hi := COL_PLANK_HI if shade_i == 0 else (COL_OAK_HI if shade_i == 1 else COL_WARM_OAK_HI)
		var c_mid := COL_PLANK_MID if shade_i == 0 else (COL_OAK_MID if shade_i == 1 else COL_WARM_OAK_MID)
		var c_lo := COL_PLANK_LO if shade_i == 0 else COL_OAK_LO
		_add_beveled_plank(st, plank_basis, pos, sz, 0.007, c_hi, c_mid, c_lo)
		# Small cross-cleat batten near the upper third of each repair plank for instant silhouette read.
		var cleat_off := plank_basis * Vector3(0.0, sz.y * 0.24, 0.0)
		_add_oriented_box(st, plank_basis, pos + cleat_off, Vector3(sz.x + 0.008, 0.034, sz.z + 0.010),
			COL_OAK_MID, COL_OAK_LO, COL_DARK_OAK_LO)

	st.generate_normals()
	return st.commit()


# ==============================================================================
# Sculpted Flat-Faceted Geometry Helpers (Outward-Wound SurfaceTool Primitives)
# ==============================================================================

static func _add_faceted_sphere(
	st: SurfaceTool,
	center: Vector3,
	radius: float,
	segs: int,
	rings: int,
	col_hi: Color,
	col_mid: Color,
	col_lo: Color
) -> void:
	for ri in rings:
		var phi0 := PI * float(ri) / float(rings)
		var phi1 := PI * float(ri + 1) / float(rings)
		var y0 := cos(phi0) * radius
		var r0 := sin(phi0) * radius
		var y1 := cos(phi1) * radius
		var r1 := sin(phi1) * radius
		var t0 := clampf(0.5 + 0.5 * cos(phi0), 0.0, 1.0)
		var t1 := clampf(0.5 + 0.5 * cos(phi1), 0.0, 1.0)
		var c0 := col_lo.lerp(col_hi, t0) if t0 >= 0.5 else col_lo.lerp(col_mid, t0 * 2.0)
		var c1 := col_lo.lerp(col_hi, t1) if t1 >= 0.5 else col_lo.lerp(col_mid, t1 * 2.0)
		for si in segs:
			var a0 := TAU * float(si) / float(segs)
			var a1 := TAU * float(si + 1) / float(segs)
			var p00 := center + Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p10 := center + Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p01 := center + Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := center + Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			if ri == 0:
				var avg_d := ((p00 + p01 + p11) / 3.0 - center).normalized()
				_emit_tri_facing(st, p00, p01, p11, avg_d, c0, c1, c1)
			elif ri == rings - 1:
				var avg_d := ((p00 + p10 + p01) / 3.0 - center).normalized()
				_emit_tri_facing(st, p00, p10, p01, avg_d, c0, c0, c1)
			else:
				var avg_d := ((p00 + p10 + p11 + p01) * 0.25 - center).normalized()
				_emit_quad_facing(st, p00, p10, p11, p01, avg_d, c0, c0, c1, c1)


static func _add_beveled_plank(
	st: SurfaceTool,
	rot_basis: Basis,
	center: Vector3,
	size: Vector3,
	bevel: float,
	col_top: Color,
	col_side: Color,
	col_bot: Color
) -> void:
	# Chamfered octagonal-section plank prism along local Y (3 rings: chamfered bottom, body, chamfered top).
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var b := minf(bevel, minf(hx, minf(hy, hz)) * 0.45)

	# Core box + subtle tapered chamfer caps at +Y and -Y ends.
	_add_oriented_box(st, rot_basis, center, Vector3(size.x, size.y - b * 2.0, size.z), col_top, col_side, col_bot)

	var top_in_x := hx - b
	var top_in_z := hz - b
	var outer_top: Array[Vector3] = [
		center + rot_basis * Vector3(-hx, hy - b, -hz),
		center + rot_basis * Vector3(hx, hy - b, -hz),
		center + rot_basis * Vector3(hx, hy - b, hz),
		center + rot_basis * Vector3(-hx, hy - b, hz),
	]
	var inner_top: Array[Vector3] = [
		center + rot_basis * Vector3(-top_in_x, hy, -top_in_z),
		center + rot_basis * Vector3(top_in_x, hy, -top_in_z),
		center + rot_basis * Vector3(top_in_x, hy, top_in_z),
		center + rot_basis * Vector3(-top_in_x, hy, top_in_z),
	]
	var outer_bot: Array[Vector3] = [
		center + rot_basis * Vector3(-hx, -hy + b, -hz),
		center + rot_basis * Vector3(hx, -hy + b, -hz),
		center + rot_basis * Vector3(hx, -hy + b, hz),
		center + rot_basis * Vector3(-hx, -hy + b, hz),
	]
	var inner_bot: Array[Vector3] = [
		center + rot_basis * Vector3(-top_in_x, -hy, -top_in_z),
		center + rot_basis * Vector3(top_in_x, -hy, -top_in_z),
		center + rot_basis * Vector3(top_in_x, -hy, top_in_z),
		center + rot_basis * Vector3(-top_in_x, -hy, top_in_z),
	]
	var up_dir := rot_basis.y.normalized()
	_emit_quad_facing(st, inner_top[0], inner_top[1], inner_top[2], inner_top[3], up_dir, col_top, col_top, col_top, col_top)
	_emit_quad_facing(st, inner_bot[0], inner_bot[1], inner_bot[2], inner_bot[3], -up_dir, col_bot, col_bot, col_bot, col_bot)
	for i in 4:
		var i1 := (i + 1) % 4
		var mid_t := (outer_top[i] + outer_top[i1] + inner_top[i1] + inner_top[i]) * 0.25
		_emit_quad_facing(st, outer_top[i], outer_top[i1], inner_top[i1], inner_top[i],
			(mid_t - center).normalized(), col_side, col_side, col_top, col_top)
		var mid_b := (outer_bot[i] + outer_bot[i1] + inner_bot[i1] + inner_bot[i]) * 0.25
		_emit_quad_facing(st, outer_bot[i], outer_bot[i1], inner_bot[i1], inner_bot[i],
			(mid_b - center).normalized(), col_side, col_side, col_bot, col_bot)


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
				_emit_tri_facing(st, p00, p01, p11, ((p00 + p01 + p11) / 3.0 - ref_c).normalized(), c0, c1, c1)
			elif r1 <= 0.0004 and r0 > 0.0004:
				_emit_tri_facing(st, p00, p10, p01, ((p00 + p10 + p01) / 3.0 - ref_c).normalized(), c0, c0, c1)
			elif r0 > 0.0004 and r1 > 0.0004:
				var am := (a0 + a1) * 0.5
				var dy := y1 - y0
				var dr := r1 - r0
				var out_d := Vector3(cos(am) * dy, -dr, sin(am) * dy)
				if out_d.length_squared() < 1e-8:
					out_d = ((p00 + p10 + p11 + p01) * 0.25 - ref_c)
				_emit_quad_facing(st, p00, p10, p11, p01, out_d.normalized(), c0, c0, c1, c1)


static func _add_tube(st: SurfaceTool, p0: Vector3, p1: Vector3, r0: float, r1: float,
		segs: int, col_hi: Color, col_lo: Color) -> void:
	var axis := p1 - p0
	if axis.length_squared() < 1e-10:
		return
	var dir := axis.normalized()
	var up_ref := Vector3.UP if absf(dir.y) < 0.92 else Vector3.RIGHT
	var u := dir.cross(up_ref).normalized()
	var v := dir.cross(u).normalized()
	for s in segs:
		var a0 := TAU * float(s) / float(segs)
		var a1 := TAU * float(s + 1) / float(segs)
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		var dm := (d0 + d1).normalized()
		var c0 := col_lo.lerp(col_hi, clampf(0.5 + 0.5 * d0.y, 0.0, 1.0))
		var c1 := col_lo.lerp(col_hi, clampf(0.5 + 0.5 * d1.y, 0.0, 1.0))
		var v00 := p0 + d0 * r0
		var v10 := p0 + d1 * r0
		var v01 := p1 + d0 * r1
		var v11 := p1 + d1 * r1
		_emit_quad_facing(st, v00, v10, v11, v01, dm, c0, c1, c1, c0)
		_emit_tri_facing(st, p0, v00, v10, -dir, col_lo, c0, c1)
		_emit_tri_facing(st, p1, v11, v01, dir, col_hi, c1, c0)


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
	var rx := rot_basis.x.normalized()
	var ry := rot_basis.y.normalized()
	var rz := rot_basis.z.normalized()
	_emit_quad_facing(st, c[3], c[2], c[6], c[7], ry, col_top, col_top, col_top, col_top)
	_emit_quad_facing(st, c[4], c[5], c[1], c[0], -ry, col_bot, col_bot, col_bot, col_bot)
	_emit_quad_facing(st, c[0], c[1], c[2], c[3], -rz, col_bot, col_bot, col_side, col_side)
	_emit_quad_facing(st, c[5], c[4], c[7], c[6], rz, col_bot, col_bot, col_side, col_side)
	_emit_quad_facing(st, c[4], c[0], c[3], c[7], -rx, col_bot, col_bot, col_side, col_side)
	_emit_quad_facing(st, c[1], c[5], c[6], c[2], rx, col_bot, col_bot, col_side, col_side)


static func _emit_quad_facing(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		desired_dir: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_emit_tri_facing(st, a, b, c, desired_dir, ca, cb, cc)
	_emit_tri_facing(st, a, c, d, desired_dir, ca, cc, cd)


static func _emit_tri_facing(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		desired_dir: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	if desired_dir.length_squared() > 1e-12 and n.dot(desired_dir) < 0.0:
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
