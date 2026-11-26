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

# Coral-limestone bastion, weathered sea-oak gantry, and forged iron brazier palette.
const COL_FORT_STONE_LIGHT := Color(0.84, 0.79, 0.70)
const COL_FORT_STONE_MID := Color(0.71, 0.66, 0.58)
const COL_FORT_STONE_SHADOW := Color(0.50, 0.48, 0.45)
const COL_FORT_STONE_MOSS := Color(0.41, 0.47, 0.33)
const COL_FORT_WOOD_LIGHT := Color(0.53, 0.36, 0.21)
const COL_FORT_WOOD_MID := Color(0.40, 0.26, 0.15)
const COL_FORT_WOOD_DARK := Color(0.25, 0.16, 0.09)
const COL_FORT_IRON_HI := Color(0.25, 0.26, 0.29)
const COL_FORT_IRON_LO := Color(0.11, 0.12, 0.14)
const COL_FORT_BANNER := Color(0.66, 0.14, 0.13)

static var _beacon_puff_tex: ImageTexture = null


## Crowning Fort Bastion controller node mounted on `fort_rock` islands.
## Owns the Signal Brazier flare state (`set_siege_beacon`), live flame/ember
## beacon column animation, and the 4 mounted seaward `FortBattery` emplacements.
class FortBastion:
	extends Node3D

	var signal_brazier_node: Node3D = null
	var signal_brazier_light: OmniLight3D = null
	var is_siege_beacon_active: bool = false
	var batteries: Array[FortBattery] = []

	var _flame_core: MeshInstance3D = null
	var _flame_mat: StandardMaterial3D = null
	var _beacon_smoke: GPUParticles3D = null
	var _beacon_embers: GPUParticles3D = null
	var _clock: float = 0.0

	func _exit_tree() -> void:
		if _beacon_smoke != null and is_instance_valid(_beacon_smoke):
			_beacon_smoke.emitting = false
		if _beacon_embers != null and is_instance_valid(_beacon_embers):
			_beacon_embers.emitting = false

	func _process(delta: float) -> void:
		_clock += delta
		var wave := sin(_clock * 6.4) * 0.6 + sin(_clock * 13.7 + 1.1) * 0.4
		if _flame_core != null and is_instance_valid(_flame_core):
			var base_xz := 1.48 if is_siege_beacon_active else 1.0
			var base_y := 2.25 if is_siege_beacon_active else 1.05
			_flame_core.scale = Vector3(
				base_xz * (1.0 + wave * 0.08),
				base_y * (1.0 + wave * 0.16),
				base_xz * (1.0 - wave * 0.07)
			)
			_flame_core.rotation.y = _clock * (1.35 if is_siege_beacon_active else 0.55)
		if is_siege_beacon_active and signal_brazier_light != null and is_instance_valid(signal_brazier_light):
			signal_brazier_light.light_energy = 15.5 * (1.0 + wave * 0.16)

	## Flare the Signal Brazier bright emerald-crimson during active Fort Sieges,
	## or return it to a warm crimson watch-fire when calm.
	func set_siege_beacon(active: bool) -> void:
		is_siege_beacon_active = active
		if signal_brazier_light != null and is_instance_valid(signal_brazier_light):
			if active:
				signal_brazier_light.light_color = Color(0.24, 0.98, 0.56)
				signal_brazier_light.light_energy = 15.5
				signal_brazier_light.omni_range = 88.0
			else:
				signal_brazier_light.light_color = Color(1.0, 0.34, 0.14)
				signal_brazier_light.light_energy = 7.5
				signal_brazier_light.omni_range = 62.0
		if _flame_mat != null:
			if active:
				_flame_mat.albedo_color = Color(0.56, 1.0, 0.72)
				_flame_mat.emission = Color(0.20, 0.96, 0.52)
				_flame_mat.emission_energy_multiplier = 6.2
			else:
				_flame_mat.albedo_color = Color(1.0, 0.74, 0.32)
				_flame_mat.emission = Color(1.0, 0.36, 0.10)
				_flame_mat.emission_energy_multiplier = 3.8
		if _flame_core != null and is_instance_valid(_flame_core):
			_flame_core.scale = Vector3(1.48, 2.25, 1.48) if active else Vector3.ONE
		if _beacon_smoke != null and is_instance_valid(_beacon_smoke):
			var sp := _beacon_smoke.process_material as ParticleProcessMaterial
			if sp != null:
				sp.initial_velocity_min = 4.2 if active else 2.2
				sp.initial_velocity_max = 7.5 if active else 4.2
				sp.color_ramp = IslandGenerator._make_beacon_smoke_ramp(active)
		if _beacon_embers != null and is_instance_valid(_beacon_embers):
			var ep := _beacon_embers.process_material as ParticleProcessMaterial
			if ep != null:
				ep.initial_velocity_min = 5.2 if active else 2.6
				ep.initial_velocity_max = 10.5 if active else 5.4
				ep.color_ramp = IslandGenerator._make_beacon_ember_ramp(active)

	## Convenience helper toggling both the Signal Brazier siege flare and all 4 batteries.
	func set_siege_active(active: bool) -> void:
		set_siege_beacon(active)
		for bat in batteries:
			if bat != null and is_instance_valid(bat):
				bat.set_siege_active(active)

	func get_batteries() -> Array[FortBattery]:
		var out: Array[FortBattery] = []
		for bat in batteries:
			if bat != null and is_instance_valid(bat):
				out.append(bat)
		return out


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

	# Build sculpted Stone Bastion, Watchtower Gantry, Signal Brazier & 4 FortBatteries on forts.
	var fort_courtyard_spawns: Array[Vector3] = []
	if arch == &"fort_rock":
		var scale_r := radius / 60.0
		var lb := Basis(Vector3.UP, landing_yaw)
		var bastion_xz := lb * Vector3(0.0, 0.0, 2.0 * scale_r)
		var bastion_pos := Vector3(bastion_xz.x, island.surface_height(bastion_xz.x, bastion_xz.z), bastion_xz.z)
		_build_fort_bastion(island, landing_yaw, bastion_pos, prop_body, props_root, rng)
		# Keep trees, ferns, boulders, and beach dig spots clear of the bastion & approach ramp.
		exclusions.append(Vector3(bastion_pos.x, bastion_pos.z, 17.5))
		for ramp_v: float in [-13.5, -22.5, -31.0]:
			var rp := lb * Vector3(0.0, 0.0, ramp_v * scale_r)
			exclusions.append(Vector3(rp.x, rp.z, 7.2))
		for local_sp: Vector3 in [Vector3(0.0, 0.0, -2.0), Vector3(-5.0, 0.0, 2.8), Vector3(5.0, 0.0, 2.8)]:
			var wp := bastion_pos + lb * local_sp
			wp.y = island.surface_height(wp.x, wp.z)
			fort_courtyard_spawns.append(wp)

	# Gather verified walkable beach/clearing spots for buried treasure & enemy spawns.
	_populate_gameplay_points(island, landing_yaw, exclusions, rng)
	for sp in fort_courtyard_spawns:
		island.enemy_spawns.append(sp)
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
			# Tiered coral-limestone Watch Mesa crowned by a level bastion plateau,
			# a walkable sloped landing ramp from the -v cove, and twin rear citadel crags!
			var bastion_v := 2.0 * scale_r
			var bastion_y := clampf(target_peak * 0.42, 14.5, 19.5)
			var mesa := _stepped_mesa(u, v, 0.0, bastion_v, 34.0 * scale_r, 31.0 * scale_r, bastion_y, 0.20, 8.0, 0.54)
			var crag_l := _faceted_spire(u, v, -17.0 * scale_r, 27.0 * scale_r, 18.0 * scale_r, 17.0 * scale_r, target_peak, 0.32, 5.0, 1.32)
			var crag_r := _faceted_spire(u, v, 18.0 * scale_r, 24.0 * scale_r, 16.0 * scale_r, 15.0 * scale_r, target_peak * 0.78, -0.38, 5.0, 1.38)
			h = maxf(h, maxf(mesa, maxf(crag_l, crag_r)))
			h += ridge_n * 2.2 * _smoothstep(18.0, 34.0, h)
			# Level the bastion courtyard & gun terrace plateau cleanly so walls & cannons sit flush.
			var mesa_d := Vector2(u, v - bastion_v).length()
			var mesa_flat := _smoothstep(16.2 * scale_r, 13.4 * scale_r, mesa_d)
			h = lerpf(h, bastion_y, mesa_flat)
			# Walkable sloped landing ramp from the -v sandy cove straight up into the bastion gateway.
			var ramp_u := _smoothstep(14.0 * scale_r, 5.6 * scale_r, absf(u))
			var ramp_v := _smoothstep(-44.0 * scale_r, -37.0 * scale_r, v) * _smoothstep(-7.5 * scale_r, -12.5 * scale_r, v)
			var ramp_t := clampf((v + 38.0 * scale_r) / (27.5 * scale_r), 0.0, 1.0)
			var ramp_h := lerpf(1.75, bastion_y, ramp_t)
			h = lerpf(h, ramp_h, ramp_u * ramp_v * 0.95)
			# Welcoming sandy landing beach cove at the ramp foot (-v shoreline).
			var cove_u := _smoothstep(28.0 * scale_r, 11.0 * scale_r, absf(u))
			var cove_v := _smoothstep(-28.0 * scale_r, -42.0 * scale_r, v)
			if d_shore < 0.0 and cove_u * cove_v > 0.001:
				var cove_h := 1.45 + 1.15 * clampf((-d_shore - 4.0) / (20.0 * scale_r), 0.0, 1.0)
				h = lerpf(h, minf(h, cove_h), cove_u * cove_v * 0.78)

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


# ============================================================ fort stone bastion & signal brazier

## Construct the crowning Coral-Limestone Stone Bastion, Timber Watchtower Gantry,
## Towering Iron Signal Brazier, wall-pier colliders, and 4 seaward FortBatteries.
static func _build_fort_bastion(island: Island, landing_yaw: float, bastion_pos: Vector3,
		prop_body: StaticBody3D, props_root: Node3D, rng: RandomNumberGenerator) -> FortBastion:
	var bastion := FortBastion.new()
	bastion.name = "FortBastion"
	var bastion_xform := Transform3D(Basis(Vector3.UP, landing_yaw), bastion_pos)
	bastion.transform = bastion_xform
	island.add_child(bastion)

	const WALL_R := 11.4
	const CORNER_R := 12.35
	const EMBRASURE_INDICES := [1, 2, 6, 7]  # Starboard-fore, starboard-flank, port-flank, port-fore
	const REAR_WALL_INDICES := [3, 4, 5]     # Solid crenellated rear curtain walls

	var stone_st := SurfaceTool.new()
	stone_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood_st := SurfaceTool.new()
	wood_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var iron_st := SurfaceTool.new()
	iron_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Octagonal coral-limestone flagstone courtyard pavement & central compass dais.
	_build_bastion_courtyard(stone_st, WALL_R - 0.55)

	# 2. Eight battered octagonal corner buttress towers with recessed ashlar bands & merlons.
	for ci in 8:
		var corner_yaw := float(ci) * (PI * 0.25) + PI * 0.125
		var corner_dir := Vector3(-sin(corner_yaw), 0.0, -cos(corner_yaw))
		var c_pos := corner_dir * CORNER_R
		# Deep battered plinth anchored into the mesa rock with mossy stone base staining.
		_bastion_add_tapered_prism(stone_st, Vector3(c_pos.x, -2.8, c_pos.z),
			Vector2(1.48, 1.48), Vector2(1.18, 1.18), 3.0, corner_yaw,
			COL_FORT_STONE_MID, COL_FORT_STONE_MOSS, COL_FORT_STONE_SHADOW)
		# Main faceted ashlar pier shaft.
		_bastion_add_tapered_prism(stone_st, Vector3(c_pos.x, 0.2, c_pos.z),
			Vector2(1.16, 1.16), Vector2(1.04, 1.04), 3.35, corner_yaw,
			COL_FORT_STONE_LIGHT, COL_FORT_STONE_MID, COL_FORT_STONE_SHADOW)
		# Overhanging beveled stone cornice cap & corner merlon crown.
		_bastion_add_tapered_prism(stone_st, Vector3(c_pos.x, 3.55, c_pos.z),
			Vector2(1.18, 1.18), Vector2(1.22, 1.22), 0.28, corner_yaw,
			COL_FORT_STONE_LIGHT, COL_FORT_STONE_LIGHT, COL_FORT_STONE_SHADOW)
		_bastion_add_tapered_prism(stone_st, Vector3(c_pos.x, 3.83, c_pos.z),
			Vector2(1.02, 1.02), Vector2(0.86, 0.86), 0.78, corner_yaw,
			COL_FORT_STONE_LIGHT, COL_FORT_STONE_MID, COL_FORT_STONE_SHADOW)
		_add_bastion_box_collider(prop_body, bastion_xform, "CornerPier_%d" % ci,
			Transform3D(Basis(Vector3.UP, corner_yaw), Vector3(c_pos.x, 2.0, c_pos.z)),
			Vector3(2.25, 4.4, 2.25))

	# 3. Eight curtain wall bays around the octagon:
	#    Bay 0 (yaw=0, facing -Z landing ramp): wide open stone arch gateway + open oak gates
	#    Bays 1, 2, 6, 7: open seaward gun embrasures with mounted FortBatteries
	#    Bays 3, 4, 5: solid crenellated limestone curtain walls
	var battery_idx := 0
	for bi in 8:
		var bay_yaw := -float(bi) * (PI * 0.25)
		if bay_yaw < -PI:
			bay_yaw += TAU
		var bay_basis := Basis(Vector3.UP, bay_yaw)
		var bay_dir := -bay_basis.z
		var bay_center := bay_dir * WALL_R
		var bay_xf := Transform3D(bay_basis, bay_center)

		if bi == 0:
			_build_bastion_gateway(stone_st, wood_st, iron_st, bay_xf, bastion_xform, prop_body, bastion, island, rng)
		elif EMBRASURE_INDICES.has(bi):
			_build_bastion_embrasure(stone_st, bay_xf, bastion_xform, prop_body, bi)
			# Ground & mount live FortBattery cleanly inside the seaward gun embrasure!
			var bat := FortBattery.new()
			bat.name = "FortBattery_%d" % battery_idx
			bat.base_forward_yaw = bay_yaw
			bat.position = bay_dir * (WALL_R - 1.35) + Vector3(0.0, 0.28, 0.0)
			bastion.add_child(bat)
			bastion.batteries.append(bat)
			battery_idx += 1
		elif REAR_WALL_INDICES.has(bi):
			_build_bastion_curtain_wall(stone_st, bay_xf, bastion_xform, prop_body, bi)

	# 4. Timber Watchtower Gantry & Towering Iron Signal Brazier on the rear bastion crest.
	var gantry_origin := Vector3(0.0, 0.0, 8.35)
	_build_watchtower_gantry(wood_st, iron_st, gantry_origin, bastion_xform, prop_body)
	_build_signal_brazier(bastion, island, iron_st, gantry_origin + Vector3(0.0, 7.52, 0.0), rng)

	# Commit the 3 shared stylized bastion meshes (only 3 draw calls for entire stone + timber + iron fort!).
	stone_st.generate_normals()
	var stone_mi := MeshInstance3D.new()
	stone_mi.name = "BastionStonework"
	stone_mi.mesh = stone_st.commit()
	var stone_mat := StandardMaterial3D.new()
	stone_mat.vertex_color_use_as_albedo = true
	stone_mat.roughness = 0.89
	stone_mat.metallic = 0.0
	stone_mi.material_override = stone_mat
	bastion.add_child(stone_mi)

	wood_st.generate_normals()
	var wood_mi := MeshInstance3D.new()
	wood_mi.name = "WatchtowerGantry"
	wood_mi.mesh = wood_st.commit()
	var wood_mat := StandardMaterial3D.new()
	wood_mat.vertex_color_use_as_albedo = true
	wood_mat.roughness = 0.87
	wood_mat.metallic = 0.02
	wood_mi.material_override = wood_mat
	bastion.add_child(wood_mi)

	iron_st.generate_normals()
	var iron_mi := MeshInstance3D.new()
	iron_mi.name = "SignalBrazierIron"
	iron_mi.mesh = iron_st.commit()
	var iron_mat := StandardMaterial3D.new()
	iron_mat.vertex_color_use_as_albedo = true
	iron_mat.roughness = 0.44
	iron_mat.metallic = 0.78
	iron_mi.material_override = iron_mat
	bastion.add_child(iron_mi)

	# 5. Garrison supply crates & barrels tucked cleanly against the rear curtain walls.
	var garrison_props: Array[Array] = [
		[BARREL_SCENE, "BastionBarrel_L1", Vector3(-6.2, 0.06, 6.4), 0.4],
		[CRATE_SCENE, "BastionCrate_L2", Vector3(-5.0, 0.06, 7.1), -0.35],
		[BARREL_SCENE, "BastionBarrel_R1", Vector3(6.2, 0.06, 6.4), 1.7],
		[CRATE_SCENE, "BastionCrate_R2", Vector3(4.9, 0.06, 7.0), 0.25],
	]
	var dummy_foliage: Dictionary = {}
	for gp in garrison_props:
		var local_p := bastion_xform * (gp[2] as Vector3)
		var g_xf := Transform3D(Basis(Vector3.UP, landing_yaw + float(gp[3])), local_p)
		_spawn_prop(island, gp[0] as PackedScene, String(gp[1]), g_xf, prop_body, props_root, dummy_foliage)

	return bastion


static func _build_bastion_courtyard(st: SurfaceTool, inner_r: float) -> void:
	# Flush octagonal limestone courtyard floor with mossy seam borders.
	var h := 0.06
	var center := Vector3(0.0, h, 0.0)
	for i in 8:
		var a0 := float(i) * (PI * 0.25) + PI * 0.125
		var a1 := float(i + 1) * (PI * 0.25) + PI * 0.125
		var p0 := Vector3(-sin(a0) * inner_r, h, -cos(a0) * inner_r)
		var p1 := Vector3(-sin(a1) * inner_r, h, -cos(a1) * inner_r)
		var c_slab := COL_FORT_STONE_LIGHT.lerp(COL_FORT_STONE_MID, 0.25 + 0.18 * float(i % 2))
		var c_edge := COL_FORT_STONE_MID.lerp(COL_FORT_STONE_MOSS, 0.35)
		_bastion_tri(st, center, p1, p0, c_slab, c_edge, c_edge)
	# Central chamfered stone compass dais in the courtyard heart.
	_bastion_add_tapered_prism(st, Vector3(0.0, 0.0, 0.0),
		Vector2(2.35, 2.35), Vector2(2.05, 2.05), 0.14, PI * 0.125,
		COL_FORT_STONE_LIGHT, COL_FORT_STONE_MID, COL_FORT_STONE_MOSS)


static func _build_bastion_gateway(stone_st: SurfaceTool, wood_st: SurfaceTool, iron_st: SurfaceTool,
		bay_xf: Transform3D, bastion_xform: Transform3D, prop_body: StaticBody3D,
		bastion: FortBastion, island: Island, rng: RandomNumberGenerator) -> void:
	# Twin heavy flanking gate-jamb piers leaving a wide 4.4 m walkable ramp gateway!
	for sgn: float in [-1.0, 1.0]:
		var jamb_local := Vector3(sgn * 3.15, 0.0, 0.0)
		var jamb_pos := bay_xf * jamb_local
		var bay_yaw := bay_xf.basis.get_euler().y
		_bastion_add_tapered_prism(stone_st, Vector3(jamb_pos.x, -2.5, jamb_pos.z),
			Vector2(1.15, 1.15), Vector2(0.95, 0.92), 2.7, bay_yaw,
			COL_FORT_STONE_MID, COL_FORT_STONE_MOSS, COL_FORT_STONE_SHADOW)
		_bastion_add_tapered_prism(stone_st, Vector3(jamb_pos.x, 0.2, jamb_pos.z),
			Vector2(0.94, 0.90), Vector2(0.86, 0.84), 4.15, bay_yaw,
			COL_FORT_STONE_LIGHT, COL_FORT_STONE_MID, COL_FORT_STONE_SHADOW)
		_bastion_add_tapered_prism(stone_st, Vector3(jamb_pos.x, 4.35, jamb_pos.z),
			Vector2(0.98, 0.96), Vector2(0.88, 0.86), 0.65, bay_yaw,
			COL_FORT_STONE_LIGHT, COL_FORT_STONE_LIGHT, COL_FORT_STONE_SHADOW)
		_add_bastion_box_collider(prop_body, bastion_xform, "GateJamb_%s" % ("R" if sgn > 0.0 else "L"),
			Transform3D(bay_xf.basis, Vector3(jamb_pos.x, 2.2, jamb_pos.z)),
			Vector3(1.85, 4.5, 1.85))

		# Open heavy weathered oak gate wing swung wide inward (+Z of bay_xf is inside courtyard).
		var wing_yaw := bay_yaw + sgn * 1.92
		var hinge := bay_xf * Vector3(sgn * 2.15, 0.08, 0.55)
		var wing_c := hinge + Basis(Vector3.UP, wing_yaw) * Vector3(-sgn * 0.92, 1.45, 0.0)
		_bastion_add_tapered_prism(wood_st, wing_c + Vector3(0.0, -1.45, 0.0),
			Vector2(0.92, 0.11), Vector2(0.90, 0.10), 2.95, wing_yaw,
			COL_FORT_WOOD_LIGHT, COL_FORT_WOOD_MID, COL_FORT_WOOD_DARK)
		for strap_y: float in [0.55, 2.25]:
			_bastion_add_tapered_prism(iron_st, Vector3(wing_c.x, strap_y, wing_c.z),
				Vector2(0.94, 0.14), Vector2(0.94, 0.14), 0.14, wing_yaw,
				COL_FORT_IRON_HI, COL_FORT_IRON_HI, COL_FORT_IRON_LO)

	# 5-voussoir sculpted coral-limestone arch spanning cleanly above y = 3.55 m!
	var bay_yaw_arch := bay_xf.basis.get_euler().y
	var voussoirs: Array[Array] = [
		[-1.95, 3.35, 0.34, Vector2(0.58, 0.82), 0.72],
		[-1.02, 3.82, 0.16, Vector2(0.62, 0.84), 0.78],
		[0.0, 4.02, 0.0, Vector2(0.68, 0.94), 0.98],
		[1.02, 3.82, -0.16, Vector2(0.62, 0.84), 0.78],
		[1.95, 3.35, -0.34, Vector2(0.58, 0.82), 0.72],
	]
	for v_spec in voussoirs:
		var vx: float = float(v_spec[0])
		var vy: float = float(v_spec[1])
		var vroll: float = float(v_spec[2])
		var vh_xz: Vector2 = v_spec[3] as Vector2
		var v_h: float = float(v_spec[4])
		var v_xf := bay_xf * Transform3D(Basis(Vector3.BACK, vroll), Vector3(vx, vy, 0.0))
		_bastion_add_oriented_prism(stone_st, v_xf, vh_xz, vh_xz * 0.92, v_h,
			COL_FORT_STONE_LIGHT, COL_FORT_STONE_MID, COL_FORT_STONE_SHADOW)

	# Stepped stone ramp threshold slab welcoming players straight into the courtyard.
	var thresh_pos := bay_xf * Vector3(0.0, -0.25, -0.65)
	_bastion_add_tapered_prism(stone_st, thresh_pos,
		Vector2(2.35, 1.45), Vector2(2.15, 1.25), 0.32, bay_yaw_arch,
		COL_FORT_STONE_LIGHT, COL_FORT_STONE_MID, COL_FORT_STONE_MOSS)

	# Hanging wrought-iron gatehouse lantern beneath the arch keystone.
	var lant_pos := bay_xf * Vector3(0.0, 3.45, 0.0)
	_bastion_add_beam(iron_st, lant_pos + Vector3(0.0, 0.58, 0.0), lant_pos, 0.032, 6,
		COL_FORT_IRON_HI, COL_FORT_IRON_LO)
	_bastion_add_tapered_prism(iron_st, lant_pos + Vector3(0.0, -0.24, 0.0),
		Vector2(0.16, 0.16), Vector2(0.22, 0.22), 0.34, bay_yaw_arch,
		COL_FORT_IRON_HI, COL_FORT_IRON_HI, COL_FORT_IRON_LO)
	var gate_light := OmniLight3D.new()
	gate_light.name = "GatehouseLanternLight"
	gate_light.light_color = Color(1.0, 0.68, 0.28)
	gate_light.light_energy = 3.2
	gate_light.omni_range = 18.0
	gate_light.omni_attenuation = 1.4
	gate_light.shadow_enabled = false
	gate_light.position = lant_pos + Vector3(0.0, -0.18, 0.0)
	bastion.add_child(gate_light)
	island.register_flicker_light(gate_light, 3.2, 0.14, rng.randf() * TAU)


static func _build_bastion_embrasure(stone_st: SurfaceTool, bay_xf: Transform3D,
		bastion_xform: Transform3D, prop_body: StaticBody3D, bay_idx: int) -> void:
	var bay_yaw := bay_xf.basis.get_euler().y

	# Raised beveled limestone gun firing terrace supporting the FortBattery (steppable 0.28 m rise).
	var terrace_pos := bay_xf * Vector3(0.0, -0.04, 1.45)
	_bastion_add_tapered_prism(stone_st, terrace_pos,
		Vector2(2.65, 2.05), Vector2(2.45, 1.88), 0.32, bay_yaw,
		COL_FORT_STONE_LIGHT, COL_FORT_STONE_MID, COL_FORT_STONE_MOSS)
	_add_bastion_box_collider(prop_body, bastion_xform, "EmbrasureTerrace_%d" % bay_idx,
		Transform3D(bay_xf.basis, bay_xf * Vector3(0.0, 0.14, 1.45)),
		Vector3(4.9, 0.28, 3.76))

	# Low battered coral-limestone breastwork sill below the gun barrel (top y = 0.44 m)
	# so downward plunging fire at close ships always clears the masonry cleanly!
	var sill_pos := bay_xf * Vector3(0.0, -2.5, 0.20)
	_bastion_add_tapered_prism(stone_st, sill_pos,
		Vector2(3.95, 0.92), Vector2(3.80, 0.62), 2.94, bay_yaw,
		COL_FORT_STONE_LIGHT, COL_FORT_STONE_MID, COL_FORT_STONE_MOSS)
	_add_bastion_box_collider(prop_body, bastion_xform, "EmbrasureSill_%d" % bay_idx,
		Transform3D(bay_xf.basis, bay_xf * Vector3(0.0, 0.18, 0.25)),
		Vector3(7.4, 0.44, 1.05))

	# Twin flanking splayed embrasure cheek merlons leaving a wide 4.9 m open firing throat
	# that clears the full +/-1.05 rad yaw arc!
	for sgn: float in [-1.0, 1.0]:
		var cheek_pos := bay_xf * Vector3(sgn * 3.22, 0.44, 0.0)
		_bastion_add_tapered_prism(stone_st, cheek_pos,
			Vector2(0.84, 0.78), Vector2(0.76, 0.70), 3.00, bay_yaw,
			COL_FORT_STONE_LIGHT, COL_FORT_STONE_MID, COL_FORT_STONE_SHADOW)
		_bastion_add_tapered_prism(stone_st, cheek_pos + Vector3(0.0, 3.00, 0.0),
			Vector2(0.86, 0.80), Vector2(0.74, 0.70), 0.72, bay_yaw,
			COL_FORT_STONE_LIGHT, COL_FORT_STONE_LIGHT, COL_FORT_STONE_SHADOW)
		_add_bastion_box_collider(prop_body, bastion_xform, "EmbrasureCheek_%d_%s" % [bay_idx, "R" if sgn > 0.0 else "L"],
			Transform3D(bay_xf.basis, bay_xf * Vector3(sgn * 3.22, 2.1, 0.0)),
			Vector3(1.52, 3.9, 1.48))


static func _build_bastion_curtain_wall(stone_st: SurfaceTool, bay_xf: Transform3D,
		bastion_xform: Transform3D, prop_body: StaticBody3D, bay_idx: int) -> void:
	var bay_yaw := bay_xf.basis.get_euler().y
	# Deep battered limestone foundation plinth + full-height curtain wall.
	var base_pos := bay_xf * Vector3(0.0, -2.6, 0.0)
	_bastion_add_tapered_prism(stone_st, base_pos,
		Vector2(4.05, 1.12), Vector2(3.85, 0.88), 2.85, bay_yaw,
		COL_FORT_STONE_MID, COL_FORT_STONE_MOSS, COL_FORT_STONE_SHADOW)
	var wall_pos := bay_xf * Vector3(0.0, 0.25, 0.0)
	_bastion_add_tapered_prism(stone_st, wall_pos,
		Vector2(3.85, 0.86), Vector2(3.75, 0.72), 3.10, bay_yaw,
		COL_FORT_STONE_LIGHT, COL_FORT_STONE_MID, COL_FORT_STONE_SHADOW)
	# Overhanging cornice stringcourse.
	var corn_pos := bay_xf * Vector3(0.0, 3.35, 0.0)
	_bastion_add_tapered_prism(stone_st, corn_pos,
		Vector2(3.88, 0.86), Vector2(3.92, 0.90), 0.24, bay_yaw,
		COL_FORT_STONE_LIGHT, COL_FORT_STONE_LIGHT, COL_FORT_STONE_SHADOW)
	# 3 sculpted beveled crenellation merlons separated by classic crenels.
	for mx: float in [-2.45, 0.0, 2.45]:
		var m_pos := bay_xf * Vector3(mx, 3.59, 0.0)
		_bastion_add_tapered_prism(stone_st, m_pos,
			Vector2(0.76, 0.72), Vector2(0.64, 0.62), 0.84, bay_yaw,
			COL_FORT_STONE_LIGHT, COL_FORT_STONE_MID, COL_FORT_STONE_SHADOW)
	_add_bastion_box_collider(prop_body, bastion_xform, "CurtainWall_%d" % bay_idx,
		Transform3D(bay_xf.basis, bay_xf * Vector3(0.0, 2.0, 0.0)),
		Vector3(7.9, 4.2, 1.75))


static func _build_watchtower_gantry(wood_st: SurfaceTool, iron_st: SurfaceTool,
		origin: Vector3, bastion_xform: Transform3D, prop_body: StaticBody3D) -> void:
	const DECK_Y := 7.45
	var bot_corners: Array[Vector3] = [
		origin + Vector3(-1.82, 0.0, -1.55),
		origin + Vector3(1.82, 0.0, -1.55),
		origin + Vector3(1.82, 0.0, 1.55),
		origin + Vector3(-1.82, 0.0, 1.55),
	]
	var top_corners: Array[Vector3] = [
		origin + Vector3(-1.42, DECK_Y, -1.24),
		origin + Vector3(1.42, DECK_Y, -1.24),
		origin + Vector3(1.42, DECK_Y, 1.24),
		origin + Vector3(-1.42, DECK_Y, 1.24),
	]

	# 4 battered octagonal timber gantry legs + corner colliders + iron collar straps.
	for i in 4:
		_bastion_add_beam(wood_st, bot_corners[i], top_corners[i], 0.175, 8,
			COL_FORT_WOOD_LIGHT, COL_FORT_WOOD_DARK)
		var mid_p := bot_corners[i].lerp(top_corners[i], 0.5)
		_add_bastion_box_collider(prop_body, bastion_xform, "GantryPost_%d" % i,
			Transform3D(Basis.IDENTITY, mid_p), Vector3(0.42, DECK_Y, 0.42))
		for strap_t: float in [0.18, 0.55, 0.92]:
			var sp := bot_corners[i].lerp(top_corners[i], strap_t)
			_bastion_add_tapered_prism(iron_st, sp + Vector3(0.0, -0.07, 0.0),
				Vector2(0.20, 0.20), Vector2(0.20, 0.20), 0.14, 0.0,
				COL_FORT_IRON_HI, COL_FORT_IRON_HI, COL_FORT_IRON_LO)

	# Horizontal ledger beams + diagonal X-bracing timber struts across 2 gantry tiers.
	for tier_idx in 2:
		var t0 := float(tier_idx) * 0.48 + 0.08
		var t1 := t0 + 0.42
		for side in 4:
			var next_s := (side + 1) % 4
			var a0 := bot_corners[side].lerp(top_corners[side], t0)
			var b0 := bot_corners[next_s].lerp(top_corners[next_s], t0)
			var a1 := bot_corners[side].lerp(top_corners[side], t1)
			var b1 := bot_corners[next_s].lerp(top_corners[next_s], t1)
			_bastion_add_beam(wood_st, a1, b1, 0.11, 6, COL_FORT_WOOD_LIGHT, COL_FORT_WOOD_DARK)
			# Leave courtyard-facing (-Z, side 0) lower bay open for walkway & ladder access!
			if not (tier_idx == 0 and side == 0):
				_bastion_add_beam(wood_st, a0, b1, 0.085, 6, COL_FORT_WOOD_MID, COL_FORT_WOOD_DARK)
				_bastion_add_beam(wood_st, b0, a1, 0.085, 6, COL_FORT_WOOD_MID, COL_FORT_WOOD_DARK)

	# Planked wooden lookout deck platform & overhanging corbel joists.
	for jz: float in [-1.30, 0.0, 1.30]:
		_bastion_add_beam(wood_st, origin + Vector3(-2.15, DECK_Y - 0.14, jz),
			origin + Vector3(2.15, DECK_Y - 0.14, jz), 0.12, 6, COL_FORT_WOOD_MID, COL_FORT_WOOD_DARK)
	var plank_count := 8
	for pi in plank_count:
		var frac := (float(pi) + 0.5) / float(plank_count) - 0.5
		var px := frac * 3.85
		var c_p := COL_FORT_WOOD_LIGHT.lerp(COL_FORT_WOOD_MID, 0.25 * float(pi % 3))
		_bastion_add_tapered_prism(wood_st, origin + Vector3(px, DECK_Y - 0.04, 0.0),
			Vector2(0.21, 1.65), Vector2(0.20, 1.63), 0.12, 0.0, c_p, COL_FORT_WOOD_MID, COL_FORT_WOOD_DARK)

	# Waist-high timber lookout parapet railing around the gantry platform.
	var rail_pts: Array[Vector3] = [
		origin + Vector3(-1.82, DECK_Y, -1.55),
		origin + Vector3(1.82, DECK_Y, -1.55),
		origin + Vector3(1.82, DECK_Y, 1.55),
		origin + Vector3(-1.82, DECK_Y, 1.55),
	]
	for ri in 4:
		var rn := (ri + 1) % 4
		_bastion_add_beam(wood_st, rail_pts[ri], rail_pts[ri] + Vector3(0.0, 1.08, 0.0),
			0.09, 6, COL_FORT_WOOD_LIGHT, COL_FORT_WOOD_DARK)
		_bastion_add_beam(wood_st, rail_pts[ri] + Vector3(0.0, 0.98, 0.0),
			rail_pts[rn] + Vector3(0.0, 0.98, 0.0), 0.075, 6, COL_FORT_WOOD_LIGHT, COL_FORT_WOOD_DARK)
		_bastion_add_beam(wood_st, rail_pts[ri] + Vector3(0.0, 0.52, 0.0),
			rail_pts[rn] + Vector3(0.0, 0.52, 0.0), 0.058, 6, COL_FORT_WOOD_MID, COL_FORT_WOOD_DARK)

	# Sloped wooden ladder rising along the courtyard-facing (-Z) gantry side.
	var lad_bot_l := origin + Vector3(-0.34, 0.04, -2.35)
	var lad_bot_r := origin + Vector3(0.34, 0.04, -2.35)
	var lad_top_l := origin + Vector3(-0.34, DECK_Y + 0.15, -1.52)
	var lad_top_r := origin + Vector3(0.34, DECK_Y + 0.15, -1.52)
	_bastion_add_beam(wood_st, lad_bot_l, lad_top_l, 0.055, 6, COL_FORT_WOOD_LIGHT, COL_FORT_WOOD_DARK)
	_bastion_add_beam(wood_st, lad_bot_r, lad_top_r, 0.055, 6, COL_FORT_WOOD_LIGHT, COL_FORT_WOOD_DARK)
	for rung_i in range(1, 14):
		var rt := float(rung_i) / 14.0
		_bastion_add_beam(wood_st, lad_bot_l.lerp(lad_top_l, rt), lad_bot_r.lerp(lad_top_r, rt),
			0.036, 6, COL_FORT_WOOD_LIGHT, COL_FORT_WOOD_MID)

	# Tall weathered war-pennant flagpole & forked crimson fort standard on the rear corner!
	var pole_base := origin + Vector3(1.58, DECK_Y, 1.32)
	var pole_top := pole_base + Vector3(0.0, 5.2, 0.0)
	_bastion_add_beam(wood_st, pole_base, pole_top, 0.075, 8, COL_FORT_WOOD_LIGHT, COL_FORT_WOOD_DARK)
	var p_top := pole_top + Vector3(0.0, -0.25, 0.0)
	var p_bot := pole_top + Vector3(0.0, -1.35, 0.0)
	var p_mid := pole_top + Vector3(1.55, -0.80, -0.35)
	var p_tip_u := pole_top + Vector3(2.45, -0.45, -0.55)
	var p_tip_l := pole_top + Vector3(2.35, -1.18, -0.52)
	var c_ban_hi := COL_FORT_BANNER * 1.15
	var c_ban_lo := COL_FORT_BANNER * 0.72
	# Double-sided weathered forked swallowtail pennant.
	_bastion_tri(wood_st, p_top, p_tip_u, p_mid, c_ban_hi, c_ban_hi, c_ban_lo)
	_bastion_tri(wood_st, p_top, p_mid, p_tip_u, c_ban_hi, c_ban_lo, c_ban_hi)
	_bastion_tri(wood_st, p_top, p_mid, p_bot, c_ban_hi, c_ban_lo, c_ban_lo)
	_bastion_tri(wood_st, p_top, p_bot, p_mid, c_ban_hi, c_ban_lo, c_ban_lo)
	_bastion_tri(wood_st, p_bot, p_mid, p_tip_l, c_ban_lo, c_ban_hi, c_ban_lo)
	_bastion_tri(wood_st, p_bot, p_tip_l, p_mid, c_ban_lo, c_ban_lo, c_ban_hi)


static func _build_signal_brazier(bastion: FortBastion, island: Island, iron_st: SurfaceTool,
		base_pos: Vector3, rng: RandomNumberGenerator) -> void:
	var brazier_node := Node3D.new()
	brazier_node.name = "SignalBrazier"
	brazier_node.position = base_pos
	bastion.add_child(brazier_node)
	bastion.signal_brazier_node = brazier_node

	# Heavy 4-legged splayed wrought-iron pedestal cradle (y = 0..1.35 above gantry deck).
	for li in 4:
		var ang := float(li) * (PI * 0.5) + PI * 0.25
		var foot := base_pos + Vector3(cos(ang) * 0.92, 0.0, sin(ang) * 0.92)
		var neck := base_pos + Vector3(cos(ang) * 0.42, 1.35, sin(ang) * 0.42)
		_bastion_add_beam(iron_st, foot, neck, 0.085, 6, COL_FORT_IRON_HI, COL_FORT_IRON_LO)

	# Heavy riveted wrought-iron fire dish bottom & 8 curved spiked cage ribs.
	_bastion_add_tapered_prism(iron_st, base_pos + Vector3(0.0, 1.25, 0.0),
		Vector2(0.58, 0.58), Vector2(0.84, 0.84), 0.32, PI * 0.125,
		COL_FORT_IRON_HI, COL_FORT_IRON_HI, COL_FORT_IRON_LO)
	var basket_segs := 8
	for si in basket_segs:
		var a0 := TAU * float(si) / float(basket_segs)
		var a1 := TAU * float(si + 1) / float(basket_segs)
		var p_bot := base_pos + Vector3(cos(a0) * 0.78, 1.48, sin(a0) * 0.78)
		var p_mid := base_pos + Vector3(cos(a0) * 1.18, 2.22, sin(a0) * 1.18)
		var p_top := base_pos + Vector3(cos(a0) * 1.34, 2.75, sin(a0) * 1.34)
		var p_finial := base_pos + Vector3(cos(a0) * 1.42, 3.05, sin(a0) * 1.42)
		_bastion_add_beam(iron_st, p_bot, p_mid, 0.068, 6, COL_FORT_IRON_HI, COL_FORT_IRON_LO)
		_bastion_add_beam(iron_st, p_mid, p_top, 0.062, 6, COL_FORT_IRON_HI, COL_FORT_IRON_LO)
		_bastion_add_beam(iron_st, p_top, p_finial, 0.036, 6, COL_FORT_IRON_HI, COL_FORT_IRON_LO)
		# Two heavy horizontal riveted retaining iron hoops around the basket.
		var p_mid_n := base_pos + Vector3(cos(a1) * 1.18, 2.22, sin(a1) * 1.18)
		var p_top_n := base_pos + Vector3(cos(a1) * 1.34, 2.75, sin(a1) * 1.34)
		_bastion_add_beam(iron_st, p_mid, p_mid_n, 0.064, 6, COL_FORT_IRON_HI, COL_FORT_IRON_LO)
		_bastion_add_beam(iron_st, p_top, p_top_n, 0.072, 6, COL_FORT_IRON_HI, COL_FORT_IRON_LO)

	# Sculpted multi-tongue stylized emissive flame core inside the fire basket!
	var flame_st := SurfaceTool.new()
	flame_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var coal_col := Color(1.0, 0.42, 0.10)
	var mid_col := Color(1.0, 0.72, 0.24)
	var tip_col := Color(1.0, 0.96, 0.68)
	# Glowing incandescent coal mound + 5 layered rising flame tongues.
	_bastion_add_tapered_prism(flame_st, Vector3(0.0, 0.0, 0.0),
		Vector2(0.82, 0.82), Vector2(0.54, 0.54), 0.42, PI * 0.125, mid_col, coal_col, coal_col)
	var tongues: Array[Array] = [
		[Vector3(0.0, 0.25, 0.0), 0.56, 1.85],
		[Vector3(-0.36, 0.20, 0.24), 0.34, 1.28],
		[Vector3(0.38, 0.20, -0.22), 0.34, 1.34],
		[Vector3(0.22, 0.20, 0.36), 0.30, 1.12],
		[Vector3(-0.26, 0.20, -0.34), 0.32, 1.22],
	]
	for t_spec in tongues:
		var tc: Vector3 = t_spec[0] as Vector3
		var t_rad: float = float(t_spec[1])
		var th: float = float(t_spec[2])
		var apex := tc + Vector3(0.0, th, 0.0)
		for fi in 6:
			var fa0 := TAU * float(fi) / 6.0
			var fa1 := TAU * float(fi + 1) / 6.0
			var b0 := tc + Vector3(cos(fa0) * t_rad, 0.0, sin(fa0) * t_rad)
			var b1 := tc + Vector3(cos(fa1) * t_rad, 0.0, sin(fa1) * t_rad)
			_bastion_tri(flame_st, b0, b1, apex, coal_col, mid_col, tip_col)
	flame_st.generate_normals()

	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.vertex_color_use_as_albedo = true
	flame_mat.albedo_color = Color(1.0, 0.74, 0.32)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.36, 0.10)
	flame_mat.emission_energy_multiplier = 3.8
	var flame_mi := MeshInstance3D.new()
	flame_mi.name = "BrazierFlameCore"
	flame_mi.mesh = flame_st.commit()
	flame_mi.material_override = flame_mat
	flame_mi.position = Vector3(0.0, 1.52, 0.0)
	flame_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	brazier_node.add_child(flame_mi)
	bastion._flame_core = flame_mi
	bastion._flame_mat = flame_mat

	# Flickering warm-crimson Signal Brazier OmniLight3D registered via distance-gated flicker!
	var brazier_light := OmniLight3D.new()
	brazier_light.name = "SignalBrazierLight"
	brazier_light.light_color = Color(1.0, 0.34, 0.14)
	brazier_light.light_energy = 7.5
	brazier_light.omni_range = 62.0
	brazier_light.omni_attenuation = 1.25
	brazier_light.shadow_enabled = false
	brazier_light.position = Vector3(0.0, 2.85, 0.0)
	brazier_node.add_child(brazier_light)
	bastion.signal_brazier_light = brazier_light
	island.register_flicker_light(brazier_light, 7.5, 0.20, rng.randf() * TAU)

	# Rising feathered beacon smoke & ember column (skipped cleanly in headless mode).
	if DisplayServer.get_name() == "headless":
		return

	var smoke_p := GPUParticles3D.new()
	smoke_p.name = "BeaconSmokeColumn"
	smoke_p.amount = 28
	smoke_p.lifetime = 4.6
	smoke_p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	smoke_p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke_p.visibility_aabb = AABB(Vector3(-10.0, -2.0, -10.0), Vector3(20.0, 34.0, 20.0))
	smoke_p.position = Vector3(0.0, 2.75, 0.0)
	var s_proc := ParticleProcessMaterial.new()
	s_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	s_proc.emission_ring_radius = 0.72
	s_proc.emission_ring_inner_radius = 0.15
	s_proc.emission_ring_height = 0.25
	s_proc.emission_ring_axis = Vector3.UP
	s_proc.direction = Vector3(0.18, 1.0, 0.08).normalized()
	s_proc.spread = 14.0
	s_proc.initial_velocity_min = 2.2
	s_proc.initial_velocity_max = 4.2
	s_proc.gravity = Vector3(0.35, 0.65, 0.15)
	s_proc.scale_min = 1.25
	s_proc.scale_max = 2.45
	var s_curve := Curve.new()
	s_curve.add_point(Vector2(0.0, 0.45))
	s_curve.add_point(Vector2(0.42, 1.25))
	s_curve.add_point(Vector2(1.0, 2.20))
	var s_curve_tex := CurveTexture.new()
	s_curve_tex.curve = s_curve
	s_proc.scale_curve = s_curve_tex
	s_proc.color_ramp = _make_beacon_smoke_ramp(false)
	smoke_p.process_material = s_proc
	var s_quad := QuadMesh.new()
	s_quad.size = Vector2(2.1, 2.1)
	var s_mat := StandardMaterial3D.new()
	s_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	s_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	s_mat.vertex_color_use_as_albedo = true
	s_mat.albedo_texture = _get_beacon_puff_texture()
	s_quad.material = s_mat
	smoke_p.draw_pass_1 = s_quad
	smoke_p.emitting = true
	brazier_node.add_child(smoke_p)
	bastion._beacon_smoke = smoke_p

	var ember_p := GPUParticles3D.new()
	ember_p.name = "BeaconEmberColumn"
	ember_p.amount = 24
	ember_p.lifetime = 2.4
	ember_p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	ember_p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ember_p.visibility_aabb = AABB(Vector3(-8.0, -1.0, -8.0), Vector3(16.0, 24.0, 16.0))
	ember_p.position = Vector3(0.0, 2.55, 0.0)
	var e_proc := ParticleProcessMaterial.new()
	e_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	e_proc.emission_ring_radius = 0.85
	e_proc.emission_ring_inner_radius = 0.10
	e_proc.emission_ring_height = 0.20
	e_proc.emission_ring_axis = Vector3.UP
	e_proc.direction = Vector3.UP
	e_proc.spread = 22.0
	e_proc.initial_velocity_min = 2.6
	e_proc.initial_velocity_max = 5.4
	e_proc.gravity = Vector3(0.25, 0.45, 0.0)
	e_proc.scale_min = 0.45
	e_proc.scale_max = 1.05
	e_proc.color_ramp = _make_beacon_ember_ramp(false)
	ember_p.process_material = e_proc
	var e_quad := QuadMesh.new()
	e_quad.size = Vector2(0.32, 0.32)
	var e_mat := StandardMaterial3D.new()
	e_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	e_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	e_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	e_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	e_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	e_mat.vertex_color_use_as_albedo = true
	e_mat.albedo_texture = _get_beacon_puff_texture()
	e_quad.material = e_mat
	ember_p.draw_pass_1 = e_quad
	ember_p.emitting = true
	brazier_node.add_child(ember_p)
	bastion._beacon_embers = ember_p


static func _make_beacon_smoke_ramp(siege_active: bool) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.14, 0.58, 1.0])
	if siege_active:
		grad.colors = PackedColorArray([
			Color(0.26, 0.96, 0.54, 0.0),
			Color(0.22, 0.72, 0.44, 0.68),
			Color(0.26, 0.32, 0.28, 0.44),
			Color(0.18, 0.20, 0.20, 0.0),
		])
	else:
		grad.colors = PackedColorArray([
			Color(0.95, 0.46, 0.16, 0.0),
			Color(0.38, 0.28, 0.24, 0.56),
			Color(0.26, 0.25, 0.26, 0.34),
			Color(0.22, 0.22, 0.24, 0.0),
		])
	var tex := GradientTexture1D.new()
	tex.width = 32
	tex.gradient = grad
	return tex


static func _make_beacon_ember_ramp(siege_active: bool) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.72, 1.0])
	if siege_active:
		grad.colors = PackedColorArray([
			Color(0.75, 1.0, 0.84, 1.0),
			Color(0.22, 0.98, 0.54, 0.94),
			Color(0.95, 0.26, 0.14, 0.52),
			Color(0.60, 0.10, 0.06, 0.0),
		])
	else:
		grad.colors = PackedColorArray([
			Color(1.0, 0.96, 0.72, 1.0),
			Color(1.0, 0.52, 0.14, 0.90),
			Color(0.92, 0.20, 0.05, 0.48),
			Color(0.55, 0.08, 0.02, 0.0),
		])
	var tex := GradientTexture1D.new()
	tex.width = 32
	tex.gradient = grad
	return tex


static func _get_beacon_puff_texture() -> ImageTexture:
	if _beacon_puff_tex != null:
		return _beacon_puff_tex
	var sz := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var half := float(sz - 1) * 0.5
	var lobes: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.88),
		Vector3(-0.22, -0.10, 0.56),
		Vector3(0.24, -0.06, 0.54),
		Vector3(0.04, 0.22, 0.52),
	]
	for y in sz:
		for x in sz:
			var nx := (float(x) - half) / half
			var ny := (float(y) - half) / half
			var density := 0.0
			for lobe in lobes:
				var dx := nx - lobe.x
				var dy := ny - lobe.y
				var r := sqrt(dx * dx + dy * dy) / lobe.z
				if r < 1.0:
					var w := 1.0 - r * r
					density = maxf(density, w * w)
			var outer := clampf(1.0 - sqrt(nx * nx + ny * ny), 0.0, 1.0)
			var alpha := clampf(density * smoothstep(0.0, 0.42, outer), 0.0, 1.0)
			var shade := lerpf(0.88, 1.0, density)
			img.set_pixel(x, y, Color(shade, shade, shade, alpha))
	_beacon_puff_tex = ImageTexture.create_from_image(img)
	return _beacon_puff_tex


static func _add_bastion_box_collider(prop_body: StaticBody3D, bastion_xform: Transform3D,
		col_name: String, local_xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = "Col_Bastion_" + col_name
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.transform = bastion_xform * local_xf
	prop_body.add_child(cs)


static func _bastion_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)


static func _bastion_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_bastion_tri(st, a, b, c, ca, cb, cc)
	_bastion_tri(st, a, c, d, ca, cc, cd)


static func _bastion_add_tapered_prism(st: SurfaceTool, base_center: Vector3,
		half_bot: Vector2, half_top: Vector2, height: float, yaw: float,
		col_top: Color, col_mid: Color, col_bot: Color) -> void:
	_bastion_add_oriented_prism(st, Transform3D(Basis(Vector3.UP, yaw), base_center),
		half_bot, half_top, height, col_top, col_mid, col_bot)


static func _bastion_add_oriented_prism(st: SurfaceTool, xf: Transform3D,
		half_bot: Vector2, half_top: Vector2, height: float,
		col_top: Color, col_mid: Color, col_bot: Color) -> void:
	var b: Array[Vector3] = [
		xf * Vector3(-half_bot.x, 0.0, -half_bot.y),
		xf * Vector3(half_bot.x, 0.0, -half_bot.y),
		xf * Vector3(half_bot.x, 0.0, half_bot.y),
		xf * Vector3(-half_bot.x, 0.0, half_bot.y),
	]
	var t: Array[Vector3] = [
		xf * Vector3(-half_top.x, height, -half_top.y),
		xf * Vector3(half_top.x, height, -half_top.y),
		xf * Vector3(half_top.x, height, half_top.y),
		xf * Vector3(-half_top.x, height, half_top.y),
	]
	# Top cap (+Y outward) & bottom cap (-Y outward).
	_bastion_quad(st, t[0], t[1], t[2], t[3], col_top, col_top, col_top, col_top)
	_bastion_quad(st, b[0], b[3], b[2], b[1], col_bot, col_bot, col_bot, col_bot)
	for i in 4:
		var j := (i + 1) % 4
		var c_up := col_top.lerp(col_mid, 0.35 + 0.14 * float(i % 2))
		var c_lo := col_bot.lerp(col_mid, 0.25)
		_bastion_quad(st, b[i], b[j], t[j], t[i], c_lo, c_lo, c_up, c_up)


static func _bastion_add_beam(st: SurfaceTool, a: Vector3, b: Vector3, radius: float,
		segs: int, col_hi: Color, col_lo: Color) -> void:
	var axis := b - a
	var length := axis.length()
	if length < 0.0001:
		return
	var dir := axis / length
	var ref := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
	var u := dir.cross(ref).normalized()
	var v := dir.cross(u).normalized()
	for i in segs:
		var ang0 := TAU * float(i) / float(segs)
		var ang1 := TAU * float(i + 1) / float(segs)
		var off0 := (u * cos(ang0) + v * sin(ang0)) * radius
		var off1 := (u * cos(ang1) + v * sin(ang1)) * radius
		var s0 := clampf(0.5 + 0.5 * off0.normalized().y, 0.0, 1.0)
		var s1 := clampf(0.5 + 0.5 * off1.normalized().y, 0.0, 1.0)
		var c0 := col_lo.lerp(col_hi, s0)
		var c1 := col_lo.lerp(col_hi, s1)
		_bastion_quad(st, a + off0, b + off0, b + off1, a + off1, c0, c0, c1, c1)
		_bastion_tri(st, a, a + off0, a + off1, col_lo, c0, c1)
		_bastion_tri(st, b, b + off1, b + off0, col_hi, c1, c0)
