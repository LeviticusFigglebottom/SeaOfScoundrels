class_name CrewBrain
extends Node
## Utility-based AI crewmate brain. Attach as a child of a `Pawn`.
##
## Uses the exact same Pawn intent fields and Station `drive()` API as a human
## player (docs/ARCHITECTURE.md). Priority hierarchy:
##   1. Survival: patch open hull breaches & bail rising bilge water.
##   2. Active Captain Order (from the Command Wheel).
##   3. Combat: fire ship cannons at hostile ships in broadside arc (unless hold_fire).
##   4. Autonomous sailing: trim sails into the wind, steer autopilot heading if helm free.
##   5. Hauling: fetch dropped treasure chests nearby onto the ship's deck.
##   6. Downtime: lookout callouts, idle banter, and joining the captain's shanty stems.
##
## Runs with `process_physics_priority = -10` so intent is written before Pawn ticks.

signal callout_spoken(speaker: String, text: String, category: StringName)
signal order_changed(order: StringName)
signal task_changed(task: StringName)

## Persona ID from CrewDialogue.PERSONAS (&"helmsman", &"lookout", &"carpenter").
@export var persona_id: StringName = &"helmsman"
## Sighting radius for islands & rival ships (scaled by Economy lookout traits).
@export var lookout_range: float = 520.0
## Base speed multipliers from Economy crew traits.
@export var repair_speed_scale: float = 1.0
@export var bail_speed_scale: float = 1.0

var pawn: Pawn = null
var ship: Ship = null
var captain: Pawn = null

## Active captain order (&"auto", &"helm", &"trim", &"anchor_drop", &"anchor_raise",
## &"cannons", &"repair", &"follow", &"fetch_treasure", &"shanty").
var current_order: StringName = &"auto"
var order_target: Variant = null
var hold_fire: bool = false
## Optional autopilot heading (radians, 0 = -Z) or NaN when holding current heading.
var autopilot_heading: float = NAN
## Optional autopilot world destination (Vector3.INF when unset).
var autopilot_dest: Vector3 = Vector3.INF
## Current active task for HUD/debug/tests.
var current_task: StringName = &"idle"

# Ship-local navigation waypoints connecting quarterdeck, main deck, and hold.
const NAV_QDECK := Vector3(0.0, 2.0, 4.7)
const NAV_QSTAIR_TOP_R := Vector3(1.38, 2.0, 4.15)
const NAV_QSTAIR_BOT_R := Vector3(1.38, 1.1, 2.15)
const NAV_MAIN_MID := Vector3(0.0, 1.1, 2.45)
const NAV_MAIN_FORE := Vector3(0.0, 1.1, -2.6)
const NAV_HOLD_STAIR_MID := Vector3(0.0, 0.2, 1.1)
const NAV_HOLD_FOOT := Vector3(0.0, -0.85, -0.35)
const NAV_HOLD_AFT := Vector3(0.8, -0.85, 1.9)
const NAV_HOLD_FORE := Vector3(0.5, -0.85, -2.0)

var _rng := RandomNumberGenerator.new()
var _route: Array[Vector3] = []  # ship-local waypoints when moving across decks
var _route_is_local: bool = true
var _work_timer: float = 0.0
var _patch_slot: int = -1
var _target_carryable: Carryable = null
var _target_enemy_ship: Ship = null
var _cannon_side: StringName = &"starboard"
var _joining_shanty: bool = false
var _clock: float = 0.0
var _shanty_phase: float = 0.0
var _last_audio_beat: float = -1.0
var _shanty_tool_node: Node3D = null
var _shanty_tool_id: StringName = &""
var _shanty_motes: GPUParticles3D = null
var _shanty_base_rot: Vector3 = Vector3.ZERO
var _scan_timer: float = 0.5
var _banter_timer: float = 28.0
var _callout_cooldowns: Dictionary = {}  # String -> float seconds left
var _reported_islands: Dictionary = {}   # String -> true
var _reported_ships: Dictionary = {}     # int instance_id -> true
var _last_wind_heading: float = NAN
var _was_breached: bool = false


func _init() -> void:
	process_physics_priority = -10


func _ready() -> void:
	pawn = get_parent() as Pawn
	assert(pawn != null, "CrewBrain must be a child of a Pawn")
	_rng.seed = hash(String(persona_id)) ^ 0xC2E47
	_apply_persona_visual()
	_last_wind_heading = Weather.wind_heading
	_banter_timer = _rng.randf_range(22.0, 40.0)


func _exit_tree() -> void:
	_stop_shanty_join(false)


func _find_character_visual() -> CharacterVisual:
	if pawn == null or not is_instance_valid(pawn):
		return null
	var vis := pawn.get_node_or_null(^"Visual/CharacterVisual") as CharacterVisual
	if vis == null:
		vis = pawn.get_node_or_null(^"Visual") as CharacterVisual
	return vis


func _apply_persona_visual() -> void:
	if pawn == null:
		return
	var p := CrewDialogue.get_persona(persona_id)
	var vis: Node = _find_character_visual()
	if vis == null:
		vis = pawn.get_node_or_null(^"Visual")
	if vis != null and vis.has_method(&"set_archetype"):
		vis.call(&"set_archetype", p["archetype"])


## Human-readable crewmate name.
func crew_name() -> String:
	return String(CrewDialogue.get_persona(persona_id)["name"])


## Return the currently equipped 3D shanty instrument prop (or null when idle).
func get_held_shanty_instrument() -> Node3D:
	if _shanty_tool_node != null and is_instance_valid(_shanty_tool_node):
		return _shanty_tool_node
	return null


## Assign ship, captain, and persona in one call.
func setup(p_ship: Ship, p_captain: Pawn, p_persona: StringName = &"helmsman") -> void:
	if _joining_shanty and p_persona != persona_id:
		_stop_shanty_join()
	ship = p_ship
	captain = p_captain
	persona_id = p_persona
	_rng.seed = hash(String(persona_id)) ^ 0xC2E47
	if is_node_ready():
		_apply_persona_visual()


## Apply crew traits from Economy.get_ship_modifiers(profile).
func apply_modifiers(mods: Dictionary) -> void:
	repair_speed_scale = float(mods.get("patch_scale", 1.0))
	bail_speed_scale = float(mods.get("bail_scale", 1.0))
	lookout_range = 520.0 * float(mods.get("lookout_scale", 1.0))


## Captain command-wheel entry point (host only).
func give_order(order: StringName, target: Variant = null) -> void:
	if not Net.is_host():
		return
	if order == &"hold_fire":
		hold_fire = not hold_fire
		_speak(&"order_ack", {"order": "holding fire" if hold_fire else "weapons free"}, "order")
		order_changed.emit(order)
		return
	if order == &"free_fire":
		hold_fire = false
		_speak(&"order_ack", {"order": "weapons free"}, "order")
		order_changed.emit(order)
		return

	current_order = order
	order_target = target
	_route.clear()
	_work_timer = 0.0
	_patch_slot = -1
	if order != &"shanty":
		_stop_shanty_join()
	if pawn != null and pawn.station != null:
		var want_kind := _station_kind_for_order(order)
		if want_kind == &"" or pawn.station.get(&"kind") != want_kind:
			pawn.leave_station()

	if order == &"helm":
		if target is float or target is int:
			autopilot_heading = float(target)
			autopilot_dest = Vector3.INF
		elif target is Vector3:
			autopilot_dest = target
			autopilot_heading = NAN
		elif ship != null:
			autopilot_heading = atan2(-ship.global_basis.z.x, -ship.global_basis.z.z)
			autopilot_dest = Vector3.INF

	var label := _order_label(order)
	_speak(&"order_ack", {"order": label}, "order")
	order_changed.emit(order)


## Gracefully yield this crew slot when a human co-op peer joins.
func yield_to_human_player() -> void:
	if pawn != null and pawn.station != null:
		pawn.leave_station()
	if pawn != null and pawn.carried != null:
		pawn.drop_carried(0.4)
	_stop_shanty_join()
	set_physics_process(false)


# ------------------------------------------------------------------ main tick

func _physics_process(delta: float) -> void:
	_clock += delta
	if not Net.is_host() or pawn == null or pawn.dead:
		if _joining_shanty:
			_stop_shanty_join()
		if pawn != null:
			pawn.wish_dir = Vector3.ZERO
			pawn.wish_sprint = false
			pawn.wish_jump = false
		return

	_tick_cooldowns(delta)
	_tick_lookout(delta)

	# Handle being overboard: swim straight for the nearest hull ladder.
	if ship != null and is_instance_valid(ship) and pawn.is_swimming() and current_order != &"follow":
		_stop_shanty_join()
		_set_task(&"board_ladder")
		_tick_swim_to_ladder()
		return

	var task := _choose_task()
	_set_task(task)
	if task != &"shanty":
		_stop_shanty_join()

	match task:
		&"patch_hole":
			_tick_patch_hole(delta)
		&"bail":
			_tick_bail(delta)
		&"anchor_drop":
			_tick_anchor(true, delta)
		&"anchor_raise":
			_tick_anchor(false, delta)
		&"trim_sails":
			_tick_trim_sails(delta)
		&"set_sails":
			_tick_set_sails(delta)
		&"helm":
			_tick_helm(delta)
		&"cannons":
			_tick_cannons(delta)
		&"fetch_treasure":
			_tick_fetch_treasure(delta)
		&"follow":
			_tick_follow(delta)
		&"shanty":
			_tick_shanty(delta)
		_:
			_tick_idle()


func _choose_task() -> StringName:
	var has_ship := ship != null and is_instance_valid(ship) and not ship.is_sinking

	# 1. Survival beats everything (except explicit follow off-ship when captain is on land).
	if has_ship and (pawn.platform == ship or current_order != &"follow"):
		if ship.open_hole_count() > 0:
			return &"patch_hole"
		var bail_thresh := 0.015 if current_task == &"bail" else 0.14
		if ship.water_level > bail_thresh or (current_order == &"repair" and ship.water_level > 0.02):
			return &"bail"

	# 2. Explicit captain orders.
	match current_order:
		&"anchor_drop":
			if has_ship and not ship.anchor_down:
				return &"anchor_drop"
			current_order = &"auto"
		&"anchor_raise":
			if has_ship and (ship.anchor_down or ship.anchor_progress > 0.05):
				return &"anchor_raise"
			current_order = &"auto"
		&"trim":
			if has_ship:
				if ship.sail_set < 0.9:
					return &"set_sails"
				var order_trim_thresh := 0.06 if current_task == &"trim_sails" else 0.16
				if absf(ship.sail_trim - ship.ideal_sail_trim()) > order_trim_thresh:
					return &"trim_sails"
			current_order = &"auto"
		&"helm":
			if has_ship:
				return &"helm"
		&"cannons":
			if has_ship and not hold_fire:
				return &"cannons"
		&"repair":
			if has_ship and ship.open_hole_count() > 0:
				return &"patch_hole"
			if has_ship and ship.water_level > 0.02:
				return &"bail"
			current_order = &"auto"
		&"follow":
			return &"follow"
		&"fetch_treasure":
			if _find_fetchable_treasure() != null or pawn.carried != null:
				return &"fetch_treasure"
			current_order = &"auto"
		&"shanty":
			return &"shanty"

	# 3. Autonomous combat if hostile ship in broadside range.
	if has_ship and not hold_fire and pawn.platform == ship:
		_target_enemy_ship = _find_hostile_ship(120.0)
		if _target_enemy_ship != null and ship.cannonballs_remaining > 0:
			return &"cannons"

	# 4. Autonomous sail trim when under way and trim is significantly off (with hysteresis).
	if has_ship and pawn.platform == ship and ship.sail_set > 0.15:
		var trim_err := absf(ship.sail_trim - ship.ideal_sail_trim())
		var angle_st := ship.get_station(&"sail_angle")
		var trim_thresh := 0.06 if current_task == &"trim_sails" else 0.28
		if trim_err > trim_thresh and angle_st != null and (angle_st.occupant == null or angle_st.occupant == pawn):
			return &"trim_sails"

	# 5. Autonomous helm if autopilot heading/dest is set and helm is free.
	if has_ship and pawn.platform == ship and (not is_nan(autopilot_heading) or autopilot_dest.is_finite()):
		var helm_st := ship.get_station(&"helm")
		if helm_st != null and (helm_st.occupant == null or helm_st.occupant == pawn):
			return &"helm"

	# 6. Autonomous treasure haul if already carrying or a loose chest is near.
	if has_ship and (pawn.carried != null or _find_fetchable_treasure(18.0) != null):
		return &"fetch_treasure"

	# 7. Join active shanty session during calm downtime!
	if Audio.is_shanty_playing() and has_ship and pawn.platform == ship:
		return &"shanty"

	return &"idle"


func _set_task(t: StringName) -> void:
	if t == current_task:
		return
	# Release station cleanly if switching to a task that does not use it.
	if pawn.station != null:
		var st_kind := StringName(pawn.station.get(&"kind"))
		var keep := (t == &"helm" and st_kind == &"helm") \
			or (t == &"trim_sails" and st_kind == &"sail_angle") \
			or (t == &"set_sails" and st_kind == &"sail_length") \
			or ((t == &"anchor_drop" or t == &"anchor_raise") and st_kind == &"anchor") \
			or (t == &"cannons" and st_kind == &"cannon") \
			or (t == &"bail" and st_kind == &"bilge")
		if not keep:
			pawn.leave_station()
	current_task = t
	_route.clear()
	_work_timer = 0.0
	task_changed.emit(t)


# ------------------------------------------------------------------ task handlers

func _tick_patch_hole(delta: float) -> void:
	var open := ship.get_open_holes()
	if open.is_empty():
		_patch_slot = -1
		return
	var target_hole: Dictionary = open[0]
	var best_d := INF
	var my_local := pawn.platform_local_position()
	for h in open:
		var d := my_local.distance_to(h["local_pos"] as Vector3)
		if d < best_d:
			best_d = d
			target_hole = h
	_patch_slot = int(target_hole["index"])
	var hpos: Vector3 = target_hole["local_pos"]
	var stand_local := Vector3(clampf(hpos.x * 0.45, -0.85, 0.85), -0.85, clampf(hpos.z, -2.8, 3.4))
	if _navigate_ship_local(stand_local, 1.35):
		pawn.wish_dir = Vector3.ZERO
		_face_ship_local(hpos)
		_play_anim(&"hammer", 0.5)
		_work_timer += delta * repair_speed_scale
		if _work_timer >= 1.35:
			_work_timer = 0.0
			if ship.patch_hole(_patch_slot):
				_speak(&"patched", {}, "patched")
			_patch_slot = -1


func _tick_bail(delta: float) -> void:
	var st := ship.get_station(&"bilge")
	if st == null:
		return
	if pawn.station == st:
		pawn.wish_dir = Vector3.ZERO
		_play_anim(&"bail", 0.55)
		pawn.drive_station(Vector2(0.0, 1.0), true, false, delta * bail_speed_scale)
		if ship.water_level <= 0.01:
			pawn.leave_station()
		return
	if _navigate_to_station(st):
		if st.can_occupy(pawn):
			pawn.enter_station(st)
		else:
			# Fallback direct bail if another crewmate occupies the bilge station.
			_play_anim(&"bail", 0.55)
			ship.bail(0.22 * delta * bail_speed_scale)


func _tick_anchor(want_down: bool, delta: float) -> void:
	var st := ship.get_station(&"anchor")
	if st == null:
		return
	if pawn.station == st:
		pawn.wish_dir = Vector3.ZERO
		pawn.drive_station(Vector2(0.0, -1.0 if want_down else 1.0), want_down, not want_down, delta)
		var done := (want_down and ship.anchor_progress >= 0.95) or (not want_down and ship.anchor_progress <= 0.05)
		if done:
			pawn.leave_station()
			if current_order == &"anchor_drop" or current_order == &"anchor_raise":
				current_order = &"auto"
		return
	if _navigate_to_station(st) and st.can_occupy(pawn):
		pawn.enter_station(st)


func _tick_set_sails(delta: float) -> void:
	var st := ship.get_station(&"sail_length")
	if st == null:
		return
	var target_set := 1.0
	if order_target is float or order_target is int:
		target_set = clampf(float(order_target), 0.0, 1.0)
	if pawn.station == st:
		pawn.wish_dir = Vector3.ZERO
		var diff := target_set - ship.sail_set
		if absf(diff) < 0.04:
			ship.set_sail_target(target_set)
			pawn.leave_station()
			return
		var y_in := clampf(diff * 4.0, -1.0, 1.0)
		pawn.drive_station(Vector2(0.0, y_in), diff > 0.0, diff < 0.0, delta)
		return
	if _navigate_to_station(st) and st.can_occupy(pawn):
		pawn.enter_station(st)


func _tick_trim_sails(delta: float) -> void:
	var st := ship.get_station(&"sail_angle")
	if st == null:
		return
	var ideal := ship.ideal_sail_trim()
	if pawn.station == st:
		pawn.wish_dir = Vector3.ZERO
		var diff := ideal - ship.sail_trim
		if absf(diff) < 0.06:
			ship.set_trim_target(ideal)
			pawn.leave_station()
			if ship.wind_catch() > 0.8:
				_speak(&"full_billow", {}, "full_billow")
			return
		var x_in := clampf(diff * 3.0, -1.0, 1.0)
		pawn.drive_station(Vector2(x_in, 0.0), false, false, delta)
		return
	if _navigate_to_station(st) and st.can_occupy(pawn):
		pawn.enter_station(st)


func _tick_helm(delta: float) -> void:
	var st := ship.get_station(&"helm")
	if st == null:
		return
	if pawn.station == st:
		pawn.wish_dir = Vector3.ZERO
		var desired := autopilot_heading
		if autopilot_dest.is_finite():
			var to := autopilot_dest - ship.global_position
			if Vector2(to.x, to.z).length() < 45.0:
				autopilot_dest = Vector3.INF
				desired = atan2(-ship.global_basis.z.x, -ship.global_basis.z.z)
			else:
				desired = atan2(to.x, -to.z)
		if is_nan(desired):
			desired = atan2(-ship.global_basis.z.x, -ship.global_basis.z.z)
		var cur_hdg := atan2(-ship.global_basis.z.x, -ship.global_basis.z.z)
		# Positive heading difference (CW towards +X) needs positive helm (starboard).
		var err := wrapf(desired - cur_hdg, -PI, PI)
		var want_helm := clampf(err * 1.15, -1.0, 1.0)
		var helm_delta := want_helm - ship.helm_target
		var x_in := clampf(helm_delta * 3.0, -1.0, 1.0)
		pawn.drive_station(Vector2(x_in, 0.0), false, absf(want_helm) < 0.04, delta)
		return
	if _navigate_to_station(st) and st.can_occupy(pawn):
		pawn.enter_station(st)


func _tick_cannons(delta: float) -> void:
	var enemy := _target_enemy_ship
	if enemy == null or not is_instance_valid(enemy) or enemy.is_sinking:
		enemy = _find_hostile_ship(140.0)
		_target_enemy_ship = enemy
	if enemy == null:
		if pawn.station != null and pawn.station.get(&"kind") == &"cannon":
			pawn.leave_station()
		if current_order == &"cannons":
			current_order = &"auto"
		return

	# Pick port or starboard cannon facing the target.
	var enemy_local := ship.global_transform.affine_inverse() * enemy.global_position
	_cannon_side = &"starboard" if enemy_local.x >= 0.0 else &"port"
	var st := ship.get_station(&"cannon", _cannon_side)
	if st == null:
		return
	if pawn.station == st:
		pawn.wish_dir = Vector3.ZERO
		# Lead target velocity and compute ballistic elevation.
		var dist := ship.global_position.distance_to(enemy.global_position)
		var flight_t := dist / Ship.CANNON_MUZZLE_SPEED
		var aim_world := enemy.global_position + enemy.linear_velocity * flight_t + Vector3.UP * 0.6
		var st_local := st.global_transform.affine_inverse() * aim_world
		# In station local space, -Z is out the gunport, +X is right.
		var desired_yaw := clampf(atan2(-st_local.x, -st_local.z), -0.58, 0.58)
		var horiz := maxf(Vector2(st_local.x, st_local.z).length(), 1.0)
		var drop := 0.5 * Cannonball.GRAVITY * flight_t * flight_t
		var desired_pitch := clampf(atan2(st_local.y + drop, horiz), -0.18, 0.42)
		ship.aim_cannon(_cannon_side, desired_yaw, desired_pitch)
		var in_arc := st_local.z < -2.0 and absf(atan2(-st_local.x, -st_local.z)) < 0.65
		var fire := in_arc and dist < 130.0
		if fire:
			var ball := ship.fire_cannon(_cannon_side, pawn)
			if ball != null:
				_speak(&"cannon_fire", {}, "cannon_fire")
		else:
			pawn.drive_station(Vector2.ZERO, false, false, delta)
		return
	if _navigate_to_station(st) and st.can_occupy(pawn):
		pawn.enter_station(st)


func _tick_fetch_treasure(_delta: float) -> void:
	if pawn.carried != null:
		# Bring the chest aboard the ship's main deck and set it down cleanly!
		var stow_local := Vector3(0.75, 1.12, -0.6)
		if pawn.platform == ship:
			if _navigate_ship_local(stow_local, 1.0):
				pawn.wish_dir = Vector3.ZERO
				pawn.drop_carried(0.15)
				_speak(&"chest_aboard", {}, "chest_aboard")
				if current_order == &"fetch_treasure":
					current_order = &"auto"
		elif ship != null:
			# Walk / swim towards the ship's ladder to bring the load aboard.
			var ladder_world := ship.global_transform * Vector3(2.8, 0.0, 2.0)
			_move_world_towards(ladder_world, 1.2)
		return

	var item := _find_fetchable_treasure(45.0 if current_order == &"fetch_treasure" else 18.0)
	if item == null:
		current_order = &"auto"
		return
	_target_carryable = item
	if pawn.global_position.distance_to(item.global_position) < 2.2:
		pawn.wish_dir = Vector3.ZERO
		pawn.pick_up(item)
	else:
		_move_world_towards(item.global_position, 1.8)


func _tick_follow(_delta: float) -> void:
	if captain == null or not is_instance_valid(captain):
		pawn.wish_dir = Vector3.ZERO
		return
	var d := captain.global_position - pawn.global_position
	var flat_d := Vector2(d.x, d.z).length()
	if flat_d < 2.6:
		pawn.wish_dir = Vector3.ZERO
		pawn.wish_sprint = false
		return
	if ship != null and pawn.platform == ship and captain.platform == ship:
		_navigate_ship_local(captain.platform_local_position(), 2.4)
	else:
		_move_world_towards(captain.global_position, 2.4, flat_d > 5.5)


func _tick_shanty(delta: float) -> void:
	pawn.wish_dir = Vector3.ZERO
	pawn.wish_sprint = false
	var inst: StringName = CrewDialogue.get_persona(persona_id)["instrument"]
	if not _joining_shanty:
		_joining_shanty = true
		_last_audio_beat = -1.0
		_shanty_phase = Audio.shanty_beat() if Audio.is_shanty_playing() else (_clock * 2.0)
		if not Audio.is_shanty_playing():
			Audio.play_shanty([inst])
		else:
			Audio.set_shanty_instrument(inst, true, 0.35)
		Audio.set_shanty_emitter(inst, pawn)
		_attach_shanty_props(inst)
		_speak(&"shanty_join", {}, "shanty")
	elif _shanty_tool_node == null or not is_instance_valid(_shanty_tool_node):
		var vis := _find_character_visual()
		if vis != null and vis.hand_right != null:
			_attach_shanty_props(inst)

	_play_anim_if_idle(&"play_instrument", 1.6)
	_animate_shanty_instrument(delta)


func _stop_shanty_join(detach_from_parent: bool = true) -> void:
	_detach_shanty_props(detach_from_parent)
	_last_audio_beat = -1.0
	_shanty_phase = 0.0
	if not _joining_shanty:
		return
	_joining_shanty = false
	var inst: StringName = CrewDialogue.get_persona(persona_id)["instrument"]
	if Audio != null:
		Audio.set_shanty_emitter(inst, null)
		Audio.set_shanty_instrument(inst, false, 0.35)


func _attach_shanty_props(inst: StringName) -> void:
	_detach_shanty_props(true)
	var tool_id := _tool_id_for_instrument(inst)
	var vis := _find_character_visual()
	if vis != null and vis.hand_right == null:
		vis.set_archetype(vis.archetype)
	if vis != null and vis.hand_right != null and is_instance_valid(vis.hand_right):
		var prop := ToolMeshes.build_tool(tool_id)
		prop.name = "ShantyInstrument_" + String(tool_id)
		# Position naturally in CharacterVisual.hand_right socket (+Y along fingers, -X forward).
		match tool_id:
			&"hurdy_gurdy":
				prop.position = Vector3(-0.05, 0.13, -0.09)
				prop.rotation_degrees = Vector3(8.0, -14.0, -84.0)
				prop.scale = Vector3.ONE * 0.95
			&"whistle":
				prop.position = Vector3(0.0, 0.085, -0.03)
				prop.rotation_degrees = Vector3(-16.0, 12.0, -80.0)
				prop.scale = Vector3.ONE * 0.95
			_:
				prop.position = Vector3(-0.04, 0.08, -0.08)
				prop.rotation_degrees = Vector3(12.0, -18.0, -78.0)
				prop.scale = Vector3.ONE * 0.95
		vis.hand_right.add_child(prop)
		_shanty_tool_node = prop
		_shanty_tool_id = tool_id
		_shanty_base_rot = prop.rotation

	if pawn != null and is_instance_valid(pawn):
		_shanty_motes = _build_shanty_motes()
		pawn.add_child(_shanty_motes)


func _detach_shanty_props(detach_from_parent: bool = true) -> void:
	if _shanty_motes != null and is_instance_valid(_shanty_motes):
		_shanty_motes.emitting = false
		_shanty_motes.visible = false
		_shanty_motes.draw_pass_1 = null
		_shanty_motes.process_material = null
		if detach_from_parent and _shanty_motes.get_parent() != null:
			_shanty_motes.get_parent().remove_child(_shanty_motes)
		_shanty_motes.queue_free()
	_shanty_motes = null
	if _shanty_tool_node != null and is_instance_valid(_shanty_tool_node):
		if detach_from_parent and _shanty_tool_node.get_parent() != null:
			_shanty_tool_node.get_parent().remove_child(_shanty_tool_node)
		_shanty_tool_node.queue_free()
	_shanty_tool_node = null
	_shanty_tool_id = &""


func _animate_shanty_instrument(delta: float) -> void:
	if _shanty_tool_node == null or not is_instance_valid(_shanty_tool_node):
		return
	var audio_beat := Audio.shanty_beat() if Audio.is_shanty_playing() else -1.0
	if audio_beat >= 0.0 and absf(audio_beat - _last_audio_beat) > 0.0001:
		var wrapped := _last_audio_beat >= 0.0 and audio_beat < _last_audio_beat - 1.0
		_last_audio_beat = audio_beat
		if wrapped:
			_shanty_phase = audio_beat
		elif audio_beat > _shanty_phase:
			_shanty_phase = audio_beat
		else:
			_shanty_phase += delta * 2.0
	else:
		_shanty_phase += delta * 2.0
	var beat := _shanty_phase
	match _shanty_tool_id:
		&"instrument":
			var stretch := 0.5 + 0.46 * sin(beat * PI)
			ToolMeshes.set_concertina_stretch(_shanty_tool_node, stretch)
		&"hurdy_gurdy":
			ToolMeshes.set_hurdy_gurdy_crank(_shanty_tool_node, beat * TAU * 0.5)
		&"whistle":
			var sway := sin(beat * PI) * 0.15
			var nod := sin(beat * TAU) * 0.07
			_shanty_tool_node.rotation = _shanty_base_rot + Vector3(nod, sway, sway * 0.5)


static func _tool_id_for_instrument(inst: StringName) -> StringName:
	match inst:
		&"hurdy_gurdy":
			return &"hurdy_gurdy"
		&"whistle":
			return &"whistle"
		&"concertina":
			return &"instrument"
		_:
			return &"instrument"


static func _build_shanty_motes() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "ShantyMotes"
	p.position = Vector3(0.0, 1.36, -0.24)
	p.amount = 8
	p.lifetime = 1.45
	p.explosiveness = 0.18
	p.randomness = 0.35
	p.local_coords = false
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3.0, 3.0, 3.0))

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.22
	proc.direction = Vector3(0.0, 1.0, 0.0)
	proc.spread = 38.0
	proc.initial_velocity_min = 0.26
	proc.initial_velocity_max = 0.58
	proc.gravity = Vector3(0.0, 0.16, 0.0)
	proc.damping_min = 0.35
	proc.damping_max = 0.65
	proc.scale_min = 0.55
	proc.scale_max = 1.05
	var sc_curve := Curve.new()
	sc_curve.add_point(Vector2(0.0, 0.25))
	sc_curve.add_point(Vector2(0.28, 1.0))
	sc_curve.add_point(Vector2(1.0, 0.05))
	var sc_tex := CurveTexture.new()
	sc_tex.curve = sc_curve
	proc.scale_curve = sc_tex
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.22, 0.68, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.94, 0.68, 0.0),
		Color(1.0, 0.85, 0.38, 0.72),
		Color(1.0, 0.68, 0.22, 0.38),
		Color(0.95, 0.50, 0.12, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.width = 24
	ramp.gradient = grad
	proc.color_ramp = ramp
	p.process_material = proc

	var radial_grad := Gradient.new()
	radial_grad.offsets = PackedFloat32Array([0.0, 0.38, 0.76, 1.0])
	radial_grad.colors = PackedColorArray([
		Color(1.0, 0.98, 0.86, 1.0),
		Color(1.0, 0.88, 0.44, 0.65),
		Color(1.0, 0.70, 0.24, 0.16),
		Color(1.0, 0.55, 0.12, 0.0),
	])
	var mote_tex := GradientTexture2D.new()
	mote_tex.width = 24
	mote_tex.height = 24
	mote_tex.fill = GradientTexture2D.FILL_RADIAL
	mote_tex.fill_from = Vector2(0.5, 0.5)
	mote_tex.fill_to = Vector2(0.5, 0.0)
	mote_tex.gradient = radial_grad

	var quad := QuadMesh.new()
	quad.size = Vector2(0.11, 0.11)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = mote_tex
	quad.material = mat
	p.draw_pass_1 = quad
	p.emitting = true
	return p


func _tick_idle() -> void:
	# Stand at a natural deck lookout spot when nothing urgent needs attention.
	if ship != null and pawn.platform == ship:
		var home := Vector3(-1.0, 1.1, -2.0)
		match persona_id:
			&"helmsman":
				home = Vector3(-1.1, 2.0, 4.7)
			&"lookout":
				home = Vector3(0.0, 1.1, -3.4)
			&"carpenter":
				home = Vector3(1.1, 1.1, -0.4)
		if pawn.platform_local_position().distance_to(home) > 1.2:
			_navigate_ship_local(home, 0.9)
		else:
			pawn.wish_dir = Vector3.ZERO
			pawn.wish_sprint = false
	else:
		pawn.wish_dir = Vector3.ZERO
		pawn.wish_sprint = false


# ------------------------------------------------------------------ navigation

func _navigate_to_station(st: Station) -> bool:
	var stand_world := Pawn.station_stand_transform(st).origin
	if ship != null and pawn.platform == ship:
		var stand_local := ship.global_transform.affine_inverse() * stand_world
		return _navigate_ship_local(stand_local, 0.85)
	return _move_world_towards(stand_world, 0.9)


## Ship-local deck-aware waypoint navigator so crew climb quarterdeck & hold stairs cleanly.
func _navigate_ship_local(goal_local: Vector3, arrive_dist: float = 0.65) -> bool:
	if ship == null:
		return false
	var cur := pawn.platform_local_position()
	var same_level := absf(cur.y - goal_local.y) < 0.65
	if same_level and cur.distance_to(goal_local) <= arrive_dist:
		pawn.wish_dir = Vector3.ZERO
		pawn.wish_sprint = false
		_route.clear()
		return true

	if _route.is_empty() or _route[_route.size() - 1].distance_to(goal_local) > 0.75:
		_route = _plan_ship_route(cur, goal_local)
		_route_is_local = true

	while not _route.is_empty():
		var wp: Vector3 = _route[0]
		var d := wp - cur
		var flat := Vector2(d.x, d.z).length()
		var thresh := arrive_dist if _route.size() == 1 else 0.55
		if flat <= thresh and absf(d.y) < 0.85:
			_route.remove_at(0)
		else:
			var world_dir := ship.global_basis * Vector3(d.x, 0.0, d.z)
			world_dir.y = 0.0
			if world_dir.length_squared() > 0.0001:
				var wd := world_dir.normalized()
				pawn.wish_dir = wd
				pawn.wish_sprint = current_task == &"patch_hole" or current_task == &"bail" or flat > 3.0
				pawn.look_yaw = atan2(-wd.x, -wd.z)
			else:
				pawn.wish_dir = Vector3.ZERO
			return false

	pawn.wish_dir = Vector3.ZERO
	pawn.wish_sprint = false
	return true


func _plan_ship_route(from_l: Vector3, to_l: Vector3) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var from_deck := _deck_band(from_l.y)
	var to_deck := _deck_band(to_l.y)

	if from_deck == to_deck:
		if from_deck == 0 and ((from_l.z > -0.7 and to_l.z < -1.1) or (from_l.z < -1.1 and to_l.z > -0.7)):
			# Walk along the side aisle past the mast pillar at (0, -1.0) in the hold.
			var side_x := 0.82 if from_l.x >= 0.0 else -0.82
			pts.append(Vector3(side_x, -0.85, -0.35))
			pts.append(Vector3(side_x, -0.85, -1.65))
		pts.append(to_l)
		return pts

	# Step 1: get to main deck (band 1) first.
	if from_deck == 2:
		pts.append(NAV_QSTAIR_TOP_R)
		pts.append(NAV_QSTAIR_BOT_R)
	elif from_deck == 0:
		if from_l.z < -1.1:
			var sx := 0.82 if from_l.x >= 0.0 else -0.82
			pts.append(Vector3(sx, -0.85, -1.65))
			pts.append(Vector3(sx, -0.85, -0.35))
		pts.append(NAV_HOLD_FOOT)
		pts.append(NAV_HOLD_STAIR_MID)
		pts.append(NAV_MAIN_MID)

	# Step 2: move from main deck to target deck.
	if to_deck == 2:
		pts.append(NAV_QSTAIR_BOT_R)
		pts.append(NAV_QSTAIR_TOP_R)
	elif to_deck == 0:
		pts.append(NAV_MAIN_MID)
		pts.append(NAV_HOLD_STAIR_MID)
		pts.append(NAV_HOLD_FOOT)
		if to_l.z < -1.1:
			pts.append(Vector3(0.82, -0.85, -0.35))
			pts.append(Vector3(0.82, -0.85, -1.65))

	pts.append(to_l)
	return pts


static func _deck_band(y: float) -> int:
	if y < 0.25:
		return 0  # hold
	if y > 1.65:
		return 2  # quarterdeck
	return 1      # main deck


func _move_world_towards(world_goal: Vector3, arrive_dist: float, sprint: bool = false) -> bool:
	var d := world_goal - pawn.global_position
	var flat := Vector3(d.x, 0.0, d.z)
	if flat.length() <= arrive_dist:
		pawn.wish_dir = Vector3.ZERO
		pawn.wish_sprint = false
		return true
	var dir := flat.normalized()
	pawn.wish_dir = dir
	pawn.wish_sprint = sprint
	pawn.look_yaw = atan2(-dir.x, -dir.z)
	return false


func _tick_swim_to_ladder() -> void:
	if ship == null:
		return
	var best_l: Ladder = null
	var best_d := INF
	for c in ship.get_children():
		if c is Ladder:
			var d := pawn.global_position.distance_to((c as Ladder).global_position)
			if d < best_d:
				best_d = d
				best_l = c as Ladder
	if best_l != null:
		var aim := best_l.global_position + best_l.global_basis.z * 0.35
		_move_world_towards(aim, 0.25, true)


func _face_ship_local(local_target: Vector3) -> void:
	if ship == null:
		return
	var world_t := ship.global_transform * local_target
	var d := world_t - pawn.global_position
	d.y = 0.0
	if d.length_squared() > 0.001:
		pawn.look_yaw = atan2(-d.x, -d.z)


# ------------------------------------------------------------------ sensors & callouts

func _tick_cooldowns(delta: float) -> void:
	var expired: Array[String] = []
	for k: String in _callout_cooldowns:
		_callout_cooldowns[k] = float(_callout_cooldowns[k]) - delta
		if float(_callout_cooldowns[k]) <= 0.0:
			expired.append(k)
	for k in expired:
		_callout_cooldowns.erase(k)


func _tick_lookout(delta: float) -> void:
	_scan_timer -= delta
	_banter_timer -= delta

	# Immediate breach & flooding callouts.
	if ship != null and is_instance_valid(ship):
		var breached := ship.open_hole_count() > 0
		if breached and not _was_breached:
			_speak(&"leak", {}, "leak", 12.0)
		_was_breached = breached
		if ship.water_level > 0.35:
			_speak(&"water_high", {}, "water_high", 22.0)

	if _scan_timer > 0.0:
		return
	_scan_timer = 1.25

	var origin := ship.global_position if ship != null else pawn.global_position

	# Wind shift callout.
	if not is_nan(_last_wind_heading):
		if absf(angle_difference(_last_wind_heading, Weather.wind_heading)) > 0.55:
			_last_wind_heading = Weather.wind_heading
			var wdir := Vector3(sin(Weather.wind_heading), 0.0, -cos(Weather.wind_heading))
			_speak(&"wind_shift", {"bearing": CrewDialogue.compass_bearing(Vector3.ZERO, wdir)}, "wind_shift", 35.0)

	# Hostile ship sightings take top priority over distant landmarks.
	var enemy := _find_hostile_ship(lookout_range)
	if enemy != null:
		var eid := enemy.get_instance_id()
		if not _reported_ships.has(eid):
			_reported_ships[eid] = true
			var label := "Drowned Sloop"
			if enemy.faction == &"ghost":
				label = "Ghost Ship"
			elif enemy.faction == &"corsair":
				label = "Corsair Raider"
			var brg := CrewDialogue.ship_relative_bearing(ship, enemy.global_position)
			_speak(&"sail_sighted", {"target": label, "bearing": brg}, "ship:" + str(eid), 35.0)
			return

	# Island sightings (nodes in group `islands`) ahead or abeam — ignore islands behind the stern.
	for node in get_tree().get_nodes_in_group(&"islands"):
		if not (node is Node3D):
			continue
		var isl := node as Node3D
		var raw_id: Variant = isl.get(&"island_id")
		var id_key: String = String(raw_id) if raw_id != null else String(isl.name)
		if _reported_islands.has(id_key):
			continue
		var dist := origin.distance_to(isl.global_position)
		if dist < lookout_range and dist > 95.0:
			var brg := CrewDialogue.ship_relative_bearing(ship, isl.global_position)
			if brg.contains("stern"):
				continue
			_reported_islands[id_key] = true
			var raw_nm: Variant = isl.get(&"display_name")
			var nm: String = String(raw_nm) if raw_nm != null else String(isl.name)
			if raw_nm == null and isl.has_meta("display_name"):
				nm = String(isl.get_meta("display_name"))
			_speak(&"land_ho", {"target": nm, "bearing": brg}, "land:" + id_key, 60.0)
			break

	# Calm sailing banter.
	if _banter_timer <= 0.0 and current_task == &"idle" and ship != null and ship.forward_speed() > 1.8:
		_banter_timer = _rng.randf_range(42.0, 75.0)
		_speak(&"banter", {}, "banter", 40.0)


func _speak(category: StringName, vars: Dictionary = {}, cd_key: String = "", cooldown: float = 8.0) -> void:
	var key := cd_key if cd_key != "" else String(category)
	if _callout_cooldowns.has(key):
		return
	var text := CrewDialogue.format_line(persona_id, category, vars, _rng)
	if text == "":
		return
	_callout_cooldowns[key] = cooldown
	Game.post_notice(text)
	Audio.play_sfx(&"crew_shout", pawn.global_position, -6.0, 0.08)
	_play_anim(&"shout", 0.7)
	callout_spoken.emit(crew_name(), text, category)


func _find_hostile_ship(max_dist: float) -> Ship:
	if ship == null:
		return null
	var best: Ship = null
	var best_d := max_dist
	for node in get_tree().get_nodes_in_group(&"ship"):
		var s := node as Ship
		if s == null or s == ship or s.is_sinking or s.faction == ship.faction:
			continue
		var d := ship.global_position.distance_to(s.global_position)
		if d < best_d:
			best_d = d
			best = s
	return best


func _find_fetchable_treasure(max_dist: float = 35.0) -> Carryable:
	var best: Carryable = null
	var best_d := max_dist
	for node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var it := node as Interactable
		if it == null or not it.enabled:
			continue
		var tgt := it.get_target()
		if not (tgt is Carryable):
			continue
		var c := tgt as Carryable
		if c.is_held() or c.stored_in != null:
			continue
		# Skip items already neatly stowed on our ship's main deck!
		if ship != null:
			var loc := ship.global_transform.affine_inverse() * c.global_position
			if absf(loc.x) < 1.9 and loc.z > -5.5 and loc.z < 5.5 and loc.y > -1.0 and loc.y < 2.6:
				continue
		var d := pawn.global_position.distance_to(c.global_position)
		if d < best_d:
			best_d = d
			best = c
	return best


func _play_anim(action: StringName, duration: float) -> void:
	if pawn == null:
		return
	var drv := pawn.get_node_or_null(^"Visual/AnimationDriver")
	if drv == null:
		drv = pawn.get_node_or_null(^"AnimationDriver")
	if drv != null and drv.has_method(&"play_action"):
		drv.call(&"play_action", action, duration)


func _play_anim_if_idle(action: StringName, duration: float) -> void:
	if pawn == null:
		return
	var drv := pawn.get_node_or_null(^"Visual/AnimationDriver") as AnimationDriver
	if drv == null:
		drv = pawn.get_node_or_null(^"AnimationDriver") as AnimationDriver
	if drv == null:
		return
	if drv.get_current_action() != action:
		drv.play_action(action, duration)


static func _station_kind_for_order(order: StringName) -> StringName:
	match order:
		&"helm": return &"helm"
		&"trim": return &"sail_angle"
		&"anchor_drop", &"anchor_raise": return &"anchor"
		&"cannons": return &"cannon"
		&"repair": return &"bilge"
		_: return &""


static func _order_label(order: StringName) -> String:
	match order:
		&"helm": return "taking the helm"
		&"trim": return "trimming sails for speed"
		&"anchor_drop": return "dropping the anchor"
		&"anchor_raise": return "heaving the anchor"
		&"cannons": return "manning the cannons"
		&"repair": return "patching and bailing"
		&"follow": return "right behind you"
		&"fetch_treasure": return "fetching the haul"
		&"shanty": return "striking up a tune"
		_: return "standing by"
