class_name AIShipBrain
extends Node
## Naval AI controller for enemy ships (Drowned Sloop and Ghost Ship).
##
## Drives the exact same `Ship` control interface as a player/crew (`set_helm_target`,
## `set_sail_target`, `set_trim_target`, `set_anchor`, `aim_cannon`, `fire_cannon`,
## `patch_hole`, `bail`) so enemy vessels obey identical wave, sail, and flood physics.

signal salvage_dropped(ship_pos: Vector3, items: Array)

@export var archetype: StringName = &"drowned_sloop"  # &"drowned_sloop" or &"ghost_ship"
@export var preferred_range: float = 58.0
@export var aggro_range: float = 480.0
@export var repair_interval: float = 11.0

var ship: Ship = null
var target_ship: Ship = null

var _orbit_sign: float = 1.0  # +1 circles starboard-to-target, -1 port-to-target
var _repair_timer: float = 8.0
var _fire_delay: float = 1.5
var _salvage_spawned: bool = false


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
	else:
		ship.faction = &"drowned"
		ship.speed_modifier = 0.96
		ship.reload_modifier = 1.15
		ship.apply_livery(Color(0.26, 0.34, 0.30), Color(0.18, 0.58, 0.42), Color(0.14, 0.92, 0.52))


## Convenience factory: spawns a ready-to-sail enemy sloop with AIShipBrain.
static func spawn_enemy_sloop(p_archetype: StringName, world_pos: Vector3, parent: Node, target: Ship = null) -> Ship:
	var sloop_scene: PackedScene = load("res://src/ship/sloop.tscn")
	var s := sloop_scene.instantiate() as Ship
	s.name = "GhostSloop" if p_archetype == &"ghost_ship" else "DrownedSloop"
	s.faction = &"ghost" if p_archetype == &"ghost_ship" else &"drowned"
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

	if target_ship == null:
		# Patrol steadily.
		ship.set_sail_target(0.65)
		ship.set_helm_target(0.12)
		return

	var to_t := target_ship.global_position - ship.global_position
	var flat := Vector3(to_t.x, 0.0, to_t.z)
	var dist := flat.length()

	# Desired heading: close in when far, smoothly tangent-orbit at preferred_range for broadsides!
	var dir_to := flat.normalized() if dist > 0.1 else Vector3.FORWARD
	var tangent := Vector3(-dir_to.z, 0.0, dir_to.x) * _orbit_sign
	var radial_weight := clampf((dist - preferred_range) / 55.0, -0.45, 0.92)
	var desired_dir := (tangent * (1.0 - absf(radial_weight) * 0.5) + dir_to * radial_weight).normalized()

	# Steer around nearby islands so AI sloops never run aground!
	desired_dir = _apply_island_avoidance(desired_dir)

	var desired_hdg := atan2(desired_dir.x, -desired_dir.z)
	var cur_hdg := atan2(-ship.global_basis.z.x, -ship.global_basis.z.z)
	var err := wrapf(desired_hdg - cur_hdg, -PI, PI)
	ship.set_helm_target(clampf(err * 1.15, -1.0, 1.0))

	# Throttle sails to match engagement range cleanly.
	var want_sail := 1.0 if dist > preferred_range * 1.35 else (0.72 if dist > 32.0 else 0.45)
	ship.set_sail_target(want_sail)

	# Broadside gunnery with velocity lead & ballistic drop!
	_fire_delay = maxf(0.0, _fire_delay - delta)
	if _fire_delay <= 0.0 and dist < 135.0 and ship.cannonballs_remaining > 0:
		_try_broadside(dist)


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


func _find_player_ship() -> Ship:
	var best: Ship = null
	var best_d := aggro_range
	for node in get_tree().get_nodes_in_group(&"ship"):
		var s := node as Ship
		if s == null or s == ship or s.is_sinking or s.faction != &"player":
			continue
		var d := ship.global_position.distance_to(s.global_position)
		if d < best_d:
			best_d = d
			best = s
	return best


func _on_sunk() -> void:
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
