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
const COL_SEA_RIPPLE := Color(0.46, 0.56, 0.52, 1.0)
const COL_BEACH := Color(0.84, 0.74, 0.52, 1.0)
const COL_LOWLAND := Color(0.68, 0.70, 0.46, 1.0)
const COL_HIGHLAND := Color(0.57, 0.53, 0.40, 1.0)
const COL_INK_DARK := Color(0.22, 0.14, 0.09, 1.0)
const COL_INK_MID := Color(0.42, 0.30, 0.20, 1.0)
const COL_INK_FAINT := Color(0.60, 0.49, 0.34, 1.0)
const COL_FOXING := Color(0.48, 0.33, 0.18, 1.0)
const COL_CRIMSON := Color(0.76, 0.11, 0.09, 1.0)
const COL_CRIMSON_DARK := Color(0.48, 0.06, 0.05, 1.0)

static var _cached_base: Dictionary = {}  # int size -> PackedByteArray (no static Resource leak)


## Sanitize arbitrary text to printable strict ASCII (< 128), uppercased for parchment labels.
static func sanitize_ascii(raw: String, fallback: String = "UNCHARTED ISLE") -> String:
	var out := ""
	var prev_space := false
	for i in raw.length():
		var code := raw.unicode_at(i)
		if code >= 32 and code <= 126:
			var ch := char(code)
			if ch == " ":
				if not prev_space and not out.is_empty():
					out += " "
				prev_space = true
			else:
				out += ch
				prev_space = false
	var cleaned := out.strip_edges().to_upper()
	return fallback if cleaned.is_empty() else cleaned


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
	var buf := _get_parchment_base_bytes(res)
	var r_world := maxf(island_radius, 12.0)
	var seed_val := hash(island_name) ^ 0x4D4150
	var s := float(res) / 256.0

	var pts := contour_points
	if pts.size() < 3:
		pts = generate_fallback_contour(island_name, r_world)

	var center := Vector2(res * 0.5, res * 0.53)
	var scale_px := (res * 0.33) / r_world

	# Convert island-local XZ (X right, Z south/down) to map pixel coords.
	var poly := PackedVector2Array()
	poly.resize(pts.size())
	for i in pts.size():
		poly[i] = center + Vector2(pts[i].x, pts[i].y) * scale_px

	# Compute clamped dig site & coastal landing point up front so landmarks keep clear.
	var dig_px := center + Vector2(dig_local_pos.x, dig_local_pos.y) * scale_px
	dig_px.x = clampf(dig_px.x, res * 0.17, res * 0.83)
	dig_px.y = clampf(dig_px.y, res * 0.21, res * 0.83)
	var landing_px := _nearest_contour_point(poly, dig_px + Vector2(0.0, res * 0.18))

	# Faint nautical rhumb lines radiating from the compass rose corner + subtle age-foxing speckles.
	var rose_pos := Vector2(res * 0.81, res * 0.21)
	_buf_rhumb_lines(buf, res, rose_pos)
	_buf_age_foxing(buf, res, seed_val, dig_px)

	# 17th-century coastal wave-ripple contours + hand-inked outer shoreline shading hatches!
	_buf_coastal_wave_hatches(buf, res, poly, center, seed_val)

	# Island terrain bands: sandy beach, green lowland, rocky highland crest.
	_buf_fill_polygon(buf, res, poly, COL_BEACH, 0.88)
	var mid_poly := _scale_polygon(poly, center, 0.72)
	_buf_fill_polygon(buf, res, mid_poly, COL_LOWLAND, 0.78)
	var high_poly := _scale_polygon(poly, center, 0.43)
	_buf_fill_polygon(buf, res, high_poly, COL_HIGHLAND, 0.66)

	# Topographic elevation contour lines + delicate downhill hachure ticks + dark inked shoreline.
	_buf_stroke_polygon(buf, res, mid_poly, COL_INK_MID, 1.05 * s, 0.56)
	_buf_stroke_polygon(buf, res, high_poly, COL_INK_MID, 0.95 * s, 0.48)
	_buf_topo_hachures(buf, res, mid_poly, high_poly, center)
	_buf_stroke_polygon(buf, res, poly, COL_INK_DARK, 2.1 * s, 0.96)

	# Tiny hand-inked palm-tree & cliff-peak landmark sketches inside the island contour.
	_buf_island_landmarks(buf, res, poly, mid_poly, high_poly, center, dig_px, landing_px, seed_val)

	# Dotted pace trail from the landing cove toward the dig site.
	_buf_dotted_trail(buf, res, landing_px, dig_px, s)

	# Bold hand-painted crimson X at the buried dig site!
	_buf_red_x(buf, res, dig_px, res * 0.056)

	# Decorative 8-point compass rose + North marker.
	_buf_compass_rose(buf, res, rose_pos, res * 0.095)

	# Weathered double-line cartographer's border with corner compass ticks & strict-ASCII title ribbon.
	_buf_border_frame(buf, res)
	_buf_title_cartouche(buf, res, island_name)
	return Image.create_from_data(res, res, false, Image.FORMAT_RGBA8, buf)


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


static func _get_parchment_base_bytes(size: int) -> PackedByteArray:
	if _cached_base.has(size):
		return (_cached_base[size] as PackedByteArray).duplicate()
	var buf := PackedByteArray()
	buf.resize(size * size * 4)
	var inv := 1.0 / float(size - 1)
	var c0r := COL_PARCHMENT_CENTER.r
	var c0g := COL_PARCHMENT_CENTER.g
	var c0b := COL_PARCHMENT_CENTER.b
	var c1r := COL_PARCHMENT_EDGE.r
	var c1g := COL_PARCHMENT_EDGE.g
	var c1b := COL_PARCHMENT_EDGE.b
	var off := 0
	for y in size:
		var ny := float(y) * inv * 2.0 - 1.0
		var fy := sin(float(y) * 0.37) * 0.012
		var sty := ny - 0.34
		var sty2 := sty * sty
		for x in size:
			var nx := float(x) * inv * 2.0 - 1.0
			var edge_d := maxf(absf(nx), absf(ny))
			var radial := sqrt(nx * nx + ny * ny)
			var vig := clampf(pow(maxf(edge_d, radial * 0.72), 2.1) * 0.82, 0.0, 1.0)
			# Deterministic fibrous paper mottling + subtle tea-stain ring.
			var h := sin(float(x) * 0.17 + float(y) * 0.13) * cos(float(x) * 0.09 - float(y) * 0.21)
			var grain := fy + sin(float(x) * 0.53) * 0.008 + h * 0.025
			var stx := nx + 0.38
			var stain_d := sqrt(stx * stx + sty2)
			var stain := smoothstep(0.46, 0.14, stain_d) * 0.07
			var t := clampf(vig + stain, 0.0, 1.0)
			buf[off] = int(clampf(lerpf(c0r, c1r, t) + grain, 0.0, 1.0) * 255.0)
			buf[off + 1] = int(clampf(lerpf(c0g, c1g, t) + grain * 0.9, 0.0, 1.0) * 255.0)
			buf[off + 2] = int(clampf(lerpf(c0b, c1b, t) + grain * 0.75, 0.0, 1.0) * 255.0)
			buf[off + 3] = 255
			off += 4
	_cached_base[size] = buf
	return buf.duplicate()


static func _get_parchment_base(size: int) -> Image:
	return Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, _get_parchment_base_bytes(size))


# --- Fast direct PackedByteArray raster primitives for treasure maps ---

static func _buf_line(buf: PackedByteArray, res: int, a: Vector2, b: Vector2, col: Color, width: float = 1.5, alpha: float = 1.0) -> void:
	var a_eff := clampf(alpha * col.a, 0.0, 1.0)
	if a_eff <= 0.003:
		return
	# Liang-Barsky clip to image bounds so long rhumb lines never waste work off-canvas.
	var dx := b.x - a.x
	var dy := b.y - a.y
	var t0 := 0.0
	var t1 := 1.0
	var bound := float(res - 1)
	for edge in 4:
		var p := 0.0
		var q := 0.0
		match edge:
			0:
				p = -dx
				q = a.x
			1:
				p = dx
				q = bound - a.x
			2:
				p = -dy
				q = a.y
			3:
				p = dy
				q = bound - a.y
		if absf(p) < 0.00001:
			if q < 0.0:
				return
		else:
			var r_clip := q / p
			if p < 0.0:
				if r_clip > t1:
					return
				if r_clip > t0:
					t0 = r_clip
			else:
				if r_clip < t0:
					return
				if r_clip < t1:
					t1 = r_clip
	var x0 := a.x + dx * t0
	var y0 := a.y + dy * t0
	var x1 := a.x + dx * t1
	var y1 := a.y + dy * t1
	var sdx := x1 - x0
	var sdy := y1 - y0
	var dist := sqrt(sdx * sdx + sdy * sdy)
	var sr := col.r * 255.0
	var sg := col.g * 255.0
	var sb := col.b * 255.0

	# Fast 2-tap antialiased thin stroke for fine copperplate lines (width <= 1.35).
	if width <= 1.35:
		var thin_steps := maxi(1, int(ceilf(maxf(absf(sdx), absf(sdy)))))
		var inv_s := 1.0 / float(thin_steps)
		var steep := absf(sdy) > absf(sdx)
		var w_boost := clampf(width, 0.55, 1.35) * a_eff
		for i in range(thin_steps + 1):
			var t := float(i) * inv_s
			var fx := x0 + sdx * t
			var fy := y0 + sdy * t
			if steep:
				var ix := int(floorf(fx))
				var iy := int(roundf(fy))
				var frac := fx - float(ix)
				if iy >= 0 and iy < res:
					var row_base := iy * res
					if ix >= 0 and ix < res:
						var w0 := minf(1.0, (1.0 - frac) * w_boost)
						var inv0 := 1.0 - w0
						var off0 := (row_base + ix) * 4
						buf[off0] = int(float(buf[off0]) * inv0 + sr * w0)
						buf[off0 + 1] = int(float(buf[off0 + 1]) * inv0 + sg * w0)
						buf[off0 + 2] = int(float(buf[off0 + 2]) * inv0 + sb * w0)
					var ix1 := ix + 1
					if ix1 >= 0 and ix1 < res and frac > 0.02:
						var w1 := minf(1.0, frac * w_boost)
						var inv1 := 1.0 - w1
						var off1 := (row_base + ix1) * 4
						buf[off1] = int(float(buf[off1]) * inv1 + sr * w1)
						buf[off1 + 1] = int(float(buf[off1 + 1]) * inv1 + sg * w1)
						buf[off1 + 2] = int(float(buf[off1 + 2]) * inv1 + sb * w1)
			else:
				var ix := int(roundf(fx))
				var iy := int(floorf(fy))
				var frac := fy - float(iy)
				if ix >= 0 and ix < res:
					if iy >= 0 and iy < res:
						var w0 := minf(1.0, (1.0 - frac) * w_boost)
						var inv0 := 1.0 - w0
						var off0 := (iy * res + ix) * 4
						buf[off0] = int(float(buf[off0]) * inv0 + sr * w0)
						buf[off0 + 1] = int(float(buf[off0 + 1]) * inv0 + sg * w0)
						buf[off0 + 2] = int(float(buf[off0 + 2]) * inv0 + sb * w0)
					var iy1 := iy + 1
					if iy1 >= 0 and iy1 < res and frac > 0.02:
						var w1 := minf(1.0, frac * w_boost)
						var inv1 := 1.0 - w1
						var off1 := (iy1 * res + ix) * 4
						buf[off1] = int(float(buf[off1]) * inv1 + sr * w1)
						buf[off1 + 1] = int(float(buf[off1 + 1]) * inv1 + sg * w1)
						buf[off1 + 2] = int(float(buf[off1 + 2]) * inv1 + sb * w1)
		return

	# Bold brush strokes (shoreline, crimson X, borders): direct byte disc stamp.
	var steps := maxi(1, int(ceilf(dist)))
	var rad := width * 0.5
	var irad := int(ceilf(rad))
	var max_r := rad + 0.55
	var max_r2 := max_r * max_r
	var inv_steps := 1.0 / float(steps)
	for i in range(steps + 1):
		var t := float(i) * inv_steps
		var px_f := x0 + sdx * t
		var py_f := y0 + sdy * t
		var cx := int(roundf(px_f))
		var cy := int(roundf(py_f))
		var ya := maxi(0, cy - irad)
		var yb := mini(res - 1, cy + irad)
		var xa := maxi(0, cx - irad)
		var xb := mini(res - 1, cx + irad)
		for py in range(ya, yb + 1):
			var ddy := float(py) - py_f
			var ddy2 := ddy * ddy
			if ddy2 > max_r2:
				continue
			var row_base := py * res
			for px in range(xa, xb + 1):
				var ddx := float(px) - px_f
				var d2 := ddx * ddx + ddy2
				if d2 <= max_r2:
					var cov := clampf((max_r - sqrt(d2)) / 1.05, 0.0, 1.0) * a_eff
					var inv_c := 1.0 - cov
					var off := (row_base + px) * 4
					buf[off] = int(float(buf[off]) * inv_c + sr * cov)
					buf[off + 1] = int(float(buf[off + 1]) * inv_c + sg * cov)
					buf[off + 2] = int(float(buf[off + 2]) * inv_c + sb * cov)


static func _buf_circle_outline(buf: PackedByteArray, res: int, center: Vector2, radius: float, col: Color, width: float = 1.4, alpha: float = 1.0) -> void:
	var segs := maxi(16, int(radius * 1.4))
	var prev := center + Vector2(radius, 0.0)
	for i in range(1, segs + 1):
		var a := float(i) / float(segs) * TAU
		var cur := center + Vector2(cos(a), sin(a)) * radius
		_buf_line(buf, res, prev, cur, col, width, alpha)
		prev = cur


static func _buf_stroke_polygon(buf: PackedByteArray, res: int, poly: PackedVector2Array, col: Color, width: float, alpha: float) -> void:
	var n := poly.size()
	if n < 2:
		return
	for i in n:
		_buf_line(buf, res, poly[i], poly[(i + 1) % n], col, width, alpha)


static func _buf_fill_polygon(buf: PackedByteArray, res: int, poly: PackedVector2Array, col: Color, alpha: float) -> void:
	var n := poly.size()
	if n < 3:
		return
	var a_eff := clampf(alpha * col.a, 0.0, 1.0)
	if a_eff <= 0.003:
		return
	var min_y := res
	var max_y := 0
	for p in poly:
		min_y = mini(min_y, int(floorf(p.y)))
		max_y = maxi(max_y, int(ceilf(p.y)))
	min_y = clampi(min_y, 0, res - 1)
	max_y = clampi(max_y, 0, res - 1)
	var sr := col.r * 255.0 * a_eff
	var sg := col.g * 255.0 * a_eff
	var sb := col.b * 255.0 * a_eff
	var inv_a := 1.0 - a_eff

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
		var row_base := y * res
		var idx := 0
		while idx + 1 < xs.size():
			var x0 := clampi(int(ceilf(xs[idx])), 0, res - 1)
			var x1 := clampi(int(floorf(xs[idx + 1])), 0, res - 1)
			var off := (row_base + x0) * 4
			for _x in range(x0, x1 + 1):
				buf[off] = int(float(buf[off]) * inv_a + sr)
				buf[off + 1] = int(float(buf[off + 1]) * inv_a + sg)
				buf[off + 2] = int(float(buf[off + 2]) * inv_a + sb)
				off += 4
			idx += 2


static func _buf_fill_rect(buf: PackedByteArray, res: int, x0: int, y0: int, x1: int, y1: int, col: Color, alpha: float) -> void:
	var a_eff := clampf(alpha * col.a, 0.0, 1.0)
	if a_eff <= 0.003:
		return
	var xa := clampi(mini(x0, x1), 0, res - 1)
	var xb := clampi(maxi(x0, x1), 0, res - 1)
	var ya := clampi(mini(y0, y1), 0, res - 1)
	var yb := clampi(maxi(y0, y1), 0, res - 1)
	var sr := col.r * 255.0 * a_eff
	var sg := col.g * 255.0 * a_eff
	var sb := col.b * 255.0 * a_eff
	var inv_a := 1.0 - a_eff
	for y in range(ya, yb + 1):
		var off := (y * res + xa) * 4
		for _x in range(xa, xb + 1):
			buf[off] = int(float(buf[off]) * inv_a + sr)
			buf[off + 1] = int(float(buf[off + 1]) * inv_a + sg)
			buf[off + 2] = int(float(buf[off + 2]) * inv_a + sb)
			off += 4


static func _buf_rect_outline(buf: PackedByteArray, res: int, x0: int, y0: int, x1: int, y1: int, col: Color, width: float, alpha: float) -> void:
	var half := maxi(0, int(floorf((width - 0.5) * 0.5)))
	_buf_fill_rect(buf, res, x0 - half, y0 - half, x1 + half, y0 + half, col, alpha)
	_buf_fill_rect(buf, res, x0 - half, y1 - half, x1 + half, y1 + half, col, alpha)
	_buf_fill_rect(buf, res, x0 - half, y0 + half + 1, x0 + half, y1 - half - 1, col, alpha)
	_buf_fill_rect(buf, res, x1 - half, y0 + half + 1, x1 + half, y1 - half - 1, col, alpha)


static func _buf_fill_circle(buf: PackedByteArray, res: int, center: Vector2, radius: float, col: Color, alpha: float) -> void:
	var a_eff := clampf(alpha * col.a, 0.0, 1.0)
	if a_eff <= 0.003:
		return
	var ir := int(ceilf(radius + 1.0))
	var cx := int(roundf(center.x))
	var cy := int(roundf(center.y))
	var max_r := radius + 0.65
	var max_r2 := max_r * max_r
	var sr := col.r * 255.0
	var sg := col.g * 255.0
	var sb := col.b * 255.0
	var ya := maxi(0, cy - ir)
	var yb := mini(res - 1, cy + ir)
	var xa := maxi(0, cx - ir)
	var xb := mini(res - 1, cx + ir)
	for py in range(ya, yb + 1):
		var ddy := float(py) - center.y
		var ddy2 := ddy * ddy
		if ddy2 > max_r2:
			continue
		var row_base := py * res
		for px in range(xa, xb + 1):
			var ddx := float(px) - center.x
			var d2 := ddx * ddx + ddy2
			if d2 <= max_r2:
				var cov := clampf((max_r - sqrt(d2)) / 1.1, 0.0, 1.0) * a_eff
				var inv_c := 1.0 - cov
				var off := (row_base + px) * 4
				buf[off] = int(float(buf[off]) * inv_c + sr * cov)
				buf[off + 1] = int(float(buf[off + 1]) * inv_c + sg * cov)
				buf[off + 2] = int(float(buf[off + 2]) * inv_c + sb * cov)


static func _buf_diamond(buf: PackedByteArray, res: int, center: Vector2, r: float, col: Color, alpha: float) -> void:
	_buf_fill_polygon(buf, res, PackedVector2Array([
		center + Vector2(0.0, -r),
		center + Vector2(r, 0.0),
		center + Vector2(0.0, r),
		center + Vector2(-r, 0.0),
	]), col, alpha)


static func _buf_text_centered(buf: PackedByteArray, res: int, text: String, center_x: int, top_y: int,
		scale: int, col: Color, alpha: float = 0.95) -> void:
	var adv := 6 * scale
	var total_w := maxi(0, text.length() * adv - scale)
	var start_x := center_x - floori(float(total_w) * 0.5)
	var upper := text.to_upper()
	var a_eff := clampf(alpha * col.a, 0.0, 1.0)
	var sr := col.r * 255.0 * a_eff
	var sg := col.g * 255.0 * a_eff
	var sb := col.b * 255.0 * a_eff
	var inv_a := 1.0 - a_eff
	var pen_x := start_x
	for i in upper.length():
		var ch := upper.substr(i, 1)
		var rows: Array = FONT_5X7.get(ch, FONT_5X7[" "])
		for ry in 7:
			var bits: int = int(rows[ry])
			if bits == 0:
				continue
			for rx in 5:
				if (bits & (1 << (4 - rx))) == 0:
					continue
				var px0 := pen_x + rx * scale
				var py0 := top_y + ry * scale
				for dy in scale:
					var py := py0 + dy
					if py < 0 or py >= res:
						continue
					var row_base := py * res
					for dx in scale:
						var px := px0 + dx
						if px < 0 or px >= res:
							continue
						var off := (row_base + px) * 4
						buf[off] = int(float(buf[off]) * inv_a + sr)
						buf[off + 1] = int(float(buf[off + 1]) * inv_a + sg)
						buf[off + 2] = int(float(buf[off + 2]) * inv_a + sb)
		pen_x += adv


static func _buf_coastal_wave_hatches(buf: PackedByteArray, res: int, poly: PackedVector2Array, center: Vector2, seed_val: int) -> void:
	var n := poly.size()
	if n < 3:
		return
	var s := float(res) / 256.0

	# 1. Three hand-engraved broken coastal wave-ripple rings hugging the outer shoreline contour.
	var ring_specs: Array[Array] = [
		[1.055, COL_SEA_RIPPLE, 1.25 * s, 0.56, 0.015],
		[1.125, COL_SEA_RIPPLE, 1.05 * s, 0.42, 0.022],
		[1.195, COL_INK_FAINT, 0.90 * s, 0.32, 0.026],
	]
	for r_idx in ring_specs.size():
		var spec: Array = ring_specs[r_idx]
		var factor: float = float(spec[0])
		var col: Color = spec[1]
		var width: float = float(spec[2])
		var alpha: float = float(spec[3])
		var wob_amp: float = float(spec[4])
		for i in n:
			if r_idx >= 1 and ((i + r_idx + seed_val) % 5 == 0):
				continue
			var a0 := poly[i]
			var a1 := poly[(i + 1) % n]
			var f0 := factor + sin(float(i) * 1.9 + float(r_idx * 2 + seed_val)) * wob_amp
			var f1 := factor + sin(float(i + 1) * 1.9 + float(r_idx * 2 + seed_val)) * wob_amp
			var p0 := center + (a0 - center) * f0
			var p1 := center + (a1 - center) * f1
			if r_idx == 2:
				p0 = p0.lerp(p1, 0.14)
				p1 = p0.lerp(p1, 0.84)
			_buf_line(buf, res, p0, p1, col, width, alpha)

	# 2. Fine perpendicular 17th-century coastal shading hatch ticks radiating along the shoreline.
	var hatch_step := maxf(4.5, 6.2 * s)
	var hatch_idx := 0
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var seg := b - a
		var seg_len := seg.length()
		if seg_len < 1.0:
			continue
		var count := maxi(1, int(floorf(seg_len / hatch_step)))
		var edge_n := Vector2(seg.y, -seg.x).normalized()
		for k in count:
			var t := (float(k) + 0.5) / float(count)
			var p := a.lerp(b, t)
			var rad_out := (p - center).normalized()
			var out_dir := (edge_n if edge_n.dot(rad_out) >= 0.0 else -edge_n)
			out_dir = (out_dir * 0.65 + rad_out * 0.35).normalized()
			var len_var := 2.6 + (1.6 if (hatch_idx % 2 == 0) else 0.5) + sin(float(hatch_idx) * 1.7 + float(seed_val)) * 0.5
			_buf_line(buf, res, p + out_dir * (1.2 * s), p + out_dir * (len_var * s), COL_INK_MID, 0.85 * s, 0.50)
			hatch_idx += 1


static func _buf_topo_hachures(buf: PackedByteArray, res: int, mid_poly: PackedVector2Array, high_poly: PackedVector2Array, center: Vector2) -> void:
	var s := float(res) / 256.0
	var rings: Array[Array] = [
		[mid_poly, 7.6 * s, 3.0 * s, 0.46],
		[high_poly, 6.4 * s, 2.7 * s, 0.52],
	]
	for spec in rings:
		var ring: PackedVector2Array = spec[0]
		var step: float = float(spec[1])
		var hlen: float = float(spec[2])
		var alpha: float = float(spec[3])
		var n := ring.size()
		if n < 3:
			continue
		for i in n:
			var a := ring[i]
			var b := ring[(i + 1) % n]
			var seg_len := a.distance_to(b)
			if seg_len < 2.0:
				continue
			var count := maxi(1, int(floorf(seg_len / step)))
			for k in count:
				var p := a.lerp(b, (float(k) + 0.5) / float(count))
				var out_dir := (p - center).normalized()
				_buf_line(buf, res, p, p + out_dir * hlen, COL_INK_MID, 0.85 * s, alpha)


static func _buf_island_landmarks(
	buf: PackedByteArray,
	res: int,
	poly: PackedVector2Array,
	mid_poly: PackedVector2Array,
	high_poly: PackedVector2Array,
	center: Vector2,
	dig_px: Vector2,
	landing_px: Vector2,
	seed_val: int
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0x1A4D
	var s := float(res) / 256.0
	var min_dig_d := float(res) * 0.145
	var min_pair_d := float(res) * 0.085
	var placed: Array[Vector2] = []

	# 1. Tiny hand-inked cliff-peak chevron sketches near the highland crest.
	var cliff_placed := 0
	for _attempt in 32:
		if cliff_placed >= 2:
			break
		var ang := rng.randf_range(0.0, TAU)
		var r_frac := rng.randf_range(0.05, 0.36)
		var pt := center + Vector2(cos(ang), sin(ang)) * (float(res) * 0.30 * r_frac)
		if not Geometry2D.is_point_in_polygon(pt, high_poly):
			continue
		if not Geometry2D.is_point_in_polygon(pt + Vector2(0.0, -5.5 * s), mid_poly):
			continue
		if pt.distance_to(dig_px) < min_dig_d:
			continue
		if _dist_point_to_segment(pt, landing_px, dig_px) < float(res) * 0.055:
			continue
		var too_close := false
		for prev_pt in placed:
			if pt.distance_to(prev_pt) < min_pair_d:
				too_close = true
				break
		if too_close:
			continue
		_buf_cliff_peak_sketch(buf, res, pt, s)
		placed.append(pt)
		cliff_placed += 1

	# 2. Tiny hand-inked palm-tree sketches nestled cleanly inside the coastal lowland band.
	var palm_placed := 0
	for _attempt in 36:
		if palm_placed >= 3:
			break
		var ang := rng.randf_range(0.0, TAU)
		var r_frac := rng.randf_range(0.38, 0.70)
		var pt := center + Vector2(cos(ang), sin(ang)) * (float(res) * 0.28 * r_frac)
		if not Geometry2D.is_point_in_polygon(pt, mid_poly):
			continue
		if Geometry2D.is_point_in_polygon(pt, high_poly):
			continue
		if not Geometry2D.is_point_in_polygon(pt + Vector2(0.0, -9.0 * s), poly):
			continue
		if pt.distance_to(dig_px) < min_dig_d:
			continue
		if _dist_point_to_segment(pt, landing_px, dig_px) < float(res) * 0.055:
			continue
		var too_close := false
		for prev_pt in placed:
			if pt.distance_to(prev_pt) < min_pair_d:
				too_close = true
				break
		if too_close:
			continue
		var lean := 1.0 if (palm_placed % 2 == 0) else -1.0
		_buf_palm_sketch(buf, res, pt, s, lean)
		placed.append(pt)
		palm_placed += 1


static func _buf_cliff_peak_sketch(buf: PackedByteArray, res: int, pos: Vector2, s: float) -> void:
	var apex := pos + Vector2(0.0, -5.0 * s)
	var base_l := pos + Vector2(-6.2 * s, 3.0 * s)
	var base_r := pos + Vector2(6.5 * s, 3.2 * s)
	_buf_line(buf, res, base_l, apex, COL_INK_DARK, 1.15 * s, 0.85)
	_buf_line(buf, res, apex, base_r, COL_INK_DARK, 1.25 * s, 0.88)
	_buf_line(buf, res, apex.lerp(base_r, 0.18), pos + Vector2(0.8 * s, 2.8 * s), COL_INK_MID, 0.85 * s, 0.68)
	_buf_line(buf, res, apex.lerp(base_r, 0.42), pos + Vector2(3.2 * s, 3.0 * s), COL_INK_MID, 0.85 * s, 0.68)
	_buf_line(buf, res, apex.lerp(base_r, 0.68), pos + Vector2(5.1 * s, 3.1 * s), COL_INK_MID, 0.80 * s, 0.60)


static func _buf_palm_sketch(buf: PackedByteArray, res: int, base: Vector2, s: float, lean: float) -> void:
	var mid := base + Vector2(lean * 1.6 * s, -3.8 * s)
	var crown := base + Vector2(lean * 2.5 * s, -7.8 * s)
	_buf_line(buf, res, base + Vector2(-2.2 * s, 0.4 * s), base + Vector2(2.4 * s, 0.4 * s), COL_INK_MID, 0.85 * s, 0.54)
	_buf_line(buf, res, base, mid, COL_INK_DARK, 1.15 * s, 0.88)
	_buf_line(buf, res, mid, crown, COL_INK_DARK, 1.05 * s, 0.88)
	var frond_dirs: Array[Vector2] = [
		Vector2(-4.8, -1.6),
		Vector2(-3.6, 1.4),
		Vector2(0.4 * lean, -3.8),
		Vector2(4.6, -1.4),
		Vector2(3.8, 1.6),
	]
	for fd in frond_dirs:
		var tip := crown + fd * s
		var arch := crown.lerp(tip, 0.55) + Vector2(0.0, -1.1 * s)
		_buf_line(buf, res, crown, arch, COL_INK_DARK, 0.90 * s, 0.82)
		_buf_line(buf, res, arch, tip, COL_INK_MID, 0.80 * s, 0.74)


static func _buf_age_foxing(buf: PackedByteArray, res: int, seed_val: int, dig_px: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0xF0C5
	var s := float(res) / 256.0
	var title_box := Rect2(res * 0.06, res * 0.06, res * 0.62, res * 0.14)
	for _i in 44:
		var p := Vector2(rng.randf_range(res * 0.05, res * 0.95), rng.randf_range(res * 0.05, res * 0.95))
		if p.distance_to(dig_px) < res * 0.11 or title_box.has_point(p):
			continue
		var r := rng.randf_range(0.65, 1.55) * s
		var alpha := rng.randf_range(0.16, 0.34)
		var col := COL_FOXING if (rng.randi() % 2 == 0) else COL_INK_FAINT
		_buf_fill_circle(buf, res, p, r, col, alpha)


static func _buf_rhumb_lines(buf: PackedByteArray, res: int, origin: Vector2) -> void:
	var reach := float(res) * 1.25
	for i in 12:
		var a := float(i) / 12.0 * TAU
		_buf_line(buf, res, origin, origin + Vector2(cos(a), sin(a)) * reach, COL_INK_FAINT, 1.0, 0.22)


static func _buf_dotted_trail(buf: PackedByteArray, res: int, start: Vector2, finish: Vector2, scale_f: float) -> void:
	var dir := finish - start
	var dist := dir.length()
	if dist < 10.0 * scale_f:
		return
	var u := dir / dist
	var pos := 6.0 * scale_f
	var stop_d := dist - 10.0 * scale_f
	while pos < stop_d:
		var p0 := start + u * pos
		var p1 := start + u * minf(pos + 3.4 * scale_f, stop_d)
		_buf_line(buf, res, p0, p1, COL_INK_DARK, 1.45 * scale_f, 0.80)
		pos += 7.5 * scale_f


static func _buf_red_x(buf: PackedByteArray, res: int, center: Vector2, half: float) -> void:
	var r := maxf(half, 7.0)
	_buf_circle_outline(buf, res, center, r * 1.38, COL_CRIMSON_DARK, 1.2, 0.44)
	var a1 := center + Vector2(-r, -r * 0.92)
	var b1 := center + Vector2(r, r * 0.95)
	var a2 := center + Vector2(-r * 0.94, r)
	var b2 := center + Vector2(r * 0.96, -r * 0.94)
	_buf_line(buf, res, a1, b1, COL_CRIMSON_DARK, r * 0.44, 0.86)
	_buf_line(buf, res, a2, b2, COL_CRIMSON_DARK, r * 0.44, 0.86)
	_buf_line(buf, res, a1, b1, COL_CRIMSON, r * 0.28, 0.98)
	_buf_line(buf, res, a2, b2, COL_CRIMSON, r * 0.28, 0.98)


static func _buf_compass_rose(buf: PackedByteArray, res: int, center: Vector2, radius: float) -> void:
	_buf_circle_outline(buf, res, center, radius * 0.72, COL_INK_DARK, 1.2, 0.80)
	_buf_circle_outline(buf, res, center, radius * 0.56, COL_INK_MID, 1.0, 0.56)
	for i in 4:
		var a := (float(i) + 0.5) * PI * 0.5
		_buf_line(buf, res, center, center + Vector2(cos(a), sin(a)) * (radius * 0.76), COL_INK_MID, 1.5, 0.80)
	var dirs := [Vector2(0.0, -1.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(-1.0, 0.0)]
	for i in 4:
		var d: Vector2 = dirs[i]
		var side := Vector2(-d.y, d.x)
		var tip := center + d * radius
		var p_l := center + side * (radius * 0.19)
		var p_r := center - side * (radius * 0.19)
		var col := COL_CRIMSON if i == 0 else COL_INK_DARK
		_buf_fill_polygon(buf, res, PackedVector2Array([center, tip, p_l]), col, 0.95)
		_buf_fill_polygon(buf, res, PackedVector2Array([center, tip, p_r]), COL_INK_MID if i != 0 else COL_CRIMSON_DARK, 0.74)
	var ny := center.y - radius - 4.0
	var nh := maxf(5.0, radius * 0.28)
	var nw := nh * 0.65
	var n0 := Vector2(center.x - nw * 0.5, ny)
	var n1 := Vector2(center.x - nw * 0.5, ny - nh)
	var n2 := Vector2(center.x + nw * 0.5, ny)
	var n3 := Vector2(center.x + nw * 0.5, ny - nh)
	_buf_line(buf, res, n0, n1, COL_CRIMSON, 1.4, 0.95)
	_buf_line(buf, res, n1, n2, COL_CRIMSON, 1.3, 0.95)
	_buf_line(buf, res, n2, n3, COL_CRIMSON, 1.4, 0.95)


static func _buf_border_frame(buf: PackedByteArray, res: int) -> void:
	var s := float(res) / 256.0
	var m1 := maxi(8, int(roundf(res * 0.042)))
	var m2 := m1 + maxi(4, int(roundf(res * 0.020)))
	var m0 := maxi(3, m1 - 3)
	_buf_rect_outline(buf, res, m0, m0, res - 1 - m0, res - 1 - m0, COL_INK_FAINT, 1.0, 0.36)
	_buf_rect_outline(buf, res, m1, m1, res - 1 - m1, res - 1 - m1, COL_INK_DARK, 1.8 * s, 0.90)
	_buf_rect_outline(buf, res, m2, m2, res - 1 - m2, res - 1 - m2, COL_INK_MID, 1.0, 0.68)
	# Nautical scale ticks along all four borders.
	var ticks := 8
	for i in range(1, ticks):
		var u := int(roundf(lerpf(float(m2), float(res - 1 - m2), float(i) / float(ticks))))
		_buf_fill_rect(buf, res, u, m1, u, m2, COL_INK_DARK, 0.78)
		_buf_fill_rect(buf, res, u, res - 1 - m2, u, res - 1 - m1, COL_INK_DARK, 0.78)
		_buf_fill_rect(buf, res, m1, u, m2, u, COL_INK_DARK, 0.78)
		_buf_fill_rect(buf, res, res - 1 - m2, u, res - 1 - m1, u, COL_INK_DARK, 0.78)

	# Delicate corner compass-tick arcs & miter diamond studs at all four inner frame corners.
	var corner_specs: Array[Array] = [
		[Vector2(m2, m2), Vector2(1.0, 1.0), 0.0],
		[Vector2(res - 1 - m2, m2), Vector2(-1.0, 1.0), PI * 0.5],
		[Vector2(res - 1 - m2, res - 1 - m2), Vector2(-1.0, -1.0), PI],
		[Vector2(m2, res - 1 - m2), Vector2(1.0, -1.0), PI * 1.5],
	]
	var tick_r := 11.5 * s
	for c in corner_specs:
		var pt: Vector2 = c[0]
		var sv: Vector2 = c[1]
		var a_start: float = float(c[2])
		_buf_line(buf, res, pt, pt + sv * (6.2 * s), COL_INK_DARK, 1.1 * s, 0.78)
		_buf_diamond(buf, res, pt + sv * (3.6 * s), 2.1 * s, COL_INK_DARK, 0.80)
		for ti in 3:
			var ang := a_start + (float(ti) + 1.0) * (PI * 0.125)
			var dir := Vector2(cos(ang), sin(ang))
			_buf_line(buf, res, pt + dir * (tick_r * 0.72), pt + dir * tick_r, COL_INK_MID, 0.95 * s, 0.68)


static func _buf_title_cartouche(buf: PackedByteArray, res: int, island_name: String) -> void:
	var s := float(res) / 256.0
	var font_scale := 2 if res >= 384 else 1
	var adv := 6 * font_scale
	var x0 := int(roundf(res * 0.088))
	var y0 := int(roundf(res * 0.086))
	var max_w := int(roundf(res * 0.56))
	var pad_x := 6 * font_scale
	var max_chars := maxi(4, int(floorf(float(max_w - pad_x * 2 + font_scale) / float(adv))))
	var title := sanitize_ascii(island_name, "UNCHARTED ISLE")
	if title.length() > max_chars:
		title = title.substr(0, max_chars).strip_edges()
	var text_w := maxi(adv * 4, title.length() * adv - font_scale)
	var w := mini(max_w, text_w + pad_x * 2)
	var h := 7 * font_scale + 10 * font_scale

	_buf_fill_rect(buf, res, x0, y0, x0 + w, y0 + h, COL_BANNER_CREAM, 0.58)
	_buf_rect_outline(buf, res, x0, y0, x0 + w, y0 + h, COL_INK_DARK, 1.3 * s, 0.88)
	_buf_rect_outline(buf, res, x0 + 2, y0 + 2, x0 + w - 2, y0 + h - 2, COL_INK_MID, 1.0, 0.52)
	_buf_fill_rect(buf, res, x0 + 4, y0 + h - 2, x0 + w - 4, y0 + h - 2, COL_CRIMSON, 0.68)
	var text_y := y0 + int(floorf(float(h - 7 * font_scale) * 0.5))
	_buf_text_centered(buf, res, title, x0 + int(floorf(float(w) * 0.5)), text_y, font_scale, COL_INK_DARK, 0.94)


# --- Image-based raster primitives (used by 512x512 Riddle Scrolls & Wanted Bounty Posters) ---

static func _blend_pixel(img: Image, x: int, y: int, col: Color, alpha: float) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	var a := clampf(alpha * col.a, 0.0, 1.0)
	if a <= 0.002:
		return
	var dst := img.get_pixel(x, y)
	img.set_pixel(x, y, dst.lerp(Color(col.r, col.g, col.b, 1.0), a))


static func _draw_line(img: Image, a: Vector2, b: Vector2, col: Color, width: float = 1.5, alpha: float = 1.0) -> void:
	var dx_ab := b.x - a.x
	var dy_ab := b.y - a.y
	var dist := sqrt(dx_ab * dx_ab + dy_ab * dy_ab)
	var steps := maxi(1, int(ceilf(dist * 1.25)))
	var rad := maxf(0.45, width * 0.5)
	var irad := int(ceilf(rad))
	var max_r := rad + 0.60
	var max_r2 := max_r * max_r
	var inv_steps := 1.0 / float(steps)
	for i in range(steps + 1):
		var t := float(i) * inv_steps
		var px_f := a.x + dx_ab * t
		var py_f := a.y + dy_ab * t
		var cx := int(roundf(px_f))
		var cy := int(roundf(py_f))
		for dy in range(-irad, irad + 1):
			var py := cy + dy
			var ddy := float(py) - py_f
			var ddy2 := ddy * ddy
			if ddy2 > max_r2:
				continue
			for dx in range(-irad, irad + 1):
				var px := cx + dx
				var ddx := float(px) - px_f
				var d2 := ddx * ddx + ddy2
				if d2 <= max_r2:
					var cov := clampf((max_r - sqrt(d2)) / 1.05, 0.0, 1.0)
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


static func _dist_point_to_segment(pt: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.001:
		return pt.distance_to(a)
	var t := clampf((pt - a).dot(ab) / l2, 0.0, 1.0)
	return pt.distance_to(a + ab * t)


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


static func _draw_rect_outline(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color, width: float, alpha: float) -> void:
	_draw_line(img, Vector2(x0, y0), Vector2(x1, y0), col, width, alpha)
	_draw_line(img, Vector2(x1, y0), Vector2(x1, y1), col, width, alpha)
	_draw_line(img, Vector2(x1, y1), Vector2(x0, y1), col, width, alpha)
	_draw_line(img, Vector2(x0, y1), Vector2(x0, y0), col, width, alpha)


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
