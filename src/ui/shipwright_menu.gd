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
signal ship_name_changed(new_name: String)
signal armory_loadout_changed(melee_id: StringName, ranged_id: StringName)
signal emissary_changed(company_id: StringName, grade: int)
signal commodity_purchased(commodity_id: StringName, cost: int, item: Node)
signal settings_changed

const TAB_VOYAGES := &"voyages"
const TAB_SHIPWRIGHT := &"shipwright"
const TAB_LOG := &"log"
const TAB_SETTINGS := &"settings"

const SLOT_SECTIONS: Array[Array] = [
	[&"hull", "Hull Planking (Speed vs. Strength)"],
	[&"sail", "Sail Rigging (Downwind vs. Close-Hauled)"],
	[&"cannon", "Broadside Cannons (Breach vs. Reload)"],
	[&"trait", "Crew Trait"],
	[&"tool_variant", "Tool Variant"],
	[&"hull_livery", "Hull Paint"],
	[&"sail_cosmetic", "Sail Livery"],
	[&"flag", "Masthead Pennant"],
	[&"crew_uniform", "Crew Uniform"],
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
var selected_melee_weapon: StringName = &"cutlass"
var selected_ranged_weapon: StringName = &"pistol"
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
var _trade_spawn_seq: int = 0

var _theme: Theme = null
var _backdrop: ColorRect = null
var _tab_buttons: Dictionary = {}  # StringName -> Button
var _tab_pages: Dictionary = {}    # StringName -> Control
var _gold_header_label: Label = null
var _status_label: Label = null

# Dynamic tab content roots
var _voyage_list_box: VBoxContainer = null
var _shipwright_box: VBoxContainer = null
var _log_box: VBoxContainer = null
var _settings_box: VBoxContainer = null


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_theme = HudIcons.build_parchment_theme()
	if Game != null and Game.profile != null:
		var saved_cls := String(Game.profile.data.get("ship_class", "sloop"))
		if saved_cls == "brigantine" or saved_cls == "sloop":
			selected_ship_class = StringName(saved_cls)
		var saved_melee := StringName(String(Game.profile.data.get("melee_weapon", "cutlass")))
		if saved_melee == &"cutlass" or saved_melee == &"boarding_axe":
			selected_melee_weapon = saved_melee
		var saved_ranged := StringName(String(Game.profile.data.get("ranged_weapon", "pistol")))
		if saved_ranged == &"pistol" or saved_ranged == &"blunderbuss":
			selected_ranged_weapon = saved_ranged
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
	if inventory != null and is_instance_valid(inventory):
		selected_melee_weapon = inventory.melee_weapon
		selected_ranged_weapon = inventory.ranged_weapon
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
	if tab == TAB_LOG:
		_rebuild_log_tab()


## Rebuild all dynamic cards and readouts from live profile, voyage, and settings state.
func refresh() -> void:
	if _gold_header_label != null:
		var gold := int(Game.profile.data.get("gold", 0)) if (Game != null and Game.profile != null) else 0
		_gold_header_label.text = "Treasury: %d Gold" % gold
	_rebuild_voyages_tab()
	_rebuild_shipwright_tab()
	_rebuild_log_tab()
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


## Raise a Trading Company Emissary flag on `voyage_manager.emissary` and sync ship/director.
func raise_emissary_flag(company_id: StringName) -> bool:
	if voyage_manager == null or voyage_manager.emissary == null or not Net.is_host():
		return false
	if not voyage_manager.emissary.raise_flag(company_id):
		return false
	var grade := voyage_manager.emissary.grade
	if ship != null and is_instance_valid(ship):
		var sflag := ship.get_node_or_null(^"ShipEmissaryFlag") as ShipEmissaryFlag
		if sflag != null:
			sflag.set_emissary(company_id, grade)
	if world_director != null and is_instance_valid(world_director):
		world_director.emissary_grade = grade
	Audio.play_sfx(&"ui_select", Vector3.INF, -2.0)
	var cname := EmissaryLedger.company_short_name(company_id)
	_set_status("Raised %s Emissary flag (Grade I)." % cname)
	if Game != null:
		Game.post_notice("Raised %s Emissary Flag (Grade I)!" % cname)
	emissary_changed.emit(company_id, grade)
	refresh()
	return true


## Voluntarily lower the active Emissary flag for its cash-out gold & renown bonus.
func lower_emissary_flag() -> Dictionary:
	if voyage_manager == null or voyage_manager.emissary == null or not Net.is_host():
		return {}
	if not voyage_manager.emissary.is_active():
		return {}
	var prof: Profile = Game.profile if (Game != null and Game.profile != null) else voyage_manager.profile
	var res := voyage_manager.emissary.lower_flag(prof)
	if Game != null and Game.profile != null and prof == Game.profile:
		Game.save()
	if ship != null and is_instance_valid(ship):
		var sflag := ship.get_node_or_null(^"ShipEmissaryFlag") as ShipEmissaryFlag
		if sflag != null:
			sflag.set_emissary(&"", 0)
	if world_director != null and is_instance_valid(world_director):
		world_director.emissary_grade = 0
	Audio.play_sfx(&"coin_jingle", Vector3.INF, -2.0)
	var comp_id: StringName = res.get("company_id", &"")
	var cname := EmissaryLedger.company_short_name(comp_id)
	var bonus_g := int(res.get("bonus_gold", 0))
	var bonus_r := int(res.get("bonus_renown", 0))
	_set_status("Lowered %s Emissary flag (+%dg, +%d renown)." % [cname, bonus_g, bonus_r])
	if Game != null:
		Game.post_notice("Lowered %s Emissary Flag (+%d gold, +%d renown)!" % [cname, bonus_g, bonus_r])
	emissary_changed.emit(&"", 0)
	refresh()
	return res


## Host-only. Purchase a Merchant Trade Route commodity crate at `origin_outpost_id`,
## deduct gold from the active captain profile, and spawn the physical Carryable onto
## the moored ship deck (or nearby outpost pier).
func buy_trade_commodity(commodity_id: StringName) -> Dictionary:
	var prof: Profile = Game.profile if (Game != null and Game.profile != null) else (voyage_manager.profile if voyage_manager != null else null)
	var spawn_info := _resolve_trade_crate_spawn()
	var spawn_pos: Vector3 = spawn_info["position"] as Vector3
	var spawn_parent: Node = spawn_info["parent"] as Node

	var res := TradeRoutes.purchase_commodity(prof, commodity_id, origin_outpost_id, spawn_pos, spawn_parent)
	if not bool(res.get("ok", false)):
		var reason := String(res.get("reason", "Cannot purchase trade crate."))
		_set_status(reason)
		Audio.play_sfx(&"ui_back", Vector3.INF, -3.0)
		return res

	if Game != null and Game.profile != null and prof == Game.profile:
		Game.save()
	Audio.play_sfx(&"coin_jingle", Vector3.INF, -2.0)
	var item_node: Node = res.get("item", null) as Node
	var crate_name := String(item_node.get_meta(&"treasure_name", String(commodity_id))) if item_node != null else String(commodity_id)
	var dest_name := String(res.get("best_dest_name", "another port"))
	var cost := int(res.get("cost", 0))
	_set_status("Loaded %s (-%dg). Sail to %s for top profit!" % [crate_name, cost, dest_name])
	if Game != null:
		Game.post_notice("Bought %s (-%dg) - haul to %s for high demand!" % [crate_name, cost, dest_name])
	commodity_purchased.emit(commodity_id, cost, item_node)
	refresh()
	return res


func _resolve_trade_crate_spawn() -> Dictionary:
	var spawn_parent: Node = null
	if scene_root != null and is_instance_valid(scene_root):
		var entities := scene_root.get_node_or_null(^"Entities")
		spawn_parent = entities if entities != null else scene_root
	elif ship != null and is_instance_valid(ship) and ship.get_parent() != null:
		spawn_parent = ship.get_parent()
	elif get_parent() != null:
		spawn_parent = get_parent()

	var slot_idx := _trade_spawn_seq % 4
	_trade_spawn_seq += 1
	var offset_x := -0.75 + 0.50 * float(slot_idx)
	var spawn_pos := Vector3(offset_x, 2.0, 0.0)

	if ship != null and is_instance_valid(ship):
		var hs_v: Variant = ship.get(&"hull_scale")
		var hs := float(hs_v) if (hs_v != null and float(hs_v) > 0.01) else 1.0
		var deck_local := Vector3(offset_x * 0.7, 1.45, -1.25) * hs
		spawn_pos = (ship.global_transform * deck_local) if ship.is_inside_tree() else (ship.position + deck_local)
	elif archipelago != null and is_instance_valid(archipelago):
		var isl := archipelago.get_island_by_id(String(origin_outpost_id))
		if isl is Outpost:
			var op := isl as Outpost
			if op.merchant_stall != null and is_instance_valid(op.merchant_stall) and op.merchant_stall.is_inside_tree():
				spawn_pos = op.merchant_stall.global_position + Vector3(offset_x, 0.9, -1.6)
			elif op.is_inside_tree():
				spawn_pos = op.global_position + Vector3(offset_x, 2.5, 0.0)
	elif player_controller != null and is_instance_valid(player_controller):
		var p_node := player_controller.get_parent() as Node3D
		if p_node != null and p_node.is_inside_tree():
			spawn_pos = p_node.global_position + Vector3(offset_x, 1.0, -1.2)

	return {"position": spawn_pos, "parent": spawn_parent}


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

	var applied_mods := apply_economy_to_ship(ship, Game.profile, _crew_brains, world_director, inventory)
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


## Switch preferred captain armory weapons (&"cutlass"/&"boarding_axe" and &"pistol"/&"blunderbuss"),
## immediately updating Inventory + CombatComponent and saving to Game.profile.
func select_armory_loadout(melee_id: StringName, ranged_id: StringName) -> void:
	if melee_id == &"cutlass" or melee_id == &"boarding_axe":
		selected_melee_weapon = melee_id
	if ranged_id == &"pistol" or ranged_id == &"blunderbuss":
		selected_ranged_weapon = ranged_id
	if inventory != null and is_instance_valid(inventory):
		inventory.set_weapon_loadout(selected_melee_weapon, selected_ranged_weapon)
	if Game != null and Game.profile != null:
		Game.profile.data["melee_weapon"] = String(selected_melee_weapon)
		Game.profile.data["ranged_weapon"] = String(selected_ranged_weapon)
		Game.save()
	Audio.play_sfx(&"ui_select", Vector3.INF, -2.5)
	_set_status("Armory loadout: %s + %s" % [
		ToolMeshes.get_display_name(selected_melee_weapon),
		ToolMeshes.get_display_name(selected_ranged_weapon),
	])
	armory_loadout_changed.emit(selected_melee_weapon, selected_ranged_weapon)
	refresh()


## Cycle the captain's ship name through `Profile.PRESET_SHIP_NAMES`, save profile,
## repaint the moored ship's stern nameplate immediately, and emit `ship_name_changed`.
func cycle_ship_name() -> String:
	var presets: Array[String] = Profile.PRESET_SHIP_NAMES
	var cur := Game.profile.get_ship_name() if (Game != null and Game.profile != null) else Profile.DEFAULT_SHIP_NAME
	var idx := presets.find(cur)
	var next_name: String = presets[(idx + 1) % presets.size()] if idx >= 0 else presets[0]
	if Game != null and Game.profile != null:
		next_name = Game.profile.set_ship_name(next_name)
		Game.save()
	if ship != null and is_instance_valid(ship):
		if ship.has_method(&"set_ship_name"):
			ship.call(&"set_ship_name", next_name)
		else:
			var np := ship.get_node_or_null(^"ShipNameplate") as ShipNameplate
			if np != null:
				np.set_ship_name(next_name)
	Audio.play_sfx(&"ui_select", Vector3.INF, -2.5)
	_set_status("Ship christened: %s" % next_name)
	ship_name_changed.emit(next_name)
	refresh()
	return next_name


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
	director: WorldDirector = null,
	p_inventory: Inventory = null
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
		var glow_accent := Color.BLACK
		var hull_tint := Color.WHITE
		var sail_emblem_mode := int(mods.get("sail_emblem_mode", 0))
		var sail_cos := StringName(String(mods.get("sail_cosmetic_id", &"")))
		if sail_cos != &"":
			var se := Economy.get_unlock(sail_cos)
			# Heraldic emblem modes (4..7) paint vibrant multi-color stripes & medallions
			# directly in sail_wind.gdshader; keep sail_tint Color.WHITE so colors stay rich
			# while the unlock's "tint" still drives the Shipwright swatch chip.
			if sail_emblem_mode < 4 and se.has("tint") and se["tint"] is Color:
				sail_tint = se["tint"] as Color
		var flag_cos := StringName(String(mods.get("flag_id", &"")))
		if flag_cos != &"":
			var fe := Economy.get_unlock(flag_cos)
			if fe.has("tint") and fe["tint"] is Color:
				flag_tint = fe["tint"] as Color
		var hull_cos := StringName(String(mods.get("hull_livery_id", &"")))
		if hull_cos != &"":
			var he := Economy.get_unlock(hull_cos)
			if he.has("tint") and he["tint"] is Color:
				hull_tint = he["tint"] as Color
			if he.has("glow_accent") and he["glow_accent"] is Color:
				glow_accent = he["glow_accent"] as Color
		var livery_args: Array = [sail_tint, flag_tint, glow_accent, hull_tint]
		for m: Dictionary in target_ship.get_method_list():
			if String(m.get("name", "")) == "apply_livery":
				var m_args: Array = m.get("args", []) as Array
				if m_args.size() >= 5:
					livery_args.append(sail_emblem_mode)
				break
		target_ship.callv(&"apply_livery", livery_args)

	for b in crew_brains:
		if b != null and is_instance_valid(b):
			b.apply_modifiers(mods)

	var crew_uniform_id := StringName(String(mods.get("crew_uniform_id", &"")))
	_apply_crew_uniform(crew_brains, crew_uniform_id)

	if director != null and is_instance_valid(director):
		director.lookout_scale = float(mods.get("lookout_scale", 1.0))

	if p_inventory != null and is_instance_valid(p_inventory):
		p_inventory.apply_tool_modifiers(mods)

	return bridged


static func _apply_crew_uniform(crew_brains: Array[CrewBrain], uniform_id: StringName) -> void:
	var has_uniform := uniform_id != &""
	var base_primary := Color.WHITE
	var base_accent := Color.WHITE
	if has_uniform:
		var ue := Economy.get_unlock(uniform_id)
		if ue.is_empty() or not (ue.get("tint") is Color):
			has_uniform = false
		else:
			base_primary = ue["tint"] as Color
			base_accent = (ue["accent_tint"] as Color) if (ue.get("accent_tint") is Color) else base_primary.lightened(0.25)

	for idx in crew_brains.size():
		var b := crew_brains[idx]
		if b == null or not is_instance_valid(b):
			continue
		if b.pawn == null or not is_instance_valid(b.pawn):
			continue
		var cv := _character_visual_of(b.pawn)
		if cv == null:
			continue
		if not cv.has_meta(&"default_primary_tint"):
			cv.set_meta(&"default_primary_tint", cv._primary_tint)
			cv.set_meta(&"default_secondary_tint", cv._secondary_tint)
		if not has_uniform:
			var def_p: Color = cv.get_meta(&"default_primary_tint", cv._primary_tint) as Color
			var def_a: Color = cv.get_meta(&"default_secondary_tint", cv._secondary_tint) as Color
			cv.set_tint(def_p, def_a)
			continue
		# Subtle per-persona tonal offset so Barnaby, Maren & Pip keep individual charm
		# while reading unmistakably as a unified pirate crew.
		var p_col := base_primary
		var a_col := base_accent
		match b.persona_id:
			&"helmsman":
				pass
			&"lookout":
				p_col = base_primary.lightened(0.10)
				a_col = base_accent.lightened(0.06)
			&"carpenter":
				p_col = base_primary.darkened(0.10)
				a_col = base_accent.darkened(0.06)
			_:
				if idx % 3 == 1:
					p_col = base_primary.lightened(0.08)
					a_col = base_accent.lightened(0.05)
				elif idx % 3 == 2:
					p_col = base_primary.darkened(0.08)
					a_col = base_accent.darkened(0.05)
		cv.set_tint(p_col, a_col)


static func _character_visual_of(p: Pawn) -> CharacterVisual:
	if p == null:
		return null
	var cv := p.get_node_or_null(^"Visual/CharacterVisual") as CharacterVisual
	if cv != null:
		return cv
	var found := p.find_children("*", "CharacterVisual", true, false)
	if not found.is_empty():
		return found[0] as CharacterVisual
	return null


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
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.05, 0.04, 0.02, 0.58)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.theme = _theme
	add_child(_backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
		[TAB_LOG, "Captain's Log"],
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
	_log_box = _make_scroll_page(body_holder, "CaptainsLogPage", TAB_LOG)
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
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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

	# Trading Company Emissary Desk (top section above voyage cards)
	_voyage_list_box.add_child(_build_emissary_desk_card())

	# Merchant Commodity Trade Manifest for the current Outpost
	_voyage_list_box.add_child(_build_trade_manifest_card())

	# Active voyage banner
	if voyage_manager != null and voyage_manager.has_active_voyage():
		var av := voyage_manager.active_voyage
		var banner := _make_card_panel(Color(0.96, 0.90, 0.74, 0.96), HudIcons.COL_CRIMSON)
		var bv := VBoxContainer.new()
		bv.add_theme_constant_override("separation", 4)
		banner.add_child(bv)
		var hdr := Label.new()
		hdr.text = _to_ascii("ACTIVE VOYAGE: %s" % String(av.get("title", "Voyage")))
		hdr.add_theme_font_size_override("font_size", 17)
		hdr.add_theme_color_override("font_color", HudIcons.COL_CRIMSON)
		bv.add_child(hdr)
		var obj := Label.new()
		obj.text = _to_ascii(voyage_manager.get_current_objective())
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


func _build_emissary_desk_card() -> PanelContainer:
	var ledger: EmissaryLedger = voyage_manager.emissary if voyage_manager != null else null
	var active := ledger != null and ledger.is_active()
	var card := _make_card_panel(
		Color(0.96, 0.90, 0.74, 0.98) if active else Color(0.92, 0.85, 0.70, 0.96),
		HudIcons.COL_BRASS if active else HudIcons.COL_INK_SOFT
	)
	card.name = "EmissaryDeskCard"

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)

	var hdr := Label.new()
	hdr.name = "EmissaryDeskTitle"
	hdr.text = "TRADING COMPANY EMISSARY DESK"
	hdr.add_theme_font_size_override("font_size", 16)
	hdr.add_theme_color_override("font_color", HudIcons.COL_CRIMSON if active else HudIcons.COL_INK)
	v.add_child(hdr)

	if active:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		v.add_child(row)

		var cname := EmissaryLedger.company_short_name(ledger.active_company)
		var roman := ledger.get_grade_roman()
		var mult := ledger.get_multiplier()
		var status_lbl := Label.new()
		status_lbl.name = "EmissaryStatusLabel"
		status_lbl.text = _to_ascii("Flying: %s Emissary %s (%.2fx Payout)" % [cname, roman, mult])
		status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		status_lbl.add_theme_font_size_override("font_size", 15)
		status_lbl.add_theme_color_override("font_color", Color(0.56, 0.36, 0.06))
		row.add_child(status_lbl)

		var bonus_gold := ledger.get_lower_bonus_gold()
		var lower_btn := Button.new()
		lower_btn.name = "LowerEmissaryButton"
		lower_btn.text = "Lower Flag (+%dg)" % bonus_gold
		lower_btn.custom_minimum_size = Vector2(186.0, 38.0)
		_style_highlight_button(lower_btn, true)
		lower_btn.pressed.connect(func() -> void: lower_emissary_flag())
		row.add_child(lower_btn)
	else:
		var info_lbl := Label.new()
		info_lbl.name = "EmissaryStatusLabel"
		info_lbl.text = "Raise an Emissary flag to multiply matching payouts up to 2.50x (higher hunter risk)."
		info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_lbl.add_theme_font_size_override("font_size", 13)
		info_lbl.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
		v.add_child(info_lbl)

		var btn_row := HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 10)
		v.add_child(btn_row)

		var specs: Array[Array] = [
			[&"gilded_compass", "Raise Gilded Compass"],
			[&"sunken_archive", "Raise Sunken Archive"],
			[&"iron_tide", "Raise Iron Tide"],
		]
		for spec: Array in specs:
			var cid: StringName = spec[0]
			var label_txt: String = String(spec[1])
			var rbtn := Button.new()
			rbtn.name = "RaiseEmissary_" + String(cid)
			rbtn.text = label_txt
			rbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rbtn.custom_minimum_size = Vector2(0.0, 38.0)
			rbtn.pressed.connect(func() -> void: raise_emissary_flag(cid))
			btn_row.add_child(rbtn)

	return card


func _build_trade_manifest_card() -> PanelContainer:
	var port_name := TradeRoutes.get_outpost_name(origin_outpost_id)
	var manifest := TradeRoutes.get_outpost_manifest(origin_outpost_id)
	var prof: Profile = Game.profile if (Game != null and Game.profile != null) else (voyage_manager.profile if voyage_manager != null else null)
	var gold := int(prof.data.get("gold", 0)) if prof != null else 0

	var card := _make_card_panel(Color(0.93, 0.87, 0.72, 0.98), HudIcons.COL_BRASS)
	card.name = "TradeManifestCard"

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)

	var hdr := Label.new()
	hdr.name = "TradeManifestTitle"
	hdr.text = _to_ascii("MERCHANT TRADE MANIFEST - %s" % port_name.to_upper())
	hdr.add_theme_font_size_override("font_size", 16)
	hdr.add_theme_color_override("font_color", HudIcons.COL_INK)
	v.add_child(hdr)

	var sub := Label.new()
	sub.text = "Buy surplus cargo crates here and sail to high-demand outposts for 1.9x-2.3x arbitrage!"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	v.add_child(sub)

	for entry: Dictionary in manifest:
		var cid := entry["id"] as StringName
		var cname := String(entry["name"])
		var buy_price := int(entry["buy_price"])
		var dest_name := String(entry["best_dest_name"])
		var best_sell := int(entry["best_sell_price"])
		var profit := int(entry["projected_profit"])
		var demand_lbl := String(entry["demand_label"])

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		v.add_child(row)

		var info_v := VBoxContainer.new()
		info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_v.add_theme_constant_override("separation", 2)
		row.add_child(info_v)

		var name_lbl := Label.new()
		name_lbl.text = _to_ascii("%s (Buy %dg)" % [cname, buy_price])
		name_lbl.add_theme_font_size_override("font_size", 15)
		name_lbl.add_theme_color_override("font_color", HudIcons.COL_INK)
		info_v.add_child(name_lbl)

		var route_lbl := Label.new()
		route_lbl.text = _to_ascii("Best Port: %s  |  Payout: %dg (+%dg profit)  |  %s" % [
			dest_name, best_sell, profit, demand_lbl])
		route_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		route_lbl.add_theme_font_size_override("font_size", 13)
		route_lbl.add_theme_color_override("font_color", Color(0.45, 0.30, 0.10))
		info_v.add_child(route_lbl)

		var buy_btn := Button.new()
		buy_btn.name = "BuyCommodity_" + String(cid)
		buy_btn.text = "Buy Crate (%dg)" % buy_price
		buy_btn.custom_minimum_size = Vector2(168.0, 38.0)
		buy_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		buy_btn.disabled = (gold < buy_price)
		buy_btn.tooltip_text = "Load %s onto your moored ship deck" % cname if gold >= buy_price else "Requires %dg" % buy_price
		buy_btn.pressed.connect(func() -> void: buy_trade_commodity(cid))
		row.add_child(buy_btn)

	return card


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
	title_lbl.text = _to_ascii("%s%s" % [prefix, String(voyage.get("title", "Voyage"))])
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", HudIcons.COL_CRIMSON if is_story else HudIcons.COL_INK)
	info_v.add_child(title_lbl)

	var meta_lbl := Label.new()
	meta_lbl.text = _to_ascii("%s  |  %s  |  Destination: %s  |  Reward: ~%d Gold, +%d Renown" % [
		comp_name, shape_name, island_name, est_gold, est_renown])
	meta_lbl.add_theme_font_size_override("font_size", 13)
	meta_lbl.add_theme_color_override("font_color", Color(0.45, 0.30, 0.10))
	info_v.add_child(meta_lbl)

	if briefing != "":
		var brief_lbl := Label.new()
		brief_lbl.text = _to_ascii(briefing)
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
		rank_lbl.text = _to_ascii("Rank %d -- %s" % [int(prog["rank"]), String(prog["title"])])
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

	# 2a. Custom Stern Ship Nameplate Row
	var name_card := _make_card_panel(Color(0.91, 0.84, 0.70, 0.96), HudIcons.COL_BRASS)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	name_card.add_child(name_row)

	var name_hdr := Label.new()
	name_hdr.text = "SHIP NAMEPLATE"
	name_hdr.add_theme_font_size_override("font_size", 16)
	name_hdr.add_theme_color_override("font_color", HudIcons.COL_INK)
	name_row.add_child(name_hdr)

	var cur_ship_name := prof.get_ship_name() if prof != null else Profile.DEFAULT_SHIP_NAME
	var name_val := Label.new()
	name_val.name = "ShipNameValueLabel"
	name_val.text = "\"%s\"" % cur_ship_name
	name_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_val.add_theme_font_size_override("font_size", 17)
	name_val.add_theme_color_override("font_color", HudIcons.COL_CRIMSON)
	name_row.add_child(name_val)

	var cycle_btn := Button.new()
	cycle_btn.name = "CycleShipNameButton"
	cycle_btn.text = "Cycle Ship Name"
	cycle_btn.custom_minimum_size = Vector2(172.0, 36.0)
	cycle_btn.pressed.connect(func() -> void: cycle_ship_name())
	name_row.add_child(cycle_btn)
	_shipwright_box.add_child(name_card)

	# 2b. Armory Loadout Selector (Melee & Firearm)
	if inventory != null and is_instance_valid(inventory):
		selected_melee_weapon = inventory.melee_weapon
		selected_ranged_weapon = inventory.ranged_weapon
	var armory_card := _make_card_panel(Color(0.91, 0.84, 0.70, 0.96), HudIcons.COL_BRASS)
	var armory_row := HBoxContainer.new()
	armory_row.add_theme_constant_override("separation", 10)
	armory_card.add_child(armory_row)

	var armory_lbl := Label.new()
	armory_lbl.text = "ARMORY LOADOUT"
	armory_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	armory_lbl.add_theme_font_size_override("font_size", 16)
	armory_row.add_child(armory_lbl)

	var melee_lbl := Label.new()
	melee_lbl.text = "Melee:"
	melee_lbl.add_theme_font_size_override("font_size", 14)
	melee_lbl.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	armory_row.add_child(melee_lbl)

	for m_spec: Array in [[&"cutlass", "Cutlass"], [&"boarding_axe", "Boarding Axe"]]:
		var mid: StringName = m_spec[0]
		var mlabel: String = m_spec[1]
		var mbtn := Button.new()
		mbtn.name = "ArmoryMelee_" + String(mid)
		mbtn.text = mlabel
		_style_highlight_button(mbtn, selected_melee_weapon == mid)
		mbtn.pressed.connect(func() -> void: select_armory_loadout(mid, selected_ranged_weapon))
		armory_row.add_child(mbtn)

	var sep_lbl := Label.new()
	sep_lbl.text = "|"
	sep_lbl.add_theme_font_size_override("font_size", 15)
	sep_lbl.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	armory_row.add_child(sep_lbl)

	var ranged_lbl := Label.new()
	ranged_lbl.text = "Firearm:"
	ranged_lbl.add_theme_font_size_override("font_size", 14)
	ranged_lbl.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	armory_row.add_child(ranged_lbl)

	for r_spec: Array in [[&"pistol", "Flintlock Pistol"], [&"blunderbuss", "Blunderbuss"]]:
		var rid: StringName = r_spec[0]
		var rlabel: String = r_spec[1]
		var rbtn := Button.new()
		rbtn.name = "ArmoryRanged_" + String(rid)
		rbtn.text = rlabel
		_style_highlight_button(rbtn, selected_ranged_weapon == rid)
		rbtn.pressed.connect(func() -> void: select_armory_loadout(selected_melee_weapon, rid))
		armory_row.add_child(rbtn)
	_shipwright_box.add_child(armory_card)

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

			if entry.has("tint") and entry["tint"] is Color:
				if entry.has("accent_tint") and entry["accent_tint"] is Color:
					var swatch_box := HBoxContainer.new()
					swatch_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
					swatch_box.add_theme_constant_override("separation", 3)
					swatch_box.add_child(_make_swatch_chip(entry["tint"] as Color, String(uid)))
					swatch_box.add_child(_make_accent_swatch_chip(entry["accent_tint"] as Color, String(uid)))
					h.add_child(swatch_box)
				else:
					h.add_child(_make_swatch_chip(entry["tint"] as Color, String(uid)))

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


func _rebuild_log_tab() -> void:
	if _log_box == null:
		return
	_clear_children(_log_box)
	var prof: Profile = Game.profile if Game != null else null
	var ship_name := prof.get_ship_name() if prof != null else Profile.DEFAULT_SHIP_NAME
	var cls_id := ship.ship_class if (ship != null and is_instance_valid(ship)) else selected_ship_class
	var cls_label := String(cls_id).capitalize()
	var gold := int(prof.data.get("gold", 0)) if prof != null else 0
	var stats: Dictionary = prof.get_stats() if prof != null else {}

	# 1. Vessel & Deeds Header Card
	var deeds_card := _make_card_panel(Color(0.95, 0.89, 0.74, 0.98), HudIcons.COL_INK)
	deeds_card.name = "LogDeedsCard"
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 8)
	deeds_card.add_child(dv)

	var vessel_hdr := Label.new()
	vessel_hdr.name = "LogVesselLabel"
	vessel_hdr.text = _to_ascii("%s  -  %s" % [ship_name, cls_label])
	vessel_hdr.add_theme_font_size_override("font_size", 21)
	vessel_hdr.add_theme_color_override("font_color", HudIcons.COL_INK)
	dv.add_child(vessel_hdr)

	var deeds_grid := GridContainer.new()
	deeds_grid.name = "LogDeedsGrid"
	deeds_grid.columns = 3
	deeds_grid.add_theme_constant_override("h_separation", 24)
	deeds_grid.add_theme_constant_override("v_separation", 6)
	dv.add_child(deeds_grid)

	var deed_rows: Array[String] = [
		"Gold Purse: %d Gold" % gold,
		"Voyages Completed: %d" % int(stats.get("voyages_completed", 0)),
		"Treasures Sold: %d" % int(stats.get("chests_sold", 0)),
		"Total Gold Earned: %d Gold" % int(stats.get("gold_earned", 0)),
		"Bosses Vanquished: %d" % int(stats.get("bosses_defeated", 0)),
		"Ships Lost: %d" % int(stats.get("times_sunk", 0)),
	]
	for item_txt in deed_rows:
		var lbl := Label.new()
		lbl.text = _to_ascii(item_txt)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
		deeds_grid.add_child(lbl)
	_log_box.add_child(deeds_card)

	# 2. Trading Company Standing Section (all 3 companies with heraldic ink-framed ProgressBars)
	var stand_card := _make_card_panel(Color(0.91, 0.84, 0.69, 0.96), HudIcons.COL_INK_SOFT)
	stand_card.name = "LogStandingCard"
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 10)
	stand_card.add_child(sv)

	var shdr := Label.new()
	shdr.text = "TRADING COMPANY STANDING"
	shdr.add_theme_font_size_override("font_size", 16)
	shdr.add_theme_color_override("font_color", HudIcons.COL_CRIMSON)
	sv.add_child(shdr)

	var company_order: Array[StringName] = [&"gilded_compass", &"iron_tide", &"sunken_archive"]
	for cid: StringName in company_order:
		var cmeta: Dictionary = Economy.COMPANIES.get(cid, {})
		var cprog: Dictionary = Economy.get_company_progress(prof, cid)
		var cname := String(cmeta.get("name", String(cid).capitalize()))
		var ccol: Color = cmeta.get("color", HudIcons.COL_GOLD) as Color
		var rank := int(cprog.get("rank", 1))
		var rtitle := String(cprog.get("title", "Swab"))
		var pts := int(cprog.get("points", 0))
		var next_thr := int(cprog.get("next_threshold", pts))
		var is_max := bool(cprog.get("is_max", false))
		var frac := float(cprog.get("progress_frac", 0.0))

		var row_v := VBoxContainer.new()
		row_v.add_theme_constant_override("separation", 4)
		sv.add_child(row_v)

		var row_top := HBoxContainer.new()
		row_top.add_theme_constant_override("separation", 12)
		row_v.add_child(row_top)

		var name_lbl := Label.new()
		name_lbl.text = _to_ascii("%s   (Rank %d - %s)" % [cname, rank, rtitle])
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 15)
		name_lbl.add_theme_color_override("font_color", HudIcons.COL_INK)
		row_top.add_child(name_lbl)

		var ren_lbl := Label.new()
		ren_lbl.text = _to_ascii("%d Renown (MAX)" % pts if is_max else "%d / %d Renown" % [pts, next_thr])
		ren_lbl.add_theme_font_size_override("font_size", 14)
		ren_lbl.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
		row_top.add_child(ren_lbl)

		var bar := ProgressBar.new()
		bar.name = "StandingBar_" + String(cid)
		bar.min_value = 0.0
		bar.max_value = 100.0
		bar.value = clampf(frac * 100.0, 0.0, 100.0)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0.0, 14.0)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var bg_sb := StyleBoxFlat.new()
		bg_sb.bg_color = Color(0.84, 0.77, 0.62, 0.96)
		bg_sb.border_color = HudIcons.COL_INK
		bg_sb.set_border_width_all(2)
		bg_sb.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("background", bg_sb)

		var fill_sb := StyleBoxFlat.new()
		fill_sb.bg_color = ccol
		fill_sb.border_color = HudIcons.COL_INK
		fill_sb.set_border_width_all(1)
		fill_sb.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("fill", fill_sb)
		row_v.add_child(bar)
	_log_box.add_child(stand_card)

	# 3. Archipelago Discovery Ledger (2-column ink checklist)
	var disc_card := _make_card_panel(Color(0.91, 0.84, 0.69, 0.96), HudIcons.COL_INK_SOFT)
	disc_card.name = "LogDiscoveryCard"
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	disc_card.add_child(lv)

	var disc_lookup: Dictionary = {}
	if prof != null:
		var raw_disc: Variant = prof.data.get("discoveries", [])
		if raw_disc is Array:
			for d_item in (raw_disc as Array):
				disc_lookup[String(d_item)] = true

	var isl_entries: Array[Dictionary] = []
	if archipelago != null and is_instance_valid(archipelago):
		isl_entries = archipelago.get_map_data()
	else:
		isl_entries = VoyageComposer.default_archipelago_roster()

	var charted := 0
	for e in isl_entries:
		var iid := String(e.get("island_id", e.get("id", "")))
		if disc_lookup.has(iid):
			charted += 1

	var lhdr := Label.new()
	lhdr.name = "ChartedWatersHeader"
	lhdr.text = _to_ascii("CHARTED WATERS: %d / %d ISLANDS" % [charted, isl_entries.size()])
	lhdr.add_theme_font_size_override("font_size", 16)
	lhdr.add_theme_color_override("font_color", HudIcons.COL_CRIMSON)
	lv.add_child(lhdr)

	var ledger_grid := GridContainer.new()
	ledger_grid.name = "DiscoveryLedgerGrid"
	ledger_grid.columns = 2
	ledger_grid.add_theme_constant_override("h_separation", 22)
	ledger_grid.add_theme_constant_override("v_separation", 6)
	lv.add_child(ledger_grid)

	for e in isl_entries:
		var iid := String(e.get("island_id", e.get("id", "")))
		var iname := String(e.get("display_name", e.get("name", iid.capitalize())))
		var raw_arch := String(e.get("archetype", e.get("kind", "island")))
		var arch_lbl := raw_arch.replace("_", " ").capitalize()
		var found := disc_lookup.has(iid)

		var row_lbl := Label.new()
		row_lbl.name = "DiscoveryItem_" + iid
		row_lbl.text = _to_ascii("[%s] %s (%s)" % ["X" if found else " ", iname, arch_lbl])
		row_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_lbl.add_theme_font_size_override("font_size", 14)
		row_lbl.add_theme_color_override("font_color", HudIcons.COL_INK if found else Color(0.46, 0.39, 0.29))
		ledger_grid.add_child(row_lbl)
	_log_box.add_child(disc_card)


# ==============================================================================
# Style Helpers
# ==============================================================================

func _set_status(msg: String) -> void:
	if _status_label != null:
		_status_label.text = _to_ascii(msg)


static func _to_ascii(text: String) -> String:
	var out := text.replace(char(0x2014), "--").replace(char(0x2013), "-")
	out = out.replace(char(0x00B7), "|").replace(char(0x2022), "*")
	out = out.replace(char(0x2018), "'").replace(char(0x2019), "'")
	out = out.replace(char(0x201C), "\"").replace(char(0x201D), "\"")
	out = out.replace(char(0x2026), "...")
	return out


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


static func _make_swatch_chip(swatch_color: Color, uid_str: String) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.name = "Swatch_" + uid_str
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.13, 0.08, 1.0)
	sb.border_color = HudIcons.COL_INK
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(2)
	frame.add_theme_stylebox_override("panel", sb)

	var chip := ColorRect.new()
	chip.name = "SwatchColor"
	chip.custom_minimum_size = Vector2(18.0, 18.0)
	chip.color = swatch_color
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(chip)
	return frame


static func _make_accent_swatch_chip(accent_color: Color, uid_str: String) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.name = "SwatchAccent_" + uid_str
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.13, 0.08, 1.0)
	sb.border_color = HudIcons.COL_INK
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(2)
	frame.add_theme_stylebox_override("panel", sb)

	var chip := ColorRect.new()
	chip.name = "SwatchAccentColor"
	chip.custom_minimum_size = Vector2(12.0, 18.0)
	chip.color = accent_color
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(chip)
	return frame


static func _clear_children(container: Node) -> void:
	for c in container.get_children():
		container.remove_child(c)
		c.queue_free()
