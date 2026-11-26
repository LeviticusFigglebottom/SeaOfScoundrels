class_name WorldEventCloud
extends Node3D
## Iconic horizon-readable Sea-of-Thieves World Event Sky Beacons.
##
## Sculpts three colossal flat-faceted painterly ArrayMesh formations hovering
## at CLOUD_ALTITUDE (175.0 m) so crews can read active world events across
## 2,500 m of open ocean at noon, sunset, and midnight:
##   - &"fort_siege" -> "Fort Skull Cloud" (billowing storm-slate skull + blazing emerald eyes)
##   - &"ghost_ship" -> "Ghost Fleet Cloud" (spectral teal vortex + ghostly galleon silhouette)
##   - &"leviathan"  -> "Abyssal Tempest Cloud" (indigo-violet anvil + 5 curling tentacle arcs)
##
## Uses 100% sculpted SurfaceTool ArrayMeshes (zero PrimitiveMesh), ref-counted
## static mesh/material caches, SHADOW_CASTING_SETTING_OFF, and zero-leak cleanup.

const GROUP := &"world_event_clouds"
const CLOUD_ALTITUDE := 175.0
const BOB_AMPLITUDE := 3.2
const DEFAULT_FADE_DURATION := 1.5
const MIN_SCALE := 0.001
const VALID_KINDS: Array[StringName] = [&"fort_siege", &"ghost_ship", &"leviathan"]

enum FadeState { FADING_IN, ACTIVE, FADING_OUT }

# Painterly sky-beacon sRGB palettes.
const COL_SKULL_HI := Color(0.58, 0.64, 0.68)
const COL_SKULL_MID := Color(0.28, 0.34, 0.40)
const COL_SKULL_DEEP := Color(0.11, 0.14, 0.19)
const COL_SKULL_UNDER := Color(0.20, 0.36, 0.30)
const COL_FORT_EYE_HI := Color(0.46, 1.00, 0.62)
const COL_FORT_EYE_LO := Color(0.12, 0.86, 0.42)

const COL_GHOST_HI := Color(0.58, 0.90, 0.90)
const COL_GHOST_MID := Color(0.18, 0.50, 0.56)
const COL_GHOST_DEEP := Color(0.08, 0.22, 0.30)
const COL_GHOST_GLOW_HI := Color(0.54, 1.00, 0.94)
const COL_GHOST_GLOW_LO := Color(0.14, 0.84, 0.80)

const COL_LEV_HI := Color(0.54, 0.46, 0.72)
const COL_LEV_MID := Color(0.24, 0.17, 0.40)
const COL_LEV_DEEP := Color(0.10, 0.07, 0.20)
const COL_LEV_EYE_HI := Color(0.86, 0.58, 1.00)
const COL_LEV_EYE_LO := Color(0.54, 0.20, 0.96)

# Ref-counted static shared caches (zero extra VRAM; cleared when _active_instances hits 0).
static var _active_instances: int = 0
static var _mesh_cache: Dictionary = {}
static var _body_mat_cache: Dictionary = {}
static var _accent_mat_cache: Dictionary = {}

var event_kind: StringName = &"fort_siege"
var display_label: String = "Fort Skull Cloud"
var event_world_pos: Vector3 = Vector3.ZERO

var _visual_root: Node3D = null
var _cloud_mi: MeshInstance3D = null
var _accent_override: StandardMaterial3D = null
var _configured: bool = false
var _fade_state: FadeState = FadeState.ACTIVE
var _fade_duration: float = DEFAULT_FADE_DURATION
var _scale_t: float = 1.0
var _anim_time: float = 0.0
var _phase_offset: float = 0.0
var _tri_count: int = 0


## Return the strict-ASCII display label for a world event cloud kind.
static func label_for_kind(kind: StringName) -> String:
	match kind:
		&"ghost_ship":
			return "Ghost Fleet Cloud"
		&"leviathan":
			return "Abyssal Tempest Cloud"
		_:
			return "Fort Skull Cloud"


## Release all statically cached cloud ArrayMeshes and StandardMaterial3Ds cleanly.
static func clear_shared_cache() -> void:
	_mesh_cache.clear()
	_body_mat_cache.clear()
	_accent_mat_cache.clear()


func _enter_tree() -> void:
	_active_instances += 1
	add_to_group(GROUP)


func _ready() -> void:
	if not _configured:
		configure(event_kind, Vector3(position.x, 0.0, position.z), true)
	else:
		global_position = Vector3(event_world_pos.x, CLOUD_ALTITUDE, event_world_pos.z)
		if _cloud_mi == null or not is_instance_valid(_cloud_mi):
			_rebuild_visual()


func _exit_tree() -> void:
	if _cloud_mi != null and is_instance_valid(_cloud_mi):
		if _cloud_mi.mesh != null:
			for si in _cloud_mi.mesh.get_surface_count():
				_cloud_mi.set_surface_override_material(si, null)
		_cloud_mi.mesh = null
		_cloud_mi.material_override = null
	_accent_override = null
	_cloud_mi = null
	_visual_root = null
	_active_instances = maxi(0, _active_instances - 1)
	if _active_instances == 0:
		clear_shared_cache()


func _process(delta: float) -> void:
	step_cloud(delta)


## Configure event kind, sea-level XZ coordinates, and optional instant pop-in.
func configure(kind: StringName, sea_world_pos: Vector3, instant: bool = false) -> void:
	var norm_kind := _normalize_kind(kind)
	event_kind = norm_kind
	display_label = label_for_kind(norm_kind)
	event_world_pos = Vector3(sea_world_pos.x, 0.0, sea_world_pos.z)
	_configured = true
	_phase_offset = fposmod(absf(sea_world_pos.x * 0.017 + sea_world_pos.z * 0.023), TAU)

	var sky_pos := Vector3(event_world_pos.x, CLOUD_ALTITUDE, event_world_pos.z)
	if is_inside_tree():
		global_position = sky_pos
	else:
		position = sky_pos

	if instant:
		_fade_state = FadeState.ACTIVE
		_scale_t = 1.0
	else:
		_fade_state = FadeState.FADING_IN
		_fade_duration = DEFAULT_FADE_DURATION
		_scale_t = 0.0

	_rebuild_visual()
	_apply_animation_state()


## Smoothly shrink and free this sky beacon over `duration` seconds.
func fade_out_and_free(duration: float = 1.5) -> void:
	if is_in_group(GROUP):
		remove_from_group(GROUP)
	if duration <= 0.001:
		_fade_state = FadeState.FADING_OUT
		_scale_t = 0.0
		queue_free()
		return
	_fade_state = FadeState.FADING_OUT
	_fade_duration = maxf(0.05, duration)


## Return true while this cloud beacon is fading out for teardown.
func is_fading_out() -> bool:
	return _fade_state == FadeState.FADING_OUT


## Return total sculpted triangle count for the active cloud formation.
func get_triangle_count() -> int:
	if _tri_count <= 0:
		var mesh := _get_or_build_mesh(event_kind)
		_tri_count = _count_mesh_tris(mesh)
	return _tri_count


## Advance gentle living sky billow bob, atmospheric rotation, eye pulse, and fades.
func step_cloud(delta: float) -> void:
	var dt := maxf(0.0, delta)
	_anim_time += dt

	match _fade_state:
		FadeState.FADING_IN:
			_scale_t = minf(1.0, _scale_t + dt / maxf(0.05, _fade_duration))
			if _scale_t >= 1.0:
				_scale_t = 1.0
				_fade_state = FadeState.ACTIVE
		FadeState.FADING_OUT:
			_scale_t = maxf(0.0, _scale_t - dt / maxf(0.05, _fade_duration))
			if _scale_t <= 0.0:
				_apply_animation_state()
				queue_free()
				return

	_apply_animation_state()


func _apply_animation_state() -> void:
	var eased := _scale_t * _scale_t * (3.0 - 2.0 * _scale_t)
	var eff_scale := maxf(MIN_SCALE, eased)

	if _visual_root != null and is_instance_valid(_visual_root):
		var bob_y := sin(_anim_time * 0.58 + _phase_offset) * BOB_AMPLITUDE
		var yaw_speed := 0.055 if event_kind == &"fort_siege" else (0.14 if event_kind == &"ghost_ship" else 0.085)
		var sway_z := sin(_anim_time * 0.42 + _phase_offset * 1.3) * 0.036
		var sway_x := cos(_anim_time * 0.34 + _phase_offset * 0.7) * 0.024
		_visual_root.position = Vector3(0.0, bob_y, 0.0)
		_visual_root.rotation = Vector3(sway_x, _anim_time * yaw_speed, sway_z)
		_visual_root.scale = Vector3.ONE * eff_scale

	if _accent_override != null:
		var base_e := 2.65
		var pulse_amp := 0.75
		var pulse_rate := 2.1
		if event_kind == &"ghost_ship":
			base_e = 2.35
			pulse_amp = 0.65
			pulse_rate = 1.75
		elif event_kind == &"leviathan":
			base_e = 2.85
			pulse_amp = 0.95
			pulse_rate = 2.65
		var pulse := sin(_anim_time * pulse_rate + _phase_offset)
		_accent_override.emission_energy_multiplier = maxf(0.2, (base_e + pulse * pulse_amp) * eased)


func _rebuild_visual() -> void:
	var mesh := _get_or_build_mesh(event_kind)
	_tri_count = _count_mesh_tris(mesh)

	if _visual_root == null or not is_instance_valid(_visual_root):
		_visual_root = get_node_or_null(^"CloudVisualRoot") as Node3D
		if _visual_root == null:
			_visual_root = Node3D.new()
			_visual_root.name = "CloudVisualRoot"
			add_child(_visual_root)

	if _cloud_mi == null or not is_instance_valid(_cloud_mi):
		_cloud_mi = _visual_root.get_node_or_null(^"CloudMesh") as MeshInstance3D
		if _cloud_mi == null:
			_cloud_mi = MeshInstance3D.new()
			_cloud_mi.name = "CloudMesh"
			_cloud_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_cloud_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			_cloud_mi.extra_cull_margin = 16.0
			_visual_root.add_child(_cloud_mi)

	_cloud_mi.mesh = mesh
	_cloud_mi.set_surface_override_material(0, null)

	var shared_accent := _accent_mat_cache.get(event_kind, null) as StandardMaterial3D
	if shared_accent != null:
		_accent_override = shared_accent.duplicate() as StandardMaterial3D
		if mesh.get_surface_count() > 1:
			_cloud_mi.set_surface_override_material(1, _accent_override)


static func _normalize_kind(kind: StringName) -> StringName:
	if VALID_KINDS.has(kind):
		return kind
	return &"fort_siege"


# ==============================================================================
# Shared Sculpted Sky Beacon Cache & Material Factories
# ==============================================================================

static func _get_or_build_mesh(kind: StringName) -> ArrayMesh:
	var k := _normalize_kind(kind)
	if _mesh_cache.has(k) and _mesh_cache[k] is ArrayMesh:
		return _mesh_cache[k] as ArrayMesh

	var body_mat := _get_or_build_body_mat(k)
	var accent_mat := _get_or_build_accent_mat(k)

	var body_st := SurfaceTool.new()
	body_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var accent_st := SurfaceTool.new()
	accent_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	match k:
		&"ghost_ship":
			_sculpt_ghost_fleet_cloud(body_st, accent_st)
		&"leviathan":
			_sculpt_leviathan_tempest_cloud(body_st, accent_st)
		_:
			_sculpt_fort_skull_cloud(body_st, accent_st)

	var mesh := body_st.commit()
	mesh.surface_set_material(0, body_mat)
	accent_st.commit(mesh)
	if mesh.get_surface_count() > 1:
		mesh.surface_set_material(1, accent_mat)

	_mesh_cache[k] = mesh
	return mesh


static func _get_or_build_body_mat(kind: StringName) -> StandardMaterial3D:
	if _body_mat_cache.has(kind) and _body_mat_cache[kind] is StandardMaterial3D:
		return _body_mat_cache[kind] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.96
	mat.metallic = 0.0
	mat.disable_fog = true
	# Subtle twilight/midnight self-lift so colossal silhouettes read clearly even at midnight.
	mat.emission_enabled = true
	match kind:
		&"ghost_ship":
			mat.emission = Color(0.14, 0.42, 0.46)
			mat.emission_energy_multiplier = 0.34
		&"leviathan":
			mat.emission = Color(0.24, 0.14, 0.42)
			mat.emission_energy_multiplier = 0.32
		_:
			mat.emission = Color(0.20, 0.27, 0.30)
			mat.emission_energy_multiplier = 0.30
	_body_mat_cache[kind] = mat
	return mat


static func _get_or_build_accent_mat(kind: StringName) -> StandardMaterial3D:
	if _accent_mat_cache.has(kind) and _accent_mat_cache[kind] is StandardMaterial3D:
		return _accent_mat_cache[kind] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.42
	mat.metallic = 0.0
	mat.disable_fog = true
	mat.emission_enabled = true
	match kind:
		&"ghost_ship":
			mat.emission = Color(0.24, 0.96, 0.88)
			mat.emission_energy_multiplier = 2.35
		&"leviathan":
			mat.emission = Color(0.76, 0.36, 1.00)
			mat.emission_energy_multiplier = 2.85
		_:
			mat.emission = Color(0.20, 1.00, 0.48)
			mat.emission_energy_multiplier = 2.65
	_accent_mat_cache[kind] = mat
	return mat


# ==============================================================================
# Variant 1: Fort Skull Cloud (&"fort_siege") ~64 m wide, ~1,840 tris
# ==============================================================================

static func _sculpt_fort_skull_cloud(body_st: SurfaceTool, accent_st: SurfaceTool) -> void:
	# 1. Towering billowing storm-slate cranium dome + asymmetric cumulus crown puffs.
	_add_cloud_puff(body_st, Vector3(0.0, 14.0, -2.0), Vector3(21.0, 17.5, 19.5),
		7, 12, COL_SKULL_HI, COL_SKULL_MID, COL_SKULL_DEEP, 1.1, 0.13)

	var cranium_lobes: Array[Array] = [
		[Vector3(-13.5, 20.5, -1.0), Vector3(12.5, 11.5, 12.5), 2.1],
		[Vector3(13.5, 21.0, -0.5), Vector3(12.8, 12.0, 12.0), 3.4],
		[Vector3(0.0, 26.0, -4.0), Vector3(14.5, 10.5, 13.5), 4.7],
		[Vector3(-17.5, 10.0, -5.0), Vector3(11.5, 10.0, 11.5), 5.9],
		[Vector3(17.5, 10.5, -5.0), Vector3(11.5, 10.2, 11.5), 7.2],
		[Vector3(0.0, 14.5, -17.5), Vector3(16.0, 13.0, 11.0), 8.5],
	]
	for lobe: Array in cranium_lobes:
		_add_cloud_puff(body_st, lobe[0] as Vector3, lobe[1] as Vector3,
			5, 8, COL_SKULL_HI, COL_SKULL_MID, COL_SKULL_DEEP, float(lobe[2]), 0.16)

	# 2. Heavy overhanging furrowed brow ridges (front skull visage facing +Z).
	var brows: Array[Array] = [
		[Vector3(-11.0, 10.8, 15.0), Vector3(9.0, 4.6, 7.2), 10.2],
		[Vector3(11.0, 10.8, 15.0), Vector3(9.0, 4.6, 7.2), 11.5],
		[Vector3(-4.0, 9.6, 17.5), Vector3(5.6, 3.8, 5.5), 12.7],
		[Vector3(4.0, 9.6, 17.5), Vector3(5.6, 3.8, 5.5), 13.9],
	]
	for br: Array in brows:
		_add_cloud_puff(body_st, br[0] as Vector3, br[1] as Vector3,
			4, 8, COL_SKULL_HI, COL_SKULL_MID, COL_SKULL_UNDER, float(br[2]), 0.14)

	# 3. Hollow recessed eye-socket shadow beds & sculpted cheekbones.
	_add_cloud_puff(body_st, Vector3(-9.2, 3.4, 13.5), Vector3(6.6, 5.8, 4.2),
		4, 8, COL_SKULL_DEEP, COL_SKULL_DEEP, COL_SKULL_DEEP, 15.1, 0.10)
	_add_cloud_puff(body_st, Vector3(9.2, 3.4, 13.5), Vector3(6.6, 5.8, 4.2),
		4, 8, COL_SKULL_DEEP, COL_SKULL_DEEP, COL_SKULL_DEEP, 16.4, 0.10)

	var cheeks: Array[Array] = [
		[Vector3(-17.8, -1.8, 11.0), Vector3(7.4, 6.0, 7.8), 17.6],
		[Vector3(17.8, -1.8, 11.0), Vector3(7.4, 6.0, 7.8), 18.8],
		[Vector3(-11.8, -5.2, 14.8), Vector3(6.2, 4.2, 6.4), 19.9],
		[Vector3(11.8, -5.2, 14.8), Vector3(6.2, 4.2, 6.4), 21.1],
	]
	for ch: Array in cheeks:
		_add_cloud_puff(body_st, ch[0] as Vector3, ch[1] as Vector3,
			4, 8, COL_SKULL_MID, COL_SKULL_DEEP, COL_SKULL_UNDER, float(ch[2]), 0.15)

	# 4. Sculpted nasal bridge & dark hollow nasal cleft.
	_add_cloud_puff(body_st, Vector3(0.0, 3.8, 17.6), Vector3(3.4, 4.2, 4.2),
		4, 6, COL_SKULL_MID, COL_SKULL_DEEP, COL_SKULL_DEEP, 22.3, 0.12)
	_add_cloud_puff(body_st, Vector3(0.0, -2.0, 15.4), Vector3(3.6, 4.4, 3.6),
		4, 6, COL_SKULL_DEEP, COL_SKULL_DEEP, COL_SKULL_DEEP, 23.5, 0.08)

	# 5. Upper jaw arch & five sculpted cloud teeth pillars.
	var teeth_x: Array[float] = [-9.2, -4.6, 0.0, 4.6, 9.2]
	for ti in teeth_x.size():
		var tx := teeth_x[ti]
		var ty := -11.5 - (1.4 if ti == 2 else (0.7 if ti == 1 or ti == 3 else 0.0))
		var tz := 15.0 - absf(tx) * 0.22
		_add_cloud_puff(body_st, Vector3(tx, ty, tz), Vector3(2.3, 4.4, 3.2),
			4, 6, COL_SKULL_HI, COL_SKULL_MID, COL_SKULL_UNDER, 25.0 + float(ti) * 1.7, 0.11)

	# 6. Broad billowing storm-collar cloud bank framing the skull (~64 m total span).
	var collar: Array[Array] = [
		[Vector3(-25.5, -7.5, -2.0), Vector3(11.5, 7.2, 11.0), 31.1],
		[Vector3(25.5, -7.5, -2.0), Vector3(11.5, 7.2, 11.0), 32.4],
		[Vector3(-18.0, -14.5, 4.5), Vector3(10.5, 6.5, 9.5), 33.7],
		[Vector3(18.0, -14.5, 4.5), Vector3(10.5, 6.5, 9.5), 34.9],
		[Vector3(0.0, -17.0, -8.0), Vector3(19.5, 7.8, 13.5), 36.2],
		[Vector3(0.0, -12.0, -19.5), Vector3(17.0, 8.5, 10.5), 37.5],
	]
	for cl: Array in collar:
		_add_cloud_puff(body_st, cl[0] as Vector3, cl[1] as Vector3,
			4, 8, COL_SKULL_MID, COL_SKULL_DEEP, COL_SKULL_DEEP, float(cl[2]), 0.18)

	# 7. Accent Surface: Twin blazing emerald-green glowing eye sockets & flame wisps!
	_add_cloud_puff(accent_st, Vector3(-9.2, 3.2, 17.8), Vector3(4.5, 3.8, 3.8),
		5, 10, COL_FORT_EYE_HI, COL_FORT_EYE_HI, COL_FORT_EYE_LO, 41.0, 0.10)
	_add_cloud_puff(accent_st, Vector3(9.2, 3.2, 17.8), Vector3(4.5, 3.8, 3.8),
		5, 10, COL_FORT_EYE_HI, COL_FORT_EYE_HI, COL_FORT_EYE_LO, 42.3, 0.10)

	# Sweeping twin emerald spectral wisps trailing upward from the blazing eye sockets.
	for side_i in 2:
		var sx := -1.0 if side_i == 0 else 1.0
		var wisp_pts: Array[Vector3] = [
			Vector3(sx * 11.5, 3.6, 18.2),
			Vector3(sx * 16.5, 7.2, 17.5),
			Vector3(sx * 20.5, 12.6, 14.5),
			Vector3(sx * 22.8, 18.5, 10.0),
			Vector3(sx * 23.0, 23.8, 5.5),
		]
		var wisp_r: Array[float] = [2.4, 2.0, 1.5, 0.95, 0.35]
		_add_cloud_ribbon_tube(accent_st, wisp_pts, wisp_r, 6,
			COL_FORT_EYE_HI, COL_FORT_EYE_LO, 45.0 + float(side_i) * 3.1)

	# Subtle emerald fissure glow inside the jaw/nasal shadow so night beacons gleam.
	_add_cloud_puff(accent_st, Vector3(0.0, -7.8, 14.5), Vector3(5.8, 1.8, 2.6),
		4, 6, COL_FORT_EYE_HI, COL_FORT_EYE_LO, COL_FORT_EYE_LO, 49.0, 0.12)


# ==============================================================================
# Variant 2: Ghost Fleet Cloud (&"ghost_ship") ~68 m wide, ~1,830 tris
# ==============================================================================

static func _sculpt_ghost_fleet_cloud(body_st: SurfaceTool, accent_st: SurfaceTool) -> void:
	# 1. Swirling spectral teal-cyan funnel vortex rising beneath the ghost galleon.
	_add_cloud_puff(body_st, Vector3(0.0, -15.5, 0.0), Vector3(13.5, 11.0, 13.5),
		5, 10, COL_GHOST_MID, COL_GHOST_DEEP, COL_GHOST_DEEP, 51.0, 0.16)

	for arm in 4:
		var base_ang := float(arm) * (TAU * 0.25)
		var pts: Array[Vector3] = []
		var rads: Array[float] = []
		var steps := 10
		for si in steps:
			var t := float(si) / float(steps - 1)
			var ang := base_ang + t * 2.35
			var swirl_r := lerpf(5.0, 27.0, pow(t, 0.85))
			var y := lerpf(-25.5, -2.5, t)
			pts.append(Vector3(cos(ang) * swirl_r, y, sin(ang) * swirl_r * 0.84))
			rads.append(lerpf(2.2, 5.2, sin(t * PI * 0.82)))
		_add_cloud_ribbon_tube(body_st, pts, rads, 6,
			COL_GHOST_DEEP, COL_GHOST_MID, 54.0 + float(arm) * 2.7)

	# 2. Billowing ghostly galleon hull silhouette (high stern castle -X to prow bowsprit +X).
	var hull_puffs: Array[Array] = [
		[Vector3(-23.0, 7.5, 0.0), Vector3(10.5, 9.2, 9.5), 61.1],   # High stern castle
		[Vector3(-14.5, 3.0, 0.5), Vector3(10.2, 7.5, 10.2), 62.3],  # Quarterdeck hull
		[Vector3(-4.0, 0.5, -0.4), Vector3(11.5, 6.8, 10.6), 63.5],  # Midship waist
		[Vector3(7.5, 1.8, 0.4), Vector3(11.0, 7.0, 10.2), 64.7],    # Foredeck hull
		[Vector3(18.5, 4.8, -0.2), Vector3(9.8, 6.5, 8.6), 65.9],    # Forecastle prow
		[Vector3(28.5, 8.8, 0.0), Vector3(8.5, 3.6, 4.6), 67.1],     # Bowsprit cloud lance
		[Vector3(-27.5, 13.5, 0.0), Vector3(7.2, 6.2, 7.2), 68.3],   # Taffrail crest
	]
	for hp: Array in hull_puffs:
		_add_cloud_puff(body_st, hp[0] as Vector3, hp[1] as Vector3,
			5, 8, COL_GHOST_HI, COL_GHOST_MID, COL_GHOST_DEEP, float(hp[2]), 0.16)

	# 3. Towering double-masted billowing ghostly cloud sails (mainmast & foremast).
	var sail_puffs: Array[Array] = [
		# Mainmast towering billowing canvas bank
		[Vector3(-4.5, 14.5, 2.2), Vector3(10.8, 8.5, 7.4), 71.0],
		[Vector3(-3.5, 23.5, 3.2), Vector3(9.6, 7.6, 6.6), 72.2],
		[Vector3(-4.5, 30.5, 2.0), Vector3(7.4, 5.8, 5.4), 73.4],
		[Vector3(-12.0, 16.5, 1.5), Vector3(6.8, 7.2, 5.8), 74.6],
		# Foremast billowing foresail & topsail bank
		[Vector3(11.5, 13.5, 2.4), Vector3(8.8, 7.2, 6.4), 75.8],
		[Vector3(12.0, 21.5, 3.0), Vector3(7.6, 6.2, 5.6), 77.0],
		[Vector3(11.5, 27.2, 1.8), Vector3(5.8, 4.6, 4.4), 78.2],
	]
	for sp: Array in sail_puffs:
		_add_cloud_puff(body_st, sp[0] as Vector3, sp[1] as Vector3,
			5, 8, COL_GHOST_HI, COL_GHOST_MID, COL_GHOST_DEEP, float(sp[2]), 0.15)

	# 4. Accent Surface: Flowing glowing ectoplasm pennants, stern lantern & sea-fire vortex arcs!
	var main_pennant: Array[Vector3] = [
		Vector3(-4.5, 35.0, 1.2),
		Vector3(-11.5, 36.2, 0.2),
		Vector3(-19.0, 34.4, -1.2),
		Vector3(-26.0, 35.6, -2.0),
		Vector3(-32.5, 33.4, -2.8),
		Vector3(-37.5, 34.2, -3.2),
	]
	_add_cloud_ribbon_tube(accent_st, main_pennant, [2.1, 1.8, 1.45, 1.1, 0.72, 0.30], 6,
		COL_GHOST_GLOW_HI, COL_GHOST_GLOW_LO, 81.0)

	var fore_pennant: Array[Vector3] = [
		Vector3(11.5, 31.2, 1.2),
		Vector3(5.5, 32.0, 0.5),
		Vector3(-1.2, 30.8, -0.4),
		Vector3(-7.8, 31.6, -1.2),
		Vector3(-13.5, 30.0, -1.8),
	]
	_add_cloud_ribbon_tube(accent_st, fore_pennant, [1.75, 1.45, 1.15, 0.80, 0.28], 6,
		COL_GHOST_GLOW_HI, COL_GHOST_GLOW_LO, 83.4)

	# Glowing spectral stern-castle lantern beacon puff.
	_add_cloud_puff(accent_st, Vector3(-28.5, 12.2, 0.0), Vector3(4.2, 4.8, 4.2),
		4, 8, COL_GHOST_GLOW_HI, COL_GHOST_GLOW_HI, COL_GHOST_GLOW_LO, 86.0, 0.12)

	# Three swirling ectoplasm sea-fire ribbons inside the spectral funnel vortex.
	for wi in 3:
		var ang0 := float(wi) * (TAU / 3.0) + 0.45
		var v_pts: Array[Vector3] = []
		var v_rads: Array[float] = []
		for sj in 6:
			var t := float(sj) / 5.0
			var a := ang0 + t * 2.05
			var r := lerpf(6.5, 22.5, t)
			v_pts.append(Vector3(cos(a) * r, lerpf(-22.0, -4.0, t), sin(a) * r * 0.85))
			v_rads.append(lerpf(1.25, 0.55, absf(t - 0.5) * 1.6))
		_add_cloud_ribbon_tube(accent_st, v_pts, v_rads, 6,
			COL_GHOST_GLOW_LO, COL_GHOST_GLOW_HI, 89.0 + float(wi) * 2.3)


# ==============================================================================
# Variant 3: Abyssal Tempest Cloud (&"leviathan") ~72 m wide, ~1,910 tris
# ==============================================================================

static func _sculpt_leviathan_tempest_cloud(body_st: SurfaceTool, accent_st: SurfaceTool) -> void:
	# 1. Brooding indigo-violet anvil thunderhead crown & dark storm underbelly.
	_add_cloud_puff(body_st, Vector3(0.0, 17.5, 0.0), Vector3(26.0, 11.5, 26.0),
		6, 12, COL_LEV_HI, COL_LEV_MID, COL_LEV_DEEP, 91.0, 0.14)

	for ri in 7:
		var a := float(ri) / 7.0 * TAU + 0.25
		var dist := 22.0 + 3.0 * sin(float(ri) * 2.1)
		var y := 14.0 + 3.2 * cos(float(ri) * 1.7)
		_add_cloud_puff(body_st, Vector3(cos(a) * dist, y, sin(a) * dist),
			Vector3(13.5, 8.8, 13.5), 5, 8, COL_LEV_HI, COL_LEV_MID, COL_LEV_DEEP,
			93.0 + float(ri) * 1.9, 0.17)

	# Heavy brooding dark storm-bell underbelly surrounding the storm eye.
	for bi in 3:
		var a := float(bi) * (TAU / 3.0) + 0.5
		_add_cloud_puff(body_st, Vector3(cos(a) * 12.5, 2.5, sin(a) * 12.5),
			Vector3(12.0, 7.5, 12.0), 4, 8, COL_LEV_MID, COL_LEV_DEEP, COL_LEV_DEEP,
			105.0 + float(bi) * 2.2, 0.15)

	# 2. Five colossal curling sculpted tentacle cloud arcs (~72 m diameter)!
	for ti in 5:
		var base_ang := float(ti) * (TAU / 5.0)
		var curl_dir := 1.0 if (ti % 2 == 0) else -1.0
		var t_pts: Array[Vector3] = []
		var t_rads: Array[float] = []
		var steps := 11
		for si in steps:
			var u := float(si) / float(steps - 1)
			# Sweep down from storm belly, flare wide to ~36 m, then hook menacingly upward & inward!
			var radial := 10.5 + 26.0 * sin(u * PI * 0.78) + 4.0 * u * cos(u * PI * 1.2)
			var swirl := base_ang + curl_dir * (0.48 * u + 0.36 * pow(u, 2.2))
			var y := 2.0 - 17.5 * sin(u * PI * 0.72) + 21.0 * pow(u, 2.4)
			t_pts.append(Vector3(cos(swirl) * radial, y, sin(swirl) * radial))
			t_rads.append(lerpf(5.8, 0.95, pow(u, 0.85)))
		_add_cloud_ribbon_tube(body_st, t_pts, t_rads, 7,
			COL_LEV_DEEP, COL_LEV_HI, 112.0 + float(ti) * 3.3)

	# 3. Accent Surface: Pulsing electric-violet storm eye, halo ring & 5 crackling veins!
	_add_cloud_puff(accent_st, Vector3(0.0, -2.5, 0.0), Vector3(7.6, 5.2, 7.6),
		5, 10, COL_LEV_EYE_HI, COL_LEV_EYE_HI, COL_LEV_EYE_LO, 130.0, 0.11)

	# Swirling electric-violet halo ring encircling the central storm eye.
	var halo_pts: Array[Vector3] = []
	var halo_rads: Array[float] = []
	var halo_steps := 10
	for hi in halo_steps:
		var ha := float(hi) / float(halo_steps - 1) * TAU * 0.92
		var hr := 14.5 + 1.4 * sin(ha * 3.0)
		halo_pts.append(Vector3(cos(ha) * hr, -3.5 + 1.2 * cos(ha * 2.0), sin(ha) * hr))
		halo_rads.append(1.55)
	_add_cloud_ribbon_tube(accent_st, halo_pts, halo_rads, 6,
		COL_LEV_EYE_LO, COL_LEV_EYE_HI, 134.0)

	# Five jagged electric-violet lightning veins running along the tentacle arcs.
	for li in 5:
		var lang := float(li) * (TAU / 5.0)
		var l_pts: Array[Vector3] = []
		var l_rads: Array[float] = []
		for sj in 5:
			var u := float(sj) / 4.0
			var zig := 1.6 if (sj % 2 == 1) else -1.4
			var r := lerpf(9.0, 31.5, u)
			var a := lang + 0.08 * zig * u
			var y := lerpf(-2.0, -10.5, sin(u * PI * 0.8)) + 8.0 * pow(u, 2.2)
			l_pts.append(Vector3(cos(a) * r, y, sin(a) * r))
			l_rads.append(lerpf(1.25, 0.42, u))
		_add_cloud_ribbon_tube(accent_st, l_pts, l_rads, 5,
			COL_LEV_EYE_HI, COL_LEV_EYE_LO, 140.0 + float(li) * 2.9)


# ==============================================================================
# Low-Level Sculpted Flat-Faceted SurfaceTool Primitives (Zero PrimitiveMesh)
# ==============================================================================

static func _add_cloud_puff(
	st: SurfaceTool,
	center: Vector3,
	radii: Vector3,
	rings: int,
	segs: int,
	col_top: Color,
	col_mid: Color,
	col_bot: Color,
	puff_seed: float,
	crinkle: float = 0.14
) -> void:
	var r_count := maxi(3, rings)
	var s_count := maxi(5, segs)

	var top_bump := clampf(1.0 + crinkle * 0.55 * sin(puff_seed * 1.7), 0.78, 1.25)
	var bot_bump := clampf(1.0 + crinkle * 0.55 * cos(puff_seed * 2.1), 0.78, 1.25)
	var top_pt := center + Vector3(0.0, radii.y * top_bump, 0.0)
	var bot_pt := center + Vector3(0.0, -radii.y * bot_bump, 0.0)

	var ring_pts: Array[Array] = []
	var ring_cols: Array[Array] = []
	for ri in range(1, r_count):
		var theta := float(ri) / float(r_count) * PI
		var sin_t := sin(theta)
		var cos_t := cos(theta)
		var pts: Array[Vector3] = []
		var cols: Array[Color] = []
		for si in s_count:
			var phi := float(si) / float(s_count) * TAU
			var ux := sin_t * cos(phi)
			var uy := cos_t
			var uz := sin_t * sin(phi)
			var wave := sin(ux * 3.7 + puff_seed) * cos(uy * 3.1 - puff_seed * 0.7) \
				+ 0.55 * sin(uz * 4.3 + puff_seed * 1.3)
			var bump := clampf(1.0 + crinkle * wave, 0.72, 1.32)
			pts.append(center + Vector3(ux * radii.x, uy * radii.y, uz * radii.z) * bump)
			var h := clampf((uy + 1.0) * 0.5, 0.0, 1.0)
			var c := col_bot.lerp(col_mid, clampf(h * 2.0, 0.0, 1.0)) if h < 0.5 \
				else col_mid.lerp(col_top, clampf((h - 0.5) * 2.0, 0.0, 1.0))
			var shade_var := 0.92 + 0.14 * clampf(0.5 + 0.5 * sin(phi * 2.0 + float(ri) * 1.3 + puff_seed), 0.0, 1.0)
			cols.append(Color(
				clampf(c.r * shade_var, 0.0, 1.0),
				clampf(c.g * shade_var, 0.0, 1.0),
				clampf(c.b * shade_var, 0.0, 1.0),
				1.0
			))
		ring_pts.append(pts)
		ring_cols.append(cols)

	# Top cap fan.
	var first_pts: Array = ring_pts[0]
	var first_cols: Array = ring_cols[0]
	for si in s_count:
		var nsi := (si + 1) % s_count
		_emit_outward_tri(st, top_pt, first_pts[si] as Vector3, first_pts[nsi] as Vector3,
			center, col_top, first_cols[si] as Color, first_cols[nsi] as Color)

	# Middle latitude bands.
	for bi in range(ring_pts.size() - 1):
		var a_pts: Array = ring_pts[bi]
		var b_pts: Array = ring_pts[bi + 1]
		var a_cols: Array = ring_cols[bi]
		var b_cols: Array = ring_cols[bi + 1]
		for si in s_count:
			var nsi := (si + 1) % s_count
			_emit_outward_quad(
				st,
				a_pts[si] as Vector3, b_pts[si] as Vector3,
				b_pts[nsi] as Vector3, a_pts[nsi] as Vector3,
				center,
				a_cols[si] as Color, b_cols[si] as Color,
				b_cols[nsi] as Color, a_cols[nsi] as Color
			)

	# Bottom cap fan.
	var last_pts: Array = ring_pts[ring_pts.size() - 1]
	var last_cols: Array = ring_cols[ring_cols.size() - 1]
	for si in s_count:
		var nsi := (si + 1) % s_count
		_emit_outward_tri(st, bot_pt, last_pts[nsi] as Vector3, last_pts[si] as Vector3,
			center, col_bot, last_cols[nsi] as Color, last_cols[si] as Color)


static func _add_cloud_ribbon_tube(
	st: SurfaceTool,
	points: Array[Vector3],
	radii: Array[float],
	segs: int,
	col_start: Color,
	col_end: Color,
	tube_seed: float
) -> void:
	var n_pts := points.size()
	if n_pts < 2 or radii.size() < n_pts:
		return
	var s_count := maxi(4, segs)

	var rings_v: Array[Array] = []
	var rings_c: Array[Color] = []
	var prev_right := Vector3.ZERO

	for i in n_pts:
		var p := points[i]
		var tangent := Vector3.UP
		if i == 0:
			tangent = (points[1] - points[0]).normalized()
		elif i == n_pts - 1:
			tangent = (points[n_pts - 1] - points[n_pts - 2]).normalized()
		else:
			tangent = (points[i + 1] - points[i - 1]).normalized()
		if tangent.length_squared() < 1e-8:
			tangent = Vector3.UP

		var right: Vector3
		if prev_right.length_squared() > 0.25:
			var proj := prev_right - tangent * prev_right.dot(tangent)
			if proj.length_squared() > 1e-6:
				right = proj.normalized()
			else:
				var ref := Vector3.RIGHT if absf(tangent.y) > 0.9 else Vector3.UP
				right = ref.cross(tangent).normalized()
		else:
			var ref := Vector3.RIGHT if absf(tangent.y) > 0.9 else Vector3.UP
			right = ref.cross(tangent).normalized()
		prev_right = right
		var up_v := tangent.cross(right).normalized()

		var rad := maxf(0.22, radii[i])
		var ring: Array[Vector3] = []
		for si in s_count:
			var phi := float(si) / float(s_count) * TAU
			var cr := 1.0 + 0.14 * sin(phi * 3.0 + float(i) * 1.15 + tube_seed)
			var offset := (right * cos(phi) + up_v * sin(phi)) * (rad * cr)
			ring.append(p + offset)
		rings_v.append(ring)
		var u := float(i) / float(n_pts - 1)
		rings_c.append(col_start.lerp(col_end, u))

	# Start cap.
	var tan0 := (points[1] - points[0]).normalized()
	var cap0 := points[0] - tan0 * (maxf(0.22, radii[0]) * 0.55)
	var r0: Array = rings_v[0]
	var c0: Color = rings_c[0]
	for si in s_count:
		var nsi := (si + 1) % s_count
		_emit_outward_tri(st, cap0, r0[nsi] as Vector3, r0[si] as Vector3, points[0], c0, c0, c0)

	# Segment quads.
	for i in range(n_pts - 1):
		var ra: Array = rings_v[i]
		var rb: Array = rings_v[i + 1]
		var ca: Color = rings_c[i]
		var cb: Color = rings_c[i + 1]
		var seg_mid := 0.5 * (points[i] + points[i + 1])
		for si in s_count:
			var nsi := (si + 1) % s_count
			_emit_outward_quad(
				st,
				ra[si] as Vector3, rb[si] as Vector3,
				rb[nsi] as Vector3, ra[nsi] as Vector3,
				seg_mid, ca, cb, cb, ca
			)

	# Tip cap.
	var tan_end := (points[n_pts - 1] - points[n_pts - 2]).normalized()
	var tip_pt := points[n_pts - 1] + tan_end * (maxf(0.22, radii[n_pts - 1]) * 0.85)
	var r_last: Array = rings_v[n_pts - 1]
	var c_last: Color = rings_c[n_pts - 1]
	for si in s_count:
		var nsi := (si + 1) % s_count
		_emit_outward_tri(st, tip_pt, r_last[si] as Vector3, r_last[nsi] as Vector3,
			points[n_pts - 1], c_last, c_last, c_last)


static func _emit_outward_quad(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	ref_center: Vector3,
	ca: Color,
	cb: Color,
	cc: Color,
	cd: Color
) -> void:
	_emit_outward_tri(st, a, b, c, ref_center, ca, cb, cc)
	_emit_outward_tri(st, a, c, d, ref_center, ca, cc, cd)


static func _emit_outward_tri(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	ref_center: Vector3,
	ca: Color,
	cb: Color,
	cc: Color
) -> void:
	var centroid := (a + b + c) / 3.0
	_emit_dir_tri(st, a, b, c, centroid - ref_center, ca, cb, cc)


static func _emit_dir_tri(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	expected_normal: Vector3,
	ca: Color,
	cb: Color,
	cc: Color
) -> void:
	var n := (c - a).cross(b - a)
	var len_sq := n.length_squared()
	if len_sq < 1e-10:
		return
	if n.dot(expected_normal) < 0.0:
		var tv := b
		b = c
		c = tv
		var tc := cb
		cb = cc
		cc = tc
		n = -n
	var unit_n := n / sqrt(len_sq)
	st.set_smooth_group(-1)
	st.set_normal(unit_n)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_smooth_group(-1)
	st.set_normal(unit_n)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_smooth_group(-1)
	st.set_normal(unit_n)
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
