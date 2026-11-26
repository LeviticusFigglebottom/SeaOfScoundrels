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
const HOVER_POP := 12.0
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

var _open_anim: float = 0.0
var _pointer_angle: float = -PI * 0.5
var _pointer_visible: float = 0.0
var _font: Font = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_font = HudIcons.get_ui_font()


## Configure the wheel's ordered slice definitions.
func configure(title: String, slice_entries: Array[Dictionary], sec_hint: String = "", foot_hint: String = "") -> void:
	wheel_title = title
	entries = slice_entries.duplicate(true)
	secondary_hint = sec_hint
	footer_hint = foot_hint
	hovered_index = clampi(hovered_index, -1, entries.size() - 1)
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
	if hovered_index >= 0 and not entries.is_empty():
		var step := TAU / float(entries.size())
		_pointer_angle = -PI * 0.5 + float(hovered_index) * step
		_pointer_visible = 1.0
	else:
		_pointer_angle = -PI * 0.5
		_pointer_visible = 0.0
	_open_anim = 0.0
	Audio.play_sfx(&"ui_open", Vector3.INF, -3.0)
	queue_redraw()


## Close the radial wheel. If `confirm` is true and a wedge is hovered, emits `item_selected`.
func close_wheel(confirm: bool = true) -> StringName:
	if not is_open:
		return &""
	is_open = false
	visible = false
	var chosen := &""
	if confirm and hovered_index >= 0 and hovered_index < entries.size():
		chosen = entries[hovered_index]["id"]
		Audio.play_sfx(&"ui_select", Vector3.INF, -2.5)
		item_selected.emit(chosen)
		wheel_closed.emit(true)
	else:
		Audio.play_sfx(&"ui_back", Vector3.INF, -3.0)
		wheel_closed.emit(false)
	queue_redraw()
	return chosen


## Programmatically set the hovered wedge index (plays `ui_tick` if changed).
func set_hover_index(idx: int, play_sound: bool = true) -> void:
	var clamped := idx if (idx >= 0 and idx < entries.size()) else -1
	if clamped == hovered_index:
		return
	hovered_index = clamped
	if play_sound and is_open and hovered_index >= 0:
		Audio.play_sfx(&"ui_tick", Vector3.INF, -6.0, 0.04)
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
				Audio.play_sfx(&"ui_select", Vector3.INF, -2.5)
				item_selected.emit(id)
			return true
	return false


func get_hovered_id() -> StringName:
	if hovered_index >= 0 and hovered_index < entries.size():
		return entries[hovered_index]["id"]
	return &""


## Return the active strict-ASCII footer pill string rendered beneath the wheel.
func get_footer_pill_text() -> String:
	if secondary_hint != "":
		return _to_ascii(secondary_hint)
	if footer_hint != "":
		return _to_ascii(footer_hint)
	return DEFAULT_ITEM_FOOTER


func _process(delta: float) -> void:
	if not is_open:
		return
	var dirty := false
	if _open_anim < 1.0:
		_open_anim = minf(1.0, _open_anim + delta * 8.5)
		dirty = true
	if hovered_index >= 0 and hovered_index < entries.size():
		var step := TAU / float(entries.size())
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
	var scale_r := lerpf(0.82, 1.0, ease_t)
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

	# Draw every parchment wedge.
	for i in n:
		var a0 := start_base + float(i) * step
		var a1 := a0 + step
		var amid := (a0 + a1) * 0.5
		var is_hov := (i == hovered_index)
		var is_active: bool = (entries[i]["id"] == active_id)
		var pop := HOVER_POP * scale_r if is_hov else 0.0
		var wedge_out := r_out + pop
		var fill := HudIcons.COL_PARCHMENT_HIGHLIGHT if is_hov else (
			Color(0.94, 0.87, 0.70, 0.97) if is_active else HudIcons.COL_PARCHMENT)
		fill.a *= ease_t

		var poly := _annular_sector(center, r_in, wedge_out, a0 + 0.012, a1 - 0.012, 8)
		draw_colored_polygon(poly, fill)

		# Inner gold/crimson arc highlight for hovered or currently equipped slice.
		if is_hov:
			draw_arc(center, wedge_out - 3.0, a0 + 0.014, a1 - 0.014, 12, HudIcons.COL_CRIMSON, 4.5, true)
			draw_arc(center, r_in + 3.0, a0 + 0.014, a1 - 0.014, 10, HudIcons.COL_GOLD, 3.0, true)
		elif is_active:
			draw_arc(center, r_in + 3.0, a0 + 0.014, a1 - 0.014, 10, HudIcons.COL_BRASS, 2.8, true)

		# Crisp sepia divider line.
		var p0 := center + Vector2(cos(a0), sin(a0)) * r_in
		var p1 := center + Vector2(cos(a0), sin(a0)) * r_out
		draw_line(p0, p1, HudIcons.COL_INK_SOFT, 1.8, true)

		# Vector icon + crisp short label cleanly paired inside each wedge!
		var wedge_r := lerpf(r_in, wedge_out, 0.50)
		var wedge_pos := center + Vector2(cos(amid), sin(amid)) * wedge_r
		var icon_sz := (22.0 if is_hov else 18.5) * scale_r
		var icon_pos := wedge_pos + Vector2(0.0, -7.5 * scale_r)
		var ink := HudIcons.COL_INK
		var acc := HudIcons.COL_CRIMSON if is_hov else HudIcons.COL_BRASS
		var icon_id: StringName = entries[i].get("icon", entries[i]["id"])
		HudIcons.draw_icon(self, icon_id, icon_pos, icon_sz, ink, acc)

		if _font != null:
			var raw_short := String(entries[i].get("short_label", ""))
			var short_lbl := _to_ascii(raw_short) if raw_short != "" else _short_slice_label(_to_ascii(String(entries[i].get("label", ""))))
			if short_lbl != "":
				var max_lbl_w := 76.0 * scale_r
				var lbl_fs := 12 if is_hov else 11
				while lbl_fs > 9 and _font.get_string_size(short_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, lbl_fs).x > max_lbl_w:
					lbl_fs -= 1
				var lbl_col := HudIcons.COL_CRIMSON if is_hov else HudIcons.COL_INK
				lbl_col.a *= ease_t
				var lbl_y := icon_pos.y + icon_sz + 12.0 * scale_r
				draw_string(_font, Vector2(wedge_pos.x - max_lbl_w * 0.5, lbl_y),
					short_lbl, HORIZONTAL_ALIGNMENT_CENTER, max_lbl_w, lbl_fs, lbl_col)

	# Outer & inner brass compass rings + degree ticks.
	draw_arc(center, r_out, 0.0, TAU, 72, HudIcons.COL_INK, 2.4, true)
	draw_arc(center, r_in, 0.0, TAU, 48, HudIcons.COL_INK, 2.6, true)
	for t in 36:
		var ta := float(t) / 36.0 * TAU
		var d := Vector2(cos(ta), sin(ta))
		var t_len := 7.0 if (t % 3 == 0) else 4.0
		draw_line(center + d * (r_out + 2.0), center + d * (r_out + 2.0 + t_len), HudIcons.COL_GOLD, 1.4, true)

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
	return out


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
