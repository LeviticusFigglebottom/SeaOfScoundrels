extends TestCase
## Headless tests for Wave 32B:
##   - Guided 8-Stage Interactive TutorialDirector (Maiden Voyage)
##   - Escalating 4-Wave SkirmishDirector (High-Seas Naval Skirmish)
##   - CrewDialogue strict-ASCII tutorial_step, skirmish_wave, and skirmish_victory callouts

const SLOOP_SCENE: PackedScene = preload("res://src/ship/sloop.tscn")
const PAWN_SCENE: PackedScene = preload("res://src/characters/pawn.tscn")

var _root: Node3D = null
var _saved_weather: Dictionary = {}
var _saved_amp: float = 1.0
var _saved_profile_data: Dictionary = {}


func _begin() -> void:
	_saved_weather = Weather.get_state()
	_saved_amp = Sea.amp_scale
	_saved_profile_data = Game.profile.data.duplicate(true)
	Net.start_single_player()
	Weather.day_length_seconds = 0.0
	Weather.lightning_enabled = false
	Weather.set_weather(0.0, 10.0, 0.0)
	Sea.amp_scale = 0.0
	_root = Node3D.new()
	add_child(_root)


func _end() -> void:
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	await physics_frames(3)
	Rowboat.clear_shared_cache()
	Weather.apply_state(_saved_weather)
	Sea.amp_scale = _saved_amp
	Game.profile.data = _saved_profile_data.duplicate(true)


static func _is_strict_ascii(txt: String) -> bool:
	for i in txt.length():
		if txt.unicode_at(i) >= 128:
			return false
	return true


func _make_player_rig(ship: Ship) -> Dictionary:
	var pawn := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(pawn)
	pawn.board(ship, ship.ship_point(Vector3(0.0, 1.12, 0.8)))
	var inv := Inventory.new()
	inv.input_enabled = false
	pawn.add_child(inv)
	var mtv := MapTableView.new()
	mtv.mount_to_ship(ship)
	var rb := Rowboat.new()
	rb.name = "TutorialRowboat"
	_root.add_child(rb)
	rb.attach_to_ship(ship)
	return {
		"pawn": pawn,
		"inv": inv,
		"map_table": mtv,
		"rowboat": rb,
	}


# ==============================================================================
# 1. Guided 8-Stage TutorialDirector (Maiden Voyage)
# ==============================================================================

func test_wave32_tutorial_director_full_8_step_progression_and_graduation() -> void:
	_begin()

	# Verify all 8 authored stage definitions are strictly ASCII.
	check_eq(TutorialDirector.STAGES.size(), 8, "TutorialDirector has exactly 8 stages")
	for i in TutorialDirector.STAGES.size():
		var st: Dictionary = TutorialDirector.STAGES[i]
		var title := String(st["title"])
		var hint := String(st["hint"])
		check(_is_strict_ascii(title), "Stage %d title strict ASCII: '%s'" % [i, title])
		check(_is_strict_ascii(hint), "Stage %d hint strict ASCII: '%s'" % [i, hint])

	var sloop := SLOOP_SCENE.instantiate() as Ship
	sloop.enable_effects = false
	_root.add_child(sloop)
	await physics_frames(8)

	var rig := _make_player_rig(sloop)
	var pawn: Pawn = rig["pawn"]
	var inv: Inventory = rig["inv"]
	var mtv: MapTableView = rig["map_table"]
	var rb: Rowboat = rig["rowboat"]
	await physics_frames(4)

	# Anchor sloop in harbour with furled sails before starting Maiden Voyage.
	sloop.anchor_down = true
	sloop.anchor_progress = 1.0
	sloop.sail_set = 0.0
	sloop.set_sail_target(0.0)
	inv.equip(&"cutlass", true)

	var td := TutorialDirector.new()
	td.play_audio = false
	td.post_notices = true
	_root.add_child(td)
	td.bind(sloop, pawn, inv, mtv, rb)

	var changed_steps: Array[Dictionary] = []
	var completed_steps: Array[Dictionary] = []
	var graduation_awards: Array[Dictionary] = []
	var skipped_count := [0]
	var notices: Array[String] = []

	var on_notice := func(msg: String) -> void:
		notices.append(msg)
	Game.notice.connect(on_notice)

	td.step_changed.connect(func(idx: int, sid: StringName, title: String, hint: String, prog: String) -> void:
		changed_steps.append({"index": idx, "id": sid, "title": title, "hint": hint, "progress": prog})
	)
	td.step_completed.connect(func(idx: int, sid: StringName) -> void:
		completed_steps.append({"index": idx, "id": sid})
	)
	td.tutorial_completed.connect(func(bg: int, br: int) -> void:
		graduation_awards.append({"gold": bg, "renown": br})
	)
	td.tutorial_skipped.connect(func() -> void:
		skipped_count[0] += 1
	)

	var gold_before := int(Game.profile.data.get("gold", 0))
	var renown_before := int((Game.profile.data.get("renown", {}) as Dictionary).get("gilded_compass", 0))

	var island_pos := sloop.global_position + Vector3(0.0, 0.0, -320.0)
	td.start_tutorial(island_pos, "Cutlass Cay")

	check(td.active and not td.completed, "Tutorial starts active and incomplete")
	check_eq(td.current_step, 0, "Tutorial starts at stage 0")
	check_eq(td.get_progress_text(), "Step 1 / 8", "Progress text begins at Step 1 / 8")
	check_eq(changed_steps.size(), 1, "start_tutorial emits initial step_changed")
	check_eq(changed_steps[0]["id"], &"equip_compass", "Stage 0 id is equip_compass")

	# Stage 0 -> 1: Equip Brass Compass
	inv.equip(&"compass", true)
	td.step_tutorial(0.05)
	check_eq(td.current_step, 1, "Equipping compass advances to stage 1 (check_map_table)")
	check_eq(completed_steps.size(), 1, "Stage 0 completed once")
	check_eq(completed_steps[0]["id"], &"equip_compass", "Stage 0 completed id matches")

	# Stage 1 -> 2: Place Chart Pin on MapTableView
	mtv.place_marker(island_pos)
	td.step_tutorial(0.05)
	check_eq(td.current_step, 2, "Placing chart pin advances to stage 2 (raise_anchor)")
	check_eq(td.get_progress_text(), "Step 3 / 8", "Progress text reads Step 3 / 8 on stage 2")

	# Stage 2 -> 3: Raise Anchor Capstan (must wait while anchored)
	td.step_tutorial(0.05)
	check_eq(td.current_step, 2, "Stage 2 waits while ship remains anchored")
	sloop.anchor_down = false
	sloop.anchor_progress = 0.0
	td.step_tutorial(0.05)
	check_eq(td.current_step, 3, "Raising anchor advances to stage 3 (drop_and_trim_sails)")

	# Stage 3 -> 4: Drop & Trim Sails (must wait while furled)
	td.step_tutorial(0.05)
	check_eq(td.current_step, 3, "Stage 3 waits while sails are furled")
	sloop.set_sail_target(0.55)
	sloop.sail_set = 0.55
	sloop.sail_trim = sloop.ideal_sail_trim()
	td.step_tutorial(0.05)
	check_eq(td.current_step, 4, "Dropping & trimming sails advances to stage 4 (take_helm_and_sail)")

	# Stage 4 -> 5: Take Helm & Sail 45 m clear of Port Scoundrel
	td.step_tutorial(0.05)
	check_eq(td.current_step, 4, "Stage 4 waits before leaving harbour")
	sloop.global_position += Vector3(0.0, 0.0, -50.0)
	td.step_tutorial(0.05)
	check_eq(td.current_step, 5, "Sailing 50 m clear advances to stage 5 (fire_cannon)")

	# Stage 5 -> 6: Fire a Broadside Cannon
	td.step_tutorial(0.05)
	check_eq(td.current_step, 5, "Stage 5 waits until cannon or harpoon fires")
	var fired_ball := sloop.fire_cannon(&"port", pawn)
	check(fired_ball != null, "Real Sloop.fire_cannon spawns a Cannonball")
	td.step_tutorial(0.05)
	check_eq(td.current_step, 6, "Firing broadside cannon advances to stage 6 (reach_island_or_rowboat)")

	# Stage 6 -> 7: Launch Stern Rowboat
	check(rb.is_docked(), "Rowboat starts docked prior to launch")
	check(rb.launch(pawn, false), "Rowboat launches cleanly from stern davits")
	td.step_tutorial(0.05)
	check_eq(td.current_step, 7, "Launching rowboat advances to stage 7 (dig_and_sell_treasure)")
	check_eq(td.get_progress_text(), "Step 8 / 8", "Progress text reads Step 8 / 8 on final stage")

	# Stage 7 -> Graduation: Unearth sub-tip + Sell chest
	td.notify_treasure_unearthed()
	check(td.active and not td.completed, "Unearthing chest keeps tutorial active until sold")
	check_eq(td.last_sub_tip, TutorialDirector.UNEARTHED_SUB_TIP, "Sub-tip posted when chest unearthed")
	check(_is_strict_ascii(td.last_sub_tip), "Unearthed sub-tip is strict ASCII")
	var cur_dict := td.get_current_step_dict()
	check_eq(String(cur_dict.get("hint", "")), TutorialDirector.UNEARTHED_SUB_TIP,
		"Active stage 7 hint updates to haul-home reminder after unearthing")

	td.notify_treasure_sold()
	check(td.completed and not td.active, "Selling chest completes tutorial and transitions to Open Seas")
	check_eq(completed_steps.size(), 8, "All 8 stages emitted step_completed")
	check_eq(changed_steps.size(), 8, "All 8 stages emitted step_changed exactly once")
	check_eq(graduation_awards.size(), 1, "tutorial_completed emitted once on graduation")
	if graduation_awards.size() == 1:
		check_eq(graduation_awards[0]["gold"], 500, "Graduation bonus awards +500 gold")
		check_eq(graduation_awards[0]["renown"], 100, "Graduation bonus awards +100 renown")

	var gold_after := int(Game.profile.data.get("gold", 0))
	var renown_after := int((Game.profile.data.get("renown", {}) as Dictionary).get("gilded_compass", 0))
	check_eq(gold_after - gold_before, 500, "Game.profile received +500 graduation gold")
	check_eq(renown_after - renown_before, 100, "Game.profile received +100 Gilded Compass renown")

	# Verify every emitted step title/hint/progress & notice is strict ASCII.
	for entry in changed_steps:
		check(_is_strict_ascii(String(entry["title"])), "Emitted step title strict ASCII")
		check(_is_strict_ascii(String(entry["hint"])), "Emitted step hint strict ASCII")
		check(_is_strict_ascii(String(entry["progress"])), "Emitted step progress strict ASCII")
	for n_msg in notices:
		check(_is_strict_ascii(n_msg), "Tutorial Game.notice strict ASCII: '%s'" % n_msg)

	# ------------------------------------------------------------------
	# Alternative Triggers + skip_current_step() + skip_all()
	# ------------------------------------------------------------------
	mtv.clear_markers()
	rb.global_position = rb.get_dock_world_transform(sloop).origin
	rb.dock_to_ship(sloop, pawn)
	inv.equip(&"cutlass", true)
	sloop.anchor_down = true
	sloop.anchor_progress = 1.0
	sloop.sail_set = 0.0

	var td2 := TutorialDirector.new()
	td2.play_audio = false
	td2.post_notices = false
	_root.add_child(td2)
	td2.bind(sloop, pawn, inv, mtv, rb)
	var td2_skipped := [0]
	var td2_completed := [0]
	td2.tutorial_skipped.connect(func() -> void: td2_skipped[0] += 1)
	td2.tutorial_completed.connect(func(_g: int, _r: int) -> void: td2_completed[0] += 1)

	td2.start_tutorial(sloop.global_position + Vector3(0.0, 0.0, -350.0), "Cutlass Cay")
	# skip_current_step advances 0 -> 1 cleanly
	td2.skip_current_step()
	check_eq(td2.current_step, 1, "skip_current_step advances 0 -> 1")

	# Occupying map_table station completes stage 1
	var map_st := sloop.get_station(&"map_table")
	check(map_st != null, "Sloop has map_table station")
	if map_st != null:
		pawn.teleport(map_st.get_stand_global().origin)
		check(pawn.enter_station(map_st), "Pawn occupies map_table station")
		td2.step_tutorial(0.05)
		check_eq(td2.current_step, 2, "Entering map_table station completes stage 1")
		pawn.leave_station()

	# Skip through stages 2, 3, 4 to reach stage 5 (fire_cannon)
	td2.skip_current_step()
	td2.skip_current_step()
	td2.skip_current_step()
	check_eq(td2.current_step, 5, "Skipped cleanly to stage 5 (fire_cannon)")

	# Bow ShipHarpoon fire also completes stage 5!
	var hp_res := sloop.fire_harpoon(&"port", pawn)
	check(not hp_res.is_empty(), "Sloop bow harpoon fires cleanly")
	td2.step_tutorial(0.05)
	check_eq(td2.current_step, 6, "Firing bow ShipHarpoon completes stage 5")
	sloop.release_harpoon(&"port")

	# Stepping onto island terrain (pawn.platform == null) completes stage 6!
	pawn.platform = null
	td2.step_tutorial(0.05)
	check_eq(td2.current_step, 7, "Stepping onto island terrain completes stage 6")

	# skip_all() exits tutorial without awarding graduation bonus!
	var gold_before_skip := int(Game.profile.data.get("gold", 0))
	td2.skip_all()
	check(not td2.active and not td2.completed, "skip_all deactivates tutorial without completing")
	check_eq(td2_skipped[0], 1, "skip_all emits tutorial_skipped once")
	check_eq(td2_completed[0], 0, "skip_all does not emit tutorial_completed")
	check_eq(int(Game.profile.data.get("gold", 0)), gold_before_skip, "skip_all awards 0 graduation gold")

	Game.notice.disconnect(on_notice)
	await _end()
	check_eq(Rowboat._active_instances, 0, "Zero leaked Rowboat instances after tutorial teardown")


# ==============================================================================
# 2. Escalating 4-Wave SkirmishDirector + CrewDialogue Callouts
# ==============================================================================

func test_wave32_skirmish_director_all_4_waves_restock_bounties_and_victory() -> void:
	_begin()

	var sd := SkirmishDirector.new()
	sd.play_audio = false
	sd.post_notices = true
	_root.add_child(sd)

	var waves_seen: Array[Dictionary] = []
	var ships_spawned: Array[Dictionary] = []
	var leviathans_spawned: Array[Vector3] = []
	var waves_cleared: Array[Dictionary] = []
	var restocks: Array[Dictionary] = []
	var victories: Array[Dictionary] = []
	var objectives: Array[Dictionary] = []
	var notices: Array[String] = []

	var on_notice := func(msg: String) -> void:
		notices.append(msg)
	Game.notice.connect(on_notice)

	sd.wave_started.connect(func(wn: int, wt: String, banner: String, ec: int) -> void:
		waves_seen.append({"wave": wn, "title": wt, "banner": banner, "count": ec})
	)
	sd.spawn_ship_requested.connect(func(arch: StringName, off: Vector3) -> void:
		ships_spawned.append({"wave": sd.wave_number, "archetype": arch, "offset": off})
	)
	sd.spawn_leviathan_requested.connect(func(off: Vector3) -> void:
		leviathans_spawned.append(off)
	)
	sd.wave_cleared.connect(func(wn: int, bounty: int, sc: int) -> void:
		waves_cleared.append({"wave": wn, "bounty": bounty, "score": sc})
	)
	sd.restock_requested.connect(func(cb: int, pl: int) -> void:
		restocks.append({"cannonballs": cb, "planks": pl})
	)
	sd.skirmish_victory.connect(func(tg: int, tk: int, ts: int) -> void:
		victories.append({"gold": tg, "kills": tk, "score": ts})
	)
	sd.objective_updated.connect(func(t: String, d: String, p: String) -> void:
		objectives.append({"title": t, "detail": d, "progress": p})
	)

	# Standby objective before start is strict ASCII
	var idle_obj := sd.get_objective_summary()
	check(_is_strict_ascii(String(idle_obj["title"])) and _is_strict_ascii(String(idle_obj["detail"])) \
		and _is_strict_ascii(String(idle_obj["progress"])), "IDLE objective summary is strict ASCII")

	var gold_before := int(Game.profile.data.get("gold", 0))
	var iron_renown_before := int((Game.profile.data.get("renown", {}) as Dictionary).get("iron_tide", 0))
	var bosses_before := int(Game.profile.get_stats().get("bosses_defeated", 0))

	# ------------------------------------------------------------------
	# Run A: Standard 1.0x Difficulty / 1.0x Payout across all 4 waves
	# ------------------------------------------------------------------
	sd.start_skirmish(1.0, 1.0)
	check_eq(sd.state, SkirmishDirector.State.COMBAT, "Wave 1 enters COMBAT immediately")
	check_eq(sd.wave_number, 1, "Wave 1 active")
	check_eq(sd.enemies_remaining, 1, "Wave 1 has 1 enemy")
	check_eq(waves_seen.size(), 1, "wave_started emitted for Wave 1")
	check_eq(waves_seen[0]["title"], "Drowned Vanguard", "Wave 1 title is Drowned Vanguard")
	check_eq(ships_spawned.size(), 1, "Wave 1 requests 1 ship spawn")
	check_eq(ships_spawned[0]["archetype"], &"drowned_sloop", "Wave 1 spawns drowned_sloop")

	# Defeat Wave 1 -> INTERMISSION + restock
	sd.notify_enemy_defeated(&"ship")
	check_eq(sd.state, SkirmishDirector.State.INTERMISSION, "Wave 1 clear enters INTERMISSION")
	check_near(sd.intermission_remaining, SkirmishDirector.INTERMISSION_SECONDS, 0.01,
		"Intermission countdown starts at 6.0 s")
	check_eq(waves_cleared.size(), 1, "wave_cleared emitted for Wave 1")
	check_eq(waves_cleared[0]["bounty"], 350, "Wave 1 bounty is 350g")
	check_eq(restocks.size(), 1, "restock_requested emitted after Wave 1")
	check_eq(restocks[0]["cannonballs"], 20, "Restock grants +20 cannonballs")
	check_eq(restocks[0]["planks"], 12, "Restock grants +12 planks")

	# Intermission timer does not start Wave 2 prematurely
	sd.step_skirmish(3.0)
	check_eq(sd.state, SkirmishDirector.State.INTERMISSION, "Still in INTERMISSION after 3.0 s")
	check_eq(sd.wave_number, 1, "Still wave 1 during intermission")
	sd.step_skirmish(3.1)

	# Wave 2: Corsair Pincer (twin flanking drowned sloops)
	check_eq(sd.state, SkirmishDirector.State.COMBAT, "Wave 2 begins after 6.0 s intermission")
	check_eq(sd.wave_number, 2, "Wave 2 active")
	check_eq(sd.enemies_remaining, 2, "Wave 2 has 2 enemies")
	check_eq(waves_seen[1]["title"], "Corsair Pincer", "Wave 2 title is Corsair Pincer")
	check_eq(ships_spawned.size(), 3, "Wave 2 requested 2 additional ship spawns")
	check_eq(ships_spawned[1]["archetype"], &"drowned_sloop", "Wave 2 spawn A is drowned_sloop")
	check_eq(ships_spawned[2]["archetype"], &"drowned_sloop", "Wave 2 spawn B is drowned_sloop")
	var off_a: Vector3 = ships_spawned[1]["offset"]
	var off_b: Vector3 = ships_spawned[2]["offset"]
	check(off_a.x < 0.0 and off_b.x > 0.0, "Wave 2 flanks port (-X) and starboard (+X)")

	sd.notify_enemy_defeated(&"ship")
	check_eq(sd.state, SkirmishDirector.State.COMBAT, "Wave 2 stays in COMBAT with 1 enemy remaining")
	check_eq(sd.enemies_remaining, 1, "Wave 2 has 1 enemy remaining")
	sd.notify_enemy_defeated(&"ship")
	check_eq(sd.state, SkirmishDirector.State.INTERMISSION, "Wave 2 clear enters INTERMISSION")
	check_eq(waves_cleared[1]["bounty"], 650, "Wave 2 bounty is 650g")
	check_eq(restocks.size(), 2, "restock_requested emitted after Wave 2")

	# Wave 3: Spectral Armada (corsair_brigantine + ghost_ship)
	sd.step_skirmish(6.1)
	check_eq(sd.state, SkirmishDirector.State.COMBAT, "Wave 3 enters COMBAT")
	check_eq(sd.wave_number, 3, "Wave 3 active")
	check_eq(waves_seen[2]["title"], "Spectral Armada", "Wave 3 title is Spectral Armada")
	check_eq(ships_spawned.size(), 5, "Wave 3 requested 2 ship spawns")
	check_eq(ships_spawned[3]["archetype"], &"corsair_brigantine", "Wave 3 spawns corsair_brigantine")
	check_eq(ships_spawned[4]["archetype"], &"ghost_ship", "Wave 3 spawns ghost_ship")

	sd.notify_enemy_defeated(&"ship")
	sd.notify_enemy_defeated(&"ship")
	check_eq(sd.state, SkirmishDirector.State.INTERMISSION, "Wave 3 clear enters INTERMISSION")
	check_eq(waves_cleared[2]["bounty"], 1100, "Wave 3 bounty is 1100g")
	check_eq(restocks.size(), 3, "restock_requested emitted after Wave 3")

	# Wave 4: Wrath of the Abyss (leviathan + drowned_sloop escort)
	sd.step_skirmish(6.1)
	check_eq(sd.state, SkirmishDirector.State.COMBAT, "Wave 4 enters COMBAT")
	check_eq(sd.wave_number, 4, "Wave 4 active")
	check_eq(waves_seen[3]["title"], "Wrath of the Abyss", "Wave 4 title is Wrath of the Abyss")
	check_eq(leviathans_spawned.size(), 1, "Wave 4 requests 1 Leviathan spawn")
	check_eq(ships_spawned.size(), 6, "Wave 4 requests 1 drowned_sloop escort")
	check_eq(ships_spawned[5]["archetype"], &"drowned_sloop", "Wave 4 escort is drowned_sloop")

	sd.notify_enemy_defeated(&"leviathan")
	check_eq(sd.enemies_remaining, 1, "Escort remains after Leviathan defeated")
	sd.notify_enemy_defeated(&"ship")

	# Victory assertions
	check_eq(sd.state, SkirmishDirector.State.VICTORY, "Clearing Wave 4 enters VICTORY")
	check_eq(waves_cleared.size(), 4, "All 4 waves emitted wave_cleared")
	check_eq(waves_cleared[3]["bounty"], 2000, "Wave 4 bounty is 2000g")
	check_eq(restocks.size(), 3, "No extra intermission restock emitted after final Wave 4")
	check_eq(victories.size(), 1, "skirmish_victory emitted once")
	check_eq(sd.total_bounty_gold, 4100, "Total base bounty across 4 waves is 4100g")
	check_eq(sd.total_kills, 7, "Total kills across 4 waves is 7")
	check_eq(sd.score, 5200, "Total base score is 6*100 + 500 + 4100 = 5200")
	if victories.size() == 1:
		check_eq(victories[0]["gold"], 4100, "skirmish_victory reports 4100g total")
		check_eq(victories[0]["kills"], 7, "skirmish_victory reports 7 kills")
		check_eq(victories[0]["score"], 5200, "skirmish_victory reports 5200 score")

	# Verify profile integration (gold, Iron Tide renown, bosses_defeated)
	var gold_after := int(Game.profile.data.get("gold", 0))
	var iron_renown_after := int((Game.profile.data.get("renown", {}) as Dictionary).get("iron_tide", 0))
	var bosses_after := int(Game.profile.get_stats().get("bosses_defeated", 0))
	check_eq(gold_after - gold_before, 4100, "Game.profile received 4100g skirmish bounties")
	check(iron_renown_after > iron_renown_before, "Game.profile received Iron Tide renown")
	check_eq(bosses_after - bosses_before, 1, "Defeating Wave 4 Leviathan incremented bosses_defeated")

	# Verify apply_ship_restock helper on a real Sloop
	var sloop := SLOOP_SCENE.instantiate() as Ship
	sloop.enable_effects = false
	_root.add_child(sloop)
	await physics_frames(4)
	sloop.cannonballs_remaining = 8
	sloop.planks_remaining = 4
	sloop.water_level = 0.50
	SkirmishDirector.apply_ship_restock(sloop)
	check_eq(sloop.cannonballs_remaining, 28, "apply_ship_restock adds +20 cannonballs")
	check_eq(sloop.planks_remaining, 16, "apply_ship_restock adds +12 planks")
	check_near(sloop.water_level, 0.15, 0.02, "apply_ship_restock clears 0.35 bilge water")

	# ------------------------------------------------------------------
	# Run B: Veteran Scaling (1.5x difficulty & 1.5x payout + PREPARING)
	# ------------------------------------------------------------------
	var vet_sd := SkirmishDirector.new()
	vet_sd.play_audio = false
	vet_sd.post_notices = false
	vet_sd.profile = Profile.new()
	_root.add_child(vet_sd)

	vet_sd.start_skirmish(1.5, 1.5, 1.5)
	check_eq(vet_sd.state, SkirmishDirector.State.PREPARING, "prepare_delay > 0 starts in PREPARING")
	var prep_obj := vet_sd.get_objective_summary()
	check(_is_strict_ascii(String(prep_obj["title"])) and _is_strict_ascii(String(prep_obj["detail"])),
		"PREPARING objective is strict ASCII")
	vet_sd.step_skirmish(1.6)
	check_eq(vet_sd.state, SkirmishDirector.State.COMBAT, "PREPARING transitions cleanly to Wave 1 COMBAT")

	# Walk through all 4 waves at 1.5x scaling
	vet_sd.notify_enemy_defeated(&"ship")
	vet_sd.step_skirmish(6.1)
	vet_sd.notify_enemy_defeated(&"ship")
	vet_sd.notify_enemy_defeated(&"ship")
	vet_sd.step_skirmish(6.1)
	vet_sd.notify_enemy_defeated(&"ship")
	vet_sd.notify_enemy_defeated(&"ship")
	vet_sd.step_skirmish(6.1)
	vet_sd.notify_enemy_defeated(&"leviathan")
	vet_sd.notify_enemy_defeated(&"ship")

	check_eq(vet_sd.state, SkirmishDirector.State.VICTORY, "Veteran skirmish finishes in VICTORY")
	check_eq(vet_sd.total_bounty_gold, 6150, "1.5x payout scale yields 6150g total bounty")
	check_eq(vet_sd.score, 7800, "1.5x difficulty scale yields 7800 total score")
	var vet_state := vet_sd.get_state()
	check_eq(String(vet_state["state_name"]), "VICTORY", "get_state reports state_name VICTORY")

	# Verify ALL emitted wave banners, objectives, and notices are 100% strict ASCII
	for w in waves_seen:
		check(_is_strict_ascii(String(w["title"])), "Wave title strict ASCII: '%s'" % String(w["title"]))
		check(_is_strict_ascii(String(w["banner"])), "Wave banner strict ASCII: '%s'" % String(w["banner"]))
	for obj in objectives:
		check(_is_strict_ascii(String(obj["title"])), "Objective title strict ASCII: '%s'" % String(obj["title"]))
		check(_is_strict_ascii(String(obj["detail"])), "Objective detail strict ASCII: '%s'" % String(obj["detail"]))
		check(_is_strict_ascii(String(obj["progress"])), "Objective progress strict ASCII: '%s'" % String(obj["progress"]))
	for n_msg in notices:
		check(_is_strict_ascii(n_msg), "Skirmish Game.notice strict ASCII: '%s'" % n_msg)

	# ------------------------------------------------------------------
	# CrewDialogue Wave 32B Callouts across all 3 personas (strict ASCII)
	# ------------------------------------------------------------------
	var new_cats: Array[StringName] = [&"tutorial_step", &"skirmish_wave", &"skirmish_victory"]
	var personas: Array[StringName] = [&"helmsman", &"lookout", &"carpenter"]
	for persona_id in personas:
		var bank: Dictionary = CrewDialogue.LINES.get(persona_id, {})
		var speaker_name := String(CrewDialogue.get_persona(persona_id)["name"])
		for cat in new_cats:
			var pool: Array = bank.get(cat, [])
			check(pool.size() >= 2, "CrewDialogue[%s][%s] has >= 2 lines" % [String(persona_id), String(cat)])
			for raw_line in pool:
				var raw_str := String(raw_line)
				check(raw_str.length() > 10, "CrewDialogue %s/%s non-trivial" % [String(persona_id), String(cat)])
				check(_is_strict_ascii(raw_str), "CrewDialogue %s/%s strict ASCII: '%s'" % [
					String(persona_id), String(cat), raw_str,
				])
			var formatted := CrewDialogue.format_line(persona_id, cat)
			check(formatted.begins_with(speaker_name + ": "),
				"CrewDialogue.format_line(%s, %s) prefixed with speaker name" % [String(persona_id), String(cat)])
			check(_is_strict_ascii(formatted), "Formatted CrewDialogue %s/%s strict ASCII" % [
				String(persona_id), String(cat),
			])

	Game.notice.disconnect(on_notice)
	await _end()
