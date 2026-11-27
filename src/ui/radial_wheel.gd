class_name RadialWheel
extends Control
## Diegetic circular parchment-and-ink radial wheel control.
##
## Shared by the 11-wedge Item Radial (Q/Tab) and 9-wedge Crew Command Wheel (G).
## Draws annular parchment wedges, brass rim ticks, procedural vector icons via
## `HudIcons`, per-slice short labels, a rotating brass pointer chevron, and a
## central brass-rimmed title medallion.

signal item_selected(id: StringName)
signal secondary_triggered
signal wheel_closed(confirmed: bool)

const OUTER_RADIUS := 214.0
const INNER_RADIUS := 78.0
const HOVER_POP := 8.0
const HOVER_RADIAL_OFFSET := 4.0
const OPEN_SCALE_START := 0.88
const OPEN_ANIM_DURATION := 0.12
const WEDGE_HOVER_RISE_RATE := 16.0
const WEDGE_HOVER_FALL_RATE := 12.0
const SFX_HOVER_TICK := &"ui_tick"
const HOVER_TICK_VOL_DB := -9.0
const DEADZONE_RADIUS := 36.0
const DEFAULT_ITEM_FOOTER := "Click or release [Q] to equip  |  [Esc] Cancel"

## Entries: Array of { "id": StringName, "label": String, "hint": String, "icon": StringName, optional "short_label": String }.
var entries: Array[Dictionary] = []
var wheel_title: String = ""
var secondary_hint: String = ""
var footer_hint: String = ""
var is_open: bool = false
var hovered_index: int = -1
var active_id: StringName = &""
var hover_tick_count: int = 0

var _open_anim: float = 0.0
var _wedge_hover: PackedFloat32Array = PackedFloat32Array()
var _last_tick_hover_index: int = -1
var _pointer_angle: float = -PI * 0.5
var _pointer_visible: float = 0.0
var _font: Font = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_font = HudIcons.get_ui_font()


func _exit_tree() -> void:
	_font = null
	_last_tick_hover_index = -1


func _ensure_wedge_hover_size() -> void:
	var n := entries.size()
	if _wedge_hover.size() != n:
		_wedge_hover.resize(n)
		_wedge_hover.fill(0.0)


func _emit_hover_tick() -> void:
	hover_tick_count += 1
	if Audio != null and Audio.has_sound(SFX_HOVER_TICK):
		Audio.play_sfx(SFX_HOVER_TICK, Vector3.INF, HOVER_TICK_VOL_DB, 0.04)


## Configure the wheel's ordered slice definitions.
func configure(title: String, slice_entries: Array[Dictionary], sec_hint: String = "", foot_hint: String = "") -> void:
	wheel_title = title
	entries = slice_entries.duplicate(true)
	secondary_hint = sec_hint
	footer_hint = foot_hint
	hovered_index = clampi(hovered_index, -1, entries.size() - 1)
	_wedge_hover.resize(entries.size())
	_wedge_hover.fill(0.0)
	_last_tick_hover_index = hovered_index if is_open else -1
	queue_redraw()


## Open the radial wheel, optionally pre-highlighting `initial_id`.
func open_wheel(initial_id: StringName = &"") -> void:
	if is_open:
		return
	is_open = true
	visible = true
	active_id = initial_id
	hovered_index = -1
	if initial_id != &"":
		for i in entries.size():
			if entries[i]["id"] == initial_id:
				hovered_index = i
				break
	_ensure_wedge_hover_size()
	_wedge_hover.fill(0.0)
	_last_tick_hover_index = hovered_index
	if hovered_index >= 0 and not entries.is_empty():
		var step := TAU / float(entries.size())
		_pointer_angle = -PI * 0.5 + float(hovered_index) * step
		_pointer_visible = 1.0
	else:
		_pointer_angle = -PI * 0.5
		_pointer_visible = 0.0
	_open_anim = 0.0
	if Audio != null and Audio.has_sound(&"ui_open"):
		Audio.play_sfx(&"ui_open", Vector3.INF, -3.0)
	queue_redraw()


## Close the radial wheel. If `confirm` is true and a wedge is hovered, emits `item_selected`.
func close_wheel(confirm: bool = true) -> StringName:
	if not is_open:
		return &""
	is_open = false
	visible = false
	_open_anim = 0.0
	_last_tick_hover_index = -1
	_wedge_hover.fill(0.0)
	var chosen := &""
	if confirm and hovered_index >= 0 and hovered_index < entries.size():
		chosen = entries[hovered_index]["id"]
		if Audio != null and Audio.has_sound(&"ui_select"):
			Audio.play_sfx(&"ui_select", Vector3.INF, -2.5)
		item_selected.emit(chosen)
		wheel_closed.emit(true)
	else:
		if Audio != null and Audio.has_sound(&"ui_back"):
			Audio.play_sfx(&"ui_back", Vector3.INF, -3.0)
		wheel_closed.emit(false)
	queue_redraw()
	return chosen


## Programmatically set the hovered wedge index (plays `ui_tick` if changed while open).
func set_hover_index(idx: int, play_sound: bool = true) -> void:
	var clamped := idx if (idx >= 0 and idx < entries.size()) else -1
	if clamped == hovered_index:
		return
	hovered_index = clamped
	_last_tick_hover_index = hovered_index if is_open else -1
	if play_sound and is_open and hovered_index >= 0:
		_emit_hover_tick()
	queue_redraw()


## Highlight and return the entry corresponding to screen-center angle `angle_rad`
## (where -PI/2 is straight up / 12 o'clock, increasing clockwise).
func select_by_angle(angle_rad: float) -> StringName:
	if entries.is_empty():
		return &""
	var n := entries.size()
	var step := TAU / float(n)
	# Slice 0 is centered at -PI/2 (top).
	var shifted := fposmod(angle_rad + PI * 0.5 + step * 0.5, TAU)
	var idx := clampi(int(floorf(shifted / step)), 0, n - 1)
	set_hover_index(idx)
	return entries[idx]["id"]


## Immediately select a slice by ID (opens/closes cleanly for tests or hotkeys).
func select_by_id(id: StringName) -> bool:
	for i in entries.size():
		if entries[i]["id"] == id:
			hovered_index = i
			if is_open:
				close_wheel(true)
			else:
				if Audio != null and Audio.has_sound(&"ui_select"):
					Audio.play_sfx(&"ui_select", Vector3.INF, -2.5)
				item_selected.emit(id)
			return true
	return false


func get_hovered_id() -> StringName:
	if hovered_index >= 0 and hovered_index < entries.size():
		return entries[hovered_index]["id"]
	return &""


## Return the smooth hover expansion weight [0.0..1.0] for slice `index`.
func get_wedge_hover_weight(index: int) -> float:
	if index < 0 or index >= _wedge_hover.size():
		return 0.0
	return _wedge_hover[index]


## Return the open pop-in animation progress [0.0..1.0].
func get_open_anim_progress() -> float:
	return clampf(_open_anim, 0.0, 1.0)


## Return total selection tick SFX triggers fired on hover slice changes.
func get_hover_tick_count() -> int:
	return hover_tick_count


## Return the strict-ASCII short display label rendered inside slice `index`.
func get_slice_display_label(index: int) -> String:
	if index < 0 or index >= entries.size():
		return ""
	var raw_short := String(entries[index].get("short_label", ""))
	if raw_short != "":
		return _to_ascii(raw_short)
	return _to_ascii(_short_slice_label(_to_ascii(String(entries[index].get("label", "")))))


## Return the active strict-ASCII footer pill string rendered beneath the wheel.
func get_footer_pill_text() -> String:
	if secondary_hint != "":
		return _to_ascii(secondary_hint)
	if footer_hint != "":
		return _to_ascii(footer_hint)
	return DEFAULT_ITEM_FOOTER


## Advance open pop-in, per-wedge smooth hover expansion weights, and pointer angle.
## Callable directly in headless tests with zero steady-state allocations.
func step_radial_animation(delta: float) -> void:
	if not is_open or delta <= 0.0:
		return
	var n := entries.size()
	if _wedge_hover.size() != n:
		_wedge_hover.resize(n)
		_wedge_hover.fill(0.0)
	if hovered_index != _last_tick_hover_index:
		if hovered_index >= 0 and hovered_index < n:
			_emit_hover_tick()
		_last_tick_hover_index = hovered_index

	var dirty := false
	if _open_anim < 1.0:
		_open_anim = minf(1.0, _open_anim + delta / OPEN_ANIM_DURATION)
		dirty = true

	var rise_t := 1.0 - exp(-WEDGE_HOVER_RISE_RATE * delta)
	var fall_t := 1.0 - exp(-WEDGE_HOVER_FALL_RATE * delta)
	for i in n:
		var cur := _wedge_hover[i]
		var target := 1.0 if i == hovered_index else 0.0
		if absf(cur - target) > 0.0005:
			var blend := rise_t if target > cur else fall_t
			var nxt := lerpf(cur, target, blend)
			if absf(nxt - target) < 0.001:
				nxt = target
			_wedge_hover[i] = nxt
			dirty = true

	if hovered_index >= 0 and hovered_index < n:
		var step := TAU / float(n)
		var target_ang := -PI * 0.5 + float(hovered_index) * step
		if _pointer_visible < 0.05:
			_pointer_angle = target_ang
			dirty = true
		else:
			var diff := angle_difference(_pointer_angle, target_ang)
			if absf(diff) > 0.002:
				_pointer_angle = wrapf(_pointer_angle + diff * (1.0 - exp(-22.0 * delta)), -PI, PI)
				dirty = true
		if _pointer_visible < 1.0:
			_pointer_visible = minf(1.0, _pointer_visible + delta * 10.0)
			dirty = true
	elif _pointer_visible > 0.0:
		_pointer_visible = maxf(0.0, _pointer_visible - delta * 10.0)
		dirty = true

	if dirty:
		queue_redraw()


func _process(delta: float) -> void:
	step_radial_animation(delta)


func _gui_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventMouseMotion:
		var wheel_sz := _get_wheel_size()
		var m := event as InputEventMouseMotion
		var offset := m.position - wheel_sz * 0.5
		if offset.length() >= DEADZONE_RADIUS:
			select_by_angle(atan2(offset.y, offset.x))
		accept_event()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var wheel_sz := _get_wheel_size()
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var offset := mb.position - wheel_sz * 0.5
			if offset.length() >= DEADZONE_RADIUS:
				select_by_angle(atan2(offset.y, offset.x))
			close_wheel(true)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if secondary_hint != "":
				if Audio != null and Audio.has_sound(&"ui_select"):
					Audio.play_sfx(&"ui_select", Vector3.INF, -3.0)
				secondary_triggered.emit()
				queue_redraw()
			else:
				close_wheel(false)
			accept_event()


func _get_wheel_size() -> Vector2:
	if size.is_finite() and size.length_squared() >= 1.0 and size.x > 10.0 and size.y > 10.0:
		return size
	var vp_sz := get_viewport_rect().size
	if vp_sz.is_finite() and vp_sz.x > 10.0 and vp_sz.y > 10.0:
		return vp_sz
	return Vector2.ZERO


func _draw_wedge(
	i: int,
	center: Vector2,
	r_in: float,
	r_out: float,
	start_base: float,
	step: float,
	scale_r: float,
	ease_t: float
) -> void:
	var a0 := start_base + float(i) * step
	var a1 := a0 + step
	var amid := (a0 + a1) * 0.5
	var mid_dir := Vector2(cos(amid), sin(amid))
	var is_hov := (i == hovered_index)
	var w := _wedge_hover[i] if i < _wedge_hover.size() else (1.0 if is_hov else 0.0)
	var is_active: bool = (entries[i]["id"] == active_id)

	var wedge_center := center + mid_dir * (HOVER_RADIAL_OFFSET * w * scale_r)
	var wedge_out := r_out + HOVER_POP * w * scale_r
	var base_fill := Color(0.94, 0.87, 0.70, 0.97) if is_active else HudIcons.COL_PARCHMENT
	var fill := base_fill.lerp(HudIcons.COL_PARCHMENT_HIGHLIGHT, w)
	fill.a *= ease_t

	var poly := _annular_sector(wedge_center, r_in, wedge_out, a0 + 0.012, a1 - 0.012, 8)
	draw_colored_polygon(poly, fill)

	# Gleaming brass outer highlight arc & warm crimson/gold accents on hover or active slice.
	if w > 0.02:
		var brass_outer := Color(0.98, 0.85, 0.44, 0.96 * w * ease_t)
		var crimson_trim := HudIcons.COL_CRIMSON
		crimson_trim.a *= w * ease_t
		var gold_inner := HudIcons.COL_GOLD
		gold_inner.a *= w * ease_t
		draw_arc(wedge_center, wedge_out - 1.6, a0 + 0.012, a1 - 0.012, 14, brass_outer, 3.8, true)
		draw_arc(wedge_center, wedge_out - 5.2, a0 + 0.014, a1 - 0.014, 12, crimson_trim, 2.2, true)
		draw_arc(wedge_center, r_in + 3.0, a0 + 0.014, a1 - 0.014, 10, gold_inner, 3.0, true)
	elif is_active:
		var active_brass := HudIcons.COL_BRASS
		active_brass.a *= ease_t
		draw_arc(wedge_center, r_in + 3.0, a0 + 0.014, a1 - 0.014, 10, active_brass, 2.8, true)

	# Vector icon + crisp short label cleanly paired inside each wedge!
	var wedge_r := lerpf(r_in, wedge_out, 0.50)
	var wedge_pos := wedge_center + mid_dir * wedge_r
	var icon_sz := lerpf(18.5, 22.5, w) * scale_r
	var icon_pos := wedge_pos + Vector2(0.0, -7.5 * scale_r)
	var ink := HudIcons.COL_INK.lerp(Color(0.07, 0.04, 0.01, 1.0), w)
	ink.a *= ease_t
	var acc := HudIcons.COL_BRASS.lerp(HudIcons.COL_CRIMSON, w)
	acc.a *= ease_t
	var icon_id: StringName = entries[i].get("icon", entries[i]["id"])
	HudIcons.draw_icon(self, icon_id, icon_pos, icon_sz, ink, acc)

	if _font != null:
		var short_lbl := get_slice_display_label(i)
		if short_lbl != "":
			var max_lbl_w := 76.0 * scale_r
			var lbl_fs := 12 if w >= 0.45 else 11
			while lbl_fs > 9 and _font.get_string_size(short_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, lbl_fs).x > max_lbl_w:
				lbl_fs -= 1
			var lbl_col := HudIcons.COL_INK.lerp(HudIcons.COL_CRIMSON, w)
			lbl_col.a *= ease_t
			var lbl_y := icon_pos.y + icon_sz + 12.0 * scale_r
			draw_string(_font, Vector2(wedge_pos.x - max_lbl_w * 0.5, lbl_y),
				short_lbl, HORIZONTAL_ALIGNMENT_CENTER, max_lbl_w, lbl_fs, lbl_col)


func _draw() -> void:
	if not is_open or entries.is_empty():
		return
	var wheel_sz := _get_wheel_size()
	if not wheel_sz.is_finite() or wheel_sz.x < 4.0 or wheel_sz.y < 4.0:
		return
	if _font == null:
		_font = HudIcons.get_ui_font()
	var center := wheel_sz * 0.5
	var ease_t := 1.0 - pow(1.0 - clampf(_open_anim, 0.0, 1.0), 3.0)
	var scale_r := lerpf(OPEN_SCALE_START, 1.0, ease_t)
	var r_in := INNER_RADIUS * scale_r
	var r_out := OUTER_RADIUS * scale_r

	# Subtle warm nautical shadow scrim behind the wheel.
	draw_rect(Rect2(Vector2.ZERO, wheel_sz), Color(0.06, 0.04, 0.02, 0.34 * ease_t), true)

	# Outer decorative dark-oak & brass backing halo.
	draw_circle(center, r_out + 10.0, Color(0.18, 0.12, 0.07, 0.90 * ease_t))
	draw_arc(center, r_out + 10.0, 0.0, TAU, 72, HudIcons.COL_BRASS, 2.5, true)

	var n := entries.size()
	var step := TAU / float(n)
	var start_base := -PI * 0.5 - step * 0.5

	# Draw base parchment wedges first, then dividers & compass rings, then popped hovered wedge on top.
	for i in n:
		if i != hovered_index:
			_draw_wedge(i, center, r_in, r_out, start_base, step, scale_r, ease_t)

	# Crisp sepia wedge divider lines.
	for i in n:
		var a0 := start_base + float(i) * step
		var dir0 := Vector2(cos(a0), sin(a0))
		draw_line(center + dir0 * r_in, center + dir0 * r_out, HudIcons.COL_INK_SOFT, 1.8, true)

	# Outer & inner brass compass rings + degree ticks.
	draw_arc(center, r_out, 0.0, TAU, 72, HudIcons.COL_INK, 2.4, true)
	draw_arc(center, r_in, 0.0, TAU, 48, HudIcons.COL_INK, 2.6, true)
	for t in 36:
		var ta := float(t) / 36.0 * TAU
		var d := Vector2(cos(ta), sin(ta))
		var t_len := 7.0 if (t % 3 == 0) else 4.0
		draw_line(center + d * (r_out + 2.0), center + d * (r_out + 2.0 + t_len), HudIcons.COL_GOLD, 1.4, true)

	# Draw actively hovered wedge on top so its smooth radial pop & gleaming brass rim stand proud.
	if hovered_index >= 0 and hovered_index < n:
		_draw_wedge(hovered_index, center, r_in, r_out, start_base, step, scale_r, ease_t)

	# Gleaming central brass pointer chevron rotating smoothly toward the hovered wedge!
	if _pointer_visible > 0.02:
		var pa := _pointer_angle
		var p_alpha := _pointer_visible * ease_t
		var dir := Vector2(cos(pa), sin(pa))
		var w_ang := 0.21
		var tip := center + dir * (r_in + 15.0 * scale_r)
		var wing_l := center + Vector2(cos(pa - w_ang), sin(pa - w_ang)) * (r_in - 5.0 * scale_r)
		var wing_r := center + Vector2(cos(pa + w_ang), sin(pa + w_ang)) * (r_in - 5.0 * scale_r)
		var notch := center + dir * (r_in - 1.5 * scale_r)
		var chevron := PackedVector2Array([tip, wing_r, notch, wing_l])
		var gold_col := HudIcons.COL_GOLD
		gold_col.a *= p_alpha
		var ink_col := HudIcons.COL_INK
		ink_col.a *= p_alpha
		var glint_col := Color(0.99, 0.94, 0.74, 0.92 * p_alpha)
		draw_colored_polygon(chevron, gold_col)
		draw_polyline(PackedVector2Array([tip, wing_r, notch, wing_l, tip]), ink_col, 2.0, true)
		draw_line(notch + dir * 2.0, tip - dir * 3.0, glint_col, 1.6, true)

	# Center brass-rimmed parchment medallion with hovered title & subtitle.
	draw_circle(center, r_in - 2.0, Color(0.95, 0.89, 0.74, 0.98 * ease_t))
	draw_arc(center, r_in - 5.0, 0.0, TAU, 48, HudIcons.COL_BRASS, 2.2, true)
	if _font != null:
		var main_txt := _to_ascii(wheel_title)
		var sub_txt := "Move mouse to select"
		if hovered_index >= 0 and hovered_index < entries.size():
			main_txt = _to_ascii(String(entries[hovered_index].get("label", "")))
			sub_txt = _to_ascii(String(entries[hovered_index].get("hint", "")))

		var max_medallion_w := r_in * 1.65
		var main_fs := 17
		while main_fs > 12 and _font.get_string_size(main_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, main_fs).x > max_medallion_w:
			main_fs -= 1

		var sub_fs := 12
		var sub_lines := PackedStringArray()
		if sub_txt != "":
			sub_lines = _wrap_medallion_lines(_font, sub_txt, max_medallion_w, sub_fs)
			while sub_fs > 10 and (sub_lines.size() > 3 or _max_line_width(_font, sub_lines, sub_fs) > max_medallion_w):
				sub_fs -= 1
				sub_lines = _wrap_medallion_lines(_font, sub_txt, max_medallion_w, sub_fs)

		var line_step := float(sub_fs) + 3.0
		var main_y := center.y + 4.0
		if not sub_lines.is_empty():
			var total_sub_h := float(sub_lines.size()) * line_step
			main_y = center.y - total_sub_h * 0.42
		draw_string(_font, Vector2(center.x - max_medallion_w * 0.5, main_y),
			main_txt, HORIZONTAL_ALIGNMENT_CENTER, max_medallion_w, main_fs, HudIcons.COL_INK)

		var sub_y := main_y + 15.0
		for ln in sub_lines:
			draw_string(_font, Vector2(center.x - max_medallion_w * 0.5, sub_y),
				ln, HORIZONTAL_ALIGNMENT_CENTER, max_medallion_w, sub_fs, HudIcons.COL_INK_SOFT)
			sub_y += line_step

		# Clean brass-trimmed parchment footer pill below the wheel.
		var pill_clean := get_footer_pill_text()
		if pill_clean != "":
			var pill_sz := _font.get_string_size(pill_clean, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
			var pw := pill_sz.x + 30.0
			var ph := 32.0
			var pr := Rect2(center.x - pw * 0.5, center.y + r_out + 26.0, pw, ph)
			var pbg := HudIcons.COL_PARCHMENT
			pbg.a *= ease_t
			var pborder := HudIcons.COL_BRASS
			pborder.a *= ease_t
			var pink := HudIcons.COL_INK
			pink.a *= ease_t
			draw_rect(pr, pbg, true)
			draw_rect(pr, pborder, false, 3.0)
			draw_rect(pr.grow(-2.0), pink, false, 1.2)
			draw_string(_font, Vector2(center.x - pill_sz.x * 0.5, pr.position.y + 21.0),
				pill_clean, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, pink)


static func _short_slice_label(full_label: String) -> String:
	var clean := full_label.strip_edges()
	if clean == "":
		return ""
	match clean:
		"Boarding Axe":
			return "Axe"
		"Flintlock Pistol":
			return "Pistol"
		"Blunderbuss":
			return "Blunder"
		"Brass Compass":
			return "Compass"
		"Oil Lantern":
			return "Lantern"
		"Treasure Map":
			return "Map"
		"Iron Shovel":
			return "Shovel"
		"Bilge Bucket":
			return "Bucket"
		"Oak Planks":
			return "Planks"
		"Grog Tankard":
			return "Tankard"
		"Concertina":
			return "Music"
		"Hurdy-Gurdy":
			return "Music"
		"Bosun's Whistle":
			return "Whistle"
		"Man Helm":
			return "Helm"
		"Trim Sails":
			return "Sails"
		"Drop Anchor":
			return "Drop"
		"Raise Anchor":
			return "Weigh"
		"Man Cannons":
			return "Cannons"
		"Repair & Bail":
			return "Repair"
		"Follow Me":
			return "Follow"
		"Fetch Loot":
			return "Loot"
		"Play Shanty":
			return "Shanty"
	var parts := clean.split(" ", false)
	if parts.size() >= 2:
		return parts[parts.size() - 1]
	return clean


static func _to_ascii(text: String) -> String:
	var out := text.replace(char(0x2014), "--").replace(char(0x2013), "-")
	out = out.replace(char(0x00B7), "|").replace(char(0x2022), "*")
	out = out.replace(char(0x2018), "'").replace(char(0x2019), "'")
	out = out.replace(char(0x201C), "\"").replace(char(0x201D), "\"")
	out = out.replace(char(0x2026), "...")
	var has_non_ascii := false
	for i in out.length():
		if out.unicode_at(i) >= 128:
			has_non_ascii = true
			break
	if not has_non_ascii:
		return out
	var clean := ""
	for i in out.length():
		if out.unicode_at(i) < 128:
			clean += out[i]
	return clean


static func _max_line_width(font: Font, lines: PackedStringArray, font_size: int) -> float:
	var best := 0.0
	for ln in lines:
		best = maxf(best, font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	return best


static func _wrap_medallion_lines(font: Font, text: String, max_w: float, font_size: int) -> PackedStringArray:
	var out := PackedStringArray()
	var clauses := text.split("|", false)
	for raw_clause in clauses:
		var clause := raw_clause.strip_edges()
		if clause == "":
			continue
		if font.get_string_size(clause, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
			out.append(clause)
			continue
		var words := clause.split(" ", false)
		var cur := ""
		for w in words:
			var cand := w if cur == "" else (cur + " " + w)
			if cur == "" or font.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
				cur = cand
			else:
				out.append(cur)
				cur = w
		if cur != "":
			out.append(cur)
	return out


static func _annular_sector(
	center: Vector2,
	r_in: float,
	r_out: float,
	a0: float,
	a1: float,
	arc_steps: int
) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := maxi(arc_steps, 3)
	for i in range(steps + 1):
		var a := lerpf(a0, a1, float(i) / float(steps))
		pts.append(center + Vector2(cos(a), sin(a)) * r_out)
	for i in range(steps, -1, -1):
		var a := lerpf(a0, a1, float(i) / float(steps))
		pts.append(center + Vector2(cos(a), sin(a)) * r_in)
	return pts
