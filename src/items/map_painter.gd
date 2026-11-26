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
