class_name ShipwrightMenu
extends CanvasLayer
## Outpost Voyage Board, Shipwright Refit, Trading Companies & Settings overlay.
##
## Styled with the warm parchment-and-ink theme from `HudIcons` (`scoundrel_font.fnt`,
## zero third-party assets). Opens via `open_menu(tab)` and closes via `close_menu()`,
## cleanly coordinating `PlayerController.set_look_paused(...)` and mouse capture.

signal menu_opened(tab: StringName)
signal menu_closed
signal voyage_accepted(voyage: Dictionary)
signal loadout_changed(slot: StringName, unlock_id: StringName)
signal ship_class_selected(cls: StringName)
signal settings_changed

const TAB_VOYAGES := &"voyages"
const TAB_SHIPWRIGHT := &"shipwright"
const TAB_SETTINGS := &"settings"

const SLOT_SECTIONS: Array[Array] = [
	[&"hull", "Hull Planking (Speed vs. Strength)"],
	[&"sail", "Sail Rigging (Downwind vs. Close-Hauled)"],
	[&"cannon", "Broadside Cannons (Breach vs. Reload)"],
	[&"trait", "Crew Trait"],
	[&"sail_cosmetic", "Sail Livery"],
	[&"flag", "Masthead Pennant"],
]

const SHAPE_LABELS := {
	&"buried_hoard": "Buried Hoard",
	&"riddle_trail": "Riddle Trail",
	&"drowned_bounty": "Drowned Bounty",
	&"wreck_salvage": "Wreck Salvage",
	&"cargo_run": "Merchant Charter",
	&"fort_siege": "Sea Fort Siege",
	&"open_sea_hunt": "Open-Sea Hunt",
}

var is_open: bool = false
var active_tab: StringName = TAB_VOYAGES
var selected_ship_class: StringName = &"sloop"
var selected_story_chapter: int = 1
var origin_outpost_id: StringName = &"port_scoundrel"

var voyage_manager: VoyageManager = null
var archipelago: Archipelago = null
var ship: Ship = null
var player_controller: PlayerController = null
var user_settings: UserSettings = null
var inventory: Inventory = null
var map_table: MapTableView = null
var world_director: WorldDirector = null
var scene_root: Node = null
var _crew_brains: Array[CrewBrain] = []

var _theme: Theme = null
var _backdrop: ColorRect = null
var _tab_buttons: Dictionary = {}  # StringName -> Button
var _tab_pages: Dictionary = {}    # StringName -> Control
var _gold_header_label: Label = null
var _status_label: Label = null

# Dynamic tab content roots
var _voyage_list_box: VBoxContainer = null
var _shipwright_box: VBoxContainer = null
var _settings_box: VBoxContainer = null


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_theme = HudIcons.build_parchment_theme()
	if Game != null and Game.profile != null:
		var saved_cls := String(Game.profile.data.get("ship_class", "sloop"))
		if saved_cls == "brigantine" or saved_cls == "sloop":
			selected_ship_class = StringName(saved_cls)
	_build_ui()
	_backdrop.visible = false


## Bind live gameplay systems so accepting voyages, buying sidegrades, and changing
## settings immediately take effect in the running world.
func bind(
	p_voyage_manager: VoyageManager,
	p_archipelago: Archipelago,
	p_ship: Ship,
	p_player_controller: PlayerController,
	p_settings: UserSettings,
	p_inventory: Inventory = null,
	p_map_table: MapTableView = null,
	p_crew_brains: Array[CrewBrain] = [],
	p_world_director: WorldDirector = null,
	p_scene_root: Node = null
) -> void:
	voyage_manager = p_voyage_manager
	archipelago = p_archipelago
	ship = p_ship
	player_controller = p_player_controller
	user_settings = p_settings
	inventory = p_inventory
	map_table = p_map_table
	_crew_brains = p_crew_brains.duplicate()
	world_director = p_world_director
	scene_root = p_scene_root
	if is_open:
		refresh()


func set_crew_brains(brains: Array[CrewBrain]) -> void:
	_crew_brains = brains.duplicate()


## Open the Outpost overlay to `tab` (&"voyages", &"shipwright", or &"settings").
func open_menu(tab: StringName = TAB_VOYAGES) -> void:
	if not _tab_pages.has(tab):
		tab = TAB_VOYAGES
	active_tab = tab
	is_open = true
	if _backdrop != null:
		_backdrop.visible = true
	if player_controller != null and is_instance_valid(player_controller):
		player_controller.set_look_paused(true)
	refresh()
	set_active_tab(active_tab)
	Audio.play_sfx(&"ui_open", Vector3.INF, -2.5)
	menu_opened.emit(active_tab)


## Close the Outpost overlay and restore first-person mouse capture.
func close_menu() -> void:
	if not is_open:
		return
	is_open = false
	if _backdrop != null:
		_backdrop.visible = false
	if player_controller != null and is_instance_valid(player_controller):
		player_controller.set_look_paused(false)
	Audio.play_sfx(&"ui_back", Vector3.INF, -3.0)
	menu_closed.emit()


func set_active_tab(tab: StringName) -> void:
	if not _tab_pages.has(tab):
		return
	active_tab = tab
	for key: StringName in _tab_pages:
		var page: Control = _tab_pages[key]
		page.visible = (key == tab)
	for key: StringName in _tab_buttons:
		var btn: Button = _tab_buttons[key]
		_style_highlight_button(btn, key == tab)


## Rebuild all dynamic cards and readouts from live profile, voyage, and settings state.
func refresh() -> void:
	if _gold_header_label != null:
		var gold := int(Game.profile.data.get("gold", 0)) if (Game != null and Game.profile != null) else 0
		_gold_header_label.text = "Treasury: %d Gold" % gold
	_rebuild_voyages_tab()
	_rebuild_shipwright_tab()
	_rebuild_settings_tab()


# ==============================================================================
# Gameplay Actions (callable from UI buttons or headless tests)
# ==============================================================================

## Accept a voyage contract, sync held treasure map + map table, and notify listeners.
func accept_voyage(voyage: Dictionary) -> bool:
	if voyage.is_empty() or voyage_manager == null or not Net.is_host():
		return false
	if not voyage_manager.start_voyage(voyage):
		return false
	sync_voyage_charts(voyage)
	Audio.play_sfx(&"ui_select", Vector3.INF, -2.0)
	_set_status("Accepted voyage: %s" % String(voyage.get("title", "Voyage")))
	voyage_accepted.emit(voyage_manager.active_voyage)
	refresh()
	return true


## Sync both the player's held treasure map and the ship's MapTableView to `voyage`.
func sync_voyage_charts(voyage: Dictionary) -> void:
	if voyage.is_empty():
		return
	var target_id := String(voyage.get("target_island_id", ""))
	var target_isl: Island = archipelago.get_island_by_id(target_id) if archipelago != null else null
	if target_isl != null:
		var dig_local := Vector3.ZERO
		var sites := target_isl.get_dig_sites()
		if not sites.is_empty():
			dig_local = sites[0].position
		elif not target_isl.dig_points.is_empty():
			dig_local = target_isl.dig_points[0]
		if inventory != null and is_instance_valid(inventory):
			inventory.set_treasure_map(
				target_isl.display_name,
				target_isl.contour_points,
				dig_local,
				target_isl.island_radius
			)
		if map_table != null and is_instance_valid(map_table):
			map_table.set_voyage_target(target_isl.global_position)
			map_table.refresh_now()
	else:
		var raw_pos: Variant = voyage.get("target_position", Vector3.INF)
		if raw_pos is Vector3 and map_table != null and is_instance_valid(map_table):
			map_table.set_voyage_target(raw_pos as Vector3)
			map_table.refresh_now()


## Purchase (if not owned) and equip a sidegrade fitting, crew trait, or ship livery.
## Immediately applies modifiers & cosmetics to the active Ship and CrewBrains, and saves!
func buy_or_equip_unlock(unlock_id: StringName) -> Dictionary:
	if Game == null or Game.profile == null:
		return {"ok": false, "reason": "No captain profile."}
	var entry := Economy.get_unlock(unlock_id)
	if entry.is_empty():
		return {"ok": false, "reason": "Unknown fitting."}

	var purchased := false
	if not Economy.is_unlocked(Game.profile, unlock_id):
		var buy_res := Economy.purchase_unlock(Game.profile, unlock_id)
		if not bool(buy_res.get("ok", false)):
			var reason := String(buy_res.get("reason", "Cannot purchase."))
			_set_status(reason)
			Audio.play_sfx(&"ui_back", Vector3.INF, -3.0)
			return buy_res
		purchased = true
		Audio.play_sfx(&"coin_jingle", Vector3.INF, -2.0)

	var slot: StringName = entry["slot"]
	if not Economy.equip_loadout(Game.profile, slot, unlock_id):
		return {"ok": false, "reason": "Could not equip %s." % String(unlock_id)}

	var applied_mods := apply_economy_to_ship(ship, Game.profile, _crew_brains, world_director)
	Game.save()

	var nm := String(entry["name"])
	if purchased:
		_set_status("Purchased & fitted: %s!" % nm)
		Game.post_notice("Shipwright fitted %s!" % nm)
	else:
		Audio.play_sfx(&"ui_select", Vector3.INF, -2.5)
		_set_status("Equipped: %s." % nm)
	loadout_changed.emit(slot, unlock_id)
	refresh()
	return {
		"ok": true,
		"purchased": purchased,
		"unlock_id": unlock_id,
		"slot": slot,
		"modifiers": applied_mods,
	}


## Switch preferred ship class (&"sloop" or &"brigantine") and emit `ship_class_selected`.
func select_ship_class(cls: StringName) -> void:
	if cls != &"sloop" and cls != &"brigantine":
		return
	selected_ship_class = cls
	if Game != null and Game.profile != null:
		Game.profile.data["ship_class"] = String(cls)
		Game.save()
	Audio.play_sfx(&"ui_select", Vector3.INF, -2.5)
	_set_status("Ship class selected: %s" % String(cls).capitalize())
	ship_class_selected.emit(cls)
	refresh()


## Apply a unified Low (0) / Medium (1) / High (2) graphics preset through UserSettings.
func apply_quality_preset(level: int) -> void:
	var lv := clampi(level, 0, 2)
	if user_settings != null:
		user_settings.data["ocean_quality"] = lv
		user_settings.data["cloud_quality"] = lv
		user_settings.apply_all(scene_root)
		user_settings.save()
	Audio.play_sfx(&"ui_select", Vector3.INF, -2.5)
	var names := ["Low", "Medium", "High"]
	_set_status("Quality preset set to %s." % names[lv])
	settings_changed.emit()
	refresh()


## Restore all keyboard actions in InputMap back to `InputSetup.ACTIONS` defaults.
func reset_keybindings() -> void:
	for action_name: String in InputSetup.ACTIONS:
		if not InputMap.has_action(action_name):
			continue
		InputMap.action_erase_events(action_name)
		for code in InputSetup.ACTIONS[action_name]:
			var ev: InputEvent
			if code is String:
				var mb := InputEventMouseButton.new()
				mb.button_index = MOUSE_BUTTON_LEFT if code == "mouse_left" else MOUSE_BUTTON_RIGHT
				ev = mb
			else:
				var k := InputEventKey.new()
				k.physical_keycode = int(code) as Key
				ev = k
			InputMap.action_add_event(action_name, ev)
	if user_settings != null:
		user_settings.data["keybinds"] = {}
		user_settings.save()
	Audio.play_sfx(&"ui_select", Vector3.INF, -2.5)
	_set_status("Key bindings restored to defaults.")
	settings_changed.emit()
	refresh()


## Compute Economy modifiers + liveries from `profile` and apply them to `ship`,
## `crew_brains`, and `world_director`. Bridges Economy key names to `Ship.apply_modifiers()`.
static func apply_economy_to_ship(
	target_ship: Ship,
	profile: Profile,
	crew_brains: Array[CrewBrain] = [],
	director: WorldDirector = null
) -> Dictionary:
	var mods := Economy.get_ship_modifiers(profile)
	var bridged := mods.duplicate()
	bridged["speed_scale"] = float(mods.get("speed", 1.0)) * float(mods.get("downwind", 1.0))
	bridged["close_hauled_scale"] = float(mods.get("close_hauled", 1.0))
	bridged["cannon_radius_scale"] = float(mods.get("breach_radius", 1.0))

	if target_ship != null and is_instance_valid(target_ship):
		target_ship.apply_modifiers(bridged)
		var sail_tint := Color.WHITE
		var flag_tint := Color.WHITE
		var sail_cos := StringName(String(mods.get("sail_cosmetic_id", &"")))
		if sail_cos != &"":
			var se := Economy.get_unlock(sail_cos)
			if se.has("tint") and se["tint"] is Color:
				sail_tint = se["tint"] as Color
		var flag_cos := StringName(String(mods.get("flag_id", &"")))
		if flag_cos != &"":
			var fe := Economy.get_unlock(flag_cos)
			if fe.has("tint") and fe["tint"] is Color:
				flag_tint = fe["tint"] as Color
		target_ship.apply_livery(sail_tint, flag_tint)

	for b in crew_brains:
		if b != null and is_instance_valid(b):
			b.apply_modifiers(mods)

	if director != null and is_instance_valid(director):
		director.lookout_scale = float(mods.get("lookout_scale", 1.0))

	return bridged


# ==============================================================================
# Input handling
# ==============================================================================

func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed(&"pause"):
		close_menu()
		get_viewport().set_input_as_handled()


# ==============================================================================
# UI Construction
# ==============================================================================

func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.name = "ShipwrightBackdrop"
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.05, 0.04, 0.02, 0.58)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.theme = _theme
	add_child(_backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 72)
	margin.add_theme_constant_override("margin_right", 72)
	margin.add_theme_constant_override("margin_top", 44)
	margin.add_theme_constant_override("margin_bottom", 44)
	_backdrop.add_child(margin)

	var folio := PanelContainer.new()
	folio.name = "OutpostFolio"
	folio.add_theme_stylebox_override("panel",
		HudIcons.make_parchment_box(Color(0.93, 0.87, 0.73, 0.99), HudIcons.COL_INK, 3, 10, 26, 20))
	margin.add_child(folio)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 12)
	folio.add_child(root_v)

	# Header bar: title, treasury, close button
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	root_v.add_child(header)

	var title_lbl := Label.new()
	title_lbl.text = "OUTPOST HARBOURMASTER & SHIPWRIGHT"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.add_theme_color_override("font_color", HudIcons.COL_INK)
	header.add_child(title_lbl)

	_gold_header_label = Label.new()
	_gold_header_label.name = "GoldHeaderLabel"
	_gold_header_label.text = "Treasury: 0 Gold"
	_gold_header_label.add_theme_font_size_override("font_size", 19)
	_gold_header_label.add_theme_color_override("font_color", Color(0.56, 0.36, 0.06))
	header.add_child(_gold_header_label)

	var close_btn := Button.new()
	close_btn.name = "CloseMenuButton"
	close_btn.text = "Close [Esc]"
	close_btn.pressed.connect(close_menu)
	header.add_child(close_btn)

	# Tab bar
	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 10)
	root_v.add_child(tab_bar)

	var tab_specs: Array[Array] = [
		[TAB_VOYAGES, "Voyage Board"],
		[TAB_SHIPWRIGHT, "Shipwright & Companies"],
		[TAB_SETTINGS, "Settings & Controls"],
	]
	for spec in tab_specs:
		var tid: StringName = spec[0]
		var label: String = spec[1]
		var btn := Button.new()
		btn.name = "Tab_" + String(tid)
		btn.text = label
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func() -> void:
			Audio.play_sfx(&"ui_tick", Vector3.INF, -3.5)
			set_active_tab(tid)
		)
		tab_bar.add_child(btn)
		_tab_buttons[tid] = btn

	# Scrollable tab body
	var body_holder := Control.new()
	body_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_v.add_child(body_holder)

	_voyage_list_box = _make_scroll_page(body_holder, "VoyagesPage", TAB_VOYAGES)
	_shipwright_box = _make_scroll_page(body_holder, "ShipwrightPage", TAB_SHIPWRIGHT)
	_settings_box = _make_scroll_page(body_holder, "SettingsPage", TAB_SETTINGS)

	# Footer status bar
	_status_label = Label.new()
	_status_label.name = "MenuStatusLabel"
	_status_label.text = "Select a charter, refit your hull, or adjust sea settings."
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	root_v.add_child(_status_label)


func _make_scroll_page(parent: Control, node_name: String, tab_id: StringName) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = node_name
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	_tab_pages[tab_id] = scroll

	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 12)
	scroll.add_child(inner)
	return inner


# ==============================================================================
# Tab 1: Voyage Board
# ==============================================================================

func _rebuild_voyages_tab() -> void:
	if _voyage_list_box == null:
		return
	_clear_children(_voyage_list_box)

	var map_data: Array[Dictionary] = archipelago.get_map_data() if archipelago != null else VoyageComposer.default_archipelago_roster()
	var composer: VoyageComposer = voyage_manager.composer if voyage_manager != null else VoyageComposer.new()

	# Active voyage banner
	if voyage_manager != null and voyage_manager.has_active_voyage():
		var av := voyage_manager.active_voyage
		var banner := _make_card_panel(Color(0.96, 0.90, 0.74, 0.96), HudIcons.COL_CRIMSON)
		var bv := VBoxContainer.new()
		bv.add_theme_constant_override("separation", 4)
		banner.add_child(bv)
		var hdr := Label.new()
		hdr.text = "ACTIVE VOYAGE: %s" % String(av.get("title", "Voyage"))
		hdr.add_theme_font_size_override("font_size", 17)
		hdr.add_theme_color_override("font_color", HudIcons.COL_CRIMSON)
		bv.add_child(hdr)
		var obj := Label.new()
		obj.text = voyage_manager.get_current_objective()
		obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		obj.add_theme_font_size_override("font_size", 14)
		bv.add_child(obj)
		_voyage_list_box.add_child(banner)

	# Authored Story Chapter section
	var story_hdr_row := HBoxContainer.new()
	story_hdr_row.add_theme_constant_override("separation", 8)
	_voyage_list_box.add_child(story_hdr_row)

	var story_hdr := Label.new()
	story_hdr.text = "AUTHORED STORY VOYAGE"
	story_hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	story_hdr.add_theme_font_size_override("font_size", 16)
	story_hdr.add_theme_color_override("font_color", HudIcons.COL_CRIMSON)
	story_hdr_row.add_child(story_hdr)

	for ch in range(1, VoyageComposer.STORY_CHAPTER_COUNT + 1):
		var cbtn := Button.new()
		cbtn.text = "Ch. %d" % ch
		var ch_num := ch
		_style_highlight_button(cbtn, selected_story_chapter == ch_num)
		cbtn.pressed.connect(func() -> void:
			selected_story_chapter = ch_num
			Audio.play_sfx(&"ui_tick", Vector3.INF, -3.5)
			_rebuild_voyages_tab()
		)
		story_hdr_row.add_child(cbtn)

	var story_voyage := composer.get_story_voyage(selected_story_chapter, map_data)
	_voyage_list_box.add_child(_build_voyage_card(story_voyage, true))

	# Procedural Board Offers section
	var board_hdr_row := HBoxContainer.new()
	board_hdr_row.add_theme_constant_override("separation", 8)
	_voyage_list_box.add_child(board_hdr_row)

	var board_hdr := Label.new()
	board_hdr.text = "COMPANY CHARTERS (3 POSTED)"
	board_hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_hdr.add_theme_font_size_override("font_size", 16)
	board_hdr.add_theme_color_override("font_color", HudIcons.COL_INK)
	board_hdr_row.add_child(board_hdr)

	var ref_btn := Button.new()
	ref_btn.name = "RefreshVoyagesButton"
	ref_btn.text = "Post Fresh Charters"
	ref_btn.pressed.connect(func() -> void:
		if voyage_manager != null and Net.is_host():
			voyage_manager.refresh_offers(map_data, 3, origin_outpost_id)
			Audio.play_sfx(&"ui_select", Vector3.INF, -3.0)
			_rebuild_voyages_tab()
	)
	board_hdr_row.add_child(ref_btn)

	var offers: Array[Dictionary] = []
	if voyage_manager != null:
		if voyage_manager.available_voyages.is_empty() and Net.is_host():
			voyage_manager.refresh_offers(map_data, 3, origin_outpost_id)
		offers = voyage_manager.available_voyages
	else:
		offers = composer.generate_board_offers(map_data, 3, {}, origin_outpost_id)

	for offer in offers:
		_voyage_list_box.add_child(_build_voyage_card(offer, false))


func _build_voyage_card(voyage: Dictionary, is_story: bool) -> PanelContainer:
	var comp_id := StringName(String(voyage.get("company_id", &"gilded_compass")))
	var comp_info := Economy.get_company(comp_id)
	var comp_name := String(comp_info.get("short_name", "Guild"))
	var shape_id := StringName(String(voyage.get("shape", &"buried_hoard")))
	var shape_name := String(SHAPE_LABELS.get(shape_id, String(shape_id).replace("_", " ").capitalize()))
	var island_name := String(voyage.get("target_island_name", "Unknown Isle"))
	var payoff: Dictionary = voyage.get("payoff", {})
	var est_gold := int(payoff.get("estimated_gold", 0))
	var est_renown := int(payoff.get("estimated_renown", 0))
	var hook: Dictionary = voyage.get("hook", {})
	var briefing := String(hook.get("briefing", ""))

	var bg := Color(0.95, 0.89, 0.74, 0.98) if is_story else Color(0.90, 0.83, 0.68, 0.96)
	var border := HudIcons.COL_BRASS if is_story else HudIcons.COL_INK_SOFT
	var card := _make_card_panel(bg, border)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)

	var info_v := VBoxContainer.new()
	info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_v.add_theme_constant_override("separation", 3)
	row.add_child(info_v)

	var title_lbl := Label.new()
	var prefix := "[STORY CH.%d] " % int(voyage.get("story_chapter", 1)) if is_story else ""
	title_lbl.text = "%s%s" % [prefix, String(voyage.get("title", "Voyage"))]
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", HudIcons.COL_CRIMSON if is_story else HudIcons.COL_INK)
	info_v.add_child(title_lbl)

	var meta_lbl := Label.new()
	meta_lbl.text = "%s  |  %s  |  Destination: %s  |  Reward: ~%d Gold, +%d Renown" % [
		comp_name, shape_name, island_name, est_gold, est_renown]
	meta_lbl.add_theme_font_size_override("font_size", 13)
	meta_lbl.add_theme_color_override("font_color", Color(0.45, 0.30, 0.10))
	info_v.add_child(meta_lbl)

	if briefing != "":
		var brief_lbl := Label.new()
		brief_lbl.text = briefing
		brief_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		brief_lbl.add_theme_font_size_override("font_size", 13)
		brief_lbl.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
		info_v.add_child(brief_lbl)

	var btn := Button.new()
	btn.name = "Accept_" + String(voyage.get("id", "voyage"))
	btn.text = "Accept Voyage"
	btn.custom_minimum_size = Vector2(154.0, 44.0)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v_copy := voyage.duplicate(true)
	btn.pressed.connect(func() -> void:
		accept_voyage(v_copy)
	)
	row.add_child(btn)
	return card


# ==============================================================================
# Tab 2: Shipwright & Trading Companies
# ==============================================================================

func _rebuild_shipwright_tab() -> void:
	if _shipwright_box == null:
		return
	_clear_children(_shipwright_box)
	var prof: Profile = Game.profile if Game != null else null

	# 1. Three Trading Companies renown bar
	var comp_hdr := Label.new()
	comp_hdr.text = "TRADING COMPANY STANDING"
	comp_hdr.add_theme_font_size_override("font_size", 16)
	comp_hdr.add_theme_color_override("font_color", HudIcons.COL_CRIMSON)
	_shipwright_box.add_child(comp_hdr)

	var comp_row := HBoxContainer.new()
	comp_row.add_theme_constant_override("separation", 10)
	_shipwright_box.add_child(comp_row)

	for comp_id: StringName in [&"gilded_compass", &"iron_tide", &"sunken_archive"]:
		var info := Economy.get_company(comp_id)
		var prog := Economy.get_company_progress(prof, comp_id)
		var card := _make_card_panel(Color(0.90, 0.83, 0.68, 0.96), HudIcons.COL_INK_SOFT)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 3)
		card.add_child(cv)

		var cname := Label.new()
		cname.text = String(info.get("short_name", String(comp_id)))
		cname.add_theme_font_size_override("font_size", 16)
		cname.add_theme_color_override("font_color", HudIcons.COL_INK)
		cv.add_child(cname)

		var rank_lbl := Label.new()
		rank_lbl.text = "Rank %d — %s" % [int(prog["rank"]), String(prog["title"])]
		rank_lbl.add_theme_font_size_override("font_size", 14)
		rank_lbl.add_theme_color_override("font_color", HudIcons.COL_CRIMSON)
		cv.add_child(rank_lbl)

		var pts_lbl := Label.new()
		pts_lbl.text = "%d / %d Renown" % [int(prog["points"]), int(prog["next_threshold"])]
		pts_lbl.add_theme_font_size_override("font_size", 13)
		pts_lbl.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
		cv.add_child(pts_lbl)
		comp_row.add_child(card)

	# 2. Ship Class Toggle (Sloop / Brigantine)
	var cls_card := _make_card_panel(Color(0.91, 0.84, 0.70, 0.96), HudIcons.COL_BRASS)
	var cls_row := HBoxContainer.new()
	cls_row.add_theme_constant_override("separation", 12)
	cls_card.add_child(cls_row)

	var cls_lbl := Label.new()
	cls_lbl.text = "SHIP CLASS"
	cls_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cls_lbl.add_theme_font_size_override("font_size", 16)
	cls_row.add_child(cls_lbl)

	for cls_spec: Array in [[&"sloop", "Sloop (Agile, 1-2 Crew)"], [&"brigantine", "Brigantine (2-4 Crew)"]]:
		var cid: StringName = cls_spec[0]
		var clabel: String = cls_spec[1]
		var btn := Button.new()
		btn.name = "ShipClass_" + String(cid)
		btn.text = clabel
		_style_highlight_button(btn, selected_ship_class == cid)
		btn.pressed.connect(func() -> void: select_ship_class(cid))
		cls_row.add_child(btn)
	_shipwright_box.add_child(cls_card)

	# 3. Sidegrade Fittings & Ship Liveries by slot
	for sec in SLOT_SECTIONS:
		var slot_id: StringName = sec[0]
		var sec_title: String = sec[1]
		var sh := Label.new()
		sh.text = sec_title.to_upper()
		sh.add_theme_font_size_override("font_size", 15)
		sh.add_theme_color_override("font_color", HudIcons.COL_INK)
		_shipwright_box.add_child(sh)

		var equipped_id := Economy.get_equipped(prof, slot_id)
		var items := Economy.get_unlocks_by_slot(slot_id)
		for entry in items:
			var uid: StringName = entry["id"]
			var owned := Economy.is_unlocked(prof, uid)
			var equipped := (equipped_id == uid)
			var blocker := Economy.get_purchase_blocker(prof, uid)

			var row_panel := _make_card_panel(
				Color(0.95, 0.90, 0.75, 0.98) if equipped else Color(0.89, 0.82, 0.67, 0.95),
				HudIcons.COL_CRIMSON if equipped else HudIcons.COL_INK_SOFT
			)
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 12)
			row_panel.add_child(h)

			var text_v := VBoxContainer.new()
			text_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			text_v.add_theme_constant_override("separation", 2)
			h.add_child(text_v)

			var nm := Label.new()
			nm.text = String(entry["name"])
			nm.add_theme_font_size_override("font_size", 16)
			nm.add_theme_color_override("font_color", HudIcons.COL_INK)
			text_v.add_child(nm)

			var desc := Label.new()
			var comp_short := String(Economy.get_company(entry["company_id"]).get("short_name", ""))
			desc.text = "%s  (%s Rank %d)" % [String(entry["summary"]), comp_short, int(entry["req_rank"])]
			desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc.add_theme_font_size_override("font_size", 13)
			desc.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
			text_v.add_child(desc)

			var act_btn := Button.new()
			act_btn.name = "UnlockBtn_" + String(uid)
			act_btn.custom_minimum_size = Vector2(156.0, 38.0)
			act_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			if equipped:
				act_btn.text = "Equipped"
				act_btn.disabled = true
				_style_highlight_button(act_btn, true)
			elif owned:
				act_btn.text = "Equip"
				act_btn.pressed.connect(func() -> void: buy_or_equip_unlock(uid))
			else:
				act_btn.text = "Buy %dg" % int(entry["cost"])
				act_btn.tooltip_text = blocker if blocker != "" else "Purchase & equip immediately"
				act_btn.disabled = (blocker != "")
				act_btn.pressed.connect(func() -> void: buy_or_equip_unlock(uid))
			h.add_child(act_btn)
			_shipwright_box.add_child(row_panel)


# ==============================================================================
# Tab 3: Settings & Controls
# ==============================================================================

func _rebuild_settings_tab() -> void:
	if _settings_box == null:
		return
	_clear_children(_settings_box)

	var cfg: Dictionary = user_settings.data if user_settings != null else UserSettings._defaults()

	# Graphics Quality Preset
	var qual_card := _make_card_panel(Color(0.90, 0.83, 0.68, 0.96), HudIcons.COL_INK_SOFT)
	var qv := VBoxContainer.new()
	qv.add_theme_constant_override("separation", 8)
	qual_card.add_child(qv)

	var qhdr := Label.new()
	qhdr.text = "GRAPHICS QUALITY PRESET"
	qhdr.add_theme_font_size_override("font_size", 16)
	qhdr.add_theme_color_override("font_color", HudIcons.COL_CRIMSON)
	qv.add_child(qhdr)

	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 10)
	qv.add_child(preset_row)
	var cur_o := int(cfg.get("ocean_quality", 2))
	var cur_c := int(cfg.get("cloud_quality", 1))
	var pnames := ["Low", "Medium", "High"]
	for i in 3:
		var btn := Button.new()
		btn.name = "Preset_" + pnames[i]
		btn.text = pnames[i]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lv := i
		_style_highlight_button(btn, cur_o == lv and cur_c == lv)
		btn.pressed.connect(func() -> void: apply_quality_preset(lv))
		preset_row.add_child(btn)
	_settings_box.add_child(qual_card)

	# Accessibility toggles
	var acc_card := _make_card_panel(Color(0.90, 0.83, 0.68, 0.96), HudIcons.COL_INK_SOFT)
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 8)
	acc_card.add_child(av)

	var ahdr := Label.new()
	ahdr.text = "ACCESSIBILITY & COMFORT"
	ahdr.add_theme_font_size_override("font_size", 16)
	ahdr.add_theme_color_override("font_color", HudIcons.COL_CRIMSON)
	av.add_child(ahdr)

	var bob_chk := CheckBox.new()
	bob_chk.name = "ReduceHeadBobCheck"
	bob_chk.text = "Reduce Head-Bob (disables walking camera sway)"
	bob_chk.button_pressed = not bool(cfg.get("head_bob_enabled", true))
	bob_chk.toggled.connect(func(reduced: bool) -> void:
		if user_settings != null:
			user_settings.data["head_bob_enabled"] = not reduced
			user_settings.apply_all(scene_root)
			user_settings.save()
		settings_changed.emit()
	)
	av.add_child(bob_chk)

	var sub_chk := CheckBox.new()
	sub_chk.name = "SubtitlesCheck"
	sub_chk.text = "Show Subtitles & Crew Callout Banners"
	sub_chk.button_pressed = bool(cfg.get("subtitles_enabled", true))
	sub_chk.toggled.connect(func(enabled: bool) -> void:
		if user_settings != null:
			user_settings.data["subtitles_enabled"] = enabled
			user_settings.save()
		settings_changed.emit()
	)
	av.add_child(sub_chk)

	var hc_chk := CheckBox.new()
	hc_chk.name = "HighContrastCheck"
	hc_chk.text = "High-Contrast Interaction Prompts"
	hc_chk.button_pressed = bool(cfg.get("high_contrast_prompts", false))
	hc_chk.toggled.connect(func(enabled: bool) -> void:
		if user_settings != null:
			user_settings.data["high_contrast_prompts"] = enabled
			user_settings.save()
		settings_changed.emit()
	)
	av.add_child(hc_chk)
	_settings_box.add_child(acc_card)

	# Controls & Keybinding Reset
	var ctl_card := _make_card_panel(Color(0.90, 0.83, 0.68, 0.96), HudIcons.COL_INK_SOFT)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	ctl_card.add_child(cv)

	var chdr := Label.new()
	chdr.text = "CONTROLS & KEY BINDINGS"
	chdr.add_theme_font_size_override("font_size", 16)
	chdr.add_theme_color_override("font_color", HudIcons.COL_CRIMSON)
	cv.add_child(chdr)

	var binds_lbl := Label.new()
	binds_lbl.text = "Move: WASD   |   Sprint: Shift   |   Jump: Space   |   Interact: F   |   Leave Station: X\n" \
		+ "Tools Radial: Tab   |   Crew Command Wheel: Q   |   Primary/Secondary: LMB/RMB   |   Pause: Esc"
	binds_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	binds_lbl.add_theme_font_size_override("font_size", 13)
	binds_lbl.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	cv.add_child(binds_lbl)

	var reset_btn := Button.new()
	reset_btn.name = "ResetKeybindsButton"
	reset_btn.text = "Reset Key Bindings to Defaults"
	reset_btn.pressed.connect(reset_keybindings)
	cv.add_child(reset_btn)
	_settings_box.add_child(ctl_card)


# ==============================================================================
# Style Helpers
# ==============================================================================

func _set_status(msg: String) -> void:
	if _status_label != null:
		_status_label.text = msg


static func _make_card_panel(bg: Color, border: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", HudIcons.make_parchment_box(bg, border, 2, 7, 14, 10))
	return p


static func _style_highlight_button(btn: Button, active: bool) -> void:
	if btn == null:
		return
	if active:
		btn.add_theme_stylebox_override("normal",
			HudIcons.make_parchment_box(HudIcons.COL_GOLD, HudIcons.COL_CRIMSON, 2, 5, 12, 7))
	else:
		btn.remove_theme_stylebox_override("normal")


static func _clear_children(container: Node) -> void:
	for c in container.get_children():
		container.remove_child(c)
		c.queue_free()
