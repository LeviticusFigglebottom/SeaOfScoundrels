class_name SeaSoundscape
extends Node
## Dynamic, cooldown-gated, telemetry-driven wooden-ship sailing SFX controller.
##
## Complements AudioManager's continuous ambience beds (hull_wash, sea_calm,
## wind_light, etc.) with responsive timber, rigging, and canvas one-shots from
## verified keys in assets/generated/audio/manifest.json:
##   - &"hull_creak"   : hull heel/roll groan & deep oak heavy-swell keel timber groans
##   - &"rope_creak"   : taut hemp rigging creak under sail, storm shroud lash, or moored harbour hawser
##   - &"sail_flap"    : luffing canvas under headwind or storm-whipped reefed sail lash
##   - &"sail_fill"    : crisp billowing snap entering full wind catch
##   - &"seagull"      : distant daytime coastal gull / tropical bird calls near islands
##   - &"splash_small" : soft harbour waterline hull-lap while moored near shore
##   - &"whale_call"   : rare distant open-ocean whale call off the beam in calm/moderate seas
##   - &"hold_slosh"   : soft muffled underwater submersion water/bubble ripples

signal sfx_triggered(key: StringName, volume_db: float)

const SFX_HULL_CREAK := &"hull_creak"
const SFX_HULL_GROAN := &"hull_creak"
const SFX_ROPE_CREAK := &"rope_creak"
const SFX_SAIL_FLAP := &"sail_flap"
const SFX_SAIL_FILL := &"sail_fill"
const SFX_SHORE_BIRD := &"seagull"
const SFX_HULL_LAP := &"splash_small"
const SFX_WHALE_CALL := &"whale_call"
const SFX_UNDERWATER_BUBBLE := &"hold_slosh"

const HULL_ROLL_RAD_MIN := 0.10
const HULL_ROLL_VEL_MIN := 0.18
const HULL_CREAK_CD_MIN := 4.5
const HULL_CREAK_CD_MAX := 8.0

const HULL_GROAN_ROLL_MIN := 0.12
const HULL_GROAN_PITCH_MIN := 0.12
const HULL_GROAN_STORM_MIN := 0.45
const HULL_GROAN_WAVE_AMP_MIN := 0.55
const HULL_GROAN_CD_MIN := 5.5
const HULL_GROAN_CD_MAX := 9.5

const UNDERWATER_BUBBLE_DEPTH_MIN := 0.65
const UNDERWATER_BUBBLE_CD_MIN := 3.2
const UNDERWATER_BUBBLE_CD_MAX := 5.8

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

const MOORING_ISLAND_MIN := 0.45
const MOORING_SPEED_MAX := 1.35
const MOORING_SAIL_MAX := 0.20
const MOORING_ROPE_CD_MIN := 9.0
const MOORING_ROPE_CD_MAX := 15.5
const HULL_LAP_CD_MIN := 6.5
const HULL_LAP_CD_MAX := 12.0

const STORM_LASH_MIN := 0.55
const STORM_LASH_SAIL_MIN := 0.12
const STORM_ROPE_CD_MIN := 4.8
const STORM_ROPE_CD_MAX := 8.5
const STORM_FLAP_CD_MIN := 3.2
const STORM_FLAP_CD_MAX := 5.6

const WHALE_ISLAND_MAX := 0.08
const WHALE_STORM_MAX := 0.35
const WHALE_DAY_START := 5.0
const WHALE_DAY_END := 21.5
const WHALE_CALL_INIT_CD := 18.0
const WHALE_CALL_CD_MIN := 38.0
const WHALE_CALL_CD_MAX := 65.0
const WHALE_DIST_MIN := 45.0
const WHALE_DIST_MAX := 80.0

@export var enabled: bool = true

var ship: Node3D = null
var listener: Node3D = null
var last_sfx_triggered: StringName = &""
## Proximity factor to nearest island shore in 0..1 (0 in open ocean, 1 within island_radius + 35 m).
var near_island_factor: float = 0.0
var hull_groan_count: int = 0
var underwater_bubble_count: int = 0

var _rng := RandomNumberGenerator.new()
var _cd_hull_creak: float = 0.0
var _cd_hull_groan: float = 0.0
var _cd_rope_creak: float = 0.0
var _cd_sail_flap: float = 0.0
var _cd_sail_fill: float = 0.0
var _cd_shore_bird: float = 0.0
var _cd_hull_lap: float = 0.0
var _cd_whale_call: float = WHALE_CALL_INIT_CD
var _cd_underwater_bubble: float = 0.0
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
	SFX_HULL_LAP: 0,
	SFX_WHALE_CALL: 0,
	SFX_UNDERWATER_BUBBLE: 0,
}


func _init() -> void:
	name = "SeaSoundscape"
	_rng.randomize()


func _exit_tree() -> void:
	ship = null
	listener = null
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


## Bind an optional listener Node3D (camera or pawn) for underwater depth sampling.
func bind_listener(node: Node3D) -> void:
	listener = node


## Clear cooldown timers, transition latches, and triggered event counters.
func reset_state() -> void:
	_cd_hull_creak = 0.0
	_cd_hull_groan = 0.0
	_cd_rope_creak = 0.0
	_cd_sail_flap = 0.0
	_cd_sail_fill = 0.0
	_cd_shore_bird = 0.0
	_cd_hull_lap = 0.0
	_cd_whale_call = WHALE_CALL_INIT_CD
	_cd_underwater_bubble = 0.0
	near_island_factor = 0.0
	_nearest_shore_pos = Vector3.ZERO
	_prev_roll_rad = 0.0
	_has_prev_sample = false
	_billow_armed = false
	last_sfx_triggered = &""
	hull_groan_count = 0
	underwater_bubble_count = 0
	_event_counts[SFX_HULL_CREAK] = 0
	_event_counts[SFX_ROPE_CREAK] = 0
	_event_counts[SFX_SAIL_FLAP] = 0
	_event_counts[SFX_SAIL_FILL] = 0
	_event_counts[SFX_SHORE_BIRD] = 0
	_event_counts[SFX_HULL_LAP] = 0
	_event_counts[SFX_WHALE_CALL] = 0
	_event_counts[SFX_UNDERWATER_BUBBLE] = 0


## Return total heavy-swell hull timber groans emitted since last reset.
func get_hull_groan_count() -> int:
	return hull_groan_count


## Return total underwater submersion bubble ripples emitted since last reset.
func get_underwater_bubble_count() -> int:
	return underwater_bubble_count


## Return a snapshot Dictionary of triggered event counts per SFX key.
func get_event_counts() -> Dictionary:
	return _event_counts.duplicate()


func _physics_process(delta: float) -> void:
	if enabled:
		tick_soundscape(delta)


## Advance cooldowns and evaluate sailing & underwater soundscape telemetry.
## Callable directly in deterministic headless unit tests with zero steady-state allocations.
func step(delta: float) -> void:
	tick_soundscape(delta)


## Deterministic tick for maritime soundscape layers (hull groans, rigging, shore, whale, bubbles).
## Pass explicit `underwater_depth` (metres) and `in_dry_hull` in tests, or leave `NAN` to auto-sample.
func tick_soundscape(delta: float, underwater_depth: float = NAN, in_dry_hull: bool = false) -> void:
	if not enabled or delta <= 0.0:
		return

	_cd_underwater_bubble = maxf(0.0, _cd_underwater_bubble - delta)
	_step_underwater_bubbles(underwater_depth, in_dry_hull)

	if ship == null or not is_instance_valid(ship):
		ship = null
		near_island_factor = 0.0
		return
	if ship is Ship and (ship as Ship).is_sinking:
		return

	_cd_hull_creak = maxf(0.0, _cd_hull_creak - delta)
	_cd_hull_groan = maxf(0.0, _cd_hull_groan - delta)
	_cd_rope_creak = maxf(0.0, _cd_rope_creak - delta)
	_cd_sail_flap = maxf(0.0, _cd_sail_flap - delta)
	_cd_sail_fill = maxf(0.0, _cd_sail_fill - delta)
	_cd_shore_bird = maxf(0.0, _cd_shore_bird - delta)
	_cd_hull_lap = maxf(0.0, _cd_hull_lap - delta)
	_cd_whale_call = maxf(0.0, _cd_whale_call - delta)

	var pos := ship.global_position if ship.is_inside_tree() else ship.position
	var ship_basis := ship.global_basis if ship.is_inside_tree() else ship.basis
	var ship_up := ship_basis.y
	var local_storm := clampf(Weather.local_storminess(pos), 0.0, 1.0) if Weather != null else 0.0
	var tod := Weather.time_of_day if Weather != null else 12.0
	_update_island_proximity(pos)

	# 1. Timber hull creak on pronounced heel angle or roll velocity.
	var roll_rad := _sample_roll_rad(ship)
	var pitch_rad := _sample_pitch_rad(ship)
	var roll_vel := _sample_roll_vel(ship, roll_rad, delta)
	_prev_roll_rad = roll_rad
	_has_prev_sample = true

	var abs_roll := absf(roll_rad)
	var abs_pitch := absf(pitch_rad)
	var abs_roll_vel := absf(roll_vel)
	if _cd_hull_creak <= 0.0 and (abs_roll >= HULL_ROLL_RAD_MIN or abs_roll_vel >= HULL_ROLL_VEL_MIN):
		var heel_t := clampf((abs_roll - HULL_ROLL_RAD_MIN) / 0.25, 0.0, 1.0)
		var vel_t := clampf((abs_roll_vel - HULL_ROLL_VEL_MIN) / 0.55, 0.0, 1.0)
		var intensity := clampf(maxf(heel_t, vel_t) * 0.72 + local_storm * 0.28, 0.0, 1.0)
		var vol_db := lerpf(-10.5, -2.5, intensity)
		_cd_hull_creak = _rng.randf_range(HULL_CREAK_CD_MIN, HULL_CREAK_CD_MAX)
		_trigger(SFX_HULL_CREAK, pos, vol_db)

	var sail_set := _sample_sail_set(ship)
	var fwd_speed := _sample_forward_speed(ship)
	var wc := _sample_wind_catch(ship)
	var is_moored_harbour := (
		near_island_factor >= MOORING_ISLAND_MIN
		and absf(fwd_speed) < MOORING_SPEED_MAX
		and sail_set < MOORING_SAIL_MAX
	)

	# 2. Hemp rigging tension creak: lively sail, storm shroud lash, or gentle harbour mooring hawser.
	if _cd_rope_creak <= 0.0:
		if fwd_speed >= ROPE_SPEED_MIN and sail_set >= ROPE_SAIL_MIN:
			var load_t := clampf((fwd_speed - ROPE_SPEED_MIN) / 7.5, 0.0, 1.0) * clampf(sail_set, 0.35, 1.0)
			var vol_db := lerpf(-11.0, -4.5, load_t)
			_cd_rope_creak = _rng.randf_range(ROPE_CREAK_CD_MIN, ROPE_CREAK_CD_MAX)
			_trigger(SFX_ROPE_CREAK, pos + ship_up * 3.2, vol_db)
		elif local_storm >= STORM_LASH_MIN and sail_set >= STORM_LASH_SAIL_MIN:
			var storm_t := clampf((local_storm - STORM_LASH_MIN) / (1.0 - STORM_LASH_MIN), 0.0, 1.0)
			var sail_t := clampf(sail_set, STORM_LASH_SAIL_MIN, 1.0)
			var vol_db := lerpf(-10.0, -3.5, clampf(storm_t * 0.70 + sail_t * 0.30, 0.0, 1.0))
			_cd_rope_creak = _rng.randf_range(STORM_ROPE_CD_MIN, STORM_ROPE_CD_MAX) * lerpf(1.0, 0.72, storm_t)
			_trigger(SFX_ROPE_CREAK, pos + ship_up * 4.0, vol_db, 0.08)
		elif is_moored_harbour:
			var moor_t := clampf((near_island_factor - MOORING_ISLAND_MIN) / (1.0 - MOORING_ISLAND_MIN), 0.0, 1.0)
			var swell_t := clampf(moor_t * 0.55 + local_storm * 0.45, 0.0, 1.0)
			var vol_db := lerpf(-14.0, -10.5, swell_t)
			_cd_rope_creak = _rng.randf_range(MOORING_ROPE_CD_MIN, MOORING_ROPE_CD_MAX)
			_trigger(SFX_ROPE_CREAK, pos + ship_up * 1.4, vol_db, 0.07)

	# 3. Canvas luffing flap (headwind/poor trim) or storm-whipped rigging lash even on reefed sails.
	if _cd_sail_flap <= 0.0:
		if sail_set >= FLAP_SAIL_MIN and wc < FLAP_WIND_CATCH_MAX:
			var luff_t := clampf(sail_set * (1.0 - wc), 0.0, 1.0)
			var vol_db := lerpf(-9.5, -4.0, luff_t)
			_cd_sail_flap = _rng.randf_range(SAIL_FLAP_CD_MIN, SAIL_FLAP_CD_MAX)
			_trigger(SFX_SAIL_FLAP, pos + ship_up * 6.0, vol_db)
		elif local_storm >= STORM_LASH_MIN and sail_set >= STORM_LASH_SAIL_MIN:
			var storm_t := clampf((local_storm - STORM_LASH_MIN) / (1.0 - STORM_LASH_MIN), 0.0, 1.0)
			var sail_t := clampf(sail_set, STORM_LASH_SAIL_MIN, 1.0)
			var vol_db := lerpf(-9.5, -3.0, clampf(storm_t * 0.72 + sail_t * 0.28, 0.0, 1.0))
			_cd_sail_flap = _rng.randf_range(STORM_FLAP_CD_MIN, STORM_FLAP_CD_MAX) * lerpf(1.0, 0.75, storm_t)
			_trigger(SFX_SAIL_FLAP, pos + ship_up * 5.8, vol_db, 0.08)

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

	# 5. Soft harbour waterline hull-lap when moored/drifting slowly near an island shore.
	if _cd_hull_lap <= 0.0 and is_moored_harbour:
		var lap_t := clampf(0.35 + local_storm * 0.65, 0.0, 1.0)
		var vol_db := lerpf(-15.5, -11.5, lap_t)
		var side_sign := -1.0 if _rng.randf() < 0.5 else 1.0
		var lap_pos := pos + ship_basis.x * (side_sign * 2.8) + ship_basis.z * _rng.randf_range(-3.0, 3.0)
		_cd_hull_lap = _rng.randf_range(HULL_LAP_CD_MIN, HULL_LAP_CD_MAX)
		_trigger(SFX_HULL_LAP, lap_pos, vol_db, 0.10)

	# 6. Coastal island proximity awareness & daytime non-stormy tropical bird ambiance.
	if _cd_shore_bird <= 0.0 and near_island_factor > SHORE_BIRD_MIN_FACTOR:
		var storm := Weather.storminess if Weather != null else 0.0
		if tod >= SHORE_BIRD_DAY_START and tod <= SHORE_BIRD_DAY_END and storm < SHORE_BIRD_STORM_MAX:
			var bird_t := clampf((near_island_factor - SHORE_BIRD_MIN_FACTOR) / (1.0 - SHORE_BIRD_MIN_FACTOR), 0.0, 1.0)
			var vol_db := lerpf(SHORE_BIRD_VOL_DB - 3.0, SHORE_BIRD_VOL_DB, bird_t)
			var call_pos := pos.lerp(_nearest_shore_pos, 0.45) + Vector3.UP * _rng.randf_range(12.0, 20.0)
			_cd_shore_bird = _rng.randf_range(SHORE_BIRD_CD_MIN, SHORE_BIRD_CD_MAX)
			_trigger(SFX_SHORE_BIRD, call_pos, vol_db, 0.09)

	# 7. Rare evocative distant open-ocean whale call off the beam in calm/moderate seas.
	if _cd_whale_call <= 0.0 and near_island_factor < WHALE_ISLAND_MAX:
		if local_storm < WHALE_STORM_MAX and tod >= WHALE_DAY_START and tod <= WHALE_DAY_END:
			var calm_t := clampf(1.0 - local_storm / WHALE_STORM_MAX, 0.0, 1.0)
			var vol_db := lerpf(-16.0, -13.0, calm_t * _rng.randf_range(0.55, 1.0))
			var beam_sign := -1.0 if _rng.randf() < 0.5 else 1.0
			var beam_dist := _rng.randf_range(WHALE_DIST_MIN, WHALE_DIST_MAX)
			var fore_off := _rng.randf_range(-18.0, 24.0)
			var whale_pos := pos + ship_basis.x * (beam_sign * beam_dist) + ship_basis.z * fore_off
			whale_pos.y = pos.y - 1.5
			_cd_whale_call = _rng.randf_range(WHALE_CALL_CD_MIN, WHALE_CALL_CD_MAX)
			_trigger(SFX_WHALE_CALL, whale_pos, vol_db, 0.06)

	# 8. Heavy-swell deep oak hull timber groans during rough rolling/pitching or stormy active waves.
	var waves_active := Sea != null and Sea.amp_scale >= HULL_GROAN_WAVE_AMP_MIN
	var rough_motion := abs_roll >= HULL_GROAN_ROLL_MIN or abs_pitch >= HULL_GROAN_PITCH_MIN
	if _cd_hull_groan <= 0.0 and waves_active and (rough_motion or local_storm >= HULL_GROAN_STORM_MIN):
		var tilt_t := clampf((maxf(abs_roll, abs_pitch) - HULL_GROAN_ROLL_MIN) / 0.24, 0.0, 1.0)
		var swell_storm_t := clampf((local_storm - HULL_GROAN_STORM_MIN) / (1.0 - HULL_GROAN_STORM_MIN), 0.0, 1.0)
		var amp_t := clampf((Sea.amp_scale - HULL_GROAN_WAVE_AMP_MIN) / 0.45, 0.0, 1.0)
		var groan_t := clampf(maxf(tilt_t, swell_storm_t) * 0.78 + amp_t * 0.22, 0.0, 1.0)
		var groan_db := lerpf(-11.5, -5.0, groan_t)
		var groan_pitch := _rng.randf_range(0.76, 0.88)
		var groan_pos := pos - ship_up * 0.85 + ship_basis.z * _rng.randf_range(-2.5, 2.5)
		_cd_hull_groan = _rng.randf_range(HULL_GROAN_CD_MIN, HULL_GROAN_CD_MAX)
		hull_groan_count += 1
		_trigger(SFX_HULL_GROAN, groan_pos, groan_db, 0.04, groan_pitch)


func _step_underwater_bubbles(underwater_depth_override: float, dry_hull_override: bool) -> void:
	if listener != null and not is_instance_valid(listener):
		listener = null

	var uw_depth := 0.0
	var in_dry_hull := dry_hull_override
	var listener_pos := Vector3.INF

	if not is_nan(underwater_depth_override):
		uw_depth = underwater_depth_override
		if listener != null:
			listener_pos = listener.global_position if listener.is_inside_tree() else listener.position
	elif listener != null:
		listener_pos = listener.global_position if listener.is_inside_tree() else listener.position
		in_dry_hull = Ocean.current != null and is_instance_valid(Ocean.current) and Ocean.current.is_point_in_dry_hull(listener_pos)
		if in_dry_hull:
			uw_depth = -1000.0
		else:
			var sea_y := Sea.height(listener_pos.x, listener_pos.z) if Sea != null else 0.0
			uw_depth = sea_y - listener_pos.y
	elif Ocean.current != null and is_instance_valid(Ocean.current):
		var cam := Ocean.current.active_camera()
		if cam != null and is_instance_valid(cam):
			listener_pos = cam.global_position
			in_dry_hull = Ocean.current.is_point_in_dry_hull(listener_pos)
			if in_dry_hull:
				uw_depth = -1000.0
			else:
				var sea_y := Sea.height(listener_pos.x, listener_pos.z) if Sea != null else 0.0
				uw_depth = sea_y - listener_pos.y
		else:
			uw_depth = Ocean.current.camera_depth
			in_dry_hull = uw_depth <= -999.0
	elif is_inside_tree():
		var vp := get_viewport()
		var cam := vp.get_camera_3d() if vp != null else null
		if cam != null and is_instance_valid(cam):
			listener_pos = cam.global_position
			var sea_y := Sea.height(listener_pos.x, listener_pos.z) if Sea != null else 0.0
			uw_depth = sea_y - listener_pos.y

	if _cd_underwater_bubble <= 0.0 and not in_dry_hull and uw_depth >= UNDERWATER_BUBBLE_DEPTH_MIN:
		var depth_t := clampf((uw_depth - UNDERWATER_BUBBLE_DEPTH_MIN) / 4.0, 0.0, 1.0)
		var bubble_db := lerpf(-16.5, -12.5, depth_t)
		var bubble_pitch := _rng.randf_range(0.72, 0.88)
		var bubble_pos := Vector3.INF
		if listener_pos.is_finite():
			bubble_pos = listener_pos + Vector3(
				_rng.randf_range(-1.8, 1.8),
				_rng.randf_range(-0.3, 0.9),
				_rng.randf_range(-1.8, 1.8)
			)
		_cd_underwater_bubble = _rng.randf_range(UNDERWATER_BUBBLE_CD_MIN, UNDERWATER_BUBBLE_CD_MAX)
		underwater_bubble_count += 1
		_trigger(SFX_UNDERWATER_BUBBLE, bubble_pos, bubble_db, 0.06, bubble_pitch)


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


func _trigger(key: StringName, pos: Vector3, vol_db: float, pitch_jitter: float = 0.05, pitch_mult: float = 1.0) -> void:
	last_sfx_triggered = key
	_event_counts[key] = int(_event_counts.get(key, 0)) + 1
	if Audio != null and Audio.has_sound(key):
		var player: Node = Audio.play_sfx(key, pos, vol_db, pitch_jitter)
		if player != null and not is_equal_approx(pitch_mult, 1.0):
			if player is AudioStreamPlayer3D:
				(player as AudioStreamPlayer3D).pitch_scale *= pitch_mult
			elif player is AudioStreamPlayer:
				(player as AudioStreamPlayer).pitch_scale *= pitch_mult
	sfx_triggered.emit(key, vol_db)


func _sample_roll_rad(s: Node3D) -> float:
	var b := s.global_basis if s.is_inside_tree() else s.basis
	return atan2(b.x.y, b.y.y)


func _sample_pitch_rad(s: Node3D) -> float:
	var b := s.global_basis if s.is_inside_tree() else s.basis
	return atan2(-b.z.y, b.y.y)


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
