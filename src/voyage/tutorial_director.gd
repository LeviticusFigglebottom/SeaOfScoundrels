class_name TutorialDirector
extends Node
## Guided 8-stage interactive Maiden Voyage tutorial director.
##
## Observes real player actions across Ship, Pawn, Inventory, MapTableView,
## ShipHarpoon, and Rowboat (or explicit `notify_action()` hooks) and awards
## the Maiden Voyage graduation bonus upon completion before transitioning
## seamlessly into Open-Seas Adventure.
## Host-authoritative (`Net.is_host()`) for all progression and profile rewards.

signal step_changed(step_index: int, step_id: StringName, title: String, hint: String, progress_text: String)
signal step_completed(step_index: int, step_id: StringName)
signal tutorial_completed(bonus_gold: int, bonus_renown: int)
signal tutorial_skipped()
signal sub_tip_posted(message: String)

const GRADUATION_GOLD: int = 500
const GRADUATION_RENOWN: int = 100
const GRADUATION_COMPANY: StringName = &"gilded_compass"
const SAIL_CLEAR_DISTANCE_M: float = 45.0
const SAIL_HELM_DISTANCE_M: float = 35.0
const ISLAND_APPROACH_RADIUS_M: float = 95.0
const UNEARTHED_SUB_TIP: String = "Chest unearthed! Carry it aboard and sell at Port Scoundrel!"

const STAGES: Array[Dictionary] = [
	{
		"id": &"equip_compass",
		"title": "1. Equip Your Brass Compass",
		"hint": "Press [Q/Tab] to open the Tool Radial or [1]-[6] and equip your Compass ([LMB] toggles Chart Pin, [RMB] counts paces).",
	},
	{
		"id": &"check_map_table",
		"title": "2. Check the Map Table Below Deck",
		"hint": "Head below deck to the Chart Table ([F]) to inspect the archipelago and spot Cutlass Cay to the north.",
	},
	{
		"id": &"raise_anchor",
		"title": "3. Heave the Anchor Capstan",
		"hint": "Walk to the Capstan on deck, press [F] and hold [W] or [LMB] until the anchor clicks home!",
	},
	{
		"id": &"drop_and_trim_sails",
		"title": "4. Drop & Trim the Sails",
		"hint": "Use Sail Length ([F], hold [S] to drop canvas) and Sail Angle ([F], [A]/[D] to catch the wind ribbons).",
	},
	{
		"id": &"take_helm_and_sail",
		"title": "5. Take the Helm & Leave Harbour",
		"hint": "Grab the Ship's Wheel ([F], [A]/[D] to steer) and sail 45 m clear of Port Scoundrel toward Cutlass Cay!",
	},
	{
		"id": &"fire_cannon",
		"title": "6. Fire a Broadside Cannon",
		"hint": "Man a deck Cannon ([F], [WASD] aim, [R] cycle Iron/Chainshot/Firebomb/Flare, [LMB] fire!).",
	},
	{
		"id": &"reach_island_or_rowboat",
		"title": "7. Approach Cutlass Cay or Launch the Rowboat",
		"hint": "Sail within 95 m of Cutlass Cay (or drop anchor [F] and launch the stern Rowboat [F] to row ashore!).",
	},
	{
		"id": &"dig_and_sell_treasure",
		"title": "8. Unearth & Sell Your First Chest",
		"hint": "Equip Shovel to dig the marked treasure on Cutlass Cay, sail back to Port Scoundrel, and sell it at the Merchant Stall!",
	},
]

var active: bool = false
var completed: bool = false
var current_step: int = 0
var target_island_pos: Vector3 = Vector3.ZERO
var target_island_name: String = "Cutlass Cay"
## Optional profile override (uses `Game.profile` when null).
var profile: Profile = null
## When false, `Game.post_notice` banners are suppressed (useful in quiet tests).
var post_notices: bool = true
## When false, `Audio.play_stinger` is suppressed.
var play_audio: bool = true
## Most recent sub-tip message posted during the tutorial.
var last_sub_tip: String = ""

var _ship: Ship = null
var _pawn: Pawn = null
var _inventory: Inventory = null
var _map_table: MapTableView = null
var _rowboat: Rowboat = null
var _bound_harpoons: Array[ShipHarpoon] = []

var _start_pos: Vector3 = Vector3.ZERO
var _has_start_pos: bool = false
var _has_target_island: bool = false
var _baseline_cannonballs: int = Ship.MAX_CANNONBALLS
var _manned_helm: bool = false
var _cannon_or_harpoon_fired: bool = false
var _rowboat_launched_flag: bool = false
var _treasure_unearthed: bool = false
var _advancing: bool = false


func _exit_tree() -> void:
	_disconnect_bound_signals()
	_clear_refs()
	active = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_disconnect_bound_signals()
		_clear_refs()


func _physics_process(delta: float) -> void:
	if active:
		step_tutorial(delta)


## Bind live player ship, pawn, inventory, and optional chart table & rowboat.
func bind(
	p_ship: Ship,
	p_pawn: Pawn,
	p_inventory: Inventory,
	p_map_table: MapTableView = null,
	p_rowboat: Rowboat = null
) -> void:
	_disconnect_bound_signals()
	_ship = p_ship
	_pawn = p_pawn
	_inventory = p_inventory
	_map_table = p_map_table
	_rowboat = p_rowboat
	_connect_bound_signals()
	_capture_ship_baselines(not _has_start_pos)


## Begin the 8-stage Maiden Voyage tutorial from stage 0 (host-only).
func start_tutorial(
	p_target_island_pos: Vector3 = Vector3.ZERO,
	p_target_name: String = "Cutlass Cay"
) -> void:
	if not Net.is_host():
		return
	target_island_pos = p_target_island_pos
	target_island_name = _sanitize_ascii(p_target_name, "Cutlass Cay")
	active = true
	completed = false
	current_step = 0
	_manned_helm = false
	_cannon_or_harpoon_fired = false
	_rowboat_launched_flag = false
	_treasure_unearthed = false
	last_sub_tip = ""
	_capture_ship_baselines(true)
	_has_target_island = (target_island_pos != Vector3.ZERO) \
		or (_has_start_pos and _xz_distance(_start_pos, target_island_pos) > ISLAND_APPROACH_RADIUS_M)
	_bind_harpoons()
	_emit_current_step()


## Halt tutorial tracking cleanly without awarding graduation rewards.
func stop_tutorial() -> void:
	active = false


## Poll live gameplay state for the active tutorial step (host-only).
## Called automatically each physics tick, or directly in headless tests.
func step_tutorial(_delta: float) -> void:
	if not active or completed or not Net.is_host():
		return
	if current_step < 0 or current_step >= STAGES.size():
		return
	_bind_harpoons()
	_update_live_trackers()
	var step_id := _current_step_id()
	if _is_step_satisfied(step_id):
		_complete_current_step()


## Explicitly mark a stage action as completed if it matches the active stage (host-only).
func notify_action(action_id: StringName) -> void:
	if not active or completed or not Net.is_host():
		return
	if action_id == _current_step_id():
		_complete_current_step()


## Notify that the player dug up a buried chest; posts an encouraging haul-home sub-tip.
func notify_treasure_unearthed() -> void:
	if not active or completed or not Net.is_host():
		return
	_treasure_unearthed = true
	last_sub_tip = UNEARTHED_SUB_TIP
	_post_notice(UNEARTHED_SUB_TIP)
	sub_tip_posted.emit(UNEARTHED_SUB_TIP)


## Notify that the player sold treasure at a merchant stall; completes Stage 8 (host-only).
func notify_treasure_sold() -> void:
	if not active or completed or not Net.is_host():
		return
	if _current_step_id() == &"dig_and_sell_treasure":
		_complete_current_step()


## Advance past the active tutorial step immediately (host-only).
func skip_current_step() -> void:
	if not active or completed or not Net.is_host():
		return
	_complete_current_step()


## Skip the remaining Maiden Voyage steps without graduation bonus (host-only).
func skip_all() -> void:
	if not active or completed or not Net.is_host():
		return
	active = false
	_post_notice("Maiden Voyage skipped - the Open Seas await, Captain!")
	tutorial_skipped.emit()


## Return the active stage dictionary with formatted title, hint, and progress_text.
## Returns an empty Dictionary when inactive or completed.
func get_current_step_dict() -> Dictionary:
	if not active or completed or current_step < 0 or current_step >= STAGES.size():
		return {}
	return _format_stage(current_step)


## Return human-readable strict-ASCII progress label (e.g. "Step 3 / 8").
func get_progress_text() -> String:
	if completed:
		return "Complete (%d / %d)" % [STAGES.size(), STAGES.size()]
	var shown := clampi(current_step + 1, 1, STAGES.size())
	return "Step %d / %d" % [shown, STAGES.size()]


## Total number of tutorial stages.
func get_stage_count() -> int:
	return STAGES.size()


## Return a full state snapshot for HUD or save inspection.
func get_state() -> Dictionary:
	return {
		"active": active,
		"completed": completed,
		"current_step": current_step,
		"total_steps": STAGES.size(),
		"progress_text": get_progress_text(),
		"target_island_name": target_island_name,
		"target_island_pos": target_island_pos,
		"treasure_unearthed": _treasure_unearthed,
		"step": get_current_step_dict(),
	}


# ==============================================================================
# Internal Detection & Progression
# ==============================================================================

func _current_step_id() -> StringName:
	if current_step < 0 or current_step >= STAGES.size():
		return &""
	return StringName(STAGES[current_step]["id"])


func _format_stage(index: int) -> Dictionary:
	var raw: Dictionary = STAGES[index]
	var title := String(raw["title"]).replace("Cutlass Cay", target_island_name)
	var hint := String(raw["hint"]).replace("Cutlass Cay", target_island_name)
	if StringName(raw["id"]) == &"dig_and_sell_treasure" and _treasure_unearthed:
		hint = UNEARTHED_SUB_TIP
	return {
		"index": index,
		"id": StringName(raw["id"]),
		"title": title,
		"hint": hint,
		"progress_text": get_progress_text(),
	}


func _emit_current_step() -> void:
	if current_step < 0 or current_step >= STAGES.size():
		return
	var st := _format_stage(current_step)
	step_changed.emit(
		current_step,
		StringName(st["id"]),
		String(st["title"]),
		String(st["hint"]),
		String(st["progress_text"])
	)


func _update_live_trackers() -> void:
	if _ship != null and is_instance_valid(_ship) and not _has_start_pos:
		_start_pos = _ship.global_position
		_has_start_pos = true
	if _pawn != null and is_instance_valid(_pawn) and _pawn.station != null and is_instance_valid(_pawn.station):
		if _station_kind(_pawn.station) == &"helm":
			_manned_helm = true
	elif _ship != null and is_instance_valid(_ship):
		var helm_st := _ship.get_station(&"helm")
		if helm_st != null and _pawn != null and helm_st.occupant == _pawn:
			_manned_helm = true


func _is_step_satisfied(step_id: StringName) -> bool:
	match step_id:
		&"equip_compass":
			return _is_compass_equipped()
		&"check_map_table":
			return _is_map_table_checked()
		&"raise_anchor":
			return _is_anchor_raised()
		&"drop_and_trim_sails":
			return _is_sail_dropped_and_trimmed()
		&"take_helm_and_sail":
			return _has_left_harbour()
		&"fire_cannon":
			return _has_fired_cannon_or_harpoon()
		&"reach_island_or_rowboat":
			return _has_approached_island_or_launched_rowboat()
		&"dig_and_sell_treasure":
			return false
	return false


func _is_compass_equipped() -> bool:
	if _inventory == null or not is_instance_valid(_inventory):
		return false
	if _inventory.active_item == &"compass":
		return true
	var fallback: Variant = _inventory.get(&"equipped_id")
	return fallback != null and StringName(String(fallback)) == &"compass"


func _is_map_table_checked() -> bool:
	if _pawn != null and is_instance_valid(_pawn) and _pawn.station != null and is_instance_valid(_pawn.station):
		if _station_kind(_pawn.station) == &"map_table":
			return true
	if _ship != null and is_instance_valid(_ship):
		var map_st := _ship.get_station(&"map_table")
		if map_st != null and map_st.is_occupied():
			if _pawn == null or map_st.occupant == _pawn:
				return true
	if _map_table != null and is_instance_valid(_map_table):
		if _map_table.has_active_pin():
			return true
		if _map_table.has_method(&"has_chart_pin") and bool(_map_table.call(&"has_chart_pin")):
			return true
	return false


func _is_anchor_raised() -> bool:
	if _ship == null or not is_instance_valid(_ship):
		return false
	return (not _ship.anchor_down) and _ship.anchor_progress <= 0.05


func _is_sail_dropped_and_trimmed() -> bool:
	if _ship == null or not is_instance_valid(_ship):
		return false
	if _ship.sail_set < 0.35:
		return false
	if _ship.sail_set >= 0.45:
		return true
	return _ship.wind_catch() > 0.55


func _has_left_harbour() -> bool:
	if _ship == null or not is_instance_valid(_ship):
		return false
	if not _has_start_pos:
		_start_pos = _ship.global_position
		_has_start_pos = true
		return false
	var dist_xz := _xz_distance(_ship.global_position, _start_pos)
	if _manned_helm and dist_xz >= SAIL_HELM_DISTANCE_M:
		return true
	var speed_xz := Vector2(_ship.linear_velocity.x, _ship.linear_velocity.z).length()
	var underway := (not _ship.anchor_down) or _ship.sail_set >= 0.1 or speed_xz > 0.3
	return underway and dist_xz >= SAIL_CLEAR_DISTANCE_M


func _has_fired_cannon_or_harpoon() -> bool:
	if _cannon_or_harpoon_fired:
		return true
	if _ship != null and is_instance_valid(_ship):
		if _ship.cannonballs_remaining < _baseline_cannonballs:
			return true
	return false


func _has_approached_island_or_launched_rowboat() -> bool:
	if _rowboat_launched_flag:
		return true
	if _rowboat != null and is_instance_valid(_rowboat) and not _rowboat.is_docked():
		return true
	if _pawn != null and is_instance_valid(_pawn):
		if _pawn.platform == null and not _pawn.dead and _pawn.mode != Pawn.Mode.SWIM:
			return true
	if _has_target_island and _ship != null and is_instance_valid(_ship):
		if _xz_distance(_ship.global_position, target_island_pos) <= ISLAND_APPROACH_RADIUS_M:
			return true
	return false


func _complete_current_step() -> void:
	if _advancing or not active or completed or not Net.is_host():
		return
	if current_step < 0 or current_step >= STAGES.size():
		return
	_advancing = true
	var done_idx := current_step
	var done_id := _current_step_id()
	step_completed.emit(done_idx, done_id)
	current_step = done_idx + 1
	if current_step >= STAGES.size():
		_graduate()
	else:
		_on_enter_step(current_step)
		_emit_current_step()
	_advancing = false


func _on_enter_step(step_index: int) -> void:
	var next_id := StringName(STAGES[step_index]["id"])
	if next_id == &"fire_cannon":
		_cannon_or_harpoon_fired = false
		if _ship != null and is_instance_valid(_ship):
			_baseline_cannonballs = _ship.cannonballs_remaining
		_bind_harpoons()
	elif next_id == &"take_helm_and_sail":
		if not _has_start_pos and _ship != null and is_instance_valid(_ship):
			_start_pos = _ship.global_position
			_has_start_pos = true
	elif next_id == &"dig_and_sell_treasure" and _treasure_unearthed:
		last_sub_tip = UNEARTHED_SUB_TIP


func _graduate() -> void:
	active = false
	completed = true
	var prof := _get_profile()
	if prof != null:
		prof.add_gold(GRADUATION_GOLD)
		prof.bump_stat("gold_earned", GRADUATION_GOLD)
		prof.add_renown(String(GRADUATION_COMPANY), GRADUATION_RENOWN)
		prof.changed.emit()
	if play_audio and Audio != null:
		Audio.play_stinger(&"victory")
	_post_notice(
		"Maiden Voyage Complete! +%d Gold & +%d Gilded Compass Renown - the Open Seas are yours!" % [
			GRADUATION_GOLD, GRADUATION_RENOWN,
		]
	)
	tutorial_completed.emit(GRADUATION_GOLD, GRADUATION_RENOWN)


# ==============================================================================
# Signal Wiring & Teardown
# ==============================================================================

func _connect_bound_signals() -> void:
	if _inventory != null and is_instance_valid(_inventory):
		if not _inventory.item_equipped.is_connected(_on_item_equipped):
			_inventory.item_equipped.connect(_on_item_equipped)
	if _pawn != null and is_instance_valid(_pawn):
		if not _pawn.station_changed.is_connected(_on_pawn_station_changed):
			_pawn.station_changed.connect(_on_pawn_station_changed)
	if _map_table != null and is_instance_valid(_map_table):
		if not _map_table.marker_placed.is_connected(_on_map_marker_placed):
			_map_table.marker_placed.connect(_on_map_marker_placed)
	if _ship != null and is_instance_valid(_ship):
		if not _ship.cannon_fired.is_connected(_on_ship_cannon_fired):
			_ship.cannon_fired.connect(_on_ship_cannon_fired)
		_bind_harpoons()
	if _rowboat != null and is_instance_valid(_rowboat):
		if not _rowboat.launched.is_connected(_on_rowboat_launched):
			_rowboat.launched.connect(_on_rowboat_launched)


func _bind_harpoons() -> void:
	if _ship == null or not is_instance_valid(_ship):
		return
	for side: StringName in [&"port", &"starboard"]:
		var hp := _ship.get_harpoon(side)
		if hp != null and is_instance_valid(hp):
			if not hp.fired.is_connected(_on_harpoon_fired):
				hp.fired.connect(_on_harpoon_fired)
			if not _bound_harpoons.has(hp):
				_bound_harpoons.append(hp)


func _disconnect_bound_signals() -> void:
	if _inventory != null and is_instance_valid(_inventory):
		if _inventory.item_equipped.is_connected(_on_item_equipped):
			_inventory.item_equipped.disconnect(_on_item_equipped)
	if _pawn != null and is_instance_valid(_pawn):
		if _pawn.station_changed.is_connected(_on_pawn_station_changed):
			_pawn.station_changed.disconnect(_on_pawn_station_changed)
	if _map_table != null and is_instance_valid(_map_table):
		if _map_table.marker_placed.is_connected(_on_map_marker_placed):
			_map_table.marker_placed.disconnect(_on_map_marker_placed)
	if _ship != null and is_instance_valid(_ship):
		if _ship.cannon_fired.is_connected(_on_ship_cannon_fired):
			_ship.cannon_fired.disconnect(_on_ship_cannon_fired)
	for hp in _bound_harpoons:
		if hp != null and is_instance_valid(hp) and hp.fired.is_connected(_on_harpoon_fired):
			hp.fired.disconnect(_on_harpoon_fired)
	_bound_harpoons.clear()
	if _rowboat != null and is_instance_valid(_rowboat):
		if _rowboat.launched.is_connected(_on_rowboat_launched):
			_rowboat.launched.disconnect(_on_rowboat_launched)


func _clear_refs() -> void:
	_ship = null
	_pawn = null
	_inventory = null
	_map_table = null
	_rowboat = null
	_bound_harpoons.clear()
	profile = null


func _capture_ship_baselines(reset_start_pos: bool) -> void:
	if _ship == null or not is_instance_valid(_ship):
		return
	if reset_start_pos:
		_start_pos = _ship.global_position
		_has_start_pos = true
	_baseline_cannonballs = _ship.cannonballs_remaining


func _on_item_equipped(item_id: StringName) -> void:
	if not active or completed or not Net.is_host():
		return
	if item_id == &"compass" and _current_step_id() == &"equip_compass":
		_complete_current_step()


func _on_pawn_station_changed(st: Node3D) -> void:
	if not active or completed or not Net.is_host():
		return
	if st == null or not is_instance_valid(st):
		return
	var kind := _station_kind(st)
	if kind == &"helm":
		_manned_helm = true
	elif kind == &"map_table" and _current_step_id() == &"check_map_table":
		_complete_current_step()


func _on_map_marker_placed(_world_pos: Vector3) -> void:
	if not active or completed or not Net.is_host():
		return
	if _current_step_id() == &"check_map_table":
		_complete_current_step()


func _on_ship_cannon_fired(_side: StringName, _cannonball: Node) -> void:
	if not active or completed or not Net.is_host():
		return
	if _current_step_id() == &"fire_cannon":
		_cannon_or_harpoon_fired = true
		_complete_current_step()


func _on_harpoon_fired(_result: Dictionary) -> void:
	if not active or completed or not Net.is_host():
		return
	if _current_step_id() == &"fire_cannon":
		_cannon_or_harpoon_fired = true
		_complete_current_step()


func _on_rowboat_launched(_by_pawn: Node) -> void:
	if not active or completed or not Net.is_host():
		return
	if _current_step_id() == &"reach_island_or_rowboat":
		_rowboat_launched_flag = true
		_complete_current_step()


# ==============================================================================
# Helpers
# ==============================================================================

func _get_profile() -> Profile:
	if profile != null:
		return profile
	if Game != null:
		return Game.profile
	return null


func _post_notice(text: String) -> void:
	if post_notices and Game != null and text != "":
		Game.post_notice(text)


static func _station_kind(st: Node3D) -> StringName:
	if st is Station:
		return (st as Station).kind
	var k: Variant = st.get(&"kind")
	return StringName(String(k)) if k != null else &""


static func _xz_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _sanitize_ascii(raw: String, fallback: String) -> String:
	var out := ""
	for i in raw.length():
		var code := raw.unicode_at(i)
		if code >= 32 and code <= 126:
			out += char(code)
	out = out.strip_edges()
	return out if not out.is_empty() else fallback
