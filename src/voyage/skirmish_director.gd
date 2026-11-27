class_name SkirmishDirector
extends Node
## Escalating High-Seas Naval Skirmish wave-combat director.
##
## Orchestrates 4 handcrafted naval combat waves with intermission resupply
## countdowns, difficulty/payout scaling, profile bounty payouts, and cleanly
## decoupled ship/Leviathan spawn signals for `scenes/main.gd` and headless tests.
## Host-authoritative (`Net.is_host()`) for all wave transitions and rewards.

signal wave_started(wave_num: int, wave_title: String, banner_text: String, enemy_count: int)
signal spawn_ship_requested(archetype: StringName, relative_offset: Vector3)
signal spawn_leviathan_requested(relative_offset: Vector3)
signal wave_cleared(wave_num: int, bounty_gold: int, score: int)
signal restock_requested(cannonballs: int, planks: int)
signal skirmish_victory(total_gold: int, total_kills: int, total_score: int)
signal objective_updated(title: String, detail: String, progress: String)

enum State { IDLE, PREPARING, COMBAT, INTERMISSION, VICTORY }

const INTERMISSION_SECONDS: float = 6.0
const RESTOCK_CANNONBALLS: int = 20
const RESTOCK_PLANKS: int = 12
const RESTOCK_BILGE_CLEAR: float = 0.35
const SHIP_KILL_SCORE: int = 100
const LEVIATHAN_KILL_SCORE: int = 500
const SKIRMISH_COMPANY: StringName = &"iron_tide"
const SFX_RESTOCK_BELL: StringName = &"ship_bell"
const RESTOCK_BELL_DB: float = -5.0

const STATE_NAMES: Array[String] = ["IDLE", "PREPARING", "COMBAT", "INTERMISSION", "VICTORY"]

const WAVES: Array[Dictionary] = [
	{
		"wave_num": 1,
		"title": "Drowned Vanguard",
		"bounty": 350,
		"banner": "Wave 1: Drowned Vanguard - Sink the cursed sloop!",
		"spawns": [
			{"kind": &"ship", "archetype": &"drowned_sloop", "offset": Vector3(0.0, 0.0, -240.0)},
		],
	},
	{
		"wave_num": 2,
		"title": "Corsair Pincer",
		"bounty": 650,
		"banner": "Wave 2: Corsair Pincer - Twin enemy hulls closing fast!",
		"spawns": [
			{"kind": &"ship", "archetype": &"drowned_sloop", "offset": Vector3(-210.0, 0.0, -170.0)},
			{"kind": &"ship", "archetype": &"drowned_sloop", "offset": Vector3(210.0, 0.0, -170.0)},
		],
	},
	{
		"wave_num": 3,
		"title": "Spectral Armada",
		"bounty": 1100,
		"banner": "Wave 3: Spectral Armada - Corsair Brigantine & Ghost Ship!",
		"spawns": [
			{"kind": &"ship", "archetype": &"corsair_brigantine", "offset": Vector3(-230.0, 0.0, -210.0)},
			{"kind": &"ship", "archetype": &"ghost_ship", "offset": Vector3(230.0, 0.0, -200.0)},
		],
	},
	{
		"wave_num": 4,
		"title": "Wrath of the Abyss",
		"bounty": 2000,
		"banner": "Final Wave: Wrath of the Abyss - Defeat the Abyssal Leviathan!",
		"spawns": [
			{"kind": &"leviathan", "archetype": &"leviathan", "offset": Vector3(0.0, 0.0, -185.0)},
			{"kind": &"ship", "archetype": &"drowned_sloop", "offset": Vector3(220.0, 0.0, -160.0)},
		],
	},
]

var state: State = State.IDLE
var difficulty_scale: float = 1.0
var payout_scale: float = 1.0
var wave_number: int = 0
var enemies_remaining: int = 0
var enemies_total_in_wave: int = 0
var total_kills: int = 0
var total_bounty_gold: int = 0
var score: int = 0
var intermission_remaining: float = 0.0
var prepare_remaining: float = 0.0
var elapsed_seconds: float = 0.0
## Optional profile override (uses `Game.profile` when null).
var profile: Profile = null
## When false, `Game.post_notice` banners are suppressed (useful in quiet tests).
var post_notices: bool = true
## When false, `Audio.play_stinger` and intermission restock bell SFX are suppressed.
var play_audio: bool = true
## Number of intermission resupply ship-bell SFX cues played during the current skirmish.
var restock_bell_count: int = 0


func _exit_tree() -> void:
	state = State.IDLE
	profile = null


func _physics_process(delta: float) -> void:
	step_skirmish(delta)


## Begin an escalating 4-wave Naval Skirmish (host-only).
## Set `p_prepare_delay > 0.0` for a brief pre-wave countdown in `State.PREPARING`;
## default `0.0` launches Wave 1 immediately for instant naval action.
func start_skirmish(
	p_difficulty_scale: float = 1.0,
	p_payout_scale: float = 1.0,
	p_prepare_delay: float = 0.0
) -> void:
	if not Net.is_host():
		return
	difficulty_scale = clampf(p_difficulty_scale, 0.5, 3.0)
	payout_scale = clampf(p_payout_scale, 0.5, 3.0)
	wave_number = 0
	enemies_remaining = 0
	enemies_total_in_wave = 0
	total_kills = 0
	total_bounty_gold = 0
	score = 0
	intermission_remaining = 0.0
	prepare_remaining = maxf(0.0, p_prepare_delay)
	elapsed_seconds = 0.0
	restock_bell_count = 0

	state = State.PREPARING
	if prepare_remaining > 0.0:
		_post_notice("High-Seas Naval Skirmish - Battle stations! Wave 1 incoming...")
		_emit_objective()
	else:
		_begin_wave(1)


## Stop the active skirmish cleanly and return to `State.IDLE`.
func stop_skirmish() -> void:
	state = State.IDLE
	intermission_remaining = 0.0
	prepare_remaining = 0.0
	enemies_remaining = 0
	enemies_total_in_wave = 0
	_emit_objective()


## Advance wave preparation and intermission countdown timers (host-only).
## Called automatically each physics tick, or directly in headless tests.
func step_skirmish(delta: float) -> void:
	if not Net.is_host() or delta <= 0.0:
		return
	if state == State.IDLE or state == State.VICTORY:
		return
	elapsed_seconds += delta

	if state == State.PREPARING:
		var prev_prep := ceili(prepare_remaining)
		prepare_remaining = maxf(0.0, prepare_remaining - delta)
		if prepare_remaining <= 0.0:
			_begin_wave(1)
		elif ceili(prepare_remaining) != prev_prep:
			_emit_objective()
	elif state == State.INTERMISSION:
		var prev_sec := ceili(intermission_remaining)
		intermission_remaining = maxf(0.0, intermission_remaining - delta)
		if intermission_remaining <= 0.0:
			_begin_wave(wave_number + 1)
		elif ceili(intermission_remaining) != prev_sec:
			_emit_objective()


## Report that an enemy ship or Leviathan from the active wave was defeated (host-only).
func notify_enemy_defeated(kind: StringName = &"ship") -> void:
	if not Net.is_host() or state != State.COMBAT:
		return
	if enemies_remaining <= 0:
		return
	total_kills += 1
	enemies_remaining = maxi(0, enemies_remaining - 1)
	var base_pts := LEVIATHAN_KILL_SCORE if kind == &"leviathan" else SHIP_KILL_SCORE
	score += maxi(1, roundi(float(base_pts) * difficulty_scale))

	if kind == &"leviathan":
		var prof := _get_profile()
		if prof != null:
			prof.record_boss_defeated()

	if enemies_remaining == 0:
		_complete_current_wave()
	else:
		_emit_objective()


## Return strict-ASCII HUD objective summary (`title`, `detail`, `progress`).
func get_objective_summary() -> Dictionary:
	var total_waves := WAVES.size()
	match state:
		State.IDLE:
			return {
				"title": "Naval Skirmish - Standby",
				"detail": "Ready for 4 escalating waves of high-seas combat.",
				"progress": "0 / %d Waves" % total_waves,
			}
		State.PREPARING:
			var secs := maxi(1, ceili(prepare_remaining))
			return {
				"title": "Naval Skirmish - Battle Stations",
				"detail": "First enemy wave sighted in %ds!" % secs,
				"progress": "Wave 1 / %d | 0g Bounty" % total_waves,
			}
		State.COMBAT:
			var w := _get_wave_dict(wave_number)
			var wtitle := String(w.get("title", "Hostile Fleet"))
			var defeated := maxi(0, enemies_total_in_wave - enemies_remaining)
			var noun := "foe" if enemies_remaining == 1 else "foes"
			return {
				"title": "Wave %d / %d: %s" % [wave_number, total_waves, wtitle],
				"detail": "Sink remaining enemy armada (%d %s left)" % [enemies_remaining, noun],
				"progress": "%d / %d defeated | %dg Bounty" % [
					defeated, enemies_total_in_wave, total_bounty_gold,
				],
			}
		State.INTERMISSION:
			var next_w := _get_wave_dict(wave_number + 1)
			var next_title := String(next_w.get("title", "Next Wave"))
			var secs := maxi(1, ceili(intermission_remaining))
			return {
				"title": "Wave %d Cleared - Resupplying" % wave_number,
				"detail": "Next: %s in %ds (+%d Shot, +%d Planks)" % [
					next_title, secs, RESTOCK_CANNONBALLS, RESTOCK_PLANKS,
				],
				"progress": "Wave %d / %d | %dg Bounty" % [wave_number, total_waves, total_bounty_gold],
			}
		State.VICTORY:
			return {
				"title": "Naval Skirmish Victory!",
				"detail": "All %d waves defeated - %d hostiles sunk!" % [total_waves, total_kills],
				"progress": "%dg Bounty | Score %d" % [total_bounty_gold, score],
			}
	return {"title": "", "detail": "", "progress": ""}


## Return a full state dictionary snapshot for HUD, telemetry, or tests.
func get_state() -> Dictionary:
	var w := _get_wave_dict(wave_number)
	return {
		"state": state,
		"state_name": STATE_NAMES[clampi(int(state), 0, STATE_NAMES.size() - 1)],
		"wave_number": wave_number,
		"total_waves": WAVES.size(),
		"wave_title": String(w.get("title", "")),
		"enemies_remaining": enemies_remaining,
		"enemies_total_in_wave": enemies_total_in_wave,
		"total_kills": total_kills,
		"total_bounty_gold": total_bounty_gold,
		"score": score,
		"difficulty_scale": difficulty_scale,
		"payout_scale": payout_scale,
		"intermission_remaining": intermission_remaining,
		"prepare_remaining": prepare_remaining,
		"elapsed_seconds": elapsed_seconds,
		"restock_bell_count": restock_bell_count,
		"objective": get_objective_summary(),
	}


## Host-side helper for `scenes/main.gd` to fulfill `restock_requested` on a player `Ship`:
## adds cannonballs & planks up to ship caps and partially clears bilge floodwater.
static func apply_ship_restock(
	ship: Ship,
	cannonballs: int = RESTOCK_CANNONBALLS,
	planks: int = RESTOCK_PLANKS,
	bilge_clear: float = RESTOCK_BILGE_CLEAR
) -> void:
	if not Net.is_host() or ship == null or not is_instance_valid(ship):
		return
	ship.cannonballs_remaining = mini(Ship.MAX_CANNONBALLS, ship.cannonballs_remaining + maxi(0, cannonballs))
	ship.planks_remaining = mini(Ship.MAX_PLANKS, ship.planks_remaining + maxi(0, planks))
	if bilge_clear > 0.0 and ship.water_level > 0.0:
		ship.bail(bilge_clear)
	if ship.has_method(&"_sync_supply_barrels"):
		ship.call(&"_sync_supply_barrels")


# ==============================================================================
# Internal Wave Progression
# ==============================================================================

func _begin_wave(num: int) -> void:
	if num < 1 or num > WAVES.size():
		return
	var wave := WAVES[num - 1]
	var spawns: Array = wave["spawns"]
	wave_number = num
	enemies_total_in_wave = spawns.size()
	enemies_remaining = enemies_total_in_wave
	intermission_remaining = 0.0
	prepare_remaining = 0.0
	state = State.COMBAT

	var title := String(wave["title"])
	var banner := String(wave["banner"])
	wave_started.emit(wave_number, title, banner, enemies_total_in_wave)

	var has_leviathan := false
	for raw_entry in spawns:
		var entry: Dictionary = raw_entry
		var kind := StringName(entry["kind"])
		var offset: Vector3 = entry["offset"]
		if kind == &"leviathan":
			has_leviathan = true
			spawn_leviathan_requested.emit(offset)
		else:
			var archetype := StringName(entry["archetype"])
			spawn_ship_requested.emit(archetype, offset)

	if play_audio and Audio != null:
		Audio.play_stinger(&"danger" if has_leviathan else &"ship_sighted")
	_post_notice(banner)
	_emit_objective()


func _complete_current_wave() -> void:
	var wave := _get_wave_dict(wave_number)
	var base_bounty := int(wave.get("bounty", 0))
	var bounty_gold := maxi(0, roundi(float(base_bounty) * payout_scale))
	var wave_score := maxi(0, roundi(float(base_bounty) * difficulty_scale))
	total_bounty_gold += bounty_gold
	score += wave_score

	var prof := _get_profile()
	if prof != null and bounty_gold > 0:
		prof.add_gold(bounty_gold)
		prof.bump_stat("gold_earned", bounty_gold)
		var renown_gain := maxi(10, roundi(float(base_bounty) * 0.08))
		prof.add_renown(String(SKIRMISH_COMPANY), renown_gain)
		prof.changed.emit()

	wave_cleared.emit(wave_number, bounty_gold, score)

	if wave_number < WAVES.size():
		state = State.INTERMISSION
		intermission_remaining = INTERMISSION_SECONDS
		restock_requested.emit(RESTOCK_CANNONBALLS, RESTOCK_PLANKS)
		if play_audio and Audio != null:
			Audio.play_stinger(&"discovery")
			if Audio.has_sound(SFX_RESTOCK_BELL):
				Audio.play_sfx(SFX_RESTOCK_BELL, Vector3.INF, RESTOCK_BELL_DB)
				restock_bell_count += 1
		_post_notice(
			"Wave %d Cleared! +%dg Bounty | Supplies Restocked (+%d Shot, +%d Planks) | Next wave in %.0fs!" % [
				wave_number, bounty_gold, RESTOCK_CANNONBALLS, RESTOCK_PLANKS, INTERMISSION_SECONDS,
			]
		)
		_emit_objective()
	else:
		state = State.VICTORY
		intermission_remaining = 0.0
		if play_audio and Audio != null:
			Audio.play_stinger(&"victory")
		_post_notice(
			"Skirmish Victory! All %d waves defeated - %dg Bounty Earned (Score: %d)!" % [
				WAVES.size(), total_bounty_gold, score,
			]
		)
		skirmish_victory.emit(total_bounty_gold, total_kills, score)
		_emit_objective()


func _get_wave_dict(num: int) -> Dictionary:
	if num < 1 or num > WAVES.size():
		return {}
	return WAVES[num - 1]


func _emit_objective() -> void:
	var obj := get_objective_summary()
	objective_updated.emit(String(obj["title"]), String(obj["detail"]), String(obj["progress"]))


func _get_profile() -> Profile:
	if profile != null:
		return profile
	if Game != null:
		return Game.profile
	return null


func _post_notice(text: String) -> void:
	if post_notices and Game != null and text != "":
		Game.post_notice(text)
