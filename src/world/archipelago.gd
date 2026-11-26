class_name Archipelago
extends Node3D
## Deterministic 11-island archipelago spanning ~2400 m x 2400 m with >320 m
## open sailing channels between every island pair.
##
## Port Scoundrel (Outpost 0) sits near the origin with its dock facing NNE
## straight toward Cutlass Cay (~446 m away on the horizon). Every island has a
## distinct original name, sculpted landmark silhouette, walkable sandy beach,
## coastline contour polygon, and discovery tracking through `Game.profile`.

signal island_discovered(island: Island)

const DISCOVERY_MARGIN := 95.0

## Canonical 11-island deterministic archipelago layout.
## Angles: dock_yaw / landing_yaw rotates local -Z (seaward pier or landing cove)
## using Basis(Vector3.UP, yaw): negative yaw turns -Z eastward (+X), positive westward (-X).
const ISLAND_SPECS: Array[Dictionary] = [
	{
		"id": "port_scoundrel",
		"name": "Port Scoundrel",
		"archetype": &"outpost",
		"kind": &"outpost",
		"position": Vector3(0.0, 0.0, 0.0),
		"radius": 62.0,
		"peak_height": 48.0,
		# Dock faces NNE (~21 deg E of -Z), aiming straight toward Cutlass Cay on the horizon!
		"dock_yaw": -0.37,
		"seed": 1101,
		"landmarks": ["Scoundrel's Pier", "Harbour Beacon", "Salty Lantern Tavern"],
	},
	{
		"id": "cutlass_cay",
		"name": "Cutlass Cay",
		"archetype": &"treasure_peak",
		"kind": &"treasure_island",
		"position": Vector3(165.0, 0.0, -415.0),
		"radius": 52.0,
		"peak_height": 68.0,
		# Landing beach faces SSW straight back toward Port Scoundrel!
		"landing_yaw": 2.77,
		"seed": 2203,
		"spawn_default_dig_site": true,
		"default_treasure_id": &"wayfarer_chest",
		"landmarks": ["Cutlass Twin Spires", "Golden Cove", "Split Palm"],
	},
	{
		"id": "barnacle_haven",
		"name": "Barnacle Haven",
		"archetype": &"outpost",
		"kind": &"outpost",
		"position": Vector3(-680.0, 0.0, 620.0),
		"radius": 60.0,
		"peak_height": 46.0,
		# Dock faces NE toward the open central channel.
		"dock_yaw": -0.78,
		"seed": 3307,
		"landmarks": ["Barnacle Wharf", "Copper Beacon", "Driftwood Tavern"],
	},
	{
		"id": "gulls_arch",
		"name": "Gull's Arch",
		"archetype": &"sea_arch",
		"kind": &"treasure_island",
		"position": Vector3(-540.0, 0.0, -340.0),
		"radius": 56.0,
		"peak_height": 50.0,
		"landing_yaw": -2.15,
		"seed": 4409,
		"spawn_default_dig_site": true,
		"default_treasure_id": &"driftwood_chest",
		"landmarks": ["Great White Arch", "Tern Tide Bay", "Gull Bluff"],
	},
	{
		"id": "smugglers_cove",
		"name": "Smuggler's Cove",
		"archetype": &"smuggler_cove",
		"kind": &"treasure_island",
		"position": Vector3(740.0, 0.0, -180.0),
		"radius": 58.0,
		"peak_height": 56.0,
		"landing_yaw": 1.35,
		"seed": 5501,
		"spawn_default_dig_site": true,
		"default_treasure_id": &"corsair_chest",
		"landmarks": ["Amphitheatre Gate", "Hidden Beach", "Smuggler's Fire"],
	},
	{
		"id": "cinder_crag",
		"name": "Cinder Crag",
		"archetype": &"volcano_crag",
		"kind": &"landmark",
		"position": Vector3(-280.0, 0.0, -1080.0),
		"radius": 68.0,
		"peak_height": 90.0,
		"landing_yaw": 2.90,
		"seed": 6607,
		"landmarks": ["Obsidian Caldera", "Basalt Fang", "Ash Cove"],
	},
	{
		"id": "skull_bluff",
		"name": "Skull Bluff",
		"archetype": &"skull_bluff",
		"kind": &"treasure_island",
		"position": Vector3(820.0, 0.0, -940.0),
		"radius": 60.0,
		"peak_height": 64.0,
		"landing_yaw": 2.35,
		"seed": 7703,
		"spawn_default_dig_site": true,
		"default_treasure_id": &"corsair_chest",
		"landmarks": ["Skull Brow", "High Limestone Crown", "South Sand Spit"],
	},
	{
		"id": "crescent_atoll",
		"name": "Crescent Atoll",
		"archetype": &"crescent_lagoon",
		"kind": &"treasure_island",
		"position": Vector3(640.0, 0.0, 560.0),
		"radius": 64.0,
		"peak_height": 34.0,
		"landing_yaw": 0.72,
		"seed": 8803,
		"spawn_default_dig_site": true,
		"default_treasure_id": &"wayfarer_chest",
		"landmarks": ["Turquoise Lagoon", "Twin Palm Horns", "Coral Crag"],
	},
	{
		"id": "ironwatch_fort",
		"name": "Ironwatch Fort",
		"archetype": &"fort_rock",
		"kind": &"fort",
		"position": Vector3(-1020.0, 0.0, -820.0),
		"radius": 56.0,
		"peak_height": 42.0,
		"landing_yaw": -2.35,
		"seed": 9901,
		"landmarks": ["Sea Bastion", "Ironwatch Terrace", "Powder Cove"],
	},
	{
		"id": "wreckers_shoal",
		"name": "Wrecker's Shoal",
		"archetype": &"wreck_shoal",
		"kind": &"shipwreck",
		"position": Vector3(40.0, 0.0, 760.0),
		"radius": 54.0,
		"peak_height": 40.0,
		"landing_yaw": 0.05,
		"seed": 10903,
		"spawn_default_dig_site": true,
		"default_treasure_id": &"wayfarer_chest",
		"landmarks": ["Broken Hull", "Barnacle Mast", "Wrecker's Sandbar"],
	},
	{
		"id": "emerald_spire",
		"name": "Emerald Spire",
		"archetype": &"twin_spires",
		"kind": &"landmark",
		"position": Vector3(-1100.0, 0.0, 120.0),
		"radius": 58.0,
		"peak_height": 82.0,
		"landing_yaw": -1.42,
		"seed": 12007,
		"landmarks": ["Emerald Needles", "Mossy Saddle", "East Cove"],
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


## Deterministically build all 11 islands if not already constructed.
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
			var reef_density := 1.15 if isl.archetype in [&"crescent_lagoon", &"wreck_shoal", &"palm_atoll"] else 0.80
			CoralReef.populate_for_island(isl, int(spec.get("seed", 1000)) + 77, reef_density)
		# Populate 1-DC tropical reef fish schools hovering over shallow turquoise coral gardens (culled > 75 m).
		if isl.archetype in [
			&"crescent_lagoon", &"wreck_shoal", &"palm_atoll",
			&"treasure_peak", &"treasure_cove", &"smuggler_cove",
			&"outpost", &"outpost_harbour", &"sea_arch",
		]:
			ReefFishSchool.populate_for_island(isl, int(spec.get("seed", 1000)) + 131)
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
