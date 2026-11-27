class_name AIShipBrain
extends Node
## Naval AI controller for enemy ships (Drowned Sloop and Ghost Ship).
##
## Drives the exact same `Ship` control interface as a player/crew (`set_helm_target`,
## `set_sail_target`, `set_trim_target`, `set_anchor`, `aim_cannon`, `fire_cannon`,
## `patch_hole`, `bail`) so enemy vessels obey identical wave, sail, and flood physics.

signal salvage_dropped(ship_pos: Vector3, items: Array)
signal phase_shifted(from_pos: Vector3, to_pos: Vector3)

const PHASE_OUT_DURATION := 1.2
const PHASE_IN_DURATION := 1.1
const PHASE_MIN_DIST := 25.0
const PHASE_MAX_DIST := 155.0
const PHASE_AMBUSH_RANGE := 58.0
const NIGHT_STEALTH_AGGRO_MULT := 0.62
const SAIL_DAMAGE_EVASIVE_HELM_BIAS := 0.42
const SAIL_DAMAGE_EVASIVE_PERIOD := 2.4

@export var archetype: StringName = &"drowned_sloop"  # &"drowned_sloop", &"ghost_ship", or &"corsair_sloop"
@export var preferred_range: float = 58.0
@export var aggro_range: float = 480.0
@export var repair_interval: float = 11.0
@export var phase_cooldown: float = 20.0

var ship: Ship = null
var target_ship: Ship = null

var _orbit_sign: float = 1.0  # +1 circles starboard-to-target, -1 port-to-target
var _repair_timer: float = 8.0
var _fire_delay: float = 1.5
var _salvage_spawned: bool = false
var _phase_state: StringName = &"solid"  # &"solid", &"fading_out", &"fading_in"
var _phase_timer: float = 14.0
var _phase_elapsed: float = 0.0
var _phase_ring_stamped: bool = false
var _evasive_timer: float = 0.0
var _evasive_sign: float = -1.0
var _was_sail_damaged: bool = false


func _ready() -> void:
	name = "AIShipBrain"
	ship = get_parent() as Ship
	assert(ship != null, "AIShipBrain must be a child of a Ship")
	_apply_archetype()
	ship.sunk.connect(_on_sunk)


func _apply_archetype() -> void:
	if archetype == &"ghost_ship":
		ship.faction = &"ghost"
		ship.speed_modifier = 1.15
		ship.reload_modifier = 0.78
		ship.apply_livery(Color(0.38, 0.94, 0.88), Color(0.28, 0.96, 0.86), Color(0.22, 0.98, 0.84))
	elif archetype == &"corsair_sloop":
		ship.faction = &"corsair"
		ship.speed_modifier = 1.08
		ship.reload_modifier = 0.92
		preferred_range = 46.0
		ship.apply_livery(Color(0.68, 0.14, 0.16), Color(0.92, 0.72, 0.22), Color(0.0, 0.0, 0.0))
	else:
		ship.faction = &"drowned"
		ship.speed_modifier = 0.96
		ship.reload_modifier = 1.15
		ship.apply_livery(Color(0.26, 0.34, 0.30), Color(0.18, 0.58, 0.42), Color(0.14, 0.92, 0.52))


## Convenience factory: spawns a ready-to-sail enemy sloop with AIShipBrain.
static func spawn_enemy_sloop(p_archetype: StringName, world_pos: Vector3, parent: Node, target: Ship = null) -> Ship:
	var sloop_scene: PackedScene = load("res://src/ship/sloop.tscn")
	var s := sloop_scene.instantiate() as Ship
	if p_archetype == &"ghost_ship":
		s.name = "GhostSloop"
		s.faction = &"ghost"
	elif p_archetype == &"corsair_sloop":
		s.name = "CorsairSloop"
		s.faction = &"corsair"
	else:
		s.name = "DrownedSloop"
		s.faction = &"drowned"
	var brain := AIShipBrain.new()
	brain.archetype = p_archetype
	brain.target_ship = target
	s.add_child(brain)
	parent.add_child(s)
	s.global_position = Vector3(world_pos.x, Sea.height(world_pos.x, world_pos.z), world_pos.z)
	if target != null:
		var to := target.global_position - s.global_position
		s.rotation.y = atan2(-to.x, -to.z)
	s.set_sail_target(0.85)
	s.sail_set = 0.85
	return s


## Host-only trigger to begin a Ghost Ship spectral phase-shift broadside ambush.
func trigger_phase_shift() -> bool:
	if not Net.is_host() or ship == null or ship.is_sinking:
		return false
	if archetype != &"ghost_ship" or _phase_state != &"solid":
		return false
	if target_ship == null or not is_instance_valid(target_ship) or target_ship.is_sinking:
		return false
	_phase_state = &"fading_out"
	_phase_elapsed = 0.0
	_phase_ring_stamped = false
	ship.set_spectral_phase(1.0, 1.4)
	ship.trigger_spectral_phase_ring(1.0)
	if Ocean.current != null:
		Ocean.current.add_foam(ship.global_position, 9.0, 1.0)
	Audio.play_sfx(&"thunder_near", ship.global_position, -6.0)
	return true


func _physics_process(delta: float) -> void:
	if not Net.is_host() or ship == null or ship.is_sinking:
		return

	if target_ship == null or not is_instance_valid(target_ship) or target_ship.is_sinking:
		target_ship = _find_player_ship()

	# Keep sail trimmed cleanly to the wind.
	ship.set_trim_target(ship.ideal_sail_trim())
	ship.set_anchor(false)

	# Slow self-repair so sustained player broadsides can overwhelm and sink it.
	_tick_self_repair(delta)

	if archetype == &"ghost_ship":
		_tick_ghost_phase(delta)

	var sails_torn := is_sail_damaged()
	if sails_torn:
		if not _was_sail_damaged:
			_evasive_timer = 0.0
			_evasive_sign = -_orbit_sign
		_evasive_timer += delta
		if _evasive_timer >= SAIL_DAMAGE_EVASIVE_PERIOD:
			_evasive_timer = 0.0
			_evasive_sign = -_evasive_sign
	else:
		_evasive_timer = 0.0
	_was_sail_damaged = sails_torn

	if target_ship == null:
		# Patrol steadily (or weave defensively if sails were shredded from afar).
		ship.set_sail_target(1.0 if sails_torn else 0.65)
		ship.set_helm_target(_evasive_sign * SAIL_DAMAGE_EVASIVE_HELM_BIAS if sails_torn else 0.12)
		return

	var to_t := target_ship.global_position - ship.global_position
	var flat := Vector3(to_t.x, 0.0, to_t.z)
	var dist := flat.length()

	if archetype == &"ghost_ship" and _phase_state == &"solid":
		_phase_timer = maxf(0.0, _phase_timer - delta)
		if _phase_timer <= 0.0 and dist >= PHASE_MIN_DIST and dist <= PHASE_MAX_DIST:
			trigger_phase_shift()

	# Desired heading: close in when far, smoothly tangent-orbit at preferred_range for broadsides!
	var dir_to := flat.normalized() if dist > 0.1 else Vector3.FORWARD
	var tangent := Vector3(-dir_to.z, 0.0, dir_to.x) * _orbit_sign
	var radial_weight := clampf((dist - preferred_range) / 55.0, -0.45, 0.92)
	if sails_torn:
		radial_weight = clampf(radial_weight - 0.22, -0.60, 0.70)
	var desired_dir := (tangent * (1.0 - absf(radial_weight) * 0.5) + dir_to * radial_weight).normalized()

	# Steer around nearby islands so AI sloops never run aground!
	desired_dir = _apply_island_avoidance(desired_dir)

	var desired_hdg := atan2(desired_dir.x, -desired_dir.z)
	var cur_hdg := atan2(-ship.global_basis.z.x, -ship.global_basis.z.z)
	var err := wrapf(desired_hdg - cur_hdg, -PI, PI)
	var helm_cmd := clampf(err * 1.15, -1.0, 1.0)
	if sails_torn:
		helm_cmd = clampf(helm_cmd + _evasive_sign * SAIL_DAMAGE_EVASIVE_HELM_BIAS, -1.0, 1.0)
	ship.set_helm_target(helm_cmd)

	# Throttle sails to match engagement range cleanly (push full canvas when recovering from chainshot).
	var want_sail := 1.0 if (sails_torn or dist > preferred_range * 1.35) else (0.72 if dist > 32.0 else 0.45)
	ship.set_sail_target(want_sail)

	# Hold fire while dissolving into or materializing out of the mist.
	if _phase_state != &"solid":
		return

	# Broadside gunnery with velocity lead & ballistic drop!
	_fire_delay = maxf(0.0, _fire_delay - delta)
	if _fire_delay <= 0.0 and dist < 135.0 and ship.cannonballs_remaining > 0:
		_try_broadside(dist)


func _tick_ghost_phase(delta: float) -> void:
	if _phase_state == &"fading_out":
		_phase_elapsed += delta
		var t := clampf(_phase_elapsed / PHASE_OUT_DURATION, 0.0, 1.0)
		var alpha := 1.0 - t
		var flare := lerpf(1.4, 1.85, sin(t * PI))
		ship.set_spectral_phase(alpha, flare)
		if t >= 1.0:
			_execute_phase_teleport()
	elif _phase_state == &"fading_in":
		_phase_elapsed += delta
		var t := clampf(_phase_elapsed / PHASE_IN_DURATION, 0.0, 1.0)
		var flare := lerpf(1.6, 0.0, t)
		ship.set_spectral_phase(t, flare)
		if not _phase_ring_stamped and t >= 0.08:
			_phase_ring_stamped = true
			_stamp_phase_foam_ring(ship.global_position, 9.5)
		if t >= 1.0:
			ship.set_spectral_phase(1.0, 0.0)
			_phase_state = &"solid"
			_phase_timer = phase_cooldown
			_fire_delay = 0.6


func _execute_phase_teleport() -> void:
	if target_ship == null or not is_instance_valid(target_ship) or target_ship.is_sinking:
		_phase_state = &"fading_in"
		_phase_elapsed = 0.0
		_phase_ring_stamped = false
		return

	var old_pos := ship.global_position
	_orbit_sign = -_orbit_sign
	var new_pos := _pick_opposite_beam_position(old_pos)
	new_pos.y = Sea.height(new_pos.x, new_pos.z)

	var to_t := target_ship.global_position - new_pos
	to_t.y = 0.0
	var dir_to := to_t.normalized() if to_t.length_squared() > 0.01 else Vector3.FORWARD
	var broadside_fwd := (Vector3(-dir_to.z, 0.0, dir_to.x) * _orbit_sign).normalized()
	var broadside_yaw := atan2(-broadside_fwd.x, -broadside_fwd.z)

	ship.global_transform = Transform3D(Basis(Vector3.UP, broadside_yaw), new_pos)
	ship.linear_velocity = broadside_fwd * 6.5
	ship.angular_velocity = Vector3.ZERO
	ship.set_spectral_phase(0.0, 1.6)
	ship.trigger_spectral_phase_ring(1.0)

	_stamp_phase_foam_ring(new_pos, 9.5)
	Audio.play_sfx(&"thunder_near", new_pos, -5.0)
	Game.post_notice("Ghost ship vanished into the mist -- watch the opposite beam!")
	phase_shifted.emit(old_pos, new_pos)

	_phase_state = &"fading_in"
	_phase_elapsed = 0.0
	_phase_ring_stamped = false


func _pick_opposite_beam_position(old_pos: Vector3) -> Vector3:
	var t_pos := target_ship.global_position
	var t_right := Vector3(target_ship.global_basis.x.x, 0.0, target_ship.global_basis.x.z)
	if t_right.length_squared() < 0.01:
		t_right = Vector3.RIGHT
	else:
		t_right = t_right.normalized()

	var old_rel := Vector3(old_pos.x - t_pos.x, 0.0, old_pos.z - t_pos.z)
	var old_lateral := old_rel.dot(t_right)
	var beam_sign := -1.0 if old_lateral >= 0.0 else 1.0
	if absf(old_lateral) < 4.0:
		beam_sign = _orbit_sign
	var base_dir := (t_right * beam_sign).normalized()

	var angle_offsets: Array[float] = [
		0.0,
		deg_to_rad(25.0), deg_to_rad(-25.0),
		deg_to_rad(50.0), deg_to_rad(-50.0),
		deg_to_rad(75.0), deg_to_rad(-75.0),
		deg_to_rad(100.0), deg_to_rad(-100.0),
		deg_to_rad(130.0), deg_to_rad(-130.0),
		deg_to_rad(160.0), deg_to_rad(-160.0),
	]
	var radii: Array[float] = [PHASE_AMBUSH_RANGE, 82.0, 112.0]
	for rad in radii:
		for ang in angle_offsets:
			var cand_dir := base_dir.rotated(Vector3.UP, ang)
			var cand := Vector3(t_pos.x + cand_dir.x * rad, 0.0, t_pos.z + cand_dir.z * rad)
			if _is_position_clear_of_islands(cand):
				return cand
	return Vector3(t_pos.x + base_dir.x * PHASE_AMBUSH_RANGE, 0.0, t_pos.z + base_dir.z * PHASE_AMBUSH_RANGE)


func _is_position_clear_of_islands(pos: Vector3) -> bool:
	for node in get_tree().get_nodes_in_group(&"islands"):
		if not (node is Node3D):
			continue
		var isl := node as Node3D
		var raw_r: Variant = isl.get(&"island_radius")
		var min_clear := (float(raw_r) if raw_r != null else 75.0) + 55.0
		var dist_xz := Vector2(pos.x - isl.global_position.x, pos.z - isl.global_position.z).length()
		if dist_xz <= min_clear:
			return false
	return true


func _stamp_phase_foam_ring(center: Vector3, radius: float) -> void:
	if Ocean.current == null:
		return
	Ocean.current.add_foam(center, radius, 1.0)
	for i in 4:
		var ang := float(i) * PI * 0.5 + 0.35
		var p := center + Vector3(cos(ang) * 5.2, 0.0, sin(ang) * 5.2)
		Ocean.current.add_foam(p, 5.5, 0.85)


func _try_broadside(dist: float) -> void:
	var t_local := ship.global_transform.affine_inverse() * target_ship.global_position
	var side: StringName = &"starboard" if t_local.x >= 0.0 else &"port"
	var st := ship.get_station(&"cannon", side)
	if st == null:
		return

	var flight_t := dist / Ship.CANNON_MUZZLE_SPEED
	var aim_world := target_ship.global_position + target_ship.linear_velocity * flight_t + Vector3.UP * 0.5
	var st_local := st.global_transform.affine_inverse() * aim_world
	# Only fire when target is genuinely inside the cannon's lateral arc!
	if st_local.z >= -4.0:
		return
	var yaw := atan2(-st_local.x, -st_local.z)
	if absf(yaw) > 0.52:
		return

	var horiz := maxf(Vector2(st_local.x, st_local.z).length(), 1.0)
	var drop := 0.5 * Cannonball.GRAVITY * flight_t * flight_t
	var pitch := clampf(atan2(st_local.y + drop, horiz), -0.16, 0.40)
	ship.aim_cannon(side, clampf(yaw, -0.55, 0.55), pitch)
	if ship.fire_cannon(side) != null:
		_fire_delay = 2.8 if archetype == &"ghost_ship" else 3.8


func _tick_self_repair(delta: float) -> void:
	if ship.open_hole_count() == 0 and ship.water_level <= 0.05:
		return
	_repair_timer -= delta
	if _repair_timer > 0.0:
		return
	_repair_timer = repair_interval
	var open := ship.get_open_holes()
	if not open.is_empty():
		ship.patch_hole(int(open[0]["index"]))
	elif ship.water_level > 0.1:
		ship.bail(0.18)


func _apply_island_avoidance(desired_dir: Vector3) -> Vector3:
	var steer := desired_dir
	for node in get_tree().get_nodes_in_group(&"islands"):
		if not (node is Node3D):
			continue
		var isl := node as Node3D
		var raw_r: Variant = isl.get(&"island_radius")
		var safe_r := (float(raw_r) if raw_r != null else 75.0) + 55.0
		var away := ship.global_position - isl.global_position
		away.y = 0.0
		var d := away.length()
		if d < safe_r and d > 0.1:
			var push := away / d
			steer += push * (1.0 - d / safe_r) * 2.5
	return steer.normalized() if steer.length_squared() > 0.001 else desired_dir


## Effective spotting range against `target`, shrinking at night when the target runs dark.
func effective_aggro_range(target: Node3D) -> float:
	if target == null or not is_instance_valid(target):
		return aggro_range
	var is_night_sky := Weather != null and Weather.sun_height() < 0.0
	var lit_v: Variant = target.get(&"lanterns_lit")
	var running_dark := lit_v != null and not bool(lit_v)
	if is_night_sky and running_dark:
		return aggro_range * NIGHT_STEALTH_AGGRO_MULT
	return aggro_range


## True while this enemy vessel is suffering active Chainshot sail damage.
func is_sail_damaged() -> bool:
	if ship == null or not is_instance_valid(ship):
		return false
	var sd_v: Variant = ship.get(&"sail_damage_timer")
	return sd_v != null and float(sd_v) > 0.0


func _find_player_ship() -> Ship:
	var best: Ship = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group(&"ship"):
		var s := node as Ship
		if s == null or s == ship or s.is_sinking or s.faction != &"player":
			continue
		var max_range := effective_aggro_range(s)
		var d := ship.global_position.distance_to(s.global_position)
		if d < max_range and d < best_d:
			best_d = d
			best = s
	return best


func _on_sunk() -> void:
	if archetype == &"ghost_ship" and ship != null:
		_phase_state = &"solid"
		ship.set_spectral_phase(1.0, 0.0)
	if not Net.is_host() or _salvage_spawned:
		return
	_salvage_spawned = true
	var parent := ship.get_parent()
	if parent == null:
		return
	var pos := ship.global_position
	var surf := Sea.height(pos.x, pos.z)
	var loot_ids: Array[StringName] = [&"drowned_skull", &"wayfarer_chest"]
	if archetype == &"ghost_ship":
		loot_ids = [&"captains_skull", &"corsair_chest"]
	var spawned: Array = []
	for i in loot_ids.size():
		var off := Vector3((float(i) - 0.5) * 3.5, 0.3, 0.0)
		var item := TreasureCatalog.create_treasure_carryable(loot_ids[i], Vector3(pos.x + off.x, surf + 0.3, pos.z + off.z))
		parent.add_child(item)
		item.global_position = Vector3(pos.x + off.x, surf + 0.3, pos.z + off.z)
		spawned.append(item)
	Audio.play_stinger(&"victory")
	Game.post_notice("Enemy vessel sunk! Salvage floats on the waves!")
	salvage_dropped.emit(pos, spawned)
