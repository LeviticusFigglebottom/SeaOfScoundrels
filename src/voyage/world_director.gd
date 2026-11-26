class_name WorldDirector
extends Node
## Host-authoritative living-sea pacing director.
##
## Tracks sailing time, cargo risk aboard the player ship, swimmer exposure,
## and active world events. Produces fair, readable horizon sightings with
## proportional threat (rivals hunt rich hauls, flotsam keeps calm crossings
## lively, storm cells drift across sea lanes, sharks stalk deep swimmers)
## and converts ship sinkings into marked 60%-salvage wrecks rather than wipes.

signal sighting_warning(message: String, world_pos: Vector3, event_kind: StringName, bearing: String, distance: float)
signal spawn_rival_ship(spawn_pos: Vector3, archetype: StringName, target_ship: Node)
signal spawn_shark_pack(center: Vector3, count: int)
signal spawn_flotsam_barrels(pos: Vector3, count: int)
signal spawn_ghost_ship(spawn_pos: Vector3)
signal spawn_storm_cell(center: Vector3, radius: float, velocity: Vector3)
signal spawn_leviathan(center: Vector3, target_ship: Node)
signal spawn_fort_siege(fort_pos: Vector3, bearing: String)
signal spawn_castaway(pos: Vector3)
signal spawn_shipwreck(pos: Vector3, seed_val: int)
signal wreck_recorded(wreck: Dictionary)
signal wreck_salvaged(wreck_id: String, recovered_items: Array)
signal event_cloud_spawned(kind: StringName, world_pos: Vector3, cloud_node: Node3D)
signal event_cloud_cleared(kind: StringName)

## Minimum breather (seconds) between consecutive major world events.
const MIN_EVENT_GAP := 45.0
## Maximum quiet sailing stretch (seconds) before forcing a small sea sighting.
const MAX_DROUGHT_SECONDS := 150.0
## Fair horizon warning band for major threats (metres).
const SIGHTING_MIN_RANGE := 280.0
const SIGHTING_MAX_RANGE := 450.0
## Distance band for small flotsam sightings ahead of the bow (metres).
const FLOTSAM_MIN_RANGE := 120.0
const FLOTSAM_MAX_RANGE := 210.0
## Distance band for half-submerged sunken shipwreck dive sightings (metres).
const SHIPWRECK_MIN_RANGE := 180.0
const SHIPWRECK_MAX_RANGE := 320.0
## Seconds a pawn may swim in deep open water before attracting a shark pack.
const SHARK_SWIM_THRESHOLD := 12.0
## Cooldown (seconds) between shark pack spawns.
const SHARK_COOLDOWN := 90.0
## Target fraction of cargo gold value preserved at a marked wreck on sinking.
const WRECK_SALVAGE_RATIO := 0.60
## Radius around an outpost dock considered safe harbour from hostile spawns.
const SAFE_HARBOR_RADIUS := 220.0

const COMPASS_POINTS: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const CLOUD_EVENT_KINDS: Array[StringName] = [&"fort_siege", &"ghost_ship", &"leviathan"]

## Seconds elapsed since any sighting or world event occurred.
var time_since_event: float = 0.0
## Seconds elapsed since the last major world event (rival, ghost, storm).
var time_since_major_event: float = 0.0
## Seconds elapsed since the last flotsam barrel cluster.
var time_since_flotsam: float = 0.0
## Seconds elapsed since the last half-submerged sunken shipwreck dive encounter.
var time_since_shipwreck: float = 0.0
## Total gold value of treasure currently aboard the player ship.
var cargo_value_aboard: int = 0
## Last known world position of the player ship.
var player_ship_pos: Vector3 = Vector3.ZERO
## Last known horizontal velocity of the player ship.
var player_ship_velocity: Vector3 = Vector3.ZERO
## Cumulative metres sailed during this session.
var sailing_distance: float = 0.0
## Most recent outpost visited (used to restore ship after sinking).
var last_outpost_id: StringName = &"port_scoundrel"
## World position of the most recent outpost dock.
var last_outpost_pos: Vector3 = Vector3.ZERO
## Currently active timed world events managed by the director.
var active_events: Array[Dictionary] = []
## Marked shipwrecks available for cargo salvage recovery.
var salvage_wrecks: Array[Dictionary] = []
## Accumulated deep-water swimming exposure (seconds).
var deep_swim_seconds: float = 0.0
## Lookout range multiplier (from Economy crew traits, e.g. Keen Lookout = 1.4).
var lookout_scale: float = 1.0
## Voyages completed (unlocks rarer spectral threats on later runs).
var voyage_count: int = 0
## Active Trading Company Emissary Grade (0 = inactive, 1..5 = Grade I..V).
var emissary_grade: int = 0
## Optional live ship tracked automatically in `_physics_process`.
var player_ship: Node3D = null
## Master toggle for automatic stepping.
var enabled: bool = true
## Whether storm cell events invoke `Weather.set_storm_cell`.
var weather_integration: bool = true
## Whether sighting warnings also call `Game.post_notice`.
var post_notices: bool = true

var _rng := RandomNumberGenerator.new()
var _shipwreck_rng := RandomNumberGenerator.new()
var _event_serial: int = 0
var _wreck_serial: int = 0
var _next_major_delay: float = 130.0
var _next_flotsam_delay: float = 70.0
var _next_shipwreck_delay: float = 215.0
var _shark_cooldown: float = 0.0
var _has_prev_pos: bool = false
var _storm_active_id: String = ""
var _event_clouds: Dictionary = {}  # StringName kind -> WorldEventCloud


func _init(seed_value: int = 0) -> void:
	if seed_value != 0:
		set_seed(seed_value)
	else:
		_rng.randomize()
		_shipwreck_rng.randomize()
		_next_shipwreck_delay = _shipwreck_rng.randf_range(190.0, 260.0)
	_roll_next_delays()


func _exit_tree() -> void:
	for raw_cloud in _event_clouds.values():
		var cloud := raw_cloud as WorldEventCloud
		if cloud != null and is_instance_valid(cloud) and not cloud.is_queued_for_deletion():
			if cloud.is_in_group(WorldEventCloud.GROUP):
				cloud.remove_from_group(WorldEventCloud.GROUP)
			cloud.queue_free()
	_event_clouds.clear()


func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value
	_shipwreck_rng.seed = seed_value ^ 0x5419EC
	_event_serial = 0
	_wreck_serial = 0
	time_since_shipwreck = 0.0
	_next_shipwreck_delay = _shipwreck_rng.randf_range(190.0, 260.0)
	_roll_next_delays()


func _physics_process(delta: float) -> void:
	if not enabled or not Net.is_host() or player_ship == null or not is_instance_valid(player_ship):
		return
	var pos := player_ship.global_position
	var vel := Vector3.ZERO
	var v_prop: Variant = player_ship.get("linear_velocity")
	if v_prop is Vector3:
		vel = v_prop
	var fwd := -player_ship.global_transform.basis.z
	step(delta, {
		"ship_pos": pos,
		"ship_velocity": vel,
		"ship_forward": fwd,
		"ship_node": player_ship,
		"cargo_value": cargo_value_aboard,
	})


## Pure-simulation director step (host-only). Safe to call in fast headless loops
## to simulate hours of sailing in milliseconds. Returns events spawned this step.
func step(delta: float, context: Dictionary = {}) -> Array[Dictionary]:
	var spawned: Array[Dictionary] = []
	if not enabled or not Net.is_host() or delta <= 0.0:
		return spawned

	_update_context(delta, context)
	_age_active_events(delta)
	if _shark_cooldown > 0.0:
		_shark_cooldown = maxf(0.0, _shark_cooldown - delta)

	var in_harbor := false
	if context.has("in_safe_harbor"):
		in_harbor = bool(context["in_safe_harbor"])
	elif context.has("outpost_positions"):
		in_harbor = is_in_safe_harbor(player_ship_pos, context["outpost_positions"])
	var ship_node: Node = context.get("ship_node", player_ship)
	var heading_dir := _resolve_heading(context)

	# 1. Shark pack threat for deep open-water swimmers or wreck divers.
	var swimming_deep := bool(context.get("pawn_swimming_deep", false))
	var near_wreck := bool(context.get("near_wreck_dive", false))
	if swimming_deep or near_wreck:
		var rate := 1.4 if near_wreck else 1.0
		deep_swim_seconds += delta * rate
		if deep_swim_seconds > SHARK_SWIM_THRESHOLD and _shark_cooldown <= 0.0 and not in_harbor:
			var swimmer_pos: Vector3 = context.get("swimmer_pos", player_ship_pos)
			var shark_evt := _trigger_shark_pack(swimmer_pos)
			spawned.append(shark_evt)
			deep_swim_seconds = 0.0
			_shark_cooldown = SHARK_COOLDOWN
	else:
		deep_swim_seconds = maxf(0.0, deep_swim_seconds - delta * 2.0)

	# Advance pacing clocks while at sea.
	var speed := Vector2(player_ship_velocity.x, player_ship_velocity.z).length()
	var is_sailing := speed > 0.5 or bool(context.get("sailing", false))
	if not in_harbor:
		time_since_event += delta
		time_since_major_event += delta * (1.0 if is_sailing else 0.45)
		time_since_flotsam += delta * (1.0 if is_sailing else 0.35)
		time_since_shipwreck += delta * (1.0 if is_sailing else 0.35)

	if in_harbor:
		return spawned

	# 2. Major world events (proportional to cargo risk, always with fair sighting range).
	var cargo_risk := get_cargo_risk()
	var target_major := lerpf(_next_major_delay, _next_major_delay * 0.62, cargo_risk)
	if time_since_major_event >= maxf(MIN_EVENT_GAP, target_major):
		var major_evt := _trigger_major_event(heading_dir, ship_node, cargo_risk)
		if not major_evt.is_empty():
			spawned.append(major_evt)
			time_since_major_event = 0.0
			time_since_event = 0.0
			_next_major_delay = _rng.randf_range(125.0, 195.0)
			return spawned

	# 3. Frequent flotsam / small sightings so sailing downtime is never empty.
	if time_since_flotsam >= _next_flotsam_delay or time_since_event >= MAX_DROUGHT_SECONDS:
		var flotsam_evt := _trigger_flotsam(heading_dir)
		spawned.append(flotsam_evt)
		time_since_flotsam = 0.0
		time_since_event = 0.0
		_next_flotsam_delay = _rng.randf_range(65.0, 100.0)

	# 3b. Half-submerged Sunken Shipwreck ocean dive encounters on a dedicated cooldown
	#     so calm/rich flotsam & major-event pacing stays 100% deterministic.
	if time_since_shipwreck >= _next_shipwreck_delay and not _has_active_event(&"sunken_shipwreck"):
		var wreck_evt := _trigger_shipwreck(heading_dir)
		spawned.append(wreck_evt)
		time_since_shipwreck = 0.0
		time_since_event = 0.0
		_next_shipwreck_delay = _shipwreck_rng.randf_range(190.0, 260.0)

	return spawned


## Normalized 0..1 risk curve based on gold value aboard plus active Emissary hunter risk.
func get_cargo_risk() -> float:
	var cargo_base := clampf(float(maxi(0, cargo_value_aboard)) / 1200.0, 0.0, 1.0)
	var emissary_bonus: float = EmissaryLedger.HUNTER_RISK_BONUS[clampi(emissary_grade, 0, 5)]
	return clampf(cargo_base + emissary_bonus, 0.0, 1.0)


## Compute compass bearing string ("N", "NE", ...) in world space (-Z North, +X East).
static func compass_bearing(from_pos: Vector3, to_pos: Vector3) -> String:
	var dx := to_pos.x - from_pos.x
	var dz := to_pos.z - from_pos.z
	if dx * dx + dz * dz < 0.0001:
		return "N"
	var angle := fposmod(atan2(dx, -dz), TAU)
	var idx := int(round(angle / (TAU / 8.0))) % 8
	return COMPASS_POINTS[idx]


## Sum gold value across an array of Carryable nodes or treasure dictionaries.
static func sum_cargo_value(cargo_items: Array) -> int:
	var total := 0
	for item in cargo_items:
		if item is Dictionary:
			total += int((item as Dictionary).get("gold_value", 0))
		elif item is Node:
			var info := TreasureCatalog.inspect_carryable(item as Node)
			total += int(info.get("gold_value", 0))
	return total


## Record a marked shipwreck when the player's ship sinks (host-only).
## Preserves ~60% of lost cargo value at the wreck site and computes the ship's
## restore Transform3D at `last_outpost_id` (a setback and errand, never a wipe).
func record_ship_wreck(world_pos: Vector3, cargo_items: Array,
		outpost_positions: Dictionary = {}) -> Dictionary:
	if not Net.is_host():
		return {}

	var normalized: Array[Dictionary] = []
	var total_lost := 0
	for item in cargo_items:
		var info: Dictionary = {}
		if item is Dictionary:
			info = (item as Dictionary).duplicate(true)
			if not info.has("gold_value") and info.has("treasure_id"):
				var base := TreasureCatalog.get_entry(StringName(String(info["treasure_id"])))
				info["gold_value"] = int(base.get("gold_value", 0))
		elif item is Node:
			info = TreasureCatalog.inspect_carryable(item as Node)
		if info.is_empty():
			continue
		total_lost += int(info.get("gold_value", 0))
		normalized.append(info)

	var salvaged_items := _select_salvage_items(normalized, total_lost)
	var salvaged_value := 0
	for s in salvaged_items:
		salvaged_value += int(s.get("gold_value", 0))

	var dock_pos := last_outpost_pos
	if outpost_positions.has(last_outpost_id):
		dock_pos = outpost_positions[last_outpost_id]
	elif outpost_positions.has(String(last_outpost_id)):
		dock_pos = outpost_positions[String(last_outpost_id)]
	# Offset slightly clear of the wharf into navigable water, facing -Z (north).
	var restore_origin := Vector3(dock_pos.x, 0.0, dock_pos.z - 28.0)
	var restore_transform := Transform3D(Basis.IDENTITY, restore_origin)

	_wreck_serial += 1
	var wreck := {
		"id": "wreck_%d" % _wreck_serial,
		"position": Vector3(world_pos.x, 0.0, world_pos.z),
		"total_lost_value": total_lost,
		"salvage_value": salvaged_value,
		"salvage_ratio": float(salvaged_value) / float(total_lost) if total_lost > 0 else 0.0,
		"items": salvaged_items,
		"lost_count": normalized.size(),
		"salvaged_count": salvaged_items.size(),
		"salvaged": false,
		"restore_outpost_id": last_outpost_id,
		"restore_transform": restore_transform,
	}
	salvage_wrecks.append(wreck)
	cargo_value_aboard = 0
	wreck_recorded.emit(wreck)

	var port_label := String(last_outpost_id).replace("_", " ").capitalize()
	if post_notices and Game != null:
		Game.post_notice("Ship lost! Salvage buoy marked (%d gold recoverable) — ship restored at %s." % [
			salvaged_value, port_label])
	return wreck


## Recover the preserved cargo from a marked wreck site (host-only).
func claim_wreck_salvage(wreck_id: String) -> Array:
	if not Net.is_host():
		return []
	for i in salvage_wrecks.size():
		var w: Dictionary = salvage_wrecks[i]
		if String(w.get("id", "")) == wreck_id and not bool(w.get("salvaged", false)):
			w["salvaged"] = true
			var items: Array = (w.get("items", []) as Array).duplicate(true)
			wreck_salvaged.emit(wreck_id, items)
			return items
	return []


func get_active_wrecks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for w in salvage_wrecks:
		if not bool(w.get("salvaged", false)):
			out.append(w)
	return out


func set_last_outpost(outpost_id: StringName, outpost_pos: Vector3) -> void:
	if not Net.is_host():
		return
	last_outpost_id = outpost_id
	last_outpost_pos = Vector3(outpost_pos.x, 0.0, outpost_pos.z)


## Return true if `world_pos` lies within SAFE_HARBOR_RADIUS of any given outpost position.
func is_in_safe_harbor(world_pos: Vector3, outpost_positions: Variant = []) -> bool:
	var flat_pos := Vector2(world_pos.x, world_pos.z)
	if outpost_positions is Array:
		for p in outpost_positions:
			if p is Vector3 and flat_pos.distance_to(Vector2((p as Vector3).x, (p as Vector3).z)) <= SAFE_HARBOR_RADIUS:
				return true
	elif outpost_positions is Dictionary:
		for p in (outpost_positions as Dictionary).values():
			if p is Vector3 and flat_pos.distance_to(Vector2((p as Vector3).x, (p as Vector3).z)) <= SAFE_HARBOR_RADIUS:
				return true
	return false


## Trigger a specific world event directly (e.g. a scripted voyage complication)
## while preserving fair sighting distances, warnings, and pacing cooldowns.
func trigger_event(kind: StringName, context: Dictionary = {}) -> Dictionary:
	if not Net.is_host():
		return {}
	if not context.is_empty():
		_update_context(0.0, context)
	var heading_dir := _resolve_heading(context)
	var ship_node: Node = context.get("ship_node", player_ship)
	var evt: Dictionary = {}
	match kind:
		&"rival_ship", &"drowned_sloop", &"corsair_sloop":
			evt = _trigger_rival_ship(heading_dir, ship_node, kind == &"corsair_sloop")
			time_since_major_event = 0.0
		&"ghost_ship":
			evt = _trigger_ghost_ship(heading_dir)
			time_since_major_event = 0.0
		&"storm_cell":
			evt = _trigger_storm_cell(heading_dir)
			time_since_major_event = 0.0
		&"leviathan":
			evt = _trigger_leviathan(heading_dir, ship_node)
			time_since_major_event = 0.0
		&"fort_siege":
			var fort_pos: Vector3 = context.get("fort_pos", player_ship_pos + _forward_arc_offset(heading_dir, 360.0, 0.8))
			evt = _trigger_fort_siege(fort_pos)
			time_since_major_event = 0.0
		&"castaway":
			evt = _trigger_castaway(heading_dir)
			time_since_flotsam = 0.0
		&"flotsam_barrels":
			evt = _trigger_flotsam(heading_dir)
			time_since_flotsam = 0.0
		&"sunken_shipwreck":
			evt = _trigger_shipwreck(heading_dir)
			time_since_shipwreck = 0.0
		&"shark_pack":
			var swimmer_pos: Vector3 = context.get("swimmer_pos", player_ship_pos)
			evt = _trigger_shark_pack(swimmer_pos)
			_shark_cooldown = SHARK_COOLDOWN
		_:
			push_warning("WorldDirector: unknown event kind '%s'" % kind)
			return {}
	if not evt.is_empty():
		time_since_event = 0.0
	return evt


## Trigger a half-submerged Sunken Shipwreck ocean dive sighting ahead of `heading_dir` (host-only).
func trigger_shipwreck(heading_dir: Vector3 = Vector3.FORWARD) -> Dictionary:
	if not Net.is_host():
		return {}
	var evt := _trigger_shipwreck(heading_dir)
	time_since_shipwreck = 0.0
	time_since_event = 0.0
	return evt


## Immediately force-spawn a Sunken Shipwreck encounter along `heading_dir` (host-only).
func force_spawn_shipwreck(heading_dir: Vector3 = Vector3.FORWARD) -> Dictionary:
	return trigger_shipwreck(heading_dir)


func get_state() -> Dictionary:
	return {
		"cargo_value_aboard": cargo_value_aboard,
		"sailing_distance": sailing_distance,
		"last_outpost_id": last_outpost_id,
		"last_outpost_pos": last_outpost_pos,
		"voyage_count": voyage_count,
		"emissary_grade": emissary_grade,
		"active_events": active_events.duplicate(true),
		"salvage_wrecks": salvage_wrecks.duplicate(true),
	}


## Spawn (or replace) a colossal high-altitude WorldEventCloud beacon for `kind` over `world_pos`.
func spawn_event_cloud(kind: StringName, world_pos: Vector3, instant: bool = false) -> WorldEventCloud:
	if not CLOUD_EVENT_KINDS.has(kind):
		return null
	if _event_clouds.has(kind):
		var old_cloud := _event_clouds[kind] as WorldEventCloud
		_event_clouds.erase(kind)
		if old_cloud != null and is_instance_valid(old_cloud) and not old_cloud.is_queued_for_deletion():
			if old_cloud.is_in_group(WorldEventCloud.GROUP):
				old_cloud.remove_from_group(WorldEventCloud.GROUP)
			if old_cloud.is_inside_tree():
				old_cloud.queue_free()
			else:
				old_cloud.free()

	var sea_pos := Vector3(world_pos.x, 0.0, world_pos.z)
	var cloud := WorldEventCloud.new()
	cloud.name = "WorldEventCloud_%s" % String(kind)
	cloud.configure(kind, sea_pos, instant)
	add_child(cloud)
	if cloud.is_inside_tree():
		cloud.global_position = Vector3(sea_pos.x, WorldEventCloud.CLOUD_ALTITUDE, sea_pos.z)
	_event_clouds[kind] = cloud
	event_cloud_spawned.emit(kind, sea_pos, cloud)
	return cloud


## Clear and fade out (or immediately remove) the active WorldEventCloud for `kind`.
func clear_event_cloud(kind: StringName, instant: bool = false) -> void:
	if not _event_clouds.has(kind):
		return
	var cloud := _event_clouds[kind] as WorldEventCloud
	_event_clouds.erase(kind)
	if cloud != null and is_instance_valid(cloud) and not cloud.is_queued_for_deletion():
		if instant:
			if cloud.is_in_group(WorldEventCloud.GROUP):
				cloud.remove_from_group(WorldEventCloud.GROUP)
			if cloud.is_inside_tree():
				cloud.queue_free()
			else:
				cloud.free()
		else:
			cloud.fade_out_and_free()
	event_cloud_cleared.emit(kind)


## Return all currently active WorldEventCloud sky beacon nodes tracked by this director.
func get_active_event_clouds() -> Array[WorldEventCloud]:
	var out: Array[WorldEventCloud] = []
	for raw_cloud in _event_clouds.values():
		var cloud := raw_cloud as WorldEventCloud
		if cloud != null and is_instance_valid(cloud) \
				and not cloud.is_queued_for_deletion() and not cloud.is_fading_out():
			out.append(cloud)
	return out


# --- Event Trigger Internals --------------------------------------------

func _trigger_major_event(heading_dir: Vector3, ship_node: Node,
		cargo_risk: float) -> Dictionary:
	# Weights scale smoothly with cargo value aboard:
	# Calm (0g):    ~10% rival,  0% ghost, 90% storm cell
	# Rich (1200g): ~65% rival, 17% ghost, 18% storm cell (when unlocked)
	var ghost_eligible := cargo_value_aboard >= 800 or voyage_count >= 2
	var w_rival := lerpf(0.10, 0.68, cargo_risk)
	var w_ghost := lerpf(0.04, 0.18, cargo_risk) if ghost_eligible else 0.0
	var w_storm := lerpf(0.86, 0.18, cargo_risk)
	if _storm_active_id != "":
		w_storm *= 0.15

	var total := w_rival + w_ghost + w_storm
	var roll := _rng.randf() * total
	if roll < w_rival:
		var use_corsair := cargo_value_aboard >= 500 and _rng.randf() < 0.35
		return _trigger_rival_ship(heading_dir, ship_node, use_corsair)
	elif roll < w_rival + w_ghost:
		return _trigger_ghost_ship(heading_dir)
	else:
		return _trigger_storm_cell(heading_dir)


func _trigger_rival_ship(heading_dir: Vector3, ship_node: Node, force_corsair: bool = false) -> Dictionary:
	var dist := _pick_sighting_distance()
	var offset := _forward_arc_offset(heading_dir, dist, 1.05)
	var spawn_pos := Vector3(player_ship_pos.x + offset.x, 0.0, player_ship_pos.z + offset.z)
	var bearing := compass_bearing(player_ship_pos, spawn_pos)
	var archetype: StringName = &"drowned_sloop"
	if force_corsair:
		archetype = &"corsair_sloop"
	elif cargo_value_aboard >= 700:
		archetype = &"drowned_sloop_raider"
	var label := "Corsair Rival Sloop" if archetype == &"corsair_sloop" else "Drowned Sloop"
	var msg := "Sail on the horizon — %s bearing %s (%d m)!" % [label, bearing, roundi(dist)]

	var evt := _register_event(&"rival_ship", spawn_pos, 240.0, {
		"archetype": archetype,
		"bearing": bearing,
		"distance": dist,
		"message": msg,
	})
	_emit_warning(msg, spawn_pos, &"rival_ship", bearing, dist)
	spawn_rival_ship.emit(spawn_pos, archetype, ship_node)
	return evt


func _trigger_ghost_ship(heading_dir: Vector3) -> Dictionary:
	var dist := maxf(320.0, _pick_sighting_distance())
	var offset := _forward_arc_offset(heading_dir, dist, 1.25)
	var spawn_pos := Vector3(player_ship_pos.x + offset.x, 0.0, player_ship_pos.z + offset.z)
	var bearing := compass_bearing(player_ship_pos, spawn_pos)
	var msg := "Pale sea-fire on the horizon — Ghost Ship bearing %s (%d m)!" % [bearing, roundi(dist)]

	var evt := _register_event(&"ghost_ship", spawn_pos, 260.0, {
		"bearing": bearing,
		"distance": dist,
		"message": msg,
	})
	if is_inside_tree():
		spawn_event_cloud(&"ghost_ship", spawn_pos)
	_emit_warning(msg, spawn_pos, &"ghost_ship", bearing, dist)
	spawn_ghost_ship.emit(spawn_pos)
	return evt


func _trigger_leviathan(heading_dir: Vector3, ship_node: Node) -> Dictionary:
	var dist := maxf(260.0, _pick_sighting_distance() * 0.9)
	var offset := _forward_arc_offset(heading_dir, dist, 0.65)
	var center := Vector3(player_ship_pos.x + offset.x, 0.0, player_ship_pos.z + offset.z)
	var bearing := compass_bearing(player_ship_pos, center)
	var msg := "The sea boils ink-black ahead — Abyssal Leviathan stirring bearing %s (%d m)!" % [bearing, roundi(dist)]

	var evt := _register_event(&"leviathan", center, 300.0, {
		"bearing": bearing,
		"distance": dist,
		"message": msg,
	})
	if is_inside_tree():
		spawn_event_cloud(&"leviathan", center)
	_emit_warning(msg, center, &"leviathan", bearing, dist)
	spawn_leviathan.emit(center, ship_node)
	return evt


func _trigger_fort_siege(fort_pos: Vector3) -> Dictionary:
	var dist := Vector2(fort_pos.x - player_ship_pos.x, fort_pos.z - player_ship_pos.z).length()
	var bearing := compass_bearing(player_ship_pos, fort_pos)
	var msg := "Signal brazier lit over the sea fort — Fort Siege active bearing %s (%d m)!" % [bearing, roundi(dist)]

	var evt := _register_event(&"fort_siege", fort_pos, 420.0, {
		"bearing": bearing,
		"distance": dist,
		"message": msg,
	})
	if is_inside_tree():
		spawn_event_cloud(&"fort_siege", fort_pos)
	_emit_warning(msg, fort_pos, &"fort_siege", bearing, dist)
	spawn_fort_siege.emit(fort_pos, bearing)
	return evt


func _trigger_castaway(heading_dir: Vector3) -> Dictionary:
	var dist := _rng.randf_range(FLOTSAM_MIN_RANGE, FLOTSAM_MAX_RANGE)
	var offset := _forward_arc_offset(heading_dir, dist, 0.55)
	var pos := Vector3(player_ship_pos.x + offset.x, 0.0, player_ship_pos.z + offset.z)
	var bearing := compass_bearing(player_ship_pos, pos)
	var msg := "Distress lantern waving on a raft — Castaway sighting bearing %s (%d m)." % [bearing, roundi(dist)]

	var evt := _register_event(&"castaway", pos, 220.0, {
		"bearing": bearing,
		"distance": dist,
		"message": msg,
	})
	_emit_warning(msg, pos, &"castaway", bearing, dist)
	spawn_castaway.emit(pos)
	return evt


func _trigger_storm_cell(heading_dir: Vector3) -> Dictionary:
	var dist := _pick_sighting_distance()
	var offset := _forward_arc_offset(heading_dir, dist, 0.70)
	var center := Vector3(player_ship_pos.x + offset.x, 0.0, player_ship_pos.z + offset.z)
	# Keep radius smaller than spawn distance so the ship sees the squall wall
	# building ahead instead of snapping straight into zero visibility.
	var radius := minf(dist - 40.0, _rng.randf_range(240.0, 340.0))
	var cross_angle := atan2(heading_dir.x, -heading_dir.z) + _rng.randf_range(-1.1, 1.1)
	var drift_speed := _rng.randf_range(4.5, 8.5)
	var velocity := Vector3(sin(cross_angle), 0.0, -cos(cross_angle)) * drift_speed
	var bearing := compass_bearing(player_ship_pos, center)
	var msg := "Dark squall building ahead — storm cell bearing %s (%d m)!" % [bearing, roundi(dist)]

	var evt := _register_event(&"storm_cell", center, 210.0, {
		"radius": radius,
		"velocity": velocity,
		"bearing": bearing,
		"distance": dist,
		"message": msg,
	})
	_storm_active_id = String(evt["id"])
	if weather_integration and Weather != null:
		Weather.set_storm_cell(center, radius, 0.85, 0.0, velocity)
	_emit_warning(msg, center, &"storm_cell", bearing, dist)
	spawn_storm_cell.emit(center, radius, velocity)
	return evt


func _trigger_flotsam(heading_dir: Vector3) -> Dictionary:
	var dist := _rng.randf_range(FLOTSAM_MIN_RANGE, FLOTSAM_MAX_RANGE)
	var offset := _forward_arc_offset(heading_dir, dist, 0.55)
	var pos := Vector3(player_ship_pos.x + offset.x, 0.0, player_ship_pos.z + offset.z)
	var count := _rng.randi_range(2, 5)
	var bearing := compass_bearing(player_ship_pos, pos)
	var msg := "Flotsam barrels bobbing off the bow — bearing %s (%d m)." % [bearing, roundi(dist)]

	var evt := _register_event(&"flotsam_barrels", pos, 180.0, {
		"count": count,
		"bearing": bearing,
		"distance": dist,
		"message": msg,
	})
	_emit_warning(msg, pos, &"flotsam_barrels", bearing, dist)
	spawn_flotsam_barrels.emit(pos, count)
	return evt


func _trigger_shipwreck(heading_dir: Vector3) -> Dictionary:
	var flat_hdg := Vector3(heading_dir.x, 0.0, heading_dir.z)
	if flat_hdg.length_squared() < 0.001:
		flat_hdg = Vector3.FORWARD
	else:
		flat_hdg = flat_hdg.normalized()
	var dist := _shipwreck_rng.randf_range(SHIPWRECK_MIN_RANGE, SHIPWRECK_MAX_RANGE)
	var base_az := atan2(flat_hdg.x, -flat_hdg.z)
	var az := base_az + _shipwreck_rng.randf_range(-0.65, 0.65)
	var offset := Vector3(sin(az) * dist, 0.0, -cos(az) * dist)
	var pos := Vector3(player_ship_pos.x + offset.x, 0.0, player_ship_pos.z + offset.z)
	var bearing := compass_bearing(player_ship_pos, pos)
	var wreck_seed := maxi(1, int(_shipwreck_rng.randi() & 0x7FFFFFFF))
	var msg := "Circling gulls over a half-sunk hull -- Sunken Shipwreck bearing %s (%d m)!" % [
		bearing, roundi(dist)]

	var evt := _register_event(&"sunken_shipwreck", pos, 360.0, {
		"seed_val": wreck_seed,
		"bearing": bearing,
		"distance": dist,
		"message": msg,
	})
	_emit_warning(msg, pos, &"sunken_shipwreck", bearing, dist)
	spawn_shipwreck.emit(pos, wreck_seed)
	return evt


func _has_active_event(kind: StringName) -> bool:
	for evt in active_events:
		if evt.get("kind", &"") == kind:
			return true
	return false


func _trigger_shark_pack(swimmer_pos: Vector3) -> Dictionary:
	var az := _rng.randf() * TAU
	var dist := _rng.randf_range(35.0, 55.0)
	var center := Vector3(swimmer_pos.x + sin(az) * dist, 0.0, swimmer_pos.z - cos(az) * dist)
	var count := _rng.randi_range(2, 4)
	var bearing := compass_bearing(swimmer_pos, center)
	var msg := "Dorsal fins cutting the swell — shark pack bearing %s!" % bearing

	var evt := _register_event(&"shark_pack", center, 95.0, {
		"count": count,
		"bearing": bearing,
		"distance": dist,
		"message": msg,
	})
	_emit_warning(msg, center, &"shark_pack", bearing, dist)
	spawn_shark_pack.emit(center, count)
	return evt


func _register_event(kind: StringName, pos: Vector3, duration: float,
		extra: Dictionary = {}) -> Dictionary:
	_event_serial += 1
	var evt := {
		"id": "evt_%s_%d" % [String(kind), _event_serial],
		"kind": kind,
		"position": pos,
		"age": 0.0,
		"duration": duration,
	}
	for k in extra.keys():
		evt[k] = extra[k]
	active_events.append(evt)
	return evt


func _emit_warning(msg: String, pos: Vector3, kind: StringName,
		bearing: String, dist: float) -> void:
	sighting_warning.emit(msg, pos, kind, bearing, dist)
	if post_notices and Game != null:
		Game.post_notice(msg)


func _age_active_events(delta: float) -> void:
	var i := 0
	while i < active_events.size():
		var evt: Dictionary = active_events[i]
		evt["age"] = float(evt["age"]) + delta
		if float(evt["age"]) >= float(evt["duration"]):
			var id_str := String(evt.get("id", ""))
			var kind: StringName = evt.get("kind", &"")
			active_events.remove_at(i)
			if id_str == _storm_active_id:
				_storm_active_id = ""
				if weather_integration and Weather != null:
					Weather.clear_storm_cell(15.0)
			if CLOUD_EVENT_KINDS.has(kind) and _event_clouds.has(kind):
				var still_active := false
				for rem_evt in active_events:
					if rem_evt.get("kind", &"") == kind:
						still_active = true
						break
				if not still_active:
					clear_event_cloud(kind)
		else:
			i += 1


func _update_context(delta: float, context: Dictionary) -> void:
	if context.has("last_outpost_id"):
		last_outpost_id = StringName(String(context["last_outpost_id"]))
	if context.has("last_outpost_pos") and context["last_outpost_pos"] is Vector3:
		last_outpost_pos = context["last_outpost_pos"]
	if context.has("lookout_scale"):
		lookout_scale = clampf(float(context["lookout_scale"]), 0.75, 2.0)
	if context.has("voyage_count"):
		voyage_count = maxi(0, int(context["voyage_count"]))
	if context.has("emissary_grade"):
		emissary_grade = clampi(int(context.get("emissary_grade", emissary_grade)), 0, EmissaryLedger.MAX_GRADE)
	if context.has("cargo_value"):
		cargo_value_aboard = maxi(0, int(context["cargo_value"]))
	elif context.has("cargo_nodes") and context["cargo_nodes"] is Array:
		cargo_value_aboard = sum_cargo_value(context["cargo_nodes"] as Array)

	var prev_pos := player_ship_pos
	if context.has("ship_pos") and context["ship_pos"] is Vector3:
		player_ship_pos = context["ship_pos"]
	if context.has("ship_velocity") and context["ship_velocity"] is Vector3:
		player_ship_velocity = context["ship_velocity"]
		if not context.has("ship_pos"):
			player_ship_pos += player_ship_velocity * delta
	elif _has_prev_pos and delta > 0.0001:
		player_ship_velocity = (player_ship_pos - prev_pos) / delta

	if _has_prev_pos:
		var step_dist := Vector2(
			player_ship_pos.x - prev_pos.x,
			player_ship_pos.z - prev_pos.z).length()
		sailing_distance += step_dist
	else:
		_has_prev_pos = true


func _resolve_heading(context: Dictionary) -> Vector3:
	if context.has("ship_forward") and context["ship_forward"] is Vector3:
		var f: Vector3 = context["ship_forward"]
		var flat := Vector3(f.x, 0.0, f.z)
		if flat.length_squared() > 0.001:
			return flat.normalized()
	var v_flat := Vector3(player_ship_velocity.x, 0.0, player_ship_velocity.z)
	if v_flat.length_squared() > 0.05:
		return v_flat.normalized()
	return Vector3(0.0, 0.0, -1.0)


func _pick_sighting_distance() -> float:
	var base := _rng.randf_range(SIGHTING_MIN_RANGE, SIGHTING_MAX_RANGE)
	return maxf(SIGHTING_MIN_RANGE, base * maxf(1.0, lookout_scale))


func _forward_arc_offset(heading: Vector3, distance: float, max_angle_rad: float) -> Vector3:
	var base_az := atan2(heading.x, -heading.z)
	var az := base_az + _rng.randf_range(-max_angle_rad, max_angle_rad)
	return Vector3(sin(az) * distance, 0.0, -cos(az) * distance)


func _roll_next_delays() -> void:
	_next_major_delay = _rng.randf_range(115.0, 175.0)
	_next_flotsam_delay = _rng.randf_range(60.0, 95.0)


func _select_salvage_items(items: Array[Dictionary], total_lost: int) -> Array[Dictionary]:
	if items.is_empty():
		return []
	var target := roundi(float(total_lost) * WRECK_SALVAGE_RATIO)
	if items.size() == 1:
		var kept := items[0].duplicate(true)
		var g := int(kept.get("gold_value", 0))
		kept["gold_value"] = maxi(1, roundi(float(g) * WRECK_SALVAGE_RATIO))
		kept["salvaged_from_wreck"] = true
		return [kept]

	# Sort descending by gold value and pick subset closest to 60% of total value.
	var sorted := items.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("gold_value", 0)) > int(b.get("gold_value", 0))
	)
	var chosen: Array[Dictionary] = []
	var acc := 0
	for entry in sorted:
		var v := int(entry.get("gold_value", 0))
		var dist_without := absf(float(acc - target))
		var dist_with := absf(float((acc + v) - target))
		if chosen.is_empty() or dist_with <= dist_without:
			var copy := (entry as Dictionary).duplicate(true)
			copy["salvaged_from_wreck"] = true
			chosen.append(copy)
			acc += v

	# If coarse item sizes pulled ratio far from 60%, water-discount the last kept item.
	if total_lost > 0 and not chosen.is_empty():
		var ratio := float(acc) / float(total_lost)
		if ratio > 0.68:
			var excess := acc - target
			var last_item: Dictionary = chosen[chosen.size() - 1]
			var lv := int(last_item.get("gold_value", 0))
			if lv > excess + 20:
				last_item["gold_value"] = lv - excess
	return chosen
