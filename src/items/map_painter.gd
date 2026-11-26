class_name MapPainter
extends RefCounted
## Procedural parchment-and-ink texture painter for held treasure maps.
##
## Produces a rich aged-vellum ImageTexture featuring a cached fibrous parchment
## base, double sepia border, coastal depth rings, island terrain contours,
## an 8-point compass rose with North glyph, dotted trail ticks, and a bold
## hand-brushed crimson X marking the buried dig site.

const DEFAULT_SIZE := 256

const COL_PARCHMENT_CENTER := Color(0.91, 0.84, 0.68, 1.0)
const COL_PARCHMENT_EDGE := Color(0.71, 0.58, 0.39, 1.0)
const COL_SEA_RIPPLE := Color(0.50, 0.58, 0.54, 1.0)
const COL_BEACH := Color(0.84, 0.74, 0.52, 1.0)
const COL_LOWLAND := Color(0.68, 0.70, 0.46, 1.0)
const COL_HIGHLAND := Color(0.57, 0.53, 0.40, 1.0)
const COL_INK_DARK := Color(0.22, 0.14, 0.09, 1.0)
const COL_INK_MID := Color(0.42, 0.30, 0.20, 1.0)
const COL_INK_FAINT := Color(0.60, 0.49, 0.34, 1.0)
const COL_CRIMSON := Color(0.76, 0.11, 0.09, 1.0)
const COL_CRIMSON_DARK := Color(0.48, 0.06, 0.05, 1.0)

static var _cached_base: Dictionary = {}  # int size -> PackedByteArray (no static Resource leak)


## Render a complete parchment treasure map texture for `island_name`.
## `contour_points` are island-local XZ vertices (Vector2(x, z)), where -Z is North
## (up on the map) and +X is East (right). `dig_local_pos` is island-local XZ.
static func render_treasure_map(
	island_name: String,
	contour_points: PackedVector2Array,
	dig_local_pos: Vector2,
	island_radius: float = 120.0,
	size: int = DEFAULT_SIZE
) -> ImageTexture:
	var img := render_treasure_map_image(island_name, contour_points, dig_local_pos, island_radius, size)
	return ImageTexture.create_from_image(img)


## Render the raw Image for a treasure map (useful for inspection or custom textures).
static func render_treasure_map_image(
	island_name: String,
	contour_points: PackedVector2Array,
	dig_local_pos: Vector2,
	island_radius: float = 120.0,
	size: int = DEFAULT_SIZE
) -> Image:
	var res := clampi(size, 128, 512)
	var img := _get_parchment_base(res).duplicate() as Image
	var r_world := maxf(island_radius, 12.0)

	var pts := contour_points
	if pts.size() < 3:
		pts = generate_fallback_contour(island_name, r_world)

	var center := Vector2(res * 0.5, res * 0.52)
	var scale_px := (res * 0.34) / r_world

	# Convert island-local XZ (X right, Z south/down) to map pixel coords.
	var poly := PackedVector2Array()
	poly.resize(pts.size())
	for i in pts.size():
		poly[i] = center + Vector2(pts[i].x, pts[i].y) * scale_px

	# Faint nautical rhumb lines radiating from the compass rose corner.
	var rose_pos := Vector2(res * 0.80, res * 0.21)
	_draw_rhumb_lines(img, rose_pos, res)

	# Outer coastal ripple rings around the island silhouette.
	_stroke_polygon_scaled(img, poly, center, 1.13, COL_SEA_RIPPLE, 1.2, 0.35)
	_stroke_polygon_scaled(img, poly, center, 1.06, COL_SEA_RIPPLE, 1.4, 0.50)

	# Island terrain bands: sandy beach, green lowland, rocky highland crest.
	_fill_polygon(img, poly, COL_BEACH, 0.88)
	var mid_poly := _scale_polygon(poly, center, 0.72)
	_fill_polygon(img, mid_poly, COL_LOWLAND, 0.78)
	var high_poly := _scale_polygon(poly, center, 0.42)
	_fill_polygon(img, high_poly, COL_HIGHLAND, 0.65)

	# Hand-inked topographic contour lines + dark outer shoreline.
	_stroke_polygon(img, mid_poly, COL_INK_MID, 1.1, 0.55)
	_stroke_polygon(img, high_poly, COL_INK_MID, 1.0, 0.45)
	_stroke_polygon(img, poly, COL_INK_DARK, 2.2, 0.95)

	# Dotted path from the southern cove toward the dig site.
	var dig_px := center + Vector2(dig_local_pos.x, dig_local_pos.y) * scale_px
	dig_px.x = clampf(dig_px.x, res * 0.16, res * 0.84)
	dig_px.y = clampf(dig_px.y, res * 0.18, res * 0.84)
	var landing_px := _nearest_contour_point(poly, dig_px + Vector2(0.0, res * 0.18))
	_draw_dotted_trail(img, landing_px, dig_px)

	# Bold hand-painted crimson X at the buried dig site!
	_draw_red_x(img, dig_px, res * 0.055)

	# Decorative 8-point compass rose + North marker.
	_draw_compass_rose(img, rose_pos, res * 0.10)

	# Double-line sepia cartographer's border and title ribbon at top-left.
	_draw_border_frame(img, res)
	_draw_title_cartouche(img, island_name, res)
	return img


## Generate a natural cove-shaped procedural island contour when none is provided.
static func generate_fallback_contour(island_name: String, radius: float = 120.0) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(island_name) ^ 0x51A7D
	var count := 20
	var p1 := rng.randf_range(0.0, TAU)
	var p2 := rng.randf_range(0.0, TAU)
	var p3 := rng.randf_range(0.0, TAU)
	var cove_ang := rng.randf_range(0.4, 2.5)
	var pts := PackedVector2Array()
	pts.resize(count)
	for i in count:
		var a := float(i) / float(count) * TAU
		var lobe := 0.80 + 0.16 * sin(a * 2.0 + p1) + 0.11 * cos(a * 3.0 + p2) + 0.06 * sin(a * 5.0 + p3)
		var cove_d := absf(wrapf(a - cove_ang, -PI, PI))
		if cove_d < 0.55:
			lobe -= 0.24 * cos(cove_d / 0.55 * PI * 0.5)
		var r := radius * clampf(lobe, 0.42, 1.05)
		pts[i] = Vector2(cos(a) * r, sin(a) * r)
	return pts


static func _get_parchment_base(size: int) -> Image:
	if _cached_base.has(size):
		return Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, _cached_base[size] as PackedByteArray)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var inv := 1.0 / float(size - 1)
	for y in size:
		var ny := float(y) * inv * 2.0 - 1.0
		var fy := sin(float(y) * 0.37) * 0.012
		for x in size:
			var nx := float(x) * inv * 2.0 - 1.0
			var edge_d := maxf(absf(nx), absf(ny))
			var radial := sqrt(nx * nx + ny * ny)
			var vig := clampf(pow(maxf(edge_d, radial * 0.72), 2.1) * 0.82, 0.0, 1.0)
			# Deterministic fibrous paper mottling + subtle tea-stain ring.
			var h := sin(float(x) * 0.17 + float(y) * 0.13) * cos(float(x) * 0.09 - float(y) * 0.21)
			var grain := fy + sin(float(x) * 0.53) * 0.008 + h * 0.025
			var stain_d := Vector2(nx + 0.38, ny - 0.34).length()
			var stain := smoothstep(0.46, 0.14, stain_d) * 0.07
			var col := COL_PARCHMENT_CENTER.lerp(COL_PARCHMENT_EDGE, clampf(vig + stain, 0.0, 1.0))
			col.r = clampf(col.r + grain, 0.0, 1.0)
			col.g = clampf(col.g + grain * 0.9, 0.0, 1.0)
			col.b = clampf(col.b + grain * 0.75, 0.0, 1.0)
			img.set_pixel(x, y, col)
	_cached_base[size] = img.get_data()
	return img


static func _blend_pixel(img: Image, x: int, y: int, col: Color, alpha: float) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	var a := clampf(alpha * col.a, 0.0, 1.0)
	if a <= 0.002:
		return
	var dst := img.get_pixel(x, y)
	img.set_pixel(x, y, dst.lerp(Color(col.r, col.g, col.b, 1.0), a))


static func _draw_line(img: Image, a: Vector2, b: Vector2, col: Color, width: float = 1.5, alpha: float = 1.0) -> void:
	var dist := a.distance_to(b)
	var steps := maxi(1, int(ceilf(dist * 1.4)))
	var rad := maxf(0.5, width * 0.5)
	var irad := int(ceilf(rad))
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		var cx := int(roundf(p.x))
		var cy := int(roundf(p.y))
		for dy in range(-irad, irad + 1):
			for dx in range(-irad, irad + 1):
				var px := cx + dx
				var py := cy + dy
				var d := Vector2(float(px) - p.x, float(py) - p.y).length()
				if d <= rad + 0.65:
					var cov := clampf((rad + 0.65 - d) / 1.1, 0.0, 1.0)
					_blend_pixel(img, px, py, col, alpha * cov)


static func _draw_circle_outline(img: Image, center: Vector2, radius: float, col: Color, width: float = 1.4, alpha: float = 1.0) -> void:
	var segs := maxi(16, int(radius * 1.5))
	var prev := center + Vector2(radius, 0.0)
	for i in range(1, segs + 1):
		var a := float(i) / float(segs) * TAU
		var cur := center + Vector2(cos(a), sin(a)) * radius
		_draw_line(img, prev, cur, col, width, alpha)
		prev = cur


static func _scale_polygon(poly: PackedVector2Array, center: Vector2, factor: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(poly.size())
	for i in poly.size():
		out[i] = center + (poly[i] - center) * factor
	return out


static func _stroke_polygon(img: Image, poly: PackedVector2Array, col: Color, width: float, alpha: float) -> void:
	var n := poly.size()
	if n < 2:
		return
	for i in n:
		_draw_line(img, poly[i], poly[(i + 1) % n], col, width, alpha)


static func _stroke_polygon_scaled(img: Image, poly: PackedVector2Array, center: Vector2, factor: float, col: Color, width: float, alpha: float) -> void:
	_stroke_polygon(img, _scale_polygon(poly, center, factor), col, width, alpha)


static func _fill_polygon(img: Image, poly: PackedVector2Array, col: Color, alpha: float) -> void:
	var n := poly.size()
	if n < 3:
		return
	var min_y := img.get_height()
	var max_y := 0
	for p in poly:
		min_y = mini(min_y, int(floorf(p.y)))
		max_y = maxi(max_y, int(ceilf(p.y)))
	min_y = clampi(min_y, 0, img.get_height() - 1)
	max_y = clampi(max_y, 0, img.get_height() - 1)

	var xs: Array[float] = []
	for y in range(min_y, max_y + 1):
		xs.clear()
		var fy := float(y) + 0.5
		for i in n:
			var a := poly[i]
			var b := poly[(i + 1) % n]
			if (a.y <= fy and b.y > fy) or (b.y <= fy and a.y > fy):
				var t := (fy - a.y) / (b.y - a.y)
				xs.append(a.x + t * (b.x - a.x))
		if xs.size() < 2:
			continue
		xs.sort()
		var idx := 0
		while idx + 1 < xs.size():
			var x0 := clampi(int(ceilf(xs[idx])), 0, img.get_width() - 1)
			var x1 := clampi(int(floorf(xs[idx + 1])), 0, img.get_width() - 1)
			for x in range(x0, x1 + 1):
				_blend_pixel(img, x, y, col, alpha)
			idx += 2


static func _nearest_contour_point(poly: PackedVector2Array, target: Vector2) -> Vector2:
	if poly.is_empty():
		return target
	var best := poly[0]
	var best_d := target.distance_squared_to(best)
	for p in poly:
		var d := target.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = p
	return best


static func _draw_dotted_trail(img: Image, start: Vector2, finish: Vector2) -> void:
	var dir := finish - start
	var dist := dir.length()
	if dist < 10.0:
		return
	var u := dir / dist
	var pos := 6.0
	while pos < dist - 10.0:
		var p0 := start + u * pos
		var p1 := start + u * minf(pos + 3.2, dist - 10.0)
		_draw_line(img, p0, p1, COL_INK_DARK, 1.4, 0.72)
		pos += 7.5


static func _draw_red_x(img: Image, center: Vector2, half: float) -> void:
	var r := maxf(half, 7.0)
	# Subtle inked halo behind the crimson X for immediate readability.
	_draw_circle_outline(img, center, r * 1.38, COL_CRIMSON_DARK, 1.2, 0.42)
	var a1 := center + Vector2(-r, -r * 0.92)
	var b1 := center + Vector2(r, r * 0.95)
	var a2 := center + Vector2(-r * 0.94, r)
	var b2 := center + Vector2(r * 0.96, -r * 0.94)
	# Dark outline pass, then rich crimson brush pass.
	_draw_line(img, a1, b1, COL_CRIMSON_DARK, r * 0.44, 0.85)
	_draw_line(img, a2, b2, COL_CRIMSON_DARK, r * 0.44, 0.85)
	_draw_line(img, a1, b1, COL_CRIMSON, r * 0.28, 0.98)
	_draw_line(img, a2, b2, COL_CRIMSON, r * 0.28, 0.98)


static func _draw_rhumb_lines(img: Image, origin: Vector2, res: int) -> void:
	var reach := float(res) * 1.25
	for i in 12:
		var a := float(i) / 12.0 * TAU
		_draw_line(img, origin, origin + Vector2(cos(a), sin(a)) * reach, COL_INK_FAINT, 1.0, 0.22)


static func _draw_compass_rose(img: Image, center: Vector2, radius: float) -> void:
	_draw_circle_outline(img, center, radius * 0.72, COL_INK_DARK, 1.2, 0.78)
	_draw_circle_outline(img, center, radius * 0.56, COL_INK_MID, 1.0, 0.55)
	# Minor intercardinal spokes.
	for i in 4:
		var a := (float(i) + 0.5) * PI * 0.5
		var tip := center + Vector2(cos(a), sin(a)) * (radius * 0.76)
		_draw_line(img, center, tip, COL_INK_MID, 1.6, 0.78)
	# Major cardinal spikes (North highlighted crimson!).
	var dirs := [Vector2(0.0, -1.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(-1.0, 0.0)]
	for i in 4:
		var d: Vector2 = dirs[i]
		var side := Vector2(-d.y, d.x)
		var tip := center + d * radius
		var p_l := center + side * (radius * 0.19)
		var p_r := center - side * (radius * 0.19)
		var col := COL_CRIMSON if i == 0 else COL_INK_DARK
		_fill_polygon(img, PackedVector2Array([center, tip, p_l]), col, 0.95)
		_fill_polygon(img, PackedVector2Array([center, tip, p_r]), COL_INK_MID if i != 0 else COL_CRIMSON_DARK, 0.72)
	# Tiny hand-inked "N" above North tip.
	var ny := center.y - radius - 4.0
	var nh := maxf(5.0, radius * 0.28)
	var nw := nh * 0.65
	var n0 := Vector2(center.x - nw * 0.5, ny)
	var n1 := Vector2(center.x - nw * 0.5, ny - nh)
	var n2 := Vector2(center.x + nw * 0.5, ny)
	var n3 := Vector2(center.x + nw * 0.5, ny - nh)
	_draw_line(img, n0, n1, COL_CRIMSON, 1.5, 0.95)
	_draw_line(img, n1, n2, COL_CRIMSON, 1.4, 0.95)
	_draw_line(img, n2, n3, COL_CRIMSON, 1.5, 0.95)


static func _draw_border_frame(img: Image, res: int) -> void:
	var m1 := maxi(8, int(roundf(res * 0.042)))
	var m2 := m1 + maxi(4, int(roundf(res * 0.018)))
	_draw_rect_outline(img, m1, m1, res - 1 - m1, res - 1 - m1, COL_INK_DARK, 1.6, 0.85)
	_draw_rect_outline(img, m2, m2, res - 1 - m2, res - 1 - m2, COL_INK_MID, 1.0, 0.60)
	# Nautical scale ticks along borders.
	var ticks := 8
	for i in range(1, ticks):
		var u := lerpf(float(m2), float(res - 1 - m2), float(i) / float(ticks))
		_draw_line(img, Vector2(u, float(m1)), Vector2(u, float(m2)), COL_INK_DARK, 1.1, 0.70)
		_draw_line(img, Vector2(u, float(res - 1 - m2)), Vector2(u, float(res - 1 - m1)), COL_INK_DARK, 1.1, 0.70)
		_draw_line(img, Vector2(float(m1), u), Vector2(float(m2), u), COL_INK_DARK, 1.1, 0.70)
		_draw_line(img, Vector2(float(res - 1 - m2), u), Vector2(float(res - 1 - m1), u), COL_INK_DARK, 1.1, 0.70)


static func _draw_rect_outline(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color, width: float, alpha: float) -> void:
	_draw_line(img, Vector2(x0, y0), Vector2(x1, y0), col, width, alpha)
	_draw_line(img, Vector2(x1, y0), Vector2(x1, y1), col, width, alpha)
	_draw_line(img, Vector2(x1, y1), Vector2(x0, y1), col, width, alpha)
	_draw_line(img, Vector2(x0, y1), Vector2(x0, y0), col, width, alpha)


static func _draw_title_cartouche(img: Image, island_name: String, res: int) -> void:
	# Small inked scroll cartouche in upper-left with stylized calligraphic stroke pattern.
	var x0 := int(roundf(res * 0.09))
	var y0 := int(roundf(res * 0.09))
	var w := int(roundf(res * 0.44))
	var h := int(roundf(res * 0.095))
	_draw_rect_outline(img, x0, y0, x0 + w, y0 + h, COL_INK_DARK, 1.2, 0.75)
	_draw_line(img, Vector2(x0 + 4, y0 + h - 3), Vector2(x0 + w - 4, y0 + h - 3), COL_INK_MID, 1.0, 0.50)
	# Stylized inked script strokes proportional to island_name characters.
	var letters := mini(maxi(island_name.length(), 4), 16)
	var step := float(w - 14) / float(letters)
	var cy := float(y0) + float(h) * 0.48
	for i in letters:
		var ch := island_name.unicode_at(i) if i < island_name.length() else 65
		if ch == 32:
			continue
		var lx := float(x0 + 7) + float(i) * step
		var tall := float(h) * (0.28 if (ch % 3 == 0) else 0.17)
		_draw_line(img, Vector2(lx, cy + tall * 0.6), Vector2(lx + step * 0.65, cy - tall), COL_INK_DARK, 1.2, 0.78)
		if ch % 2 == 0:
			_draw_line(img, Vector2(lx, cy - tall * 0.4), Vector2(lx + step * 0.6, cy + tall * 0.5), COL_INK_DARK, 1.0, 0.65)


# ==============================================================================
# Diegetic Parchment Scrolls & Wanted Bounty Posters (512x512)
# ==============================================================================

const SCROLL_SIZE := 512
const COL_SINGE := Color(0.24, 0.15, 0.08, 1.0)
const COL_BANNER_CREAM := Color(0.95, 0.89, 0.75, 1.0)
const COL_SKULL_IVORY := Color(0.95, 0.90, 0.78, 1.0)
const COL_SKULL_SHADE := Color(0.76, 0.67, 0.52, 1.0)
const COL_HAT_CHARCOAL := Color(0.19, 0.15, 0.12, 1.0)
const COL_GOLD_TRIM := Color(0.88, 0.66, 0.20, 1.0)
const COL_BLADE_STEEL := Color(0.84, 0.82, 0.74, 1.0)
const COL_EYE_GLOW_OUTER := Color(0.98, 0.36, 0.08, 1.0)
const COL_EYE_GLOW_CORE := Color(1.00, 0.92, 0.46, 1.0)
const COL_WAX_HI := Color(0.92, 0.24, 0.18, 1.0)

## Compact crisp 5x7 uppercase + digit + punctuation bitmap ink font (5 bits per row, MSB left).
const FONT_5X7 := {
	"A": [0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
	"B": [0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E],
	"C": [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E],
	"D": [0x1C, 0x12, 0x11, 0x11, 0x11, 0x12, 0x1C],
	"E": [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F],
	"F": [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10],
	"G": [0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F],
	"H": [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
	"I": [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E],
	"J": [0x07, 0x02, 0x02, 0x02, 0x12, 0x12, 0x0C],
	"K": [0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11],
	"L": [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F],
	"M": [0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11],
	"N": [0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11],
	"O": [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
	"P": [0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10],
	"Q": [0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D],
	"R": [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11],
	"S": [0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E],
	"T": [0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04],
	"U": [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
	"V": [0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04],
	"W": [0x11, 0x11, 0x11, 0x15, 0x15, 0x1B, 0x11],
	"X": [0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11],
	"Y": [0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04],
	"Z": [0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F],
	"0": [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E],
	"1": [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E],
	"2": [0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F],
	"3": [0x1E, 0x01, 0x01, 0x0E, 0x01, 0x01, 0x1E],
	"4": [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02],
	"5": [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E],
	"6": [0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E],
	"7": [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],
	"8": [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E],
	"9": [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C],
	".": [0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C],
	",": [0x00, 0x00, 0x00, 0x00, 0x04, 0x04, 0x08],
	":": [0x00, 0x04, 0x04, 0x00, 0x04, 0x04, 0x00],
	"'": [0x04, 0x04, 0x08, 0x00, 0x00, 0x00, 0x00],
	"-": [0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00],
	"!": [0x04, 0x04, 0x04, 0x04, 0x04, 0x00, 0x04],
	"?": [0x0E, 0x11, 0x01, 0x02, 0x04, 0x00, 0x04],
	"/": [0x01, 0x02, 0x02, 0x04, 0x08, 0x08, 0x10],
	"*": [0x00, 0x15, 0x0E, 0x1F, 0x0E, 0x15, 0x00],
	" ": [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
}


## Convenience alias matching `paint_riddle_scroll` / `paint_bounty_poster` naming.
static func paint_treasure_map(
	island_name: String,
	contour_points: PackedVector2Array,
	dig_local_pos: Vector2,
	island_radius: float = 120.0,
	size: int = SCROLL_SIZE
) -> ImageTexture:
	return render_treasure_map(island_name, contour_points, dig_local_pos, island_radius, size)


## Paint a 512x512 hand-inked rhyming Riddle Scroll with singed sepia margins,
## double corner flourishes, compass-star header crest, island title banner,
## revealed stanzas + faint mystery dotted lines for locked verses, and a stamped crimson wax seal!
static func paint_riddle_scroll(
	island_name: String,
	stanzas: Array,
	revealed_count: int = 1,
	seed_val: int = 1
) -> ImageTexture:
	var img := paint_riddle_scroll_image(island_name, stanzas, revealed_count, seed_val)
	return ImageTexture.create_from_image(img)


static func paint_riddle_scroll_image(
	island_name: String,
	stanzas: Array,
	revealed_count: int = 1,
	seed_val: int = 1
) -> Image:
	var res := SCROLL_SIZE
	var img := _make_seeded_parchment(res, seed_val)

	# Ornate double sepia frame with decorative hand-inked corner flourishes.
	_draw_ornate_scroll_border(img, res, 20, 29)

	# Compass-star header crest flanked by tapered sepia divider bars.
	var crest_c := Vector2(res * 0.5, 66.0)
	_draw_compass_rose(img, crest_c, 24.0)
	_draw_line(img, Vector2(56.0, 66.0), Vector2(214.0, 66.0), COL_INK_DARK, 1.8, 0.85)
	_draw_line(img, Vector2(68.0, 72.0), Vector2(204.0, 72.0), COL_INK_MID, 1.1, 0.60)
	_draw_line(img, Vector2(298.0, 66.0), Vector2(456.0, 66.0), COL_INK_DARK, 1.8, 0.85)
	_draw_line(img, Vector2(308.0, 72.0), Vector2(444.0, 72.0), COL_INK_MID, 1.1, 0.60)
	_draw_diamond(img, Vector2(56.0, 66.0), 5.0, COL_CRIMSON, 0.90)
	_draw_diamond(img, Vector2(456.0, 66.0), 5.0, COL_CRIMSON, 0.90)

	# Bold island title banner ribbon.
	var bx0 := 56
	var bx1 := 456
	var by0 := 102
	var by1 := 146
	_fill_rect(img, bx0, by0, bx1, by1, COL_BANNER_CREAM, 0.45)
	_draw_rect_outline(img, bx0, by0, bx1, by1, COL_INK_DARK, 2.0, 0.88)
	_draw_rect_outline(img, bx0 + 4, by0 + 4, bx1 - 4, by1 - 4, COL_INK_MID, 1.0, 0.55)
	_draw_line(img, Vector2(bx0 + 18, by1 - 6), Vector2(bx1 - 18, by1 - 6), COL_CRIMSON, 1.5, 0.78)
	var title_str := (island_name if island_name.strip_edges() != "" else "UNCHARTED ISLE").to_upper()
	var title_scale := 3 if title_str.length() <= 19 else 2
	var title_y := by0 + floori(float(by1 - by0 - 7 * title_scale) * 0.5) - 1
	_draw_text_centered(img, title_str, floori(float(res) * 0.5), title_y, title_scale, COL_INK_DARK, 0.96, true)

	# Prepare stanzas (clean fallback if empty).
	var verses: Array[String] = []
	for s in stanzas:
		verses.append(String(s))
	if verses.is_empty():
		verses = [
			"Seek the pale shore where trade winds sigh,",
			"Ten paces north of the weathered palm high,",
			"Strike spade to sand where shadows lie.",
		]
	var max_verses := mini(verses.size(), 4)
	var shown := clampi(revealed_count, 0, max_verses)

	# Render revealed stanzas in crisp hand-inked sepia typography & locked stanzas as faint mystery dots.
	var romans := ["I.", "II.", "III.", "IV."]
	var cursor_y := 166
	var verse_slot_h := 64 if max_verses >= 4 else 76
	for vi in max_verses:
		if vi > 0:
			var sep_y := float(cursor_y - 11)
			_draw_line(img, Vector2(128.0, sep_y), Vector2(236.0, sep_y), COL_INK_FAINT, 1.0, 0.55)
			_draw_diamond(img, Vector2(256.0, sep_y), 3.5, COL_INK_MID, 0.70)
			_draw_line(img, Vector2(276.0, sep_y), Vector2(384.0, sep_y), COL_INK_FAINT, 1.0, 0.55)

		if vi < shown:
			_draw_text_left(img, romans[vi], 50, cursor_y, 2, COL_CRIMSON_DARK, 0.92, true)
			var wrapped := _wrap_text(verses[vi].to_upper(), 27)
			var max_lines := mini(wrapped.size(), 3)
			for li in max_lines:
				_draw_text_left(img, wrapped[li], 106, cursor_y + li * 19, 2, COL_INK_DARK, 0.92, false)
		else:
			# Faint mystery dotted lines with clean centered "? ? ?" gap for locked stanzas!
			_draw_text_left(img, romans[vi], 50, cursor_y, 2, COL_INK_FAINT, 0.56, false)
			for row in 2:
				var dy := float(cursor_y + 7 + row * 19)
				var dx := 112.0
				while dx < 438.0:
					if row != 0 or dx < 230.0 or dx > 314.0:
						_fill_circle(img, Vector2(dx, dy), 2.0, COL_INK_FAINT, 0.58)
					dx += 14.0
			_draw_text_centered(img, "? ? ?", 272, cursor_y, 2, COL_INK_MID, 0.56, false)
		cursor_y += verse_slot_h

	# Calligraphic navigator flourish at bottom-left + stamped crimson wax seal at bottom-right!
	_draw_quill_signature(img, Vector2(66.0, 446.0), 175.0, seed_val)
	_draw_wax_seal(img, Vector2(414.0, 434.0), 34.0, seed_val ^ 0x5EA1)
	return img


## Paint a 512x512 17th-century pirate WANTED Bounty Poster with bold header,
## double crimson rules, hand-inked pirate-captain skull wearing a tricorn hat with
## glowing eyes & crossed cutlasses, captain name, hideout caption, reward banner & wax stamp!
static func paint_bounty_poster(
	captain_name: String,
	island_name: String,
	gold_reward: int,
	seed_val: int = 1
) -> ImageTexture:
	var img := paint_bounty_poster_image(captain_name, island_name, gold_reward, seed_val)
	return ImageTexture.create_from_image(img)


static func paint_bounty_poster_image(
	captain_name: String,
	island_name: String,
	gold_reward: int,
	seed_val: int = 1
) -> Image:
	var res := SCROLL_SIZE
	var img := _make_seeded_parchment(res, seed_val ^ 0xB007)

	# Heavy 17th-century woodblock poster border + iron tack holes at the top corners.
	_draw_ornate_scroll_border(img, res, 18, 27)
	_fill_circle(img, Vector2(38.0, 38.0), 4.5, COL_SINGE, 0.85)
	_fill_circle(img, Vector2(474.0, 38.0), 4.5, COL_SINGE, 0.85)

	# Bold woodblock "WANTED" header + double crimson rule + sub-caption.
	var half_res := floori(float(res) * 0.5)
	_draw_text_centered(img, "WANTED", half_res, 40, 6, COL_INK_DARK, 0.98, true)
	_draw_line(img, Vector2(46.0, 92.0), Vector2(466.0, 92.0), COL_CRIMSON, 3.2, 0.92)
	_draw_line(img, Vector2(46.0, 100.0), Vector2(466.0, 100.0), COL_CRIMSON_DARK, 1.8, 0.85)
	_draw_diamond(img, Vector2(46.0, 96.0), 5.5, COL_CRIMSON_DARK, 0.92)
	_draw_diamond(img, Vector2(466.0, 96.0), 5.5, COL_CRIMSON_DARK, 0.92)
	_draw_text_centered(img, "DEAD OR BANISHED", half_res, 108, 2, COL_CRIMSON_DARK, 0.90, true)

	# Inked portrait frame with woodcut cross-hatching backdrop.
	var px0 := 116
	var py0 := 130
	var px1 := 396
	var py1 := 342
	_fill_rect(img, px0, py0, px1, py1, COL_PARCHMENT_EDGE, 0.34)
	_draw_woodcut_hatching(img, px0 + 4, py0 + 4, px1 - 4, py1 - 4)
	_draw_rect_outline(img, px0, py0, px1, py1, COL_INK_DARK, 2.8, 0.94)
	_draw_rect_outline(img, px0 + 5, py0 + 5, px1 - 5, py1 - 5, COL_INK_MID, 1.2, 0.72)

	# Hand-drawn crossed cutlasses + tricorn-crowned pirate-captain skull with glowing eyes!
	var portrait_c := Vector2(res * 0.5, 246.0)
	_draw_crossed_cutlasses(img, portrait_c)
	_draw_pirate_captain_skull(img, portrait_c, seed_val)

	# Captain name, hideout caption, and bold crimson REWARD banner + crimson wax stamp!
	var cap_str := (captain_name if captain_name.strip_edges() != "" else "CAPTAIN BLACKTIDE").to_upper()
	var cap_scale := 3 if cap_str.length() <= 21 else 2
	_draw_text_centered(img, cap_str, half_res, 354, cap_scale, COL_INK_DARK, 0.97, true)
	_draw_line(img, Vector2(72.0, 382.0), Vector2(440.0, 382.0), COL_INK_MID, 1.4, 0.72)

	var isl_str := (island_name if island_name.strip_edges() != "" else "CUTLASS CAY").to_upper()
	var last_seen := "LAST SEEN: " + isl_str
	if last_seen.length() > 32:
		last_seen = last_seen.substr(0, 32)
	_draw_text_centered(img, last_seen, half_res, 392, 2, COL_INK_DARK, 0.90, false)

	# Reward banner box + stamped crimson wax seal overlapping bottom-right!
	var rx0 := 48
	var rx1 := 376
	var ry0 := 422
	var ry1 := 468
	_fill_rect(img, rx0, ry0, rx1, ry1, COL_BANNER_CREAM, 0.52)
	_draw_rect_outline(img, rx0, ry0, rx1, ry1, COL_CRIMSON_DARK, 2.4, 0.92)
	_draw_rect_outline(img, rx0 + 4, ry0 + 4, rx1 - 4, ry1 - 4, COL_CRIMSON, 1.2, 0.72)
	var rew_str := "REWARD: %d GOLD" % maxi(0, gold_reward)
	var rew_scale := 3 if rew_str.length() <= 16 else 2
	var rew_y := ry0 + floori(float(ry1 - ry0 - 7 * rew_scale) * 0.5)
	_draw_text_centered(img, rew_str, floori(float(rx0 + rx1) * 0.5), rew_y, rew_scale, COL_CRIMSON_DARK, 0.96, true)

	_draw_wax_seal(img, Vector2(422.0, 438.0), 34.0, seed_val ^ 0xC01D)
	return img


static func _make_seeded_parchment(res: int, seed_val: int) -> Image:
	var img := _get_parchment_base(res).duplicate() as Image
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0x7A4C8
	var s1 := Vector2(rng.randf_range(0.18, 0.82), rng.randf_range(0.18, 0.82)) * float(res)
	var s2 := Vector2(rng.randf_range(0.18, 0.82), rng.randf_range(0.18, 0.82)) * float(res)
	var r1 := float(res) * rng.randf_range(0.16, 0.26)
	var r2 := float(res) * rng.randf_range(0.12, 0.20)

	# Singed dark deckled borders + seeded warm tea-stain blotches + subtle scroll-fold creases.
	var margin := float(res) * 0.048
	for y in res:
		var edge_y := minf(float(y), float(res - 1 - y))
		var crease := 0.0
		if absf(float(y) - float(res) * 0.33) < 2.2 or absf(float(y) - float(res) * 0.67) < 2.2:
			crease = 0.045
		for x in res:
			var edge_x := minf(float(x), float(res - 1 - x))
			var edge_d := minf(edge_x, edge_y)
			var singe_wobble := sin(float(x) * 0.07 + float(seed_val)) * 3.5 + cos(float(y) * 0.09 - float(seed_val)) * 3.5
			var singe := clampf(1.0 - (edge_d + singe_wobble) / margin, 0.0, 1.0)
			var d1 := Vector2(float(x) - s1.x, float(y) - s1.y).length() / r1
			var d2 := Vector2(float(x) - s2.x, float(y) - s2.y).length() / r2
			var blotch := (smoothstep(1.0, 0.2, d1) + smoothstep(1.0, 0.2, d2) * 0.8) * 0.08
			var dark_mix := clampf(singe * singe * 0.68 + blotch + crease, 0.0, 0.78)
			if dark_mix > 0.004:
				var dst := img.get_pixel(x, y)
				img.set_pixel(x, y, dst.lerp(COL_SINGE, dark_mix))
	return img


static func _draw_ornate_scroll_border(img: Image, res: int, m1: int, m2: int) -> void:
	_draw_rect_outline(img, m1, m1, res - 1 - m1, res - 1 - m1, COL_INK_DARK, 2.2, 0.88)
	_draw_rect_outline(img, m2, m2, res - 1 - m2, res - 1 - m2, COL_INK_MID, 1.2, 0.65)
	# Decorative double corner flourishes & inward L-scroll brackets at all 4 corners.
	var fl := 24.0
	var corners: Array[Array] = [
		[Vector2(m2, m2), Vector2(1.0, 1.0)],
		[Vector2(res - 1 - m2, m2), Vector2(-1.0, 1.0)],
		[Vector2(res - 1 - m2, res - 1 - m2), Vector2(-1.0, -1.0)],
		[Vector2(m2, res - 1 - m2), Vector2(1.0, -1.0)],
	]
	for c in corners:
		var pt: Vector2 = c[0]
		var s: Vector2 = c[1]
		var h_end := pt + Vector2(s.x * fl, 0.0)
		var v_end := pt + Vector2(0.0, s.y * fl)
		var inner := pt + Vector2(s.x * 11.0, s.y * 11.0)
		_draw_line(img, h_end, pt + Vector2(s.x * fl, s.y * 9.0), COL_INK_DARK, 1.6, 0.82)
		_draw_line(img, v_end, pt + Vector2(s.x * 9.0, s.y * fl), COL_INK_DARK, 1.6, 0.82)
		_draw_line(img, pt, inner, COL_INK_MID, 1.4, 0.72)
		_draw_diamond(img, inner, 4.5, COL_INK_DARK, 0.82)


static func _draw_wax_seal(img: Image, center: Vector2, radius: float, seed_val: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var segs := 22
	var blob := PackedVector2Array()
	blob.resize(segs)
	for i in segs:
		var a := float(i) / float(segs) * TAU
		var wobble := 0.90 + 0.16 * sin(a * 5.0 + float(seed_val)) + rng.randf_range(-0.05, 0.07)
		blob[i] = center + Vector2(cos(a), sin(a)) * (radius * wobble)

	# Drop shadow beneath molten wax, rich crimson wax body, glossy upper-left highlight & recessed stamp rim.
	var shadow_poly := PackedVector2Array()
	shadow_poly.resize(segs)
	for i in segs:
		shadow_poly[i] = blob[i] + Vector2(2.5, 3.0)
	_fill_polygon(img, shadow_poly, COL_SINGE, 0.42)
	_fill_polygon(img, blob, COL_CRIMSON_DARK, 0.96)
	_fill_polygon(img, _scale_polygon(blob, center, 0.88), COL_CRIMSON, 0.96)
	_fill_circle(img, center + Vector2(-radius * 0.24, -radius * 0.24), radius * 0.34, COL_WAX_HI, 0.36)
	_draw_circle_outline(img, center, radius * 0.68, COL_CRIMSON_DARK, 2.2, 0.85)
	_draw_circle_outline(img, center, radius * 0.60, COL_WAX_HI, 1.2, 0.45)

	# Embossed 4-point compass-star & center dot stamped in the molten wax.
	var star_r := radius * 0.44
	var star_dirs := [Vector2(0.0, -1.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(-1.0, 0.0)]
	for d: Vector2 in star_dirs:
		var side := Vector2(-d.y, d.x)
		_fill_polygon(img, PackedVector2Array([
			center, center + d * star_r, center + side * (star_r * 0.24)
		]), COL_WAX_HI, 0.58)
		_fill_polygon(img, PackedVector2Array([
			center, center + d * star_r, center - side * (star_r * 0.24)
		]), COL_CRIMSON_DARK, 0.72)
	_fill_circle(img, center, radius * 0.12, COL_WAX_HI, 0.65)


static func _draw_quill_signature(img: Image, start: Vector2, span_w: float, seed_val: int) -> void:
	var prev := start
	var steps := 24
	for i in range(1, steps + 1):
		var u := float(i) / float(steps)
		var px := start.x + u * span_w
		var py := start.y + sin(u * TAU * 3.5 + float(seed_val)) * (6.0 * (1.0 - u * 0.5)) - u * 5.0
		var cur := Vector2(px, py)
		_draw_line(img, prev, cur, COL_INK_DARK, 1.6 - u * 0.5, 0.72)
		prev = cur
	_draw_line(img, start + Vector2(8.0, 10.0), start + Vector2(span_w * 0.82, 7.0), COL_INK_MID, 1.1, 0.58)


static func _draw_woodcut_hatching(img: Image, x0: int, y0: int, x1: int, y1: int) -> void:
	# Subtle diagonal engraving lines giving the Wanted portrait authentic 17th-century woodcut tone.
	var step := 10
	for s in range(x0 - (y1 - y0), x1, step):
		var p0 := Vector2(float(s), float(y0))
		var p1 := Vector2(float(s + (y1 - y0)), float(y1))
		# Clip line cleanly to portrait rect.
		var t0 := 0.0
		var t1 := 1.0
		var d := p1 - p0
		if absf(d.x) > 0.001:
			var tx0 := (float(x0) - p0.x) / d.x
			var tx1 := (float(x1) - p0.x) / d.x
			t0 = maxf(t0, minf(tx0, tx1))
			t1 = minf(t1, maxf(tx0, tx1))
		if t1 > t0:
			_draw_line(img, p0.lerp(p1, t0), p0.lerp(p1, t1), COL_INK_FAINT, 1.0, 0.24)


static func _draw_crossed_cutlasses(img: Image, center: Vector2) -> void:
	# Twin curved pirate cutlasses crossing diagonally behind the skull, gleaming tips flaring past the tricorn!
	for sg: float in [-1.0, 1.0]:
		var hilt_base := center + Vector2(sg * -102.0, 76.0)
		var guard_c := center + Vector2(sg * -80.0, 58.0)
		var mid_b := center + Vector2(sg * 22.0, -18.0)
		var tip_b := center + Vector2(sg * 124.0, -98.0)
		var back_mid := mid_b + Vector2(sg * -8.0, -11.0)
		var edge_mid := mid_b + Vector2(sg * 11.0, 11.0)
		var blade_poly := PackedVector2Array([
			guard_c + Vector2(sg * -5.0, -6.0),
			back_mid,
			tip_b,
			edge_mid,
			guard_c + Vector2(sg * 6.0, 6.0),
		])
		_fill_polygon(img, blade_poly, COL_BLADE_STEEL, 0.94)
		_stroke_polygon(img, blade_poly, COL_INK_DARK, 2.2, 0.95)
		# Fuller groove down blade spine.
		_draw_line(img, guard_c, tip_b.lerp(back_mid, 0.22), COL_INK_MID, 1.3, 0.68)
		# Brass crossguard & curved D-knuckle bow + wrapped handle + pommel.
		_draw_line(img, hilt_base, guard_c, COL_HAT_CHARCOAL, 7.5, 0.95)
		_draw_line(img, guard_c + Vector2(sg * -10.0, -14.0), guard_c + Vector2(sg * 12.0, 14.0), COL_GOLD_TRIM, 4.2, 0.95)
		_draw_line(img, guard_c + Vector2(sg * 12.0, 14.0), hilt_base + Vector2(sg * 6.0, 10.0), COL_GOLD_TRIM, 3.0, 0.92)
		_fill_circle(img, hilt_base, 6.5, COL_GOLD_TRIM, 0.96)
		_draw_circle_outline(img, hilt_base, 6.5, COL_INK_DARK, 1.5, 0.92)


static func _draw_pirate_captain_skull(img: Image, center: Vector2, seed_val: int) -> void:
	# 1. Bleached-ivory skull cranium + flared cheekbones + grinning jawbone!
	var cranium := PackedVector2Array([
		center + Vector2(-46.0, -40.0),
		center + Vector2(-54.0, -6.0),
		center + Vector2(-48.0, 24.0),
		center + Vector2(-34.0, 40.0),
		center + Vector2(-28.0, 62.0),
		center + Vector2(-16.0, 74.0),
		center + Vector2(16.0, 74.0),
		center + Vector2(28.0, 62.0),
		center + Vector2(34.0, 40.0),
		center + Vector2(48.0, 24.0),
		center + Vector2(54.0, -6.0),
		center + Vector2(46.0, -40.0),
		center + Vector2(0.0, -54.0),
	])
	_fill_polygon(img, cranium, COL_SKULL_IVORY, 0.98)
	# Subtle sepia shading along cheek hollows & lower jaw.
	var jaw_shade := PackedVector2Array([
		center + Vector2(-44.0, 16.0),
		center + Vector2(-32.0, 38.0),
		center + Vector2(-26.0, 62.0),
		center + Vector2(-16.0, 73.0),
		center + Vector2(16.0, 73.0),
		center + Vector2(26.0, 62.0),
		center + Vector2(32.0, 38.0),
		center + Vector2(44.0, 16.0),
		center + Vector2(22.0, 34.0),
		center + Vector2(-22.0, 34.0),
	])
	_fill_polygon(img, jaw_shade, COL_SKULL_SHADE, 0.45)
	_stroke_polygon(img, cranium, COL_INK_DARK, 2.8, 0.96)

	# Weathered pirate brow crack & furrowed brow arches.
	_draw_line(img, center + Vector2(-38.0, -14.0), center + Vector2(-8.0, -8.0), COL_INK_DARK, 2.6, 0.90)
	_draw_line(img, center + Vector2(38.0, -14.0), center + Vector2(8.0, -8.0), COL_INK_DARK, 2.6, 0.90)
	var crack_side := 1.0 if (seed_val % 2 == 0) else -1.0
	_draw_line(img, center + Vector2(crack_side * 16.0, -34.0), center + Vector2(crack_side * 10.0, -20.0), COL_INK_DARK, 1.8, 0.78)
	_draw_line(img, center + Vector2(crack_side * 10.0, -20.0), center + Vector2(crack_side * 18.0, -12.0), COL_INK_DARK, 1.5, 0.72)

	# 2. Deep dark-sepia eye sockets with glowing fiery pirate eyes!
	for sx: float in [-1.0, 1.0]:
		var ec := center + Vector2(sx * 22.0, 4.0)
		var sock := PackedVector2Array([
			ec + Vector2(-14.0, -10.0),
			ec + Vector2(12.0, -12.0),
			ec + Vector2(15.0, 4.0),
			ec + Vector2(6.0, 14.0),
			ec + Vector2(-12.0, 11.0),
		])
		_fill_polygon(img, sock, COL_HAT_CHARCOAL, 0.96)
		_stroke_polygon(img, sock, COL_INK_DARK, 2.0, 0.96)
		# Incandescent fiery eye ember & white-gold spark center!
		_fill_circle(img, ec + Vector2(0.0, 1.0), 8.5, COL_EYE_GLOW_OUTER, 0.92)
		_fill_circle(img, ec + Vector2(0.0, 1.0), 4.5, COL_EYE_GLOW_CORE, 0.98)

	# 3. Inverted-heart nasal cavity & grinning tooth row.
	var nose := PackedVector2Array([
		center + Vector2(0.0, 15.0),
		center + Vector2(8.0, 31.0),
		center + Vector2(0.0, 27.0),
		center + Vector2(-8.0, 31.0),
	])
	_fill_polygon(img, nose, COL_HAT_CHARCOAL, 0.95)
	_draw_line(img, center + Vector2(-24.0, 46.0), center + Vector2(24.0, 46.0), COL_INK_DARK, 2.4, 0.94)
	_draw_line(img, center + Vector2(-22.0, 62.0), center + Vector2(22.0, 62.0), COL_INK_DARK, 2.0, 0.90)
	for ti in 7:
		var tx := center.x - 21.0 + float(ti) * 7.0
		_draw_line(img, Vector2(tx, center.y + 44.0), Vector2(tx, center.y + 63.0), COL_INK_DARK, 1.7, 0.90)

	# 4. Sweeping cocked 17th-century Pirate Captain Tricorn Hat with gold trim & crimson ribbon!
	var hat_crown := PackedVector2Array([
		center + Vector2(-58.0, -34.0),
		center + Vector2(-46.0, -82.0),
		center + Vector2(0.0, -104.0),
		center + Vector2(46.0, -82.0),
		center + Vector2(58.0, -34.0),
	])
	var hat_brim := PackedVector2Array([
		center + Vector2(-106.0, -56.0),
		center + Vector2(-62.0, -30.0),
		center + Vector2(0.0, -24.0),
		center + Vector2(62.0, -30.0),
		center + Vector2(106.0, -56.0),
		center + Vector2(84.0, -78.0),
		center + Vector2(44.0, -54.0),
		center + Vector2(0.0, -48.0),
		center + Vector2(-44.0, -54.0),
		center + Vector2(-84.0, -78.0),
	])
	_fill_polygon(img, hat_crown, COL_HAT_CHARCOAL, 0.97)
	_stroke_polygon(img, hat_crown, COL_INK_DARK, 2.6, 0.96)
	_fill_polygon(img, hat_brim, COL_HAT_CHARCOAL.lightened(0.08), 0.98)
	_stroke_polygon(img, hat_brim, COL_INK_DARK, 2.6, 0.96)
	# Gold braided trim along the cocked upper tricorn brim & bold crimson ribbon + gold buckle!
	_draw_line(img, center + Vector2(-100.0, -58.0), center + Vector2(-80.0, -74.0), COL_GOLD_TRIM, 3.4, 0.94)
	_draw_line(img, center + Vector2(-80.0, -74.0), center + Vector2(0.0, -50.0), COL_GOLD_TRIM, 3.0, 0.92)
	_draw_line(img, center + Vector2(0.0, -50.0), center + Vector2(80.0, -74.0), COL_GOLD_TRIM, 3.0, 0.92)
	_draw_line(img, center + Vector2(80.0, -74.0), center + Vector2(100.0, -58.0), COL_GOLD_TRIM, 3.4, 0.94)
	# Crimson tricorn cockade & gold hat-buckle clasp at center front.
	var band := PackedVector2Array([
		center + Vector2(-46.0, -36.0),
		center + Vector2(46.0, -36.0),
		center + Vector2(42.0, -46.0),
		center + Vector2(-42.0, -46.0),
	])
	_fill_polygon(img, band, COL_CRIMSON, 0.92)
	_draw_rect_outline(img, int(center.x - 10.0), int(center.y - 47.0), int(center.x + 10.0), int(center.y - 35.0), COL_GOLD_TRIM, 2.6, 0.98)


static func _fill_rect(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color, alpha: float) -> void:
	var xa := clampi(mini(x0, x1), 0, img.get_width() - 1)
	var xb := clampi(maxi(x0, x1), 0, img.get_width() - 1)
	var ya := clampi(mini(y0, y1), 0, img.get_height() - 1)
	var yb := clampi(maxi(y0, y1), 0, img.get_height() - 1)
	for y in range(ya, yb + 1):
		for x in range(xa, xb + 1):
			_blend_pixel(img, x, y, col, alpha)


static func _fill_circle(img: Image, center: Vector2, radius: float, col: Color, alpha: float) -> void:
	var ir := int(ceilf(radius + 1.0))
	var cx := int(roundf(center.x))
	var cy := int(roundf(center.y))
	for dy in range(-ir, ir + 1):
		for dx in range(-ir, ir + 1):
			var d := Vector2(float(cx + dx) - center.x, float(cy + dy) - center.y).length()
			if d <= radius + 0.65:
				var cov := clampf((radius + 0.65 - d) / 1.1, 0.0, 1.0)
				_blend_pixel(img, cx + dx, cy + dy, col, alpha * cov)


static func _draw_diamond(img: Image, center: Vector2, r: float, col: Color, alpha: float) -> void:
	_fill_polygon(img, PackedVector2Array([
		center + Vector2(0.0, -r),
		center + Vector2(r, 0.0),
		center + Vector2(0.0, r),
		center + Vector2(-r, 0.0),
	]), col, alpha)


static func _wrap_text(text: String, max_chars: int) -> Array[String]:
	var words := text.split(" ", false)
	var lines: Array[String] = []
	var cur := ""
	for w in words:
		if cur == "":
			cur = w
		elif cur.length() + 1 + w.length() <= max_chars:
			cur += " " + w
		else:
			lines.append(cur)
			cur = w
	if cur != "":
		lines.append(cur)
	return lines


static func _draw_text_centered(img: Image, text: String, center_x: int, top_y: int,
		scale: int, col: Color, alpha: float = 0.95, bold: bool = false) -> void:
	var adv := 6 * scale
	var total_w := maxi(0, text.length() * adv - scale)
	_draw_text_left(img, text, center_x - floori(float(total_w) * 0.5), top_y, scale, col, alpha, bold)


static func _draw_text_left(img: Image, text: String, start_x: int, top_y: int,
		scale: int, col: Color, alpha: float = 0.95, bold: bool = false) -> void:
	var upper := text.to_upper()
	var adv := 6 * scale
	var pen_x := start_x
	for i in upper.length():
		var ch := upper.substr(i, 1)
		var rows: Array = FONT_5X7.get(ch, FONT_5X7[" "])
		for ry in 7:
			var bits: int = int(rows[ry])
			for rx in 5:
				if (bits & (1 << (4 - rx))) == 0:
					continue
				var px0 := pen_x + rx * scale
				var py0 := top_y + ry * scale
				var w_pad := 1 if bold else 0
				for dy in range(scale):
					for dx in range(scale + w_pad):
						_blend_pixel(img, px0 + dx, py0 + dy, col, alpha)
		pen_x += adv
