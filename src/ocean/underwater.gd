class_name Underwater
extends Node3D
## Underwater view for `Ocean`: a full-screen pass that fogs, tints and lights
## the scene while the camera lens is (partly) below the water surface, paired
## with camera-wrapping volumetric `UnderwaterPlanktonMotes` marine snow /
## nocturnal bioluminescent plankton. The surface seen from below (Snell's
## window) is drawn by ocean.gdshader itself; this pass is drawn first so the
## surface composites over it.

const SHADER := preload("res://src/ocean/underwater.gdshader")
const DETAIL_TEX := preload("res://assets/generated/ocean/water_detail.png")

## Show the pass while the camera is within this many metres above the surface.
const NEAR_SURFACE := 0.6

# Q20B volumetric camera-wrapping UnderwaterPlanktonMotes constants (sRGB).
const PLANKTON_COUNT := 36
const PLANKTON_VOL_X := 14.0
const PLANKTON_VOL_Y := 8.0
const PLANKTON_VOL_Z := 14.0
const PLANKTON_SUBMERGE_MIN_DEPTH := 0.15
const PLANKTON_SURFACE_CLEARANCE := 0.25
const PLANKTON_VISIBILITY_END := 40.0
const PLANKTON_EXTRA_CULL_MARGIN := 20.0

const COL_PLANKTON_TIP := Color(0.96, 1.00, 1.00, 1.0)
const COL_PLANKTON_EQ := Color(0.76, 0.96, 0.98, 1.0)
const COL_PLANKTON_DAY_A := Color(0.62, 0.94, 0.92, 1.0)
const COL_PLANKTON_DAY_B := Color(0.84, 0.98, 0.88, 1.0)
const COL_PLANKTON_NIGHT_A := Color(0.18, 0.96, 0.92, 1.0)
const COL_PLANKTON_NIGHT_B := Color(0.42, 1.00, 0.98, 1.0)

var material: ShaderMaterial
var _quad: MeshInstance3D
var _ocean: Node3D
var _plankton_motes_mmi: MultiMeshInstance3D = null
var _plankton_clock: float = 0.0
var _pending_dt: float = 0.0
var _plankton_biolum_factor: float = 0.0

# Preallocated camera-wrapping plankton buffers (zero steady-state heap allocations).
var _plankton_seed_x := PackedFloat32Array()
var _plankton_seed_y := PackedFloat32Array()
var _plankton_seed_z := PackedFloat32Array()
var _plankton_drift_x := PackedFloat32Array()
var _plankton_drift_y := PackedFloat32Array()
var _plankton_drift_z := PackedFloat32Array()
var _plankton_phase := PackedFloat32Array()
var _plankton_scale := PackedFloat32Array()
var _plankton_tint := PackedFloat32Array()
var _plankton_pos := PackedVector3Array()
var _plankton_colors := PackedColorArray()

# Ref-counted static sculpted ArrayMesh & zero-VRAM material caches (zero ObjectDB leaks).
static var _active_underwaters: int = 0
static var _plankton_mesh: ArrayMesh = null
static var _plankton_mat: StandardMaterial3D = null


## Release statically cached sculpted plankton mesh & material cleanly.
static func clear_shared_cache() -> void:
	_plankton_mesh = null
	_plankton_mat = null


func _enter_tree() -> void:
	_active_underwaters += 1


func _exit_tree() -> void:
	_release_local_refs()
	_active_underwaters = maxi(0, _active_underwaters - 1)
	if _active_underwaters == 0:
		clear_shared_cache()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_release_local_refs()
		if _active_underwaters == 0:
			clear_shared_cache()


func _release_local_refs() -> void:
	_ocean = null
	if _quad != null and is_instance_valid(_quad):
		_quad.visible = false
		_quad.material_override = null
	_quad = null
	if _plankton_motes_mmi != null and is_instance_valid(_plankton_motes_mmi):
		_plankton_motes_mmi.visible = false
		_plankton_motes_mmi.material_override = null
		_plankton_motes_mmi.multimesh = null
	_plankton_motes_mmi = null
	if material != null:
		material.set_shader_parameter(&"detail_tex", null)
	material = null


func _process(delta: float) -> void:
	_pending_dt = minf(_pending_dt + maxf(delta, 0.0), 0.25)


func setup(ocean: Node3D) -> void:
	_ocean = ocean
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.render_priority = -10  # before the ocean surface
	material.set_shader_parameter(&"detail_tex", DETAIL_TEX)
	Sea.bind_material(material)
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	_quad = MeshInstance3D.new()
	_quad.name = "ScreenPass"
	_quad.mesh = quad
	_quad.material_override = material
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.custom_aabb = AABB(Vector3(-1e6, -1e6, -1e6), Vector3(2e6, 2e6, 2e6))
	_quad.visible = false
	add_child(_quad)

	_build_plankton_motes()


func set_shaft_steps(steps: int) -> void:
	if material != null:
		material.set_shader_parameter(&"uw_shaft_steps", steps)


## Return the MultiMeshInstance3D rendering camera-wrapping UnderwaterPlanktonMotes.
func get_plankton_motes_node() -> MultiMeshInstance3D:
	return _plankton_motes_mmi


## Return the current world-space positions of all 36 camera-wrapping plankton motes.
func get_plankton_positions() -> PackedVector3Array:
	return _plankton_pos.duplicate()


## Return the current per-instance colors of all 36 camera-wrapping plankton motes.
func get_plankton_colors() -> PackedColorArray:
	return _plankton_colors.duplicate()


## Return current 0..1 nocturnal bioluminescence blend factor (0 midday -> 1 midnight).
func get_plankton_biolum_factor() -> float:
	return _plankton_biolum_factor


## Advance underwater current drift and update all 36 camera-wrapping plankton motes.
func step_plankton(delta: float, cam_pos: Vector3, depth: float, in_dry_hull: bool = false) -> void:
	var dt := maxf(delta, 0.0)
	_plankton_clock += dt
	var dl := clampf(Weather.daylight(), 0.0, 1.0) if Weather != null else 1.0
	var biolum := 1.0 - dl
	_plankton_biolum_factor = biolum

	var active := (not in_dry_hull) and depth > PLANKTON_SUBMERGE_MIN_DEPTH
	if _plankton_motes_mmi == null or not is_instance_valid(_plankton_motes_mmi):
		return
	_plankton_motes_mmi.visible = active
	if not active:
		return

	var mm := _plankton_motes_mmi.multimesh
	if mm == null or _plankton_pos.size() != PLANKTON_COUNT:
		return

	if _plankton_motes_mmi.is_inside_tree():
		_plankton_motes_mmi.global_transform = Transform3D(Basis.IDENTITY, cam_pos)
	else:
		_plankton_motes_mmi.transform = Transform3D(Basis.IDENTITY, cam_pos)

	var half_x := PLANKTON_VOL_X * 0.5
	var half_y := PLANKTON_VOL_Y * 0.5
	var half_z := PLANKTON_VOL_Z * 0.5
	var t := _plankton_clock
	var depth_fade := clampf((depth - PLANKTON_SUBMERGE_MIN_DEPTH) / 0.40, 0.15, 1.0)
	var twinkle_freq := lerpf(1.35, 2.45, biolum)
	var base_glow := lerpf(0.44, 0.96, biolum) * depth_fade
	var size_boost := lerpf(0.88, 1.18, biolum)
	var has_sea := Sea != null

	for i in PLANKTON_COUNT:
		var ph := _plankton_phase[i]
		var raw_x := _plankton_seed_x[i] + _plankton_drift_x[i] * t + sin(t * 0.55 + ph) * 0.35
		var raw_y := _plankton_seed_y[i] + _plankton_drift_y[i] * t + sin(t * 0.72 + ph * 1.3) * 0.22
		var raw_z := _plankton_seed_z[i] + _plankton_drift_z[i] * t + cos(t * 0.48 + ph * 0.8) * 0.35

		var ox := fposmod(raw_x - cam_pos.x + half_x, PLANKTON_VOL_X) - half_x
		var oy := fposmod(raw_y - cam_pos.y + half_y, PLANKTON_VOL_Y) - half_y
		var oz := fposmod(raw_z - cam_pos.z + half_z, PLANKTON_VOL_Z) - half_z

		var wx := cam_pos.x + ox
		var wz := cam_pos.z + oz
		var wy := cam_pos.y + oy
		var surf_y := Sea.height(wx, wz) if has_sea else 0.0
		var max_y := surf_y - PLANKTON_SURFACE_CLEARANCE
		if wy > max_y:
			var min_box_y := cam_pos.y - half_y
			var under_span := max_y - min_box_y
			if under_span > 0.25:
				wy = max_y - fposmod(wy - max_y, under_span)
			wy = minf(wy, max_y)

		_plankton_pos[i] = Vector3(wx, wy, wz)
		var local_pos := Vector3(ox, wy - cam_pos.y, oz)

		var edge_x := clampf((half_x - absf(ox)) / 1.4, 0.0, 1.0)
		var edge_y := clampf((half_y - absf(local_pos.y)) / 1.0, 0.0, 1.0)
		var edge_z := clampf((half_z - absf(oz)) / 1.4, 0.0, 1.0)
		var edge_fade := edge_x * edge_y * edge_z
		var near_fade := smoothstep(0.25, 0.95, local_pos.length())

		var sc := _plankton_scale[i] * size_boost * lerpf(0.45, 1.0, edge_fade)
		var rot := Basis.from_euler(Vector3(t * 0.45 + ph, t * 0.65 + ph * 1.7, ph * 0.5))
		mm.set_instance_transform(i, Transform3D(rot.scaled(Vector3(sc, sc, sc)), local_pos))

		var tint := _plankton_tint[i]
		var day_col := COL_PLANKTON_DAY_A.lerp(COL_PLANKTON_DAY_B, tint)
		var night_col := COL_PLANKTON_NIGHT_A.lerp(COL_PLANKTON_NIGHT_B, tint)
		var col := day_col.lerp(night_col, biolum)
		var twinkle := 0.62 + 0.38 * sin(t * twinkle_freq + ph * 2.3)
		var lum := base_glow * twinkle * edge_fade * near_fade
		var inst_col := Color(col.r * lum, col.g * lum, col.b * lum, 1.0)
		_plankton_colors[i] = inst_col
		mm.set_instance_color(i, inst_col)


## Called by Ocean every frame. depth > 0 means the camera is under water.
func update(cam: Camera3D, depth: float) -> void:
	var in_dry_hull := (
		_ocean != null
		and _ocean.has_method(&"is_point_in_dry_hull")
		and bool(_ocean.call(&"is_point_in_dry_hull", cam.global_position))
	)
	var dt := _pending_dt
	_pending_dt = 0.0
	step_plankton(dt, cam.global_position, depth, in_dry_hull)

	var on := (not in_dry_hull) and depth > -NEAR_SURFACE
	if _quad != null and is_instance_valid(_quad):
		_quad.visible = on
	if not on:
		return
	if _quad != null and is_instance_valid(_quad):
		_quad.global_position = cam.global_position
	if material != null:
		material.set_shader_parameter(&"uw_cam_depth", depth)
		material.set_shader_parameter(&"waterline_active", 1.0 if absf(depth) < NEAR_SURFACE else 0.0)


func _build_plankton_motes() -> void:
	_ensure_plankton_shared_assets()

	_plankton_seed_x.resize(PLANKTON_COUNT)
	_plankton_seed_y.resize(PLANKTON_COUNT)
	_plankton_seed_z.resize(PLANKTON_COUNT)
	_plankton_drift_x.resize(PLANKTON_COUNT)
	_plankton_drift_y.resize(PLANKTON_COUNT)
	_plankton_drift_z.resize(PLANKTON_COUNT)
	_plankton_phase.resize(PLANKTON_COUNT)
	_plankton_scale.resize(PLANKTON_COUNT)
	_plankton_tint.resize(PLANKTON_COUNT)
	_plankton_pos.resize(PLANKTON_COUNT)
	_plankton_colors.resize(PLANKTON_COUNT)

	var rng := RandomNumberGenerator.new()
	rng.seed = 0x00020B36
	var cell_x := PLANKTON_VOL_X / 3.0
	var cell_y := PLANKTON_VOL_Y / 3.0
	var cell_z := PLANKTON_VOL_Z / 4.0
	var idx := 0
	for ix in 3:
		for iy in 3:
			for iz in 4:
				_plankton_seed_x[idx] = (float(ix) + rng.randf_range(0.12, 0.88)) * cell_x
				_plankton_seed_y[idx] = (float(iy) + rng.randf_range(0.12, 0.88)) * cell_y
				_plankton_seed_z[idx] = (float(iz) + rng.randf_range(0.12, 0.88)) * cell_z
				_plankton_drift_x[idx] = rng.randf_range(0.14, 0.34)
				_plankton_drift_y[idx] = rng.randf_range(-0.08, 0.09)
				_plankton_drift_z[idx] = rng.randf_range(-0.26, 0.22)
				_plankton_phase[idx] = rng.randf() * TAU
				_plankton_scale[idx] = rng.randf_range(0.62, 1.38)
				_plankton_tint[idx] = rng.randf()
				_plankton_pos[idx] = Vector3.ZERO
				_plankton_colors[idx] = COL_PLANKTON_DAY_A
				idx += 1

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = false
	mm.mesh = _plankton_mesh
	mm.instance_count = PLANKTON_COUNT
	for i in PLANKTON_COUNT:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_color(i, COL_PLANKTON_DAY_A)

	_plankton_motes_mmi = MultiMeshInstance3D.new()
	_plankton_motes_mmi.name = "UnderwaterPlanktonMotes"
	_plankton_motes_mmi.top_level = true
	_plankton_motes_mmi.multimesh = mm
	_plankton_motes_mmi.material_override = _plankton_mat
	_plankton_motes_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_plankton_motes_mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_plankton_motes_mmi.visibility_range_end = PLANKTON_VISIBILITY_END
	_plankton_motes_mmi.extra_cull_margin = PLANKTON_EXTRA_CULL_MARGIN
	_plankton_motes_mmi.custom_aabb = AABB(Vector3(-10.0, -8.0, -10.0), Vector3(20.0, 16.0, 20.0))
	_plankton_motes_mmi.visible = false
	add_child(_plankton_motes_mmi)


static func _ensure_plankton_shared_assets() -> void:
	if _plankton_mesh == null:
		_plankton_mesh = _build_plankton_octahedron_mesh()
	if _plankton_mat == null:
		_plankton_mat = StandardMaterial3D.new()
		_plankton_mat.albedo_color = Color.WHITE
		_plankton_mat.vertex_color_use_as_albedo = true
		_plankton_mat.vertex_color_is_srgb = true
		_plankton_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_plankton_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_plankton_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_plankton_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_plankton_mat.render_priority = 2


## Sculpted exact 8-tri faceted diamond octahedron for UnderwaterPlanktonMotes (0 primitives).
static func _build_plankton_octahedron_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const R_EQ := 0.036
	const R_TOP := 0.056
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
		_emit_outward_tri(st, top, ring[k], ring[nk], COL_PLANKTON_TIP, COL_PLANKTON_EQ, COL_PLANKTON_EQ)
		_emit_outward_tri(st, bot, ring[nk], ring[k], COL_PLANKTON_TIP, COL_PLANKTON_EQ, COL_PLANKTON_EQ)
	return st.commit()


static func _emit_outward_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	var centroid := (a + b + c) / 3.0
	if n.dot(centroid) < 0.0:
		var tv := b
		b = c
		c = tv
		var tc := cb
		cb = cc
		cc = tc
		n = -n
	var n_unit := n.normalized()
	st.set_normal(n_unit)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_normal(n_unit)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_normal(n_unit)
	st.set_color(cc)
	st.add_vertex(c)

