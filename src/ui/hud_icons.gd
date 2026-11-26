class_name HudIcons
extends RefCounted
## Procedurally drawn parchment-and-ink vector icons and UI font/style helpers.
##
## Renders crisp hand-inked icons via CanvasItem `_draw()` calls for all 11 held
## tools/weapons and all crew captain commands, with zero third-party assets.

const FONT_PATH := "res://assets/generated/ui/scoundrel_font.fnt"

const COL_PARCHMENT := Color(0.92, 0.85, 0.70, 0.96)
const COL_PARCHMENT_DARK := Color(0.81, 0.71, 0.54, 0.96)
const COL_PARCHMENT_HIGHLIGHT := Color(0.97, 0.91, 0.74, 0.98)
const COL_INK := Color(0.20, 0.13, 0.08, 0.96)
const COL_INK_SOFT := Color(0.38, 0.27, 0.17, 0.86)
const COL_BRASS := Color(0.76, 0.56, 0.20, 1.0)
const COL_GOLD := Color(0.89, 0.70, 0.25, 1.0)
const COL_CRIMSON := Color(0.76, 0.14, 0.12, 0.98)
const COL_TEAL := Color(0.16, 0.52, 0.50, 0.96)

## Load the original procedural BMFont (`scoundrel_font.fnt`) with graceful fallback.
static func get_ui_font() -> Font:
	if ResourceLoader.exists(FONT_PATH):
		var f := load(FONT_PATH) as Font
		if f != null:
			return f
	return ThemeDB.fallback_font


## Build a warm parchment-and-ink StyleBoxFlat for banners, panels, and buttons.
static func make_parchment_box(
	bg: Color = COL_PARCHMENT,
	border: Color = COL_INK,
	border_w: int = 2,
	radius: int = 6,
	pad_h: int = 12,
	pad_v: int = 7
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	sb.shadow_color = Color(0.08, 0.05, 0.02, 0.30)
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(0.0, 2.0)
	return sb


## Build a cohesive parchment-and-ink Theme using `scoundrel_font.fnt`.
static func build_parchment_theme() -> Theme:
	var th := Theme.new()
	var font := get_ui_font()
	if font != null:
		th.default_font = font
	th.default_font_size = 16

	th.set_color("font_color", "Label", COL_INK)
	th.set_color("font_color", "Button", COL_INK)
	th.set_color("font_hover_color", "Button", COL_CRIMSON)
	th.set_color("font_pressed_color", "Button", COL_INK)
	th.set_color("font_focus_color", "Button", COL_INK)
	th.set_color("font_color", "LineEdit", COL_INK)
	th.set_color("font_placeholder_color", "LineEdit", COL_INK_SOFT)

	var btn_norm := make_parchment_box(Color(0.89, 0.81, 0.64, 0.98), COL_INK, 2, 5, 14, 7)
	var btn_hov := make_parchment_box(COL_PARCHMENT_HIGHLIGHT, COL_CRIMSON, 2, 5, 14, 7)
	var btn_press := make_parchment_box(COL_PARCHMENT_DARK, COL_INK, 2, 5, 14, 7)
	th.set_stylebox("normal", "Button", btn_norm)
	th.set_stylebox("hover", "Button", btn_hov)
	th.set_stylebox("pressed", "Button", btn_press)
	th.set_stylebox("focus", "Button", btn_hov)

	var edit_sb := make_parchment_box(Color(0.96, 0.91, 0.79, 0.98), COL_INK_SOFT, 2, 4, 8, 4)
	th.set_stylebox("normal", "LineEdit", edit_sb)
	th.set_stylebox("focus", "LineEdit", make_parchment_box(Color(0.98, 0.94, 0.84, 1.0), COL_CRIMSON, 2, 4, 8, 4))

	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Color(0.56, 0.45, 0.30, 0.85)
	slider_bg.set_corner_radius_all(3)
	slider_bg.content_margin_top = 4
	slider_bg.content_margin_bottom = 4
	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = COL_BRASS
	slider_fill.set_corner_radius_all(3)
	th.set_stylebox("slider", "HSlider", slider_bg)
	th.set_stylebox("grabber_area", "HSlider", slider_fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	return th


## Draw a crisp procedural hand-inked vector icon for any tool or crew command ID.
static func draw_icon(
	canvas: CanvasItem,
	icon_id: StringName,
	center: Vector2,
	radius: float,
	ink: Color = COL_INK,
	accent: Color = COL_CRIMSON
) -> void:
	var r := maxf(radius, 8.0)
	match icon_id:
		&"cutlass":
			_draw_cutlass(canvas, center, r, ink, accent)
		&"pistol":
			_draw_pistol(canvas, center, r, ink, accent)
		&"compass":
			_draw_compass(canvas, center, r, ink, accent)
		&"spyglass":
			_draw_spyglass(canvas, center, r, ink, accent)
		&"lantern":
			_draw_lantern(canvas, center, r, ink, accent)
		&"map":
			_draw_map(canvas, center, r, ink, accent)
		&"shovel":
			_draw_shovel(canvas, center, r, ink, accent)
		&"bucket":
			_draw_bucket(canvas, center, r, ink, accent)
		&"planks":
			_draw_planks(canvas, center, r, ink, accent)
		&"tankard":
			_draw_tankard(canvas, center, r, ink, accent)
		&"instrument", &"shanty":
			_draw_instrument(canvas, center, r, ink, accent)
		&"helm":
			_draw_helm(canvas, center, r, ink, accent)
		&"trim":
			_draw_sail(canvas, center, r, ink, accent)
		&"anchor_drop":
			_draw_anchor(canvas, center, r, ink, accent, true)
		&"anchor_raise":
			_draw_anchor(canvas, center, r, ink, accent, false)
		&"cannons":
			_draw_cannon(canvas, center, r, ink, accent)
		&"repair":
			_draw_repair(canvas, center, r, ink, accent)
		&"follow":
			_draw_follow(canvas, center, r, ink, accent)
		&"fetch_treasure":
			_draw_chest(canvas, center, r, ink, accent)
		&"hold_fire":
			_draw_cannon(canvas, center, r, ink, accent)
			canvas.draw_line(center + Vector2(-r * 0.72, -r * 0.72), center + Vector2(r * 0.72, r * 0.72), accent, 3.0, true)
		_:
			canvas.draw_arc(center, r * 0.55, 0.0, TAU, 16, ink, 2.2, true)
			canvas.draw_circle(center, r * 0.16, accent)


# ==============================================================================
# 11 Tool icons
# ==============================================================================

static func _draw_cutlass(c: CanvasItem, o: Vector2, r: float, ink: Color, accent: Color) -> void:
	# Sweeping curved pirate blade from bottom-left hilt to top-right tip.
	var blade := PackedVector2Array([
		o + Vector2(-r * 0.34, r * 0.24),
		o + Vector2(-r * 0.06, -r * 0.28),
		o + Vector2(r * 0.44, -r * 0.74),
		o + Vector2(r * 0.72, -r * 0.78),
		o + Vector2(r * 0.54, -r * 0.36),
		o + Vector2(r * 0.12, r * 0.06),
		o + Vector2(-r * 0.18, r * 0.38),
	])
	c.draw_colored_polygon(blade, ink)
	# Sweeping brass D-guard bow + grip.
	c.draw_line(o + Vector2(-r * 0.44, r * 0.12), o + Vector2(-r * 0.08, r * 0.48), accent, 3.2, true)
	c.draw_line(o + Vector2(-r * 0.28, r * 0.32), o + Vector2(-r * 0.64, r * 0.68), ink, 4.4, true)
	c.draw_arc(o + Vector2(-r * 0.36, r * 0.54), r * 0.26, -0.3, 2.35, 12, accent, 2.4, true)


static func _draw_pistol(c: CanvasItem, o: Vector2, r: float, ink: Color, accent: Color) -> void:
	# Chunky flintlock barrel & flared muzzle pointing right, curved stock bottom-left.
	var barrel := PackedVector2Array([
		o + Vector2(-r * 0.36, -r * 0.28),
		o + Vector2(r * 0.74, -r * 0.24),
		o + Vector2(r * 0.78, -r * 0.34),
		o + Vector2(r * 0.78, r * 0.02),
		o + Vector2(r * 0.70, -r * 0.05),
		o + Vector2(-r * 0.28, -r * 0.02),
	])
	c.draw_colored_polygon(barrel, ink)
	var stock := PackedVector2Array([
		o + Vector2(-r * 0.36, -r * 0.18),
		o + Vector2(-r * 0.12, -r * 0.04),
		o + Vector2(-r * 0.42, r * 0.68),
		o + Vector2(-r * 0.74, r * 0.56),
	])
	c.draw_colored_polygon(stock, ink)
	# Brass cock hammer & trigger guard.
	c.draw_line(o + Vector2(-r * 0.18, -r * 0.26), o + Vector2(-r * 0.30, -r * 0.56), accent, 2.8, true)
	c.draw_arc(o + Vector2(-r * 0.04, r * 0.14), r * 0.17, 0.0, PI, 10, accent, 2.2, true)


static func _draw_compass(c: CanvasItem, o: Vector2, r: float, ink: Color, accent: Color) -> void:
	c.draw_arc(o, r * 0.70, 0.0, TAU, 28, ink, 2.6, true)
	c.draw_arc(o, r * 0.54, 0.0, TAU, 24, ink, 1.2, true)
	# Top lanyard ring.
	c.draw_arc(o + Vector2(0.0, -r * 0.84), r * 0.14, 0.0, TAU, 12, ink, 2.0, true)
	# Crimson North needle & ink South tail.
	c.draw_colored_polygon(PackedVector2Array([
		o + Vector2(0.0, -r * 0.54),
		o + Vector2(r * 0.17, 0.0),
		o + Vector2(-r * 0.17, 0.0),
	]), accent)
	c.draw_colored_polygon(PackedVector2Array([
		o + Vector2(0.0, r * 0.54),
		o + Vector2(r * 0.15, 0.0),
		o + Vector2(-r * 0.15, 0.0),
	]), ink)
	c.draw_circle(o, r * 0.09, COL_PARCHMENT)


static func _draw_spyglass(c: CanvasItem, o: Vector2, r: float, ink: Color, accent: Color) -> void:
	var d := Vector2(0.76, -0.65).normalized()
	var n := Vector2(-d.y, d.x)
	# Three stepped telescoping tubes.
	var segs := [[-0.78, -0.30, 0.14], [-0.30, 0.22, 0.20], [0.22, 0.78, 0.28]]
	for idx in segs.size():
		var s: Array = segs[idx]
		var a := o + d * (r * float(s[0]))
		var b := o + d * (r * float(s[1]))
		var hw := r * float(s[2])
		var poly := PackedVector2Array([a + n * hw, b + n * hw, b - n * hw, a - n * hw])
		c.draw_colored_polygon(poly, accent if idx == 1 else ink)
		c.draw_line(b + n * (hw * 1.18), b - n * (hw * 1.18), ink, 2.4, true)


static func _draw_lantern(c: CanvasItem, o: Vector2, r: float, ink: Color, accent: Color) -> void:
	# Bail handle, roof cap, glass cage & glowing flame teardrop.
	c.draw_arc(o + Vector2(0.0, -r * 0.64), r * 0.22, PI, TAU, 12, ink, 2.2, true)
	c.draw_colored_polygon(PackedVector2Array([
		o + Vector2(0.0, -r * 0.62),
		o + Vector2(r * 0.50, -r * 0.30),
		o + Vector2(-r * 0.50, -r * 0.30),
	]), ink)
	c.draw_rect(Rect2(o + Vector2(-r * 0.36, -r * 0.30), Vector2(r * 0.72, r * 0.74)), ink, false, 2.6)
	c.draw_rect(Rect2(o + Vector2(-r * 0.48, r * 0.44), Vector2(r * 0.96, r * 0.24)), ink, true)
	# Glowing flame diamond inside.
	c.draw_colored_polygon(PackedVector2Array([
		o + Vector2(0.0, -r * 0.18),
		o + Vector2(r * 0.18, r * 0.12),
		o + Vector2(0.0, r * 0.32),
		o + Vector2(-r * 0.18, r * 0.12),
	]), accent)


static func _draw_map(c: CanvasItem, o: Vector2, r: float, ink: Color, accent: Color) -> void:
	# Rolled parchment scroll with top/bottom rollers & red X.
	c.draw_rect(Rect2(o + Vector2(-r * 0.58, -r * 0.48), Vector2(r * 1.16, r * 0.96)), ink, false, 2.4)
	c.draw_line(o + Vector2(-r * 0.74, -r * 0.52), o + Vector2(r * 0.74, -r * 0.52), ink, 4.2, true)
	c.draw_line(o + Vector2(-r * 0.74, r * 0.52), o + Vector2(r * 0.74, r * 0.52), ink, 4.2, true)
	# Island loop & bold red X.
	c.draw_arc(o + Vector2(-r * 0.16, r * 0.04), r * 0.24, 0.0, TAU, 10, ink, 1.6, true)
	var xc := o + Vector2(r * 0.18, -r * 0.04)
	var xr := r * 0.22
	c.draw_line(xc + Vector2(-xr, -xr), xc + Vector2(xr, xr), accent, 3.0, true)
	c.draw_line(xc + Vector2(-xr, xr), xc + Vector2(xr, -xr), accent, 3.0, true)


static func _draw_shovel(c: CanvasItem, o: Vector2, r: float, ink: Color, accent: Color) -> void:
	# Diagonal heavy spade from top-left D-handle to bottom-right iron blade.
	c.draw_line(o + Vector2(-r * 0.46, -r * 0.46), o + Vector2(r * 0.22, r * 0.22), ink, 3.6, true)
	# D-grip at top-left.
	c.draw_arc(o + Vector2(-r * 0.56, -r * 0.56), r * 0.18, 0.0, TAU, 12, accent, 2.6, true)
	# Tapered spade blade at bottom-right.
	c.draw_colored_polygon(PackedVector2Array([
		o + Vector2(r * 0.06, r * 0.34),
		o + Vector2(r * 0.34, r * 0.06),
		o + Vector2(r * 0.68, r * 0.44),
		o + Vector2(r * 0.74, r * 0.74),
		o + Vector2(r * 0.44, r * 0.68),
	]), ink)


static func _draw_bucket(c: CanvasItem, o: Vector2, r: float, ink: Color, accent: Color) -> void:
	# Bail arch + tapered barrel bucket + iron bands + water rim.
	c.draw_arc(o + Vector2(0.0, -r * 0.22), r * 0.46, PI, TAU, 14, ink, 2.4, true)
	var body := PackedVector2Array([
		o + Vector2(-r * 0.52, -r * 0.22),
		o + Vector2(r * 0.52, -r * 0.22),
		o + Vector2(r * 0.38, r * 0.64),
		o + Vector2(-r * 0.38, r * 0.64),
	])
	c.draw_colored_polygon(body, ink)
	c.draw_line(o + Vector2(-r * 0.46, r * 0.04), o + Vector2(r * 0.46, r * 0.04), COL_PARCHMENT, 2.2, true)
	c.draw_line(o + Vector2(-r * 0.40, r * 0.40), o + Vector2(r * 0.40, r * 0.40), COL_PARCHMENT, 2.2, true)
	c.draw_line(o + Vector2(-r * 0.38, -r * 0.14), o + Vector2(r * 0.38, -r * 0.14), accent, 3.0, true)


static func _draw_planks(c: CanvasItem, o: Vector2, r: float, ink: Color, accent: Color) -> void:
	# Two crossed sturdy oak repair planks with bright nail dots.
	for ang in [-0.42, 0.42]:
		var d := Vector2(cos(ang), sin(ang))
		var n := Vector2(-d.y, d.x)
		var l := r * 0.72
		var hw := r * 0.18
		var poly := PackedVector2Array([
			o - d * l + n * hw, o + d * l + n * hw,
			o + d * l - n * hw, o - d * l - n * hw,
		])
		c.draw_colored_polygon(poly, ink)
		c.draw_circle(o + d * (l * 0.72), r * 0.07, accent)
		c.draw_circle(o - d * (l * 0.72), r * 0.07, accent)


static func _draw_tankard(c: CanvasItem, o: Vector2, r: float, ink: Color, accent: Color) -> void:
	# Banded grog mug + side handle + frothy foam puffs.
	c.draw_rect(Rect2(o + Vector2(-r * 0.48, -r * 0.24), Vector2(r * 0.72, r * 0.88)), ink, true)
	c.draw_arc(o + Vector2(r * 0.24, r * 0.20), r * 0.28, -PI * 0.48, PI * 0.48, 12, ink, 3.2, true)
	c.draw_line(o + Vector2(-r * 0.48, r * 0.04), o + Vector2(r * 0.24, r * 0.04), COL_PARCHMENT, 2.0, true)
	c.draw_line(o + Vector2(-r * 0.48, r * 0.42), o + Vector2(r * 0.24, r * 0.42), COL_PARCHMENT, 2.0, true)
	# Frothy foam top puffs.
	c.draw_circle(o + Vector2(-r * 0.28, -r * 0.34), r * 0.22, accent)
	c.draw_circle(o + Vector2(-r * 0.06, -r * 0.42), r * 0.24, accent)
	c.draw_circle(o + Vector2(r * 0.14, -r * 0.30), r * 0.20, accent)


static func _draw_instrument(c: CanvasItem, o: Vector2, r: float, ink: Color, accent: Color) -> void:
	# Concertina endplates + pleated zig-zag bellows!
	c.draw_rect(Rect2(o + Vector2(-r * 0.74, -r * 0.48), Vector2(r * 0.26, r * 0.96)), ink, true)
	c.draw_rect(Rect2(o + Vector2(r * 0.48, -r * 0.48), Vector2(r * 0.26, r * 0.96)), ink, true)
	for i in 4:
		var x := lerpf(-r * 0.38, r * 0.38, float(i) / 3.0)
		c.draw_line(o + Vector2(x, -r * 0.42), o + Vector2(x, r * 0.42), accent, 2.6, true)
	c.draw_line(o + Vector2(-r * 0.48, -r * 0.38), o + Vector2(r * 0.48, -r * 0.38), ink, 2.0, true)
	c.draw_line(o + Vector2(-r * 0.48, r * 0.38), o + Vector2(r * 0.48, r * 0.38), ink, 2.0, true)


# ==============================================================================
# Crew Command Wheel icons
# ==============================================================================

static func _draw_helm(c: CanvasItem, o: Vector2, r: float, ink: Color, accent: Color) -> void:
	c.draw_arc(o, r * 0.56, 0.0, TAU, 24, ink, 3.0, true)
	c.draw_circle(o, r * 0.16, accent)
	for i in 8:
		var a := float(i) / 8.0 * TAU
		var d := Vector2(cos(a), sin(a))
		c.draw_line(o + d * (r * 0.16), o + d * (r * 0.80), ink, 2.5, true)


static func _draw_sail(c: CanvasItem, o: Vector2, r: float, ink: Color, accent: Color) -> void:
	# Mast, yardarm, billowing square sail & wind swoosh.
	c.draw_line(o + Vector2(0.0, -r * 0.76), o + Vector2(0.0, r * 0.76), ink, 3.0, true)
	c.draw_line(o + Vector2(-r * 0.62, -r * 0.52), o + Vector2(r * 0.62, -r * 0.52), ink, 3.2, true)
	var sail := PackedVector2Array([
		o + Vector2(-r * 0.54, -r * 0.46),
		o + Vector2(r * 0.54, -r * 0.46),
		o + Vector2(r * 0.68, r * 0.02),
		o + Vector2(r * 0.48, r * 0.44),
		o + Vector2(-r * 0.48, r * 0.44),
		o + Vector2(-r * 0.34, r * 0.02),
	])
	c.draw_colored_polygon(sail, ink)
	c.draw_line(o + Vector2(-r * 0.78, -r * 0.10), o + Vector2(-r * 0.44, -r * 0.10), accent, 2.4, true)
	c.draw_line(o + Vector2(-r * 0.72, r * 0.18), o + Vector2(-r * 0.40, r * 0.18), accent, 2.4, true)


static func _draw_anchor(c: CanvasItem, o: Vector2, r: float, ink: Color, accent: Color, is_drop: bool) -> void:
	c.draw_arc(o + Vector2(0.0, -r * 0.58), r * 0.16, 0.0, TAU, 12, ink, 2.4, true)
	c.draw_line(o + Vector2(0.0, -r * 0.42), o + Vector2(0.0, r * 0.56), ink, 3.2, true)
	c.draw_line(o + Vector2(-r * 0.34, -r * 0.24), o + Vector2(r * 0.34, -r * 0.24), ink, 2.8, true)
	c.draw_arc(o + Vector2(0.0, r * 0.14), r * 0.48, 0.22, PI - 0.22, 16, ink, 3.2, true)
	# Directional chevron (down for drop, up for raise).
	var cy := o.y + (r * 0.74 if is_drop else -r * 0.82)
	var dy := r * 0.20 if is_drop else -r * 0.20
	c.draw_line(Vector2(o.x - r * 0.26, cy - dy), Vector2(o.x, cy), accent, 3.0, true)
	c.draw_line(Vector2(o.x + r * 0.26, cy - dy), Vector2(o.x, cy), accent, 3.0, true)


static func _draw_cannon(c: CanvasItem, o: Vector2, r: float, ink: Color, accent: Color) -> void:
	# Broadside cannon barrel + carriage wheel + muzzle blast star.
	var barrel := PackedVector2Array([
		o + Vector2(-r * 0.64, -r * 0.04),
		o + Vector2(r * 0.42, -r * 0.44),
		o + Vector2(r * 0.56, -r * 0.10),
		o + Vector2(-r * 0.46, r * 0.34),
	])
	c.draw_colored_polygon(barrel, ink)
	c.draw_arc(o + Vector2(-r * 0.24, r * 0.44), r * 0.24, 0.0, TAU, 14, ink, 3.0, true)
	c.draw_circle(o + Vector2(-r * 0.24, r * 0.44), r * 0.08, accent)
	# Muzzle spark star.
	var sp := o + Vector2(r * 0.66, -r * 0.36)
	c.draw_line(sp + Vector2(-r * 0.16, 0.0), sp + Vector2(r * 0.16, 0.0), accent, 2.4, true)
	c.draw_line(sp + Vector2(0.0, -r * 0.16), sp + Vector2(0.0, r * 0.16), accent, 2.4, true)


static func _draw_repair(c: CanvasItem, o: Vector2, r: float, ink: Color, accent: Color) -> void:
	# Crossed carpenter's hammer and repair plank.
	c.draw_line(o + Vector2(-r * 0.52, r * 0.56), o + Vector2(r * 0.36, -r * 0.32), ink, 3.8, true)
	var head := PackedVector2Array([
		o + Vector2(r * 0.10, -r * 0.58),
		o + Vector2(r * 0.64, -r * 0.06),
		o + Vector2(r * 0.46, r * 0.12),
		o + Vector2(-r * 0.08, -r * 0.40),
	])
	c.draw_colored_polygon(head, accent)
	c.draw_line(o + Vector2(-r * 0.56, -r * 0.34), o + Vector2(r * 0.48, r * 0.52), ink, 4.8, true)


static func _draw_follow(c: CanvasItem, o: Vector2, r: float, ink: Color, accent: Color) -> void:
	# Double forward march chevrons + leader star.
	for off_y in [r * 0.18, -r * 0.22]:
		c.draw_line(o + Vector2(-r * 0.46, off_y + r * 0.26), o + Vector2(0.0, off_y - r * 0.22), ink, 3.4, true)
		c.draw_line(o + Vector2(r * 0.46, off_y + r * 0.26), o + Vector2(0.0, off_y - r * 0.22), ink, 3.4, true)
	c.draw_circle(o + Vector2(0.0, -r * 0.60), r * 0.14, accent)


static func _draw_chest(c: CanvasItem, o: Vector2, r: float, ink: Color, accent: Color) -> void:
	# Banded pirate treasure chest with gold lock clasp.
	c.draw_rect(Rect2(o + Vector2(-r * 0.60, -r * 0.10), Vector2(r * 1.20, r * 0.66)), ink, true)
	var lid := PackedVector2Array([
		o + Vector2(-r * 0.62, -r * 0.16),
		o + Vector2(-r * 0.46, -r * 0.50),
		o + Vector2(r * 0.46, -r * 0.50),
		o + Vector2(r * 0.62, -r * 0.16),
	])
	c.draw_colored_polygon(lid, ink)
	c.draw_line(o + Vector2(-r * 0.60, -r * 0.12), o + Vector2(r * 0.60, -r * 0.12), COL_PARCHMENT, 2.2, true)
	c.draw_rect(Rect2(o + Vector2(-r * 0.14, -r * 0.22), Vector2(r * 0.28, r * 0.30)), accent, true)
