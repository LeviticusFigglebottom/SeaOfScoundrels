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

const TEX_GRASS_ALB: Texture2D = preload("res://assets/generated/textures/terrain_grass_albedo.png")
const TEX_GRASS_NRM: Texture2D = preload("res://assets/generated/textures/terrain_grass_normal.png")
const TEX_DIRT_ALB: Texture2D = preload("res://assets/generated/textures/terrain_dirt_albedo.png")
const TEX_DIRT_NRM: Texture2D = preload("res://assets/generated/textures/terrain_dirt_normal.png")
const TEX_SAND_ALB: Texture2D = preload("res://assets/generated/textures/terrain_sand_albedo.png")
const TEX_SAND_NRM: Texture2D = preload("res://assets/generated/textures/terrain_sand_normal.png")
const TEX_CLIFF_ALB: Texture2D = preload("res://assets/generated/textures/terrain_cliff_albedo.png")
const TEX_CLIFF_NRM: Texture2D = preload("res://assets/generated/textures/terrain_cliff_normal.png")
const TEX_VOLCANIC_ALB: Texture2D = preload("res://assets/generated/textures/terrain_volcanic_albedo.png")
const TEX_VOLCANIC_NRM: Texture2D = preload("res://assets/generated/textures/terrain_volcanic_normal.png")

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
const SUPPLY_BARREL_SCRIPT: GDScript = preload("res://src/world/supply_barrel.gd")
const FORT_VAULT_SCRIPT: GDScript = preload("res://src/world/fort_vault.gd")

const TERRAIN_PBR_TEXTURE_PATHS: Dictionary = {
	"tex_grass_albedo": "res://assets/generated/textures/terrain_grass_albedo.png",
	"tex_grass_normal": "res://assets/generated/textures/terrain_grass_normal.png",
	"tex_dirt_albedo": "res://assets/generated/textures/terrain_dirt_albedo.png",
	"tex_dirt_normal": "res://assets/generated/textures/terrain_dirt_normal.png",
	"tex_sand_albedo": "res://assets/generated/textures/terrain_sand_albedo.png",
	"tex_sand_normal": "res://assets/generated/textures/terrain_sand_normal.png",
	"tex_cliff_albedo": "res://assets/generated/textures/terrain_cliff_albedo.png",
	"tex_cliff_normal": "res://assets/generated/textures/terrain_cliff_normal.png",
	"tex_volcanic_albedo": "res://assets/generated/textures/terrain_volcanic_albedo.png",
	"tex_volcanic_normal": "res://assets/generated/textures/terrain_volcanic_normal.png",
}

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
	&"sea_stack",
	&"grand_citadel",
	&"grand_outpost",
]

## Non-outpost tropical beach archetypes that wash up a glinting `MessageBottle`.
const BOTTLE_ARCHETYPES: Array[StringName] = [
	&"treasure_peak",
	&"smuggler_cove",
	&"crescent_lagoon",
	&"wreck_shoal",
	&"sea_arch",
	&"palm_atoll",
	&"grand_citadel",
]

## Deterministic washed-up bottle clues pointing to other archipelago islands & high-value loot.
const BOTTLE_CLUE_TARGETS: Array[Dictionary] = [
	{
		"target_id": "smugglers_cove",
		"target_name": "Smuggler's Cove",
		"treasure_id": &"corsair_chest",
		"clue_text": "Salt-stained chart: a Corsair's War-Chest lies buried along the hidden beach of Smuggler's Cove!",
	},
	{
		"target_id": "crescent_atoll",
		"target_name": "Crescent Atoll",
		"treasure_id": &"archive_chalice",
		"clue_text": "Wax-sealed cipher: a Gilded Tide-Chalice gleams beneath the palms of Crescent Atoll!",
	},
	{
		"target_id": "skull_bluff",
		"target_name": "Skull Bluff",
		"treasure_id": &"captains_skull",
		"clue_text": "Torn bounty writ: a Drowned Captain's Skull rests above the south sand spit of Skull Bluff!",
	},
	{
		"target_id": "ironwatch_fort",
		"target_name": "Ironwatch Fort",
		"treasure_id": &"sovereign_chest",
		"clue_text": "Smuggler's ledger scrap: a Sovereign's Strongbox awaits on Ironwatch Fort's coastal bastion!",
	},
	{
		"target_id": "wreckers_shoal",
		"target_name": "Wrecker's Shoal",
		"treasure_id": &"corsair_chest",
		"clue_text": "Waterlogged logbook page: a Corsair's War-Chest washed ashore near the broken hull of Wrecker's Shoal!",
	},
	{
		"target_id": "cutlass_cay",
		"target_name": "Cutlass Cay",
		"treasure_id": &"archive_chalice",
		"clue_text": "Sun-faded map scrap: a Gilded Tide-Chalice waits by the Split Palm of Cutlass Cay!",
	},
	{
		"target_id": "sovereigns_bastion",
		"target_name": "Sovereign's Bastion",
		"treasure_id": &"sovereign_chest",
		"clue_text": "Gilded seal fragment: a Sovereign's Strongbox lies hidden beneath the temple terraces of Sovereign's Bastion!",
	},
]

const LAYER_WORLD_STATIC := 1
const SEA_FLOOR_Y := -20.0
const CONTOUR_SAMPLES := 36

# Warm weathered coral-limestone bastion, sea-oak gantry, and forged iron brazier palette.
const COL_FORT_STONE_LIGHT := Color(0.68, 0.57, 0.41)
const COL_FORT_STONE_MID := Color(0.49, 0.41, 0.31)
const COL_FORT_STONE_SHADOW := Color(0.28, 0.25, 0.22)
const COL_FORT_STONE_MOSS := Color(0.26, 0.36, 0.20)
const COL_FORT_WOOD_LIGHT := Color(0.53, 0.36, 0.21)
const COL_FORT_WOOD_MID := Color(0.40, 0.26, 0.15)
const COL_FORT_WOOD_DARK := Color(0.25, 0.16, 0.09)
const COL_FORT_IRON_HI := Color(0.25, 0.26, 0.29)
const COL_FORT_IRON_LO := Color(0.11, 0.12, 0.14)
const COL_FORT_BANNER := Color(0.66, 0.14, 0.13)

# Smuggler's Sea Cave Grotto warm sunlit ochre-limestone -> mossy upper crown -> deep warm cavern palette (sRGB).
const COL_GROTTO_LIMESTONE_SUN := Color(0.62, 0.53, 0.41)
const COL_GROTTO_LIMESTONE_MID := Color(0.48, 0.41, 0.32)
const COL_GROTTO_MOSS := Color(0.32, 0.43, 0.23)
const COL_GROTTO_SHADOW := Color(0.36, 0.30, 0.24)
const COL_GROTTO_DEEP := Color(0.28, 0.23, 0.19)
const COL_GROTTO_SLATE := Color(0.33, 0.28, 0.23)
const COL_GROTTO_STALACTITE := Color(0.45, 0.38, 0.29)
const COL_GROTTO_BRASS_HI := Color(0.84, 0.64, 0.26)
const COL_GROTTO_BRASS_LO := Color(0.48, 0.34, 0.12)

# Cinder Crag obsidian basalt crust & incandescent magma caldera palette.
const COL_CALDERA_MAGMA_CORE := Color(1.0, 0.90, 0.36)
const COL_CALDERA_MAGMA_MID := Color(1.0, 0.42, 0.06)
const COL_CALDERA_MAGMA_RIM := Color(0.68, 0.10, 0.02)
const COL_CALDERA_OBSIDIAN_TOP := Color(0.11, 0.11, 0.13)
const COL_CALDERA_OBSIDIAN_EDGE := Color(0.20, 0.19, 0.22)
const COL_CALDERA_OBSIDIAN_SCORCH := Color(0.46, 0.14, 0.05)

static var _beacon_puff_tex: ImageTexture = null
static var _active_puff_users: int = 0


static func _retain_puff_tex() -> void:
	_active_puff_users += 1


static func _release_puff_tex() -> void:
	_active_puff_users = maxi(0, _active_puff_users - 1)
	if _active_puff_users == 0:
		_beacon_puff_tex = null


## Crowning Fort Bastion controller node mounted on `fort_rock` / `grand_citadel` islands.
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

	func _enter_tree() -> void:
		IslandGenerator._retain_puff_tex()

	func _exit_tree() -> void:
		for p: GPUParticles3D in [_beacon_smoke, _beacon_embers]:
			if p != null and is_instance_valid(p):
				p.emitting = false
				p.visible = false
				p.draw_pass_1 = null
				p.process_material = null
		_beacon_smoke = null
		_beacon_embers = null
		IslandGenerator._release_puff_tex()

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


## Glowing volcanic magma caldera & towering ash/ember plume controller node mounted
## inside the summit crater bowl of `volcano_crag` islands (e.g. Cinder Crag).
class VolcanoCaldera:
	extends Node3D

	var magma_mesh: MeshInstance3D = null
	var obsidian_mesh: MeshInstance3D = null
	var lava_fissure_mesh: MeshInstance3D = null
	var caldera_light: OmniLight3D = null
	var ash_plume: GPUParticles3D = null
	var ember_plume: GPUParticles3D = null

	var _magma_mat: StandardMaterial3D = null
	var _fissure_mat: StandardMaterial3D = null
	var _clock: float = 0.0

	func _enter_tree() -> void:
		IslandGenerator._retain_puff_tex()

	func _exit_tree() -> void:
		for p: GPUParticles3D in [ash_plume, ember_plume]:
			if p != null and is_instance_valid(p):
				p.emitting = false
				p.visible = false
				p.draw_pass_1 = null
				p.process_material = null
		ash_plume = null
		ember_plume = null
		_magma_mat = null
		_fissure_mat = null
		magma_mesh = null
		obsidian_mesh = null
		lava_fissure_mesh = null
		caldera_light = null
		IslandGenerator._release_puff_tex()

	func _process(delta: float) -> void:
		_clock += delta
		var pulse := 1.0 + 0.22 * sin(_clock * 1.85) + 0.09 * sin(_clock * 4.2 + 0.8)
		if _magma_mat != null:
			_magma_mat.albedo_color = Color(2.15 * pulse, 1.80 * pulse, 1.45 * pulse, 1.0)
			_magma_mat.emission_energy_multiplier = 4.2 * pulse
		if _fissure_mat != null:
			var f_pulse := 1.0 + 0.14 * sin(_clock * 2.15 + 0.6) + 0.06 * sin(_clock * 4.7)
			_fissure_mat.albedo_color = Color(1.48 * f_pulse, 1.18 * f_pulse, 0.88 * f_pulse, 1.0)
			_fissure_mat.emission_energy_multiplier = 2.8 * f_pulse
		if magma_mesh != null and is_instance_valid(magma_mesh):
			magma_mesh.position.y = 0.06 * sin(_clock * 1.65)



## Build a complete procedural `Island` (or `Outpost` for `&"outpost"` / `&"grand_outpost"`).
## `spec` keys (all optional except defaults):
##   id (String), name (String), archetype (StringName), kind (StringName),
##   seed (int), radius (float), peak_height (float), dock_yaw (float),
##   landing_yaw (float), landmarks (Array[String]), spawn_default_dig_site (bool),
##   default_treasure_id (StringName).
static func build_island(spec: Dictionary) -> Island:
	var arch := StringName(String(spec.get("archetype", &"treasure_peak")))
	if not ARCHETYPES.has(arch):
		arch = &"treasure_peak"
	var is_outpost := arch == &"outpost" or arch == &"grand_outpost" or bool(spec.get("is_outpost", false))
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
	island.seabed_radius = radius + clampf(radius * 0.55, 58.0, 82.0)
	island.peak_height = target_peak

	var lm_raw: Variant = spec.get("landmarks", _default_landmarks(arch))
	var lm_typed: Array[String] = []
	if lm_raw is Array:
		for item in lm_raw as Array:
			lm_typed.append(String(item))
	island.landmarks = lm_typed

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	# Adaptive high-resolution terrain height grid scaled by island tier (72..120).
	var grid_res := 72
	if radius > 145.0:
		grid_res = 120
	elif radius > 105.0:
		grid_res = 104
	elif radius > 60.0:
		grid_res = 88
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
	_build_terrain_mesh_and_collider(island, grid, grid_res, grid_half, terrain_mat, arch, landing_yaw)

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
		if arch == &"grand_outpost":
			keepouts.append([0.0, -64.0, 22.0])
			keepouts.append([0.0, -104.0, 26.0])
		for k in keepouts:
			var wp := db * Vector3(float(k[0]), 0.0, float(k[1]))
			exclusions.append(Vector3(wp.x, wp.z, float(k[2])))
	else:
		island.mooring_transform = _compute_non_outpost_mooring(island, landing_yaw)

	# Build sculpted Stone Bastion, Watchtower Gantry, Signal Brazier & 4 FortBatteries on forts & grand citadels.
	var fort_courtyard_spawns: Array[Vector3] = []
	if arch == &"fort_rock" or arch == &"grand_citadel":
		var scale_r := radius / 60.0
		var lb := Basis(Vector3.UP, landing_yaw)
		var bastion_v := 18.0 if arch == &"grand_citadel" else 2.0 * scale_r
		var bastion_xz := lb * Vector3(0.0, 0.0, bastion_v)
		var bastion_pos := Vector3(bastion_xz.x, island.surface_height(bastion_xz.x, bastion_xz.z), bastion_xz.z)
		var bastion := _build_fort_bastion(island, landing_yaw, bastion_pos, prop_body, props_root, rng)
		if arch == &"grand_citadel" and bastion != null:
			_mount_citadel_fort_vault(bastion)
		# Keep trees, ferns, boulders, and beach dig spots clear of the bastion & approach ramp.
		exclusions.append(Vector3(bastion_pos.x, bastion_pos.z, 20.0 if arch == &"grand_citadel" else 17.5))
		var ramp_stops: Array[float] = [-10.0, -28.0, -48.0, -68.0]
		if arch != &"grand_citadel":
			ramp_stops = [-13.5 * scale_r, -22.5 * scale_r, -31.0 * scale_r]
		for ramp_v: float in ramp_stops:
			var rp := lb * Vector3(0.0, 0.0, ramp_v)
			exclusions.append(Vector3(rp.x, rp.z, 8.5 if arch == &"grand_citadel" else 7.2))
		for local_sp: Vector3 in [Vector3(0.0, 0.0, -2.0), Vector3(-5.0, 0.0, 2.8), Vector3(5.0, 0.0, 2.8)]:
			var wp := bastion_pos + lb * local_sp
			wp.y = island.surface_height(wp.x, wp.z)
			fort_courtyard_spawns.append(wp)
	elif arch == &"smuggler_cove":
		# Reserve clean cave vault & cove mouth approach in cave-relative metres before placing dig sites/campfires.
		var sc_r := radius / 60.0
		var sc_b := Basis(Vector3.UP, landing_yaw)
		var v_grotto := 6.0 * sc_r
		var sc_mid := sc_b * Vector3(0.0, 0.0, v_grotto + 5.5)
		var sc_mouth := sc_b * Vector3(0.0, 0.0, v_grotto - 2.0)
		exclusions.append(Vector3(sc_mid.x, sc_mid.z, 10.8))
		exclusions.append(Vector3(sc_mouth.x, sc_mouth.z, 7.6))

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

	# Place ground-snapped stylized props (palms, ferns, boulders, spires, arches, wrecks, campfires,
	# plus duck-typed Wave 24A architecture/jungle props, Wave 24B waterfalls/fumaroles & Wave I-2 landmarks).
	var foliage_mat_cache: Dictionary = {}
	_populate_archetype_props(island, arch, landing_yaw, exclusions, rng, prop_body, props_root, foliage_mat_cache)

	# Populate batched MultiMesh 3D ground cover, coastal shoreline details & steep-slope cliff buttresses.
	IslandDetails.populate_for_island(island, arch, seed_val + 503, exclusions)

	# Atmospheric night-time tropical fireflies over palm groves, coves & outposts (skip stark volcanic crag).
	if arch != &"volcano_crag":
		_build_island_fireflies(island, arch, landing_yaw)

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
	if r >= seabed_r + 2.0:
		return SEA_FLOOR_Y
	var ang := atan2(v, u)
	var s := float(seed_val % 4096) * 0.137

	# Organic surface detail & ridged cliff noise fields (skip deep underwater outer abyss).
	var in_land_zone := r < radius * 1.42
	var detail_n := (_fbm2(u * 0.068 - s * 0.4, v * 0.068 + s * 0.9) - 0.5) if in_land_zone else 0.0
	var ridge_n := (1.0 - absf(_fbm2(u * 0.052 + s * 1.3, v * 0.052 + s * 0.5) * 2.0 - 1.0)) if in_land_zone else 0.0

	# Base coastline silhouette per archetype (organic coves, peninsulas & harbour bays).
	var coast_freq := 0.022 if radius <= 85.0 else 0.015
	var coast_m := _fbm2(u * coast_freq + s, v * coast_freq - s * 0.7) - 0.5
	var r_coast := radius * (1.0 + 0.16 * coast_m + 0.07 * cos(ang * 2.0 + s) + 0.05 * sin(ang * 3.0 - s))
	if arch == &"crescent_lagoon" or arch == &"palm_atoll":
		r_coast = radius * (1.02 + 0.10 * coast_m)
	elif arch == &"wreck_shoal":
		r_coast = radius * (1.06 + 0.18 * cos(ang * 2.0 - 0.4) + 0.14 * coast_m)
	elif arch == &"sea_stack":
		r_coast = radius * (0.94 + 0.18 * cos(ang * 2.0 + 0.55) + 0.14 * coast_m)
	elif arch == &"outpost":
		# Sheltered horseshoe harbour bay indenting smoothly to the unscaled dock shoreline (v ~ -26 m).
		var bay_ang := exp(-pow(u / 30.0, 2.0)) * _smoothstep(-4.0, -24.0, v)
		var bay_cut := maxf(18.0, radius - 40.0)
		r_coast = radius * (1.0 + 0.12 * coast_m + 0.05 * cos(ang * 3.0 - 0.4)) - bay_cut * bay_ang
	elif arch == &"grand_outpost":
		# Sweeping natural horseshoe harbour fjord opening wide & deep seaward along -v!
		var fjord_ang := exp(-pow(u / 48.0, 2.0)) * _smoothstep(4.0, -24.0, v)
		var fjord_cut := maxf(44.0, radius - 34.0)
		r_coast = radius * (1.0 + 0.13 * coast_m + 0.08 * cos(ang * 2.0 + 0.3)) - fjord_cut * fjord_ang
	elif arch == &"fort_rock":
		# Welcoming coastal landing bay on the -v flank so ships anchor clearly in front of the bastion.
		var fort_bay := exp(-pow(u / (28.0 * maxf(1.0, radius / 60.0)), 2.0)) * _smoothstep(-8.0, -34.0, v)
		r_coast = radius * (1.0 + 0.12 * coast_m) - maxf(0.0, (radius - 60.0) * 0.42) * fort_bay
	elif arch == &"grand_citadel":
		# Broad grand fortress headland with sheltered seaward bay & twin protruding coastal promontories.
		var cit_bay := exp(-pow(u / 54.0, 2.0)) * _smoothstep(-10.0, -48.0, v)
		r_coast = radius * (1.02 + 0.14 * coast_m + 0.07 * sin(ang * 3.0 + 0.4)) - 34.0 * cit_bay

	var d_shore := r - r_coast

	# Base coastal elevation curve:
	#   seaward: gentle glowing turquoise shallows (0..-3.8 m over ~18-28 m), then smooth drop to -20 m
	#   landward: walkable golden beach (0..+3.0 m over ~17-22 m, gentle slope), then lush rolling highlands
	var base_h := 0.0
	if d_shore >= 0.0:
		var shallow_span := 30.0 if arch == &"wreck_shoal" else clampf(radius * 0.24, 18.0, 32.0)
		var deep_span := maxf(24.0, seabed_r - r_coast - shallow_span)
		if d_shore <= shallow_span:
			var t := d_shore / shallow_span
			base_h = -3.8 * (t * t * (2.0 - t))
		else:
			var t2 := clampf((d_shore - shallow_span) / deep_span, 0.0, 1.0)
			base_h = lerpf(-3.8, SEA_FLOOR_Y, t2 * t2 * (3.0 - 2.0 * t2))
	else:
		var inland := -d_shore
		var beach_span := clampf(radius * 0.20, 14.0, 24.0)
		var beach_t := clampf(inland / beach_span, 0.0, 1.0)
		var hill_t := clampf((inland - beach_span * 0.65) / maxf(20.0, radius * 0.58), 0.0, 1.0)
		base_h = 3.0 * (beach_t * (2.0 - beach_t)) + clampf(5.0 + radius * 0.035, 5.2, 11.5) * (hill_t * hill_t * (3.0 - 2.0 * hill_t))
		base_h += detail_n * 1.8 * hill_t

	# Archetype-specific ridged mountain massifs, stepped geological terraces, canyons, lagoons & harbours.
	var h := base_h
	var scale_r := radius / 60.0

	match arch:
		&"outpost":
			# Sweeping curved limestone mountain massif & lush upper terrace behind the harbour village!
			var main_ridge := _ridged_massif(u, v, Vector2(-34.0 * scale_r, 16.0 * scale_r),
				Vector2(28.0 * scale_r, 26.0 * scale_r), 26.0 * scale_r, 20.0 * scale_r,
				target_peak, target_peak * 0.70, 9.0 * scale_r, 9.5, s + 1.1)
			var west_arm := _ridged_massif(u, v, Vector2(-34.0 * scale_r, 16.0 * scale_r),
				Vector2(-40.0 * scale_r, -16.0 * scale_r), 20.0 * scale_r, 14.0 * scale_r,
				target_peak * 0.62, target_peak * 0.34, -5.0 * scale_r, 8.0, s + 2.4)
			var upper_bench := _terraced_cliff(u, v, 8.0 * scale_r, 12.0 * scale_r,
				26.0 * scale_r, 18.0 * scale_r, 14.5, -0.25, 2, 0.58, s + 3.7)
			h = maxf(h, maxf(main_ridge, maxf(west_arm, upper_bench)))
			h += ridge_n * 2.4 * _smoothstep(8.0, 26.0, h)
			h = _grade_outpost_harbour(h, u, v, radius, false)

		&"grand_outpost":
			# Massive Capital Port (Galleon's Reach): deep natural harbour fjord framed by sweeping curved
			# headland massifs, lush terraced upper town highlands, and twin guardian cliff peaks!
			var back_arc_w := _ridged_massif(u, v, Vector2(-88.0, 38.0), Vector2(-12.0, 94.0),
				46.0, 44.0, target_peak * 0.72, target_peak, 18.0, 11.0, s + 1.3)
			var back_arc_e := _ridged_massif(u, v, Vector2(-12.0, 94.0), Vector2(88.0, 42.0),
				44.0, 42.0, target_peak, target_peak * 0.68, 16.0, 11.0, s + 2.7)
			var arm_port := _ridged_massif(u, v, Vector2(-86.0, 32.0), Vector2(-78.0, -96.0),
				38.0, 26.0, target_peak * 0.60, target_peak * 0.36, -14.0, 9.0, s + 4.1)
			var arm_stbd := _ridged_massif(u, v, Vector2(86.0, 36.0), Vector2(76.0, -88.0),
				36.0, 26.0, target_peak * 0.54, target_peak * 0.34, 14.0, 9.0, s + 5.5)
			var town_terrace := _terraced_cliff(u, v, 0.0, 32.0, 66.0, 42.0, 16.5, 0.05, 3, 0.56, s + 6.9)
			var east_overlook := _terraced_cliff(u, v, 56.0, -24.0, 28.0, 26.0, 24.0, -0.35, 3, 0.48, s + 8.2)
			h = maxf(h, maxf(maxf(back_arc_w, back_arc_e), maxf(arm_port, arm_stbd)))
			h = maxf(h, maxf(town_terrace, east_overlook))
			h += ridge_n * 3.0 * _smoothstep(10.0, 32.0, h)
			h = _grade_outpost_harbour(h, u, v, radius, true)

		&"sea_stack":
			# Dramatic razor-ridged coastal sea-stack monolith & twin crooked rock fangs rising from turquoise shallows!
			var fang_main := _ridged_massif(u, v, Vector2(-9.0 * scale_r, 8.0 * scale_r),
				Vector2(10.0 * scale_r, -3.0 * scale_r), 16.0 * scale_r, 13.0 * scale_r,
				target_peak, target_peak * 0.72, 4.5 * scale_r, 7.5, s + 1.7)
			var fang_sub := _terraced_cliff(u, v, -15.0 * scale_r, -10.0 * scale_r,
				12.0 * scale_r, 11.0 * scale_r, target_peak * 0.58, 0.65, 3, 0.24, s + 3.2)
			h = maxf(h, maxf(fang_main, fang_sub))
			h += ridge_n * 3.2 * _smoothstep(6.0, 22.0, h)
			# Carve a walkable golden sandbar landing pocket on the -v seaward shelf for the tide-path.
			var pocket := _smoothstep(20.0 * scale_r, 7.5 * scale_r, absf(u - 2.0 * scale_r)) * _smoothstep(-3.0 * scale_r, -13.0 * scale_r, v)
			if d_shore < 0.0 and pocket > 0.001:
				var p_h := 1.45 + 1.05 * clampf((-d_shore - 2.5) / (14.0 * scale_r), 0.0, 1.0)
				h = lerpf(h, minf(h, p_h), pocket * 0.94)

		&"treasure_peak":
			# Iconic Cutlass Cay: sweeping golden landing cove + curved terraced twin limestone ridge peaks!
			var ridge_main := _ridged_massif(u, v, Vector2(-14.0 * scale_r, 16.0 * scale_r),
				Vector2(10.0 * scale_r, 8.0 * scale_r), 22.0 * scale_r, 17.0 * scale_r,
				target_peak, target_peak * 0.74, 6.0 * scale_r, 9.0, s + 0.9)
			var spire_east := _terraced_cliff(u, v, 19.0 * scale_r, 2.0 * scale_r,
				16.0 * scale_r, 15.0 * scale_r, target_peak * 0.68, -0.55, 3, 0.26, s + 2.3)
			var shoulder_w := _terraced_cliff(u, v, -22.0 * scale_r, 14.0 * scale_r,
				15.0 * scale_r, 14.0 * scale_r, target_peak * 0.44, 0.85, 2, 0.42, s + 4.1)
			h = maxf(h, maxf(ridge_main, maxf(spire_east, shoulder_w)))
			h += ridge_n * 3.2 * _smoothstep(8.0, 26.0, h)
			# Grade a wide, welcoming golden sand cove on the -v landing beach.
			var cove_u := _smoothstep(30.0 * scale_r, 12.0 * scale_r, absf(u - 2.0 * scale_r))
			var cove_v := _smoothstep(6.0 * scale_r, -16.0 * scale_r, v)
			var cove_mask := cove_u * cove_v
			if d_shore < 0.0 and cove_mask > 0.001:
				var inland_c := -d_shore
				var cove_h := 1.48 + 1.42 * clampf((inland_c - 4.8) / (26.0 * scale_r), 0.0, 1.0)
				h = lerpf(h, minf(h, cove_h), cove_mask * 0.82)

		&"twin_spires":
			# Soaring twin terraced cathedral massifs framing a lush emerald highland canyon & waterfall cliff!
			var m_west := _ridged_massif(u, v, Vector2(-24.0 * scale_r, -12.0 * scale_r),
				Vector2(-18.0 * scale_r, 24.0 * scale_r), 24.0 * scale_r, 22.0 * scale_r,
				target_peak * 0.82, target_peak, -8.0 * scale_r, 11.5, s + 1.2)
			var m_east := _ridged_massif(u, v, Vector2(22.0 * scale_r, -14.0 * scale_r),
				Vector2(20.0 * scale_r, 20.0 * scale_r), 21.0 * scale_r, 22.0 * scale_r,
				target_peak * 0.70, target_peak * 0.84, 7.0 * scale_r, 11.0, s + 2.8)
			var head_cliff := _terraced_cliff(u, v, 0.0, 28.0 * scale_r,
				24.0 * scale_r, 18.0 * scale_r, target_peak * 0.44, 0.15, 3, 0.48, s + 4.4)
			var saddle_shelf := _terraced_cliff(u, v, 0.0, 2.0 * scale_r,
				18.0 * scale_r, 24.0 * scale_r, 14.5, 0.0, 2, 0.62, s + 5.6)
			h = maxf(h, maxf(maxf(m_west, m_east), maxf(head_cliff, saddle_shelf)))
			# Carve a scenic walkable emerald canyon floor descending from the waterfall headwall to the -v cove!
			var canyon_u := _smoothstep(15.0 * scale_r, 5.5 * scale_r, absf(u))
			var canyon_v := _smoothstep(18.0 * scale_r, 8.0 * scale_r, v) * _smoothstep(-46.0 * scale_r, -28.0 * scale_r, v)
			var canyon_t := clampf((v + 38.0 * scale_r) / (50.0 * scale_r), 0.0, 1.0)
			var canyon_h := lerpf(1.8, 12.5, canyon_t * canyon_t * (3.0 - 2.0 * canyon_t))
			h = lerpf(h, minf(h, canyon_h), canyon_u * canyon_v * 0.82)
			h += ridge_n * 3.4 * _smoothstep(14.0, 36.0, h)

		&"crescent_lagoon":
			# Broad coral-sand ring embracing a vast turquoise shallow lagoon + sculpted terraced back headland!
			var lag_d := Vector2(u, v + 8.0 * scale_r).length()
			var lag_mouth := _smoothstep(20.0 * scale_r, 6.0 * scale_r, absf(u)) * _smoothstep(-6.0 * scale_r, -26.0 * scale_r, v)
			var lag_pool := _smoothstep(29.0 * scale_r, 14.0 * scale_r, lag_d)
			var lagoon_mask := clampf(maxf(lag_pool, lag_mouth), 0.0, 1.0)
			var back_ridge := _ridged_massif(u, v, Vector2(-18.0 * scale_r, 32.0 * scale_r),
				Vector2(24.0 * scale_r, 28.0 * scale_r), 18.0 * scale_r, 16.0 * scale_r,
				target_peak * 0.86, target_peak, 6.0 * scale_r, 8.5, s + 1.5)
			var horn_w := _terraced_cliff(u, v, -33.0 * scale_r, 6.0 * scale_r,
				15.0 * scale_r, 18.0 * scale_r, target_peak * 0.44, 0.65, 2, 0.46, s + 3.0)
			h = maxf(h, maxf(back_ridge, horn_w))
			h = lerpf(h, -2.2 + 0.5 * detail_n, lagoon_mask * 0.92)

		&"sea_arch":
			# Twin terraced coastal headlands cradling a bright sandy tide bay (crowned with rock_arch.glb).
			var b_l := _ridged_massif(u, v, Vector2(-28.0 * scale_r, -6.0 * scale_r),
				Vector2(-18.0 * scale_r, 22.0 * scale_r), 20.0 * scale_r, 18.0 * scale_r,
				target_peak * 0.78, target_peak, -5.0 * scale_r, 9.0, s + 1.1)
			var b_r := _ridged_massif(u, v, Vector2(26.0 * scale_r, -2.0 * scale_r),
				Vector2(18.0 * scale_r, 24.0 * scale_r), 18.0 * scale_r, 18.0 * scale_r,
				target_peak * 0.66, target_peak * 0.80, 5.0 * scale_r, 9.0, s + 2.5)
			var b_back := _terraced_cliff(u, v, 0.0, 28.0 * scale_r,
				20.0 * scale_r, 16.0 * scale_r, target_peak * 0.54, 0.12, 3, 0.45, s + 3.9)
			h = maxf(h, maxf(b_l, maxf(b_r, b_back)))
			# Soft sandy cove trough between the twin bluffs.
			var bay := _smoothstep(18.0 * scale_r, 6.0 * scale_r, absf(u)) * _smoothstep(12.0 * scale_r, -16.0 * scale_r, v)
			h = lerpf(h, clampf(lerpf(-1.8, 2.8, (v + 30.0 * scale_r) / (40.0 * scale_r)), -2.2, 3.0), bay * 0.72)

		&"fort_rock":
			# Tiered coral-limestone Watch Mesa crowned by a level bastion plateau,
			# a walkable sloped landing ramp from the -v cove, and twin sculpted rear citadel ridges!
			var bastion_v := 2.0 * scale_r
			var bastion_y := clampf(target_peak * 0.38, 15.2, 19.5)
			var mesa := _terraced_cliff(u, v, 0.0, bastion_v, 34.0 * scale_r, 31.0 * scale_r,
				bastion_y, 0.20, 3, 0.56, s + 1.4)
			var rear_ridge_l := _ridged_massif(u, v, Vector2(-32.0 * scale_r, 18.0 * scale_r),
				Vector2(-6.0 * scale_r, 32.0 * scale_r), 18.0 * scale_r, 16.0 * scale_r,
				target_peak * 0.84, target_peak, 6.0 * scale_r, 9.0, s + 2.6)
			var rear_ridge_r := _ridged_massif(u, v, Vector2(6.0 * scale_r, 30.0 * scale_r),
				Vector2(30.0 * scale_r, 16.0 * scale_r), 16.0 * scale_r, 15.0 * scale_r,
				target_peak * 0.82, target_peak * 0.64, -5.0 * scale_r, 9.0, s + 4.0)
			h = maxf(h, maxf(mesa, maxf(rear_ridge_l, rear_ridge_r)))
			h += ridge_n * 2.2 * _smoothstep(18.0, 34.0, h)
			# Level the bastion courtyard & gun terrace plateau cleanly so walls & cannons sit flush.
			var mesa_d := Vector2(u, v - bastion_v).length()
			var flat_in := maxf(15.2, 13.4 * scale_r)
			var flat_out := maxf(18.5, 16.2 * scale_r)
			var mesa_flat := _smoothstep(flat_out, flat_in, mesa_d)
			h = lerpf(h, bastion_y, mesa_flat)
			# Walkable sloped landing ramp from the -v sandy cove straight up into the bastion gateway.
			var ramp_u := _smoothstep(14.0 * scale_r, 5.6 * scale_r, absf(u))
			var ramp_v := _smoothstep(-46.0 * scale_r, -36.0 * scale_r, v) * _smoothstep(-7.0 * scale_r, -12.5 * scale_r, v)
			var ramp_t := clampf((v + 38.0 * scale_r) / (27.5 * scale_r), 0.0, 1.0)
			var ramp_h := lerpf(1.75, bastion_y, ramp_t)
			h = lerpf(h, ramp_h, ramp_u * ramp_v * 0.95)
			# Welcoming sandy landing beach cove at the ramp foot (-v shoreline).
			var cove_u := _smoothstep(28.0 * scale_r, 11.0 * scale_r, absf(u))
			var cove_v := _smoothstep(-28.0 * scale_r, -42.0 * scale_r, v)
			if d_shore < 0.0 and cove_u * cove_v > 0.001:
				var cove_h := 1.45 + 1.15 * clampf((-d_shore - 4.0) / (20.0 * scale_r), 0.0, 1.0)
				h = lerpf(h, minf(h, cove_h), cove_u * cove_v * 0.78)

		&"grand_citadel":
			# Massive Multi-Biome Flagship Citadel (Sovereign's Bastion, 364 m across!):
			# Crowned by an elevated FortBastion + FortVault plateau, flanked by outer bastion headlands,
			# sweeping lush emerald jungle temple terraces, a waterfall cliff drop, and a 96 m rear massif!
			var bastion_v := 18.0
			var bastion_y := clampf(target_peak * 0.24, 21.0, 25.0)
			var cit_mesa := _terraced_cliff(u, v, 0.0, bastion_v, 48.0, 44.0, bastion_y, 0.12, 3, 0.56, s + 0.8)
			var rear_w := _ridged_massif(u, v, Vector2(-106.0, 54.0), Vector2(-12.0, 108.0),
				48.0, 46.0, target_peak * 0.78, target_peak, 22.0, 11.5, s + 2.1)
			var rear_e := _ridged_massif(u, v, Vector2(-12.0, 108.0), Vector2(96.0, 56.0),
				46.0, 44.0, target_peak, target_peak * 0.80, 18.0, 11.5, s + 3.4)
			var temple_terrace_w := _terraced_cliff(u, v, -76.0, 14.0, 46.0, 44.0, 26.0, 0.28, 3, 0.58, s + 4.8)
			var temple_terrace_e := _terraced_cliff(u, v, 74.0, 8.0, 46.0, 42.0, 30.0, -0.32, 3, 0.56, s + 6.1)
			var prom_w := _terraced_cliff(u, v, -68.0, -68.0, 34.0, 32.0, 15.5, 0.45, 2, 0.54, s + 7.5)
			var prom_e := _terraced_cliff(u, v, 68.0, -64.0, 34.0, 32.0, 16.0, -0.40, 2, 0.54, s + 8.9)
			h = maxf(h, maxf(cit_mesa, maxf(rear_w, rear_e)))
			h = maxf(h, maxf(maxf(temple_terrace_w, temple_terrace_e), maxf(prom_w, prom_e)))
			h += ridge_n * 3.2 * _smoothstep(16.0, 42.0, h)
			# Carve a dramatic eastern waterfall plunge cove right below temple_terrace_e (u ~ 56, v ~ -26).
			var wf_cove := _smoothstep(24.0, 8.0, Vector2(u - 54.0, v + 30.0).length())
			h = lerpf(h, minf(h, 2.2), wf_cove * 0.84)
			# Level the central FortBastion & FortVault courtyard plateau cleanly.
			var cit_d := Vector2(u, v - bastion_v).length()
			h = lerpf(h, bastion_y, _smoothstep(28.0, 22.0, cit_d))
			# Grand walkable graded coastal approach road from the -v landing beach up to Bay 0 gateway!
			var g_ramp_u := _smoothstep(18.0, 8.0, absf(u))
			var g_ramp_v := _smoothstep(-105.0, -82.0, v) * _smoothstep(4.0, -6.0, v)
			var g_ramp_t := clampf((v + 86.0) / 82.0, 0.0, 1.0)
			var g_ramp_h := lerpf(1.75, bastion_y, g_ramp_t)
			h = lerpf(h, g_ramp_h, g_ramp_u * g_ramp_v * 0.94)
			# Welcoming sweeping golden sand landing cove along -v shoreline.
			var g_cove_u := _smoothstep(54.0, 22.0, absf(u))
			var g_cove_v := _smoothstep(-68.0, -104.0, v)
			if d_shore < 0.0 and g_cove_u * g_cove_v > 0.001:
				var gc_h := 1.45 + 1.35 * clampf((-d_shore - 4.0) / 36.0, 0.0, 1.0)
				h = lerpf(h, minf(h, gc_h), g_cove_u * g_cove_v * 0.80)

		&"wreck_shoal":
			# Broad shallow sandbars & jagged knife-edge limestone ribs for dramatic shipwrecks.
			var rib1 := _ridged_massif(u, v, Vector2(-24.0 * scale_r, 12.0 * scale_r),
				Vector2(-2.0 * scale_r, 18.0 * scale_r), 14.0 * scale_r, 11.0 * scale_r,
				target_peak * 0.82, target_peak, 4.0 * scale_r, 7.5, s + 1.2)
			var rib2 := _ridged_massif(u, v, Vector2(12.0 * scale_r, 14.0 * scale_r),
				Vector2(26.0 * scale_r, 2.0 * scale_r), 12.0 * scale_r, 10.0 * scale_r,
				target_peak * 0.74, target_peak * 0.45, -3.5 * scale_r, 7.0, s + 2.5)
			var rib3 := _terraced_cliff(u, v, 2.0 * scale_r, -10.0 * scale_r,
				11.0 * scale_r, 13.0 * scale_r, target_peak * 0.36, 0.15, 2, 0.36, s + 3.8)
			h = maxf(h, maxf(rib1, maxf(rib2, rib3)))
			# Broad sandy shoal apron extending seaward on -v.
			var shoal := _smoothstep(42.0 * scale_r, 14.0 * scale_r, Vector2(u, v + 22.0 * scale_r).length())
			h = maxf(h, lerpf(-3.2, 1.8, shoal) + detail_n * 0.6)

		&"volcano_crag":
			# Colossal multi-ribbed basalt stratovolcano with recessed summit caldera bowl,
			# jagged rim fangs (peaking at 14.5 * scale_r), radiating lava-flow buttress ridges & fumarole benches!
			var cv := v - 4.0 * scale_r
			var v_dist := Vector2(u, cv).length()
			var v_ang := atan2(cv, u)
			var cone := _faceted_spire(u, v, 0.0, 4.0 * scale_r, 50.0 * scale_r, 48.0 * scale_r, target_peak * 1.12, 0.18, 7.0, 1.08)
			var rim_band := exp(-pow((v_dist - 14.5 * scale_r) / (6.8 * scale_r), 2.0))
			var rim_jags := 1.0 + 0.16 * cos(v_ang * 5.0 + 0.4) + 0.10 * sin(v_ang * 3.0 - 0.7)
			var breach := _smoothstep(0.35, 0.95, -sin(v_ang)) * 0.24
			cone += rim_band * (target_peak * 0.30) * rim_jags * (1.0 - breach)
			var bowl_mask := _smoothstep(13.8 * scale_r, 8.8 * scale_r, v_dist)
			var bowl_t := clampf((v_dist - 6.5 * scale_r) / (5.5 * scale_r), 0.0, 1.0)
			var bowl_floor := target_peak * (0.68 + 0.09 * bowl_t * bowl_t)
			cone = lerpf(cone, minf(cone, bowl_floor), bowl_mask)
			# Radiating sculpted basalt lava-flow ribs & fumarole cliff benches outside the caldera bowl.
			var rib_e := _ridged_massif(u, v, Vector2(18.0 * scale_r, 10.0 * scale_r),
				Vector2(44.0 * scale_r, 22.0 * scale_r), 18.0 * scale_r, 14.0 * scale_r,
				target_peak * 0.60, target_peak * 0.26, 6.0 * scale_r, 11.0, s + 1.6)
			var rib_w := _ridged_massif(u, v, Vector2(-18.0 * scale_r, 12.0 * scale_r),
				Vector2(-46.0 * scale_r, -6.0 * scale_r), 18.0 * scale_r, 14.0 * scale_r,
				target_peak * 0.56, target_peak * 0.22, -7.0 * scale_r, 11.0, s + 3.1)
			var rib_n := _ridged_massif(u, v, Vector2(-4.0 * scale_r, 20.0 * scale_r),
				Vector2(10.0 * scale_r, 48.0 * scale_r), 20.0 * scale_r, 15.0 * scale_r,
				target_peak * 0.62, target_peak * 0.28, 8.0 * scale_r, 11.0, s + 4.7)
			var bench_sw := _terraced_cliff(u, v, -28.0 * scale_r, -26.0 * scale_r,
				18.0 * scale_r, 16.0 * scale_r, target_peak * 0.24, 0.5, 2, 0.55, s + 6.2)
			var bench_se := _terraced_cliff(u, v, 28.0 * scale_r, -24.0 * scale_r,
				18.0 * scale_r, 16.0 * scale_r, target_peak * 0.26, -0.45, 2, 0.55, s + 7.4)
			var outer_ribs := maxf(maxf(rib_e, rib_w), maxf(rib_n, maxf(bench_sw, bench_se)))
			h = maxf(h, maxf(cone, lerpf(outer_ribs, cone, bowl_mask)))
			# Subtle geological basalt strata outside the caldera bowl.
			if h > 8.0 and bowl_mask < 0.35:
				h = lerpf(h, _apply_geological_terraces(h, 12.5, 0.42), 1.0 - bowl_mask * 2.5)
			h += ridge_n * 4.2 * _smoothstep(12.0, 44.0, h) * (1.0 - bowl_mask * 0.85)
			# Walkable dark-ash pocket beach on the -v landing flank.
			var pock := _smoothstep(22.0 * scale_r, 8.0 * scale_r, absf(u)) * _smoothstep(-18.0 * scale_r, -40.0 * scale_r, v)
			h = lerpf(h, minf(h, 2.2), pock * 0.74)

		&"palm_atoll":
			# Lush coral ring atoll with turquoise center lagoon, sandy dunes, and a single windward crag.
			var c_dist := Vector2(u, v).length()
			var ring_band := exp(-pow((c_dist - radius * 0.64) / (radius * 0.24), 2.0))
			var channel := _smoothstep(14.0 * scale_r, 4.0 * scale_r, absf(u)) * _smoothstep(0.0, -radius * 0.9, v)
			var atoll_h := lerpf(SEA_FLOOR_Y, 4.4 + detail_n * 1.5, clampf(ring_band * 1.35, 0.0, 1.0))
			var inner_lagoon := _smoothstep(radius * 0.56, radius * 0.28, c_dist)
			atoll_h = lerpf(atoll_h, -2.0 + detail_n * 0.4, inner_lagoon)
			atoll_h = lerpf(atoll_h, -2.8, channel * 0.85)
			var rock_head := _terraced_cliff(u, v, 22.0 * scale_r, 24.0 * scale_r,
				18.0 * scale_r, 16.0 * scale_r, target_peak, 0.4, 3, 0.35, s + 2.1)
			h = maxf(maxf(base_h * 0.35, atoll_h), rock_head)

		&"skull_bluff":
			# Monumental stepped limestone skull headland with sculpted jaw ridges, twin dark brow hollows & lush terraces!
			var head := _terraced_cliff(u, v, 0.0, 10.0 * scale_r, 36.0 * scale_r, 30.0 * scale_r,
				target_peak * 0.84, 0.08, 4, 0.44, s + 1.0)
			var brow_ridge := _ridged_massif(u, v, Vector2(-22.0 * scale_r, 14.0 * scale_r),
				Vector2(22.0 * scale_r, 14.0 * scale_r), 18.0 * scale_r, 18.0 * scale_r,
				target_peak, target_peak * 0.94, 8.0 * scale_r, 10.0, s + 2.4)
			var lower_terrace_w := _terraced_cliff(u, v, -34.0 * scale_r, -12.0 * scale_r,
				18.0 * scale_r, 18.0 * scale_r, 16.5, 0.35, 2, 0.58, s + 3.7)
			var lower_terrace_e := _terraced_cliff(u, v, 34.0 * scale_r, -10.0 * scale_r,
				18.0 * scale_r, 18.0 * scale_r, 15.0, -0.35, 2, 0.58, s + 4.9)
			h = maxf(h, maxf(maxf(head, brow_ridge), maxf(lower_terrace_w, lower_terrace_e)))
			# Twin dark cliff brow hollows on the -v sea-facing wall.
			var h_l := _smoothstep(10.5 * scale_r, 3.0 * scale_r, Vector2(u + 11.5 * scale_r, v + 8.0 * scale_r).length())
			var h_r := _smoothstep(10.5 * scale_r, 3.0 * scale_r, Vector2(u - 11.5 * scale_r, v + 8.0 * scale_r).length())
			h -= (h_l + h_r) * (target_peak * 0.24)
			h += ridge_n * 2.8 * _smoothstep(10.0, 32.0, h)

		&"smuggler_cove":
			# Steep terraced horseshoe cliff amphitheatre enclosing a hidden pocket beach & cliff-embedded sea cave!
			var back_ridge := _ridged_massif(u, v, Vector2(-28.0 * scale_r, 22.0 * scale_r),
				Vector2(28.0 * scale_r, 22.0 * scale_r), 24.0 * scale_r, 24.0 * scale_r,
				target_peak * 0.82, target_peak, 12.0 * scale_r, 9.5, s + 1.3)
			var wing_l := _ridged_massif(u, v, Vector2(-28.0 * scale_r, 22.0 * scale_r),
				Vector2(-32.0 * scale_r, -12.0 * scale_r), 20.0 * scale_r, 16.0 * scale_r,
				target_peak * 0.78, target_peak * 0.42, -5.0 * scale_r, 9.0, s + 2.7)
			var wing_r := _ridged_massif(u, v, Vector2(28.0 * scale_r, 22.0 * scale_r),
				Vector2(32.0 * scale_r, -10.0 * scale_r), 20.0 * scale_r, 16.0 * scale_r,
				target_peak * 0.76, target_peak * 0.38, 5.0 * scale_r, 9.0, s + 3.9)
			var v_grotto := 6.0 * scale_r
			var cheek_l := _faceted_spire(u, v, -15.5, v_grotto + 7.5, 14.5, 15.5, target_peak * 0.48, 0.25, 5.0, 1.32)
			var cheek_r := _faceted_spire(u, v, 15.5, v_grotto + 7.5, 14.5, 15.5, target_peak * 0.45, -0.28, 5.0, 1.32)
			h = maxf(h, maxf(maxf(back_ridge, maxf(wing_l, wing_r)), maxf(cheek_l, cheek_r)))
			# Sheltered sandy pocket cove carved right into the amphitheatre heart.
			var cov := _smoothstep(24.0 * scale_r, 10.0 * scale_r, Vector2(u, v + 6.0 * scale_r).length())
			var mouth := _smoothstep(14.0 * scale_r, 5.0 * scale_r, absf(u)) * _smoothstep(-2.0 * scale_r, -30.0 * scale_r, v)
			var target_cov := lerpf(-2.4, 2.5, clampf((v + 24.0 * scale_r) / (26.0 * scale_r), 0.0, 1.0))
			h = lerpf(h, minf(h, target_cov), clampf(maxf(cov, mouth), 0.0, 1.0) * 0.88)
			# Carve exact cave-relative walkable sea-cave grotto recess around v_grotto
			# so the mountain tightly hugs the unscaled GrottoVaultMesh at any island scale!
			var grotto_u := _smoothstep(11.0, 5.8, absf(u))
			var grotto_v := _smoothstep(v_grotto - 7.5, v_grotto - 2.0, v) * _smoothstep(v_grotto + 20.5, v_grotto + 14.8, v)
			var grotto_mask := grotto_u * grotto_v
			if grotto_mask > 0.001:
				var grotto_floor := lerpf(1.94, 2.38, clampf((v - (v_grotto - 2.0)) / 14.5, 0.0, 1.0))
				h = lerpf(h, minf(h, grotto_floor), grotto_mask)

	# Keep outer skirt pinned cleanly to SEA_FLOOR_Y so islands blend seamlessly into deep ocean.
	var outer_t := _smoothstep(seabed_r - 12.0, seabed_r + 2.0, r)
	return lerpf(h, SEA_FLOOR_Y, outer_t)


static func _grade_outpost_harbour(h: float, u: float, v: float, radius: float, is_grand: bool) -> float:
	# Exact unscaled harbour village, Beacon Tower headland shelf, and deep-water pier channel
	# so Outpost.build_outpost_structures() sits flush & navigable at any outpost scale (62..166 m)!
	var bcn_mesa := _stepped_mesa(u, v, 24.0, -6.5, 13.5, 13.5, 11.8, 0.25, 6.0, 0.52)
	h = maxf(h, bcn_mesa)
	var bcn_d := Vector2(u - 24.0, v + 6.5).length()
	h = lerpf(h, 11.8, _smoothstep(9.0, 5.2, bcn_d))

	# Smoothly graded walkable harbour village terrace (u in [-18..16], v in [-26..-1]).
	var plaza_u := _smoothstep(23.0, 13.5, absf(u + 1.5))
	var plaza_v := _smoothstep(-28.5, -23.5, v) * _smoothstep(7.0, -3.0, v)
	var plaza_target := lerpf(0.35, 3.35, clampf((v + 25.8) / 18.5, 0.0, 1.0))
	h = lerpf(h, plaza_target, plaza_u * plaza_v * 0.98)

	# Deep-water harbour pier channel & mooring basin opening straight seaward from v = -25.8 to open sea!
	var chan_outer := 36.0 if is_grand else 23.0
	var chan_inner := 16.0 if is_grand else 11.5
	# Widen the grand fjord channel naturally as it opens seaward past the dock pier.
	var seaward_flare := clampf((-v - 42.0) * 0.28, 0.0, 24.0) if is_grand else 0.0
	var chan_u := _smoothstep(chan_outer + seaward_flare, chan_inner + seaward_flare * 0.6, absf(u - 1.5))
	var chan_v := _smoothstep(-24.2, -28.8, v)
	var chan_depth := lerpf(0.35, -8.4, clampf((-25.8 - v) / 10.5, 0.0, 1.0))
	chan_depth = minf(chan_depth, lerpf(-8.4, SEA_FLOOR_Y, clampf((-48.0 - v) / maxf(28.0, radius * 0.65), 0.0, 1.0)))
	h = lerpf(h, minf(h, chan_depth), chan_u * chan_v)

	# Guarantee exact gentle walkable sand ramp landing right at dock ramp foot (u=0, v=-25.75).
	var ramp_d := Vector2(u * 0.65, v + 25.75).length()
	h = lerpf(h, 0.34, _smoothstep(6.5, 2.2, ramp_d))
	return h


static func _apply_geological_terraces(raw_h: float, step_height: float, terrace_strength: float) -> float:
	if raw_h <= 3.5 or step_height <= 0.5:
		return raw_h
	var q := raw_h / step_height
	var base_q := floorf(q)
	var frac := q - base_q
	# Steep limestone/basalt cliff riser across 0.06..0.52 followed by a natural sloping strata bench.
	var stepped := base_q + _smoothstep(0.06, 0.52, frac) * 0.86 + frac * 0.14
	return lerpf(raw_h, stepped * step_height, clampf(terrace_strength, 0.0, 1.0))


static func _ridged_massif(u: float, v: float, p_a: Vector2, p_b: Vector2,
		width_a: float, width_b: float, height_a: float, height_b: float,
		ridge_warp: float, strata_step: float, seed_f: float) -> float:
	var ab := p_b - p_a
	var len_sq := ab.length_squared()
	if len_sq < 0.01:
		return SEA_FLOOR_Y
	var seg_len := sqrt(len_sq)
	var dir := ab / seg_len
	var perp := Vector2(-dir.y, dir.x)
	var rel := Vector2(u, v) - p_a
	var t_raw := rel.dot(dir) / seg_len
	var t := clampf(t_raw, 0.0, 1.0)
	var w := maxf(lerpf(width_a, width_b, t), 2.0)

	# Exact bounding early-out before expensive noise evaluation (zero visual change, ~4x faster!).
	var lateral_curve := ridge_warp * sin(t * PI)
	var base_spine := p_a + ab * t + perp * lateral_curve
	var max_reach := w * 1.50 + maxf(width_a, width_b) * 0.17
	if Vector2(u, v).distance_squared_to(base_spine) >= max_reach * max_reach:
		return SEA_FLOOR_Y

	# Smooth curved headland spine + low-frequency geological ridge warp.
	var warp_n := (_fbm2(u * 0.026 + seed_f, v * 0.026 - seed_f * 0.8) - 0.5) * 0.32
	var spine_pt := base_spine + perp * (warp_n * maxf(width_a, width_b))
	var dist := Vector2(u, v).distance_to(spine_pt)

	# Eroded radial cliff gullies & angular rock buttresses along the flanks.
	var gully_n := _fbm2(u * 0.055 - seed_f * 1.1, v * 0.055 + seed_f * 0.6)
	var rib_mod := 0.84 + 0.34 * (1.0 - absf(gully_n * 2.0 - 1.0))
	var d_norm := dist / (w * rib_mod)
	if d_norm >= 1.25:
		return SEA_FLOOR_Y

	var crest_h := lerpf(height_a, height_b, t) * (0.92 + 0.16 * sin(t * PI) + 0.08 * (gully_n - 0.5))
	# Convex shoulder profile so ridges feel monumental and craggy instead of narrow triangular pyramids.
	var slope_u := clampf(1.0 - d_norm, 0.0, 1.0)
	var prof := pow(slope_u, 1.12) * (0.82 + 0.18 * _smoothstep(0.0, 0.45, slope_u))
	var h := prof * crest_h
	var high_w := _smoothstep(18.0, 32.0, h)
	if high_w > 0.0:
		# Upper-mountain ridged-multifractal erosion chutes, angular buttress ribs & jagged spine crags.
		var crag_n := _fbm2(u * 0.092 + seed_f * 1.37, v * 0.092 - seed_f * 0.89)
		var crag_ridge := 1.0 - absf(crag_n * 2.0 - 1.0)
		var frac_n := _fbm2(u * 0.165 - seed_f * 0.61, v * 0.165 + seed_f * 1.19)
		var frac_ridge := 1.0 - absf(frac_n * 2.0 - 1.0)
		var crag_sharp := crag_ridge * crag_ridge
		var crag_signed := clampf((crag_sharp - 0.62) * 1.50 + (frac_ridge * frac_ridge - 0.62) * crag_ridge * 1.15, -1.0, 1.0)
		var relief_amp := clampf(crest_h * 0.085, 2.2, 4.8)
		var flank_w := high_w * clampf(slope_u * 1.65, 0.0, 1.0)
		# Accentuate angular crag crowns along the upper ridge spine without altering flanks below 18 m.
		var spine_crown := maxf(crag_sharp - 0.52, 0.0) * _smoothstep(0.68, 0.98, slope_u) * high_w * clampf(crest_h * 0.042, 0.8, 2.4)
		h += crag_signed * relief_amp * flank_w + spine_crown
	if strata_step > 0.5 and h > 4.0:
		var terrace_strength := lerpf(0.46, 0.72, high_w)
		h = _apply_geological_terraces(h, strata_step, terrace_strength)
	if high_w > 0.0:
		h = minf(h, crest_h * 1.15)
	return h


static func _terraced_cliff(u: float, v: float, cx: float, cz: float, rx: float, rz: float,
		height: float, yaw: float, terrace_levels: int, flat_crown: float, seed_f: float) -> float:
	var dx := u - cx
	var dz := v - cz
	var c := cos(-yaw)
	var s := sin(-yaw)
	var lx := (dx * c - dz * s) / maxf(rx, 1.0)
	var lz := (dx * s + dz * c) / maxf(rz, 1.0)
	var r := sqrt(lx * lx + lz * lz)
	if r >= 1.38:
		return SEA_FLOOR_Y

	# Domain-warped organic fracture silhouette instead of uniform radial petals.
	var ang := atan2(lz, lx)
	var rock_n := _fbm2(u * 0.042 + seed_f, v * 0.042 - seed_f * 0.65) - 0.5
	var r_fac := r * (1.0 + 0.18 * rock_n + 0.09 * cos(ang * 5.0 + yaw * 1.4) + 0.05 * sin(ang * 7.0 - seed_f))
	var t := clampf((1.0 - r_fac) / maxf(1.0 - flat_crown, 0.14), 0.0, 1.0)
	var prof := t * t * (3.0 - 2.0 * t)
	var h := prof * height
	var high_w := _smoothstep(18.0, 32.0, h)
	if t > 0.06 and t < 0.82 and high_w > 0.0:
		# Subtle angular vertical rock-fluting / erosion crevices on steep upper cliff flanks only.
		var flute_w := sin(clampf((t - 0.06) / 0.76, 0.0, 1.0) * PI) * high_w
		var flute_n := _fbm2(u * 0.115 - seed_f * 0.73, v * 0.115 + seed_f * 1.29)
		var flute_ridge := 1.0 - absf(flute_n * 2.0 - 1.0)
		var flute_signed := clampf((flute_ridge * flute_ridge - 0.62) * 2.0, -1.0, 1.0)
		var flute_amp := clampf(height * 0.055, 1.4, 2.4)
		h += flute_signed * flute_amp * flute_w
	if terrace_levels >= 2 and t > 0.04 and t < 0.94:
		var step_h := maxf(4.2, height / float(terrace_levels))
		var flank_w := _smoothstep(0.06, 0.16, t) * _smoothstep(0.82, 0.70, t) * high_w
		var terrace_strength := lerpf(0.58, 0.74, flank_w)
		h = _apply_geological_terraces(h, step_h, terrace_strength)
	# Subtle rolling highland grass undulation across the walkable crown plateau.
	if t >= 0.85:
		h += rock_n * minf(2.2, height * 0.06) * _smoothstep(0.85, 0.98, t)
	return h


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
	# Subtle geological terrace steps on steep limestone cliffs (crisper strata above 18 m).
	if h > 5.0:
		var high_w := _smoothstep(18.0, 32.0, h)
		var strata_amp := lerpf(0.032, 0.044, high_w)
		h += strata_amp * height * sin(h * 0.42) * clampf(profile * 2.4, 0.0, 1.0)
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

static func get_terrain_pbr_texture_paths() -> Dictionary:
	return TERRAIN_PBR_TEXTURE_PATHS.duplicate()


static func _create_terrain_material(arch: StringName) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = ISLAND_SHADER
	mat.set_shader_parameter(&"use_terrain_textures", true)
	mat.set_shader_parameter(&"tex_grass_albedo", TEX_GRASS_ALB)
	mat.set_shader_parameter(&"tex_grass_normal", TEX_GRASS_NRM)
	mat.set_shader_parameter(&"tex_dirt_albedo", TEX_DIRT_ALB)
	mat.set_shader_parameter(&"tex_dirt_normal", TEX_DIRT_NRM)
	mat.set_shader_parameter(&"tex_sand_albedo", TEX_SAND_ALB)
	mat.set_shader_parameter(&"tex_sand_normal", TEX_SAND_NRM)
	mat.set_shader_parameter(&"tex_cliff_albedo", TEX_CLIFF_ALB)
	mat.set_shader_parameter(&"tex_cliff_normal", TEX_CLIFF_NRM)
	mat.set_shader_parameter(&"tex_volcanic_albedo", TEX_VOLCANIC_ALB)
	mat.set_shader_parameter(&"tex_volcanic_normal", TEX_VOLCANIC_NRM)
	match arch:
		&"volcano_crag":
			mat.set_shader_parameter(&"cliff_tint", Color(0.45, 0.43, 0.48))
			mat.set_shader_parameter(&"grass_tint", Color(0.76, 0.80, 0.56))
			mat.set_shader_parameter(&"volcanic_amount", 1.0)
			mat.set_shader_parameter(&"cliff_strata_scale", 0.72)
		&"twin_spires":
			mat.set_shader_parameter(&"cliff_tint", Color(1.02, 1.00, 0.95))
			mat.set_shader_parameter(&"grass_tint", Color(0.92, 1.12, 0.88))
			mat.set_shader_parameter(&"lush_jungle_amount", 0.92)
			mat.set_shader_parameter(&"ruin_moss_amount", 0.48)
			mat.set_shader_parameter(&"cliff_strata_scale", 0.84)
		&"grand_citadel":
			mat.set_shader_parameter(&"cliff_tint", Color(0.98, 0.96, 0.92))
			mat.set_shader_parameter(&"grass_tint", Color(0.94, 1.10, 0.88))
			mat.set_shader_parameter(&"lush_jungle_amount", 0.76)
			mat.set_shader_parameter(&"ruin_moss_amount", 0.58)
			mat.set_shader_parameter(&"cliff_strata_scale", 0.74)
			mat.set_shader_parameter(&"path_warmth", 0.52)
		&"grand_outpost":
			mat.set_shader_parameter(&"cliff_tint", Color(1.03, 0.99, 0.92))
			mat.set_shader_parameter(&"grass_tint", Color(0.98, 1.06, 0.92))
			mat.set_shader_parameter(&"lush_jungle_amount", 0.68)
			mat.set_shader_parameter(&"ruin_moss_amount", 0.24)
			mat.set_shader_parameter(&"cliff_strata_scale", 0.78)
			mat.set_shader_parameter(&"path_warmth", 0.68)
		&"crescent_lagoon", &"palm_atoll":
			mat.set_shader_parameter(&"cliff_tint", Color(1.04, 0.98, 0.88))
			mat.set_shader_parameter(&"grass_tint", Color(1.06, 1.08, 0.92))
			mat.set_shader_parameter(&"lush_jungle_amount", 0.52)
			mat.set_shader_parameter(&"ruin_moss_amount", 0.25)
		&"smuggler_cove":
			mat.set_shader_parameter(&"cliff_tint", Color(0.96, 0.94, 0.90))
			mat.set_shader_parameter(&"grass_tint", Color(0.96, 1.05, 0.92))
			mat.set_shader_parameter(&"lush_jungle_amount", 0.45)
			mat.set_shader_parameter(&"ruin_moss_amount", 0.36)
		&"fort_rock", &"skull_bluff":
			mat.set_shader_parameter(&"cliff_tint", Color(0.92, 0.90, 0.87))
			mat.set_shader_parameter(&"ruin_moss_amount", 0.42)
			mat.set_shader_parameter(&"cliff_strata_scale", 0.90)
		&"sea_stack":
			mat.set_shader_parameter(&"cliff_tint", Color(0.92, 0.90, 0.88))
			mat.set_shader_parameter(&"ruin_moss_amount", 0.22)
			mat.set_shader_parameter(&"cliff_strata_scale", 1.32)
		_:
			mat.set_shader_parameter(&"cliff_tint", Color(1.0, 1.0, 1.0))
			mat.set_shader_parameter(&"grass_tint", Color(1.0, 1.0, 1.0))
	return mat


static func _build_terrain_mesh_and_collider(island: Island, grid: PackedFloat32Array,
		grid_res: int, grid_half: float, mat: ShaderMaterial,
		arch: StringName = &"treasure_peak", landing_yaw: float = 0.0) -> void:
	var stride := grid_res + 1
	var span := grid_half * 2.0
	var step := span / float(grid_res)
	var vert_count := stride * stride
	var cos_y := cos(landing_yaw)
	var sin_y := sin(landing_yaw)
	var peak_ref := maxf(island.peak_height, 24.0)

	# Compute winding walkable trail polylines & expose lightweight metadata for IslandDetails trail parting.
	var trail_polylines: Array[PackedVector2Array] = IslandTrails.get_trail_polylines(arch, island.island_radius, island.island_id)
	var trail_hw: float = IslandTrails.get_trail_half_width(arch)
	var trail_sample_hw := maxf(trail_hw, step * 1.05)
	island.set_meta(&"trail_polylines", trail_polylines)
	island.set_meta(&"trail_half_width", trail_hw)
	island.set_meta(&"landing_yaw", landing_yaw)

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

			# 2-ring crevice AO darkening in ravines & inner terrace corners + ridge highlight pop.
			var ix0b := maxi(ix - 2, 0)
			var ix1b := mini(ix + 2, grid_res)
			var iz0b := maxi(iz - 2, 0)
			var iz1b := mini(iz + 2, grid_res)
			var avg1 := 0.25 * (hx0 + hx1 + hz0 + hz1)
			var avg2 := 0.25 * (grid[iz * stride + ix0b] + grid[iz * stride + ix1b] + grid[iz0b * stride + ix] + grid[iz1b * stride + ix])
			var curv := clampf((y - avg1) * 0.14 + (y - avg2) * 0.08, -0.22, 0.11)
			var shade := clampf(1.0 + curv, 0.78, 1.09)
			var c_vert := Color(shade, shade, shade, 1.0)

			# Subtle biome rock richness & warm sun-bleached coastal approach path tinting.
			var u := x * cos_y - z * sin_y
			var v := x * sin_y + z * cos_y
			if arch == &"volcano_crag":
				var rim_w := _smoothstep(peak_ref * 0.56, peak_ref * 0.82, y)
				c_vert = c_vert.lerp(Color(0.84, 0.80, 0.78), _smoothstep(4.0, 26.0, y) * 0.35)
				c_vert = c_vert.lerp(Color(1.06, 0.86, 0.72), rim_w * 0.35)
			elif arch == &"twin_spires" or arch == &"grand_citadel":
				if y > 8.0 and y < 32.0 and n.y > 0.78:
					c_vert *= Color(0.92, 1.04, 0.90)
			elif arch == &"sea_stack" or arch == &"skull_bluff":
				if y > -1.5 and y < 4.0 and n.y < 0.72:
					c_vert *= Color(0.84, 0.87, 0.86)

			# Organic winding walkable dirt/cobble footpaths across all 14 islands (1.0 - COLOR.a)
			# plus warm pebbled harbour plaza clearing on outposts (drives 1024x1024 pebbled dirt PBR).
			var trail_a := IslandTrails.sample_trail_alpha(u, v, trail_polylines, trail_sample_hw, n.y, y)
			if (arch == &"outpost" or arch == &"grand_outpost") and n.y > 0.78 and y > 1.0:
				var wobble := sin(v * 0.14 + u * 0.09) * 2.4 + cos(v * 0.27 - u * 0.13) * 1.1
				var plaza_d := Vector2((u + 1.5) * 0.78, v + 14.0).length()
				var plaza_t := (1.0 - _smoothstep(8.0, 17.5, plaza_d + wobble * 0.5)) * 0.88
				if plaza_t > 0.01:
					trail_a = minf(trail_a, lerpf(1.0, 0.06, clampf(plaza_t, 0.0, 1.0)))
			if trail_a < 0.90:
				var warm_t := clampf((0.90 - trail_a) / 0.90, 0.0, 1.0) * 0.25
				c_vert = c_vert.lerp(Color(1.05, 1.01, 0.94), warm_t)
			c_vert.a = trail_a
			colors[idx] = c_vert

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
	var max_dig := 7 if island.island_radius > 110.0 else 5
	var max_enemies := 10 if island.island_radius > 110.0 else 6

	# First look along the welcoming landing cove beach so starter dig sites are easy to reach on foot!
	var beach_candidates: Array[Vector3] = []
	for ring: float in [0.42, 0.58, 0.72, 0.84, 0.91, 0.96]:
		for k in 28:
			var ang := -PI * 0.5 + (float(k) - 14.0) * (TAU / 28.0)
			var u: float = cos(ang) * island.island_radius * ring
			var v: float = sin(ang) * island.island_radius * ring
			var lp := basis * Vector3(u, 0.0, v)
			var h := island.surface_height(lp.x, lp.z)
			if h < 1.15 or h > 5.5:
				continue
			var n := island.surface_normal(lp.x, lp.z)
			if n.y < 0.89:
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

	var dig_spacing := 14.0 if island.island_radius > 110.0 else 11.0
	for p in beach_candidates:
		if dig_pts.size() >= max_dig:
			break
		if _far_from_all(p, dig_pts, dig_spacing):
			dig_pts.append(p)

	# Enemy spawns across dry sandy beaches & walkable grassy terraces.
	var max_enemy_h := 24.0 if island.island_radius > 110.0 else 9.5
	for _attempt in max_enemies * 18:
		if enemy_pts.size() >= max_enemies:
			break
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(island.island_radius * 0.22, island.island_radius * 0.94)
		var lx := cos(ang) * rad
		var lz := sin(ang) * rad
		var h := island.surface_height(lx, lz)
		if h < 1.3 or h > max_enemy_h:
			continue
		var n := island.surface_normal(lx, lz)
		if n.y < 0.86:
			continue
		if _in_exclusion(lx, lz, exclusions):
			continue
		var cand := Vector3(lx, h, lz)
		if _far_from_all(cand, enemy_pts, 10.0):
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
			# Wave I-2 IslandLandmarks places our 19 m PBR `coastal_sea_arch.glb` (`CoastalSeaArch_Main` &
			# `CoastalSeaArch_Outer`) straddling Gull's Arch's tide bay; only fall back to legacy
			# `ROCK_ARCH_SCENE` if the PBR landmark asset is absent so there are zero overlapping arches.
			if not ResourceLoader.exists("res://assets/generated/landmarks/coastal_sea_arch.glb"):
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

		&"treasure_peak", &"smuggler_cove", &"fort_rock", &"grand_citadel":
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

	# 1b. Walkable Smuggler's Sea Cave Grotto sunk deep into the rising amphitheatre cliff wall.
	if arch == &"smuggler_cove":
		var scale_r := island.island_radius / 60.0
		var grotto_xz := basis * Vector3(0.0, 0.0, 6.0 * scale_r)
		var grotto_y := island.surface_height(grotto_xz.x, grotto_xz.z)
		var grotto_xform := Transform3D(basis, Vector3(grotto_xz.x, grotto_y, grotto_xz.z))
		_build_smugglers_grotto(island, grotto_xform, landing_yaw, prop_body, props_root, foliage_cache, rng)
		var grotto_mid := grotto_xform * Vector3(0.0, 0.0, 5.5)
		var grotto_mouth := grotto_xform * Vector3(0.0, 0.0, -1.8)
		placed.append(Vector3(grotto_mid.x, grotto_mid.z, 11.2))
		keepout_zones.append(Vector3(grotto_mid.x, grotto_mid.z, 11.2))
		placed.append(Vector3(grotto_mouth.x, grotto_mouth.z, 7.8))
		keepout_zones.append(Vector3(grotto_mouth.x, grotto_mouth.z, 7.8))

	# 1c. Glowing Volcanic Magma Caldera & towering rising ash/ember plume on volcanic peaks.
	if arch == &"volcano_crag":
		var scale_r := island.island_radius / 60.0
		var cal_xz := basis * Vector3(0.0, 0.0, 4.0 * scale_r)
		var cal_y := island.surface_height(cal_xz.x, cal_xz.z) + 1.8
		var cal_xform := Transform3D(basis, Vector3(cal_xz.x, cal_y, cal_xz.z))
		_build_volcano_caldera(island, cal_xform, scale_r, rng)
		placed.append(Vector3(cal_xz.x, cal_xz.z, 16.0 * scale_r))
		keepout_zones.append(Vector3(cal_xz.x, cal_xz.z, 16.0 * scale_r))

	# 1d. Duck-typed Wave 24A architecture/jungle props & Wave 24B waterfalls/fumaroles.
	var area_scale := clampf(pow(island.island_radius / 60.0, 1.35), 0.75, 3.6)
	var opt_prop_cache: Dictionary = {}
	_populate_wave24_landmarks_and_architecture(
		island, arch, landing_yaw, area_scale, placed, keepout_zones,
		rng, prop_body, props_root, foliage_cache, opt_prop_cache)

	# 1e. Bespoke Wave I-2 signature 3D landmarks & trail storytelling markers across all 14 islands.
	var landmark_cache: Dictionary = {}
	var trail_markers := IslandTrails.get_trail_marker_spots(island, arch, landing_yaw)
	IslandLandmarks.populate_signature_landmarks(
		island, arch, landing_yaw, placed, keepout_zones, rng,
		prop_body, props_root, foliage_cache, landmark_cache, trail_markers)

	# 2. Dramatic offshore sea stacks (`rock_spire.glb`) for iconic horizon silhouettes.
	var base_spires := 4 if arch == &"sea_stack" else (3 if arch in [&"treasure_peak", &"twin_spires", &"volcano_crag", &"skull_bluff", &"grand_citadel"] else 2)
	var spire_count := clampi(int(round(float(base_spires) * clampf(sqrt(area_scale), 0.9, 2.0))), 2, 7)
	for si in spire_count:
		# Place sea stacks off the side flanks so they never block the landing cove or outpost pier!
		var side_sgn := -1.0 if si % 2 == 0 else 1.0
		var s_ang := side_sgn * rng.randf_range(0.65, 2.35)
		var s_dist := island.island_radius * rng.randf_range(0.95, 1.24)
		var sp := basis * Vector3(sin(s_ang) * s_dist, 0.0, cos(s_ang) * s_dist)
		if _in_exclusion(sp.x, sp.z, placed):
			continue
		var sy := island.surface_height(sp.x, sp.z)
		var sc_val := rng.randf_range(0.90, 1.75) * clampf(island.island_radius / 72.0, 0.85, 1.45)
		_spawn_prop(island, ROCK_SPIRE_SCENE, "SeaStack_%d" % si,
			Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sc_val, sc_val * rng.randf_range(0.95, 1.35), sc_val)),
				Vector3(sp.x, maxf(sy - 1.2, -3.5), sp.z)),
			prop_body, props_root, foliage_cache)
		placed.append(Vector3(sp.x, sp.z, 7.0))
		keepout_zones.append(Vector3(sp.x, sp.z, 5.8))

	# 3. Area-scaled lush tropical palm groves leaning over beaches & highland green terraces.
	var base_palms := 22.0
	if arch in [&"crescent_lagoon", &"palm_atoll", &"treasure_peak", &"grand_citadel"]:
		base_palms = 26.0
	elif arch == &"volcano_crag":
		base_palms = 10.0
	elif arch == &"sea_stack":
		base_palms = 10.0
	elif arch == &"outpost" or arch == &"grand_outpost":
		base_palms = 20.0
	var palm_target := clampi(int(round(base_palms * area_scale)), 8, 84)
	var max_palm_h := 28.0 if island.island_radius > 105.0 else 16.5

	var palms_placed := 0
	var palm_positions: Array[Vector3] = []
	for _attempt in palm_target * 12:
		if palms_placed >= palm_target:
			break
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(island.island_radius * 0.20, island.island_radius * 0.96)
		var px := cos(ang) * rad
		var pz := sin(ang) * rad
		if _in_exclusion(px, pz, placed):
			continue
		if _is_point_on_trail(island, px, pz, 0.92):
			continue
		var h := island.surface_height(px, pz)
		if h < 1.35 or h > max_palm_h:
			continue
		var n := island.surface_normal(px, pz)
		if n.y < 0.79:
			continue
		# Curved palms favour beach verges and lean picturesquely toward the sea!
		var use_curved := (h < 3.8 and rng.randf() < 0.74) or rng.randf() < 0.44
		var scene := PALM_CURVED_SCENE if use_curved else PALM_TALL_SCENE
		var outward_yaw := atan2(px, pz) - PI * 0.5 + rng.randf_range(-0.55, 0.55)
		var sc_p := rng.randf_range(0.86, 1.24)
		var xform := Transform3D(
			Basis(Vector3.UP, outward_yaw) * Basis.from_scale(Vector3(sc_p, sc_p * rng.randf_range(0.92, 1.14), sc_p)),
			Vector3(px, h - 0.16, pz))
		_spawn_prop(island, scene, "Palm_%d" % palms_placed, xform, prop_body, props_root, foliage_cache)
		placed.append(Vector3(px, pz, 4.6))
		palm_positions.append(Vector3(px, h, pz))
		palms_placed += 1

		# Cluster 1-2 companion palms around beach & grass-verge trunks for lush groves.
		if palms_placed < palm_target and h < 14.0 and rng.randf() < 0.68:
			var companions := mini(rng.randi_range(1, 2), palm_target - palms_placed)
			for ci in companions:
				for _c_try in 5:
					var c_ang := ang + rng.randf_range(-1.9, 1.9) + float(ci) * 2.1
					var c_dist := rng.randf_range(2.2, 3.6)
					var cx := px + cos(c_ang) * c_dist
					var cz := pz + sin(c_ang) * c_dist
					if _in_exclusion(cx, cz, keepout_zones):
						continue
					if _is_point_on_trail(island, cx, cz, 0.92):
						continue
					if not _far_from_all(Vector3(cx, 0.0, cz), palm_positions, 1.95):
						continue
					var ch := island.surface_height(cx, cz)
					if ch < 1.35 or ch > max_palm_h:
						continue
					var cn := island.surface_normal(cx, cz)
					if cn.y < 0.79:
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

	# 4. Area-scaled lush tropical bush ferns tucked around palms & highland grassy shelves.
	var base_ferns := 28.0 if arch != &"volcano_crag" else 8.0
	if arch == &"outpost" or arch == &"grand_outpost":
		base_ferns = 24.0
	elif arch == &"sea_stack":
		base_ferns = 12.0
	var fern_target := clampi(int(round(base_ferns * area_scale)), 8, 92)
	var max_fern_h := 30.0 if island.island_radius > 105.0 else 17.5
	var ferns_placed := 0
	var fern_positions: Array[Vector3] = []
	var palm_fern_cap := int(fern_target * 0.55)

	# First tuck 1-2 ferns around palm bases near the beach/grass transition rim.
	for palm_p in palm_positions:
		if ferns_placed >= palm_fern_cap:
			break
		if palm_p.y < 1.65 or palm_p.y > max_fern_h:
			continue
		var tuft_n := rng.randi_range(1, 2)
		for _ti in tuft_n:
			if ferns_placed >= palm_fern_cap:
				break
			var f_ang := rng.randf() * TAU
			var f_dist := rng.randf_range(1.15, 2.55)
			var fx := palm_p.x + cos(f_ang) * f_dist
			var fz := palm_p.z + sin(f_ang) * f_dist
			if _in_exclusion(fx, fz, keepout_zones):
				continue
			if _is_point_on_trail(island, fx, fz, 0.85):
				continue
			if not _far_from_all(Vector3(fx, 0.0, fz), fern_positions, 1.35):
				continue
			var fh := island.surface_height(fx, fz)
			if fh < 1.75 or fh > max_fern_h:
				continue
			var fn := island.surface_normal(fx, fz)
			if fn.y < 0.77:
				continue
			var sc_f := rng.randf_range(0.78, 1.35)
			var slope_sink := 0.20 * clampf((0.86 - fn.y) / 0.30, 0.0, 1.0)
			var xform := Transform3D(
				Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * sc_f),
				Vector3(fx, fh - 0.10 - slope_sink, fz))
			_spawn_prop(island, BUSH_FERN_SCENE, "Fern_%d" % ferns_placed, xform, prop_body, props_root, foliage_cache)
			fern_positions.append(Vector3(fx, fh, fz))
			ferns_placed += 1

	# Fill remaining ferns along beach/grass rims and highland benches.
	for _attempt in fern_target * 10:
		if ferns_placed >= fern_target:
			break
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(island.island_radius * 0.16, island.island_radius * 0.92)
		var fx := cos(ang) * rad
		var fz := sin(ang) * rad
		if _in_exclusion(fx, fz, keepout_zones):
			continue
		if _is_point_on_trail(island, fx, fz, 0.85):
			continue
		if not _far_from_all(Vector3(fx, 0.0, fz), fern_positions, 1.8):
			continue
		var h := island.surface_height(fx, fz)
		if h < 1.85 or h > max_fern_h:
			continue
		var n := island.surface_normal(fx, fz)
		if n.y < 0.77:
			continue
		var sc_f := rng.randf_range(0.80, 1.38)
		var slope_sink := 0.20 * clampf((0.86 - n.y) / 0.30, 0.0, 1.0)
		var xform := Transform3D(
			Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * sc_f),
			Vector3(fx, h - 0.10 - slope_sink, fz))
		_spawn_prop(island, BUSH_FERN_SCENE, "Fern_%d" % ferns_placed, xform, prop_body, props_root, foliage_cache)
		fern_positions.append(Vector3(fx, h, fz))
		ferns_placed += 1

	# 5. Area-scaled faceted coastal boulders anchoring beaches, headlands, terraces, and shallows.
	var rock_target := clampi(int(round(13.0 * area_scale)), 10, 40)
	var max_rock_h := 24.0 if island.island_radius > 105.0 else 11.5
	var rocks_placed := 0
	for _attempt in rock_target * 14:
		if rocks_placed >= rock_target:
			break
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(island.island_radius * 0.30, island.island_radius * 1.05)
		var rx := cos(ang) * rad
		var rz := sin(ang) * rad
		if _in_exclusion(rx, rz, placed):
			continue
		if _is_point_on_trail(island, rx, rz, 1.0):
			continue
		var h := island.surface_height(rx, rz)
		if h < -1.0 or h > max_rock_h:
			continue
		var n := island.surface_normal(rx, rz)
		if n.y < 0.72:
			continue
		var n_wide := island.surface_normal(rx, rz, 2.5)
		if n_wide.y < 0.72:
			continue
		var sc_r := rng.randf_range(0.75, 1.65)
		var min_foot_h := h
		for off: Vector2 in [Vector2(1.3, 0.0), Vector2(-1.3, 0.0), Vector2(0.0, 1.3), Vector2(0.0, -1.3)]:
			var fh := island.surface_height(rx + off.x * sc_r, rz + off.y * sc_r)
			if fh < min_foot_h:
				min_foot_h = fh
		if h - min_foot_h > 1.05 * sc_r:
			continue
		var slope_ny := minf(n.y, n_wide.y)
		var slope_sink := 0.28 * clampf((0.84 - slope_ny) / 0.30, 0.0, 1.0)
		var embed_y := minf(h, min_foot_h + 0.35 * sc_r) - 0.38 * sc_r - slope_sink
		var xform := Transform3D(
			Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sc_r, sc_r * rng.randf_range(0.75, 1.20), sc_r)),
			Vector3(rx, embed_y, rz))
		_spawn_prop(island, ROCK_BOULDER_SCENE, "Boulder_%d" % rocks_placed, xform, prop_body, props_root, foliage_cache)
		placed.append(Vector3(rx, rz, 3.6))
		rocks_placed += 1

	# 6. Washed-up glinting MessageBottle along dry upper golden beaches on tropical islands.
	if not island.is_outpost and BOTTLE_ARCHETYPES.has(arch):
		_spawn_beach_message_bottle(island, landing_yaw, placed, keepout_zones)

	# 7. Interactive bonus SupplyBarrels near beach campfires & cove landings (one-press take-all).
	if not island.is_outpost:
		_spawn_island_supply_barrels(island, arch, landing_yaw, placed, keepout_zones, props_root, rng)


static func _load_optional_prop(filename: String, cache: Dictionary) -> PackedScene:
	if cache.has(filename):
		return cache[filename] as PackedScene
	var path := "res://assets/generated/props/" + filename
	if not ResourceLoader.exists(path):
		cache[filename] = null
		return null
	var scene := load(path) as PackedScene
	cache[filename] = scene
	return scene


static func _spawn_optional_at(island: Island, filename: String, node_name: String,
		local_xz: Vector3, yaw: float, scale_vec: Vector3, embed_y: float,
		keepout_r: float, placed: Array[Vector3], keepout_zones: Array[Vector3],
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		prop_cache: Dictionary, min_h: float = 0.5, max_h: float = 48.0, min_ny: float = 0.72) -> Node3D:
	var scene := _load_optional_prop(filename, prop_cache)
	if scene == null:
		return null
	if _in_exclusion(local_xz.x, local_xz.z, keepout_zones):
		return null
	var h := island.surface_height(local_xz.x, local_xz.z)
	if h < min_h or h > max_h:
		return null
	if island.surface_normal(local_xz.x, local_xz.z).y < min_ny:
		return null
	var xform := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(scale_vec),
		Vector3(local_xz.x, h - embed_y, local_xz.z))
	var node := _spawn_prop(island, scene, node_name, xform, prop_body, props_root, foliage_cache)
	if keepout_r > 0.0:
		placed.append(Vector3(local_xz.x, local_xz.z, keepout_r))
		keepout_zones.append(Vector3(local_xz.x, local_xz.z, keepout_r))
	return node


static func _populate_wave24_landmarks_and_architecture(island: Island, arch: StringName,
		landing_yaw: float, area_scale: float, placed: Array[Vector3],
		keepout_zones: Array[Vector3], rng: RandomNumberGenerator, prop_body: StaticBody3D,
		props_root: Node3D, foliage_cache: Dictionary, prop_cache: Dictionary) -> void:
	var basis := Basis(Vector3.UP, landing_yaw)

	# A. Outposts & Massive Capital Port (harbour warehouses, seawall bastions, watchtowers, banyans & overlooks).
	if arch == &"outpost" or arch == &"grand_outpost":
		var is_grand := arch == &"grand_outpost"
		# Waterfront harbour warehouses flanking the village wharf (clear of tavern/stall/bunting!).
		var wh_specs: Array[Array] = [
			[Vector3(-23.5, 0.0, -16.5), 0.32, Vector3(1.0, 1.0, 1.0)],
		]
		if is_grand:
			wh_specs.append([Vector3(22.0, 0.0, -21.0), -0.42, Vector3(1.12, 1.08, 1.12)])
			wh_specs.append([Vector3(-28.0, 0.0, -34.0), 0.58, Vector3(1.05, 1.05, 1.05)])
		for wi in wh_specs.size():
			var lp := basis * (wh_specs[wi][0] as Vector3)
			_spawn_optional_at(island, "harbour_warehouse.glb", "HarbourWarehouse_%d" % wi,
				lp, landing_yaw + float(wh_specs[wi][1]), wh_specs[wi][2] as Vector3, 0.28, 7.5,
				placed, keepout_zones, prop_body, props_root, foliage_cache, prop_cache, 0.6, 14.0, 0.76)

		# Coastal seawall bastions framing the harbour entrance headlands.
		var sw_specs: Array[Array] = [
			[Vector3(-28.0, 0.0, -32.0), 0.45, Vector3(1.05, 1.0, 1.05)],
			[Vector3(31.0, 0.0, -28.0), -0.45, Vector3(1.05, 1.0, 1.05)],
		]
		if is_grand:
			sw_specs.append([Vector3(-48.0, 0.0, -78.0), 0.35, Vector3(1.25, 1.18, 1.25)])
			sw_specs.append([Vector3(48.0, 0.0, -72.0), -0.35, Vector3(1.25, 1.18, 1.25)])
		for si in sw_specs.size():
			var lp := basis * (sw_specs[si][0] as Vector3)
			_spawn_optional_at(island, "seawall_bastion.glb", "SeawallBastion_%d" % si,
				lp, landing_yaw + float(sw_specs[si][1]), sw_specs[si][2] as Vector3, 0.45, 7.2,
				placed, keepout_zones, prop_body, props_root, foliage_cache, prop_cache, 0.4, 24.0, 0.66)

		# Timber headland watchtowers guarding the harbour approach.
		var wt_specs: Array[Array] = [
			[Vector3(-34.0, 0.0, -10.0), 0.35, Vector3(1.0, 1.0, 1.0)],
		]
		if is_grand:
			wt_specs.append([Vector3(56.0, 0.0, -24.0), -0.38, Vector3(1.12, 1.15, 1.12)])
			wt_specs.append([Vector3(-64.0, 0.0, -54.0), 0.25, Vector3(1.10, 1.12, 1.10)])
		for ti in wt_specs.size():
			var lp := basis * (wt_specs[ti][0] as Vector3)
			_spawn_optional_at(island, "watchtower_wood.glb", "HeadlandWatchtower_%d" % ti,
				lp, landing_yaw + float(wt_specs[ti][1]), wt_specs[ti][2] as Vector3, 0.30, 6.2,
				placed, keepout_zones, prop_body, props_root, foliage_cache, prop_cache, 4.0, 34.0, 0.70)

		# Scenic ancient hilltop ruin pillars crowning Galleon's Reach upper overlooks.
		if is_grand:
			for pi in 3:
				var p_off: Vector3 = [Vector3(-18.0, 0.0, 36.0), Vector3(24.0, 0.0, 38.0), Vector3(54.0, 0.0, 8.0)][pi]
				var lp := basis * p_off
				_spawn_optional_at(island, "ruin_pillar.glb", "OverlookRuinPillar_%d" % pi,
					lp, landing_yaw + rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.95, 1.25), 0.32, 4.2,
					placed, keepout_zones, prop_body, props_root, foliage_cache, prop_cache, 6.0, 34.0, 0.72)

	# B. Sea Fort & Sovereign's Grand Citadel (outer seawall bastions, watchtowers, jungle temples, bridge & waterfall).
	if arch == &"fort_rock" or arch == &"grand_citadel":
		var is_citadel := arch == &"grand_citadel"
		var sw_list: Array[Array] = [
			[Vector3(-34.0, 0.0, -24.0), 0.48, Vector3(1.05, 1.0, 1.05)],
			[Vector3(34.0, 0.0, -24.0), -0.48, Vector3(1.05, 1.0, 1.05)],
		]
		if is_citadel:
			sw_list = [
				[Vector3(-64.0, 0.0, -64.0), 0.42, Vector3(1.28, 1.20, 1.28)],
				[Vector3(64.0, 0.0, -60.0), -0.42, Vector3(1.28, 1.20, 1.28)],
				[Vector3(-36.0, 0.0, -26.0), 0.30, Vector3(1.15, 1.10, 1.15)],
				[Vector3(36.0, 0.0, -24.0), -0.30, Vector3(1.15, 1.10, 1.15)],
			]
		for si in sw_list.size():
			var lp := basis * (sw_list[si][0] as Vector3)
			_spawn_optional_at(island, "seawall_bastion.glb", "CitadelSeawall_%d" % si,
				lp, landing_yaw + float(sw_list[si][1]), sw_list[si][2] as Vector3, 0.45, 7.5,
				placed, keepout_zones, prop_body, props_root, foliage_cache, prop_cache, 2.0, 32.0, 0.66)

		var wt_list: Array[Array] = [
			[Vector3(-28.0, 0.0, -6.0), 0.35, Vector3(1.0, 1.0, 1.0)],
			[Vector3(28.0, 0.0, -6.0), -0.35, Vector3(1.0, 1.0, 1.0)],
		]
		if is_citadel:
			wt_list = [
				[Vector3(-68.0, 0.0, -56.0), 0.35, Vector3(1.15, 1.18, 1.15)],
				[Vector3(68.0, 0.0, -54.0), -0.35, Vector3(1.15, 1.18, 1.15)],
				[Vector3(-38.0, 0.0, 26.0), 0.25, Vector3(1.10, 1.12, 1.10)],
			]
		for ti in wt_list.size():
			var lp := basis * (wt_list[ti][0] as Vector3)
			_spawn_optional_at(island, "watchtower_wood.glb", "FortWatchtower_%d" % ti,
				lp, landing_yaw + float(wt_list[ti][1]), wt_list[ti][2] as Vector3, 0.30, 6.2,
				placed, keepout_zones, prop_body, props_root, foliage_cache, prop_cache, 4.0, 36.0, 0.70)

		if is_citadel:
			# Ancient jungle temple arches, pillars & timber bridge across the highland terraces!
			for ai in 2:
				var a_off: Vector3 = [Vector3(-72.0, 0.0, 12.0), Vector3(72.0, 0.0, 12.0)][ai]
				_spawn_optional_at(island, "ruin_arch.glb", "CitadelRuinArch_%d" % ai,
					basis * a_off, landing_yaw + (0.35 if ai == 0 else -0.35), Vector3(1.22, 1.22, 1.22),
					0.35, 7.5, placed, keepout_zones, prop_body, props_root, foliage_cache, prop_cache, 10.0, 38.0, 0.72)
			for pi in 4:
				var p_off: Vector3 = [
					Vector3(-82.0, 0.0, 24.0), Vector3(-62.0, 0.0, 26.0),
					Vector3(64.0, 0.0, 24.0), Vector3(84.0, 0.0, 4.0),
				][pi]
				_spawn_optional_at(island, "ruin_pillar.glb", "CitadelRuinPillar_%d" % pi,
					basis * p_off, landing_yaw + rng.randf() * TAU, Vector3.ONE * rng.randf_range(1.0, 1.32),
					0.32, 4.2, placed, keepout_zones, prop_body, props_root, foliage_cache, prop_cache, 8.0, 38.0, 0.70)
			_spawn_optional_at(island, "timber_bridge.glb", "CitadelTimberBridge",
				basis * Vector3(-42.0, 0.0, -14.0), landing_yaw + 0.65, Vector3(1.15, 1.05, 1.15),
				0.24, 6.8, placed, keepout_zones, prop_body, props_root, foliage_cache, prop_cache, 4.0, 28.0, 0.72)
			# Cascading highland waterfall plunging off Sovereign's Bastion eastern temple cliff!
			var wf_top := basis * Vector3(62.0, 0.0, -10.0)
			var wf_bot := basis * Vector3(54.0, 0.0, -28.0)
			var top_y := island.surface_height(wf_top.x, wf_top.z)
			var bot_y := maxf(0.2, island.surface_height(wf_bot.x, wf_bot.z))
			var drop_h := clampf(top_y - bot_y, 12.0, 34.0)
			var run_c := Vector2(wf_bot.x - wf_top.x, wf_bot.z - wf_top.z)
			var yaw_c := atan2(-run_c.x, -run_c.y) if run_c.length_squared() > 0.01 else (landing_yaw - 0.42)
			var reach_c := clampf(run_c.length() * 0.72, 4.8, 16.5)
			_try_spawn_waterfall(island, "CitadelWaterfall", Vector3(wf_top.x, top_y - 0.35, wf_top.z),
				yaw_c, drop_h, 5.4, reach_c)

	# C. Lush Canyon (`twin_spires`), Highland Ruins (`skull_bluff`, `smuggler_cove`).
	if arch == &"twin_spires":
		var s_r := island.island_radius / 60.0
		_spawn_optional_at(island, "timber_bridge.glb", "CanyonTimberBridge",
			basis * Vector3(0.0, 0.0, -6.0 * s_r), landing_yaw, Vector3(1.18, 1.08, 1.18),
			0.24, 6.5, placed, keepout_zones, prop_body, props_root, foliage_cache, prop_cache, 2.0, 24.0, 0.72)
		for ai in 2:
			var a_off: Vector3 = [Vector3(-6.0 * s_r, 0.0, 6.0 * s_r), Vector3(7.0 * s_r, 0.0, -16.0 * s_r)][ai]
			_spawn_optional_at(island, "ruin_arch.glb", "CanyonRuinArch_%d" % ai,
				basis * a_off, landing_yaw + (0.25 if ai == 0 else -0.35), Vector3(1.15, 1.15, 1.15),
				0.32, 6.5, placed, keepout_zones, prop_body, props_root, foliage_cache, prop_cache, 2.0, 26.0, 0.72)
		for pi in 3:
			var p_off: Vector3 = [
				Vector3(-12.0 * s_r, 0.0, -12.0 * s_r),
				Vector3(12.0 * s_r, 0.0, 2.0 * s_r),
				Vector3(-4.0 * s_r, 0.0, 14.0 * s_r),
			][pi]
			_spawn_optional_at(island, "ruin_pillar.glb", "CanyonRuinPillar_%d" % pi,
				basis * p_off, landing_yaw + rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.95, 1.25),
				0.30, 4.0, placed, keepout_zones, prop_body, props_root, foliage_cache, prop_cache, 2.0, 28.0, 0.70)
		# Thundering Emerald Spire waterfall plunging down the canyon headwall cliff!
		var wf_top := basis * Vector3(0.0, 0.0, 20.0 * s_r)
		var wf_bot := basis * Vector3(0.0, 0.0, 8.0 * s_r)
		var top_y := island.surface_height(wf_top.x, wf_top.z)
		var bot_y := maxf(1.5, island.surface_height(wf_bot.x, wf_bot.z))
		var drop_h := clampf(top_y - bot_y, 14.0, 38.0)
		var run_e := Vector2(wf_bot.x - wf_top.x, wf_bot.z - wf_top.z)
		var yaw_e := atan2(-run_e.x, -run_e.y) if run_e.length_squared() > 0.01 else landing_yaw
		var reach_e := clampf(run_e.length() * 0.74, 5.2, 18.0)
		_try_spawn_waterfall(island, "EmeraldCanyonWaterfall", Vector3(wf_top.x, top_y - 0.35, wf_top.z),
			yaw_e, drop_h, 5.2, reach_e)
	elif arch == &"skull_bluff" or arch == &"smuggler_cove":
		var s_r := island.island_radius / 60.0
		_spawn_optional_at(island, "ruin_arch.glb", "HighlandRuinArch",
			basis * Vector3(-24.0 * s_r, 0.0, -10.0 * s_r), landing_yaw + 0.52, Vector3(1.12, 1.12, 1.12),
			0.32, 6.5, placed, keepout_zones, prop_body, props_root, foliage_cache, prop_cache, 3.0, 28.0, 0.72)
		for pi in 2:
			var p_off: Vector3 = [Vector3(24.0 * s_r, 0.0, -12.0 * s_r), Vector3(-18.0 * s_r, 0.0, -22.0 * s_r)][pi]
			_spawn_optional_at(island, "ruin_pillar.glb", "HighlandRuinPillar_%d" % pi,
				basis * p_off, landing_yaw + rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.95, 1.22),
				0.30, 4.0, placed, keepout_zones, prop_body, props_root, foliage_cache, prop_cache, 2.5, 28.0, 0.70)
		if arch == &"skull_bluff":
			_spawn_optional_at(island, "timber_bridge.glb", "BluffTimberBridge",
				basis * Vector3(0.0, 0.0, -26.0 * s_r), landing_yaw + 0.18, Vector3(1.08, 1.0, 1.08),
				0.24, 6.2, placed, keepout_zones, prop_body, props_root, foliage_cache, prop_cache, 2.0, 22.0, 0.74)

	# D. Lush `jungle_banyan.glb` groves crowning upper green terraces & jungles!
	var banyan_scene := _load_optional_prop("jungle_banyan.glb", prop_cache)
	if banyan_scene != null and arch != &"volcano_crag" and arch != &"sea_stack" and arch != &"wreck_shoal":
		var banyan_base := 5.0 if arch in [&"grand_citadel", &"twin_spires", &"skull_bluff", &"grand_outpost"] else 3.0
		var banyan_target := clampi(int(round(banyan_base * clampf(area_scale, 0.8, 3.2))), 2, 16)
		var banyans_placed := 0
		for _bi in banyan_target * 14:
			if banyans_placed >= banyan_target:
				break
			var ang := rng.randf() * TAU
			var rad := rng.randf_range(island.island_radius * 0.18, island.island_radius * 0.82)
			var bx := cos(ang) * rad
			var bz := sin(ang) * rad
			if _in_exclusion(bx, bz, placed):
				continue
			var bh := island.surface_height(bx, bz)
			if bh < 4.5 or bh > 32.0:
				continue
			if island.surface_normal(bx, bz).y < 0.80:
				continue
			var b_sc := rng.randf_range(0.90, 1.35)
			var b_xf := Transform3D(
				Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(b_sc, b_sc * rng.randf_range(0.92, 1.12), b_sc)),
				Vector3(bx, bh - 0.28, bz))
			_spawn_prop(island, banyan_scene, "JungleBanyan_%d" % banyans_placed, b_xf, prop_body, props_root, foliage_cache)
			placed.append(Vector3(bx, bz, 8.2))
			keepout_zones.append(Vector3(bx, bz, 6.4))
			banyans_placed += 1

	# E. Massive Volcano active `VolcanicFumarole` steam vents around basalt terraces & ash cove!
	if arch == &"volcano_crag":
		_try_spawn_fumaroles(island, landing_yaw, rng, placed, keepout_zones)


static func _try_spawn_waterfall(island: Island, node_name: String, top_pos: Vector3,
		yaw: float, drop_height: float, width: float, out_reach: float = 0.0) -> Node3D:
	const WF_PATH := "res://src/world/island_waterfall.gd"
	if not ResourceLoader.exists(WF_PATH):
		return null
	var wf_script := load(WF_PATH) as GDScript
	if wf_script == null:
		return null
	var wf := wf_script.new() as Node3D
	if wf == null:
		return null
	wf.name = node_name
	wf.position = top_pos
	wf.rotation = Vector3(0.0, yaw, 0.0)
	for h_key: String in ["height_m", "drop_height", "fall_height", "waterfall_height", "cliff_height", "height"]:
		if h_key in wf:
			wf.set(StringName(h_key), drop_height)
	for w_key: String in ["width_m", "width", "fall_width", "waterfall_width", "stream_width"]:
		if w_key in wf:
			wf.set(StringName(w_key), width)
	if out_reach > 0.1 and "out_reach_m" in wf:
		wf.set(&"out_reach_m", out_reach)
	island.add_child(wf)
	return wf


static func _try_spawn_fumaroles(island: Island, landing_yaw: float, rng: RandomNumberGenerator,
		placed: Array[Vector3], keepout_zones: Array[Vector3]) -> void:
	const FUM_PATH := "res://src/world/island_fumarole.gd"
	if not ResourceLoader.exists(FUM_PATH):
		return
	var fum_script := load(FUM_PATH) as GDScript
	if fum_script == null:
		return
	var basis := Basis(Vector3.UP, landing_yaw)
	var scale_r := island.island_radius / 60.0
	var candidate_uvs: Array[Vector2] = [
		Vector2(-26.0 * scale_r, -24.0 * scale_r),
		Vector2(26.0 * scale_r, -22.0 * scale_r),
		Vector2(-14.0 * scale_r, -34.0 * scale_r),
		Vector2(16.0 * scale_r, -32.0 * scale_r),
		Vector2(-34.0 * scale_r, 8.0 * scale_r),
		Vector2(34.0 * scale_r, 10.0 * scale_r),
	]
	var spawned := 0
	for uv in candidate_uvs:
		if spawned >= 4:
			break
		var lp := basis * Vector3(uv.x, 0.0, uv.y)
		if _in_exclusion(lp.x, lp.z, keepout_zones):
			continue
		var h := island.surface_height(lp.x, lp.z)
		if h < 2.0 or h > 56.0:
			continue
		if island.surface_normal(lp.x, lp.z).y < 0.70:
			continue
		var fum := fum_script.new() as Node3D
		if fum == null:
			continue
		fum.name = "VolcanicFumarole_%d" % spawned
		fum.position = Vector3(lp.x, h, lp.z)
		fum.rotation = Vector3(0.0, rng.randf() * TAU, 0.0)
		if "seed_val" in fum:
			fum.set(&"seed_val", rng.randi())
		island.add_child(fum)
		placed.append(Vector3(lp.x, lp.z, 5.5))
		keepout_zones.append(Vector3(lp.x, lp.z, 5.5))
		spawned += 1


static func _spawn_beach_message_bottle(island: Island, landing_yaw: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3]) -> MessageBottle:
	var basis := Basis(Vector3.UP, landing_yaw)
	var chosen := Vector3.ZERO
	var found := false

	# Pass 1: Prefer dry upper golden shoreline flanking the welcoming landing cove.
	var passes: Array[Array] = [
		[0.65, 2.35, 0.88, 1.35, 21],
		[0.45, 3.00, 0.84, PI, 36],
	]
	for pass_cfg: Array in passes:
		if found:
			break
		var h_min: float = float(pass_cfg[0])
		var h_max: float = float(pass_cfg[1])
		var n_min: float = float(pass_cfg[2])
		var half_arc: float = float(pass_cfg[3])
		var steps_a: int = int(pass_cfg[4])
		for ring_frac: float in [0.92, 0.88, 0.96, 0.82, 0.76, 0.68, 0.60]:
			if found:
				break
			var r_cand := island.island_radius * ring_frac
			for ai in range(steps_a):
				# Sweep symmetrically outward from the seaward cove flanks so it sits beside—not blocking—landing.
				var u := 0.0 if steps_a <= 1 else (float(ai) / float(steps_a - 1)) * 2.0 - 1.0
				var ang := -PI * 0.5 + u * half_arc
				var lp := basis * Vector3(cos(ang) * r_cand, 0.0, sin(ang) * r_cand)
				if _in_exclusion(lp.x, lp.z, keepout_zones) or _in_exclusion(lp.x, lp.z, placed):
					continue
				if not _far_from_all(Vector3(lp.x, 0.0, lp.z), island.dig_points, 4.5):
					continue
				var h := island.surface_height(lp.x, lp.z)
				if h < h_min or h > h_max:
					continue
				if island.surface_normal(lp.x, lp.z).y < n_min:
					continue
				chosen = Vector3(lp.x, h, lp.z)
				found = true
				break

	if not found:
		return null

	var clue_idx := absi(island.island_id.hash()) % BOTTLE_CLUE_TARGETS.size()
	var clue: Dictionary = BOTTLE_CLUE_TARGETS[clue_idx]
	if String(clue["target_id"]) == island.island_id:
		clue_idx = (clue_idx + 1) % BOTTLE_CLUE_TARGETS.size()
		clue = BOTTLE_CLUE_TARGETS[clue_idx]

	var bottle := MessageBottle.new()
	bottle.name = "BeachMessageBottle"
	bottle.clue_id = StringName("bottle_%s" % island.island_id)
	bottle.target_island_id = String(clue["target_id"])
	bottle.target_island_name = String(clue["target_name"])
	bottle.treasure_id = StringName(clue["treasure_id"])
	bottle.clue_text = String(clue["clue_text"])
	var seaward_yaw := atan2(chosen.x, chosen.z) + 0.42
	bottle.position = chosen
	bottle.rotation = Vector3(0.0, seaward_yaw, 0.0)
	island.add_child(bottle)
	placed.append(Vector3(chosen.x, chosen.z, 2.5))
	keepout_zones.append(Vector3(chosen.x, chosen.z, 2.5))
	return bottle


static func _spawn_island_supply_barrels(
	island: Island,
	arch: StringName,
	landing_yaw: float,
	placed: Array[Vector3],
	keepout_zones: Array[Vector3],
	props_root: Node3D,
	rng: RandomNumberGenerator
) -> Array[Node3D]:
	var spawned: Array[Node3D] = []
	var want_count := 2 if arch in [&"treasure_peak", &"smuggler_cove", &"fort_rock", &"wreck_shoal", &"crescent_lagoon"] else 1
	var basis := Basis(Vector3.UP, landing_yaw)

	# Pass 1: Place a bonus SupplyBarrel near the island's BeachCampfire clearing (just outside its keepout ring).
	var campfire := props_root.get_node_or_null(^"BeachCampfire") as Node3D
	if campfire != null and spawned.size() < want_count:
		var camp_p := campfire.position
		for rad: float in [5.2, 5.9, 6.6]:
			if spawned.size() >= 1:
				break
			for ai in 12:
				var ang := float(ai) / 12.0 * TAU + 0.35
				var cx := camp_p.x + cos(ang) * rad
				var cz := camp_p.z + sin(ang) * rad
				if _in_exclusion(cx, cz, keepout_zones) or _in_exclusion(cx, cz, placed):
					continue
				if not _far_from_all(Vector3(cx, 0.0, cz), island.dig_points, 3.2):
					continue
				var h := island.surface_height(cx, cz)
				if h < 0.55 or h > 9.0 or island.surface_normal(cx, cz).y < 0.84:
					continue
				var barrel := _create_island_supply_barrel(island, spawned.size(), Vector3(cx, h, cz), rng, placed, keepout_zones)
				spawned.append(barrel)
				break

	# Pass 2: Place remaining bonus SupplyBarrel(s) along welcoming sandy cove landings & beach flanks.
	var sweeps: Array[Array] = [
		[0.55, 3.60, 0.86, 1.35, 19],
		[0.45, 5.20, 0.80, PI, 28],
	]
	for sweep_cfg: Array in sweeps:
		if spawned.size() >= want_count:
			break
		var h_min: float = float(sweep_cfg[0])
		var h_max: float = float(sweep_cfg[1])
		var n_min: float = float(sweep_cfg[2])
		var half_arc: float = float(sweep_cfg[3])
		var steps_a: int = int(sweep_cfg[4])
		for ring_frac: float in [0.92, 0.86, 0.96, 0.78, 0.70, 0.60]:
			if spawned.size() >= want_count:
				break
			var r_cand := island.island_radius * ring_frac
			for ai in range(steps_a):
				if spawned.size() >= want_count:
					break
				var u := 0.0 if steps_a <= 1 else (float(ai) / float(steps_a - 1)) * 2.0 - 1.0
				var ang := -PI * 0.5 + u * half_arc
				var lp := basis * Vector3(cos(ang) * r_cand, 0.0, sin(ang) * r_cand)
				if _in_exclusion(lp.x, lp.z, keepout_zones) or _in_exclusion(lp.x, lp.z, placed):
					continue
				if not _far_from_all(Vector3(lp.x, 0.0, lp.z), island.dig_points, 3.4):
					continue
				var h := island.surface_height(lp.x, lp.z)
				if h < h_min or h > h_max or island.surface_normal(lp.x, lp.z).y < n_min:
					continue
				var barrel := _create_island_supply_barrel(island, spawned.size(), Vector3(lp.x, h, lp.z), rng, placed, keepout_zones)
				spawned.append(barrel)
	return spawned


static func _create_island_supply_barrel(
	island: Island,
	idx: int,
	pos: Vector3,
	rng: RandomNumberGenerator,
	placed: Array[Vector3],
	keepout_zones: Array[Vector3]
) -> Node3D:
	var barrel := SUPPLY_BARREL_SCRIPT.new() as Node3D
	barrel.name = "SupplyBarrel_%d" % idx
	barrel.position = pos
	barrel.rotation = Vector3(0.0, rng.randf() * TAU, 0.0)
	island.add_child(barrel)
	placed.append(Vector3(pos.x, pos.z, 2.0))
	keepout_zones.append(Vector3(pos.x, pos.z, 2.0))
	return barrel


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

	# Interactive tripod cookpot suspended over the beach campfire embers so
	# captains can sear fresh island crab claws and fish right on shore!
	var stove := CookingStove.new()
	stove.name = "CampfireCookingStove"
	stove.set(&"build_hearth", false)
	stove.set(&"build_campfire_tripod", true)
	stove.position = Vector3.ZERO
	fire.add_child(stove)
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
			if src_mat.resource_name.begins_with("mat_foliage"):
				var tex: Texture2D = null
				var nrm_tex: Texture2D = null
				var rgh_tex: Texture2D = null
				if src_mat is StandardMaterial3D:
					var sm := src_mat as StandardMaterial3D
					tex = sm.albedo_texture
					nrm_tex = sm.normal_texture
					rgh_tex = sm.roughness_texture
				var cache_key := (tex.resource_path if tex != null else "default_foliage") \
					+ "|" + (nrm_tex.resource_path if nrm_tex != null else "")
				var wind_mat: ShaderMaterial = foliage_cache.get(cache_key)
				if wind_mat == null:
					wind_mat = ShaderMaterial.new()
					wind_mat.shader = FOLIAGE_SHADER
					if tex != null:
						wind_mat.set_shader_parameter(&"albedo_tex", tex)
						wind_mat.set_shader_parameter(&"use_albedo_tex", 1.0)
					else:
						wind_mat.set_shader_parameter(&"use_albedo_tex", 0.0)
					if nrm_tex != null:
						wind_mat.set_shader_parameter(&"normal_tex", nrm_tex)
						wind_mat.set_shader_parameter(&"use_normal_tex", 1.0)
					else:
						wind_mat.set_shader_parameter(&"use_normal_tex", 0.0)
					if rgh_tex != null:
						wind_mat.set_shader_parameter(&"roughness_tex", rgh_tex)
						wind_mat.set_shader_parameter(&"use_roughness_tex", 1.0)
					else:
						wind_mat.set_shader_parameter(&"use_roughness_tex", 0.0)
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


## Returns true if local island point `(local_x, local_z)` falls inside
## `trail_half_width * clearance_scale` of any painted trail segment in `trail_polylines`.
static func _is_point_on_trail(island: Island, local_x: float, local_z: float,
		clearance_scale: float = 0.88) -> bool:
	if island == null or not island.has_meta(&"trail_polylines"):
		return false
	var raw_trails: Variant = island.get_meta(&"trail_polylines", [])
	if not (raw_trails is Array):
		return false
	var trail_hw := maxf(0.0, float(island.get_meta(&"trail_half_width", 3.0)))
	var clear_r := trail_hw * clearance_scale
	if clear_r <= 0.001:
		return false
	var clear_r_sq := clear_r * clear_r
	var yaw := float(island.get_meta(&"landing_yaw", 0.0))
	var cos_y := cos(yaw)
	var sin_y := sin(yaw)
	var u := local_x * cos_y - local_z * sin_y
	var v := local_x * sin_y + local_z * cos_y

	var min_dist_sq := INF
	for poly_var: Variant in (raw_trails as Array):
		var pts := PackedVector2Array()
		if poly_var is PackedVector2Array:
			pts = poly_var as PackedVector2Array
		elif poly_var is Array:
			for p_var: Variant in (poly_var as Array):
				if p_var is Vector2:
					pts.append(p_var as Vector2)
		var count := pts.size()
		if count < 2:
			continue
		for i in range(count - 1):
			var a := pts[i]
			var b := pts[i + 1]
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
				if min_dist_sq < clear_r_sq:
					return true
	return min_dist_sq < clear_r_sq


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
		&"grand_citadel":
			return 182.0
		&"volcano_crag":
			return 176.0
		&"grand_outpost":
			return 166.0
		&"twin_spires":
			return 138.0
		&"crescent_lagoon":
			return 134.0
		&"skull_bluff":
			return 124.0
		&"smuggler_cove":
			return 96.0
		&"fort_rock":
			return 92.0
		&"outpost", &"sea_arch":
			return 82.0
		&"palm_atoll":
			return 64.0
		&"treasure_peak":
			return 54.0
		&"wreck_shoal":
			return 46.0
		&"sea_stack":
			return 38.0
		_:
			return 68.0


static func _default_peak(arch: StringName) -> float:
	match arch:
		&"volcano_crag":
			return 132.0
		&"twin_spires":
			return 98.0
		&"grand_citadel":
			return 96.0
		&"skull_bluff":
			return 78.0
		&"grand_outpost":
			return 76.0
		&"treasure_peak":
			return 66.0
		&"smuggler_cove":
			return 64.0
		&"sea_arch":
			return 58.0
		&"outpost", &"sea_stack":
			return 54.0
		&"fort_rock":
			return 52.0
		&"crescent_lagoon":
			return 44.0
		&"wreck_shoal":
			return 36.0
		&"palm_atoll":
			return 32.0
		_:
			return 48.0


static func _default_kind(arch: StringName) -> StringName:
	match arch:
		&"outpost", &"grand_outpost":
			return &"outpost"
		&"fort_rock", &"grand_citadel":
			return &"fort"
		&"wreck_shoal":
			return &"shipwreck"
		&"volcano_crag", &"twin_spires", &"sea_stack":
			return &"landmark"
		_:
			return &"treasure_island"


static func _default_landmarks(arch: StringName) -> Array[String]:
	match arch:
		&"outpost":
			return ["Harbour Pier", "Beacon Tower", "Tavern Porch"]
		&"grand_outpost":
			return ["Grand Wharf", "Headland Bastions", "Sovereign Beacon"]
		&"treasure_peak":
			return ["Twin Peaks", "Golden Cove", "Split Palm"]
		&"twin_spires":
			return ["North Needle", "Waterfall Saddle", "Emerald Bluff"]
		&"crescent_lagoon":
			return ["Turquoise Lagoon", "Coral Horn", "Sunlit Spit"]
		&"sea_arch":
			return ["White Sea Arch", "Tide Bay", "Gull Cliff"]
		&"fort_rock":
			return ["Stone Bastion", "Watch Mesa", "Landing Ramp"]
		&"grand_citadel":
			return ["Sovereign Citadel", "Temple Terraces", "Cascade Falls"]
		&"wreck_shoal":
			return ["Broken Bow", "Barnacle Mast", "Shoal Bar"]
		&"volcano_crag":
			return ["Basalt Rim", "Caldera Spire", "Fumarole Terraces"]
		&"palm_atoll":
			return ["Palm Ring", "Shallow Pool", "Coral Monolith"]
		&"skull_bluff":
			return ["Skull Brow", "High Crag", "South Beach"]
		&"smuggler_cove":
			return ["Hidden Pocket", "Cliff Gate", "Smuggler's Fire"]
		&"sea_stack":
			return ["Siren's Fang", "Tide Chasm", "Coral Shelf"]
		_:
			return ["Coastal Rock", "Sandy Cove", "Lone Palm"]


static func _mount_citadel_fort_vault(bastion: FortBastion) -> Node3D:
	var existing := bastion.get_node_or_null(^"FortVault") as Node3D
	if existing != null:
		return existing
	var vault := FORT_VAULT_SCRIPT.new() as Node3D
	if vault == null:
		return null
	vault.name = "FortVault"
	vault.position = Vector3(0.0, 0.06, -11.4)
	bastion.add_child(vault)
	for bat in bastion.get_batteries():
		if not bat.has_meta(&"fort_vault_wired"):
			bat.set_meta(&"fort_vault_wired", true)
			bat.battery_destroyed.connect(func(_b: FortBattery) -> void:
				if not is_instance_valid(bastion) or not is_instance_valid(vault):
					return
				for other in bastion.get_batteries():
					if not other.destroyed:
						return
				if vault.has_method(&"set_siege_cleared"):
					vault.call(&"set_siege_cleared", true)
			)
	return vault


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
	stone_st.set_smooth_group(-1)
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
	stone_mat.vertex_color_is_srgb = true
	stone_mat.uv1_triplanar = true
	stone_mat.uv1_world_triplanar = false
	stone_mat.uv1_scale = Vector3(0.22, 0.22, 0.22)
	stone_mat.albedo_texture = TEX_CLIFF_ALB
	stone_mat.albedo_color = Color(1.20, 1.18, 1.14)
	stone_mat.normal_enabled = true
	stone_mat.normal_scale = 0.72
	stone_mat.normal_texture = TEX_CLIFF_NRM
	stone_mat.roughness = 0.90
	stone_mat.metallic = 0.0
	stone_mat.metallic_specular = 0.24
	stone_mi.material_override = stone_mat
	bastion.add_child(stone_mi)

	wood_st.generate_normals()
	var wood_mi := MeshInstance3D.new()
	wood_mi.name = "WatchtowerGantry"
	wood_mi.mesh = wood_st.commit()
	var wood_mat := StandardMaterial3D.new()
	wood_mat.vertex_color_use_as_albedo = true
	wood_mat.vertex_color_is_srgb = true
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
	iron_mat.vertex_color_is_srgb = true
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

	# Grounded stepped stone ramp threshold apron with buried masonry skirt (y = -1.65 m)
	# so outer left/right corners never hover over sloped approaches on any fort island.
	var thresh_skirt_pos := bay_xf * Vector3(0.0, -1.65, -0.65)
	_bastion_add_tapered_prism(stone_st, thresh_skirt_pos,
		Vector2(2.62, 1.72), Vector2(2.26, 1.36), 1.62, bay_yaw_arch,
		COL_FORT_STONE_MID, COL_FORT_STONE_SHADOW, COL_FORT_STONE_MOSS.lerp(COL_FORT_STONE_SHADOW, 0.40))
	var thresh_cap_pos := bay_xf * Vector3(0.0, -0.05, -0.65)
	_bastion_add_tapered_prism(stone_st, thresh_cap_pos,
		Vector2(2.28, 1.38), Vector2(2.15, 1.25), 0.12, bay_yaw_arch,
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
	var block_hash := sin(xf.origin.x * 12.9898 + xf.origin.y * 78.233 + xf.origin.z * 37.719) * 43758.5453
	var block_jit := (block_hash - floorf(block_hash)) * 2.0 - 1.0
	var tone_mul := 1.0 + block_jit * 0.075
	var warm_r := 1.0 + block_jit * 0.03
	var warm_b := 1.0 - block_jit * 0.03
	var j_top := Color(
		clampf(col_top.r * tone_mul * warm_r, 0.0, 1.0),
		clampf(col_top.g * tone_mul, 0.0, 1.0),
		clampf(col_top.b * tone_mul * warm_b, 0.0, 1.0)
	)
	var j_mid := Color(
		clampf(col_mid.r * tone_mul, 0.0, 1.0),
		clampf(col_mid.g * tone_mul, 0.0, 1.0),
		clampf(col_mid.b * tone_mul, 0.0, 1.0)
	)
	var j_bot := Color(
		clampf(col_bot.r * (1.0 + block_jit * 0.045), 0.0, 1.0),
		clampf(col_bot.g * (1.0 + block_jit * 0.045), 0.0, 1.0),
		clampf(col_bot.b * (1.0 + block_jit * 0.045), 0.0, 1.0)
	)
	# Top cap (+Y outward) & bottom cap (-Y outward).
	_bastion_quad(st, t[0], t[1], t[2], t[3], j_top, j_top, j_top, j_top)
	_bastion_quad(st, b[0], b[3], b[2], b[1], j_bot, j_bot, j_bot, j_bot)
	for i in 4:
		var j := (i + 1) % 4
		var face_shade := 0.30 + 0.16 * float(i % 2) + 0.06 * float(i >= 2)
		var c_up := j_top.lerp(j_mid, face_shade)
		var c_lo := j_bot.lerp(j_mid, 0.22 + 0.08 * float(i % 2))
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


# ============================================================ smuggler's sea cave grotto

## Build the walkable faceted-limestone Smuggler's Sea Cave Grotto (`SmugglersGrotto`)
## tucked into the amphitheatre cliff foot of `&"smuggler_cove"`, with hanging stalactites,
## rain shelter Area3D (`GrottoShelter`), 2 warm flickering brass smuggler lanterns,
## a raised timber Contraband Stash Table, and tucked rum barrels & crates.
static func _build_smugglers_grotto(island: Island, grotto_xform: Transform3D,
		landing_yaw: float, prop_body: StaticBody3D, props_root: Node3D,
		foliage_cache: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var grotto := Node3D.new()
	grotto.name = "SmugglersGrotto"
	grotto.transform = grotto_xform
	island.add_child(grotto)

	# 1. Sculpted organic faceted ochre-limestone cavern vault, craggy brow, flanking buttresses & stalactites.
	var vault_mi := MeshInstance3D.new()
	vault_mi.name = "GrottoVaultMesh"
	vault_mi.mesh = _build_grotto_vault_mesh(rng)
	var vault_mat := StandardMaterial3D.new()
	vault_mat.vertex_color_use_as_albedo = true
	vault_mat.vertex_color_is_srgb = true
	vault_mat.uv1_triplanar = true
	vault_mat.uv1_world_triplanar = false
	vault_mat.uv1_scale = Vector3(0.24, 0.24, 0.24)
	vault_mat.albedo_texture = TEX_CLIFF_ALB
	vault_mat.albedo_color = Color(1.18, 1.15, 1.10)
	vault_mat.normal_enabled = true
	vault_mat.normal_scale = 0.72
	vault_mat.normal_texture = TEX_CLIFF_NRM
	vault_mat.roughness = 0.92
	vault_mat.metallic = 0.0
	vault_mat.metallic_specular = 0.24
	vault_mi.material_override = vault_mat
	grotto.add_child(vault_mi)

	# 2. Left/right/rear BoxShape3D colliders ONLY (entire mouth & central floor stay 100% walkable!).
	_add_grotto_box_collider(prop_body, grotto_xform, "WallL",
		Transform3D(Basis.IDENTITY, Vector3(-3.95, 2.5, 5.5)), Vector3(1.5, 5.4, 11.4))
	_add_grotto_box_collider(prop_body, grotto_xform, "WallR",
		Transform3D(Basis.IDENTITY, Vector3(3.95, 2.5, 5.5)), Vector3(1.5, 5.4, 11.4))
	_add_grotto_box_collider(prop_body, grotto_xform, "WallRear",
		Transform3D(Basis.IDENTITY, Vector3(0.0, 2.5, 11.55)), Vector3(7.6, 5.4, 1.5))

	# 3. Rain Shelter Area3D in group `shelter` enclosing the walkable cavern interior.
	var shelter := Area3D.new()
	shelter.name = "GrottoShelter"
	shelter.collision_layer = 1 << 6
	shelter.collision_mask = 0
	shelter.monitoring = false
	shelter.monitorable = false
	shelter.add_to_group(&"shelter")
	shelter.position = Vector3(0.0, 2.55, 5.6)
	var shelter_cs := CollisionShape3D.new()
	shelter_cs.name = "ShelterBox"
	var shelter_box := BoxShape3D.new()
	shelter_box.size = Vector3(6.8, 5.1, 10.8)
	shelter_cs.shape = shelter_box
	shelter.add_child(shelter_cs)
	grotto.add_child(shelter)

	# 4. Raised timber Contraband Stash Table near the rear alcove + iron/brass lantern hardware.
	var table_local_xz := Vector3(0.0, 0.0, 8.75)
	var table_island := grotto_xform * table_local_xz
	var table_floor_y := island.surface_height(table_island.x, table_island.z) - grotto_xform.origin.y
	var table_origin := Vector3(table_local_xz.x, table_floor_y, table_local_xz.z)

	var wood_st := SurfaceTool.new()
	wood_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	wood_st.set_smooth_group(-1)
	var metal_st := SurfaceTool.new()
	metal_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	metal_st.set_smooth_group(-1)
	_build_contraband_stash_table(wood_st, metal_st, table_origin)

	_add_grotto_box_collider(prop_body, grotto_xform, "StashTable",
		Transform3D(Basis.IDENTITY, table_origin + Vector3(0.0, 0.44, 0.0)), Vector3(2.34, 0.88, 1.06))

	# 5. Two hanging warm glowing smuggler brass lanterns inside the cave arch.
	var lantern_specs: Array[Array] = [
		[Vector3(2.05, 3.12, 2.35), 4.65],
		[Vector3(-1.95, 3.02, 7.55), 4.55],
	]
	for li in lantern_specs.size():
		var l_pos: Vector3 = lantern_specs[li][0] as Vector3
		var ceil_y: float = float(lantern_specs[li][1])
		# Hanging brass chain, domed lantern cap, oil dish, and 4 vertical cage rods.
		_bastion_add_beam(metal_st, Vector3(l_pos.x, ceil_y, l_pos.z), l_pos + Vector3(0.0, 0.24, 0.0),
			0.026, 6, COL_GROTTO_BRASS_HI, COL_GROTTO_BRASS_LO)
		_bastion_add_tapered_prism(metal_st, l_pos + Vector3(0.0, 0.14, 0.0),
			Vector2(0.24, 0.24), Vector2(0.10, 0.10), 0.16, PI * 0.25,
			COL_GROTTO_BRASS_HI, COL_GROTTO_BRASS_HI, COL_GROTTO_BRASS_LO)
		_bastion_add_tapered_prism(metal_st, l_pos + Vector3(0.0, -0.26, 0.0),
			Vector2(0.15, 0.15), Vector2(0.22, 0.22), 0.10, PI * 0.25,
			COL_GROTTO_BRASS_HI, COL_GROTTO_BRASS_LO, COL_GROTTO_BRASS_LO)
		for ci in 4:
			var ca := float(ci) * (PI * 0.5) + PI * 0.25
			var off := Vector3(cos(ca) * 0.17, 0.0, sin(ca) * 0.17)
			_bastion_add_beam(metal_st, l_pos + off + Vector3(0.0, -0.18, 0.0),
				l_pos + off + Vector3(0.0, 0.16, 0.0), 0.018, 5, COL_GROTTO_BRASS_HI, COL_GROTTO_BRASS_LO)

		# Glowing warm amber lantern glass core.
		var glow_st := SurfaceTool.new()
		glow_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		glow_st.set_smooth_group(-1)
		_bastion_add_tapered_prism(glow_st, Vector3(0.0, -0.16, 0.0),
			Vector2(0.13, 0.13), Vector2(0.14, 0.14), 0.30, PI * 0.25,
			Color(1.0, 0.94, 0.66), Color(1.0, 0.74, 0.30), Color(0.95, 0.50, 0.14))
		glow_st.generate_normals()
		var glow_mi := MeshInstance3D.new()
		glow_mi.name = "SmugglerLanternGlow_%d" % li
		glow_mi.mesh = glow_st.commit()
		glow_mi.position = l_pos
		glow_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var glow_mat := StandardMaterial3D.new()
		glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow_mat.vertex_color_use_as_albedo = true
		glow_mat.vertex_color_is_srgb = true
		glow_mat.albedo_color = Color(2.1, 1.55, 0.75)
		glow_mat.emission_enabled = true
		glow_mat.emission = Color(1.0, 0.70, 0.24)
		glow_mat.emission_energy_multiplier = 3.8
		glow_mi.material_override = glow_mat
		grotto.add_child(glow_mi)

		# Warm flickering OmniLight3D registered via island distance-gated flicker!
		var light := OmniLight3D.new()
		light.name = "SmugglerLanternLight_%d" % li
		light.light_color = Color(1.0, 0.66, 0.24)
		light.light_energy = 4.2
		light.omni_range = 18.0
		light.omni_attenuation = 1.25
		light.shadow_enabled = false
		light.position = l_pos + Vector3(0.0, -0.05, 0.0)
		grotto.add_child(light)
		island.register_flicker_light(light, 4.2, 0.16, rng.randf() * TAU)

	wood_st.generate_normals()
	var table_mi := MeshInstance3D.new()
	table_mi.name = "ContrabandStashTable"
	table_mi.mesh = wood_st.commit()
	var table_mat := StandardMaterial3D.new()
	table_mat.vertex_color_use_as_albedo = true
	table_mat.vertex_color_is_srgb = true
	table_mat.roughness = 0.86
	table_mat.metallic = 0.02
	table_mi.material_override = table_mat
	grotto.add_child(table_mi)

	metal_st.generate_normals()
	var metal_mi := MeshInstance3D.new()
	metal_mi.name = "GrottoLanternHardware"
	metal_mi.mesh = metal_st.commit()
	var metal_mat := StandardMaterial3D.new()
	metal_mat.vertex_color_use_as_albedo = true
	metal_mat.vertex_color_is_srgb = true
	metal_mat.roughness = 0.38
	metal_mat.metallic = 0.78
	metal_mi.material_override = metal_mat
	grotto.add_child(metal_mi)

	# 6. Tucked smuggler rum barrels & supply crates along the cave sidewalls (center stays open!).
	var grotto_props: Array[Array] = [
		[BARREL_SCENE, "GrottoBarrel_L1", Vector3(-2.38, 0.0, 3.4), 0.45],
		[CRATE_SCENE, "GrottoCrate_L1", Vector3(-2.32, 0.0, 5.1), 0.18],
		[BARREL_SCENE, "GrottoBarrel_L2", Vector3(-2.26, 0.0, 6.7), 1.65],
		[CRATE_SCENE, "GrottoCrate_R1", Vector3(2.38, 0.0, 4.1), -0.22],
		[BARREL_SCENE, "GrottoBarrel_R1", Vector3(2.32, 0.0, 5.8), 2.10],
		[CRATE_SCENE, "GrottoCrate_R2", Vector3(2.18, 0.0, 7.8), 0.35],
	]
	for gp in grotto_props:
		var lp := grotto_xform * (gp[2] as Vector3)
		lp.y = island.surface_height(lp.x, lp.z)
		var prop_xf := Transform3D(Basis(Vector3.UP, landing_yaw + float(gp[3])), lp)
		_spawn_prop(island, gp[0] as PackedScene, String(gp[1]), prop_xf, prop_body, props_root, foliage_cache)

	# 7. Lush tropical ferns fanning gracefully over the mossy rocky cave brow & shoulders.
	var brow_ferns: Array[Array] = [
		["GrottoBrowFern_L", Vector3(-3.30, 5.55, -0.60), Vector3(-0.22, 0.42, 0.28), 1.45],
		["GrottoBrowFern_C", Vector3(0.22, 6.72, -0.58), Vector3(-0.28, 2.05, -0.05), 1.58],
		["GrottoBrowFern_R", Vector3(3.30, 5.42, -0.55), Vector3(-0.20, -1.18, -0.28), 1.38],
		["GrottoBrowFern_R2", Vector3(5.35, 3.05, -0.90), Vector3(-0.18, -0.65, -0.22), 1.32],
	]
	for bf in brow_ferns:
		var local_pos: Vector3 = bf[1] as Vector3
		var euler: Vector3 = bf[2] as Vector3
		var f_sc: float = float(bf[3])
		var local_xf := Transform3D(Basis.from_euler(euler) * Basis.from_scale(Vector3.ONE * f_sc), local_pos)
		_spawn_prop(island, BUSH_FERN_SCENE, String(bf[0]), grotto_xform * local_xf, prop_body, props_root, foliage_cache)

	# 8. Weathered flanking coastal cliff boulders anchoring the cave shoulders smoothly into the beach.
	var flank_boulders: Array[Array] = [
		["GrottoFlankBoulder_L1", Vector3(-5.65, 0.0, -1.85), 0.65, Vector3(1.55, 1.28, 1.42)],
		["GrottoFlankBoulder_L2", Vector3(-7.65, 0.0, 0.70), 2.15, Vector3(1.78, 1.56, 1.52)],
		["GrottoFlankBoulder_R1", Vector3(5.75, 0.0, -1.70), -0.95, Vector3(1.52, 1.24, 1.38)],
		["GrottoFlankBoulder_R2", Vector3(7.60, 0.0, 0.85), 1.40, Vector3(1.72, 1.50, 1.48)],
	]
	for fb in flank_boulders:
		var bp := grotto_xform * (fb[1] as Vector3)
		var by := island.surface_height(bp.x, bp.z)
		var b_yaw := landing_yaw + float(fb[2])
		var b_sc: Vector3 = fb[3] as Vector3
		var b_xf := Transform3D(Basis(Vector3.UP, b_yaw) * Basis.from_scale(b_sc),
			Vector3(bp.x, by - 0.56 * b_sc.y, bp.z))
		_spawn_prop(island, ROCK_BOULDER_SCENE, String(fb[0]), b_xf, prop_body, props_root, foliage_cache)

	return grotto


static func _build_grotto_vault_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)

	# 7 sculpted asymmetric longitudinal sea-cave stations from flared craggy mouth (z=-1.0)
	# to deep rear alcove (z=11.2), with wide sweeping outer flanks & rising mountain hood.
	var z_stops: Array[float] = [-1.0, 0.2, 2.2, 4.5, 6.8, 9.1, 11.2]
	var in_rx: Array[float] = [3.62, 3.36, 3.52, 3.72, 3.64, 3.32, 2.90]
	var in_ry: Array[float] = [5.38, 5.18, 5.04, 4.90, 4.72, 4.44, 4.02]
	var out_rx: Array[float] = [6.35, 6.75, 7.45, 8.20, 8.95, 9.65, 10.40]
	var out_ry: Array[float] = [6.05, 6.75, 7.65, 8.65, 9.85, 11.15, 12.60]

	const ARCH_SEGS := 10
	const RING_PTS := ARCH_SEGS + 3  # flared footing_L + 11 arch stops + flared footing_R
	var inner_rings: Array = []
	var outer_rings: Array = []
	var inner_cols: Array = []
	var outer_cols: Array = []

	for si in z_stops.size():
		var z := z_stops[si]
		var depth_t := clampf((z + 1.0) / 12.2, 0.0, 1.0)
		var iring: Array[Vector3] = []
		var oring: Array[Vector3] = []
		var icol: Array[Color] = []
		var ocol: Array[Color] = []

		for pi in RING_PTS:
			var ix: float
			var iy: float
			var ox: float
			var oy: float
			var crown_w := 0.0
			if pi == 0:
				ix = -in_rx[si] * 1.08
				iy = -1.45
				ox = -out_rx[si] * 1.24
				oy = -2.45
			elif pi == RING_PTS - 1:
				ix = in_rx[si] * 1.08
				iy = -1.45
				ox = out_rx[si] * 1.24
				oy = -2.45
			else:
				var theta := PI * float(pi - 1) / float(ARCH_SEGS)
				crown_w = sin(theta)
				# Organic sea-eroded harmonic strata relief + faceted jitter (keeps walkable floor >= 6.4 m wide!).
				var asym := 0.22 * sin(theta * 2.0 + 0.55)
				var strata_in := 0.16 * sin(z * 0.95 + theta * 3.0) * crown_w
				var j_in := rng.randf_range(-0.14, 0.16) * crown_w + strata_in
				var crag_out := 0.52 * sin(theta * 3.0 + z * 0.45) + 0.32 * cos(theta * 5.0 - z * 0.35)
				var j_out := rng.randf_range(-0.34, 0.48) * (0.45 + 0.55 * crown_w) + crag_out * (0.35 + 0.65 * crown_w)
				var base_flare := (1.0 - crown_w) * (1.0 - crown_w) * 1.25
				ix = -cos(theta) * (in_rx[si] + j_in) + asym * 0.45 * crown_w
				iy = sin(theta) * (in_ry[si] + j_in * 0.85 + asym * 0.35)
				ox = -cos(theta) * (out_rx[si] + j_out + base_flare) + asym * 0.85
				oy = sin(theta) * (out_ry[si] + j_out * 1.05)

			var z_j := 0.0
			if si == 0:
				z_j = -0.35 * sin(crown_w * PI) + rng.randf_range(-0.18, 0.22)
			iring.append(Vector3(ix, iy, z + z_j * 0.35))
			oring.append(Vector3(ox, oy, z + z_j + (0.35 if si == 0 and crown_w < 0.30 else 0.0)))

			# Warm inner cavern rock: weathered ochre lip -> warm shadow -> deep warm earth-brown alcove.
			var c_in := COL_GROTTO_LIMESTONE_MID.lerp(COL_GROTTO_SHADOW, smoothstep(0.02, 0.32, depth_t))
			c_in = c_in.lerp(COL_GROTTO_DEEP, smoothstep(0.36, 0.96, depth_t) * 0.88)
			if iy < 0.90:
				c_in = c_in.lerp(COL_GROTTO_SLATE, 0.48)
			elif crown_w > 0.65 and depth_t < 0.38:
				c_in = c_in.lerp(COL_GROTTO_MOSS, 0.24)
			icol.append(c_in)

			# Outer cliff shell: warm sunlit ochre-limestone -> weathered mid-cliff -> mossy upper rock crown.
			var facet_tone := 0.94 + 0.12 * float((si * 3 + pi) % 3) * 0.5
			var c_out := COL_GROTTO_LIMESTONE_MID.lerp(COL_GROTTO_LIMESTONE_SUN, smoothstep(0.18, 0.78, crown_w)) * facet_tone
			if crown_w > 0.56:
				var moss_w := smoothstep(0.56, 0.92, crown_w) * (0.42 + 0.22 * float((si + pi) % 2))
				c_out = c_out.lerp(COL_GROTTO_MOSS, clampf(moss_w, 0.0, 0.78))
			if oy < 0.75:
				c_out = c_out.lerp(COL_GROTTO_SLATE, 0.38)
			ocol.append(c_out)

		inner_rings.append(iring)
		outer_rings.append(oring)
		inner_cols.append(icol)
		outer_cols.append(ocol)

	# Connect inner vault shell (normals inward) & outer sweeping cliff shell (normals outward).
	for si in z_stops.size() - 1:
		var ir0: Array[Vector3] = inner_rings[si]
		var ir1: Array[Vector3] = inner_rings[si + 1]
		var ic0: Array[Color] = inner_cols[si]
		var ic1: Array[Color] = inner_cols[si + 1]
		var or0: Array[Vector3] = outer_rings[si]
		var or1: Array[Vector3] = outer_rings[si + 1]
		var oc0: Array[Color] = outer_cols[si]
		var oc1: Array[Color] = outer_cols[si + 1]
		var mid_z := 0.5 * (z_stops[si] + z_stops[si + 1])
		var center_ref := Vector3(0.0, 1.6, mid_z)

		for pi in RING_PTS - 1:
			var q_in_mid := 0.25 * (ir0[pi] + ir0[pi + 1] + ir1[pi + 1] + ir1[pi])
			_grotto_quad_oriented(st, ir0[pi], ir0[pi + 1], ir1[pi + 1], ir1[pi],
				ic0[pi], ic0[pi + 1], ic1[pi + 1], ic1[pi], center_ref - q_in_mid)

			var q_out_mid := 0.25 * (or0[pi] + or0[pi + 1] + or1[pi + 1] + or1[pi])
			_grotto_quad_oriented(st, or0[pi], or0[pi + 1], or1[pi + 1], or1[pi],
				oc0[pi], oc0[pi + 1], oc1[pi + 1], oc1[pi], q_out_mid - center_ref)

	# Sculpted thick organic sea-carved portal arch face joining inner & outer rings (faces seaward -Z).
	var fr_in: Array[Vector3] = inner_rings[0]
	var fr_out: Array[Vector3] = outer_rings[0]
	var fc_in: Array[Color] = inner_cols[0]
	var fc_out: Array[Color] = outer_cols[0]
	for pi in RING_PTS - 1:
		var lip_c0 := fc_in[pi].lerp(COL_GROTTO_LIMESTONE_SUN, 0.42)
		var lip_c1 := fc_in[pi + 1].lerp(COL_GROTTO_LIMESTONE_SUN, 0.42)
		_grotto_quad_oriented(st, fr_out[pi], fr_out[pi + 1], fr_in[pi + 1], fr_in[pi],
			fc_out[pi], fc_out[pi + 1], lip_c1, lip_c0, Vector3(0.0, 0.0, -1.0))

	# Closed sculpted rear rock wall (inner face toward -Z) + deep mountain-collar hood (+Z into cliff).
	var bk_in: Array[Vector3] = inner_rings[z_stops.size() - 1]
	var bk_ic: Array[Color] = inner_cols[z_stops.size() - 1]
	var rear_apex := Vector3(0.0, 1.95, 11.65)
	for pi in RING_PTS - 1:
		_grotto_tri_oriented(st, bk_in[pi], bk_in[pi + 1], rear_apex,
			bk_ic[pi], bk_ic[pi + 1], COL_GROTTO_DEEP, Vector3(0.0, 0.0, -1.0))
	# Seal the bottom base triangle between left/right rear footings so zero daylight leaks behind the stash table.
	_grotto_tri_oriented(st, bk_in[RING_PTS - 1], bk_in[0], rear_apex,
		bk_ic[RING_PTS - 1], bk_ic[0], COL_GROTTO_DEEP, Vector3(0.0, 0.0, -1.0))
	var bk_out: Array[Vector3] = outer_rings[z_stops.size() - 1]
	var bk_oc: Array[Color] = outer_cols[z_stops.size() - 1]
	var outer_rear_apex := Vector3(0.0, 11.5, 17.5)
	for pi in RING_PTS - 1:
		_grotto_tri_oriented(st, bk_out[pi], bk_out[pi + 1], outer_rear_apex,
			bk_oc[pi], bk_oc[pi + 1], COL_GROTTO_LIMESTONE_MID, Vector3(0.0, 0.35, 1.0))
	_grotto_tri_oriented(st, bk_out[RING_PTS - 1], bk_out[0], outer_rear_apex,
		bk_oc[RING_PTS - 1], bk_oc[0], COL_GROTTO_LIMESTONE_MID, Vector3(0.0, 0.35, 1.0))

	# Organic tapered multi-faceted craggy rock brow arch & rising mountain-collar spurs
	# (irregular 6-sided faceted rock spires — zero boxy rectangular slabs!).
	var brow_crags: Array[Array] = [
		# [pos, euler, base_rx, base_rz, top_rx, top_rz, height, top_shift, phase, moss_blend]
		[Vector3(-3.85, 2.85, -0.75), Vector3(0.10, 0.25, 0.28), 2.05, 1.85, 1.05, 0.95, 2.85, Vector2(0.45, -0.18), 0.4, 0.55],
		[Vector3(-1.85, 4.35, -0.95), Vector3(0.16, -0.18, 0.14), 2.15, 1.95, 1.00, 0.92, 2.45, Vector2(0.28, -0.35), 1.3, 0.68],
		[Vector3(0.25, 4.65, -0.88), Vector3(0.14, 0.32, -0.05), 2.35, 2.15, 1.15, 1.05, 2.35, Vector2(-0.12, -0.38), 2.1, 0.78],
		[Vector3(2.15, 4.22, -0.82), Vector3(0.15, -0.28, -0.16), 2.05, 1.90, 0.95, 0.88, 2.30, Vector2(-0.32, -0.30), 3.2, 0.65],
		[Vector3(3.85, 2.75, -0.68), Vector3(0.08, -0.22, -0.28), 2.00, 1.80, 1.02, 0.90, 2.75, Vector2(-0.42, -0.15), 4.1, 0.52],
		# Stepped mossy upper cliff-shoulder crags bridging seamlessly into the amphitheatre wall behind.
		[Vector3(-3.65, 4.55, 2.10), Vector3(-0.08, 0.40, 0.14), 3.30, 3.45, 1.75, 1.80, 4.35, Vector2(0.55, 0.65), 0.9, 0.74],
		[Vector3(0.05, 5.10, 2.65), Vector3(-0.10, -0.22, 0.02), 3.85, 3.80, 2.05, 2.10, 4.85, Vector2(0.08, 0.85), 2.7, 0.82],
		[Vector3(3.75, 4.35, 2.25), Vector3(-0.08, -0.36, -0.14), 3.25, 3.40, 1.70, 1.75, 4.15, Vector2(-0.52, 0.60), 5.0, 0.72],
		[Vector3(0.0, 5.95, 7.20), Vector3(-0.12, 0.15, 0.0), 5.65, 5.20, 3.10, 2.90, 6.85, Vector2(0.0, 1.35), 1.8, 0.60],
	]
	for bc in brow_crags:
		var c_xf := Transform3D(Basis.from_euler(bc[1] as Vector3), bc[0] as Vector3)
		var moss_w: float = float(bc[9])
		var col_top := COL_GROTTO_LIMESTONE_SUN.lerp(COL_GROTTO_MOSS, moss_w)
		_grotto_add_faceted_rock_crag(st, c_xf,
			float(bc[2]), float(bc[3]), float(bc[4]), float(bc[5]), float(bc[6]), 6,
			bc[7] as Vector2, float(bc[8]),
			col_top, COL_GROTTO_LIMESTONE_SUN, COL_GROTTO_SHADOW)

	# Sweeping sloping flanking coastal monolith buttresses blending both cave shoulders into beach sand.
	var flank_buttresses: Array[Array] = [
		# Port cliff-shoulder cascade stepping down into the golden beach.
		[Vector3(-4.85, -2.25, 0.35), Vector3(0.04, 0.24, 0.24), 2.75, 3.25, 1.35, 1.65, 7.20, Vector2(0.95, 0.30), 0.7, 0.38],
		[Vector3(-6.45, -2.30, -0.45), Vector3(0.08, 0.55, 0.32), 2.60, 2.75, 1.10, 1.20, 5.35, Vector2(1.05, 0.18), 2.2, 0.32],
		[Vector3(-7.90, -2.20, 2.65), Vector3(-0.04, 0.38, 0.22), 3.35, 3.85, 1.65, 1.85, 8.20, Vector2(1.10, 0.55), 3.6, 0.58],
		[Vector3(-4.55, -2.15, -1.65), Vector3(0.14, 0.65, 0.26), 1.95, 1.75, 0.82, 0.76, 4.35, Vector2(0.65, 0.28), 4.9, 0.24],
		# Starboard cliff-shoulder cascade stepping down into the golden beach.
		[Vector3(4.90, -2.25, 0.45), Vector3(0.04, -0.26, -0.24), 2.70, 3.20, 1.32, 1.60, 7.05, Vector2(-0.92, 0.28), 1.4, 0.36],
		[Vector3(6.55, -2.30, -0.35), Vector3(0.08, -0.52, -0.30), 2.55, 2.70, 1.08, 1.18, 5.20, Vector2(-1.02, 0.16), 2.9, 0.30],
		[Vector3(7.95, -2.20, 2.80), Vector3(-0.04, -0.34, -0.22), 3.30, 3.80, 1.62, 1.80, 8.05, Vector2(-1.08, 0.52), 4.3, 0.56],
		[Vector3(4.60, -2.15, -1.55), Vector3(0.14, -0.62, -0.25), 1.90, 1.70, 0.80, 0.74, 4.25, Vector2(-0.62, 0.26), 5.6, 0.22],
	]
	for fb in flank_buttresses:
		var f_xf := Transform3D(Basis.from_euler(fb[1] as Vector3), fb[0] as Vector3)
		var f_moss: float = float(fb[9])
		var f_top := COL_GROTTO_LIMESTONE_SUN.lerp(COL_GROTTO_MOSS, f_moss)
		_grotto_add_faceted_rock_crag(st, f_xf,
			float(fb[2]), float(fb[3]), float(fb[4]), float(fb[5]), float(fb[6]), 6,
			fb[7] as Vector2, float(fb[8]),
			f_top, COL_GROTTO_LIMESTONE_MID, COL_GROTTO_SLATE)

	# Subtle organic recessed interior rock-fold spurs & low sea-worn basal outcrops
	# (strictly tucked against outer wall base |x| >= 3.10 so central 6 m stays wide open!).
	var inner_outcrops: Array[Array] = [
		[Vector3(-3.32, -0.45, 1.25), Vector3(0.0, 0.35, -0.14), 0.72, 1.15, 0.34, 0.58, 1.85, Vector2(-0.18, 0.0), 0.6],
		[Vector3(3.30, -0.45, 1.55), Vector3(0.0, -0.40, 0.14), 0.70, 1.10, 0.32, 0.55, 1.78, Vector2(0.18, 0.0), 1.9],
		[Vector3(-3.40, -0.40, 5.20), Vector3(0.0, 0.22, -0.12), 0.68, 1.25, 0.28, 0.62, 1.65, Vector2(-0.22, 0.0), 3.1],
		[Vector3(3.38, -0.40, 5.45), Vector3(0.0, -0.25, 0.12), 0.66, 1.20, 0.28, 0.60, 1.60, Vector2(0.22, 0.0), 4.4],
		[Vector3(-3.18, -0.35, 8.85), Vector3(0.0, 0.48, -0.10), 0.62, 1.05, 0.26, 0.52, 1.45, Vector2(-0.18, 0.0), 5.2],
		[Vector3(3.18, -0.35, 8.95), Vector3(0.0, -0.42, 0.10), 0.62, 1.02, 0.26, 0.50, 1.42, Vector2(0.18, 0.0), 2.5],
	]
	for io in inner_outcrops:
		var io_pos: Vector3 = io[0] as Vector3
		var io_xf := Transform3D(Basis.from_euler(io[1] as Vector3), io_pos)
		var dt := clampf((io_pos.z + 1.0) / 11.5, 0.0, 1.0)
		var c_io_top := COL_GROTTO_LIMESTONE_MID.lerp(COL_GROTTO_DEEP, 0.35 + 0.45 * dt)
		var c_io_bot := COL_GROTTO_SLATE.lerp(COL_GROTTO_DEEP, 0.55 * dt)
		_grotto_add_faceted_rock_crag(st, io_xf,
			float(io[2]), float(io[3]), float(io[4]), float(io[5]), float(io[6]), 5,
			io[7] as Vector2, float(io[8]),
			c_io_top, COL_GROTTO_SHADOW, c_io_bot)

	# 10 hanging faceted stalactites along the brow arch and vaulted cavern ceiling (all tips >= 3.0 m!).
	var stalactites: Array[Array] = [
		[Vector3(-2.10, 4.65, -0.60), 0.28, 1.15],
		[Vector3(-0.85, 5.28, -0.82), 0.32, 1.45],
		[Vector3(0.70, 5.32, -0.65), 0.30, 1.35],
		[Vector3(2.05, 4.68, -0.45), 0.26, 1.05],
		[Vector3(-1.55, 4.76, 2.15), 0.28, 1.30],
		[Vector3(1.25, 4.88, 2.95), 0.26, 1.25],
		[Vector3(-0.35, 4.98, 4.65), 0.31, 1.50],
		[Vector3(1.68, 4.48, 5.95), 0.25, 1.15],
		[Vector3(-1.40, 4.46, 7.55), 0.27, 1.20],
		[Vector3(0.45, 4.42, 9.20), 0.24, 1.08],
	]
	for st_spec in stalactites:
		var s_base: Vector3 = st_spec[0] as Vector3
		var s_rad: float = float(st_spec[1])
		var s_len: float = float(st_spec[2])
		var dt := clampf((s_base.z + 0.8) / 11.0, 0.0, 1.0)
		var c_base := COL_GROTTO_LIMESTONE_MID.lerp(COL_GROTTO_SHADOW, 0.45 * dt)
		var c_tip := COL_GROTTO_STALACTITE.lerp(COL_GROTTO_DEEP, 0.35 * dt)
		_grotto_add_stalactite(st, s_base, s_rad, s_len, c_base, c_tip, rng.randf() * TAU)

	st.generate_normals()
	return st.commit()


static func _grotto_add_faceted_rock_crag(st: SurfaceTool, xf: Transform3D,
		base_rx: float, base_rz: float, top_rx: float, top_rz: float, height: float,
		sides: int, top_shift: Vector2, phase: float,
		col_top: Color, col_mid: Color, col_bot: Color) -> void:
	var n_sides := maxi(sides, 5)
	var mid_h := height * 0.56
	var crown_h := height * 0.88
	var mid_rx := lerpf(base_rx, top_rx, 0.38)
	var mid_rz := lerpf(base_rz, top_rz, 0.38)

	var r_bot: Array[Vector3] = []
	var r_mid: Array[Vector3] = []
	var r_top: Array[Vector3] = []
	for i in n_sides:
		var ang := phase * 0.35 + TAU * float(i) / float(n_sides)
		var j_b := 1.0 + 0.16 * sin(ang * 2.0 + phase) + 0.10 * cos(ang * 3.0 - phase)
		var j_m := 1.0 + 0.14 * sin(ang * 2.0 + phase + 0.7) + 0.09 * cos(ang * 3.0 + phase)
		var j_t := 1.0 + 0.12 * cos(ang * 2.0 - phase)
		var ca := cos(ang)
		var sa := sin(ang)
		r_bot.append(xf * Vector3(ca * base_rx * j_b, 0.0, sa * base_rz * j_b))
		r_mid.append(xf * Vector3(ca * mid_rx * j_m + top_shift.x * 0.42, mid_h, sa * mid_rz * j_m + top_shift.y * 0.42))
		r_top.append(xf * Vector3(ca * top_rx * j_t + top_shift.x, crown_h, sa * top_rz * j_t + top_shift.y))

	var apex := xf * Vector3(top_shift.x * 1.15, height, top_shift.y * 1.15)
	var belly := xf * Vector3(0.0, -height * 0.22, 0.0)
	var ref_lo := xf * Vector3(top_shift.x * 0.22, mid_h * 0.5, top_shift.y * 0.22)
	var ref_hi := xf * Vector3(top_shift.x * 0.70, (mid_h + crown_h) * 0.5, top_shift.y * 0.70)
	var ref_cap := xf * Vector3(top_shift.x, crown_h - height * 0.18, top_shift.y)
	var ref_belly := xf * Vector3(0.0, height * 0.15, 0.0)

	for i in n_sides:
		var j := (i + 1) % n_sides
		var shade_f := 0.94 + 0.12 * float(i % 2)
		var c_b := col_bot * shade_f
		var c_m := col_mid * shade_f
		var c_t := col_top * (0.96 + 0.08 * float((i + 1) % 2))
		var q1_ctr := 0.25 * (r_bot[i] + r_bot[j] + r_mid[j] + r_mid[i])
		var q2_ctr := 0.25 * (r_mid[i] + r_mid[j] + r_top[j] + r_top[i])
		var cap_ctr := (r_top[i] + r_top[j] + apex) / 3.0
		var bel_ctr := (r_bot[i] + r_bot[j] + belly) / 3.0
		_grotto_tri_oriented(st, r_bot[i], r_bot[j], belly,
			c_b, c_b, col_bot * 0.82, bel_ctr - ref_belly)
		_grotto_quad_oriented(st, r_bot[i], r_bot[j], r_mid[j], r_mid[i],
			c_b, c_b, c_m, c_m, q1_ctr - ref_lo)
		_grotto_quad_oriented(st, r_mid[i], r_mid[j], r_top[j], r_top[i],
			c_m, c_m, c_t, c_t, q2_ctr - ref_hi)
		_grotto_tri_oriented(st, r_top[i], r_top[j], apex,
			c_t, c_t, col_top, cap_ctr - ref_cap)


static func _build_contraband_stash_table(wood_st: SurfaceTool, metal_st: SurfaceTool,
		origin: Vector3) -> void:
	# Chunky beveled weathered sea-oak plank tabletop (2.30 m x 1.02 m at y = 0.86 m).
	for pi in 4:
		var pz := -0.375 + float(pi) * 0.25
		var c_plank := COL_FORT_WOOD_LIGHT.lerp(COL_FORT_WOOD_MID, 0.24 * float(pi % 3))
		_bastion_add_tapered_prism(wood_st, origin + Vector3(0.0, 0.76, pz),
			Vector2(1.14, 0.115), Vector2(1.12, 0.110), 0.10, 0.0,
			c_plank, COL_FORT_WOOD_MID, COL_FORT_WOOD_DARK)
	# Twin splayed timber trestle legs + lower stretcher beam + iron corner straps.
	for sgn: float in [-1.0, 1.0]:
		var lx := sgn * 0.88
		_bastion_add_tapered_prism(wood_st, origin + Vector3(lx, 0.0, 0.0),
			Vector2(0.11, 0.44), Vector2(0.09, 0.36), 0.76, 0.0,
			COL_FORT_WOOD_MID, COL_FORT_WOOD_MID, COL_FORT_WOOD_DARK)
		_bastion_add_tapered_prism(metal_st, origin + Vector3(sgn * 1.13, 0.75, 0.0),
			Vector2(0.03, 0.48), Vector2(0.03, 0.48), 0.12, 0.0,
			COL_FORT_IRON_HI, COL_FORT_IRON_HI, COL_FORT_IRON_LO)
	_bastion_add_beam(wood_st, origin + Vector3(-0.88, 0.24, 0.0), origin + Vector3(0.88, 0.24, 0.0),
		0.068, 6, COL_FORT_WOOD_LIGHT, COL_FORT_WOOD_DARK)

	# Environmental storytelling contraband props on the tabletop:
	# Unrolled parchment chart + stacked brass/gold ingots + tall emerald rum bottle.
	var col_parch := Color(0.86, 0.78, 0.56)
	var col_parch_edge := Color(0.72, 0.62, 0.40)
	_bastion_add_tapered_prism(wood_st, origin + Vector3(-0.28, 0.86, 0.02),
		Vector2(0.46, 0.32), Vector2(0.46, 0.32), 0.02, 0.14,
		col_parch, col_parch_edge, col_parch_edge)
	# Stacked contraband gold bars on the starboard half of the table.
	var col_gold_hi := Color(0.96, 0.78, 0.24)
	var col_gold_lo := Color(0.64, 0.46, 0.10)
	_bastion_add_tapered_prism(metal_st, origin + Vector3(0.52, 0.86, -0.06),
		Vector2(0.18, 0.09), Vector2(0.14, 0.06), 0.08, -0.20, col_gold_hi, col_gold_hi, col_gold_lo)
	_bastion_add_tapered_prism(metal_st, origin + Vector3(0.56, 0.86, 0.12),
		Vector2(0.18, 0.09), Vector2(0.14, 0.06), 0.08, 0.15, col_gold_hi, col_gold_hi, col_gold_lo)
	_bastion_add_tapered_prism(metal_st, origin + Vector3(0.54, 0.94, 0.03),
		Vector2(0.17, 0.08), Vector2(0.13, 0.05), 0.08, -0.05, col_gold_hi, col_gold_hi, col_gold_lo)
	# Rum bottle on the port corner.
	var col_bottle_hi := Color(0.22, 0.52, 0.26)
	var col_bottle_lo := Color(0.10, 0.28, 0.14)
	_bastion_add_tapered_prism(wood_st, origin + Vector3(-0.84, 0.86, -0.22),
		Vector2(0.065, 0.065), Vector2(0.055, 0.055), 0.22, 0.3, col_bottle_hi, col_bottle_hi, col_bottle_lo)
	_bastion_add_tapered_prism(wood_st, origin + Vector3(-0.84, 1.08, -0.22),
		Vector2(0.030, 0.030), Vector2(0.024, 0.024), 0.10, 0.3, col_bottle_hi, col_bottle_lo, col_bottle_lo)


static func _add_grotto_box_collider(prop_body: StaticBody3D, grotto_xform: Transform3D,
		col_name: String, local_xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = "Col_Grotto_" + col_name
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.transform = grotto_xform * local_xf
	prop_body.add_child(cs)


static func _grotto_add_stalactite(st: SurfaceTool, base_center: Vector3, base_r: float,
		length: float, col_base: Color, col_tip: Color, yaw_off: float) -> void:
	const SIDES := 5
	var mid_y := base_center.y - length * 0.45
	var tip := Vector3(base_center.x, base_center.y - length, base_center.z)
	var top_ring: Array[Vector3] = []
	var mid_ring: Array[Vector3] = []
	for i in SIDES:
		var ang := yaw_off + TAU * float(i) / float(SIDES)
		top_ring.append(base_center + Vector3(cos(ang) * base_r, 0.22, sin(ang) * base_r))
		mid_ring.append(Vector3(base_center.x + cos(ang) * base_r * 0.56, mid_y, base_center.z + sin(ang) * base_r * 0.56))
	var col_mid := col_base.lerp(col_tip, 0.5)
	for i in SIDES:
		var j := (i + 1) % SIDES
		var out_dir := (0.5 * (top_ring[i] + top_ring[j]) - base_center)
		out_dir.y = -0.25
		_grotto_quad_oriented(st, top_ring[i], top_ring[j], mid_ring[j], mid_ring[i],
			col_base, col_base, col_mid, col_mid, out_dir)
		_grotto_tri_oriented(st, mid_ring[i], mid_ring[j], tip, col_mid, col_mid, col_tip, out_dir)


static func _grotto_tri_oriented(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color, desired_normal: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.dot(desired_normal) >= 0.0:
		_bastion_tri(st, a, b, c, ca, cb, cc)
	else:
		_bastion_tri(st, a, c, b, ca, cc, cb)


static func _grotto_quad_oriented(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ca: Color, cb: Color, cc: Color, cd: Color, desired_normal: Vector3) -> void:
	_grotto_tri_oriented(st, a, b, c, ca, cb, cc, desired_normal)
	_grotto_tri_oriented(st, a, c, d, ca, cc, cd, desired_normal)


# ============================================================ volcanic magma caldera & plume

## Build the glowing molten magma caldera, cracked charcoal-obsidian crust plates,
## crimson-amber caldera rim bounce light, and towering ash/ember volcanic plume
## inside the summit crater of `&"volcano_crag"` islands (e.g. Cinder Crag).
static func _build_volcano_caldera(island: Island, cal_xform: Transform3D,
		scale_r: float, rng: RandomNumberGenerator) -> VolcanoCaldera:
	var caldera := VolcanoCaldera.new()
	caldera.name = "VolcanoCaldera"
	caldera.transform = cal_xform
	island.add_child(caldera)

	var pool_r := 9.6 * scale_r

	# 1. Glowing Molten Magma Basin with radiating incandescent gold/orange/crimson fissures.
	var magma_st := SurfaceTool.new()
	magma_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	magma_st.set_smooth_group(-1)
	const SPOKES := 16
	var r_fracs: Array[float] = [0.24, 0.56, 0.84, 1.06]
	var center_pt := Vector3(0.0, 0.34, 0.0)
	var rings: Array = []
	var ring_cols: Array = []

	for ri in r_fracs.size():
		var rf := r_fracs[ri]
		var r_pts: Array[Vector3] = []
		var r_cls: Array[Color] = []
		for si in SPOKES:
			var ang := TAU * float(si) / float(SPOKES)
			var wobble := 1.0 + 0.11 * sin(ang * 3.0 + 0.4) + 0.07 * cos(ang * 5.0 - 0.8)
			var rad := pool_r * rf * wobble
			var fissure := pow(maxf(0.0, cos(ang * 6.0 + rf * 2.1)), 3.2)
			var py := 0.24 * (1.0 - rf) + 0.16 * fissure
			if ri == r_fracs.size() - 1:
				py = -1.65  # Skirt plunges cleanly into the basalt caldera walls.
			r_pts.append(Vector3(cos(ang) * rad, py, sin(ang) * rad))

			var heat := clampf((1.0 - rf * 0.82) * 0.72 + fissure * 0.62, 0.0, 1.0)
			var c_lava := COL_CALDERA_MAGMA_RIM.lerp(COL_CALDERA_MAGMA_MID, smoothstep(0.05, 0.55, heat))
			c_lava = c_lava.lerp(COL_CALDERA_MAGMA_CORE, smoothstep(0.58, 0.96, heat))
			r_cls.append(c_lava)
		rings.append(r_pts)
		ring_cols.append(r_cls)

	var r0: Array[Vector3] = rings[0]
	var c0: Array[Color] = ring_cols[0]
	for si in SPOKES:
		var sn := (si + 1) % SPOKES
		_grotto_tri_oriented(magma_st, center_pt, r0[si], r0[sn],
			COL_CALDERA_MAGMA_CORE, c0[si], c0[sn], Vector3.UP)
	for ri in rings.size() - 1:
		var a_r: Array[Vector3] = rings[ri]
		var b_r: Array[Vector3] = rings[ri + 1]
		var a_c: Array[Color] = ring_cols[ri]
		var b_c: Array[Color] = ring_cols[ri + 1]
		for si in SPOKES:
			var sn := (si + 1) % SPOKES
			_grotto_quad_oriented(magma_st, a_r[si], a_r[sn], b_r[sn], b_r[si],
				a_c[si], a_c[sn], b_c[sn], b_c[si], Vector3.UP)

	magma_st.generate_normals()
	var magma_mat := StandardMaterial3D.new()
	magma_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	magma_mat.vertex_color_use_as_albedo = true
	magma_mat.albedo_color = Color(2.15, 1.80, 1.45, 1.0)
	magma_mat.emission_enabled = true
	magma_mat.emission = Color(1.0, 0.36, 0.06)
	magma_mat.emission_energy_multiplier = 4.2
	var magma_mi := MeshInstance3D.new()
	magma_mi.name = "MagmaPool"
	magma_mi.mesh = magma_st.commit()
	magma_mi.material_override = magma_mat
	magma_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	caldera.add_child(magma_mi)
	caldera.magma_mesh = magma_mi
	caldera._magma_mat = magma_mat

	# 2. Cracked faceted charcoal-obsidian crust plates + scorched volcanic rim collar slabs.
	var crust_st := SurfaceTool.new()
	crust_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	crust_st.set_smooth_group(-1)
	# 9 floating jagged obsidian crust islands seated between the glowing radial fissures.
	for pi in 9:
		var p_ang := (TAU * float(pi) / 9.0) + 0.28 + rng.randf_range(-0.14, 0.14)
		var p_rad := pool_r * rng.randf_range(0.32, 0.72)
		var p_pos := Vector3(cos(p_ang) * p_rad, -0.25, sin(p_ang) * p_rad)
		var p_hx := rng.randf_range(1.15, 2.05) * scale_r
		var p_hz := rng.randf_range(0.95, 1.75) * scale_r
		var p_h := rng.randf_range(0.62, 1.02)
		_bastion_add_tapered_prism(crust_st, p_pos,
			Vector2(p_hx, p_hz), Vector2(p_hx * 0.74, p_hz * 0.72), p_h, p_ang + rng.randf_range(-0.4, 0.4),
			COL_CALDERA_OBSIDIAN_TOP, COL_CALDERA_OBSIDIAN_EDGE, COL_CALDERA_OBSIDIAN_SCORCH)

	# 12 tilted jagged obsidian basalt rim slabs anchoring the magma basin into the crater walls.
	for r_idx in 12:
		var ra := TAU * float(r_idx) / 12.0 + rng.randf_range(-0.08, 0.08)
		var rr := pool_r * rng.randf_range(0.90, 1.06)
		var r_pos := Vector3(cos(ra) * rr, -2.2, sin(ra) * rr)
		var r_w := rng.randf_range(1.85, 2.85) * scale_r
		var r_d := rng.randf_range(1.35, 2.05) * scale_r
		var r_h := rng.randf_range(3.2, 4.8)
		var tilt := Basis(Vector3.UP, -ra) * Basis(Vector3.BACK, rng.randf_range(-0.22, -0.06))
		_bastion_add_oriented_prism(crust_st, Transform3D(tilt, r_pos),
			Vector2(r_d, r_w), Vector2(r_d * 0.62, r_w * 0.72), r_h,
			COL_CALDERA_OBSIDIAN_TOP, COL_CALDERA_OBSIDIAN_EDGE, COL_CALDERA_OBSIDIAN_SCORCH)

	crust_st.generate_normals()
	var crust_mi := MeshInstance3D.new()
	crust_mi.name = "ObsidianCrust"
	crust_mi.mesh = crust_st.commit()
	var crust_mat := StandardMaterial3D.new()
	crust_mat.vertex_color_use_as_albedo = true
	crust_mat.roughness = 0.86
	crust_mat.metallic = 0.06
	crust_mi.material_override = crust_mat
	caldera.add_child(crust_mi)
	caldera.obsidian_mesh = crust_mi

	# 3. High-mounted fiery magma rim bounce light illuminating the jagged basalt caldera fangs!
	var plume_sc := clampf(scale_r * 0.62, 1.0, 1.85)
	var cal_light := OmniLight3D.new()
	cal_light.name = "CalderaMagmaLight"
	cal_light.light_color = Color(1.0, 0.36, 0.08)
	cal_light.light_energy = 10.5
	cal_light.omni_range = maxf(76.0, 44.0 * scale_r)
	cal_light.omni_attenuation = 0.72
	cal_light.shadow_enabled = false
	cal_light.position = Vector3(0.0, 7.5 * plume_sc, 0.0)
	caldera.add_child(cal_light)
	caldera.caldera_light = cal_light
	island.register_flicker_light(cal_light, 10.5, 0.18, rng.randf() * TAU)

	# 4. Two sculpted glowing molten lava-fissure runnels spilling through the breached -v notch
	#    and snaking boldly down the steep dark basalt cliff face!
	var fissure_mat := StandardMaterial3D.new()
	fissure_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fissure_mat.vertex_color_use_as_albedo = true
	fissure_mat.vertex_color_is_srgb = true
	fissure_mat.albedo_color = Color(1.48, 1.18, 0.88, 1.0)
	fissure_mat.emission_enabled = true
	fissure_mat.emission = Color(1.0, 0.38, 0.06)
	fissure_mat.emission_energy_multiplier = 2.8
	var fissure_mi := MeshInstance3D.new()
	fissure_mi.name = "LavaFissureMesh"
	fissure_mi.mesh = _build_lava_fissure_mesh(island, cal_xform, scale_r)
	fissure_mi.material_override = fissure_mat
	fissure_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	caldera.add_child(fissure_mi)
	caldera.lava_fissure_mesh = fissure_mi
	caldera._fissure_mat = fissure_mat

	# 5. Towering rising volcanic ash plume (lean <= 28 puffs, bold scale visible from 2+ km away!).
	var ash_p := GPUParticles3D.new()
	ash_p.name = "VolcanoAshPlume"
	ash_p.amount = 28
	ash_p.lifetime = 12.5
	ash_p.preprocess = 7.0
	ash_p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	ash_p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ash_span := 56.0 * plume_sc
	ash_p.visibility_aabb = AABB(Vector3(-ash_span, -4.0, -ash_span), Vector3(ash_span * 2.0, 142.0 * plume_sc, ash_span * 2.0))
	ash_p.position = Vector3(0.0, 3.6, 0.0)
	var ash_proc := ParticleProcessMaterial.new()
	ash_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	ash_proc.emission_ring_radius = 6.8 * scale_r
	ash_proc.emission_ring_inner_radius = 1.6 * scale_r
	ash_proc.emission_ring_height = 1.2
	ash_proc.emission_ring_axis = Vector3.UP
	ash_proc.direction = Vector3(0.14, 1.0, 0.08).normalized()
	ash_proc.spread = 12.0
	ash_proc.initial_velocity_min = 5.0 * plume_sc
	ash_proc.initial_velocity_max = 7.8 * plume_sc
	ash_proc.gravity = Vector3(0.35, 0.16, 0.16)
	ash_proc.scale_min = 3.8 * plume_sc
	ash_proc.scale_max = 6.2 * plume_sc
	var ash_curve := Curve.new()
	ash_curve.add_point(Vector2(0.0, 0.62))
	ash_curve.add_point(Vector2(0.32, 1.55))
	ash_curve.add_point(Vector2(0.72, 2.55))
	ash_curve.add_point(Vector2(1.0, 3.45))
	var ash_curve_tex := CurveTexture.new()
	ash_curve_tex.curve = ash_curve
	ash_proc.scale_curve = ash_curve_tex
	ash_proc.color_ramp = _make_volcano_ash_ramp()
	ash_p.process_material = ash_proc
	var ash_quad := QuadMesh.new()
	ash_quad.size = Vector2(6.4, 6.4)
	var ash_mat := StandardMaterial3D.new()
	ash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ash_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	ash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ash_mat.vertex_color_use_as_albedo = true
	ash_mat.albedo_texture = _get_beacon_puff_texture()
	ash_quad.material = ash_mat
	ash_p.draw_pass_1 = ash_quad
	ash_p.emitting = true
	caldera.add_child(ash_p)
	caldera.ash_plume = ash_p

	# 6. Soaring incandescent volcanic lava embers (lean <= 24 embers, bold bright sparks above rim!).
	var ember_p := GPUParticles3D.new()
	ember_p.name = "VolcanoEmberPlume"
	ember_p.amount = 24
	ember_p.lifetime = 5.6
	ember_p.preprocess = 2.8
	ember_p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	ember_p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var emb_span := 36.0 * plume_sc
	ember_p.visibility_aabb = AABB(Vector3(-emb_span, -2.0, -emb_span), Vector3(emb_span * 2.0, 88.0 * plume_sc, emb_span * 2.0))
	ember_p.position = Vector3(0.0, 4.0, 0.0)
	var emb_proc := ParticleProcessMaterial.new()
	emb_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	emb_proc.emission_ring_radius = 8.0 * scale_r
	emb_proc.emission_ring_inner_radius = 1.2 * scale_r
	emb_proc.emission_ring_height = 0.8
	emb_proc.emission_ring_axis = Vector3.UP
	emb_proc.direction = Vector3(0.10, 1.0, 0.06).normalized()
	emb_proc.spread = 24.0
	emb_proc.initial_velocity_min = 7.5 * plume_sc
	emb_proc.initial_velocity_max = 14.8 * plume_sc
	emb_proc.gravity = Vector3(0.30, -0.32, 0.15)
	emb_proc.scale_min = 0.85 * plume_sc
	emb_proc.scale_max = 1.95 * plume_sc
	emb_proc.color_ramp = _make_volcano_ember_ramp()
	ember_p.process_material = emb_proc
	var emb_quad := QuadMesh.new()
	emb_quad.size = Vector2(1.45, 1.45)
	var emb_mat := StandardMaterial3D.new()
	emb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	emb_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	emb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	emb_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	emb_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	emb_mat.vertex_color_use_as_albedo = true
	emb_mat.albedo_texture = _get_beacon_puff_texture()
	emb_quad.material = emb_mat
	ember_p.draw_pass_1 = emb_quad
	ember_p.emitting = true
	caldera.add_child(ember_p)
	caldera.ember_plume = ember_p

	return caldera


static func _build_lava_fissure_mesh(island: Island, cal_xform: Transform3D,
		scale_r: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)

	var inv_basis := cal_xform.basis.inverse()
	var col_scorch := Color(0.20, 0.03, 0.01)
	var col_rim_hot := Color(1.0, 0.30, 0.03)
	var w_scale := minf(scale_r, 1.85)

	# Probe both breached seaward -v caldera rim saddles (r = 14.5 * scale_r) so the two molten lava
	# fissures spill independently through genuine V-notches rather than overlapping or climbing fangs!
	var rim_r := 14.5 * scale_r
	var notch_a := -1.68
	var min_h_a := INF
	for si in 17:
		var cand_ang := lerpf(-2.05, -1.32, float(si) / 16.0)
		var rim_isl := cal_xform * Vector3(cos(cand_ang) * rim_r, 0.0, sin(cand_ang) * rim_r)
		var rim_h := island.surface_height(rim_isl.x, rim_isl.z)
		if rim_h < min_h_a:
			min_h_a = rim_h
			notch_a = cand_ang

	var notch_b := -2.38
	var min_h_b := INF
	for si in 17:
		var cand_ang := lerpf(-2.70, -2.16, float(si) / 16.0)
		var rim_isl := cal_xform * Vector3(cos(cand_ang) * rim_r, 0.0, sin(cand_ang) * rim_r)
		var rim_h := island.surface_height(rim_isl.x, rim_isl.z)
		if rim_h < min_h_b:
			min_h_b = rim_h
			notch_b = cand_ang

	# 2 distinct glowing molten lava-fissure runnels spilling through the twin seaward V-notches
	# and snaking down the steep dark basalt cliff face:
	# [r_start, r_end, base_notch_ang, fork_drift, wave_amp, wave_freq, wave_phase, width_top, width_bot]
	var runnels: Array[Array] = [
		[7.8 * scale_r, 38.5 * scale_r, notch_a, 0.16, 0.085, 8.6, 0.45, 1.32 * w_scale, 0.34 * w_scale],
		[8.0 * scale_r, 35.6 * scale_r, notch_b, -0.10, 0.095, 9.2, 2.05, 1.24 * w_scale, 0.30 * w_scale],
	]

	const STEPS := 26
	const OFFSETS: Array[float] = [-1.0, -0.34, 0.0, 0.34, 1.0]

	for run in runnels:
		var r0: float = float(run[0])
		var r1: float = float(run[1])
		var base_notch: float = float(run[2])
		var fork_drift: float = float(run[3])
		var w_amp: float = float(run[4])
		var w_freq: float = float(run[5])
		var w_phase: float = float(run[6])
		var w_top: float = float(run[7])
		var w_bot: float = float(run[8])

		var center_xz: Array[Vector2] = []
		for i in range(STEPS + 1):
			var t := float(i) / float(STEPS)
			var r := lerpf(r0, r1, t)
			# Thread cleanly through each V-notch across t=0..0.24, then meander down the dark basalt face!
			var post_notch := smoothstep(0.20, 0.90, t)
			var meander := sin(t * w_freq + w_phase) * w_amp * smoothstep(0.18, 0.44, t)
			var ang := base_notch + fork_drift * post_notch + meander
			center_xz.append(Vector2(cos(ang) * r, sin(ang) * r))

		var rows_pts: Array = []
		var rows_cols: Array = []
		var rows_norms: Array[Vector3] = []

		for i in range(STEPS + 1):
			var t := float(i) / float(STEPS)
			var c_xz := center_xz[i]
			var prev_xz := center_xz[maxi(i - 1, 0)]
			var next_xz := center_xz[mini(i + 1, STEPS)]
			var tang := (next_xz - prev_xz)
			tang = tang.normalized() if tang.length_squared() > 0.0001 else Vector2(0.0, -1.0)
			var side := Vector2(-tang.y, tang.x)

			# Slightly wider molten spill pooling over the breached notch lip, tapering into craggy veins below.
			var lip_bulge := 1.0 + 0.28 * exp(-pow((t - 0.20) / 0.12, 2.0))
			var pulse_w := 1.0 + 0.22 * sin(t * 17.0 + w_phase)
			var half_w := lerpf(w_top, w_bot, pow(t, 0.82)) * lip_bulge * pulse_w
			var cool := smoothstep(0.54, 1.0, t) * 0.56

			var row_p: Array[Vector3] = []
			var row_c: Array[Color] = []
			var center_n_loc := Vector3.UP

			for oi in OFFSETS.size():
				var k := OFFSETS[oi]
				var p_xz := c_xz + side * (k * half_w)
				var isl_p := cal_xform * Vector3(p_xz.x, 0.0, p_xz.y)
				var h_isl := island.surface_height(isl_p.x, isl_p.z)
				var n_isl := island.surface_normal(isl_p.x, isl_p.z, 1.2)
				var n_loc := (inv_basis * n_isl).normalized()
				if oi == 2:
					center_n_loc = n_loc

				var y_g := h_isl - cal_xform.origin.y
				if t < 0.14:
					y_g = maxf(y_g, lerpf(0.18, y_g, smoothstep(0.0, 0.14, t)))

				var v_pos: Vector3
				var v_col: Color
				if oi == 2:
					# Narrow incandescent molten yellow-gold spine proud of the basalt cliff.
					v_pos = Vector3(p_xz.x, y_g + 0.40, p_xz.y) + n_loc * 0.42
					v_col = COL_CALDERA_MAGMA_CORE.lerp(COL_CALDERA_MAGMA_MID, cool)
				elif oi == 1 or oi == 3:
					# Blazing orange-red molten margins snapped proud of surface_height + 0.35.
					v_pos = Vector3(p_xz.x, y_g + 0.35, p_xz.y) + n_loc * 0.30
					v_col = col_rim_hot.lerp(COL_CALDERA_MAGMA_RIM, 0.25 + cool * 0.62)
				else:
					# Charred dark crimson-obsidian outer lips tucked firmly into the cliff slope.
					v_pos = Vector3(p_xz.x, y_g - 0.15, p_xz.y) - n_loc * 0.12
					v_col = col_scorch

				row_p.append(v_pos)
				row_c.append(v_col)

			rows_pts.append(row_p)
			rows_cols.append(row_c)
			rows_norms.append(center_n_loc)

		for i in STEPS:
			var p0: Array[Vector3] = rows_pts[i]
			var p1: Array[Vector3] = rows_pts[i + 1]
			var c0: Array[Color] = rows_cols[i]
			var c1: Array[Color] = rows_cols[i + 1]
			var out_n := (rows_norms[i] + rows_norms[i + 1]).normalized()
			for oi in OFFSETS.size() - 1:
				_grotto_quad_oriented(st, p0[oi], p0[oi + 1], p1[oi + 1], p1[oi],
					c0[oi], c0[oi + 1], c1[oi + 1], c1[oi], out_n)

	st.generate_normals()
	return st.commit()


static func _make_volcano_ash_ramp() -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.10, 0.28, 0.72, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.42, 0.10, 0.0),
		Color(0.92, 0.34, 0.12, 0.86),
		Color(0.18, 0.15, 0.18, 0.82),
		Color(0.24, 0.23, 0.28, 0.50),
		Color(0.34, 0.34, 0.38, 0.0),
	])
	var tex := GradientTexture1D.new()
	tex.width = 32
	tex.gradient = grad
	return tex


static func _make_volcano_ember_ramp() -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.68, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.96, 0.68, 1.0),
		Color(1.0, 0.56, 0.12, 0.96),
		Color(0.95, 0.20, 0.04, 0.68),
		Color(0.48, 0.05, 0.01, 0.0),
	])
	var tex := GradientTexture1D.new()
	tex.width = 32
	tex.gradient = grad
	return tex


static func _build_island_fireflies(island: Island, arch: StringName, landing_yaw: float) -> void:
	# Position firefly swarm gently over the island's warm inland palm grove / campfire clearing.
	var glade_xz := Vector3.ZERO
	var lb := Basis(Vector3.UP, landing_yaw)
	if island.is_outpost:
		glade_xz = lb * Vector3(-4.0, 0.0, -10.0)
	elif arch == &"smuggler_cove":
		glade_xz = lb * Vector3(0.0, 0.0, 5.5)
	elif not island.dig_points.is_empty():
		var dp0 := island.dig_points[0]
		glade_xz = Vector3(dp0.x * 0.72, 0.0, dp0.z * 0.72)
	else:
		glade_xz = lb * Vector3(0.0, 0.0, -island.island_radius * 0.35)
	var ground_y := maxf(island.surface_height(glade_xz.x, glade_xz.z), 1.0)

	var p := GPUParticles3D.new()
	p.name = "IslandFireflies"
	p.position = Vector3(glade_xz.x, ground_y + 2.4, glade_xz.z)
	p.amount = 36
	p.lifetime = 4.6
	p.preprocess = 2.5
	p.randomness = 0.45
	p.local_coords = true
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-22.0, -6.0, -22.0), Vector3(44.0, 14.0, 44.0))
	p.emitting = false
	p.visible = false

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(14.5, 2.2, 14.5)
	proc.direction = Vector3.UP
	proc.spread = 180.0
	proc.initial_velocity_min = 0.14
	proc.initial_velocity_max = 0.42
	proc.gravity = Vector3(0.0, 0.04, 0.0)
	proc.damping_min = 0.35
	proc.damping_max = 0.65
	proc.turbulence_enabled = true
	proc.turbulence_noise_strength = 0.95
	proc.turbulence_noise_scale = 2.6
	proc.turbulence_influence_min = 0.35
	proc.turbulence_influence_max = 0.65
	proc.scale_min = 0.55
	proc.scale_max = 1.25

	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.15))
	sc.add_point(Vector2(0.24, 1.0))
	sc.add_point(Vector2(0.54, 0.62))
	sc.add_point(Vector2(0.78, 1.08))
	sc.add_point(Vector2(1.0, 0.10))
	var sc_tex := CurveTexture.new()
	sc_tex.curve = sc
	proc.scale_curve = sc_tex

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.18, 0.48, 0.78, 1.0])
	grad.colors = PackedColorArray([
		Color(0.95, 0.98, 0.45, 0.0),
		Color(0.92, 1.00, 0.46, 0.94),
		Color(1.00, 0.80, 0.28, 0.86),
		Color(0.96, 0.96, 0.38, 0.74),
		Color(1.00, 0.72, 0.20, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.width = 32
	ramp.gradient = grad
	proc.color_ramp = ramp
	p.process_material = proc

	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 0.18)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Island.get_firefly_glow_texture()
	quad.material = mat
	p.draw_pass_1 = quad

	island.add_child(p)
	island.register_fireflies(p)

