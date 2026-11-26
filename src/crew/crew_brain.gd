class_name CrewBrain
extends Node
## Utility-based AI crewmate brain. Attach as a child of a `Pawn`.
##
## Uses the exact same Pawn intent fields and Station `drive()` API as a human
## player (docs/ARCHITECTURE.md). Priority hierarchy:
##   1. Survival: patch open hull breaches & bail rising bilge water.
##   2. Active Captain Order (from the Command Wheel), including ashore/boarding
##      melee escort combat during `"Follow Me"` (`&"follow"`).
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

# Ashore / boarding melee escort combat tuning
const ESCORT_DETECT_RANGE := 15.0
const ESCORT_LEASH_RANGE := 18.0
const ESCORT_ENGAGE_RANGE := 1.85
const ESCORT_ATTACK_REACH := 2.35
const ESCORT_BATTLE_CRY_COOLDOWN := 9.5

const BATTLE_CRY_LINES := {
	&"helmsman": [
		"Stand clear, Cap'n -- I've got your flank!",
		"Steel out! Let's send these bilge-rats packing!",
		"Back to the locker with ye!",
	],
	&"lookout": [
		"Hostiles close! Covering you, Cap'n!",
		"Watch your left -- I'll cut this one down!",
		"Not on my watch! Draw blades!",
	],
	&"carpenter": [
		"Don't worry, Cap'n -- I swing a cutlass as brisk as a hammer!",
		"Oi! Nobody touches my Captain!",
		"I'll patch you up after I finish this lot!",
	],
}

const SHANTY_STEM_POOL: Array[StringName] = [&"hurdy_gurdy", &"whistle", &"concertina"]
const SHANTY_ENCORE_COOLDOWN := 20.0

const SHANTY_ENCORE_LINES := {
	&"helmsman": [
		"Now THAT'S a tune to fill the sails!",
		"Steady rhythm, Cap'n -- another verse for fair winds!",
	],
	&"lookout": [
		"Encore, Captain -- the wind loves a merry band!",
		"Best harmony on the archipelago! Keep it rolling!",
	],
	&"carpenter": [
		"Best jam since Tortuga! Strike up another verse!",
		"Even the hull timbers are tapping along, Cap'n!",
	],
}

const SIGHTING_ACK_COOLDOWN := 4.0
const TOAST_ACK_COOLDOWN := 4.0
const SPLASHED_COOLDOWN := 4.5
const HARPOON_HAUL_COOLDOWN := 6.0
const CHAINSHOT_HIT_COOLDOWN := 8.0
const RUNNING_DARK_COOLDOWN := 6.0
const ROWBOAT_COOLDOWN := 6.0
const EVENT_CLOUD_COOLDOWN := 10.0
const FIRE_CALLOUT_COOLDOWN := 7.0
const CANNON_SELF_LAUNCH_COOLDOWN := 6.0
const SHIPWRECK_COOLDOWN := 10.0
const MERMAID_RETURN_COOLDOWN := 6.0
const MEGALODON_SIGHTED_COOLDOWN := 12.0
const SIGHTING_ACK_TEMPLATES := {
	&"helmsman": "Aye, Captain! {target} to the {bearing} - steady as she goes!",
	&"lookout": "Spotted {target} off the {bearing} - keeping a sharp eye on it!",
	&"carpenter": "{target} to the {bearing}? Guns and planks at the ready, Captain!",
}

var _rng := RandomNumberGenerator.new()
var _route: Array[Vector3] = []  # ship-local waypoints when moving across decks
var _route_is_local: bool = true
var _work_timer: float = 0.0
var _patch_slot: int = -1
var _target_carryable: Carryable = null
var _target_enemy_ship: Ship = null
var _cannon_side: StringName = &"starboard"
var _combat: CombatComponent = null
var _melee_target: Node3D = null
var _melee_target_cc: CombatComponent = null
var _melee_attack_cd: float = 0.0
var _melee_block_timer: float = 0.0
var _melee_combo_count: int = 0
var _joining_shanty: bool = false
var _active_shanty_inst: StringName = &""
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
var _reported_wrecks: Dictionary = {}    # int instance_id -> true
var _reported_megalodons: Dictionary = {} # int instance_id -> true
var _last_wind_heading: float = NAN
var _was_breached: bool = false
var _was_on_fire: bool = false
var _bound_ship: Ship = null


func _init() -> void:
	process_physics_priority = -10


func _enter_tree() -> void:
	add_to_group(&"crew_brains")


func _ready() -> void:
	pawn = get_parent() as Pawn
	assert(pawn != null, "CrewBrain must be a child of a Pawn")
	_rng.seed = hash(String(persona_id)) ^ 0xC2E47
	_apply_persona_visual()
	_last_wind_heading = Weather.wind_heading
	_banter_timer = _rng.randf_range(22.0, 40.0)
	_bind_ship_signals()


func _exit_tree() -> void:
	_unbind_ship_signals()
	_clear_melee_combat()
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


## Return the currently active shanty stem name (`&"hurdy_gurdy"`, `&"whistle"`, `&"concertina"`, or `&""` when idle).
func get_active_shanty_instrument() -> StringName:
	return _active_shanty_inst if _joining_shanty else &""


## Return the currently engaged ashore/boarding melee threat (or null when not fighting).
func get_melee_target() -> Node3D:
	if _melee_target != null and is_instance_valid(_melee_target) and not _is_target_defeated(_melee_target):
		return _melee_target
	return null


## Bind this crewmate to `p_ship` and safely wire optional ship event signals.
func bind_ship(p_ship: Ship) -> void:
	_unbind_ship_signals()
	ship = p_ship
	if is_inside_tree():
		_bind_ship_signals()


func _bind_ship_signals() -> void:
	if _bound_ship != null and _bound_ship != ship:
		_unbind_ship_signals()
	if ship == null or not is_instance_valid(ship):
		return
	_bound_ship = ship
	if _bound_ship.has_signal(&"harpoon_loot_snagged"):
		var cb_harpoon := Callable(self, &"_on_ship_harpoon_loot_snagged")
		if not _bound_ship.is_connected(&"harpoon_loot_snagged", cb_harpoon):
			_bound_ship.connect(&"harpoon_loot_snagged", cb_harpoon)
	if _bound_ship.has_signal(&"lanterns_toggled"):
		var cb_lanterns := Callable(self, &"_on_ship_lanterns_toggled")
		if not _bound_ship.is_connected(&"lanterns_toggled", cb_lanterns):
			_bound_ship.connect(&"lanterns_toggled", cb_lanterns)
	if _bound_ship.has_signal(&"pawn_cannon_launched"):
		var cb_launch := Callable(self, &"_on_ship_pawn_cannon_launched")
		if not _bound_ship.is_connected(&"pawn_cannon_launched", cb_launch):
			_bound_ship.connect(&"pawn_cannon_launched", cb_launch)


func _unbind_ship_signals() -> void:
	if _bound_ship != null and is_instance_valid(_bound_ship):
		if _bound_ship.has_signal(&"harpoon_loot_snagged"):
			var cb_harpoon := Callable(self, &"_on_ship_harpoon_loot_snagged")
			if _bound_ship.is_connected(&"harpoon_loot_snagged", cb_harpoon):
				_bound_ship.disconnect(&"harpoon_loot_snagged", cb_harpoon)
		if _bound_ship.has_signal(&"lanterns_toggled"):
			var cb_lanterns := Callable(self, &"_on_ship_lanterns_toggled")
			if _bound_ship.is_connected(&"lanterns_toggled", cb_lanterns):
				_bound_ship.disconnect(&"lanterns_toggled", cb_lanterns)
		if _bound_ship.has_signal(&"pawn_cannon_launched"):
			var cb_launch := Callable(self, &"_on_ship_pawn_cannon_launched")
			if _bound_ship.is_connected(&"pawn_cannon_launched", cb_launch):
				_bound_ship.disconnect(&"pawn_cannon_launched", cb_launch)
	_bound_ship = null


## Assign ship, captain, and persona in one call.
func setup(p_ship: Ship, p_captain: Pawn, p_persona: StringName = &"helmsman") -> void:
	if _joining_shanty and p_persona != persona_id:
		_stop_shanty_join()
	bind_ship(p_ship)
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
	_clear_melee_combat()
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
		_clear_melee_combat()
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
		&"douse_fire":
			_tick_douse_fire(delta)
		&"mend_rigging":
			_tick_mend_rigging(delta)
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


func _ship_scale() -> float:
	if ship != null and is_instance_valid(ship):
		var hs: Variant = ship.get(&"hull_scale")
		if hs != null and float(hs) > 0.01:
			return float(hs)
	return 1.0


func _needs_mast_repair() -> bool:
	if ship == null or not is_instance_valid(ship):
		return false
	var raw_timer: Variant = ship.get(&"sail_damage_timer")
	return raw_timer != null and float(raw_timer) > 0.0


func _has_active_carpenter_aboard() -> bool:
	if ship == null or not is_instance_valid(ship):
		return false
	for cb in _sibling_crew_brains():
		if cb.ship == ship and cb.persona_id == &"carpenter" \
				and cb.pawn != null and is_instance_valid(cb.pawn) \
				and not cb.pawn.dead and cb.pawn.platform == ship:
			return true
	return false


func _choose_task() -> StringName:
	var has_ship := ship != null and is_instance_valid(ship) and not ship.is_sinking

	# 1. Survival beats everything (except explicit follow off-ship when captain is on land).
	if has_ship and (pawn.platform == ship or current_order != &"follow"):
		if ship.water_level >= 0.65:
			return &"bail"
		if ship.open_hole_count() > 0:
			return &"patch_hole"
		if ship.has_deck_fire() and ship.water_level < 0.65:
			if persona_id == &"carpenter" or current_order == &"repair" or not _has_active_carpenter_aboard():
				return &"douse_fire"
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
		&"set_sails":
			if has_ship:
				var tgt := clampf(float(order_target), 0.0, 1.0) if (order_target is float or order_target is int) else 1.0
				if absf(ship.sail_set - tgt) > 0.05:
					return &"set_sails"
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
			if has_ship and ship.has_deck_fire() and ship.water_level < 0.65:
				return &"douse_fire"
			if has_ship and persona_id == &"carpenter" and _needs_mast_repair():
				var repair_sail_st := ship.get_station(&"sail_length")
				if repair_sail_st != null and (repair_sail_st.occupant == null or repair_sail_st.occupant == pawn):
					return &"mend_rigging"
			current_order = &"auto"
		&"follow":
			return &"follow"
		&"fetch_treasure":
			if _find_fetchable_treasure() != null or pawn.carried != null:
				return &"fetch_treasure"
			current_order = &"auto"
		&"shanty":
			return &"shanty"

	# 2b. Carpenter mast/rigging repair priority when sails are chainshot-damaged and hull is safe.
	if has_ship and pawn.platform == ship and persona_id == &"carpenter" and _needs_mast_repair():
		var mast_st := ship.get_station(&"sail_length")
		if mast_st != null and (mast_st.occupant == null or mast_st.occupant == pawn):
			return &"mend_rigging"

	# 3. Autonomous combat if hostile ship in broadside range.
	if has_ship and not hold_fire and pawn.platform == ship:
		_target_enemy_ship = _find_hostile_ship(120.0)
		if _target_enemy_ship != null and ship.cannonballs_remaining > 0:
			return &"cannons"

	# 4. Autonomous capstan assist: if Captain is actively raising the anchor, pitch in at the capstan!
	if has_ship and pawn.platform == ship and captain != null and is_instance_valid(captain) \
			and not captain.dead and captain.station != null and is_instance_valid(captain.station):
		if StringName(captain.station.get(&"kind")) == &"anchor" and (ship.anchor_down or ship.anchor_progress > 0.05):
			return &"anchor_raise"

	# 5. Autonomous sail trim when under way and trim is significantly off (with hysteresis).
	if has_ship and pawn.platform == ship and ship.sail_set > 0.15:
		var trim_err := absf(ship.sail_trim - ship.ideal_sail_trim())
		var angle_st := ship.get_station(&"sail_angle")
		var trim_thresh := 0.06 if current_task == &"trim_sails" else 0.28
		if trim_err > trim_thresh and angle_st != null and (angle_st.occupant == null or angle_st.occupant == pawn):
			return &"trim_sails"

	# 6. Autonomous helm if autopilot heading/dest is set and helm is free.
	if has_ship and pawn.platform == ship and (not is_nan(autopilot_heading) or autopilot_dest.is_finite()):
		var helm_st := ship.get_station(&"helm")
		if helm_st != null and (helm_st.occupant == null or helm_st.occupant == pawn):
			return &"helm"

	# 7. Autonomous treasure haul if already carrying or a loose chest is near.
	if has_ship and (pawn.carried != null or _find_fetchable_treasure(18.0) != null):
		return &"fetch_treasure"

	# 7b. Any otherwise idle crewmate pitches in to douse deck fires!
	if has_ship and pawn.platform == ship and ship.has_deck_fire() and ship.water_level < 0.65:
		return &"douse_fire"

	# 8. Join active shanty session during calm downtime!
	if Audio.is_shanty_playing() and has_ship and pawn.platform == ship:
		return &"shanty"

	# 9. Autonomous close-quarters defense when ashore or facing boarders on deck.
	if not hold_fire and _resolve_combat() != null:
		var off_ship := not has_ship or pawn.platform != ship
		var cap_ashore := captain != null and is_instance_valid(captain) and not captain.dead and (not has_ship or captain.platform != ship)
		if off_ship or cap_ashore:
			if _find_nearby_melee_threat(_resolve_combat(), false) != null:
				return &"follow"
		elif has_ship and _find_nearby_melee_threat(_resolve_combat(), true) != null:
			return &"follow"

	return &"idle"


func _set_task(t: StringName) -> void:
	if t == current_task:
		return
	if current_task == &"follow" and t != &"follow":
		_clear_melee_combat()
	# Release station cleanly if switching to a task that does not use it.
	if pawn.station != null:
		var st_kind := StringName(pawn.station.get(&"kind"))
		var keep := (t == &"helm" and st_kind == &"helm") \
			or (t == &"trim_sails" and st_kind == &"sail_angle") \
			or ((t == &"set_sails" or t == &"mend_rigging") and st_kind == &"sail_length") \
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
	var hs := _ship_scale()
	var is_brig := ship.ship_class == &"brigantine"
	var hpos: Vector3 = target_hole["local_pos"]
	var x_lim := (1.15 if is_brig else 0.85) * hs
	var z_min := (-4.2 if is_brig else -2.8) * hs
	var z_max := (4.8 if is_brig else 3.4) * hs
	var hold_y := (-0.95 if is_brig else -0.85) * hs
	var stand_local := Vector3(clampf(hpos.x * 0.45, -x_lim, x_lim), hold_y, clampf(hpos.z, z_min, z_max))
	if _navigate_ship_local(stand_local, 1.35 * hs):
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


func _tick_douse_fire(delta: float) -> void:
	if ship == null or not is_instance_valid(ship) or not ship.has_deck_fire():
		return
	_speak(&"fire_aboard", {}, "fire_aboard", FIRE_CALLOUT_COOLDOWN)
	var sf := ship.get_ship_fire()
	if sf == null:
		return
	var fire_world := sf.get_nearest_fire_world_pos(pawn.global_position)
	if not fire_world.is_finite():
		return
	var hs := _ship_scale()
	var fire_local := ship.global_transform.affine_inverse() * fire_world
	var arrived := false
	if pawn.platform == ship:
		arrived = _navigate_ship_local(fire_local, 2.2 * hs)
		if not arrived:
			var cur_local := pawn.platform_local_position()
			if absf(cur_local.y - fire_local.y) < 0.85 * hs \
					and pawn.global_position.distance_to(fire_world) <= 2.5 * hs:
				arrived = true
	else:
		arrived = _move_world_towards(fire_world, 2.2, true)
	if arrived:
		pawn.wish_dir = Vector3.ZERO
		pawn.wish_sprint = false
		_face_ship_local(fire_local)
		_play_anim(&"bail", 0.55)
		_work_timer += delta * bail_speed_scale
		if _work_timer >= 0.45:
			_work_timer = 0.0
			var doused := ship.douse_deck_fire(fire_world, 4.8)
			Audio.play_sfx(&"bucket_splash", fire_world, -1.5)
			if doused > 0:
				_speak(&"fire_doused", {}, "fire_doused", FIRE_CALLOUT_COOLDOWN)


func _tick_mend_rigging(delta: float) -> void:
	var st := ship.get_station(&"sail_length")
	if st == null:
		return
	if not _needs_mast_repair():
		if pawn.station == st:
			pawn.leave_station()
		return
	if pawn.station == st:
		pawn.wish_dir = Vector3.ZERO
		# Haul [W] (axis = Vector2(0.0, 1.0)) on Station_SailLength to mend damaged rigging.
		pawn.drive_station(Vector2(0.0, 1.0), false, false, delta)
		return
	if _navigate_to_station(st) and st.can_occupy(pawn):
		pawn.enter_station(st)


func _tick_anchor(want_down: bool, delta: float) -> void:
	var st := ship.get_station(&"anchor")
	if st == null:
		return
	if pawn.station == st:
		pawn.wish_dir = Vector3.ZERO
		# Sea-of-Thieves polarity: W (axis.y > 0) / primary heaves anchor up; S (axis.y < 0) / secondary drops anchor.
		if want_down:
			pawn.drive_station(Vector2(0.0, -1.0), false, true, delta)
		else:
			pawn.drive_station(Vector2(0.0, 1.0), true, false, delta)
		var done := (want_down and ship.anchor_down and ship.anchor_progress >= 0.95) \
			or (not want_down and not ship.anchor_down and ship.anchor_progress <= 0.05)
		if done:
			pawn.leave_station()
			if current_order == &"anchor_drop" or current_order == &"anchor_raise":
				current_order = &"auto"
		return
	if not want_down and st.is_occupied() and st.occupant != pawn:
		# Captain or another crewmate is already on the capstan: stand within 2.0 m and push a bar for multi-hand boost!
		var hs := _ship_scale()
		var st_local := ship.global_transform.affine_inverse() * st.global_position
		var stand_local := ship.global_transform.affine_inverse() * Pawn.station_stand_transform(st).origin
		var angle_off := 2.1 if persona_id == &"lookout" else (-2.1 if persona_id == &"carpenter" else PI)
		var bar_r := 0.95 * hs
		var beam_lim := (2.0 if ship.ship_class == &"brigantine" else 1.60) * hs
		var helper_local := Vector3(
			clampf(st_local.x + sin(angle_off) * bar_r, -beam_lim, beam_lim),
			stand_local.y,
			st_local.z + cos(angle_off) * bar_r
		)
		var dist_to_capstan := pawn.global_position.distance_to(st.global_position)
		if _navigate_ship_local(helper_local, 0.85 * hs) or dist_to_capstan <= 1.85:
			pawn.wish_dir = Vector3.ZERO
			pawn.wish_sprint = false
			_face_ship_local(st_local)
			_play_anim_if_idle(&"bail", 0.70)
		return
	if _navigate_to_station(st):
		if want_down and not ship.anchor_down and ship.anchor_progress <= 0.06 \
				and st.has_method(&"try_quick_use") and bool(st.call(&"try_quick_use", pawn)):
			if current_order == &"anchor_drop":
				current_order = &"auto"
			return
		if st.can_occupy(pawn):
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
		# Sea-of-Thieves hoist polarity: S (axis.y < 0) / primary lowers sail (+sail_set); W (axis.y > 0) / secondary raises.
		var y_in := clampf(-diff * 4.0, -1.0, 1.0)
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
		var hs := _ship_scale()
		var stow_local := Vector3(0.75, 1.12, -0.6) * hs
		if pawn.platform == ship:
			if _navigate_ship_local(stow_local, 1.0 * hs):
				pawn.wish_dir = Vector3.ZERO
				pawn.drop_carried(0.15)
				_speak(&"chest_aboard", {}, "chest_aboard")
				if current_order == &"fetch_treasure":
					current_order = &"auto"
		elif ship != null:
			# Walk / swim towards the ship's ladder to bring the load aboard.
			var ladder_world := ship.global_transform * (Vector3(2.8, 0.0, 2.0) * hs)
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


func _tick_follow(delta: float) -> void:
	var cc := _resolve_combat()
	if cc != null:
		var same_ship_only := current_order != &"follow" and ship != null and is_instance_valid(ship) and pawn.platform == ship
		var threat := _update_melee_target(cc, same_ship_only)
		if threat != null:
			_tick_escort_melee(cc, delta)
			return
		_clear_melee_combat()

	if captain == null or not is_instance_valid(captain):
		pawn.wish_dir = Vector3.ZERO
		pawn.wish_sprint = false
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


func _resolve_combat() -> CombatComponent:
	if _combat != null and is_instance_valid(_combat):
		return _combat
	if pawn == null or not is_instance_valid(pawn):
		return null
	var cc := pawn.get_node_or_null(^"CombatComponent") as CombatComponent
	if cc == null:
		for child in pawn.get_children():
			if child is CombatComponent:
				cc = child as CombatComponent
				break
	_combat = cc
	return _combat


func _clear_melee_combat() -> void:
	if _combat != null and is_instance_valid(_combat) and _combat.is_blocking:
		_combat.set_blocking(false)
	_melee_target = null
	_melee_target_cc = null
	_melee_block_timer = 0.0
	_melee_combo_count = 0


func _update_melee_target(cc: CombatComponent, same_ship_only: bool) -> Node3D:
	var my_pos := pawn.global_position
	var has_cap := captain != null and is_instance_valid(captain) and not captain.dead
	var cap_pos := captain.global_position if has_cap else my_pos

	if _melee_target != null:
		if not is_instance_valid(_melee_target) or _is_target_defeated(_melee_target):
			_melee_target = null
			_melee_target_cc = null
		else:
			var d_me := my_pos.distance_to(_melee_target.global_position)
			var d_cap := cap_pos.distance_to(_melee_target.global_position)
			var dy := absf(_melee_target.global_position.y - my_pos.y)
			var out_of_leash := minf(d_me, d_cap) > ESCORT_LEASH_RANGE or (has_cap and d_cap > ESCORT_LEASH_RANGE + 4.0) or dy > 5.5
			if same_ship_only and not (_melee_target is Pawn and (_melee_target as Pawn).platform == ship):
				out_of_leash = true
			if out_of_leash:
				_melee_target = null
				_melee_target_cc = null

	var fresh := _find_nearby_melee_threat(cc, same_ship_only)
	if _melee_target == null:
		_melee_target = fresh
		_melee_target_cc = _combat_component_of(fresh)
	elif fresh != null and fresh != _melee_target:
		# Switch cleanly if another hostile rushes right into our face.
		var cur_d := my_pos.distance_to(_melee_target.global_position)
		var new_d := my_pos.distance_to(fresh.global_position)
		if new_d < 3.0 and new_d + 1.5 < cur_d:
			_melee_target = fresh
			_melee_target_cc = _combat_component_of(fresh)
	return _melee_target


func _find_nearby_melee_threat(cc: CombatComponent, same_ship_only: bool) -> Node3D:
	if pawn == null or not is_inside_tree():
		return null
	var my_pos := pawn.global_position
	var has_cap := captain != null and is_instance_valid(captain) and not captain.dead
	var cap_pos := captain.global_position if has_cap else my_pos
	var my_faction := cc.faction if cc != null else &"player"

	var best: Node3D = null
	var best_score := INF

	# 1. Hostile combatants (Drowned, Tidecallers, Corsairs).
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var other_cc := node as CombatComponent
		if other_cc == null or other_cc == cc or other_cc.faction == my_faction or other_cc.faction == &"player":
			continue
		var other_p := other_cc.pawn
		if other_p == null or not is_instance_valid(other_p) or other_p.dead:
			continue
		if same_ship_only and other_p.platform != ship:
			continue
		if absf(other_p.global_position.y - my_pos.y) > 5.5:
			continue
		var d_me := my_pos.distance_to(other_p.global_position)
		var d_cap := cap_pos.distance_to(other_p.global_position)
		if minf(d_me, d_cap) > ESCORT_DETECT_RANGE:
			continue
		var score := minf(d_me, d_cap * 0.92)
		if score < best_score:
			best_score = score
			best = other_p

	# 2. Hostile wildlife / beasts (IslandCrab, Shark, ReefEel).
	if not same_ship_only:
		for node in get_tree().get_nodes_in_group(&"beasts"):
			if not (node is Node3D) or not node.has_method(&"apply_damage"):
				continue
			if _is_target_defeated(node):
				continue
			var fac: Variant = node.get(&"faction")
			if fac != null and StringName(fac) == &"player":
				continue
			var beast := node as Node3D
			if absf(beast.global_position.y - my_pos.y) > 4.5:
				continue
			var d_me := my_pos.distance_to(beast.global_position)
			var d_cap := cap_pos.distance_to(beast.global_position)
			if minf(d_me, d_cap) > ESCORT_DETECT_RANGE:
				continue
			# Don't leap off dry ground/deck into deep water to chase distant aquatic predators.
			if (beast is Shark or beast is ReefEel) and not pawn.is_swimming() and d_me > 3.2:
				continue
			var score := minf(d_me, d_cap * 0.95) + 1.0
			if score < best_score:
				best_score = score
				best = beast

	return best


func _tick_escort_melee(cc: CombatComponent, delta: float) -> void:
	if _melee_target == null or not is_instance_valid(_melee_target) or _is_target_defeated(_melee_target):
		_clear_melee_combat()
		return

	# Ensure a melee weapon (cutlass) is ready for close-quarters escort combat.
	var spec: Dictionary = CombatComponent.WEAPONS.get(cc.equipped_weapon, {})
	if spec.get("type") != &"melee":
		cc.equip_weapon(&"cutlass")

	_melee_attack_cd = maxf(0.0, _melee_attack_cd - delta)
	if _melee_block_timer > 0.0:
		_melee_block_timer = maxf(0.0, _melee_block_timer - delta)
		if _melee_block_timer <= 0.0 and cc.is_blocking:
			cc.set_blocking(false)

	var to_t := _melee_target.global_position - pawn.global_position
	var flat_to := Vector3(to_t.x, 0.0, to_t.z)
	var dist := flat_to.length()
	if dist > 0.05:
		pawn.look_yaw = atan2(-flat_to.x, -flat_to.z)

	# Atmospheric persona battle-cry on engagement (generous cooldown prevents spam).
	_speak(&"battle_cry", {}, "battle_cry", ESCORT_BATTLE_CRY_COOLDOWN)

	# Reactive cutlass block / timed parry when facing a threat mid-windup.
	var enemy_winding := _melee_target_cc != null and is_instance_valid(_melee_target_cc) \
		and _melee_target_cc.state == CombatComponent.State.WINDUP
	if enemy_winding and dist <= 2.9 and _melee_block_timer <= 0.0 \
			and cc.state == CombatComponent.State.IDLE and cc.stamina >= 22.0:
		if _rng.randf() < 0.55:
			cc.set_blocking(true)
			_melee_block_timer = 0.36
			pawn.wish_dir = Vector3.ZERO
			pawn.wish_sprint = false
			return

	if _melee_block_timer > 0.0:
		pawn.wish_dir = Vector3.ZERO
		pawn.wish_sprint = false
		return

	# Close smoothly to cutlass engagement range (~1.85 m) and keep clean spacing.
	if dist > ESCORT_ENGAGE_RANGE:
		if cc.is_blocking:
			cc.set_blocking(false)
		if ship != null and pawn.platform == ship and _melee_target is Pawn and (_melee_target as Pawn).platform == ship:
			_navigate_ship_local((_melee_target as Pawn).platform_local_position(), ESCORT_ENGAGE_RANGE)
		else:
			_move_world_towards(_melee_target.global_position, ESCORT_ENGAGE_RANGE, dist > 3.8)
	elif dist < 0.95 and dist > 0.05:
		pawn.wish_dir = -(flat_to / dist) * 0.55
		pawn.wish_sprint = false
	else:
		pawn.wish_dir = Vector3.ZERO
		pawn.wish_sprint = false

	# Re-aim toward the threat after movement so every strike lands squarely inside arc_cos.
	if dist > 0.05:
		pawn.look_yaw = atan2(-flat_to.x, -flat_to.z)

	if dist <= ESCORT_ATTACK_REACH and _melee_attack_cd <= 0.0 \
			and cc.state != CombatComponent.State.STAGGERED \
			and cc.state != CombatComponent.State.WINDUP \
			and cc.state != CombatComponent.State.ACTIVE:
		var target_guarding := _melee_target_cc != null and is_instance_valid(_melee_target_cc) \
			and (_melee_target_cc.has_shield or _melee_target_cc.is_blocking)
		var want_heavy := (target_guarding and cc.stamina >= 30.0) or (_melee_combo_count >= 3 and cc.stamina >= 38.0)
		if want_heavy and cc.heavy_attack():
			_melee_combo_count = 0
			_melee_attack_cd = _rng.randf_range(0.65, 0.95)
		elif cc.primary_attack():
			_melee_combo_count += 1
			_melee_attack_cd = _rng.randf_range(0.28, 0.52)


static func _combat_component_of(node: Node) -> CombatComponent:
	if node == null or not is_instance_valid(node):
		return null
	var cc := node.get_node_or_null(^"CombatComponent") as CombatComponent
	if cc != null:
		return cc
	for child in node.get_children():
		if child is CombatComponent:
			return child as CombatComponent
	return null


static func _is_target_defeated(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return true
	if node is Pawn:
		return (node as Pawn).dead
	var d: Variant = node.get(&"dead")
	if d is bool and bool(d):
		return true
	var hp: Variant = node.get(&"health")
	if (hp is float or hp is int) and float(hp) <= 0.0:
		return true
	return false


func _tick_shanty(delta: float) -> void:
	pawn.wish_dir = Vector3.ZERO
	pawn.wish_sprint = false
	if not _joining_shanty:
		var chosen := _choose_shanty_instrument()
		_enter_shanty_jam(chosen)
	else:
		# If the captain cycles onto our stem mid-song, smoothly hand off to a complementary stem!
		var cap_inst := _captain_playing_instrument()
		if cap_inst != &"" and cap_inst == _active_shanty_inst:
			var next_inst := _choose_shanty_instrument()
			if next_inst != _active_shanty_inst:
				_handoff_shanty_instrument(next_inst)
		if _shanty_tool_node == null or not is_instance_valid(_shanty_tool_node):
			var vis := _find_character_visual()
			if vis != null and vis.hand_right != null:
				_attach_shanty_props(_active_shanty_inst)

	_play_anim_if_idle(&"play_instrument", 1.6)
	_animate_shanty_instrument(delta)


func _enter_shanty_jam(inst: StringName) -> void:
	_joining_shanty = true
	_active_shanty_inst = inst
	_last_audio_beat = -1.0
	_shanty_phase = Audio.shanty_beat() if Audio.is_shanty_playing() else (_clock * 2.0)
	if not Audio.is_shanty_playing():
		Audio.play_shanty([inst])
	else:
		Audio.set_shanty_instrument(inst, true, 0.35)
	Audio.set_shanty_emitter(inst, pawn)
	_attach_shanty_props(inst)
	_speak(&"shanty_join", {}, "shanty")


func _handoff_shanty_instrument(next_inst: StringName) -> void:
	if next_inst == &"" or next_inst == _active_shanty_inst:
		return
	var old_inst := _active_shanty_inst
	if Audio != null and old_inst != &"":
		Audio.set_shanty_emitter(old_inst, null)
		if not _is_stem_active_elsewhere(old_inst):
			Audio.set_shanty_instrument(old_inst, false, 0.25)
	_active_shanty_inst = next_inst
	if Audio != null and Audio.is_shanty_playing():
		Audio.set_shanty_instrument(next_inst, true, 0.25)
		Audio.set_shanty_emitter(next_inst, pawn)
	_attach_shanty_props(next_inst)


func _captain_playing_instrument() -> StringName:
	if captain == null or not is_instance_valid(captain):
		return &""
	var inv := captain.get_node_or_null(^"Inventory") as Inventory
	if inv == null:
		for c in captain.get_children():
			if c is Inventory:
				inv = c as Inventory
				break
	if inv != null and inv.playing_shanty:
		return inv.shanty_instrument
	return &""


func _sibling_crew_brains() -> Array[CrewBrain]:
	var out: Array[CrewBrain] = []
	if not is_inside_tree():
		return out
	for node in get_tree().get_nodes_in_group(&"crew_brains"):
		var cb := node as CrewBrain
		if cb != null and cb != self and is_instance_valid(cb):
			out.append(cb)
	return out


func _is_stem_active_elsewhere(inst: StringName) -> bool:
	if _captain_playing_instrument() == inst:
		return true
	for cb in _sibling_crew_brains():
		if cb._joining_shanty and cb._active_shanty_inst == inst:
			return true
	return false


func _choose_shanty_instrument() -> StringName:
	var pref: StringName = CrewDialogue.get_persona(persona_id)["instrument"]
	var cap_inst := _captain_playing_instrument()
	var used: Array[StringName] = []
	if cap_inst != &"":
		used.append(cap_inst)
	for cb in _sibling_crew_brains():
		if cb._joining_shanty and cb._active_shanty_inst != &"" and not used.has(cb._active_shanty_inst):
			used.append(cb._active_shanty_inst)
	if pref != cap_inst and not used.has(pref):
		return pref
	for cand in SHANTY_STEM_POOL:
		if not used.has(cand):
			return cand
	if pref != cap_inst:
		return pref
	for cand in SHANTY_STEM_POOL:
		if cand != cap_inst:
			return cand
	return pref


func _stop_shanty_join(detach_from_parent: bool = true) -> void:
	_detach_shanty_props(detach_from_parent)
	_last_audio_beat = -1.0
	_shanty_phase = 0.0
	if not _joining_shanty:
		_active_shanty_inst = &""
		return
	var inst := _active_shanty_inst if _active_shanty_inst != &"" else StringName(CrewDialogue.get_persona(persona_id)["instrument"])
	_joining_shanty = false
	_active_shanty_inst = &""
	if Audio != null:
		Audio.set_shanty_emitter(inst, null)
		if not _is_stem_active_elsewhere(inst):
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
			_trigger_shanty_encore_toast()
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


func _trigger_shanty_encore_toast() -> void:
	if _callout_cooldowns.has("shanty_encore"):
		return
	_speak(&"shanty_encore", {}, "shanty_encore", SHANTY_ENCORE_COOLDOWN)
	for other in _sibling_crew_brains():
		other._callout_cooldowns["shanty_encore"] = SHANTY_ENCORE_COOLDOWN


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


func _idle_watch_spot() -> Vector3:
	var hs := _ship_scale()
	var is_brig := ship != null and ship.ship_class == &"brigantine"
	match persona_id:
		&"helmsman":
			return (Vector3(-1.85, 1.25, 2.25) if is_brig else Vector3(-1.55, 1.12, 1.35)) * hs
		&"lookout":
			return (Vector3(0.0, 1.25, -6.10) if is_brig else Vector3(0.0, 1.12, -3.75)) * hs
		&"carpenter":
			return (Vector3(1.85, 1.25, -1.10) if is_brig else Vector3(1.55, 1.12, -0.95)) * hs
	return (Vector3(-1.55, 1.25, 0.0) if is_brig else Vector3(-1.35, 1.12, 0.0)) * hs


func _tick_idle() -> void:
	# Stand at a spacious spread-out deck lookout spot and respect personal space (min_sep = 2.0 m).
	if ship != null and pawn.platform == ship:
		var hs := _ship_scale()
		var is_brig := ship.ship_class == &"brigantine"
		var cur_local := pawn.platform_local_position()
		var my_band := _deck_band(cur_local.y / hs)
		var home := _idle_watch_spot()
		var home_band := _deck_band(home.y / hs)

		var peers: Array[Pawn] = []
		if captain != null and is_instance_valid(captain) and not captain.dead:
			peers.append(captain)
		for cb in _sibling_crew_brains():
			if cb.pawn != null and is_instance_valid(cb.pawn) and not cb.pawn.dead:
				peers.append(cb.pawn)

		# If we are on a different deck than our watch post (e.g., quarterdeck), walk to our watch post first.
		var min_sep := 2.0
		var home_blocked := false
		for other_p in peers:
			if other_p.platform == ship:
				var ol := other_p.platform_local_position()
				if _deck_band(ol.y / hs) == home_band \
						and Vector2(ol.x - home.x, ol.z - home.z).length() < min_sep:
					home_blocked = true
					break

		if my_band != home_band and not home_blocked:
			_navigate_ship_local(home, 0.9 * hs)
			return

		# Personal-space separation: gently sidestep away if Captain or another Pawn is within 2.0 m on our deck band.
		var repel_local := Vector3.ZERO
		for other_p in peers:
			if other_p == pawn or other_p.platform != ship:
				continue
			var other_local := other_p.platform_local_position()
			if _deck_band(other_local.y / hs) != my_band:
				continue
			var diff := Vector3(cur_local.x - other_local.x, 0.0, cur_local.z - other_local.z)
			var d := diff.length()
			if d < min_sep:
				var push_dir := diff / d if d > 0.05 else Vector3(1.0 if cur_local.x >= 0.0 else -1.0, 0.0, 0.0)
				var weight := 1.4 if other_p == captain else 1.0
				repel_local += push_dir * ((min_sep - d) / min_sep) * weight

		if repel_local.length_squared() > 0.002:
			var beam_lim := (1.95 if is_brig else 1.65) * hs
			var z_min := (-6.2 if is_brig else -3.85) * hs
			var z_max := (3.4 if is_brig else 2.25) * hs
			if my_band == 2:
				z_min = (4.2 if is_brig else 3.2) * hs
				z_max = (6.8 if is_brig else 5.0) * hs
			elif my_band == 0:
				z_min = (-4.2 if is_brig else -2.8) * hs
				z_max = (4.8 if is_brig else 3.4) * hs
			var step_dir := repel_local.normalized()
			var target_l := Vector3(
				clampf(cur_local.x + step_dir.x * 1.35, -beam_lim, beam_lim),
				cur_local.y,
				clampf(cur_local.z + step_dir.z * 1.35, z_min, z_max)
			)
			var move_l := Vector3(target_l.x - cur_local.x, 0.0, target_l.z - cur_local.z)
			# If pinned against a hull rail or bulkhead, slide smoothly along the open deck walkway!
			if move_l.length() < 0.55:
				var rail_blocked := absf(cur_local.x + step_dir.x * 0.5) > beam_lim - 0.15
				var z_mid := 0.5 * (z_min + z_max)
				if rail_blocked:
					var slide_z := 1.0 if step_dir.z > 0.1 else (-1.0 if step_dir.z < -0.1 else (1.0 if cur_local.z < z_mid else -1.0))
					var z_try := clampf(cur_local.z + slide_z * 1.45, z_min, z_max)
					if absf(z_try - cur_local.z) < 0.45:
						z_try = clampf(cur_local.z - slide_z * 1.45, z_min, z_max)
					target_l = Vector3(clampf(cur_local.x - signf(cur_local.x) * 0.25, -beam_lim, beam_lim), cur_local.y, z_try)
				else:
					var slide_x := 1.0 if cur_local.x < 0.0 else -1.0
					target_l = Vector3(clampf(cur_local.x + slide_x * 1.35, -beam_lim, beam_lim), cur_local.y, target_l.z)
				move_l = Vector3(target_l.x - cur_local.x, 0.0, target_l.z - cur_local.z)
			if move_l.length() > 0.12:
				var world_dir := ship.global_basis * move_l
				world_dir.y = 0.0
				if world_dir.length_squared() > 0.0001:
					var wd := world_dir.normalized()
					pawn.wish_dir = wd * 0.72
					pawn.wish_sprint = false
					pawn.look_yaw = atan2(-wd.x, -wd.z)
					return

		if not home_blocked and cur_local.distance_to(home) > 1.2 * hs:
			_navigate_ship_local(home, 0.9 * hs)
		else:
			pawn.wish_dir = Vector3.ZERO
			pawn.wish_sprint = false
	else:
		pawn.wish_dir = Vector3.ZERO
		pawn.wish_sprint = false


# ------------------------------------------------------------------ navigation

func _navigate_to_station(st: Station) -> bool:
	var hs := _ship_scale()
	var stand_world := Pawn.station_stand_transform(st).origin
	if ship != null and pawn.platform == ship:
		var stand_local := ship.global_transform.affine_inverse() * stand_world
		return _navigate_ship_local(stand_local, 0.85 * hs)
	return _move_world_towards(stand_world, 0.9)


## Ship-local deck-aware waypoint navigator so crew climb quarterdeck & hold stairs cleanly.
func _navigate_ship_local(goal_local: Vector3, arrive_dist: float = 0.65) -> bool:
	if ship == null:
		return false
	var hs := _ship_scale()
	var cur := pawn.platform_local_position()
	var same_level := absf(cur.y - goal_local.y) < 0.65 * hs
	if same_level and cur.distance_to(goal_local) <= arrive_dist:
		pawn.wish_dir = Vector3.ZERO
		pawn.wish_sprint = false
		_route.clear()
		return true

	if _route.is_empty() or _route[_route.size() - 1].distance_to(goal_local) > 0.75 * hs:
		_route = _plan_ship_route(cur, goal_local)
		_route_is_local = true

	while not _route.is_empty():
		var wp: Vector3 = _route[0]
		var d := wp - cur
		var flat := Vector2(d.x, d.z).length()
		var thresh := arrive_dist if _route.size() == 1 else (0.55 * hs)
		if flat <= thresh and absf(d.y) < 0.85 * hs:
			_route.remove_at(0)
		else:
			var world_dir := ship.global_basis * Vector3(d.x, 0.0, d.z)
			world_dir.y = 0.0
			if world_dir.length_squared() > 0.0001:
				var wd := world_dir.normalized()
				pawn.wish_dir = wd
				pawn.wish_sprint = current_task == &"patch_hole" or current_task == &"bail" \
					or current_task == &"douse_fire" or flat > 3.0 * hs
				pawn.look_yaw = atan2(-wd.x, -wd.z)
			else:
				pawn.wish_dir = Vector3.ZERO
			return false

	pawn.wish_dir = Vector3.ZERO
	pawn.wish_sprint = false
	return true


func _plan_ship_route(from_l: Vector3, to_l: Vector3) -> Array[Vector3]:
	var hs := _ship_scale()
	var pts: Array[Vector3] = []
	var from_deck := _deck_band(from_l.y / hs)
	var to_deck := _deck_band(to_l.y / hs)
	var from_z_u := from_l.z / hs
	var to_z_u := to_l.z / hs

	if from_deck == to_deck:
		if from_deck == 0 and ((from_z_u > -0.7 and to_z_u < -1.1) or (from_z_u < -1.1 and to_z_u > -0.7)):
			# Walk along the side aisle past the mast pillar at (0, -1.0) in the hold.
			var side_x := (0.82 if from_l.x >= 0.0 else -0.82) * hs
			if from_z_u > to_z_u:
				pts.append(Vector3(side_x, -0.85 * hs, -0.35 * hs))
				pts.append(Vector3(side_x, -0.85 * hs, -1.65 * hs))
			else:
				pts.append(Vector3(side_x, -0.85 * hs, -1.65 * hs))
				pts.append(Vector3(side_x, -0.85 * hs, -0.35 * hs))
		pts.append(to_l)
		return pts

	# Step 1: get to main deck (band 1) first.
	if from_deck == 2:
		pts.append(NAV_QSTAIR_TOP_R * hs)
		pts.append(NAV_QSTAIR_BOT_R * hs)
	elif from_deck == 0:
		if from_z_u < -1.1:
			var sx := (0.82 if from_l.x >= 0.0 else -0.82) * hs
			pts.append(Vector3(sx, -0.85 * hs, -1.65 * hs))
			pts.append(Vector3(sx, -0.85 * hs, -0.35 * hs))
		pts.append(NAV_HOLD_FOOT * hs)
		pts.append(NAV_HOLD_STAIR_MID * hs)
		pts.append(NAV_MAIN_MID * hs)

	# Step 2: move from main deck to target deck.
	if to_deck == 2:
		pts.append(NAV_QSTAIR_BOT_R * hs)
		pts.append(NAV_QSTAIR_TOP_R * hs)
	elif to_deck == 0:
		pts.append(NAV_MAIN_MID * hs)
		pts.append(NAV_HOLD_STAIR_MID * hs)
		pts.append(NAV_HOLD_FOOT * hs)
		if to_z_u < -1.1:
			pts.append(Vector3(0.82 * hs, -0.85 * hs, -0.35 * hs))
			pts.append(Vector3(0.82 * hs, -0.85 * hs, -1.65 * hs))

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

	# Immediate breach, flooding, and deck fire callouts.
	if ship != null and is_instance_valid(ship):
		var breached := ship.open_hole_count() > 0
		if breached and not _was_breached:
			_speak(&"leak", {}, "leak", 12.0)
		_was_breached = breached
		if ship.water_level > 0.35:
			_speak(&"water_high", {}, "water_high", 22.0)
		var on_fire := ship.has_deck_fire()
		if on_fire and not _was_on_fire:
			_speak(&"fire_aboard", {}, "fire_aboard", FIRE_CALLOUT_COOLDOWN)
		_was_on_fire = on_fire

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

	# Colossal Ancient Megalodon sightings within extended range (deduplicated per instance ID).
	var meg_range := lookout_range * 1.25
	for node in get_tree().get_nodes_in_group(&"megalodons"):
		if not (node is Node3D):
			continue
		var meg := node as Node3D
		var dead_v: Variant = meg.get(&"dead")
		if dead_v != null and bool(dead_v):
			continue
		var mid := meg.get_instance_id()
		if _reported_megalodons.has(mid):
			continue
		var mdist := origin.distance_to(meg.global_position)
		if mdist <= meg_range:
			_reported_megalodons[mid] = true
			var mnm := "Ancient Megalodon"
			for prop_nm: StringName in [&"display_name", &"megalodon_name", &"boss_name"]:
				var raw_mnm: Variant = meg.get(prop_nm)
				if raw_mnm != null and String(raw_mnm).strip_edges() != "":
					mnm = String(raw_mnm).strip_edges()
					break
			if mnm == "Ancient Megalodon" and meg.has_meta(&"display_name"):
				var meta_mnm := String(meg.get_meta(&"display_name")).strip_edges()
				if meta_mnm != "":
					mnm = meta_mnm
			var mbrg := CrewDialogue.ship_relative_bearing(ship, meg.global_position)
			_speak(&"megalodon_sighted", {"target": mnm, "bearing": mbrg}, "meg:" + str(mid), 45.0)
			return

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

	# Half-submerged Sunken Shipwreck sightings within extended gull-marker range (deduplicated per wreck).
	var wreck_range := lookout_range * 1.15
	for node in get_tree().get_nodes_in_group(&"sunken_shipwrecks"):
		if not (node is Node3D):
			continue
		var wreck := node as Node3D
		if wreck.has_method(&"is_cleared") and bool(wreck.call(&"is_cleared")):
			continue
		var wid := wreck.get_instance_id()
		if _reported_wrecks.has(wid):
			continue
		var wdist := origin.distance_to(wreck.global_position)
		if wdist <= wreck_range:
			_reported_wrecks[wid] = true
			var raw_wnm: Variant = wreck.get(&"wreck_name")
			var wnm: String = String(raw_wnm).strip_edges() if raw_wnm != null else "Sunken Shipwreck"
			if wnm == "":
				wnm = "Sunken Shipwreck"
			var wbrg := CrewDialogue.ship_relative_bearing(ship, wreck.global_position)
			_speak(&"shipwreck_sighted", {"target": wnm, "bearing": wbrg}, "wreck:" + str(wid), 45.0)
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


## Acknowledge a target sighted through the Captain's spyglass with a persona response.
func acknowledge_captain_sighting(target_label: String, bearing: String, target_pos: Vector3) -> bool:
	if pawn == null or not is_instance_valid(pawn) or pawn.dead or not is_inside_tree():
		return false
	if _callout_cooldowns.has("sighting_ack"):
		return false
	# Briefly turn toward the sighted horizon target if not pinned to the helm.
	var on_helm := pawn.station != null and StringName(pawn.station.get(&"kind")) == &"helm"
	if not on_helm:
		var look_d := target_pos - pawn.global_position
		look_d.y = 0.0
		if look_d.length_squared() > 0.01:
			pawn.look_yaw = atan2(-look_d.x, -look_d.z)
	var safe_bearing := bearing if bearing != "" else "ahead"
	_speak(&"sighting_ack", {"target": target_label, "bearing": safe_bearing}, "sighting_ack", SIGHTING_ACK_COOLDOWN)
	_play_anim(&"shout", 0.6)
	return true


## Cheer back when the Captain raises a grog tankard toast nearby.
func acknowledge_captain_toast() -> bool:
	if pawn == null or not is_instance_valid(pawn) or pawn.dead or not is_inside_tree():
		return false
	if _callout_cooldowns.has("toast_ack"):
		return false
	var on_helm := pawn.station != null and StringName(pawn.station.get(&"kind")) == &"helm"
	if not on_helm and captain != null and is_instance_valid(captain):
		var look_d := captain.global_position - pawn.global_position
		look_d.y = 0.0
		if look_d.length_squared() > 0.01:
			pawn.look_yaw = atan2(-look_d.x, -look_d.z)
	_speak(&"toast_ack", {}, "toast_ack", TOAST_ACK_COOLDOWN)
	return true


## Lighthearted persona reaction when splashed by the Captain's water bucket.
func react_to_water_splash() -> bool:
	if pawn == null or not is_instance_valid(pawn) or pawn.dead or not is_inside_tree():
		return false
	if _callout_cooldowns.has("splashed"):
		return false
	var on_helm := pawn.station != null and StringName(pawn.station.get(&"kind")) == &"helm"
	if not on_helm and captain != null and is_instance_valid(captain):
		var look_d := captain.global_position - pawn.global_position
		look_d.y = 0.0
		if look_d.length_squared() > 0.01:
			pawn.look_yaw = atan2(-look_d.x, -look_d.z)
	_speak(&"splashed", {}, "splashed", SPLASHED_COOLDOWN)
	return true


## Cheer when the Captain snags treasure or salvage with the bow harpoon.
func celebrate_harpoon_haul(item_label: String = "treasure") -> bool:
	if pawn == null or not is_instance_valid(pawn) or pawn.dead or not is_inside_tree():
		return false
	if _callout_cooldowns.has("harpoon_haul"):
		return false
	var clean_label := item_label.strip_edges()
	if clean_label == "":
		clean_label = "treasure"
	_speak(&"harpoon_haul", {"target": clean_label}, "harpoon_haul", HARPOON_HAUL_COOLDOWN)
	return true


## Tactical callout when Chainshot shreds a rival ship's sails.
func callout_chainshot_hit() -> bool:
	if pawn == null or not is_instance_valid(pawn) or pawn.dead or not is_inside_tree():
		return false
	if _callout_cooldowns.has("chainshot_hit"):
		return false
	_speak(&"chainshot_hit", {}, "chainshot_hit", CHAINSHOT_HIT_COOLDOWN)
	return true


## Persona remark when deck lanterns are doused (running dark) or relit.
func comment_running_dark(lit: bool) -> bool:
	if pawn == null or not is_instance_valid(pawn) or pawn.dead or not is_inside_tree():
		return false
	var category: StringName = &"lanterns_lit" if lit else &"running_dark"
	var cd_key := String(category)
	if _callout_cooldowns.has(cd_key):
		return false
	_speak(category, {}, cd_key, RUNNING_DARK_COOLDOWN)
	return true


## Persona callout when the stern rowboat is launched onto the sea.
func notify_rowboat_launched() -> bool:
	if pawn == null or not is_instance_valid(pawn) or pawn.dead or not is_inside_tree():
		return false
	if _callout_cooldowns.has("rowboat_launched"):
		return false
	_speak(&"rowboat_launched", {}, "rowboat_launched", ROWBOAT_COOLDOWN)
	return true


## Persona callout when the stern rowboat is hoisted back onto the davits.
func notify_rowboat_docked() -> bool:
	if pawn == null or not is_instance_valid(pawn) or pawn.dead or not is_inside_tree():
		return false
	if _callout_cooldowns.has("rowboat_docked"):
		return false
	_speak(&"rowboat_docked", {}, "rowboat_docked", ROWBOAT_COOLDOWN)
	return true


## Persona horizon callout when a colossal WorldEventCloud sky beacon looms overhead.
func notify_event_cloud_sighted(cloud_label: String, bearing: String) -> bool:
	if pawn == null or not is_instance_valid(pawn) or pawn.dead or not is_inside_tree():
		return false
	if _callout_cooldowns.has("event_cloud"):
		return false
	var clean_cloud := cloud_label.strip_edges()
	if clean_cloud == "":
		clean_cloud = "Fort Skull Cloud"
	var clean_bearing := bearing.strip_edges()
	if clean_bearing == "":
		clean_bearing = "ahead"
	_speak(&"event_cloud_sighted", {"cloud": clean_cloud, "bearing": clean_bearing}, "event_cloud", EVENT_CLOUD_COOLDOWN)
	return true


## Persona horizon callout when a half-submerged Sunken Shipwreck dive encounter is spotted.
func notify_shipwreck_sighted(wreck_label: String, bearing: String) -> bool:
	if pawn == null or not is_instance_valid(pawn) or pawn.dead or not is_inside_tree():
		return false
	if _callout_cooldowns.has("shipwreck_sighted"):
		return false
	var clean_target := wreck_label.strip_edges()
	if clean_target == "":
		clean_target = "Sunken Shipwreck"
	var clean_bearing := bearing.strip_edges()
	if clean_bearing == "":
		clean_bearing = "ahead"
	_speak(&"shipwreck_sighted", {"target": clean_target, "bearing": clean_bearing},
		"shipwreck_sighted", SHIPWRECK_COOLDOWN)
	return true


## Warm persona welcome when the Captain returns aboard via a Sea Mermaid beacon.
func notify_mermaid_return() -> bool:
	if pawn == null or not is_instance_valid(pawn) or pawn.dead or not is_inside_tree():
		return false
	if _callout_cooldowns.has("mermaid_return"):
		return false
	_speak(&"mermaid_return", {}, "mermaid_return", MERMAID_RETURN_COOLDOWN)
	return true


## Urgent persona callout when a colossal Ancient Megalodon circles the hull.
func notify_megalodon_sighted(label: String = "Ancient Megalodon", bearing: String = "ahead") -> bool:
	if pawn == null or not is_instance_valid(pawn) or pawn.dead or not is_inside_tree():
		return false
	if _callout_cooldowns.has("megalodon_sighted"):
		return false
	var clean_target := label.strip_edges()
	if clean_target == "":
		clean_target = "Ancient Megalodon"
	var clean_bearing := bearing.strip_edges()
	if clean_bearing == "":
		clean_bearing = "ahead"
	_speak(&"megalodon_sighted", {"target": clean_target, "bearing": clean_bearing},
		"megalodon_sighted", MEGALODON_SIGHTED_COOLDOWN)
	return true


func _on_ship_harpoon_loot_snagged(arg0: Variant = null, arg1: Variant = null, _arg2: Variant = null) -> void:
	if not Net.is_host():
		return
	var label := "treasure"
	if arg0 is String and String(arg0).strip_edges() != "":
		label = String(arg0).strip_edges()
	elif arg0 is StringName and String(arg0) != "":
		label = String(arg0)
	elif arg0 is Node and is_instance_valid(arg0):
		var n := arg0 as Node
		var item_nm: Variant = n.get(&"item_name")
		var disp_nm: Variant = n.get(&"display_name")
		if item_nm != null and String(item_nm).strip_edges() != "":
			label = String(item_nm).strip_edges()
		elif disp_nm != null and String(disp_nm).strip_edges() != "":
			label = String(disp_nm).strip_edges()
		elif n.has_meta(&"display_name"):
			var meta_nm := String(n.get_meta(&"display_name")).strip_edges()
			if meta_nm != "":
				label = meta_nm
		elif arg1 is String and String(arg1).strip_edges() != "":
			label = String(arg1).strip_edges()
	elif arg1 is String and String(arg1).strip_edges() != "":
		label = String(arg1).strip_edges()
	if celebrate_harpoon_haul(label):
		for other in _sibling_crew_brains():
			if other.ship == ship:
				other._callout_cooldowns["harpoon_haul"] = HARPOON_HAUL_COOLDOWN


func _on_ship_lanterns_toggled(lit_v: Variant = true, _arg1: Variant = null, _arg2: Variant = null) -> void:
	if not Net.is_host():
		return
	var lit := true
	if lit_v is bool:
		lit = bool(lit_v)
	elif ship != null and is_instance_valid(ship):
		var raw_lit: Variant = ship.get(&"lanterns_lit")
		if raw_lit != null:
			lit = bool(raw_lit)
	if comment_running_dark(lit):
		var cd_key := "lanterns_lit" if lit else "running_dark"
		for other in _sibling_crew_brains():
			if other.ship == ship:
				other._callout_cooldowns[cd_key] = RUNNING_DARK_COOLDOWN


## Cheer when the Captain blasts themselves out of a ship cannon.
func cheer_cannon_self_launch() -> bool:
	if pawn == null or not is_instance_valid(pawn) or pawn.dead or not is_inside_tree():
		return false
	if _callout_cooldowns.has("cannon_self_launch"):
		return false
	_speak(&"cannon_self_launch", {}, "cannon_self_launch", CANNON_SELF_LAUNCH_COOLDOWN)
	return true


func _on_ship_pawn_cannon_launched(_side: Variant = &"", launched_pawn: Variant = null) -> void:
	if not Net.is_host():
		return
	if launched_pawn == pawn:
		return
	if cheer_cannon_self_launch():
		for other in _sibling_crew_brains():
			if other.ship == ship:
				other._callout_cooldowns["cannon_self_launch"] = CANNON_SELF_LAUNCH_COOLDOWN


func _speak(category: StringName, vars: Dictionary = {}, cd_key: String = "", cooldown: float = 8.0) -> void:
	var key := cd_key if cd_key != "" else String(category)
	if _callout_cooldowns.has(key):
		return
	var text := CrewDialogue.format_line(persona_id, category, vars, _rng)
	if text == "" and category == &"battle_cry":
		var cries: Array = BATTLE_CRY_LINES.get(persona_id, BATTLE_CRY_LINES[&"helmsman"])
		if not cries.is_empty():
			text = "%s: %s" % [crew_name(), String(cries[_rng.randi_range(0, cries.size() - 1)])]
	elif text == "" and category == &"shanty_encore":
		var encores: Array = SHANTY_ENCORE_LINES.get(persona_id, SHANTY_ENCORE_LINES[&"helmsman"])
		if not encores.is_empty():
			text = "%s: %s" % [crew_name(), String(encores[_rng.randi_range(0, encores.size() - 1)])]
	elif text == "" and category == &"sighting_ack":
		var tmpl := String(SIGHTING_ACK_TEMPLATES.get(persona_id, SIGHTING_ACK_TEMPLATES[&"lookout"]))
		tmpl = tmpl.replace("{target}", String(vars.get("target", "sighting")))
		tmpl = tmpl.replace("{bearing}", String(vars.get("bearing", "ahead")))
		text = "%s: %s" % [crew_name(), tmpl]
	if text == "":
		return
	_callout_cooldowns[key] = cooldown
	Game.post_notice(text)
	var voice_db := -11.0 if category == &"running_dark" else -6.0
	Audio.play_sfx(&"crew_shout", pawn.global_position, voice_db, 0.08)
	var skip_shout_anim := (category == &"shanty_encore") \
		or (category == &"running_dark") \
		or (category == &"battle_cry" and _combat != null and _combat.state != CombatComponent.State.IDLE)
	if not skip_shout_anim:
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
			var hs := _ship_scale()
			var loc := (ship.global_transform.affine_inverse() * c.global_position) / hs
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
		&"set_sails": return &"sail_length"
		&"trim": return &"sail_angle"
		&"anchor_drop", &"anchor_raise": return &"anchor"
		&"cannons": return &"cannon"
		&"repair": return &"bilge"
		_: return &""


static func _order_label(order: StringName) -> String:
	match order:
		&"helm": return "taking the helm"
		&"set_sails": return "setting the sails"
		&"trim": return "trimming sails for speed"
		&"anchor_drop": return "dropping the anchor"
		&"anchor_raise": return "heaving the anchor"
		&"cannons": return "manning the cannons"
		&"repair": return "patching and bailing"
		&"follow": return "right behind you"
		&"fetch_treasure": return "fetching the haul"
		&"shanty": return "striking up a tune"
		_: return "standing by"
