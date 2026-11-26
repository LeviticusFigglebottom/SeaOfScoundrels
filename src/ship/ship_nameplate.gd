class_name ShipNameplate
extends Node3D
## Carved dark-mahogany and gilded-brass stern transom nameplate mounted flush
## against the outer aft frieze of Sloop and Brigantine hulls.
##
## Paints crisp 512x112 gold-leaf serif lettering onto a varnished mahogany
## ImageTexture ONLY on mount or `set_ship_name()` (0.00 ms per-frame cost,
## zero SubViewport overhead, zero raw PrimitiveMeshes, and leak-free cache teardown).

const TEX_W := 512
const TEX_H := 112

const SLOOP_POS := Vector3(0.0, 1.88, 6.72)
const SLOOP_RAKE_X := -0.20
const SLOOP_SIZE := Vector2(1.48, 0.30)

const BRIG_POS := Vector3(0.0, 2.08, 8.68)
const BRIG_RAKE_X := -0.22
const BRIG_SIZE := Vector2(1.86, 0.34)

# Sculpted frame palette (sRGB calibrated).
const COL_MAHOGANY_HI := Color(0.38, 0.18, 0.09)
const COL_MAHOGANY_MID := Color(0.25, 0.11, 0.055)
const COL_MAHOGANY_LO := Color(0.14, 0.06, 0.03)
const COL_BRASS_HI := Color(0.98, 0.80, 0.30)
const COL_BRASS_MID := Color(0.84, 0.62, 0.18)
const COL_BRASS_LO := Color(0.50, 0.34, 0.09)

# Crisp 5x7 uppercase nautical serif glyph bitmaps (each row is a 5-bit mask, bit 4 = left).
const GLYPHS := {
	"A": [0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x1B],
	"B": [0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E],
	"C": [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E],
	"D": [0x1E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E],
	"E": [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F],
	"F": [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x18],
	"G": [0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F],
	"H": [0x1B, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x1B],
	"I": [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E],
	"J": [0x07, 0x02, 0x02, 0x02, 0x12, 0x12, 0x0C],
	"K": [0x1B, 0x12, 0x14, 0x18, 0x14, 0x12, 0x1B],
	"L": [0x18, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F],
	"M": [0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x1B],
	"N": [0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11],
	"O": [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
	"P": [0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x18],
	"Q": [0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D],
	"R": [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x1B],
	"S": [0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E],
	"T": [0x1F, 0x15, 0x04, 0x04, 0x04, 0x04, 0x0E],
	"U": [0x1B, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
	"V": [0x1B, 0x11, 0x11, 0x11, 0x0A, 0x0A, 0x04],
	"W": [0x1B, 0x11, 0x11, 0x15, 0x15, 0x1B, 0x11],
	"X": [0x1B, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x1B],
	"Y": [0x1B, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x0E],
	"Z": [0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F],
	"0": [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E],
	"1": [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E],
	"2": [0x0E, 0x11, 0x01, 0x06, 0x08, 0x10, 0x1F],
	"3": [0x1E, 0x01, 0x01, 0x0E, 0x01, 0x01, 0x1E],
	"4": [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02],
	"5": [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E],
	"6": [0x0E, 0x10, 0x1E, 0x11, 0x11, 0x11, 0x0E],
	"7": [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],
	"8": [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E],
	"9": [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C],
	"'": [0x06, 0x04, 0x08, 0x00, 0x00, 0x00, 0x00],
	"-": [0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00],
	".": [0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C],
	"&": [0x0C, 0x12, 0x14, 0x08, 0x15, 0x12, 0x0D],
	"!": [0x04, 0x04, 0x04, 0x04, 0x04, 0x00, 0x04],
	"/": [0x01, 0x02, 0x02, 0x04, 0x08, 0x08, 0x10],
	":": [0x00, 0x0C, 0x0C, 0x00, 0x0C, 0x0C, 0x00],
	" ": [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
}

# Statically cached frame/quad ArrayMeshes & frame materials shared across all active nameplates.
static var _active_nameplates: int = 0
static var _frame_mesh_sloop: ArrayMesh = null
static var _frame_mesh_brig: ArrayMesh = null
static var _plaque_mesh_sloop: ArrayMesh = null
static var _plaque_mesh_brig: ArrayMesh = null
static var _wood_mat: StandardMaterial3D = null
static var _brass_mat: StandardMaterial3D = null

@export var ship_class: StringName = &"sloop"
var current_name: String = Profile.DEFAULT_SHIP_NAME

var _frame_mi: MeshInstance3D = null
var _plaque_mi: MeshInstance3D = null
var _plaque_mat: StandardMaterial3D = null
var _plaque_tex: ImageTexture = null


## Mount (or update) a carved stern transom ShipNameplate onto `ship`.
static func mount_to_ship(ship: Ship, initial_name: String = "The Gilded Scoundrel") -> ShipNameplate:
	if ship == null or not is_instance_valid(ship):
		return null
	var existing := ship.get_node_or_null(^"ShipNameplate") as ShipNameplate
	if existing != null:
		existing.set_ship_name(initial_name)
		return existing

	var plate := ShipNameplate.new()
	plate.name = "ShipNameplate"
	plate.ship_class = ship.ship_class
	plate.current_name = Profile.sanitize_ship_name(initial_name)
	if ship.ship_class == &"brigantine":
		plate.position = BRIG_POS * ship.hull_scale
		plate.rotation.x = BRIG_RAKE_X
	else:
		plate.position = SLOOP_POS * ship.hull_scale
		plate.rotation.x = SLOOP_RAKE_X
	plate.scale = Vector3.ONE * ship.hull_scale
	ship.add_child(plate)
	return plate


## Release all statically cached nameplate frame/quad meshes and materials cleanly.
static func clear_shared_cache() -> void:
	_frame_mesh_sloop = null
	_frame_mesh_brig = null
	_plaque_mesh_sloop = null
	_plaque_mesh_brig = null
	_wood_mat = null
	_brass_mat = null


func _enter_tree() -> void:
	_active_nameplates += 1


func _ready() -> void:
	_ensure_shared_assets()
	var is_brig := ship_class == &"brigantine"

	_frame_mi = MeshInstance3D.new()
	_frame_mi.name = "NameplateFrame"
	_frame_mi.mesh = _frame_mesh_brig if is_brig else _frame_mesh_sloop
	_frame_mi.set_surface_override_material(0, _wood_mat)
	if _frame_mi.mesh.get_surface_count() > 1:
		_frame_mi.set_surface_override_material(1, _brass_mat)
	add_child(_frame_mi)

	_plaque_mat = StandardMaterial3D.new()
	_plaque_mat.albedo_color = Color.WHITE
	_plaque_mat.roughness = 0.32
	_plaque_mat.metallic = 0.25
	_plaque_mat.emission_enabled = true
	_plaque_mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	_plaque_mat.emission = Color(1.0, 0.90, 0.65)
	_plaque_mat.emission_energy_multiplier = 0.16

	_plaque_mi = MeshInstance3D.new()
	_plaque_mi.name = "NameplateFace"
	_plaque_mi.mesh = _plaque_mesh_brig if is_brig else _plaque_mesh_sloop
	_plaque_mi.material_override = _plaque_mat
	add_child(_plaque_mi)

	set_ship_name(current_name)


func _exit_tree() -> void:
	if _plaque_mat != null:
		_plaque_mat.albedo_texture = null
		_plaque_mat.emission_texture = null
	_plaque_tex = null
	_plaque_mat = null
	for mi: MeshInstance3D in [_frame_mi, _plaque_mi]:
		if mi != null and is_instance_valid(mi):
			if mi.mesh != null:
				for si in mi.mesh.get_surface_count():
					mi.set_surface_override_material(si, null)
			mi.mesh = null
			mi.material_override = null
	_frame_mi = null
	_plaque_mi = null
	_active_nameplates = maxi(0, _active_nameplates - 1)
	if _active_nameplates == 0:
		clear_shared_cache()


## Update `current_name` and repaint the 512x112 mahogany-and-gold plaque texture once.
func set_ship_name(new_name: String) -> void:
	current_name = Profile.sanitize_ship_name(new_name)
	if _plaque_mat == null:
		return
	var next_tex := _paint_plaque_texture(current_name)
	_plaque_mat.albedo_texture = next_tex
	_plaque_mat.emission_texture = next_tex
	_plaque_tex = next_tex


## Return the currently active painted plaque ImageTexture (useful for verification/tests).
func get_plaque_texture() -> ImageTexture:
	return _plaque_tex


# ==============================================================================
# Procedural 512x112 Mahogany & Gold-Leaf Serif Texture Painter
# ==============================================================================

static func _paint_plaque_texture(ship_name: String) -> ImageTexture:
	var img := Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)
	var upper := Profile.sanitize_ship_name(ship_name).to_upper()

	# 1. Deep varnished mahogany woodgrain background with beveled border shading.
	for y in TEX_H:
		var vy := float(y) / float(TEX_H - 1)
		var bevel_y := 1.0 - 0.34 * pow(absf(vy * 2.0 - 1.0), 2.6)
		var sheen := 0.08 * exp(-pow((vy - 0.24) * 5.0, 2.0))
		for x in TEX_W:
			var vx := float(x) / float(TEX_W - 1)
			var bevel_x := 1.0 - 0.26 * pow(absf(vx * 2.0 - 1.0), 4.0)
			var grain := sin(float(y) * 0.48 + sin(float(x) * 0.032) * 2.2) * 0.5 + 0.5
			var fine := sin(float(y) * 1.45 + float(x) * 0.015) * 0.5 + 0.5
			var wood_k := (0.68 + 0.22 * grain + 0.10 * fine) * bevel_y * bevel_x
			var r := clampf(0.24 * wood_k + sheen, 0.0, 1.0)
			var g := clampf(0.105 * wood_k + sheen * 0.65, 0.0, 1.0)
			var b := clampf(0.052 * wood_k + sheen * 0.35, 0.0, 1.0)
			img.set_pixel(x, y, Color(r, g, b, 1.0))

	# 2. Gilded double-pinline border & 4 corner diamond rivets.
	var gold_outer := Color(0.90, 0.69, 0.22, 1.0)
	var gold_inner := Color(0.76, 0.56, 0.16, 1.0)
	var groove_dark := Color(0.08, 0.03, 0.015, 1.0)
	_draw_rect_outline(img, 6, 6, TEX_W - 7, TEX_H - 7, 2, gold_outer)
	_draw_rect_outline(img, 9, 9, TEX_W - 10, TEX_H - 10, 1, groove_dark)
	_draw_rect_outline(img, 12, 12, TEX_W - 13, TEX_H - 13, 1, gold_inner)
	for cx: int in [17, TEX_W - 18]:
		for cy: int in [17, TEX_H - 18]:
			_draw_diamond(img, cx, cy, 4, Color(0.98, 0.86, 0.42, 1.0))

	# 3. Flanking miniature 8-point antique-gold compass stars left & right of lettering.
	var mid_y := int(TEX_H * 0.5)
	_draw_compass_star(img, 34, mid_y, 12, Color(0.96, 0.80, 0.30, 1.0), Color(0.68, 0.46, 0.11, 1.0))
	_draw_compass_star(img, TEX_W - 35, mid_y, 12, Color(0.96, 0.80, 0.30, 1.0), Color(0.68, 0.46, 0.11, 1.0))

	# 4. Crisp hand-beveled gold-leaf serif lettering centered cleanly between stars!
	var n_chars := maxi(1, upper.length())
	var max_text_w := TEX_W - 118  # Generous margin inside left/right compass stars
	var scale_px := 6
	while scale_px > 2:
		var est_w := n_chars * (5 * scale_px) + (n_chars - 1) * (scale_px + 1)
		if est_w <= max_text_w:
			break
		scale_px -= 1
	var char_adv := 5 * scale_px + scale_px + 1
	var total_w := n_chars * (5 * scale_px) + (n_chars - 1) * (scale_px + 1)
	var start_x := int((TEX_W - total_w) * 0.5)
	var start_y := int((TEX_H - 7 * scale_px) * 0.5)

	var col_shadow := Color(0.06, 0.025, 0.01, 1.0)
	var col_gold_hi := Color(1.00, 0.94, 0.64, 1.0)
	var col_gold_mid := Color(0.94, 0.74, 0.22, 1.0)
	var col_gold_lo := Color(0.70, 0.46, 0.10, 1.0)

	# Pass 1: Umber carved drop shadow.
	for ci in upper.length():
		var ch := upper.substr(ci, 1)
		var rows: Array = GLYPHS.get(ch, GLYPHS[" "])
		_draw_glyph_block(img, rows, start_x + ci * char_adv + 2, start_y + 2, scale_px, col_shadow, col_shadow, col_shadow)
	# Pass 2: Beveled gold-leaf serif face (champagne top highlight, burnished gold body, amber base).
	for ci in upper.length():
		var ch := upper.substr(ci, 1)
		var rows: Array = GLYPHS.get(ch, GLYPHS[" "])
		_draw_glyph_block(img, rows, start_x + ci * char_adv, start_y, scale_px, col_gold_hi, col_gold_mid, col_gold_lo)

	return ImageTexture.create_from_image(img)


static func _draw_glyph_block(img: Image, rows: Array, ox: int, oy: int, s: int,
		col_hi: Color, col_mid: Color, col_lo: Color) -> void:
	for ry in rows.size():
		var mask := int(rows[ry])
		if mask == 0:
			continue
		for rx in 5:
			if (mask & (1 << (4 - rx))) == 0:
				continue
			var bx := ox + rx * s
			var by := oy + ry * s
			for dy in s:
				var py := by + dy
				if py < 0 or py >= TEX_H:
					continue
				var c := col_mid
				if dy == 0 and ry <= 2:
					c = col_hi
				elif dy == s - 1 and ry >= 4:
					c = col_lo
				for dx in s:
					var px := bx + dx
					if px >= 0 and px < TEX_W:
						img.set_pixel(px, py, c)


static func _draw_rect_outline(img: Image, x0: int, y0: int, x1: int, y1: int, thick: int, col: Color) -> void:
	for t in thick:
		for x in range(x0 + t, x1 - t + 1):
			if x >= 0 and x < TEX_W:
				if y0 + t >= 0 and y0 + t < TEX_H:
					img.set_pixel(x, y0 + t, col)
				if y1 - t >= 0 and y1 - t < TEX_H:
					img.set_pixel(x, y1 - t, col)
		for y in range(y0 + t, y1 - t + 1):
			if y >= 0 and y < TEX_H:
				if x0 + t >= 0 and x0 + t < TEX_W:
					img.set_pixel(x0 + t, y, col)
				if x1 - t >= 0 and x1 - t < TEX_W:
					img.set_pixel(x1 - t, y, col)


static func _draw_diamond(img: Image, cx: int, cy: int, r: int, col: Color) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if abs(dx) + abs(dy) <= r:
				var px := cx + dx
				var py := cy + dy
				if px >= 0 and px < TEX_W and py >= 0 and py < TEX_H:
					img.set_pixel(px, py, col)


static func _draw_compass_star(img: Image, cx: int, cy: int, rad: int, col_hi: Color, col_lo: Color) -> void:
	for dy in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			var px := cx + dx
			var py := cy + dy
			if px < 0 or px >= TEX_W or py < 0 or py >= TEX_H:
				continue
			var ax := float(abs(dx))
			var ay := float(abs(dy))
			var r := sqrt(ax * ax + ay * ay)
			var on_card := (ax <= 2.2 and ay <= float(rad)) or (ay <= 2.2 and ax <= float(rad))
			var on_diag := absf(ax - ay) <= 1.8 and r <= float(rad) * 0.68
			var on_hub := r <= 3.5
			if on_hub or on_card or on_diag:
				var is_lit := (dx + dy) <= 0
				img.set_pixel(px, py, col_hi if (on_hub or is_lit) else col_lo)


# ==============================================================================
# Shared Sculpted Frame & Plaque Quad ArrayMeshes (Zero Raw Primitives)
# ==============================================================================

static func _ensure_shared_assets() -> void:
	if _wood_mat == null:
		_wood_mat = StandardMaterial3D.new()
		_wood_mat.vertex_color_use_as_albedo = true
		_wood_mat.vertex_color_is_srgb = true
		_wood_mat.roughness = 0.58
		_wood_mat.metallic = 0.04
	if _brass_mat == null:
		_brass_mat = StandardMaterial3D.new()
		_brass_mat.vertex_color_use_as_albedo = true
		_brass_mat.vertex_color_is_srgb = true
		_brass_mat.roughness = 0.24
		_brass_mat.metallic = 0.80
	if _frame_mesh_sloop == null:
		_frame_mesh_sloop = _build_frame_mesh(SLOOP_SIZE.x, SLOOP_SIZE.y)
	if _frame_mesh_brig == null:
		_frame_mesh_brig = _build_frame_mesh(BRIG_SIZE.x, BRIG_SIZE.y)
	if _plaque_mesh_sloop == null:
		_plaque_mesh_sloop = _build_plaque_quad_mesh(SLOOP_SIZE.x, SLOOP_SIZE.y)
	if _plaque_mesh_brig == null:
		_plaque_mesh_brig = _build_plaque_quad_mesh(BRIG_SIZE.x, BRIG_SIZE.y)


static func _build_plaque_quad_mesh(width: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := width * 0.5
	var hh := height * 0.5
	var zf := 0.023
	# Facing +Z aft; viewer looking from +Z toward -Z sees -X on left (u=0) and +X on right (u=1).
	var top_l := Vector3(-hw, hh, zf)
	var top_r := Vector3(hw, hh, zf)
	var br := Vector3(hw, -hh, zf)
	var bl := Vector3(-hw, -hh, zf)

	st.set_smooth_group(-1)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(top_l)
	st.set_smooth_group(-1)
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(top_r)
	st.set_smooth_group(-1)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(br)

	st.set_smooth_group(-1)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(top_l)
	st.set_smooth_group(-1)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(br)
	st.set_smooth_group(-1)
	st.set_uv(Vector2(0.0, 1.0))
	st.add_vertex(bl)

	st.generate_normals()
	return st.commit()


static func _build_frame_mesh(width: float, height: float) -> ArrayMesh:
	var wood_st := SurfaceTool.new()
	wood_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var brass_st := SurfaceTool.new()
	brass_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var hw := width * 0.5
	var hh := height * 0.5

	# 1. Thick carved mahogany transom backing plaque board flush against stern frieze.
	_append_box(wood_st, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.0)),
		Vector3(width + 0.09, height + 0.08, 0.042), COL_MAHOGANY_HI, COL_MAHOGANY_MID, COL_MAHOGANY_LO)

	# 2. Raised beveled mahogany outer molding rails framing the recessed plaque face!
	var rail_t := 0.036
	var rail_d := 0.022
	_append_box(wood_st, Transform3D(Basis.IDENTITY, Vector3(0.0, hh + 0.020, 0.022)),
		Vector3(width + 0.10, rail_t, rail_d), COL_MAHOGANY_HI, COL_MAHOGANY_MID, COL_MAHOGANY_LO)
	_append_box(wood_st, Transform3D(Basis.IDENTITY, Vector3(0.0, -hh - 0.020, 0.022)),
		Vector3(width + 0.10, rail_t, rail_d), COL_MAHOGANY_HI, COL_MAHOGANY_MID, COL_MAHOGANY_LO)
	_append_box(wood_st, Transform3D(Basis.IDENTITY, Vector3(-hw - 0.026, 0.0, 0.022)),
		Vector3(0.044, height + 0.04, rail_d), COL_MAHOGANY_HI, COL_MAHOGANY_MID, COL_MAHOGANY_LO)
	_append_box(wood_st, Transform3D(Basis.IDENTITY, Vector3(hw + 0.026, 0.0, 0.022)),
		Vector3(0.044, height + 0.04, rail_d), COL_MAHOGANY_HI, COL_MAHOGANY_MID, COL_MAHOGANY_LO)

	# 3. Scrolled gilded brass corner brackets & raised stud bosses clasping all 4 corners!
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var cx := sx * (hw + 0.028)
			var cy := sy * (hh + 0.022)
			_append_box(brass_st, Transform3D(Basis.IDENTITY, Vector3(cx, cy, 0.026)),
				Vector3(0.068, 0.056, 0.024), COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)
			_append_box(brass_st, Transform3D(Basis.IDENTITY, Vector3(cx - sx * 0.072, cy, 0.026)),
				Vector3(0.088, 0.026, 0.020), COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)
			_append_box(brass_st, Transform3D(Basis.IDENTITY, Vector3(cx, cy - sy * 0.050, 0.026)),
				Vector3(0.028, 0.058, 0.020), COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)
			# Decorative corner brass scroll curl & rivet boss facing aft (+Z).
			_append_box(brass_st, Transform3D(Basis(Vector3.BACK, PI * 0.25), Vector3(cx, cy, 0.039)),
				Vector3(0.026, 0.026, 0.014), COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)

	# 4. Sculpted Top Gilded Brass Crown Flourish Crest & Lower Pendant Finial!
	_append_box(brass_st, Transform3D(Basis.IDENTITY, Vector3(0.0, hh + 0.052, 0.018)),
		Vector3(0.28, 0.042, 0.026), COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)
	for sx: float in [-1.0, 1.0]:
		_append_box(brass_st, Transform3D(Basis(Vector3.BACK, sx * -0.26), Vector3(sx * 0.175, hh + 0.040, 0.020)),
			Vector3(0.14, 0.026, 0.022), COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)
	# Central raised 4-point brass star diamond atop the crown crest.
	_append_box(brass_st, Transform3D(Basis(Vector3.BACK, PI * 0.25), Vector3(0.0, hh + 0.088, 0.022)),
		Vector3(0.068, 0.068, 0.024), COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)
	# Lower scrolled drop pendant balancing the stern transom crest.
	_append_box(brass_st, Transform3D(Basis(Vector3.BACK, PI * 0.25), Vector3(0.0, -hh - 0.046, 0.020)),
		Vector3(0.046, 0.046, 0.022), COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)

	wood_st.generate_normals()
	var mesh := wood_st.commit()
	brass_st.generate_normals()
	brass_st.commit(mesh)
	return mesh


static func _append_box(st: SurfaceTool, xf: Transform3D, size: Vector3,
		col_top: Color, col_mid: Color, col_bot: Color) -> void:
	var h := size * 0.5
	var c: Array[Vector3] = [
		xf * Vector3(-h.x, -h.y, -h.z),
		xf * Vector3(h.x, -h.y, -h.z),
		xf * Vector3(h.x, h.y, -h.z),
		xf * Vector3(-h.x, h.y, -h.z),
		xf * Vector3(-h.x, -h.y, h.z),
		xf * Vector3(h.x, -h.y, h.z),
		xf * Vector3(h.x, h.y, h.z),
		xf * Vector3(-h.x, h.y, h.z),
	]
	var ctr := xf.origin
	_emit_outward_quad(st, c[3], c[2], c[6], c[7], ctr, col_top, col_top, col_top, col_top)
	_emit_outward_quad(st, c[4], c[5], c[1], c[0], ctr, col_bot, col_bot, col_bot, col_bot)
	_emit_outward_quad(st, c[0], c[1], c[2], c[3], ctr, col_bot, col_bot, col_mid, col_mid)
	_emit_outward_quad(st, c[5], c[4], c[7], c[6], ctr, col_bot, col_bot, col_mid, col_mid)
	_emit_outward_quad(st, c[4], c[0], c[3], c[7], ctr, col_bot, col_bot, col_mid, col_mid)
	_emit_outward_quad(st, c[1], c[5], c[6], c[2], ctr, col_bot, col_bot, col_mid, col_mid)


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
