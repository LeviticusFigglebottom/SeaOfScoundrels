class_name CaptainCabinFurnishings
extends Node3D
## Sculpted flagship storytelling furnishings for the player ship's stern cabin:
##   1. Brass Armillary Astrolabe & Rotating Orrery Globe (`AstrolabeStand`)
##      with interactive captain's summary & spin boost.
##   2. Captain's Open Logbook Lectern & Trading Company Renown Trophy Stand
##      (`TrophyLectern`) with curved parchment logbook, crimson quill, flickering
##      candlelight (distance-culled > 18 m), and 3 sculpted 3D company medallions.

const CANDLE_LIGHT_CULL_DIST := 18.0
const RENOWN_UNLOCK_THRESHOLD := 50
const RENOWN_GLEAM_THRESHOLD := 250

const COMPANIES_ORDER: Array[StringName] = [
	&"gilded_compass",
	&"sunken_archive",
	&"iron_tide",
]

# Painterly cabin mahogany, carved oak, burnished pirate brass, parchment & jewel palette (sRGB).
const COL_MAHOGANY_HI := Color(0.42, 0.20, 0.11)
const COL_MAHOGANY_MID := Color(0.28, 0.13, 0.07)
const COL_MAHOGANY_LO := Color(0.16, 0.07, 0.04)
const COL_OAK_HI := Color(0.56, 0.36, 0.19)
const COL_OAK_MID := Color(0.42, 0.25, 0.13)
const COL_OAK_LO := Color(0.26, 0.15, 0.08)

const COL_BRASS_HI := Color(0.98, 0.80, 0.30)
const COL_BRASS_MID := Color(0.84, 0.62, 0.18)
const COL_BRASS_LO := Color(0.52, 0.36, 0.10)

const COL_IRON_HI := Color(0.22, 0.21, 0.24)
const COL_IRON_MID := Color(0.12, 0.12, 0.14)
const COL_IRON_LO := Color(0.06, 0.06, 0.08)

const COL_GLOBE_SEA := Color(0.11, 0.36, 0.58)
const COL_GLOBE_DEEP := Color(0.07, 0.24, 0.44)
const COL_GLOBE_LAND := Color(0.88, 0.68, 0.28)

const COL_PARCHMENT := Color(0.95, 0.90, 0.76)
const COL_PARCHMENT_SH := Color(0.82, 0.75, 0.58)
const COL_INK_LINE := Color(0.28, 0.20, 0.14)
const COL_LEATHER := Color(0.42, 0.11, 0.11)
const COL_CRIMSON := Color(0.76, 0.16, 0.14)
const COL_CRIMSON_LO := Color(0.48, 0.09, 0.09)
const COL_WAX := Color(0.96, 0.91, 0.78)
const COL_FLAME_CORE := Color(1.00, 0.95, 0.72)
const COL_FLAME_TIP := Color(1.00, 0.58, 0.14)
const COL_ARCHIVE_TEAL := Color(0.16, 0.92, 0.76)
const COL_ARCHIVE_HOT := Color(0.56, 1.00, 0.92)

# Statically cached procedural ArrayMeshes & materials shared across all active ships.
static var _active_instances: int = 0
static var _wood_mat: StandardMaterial3D = null
static var _brass_mat: StandardMaterial3D = null
static var _brass_gleam_mat: StandardMaterial3D = null
static var _iron_mat: StandardMaterial3D = null
static var _flame_mat: StandardMaterial3D = null
static var _archive_glow_mat: StandardMaterial3D = null
static var _archive_glow_high_mat: StandardMaterial3D = null

static var _astrolabe_base_mesh: ArrayMesh = null
static var _astrolabe_rings_mesh: ArrayMesh = null
static var _orrery_globe_mesh: ArrayMesh = null
static var _lectern_mesh: ArrayMesh = null
static var _medallion_compass_mesh: ArrayMesh = null
static var _medallion_archive_mesh: ArrayMesh = null
static var _medallion_iron_mesh: ArrayMesh = null

@export var ship_class: StringName = &"sloop"
@export var force_all_medallions: bool = false

var astrolabe_stand: Node3D = null
var astrolabe_rings: MeshInstance3D = null
var orrery_globe: MeshInstance3D = null
var astrolabe_interactable: Interactable = null

var trophy_lectern: Node3D = null
var candle_light: OmniLight3D = null
var medallions: Dictionary = {}  # StringName company_id -> MeshInstance3D

var _pedestal_mi: MeshInstance3D = null
var _lectern_mi: MeshInstance3D = null
var _clock: float = 0.0
var _spin_boost: float = 0.0


## Release all statically cached meshes and materials cleanly.
static func clear_shared_cache() -> void:
	_wood_mat = null
	_brass_mat = null
	_brass_gleam_mat = null
	_iron_mat = null
	_flame_mat = null
	_archive_glow_mat = null
	_archive_glow_high_mat = null
	_astrolabe_base_mesh = null
	_astrolabe_rings_mesh = null
	_orrery_globe_mesh = null
	_lectern_mesh = null
	_medallion_compass_mesh = null
	_medallion_archive_mesh = null
	_medallion_iron_mesh = null


func _enter_tree() -> void:
	_active_instances += 1


func _ready() -> void:
	_ensure_shared_assets()
	_build_astrolabe_station()
	_build_trophy_lectern_station()
	var prof: Profile = Game.profile if Game != null else null
	sync_renown(prof, force_all_medallions)


func _exit_tree() -> void:
	var all_mis: Array[MeshInstance3D] = [
		_pedestal_mi,
		astrolabe_rings,
		orrery_globe,
		_lectern_mi,
	]
	for comp_id: StringName in medallions:
		var m := medallions[comp_id] as MeshInstance3D
		if m != null:
			all_mis.append(m)
	for mi in all_mis:
		if mi != null and is_instance_valid(mi):
			if mi.mesh != null:
				for si in mi.mesh.get_surface_count():
					mi.set_surface_override_material(si, null)
			mi.mesh = null
			mi.material_override = null
	medallions.clear()
	_pedestal_mi = null
	astrolabe_rings = null
	orrery_globe = null
	astrolabe_stand = null
	astrolabe_interactable = null
	_lectern_mi = null
	trophy_lectern = null
	candle_light = null
	_active_instances = maxi(0, _active_instances - 1)
	if _active_instances == 0:
		clear_shared_cache()


func _process(delta: float) -> void:
	_clock += delta
	if _spin_boost > 0.0:
		_spin_boost = move_toward(_spin_boost, 0.0, 1.35 * delta)

	# Smoothly rotate nested brass armillary rings & inner cerulean/gold orrery globe!
	if astrolabe_rings != null and is_instance_valid(astrolabe_rings):
		astrolabe_rings.rotation.y += (0.52 + _spin_boost) * delta
		astrolabe_rings.rotation.x = sin(_clock * 0.72) * 0.14
	if orrery_globe != null and is_instance_valid(orrery_globe):
		orrery_globe.rotation.y -= (0.34 + _spin_boost * 0.75) * delta

	# Distance-culled warm flickering cabin candlelight (0.00 ms when camera > 18 m away!).
	if candle_light != null and is_instance_valid(candle_light):
		var vp := get_viewport()
		var cam := vp.get_camera_3d() if vp != null else null
		if cam != null:
			var dist_sq := candle_light.global_position.distance_squared_to(cam.global_position)
			var show_light := visible and dist_sq <= CANDLE_LIGHT_CULL_DIST * CANDLE_LIGHT_CULL_DIST
			candle_light.visible = show_light
			if not show_light:
				return
		else:
			candle_light.visible = visible
		if candle_light.visible:
			var flick := sin(_clock * 6.8) * 0.05 + sin(_clock * 14.3 + 1.1) * 0.028
			candle_light.light_energy = 0.56 + flick


## Toggle and polish the 3 sculpted Trading Company Renown medallions from `profile`.
func sync_renown(profile: Profile, force_all: bool = false) -> void:
	var show_all := force_all or force_all_medallions
	for comp_id: StringName in COMPANIES_ORDER:
		var mi := medallions.get(comp_id) as MeshInstance3D
		if mi == null or not is_instance_valid(mi):
			continue
		var pts := Economy.get_company_renown(profile, comp_id) if profile != null else 0
		var unlocked := show_all or pts >= RENOWN_UNLOCK_THRESHOLD
		var high_gleam := show_all or pts >= RENOWN_GLEAM_THRESHOLD
		mi.visible = unlocked
		if not unlocked:
			continue
		if comp_id == &"gilded_compass":
			mi.set_surface_override_material(0, _brass_gleam_mat if high_gleam else _brass_mat)
		elif comp_id == &"sunken_archive":
			mi.set_surface_override_material(0, _iron_mat)
			if mi.mesh != null and mi.mesh.get_surface_count() > 1:
				mi.set_surface_override_material(1, _archive_glow_high_mat if high_gleam else _archive_glow_mat)
		elif comp_id == &"iron_tide":
			mi.set_surface_override_material(0, _iron_mat)
			if mi.mesh != null and mi.mesh.get_surface_count() > 1:
				mi.set_surface_override_material(1, _wood_mat)
			if mi.mesh != null and mi.mesh.get_surface_count() > 2:
				mi.set_surface_override_material(2, _brass_gleam_mat if high_gleam else _brass_mat)


# ==============================================================================
# Station Builders & Interaction
# ==============================================================================

func _build_astrolabe_station() -> void:
	var is_brig := ship_class == &"brigantine"
	astrolabe_stand = Node3D.new()
	astrolabe_stand.name = "AstrolabeStand"
	if is_brig:
		astrolabe_stand.position = Vector3(0.58, -0.95, 5.45)
		astrolabe_stand.scale = Vector3(0.92, 0.92, 0.92)
	else:
		astrolabe_stand.position = Vector3(0.62, -0.85, 3.55)
	add_child(astrolabe_stand)

	_pedestal_mi = MeshInstance3D.new()
	_pedestal_mi.name = "AstrolabePedestal"
	_pedestal_mi.mesh = _astrolabe_base_mesh
	_pedestal_mi.set_surface_override_material(0, _wood_mat)
	if _astrolabe_base_mesh.get_surface_count() > 1:
		_pedestal_mi.set_surface_override_material(1, _brass_mat)
	astrolabe_stand.add_child(_pedestal_mi)

	astrolabe_rings = MeshInstance3D.new()
	astrolabe_rings.name = "AstrolabeRings"
	astrolabe_rings.position = Vector3(0.0, 1.14, 0.0)
	astrolabe_rings.mesh = _astrolabe_rings_mesh
	astrolabe_rings.material_override = _brass_mat
	astrolabe_stand.add_child(astrolabe_rings)

	orrery_globe = MeshInstance3D.new()
	orrery_globe.name = "OrreryGlobe"
	orrery_globe.position = Vector3(0.0, 1.14, 0.0)
	orrery_globe.rotation.z = deg_to_rad(23.4)
	orrery_globe.mesh = _orrery_globe_mesh
	orrery_globe.set_surface_override_material(0, _wood_mat)
	if _orrery_globe_mesh.get_surface_count() > 1:
		orrery_globe.set_surface_override_material(1, _brass_mat)
	astrolabe_stand.add_child(orrery_globe)

	astrolabe_interactable = Interactable.create("Inspect Captain's Astrolabe & Log", 0.9)
	astrolabe_interactable.name = "AstrolabeInteractable"
	astrolabe_interactable.position = Vector3(0.0, 1.05, 0.0)
	astrolabe_interactable.reach = 2.8
	astrolabe_interactable.target = self
	astrolabe_interactable.interacted.connect(_on_astrolabe_interacted)
	astrolabe_stand.add_child(astrolabe_interactable)


func _build_trophy_lectern_station() -> void:
	var is_brig := ship_class == &"brigantine"
	trophy_lectern = Node3D.new()
	trophy_lectern.name = "TrophyLectern"
	if is_brig:
		trophy_lectern.position = Vector3(-0.56, -0.95, 5.45)
		trophy_lectern.scale = Vector3(0.86, 0.86, 0.86)
		trophy_lectern.rotation.y = 0.55
	else:
		trophy_lectern.position = Vector3(-0.52, -0.85, 3.55)
		trophy_lectern.scale = Vector3(0.88, 0.88, 0.88)
		trophy_lectern.rotation.y = 0.72
	add_child(trophy_lectern)

	_lectern_mi = MeshInstance3D.new()
	_lectern_mi.name = "LecternBody"
	_lectern_mi.mesh = _lectern_mesh
	_lectern_mi.set_surface_override_material(0, _wood_mat)
	if _lectern_mesh.get_surface_count() > 1:
		_lectern_mi.set_surface_override_material(1, _brass_mat)
	if _lectern_mesh.get_surface_count() > 2:
		_lectern_mi.set_surface_override_material(2, _flame_mat)
	trophy_lectern.add_child(_lectern_mi)

	candle_light = OmniLight3D.new()
	candle_light.name = "CabinCandleLight"
	candle_light.position = Vector3(-0.18, 1.04, 0.04)
	candle_light.light_color = Color(1.0, 0.76, 0.42)
	candle_light.light_energy = 0.56
	candle_light.omni_range = 3.2
	candle_light.omni_attenuation = 1.85
	candle_light.shadow_enabled = false
	trophy_lectern.add_child(candle_light)

	# 3 sculpted 3D Trading Company medallions mounted cleanly in the brass trophy rack behind the logbook!
	var med_specs: Array[Array] = [
		[&"gilded_compass", "Medallion_gilded_compass", _medallion_compass_mesh, Vector3(-0.20, 1.21, 0.165)],
		[&"sunken_archive", "Medallion_sunken_archive", _medallion_archive_mesh, Vector3(0.00, 1.23, 0.165)],
		[&"iron_tide", "Medallion_iron_tide", _medallion_iron_mesh, Vector3(0.20, 1.21, 0.165)],
	]
	for spec in med_specs:
		var comp_id: StringName = spec[0] as StringName
		var mi := MeshInstance3D.new()
		mi.name = String(spec[1])
		mi.mesh = spec[2] as ArrayMesh
		mi.position = spec[3] as Vector3
		mi.visible = false
		trophy_lectern.add_child(mi)
		medallions[comp_id] = mi


func _on_astrolabe_interacted(_pawn: Node) -> void:
	_spin_boost = 3.2
	var sfx_pos := astrolabe_stand.global_position if (astrolabe_stand != null and astrolabe_stand.is_inside_tree()) else global_position
	Audio.play_sfx(&"coin_jingle", sfx_pos, -4.0)

	var prof: Profile = Game.profile if Game != null else null
	var gold := int(prof.data.get("gold", 0)) if prof != null else 0
	var disc_arr: Variant = prof.data.get("discoveries", []) if prof != null else []
	var disc_count := (disc_arr as Array).size() if disc_arr is Array else 0
	var r_gc := Economy.get_company_rank(prof, &"gilded_compass")
	var r_sa := Economy.get_company_rank(prof, &"sunken_archive")
	var r_it := Economy.get_company_rank(prof, &"iron_tide")
	Game.post_notice("Captain's Log: %d Gold | %d Discoveries | Compass R%d, Archive R%d, Iron Tide R%d" % [
		gold, disc_count, r_gc, r_sa, r_it])


# ==============================================================================
# Shared Sculpted Flat-Faceted Procedural Assets (Zero Raw Primitives)
# ==============================================================================

static func _ensure_shared_assets() -> void:
	if _wood_mat == null:
		_wood_mat = StandardMaterial3D.new()
		_wood_mat.vertex_color_use_as_albedo = true
		_wood_mat.vertex_color_is_srgb = true
		_wood_mat.roughness = 0.62
		_wood_mat.metallic = 0.04

	if _brass_mat == null:
		_brass_mat = StandardMaterial3D.new()
		_brass_mat.vertex_color_use_as_albedo = true
		_brass_mat.vertex_color_is_srgb = true
		_brass_mat.roughness = 0.25
		_brass_mat.metallic = 0.78

	if _brass_gleam_mat == null:
		_brass_gleam_mat = StandardMaterial3D.new()
		_brass_gleam_mat.vertex_color_use_as_albedo = true
		_brass_gleam_mat.vertex_color_is_srgb = true
		_brass_gleam_mat.roughness = 0.20
		_brass_gleam_mat.metallic = 0.84
		_brass_gleam_mat.emission_enabled = true
		_brass_gleam_mat.emission = Color(1.0, 0.78, 0.26)
		_brass_gleam_mat.emission_energy_multiplier = 0.42

	if _iron_mat == null:
		_iron_mat = StandardMaterial3D.new()
		_iron_mat.vertex_color_use_as_albedo = true
		_iron_mat.vertex_color_is_srgb = true
		_iron_mat.roughness = 0.44
		_iron_mat.metallic = 0.66

	if _flame_mat == null:
		_flame_mat = StandardMaterial3D.new()
		_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flame_mat.vertex_color_use_as_albedo = true
		_flame_mat.vertex_color_is_srgb = true
		_flame_mat.emission_enabled = true
		_flame_mat.emission = Color(1.0, 0.76, 0.28)
		_flame_mat.emission_energy_multiplier = 3.2

	if _archive_glow_mat == null:
		_archive_glow_mat = StandardMaterial3D.new()
		_archive_glow_mat.vertex_color_use_as_albedo = true
		_archive_glow_mat.vertex_color_is_srgb = true
		_archive_glow_mat.roughness = 0.22
		_archive_glow_mat.metallic = 0.16
		_archive_glow_mat.emission_enabled = true
		_archive_glow_mat.emission = Color(0.14, 0.94, 0.78)
		_archive_glow_mat.emission_energy_multiplier = 1.65

	if _archive_glow_high_mat == null:
		_archive_glow_high_mat = StandardMaterial3D.new()
		_archive_glow_high_mat.vertex_color_use_as_albedo = true
		_archive_glow_high_mat.vertex_color_is_srgb = true
		_archive_glow_high_mat.roughness = 0.18
		_archive_glow_high_mat.metallic = 0.18
		_archive_glow_high_mat.emission_enabled = true
		_archive_glow_high_mat.emission = Color(0.18, 0.98, 0.84)
		_archive_glow_high_mat.emission_energy_multiplier = 2.60

	if _astrolabe_base_mesh == null:
		_astrolabe_base_mesh = _build_astrolabe_base_mesh()
	if _astrolabe_rings_mesh == null:
		_astrolabe_rings_mesh = _build_astrolabe_rings_mesh()
	if _orrery_globe_mesh == null:
		_orrery_globe_mesh = _build_orrery_globe_mesh()
	if _lectern_mesh == null:
		_lectern_mesh = _build_lectern_mesh()
	if _medallion_compass_mesh == null:
		_medallion_compass_mesh = _build_medallion_compass_mesh()
	if _medallion_archive_mesh == null:
		_medallion_archive_mesh = _build_medallion_archive_mesh()
	if _medallion_iron_mesh == null:
		_medallion_iron_mesh = _build_medallion_iron_mesh()


static func _build_astrolabe_base_mesh() -> ArrayMesh:
	var wood_st := SurfaceTool.new()
	wood_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var brass_st := SurfaceTool.new()
	brass_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Turned octagonal dark-mahogany pedestal (y = 0.00 .. 0.88 m).
	var ped_rings: Array[Array] = [
		[0.000, 0.000, COL_MAHOGANY_LO],
		[0.000, 0.215, COL_MAHOGANY_LO],
		[0.040, 0.210, COL_MAHOGANY_MID],
		[0.085, 0.165, COL_MAHOGANY_HI],
		[0.145, 0.115, COL_MAHOGANY_MID],
		[0.240, 0.082, COL_MAHOGANY_LO],
		[0.420, 0.098, COL_MAHOGANY_HI],
		[0.540, 0.072, COL_MAHOGANY_MID],
		[0.690, 0.078, COL_MAHOGANY_MID],
		[0.785, 0.132, COL_MAHOGANY_HI],
		[0.855, 0.155, COL_MAHOGANY_HI],
		[0.880, 0.142, COL_MAHOGANY_MID],
		[0.880, 0.000, COL_MAHOGANY_LO],
	]
	_append_lathe_y(wood_st, ped_rings, 8)

	# 3 decorative splayed mahogany claw feet with brass caps resting flush at y = 0.0.
	for fi in 3:
		var ang := float(fi) / 3.0 * TAU + 0.52
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		_append_prism(wood_st, dir * 0.14 + Vector3(0.0, 0.09, 0.0), dir * 0.24 + Vector3(0.0, 0.02, 0.0),
			0.042, 0.030, 5, COL_MAHOGANY_HI, COL_MAHOGANY_LO)
		_append_prism(brass_st, dir * 0.235 + Vector3(0.0, 0.00, 0.0), dir * 0.235 + Vector3(0.0, 0.034, 0.0),
			0.032, 0.026, 6, COL_BRASS_LO, COL_BRASS_HI)

	# 3 gleaming brass pedestal collar rings + central cradle finial spire.
	for cy_r: Array in [[0.145, 0.122], [0.540, 0.084], [0.855, 0.162]]:
		var cy: float = float(cy_r[0])
		var cr: float = float(cy_r[1])
		_append_lathe_y(brass_st, [
			[cy - 0.018, cr - 0.008, COL_BRASS_LO],
			[cy - 0.008, cr, COL_BRASS_HI],
			[cy + 0.008, cr, COL_BRASS_HI],
			[cy + 0.018, cr - 0.008, COL_BRASS_LO],
		], 8)

	# 2. Stationary outer brass horizon ring at y = 1.14 m + 4 curved supporting quadrant arms!
	var center_y := 1.14
	var hor_r := 0.268
	_append_torus_ring(brass_st, Vector3(0.0, center_y, 0.0), Basis.IDENTITY, hor_r, 0.016, 0.011, 16, COL_BRASS_HI, COL_BRASS_LO)

	# 4 curved brass quadrant support arms rising from pedestal top (y = 0.87) up to horizon ring!
	for ai in 4:
		var ang := float(ai) * PI * 0.5 + PI * 0.25
		var rdir := Vector3(cos(ang), 0.0, sin(ang))
		var p0 := rdir * 0.09 + Vector3(0.0, 0.865, 0.0)
		var p1 := rdir * 0.21 + Vector3(0.0, 0.945, 0.0)
		var p2 := rdir * hor_r + Vector3(0.0, center_y - 0.010, 0.0)
		_append_prism(brass_st, p0, p1, 0.014, 0.012, 5, COL_BRASS_MID, COL_BRASS_HI)
		_append_prism(brass_st, p1, p2, 0.012, 0.011, 5, COL_BRASS_HI, COL_BRASS_MID)

	# 8 raised brass degree tick bosses around the horizon ring.
	for ti in 8:
		var ang := float(ti) / 8.0 * TAU
		var tpos := Vector3(cos(ang) * hor_r, center_y + 0.013, sin(ang) * hor_r)
		_append_box(brass_st, Transform3D(Basis(Vector3.UP, -ang), tpos),
			Vector3(0.024, 0.010, 0.010), COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)

	wood_st.generate_normals()
	var mesh := wood_st.commit()
	brass_st.generate_normals()
	brass_st.commit(mesh)
	return mesh


static func _build_astrolabe_rings_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Nested brass armillary meridian, tilted ecliptic band, equatorial ring & polar spindle!
	# 1. Outer vertical meridian ring (in XY plane).
	_append_torus_ring(st, Vector3.ZERO, Basis(Vector3.RIGHT, PI * 0.5), 0.224, 0.012, 0.010, 16, COL_BRASS_HI, COL_BRASS_LO)
	# 2. Orthogonal vertical colure ring (in YZ plane).
	_append_torus_ring(st, Vector3.ZERO, Basis(Vector3.BACK, PI * 0.5), 0.210, 0.010, 0.008, 16, COL_BRASS_MID, COL_BRASS_LO)
	# 3. Wide tilted ecliptic zodiac band (tilted 24 deg, 16 segments).
	var ecl_rot := Basis(Vector3.FORWARD, deg_to_rad(24.0))
	_append_torus_ring(st, Vector3.ZERO, ecl_rot, 0.194, 0.009, 0.024, 16, COL_BRASS_HI, COL_BRASS_MID)
	# 4. Inner equatorial ring.
	_append_torus_ring(st, Vector3.ZERO, Basis.IDENTITY, 0.168, 0.008, 0.008, 14, COL_BRASS_HI, COL_BRASS_LO)
	# 5. Polar brass spindle axis piercing through the globe poles + miniature sun & moon finials!
	var axis_dir := Basis(Vector3.FORWARD, deg_to_rad(23.4)) * Vector3.UP
	_append_prism(st, -axis_dir * 0.232, axis_dir * 0.232, 0.007, 0.007, 6, COL_BRASS_LO, COL_BRASS_HI)
	_append_faceted_sphere(st, axis_dir * 0.244, 0.019, COL_BRASS_HI, COL_BRASS_MID)
	_append_faceted_sphere(st, -axis_dir * 0.240, 0.014, COL_BRASS_MID, COL_BRASS_LO)

	st.generate_normals()
	return st.commit()


static func _build_orrery_globe_mesh() -> ArrayMesh:
	var globe_st := SurfaceTool.new()
	globe_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var brass_st := SurfaceTool.new()
	brass_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1x subdivided geodesic faceted crystal globe (80 crisp flat facets) with cerulean ocean & antique-gold continents!
	var phi := (1.0 + sqrt(5.0)) * 0.5
	var raw_v: Array[Vector3] = [
		Vector3(-1.0, phi, 0.0), Vector3(1.0, phi, 0.0), Vector3(-1.0, -phi, 0.0), Vector3(1.0, -phi, 0.0),
		Vector3(0.0, -1.0, phi), Vector3(0.0, 1.0, phi), Vector3(0.0, -1.0, -phi), Vector3(0.0, 1.0, -phi),
		Vector3(phi, 0.0, -1.0), Vector3(phi, 0.0, 1.0), Vector3(-phi, 0.0, -1.0), Vector3(-phi, 0.0, 1.0),
	]
	for i in raw_v.size():
		raw_v[i] = raw_v[i].normalized()

	var base_faces: Array[Array] = [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]

	const R := 0.118
	for f in base_faces:
		var a: Vector3 = raw_v[int(f[0])]
		var b: Vector3 = raw_v[int(f[1])]
		var c: Vector3 = raw_v[int(f[2])]
		var ab := (a + b).normalized()
		var bc := (b + c).normalized()
		var ca := (c + a).normalized()
		for sub: Array in [[a, ab, ca], [b, bc, ab], [c, ca, bc], [ab, bc, ca]]:
			var v0: Vector3 = sub[0] as Vector3
			var v1: Vector3 = sub[1] as Vector3
			var v2: Vector3 = sub[2] as Vector3
			var dir_c := (v0 + v1 + v2).normalized()
			# Organic archipelago & continent lobes painted in antique gold over deep cerulean seas!
			var land_val := sin(dir_c.x * 3.4 + dir_c.z * 2.1) * cos(dir_c.y * 2.8 - dir_c.x * 1.4) \
				+ 0.45 * sin(dir_c.z * 5.2 - dir_c.y * 3.6)
			var is_land := land_val > 0.24
			var rad_scale := 1.045 if is_land else 1.0
			var col := COL_GLOBE_LAND if is_land else (COL_GLOBE_SEA if dir_c.y > -0.2 else COL_GLOBE_DEEP)
			_emit_outward_tri(globe_st, v0 * (R * rad_scale), v1 * (R * rad_scale), v2 * (R * rad_scale),
				Vector3.ZERO, col, col, col)

	# Delicate gleaming equatorial brass band hugging the globe!
	_append_torus_ring(brass_st, Vector3.ZERO, Basis.IDENTITY, R * 1.055, 0.005, 0.005, 16, COL_BRASS_HI, COL_BRASS_LO)

	globe_st.generate_normals()
	var mesh := globe_st.commit()
	brass_st.generate_normals()
	brass_st.commit(mesh)
	return mesh


static func _build_lectern_mesh() -> ArrayMesh:
	var wood_st := SurfaceTool.new()
	wood_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var brass_st := SurfaceTool.new()
	brass_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var flame_st := SurfaceTool.new()
	flame_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Carved oak lectern base, paneled column, shelf & slanted reading desk (y = 0.00 .. 0.94 m).
	# Grounded splayed base plinth & carved trestle runners flush at y = 0.0.
	_append_box(wood_st, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.038, 0.0)),
		Vector3(0.58, 0.076, 0.44), COL_OAK_HI, COL_OAK_MID, COL_OAK_LO)
	for sx: float in [-0.26, 0.26]:
		_append_box(wood_st, Transform3D(Basis.IDENTITY, Vector3(sx, 0.055, 0.0)),
			Vector3(0.085, 0.11, 0.50), COL_OAK_HI, COL_OAK_MID, COL_OAK_LO)

	# Fluted heavy central oak reading pillar + carved side scroll cheeks + mid shelf.
	_append_box(wood_st, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.46, 0.03)),
		Vector3(0.32, 0.78, 0.26), COL_OAK_HI, COL_OAK_MID, COL_OAK_LO)
	_append_box(wood_st, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.46, 0.02)),
		Vector3(0.42, 0.055, 0.34), COL_OAK_HI, COL_OAK_MID, COL_OAK_LO)
	for sx: float in [-0.20, 0.20]:
		_append_box(wood_st, Transform3D(Basis.IDENTITY, Vector3(sx, 0.46, 0.03)),
			Vector3(0.055, 0.72, 0.30), COL_MAHOGANY_HI, COL_MAHOGANY_MID, COL_MAHOGANY_LO)
		_append_box(brass_st, Transform3D(Basis.IDENTITY, Vector3(sx, 0.09, -0.22)),
			Vector3(0.06, 0.04, 0.04), COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)

	# Slanted reading desk top (angled 16 deg toward reader at -Z) + front book-stop lip rail.
	var desk_tilt := Basis(Vector3.RIGHT, deg_to_rad(-16.0))
	var desk_xf := Transform3D(desk_tilt, Vector3(0.0, 0.90, -0.02))
	_append_box(wood_st, desk_xf, Vector3(0.68, 0.052, 0.46), COL_OAK_HI, COL_OAK_MID, COL_OAK_LO)
	_append_box(wood_st, desk_xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.042, -0.21)),
		Vector3(0.66, 0.038, 0.028), COL_MAHOGANY_HI, COL_MAHOGANY_MID, COL_MAHOGANY_LO)

	# 2. Open Captain's Logbook resting on the slanted desk (curved cream pages + red bookmark!).
	var book_xf := desk_xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.038, -0.02))
	# Crimson leather cover boards & brass corner protectors.
	_append_box(wood_st, book_xf, Vector3(0.40, 0.018, 0.28), COL_LEATHER, COL_LEATHER.darkened(0.18), COL_MAHOGANY_LO)
	for sx: float in [-0.19, 0.19]:
		for sz: float in [-0.13, 0.13]:
			_append_box(brass_st, book_xf * Transform3D(Basis.IDENTITY, Vector3(sx, 0.008, sz)),
				Vector3(0.030, 0.022, 0.030), COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)
	# Sculpted arched open cream-parchment left & right page sheaves!
	for side_sgn: float in [-1.0, 1.0]:
		var px_pts: Array[Vector2] = [
			Vector2(0.002, 0.012),
			Vector2(0.055, 0.036),
			Vector2(0.125, 0.038),
			Vector2(0.182, 0.022),
		]
		for si in range(px_pts.size() - 1):
			var a := px_pts[si]
			var b := px_pts[si + 1]
			var mid_x := side_sgn * 0.5 * (a.x + b.x)
			var mid_y := 0.5 * (a.y + b.y)
			var dx := (b.x - a.x)
			var dy := (b.y - a.y)
			var seg_w := sqrt(dx * dx + dy * dy) + 0.004
			var ang := atan2(dy, dx) * side_sgn
			var pcol := COL_PARCHMENT if si != 0 else COL_PARCHMENT_SH
			_append_box(wood_st,
				book_xf * Transform3D(Basis(Vector3.BACK, ang), Vector3(mid_x, mid_y, 0.0)),
				Vector3(seg_w, 0.018, 0.252), pcol, COL_PARCHMENT_SH, COL_PARCHMENT_SH)
		# Crisp sepia handwritten ink script bars on open pages!
		for li in 4:
			var lz := -0.075 + float(li) * 0.048
			_append_box(wood_st,
				book_xf * Transform3D(Basis.IDENTITY, Vector3(side_sgn * 0.098, 0.047, lz)),
				Vector3(0.115, 0.004, 0.011), COL_INK_LINE, COL_INK_LINE, COL_INK_LINE)
	# Flowing crimson silk bookmark ribbon draped over the front lip!
	_append_box(wood_st, book_xf * Transform3D(Basis(Vector3.RIGHT, 0.14), Vector3(0.028, 0.028, -0.155)),
		Vector3(0.020, 0.006, 0.11), COL_CRIMSON, COL_CRIMSON, COL_CRIMSON_LO)

	# 3. Brass Inkwell & Arched Crimson Feather Quill on starboard corner (x = +0.25).
	var ink_pos := Vector3(0.25, 0.945, 0.08)
	_append_lathe_y(brass_st, [
		[0.000, 0.000, COL_BRASS_LO],
		[0.000, 0.038, COL_BRASS_LO],
		[0.012, 0.042, COL_BRASS_HI],
		[0.042, 0.032, COL_BRASS_MID],
		[0.052, 0.022, COL_BRASS_HI],
		[0.052, 0.000, COL_IRON_LO],
	], 8, ink_pos)
	# Crimson pirate feather quill rising jauntily from inkwell!
	_append_prism(wood_st, ink_pos + Vector3(0.0, 0.038, 0.0), ink_pos + Vector3(0.065, 0.23, 0.035),
		0.006, 0.003, 4, COL_WAX, COL_WAX)
	_append_box(wood_st, Transform3D(Basis.from_euler(Vector3(0.18, 0.35, -0.30)), ink_pos + Vector3(0.045, 0.175, 0.025)),
		Vector3(0.042, 0.145, 0.010), COL_CRIMSON, COL_CRIMSON, COL_CRIMSON_LO)

	# 4. Flickering Wax Candle on Brass Saucer with Emissive Teardrop Flame (port corner x = -0.22).
	var cdl_pos := Vector3(-0.22, 0.945, 0.08)
	_append_lathe_y(brass_st, [
		[0.000, 0.000, COL_BRASS_LO],
		[0.000, 0.064, COL_BRASS_LO],
		[0.016, 0.070, COL_BRASS_HI],
		[0.020, 0.056, COL_BRASS_MID],
		[0.010, 0.000, COL_BRASS_LO],
	], 8, cdl_pos)
	# Wax candle body + wick + glowing teardrop flame (Surface 2)!
	_append_lathe_y(wood_st, [
		[0.012, 0.028, COL_WAX],
		[0.140, 0.025, COL_WAX],
		[0.148, 0.022, COL_PARCHMENT_SH],
		[0.148, 0.000, COL_PARCHMENT_SH],
	], 8, cdl_pos)
	_append_prism(wood_st, cdl_pos + Vector3(0.0, 0.146, 0.0), cdl_pos + Vector3(0.0, 0.164, 0.0),
		0.003, 0.002, 4, COL_IRON_LO, COL_IRON_LO)
	_append_lathe_y(flame_st, [
		[0.160, 0.000, COL_FLAME_CORE],
		[0.172, 0.018, COL_FLAME_CORE],
		[0.192, 0.014, COL_FLAME_TIP],
		[0.218, 0.000, COL_FLAME_TIP],
	], 6, cdl_pos)

	# 5. Brass-Framed 3-Slot Trading Company Renown Trophy Rack rising behind the logbook!
	# Twin carved mahogany & brass side stanchions + arched backboard + 3 beveled brass slot bezels.
	for sx: float in [-0.31, 0.31]:
		_append_box(wood_st, Transform3D(Basis.IDENTITY, Vector3(sx, 1.15, 0.19)),
			Vector3(0.052, 0.44, 0.052), COL_MAHOGANY_HI, COL_MAHOGANY_MID, COL_MAHOGANY_LO)
		_append_faceted_sphere(brass_st, Vector3(sx, 1.39, 0.19), 0.028, COL_BRASS_HI, COL_BRASS_LO)
	_append_box(wood_st, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.20, 0.205)),
		Vector3(0.64, 0.30, 0.044), COL_MAHOGANY_HI, COL_MAHOGANY_MID, COL_MAHOGANY_LO)
	_append_box(brass_st, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.365, 0.205)),
		Vector3(0.68, 0.036, 0.056), COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)
	_append_box(brass_st, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.045, 0.205)),
		Vector3(0.68, 0.032, 0.056), COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)
	# 3 recessed brass medallion mounting rosettes facing -Z!
	for mx_my: Array in [[-0.20, 1.21], [0.00, 1.23], [0.20, 1.21]]:
		var m_xf := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(float(mx_my[0]), float(mx_my[1]), 0.180))
		_append_torus_ring(brass_st, m_xf.origin, m_xf.basis, 0.072, 0.008, 0.009, 10, COL_BRASS_HI, COL_BRASS_LO)

	wood_st.generate_normals()
	var mesh := wood_st.commit()
	brass_st.generate_normals()
	brass_st.commit(mesh)
	flame_st.generate_normals()
	flame_st.commit(mesh)
	return mesh


static func _build_medallion_compass_mesh() -> ArrayMesh:
	# Gilded Compass: Burnished gold 8-point compass sun-disc medallion facing -Z!
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Beveled circular gold backing plaque.
	var plaque_rot := Basis(Vector3.RIGHT, -PI * 0.5)
	_append_disc_z(st, 0.068, 0.016, 12, COL_BRASS_MID, COL_BRASS_LO)
	_append_torus_ring(st, Vector3(0.0, 0.0, -0.008), plaque_rot, 0.064, 0.009, 0.009, 12, COL_BRASS_HI, COL_BRASS_LO)

	# Raised 8-point faceted compass star rays protruding forward along -Z!
	for ki in 8:
		var ang := float(ki) / 8.0 * TAU
		var is_card := (ki % 2 == 0)
		var r_tip := 0.066 if is_card else 0.048
		var r_side := 0.015 if is_card else 0.011
		var dir := Vector3(cos(ang), sin(ang), 0.0)
		var perp := Vector3(-sin(ang), cos(ang), 0.0)
		var apex := Vector3(0.0, 0.0, -0.028)
		var tip := dir * r_tip + Vector3(0.0, 0.0, -0.012)
		var sl := dir * 0.014 + perp * r_side + Vector3(0.0, 0.0, -0.014)
		var sr := dir * 0.014 - perp * r_side + Vector3(0.0, 0.0, -0.014)
		var ref_back := Vector3(0.0, 0.0, 0.02)
		_emit_outward_tri(st, apex, sl, tip, ref_back, COL_BRASS_HI, COL_BRASS_HI, COL_BRASS_MID)
		_emit_outward_tri(st, apex, tip, sr, ref_back, COL_BRASS_MID, COL_BRASS_LO, COL_BRASS_LO)

	st.generate_normals()
	return st.commit()


static func _build_medallion_archive_mesh() -> ArrayMesh:
	# Sunken Archive: Dark obsidian octagonal frame (Surface 0) + luminous turquoise-emerald sea tablet (Surface 1)!
	var iron_st := SurfaceTool.new()
	iron_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow_st := SurfaceTool.new()
	glow_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Heavy chamfered octagonal obsidian bezel plaque.
	_append_disc_z(iron_st, 0.072, 0.020, 8, COL_IRON_HI, COL_IRON_LO)
	_append_torus_ring(iron_st, Vector3(0.0, 0.0, -0.010), Basis(Vector3.RIGHT, -PI * 0.5),
		0.064, 0.010, 0.010, 8, COL_IRON_HI, COL_IRON_LO)

	# Luminous recessed octagonal turquoise sea-tablet + raised glowing rune diamond center!
	_append_disc_z(glow_st, 0.052, 0.016, 8, COL_ARCHIVE_TEAL, COL_ARCHIVE_TEAL.darkened(0.25), Vector3(0.0, 0.0, -0.008))
	_append_box(glow_st, Transform3D(Basis(Vector3.BACK, PI * 0.25), Vector3(0.0, 0.0, -0.022)),
		Vector3(0.036, 0.036, 0.014), COL_ARCHIVE_HOT, COL_ARCHIVE_TEAL, COL_ARCHIVE_TEAL)

	iron_st.generate_normals()
	var mesh := iron_st.commit()
	glow_st.generate_normals()
	glow_st.commit(mesh)
	return mesh


static func _build_medallion_iron_mesh() -> ArrayMesh:
	# Iron Tide: Forged soot-black iron heater shield (Surface 0) + crimson chevron field (Surface 1) + gold boss (Surface 2)!
	var iron_st := SurfaceTool.new()
	iron_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paint_st := SurfaceTool.new()
	paint_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var brass_st := SurfaceTool.new()
	brass_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Heraldic heater shield silhouette (flat top, tapered pointed base).
	var shield_pts: Array[Vector2] = [
		Vector2(-0.056, 0.064),
		Vector2(0.056, 0.064),
		Vector2(0.056, 0.004),
		Vector2(0.036, -0.044),
		Vector2(0.000, -0.074),
		Vector2(-0.036, -0.044),
		Vector2(-0.056, 0.004),
	]
	_append_extruded_poly_z(iron_st, shield_pts, -0.010, 0.010, COL_IRON_HI, COL_IRON_MID, COL_IRON_LO)

	# Recessed crimson heraldic inner shield field!
	var inner_pts: Array[Vector2] = []
	for pt in shield_pts:
		inner_pts.append(pt * 0.78)
	_append_extruded_poly_z(paint_st, inner_pts, -0.016, -0.008, COL_CRIMSON, COL_CRIMSON, COL_CRIMSON_LO)

	# Raised golden chevron V-bars + central cannonball boss!
	_append_box(brass_st, Transform3D(Basis(Vector3.BACK, -0.52), Vector3(-0.020, 0.004, -0.020)),
		Vector3(0.048, 0.014, 0.012), COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)
	_append_box(brass_st, Transform3D(Basis(Vector3.BACK, 0.52), Vector3(0.020, 0.004, -0.020)),
		Vector3(0.048, 0.014, 0.012), COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_LO)
	_append_faceted_sphere(brass_st, Vector3(0.0, 0.022, -0.022), 0.016, COL_BRASS_HI, COL_BRASS_LO)

	iron_st.generate_normals()
	var mesh := iron_st.commit()
	paint_st.generate_normals()
	paint_st.commit(mesh)
	brass_st.generate_normals()
	brass_st.commit(mesh)
	return mesh


# ==============================================================================
# Flat-Faceted `SurfaceTool` Helpers (`set_smooth_group(-1)`)
# ==============================================================================

static func _append_lathe_y(st: SurfaceTool, rings: Array[Array], segs: int,
		offset: Vector3 = Vector3.ZERO) -> void:
	for j in range(rings.size() - 1):
		var y0 := float(rings[j][0])
		var r0 := float(rings[j][1])
		var c0: Color = rings[j][2] as Color
		var y1 := float(rings[j + 1][0])
		var r1 := float(rings[j + 1][1])
		var c1: Color = rings[j + 1][2] as Color
		var ym := 0.5 * (y0 + y1)
		var ctr := offset + Vector3(0.0, ym, 0.0)
		for k in segs:
			var a0 := float(k) / float(segs) * TAU
			var a1 := float((k + 1) % segs) / float(segs) * TAU
			var p00 := offset + Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p01 := offset + Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p10 := offset + Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := offset + Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			if r0 > 1e-5 and r1 > 1e-5:
				_emit_outward_quad(st, p00, p10, p11, p01, ctr, c0, c1, c1, c0)
			elif r1 > 1e-5:
				var ref_cap := offset + Vector3(0.0, y1 + (0.05 if y1 >= y0 else -0.05), 0.0)
				_emit_outward_tri(st, p00, p10, p11, ref_cap, c0, c1, c1)
			elif r0 > 1e-5:
				var ref_cap := offset + Vector3(0.0, y0 + (0.05 if y0 >= y1 else -0.05), 0.0)
				_emit_outward_tri(st, p10, p01, p00, ref_cap, c1, c0, c0)


static func _append_torus_ring(st: SurfaceTool, center: Vector3, rot: Basis,
		major_r: float, radial_half: float, height_half: float, segs: int,
		col_hi: Color, col_lo: Color) -> void:
	var sec_rings: Array[Array] = []
	for i in segs:
		var a := float(i) / float(segs) * TAU
		var rdir := Vector3(cos(a), 0.0, sin(a))
		var r_in := maxf(major_r - radial_half, 0.002)
		var r_out := major_r + radial_half
		var ring: Array[Vector3] = [
			center + rot * (rdir * r_out + Vector3(0.0, height_half, 0.0)),
			center + rot * (rdir * r_in + Vector3(0.0, height_half, 0.0)),
			center + rot * (rdir * r_in - Vector3(0.0, height_half, 0.0)),
			center + rot * (rdir * r_out - Vector3(0.0, height_half, 0.0)),
		]
		sec_rings.append(ring)
	var cols: Array[Color] = [col_hi, col_hi, col_lo, col_lo]
	for i in segs:
		var ni := (i + 1) % segs
		var r0: Array = sec_rings[i]
		var r1: Array = sec_rings[ni]
		var am := (float(i) + 0.5) / float(segs) * TAU
		var tube_ctr := center + rot * (Vector3(cos(am), 0.0, sin(am)) * major_r)
		for k in 4:
			var nk := (k + 1) % 4
			_emit_outward_quad(st, r0[k] as Vector3, r1[k] as Vector3, r1[nk] as Vector3, r0[nk] as Vector3,
				tube_ctr, cols[k], cols[k], cols[nk], cols[nk])


static func _append_disc_z(st: SurfaceTool, radius: float, thickness: float, segs: int,
		col_face: Color, col_rim: Color, offset: Vector3 = Vector3.ZERO) -> void:
	var hz := thickness * 0.5
	var f_ring: Array[Vector3] = []
	var b_ring: Array[Vector3] = []
	for k in segs:
		var a := float(k) / float(segs) * TAU
		f_ring.append(offset + Vector3(cos(a) * radius, sin(a) * radius, -hz))
		b_ring.append(offset + Vector3(cos(a) * radius, sin(a) * radius, hz))
	var f_ctr := offset + Vector3(0.0, 0.0, -hz)
	var b_ctr := offset + Vector3(0.0, 0.0, hz)
	for k in segs:
		var nk := (k + 1) % segs
		_emit_outward_tri(st, f_ctr, f_ring[k], f_ring[nk], offset + Vector3(0.0, 0.0, 0.05), col_face, col_face, col_face)
		_emit_outward_tri(st, b_ctr, b_ring[nk], b_ring[k], offset - Vector3(0.0, 0.0, 0.05), col_rim, col_rim, col_rim)
		_emit_outward_quad(st, f_ring[k], b_ring[k], b_ring[nk], f_ring[nk], offset, col_rim, col_rim, col_rim, col_rim)


static func _append_extruded_poly_z(st: SurfaceTool, pts: Array[Vector2], z_front: float, z_back: float,
		col_front: Color, col_side: Color, col_back: Color) -> void:
	var n := pts.size()
	var ctr2 := Vector2.ZERO
	for p in pts:
		ctr2 += p
	ctr2 /= float(maxi(n, 1))
	var f_ctr := Vector3(ctr2.x, ctr2.y, z_front)
	var b_ctr := Vector3(ctr2.x, ctr2.y, z_back)
	var mid_ctr := Vector3(ctr2.x, ctr2.y, 0.5 * (z_front + z_back))
	for i in n:
		var ni := (i + 1) % n
		var p0 := pts[i]
		var p1 := pts[ni]
		var f0 := Vector3(p0.x, p0.y, z_front)
		var f1 := Vector3(p1.x, p1.y, z_front)
		var b0 := Vector3(p0.x, p0.y, z_back)
		var b1 := Vector3(p1.x, p1.y, z_back)
		_emit_outward_tri(st, f_ctr, f0, f1, b_ctr, col_front, col_front, col_front)
		_emit_outward_tri(st, b_ctr, b1, b0, f_ctr, col_back, col_back, col_back)
		_emit_outward_quad(st, f0, b0, b1, f1, mid_ctr, col_side, col_side, col_side, col_side)


static func _append_prism(st: SurfaceTool, p0: Vector3, p1: Vector3,
		r0: float, r1: float, sides: int, c0: Color, c1: Color) -> void:
	var axis := p1 - p0
	if axis.length_squared() < 1e-8:
		return
	var dir := axis.normalized()
	var ref := Vector3.RIGHT if absf(dir.dot(Vector3.RIGHT)) < 0.85 else Vector3.FORWARD
	var u := dir.cross(ref).normalized()
	var v := u.cross(dir).normalized()
	var ring0: Array[Vector3] = []
	var ring1: Array[Vector3] = []
	for k in sides:
		var a := float(k) / float(sides) * TAU
		var rad := u * cos(a) + v * sin(a)
		ring0.append(p0 + rad * r0)
		ring1.append(p1 + rad * r1)
	var mid := (p0 + p1) * 0.5
	for k in sides:
		var nk := (k + 1) % sides
		_emit_outward_quad(st, ring0[k], ring1[k], ring1[nk], ring0[nk], mid, c0, c1, c1, c0)
		_emit_outward_tri(st, p0, ring0[nk], ring0[k], mid, c0, c0, c0)
		_emit_outward_tri(st, p1, ring1[k], ring1[nk], mid, c1, c1, c1)


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


static func _append_faceted_sphere(st: SurfaceTool, center: Vector3, radius: float,
		col_hi: Color, col_lo: Color) -> void:
	const LON := 8
	const LAT := 4
	var rings: Array[Array] = []
	for li in range(1, LAT):
		var phi := PI * float(li) / float(LAT)
		var ring: Array[Vector3] = []
		for ki in LON:
			var theta := TAU * float(ki) / float(LON)
			ring.append(center + Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta)) * radius)
		rings.append(ring)
	var north := center + Vector3(0.0, radius, 0.0)
	var south := center - Vector3(0.0, radius, 0.0)
	for ki in LON:
		var nki := (ki + 1) % LON
		_emit_outward_tri(st, north, rings[0][ki] as Vector3, rings[0][nki] as Vector3, center, col_hi, col_hi, col_hi)
		_emit_outward_tri(st, south, rings[rings.size() - 1][nki] as Vector3, rings[rings.size() - 1][ki] as Vector3,
			center, col_lo, col_lo, col_lo)
	for li in range(rings.size() - 1):
		var c0 := col_hi if li == 0 else col_lo
		var c1 := col_lo
		for ki in LON:
			var nki := (ki + 1) % LON
			_emit_outward_quad(st, rings[li][ki] as Vector3, rings[li + 1][ki] as Vector3,
				rings[li + 1][nki] as Vector3, rings[li][nki] as Vector3, center, c0, c1, c1, c0)


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
