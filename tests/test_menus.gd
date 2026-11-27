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
