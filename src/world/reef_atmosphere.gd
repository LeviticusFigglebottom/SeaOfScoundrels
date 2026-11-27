class_name ReefAtmosphere
extends Node3D
## Underwater reef atmosphere & micro-ecosystem companion for `CoralReef` islands.
##
## Attaches cleanly as a sibling of `CoralReef` on an `Island` (preserving all
## `CoralReef` 3-MultiMesh and zero-MeshInstance3D invariants) and elevates
## underwater diving sanctuaries with strictly 3 GPU-batched procedural children:
##   1. `UnderwaterSunShafts` (`MeshInstance3D`)     — 10..14 slanted volumetric god-rays
##   2. `SeaFanClamBeds`      (`MultiMeshInstance3D`) — 18..26 sculpted Giant Pearl-Clams
##                                                      & pleated lacy Sea-Fan corals
##   3. `ReefBubblePlumes`    (`MultiMeshInstance3D`) — 36..48 rising 12-tri faceted
##                                                      micro-bubbles from 4..6 seabed vents
##
## Zero raw PrimitiveMeshes, zero extra VRAM textures, distance-gated <= 95 m bubble
## updates (0.00 ms far CPU), dynamic Weather sun-shaft & nocturnal coral bioluminescence,
## and ref-counted zero-leak static cache teardown.

const GROUP := &"reef_atmosphere"

const SUN_SHAFT_TOP_Y := -0.06
const SUN_SHAFT_MIN_BOT_Y := -9.5
const SUN_SHAFT_MAX_BOT_Y := -6.5
const SUN_SHAFT_VIS_MIN := 165.0
const SUN_SHAFT_VIS_OFFSET := 115.0

const SEAFAN_MIN_SURFACE_Y := -8.2
const SEAFAN_MAX_SURFACE_Y := -1.15
const SEAFAN_CLAM_MESH_HEIGHT := 1.12

const BUBBLE_TOP_Y := -0.22
const BUBBLE_VISIBILITY_RANGE_END := 115.0
const BUBBLE_CULL_DIST := 95.0
const BUBBLE_CULL_DIST_SQ := BUBBLE_CULL_DIST * BUBBLE_CULL_DIST

const LIGHTING_UPDATE_INTERVAL := 0.12
const NOCTURNAL_SEAFAN_MAX_ENERGY := 0.68

# Sun-shaft palette across tropical noon, golden twilight, moonlit night, and heavy storms.
const COL_SHAFT_NOON := Color(0.42, 0.92, 0.90, 1.0)
const COL_SHAFT_GOLDEN := Color(0.96, 0.76, 0.44, 1.0)
const COL_SHAFT_MOON := Color(0.24, 0.62, 0.86, 1.0)
const COL_SHAFT_STORM := Color(0.30, 0.55, 0.62, 1.0)

# Luminous high-value sRGB reef tints for SeaFanClam MultiMesh variation
# (preserves pearl cream, turquoise mantle, and vibrant coral frond hues without muddying).
const SEAFAN_CLAM_PALETTE: Array[Color] = [
	Color(1.00, 0.88, 0.84, 1.0),  # Sunlit coral-cream
	Color(0.86, 0.98, 0.96, 1.0),  # Luminous aqua-pearl
	Color(1.00, 0.93, 0.80, 1.0),  # Golden lagoon opal
	Color(0.96, 0.86, 0.98, 1.0),  # Reef orchid-rose
	Color(0.90, 0.98, 0.88, 1.0),  # Jade-lagoon shimmer
]

const BUBBLE_PALETTE: Array[Color] = [
	Color(0.90, 0.99, 1.00, 1.0),
	Color(0.80, 0.96, 1.00, 1.0),
	Color(0.86, 1.00, 0.98, 1.0),
]

static var _active_count: int = 0
static var _sun_shaft_shader: Shader = null
static var _seafan_clam_mesh: ArrayMesh = null
static var _seafan_clam_material: StandardMaterial3D = null
static var _bubble_mesh: ArrayMesh = null
static var _bubble_material: StandardMaterial3D = null

var _sun_shafts_mi: MeshInstance3D = null
var _sun_shaft_mat: ShaderMaterial = null
var _seafan_mmi: MultiMeshInstance3D = null
var _bubbles_mmi: MultiMeshInstance3D = null

var _sun_shaft_count: int = 0
var _sun_shaft_intensity: float = 0.38
var _sun_shaft_color: Color = COL_SHAFT_NOON
var _biolum_strength: float = 0.0
var _seafan_count: int = 0
var _bubble_count: int = 0

var _placed_seafan_transforms: Array[Transform3D] = []
var _vent_positions: Array[Vector3] = []
var _bubble_outer_radius: float = 0.0

# Flat packed bubble simulation arrays (zero per-frame heap allocations).
var _bubble_vent_x: PackedFloat32Array = PackedFloat32Array()
var _bubble_vent_z: PackedFloat32Array = PackedFloat32Array()
var _bubble_y_start: PackedFloat32Array = PackedFloat32Array()
var _bubble_y: PackedFloat32Array = PackedFloat32Array()
var _bubble_speed: PackedFloat32Array = PackedFloat32Array()
var _bubble_phase: PackedFloat32Array = PackedFloat32Array()
var _bubble_helix_r: PackedFloat32Array = PackedFloat32Array()
var _bubble_helix_freq: PackedFloat32Array = PackedFloat32Array()
var _bubble_scale: PackedFloat32Array = PackedFloat32Array()

var _bubble_clock: float = 0.0
var _lighting_accum: float = LIGHTING_UPDATE_INTERVAL


func _enter_tree() -> void:
	add_to_group(GROUP)
	_active_count += 1


func _exit_tree() -> void:
	_release_refs()
	_active_count = maxi(0, _active_count - 1)
	if _active_count == 0:
		clear_shared_cache()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_release_refs()


func _release_refs() -> void:
	if _sun_shafts_mi != null and is_instance_valid(_sun_shafts_mi):
		_sun_shafts_mi.material_override = null
		_sun_shafts_mi.mesh = null
	if _sun_shaft_mat != null:
		_sun_shaft_mat.shader = null
		_sun_shaft_mat = null
	if _seafan_mmi != null and is_instance_valid(_seafan_mmi):
		_seafan_mmi.material_override = null
		_seafan_mmi.multimesh = null
	if _bubbles_mmi != null and is_instance_valid(_bubbles_mmi):
		_bubbles_mmi.material_override = null
		_bubbles_mmi.multimesh = null
	_sun_shafts_mi = null
	_seafan_mmi = null
	_bubbles_mmi = null
	_placed_seafan_transforms.clear()
	_vent_positions.clear()


## Release statically cached shared procedural meshes, shaders, and materials cleanly.
static func clear_shared_cache() -> void:
	_sun_shaft_shader = null
	_seafan_clam_mesh = null
	_seafan_clam_material = null
	_bubble_mesh = null
	_bubble_material = null


func _process(delta: float) -> void:
	_lighting_accum += delta
	if _lighting_accum >= LIGHTING_UPDATE_INTERVAL:
		_lighting_accum = 0.0
		_update_lighting()
	if _bubble_count > 0 and _is_camera_within_bubble_range():
		_step_bubbles(delta)


## Deterministically populate volumetric underwater sun-shafts, sculpted Giant Pearl-Clams
## with pleated coral Sea-Fans, and rising micro-bubble plumes around `island`'s shallow reefs.
static func populate_for_island(island: Island, bed_centers: Array[Vector2],
		rng_seed: int = 0) -> ReefAtmosphere:
	var atmo := ReefAtmosphere.new()
	atmo.name = "ReefAtmosphere"
	if island == null:
		return atmo

	var rng := RandomNumberGenerator.new()
	var seed_val := rng_seed
	if seed_val == 0:
		seed_val = island.island_id.hash() ^ 0x5A17
	if seed_val == 0:
		seed_val = 0x4EEF5A17
	rng.seed = seed_val

	var r_min := maxf(4.0, island.island_radius * CoralReef.MIN_RADIUS_FACTOR)
	var r_max := maxf(r_min + 4.0, island.seabed_radius * CoralReef.MAX_SEABED_FACTOR)
	var mooring_xz := Vector2(island.mooring_transform.origin.x, island.mooring_transform.origin.z)
	var has_pier := island is Outpost
	var pier_a := Vector2.ZERO
	var pier_b := Vector2.ZERO
	if has_pier:
		var op := island as Outpost
		pier_a = Vector2(op.dock_local_transform.origin.x, op.dock_local_transform.origin.z)
		pier_b = Vector2(op.dock_pier_end_local.x, op.dock_pier_end_local.z)

	# Build a local working list of reef bed centers (discovering shallow shelf anchors if empty).
	var anchors: Array[Vector2] = []
	for bc in bed_centers:
		anchors.append(bc)
	if anchors.is_empty():
		for _attempt in 140:
			if anchors.size() >= 8:
				break
			var pt := _sample_annulus_xz(rng, r_min, r_max)
			if not _is_valid_atmosphere_spot(island, pt, mooring_xz, has_pier, pier_a, pier_b):
				continue
			if _far_from_xz(pt, anchors, 12.0):
				anchors.append(pt)

	# 1. UnderwaterSunShafts (10..14 angled volumetric god-rays in 1 batched ArrayMesh).
	var target_shafts := rng.randi_range(11, 14)
	var shaft_specs: Array[Dictionary] = []
	var shaft_xz: Array[Vector2] = []
	var slant_az := rng.randf_range(0.0, TAU)
	var sun_slant_dir := Vector2(cos(slant_az), sin(slant_az))

	# Prioritize reef bed centers first so hero coral beds receive crisp sunlit god-rays.
	for bi in anchors.size():
		if shaft_specs.size() >= target_shafts:
			break
		var base_c := anchors[bi]
		var jitter_ang := rng.randf() * TAU
		var jitter_d := rng.randf_range(0.5, 2.4)
		var pt := base_c + Vector2(cos(jitter_ang), sin(jitter_ang)) * jitter_d
		if not _is_valid_atmosphere_spot(island, pt, mooring_xz, has_pier, pier_a, pier_b):
			pt = base_c
		if not _far_from_xz(pt, shaft_xz, 3.8):
			continue
		shaft_specs.append(_make_shaft_spec(rng, island, pt, sun_slant_dir))
		shaft_xz.append(pt)

	# Add companion shafts clustering softly around the primary reef beds & shallow shelf.
	for _attempt in 180:
		if shaft_specs.size() >= target_shafts:
			break
		var pt := _sample_reef_candidate(rng, anchors, r_min, r_max, 0.72, 3.2, 10.5)
		if not _is_valid_atmosphere_spot(island, pt, mooring_xz, has_pier, pier_a, pier_b):
			continue
		if not _far_from_xz(pt, shaft_xz, 4.5):
			continue
		shaft_specs.append(_make_shaft_spec(rng, island, pt, sun_slant_dir))
		shaft_xz.append(pt)

	var shaft_mat := ShaderMaterial.new()
	shaft_mat.shader = _get_sun_shaft_shader()
	shaft_mat.set_shader_parameter(&"u_intensity", 0.38)
	shaft_mat.set_shader_parameter(&"u_color", COL_SHAFT_NOON)

	var shafts_mi := MeshInstance3D.new()
	shafts_mi.name = "UnderwaterSunShafts"
	shafts_mi.mesh = _build_sun_shafts_mesh(shaft_specs)
	shafts_mi.material_override = shaft_mat
	shafts_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shafts_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	shafts_mi.visibility_range_end = maxf(SUN_SHAFT_VIS_MIN, island.seabed_radius + SUN_SHAFT_VIS_OFFSET)
	shafts_mi.visibility_range_end_margin = CoralReef.VISIBILITY_RANGE_MARGIN
	shafts_mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	shafts_mi.extra_cull_margin = 2.0

	atmo._sun_shaft_mat = shaft_mat
	atmo._sun_shafts_mi = shafts_mi
	atmo._sun_shaft_count = shaft_specs.size()
	atmo.add_child(shafts_mi)

	# 2. SeaFanClamBeds (24..32 sculpted Giant Pearl-Clams & pleated coral Sea-Fans in 1 MultiMesh).
	var target_seafans := rng.randi_range(24, 32)
	var seafan_xf: Array[Transform3D] = []
	var seafan_col: Array[Color] = []
	var seafan_xz: Array[Vector2] = []

	# Ensure the primary hero reef bed hosts a sculpted Giant Pearl-Clam & Sea-Fan pair right beside its sun-shaft.
	if not anchors.is_empty():
		var hero_c := anchors[0]
		for _hi in 28:
			if seafan_xf.size() >= 2:
				break
			var hang := rng.randf() * TAU
			var hdist := rng.randf_range(1.65, 3.25)
			var hpt := hero_c + Vector2(cos(hang), sin(hang)) * hdist
			if not _is_valid_atmosphere_spot(island, hpt, mooring_xz, has_pier, pier_a, pier_b):
				continue
			if not _far_from_xz(hpt, seafan_xz, 1.85):
				continue
			var hh := island.surface_height(hpt.x, hpt.y)
			var hroot_y := hh - CoralReef.ROOT_EMBED_Y
			if hroot_y > CoralReef.MAX_ROOT_Y:
				continue
			var hn := island.surface_normal(hpt.x, hpt.y)
			var hbs := rng.randf_range(1.00, 1.26)
			var hmax := maxf(0.45, -hh - 0.28)
			var hsy := minf(hbs, hmax / SEAFAN_CLAM_MESH_HEIGHT)
			var hsx := minf(hbs, hsy * 1.24)
			var hxf := _grounded_transform(
				Vector3(hpt.x, hroot_y, hpt.y), hn, 0.35, rng.randf() * TAU, Vector3(hsx, hsy, hsx)
			)
			seafan_xf.append(hxf)
			seafan_col.append(_pick_jittered_color(rng, SEAFAN_CLAM_PALETTE))
			seafan_xz.append(hpt)

	for pass_idx in 2:
		var min_sep := 2.2 if pass_idx == 0 else 1.25
		var attempts := target_seafans * 28 + 160
		for _i in attempts:
			if seafan_xf.size() >= target_seafans:
				break
			var pt := _sample_reef_candidate(rng, anchors, r_min, r_max, 0.78, 1.4, 9.5)
			if not _is_valid_atmosphere_spot(island, pt, mooring_xz, has_pier, pier_a, pier_b):
				continue
			if not _far_from_xz(pt, seafan_xz, min_sep):
				continue
			var h := island.surface_height(pt.x, pt.y)
			var root_y := h - CoralReef.ROOT_EMBED_Y
			if root_y > CoralReef.MAX_ROOT_Y:
				continue
			var n := island.surface_normal(pt.x, pt.y)
			var base_s := rng.randf_range(0.82, 1.28)
			var max_h := maxf(0.45, -h - 0.28)
			var sy := minf(base_s * rng.randf_range(0.92, 1.10), max_h / SEAFAN_CLAM_MESH_HEIGHT)
			var sx := minf(base_s, sy * 1.24)
			var sz := sx * rng.randf_range(0.92, 1.10)
			var xf := _grounded_transform(
				Vector3(pt.x, root_y, pt.y), n, 0.38, rng.randf() * TAU, Vector3(sx, sy, sz)
			)
			seafan_xf.append(xf)
			seafan_col.append(_pick_jittered_color(rng, SEAFAN_CLAM_PALETTE))
			seafan_xz.append(pt)

	var reef_vis_end := maxf(CoralReef.VISIBILITY_RANGE_END, island.seabed_radius + 110.0)
	var seafan_mmi := _create_multimesh_node(
		"SeaFanClamBeds",
		_get_seafan_clam_mesh(),
		_get_seafan_clam_material(),
		seafan_xf,
		seafan_col,
		0.5,
		reef_vis_end
	)
	atmo._seafan_mmi = seafan_mmi
	atmo._seafan_count = seafan_xf.size()
	atmo._placed_seafan_transforms = seafan_xf.duplicate()
	atmo.add_child(seafan_mmi)

	# 3. ReefBubblePlumes (36..48 sculpted 12-tri faceted micro-bubbles from 4..6 seabed vents).
	var target_vents := rng.randi_range(4, 6)
	var vents: Array[Vector3] = []
	var vent_xz: Array[Vector2] = []

	for bi in anchors.size():
		if vents.size() >= target_vents:
			break
		var pt := anchors[bi]
		if not _is_valid_atmosphere_spot(island, pt, mooring_xz, has_pier, pier_a, pier_b):
			continue
		if not _far_from_xz(pt, vent_xz, 6.0):
			continue
		var h := island.surface_height(pt.x, pt.y)
		vents.append(Vector3(pt.x, h + 0.08, pt.y))
		vent_xz.append(pt)

	for _attempt in 160:
		if vents.size() >= target_vents:
			break
		var pt := _sample_reef_candidate(rng, anchors, r_min, r_max, 0.65, 2.0, 11.0)
		if not _is_valid_atmosphere_spot(island, pt, mooring_xz, has_pier, pier_a, pier_b):
			continue
		if not _far_from_xz(pt, vent_xz, 5.5):
			continue
		var h := island.surface_height(pt.x, pt.y)
		vents.append(Vector3(pt.x, h + 0.08, pt.y))
		vent_xz.append(pt)

	var target_bubbles := rng.randi_range(38, 46)
	var bubble_xf: Array[Transform3D] = []
	var bubble_col: Array[Color] = []

	if not vents.is_empty():
		atmo._vent_positions = vents.duplicate()
		var max_r := 0.0
		for vp in vents:
			max_r = maxf(max_r, Vector2(vp.x, vp.z).length())
		atmo._bubble_outer_radius = max_r + 2.0

		atmo._bubble_vent_x.resize(target_bubbles)
		atmo._bubble_vent_z.resize(target_bubbles)
		atmo._bubble_y_start.resize(target_bubbles)
		atmo._bubble_y.resize(target_bubbles)
		atmo._bubble_speed.resize(target_bubbles)
		atmo._bubble_phase.resize(target_bubbles)
		atmo._bubble_helix_r.resize(target_bubbles)
		atmo._bubble_helix_freq.resize(target_bubbles)
		atmo._bubble_scale.resize(target_bubbles)

		for i in target_bubbles:
			var v_idx := i % vents.size()
			var vp := vents[v_idx]
			var y_start := minf(vp.y, BUBBLE_TOP_Y - 0.65)
			var span := maxf(0.45, BUBBLE_TOP_Y - y_start)
			var slot_in_vent := float(floori(float(i) / float(vents.size())))
			var slots_per_vent := maxf(1.0, ceilf(float(target_bubbles) / float(vents.size())))
			var frac := wrapf((slot_in_vent + rng.randf_range(0.05, 0.90)) / slots_per_vent, 0.0, 0.96)
			var y_init := y_start + frac * span

			atmo._bubble_vent_x[i] = vp.x + rng.randf_range(-0.18, 0.18)
			atmo._bubble_vent_z[i] = vp.z + rng.randf_range(-0.18, 0.18)
			atmo._bubble_y_start[i] = y_start
			atmo._bubble_y[i] = y_init
			atmo._bubble_speed[i] = rng.randf_range(0.68, 1.32)
			atmo._bubble_phase[i] = rng.randf() * TAU
			atmo._bubble_helix_r[i] = rng.randf_range(0.06, 0.22)
			atmo._bubble_helix_freq[i] = rng.randf_range(2.4, 4.4)
			atmo._bubble_scale[i] = rng.randf_range(0.62, 1.38)

			var b_xf := atmo._compute_bubble_transform(i)
			bubble_xf.append(b_xf)
			bubble_col.append(_pick_jittered_color(rng, BUBBLE_PALETTE))

	var bubbles_mmi := _create_multimesh_node(
		"ReefBubblePlumes",
		_get_bubble_mesh(),
		_get_bubble_material(),
		bubble_xf,
		bubble_col,
		2.0,
		BUBBLE_VISIBILITY_RANGE_END
	)
	atmo._bubbles_mmi = bubbles_mmi
	atmo._bubble_count = bubble_xf.size()
	atmo.add_child(bubbles_mmi)

	island.add_child(atmo)
	atmo._update_lighting()
	return atmo


# ------------------------------------------------------------------ inspection & tick API

## Current volumetric sun-shaft intensity uniform (`u_intensity`).
func get_sun_shaft_intensity() -> float:
	return _sun_shaft_intensity


## Current volumetric sun-shaft color tint (`u_color`).
func get_sun_shaft_color() -> Color:
	return _sun_shaft_color


## Number of volumetric god-ray shafts batched inside `UnderwaterSunShafts`.
func get_sun_shaft_count() -> int:
	return _sun_shaft_count


## Current nocturnal coral bioluminescence factor (`0.0` noon .. `1.0` midnight).
func get_biolum_strength() -> float:
	return _biolum_strength


## Number of sculpted Giant Pearl-Clam & Sea-Fan coral clusters placed in `SeaFanClamBeds`.
func get_sea_fan_clam_count() -> int:
	return _seafan_count


## Read-only copy of all placed `SeaFanClamBeds` transforms (reliable under `--headless`).
func get_placed_sea_fan_transforms() -> Array[Transform3D]:
	return _placed_seafan_transforms.duplicate()


## Number of rising faceted micro-bubbles batched in `ReefBubblePlumes`.
func get_bubble_count() -> int:
	return _bubble_count


## Current local Y elevation of every rising micro-bubble (reliable under `--headless`).
func get_bubble_heights() -> PackedFloat32Array:
	return _bubble_y.duplicate()


## Deterministic atmosphere tick for sun-shafts, nocturnal coral bioluminescence, and
## distance-gated (or forced) micro-bubble plume animation.
func tick_atmosphere(delta: float, force_bubbles: bool = false) -> void:
	_update_lighting()
	if _bubble_count <= 0 or delta <= 0.0:
		return
	if force_bubbles or _is_camera_within_bubble_range():
		_step_bubbles(delta)


# ------------------------------------------------------------------ runtime simulation

func _update_lighting() -> void:
	var day := clampf(Weather.daylight(), 0.0, 1.0)
	var sun_h := Weather.sun_height()
	var storm := clampf(
		Weather.local_storminess(global_position) if is_inside_tree() else Weather.storminess,
		0.0,
		1.0
	)

	# Volumetric god-ray intensity:
	# - Clear noon (~0.38) -> dimmed smoothly in heavy storms (~0.11 at storm=0.9)
	#   -> soft moonlit cyan shafts at midnight (~0.045).
	var sun_elev := clampf(smoothstep(0.05, 0.85, sun_h), 0.0, 1.0)
	var clear_intensity := lerpf(0.045, lerpf(0.24, 0.38, sun_elev), day)
	var storm_atten := lerpf(1.0, 0.26, smoothstep(0.10, 0.95, storm))
	_sun_shaft_intensity = clear_intensity * storm_atten

	# Color tint shifts smoothly across sun elevation:
	# - Moonlit night (sun_h < -0.10) -> cool moonlit cyan
	# - Dawn & sunset golden hour (sun_h ~ -0.02..+0.25) -> warm golden-amber
	# - Tropical midday (sun_h > 0.45) -> sunlit aquamarine
	# - Heavy storms mute rays toward slate-teal.
	var golden_band := smoothstep(-0.14, 0.02, sun_h) * (1.0 - smoothstep(0.18, 0.56, sun_h))
	var high_sun := smoothstep(0.14, 0.54, sun_h)
	var base_col := COL_SHAFT_MOON.lerp(COL_SHAFT_NOON, high_sun)
	var sky_col := base_col.lerp(COL_SHAFT_GOLDEN, golden_band * 0.88)
	_sun_shaft_color = sky_col.lerp(COL_SHAFT_STORM, storm * 0.65)

	if _sun_shaft_mat != null:
		_sun_shaft_mat.set_shader_parameter(&"u_intensity", _sun_shaft_intensity)
		_sun_shaft_mat.set_shader_parameter(&"u_color", _sun_shaft_color)

	# Nocturnal underwater bioluminescence driven by `1.0 - Weather.daylight()`.
	var night_factor := clampf(1.0 - day, 0.0, 1.0)
	_biolum_strength = smoothstep(0.15, 0.92, night_factor)

	if _seafan_clam_material != null:
		var target_seafan_e := _biolum_strength * NOCTURNAL_SEAFAN_MAX_ENERGY
		if absf(_seafan_clam_material.emission_energy_multiplier - target_seafan_e) > 0.0005:
			_seafan_clam_material.emission_energy_multiplier = target_seafan_e

	CoralReef.update_bioluminescence(_biolum_strength)


func _is_camera_within_bubble_range() -> bool:
	if not is_inside_tree():
		return false
	var vp := get_viewport()
	if vp == null:
		return false
	var cam := vp.get_camera_3d()
	if cam == null:
		return false
	var cam_pos := cam.global_position
	var outer := _bubble_outer_radius + BUBBLE_CULL_DIST
	if global_position.distance_squared_to(cam_pos) > outer * outer:
		return false
	var cam_local := to_local(cam_pos)
	for vp_local in _vent_positions:
		if cam_local.distance_squared_to(vp_local) <= BUBBLE_CULL_DIST_SQ:
			return true
	return false


func _step_bubbles(delta: float) -> void:
	if _bubbles_mmi == null or not is_instance_valid(_bubbles_mmi):
		return
	var mm := _bubbles_mmi.multimesh
	if mm == null:
		return
	_bubble_clock += delta
	for i in _bubble_count:
		var y0 := _bubble_y_start[i]
		var span := maxf(0.45, BUBBLE_TOP_Y - y0)
		var y_next := _bubble_y[i] + _bubble_speed[i] * delta
		if y_next >= BUBBLE_TOP_Y:
			y_next = y0 + fposmod(y_next - y0, span)
		_bubble_y[i] = y_next
		mm.set_instance_transform(i, _compute_bubble_transform(i))


func _compute_bubble_transform(idx: int) -> Transform3D:
	var y := _bubble_y[idx]
	var y0 := _bubble_y_start[idx]
	var span := maxf(0.45, BUBBLE_TOP_Y - y0)
	var prog := clampf((y - y0) / span, 0.0, 1.0)
	var ang := _bubble_phase[idx] + _bubble_clock * _bubble_helix_freq[idx] + prog * TAU * 1.35
	var rad := _bubble_helix_r[idx] * (0.35 + 0.65 * prog)
	var bx := _bubble_vent_x[idx] + cos(ang) * rad
	var bz := _bubble_vent_z[idx] + sin(ang) * rad
	var size_env := smoothstep(0.0, 0.08, prog) * (1.0 - 0.35 * smoothstep(0.92, 1.0, prog))
	var s := maxf(0.22, _bubble_scale[idx] * size_env)
	return Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3(bx, y, bz))


# ------------------------------------------------------------------ placement helpers

static func _make_shaft_spec(rng: RandomNumberGenerator, island: Island, pt: Vector2,
		sun_slant_dir: Vector2) -> Dictionary:
	var h := island.surface_height(pt.x, pt.y)
	var top_y := -0.35
	var slant_rad := deg_to_rad(rng.randf_range(24.0, 32.0))
	var az_jit := rng.randf_range(-0.10, 0.10)
	var dir2 := sun_slant_dir.rotated(az_jit).normalized()
	var est_depth := maxf(1.8, absf(top_y - h))
	var horiz_shift := tan(slant_rad) * est_depth
	var bot_xz := Vector2(pt.x + dir2.x * horiz_shift, pt.y + dir2.y * horiz_shift)
	var bot_h := island.surface_height(bot_xz.x, bot_xz.y)
	var bot_y := clampf(bot_h + 0.08, SUN_SHAFT_MIN_BOT_Y, -1.45)
	var top_pt := Vector3(pt.x, top_y, pt.y)
	var bot_pt := Vector3(bot_xz.x, bot_y, bot_xz.y)
	var r_top := rng.randf_range(0.30, 0.52)
	var r_bot := r_top * rng.randf_range(1.90, 2.40)
	return {
		"top": top_pt,
		"bot": bot_pt,
		"r_top": r_top,
		"r_bot": r_bot,
		"phase": rng.randf(),
		"var": rng.randf(),
	}


static func _create_multimesh_node(node_name: String, mesh: ArrayMesh, mat: Material,
		transforms: Array[Transform3D], colors: Array[Color],
		cull_margin: float, vis_end: float) -> MultiMeshInstance3D:
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
	mmi.visibility_range_end = vis_end
	mmi.visibility_range_end_margin = CoralReef.VISIBILITY_RANGE_MARGIN
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	if cull_margin > 0.0:
		mmi.extra_cull_margin = cull_margin
	return mmi


static func _sample_annulus_xz(rng: RandomNumberGenerator, r_min: float, r_max: float) -> Vector2:
	var ang := rng.randf() * TAU
	var r := sqrt(lerpf(r_min * r_min, r_max * r_max, rng.randf()))
	return Vector2(cos(ang) * r, sin(ang) * r)


static func _sample_reef_candidate(rng: RandomNumberGenerator, anchors: Array[Vector2],
		r_min: float, r_max: float, cluster_prob: float,
		patch_min: float, patch_max: float) -> Vector2:
	if not anchors.is_empty() and rng.randf() < cluster_prob:
		var ctr := anchors[rng.randi_range(0, anchors.size() - 1)]
		var ang := rng.randf() * TAU
		var dist := lerpf(patch_min, patch_max, sqrt(rng.randf()))
		var pt := ctr + Vector2(cos(ang) * dist, sin(ang) * dist)
		var r_len := pt.length()
		if r_len >= r_min and r_len <= r_max:
			return pt
	return _sample_annulus_xz(rng, r_min, r_max)


static func _is_valid_atmosphere_spot(island: Island, pt: Vector2, mooring_xz: Vector2,
		has_pier: bool, pier_a: Vector2, pier_b: Vector2) -> bool:
	if pt.distance_squared_to(mooring_xz) < CoralReef.MOORING_CLEAR_RADIUS * CoralReef.MOORING_CLEAR_RADIUS:
		return false
	if has_pier and _point_segment_dist_sq(pt, pier_a, pier_b) < CoralReef.PIER_CLEAR_RADIUS * CoralReef.PIER_CLEAR_RADIUS:
		return false
	var h := island.surface_height(pt.x, pt.y)
	if h > SEAFAN_MAX_SURFACE_Y or h < SEAFAN_MIN_SURFACE_Y:
		return false
	var n := island.surface_normal(pt.x, pt.y)
	return n.y >= CoralReef.MIN_NORMAL_Y


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
	var h := wrapf(base.h + rng.randf_range(-0.02, 0.02), 0.0, 1.0)
	var s := clampf(base.s * rng.randf_range(0.92, 1.08), 0.0, 1.0)
	var v := clampf(base.v * rng.randf_range(0.95, 1.03), 0.0, 1.0)
	return Color.from_hsv(h, s, v, 1.0)


# ------------------------------------------------------------------ shared cached assets

static func _get_sun_shaft_shader() -> Shader:
	if _sun_shaft_shader == null:
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform float u_intensity = 0.38;
uniform vec4 u_color : source_color = vec4(0.42, 0.92, 0.90, 1.0);

void vertex() {
	float phase = COLOR.r * 6.2831853;
	float sway = UV.y * 0.22;
	VERTEX.x += sin(TIME * 0.72 + phase + UV.y * 1.5) * sway;
	VERTEX.z += cos(TIME * 0.61 + phase * 1.3 + UV.y * 1.2) * sway;
}

void fragment() {
	float raw_depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float scene_z = -scene_view.z / max(scene_view.w, 1e-5);
	float frag_z = -VERTEX.z;
	float soft_depth = smoothstep(0.0, 1.45, scene_z - frag_z);
	float near_fade = smoothstep(1.1, 3.8, frag_z);
	float fresnel = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 2.55);
	float v_fade = smoothstep(0.0, 0.28, UV.y) * smoothstep(1.0, 0.24, UV.y);
	float phase = COLOR.r * 6.2831853;
	float beam_var = mix(0.80, 1.18, COLOR.g);
	float ang = UV.x * 6.2831853;
	float streak_a = 0.5 + 0.5 * sin(ang * 3.0 + TIME * 0.95 + phase - UV.y * 2.6);
	float streak_b = 0.5 + 0.5 * sin(ang * 5.0 - TIME * 1.35 + phase * 1.7 + UV.y * 3.8);
	float wave_pulse = 0.86 + 0.14 * sin(TIME * 1.15 + phase + UV.y * 1.8);
	float caustic = (0.34 + 0.68 * pow(streak_a, 2.1) + 0.36 * streak_b * streak_a) * wave_pulse;
	vec3 depth_tint = mix(u_color.rgb * vec3(1.16, 1.10, 0.92), u_color.rgb * vec3(0.68, 1.02, 1.14), UV.y);
	float energy = fresnel * v_fade * soft_depth * near_fade * caustic * beam_var * u_intensity * 0.92;
	ALBEDO = depth_tint * energy;
	ALPHA = 1.0;
}
"""
		_sun_shaft_shader = sh
	return _sun_shaft_shader


static func _get_seafan_clam_material() -> StandardMaterial3D:
	if _seafan_clam_material == null:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.roughness = 0.58
		mat.metallic = 0.04
		mat.metallic_specular = 0.42
		mat.emission_enabled = true
		mat.emission = Color(0.28, 0.88, 0.84)
		mat.emission_energy_multiplier = 0.0
		_seafan_clam_material = mat
	return _seafan_clam_material


static func _get_bubble_material() -> StandardMaterial3D:
	if _bubble_material == null:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.albedo_color = Color(0.84, 0.97, 1.0, 0.54)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.08
		mat.metallic = 0.06
		mat.metallic_specular = 0.72
		mat.rim_enabled = true
		mat.rim = 0.85
		mat.rim_tint = 0.35
		mat.emission_enabled = true
		mat.emission = Color(0.32, 0.86, 0.94)
		mat.emission_energy_multiplier = 0.35
		_bubble_material = mat
	return _bubble_material


static func _get_seafan_clam_mesh() -> ArrayMesh:
	if _seafan_clam_mesh == null:
		_seafan_clam_mesh = _build_seafan_clam_mesh()
	return _seafan_clam_mesh


static func _get_bubble_mesh() -> ArrayMesh:
	if _bubble_mesh == null:
		_bubble_mesh = _build_bubble_mesh()
	return _bubble_mesh


# ------------------------------------------------------------------ Mesh 1: Underwater Sun-Shafts

static func _build_sun_shafts_mesh(specs: Array[Dictionary]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	const SIDES := 10
	const V_SEGS := 3

	for spec in specs:
		var top_pt: Vector3 = spec["top"]
		var bot_pt: Vector3 = spec["bot"]
		var r_top: float = float(spec["r_top"])
		var r_bot: float = float(spec["r_bot"])
		var phase_01: float = float(spec["phase"])
		var beam_var: float = float(spec["var"])

		var axis := bot_pt - top_pt
		var shaft_len := axis.length()
		if shaft_len < 0.25:
			continue
		var dir := axis / shaft_len
		var ref := Vector3.RIGHT if absf(dir.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
		var u_ax := dir.cross(ref).normalized()
		var v_ax := dir.cross(u_ax).normalized()
		var dr := r_bot - r_top
		var v_col := Color(phase_01, beam_var, 1.0, 1.0)

		var rings_p: Array[Array] = []
		var rings_n: Array[Array] = []
		var rings_uv: Array[Array] = []

		for vi in range(V_SEGS + 1):
			var t := float(vi) / float(V_SEGS)
			var ctr := top_pt.lerp(bot_pt, t)
			var rad_r := lerpf(r_top, r_bot, t)
			var pts: Array[Vector3] = []
			var norms: Array[Vector3] = []
			var uvs: Array[Vector2] = []
			for si in range(SIDES + 1):
				var u := float(si) / float(SIDES)
				var ang := u * TAU
				var radial := u_ax * cos(ang) + v_ax * sin(ang)
				var n_out := (radial * shaft_len - dir * dr).normalized()
				pts.append(ctr + radial * rad_r)
				norms.append(n_out)
				uvs.append(Vector2(u, t))
			rings_p.append(pts)
			rings_n.append(norms)
			rings_uv.append(uvs)

		for vi in V_SEGS:
			var p0: Array = rings_p[vi]
			var p1: Array = rings_p[vi + 1]
			var n0: Array = rings_n[vi]
			var n1: Array = rings_n[vi + 1]
			var u0: Array = rings_uv[vi]
			var u1: Array = rings_uv[vi + 1]
			for si in SIDES:
				_add_smooth_tri(st, p0[si], p0[si + 1], p1[si + 1],
					n0[si], n0[si + 1], n1[si + 1], u0[si], u0[si + 1], u1[si + 1], v_col)
				_add_smooth_tri(st, p0[si], p1[si + 1], p1[si],
					n0[si], n1[si + 1], n1[si], u0[si], u1[si + 1], u1[si], v_col)

	return st.commit()


# ------------------------------------------------------------------ Mesh 2: Sculpted Giant Pearl-Clam + Sea-Fan Coral

static func _build_seafan_clam_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Faceted limestone-sand holdfast base anchoring clam & sea-fan below y = 0 (18 tris).
	_append_holdfast_base(
		st,
		Vector3(0.0, 0.0, 0.0),
		0.44,
		0.09,
		0.38,
		-0.14,
		6,
		Color(0.48, 0.50, 0.54, 1.0),
		Color(0.68, 0.69, 0.70, 1.0)
	)

	# 2. Ribbed, open-valved Giant Pearl-Clam (Tridacna gigas) with fluted mantle & luminous pearl.
	var clam_ctr := Vector3(-0.12, 0.05, 0.08)
	_append_giant_pearl_clam(st, clam_ctr)

	# 3. Upright pleated lacy coral Sea-Fan frond flanking the clam (108 tris).
	var fan_ctr := Vector3(0.24, 0.02, -0.14)
	_append_pleated_sea_fan(st, fan_ctr)

	st.generate_normals()
	return st.commit()


static func _append_giant_pearl_clam(st: SurfaceTool, center: Vector3) -> void:
	const RIB_SEGS := 5
	const SHELL_THICK := 0.036

	var col_outer_valley := Color(0.62, 0.60, 0.56, 1.0)
	var col_outer_crest := Color(0.95, 0.92, 0.84, 1.0)
	var col_rim := Color(0.98, 0.96, 0.90, 1.0)
	var col_nacre_inner := Color(0.88, 0.94, 0.98, 1.0)
	var col_nacre_lip := Color(0.98, 0.95, 0.92, 1.0)

	# Two thick fluted shell valves opening upward in a V-cradle (left: -X, right: +X).
	for side_sign: float in [-1.0, 1.0]:
		var umbo_out := center + Vector3(side_sign * 0.055, 0.01, 0.0)
		var umbo_in := center + Vector3(side_sign * 0.018, 0.04, 0.0)
		var mid_out: Array[Vector3] = []
		var lip_out: Array[Vector3] = []
		var mid_in: Array[Vector3] = []
		var lip_in: Array[Vector3] = []
		var mid_col: Array[Color] = []
		var lip_col: Array[Color] = []

		for k in range(RIB_SEGS + 1):
			var frac := float(k) / float(RIB_SEGS)
			var fan_ang := lerpf(-1.12, 1.12, frac)
			var flute := 1.0 if (k % 2 == 1) else -1.0
			var cs := cos(fan_ang)
			var sn := sin(fan_ang)

			# Mid-shell rib ridge.
			var mid_r := 0.20 + flute * 0.020
			var mid_x := side_sign * (0.145 + cs * 0.065 + flute * 0.024)
			var mid_y := 0.05 + cs * mid_r * 0.72
			var mid_z := sn * mid_r * 0.96
			var p_mo := center + Vector3(mid_x, mid_y, mid_z)
			var p_mi := p_mo + Vector3(-side_sign * SHELL_THICK, 0.016, 0.0)

			# Outer wavy scalloped interlocking valve lip.
			var lip_r := 0.34 + flute * 0.036
			var lip_x := side_sign * (0.215 + cs * 0.075 + flute * 0.036)
			var lip_y := 0.09 + cs * lip_r * 0.88 + flute * 0.022
			var lip_z := sn * lip_r * 0.98
			var p_lo := center + Vector3(lip_x, lip_y, lip_z)
			var p_li := p_lo + Vector3(-side_sign * SHELL_THICK * 0.92, 0.008, 0.0)

			mid_out.append(p_mo)
			mid_in.append(p_mi)
			lip_out.append(p_lo)
			lip_in.append(p_li)
			var rib_t := 0.82 if flute > 0.0 else 0.18
			mid_col.append(col_outer_valley.lerp(col_outer_crest, rib_t * 0.85))
			lip_col.append(col_outer_valley.lerp(col_outer_crest, rib_t))

		var shell_ref := center + Vector3(side_sign * 0.14, 0.08, 0.0)
		var cavity_ref := center + Vector3(0.0, 0.24, 0.0)

		for k in RIB_SEGS:
			# Outer ribbed calcium shell (faces outward away from cavity_ref).
			_add_outward_tri(st, umbo_out, mid_out[k], mid_out[k + 1], cavity_ref,
				col_outer_valley, mid_col[k], mid_col[k + 1])
			_add_outward_quad(st, mid_out[k], lip_out[k], lip_out[k + 1], mid_out[k + 1], cavity_ref,
				mid_col[k], lip_col[k], lip_col[k + 1], mid_col[k + 1])

			# Thick scalloped rim bevel (faces upward/outward away from shell_ref).
			_add_outward_quad(st, lip_out[k], lip_in[k], lip_in[k + 1], lip_out[k + 1], shell_ref,
				lip_col[k], col_rim, col_rim, lip_col[k + 1])

			# Inner mother-of-pearl concave lining (faces inward toward cavity_ref).
			_add_inward_quad(st, lip_in[k], mid_in[k], mid_in[k + 1], lip_in[k + 1], cavity_ref,
				col_nacre_lip, col_nacre_inner, col_nacre_inner, col_nacre_lip)
			_add_inward_tri(st, mid_in[k], umbo_in, mid_in[k + 1], cavity_ref,
				col_nacre_inner, col_nacre_inner, col_nacre_inner)

		# Watertight end walls at k = 0 and k = RIB_SEGS.
		for end_k: int in [0, RIB_SEGS]:
			var end_ref := center + Vector3(side_sign * 0.12, 0.14, 0.0)
			_add_outward_tri(st, umbo_out, umbo_in, mid_in[end_k], end_ref,
				col_outer_valley, col_nacre_inner, col_nacre_inner)
			_add_outward_tri(st, umbo_out, mid_in[end_k], mid_out[end_k], end_ref,
				col_outer_valley, col_nacre_inner, mid_col[end_k])
			_add_outward_quad(st, mid_out[end_k], mid_in[end_k], lip_in[end_k], lip_out[end_k], end_ref,
				mid_col[end_k], col_nacre_inner, col_rim, lip_col[end_k])

	# Wavy iridescent fluted mantle cushion nestled between the open valves (24 tris).
	const MANTLE_SEGS := 6
	var col_mantle_core := Color(0.18, 0.68, 0.78, 1.0)
	var col_mantle_lip := Color(0.42, 0.96, 0.92, 1.0)
	var m_left: Array[Vector3] = []
	var m_mid: Array[Vector3] = []
	var m_right: Array[Vector3] = []
	for k in range(MANTLE_SEGS + 1):
		var frac := float(k) / float(MANTLE_SEGS)
		var z := lerpf(-0.24, 0.24, frac)
		var arch := sin(frac * PI)
		var wave := sin(frac * PI * 5.0) * 0.022
		var half_w := 0.055 + arch * 0.125
		var y_edge := 0.14 + arch * 0.115 + wave
		var y_ctr := 0.105 + arch * 0.055
		m_left.append(center + Vector3(-half_w, y_edge, z))
		m_mid.append(center + Vector3(0.0, y_ctr, z))
		m_right.append(center + Vector3(half_w, y_edge, z))

	var mantle_ref := center + Vector3(0.0, 0.02, 0.0)
	for k in MANTLE_SEGS:
		_add_outward_quad(st, m_left[k], m_mid[k], m_mid[k + 1], m_left[k + 1], mantle_ref,
			col_mantle_lip, col_mantle_core, col_mantle_core, col_mantle_lip)
		_add_outward_quad(st, m_mid[k], m_right[k], m_right[k + 1], m_mid[k + 1], mantle_ref,
			col_mantle_core, col_mantle_lip, col_mantle_lip, col_mantle_core)

	# Luminous cream-opal pearl nestled in the center of the open mantle (24 tris).
	_append_faceted_pearl(st, center + Vector3(0.0, 0.215, 0.0), 0.088)


static func _append_faceted_pearl(st: SurfaceTool, center: Vector3, radius: float) -> void:
	const SIDES := 6
	var col_top := Color(1.00, 0.99, 0.94, 1.0)
	var col_upper := Color(0.99, 0.96, 0.89, 1.0)
	var col_lower := Color(0.92, 0.94, 0.97, 1.0)
	var col_bot := Color(0.84, 0.93, 0.96, 1.0)

	var top_pt := center + Vector3(0.0, radius, 0.0)
	var bot_pt := center - Vector3(0.0, radius, 0.0)
	var upper_ring: Array[Vector3] = []
	var lower_ring: Array[Vector3] = []
	var r_band := radius * 0.866
	var y_band := radius * 0.48
	for s in SIDES:
		var ang := float(s) / float(SIDES) * TAU
		upper_ring.append(center + Vector3(cos(ang) * r_band, y_band, sin(ang) * r_band))
		lower_ring.append(center + Vector3(cos(ang + PI / float(SIDES)) * r_band, -y_band,
			sin(ang + PI / float(SIDES)) * r_band))

	for s in SIDES:
		var ns := (s + 1) % SIDES
		_add_outward_tri(st, upper_ring[s], top_pt, upper_ring[ns], center, col_upper, col_top, col_upper)
		_add_outward_quad(st, lower_ring[s], upper_ring[s], upper_ring[ns], lower_ring[ns], center,
			col_lower, col_upper, col_upper, col_lower)
		_add_outward_tri(st, lower_ring[ns], bot_pt, lower_ring[s], center, col_lower, col_bot, col_lower)


static func _append_pleated_sea_fan(st: SurfaceTool, origin: Vector3) -> void:
	# Sturdy coral stalk anchored into the holdfast base (8 tris).
	var col_stem_bot := Color(0.68, 0.28, 0.34, 1.0)
	var col_stem_top := Color(0.84, 0.38, 0.36, 1.0)
	var p_base := origin + Vector3(0.0, -0.05, 0.0)
	var p_fork := origin + Vector3(0.0, 0.22, 0.0)
	_append_prism_stalk(st, p_base, p_fork, 0.068, 0.052, 4, col_stem_bot, col_stem_top)

	# 5 upright pleated coral sea-fan lobes radiating in an organic palmate silhouette (100 tris).
	# Plane of the fan faces obliquely forward-left to frame the Giant Pearl-Clam cleanly.
	var fan_yaw := -0.48
	var fan_right := Vector3(cos(fan_yaw), 0.0, sin(fan_yaw))
	var fan_fwd := Vector3(-sin(fan_yaw), 0.0, cos(fan_yaw))

	# [tilt_rad, length, max_half_width, pleat_depth, curl_fwd]
	var lobes: Array[Array] = [
		[-0.92, 0.58, 0.095, 0.036, 0.08],
		[-0.46, 0.78, 0.115, 0.044, 0.10],
		[0.00, 0.90, 0.125, 0.048, 0.12],
		[0.46, 0.76, 0.112, 0.042, 0.10],
		[0.92, 0.56, 0.092, 0.035, 0.07],
	]

	var col_root := Color(0.82, 0.34, 0.38, 1.0)
	var col_mid := Color(0.98, 0.50, 0.38, 1.0)
	var col_tip := Color(1.00, 0.78, 0.54, 1.0)

	for spec in lobes:
		var tilt: float = float(spec[0])
		var length: float = float(spec[1])
		var max_w: float = float(spec[2])
		var pleat: float = float(spec[3])
		var curl: float = float(spec[4])

		var lobe_dir := (Vector3.UP * cos(tilt) + fan_right * sin(tilt)).normalized()
		var lat_dir := (fan_right * cos(tilt) - Vector3.UP * sin(tilt)).normalized()

		var stations_t: Array[float] = [0.0, 0.36, 0.74]
		var widths: Array[float] = [0.34, 0.94, 1.00]
		var thicks: Array[float] = [0.85, 1.00, 0.72]
		var cols: Array[Color] = [col_root, col_mid, col_mid.lerp(col_tip, 0.65)]

		var rings: Array[Array] = []
		var ctrs: Array[Vector3] = []
		for si in stations_t.size():
			var t: float = stations_t[si]
			var ctr := p_fork + lobe_dir * (length * t) + fan_fwd * (curl * t * t)
			var w: float = max_w * widths[si]
			var d: float = pleat * thicks[si]
			rings.append([
				ctr - lat_dir * w,
				ctr + fan_fwd * d,
				ctr + lat_dir * w,
				ctr - fan_fwd * d,
			])
			ctrs.append(ctr)

		var tip := p_fork + lobe_dir * length + fan_fwd * (curl * 1.15)
		for si in range(rings.size() - 1):
			var r0: Array = rings[si]
			var r1: Array = rings[si + 1]
			var seg_ref := (ctrs[si] + ctrs[si + 1]) * 0.5
			var c0: Color = cols[si]
			var c1: Color = cols[si + 1]
			for ei in 4:
				var nei := (ei + 1) % 4
				_add_outward_quad(st, r0[ei], r1[ei], r1[nei], r0[nei], seg_ref, c0, c1, c1, c0)

		var top_r: Array = rings[rings.size() - 1]
		var tip_ref := ctrs[ctrs.size() - 1] - lobe_dir * 0.06
		var c_top: Color = cols[cols.size() - 1]
		for ei in 4:
			var nei := (ei + 1) % 4
			_add_outward_tri(st, top_r[ei], tip, top_r[nei], tip_ref, c_top, col_tip, c_top)


static func _append_prism_stalk(st: SurfaceTool, p0: Vector3, p1: Vector3, r0: float,
		r1: float, sides: int, col0: Color, col1: Color) -> void:
	var axis := p1 - p0
	if axis.length_squared() < 1e-6:
		return
	var dir := axis.normalized()
	var ref := Vector3.RIGHT if absf(dir.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var u := dir.cross(ref).normalized()
	var v := dir.cross(u).normalized()
	var ring0: Array[Vector3] = []
	var ring1: Array[Vector3] = []
	for i in sides:
		var ang := float(i) / float(sides) * TAU
		var rad := u * cos(ang) + v * sin(ang)
		ring0.append(p0 + rad * r0)
		ring1.append(p1 + rad * r1)
	var mid_ref := (p0 + p1) * 0.5
	for i in sides:
		var ni := (i + 1) % sides
		_add_outward_quad(st, ring0[i], ring1[i], ring1[ni], ring0[ni], mid_ref,
			col0, col1, col1, col0)


# ------------------------------------------------------------------ Mesh 3: 12-Tri Gem Micro-Bubble

static func _build_bubble_mesh() -> ArrayMesh:
	# Sculpted exact 12-triangle oblate hexagonal bipyramid gem-bubble (zero SphereMesh).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SIDES := 6
	const R_EQ := 0.056
	const R_POLE := 0.047
	var top := Vector3(0.0, R_POLE, 0.0)
	var bot := Vector3(0.0, -R_POLE, 0.0)
	var ring: Array[Vector3] = []
	for s in SIDES:
		var ang := float(s) / float(SIDES) * TAU
		ring.append(Vector3(cos(ang) * R_EQ, 0.0, sin(ang) * R_EQ))
	var col_top := Color(0.96, 1.00, 1.00, 1.0)
	var col_eq := Color(0.76, 0.96, 1.00, 1.0)
	var col_bot := Color(0.56, 0.88, 0.96, 1.0)
	for s in SIDES:
		var ns := (s + 1) % SIDES
		_add_outward_tri(st, ring[s], top, ring[ns], Vector3.ZERO, col_eq, col_top, col_eq)
		_add_outward_tri(st, ring[ns], bot, ring[s], Vector3.ZERO, col_eq, col_bot, col_eq)
	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ SurfaceTool primitives

static func _append_holdfast_base(st: SurfaceTool, center: Vector3, rx: float, ry: float,
		rz: float, bot_y: float, segs: int, col_bot: Color, col_top: Color) -> void:
	var bot_ring: Array[Vector3] = []
	var mid_ring: Array[Vector3] = []
	for k in segs:
		var ang := float(k) / float(segs) * TAU
		var jit := 0.92 + 0.14 * sin(ang * 3.0 + 0.4)
		bot_ring.append(center + Vector3(cos(ang) * rx * jit, bot_y, sin(ang) * rz * jit))
		mid_ring.append(center + Vector3(cos(ang) * rx * 0.74 * jit, ry * 0.65, sin(ang) * rz * 0.74 * jit))
	var crown := center + Vector3(0.0, ry, 0.0)
	var ref_ctr := center + Vector3(0.0, (bot_y + ry) * 0.35, 0.0)
	var col_mid := col_bot.lerp(col_top, 0.58)
	for k in segs:
		var nk := (k + 1) % segs
		_add_outward_quad(st, bot_ring[k], mid_ring[k], mid_ring[nk], bot_ring[nk], ref_ctr,
			col_bot, col_mid, col_mid, col_bot)
		_add_outward_tri(st, mid_ring[k], crown, mid_ring[nk], ref_ctr,
			col_mid, col_top, col_mid)


static func _add_outward_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_add_outward_tri(st, a, b, c, ref_center, ca, cb, cc)
	_add_outward_tri(st, a, c, d, ref_center, ca, cc, cd)


static func _add_inward_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_add_inward_tri(st, a, b, c, ref_center, ca, cb, cc)
	_add_inward_tri(st, a, c, d, ref_center, ca, cc, cd)


static func _add_outward_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color) -> void:
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
	_add_flat_tri(st, a, b, c, ca, cb, cc)


static func _add_inward_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	# Winding facing TOWARD `ref_center` (used for concave inner clam shell lining).
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-10:
		return
	var centroid := (a + b + c) / 3.0
	if n.dot(ref_center - centroid) < 0.0:
		var tmp_v := b
		b = c
		c = tmp_v
		var tmp_c := cb
		cb = cc
		cc = tmp_c
	_add_flat_tri(st, a, b, c, ca, cb, cc)


static func _add_flat_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color) -> void:
	if (c - a).cross(b - a).length_squared() < 1e-10:
		return
	st.set_smooth_group(-1)
	st.set_color(ca)
	st.set_uv(Vector2(0.5, 0.5))
	st.add_vertex(a)

	st.set_smooth_group(-1)
	st.set_color(cb)
	st.set_uv(Vector2(0.5, 0.5))
	st.add_vertex(b)

	st.set_smooth_group(-1)
	st.set_color(cc)
	st.set_uv(Vector2(0.5, 0.5))
	st.add_vertex(c)


static func _add_smooth_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3,
		uva: Vector2, uvb: Vector2, uvc: Vector2, col: Color) -> void:
	if (c - a).cross(b - a).length_squared() < 1e-10:
		return
	st.set_normal(na)
	st.set_color(col)
	st.set_uv(uva)
	st.add_vertex(a)

	st.set_normal(nb)
	st.set_color(col)
	st.set_uv(uvb)
	st.add_vertex(b)

	st.set_normal(nc)
	st.set_color(col)
	st.set_uv(uvc)
	st.add_vertex(c)
