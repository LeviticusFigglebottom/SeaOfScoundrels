class_name Archipelago
extends Node3D
## Deterministic 14-island multi-tier archipelago spanning ~4.0 km x 4.0 km with
## >= 353 m open sailing channels between all 91 island pairs.
##
## Islands span 4 dramatic scale tiers from tiny 38 m sea-stacks (Siren's Tooth)
## and 46-54 m starter cays up to massive 166-182 m flagship islands (Cinder Crag,
## Sovereign's Bastion, Galleon's Reach). Port Scoundrel (Outpost 0) sits near the
## origin with its dock facing NNE straight toward Cutlass Cay (~490 m away).

signal island_discovered(island: Island)

const DISCOVERY_MARGIN := 95.0

## Canonical 14-island deterministic archipelago layout across 4 size tiers.
## Angles: dock_yaw / landing_yaw rotates local -Z (seaward pier or landing cove)
## using Basis(Vector3.UP, yaw): negative yaw turns -Z eastward (+X), positive westward (-X).
const ISLAND_SPECS: Array[Dictionary] = [
	# --- Tier 2 Outpost 0 (Home Port) ---
	{
		"id": "port_scoundrel",
		"name": "Port Scoundrel",
		"archetype": &"outpost",
		"kind": &"outpost",
		"position": Vector3(0.0, 0.0, 0.0),
		"radius": 82.0,
		"peak_height": 54.0,
		# Dock faces NNE (~21 deg E of -Z), aiming straight toward Cutlass Cay on the horizon!
		"dock_yaw": -0.37,
		"seed": 1101,
		"landmarks": ["Scoundrel's Pier", "Harbour Beacon", "Salty Lantern Tavern"],
	},
	# --- Tier 1 Starter Treasure Cay ---
	{
		"id": "cutlass_cay",
		"name": "Cutlass Cay",
		"archetype": &"treasure_peak",
		"kind": &"treasure_island",
		"position": Vector3(178.0, 0.0, -456.0),
		"radius": 54.0,
		"peak_height": 66.0,
		# Landing beach faces SSW straight back toward Port Scoundrel!
		"landing_yaw": 2.77,
		"seed": 2203,
		"spawn_default_dig_site": true,
		"default_treasure_id": &"wayfarer_chest",
		"landmarks": ["Cutlass Twin Spires", "Golden Cove", "Split Palm"],
	},
	# --- Tier 2 Outpost 1 ---
	{
		"id": "barnacle_haven",
		"name": "Barnacle Haven",
		"archetype": &"outpost",
		"kind": &"outpost",
		"position": Vector3(-920.0, 0.0, 760.0),
		"radius": 78.0,
		"peak_height": 48.0,
		# Dock faces NE toward the open central channel.
		"dock_yaw": -0.78,
		"seed": 3307,
		"landmarks": ["Barnacle Wharf", "Copper Beacon", "Driftwood Tavern"],
	},
	# --- Tier 2 Coastal Arch Island ---
	{
		"id": "gulls_arch",
		"name": "Gull's Arch",
		"archetype": &"sea_arch",
		"kind": &"treasure_island",
		"position": Vector3(-640.0, 0.0, -420.0),
		"radius": 82.0,
		"peak_height": 58.0,
		"landing_yaw": -2.15,
		"seed": 4409,
		"spawn_default_dig_site": true,
		"default_treasure_id": &"driftwood_chest",
		"landmarks": ["Great White Arch", "Tern Tide Bay", "Gull Bluff"],
	},
	# --- Tier 2 Smuggler's Amphitheatre ---
	{
		"id": "smugglers_cove",
		"name": "Smuggler's Cove",
		"archetype": &"smuggler_cove",
		"kind": &"treasure_island",
		"position": Vector3(860.0, 0.0, -210.0),
		"radius": 96.0,
		"peak_height": 64.0,
		"landing_yaw": 1.35,
		"seed": 5501,
		"spawn_default_dig_site": true,
		"default_treasure_id": &"corsair_chest",
		"landmarks": ["Amphitheatre Gate", "Hidden Beach", "Smuggler's Fire"],
	},
	# --- Tier 4 Massive Stratovolcano ---
	{
		"id": "cinder_crag",
		"name": "Cinder Crag",
		"archetype": &"volcano_crag",
		"kind": &"landmark",
		"position": Vector3(-320.0, 0.0, -1420.0),
		"radius": 176.0,
		"peak_height": 132.0,
		"landing_yaw": 2.90,
		"seed": 6607,
		"landmarks": ["Obsidian Caldera", "Basalt Fangs", "Fumarole Terraces"],
	},
	# --- Tier 3 Multi-Biome Highland Headland ---
	{
		"id": "skull_bluff",
		"name": "Skull Bluff",
		"archetype": &"skull_bluff",
		"kind": &"treasure_island",
		"position": Vector3(1060.0, 0.0, -1120.0),
		"radius": 124.0,
		"peak_height": 78.0,
		"landing_yaw": 2.35,
		"seed": 7703,
		"spawn_default_dig_site": true,
		"default_treasure_id": &"corsair_chest",
		"landmarks": ["Skull Brow", "High Limestone Crown", "South Sand Spit"],
	},
	# --- Tier 3 Grand Coral Lagoon ---
	{
		"id": "crescent_atoll",
		"name": "Crescent Atoll",
		"archetype": &"crescent_lagoon",
		"kind": &"treasure_island",
		"position": Vector3(820.0, 0.0, 740.0),
		"radius": 134.0,
		"peak_height": 44.0,
		"landing_yaw": 0.72,
		"seed": 8803,
		"spawn_default_dig_site": true,
		"default_treasure_id": &"wayfarer_chest",
		"landmarks": ["Turquoise Lagoon", "Twin Palm Horns", "Coral Crag"],
	},
	# --- Tier 2 Sea Fort ---
	{
		"id": "ironwatch_fort",
		"name": "Ironwatch Fort",
		"archetype": &"fort_rock",
		"kind": &"fort",
		"position": Vector3(-1240.0, 0.0, -960.0),
		"radius": 92.0,
		"peak_height": 52.0,
		"landing_yaw": -2.35,
		"seed": 9901,
		"landmarks": ["Sea Bastion", "Ironwatch Terrace", "Powder Cove"],
	},
	# --- Tier 1 Shipwreck Sandbar ---
	{
		"id": "wreckers_shoal",
		"name": "Wrecker's Shoal",
		"archetype": &"wreck_shoal",
		"kind": &"shipwreck",
		"position": Vector3(90.0, 0.0, 820.0),
		"radius": 46.0,
		"peak_height": 36.0,
		"landing_yaw": 0.05,
		"seed": 10903,
		"spawn_default_dig_site": true,
		"default_treasure_id": &"wayfarer_chest",
		"landmarks": ["Broken Hull", "Barnacle Mast", "Wrecker's Sandbar"],
	},
	# --- Tier 3 Twin Cathedral Massifs & Waterfall Canyon ---
	{
		"id": "emerald_spire",
		"name": "Emerald Spire",
		"archetype": &"twin_spires",
		"kind": &"landmark",
		"position": Vector3(-1360.0, 0.0, 140.0),
		"radius": 138.0,
		"peak_height": 98.0,
		"landing_yaw": -1.42,
		"seed": 12007,
		"landmarks": ["Emerald Needles", "Waterfall Saddle", "East Cove"],
	},
	# --- Tier 1 Tiny Sea-Stack Monolith (NEW) ---
	{
		"id": "sirens_tooth",
		"name": "Siren's Tooth",
		"archetype": &"sea_stack",
		"kind": &"landmark",
		"position": Vector3(-420.0, 0.0, 310.0),
		"radius": 38.0,
		"peak_height": 54.0,
		"landing_yaw": -0.62,
		"seed": 13109,
		"landmarks": ["Siren's Fang", "Tide Chasm", "Coral Shelf"],
	},
	# --- Tier 4 Massive Sovereign Grand Citadel (NEW) ---
	{
		"id": "sovereigns_bastion",
		"name": "Sovereign's Bastion",
		"archetype": &"grand_citadel",
		"kind": &"fort",
		"position": Vector3(1560.0, 0.0, 120.0),
		"radius": 182.0,
		"peak_height": 96.0,
		"landing_yaw": 1.72,
		"seed": 14207,
		"spawn_default_dig_site": true,
		"default_treasure_id": &"sovereign_chest",
		"landmarks": ["Sovereign Citadel", "Temple Terraces", "Cascade Falls"],
	},
	# --- Tier 4 Massive Capital Port Outpost 2 (NEW) ---
	{
		"id": "galleons_reach",
		"name": "Galleon's Reach",
		"archetype": &"grand_outpost",
		"kind": &"outpost",
		"position": Vector3(-140.0, 0.0, 1520.0),
		"radius": 166.0,
		"peak_height": 76.0,
		"dock_yaw": 0.12,
		"seed": 15313,
		"landmarks": ["Grand Wharf", "Headland Bastions", "Sovereign Beacon"],
	},
]

@export var auto_build: bool = true

var islands: Array[Island] = []
var _outposts: Array[Outpost] = []
var _by_id: Dictionary = {}  # String -> Island
var _built: bool = false


func _ready() -> void:
	if auto_build and not _built:
		build_archipelago()


## Deterministically build all 14 islands if not already constructed.
func build_archipelago() -> void:
	if _built:
		return
	_built = true
	islands.clear()
	_outposts.clear()
	_by_id.clear()

	for spec in ISLAND_SPECS:
		var isl := IslandGenerator.build_island(spec)
		isl.position = spec["position"] as Vector3
		add_child(isl)
		# Populate shallow underwater coral & swaying kelp gardens (<= 3 MultiMesh DC, distance-culled > 155 m).
		if isl.archetype != &"volcano_crag":
			var reef_density := 1.20 if isl.archetype in [
				&"crescent_lagoon", &"wreck_shoal", &"palm_atoll", &"sea_stack", &"grand_outpost",
			] else 0.85
			CoralReef.populate_for_island(isl, int(spec.get("seed", 1000)) + 77, reef_density)
		# Populate 1-DC tropical reef fish schools hovering over shallow turquoise coral gardens (culled > 75 m).
		if isl.archetype in [
			&"crescent_lagoon", &"wreck_shoal", &"palm_atoll",
			&"treasure_peak", &"treasure_cove", &"smuggler_cove",
			&"outpost", &"outpost_harbour", &"grand_outpost",
			&"sea_arch", &"sea_stack", &"grand_citadel",
		]:
			ReefFishSchool.populate_for_island(isl, int(spec.get("seed", 1000)) + 131)
		# Populate peaceful gliding Giant Reef Manta Rays across sunlit tropical lagoons (culled > 85 m).
		if isl.archetype in [
			&"crescent_lagoon", &"palm_atoll", &"wreck_shoal",
			&"treasure_peak", &"treasure_cove", &"sea_stack", &"grand_outpost",
		]:
			MantaRay.populate_for_island(isl, int(spec.get("seed", 1000)) + 211)
		islands.append(isl)
		_by_id[isl.island_id] = isl
		if isl is Outpost:
			_outposts.append(isl as Outpost)


func get_islands() -> Array[Island]:
	if not _built:
		build_archipelago()
	return islands


func get_outposts() -> Array[Outpost]:
	if not _built:
		build_archipelago()
	return _outposts


func get_outpost(index: int = 0) -> Outpost:
	if not _built:
		build_archipelago()
	if _outposts.is_empty():
		return null
	return _outposts[clampi(index, 0, _outposts.size() - 1)]


func get_island_by_id(id: String) -> Island:
	if not _built:
		build_archipelago()
	return _by_id.get(id, null) as Island


func get_starter_treasure_island() -> Island:
	var starter := get_island_by_id("cutlass_cay")
	if starter != null:
		return starter
	for isl in get_islands():
		if not isl.is_outpost:
			return isl
	return null


## Maximum shore proximity factor (0..1) across all islands at `world_pos`.
func nearest_shore_factor(world_pos: Vector3) -> float:
	if not _built:
		build_archipelago()
	var best := 0.0
	for isl in islands:
		var f := isl.shore_factor(world_pos)
		if f > best:
			best = f
	return best


## Closest island to `world_pos` (horizontal XZ distance to island center).
func nearest_island(world_pos: Vector3) -> Island:
	if not _built:
		build_archipelago()
	var best: Island = null
	var best_d2 := INF
	for isl in islands:
		var pos := isl.global_position if isl.is_inside_tree() else isl.position
		var dx := world_pos.x - pos.x
		var dz := world_pos.z - pos.z
		var d2 := dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best = isl
	return best


## Check whether `world_pos` discovers an uncharted island (host-authoritative).
## Returns the newly discovered `Island` on first discovery, otherwise `null`.
func check_discovery(world_pos: Vector3) -> Island:
	if not Net.is_host():
		return null
	if not _built:
		build_archipelago()
	for isl in islands:
		var pos := isl.global_position if isl.is_inside_tree() else isl.position
		var dist_xz := Vector2(world_pos.x - pos.x, world_pos.z - pos.z).length()
		if dist_xz <= isl.island_radius + DISCOVERY_MARGIN:
			if Game.profile.discover(isl.island_id):
				Game.post_notice("Discovered %s!" % isl.display_name)
				island_discovered.emit(isl)
				return isl
	return null


## Map table, held treasure map, and VoyageComposer island roster payload.
func get_map_data() -> Array[Dictionary]:
	if not _built:
		build_archipelago()
	var out: Array[Dictionary] = []
	for isl in islands:
		out.append(isl.get_map_entry())
	return out
