class_name IslandTrails
extends RefCounted
## Organic winding footpath & cobbled harbour trail polylines for every island
## archetype in Sea of Scoundrels.
##
## All polylines are authored in each island's canonical `(u, v)` landing frame
## (matching `IslandGenerator._eval_height`, where `-v` faces seaward toward the
## landing cove or dock pier and `+u` faces starboard). Transforming back into
## island-local XZ uses `Basis(Vector3.UP, landing_yaw) * Vector3(u, 0.0, v)`.
##
## `IslandGenerator` encodes `sample_trail_alpha()` into terrain vertex `COLOR.a`
## so `island_shader.gdshader` blends sunlit pebbled footpaths via `1.0 - COLOR.a`,
## and `IslandLandmarks` consumes `get_trail_marker_spots()` to line trailheads,
## forks, and scenic bends with `trail_lantern_post.glb` & `stone_cairn_marker.glb`.

const TRAIL_MIN_Y := 0.9
const TRAIL_FULL_Y := 2.0
const TRAIL_MIN_NY := 0.68
const TRAIL_FULL_NY := 0.84
const TRAIL_PEAK_STRENGTH := 0.92
const TRAIL_OUTER_SCALE := 1.45
const TRAIL_CORE_SCALE := 0.45
const TRAIL_MAX_WOBBLE := 0.62

const MARKER_MIN_Y := 1.4
const MARKER_MAX_Y := 34.0
const MARKER_MIN_NY := 0.76
const MARKER_OFFSET_MIN := 2.4
const MARKER_OFFSET_MAX := 3.2


## Return 1 to 3 organic curved polylines in canonical `(u, v)` coordinates
## tailored to the island's archetype topography and optional `island_id`.
static func get_trail_polylines(arch: StringName, radius: float,
		island_id: String = "") -> Array[PackedVector2Array]:
	var s := maxf(radius / 60.0, 0.35)
	var out: Array[PackedVector2Array] = []

	match arch:
		&"outpost", &"outpost_harbour":
			if island_id == "barnacle_haven":
				# Barnacle Haven: dock ramp -> curving east-then-south around harbour plaza
				# -> climbing up to Copper Beacon shelf -> looping out onto the east harbour promontory.
				out.append(_catmull_rom_polyline([
					Vector2(0.0, -25.5),
					Vector2(4.2, -20.8),
					Vector2(10.5, -13.2),
					Vector2(13.6, -5.6),
					Vector2(20.5, -4.5),
					Vector2(24.0, -6.5),
					Vector2(32.5, -10.5),
					Vector2(35.0, -19.0),
					Vector2(27.5, -24.0),
				], 3))
				# Secondary scenic wharf trail west past Driftwood Tavern to coastal cliff lookout & bluff pier.
				out.append(_catmull_rom_polyline([
					Vector2(-0.8, -22.5),
					Vector2(-4.5, -16.2),
					Vector2(-11.0, -12.2),
					Vector2(-18.5, -9.8),
					Vector2(-26.0, -12.0),
					Vector2(-32.5, -17.5),
					Vector2(-36.5, -23.5),
				], 3))
			else:
				# Port Scoundrel (default): dock ramp -> sweeping gently through central plaza
				# -> curving up to Harbour Beacon Tower -> continuing across the sunlit upper terrace.
				out.append(_catmull_rom_polyline([
					Vector2(0.0, -25.5),
					Vector2(-1.4, -20.5),
					Vector2(-0.6, -15.6),
					Vector2(5.5, -11.8),
					Vector2(12.2, -10.2),
					Vector2(24.0, -6.5),
					Vector2(33.5, -9.0),
					Vector2(34.5, 0.5),
					Vector2(25.5, 8.5),
					Vector2(12.0, 10.0),
				], 3))
				# West branch past Salty Lantern Tavern to the western cliff overlook & headland watchtower.
				out.append(_catmull_rom_polyline([
					Vector2(-1.2, -17.2),
					Vector2(-6.4, -14.2),
					Vector2(-11.4, -12.6),
					Vector2(-18.0, -8.5),
					Vector2(-24.5, -3.0),
					Vector2(-28.0, 2.0),
					Vector2(-32.5, -4.5),
					Vector2(-34.5, -13.5),
				], 3))

		&"grand_outpost":
			# Galleon's Reach: grand wharf -> harbour boulevard curving past warehouses &
			# tavern -> sweeping switchback ascending onto upper `town_terrace` (0, 32).
			out.append(_catmull_rom_polyline([
				Vector2(0.0, -25.5),
				Vector2(-1.5, -19.5),
				Vector2(4.5, -14.0),
				Vector2(12.2, -8.2),
				Vector2(15.5, 3.0),
				Vector2(8.5, 13.5),
				Vector2(-9.5, 21.5),
				Vector2(-11.0, 29.0),
				Vector2(0.0, 32.0),
				Vector2(16.0, 33.5),
			], 3))
			# East branch climbing past Sovereign Beacon shelf & Temple Stairway out to `east_overlook` (52, -20).
			out.append(_catmull_rom_polyline([
				Vector2(5.0, -14.0),
				Vector2(14.5, -12.0),
				Vector2(24.0, -6.5),
				Vector2(34.5, -10.5),
				Vector2(43.5, -15.8),
				Vector2(52.0, -20.0),
			], 3))
			# West branch weaving past Tavern & harbour warehouses toward the west headland watchtower & catwalk.
			out.append(_catmull_rom_polyline([
				Vector2(-1.5, -19.5),
				Vector2(-9.5, -15.2),
				Vector2(-16.5, -13.2),
				Vector2(-24.5, -20.0),
				Vector2(-36.0, -30.5),
				Vector2(-46.0, -38.0),
				Vector2(-54.0, -44.0),
			], 3))

		&"treasure_peak", &"treasure_cove":
			# Cutlass Cay: golden cove beach -> gentle S-curve past campfire/dig clearings
			# -> climbing smoothly up into the grassy saddle between the twin spires.
			out.append(_catmull_rom_polyline([
				Vector2(2.0 * s, -34.0 * s),
				Vector2(-3.2 * s, -24.5 * s),
				Vector2(3.6 * s, -15.0 * s),
				Vector2(-2.2 * s, -6.5 * s),
				Vector2(-6.0 * s, 0.0),
			], 3))
			# Scenic spur curling across the sunny eastern palm terrace.
			out.append(_catmull_rom_polyline([
				Vector2(3.2 * s, -16.5 * s),
				Vector2(11.0 * s, -17.5 * s),
				Vector2(18.5 * s, -15.0 * s),
				Vector2(25.0 * s, -13.0 * s),
			], 3))

		&"twin_spires":
			# Emerald Spire: landing cove -> winding gently up the emerald canyon floor across
			# `CanyonTimberBridge` (0, -6*s) -> curving up to `TempleStairway_Canyon` & waterfall basin.
			out.append(_catmull_rom_polyline([
				Vector2(0.0, -38.0 * s),
				Vector2(2.6 * s, -28.0 * s),
				Vector2(-1.6 * s, -17.0 * s),
				Vector2(0.0, -6.0 * s),
				Vector2(2.0 * s, 3.0 * s),
				Vector2(0.8 * s, 9.2 * s),
			], 3))
			# Short ruined-arch shrine side spur on the walkable western canyon shoulder.
			out.append(_catmull_rom_polyline([
				Vector2(1.4 * s, 1.5 * s),
				Vector2(-2.4 * s, 3.5 * s),
				Vector2(-5.0 * s, 5.5 * s),
			], 3))

		&"crescent_lagoon":
			# Crescent Atoll: sweeping sandy palm-horn footpath hugging the turquoise lagoon's
			# western & back shore up to the rear highland vista.
			out.append(_catmull_rom_polyline([
				Vector2(-26.0 * s, -22.0 * s),
				Vector2(-34.0 * s, -7.5 * s),
				Vector2(-32.0 * s, 10.0 * s),
				Vector2(-18.5 * s, 21.0 * s),
				Vector2(-4.5 * s, 23.0 * s),
				Vector2(8.0 * s, 22.0 * s),
			], 3))
			# Eastern coral-spit footpath curling around the lagoon rim.
			out.append(_catmull_rom_polyline([
				Vector2(28.0 * s, -16.0 * s),
				Vector2(34.5 * s, -4.0 * s),
				Vector2(33.0 * s, 10.0 * s),
				Vector2(22.0 * s, 19.5 * s),
			], 3))

		&"sea_arch":
			# Gull's Arch: tide cove beach beneath `SeaArch_Main` -> splitting smoothly onto the
			# walkable western headland bluff terrace.
			out.append(_catmull_rom_polyline([
				Vector2(0.0, -25.0 * s),
				Vector2(-1.5 * s, -16.5 * s),
				Vector2(-9.5 * s, -15.8 * s),
				Vector2(-17.5 * s, -19.5 * s),
				Vector2(-24.5 * s, -24.0 * s),
			], 3))
			# Fork sweeping onto the sunny eastern bluff shelf overlooking Tern Tide Bay.
			out.append(_catmull_rom_polyline([
				Vector2(-0.8 * s, -16.5 * s),
				Vector2(8.5 * s, -15.0 * s),
				Vector2(16.5 * s, -16.0 * s),
				Vector2(25.0 * s, -20.5 * s),
			], 3))

		&"fort_rock":
			# Ironwatch Fort: wide cobbled assault ramp straight from landing cove to FortBastion gateway.
			out.append(_catmull_rom_polyline([
				Vector2(0.0, -40.0 * s),
				Vector2(0.8 * s, -30.5 * s),
				Vector2(-0.6 * s, -20.5 * s),
				Vector2(0.0, -10.0 * s),
			], 3))
			# Flanking bastion-mesa patrol terrace linking the western & eastern watchtower approaches.
			out.append(_catmull_rom_polyline([
				Vector2(-20.0 * s, -8.5 * s),
				Vector2(-12.0 * s, -11.2 * s),
				Vector2(0.0, -11.6 * s),
				Vector2(12.0 * s, -11.2 * s),
				Vector2(22.0 * s, -8.5 * s),
			], 3))

		&"grand_citadel":
			# Sovereign's Bastion (UNSCALED terrain frame): grand cobbled highway from the
			# sweeping landing cove straight up to the `FortBastion` gateway.
			out.append(_catmull_rom_polyline([
				Vector2(0.0, -94.0),
				Vector2(1.8, -72.0),
				Vector2(-1.6, -48.0),
				Vector2(1.2, -24.0),
				Vector2(0.0, 2.0),
			], 3))
			# Scenic western temple branch crossing `CitadelTimberBridge` (-42, -14) to west ruins.
			out.append(_catmull_rom_polyline([
				Vector2(-1.6, -48.0),
				Vector2(-14.0, -44.0),
				Vector2(-30.0, -28.0),
				Vector2(-46.0, -14.0),
				Vector2(-59.0, 0.0),
				Vector2(-70.0, 14.0),
			], 3))
			# Eastern temple & cascade waterfall branch curving past the plunge cove to `temple_terrace_e`.
			out.append(_catmull_rom_polyline([
				Vector2(-1.0, -48.0),
				Vector2(14.0, -44.0),
				Vector2(30.0, -36.0),
				Vector2(44.0, -27.0),
				Vector2(58.0, -11.0),
				Vector2(69.0, 8.0),
			], 3))

		&"wreck_shoal":
			# Wrecker's Shoal: salvage footpath winding from the `-v` sandbar past stranded hulls
			# up onto the central limestone rock ridge.
			out.append(_catmull_rom_polyline([
				Vector2(8.0 * s, -37.0 * s),
				Vector2(1.5 * s, -27.0 * s),
				Vector2(-4.5 * s, -15.0 * s),
				Vector2(-2.5 * s, -3.0 * s),
			], 3))

		&"volcano_crag":
			# Cinder Crag: dark ash-cove climber's trail ascending cleanly onto the southwest
			# fumarole terrace rim.
			out.append(_catmull_rom_polyline([
				Vector2(0.0, -44.0 * s),
				Vector2(-7.5 * s, -42.5 * s),
				Vector2(-16.0 * s, -41.0 * s),
				Vector2(-23.0 * s, -37.5 * s),
				Vector2(-26.5 * s, -33.0 * s),
			], 3))
			# Fork climbing smoothly onto the southeast fumarole terrace overlooking the ash cove.
			out.append(_catmull_rom_polyline([
				Vector2(0.0, -41.5 * s),
				Vector2(7.0 * s, -39.0 * s),
				Vector2(13.5 * s, -37.0 * s),
				Vector2(18.5 * s, -35.5 * s),
				Vector2(22.0 * s, -32.0 * s),
			], 3))

		&"skull_bluff":
			# Skull Bluff: landing spit -> across `BluffTimberBridge` (0, -26*s) -> curving onto
			# the lush western highland terrace overlooking Skull Brow.
			out.append(_catmull_rom_polyline([
				Vector2(0.0, -40.0 * s),
				Vector2(1.4 * s, -33.0 * s),
				Vector2(0.0, -26.0 * s),
				Vector2(-10.5 * s, -22.0 * s),
				Vector2(-22.5 * s, -17.0 * s),
				Vector2(-32.0 * s, -12.0 * s),
			], 3))
			# Eastern bridgehead fork ascending to the eastern highland terrace.
			out.append(_catmull_rom_polyline([
				Vector2(0.0, -25.2 * s),
				Vector2(10.5 * s, -21.0 * s),
				Vector2(22.5 * s, -15.5 * s),
				Vector2(32.0 * s, -10.0 * s),
			], 3))

		&"smuggler_cove":
			# Smuggler's Cove: hidden pocket beach winding straight into `SmugglersGrotto` mouth.
			out.append(_catmull_rom_polyline([
				Vector2(0.0, -22.0 * s),
				Vector2(-1.8 * s, -13.0 * s),
				Vector2(1.4 * s, -4.5 * s),
				Vector2(0.0, 4.0 * s),
			], 3))
			# East side-climb footpath scaling toward the cliffside catwalk overlook.
			out.append(_catmull_rom_polyline([
				Vector2(1.4 * s, -13.5 * s),
				Vector2(9.0 * s, -13.8 * s),
				Vector2(17.0 * s, -11.8 * s),
				Vector2(24.0 * s, -8.0 * s),
			], 3))

		&"sea_stack":
			# Siren's Tooth: winding rocky tide-path across the `-v` pocket sandbar skirting the
			# wrecked ship bow toward the eastern coastal arch shelf.
			out.append(_catmull_rom_polyline([
				Vector2(-17.0 * s, -28.0 * s),
				Vector2(-4.0 * s, -33.5 * s),
				Vector2(6.5 * s, -29.5 * s),
				Vector2(14.5 * s, -23.5 * s),
				Vector2(21.5 * s, -19.0 * s),
			], 3))

		&"palm_atoll":
			# Coral-ring footpath tracing the scenic beach rim around the western & northern lagoon.
			out.append(_catmull_rom_polyline([
				Vector2(-18.0 * s, -33.5 * s),
				Vector2(-34.5 * s, -16.5 * s),
				Vector2(-38.0 * s, 4.0 * s),
				Vector2(-26.5 * s, 27.0 * s),
				Vector2(-6.0 * s, 37.5 * s),
				Vector2(8.0 * s, 36.0 * s),
			], 3))
			# Eastern coral-rim arc tracing the windward beach back toward the lagoon channel.
			out.append(_catmull_rom_polyline([
				Vector2(18.0 * s, -33.5 * s),
				Vector2(34.5 * s, -16.5 * s),
				Vector2(38.0 * s, 3.0 * s),
				Vector2(34.5 * s, 16.0 * s),
			], 3))

		_:
			# Safe scenic cove fallback for any custom/unknown archetype.
			out.append(_catmull_rom_polyline([
				Vector2(0.0, -30.0 * s),
				Vector2(-4.0 * s, -18.0 * s),
				Vector2(4.0 * s, -6.0 * s),
				Vector2(0.0, 6.0 * s),
			], 3))

	return out


## Return the nominal trail half-width in metres for `arch`.
## Wide cobbled harbour & fort roads span `3.6..4.2 m`; winding footpaths span `2.4..3.2 m`
## (`2.1 m` on compact `sea_stack`).
static func get_trail_half_width(arch: StringName) -> float:
	match arch:
		&"grand_outpost":
			return 4.2
		&"grand_citadel":
			return 4.1
		&"outpost", &"outpost_harbour":
			return 3.8
		&"fort_rock":
			return 3.7
		&"volcano_crag":
			return 3.1
		&"twin_spires", &"skull_bluff":
			return 3.0
		&"crescent_lagoon":
			return 2.9
		&"smuggler_cove":
			return 2.8
		&"treasure_peak", &"treasure_cove", &"sea_arch":
			return 2.7
		&"palm_atoll":
			return 2.6
		&"wreck_shoal":
			return 2.5
		&"sea_stack":
			return 2.1
		_:
			return 2.6


## Sample vertex `COLOR.a` for a terrain vertex at canonical `(u, v)`, elevation `y`,
## and upward surface normal `slope_ny`.
## Returns `~0.08` along trail centerlines (`1.0 - COLOR.a == 0.92`) and `1.0` off-trail.
static func sample_trail_alpha(u: float, v: float, polylines: Array[PackedVector2Array],
		half_width: float, slope_ny: float, y: float) -> float:
	if polylines.is_empty() or half_width <= 0.01:
		return 1.0
	if y <= TRAIL_MIN_Y or slope_ny <= TRAIL_MIN_NY:
		return 1.0

	var max_reach := (half_width + TRAIL_MAX_WOBBLE) * TRAIL_OUTER_SCALE
	var max_reach_sq := max_reach * max_reach
	var min_dist_sq := max_reach_sq + 1.0

	for poly in polylines:
		var count := poly.size()
		if count < 2:
			continue
		for i in range(count - 1):
			var a := poly[i]
			var b := poly[i + 1]
			# Fast per-segment bounding rejection before closest-point projection.
			var min_x := minf(a.x, b.x) - max_reach
			if u < min_x:
				continue
			var max_x := maxf(a.x, b.x) + max_reach
			if u > max_x:
				continue
			var min_y := minf(a.y, b.y) - max_reach
			if v < min_y:
				continue
			var max_y := maxf(a.y, b.y) + max_reach
			if v > max_y:
				continue

			var dx := b.x - a.x
			var dy := b.y - a.y
			var len_sq := dx * dx + dy * dy
			var d_sq: float
			if len_sq <= 0.0001:
				var px := u - a.x
				var py := v - a.y
				d_sq = px * px + py * py
			else:
				var t := clampf(((u - a.x) * dx + (v - a.y) * dy) / len_sq, 0.0, 1.0)
				var px := u - (a.x + dx * t)
				var py := v - (a.y + dy * t)
				d_sq = px * px + py * py
			if d_sq < min_dist_sq:
				min_dist_sq = d_sq

	if min_dist_sq >= max_reach_sq:
		return 1.0

	var dist := sqrt(min_dist_sq)
	# Subtle deterministic hand-worn width wobble so edges never read as mechanical stripes.
	var wobble := sin(u * 0.27 + v * 0.19) * 0.35 + cos(u * 0.14 - v * 0.31) * 0.25
	var eff_hw := maxf(half_width + wobble, 0.85)
	var outer_r := eff_hw * TRAIL_OUTER_SCALE
	if dist >= outer_r:
		return 1.0

	var core_r := eff_hw * TRAIL_CORE_SCALE
	var radial := 1.0 - _smoothstep(core_r, outer_r, dist)
	var height_gate := _smoothstep(TRAIL_MIN_Y, TRAIL_FULL_Y, y)
	var slope_gate := _smoothstep(TRAIL_MIN_NY, TRAIL_FULL_NY, slope_ny)
	var trail_strength := radial * height_gate * slope_gate
	return clampf(1.0 - trail_strength * TRAIL_PEAK_STRENGTH, 0.08, 1.0)


## Sample grounded roadside trail marker spots (`trail_lantern_post.glb` &
## `stone_cairn_marker.glb`) along `island`'s winding trails.
## Each entry is `{"pos": Vector3(lx, h, lz), "yaw": marker_yaw, "kind": &"lantern" | &"cairn"}`.
static func get_trail_marker_spots(island: Island, arch: StringName,
		landing_yaw: float) -> Array[Dictionary]:
	var spots: Array[Dictionary] = []
	if island == null:
		return spots

	var radius := island.island_radius
	var polylines := get_trail_polylines(arch, radius, island.island_id)
	if polylines.is_empty():
		return spots

	var half_width := get_trail_half_width(arch)
	var basis := Basis(Vector3.UP, landing_yaw)
	var plan := _build_marker_plan(arch, polylines.size())
	var min_spacing := _marker_min_spacing(arch, radius)
	var min_spacing_sq := min_spacing * min_spacing

	var side_sign := 1.0
	var station_idx := 0
	for entry in plan:
		var poly_idx := int(entry["poly"])
		if poly_idx < 0 or poly_idx >= polylines.size():
			continue
		var poly := polylines[poly_idx]
		if poly.size() < 2:
			continue

		var frac := float(entry["t"])
		var kind := entry["kind"] as StringName
		var base_offset := clampf(
			half_width * 0.82 + sin(float(station_idx) * 2.13 + radius * 0.07) * 0.28,
			MARKER_OFFSET_MIN,
			MARKER_OFFSET_MAX
		)

		var placed := _try_place_marker_at_station(
			island, arch, radius, basis, polylines, poly,
			frac, side_sign, base_offset, kind, spots, min_spacing_sq
		)
		if not placed.is_empty():
			spots.append(placed)
			side_sign = -side_sign
		station_idx += 1

	return spots


# ============================================================ internal helpers

static func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 1.0 if x >= edge1 else 0.0
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Catmull-Rom spline subdivision producing smooth organic trails passing cleanly
## through every authored control waypoint.
static func _catmull_rom_polyline(ctrl: Array[Vector2], subdiv: int = 3) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := ctrl.size()
	if n == 0:
		return pts
	if n == 1:
		pts.append(ctrl[0])
		return pts

	var steps := maxi(subdiv, 1)
	for i in range(n - 1):
		var p0 := ctrl[maxi(i - 1, 0)]
		var p1 := ctrl[i]
		var p2 := ctrl[i + 1]
		var p3 := ctrl[mini(i + 2, n - 1)]
		for k in range(steps):
			var t := float(k) / float(steps)
			pts.append(_catmull_rom_pt(p0, p1, p2, p3, t))
	pts.append(ctrl[n - 1])
	return pts


static func _catmull_rom_pt(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)


static func _polyline_length(poly: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(poly.size() - 1):
		total += poly[i].distance_to(poly[i + 1])
	return total


## Evaluate point & unit forward tangent along `poly` at normalized arc fraction `frac` in `[0, 1]`.
static func _sample_polyline_arc(poly: PackedVector2Array, frac: float) -> Dictionary:
	var total := _polyline_length(poly)
	if total <= 0.001:
		return {"pt": poly[0], "dir": Vector2(0.0, 1.0)}
	var target := clampf(frac, 0.0, 1.0) * total
	var accum := 0.0
	for i in range(poly.size() - 1):
		var a := poly[i]
		var b := poly[i + 1]
		var seg := b - a
		var seg_len := seg.length()
		if seg_len <= 0.0001:
			continue
		if accum + seg_len >= target or i == poly.size() - 2:
			var local_t := clampf((target - accum) / seg_len, 0.0, 1.0)
			return {
				"pt": a + seg * local_t,
				"dir": seg / seg_len,
			}
		accum += seg_len
	var last_a := poly[poly.size() - 2]
	var last_b := poly[poly.size() - 1]
	var last_dir := (last_b - last_a).normalized()
	if last_dir.length_squared() < 0.01:
		last_dir = Vector2(0.0, 1.0)
	return {"pt": last_b, "dir": last_dir}


static func _min_dist_to_polylines(u: float, v: float, polylines: Array[PackedVector2Array]) -> float:
	var min_sq := 1e12
	for poly in polylines:
		var count := poly.size()
		for i in range(count - 1):
			var a := poly[i]
			var b := poly[i + 1]
			var dx := b.x - a.x
			var dy := b.y - a.y
			var len_sq := dx * dx + dy * dy
			var d_sq: float
			if len_sq <= 0.0001:
				var px := u - a.x
				var py := v - a.y
				d_sq = px * px + py * py
			else:
				var t := clampf(((u - a.x) * dx + (v - a.y) * dy) / len_sq, 0.0, 1.0)
				var px := u - (a.x + dx * t)
				var py := v - (a.y + dy * t)
				d_sq = px * px + py * py
			if d_sq < min_sq:
				min_sq = d_sq
	return sqrt(min_sq)


static func _try_place_marker_at_station(island: Island, arch: StringName, radius: float,
		basis: Basis, polylines: Array[PackedVector2Array], poly: PackedVector2Array,
		frac: float, pref_side: float, base_offset: float, kind: StringName,
		existing: Array[Dictionary], min_spacing_sq: float) -> Dictionary:
	# Try nominal arc position first, then gentle along-trail nudges if blocked by a cliff/keepout/water.
	var nudges: Array[float] = [0.0, 0.05, -0.05, 0.10, -0.10, 0.16, -0.16, 0.22, -0.22]
	var sides: Array[float] = [pref_side, -pref_side]
	var offsets: Array[float] = [
		base_offset,
		clampf(base_offset + 0.35, MARKER_OFFSET_MIN, MARKER_OFFSET_MAX),
		clampf(base_offset - 0.35, MARKER_OFFSET_MIN, MARKER_OFFSET_MAX),
	]

	for n_delta in nudges:
		var test_frac := clampf(frac + n_delta, 0.03, 0.97)
		var sample := _sample_polyline_arc(poly, test_frac)
		var pt := sample["pt"] as Vector2
		var dir_uv := sample["dir"] as Vector2
		var perp_uv := Vector2(-dir_uv.y, dir_uv.x)

		for side in sides:
			for off in offsets:
				var m_uv := pt + perp_uv * (side * off)
				if _is_in_landmark_keepout(arch, radius, m_uv.x, m_uv.y):
					continue
				# Keep clear of intersecting branch centerlines at Y-forks.
				if _min_dist_to_polylines(m_uv.x, m_uv.y, polylines) < 1.85:
					continue

				var lp := basis * Vector3(m_uv.x, 0.0, m_uv.y)
				var lx := lp.x
				var lz := lp.z

				var too_close := false
				for prev in existing:
					var ppos := prev["pos"] as Vector3
					var ddx := lx - ppos.x
					var ddz := lz - ppos.z
					if ddx * ddx + ddz * ddz < min_spacing_sq:
						too_close = true
						break
				if too_close:
					continue

				var h := island.surface_height(lx, lz)
				if h < MARKER_MIN_Y or h > MARKER_MAX_Y:
					continue
				var ny := island.surface_normal(lx, lz).y
				if ny < MARKER_MIN_NY:
					continue

				var marker_yaw := _compute_marker_yaw(basis, pt, m_uv, dir_uv, kind)
				return {
					"pos": Vector3(lx, h, lz),
					"yaw": marker_yaw,
					"kind": kind,
				}
	return {}


## Orient markers meaningfully toward the footpath:
## - `trail_lantern_post.glb` has its overhanging lantern cross-arm along local `+X`.
## - `stone_cairn_marker.glb` has its carved golden compass-rune slab & pennant facing local `-Z`.
static func _compute_marker_yaw(basis: Basis, trail_uv: Vector2, marker_uv: Vector2,
		dir_uv: Vector2, kind: StringName) -> float:
	var to_trail_uv := trail_uv - marker_uv
	if to_trail_uv.length_squared() > 0.0001:
		to_trail_uv = to_trail_uv.normalized()
	else:
		to_trail_uv = Vector2(1.0, 0.0)

	var to_trail_local := basis * Vector3(to_trail_uv.x, 0.0, to_trail_uv.y)
	if kind == &"lantern":
		# Align local `+X` (`cos(yaw), 0, -sin(yaw)`) with `to_trail_local` so the lantern arm
		# overhangs the footpath.
		return atan2(-to_trail_local.z, to_trail_local.x)

	# For cairns, angle the `-Z` carved rune slab slightly toward approaching hikers + the path.
	var face_uv := (to_trail_uv * 0.78 - dir_uv * 0.62).normalized()
	var face_local := basis * Vector3(face_uv.x, 0.0, face_uv.y)
	# Align local `-Z` (`-sin(yaw), 0, -cos(yaw)`) with `face_local`.
	return atan2(-face_local.x, -face_local.z)


static func _marker_min_spacing(arch: StringName, radius: float) -> float:
	match arch:
		&"sea_stack":
			return 5.5
		&"wreck_shoal":
			return 6.2
		&"treasure_peak", &"treasure_cove":
			return 7.8
		&"outpost", &"outpost_harbour":
			return 9.5
		&"grand_outpost", &"grand_citadel", &"volcano_crag":
			return 15.0
		_:
			return clampf(radius * 0.11, 8.5, 14.0)


## Authored per-archetype marker stations `(poly_index, arc_fraction, kind)` targeting:
## - Outposts, forts, grand_citadel, smuggler_cove: 3..7 warm `&"lantern"` posts depending on tier.
## - Wild treasure/cove/volcano/shoal islands: mix of 2..5 `&"cairn"` markers + 1..3 `&"lantern"` posts.
static func _build_marker_plan(arch: StringName, poly_count: int) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	match arch:
		&"outpost", &"outpost_harbour":
			plan = [
				{"poly": 0, "t": 0.34, "kind": &"lantern"},
				{"poly": 0, "t": 0.62, "kind": &"lantern"},
				{"poly": 0, "t": 0.82, "kind": &"lantern"},
				{"poly": 0, "t": 0.96, "kind": &"lantern"},
				{"poly": 1, "t": 0.56, "kind": &"lantern"},
				{"poly": 1, "t": 0.88, "kind": &"lantern"},
			]
		&"grand_outpost":
			plan = [
				{"poly": 0, "t": 0.30, "kind": &"lantern"},
				{"poly": 0, "t": 0.58, "kind": &"lantern"},
				{"poly": 0, "t": 0.88, "kind": &"lantern"},
				{"poly": 1, "t": 0.64, "kind": &"lantern"},
				{"poly": 1, "t": 0.90, "kind": &"lantern"},
				{"poly": 2, "t": 0.44, "kind": &"lantern"},
				{"poly": 2, "t": 0.78, "kind": &"lantern"},
			]
		&"fort_rock":
			plan = [
				{"poly": 0, "t": 0.08, "kind": &"lantern"},
				{"poly": 0, "t": 0.66, "kind": &"lantern"},
				{"poly": 1, "t": 0.08, "kind": &"lantern"},
				{"poly": 1, "t": 0.28, "kind": &"lantern"},
				{"poly": 1, "t": 0.74, "kind": &"lantern"},
				{"poly": 1, "t": 0.94, "kind": &"lantern"},
			]
		&"grand_citadel":
			plan = [
				{"poly": 0, "t": 0.12, "kind": &"lantern"},
				{"poly": 0, "t": 0.36, "kind": &"lantern"},
				{"poly": 0, "t": 0.78, "kind": &"lantern"},
				{"poly": 1, "t": 0.34, "kind": &"lantern"},
				{"poly": 1, "t": 0.84, "kind": &"cairn"},
				{"poly": 2, "t": 0.36, "kind": &"lantern"},
				{"poly": 2, "t": 0.86, "kind": &"lantern"},
			]
		&"smuggler_cove":
			plan = [
				{"poly": 0, "t": 0.16, "kind": &"lantern"},
				{"poly": 0, "t": 0.52, "kind": &"lantern"},
				{"poly": 1, "t": 0.24, "kind": &"lantern"},
				{"poly": 1, "t": 0.60, "kind": &"lantern"},
				{"poly": 1, "t": 0.92, "kind": &"cairn"},
			]
		&"treasure_peak", &"treasure_cove":
			plan = [
				{"poly": 0, "t": 0.12, "kind": &"lantern"},
				{"poly": 0, "t": 0.44, "kind": &"lantern"},
				{"poly": 0, "t": 0.78, "kind": &"cairn"},
				{"poly": 1, "t": 0.46, "kind": &"cairn"},
				{"poly": 1, "t": 0.88, "kind": &"cairn"},
			]
		&"twin_spires":
			plan = [
				{"poly": 0, "t": 0.10, "kind": &"lantern"},
				{"poly": 0, "t": 0.32, "kind": &"cairn"},
				{"poly": 0, "t": 0.54, "kind": &"lantern"},
				{"poly": 0, "t": 0.78, "kind": &"cairn"},
				{"poly": 0, "t": 0.94, "kind": &"lantern"},
				{"poly": 1, "t": 0.80, "kind": &"cairn"},
			]
		&"crescent_lagoon":
			plan = [
				{"poly": 0, "t": 0.12, "kind": &"lantern"},
				{"poly": 0, "t": 0.38, "kind": &"cairn"},
				{"poly": 0, "t": 0.68, "kind": &"cairn"},
				{"poly": 0, "t": 0.92, "kind": &"cairn"},
				{"poly": 1, "t": 0.18, "kind": &"lantern"},
				{"poly": 1, "t": 0.76, "kind": &"cairn"},
			]
		&"sea_arch":
			plan = [
				{"poly": 0, "t": 0.24, "kind": &"lantern"},
				{"poly": 0, "t": 0.58, "kind": &"cairn"},
				{"poly": 0, "t": 0.88, "kind": &"cairn"},
				{"poly": 1, "t": 0.34, "kind": &"lantern"},
				{"poly": 1, "t": 0.80, "kind": &"cairn"},
			]
		&"wreck_shoal":
			plan = [
				{"poly": 0, "t": 0.08, "kind": &"lantern"},
				{"poly": 0, "t": 0.48, "kind": &"cairn"},
				{"poly": 0, "t": 0.86, "kind": &"cairn"},
			]
		&"volcano_crag":
			plan = [
				{"poly": 0, "t": 0.12, "kind": &"lantern"},
				{"poly": 0, "t": 0.52, "kind": &"cairn"},
				{"poly": 0, "t": 0.86, "kind": &"cairn"},
				{"poly": 1, "t": 0.22, "kind": &"lantern"},
				{"poly": 1, "t": 0.58, "kind": &"cairn"},
				{"poly": 1, "t": 0.88, "kind": &"cairn"},
			]
		&"skull_bluff":
			plan = [
				{"poly": 0, "t": 0.12, "kind": &"lantern"},
				{"poly": 0, "t": 0.36, "kind": &"lantern"},
				{"poly": 0, "t": 0.62, "kind": &"cairn"},
				{"poly": 0, "t": 0.90, "kind": &"cairn"},
				{"poly": 1, "t": 0.44, "kind": &"cairn"},
				{"poly": 1, "t": 0.84, "kind": &"cairn"},
			]
		&"sea_stack":
			plan = [
				{"poly": 0, "t": 0.12, "kind": &"lantern"},
				{"poly": 0, "t": 0.54, "kind": &"cairn"},
				{"poly": 0, "t": 0.88, "kind": &"cairn"},
			]
		&"palm_atoll":
			plan = [
				{"poly": 0, "t": 0.12, "kind": &"lantern"},
				{"poly": 0, "t": 0.48, "kind": &"cairn"},
				{"poly": 0, "t": 0.84, "kind": &"cairn"},
				{"poly": 1, "t": 0.16, "kind": &"lantern"},
				{"poly": 1, "t": 0.78, "kind": &"cairn"},
			]
		_:
			plan = [
				{"poly": 0, "t": 0.16, "kind": &"lantern"},
				{"poly": 0, "t": 0.54, "kind": &"cairn"},
				{"poly": 0, "t": 0.88, "kind": &"cairn"},
			]

	if poly_count <= 1:
		var clamped: Array[Dictionary] = []
		for item in plan:
			if int(item["poly"]) == 0:
				clamped.append(item)
		return clamped
	return plan


## Canonical `(u, v)` keepout circles mirroring `IslandGenerator` and `IslandLandmarks`
## exclusions so trail markers never clip into buildings, plazas, ramps, bridges,
## fort bastions, shipwrecks, or grotto walls.
static func _is_in_landmark_keepout(arch: StringName, radius: float, u: float, v: float) -> bool:
	var s := maxf(radius / 60.0, 0.35)
	var pt := Vector2(u, v)

	if arch == &"outpost" or arch == &"outpost_harbour" or arch == &"grand_outpost":
		var out_zones: Array[Vector3] = [
			Vector3(0.0, -34.0, 15.4),    # Dock pier & ramp head
			Vector3(4.5, -39.5, 11.4),    # Mooring apron
			Vector3(0.0, -18.0, 15.0),    # Central harbour plaza keepout
			Vector3(-11.0, -7.5, 11.0),   # Outpost Tavern footprint
			Vector3(24.0, -6.5, 9.5),     # Beacon Tower headland footprint
			Vector3(9.2, -18.5, 7.0),     # Merchant Stall
			Vector3(-6.6, -19.5, 4.8),    # Voyage Notice Board
			Vector3(-23.5, -16.5, 8.0),   # Harbour Warehouse 0
			Vector3(-34.0, -10.0, 6.6),   # Headland Watchtower 0
		]
		if arch == &"grand_outpost":
			out_zones.append(Vector3(22.0, -21.0, 8.0))   # Harbour Warehouse 1
			out_zones.append(Vector3(-28.0, -34.0, 8.0))  # Harbour Warehouse 2
			out_zones.append(Vector3(56.0, -24.0, 6.8))   # East Headland Watchtower
			out_zones.append(Vector3(-64.0, -54.0, 6.8))  # West Headland Watchtower
			out_zones.append(Vector3(41.0, -8.0, 7.8))    # TempleStairway_Overlook
			out_zones.append(Vector3(-49.0, -45.0, 7.4))  # CliffCatwalkPier_West
			out_zones.append(Vector3(38.0, -39.0, 7.4))   # CliffCatwalkPier_East
		for z in out_zones:
			if pt.distance_squared_to(Vector2(z.x, z.y)) < z.z * z.z:
				return true
		return false

	match arch:
		&"fort_rock":
			var f_zones: Array[Vector3] = [
				Vector3(0.0, 2.0 * s, 17.8),
				Vector3(0.0, -13.5 * s, 7.3),
				Vector3(0.0, -22.5 * s, 7.3),
				Vector3(0.0, -31.0 * s, 7.3),
				Vector3(-28.0, -6.0, 6.6),
				Vector3(28.0, -6.0, 6.6),
				Vector3(-34.0, -24.0, 7.8),
				Vector3(34.0, -24.0, 7.8),
			]
			for z in f_zones:
				if pt.distance_squared_to(Vector2(z.x, z.y)) < z.z * z.z:
					return true
		&"grand_citadel":
			var c_zones: Array[Vector3] = [
				Vector3(0.0, 18.0, 20.5),
				Vector3(0.0, -10.0, 9.0),
				Vector3(0.0, -28.0, 9.0),
				Vector3(0.0, -48.0, 9.0),
				Vector3(0.0, -68.0, 9.0),
				Vector3(-42.0, -14.0, 7.2),   # CitadelTimberBridge
				Vector3(-54.0, -14.0, 7.8),   # TempleStairway_West
				Vector3(54.0, -5.0, 7.8),     # TempleStairway_East
				Vector3(-72.0, 12.0, 7.8),    # CitadelRuinArch_0
				Vector3(72.0, 12.0, 7.8),     # CitadelRuinArch_1
				Vector3(-36.0, -26.0, 7.8),   # CitadelSeawall_2
				Vector3(36.0, -24.0, 7.8),    # CitadelSeawall_3
			]
			for z in c_zones:
				if pt.distance_squared_to(Vector2(z.x, z.y)) < z.z * z.z:
					return true
		&"twin_spires":
			var ts_zones: Array[Vector3] = [
				Vector3(0.0, -6.0 * s, 6.8),      # CanyonTimberBridge
				Vector3(1.3 * s, 8.7 * s, 7.2),   # TempleStairway_Canyon
				Vector3(7.0 * s, -16.0 * s, 6.8), # CanyonRuinArch_1
				Vector3(-6.0 * s, 6.0 * s, 6.8),  # CanyonRuinArch_0
			]
			for z in ts_zones:
				if pt.distance_squared_to(Vector2(z.x, z.y)) < z.z * z.z:
					return true
		&"skull_bluff":
			var sb_zones: Array[Vector3] = [
				Vector3(0.0, -26.0 * s, 6.6),      # BluffTimberBridge
				Vector3(0.0, -10.0 * s, 8.0),      # SkullCliffCarving
				Vector3(-24.0 * s, -10.0 * s, 7.0),# HighlandRuinArch
				Vector3(24.0 * s, -12.0 * s, 4.8), # HighlandRuinPillar_0
				Vector3(-18.0 * s, -22.0 * s, 4.8),# HighlandRuinPillar_1
			]
			for z in sb_zones:
				if pt.distance_squared_to(Vector2(z.x, z.y)) < z.z * z.z:
					return true
		&"smuggler_cove":
			var vg := 6.0 * s
			if pt.distance_squared_to(Vector2(0.0, vg + 5.5)) < 11.6 * 11.6:
				return true
			if pt.distance_squared_to(Vector2(0.0, vg - 1.8)) < 8.2 * 8.2:
				return true
			if pt.distance_squared_to(Vector2(26.0, -10.0)) < 6.8 * 6.8:
				return true
		&"sea_arch":
			if pt.distance_squared_to(Vector2(0.0, -radius * 0.45)) < 10.0 * 10.0:
				return true
		&"wreck_shoal":
			if pt.distance_squared_to(Vector2(-12.0, -radius * 0.62)) < 9.0 * 9.0:
				return true
			if pt.distance_squared_to(Vector2(20.0, -radius * 0.44)) < 8.5 * 8.5:
				return true
			if pt.distance_squared_to(Vector2(5.0, -3.0)) < 8.6 * 8.6:
				return true
		&"sea_stack":
			if pt.distance_squared_to(Vector2(-4.0, -12.0)) < 8.8 * 8.8:
				return true
			if pt.distance_squared_to(Vector2(18.0, -11.0)) < 8.4 * 8.4:
				return true

	return false
