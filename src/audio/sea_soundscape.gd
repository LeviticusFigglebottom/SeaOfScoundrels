class_name SeaSoundscape
extends Node
## Dynamic, cooldown-gated, telemetry-driven wooden-ship sailing SFX controller.
##
## Complements AudioManager's continuous ambience beds (hull_wash, sea_calm,
## wind_light, etc.) with responsive timber, rigging, and canvas one-shots from
## verified keys in assets/generated/audio/manifest.json:
##   - &"hull_creak" : hull heel/roll groan (scaled by heel & storminess)
##   - &"rope_creak" : taut hemp rigging creak at speed under sail
##   - &"sail_flap"  : luffing canvas when poorly trimmed / catching headwind
##   - &"sail_fill"  : crisp billowing snap entering full wind catch
##   - &"seagull"    : distant daytime coastal gull / tropical bird calls near islands

signal sfx_triggered(key: StringName, volume_db: float)

const SFX_HULL_CREAK := &"hull_creak"
const SFX_ROPE_CREAK := &"rope_creak"
const SFX_SAIL_FLAP := &"sail_flap"
const SFX_SAIL_FILL := &"sail_fill"
const SFX_SHORE_BIRD := &"seagull"

const HULL_ROLL_RAD_MIN := 0.10
const HULL_ROLL_VEL_MIN := 0.18
const HULL_CREAK_CD_MIN := 4.5
const HULL_CREAK_CD_MAX := 8.0

const ROPE_SPEED_MIN := 4.2
const ROPE_SAIL_MIN := 0.35
const ROPE_CREAK_CD_MIN := 6.0
const ROPE_CREAK_CD_MAX := 10.5

const FLAP_SAIL_MIN := 0.25
const FLAP_WIND_CATCH_MAX := 0.28
const SAIL_FLAP_CD_MIN := 3.8
const SAIL_FLAP_CD_MAX := 6.2

const FILL_SAIL_MIN := 0.35
const FILL_LOW_CATCH_THRESH := 0.60
const FILL_HIGH_CATCH_THRESH := 0.84
const SAIL_FILL_CD := 4.0

const SHORE_FULL_MARGIN := 35.0
const SHORE_FADE_SPAN := 115.0
const SHORE_BIRD_MIN_FACTOR := 0.25
const SHORE_BIRD_DAY_START := 6.0
const SHORE_BIRD_DAY_END := 19.0
const SHORE_BIRD_STORM_MAX := 0.55
const SHORE_BIRD_CD_MIN := 7.0
const SHORE_BIRD_CD_MAX := 14.0
const SHORE_BIRD_VOL_DB := -12.0

@export var enabled: bool = true

var ship: Node3D = null
var last_sfx_triggered: StringName = &""
## Proximity factor to nearest island shore in 0..1 (0 in open ocean, 1 within island_radius + 35 m).
var near_island_factor: float = 0.0

var _rng := RandomNumberGenerator.new()
var _cd_hull_creak: float = 0.0
var _cd_rope_creak: float = 0.0
var _cd_sail_flap: float = 0.0
var _cd_sail_fill: float = 0.0
var _cd_shore_bird: float = 0.0
var _nearest_shore_pos: Vector3 = Vector3.ZERO
var _prev_roll_rad: float = 0.0
var _has_prev_sample: bool = false
var _billow_armed: bool = false
var _event_counts: Dictionary = {
	SFX_HULL_CREAK: 0,
	SFX_ROPE_CREAK: 0,
	SFX_SAIL_FLAP: 0,
	SFX_SAIL_FILL: 0,
	SFX_SHORE_BIRD: 0,
}


func _init() -> void:
	name = "SeaSoundscape"
	_rng.randomize()


func _exit_tree() -> void:
	ship = null
	_has_prev_sample = false
	near_island_factor = 0.0
	_nearest_shore_pos = Vector3.ZERO
	set_physics_process(false)


## Bind a Ship (or telemetry-compatible Node3D) and reset cooldown/state tracking.
func bind_ship(s: Node3D) -> void:
	ship = s
	reset_state()
	if ship != null and is_instance_valid(ship):
		_prev_roll_rad = _sample_roll_rad(ship)
		_has_prev_sample = true


## Clear cooldown timers, transition latches, and triggered event counters.
func reset_state() -> void:
	_cd_hull_creak = 0.0
	_cd_rope_creak = 0.0
	_cd_sail_flap = 0.0
	_cd_sail_fill = 0.0
	_cd_shore_bird = 0.0
	near_island_factor = 0.0
	_nearest_shore_pos = Vector3.ZERO
	_prev_roll_rad = 0.0
	_has_prev_sample = false
	_billow_armed = false
	last_sfx_triggered = &""
	_event_counts[SFX_HULL_CREAK] = 0
	_event_counts[SFX_ROPE_CREAK] = 0
	_event_counts[SFX_SAIL_FLAP] = 0
	_event_counts[SFX_SAIL_FILL] = 0
	_event_counts[SFX_SHORE_BIRD] = 0


## Return a snapshot Dictionary of triggered event counts per SFX key.
func get_event_counts() -> Dictionary:
	return _event_counts.duplicate()


func _physics_process(delta: float) -> void:
	if enabled and ship != null:
		step(delta)


## Advance cooldowns and evaluate sailing telemetry for dynamic ship SFX.
## Callable directly in deterministic headless unit tests with zero steady-state allocations.
func step(delta: float) -> void:
	if not enabled or delta <= 0.0:
		return
	if ship == null or not is_instance_valid(ship):
		ship = null
		near_island_factor = 0.0
		return
	if ship is Ship and (ship as Ship).is_sinking:
		return

	_cd_hull_creak = maxf(0.0, _cd_hull_creak - delta)
	_cd_rope_creak = maxf(0.0, _cd_rope_creak - delta)
	_cd_sail_flap = maxf(0.0, _cd_sail_flap - delta)
	_cd_sail_fill = maxf(0.0, _cd_sail_fill - delta)
	_cd_shore_bird = maxf(0.0, _cd_shore_bird - delta)

	var pos := ship.global_position if ship.is_inside_tree() else ship.position
	var ship_up := ship.global_basis.y if ship.is_inside_tree() else ship.basis.y

	# 1. Timber hull creak on pronounced heel angle or roll velocity.
	var roll_rad := _sample_roll_rad(ship)
	var roll_vel := _sample_roll_vel(ship, roll_rad, delta)
	_prev_roll_rad = roll_rad
	_has_prev_sample = true

	var abs_roll := absf(roll_rad)
	var abs_roll_vel := absf(roll_vel)
	if _cd_hull_creak <= 0.0 and (abs_roll >= HULL_ROLL_RAD_MIN or abs_roll_vel >= HULL_ROLL_VEL_MIN):
		var heel_t := clampf((abs_roll - HULL_ROLL_RAD_MIN) / 0.25, 0.0, 1.0)
		var vel_t := clampf((abs_roll_vel - HULL_ROLL_VEL_MIN) / 0.55, 0.0, 1.0)
		var storm_t := clampf(Weather.local_storminess(pos), 0.0, 1.0) if Weather != null else 0.0
		var intensity := clampf(maxf(heel_t, vel_t) * 0.72 + storm_t * 0.28, 0.0, 1.0)
		var vol_db := lerpf(-10.5, -2.5, intensity)
		_cd_hull_creak = _rng.randf_range(HULL_CREAK_CD_MIN, HULL_CREAK_CD_MAX)
		_trigger(SFX_HULL_CREAK, pos, vol_db)

	var sail_set := _sample_sail_set(ship)
	var fwd_speed := _sample_forward_speed(ship)
	var wc := _sample_wind_catch(ship)

	# 2. Hemp rigging tension creak at lively forward speed under sail.
	if _cd_rope_creak <= 0.0 and fwd_speed >= ROPE_SPEED_MIN and sail_set >= ROPE_SAIL_MIN:
		var load_t := clampf((fwd_speed - ROPE_SPEED_MIN) / 7.5, 0.0, 1.0) * clampf(sail_set, 0.35, 1.0)
		var vol_db := lerpf(-11.0, -4.5, load_t)
		_cd_rope_creak = _rng.randf_range(ROPE_CREAK_CD_MIN, ROPE_CREAK_CD_MAX)
		_trigger(SFX_ROPE_CREAK, pos + ship_up * 3.2, vol_db)

	# 3. Canvas luffing flap when sail is set but poorly trimmed / facing headwind.
	if _cd_sail_flap <= 0.0 and sail_set >= FLAP_SAIL_MIN and wc < FLAP_WIND_CATCH_MAX:
		var luff_t := clampf(sail_set * (1.0 - wc), 0.0, 1.0)
		var vol_db := lerpf(-9.5, -4.0, luff_t)
		_cd_sail_flap = _rng.randf_range(SAIL_FLAP_CD_MIN, SAIL_FLAP_CD_MAX)
		_trigger(SFX_SAIL_FLAP, pos + ship_up * 6.0, vol_db)

	# 4. Crisp billowing canvas snap when transitioning from low/mid wind catch into full billow.
	if sail_set < FILL_SAIL_MIN or wc < FILL_LOW_CATCH_THRESH:
		_billow_armed = true
	elif _billow_armed and wc >= FILL_HIGH_CATCH_THRESH:
		_billow_armed = false
		if _cd_sail_fill <= 0.0:
			var fill_t := clampf(sail_set, 0.35, 1.0)
			var vol_db := lerpf(-6.5, -2.5, fill_t)
			_cd_sail_fill = SAIL_FILL_CD
			_trigger(SFX_SAIL_FILL, pos + ship_up * 6.0, vol_db)

	# 5. Coastal island proximity awareness & daytime non-stormy tropical bird ambiance.
	_update_island_proximity(pos)
	if _cd_shore_bird <= 0.0 and near_island_factor > SHORE_BIRD_MIN_FACTOR:
		var tod := Weather.time_of_day if Weather != null else 12.0
		var storm := Weather.storminess if Weather != null else 0.0
		if tod >= SHORE_BIRD_DAY_START and tod <= SHORE_BIRD_DAY_END and storm < SHORE_BIRD_STORM_MAX:
			var bird_t := clampf((near_island_factor - SHORE_BIRD_MIN_FACTOR) / (1.0 - SHORE_BIRD_MIN_FACTOR), 0.0, 1.0)
			var vol_db := lerpf(SHORE_BIRD_VOL_DB - 3.0, SHORE_BIRD_VOL_DB, bird_t)
			var call_pos := pos.lerp(_nearest_shore_pos, 0.45) + Vector3.UP * _rng.randf_range(12.0, 20.0)
			_cd_shore_bird = _rng.randf_range(SHORE_BIRD_CD_MIN, SHORE_BIRD_CD_MAX)
			_trigger(SFX_SHORE_BIRD, call_pos, vol_db, 0.09)


func _update_island_proximity(pos: Vector3) -> void:
	var tree := get_tree() if is_inside_tree() else (ship.get_tree() if (ship != null and ship.is_inside_tree()) else null)
	if tree == null:
		near_island_factor = 0.0
		_nearest_shore_pos = pos
		return
	var best_factor := 0.0
	var best_shore := pos
	for node in tree.get_nodes_in_group(&"islands"):
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		var isl := node as Node3D
		var isl_pos := isl.global_position if isl.is_inside_tree() else isl.position
		var r_v: Variant = isl.get(&"island_radius")
		var isl_r := maxf(float(r_v) if r_v != null else 60.0, 1.0)
		var dx := pos.x - isl_pos.x
		var dz := pos.z - isl_pos.z
		var dist_xz := sqrt(dx * dx + dz * dz)
		var inner_d := isl_r + SHORE_FULL_MARGIN
		var outer_d := inner_d + SHORE_FADE_SPAN
		var fac := 0.0
		if dist_xz <= inner_d:
			fac = 1.0
		elif dist_xz < outer_d:
			fac = 1.0 - smoothstep(inner_d, outer_d, dist_xz)
		if fac > best_factor:
			best_factor = fac
			if dist_xz > 0.01:
				var inv_d := 1.0 / dist_xz
				var shore_r := minf(isl_r, dist_xz)
				best_shore = Vector3(isl_pos.x + dx * inv_d * shore_r, pos.y, isl_pos.z + dz * inv_d * shore_r)
			else:
				best_shore = isl_pos
	near_island_factor = best_factor
	_nearest_shore_pos = best_shore


func _trigger(key: StringName, pos: Vector3, vol_db: float, pitch_jitter: float = 0.05) -> void:
	last_sfx_triggered = key
	_event_counts[key] = int(_event_counts.get(key, 0)) + 1
	if Audio != null and Audio.has_sound(key):
		Audio.play_sfx(key, pos, vol_db, pitch_jitter)
	sfx_triggered.emit(key, vol_db)


func _sample_roll_rad(s: Node3D) -> float:
	var b := s.global_basis if s.is_inside_tree() else s.basis
	return atan2(b.x.y, b.y.y)


func _sample_roll_vel(s: Node3D, roll_rad: float, delta: float) -> float:
	var vel := 0.0
	if _has_prev_sample and delta > 0.0001:
		vel = (roll_rad - _prev_roll_rad) / delta
	if s is RigidBody3D:
		var b := s.global_basis if s.is_inside_tree() else s.basis
		var ang_z := (b.inverse() * (s as RigidBody3D).angular_velocity).z
		if absf(ang_z) > absf(vel):
			vel = ang_z
	return vel


func _sample_forward_speed(s: Node3D) -> float:
	if s is Ship:
		return (s as Ship).forward_speed()
	if s.has_method(&"forward_speed"):
		return float(s.call(&"forward_speed"))
	if s is RigidBody3D:
		var b := s.global_basis if s.is_inside_tree() else s.basis
		return (s as RigidBody3D).linear_velocity.dot(-b.z)
	return 0.0


func _sample_sail_set(s: Node3D) -> float:
	if s is Ship:
		return (s as Ship).sail_set
	var v: Variant = s.get(&"sail_set")
	return float(v) if v != null else 0.0


func _sample_wind_catch(s: Node3D) -> float:
	if s is Ship:
		return (s as Ship).wind_catch()
	if s.has_method(&"wind_catch"):
		return float(s.call(&"wind_catch"))
	var v: Variant = s.get(&"wind_catch_value")
	return float(v) if v != null else 0.0
