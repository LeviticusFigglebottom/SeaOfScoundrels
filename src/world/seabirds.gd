class_name SeabirdFlock
extends Node3D
## Living-world seabird flock marking shipwrecks, flotsam, dig sites, and harbours.
##
## Spawns a flock of 4-7 chunky painterly procedural 3D seagulls with sculpted cream-white
## bodies, golden hooked beaks, forked tails, slate-blue wingtips, and articulated
## pivoting wings (`WingL`, `WingR`) that smoothly alternate between rhythmic flapping
## bursts and banked gliding turns in staggered elliptical orbits.

const GROUP := &"seabird_flocks"
const LOOT_MARKER_GROUP := &"loot_markers"
const WING_CULL_DISTANCE := 320.0
const CRY_HEAR_DISTANCE := 210.0
const SHIP_ESCORT_ENTER_DIST := 135.0
const SHIP_ESCORT_EXIT_DIST := 240.0
const SHIP_ESCORT_MIN_SPEED := 1.6
const SHIP_ESCORT_EXIT_SPEED := 0.75
const SHIP_ESCORT_MAX_BIRDS := 2
const SHIP_ESCORT_SCAN_INTERVAL := 0.25
const SHIP_ESCORT_BLEND_TIME := 1.8

# Painterly sunlit coastal gull palette.
const COL_BODY_WHITE := Color(0.97, 0.95, 0.90)
const COL_BELLY_SHADE := Color(0.80, 0.84, 0.88)
const COL_MANTLE_PEARL := Color(0.76, 0.82, 0.87)
const COL_WING_SLATE := Color(0.42, 0.52, 0.64)
const COL_WING_TIP := Color(0.16, 0.21, 0.28)
const COL_TAIL_BAND := Color(0.22, 0.27, 0.35)
const COL_BEAK_GOLD := Color(0.96, 0.72, 0.14)
const COL_BEAK_SPOT := Color(0.88, 0.24, 0.14)
const COL_FEET_AMBER := Color(0.90, 0.54, 0.16)
const COL_EYE_DARK := Color(0.08, 0.09, 0.11)

@export_range(1, 12, 1) var bird_count: int = 5
@export var orbit_radius: float = 14.0
@export var orbit_height: float = 16.0
@export var is_loot_marker: bool = true
@export var bird_scale: float = 1.35
@export var flock_seed: int = 0

## True during the most recent tick when wing updates were culled (> 320 m from camera).
var wing_anim_culled: bool = false

var _birds: Array[Dictionary] = []
var _body_mesh: ArrayMesh = null
var _wing_l_mesh: ArrayMesh = null
var _wing_r_mesh: ArrayMesh = null
var _plumage_mat: StandardMaterial3D = null
var _rng := RandomNumberGenerator.new()
var _cry_timer: float = 4.5
var _clock: float = 0.0
var _escort_ship: Node3D = null
var _escort_scan_timer: float = 0.0
var _escort_last_ship_pos: Vector3 = Vector3.ZERO
var _escort_last_ship_aft: Vector3 = Vector3.BACK
var _escort_last_ship_right: Vector3 = Vector3.RIGHT
var _escort_last_ship_vel: Vector3 = Vector3.ZERO
var _has_escort_anchor: bool = false


## Spawn a configured circling gull flock anchored above `world_pos`.
static func spawn_over(parent: Node, world_pos: Vector3, radius: float = 14.0,
		height: float = 16.0, count: int = 5) -> SeabirdFlock:
	var flock := SeabirdFlock.new()
	flock.name = "SeabirdFlock"
	flock.orbit_radius = maxf(radius, 3.0)
	flock.orbit_height = maxf(height, 4.0)
	flock.bird_count = maxi(count, 1)
	flock.is_loot_marker = true
	var seed_hash := hash(Vector3i(
		int(roundf(world_pos.x * 2.0)),
		int(roundf(world_pos.y * 2.0)),
		int(roundf(world_pos.z * 2.0))
	))
	flock.flock_seed = seed_hash if seed_hash != 0 else 0x6011B1D
	if parent != null:
		parent.add_child(flock)
	flock.global_position = world_pos
	return flock


func _enter_tree() -> void:
	add_to_group(GROUP)
	if is_loot_marker:
		add_to_group(LOOT_MARKER_GROUP)


func _exit_tree() -> void:
	_escort_ship = null
	_has_escort_anchor = false


func _ready() -> void:
	if flock_seed != 0:
		_rng.seed = flock_seed
	else:
		var pos_hash := hash(Vector3i(
			int(roundf(global_position.x * 2.0)),
			int(roundf(global_position.y * 2.0)),
			int(roundf(global_position.z * 2.0))
		))
		_rng.seed = pos_hash if pos_hash != 0 else 0x6011B1D
	_cry_timer = _rng.randf_range(3.5, 9.5)
	_build_shared_assets()
	_spawn_flock()
	step_flock(0.0)


## Return all spawned gull root nodes in this flock.
func get_birds() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for entry in _birds:
		var root := entry["root"] as Node3D
		if root != null and is_instance_valid(root):
			out.append(root)
	return out


## Return the number of gulls actively riding a nearby ship's slipstream (blend >= 0.45).
func get_escorting_bird_count() -> int:
	var n := 0
	for entry in _birds:
		if float(entry.get("escort_blend", 0.0)) >= 0.45:
			n += 1
	return n


## Return the currently escorted sailing ship (or null when no moving ship is in escort range).
func get_escort_target_ship() -> Node3D:
	if _escort_ship != null and is_instance_valid(_escort_ship) and _escort_ship.is_inside_tree():
		return _escort_ship
	return null


## Return the current 0..1 slipstream escort blend weight for bird `idx` (0.0 if out of bounds).
func get_bird_escort_blend(idx: int) -> float:
	if idx < 0 or idx >= _birds.size():
		return 0.0
	return float(_birds[idx].get("escort_blend", 0.0))


func _process(delta: float) -> void:
	step_flock(delta)


## Advance bird orbits, ship-following slipstream escorts, banking rolls, flapping/gliding, and gull cries.
func step_flock(delta: float) -> void:
	if _birds.is_empty():
		return
	var dt := clampf(delta, 0.0, 0.15)
	_clock += dt

	_escort_scan_timer -= dt
	var target_invalid := _escort_ship != null and (not is_instance_valid(_escort_ship) or not _escort_ship.is_inside_tree())
	if dt <= 0.0 or target_invalid or _escort_scan_timer <= 0.0:
		_escort_scan_timer = SHIP_ESCORT_SCAN_INTERVAL
		_update_escort_target()
	if _escort_ship != null:
		_sync_escort_anchor()

	var cam := get_viewport().get_camera_3d() if is_inside_tree() and get_viewport() != null else null
	var cam_dist_sq := 0.0
	if cam != null:
		var flock_center := global_position + Vector3(0.0, orbit_height, 0.0)
		cam_dist_sq = flock_center.distance_squared_to(cam.global_position)
	wing_anim_culled = cam != null and cam_dist_sq > WING_CULL_DISTANCE * WING_CULL_DISTANCE

	var wind_drift := Vector3.ZERO
	if Weather != null:
		var wv := Weather.mean_wind_vector()
		wind_drift = Vector3(wv.x, 0.0, wv.z) * 0.08

	var escort_slots := mini(SHIP_ESCORT_MAX_BIRDS, maxi(1, _birds.size() - 2))
	if _birds.size() <= 2:
		escort_slots = mini(escort_slots, maxi(0, _birds.size() - 1))
	var any_blended := false
	var ship_vel_local := Vector3.ZERO
	if _escort_ship != null:
		ship_vel_local = global_basis.inverse() * _escort_last_ship_vel if is_inside_tree() else _escort_last_ship_vel

	for i in _birds.size():
		var entry: Dictionary = _birds[i]
		var root := entry["root"] as Node3D
		if root == null or not is_instance_valid(root):
			continue

		var angle: float = float(entry["angle"])
		var angular_speed: float = float(entry["angular_speed"])
		var dir_sign: float = float(entry["dir_sign"])
		angle = wrapf(angle + angular_speed * dir_sign * dt, 0.0, TAU)
		entry["angle"] = angle

		var escort_blend: float = float(entry["escort_blend"])
		var want_escort := (_escort_ship != null) and (i < escort_slots)
		if dt > 0.0:
			var goal_escort := 1.0 if want_escort else 0.0
			escort_blend = move_toward(escort_blend, goal_escort, dt / SHIP_ESCORT_BLEND_TIME)
			entry["escort_blend"] = escort_blend
		if escort_blend > 0.0001:
			any_blended = true

		var prev_pos := _orbit_local_pos(entry, angle - angular_speed * dir_sign * 0.04, wind_drift)
		var orbit_pos := _orbit_local_pos(entry, angle, wind_drift)
		var next_pos := _orbit_local_pos(entry, angle + angular_speed * dir_sign * 0.04, wind_drift)
		var cur_pos := orbit_pos
		var vel := (next_pos - prev_pos) / 0.08

		if escort_blend > 0.0001 and _has_escort_anchor:
			var smooth_b := smoothstep(0.0, 1.0, escort_blend)
			var escort_pos := _escort_local_pos(entry, _clock)
			cur_pos = orbit_pos.lerp(escort_pos, smooth_b)
			if escort_blend >= 0.98 and _escort_ship != null:
				var e_prev := _escort_local_pos(entry, _clock - 0.04)
				var e_next := _escort_local_pos(entry, _clock + 0.04)
				vel = ship_vel_local + (e_next - e_prev) / 0.08
			elif dt > 0.0001 and bool(entry["has_prev_pos"]):
				vel = (cur_pos - (entry["prev_pos"] as Vector3)) / dt
				if _escort_ship != null and Vector2(vel.x, vel.z).length() < 1.0:
					vel += ship_vel_local * smooth_b

		root.position = cur_pos
		entry["prev_pos"] = cur_pos
		entry["has_prev_pos"] = true

		var horiz_len := Vector2(vel.x, vel.z).length()
		var yaw: float = float(entry["yaw"])
		var yaw_rate := 0.0
		if horiz_len > 0.01:
			var target_yaw := atan2(-vel.x, -vel.z)
			if bool(entry["has_yaw"]) and dt > 0.0001:
				var next_yaw := target_yaw
				if escort_blend > 0.0001:
					next_yaw = lerp_angle(yaw, target_yaw, clampf(dt * 5.0, 0.0, 1.0))
				var dyaw := wrapf(next_yaw - yaw, -PI, PI)
				yaw_rate = dyaw / dt
				yaw = next_yaw
			else:
				# Analytical curvature yaw rate on first tick so banking is immediate.
				yaw_rate = dir_sign * angular_speed
				yaw = target_yaw
			entry["yaw"] = yaw
			entry["has_yaw"] = true

		var pitch := clampf(atan2(vel.y, maxf(horiz_len, 0.5)), -0.32, 0.32)
		var target_bank := clampf(yaw_rate * 0.85, -0.58, 0.58)
		var bank: float = lerpf(float(entry["bank"]), target_bank, clampf(dt * 4.5, 0.0, 1.0)) if dt > 0.0 else target_bank
		entry["bank"] = bank

		root.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, bank)

		# Distance-cull wing flap updates beyond 320 m from the active camera.
		if wing_anim_culled:
			continue

		var mode_timer: float = float(entry["mode_timer"]) - dt
		var flapping: bool = bool(entry["flapping"])
		if mode_timer <= 0.0:
			flapping = not flapping
			entry["flapping"] = flapping
			if escort_blend > 0.35:
				# Escort gulls ride the vessel's masthead updraft in longer soaring glides.
				mode_timer = _rng.randf_range(0.9, 1.6) if flapping else _rng.randf_range(4.2, 6.8)
			else:
				mode_timer = _rng.randf_range(1.8, 3.1) if flapping else _rng.randf_range(2.6, 4.6)
		entry["mode_timer"] = mode_timer

		var flap_blend: float = float(entry["flap_blend"])
		var goal_blend := 1.0 if flapping else 0.0
		flap_blend = move_toward(flap_blend, goal_blend, dt * 2.4)
		entry["flap_blend"] = flap_blend

		var flap_freq: float = float(entry["flap_freq"])
		var flap_phase: float = float(entry["flap_phase"]) + dt * flap_freq * TAU
		entry["flap_phase"] = flap_phase

		# Rhythmic downstroke/upstroke mixed smoothly into a gentle banked gull dihedral glide.
		var raw_flap := sin(flap_phase) * 0.58 - 0.06
		var glide_dihedral := 0.14 + absf(bank) * 0.12 + 0.05 * escort_blend
		var wing_roll := lerpf(glide_dihedral, raw_flap, flap_blend)
		var wing_pitch := cos(flap_phase) * 0.14 * flap_blend

		var wing_l := entry["wing_l"] as Node3D
		var wing_r := entry["wing_r"] as Node3D
		if wing_l != null:
			wing_l.rotation = Vector3(wing_pitch, 0.0, -wing_roll)
		if wing_r != null:
			wing_r.rotation = Vector3(wing_pitch, 0.0, wing_roll)

	if _escort_ship == null and not any_blended:
		_has_escort_anchor = false

	# Subtle periodic distant gull cries if the sound exists in Audio.catalogue.
	if dt > 0.0:
		_cry_timer -= dt
		if _cry_timer <= 0.0:
			_cry_timer = _rng.randf_range(7.0, 14.5)
			if (cam == null or cam_dist_sq <= CRY_HEAR_DISTANCE * CRY_HEAR_DISTANCE) and _has_gull_sfx():
				var idx := _rng.randi_range(0, _birds.size() - 1)
				var caller := _birds[idx]["root"] as Node3D
				if caller != null and is_instance_valid(caller):
					Audio.play_sfx(&"seagull", caller.global_position, -4.5, 0.11)


static func _ship_horizontal_velocity(node: Node3D) -> Vector3:
	var vel_v: Variant = node.get(&"linear_velocity")
	if vel_v is Vector3:
		var v := vel_v as Vector3
		return Vector3(v.x, 0.0, v.z)
	return Vector3.ZERO


static func _is_ship_sinking(node: Node3D) -> bool:
	var sinking_v: Variant = node.get(&"is_sinking")
	return sinking_v is bool and bool(sinking_v)


func _update_escort_target() -> void:
	if not is_inside_tree():
		_escort_ship = null
		return
	var tree := get_tree()
	if tree == null:
		_escort_ship = null
		return
	var my_pos := global_position

	# Keep current escort target while inside exit distance and above hysteresis exit speed.
	if _escort_ship != null:
		if not is_instance_valid(_escort_ship) or not _escort_ship.is_inside_tree() or _is_ship_sinking(_escort_ship):
			_escort_ship = null
		else:
			var sp := _escort_ship.global_position
			var horiz_d := Vector2(sp.x - my_pos.x, sp.z - my_pos.z).length()
			var spd := _ship_horizontal_velocity(_escort_ship).length()
			if horiz_d > SHIP_ESCORT_EXIT_DIST or spd < SHIP_ESCORT_EXIT_SPEED:
				_escort_ship = null

	# When unengaged, acquire the closest active sailing ship within SHIP_ESCORT_ENTER_DIST.
	if _escort_ship == null:
		var best: Node3D = null
		var best_d := SHIP_ESCORT_ENTER_DIST
		for grp: StringName in [&"ship", &"ships"]:
			for node in tree.get_nodes_in_group(grp):
				var candidate := node as Node3D
				if candidate == null or not is_instance_valid(candidate) or not candidate.is_inside_tree():
					continue
				if _is_ship_sinking(candidate):
					continue
				var spd := _ship_horizontal_velocity(candidate).length()
				if spd < SHIP_ESCORT_MIN_SPEED:
					continue
				var cp := candidate.global_position
				var d := Vector2(cp.x - my_pos.x, cp.z - my_pos.z).length()
				if d <= best_d:
					best_d = d
					best = candidate
		_escort_ship = best


func _sync_escort_anchor() -> void:
	if _escort_ship == null or not is_instance_valid(_escort_ship) or not _escort_ship.is_inside_tree():
		return
	_escort_last_ship_pos = _escort_ship.global_position
	var hv := _ship_horizontal_velocity(_escort_ship)
	_escort_last_ship_vel = hv
	var aft := Vector3.ZERO
	if hv.length_squared() > 0.04:
		aft = -hv.normalized()
	else:
		var bz := _escort_ship.global_basis.z
		aft = Vector3(bz.x, 0.0, bz.z)
		aft = aft.normalized() if aft.length_squared() > 0.001 else Vector3.BACK
	_escort_last_ship_aft = aft
	var rt := Vector3.UP.cross(aft)
	_escort_last_ship_right = rt.normalized() if rt.length_squared() > 0.001 else Vector3.RIGHT
	_has_escort_anchor = true


func _escort_local_pos(entry: Dictionary, t: float) -> Vector3:
	var aft_dist: float = float(entry["escort_aft"])
	var lat_amp: float = float(entry["escort_lat"])
	var base_h: float = float(entry["escort_height"])
	var phase: float = float(entry["escort_phase"]) + t * float(entry["escort_freq"])
	var bob: float = sin(t * float(entry["bob_freq"]) + float(entry["bob_phase"])) * float(entry["bob_amp"]) * 0.65
	var world_pos := _escort_last_ship_pos \
		+ _escort_last_ship_aft * aft_dist \
		+ _escort_last_ship_right * (sin(phase) * lat_amp) \
		+ Vector3.UP * (base_h + bob)
	if is_inside_tree():
		return to_local(world_pos)
	return world_pos - position


func _orbit_local_pos(entry: Dictionary, angle: float, wind_drift: Vector3) -> Vector3:
	var rx: float = float(entry["rx"])
	var rz: float = float(entry["rz"])
	var ellipse_rot: float = float(entry["ellipse_rot"])
	var base_y: float = float(entry["base_y"])
	var bob_amp: float = float(entry["bob_amp"])
	var bob_freq: float = float(entry["bob_freq"])
	var bob_phase: float = float(entry["bob_phase"])

	var lx := cos(angle) * rx
	var lz := sin(angle) * rz
	var cr := cos(ellipse_rot)
	var sr := sin(ellipse_rot)
	var px := lx * cr - lz * sr
	var pz := lx * sr + lz * cr
	var py := base_y + sin(_clock * bob_freq + bob_phase) * bob_amp + sin(angle * 2.0 + bob_phase) * (bob_amp * 0.45)
	var sway := sin(_clock * 0.28 + bob_phase) * 1.4
	return Vector3(px + wind_drift.x * sway, py, pz + wind_drift.z * sway)


func _has_gull_sfx() -> bool:
	if Audio == null:
		return false
	var sfx_section: Variant = Audio.catalogue.get("sfx", null)
	if not (sfx_section is Dictionary):
		return false
	if not (sfx_section as Dictionary).has("seagull"):
		return false
	return Audio.has_sound(&"seagull")


func _spawn_flock() -> void:
	_birds.clear()
	var count := maxi(bird_count, 1)
	var base_dir := 1.0 if _rng.randf() > 0.5 else -1.0
	var scale_mult := bird_scale * (1.08 if is_loot_marker else 1.0)
	var seed_abs := absi(flock_seed)

	for i in count:
		var gull := Node3D.new()
		gull.name = "Gull_%d" % i
		var s := scale_mult * _rng.randf_range(0.90, 1.14)
		gull.scale = Vector3(s, s, s)

		var body_mi := MeshInstance3D.new()
		body_mi.name = "Body"
		body_mi.mesh = _body_mesh
		body_mi.material_override = _plumage_mat
		body_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gull.add_child(body_mi)

		var wing_l := Node3D.new()
		wing_l.name = "WingL"
		wing_l.position = Vector3(-0.13, 0.045, -0.05)
		var wl_mi := MeshInstance3D.new()
		wl_mi.name = "WingLMesh"
		wl_mi.mesh = _wing_l_mesh
		wl_mi.material_override = _plumage_mat
		wl_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wing_l.add_child(wl_mi)
		gull.add_child(wing_l)

		var wing_r := Node3D.new()
		wing_r.name = "WingR"
		wing_r.position = Vector3(0.13, 0.045, -0.05)
		var wr_mi := MeshInstance3D.new()
		wr_mi.name = "WingRMesh"
		wr_mi.mesh = _wing_r_mesh
		wr_mi.material_override = _plumage_mat
		wr_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wing_r.add_child(wr_mi)
		gull.add_child(wing_r)

		add_child(gull)

		var radius_var := orbit_radius * _rng.randf_range(0.76, 1.24)
		var ecc := _rng.randf_range(0.74, 1.18)
		var speed_mps := _rng.randf_range(6.2, 8.4)
		var ang_spd := speed_mps / maxf(radius_var, 4.0)
		var start_flapping := (i % 2 == 0)

		# Deterministic slipstream offsets derived without altering the home-orbit RNG stream.
		var escort_aft := 11.0 + fposmod(float(i) * 5.7 + float(seed_abs % 17) * 0.35, 12.0)
		var escort_lat := 5.5 + fposmod(float(i) * 2.1 + float(seed_abs % 13) * 0.25, 4.0)
		var escort_height := 8.5 + fposmod(float(i) * 2.4 + float(seed_abs % 11) * 0.35, 5.5)
		var escort_phase := float(i) * PI + fposmod(float(seed_abs % 29) * 0.22, TAU)
		var escort_freq := 0.55 + fposmod(float(i) * 0.17, 0.25)

		_birds.append({
			"root": gull,
			"wing_l": wing_l,
			"wing_r": wing_r,
			"angle": (float(i) / float(count)) * TAU + _rng.randf_range(-0.35, 0.35),
			"angular_speed": ang_spd,
			"dir_sign": base_dir,
			"rx": radius_var,
			"rz": radius_var * ecc,
			"ellipse_rot": _rng.randf_range(-0.45, 0.45),
			"base_y": orbit_height + _rng.randf_range(-2.6, 3.2),
			"bob_amp": _rng.randf_range(0.65, 1.45),
			"bob_freq": _rng.randf_range(0.45, 0.85),
			"bob_phase": _rng.randf_range(0.0, TAU),
			"flapping": start_flapping,
			"flap_blend": 1.0 if start_flapping else 0.0,
			"flap_phase": _rng.randf_range(0.0, TAU),
			"flap_freq": _rng.randf_range(3.6, 4.8),
			"mode_timer": _rng.randf_range(1.2, 3.6),
			"yaw": 0.0,
			"has_yaw": false,
			"bank": 0.0,
			"escort_blend": 0.0,
			"escort_aft": escort_aft,
			"escort_lat": escort_lat,
			"escort_height": escort_height,
			"escort_phase": escort_phase,
			"escort_freq": escort_freq,
			"prev_pos": Vector3.ZERO,
			"has_prev_pos": false,
		})


# ------------------------------------------------------------------ procedural meshes

func _build_shared_assets() -> void:
	_plumage_mat = StandardMaterial3D.new()
	_plumage_mat.vertex_color_use_as_albedo = true
	_plumage_mat.vertex_color_is_srgb = true
	_plumage_mat.roughness = 0.72
	_plumage_mat.metallic = 0.0

	_body_mesh = _build_gull_body_mesh()
	_wing_l_mesh = _build_gull_wing_mesh(-1.0)
	_wing_r_mesh = _build_gull_wing_mesh(1.0)


static func _build_gull_body_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Chunky sculpted gull fuselage (-Z chest/head, +Z tapered rump).
	# Station format: [z, y_center, rx, ry_top, ry_bot, top_color, bot_color]
	var stations: Array[Array] = [
		[-0.56, 0.09, 0.055, 0.055, 0.048, COL_BODY_WHITE, COL_BODY_WHITE],   # Crown / forehead
		[-0.44, 0.095, 0.095, 0.092, 0.078, COL_BODY_WHITE, COL_BODY_WHITE],  # Head widest
		[-0.30, 0.04, 0.092, 0.088, 0.085, COL_BODY_WHITE, COL_BODY_WHITE],   # Chunky neck
		[-0.14, 0.01, 0.165, 0.135, 0.145, COL_MANTLE_PEARL, COL_BODY_WHITE], # Broad breast
		[0.08, 0.02, 0.155, 0.125, 0.130, COL_MANTLE_PEARL, COL_BELLY_SHADE], # Mid torso
		[0.28, 0.04, 0.095, 0.082, 0.075, COL_MANTLE_PEARL, COL_BELLY_SHADE], # Tapered rump
		[0.44, 0.055, 0.052, 0.036, 0.032, COL_BODY_WHITE, COL_BELLY_SHADE],  # Tail root
	]
	_append_body_loft(st, stations, 8)

	# 2. Golden hooked beak protruding forward along -Z with coastal red lower spot.
	var beak_base := Vector3(0.0, 0.082, -0.56)
	var beak_mid := Vector3(0.0, 0.072, -0.71)
	var beak_tip := Vector3(0.0, 0.038, -0.78)
	var b_top := beak_base + Vector3(0.0, 0.036, 0.0)
	var b_bot := beak_base + Vector3(0.0, -0.026, 0.0)
	var b_l := beak_base + Vector3(-0.036, 0.0, 0.0)
	var b_r := beak_base + Vector3(0.036, 0.0, 0.0)
	var m_top := beak_mid + Vector3(0.0, 0.024, 0.0)
	var m_bot := beak_mid + Vector3(0.0, -0.020, 0.0)
	var m_l := beak_mid + Vector3(-0.022, 0.0, 0.0)
	var m_r := beak_mid + Vector3(0.022, 0.0, 0.0)
	var b_center := Vector3(0.0, 0.075, -0.64)
	_add_outward_quad(st, b_top, m_top, m_r, b_r, b_center, COL_BEAK_GOLD)
	_add_outward_quad(st, b_l, m_l, m_top, b_top, b_center, COL_BEAK_GOLD)
	_add_outward_quad(st, b_r, m_r, m_bot, b_bot, b_center, COL_BEAK_SPOT)
	_add_outward_quad(st, b_bot, m_bot, m_l, b_l, b_center, COL_BEAK_SPOT)
	# Hooked tip pyramid.
	var tip_center := Vector3(0.0, 0.062, -0.73)
	_add_outward_tri(st, m_top, beak_tip, m_r, tip_center, COL_BEAK_GOLD, COL_BEAK_GOLD, COL_BEAK_GOLD)
	_add_outward_tri(st, m_l, beak_tip, m_top, tip_center, COL_BEAK_GOLD, COL_BEAK_GOLD, COL_BEAK_GOLD)
	_add_outward_tri(st, m_r, beak_tip, m_bot, tip_center, COL_BEAK_GOLD, COL_BEAK_SPOT, COL_BEAK_SPOT)
	_add_outward_tri(st, m_bot, beak_tip, m_l, tip_center, COL_BEAK_SPOT, COL_BEAK_SPOT, COL_BEAK_GOLD)

	# 3. Expressive dark bead eyes on left & right head cheeks.
	for sg: float in [-1.0, 1.0]:
		_append_faceted_gem(st, Vector3(sg * 0.082, 0.115, -0.47), Vector3(0.026, 0.026, 0.028), COL_EYE_DARK)

	# 4. Forked fan tail (+Z) with dark slate subterminal band & crisp V-notch.
	var tail_root_l := Vector3(-0.048, 0.062, 0.42)
	var tail_root_r := Vector3(0.048, 0.062, 0.42)
	var tail_root_c := Vector3(0.0, 0.068, 0.42)
	var tail_bot_c := Vector3(0.0, 0.036, 0.43)
	var fork_mid := Vector3(0.0, 0.062, 0.63)
	var tip_l := Vector3(-0.22, 0.072, 0.78)
	var tip_r := Vector3(0.22, 0.072, 0.78)
	var mid_l := Vector3(-0.14, 0.068, 0.62)
	var mid_r := Vector3(0.14, 0.068, 0.62)
	var tail_ctr := Vector3(0.0, 0.045, 0.58)
	# Upper fan (white inner -> slate-band outer prongs).
	_add_outward_tri(st, tail_root_l, tail_root_c, mid_l, tail_ctr, COL_BODY_WHITE, COL_BODY_WHITE, COL_BODY_WHITE)
	_add_outward_tri(st, tail_root_c, fork_mid, mid_l, tail_ctr, COL_BODY_WHITE, COL_BODY_WHITE, COL_BODY_WHITE)
	_add_outward_tri(st, tail_root_c, tail_root_r, mid_r, tail_ctr, COL_BODY_WHITE, COL_BODY_WHITE, COL_BODY_WHITE)
	_add_outward_tri(st, tail_root_c, mid_r, fork_mid, tail_ctr, COL_BODY_WHITE, COL_BODY_WHITE, COL_BODY_WHITE)
	_add_outward_tri(st, mid_l, fork_mid, tip_l, tail_ctr, COL_TAIL_BAND, COL_TAIL_BAND, COL_WING_TIP)
	_add_outward_tri(st, fork_mid, mid_r, tip_r, tail_ctr, COL_TAIL_BAND, COL_TAIL_BAND, COL_WING_TIP)
	# Underside tail wedge for solid 3D silhouette from below.
	var under_ctr := Vector3(0.0, 0.09, 0.58)
	_add_outward_tri(st, tail_root_l, tail_bot_c, tip_l, under_ctr, COL_BELLY_SHADE, COL_BELLY_SHADE, COL_TAIL_BAND)
	_add_outward_tri(st, tail_bot_c, fork_mid, tip_l, under_ctr, COL_BELLY_SHADE, COL_BELLY_SHADE, COL_TAIL_BAND)
	_add_outward_tri(st, tail_bot_c, tail_root_r, tip_r, under_ctr, COL_BELLY_SHADE, COL_BELLY_SHADE, COL_TAIL_BAND)
	_add_outward_tri(st, tail_bot_c, tip_r, fork_mid, under_ctr, COL_BELLY_SHADE, COL_TAIL_BAND, COL_BELLY_SHADE)

	# 5. Tucked golden-orange webbed feet under rear belly.
	for sg: float in [-1.0, 1.0]:
		_append_faceted_gem(st, Vector3(sg * 0.055, -0.082, 0.22), Vector3(0.032, 0.022, 0.085), COL_FEET_AMBER)

	return st.commit()


## Build a chunky 3D cambered gull wing extending along `side_sign` (-1 left, +1 right).
static func _build_gull_wing_mesh(side_sign: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 4 span stations from shoulder root (x = 0) to swept slate-blue primary wingtip.
	# Format: [span_x, y_off, z_lead, z_trail, thick_up, thick_dn, top_col, bot_col]
	var ribs: Array[Array] = [
		[0.00, 0.00, -0.18, 0.17, 0.048, 0.022, COL_BODY_WHITE, COL_BODY_WHITE],
		[0.36, 0.06, -0.22, 0.14, 0.036, 0.016, COL_MANTLE_PEARL, COL_BODY_WHITE],
		[0.72, 0.01, -0.12, 0.16, 0.024, 0.010, COL_WING_SLATE, COL_BELLY_SHADE],
		[1.04, -0.05, 0.06, 0.24, 0.012, 0.006, COL_WING_TIP, COL_TAIL_BAND],
	]

	for i in range(ribs.size() - 1):
		var a: Array = ribs[i]
		var b: Array = ribs[i + 1]
		var xa: float = side_sign * float(a[0])
		var xb: float = side_sign * float(b[0])
		var ya: float = float(a[1])
		var yb: float = float(b[1])

		var a_lead := Vector3(xa, ya, float(a[2]))
		var a_trail := Vector3(xa, ya - 0.005, float(a[3]))
		var a_mid_z: float = lerpf(float(a[2]), float(a[3]), 0.38)
		var a_top := Vector3(xa, ya + float(a[4]), a_mid_z)
		var a_bot := Vector3(xa, ya - float(a[5]), a_mid_z)

		var b_lead := Vector3(xb, yb, float(b[2]))
		var b_trail := Vector3(xb, yb - 0.005, float(b[3]))
		var b_mid_z: float = lerpf(float(b[2]), float(b[3]), 0.38)
		var b_top := Vector3(xb, yb + float(b[4]), b_mid_z)
		var b_bot := Vector3(xb, yb - float(b[5]), b_mid_z)

		var ctr := (a_lead + a_trail + b_lead + b_trail) * 0.25
		var top_col_a: Color = a[6]
		var top_col_b: Color = b[6]
		var bot_col_a: Color = a[7]
		var bot_col_b: Color = b[7]

		# Upper camber (front half + trailing half).
		_add_outward_quad_grad(st, a_lead, b_lead, b_top, a_top, ctr, top_col_a, top_col_b, top_col_b, top_col_a)
		_add_outward_quad_grad(st, a_top, b_top, b_trail, a_trail, ctr, top_col_a, top_col_b, top_col_b, top_col_a)
		# Lower surface (front half + trailing half).
		_add_outward_quad_grad(st, a_bot, b_bot, b_lead, a_lead, ctr, bot_col_a, bot_col_b, bot_col_b, bot_col_a)
		_add_outward_quad_grad(st, a_trail, b_trail, b_bot, a_bot, ctr, bot_col_a, bot_col_b, bot_col_b, bot_col_a)

	# Tapered wingtip primary feather spike cap.
	var last: Array = ribs[ribs.size() - 1]
	var xl: float = side_sign * float(last[0])
	var yl: float = float(last[1])
	var l_lead := Vector3(xl, yl, float(last[2]))
	var l_trail := Vector3(xl, yl - 0.005, float(last[3]))
	var l_mid_z: float = lerpf(float(last[2]), float(last[3]), 0.38)
	var l_top := Vector3(xl, yl + float(last[4]), l_mid_z)
	var l_bot := Vector3(xl, yl - float(last[5]), l_mid_z)
	var tip := Vector3(side_sign * 1.22, yl - 0.04, 0.26)
	var cap_ctr := Vector3(xl, yl, l_mid_z)
	_add_outward_tri(st, l_lead, tip, l_top, cap_ctr, COL_WING_TIP, COL_WING_TIP, COL_WING_TIP)
	_add_outward_tri(st, l_top, tip, l_trail, cap_ctr, COL_WING_TIP, COL_WING_TIP, COL_WING_TIP)
	_add_outward_tri(st, l_trail, tip, l_bot, cap_ctr, COL_TAIL_BAND, COL_WING_TIP, COL_TAIL_BAND)
	_add_outward_tri(st, l_bot, tip, l_lead, cap_ctr, COL_TAIL_BAND, COL_WING_TIP, COL_TAIL_BAND)

	return st.commit()


static func _append_body_loft(st: SurfaceTool, stations: Array[Array], segs: int) -> void:
	var rings: Array[Array] = []
	var ring_cols: Array[Array] = []
	var centers: Array[Vector3] = []

	for row in stations:
		var z: float = float(row[0])
		var yc: float = float(row[1])
		var rx: float = float(row[2])
		var ry_top: float = float(row[3])
		var ry_bot: float = float(row[4])
		var col_top: Color = row[5]
		var col_bot: Color = row[6]
		var ring: Array[Vector3] = []
		var cols: Array[Color] = []
		for k in segs:
			var a := float(k) / float(segs) * TAU
			var sa := sin(a)
			var ry := ry_top if sa >= 0.0 else ry_bot
			ring.append(Vector3(cos(a) * rx, yc + sa * ry, z))
			cols.append(col_bot.lerp(col_top, clampf(sa * 0.5 + 0.5, 0.0, 1.0)))
		rings.append(ring)
		ring_cols.append(cols)
		centers.append(Vector3(0.0, yc, z))

	for j in range(rings.size() - 1):
		var r0: Array = rings[j]
		var r1: Array = rings[j + 1]
		var c0: Array = ring_cols[j]
		var c1: Array = ring_cols[j + 1]
		var ctr := (centers[j] + centers[j + 1]) * 0.5
		for k in segs:
			var nk := (k + 1) % segs
			_add_outward_quad_grad(st, r1[nk], r0[nk], r0[k], r1[k], ctr,
				c1[nk], c0[nk], c0[k], c1[k])

	# Front cap.
	var first_r: Array = rings[0]
	var first_c: Array = ring_cols[0]
	var front_ctr := centers[0] + Vector3(0.0, 0.0, 0.08)
	var front_tip := centers[0] + Vector3(0.0, 0.0, -0.025)
	for k in segs:
		var nk := (k + 1) % segs
		_add_outward_tri(st, front_tip, first_r[k], first_r[nk], front_ctr,
			first_c[k], first_c[k], first_c[nk])

	# Back cap.
	var last_idx := rings.size() - 1
	var last_r: Array = rings[last_idx]
	var last_c: Array = ring_cols[last_idx]
	var back_ctr := centers[last_idx] + Vector3(0.0, 0.0, -0.08)
	var back_tip := centers[last_idx] + Vector3(0.0, 0.0, 0.02)
	for k in segs:
		var nk := (k + 1) % segs
		_add_outward_tri(st, back_tip, last_r[nk], last_r[k], back_ctr,
			last_c[k], last_c[nk], last_c[k])


static func _append_faceted_gem(st: SurfaceTool, center: Vector3, half_ext: Vector3, col: Color) -> void:
	var px := center + Vector3(half_ext.x, 0.0, 0.0)
	var nx := center + Vector3(-half_ext.x, 0.0, 0.0)
	var py := center + Vector3(0.0, half_ext.y, 0.0)
	var ny := center + Vector3(0.0, -half_ext.y, 0.0)
	var pz := center + Vector3(0.0, 0.0, half_ext.z)
	var nz := center + Vector3(0.0, 0.0, -half_ext.z)
	var shade := col.darkened(0.16)
	_add_outward_tri(st, py, px, nz, center, col, col, col)
	_add_outward_tri(st, py, nz, nx, center, col, col, col)
	_add_outward_tri(st, py, nx, pz, center, col, col, col)
	_add_outward_tri(st, py, pz, px, center, col, col, col)
	_add_outward_tri(st, ny, nz, px, center, shade, col, col)
	_add_outward_tri(st, ny, nx, nz, center, shade, col, col)
	_add_outward_tri(st, ny, pz, nx, center, shade, col, col)
	_add_outward_tri(st, ny, px, pz, center, shade, col, col)


static func _add_outward_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ref_center: Vector3, col: Color) -> void:
	_add_outward_quad_grad(st, a, b, c, d, ref_center, col, col, col, col)


static func _add_outward_quad_grad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_add_outward_tri(st, a, b, c, ref_center, ca, cb, cc)
	_add_outward_tri(st, a, c, d, ref_center, ca, cc, cd)


static func _add_outward_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color) -> void:
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
		n = -n
	n = n.normalized()
	st.set_normal(n)
	st.set_color(ca); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(a)
	st.set_normal(n)
	st.set_color(cb); st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(b)
	st.set_normal(n)
	st.set_color(cc); st.set_uv(Vector2(0.5, 1.0)); st.add_vertex(c)
