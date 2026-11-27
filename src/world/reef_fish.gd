class_name ReefFishSchool
extends Node3D
## 1-draw-call sculpted underwater tropical reef fish school (`MultiMeshInstance3D`).
##
## Renders 20..26 flat-faceted tropical reef fish (Royal Butterflyfish, Reef Blue
## Tang, Coral Anthias, Emerald Chromis) in a single batched draw call swimming
## along curving submerged figure-8 / toroidal reef loops (-1.2 m .. -5.2 m),
## tail-wagging smoothly, scattering playfully when a swimming Pawn approaches
## within 4.5 m, and skipping CPU updates beyond 78 m for 0.00 ms sailing cost.

const GROUP := &"reef_fish"
const VISIBILITY_END := 75.0
const VISIBILITY_MARGIN := 12.0
const CPU_CULL_DIST := 78.0
const SCATTER_RADIUS := 4.5
const MAX_FISH_Y := -0.95
const MOORING_CLEAR_RADIUS := 9.5
const PIER_CLEAR_RADIUS := 5.0
const BIOLUM_COLOR := Color(0.18, 0.88, 0.92)
const BIOLUM_MAX_ENERGY := 0.42
const SCATTER_BUBBLE_COUNT := 12
const SCATTER_BUBBLE_LIFETIME := 1.15
const SCATTER_BUBBLE_COOLDOWN := 0.65
const SCATTER_BUBBLE_MAX_WORLD_Y := -0.35
const COL_BUBBLE_TOP := Color(0.95, 1.00, 1.00, 1.0)
const COL_BUBBLE_MID := Color(0.76, 0.96, 0.99, 1.0)
const COL_BUBBLE_BOT := Color(0.56, 0.88, 0.96, 1.0)

# Vibrant tropical reef species tints multiplied against bright neutral sRGB vertex shading.
const SPECIES_PALETTE: Array[Color] = [
	Color(1.00, 0.84, 0.16, 1.0),  # Royal Butterflyfish (sunlit golden yellow)
	Color(0.14, 0.62, 1.00, 1.0),  # Reef Blue Tang (electric cobalt-cyan)
	Color(1.00, 0.44, 0.20, 1.0),  # Coral Anthias (warm tangerine-coral)
	Color(0.32, 0.90, 0.78, 1.0),  # Emerald Chromis (silvery seafoam-teal)
]

static var _active_schools: int = 0
static var _fish_mesh: ArrayMesh = null
static var _fish_mat: StandardMaterial3D = null
static var _bubble_mesh: ArrayMesh = null
static var _bubble_mat: StandardMaterial3D = null

@export var fish_count: int = 24
@export var school_radius: float = 4.6
@export var seed_val: int = 101
@export var min_depth_y: float = -4.8
@export var max_depth_y: float = -1.2

var _mmi: MultiMeshInstance3D = null
var _bubbles_mmi: MultiMeshInstance3D = null
var _fish: Array[Dictionary] = []
var _clock: float = 0.0
var _built: bool = false
var _biolum_energy: float = 0.0
var _bubble_origin: PackedVector3Array = PackedVector3Array()
var _bubble_pos: PackedVector3Array = PackedVector3Array()
var _bubble_rise_speed: PackedFloat32Array = PackedFloat32Array()
var _bubble_wobble_phase: PackedFloat32Array = PackedFloat32Array()
var _bubble_wobble_rad: PackedFloat32Array = PackedFloat32Array()
var _bubble_wobble_freq: PackedFloat32Array = PackedFloat32Array()
var _bubble_scale: PackedFloat32Array = PackedFloat32Array()
var _bubble_burst_elapsed: float = -1.0
var _bubble_cooldown: float = 0.0
var _bubble_active_ratio: float = 0.0
var _bubble_rng: RandomNumberGenerator = null


## Release statically cached shared fish and scatter bubble ArrayMeshes and materials cleanly.
static func clear_shared_cache() -> void:
	_fish_mesh = null
	_fish_mat = null
	_bubble_mesh = null
	_bubble_mat = null


## Deterministically find a shallow lagoon/reef patch around `island` (depth -1.8 m .. -5.0 m,
## right over its `CoralReef` when present, clear of mooring & pier) and attach a `ReefFishSchool`.
static func populate_for_island(island: Island, rng_seed: int = 0) -> ReefFishSchool:
	if island == null:
		return null

	var rng := RandomNumberGenerator.new()
	var s := rng_seed if rng_seed != 0 else (island.island_id.hash() ^ 0xF1545C01)
	if s == 0:
		s = 0xF1545C01
	rng.seed = s

	var chosen_xz := Vector2.ZERO
	var chosen_seabed := -3.2
	var found := false

	var mooring_xz := Vector2(island.mooring_transform.origin.x, island.mooring_transform.origin.z)
	var has_pier := island is Outpost
	var pier_a := Vector2.ZERO
	var pier_b := Vector2.ZERO
	if has_pier:
		var op := island as Outpost
		pier_a = Vector2(op.dock_local_transform.origin.x, op.dock_local_transform.origin.z)
		pier_b = Vector2(op.dock_pier_end_local.x, op.dock_pier_end_local.z)

	# 1. Prefer anchoring directly above the island's primary shallow CoralReef bed!
	var reef := island.get_node_or_null(^"CoralReef") as CoralReef
	if reef != null:
		var pts := reef.get_placed_transforms()
		for pi in mini(pts.size(), 16):
			var p: Vector3 = pts[pi].origin
			var pxz := Vector2(p.x, p.z)
			if not _is_clear_of_harbour(pxz, mooring_xz, has_pier, pier_a, pier_b):
				continue
			var bed_y := island.surface_height(p.x, p.z)
			if bed_y <= -1.75 and bed_y >= -5.6:
				chosen_xz = pxz
				chosen_seabed = bed_y
				found = true
				break

	# 2. Fallback deterministic shallow shelf sweep (-1.8 m .. -5.0 m).
	if not found:
		var r_min := maxf(6.0, island.island_radius * 0.62)
		var r_max := maxf(r_min + 6.0, island.seabed_radius * 0.88)
		for _attempt in 140:
			var ang := rng.randf() * TAU
			var rad := lerpf(r_min, r_max, rng.randf())
			var pxz := Vector2(cos(ang) * rad, sin(ang) * rad)
			if not _is_clear_of_harbour(pxz, mooring_xz, has_pier, pier_a, pier_b):
				continue
			var bed_y := island.surface_height(pxz.x, pxz.y)
			if bed_y <= -1.8 and bed_y >= -5.0:
				chosen_xz = pxz
				chosen_seabed = bed_y
				found = true
				break

	if not found:
		return null

	var school := ReefFishSchool.new()
	school.name = "ReefFishSchool"
	school.seed_val = s
	school.fish_count = rng.randi_range(20, 26)
	school.school_radius = rng.randf_range(3.8, 5.2)
	var center_y := clampf(chosen_seabed + 1.35, -4.4, -1.65)
	school.position = Vector3(chosen_xz.x, center_y, chosen_xz.y)
	school.min_depth_y = maxf(chosen_seabed + 0.45, -5.2)
	school.max_depth_y = minf(center_y + 0.55, -1.2)
	island.add_child(school)
	return school


static func _is_clear_of_harbour(pt: Vector2, mooring_xz: Vector2,
		has_pier: bool, pier_a: Vector2, pier_b: Vector2) -> bool:
	if pt.distance_to(mooring_xz) < MOORING_CLEAR_RADIUS:
		return false
	if has_pier:
		var ab := pier_b - pier_a
		var ab_len2 := ab.length_squared()
		var t := clampf((pt - pier_a).dot(ab) / ab_len2, 0.0, 1.0) if ab_len2 > 0.001 else 0.0
		if pt.distance_to(pier_a + ab * t) < PIER_CLEAR_RADIUS:
			return false
	return true


func _enter_tree() -> void:
	_active_schools += 1
	add_to_group(GROUP)


func _exit_tree() -> void:
	if _mmi != null and is_instance_valid(_mmi):
		_mmi.visible = false
		_mmi.material_override = null
		_mmi.multimesh = null
	_mmi = null
	if _bubbles_mmi != null and is_instance_valid(_bubbles_mmi):
		_bubbles_mmi.visible = false
		_bubbles_mmi.material_override = null
		_bubbles_mmi.multimesh = null
	_bubbles_mmi = null
	_bubble_origin.clear()
	_bubble_pos.clear()
	_bubble_rise_speed.clear()
	_bubble_wobble_phase.clear()
	_bubble_wobble_rad.clear()
	_bubble_wobble_freq.clear()
	_bubble_scale.clear()
	_bubble_burst_elapsed = -1.0
	_bubble_cooldown = 0.0
	_bubble_active_ratio = 0.0
	_bubble_rng = null
	_biolum_energy = 0.0
	_fish.clear()
	_built = false
	_active_schools = maxi(0, _active_schools - 1)
	if _active_schools == 0:
		clear_shared_cache()


func _ready() -> void:
	_ensure_built()


func _physics_process(delta: float) -> void:
	if not _built:
		return
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam != null:
		if global_position.distance_squared_to(cam.global_position) > CPU_CULL_DIST * CPU_CULL_DIST:
			return
	var threat := _find_nearby_swimmer()
	step_school(delta, threat)


## Deterministically advance all fish along curving figure-8 / toroidal reef loops,
## applying tail-wag sway, nocturnal bioluminescent sheen, playful scatter away from
## `threat_pos` (within 4.5 m), and rising submerged scatter micro-bubbles.
func step_school(delta: float, threat_pos: Vector3 = Vector3.INF) -> void:
	if not _built or _mmi == null or _mmi.multimesh == null:
		return
	var dt := clampf(delta, 0.0, 0.25)
	_clock += dt
	_update_nocturnal_biolum()
	var mm := _mmi.multimesh
	var origin_w := global_position if is_inside_tree() else position
	var inv_basis := global_basis.inverse() if is_inside_tree() else basis.inverse()
	var has_threat := threat_pos.is_finite()
	var local_threat := inv_basis * (threat_pos - origin_w) if has_threat else Vector3.INF
	var local_max_y := MAX_FISH_Y - origin_w.y
	var local_hi_y := minf(max_depth_y - origin_w.y, local_max_y)
	var local_lo_y := minf(min_depth_y - origin_w.y, local_hi_y - 0.15)

	var startled_count := 0
	var startled_sum := Vector3.ZERO

	for i in _fish.size():
		var f: Dictionary = _fish[i]
		var t: float = _clock * float(f["speed"]) + float(f["phase"])
		var r: float = float(f["orbit_r"])
		var fig_blend: float = float(f["fig_blend"])
		var swirl_ang: float = float(f["swirl_yaw"])

		# Blend smooth toroidal reef circle with graceful figure-8 weave.
		var cx := cos(t) * r
		var cz := sin(t) * r * (0.72 + 0.28 * cos(t * 0.5))
		var fx := sin(t) * r * 1.12
		var fz := sin(t) * cos(t) * r * 1.35
		var raw_x := lerpf(cx, fx, fig_blend)
		var raw_z := lerpf(cz, fz, fig_blend)
		var cs := cos(swirl_ang)
		var sn := sin(swirl_ang)
		var target_local := Vector3(
			raw_x * cs - raw_z * sn,
			float(f["depth_offset"]) + sin(t * 1.7 + float(f["wag_phase"])) * 0.26,
			raw_x * sn + raw_z * cs
		)
		target_local.y = clampf(target_local.y, local_lo_y, local_hi_y)

		var pos: Vector3 = f["pos"] as Vector3
		var scatter_vel: Vector3 = f["scatter_vel"] as Vector3
		var scattering := false

		if has_threat:
			var away := pos - local_threat
			var dist := away.length()
			if dist < SCATTER_RADIUS:
				scattering = true
				startled_count += 1
				startled_sum += pos
				var push_dir := Vector3(away.x, minf(away.y, -0.15), away.z)
				if push_dir.length_squared() < 0.0001:
					push_dir = Vector3(cos(float(i)), -0.2, sin(float(i)))
				push_dir = push_dir.normalized()
				var urgency := clampf(1.0 - dist / SCATTER_RADIUS, 0.2, 1.0)
				scatter_vel = scatter_vel.lerp(push_dir * (4.8 + 4.4 * urgency), clampf(dt * 12.0, 0.0, 1.0))

		var next_pos: Vector3
		if dt > 0.0:
			var steer_rate := 1.4 if scatter_vel.length_squared() > 0.35 else 3.2
			var follow := pos.lerp(target_local, 1.0 - exp(-steer_rate * dt))
			next_pos = follow + scatter_vel * dt
			scatter_vel *= exp(-2.4 * dt)
		else:
			next_pos = target_local

		next_pos.y = clampf(next_pos.y, local_lo_y, local_max_y)

		var move_vec := next_pos - pos
		var heading: Vector3 = f["heading"] as Vector3
		if move_vec.length_squared() > 1e-6:
			var desired_h := move_vec.normalized()
			heading = heading.lerp(desired_h, 1.0 - exp(-9.5 * maxf(dt, 0.016))).normalized()
		if heading.length_squared() < 0.01:
			heading = Vector3.FORWARD

		f["pos"] = next_pos
		f["heading"] = heading
		f["scatter_vel"] = scatter_vel

		var wag_amp := 0.26 if (scattering or scatter_vel.length_squared() > 0.5) else 0.16
		var wag := sin(_clock * 9.0 + float(f["wag_phase"])) * wag_amp
		var flat_h := Vector3(heading.x, 0.0, heading.z)
		var base_yaw := atan2(-flat_h.x, -flat_h.z) if flat_h.length_squared() > 1e-5 else 0.0
		var pitch := clampf(asin(clampf(heading.y, -0.7, 0.7)), -0.55, 0.55)
		var roll := -wag * 0.45
		var fish_basis := Basis(Vector3.UP, base_yaw + wag) \
			* Basis(Vector3.RIGHT, pitch) \
			* Basis(Vector3.FORWARD, roll) \
			* Basis.from_scale(Vector3.ONE * float(f["scale"]))
		mm.set_instance_transform(i, Transform3D(fish_basis, next_pos))

	if _bubble_cooldown > 0.0 and dt > 0.0:
		_bubble_cooldown = maxf(0.0, _bubble_cooldown - dt)
	var triggered_burst := false
	if startled_count > 0 and _bubble_cooldown <= 0.0:
		_trigger_scatter_bubbles(startled_sum / float(startled_count), origin_w)
		_bubble_cooldown = SCATTER_BUBBLE_COOLDOWN
		triggered_burst = true
	_step_scatter_bubbles(0.0 if triggered_burst else dt, origin_w)


func get_multimesh_instance() -> MultiMeshInstance3D:
	return _mmi


## Current nocturnal bioluminescent sheen emission energy (`0.00` daylight -> `0.42` midnight).
func get_biolum_energy() -> float:
	return _biolum_energy


## Preallocated 12-instance sculpted `ScatterBubbleBurst` MultiMeshInstance3D (hidden when calm).
func get_scatter_bubbles() -> MultiMeshInstance3D:
	if _bubbles_mmi != null and is_instance_valid(_bubbles_mmi):
		return _bubbles_mmi
	return null


## Remaining active fraction of `ScatterBubbleBurst` (`0.0` hidden/calm, `1.0 -> 0.0` during 1.15 s burst).
func get_scatter_bubble_active_ratio() -> float:
	return _bubble_active_ratio


## Read-only world-space positions of all 12 scatter bubbles (reliable under `--headless`).
func get_scatter_bubble_world_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	if _bubble_pos.is_empty():
		return out
	var origin_w := global_position if is_inside_tree() else position
	out.resize(_bubble_pos.size())
	for i in _bubble_pos.size():
		out[i] = origin_w + _bubble_pos[i]
	return out


func get_fish_world_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	if _fish.is_empty():
		return out
	var xf := global_transform if is_inside_tree() else transform
	out.resize(_fish.size())
	for i in _fish.size():
		out[i] = xf * (_fish[i]["pos"] as Vector3)
	return out


func _update_nocturnal_biolum() -> void:
	var day := clampf(Weather.daylight(), 0.0, 1.0) if Weather != null else 1.0
	var night_factor := clampf(1.0 - day, 0.0, 1.0)
	var biolum_mix := smoothstep(0.15, 0.92, night_factor)
	_biolum_energy = biolum_mix * BIOLUM_MAX_ENERGY
	if _fish_mat != null and absf(_fish_mat.emission_energy_multiplier - _biolum_energy) > 0.0005:
		_fish_mat.emission_energy_multiplier = _biolum_energy


func _trigger_scatter_bubbles(centroid_local: Vector3, origin_w: Vector3) -> void:
	if _bubbles_mmi == null or not is_instance_valid(_bubbles_mmi) or _bubble_origin.size() != SCATTER_BUBBLE_COUNT:
		return
	if _bubble_rng == null:
		_bubble_rng = RandomNumberGenerator.new()
		_bubble_rng.seed = seed_val ^ 0xB0BB1E5
	var gb := global_transform.basis if is_inside_tree() else transform.basis
	var centroid_world_off := gb * centroid_local
	var sea_y := Sea.height(origin_w.x, origin_w.z) if Sea != null else 0.0
	var max_world_y := minf(sea_y + SCATTER_BUBBLE_MAX_WORLD_Y, SCATTER_BUBBLE_MAX_WORLD_Y)
	var max_local_y := max_world_y - origin_w.y

	for i in SCATTER_BUBBLE_COUNT:
		var rad := _bubble_rng.randf_range(0.08, 0.52)
		var az := float(i) / float(SCATTER_BUBBLE_COUNT) * TAU + _bubble_rng.randf_range(-0.22, 0.22)
		var oy := minf(centroid_world_off.y + _bubble_rng.randf_range(-0.22, 0.14), max_local_y - 0.18)
		var orig := Vector3(centroid_world_off.x + cos(az) * rad, oy, centroid_world_off.z + sin(az) * rad)
		_bubble_origin[i] = orig
		_bubble_pos[i] = orig
		_bubble_rise_speed[i] = _bubble_rng.randf_range(0.72, 1.38)
		_bubble_wobble_phase[i] = _bubble_rng.randf() * TAU
		_bubble_wobble_rad[i] = _bubble_rng.randf_range(0.05, 0.13)
		_bubble_wobble_freq[i] = _bubble_rng.randf_range(3.6, 6.2)
		_bubble_scale[i] = _bubble_rng.randf_range(0.75, 1.35)

	_bubble_burst_elapsed = 0.0
	_bubble_active_ratio = 1.0


func _step_scatter_bubbles(dt: float, origin_w: Vector3) -> void:
	if _bubbles_mmi == null or not is_instance_valid(_bubbles_mmi):
		_bubble_active_ratio = 0.0
		return
	if _bubble_burst_elapsed < 0.0:
		_bubbles_mmi.visible = false
		_bubble_active_ratio = 0.0
		return
	var bmm := _bubbles_mmi.multimesh
	if bmm == null or _bubble_origin.size() != SCATTER_BUBBLE_COUNT:
		_bubble_active_ratio = 0.0
		return

	_bubble_burst_elapsed += maxf(dt, 0.0)
	var u := clampf(_bubble_burst_elapsed / SCATTER_BUBBLE_LIFETIME, 0.0, 1.0)
	if u >= 1.0:
		_bubble_burst_elapsed = -1.0
		_bubble_active_ratio = 0.0
		_bubbles_mmi.visible = false
		return

	if is_inside_tree():
		var gb := global_transform.basis
		if absf(gb.determinant()) > 1e-6:
			_bubbles_mmi.basis = gb.inverse()
		else:
			_bubbles_mmi.basis = Basis.IDENTITY

	var sea_y := Sea.height(origin_w.x, origin_w.z) if Sea != null else 0.0
	var max_world_y := minf(sea_y + SCATTER_BUBBLE_MAX_WORLD_Y, SCATTER_BUBBLE_MAX_WORLD_Y)
	var max_local_y := max_world_y - origin_w.y

	var fade_in := smoothstep(0.0, 0.12, u)
	var fade_out := 1.0 - smoothstep(0.66, 1.0, u)
	var env := clampf(lerpf(0.60, 1.0, fade_in) * fade_out, 0.0, 1.0)
	_bubble_active_ratio = clampf(1.0 - u, 0.0, 1.0)
	_bubbles_mmi.visible = true

	for i in SCATTER_BUBBLE_COUNT:
		var base_p := _bubble_origin[i]
		var ang := _bubble_wobble_phase[i] + _bubble_burst_elapsed * _bubble_wobble_freq[i]
		var wobble := _bubble_wobble_rad[i] * (0.25 + 0.75 * u)
		var bx := base_p.x + cos(ang) * wobble
		var bz := base_p.z + sin(ang) * wobble
		var by := minf(base_p.y + _bubble_rise_speed[i] * _bubble_burst_elapsed, max_local_y)
		var bpos := Vector3(bx, by, bz)
		_bubble_pos[i] = bpos

		var sc := _bubble_scale[i] * lerpf(0.35, 1.0, env)
		var b_basis := Basis(Vector3.UP, ang * 0.65) * Basis.from_scale(Vector3(sc, sc, sc))
		bmm.set_instance_transform(i, Transform3D(b_basis, bpos))
		bmm.set_instance_color(i, Color(0.84, 0.98, 1.00, clampf(0.86 * env, 0.0, 1.0)))


func _find_nearby_swimmer() -> Vector3:
	if not is_inside_tree():
		return Vector3.INF
	var tree := get_tree()
	if tree == null:
		return Vector3.INF
	var origin_w := global_position
	var max_r := school_radius + SCATTER_RADIUS + 4.0
	var best_d2 := max_r * max_r
	var best_pos := Vector3.INF
	for grp: StringName in [&"pawns", &"player"]:
		for node in tree.get_nodes_in_group(grp):
			if not (node is Node3D):
				continue
			if node is Pawn and (node as Pawn).dead:
				continue
			var p_pos := (node as Node3D).global_position + Vector3.UP * 0.6
			var d2 := origin_w.distance_squared_to(p_pos)
			if d2 < best_d2:
				best_d2 = d2
				best_pos = p_pos
	for node in tree.get_nodes_in_group(&"combatants"):
		if node == null or not is_instance_valid(node):
			continue
		var par := node.get_parent() as Pawn
		if par == null or not is_instance_valid(par) or par.dead or not par.is_inside_tree():
			continue
		var p_pos := par.global_position + Vector3.UP * 0.6
		var d2 := origin_w.distance_squared_to(p_pos)
		if d2 < best_d2:
			best_d2 = d2
			best_pos = p_pos
	return best_pos


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_ensure_shared_assets()

	var count := clampi(fish_count, 1, 48)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0x5C001F15

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _fish_mesh
	mm.instance_count = count

	_fish.clear()
	var origin_y := global_position.y if is_inside_tree() else position.y
	var local_max_y := MAX_FISH_Y - origin_y
	var local_hi_y := minf(max_depth_y - origin_y, local_max_y)
	var local_lo_y := minf(min_depth_y - origin_y, local_hi_y - 0.15)
	var depth_span := maxf(0.25, local_hi_y - local_lo_y)

	for i in count:
		var sp_col: Color = SPECIES_PALETTE[i % SPECIES_PALETTE.size()]
		var jitter := rng.randf_range(-0.06, 0.06)
		var inst_col := sp_col.lightened(jitter) if jitter > 0.0 else sp_col.darkened(-jitter)
		mm.set_instance_color(i, inst_col)

		var phase := (float(i) / float(count)) * TAU + rng.randf_range(-0.35, 0.35)
		var orbit_r := school_radius * rng.randf_range(0.42, 1.05)
		var speed := rng.randf_range(0.56, 0.94)
		var fig_blend := rng.randf_range(0.35, 0.90)
		var swirl_yaw := rng.randf_range(-0.55, 0.55)
		var depth_off := lerpf(local_lo_y, local_hi_y, rng.randf())
		depth_off = clampf(depth_off, local_lo_y, local_lo_y + depth_span)

		var init_pos := Vector3(cos(phase) * orbit_r, depth_off, sin(phase) * orbit_r)
		var init_head := Vector3(-sin(phase), 0.0, cos(phase)).normalized()
		_fish.append({
			"orbit_r": orbit_r,
			"speed": speed,
			"phase": phase,
			"fig_blend": fig_blend,
			"swirl_yaw": swirl_yaw,
			"depth_offset": depth_off,
			"scale": rng.randf_range(0.78, 1.28),
			"wag_phase": rng.randf() * TAU,
			"pos": init_pos,
			"heading": init_head,
			"scatter_vel": Vector3.ZERO,
		})

	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "FishSchoolMultiMesh"
	_mmi.multimesh = mm
	_mmi.material_override = _fish_mat
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.visibility_range_end = VISIBILITY_END
	_mmi.visibility_range_end_margin = VISIBILITY_MARGIN
	_mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(_mmi)

	_build_scatter_bubbles()

	# Prime initial fish transforms along their loops.
	step_school(0.0)


func _build_scatter_bubbles() -> void:
	if _bubbles_mmi != null:
		return
	_bubble_rng = RandomNumberGenerator.new()
	_bubble_rng.seed = seed_val ^ 0xB0BB1E5
	_bubble_origin.resize(SCATTER_BUBBLE_COUNT)
	_bubble_pos.resize(SCATTER_BUBBLE_COUNT)
	_bubble_rise_speed.resize(SCATTER_BUBBLE_COUNT)
	_bubble_wobble_phase.resize(SCATTER_BUBBLE_COUNT)
	_bubble_wobble_rad.resize(SCATTER_BUBBLE_COUNT)
	_bubble_wobble_freq.resize(SCATTER_BUBBLE_COUNT)
	_bubble_scale.resize(SCATTER_BUBBLE_COUNT)
	for i in SCATTER_BUBBLE_COUNT:
		_bubble_origin[i] = Vector3.ZERO
		_bubble_pos[i] = Vector3.ZERO
		_bubble_rise_speed[i] = 1.0
		_bubble_wobble_phase[i] = 0.0
		_bubble_wobble_rad[i] = 0.08
		_bubble_wobble_freq[i] = 4.5
		_bubble_scale[i] = 1.0

	var bmm := MultiMesh.new()
	bmm.transform_format = MultiMesh.TRANSFORM_3D
	bmm.use_colors = true
	bmm.use_custom_data = false
	bmm.mesh = _bubble_mesh
	bmm.instance_count = SCATTER_BUBBLE_COUNT
	for i in SCATTER_BUBBLE_COUNT:
		bmm.set_instance_transform(i, Transform3D.IDENTITY)
		bmm.set_instance_color(i, Color(0.84, 0.98, 1.00, 0.0))

	_bubbles_mmi = MultiMeshInstance3D.new()
	_bubbles_mmi.name = "ScatterBubbleBurst"
	_bubbles_mmi.multimesh = bmm
	_bubbles_mmi.material_override = _bubble_mat
	_bubbles_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bubbles_mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_bubbles_mmi.visibility_range_end = VISIBILITY_END
	_bubbles_mmi.visibility_range_end_margin = VISIBILITY_MARGIN
	_bubbles_mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	var half_span := school_radius + 2.5
	_bubbles_mmi.custom_aabb = AABB(Vector3(-half_span, -4.5, -half_span), Vector3(half_span * 2.0, 9.5, half_span * 2.0))
	_bubbles_mmi.visible = false
	_bubble_burst_elapsed = -1.0
	_bubble_cooldown = 0.0
	_bubble_active_ratio = 0.0
	add_child(_bubbles_mmi)


# ==============================================================================
# Sculpted Flat-Faceted Tropical Reef Fish & Scatter Micro-Bubbles (`SurfaceTool`)
# ==============================================================================

static func _ensure_shared_assets() -> void:
	if _fish_mat == null:
		_fish_mat = StandardMaterial3D.new()
		_fish_mat.albedo_color = Color.WHITE
		_fish_mat.vertex_color_use_as_albedo = true
		_fish_mat.vertex_color_is_srgb = true
		_fish_mat.roughness = 0.34
		_fish_mat.metallic = 0.12
		_fish_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_fish_mat.emission_enabled = true
		_fish_mat.emission = BIOLUM_COLOR
		_fish_mat.emission_energy_multiplier = 0.0

	if _fish_mesh == null:
		_fish_mesh = _build_tropical_fish_mesh()

	if _bubble_mesh == null:
		_bubble_mesh = _build_bubble_mesh()

	if _bubble_mat == null:
		_bubble_mat = StandardMaterial3D.new()
		_bubble_mat.albedo_color = Color(0.90, 0.99, 1.00, 0.82)
		_bubble_mat.vertex_color_use_as_albedo = true
		_bubble_mat.vertex_color_is_srgb = true
		_bubble_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_bubble_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_bubble_mat.cull_mode = BaseMaterial3D.CULL_BACK


static func _build_bubble_mesh() -> ArrayMesh:
	# Exact 12-triangle 6-sided faceted silvery-aqua micro-bubble bipyramid (zero SphereMesh).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SIDES := 6
	const R_EQ := 0.056
	const R_POLE := 0.048
	var top := Vector3(0.0, R_POLE, 0.0)
	var bot := Vector3(0.0, -R_POLE, 0.0)
	var ring: Array[Vector3] = []
	for s in SIDES:
		var ang := float(s) / float(SIDES) * TAU
		ring.append(Vector3(cos(ang) * R_EQ, 0.0, sin(ang) * R_EQ))
	for s in SIDES:
		var ns := (s + 1) % SIDES
		_emit_outward_tri(st, ring[s], COL_BUBBLE_MID, top, COL_BUBBLE_TOP, ring[ns], COL_BUBBLE_MID, Vector3.ZERO)
		_emit_outward_tri(st, ring[ns], COL_BUBBLE_MID, bot, COL_BUBBLE_BOT, ring[s], COL_BUBBLE_MID, Vector3.ZERO)
	st.generate_normals()
	return st.commit()


static func _build_tropical_fish_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Neutral bright painterly value mask so per-instance MultiMesh colors paint vivid
	# Royal Butterflyfish gold, Reef Blue Tang cobalt, Coral Anthias tangerine, & Chromis teal.
	var col_top := Color(0.92, 0.94, 0.96)
	var col_flank := Color(1.00, 1.00, 1.00)
	var col_belly := Color(0.96, 0.97, 0.99)
	var col_fin := Color(0.90, 0.92, 0.96)
	var col_gill := Color(0.72, 0.74, 0.80)
	var col_eye := Color(0.08, 0.09, 0.12)

	# 1. Streamlined laterally compressed tropical reef fish body (-Z nose, +Z tail, ~0.31 m).
	# Station: [z, rx, ry, cy, shade_color]
	var stations: Array[Array] = [
		[-0.155, 0.004, 0.009, -0.004, col_top],
		[-0.118, 0.017, 0.044, 0.002, col_flank],
		[-0.058, 0.025, 0.072, 0.006, col_flank],
		[0.004, 0.022, 0.068, 0.004, col_flank],
		[0.058, 0.014, 0.042, 0.000, col_gill],
		[0.092, 0.006, 0.016, 0.000, col_gill],
		[0.104, 0.005, 0.018, 0.000, col_fin],
	]
	var segs := 8
	var rings: Array[Array] = []
	var ring_cols: Array[Array] = []
	for s_row: Array in stations:
		var z: float = float(s_row[0])
		var rx: float = float(s_row[1])
		var ry: float = float(s_row[2])
		var cy: float = float(s_row[3])
		var base_c: Color = s_row[4] as Color
		var r_pts: Array[Vector3] = []
		var r_cls: Array[Color] = []
		for k in segs:
			var a := float(k) / float(segs) * TAU
			var ca := cos(a)
			var sa := sin(a)
			r_pts.append(Vector3(ca * rx, cy + sa * ry, z))
			var vcol := base_c.lerp(col_top if sa > 0.0 else col_belly, absf(sa) * 0.45)
			r_cls.append(vcol)
		rings.append(r_pts)
		ring_cols.append(r_cls)

	for si in range(stations.size() - 1):
		var r0: Array = rings[si]
		var r1: Array = rings[si + 1]
		var c0: Array = ring_cols[si]
		var c1: Array = ring_cols[si + 1]
		var mid_z := (float(stations[si][0]) + float(stations[si + 1][0])) * 0.5
		var mid_c := Vector3(0.0, 0.0, mid_z)
		for k in segs:
			var nk := (k + 1) % segs
			_emit_outward_quad(st,
				r0[k] as Vector3, c0[k] as Color,
				r1[k] as Vector3, c1[k] as Color,
				r1[nk] as Vector3, c1[nk] as Color,
				r0[nk] as Vector3, c0[nk] as Color,
				mid_c)

	# Cap nose tip and tail stem cleanly.
	var nose_tip := Vector3(0.0, -0.004, -0.162)
	var tail_hub := Vector3(0.0, 0.0, 0.106)
	for k in segs:
		var nk := (k + 1) % segs
		_emit_outward_tri(st, nose_tip, col_top,
			rings[0][k] as Vector3, ring_cols[0][k] as Color,
			rings[0][nk] as Vector3, ring_cols[0][nk] as Color,
			Vector3(0.0, 0.0, -0.08))
		_emit_outward_tri(st, tail_hub, col_fin,
			rings[rings.size() - 1][nk] as Vector3, ring_cols[rings.size() - 1][nk] as Color,
			rings[rings.size() - 1][k] as Vector3, ring_cols[rings.size() - 1][k] as Color,
			Vector3(0.0, 0.0, 0.04))

	# 2. Swept Dorsal Fin crest along spine (+Y).
	var d_b0 := Vector3(0.0, 0.068, -0.064)
	var d_b1 := Vector3(0.0, 0.066, 0.008)
	var d_b2 := Vector3(0.0, 0.036, 0.072)
	var d_t0 := Vector3(0.0, 0.116, -0.012)
	var d_t1 := Vector3(0.0, 0.102, 0.062)
	var d_t2 := Vector3(0.0, 0.062, 0.098)
	_emit_fin_quad(st, d_b0, d_b1, d_t1, d_t0, col_fin, col_top)
	_emit_fin_quad(st, d_b1, d_b2, d_t2, d_t1, col_fin, col_top)

	# 3. Swept Pelvic / Anal Ventral Fin (-Y).
	var v_b0 := Vector3(0.0, -0.060, -0.030)
	var v_b1 := Vector3(0.0, -0.056, 0.020)
	var v_b2 := Vector3(0.0, -0.034, 0.074)
	var v_t0 := Vector3(0.0, -0.096, 0.010)
	var v_t1 := Vector3(0.0, -0.082, 0.072)
	_emit_fin_quad(st, v_b0, v_b1, v_t0, v_t0 + Vector3(0.0, 0.008, -0.022), col_fin, col_belly)
	_emit_fin_quad(st, v_b1, v_b2, v_t1, v_t0, col_fin, col_belly)

	# 4. Twin Pectoral Side Fins splayed slightly out & aft from gill flanks.
	for sgn: float in [-1.0, 1.0]:
		var p_root_f := Vector3(sgn * 0.022, -0.006, -0.058)
		var p_root_b := Vector3(sgn * 0.020, -0.014, -0.026)
		var p_tip_f := Vector3(sgn * 0.068, -0.020, -0.018)
		var p_tip_b := Vector3(sgn * 0.058, -0.034, 0.012)
		_emit_fin_quad(st, p_root_f, p_root_b, p_tip_b, p_tip_f, col_fin, col_flank)

	# 5. Expressive Forked Caudal Tail Fin (+Z swallowtail).
	var c_top_root := Vector3(0.0, 0.016, 0.098)
	var c_mid_root := Vector3(0.0, 0.000, 0.102)
	var c_bot_root := Vector3(0.0, -0.016, 0.098)
	var c_notch := Vector3(0.0, 0.000, 0.128)
	var c_up_tip := Vector3(0.0, 0.072, 0.162)
	var c_lo_tip := Vector3(0.0, -0.072, 0.162)
	_emit_fin_quad(st, c_top_root, c_mid_root, c_notch, c_up_tip, col_fin, col_top)
	_emit_fin_quad(st, c_mid_root, c_bot_root, c_lo_tip, c_notch, col_fin, col_top)

	# 6. Tiny dark faceted eye gems on both sides of head.
	for sgn: float in [-1.0, 1.0]:
		var ec := Vector3(sgn * 0.018, 0.018, -0.104)
		var apex := ec + Vector3(sgn * 0.005, 0.0, 0.0)
		var er := 0.0085
		var e_ring: Array[Vector3] = [
			ec + Vector3(0.0, er, 0.0),
			ec + Vector3(0.0, 0.0, -er),
			ec + Vector3(0.0, -er, 0.0),
			ec + Vector3(0.0, 0.0, er),
		]
		for k in 4:
			var nk := (k + 1) % 4
			_emit_outward_tri(st, apex, col_eye, e_ring[k], col_eye, e_ring[nk], col_eye, Vector3(0.0, 0.018, -0.104))

	st.generate_normals()
	return st.commit()


static func _emit_fin_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		col_root: Color, col_tip: Color) -> void:
	_emit_flat_tri(st, a, col_root, b, col_root, c, col_tip)
	_emit_flat_tri(st, a, col_root, c, col_tip, d, col_tip)


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


static func _emit_outward_quad(st: SurfaceTool, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color, d: Vector3, cd: Color,
		ref_center: Vector3) -> void:
	_emit_outward_tri(st, a, ca, b, cb, c, cc, ref_center)
	_emit_outward_tri(st, a, ca, c, cc, d, cd, ref_center)
