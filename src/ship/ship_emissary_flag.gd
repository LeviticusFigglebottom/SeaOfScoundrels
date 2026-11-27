class_name ShipEmissaryFlag
extends Node3D
## Sculpted starboard-quarter stern Trading Company Emissary Flag & Grade Pennants.
##
## Features 100% sculpted flat-faceted `SurfaceTool` `ArrayMesh` geometry (zero raw
## `PrimitiveMesh`es, >= 520 tris) using WeakRef-cached shared ship BC7 PBR
## normal/roughness maps (object-space triplanar mapping, `uv1_world_triplanar = false`,
## zero extra VRAM) and ref-counted leak-free static cache teardown.
##
## Mounted cleanly on the STARBOARD quarter stern taffrail (clear of port FishingLine,
## stern Rowboat, ShipNameplate, and Helm):
## - Beveled oak taffrail socket clamp & tapered 2.55 m wooden stern flagstaff
## - Turned brass clamping straps, decorative collars, grommets & spearhead finial
## - Billowing swallowtail company banner (Gilded Compass, Sunken Archive, Iron Tide)
## - 5 sculpted gilded brass Grade Pennant Ribbons (`_grade_pennants[0..4]`) stepped
##   down the mast below the main banner, displaying exactly `grade` (1..5) pennants.

const SLOOP_STAFF_LOCAL := Vector3(1.53, 3.16, 5.65)
const BRIG_STAFF_LOCAL := Vector3(1.85, 3.65, 7.15)

const STAFF_HEIGHT := 2.55
const BANNER_PIVOT_Y := 1.98
const GRADE_PENNANT_HEIGHTS: Array[float] = [1.44, 1.24, 1.04, 0.84, 0.64]

const TEX_OAK_NORMAL := "res://assets/generated/textures/ship_oak_normal.png"
const TEX_OAK_ROUGH := "res://assets/generated/textures/ship_oak_rough.png"
const TEX_BRASS_NORMAL := "res://assets/generated/textures/ship_brass_normal.png"
const TEX_BRASS_ROUGH := "res://assets/generated/textures/ship_brass_rough.png"
const TEX_CLOTH_NORMAL := "res://assets/generated/textures/ship_cloth_normal.png"

# sRGB-calibrated painterly nautical palettes.
const COL_OAK_HI := Color(0.56, 0.38, 0.21)
const COL_OAK_MID := Color(0.40, 0.26, 0.14)
const COL_OAK_LO := Color(0.22, 0.14, 0.07)

const COL_BRASS_HI := Color(0.98, 0.82, 0.34)
const COL_BRASS_MID := Color(0.79, 0.59, 0.20)
const COL_BRASS_LO := Color(0.46, 0.32, 0.10)

# Company banner palettes: [primary_hi, primary_lo, trim_hi, trim_lo, emblem_col]
const COMPANY_PALETTES := {
	&"gilded_compass": [
		Color(0.92, 0.72, 0.20),
		Color(0.68, 0.46, 0.10),
		Color(0.76, 0.16, 0.14),
		Color(0.48, 0.08, 0.09),
		Color(1.00, 0.88, 0.40),
	],
	&"sunken_archive": [
		Color(0.14, 0.54, 0.58),
		Color(0.08, 0.32, 0.38),
		Color(0.90, 0.84, 0.68),
		Color(0.66, 0.58, 0.44),
		Color(0.32, 0.90, 0.82),
	],
	&"iron_tide": [
		Color(0.66, 0.14, 0.15),
		Color(0.36, 0.07, 0.09),
		Color(0.86, 0.66, 0.22),
		Color(0.48, 0.34, 0.10),
		Color(0.96, 0.78, 0.30),
	],
}

const GRADE_MOTE_COUNT := 10
const GRADE_MOTE_VISIBILITY_RANGE := 220.0

# Company Grade IV-V prestige aura sparkle palettes: [primary_glow, accent_spark] (sRGB).
const COMPANY_AURA_COLORS := {
	&"gilded_compass": [Color(1.00, 0.84, 0.28, 1.0), Color(1.00, 0.96, 0.68, 1.0)],
	&"sunken_archive": [Color(0.18, 0.94, 0.86, 1.0), Color(0.68, 1.00, 0.96, 1.0)],
	&"iron_tide": [Color(1.00, 0.42, 0.14, 1.0), Color(1.00, 0.80, 0.28, 1.0)],
}

@export var ship_class: StringName = &"sloop"

var active_company: StringName = &""
var emissary_grade: int = 0

var _built: bool = false
var _oak_mi: MeshInstance3D = null
var _brass_mi: MeshInstance3D = null
var _banner_pivot: Node3D = null
var _banner_mi: MeshInstance3D = null
var _grade_pennants: Array[MeshInstance3D] = []
var _all_mesh_instances: Array[MeshInstance3D] = []
var _grade_motes: MultiMeshInstance3D = null
var _grade_motes_mm: MultiMesh = null
var _grade_motes_mat: StandardMaterial3D = null
var _mote_clock: float = 0.0
var _mote_phase_off: PackedFloat32Array = PackedFloat32Array()
var _mote_y_off: PackedFloat32Array = PackedFloat32Array()
var _mote_x_amp: PackedFloat32Array = PackedFloat32Array()
var _mote_speed_mul: PackedFloat32Array = PackedFloat32Array()
var _mote_spin_rate: PackedFloat32Array = PackedFloat32Array()
var _mote_positions: PackedVector3Array = PackedVector3Array()
var _mote_colors: PackedColorArray = PackedColorArray()
var _mote_primary_col: Color = Color(1.00, 0.84, 0.28, 1.0)
var _mote_accent_col: Color = Color(1.00, 0.96, 0.68, 1.0)
var _flutter_time: float = 0.0
var _current_wind_yaw: float = 0.0

# Ref-counted static sculpted ArrayMesh & shared PBR material caches (zero ObjectDB leaks).
static var _active_instances: int = 0
static var _pbr_tex_cache: Dictionary = {}  # String path -> WeakRef(Texture2D)
static var _oak_mesh: ArrayMesh = null
static var _brass_mesh: ArrayMesh = null
static var _pennant_mesh: ArrayMesh = null
static var _mote_mesh: ArrayMesh = null
static var _banner_meshes: Dictionary = {}  # StringName company_id -> ArrayMesh
static var _oak_mat: StandardMaterial3D = null
static var _brass_mat: StandardMaterial3D = null
static var _cloth_mat: StandardMaterial3D = null


## Mount (or reuse) a sculpted stern starboard-quarter `ShipEmissaryFlag` onto `ship`.
static func mount_to_ship(ship: Node3D) -> ShipEmissaryFlag:
	if ship == null or not is_instance_valid(ship):
		return null
	var existing := ship.get_node_or_null(^"ShipEmissaryFlag") as ShipEmissaryFlag
	if existing != null:
		return existing

	var flag := ShipEmissaryFlag.new()
	flag.name = "ShipEmissaryFlag"
	var cls_v: Variant = ship.get(&"ship_class")
	var is_brig := (cls_v is StringName and (cls_v as StringName) == &"brigantine")
	flag.ship_class = &"brigantine" if is_brig else &"sloop"

	var hs_v: Variant = ship.get(&"hull_scale")
	var hs := float(hs_v) if (hs_v != null and float(hs_v) > 0.01) else 1.0
	var base_local := BRIG_STAFF_LOCAL if is_brig else SLOOP_STAFF_LOCAL
	if ship.has_method(&"ship_point"):
		flag.position = ship.call(&"ship_point", base_local) as Vector3
	else:
		flag.position = base_local * hs
	flag.scale = Vector3.ONE * hs
	ship.add_child(flag)
	return flag


## Release all statically cached flag ArrayMeshes, PBR materials, and WeakRef textures cleanly.
static func clear_shared_cache() -> void:
	for mat: StandardMaterial3D in [_oak_mat, _brass_mat, _cloth_mat]:
		if mat != null:
			mat.normal_texture = null
			mat.roughness_texture = null
	_oak_mesh = null
	_brass_mesh = null
	_pennant_mesh = null
	_mote_mesh = null
	_banner_meshes.clear()
	_oak_mat = null
	_brass_mat = null
	_cloth_mat = null
	_pbr_tex_cache.clear()


func _enter_tree() -> void:
	_active_instances += 1


func _ready() -> void:
	_ensure_built()
	set_emissary(active_company, emissary_grade)


func _exit_tree() -> void:
	_release_mesh_refs()
	_active_instances = maxi(0, _active_instances - 1)
	if _active_instances == 0:
		clear_shared_cache()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_release_mesh_refs()


func _process(delta: float) -> void:
	if not visible or _banner_pivot == null or not is_instance_valid(_banner_pivot):
		return
	var dt := maxf(0.0, delta)
	var wind_spd := Weather.local_wind_speed() if Weather != null else 8.0
	_flutter_time = fmod(_flutter_time + dt * (3.6 + wind_spd * 0.26), TAU * 100.0)

	var wind_heading := Weather.wind_heading if Weather != null else 0.0
	var world_wind := Vector3(sin(wind_heading), 0.0, -cos(wind_heading))
	var local_wind := world_wind
	if is_inside_tree():
		local_wind = global_transform.basis.inverse() * world_wind
	var target_yaw := atan2(local_wind.x, local_wind.z)
	if Vector2(local_wind.x, local_wind.z).length_squared() < 0.0001:
		target_yaw = 0.0

	var blend := clampf(dt * 4.5, 0.0, 1.0)
	_current_wind_yaw = lerp_angle(_current_wind_yaw, target_yaw, blend) if dt > 0.0 else target_yaw
	var wind_gust := sin(_flutter_time * 1.45) * 0.11 + sin(_flutter_time * 3.15) * 0.045
	_banner_pivot.rotation.y = _current_wind_yaw + wind_gust

	if _banner_mi != null and is_instance_valid(_banner_mi):
		_banner_mi.rotation.y = sin(_flutter_time * 2.35) * 0.07
		_banner_mi.rotation.z = sin(_flutter_time * 1.85 + 0.6) * 0.045

	for i in _grade_pennants.size():
		var pen := _grade_pennants[i]
		if pen != null and is_instance_valid(pen) and pen.visible:
			pen.rotation.y = sin(_flutter_time * 2.85 + float(i) * 0.85) * 0.13
			pen.rotation.z = sin(_flutter_time * 2.15 + float(i) * 1.10) * 0.055

	if is_grade_aura_active():
		tick_grade_motes(dt)


# ==============================================================================
# Public Emissary API & Introspection
# ==============================================================================

## Show or hide the stern Emissary flag, tint banner to `company_id`, and display `grade` (1..5) pennants.
func set_emissary(company_id: StringName, grade: int) -> void:
	_ensure_built()
	active_company = company_id
	emissary_grade = clampi(grade, 0, 5)
	if emissary_grade <= 0 or active_company == &"":
		visible = false
		for pen: MeshInstance3D in _grade_pennants:
			if pen != null and is_instance_valid(pen):
				pen.visible = false
		if _grade_motes != null and is_instance_valid(_grade_motes):
			_grade_motes.visible = false
		return

	visible = true
	if _banner_mi != null and is_instance_valid(_banner_mi):
		_banner_mi.mesh = _get_banner_mesh(active_company)
	for i in _grade_pennants.size():
		var pen := _grade_pennants[i]
		if pen != null and is_instance_valid(pen):
			pen.visible = (i < emissary_grade)

	var aura_pal: Array = COMPANY_AURA_COLORS.get(active_company, COMPANY_AURA_COLORS[&"gilded_compass"])
	_mote_primary_col = aura_pal[0] as Color
	_mote_accent_col = aura_pal[1] as Color
	if is_grade_aura_active():
		tick_grade_motes(0.0)
	elif _grade_motes != null and is_instance_valid(_grade_motes):
		_grade_motes.visible = false


## Return total sculpted triangle count across all mounted flag MeshInstance3Ds.
func get_triangle_count() -> int:
	_ensure_built()
	var total := 0
	for mi: MeshInstance3D in _all_mesh_instances:
		if mi != null and is_instance_valid(mi) and mi.mesh is ArrayMesh:
			total += _count_mesh_tris(mi.mesh as ArrayMesh)
	return total


## Return exact number of currently visible gilded brass Grade Pennant Ribbons (0..5).
func get_visible_grade_pennants() -> int:
	if not visible:
		return 0
	var count := 0
	for pen: MeshInstance3D in _grade_pennants:
		if pen != null and is_instance_valid(pen) and pen.visible:
			count += 1
	return count


## Return the MultiMeshInstance3D rendering the 10 Grade IV-V prestige diamond sparkles.
func get_grade_motes_node() -> MultiMeshInstance3D:
	return _grade_motes


## Return the pre-allocated local-space positions of the 10 prestige sparkles (headless-safe).
func get_grade_mote_positions() -> PackedVector3Array:
	return _mote_positions


## Return the pre-allocated instance colors of the 10 prestige sparkles (headless-safe).
func get_grade_mote_colors() -> PackedColorArray:
	return _mote_colors


## True while the vessel flies a prestigious Grade IV or V Emissary Flag aura.
func is_grade_aura_active() -> bool:
	return visible and active_company != &"" and emissary_grade >= 4


## Advance the 10 company-colored prestige sparkles streaming downwind off the stern banner (0 allocations).
func tick_grade_motes(delta: float) -> void:
	if _grade_motes == null or not is_instance_valid(_grade_motes) or _grade_motes_mm == null:
		return
	if not is_grade_aura_active():
		_grade_motes.visible = false
		return

	_grade_motes.visible = true
	var dt := maxf(0.0, delta)
	var is_g5 := (emissary_grade >= 5)
	var speed_base := 0.92 if is_g5 else 0.55
	var bright_mul := 1.18 if is_g5 else 0.72
	var scale_mul := 1.22 if is_g5 else 0.92
	_mote_clock = fmod(_mote_clock + dt * speed_base, 1000.0)

	if _grade_motes_mat != null:
		var mat_tint := _mote_primary_col.lerp(Color.WHITE, 0.50)
		_grade_motes_mat.albedo_color = Color(mat_tint.r, mat_tint.g, mat_tint.b, 1.0)

	for i in GRADE_MOTE_COUNT:
		var phase := fposmod(_mote_clock * _mote_speed_mul[i] + _mote_phase_off[i], 1.0)
		var env := smoothstep(0.0, 0.16, phase) * smoothstep(0.0, 0.30, 1.0 - phase)
		var z := lerpf(0.26, 2.32, phase)
		var sway := phase * TAU + _mote_phase_off[i] * TAU
		var x := sin(sway * 1.15) * _mote_x_amp[i] * (0.35 + 0.65 * phase)
		var y := _mote_y_off[i] + sin(sway) * 0.10 + phase * 0.24
		var sc := maxf(0.02, lerpf(0.45, 1.15, env) * scale_mul)
		var rot_y := _mote_clock * _mote_spin_rate[i] + float(i) * 0.7
		var rot_x := rot_y * 0.65
		var mote_pos := Vector3(x, y, z)
		var mote_basis := Basis.from_euler(Vector3(rot_x, rot_y, 0.0)).scaled(Vector3(sc, sc, sc))
		_mote_positions[i] = mote_pos
		_grade_motes_mm.set_instance_transform(i, Transform3D(mote_basis, mote_pos))

		var accent_t := 0.5 + 0.5 * sin(sway * 1.7 + float(i))
		var base_c := _mote_primary_col.lerp(_mote_accent_col, accent_t)
		var lum := env * bright_mul
		var mote_col := Color(base_c.r * lum, base_c.g * lum, base_c.b * lum, 1.0)
		_mote_colors[i] = mote_col
		_grade_motes_mm.set_instance_color(i, mote_col)


# ==============================================================================
# Hierarchy Construction & Teardown
# ==============================================================================

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_ensure_shared_assets()

	_oak_mi = _add_mesh_node(self, "EmissaryStaffOak", _oak_mesh, _oak_mat)
	_brass_mi = _add_mesh_node(self, "EmissaryStaffBrass", _brass_mesh, _brass_mat)

	_banner_pivot = Node3D.new()
	_banner_pivot.name = "EmissaryWindPivot"
	add_child(_banner_pivot)

	var default_banner := _get_banner_mesh(&"gilded_compass")
	_banner_mi = _add_mesh_node(_banner_pivot, "CompanySwallowtailBanner", default_banner, _cloth_mat)
	_banner_mi.position = Vector3(0.0, BANNER_PIVOT_Y, 0.0)

	_grade_pennants.clear()
	for i in GRADE_PENNANT_HEIGHTS.size():
		var pen := _add_mesh_node(_banner_pivot, "GradePennant_%d" % (i + 1), _pennant_mesh, _brass_mat)
		pen.position = Vector3(0.0, GRADE_PENNANT_HEIGHTS[i], 0.0)
		pen.visible = false
		_grade_pennants.append(pen)

	_build_grade_motes()
	visible = false


func _build_grade_motes() -> void:
	_grade_motes_mat = StandardMaterial3D.new()
	_grade_motes_mat.vertex_color_use_as_albedo = true
	_grade_motes_mat.vertex_color_is_srgb = true
	_grade_motes_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_grade_motes_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_grade_motes_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_grade_motes_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_grade_motes_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)

	var rng := RandomNumberGenerator.new()
	rng.seed = 0xE115A415
	_mote_phase_off.resize(GRADE_MOTE_COUNT)
	_mote_y_off.resize(GRADE_MOTE_COUNT)
	_mote_x_amp.resize(GRADE_MOTE_COUNT)
	_mote_speed_mul.resize(GRADE_MOTE_COUNT)
	_mote_spin_rate.resize(GRADE_MOTE_COUNT)
	_mote_positions.resize(GRADE_MOTE_COUNT)
	_mote_colors.resize(GRADE_MOTE_COUNT)
	for i in GRADE_MOTE_COUNT:
		var base_p := (float(i) + 0.5) / float(GRADE_MOTE_COUNT)
		_mote_phase_off[i] = clampf(base_p + rng.randf_range(-0.025, 0.025), 0.04, 0.94)
		_mote_y_off[i] = rng.randf_range(-0.30, 0.30)
		_mote_x_amp[i] = rng.randf_range(0.09, 0.22)
		_mote_speed_mul[i] = rng.randf_range(0.84, 1.18)
		_mote_spin_rate[i] = rng.randf_range(2.2, 4.8) * (1.0 if (i % 2 == 0) else -1.0)
		_mote_positions[i] = Vector3.ZERO
		_mote_colors[i] = Color(0.0, 0.0, 0.0, 1.0)

	_grade_motes_mm = MultiMesh.new()
	_grade_motes_mm.transform_format = MultiMesh.TRANSFORM_3D
	_grade_motes_mm.use_colors = true
	_grade_motes_mm.use_custom_data = false
	_grade_motes_mm.mesh = _mote_mesh
	_grade_motes_mm.instance_count = GRADE_MOTE_COUNT
	for i in GRADE_MOTE_COUNT:
		_grade_motes_mm.set_instance_transform(i, Transform3D.IDENTITY)
		_grade_motes_mm.set_instance_color(i, Color(0.0, 0.0, 0.0, 1.0))

	_grade_motes = MultiMeshInstance3D.new()
	_grade_motes.name = "EmissaryGradeMotes"
	_grade_motes.position = Vector3(0.0, BANNER_PIVOT_Y, 0.0)
	_grade_motes.multimesh = _grade_motes_mm
	_grade_motes.material_override = _grade_motes_mat
	_grade_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grade_motes.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_grade_motes.visibility_range_end = GRADE_MOTE_VISIBILITY_RANGE
	_grade_motes.extra_cull_margin = 2.6
	_grade_motes.visible = false
	_banner_pivot.add_child(_grade_motes)


func _add_mesh_node(parent: Node3D, node_name: String, mesh_res: ArrayMesh,
		mat_res: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh_res
	mi.material_override = mat_res
	parent.add_child(mi)
	_all_mesh_instances.append(mi)
	return mi


func _release_mesh_refs() -> void:
	if _grade_motes != null and is_instance_valid(_grade_motes):
		_grade_motes.visible = false
		_grade_motes.material_override = null
		_grade_motes.multimesh = null
	_grade_motes = null
	_grade_motes_mm = null
	_grade_motes_mat = null
	_mote_positions.clear()
	_mote_colors.clear()
	for mi: MeshInstance3D in _all_mesh_instances:
		if mi != null and is_instance_valid(mi):
			mi.material_override = null
			mi.mesh = null
	_all_mesh_instances.clear()
	_grade_pennants.clear()
	_oak_mi = null
	_brass_mi = null
	_banner_mi = null
	_banner_pivot = null
	_built = false


# ==============================================================================
# WeakRef BC7 Ship PBR Texture & Material Cache
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
		_oak_mat = _make_pbr_mat(0.76, 0.04, TEX_OAK_NORMAL, TEX_OAK_ROUGH, Vector3(2.2, 2.2, 2.2), 0.72)
	if _brass_mat == null:
		_brass_mat = _make_pbr_mat(0.26, 0.86, TEX_BRASS_NORMAL, TEX_BRASS_ROUGH, Vector3(2.8, 2.8, 2.8), 0.55, true)
	if _cloth_mat == null:
		_cloth_mat = _make_pbr_mat(0.84, 0.04, TEX_CLOTH_NORMAL, "", Vector3(2.4, 2.4, 2.4), 0.78, true)

	if _oak_mesh == null:
		_oak_mesh = _build_oak_staff_and_clamp_mesh()
	if _brass_mesh == null:
		_brass_mesh = _build_brass_finial_and_hardware_mesh()
	if _pennant_mesh == null:
		_pennant_mesh = _build_grade_pennant_mesh()
	if _mote_mesh == null:
		_mote_mesh = _build_prestige_mote_mesh()
	for cid: StringName in COMPANY_PALETTES.keys():
		if not _banner_meshes.has(cid):
			_banner_meshes[cid] = _build_company_banner_mesh(cid)


static func _build_prestige_mote_mesh() -> ArrayMesh:
	# Exact 8-triangle faceted prestige diamond sparkle shard (zero primitives, finite unit normals).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_diamond_shard(st, Vector3.ZERO, Vector3(0.032, 0.068, 0.032),
		Color(1.00, 1.00, 1.00, 1.0), Color(0.84, 0.86, 0.92, 1.0))
	st.generate_normals()
	return st.commit()


static func _get_banner_mesh(company_id: StringName) -> ArrayMesh:
	_ensure_shared_assets()
	if _banner_meshes.has(company_id):
		return _banner_meshes[company_id] as ArrayMesh
	return _banner_meshes[&"gilded_compass"] as ArrayMesh


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
# Sculpted Flat-Faceted ArrayMesh Builders (Zero PrimitiveMesh)
# ==============================================================================

static func _build_oak_staff_and_clamp_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Beveled oak taffrail saddle clamp straddling the starboard stern rail (y = -0.10..+0.26).
	_add_box(st, Vector3(0.0, 0.0, 0.0), Vector3(0.24, 0.14, 0.28), COL_OAK_HI, COL_OAK_MID, COL_OAK_LO)
	_add_box(st, Vector3(0.0, 0.10, 0.0), Vector3(0.19, 0.08, 0.22), COL_OAK_HI, COL_OAK_MID, COL_OAK_LO)
	for sx: float in [-1.0, 1.0]:
		# Flared rail cheek clamps gripping down around the taffrail timber.
		_add_box(st, Vector3(sx * 0.115, -0.075, 0.0), Vector3(0.048, 0.16, 0.24),
			COL_OAK_HI, COL_OAK_MID, COL_OAK_LO)
		var b_brace := Basis(Vector3.FORWARD, sx * 0.36)
		_add_oriented_box(st, b_brace, Vector3(sx * 0.085, 0.16, 0.0), Vector3(0.045, 0.14, 0.12),
			COL_OAK_HI, COL_OAK_MID, COL_OAK_LO)
	for sz: float in [-1.0, 1.0]:
		var b_fore := Basis(Vector3.RIGHT, -sz * 0.32)
		_add_oriented_box(st, b_fore, Vector3(0.0, 0.15, sz * 0.095), Vector3(0.11, 0.13, 0.048),
			COL_OAK_MID, COL_OAK_MID, COL_OAK_LO)

	# 2. Turned 8-sided oak socket cup & tapered 2.55 m wooden stern flagstaff.
	_add_lathe_at(st, Vector3.ZERO, [
		Vector2(0.0, 0.08),
		Vector2(0.082, 0.08),
		Vector2(0.078, 0.22),
		Vector2(0.062, 0.28),
		Vector2(0.044, 0.32),
		Vector2(0.041, 0.80),
		Vector2(0.037, 1.35),
		Vector2(0.033, 1.90),
		Vector2(0.028, 2.38),
		Vector2(0.025, STAFF_HEIGHT),
		Vector2(0.0, STAFF_HEIGHT),
	], 8, COL_OAK_LO, COL_OAK_HI)

	st.generate_normals()
	return st.commit()


static func _build_brass_finial_and_hardware_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Lower & upper forged brass clamping straps wrapping the oak taffrail socket.
	for sy: float in [-0.02, 0.11]:
		var w := 0.256 if sy < 0.05 else 0.208
		var d := 0.296 if sy < 0.05 else 0.236
		_add_box(st, Vector3(0.0, sy, 0.0), Vector3(w, 0.030, d), COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var bp := Vector3(sx * 0.130, -0.02, sz * 0.075)
			_add_tube(st, bp - Vector3(sx * 0.012, 0.0, 0.0), bp + Vector3(sx * 0.018, 0.0, 0.0),
				0.016, 0.013, 6, COL_BRASS_HI, COL_BRASS_LO)

	# 2. Turned brass socket crown, halyard cleat collars, & banner attachment grommet rings.
	_add_lathe_at(st, Vector3.ZERO, [
		Vector2(0.052, 0.25),
		Vector2(0.072, 0.27),
		Vector2(0.072, 0.31),
		Vector2(0.054, 0.34),
		Vector2(0.043, 0.35),
	], 8, COL_BRASS_LO, COL_BRASS_HI)

	for ring_y: float in [1.56, 2.38]:
		var r_m := 0.044 if ring_y < 2.0 else 0.038
		_add_lathe_at(st, Vector3.ZERO, [
			Vector2(r_m - 0.008, ring_y - 0.022),
			Vector2(r_m + 0.008, ring_y - 0.012),
			Vector2(r_m + 0.008, ring_y + 0.012),
			Vector2(r_m - 0.008, ring_y + 0.022),
		], 8, COL_BRASS_LO, COL_BRASS_HI)

	# 3. Turned brass finial pedestal & faceted diamond spearhead crowning the 2.55 m staff.
	_add_lathe_at(st, Vector3.ZERO, [
		Vector2(0.025, 2.48),
		Vector2(0.048, 2.51),
		Vector2(0.056, 2.55),
		Vector2(0.036, 2.59),
		Vector2(0.044, 2.63),
		Vector2(0.024, 2.66),
		Vector2(0.0, 2.67),
	], 8, COL_BRASS_LO, COL_BRASS_HI)

	# Faceted spearhead blade (y = 2.64..2.94) + twin cross-guard volute spurs.
	_add_diamond_shard(st, Vector3(0.0, 2.79, 0.0), Vector3(0.036, 0.165, 0.068), COL_BRASS_HI, COL_BRASS_MID)
	for sz: float in [-1.0, 1.0]:
		var b_vol := Basis(Vector3.RIGHT, sz * 0.52)
		_add_oriented_box(st, b_vol, Vector3(0.0, 2.64, sz * 0.068), Vector3(0.026, 0.028, 0.105),
			COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)

	st.generate_normals()
	return st.commit()


static func _build_company_banner_mesh(company_id: StringName) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var pal: Array = COMPANY_PALETTES.get(company_id, COMPANY_PALETTES[&"gilded_compass"])
	var col_pri_hi: Color = pal[0] as Color
	var col_pri_lo: Color = pal[1] as Color
	var col_trim_hi: Color = pal[2] as Color
	var col_trim_lo: Color = pal[3] as Color
	var col_emblem: Color = pal[4] as Color

	# Billowing swallowtail company banner streaming aft (+Z) from staff (z = 0.04..1.44, y = -0.39..+0.39).
	const COLS := 10
	const ROWS := 4
	const LEN := 1.40
	const HALF_H := 0.39
	const HALF_T := 0.009

	var grid_p: Array = []
	var grid_m: Array = []
	var grid_c: Array = []
	for ci in range(COLS + 1):
		var u := float(ci) / float(COLS)
		var row_p: Array[Vector3] = []
		var row_m: Array[Vector3] = []
		var row_c: Array[Color] = []
		for ri in range(ROWS + 1):
			var v := float(ri) / float(ROWS)
			var y_norm := (v * 2.0) - 1.0  # -1 bottom .. +1 top
			# Deep swallowtail V-notch carved cleanly into trailing fly edge.
			var center_prox := 1.0 - absf(y_norm)
			var notch := center_prox * 0.34 * smoothstep(0.55, 1.0, u)
			var z := 0.042 + (u - notch * 0.65) * LEN
			var droop := -0.065 * u * u
			var taper := lerpf(1.0, 0.86, u)
			var y := y_norm * HALF_H * taper + droop
			var billow_x := sin(u * PI * 2.15 + absf(y_norm) * 0.35) * 0.088 * u
			row_p.append(Vector3(billow_x + HALF_T, y, z))
			row_m.append(Vector3(billow_x - HALF_T, y, z))

			var is_trim := (ri == 0 or ri == ROWS or ci == 0)
			var shade := clampf(0.55 + 0.45 * v - 0.18 * u, 0.0, 1.0)
			var base_col := col_trim_lo.lerp(col_trim_hi, shade) if is_trim else col_pri_lo.lerp(col_pri_hi, shade)
			if ci >= 3 and ci <= 6 and ri >= 1 and ri <= 3:
				base_col = base_col.lerp(col_emblem, 0.35 if (ri == 2) else 0.15)
			row_c.append(base_col)
		grid_p.append(row_p)
		grid_m.append(row_m)
		grid_c.append(row_c)

	for ci in COLS:
		for ri in ROWS:
			var p00: Vector3 = grid_p[ci][ri]
			var p10: Vector3 = grid_p[ci + 1][ri]
			var p11: Vector3 = grid_p[ci + 1][ri + 1]
			var p01: Vector3 = grid_p[ci][ri + 1]
			var m00: Vector3 = grid_m[ci][ri]
			var m10: Vector3 = grid_m[ci + 1][ri]
			var m11: Vector3 = grid_m[ci + 1][ri + 1]
			var m01: Vector3 = grid_m[ci][ri + 1]
			var c00: Color = grid_c[ci][ri]
			var c10: Color = grid_c[ci + 1][ri]
			var c11: Color = grid_c[ci + 1][ri + 1]
			var c01: Color = grid_c[ci][ri + 1]

			_emit_directed_quad(st, p00, p10, p11, p01, Vector3.RIGHT, c00, c10, c11, c01)
			_emit_directed_quad(st, m00, m01, m11, m10, Vector3.LEFT, c00, c01, c11, c10)

	# Raised company heraldic centerpiece medallion embossed on both faces of the banner.
	var emb_z := 0.56
	var emb_x := sin((emb_z / LEN) * PI * 2.15) * 0.088 * (emb_z / LEN)
	for sx: float in [-1.0, 1.0]:
		var center := Vector3(emb_x + sx * (HALF_T + 0.012), -0.012, emb_z)
		_add_diamond_shard(st, center, Vector3(0.018, 0.14, 0.14), col_emblem, col_trim_hi)
		if company_id == &"gilded_compass":
			# Four cardinal compass-point gold spikes around the diamond center.
			_add_diamond_shard(st, center + Vector3(0.0, 0.0, 0.15), Vector3(0.012, 0.045, 0.075), col_emblem, col_pri_hi)
			_add_diamond_shard(st, center + Vector3(0.0, 0.0, -0.15), Vector3(0.012, 0.045, 0.075), col_emblem, col_pri_hi)
		elif company_id == &"sunken_archive":
			# Twin vertical archive-scroll bars framing the central turquoise sigil.
			_add_box(st, center + Vector3(0.0, 0.0, -0.17), Vector3(0.016, 0.22, 0.036), col_trim_hi, col_trim_hi, col_trim_lo)
			_add_box(st, center + Vector3(0.0, 0.0, 0.17), Vector3(0.016, 0.22, 0.036), col_trim_hi, col_trim_hi, col_trim_lo)
		else:
			# Iron Tide twin war-chevron bars angled across the banner waist.
			var b_up := Basis(Vector3.RIGHT, 0.45)
			var b_dn := Basis(Vector3.RIGHT, -0.45)
			_add_oriented_box(st, b_up, center + Vector3(0.0, 0.07, 0.14), Vector3(0.018, 0.042, 0.16),
				col_emblem, col_trim_hi, col_trim_lo)
			_add_oriented_box(st, b_dn, center + Vector3(0.0, -0.07, 0.14), Vector3(0.018, 0.042, 0.16),
				col_emblem, col_trim_hi, col_trim_lo)

	st.generate_normals()
	return st.commit()


static func _build_grade_pennant_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Turned gilded brass collar clasp gripping the flagstaff at this grade tier.
	_add_lathe_at(st, Vector3.ZERO, [
		Vector2(0.036, -0.022),
		Vector2(0.052, -0.014),
		Vector2(0.052, 0.014),
		Vector2(0.036, 0.022),
	], 8, COL_BRASS_LO, COL_BRASS_HI)

	# Sculpted billowing gilded brass Grade Pennant Ribbon streaming aft (+Z, 0.56 m long).
	const SEGS := 5
	const PEN_LEN := 0.56
	const HALF_H := 0.064
	const HALF_T := 0.007

	var pts_p: Array = []
	var pts_m: Array = []
	for si in range(SEGS + 1):
		var u := float(si) / float(SEGS)
		var z := 0.045 + u * PEN_LEN
		var wave_x := sin(u * PI * 1.95) * 0.044 * u
		var droop := -0.032 * u * u
		var h := lerpf(HALF_H, 0.018, u)
		pts_p.append([
			Vector3(wave_x + HALF_T, droop - h, z),
			Vector3(wave_x + HALF_T + 0.006, droop, z),
			Vector3(wave_x + HALF_T, droop + h, z),
		])
		pts_m.append([
			Vector3(wave_x - HALF_T, droop - h, z),
			Vector3(wave_x - HALF_T - 0.006, droop, z),
			Vector3(wave_x - HALF_T, droop + h, z),
		])

	for si in SEGS:
		var u0 := float(si) / float(SEGS)
		var u1 := float(si + 1) / float(SEGS)
		var c0_edge := COL_BRASS_LO.lerp(COL_BRASS_MID, 1.0 - 0.35 * u0)
		var c1_edge := COL_BRASS_LO.lerp(COL_BRASS_MID, 1.0 - 0.35 * u1)
		var c0_mid := COL_BRASS_HI.lerp(COL_BRASS_MID, 0.25 * u0)
		var c1_mid := COL_BRASS_HI.lerp(COL_BRASS_MID, 0.25 * u1)

		var p0: Array = pts_p[si]
		var p1: Array = pts_p[si + 1]
		var m0: Array = pts_m[si]
		var m1: Array = pts_m[si + 1]

		# Starboard ridged ribbon face (+X)
		_emit_directed_quad(st, p0[0], p1[0], p1[1], p0[1], Vector3.RIGHT, c0_edge, c1_edge, c1_mid, c0_mid)
		_emit_directed_quad(st, p0[1], p1[1], p1[2], p0[2], Vector3.RIGHT, c0_mid, c1_mid, c1_edge, c0_edge)
		# Port ridged ribbon face (-X)
		_emit_directed_quad(st, m0[0], m0[1], m1[1], m1[0], Vector3.LEFT, c0_edge, c0_mid, c1_mid, c1_edge)
		_emit_directed_quad(st, m0[1], m0[2], m1[2], m1[1], Vector3.LEFT, c0_mid, c0_edge, c1_edge, c1_mid)

	# Forked twin pennant spear-tips at the fly end.
	var end_p: Array = pts_p[SEGS]
	var end_m: Array = pts_m[SEGS]
	var tip_top := ((end_p[2] as Vector3) + (end_m[2] as Vector3)) * 0.5 + Vector3(0.0, 0.012, 0.085)
	var tip_bot := ((end_p[0] as Vector3) + (end_m[0] as Vector3)) * 0.5 + Vector3(0.0, -0.012, 0.085)
	_emit_directed_tri(st, end_p[1], end_p[2], tip_top, Vector3.RIGHT, COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_HI)
	_emit_directed_tri(st, end_p[0], end_p[1], tip_bot, Vector3.RIGHT, COL_BRASS_MID, COL_BRASS_HI, COL_BRASS_HI)
	_emit_directed_tri(st, end_m[1], end_m[2], tip_top, Vector3.LEFT, COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_HI)
	_emit_directed_tri(st, end_m[0], end_m[1], tip_bot, Vector3.LEFT, COL_BRASS_MID, COL_BRASS_HI, COL_BRASS_HI)

	st.generate_normals()
	return st.commit()


# ==============================================================================
# Sculpted Flat-Faceted SurfaceTool Primitives
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
	st.set_smooth_group(-1)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_smooth_group(-1)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_smooth_group(-1)
	st.set_color(cc)
	st.add_vertex(c)
