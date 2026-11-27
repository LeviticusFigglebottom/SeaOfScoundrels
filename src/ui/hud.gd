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
## - 11-wedge Item Radial (`Q`/`Tab`) and 9-wedge Crew Command Wheel (`G`)
## - Pause / Save / Quality Presets / Audio Sliders / LAN Co-op / Controls overlay (`Escape`)

signal crew_order_issued(order: StringName)
signal pause_changed(open: bool)
signal quality_changed(target: StringName, level: int)
signal return_to_title_requested
signal mode_skip_requested

const RADIAL_HOLD_THRESHOLD_S := 0.22

const ITEM_SLICE_HINTS := {
	&"cutlass": "Light combo | Hold heavy | RMB parry",
	&"boarding_axe": "Heavy cleave | Guard crush | RMB parry",
	&"pistol": "Flintlock shot | RMB aim",
	&"blunderbuss": "6-pellet spread | Short range | RMB aim",
	&"compass": "True North / Chart Pin | LMB track | RMB paces",
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
const STAMINA_FLASH_DURATION := 0.45

const CAPTAIN_CONTROLS_LINES: Array[String] = [
	"[WASD] Move  |  [Space] Jump  |  [Shift] Sprint  |  [X] Step Off",
	"[Q / Tab] Tools Radial (Hold or Tap)  |  [G] Crew Orders  |  [1-6] Quick Slots",
	"[F] Use / Leave Stations & Quick-Drop Anchor  |  [Hold W] Heave Anchor",
	"[S / W] Lower / Raise Sails  |  [A / D] Steer Wheel & Trim Sails  |  [RMB] Center Helm",
	"[LMB / RMB] Slash / Aim / Block / Climb in Cannon  |  [R] Swap Cannon Shot (6 Types)",
	"[T] Speaking Trumpet Crew Recall  |  [B] Shipwright (at Outpost)  |  [Esc] Pause",
]

## Accent color palette for all 6 cannon ordnance types (strict-ASCII live cannon chip).
const ORDNANCE_ACCENT_COLORS := {
	&"iron": Color(0.95, 0.92, 0.84, 1.0),
	&"chainshot": Color(0.36, 0.64, 0.90, 1.0),
	&"firebomb": Color(0.96, 0.44, 0.10, 1.0),
	&"anchorball": Color(0.14, 0.84, 0.46, 1.0),
	&"ballastball": Color(0.64, 0.30, 0.96, 1.0),
	&"flare": Color(0.96, 0.74, 0.18, 1.0),
}

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

var _radial_open_time: float = 0.0
var _radial_initial_hover: int = -1

var _crew_brains: Array[CrewBrain] = []
var _root: Control = null
var _theme: Theme = null
var _damage_vignette: _DamageVignette = null
var _spyglass_view: _SpyglassOverlay = null
var _directional_damage_view: DirectionalDamageOverlay = null
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

# Context prompt & sailing-station telemetry pill (bottom-center)
const SAILING_STATION_KINDS: Array[StringName] = [&"helm", &"sail_length", &"sail_angle", &"anchor"]
var _prompt_panel: PanelContainer = null
var _prompt_label: Label = null
var _prompt_alpha: float = 0.0
var _sailing_pill_panel: PanelContainer = null
var _sailing_pill_style: StyleBoxFlat = null
var _sailing_pill_label: Label = null
var _sailing_full_wind_active: bool = false

# Active tool / supplies chip & always-visible diegetic keycap strip (bottom-right)
var _keycap_strip: HBoxContainer = null
var _keycap_strip_text: String = "[Q] Tools | [G] Crew | [1-6] Slots"
var _tool_panel: PanelContainer = null
var _tool_panel_style: StyleBoxFlat = null
var _tool_title_label: Label = null
var _tool_meta_label: Label = null
var _ordnance_pill: PanelContainer = null
var _ordnance_pill_style: StyleBoxFlat = null
var _ordnance_swatch: ColorRect = null
var _ordnance_label: Label = null
var _active_ordnance_accent: Color = Color(0.95, 0.92, 0.84, 1.0)
var _tool_flash_timer: float = 0.0
var _hull_alert_active: bool = false

# Gold & Voyage whisper (top-right)
const GOLD_ROLL_DURATION := 0.65
const GOLD_TOAST_DURATION := 1.65
const GOLD_TOAST_ACCUM_WINDOW := 0.85
const GOLD_TOAST_FLOAT_PX := 14.0
const GOLD_TOAST_BASE_TOP := 34.0
const GOLD_TOAST_HEIGHT := 24.0
const COL_GOLD_GAIN := Color(1.0, 0.86, 0.34, 1.0)
const COL_GOLD_SPEND := Color(0.95, 0.42, 0.36, 1.0)
const COL_GOLD_TEXT_BASE := Color(0.56, 0.36, 0.06, 1.0)
const COL_GOLD_TEXT_ROLL := Color(0.72, 0.48, 0.04, 1.0)

var emissary_badge_text: String = ""
var _whisper_panel: PanelContainer = null
var _gold_label: Label = null
var _gold_delta_toast_label: Label = null
var _emissary_label: Label = null
var _voyage_title_label: Label = null
var _voyage_obj_label: Label = null
var _whisper_timer: float = 0.0
var _whisper_alpha: float = 0.0
var _last_gold: int = -1
var _gold_initialized: bool = false
var _target_gold: int = 0
var _displayed_gold: int = 0
var _gold_roll_start: int = 0
var _gold_roll_elapsed: float = 0.0
var _gold_rolling: bool = false
var _gold_toast_active: bool = false
var _gold_toast_amount: int = 0
var _gold_toast_elapsed: float = 0.0
var _gold_toast_text: String = ""
var _custom_voyage_title: String = ""
var _custom_voyage_obj: String = ""

# Vitals fade, combat feedback timers & peripheral damage vignette tracking
var _vitals_show_timer: float = 0.0
var _vitals_alpha: float = 0.0
var _last_hp: float = -1.0
var _last_stamina: float = -1.0
var _damage_flash: float = 0.0
var _low_hp_clock: float = 0.0
var _parry_flash_timer: float = 0.0
var _stamina_flash_timer: float = 0.0

# Pause menu widget references
var _ocean_qual_btns: Array[Button] = []
var _cloud_qual_btns: Array[Button] = []
var _bus_sliders: Dictionary = {}  # StringName -> HSlider
var _coop_addr_edit: LineEdit = null
var _coop_port_edit: LineEdit = null
var _coop_status_label: Label = null

const CREW_ROSTER_REFRESH_INTERVAL := 0.20

# Gameplay HUD visibility & Top-Left HUD Stack (Mode Objective Card + AI Crew Roster Card)
var _hud_visible: bool = true
var _top_left_stack: VBoxContainer = null
var _mode_objective_panel: PanelContainer = null
var _mode_obj_title_label: Label = null
var _mode_obj_progress_label: Label = null
var _mode_obj_body_label: Label = null
var _mode_skip_btn: Button = null
var _mode_objective_active: bool = false
var _crew_roster_panel: PanelContainer = null
var _crew_roster_count_label: Label = null
var _crew_roster_rows_box: VBoxContainer = null
var _crew_roster_rows: Array[Dictionary] = []
var _crew_roster_entries: Array[Dictionary] = []
var _crew_roster_accum: float = 0.0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_theme = HudIcons.build_parchment_theme()
	_build_ui()
	if Game != null and not Game.notice.is_connected(_on_game_notice):
		Game.notice.connect(_on_game_notice)
	if Game != null and Game.profile != null:
		var init_gold := maxi(0, int(Game.profile.data.get("gold", 0)))
		_last_gold = init_gold
		if not _gold_initialized:
			_target_gold = init_gold
			_displayed_gold = init_gold
			_gold_roll_start = init_gold
	_update_gold_label_text()
	_sync_quality_button_states()
	_refresh_crew_roster()


func _exit_tree() -> void:
	_disconnect_signals()
	if Game != null and Game.notice.is_connected(_on_game_notice):
		Game.notice.disconnect(_on_game_notice)
	_gold_rolling = false
	_gold_toast_active = false
	_gold_toast_amount = 0
	_gold_toast_text = ""
	_crew_brains.clear()
	_crew_roster_rows.clear()
	_crew_roster_entries.clear()


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
	_parry_flash_timer = 0.0
	_stamina_flash_timer = 0.0
	clear_directional_damage_arcs()
	_connect_signals()
	if voyage_manager != null and voyage_manager.emissary != null and voyage_manager.emissary.is_active():
		set_emissary_status(
			voyage_manager.emissary.active_company,
			voyage_manager.emissary.grade,
			voyage_manager.emissary.get_multiplier()
		)
	else:
		set_emissary_status(&"", 0, 1.0)
	_sync_damage_vignette(0.0)
	_refresh_item_radial_entries()
	_refresh_tool_chip()
	_tick_sailing_telemetry()
	_sync_quality_button_states()
	_refresh_crew_roster()


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
		if not inventory.compass_mode_changed.is_connected(_on_tool_state_changed):
			inventory.compass_mode_changed.connect(_on_tool_state_changed)
		if not inventory.grog_toast_raised.is_connected(_on_grog_toast_raised):
			inventory.grog_toast_raised.connect(_on_grog_toast_raised)
	if combat != null:
		if not combat.hit_landed.is_connected(_on_combat_hit_landed):
			combat.hit_landed.connect(_on_combat_hit_landed)
		if not combat.target_hit.is_connected(_on_combat_target_hit):
			combat.target_hit.connect(_on_combat_target_hit)
		if not combat.parried.is_connected(_on_combat_parried):
			combat.parried.connect(_on_combat_parried)
		if not combat.damage_received.is_connected(_on_combat_damage_received):
			combat.damage_received.connect(_on_combat_damage_received)
		if not combat.stamina_depleted.is_connected(_on_combat_stamina_depleted):
			combat.stamina_depleted.connect(_on_combat_stamina_depleted)
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
		if voyage_manager.emissary != null:
			if not voyage_manager.emissary.grade_changed.is_connected(_on_emissary_grade_changed):
				voyage_manager.emissary.grade_changed.connect(_on_emissary_grade_changed)
			if not voyage_manager.emissary.flag_lowered.is_connected(_on_emissary_flag_lowered):
				voyage_manager.emissary.flag_lowered.connect(_on_emissary_flag_lowered)
			if not voyage_manager.emissary.flag_broken.is_connected(_on_emissary_flag_broken):
				voyage_manager.emissary.flag_broken.connect(_on_emissary_flag_broken)
	if ship != null:
		if not ship.cannon_ordnance_changed.is_connected(_on_tool_state_changed):
			ship.cannon_ordnance_changed.connect(_on_tool_state_changed)
		if not ship.cursed_hit.is_connected(_on_ship_cursed_hit):
			ship.cursed_hit.connect(_on_ship_cursed_hit)


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
		if inventory.compass_mode_changed.is_connected(_on_tool_state_changed):
			inventory.compass_mode_changed.disconnect(_on_tool_state_changed)
		if inventory.grog_toast_raised.is_connected(_on_grog_toast_raised):
			inventory.grog_toast_raised.disconnect(_on_grog_toast_raised)
	if combat != null and is_instance_valid(combat):
		if combat.hit_landed.is_connected(_on_combat_hit_landed):
			combat.hit_landed.disconnect(_on_combat_hit_landed)
		if combat.target_hit.is_connected(_on_combat_target_hit):
			combat.target_hit.disconnect(_on_combat_target_hit)
		if combat.parried.is_connected(_on_combat_parried):
			combat.parried.disconnect(_on_combat_parried)
		if combat.damage_received.is_connected(_on_combat_damage_received):
			combat.damage_received.disconnect(_on_combat_damage_received)
		if combat.stamina_depleted.is_connected(_on_combat_stamina_depleted):
			combat.stamina_depleted.disconnect(_on_combat_stamina_depleted)
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
		if voyage_manager.emissary != null:
			if voyage_manager.emissary.grade_changed.is_connected(_on_emissary_grade_changed):
				voyage_manager.emissary.grade_changed.disconnect(_on_emissary_grade_changed)
			if voyage_manager.emissary.flag_lowered.is_connected(_on_emissary_flag_lowered):
				voyage_manager.emissary.flag_lowered.disconnect(_on_emissary_flag_lowered)
			if voyage_manager.emissary.flag_broken.is_connected(_on_emissary_flag_broken):
				voyage_manager.emissary.flag_broken.disconnect(_on_emissary_flag_broken)
	if ship != null and is_instance_valid(ship):
		if ship.cannon_ordnance_changed.is_connected(_on_tool_state_changed):
			ship.cannon_ordnance_changed.disconnect(_on_tool_state_changed)
		if ship.cursed_hit.is_connected(_on_ship_cursed_hit):
			ship.cursed_hit.disconnect(_on_ship_cursed_hit)


## Explicitly register a `CrewBrain` to receive captain orders (also auto-discovered in tree).
func register_crew_brain(brain: CrewBrain) -> void:
	if brain != null and not _crew_brains.has(brain):
		_crew_brains.append(brain)
	_crew_roster_accum = 0.0
	_refresh_crew_roster()


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
	_radial_open_time = Time.get_ticks_msec() * 0.001
	_radial_initial_hover = item_radial.hovered_index
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
	_radial_open_time = Time.get_ticks_msec() * 0.001
	_radial_initial_hover = command_wheel.hovered_index
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
	_crew_roster_accum = 0.0
	_refresh_crew_roster()
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
	_sync_mode_objective_visibility()
	if _gold_delta_toast_label != null and _gold_toast_active:
		_gold_delta_toast_label.visible = not pause_open and _gold_delta_toast_label.modulate.a > 0.01
	_sync_look_pause()
	pause_changed.emit(pause_open)


func toggle_pause() -> void:
	set_pause_open(not pause_open)


## Cleanly hide or show the gameplay HUD (e.g. while First-Launch TitleMenu is open).
func set_hud_visible(vis: bool) -> void:
	_hud_visible = vis
	visible = vis
	if _root != null:
		_root.visible = vis
	if not vis:
		dismiss_voyage_title()
		if item_radial != null and item_radial.is_open:
			item_radial.close_wheel(false)
		if command_wheel != null and command_wheel.is_open:
			command_wheel.close_wheel(false)
	_sync_mode_objective_visibility()


## Return true when gameplay HUD visibility is enabled.
func is_hud_visible() -> bool:
	return _hud_visible


## Display or update the top-left Mode Objective Card (Tutorial / Naval Skirmish).
func set_mode_objective(
	title_text: String,
	body_text: String,
	progress_text: String = "",
	show_skip_btn: bool = false
) -> void:
	var clean_title := _to_ascii(title_text.strip_edges())
	var clean_body := _to_ascii(body_text.strip_edges())
	var clean_prog := _to_ascii(progress_text.strip_edges())
	if clean_title == "" and clean_body == "":
		clear_mode_objective()
		return
	_mode_objective_active = true
	if _mode_obj_title_label != null:
		_mode_obj_title_label.text = clean_title
		_mode_obj_title_label.visible = clean_title != ""
	if _mode_obj_progress_label != null:
		_mode_obj_progress_label.text = clean_prog
		_mode_obj_progress_label.visible = clean_prog != ""
	if _mode_obj_body_label != null:
		_mode_obj_body_label.text = clean_body
		_mode_obj_body_label.visible = clean_body != ""
	if _mode_skip_btn != null:
		_mode_skip_btn.visible = show_skip_btn
	_sync_mode_objective_visibility()


## Clear and hide the top-left Mode Objective Card.
func clear_mode_objective() -> void:
	_mode_objective_active = false
	if _mode_obj_title_label != null:
		_mode_obj_title_label.text = ""
	if _mode_obj_progress_label != null:
		_mode_obj_progress_label.text = ""
		_mode_obj_progress_label.visible = false
	if _mode_obj_body_label != null:
		_mode_obj_body_label.text = ""
	if _mode_skip_btn != null:
		_mode_skip_btn.visible = false
	_sync_mode_objective_visibility()


## Emit `mode_skip_requested` (bound to the optional compact Tutorial Skip Step button).
func skip_tutorial_step() -> void:
	if Audio != null:
		Audio.play_sfx(&"ui_select", Vector3.INF, -2.5)
	mode_skip_requested.emit()


## True while the top-left Mode Objective Card is active and visible on screen.
func is_mode_objective_visible() -> bool:
	return _mode_objective_panel != null and _mode_objective_panel.visible


func get_mode_objective_title() -> String:
	return _mode_obj_title_label.text if _mode_obj_title_label != null else ""


func get_mode_objective_body() -> String:
	return _mode_obj_body_label.text if _mode_obj_body_label != null else ""


func get_mode_objective_progress() -> String:
	return _mode_obj_progress_label.text if _mode_obj_progress_label != null else ""


## True while the top-left AI Crew Roster Status Card is visible on screen.
func is_crew_roster_visible() -> bool:
	return _crew_roster_panel != null and _crew_roster_panel.visible


## Return a live snapshot of displayed AI crew roster rows:
## `[{"name", "task", "task_label", "hp_ratio", "order"}]`.
func get_crew_roster_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _crew_roster_entries:
		out.append(entry.duplicate())
	return out


func _sync_top_left_visibility() -> void:
	if _mode_objective_panel != null:
		_mode_objective_panel.visible = _mode_objective_active and _hud_visible and not pause_open
	if _crew_roster_panel != null:
		_crew_roster_panel.visible = _hud_visible and not pause_open and not _crew_roster_entries.is_empty()


func _sync_mode_objective_visibility() -> void:
	if _mode_objective_panel != null:
		_mode_objective_panel.visible = _mode_objective_active and _hud_visible and not pause_open
	_crew_roster_accum = 0.0
	_refresh_crew_roster()


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


## Update displayed Captain gold. First call (or `instant = true`) snaps immediately with
## no phantom toast; subsequent changes smoothly roll `_displayed_gold` over 0.65 s and
## spawn/accumulate a floating strict-ASCII `GoldDeltaToast` beside the gold readout.
func set_gold(amount: int, instant: bool = false) -> void:
	var clamped := maxi(0, amount)
	if instant or not _gold_initialized:
		_gold_initialized = true
		_target_gold = clamped
		_displayed_gold = clamped
		_gold_roll_start = clamped
		_gold_roll_elapsed = GOLD_ROLL_DURATION
		_gold_rolling = false
		_update_gold_label_text()
		return

	var delta_gold := clamped - _target_gold
	if delta_gold == 0:
		return

	_gold_roll_start = _displayed_gold
	_target_gold = clamped
	_gold_roll_elapsed = 0.0
	_gold_rolling = true
	_whisper_timer = maxf(_whisper_timer, 5.5)

	var same_sign := (delta_gold > 0 and _gold_toast_amount > 0) or (delta_gold < 0 and _gold_toast_amount < 0)
	if _gold_toast_active and same_sign and _gold_toast_elapsed <= GOLD_TOAST_ACCUM_WINDOW:
		_gold_toast_amount += delta_gold
		_gold_toast_elapsed = 0.0
	else:
		_gold_toast_active = true
		_gold_toast_amount = delta_gold
		_gold_toast_elapsed = 0.0

	_gold_toast_text = _to_ascii(
		("+%d Gold" % _gold_toast_amount) if _gold_toast_amount > 0 else ("-%d Gold" % absi(_gold_toast_amount))
	)
	_apply_gold_toast_visuals()
	_update_gold_label_text()


## Exact latest gold target immediately after `set_gold()` (even mid roll-up).
func get_target_gold() -> int:
	return _target_gold


## Currently displayed integer gold value during the 0.65 s ease-out cubic roll-up.
func get_displayed_gold() -> int:
	return _displayed_gold


## Return the floating strict-ASCII `GoldDeltaToast` Label mounted beside the gold counter.
func get_gold_delta_toast_label() -> Label:
	return _gold_delta_toast_label


## Return current active strict-ASCII delta toast text (empty string when idle/hidden).
func get_gold_delta_toast_text() -> String:
	return _gold_toast_text if _gold_toast_active else ""


## Deterministically advance the gold counter ease-out cubic roll-up and floating delta toast.
func step_gold_animation(delta: float) -> void:
	var dt := maxf(delta, 0.0)
	if _gold_rolling:
		_gold_roll_elapsed += dt
		var t := clampf(_gold_roll_elapsed / GOLD_ROLL_DURATION, 0.0, 1.0)
		var ease_t := 1.0 - pow(1.0 - t, 3.0)
		if t >= 1.0:
			_displayed_gold = _target_gold
			_gold_rolling = false
		else:
			_displayed_gold = int(roundf(lerpf(float(_gold_roll_start), float(_target_gold), ease_t)))
		_update_gold_label_text()

	if _gold_toast_active:
		_gold_toast_elapsed += dt
		if _gold_toast_elapsed >= GOLD_TOAST_DURATION:
			_gold_toast_active = false
			_gold_toast_amount = 0
			_gold_toast_text = ""
			if _gold_delta_toast_label != null:
				_gold_delta_toast_label.text = ""
				_gold_delta_toast_label.modulate.a = 0.0
				_gold_delta_toast_label.visible = false
				_gold_delta_toast_label.offset_top = GOLD_TOAST_BASE_TOP
				_gold_delta_toast_label.offset_bottom = GOLD_TOAST_BASE_TOP + GOLD_TOAST_HEIGHT
		else:
			var u := clampf(_gold_toast_elapsed / GOLD_TOAST_DURATION, 0.0, 1.0)
			var float_t := 1.0 - pow(1.0 - u, 2.0)
			var cur_top := GOLD_TOAST_BASE_TOP - GOLD_TOAST_FLOAT_PX * float_t
			var alpha := 1.0 if u <= 0.55 else (1.0 - smoothstep(0.55, 1.0, u))
			if _gold_delta_toast_label != null:
				_gold_delta_toast_label.offset_top = cur_top
				_gold_delta_toast_label.offset_bottom = cur_top + GOLD_TOAST_HEIGHT
				_gold_delta_toast_label.modulate.a = alpha
				_gold_delta_toast_label.visible = not pause_open and alpha > 0.01


func _update_gold_label_text() -> void:
	if _gold_label == null:
		return
	_gold_label.text = "%d Gold" % _displayed_gold
	_gold_label.add_theme_color_override("font_color", COL_GOLD_TEXT_ROLL if _gold_rolling else COL_GOLD_TEXT_BASE)


func _apply_gold_toast_visuals() -> void:
	if _gold_delta_toast_label == null:
		return
	var col := COL_GOLD_GAIN if _gold_toast_amount >= 0 else COL_GOLD_SPEND
	_gold_delta_toast_label.text = _gold_toast_text
	_gold_delta_toast_label.add_theme_color_override("font_color", col)
	_gold_delta_toast_label.offset_top = GOLD_TOAST_BASE_TOP
	_gold_delta_toast_label.offset_bottom = GOLD_TOAST_BASE_TOP + GOLD_TOAST_HEIGHT
	_gold_delta_toast_label.modulate.a = 1.0
	_gold_delta_toast_label.visible = _gold_toast_active and not pause_open


## Update the strict-ASCII gilded Emissary Grade badge inside the top-right objective card.
func set_emissary_status(company_id: StringName, grade: int, multiplier: float) -> void:
	if grade <= 0 or company_id == &"":
		emissary_badge_text = ""
	else:
		emissary_badge_text = _to_ascii(EmissaryLedger.format_badge_text(company_id, grade, multiplier))
		_whisper_timer = maxf(_whisper_timer, 6.0)
	_sync_emissary_label()


## True while the top-right Emissary badge label is actively visible.
func is_emissary_badge_visible() -> bool:
	return _emissary_label != null and _emissary_label.visible


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


## Format a compact strict-ASCII 9-slot rudder bar mirroring the 3D King Spoke & brass arch.
## Centered: `[---|---] CTR`, Port: `[<--|---] PORT 45%`, Starboard: `[---|>>>] STBD 100%`.
static func format_rudder_bar(helm_val: float) -> String:
	var h := clampf(helm_val, -1.0, 1.0)
	var mag := absf(h)
	if mag < 0.06:
		return "[---|---] CTR"
	var pct := clampi(int(roundf(mag * 100.0)), 1, 100)
	var chevrons := 3 if mag >= 0.80 else (2 if mag >= 0.48 else 1)
	if h < 0.0:
		var left_slots := "<".repeat(chevrons) + "-".repeat(3 - chevrons)
		return "[%s|---] PORT %d%%" % [left_slots, pct]
	var right_slots := "-".repeat(3 - chevrons) + ">".repeat(chevrons)
	return "[---|%s] STBD %d%%" % [right_slots, pct]


## Return the live helm/sail telemetry pill text (e.g. "[---|---] CTR  |  Sail 90%  |  11.8 kt  |  FULL WIND").
func get_sailing_telemetry_text() -> String:
	return _sailing_pill_label.text if _sailing_pill_label != null else ""


## True while the diegetic sailing-station telemetry pill is visible.
func is_sailing_telemetry_visible() -> bool:
	return _sailing_pill_panel != null and _sailing_pill_panel.visible


## True while the sailing telemetry pill is warmly highlighted in nautical gold for full-billow wind catch.
func is_sailing_full_wind_highlighted() -> bool:
	return _sailing_full_wind_active


## Current border Color of the sailing telemetry pill StyleBoxFlat.
func get_sailing_pill_border_color() -> Color:
	return _sailing_pill_style.border_color if _sailing_pill_style != null else HudIcons.COL_INK_SOFT


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


## Compute horizontal bearing (radians in [-PI, PI]) from the Captain's facing yaw to `source_world_pos`.
## Front = 0, Right = +PI/2, Left = -PI/2, Behind = PI. Returns NAN if source is invalid or coincident.
func compute_relative_bearing(source_world_pos: Vector3) -> float:
	if not source_world_pos.is_finite():
		return NAN
	var origin := Vector3.ZERO
	var fwd := Vector2(0.0, -1.0)
	var right := Vector2(1.0, 0.0)
	if pawn != null and is_instance_valid(pawn):
		origin = pawn.global_position
		var yaw := pawn.look_yaw
		fwd = Vector2(-sin(yaw), -cos(yaw))
		right = Vector2(cos(yaw), -sin(yaw))
	elif player_controller != null and is_instance_valid(player_controller) and player_controller.camera != null:
		var cam := player_controller.camera
		origin = cam.global_position
		var cf := -cam.global_basis.z
		var cr := cam.global_basis.x
		var cf2 := Vector2(cf.x, cf.z)
		var cr2 := Vector2(cr.x, cr.z)
		if cf2.length_squared() > 0.0001:
			fwd = cf2.normalized()
		if cr2.length_squared() > 0.0001:
			right = cr2.normalized()
	var delta_xz := Vector2(source_world_pos.x - origin.x, source_world_pos.z - origin.z)
	if delta_xz.length_squared() < 0.0004:
		return NAN
	var dir_xz := delta_xz.normalized()
	return atan2(dir_xz.dot(right), dir_xz.dot(fwd))


## Queue a crisp directional crimson threat/damage arc pointing toward `source_world_pos`.
func register_directional_damage(source_world_pos: Vector3, intensity: float = 1.0) -> void:
	if _directional_damage_view == null:
		return
	var bearing := compute_relative_bearing(source_world_pos)
	if is_nan(bearing):
		return
	_directional_damage_view.add_arc(source_world_pos, bearing, clampf(intensity, 0.25, 1.0), _is_colorblind_mode())


## Number of currently active fading directional damage arcs around the reticle.
func get_directional_damage_arc_count() -> int:
	return _directional_damage_view.get_arc_count() if _directional_damage_view != null else 0


## Snapshot of active directional damage arcs (`[{"bearing", "remaining", "intensity", "source_pos"}]`).
func get_directional_damage_arcs() -> Array[Dictionary]:
	return _directional_damage_view.get_arcs_snapshot() if _directional_damage_view != null else []


## Immediately clear all active directional damage arcs.
func clear_directional_damage_arcs() -> void:
	if _directional_damage_view != null:
		_directional_damage_view.clear_arcs()


## Flash tactile diagonal ink hit-confirm ticks around the center crosshair.
func flash_hit_confirm(was_heavy: bool = false) -> void:
	if _crosshair_view != null:
		_crosshair_view.trigger_hit_confirm(was_heavy)


## Flash a crisp golden ring & twin burnished-gold brass guard-arcs around the crosshair on parry.
func flash_parry() -> void:
	_parry_flash_timer = _CrosshairView.PARRY_DURATION
	if _crosshair_view != null:
		_crosshair_view.trigger_parry_flash()


## Pulse the bottom-left stamina bar gold/red when an action fails due to insufficient stamina.
func flash_stamina_depleted() -> void:
	_stamina_flash_timer = STAMINA_FLASH_DURATION
	_vitals_show_timer = maxf(_vitals_show_timer, 3.5)
	if _vitals_view != null:
		var hp_r := clampf(pawn.health / maxf(pawn.max_health, 1.0), 0.0, 1.0) if (pawn != null and is_instance_valid(pawn)) else 1.0
		var st_r := clampf(combat.stamina / maxf(combat.max_stamina, 1.0), 0.0, 1.0) if (combat != null and is_instance_valid(combat)) else 0.0
		_vitals_alpha = maxf(_vitals_alpha, 0.92)
		_vitals_view.set_values(hp_r, st_r, _vitals_alpha, 1.0)


## Remaining seconds on the active crosshair hit-confirm flash (0 when idle).
func get_hit_confirm_remaining() -> float:
	return _crosshair_view.hit_timer if _crosshair_view != null else 0.0


## Remaining seconds on the active crosshair parry ring & guard-arc flash (0 when idle).
func get_parry_flash_remaining() -> float:
	return _crosshair_view.parry_timer if _crosshair_view != null else _parry_flash_timer


## Remaining seconds on the bottom-left stamina depletion pulse (0 when idle).
func get_stamina_flash_remaining() -> float:
	return _stamina_flash_timer


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


## Always-visible bottom-right keycap strip text (`[Q] Tools | [G] Crew | [1-6] Slots`).
func get_keycap_strip_text() -> String:
	return _keycap_strip_text


## True while the always-legible diegetic keycap strip is visible.
func is_keycap_strip_visible() -> bool:
	return _keycap_strip != null and _keycap_strip.visible


## Current bottom-center context prompt text.
func get_context_prompt_text() -> String:
	return _prompt_label.text if _prompt_label != null else ""


## Return the accent Color for any of the 6 cannon ordnance types (Iron, Chainshot, Firebomb, Anchorball, Ballastball, Flare).
static func get_ordnance_accent_color(kind: StringName) -> Color:
	return ORDNANCE_ACCENT_COLORS.get(kind, ORDNANCE_ACCENT_COLORS[&"iron"]) as Color


## Current live accent Color applied to the cannon ordnance badge.
func get_active_ordnance_accent_color() -> Color:
	return _active_ordnance_accent


## True while the dedicated cannon ordnance accent badge is visible inside the tool chip.
func is_ordnance_chip_visible() -> bool:
	return _ordnance_pill != null and _ordnance_pill.visible


## Strict-ASCII text currently displayed on the cannon ordnance accent badge.
func get_ordnance_chip_text() -> String:
	return _ordnance_label.text if _ordnance_label != null else ""


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

	# 1b. Directional crimson parchment-ink damage arcs around the screen reticle.
	_directional_damage_view = DirectionalDamageOverlay.new()
	_directional_damage_view.name = "DirectionalDamageOverlay"
	_root.add_child(_directional_damage_view)

	# 2. Subtle center crosshair dot with hit-confirm ticks, parry ring & brass guard arcs.
	_crosshair_view = _CrosshairView.new()
	_crosshair_view.name = "Crosshair"
	_root.add_child(_crosshair_view)

	# 3. Top-center Crew Callout & Notice parchment scroll banner, Boss Bar, and Voyage Title Card.
	_build_banner()
	_build_boss_bar()
	_build_voyage_title_card()

	# 4. Top-right Gold & Voyage Objective whisper card + Top-left Mode Objective card.
	_build_whisper_card()
	_build_mode_objective_card()

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
	_gold_label.name = "GoldLabel"
	_gold_label.text = "%d Gold" % _displayed_gold
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gold_label.add_theme_font_size_override("font_size", 17)
	_gold_label.add_theme_color_override("font_color", COL_GOLD_TEXT_BASE)
	vbox.add_child(_gold_label)

	_emissary_label = Label.new()
	_emissary_label.name = "EmissaryBadgeLabel"
	_emissary_label.text = ""
	_emissary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_emissary_label.add_theme_font_size_override("font_size", 13)
	_emissary_label.add_theme_color_override("font_color", Color(0.66, 0.44, 0.05))
	_emissary_label.visible = false
	vbox.add_child(_emissary_label)
	_sync_emissary_label()

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

	# Floating brass-gold / coral-crimson gold delta toast right beside _gold_label.
	_gold_delta_toast_label = Label.new()
	_gold_delta_toast_label.name = "GoldDeltaToast"
	_gold_delta_toast_label.anchor_left = 1.0
	_gold_delta_toast_label.anchor_right = 1.0
	_gold_delta_toast_label.anchor_top = 0.0
	_gold_delta_toast_label.anchor_bottom = 0.0
	_gold_delta_toast_label.offset_left = -312.0
	_gold_delta_toast_label.offset_right = -148.0
	_gold_delta_toast_label.offset_top = GOLD_TOAST_BASE_TOP
	_gold_delta_toast_label.offset_bottom = GOLD_TOAST_BASE_TOP + GOLD_TOAST_HEIGHT
	_gold_delta_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_gold_delta_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gold_delta_toast_label.text = ""
	_gold_delta_toast_label.add_theme_font_size_override("font_size", 16)
	_gold_delta_toast_label.add_theme_color_override("font_color", COL_GOLD_GAIN)
	_gold_delta_toast_label.add_theme_color_override("font_outline_color", Color(0.14, 0.08, 0.04, 0.92))
	_gold_delta_toast_label.add_theme_constant_override("outline_size", 3)
	_gold_delta_toast_label.add_theme_color_override("font_shadow_color", Color(0.10, 0.06, 0.03, 0.80))
	_gold_delta_toast_label.add_theme_constant_override("shadow_offset_x", 1)
	_gold_delta_toast_label.add_theme_constant_override("shadow_offset_y", 1)
	_gold_delta_toast_label.modulate.a = 0.0
	_gold_delta_toast_label.visible = false
	_root.add_child(_gold_delta_toast_label)
	if _gold_toast_active:
		_apply_gold_toast_visuals()


func _build_mode_objective_card() -> void:
	_top_left_stack = VBoxContainer.new()
	_top_left_stack.name = "TopLeftHUDStack"
	_top_left_stack.anchor_left = 0.0
	_top_left_stack.anchor_right = 0.0
	_top_left_stack.anchor_top = 0.0
	_top_left_stack.anchor_bottom = 0.0
	_top_left_stack.offset_left = 24.0
	_top_left_stack.offset_top = 24.0
	_top_left_stack.offset_right = 392.0
	_top_left_stack.offset_bottom = 240.0
	_top_left_stack.grow_vertical = Control.GROW_DIRECTION_END
	_top_left_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_left_stack.add_theme_constant_override("separation", 8)
	_root.add_child(_top_left_stack)

	_mode_objective_panel = PanelContainer.new()
	_mode_objective_panel.name = "ModeObjectiveCard"
	_mode_objective_panel.custom_minimum_size = Vector2(368.0, 0.0)
	_mode_objective_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_objective_panel.grow_vertical = Control.GROW_DIRECTION_END
	_mode_objective_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_mode_objective_panel.add_theme_stylebox_override("panel",
		HudIcons.make_parchment_box(Color(0.93, 0.86, 0.71, 0.92), HudIcons.COL_BRASS, 2, 7, 15, 10))
	_mode_objective_panel.visible = false
	_top_left_stack.add_child(_mode_objective_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	_mode_objective_panel.add_child(vbox)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hdr)

	_mode_obj_title_label = Label.new()
	_mode_obj_title_label.name = "ModeObjectiveTitle"
	_mode_obj_title_label.text = ""
	_mode_obj_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_obj_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode_obj_title_label.add_theme_font_size_override("font_size", 15)
	_mode_obj_title_label.add_theme_color_override("font_color", HudIcons.COL_CRIMSON)
	hdr.add_child(_mode_obj_title_label)

	_mode_obj_progress_label = Label.new()
	_mode_obj_progress_label.name = "ModeObjectiveProgress"
	_mode_obj_progress_label.text = ""
	_mode_obj_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_obj_progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode_obj_progress_label.add_theme_font_size_override("font_size", 13)
	_mode_obj_progress_label.add_theme_color_override("font_color", Color(0.56, 0.36, 0.06))
	_mode_obj_progress_label.visible = false
	hdr.add_child(_mode_obj_progress_label)

	_mode_obj_body_label = Label.new()
	_mode_obj_body_label.name = "ModeObjectiveBody"
	_mode_obj_body_label.text = ""
	_mode_obj_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_obj_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode_obj_body_label.add_theme_font_size_override("font_size", 14)
	_mode_obj_body_label.add_theme_color_override("font_color", HudIcons.COL_INK)
	vbox.add_child(_mode_obj_body_label)

	_mode_skip_btn = Button.new()
	_mode_skip_btn.name = "ModeSkipButton"
	_mode_skip_btn.text = "Skip Step"
	_mode_skip_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	_mode_skip_btn.custom_minimum_size = Vector2(96.0, 28.0)
	_mode_skip_btn.add_theme_font_size_override("font_size", 12)
	_mode_skip_btn.visible = false
	_mode_skip_btn.pressed.connect(skip_tutorial_step)
	vbox.add_child(_mode_skip_btn)

	_build_crew_roster_card()


func _build_crew_roster_card() -> void:
	_crew_roster_panel = PanelContainer.new()
	_crew_roster_panel.name = "CrewRosterCard"
	_crew_roster_panel.custom_minimum_size = Vector2(248.0, 0.0)
	_crew_roster_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_crew_roster_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crew_roster_panel.add_theme_stylebox_override("panel",
		HudIcons.make_parchment_box(Color(0.93, 0.86, 0.71, 0.90), HudIcons.COL_BRASS, 2, 6, 10, 7))
	_crew_roster_panel.visible = false
	_top_left_stack.add_child(_crew_roster_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crew_roster_panel.add_child(vbox)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 6)
	hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hdr)

	var title_lbl := Label.new()
	title_lbl.name = "CrewWatchHeader"
	title_lbl.text = "CREW WATCH"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", HudIcons.COL_CRIMSON)
	hdr.add_child(title_lbl)

	_crew_roster_count_label = Label.new()
	_crew_roster_count_label.name = "CrewWatchCount"
	_crew_roster_count_label.text = "0"
	_crew_roster_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_crew_roster_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crew_roster_count_label.add_theme_font_size_override("font_size", 12)
	_crew_roster_count_label.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	hdr.add_child(_crew_roster_count_label)

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	rule.color = Color(0.56, 0.42, 0.22, 0.45)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(rule)

	_crew_roster_rows_box = VBoxContainer.new()
	_crew_roster_rows_box.name = "CrewRosterRows"
	_crew_roster_rows_box.add_theme_constant_override("separation", 4)
	_crew_roster_rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_crew_roster_rows_box)


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
	_sailing_pill_style = HudIcons.make_parchment_box(Color(0.92, 0.85, 0.70, 0.90), HudIcons.COL_INK_SOFT, 2, 6, 16, 6)
	_sailing_pill_panel.add_theme_stylebox_override("panel", _sailing_pill_style)
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
	var stack := VBoxContainer.new()
	stack.name = "BottomRightHUDStack"
	stack.anchor_left = 1.0
	stack.anchor_right = 1.0
	stack.anchor_top = 1.0
	stack.anchor_bottom = 1.0
	stack.offset_left = -320.0
	stack.offset_right = -24.0
	stack.offset_top = -132.0
	stack.offset_bottom = -24.0
	stack.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	stack.alignment = BoxContainer.ALIGNMENT_END
	stack.add_theme_constant_override("separation", 6)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(stack)

	# Crisp always-legible diegetic keycap strip right above the Tool Chip (never overwritten!).
	_keycap_strip = HBoxContainer.new()
	_keycap_strip.name = "KeycapStrip"
	_keycap_strip.alignment = BoxContainer.ALIGNMENT_END
	_keycap_strip.size_flags_horizontal = Control.SIZE_SHRINK_END
	_keycap_strip.add_theme_constant_override("separation", 6)
	_keycap_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_keycap_strip)

	_keycap_strip.add_child(_make_keycap_badge("KeycapTools", "Q", "Tools", true))
	_keycap_strip.add_child(_make_keycap_badge("KeycapCrew", "G", "Crew", false))
	_keycap_strip.add_child(_make_keycap_badge("KeycapSlots", "1-6", "Slots", false))

	_tool_panel = PanelContainer.new()
	_tool_panel.name = "ToolChip"
	_tool_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_tool_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tool_panel_style = HudIcons.make_parchment_box(Color(0.91, 0.84, 0.69, 0.88), HudIcons.COL_INK_SOFT, 2, 6, 14, 7)
	_tool_panel.add_theme_stylebox_override("panel", _tool_panel_style)
	stack.add_child(_tool_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tool_panel.add_child(vbox)

	var header_row := HBoxContainer.new()
	header_row.alignment = BoxContainer.ALIGNMENT_END
	header_row.add_theme_constant_override("separation", 8)
	header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(header_row)

	_ordnance_pill = PanelContainer.new()
	_ordnance_pill.name = "OrdnanceAccentBadge"
	_ordnance_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ordnance_pill_style = HudIcons.make_parchment_box(Color(0.14, 0.11, 0.08, 0.94), get_ordnance_accent_color(&"iron"), 2, 5, 8, 2)
	_ordnance_pill_style.shadow_size = 0
	_ordnance_pill.add_theme_stylebox_override("panel", _ordnance_pill_style)
	_ordnance_pill.visible = false
	header_row.add_child(_ordnance_pill)

	var ord_row := HBoxContainer.new()
	ord_row.add_theme_constant_override("separation", 5)
	ord_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ordnance_pill.add_child(ord_row)

	_ordnance_swatch = ColorRect.new()
	_ordnance_swatch.name = "OrdnanceSwatch"
	_ordnance_swatch.custom_minimum_size = Vector2(9.0, 9.0)
	_ordnance_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ordnance_swatch.color = get_ordnance_accent_color(&"iron")
	_ordnance_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ord_row.add_child(_ordnance_swatch)

	_ordnance_label = Label.new()
	_ordnance_label.name = "OrdnanceLabel"
	_ordnance_label.text = "Iron"
	_ordnance_label.add_theme_font_size_override("font_size", 12)
	_ordnance_label.add_theme_color_override("font_color", get_ordnance_accent_color(&"iron"))
	_ordnance_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ord_row.add_child(_ordnance_label)

	_tool_title_label = Label.new()
	_tool_title_label.text = "Cutlass"
	_tool_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tool_title_label.add_theme_font_size_override("font_size", 16)
	_tool_title_label.add_theme_color_override("font_color", HudIcons.COL_INK)
	header_row.add_child(_tool_title_label)

	_tool_meta_label = Label.new()
	_tool_meta_label.text = "[Q/Tab] Tools | [G] Crew"
	_tool_meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tool_meta_label.add_theme_font_size_override("font_size", 13)
	_tool_meta_label.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	vbox.add_child(_tool_meta_label)


func _make_keycap_badge(node_name: String, key_txt: String, action_txt: String, highlight: bool) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.name = node_name
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := Color(0.95, 0.89, 0.74, 0.94) if highlight else Color(0.91, 0.84, 0.69, 0.90)
	var border := HudIcons.COL_BRASS if highlight else HudIcons.COL_INK_SOFT
	var sb := HudIcons.make_parchment_box(bg, border, 2, 5, 6, 3)
	sb.shadow_size = 3
	badge.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(row)

	var cap := PanelContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap_sb := StyleBoxFlat.new()
	cap_sb.bg_color = Color(0.22, 0.14, 0.08, 0.96)
	cap_sb.border_color = HudIcons.COL_GOLD if highlight else HudIcons.COL_BRASS
	cap_sb.set_border_width_all(1)
	cap_sb.set_corner_radius_all(3)
	cap_sb.content_margin_left = 5
	cap_sb.content_margin_right = 5
	cap_sb.content_margin_top = 1
	cap_sb.content_margin_bottom = 1
	cap.add_theme_stylebox_override("panel", cap_sb)
	row.add_child(cap)

	var key_lbl := Label.new()
	key_lbl.text = _to_ascii(key_txt)
	key_lbl.add_theme_font_size_override("font_size", 12)
	key_lbl.add_theme_color_override("font_color", Color(0.98, 0.87, 0.48, 1.0) if highlight else Color(0.94, 0.86, 0.68, 1.0))
	key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_child(key_lbl)

	var act_lbl := Label.new()
	act_lbl.text = _to_ascii(action_txt)
	act_lbl.add_theme_font_size_override("font_size", 12)
	act_lbl.add_theme_color_override("font_color", HudIcons.COL_INK)
	act_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(act_lbl)
	return badge


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
	book.custom_minimum_size = Vector2(640.0, 0.0)
	book.add_theme_stylebox_override("panel",
		HudIcons.make_parchment_box(Color(0.93, 0.86, 0.72, 0.98), HudIcons.COL_INK, 3, 10, 24, 12))
	center.add_child(book)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 6)
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

	var title_btn := Button.new()
	title_btn.name = "ReturnToTitleButton"
	title_btn.text = "Main Menu"
	title_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_btn.pressed.connect(func() -> void:
		Audio.play_sfx(&"ui_select", Vector3.INF, -2.5)
		set_pause_open(false)
		return_to_title_requested.emit()
	)
	top_row.add_child(title_btn)

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
	controls_box.add_theme_constant_override("separation", 3)
	root_v.add_child(controls_box)

	var ctrl_groups: Array[String] = [
		"\n".join(PackedStringArray([
			CAPTAIN_CONTROLS_LINES[0],
			CAPTAIN_CONTROLS_LINES[2],
			CAPTAIN_CONTROLS_LINES[3],
		])),
		"\n".join(PackedStringArray([
			CAPTAIN_CONTROLS_LINES[1],
			CAPTAIN_CONTROLS_LINES[4],
			CAPTAIN_CONTROLS_LINES[5],
		])),
	]
	for gi in ctrl_groups.size():
		var ctrl_lbl := Label.new()
		ctrl_lbl.name = "ControlsGroup_%d" % gi
		ctrl_lbl.text = _to_ascii(ctrl_groups[gi])
		ctrl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ctrl_lbl.add_theme_font_size_override("font_size", 12)
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
	if not input_enabled or not _hud_visible:
		return
	var vp := get_viewport()
	if event.is_action_pressed(&"pause"):
		if item_radial != null and item_radial.is_open:
			close_item_radial(false)
		elif command_wheel != null and command_wheel.is_open:
			close_command_wheel(false)
		else:
			toggle_pause()
		if vp != null:
			vp.set_input_as_handled()
		return

	if pause_open:
		return

	if event.is_action_pressed(&"item_radial", false):
		if item_radial != null and item_radial.is_open:
			close_item_radial(true)
		else:
			open_item_radial()
		if vp != null:
			vp.set_input_as_handled()
	elif event.is_action_released(&"item_radial"):
		if item_radial != null and item_radial.is_open:
			var held_s := Time.get_ticks_msec() * 0.001 - _radial_open_time
			var moved := item_radial.hovered_index != _radial_initial_hover
			if held_s >= RADIAL_HOLD_THRESHOLD_S or moved:
				close_item_radial(true)
			if vp != null:
				vp.set_input_as_handled()
	elif event.is_action_pressed(&"command_wheel", false):
		if command_wheel != null and command_wheel.is_open:
			close_command_wheel(true)
		else:
			open_command_wheel()
		if vp != null:
			vp.set_input_as_handled()
	elif event.is_action_released(&"command_wheel"):
		if command_wheel != null and command_wheel.is_open:
			var held_s := Time.get_ticks_msec() * 0.001 - _radial_open_time
			var moved := command_wheel.hovered_index != _radial_initial_hover
			if held_s >= RADIAL_HOLD_THRESHOLD_S or moved:
				close_command_wheel(true)
			if vp != null:
				vp.set_input_as_handled()


func _process(delta: float) -> void:
	_tick_banner(delta)
	_tick_boss_bar(delta)
	_tick_voyage_title(delta)
	_tick_vitals(delta)
	_sync_damage_vignette(delta)
	_tick_directional_damage(delta)
	_tick_context_prompt(delta)
	_tick_sailing_telemetry()
	_tick_tool_chip(delta)
	_tick_whisper(delta)
	_tick_crosshair(delta)
	_sync_top_left_visibility()
	_tick_crew_roster(delta)


func _tick_crew_roster(delta: float) -> void:
	_crew_roster_accum += maxf(delta, 0.0)
	if _crew_roster_accum < CREW_ROSTER_REFRESH_INTERVAL:
		return
	_crew_roster_accum = 0.0
	_refresh_crew_roster()


func _refresh_crew_roster() -> void:
	if _crew_roster_panel == null or _crew_roster_rows_box == null:
		return
	var live_reg: Array[CrewBrain] = []
	for rb in _crew_brains:
		if rb != null and is_instance_valid(rb):
			live_reg.append(rb)
	_crew_brains = live_reg

	var brains := get_crew_brains()
	_crew_roster_entries.clear()
	if _crew_roster_count_label != null:
		_crew_roster_count_label.text = "%d" % brains.size()

	while _crew_roster_rows.size() > brains.size():
		var popped: Dictionary = _crew_roster_rows.pop_back()
		var rnode := popped.get("row") as Control
		if rnode != null and is_instance_valid(rnode):
			if rnode.get_parent() != null:
				rnode.get_parent().remove_child(rnode)
			rnode.queue_free()

	for idx in brains.size():
		var b := brains[idx]
		var raw_name := b.crew_name() if b.has_method(&"crew_name") else String(b.persona_id).capitalize()
		var short_name := _to_ascii(raw_name.strip_edges())
		var sp := short_name.find(" ")
		if sp > 0:
			short_name = short_name.substr(0, sp)
		if short_name == "":
			short_name = "Crew"

		var task_id: StringName = b.current_task
		var badge := _crew_task_badge(task_id)
		var task_label: String = String(badge["label"])
		var badge_col: Color = badge["color"] as Color

		var hp_ratio := 1.0
		if b.pawn != null and is_instance_valid(b.pawn):
			if b.pawn.dead or b.pawn.max_health <= 0.0:
				hp_ratio = 0.0
			else:
				hp_ratio = clampf(b.pawn.health / b.pawn.max_health, 0.0, 1.0)
		var hp_col := Color(0.18, 0.68, 0.34, 1.0) if hp_ratio >= 0.60 else (
			Color(0.86, 0.66, 0.16, 1.0) if hp_ratio >= 0.30 else Color(0.82, 0.18, 0.16, 1.0)
		)

		_crew_roster_entries.append({
			"name": short_name,
			"task": task_id,
			"task_label": task_label,
			"hp_ratio": hp_ratio,
			"order": b.current_order,
		})

		var row_rec := _ensure_crew_roster_row(idx)
		var name_lbl := row_rec["name_lbl"] as Label
		var badge_lbl := row_rec["badge_lbl"] as Label
		var badge_style := row_rec["badge_style"] as StyleBoxFlat
		var hp_bar := row_rec["hp_bar"] as ProgressBar
		var hp_fill := row_rec["hp_fill"] as StyleBoxFlat
		name_lbl.text = short_name
		badge_lbl.text = task_label
		badge_style.bg_color = badge_col
		hp_bar.value = hp_ratio
		hp_fill.bg_color = hp_col

	_crew_roster_panel.visible = _hud_visible and not pause_open and not brains.is_empty()


func _ensure_crew_roster_row(idx: int) -> Dictionary:
	if idx < _crew_roster_rows.size():
		return _crew_roster_rows[idx]

	var row := HBoxContainer.new()
	row.name = "CrewRow_%d" % idx
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crew_roster_rows_box.add_child(row)

	var name_lbl := Label.new()
	name_lbl.name = "CrewName"
	name_lbl.text = "Crew"
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", HudIcons.COL_INK)
	row.add_child(name_lbl)

	var badge_panel := PanelContainer.new()
	badge_panel.name = "CrewTaskBadge"
	badge_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(0.36, 0.30, 0.22, 1.0)
	badge_style.set_corner_radius_all(3)
	badge_style.content_margin_left = 5
	badge_style.content_margin_right = 5
	badge_style.content_margin_top = 1
	badge_style.content_margin_bottom = 1
	badge_panel.add_theme_stylebox_override("panel", badge_style)
	row.add_child(badge_panel)

	var badge_lbl := Label.new()
	badge_lbl.name = "CrewTaskLabel"
	badge_lbl.text = "READY"
	badge_lbl.custom_minimum_size = Vector2(54.0, 0.0)
	badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_lbl.add_theme_font_size_override("font_size", 11)
	badge_lbl.add_theme_color_override("font_color", Color(0.98, 0.95, 0.88, 1.0))
	badge_panel.add_child(badge_lbl)

	var hp_bar := ProgressBar.new()
	hp_bar.name = "CrewHpBar"
	hp_bar.custom_minimum_size = Vector2(52.0, 7.0)
	hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_bar.min_value = 0.0
	hp_bar.max_value = 1.0
	hp_bar.step = 0.01
	hp_bar.value = 1.0
	hp_bar.show_percentage = false
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = Color(0.24, 0.17, 0.11, 0.88)
	hp_bg.border_color = HudIcons.COL_INK
	hp_bg.set_border_width_all(1)
	hp_bg.set_corner_radius_all(2)
	hp_bar.add_theme_stylebox_override("background", hp_bg)

	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.18, 0.68, 0.34, 1.0)
	hp_fill.set_corner_radius_all(2)
	hp_bar.add_theme_stylebox_override("fill", hp_fill)
	row.add_child(hp_bar)

	var rec := {
		"row": row,
		"name_lbl": name_lbl,
		"badge_lbl": badge_lbl,
		"badge_style": badge_style,
		"hp_bar": hp_bar,
		"hp_fill": hp_fill,
	}
	_crew_roster_rows.append(rec)
	return rec


static func _crew_task_badge(task: StringName) -> Dictionary:
	match task:
		&"helm":
			return {"label": "HELM", "color": Color(0.14, 0.44, 0.62, 1.0)}
		&"trim", &"sails", &"sail_length", &"sail_angle", &"trim_sails", &"set_sails":
			return {"label": "SAILS", "color": Color(0.18, 0.50, 0.46, 1.0)}
		&"anchor", &"anchor_drop", &"anchor_raise":
			return {"label": "ANCHOR", "color": Color(0.46, 0.36, 0.24, 1.0)}
		&"cannon", &"cannons":
			return {"label": "GUNNER", "color": Color(0.76, 0.16, 0.14, 1.0)}
		&"repair", &"patch", &"patch_hole", &"mend_rigging":
			return {"label": "REPAIR", "color": Color(0.72, 0.42, 0.08, 1.0)}
		&"bail":
			return {"label": "BAIL", "color": Color(0.16, 0.48, 0.68, 1.0)}
		&"fire", &"extinguish", &"douse_fire":
			return {"label": "FIRE", "color": Color(0.86, 0.28, 0.08, 1.0)}
		&"fetch", &"fetch_treasure", &"haul":
			return {"label": "HAUL", "color": Color(0.66, 0.46, 0.08, 1.0)}
		&"follow", &"escort", &"combat":
			return {"label": "ESCORT", "color": Color(0.56, 0.20, 0.48, 1.0)}
		&"board_ladder", &"return_ship":
			return {"label": "BOARD", "color": Color(0.24, 0.46, 0.58, 1.0)}
		&"shanty":
			return {"label": "SHANTY", "color": Color(0.52, 0.30, 0.64, 1.0)}
		_:
			return {"label": "READY", "color": Color(0.36, 0.30, 0.22, 1.0)}


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
		_sailing_full_wind_active = false
		_sailing_pill_panel.visible = false
		return

	var kts := maxf(0.0, ship.speed_knots())
	var rudder_txt := format_rudder_bar(ship.helm)
	var sail_pct := clampi(int(roundf(ship.sail_set * 100.0)), 0, 100)
	var efficiency := ship.wind_catch()
	var full_billow := not ship.anchor_down and ship.sail_set >= 0.25 and efficiency >= 0.88
	var state_txt := "TRIM SAILS"
	var ink_col := HudIcons.COL_INK_SOFT
	if ship.anchor_down:
		state_txt = "ANCHORED"
	elif ship.sail_set < 0.08:
		state_txt = "SAILS FURLED"
	else:
		var err := absf(angle_difference(ship.sail_trim, ship.ideal_sail_trim()))
		if full_billow or err <= 0.24:
			state_txt = "FULL WIND"
			ink_col = Color(0.58, 0.34, 0.02) if full_billow else Color(0.68, 0.36, 0.04)
		elif err <= 0.65:
			state_txt = "GOOD TRIM"
			ink_col = HudIcons.COL_INK
		else:
			state_txt = "TRIM SAILS"
			ink_col = HudIcons.COL_INK_SOFT

	_sailing_full_wind_active = full_billow
	if _sailing_pill_style != null:
		if full_billow:
			_sailing_pill_style.border_color = HudIcons.COL_GOLD
			_sailing_pill_style.bg_color = Color(0.97, 0.91, 0.72, 0.95)
			_sailing_pill_style.set_border_width_all(3)
		else:
			_sailing_pill_style.border_color = HudIcons.COL_INK_SOFT
			_sailing_pill_style.bg_color = Color(0.92, 0.85, 0.70, 0.90)
			_sailing_pill_style.set_border_width_all(2)

	_sailing_pill_label.text = _to_ascii("%s  |  Sail %d%%  |  %.1f kt  |  %s" % [rudder_txt, sail_pct, kts, state_txt])
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
	_stamina_flash_timer = maxf(0.0, _stamina_flash_timer - maxf(delta, 0.0))
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

	if hp_ratio < 0.99 or stam_ratio < 0.99 or in_combat or _stamina_flash_timer > 0.0 or force_show_vitals:
		_vitals_show_timer = maxf(_vitals_show_timer, 3.0)
	else:
		_vitals_show_timer = maxf(0.0, _vitals_show_timer - delta)

	var want_a := 0.92 if (_vitals_show_timer > 0.0 or force_show_vitals) else 0.0
	_vitals_alpha = move_toward(_vitals_alpha, want_a, delta * (5.5 if want_a > _vitals_alpha else 1.6))
	if _vitals_view != null:
		var stam_flash := clampf(_stamina_flash_timer / STAMINA_FLASH_DURATION, 0.0, 1.0)
		_vitals_view.set_values(hp_ratio, stam_ratio, _vitals_alpha, stam_flash)


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
	var spy_hide := inventory != null and inventory.spyglass_zoom > 0.4
	if _tool_panel != null:
		var urgent := _tool_flash_timer > 0.0 or _hull_alert_active
		var target_a := 0.0 if (spy_hide or pause_open) else (0.96 if urgent else 0.78)
		_tool_panel.modulate.a = move_toward(_tool_panel.modulate.a, target_a, delta * 5.0)
		_tool_panel.visible = _tool_panel.modulate.a > 0.02
	if _keycap_strip != null:
		var strip_target_a := 0.0 if (spy_hide or pause_open or is_any_overlay_open()) else 0.92
		_keycap_strip.modulate.a = move_toward(_keycap_strip.modulate.a, strip_target_a, delta * 6.0)
		_keycap_strip.visible = _keycap_strip.modulate.a > 0.02


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
	var meta := "[Q/Tab] Tools | [G] Crew"
	var active_ship := _active_ship()
	var on_cannon := false
	var ord_kind: StringName = &"iron"
	var ord_lbl := "Iron"

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
				if active_ship != null and active_ship.sail_damage_timer > 0.0:
					meta = "Rigging Damaged (%ds) | [Hold W] Mend Rigging | [F] Leave" % maxi(1, ceili(active_ship.sail_damage_timer))
				elif active_ship != null:
					meta = "[S] Lower / [W] Raise (%d%%) | [F] Leave" % int(roundf(active_ship.sail_set * 100.0))
				else:
					meta = "[S] Lower / [W] Raise | [F] Leave"
			&"sail_angle":
				title = "Sail Braces"
				meta = "[A/D] Angle | [RMB] Square | [F] Leave"
			&"cannon":
				on_cannon = true
				title = "Ship Cannon"
				if active_ship != null:
					ord_kind = active_ship.cannon_ordnance
					ord_lbl = active_ship.get_cannon_ordnance_label()
					meta = "Shot: %s (%d) | [WASD/Mouse] Aim | [LMB] Fire | [R] Swap Shot" % [ord_lbl, active_ship.cannonballs_remaining]
				else:
					meta = "[WASD/Mouse] Aim | [LMB] Fire (Iron) | [R] Swap Shot"
			&"harpoon":
				title = "Bow Harpoon"
				meta = "[Mouse/WASD] Aim | [LMB] Fire | [Hold RMB] Reel | [R] Release | [F] Leave"
			&"rowboat_oars":
				title = "Rowboat Oars"
				meta = "[A/D] Stroke Port/Stbd | [W] Surge | [S] Brake | [F] Stand"
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
				var pin_summary := inventory.get_compass_pin_summary()
				if pin_summary != "":
					var mode_tag := "Compass [Pin]" if inventory.compass_pin_mode else "Compass"
					var lmb_hint := "[LMB] True North" if inventory.compass_pin_mode else "[LMB] Track Pin"
					if inventory.is_compass_pacing():
						meta = "%s | %s | Pace %d %s | %s" % [
							mode_tag, pin_summary, inventory.get_compass_paces(),
							inventory.get_compass_heading_label(), lmb_hint,
						]
					else:
						meta = "%s | %s | %s | [RMB] Pace" % [mode_tag, pin_summary, lmb_hint]
				elif inventory.is_compass_pacing():
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

	# Update live cannon ordnance color-accented badge (strict ASCII across all 6 ordnance types).
	var accent_col := get_ordnance_accent_color(ord_kind)
	_active_ordnance_accent = accent_col
	if _ordnance_pill != null:
		_ordnance_pill.visible = on_cannon
		if on_cannon:
			if _ordnance_pill_style != null:
				_ordnance_pill_style.border_color = accent_col
			if _ordnance_swatch != null:
				_ordnance_swatch.color = accent_col
			if _ordnance_label != null:
				_ordnance_label.text = _to_ascii(ord_lbl)
				_ordnance_label.add_theme_color_override("font_color", accent_col)
	if _tool_panel_style != null:
		_tool_panel_style.border_color = accent_col if on_cannon else HudIcons.COL_INK_SOFT

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
		var g := maxi(0, int(Game.profile.data.get("gold", 0)))
		if _last_gold < 0:
			_last_gold = g
			if not _gold_initialized:
				_target_gold = g
				_displayed_gold = g
				_gold_roll_start = g
		elif g != _last_gold:
			_last_gold = g
			if not _gold_initialized:
				_gold_initialized = true
			set_gold(g)
			_whisper_timer = maxf(_whisper_timer, 5.5)

	step_gold_animation(delta)

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
	_update_gold_label_text()
	var v_title := _custom_voyage_title
	var v_obj := _custom_voyage_obj
	if voyage_manager != null and is_instance_valid(voyage_manager) and voyage_manager.has_active_voyage():
		v_title = String(voyage_manager.active_voyage.get("title", "Active Voyage"))
		v_obj = voyage_manager.get_current_objective()
	_voyage_title_label.text = _to_ascii(v_title)
	_voyage_title_label.visible = v_title != ""
	_voyage_obj_label.text = _to_ascii(v_obj)
	_voyage_obj_label.visible = v_obj != ""
	_sync_emissary_label()


func _sync_emissary_label() -> void:
	if _emissary_label == null:
		return
	_emissary_label.text = emissary_badge_text
	_emissary_label.visible = emissary_badge_text != ""


func _tick_directional_damage(delta: float) -> void:
	if _directional_damage_view == null:
		return
	var spy := inventory.spyglass_zoom if inventory != null else 0.0
	var hidden := pause_open or spy > 0.35
	_directional_damage_view.tick(delta, compute_relative_bearing, _is_colorblind_mode(), hidden)


func _tick_crosshair(delta: float) -> void:
	if _crosshair_view == null:
		return
	var spy := inventory.spyglass_zoom if inventory != null else 0.0
	var hide_dot := is_any_overlay_open() or spy > 0.25
	var want := 0.0 if hide_dot else 0.78
	var prev_a := _crosshair_view.alpha
	_crosshair_view.alpha = move_toward(_crosshair_view.alpha, want, delta * 10.0)
	var fx_dirty := _crosshair_view.tick_effects(delta)
	_parry_flash_timer = _crosshair_view.parry_timer
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
	item_radial.configure("Tools & Gear", slices, "", RadialWheel.DEFAULT_ITEM_FOOTER)


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


func _on_ship_cursed_hit(_curse_kind: StringName, _duration: float) -> void:
	_tool_flash_timer = 3.5
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


func _on_pawn_damaged(amount: float, from: Node) -> void:
	_vitals_show_timer = 4.5
	if amount > 0.5:
		_damage_flash = clampf(_damage_flash + clampf(amount / 35.0, 0.35, 0.9), 0.0, 1.0)
		if pawn != null and is_instance_valid(pawn):
			_last_hp = pawn.health
		_sync_damage_vignette(0.0)
		# Fallback when no CombatComponent is bound; when combat is bound, combat.damage_received drives arcs once.
		if (combat == null or not is_instance_valid(combat)) and from != null and is_instance_valid(from):
			if from is Node3D:
				register_directional_damage((from as Node3D).global_position, clampf(amount / 25.0, 0.45, 1.0))
			elif from.get_parent() is Node3D:
				register_directional_damage((from.get_parent() as Node3D).global_position, clampf(amount / 25.0, 0.45, 1.0))


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


func _on_combat_damage_received(amount: float, attacker_pos: Vector3) -> void:
	if amount > 0.5 and attacker_pos.is_finite():
		register_directional_damage(attacker_pos, clampf(amount / 25.0, 0.45, 1.0))


func _on_combat_stamina_depleted(_cost: float) -> void:
	flash_stamina_depleted()


func _on_voyage_started(_voyage: Dictionary) -> void:
	_whisper_timer = 6.5


func _on_voyage_stage_changed(_stage: int, _obj: String) -> void:
	_whisper_timer = 6.0


func _on_emissary_grade_changed(company_id: StringName, new_grade: int, multiplier: float) -> void:
	set_emissary_status(company_id, new_grade, multiplier)


func _on_emissary_flag_lowered(_company_id: StringName, _final_grade: int, _bonus_gold: int, _bonus_renown: int) -> void:
	set_emissary_status(&"", 0, 1.0)


func _on_emissary_flag_broken(_company_id: StringName, _lost_grade: int) -> void:
	set_emissary_status(&"", 0, 1.0)


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


class DirectionalDamageOverlay extends Control:
	const ARC_RADIUS := 92.0
	const ARC_DURATION := 0.90
	const MAX_ARCS := 8
	const ARC_SEGMENTS := 12

	var _arcs: Array[Dictionary] = []
	var _colorblind: bool = false

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func add_arc(source_pos: Vector3, bearing: float, intensity: float, colorblind: bool = false) -> void:
		_colorblind = colorblind
		for arc in _arcs:
			if absf(angle_difference(float(arc["bearing"]), bearing)) < 0.24:
				arc["source_pos"] = source_pos
				arc["bearing"] = bearing
				arc["remaining"] = ARC_DURATION
				arc["intensity"] = maxf(float(arc["intensity"]), intensity)
				visible = true
				queue_redraw()
				return
		if _arcs.size() >= MAX_ARCS:
			_arcs.remove_at(0)
		_arcs.append({
			"source_pos": source_pos,
			"bearing": bearing,
			"remaining": ARC_DURATION,
			"intensity": intensity,
		})
		visible = true
		queue_redraw()

	func clear_arcs() -> void:
		_arcs.clear()
		visible = false

	func get_arc_count() -> int:
		return _arcs.size()

	func get_arcs_snapshot() -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for arc in _arcs:
			out.append({
				"bearing": float(arc["bearing"]),
				"remaining": float(arc["remaining"]),
				"intensity": float(arc["intensity"]),
				"source_pos": arc["source_pos"] as Vector3,
			})
		return out

	func tick(delta: float, bearing_fn: Callable, colorblind: bool, is_suppressed: bool) -> void:
		_colorblind = colorblind
		if _arcs.is_empty():
			visible = false
			return
		var dt := maxf(delta, 0.0)
		for i in range(_arcs.size() - 1, -1, -1):
			var arc: Dictionary = _arcs[i]
			var rem := float(arc["remaining"]) - dt
			if rem <= 0.0:
				_arcs.remove_at(i)
				continue
			arc["remaining"] = rem
			if bearing_fn.is_valid():
				var updated: Variant = bearing_fn.call(arc["source_pos"])
				if updated is float and not is_nan(updated as float):
					arc["bearing"] = updated as float
		visible = not is_suppressed and not _arcs.is_empty()
		if visible:
			queue_redraw()

	func _draw() -> void:
		if _arcs.is_empty():
			return
		var view_sz := size if (size.is_finite() and size.length_squared() >= 1.0) else get_viewport_rect().size
		if not view_sz.is_finite() or view_sz.x < 4.0 or view_sz.y < 4.0:
			return
		var c := view_sz * 0.5
		for arc in _arcs:
			var t := clampf(float(arc["remaining"]) / ARC_DURATION, 0.0, 1.0)
			var inten := clampf(float(arc["intensity"]), 0.25, 1.0)
			var fade := smoothstep(0.0, 0.72, t)
			var r := ARC_RADIUS + pow(t, 3.0) * 7.0
			var screen_ang := float(arc["bearing"]) - PI * 0.5
			var half_span := lerpf(0.24, 0.36, inten)
			var peak_half_w := lerpf(3.4, 5.2, inten)

			var ink_col := Color(0.14, 0.07, 0.04, 0.84 * fade)
			var fill_col := Color(0.92, 0.48, 0.08, 0.94 * fade) if _colorblind else Color(0.84, 0.13, 0.10, 0.94 * fade)
			var glint_col := Color(0.98, 0.86, 0.50, 0.78 * fade)

			# Tapered curved parchment-ink directional threat ribbon.
			for s in ARC_SEGMENTS:
				var u0 := float(s) / float(ARC_SEGMENTS)
				var u1 := float(s + 1) / float(ARC_SEGMENTS)
				var a0 := lerpf(screen_ang - half_span, screen_ang + half_span, u0)
				var a1 := lerpf(screen_ang - half_span, screen_ang + half_span, u1)
				var w0 := 0.8 + peak_half_w * pow(sin(u0 * PI), 0.75)
				var w1 := 0.8 + peak_half_w * pow(sin(u1 * PI), 0.75)
				var d0 := Vector2(cos(a0), sin(a0))
				var d1 := Vector2(cos(a1), sin(a1))
				var border_quad := PackedVector2Array([
					c + d0 * (r - w0 - 1.5),
					c + d0 * (r + w0 + 1.5),
					c + d1 * (r + w1 + 1.5),
					c + d1 * (r - w1 - 1.5),
				])
				draw_colored_polygon(border_quad, ink_col)
				var fill_quad := PackedVector2Array([
					c + d0 * (r - w0),
					c + d0 * (r + w0),
					c + d1 * (r + w1),
					c + d1 * (r - w1),
				])
				draw_colored_polygon(fill_quad, fill_col)

			# Crisp outward-pointing directional crimson chevron beak with gold ink accent.
			var dir := Vector2(cos(screen_ang), sin(screen_ang))
			var perp := Vector2(-dir.y, dir.x)
			var beak_outer := PackedVector2Array([
				c + dir * (r + 14.5),
				c + dir * (r + 1.0) + perp * 10.5,
				c + dir * (r - 3.0),
				c + dir * (r + 1.0) - perp * 10.5,
			])
			draw_colored_polygon(beak_outer, ink_col)
			var beak_inner := PackedVector2Array([
				c + dir * (r + 12.2),
				c + dir * (r + 1.8) + perp * 8.2,
				c + dir * (r - 1.4),
				c + dir * (r + 1.8) - perp * 8.2,
			])
			draw_colored_polygon(beak_inner, fill_col)
			draw_line(c + dir * (r + 10.0), c + dir * (r + 2.8) + perp * 5.2, glint_col, 1.4, true)
			draw_line(c + dir * (r + 10.0), c + dir * (r + 2.8) - perp * 5.2, glint_col, 1.4, true)


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

		# 3. Crisp expanding golden ring flash & twin opposing burnished-gold brass guard-arcs on timed parry.
		if parry_timer > 0.001:
			var pt := clampf(parry_timer / PARRY_DURATION, 0.0, 1.0)
			var pfade := smoothstep(0.0, 0.38, pt) * vis_scale
			var ring_expand := 1.0 - pt * pt
			var ring_r := lerpf(12.0, 32.0, ring_expand)
			var ring_fade := smoothstep(0.0, 0.55, pt) * vis_scale
			draw_arc(c, ring_r, 0.0, TAU, 36, Color(0.18, 0.11, 0.05, 0.52 * ring_fade), 4.6, true)
			draw_arc(c, ring_r, 0.0, TAU, 36, Color(0.96, 0.80, 0.30, 0.90 * ring_fade), 2.4, true)
			draw_arc(c, ring_r - 0.8, 0.0, TAU, 36, Color(1.0, 0.96, 0.80, 0.82 * ring_fade), 1.1, true)

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
	var _stamina_flash: float = 0.0

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

	func set_values(hp: float, stamina: float, alpha: float, stamina_flash: float = 0.0) -> void:
		var clamped_flash := clampf(stamina_flash, 0.0, 1.0)
		var changed := absf(hp - _hp) > 0.002 or absf(stamina - _stamina) > 0.002 \
			or absf(alpha - _alpha) > 0.004 or absf(clamped_flash - _stamina_flash) > 0.005
		_hp = hp
		_stamina = stamina
		_alpha = alpha
		_stamina_flash = clamped_flash
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
		var st_track := track
		var st_border := border
		var st_border_w := 1.1
		if _stamina_flash > 0.01:
			var pulse := 0.5 + 0.5 * sin(_stamina_flash * PI * 4.0)
			var warn_col := Color(0.92, 0.22, 0.12).lerp(Color(0.98, 0.76, 0.20), pulse)
			var blend := clampf(_stamina_flash * 0.92, 0.0, 1.0)
			st_col = st_col.lerp(Color(warn_col.r, warn_col.g, warn_col.b, 0.98 * _alpha), blend)
			st_track = track.lerp(Color(warn_col.r, warn_col.g, warn_col.b, 0.45 * _alpha), blend)
			st_border = border.lerp(Color(warn_col.r, warn_col.g, warn_col.b, 0.98 * _alpha), blend)
			st_border_w = lerpf(1.1, 2.1, blend)

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

		# Slender 5-segment ochre stamina bar below (pulses gold/red on stamina depletion).
		for i in pips:
			var x := pad_x + float(i) * (pip_w + gap)
			var r_st := Rect2(x, 35.0, pip_w, 9.0)
			draw_rect(r_st, st_track, true)
			var fill_st := clampf(_stamina * float(pips) - float(i), 0.0, 1.0)
			if fill_st > 0.01:
				draw_rect(Rect2(x, 35.0, pip_w * fill_st, 9.0), st_col, true)
			draw_rect(r_st, st_border, false, st_border_w)


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
