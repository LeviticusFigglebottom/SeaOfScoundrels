class_name CoralReef
extends Node3D
## Batched MultiMesh underwater coral reefs and swaying kelp gardens for islands.
##
## Populates an island's shallow seabed skirt (-0.85 m .. -9.5 m) with vibrant
## painterly tropical reef beds using strictly 3 MultiMeshInstance3D draw calls:
##   1. `StaghornCorals`   — branching staghorn & sea-fan coral clusters
##   2. `BrainTableCorals` — fluted brain coral domes + cantilevered table shelves
##   3. `KelpFronds`       — 5-blade swaying emerald/chartreuse kelp & seagrass tufts
##
## All 3 procedural meshes (`SurfaceTool`, `set_smooth_group(-1)`) and materials
## are cached statically across islands while active in the scene tree, and all
## MultiMeshes disable shadows and distance-cull cleanly at 155 m (0.00 ms far GPU).

const GROUP := &"coral_reefs"
const KELP_SHADER: Shader = preload("res://src/world/coral_kelp.gdshader")

const VISIBILITY_RANGE_END := 155.0
const VISIBILITY_RANGE_MARGIN := 20.0
const MIN_RADIUS_FACTOR := 0.55
const MAX_SEABED_FACTOR := 0.94
const MIN_SURFACE_Y := -9.5
const MAX_SURFACE_Y := -0.85
const MAX_ROOT_Y := -0.65
const ROOT_EMBED_Y := 0.12
const MIN_NORMAL_Y := 0.72
const MOORING_CLEAR_RADIUS := 9.5
const PIER_CLEAR_RADIUS := 5.0

# Reference local mesh heights (at unit scale) used to keep tips strictly submerged.
const STAGHORN_MESH_HEIGHT := 1.28
const BRAIN_TABLE_MESH_HEIGHT := 0.82
const KELP_MESH_HEIGHT := 2.45

# Vibrant tropical coral & kelp palettes (authored in sRGB).
const STAGHORN_PALETTE: Array[Color] = [
	Color(0.949, 0.420, 0.357, 1.0),  # Sunset coral (#f26b5b)
	Color(0.965, 0.596, 0.282, 1.0),  # Warm tangerine (#f69848)
	Color(0.851, 0.349, 0.612, 1.0),  # Reef magenta (#d9599c)
	Color(0.910, 0.753, 0.290, 1.0),  # Golden ochre (#e8c04a)
	Color(0.267, 0.761, 0.722, 1.0),  # Turquoise sea-fan (#44c2b8)
]

const BRAIN_TABLE_PALETTE: Array[Color] = [
	Color(0.922, 0.847, 0.690, 1.0),  # Coral-cream (#ebd8b0)
	Color(0.875, 0.467, 0.408, 1.0),  # Rose-terracotta (#df7768)
	Color(0.353, 0.639, 0.549, 1.0),  # Teal-olive (#5aa38c)
	Color(0.898, 0.725, 0.298, 1.0),  # Warm gold (#e5b94c)
	Color(0.812, 0.455, 0.580, 1.0),  # Reef rose-lilac (#cf7494)
]

const KELP_PALETTE: Array[Color] = [
	Color(0.133, 0.620, 0.345, 1.0),  # Rich emerald (#229e58)
	Color(0.463, 0.745, 0.220, 1.0),  # Chartreuse-kelp (#76be38)
	Color(0.169, 0.549, 0.431, 1.0),  # Olive-teal (#2b8c6e)
	Color(0.220, 0.722, 0.416, 1.0),  # Sunlit jade (#38b86a)
	Color(0.541, 0.659, 0.212, 1.0),  # Golden-olive (#8aa836)
]

static var _staghorn_mesh: ArrayMesh = null
static var _brain_table_mesh: ArrayMesh = null
static var _kelp_mesh: ArrayMesh = null
static var _coral_material: StandardMaterial3D = null
static var _kelp_material: ShaderMaterial = null
static var _active_reefs: int = 0

var _staghorn_mmi: MultiMeshInstance3D = null
var _brain_mmi: MultiMeshInstance3D = null
var _kelp_mmi: MultiMeshInstance3D = null
var _staghorn_count: int = 0
var _brain_count: int = 0
var _kelp_count: int = 0
var _min_root_y: float = 0.0
var _max_root_y: float = 0.0
var _has_instances: bool = false
var _placed_transforms: Array[Transform3D] = []


func _enter_tree() -> void:
	add_to_group(GROUP)
	_active_reefs += 1


func _exit_tree() -> void:
	for mmi in [_staghorn_mmi, _brain_mmi, _kelp_mmi]:
		if mmi != null and is_instance_valid(mmi):
			mmi.material_override = null
			mmi.multimesh = null
	_staghorn_mmi = null
	_brain_mmi = null
	_kelp_mmi = null
	_placed_transforms.clear()
	_active_reefs = maxi(0, _active_reefs - 1)
	if _active_reefs == 0:
		clear_shared_cache()


## Release statically cached shared procedural meshes & materials cleanly.
static func clear_shared_cache() -> void:
	_staghorn_mesh = null
	_brain_table_mesh = null
	_kelp_mesh = null
	_coral_material = null
	_kelp_material = null


## Deterministically populate underwater coral reefs and swaying kelp gardens
## around `island`'s shallow seabed skirt and attach the resulting `CoralReef`.
static func populate_for_island(island: Island, rng_seed: int = 0,
		density_scale: float = 1.0) -> CoralReef:
	var reef := CoralReef.new()
	reef.name = "CoralReef"
	if island == null:
		return reef

	var rng := RandomNumberGenerator.new()
	var seed_val := rng_seed
	if seed_val == 0:
		seed_val = island.island_id.hash()
	if seed_val == 0:
		seed_val = 0xC04A1EEF
	rng.seed = seed_val

	var scale_k := clampf(density_scale, 0.0, 3.0)
	var lush_bonus := 1.0
	if island.archetype == &"crescent_lagoon" or island.archetype == &"palm_atoll" \
			or island.archetype == &"wreck_shoal":
		lush_bonus = 1.12

	var target_staghorn := int(roundf(clampf(float(rng.randi_range(42, 62)) * lush_bonus, 36.0, 70.0) * scale_k))
	var target_brain := int(roundf(clampf(float(rng.randi_range(32, 50)) * lush_bonus, 28.0, 55.0) * scale_k))
	var target_kelp := int(roundf(clampf(float(rng.randi_range(92, 138)) * lush_bonus, 80.0, 150.0) * scale_k))

	var r_min := maxf(4.0, island.island_radius * MIN_RADIUS_FACTOR)
	var r_max := maxf(r_min + 4.0, island.seabed_radius * MAX_SEABED_FACTOR)
	var mooring_xz := Vector2(island.mooring_transform.origin.x, island.mooring_transform.origin.z)
	var has_pier := island is Outpost
	var pier_a := Vector2.ZERO
	var pier_b := Vector2.ZERO
	if has_pier:
		var op := island as Outpost
		pier_a = Vector2(op.dock_local_transform.origin.x, op.dock_local_transform.origin.z)
		pier_b = Vector2(op.dock_pier_end_local.x, op.dock_pier_end_local.z)

	# 1. Discover organic reef-bed cluster centers in the valid shallow shelf.
	var bed_centers: Array[Vector2] = []
	var desired_beds := rng.randi_range(7, 10)
	for _attempt in 180:
		if bed_centers.size() >= desired_beds:
			break
		var pt := _sample_annulus_xz(rng, r_min, r_max)
		if not _is_valid_reef_spot(island, pt, mooring_xz, has_pier, pier_a, pier_b):
			continue
		var bh := island.surface_height(pt.x, pt.y)
		if bh > -1.15 or bh < -7.8:
			continue
		if _far_from_xz(pt, bed_centers, 14.0):
			bed_centers.append(pt)

	var coral_occupied: Array[Vector2] = []
	var kelp_occupied: Array[Vector2] = []

	var staghorn_xf: Array[Transform3D] = []
	var staghorn_col: Array[Color] = []
	var brain_xf: Array[Transform3D] = []
	var brain_col: Array[Color] = []
	var kelp_xf: Array[Transform3D] = []
	var kelp_col: Array[Color] = []

	var min_y := INF
	var max_y := -INF

	# 2. Place Brain & Layered Table Coral Mounds first as reef-bed anchors.
	var brain_attempts := target_brain * 24 + 90
	for _i in brain_attempts:
		if brain_xf.size() >= target_brain:
			break
		var pt := _sample_reef_candidate(rng, bed_centers, r_min, r_max, 0.68, 3.0, 12.0)
		if not _is_valid_reef_spot(island, pt, mooring_xz, has_pier, pier_a, pier_b):
			continue
		if not _far_from_xz(pt, coral_occupied, 1.85):
			continue
		var h := island.surface_height(pt.x, pt.y)
		var root_y := h - ROOT_EMBED_Y
		if root_y > MAX_ROOT_Y:
			continue
		var n := island.surface_normal(pt.x, pt.y)
		var sx := rng.randf_range(0.80, 1.42)
		var sz := sx * rng.randf_range(0.88, 1.14)
		var max_h := maxf(0.40, -h - 0.24)
		var sy := minf(rng.randf_range(0.76, 1.24), max_h / BRAIN_TABLE_MESH_HEIGHT)
		var xf := _grounded_transform(Vector3(pt.x, root_y, pt.y), n, 0.65, rng.randf() * TAU, Vector3(sx, sy, sz))
		brain_xf.append(xf)
		brain_col.append(_pick_jittered_color(rng, BRAIN_TABLE_PALETTE))
		coral_occupied.append(pt)
		min_y = minf(min_y, root_y)
		max_y = maxf(max_y, root_y)

	# 3. Place Branching Staghorn & Sea-Fan Clusters ringing the mounds & reef ledges.
	var staghorn_attempts := target_staghorn * 24 + 100
	for _i in staghorn_attempts:
		if staghorn_xf.size() >= target_staghorn:
			break
		var pt := _sample_reef_candidate(rng, bed_centers, r_min, r_max, 0.66, 2.2, 11.5)
		if not _is_valid_reef_spot(island, pt, mooring_xz, has_pier, pier_a, pier_b):
			continue
		if not _far_from_xz(pt, coral_occupied, 1.35):
			continue
		var h := island.surface_height(pt.x, pt.y)
		var root_y := h - ROOT_EMBED_Y
		if root_y > MAX_ROOT_Y:
			continue
		var n := island.surface_normal(pt.x, pt.y)
		var base_s := rng.randf_range(0.76, 1.32)
		var max_h := maxf(0.45, -h - 0.24)
		var sy := minf(base_s * rng.randf_range(0.90, 1.16), max_h / STAGHORN_MESH_HEIGHT)
		var sx := minf(base_s, sy * 1.28)
		var sz := sx * rng.randf_range(0.90, 1.12)
		var xf := _grounded_transform(Vector3(pt.x, root_y, pt.y), n, 0.40, rng.randf() * TAU, Vector3(sx, sy, sz))
		staghorn_xf.append(xf)
		staghorn_col.append(_pick_jittered_color(rng, STAGHORN_PALETTE))
		coral_occupied.append(pt)
		min_y = minf(min_y, root_y)
		max_y = maxf(max_y, root_y)

	# 4. Place Multi-Ribbon Swaying Kelp & Seagrass Gardens weaving around coral beds.
	var kelp_attempts := target_kelp * 20 + 140
	for _i in kelp_attempts:
		if kelp_xf.size() >= target_kelp:
			break
		var pt := _sample_reef_candidate(rng, bed_centers, r_min, r_max, 0.60, 2.8, 15.0)
		if not _is_valid_reef_spot(island, pt, mooring_xz, has_pier, pier_a, pier_b):
			continue
		if not _far_from_xz(pt, kelp_occupied, 0.72):
			continue
		if not _far_from_xz(pt, coral_occupied, 0.62):
			continue
		var h := island.surface_height(pt.x, pt.y)
		var root_y := h - ROOT_EMBED_Y
		if root_y > MAX_ROOT_Y:
			continue
		var n := island.surface_normal(pt.x, pt.y)
		# Taller lush 1.4..2.6 m kelp fronds in deeper shelves; shorter seagrass in 0.85..2.0 m shallows.
		var depth_t := clampf((-h - 0.85) / 3.2, 0.0, 1.0)
		var desired_sy := lerpf(rng.randf_range(0.32, 0.52), rng.randf_range(0.76, 1.08), depth_t)
		var max_h := maxf(0.45, -h - 0.25)
		var sy := minf(desired_sy, max_h / KELP_MESH_HEIGHT)
		var sx := rng.randf_range(0.84, 1.24) * lerpf(0.82, 1.08, depth_t)
		var sz := sx * rng.randf_range(0.88, 1.14)
		var xf := _grounded_transform(Vector3(pt.x, root_y, pt.y), n, 0.22, rng.randf() * TAU, Vector3(sx, sy, sz))
		kelp_xf.append(xf)
		kelp_col.append(_pick_jittered_color(rng, KELP_PALETTE))
		kelp_occupied.append(pt)
		min_y = minf(min_y, root_y)
		max_y = maxf(max_y, root_y)

	# 5. Build strictly 3 batched MultiMeshInstance3D children sharing cached static meshes.
	var coral_mat := _get_coral_material()
	var kelp_mat := _get_kelp_material()

	reef._staghorn_mmi = _create_multimesh_node(
		"StaghornCorals", _get_staghorn_mesh(), coral_mat, staghorn_xf, staghorn_col, 0.0)
	reef._brain_mmi = _create_multimesh_node(
		"BrainTableCorals", _get_brain_table_mesh(), coral_mat, brain_xf, brain_col, 0.0)
	reef._kelp_mmi = _create_multimesh_node(
		"KelpFronds", _get_kelp_mesh(), kelp_mat, kelp_xf, kelp_col, 1.0)

	reef.add_child(reef._staghorn_mmi)
	reef.add_child(reef._brain_mmi)
	reef.add_child(reef._kelp_mmi)

	reef._staghorn_count = staghorn_xf.size()
	reef._brain_count = brain_xf.size()
	reef._kelp_count = kelp_xf.size()
	reef._placed_transforms.clear()
	reef._placed_transforms.append_array(staghorn_xf)
	reef._placed_transforms.append_array(brain_xf)
	reef._placed_transforms.append_array(kelp_xf)
	if min_y <= max_y:
		reef._min_root_y = min_y
		reef._max_root_y = max_y
		reef._has_instances = true

	island.add_child(reef)
	return reef


# ------------------------------------------------------------------ inspection API

## Number of MultiMeshInstance3D draw-call nodes owned by this reef (always <= 3).
func get_multimesh_count() -> int:
	var count := 0
	for child in get_children():
		if child is MultiMeshInstance3D:
			count += 1
	return count


## Total placed underwater coral & kelp instances across all 3 MultiMeshes.
func get_total_instance_count() -> int:
	var total := 0
	for child in get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi != null and mmi.multimesh != null:
			total += mmi.multimesh.instance_count
	return total


func get_staghorn_count() -> int:
	return _staghorn_count


func get_brain_coral_count() -> int:
	return _brain_count


func get_kelp_count() -> int:
	return _kelp_count


## Local-space Y elevation range `Vector2(min_y, max_y)` across all placed reef roots.
func get_reef_bounds_depth_range() -> Vector2:
	if not _has_instances:
		return Vector2.ZERO
	return Vector2(_min_root_y, _max_root_y)


## Read-only copy of all placed instance local transforms across the 3 MultiMeshes
## (reliable even under `--headless` where RenderingServerDummy drops GPU buffers).
func get_placed_transforms() -> Array[Transform3D]:
	return _placed_transforms.duplicate()


# ------------------------------------------------------------------ placement helpers

static func _create_multimesh_node(node_name: String, mesh: ArrayMesh, mat: Material,
		transforms: Array[Transform3D], colors: Array[Color],
		cull_margin: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = false
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = VISIBILITY_RANGE_END
	mmi.visibility_range_end_margin = VISIBILITY_RANGE_MARGIN
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	if cull_margin > 0.0:
		mmi.extra_cull_margin = cull_margin
	return mmi


static func _sample_annulus_xz(rng: RandomNumberGenerator, r_min: float, r_max: float) -> Vector2:
	var ang := rng.randf() * TAU
	var r := sqrt(lerpf(r_min * r_min, r_max * r_max, rng.randf()))
	return Vector2(cos(ang) * r, sin(ang) * r)


static func _sample_reef_candidate(rng: RandomNumberGenerator, bed_centers: Array[Vector2],
		r_min: float, r_max: float, cluster_prob: float,
		patch_min: float, patch_max: float) -> Vector2:
	if not bed_centers.is_empty() and rng.randf() < cluster_prob:
		var ctr := bed_centers[rng.randi_range(0, bed_centers.size() - 1)]
		var ang := rng.randf() * TAU
		var dist := lerpf(patch_min, patch_max, sqrt(rng.randf()))
		var pt := ctr + Vector2(cos(ang) * dist, sin(ang) * dist)
		var r_len := pt.length()
		if r_len >= r_min and r_len <= r_max:
			return pt
	return _sample_annulus_xz(rng, r_min, r_max)


static func _is_valid_reef_spot(island: Island, pt: Vector2, mooring_xz: Vector2,
		has_pier: bool, pier_a: Vector2, pier_b: Vector2) -> bool:
	if pt.distance_squared_to(mooring_xz) < MOORING_CLEAR_RADIUS * MOORING_CLEAR_RADIUS:
		return false
	if has_pier and _point_segment_dist_sq(pt, pier_a, pier_b) < PIER_CLEAR_RADIUS * PIER_CLEAR_RADIUS:
		return false
	var h := island.surface_height(pt.x, pt.y)
	if h > MAX_SURFACE_Y or h < MIN_SURFACE_Y:
		return false
	var n := island.surface_normal(pt.x, pt.y)
	return n.y >= MIN_NORMAL_Y


static func _point_segment_dist_sq(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_squared_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_squared_to(a + ab * t)


static func _far_from_xz(pt: Vector2, existing: Array[Vector2], min_dist: float) -> bool:
	var d2 := min_dist * min_dist
	for other in existing:
		if pt.distance_squared_to(other) < d2:
			return false
	return true


static func _grounded_transform(origin: Vector3, normal: Vector3, tilt_weight: float,
		yaw: float, scl: Vector3) -> Transform3D:
	var up_axis := Vector3.UP.lerp(normal.normalized(), tilt_weight).normalized()
	var ref_fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right_axis := ref_fwd.cross(up_axis)
	if right_axis.length_squared() < 0.0001:
		right_axis = Vector3.RIGHT
	else:
		right_axis = right_axis.normalized()
	var back_axis := right_axis.cross(up_axis).normalized()
	var xform_basis := Basis(right_axis, up_axis, back_axis).scaled(scl)
	return Transform3D(xform_basis, origin)


static func _pick_jittered_color(rng: RandomNumberGenerator, palette: Array[Color]) -> Color:
	var base := palette[rng.randi_range(0, palette.size() - 1)]
	var h := wrapf(base.h + rng.randf_range(-0.025, 0.025), 0.0, 1.0)
	var s := clampf(base.s * rng.randf_range(0.92, 1.08), 0.0, 1.0)
	var v := clampf(base.v * rng.randf_range(0.92, 1.08), 0.0, 1.0)
	return Color.from_hsv(h, s, v, 1.0)


# ------------------------------------------------------------------ shared cached assets

static func _get_coral_material() -> StandardMaterial3D:
	if _coral_material == null:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.roughness = 0.76
		mat.metallic = 0.0
		mat.metallic_specular = 0.28
		_coral_material = mat
	return _coral_material


static func _get_kelp_material() -> ShaderMaterial:
	if _kelp_material == null:
		var mat := ShaderMaterial.new()
		mat.shader = KELP_SHADER
		_kelp_material = mat
	return _kelp_material


static func _get_staghorn_mesh() -> ArrayMesh:
	if _staghorn_mesh == null:
		_staghorn_mesh = _build_staghorn_mesh()
	return _staghorn_mesh


static func _get_brain_table_mesh() -> ArrayMesh:
	if _brain_table_mesh == null:
		_brain_table_mesh = _build_brain_table_mesh()
	return _brain_table_mesh


static func _get_kelp_mesh() -> ArrayMesh:
	if _kelp_mesh == null:
		_kelp_mesh = _build_kelp_mesh()
	return _kelp_mesh


# ------------------------------------------------------------------ Mesh 1: Staghorn & Fan Coral

static func _build_staghorn_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Chunky faceted limestone-coral holdfast rock collar anchoring the branches into sand.
	var col_hold_bot := Color(0.46, 0.45, 0.50, 1.0)
	var col_hold_top := Color(0.64, 0.63, 0.67, 1.0)
	_append_holdfast_base(st, Vector3.ZERO, 0.40, 0.19, 0.37, -0.10, 7, col_hold_bot, col_hold_top)

	var col_base := Color(0.68, 0.67, 0.71, 1.0)
	var col_mid := Color(0.86, 0.85, 0.87, 1.0)
	var col_hi := Color(0.95, 0.95, 0.94, 1.0)
	var col_tip := Color(1.00, 1.00, 0.98, 1.0)

	# 5 primary radiating staghorn trunks: [azimuth, lean_rad, height, root_off, base_r, has_fan_bud]
	var trunks: Array[Array] = [
		[0.18, 0.28, 1.18, 0.08, 0.115, true],
		[1.42, 0.44, 1.04, 0.13, 0.102, false],
		[2.58, 0.54, 0.92, 0.14, 0.095, true],
		[3.86, 0.36, 1.12, 0.11, 0.108, false],
		[5.16, 0.48, 0.96, 0.14, 0.098, false],
	]

	for idx in trunks.size():
		var spec: Array = trunks[idx]
		var az: float = float(spec[0])
		var lean: float = float(spec[1])
		var h_tot: float = float(spec[2])
		var roff: float = float(spec[3])
		var r_base: float = float(spec[4])
		var has_bud: bool = bool(spec[5])

		var rad_dir := Vector3(cos(az), 0.0, sin(az))
		var tan_dir := Vector3(-sin(az), 0.0, cos(az))

		var p0 := rad_dir * roff + Vector3(0.0, 0.05, 0.0)
		var dir_lo := (Vector3.UP * cos(lean) + rad_dir * sin(lean)).normalized()
		var p1 := p0 + dir_lo * (h_tot * 0.42)
		var dir_hi := (Vector3.UP * cos(lean * 0.65) + rad_dir * sin(lean * 0.65) + tan_dir * 0.14).normalized()
		var p2 := p1 + dir_hi * (h_tot * 0.32)

		var r_elbow := r_base * 0.74
		var r_fork := r_base * 0.58
		_append_tapered_limb(st, p0, p1, r_base, r_elbow, 5, col_base, col_mid, false)
		_append_tapered_limb(st, p1, p2, r_elbow, r_fork, 5, col_mid, col_hi, false)

		# Lateral secondary antler forking outward from the mid-elbow and curving upward.
		var side_sign := 1.0 if (idx % 2 == 0) else -1.0
		var lat_d1 := (rad_dir * 0.68 + tan_dir * (0.48 * side_sign) + Vector3.UP * 0.56).normalized()
		var lat_m := p1 + lat_d1 * (h_tot * 0.25)
		var lat_d2 := (rad_dir * 0.34 + tan_dir * (0.30 * side_sign) + Vector3.UP * 0.89).normalized()
		var lat_tip := lat_m + lat_d2 * (h_tot * 0.26)
		_append_tapered_limb(st, p1, lat_m, r_elbow * 0.76, r_elbow * 0.56, 5, col_mid, col_hi, false)
		_append_tapered_limb(st, lat_m, lat_tip, r_elbow * 0.56, r_elbow * 0.40, 5, col_hi, col_tip, true)

		# Twin crown antlers splitting from the upper fork (one tall inner, one swept outer).
		var crown_a_dir := (Vector3.UP * 0.88 + rad_dir * 0.24 - tan_dir * (0.38 * side_sign)).normalized()
		var crown_a_tip := p2 + crown_a_dir * (h_tot * 0.34)
		_append_tapered_limb(st, p2, crown_a_tip, r_fork * 0.88, r_fork * 0.56, 5, col_hi, col_tip, true)

		var crown_b_dir := (Vector3.UP * 0.76 + rad_dir * 0.52 + tan_dir * (0.36 * side_sign)).normalized()
		var crown_b_tip := p2 + crown_b_dir * (h_tot * 0.27)
		_append_tapered_limb(st, p2, crown_b_tip, r_fork * 0.76, r_fork * 0.50, 5, col_hi, col_tip, true)

		# Optional tertiary fan-bud prong for dense sea-fan / staghorn silhouette.
		if has_bud:
			var bud_dir := (Vector3.UP * 0.68 + rad_dir * 0.64 - tan_dir * (0.34 * side_sign)).normalized()
			var bud_tip := lat_m + bud_dir * (h_tot * 0.20)
			_append_tapered_limb(st, lat_m, bud_tip, r_elbow * 0.48, r_elbow * 0.34, 5, col_hi, col_tip, true)

	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ Mesh 2: Brain & Table Coral

static func _build_brain_table_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Sculpted fluted brain-coral dome anchored cleanly below y = 0.
	var dome_ctr := Vector3(-0.08, 0.0, -0.04)
	var radial_segs := 12
	# Ring table: [y, radius_scale, base_shade]
	var dome_rings: Array[Array] = [
		[-0.14, 0.78, 0.50],
		[0.06, 0.82, 0.64],
		[0.26, 0.75, 0.78],
		[0.44, 0.58, 0.90],
		[0.57, 0.33, 0.96],
	]

	var ring_pts: Array[Array] = []
	var ring_cols: Array[Array] = []
	for ri in dome_rings.size():
		var row: Array = dome_rings[ri]
		var y_val: float = float(row[0])
		var r_base: float = float(row[1])
		var shade_base: float = float(row[2])
		var pts: Array[Vector3] = []
		var cols: Array[Color] = []
		for k in radial_segs:
			var ang := float(k) / float(radial_segs) * TAU
			var flute := sin(ang * 6.0 + float(ri) * 0.72) * 0.095 + cos(ang * 4.0 - float(ri) * 0.45) * 0.045
			var r_mod := r_base * (1.0 + flute)
			var vx := dome_ctr.x + cos(ang) * r_mod
			var vz := dome_ctr.z + sin(ang) * r_mod * 0.92
			var vy := y_val + flute * 0.08 * float(ri)
			pts.append(Vector3(vx, vy, vz))
			var valley_ao := clampf(shade_base + flute * 0.58, 0.42, 1.0)
			cols.append(Color(valley_ao, valley_ao * 0.99, valley_ao * 0.97, 1.0))
		ring_pts.append(pts)
		ring_cols.append(cols)

	var dome_ref := dome_ctr + Vector3(0.0, 0.12, 0.0)
	for ri in range(ring_pts.size() - 1):
		var r0: Array = ring_pts[ri]
		var r1: Array = ring_pts[ri + 1]
		var c0: Array = ring_cols[ri]
		var c1: Array = ring_cols[ri + 1]
		for k in radial_segs:
			var nk := (k + 1) % radial_segs
			_add_outward_quad(st, r0[k], r1[k], r1[nk], r0[nk], dome_ref,
				c0[k], c1[k], c1[nk], c0[nk])

	# Fluted dome crown cap.
	var apex := dome_ctr + Vector3(0.0, 0.65, 0.0)
	var col_apex := Color(1.0, 0.99, 0.96, 1.0)
	var top_r: Array = ring_pts[ring_pts.size() - 1]
	var top_c: Array = ring_cols[ring_cols.size() - 1]
	for k in radial_segs:
		var nk := (k + 1) % radial_segs
		_add_outward_tri(st, top_r[k], apex, top_r[nk], dome_ref, top_c[k], col_apex, top_c[nk])

	# 2. Three cantilevered overlapping reef table-coral shelf plates fanning asymmetrically,
	#    each anchored solidly into the brain-coral dome by a chunky tapered coral pedestal stalk.
	_append_table_shelf(st, Vector3(0.08, -0.06, 0.04), Vector3(0.45, 0.32, 0.17),
		0.56, 0.45, 0.12, 0.35, 10)
	_append_table_shelf(st, Vector3(-0.10, 0.02, 0.10), Vector3(-0.24, 0.49, 0.41),
		0.48, 0.39, 0.11, 2.05, 10)
	_append_table_shelf(st, Vector3(0.02, 0.10, -0.08), Vector3(0.22, 0.66, -0.31),
		0.42, 0.34, 0.10, -1.15, 10)

	# 3. Two small companion basal coral knobs nestled into the seabed perimeter.
	_append_holdfast_base(st, Vector3(0.44, 0.0, -0.44), 0.28, 0.25, 0.24, -0.08, 6,
		Color(0.56, 0.55, 0.58, 1.0), Color(0.90, 0.89, 0.86, 1.0))
	_append_holdfast_base(st, Vector3(-0.56, 0.0, -0.22), 0.24, 0.22, 0.26, -0.08, 6,
		Color(0.54, 0.54, 0.57, 1.0), Color(0.88, 0.88, 0.85, 1.0))

	st.generate_normals()
	return st.commit()


static func _append_table_shelf(st: SurfaceTool, stalk_base: Vector3, shelf_center: Vector3,
		rx: float, rz: float, thick: float, yaw: float, segs: int) -> void:
	# Chunky 2-tier horizontal-ring tapered coral pedestal stalk:
	# - bot_ring embeds deep inside the brain-coral dome body
	# - mid_ring forms a sturdy sculpted coral stem waist
	# - top_ring penetrates strictly horizontal up inside the shelf interior (zero air gap at any angle)
	const STALK_SIDES := 6
	var base_r := minf(rx, rz)
	var r_bot := base_r * 0.44
	var r_mid := base_r * 0.36
	var r_top := base_r * 0.48
	var c_bot := stalk_base
	var c_top := Vector3(shelf_center.x, shelf_center.y - thick * 0.04, shelf_center.z)
	var c_mid := c_bot.lerp(c_top, 0.52)
	var col_stalk_bot := Color(0.56, 0.55, 0.59, 1.0)
	var col_stalk_mid := Color(0.68, 0.67, 0.70, 1.0)
	var col_stalk_top := Color(0.76, 0.75, 0.77, 1.0)

	var bot_ring: Array[Vector3] = []
	var mid_ring: Array[Vector3] = []
	var top_ring: Array[Vector3] = []
	for i in STALK_SIDES:
		var ang := yaw + float(i) / float(STALK_SIDES) * TAU
		var jit := 0.94 + 0.10 * sin(ang * 3.0 + yaw)
		var dir_xz := Vector3(cos(ang), 0.0, sin(ang))
		bot_ring.append(c_bot + dir_xz * (r_bot * jit))
		mid_ring.append(c_mid + dir_xz * (r_mid * jit))
		top_ring.append(c_top + dir_xz * (r_top * jit))

	var ref_lo := c_bot.lerp(c_mid, 0.5)
	var ref_hi := c_mid.lerp(c_top, 0.5)
	for i in STALK_SIDES:
		var ni := (i + 1) % STALK_SIDES
		_add_outward_quad(st, bot_ring[i], mid_ring[i], mid_ring[ni], bot_ring[ni], ref_lo,
			col_stalk_bot, col_stalk_mid, col_stalk_mid, col_stalk_bot)
		_add_outward_quad(st, mid_ring[i], top_ring[i], top_ring[ni], mid_ring[ni], ref_hi,
			col_stalk_mid, col_stalk_top, col_stalk_top, col_stalk_mid)

	var col_under := Color(0.56, 0.56, 0.60, 1.0)
	var col_rim := Color(1.00, 0.99, 0.96, 1.0)
	var col_top_ctr := Color(0.88, 0.88, 0.86, 1.0)

	var cy := cos(yaw)
	var sy := sin(yaw)
	var under_hub := shelf_center - Vector3(0.0, thick, 0.0)
	var top_hub := shelf_center + Vector3(0.0, thick * 0.26, 0.0)
	var ref_ctr := shelf_center - Vector3(0.0, thick * 0.28, 0.0)

	var rim_bot: Array[Vector3] = []
	var rim_top: Array[Vector3] = []
	for k in segs:
		var ang := float(k) / float(segs) * TAU
		var scallop := 1.0 + 0.13 * sin(ang * 5.0 + yaw) + 0.06 * cos(ang * 3.0 - yaw)
		var lx := cos(ang) * rx * scallop
		var lz := sin(ang) * rz * scallop
		var wx := shelf_center.x + lx * cy - lz * sy
		var wz := shelf_center.z + lx * sy + lz * cy
		var wave_y := sin(ang * 4.0 + yaw * 1.5) * (thick * 0.22)
		rim_bot.append(Vector3(wx, shelf_center.y - thick * 0.36 + wave_y, wz))
		rim_top.append(Vector3(wx * 0.97 + shelf_center.x * 0.03,
			shelf_center.y + thick * 0.32 + wave_y, wz * 0.97 + shelf_center.z * 0.03))

	for k in segs:
		var nk := (k + 1) % segs
		# Sloped shaded underside cone.
		_add_outward_tri(st, under_hub, rim_bot[k], rim_bot[nk], ref_ctr,
			col_under, col_under.lerp(col_rim, 0.25), col_under.lerp(col_rim, 0.25))
		# Chunky beveled bright coral shelf rim.
		_add_outward_quad(st, rim_bot[k], rim_top[k], rim_top[nk], rim_bot[nk], ref_ctr,
			col_under.lerp(col_rim, 0.45), col_rim, col_rim, col_under.lerp(col_rim, 0.45))
		# Sunlit scalloped upper terrace disc.
		_add_outward_tri(st, top_hub, rim_top[nk], rim_top[k], ref_ctr,
			col_top_ctr, col_rim, col_rim)


# ------------------------------------------------------------------ Mesh 3: 5-Blade Swaying Kelp

static func _build_kelp_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Small grounded rocky holdfast base (UV.y = 1.0 -> zero sway in coral_kelp.gdshader).
	var col_rock_lo := Color(0.38, 0.42, 0.42, 1.0)
	var col_rock_hi := Color(0.52, 0.56, 0.54, 1.0)
	_append_holdfast_base(st, Vector3.ZERO, 0.24, 0.11, 0.22, -0.10, 6,
		col_rock_lo, col_rock_hi, Vector2(0.5, 1.0))

	# 5 undulating ribbon blades rising 1.08..2.45 m from the rocky holdfast:
	# [azimuth, root_offset, height, max_width, lean_out, curl_amp, phase_01]
	var blades: Array[Array] = [
		[0.20, 0.05, 2.45, 0.23, 0.34, 0.14, 0.00],
		[1.48, 0.10, 2.15, 0.21, 0.44, 0.16, 0.23],
		[2.74, 0.10, 1.80, 0.20, 0.50, 0.15, 0.47],
		[3.96, 0.12, 1.44, 0.19, 0.54, 0.12, 0.71],
		[5.22, 0.11, 1.08, 0.17, 0.46, 0.10, 0.89],
	]

	var segs := 7
	var col_root := Color(0.56, 0.62, 0.58, 1.0)
	var col_mid := Color(0.88, 0.92, 0.85, 1.0)
	var col_tip := Color(1.00, 1.00, 0.94, 1.0)

	for spec in blades:
		var ang: float = float(spec[0])
		var roff: float = float(spec[1])
		var height: float = float(spec[2])
		var max_w: float = float(spec[3])
		var lean: float = float(spec[4])
		var curl: float = float(spec[5])
		var phase_01: float = float(spec[6])

		var rad := Vector3(cos(ang), 0.0, sin(ang))
		var side := Vector3(-sin(ang), 0.0, cos(ang))
		var uv2 := Vector2(phase_01, 0.0)

		var left_pts: Array[Vector3] = []
		var mid_pts: Array[Vector3] = []
		var right_pts: Array[Vector3] = []
		var t_vals: Array[float] = []

		for s in range(segs + 1):
			var t := float(s) / float(segs)
			t_vals.append(t)
			var y := 0.03 + height * t
			var r_out := roff + lean * pow(t, 1.32) + sin(t * PI * 1.65) * curl
			var lat_wiggle := sin(t * PI * 2.15 + phase_01 * TAU) * (0.10 * t)
			var ctr := rad * r_out + side * lat_wiggle + Vector3(0.0, y, 0.0)

			# Ruffled kelp width envelope: sturdy stipe -> broad undulating lamina -> pointed tip.
			var envelope := sin(pow(t, 0.68) * PI)
			var stipe := (1.0 - smoothstep(0.0, 0.22, t)) * 0.26
			var ruffle := 1.0 + 0.16 * sin(t * PI * 5.0 + phase_01 * TAU)
			var half_w := max_w * 0.5 * maxf(envelope * ruffle, stipe) * (1.0 - smoothstep(0.92, 1.0, t))

			var twist := sin(t * PI * 1.45 + phase_01 * TAU) * 0.46
			var blade_side := (side * cos(twist) + rad * sin(twist)).normalized()
			var blade_n := (rad * cos(twist) - side * sin(twist)).normalized()
			var crease := blade_n * (half_w * 0.26)

			left_pts.append(ctr - blade_side * half_w)
			mid_pts.append(ctr + crease)
			right_pts.append(ctr + blade_side * half_w)

		for s in segs:
			var t0: float = t_vals[s]
			var t1: float = t_vals[s + 1]
			var uv_y0 := 1.0 - t0
			var uv_y1 := 1.0 - t1

			var c0 := col_root.lerp(col_mid, smoothstep(0.0, 0.55, t0)).lerp(col_tip, smoothstep(0.55, 1.0, t0))
			var c1 := col_root.lerp(col_mid, smoothstep(0.0, 0.55, t1)).lerp(col_tip, smoothstep(0.55, 1.0, t1))
			var c0_mid := c0 * Color(0.90, 0.92, 0.90, 1.0)
			var c1_mid := c1 * Color(0.90, 0.92, 0.90, 1.0)

			if s < segs - 1:
				# Left half of V-creased kelp blade.
				_add_flat_tri(st, left_pts[s], left_pts[s + 1], mid_pts[s + 1],
					c0, c1, c1_mid, Vector2(0.0, uv_y0), Vector2(0.0, uv_y1), Vector2(0.5, uv_y1), uv2)
				_add_flat_tri(st, left_pts[s], mid_pts[s + 1], mid_pts[s],
					c0, c1_mid, c0_mid, Vector2(0.0, uv_y0), Vector2(0.5, uv_y1), Vector2(0.5, uv_y0), uv2)
				# Right half of V-creased kelp blade.
				_add_flat_tri(st, mid_pts[s], mid_pts[s + 1], right_pts[s + 1],
					c0_mid, c1_mid, c1, Vector2(0.5, uv_y0), Vector2(0.5, uv_y1), Vector2(1.0, uv_y1), uv2)
				_add_flat_tri(st, mid_pts[s], right_pts[s + 1], right_pts[s],
					c0_mid, c1, c0, Vector2(0.5, uv_y0), Vector2(1.0, uv_y1), Vector2(1.0, uv_y0), uv2)
			else:
				# Graceful pointed ribbon tip meeting at mid_pts[segs].
				var tip_pt := mid_pts[segs]
				_add_flat_tri(st, left_pts[s], tip_pt, mid_pts[s],
					c0, col_tip, c0_mid, Vector2(0.0, uv_y0), Vector2(0.5, 0.0), Vector2(0.5, uv_y0), uv2)
				_add_flat_tri(st, mid_pts[s], tip_pt, right_pts[s],
					c0_mid, col_tip, c0, Vector2(0.5, uv_y0), Vector2(0.5, 0.0), Vector2(1.0, uv_y0), uv2)

	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ SurfaceTool primitives

static func _append_holdfast_base(st: SurfaceTool, center: Vector3, rx: float, ry: float,
		rz: float, bot_y: float, segs: int, col_bot: Color, col_top: Color,
		fixed_uv: Vector2 = Vector2(0.5, 0.5)) -> void:
	var bot_ring: Array[Vector3] = []
	var mid_ring: Array[Vector3] = []
	for k in segs:
		var ang := float(k) / float(segs) * TAU
		var jit := 0.90 + 0.16 * sin(ang * 3.0 + center.x * 4.0)
		bot_ring.append(center + Vector3(cos(ang) * rx * jit, bot_y, sin(ang) * rz * jit))
		mid_ring.append(center + Vector3(cos(ang) * rx * 0.72 * jit, ry * 0.65, sin(ang) * rz * 0.72 * jit))
	var crown := center + Vector3(0.0, ry, 0.0)
	var ref_ctr := center + Vector3(0.0, (bot_y + ry) * 0.35, 0.0)
	var col_mid := col_bot.lerp(col_top, 0.58)
	for k in segs:
		var nk := (k + 1) % segs
		_add_outward_quad(st, bot_ring[k], mid_ring[k], mid_ring[nk], bot_ring[nk], ref_ctr,
			col_bot, col_mid, col_mid, col_bot, fixed_uv)
		_add_outward_tri(st, mid_ring[k], crown, mid_ring[nk], ref_ctr,
			col_mid, col_top, col_mid, fixed_uv)


static func _append_tapered_limb(st: SurfaceTool, p0: Vector3, p1: Vector3, r0: float,
		r1: float, sides: int, col0: Color, col1: Color, cap_tip: bool) -> void:
	var axis := p1 - p0
	var seg_len := axis.length()
	if seg_len < 0.001:
		return
	var dir := axis / seg_len
	var ref := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
	var u := dir.cross(ref).normalized()
	var v := dir.cross(u).normalized()

	var ring0: Array[Vector3] = []
	var ring1: Array[Vector3] = []
	for i in sides:
		var ang := float(i) / float(sides) * TAU
		var radial := u * cos(ang) + v * sin(ang)
		ring0.append(p0 + radial * r0)
		ring1.append(p1 + radial * r1)

	var mid_ctr := (p0 + p1) * 0.5
	for i in sides:
		var ni := (i + 1) % sides
		_add_outward_quad(st, ring0[i], ring1[i], ring1[ni], ring0[ni], mid_ctr,
			col0, col1, col1, col0)

	if cap_tip:
		# Chunky beveled sunlit coral polyp crown cap (never a sharp needle).
		var collar_center := p1 + dir * (r1 * 0.52)
		var apex := p1 + dir * (r1 * 1.05)
		var col_crown := Color(1.0, 1.0, 0.98, 1.0)
		var collar: Array[Vector3] = []
		for i in sides:
			var ang := float(i) / float(sides) * TAU
			var radial := u * cos(ang) + v * sin(ang)
			collar.append(collar_center + radial * (r1 * 0.72))
		var tip_ref := p1 - dir * (r1 * 0.5)
		for i in sides:
			var ni := (i + 1) % sides
			_add_outward_quad(st, ring1[i], collar[i], collar[ni], ring1[ni], tip_ref,
				col1, col_crown, col_crown, col1)
			_add_outward_tri(st, collar[i], apex, collar[ni], tip_ref,
				col_crown, col_crown, col_crown)


static func _add_outward_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color, cd: Color,
		uv: Vector2 = Vector2(0.5, 0.5)) -> void:
	_add_outward_tri(st, a, b, c, ref_center, ca, cb, cc, uv)
	_add_outward_tri(st, a, c, d, ref_center, ca, cc, cd, uv)


static func _add_outward_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color,
		uv: Vector2 = Vector2(0.5, 0.5)) -> void:
	# Godot front-face winding is CW -> outward normal is (c - a) x (b - a).
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-10:
		return
	var centroid := (a + b + c) / 3.0
	if n.dot(centroid - ref_center) < 0.0:
		var tmp_v := b
		b = c
		c = tmp_v
		var tmp_c := cb
		cb = cc
		cc = tmp_c
	_add_flat_tri(st, a, b, c, ca, cb, cc, uv, uv, uv, Vector2.ZERO)


static func _add_flat_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color, uva: Vector2, uvb: Vector2, uvc: Vector2,
		uv2: Vector2) -> void:
	if (c - a).cross(b - a).length_squared() < 1e-10:
		return
	st.set_smooth_group(-1)
	st.set_color(ca)
	st.set_uv(uva)
	st.set_uv2(uv2)
	st.add_vertex(a)

	st.set_smooth_group(-1)
	st.set_color(cb)
	st.set_uv(uvb)
	st.set_uv2(uv2)
	st.add_vertex(b)

	st.set_smooth_group(-1)
	st.set_color(cc)
	st.set_uv(uvc)
	st.set_uv2(uv2)
	st.add_vertex(c)
