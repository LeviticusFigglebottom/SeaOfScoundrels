class_name IslandWaterfall
extends Node3D
## Dynamic live cliffside island waterfall featuring a zero-primitive sculpted
## parabolic cascading water curtain (`waterfall.gdshader`), pulsing concentric
## plunge-pool foam apron, billowing distance-culled spray mist, and leak-free cache teardown.

const WATERFALL_SHADER: Shader = preload("res://src/world/waterfall.gdshader")
const CULL_DIST := 240.0
const SHEET_COLS := 10
const SHEET_ROWS := 18

# Statically cached shared pool foam, mist & sunlit rainbow arch assets across all active waterfalls.
static var _active_waterfalls: int = 0
static var _pool_foam_mesh: ArrayMesh = null
static var _pool_foam_mat: StandardMaterial3D = null
static var _mist_tex: ImageTexture = null
static var _mist_mat: StandardMaterial3D = null
static var _mist_card_mesh: ArrayMesh = null
static var _rainbow_mesh: ArrayMesh = null
static var _rainbow_mat: StandardMaterial3D = null

@export var height_m: float = 16.0
@export var width_m: float = 4.2
@export var out_reach_m: float = 0.0
@export var enable_effects: bool = true

var waterfall_sheet: MeshInstance3D = null
var plunge_pool_foam: MeshInstance3D = null
var waterfall_mist: GPUParticles3D = null
var waterfall_rainbow: MeshInstance3D = null

var _sheet_mesh: ArrayMesh = null
var _sheet_mat: ShaderMaterial = null
var _out_reach: float = 3.8
var _clock: float = 0.0
var _distance_active: bool = true
var _tri_count: int = 0
var _rainbow_strength: float = 0.0


## Create a configured cliffside waterfall dropping `p_height_m` metres at width `p_width_m`.
static func create(p_height_m: float = 16.0, p_width_m: float = 4.2) -> IslandWaterfall:
	var wf := IslandWaterfall.new()
	wf.name = "IslandWaterfall"
	wf.height_m = maxf(2.0, p_height_m)
	wf.width_m = maxf(0.8, p_width_m)
	return wf


## Release all statically cached waterfall pool, mist & rainbow arch assets cleanly.
static func clear_shared_cache() -> void:
	if _mist_mat != null:
		_mist_mat.albedo_texture = null
	_pool_foam_mesh = null
	_pool_foam_mat = null
	_mist_tex = null
	_mist_mat = null
	_mist_card_mesh = null
	_rainbow_mesh = null
	_rainbow_mat = null


func _enter_tree() -> void:
	_active_waterfalls += 1
	add_to_group(&"island_waterfalls")


func _ready() -> void:
	_ensure_shared_assets()
	_out_reach = clampf(out_reach_m, 2.2, 22.0) if out_reach_m > 0.1 else clampf(height_m * 0.24, 1.8, 5.2)

	# 1. Parabolic cascading water curtain (10x18 subdivided sculpted ArrayMesh).
	_sheet_mesh = _build_waterfall_sheet_mesh(height_m, width_m, _out_reach)
	_sheet_mat = ShaderMaterial.new()
	_sheet_mat.shader = WATERFALL_SHADER
	_sheet_mat.set_shader_parameter(&"flow_speed", clampf(1.25 + height_m * 0.015, 1.2, 1.8))

	waterfall_sheet = MeshInstance3D.new()
	waterfall_sheet.name = "WaterfallSheet"
	waterfall_sheet.mesh = _sheet_mesh
	waterfall_sheet.material_override = _sheet_mat
	waterfall_sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	waterfall_sheet.visibility_range_end = CULL_DIST + 120.0
	add_child(waterfall_sheet)

	var rainbow_local_y := -height_m + 0.55
	var mist_local_y := -height_m + 0.35
	var parent_isl := get_parent()
	if parent_isl != null and parent_isl.has_method(&"surface_height"):
		var pool_in_isl := transform * Vector3(0.0, 0.0, -_out_reach)
		var pool_surf_y := float(parent_isl.call(&"surface_height", pool_in_isl.x, pool_in_isl.z))
		var impact_y := clampf(pool_surf_y - position.y, -height_m, -1.2)
		mist_local_y = maxf(mist_local_y, impact_y + 0.45)
		var rb_in_isl := transform * Vector3(0.0, 0.0, -_out_reach - 0.85)
		var rb_surf_y := float(parent_isl.call(&"surface_height", rb_in_isl.x, rb_in_isl.z))
		var rb_impact_y := clampf(rb_surf_y - position.y, -height_m, -0.8)
		rainbow_local_y = maxf(rainbow_local_y, maxf(impact_y, rb_impact_y) + 0.35)

	# 2. Concentric aerated whitewater plunge-pool foam apron disk/ring (strictly basin-anchored).
	plunge_pool_foam = MeshInstance3D.new()
	plunge_pool_foam.name = "PlungePoolFoam"
	plunge_pool_foam.mesh = _pool_foam_mesh
	plunge_pool_foam.material_override = _pool_foam_mat
	var pool_radius := maxf(width_m * 0.92, 2.6)
	plunge_pool_foam.position = Vector3(0.0, -height_m + 0.08, -_out_reach)
	plunge_pool_foam.scale = Vector3(pool_radius, 1.0, pool_radius * 0.85)
	plunge_pool_foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plunge_pool_foam.visibility_range_end = CULL_DIST + 80.0
	add_child(plunge_pool_foam)

	# 3. Sunlit additive 7-band prismatic mist-rainbow arch hovering over the plunge basin.
	waterfall_rainbow = MeshInstance3D.new()
	waterfall_rainbow.name = "WaterfallMistRainbow"
	waterfall_rainbow.mesh = _rainbow_mesh
	waterfall_rainbow.material_override = _rainbow_mat
	var rainbow_scale := maxf(width_m * 1.15, 3.2)
	waterfall_rainbow.position = Vector3(0.0, rainbow_local_y, -_out_reach - 0.85)
	waterfall_rainbow.scale = Vector3.ONE * rainbow_scale
	waterfall_rainbow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	waterfall_rainbow.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	waterfall_rainbow.visibility_range_end = CULL_DIST + 40.0
	add_child(waterfall_rainbow)

	_tri_count = _count_mesh_tris(_sheet_mesh) + _count_mesh_tris(_pool_foam_mesh) + _count_mesh_tris(_rainbow_mesh)

	# 4. Sunlit billowing plunge-pool spray & mist GPUParticles3D (zero-primitive ArrayMesh card!).
	if enable_effects:
		waterfall_mist = _build_mist_particles(width_m)
		waterfall_mist.position = Vector3(0.0, mist_local_y, -_out_reach)
		add_child(waterfall_mist)

	tick_atmosphere()


func _exit_tree() -> void:
	for mi: MeshInstance3D in [waterfall_sheet, plunge_pool_foam, waterfall_rainbow]:
		if mi != null and is_instance_valid(mi):
			mi.material_override = null
			mi.mesh = null
	if waterfall_mist != null and is_instance_valid(waterfall_mist):
		waterfall_mist.emitting = false
		waterfall_mist.visible = false
		var pm := waterfall_mist.process_material as ParticleProcessMaterial
		if pm != null:
			pm.color_ramp = null
		waterfall_mist.material_override = null
		waterfall_mist.draw_pass_1 = null
		waterfall_mist.process_material = null
	waterfall_sheet = null
	plunge_pool_foam = null
	waterfall_rainbow = null
	waterfall_mist = null
	_sheet_mesh = null
	_sheet_mat = null
	_rainbow_strength = 0.0
	_active_waterfalls = maxi(0, _active_waterfalls - 1)
	if _active_waterfalls == 0:
		clear_shared_cache()


func _process(delta: float) -> void:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam != null:
		var mid_pos := global_position + Vector3(0.0, -height_m * 0.5, -_out_reach * 0.5)
		var in_range := cam.global_position.distance_squared_to(mid_pos) <= CULL_DIST * CULL_DIST
		if in_range != _distance_active:
			set_distance_active(in_range)
	if not _distance_active:
		return

	_clock += delta
	if plunge_pool_foam != null and is_instance_valid(plunge_pool_foam):
		var base_r := maxf(width_m * 0.92, 2.6)
		var pulse := 1.0 + 0.065 * sin(_clock * 3.1) + 0.03 * cos(_clock * 6.4)
		plunge_pool_foam.scale = Vector3(base_r * pulse, 1.0, base_r * 0.85 * (2.0 - pulse))
		plunge_pool_foam.rotation.y += delta * 0.24
	tick_atmosphere()


## Return total sculpted triangle count across the waterfall sheet, plunge-pool foam, and mist rainbow.
func get_triangle_count() -> int:
	return _tri_count


## Return the sculpted additive prismatic WaterfallMistRainbow MeshInstance3D.
func get_mist_rainbow_node() -> MeshInstance3D:
	return waterfall_rainbow


## Return current sunlit prismatic mist-rainbow intensity (0.0 at night/storm/culled, ~0.55 in clear daylight).
func get_mist_rainbow_strength() -> float:
	return _rainbow_strength


## Refresh sunlit prismatic mist-rainbow visibility & shimmer from current Weather daylight/storminess.
func tick_atmosphere() -> void:
	if waterfall_rainbow == null or not is_instance_valid(waterfall_rainbow):
		_rainbow_strength = 0.0
		return
	if not _distance_active:
		_rainbow_strength = 0.0
		waterfall_rainbow.visible = false
		return
	var day_f := Weather.daylight() if Weather != null else 1.0
	var storm_f := Weather.storminess if Weather != null else 0.0
	var sun_clear := clampf(day_f * (1.0 - storm_f * 0.85), 0.0, 1.0)
	var arc_fade := smoothstep(0.22, 0.85, sun_clear)
	if arc_fade <= 0.005:
		_rainbow_strength = 0.0
		waterfall_rainbow.visible = false
		if _rainbow_mat != null:
			_rainbow_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
		return
	var shimmer := 0.55 + 0.055 * sin(_clock * 1.45) + 0.025 * cos(_clock * 2.75)
	_rainbow_strength = arc_fade * shimmer
	waterfall_rainbow.visible = true
	if _rainbow_mat != null:
		_rainbow_mat.albedo_color = Color(_rainbow_strength, _rainbow_strength, _rainbow_strength, 1.0)


## Toggle mist emission, rainbow arch, and plunge-pool animation cleanly for distance culling or tests.
func set_distance_active(active: bool) -> void:
	_distance_active = active
	if waterfall_mist != null and is_instance_valid(waterfall_mist):
		waterfall_mist.emitting = active and enable_effects
		waterfall_mist.visible = active and enable_effects
	tick_atmosphere()


# ==============================================================================
# Particle Emitter & Shared Sculpted Zero-Primitive Asset Builders
# ==============================================================================

func _build_mist_particles(w_m: float) -> GPUParticles3D:
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(maxf(w_m * 0.55, 1.2), 0.35, 0.95)
	proc.direction = Vector3(0.0, 0.72, -0.68).normalized()
	proc.spread = 46.0
	proc.initial_velocity_min = 1.1
	proc.initial_velocity_max = 2.6
	proc.gravity = Vector3(0.0, -0.35, 0.0)
	proc.damping_min = 0.8
	proc.damping_max = 1.4
	proc.scale_min = 1.65
	proc.scale_max = 3.25

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.22, 0.72, 1.0])
	grad.colors = PackedColorArray([
		Color(0.95, 0.99, 1.0, 0.0),
		Color(0.94, 0.99, 0.99, 0.44),
		Color(0.76, 0.95, 0.96, 0.24),
		Color(0.68, 0.92, 0.94, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.width = 16
	ramp.gradient = grad
	proc.color_ramp = ramp

	var gp := GPUParticles3D.new()
	gp.name = "WaterfallMist"
	gp.amount = 18
	gp.lifetime = 2.15
	gp.preprocess = 0.8
	gp.local_coords = false
	gp.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gp.visibility_aabb = AABB(Vector3(-8.0, -3.0, -8.0), Vector3(16.0, 12.0, 16.0))
	gp.process_material = proc
	gp.draw_pass_1 = _mist_card_mesh
	gp.material_override = _mist_mat
	gp.emitting = _distance_active
	gp.visible = _distance_active
	return gp


static func _ensure_shared_assets() -> void:
	if _pool_foam_mesh == null:
		_pool_foam_mesh = _build_plunge_pool_foam_mesh()
	if _pool_foam_mat == null:
		_pool_foam_mat = StandardMaterial3D.new()
		_pool_foam_mat.vertex_color_use_as_albedo = true
		_pool_foam_mat.vertex_color_is_srgb = true
		_pool_foam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_pool_foam_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_pool_foam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_pool_foam_mat.roughness = 0.65
		_pool_foam_mat.metallic = 0.02
	if _mist_tex == null:
		_mist_tex = _make_soft_mist_texture()
	if _mist_mat == null:
		_mist_mat = StandardMaterial3D.new()
		_mist_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mist_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mist_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_mist_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mist_mat.vertex_color_use_as_albedo = true
		_mist_mat.albedo_texture = _mist_tex
	if _mist_card_mesh == null:
		_mist_card_mesh = _build_billboard_card_mesh(1.0)
	if _rainbow_mesh == null:
		_rainbow_mesh = _build_mist_rainbow_mesh()
	if _rainbow_mat == null:
		_rainbow_mat = StandardMaterial3D.new()
		_rainbow_mat.vertex_color_use_as_albedo = true
		_rainbow_mat.vertex_color_is_srgb = true
		_rainbow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_rainbow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_rainbow_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_rainbow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_rainbow_mat.albedo_color = Color(0.55, 0.55, 0.55, 1.0)


static func _build_mist_rainbow_mesh() -> ArrayMesh:
	# Curved 7-band prismatic mist-rainbow arch (20x7x2 = 280 tris, zero primitives, zero textures).
	# Soft red -> orange -> gold -> emerald -> cyan -> indigo spectral bands feather cleanly to
	# Color(0, 0, 0, 1) at inner rim, outer rim, and both base arch ends for seamless additive blending.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const ARC_SEGS := 20

	var ring_specs: Array[Array] = [
		[0.56, Color(0.00, 0.00, 0.00, 1.0)],  # Inner rim fade (pure black under additive blend)
		[0.63, Color(0.30, 0.22, 0.66, 1.0)],  # Indigo
		[0.69, Color(0.16, 0.62, 0.78, 1.0)],  # Cyan
		[0.75, Color(0.20, 0.74, 0.44, 1.0)],  # Emerald
		[0.81, Color(0.84, 0.74, 0.22, 1.0)],  # Gold
		[0.87, Color(0.86, 0.46, 0.16, 1.0)],  # Orange
		[0.93, Color(0.82, 0.22, 0.20, 1.0)],  # Soft Red
		[1.02, Color(0.00, 0.00, 0.00, 1.0)],  # Outer rim fade (pure black under additive blend)
	]
	var ring_count := ring_specs.size()
	var pt_grid: Array[Array] = []
	var col_grid: Array[Array] = []
	for s in range(ARC_SEGS + 1):
		var u := float(s) / float(ARC_SEGS)
		var theta := u * PI
		var end_fade := smoothstep(0.0, 0.22, u) * smoothstep(0.0, 0.22, 1.0 - u)
		var sin_t := sin(theta)
		var cos_t := cos(theta)
		var pts: Array[Vector3] = []
		var cols: Array[Color] = []
		for ri in ring_count:
			var spec: Array = ring_specs[ri]
			var rad := float(spec[0])
			var base_c: Color = spec[1] as Color
			pts.append(Vector3(-cos_t * rad, sin_t * rad * 0.86, -0.14 * sin_t * rad))
			cols.append(Color(base_c.r * end_fade, base_c.g * end_fade, base_c.b * end_fade, 1.0))
		pt_grid.append(pts)
		col_grid.append(cols)

	for s in ARC_SEGS:
		var pts0: Array = pt_grid[s]
		var pts1: Array = pt_grid[s + 1]
		var cols0: Array = col_grid[s]
		var cols1: Array = col_grid[s + 1]
		for ri in range(ring_count - 1):
			var p00: Vector3 = pts0[ri] as Vector3
			var p10: Vector3 = pts1[ri] as Vector3
			var p01: Vector3 = pts0[ri + 1] as Vector3
			var p11: Vector3 = pts1[ri + 1] as Vector3
			var c00: Color = cols0[ri] as Color
			var c10: Color = cols1[ri] as Color
			var c01: Color = cols0[ri + 1] as Color
			var c11: Color = cols1[ri + 1] as Color

			st.set_smooth_group(1)
			st.set_color(c00)
			st.add_vertex(p00)
			st.set_smooth_group(1)
			st.set_color(c10)
			st.add_vertex(p10)
			st.set_smooth_group(1)
			st.set_color(c11)
			st.add_vertex(p11)

			st.set_smooth_group(1)
			st.set_color(c00)
			st.add_vertex(p00)
			st.set_smooth_group(1)
			st.set_color(c11)
			st.add_vertex(p11)
			st.set_smooth_group(1)
			st.set_color(c01)
			st.add_vertex(p01)

	st.generate_normals()
	return st.commit()


static func _build_waterfall_sheet_mesh(h_m: float, w_m: float, out_reach: float) -> ArrayMesh:
	# 10x18 parabolic gravity-curved waterfall curtain arching outward along -Z and flaring wider at splash base!
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var grid: Array[Array] = []
	var uv_grid: Array[Array] = []
	for r in range(SHEET_ROWS + 1):
		var v := float(r) / float(SHEET_ROWS)
		# Gravity fall curve: accelerates downward (y = -h_m * v^1.18), arches cleanly out along -Z!
		var py := -h_m * pow(v, 1.12)
		var pz_base := -out_reach * pow(v, 0.56)
		var flare := lerpf(0.88, 1.38, pow(v, 1.15))
		var half_w := w_m * 0.5 * flare
		var row_pts: Array[Vector3] = []
		var row_uvs: Array[Vector2] = []
		for c in range(SHEET_COLS + 1):
			var u := float(c) / float(SHEET_COLS)
			var px := lerpf(-half_w, half_w, u)
			# Subtle convex forward arch across curtain width so it catches side sunlight richly.
			var arch_z := -0.24 * sin(u * PI) * (0.45 + 0.55 * v)
			row_pts.append(Vector3(px, py, pz_base + arch_z))
			row_uvs.append(Vector2(u, v))
		grid.append(row_pts)
		uv_grid.append(row_uvs)

	for r in SHEET_ROWS:
		var r0: Array = grid[r]
		var r1: Array = grid[r + 1]
		var uv0: Array = uv_grid[r]
		var uv1: Array = uv_grid[r + 1]
		for c in SHEET_COLS:
			var p00: Vector3 = r0[c] as Vector3
			var p10: Vector3 = r0[c + 1] as Vector3
			var p01: Vector3 = r1[c] as Vector3
			var p11: Vector3 = r1[c + 1] as Vector3
			var t00: Vector2 = uv0[c] as Vector2
			var t10: Vector2 = uv0[c + 1] as Vector2
			var t01: Vector2 = uv1[c] as Vector2
			var t11: Vector2 = uv1[c + 1] as Vector2

			# Outward normal faces -Z (front of cascade).
			st.set_smooth_group(1)
			st.set_uv(t00)
			st.add_vertex(p00)
			st.set_smooth_group(1)
			st.set_uv(t01)
			st.add_vertex(p01)
			st.set_smooth_group(1)
			st.set_uv(t11)
			st.add_vertex(p11)

			st.set_smooth_group(1)
			st.set_uv(t00)
			st.add_vertex(p00)
			st.set_smooth_group(1)
			st.set_uv(t11)
			st.add_vertex(p11)
			st.set_smooth_group(1)
			st.set_uv(t10)
			st.add_vertex(p10)

	st.generate_normals()
	return st.commit()


static func _build_plunge_pool_foam_mesh() -> ArrayMesh:
	# Concentric scalloped whitewater plunge-pool foam apron disk/ring (~96 tris, zero raw primitives!).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGS := 16

	var ring_specs: Array[Array] = [
		[0.24, 0.14, Color(0.97, 0.99, 0.99, 0.95)],
		[0.58, 0.06, Color(0.90, 0.98, 0.97, 0.80)],
		[0.88, 0.01, Color(0.68, 0.93, 0.92, 0.44)],
		[1.08, 0.00, Color(0.55, 0.88, 0.90, 0.00)],
	]
	var rings: Array[Array] = []
	var cols: Array[Color] = []
	for ri in ring_specs.size():
		var spec: Array = ring_specs[ri]
		var rad := float(spec[0])
		var y := float(spec[1])
		var ring: Array[Vector3] = []
		for k in SEGS:
			var a := float(k) / float(SEGS) * TAU
			var lobe := 1.0 + 0.12 * sin(a * 5.0 + float(ri) * 0.9) + 0.06 * cos(a * 7.0)
			ring.append(Vector3(cos(a) * rad * lobe, y, sin(a) * rad * lobe))
		rings.append(ring)
		cols.append(spec[2] as Color)

	# Inner frothy boiling cap.
	var center_pt := Vector3(0.0, 0.18, 0.0)
	var c_core := Color(0.98, 1.0, 1.0, 0.98)
	var r_inner: Array = rings[0]
	for k in SEGS:
		var nk := (k + 1) % SEGS
		_emit_up_tri(st, center_pt, r_inner[nk] as Vector3, r_inner[k] as Vector3, c_core, cols[0], cols[0])

	# Concentric aerated foam rings feathering cleanly out to transparent aqua rim.
	for ri in range(rings.size() - 1):
		var r0: Array = rings[ri]
		var r1: Array = rings[ri + 1]
		var c0 := cols[ri]
		var c1 := cols[ri + 1]
		for k in SEGS:
			var nk := (k + 1) % SEGS
			_emit_up_tri(st, r0[k] as Vector3, r0[nk] as Vector3, r1[nk] as Vector3, c0, c0, c1)
			_emit_up_tri(st, r0[k] as Vector3, r1[nk] as Vector3, r1[k] as Vector3, c0, c1, c1)

	st.generate_normals()
	return st.commit()


static func _build_billboard_card_mesh(sz: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := sz * 0.5
	var p0 := Vector3(-h, h, 0.0)
	var p1 := Vector3(h, h, 0.0)
	var p2 := Vector3(h, -h, 0.0)
	var p3 := Vector3(-h, -h, 0.0)
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


static func _make_soft_mist_texture() -> ImageTexture:
	var sz := 48
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var half := float(sz - 1) * 0.5
	for y in sz:
		for x in sz:
			var nx := (float(x) - half) / half
			var ny := (float(y) - half) / half
			var r := sqrt(nx * nx + ny * ny)
			var w := clampf(1.0 - r, 0.0, 1.0)
			var alpha := w * w * smoothstep(0.0, 0.5, w)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)


static func _emit_up_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	if n.y < 0.0:
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


static func _count_mesh_tris(mesh: ArrayMesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		total += floori(float(verts.size()) / 3.0)
	return total
