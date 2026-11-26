class_name TitleMenu
extends CanvasLayer
## Live-3D First-Launch Title & Main Menu overlay for Sea of Scoundrels.
##
## Floats cleanly over the live 3D harbour vista with a soft left-anchored
## vignette and handcrafted parchment-and-brass panels, leaving the right side
## open so the moored Sloop/Brigantine, volumetric clouds, and 2D-FFT ocean
## shimmer right beside the menu. Provides 4 clean pages:
## - LANDING: Title masthead, Captain Profile summary, and game mode stack
## - SETUP: Pre-Sail Voyage, Ship, Outpost, Crew, Weather & Emissary configurator
## - COOP: LAN / Direct-IP Co-op Crew Host & Join lobby
## - SETTINGS: Live UserSettings graphics, audio, FOV, sensitivity & controls

signal start_game_requested(config: SessionConfig)
signal preview_config_changed(config: SessionConfig)
signal settings_changed
signal quit_requested

enum Page {
	LANDING,
	SETUP,
	COOP,
	SETTINGS,
}

const DEFAULT_SENS := 0.0023

const CAPTAIN_CONTROLS_LINES: Array[String] = [
	"[WASD] Move  |  [Space] Jump  |  [Shift] Sprint  |  [X] Step Off",
	"[Q / Tab] Tools Radial (Hold or Tap)  |  [G] Crew Orders  |  [1-6] Quick Slots",
	"[F] Use / Leave Stations & Quick-Drop Anchor  |  [Hold W] Heave Anchor",
	"[S / W] Lower / Raise Sails  |  [A / D] Steer Wheel & Trim Sails  |  [RMB] Center Helm",
	"[LMB / RMB] Slash / Aim / Block / Climb in Cannon  |  [R] Swap Cannon Shot (6 Types)",
	"[T] Speaking Trumpet Crew Recall  |  [B] Shipwright (at Outpost)  |  [Esc] Pause",
]

var is_open: bool = false
var config: SessionConfig = SessionConfig.new()
var current_page: Page = Page.LANDING

var user_settings: UserSettings = null
var profile: Profile = null
var scene_root: Node = null

var _theme: Theme = null
var _root: Control = null
var _backdrop: _LeftVignetteBackdrop = null
var _pages: Dictionary = {}  # Page (int) -> Control
var _syncing_ui: bool = false
var _status_message: String = ""

# Landing widgets
var _profile_ship_label: Label = null
var _profile_stats_label: Label = null
var _landing_status_label: Label = null

# Setup widgets
var _setup_header_pill: Label = null
var _mode_btns: Dictionary = {}       # StringName -> Button
var _mode_desc_label: Label = null
var _ship_btns: Dictionary = {}       # StringName -> Button
var _ship_desc_label: Label = null
var _ship_name_edit: LineEdit = null
var _crew_btns: Dictionary = {}       # int -> Button
var _crew_desc_label: Label = null
var _outpost_btns: Dictionary = {}    # StringName -> Button
var _outpost_desc_label: Label = null
var _time_btns: Dictionary = {}       # StringName -> Button
var _weather_btns: Dictionary = {}    # StringName -> Button
var _diff_btns: Dictionary = {}       # StringName -> Button
var _diff_desc_label: Label = null
var _emissary_btns: Dictionary = {}   # StringName -> Button
var _emissary_desc_label: Label = null
var _setup_status_label: Label = null

# Co-op widgets
var _coop_host_port_edit: LineEdit = null
var _coop_ship_btns: Dictionary = {}     # StringName -> Button
var _coop_outpost_btns: Dictionary = {}  # StringName -> Button
var _coop_ship_name_edit: LineEdit = null
var _coop_crew_btns: Dictionary = {}     # int -> Button
var _coop_crew_desc_label: Label = null
var _coop_join_addr_edit: LineEdit = null
var _coop_join_port_edit: LineEdit = null
var _coop_status_label: Label = null

# Settings widgets
var _ocean_qual_btns: Array[Button] = []
var _cloud_qual_btns: Array[Button] = []
var _audio_sliders: Dictionary = {}       # String -> HSlider
var _audio_val_labels: Dictionary = {}    # String -> Label
var _fov_slider: HSlider = null
var _fov_val_label: Label = null
var _sens_slider: HSlider = null
var _sens_val_label: Label = null
var _settings_status_label: Label = null


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_theme = HudIcons.build_parchment_theme()
	if profile == null and Game != null and Game.profile != null:
		profile = Game.profile
		_connect_profile()
		config.apply_profile_defaults(profile)
	else:
		config.validate()
	_build_ui()
	_sync_all_controls()
	refresh_profile_summary()
	visible = false
	if _root != null:
		_root.visible = false


func _exit_tree() -> void:
	_disconnect_profile()


## Bind live UserSettings, Captain Profile, and optional scene root for live Apply.
func bind(p_settings: UserSettings, p_profile: Profile = null, p_scene_root: Node = null) -> void:
	_disconnect_profile()
	user_settings = p_settings
	if p_profile != null:
		profile = p_profile
	elif Game != null and Game.profile != null:
		profile = Game.profile
	else:
		profile = null
	scene_root = p_scene_root
	_connect_profile()
	if profile != null:
		config.apply_profile_defaults(profile)
	else:
		config.validate()
	_sync_all_controls()
	refresh_profile_summary()


## Open the Title Menu overlay on `page` and reveal the cursor when not headless.
func open_menu(page: Page = Page.LANDING) -> void:
	var was_open := is_open
	is_open = true
	visible = true
	if _root != null:
		_root.visible = true
	show_page(page)
	refresh_profile_summary()
	_sync_all_controls()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not was_open and Audio != null:
		Audio.play_sfx(&"ui_open", Vector3.INF, -2.5)


## Close the Title Menu overlay cleanly.
func close_menu() -> void:
	var was_open := is_open
	is_open = false
	visible = false
	if _root != null:
		_root.visible = false
	if was_open and Audio != null:
		Audio.play_sfx(&"ui_back", Vector3.INF, -3.0)


## Switch visible Title Menu view between LANDING, SETUP, COOP, and SETTINGS.
func show_page(page: Page) -> void:
	current_page = page
	if page == Page.COOP:
		config.mode = SessionConfig.MODE_COOP
		config.validate()
	elif page == Page.SETUP and config.mode == SessionConfig.MODE_COOP:
		config.mode = SessionConfig.MODE_ADVENTURE
		config.validate()
	for key: int in _pages:
		var ctrl := _pages[key] as Control
		if ctrl != null:
			ctrl.visible = (key == int(page))
	_sync_all_controls()
	if page == Page.LANDING:
		refresh_profile_summary()


## Update status/error readout across Landing, Setup, Co-op, and Settings views.
func set_status_message(msg: String) -> void:
	_status_message = _to_ascii(msg.strip_edges())
	if _landing_status_label != null:
		_landing_status_label.text = _status_message if _status_message != "" else "Live 3D Harbour Ready - Choose Your Voyage"
	if _coop_status_label != null:
		_coop_status_label.text = _status_message if _status_message != "" else "Ready for LAN or Direct-IP crew session."
	if _setup_status_label != null:
		_setup_status_label.text = _status_message if _status_message != "" else "Live harbour preview updates as you configure."
	if _settings_status_label != null and _status_message != "":
		_settings_status_label.text = _status_message


## Return the most recently set strict-ASCII status message.
func get_status_message() -> String:
	return _status_message


## Refresh the Captain Profile summary badge (Gold, Voyages, Chests, Ship Name).
func refresh_profile_summary() -> void:
	var prof := profile if profile != null else (Game.profile if Game != null else null)
	var gold := 0
	var voyages := 0
	var chests := 0
	var ship_nm := config.ship_name
	var cls_name := String(config.get_ship_spec().get("name", "Sloop"))
	if prof != null:
		gold = int(prof.data.get("gold", 0))
		var stats := prof.get_stats()
		voyages = int(stats.get("voyages_completed", 0))
		chests = int(stats.get("chests_sold", 0))
		if ship_nm.is_empty():
			ship_nm = prof.get_ship_name()
	if _profile_ship_label != null:
		_profile_ship_label.text = _to_ascii("Vessel: %s  (%s)" % [ship_nm, cls_name])
	if _profile_stats_label != null:
		_profile_stats_label.text = _to_ascii(
			"%d Gold  |  %d Voyages  |  %d Chests Sold" % [gold, voyages, chests]
		)


# ==============================================================================
# Programmatic Configuration API (also wired to UI controls & tests)
# ==============================================================================

func select_mode(mode_id: StringName) -> void:
	if not SessionConfig.VALID_MODES.has(mode_id):
		return
	config.mode = mode_id
	config.validate()
	_sync_all_controls()
	_emit_preview_changed()


func select_ship_class(cls: StringName) -> void:
	if cls != &"sloop" and cls != &"brigantine":
		return
	config.ship_class = cls
	config.validate()
	_sync_all_controls()
	refresh_profile_summary()
	_emit_preview_changed()


func select_spawn_outpost(outpost_id: StringName) -> void:
	config.spawn_outpost_id = outpost_id
	config.validate()
	_sync_all_controls()
	_emit_preview_changed()


func select_crew_count(count: int) -> void:
	config.crew_count = clampi(count, 0, 3)
	config.validate()
	_sync_all_controls()
	_emit_preview_changed()


func select_time_preset(preset: StringName) -> void:
	config.time_preset = preset
	config.validate()
	_sync_all_controls()
	_emit_preview_changed()


func select_weather_preset(preset: StringName) -> void:
	config.weather_preset = preset
	config.validate()
	_sync_all_controls()
	_emit_preview_changed()


func select_difficulty(diff: StringName) -> void:
	config.difficulty = diff
	config.validate()
	_sync_all_controls()
	_emit_preview_changed()


func select_starting_emissary(comp: StringName) -> void:
	config.starting_emissary = comp
	config.validate()
	_sync_all_controls()
	_emit_preview_changed()


func set_ship_name(raw_name: String) -> void:
	config.ship_name = Profile.sanitize_ship_name(raw_name)
	config.validate()
	_sync_all_controls()
	refresh_profile_summary()
	_emit_preview_changed()


func cycle_random_ship_name() -> String:
	var presets := Profile.PRESET_SHIP_NAMES
	if presets.is_empty():
		return config.ship_name
	var idx := presets.find(config.ship_name)
	var next_name: String = presets[(idx + 1) % presets.size()]
	set_ship_name(next_name)
	return next_name


func set_coop_address(addr: String) -> void:
	config.coop_address = addr
	config.validate()
	_sync_coop_controls()


func set_coop_port(port: int) -> void:
	config.coop_port = port
	config.validate()
	_sync_coop_controls()


## Finalize active `SessionConfig` and emit `start_game_requested`.
func trigger_set_sail() -> void:
	_pull_text_edits_into_config()
	config.validate()
	if Audio != null:
		Audio.play_sfx(&"ui_select", Vector3.INF, -1.5)
	start_game_requested.emit(config.duplicate_config())


## Configure Co-op Host session from lobby inputs and emit `start_game_requested`.
func trigger_coop_host() -> void:
	config.mode = SessionConfig.MODE_COOP
	config.coop_role = &"host"
	_pull_text_edits_into_config()
	config.validate()
	_sync_all_controls()
	set_status_message("Launching Co-op Host on port %d..." % config.coop_port)
	if Audio != null:
		Audio.play_sfx(&"ui_select", Vector3.INF, -1.5)
	start_game_requested.emit(config.duplicate_config())


## Configure Co-op Join session from lobby inputs and emit `start_game_requested`.
func trigger_coop_join() -> void:
	config.mode = SessionConfig.MODE_COOP
	config.coop_role = &"join"
	_pull_text_edits_into_config()
	config.validate()
	_sync_all_controls()
	set_status_message("Joining crew at %s:%d..." % [config.coop_address, config.coop_port])
	if Audio != null:
		Audio.play_sfx(&"ui_select", Vector3.INF, -1.5)
	start_game_requested.emit(config.duplicate_config())


## Apply Ocean Quality preset (0=Low, 1=Med, 2=High) to UserSettings & live Ocean.
func set_ocean_quality(level: int) -> void:
	var lv := clampi(level, 0, 2)
	if user_settings != null:
		user_settings.data["ocean_quality"] = lv
	if Ocean.current != null:
		Ocean.current.quality = lv as Ocean.Quality
	_sync_settings_controls()
	settings_changed.emit()


## Apply Cloud Quality preset (0=Low, 1=Med, 2=High) to UserSettings & live SkyRig.
func set_cloud_quality(level: int) -> void:
	var lv := clampi(level, 0, 2)
	if user_settings != null:
		user_settings.data["cloud_quality"] = lv
	if scene_root != null and is_instance_valid(scene_root):
		for n in scene_root.find_children("*", "", true, false):
			if n.get(&"cloud_quality") != null and n.has_method(&"cloud_light_at"):
				n.set(&"cloud_quality", lv)
				break
	_sync_settings_controls()
	settings_changed.emit()


## Apply all active UserSettings immediately and optionally persist to disk.
func apply_and_save_settings(persist: bool = true) -> void:
	if user_settings != null:
		user_settings.apply_all(scene_root)
		if persist:
			user_settings.save()
	if _settings_status_label != null:
		_settings_status_label.text = "Settings saved and applied."
	if Audio != null:
		Audio.play_sfx(&"ui_select", Vector3.INF, -2.5)
	settings_changed.emit()


# ==============================================================================
# Input Handling
# ==============================================================================

func _input(event: InputEvent) -> void:
	if not is_open:
		return
	var is_esc := event.is_action_pressed(&"pause")
	if not is_esc and event is InputEventKey:
		var kev := event as InputEventKey
		if kev.pressed and not kev.echo and kev.physical_keycode == KEY_ESCAPE:
			is_esc = true
	if is_esc:
		if current_page != Page.LANDING:
			if Audio != null:
				Audio.play_sfx(&"ui_back", Vector3.INF, -3.0)
			show_page(Page.LANDING)
		get_viewport().set_input_as_handled()


# ==============================================================================
# UI Construction
# ==============================================================================

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "TitleMenuRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = _theme
	add_child(_root)

	# Soft left-side atmospheric vignette keeping the right 3D ocean/harbour vista clear.
	_backdrop = _LeftVignetteBackdrop.new()
	_backdrop.name = "LeftVignetteBackdrop"
	_root.add_child(_backdrop)

	_pages[int(Page.LANDING)] = _build_landing_page()
	_pages[int(Page.SETUP)] = _build_setup_page()
	_pages[int(Page.COOP)] = _build_coop_page()
	_pages[int(Page.SETTINGS)] = _build_settings_page()

	for key: int in _pages:
		var ctrl := _pages[key] as Control
		ctrl.visible = (key == int(current_page))
		_root.add_child(ctrl)


func _build_landing_page() -> Control:
	var holder := Control.new()
	holder.name = "LandingPage"
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var column := VBoxContainer.new()
	column.name = "LandingColumn"
	column.anchor_left = 0.028
	column.anchor_right = 0.368
	column.anchor_top = 0.055
	column.anchor_bottom = 0.945
	column.custom_minimum_size = Vector2(456.0, 0.0)
	column.add_theme_constant_override("separation", 14)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.add_child(column)

	# 1. Dramatic Pirate Title Masthead (double crimson & gold parchment frame)
	var mast_outer := PanelContainer.new()
	mast_outer.name = "TitleMasthead"
	var outer_sb := HudIcons.make_parchment_box(
		Color(0.93, 0.86, 0.71, 0.93),
		HudIcons.COL_CRIMSON,
		3,
		10,
		5,
		5
	)
	outer_sb.shadow_size = 10
	outer_sb.shadow_offset = Vector2(0.0, 4.0)
	mast_outer.add_theme_stylebox_override("panel", outer_sb)
	column.add_child(mast_outer)

	var mast_inner := PanelContainer.new()
	var inner_sb := StyleBoxFlat.new()
	inner_sb.bg_color = Color(0.96, 0.90, 0.77, 0.20)
	inner_sb.border_color = HudIcons.COL_GOLD
	inner_sb.set_border_width_all(2)
	inner_sb.set_corner_radius_all(6)
	inner_sb.content_margin_left = 18
	inner_sb.content_margin_right = 18
	inner_sb.content_margin_top = 16
	inner_sb.content_margin_bottom = 16
	mast_inner.add_theme_stylebox_override("panel", inner_sb)
	mast_outer.add_child(mast_inner)

	var mast_v := VBoxContainer.new()
	mast_v.add_theme_constant_override("separation", 7)
	mast_inner.add_child(mast_v)

	var mast_top := HBoxContainer.new()
	mast_top.alignment = BoxContainer.ALIGNMENT_CENTER
	mast_top.add_theme_constant_override("separation", 12)
	mast_v.add_child(mast_top)

	var emblem := _TitleEmblem.new()
	emblem.name = "TitleEmblem"
	mast_top.add_child(emblem)

	var title_lbl := Label.new()
	title_lbl.name = "TitleHeading"
	title_lbl.text = "SEA OF SCOUNDRELS"
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 30)
	title_lbl.add_theme_color_override("font_color", HudIcons.COL_INK)
	title_lbl.add_theme_color_override("font_shadow_color", Color(0.20, 0.13, 0.08, 0.30))
	title_lbl.add_theme_constant_override("shadow_offset_x", 1)
	title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	mast_top.add_child(title_lbl)

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(280.0, 2.0)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule.color = HudIcons.COL_BRASS
	mast_v.add_child(rule)

	var sub_lbl := Label.new()
	sub_lbl.name = "TitleSubtitle"
	sub_lbl.text = "HIGH-SEAS VOYAGES, CO-OP CREWS & PLUNDER"
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_lbl.add_theme_font_size_override("font_size", 13)
	sub_lbl.add_theme_color_override("font_color", HudIcons.COL_CRIMSON)
	mast_v.add_child(sub_lbl)

	# 2. Captain Profile Badge
	var prof_panel := PanelContainer.new()
	prof_panel.name = "ProfileSummaryPanel"
	prof_panel.add_theme_stylebox_override("panel",
		HudIcons.make_parchment_box(Color(0.91, 0.84, 0.69, 0.90), HudIcons.COL_BRASS, 2, 7, 16, 10))
	column.add_child(prof_panel)

	var prof_v := VBoxContainer.new()
	prof_v.add_theme_constant_override("separation", 3)
	prof_panel.add_child(prof_v)

	_profile_ship_label = Label.new()
	_profile_ship_label.name = "ProfileShipLabel"
	_profile_ship_label.text = "Vessel: The Gilded Scoundrel  (Sloop)"
	_profile_ship_label.add_theme_font_size_override("font_size", 15)
	_profile_ship_label.add_theme_color_override("font_color", HudIcons.COL_INK)
	prof_v.add_child(_profile_ship_label)

	_profile_stats_label = Label.new()
	_profile_stats_label.name = "ProfileStatsLabel"
	_profile_stats_label.text = "0 Gold  |  0 Voyages  |  0 Chests Sold"
	_profile_stats_label.add_theme_font_size_override("font_size", 13)
	_profile_stats_label.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	prof_v.add_child(_profile_stats_label)

	# 3. Main Vertical Action Stack
	var stack_panel := PanelContainer.new()
	stack_panel.name = "MainActionStack"
	stack_panel.add_theme_stylebox_override("panel",
		HudIcons.make_parchment_box(Color(0.92, 0.85, 0.70, 0.92), HudIcons.COL_INK, 2, 9, 18, 16))
	column.add_child(stack_panel)

	var stack_v := VBoxContainer.new()
	stack_v.add_theme_constant_override("separation", 10)
	stack_panel.add_child(stack_v)

	# Primary Adventure row + 1-click Quick Sail CTA
	var adv_row := HBoxContainer.new()
	adv_row.add_theme_constant_override("separation", 8)
	stack_v.add_child(adv_row)

	var btn_adv := _make_menu_button("BtnAdventure", "Set Sail - Adventure", 46.0, 17)
	btn_adv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_cta_button(btn_adv)
	btn_adv.pressed.connect(func() -> void:
		_play_select()
		select_mode(SessionConfig.MODE_ADVENTURE)
		show_page(Page.SETUP)
	)
	adv_row.add_child(btn_adv)

	var btn_quick := _make_menu_button("BtnQuickSail", "Quick Sail", 46.0, 15)
	btn_quick.custom_minimum_size = Vector2(124.0, 46.0)
	btn_quick.tooltip_text = "Launch Open-Seas Adventure immediately with current vessel"
	_style_gold_button(btn_quick)
	btn_quick.pressed.connect(func() -> void:
		config.mode = SessionConfig.MODE_ADVENTURE
		trigger_set_sail()
	)
	adv_row.add_child(btn_quick)

	var btn_tut := _make_menu_button("BtnTutorial", "Maiden Voyage (Tutorial)", 42.0, 16)
	btn_tut.tooltip_text = "Guided 8-step interactive pirate tutorial from Port Scoundrel to Cutlass Cay"
	btn_tut.pressed.connect(func() -> void:
		_play_select()
		select_mode(SessionConfig.MODE_TUTORIAL)
		show_page(Page.SETUP)
	)
	stack_v.add_child(btn_tut)

	var btn_skirm := _make_menu_button("BtnSkirmish", "High-Seas Naval Skirmish", 42.0, 16)
	btn_skirm.tooltip_text = "Instant open-sea naval combat waves escalating to the Abyssal Leviathan"
	btn_skirm.pressed.connect(func() -> void:
		_play_select()
		select_mode(SessionConfig.MODE_SKIRMISH)
		show_page(Page.SETUP)
	)
	stack_v.add_child(btn_skirm)

	var btn_coop := _make_menu_button("BtnCoop", "Co-op Crew (Host / Join)", 42.0, 16)
	btn_coop.tooltip_text = "Host a LAN/Direct-IP crew server or join a friend's ship"
	btn_coop.pressed.connect(func() -> void:
		_play_select()
		show_page(Page.COOP)
	)
	stack_v.add_child(btn_coop)

	var btn_set := _make_menu_button("BtnSettings", "Settings & Controls", 40.0, 15)
	btn_set.pressed.connect(func() -> void:
		_play_select()
		show_page(Page.SETTINGS)
	)
	stack_v.add_child(btn_set)

	var btn_quit := _make_menu_button("BtnQuit", "Quit to Desktop", 38.0, 15)
	btn_quit.pressed.connect(_on_quit_pressed)
	stack_v.add_child(btn_quit)

	# 4. Subtle Footer Status Strip
	_landing_status_label = Label.new()
	_landing_status_label.name = "LandingStatusLabel"
	_landing_status_label.text = "Live 3D Harbour Ready - Choose Your Voyage"
	_landing_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_landing_status_label.add_theme_font_size_override("font_size", 13)
	_landing_status_label.add_theme_color_override("font_color", Color(0.96, 0.90, 0.76, 0.92))
	_landing_status_label.add_theme_color_override("font_shadow_color", Color(0.05, 0.03, 0.02, 0.85))
	_landing_status_label.add_theme_constant_override("shadow_offset_x", 1)
	_landing_status_label.add_theme_constant_override("shadow_offset_y", 1)
	column.add_child(_landing_status_label)

	return holder


func _build_setup_page() -> Control:
	var holder := Control.new()
	holder.name = "SetupPage"
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := PanelContainer.new()
	panel.name = "SetupConfiguratorPanel"
	panel.anchor_left = 0.024
	panel.anchor_right = 0.568
	panel.anchor_top = 0.035
	panel.anchor_bottom = 0.965
	panel.add_theme_stylebox_override("panel",
		HudIcons.make_parchment_box(Color(0.93, 0.86, 0.71, 0.94), HudIcons.COL_INK, 3, 10, 22, 16))
	holder.add_child(panel)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 10)
	panel.add_child(root_v)

	# Header bar
	var hdr_row := HBoxContainer.new()
	hdr_row.add_theme_constant_override("separation", 12)
	root_v.add_child(hdr_row)

	var hdr_lbl := Label.new()
	hdr_lbl.name = "SetupHeading"
	hdr_lbl.text = "PRE-SAIL VOYAGE CONFIGURATOR"
	hdr_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_lbl.add_theme_font_size_override("font_size", 22)
	hdr_lbl.add_theme_color_override("font_color", HudIcons.COL_INK)
	hdr_row.add_child(hdr_lbl)

	_setup_header_pill = Label.new()
	_setup_header_pill.name = "SetupSummaryPill"
	_setup_header_pill.text = "Adventure  |  Sloop"
	_setup_header_pill.add_theme_font_size_override("font_size", 14)
	_setup_header_pill.add_theme_color_override("font_color", HudIcons.COL_CRIMSON)
	hdr_row.add_child(_setup_header_pill)

	# Mode selector bar (Adventure / Tutorial / Naval Skirmish)
	var mode_card := _make_sub_card()
	var mode_v := VBoxContainer.new()
	mode_v.add_theme_constant_override("separation", 6)
	mode_card.add_child(mode_v)
	mode_v.add_child(_make_section_label("GAME MODE"))

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	mode_v.add_child(mode_row)
	_mode_btns.clear()
	for mode_id: StringName in [SessionConfig.MODE_ADVENTURE, SessionConfig.MODE_TUTORIAL, SessionConfig.MODE_SKIRMISH]:
		var mlabel := _lookup_mode_short(mode_id)
		var btn := _make_menu_button("ModeBtn_" + String(mode_id), mlabel, 36.0, 14)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var mid := mode_id
		btn.pressed.connect(func() -> void:
			_play_select()
			select_mode(mid)
		)
		mode_row.add_child(btn)
		_mode_btns[mode_id] = btn

	_mode_desc_label = Label.new()
	_mode_desc_label.name = "ModeDescLabel"
	_mode_desc_label.text = ""
	_mode_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_desc_label.add_theme_font_size_override("font_size", 13)
	_mode_desc_label.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	mode_v.add_child(_mode_desc_label)
	root_v.add_child(mode_card)

	# Scrollable two-column configurator body
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_v.add_child(scroll)

	var cols := HBoxContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 12)
	scroll.add_child(cols)

	# --- Left Column: Ship Class, Vessel Name, Crew Roster ---
	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 10)
	cols.add_child(left_col)

	# Ship Class card
	var ship_card := _make_sub_card()
	var ship_v := VBoxContainer.new()
	ship_v.add_theme_constant_override("separation", 6)
	ship_card.add_child(ship_v)
	ship_v.add_child(_make_section_label("SHIP CLASS"))

	var ship_row := HBoxContainer.new()
	ship_row.add_theme_constant_override("separation", 8)
	ship_v.add_child(ship_row)
	_ship_btns.clear()
	for spec in SessionConfig.SHIP_SPECS:
		var sid: StringName = spec["id"]
		var btn := _make_menu_button(
			"ShipBtn_" + String(sid),
			"%s [%s]" % [String(spec["name"]), String(spec["crew_rec"])],
			38.0,
			13
		)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cap_sid := sid
		btn.pressed.connect(func() -> void:
			_play_select()
			select_ship_class(cap_sid)
		)
		ship_row.add_child(btn)
		_ship_btns[sid] = btn

	_ship_desc_label = Label.new()
	_ship_desc_label.name = "ShipDescLabel"
	_ship_desc_label.text = ""
	_ship_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ship_desc_label.add_theme_font_size_override("font_size", 13)
	_ship_desc_label.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	ship_v.add_child(_ship_desc_label)

	# Vessel Name row inside ship card
	ship_v.add_child(_make_section_label("VESSEL NAME"))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	ship_v.add_child(name_row)

	_ship_name_edit = LineEdit.new()
	_ship_name_edit.name = "ShipNameEdit"
	_ship_name_edit.text = config.ship_name
	_ship_name_edit.placeholder_text = "Enter ship name..."
	_ship_name_edit.max_length = Profile.MAX_SHIP_NAME_LEN
	_ship_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ship_name_edit.text_submitted.connect(func(new_text: String) -> void:
		set_ship_name(new_text)
	)
	_ship_name_edit.text_changed.connect(func(new_text: String) -> void:
		if _syncing_ui:
			return
		var clean := Profile.sanitize_ship_name(new_text)
		if clean != config.ship_name:
			config.ship_name = clean
			refresh_profile_summary()
			_emit_preview_changed()
	)
	name_row.add_child(_ship_name_edit)

	var rnd_btn := _make_menu_button("RandomShipNameBtn", "Random", 34.0, 13)
	rnd_btn.custom_minimum_size = Vector2(88.0, 34.0)
	rnd_btn.tooltip_text = "Cycle preset scoundrel vessel names"
	rnd_btn.pressed.connect(func() -> void:
		_play_select()
		cycle_random_ship_name()
	)
	name_row.add_child(rnd_btn)
	left_col.add_child(ship_card)

	# Crew Roster card
	var crew_card := _make_sub_card()
	var crew_v := VBoxContainer.new()
	crew_v.add_theme_constant_override("separation", 6)
	crew_card.add_child(crew_v)
	crew_v.add_child(_make_section_label("CREW ROSTER"))

	var crew_grid := GridContainer.new()
	crew_grid.columns = 2
	crew_grid.add_theme_constant_override("h_separation", 8)
	crew_grid.add_theme_constant_override("v_separation", 6)
	crew_v.add_child(crew_grid)
	_crew_btns.clear()
	for preset in SessionConfig.CREW_PRESETS:
		var cnt := int(preset["count"])
		var btn := _make_menu_button("CrewBtn_%d" % cnt, String(preset["short"]), 35.0, 13)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cap_cnt := cnt
		btn.pressed.connect(func() -> void:
			_play_select()
			select_crew_count(cap_cnt)
		)
		crew_grid.add_child(btn)
		_crew_btns[cnt] = btn

	_crew_desc_label = Label.new()
	_crew_desc_label.name = "CrewDescLabel"
	_crew_desc_label.text = ""
	_crew_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_crew_desc_label.add_theme_font_size_override("font_size", 13)
	_crew_desc_label.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	crew_v.add_child(_crew_desc_label)
	left_col.add_child(crew_card)

	# --- Right Column: Spawn Outpost, Time, Weather, Difficulty, Emissary ---
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 10)
	cols.add_child(right_col)

	# Spawn Outpost card
	var out_card := _make_sub_card()
	var out_v := VBoxContainer.new()
	out_v.add_theme_constant_override("separation", 6)
	out_card.add_child(out_v)
	out_v.add_child(_make_section_label("SPAWN OUTPOST"))

	var out_row := VBoxContainer.new()
	out_row.add_theme_constant_override("separation", 5)
	out_v.add_child(out_row)
	_outpost_btns.clear()
	for spec in SessionConfig.OUTPOST_SPECS:
		var oid: StringName = spec["id"]
		var btn := _make_menu_button(
			"OutpostBtn_" + String(oid),
			"%s  (%s)" % [String(spec["name"]), String(spec["region"])],
			33.0,
			13
		)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cap_oid := oid
		btn.pressed.connect(func() -> void:
			_play_select()
			select_spawn_outpost(cap_oid)
		)
		out_row.add_child(btn)
		_outpost_btns[oid] = btn

	_outpost_desc_label = Label.new()
	_outpost_desc_label.name = "OutpostDescLabel"
	_outpost_desc_label.text = ""
	_outpost_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_outpost_desc_label.add_theme_font_size_override("font_size", 13)
	_outpost_desc_label.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	out_v.add_child(_outpost_desc_label)
	right_col.add_child(out_card)

	# Seas & Conditions card
	var sea_card := _make_sub_card()
	var sea_v := VBoxContainer.new()
	sea_v.add_theme_constant_override("separation", 6)
	sea_card.add_child(sea_v)
	sea_v.add_child(_make_section_label("TIME OF DAY"))

	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 5)
	sea_v.add_child(time_row)
	_time_btns.clear()
	for preset in SessionConfig.TIME_PRESETS:
		var tid: StringName = preset["id"]
		var btn := _make_menu_button("TimeBtn_" + String(tid), String(preset["short"]), 32.0, 13)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cap_tid := tid
		btn.pressed.connect(func() -> void:
			_play_select()
			select_time_preset(cap_tid)
		)
		time_row.add_child(btn)
		_time_btns[tid] = btn

	sea_v.add_child(_make_section_label("WEATHER"))
	var wx_row := HBoxContainer.new()
	wx_row.add_theme_constant_override("separation", 5)
	sea_v.add_child(wx_row)
	_weather_btns.clear()
	for preset in SessionConfig.WEATHER_PRESETS:
		var wid: StringName = preset["id"]
		var btn := _make_menu_button("WeatherBtn_" + String(wid), String(preset["short"]), 32.0, 13)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cap_wid := wid
		btn.pressed.connect(func() -> void:
			_play_select()
			select_weather_preset(cap_wid)
		)
		wx_row.add_child(btn)
		_weather_btns[wid] = btn

	sea_v.add_child(_make_section_label("DIFFICULTY"))
	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 5)
	sea_v.add_child(diff_row)
	_diff_btns.clear()
	for preset in SessionConfig.DIFFICULTY_PRESETS:
		var did: StringName = preset["id"]
		var btn := _make_menu_button("DiffBtn_" + String(did), String(preset["short"]), 32.0, 13)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cap_did := did
		btn.pressed.connect(func() -> void:
			_play_select()
			select_difficulty(cap_did)
		)
		diff_row.add_child(btn)
		_diff_btns[did] = btn

	_diff_desc_label = Label.new()
	_diff_desc_label.name = "DifficultyDescLabel"
	_diff_desc_label.text = ""
	_diff_desc_label.add_theme_font_size_override("font_size", 12)
	_diff_desc_label.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	sea_v.add_child(_diff_desc_label)

	sea_v.add_child(_make_section_label("STARTING EMISSARY FLAG"))
	var em_grid := GridContainer.new()
	em_grid.columns = 2
	em_grid.add_theme_constant_override("h_separation", 6)
	em_grid.add_theme_constant_override("v_separation", 5)
	sea_v.add_child(em_grid)
	_emissary_btns.clear()
	for preset in SessionConfig.EMISSARY_PRESETS:
		var eid: StringName = preset["id"]
		var suffix := "none" if eid == &"" else String(eid)
		var btn := _make_menu_button("EmissaryBtn_" + suffix, String(preset["short"]), 32.0, 13)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cap_eid := eid
		btn.pressed.connect(func() -> void:
			_play_select()
			select_starting_emissary(cap_eid)
		)
		em_grid.add_child(btn)
		_emissary_btns[eid] = btn

	_emissary_desc_label = Label.new()
	_emissary_desc_label.name = "EmissaryDescLabel"
	_emissary_desc_label.text = ""
	_emissary_desc_label.add_theme_font_size_override("font_size", 12)
	_emissary_desc_label.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	sea_v.add_child(_emissary_desc_label)
	right_col.add_child(sea_card)

	# Footer bar: Back + Status + prominent SET SAIL! CTA
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	root_v.add_child(foot)

	var back_btn := _make_menu_button("SetupBackBtn", "Back", 42.0, 15)
	back_btn.custom_minimum_size = Vector2(116.0, 42.0)
	back_btn.pressed.connect(func() -> void:
		_play_back()
		show_page(Page.LANDING)
	)
	foot.add_child(back_btn)

	_setup_status_label = Label.new()
	_setup_status_label.name = "SetupStatusLabel"
	_setup_status_label.text = "Live harbour preview updates as you configure."
	_setup_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_setup_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_setup_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_setup_status_label.add_theme_font_size_override("font_size", 13)
	_setup_status_label.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	foot.add_child(_setup_status_label)

	var sail_btn := _make_menu_button("SetSailBtn", "SET SAIL!", 44.0, 18)
	sail_btn.custom_minimum_size = Vector2(210.0, 44.0)
	_style_cta_button(sail_btn)
	sail_btn.pressed.connect(trigger_set_sail)
	foot.add_child(sail_btn)

	return holder


func _build_coop_page() -> Control:
	var holder := Control.new()
	holder.name = "CoopPage"
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := PanelContainer.new()
	panel.name = "CoopLobbyPanel"
	panel.anchor_left = 0.024
	panel.anchor_right = 0.568
	panel.anchor_top = 0.05
	panel.anchor_bottom = 0.95
	panel.add_theme_stylebox_override("panel",
		HudIcons.make_parchment_box(Color(0.93, 0.86, 0.71, 0.94), HudIcons.COL_INK, 3, 10, 22, 16))
	holder.add_child(panel)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 12)
	panel.add_child(root_v)

	var hdr := Label.new()
	hdr.name = "CoopHeading"
	hdr.text = "CO-OP CREW LOBBY (LAN / DIRECT IP)"
	hdr.add_theme_font_size_override("font_size", 22)
	hdr.add_theme_color_override("font_color", HudIcons.COL_INK)
	root_v.add_child(hdr)

	var sub := Label.new()
	sub.text = "Up to 4 pirates sail aboard one vessel. AI crewmates automatically yield slots as friends board."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	root_v.add_child(sub)

	var cards := HBoxContainer.new()
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 12)
	root_v.add_child(cards)

	# --- Left Card: Host Crew Session ---
	var host_card := _make_sub_card()
	host_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 8)
	host_card.add_child(hv)
	hv.add_child(_make_section_label("HOST CREW SESSION"))

	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	var hp_lbl := Label.new()
	hp_lbl.text = "Server Port:"
	hp_lbl.custom_minimum_size = Vector2(102.0, 0.0)
	hp_lbl.add_theme_font_size_override("font_size", 14)
	hp_row.add_child(hp_lbl)
	_coop_host_port_edit = LineEdit.new()
	_coop_host_port_edit.name = "CoopHostPortEdit"
	_coop_host_port_edit.text = str(config.coop_port)
	_coop_host_port_edit.placeholder_text = str(Net.DEFAULT_PORT)
	_coop_host_port_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_row.add_child(_coop_host_port_edit)
	hv.add_child(hp_row)

	hv.add_child(_make_section_label("SHIP CLASS"))
	var cship_row := HBoxContainer.new()
	cship_row.add_theme_constant_override("separation", 6)
	hv.add_child(cship_row)
	_coop_ship_btns.clear()
	for spec in SessionConfig.SHIP_SPECS:
		var sid: StringName = spec["id"]
		var btn := _make_menu_button("CoopShipBtn_" + String(sid), String(spec["name"]), 34.0, 14)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cap_sid := sid
		btn.pressed.connect(func() -> void:
			_play_select()
			select_ship_class(cap_sid)
		)
		cship_row.add_child(btn)
		_coop_ship_btns[sid] = btn

	hv.add_child(_make_section_label("SPAWN OUTPOST"))
	var cout_box := VBoxContainer.new()
	cout_box.add_theme_constant_override("separation", 5)
	hv.add_child(cout_box)
	_coop_outpost_btns.clear()
	for spec in SessionConfig.OUTPOST_SPECS:
		var oid: StringName = spec["id"]
		var btn := _make_menu_button("CoopOutpostBtn_" + String(oid), String(spec["name"]), 32.0, 13)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cap_oid := oid
		btn.pressed.connect(func() -> void:
			_play_select()
			select_spawn_outpost(cap_oid)
		)
		cout_box.add_child(btn)
		_coop_outpost_btns[oid] = btn

	hv.add_child(_make_section_label("SHIP NAME"))
	var cname_row := HBoxContainer.new()
	cname_row.add_theme_constant_override("separation", 6)
	hv.add_child(cname_row)
	_coop_ship_name_edit = LineEdit.new()
	_coop_ship_name_edit.name = "CoopShipNameEdit"
	_coop_ship_name_edit.text = config.ship_name
	_coop_ship_name_edit.max_length = Profile.MAX_SHIP_NAME_LEN
	_coop_ship_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_coop_ship_name_edit.text_submitted.connect(func(t: String) -> void: set_ship_name(t))
	_coop_ship_name_edit.text_changed.connect(func(new_text: String) -> void:
		if _syncing_ui:
			return
		var clean := Profile.sanitize_ship_name(new_text)
		if clean != config.ship_name:
			config.ship_name = clean
			refresh_profile_summary()
			_emit_preview_changed()
	)
	cname_row.add_child(_coop_ship_name_edit)

	var crnd := _make_menu_button("CoopRandomNameBtn", "Random", 32.0, 13)
	crnd.custom_minimum_size = Vector2(78.0, 32.0)
	crnd.pressed.connect(func() -> void:
		_play_select()
		cycle_random_ship_name()
	)
	cname_row.add_child(crnd)

	hv.add_child(_make_section_label("AI FILL CREW (0-3)"))
	var ccrew_row := HBoxContainer.new()
	ccrew_row.add_theme_constant_override("separation", 5)
	hv.add_child(ccrew_row)
	_coop_crew_btns.clear()
	for i in 4:
		var btn := _make_menu_button("CoopCrewBtn_%d" % i, str(i), 32.0, 13)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cap_i := i
		btn.pressed.connect(func() -> void:
			_play_select()
			select_crew_count(cap_i)
		)
		ccrew_row.add_child(btn)
		_coop_crew_btns[i] = btn

	_coop_crew_desc_label = Label.new()
	_coop_crew_desc_label.text = ""
	_coop_crew_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_coop_crew_desc_label.add_theme_font_size_override("font_size", 12)
	_coop_crew_desc_label.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	hv.add_child(_coop_crew_desc_label)

	var host_spacer := Control.new()
	host_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hv.add_child(host_spacer)

	var host_btn := _make_menu_button("BtnCoopHost", "Host & Set Sail", 42.0, 16)
	_style_cta_button(host_btn)
	host_btn.pressed.connect(trigger_coop_host)
	hv.add_child(host_btn)
	cards.add_child(host_card)

	# --- Right Card: Join Friend's Crew ---
	var join_card := _make_sub_card()
	join_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var jv := VBoxContainer.new()
	jv.add_theme_constant_override("separation", 10)
	join_card.add_child(jv)
	jv.add_child(_make_section_label("JOIN FRIEND'S CREW"))

	var jinfo := Label.new()
	jinfo.text = "Enter your captain's LAN or Direct-IP host address and UDP port to board their ship directly."
	jinfo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	jinfo.add_theme_font_size_override("font_size", 13)
	jinfo.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	jv.add_child(jinfo)

	var ja_lbl := Label.new()
	ja_lbl.text = "Host IP Address:"
	ja_lbl.add_theme_font_size_override("font_size", 14)
	jv.add_child(ja_lbl)

	_coop_join_addr_edit = LineEdit.new()
	_coop_join_addr_edit.name = "CoopJoinAddrEdit"
	_coop_join_addr_edit.text = config.coop_address
	_coop_join_addr_edit.placeholder_text = "127.0.0.1"
	jv.add_child(_coop_join_addr_edit)

	var jp_lbl := Label.new()
	jp_lbl.text = "Host Port:"
	jp_lbl.add_theme_font_size_override("font_size", 14)
	jv.add_child(jp_lbl)

	_coop_join_port_edit = LineEdit.new()
	_coop_join_port_edit.name = "CoopJoinPortEdit"
	_coop_join_port_edit.text = str(config.coop_port)
	_coop_join_port_edit.placeholder_text = str(Net.DEFAULT_PORT)
	jv.add_child(_coop_join_port_edit)

	var status_box := PanelContainer.new()
	status_box.add_theme_stylebox_override("panel",
		HudIcons.make_parchment_box(Color(0.87, 0.79, 0.63, 0.94), HudIcons.COL_TEAL, 2, 6, 12, 10))
	jv.add_child(status_box)

	_coop_status_label = Label.new()
	_coop_status_label.name = "CoopStatusLabel"
	_coop_status_label.text = "Ready for LAN or Direct-IP crew session."
	_coop_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_coop_status_label.add_theme_font_size_override("font_size", 13)
	_coop_status_label.add_theme_color_override("font_color", HudIcons.COL_INK)
	status_box.add_child(_coop_status_label)

	var join_spacer := Control.new()
	join_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	jv.add_child(join_spacer)

	var join_btn := _make_menu_button("BtnCoopJoin", "Join Crew", 42.0, 16)
	_style_gold_button(join_btn)
	join_btn.pressed.connect(trigger_coop_join)
	jv.add_child(join_btn)
	cards.add_child(join_card)

	# Footer bar
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	root_v.add_child(foot)

	var back_btn := _make_menu_button("CoopBackBtn", "Back", 40.0, 15)
	back_btn.custom_minimum_size = Vector2(120.0, 40.0)
	back_btn.pressed.connect(func() -> void:
		_play_back()
		show_page(Page.LANDING)
	)
	foot.add_child(back_btn)

	return holder


func _build_settings_page() -> Control:
	var holder := Control.new()
	holder.name = "SettingsPage"
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := PanelContainer.new()
	panel.name = "SettingsPanel"
	panel.anchor_left = 0.024
	panel.anchor_right = 0.568
	panel.anchor_top = 0.035
	panel.anchor_bottom = 0.965
	panel.add_theme_stylebox_override("panel",
		HudIcons.make_parchment_box(Color(0.93, 0.86, 0.71, 0.94), HudIcons.COL_INK, 3, 10, 22, 16))
	holder.add_child(panel)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 10)
	panel.add_child(root_v)

	var hdr := Label.new()
	hdr.name = "SettingsHeading"
	hdr.text = "SETTINGS & CONTROLS"
	hdr.add_theme_font_size_override("font_size", 22)
	hdr.add_theme_color_override("font_color", HudIcons.COL_INK)
	root_v.add_child(hdr)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_v.add_child(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)

	# 1. Graphics Quality Card
	var gfx_card := _make_sub_card()
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", 8)
	gfx_card.add_child(gv)
	gv.add_child(_make_section_label("GRAPHICS QUALITY"))

	_ocean_qual_btns.clear()
	gv.add_child(_make_quality_picker("Ocean Quality", "SettingsOceanBtn", _ocean_qual_btns, func(lv: int) -> void:
		_play_select()
		set_ocean_quality(lv)
	))
	_cloud_qual_btns.clear()
	gv.add_child(_make_quality_picker("Cloud Quality", "SettingsCloudBtn", _cloud_qual_btns, func(lv: int) -> void:
		_play_select()
		set_cloud_quality(lv)
	))
	body.add_child(gfx_card)

	# 2. Audio Volumes Card
	var aud_card := _make_sub_card()
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 7)
	aud_card.add_child(av)
	av.add_child(_make_section_label("AUDIO MIXER"))

	_audio_sliders.clear()
	_audio_val_labels.clear()
	var bus_specs: Array[Array] = [
		["Master", "master_volume", Audio.BUS_MASTER],
		["Music", "music_volume", Audio.BUS_MUSIC],
		["Ambience", "ambience_volume", Audio.BUS_AMBIENCE],
		["SFX", "sfx_volume", Audio.BUS_SFX],
	]
	for bspec in bus_specs:
		var lbl_name: String = bspec[0]
		var data_key: String = bspec[1]
		var bus_id: StringName = bspec[2]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var l := Label.new()
		l.text = lbl_name
		l.custom_minimum_size = Vector2(118.0, 0.0)
		l.add_theme_font_size_override("font_size", 14)
		row.add_child(l)

		var sl := HSlider.new()
		sl.name = "SettingsSlider_" + lbl_name.to_lower()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.02
		sl.value = 1.0
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var val_lbl := Label.new()
		val_lbl.custom_minimum_size = Vector2(54.0, 0.0)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_lbl.text = "100%"
		val_lbl.add_theme_font_size_override("font_size", 13)
		val_lbl.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)

		var cap_key := data_key
		var cap_bus := bus_id
		var cap_vlbl := val_lbl
		sl.value_changed.connect(func(v: float) -> void:
			cap_vlbl.text = "%d%%" % int(roundf(v * 100.0))
			if _syncing_ui:
				return
			if user_settings != null:
				user_settings.data[cap_key] = v
			if Audio != null:
				Audio.set_bus_volume(cap_bus, v)
		)
		row.add_child(sl)
		row.add_child(val_lbl)
		_audio_sliders[data_key] = sl
		_audio_val_labels[data_key] = val_lbl
		av.add_child(row)
	body.add_child(aud_card)

	# 3. Camera & Controls Sensitivity Card
	var cam_card := _make_sub_card()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	cam_card.add_child(cv)
	cv.add_child(_make_section_label("CAMERA & MOUSE"))

	var fov_row := HBoxContainer.new()
	fov_row.add_theme_constant_override("separation", 10)
	var fov_l := Label.new()
	fov_l.text = "Field of View"
	fov_l.custom_minimum_size = Vector2(138.0, 0.0)
	fov_l.add_theme_font_size_override("font_size", 14)
	fov_row.add_child(fov_l)

	_fov_slider = HSlider.new()
	_fov_slider.name = "SettingsSlider_fov"
	_fov_slider.min_value = 65.0
	_fov_slider.max_value = 100.0
	_fov_slider.step = 1.0
	_fov_slider.value = 80.0
	_fov_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fov_row.add_child(_fov_slider)

	_fov_val_label = Label.new()
	_fov_val_label.custom_minimum_size = Vector2(58.0, 0.0)
	_fov_val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fov_val_label.text = "80 deg"
	_fov_val_label.add_theme_font_size_override("font_size", 13)
	_fov_val_label.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	fov_row.add_child(_fov_val_label)
	_fov_slider.value_changed.connect(func(v: float) -> void:
		_fov_val_label.text = "%d deg" % int(roundf(v))
		if _syncing_ui:
			return
		if user_settings != null:
			user_settings.data["fov"] = v
	)
	cv.add_child(fov_row)

	var sens_row := HBoxContainer.new()
	sens_row.add_theme_constant_override("separation", 10)
	var sens_l := Label.new()
	sens_l.text = "Mouse Sensitivity"
	sens_l.custom_minimum_size = Vector2(138.0, 0.0)
	sens_l.add_theme_font_size_override("font_size", 14)
	sens_row.add_child(sens_l)

	_sens_slider = HSlider.new()
	_sens_slider.name = "SettingsSlider_sens"
	_sens_slider.min_value = 0.0008
	_sens_slider.max_value = 0.0060
	_sens_slider.step = 0.0001
	_sens_slider.value = DEFAULT_SENS
	_sens_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sens_row.add_child(_sens_slider)

	_sens_val_label = Label.new()
	_sens_val_label.custom_minimum_size = Vector2(58.0, 0.0)
	_sens_val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_sens_val_label.text = "1.00x"
	_sens_val_label.add_theme_font_size_override("font_size", 13)
	_sens_val_label.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	sens_row.add_child(_sens_val_label)
	_sens_slider.value_changed.connect(func(v: float) -> void:
		_sens_val_label.text = "%.2fx" % (v / DEFAULT_SENS)
		if _syncing_ui:
			return
		if user_settings != null:
			user_settings.data["mouse_sensitivity"] = v
	)
	cv.add_child(sens_row)
	body.add_child(cam_card)

	# 4. Controls Summary Reference Card
	var ctl_card := _make_sub_card()
	ctl_card.name = "ControlsReferenceCard"
	var ctl_v := VBoxContainer.new()
	ctl_v.name = "TitleControlsList"
	ctl_v.add_theme_constant_override("separation", 4)
	ctl_card.add_child(ctl_v)
	ctl_v.add_child(_make_section_label("CAPTAIN'S CONTROLS"))

	for line_txt: String in CAPTAIN_CONTROLS_LINES:
		var cl := Label.new()
		cl.text = _to_ascii(line_txt)
		cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cl.add_theme_font_size_override("font_size", 13)
		cl.add_theme_color_override("font_color", HudIcons.COL_INK)
		ctl_v.add_child(cl)
	body.add_child(ctl_card)

	# Footer bar
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	root_v.add_child(foot)

	var back_btn := _make_menu_button("SettingsBackBtn", "Back", 40.0, 15)
	back_btn.custom_minimum_size = Vector2(116.0, 40.0)
	back_btn.pressed.connect(func() -> void:
		_play_back()
		show_page(Page.LANDING)
	)
	foot.add_child(back_btn)

	_settings_status_label = Label.new()
	_settings_status_label.name = "SettingsStatusLabel"
	_settings_status_label.text = "Changes apply live across the harbour."
	_settings_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_settings_status_label.add_theme_font_size_override("font_size", 13)
	_settings_status_label.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	foot.add_child(_settings_status_label)

	var apply_btn := _make_menu_button("SettingsApplyBtn", "Save & Apply", 42.0, 15)
	apply_btn.custom_minimum_size = Vector2(168.0, 42.0)
	_style_cta_button(apply_btn)
	apply_btn.pressed.connect(func() -> void: apply_and_save_settings(true))
	foot.add_child(apply_btn)

	return holder


# ==============================================================================
# UI Synchronization & Helpers
# ==============================================================================

func _sync_all_controls() -> void:
	_syncing_ui = true
	_sync_setup_controls()
	_sync_coop_controls()
	_sync_settings_controls()
	_syncing_ui = false


func _sync_setup_controls() -> void:
	var is_tutorial := (config.mode == SessionConfig.MODE_TUTORIAL)

	if _setup_header_pill != null:
		var mshort := _lookup_mode_short(config.mode)
		var sname := String(config.get_ship_spec().get("name", "Sloop"))
		_setup_header_pill.text = _to_ascii("%s  |  %s" % [mshort, sname])

	for mid: StringName in _mode_btns:
		_style_toggle_btn(_mode_btns[mid] as Button, config.mode == mid)
	if _mode_desc_label != null:
		_mode_desc_label.text = _to_ascii(String(config.get_mode_spec().get("desc", "")))

	for sid: StringName in _ship_btns:
		_style_toggle_btn(_ship_btns[sid] as Button, config.ship_class == sid)
	if _ship_desc_label != null:
		var sspec := config.get_ship_spec()
		_ship_desc_label.text = _to_ascii(
			"%d Cannons - %s" % [int(sspec.get("cannons", 2)), String(sspec.get("desc", ""))]
		)

	if _ship_name_edit != null and _ship_name_edit.text != config.ship_name:
		_ship_name_edit.text = config.ship_name

	for cnt: int in _crew_btns:
		var btn := _crew_btns[cnt] as Button
		btn.disabled = (is_tutorial and cnt == 0)
		btn.tooltip_text = "Barnaby sails with you during Maiden Voyage." if btn.disabled else ""
		_style_toggle_btn(btn, config.crew_count == cnt)
	if _crew_desc_label != null:
		var cpreset := config.get_crew_preset()
		_crew_desc_label.text = _to_ascii("%s: %s" % [String(cpreset["name"]), String(cpreset["desc"])])

	for oid: StringName in _outpost_btns:
		var btn := _outpost_btns[oid] as Button
		btn.disabled = (is_tutorial and oid != &"port_scoundrel")
		_style_toggle_btn(btn, config.spawn_outpost_id == oid)
	if _outpost_desc_label != null:
		var ospec := config.get_outpost_spec()
		if is_tutorial:
			_outpost_desc_label.text = _to_ascii(
				"Port Scoundrel (Tutorial Harbour) - %s" % String(ospec.get("desc", ""))
			)
		else:
			_outpost_desc_label.text = _to_ascii(
				"%s - %s" % [String(ospec.get("region", "")), String(ospec.get("desc", ""))]
			)

	for tid: StringName in _time_btns:
		_style_toggle_btn(_time_btns[tid] as Button, config.time_preset == tid)

	for wid: StringName in _weather_btns:
		var btn := _weather_btns[wid] as Button
		btn.disabled = (is_tutorial and wid != &"fair")
		_style_toggle_btn(btn, config.weather_preset == wid)

	for did: StringName in _diff_btns:
		_style_toggle_btn(_diff_btns[did] as Button, config.difficulty == did)
	if _diff_desc_label != null:
		var dscales := config.get_difficulty_scales()
		_diff_desc_label.text = _to_ascii(
			"Enemy Strength: %.2fx  |  Gold Payout: %.2fx" % [
				float(dscales["enemy_scale"]),
				float(dscales["payout_scale"]),
			]
		)

	for eid: StringName in _emissary_btns:
		var btn := _emissary_btns[eid] as Button
		btn.disabled = (is_tutorial and eid != &"")
		_style_toggle_btn(btn, config.starting_emissary == eid)
	if _emissary_desc_label != null:
		if is_tutorial:
			_emissary_desc_label.text = "Emissary flags unlock in Adventure and Naval Skirmish."
		else:
			_emissary_desc_label.text = _to_ascii("Flag: %s" % config.get_emissary_label())


func _sync_coop_controls() -> void:
	for sid: StringName in _coop_ship_btns:
		_style_toggle_btn(_coop_ship_btns[sid] as Button, config.ship_class == sid)
	for oid: StringName in _coop_outpost_btns:
		_style_toggle_btn(_coop_outpost_btns[oid] as Button, config.spawn_outpost_id == oid)
	for cnt: int in _coop_crew_btns:
		_style_toggle_btn(_coop_crew_btns[cnt] as Button, config.crew_count == cnt)
	if _coop_crew_desc_label != null:
		_coop_crew_desc_label.text = _to_ascii(String(config.get_crew_preset().get("name", "")))
	if _coop_ship_name_edit != null and _coop_ship_name_edit.text != config.ship_name:
		_coop_ship_name_edit.text = config.ship_name
	if _coop_host_port_edit != null and _coop_host_port_edit.text != str(config.coop_port):
		_coop_host_port_edit.text = str(config.coop_port)
	if _coop_join_port_edit != null and _coop_join_port_edit.text != str(config.coop_port):
		_coop_join_port_edit.text = str(config.coop_port)
	if _coop_join_addr_edit != null and _coop_join_addr_edit.text != config.coop_address:
		_coop_join_addr_edit.text = config.coop_address


func _sync_settings_controls() -> void:
	var cfg: Dictionary = user_settings.data if user_settings != null else UserSettings._defaults()
	var oq := clampi(int(cfg.get("ocean_quality", 2)), 0, 2)
	for i in _ocean_qual_btns.size():
		_style_toggle_btn(_ocean_qual_btns[i], i == oq)
	var cq := clampi(int(cfg.get("cloud_quality", 1)), 0, 2)
	for i in _cloud_qual_btns.size():
		_style_toggle_btn(_cloud_qual_btns[i], i == cq)

	for data_key: String in _audio_sliders:
		var sl := _audio_sliders[data_key] as HSlider
		var val := clampf(float(cfg.get(data_key, 1.0)), 0.0, 1.0)
		if sl != null:
			sl.set_value_no_signal(val)
		if _audio_val_labels.has(data_key):
			(_audio_val_labels[data_key] as Label).text = "%d%%" % int(roundf(val * 100.0))

	var fov_v := clampf(float(cfg.get("fov", 80.0)), 65.0, 100.0)
	if _fov_slider != null:
		_fov_slider.set_value_no_signal(fov_v)
	if _fov_val_label != null:
		_fov_val_label.text = "%d deg" % int(roundf(fov_v))

	var sens_v := clampf(float(cfg.get("mouse_sensitivity", DEFAULT_SENS)), 0.0008, 0.0060)
	if _sens_slider != null:
		_sens_slider.set_value_no_signal(sens_v)
	if _sens_val_label != null:
		_sens_val_label.text = "%.2fx" % (sens_v / DEFAULT_SENS)


func _pull_text_edits_into_config() -> void:
	if current_page == Page.COOP:
		if _coop_ship_name_edit != null:
			config.ship_name = _coop_ship_name_edit.text
		if _coop_join_addr_edit != null:
			config.coop_address = _coop_join_addr_edit.text
		var port_edit := _coop_join_port_edit if config.coop_role == &"join" else _coop_host_port_edit
		if port_edit != null and port_edit.text.strip_edges().is_valid_int():
			config.coop_port = int(port_edit.text.strip_edges())
	elif _ship_name_edit != null:
		config.ship_name = _ship_name_edit.text


func _emit_preview_changed() -> void:
	preview_config_changed.emit(config.duplicate_config())


func _connect_profile() -> void:
	if profile != null and not profile.changed.is_connected(_on_profile_changed):
		profile.changed.connect(_on_profile_changed)


func _disconnect_profile() -> void:
	if profile != null and profile.changed.is_connected(_on_profile_changed):
		profile.changed.disconnect(_on_profile_changed)


func _on_profile_changed() -> void:
	refresh_profile_summary()


func _on_quit_pressed() -> void:
	_play_back()
	quit_requested.emit()
	if quit_requested.get_connections().is_empty() and DisplayServer.get_name() != "headless" and is_inside_tree():
		get_tree().quit()


func _play_select() -> void:
	if Audio != null:
		Audio.play_sfx(&"ui_select", Vector3.INF, -2.5)


func _play_back() -> void:
	if Audio != null:
		Audio.play_sfx(&"ui_back", Vector3.INF, -3.0)


func _make_quality_picker(label_text: String, btn_prefix: String, out_btns: Array[Button], on_pick: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(118.0, 0.0)
	l.add_theme_font_size_override("font_size", 14)
	row.add_child(l)
	var labels := ["Low", "Med", "High"]
	for i in 3:
		var btn := _make_menu_button("%s_%d" % [btn_prefix, i], labels[i], 32.0, 13)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lv := i
		btn.pressed.connect(func() -> void: on_pick.call(lv))
		row.add_child(btn)
		out_btns.append(btn)
	return row


static func _lookup_mode_short(mode_id: StringName) -> String:
	for entry in SessionConfig.MODE_SPECS:
		if entry["id"] == mode_id:
			return String(entry["short"])
	return "Adventure"


static func _make_sub_card() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel",
		HudIcons.make_parchment_box(Color(0.90, 0.83, 0.68, 0.94), HudIcons.COL_INK_SOFT, 2, 7, 13, 10))
	return p


static func _make_section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", HudIcons.COL_CRIMSON)
	return l


static func _make_menu_button(node_name: String, label_text: String, min_h: float, font_sz: int) -> Button:
	var btn := Button.new()
	btn.name = node_name
	btn.text = label_text
	btn.custom_minimum_size = Vector2(0.0, min_h)
	btn.add_theme_font_size_override("font_size", font_sz)
	return btn


static func _style_toggle_btn(btn: Button, selected: bool) -> void:
	if btn == null:
		return
	if selected:
		btn.add_theme_stylebox_override("normal",
			HudIcons.make_parchment_box(HudIcons.COL_GOLD, HudIcons.COL_CRIMSON, 2, 5, 10, 6))
	else:
		btn.remove_theme_stylebox_override("normal")


static func _style_cta_button(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal",
		HudIcons.make_parchment_box(Color(0.74, 0.16, 0.13, 0.98), HudIcons.COL_GOLD, 2, 6, 16, 8))
	btn.add_theme_stylebox_override("hover",
		HudIcons.make_parchment_box(Color(0.84, 0.21, 0.16, 1.0), Color(0.98, 0.86, 0.44, 1.0), 2, 6, 16, 8))
	btn.add_theme_stylebox_override("pressed",
		HudIcons.make_parchment_box(Color(0.58, 0.12, 0.10, 0.98), HudIcons.COL_BRASS, 2, 6, 16, 8))
	btn.add_theme_color_override("font_color", Color(0.98, 0.93, 0.78, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.97, 0.86, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.96, 0.88, 0.68, 1.0))


static func _style_gold_button(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal",
		HudIcons.make_parchment_box(HudIcons.COL_GOLD, HudIcons.COL_INK, 2, 6, 14, 8))
	btn.add_theme_stylebox_override("hover",
		HudIcons.make_parchment_box(Color(0.95, 0.78, 0.34, 1.0), HudIcons.COL_CRIMSON, 2, 6, 14, 8))
	btn.add_theme_stylebox_override("pressed",
		HudIcons.make_parchment_box(HudIcons.COL_BRASS, HudIcons.COL_INK, 2, 6, 14, 8))


static func _to_ascii(text: String) -> String:
	var out := text.replace(char(0x2014), "-").replace(char(0x2013), "-")
	out = out.replace(char(0x00B7), "|").replace(char(0x2022), "*")
	out = out.replace(char(0x2018), "'").replace(char(0x2019), "'")
	out = out.replace(char(0x201C), "\"").replace(char(0x201D), "\"")
	out = out.replace(char(0x2026), "...").replace(char(0x00D7), "x")
	var clean := ""
	for i in out.length():
		var code := out.unicode_at(i)
		if code >= 9 and code < 128:
			clean += char(code)
	return clean


# ==============================================================================
# Custom Procedural Visual Controls (Zero Third-Party Assets)
# ==============================================================================

class _LeftVignetteBackdrop extends Control:
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var sz := size if (size.is_finite() and size.length_squared() >= 1.0) else get_viewport_rect().size
		if not sz.is_finite() or sz.x < 4.0 or sz.y < 4.0:
			return
		# Subtle left-side dark-sepia gradient fading cleanly to 0.0 over the right ocean vista.
		var w := sz.x
		var h := sz.y
		var c_left := Color(0.05, 0.04, 0.03, 0.34)
		var c_mid := Color(0.05, 0.04, 0.03, 0.14)
		var c_clear := Color(0.05, 0.04, 0.03, 0.0)
		var x1 := w * 0.44
		var x2 := w * 0.66
		draw_polygon(
			PackedVector2Array([Vector2(0.0, 0.0), Vector2(x1, 0.0), Vector2(x1, h), Vector2(0.0, h)]),
			PackedColorArray([c_left, c_mid, c_mid, c_left])
		)
		draw_polygon(
			PackedVector2Array([Vector2(x1, 0.0), Vector2(x2, 0.0), Vector2(x2, h), Vector2(x1, h)]),
			PackedColorArray([c_mid, c_clear, c_clear, c_mid])
		)


class _TitleEmblem extends Control:
	func _ready() -> void:
		custom_minimum_size = Vector2(46.0, 46.0)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if not size.is_finite() or size.x < 4.0 or size.y < 4.0:
			return
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.46
		draw_circle(c, r, Color(0.95, 0.89, 0.74, 0.96))
		draw_arc(c, r, 0.0, TAU, 32, HudIcons.COL_BRASS, 2.4, true)
		HudIcons.draw_icon(self, &"compass", c, r * 0.88, HudIcons.COL_INK, HudIcons.COL_CRIMSON)
