class_name GameHUD
extends CanvasLayer
## Minimal, diegetic parchment-and-ink HUD for Sea of Scoundrels.
##
## Faithful to docs/DESIGN.md: no minimap and no arcade clutter. Provides:
## - Subtle center crosshair dot (fades during spyglass or overlays)
## - Faint health & stamina pips (fade out cleanly when full & out of combat)
## - Contextual interaction prompt ribbon driven by `PlayerController.focus_prompt`
## - Subtle active tool / ammo / ship supplies chip
## - Queued top-center Crew Callout & Notice parchment banner (`Game.notice`)
## - Quiet top-right Gold & Voyage Objective whisper slip
## - Circular brass Spyglass vignette + horizon sighting readout
## - 11-wedge Item Radial (`Tab`) and 9-wedge Crew Command Wheel (`Q`)
## - Pause / Save / Quality Presets / Audio Sliders / LAN Co-op overlay (`Escape`)

signal crew_order_issued(order: StringName)
signal pause_changed(open: bool)
signal quality_changed(target: StringName, level: int)

const ITEM_SLICE_HINTS := {
	&"cutlass": "Light combo · Hold heavy · RMB parry",
	&"pistol": "Flintlock shot · RMB aim",
	&"compass": "Points true North · RMB raise",
	&"spyglass": "RMB zoom & sight horizon",
	&"lantern": "LMB toggle flame · RMB raise",
	&"map": "Treasure chart · RMB read",
	&"shovel": "Dig buried treasure mounds",
	&"bucket": "Bail bilge water · Splash out",
	&"planks": "Patch open hull breaches",
	&"tankard": "Drink grog (+15 HP)",
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

var item_radial: RadialWheel = null
var command_wheel: RadialWheel = null
var pause_overlay: Control = null
var pause_open: bool = false
var crew_hold_fire: bool = false

var _crew_brains: Array[CrewBrain] = []
var _root: Control = null
var _theme: Theme = null
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

# Context prompt (bottom-center)
var _prompt_panel: PanelContainer = null
var _prompt_label: Label = null
var _prompt_alpha: float = 0.0

# Active tool / supplies chip (bottom-right)
var _tool_panel: PanelContainer = null
var _tool_title_label: Label = null
var _tool_meta_label: Label = null
var _tool_flash_timer: float = 0.0

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

# Vitals fade tracking
var _vitals_show_timer: float = 0.0
var _vitals_alpha: float = 0.0
var _last_hp: float = -1.0
var _last_stamina: float = -1.0

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

	_connect_signals()
	_refresh_item_radial_entries()
	_refresh_tool_chip()
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
	if pawn != null and not pawn.damaged.is_connected(_on_pawn_damaged):
		pawn.damaged.connect(_on_pawn_damaged)
	if voyage_manager != null:
		if not voyage_manager.voyage_started.is_connected(_on_voyage_started):
			voyage_manager.voyage_started.connect(_on_voyage_started)
		if not voyage_manager.voyage_stage_changed.is_connected(_on_voyage_stage_changed):
			voyage_manager.voyage_stage_changed.connect(_on_voyage_stage_changed)


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
	if pawn != null and is_instance_valid(pawn):
		if pawn.damaged.is_connected(_on_pawn_damaged):
			pawn.damaged.disconnect(_on_pawn_damaged)
	if voyage_manager != null and is_instance_valid(voyage_manager):
		if voyage_manager.voyage_started.is_connected(_on_voyage_started):
			voyage_manager.voyage_started.disconnect(_on_voyage_started)
		if voyage_manager.voyage_stage_changed.is_connected(_on_voyage_stage_changed):
			voyage_manager.voyage_stage_changed.disconnect(_on_voyage_stage_changed)


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
	var clean := text.strip_edges()
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
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _theme
	add_child(_root)

	# 1. Spyglass circular brass aperture vignette (behind center HUD elements).
	_spyglass_view = _SpyglassOverlay.new()
	_spyglass_view.name = "SpyglassOverlay"
	_root.add_child(_spyglass_view)

	# 2. Subtle center crosshair dot.
	_crosshair_view = _CrosshairView.new()
	_crosshair_view.name = "Crosshair"
	_root.add_child(_crosshair_view)

	# 3. Top-center Crew Callout & Notice parchment scroll banner.
	_build_banner()

	# 4. Top-right Gold & Voyage Objective whisper card.
	_build_whisper_card()

	# 5. Bottom-left faint Health & Stamina parchment pips.
	_vitals_view = _VitalsView.new()
	_vitals_view.name = "VitalsPips"
	_root.add_child(_vitals_view)

	# 6. Bottom-center contextual interaction prompt ribbon.
	_build_context_prompt()

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
	holder.offset_top = 24.0
	holder.offset_bottom = 86.0
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(holder)

	_banner_panel = PanelContainer.new()
	_banner_panel.name = "NoticeBanner"
	_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_panel.add_theme_stylebox_override("panel",
		HudIcons.make_parchment_box(Color(0.93, 0.86, 0.71, 0.96), HudIcons.COL_INK, 2, 8, 24, 10))
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
	_banner_label.add_theme_font_size_override("font_size", 18)
	_banner_label.add_theme_color_override("font_color", HudIcons.COL_INK)
	hbox.add_child(_banner_label)

	var right_orn := Label.new()
	right_orn.text = "*"
	right_orn.add_theme_color_override("font_color", HudIcons.COL_CRIMSON)
	right_orn.add_theme_font_size_override("font_size", 18)
	hbox.add_child(right_orn)


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
	_tool_meta_label.text = "[Tab] Tools · [Q] Crew"
	_tool_meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tool_meta_label.add_theme_font_size_override("font_size", 13)
	_tool_meta_label.add_theme_color_override("font_color", HudIcons.COL_INK_SOFT)
	vbox.add_child(_tool_meta_label)


func _build_pause_overlay() -> void:
	pause_overlay = ColorRect.new()
	pause_overlay.name = "PauseOverlay"
	pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_overlay.color = Color(0.06, 0.04, 0.02, 0.52)
	pause_overlay.visible = false
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(pause_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_overlay.add_child(center)

	var book := PanelContainer.new()
	book.name = "CaptainLogPanel"
	book.custom_minimum_size = Vector2(540.0, 0.0)
	book.add_theme_stylebox_override("panel",
		HudIcons.make_parchment_box(Color(0.93, 0.86, 0.72, 0.98), HudIcons.COL_INK, 3, 10, 26, 20))
	center.add_child(book)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 12)
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


func _make_section_divider(heading: String) -> Label:
	var l := Label.new()
	l.text = "— %s —" % heading
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
	_tick_vitals(delta)
	_tick_context_prompt(delta)
	_tick_tool_chip(delta)
	_tick_whisper(delta)
	_tick_crosshair(delta)


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


func _tick_vitals(delta: float) -> void:
	var hp_ratio := 1.0
	var stam_ratio := 1.0
	var in_combat := false
	if pawn != null and is_instance_valid(pawn):
		hp_ratio = clampf(pawn.health / maxf(pawn.max_health, 1.0), 0.0, 1.0)
		if _last_hp >= 0.0 and absf(pawn.health - _last_hp) > 0.1:
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


func _tick_context_prompt(delta: float) -> void:
	var txt := ""
	if player_controller != null and is_instance_valid(player_controller) and not is_any_overlay_open():
		var raw := player_controller.focus_prompt.strip_edges()
		if raw != "":
			if raw.begins_with("["):
				txt = raw
			elif pawn != null and pawn.station != null:
				txt = "[X] %s" % raw
			else:
				txt = "[F] %s" % raw
	var want_a := 1.0 if txt != "" else 0.0
	_prompt_alpha = move_toward(_prompt_alpha, want_a, delta * 9.0)
	if _prompt_label != null and txt != "":
		_prompt_label.text = txt
	if _prompt_panel != null:
		_prompt_panel.modulate.a = _prompt_alpha
		_prompt_panel.visible = _prompt_alpha > 0.01


func _tick_tool_chip(delta: float) -> void:
	_tool_flash_timer = maxf(0.0, _tool_flash_timer - delta)
	_refresh_tool_chip()
	if _tool_panel != null:
		var spy_hide := inventory != null and inventory.spyglass_zoom > 0.4
		var target_a := 0.0 if (spy_hide or pause_open) else (0.96 if _tool_flash_timer > 0.0 else 0.76)
		_tool_panel.modulate.a = move_toward(_tool_panel.modulate.a, target_a, delta * 5.0)
		_tool_panel.visible = _tool_panel.modulate.a > 0.02


func _refresh_tool_chip() -> void:
	if _tool_title_label == null or _tool_meta_label == null:
		return
	var item_id := inventory.active_item if inventory != null else &"cutlass"
	var title := ToolMeshes.get_display_name(item_id)
	var meta := "[Tab] Tools · [Q] Crew"

	if pawn != null and pawn.station != null:
		var sk := StringName(pawn.station.get(&"kind"))
		if sk == &"cannon" and ship != null:
			title = "Ship Cannon"
			meta = "Shot: %d · [LMB] Fire" % ship.cannonballs_remaining
		elif sk == &"helm":
			title = "Ship's Wheel"
			meta = "A/D Steer · RMB Center"
		elif sk == &"map_table":
			title = "Map Table"
			meta = "WASD Pan · LMB/RMB Zoom"
	elif inventory != null:
		match item_id:
			&"pistol":
				if combat != null:
					meta = "Ammo: %d / 6 · [RMB] Aim" % combat.ammo
			&"lantern":
				meta = "Lit · [LMB] Snuff" if inventory.lantern_lit else "Unlit · [LMB] Light"
			&"bucket":
				meta = "Full · [LMB] Splash" if inventory.bucket_full else "Empty · [LMB] Bail"
			&"planks":
				var active_ship := _active_ship()
				if active_ship != null:
					meta = "Planks: %d · [LMB] Patch" % active_ship.planks_remaining
				else:
					meta = "[LMB] Patch breach"
			&"instrument":
				meta = "Playing Shanty · [LMB] Stop" if inventory.playing_shanty else "[LMB] Play Shanty"
			&"map":
				meta = "%s · [RMB] Read" % inventory.map_island_name
			&"compass":
				meta = "True North · [RMB] Raise"
			&"spyglass":
				meta = "[RMB] Peer Through"

	_tool_title_label.text = title
	_tool_meta_label.text = meta


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
	_voyage_title_label.text = v_title
	_voyage_title_label.visible = v_title != ""
	_voyage_obj_label.text = v_obj
	_voyage_obj_label.visible = v_obj != ""


func _tick_crosshair(delta: float) -> void:
	if _crosshair_view == null:
		return
	var spy := inventory.spyglass_zoom if inventory != null else 0.0
	var hide_dot := is_any_overlay_open() or spy > 0.25
	var want := 0.0 if hide_dot else 0.78
	_crosshair_view.alpha = move_toward(_crosshair_view.alpha, want, delta * 10.0)
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
		slices.append({
			"id": id,
			"label": ToolMeshes.get_display_name(id),
			"hint": String(ITEM_SLICE_HINTS.get(id, "")),
			"icon": id,
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


func _on_spyglass_zoom(amount: float) -> void:
	if _spyglass_view != null:
		_spyglass_view.set_zoom(amount)


func _on_sighting_updated(label: String, distance_m: float) -> void:
	if _spyglass_view != null:
		_spyglass_view.set_sighting(label, distance_m)


func _on_pawn_damaged(_amount: float, _from: Node) -> void:
	_vitals_show_timer = 4.5


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
	if pawn != null and pawn.platform is Ship:
		return pawn.platform as Ship
	return ship


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


# ==============================================================================
# Custom drawn minimal HUD controls
# ==============================================================================

class _CrosshairView extends Control:
	var alpha: float = 0.78

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if alpha <= 0.02:
			return
		var c := size * 0.5
		draw_circle(c, 3.6, Color(0.14, 0.09, 0.05, 0.55 * alpha))
		draw_circle(c, 2.2, Color(0.96, 0.91, 0.78, alpha))


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
		if _alpha <= 0.01:
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
	var _font: Font = null

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false
		_font = HudIcons.get_ui_font()

	func set_zoom(v: float) -> void:
		_zoom = clampf(v, 0.0, 1.0)
		visible = _zoom > 0.03
		queue_redraw()

	func set_sighting(label: String, dist_m: float) -> void:
		_sighting_label = label
		_sighting_dist = dist_m
		queue_redraw()

	func _draw() -> void:
		if _zoom <= 0.03:
			return
		var c := size * 0.5
		var min_dim := minf(size.x, size.y)
		var aperture_r := lerpf(min_dim * 0.68, min_dim * 0.42, _zoom)
		var outer_r := maxf(size.x, size.y) * 0.82
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
			var txt := "%s  —  %d m" % [_sighting_label, int(roundf(_sighting_dist))]
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
