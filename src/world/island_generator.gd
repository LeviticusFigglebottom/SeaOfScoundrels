class_name IslandGenerator
extends RefCounted
## Deterministic procedural island generator for Sea of Scoundrels.
##
## Builds sculpted painterly islands across 11 distinct archetypes with gentle
## walkable sandy beaches descending smoothly into luminous turquoise shallows
## and a -20 m seabed, topped by chunky faceted coastal cliffs & spires (30-92 m),
## ground-snapped stylized props, convex `col_*` prop colliders, foliage wind
## shaders, and simplified coastline contours for maps & charts.

const ISLAND_SHADER: Shader = preload("res://src/world/island_shader.gdshader")
const FOLIAGE_SHADER: Shader = preload("res://src/world/foliage_wind.gdshader")

const PALM_TALL_SCENE: PackedScene = preload("res://assets/generated/props/palm_tall.glb")
const PALM_CURVED_SCENE: PackedScene = preload("res://assets/generated/props/palm_curved.glb")
const BUSH_FERN_SCENE: PackedScene = preload("res://assets/generated/props/bush_fern.glb")
const ROCK_BOULDER_SCENE: PackedScene = preload("res://assets/generated/props/rock_boulder.glb")
const ROCK_SPIRE_SCENE: PackedScene = preload("res://assets/generated/props/rock_spire.glb")
const ROCK_ARCH_SCENE: PackedScene = preload("res://assets/generated/props/rock_arch.glb")
const SHIPWRECK_SCENE: PackedScene = preload("res://assets/generated/props/shipwreck_hulk.glb")
const BARREL_SCENE: PackedScene = preload("res://assets/generated/props/barrel_prop.glb")
const CRATE_SCENE: PackedScene = preload("res://assets/generated/props/crate_supply.glb")
const CAMPFIRE_SCENE: PackedScene = preload("res://assets/generated/props/campfire.glb")

const ARCHETYPES: Array[StringName] = [
	&"outpost",
	&"treasure_peak",
	&"twin_spires",
	&"crescent_lagoon",
	&"sea_arch",
	&"fort_rock",
	&"wreck_shoal",
	&"volcano_crag",
	&"palm_atoll",
	&"skull_bluff",
	&"smuggler_cove",
]

const LAYER_WORLD_STATIC := 1
const SEA_FLOOR_Y := -20.0
const CONTOUR_SAMPLES := 36


## Build a complete procedural `Island` (or `Outpost` when `archetype == &"outpost"`).
## `spec` keys (all optional except defaults):
##   id (String), name (String), archetype (StringName), kind (StringName),
##   seed (int), radius (float), peak_height (float), dock_yaw (float),
##   landing_yaw (float), landmarks (Array[String]), spawn_default_dig_site (bool),
##   default_treasure_id (StringName).
static func build_island(spec: Dictionary) -> Island:
	var arch := StringName(String(spec.get("archetype", &"treasure_peak")))
	if not ARCHETYPES.has(arch):
		arch = &"treasure_peak"
	var is_outpost := arch == &"outpost" or bool(spec.get("is_outpost", false))
	var island: Island = Outpost.new() if is_outpost else Island.new()

	var id_str := String(spec.get("id", spec.get("island_id", "island_" + String(arch))))
	var disp_name := String(spec.get("name", spec.get("display_name", id_str.replace("_", " ").capitalize())))
	var seed_val := int(spec.get("seed", _stable_hash(id_str)))
	var radius := float(spec.get("radius", _default_radius(arch)))
	var target_peak := float(spec.get("peak_height", _default_peak(arch)))
	var dock_yaw := float(spec.get("dock_yaw", 0.0))
	var landing_yaw := float(spec.get("landing_yaw", dock_yaw))

	island.name = disp_name.replace(" ", "_").replace("'", "")
	island.island_id = id_str
	island.display_name = disp_name
	island.archetype = arch
	island.kind = StringName(String(spec.get("kind", _default_kind(arch))))
	island.is_outpost = is_outpost
	island.island_radius = radius
	island.seabed_radius = radius + 62.0
	island.peak_height = target_peak

	var lm_raw: Variant = spec.get("landmarks", _default_landmarks(arch))
	var lm_typed: Array[String] = []
	if lm_raw is Array:
		for item in lm_raw as Array:
			lm_typed.append(String(item))
	island.landmarks = lm_typed

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	# Build sculpted terrain height grid, visual mesh, and walkable StaticBody3D collider.
	var grid_res := 80 if is_outpost else 72
	var grid_half := island.seabed_radius + 8.0
	var grid := _generate_height_grid(arch, radius, island.seabed_radius, target_peak,
		landing_yaw, seed_val, grid_res, grid_half)
	island.set_height_grid(grid, grid_res, grid_half, SEA_FLOOR_Y)

	# Record true peak height from generated vertices.
	var max_h := 0.0
	for h in grid:
		if h > max_h:
			max_h = h
	island.peak_height = max_h

	var terrain_mat := _create_terrain_material(arch)
	_build_terrain_mesh_and_collider(island, grid, grid_res, grid_half, terrain_mat)

	# Extract coastline polygon in local XZ for Map Table & held Treasure Maps.
	island.contour_points = _extract_contour_points(island)

	# Shared static collider body for all solid props (`col_*` convex shapes).
	var prop_body := StaticBody3D.new()
	prop_body.name = "PropColliders"
	prop_body.collision_layer = LAYER_WORLD_STATIC
	prop_body.collision_mask = 0
	island.add_child(prop_body)

	var props_root := Node3D.new()
	props_root.name = "Props"
	island.add_child(props_root)

	# Build outpost structures or non-outpost mooring & dig/enemy sites.
	var exclusions: Array[Vector3] = []  # (x, z, keepout_radius)
	if is_outpost and island is Outpost:
		var op := island as Outpost
		op.build_outpost_structures(dock_yaw, rng, prop_body, props_root)
		var db := Basis(Vector3.UP, dock_yaw)
		# Keep trees and rocks clear of the harbour channel, pier, village plaza, and beacon shelf.
		var keepouts: Array[Array] = [
			[0.0, -34.0, 15.0],
			[4.5, -39.5, 11.0],
			[0.0, -18.0, 14.5],
			[-11.0, -7.5, 10.5],
			[9.2, -18.5, 6.5],
			[-6.6, -19.5, 4.5],
			[24.0, -6.5, 9.0],
		]
		for k in keepouts:
			var wp := db * Vector3(float(k[0]), 0.0, float(k[1]))
			exclusions.append(Vector3(wp.x, wp.z, float(k[2])))
	else:
		island.mooring_transform = _compute_non_outpost_mooring(island, landing_yaw)

	# Gather verified walkable beach/clearing spots for buried treasure & enemy spawns.
	_populate_gameplay_points(island, landing_yaw, exclusions, rng)
	for dp in island.dig_points:
		exclusions.append(Vector3(dp.x, dp.z, 3.6))

	# Optionally spawn a ready-to-dig treasure mound (e.g., on Cutlass Cay or standalone islands).
	if bool(spec.get("spawn_default_dig_site", false)) and not island.dig_points.is_empty():
		var tid := StringName(String(spec.get("default_treasure_id", &"wayfarer_chest")))
		island.spawn_dig_site(island.dig_points[0], tid)

	# Place ground-snapped stylized props (palms, ferns, boulders, spires, arches, wrecks, campfires).
	var foliage_mat_cache: Dictionary = {}
	_populate_archetype_props(island, arch, landing_yaw, exclusions, rng, prop_body, props_root, foliage_mat_cache)

	return island


# ============================================================ heightfield sculpting

static func _generate_height_grid(arch: StringName, radius: float, seabed_r: float,
		target_peak: float, yaw: float, seed_val: int, grid_res: int,
		grid_half: float) -> PackedFloat32Array:
	var stride := grid_res + 1
	var grid := PackedFloat32Array()
	grid.resize(stride * stride)
	var span := grid_half * 2.0
	var cos_y := cos(yaw)
	var sin_y := sin(yaw)

	for iz in stride:
		var lz := -grid_half + span * float(iz) / float(grid_res)
		for ix in stride:
			var lx := -grid_half + span * float(ix) / float(grid_res)
			# Inverse of Basis(Vector3.UP, yaw): maps local (lx, lz) into canonical
			# harbour/landing frame where -v faces seaward and +u faces starboard.
			var u := lx * cos_y - lz * sin_y
			var v := lx * sin_y + lz * cos_y
			grid[iz * stride + ix] = _eval_height(arch, u, v, radius, seabed_r, target_peak, seed_val)
	return grid


static func _eval_height(arch: StringName, u: float, v: float, radius: float,
		seabed_r: float, target_peak: float, seed_val: int) -> float:
	var r := sqrt(u * u + v * v)
	var ang := atan2(v, u)
	var s := float(seed_val % 4096) * 0.137

	# Organic coastal perimeter wobble (low-frequency bays & headlands).
	var coast_n := _fbm2(u * 0.022 + s, v * 0.022 - s * 0.7) - 0.5
	var detail_n := _fbm2(u * 0.068 - s * 0.4, v * 0.068 + s * 0.9) - 0.5
	var ridge_n := 1.0 - absf(_fbm2(u * 0.052 + s * 1.3, v * 0.052 + s * 0.5) * 2.0 - 1.0)

	# Base coastline silhouette per archetype.
	var r_coast := radius * (1.0 + 0.16 * coast_n + 0.07 * cos(ang * 2.0 + s) + 0.05 * sin(ang * 3.0 - s))
	if arch == &"crescent_lagoon" or arch == &"palm_atoll":
		r_coast = radius * (1.02 + 0.10 * coast_n)
	elif arch == &"wreck_shoal":
		r_coast = radius * (1.06 + 0.18 * cos(ang * 2.0 - 0.4) + 0.14 * coast_n)
	elif arch == &"outpost":
		# Slight horseshoe harbour indentation on the -v (seaward) flank.
		var bay_ang := exp(-pow(u / 26.0, 2.0)) * _smoothstep(-4.0, -28.0, v)
		r_coast = radius * (1.0 + 0.11 * coast_n) - 18.0 * bay_ang

	var d_shore := r - r_coast

	# Base coastal elevation curve:
	#   seaward: gentle glowing turquoise shallows (0..-3.8 m over ~18 m), then smooth drop to -20 m
	#   landward: walkable golden beach (0..+3.0 m over ~16 m, slope < 12 deg), then lush rolling ground
	var base_h := 0.0
	if d_shore >= 0.0:
		var shallow_span := 20.0 if arch != &"wreck_shoal" else 30.0
		var deep_span := maxf(24.0, seabed_r - r_coast - shallow_span)
		if d_shore <= shallow_span:
			var t := d_shore / shallow_span
			base_h = -3.8 * (t * t * (2.0 - t))
		else:
			var t2 := clampf((d_shore - shallow_span) / deep_span, 0.0, 1.0)
			base_h = lerpf(-3.8, SEA_FLOOR_Y, t2 * t2 * (3.0 - 2.0 * t2))
	else:
		var inland := -d_shore
		var beach_t := clampf(inland / 17.0, 0.0, 1.0)
		var hill_t := clampf((inland - 12.0) / maxf(18.0, radius * 0.65), 0.0, 1.0)
		base_h = 3.0 * (beach_t * (2.0 - beach_t)) + 5.2 * (hill_t * hill_t * (3.0 - 2.0 * hill_t))
		base_h += detail_n * 1.4 * hill_t

	# Archetype-specific dramatic faceted cliffs, spires, lagoons, coves, and harbour grading.
	var h := base_h
	var scale_r := radius / 60.0

	match arch:
		&"outpost":
			# Dramatic twin-shouldered limestone backdrop behind the village (+v) + western cliff arm.
			var p1 := _faceted_spire(u, v, -5.0 * scale_r, 23.0 * scale_r, 26.0 * scale_r, 23.0 * scale_r, target_peak, 0.35, 5.0, 1.38)
			var p2 := _faceted_spire(u, v, 15.0 * scale_r, 20.0 * scale_r, 18.0 * scale_r, 17.0 * scale_r, target_peak * 0.64, -0.45, 5.0, 1.45)
			var arm_w := _faceted_spire(u, v, -31.0 * scale_r, -8.0 * scale_r, 18.0 * scale_r, 20.0 * scale_r, target_peak * 0.44, 0.7, 4.0, 1.5)
			h = maxf(h, maxf(p1, maxf(p2, arm_w)))
			h += ridge_n * 2.2 * _smoothstep(6.0, 22.0, h)

			# Crisp beacon tower headland shelf at (u = +24, v = -6.5), flat top at y = 11.8 m.
			var bcn_mesa := _stepped_mesa(u, v, 24.0, -6.5, 13.5, 13.5, 11.8, 0.25, 6.0, 0.52)
			h = maxf(h, bcn_mesa)
			# Flatten beacon crown cleanly so beacon_tower.glb sits perfectly level.
			var bcn_d := Vector2(u - 24.0, v + 6.5).length()
			var bcn_flat := _smoothstep(9.0, 5.2, bcn_d)
			h = lerpf(h, 11.8, bcn_flat)

			# Smoothly graded walkable harbour village terrace (u in [-18..16], v in [-26..-1]).
			var plaza_u := _smoothstep(22.0, 13.0, absf(u + 1.5))
			var plaza_v := _smoothstep(-28.5, -23.5, v) * _smoothstep(6.0, -3.5, v)
			var plaza_mask := plaza_u * plaza_v
			var plaza_target := lerpf(0.35, 3.35, clampf((v + 25.8) / 18.5, 0.0, 1.0))
			h = lerpf(h, plaza_target, plaza_mask * 0.94)

			# Carve clean deep-water harbour pier channel & mooring basin (v <= -25.8).
			var chan_u := _smoothstep(20.0, 10.5, absf(u - 1.5))
			var chan_v := _smoothstep(-24.2, -29.5, v)
			var chan_mask := chan_u * chan_v
			var chan_depth := lerpf(0.38, -7.8, clampf((-25.5 - v) / 15.5, 0.0, 1.0))
			chan_depth = minf(chan_depth, lerpf(-7.8, SEA_FLOOR_Y, clampf((-41.0 - v) / 28.0, 0.0, 1.0)))
			h = lerpf(h, minf(h, chan_depth), chan_mask)

			# Guarantee exact gentle walkable sand ramp landing right at dock ramp foot (u=0, v=-25.75).
			var ramp_d := Vector2(u * 0.65, v + 25.75).length()
			var ramp_blend := _smoothstep(6.5, 2.2, ramp_d)
			h = lerpf(h, 0.34, ramp_blend)

		&"treasure_peak":
			# Iconic Cutlass Cay silhouette (matching image_2.png):
			# Sweeping golden sandy landing cove on the -v flank + towering twin pale-limestone spires!
			var sp1 := _faceted_spire(u, v, -3.0 * scale_r, 12.0 * scale_r, 25.0 * scale_r, 22.0 * scale_r, target_peak, 0.25, 5.0, 1.32)
			var sp2 := _faceted_spire(u, v, 17.0 * scale_r, 4.0 * scale_r, 17.0 * scale_r, 16.0 * scale_r, target_peak * 0.68, -0.55, 5.0, 1.42)
			var sp3 := _faceted_spire(u, v, -22.0 * scale_r, 16.0 * scale_r, 15.0 * scale_r, 14.0 * scale_r, target_peak * 0.45, 0.85, 4.0, 1.50)
			h = maxf(h, maxf(sp1, maxf(sp2, sp3)))
			h += ridge_n * 3.2 * _smoothstep(8.0, 26.0, h)
			# Grade a wide, welcoming golden sand cove on the -v landing beach.
			# Strictly monotonic inland from the shoreline contour (>= 1.45 m once
			# inland of the wet shore ramp) so ocean swells never poke through mid-beach.
			var cove_u := _smoothstep(30.0 * scale_r, 12.0 * scale_r, absf(u - 2.0 * scale_r))
			var cove_v := _smoothstep(6.0 * scale_r, -16.0 * scale_r, v)
			var cove_mask := cove_u * cove_v
			if d_shore < 0.0 and cove_mask > 0.001:
				var inland_c := -d_shore
				var cove_h := 1.48 + 1.42 * clampf((inland_c - 4.8) / (26.0 * scale_r), 0.0, 1.0)
				h = lerpf(h, minf(h, cove_h), cove_mask * 0.82)

		&"twin_spires":
			# Soaring cathedral-like twin pale-limestone needles separated by a walkable green saddle!
			var n1 := _faceted_spire(u, v, -16.0 * scale_r, 4.0 * scale_r, 21.0 * scale_r, 20.0 * scale_r, target_peak, 0.42, 5.0, 1.25)
			var n2 := _faceted_spire(u, v, 18.0 * scale_r, -2.0 * scale_r, 19.0 * scale_r, 18.0 * scale_r, target_peak * 0.76, -0.38, 5.0, 1.30)
			var crag := _faceted_spire(u, v, 2.0 * scale_r, 22.0 * scale_r, 15.0 * scale_r, 14.0 * scale_r, target_peak * 0.42, 1.1, 4.0, 1.48)
			h = maxf(h, maxf(n1, maxf(n2, crag)))
			h += ridge_n * 3.4 * _smoothstep(10.0, 30.0, h)

		&"crescent_lagoon":
			# C-shaped coral-sand ring embracing a glowing turquoise shallow lagoon + back crag!
			var lag_d := Vector2(u, v + 8.0 * scale_r).length()
			var lag_mouth := _smoothstep(20.0 * scale_r, 6.0 * scale_r, absf(u)) * _smoothstep(-6.0 * scale_r, -26.0 * scale_r, v)
			var lag_pool := _smoothstep(28.0 * scale_r, 14.0 * scale_r, lag_d)
			var lagoon_mask := clampf(maxf(lag_pool, lag_mouth), 0.0, 1.0)
			var back_crag := _faceted_spire(u, v, 4.0 * scale_r, 29.0 * scale_r, 21.0 * scale_r, 16.0 * scale_r, target_peak, 0.18, 5.0, 1.40)
			var horn_w := _faceted_spire(u, v, -31.0 * scale_r, 8.0 * scale_r, 14.0 * scale_r, 18.0 * scale_r, target_peak * 0.42, 0.65, 4.0, 1.55)
			h = maxf(h, maxf(back_crag, horn_w))
			h = lerpf(h, -2.2 + 0.5 * detail_n, lagoon_mask * 0.92)

		&"sea_arch":
			# Twin coastal headlands cradling a bright sandy tide bay (crowned with rock_arch.glb).
			var b_l := _faceted_spire(u, v, -24.0 * scale_r, 6.0 * scale_r, 21.0 * scale_r, 22.0 * scale_r, target_peak, 0.30, 5.0, 1.38)
			var b_r := _faceted_spire(u, v, 24.0 * scale_r, 10.0 * scale_r, 19.0 * scale_r, 20.0 * scale_r, target_peak * 0.78, -0.45, 5.0, 1.42)
			var b_back := _faceted_spire(u, v, 0.0, 26.0 * scale_r, 18.0 * scale_r, 15.0 * scale_r, target_peak * 0.52, 0.12, 4.0, 1.50)
			h = maxf(h, maxf(b_l, maxf(b_r, b_back)))
			# Soft sandy cove trough between the twin bluffs.
			var bay := _smoothstep(18.0 * scale_r, 6.0 * scale_r, absf(u)) * _smoothstep(12.0 * scale_r, -16.0 * scale_r, v)
			h = lerpf(h, clampf(lerpf(-1.8, 2.8, (v + 30.0 * scale_r) / (40.0 * scale_r)), -2.2, 3.0), bay * 0.72)

		&"fort_rock":
			# Sheer tiered flat-topped bastion mesa with walkable landing ramp flank!
			var mesa := _stepped_mesa(u, v, 0.0, 6.0 * scale_r, 34.0 * scale_r, 30.0 * scale_r, target_peak * 0.78, 0.20, 6.0, 0.56)
			var citadel := _stepped_mesa(u, v, -6.0 * scale_r, 12.0 * scale_r, 17.0 * scale_r, 16.0 * scale_r, target_peak, -0.15, 5.0, 0.45)
			h = maxf(h, maxf(mesa, citadel))
			# Walkable sloped landing beach & bastion approach on the -v side.
			var appr_u := _smoothstep(22.0 * scale_r, 10.0 * scale_r, absf(u - 6.0 * scale_r))
			var appr_v := _smoothstep(-2.0 * scale_r, -24.0 * scale_r, v)
			var appr_h := lerpf(1.2, 8.0, clampf((v + 36.0 * scale_r) / (34.0 * scale_r), 0.0, 1.0))
			h = lerpf(h, minf(h, appr_h), appr_u * appr_v * 0.75)

		&"wreck_shoal":
			# Broad shallow sandbars & jagged knife-edge limestone ribs for dramatic shipwrecks.
			var rib1 := _faceted_spire(u, v, -14.0 * scale_r, 14.0 * scale_r, 22.0 * scale_r, 11.0 * scale_r, target_peak, 0.52, 4.0, 1.35)
			var rib2 := _faceted_spire(u, v, 18.0 * scale_r, 8.0 * scale_r, 16.0 * scale_r, 10.0 * scale_r, target_peak * 0.72, -0.62, 4.0, 1.45)
			var rib3 := _faceted_spire(u, v, 2.0 * scale_r, -10.0 * scale_r, 11.0 * scale_r, 14.0 * scale_r, target_peak * 0.36, 0.15, 4.0, 1.55)
			h = maxf(h, maxf(rib1, maxf(rib2, rib3)))
			# Broad sandy shoal apron extending seaward on -v.
			var shoal := _smoothstep(42.0 * scale_r, 14.0 * scale_r, Vector2(u, v + 22.0 * scale_r).length())
			h = maxf(h, lerpf(-3.2, 1.8, shoal) + detail_n * 0.6)

		&"volcano_crag":
			# Towering jagged basalt volcanic cone with breached summit caldera rim!
			var v_dist := Vector2(u, v - 4.0 * scale_r).length()
			var cone := _faceted_spire(u, v, 0.0, 4.0 * scale_r, 48.0 * scale_r, 46.0 * scale_r, target_peak * 1.12, 0.18, 7.0, 1.18)
			# Carve summit caldera depression so the jagged caldera rim stands bold against the sky!
			var caldera := _smoothstep(18.0 * scale_r, 5.0 * scale_r, v_dist)
			cone -= caldera * (target_peak * 0.34)
			var spur := _faceted_spire(u, v, 26.0 * scale_r, 16.0 * scale_r, 18.0 * scale_r, 16.0 * scale_r, target_peak * 0.48, -0.6, 5.0, 1.42)
			h = maxf(h, maxf(cone, spur))
			h += ridge_n * 4.2 * _smoothstep(12.0, 40.0, h)
			# Narrow walkable pocket beach on the -v landing flank.
			var pock := _smoothstep(20.0 * scale_r, 8.0 * scale_r, absf(u)) * _smoothstep(-14.0 * scale_r, -36.0 * scale_r, v)
			h = lerpf(h, minf(h, 2.2), pock * 0.72)

		&"palm_atoll":
			# Lush coral ring atoll with turquoise center lagoon, sandy dunes, and a single windward crag.
			var c_dist := Vector2(u, v).length()
			var ring_band := exp(-pow((c_dist - radius * 0.64) / (radius * 0.24), 2.0))
			var channel := _smoothstep(14.0 * scale_r, 4.0 * scale_r, absf(u)) * _smoothstep(0.0, -radius * 0.9, v)
			var atoll_h := lerpf(SEA_FLOOR_Y, 4.4 + detail_n * 1.5, clampf(ring_band * 1.35, 0.0, 1.0))
			var inner_lagoon := _smoothstep(radius * 0.56, radius * 0.28, c_dist)
			atoll_h = lerpf(atoll_h, -2.0 + detail_n * 0.4, inner_lagoon)
			atoll_h = lerpf(atoll_h, -2.8, channel * 0.85)
			var rock_head := _faceted_spire(u, v, 22.0 * scale_r, 24.0 * scale_r, 18.0 * scale_r, 16.0 * scale_r, target_peak, 0.4, 5.0, 1.42)
			h = maxf(maxf(base_h * 0.35, atoll_h), rock_head)

		&"skull_bluff":
			# Ominous stepped limestone headland mesa with twin recessed cliff brow hollows & crown crags!
			var head := _stepped_mesa(u, v, 0.0, 10.0 * scale_r, 34.0 * scale_r, 28.0 * scale_r, target_peak * 0.86, 0.08, 6.0, 0.42)
			var crown_l := _faceted_spire(u, v, -14.0 * scale_r, 14.0 * scale_r, 16.0 * scale_r, 15.0 * scale_r, target_peak, 0.25, 5.0, 1.35)
			var crown_r := _faceted_spire(u, v, 14.0 * scale_r, 14.0 * scale_r, 16.0 * scale_r, 15.0 * scale_r, target_peak * 0.92, -0.25, 5.0, 1.35)
			h = maxf(h, maxf(head, maxf(crown_l, crown_r)))
			# Twin dark cliff brow hollows on the -v sea-facing wall.
			var h_l := _smoothstep(10.0 * scale_r, 3.0 * scale_r, Vector2(u + 11.0 * scale_r, v + 8.0 * scale_r).length())
			var h_r := _smoothstep(10.0 * scale_r, 3.0 * scale_r, Vector2(u - 11.0 * scale_r, v + 8.0 * scale_r).length())
			h -= (h_l + h_r) * (target_peak * 0.22)
			h += ridge_n * 2.8 * _smoothstep(10.0, 32.0, h)

		&"smuggler_cove":
			# Steep horseshoe cliff amphitheatre enclosing a hidden pocket beach!
			var back_wall := _faceted_spire(u, v, 0.0, 26.0 * scale_r, 34.0 * scale_r, 20.0 * scale_r, target_peak, 0.05, 6.0, 1.30)
			var wing_l := _faceted_spire(u, v, -28.0 * scale_r, 2.0 * scale_r, 18.0 * scale_r, 24.0 * scale_r, target_peak * 0.74, 0.35, 5.0, 1.38)
			var wing_r := _faceted_spire(u, v, 28.0 * scale_r, 4.0 * scale_r, 18.0 * scale_r, 22.0 * scale_r, target_peak * 0.68, -0.35, 5.0, 1.40)
			h = maxf(h, maxf(back_wall, maxf(wing_l, wing_r)))
			# Sheltered sandy pocket cove carved right into the amphitheatre heart.
			var cov := _smoothstep(22.0 * scale_r, 10.0 * scale_r, Vector2(u, v + 6.0 * scale_r).length())
			var mouth := _smoothstep(13.0 * scale_r, 5.0 * scale_r, absf(u)) * _smoothstep(-2.0 * scale_r, -28.0 * scale_r, v)
			var target_cov := lerpf(-2.4, 2.6, clampf((v + 24.0 * scale_r) / (26.0 * scale_r), 0.0, 1.0))
			h = lerpf(h, minf(h, target_cov), clampf(maxf(cov, mouth), 0.0, 1.0) * 0.88)

	# Keep outer skirt pinned cleanly to SEA_FLOOR_Y so islands blend seamlessly into deep ocean.
	var outer_t := _smoothstep(seabed_r - 12.0, seabed_r + 2.0, r)
	return lerpf(h, SEA_FLOOR_Y, outer_t)


static func _faceted_spire(u: float, v: float, cx: float, cz: float, rx: float, rz: float,
		height: float, yaw: float, facets: float, sharpness: float) -> float:
	var dx := u - cx
	var dz := v - cz
	var c := cos(-yaw)
	var s := sin(-yaw)
	var lx := (dx * c - dz * s) / maxf(rx, 1.0)
	var lz := (dx * s + dz * c) / maxf(rz, 1.0)
	var r := sqrt(lx * lx + lz * lz)
	if r >= 1.35:
		return SEA_FLOOR_Y
	var ang := atan2(lz, lx)
	var r_fac := r * (1.0 + 0.14 * cos(ang * facets + yaw * 1.7) + 0.07 * sin(ang * (facets + 2.0) - 0.8))
	var profile := pow(clampf(1.0 - r_fac, 0.0, 1.0), sharpness)
	var h := profile * height
	# Subtle geological terrace steps on steep limestone cliffs.
	if h > 5.0:
		h += 0.032 * height * sin(h * 0.42) * clampf(profile * 2.4, 0.0, 1.0)
	return h


static func _stepped_mesa(u: float, v: float, cx: float, cz: float, rx: float, rz: float,
		height: float, yaw: float, facets: float, flat_top: float) -> float:
	var dx := u - cx
	var dz := v - cz
	var c := cos(-yaw)
	var s := sin(-yaw)
	var lx := (dx * c - dz * s) / maxf(rx, 1.0)
	var lz := (dx * s + dz * c) / maxf(rz, 1.0)
	var r := sqrt(lx * lx + lz * lz)
	if r >= 1.35:
		return SEA_FLOOR_Y
	var ang := atan2(lz, lx)
	var r_fac := r * (1.0 + 0.10 * cos(ang * facets + yaw))
	var t := clampf((1.0 - r_fac) / maxf(1.0 - flat_top, 0.12), 0.0, 1.0)
	var prof := t * t * (3.0 - 2.0 * t)
	var h := prof * height
	if t > 0.05 and t < 0.92:
		h += 0.04 * height * sin(t * PI * 4.0)
	return h


# ============================================================ terrain mesh & collider

static func _create_terrain_material(arch: StringName) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = ISLAND_SHADER
	match arch:
		&"volcano_crag":
			mat.set_shader_parameter(&"cliff_tint", Color(0.45, 0.43, 0.48))
			mat.set_shader_parameter(&"grass_tint", Color(0.76, 0.80, 0.56))
		&"twin_spires":
			mat.set_shader_parameter(&"cliff_tint", Color(1.02, 1.00, 0.96))
			mat.set_shader_parameter(&"grass_tint", Color(0.92, 1.12, 0.90))
		&"crescent_lagoon", &"palm_atoll":
			mat.set_shader_parameter(&"cliff_tint", Color(1.04, 0.98, 0.88))
			mat.set_shader_parameter(&"grass_tint", Color(1.06, 1.08, 0.92))
		&"fort_rock", &"skull_bluff":
			mat.set_shader_parameter(&"cliff_tint", Color(0.92, 0.90, 0.87))
		_:
			mat.set_shader_parameter(&"cliff_tint", Color(1.0, 1.0, 1.0))
			mat.set_shader_parameter(&"grass_tint", Color(1.0, 1.0, 1.0))
	return mat


static func _build_terrain_mesh_and_collider(island: Island, grid: PackedFloat32Array,
		grid_res: int, grid_half: float, mat: ShaderMaterial) -> void:
	var stride := grid_res + 1
	var span := grid_half * 2.0
	var step := span / float(grid_res)
	var vert_count := stride * stride

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(vert_count)
	normals.resize(vert_count)
	colors.resize(vert_count)

	for iz in stride:
		var z := -grid_half + step * float(iz)
		for ix in stride:
			var x := -grid_half + step * float(ix)
			var idx := iz * stride + ix
			var y := grid[idx]
			verts[idx] = Vector3(x, y, z)

			# Central-difference smooth normal for terrain bands and beach lighting.
			var ix0 := maxi(ix - 1, 0)
			var ix1 := mini(ix + 1, grid_res)
			var iz0 := maxi(iz - 1, 0)
			var iz1 := mini(iz + 1, grid_res)
			var dx_step := float(ix1 - ix0) * step
			var dz_step := float(iz1 - iz0) * step
			var hx0 := grid[iz * stride + ix0]
			var hx1 := grid[iz * stride + ix1]
			var hz0 := grid[iz0 * stride + ix]
			var hz1 := grid[iz1 * stride + ix]
			var n := Vector3((hx0 - hx1) / dx_step, 1.0, (hz0 - hz1) / dz_step).normalized()
			normals[idx] = n

			# Subtle vertex crevice AO tint (brighter on ridges, slightly deeper in hollows).
			var avg_n := 0.25 * (hx0 + hx1 + hz0 + hz1)
			var curv := clampf((y - avg_n) * 0.16, -0.14, 0.10)
			var shade := clampf(1.0 + curv, 0.84, 1.08)
			colors[idx] = Color(shade, shade, shade, 1.0)

	# Triangulate active cells (skip flat outer abyss beyond seabed_radius).
	var max_r_sq := (island.seabed_radius + step * 2.0) * (island.seabed_radius + step * 2.0)
	var indices := PackedInt32Array()
	var col_faces := PackedVector3Array()

	for iz in grid_res:
		for ix in grid_res:
			var i00 := iz * stride + ix
			var i10 := i00 + 1
			var i01 := i00 + stride
			var i11 := i01 + 1
			var v00 := verts[i00]
			var v10 := verts[i10]
			var v01 := verts[i01]
			var v11 := verts[i11]
			if v00.y <= SEA_FLOOR_Y + 0.08 and v10.y <= SEA_FLOOR_Y + 0.08 \
					and v01.y <= SEA_FLOOR_Y + 0.08 and v11.y <= SEA_FLOOR_Y + 0.08:
				var cx := 0.5 * (v00.x + v11.x)
				var cz := 0.5 * (v00.z + v11.z)
				if cx * cx + cz * cz > max_r_sq:
					continue
			# Clockwise winding viewed from +Y matches Godot ArrayMesh front-faces
			# and matches Island.surface_height() diagonal split (0,0)-(1,1).
			indices.append(i00)
			indices.append(i10)
			indices.append(i11)
			indices.append(i00)
			indices.append(i11)
			indices.append(i01)

			col_faces.append(v00)
			col_faces.append(v10)
			col_faces.append(v11)
			col_faces.append(v00)
			col_faces.append(v11)
			col_faces.append(v01)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mi := MeshInstance3D.new()
	mi.name = "TerrainMesh"
	mi.mesh = mesh
	mi.material_override = mat
	island.add_child(mi)

	# Walkable terrain StaticBody3D on layer 1 (world static).
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = LAYER_WORLD_STATIC
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	col.name = "TerrainShape"
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(col_faces)
	col.shape = shape
	body.add_child(col)
	island.add_child(body)


# ============================================================ contours, mooring & gameplay spots

static func _extract_contour_points(island: Island) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var max_r := island.seabed_radius
	for i in CONTOUR_SAMPLES:
		var ang := TAU * float(i) / float(CONTOUR_SAMPLES)
		var dx := cos(ang)
		var dz := sin(ang)
		# Scan inward from open sea to find outermost shoreline crossing y = 0.0.
		var prev_r := max_r
		var prev_h := island.surface_height(dx * prev_r, dz * prev_r)
		var hit_r := island.island_radius * 0.35
		var found := false
		var steps := 48
		for s in range(1, steps + 1):
			var r := max_r * (1.0 - float(s) / float(steps))
			var h := island.surface_height(dx * r, dz * r)
			if prev_h < 0.0 and h >= 0.0:
				var t := clampf(-prev_h / maxf(h - prev_h, 0.0001), 0.0, 1.0)
				hit_r = lerpf(prev_r, r, t)
				found = true
				break
			prev_r = r
			prev_h = h
		if not found and prev_h > 0.0:
			hit_r = island.island_radius * 0.5
		pts.append(Vector2(dx * hit_r, dz * hit_r))
	return pts


static func _compute_non_outpost_mooring(island: Island, landing_yaw: float) -> Transform3D:
	# Place mooring offshore from the landing beach (-Z of landing_yaw) in >= 6 m depth,
	# with bow (-Z) pointed straight back out toward open sea.
	var basis := Basis(Vector3.UP, landing_yaw)
	var seaward := -basis.z
	var dist := island.island_radius * 0.85
	while dist < island.seabed_radius + 10.0:
		var p := seaward * dist
		if island.surface_height(p.x, p.z) <= -6.2:
			return Transform3D(basis, Vector3(p.x, 0.0, p.z))
		dist += 3.0
	var fallback := seaward * (island.island_radius + 26.0)
	return Transform3D(basis, Vector3(fallback.x, 0.0, fallback.z))


static func _populate_gameplay_points(island: Island, landing_yaw: float,
		exclusions: Array[Vector3], rng: RandomNumberGenerator) -> void:
	var dig_pts: Array[Vector3] = []
	var enemy_pts: Array[Vector3] = []
	var basis := Basis(Vector3.UP, landing_yaw)

	# First look along the welcoming landing cove beach so starter dig sites are easy to reach on foot!
	var beach_candidates: Array[Vector3] = []
	for ring: float in [0.42, 0.58, 0.72, 0.84]:
		for k in 24:
			var ang := -PI * 0.5 + (float(k) - 12.0) * (TAU / 24.0)
			var u: float = cos(ang) * island.island_radius * ring
			var v: float = sin(ang) * island.island_radius * ring
			var lp := basis * Vector3(u, 0.0, v)
			var h := island.surface_height(lp.x, lp.z)
			if h < 1.15 or h > 5.2:
				continue
			var n := island.surface_normal(lp.x, lp.z)
			if n.y < 0.90:
				continue
			if _in_exclusion(lp.x, lp.z, exclusions):
				continue
			beach_candidates.append(Vector3(lp.x, h, lp.z))

	# Prioritize candidates on the seaward landing beach (-v side) for dig_points[0].
	var inv_b := basis.inverse()
	beach_candidates.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		var va := (inv_b * a).z + absf((inv_b * a).x) * 0.35
		var vb := (inv_b * b).z + absf((inv_b * b).x) * 0.35
		return va < vb
	)

	for p in beach_candidates:
		if dig_pts.size() >= 5:
			break
		if _far_from_all(p, dig_pts, 11.0):
			dig_pts.append(p)

	# Enemy spawns across dry sandy beaches & lower grassy clearings.
	for attempt in 90:
		if enemy_pts.size() >= 6:
			break
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(island.island_radius * 0.25, island.island_radius * 0.88)
		var lx := cos(ang) * rad
		var lz := sin(ang) * rad
		var h := island.surface_height(lx, lz)
		if h < 1.3 or h > 9.5:
			continue
		var n := island.surface_normal(lx, lz)
		if n.y < 0.87:
			continue
		if _in_exclusion(lx, lz, exclusions):
			continue
		var cand := Vector3(lx, h, lz)
		if _far_from_all(cand, enemy_pts, 9.0):
			enemy_pts.append(cand)

	island.dig_points = dig_pts
	island.enemy_spawns = enemy_pts


# ============================================================ ground-snapped stylized props

static func _populate_archetype_props(island: Island, arch: StringName, landing_yaw: float,
		exclusions: Array[Vector3], rng: RandomNumberGenerator, prop_body: StaticBody3D,
		props_root: Node3D, foliage_cache: Dictionary) -> void:
	var placed: Array[Vector3] = []  # (x, z, spacing_r)
	var keepout_zones: Array[Vector3] = []  # hard keepouts (docks, plaza, campfires, dig sites, landmarks)
	for ex in exclusions:
		placed.append(ex)
		keepout_zones.append(ex)

	var basis := Basis(Vector3.UP, landing_yaw)

	# 1. Signature landmark props per archetype (sea arches, shipwrecks, sea stacks, campfires).
	match arch:
		&"sea_arch":
			# Monumental coastal rock arch straddling the sandy tide cove + flanking sea stack!
			var arch_p := basis * Vector3(0.0, 0.0, -island.island_radius * 0.45)
			var arch_y := island.surface_height(arch_p.x, arch_p.z)
			_spawn_prop(island, ROCK_ARCH_SCENE, "SeaArch_Main",
				Transform3D(Basis(Vector3.UP, landing_yaw) * Basis.from_scale(Vector3(1.55, 1.50, 1.45)),
					Vector3(arch_p.x, minf(arch_y, 0.6) - 0.6, arch_p.z)),
				prop_body, props_root, foliage_cache)
			placed.append(Vector3(arch_p.x, arch_p.z, 9.5))
			keepout_zones.append(Vector3(arch_p.x, arch_p.z, 9.5))

			var arch2_p := basis * Vector3(island.island_radius * 0.56, 0.0, -island.island_radius * 0.58)
			_spawn_prop(island, ROCK_ARCH_SCENE, "SeaArch_Outer",
				Transform3D(Basis(Vector3.UP, landing_yaw + 0.65) * Basis.from_scale(Vector3(1.15, 1.10, 1.10)),
					Vector3(arch2_p.x, -1.2, arch2_p.z)),
				prop_body, props_root, foliage_cache)

		&"wreck_shoal":
			# Two dramatic half-sunken pirate shipwrecks stranded on the shallow sandbars!
			var w1 := basis * Vector3(-12.0, 0.0, -island.island_radius * 0.62)
			var w1_y := maxf(-1.2, island.surface_height(w1.x, w1.z))
			_spawn_prop(island, SHIPWRECK_SCENE, "Shipwreck_Main",
				Transform3D(Basis(Vector3.UP, landing_yaw + 0.55) * Basis.from_scale(Vector3(1.18, 1.18, 1.18)),
					Vector3(w1.x, w1_y + 0.15, w1.z)),
				prop_body, props_root, foliage_cache)
			placed.append(Vector3(w1.x, w1.z, 8.5))
			keepout_zones.append(Vector3(w1.x, w1.z, 8.5))

			var w2 := basis * Vector3(20.0, 0.0, -island.island_radius * 0.44)
			var w2_y := maxf(-1.4, island.surface_height(w2.x, w2.z))
			_spawn_prop(island, SHIPWRECK_SCENE, "Shipwreck_Stern",
				Transform3D(Basis(Vector3.UP, landing_yaw - 1.25) * Basis.from_scale(Vector3(0.95, 0.95, 0.95)),
					Vector3(w2.x, w2_y + 0.10, w2.z)),
				prop_body, props_root, foliage_cache)
			placed.append(Vector3(w2.x, w2.z, 8.0))
			keepout_zones.append(Vector3(w2.x, w2.z, 8.0))

		&"treasure_peak", &"smuggler_cove", &"fort_rock":
			# Stranded explorer campfire + supply barrels/crates near the landing cove.
			if island.dig_points.size() >= 2:
				var camp := island.dig_points[1]
				_spawn_campfire(island, "BeachCampfire", camp, rng, prop_body, props_root, foliage_cache)
				placed.append(Vector3(camp.x, camp.z, 4.8))
				keepout_zones.append(Vector3(camp.x, camp.z, 4.8))
				for ci in 3:
					var ca := rng.randf() * TAU
					var cp := camp + Vector3(cos(ca) * 2.4, 0.0, sin(ca) * 2.4)
					cp.y = island.surface_height(cp.x, cp.z)
					if cp.y > 0.8:
						var sc := BARREL_SCENE if ci % 2 == 0 else CRATE_SCENE
						_spawn_prop(island, sc, "CoveSupply_%d" % ci,
							Transform3D(Basis(Vector3.UP, rng.randf() * TAU), cp),
							prop_body, props_root, foliage_cache)

	# 2. Dramatic offshore sea stacks (`rock_spire.glb`) for iconic horizon silhouettes (like image.png!).
	var spire_count := 3 if arch in [&"treasure_peak", &"twin_spires", &"volcano_crag", &"skull_bluff"] else 2
	for si in spire_count:
		# Place sea stacks off the side flanks so they never block the landing cove or outpost pier!
		var side_sgn := -1.0 if si % 2 == 0 else 1.0
		var s_ang := side_sgn * rng.randf_range(0.65, 2.25)
		var s_dist := island.island_radius * rng.randf_range(0.95, 1.28)
		var sp := basis * Vector3(sin(s_ang) * s_dist, 0.0, cos(s_ang) * s_dist)
		if _in_exclusion(sp.x, sp.z, placed):
			continue
		var sy := island.surface_height(sp.x, sp.z)
		var sc_val := rng.randf_range(0.85, 1.55)
		_spawn_prop(island, ROCK_SPIRE_SCENE, "SeaStack_%d" % si,
			Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sc_val, sc_val * rng.randf_range(0.95, 1.35), sc_val)),
				Vector3(sp.x, maxf(sy - 1.2, -3.5), sp.z)),
			prop_body, props_root, foliage_cache)
		placed.append(Vector3(sp.x, sp.z, 6.5))
		keepout_zones.append(Vector3(sp.x, sp.z, 5.5))

	# 3. Lush tropical palm groves (2-3 palm clusters leaning over golden beaches & green rims).
	var palm_target := 22
	if arch in [&"crescent_lagoon", &"palm_atoll", &"treasure_peak"]:
		palm_target = 28
	elif arch == &"volcano_crag":
		palm_target = 12
	elif arch == &"outpost":
		palm_target = 20

	var palms_placed := 0
	var palm_positions: Array[Vector3] = []
	for _attempt in palm_target * 10:
		if palms_placed >= palm_target:
			break
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(island.island_radius * 0.22, island.island_radius * 0.94)
		var px := cos(ang) * rad
		var pz := sin(ang) * rad
		if _in_exclusion(px, pz, placed):
			continue
		var h := island.surface_height(px, pz)
		if h < 1.35 or h > 15.0:
			continue
		var n := island.surface_normal(px, pz)
		if n.y < 0.80:
			continue
		# Curved palms favour beach verges and lean picturesquely toward the sea!
		var use_curved := (h < 3.8 and rng.randf() < 0.74) or rng.randf() < 0.44
		var scene := PALM_CURVED_SCENE if use_curved else PALM_TALL_SCENE
		var outward_yaw := atan2(px, pz) - PI * 0.5 + rng.randf_range(-0.55, 0.55)
		var sc_p := rng.randf_range(0.86, 1.22)
		var xform := Transform3D(
			Basis(Vector3.UP, outward_yaw) * Basis.from_scale(Vector3(sc_p, sc_p * rng.randf_range(0.92, 1.12), sc_p)),
			Vector3(px, h - 0.16, pz))
		_spawn_prop(island, scene, "Palm_%d" % palms_placed, xform, prop_body, props_root, foliage_cache)
		placed.append(Vector3(px, pz, 4.6))
		palm_positions.append(Vector3(px, h, pz))
		palms_placed += 1

		# Cluster 1-2 companion palms around beach & grass-verge trunks for lush groves.
		if palms_placed < palm_target and h < 8.5 and rng.randf() < 0.68:
			var companions := mini(rng.randi_range(1, 2), palm_target - palms_placed)
			for ci in companions:
				for _c_try in 5:
					var c_ang := ang + rng.randf_range(-1.9, 1.9) + float(ci) * 2.1
					var c_dist := rng.randf_range(2.2, 3.5)
					var cx := px + cos(c_ang) * c_dist
					var cz := pz + sin(c_ang) * c_dist
					if _in_exclusion(cx, cz, keepout_zones):
						continue
					if not _far_from_all(Vector3(cx, 0.0, cz), palm_positions, 1.95):
						continue
					var ch := island.surface_height(cx, cz)
					if ch < 1.35 or ch > 14.0:
						continue
					var cn := island.surface_normal(cx, cz)
					if cn.y < 0.80:
						continue
					var c_curved := (ch < 4.0 and rng.randf() < 0.78) or rng.randf() < 0.50
					var c_scene := PALM_CURVED_SCENE if c_curved else PALM_TALL_SCENE
					var c_yaw := atan2(cx, cz) - PI * 0.5 + (0.48 if ci == 0 else -0.48) + rng.randf_range(-0.28, 0.28)
					var c_sc := rng.randf_range(0.74, 1.08)
					var c_xf := Transform3D(
						Basis(Vector3.UP, c_yaw) * Basis.from_scale(Vector3(c_sc, c_sc * rng.randf_range(0.88, 1.08), c_sc)),
						Vector3(cx, ch - 0.16, cz))
					_spawn_prop(island, c_scene, "Palm_%d" % palms_placed, c_xf, prop_body, props_root, foliage_cache)
					placed.append(Vector3(cx, cz, 2.6))
					palm_positions.append(Vector3(cx, ch, cz))
					palms_placed += 1
					break

	# 4. Lush tropical bush ferns tucked around beach/grass-rim palms & grassy verges.
	var fern_target := 32 if arch != &"volcano_crag" else 10
	if arch == &"outpost":
		fern_target = 26
	var ferns_placed := 0
	var fern_positions: Array[Vector3] = []
	var palm_fern_cap := int(fern_target * 0.55)

	# First tuck 1-2 ferns around palm bases near the beach/grass transition rim.
	for palm_p in palm_positions:
		if ferns_placed >= palm_fern_cap:
			break
		if palm_p.y < 1.65 or palm_p.y > 8.5:
			continue
		var tuft_n := rng.randi_range(1, 2)
		for _ti in tuft_n:
			if ferns_placed >= palm_fern_cap:
				break
			var f_ang := rng.randf() * TAU
			var f_dist := rng.randf_range(1.15, 2.45)
			var fx := palm_p.x + cos(f_ang) * f_dist
			var fz := palm_p.z + sin(f_ang) * f_dist
			if _in_exclusion(fx, fz, keepout_zones):
				continue
			if not _far_from_all(Vector3(fx, 0.0, fz), fern_positions, 1.35):
				continue
			var fh := island.surface_height(fx, fz)
			if fh < 1.75 or fh > 14.0:
				continue
			if island.surface_normal(fx, fz).y < 0.78:
				continue
			var sc_f := rng.randf_range(0.78, 1.32)
			var xform := Transform3D(
				Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * sc_f),
				Vector3(fx, fh - 0.10, fz))
			_spawn_prop(island, BUSH_FERN_SCENE, "Fern_%d" % ferns_placed, xform, prop_body, props_root, foliage_cache)
			fern_positions.append(Vector3(fx, fh, fz))
			ferns_placed += 1

	# Fill remaining ferns along beach/grass rims and grassy benches.
	for _attempt in fern_target * 8:
		if ferns_placed >= fern_target:
			break
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(island.island_radius * 0.18, island.island_radius * 0.88)
		var fx := cos(ang) * rad
		var fz := sin(ang) * rad
		if _in_exclusion(fx, fz, keepout_zones):
			continue
		if not _far_from_all(Vector3(fx, 0.0, fz), fern_positions, 1.8):
			continue
		var h := island.surface_height(fx, fz)
		if h < 1.85 or h > 16.0:
			continue
		var n := island.surface_normal(fx, fz)
		if n.y < 0.78:
			continue
		var sc_f := rng.randf_range(0.80, 1.38)
		var xform := Transform3D(
			Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * sc_f),
			Vector3(fx, h - 0.10, fz))
		_spawn_prop(island, BUSH_FERN_SCENE, "Fern_%d" % ferns_placed, xform, prop_body, props_root, foliage_cache)
		fern_positions.append(Vector3(fx, h, fz))
		ferns_placed += 1

	# 5. Faceted coastal boulders anchoring gentle beaches, headlands, and shallows.
	var rock_target := 14
	var rocks_placed := 0
	for _attempt in rock_target * 14:
		if rocks_placed >= rock_target:
			break
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(island.island_radius * 0.35, island.island_radius * 1.05)
		var rx := cos(ang) * rad
		var rz := sin(ang) * rad
		if _in_exclusion(rx, rz, placed):
			continue
		var h := island.surface_height(rx, rz)
		if h < -1.0 or h > 10.5:
			continue
		if island.surface_normal(rx, rz).y < 0.72:
			continue
		if island.surface_normal(rx, rz, 2.5).y < 0.72:
			continue
		var sc_r := rng.randf_range(0.75, 1.55)
		var min_foot_h := h
		for off: Vector2 in [Vector2(1.3, 0.0), Vector2(-1.3, 0.0), Vector2(0.0, 1.3), Vector2(0.0, -1.3)]:
			var fh := island.surface_height(rx + off.x * sc_r, rz + off.y * sc_r)
			if fh < min_foot_h:
				min_foot_h = fh
		if h - min_foot_h > 1.05 * sc_r:
			continue
		var embed_y := minf(h, min_foot_h + 0.35 * sc_r) - 0.38 * sc_r
		var xform := Transform3D(
			Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sc_r, sc_r * rng.randf_range(0.75, 1.20), sc_r)),
			Vector3(rx, embed_y, rz))
		_spawn_prop(island, ROCK_BOULDER_SCENE, "Boulder_%d" % rocks_placed, xform, prop_body, props_root, foliage_cache)
		placed.append(Vector3(rx, rz, 3.6))
		rocks_placed += 1


static func _spawn_campfire(island: Island, node_name: String, pos: Vector3,
		rng: RandomNumberGenerator, prop_body: StaticBody3D, props_root: Node3D,
		foliage_cache: Dictionary) -> Node3D:
	var fire := _spawn_prop(island, CAMPFIRE_SCENE, node_name,
		Transform3D(Basis(Vector3.UP, rng.randf() * TAU), pos), prop_body, props_root, foliage_cache)
	var marker := fire.find_child("Lantern_Fire", true, false) as Node3D
	var light := OmniLight3D.new()
	light.name = "CampfireLight"
	light.light_color = Color(1.0, 0.56, 0.18)
	light.light_energy = 3.0
	light.omni_range = 15.0
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.position = marker.position if marker != null else Vector3(0.0, 0.55, 0.0)
	fire.add_child(light)
	island.register_flicker_light(light, 3.0, 0.22, rng.randf() * TAU)
	return fire


static func _spawn_prop(island: Island, scene: PackedScene, node_name: String,
		local_xform: Transform3D, prop_body: StaticBody3D, props_root: Node3D,
		foliage_cache: Dictionary) -> Node3D:
	var inst := scene.instantiate() as Node3D
	inst.name = node_name
	inst.transform = local_xform
	props_root.add_child(inst)

	# Extract convex collision from every `col_*` mesh and hide collider visuals.
	for node in inst.find_children("col_*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh == null:
			continue
		var faces := mi.mesh.get_faces()
		if faces.size() < 3:
			continue
		var shape := ConvexPolygonShape3D.new()
		shape.points = faces
		var cs := CollisionShape3D.new()
		cs.name = "Col_%s_%s" % [node_name, mi.name]
		cs.shape = shape
		cs.transform = local_xform * _relative_transform(mi, inst)
		prop_body.add_child(cs)

	# Bind wind-sway foliage shader to `mat_foliage` surfaces on palms and ferns.
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or not mi.visible or mi.mesh == null:
			continue
		var mesh := mi.mesh
		for surf_i in mesh.get_surface_count():
			var src_mat := mesh.surface_get_material(surf_i)
			if src_mat == null:
				continue
			if src_mat.resource_name == "mat_foliage":
				var tex: Texture2D = null
				if src_mat is StandardMaterial3D:
					tex = (src_mat as StandardMaterial3D).albedo_texture
				var cache_key := tex.resource_path if tex != null else "default_foliage"
				var wind_mat: ShaderMaterial = foliage_cache.get(cache_key)
				if wind_mat == null:
					wind_mat = ShaderMaterial.new()
					wind_mat.shader = FOLIAGE_SHADER
					if tex != null:
						wind_mat.set_shader_parameter(&"albedo_tex", tex)
						wind_mat.set_shader_parameter(&"use_albedo_tex", 1.0)
					else:
						wind_mat.set_shader_parameter(&"use_albedo_tex", 0.0)
					wind_mat.set_shader_parameter(&"use_uv2_weight", 1.0)
					foliage_cache[cache_key] = wind_mat
					island.register_foliage_material(wind_mat)
				mi.set_surface_override_material(surf_i, wind_mat)

	return inst


# ============================================================ math & defaults

static func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != ancestor:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


static func _in_exclusion(x: float, z: float, exclusions: Array[Vector3]) -> bool:
	for ex in exclusions:
		var dx := x - ex.x
		var dz := z - ex.y
		if dx * dx + dz * dz < ex.z * ex.z:
			return true
	return false


static func _far_from_all(pos: Vector3, existing: Array[Vector3], min_dist: float) -> bool:
	var d2 := min_dist * min_dist
	for p in existing:
		var dx := pos.x - p.x
		var dz := pos.z - p.z
		if dx * dx + dz * dz < d2:
			return false
	return true


static func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 1.0 if x >= edge1 else 0.0
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _hash2(ix: int, iz: int) -> float:
	var n := ix * 374761393 + iz * 668265263
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0x7fffffff) / 2147483647.0


static func _vnoise2(x: float, z: float) -> float:
	var ix := int(floorf(x))
	var iz := int(floorf(z))
	var fx := x - float(ix)
	var fz := z - float(iz)
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uz := fz * fz * (3.0 - 2.0 * fz)
	var a := _hash2(ix, iz)
	var b := _hash2(ix + 1, iz)
	var c := _hash2(ix, iz + 1)
	var d := _hash2(ix + 1, iz + 1)
	return lerpf(lerpf(a, b, ux), lerpf(c, d, ux), uz)


static func _fbm2(x: float, z: float) -> float:
	var val := 0.0
	var amp := 0.5
	var px := x
	var pz := z
	for _i in 3:
		val += amp * _vnoise2(px, pz)
		var nx := px * 1.66 - pz * 1.24 + 17.3
		var nz := px * 1.24 + pz * 1.66 + 9.1
		px = nx
		pz = nz
		amp *= 0.5
	return val


static func _stable_hash(text: String) -> int:
	var h: int = 2166136261
	for i in text.length():
		h = int((h ^ text.unicode_at(i)) * 16777619) & 0x7fffffff
	return h if h > 0 else 1337


static func _default_radius(arch: StringName) -> float:
	match arch:
		&"outpost":
			return 62.0
		&"volcano_crag":
			return 68.0
		&"crescent_lagoon", &"palm_atoll":
			return 64.0
		&"treasure_peak":
			return 52.0
		_:
			return 58.0


static func _default_peak(arch: StringName) -> float:
	match arch:
		&"volcano_crag":
			return 90.0
		&"twin_spires":
			return 80.0
		&"treasure_peak":
			return 68.0
		&"skull_bluff":
			return 64.0
		&"smuggler_cove":
			return 56.0
		&"sea_arch":
			return 50.0
		&"outpost":
			return 48.0
		&"fort_rock":
			return 42.0
		&"wreck_shoal":
			return 40.0
		&"crescent_lagoon":
			return 35.0
		&"palm_atoll":
			return 32.0
		_:
			return 48.0


static func _default_kind(arch: StringName) -> StringName:
	match arch:
		&"outpost":
			return &"outpost"
		&"fort_rock":
			return &"fort"
		&"wreck_shoal":
			return &"shipwreck"
		&"volcano_crag", &"twin_spires":
			return &"landmark"
		_:
			return &"treasure_island"


static func _default_landmarks(arch: StringName) -> Array[String]:
	match arch:
		&"outpost":
			return ["Harbour Pier", "Beacon Tower", "Tavern Porch"]
		&"treasure_peak":
			return ["Twin Peaks", "Golden Cove", "Split Palm"]
		&"twin_spires":
			return ["North Needle", "Mossy Saddle", "Emerald Bluff"]
		&"crescent_lagoon":
			return ["Turquoise Lagoon", "Coral Horn", "Sunlit Spit"]
		&"sea_arch":
			return ["White Sea Arch", "Tide Bay", "Gull Cliff"]
		&"fort_rock":
			return ["Stone Bastion", "Watch Mesa", "Landing Ramp"]
		&"wreck_shoal":
			return ["Broken Bow", "Barnacle Mast", "Shoal Bar"]
		&"volcano_crag":
			return ["Basalt Rim", "Caldera Spire", "Ash Cove"]
		&"palm_atoll":
			return ["Palm Ring", "Shallow Pool", "Coral Monolith"]
		&"skull_bluff":
			return ["Skull Brow", "High Crag", "South Beach"]
		&"smuggler_cove":
			return ["Hidden Pocket", "Cliff Gate", "Smuggler's Fire"]
		_:
			return ["Coastal Rock", "Sandy Cove", "Lone Palm"]
