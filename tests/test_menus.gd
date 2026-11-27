extends TestCase
## Headless tests for Wave 32A: SessionConfig, TitleMenu (4 pages, live preview,
## Co-op Host/Join, Settings, strict ASCII), and GameHUD Pause Return-to-Title &
## Top-Left Mode Objective Card.


static func _is_strict_ascii(text: String) -> bool:
	for i in text.length():
		if text.unicode_at(i) >= 128:
			return false
	return true


func _check_tree_strict_ascii(root: Node, label_prefix: String) -> int:
	var checked := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is Label:
			var l := cur as Label
			checked += 1
			check(_is_strict_ascii(l.text), "%s Label '%s' text is strict ASCII: '%s'" % [label_prefix, l.name, l.text])
			check(_is_strict_ascii(l.tooltip_text), "%s Label '%s' tooltip is strict ASCII" % [label_prefix, l.name])
		elif cur is Button:
			var b := cur as Button
			checked += 1
			check(_is_strict_ascii(b.text), "%s Button '%s' text is strict ASCII: '%s'" % [label_prefix, b.name, b.text])
			check(_is_strict_ascii(b.tooltip_text), "%s Button '%s' tooltip is strict ASCII" % [label_prefix, b.name])
		elif cur is LineEdit:
			var le := cur as LineEdit
			checked += 1
			check(_is_strict_ascii(le.text), "%s LineEdit '%s' text is strict ASCII" % [label_prefix, le.name])
			check(_is_strict_ascii(le.placeholder_text), "%s LineEdit '%s' placeholder is strict ASCII" % [label_prefix, le.name])
		for child in cur.get_children():
			stack.append(child)
	return checked


# ---------------------------------------------------------------------------
# 1. SessionConfig: all presets, validation, profile sync & dict round-trip
# ---------------------------------------------------------------------------

func test_wave32_session_config_presets_validation_and_roundtrip() -> void:
	check_eq(SessionConfig.VALID_MODES.size(), 4, "4 valid game modes")
	check_eq(SessionConfig.OUTPOST_SPECS.size(), 3, "3 canonical outposts")
	check_eq(SessionConfig.SHIP_SPECS.size(), 2, "2 ship classes (sloop, brigantine)")
	check_eq(SessionConfig.CREW_PRESETS.size(), 4, "4 crew presets (0..3)")
	check_eq(SessionConfig.TIME_PRESETS.size(), 4, "4 time-of-day presets")
	check_eq(SessionConfig.WEATHER_PRESETS.size(), 3, "3 weather presets")
	check_eq(SessionConfig.DIFFICULTY_PRESETS.size(), 3, "3 difficulty presets")
	check_eq(SessionConfig.EMISSARY_PRESETS.size(), 4, "4 emissary presets")

	var cfg := SessionConfig.new()
	check_eq(cfg.mode, SessionConfig.MODE_ADVENTURE, "default mode is adventure")
	check_eq(cfg.ship_class, &"sloop", "default ship_class is sloop")
	check_eq(cfg.spawn_outpost_id, &"port_scoundrel", "default outpost is port_scoundrel")
	check_eq(cfg.crew_count, 3, "default crew_count is 3")
	check_eq(cfg.coop_port, Net.DEFAULT_PORT, "default coop_port matches Net.DEFAULT_PORT")

	# Verify all 4 modes have non-empty strict-ASCII labels.
	for mid: StringName in SessionConfig.VALID_MODES:
		cfg.mode = mid
		var lbl := cfg.get_mode_label()
		check(lbl != "" and _is_strict_ascii(lbl), "mode %s has strict-ASCII label '%s'" % [mid, lbl])

	# Verify all 3 real outposts resolve cleanly.
	cfg.mode = SessionConfig.MODE_ADVENTURE
	for oid: StringName in [&"port_scoundrel", &"barnacle_haven", &"galleons_reach"]:
		cfg.spawn_outpost_id = oid
		cfg.validate()
		var ospec := cfg.get_outpost_spec()
		check_eq(ospec["id"], oid, "outpost spec resolves %s" % oid)
		check(_is_strict_ascii(String(ospec["name"])) and _is_strict_ascii(String(ospec["desc"])),
			"outpost %s strings are strict ASCII" % oid)

	# Verify ship specs & crew personas 0..3.
	cfg.ship_class = &"brigantine"
	check_eq(int(cfg.get_ship_spec()["cannons"]), 4, "brigantine spec reports 4 cannons")
	cfg.ship_class = &"sloop"
	check_eq(int(cfg.get_ship_spec()["cannons"]), 2, "sloop spec reports 2 cannons")

	var expected_personas: Array[Array] = [
		[],
		[&"helmsman"],
		[&"helmsman", &"lookout"],
		[&"helmsman", &"lookout", &"carpenter"],
	]
	for cnt in 4:
		cfg.crew_count = cnt
		var personas := cfg.get_crew_personas()
		check_eq(personas.size(), cnt, "crew_count %d returns %d personas" % [cnt, cnt])
		for idx in cnt:
			check_eq(personas[idx], expected_personas[cnt][idx], "persona %d matches for count %d" % [idx, cnt])

	# Verify time, weather, difficulty, and emissary helpers.
	cfg.time_preset = &"dawn"
	check_near(cfg.get_time_of_day(), 6.35, 0.01, "dawn time is 6.35")
	cfg.time_preset = &"sunset"
	check_near(cfg.get_time_of_day(), 17.65, 0.01, "sunset time is 17.65")
	cfg.time_preset = &"night"
	check_near(cfg.get_time_of_day(), 22.4, 0.01, "night time is 22.4")

	cfg.weather_preset = &"storm"
	var wx := cfg.get_weather_params()
	check_near(float(wx["storm"]), 0.78, 0.01, "storm intensity is 0.78")
	check_near(float(wx["wind"]), 18.5, 0.01, "storm wind is 18.5")
	check_near(float(wx["cloud"]), 0.90, 0.01, "storm cloud is 0.90")

	cfg.difficulty = &"cursed"
	var diff := cfg.get_difficulty_scales()
	check_near(float(diff["enemy_scale"]), 1.35, 0.01, "cursed enemy_scale is 1.35")
	check_near(float(diff["payout_scale"]), 1.25, 0.01, "cursed payout_scale is 1.25")

	cfg.starting_emissary = &"iron_tide"
	check_eq(cfg.get_emissary_label(), "Iron Tide", "iron_tide emissary label resolves")

	# Profile defaults sync.
	var prof := Profile.new()
	prof.set_ship_name("Crimson Compass")
	prof.data["ship_class"] = "brigantine"
	cfg.apply_profile_defaults(prof)
	check_eq(cfg.ship_name, "Crimson Compass", "apply_profile_defaults pulls ship_name")
	check_eq(cfg.ship_class, &"brigantine", "apply_profile_defaults pulls ship_class")

	# Validation clamps bad inputs cleanly.
	cfg.mode = &"bogus_mode"
	cfg.ship_class = &"dreadnought"
	cfg.ship_name = "   " + char(0x2014) + "   "
	cfg.spawn_outpost_id = &"atlantis"
	cfg.crew_count = 99
	cfg.time_preset = &"noonish"
	cfg.weather_preset = &"hurricane"
	cfg.difficulty = &"impossible"
	cfg.starting_emissary = &"pirates_inc"
	cfg.coop_role = &"spectator"
	cfg.coop_address = "   "
	cfg.coop_port = 999999
	cfg.validate()
	check_eq(cfg.mode, SessionConfig.MODE_ADVENTURE, "invalid mode falls back to adventure")
	check_eq(cfg.ship_class, &"sloop", "invalid ship_class falls back to sloop")
	check_eq(cfg.ship_name, Profile.DEFAULT_SHIP_NAME, "blank/non-ASCII ship_name falls back to default")
	check_eq(cfg.spawn_outpost_id, &"port_scoundrel", "invalid outpost falls back to port_scoundrel")
	check_eq(cfg.crew_count, 3, "crew_count clamped to 3")
	check_eq(cfg.time_preset, &"morning", "invalid time falls back to morning")
	check_eq(cfg.weather_preset, &"fair", "invalid weather falls back to fair")
	check_eq(cfg.difficulty, &"standard", "invalid difficulty falls back to standard")
	check_eq(cfg.starting_emissary, &"", "invalid emissary falls back to none")
	check_eq(cfg.coop_role, &"host", "invalid coop_role falls back to host")
	check_eq(cfg.coop_address, "127.0.0.1", "blank coop_address falls back to loopback")
	check_eq(cfg.coop_port, 65535, "high coop_port clamped to 65535")

	cfg.coop_port = -5
	cfg.validate()
	check_eq(cfg.coop_port, Net.DEFAULT_PORT, "non-positive coop_port resets to Net.DEFAULT_PORT")

	# Tutorial validation enforces Port Scoundrel, fair weather, no emissary, and >= 1 crewmate.
	cfg.mode = SessionConfig.MODE_TUTORIAL
	cfg.spawn_outpost_id = &"galleons_reach"
	cfg.weather_preset = &"storm"
	cfg.starting_emissary = &"gilded_compass"
	cfg.crew_count = 0
	cfg.validate()
	check_eq(cfg.spawn_outpost_id, &"port_scoundrel", "tutorial guarantees port_scoundrel")
	check_eq(cfg.weather_preset, &"fair", "tutorial guarantees fair weather")
	check_eq(cfg.starting_emissary, &"", "tutorial clears emissary flag")
	check(cfg.crew_count >= 1, "tutorial guarantees at least Barnaby aboard")

	# Round-trip to_dict() / from_dict() & duplicate_config() independence.
	var src := SessionConfig.new()
	src.mode = SessionConfig.MODE_SKIRMISH
	src.ship_class = &"brigantine"
	src.ship_name = "Tidebreaker"
	src.spawn_outpost_id = &"barnacle_haven"
	src.crew_count = 2
	src.time_preset = &"sunset"
	src.weather_preset = &"choppy"
	src.difficulty = &"cursed"
	src.starting_emissary = &"sunken_archive"
	src.coop_role = &"join"
	src.coop_address = "192.168.1.42"
	src.coop_port = 25000
	var dict := src.to_dict()
	var restored := SessionConfig.from_dict(dict)
	check_eq(restored.mode, src.mode, "round-trip mode")
	check_eq(restored.ship_class, src.ship_class, "round-trip ship_class")
	check_eq(restored.ship_name, src.ship_name, "round-trip ship_name")
	check_eq(restored.spawn_outpost_id, src.spawn_outpost_id, "round-trip spawn_outpost_id")
	check_eq(restored.crew_count, src.crew_count, "round-trip crew_count")
	check_eq(restored.time_preset, src.time_preset, "round-trip time_preset")
	check_eq(restored.weather_preset, src.weather_preset, "round-trip weather_preset")
	check_eq(restored.difficulty, src.difficulty, "round-trip difficulty")
	check_eq(restored.starting_emissary, src.starting_emissary, "round-trip starting_emissary")
	check_eq(restored.coop_role, src.coop_role, "round-trip coop_role")
	check_eq(restored.coop_address, src.coop_address, "round-trip coop_address")
	check_eq(restored.coop_port, src.coop_port, "round-trip coop_port")

	var dup := src.duplicate_config()
	dup.ship_name = "Abyssal Dawn"
	check_eq(src.ship_name, "Tidebreaker", "duplicate_config produces an independent copy")


# ---------------------------------------------------------------------------
# 2. TitleMenu: 4 pages, live preview signals, Co-op Host/Join, Settings & ASCII
# ---------------------------------------------------------------------------

func test_wave32_title_menu_pages_live_preview_and_set_sail() -> void:
	var prev_oq := Ocean.current.quality if Ocean.current != null else Ocean.Quality.HIGH
	var settings := UserSettings.new()
	var prof := Profile.new()
	prof.add_gold(1450)
	prof.record_voyage_completed()
	prof.record_chest_sold(450)
	prof.record_chest_sold(500)
	prof.set_ship_name("Starlight Brigand")
	prof.data["ship_class"] = "sloop"

	var menu := TitleMenu.new()
	add_child(menu)
	menu.bind(settings, prof)
	await get_tree().process_frame

	check(not menu.is_open and not menu.visible, "TitleMenu starts closed")
	menu.open_menu(TitleMenu.Page.LANDING)
	check(menu.is_open and menu.visible, "open_menu reveals TitleMenu")
	check_eq(menu.current_page, TitleMenu.Page.LANDING, "starts on LANDING page")

	var ship_lbl := menu.find_child("ProfileShipLabel", true, false) as Label
	var stats_lbl := menu.find_child("ProfileStatsLabel", true, false) as Label
	check(ship_lbl != null and ship_lbl.text.contains("Starlight Brigand"),
		"ProfileShipLabel shows bound ship name (got '%s')" % (ship_lbl.text if ship_lbl != null else ""))
	check(stats_lbl != null and stats_lbl.text.contains("1450 Gold") and stats_lbl.text.contains("1 Voyages") and stats_lbl.text.contains("2 Chests Sold"),
		"ProfileStatsLabel shows gold, voyages & chests (got '%s')" % (stats_lbl.text if stats_lbl != null else ""))

	# Navigate across all 4 pages cleanly.
	menu.show_page(TitleMenu.Page.SETUP)
	check_eq(menu.current_page, TitleMenu.Page.SETUP, "navigated to SETUP")
	check((menu.find_child("SetupPage", true, false) as Control).visible, "SetupPage visible")
	check(not (menu.find_child("LandingPage", true, false) as Control).visible, "LandingPage hidden on SETUP")

	# Verify Escape returns cleanly from sub-page back to LANDING.
	var esc_ev := InputEventKey.new()
	esc_ev.physical_keycode = KEY_ESCAPE
	esc_ev.pressed = true
	menu._input(esc_ev)
	check_eq(menu.current_page, TitleMenu.Page.LANDING, "Escape returns from SETUP to LANDING")

	# Verify live preview_config_changed fires on every configurator control!
	var preview_events: Array[SessionConfig] = []
	menu.preview_config_changed.connect(func(c: SessionConfig) -> void: preview_events.append(c))

	menu.show_page(TitleMenu.Page.SETUP)
	menu.select_mode(SessionConfig.MODE_SKIRMISH)
	menu.select_ship_class(&"brigantine")
	menu.select_spawn_outpost(&"galleons_reach")
	menu.select_crew_count(2)
	menu.select_time_preset(&"sunset")
	menu.select_weather_preset(&"choppy")
	menu.select_difficulty(&"cursed")
	menu.select_starting_emissary(&"iron_tide")
	menu.set_ship_name("Emerald Cutlass")
	check_eq(preview_events.size(), 9, "preview_config_changed fired for all 9 configurator changes")
	var last_prev := preview_events[preview_events.size() - 1]
	check_eq(last_prev.mode, SessionConfig.MODE_SKIRMISH, "preview carries skirmish mode")
	check_eq(last_prev.ship_class, &"brigantine", "preview carries brigantine")
	check_eq(last_prev.spawn_outpost_id, &"galleons_reach", "preview carries galleons_reach")
	check_eq(last_prev.crew_count, 2, "preview carries crew_count 2")
	check_eq(last_prev.time_preset, &"sunset", "preview carries sunset")
	check_eq(last_prev.weather_preset, &"choppy", "preview carries choppy weather")
	check_eq(last_prev.difficulty, &"cursed", "preview carries cursed difficulty")
	check_eq(last_prev.starting_emissary, &"iron_tide", "preview carries iron_tide emissary")
	check_eq(last_prev.ship_name, "Emerald Cutlass", "preview carries updated ship name")

	# Random name dice button cycles preset ship names.
	var before_rnd := menu.config.ship_name
	var after_rnd := menu.cycle_random_ship_name()
	check(after_rnd != before_rnd and Profile.PRESET_SHIP_NAMES.has(after_rnd),
		"cycle_random_ship_name picks a new preset ship name")

	# Verify trigger_set_sail emits exact SessionConfig!
	var launched: Array[SessionConfig] = []
	menu.start_game_requested.connect(func(c: SessionConfig) -> void: launched.append(c))
	menu.trigger_set_sail()
	check_eq(launched.size(), 1, "trigger_set_sail emits start_game_requested")
	check_eq(launched[0].mode, SessionConfig.MODE_SKIRMISH, "launched config keeps mode")
	check_eq(launched[0].ship_class, &"brigantine", "launched config keeps ship_class")
	check_eq(launched[0].spawn_outpost_id, &"galleons_reach", "launched config keeps outpost")

	# Verify Tutorial mode locks Port Scoundrel & calm weather cleanly in UI.
	menu.select_mode(SessionConfig.MODE_TUTORIAL)
	var gr_btn := menu.find_child("OutpostBtn_galleons_reach", true, false) as Button
	var storm_btn := menu.find_child("WeatherBtn_storm", true, false) as Button
	var solo_btn := menu.find_child("CrewBtn_0", true, false) as Button
	var out_desc := menu.find_child("OutpostDescLabel", true, false) as Label
	check(gr_btn != null and gr_btn.disabled, "Tutorial mode disables non-Port-Scoundrel outposts")
	check(storm_btn != null and storm_btn.disabled, "Tutorial mode disables stormy weather")
	check(solo_btn != null and solo_btn.disabled, "Tutorial mode disables 0-crew so Barnaby stays aboard")
	check(out_desc != null and out_desc.text.contains("Tutorial Harbour"), "Tutorial mode notes Tutorial Harbour")

	# Verify Co-op Lobby Host & Join launch configs and live status label!
	menu.show_page(TitleMenu.Page.COOP)
	check_eq(menu.current_page, TitleMenu.Page.COOP, "navigated to COOP page")
	menu.select_ship_class(&"sloop")
	menu.select_spawn_outpost(&"barnacle_haven")
	menu.select_crew_count(1)
	var host_port_edit := menu.find_child("CoopHostPortEdit", true, false) as LineEdit
	check(host_port_edit != null, "CoopHostPortEdit exists")
	host_port_edit.text = "25101"
	menu.trigger_coop_host()
	check_eq(launched.size(), 2, "trigger_coop_host emits start_game_requested")
	check_eq(launched[1].mode, SessionConfig.MODE_COOP, "host launch sets MODE_COOP")
	check_eq(launched[1].coop_role, &"host", "host launch sets coop_role = host")
	check_eq(launched[1].coop_port, 25101, "host launch reads port from CoopHostPortEdit")
	check_eq(launched[1].spawn_outpost_id, &"barnacle_haven", "host launch carries outpost")
	check_eq(launched[1].crew_count, 1, "host launch carries AI fill crew count")

	var join_addr_edit := menu.find_child("CoopJoinAddrEdit", true, false) as LineEdit
	var join_port_edit := menu.find_child("CoopJoinPortEdit", true, false) as LineEdit
	join_addr_edit.text = "10.0.0.24"
	join_port_edit.text = "25202"
	menu.trigger_coop_join()
	check_eq(launched.size(), 3, "trigger_coop_join emits start_game_requested")
	check_eq(launched[2].mode, SessionConfig.MODE_COOP, "join launch sets MODE_COOP")
	check_eq(launched[2].coop_role, &"join", "join launch sets coop_role = join")
	check_eq(launched[2].coop_address, "10.0.0.24", "join launch reads IP from CoopJoinAddrEdit")
	check_eq(launched[2].coop_port, 25202, "join launch reads port from CoopJoinPortEdit")

	menu.set_status_message("Connection timed out - check host firewall.")
	var coop_status := menu.find_child("CoopStatusLabel", true, false) as Label
	check(coop_status != null and coop_status.text.contains("Connection timed out"),
		"set_status_message updates CoopStatusLabel")

	# Verify Settings page wires live UserSettings and emits settings_changed.
	menu.show_page(TitleMenu.Page.SETTINGS)
	check_eq(menu.current_page, TitleMenu.Page.SETTINGS, "navigated to SETTINGS page")
	var settings_hits: Array[int] = [0]
	menu.settings_changed.connect(func() -> void: settings_hits[0] += 1)
	menu.set_ocean_quality(1)
	menu.set_cloud_quality(2)
	var fov_sl := menu.find_child("SettingsSlider_fov", true, false) as HSlider
	check(fov_sl != null, "SettingsSlider_fov exists")
	fov_sl.value = 92.0
	menu.apply_and_save_settings(false)
	check_eq(int(settings.data["ocean_quality"]), 1, "Settings updates UserSettings ocean_quality")
	check_eq(int(settings.data["cloud_quality"]), 2, "Settings updates UserSettings cloud_quality")
	check_near(float(settings.data["fov"]), 92.0, 0.01, "Settings updates UserSettings fov")
	check(settings_hits[0] >= 3, "settings_changed emitted on quality/apply changes")

	# Verify Quit button emits quit_requested cleanly without exiting headless test runner!
	var quit_hits: Array[int] = [0]
	menu.quit_requested.connect(func() -> void: quit_hits[0] += 1)
	var quit_btn := menu.find_child("BtnQuit", true, false) as Button
	check(quit_btn != null, "BtnQuit exists on LandingPage")
	quit_btn.pressed.emit()
	check_eq(quit_hits[0], 1, "BtnQuit emits quit_requested safely")

	# Verify 100% strict ASCII across EVERY Label, Button, and LineEdit in TitleMenu!
	var checked_widgets := _check_tree_strict_ascii(menu, "TitleMenu")
	check(checked_widgets >= 45, "scanned all TitleMenu UI controls for strict ASCII (checked %d)" % checked_widgets)

	# Close and free cleanly (zero ObjectDB leaks, disconnects Profile signal).
	menu.close_menu()
	check(not menu.is_open and not menu.visible, "close_menu hides TitleMenu")
	menu.queue_free()
	await physics_frames(2)
	check(not is_instance_valid(menu), "TitleMenu frees cleanly on teardown")
	check_eq(prof.changed.get_connections().size(), 0, "TitleMenu disconnects profile.changed on teardown")
	if Ocean.current != null:
		Ocean.current.quality = prev_oq


# ---------------------------------------------------------------------------
# 3. GameHUD: Pause Return-to-Title button, Mode Objective Card & HUD hide/show
# ---------------------------------------------------------------------------

func test_wave32_hud_pause_return_to_title_and_mode_objective_card() -> void:
	var hud := GameHUD.new()
	hud.input_enabled = false
	add_child(hud)
	await get_tree().process_frame

	# 1. Pause menu ReturnToTitleButton closes pause and emits return_to_title_requested.
	var title_hits: Array[int] = [0]
	hud.return_to_title_requested.connect(func() -> void: title_hits[0] += 1)
	var ret_btn := hud.find_child("ReturnToTitleButton", true, false) as Button
	check(ret_btn != null, "GameHUD pause overlay includes ReturnToTitleButton")
	check_eq(ret_btn.text, "Main Menu", "ReturnToTitleButton text is strict-ASCII 'Main Menu'")

	hud.set_pause_open(true)
	check(hud.pause_open, "pause opened")
	ret_btn.pressed.emit()
	check(not hud.pause_open, "pressing ReturnToTitleButton closes pause overlay")
	check_eq(title_hits[0], 1, "pressing ReturnToTitleButton emits return_to_title_requested")

	# 2. Top-Left Mode Objective Card starts hidden inside TopLeftHUDStack with exact offset/width layout.
	var stack := hud.find_child("TopLeftHUDStack", true, false) as VBoxContainer
	var card := hud.find_child("ModeObjectiveCard", true, false) as PanelContainer
	check(stack != null and card != null, "GameHUD builds TopLeftHUDStack containing ModeObjectiveCard")
	check_eq(card.get_parent(), stack, "ModeObjectiveCard sits inside TopLeftHUDStack")
	check(not hud.is_mode_objective_visible(), "ModeObjectiveCard hidden by default")
	check_near(stack.offset_left, 24.0, 0.5, "TopLeftHUDStack offset_left is 24")
	check_near(stack.offset_top, 24.0, 0.5, "TopLeftHUDStack offset_top is 24")
	check_near(stack.offset_right - stack.offset_left, 368.0, 0.5, "TopLeftHUDStack width is 368")
	check_near(card.custom_minimum_size.x, 368.0, 0.5, "ModeObjectiveCard width is 368")

	# Show Tutorial step with Skip Step button.
	var skip_hits: Array[int] = [0]
	hud.mode_skip_requested.connect(func() -> void: skip_hits[0] += 1)
	hud.set_mode_objective(
		"MAIDEN VOYAGE",
		"Step aboard your sloop and heave the anchor capstan.",
		"Step 2/8",
		true
	)
	check(hud.is_mode_objective_visible(), "set_mode_objective reveals ModeObjectiveCard")
	check_eq(hud.get_mode_objective_title(), "MAIDEN VOYAGE", "objective title matches")
	check_eq(hud.get_mode_objective_progress(), "Step 2/8", "objective progress matches")
	check(hud.get_mode_objective_body().contains("anchor capstan"), "objective body matches")

	var skip_btn := hud.find_child("ModeSkipButton", true, false) as Button
	check(skip_btn != null and skip_btn.visible, "ModeSkipButton visible when show_skip_btn = true")
	skip_btn.pressed.emit()
	check_eq(skip_hits[0], 1, "clicking ModeSkipButton emits mode_skip_requested")
	hud.skip_tutorial_step()
	check_eq(skip_hits[0], 2, "skip_tutorial_step helper emits mode_skip_requested")

	# Automatically hides while pause is open, then restores when pause closes.
	hud.set_pause_open(true)
	check(not hud.is_mode_objective_visible(), "ModeObjectiveCard hides automatically when pause opens")
	hud.set_pause_open(false)
	check(hud.is_mode_objective_visible(), "ModeObjectiveCard reappears when pause closes")

	# set_hud_visible(false) hides gameplay HUD & ModeObjectiveCard cleanly.
	hud.set_hud_visible(false)
	check(not hud.is_hud_visible() and not hud.visible, "set_hud_visible(false) hides GameHUD")
	check(not hud.is_mode_objective_visible(), "ModeObjectiveCard hides while HUD is hidden")
	hud.set_hud_visible(true)
	check(hud.is_hud_visible() and hud.visible, "set_hud_visible(true) restores GameHUD")
	check(hud.is_mode_objective_visible(), "ModeObjectiveCard restores when HUD becomes visible")

	# Update to Skirmish live wave display without Skip button, verify ASCII, then clear.
	hud.set_mode_objective("NAVAL SKIRMISH", "Sink the Drowned Brigantine!", "Wave 3 | Score 1250", false)
	check(skip_btn != null and not skip_btn.visible, "ModeSkipButton hidden when show_skip_btn = false")
	_check_tree_strict_ascii(card, "ModeObjectiveCard")

	hud.clear_mode_objective()
	check(not hud.is_mode_objective_visible(), "clear_mode_objective hides ModeObjectiveCard")
	check_eq(hud.get_mode_objective_title(), "", "clear_mode_objective clears title")

	# Clean teardown (0 leaks).
	hud.queue_free()
	await physics_frames(2)
	check(not is_instance_valid(hud), "GameHUD frees cleanly on teardown")


# ---------------------------------------------------------------------------
# 4. End-to-End scenes/main.tscn TitleMenu, Live Preview, Modes & Return Flow
# ---------------------------------------------------------------------------

func test_wave32_main_scene_title_menu_live_preview_tutorial_skirmish_and_return() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	check(main_scene != null, "scenes/main.tscn loads cleanly")
	var main := main_scene.instantiate()
	add_child(main)
	await physics_frames(3)

	var tm := main.get(&"title_menu") as TitleMenu
	var hud := main.get(&"hud") as GameHUD
	var tut := main.get(&"tutorial_director") as TutorialDirector
	var sk := main.get(&"skirmish_director") as SkirmishDirector
	check(tm != null and hud != null and tut != null and sk != null,
		"Main constructs TitleMenu, GameHUD, TutorialDirector & SkirmishDirector")

	# Headless boot preserves direct-to-deck test compatibility by default.
	check(not tm.is_open, "Headless test boot keeps TitleMenu closed by default")

	# Open TitleMenu cleanly just as desktop first-launch does.
	main.call(&"_enter_title_menu", TitleMenu.Page.LANDING)
	await physics_frames(2)
	check(tm.is_open and tm.visible, "_enter_title_menu opens TitleMenu")
	check(not hud.is_hud_visible(), "GameHUD hides while TitleMenu is open")

	# Live 3D preview updates ship class, outpost, crew count, ship name & stern Emissary flag!
	tm.show_page(TitleMenu.Page.SETUP)
	tm.select_ship_class(&"brigantine")
	tm.select_spawn_outpost(&"barnacle_haven")
	tm.select_crew_count(1)
	tm.select_time_preset(&"sunset")
	tm.set_ship_name("Crimson Compass")
	tm.select_starting_emissary(&"gilded_compass")
	await physics_frames(2)

	var ship_now := main.get(&"player_ship") as Ship
	check(ship_now != null and ship_now.ship_class == &"brigantine",
		"Live preview swaps player ship to Brigantine")
	check_eq(ship_now.ship_name, "Crimson Compass", "Live preview updates vessel name")
	var visible_crew := 0
	var crew_arr: Array = main.get(&"crew_pawns")
	for cp in crew_arr:
		if cp is Node3D and (cp as Node3D).visible:
			visible_crew += 1
	check_eq(visible_crew, 1, "Live preview applies Duo crew roster (1 active crewmate)")

	# Launch Maiden Voyage Tutorial -> TitleMenu closes, HUD & Step 1 card appear!
	tm.select_mode(SessionConfig.MODE_TUTORIAL)
	tm.trigger_set_sail()
	await physics_frames(2)
	check(not tm.is_open, "Set Sail closes TitleMenu")
	check(hud.is_hud_visible(), "Set Sail restores GameHUD")
	check(tut.active and tut.current_step == 0, "Maiden Voyage starts TutorialDirector at Step 0")
	check(hud.is_mode_objective_visible() and hud.get_mode_objective_title().contains("Compass"),
		"ModeObjectiveCard shows Step 1 Compass objective")

	# Pause -> Return to Main Menu cleanly stops Tutorial and reopens TitleMenu!
	hud.return_to_title_requested.emit()
	await physics_frames(2)
	check(not tut.active, "Return to Main Menu stops TutorialDirector")
	check(tm.is_open, "Return to Main Menu re-opens TitleMenu")

	# Launch Naval Skirmish -> ship relocates to open sea & SkirmishDirector starts Wave 1!
	tm.show_page(TitleMenu.Page.SETUP)
	tm.select_mode(SessionConfig.MODE_SKIRMISH)
	tm.select_crew_count(3)
	tm.trigger_set_sail()
	await physics_frames(2)
	check(not tm.is_open and hud.is_hud_visible(), "Skirmish Set Sail enters gameplay")
	check(sk.state != SkirmishDirector.State.IDLE, "Naval Skirmish activates SkirmishDirector")

	# Clean zero-leak teardown.
	main.queue_free()
	await physics_frames(4)
	check(not is_instance_valid(main), "Main scene tears down cleanly after Wave 32 flow")


# ---------------------------------------------------------------------------
# 5. Pass Q6A: Sailing Rudder Bar, Full-Wind Gold Highlight & Strict-ASCII Controls
# ---------------------------------------------------------------------------

func test_q6a_sailing_rudder_bar_and_strict_ascii_controls() -> void:
	var saved_weather := Weather.get_state()
	var saved_amp := Sea.amp_scale
	Net.start_single_player()
	Weather.day_length_seconds = 0.0
	Weather.lightning_enabled = false
	Weather.set_weather(0.0, 10.0, 0.0)
	Sea.amp_scale = 0.0

	var root := Node3D.new()
	add_child(root)

	var sloop_scene: PackedScene = load("res://src/ship/sloop.tscn")
	var pawn_scene: PackedScene = load("res://src/characters/pawn.tscn")
	var ship := sloop_scene.instantiate() as Ship
	ship.enable_effects = false
	ship.start_anchored = true
	root.add_child(ship)
	ship.global_position = Vector3.ZERO

	var captain := pawn_scene.instantiate() as Pawn
	root.add_child(captain)
	captain.board(ship, ship.ship_point(Vector3(0.0, 2.02, 4.1)))

	var hud := GameHUD.new()
	hud.input_enabled = false
	root.add_child(hud)
	hud.bind(captain, null, null, null, ship, null, null)
	await physics_frames(3)

	# 1. Pure rudder bar formatter verifies centered, port, and starboard strict ASCII output!
	check_eq(GameHUD.format_rudder_bar(0.0), "[---|---] CTR", "centered helm renders [---|---] CTR")
	check_eq(GameHUD.format_rudder_bar(-0.45), "[<--|---] PORT 45%", "45% port helm renders [<--|---] PORT 45%")
	check_eq(GameHUD.format_rudder_bar(-1.0), "[<<<|---] PORT 100%", "full port helm renders [<<<|---] PORT 100%")
	check_eq(GameHUD.format_rudder_bar(0.45), "[---|-->] STBD 45%", "45% starboard helm renders [---|-->] STBD 45%")
	check_eq(GameHUD.format_rudder_bar(1.0), "[---|>>>] STBD 100%", "full starboard helm renders [---|>>>] STBD 100%")

	# 2. Live SailingTrimPill renders rudder bar across sailing stations (helm & anchor)
	#    and highlights border warmly in nautical gold on Full-Billow Wind Catch!
	var helm_st := ship.get_station(&"helm")
	check(helm_st != null and captain.enter_station(helm_st), "captain occupies Station_Helm")

	ship.anchor_down = false
	ship.sail_set = 0.90
	ship.sail_trim = ship.ideal_sail_trim()
	ship.helm = 0.0
	hud._process(0.05)
	var ctr_txt := hud.get_sailing_telemetry_text()
	check(hud.is_sailing_telemetry_visible(), "SailingTrimPill visible at helm")
	check(ctr_txt.contains("[---|---]") and ctr_txt.contains("CTR") and ctr_txt.ends_with("kt  |  FULL WIND"),
		"centered full-wind pill shows rudder bar + FULL WIND (got '%s')" % ctr_txt)
	check(hud.is_sailing_full_wind_highlighted(), "Full-Billow Wind Catch activates nautical gold highlight")
	check(hud.get_sailing_pill_border_color().is_equal_approx(HudIcons.COL_GOLD),
		"Full-Billow sailing pill border gleams in HudIcons.COL_GOLD")
	check(_is_strict_ascii(ctr_txt), "centered sailing pill text is strict ASCII")

	ship.helm = -0.45
	hud._process(0.05)
	var port_txt := hud.get_sailing_telemetry_text()
	check(port_txt.contains("[<--|---]") and port_txt.contains("PORT 45%"),
		"port helm updates live sailing pill rudder bar (got '%s')" % port_txt)
	check(_is_strict_ascii(port_txt), "port sailing pill text is strict ASCII")

	ship.helm = 1.0
	ship.sail_trim = wrapf(ship.ideal_sail_trim() + 1.2, -PI, PI)
	hud._process(0.05)
	var stbd_txt := hud.get_sailing_telemetry_text()
	check(stbd_txt.contains("[---|>>>]") and stbd_txt.contains("STBD 100%") and stbd_txt.ends_with("kt  |  TRIM SAILS"),
		"starboard helm & misaligned sail show STBD 100%% + TRIM SAILS (got '%s')" % stbd_txt)
	check(not hud.is_sailing_full_wind_highlighted(), "misaligned sails clear nautical gold highlight")
	check(_is_strict_ascii(stbd_txt), "starboard sailing pill text is strict ASCII")
	captain.leave_station()

	# Also visible when manning the anchor capstan!
	var anchor_st := ship.get_station(&"anchor")
	if anchor_st != null:
		check(captain.enter_station(anchor_st), "captain occupies Station_Anchor")
		hud._process(0.05)
		check(hud.is_sailing_telemetry_visible(), "SailingTrimPill also displays while manning anchor station")
		captain.leave_station()

	# 3. Verify complete strict-ASCII controls documentation on GameHUD Pause Overlay AND TitleMenu!
	var required_tokens: Array[String] = [
		"[Q / Tab]",
		"[G] Crew Orders",
		"[1-6] Quick Slots",
		"[F] Use / Leave Stations & Quick-Drop Anchor",
		"[Hold W] Heave Anchor",
		"[S / W] Lower / Raise Sails",
		"[A / D] Steer Wheel & Trim Sails",
		"[RMB] Center Helm",
		"[LMB / RMB] Slash / Aim / Block / Climb in Cannon",
		"[R] Swap Cannon Shot (6 Types)",
		"[T] Speaking Trumpet Crew Recall",
		"[B] Shipwright (at Outpost)",
		"[Esc] Pause",
	]

	hud.set_pause_open(true)
	var ctrl_strip := hud.find_child("CaptainControlsStrip", true, false) as VBoxContainer
	check(ctrl_strip != null and ctrl_strip.get_child_count() == 2,
		"GameHUD pause overlay keeps compact 2-group CaptainControlsStrip")
	var hud_controls_joined := ""
	if ctrl_strip != null:
		for ch in ctrl_strip.get_children():
			if ch is Label:
				hud_controls_joined += (ch as Label).text + "\n"
	for tok in required_tokens:
		check(hud_controls_joined.contains(tok),
			"GameHUD Pause Controls documents '%s'" % tok)
	var hud_widgets := _check_tree_strict_ascii(hud, "GameHUD")
	check(hud_widgets >= 20, "scanned all GameHUD widgets for strict ASCII (checked %d)" % hud_widgets)
	hud.set_pause_open(false)

	var menu := TitleMenu.new()
	add_child(menu)
	await get_tree().process_frame
	menu.open_menu(TitleMenu.Page.SETTINGS)
	var title_ctrl_list := menu.find_child("TitleControlsList", true, false) as VBoxContainer
	check(title_ctrl_list != null, "TitleMenu Settings includes TitleControlsList")
	var menu_controls_joined := ""
	if title_ctrl_list != null:
		for ch in title_ctrl_list.get_children():
			if ch is Label:
				menu_controls_joined += (ch as Label).text + "\n"
	for tok in required_tokens:
		check(menu_controls_joined.contains(tok),
			"TitleMenu Settings Controls documents '%s'" % tok)
	var menu_widgets := _check_tree_strict_ascii(menu, "TitleMenu")
	check(menu_widgets >= 45, "scanned all TitleMenu widgets for strict ASCII (checked %d)" % menu_widgets)

	# Clean zero-leak teardown.
	menu.close_menu()
	menu.queue_free()
	root.queue_free()
	await physics_frames(3)
	check(not is_instance_valid(menu) and not is_instance_valid(root), "Q6A test nodes free cleanly with 0 leaks")
	Weather.apply_state(saved_weather)
	Sea.amp_scale = saved_amp


# ---------------------------------------------------------------------------
# 6. Q7B: Live Diegetic AI Crew Roster Card & Shipwright Renown Bars / Specs
# ---------------------------------------------------------------------------

func test_q7b_hud_crew_roster_and_shipwright_specs() -> void:
	Net.start_single_player()
	var root := Node3D.new()
	add_child(root)

	var hud := GameHUD.new()
	hud.input_enabled = false
	root.add_child(hud)
	await get_tree().process_frame

	# 1. CrewRosterCard starts completely hidden when solo (0 AI crew).
	var stack := hud.find_child("TopLeftHUDStack", true, false) as VBoxContainer
	var obj_card := hud.find_child("ModeObjectiveCard", true, false) as PanelContainer
	var roster_card := hud.find_child("CrewRosterCard", true, false) as PanelContainer
	check(stack != null and obj_card != null and roster_card != null,
		"GameHUD mounts TopLeftHUDStack, ModeObjectiveCard, and CrewRosterCard")
	check_eq(obj_card.get_parent(), stack, "ModeObjectiveCard lives inside TopLeftHUDStack")
	check_eq(roster_card.get_parent(), stack, "CrewRosterCard lives inside TopLeftHUDStack")
	check(not hud.is_crew_roster_visible(), "CrewRosterCard hidden with 0 AI crew")
	check_eq(hud.get_crew_roster_entries().size(), 0, "0 crew roster entries when solo")

	# 2. Register 3 AI CrewBrains -> CrewRosterCard becomes visible immediately with strict-ASCII names,
	#    task badges, and accurate HP ratios!
	var pawn_scene := load("res://src/characters/pawn.tscn") as PackedScene
	check(pawn_scene != null, "pawn.tscn loads for Q7B crew roster test")
	var brains: Array[CrewBrain] = []
	var personas: Array[StringName] = [&"helmsman", &"lookout", &"carpenter"]
	var hp_vals: Array[float] = [100.0, 45.0, 20.0]
	for i in personas.size():
		var p := pawn_scene.instantiate() as Pawn
		p.max_health = 100.0
		p.set_physics_process(false)
		var cb := CrewBrain.new()
		cb.persona_id = personas[i]
		cb.set_physics_process(false)
		p.add_child(cb)
		root.add_child(p)
		p.health = hp_vals[i]
		brains.append(cb)

	brains[0].current_task = &"helm"
	brains[0].current_order = &"helm"
	brains[1].current_task = &"cannon"
	brains[1].current_order = &"cannons"
	brains[2].current_task = &"repair"
	brains[2].current_order = &"repair"

	for cb in brains:
		hud.register_crew_brain(cb)

	check(hud.is_crew_roster_visible(), "CrewRosterCard becomes visible immediately when AI crew registered")
	var entries := hud.get_crew_roster_entries()
	check_eq(entries.size(), 3, "CrewRosterCard tracks all 3 AI crewmates")
	check_eq(String(entries[0]["name"]), "Barnaby", "crew row 0 name is strict-ASCII Barnaby")
	check_eq(entries[0]["task"], &"helm", "crew row 0 task is &'helm'")
	check_eq(String(entries[0]["task_label"]), "HELM", "crew row 0 badge maps &'helm' -> HELM")
	check_near(float(entries[0]["hp_ratio"]), 1.0, 0.005, "crew row 0 HP ratio is 1.0")
	check_eq(entries[0]["order"], &"helm", "crew row 0 order is &'helm'")

	check_eq(String(entries[1]["name"]), "Maren", "crew row 1 name is strict-ASCII Maren")
	check_eq(String(entries[1]["task_label"]), "GUNNER", "crew row 1 badge maps &'cannon' -> GUNNER")
	check_near(float(entries[1]["hp_ratio"]), 0.45, 0.005, "crew row 1 HP ratio is 0.45")

	check_eq(String(entries[2]["name"]), "Pip", "crew row 2 name is strict-ASCII Pip")
	check_eq(String(entries[2]["task_label"]), "REPAIR", "crew row 2 badge maps &'repair' -> REPAIR")
	check_near(float(entries[2]["hp_ratio"]), 0.20, 0.005, "crew row 2 HP ratio is 0.20")

	# Verify dynamic live updates across throttled 0.20 s refresh ticks when tasks & HP change!
	brains[0].current_task = &"trim_sails"
	brains[1].current_task = &"bail"
	brains[2].current_task = &"douse_fire"
	brains[2].pawn.health = 75.0
	hud._process(0.25)
	var updated := hud.get_crew_roster_entries()
	check_eq(String(updated[0]["task_label"]), "SAILS", "dynamic update maps &'trim_sails' -> SAILS")
	check_eq(String(updated[1]["task_label"]), "BAIL", "dynamic update maps &'bail' -> BAIL")
	check_eq(String(updated[2]["task_label"]), "FIRE", "dynamic update maps &'douse_fire' -> FIRE")
	check_near(float(updated[2]["hp_ratio"]), 0.75, 0.005, "dynamic update reflects healed HP ratio 0.75")

	# Verify Pause hides CrewRosterCard and closing Pause restores it cleanly.
	hud.set_pause_open(true)
	check(not hud.is_crew_roster_visible(), "CrewRosterCard hides automatically while Pause overlay is open")
	hud.set_pause_open(false)
	check(hud.is_crew_roster_visible(), "CrewRosterCard restores cleanly when Pause closes")

	# Verify coexistence with ModeObjectiveCard inside TopLeftHUDStack with zero overlap!
	hud.set_mode_objective("MAIDEN VOYAGE", "Trim sails into the wind.", "Step 3/8", false)
	await get_tree().process_frame
	check(hud.is_mode_objective_visible() and hud.is_crew_roster_visible(),
		"ModeObjectiveCard and CrewRosterCard coexist visibly inside TopLeftHUDStack")
	check(obj_card.get_index() < roster_card.get_index(),
		"ModeObjectiveCard sits above CrewRosterCard inside TopLeftHUDStack")
	check_eq(stack.get_theme_constant("separation"), 8,
		"TopLeftHUDStack keeps 8 px vertical separation between cards")
	var obj_min := obj_card.get_combined_minimum_size()
	var roster_min := roster_card.get_combined_minimum_size()
	var stack_min := stack.get_combined_minimum_size()
	check(obj_min.y > 20.0 and roster_min.y > 40.0 and stack_min.y >= obj_min.y + roster_min.y + 7.5,
		"TopLeftHUDStack reserves full non-overlapping height for both cards (obj=%.1f, roster=%.1f, stack=%.1f)" % [
			obj_min.y, roster_min.y, stack_min.y
		])
	if obj_card.position.is_finite() and roster_card.position.is_finite():
		check(roster_card.position.y >= obj_card.position.y + obj_card.size.y - 0.5,
			"CrewRosterCard stacks cleanly below ModeObjectiveCard with zero overlap")
	var hud_ascii_count := _check_tree_strict_ascii(hud, "Q7B_GameHUD")
	check(hud_ascii_count >= 24, "verified strict ASCII across GameHUD & CrewRosterCard (checked %d)" % hud_ascii_count)

	# 3. ShipwrightMenu: 3 brass-framed CompanyProgress_* bars ([0..1]) & ShipClassSpecsLabel!
	var saved_profile: Profile = Game.profile
	var test_prof := Profile.new()
	test_prof.data["gold"] = 1200
	test_prof.data["ship_class"] = "sloop"
	test_prof.data["renown"] = {
		"gilded_compass": 50,   # Rank 1 (0..100) -> 0.50
		"iron_tide": 200,       # Rank 2 (100..300) -> 0.50
		"sunken_archive": 25,   # Rank 1 (0..100) -> 0.25
	}
	Game.profile = test_prof

	var sw := ShipwrightMenu.new()
	root.add_child(sw)
	await get_tree().process_frame
	sw.open_menu(ShipwrightMenu.TAB_SHIPWRIGHT)
	await get_tree().process_frame

	var expected_fracs := {
		&"gilded_compass": 0.50,
		&"iron_tide": 0.50,
		&"sunken_archive": 0.25,
	}
	for comp_id: StringName in [&"gilded_compass", &"iron_tide", &"sunken_archive"]:
		var bar := sw.find_child("CompanyProgress_" + String(comp_id), true, false) as ProgressBar
		check(bar != null, "ShipwrightMenu renders CompanyProgress_%s ProgressBar" % String(comp_id))
		if bar != null:
			check(bar.value >= 0.0 and bar.value <= 1.0,
				"CompanyProgress_%s value is in [0..1] (got %.3f)" % [String(comp_id), bar.value])
			check_near(bar.value, float(expected_fracs[comp_id]), 0.01,
				"CompanyProgress_%s matches rank progress ratio (got %.3f)" % [String(comp_id), bar.value])
			check(not bar.show_percentage, "CompanyProgress_%s hides percentage text" % String(comp_id))
			check_near(bar.custom_minimum_size.y, 9.0, 0.5, "CompanyProgress_%s height is 9 px" % String(comp_id))

	var sloop_specs := sw.find_child("ShipClassSpecsLabel", true, false) as Label
	check(sloop_specs != null, "ShipwrightMenu renders ShipClassSpecsLabel for Sloop")
	if sloop_specs != null:
		check_eq(sloop_specs.text, "Specs: ~10.9 kt Top Speed | 2 Cannons | 1-2 Crew | Agile Helm & Fast Tack",
			"Sloop ShipClassSpecsLabel shows exact Q1A Sloop specs")

	sw.select_ship_class(&"brigantine")
	await get_tree().process_frame
	var brig_specs := sw.find_child("ShipClassSpecsLabel", true, false) as Label
	check(brig_specs != null, "ShipwrightMenu renders ShipClassSpecsLabel after switching to Brigantine")
	if brig_specs != null:
		check_eq(brig_specs.text, "Specs: ~13.7 kt Top Speed | 4 Cannons | 2-4 Crew | Heavy Broadside & Momentum",
			"Brigantine ShipClassSpecsLabel shows exact Q1A Brigantine specs")

	var sw_ascii_count := _check_tree_strict_ascii(sw, "Q7B_ShipwrightMenu")
	check(sw_ascii_count >= 35, "verified 100%% strict ASCII across entire ShipwrightMenu tree (checked %d)" % sw_ascii_count)

	# 4. Clean zero-leak teardown!
	sw.close_menu()
	Game.profile = saved_profile
	Game.save()
	root.queue_free()
	await physics_frames(3)
	check(not is_instance_valid(root) and not is_instance_valid(hud) and not is_instance_valid(sw),
		"Q7B HUD & ShipwrightMenu test nodes free cleanly with 0 leaks")


# ---------------------------------------------------------------------------
# 7. Q11B: Landing Harbour Vista Quick-Preview Strip & Live 3D Camera Framing
# ---------------------------------------------------------------------------

func test_q11b_title_landing_harbour_vista_preview_and_camera_framing() -> void:
	var saved_weather := Weather.get_state()
	var saved_amp := Sea.amp_scale
	Net.start_single_player()

	var main_scene := load("res://scenes/main.tscn") as PackedScene
	check(main_scene != null, "scenes/main.tscn loads cleanly for Q11B")
	var main := main_scene.instantiate()
	add_child(main)
	await physics_frames(3)

	var tm := main.get(&"title_menu") as TitleMenu
	check(tm != null, "Main mounts TitleMenu for Q11B")
	main.call(&"_enter_title_menu", TitleMenu.Page.LANDING)
	await physics_frames(2)

	# 1. Verify HARBOUR_VISTAS catalog, Landing layout order, and zero-overflow 1280x720 height budget.
	check_eq(TitleMenu.HARBOUR_VISTAS.size(), 4, "TitleMenu defines 4 Harbour Vista quick-preview presets")
	var landing_col := tm.find_child("LandingColumn", true, false) as VBoxContainer
	var action_stack := tm.find_child("MainActionStack", true, false) as Control
	var vista_bar := tm.find_child("HarbourVistaBar", true, false) as Control
	var status_lbl := tm.find_child("LandingStatusLabel", true, false) as Control
	check(landing_col != null and action_stack != null and vista_bar != null and status_lbl != null,
		"LandingPage mounts MainActionStack, HarbourVistaBar, and LandingStatusLabel")
	if action_stack != null and vista_bar != null and status_lbl != null:
		check(action_stack.get_index() < vista_bar.get_index() and vista_bar.get_index() < status_lbl.get_index(),
			"HarbourVistaBar sits cleanly between MainActionStack and LandingStatusLabel")
	if landing_col != null:
		var col_min := landing_col.get_combined_minimum_size()
		check(col_min.y <= 674.0,
			"LandingColumn minimum height fits cleanly inside 1280x720 without overflow (min_y=%.1f)" % col_min.y)

	# 2. Verify all 4 Landing Harbour Vista buttons exist, have strict ASCII labels, emit preview_config_changed,
	#    update config.time_preset & config.weather_preset, and immediately transform Weather in main.tscn!
	var preview_events: Array[SessionConfig] = []
	tm.preview_config_changed.connect(func(c: SessionConfig) -> void: preview_events.append(c))

	var expected_vistas: Array[Dictionary] = [
		{"id": &"morning", "label": "Morning", "time": &"morning", "wx": &"fair", "tod": 10.2, "storm_min": 0.0, "storm_max": 0.15},
		{"id": &"sunset", "label": "Sunset", "time": &"sunset", "wx": &"fair", "tod": 17.65, "storm_min": 0.0, "storm_max": 0.15},
		{"id": &"twilight", "label": "Twilight", "time": &"night", "wx": &"fair", "tod": 22.4, "storm_min": 0.0, "storm_max": 0.15},
		{"id": &"storm", "label": "Storm", "time": &"sunset", "wx": &"storm", "tod": 17.65, "storm_min": 0.70, "storm_max": 0.90},
	]
	for idx in expected_vistas.size():
		var spec := expected_vistas[idx]
		var vid: StringName = spec["id"]
		var vbtn := tm.find_child("VistaBtn_" + String(vid), true, false) as Button
		check(vbtn != null, "Landing Harbour Vista button VistaBtn_%s exists" % String(vid))
		if vbtn != null:
			check_eq(vbtn.text, String(spec["label"]), "VistaBtn_%s label matches '%s'" % [String(vid), String(spec["label"])])
			check(_is_strict_ascii(vbtn.text) and _is_strict_ascii(vbtn.tooltip_text),
				"VistaBtn_%s text and tooltip are strict ASCII" % String(vid))
			vbtn.pressed.emit()
		else:
			tm.select_harbour_vista(vid)
		check_eq(tm.config.time_preset, spec["time"], "vista %s sets time_preset=%s" % [String(vid), String(spec["time"])])
		check_eq(tm.config.weather_preset, spec["wx"], "vista %s sets weather_preset=%s" % [String(vid), String(spec["wx"])])
		check_eq(tm.get_active_harbour_vista(), vid, "get_active_harbour_vista() reports %s" % String(vid))
		check_near(Weather.time_of_day, float(spec["tod"]), 0.05,
			"vista %s updates live Weather.time_of_day to %.2f (got %.2f)" % [String(vid), float(spec["tod"]), Weather.time_of_day])
		check(Weather.storminess >= float(spec["storm_min"]) and Weather.storminess <= float(spec["storm_max"]),
			"vista %s updates live Weather.storminess into [%.2f..%.2f] (got %.2f)" % [
				String(vid), float(spec["storm_min"]), float(spec["storm_max"]), Weather.storminess
			])
	check_eq(preview_events.size(), 4, "clicking all 4 Harbour Vista pills emits preview_config_changed 4 times")

	# Manual customization on Setup reports &"custom" from get_active_harbour_vista().
	tm.select_time_preset(&"dawn")
	tm.select_weather_preset(&"choppy")
	check_eq(tm.get_active_harbour_vista(), &"custom",
		"manual Setup time/weather combo reports &'custom' vista")

	# 3. Verify optional vista= hero shot override and deterministic morning+fair default!
	main.set(&"_cli_vista", &"twilight")
	main.set(&"_cli_time", NAN)
	main.call(&"_apply_hero_shot", "title_menu")
	check_eq(tm.get_active_harbour_vista(), &"twilight", "title_menu hero shot honours vista=twilight")
	check_near(Weather.time_of_day, 22.4, 0.05, "title_menu hero shot with vista=twilight sets night time 22.4")

	main.set(&"_cli_vista", &"")
	main.set(&"_cli_time", NAN)
	main.call(&"_apply_hero_shot", "title_menu")
	check_eq(tm.get_active_harbour_vista(), &"morning", "title_menu hero shot defaults cleanly to morning vista")
	check_near(Weather.time_of_day, 10.2, 0.05, "title_menu hero shot preserves deterministic 10.2 morning default")
	check_near(Weather.storminess, 0.06, 0.02, "title_menu hero shot preserves deterministic 0.06 fair default")

	# 4. Verify refined unobstructed _update_title_camera() framing for Sloop and Brigantine!
	var title_cam := main.get(&"_title_camera") as Camera3D
	check(title_cam != null and title_cam.current, "TitleMenuCamera is mounted and active on TitleMenu")

	tm.select_ship_class(&"sloop")
	await physics_frames(2)
	main.set(&"_title_orbit_time", 0.0)
	main.call(&"_update_title_camera")
	var sloop_ship := main.get(&"player_ship") as Ship
	check(sloop_ship != null and sloop_ship.ship_class == &"sloop", "preview swapped cleanly to Sloop")
	if title_cam != null and sloop_ship != null:
		var s_off := title_cam.global_position - sloop_ship.global_position
		var s_horiz := Vector2(s_off.x, s_off.z).length()
		var s_sea_y := Sea.height(title_cam.global_position.x, title_cam.global_position.z)
		check(s_horiz >= 24.0, "Sloop title camera horizontal distance >= 24.0 m (got %.2f m)" % s_horiz)
		check(title_cam.global_position.y >= s_sea_y + 3.35,
			"Sloop title camera sits well above sea surface (cam_y=%.2f, sea_y=%.2f)" % [title_cam.global_position.y, s_sea_y])
		var to_sloop := (sloop_ship.global_position - title_cam.global_position).normalized()
		var cam_fwd := -title_cam.global_basis.z
		var cam_right := title_cam.global_basis.x
		check(cam_fwd.dot(to_sloop) > 0.80, "Sloop title camera looks smoothly toward vessel & harbour")
		check(cam_right.dot(to_sloop) > 0.10, "Sloop vessel frames cleanly to the right of left-anchored TitleMenu")

	tm.select_ship_class(&"brigantine")
	await physics_frames(2)
	main.set(&"_title_orbit_time", 0.0)
	main.call(&"_update_title_camera")
	var brig_ship := main.get(&"player_ship") as Ship
	check(brig_ship != null and brig_ship.ship_class == &"brigantine", "preview swapped cleanly to Brigantine")
	if title_cam != null and brig_ship != null:
		var b_off := title_cam.global_position - brig_ship.global_position
		var b_horiz := Vector2(b_off.x, b_off.z).length()
		var b_sea_y := Sea.height(title_cam.global_position.x, title_cam.global_position.z)
		check(b_horiz >= 30.0, "Brigantine title camera horizontal distance >= 30.0 m (got %.2f m)" % b_horiz)
		check(title_cam.global_position.y >= b_sea_y + 3.35,
			"Brigantine title camera sits well above sea surface (cam_y=%.2f, sea_y=%.2f)" % [title_cam.global_position.y, b_sea_y])
		var to_brig := (brig_ship.global_position - title_cam.global_position).normalized()
		var b_fwd := -title_cam.global_basis.z
		var b_right := title_cam.global_basis.x
		check(b_fwd.dot(to_brig) > 0.80, "Brigantine title camera looks smoothly toward vessel & harbour")
		check(b_right.dot(to_brig) > 0.10, "Brigantine vessel frames cleanly to the right of left-anchored TitleMenu")

	# 5. Strict ASCII scan across entire TitleMenu tree including new Harbour Vista strip.
	var checked_ascii := _check_tree_strict_ascii(tm, "Q11B_TitleMenu")
	check(checked_ascii >= 50, "verified 100%% strict ASCII across Q11B TitleMenu (checked %d)" % checked_ascii)

	# 6. Clean zero-leak teardown.
	main.queue_free()
	await physics_frames(4)
	check(not is_instance_valid(main), "Q11B main scene frees cleanly with 0 leaks")
	Weather.apply_state(saved_weather)
	Sea.amp_scale = saved_amp


# ---------------------------------------------------------------------------
# 8. Q19B: Animated Gold Counter Roll-Up & Floating Brass GoldDeltaToast
# ---------------------------------------------------------------------------

func test_q19b_hud_animated_gold_rollup_and_delta_toast() -> void:
	var hud := GameHUD.new()
	hud.input_enabled = false
	add_child(hud)
	await get_tree().process_frame
	hud.set_process(false)

	var toast := hud.get_gold_delta_toast_label()
	check(toast != null and toast.name == "GoldDeltaToast",
		"GameHUD mounts GoldDeltaToast and exposes get_gold_delta_toast_label()")
	var gold_lbl := hud.find_child("GoldLabel", true, false) as Label
	check(gold_lbl != null, "GameHUD mounts GoldLabel inside VoyageWhisper")

	# 1. Initial set_gold(500) snaps cleanly with ZERO phantom toast.
	hud.set_gold(500)
	check_eq(hud.get_target_gold(), 500, "initial set_gold(500) sets target gold immediately")
	check_eq(hud.get_displayed_gold(), 500, "initial set_gold(500) snaps displayed gold immediately")
	if gold_lbl != null:
		check_eq(gold_lbl.text, "500 Gold", "initial set_gold(500) updates GoldLabel immediately")
	check(toast != null and not toast.visible, "initial set_gold(500) leaves GoldDeltaToast hidden (no phantom toast)")
	check_eq(hud.get_gold_delta_toast_text(), "", "initial set_gold(500) leaves toast text empty")

	# 2. Subsequent payout set_gold(850) triggers "+350 Gold" warm gilded toast & ease-out cubic roll-up!
	hud.set_gold(850)
	check_eq(hud.get_target_gold(), 850, "set_gold(850) updates get_target_gold() immediately")
	check_eq(hud.get_displayed_gold(), 500, "set_gold(850) begins smooth roll-up from 500")
	check_eq(hud.get_gold_delta_toast_text(), "+350 Gold", "set_gold(850) triggers '+350 Gold' delta toast")
	check(_is_strict_ascii(hud.get_gold_delta_toast_text()), "gain toast text is strict ASCII")
	if toast != null:
		check(toast.visible, "GoldDeltaToast becomes visible on gold gain")
		check_eq(toast.text, "+350 Gold", "GoldDeltaToast Label text matches '+350 Gold'")
		check(toast.get_theme_color("font_color").is_equal_approx(Color(1.0, 0.86, 0.34, 1.0)),
			"gain toast renders in warm gilded gold Color(1.0, 0.86, 0.34)")
	var start_top := toast.offset_top if toast != null else 0.0

	hud.step_gold_animation(0.20)
	var mid_gold := hud.get_displayed_gold()
	check(mid_gold > 500 and mid_gold < 850,
		"step_gold_animation(0.20) rolls displayed gold smoothly between 500 and 850 (got %d)" % mid_gold)
	if gold_lbl != null:
		check_eq(gold_lbl.text, "%d Gold" % mid_gold, "GoldLabel tracks rolling displayed gold cleanly")
	if toast != null:
		check(toast.offset_top < start_top - 1.5,
			"GoldDeltaToast floats gently upward during animation (%.2f -> %.2f)" % [start_top, toast.offset_top])

	hud.step_gold_animation(0.50)
	check_eq(hud.get_displayed_gold(), 850, "gold roll-up settles cleanly at 850 after 0.70 s")
	if gold_lbl != null:
		check_eq(gold_lbl.text, "850 Gold", "GoldLabel settles on '850 Gold'")

	# 3. Rapid back-to-back payout within 0.85 s (elapsed = 0.70 s) accumulates "+350" + "+150" -> "+500 Gold"!
	hud.set_gold(1000)
	check_eq(hud.get_target_gold(), 1000, "rapid payout updates target gold immediately to 1000")
	check_eq(hud.get_gold_delta_toast_text(), "+500 Gold",
		"rapid payout within 0.85 s accumulates into '+500 Gold' running total")
	if toast != null:
		check(toast.visible and toast.text == "+500 Gold", "accumulated toast label displays '+500 Gold'")
	hud.step_gold_animation(0.65)
	check_eq(hud.get_displayed_gold(), 1000, "accumulated payout rolls cleanly to 1000")

	# 4. Spend set_gold(800) switches cleanly to coral-crimson "-200 Gold" and rolls down 1000 -> 800!
	hud.set_gold(800)
	check_eq(hud.get_target_gold(), 800, "spend updates target gold immediately to 800")
	check_eq(hud.get_gold_delta_toast_text(), "-200 Gold", "spend triggers '-200 Gold' strict-ASCII toast")
	check(_is_strict_ascii(hud.get_gold_delta_toast_text()), "spend toast text is strict ASCII")
	if toast != null:
		check(toast.visible and toast.text == "-200 Gold", "GoldDeltaToast displays '-200 Gold' on spend")
		check(toast.get_theme_color("font_color").is_equal_approx(Color(0.95, 0.42, 0.36, 1.0)),
			"spend toast renders in soft coral-crimson Color(0.95, 0.42, 0.36)")

	hud.step_gold_animation(0.25)
	var mid_spend := hud.get_displayed_gold()
	check(mid_spend < 1000 and mid_spend > 800,
		"spend smoothly rolls displayed gold downward (got %d)" % mid_spend)
	hud.step_gold_animation(0.95)
	check_eq(hud.get_displayed_gold(), 800, "spend finishes rolling cleanly at 800")
	if toast != null:
		check(toast.visible and toast.modulate.a > 0.05 and toast.modulate.a < 0.95,
			"toast fades smoothly at 1.20 s (alpha=%.3f)" % toast.modulate.a)
		check(toast.offset_top <= start_top - 12.0,
			"toast floats ~14 px upward across lifetime (delta=%.2f px)" % (start_top - toast.offset_top))

	# 5. Advancing past 1.65 s (1.8 s total) hides toast cleanly with zero residue.
	hud.step_gold_animation(0.60)
	check(toast != null and not toast.visible, "GoldDeltaToast hides cleanly after 1.8 s")
	check_near(toast.modulate.a if toast != null else -1.0, 0.0, 0.001, "GoldDeltaToast alpha reaches 0.0")
	check_eq(hud.get_gold_delta_toast_text(), "", "get_gold_delta_toast_text() clears cleanly after fade")

	var checked_ascii := _check_tree_strict_ascii(hud, "Q19B_GameHUD")
	check(checked_ascii >= 20, "verified 100%% strict ASCII across Q19B GameHUD (checked %d)" % checked_ascii)

	# 6. Clean zero-leak teardown.
	hud.queue_free()
	await physics_frames(2)
	check(not is_instance_valid(hud), "Q19B GameHUD frees cleanly with 0 leaks")


# ---------------------------------------------------------------------------
# 9. Q21B: RadialWheel Smooth Hover-Wedge Pop Animation & Selection Tick SFX
# ---------------------------------------------------------------------------

func test_q21b_radial_wheel_hover_pop_animation_and_tick_sfx() -> void:
	check(Audio.has_sound(RadialWheel.SFX_HOVER_TICK),
		"Audio manifest registers verified RadialWheel hover tick SFX '%s'" % String(RadialWheel.SFX_HOVER_TICK))

	var wheel := RadialWheel.new()
	wheel.size = Vector2(1280.0, 720.0)
	add_child(wheel)
	await get_tree().process_frame
	wheel.set_process(false)

	var slices: Array[Dictionary] = [
		{"id": &"cutlass", "label": "Cutlass", "hint": "Swift blade | Parry & lunge", "icon": &"cutlass"},
		{"id": &"pistol", "label": "Flintlock Pistol", "hint": "Single-shot sidearm", "icon": &"pistol"},
		{"id": &"spyglass", "label": "Spyglass", "hint": "Scout distant sails", "icon": &"spyglass"},
		{"id": &"compass", "label": "Brass Compass", "hint": "True North bearing", "icon": &"compass"},
		{"id": &"lantern", "label": "Oil Lantern", "hint": "Warm deck light", "icon": &"lantern"},
		{"id": &"shovel", "label": "Iron Shovel", "hint": "Dig buried hoards", "icon": &"shovel"},
		{"id": &"bucket", "label": "Bilge Bucket", "hint": "Bail hold or douse fire", "icon": &"bucket"},
		{"id": &"planks", "label": "Oak Planks", "hint": "Patch hull breaches" + char(0x2014) + "fast", "icon": &"planks"},
	]
	wheel.configure("Captain Gear" + char(0x2014) + "Deck", slices, "", "Release [Q] to equip " + char(0x00B7) + " [Esc] Cancel")

	# 1. Open wheel -> smooth open pop-in 0.0 -> 1.0 over 0.12 s.
	wheel.open_wheel()
	check(wheel.is_open and wheel.visible, "RadialWheel opens cleanly with 8 slices")
	check_eq(wheel.entries.size(), 8, "RadialWheel holds all 8 configured slices")
	check_near(wheel.get_open_anim_progress(), 0.0, 0.001, "open animation starts cleanly at 0.0")
	check_eq(wheel.get_hover_tick_count(), 0, "fresh open_wheel emits zero hover selection ticks")
	for i in 8:
		check_near(wheel.get_wedge_hover_weight(i), 0.0, 0.001,
			"wedge %d starts unexpanded (weight=0.0)" % i)
	check_near(wheel.get_wedge_hover_weight(-1), 0.0, 0.001, "out-of-range negative index returns 0.0")
	check_near(wheel.get_wedge_hover_weight(99), 0.0, 0.001, "out-of-range high index returns 0.0")

	wheel.step_radial_animation(0.06)
	check_near(wheel.get_open_anim_progress(), 0.50, 0.02,
		"step_radial_animation(0.06) advances open pop-in halfway to 0.50 (got %.3f)" % wheel.get_open_anim_progress())
	wheel.step_radial_animation(0.06)
	check_near(wheel.get_open_anim_progress(), 1.0, 0.001,
		"step_radial_animation(0.12 total) completes open pop-in at 1.0")

	# 2. Hover slice 0 -> tick count increments strictly once, weight rises smoothly toward 1.0.
	wheel.set_hover_index(0)
	check_eq(wheel.get_hover_tick_count(), 1, "hovering slice 0 increments hover_tick_count to 1")
	wheel.set_hover_index(0)
	wheel.set_hover_index(0)
	check_eq(wheel.get_hover_tick_count(), 1, "repeated hover on same slice 0 does NOT increment hover_tick_count")

	wheel.step_radial_animation(0.04)
	var w0_mid := wheel.get_wedge_hover_weight(0)
	check(w0_mid > 0.30 and w0_mid < 0.90,
		"hovered slice 0 smoothly eases upward between 0.30 and 0.90 after 0.04 s (got %.3f)" % w0_mid)
	for i in range(1, 8):
		check_near(wheel.get_wedge_hover_weight(i), 0.0, 0.001,
			"non-hovered slice %d remains at 0.0" % i)

	for _step in 16:
		wheel.step_radial_animation(0.04)
	check_near(wheel.get_wedge_hover_weight(0), 1.0, 0.01,
		"hovered slice 0 settles cleanly at 1.0 (got %.3f)" % wheel.get_wedge_hover_weight(0))

	# 3. Move hover to slice 3 -> tick count becomes 2; slice 3 rises while slice 0 decays smoothly.
	wheel.set_hover_index(3)
	check_eq(wheel.get_hover_tick_count(), 2, "moving hover to slice 3 increments hover_tick_count to 2")
	wheel.set_hover_index(3)
	check_eq(wheel.get_hover_tick_count(), 2, "repeated hover on slice 3 does NOT increment hover_tick_count")

	wheel.step_radial_animation(0.05)
	var w3_mid := wheel.get_wedge_hover_weight(3)
	var w0_decay := wheel.get_wedge_hover_weight(0)
	check(w3_mid > 0.35 and w3_mid < 0.95,
		"newly hovered slice 3 smoothly rises toward 1.0 (got %.3f)" % w3_mid)
	check(w0_decay > 0.20 and w0_decay < 0.85,
		"previously hovered slice 0 smoothly decays toward 0.0 (got %.3f)" % w0_decay)

	# Exercise full RadialWheel._draw() mid-transition with both rising & decaying wedges!
	wheel.queue_redraw()
	await get_tree().process_frame

	for _step in 20:
		wheel.step_radial_animation(0.05)
	check_near(wheel.get_wedge_hover_weight(3), 1.0, 0.01,
		"slice 3 settles cleanly at 1.0 (got %.3f)" % wheel.get_wedge_hover_weight(3))
	check_near(wheel.get_wedge_hover_weight(0), 0.0, 0.01,
		"previous slice 0 decays cleanly to 0.0 (got %.3f)" % wheel.get_wedge_hover_weight(0))

	# 4. Angle-based selection triggers tick strictly on slice change (slice 6 at 9 o'clock = PI).
	var picked := wheel.select_by_angle(PI)
	check_eq(picked, &"bucket", "select_by_angle(PI) targets 9 o'clock slice 6 (bucket)")
	check_eq(wheel.get_hover_tick_count(), 3, "select_by_angle to new slice 6 increments hover_tick_count to 3")
	wheel.select_by_angle(PI + 0.05)
	check_eq(wheel.get_hover_tick_count(), 3, "same-slice angle jitter does NOT re-trigger hover tick")

	# 5. Verify strict ASCII (< 128) across every slice label, footer pill, and sanitized title/hints.
	for i in 8:
		var slbl := wheel.get_slice_display_label(i)
		check(slbl != "" and _is_strict_ascii(slbl),
			"slice %d display label '%s' is non-empty strict ASCII" % [i, slbl])
		var shint := RadialWheel._to_ascii(String(wheel.entries[i].get("hint", "")))
		check(_is_strict_ascii(shint), "slice %d sanitized hint '%s' is strict ASCII" % [i, shint])
	var title_ascii := RadialWheel._to_ascii(wheel.wheel_title)
	var footer_ascii := wheel.get_footer_pill_text()
	check(_is_strict_ascii(title_ascii), "RadialWheel title '%s' sanitizes to strict ASCII" % title_ascii)
	check(footer_ascii != "" and _is_strict_ascii(footer_ascii),
		"RadialWheel footer pill '%s' is strict ASCII" % footer_ascii)
	check(_is_strict_ascii(RadialWheel.DEFAULT_ITEM_FOOTER),
		"RadialWheel.DEFAULT_ITEM_FOOTER is strict ASCII")

	# 6. Close and free cleanly with zero ObjectDB leaks.
	wheel.close_wheel(false)
	check(not wheel.is_open, "close_wheel closes RadialWheel")
	check_near(wheel.get_open_anim_progress(), 0.0, 0.001, "close_wheel resets open animation progress to 0.0")
	for i in 8:
		check_near(wheel.get_wedge_hover_weight(i), 0.0, 0.001,
			"close_wheel resets wedge %d hover weight to 0.0" % i)
	wheel.queue_free()
	await physics_frames(2)
	check(not is_instance_valid(wheel), "Q21B RadialWheel frees cleanly with 0 leaks")


# ---------------------------------------------------------------------------
# 10. Q22B: LocationBanner Arrival Chimes & Shimmer + Shipwright Confirm Flash
# ---------------------------------------------------------------------------

func test_q22b_location_banner_arrival_chimes_shimmer_and_shipwright_confirm_flash() -> void:
	# 1. Verify manifest-registered arrival SFX mappings for all 3 LocationBanner styles.
	check_eq(LocationBanner.arrival_sfx_for_style(&"outpost"), &"ship_bell",
		"outpost banner maps to &'ship_bell'")
	check_eq(LocationBanner.arrival_sfx_for_style(&"island"), &"ui_open",
		"island banner maps to &'ui_open'")
	check_eq(LocationBanner.arrival_sfx_for_style(&"threat"), &"thunder_far",
		"threat banner maps to &'thunder_far'")
	check(Audio.has_sound(&"ship_bell"), "Audio manifest registers &'ship_bell'")
	check(Audio.has_sound(&"ui_open"), "Audio manifest registers &'ui_open'")
	check(Audio.has_sound(&"thunder_far"), "Audio manifest registers &'thunder_far'")

	var banner := LocationBanner.new()
	add_child(banner)
	banner.set_process(false)
	await get_tree().process_frame

	for c_node in banner.find_children("*", "Control", true, false):
		var ctrl := c_node as Control
		check_eq(ctrl.mouse_filter, Control.MOUSE_FILTER_IGNORE,
			"Q22B LocationBanner control '%s' uses MOUSE_FILTER_IGNORE" % ctrl.name)

	check(banner.play_audio, "LocationBanner defaults play_audio = true")
	check_eq(banner.last_arrival_sfx, &"", "LocationBanner starts with empty last_arrival_sfx")
	check_eq(banner.arrival_sfx_count, 0, "LocationBanner starts with arrival_sfx_count = 0")
	check_near(banner.get_shimmer_progress(), 0.0, 0.001, "idle shimmer progress is 0.0")

	# Outpost arrival -> &'ship_bell' + shimmer sweep 0.0 -> mid -> 1.0 across 1.15 s!
	check(banner.show_location("Port Scoundrel", "Outpost Harbour -- Safe Anchorage", &"outpost", 2.5),
		"show_location activates outpost banner")
	check_eq(banner.last_arrival_sfx, &"ship_bell", "outpost arrival plays &'ship_bell'")
	check_eq(banner.arrival_sfx_count, 1, "arrival_sfx_count increments to 1")
	check_near(banner.get_shimmer_progress(), 0.0, 0.001, "shimmer starts at 0.0 on activation")

	# Step near star sunburst flare peak (~0.18 * 1.15 s) and exercise _draw().
	banner.step_banner(0.21)
	var flare_prog := banner.get_shimmer_progress()
	check(flare_prog > 0.14 and flare_prog < 0.24,
		"shimmer advances smoothly through compass-star sunburst peak (got %.3f)" % flare_prog)
	await get_tree().process_frame

	# Step to exact midpoint (0.575 s of 1.15 s -> 0.50) and exercise wing gleam _draw().
	banner.step_banner(0.365)
	check_near(banner.get_shimmer_progress(), 0.50, 0.01,
		"shimmer hits 0.50 at 0.575 s midpoint (got %.3f)" % banner.get_shimmer_progress())
	await get_tree().process_frame

	# Step to 1.15 s completion and confirm clamp at 1.0 while still holding!
	banner.step_banner(0.575)
	check_near(banner.get_shimmer_progress(), 1.0, 0.005,
		"shimmer reaches 1.0 at SHIMMER_DURATION (1.15 s)")
	banner.step_banner(0.35)
	check_near(banner.get_shimmer_progress(), 1.0, 0.005,
		"shimmer remains clamped at 1.0 after 1.15 s while holding")
	banner.clear_banner()
	check(not banner.is_banner_active(), "clear_banner deactivates outpost banner cleanly")
	check_near(banner.get_shimmer_progress(), 0.0, 0.001, "clear_banner resets shimmer progress to 0.0")

	# Island arrival -> &'ui_open' + shimmer draw.
	check(banner.show_location("Cutlass Cay", "Uncharted Treasure Cay", &"island", 1.8),
		"show_location activates island banner")
	check_eq(banner.last_arrival_sfx, &"ui_open", "island arrival plays &'ui_open'")
	check_eq(banner.arrival_sfx_count, 2, "arrival_sfx_count increments to 2")
	banner.step_banner(0.42)
	check(banner.get_shimmer_progress() > 0.30 and banner.get_shimmer_progress() < 0.45,
		"island banner shimmer advances cleanly (got %.3f)" % banner.get_shimmer_progress())
	await get_tree().process_frame
	banner.clear_banner()

	# Threat arrival -> &'thunder_far' + seafoam-crimson shimmer draw.
	check(banner.show_location("Sovereign's Bastion", "Grand Citadel -- Tier IV Sea Fortress", &"threat", 1.8),
		"show_location activates threat banner")
	check_eq(banner.last_arrival_sfx, &"thunder_far", "threat arrival plays &'thunder_far'")
	check_eq(banner.arrival_sfx_count, 3, "arrival_sfx_count increments to 3")
	banner.step_banner(0.46)
	check(banner.get_shimmer_progress() > 0.35 and banner.get_shimmer_progress() < 0.50,
		"threat banner shimmer advances cleanly (got %.3f)" % banner.get_shimmer_progress())
	await get_tree().process_frame
	banner.clear_banner()

	# play_audio = false suppresses audio cleanly without incrementing arrival_sfx_count!
	banner.play_audio = false
	check(banner.show_location("Barnacle Haven", "Outpost Harbour -- Safe Anchorage", &"outpost", 1.5),
		"show_location succeeds while play_audio = false")
	check_eq(banner.arrival_sfx_count, 3, "play_audio = false suppresses arrival SFX count increment")
	check_eq(banner.last_arrival_sfx, &"thunder_far", "play_audio = false leaves last_arrival_sfx untouched")
	banner.clear_banner()
	banner.reset_audio_stats()
	check_eq(banner.arrival_sfx_count, 0, "reset_audio_stats zeroes arrival_sfx_count")
	check_eq(banner.last_arrival_sfx, &"", "reset_audio_stats clears last_arrival_sfx")

	# 2. ShipwrightMenu framed parchment status strip & smooth gold/warn confirmation flash!
	var saved_profile: Profile = Game.profile
	var test_prof := Profile.new()
	test_prof.data["gold"] = 50
	test_prof.data["ship_class"] = "sloop"
	Game.profile = test_prof

	var sw := ShipwrightMenu.new()
	add_child(sw)
	await get_tree().process_frame
	sw.set_process(false)
	sw.open_menu(ShipwrightMenu.TAB_SHIPWRIGHT)
	await get_tree().process_frame

	var status_panel := sw.find_child("MenuStatusPanel", true, false) as PanelContainer
	var status_lbl := sw.find_child("MenuStatusLabel", true, false) as Label
	check(status_panel != null and status_lbl != null,
		"ShipwrightMenu mounts framed MenuStatusPanel and MenuStatusLabel")
	if status_panel != null and status_lbl != null:
		check_eq(status_lbl.get_parent(), status_panel, "MenuStatusLabel sits inside MenuStatusPanel")
	var sb_ref: StyleBoxFlat = status_panel.get_theme_stylebox("panel") as StyleBoxFlat if status_panel != null else null
	check(sb_ref != null, "MenuStatusPanel uses a pre-built reusable StyleBoxFlat")
	check_near(sw.get_status_flash_strength(), 0.0, 0.001, "status flash starts idle at 0.0")
	check_eq(sw.get_status_flash_kind(), &"", "status flash kind starts idle as &''")

	# Successful equip -> &'gold' flash (1.0 -> mid -> 0.0 over 0.90 s with zero StyleBox reallocation)!
	var equip_res := sw.buy_or_equip_unlock(&"hull_standard")
	check(bool(equip_res.get("ok", false)), "equipping owned hull_standard succeeds")
	check_eq(sw.get_status_flash_kind(), &"gold", "successful equip triggers &'gold' confirmation flash")
	check_near(sw.get_status_flash_strength(), 1.0, 0.005, "gold flash starts at peak strength 1.0")
	if sb_ref != null:
		check(sb_ref.bg_color.is_equal_approx(ShipwrightMenu.STATUS_GOLD_BG),
			"gold flash peaks at glowing gilded parchment background")
		check(sb_ref.border_color.is_equal_approx(HudIcons.COL_GOLD),
			"gold flash peaks at HudIcons.COL_GOLD border")

	sw.step_feedback(0.25)
	var mid_gold_str := sw.get_status_flash_strength()
	check(mid_gold_str > 0.15 and mid_gold_str < 0.70,
		"step_feedback(0.25) smoothly eases gold flash strength downward (got %.3f)" % mid_gold_str)
	check_eq(sw.get_status_flash_kind(), &"gold", "gold flash kind persists mid-decay")
	if status_panel != null and sb_ref != null:
		check_eq(status_panel.get_theme_stylebox("panel"), sb_ref,
			"step_feedback mutates existing StyleBoxFlat in-place (0 per-frame allocations)")

	sw.step_feedback(0.65)
	check_near(sw.get_status_flash_strength(), 0.0, 0.001, "gold flash decays cleanly to 0.0 at 0.90 s")
	check_eq(sw.get_status_flash_kind(), &"", "gold flash kind clears to &'' when settled")
	if sb_ref != null:
		check(sb_ref.bg_color.is_equal_approx(ShipwrightMenu.STATUS_REST_BG),
			"status panel returns to resting parchment background after flash")
		check(sb_ref.border_color.is_equal_approx(HudIcons.COL_INK_SOFT),
			"status panel returns to HudIcons.COL_INK_SOFT border after flash")

	# Successful ship christening -> &'gold' flash!
	var new_ship_name := sw.cycle_ship_name()
	check(new_ship_name != "" and _is_strict_ascii(new_ship_name), "cycle_ship_name returns strict-ASCII name")
	check_eq(sw.get_status_flash_kind(), &"gold", "cycle_ship_name triggers &'gold' flash")
	check_near(sw.get_status_flash_strength(), 1.0, 0.005, "christen flash peaks at 1.0")
	sw.step_feedback(0.90)
	check_near(sw.get_status_flash_strength(), 0.0, 0.001, "christen flash settles cleanly to 0.0")

	# Successful quality preset -> &'gold' flash!
	sw.apply_quality_preset(1)
	check_eq(sw.get_status_flash_kind(), &"gold", "apply_quality_preset triggers &'gold' flash")
	check_near(sw.get_status_flash_strength(), 1.0, 0.005, "quality preset flash peaks at 1.0")
	sw.step_feedback(0.90)
	check_near(sw.get_status_flash_strength(), 0.0, 0.001, "quality preset flash settles cleanly to 0.0")

	# Insufficient-gold purchase failure -> &'warn' coral-crimson flash!
	var fail_res := sw.buy_or_equip_unlock(&"tool_gilded_spyglass")
	check(not bool(fail_res.get("ok", true)), "unaffordable unlock purchase fails cleanly with 50 gold")
	check_eq(sw.get_status_flash_kind(), &"warn", "insufficient-gold failure triggers &'warn' flash")
	check_near(sw.get_status_flash_strength(), 1.0, 0.005, "warn flash peaks at 1.0")
	if sb_ref != null:
		check(sb_ref.bg_color.is_equal_approx(ShipwrightMenu.STATUS_WARN_BG),
			"warn flash peaks at warm coral-parchment background")
		check(sb_ref.border_color.is_equal_approx(HudIcons.COL_CRIMSON),
			"warn flash peaks at HudIcons.COL_CRIMSON border")
	if status_lbl != null:
		check(_is_strict_ascii(status_lbl.text) and status_lbl.text != "",
			"warn status text '%s' is non-empty strict ASCII" % status_lbl.text)

	sw.step_feedback(0.30)
	var mid_warn_str := sw.get_status_flash_strength()
	check(mid_warn_str > 0.15 and mid_warn_str < 0.65,
		"step_feedback(0.30) smoothly eases warn flash downward (got %.3f)" % mid_warn_str)
	check_eq(sw.get_status_flash_kind(), &"warn", "warn flash kind persists mid-decay")
	sw.step_feedback(0.60)
	check_near(sw.get_status_flash_strength(), 0.0, 0.001, "warn flash decays cleanly to 0.0 at 0.90 s")
	check_eq(sw.get_status_flash_kind(), &"", "warn flash clears cleanly to &''")

	# Sufficient-gold purchase -> &'gold' flash!
	test_prof.data["gold"] = 500
	var buy_ok := sw.buy_or_equip_unlock(&"tool_gilded_spyglass")
	check(bool(buy_ok.get("ok", false)) and bool(buy_ok.get("purchased", false)),
		"purchasing tool_gilded_spyglass with 500 gold succeeds")
	check_eq(sw.get_status_flash_kind(), &"gold", "successful purchase triggers &'gold' flash")
	check_near(sw.get_status_flash_strength(), 1.0, 0.005, "purchase gold flash peaks at 1.0")

	# Strict ASCII verification across EVERY Label, Button & status widget in ShipwrightMenu!
	var checked_sw := _check_tree_strict_ascii(sw, "Q22B_ShipwrightMenu")
	check(checked_sw >= 35, "verified 100%% strict ASCII across Q22B ShipwrightMenu (checked %d)" % checked_sw)

	# 3. Clean zero-leak teardown!
	sw.close_menu()
	check_near(sw.get_status_flash_strength(), 0.0, 0.001, "close_menu resets status flash cleanly")
	Game.profile = saved_profile
	Game.save()
	sw.queue_free()
	banner.queue_free()
	await physics_frames(3)
	check(not is_instance_valid(sw) and not is_instance_valid(banner),
		"Q22B ShipwrightMenu and LocationBanner free cleanly with 0 leaks")


# ---------------------------------------------------------------------------
# 11. Q24B: TitleMenu Page Fade, Rate-Limited Hover Ticks, Focus & Director Chimes
# ---------------------------------------------------------------------------

func test_q24b_title_menu_page_fade_hover_ticks_and_director_chimes() -> void:
	Net.start_single_player()

	# 1. Verify every Q24B SFX id is registered in Audio's manifest (zero unknown-SFX warnings).
	check(Audio != null and Audio.has_sound(TitleMenu.SFX_HOVER_TICK),
		"Audio manifest registers TitleMenu hover tick SFX '%s'" % String(TitleMenu.SFX_HOVER_TICK))
	check(Audio != null and Audio.has_sound(SkirmishDirector.SFX_RESTOCK_BELL),
		"Audio manifest registers SkirmishDirector restock bell SFX '%s'" % String(SkirmishDirector.SFX_RESTOCK_BELL))
	check(Audio != null and Audio.has_sound(TutorialDirector.SFX_STAGE_COMPLETE),
		"Audio manifest registers TutorialDirector stage chime SFX '%s'" % String(TutorialDirector.SFX_STAGE_COMPLETE))

	# 2. TitleMenu smooth ease-out page fade (0.22 s), focus handoff & rate-limited hover ticks.
	var menu := TitleMenu.new()
	add_child(menu)
	await get_tree().process_frame
	menu.set_process(false)

	check(menu.play_hover_audio, "TitleMenu defaults play_hover_audio = true")
	check_eq(menu.hover_tick_count, 0, "TitleMenu starts with hover_tick_count = 0")

	menu.open_menu(TitleMenu.Page.LANDING)
	check_near(menu.get_page_fade_alpha(), 0.0, 0.001,
		"open_menu resets get_page_fade_alpha() to 0.0 for smooth fade-in")
	check_eq(menu.hover_tick_count, 0,
		"opening menu and focusing primary Landing button does NOT emit spurious hover ticks")
	var btn_adv := menu.find_child("BtnAdventure", true, false) as Button
	check(btn_adv != null and btn_adv.has_focus(),
		"open_menu(LANDING) grabs keyboard focus on BtnAdventure")

	# Switch to SETUP -> fade resets to 0.0, SetSailBtn grabs focus, advances 0.0 -> mid -> 1.0 across 0.22 s!
	menu.show_page(TitleMenu.Page.SETUP)
	var setup_page := menu.find_child("SetupPage", true, false) as Control
	var sail_btn := menu.find_child("SetSailBtn", true, false) as Button
	check(setup_page != null and setup_page.visible, "SetupPage is visible on Page.SETUP")
	check(sail_btn != null and sail_btn.has_focus(),
		"show_page(SETUP) grabs keyboard focus on SetSailBtn")
	check_eq(menu.hover_tick_count, 0,
		"show_page(SETUP) focus handoff does NOT emit spurious hover ticks")
	check_near(menu.get_page_fade_alpha(), 0.0, 0.001,
		"show_page(SETUP) resets get_page_fade_alpha() to 0.0")
	if setup_page != null:
		check_near(setup_page.modulate.a, 0.0, 0.001, "SetupPage modulate.a starts at 0.0")

	menu.step_ui_transition(0.055)
	var fade_q1 := menu.get_page_fade_alpha()
	check(fade_q1 > 0.35 and fade_q1 < 0.75,
		"step_ui_transition(0.055) smoothly advances ease-out fade into mid-range (got %.3f)" % fade_q1)
	if setup_page != null:
		check_near(setup_page.modulate.a, fade_q1, 0.002,
			"SetupPage modulate.a matches get_page_fade_alpha() mid-fade")

	menu.step_ui_transition(0.055)
	var fade_half := menu.get_page_fade_alpha()
	check(fade_half > fade_q1 and fade_half < 0.96,
		"step_ui_transition(0.11 total) advances monotonically along ease-out cubic (got %.3f)" % fade_half)

	menu.step_ui_transition(0.11)
	check_near(menu.get_page_fade_alpha(), 1.0, 0.0005,
		"step_ui_transition(0.22 total) snaps cleanly to 1.0")
	if setup_page != null:
		check_near(setup_page.modulate.a, 1.0, 0.0005, "SetupPage modulate.a settles cleanly at 1.0")

	# Switch to COOP & SETTINGS -> focus grabs cleanly and uneven exact sums (0.10 + 0.12 = 0.22) snap to 1.0.
	menu.show_page(TitleMenu.Page.COOP)
	var host_btn := menu.find_child("BtnCoopHost", true, false) as Button
	check(host_btn != null and host_btn.has_focus(), "show_page(COOP) grabs focus on BtnCoopHost")
	check_near(menu.get_page_fade_alpha(), 0.0, 0.001, "show_page(COOP) resets fade to 0.0")
	menu.step_ui_transition(0.10)
	check(menu.get_page_fade_alpha() > 0.50 and menu.get_page_fade_alpha() < 0.99,
		"COOP page fade mid-transition at 0.10 s (got %.3f)" % menu.get_page_fade_alpha())
	menu.step_ui_transition(0.12)
	check_near(menu.get_page_fade_alpha(), 1.0, 0.0005,
		"COOP page fade snaps cleanly to 1.0 on exact sum 0.10 + 0.12 = 0.22 s")

	menu.show_page(TitleMenu.Page.SETTINGS)
	var apply_btn := menu.find_child("SettingsApplyBtn", true, false) as Button
	check(apply_btn != null and apply_btn.has_focus(), "show_page(SETTINGS) grabs focus on SettingsApplyBtn")
	menu.step_ui_transition(0.22)
	check_near(menu.get_page_fade_alpha(), 1.0, 0.0005, "SETTINGS page fade completes cleanly at 0.22 s")

	# Rate-limited tactile hover tick SFX on mouse_entered & focus_entered.
	menu.show_page(TitleMenu.Page.LANDING)
	menu.step_ui_transition(0.22)
	var btn_tut := menu.find_child("BtnTutorial", true, false) as Button
	var btn_skirm := menu.find_child("BtnSkirmish", true, false) as Button
	var btn_coop := menu.find_child("BtnCoop", true, false) as Button
	check(btn_tut != null and btn_skirm != null and btn_coop != null,
		"Landing page primary interactive buttons exist for hover tick verification")

	if btn_tut != null and btn_skirm != null and btn_coop != null:
		btn_tut.mouse_entered.emit()
		check_eq(menu.hover_tick_count, 1, "first button hover increments hover_tick_count to 1")
		# Immediate mouse sweep & focus events within 0.07 s cooldown must be rate-limited!
		btn_skirm.mouse_entered.emit()
		btn_coop.focus_entered.emit()
		check_eq(menu.hover_tick_count, 1, "fast sweep within 0.07 s cooldown does NOT spam hover ticks")

		menu.step_ui_transition(0.03)
		btn_skirm.mouse_entered.emit()
		check_eq(menu.hover_tick_count, 1, "hover at 0.03 s (< 0.07 s cooldown) remains rate-limited")

		menu.step_ui_transition(0.04)
		btn_skirm.focus_entered.emit()
		check_eq(menu.hover_tick_count, 2, "focus_entered after 0.07 s cooldown increments hover_tick_count to 2")

		# Respect play_hover_audio = false!
		menu.play_hover_audio = false
		menu.step_ui_transition(0.10)
		btn_tut.mouse_entered.emit()
		btn_coop.focus_entered.emit()
		check_eq(menu.hover_tick_count, 2, "play_hover_audio = false suppresses hover ticks cleanly")

		# Closed menu ignores hover ticks even when play_hover_audio = true.
		menu.play_hover_audio = true
		menu.close_menu()
		menu.step_ui_transition(0.10)
		btn_tut.mouse_entered.emit()
		check_eq(menu.hover_tick_count, 2, "closed TitleMenu suppresses hover ticks cleanly")

	var checked_widgets := _check_tree_strict_ascii(menu, "Q24B_TitleMenu")
	check(checked_widgets >= 50,
		"verified 100%% strict ASCII across Q24B TitleMenu widgets (checked %d)" % checked_widgets)

	# 3. SkirmishDirector restock ship_bell SFX count & play_audio = false guard.
	var sd := SkirmishDirector.new()
	sd.play_audio = true
	sd.post_notices = false
	sd.profile = Profile.new()
	add_child(sd)

	var restock_hits: Array[int] = [0]
	sd.restock_requested.connect(func(_cb: int, _pl: int) -> void: restock_hits[0] += 1)

	sd.start_skirmish(1.0, 1.0)
	check_eq(sd.restock_bell_count, 0, "SkirmishDirector starts with restock_bell_count = 0")

	# Wave 1 clear -> INTERMISSION restock plays &'ship_bell' and increments restock_bell_count to 1!
	sd.notify_enemy_defeated(&"ship")
	check_eq(sd.state, SkirmishDirector.State.INTERMISSION, "Wave 1 clear enters INTERMISSION")
	check_eq(restock_hits[0], 1, "Wave 1 clear emits restock_requested")
	check_eq(sd.restock_bell_count, 1, "Wave 1 intermission restock increments restock_bell_count to 1")

	# Wave 2 clear with play_audio = false -> restock emits, but bell is suppressed!
	sd.play_audio = false
	sd.step_skirmish(SkirmishDirector.INTERMISSION_SECONDS + 0.1)
	check_eq(sd.wave_number, 2, "Wave 2 begins after intermission")
	sd.notify_enemy_defeated(&"ship")
	sd.notify_enemy_defeated(&"ship")
	check_eq(sd.state, SkirmishDirector.State.INTERMISSION, "Wave 2 clear enters INTERMISSION")
	check_eq(restock_hits[0], 2, "Wave 2 clear emits restock_requested")
	check_eq(sd.restock_bell_count, 1, "SkirmishDirector play_audio = false suppresses restock bell")

	# Wave 3 clear with play_audio = true -> increments restock_bell_count to 2!
	sd.play_audio = true
	sd.step_skirmish(SkirmishDirector.INTERMISSION_SECONDS + 0.1)
	sd.notify_enemy_defeated(&"ship")
	sd.notify_enemy_defeated(&"ship")
	check_eq(sd.restock_bell_count, 2, "Wave 3 intermission restock increments restock_bell_count to 2")

	# Final Wave 4 clear -> VICTORY (no intermission restock bell).
	sd.step_skirmish(SkirmishDirector.INTERMISSION_SECONDS + 0.1)
	sd.notify_enemy_defeated(&"leviathan")
	sd.notify_enemy_defeated(&"ship")
	check_eq(sd.state, SkirmishDirector.State.VICTORY, "Wave 4 clear reaches VICTORY")
	check_eq(sd.restock_bell_count, 2, "Final victory wave does NOT trigger extra intermission restock bell")
	check_eq(int(sd.get_state().get("restock_bell_count", -1)), 2,
		"SkirmishDirector.get_state() reports restock_bell_count")

	sd.start_skirmish(1.0, 1.0)
	check_eq(sd.restock_bell_count, 0, "start_skirmish resets restock_bell_count to 0")

	# 4. TutorialDirector intermediate stage completion chime & play_audio = false guard.
	var td := TutorialDirector.new()
	td.play_audio = true
	td.post_notices = false
	td.profile = Profile.new()
	add_child(td)

	td.start_tutorial(Vector3(0.0, 0.0, -300.0), "Cutlass Cay")
	check_eq(td.stage_chime_count, 0, "TutorialDirector starts with stage_chime_count = 0")

	td.notify_action(&"equip_compass")
	check_eq(td.current_step, 1, "Stage 0 completes into Stage 1")
	check_eq(td.stage_chime_count, 1, "Completing intermediate Stage 0 increments stage_chime_count to 1")

	td.notify_action(&"check_map_table")
	check_eq(td.current_step, 2, "Stage 1 completes into Stage 2")
	check_eq(td.stage_chime_count, 2, "Completing intermediate Stage 1 increments stage_chime_count to 2")

	# Suppress audio -> completing Stage 2..6 must NOT increment stage_chime_count!
	td.play_audio = false
	td.notify_action(&"raise_anchor")
	check_eq(td.current_step, 3, "Stage 2 completes while play_audio = false")
	check_eq(td.stage_chime_count, 2, "TutorialDirector play_audio = false suppresses stage chime")
	for _i in 4:
		td.skip_current_step()
	check_eq(td.current_step, 7, "Reached final graduation Stage 7")
	check_eq(td.stage_chime_count, 2, "Muted intermediate stages keep stage_chime_count at 2")

	# Final stage graduation plays victory stinger (not intermediate stage chime).
	td.play_audio = true
	td.notify_treasure_sold()
	check(td.completed and not td.active, "Final stage graduates tutorial cleanly")
	check_eq(td.stage_chime_count, 2,
		"Final graduation uses victory stinger and does NOT increment intermediate stage_chime_count")
	check_eq(int(td.get_state().get("stage_chime_count", -1)), 2,
		"TutorialDirector.get_state() reports stage_chime_count")

	td.start_tutorial(Vector3(0.0, 0.0, -300.0), "Cutlass Cay")
	check_eq(td.stage_chime_count, 0, "start_tutorial resets stage_chime_count to 0")

	# 5. Verify 0 non-ASCII (< 128) characters across all 3 Q24B production scripts!
	var q24b_scripts: Array[String] = [
		"res://src/ui/title_menu.gd",
		"res://src/voyage/skirmish_director.gd",
		"res://src/voyage/tutorial_director.gd",
	]
	for script_path: String in q24b_scripts:
		var src_text := FileAccess.get_file_as_string(script_path)
		check(src_text.length() > 100, "loaded source text of %s" % script_path)
		var non_ascii := 0
		for i in src_text.length():
			if src_text.unicode_at(i) >= 128:
				non_ascii += 1
		check_eq(non_ascii, 0, "%s has 0 non-ASCII characters" % script_path)

	# 6. Clean zero-leak teardown!
	menu.queue_free()
	sd.queue_free()
	td.queue_free()
	await physics_frames(3)
	check(not is_instance_valid(menu) and not is_instance_valid(sd) and not is_instance_valid(td),
		"Q24B TitleMenu, SkirmishDirector & TutorialDirector free cleanly with 0 leaks")



