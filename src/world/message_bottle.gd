class_name MessageBottle
extends Node3D
## Washed-up glinting emerald sea-glass message bottle discoverable on tropical
## island beaches.
##
## Features a flat-faceted painterly `SurfaceTool` emerald sea-glass bottle
## (`ArrayMesh`, zero raw primitives) half-buried at a 26-degree tide-washed
## lean inside a damp golden sand collar, holding a visible rolled cream
## parchment scroll tied with twine, sealed by a cork stopper & crimson wax
## crest, plus a gently pulsing distance-gated sunlit glass glint star.
##
## All procedural meshes, materials, and glint textures are statically shared
## across active bottles and released cleanly when the last bottle exits tree.

signal bottle_collected(bottle: MessageBottle, pawn: Node, clue: Dictionary)

const GROUP := &"message_bottles"
const GLINT_CULL_DIST := 55.0

# Painterly tropical sea-glass, sand, parchment, cork & crimson wax palette.
const COL_SAND_SUN := Color(0.87, 0.75, 0.48)
const COL_SAND_DAMP := Color(0.68, 0.54, 0.30)
const COL_SAND_SHADOW := Color(0.49, 0.38, 0.21)
const COL_SHELL := Color(0.94, 0.89, 0.78)
const COL_PARCHMENT_HI := Color(0.96, 0.91, 0.76)
const COL_PARCHMENT_EDGE := Color(0.79, 0.68, 0.47)
const COL_PARCHMENT_CORE := Color(0.42, 0.33, 0.21)
const COL_TWINE := Color(0.68, 0.20, 0.16)
const COL_CORK_HI := Color(0.74, 0.54, 0.32)
const COL_CORK_LO := Color(0.48, 0.32, 0.16)
const COL_WAX_HI := Color(0.82, 0.16, 0.14)
const COL_WAX_MID := Color(0.66, 0.11, 0.10)
const COL_WAX_LO := Color(0.40, 0.06, 0.06)
const COL_GOLD_HI := Color(0.98, 0.82, 0.30)
const COL_GOLD_LO := Color(0.68, 0.48, 0.12)
const COL_GLASS_BELLY := Color(0.14, 0.74, 0.56, 0.54)
const COL_GLASS_SHOULDER := Color(0.10, 0.62, 0.48, 0.64)
const COL_GLASS_THICK := Color(0.06, 0.44, 0.36, 0.78)
const COL_GLASS_LIP := Color(0.24, 0.84, 0.66, 0.74)

@export var clue_id: StringName = &""
@export var target_island_id: String = ""
@export var target_island_name: String = ""
@export var treasure_id: StringName = &"corsair_chest"
@export var clue_text: String = ""

var collected: bool = false
var interactable: Interactable = null

var _visual_root: Node3D = null
var _opaque_mi: MeshInstance3D = null
var _glass_mi: MeshInstance3D = null
var _glint_mi: MeshInstance3D = null
var _clock: float = 0.0
var _glint_phase: float = 0.0

# Statically cached procedural ArrayMeshes, materials & glint texture shared
# across all active bottles and cleared cleanly when `_active_bottles` hits 0.
static var _active_bottles: int = 0
static var _opaque_mesh: ArrayMesh = null
static var _glass_mesh: ArrayMesh = null
static var _glint_mesh: ArrayMesh = null
static var _opaque_mat: StandardMaterial3D = null
static var _metal_mat: StandardMaterial3D = null
static var _glass_mat: StandardMaterial3D = null
static var _glint_tex: ImageTexture = null
static var _glint_mat: StandardMaterial3D = null


func _enter_tree() -> void:
	add_to_group(GROUP)
	_active_bottles += 1


func _ready() -> void:
	_glint_phase = fposmod(float(absi(String(clue_id).hash())) * 0.173 + position.x * 0.23, TAU)
	_build_visual()
	interactable = Interactable.create("Inspect message in a bottle", 0.9)
	interactable.name = "Interactable"
	interactable.reach = 2.8
	interactable.position = Vector3(0.0, 0.24, 0.0)
	interactable.interacted.connect(_on_interacted)
	add_child(interactable)
	if collected:
		_apply_collected_visuals()


func _exit_tree() -> void:
	if interactable != null and is_instance_valid(interactable):
		if interactable.interacted.is_connected(_on_interacted):
			interactable.interacted.disconnect(_on_interacted)
	for mi: MeshInstance3D in [_opaque_mi, _glass_mi, _glint_mi]:
		if mi != null and is_instance_valid(mi):
			mi.material_override = null
			mi.mesh = null
	_opaque_mi = null
	_glass_mi = null
	_glint_mi = null
	_visual_root = null
	_active_bottles = maxi(0, _active_bottles - 1)
	if _active_bottles == 0:
		clear_shared_cache()


## Release all statically cached meshes, materials, and glint texture cleanly.
static func clear_shared_cache() -> void:
	if _glint_mat != null:
		_glint_mat.albedo_texture = null
	_opaque_mesh = null
	_glass_mesh = null
	_glint_mesh = null
	_opaque_mat = null
	_metal_mat = null
	_glass_mat = null
	_glint_tex = null
	_glint_mat = null


## Normalized clue payload emitted when a player inspects and collects the bottle.
func get_clue_dict() -> Dictionary:
	return {
		"clue_id": clue_id,
		"target_island_id": target_island_id,
		"target_island_name": target_island_name,
		"treasure_id": treasure_id,
		"clue_text": clue_text,
		"source_pos": global_position if is_inside_tree() else position,
	}


## Host-authoritative, idempotent collection triggered by interacting with the bottle.
func collect(pawn: Node) -> bool:
	if not Net.is_host() or collected:
		return false
	collected = true
	_apply_collected_visuals()
	if Audio != null:
		Audio.play_sfx(&"ui_open", global_position if is_inside_tree() else position)
	bottle_collected.emit(self, pawn, get_clue_dict())
	return true


func _on_interacted(pawn: Node) -> void:
	collect(pawn)


func _apply_collected_visuals() -> void:
	if interactable != null and is_instance_valid(interactable):
		interactable.enabled = false
	if _visual_root != null and is_instance_valid(_visual_root):
		_visual_root.visible = false
	if _glint_mi != null and is_instance_valid(_glint_mi):
		_glint_mi.visible = false
	set_process(false)


func _process(delta: float) -> void:
	if collected or _glint_mi == null:
		return
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam != null:
		var dist_sq := global_position.distance_squared_to(cam.global_position)
		if dist_sq > GLINT_CULL_DIST * GLINT_CULL_DIST:
			_glint_mi.visible = false
			return
	_glint_mi.visible = true
	_clock += delta
	# Gentle sunlit glass twinkle pulse every ~2.4 s.
	var wave := 0.5 + 0.5 * sin(_clock * 2.6 + _glint_phase)
	var sparkle := 0.38 + 0.72 * pow(wave, 3.0)
	_glint_mi.scale = Vector3.ONE * sparkle
	_glint_mi.rotation.y = _clock * 0.55 + _glint_phase


# ==============================================================================
# Sculpted Flat-Faceted Emerald Sea-Glass Bottle, Sand Mound & Sunlit Glint Star
# ==============================================================================

func _build_visual() -> void:
	_ensure_shared_assets()

	_visual_root = Node3D.new()
	_visual_root.name = "BottleVisual"
	add_child(_visual_root)

	_opaque_mi = MeshInstance3D.new()
	_opaque_mi.name = "BottleCoreMesh"
	_opaque_mi.mesh = _opaque_mesh
	_visual_root.add_child(_opaque_mi)

	_glass_mi = MeshInstance3D.new()
	_glass_mi.name = "BottleGlassMesh"
	_glass_mi.mesh = _glass_mesh
	_glass_mi.material_override = _glass_mat
	_visual_root.add_child(_glass_mi)

	var tilt := _bottle_tilt_transform()
	_glint_mi = MeshInstance3D.new()
	_glint_mi.name = "BottleGlint"
	_glint_mi.mesh = _glint_mesh
	_glint_mi.material_override = _glint_mat
	_glint_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glint_mi.position = tilt * Vector3(0.052, 0.255, 0.044)
	_visual_root.add_child(_glint_mi)


static func _bottle_tilt_transform() -> Transform3D:
	# Charming half-buried 26-degree beach-washed lean tucked into the sand collar.
	var rot := Basis(Vector3.FORWARD, deg_to_rad(26.0)) * Basis(Vector3.RIGHT, deg_to_rad(6.0))
	return Transform3D(rot, Vector3(0.0, -0.025, 0.0))


static func _ensure_shared_assets() -> void:
	if _opaque_mat == null:
		_opaque_mat = StandardMaterial3D.new()
		_opaque_mat.albedo_color = Color.WHITE
		_opaque_mat.vertex_color_use_as_albedo = true
		_opaque_mat.roughness = 0.80
		_opaque_mat.metallic = 0.04

	if _metal_mat == null:
		_metal_mat = StandardMaterial3D.new()
		_metal_mat.albedo_color = Color.WHITE
		_metal_mat.vertex_color_use_as_albedo = true
		_metal_mat.roughness = 0.26
		_metal_mat.metallic = 0.86

	if _glass_mat == null:
		_glass_mat = StandardMaterial3D.new()
		_glass_mat.albedo_color = Color.WHITE
		_glass_mat.vertex_color_use_as_albedo = true
		_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass_mat.roughness = 0.10
		_glass_mat.metallic = 0.08
		_glass_mat.clearcoat_enabled = true
		_glass_mat.clearcoat = 0.95
		_glass_mat.clearcoat_roughness = 0.08
		_glass_mat.emission_enabled = true
		_glass_mat.emission = Color(0.12, 0.50, 0.42)
		_glass_mat.emission_energy_multiplier = 0.18

	if _glint_tex == null:
		_glint_tex = _build_glint_star_texture()

	if _glint_mat == null:
		_glint_mat = StandardMaterial3D.new()
		_glint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glint_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glint_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_glint_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_glint_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_glint_mat.albedo_color = Color(1.0, 0.96, 0.78, 0.94)
		_glint_mat.albedo_texture = _glint_tex

	if _opaque_mesh == null:
		_opaque_mesh = _build_opaque_mesh()
	if _glass_mesh == null:
		_glass_mesh = _build_glass_mesh()
	if _glint_mesh == null:
		_glint_mesh = _build_glint_mesh()


static func _build_opaque_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var matte_st := SurfaceTool.new()
	matte_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gold_st := SurfaceTool.new()
	gold_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var tilt := _bottle_tilt_transform()

	# 1. Damp Golden Sand Mound Collar hugging the half-buried tilted bottle base.
	var sand_stations: Array[Array] = [
		[-0.024, 0.215, COL_SAND_SHADOW],
		[0.004, 0.195, COL_SAND_DAMP],
		[0.038, 0.145, COL_SAND_SUN],
		[0.068, 0.092, COL_SAND_SUN],
		[0.064, 0.056, COL_SAND_DAMP],
		[0.025, 0.000, COL_SAND_SHADOW],
	]
	_add_lathe_y(matte_st, sand_stations, 12, Transform3D(Basis.IDENTITY, Vector3(-0.022, 0.0, 0.005)), 0.09, 3)

	# Three small beach pebbles / pale seashell flecks nestled in the sand collar.
	var shell_spots: Array[Vector3] = [
		Vector3(0.115, 0.026, -0.068),
		Vector3(-0.128, 0.022, 0.054),
		Vector3(0.052, 0.032, 0.112),
	]
	for si in shell_spots.size():
		var r_p := 0.020 + 0.004 * float(si % 2)
		var col_p := COL_SHELL if si != 1 else COL_SAND_SUN.darkened(0.15)
		_add_faceted_stud(matte_st, shell_spots[si], r_p, r_p * 0.55, r_p * 0.85, 6,
			col_p, col_p.darkened(0.20), COL_SAND_SHADOW)

	# 2. Visible Rolled Cream Parchment Scroll tucked inside the translucent emerald bottle!
	var scroll_xf := tilt * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-6.0)) * Basis(Vector3.FORWARD, deg_to_rad(-5.0)),
			Vector3(0.008, 0.042, -0.006))
	var scroll_stations: Array[Array] = [
		[0.000, 0.000, COL_PARCHMENT_CORE],
		[0.004, 0.024, COL_PARCHMENT_CORE],
		[0.000, 0.037, COL_PARCHMENT_EDGE],
		[0.028, 0.035, COL_PARCHMENT_HI],
		[0.095, 0.034, COL_PARCHMENT_HI],
		[0.104, 0.039, COL_TWINE],
		[0.116, 0.039, COL_TWINE.darkened(0.22)],
		[0.124, 0.034, COL_PARCHMENT_HI],
		[0.188, 0.035, COL_PARCHMENT_HI],
		[0.214, 0.038, COL_PARCHMENT_EDGE],
		[0.210, 0.022, COL_PARCHMENT_CORE],
		[0.194, 0.000, COL_PARCHMENT_CORE],
	]
	_add_lathe_y(matte_st, scroll_stations, 10, scroll_xf)

	# 3. Chunky Natural Cork Stopper seated in the glass collar neck.
	var cork_stations: Array[Array] = [
		[0.336, 0.000, COL_CORK_LO],
		[0.336, 0.022, COL_CORK_LO],
		[0.362, 0.025, COL_CORK_HI],
		[0.388, 0.028, COL_CORK_HI],
		[0.396, 0.022, COL_CORK_HI.lightened(0.08)],
		[0.396, 0.000, COL_CORK_HI.lightened(0.08)],
	]
	_add_lathe_y(matte_st, cork_stations, 10, tilt)

	# 4. Crimson Wax Seal Cap crowning the cork + 3 molten drips over the neck lip.
	var wax_stations: Array[Array] = [
		[0.376, 0.028, COL_WAX_LO],
		[0.382, 0.036, COL_WAX_MID],
		[0.396, 0.037, COL_WAX_HI],
		[0.408, 0.031, COL_WAX_HI],
		[0.413, 0.018, COL_WAX_HI.lightened(0.08)],
		[0.413, 0.000, COL_WAX_HI.lightened(0.08)],
	]
	_add_lathe_y(matte_st, wax_stations, 10, tilt, 0.08, 5)
	for di in 3:
		var a := float(di) * (TAU / 3.0) + 0.45
		var drop_len := 0.028 + 0.012 * float(di % 2)
		var dp := tilt * Vector3(cos(a) * 0.035, 0.378 - drop_len * 0.5, sin(a) * 0.035)
		_add_faceted_stud(matte_st, dp, 0.011, drop_len * 0.55, 0.011, 6,
			COL_WAX_HI, COL_WAX_MID, COL_WAX_LO, tilt.basis)

	# 5. Embossed Gold Wax Compass Medallion atop the crimson wax cap.
	var seal_top := tilt * Vector3(0.0, 0.414, 0.0)
	_add_faceted_stud(gold_st, seal_top, 0.016, 0.006, 0.016, 6,
		COL_GOLD_HI, COL_GOLD_HI.darkened(0.14), COL_GOLD_LO, tilt.basis)

	matte_st.generate_normals()
	matte_st.commit(mesh)
	mesh.surface_set_material(0, _opaque_mat)

	gold_st.generate_normals()
	gold_st.commit(mesh)
	mesh.surface_set_material(1, _metal_mat)
	return mesh


static func _build_glass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Chunky stylized pirate sea-glass bottle (~0.37 m tall) with recessed punt,
	# broad faceted belly, sweeping shoulder, slender neck, and blown glass collar lip.
	var tilt := _bottle_tilt_transform()
	var glass_stations: Array[Array] = [
		[0.016, 0.000, COL_GLASS_THICK],
		[0.000, 0.068, COL_GLASS_THICK],
		[0.018, 0.078, COL_GLASS_THICK],
		[0.064, 0.082, COL_GLASS_BELLY],
		[0.132, 0.086, COL_GLASS_BELLY],
		[0.194, 0.088, COL_GLASS_SHOULDER],
		[0.228, 0.074, COL_GLASS_SHOULDER],
		[0.256, 0.046, COL_GLASS_SHOULDER],
		[0.278, 0.033, COL_GLASS_THICK],
		[0.336, 0.029, COL_GLASS_THICK],
		[0.346, 0.038, COL_GLASS_LIP],
		[0.362, 0.039, COL_GLASS_LIP],
		[0.369, 0.032, COL_GLASS_LIP],
		[0.364, 0.024, COL_GLASS_THICK],
		[0.340, 0.023, COL_GLASS_THICK],
	]
	_add_lathe_y(st, glass_stations, 14, tilt)
	st.generate_normals()
	return st.commit()


static func _build_glint_mesh() -> ArrayMesh:
	# Three orthogonal crossed feathered glint star planes (6 triangles, zero QuadMesh).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := 0.165
	var bases: Array[Basis] = [
		Basis.IDENTITY,
		Basis(Vector3.UP, PI / 3.0),
		Basis(Vector3.UP, 2.0 * PI / 3.0),
	]
	for b in bases:
		var bot_l := b * Vector3(-half, -half, 0.0)
		var bot_r := b * Vector3(half, -half, 0.0)
		var top_r := b * Vector3(half, half, 0.0)
		var top_l := b * Vector3(-half, half, 0.0)
		_emit_uv_tri(st, bot_l, Vector2(0.0, 1.0), bot_r, Vector2(1.0, 1.0), top_r, Vector2(1.0, 0.0))
		_emit_uv_tri(st, bot_l, Vector2(0.0, 1.0), top_r, Vector2(1.0, 0.0), top_l, Vector2(0.0, 0.0))
	st.generate_normals()
	return st.commit()


static func _build_glint_star_texture() -> ImageTexture:
	var sz := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var half := float(sz - 1) * 0.5
	for y in sz:
		var dy := (float(y) - half) / half
		for x in sz:
			var dx := (float(x) - half) / half
			var r := sqrt(dx * dx + dy * dy)
			var core := exp(-r * r * 14.0)
			# Crisp 4-point sunlit diamond star rays fading cleanly to zero at borders.
			var ray_h := exp(-absf(dy) * 14.0) * maxf(0.0, 1.0 - absf(dx))
			var ray_v := exp(-absf(dx) * 14.0) * maxf(0.0, 1.0 - absf(dy))
			var edge := clampf(1.0 - smoothstep(0.72, 1.0, r), 0.0, 1.0)
			var val := clampf((core + (ray_h + ray_v) * 0.65) * edge, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.97, 0.85, val))
	return ImageTexture.create_from_image(img)


# ==============================================================================
# Flat-Faceted `SurfaceTool` Helpers (`set_smooth_group(-1)`)
# ==============================================================================

static func _emit_flat_tri(st: SurfaceTool, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color) -> void:
	if (c - a).cross(b - a).length_squared() < 1e-12:
		return
	st.set_smooth_group(-1)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_smooth_group(-1)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_smooth_group(-1)
	st.set_color(cc)
	st.add_vertex(c)


static func _emit_outward_tri(st: SurfaceTool, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color, ref_center: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	var centroid := (a + b + c) / 3.0
	if n.dot(centroid - ref_center) < 0.0:
		_emit_flat_tri(st, a, ca, c, cc, b, cb)
	else:
		_emit_flat_tri(st, a, ca, b, cb, c, cc)


static func _emit_uv_tri(st: SurfaceTool, a: Vector3, uva: Vector2,
		b: Vector3, uvb: Vector2, c: Vector3, uvc: Vector2) -> void:
	st.set_smooth_group(-1)
	st.set_uv(uva)
	st.add_vertex(a)
	st.set_smooth_group(-1)
	st.set_uv(uvb)
	st.add_vertex(b)
	st.set_smooth_group(-1)
	st.set_uv(uvc)
	st.add_vertex(c)


static func _add_lathe_y(st: SurfaceTool, stations: Array[Array], segs: int,
		xform: Transform3D = Transform3D.IDENTITY, wobble_amp: float = 0.0,
		wobble_lobes: int = 0) -> void:
	for j in range(stations.size() - 1):
		var s0: Array = stations[j]
		var s1: Array = stations[j + 1]
		var y0: float = float(s0[0])
		var r0: float = float(s0[1])
		var c0: Color = s0[2] as Color
		var y1: float = float(s1[0])
		var r1: float = float(s1[1])
		var c1: Color = s1[2] as Color
		for k in segs:
			var a0 := float(k) / float(segs) * TAU
			var a1 := float(k + 1) / float(segs) * TAU
			var w0 := 1.0 + (wobble_amp * sin(float(wobble_lobes) * a0 + 0.6) if wobble_lobes > 0 else 0.0)
			var w1 := 1.0 + (wobble_amp * sin(float(wobble_lobes) * a1 + 0.6) if wobble_lobes > 0 else 0.0)
			var p00 := xform * Vector3(cos(a0) * r0 * w0, y0, sin(a0) * r0 * w0)
			var p01 := xform * Vector3(cos(a1) * r0 * w1, y0, sin(a1) * r0 * w1)
			var p10 := xform * Vector3(cos(a0) * r1 * w0, y1, sin(a0) * r1 * w0)
			var p11 := xform * Vector3(cos(a1) * r1 * w1, y1, sin(a1) * r1 * w1)
			if r0 > 1e-5 and r1 > 1e-5:
				_emit_flat_tri(st, p00, c0, p11, c1, p10, c1)
				_emit_flat_tri(st, p00, c0, p01, c0, p11, c1)
			elif r1 > 1e-5:
				_emit_flat_tri(st, p00, c0, p11, c1, p10, c1)
			elif r0 > 1e-5:
				_emit_flat_tri(st, p00, c0, p01, c0, p11, c1)


static func _add_faceted_stud(st: SurfaceTool, center: Vector3, rx: float, ry: float, rz: float,
		sides: int, col_top: Color, col_mid: Color, col_bot: Color,
		rot_basis: Basis = Basis.IDENTITY) -> void:
	var top_p := center + rot_basis * Vector3(0.0, ry, 0.0)
	var bot_p := center + rot_basis * Vector3(0.0, -ry * 0.75, 0.0)
	var ring: Array[Vector3] = []
	for k in sides:
		var a := float(k) / float(sides) * TAU
		ring.append(center + rot_basis * Vector3(cos(a) * rx, 0.0, sin(a) * rz))
	for k in sides:
		var nk := (k + 1) % sides
		_emit_outward_tri(st, top_p, col_top, ring[k], col_mid, ring[nk], col_mid, center)
		_emit_outward_tri(st, bot_p, col_bot, ring[nk], col_mid, ring[k], col_mid, center)
