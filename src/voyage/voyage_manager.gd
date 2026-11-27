class_name VoyageManager
extends Node
## Host-authoritative tracker of active and offered voyages.
##
## Manages voyage offers, stage progression, diegetic Game.post_notice updates,
## treasure turn-in coordination with Economy, and completion rewards.

signal voyage_started(voyage: Dictionary)
signal voyage_stage_changed(stage_index: int, objective_text: String)
signal voyage_completed(voyage: Dictionary, summary: Dictionary)
signal voyage_failed(voyage: Dictionary, reason: String)
signal available_voyages_changed(offers: Array[Dictionary])

## Currently active voyage dictionary (empty when no voyage is active).
var active_voyage: Dictionary = {}
## Current outpost voyage board offers.
var available_voyages: Array[Dictionary] = []
## Total voyages completed in this session.
var completed_count: int = 0
## Active stage index within `active_voyage["stages"]`, or -1 when idle.
var current_stage_index: int = -1
## Progress counter toward the current stage's `required_count`.
var stage_progress: int = 0
## Elapsed simulation seconds since the current voyage started.
var elapsed_seconds: float = 0.0
## Optional profile override (uses `Game.profile` when null).
var profile: Profile = null
## Modular voyage composer owned by this manager.
var composer: VoyageComposer = VoyageComposer.new()
## Host-authoritative Trading Company Emissary Grade ledger.
var emissary: EmissaryLedger = EmissaryLedger.new()
## When false, `Game.post_notice` calls are suppressed (optional for quiet batch sims).
var post_notices: bool = true

var _enemies_defeated: int = 0
var _treasure_boarded: bool = false
var _voyage_gold_earned: int = 0
var _voyage_renown_earned: int = 0
var _voyage_chests_sold: int = 0
var _late_warned: bool = false


func _init() -> void:
	if emissary != null and not emissary.grade_changed.is_connected(_on_emissary_grade_changed):
		emissary.grade_changed.connect(_on_emissary_grade_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if emissary != null and emissary.grade_changed.is_connected(_on_emissary_grade_changed):
			emissary.grade_changed.disconnect(_on_emissary_grade_changed)
		emissary = null


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if not Net.is_host() or active_voyage.is_empty() or delta <= 0.0:
		return
	elapsed_seconds += delta
	var comp: Dictionary = active_voyage.get("complication", {})
	var limit: float = float(comp.get("time_limit_sec", 0.0))
	if limit > 0.0:
		if elapsed_seconds > limit * 1.5:
			_late_warned = true
			abandon_voyage("Charter deadline expired.")
		elif not _late_warned and elapsed_seconds > limit:
			_late_warned = true
			_notice("Charter clock ran out -- express bonus lost! Deliver soon before the bill voids.")


func has_active_voyage() -> bool:
	return not active_voyage.is_empty()


func is_hauling_home() -> bool:
	if active_voyage.is_empty():
		return false
	return _treasure_boarded or get_current_stage().get("kind", &"") == &"sell_treasure"


func get_current_stage() -> Dictionary:
	if active_voyage.is_empty():
		return {}
	var stages: Array = active_voyage.get("stages", [])
	if current_stage_index < 0 or current_stage_index >= stages.size():
		return {}
	return stages[current_stage_index]


func get_current_objective() -> String:
	var st := get_current_stage()
	return String(st.get("objective", ""))


## Refresh the outpost voyage board with varied company offers (host-only).
func refresh_offers(archipelago_map_data: Variant = [], count: int = 3,
		origin_outpost_id: StringName = &"port_scoundrel") -> Array[Dictionary]:
	if not Net.is_host():
		return available_voyages
	var prof := _get_profile()
	var ranks := {}
	for comp_id in Economy.COMPANIES.keys():
		ranks[comp_id] = Economy.get_company_rank(prof, comp_id)
	available_voyages = composer.generate_board_offers(
		archipelago_map_data, count, ranks, origin_outpost_id)
	available_voyages_changed.emit(available_voyages)
	return available_voyages


## Start a voyage (host-only). Emits `voyage_started` and initial `voyage_stage_changed`.
func start_voyage(voyage: Dictionary) -> bool:
	if not Net.is_host():
		return false
	if voyage.is_empty():
		return false
	var stages: Array = voyage.get("stages", [])
	if stages.is_empty():
		return false
	active_voyage = voyage.duplicate(true)
	current_stage_index = 0
	stage_progress = 0
	elapsed_seconds = 0.0
	_enemies_defeated = 0
	_treasure_boarded = false
	_voyage_gold_earned = 0
	_voyage_renown_earned = 0
	_voyage_chests_sold = 0
	_late_warned = false

	var objective := get_current_objective()
	voyage_started.emit(active_voyage)
	voyage_stage_changed.emit(current_stage_index, objective)
	_notice("Voyage begun: %s -- %s" % [String(active_voyage.get("title", "Voyage")), objective])
	return true


## Start any authored Story Voyage chapter (1..3).
func start_story_voyage(chapter: int, archipelago_map_data: Variant = []) -> Dictionary:
	if not Net.is_host():
		return {}
	var story := composer.get_story_voyage(chapter, archipelago_map_data)
	start_voyage(story)
	return active_voyage


## Start the authored vertical-slice starter Story Voyage ("The Salt-King's Ledger").
func start_starter_voyage(archipelago_map_data: Variant = []) -> Dictionary:
	return start_story_voyage(1, archipelago_map_data)


## Fail or cancel the active voyage (host-only).
func abandon_voyage(reason: String = "Voyage abandoned.") -> void:
	if not Net.is_host() or active_voyage.is_empty():
		return
	var failed := active_voyage
	active_voyage = {}
	current_stage_index = -1
	stage_progress = 0
	_treasure_boarded = false
	voyage_failed.emit(failed, reason)
	_notice("Voyage failed: %s (%s)" % [String(failed.get("title", "Voyage")), reason])


# --- Gameplay Milestone Notifications (host-only) -----------------------

func notify_island_arrived(island_id: StringName) -> void:
	if not Net.is_host():
		return
	var prof := _get_profile()
	if prof != null and island_id != &"":
		if prof.discover(String(island_id)):
			_notice("Island charted: %s" % String(island_id).replace("_", " ").capitalize())
	if active_voyage.is_empty():
		return
	var st := get_current_stage()
	if st.get("kind", &"") == &"sail_to":
		var target := StringName(String(st.get("target_id", &"")))
		if target == &"" or target == island_id:
			_notice("Landfall at %s!" % String(active_voyage.get("target_island_name", String(island_id))))
			_advance_stage()


func notify_clue_solved(_clue_index: int = -1) -> void:
	if not Net.is_host() or active_voyage.is_empty():
		return
	var idx := _find_matching_stage(&"solve_riddle")
	if idx < 0:
		return
	if idx > current_stage_index:
		_jump_to_stage(idx)
	var st := get_current_stage()
	var req := maxi(1, int(st.get("required_count", 1)))
	stage_progress += 1
	if stage_progress >= req:
		_notice("Riddle solved -- the dig site is revealed!")
		_advance_stage()
	else:
		_notice("Riddle clue %d of %d solved!" % [stage_progress, req])


func notify_treasure_unearthed(chest: Variant) -> void:
	if not Net.is_host():
		return
	var info := _extract_treasure_info(chest)
	if emissary != null:
		var active_comp := StringName(String(active_voyage.get("company_id", info.get("company_id", &""))))
		emissary.add_progress(45.0, active_comp)
	if active_voyage.is_empty():
		return
	var idx := _find_matching_stage(&"dig_treasure")
	if idx < 0:
		return
	if idx > current_stage_index:
		_jump_to_stage(idx)
	var st := get_current_stage()
	var req := maxi(1, int(st.get("required_count", 1)))
	stage_progress += 1
	var tname := String(info.get("name", "Treasure"))
	if stage_progress >= req:
		_notice("Unearthed %s!" % tname)
		_advance_stage()
	else:
		_notice("Unearthed %s (%d/%d)." % [tname, stage_progress, req])


func notify_treasure_boarded(chest: Variant) -> void:
	if not Net.is_host():
		return
	var info := _extract_treasure_info(chest)
	if emissary != null:
		var active_comp := StringName(String(active_voyage.get("company_id", info.get("company_id", &""))))
		emissary.add_progress(55.0, active_comp)
	if active_voyage.is_empty():
		return
	_treasure_boarded = true
	var idx := _find_matching_stage(&"board_treasure")
	if idx < 0:
		return
	if idx > current_stage_index:
		_jump_to_stage(idx)
	var st := get_current_stage()
	var req := maxi(1, int(st.get("required_count", 1)))
	stage_progress += 1
	var tname := String(info.get("name", "Treasure"))
	if stage_progress >= req:
		_notice("%s stowed aboard!" % tname)
		_advance_stage()
	else:
		_notice("%s aboard (%d/%d)." % [tname, stage_progress, req])


func notify_enemy_defeated(enemy_kind: StringName = &"drowned") -> void:
	if not Net.is_host():
		return
	if emissary != null:
		emissary.add_progress(35.0, &"iron_tide")
	if active_voyage.is_empty():
		return
	_enemies_defeated += 1
	var st := get_current_stage()
	var skind := StringName(String(st.get("kind", &"")))
	if skind == &"sail_to":
		# Allow sinking open-sea prey or sniping a bounty captain from offshore
		# to advance directly into the combat stage without getting stuck on landfall.
		var stages: Array = active_voyage.get("stages", [])
		var next_idx := current_stage_index + 1
		if next_idx < stages.size():
			var next_st: Dictionary = stages[next_idx]
			var next_kind := StringName(String(next_st.get("kind", &"")))
			var next_target := StringName(String(next_st.get("target_id", &"")))
			if next_kind == &"defeat_captain" and _matches_captain_prey(enemy_kind, next_target):
				_jump_to_stage(next_idx)
				st = get_current_stage()
				skind = next_kind
	if skind == &"defeat_captain" or skind == &"defeat_enemies":
		var target := StringName(String(st.get("target_id", &"")))
		var counts := true
		if skind == &"defeat_captain" and target != &"":
			counts = _matches_captain_prey(enemy_kind, target)
		if counts:
			var req := maxi(1, int(st.get("required_count", 1)))
			stage_progress += 1
			if stage_progress >= req:
				_notice("Threat vanquished!")
				_advance_stage()
			else:
				_notice("Wave cleared (%d/%d)!" % [stage_progress, req])
	elif enemy_kind == &"drowned_sloop" or enemy_kind == &"ghost_ship":
		_notice("Rival vessel sent to the depths -- clear waters ahead!")


## Process a sold treasure (accepts a Carryable, raw treasure info Dictionary,
## or an already-completed Economy.sell_treasure result Dictionary).
func notify_treasure_sold(treasure_info: Variant) -> Dictionary:
	if not Net.is_host():
		return {}
	var info := _extract_treasure_info(treasure_info)
	var comp_id := _resolve_treasure_company(info)
	var mult := emissary.get_multiplier(comp_id) if emissary != null else 1.0
	var sale_emissary_grade := emissary.grade if emissary != null else 0
	var sale: Dictionary
	if info.has("gold_awarded") and bool(info.get("ok", false)):
		sale = info.duplicate(true)
		if mult > 1.001 and not sale.has("emissary_multiplier"):
			var orig_g := int(sale.get("gold_awarded", 0))
			var orig_r := int(sale.get("renown_awarded", 0))
			var scaled_g := maxi(orig_g, roundi(float(orig_g) * mult))
			var scaled_r := maxi(orig_r, roundi(float(orig_r) * mult))
			var extra_g := scaled_g - orig_g
			var extra_r := scaled_r - orig_r
			var prof := _get_profile()
			if prof != null:
				if extra_g > 0:
					prof.add_gold(extra_g)
					prof.bump_stat("gold_earned", extra_g)
				if extra_r > 0:
					prof.add_renown(String(comp_id), extra_r)
				sale["total_gold"] = int(prof.data.get("gold", 0))
			sale["gold_awarded"] = scaled_g
			sale["renown_awarded"] = scaled_r
	else:
		sale = Economy.sell_treasure(_get_profile(), info, mult)

	if not bool(sale.get("ok", false)):
		return sale

	sale["emissary_multiplier"] = mult
	sale["emissary_grade"] = sale_emissary_grade

	var gold_awarded := int(sale.get("gold_awarded", 0))
	var renown_awarded := int(sale.get("renown_awarded", 0))
	if mult > 1.001:
		_notice("Sold %s for %d gold (+%d renown, %.2fx Emissary)." % [
			String(sale.get("name", "Treasure")), gold_awarded, renown_awarded, mult])
	else:
		_notice("Sold %s for %d gold (+%d renown)." % [
			String(sale.get("name", "Treasure")), gold_awarded, renown_awarded])
	var rank_msg := String(sale.get("rank_up_notice", ""))
	if rank_msg != "":
		_notice(rank_msg)

	if emissary != null:
		emissary.add_progress(28.0, comp_id)

	if active_voyage.is_empty():
		return sale

	_voyage_gold_earned += gold_awarded
	_voyage_renown_earned += renown_awarded
	_voyage_chests_sold += 1

	var idx := _find_matching_stage(&"sell_treasure")
	if idx >= 0:
		if idx > current_stage_index:
			_jump_to_stage(idx)
		var st := get_current_stage()
		var req := maxi(1, int(st.get("required_count", 1)))
		stage_progress += 1
		if stage_progress >= req:
			_advance_stage()
	return sale


# --- Replication Helpers ------------------------------------------------

func get_state() -> Dictionary:
	return {
		"active_voyage": active_voyage.duplicate(true),
		"current_stage_index": current_stage_index,
		"stage_progress": stage_progress,
		"elapsed_seconds": elapsed_seconds,
		"completed_count": completed_count,
		"treasure_boarded": _treasure_boarded,
		"late_warned": _late_warned,
		"emissary": emissary.get_state() if emissary != null else {},
	}


func apply_state(state: Dictionary) -> void:
	var av: Variant = state.get("active_voyage", {})
	active_voyage = (av as Dictionary).duplicate(true) if av is Dictionary else {}
	current_stage_index = int(state.get("current_stage_index", -1))
	stage_progress = int(state.get("stage_progress", 0))
	elapsed_seconds = float(state.get("elapsed_seconds", 0.0))
	completed_count = int(state.get("completed_count", completed_count))
	_treasure_boarded = bool(state.get("treasure_boarded", false))
	_late_warned = bool(state.get("late_warned", false))
	var em: Variant = state.get("emissary", null)
	if emissary != null and em is Dictionary:
		emissary.apply_state(em as Dictionary)


static func _matches_captain_prey(enemy_kind: StringName, target: StringName) -> bool:
	return enemy_kind == target or enemy_kind == &"drowned_captain" \
		or enemy_kind == &"ghost_ship" or enemy_kind == &"drowned_sloop"


# --- Internal Stage Flow ------------------------------------------------

func _find_matching_stage(stage_kind: StringName) -> int:
	var stages: Array = active_voyage.get("stages", [])
	for i in range(maxi(0, current_stage_index), stages.size()):
		var st: Dictionary = stages[i]
		if StringName(String(st.get("kind", &""))) == stage_kind:
			return i
	return -1


func _jump_to_stage(idx: int) -> void:
	current_stage_index = idx
	stage_progress = 0


func _advance_stage() -> void:
	var stages: Array = active_voyage.get("stages", [])
	var comp_id := StringName(String(active_voyage.get("company_id", &"")))
	if emissary != null:
		emissary.add_progress(60.0, comp_id)
	current_stage_index += 1
	stage_progress = 0
	if current_stage_index >= stages.size():
		_complete_active_voyage()
		return
	var objective := get_current_objective()
	voyage_stage_changed.emit(current_stage_index, objective)
	_notice(objective)


func _complete_active_voyage() -> void:
	var finished := active_voyage
	var payoff: Dictionary = finished.get("payoff", {})
	var company_id := StringName(String(finished.get("company_id", &"gilded_compass")))
	var mult := emissary.get_multiplier(company_id) if emissary != null else 1.0
	var raw_bonus_gold := 0 if _late_warned else int(payoff.get("bonus_gold", 0))
	var raw_bonus_renown := int(payoff.get("bonus_renown", 0))
	var bonus_gold := maxi(0, roundi(float(raw_bonus_gold) * mult))
	var bonus_renown := maxi(0, roundi(float(raw_bonus_renown) * mult))
	var prof := _get_profile()

	var rank_up_notice := ""
	if prof != null:
		var old_rank := Economy.get_company_rank(prof, company_id)
		if bonus_gold > 0:
			prof.add_gold(bonus_gold)
			prof.bump_stat("gold_earned", bonus_gold)
		if bonus_renown > 0:
			prof.add_renown(String(company_id), bonus_renown)
		prof.bump_stat("voyages_completed", 1)
		var new_rank := Economy.get_company_rank(prof, company_id)
		if new_rank > old_rank:
			var comp_name := String(Economy.COMPANIES.get(company_id, {}).get("name", String(company_id)))
			rank_up_notice = "%s: Promoted to Rank %d -- %s!" % [
				comp_name, new_rank, Economy.rank_title(new_rank)]

	completed_count += 1
	var summary := {
		"voyage_id": String(finished.get("id", "")),
		"title": String(finished.get("title", "Voyage")),
		"shape": finished.get("shape", &"buried_hoard"),
		"company_id": company_id,
		"is_story": bool(finished.get("is_story", false)),
		"story_chapter": int(finished.get("story_chapter", 0)),
		"bonus_gold": bonus_gold,
		"bonus_renown": bonus_renown,
		"emissary_multiplier": mult,
		"total_gold_earned": _voyage_gold_earned + bonus_gold,
		"total_renown_earned": _voyage_renown_earned + bonus_renown,
		"chests_sold": _voyage_chests_sold,
		"enemies_defeated": _enemies_defeated,
		"elapsed_seconds": elapsed_seconds,
		"on_time": not _late_warned,
		"rank_up_notice": rank_up_notice,
	}

	active_voyage = {}
	current_stage_index = -1
	stage_progress = 0
	_treasure_boarded = false

	voyage_completed.emit(finished, summary)
	_notice("Voyage complete: %s! (+%d bonus gold, +%d renown)" % [
		summary["title"], bonus_gold, bonus_renown])
	if rank_up_notice != "":
		_notice(rank_up_notice)


func _on_emissary_grade_changed(company_id: StringName, new_grade: int, multiplier: float) -> void:
	if new_grade < 2:
		return
	var badge := EmissaryLedger.format_badge_text(company_id, new_grade, multiplier)
	_notice("Emissary Grade Up! %s" % badge)
	if Audio != null:
		Audio.play_stinger(&"discovery")


func _resolve_treasure_company(info: Dictionary) -> StringName:
	var raw_id: Variant = info.get("treasure_id", info.get("id", &""))
	var tid := StringName(String(raw_id))
	var base := TreasureCatalog.get_entry(tid) if tid != &"" else {}
	var comp_id := StringName(String(info.get("company_id",
			base.get("company_id", &"gilded_compass"))))
	if not Economy.COMPANIES.has(comp_id):
		comp_id = &"gilded_compass"
	return comp_id


func _extract_treasure_info(raw: Variant) -> Dictionary:
	if raw is Dictionary:
		return raw as Dictionary
	if raw is Node:
		return TreasureCatalog.inspect_carryable(raw as Node)
	if raw is StringName or raw is String:
		var tid := StringName(String(raw))
		var entry := TreasureCatalog.get_entry(tid)
		if not entry.is_empty():
			entry["treasure_id"] = tid
			return entry
	return {}


func _get_profile() -> Profile:
	if profile != null:
		return profile
	if Game != null:
		return Game.profile
	return null


func _notice(text: String) -> void:
	if post_notices and Game != null and text != "":
		Game.post_notice(text)
