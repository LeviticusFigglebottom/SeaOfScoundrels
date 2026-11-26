class_name GameHUD
extends CanvasLayer
## Minimal, diegetic parchment-and-ink HUD for Sea of Scoundrels.
##
## Faithful to docs/DESIGN.md: no minimap and no arcade clutter. Provides:
## - Subtle center crosshair dot with tactile ink hit-confirm ticks & brass parry arcs
## - Peripheral damage ink-wash vignette & low-HP heartbeat pulse (hidden at full HP)
## - Faint health & stamina pips (fade out cleanly when full & out of combat)
## - Contextual interaction prompt ribbon driven by `PlayerController.focus_prompt`
## - Subtle active tool / ammo / ship supplies chip with hull leak & flooding urgency
## - Queued top-center Crew Callout & Notice parchment banner (`Game.notice`)
## - Upper-sky first-launch / chapter Diegetic Voyage Title Card (`show_voyage_title`)
## - Quiet top-right Gold & Voyage Objective whisper slip
## - Circular brass Spyglass vignette + horizon sighting readout
## - 11-wedge Item Radial (`Tab`) and 9-wedge Crew Command Wheel (`Q`)
## - Pause / Save / Quality Presets / Audio Sliders / LAN Co-op / Controls overlay (`Escape`)

signal crew_order_issued(order: StringName)
signal pause_changed(open: bool)
signal quality_changed(target: StringName, level: int)

const ITEM_SLICE_HINTS := {
	&"cutlass": "Light combo | Hold heavy | RMB parry",
	&"boarding_axe": "Heavy cleave | Guard crush | RMB parry",
	&"pistol": "Flintlock shot | RMB aim",
	&"blunderbuss": "6-pellet spread | Short range | RMB aim",
	&"compass": "True North | Hold RMB count paces",
	&"spyglass": "RMB zoom & sight horizon",
	&"lantern": "LMB toggle flame | RMB raise",
	&"map": "Treasure chart | RMB read",
	&"shovel": "Dig buried treasure mounds",
	&"bucket": "Bail bilge water | RMB splash",
	&"planks": "Patch open hull breaches",
	&"tankard": "Drink grog (+15 HP) | RMB cheers",
	&"instrument": "Strike up a crew shanty",
}

const CREW_COMMAND_SLICES: Array[Dictionary] = [
	{"id": &"helm", "label": "Man Helm", "hint": "Hold steady course", "icon": &"helm"},
	{"id": &"trim", "label": "Trim Sails", "hint": "Catch full wind", "icon": &"trim"},
	{"id": &"anchor_drop", "label": "Drop Anchor", "hint": "Halt the sloop", "icon": &"anchor_drop"},
	{"id": &"anchor_raise", "label": "Raise Anchor", "hint": "Weigh anchor & sail", "icon": &"anchor_raise"},
	{"id": &"cannons", "label": "Man Cannons", "hint": "Engage hostile ships", "icon": &"cannons"},
	{"id": &"repair", "label": "Repair & Bail", "hint": "Patch leaks & bail", "icon": &"repair"},
	{"id": &"follow", "label": "Follow Me", "hint": "Stay at captain's heel", "icon": &"follow"},
	{"id": &"fetch_treasure", "label": "Fetch Loot", "hint": "Haul chests aboard", "icon": &"fetch_treasure"},
	{"id": &"shanty", "label": "Play Shanty", "hint": "Join in a sea reel", "icon": &"shanty"},
]

const VOYAGE_TITLE_FADE_IN := 0.45
const VOYAGE_TITLE_FADE_OUT := 0.90

@export var input_enabled: bool = true
@export var force_show_vitals: bool = false
@export var force_show_whisper: bool = false

var pawn: Pawn = null
var player_controller: PlayerController = null
var inventory: Inventory = null
var combat: CombatComponent = null
var ship: Ship = null
var voyage_manager: VoyageManager = null
var sky_rig: Node = null
var user_settings: UserSettings = null

var item_radial: RadialWheel = null
var command_wheel: RadialWheel = null
var pause_overlay: Control = null
var pause_open: bool = false
var crew_hold_fire: bool = false

var _crew_brains: Array[CrewBrain] = []
var _root: Control = null
var _theme: Theme = null
var _damage_vignette: _DamageVignette = null
var _spyglass_view: _SpyglassOverlay = null
var _crosshair_view: _CrosshairView = null
var _vitals_view: _VitalsView = null

# Banner queue (top-center)
var _banner_panel: PanelContainer = null
var _banner_label: Label = null
var _banner_queue: Array[String] = []
var _banner_current: String = ""
var _banner_timer: float = 0.0
var _banner_alpha: float = 0.0

# Boss encounter bar (top-center below banner; hidden outside active boss fights)
var _boss_panel: PanelContainer = null
var _boss_label: Label = null
var _boss_bar: ProgressBar = null
var _boss_active: bool = false
var _boss_alpha: float = 0.0

# Diegetic Voyage Title Card (upper-middle sky; non-blocking)
var _voyage_card_panel: PanelContainer = null
var _voyage_card_title_label: Label = null
var _voyage_card_rule: ColorRect = null
var _voyage_card_subtitle_label: Label = null
var _voyage_card_active: bool = false
var _voyage_card_elapsed: float = 0.0
var _voyage_card_hold: float = 4.2
var _voyage_card_alpha: float = 0.0

# Context prompt & helm-only sailing trim telemetry pill (bottom-center)
const SAILING_STATION_KINDS: Array[StringName] = [&"helm", &"sail_length", &"sail_angle"]
var _prompt_panel: PanelContainer = null
var _prompt_label: Label = null
var _prompt_alpha: float = 0.0
var _sailing_pill_panel: PanelContainer = null
var _sailing_pill_label: Label = null

# Active tool / supplies chip (bottom-right)
var _tool_panel: PanelContainer = null
var _tool_title_label: Label = null
var _tool_meta_label: Label = null
var _tool_flash_timer: float = 0.0
var _hull_alert_active: bool = false

# Gold & Voyage whisper (top-right)
var _whisper_panel: PanelContainer = null
var _gold_label: Label = null
var _voyage_title_label: Label = null
var _voyage_obj_label: Label = null
var _whisper_timer: float = 0.0
var _whisper_alpha: float = 0.0
var _last_gold: int = -1
var _custom_voyage_title: String = ""
var _custom_voyage_obj: String = ""

# Vitals fade & peripheral damage vignette tracking
var _vitals_show_timer: float = 0.0
var _vitals_alpha: float = 0.0
var _last_hp: float = -1.0
var _last_stamina: float = -1.0
var _damage_flash: float = 0.0
var _low_hp_clock: float = 0.0

# Pause menu widget references
var _ocean_qual_btns: Array[Button] = []
var _cloud_qual_btns: Array[Button] = []
var _bus_sliders: Dictionary = {}  # StringName -> HSlider
var _coop_addr_edit: LineEdit = null
var _coop_port_edit: LineEdit = null
var _coop_status_label: Label = null


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_theme = HudIcons.build_parchment_theme()
	_build_ui()
	if Game != null and not Game.notice.is_connected(_on_game_notice):
		Game.notice.connect(_on_game_notice)
	if Game != null and Game.profile != null:
		_last_gold = int(Game.profile.data.get("gold", 0))
	_sync_quality_button_states()


func _exit_tree() -> void:
	_disconnect_signals()
	if Game != null and Game.notice.is_connected(_on_game_notice):
		Game.notice.disconnect(_on_game_notice)


## Bind live player, ship, combat, inventory, voyage manager, and sky rig references.
func bind(
	p_pawn: Pawn,
	p_controller: PlayerController = null,
	p_inventory: Inventory = null,
	p_combat: CombatComponent = null,
	p_ship: Ship = null,
	p_voyage_manager: VoyageManager = null,
	p_sky_rig: Node = null
) -> void:
	_disconnect_signals()
	pawn = p_pawn
	player_controller = p_controller
	inventory = p_inventory
	combat = p_combat
	ship = p_ship
	voyage_manager = p_voyage_manager
	sky_rig = p_sky_rig

	if pawn != null:
		if player_controller == null:
			for c in pawn.get_children():
				if c is PlayerController:
					player_controller = c as PlayerController
					break
		if inventory == null:
			for c in pawn.get_children():
				if c is Inventory:
					inventory = c as Inventory
					break
		if combat == null:
			for c in pawn.get_children():
				if c is CombatComponent:
					combat = c as CombatComponent
					break

	_last_hp = pawn.health if (pawn != null and is_instance_valid(pawn)) else -1.0
	_damage_flash = 0.0
	_low_hp_clock = 0.0
	_connect_signals()
	_sync_damage_vignette(0.0)
	_refresh_item_radial_entries()
	_refresh_tool_chip()
	_tick_sailing_telemetry()
	_sync_quality_button_states()


func _connect_signals() -> void:
	if inventory != null:
		if not inventory.item_equipped.is_connected(_on_item_equipped):
			inventory.item_equipped.connect(_on_item_equipped)
		if not inventory.spyglass_zoom_changed.is_connected(_on_spyglass_zoom):
			inventory.spyglass_zoom_changed.connect(_on_spyglass_zoom)
		if not inventory.sighting_updated.is_connected(_on_sighting_updated):
			inventory.sighting_updated.connect(_on_sighting_updated)
		if not inventory.lantern_toggled.is_connected(_on_tool_state_changed):
			inventory.lantern_toggled.connect(_on_tool_state_changed)
		if not inventory.bucket_changed.is_connected(_on_tool_state_changed):
			inventory.bucket_changed.connect(_on_tool_state_changed)
		if not inventory.shanty_playing_changed.is_connected(_on_tool_state_changed):
			inventory.shanty_playing_changed.connect(_on_tool_state_changed)
		if not inventory.shanty_instrument_changed.is_connected(_on_tool_state_changed):
			inventory.shanty_instrument_changed.connect(_on_tool_state_changed)
		if not inventory.compass_pace_counted.is_connected(_on_compass_pace_counted):
			inventory.compass_pace_counted.connect(_on_compass_pace_counted)
		if not inventory.grog_toast_raised.is_connected(_on_grog_toast_raised):
			inventory.grog_toast_raised.connect(_on_grog_toast_raised)
	if combat != null:
		if not combat.hit_landed.is_connected(_on_combat_hit_landed):
			combat.hit_landed.connect(_on_combat_hit_landed)
		if not combat.target_hit.is_connected(_on_combat_target_hit):
			combat.target_hit.connect(_on_combat_target_hit)
		if not combat.parried.is_connected(_on_combat_parried):
			combat.parried.connect(_on_combat_parried)
	if pawn != null:
		if not pawn.damaged.is_connected(_on_pawn_damaged):
			pawn.damaged.connect(_on_pawn_damaged)
		if not pawn.station_changed.is_connected(_on_pawn_station_changed):
			pawn.station_changed.connect(_on_pawn_station_changed)
	if voyage_manager != null:
		if not voyage_manager.voyage_started.is_connected(_on_voyage_started):
			voyage_manager.voyage_started.connect(_on_voyage_started)
		if not voyage_manager.voyage_stage_changed.is_connected(_on_voyage_stage_changed):
			voyage_manager.voyage_stage_changed.connect(_on_voyage_stage_changed)
	if ship != null:
		if not ship.cannon_ordnance_changed.is_connected(_on_tool_state_changed):
			ship.cannon_ordnance_changed.connect(_on_tool_state_changed)


func _disconnect_signals() -> void:
	if inventory != null and is_instance_valid(inventory):
		if inventory.item_equipped.is_connected(_on_item_equipped):
			inventory.item_equipped.disconnect(_on_item_equipped)
		if inventory.spyglass_zoom_changed.is_connected(_on_spyglass_zoom):
			inventory.spyglass_zoom_changed.disconnect(_on_spyglass_zoom)
		if inventory.sighting_updated.is_connected(_on_sighting_updated):
			inventory.sighting_updated.disconnect(_on_sighting_updated)
		if inventory.lantern_toggled.is_connected(_on_tool_state_changed):
			inventory.lantern_toggled.disconnect(_on_tool_state_changed)
		if inventory.bucket_changed.is_connected(_on_tool_state_changed):
			inventory.bucket_changed.disconnect(_on_tool_state_changed)
		if inventory.shanty_playing_changed.is_connected(_on_tool_state_changed):
			inventory.shanty_playing_changed.disconnect(_on_tool_state_changed)
		if inventory.shanty_instrument_changed.is_connected(_on_tool_state_changed):
			inventory.shanty_instrument_changed.disconnect(_on_tool_state_changed)
		if inventory.compass_pace_counted.is_connected(_on_compass_pace_counted):
			inventory.compass_pace_counted.disconnect(_on_compass_pace_counted)
		if inventory.grog_toast_raised.is_connected(_on_grog_toast_raised):
			inventory.grog_toast_raised.disconnect(_on_grog_toast_raised)
	if combat != null and is_instance_valid(combat):
		if combat.hit_landed.is_connected(_on_combat_hit_landed):
			combat.hit_landed.disconnect(_on_combat_hit_landed)
		if combat.target_hit.is_connected(_on_combat_target_hit):
			combat.target_hit.disconnect(_on_combat_target_hit)
		if combat.parried.is_connected(_on_combat_parried):
			combat.parried.disconnect(_on_combat_parried)
	if pawn != null and is_instance_valid(pawn):
		if pawn.damaged.is_connected(_on_pawn_damaged):
			pawn.damaged.disconnect(_on_pawn_damaged)
		if pawn.station_changed.is_connected(_on_pawn_station_changed):
			pawn.station_changed.disconnect(_on_pawn_station_changed)
	if voyage_manager != null and is_instance_valid(voyage_manager):
		if voyage_manager.voyage_started.is_connected(_on_voyage_started):
			voyage_manager.voyage_started.disconnect(_on_voyage_started)
		if voyage_manager.voyage_stage_changed.is_connected(_on_voyage_stage_changed):
			voyage_manager.voyage_stage_changed.disconnect(_on_voyage_stage_changed)
	if ship != null and is_instance_valid(ship):
		if ship.cannon_ordnance_changed.is_connected(_on_tool_state_changed):
			ship.cannon_ordnance_changed.disconnect(_on_tool_state_changed)


## Explicitly register a `CrewBrain` to receive captain orders (also auto-discovered in tree).
func register_crew_brain(brain: CrewBrain) -> void:
	if brain != null and not _crew_brains.has(brain):
		_crew_brains.append(brain)


## Return all registered and live scene-tree `CrewBrain` instances.
func get_crew_brains() -> Array[CrewBrain]:
	var out: Array[CrewBrain] = []
	for b in _crew_brains:
		if b != null and is_instance_valid(b):
			out.append(b)
	if is_inside_tree() and get_tree().root != null:
		_collect_crew_brains(get_tree().root, out)
	return out


static func _collect_crew_brains(node: Node, out: Array[CrewBrain]) -> void:
	if node is CrewBrain:
		var cb := node as CrewBrain
		if not out.has(cb):
			out.append(cb)
	for child in node.get_children():
		_collect_crew_brains(child, out)


# ==============================================================================
# Public HUD controls (radials, orders, banners, pause, quality, audio)
# ==============================================================================

func open_item_radial() -> void:
	if pause_open or item_radial == null:
		return
	dismiss_voyage_title()
	if command_wheel != null and command_wheel.is_open:
		command_wheel.close_wheel(false)
	_refresh_item_radial_entries()
	var cur := inventory.active_item if inventory != null else &"cutlass"
	item_radial.open_wheel(cur)
	_whisper_timer = maxf(_whisper_timer, 3.0)
	_sync_look_pause()


func close_item_radial(confirm: bool = true) -> StringName:
	if item_radial == null or not item_radial.is_open:
		return &""
	var chosen := item_radial.close_wheel(confirm)
	_sync_look_pause()
	return chosen


func open_command_wheel() -> void:
	if pause_open or command_wheel == null:
		return
	dismiss_voyage_title()
	if item_radial != null and item_radial.is_open:
		item_radial.close_wheel(false)
	_update_hold_fire_hint()
	command_wheel.open_wheel()
	_sync_look_pause()


func close_command_wheel(confirm: bool = true) -> StringName:
	if command_wheel == null or not command_wheel.is_open:
		return &""
	var chosen := command_wheel.close_wheel(confirm)
	_sync_look_pause()
	return chosen


## Dispatch a captain command wheel order to all crewmates. Returns crew count reached.
func issue_crew_order(order: StringName) -> int:
	if order == &"":
		return 0
	var brains := get_crew_brains()
	var count := 0
	for b in brains:
		b.give_order(order)
		count += 1
	if order == &"hold_fire":
		crew_hold_fire = not crew_hold_fire
		_update_hold_fire_hint()
	crew_order_issued.emit(order)
	return count


func set_pause_open(open: bool) -> void:
	if pause_open == open:
		return
	if open:
		dismiss_voyage_title()
		if item_radial != null and item_radial.is_open:
			item_radial.close_wheel(false)
		if command_wheel != null and command_wheel.is_open:
			command_wheel.close_wheel(false)
		Audio.play_sfx(&"ui_open", Vector3.INF, -2.5)
	else:
		Audio.play_sfx(&"ui_back", Vector3.INF, -3.0)
	pause_open = open
	if pause_overlay != null:
		pause_overlay.visible = open
	if open:
		_sync_quality_button_states()
	_sync_look_pause()
	pause_changed.emit(pause_open)


func toggle_pause() -> void:
	set_pause_open(not pause_open)


## Apply Ocean.Quality preset (0=LOW, 1=MEDIUM, 2=HIGH).
func set_ocean_quality(level: int) -> void:
	var lv := clampi(level, 0, 2)
	if Ocean.current != null:
		Ocean.current.quality = lv as Ocean.Quality
	_sync_quality_button_states()
	quality_changed.emit(&"ocean", lv)


## Apply SkyRig.CloudQuality preset (0=LOW, 1=MEDIUM, 2=HIGH).
func set_cloud_quality(level: int) -> void:
	var lv := clampi(level, 0, 2)
	var rig := _find_sky_rig()
	if rig != null:
		rig.set(&"cloud_quality", lv)
	_sync_quality_button_states()
	quality_changed.emit(&"clouds", lv)


## Set linear volume (0..1) on an Audio bus and update matching UI slider.
func set_bus_volume(bus: StringName, linear: float) -> void:
	var v := clampf(linear, 0.0, 1.0)
	Audio.set_bus_volume(bus, v)
	if _bus_sliders.has(bus):
		var sl := _bus_sliders[bus] as HSlider
		if sl != null and absf(sl.value - v) > 0.005:
			sl.set_value_no_signal(v)


## Queue a crew callout or game notice on the top-center parchment scroll banner.
func post_banner(text: String) -> void:
	var clean := _to_ascii(text.strip_edges())
	if clean == "":
		return
	if clean == _banner_current and _banner_timer > 1.2:
		return
	if not _banner_queue.is_empty() and _banner_queue[_banner_queue.size() - 1] == clean:
		return
	_banner_queue.append(clean)
	if _banner_current == "":
		_pop_next_banner()


func get_active_banner_text() -> String:
	return _banner_current


func get_queued_banner_count() -> int:
	return _banner_queue.size()


func clear_banners() -> void:
	_banner_queue.clear()
	_banner_current = ""
	_banner_timer = 0.0
	_banner_alpha = 0.0
	if _banner_panel != null:
		_banner_panel.modulate.a = 0.0
		_banner_panel.visible = false


## Set an explicit voyage whisper objective (useful for showcases or scripted moments).
func set_voyage_whisper(title: String, objective: String, hold_seconds: float = 6.0) -> void:
	_custom_voyage_title = title
	_custom_voyage_obj = objective
	_whisper_timer = maxf(_whisper_timer, hold_seconds)
	_refresh_whisper_labels()


## Display a non-blocking diegetic parchment Voyage Title Card in the upper-middle sky.
func show_voyage_title(title: String, subtitle: String, duration: float = 4.2) -> void:
	var clean_title := _to_ascii(title.strip_edges())
	var clean_sub := _to_ascii(subtitle.strip_edges())
	if Game != null and Game.profile != null and Game.profile.has_method(&"get_ship_name"):
		var ship_nm := _to_ascii(String(Game.profile.call(&"get_ship_name")).strip_edges())
		if ship_nm != "" and not clean_sub.to_lower().contains(ship_nm.to_lower()) \
				and not clean_title.to_lower().contains(ship_nm.to_lower()):
			clean_sub = ("Aboard %s" % ship_nm) if clean_sub == "" else ("%s - Aboard %s" % [clean_sub, ship_nm])
	if clean_title == "" and clean_sub == "":
		dismiss_voyage_title()
		return
	if is_any_overlay_open():
		dismiss_voyage_title()
		return
	if _voyage_card_title_label != null:
		_voyage_card_title_label.text = clean_title
		_voyage_card_title_label.visible = clean_title != ""
	if _voyage_card_subtitle_label != null:
		_voyage_card_subtitle_label.text = clean_sub
		_voyage_card_subtitle_label.visible = clean_sub != ""
	if _voyage_card_rule != null:
		_voyage_card_rule.visible = clean_title != "" and clean_sub != ""
	_voyage_card_active = true
	_voyage_card_elapsed = 0.0
	_voyage_card_hold = maxf(duration, 0.0)
	_voyage_card_alpha = 0.0
	if _voyage_card_panel != null:
		_voyage_card_panel.modulate.a = 0.0
		_voyage_card_panel.visible = true


## Return the currently rendered Voyage Title Card subtitle text.
func get_voyage_title_subtitle_text() -> String:
	return _voyage_card_subtitle_label.text if _voyage_card_subtitle_label != null else ""


## Return the live helm/sail telemetry pill text (e.g. "11.8 kt  |  FULL WIND").
func get_sailing_telemetry_text() -> String:
	return _sailing_pill_label.text if _sailing_pill_label != null else ""


## True while the diegetic helm/sail-station telemetry pill is visible.
func is_sailing_telemetry_visible() -> bool:
	return _sailing_pill_panel != null and _sailing_pill_panel.visible


## True while the diegetic Voyage Title Card is active and visible on screen.
func is_voyage_title_visible() -> bool:
	return _voyage_card_active and _voyage_card_panel != null and _voyage_card_panel.visible


## Immediately dismiss and hide the diegetic Voyage Title Card.
func dismiss_voyage_title() -> void:
	_voyage_card_active = false
	_voyage_card_elapsed = 0.0
	_voyage_card_alpha = 0.0
	if _voyage_card_panel != null:
		_voyage_card_panel.modulate.a = 0.0
		_voyage_card_panel.visible = false


## Flash tactile diagonal ink hit-confirm ticks around the center crosshair.
func flash_hit_confirm(was_heavy: bool = false) -> void:
	if _crosshair_view != null:
		_crosshair_view.trigger_hit_confirm(was_heavy)


## Flash twin curved burnished-gold brass guard-arcs around the crosshair on parry.
func flash_parry() -> void:
	if _crosshair_view != null:
		_crosshair_view.trigger_parry_flash()


## Remaining seconds on the active crosshair hit-confirm flash (0 when idle).
func get_hit_confirm_remaining() -> float:
	return _crosshair_view.hit_timer if _crosshair_view != null else 0.0


## Remaining seconds on the active crosshair parry guard-arc flash (0 when idle).
func get_parry_flash_remaining() -> float:
	return _crosshair_view.parry_timer if _crosshair_view != null else 0.0


## Current peripheral damage ink-wash vignette alpha (0 when calm/full HP).
func get_damage_vignette_alpha() -> float:
	return _damage_vignette.get_alpha() if _damage_vignette != null else 0.0


## True while the peripheral damage vignette is actively visible on screen.
func is_damage_vignette_visible() -> bool:
	return _damage_vignette != null and _damage_vignette.visible


## Current bottom-right active tool / supplies chip title text.
func get_tool_title_text() -> String:
	return _tool_title_label.text if _tool_title_label != null else ""


## Current bottom-right active tool / supplies chip subtitle text.
func get_tool_meta_text() -> String:
	return _tool_meta_label.text if _tool_meta_label != null else ""


## Current bottom-center context prompt text.
func get_context_prompt_text() -> String:
	return _prompt_label.text if _prompt_label != null else ""


## True while the active ship has open hull breaches or critical flooding.
func is_hull_alert_active() -> bool:
	return _hull_alert_active


## Return true if any radial wheel or pause menu currently holds focus.
func is_any_overlay_open() -> bool:
	return pause_open \
		or (item_radial != null and item_radial.is_open) \
		or (command_wheel != null and command_wheel.is_open)


# ==============================================================================
# UI construction
# ==============================================================================

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "HUDRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _theme
	add_child(_root)

	# 0. Peripheral damage ink-wash & low-HP heartbeat vignette (behind all HUD panels).
	_damage_vignette = _DamageVignette.new()
	_damage_vignette.name = "DamageVignette"
	_root.add_child(_damage_vignette)

	# 1. Spyglass circular brass aperture vignette (behind center HUD elements).
	_spyglass_view = _SpyglassOverlay.new()
	_spyglass_view.name = "SpyglassOverlay"
	_root.add_child(_spyglass_view)

	# 2. Subtle center crosshair dot with hit-confirm ticks & parry guard arcs.
	_crosshair_view = _CrosshairView.new()
	_crosshair_view.name = "Crosshair"
	_root.add_child(_crosshair_view)

	# 3. Top-center Crew Callout & Notice parchment scroll banner, Boss Bar, and Voyage Title Card.
	_build_banner()
	_build_boss_bar()
	_build_voyage_title_card()

	# 4. Top-right Gold & Voyage Objective whisper card.
	_build_whisper_card()

	# 5. Bottom-left faint Health & Stamina parchment pips.
	_vitals_view = _VitalsView.new()
	_vitals_view.name = "VitalsPips"
	_root.add_child(_vitals_view)

	# 6. Bottom-center contextual interaction prompt ribbon & helm-only sailing telemetry pill.
	_build_context_prompt()
	_build_sailing_telemetry_pill()

	# 7. Bottom-right active tool / ammo / supplies chip.
	_build_tool_chip()

	# 8. Radial wheels (11-wedge Item Radial + 9-wedge Crew Command Wheel).
	item_radial = RadialWheel.new()
	item_radial.name = "ItemRadial"
	_root.add_child(item_radial)
	item_radial.item_selected.connect(_on_item_radial_selected)
	item_radial.wheel_closed.connect(func(_ok: bool) -> void: _sync_look_pause())
	_refresh_item_radial_entries()

	command_wheel = RadialWheel.new()
	command_wheel.name = "CrewCommandWheel"
	_root.add_child(command_wheel)
	command_wheel.configure("Crew Orders", CREW_COMMAND_SLICES, "[RMB] Hold Fire: OFF")
	command_wheel.item_selected.connect(_on_command_wheel_selected)
	command_wheel.secondary_triggered.connect(func() -> void: issue_crew_order(&"hold_fire"))
	command_wheel.wheel_closed.connect(func(_ok: bool) -> void: _sync_look_pause())

	# 9. Pause / Settings / Quality / Co-op Overlay.
	_build_pause_overlay()


func _build_banner() -> void:
	var holder := CenterContainer.new()
	holder.name = "BannerHolder"
	holder.anchor_left = 0.0
	holder.anchor_right = 1.0
	holder.anchor_top = 0.0
	holder.anchor_bottom = 0.0
	# Keep top-center notices clear of the top-right Voyage Whisper / Gold card (326 px wide).
	holder.offset_left = 340.0
	holder.offset_right = -340.0
	holder.offset_top = 24.0
	holder.offset_bottom = 104.0
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(holder)

	_banner_panel = PanelContainer.new()
	_banner_panel.name = "NoticeBanner"
	_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_panel.add_theme_stylebox_override("panel",
		HudIcons.make_parchment_box(Color(0.93, 0.86, 0.71, 0.96), HudIcons.COL_INK, 2, 8, 22, 9))
	_banner_panel.modulate.a = 0.0
	holder.add_child(_banner_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_panel.add_child(hbox)

	var left_orn := Label.new()
	left_orn.text = "*"
	left_orn.add_theme_color_override("font_color", HudIcons.COL_CRIMSON)
	left_orn.add_theme_font_size_override("font_size", 18)
	hbox.add_child(left_orn)

	_banner_label = Label.new()
	_banner_label.name = "BannerText"
	_banner_label.text = ""
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.add_theme_font_size_override("font_size", 18)
	_banner_label.add_theme_color_override("font_color", HudIcons.COL_INK)
	hbox.add_child(_banner_label)

	var right_orn := Label.new()
	right_orn.text = "*"
	right_orn.add_theme_color_override("font_color", HudIcons.COL_CRIMSON)
	right_orn.add_theme_font_size_override("font_size", 18)
	hbox.add_child(right_orn)


func _build_boss_bar() -> void:
	var holder := CenterContainer.new()
	holder.name = "BossBarHolder"
	holder.anchor_left = 0.0
	holder.anchor_right = 1.0
	holder.anchor_top = 0.0
	holder.anchor_bottom = 0.0
	holder.offset_top = 104.0
	holder.offset_bottom = 160.0
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(holder)

	_boss_panel = PanelContainer.new()
	_boss_panel.name = "BossEncounterPanel"
	_boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_panel.add_theme_stylebox_override("panel",
		HudIcons.make_parchment_box(Color(0.92, 0.85, 0.70, 0.94), HudIcons.COL_CRIMSON, 2, 6, 18, 6))
	_boss_panel.modulate.a = 0.0
	_boss_panel.visible = false
	holder.add_child(_boss_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_panel.add_child(vbox)

	_boss_label = Label.new()
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_label.add_theme_font_size_override("font_size", 15)
	_boss_label.add_theme_color_override("font_color", HudIcons.COL_CRIMSON)
	vbox.add_child(_boss_label)

	_boss_bar = ProgressBar.new()
	_boss_bar.custom_minimum_size = Vector2(300.0, 12.0)
	_boss_bar.min_value = 0.0
	_boss_bar.max_value = 1.0
	_boss_bar.value = 1.0
	_boss_bar.show_percentage = false
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Color(0.20, 0.14, 0.10, 0.85)
	bg_sb.set_corner_radius_all(3)
	var fg_sb := StyleBoxFlat.new()
	fg_sb.bg_color = Color(0.72, 0.16, 0.16, 0.96)
	fg_sb.set_corner_radius_all(3)
	_boss_bar.add_theme_stylebox_override("background", bg_sb)
	_boss_bar.add_theme_stylebox_override("fill", fg_sb)
	vbox.add_child(_boss_bar)


## Show or hide the diegetic boss encounter bar (Leviathan, Rival Captain, etc.).
func set_boss_encounter(title: String, hp_ratio: float, active: bool = true) -> void:
	_boss_active = active and title != ""
	if _boss_label != null and title != "":
		_boss_label.text = _to_ascii(title)
	if _boss_bar != null:
		_boss_bar.value = clampf(hp_ratio, 0.0, 1.0)


func _build_voyage_title_card() -> void:
	var holder := CenterContainer.new()
	holder.name = "VoyageTitleHolder"
	holder.anchor_left = 0.0
	holder.anchor_right = 1.0
	holder.anchor_top = 0.20
	holder.anchor_bottom = 0.20
	holder.offset_top = 0.0
	holder.offset_bottom = 132.0
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(holder)

	_voyage_card_panel = PanelContainer.new()
	_voyage_card_panel.name = "VoyageTitleCard"
	_voyage_card_panel.custom_minimum_size = Vector2(360.0, 0.0)
	_voyage_card_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outer_sb := HudIcons.make_parchment_box(
		Color(0.93, 0.86, 0.71, 0.88),
		Color(0.74, 0.16, 0.14, 0.94),
		2,
		8,
		5,
		5
	)
	outer_sb.shadow_size = 7
	outer_sb.shadow_offset = Vector2(0.0, 3.0)
	_voyage_card_panel.add_theme_stylebox_override("panel", outer_sb)
	_voyage_card_panel.modulate.a = 0.0
	_voyage_card_panel.visible = false
	holder.add_child(_voyage_card_panel)

	var inner_frame := PanelContainer.new()
	inner_frame.name = "VoyageTitleInnerFrame"
	inner_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner_sb := StyleBoxFlat.new()
	inner_sb.bg_color = Color(0.96, 0.90, 0.78, 0.14)
	inner_sb.border_color = Color(0.84, 0.64, 0.22, 0.92)
	inner_sb.set_border_width_all(1)
	inner_sb.set_corner_radius_all(5)
	inner_sb.content_margin_left = 34
	inner_sb.content_margin_right = 34
	inner_sb.content_margin_top = 13
	inner_sb.content_margin_bottom = 13
	inner_frame.add_theme_stylebox_override("panel", inner_sb)
	_voyage_card_panel.add_child(inner_frame)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner_frame.add_child(vbox)

	_voyage_card_title_label = Label.new()
	_voyage_card_title_label.name = "VoyageTitleText"
	_voyage_card_title_label.text = ""
	_voyage_card_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_voyage_card_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_voyage_card_title_label.add_theme_font_size_override("font_size", 28)
	_voyage_card_title_label.add_theme_color_override("font_color", HudIcons.COL_INK)
	_voyage_card_title_label.add_theme_color_override("font_shadow_color", Color(0.20, 0.13, 0.08, 0.30))
	_voyage_card_title_label.add_theme_constant_override("shadow_offset_x", 1)
	_voyage_card_title_label.add_theme_constant_override("shadow_offset_y", 1)
	vbox.add_child(_voyage_card_title_label)

	_voyage_card_rule = ColorRect.new()
	_voyage_card_rule.name = "VoyageTitleRule"
	_voyage_card_rule.custom_minimum_size = Vector2(220.0, 1.0)
	_voyage_card_rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_voyage_card_rule.color = Color(0.76, 0.16, 0.14, 0.56)
	_voyage_card_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_voyage_card_rule)

	_voyage_card_subtitle_label = Label.new()
	_voyage_card_subtitle_label.name = "VoyageSubtitleText"
	_voyage_card_subtitle_label.text = ""
	_voyage_card_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_voyage_card_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_voyage_card_subtitle_label.add_theme_font_size_override("font_size", 16)
	_voyage_card_subtitle_label.add_theme_color_override("font_color", Color(0.42, 0.28, 0.16, 0.94))
	vbox.add_child(_voyage_card_subtitle_label)


func _build_whisper_card() -> void:
	_whisper_panel = PanelContainer.new()
	_whisper_panel.name = "VoyageWhisper"
	_whisper_panel.anchor_left = 1.0
	_whisper_panel.anchor_right = 1.0
	_whisper_panel.anchor_top = 0.0
	_whisper_panel.anchor_bottom = 0.0
	_whisper_panel.offset_left = -326.0
	_whisper_panel.offset_right = -24.0
	_whisper_panel.offset_top = 24.0
	_whisper_panel.offset_bottom = 114.0
	_whisper_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_whisper_panel.add_theme_stylebox_override("panel",
		HudIcons.make_parchment_box(Color(0.92, 0.85, 0.70, 0.90), HudIcons.COL_INK_SOFT, 2, 6, 14, 9))
	_whisper_panel.modulate.a = 0.0
	_root.add_child(_whisper_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_whisper_panel.add_child(vbox)

	_gold_label = Label.new()
	_gold_label.text = "0 Gold"
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gold_label.add_theme_font_size_override("font_size", 17)
	_gold_label.add_theme_color_override("font_color", Color(0.56, 0.36, 0.06))
	vbox.add_child(_gold_label)

	_voyage_title_label = Label.new()
	_voyage_title_label.text = ""
	_voyage_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_voyage_title_label.add_theme_font_size_override("font_size", 14)
	_voyage_title_label.add_theme_color_override("font_color", HudIcons.COL_CRIMSON)
	vbox.add_child(_voyage_title_label)

	_voyage_obj_label = Label.new()
	_voyage_obj_label.text = ""
	_voyage_obj_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_voyage_obj_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_voyage_obj_label.add_theme_font_size_override("font_size", 13)
	_voyage_obj_label.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	vbox.add_child(_voyage_obj_label)


func _build_context_prompt() -> void:
	var holder := CenterContainer.new()
	holder.name = "PromptHolder"
	holder.anchor_left = 0.0
	holder.anchor_right = 1.0
	holder.anchor_top = 1.0
	holder.anchor_bottom = 1.0
	holder.offset_top = -126.0
	holder.offset_bottom = -78.0
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(holder)

	_prompt_panel = PanelContainer.new()
	_prompt_panel.name = "ContextPrompt"
	_prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_panel.add_theme_stylebox_override("panel",
		HudIcons.make_parchment_box(Color(0.93, 0.86, 0.72, 0.94), HudIcons.COL_INK, 2, 6, 18, 7))
	_prompt_panel.modulate.a = 0.0
	holder.add_child(_prompt_panel)

	_prompt_label = Label.new()
	_prompt_label.name = "PromptText"
	_prompt_label.text = ""
	_prompt_label.add_theme_font_size_override("font_size", 16)
	_prompt_label.add_theme_color_override("font_color", HudIcons.COL_INK)
	_prompt_panel.add_child(_prompt_label)


func _build_sailing_telemetry_pill() -> void:
	var holder := CenterContainer.new()
	holder.name = "SailingTrimHolder"
	holder.anchor_left = 0.0
	holder.anchor_right = 1.0
	holder.anchor_top = 1.0
	holder.anchor_bottom = 1.0
	holder.offset_top = -64.0
	holder.offset_bottom = -22.0
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(holder)

	_sailing_pill_panel = PanelContainer.new()
	_sailing_pill_panel.name = "SailingTrimPill"
	_sailing_pill_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sailing_pill_panel.add_theme_stylebox_override("panel",
		HudIcons.make_parchment_box(Color(0.92, 0.85, 0.70, 0.90), HudIcons.COL_INK_SOFT, 2, 6, 16, 6))
	_sailing_pill_panel.visible = false
	holder.add_child(_sailing_pill_panel)

	_sailing_pill_label = Label.new()
	_sailing_pill_label.name = "SailingTrimText"
	_sailing_pill_label.text = ""
	_sailing_pill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sailing_pill_label.add_theme_font_size_override("font_size", 15)
	_sailing_pill_label.add_theme_color_override("font_color", HudIcons.COL_INK)
	_sailing_pill_panel.add_child(_sailing_pill_label)


func _build_tool_chip() -> void:
	_tool_panel = PanelContainer.new()
	_tool_panel.name = "ToolChip"
	_tool_panel.anchor_left = 1.0
	_tool_panel.anchor_right = 1.0
	_tool_panel.anchor_top = 1.0
	_tool_panel.anchor_bottom = 1.0
	_tool_panel.offset_left = -240.0
	_tool_panel.offset_right = -24.0
	_tool_panel.offset_top = -88.0
	_tool_panel.offset_bottom = -24.0
	_tool_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_tool_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_tool_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tool_panel.add_theme_stylebox_override("panel",
		HudIcons.make_parchment_box(Color(0.91, 0.84, 0.69, 0.88), HudIcons.COL_INK_SOFT, 2, 6, 14, 7))
	_root.add_child(_tool_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tool_panel.add_child(vbox)

	_tool_title_label = Label.new()
	_tool_title_label.text = "Cutlass"
	_tool_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tool_title_label.add_theme_font_size_override("font_size", 16)
	_tool_title_label.add_theme_color_override("font_color", HudIcons.COL_INK)
	vbox.add_child(_tool_title_label)

	_tool_meta_label = Label.new()
	_tool_meta_label.text = "[Tab] Tools | [Q] Crew"
	_tool_meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tool_meta_label.add_theme_font_size_override("font_size", 13)
	_tool_meta_label.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	vbox.add_child(_tool_meta_label)


func _build_pause_overlay() -> void:
	pause_overlay = ColorRect.new()
	pause_overlay.name = "PauseOverlay"
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.color = Color(0.06, 0.04, 0.02, 0.52)
	pause_overlay.visible = false
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(pause_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.add_child(center)

	var book := PanelContainer.new()
	book.name = "CaptainLogPanel"
	book.custom_minimum_size = Vector2(580.0, 0.0)
	book.add_theme_stylebox_override("panel",
		HudIcons.make_parchment_box(Color(0.93, 0.86, 0.72, 0.98), HudIcons.COL_INK, 3, 10, 26, 16))
	center.add_child(book)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 8)
	book.add_child(root_v)

	var title := Label.new()
	title.text = "CAPTAIN'S LOG"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", HudIcons.COL_INK)
	root_v.add_child(title)

	# Top action buttons: Resume & Save Profile.
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 10)
	top_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root_v.add_child(top_row)

	var resume_btn := Button.new()
	resume_btn.name = "ResumeButton"
	resume_btn.text = "Resume Voyage"
	resume_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resume_btn.pressed.connect(func() -> void:
		Audio.play_sfx(&"ui_select", Vector3.INF, -2.5)
		set_pause_open(false)
	)
	top_row.add_child(resume_btn)

	var save_btn := Button.new()
	save_btn.name = "SaveProfileButton"
	save_btn.text = "Save Profile"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(func() -> void:
		Audio.play_sfx(&"ui_select", Vector3.INF, -2.5)
		if Game != null:
			Game.save()
			Game.post_notice("Captain's profile saved.")
	)
	top_row.add_child(save_btn)

	root_v.add_child(_make_section_divider("QUALITY PRESETS"))

	# Ocean Quality row
	_ocean_qual_btns.clear()
	root_v.add_child(_make_quality_row("Ocean", _ocean_qual_btns, func(lv: int) -> void:
		Audio.play_sfx(&"ui_select", Vector3.INF, -3.0)
		set_ocean_quality(lv)
	))
	# Cloud Quality row
	_cloud_qual_btns.clear()
	root_v.add_child(_make_quality_row("Clouds", _cloud_qual_btns, func(lv: int) -> void:
		Audio.play_sfx(&"ui_select", Vector3.INF, -3.0)
		set_cloud_quality(lv)
	))

	root_v.add_child(_make_section_divider("AUDIO VOLUMES"))

	var buses: Array[Array] = [
		["Master", Audio.BUS_MASTER],
		["Music", Audio.BUS_MUSIC],
		["Ambience", Audio.BUS_AMBIENCE],
		["SFX", Audio.BUS_SFX],
	]
	for bspec in buses:
		var lbl_txt: String = bspec[0]
		var bus_id: StringName = bspec[1]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var l := Label.new()
		l.text = lbl_txt
		l.custom_minimum_size = Vector2(96.0, 0.0)
		l.add_theme_font_size_override("font_size", 15)
		row.add_child(l)
		var sl := HSlider.new()
		sl.name = "Slider_" + lbl_txt
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.02
		sl.value = 1.0
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.value_changed.connect(func(val: float) -> void:
			Audio.set_bus_volume(bus_id, val)
		)
		row.add_child(sl)
		_bus_sliders[bus_id] = sl
		root_v.add_child(row)

	root_v.add_child(_make_section_divider("LAN CO-OP CREW"))

	var coop_inputs := HBoxContainer.new()
	coop_inputs.add_theme_constant_override("separation", 8)
	root_v.add_child(coop_inputs)

	_coop_addr_edit = LineEdit.new()
	_coop_addr_edit.name = "CoopAddressEdit"
	_coop_addr_edit.text = "127.0.0.1"
	_coop_addr_edit.placeholder_text = "Host IP"
	_coop_addr_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coop_inputs.add_child(_coop_addr_edit)

	_coop_port_edit = LineEdit.new()
	_coop_port_edit.name = "CoopPortEdit"
	_coop_port_edit.text = str(Net.DEFAULT_PORT)
	_coop_port_edit.custom_minimum_size = Vector2(88.0, 0.0)
	coop_inputs.add_child(_coop_port_edit)

	var coop_btns := HBoxContainer.new()
	coop_btns.add_theme_constant_override("separation", 10)
	root_v.add_child(coop_btns)

	var host_btn := Button.new()
	host_btn.name = "HostCoopButton"
	host_btn.text = "Host LAN Co-op"
	host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_btn.pressed.connect(_on_host_coop_pressed)
	coop_btns.add_child(host_btn)

	var join_btn := Button.new()
	join_btn.name = "JoinCoopButton"
	join_btn.text = "Join LAN Co-op"
	join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_btn.pressed.connect(_on_join_coop_pressed)
	coop_btns.add_child(join_btn)

	_coop_status_label = Label.new()
	_coop_status_label.text = "Single-player host active"
	_coop_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coop_status_label.add_theme_font_size_override("font_size", 13)
	_coop_status_label.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	root_v.add_child(_coop_status_label)

	root_v.add_child(_make_section_divider("CAPTAIN'S CONTROLS"))

	var controls_box := VBoxContainer.new()
	controls_box.name = "CaptainControlsStrip"
	controls_box.add_theme_constant_override("separation", 2)
	root_v.add_child(controls_box)

	var ctrl_lines: Array[String] = [
		"[WASD] Move  [Space] Jump  [Shift] Sprint  [F] Use / Leave  [X] Step Off",
		"[Tab] Tools  [Q] Crew Orders  [B] Shipwright  [LMB/RMB] Use & Aim  [Esc] Pause",
	]
	for line_txt in ctrl_lines:
		var ctrl_lbl := Label.new()
		ctrl_lbl.text = line_txt
		ctrl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ctrl_lbl.add_theme_font_size_override("font_size", 13)
		ctrl_lbl.add_theme_color_override("font_color", HudIcons.COL_INK)
		controls_box.add_child(ctrl_lbl)


func _make_section_divider(heading: String) -> Label:
	var l := Label.new()
	l.text = "-- %s --" % heading
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", HudIcons.COL_CRIMSON)
	return l


func _make_quality_row(label_text: String, out_btns: Array[Button], on_pick: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(96.0, 0.0)
	l.add_theme_font_size_override("font_size", 15)
	row.add_child(l)
	var names := ["LOW", "MEDIUM", "HIGH"]
	for i in 3:
		var btn := Button.new()
		btn.name = "%s_%s" % [label_text, names[i]]
		btn.text = names[i]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lv := i
		btn.pressed.connect(func() -> void: on_pick.call(lv))
		row.add_child(btn)
		out_btns.append(btn)
	return row


# ==============================================================================
# Input & frame update
# ==============================================================================

func _input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event.is_action_pressed(&"pause"):
		if item_radial != null and item_radial.is_open:
			close_item_radial(false)
		elif command_wheel != null and command_wheel.is_open:
			close_command_wheel(false)
		else:
			toggle_pause()
		get_viewport().set_input_as_handled()
		return

	if pause_open:
		return

	if event.is_action_pressed(&"item_radial"):
		open_item_radial()
		get_viewport().set_input_as_handled()
	elif event.is_action_released(&"item_radial"):
		if item_radial != null and item_radial.is_open:
			close_item_radial(true)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"command_wheel"):
		open_command_wheel()
		get_viewport().set_input_as_handled()
	elif event.is_action_released(&"command_wheel"):
		if command_wheel != null and command_wheel.is_open:
			close_command_wheel(true)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_tick_banner(delta)
	_tick_boss_bar(delta)
	_tick_voyage_title(delta)
	_tick_vitals(delta)
	_sync_damage_vignette(delta)
	_tick_context_prompt(delta)
	_tick_sailing_telemetry()
	_tick_tool_chip(delta)
	_tick_whisper(delta)
	_tick_crosshair(delta)


func _tick_sailing_telemetry() -> void:
	if _sailing_pill_panel == null or _sailing_pill_label == null:
		return
	var on_sailing_station := false
	if pawn != null and is_instance_valid(pawn) and not pawn.dead \
			and pawn.station != null and is_instance_valid(pawn.station):
		var st_kind: Variant = pawn.station.get(&"kind")
		if st_kind is StringName and SAILING_STATION_KINDS.has(st_kind as StringName):
			on_sailing_station = true
	var show_pill := on_sailing_station \
		and ship != null and is_instance_valid(ship) \
		and not is_any_overlay_open()
	if not show_pill:
		_sailing_pill_panel.visible = false
		return

	var kts := maxf(0.0, ship.speed_knots())
	var state_txt := "TRIM SAILS"
	var ink_col := HudIcons.COL_INK_SOFT
	if ship.anchor_down:
		state_txt = "ANCHORED"
	elif ship.sail_set < 0.08:
		state_txt = "SAILS FURLED"
	else:
		var err := absf(angle_difference(ship.sail_trim, ship.ideal_sail_trim()))
		if err <= 0.24:
			state_txt = "FULL WIND"
			ink_col = Color(0.68, 0.36, 0.04)
		elif err <= 0.65:
			state_txt = "GOOD TRIM"
			ink_col = HudIcons.COL_INK
		else:
			state_txt = "TRIM SAILS"
			ink_col = HudIcons.COL_INK_SOFT

	_sailing_pill_label.text = "%.1f kt  |  %s" % [kts, state_txt]
	_sailing_pill_label.add_theme_color_override("font_color", ink_col)
	_sailing_pill_panel.visible = true


func _tick_boss_bar(delta: float) -> void:
	var want_a := 0.95 if (_boss_active and not pause_open) else 0.0
	_boss_alpha = move_toward(_boss_alpha, want_a, delta * 4.5)
	if _boss_panel != null:
		_boss_panel.modulate.a = _boss_alpha
		_boss_panel.visible = _boss_alpha > 0.01


func _tick_voyage_title(delta: float) -> void:
	if not _voyage_card_active:
		return
	if is_any_overlay_open():
		dismiss_voyage_title()
		return
	_voyage_card_elapsed += maxf(delta, 0.0)
	var fade_out_start := VOYAGE_TITLE_FADE_IN + _voyage_card_hold
	var total := fade_out_start + VOYAGE_TITLE_FADE_OUT
	if _voyage_card_elapsed >= total:
		dismiss_voyage_title()
		return
	if _voyage_card_elapsed < VOYAGE_TITLE_FADE_IN:
		var t_in := clampf(_voyage_card_elapsed / VOYAGE_TITLE_FADE_IN, 0.0, 1.0)
		_voyage_card_alpha = smoothstep(0.0, 1.0, t_in)
	elif _voyage_card_elapsed < fade_out_start:
		_voyage_card_alpha = 1.0
	else:
		var t_out := clampf((_voyage_card_elapsed - fade_out_start) / VOYAGE_TITLE_FADE_OUT, 0.0, 1.0)
		_voyage_card_alpha = 1.0 - smoothstep(0.0, 1.0, t_out)
		if _voyage_card_alpha <= 0.001:
			dismiss_voyage_title()
			return
	if _voyage_card_panel != null:
		_voyage_card_panel.modulate.a = _voyage_card_alpha
		_voyage_card_panel.visible = true


func _tick_banner(delta: float) -> void:
	if _banner_current == "":
		if not _banner_queue.is_empty():
			_pop_next_banner()
		else:
			_banner_alpha = move_toward(_banner_alpha, 0.0, delta * 3.5)
	else:
		_banner_timer -= delta
		if _banner_timer <= 0.0:
			_banner_current = ""
			if not _banner_queue.is_empty():
				_pop_next_banner()
		else:
			var want_a := 1.0 if _banner_timer > 0.45 else clampf(_banner_timer / 0.45, 0.0, 1.0)
			_banner_alpha = move_toward(_banner_alpha, want_a, delta * 6.0)
	if _banner_panel != null:
		_banner_panel.modulate.a = _banner_alpha
		_banner_panel.visible = _banner_alpha > 0.01


func _pop_next_banner() -> void:
	if _banner_queue.is_empty():
		return
	_banner_current = _banner_queue.pop_front()
	# Trim dwell slightly when several callouts are queued so banter feels brisk.
	_banner_timer = 2.4 if _banner_queue.size() >= 2 else 3.6
	if _banner_label != null:
		_banner_label.text = _banner_current
		# Wrap long notices cleanly inside the safe centered band so they never overlap the Voyage Whisper card.
		if _banner_current.length() > 54:
			_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_banner_label.custom_minimum_size = Vector2(560.0, 0.0)
		else:
			_banner_label.autowrap_mode = TextServer.AUTOWRAP_OFF
			_banner_label.custom_minimum_size = Vector2.ZERO


func _tick_vitals(delta: float) -> void:
	var hp_ratio := 1.0
	var stam_ratio := 1.0
	var in_combat := false
	if pawn != null and is_instance_valid(pawn):
		hp_ratio = clampf(pawn.health / maxf(pawn.max_health, 1.0), 0.0, 1.0)
		if _last_hp >= 0.0:
			if pawn.health < _last_hp - 0.5:
				var drop := _last_hp - pawn.health
				_damage_flash = clampf(_damage_flash + clampf(drop / 35.0, 0.35, 0.9), 0.0, 1.0)
				_vitals_show_timer = 4.5
			elif absf(pawn.health - _last_hp) > 0.1:
				_vitals_show_timer = 4.0
		_last_hp = pawn.health
	if combat != null and is_instance_valid(combat):
		stam_ratio = clampf(combat.stamina / maxf(combat.max_stamina, 1.0), 0.0, 1.0)
		if _last_stamina >= 0.0 and absf(combat.stamina - _last_stamina) > 0.5:
			_vitals_show_timer = 3.2
		_last_stamina = combat.stamina
		in_combat = (combat.state != CombatComponent.State.IDLE)

	if hp_ratio < 0.99 or stam_ratio < 0.99 or in_combat or force_show_vitals:
		_vitals_show_timer = maxf(_vitals_show_timer, 3.0)
	else:
		_vitals_show_timer = maxf(0.0, _vitals_show_timer - delta)

	var want_a := 0.92 if (_vitals_show_timer > 0.0 or force_show_vitals) else 0.0
	_vitals_alpha = move_toward(_vitals_alpha, want_a, delta * (5.5 if want_a > _vitals_alpha else 1.6))
	if _vitals_view != null:
		_vitals_view.set_values(hp_ratio, stam_ratio, _vitals_alpha)


func _sync_damage_vignette(delta: float) -> void:
	if _damage_vignette == null:
		return
	if delta > 0.0 and _damage_flash > 0.0:
		_damage_flash = move_toward(_damage_flash, 0.0, delta / 0.48)

	var low_pulse := 0.0
	if pawn != null and is_instance_valid(pawn) and not pawn.dead and not pause_open:
		var hp_ratio := clampf(pawn.health / maxf(pawn.max_health, 1.0), 0.0, 1.0)
		if hp_ratio < 0.30:
			_low_hp_clock = fmod(_low_hp_clock + maxf(delta, 0.0), TAU * 10.0)
			var beat := 0.5 + 0.5 * sin(_low_hp_clock * 4.2)
			var lub_dub := pow(maxf(0.0, sin(_low_hp_clock * 4.2 + 0.85)), 4.0) * 0.35
			var wave := clampf(beat * 0.72 + lub_dub, 0.0, 1.0)
			low_pulse = lerpf(0.12, 0.28, wave)
		else:
			_low_hp_clock = 0.0
	else:
		_low_hp_clock = 0.0

	var flash_alpha := _damage_flash * 0.62 if not pause_open else 0.0
	var total_alpha := clampf(maxf(flash_alpha, low_pulse) + minf(flash_alpha, low_pulse) * 0.35, 0.0, 0.78)
	_damage_vignette.set_state(total_alpha, _damage_flash, _is_colorblind_mode())


func _tick_context_prompt(delta: float) -> void:
	var txt := ""
	if player_controller != null and is_instance_valid(player_controller) and not is_any_overlay_open():
		var raw := player_controller.focus_prompt.strip_edges()
		if raw != "":
			if raw.begins_with("["):
				txt = raw
			else:
				txt = "[F] %s" % raw
	var want_a := 1.0 if txt != "" else 0.0
	_prompt_alpha = move_toward(_prompt_alpha, want_a, delta * 9.0)
	if _prompt_label != null and txt != "":
		_prompt_label.text = _to_ascii(txt)
	if _prompt_panel != null:
		_prompt_panel.modulate.a = _prompt_alpha
		_prompt_panel.visible = _prompt_alpha > 0.01


func _tick_tool_chip(delta: float) -> void:
	_tool_flash_timer = maxf(0.0, _tool_flash_timer - delta)
	_refresh_tool_chip()
	if _tool_panel != null:
		var spy_hide := inventory != null and inventory.spyglass_zoom > 0.4
		var urgent := _tool_flash_timer > 0.0 or _hull_alert_active
		var target_a := 0.0 if (spy_hide or pause_open) else (0.96 if urgent else 0.76)
		_tool_panel.modulate.a = move_toward(_tool_panel.modulate.a, target_a, delta * 5.0)
		_tool_panel.visible = _tool_panel.modulate.a > 0.02


func _refresh_tool_chip() -> void:
	if _tool_title_label == null or _tool_meta_label == null:
		return
	var item_id := inventory.active_item if inventory != null else &"cutlass"
	var resolved_id := item_id
	if inventory != null:
		if item_id == &"cutlass" and inventory.get(&"melee_weapon") != null:
			resolved_id = StringName(inventory.get(&"melee_weapon"))
		elif item_id == &"pistol" and inventory.get(&"ranged_weapon") != null:
			resolved_id = StringName(inventory.get(&"ranged_weapon"))
	var title := ToolMeshes.get_display_name(resolved_id)
	var meta := "[Tab] Tools | [Q] Crew"
	var active_ship := _active_ship()

	if pawn != null and pawn.station != null:
		var sk := StringName(pawn.station.get(&"kind"))
		match sk:
			&"helm":
				title = "Ship's Wheel"
				meta = "[A/D] Steer | [S/RMB] Center | [F] Leave"
			&"anchor":
				title = "Anchor Capstan"
				if active_ship != null:
					var raised_pct := int(roundf((1.0 - active_ship.anchor_progress) * 100.0))
					meta = "[Hold W] Heave (%d%%) | [S] Drop | [F] Leave" % raised_pct
				else:
					meta = "[Hold W] Heave | [S] Drop | [F] Leave"
			&"sail_length":
				title = "Sail Hoist"
				if active_ship != null:
					meta = "[S] Lower / [W] Raise (%d%%) | [F] Leave" % int(roundf(active_ship.sail_set * 100.0))
				else:
					meta = "[S] Lower / [W] Raise | [F] Leave"
			&"sail_angle":
				title = "Sail Braces"
				meta = "[A/D] Angle | [RMB] Square | [F] Leave"
			&"cannon":
				title = "Ship Cannon"
				if active_ship != null:
					var ord_lbl := active_ship.get_cannon_ordnance_label()
					meta = "Shot: %s (%d) | [WASD/Mouse] Aim | [LMB] Fire | [R] Swap Shot" % [ord_lbl, active_ship.cannonballs_remaining]
				else:
					meta = "[WASD/Mouse] Aim | [LMB] Fire (Iron) | [R] Swap Shot"
			&"harpoon":
				title = "Bow Harpoon"
				meta = "[Mouse/WASD] Aim | [LMB] Fire | [Hold RMB] Reel | [R] Release | [F] Leave"
			&"map_table":
				title = "Map Table"
				meta = "[WASD] Pan | [Space] Pin | [F] Leave"
			&"bilge":
				title = "Ship's Bilge"
				meta = "[Hold LMB] Bail Water | [F] Leave"
	elif inventory != null:
		match item_id:
			&"cutlass":
				if resolved_id == &"boarding_axe":
					meta = "Heavy Cleave | [RMB] Guard"
				else:
					meta = "[LMB] Slash / Hold Lunge | [RMB] Block"
			&"pistol":
				if combat != null:
					var cap := 4 if resolved_id == &"blunderbuss" else 6
					meta = "Shot: %d / %d | [LMB] Fire | [RMB] Aim" % [combat.ammo, cap]
				else:
					meta = "[LMB] Fire | [RMB] Aim"
			&"bucket":
				meta = "[LMB] Throw / Bail | [RMB] Splash" if inventory.bucket_full else "[LMB] Scoop Bilge / Sea"
			&"planks":
				if active_ship != null:
					meta = "Planks: %d | [LMB] Patch Breach" % active_ship.planks_remaining
				else:
					meta = "[LMB] Patch Breach"
			&"shovel":
				meta = "[LMB] Dig Treasure"
			&"compass":
				if inventory.is_compass_pacing():
					meta = "Compass | %d paces (%s)" % [inventory.get_compass_paces(), inventory.get_compass_heading_label()]
				else:
					meta = "[Hold RMB] Raise & Count Paces"
			&"spyglass":
				meta = "[RMB] Zoom | [LMB] Call Out Sighting"
			&"lantern":
				meta = "Lit | [LMB] Flash / [RMB] Raise" if inventory.lantern_lit else "Unlit | [LMB] Light"
			&"map":
				meta = "%s | [RMB] Inspect" % inventory.map_island_name
			&"tankard":
				meta = "[LMB] Drink Grog | [RMB] Cheers Toast"
			&"instrument":
				var inst_disp := String(Inventory.SHANTY_INSTRUMENT_NAMES.get(
					inventory.shanty_instrument, String(inventory.shanty_instrument).capitalize()))
				meta = ("Playing %s | [LMB] Stop | [RMB] Swap" % inst_disp) if inventory.playing_shanty \
					else "[LMB] Play | [RMB] Swap Instrument"

	# Surface urgent ship flooding / open hull breach warnings right on the supplies chip.
	var hull_warn := ""
	var hull_critical := false
	if active_ship != null and is_instance_valid(active_ship):
		var open_leaks := active_ship.open_hole_count()
		if active_ship.is_sinking or active_ship.water_level > 0.32:
			hull_critical = true
			hull_warn = "  |  FLOODING! (%d)" % open_leaks if open_leaks > 0 else "  |  FLOODING!"
		elif open_leaks > 0:
			hull_warn = "  |  LEAKS: %d" % open_leaks

	_hull_alert_active = hull_warn != ""
	if _hull_alert_active:
		meta += hull_warn
		var cb := _is_colorblind_mode()
		var alert_col := Color(0.84, 0.44, 0.04, 0.98) if cb else (
			Color(0.78, 0.14, 0.10, 0.98) if hull_critical else Color(0.74, 0.38, 0.05, 0.98)
		)
		_tool_meta_label.add_theme_color_override("font_color", alert_col)
	else:
		_tool_meta_label.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)

	_tool_title_label.text = _to_ascii(title)
	_tool_meta_label.text = _to_ascii(meta)


func _tick_whisper(delta: float) -> void:
	if Game != null and Game.profile != null:
		var g := int(Game.profile.data.get("gold", 0))
		if g != _last_gold:
			_last_gold = g
			_whisper_timer = maxf(_whisper_timer, 5.5)

	var holding_map := inventory != null and inventory.active_item == &"map"
	var radial_open := item_radial != null and item_radial.is_open
	if holding_map or radial_open or force_show_whisper:
		_whisper_timer = maxf(_whisper_timer, 1.5)
	else:
		_whisper_timer = maxf(0.0, _whisper_timer - delta)

	_refresh_whisper_labels()
	var want_a := 0.92 if (_whisper_timer > 0.0 and not pause_open) else 0.0
	_whisper_alpha = move_toward(_whisper_alpha, want_a, delta * (5.0 if want_a > _whisper_alpha else 1.8))
	if _whisper_panel != null:
		_whisper_panel.modulate.a = _whisper_alpha
		_whisper_panel.visible = _whisper_alpha > 0.01


func _refresh_whisper_labels() -> void:
	if _gold_label == null:
		return
	var gold := int(Game.profile.data.get("gold", 0)) if (Game != null and Game.profile != null) else 0
	_gold_label.text = "%d Gold" % gold
	var v_title := _custom_voyage_title
	var v_obj := _custom_voyage_obj
	if voyage_manager != null and is_instance_valid(voyage_manager) and voyage_manager.has_active_voyage():
		v_title = String(voyage_manager.active_voyage.get("title", "Active Voyage"))
		v_obj = voyage_manager.get_current_objective()
	_voyage_title_label.text = _to_ascii(v_title)
	_voyage_title_label.visible = v_title != ""
	_voyage_obj_label.text = _to_ascii(v_obj)
	_voyage_obj_label.visible = v_obj != ""


func _tick_crosshair(delta: float) -> void:
	if _crosshair_view == null:
		return
	var spy := inventory.spyglass_zoom if inventory != null else 0.0
	var hide_dot := is_any_overlay_open() or spy > 0.25
	var want := 0.0 if hide_dot else 0.78
	var prev_a := _crosshair_view.alpha
	_crosshair_view.alpha = move_toward(_crosshair_view.alpha, want, delta * 10.0)
	var fx_dirty := _crosshair_view.tick_effects(delta)
	if fx_dirty or absf(_crosshair_view.alpha - prev_a) > 0.002:
		_crosshair_view.queue_redraw()


# ==============================================================================
# Callbacks & helpers
# ==============================================================================

func _refresh_item_radial_entries() -> void:
	if item_radial == null:
		return
	var slot_list: Array[StringName] = inventory.slots if inventory != null else Inventory.DEFAULT_SLOTS
	var slices: Array[Dictionary] = []
	for id in slot_list:
		var resolved_id := id
		if inventory != null:
			if id == &"cutlass" and inventory.get(&"melee_weapon") != null:
				resolved_id = StringName(inventory.get(&"melee_weapon"))
			elif id == &"pistol" and inventory.get(&"ranged_weapon") != null:
				resolved_id = StringName(inventory.get(&"ranged_weapon"))
		slices.append({
			"id": id,
			"label": ToolMeshes.get_display_name(resolved_id),
			"hint": String(ITEM_SLICE_HINTS.get(resolved_id, ITEM_SLICE_HINTS.get(id, ""))),
			"icon": resolved_id,
		})
	item_radial.configure("Tools & Gear", slices)


func _update_hold_fire_hint() -> void:
	if command_wheel != null:
		command_wheel.secondary_hint = "[RMB] Hold Fire: %s" % ("ON" if crew_hold_fire else "OFF")
		command_wheel.queue_redraw()


func _on_item_radial_selected(id: StringName) -> void:
	if inventory != null:
		inventory.equip(id)
	_tool_flash_timer = 2.8


func _on_command_wheel_selected(order_id: StringName) -> void:
	issue_crew_order(order_id)


func _on_item_equipped(_item_id: StringName) -> void:
	_tool_flash_timer = 2.8
	_refresh_tool_chip()


func _on_tool_state_changed(_v: Variant) -> void:
	_tool_flash_timer = 2.2
	_refresh_tool_chip()


func _on_compass_pace_counted(_paces: int, _heading: String) -> void:
	_tool_flash_timer = 2.0
	_refresh_tool_chip()


func _on_grog_toast_raised() -> void:
	_tool_flash_timer = 2.2
	_refresh_tool_chip()


func _on_spyglass_zoom(amount: float) -> void:
	if _spyglass_view != null:
		_spyglass_view.set_zoom(amount)


func _on_sighting_updated(label: String, distance_m: float) -> void:
	if _spyglass_view != null:
		var bearing := inventory.spyglass_sighting_bearing if (inventory != null and is_instance_valid(inventory)) else ""
		_spyglass_view.set_sighting(label, distance_m, bearing)


func _on_pawn_damaged(amount: float, _from: Node) -> void:
	_vitals_show_timer = 4.5
	if amount > 0.5:
		_damage_flash = clampf(_damage_flash + clampf(amount / 35.0, 0.35, 0.9), 0.0, 1.0)
		if pawn != null and is_instance_valid(pawn):
			_last_hp = pawn.health
		_sync_damage_vignette(0.0)


func _on_pawn_station_changed(_st: Node3D) -> void:
	_tool_flash_timer = 2.6
	_refresh_tool_chip()
	_tick_sailing_telemetry()


func _on_combat_hit_landed(_target: Pawn, _damage: float, was_heavy: bool) -> void:
	flash_hit_confirm(was_heavy)


func _on_combat_target_hit(_target: Node, _damage: float, was_heavy: bool) -> void:
	flash_hit_confirm(was_heavy)


func _on_combat_parried(_attacker: Pawn) -> void:
	flash_parry()


func _on_voyage_started(_voyage: Dictionary) -> void:
	_whisper_timer = 6.5


func _on_voyage_stage_changed(_stage: int, _obj: String) -> void:
	_whisper_timer = 6.0


func _on_game_notice(text: String) -> void:
	post_banner(text)


func _on_host_coop_pressed() -> void:
	var port := int(_coop_port_edit.text) if _coop_port_edit != null else Net.DEFAULT_PORT
	if port <= 0:
		port = Net.DEFAULT_PORT
	var err := Net.host(port)
	if err == OK:
		Audio.play_sfx(&"ui_select", Vector3.INF, -2.5)
		if _coop_status_label != null:
			_coop_status_label.text = "Hosting LAN co-op on port %d" % port
		if Game != null:
			Game.post_notice("Hosting LAN co-op on port %d!" % port)
	else:
		Audio.play_sfx(&"ui_back", Vector3.INF, -2.5)
		if _coop_status_label != null:
			_coop_status_label.text = "Host failed: %s" % error_string(err)


func _on_join_coop_pressed() -> void:
	var addr := _coop_addr_edit.text.strip_edges() if _coop_addr_edit != null else "127.0.0.1"
	if addr == "":
		addr = "127.0.0.1"
	var port := int(_coop_port_edit.text) if _coop_port_edit != null else Net.DEFAULT_PORT
	if port <= 0:
		port = Net.DEFAULT_PORT
	var err := Net.join(addr, port)
	if err == OK:
		Audio.play_sfx(&"ui_select", Vector3.INF, -2.5)
		if _coop_status_label != null:
			_coop_status_label.text = "Joining %s:%d..." % [addr, port]
		if Game != null:
			Game.post_notice("Joining co-op crew at %s:%d..." % [addr, port])
	else:
		Audio.play_sfx(&"ui_back", Vector3.INF, -2.5)
		if _coop_status_label != null:
			_coop_status_label.text = "Join failed: %s" % error_string(err)


func _sync_look_pause() -> void:
	if player_controller != null and is_instance_valid(player_controller):
		player_controller.set_look_paused(is_any_overlay_open())


func _active_ship() -> Ship:
	if pawn != null and is_instance_valid(pawn) and is_instance_valid(pawn.platform) and pawn.platform is Ship:
		return pawn.platform as Ship
	if ship != null and is_instance_valid(ship):
		return ship
	return null


func _is_colorblind_mode() -> bool:
	var cfg := user_settings
	if cfg == null and get_parent() != null:
		var found: Variant = get_parent().get(&"user_settings")
		if found is UserSettings:
			cfg = found as UserSettings
			user_settings = cfg
	if cfg == null:
		return false
	var cb_mode := String(cfg.data.get("colorblind_mode", "")).strip_edges().to_lower()
	if cb_mode != "" and cb_mode != "none" and cb_mode != "off":
		return true
	return bool(cfg.data.get("high_contrast_prompts", false))


func _find_sky_rig() -> Node:
	if sky_rig != null and is_instance_valid(sky_rig):
		return sky_rig
	if is_inside_tree() and get_tree().root != null:
		sky_rig = _search_sky_rig(get_tree().root)
	return sky_rig


static func _search_sky_rig(node: Node) -> Node:
	if node.get(&"cloud_quality") != null and node.get(&"sky_material") != null:
		return node
	for child in node.get_children():
		var found := _search_sky_rig(child)
		if found != null:
			return found
	return null


func _sync_quality_button_states() -> void:
	var oq := int(Ocean.current.quality) if Ocean.current != null else 2
	for i in _ocean_qual_btns.size():
		_style_toggle_btn(_ocean_qual_btns[i], i == oq)
	var rig := _find_sky_rig()
	var cq := int(rig.get(&"cloud_quality")) if rig != null else 1
	for i in _cloud_qual_btns.size():
		_style_toggle_btn(_cloud_qual_btns[i], i == cq)


static func _style_toggle_btn(btn: Button, selected: bool) -> void:
	if btn == null:
		return
	if selected:
		btn.add_theme_stylebox_override("normal",
			HudIcons.make_parchment_box(HudIcons.COL_GOLD, HudIcons.COL_CRIMSON, 2, 5, 10, 6))
	else:
		btn.remove_theme_stylebox_override("normal")


static func _to_ascii(text: String) -> String:
	var out := text.replace(char(0x2014), "--").replace(char(0x2013), "-")
	out = out.replace(char(0x00B7), "|").replace(char(0x2022), "*")
	out = out.replace(char(0x2018), "'").replace(char(0x2019), "'")
	out = out.replace(char(0x201C), "\"").replace(char(0x201D), "\"")
	out = out.replace(char(0x2026), "...")
	return out


# ==============================================================================
# Custom drawn minimal HUD controls
# ==============================================================================

class _DamageVignette extends Control:
	const RING_SEGMENTS := 36

	var _alpha: float = 0.0
	var _flash_intensity: float = 0.0
	var _colorblind: bool = false

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		visible = false

	func get_alpha() -> float:
		return _alpha

	func is_colorblind_tinted() -> bool:
		return _colorblind

	func set_state(alpha: float, flash_intensity: float, colorblind: bool) -> void:
		var clamped := clampf(alpha, 0.0, 0.85)
		var changed := absf(clamped - _alpha) > 0.003 \
			or absf(flash_intensity - _flash_intensity) > 0.005 \
			or colorblind != _colorblind
		_alpha = clamped
		_flash_intensity = clampf(flash_intensity, 0.0, 1.0)
		_colorblind = colorblind
		visible = _alpha > 0.005
		if changed and visible:
			queue_redraw()

	func _draw() -> void:
		if _alpha <= 0.005:
			return
		var view_sz := size if (size.is_finite() and size.length_squared() >= 1.0) else get_viewport_rect().size
		if not view_sz.is_finite() or view_sz.x < 4.0 or view_sz.y < 4.0:
			return
		var c := view_sz * 0.5
		var cx := c.x
		var cy := c.y
		var intensity := clampf(_alpha / 0.65, 0.0, 1.0)

		# Painterly ink-wash peripheral tint: warm vermilion-ink by default, amber-ochre for colorblind mode.
		var base_rgb := Color(0.84, 0.42, 0.06) if _colorblind else Color(0.54, 0.08, 0.06)
		var rim_rgb := Color(0.64, 0.28, 0.04) if _colorblind else Color(0.32, 0.05, 0.05)
		var edge_rgb := rim_rgb.lerp(base_rgb, 0.55 + 0.35 * _flash_intensity)
		var col_outer := Color(edge_rgb.r, edge_rgb.g, edge_rgb.b, _alpha)
		var col_mid := Color(base_rgb.r, base_rgb.g, base_rgb.b, _alpha * 0.42)
		var col_inner := Color(base_rgb.r, base_rgb.g, base_rgb.b, 0.0)

		var in_rx := cx * lerpf(0.84, 0.68, intensity)
		var in_ry := cy * lerpf(0.82, 0.66, intensity)
		var mid_rx := cx * 1.04
		var mid_ry := cy * 1.04
		var out_rx := cx * 1.46
		var out_ry := cy * 1.46

		var outer_pts := PackedVector2Array()
		var mid_pts := PackedVector2Array()
		var inner_pts := PackedVector2Array()
		outer_pts.resize(RING_SEGMENTS + 1)
		mid_pts.resize(RING_SEGMENTS + 1)
		inner_pts.resize(RING_SEGMENTS + 1)

		for i in RING_SEGMENTS + 1:
			var ang := float(i) / float(RING_SEGMENTS) * TAU
			var dx := cos(ang)
			var dy := sin(ang)
			outer_pts[i] = c + Vector2(dx * out_rx, dy * out_ry)
			mid_pts[i] = c + Vector2(dx * mid_rx, dy * mid_ry)
			inner_pts[i] = c + Vector2(dx * in_rx, dy * in_ry)

		var cols_outer := PackedColorArray([col_outer, col_outer, col_mid, col_mid])
		var cols_inner := PackedColorArray([col_mid, col_mid, col_inner, col_inner])
		for i in RING_SEGMENTS:
			var q_out := PackedVector2Array([outer_pts[i], outer_pts[i + 1], mid_pts[i + 1], mid_pts[i]])
			draw_polygon(q_out, cols_outer)
			var q_in := PackedVector2Array([mid_pts[i], mid_pts[i + 1], inner_pts[i + 1], inner_pts[i]])
			draw_polygon(q_in, cols_inner)


class _CrosshairView extends Control:
	const HIT_DURATION := 0.24
	const PARRY_DURATION := 0.34

	var alpha: float = 0.78
	var hit_timer: float = 0.0
	var hit_heavy: bool = false
	var parry_timer: float = 0.0

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func trigger_hit_confirm(was_heavy: bool = false) -> void:
		if hit_timer > HIT_DURATION - 0.02:
			hit_heavy = hit_heavy or was_heavy
		else:
			hit_heavy = was_heavy
		hit_timer = HIT_DURATION
		queue_redraw()

	func trigger_parry_flash() -> void:
		parry_timer = PARRY_DURATION
		queue_redraw()

	func tick_effects(delta: float) -> bool:
		var was_active := hit_timer > 0.0 or parry_timer > 0.0
		if hit_timer > 0.0:
			hit_timer = maxf(0.0, hit_timer - maxf(delta, 0.0))
		if parry_timer > 0.0:
			parry_timer = maxf(0.0, parry_timer - maxf(delta, 0.0))
		return was_active

	func _draw() -> void:
		if alpha <= 0.02:
			return
		var view_sz := size if (size.is_finite() and size.length_squared() >= 1.0) else get_viewport_rect().size
		if not view_sz.is_finite() or view_sz.x < 4.0 or view_sz.y < 4.0:
			return
		var c := view_sz * 0.5
		var vis_scale := clampf(alpha / 0.78, 0.0, 1.0)

		# 1. Subtle parchment center dot with sepia ink halo.
		draw_circle(c, 3.6, Color(0.14, 0.09, 0.05, 0.55 * alpha))
		draw_circle(c, 2.2, Color(0.96, 0.91, 0.78, alpha))

		# 2. Tactile diagonal tapered ink hit-confirm ticks (wider & burnt-crimson-gold for heavy hits).
		if hit_timer > 0.001:
			var t := clampf(hit_timer / HIT_DURATION, 0.0, 1.0)
			var ease_t := t * t
			var fade := smoothstep(0.0, 0.42, t) * vis_scale
			var inner_r := lerpf(6.5, 11.5, ease_t) if hit_heavy else lerpf(5.5, 9.5, ease_t)
			var outer_r := lerpf(14.5, 25.5, ease_t) if hit_heavy else lerpf(11.5, 19.5, ease_t)
			var w_in := 1.1 if hit_heavy else 0.8
			var w_out := 3.1 if hit_heavy else 2.1
			var ink_col := Color(0.16, 0.09, 0.05, 0.80 * fade)
			var fill_col := Color(0.95, 0.44, 0.16, 0.98 * fade) if hit_heavy else Color(0.96, 0.84, 0.44, 0.96 * fade)
			var core_col := Color(0.84, 0.18, 0.12, 0.90 * fade) if hit_heavy else Color(1.0, 0.94, 0.72, 0.82 * fade)
			for i in 4:
				var ang := PI * 0.25 + float(i) * PI * 0.5
				var dir := Vector2(cos(ang), sin(ang))
				var perp := Vector2(-dir.y, dir.x)
				var border_poly := PackedVector2Array([
					c + dir * (inner_r - 1.1) - perp * (w_in + 0.9),
					c + dir * (outer_r + 1.2) - perp * (w_out + 1.0),
					c + dir * (outer_r + 1.2) + perp * (w_out + 1.0),
					c + dir * (inner_r - 1.1) + perp * (w_in + 0.9),
				])
				draw_colored_polygon(border_poly, ink_col)
				var tick_poly := PackedVector2Array([
					c + dir * inner_r - perp * w_in,
					c + dir * outer_r - perp * w_out,
					c + dir * outer_r + perp * w_out,
					c + dir * inner_r + perp * w_in,
				])
				draw_colored_polygon(tick_poly, fill_col)
				draw_line(c + dir * (inner_r + 1.2), c + dir * (outer_r - 1.6), core_col, 1.3 if hit_heavy else 1.0, true)

		# 3. Twin opposing burnished-gold brass guard-arcs on timed parry.
		if parry_timer > 0.001:
			var pt := clampf(parry_timer / PARRY_DURATION, 0.0, 1.0)
			var pfade := smoothstep(0.0, 0.38, pt) * vis_scale
			var arc_r := lerpf(16.0, 23.0, sin(pt * PI * 0.65))
			var half_span := lerpf(0.42, 0.68, pt)
			var shadow_col := Color(0.18, 0.11, 0.05, 0.74 * pfade)
			var brass_col := Color(0.89, 0.69, 0.24, 0.96 * pfade)
			var glint_col := Color(0.99, 0.93, 0.72, 0.90 * pfade)
			for base_ang: float in [0.0, PI]:
				var a0 := base_ang - half_span
				var a1 := base_ang + half_span
				draw_arc(c, arc_r, a0, a1, 20, shadow_col, 5.4, true)
				draw_arc(c, arc_r, a0, a1, 20, brass_col, 3.2, true)
				draw_arc(c, arc_r - 0.8, a0 + 0.06, a1 - 0.06, 16, glint_col, 1.3, true)


class _VitalsView extends Control:
	var _hp: float = 1.0
	var _stamina: float = 1.0
	var _alpha: float = 0.0

	func _ready() -> void:
		anchor_left = 0.0
		anchor_right = 0.0
		anchor_top = 1.0
		anchor_bottom = 1.0
		offset_left = 26.0
		offset_right = 248.0
		offset_top = -84.0
		offset_bottom = -24.0
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_values(hp: float, stamina: float, alpha: float) -> void:
		var changed := absf(hp - _hp) > 0.002 or absf(stamina - _stamina) > 0.002 or absf(alpha - _alpha) > 0.004
		_hp = hp
		_stamina = stamina
		_alpha = alpha
		visible = _alpha > 0.01
		if changed:
			queue_redraw()

	func _draw() -> void:
		if _alpha <= 0.01 or not size.is_finite() or size.x < 4.0 or size.y < 4.0:
			return
		var bg := Color(0.91, 0.84, 0.69, 0.86 * _alpha)
		var border := Color(0.22, 0.14, 0.09, 0.92 * _alpha)
		var track := Color(0.32, 0.24, 0.16, 0.35 * _alpha)
		var hp_col := Color(0.76, 0.15, 0.12, 0.95 * _alpha)
		var st_col := Color(0.84, 0.61, 0.18, 0.92 * _alpha)

		draw_rect(Rect2(Vector2.ZERO, size), bg, true)
		draw_rect(Rect2(Vector2.ZERO, size), border, false, 2.0)

		# 5 segmented crimson-wax health pips.
		var pips := 5
		var gap := 5.0
		var pad_x := 12.0
		var pip_w := (size.x - pad_x * 2.0 - gap * float(pips - 1)) / float(pips)
		for i in pips:
			var x := pad_x + float(i) * (pip_w + gap)
			var r_hp := Rect2(x, 12.0, pip_w, 15.0)
			draw_rect(r_hp, track, true)
			var fill_hp := clampf(_hp * float(pips) - float(i), 0.0, 1.0)
			if fill_hp > 0.01:
				draw_rect(Rect2(x, 12.0, pip_w * fill_hp, 15.0), hp_col, true)
			draw_rect(r_hp, border, false, 1.4)

		# Slender 5-segment ochre stamina bar below.
		for i in pips:
			var x := pad_x + float(i) * (pip_w + gap)
			var r_st := Rect2(x, 35.0, pip_w, 9.0)
			draw_rect(r_st, track, true)
			var fill_st := clampf(_stamina * float(pips) - float(i), 0.0, 1.0)
			if fill_st > 0.01:
				draw_rect(Rect2(x, 35.0, pip_w * fill_st, 9.0), st_col, true)
			draw_rect(r_st, border, false, 1.1)


class _SpyglassOverlay extends Control:
	var _zoom: float = 0.0
	var _sighting_label: String = ""
	var _sighting_dist: float = 0.0
	var _sighting_bearing: String = ""
	var _font: Font = null

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false
		_font = HudIcons.get_ui_font()

	func set_zoom(v: float) -> void:
		_zoom = clampf(v, 0.0, 1.0)
		visible = _zoom > 0.03
		queue_redraw()

	func set_sighting(label: String, dist_m: float, bearing: String = "") -> void:
		_sighting_label = GameHUD._to_ascii(label)
		_sighting_dist = dist_m
		_sighting_bearing = GameHUD._to_ascii(bearing).strip_edges()
		queue_redraw()

	func get_sighting_text() -> String:
		if _sighting_label == "":
			return ""
		var upper := _sighting_label.to_upper()
		if _sighting_bearing != "":
			return "%s  -  %d m  %s" % [upper, int(roundf(_sighting_dist)), _sighting_bearing]
		return "%s  -  %d m" % [upper, int(roundf(_sighting_dist))]

	func _draw() -> void:
		if _zoom <= 0.03:
			return
		var view_sz := size if size.length_squared() >= 1.0 else get_viewport_rect().size
		var c := view_sz * 0.5
		var min_dim := minf(view_sz.x, view_sz.y)
		var aperture_r := lerpf(min_dim * 0.68, min_dim * 0.42, _zoom)
		var outer_r := maxf(view_sz.x, view_sz.y) * 0.82
		var a := smoothstep(0.05, 0.55, _zoom)

		# Opaque dark brass-housing mask outside the circular telescope aperture.
		var ring := _annulus_strip(c, aperture_r, outer_r, 64)
		var mask_col := Color(0.04, 0.03, 0.02, 0.96 * a)
		for seg in ring:
			draw_colored_polygon(seg as PackedVector2Array, mask_col)

		# Beveled concentric brass lens rings + subtle glass glint arc.
		draw_arc(c, aperture_r + 6.0, 0.0, TAU, 72, Color(0.42, 0.30, 0.12, a), 12.0, true)
		draw_arc(c, aperture_r + 1.0, 0.0, TAU, 72, Color(0.82, 0.63, 0.25, a), 4.0, true)
		draw_arc(c, aperture_r - 4.0, 0.0, TAU, 72, Color(0.18, 0.12, 0.06, 0.85 * a), 2.2, true)
		draw_arc(c, aperture_r - 12.0, -2.5, -1.7, 16, Color(0.96, 0.95, 0.88, 0.26 * a), 3.0, true)

		# Fine etched maritime sighting ticks around inner perimeter.
		var tick_col := Color(0.18, 0.12, 0.07, 0.48 * a)
		for i in 4:
			var ang := float(i) * PI * 0.5
			var d := Vector2(cos(ang), sin(ang))
			draw_line(c + d * (aperture_r - 36.0), c + d * (aperture_r - 8.0), tick_col, 1.8, true)
		draw_circle(c, 2.0, Color(0.95, 0.88, 0.68, 0.55 * a))

		# Subtle horizon sighting readout tucked cleanly at the bottom of the lens.
		if _sighting_label != "" and _zoom > 0.45 and _font != null:
			var txt := get_sighting_text()
			var sz := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 17)
			var box_r := Rect2(c.x - sz.x * 0.5 - 16.0, c.y + aperture_r - 58.0, sz.x + 32.0, 32.0)
			draw_rect(box_r, Color(0.92, 0.85, 0.70, 0.90 * a), true)
			draw_rect(box_r, Color(0.22, 0.14, 0.09, 0.92 * a), false, 2.0)
			draw_string(_font, Vector2(c.x - sz.x * 0.5, box_r.position.y + 22.0),
				txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, HudIcons.COL_INK)

	static func _annulus_strip(center: Vector2, r_in: float, r_out: float, segs: int) -> Array:
		var quads: Array = []
		for i in segs:
			var a0 := float(i) / float(segs) * TAU
			var a1 := float(i + 1) / float(segs) * TAU
			var d0 := Vector2(cos(a0), sin(a0))
			var d1 := Vector2(cos(a1), sin(a1))
			quads.append(PackedVector2Array([
				center + d0 * r_in,
				center + d0 * r_out,
				center + d1 * r_out,
				center + d1 * r_in,
			]))
		return quads
