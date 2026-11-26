class_name HullCrest
extends Node3D
## Sculpted flat-faceted Port & Starboard bow-cheek heraldic hull crest medallions.
##
## Conforms directly onto the exact analytical curved outer hull planking of both
## Sloop (`gen_sloop.py`) and Brigantine (`gen_brigantine.py`) with 1 MeshInstance3D
## draw-call node (2 surfaces: carved antique-bronze/obsidian frame + luminous inlaid
## runic core sigil), zero raw PrimitiveMeshes, dynamic livery emblem response across
## modes 0..7, Ghost Ship spectral phase fading, and ref-counted leak-free cache cleanup.

const SLOOP_CENTER_Z := -4.25
const SLOOP_CENTER_Y := 1.62
const SLOOP_SURFACE_OFFSET := 0.035
const SLOOP_SCALE := 1.0
const SLOOP_SHEER_SLOPE := -0.058

const BRIG_CENTER_Z := -6.30
const BRIG_CENTER_Y := 1.92
const BRIG_SURFACE_OFFSET := 0.040
const BRIG_SCALE := 1.20
const BRIG_SHEER_SLOPE := -0.052

# sRGB-calibrated carved obsidian-iron, antique bronze & burnished gold vertex palette.
const COL_IRON_HI := Color(0.21, 0.24, 0.29)
const COL_IRON_MID := Color(0.13, 0.15, 0.19)
const COL_IRON_LO := Color(0.08, 0.09, 0.12)

const COL_GOLD_HI := Color(0.96, 0.78, 0.30)
const COL_BRONZE_MID := Color(0.68, 0.48, 0.18)
const COL_BRONZE_LO := Color(0.34, 0.22, 0.08)

const COL_RUNE_APEX := Color(1.00, 1.00, 1.00)
const COL_RUNE_MID := Color(0.86, 0.90, 0.94)
const COL_RUNE_LO := Color(0.64, 0.70, 0.76)

# Ref-counted static mesh & shared frame material caches (zero ObjectDB leaks on teardown).
static var _active_crests: int = 0
static var _sloop_mesh: ArrayMesh = null
static var _brig_mesh: ArrayMesh = null
static var _frame_mat: StandardMaterial3D = null

@export var ship_class: StringName = &"sloop"

var _mesh_mi: MeshInstance3D = null
var _core_mat: StandardMaterial3D = null
var _emblem_mode: int = 0
var _glow_accent: Color = Color.BLACK
var _base_emission_energy: float = 0.15
var _spectral_alpha: float = 1.0


## Mount (or reuse) a sculpted Port & Starboard bow-cheek HullCrest on `ship`.
static func mount_to_ship(ship: Node3D) -> HullCrest:
	if ship == null or not is_instance_valid(ship):
		return null
	var existing := ship.get_node_or_null(^"HullCrest") as HullCrest
	if existing != null:
		return existing

	var crest := HullCrest.new()
	crest.name = "HullCrest"
	var cls_v: Variant = ship.get(&"ship_class")
	crest.ship_class = cls_v as StringName if cls_v is StringName else &"sloop"
	var hs_v: Variant = ship.get(&"hull_scale")
	var hs := float(hs_v) if hs_v != null else 1.0
	crest.scale = Vector3.ONE * hs
	ship.add_child(crest)
	return crest


## Release all statically cached crest ArrayMeshes and shared frame material cleanly.
static func clear_shared_cache() -> void:
	_sloop_mesh = null
	_brig_mesh = null
	_frame_mat = null


func _enter_tree() -> void:
	_active_crests += 1


func _ready() -> void:
	_ensure_shared_assets()
	var is_brig := ship_class == &"brigantine"

	_core_mat = StandardMaterial3D.new()
	_core_mat.vertex_color_use_as_albedo = true
	_core_mat.vertex_color_is_srgb = true
	_core_mat.metallic = 0.25
	_core_mat.roughness = 0.22
	_core_mat.emission_enabled = true

	_mesh_mi = MeshInstance3D.new()
	_mesh_mi.name = "HullCrestMesh"
	_mesh_mi.mesh = _brig_mesh if is_brig else _sloop_mesh
	_mesh_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_mi.set_surface_override_material(0, _frame_mat)
	if _mesh_mi.mesh != null and _mesh_mi.mesh.get_surface_count() > 1:
		_mesh_mi.set_surface_override_material(1, _core_mat)
	add_child(_mesh_mi)

	apply_emblem(_emblem_mode, _glow_accent)


func _exit_tree() -> void:
	if _mesh_mi != null and is_instance_valid(_mesh_mi):
		if _mesh_mi.mesh != null:
			for si in _mesh_mi.mesh.get_surface_count():
				_mesh_mi.set_surface_override_material(si, null)
		_mesh_mi.material_override = null
		_mesh_mi.mesh = null
	_mesh_mi = null
	_core_mat = null
	_active_crests = maxi(0, _active_crests - 1)
	if _active_crests == 0:
		clear_shared_cache()


## Apply faction / Trading Company styling (emblem_mode 0..7) to the inlaid runic core sigil.
func apply_emblem(emblem_mode: int, glow_accent: Color = Color.BLACK) -> void:
	_emblem_mode = emblem_mode
	_glow_accent = glow_accent

	var core_col := Color(0.92, 0.74, 0.24)
	var emit_col := Color(0.92, 0.74, 0.24)
	var energy := 0.15

	match emblem_mode:
		1:
			# Corsair: crimson-obsidian emblem with smoldering ember core.
			core_col = Color(0.95, 0.24, 0.14)
			emit_col = Color(0.95, 0.24, 0.14)
			energy = 0.85
		2:
			# Drowned: Concept Art 2 eerie emerald-turquoise runic glow.
			core_col = Color(0.16, 0.96, 0.58)
			emit_col = Color(0.16, 0.96, 0.58)
			energy = 1.45
		3:
			# Ghost: ethereal spectral cyan-jade core.
			core_col = Color(0.28, 1.0, 0.90)
			emit_col = Color(0.28, 1.0, 0.90)
			energy = 1.65
		4:
			# Gilded Compass: royal azure-and-gold compass-star boss.
			core_col = Color(0.98, 0.82, 0.26)
			emit_col = Color(0.98, 0.82, 0.26)
			energy = 0.45
		5:
			# Sunken Archive: Concept Art 2 glowing turquoise-emerald arcane seal.
			core_col = Color(0.18, 0.95, 0.78)
			emit_col = Color(0.18, 0.95, 0.78)
			energy = 1.50
		6:
			# Iron Tide: blazing war-crimson crest core.
			core_col = Color(0.94, 0.28, 0.18)
			emit_col = Color(0.94, 0.28, 0.18)
			energy = 0.70
		7:
			# Sovereign Sunburst: radiant golden sunburst jewel.
			core_col = Color(1.0, 0.84, 0.28)
			emit_col = Color(1.0, 0.84, 0.28)
			energy = 0.75
		_:
			# Default/Standard: burnished gold compass boss with subtle warm gleam.
			if glow_accent.get_luminance() > 0.02:
				core_col = core_col.lerp(glow_accent, 0.55)
				emit_col = glow_accent
				energy = 0.55

	_base_emission_energy = energy
	if _core_mat != null:
		_core_mat.albedo_color = core_col
		_core_mat.emission = emit_col
		_core_mat.emission_energy_multiplier = _base_emission_energy * _spectral_alpha


## Smoothly hide/fade the crest during Ghost Ship spectral phase shifts.
func set_spectral_alpha(alpha: float) -> void:
	_spectral_alpha = clampf(alpha, 0.0, 1.0)
	visible = _spectral_alpha > 0.05
	if _core_mat != null:
		_core_mat.emission_energy_multiplier = _base_emission_energy * _spectral_alpha


## Return the per-ship luminous runic core material (Surface 1).
func get_core_material() -> StandardMaterial3D:
	return _core_mat


## Return total sculpted triangle count across both surfaces of the active crest mesh.
func get_triangle_count() -> int:
	if _mesh_mi == null or _mesh_mi.mesh == null:
		return 0
	var am := _mesh_mi.mesh as ArrayMesh
	if am == null:
		return 0
	var tris := 0
	for si in am.get_surface_count():
		var idx_len := am.surface_get_array_index_len(si)
		if idx_len > 0:
			tris += floori(float(idx_len) / 3.0)
		else:
			tris += floori(float(am.surface_get_array_len(si)) / 3.0)
	return tris


# ==============================================================================
# Analytical Hull Surface Equations (exact match to gen_sloop.py & gen_brigantine.py)
# ==============================================================================

static func _sloop_zstem(y: float) -> float:
	if y >= 1.1:
		var d := y - 1.1
		return -6.5 - 0.09 * d - 0.12 * d * d
	var t := clampf((y + 1.0) / 2.1, 0.0, 1.0)
	return lerpf(-3.4, -6.5, t)


static func _sloop_tumble(y: float) -> float:
	if y <= 0.9:
		return 1.0
	return 1.0 - 0.05 * pow((y - 0.9) / 1.1, 1.3)


static func _sloop_bmid(y: float) -> float:
	var h := clampf((y + 1.0) / 1.9, 0.0, 1.0)
	return 2.2 * pow(1.0 - pow(1.0 - h, 3.0), 1.0 / 3.6) * _sloop_tumble(y)


static func _sloop_hull_b(z: float, y: float) -> float:
	var bm := _sloop_bmid(y)
	var t := clampf(z / _sloop_zstem(y), 0.0, 1.0)
	return bm * pow(maxf(0.0, 1.0 - pow(t, 2.4)), 0.7)


static func _brig_zstem(y: float) -> float:
	if y >= 1.25:
		var d := y - 1.25
		return -9.2 - 0.14 * d - 0.14 * d * d
	var t := clampf((y + 1.10) / 2.35, 0.0, 1.0)
	return lerpf(-5.40, -9.20, t)


static func _brig_tumble(y: float) -> float:
	if y <= 1.05:
		return 1.0
	return 1.0 - 0.055 * pow((y - 1.05) / 1.25, 1.3)


static func _brig_bmid(y: float) -> float:
	var h := clampf((y + 1.10) / 2.15, 0.0, 1.0)
	return 2.70 * pow(1.0 - pow(1.0 - h, 3.0), 1.0 / 3.6) * _brig_tumble(y)


static func _brig_hull_b(z: float, y: float) -> float:
	var bm := _brig_bmid(y)
	var t := clampf(z / _brig_zstem(y), 0.0, 1.0)
	return bm * pow(maxf(0.0, 1.0 - pow(t, 2.5)), 0.72)


static func _hull_b(is_brig: bool, z: float, y: float) -> float:
	return _brig_hull_b(z, y) if is_brig else _sloop_hull_b(z, y)


static func _hull_normal(is_brig: bool, side: float, z: float, y: float) -> Vector3:
	const EPS := 0.01
	var dxdz := (_hull_b(is_brig, z + EPS, y) - _hull_b(is_brig, z - EPS, y)) / (2.0 * EPS)
	var dxdy := (_hull_b(is_brig, z, y + EPS) - _hull_b(is_brig, z, y - EPS)) / (2.0 * EPS)
	return Vector3(side, -dxdy, -dxdz).normalized()


## Map medallion-local `(u, v, d)` onto the curved outer hull surface of Port (`side=-1`)
## or Starboard (`side=+1`), where `+u` runs aft along the bow sheer, `+v` runs up, and
## `d` is relief depth outward from the analytical surface offset (`+0.035 m` / `+0.040 m`).
static func _hull_map(is_brig: bool, side: float, u: float, v: float, d: float) -> Vector3:
	var sc := BRIG_SCALE if is_brig else SLOOP_SCALE
	var z0 := BRIG_CENTER_Z if is_brig else SLOOP_CENTER_Z
	var y0 := BRIG_CENTER_Y if is_brig else SLOOP_CENTER_Y
	var off := BRIG_SURFACE_OFFSET if is_brig else SLOOP_SURFACE_OFFSET
	var sheer := BRIG_SHEER_SLOPE if is_brig else SLOOP_SHEER_SLOPE

	var us := u * sc
	var vs := v * sc
	# Compensate longitudinal spacing for the bow cheek's ~19 deg horizontal angle so proportions stay true.
	var z := z0 + us * 0.946
	var y := y0 + vs + sheer * us
	var xb := _hull_b(is_brig, z, y)
	var n := _hull_normal(is_brig, side, z, y)
	return Vector3(side * xb, y, z) + n * (off + d * sc)


static func _hull_normal_uv(is_brig: bool, side: float, u: float, v: float) -> Vector3:
	var sc := BRIG_SCALE if is_brig else SLOOP_SCALE
	var z0 := BRIG_CENTER_Z if is_brig else SLOOP_CENTER_Z
	var y0 := BRIG_CENTER_Y if is_brig else SLOOP_CENTER_Y
	var sheer := BRIG_SHEER_SLOPE if is_brig else SLOOP_SHEER_SLOPE
	var us := u * sc
	var z := z0 + us * 0.946
	var y := y0 + v * sc + sheer * us
	return _hull_normal(is_brig, side, z, y)


# ==============================================================================
# Shared Sculpted ArrayMesh Construction (1 MeshInstance3D, 2 Surfaces, 0 Primitives)
# ==============================================================================

static func _ensure_shared_assets() -> void:
	if _frame_mat == null:
		_frame_mat = StandardMaterial3D.new()
		_frame_mat.vertex_color_use_as_albedo = true
		_frame_mat.vertex_color_is_srgb = true
		_frame_mat.metallic = 0.72
		_frame_mat.roughness = 0.34
	if _sloop_mesh == null:
		_sloop_mesh = _build_crest_pair_mesh(false)
	if _brig_mesh == null:
		_brig_mesh = _build_crest_pair_mesh(true)


static func _build_crest_pair_mesh(is_brig: bool) -> ArrayMesh:
	var frame_st := SurfaceTool.new()
	frame_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var core_st := SurfaceTool.new()
	core_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for side: float in [-1.0, 1.0]:
		_sculpt_single_medallion(frame_st, core_st, is_brig, side)

	frame_st.generate_normals()
	var mesh := frame_st.commit()
	core_st.generate_normals()
	core_st.commit(mesh)
	return mesh


static func _sculpt_single_medallion(frame_st: SurfaceTool, core_st: SurfaceTool,
		is_brig: bool, side: float) -> void:
	# Back skirt tucks ~12 mm inside the 160 mm outer plank so zero floating seam is ever visible.
	var sc := BRIG_SCALE if is_brig else SLOOP_SCALE
	var off := BRIG_SURFACE_OFFSET if is_brig else SLOOP_SURFACE_OFFSET
	var d_back := -(off + 0.012) / sc

	# 8-sided maritime heraldic kite/heater shield contour (CCW in (u, v) plane).
	var shield_outer: Array[Vector2] = [
		Vector2(0.00, 0.255),
		Vector2(-0.185, 0.220),
		Vector2(-0.240, 0.075),
		Vector2(-0.205, -0.095),
		Vector2(-0.115, -0.225),
		Vector2(0.00, -0.305),
		Vector2(0.115, -0.225),
		Vector2(0.205, -0.095),
		Vector2(0.240, 0.075),
		Vector2(0.185, 0.220),
	]
	var shield_inner: Array[Vector2] = []
	for pt in shield_outer:
		shield_inner.append(pt * 0.76)

	# 1. Recessed beveled dark obsidian-iron heraldic shield backing plate.
	_add_conformed_shield_plate(
		frame_st, is_brig, side, shield_outer, d_back, 0.000, 0.005,
		COL_IRON_HI, COL_IRON_MID, COL_IRON_LO
	)

	# 2. Raised beveled antique-bronze & burnished-gold outer heraldic shield rim.
	_add_conformed_frame_ring(
		frame_st, is_brig, side, shield_outer, shield_inner,
		d_back, 0.014, 0.032, 0.004,
		COL_GOLD_HI, COL_BRONZE_MID, COL_BRONZE_LO
	)

	# 3. 10 raised faceted bronze-gold corner rivets studded along the shield rim.
	for i in shield_outer.size():
		var rv_uv := shield_outer[i].lerp(shield_inner[i], 0.48)
		_add_conformed_gem_boss(
			frame_st, is_brig, side, rv_uv, 0.017, 0.017, 4,
			0.026, 0.034, 0.044,
			COL_GOLD_HI, COL_BRONZE_MID, COL_BRONZE_LO
		)

	# 4. Swept baroque aft scroll-wings flaring aft (+u) along the bow sheer (3 tiered plumes).
	var aft_upper: Array[Vector2] = [
		Vector2(0.175, 0.140),
		Vector2(0.320, 0.165),
		Vector2(0.495, 0.150),
		Vector2(0.645, 0.105),
	]
	var aft_upper_w: Array[float] = [0.060, 0.056, 0.038, 0.008]
	_add_conformed_wing_blade(
		frame_st, is_brig, side, aft_upper, aft_upper_w,
		d_back, 0.006, 0.026, COL_GOLD_HI, COL_BRONZE_MID, COL_BRONZE_LO
	)

	var aft_mid: Array[Vector2] = [
		Vector2(0.195, 0.020),
		Vector2(0.330, 0.030),
		Vector2(0.455, 0.012),
		Vector2(0.545, -0.028),
	]
	var aft_mid_w: Array[float] = [0.052, 0.046, 0.030, 0.007]
	_add_conformed_wing_blade(
		frame_st, is_brig, side, aft_mid, aft_mid_w,
		d_back, 0.004, 0.021, COL_GOLD_HI, COL_BRONZE_MID, COL_BRONZE_LO
	)

	var aft_low: Array[Vector2] = [
		Vector2(0.160, -0.095),
		Vector2(0.275, -0.115),
		Vector2(0.395, -0.150),
	]
	var aft_low_w: Array[float] = [0.040, 0.032, 0.007]
	_add_conformed_wing_blade(
		frame_st, is_brig, side, aft_low, aft_low_w,
		d_back, 0.002, 0.017, COL_BRONZE_MID, COL_BRONZE_MID, COL_BRONZE_LO
	)

	# 5. Forward prow counter-scroll wings reaching toward the stem (-u, strictly clear of anchor).
	var fore_upper: Array[Vector2] = [
		Vector2(-0.175, 0.130),
		Vector2(-0.305, 0.135),
		Vector2(-0.420, 0.095),
	]
	var fore_upper_w: Array[float] = [0.054, 0.042, 0.008]
	_add_conformed_wing_blade(
		frame_st, is_brig, side, fore_upper, fore_upper_w,
		d_back, 0.005, 0.024, COL_GOLD_HI, COL_BRONZE_MID, COL_BRONZE_LO
	)

	var fore_low: Array[Vector2] = [
		Vector2(-0.185, -0.025),
		Vector2(-0.295, -0.055),
		Vector2(-0.375, -0.098),
	]
	var fore_low_w: Array[float] = [0.044, 0.032, 0.007]
	_add_conformed_wing_blade(
		frame_st, is_brig, side, fore_low, fore_low_w,
		d_back, 0.003, 0.019, COL_BRONZE_MID, COL_BRONZE_MID, COL_BRONZE_LO
	)

	# 6. Sculpted upper 3-tine maritime crown finial atop the shield brow (+v).
	var crown_center: Array[Vector2] = [
		Vector2(0.00, 0.225),
		Vector2(0.00, 0.315),
		Vector2(0.00, 0.398),
	]
	_add_conformed_wing_blade(
		frame_st, is_brig, side, crown_center, [0.052, 0.036, 0.006],
		d_back, 0.006, 0.030, COL_GOLD_HI, COL_BRONZE_MID, COL_BRONZE_LO
	)
	for su: float in [-1.0, 1.0]:
		var tine: Array[Vector2] = [
			Vector2(su * 0.068, 0.220),
			Vector2(su * 0.118, 0.285),
			Vector2(su * 0.155, 0.342),
		]
		_add_conformed_wing_blade(
			frame_st, is_brig, side, tine, [0.036, 0.025, 0.005],
			d_back, 0.005, 0.025, COL_GOLD_HI, COL_BRONZE_MID, COL_BRONZE_LO
		)

	# 7. Lower keel spear-point finial & flanking brackets anchoring the bottom crest tip (-v).
	var keel_tip: Array[Vector2] = [
		Vector2(0.00, -0.270),
		Vector2(0.00, -0.345),
		Vector2(0.00, -0.415),
	]
	_add_conformed_wing_blade(
		frame_st, is_brig, side, keel_tip, [0.046, 0.028, 0.005],
		d_back, 0.005, 0.026, COL_GOLD_HI, COL_BRONZE_MID, COL_BRONZE_LO
	)
	for su: float in [-1.0, 1.0]:
		var spur: Array[Vector2] = [
			Vector2(su * 0.072, -0.225),
			Vector2(su * 0.115, -0.285),
		]
		_add_conformed_wing_blade(
			frame_st, is_brig, side, spur, [0.024, 0.006],
			d_back, 0.003, 0.018, COL_BRONZE_MID, COL_BRONZE_MID, COL_BRONZE_LO
		)

	# 8. Raised octagonal bronze bezel socket & 4 gripping prongs framing the runic core boss.
	var bezel_outer: Array[Vector2] = []
	var bezel_inner: Array[Vector2] = []
	for k in 8:
		var ang := float(k) * TAU / 8.0 + PI / 8.0
		var dir2 := Vector2(cos(ang), sin(ang))
		bezel_outer.append(Vector2(dir2.x * 0.105, dir2.y * 0.125 - 0.010))
		bezel_inner.append(Vector2(dir2.x * 0.074, dir2.y * 0.090 - 0.010))
	_add_conformed_frame_ring(
		frame_st, is_brig, side, bezel_outer, bezel_inner,
		0.000, 0.014, 0.026, 0.004,
		COL_GOLD_HI, COL_BRONZE_MID, COL_BRONZE_LO
	)
	for claw_uv: Vector2 in [
		Vector2(0.0, 0.088), Vector2(0.0, -0.108),
		Vector2(-0.078, -0.010), Vector2(0.078, -0.010),
	]:
		_add_conformed_gem_boss(
			frame_st, is_brig, side, claw_uv, 0.018, 0.018, 4,
			0.016, 0.026, 0.036,
			COL_GOLD_HI, COL_BRONZE_MID, COL_BRONZE_LO
		)

	# ==========================================================================
	# SURFACE 1: Luminous Inlaid Runic Core Sigil (Dynamic Livery & Arcane Glow!)
	# ==========================================================================

	# 9. Central tall 8-faceted crystal-rune compass boss nestled inside the bezel.
	_add_conformed_gem_boss(
		core_st, is_brig, side, Vector2(0.0, -0.010), 0.078, 0.098, 8,
		0.004, 0.022, 0.056,
		COL_RUNE_APEX, COL_RUNE_MID, COL_RUNE_LO
	)

	# 10. 4 cardinal starburst rune needles radiating into the dark obsidian shield field.
	var ray_specs: Array[Array] = [
		[Vector2(0.0, 0.075), Vector2(0.0, 0.175), 0.022],
		[Vector2(0.0, -0.095), Vector2(0.0, -0.215), 0.022],
		[Vector2(0.068, -0.010), Vector2(0.158, -0.010), 0.020],
		[Vector2(-0.068, -0.010), Vector2(-0.158, -0.010), 0.020],
	]
	for rspec in ray_specs:
		var p0: Vector2 = rspec[0] as Vector2
		var p1: Vector2 = rspec[1] as Vector2
		var rw: float = float(rspec[2])
		_add_conformed_wing_blade(
			core_st, is_brig, side, [p0, p0.lerp(p1, 0.55), p1], [rw, rw * 0.65, 0.004],
			0.002, 0.008, 0.028, COL_RUNE_APEX, COL_RUNE_MID, COL_RUNE_LO
		)

	# 11. 4 intercardinal faceted arcane rune shards framing the bezel corners.
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var base_uv := Vector2(sx * 0.066, -0.010 + sy * 0.078)
			var tip_uv := Vector2(sx * 0.128, -0.010 + sy * 0.142)
			_add_conformed_wing_blade(
				core_st, is_brig, side, [base_uv, tip_uv], [0.014, 0.003],
				0.002, 0.007, 0.021, COL_RUNE_APEX, COL_RUNE_MID, COL_RUNE_LO
			)

	# 12. Slender glowing arcane inlay rune streaks along the primary aft & fore baroque wings!
	_add_conformed_wing_blade(
		core_st, is_brig, side,
		[Vector2(0.245, 0.150), Vector2(0.395, 0.158), Vector2(0.555, 0.130)],
		[0.013, 0.011, 0.003],
		0.016, 0.021, 0.032, COL_RUNE_APEX, COL_RUNE_MID, COL_RUNE_LO
	)
	_add_conformed_wing_blade(
		core_st, is_brig, side,
		[Vector2(-0.225, 0.132), Vector2(-0.345, 0.120)],
		[0.012, 0.003],
		0.014, 0.019, 0.029, COL_RUNE_APEX, COL_RUNE_MID, COL_RUNE_LO
	)


# ==============================================================================
# Hull-Conformed Flat-Faceted SurfaceTool Primitives
# ==============================================================================

static func _add_conformed_shield_plate(st: SurfaceTool, is_brig: bool, side: float,
		poly: Array[Vector2], d_back: float, d_front: float, d_center: float,
		col_hi: Color, col_mid: Color, col_lo: Color) -> void:
	var n_pts := poly.size()
	var ctr_uv := Vector2.ZERO
	for p in poly:
		ctr_uv += p
	ctr_uv /= float(n_pts)

	var p_ctr := _hull_map(is_brig, side, ctr_uv.x, ctr_uv.y, d_center)
	var n_ctr := _hull_normal_uv(is_brig, side, ctr_uv.x, ctr_uv.y)

	for i in n_pts:
		var j := (i + 1) % n_pts
		var a_uv := poly[i]
		var b_uv := poly[j]
		var a_f := _hull_map(is_brig, side, a_uv.x, a_uv.y, d_front)
		var b_f := _hull_map(is_brig, side, b_uv.x, b_uv.y, d_front)
		var a_b := _hull_map(is_brig, side, a_uv.x, a_uv.y, d_back)
		var b_b := _hull_map(is_brig, side, b_uv.x, b_uv.y, d_back)

		# Subtle dish shading across the dark obsidian shield field.
		var fc := col_hi if (a_uv.y + b_uv.y) > 0.05 else col_mid
		_emit_tri_dir(st, p_ctr, a_f, b_f, n_ctr, col_mid, fc, fc)

		# Solid outer skirt tucking cleanly into the curved hull planking.
		var mid_uv := (a_uv + b_uv) * 0.5
		var rad_out := (_hull_map(is_brig, side, mid_uv.x * 1.1, mid_uv.y * 1.1, d_front) - p_ctr).normalized()
		_emit_quad_dir(st, a_b, b_b, b_f, a_f, rad_out, col_lo, col_lo, col_mid, col_mid)


static func _add_conformed_frame_ring(st: SurfaceTool, is_brig: bool, side: float,
		outer_poly: Array[Vector2], inner_poly: Array[Vector2],
		d_back: float, d_shoulder: float, d_crest: float, d_inner_base: float,
		col_hi: Color, col_mid: Color, col_lo: Color) -> void:
	var n_pts := outer_poly.size()
	var ctr_uv := Vector2.ZERO
	for p in outer_poly:
		ctr_uv += p
	ctr_uv /= float(n_pts)
	var p_ctr := _hull_map(is_brig, side, ctr_uv.x, ctr_uv.y, d_inner_base)

	for i in n_pts:
		var j := (i + 1) % n_pts
		var o0 := outer_poly[i]
		var o1 := outer_poly[j]
		var i0 := inner_poly[i]
		var i1 := inner_poly[j]
		# Crown ridge runs halfway between outer & inner rim edges for crisp specular bevels.
		var m0_out := o0.lerp(i0, 0.28)
		var m1_out := o1.lerp(i1, 0.28)
		var m0_in := o0.lerp(i0, 0.72)
		var m1_in := o1.lerp(i1, 0.72)

		var po0_b := _hull_map(is_brig, side, o0.x, o0.y, d_back)
		var po1_b := _hull_map(is_brig, side, o1.x, o1.y, d_back)
		var po0_s := _hull_map(is_brig, side, o0.x, o0.y, d_shoulder)
		var po1_s := _hull_map(is_brig, side, o1.x, o1.y, d_shoulder)
		var pm0_o := _hull_map(is_brig, side, m0_out.x, m0_out.y, d_crest)
		var pm1_o := _hull_map(is_brig, side, m1_out.x, m1_out.y, d_crest)
		var pm0_i := _hull_map(is_brig, side, m0_in.x, m0_in.y, d_crest)
		var pm1_i := _hull_map(is_brig, side, m1_in.x, m1_in.y, d_crest)
		var pi0_b := _hull_map(is_brig, side, i0.x, i0.y, d_inner_base)
		var pi1_b := _hull_map(is_brig, side, i1.x, i1.y, d_inner_base)

		var mid_uv := (o0 + o1) * 0.5
		var n_out := _hull_normal_uv(is_brig, side, mid_uv.x, mid_uv.y)
		var rad_out := (_hull_map(is_brig, side, mid_uv.x, mid_uv.y, d_shoulder) - p_ctr).normalized()
		var rad_in := -rad_out
		var top_shade := col_hi if mid_uv.y >= -0.05 else col_mid

		# Outer vertical skirt -> outer chamfer -> flat top ridge -> inner chamfer into shield dish.
		_emit_quad_dir(st, po0_b, po1_b, po1_s, po0_s, rad_out, col_lo, col_lo, col_mid, col_mid)
		_emit_quad_dir(st, po0_s, po1_s, pm1_o, pm0_o, (n_out + rad_out * 0.55).normalized(),
			col_mid, col_mid, top_shade, top_shade)
		_emit_quad_dir(st, pm0_o, pm1_o, pm1_i, pm0_i, n_out, top_shade, top_shade, col_hi, col_hi)
		_emit_quad_dir(st, pm0_i, pm1_i, pi1_b, pi0_b, (n_out + rad_in * 0.55).normalized(),
			col_mid, col_mid, col_lo, col_lo)


static func _add_conformed_wing_blade(st: SurfaceTool, is_brig: bool, side: float,
		spine: Array[Vector2], widths: Array[float],
		d_back: float, d_edge: float, d_ridge: float,
		col_hi: Color, col_mid: Color, col_lo: Color) -> void:
	var n_st := spine.size()
	if n_st < 2:
		return

	# Build per-station 5-point ridged cross sections conformed to the hull surface:
	# [0] top_back, [1] top_edge, [2] center_ridge, [3] bot_edge, [4] bot_back.
	var rings: Array[Array] = []
	var normals: Array[Vector3] = []

	for i in n_st:
		var p_prev := spine[maxi(0, i - 1)]
		var p_next := spine[mini(n_st - 1, i + 1)]
		var tang := (p_next - p_prev).normalized()
		if tang.length_squared() < 1e-6:
			tang = Vector2(1.0, 0.0)
		var perp := Vector2(-tang.y, tang.x)
		# Keep perp consistently pointing toward +v where possible for bright top highlights.
		if perp.y < 0.0:
			perp = -perp

		var t_frac := float(i) / float(n_st - 1)
		var w := widths[i]
		var uv_c := spine[i]
		var uv_top := uv_c + perp * w
		var uv_bot := uv_c - perp * w
		var dr := lerpf(d_ridge, d_edge + 0.005, t_frac * 0.65)
		var de := lerpf(d_edge, d_edge * 0.4, t_frac * 0.5)

		rings.append([
			_hull_map(is_brig, side, uv_top.x, uv_top.y, d_back),
			_hull_map(is_brig, side, uv_top.x, uv_top.y, de),
			_hull_map(is_brig, side, uv_c.x, uv_c.y, dr),
			_hull_map(is_brig, side, uv_bot.x, uv_bot.y, de),
			_hull_map(is_brig, side, uv_bot.x, uv_bot.y, d_back),
		])
		normals.append(_hull_normal_uv(is_brig, side, uv_c.x, uv_c.y))

	for i in n_st - 1:
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		var n_out := (normals[i] + normals[i + 1]).normalized()
		var up_dir := ((r0[1] as Vector3) - (r0[3] as Vector3)).normalized()
		var dn_dir := -up_dir

		# Upper skirt, upper ridge slope (bright gold), lower ridge slope (mid bronze), lower skirt.
		_emit_quad_dir(st, r0[0] as Vector3, r1[0] as Vector3, r1[1] as Vector3, r0[1] as Vector3,
			up_dir, col_lo, col_lo, col_mid, col_mid)
		_emit_quad_dir(st, r0[1] as Vector3, r1[1] as Vector3, r1[2] as Vector3, r0[2] as Vector3,
			(n_out + up_dir * 0.35).normalized(), col_mid, col_mid, col_hi, col_hi)
		_emit_quad_dir(st, r0[2] as Vector3, r1[2] as Vector3, r1[3] as Vector3, r0[3] as Vector3,
			(n_out + dn_dir * 0.35).normalized(), col_hi, col_hi, col_mid, col_mid)
		_emit_quad_dir(st, r0[3] as Vector3, r1[3] as Vector3, r1[4] as Vector3, r0[4] as Vector3,
			dn_dir, col_mid, col_mid, col_lo, col_lo)

	# Close start & tip end-caps cleanly so there are zero open edges.
	var r_start: Array = rings[0]
	var dir_start := ((r_start[2] as Vector3) - (rings[1][2] as Vector3)).normalized()
	_emit_tri_dir(st, r_start[0] as Vector3, r_start[1] as Vector3, r_start[2] as Vector3,
		dir_start, col_lo, col_mid, col_hi)
	_emit_tri_dir(st, r_start[0] as Vector3, r_start[2] as Vector3, r_start[4] as Vector3,
		dir_start, col_lo, col_hi, col_lo)
	_emit_tri_dir(st, r_start[2] as Vector3, r_start[3] as Vector3, r_start[4] as Vector3,
		dir_start, col_hi, col_mid, col_lo)

	var r_end: Array = rings[n_st - 1]
	var dir_end := ((r_end[2] as Vector3) - (rings[n_st - 2][2] as Vector3)).normalized()
	_emit_tri_dir(st, r_end[0] as Vector3, r_end[1] as Vector3, r_end[2] as Vector3,
		dir_end, col_lo, col_mid, col_hi)
	_emit_tri_dir(st, r_end[0] as Vector3, r_end[2] as Vector3, r_end[4] as Vector3,
		dir_end, col_lo, col_hi, col_lo)
	_emit_tri_dir(st, r_end[2] as Vector3, r_end[3] as Vector3, r_end[4] as Vector3,
		dir_end, col_hi, col_mid, col_lo)


static func _add_conformed_gem_boss(st: SurfaceTool, is_brig: bool, side: float,
		center_uv: Vector2, rx: float, ry: float, sides: int,
		d_base: float, d_rim: float, d_apex: float,
		col_apex: Color, col_hi: Color, col_lo: Color) -> void:
	var p_apex := _hull_map(is_brig, side, center_uv.x, center_uv.y, d_apex)
	var p_base_ctr := _hull_map(is_brig, side, center_uv.x, center_uv.y, d_base)
	var n_ctr := _hull_normal_uv(is_brig, side, center_uv.x, center_uv.y)

	var base_ring: Array[Vector3] = []
	var rim_ring: Array[Vector3] = []
	var ang_offset := 0.0 if sides == 4 else PI / float(sides)
	for k in sides:
		var ang := float(k) * TAU / float(sides) + ang_offset
		var u := center_uv.x + cos(ang) * rx
		var v := center_uv.y + sin(ang) * ry
		base_ring.append(_hull_map(is_brig, side, u, v, d_base))
		rim_ring.append(_hull_map(is_brig, side, center_uv.x + cos(ang) * rx * 0.78,
			center_uv.y + sin(ang) * ry * 0.78, d_rim))

	for k in sides:
		var k1 := (k + 1) % sides
		var b0 := base_ring[k]
		var b1 := base_ring[k1]
		var m0 := rim_ring[k]
		var m1 := rim_ring[k1]

		var rad_out := (((b0 + b1) * 0.5) - p_base_ctr).normalized()
		var crown_dir := (n_ctr + rad_out * 0.45).normalized()
		var facet_col := col_hi if ((m0.y + m1.y) * 0.5 >= p_base_ctr.y) else col_lo

		# Beveled base girdle -> sharp pyramidal gem crown facet!
		_emit_quad_dir(st, b0, b1, m1, m0, (rad_out + n_ctr * 0.35).normalized(),
			col_lo, col_lo, facet_col, facet_col)
		_emit_tri_dir(st, m0, m1, p_apex, crown_dir, facet_col, facet_col, col_apex)


static func _emit_quad_dir(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		out_dir: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_emit_tri_dir(st, a, b, c, out_dir, ca, cb, cc)
	_emit_tri_dir(st, a, c, d, out_dir, ca, cc, cd)


static func _emit_tri_dir(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		out_dir: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	if n.dot(out_dir) < 0.0:
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
