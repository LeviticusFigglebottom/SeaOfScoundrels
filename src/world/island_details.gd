class_name IslandDetails
extends Node3D
## Batched MultiMesh 3D ground cover, coastal shoreline dressing, walkable 3D trail
## flagstones/curbs, living tropical butterflies, scuttling tidepool crabs, and
## steep-slope sculptural cliff buttresses for every island across the archipelago.
##
## Replaces bare flat 2D terrain slopes and smooth cliff cones with 8–11 strictly
## batched `MultiMeshInstance3D` draw calls (ZERO raw `PrimitiveMesh`es, shadowless,
## radius-scaled distance culling):
##   1. `GrassClumps`          — 28-blade slender 3-tuft swaying grass + 3 golden plumed seed-stalks (`foliage_wind.gdshader`)
##   2. `JungleFerns`          — 10-frond 2-tier pinnate serrated fern rosettes (`foliage_wind.gdshader`)
##   3. `HibiscusShrubs`       — 16-leaf 3-tier tropical bushes crowned with 6 vivid 5-petal blossoms (`foliage_wind.gdshader`)
##   4. `CoastalDriftwood`     — gnarled silver-brown forked driftwood logs with root-claws, sea-kelp & barnacles aligned to coastline contours
##   5. `ShorePebblesShells`   — 5 beveled beach cobbles, fluted spiral shell & 5-arm coral sea star along wet/dry sand
##   6. `TidalOutcrops`        — undercut stratified barnacle-ringed coastal rock clusters emerging from tide pools & surf
##   7. `CliffButtresses`      — steep-slope (`0.12 < normal.y < 0.72`) sculptural cliff crags (GLB w/ `col_*` stripped or procedural fallback)
##   8. `CliffButtressesWide`  — optional wide stepped cliff ledges on medium/large non-volcanic islands (`r >= 75 m`)
##   9. `TrailSteppingStones`  — beveled coastal trail flagstones, sloped terrace stair-slabs & border curb stones
##  10. `IslandButterflies`    — animated sculpted tropical swallowtail butterflies fluttering above hibiscus glades & trails
##  11. `ShoreCrabs`           — animated sculpted coastal tidepool crabs scuttling sideways along wet sandy beaches

const GROUP := &"island_details"
const FOLIAGE_SHADER: Shader = preload("res://src/world/foliage_wind.gdshader")

const GLB_BUTTRESS_TALL := "res://assets/generated/landmarks/cliff_buttress_tall.glb"
const GLB_BUTTRESS_WIDE := "res://assets/generated/landmarks/cliff_buttress_wide.glb"
const GLB_VOLCANIC_SPIRE := "res://assets/generated/landmarks/volcanic_basalt_spire.glb"

const DIG_KEEPOUT_RADIUS := 3.2
const MOORING_KEEPOUT_RADIUS := 10.5
const PIER_KEEPOUT_RADIUS := 6.0

const BUTTRESS_MIN_NORMAL_Y := 0.12
const BUTTRESS_MAX_NORMAL_Y := 0.72
const WIDE_BUTTRESS_MIN_RADIUS := 75.0
const BUTTERFLY_CULL_DIST := 160.0
const CRAB_CULL_DIST := 135.0
const FOLIAGE_SUN_HEADROOM := 1.08
const WET_SHORE_MAX_H := 0.95
const WET_SHORE_SPAN := 0.85

# ------------------------------------------------------------------ sRGB palettes
# Note: `foliage_wind.gdshader` reads COLOR.rgb directly in LINEAR space, so all
# foliage vertex/instance colors are converted via `.srgb_to_linear()` before upload.
# Coastal, trail stone, butterfly & fallback rock meshes use `StandardMaterial3D` with `vertex_color_is_srgb = true`.

const GRASS_TROPICAL_PALETTE: Array[Color] = [
	Color(0.22, 0.60, 0.18, 1.0),  # Rich tropical emerald
	Color(0.32, 0.67, 0.19, 1.0),  # Sunlit meadow green
	Color(0.45, 0.72, 0.20, 1.0),  # Bright chartreuse lime
	Color(0.18, 0.52, 0.21, 1.0),  # Deep shaded jade
	Color(0.38, 0.66, 0.22, 1.0),  # Warm leaf green
]

const GRASS_VERGE_PALETTE: Array[Color] = [
	Color(0.68, 0.64, 0.26, 1.0),  # Warm golden dry coastal sedge
	Color(0.58, 0.64, 0.23, 1.0),  # Sun-bleached beach tussock
	Color(0.74, 0.66, 0.30, 1.0),  # Honey-straw dune grass
	Color(0.49, 0.62, 0.22, 1.0),  # Olive-gold verge tuft
]

const GRASS_VOLCANIC_PALETTE: Array[Color] = [
	Color(0.46, 0.44, 0.20, 1.0),  # Hardy golden-olive ash sedge
	Color(0.35, 0.36, 0.18, 1.0),  # Scorched olive tussock
	Color(0.52, 0.43, 0.21, 1.0),  # Warm ochre cinder grass
	Color(0.29, 0.31, 0.19, 1.0),  # Charred highland scrub
]

const GRASS_HIGHLAND_PALETTE: Array[Color] = [
	Color(0.24, 0.56, 0.19, 1.0),  # Sun-dappled alpine emerald
	Color(0.35, 0.62, 0.20, 1.0),  # Warm sunlit highland olive-green
	Color(0.19, 0.49, 0.21, 1.0),  # Deep cliff-ledge moss jade
	Color(0.43, 0.65, 0.23, 1.0),  # Sun-kissed ridge chartreuse
	Color(0.30, 0.54, 0.18, 1.0),  # Hardy coastal-cliff olive
]

const FERN_TROPICAL_PALETTE: Array[Color] = [
	Color(0.18, 0.58, 0.22, 1.0),  # Deep jungle fern emerald
	Color(0.26, 0.66, 0.22, 1.0),  # Sunlit tropical frond
	Color(0.14, 0.50, 0.24, 1.0),  # Cool shaded canopy jade
	Color(0.36, 0.70, 0.21, 1.0),  # Bright chartreuse crown
]

const FERN_HIGHLAND_PALETTE: Array[Color] = [
	Color(0.16, 0.55, 0.21, 1.0),  # Deep cliff-crevice emerald fern
	Color(0.25, 0.64, 0.21, 1.0),  # Sun-dappled ledge frond
	Color(0.13, 0.47, 0.23, 1.0),  # Cool canyon-shade jade fern
	Color(0.34, 0.68, 0.20, 1.0),  # Sunlit cascading ridge frond
]

const FERN_VOLCANIC_PALETTE: Array[Color] = [
	Color(0.34, 0.40, 0.20, 1.0),  # Hardy ash-fern olive
	Color(0.42, 0.42, 0.19, 1.0),  # Bronze-olive cinder fern
	Color(0.28, 0.34, 0.19, 1.0),  # Deep scorched moss fern
]

# Hibiscus meshes bake rich saturated emerald leaves + vivid crimson/pink/orange/gold
# blossoms directly into linear vertex colors; instance tints apply subtle painterly shift.
const HIBISCUS_TROPICAL_TINTS: Array[Color] = [
	Color(1.00, 0.99, 0.97, 1.0),  # True vibrant blossom mix
	Color(1.04, 0.96, 0.92, 1.0),  # Warm coral-sunset lean
	Color(0.95, 1.02, 0.95, 1.0),  # Lush cool-jade foliage lean
	Color(1.03, 0.98, 0.88, 1.0),  # Golden sunlit tropical lean
	Color(0.98, 0.94, 1.02, 1.0),  # Hibiscus-magenta pop lean
]

const HIBISCUS_VOLCANIC_TINTS: Array[Color] = [
	Color(0.84, 0.68, 0.52, 1.0),  # Warm volcanic ember-scrub
	Color(0.76, 0.64, 0.50, 1.0),  # Charred cinder-blossom
	Color(0.88, 0.74, 0.54, 1.0),  # Golden ash-bloom scrub
]

const DRIFTWOOD_PALETTE: Array[Color] = [
	Color(0.96, 0.93, 0.88, 1.0),  # Sun-bleached silver driftwood
	Color(0.86, 0.79, 0.70, 1.0),  # Weathered warm oak-drift
	Color(0.92, 0.86, 0.76, 1.0),  # Salt-washed coastal timber
	Color(0.78, 0.71, 0.62, 1.0),  # Damp storm-washed log
]

const DRIFTWOOD_VOLCANIC_PALETTE: Array[Color] = [
	Color(0.50, 0.46, 0.43, 1.0),  # Charred ash-washed driftwood
	Color(0.62, 0.56, 0.50, 1.0),  # Singed coastal timber
	Color(0.42, 0.40, 0.39, 1.0),  # Dark charcoal-grey drift
]

const PEBBLE_PALETTE: Array[Color] = [
	Color(0.98, 0.95, 0.90, 1.0),  # Pale coral cobbles & cream shell
	Color(0.92, 0.87, 0.80, 1.0),  # Warm sandstone beach pebbles
	Color(0.85, 0.84, 0.80, 1.0),  # Smooth coastal limestone mix
	Color(0.96, 0.90, 0.82, 1.0),  # Sun-warmed ochre beach stones
]

const PEBBLE_VOLCANIC_PALETTE: Array[Color] = [
	Color(0.44, 0.42, 0.44, 1.0),  # Smooth basalt shore pebbles
	Color(0.54, 0.50, 0.48, 1.0),  # Ash-worn volcanic cobbles
	Color(0.36, 0.35, 0.38, 1.0),  # Dark obsidian-slate shingle
]

const TIDAL_ROCK_PALETTE: Array[Color] = [
	Color(0.98, 0.94, 0.87, 1.0),  # Warm sunlit limestone outcrop
	Color(0.90, 0.85, 0.78, 1.0),  # Weathered ochre reef rock
	Color(0.84, 0.84, 0.80, 1.0),  # Sea-bleached coastal crag
	Color(0.95, 0.87, 0.76, 1.0),  # Golden sandstone tide rock
]

const TIDAL_ROCK_VOLCANIC_PALETTE: Array[Color] = [
	Color(0.38, 0.36, 0.40, 1.0),  # Wet charred coastal basalt
	Color(0.46, 0.43, 0.45, 1.0),  # Ash-dusted tidal crag
	Color(0.32, 0.31, 0.35, 1.0),  # Deep obsidian surf rock
]

const BUTTRESS_FALLBACK_LIMESTONE: Array[Color] = [
	Color(0.94, 0.83, 0.67, 1.0),  # Warm ochre-limestone cliff
	Color(0.98, 0.91, 0.78, 1.0),  # Sunlit pale limestone buttress
	Color(0.87, 0.76, 0.62, 1.0),  # Terracotta-streaked coastal rock
	Color(0.91, 0.84, 0.72, 1.0),  # Weathered honey crag
]

const BUTTRESS_FALLBACK_PALE: Array[Color] = [
	Color(0.99, 0.95, 0.86, 1.0),  # Chalky ivory sea-arch limestone
	Color(0.94, 0.88, 0.78, 1.0),  # Sun-bleached white-ochre bluff
	Color(0.89, 0.83, 0.74, 1.0),  # Pale travertine crag
]

const BUTTRESS_FALLBACK_VOLCANIC: Array[Color] = [
	Color(0.34, 0.31, 0.34, 1.0),  # Charred columnar basalt
	Color(0.42, 0.37, 0.38, 1.0),  # Weathered ash-basalt spire
	Color(0.28, 0.26, 0.30, 1.0),  # Deep obsidian cliff rib
	Color(0.48, 0.36, 0.32, 1.0),  # Rust-scorched caldera crag
]

const STEPPING_STONE_TROPICAL_PALETTE: Array[Color] = [
	Color(0.79, 0.71, 0.56, 1.0),  # Dusty ochre coastal sandstone
	Color(0.83, 0.76, 0.62, 1.0),  # Sun-warmed weathered flagstone
	Color(0.74, 0.64, 0.49, 1.0),  # Deep earth-toned trail paver
	Color(0.72, 0.66, 0.56, 1.0),  # Salt-worn dusty coastal travertine
]

const STEPPING_STONE_VOLCANIC_PALETTE: Array[Color] = [
	Color(0.33, 0.32, 0.36, 1.0),  # Dark volcanic basalt slab
	Color(0.42, 0.40, 0.43, 1.0),  # Ash-dusted charcoal flagstone
	Color(0.27, 0.26, 0.30, 1.0),  # Deep obsidian trail paver
	Color(0.46, 0.38, 0.36, 1.0),  # Scorched iron-basalt curb stone
]

const STEPPING_STONE_SLATE_PALETTE: Array[Color] = [
	Color(0.67, 0.65, 0.54, 1.0),  # Moss-dusted highland sandstone-slate
	Color(0.72, 0.68, 0.58, 1.0),  # Warm weathered temple flagstone
	Color(0.69, 0.66, 0.55, 1.0),  # Lichen-warmed citadel ashlar
	Color(0.59, 0.60, 0.50, 1.0),  # Deep shaded ruin moss-stone
]

const STEPPING_SLATE_ARCHETYPES: Array[StringName] = [
	&"twin_spires",
	&"grand_citadel",
	&"fort_rock",
]

const BUTTERFLY_PALETTE: Array[Color] = [
	Color(1.0, 0.58, 0.14, 1.0),  # Monarch-orange
	Color(0.22, 0.72, 1.0, 1.0),  # Tropical morpho-blue
	Color(1.0, 0.92, 0.28, 1.0),  # Sunlit sulphur-yellow
	Color(1.0, 0.40, 0.58, 1.0),  # Hibiscus-coral
]

const CRAB_PALETTE: Array[Color] = [
	Color(1.0, 0.42, 0.24, 1.0),  # Sunset-coral
	Color(1.0, 0.56, 0.22, 1.0),  # Bright tide-orange
	Color(0.88, 0.28, 0.24, 1.0), # Mottled reef-crimson
	Color(0.92, 0.74, 0.48, 1.0), # Warm sandy-ochre
]

# Biome-specific micro-foliage & coastal accent modulators (pure spatial-hash driven, +0 DC).
const DUNE_SEA_OATS_COLOR := Color(1.06, 0.98, 0.72, 1.0)     # Warm sun-bleached golden sea-oats
const DUNE_COASTAL_SAGE_COLOR := Color(0.78, 0.82, 0.54, 1.0) # Dry salt-misted coastal sage

const VOLCANIC_CALDERA_SLATE := Color(0.56, 0.54, 0.44, 1.0)  # Charred olive-slate caldera scrub
const VOLCANIC_CALDERA_RUSSET := Color(0.82, 0.56, 0.36, 1.0) # Scorched burnt-russet tussock
const VOLCANIC_CALDERA_SULFUR := Color(0.96, 0.80, 0.42, 1.0) # Sulfur-gold ember-moss accent
const VOLCANIC_HIBISCUS_EMBER := Color(1.08, 0.58, 0.34, 1.0) # Scarce fiery crimson-orange blossom
const VOLCANIC_TIDAL_OBSIDIAN := Color(0.42, 0.41, 0.45, 1.0) # Rich dark wet obsidian-basalt shore

const LAGOON_ATOLL_ARCHETYPES: Array[StringName] = [
	&"crescent_lagoon",
	&"palm_atoll",
	&"sea_arch",
	&"treasure_peak",
]
const HIBISCUS_LAGOON_TINTS: Array[Color] = [
	Color(1.06, 0.84, 0.92, 1.0),  # Vibrant tropical coral-pink
	Color(1.08, 1.00, 0.74, 1.0),  # Sunlit mango-gold
	Color(1.04, 0.78, 0.78, 1.0),  # Bright island crimson
]
const LAGOON_TIDAL_CORAL := Color(1.08, 1.05, 0.96, 1.0)      # Sun-bleached pale coral-limestone

const HIGHLAND_RUIN_ARCHETYPES: Array[StringName] = [
	&"twin_spires",
	&"grand_citadel",
	&"fort_rock",
	&"skull_bluff",
]
const LUSH_JUNGLE_TEMPLE_ARCHETYPES: Array[StringName] = [
	&"twin_spires",
	&"grand_citadel",
	&"grand_outpost",
]
const HIGHLAND_ALPINE_MOSS := Color(0.18, 0.59, 0.31, 1.0)    # Sun-dappled alpine moss-emerald
const HIGHLAND_SAGE_OLIVE := Color(0.36, 0.57, 0.39, 1.0)     # Cool highland sage-olive
const HIGHLAND_RUIN_MOSS := Color(0.14, 0.52, 0.29, 1.0)      # Ancient cliff-ruin deep moss-jade
const HIGHLAND_LICHEN_SAGE := Color(0.42, 0.60, 0.41, 1.0)    # Weathered alpine cliff lichen
const JUNGLE_VALLEY_FERN_TINT := Color(0.84, 1.04, 0.82, 1.0) # Deep valley emerald-jade depth

# ------------------------------------------------------------------ shared static caches

static var _active_details: int = 0
static var _grass_mesh: ArrayMesh = null
static var _fern_mesh: ArrayMesh = null
static var _hibiscus_mesh: ArrayMesh = null
static var _driftwood_mesh: ArrayMesh = null
static var _pebbles_mesh: ArrayMesh = null
static var _tidal_rock_mesh: ArrayMesh = null
static var _fallback_buttress_mesh: ArrayMesh = null
static var _fallback_buttress_wide_mesh: ArrayMesh = null
static var _stepping_stone_mesh: ArrayMesh = null
static var _butterfly_mesh: ArrayMesh = null
static var _crab_mesh: ArrayMesh = null
static var _foliage_material: ShaderMaterial = null
static var _wood_stone_material: StandardMaterial3D = null
static var _pebble_material: StandardMaterial3D = null
static var _tidal_rock_material: StandardMaterial3D = null
static var _buttress_fallback_material: StandardMaterial3D = null
static var _stepping_stone_mat: StandardMaterial3D = null
static var _butterfly_mat: StandardMaterial3D = null
static var _crab_mat: StandardMaterial3D = null
static var _glb_mesh_cache: Dictionary = {}  # String path -> Mesh or null

# ------------------------------------------------------------------ instance state

var _owned_multimeshes: Array[MultiMeshInstance3D] = []
var _grass_mmi: MultiMeshInstance3D = null
var _fern_mmi: MultiMeshInstance3D = null
var _hibiscus_mmi: MultiMeshInstance3D = null
var _driftwood_mmi: MultiMeshInstance3D = null
var _pebbles_mmi: MultiMeshInstance3D = null
var _tidal_mmi: MultiMeshInstance3D = null
var _buttress_mmi: MultiMeshInstance3D = null
var _buttress_wide_mmi: MultiMeshInstance3D = null
var _stepping_stone_mmi: MultiMeshInstance3D = null
var _butterfly_mmi: MultiMeshInstance3D = null
var _crab_mmi: MultiMeshInstance3D = null

var _grass_count: int = 0
var _fern_count: int = 0
var _hibiscus_count: int = 0
var _driftwood_count: int = 0
var _pebbles_count: int = 0
var _tidal_count: int = 0
var _buttress_count: int = 0
var _buttress_wide_count: int = 0
var _stepping_stone_count: int = 0
var _butterfly_count: int = 0
var _crab_count: int = 0

var _placed_buttress_normals_y: PackedFloat32Array = PackedFloat32Array()
var _placed_grass_positions: PackedVector3Array = PackedVector3Array()
var _placed_pebble_positions: PackedVector3Array = PackedVector3Array()
var _butterfly_orbits: Array[Dictionary] = []
var _butterfly_clock: float = 0.0
var _crab_orbits: Array[Dictionary] = []
var _crab_clock: float = 0.0
var _island_radius: float = 60.0


func _enter_tree() -> void:
	add_to_group(GROUP)
	_active_details += 1


func _exit_tree() -> void:
	for mmi in _owned_multimeshes:
		if mmi != null and is_instance_valid(mmi):
			mmi.material_override = null
			mmi.multimesh = null
	_owned_multimeshes.clear()
	_grass_mmi = null
	_fern_mmi = null
	_hibiscus_mmi = null
	_driftwood_mmi = null
	_pebbles_mmi = null
	_tidal_mmi = null
	_buttress_mmi = null
	_buttress_wide_mmi = null
	_stepping_stone_mmi = null
	_butterfly_mmi = null
	_crab_mmi = null
	_placed_buttress_normals_y = PackedFloat32Array()
	_placed_grass_positions = PackedVector3Array()
	_placed_pebble_positions = PackedVector3Array()
	_butterfly_orbits.clear()
	_butterfly_clock = 0.0
	_crab_orbits.clear()
	_crab_clock = 0.0
	_active_details = maxi(0, _active_details - 1)
	if _active_details == 0:
		clear_shared_cache()


func _process(delta: float) -> void:
	var dt := clampf(delta, 0.0, 0.15)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() and get_viewport() != null else null
	var dist_sq := global_position.distance_squared_to(cam.global_position) if cam != null else 0.0

	if _butterfly_mmi != null and is_instance_valid(_butterfly_mmi) and not _butterfly_orbits.is_empty():
		var tod := fposmod(Weather.time_of_day, 24.0)
		var bf_active := tod >= 6.0 and tod <= 18.8 and Weather.storminess < 0.55
		_butterfly_mmi.visible = bf_active
		if bf_active:
			var bf_cull := maxf(BUTTERFLY_CULL_DIST, _island_radius + 105.0)
			if cam == null or dist_sq <= bf_cull * bf_cull:
				_butterfly_clock += dt
				var mm := _butterfly_mmi.multimesh
				if mm != null:
					var count := mini(_butterfly_orbits.size(), mm.instance_count)
					for i in count:
						mm.set_instance_transform(i, _compute_butterfly_transform(_butterfly_orbits[i], _butterfly_clock))

	if _crab_mmi != null and is_instance_valid(_crab_mmi) and not _crab_orbits.is_empty():
		var crab_active := Weather.storminess < 0.75
		_crab_mmi.visible = crab_active
		if crab_active:
			var crab_cull := maxf(CRAB_CULL_DIST, _island_radius + 80.0)
			if cam == null or dist_sq <= crab_cull * crab_cull:
				_crab_clock += dt
				var cmm := _crab_mmi.multimesh
				if cmm != null:
					var c_count := mini(_crab_orbits.size(), cmm.instance_count)
					for i in c_count:
						cmm.set_instance_transform(i, _compute_crab_transform(_crab_orbits[i], _crab_clock))


## Release all statically cached procedural meshes, materials, and extracted GLB meshes cleanly.
static func clear_shared_cache() -> void:
	_grass_mesh = null
	_fern_mesh = null
	_hibiscus_mesh = null
	_driftwood_mesh = null
	_pebbles_mesh = null
	_tidal_rock_mesh = null
	_fallback_buttress_mesh = null
	_fallback_buttress_wide_mesh = null
	_stepping_stone_mesh = null
	_butterfly_mesh = null
	_crab_mesh = null
	_foliage_material = null
	_wood_stone_material = null
	_pebble_material = null
	_tidal_rock_material = null
	_buttress_fallback_material = null
	_stepping_stone_mat = null
	_butterfly_mat = null
	_crab_mat = null
	_glb_mesh_cache.clear()


## Deterministically populate batched 3D ground cover, coastal shoreline dressing,
## walkable 3D trail stepping stones/curbs, living tropical butterflies, scuttling
## tidepool crabs, and steep-slope cliff buttresses across `island`, attaching the
## `IslandDetails` child.
static func populate_for_island(island: Island, archetype: StringName = &"",
		rng_seed: int = 0, exclusions: Array[Vector3] = []) -> IslandDetails:
	var details := IslandDetails.new()
	details.name = "IslandDetails"
	if island == null:
		details.set_process(false)
		return details

	var arch: StringName = archetype if archetype != &"" else island.archetype
	var rng := RandomNumberGenerator.new()
	var seed_val := rng_seed
	if seed_val == 0:
		seed_val = island.island_id.hash()
	if seed_val == 0:
		seed_val = 0x151A4D37
	rng.seed = seed_val

	var is_volcanic := arch == &"volcano_crag"
	var is_tiny := island.island_radius < 45.0
	var radius := maxf(18.0, island.island_radius)
	var radius_t := clampf((radius - 45.0) / 137.0, 0.0, 1.0)
	var all_radius_t := clampf((radius - 38.0) / 144.0, 0.0, 1.0)
	details._island_radius = radius

	# 1. Build automatic keepout zones (outpost pier/plaza/tavern/stall/beacon, mooring,
	#    dig points, major structures, Wave I-2 signature landmarks, plus caller exclusions)
	#    and optional walkable trail polylines stored on `island` metadata.
	var keepouts: Array[Vector3] = []
	var pier_seg := _collect_keepouts(island, arch, exclusions, keepouts)
	var has_pier := bool(pier_seg["has_pier"])
	var pier_a: Vector2 = pier_seg["pier_a"] as Vector2
	var pier_b: Vector2 = pier_seg["pier_b"] as Vector2
	var trail_ctx := _collect_trail_context(island)

	# 2. Compute radius- & archetype-scaled layer budgets.
	var grass_target := _compute_grass_target(arch, radius, radius_t, is_volcanic, is_tiny)
	var foliage_pair := _compute_fern_hibiscus_targets(arch, radius_t, is_volcanic, is_tiny)
	var fern_target: int = foliage_pair.x
	var hibiscus_target: int = foliage_pair.y
	var driftwood_target := clampi(int(roundf(lerpf(22.0, 62.0, all_radius_t) * (0.75 if is_volcanic else 1.0))), 20, 68)
	var pebble_target := clampi(int(roundf(lerpf(50.0, 130.0, all_radius_t) * (0.78 if is_volcanic else 1.0))), 45, 135)
	var tidal_target := clampi(int(roundf(lerpf(26.0, 68.0, all_radius_t) * (1.06 if arch == &"sea_stack" or is_volcanic else 1.0))), 24, 72)
	var buttress_total_target := clampi(int(roundf(lerpf(18.0, 52.0, all_radius_t) * (1.08 if arch in [&"volcano_crag", &"twin_spires", &"sea_stack", &"grand_citadel"] else 1.0))), 14, 56)
	var butterfly_target := 0
	if not is_volcanic and arch != &"sea_stack" and not is_tiny:
		butterfly_target = clampi(int(roundf(lerpf(14.0, 36.0, radius_t))), 14, 36)
	var crab_target := 0
	if not is_volcanic:
		crab_target = clampi(int(roundf(lerpf(10.0, 26.0, all_radius_t))), 10, 26)

	var max_grass_h := maxf(24.0, island.peak_height * 0.80)
	var max_fern_h := maxf(22.0, island.peak_height * 0.72)
	var max_shrub_h := maxf(20.0, island.peak_height * 0.68)

	# 3. Discover organic lush meadow patch centers for natural clustering.
	var meadow_centers := _discover_meadow_centers(island, rng, radius, max_grass_h, keepouts, has_pier, pier_a, pier_b)

	# 4. Populate Layer 1: GrassClumps (linear colors for `foliage_wind.gdshader`).
	var grass_xf: Array[Transform3D] = []
	var grass_col: Array[Color] = []
	var grass_pos := PackedVector3Array()
	_place_grass_clumps(island, arch, rng, grass_target, radius, max_grass_h, is_volcanic,
		meadow_centers, keepouts, has_pier, pier_a, pier_b, trail_ctx, grass_xf, grass_col, grass_pos)

	# 5. Populate Layers 2 & 3: JungleFerns & HibiscusShrubs (linear colors for `foliage_wind.gdshader`).
	var fern_xf: Array[Transform3D] = []
	var fern_col: Array[Color] = []
	var hibiscus_xf: Array[Transform3D] = []
	var hibiscus_col: Array[Color] = []
	var hibiscus_pos := PackedVector3Array()
	var bush_grid: Dictionary = {}
	_place_jungle_ferns(island, arch, rng, fern_target, radius, max_fern_h, is_volcanic,
		meadow_centers, keepouts, has_pier, pier_a, pier_b, trail_ctx, bush_grid, fern_xf, fern_col)
	_place_hibiscus_shrubs(island, arch, rng, hibiscus_target, radius, max_shrub_h, is_volcanic,
		meadow_centers, keepouts, has_pier, pier_a, pier_b, trail_ctx, bush_grid, hibiscus_xf, hibiscus_col, hibiscus_pos)

	# 6. Populate Layers 4, 5, 6: CoastalDriftwood, ShorePebblesShells, TidalOutcrops (sRGB vertex colors).
	var driftwood_xf: Array[Transform3D] = []
	var driftwood_col: Array[Color] = []
	var pebble_xf: Array[Transform3D] = []
	var pebble_col: Array[Color] = []
	var pebble_pos := PackedVector3Array()
	var tidal_xf: Array[Transform3D] = []
	var tidal_col: Array[Color] = []
	_place_coastal_driftwood(island, rng, driftwood_target, radius, is_volcanic,
		keepouts, has_pier, pier_a, pier_b, trail_ctx, driftwood_xf, driftwood_col)
	_place_shore_pebbles(island, rng, pebble_target, radius, is_volcanic,
		keepouts, has_pier, pier_a, pier_b, trail_ctx, pebble_xf, pebble_col, pebble_pos)
	_place_tidal_outcrops(island, arch, rng, tidal_target, radius, is_volcanic,
		keepouts, has_pier, pier_a, pier_b, trail_ctx, tidal_xf, tidal_col)

	# 7. Populate Layer 7 (+ optional Layer 8 `CliffButtressesWide`): Steep-Slope Cliff Buttresses.
	var use_wide_layer := (not is_volcanic) and (island.island_radius >= WIDE_BUTTRESS_MIN_RADIUS)
	var tall_glb_path := GLB_VOLCANIC_SPIRE if is_volcanic else GLB_BUTTRESS_TALL
	var tall_glb_mesh := _extract_glb_visual_mesh(tall_glb_path)
	var tall_uses_glb := tall_glb_mesh != null
	var tall_mesh: Mesh = tall_glb_mesh if tall_uses_glb else _get_fallback_buttress_mesh()

	var wide_glb_mesh: Mesh = _extract_glb_visual_mesh(GLB_BUTTRESS_WIDE) if use_wide_layer else null
	var wide_uses_glb := wide_glb_mesh != null
	var wide_mesh: Mesh = wide_glb_mesh if wide_uses_glb else _get_fallback_buttress_wide_mesh()

	var buttress_xf: Array[Transform3D] = []
	var buttress_col: Array[Color] = []
	var buttress_wide_xf: Array[Transform3D] = []
	var buttress_wide_col: Array[Color] = []
	var buttress_normals_y := PackedFloat32Array()

	_place_cliff_buttresses(island, arch, rng, buttress_total_target, radius, is_volcanic,
		use_wide_layer, tall_mesh, tall_uses_glb, wide_mesh, wide_uses_glb,
		keepouts, has_pier, pier_a, pier_b,
		buttress_xf, buttress_col, buttress_wide_xf, buttress_wide_col, buttress_normals_y)

	# 8. Populate Layer 9: 3D Trail Stepping Stones, Sloped Stair-Slabs & Curb Rocks (sRGB vertex colors).
	var stepping_xf: Array[Transform3D] = []
	var stepping_col: Array[Color] = []
	_place_trail_stepping_stones(island, arch, rng, is_volcanic, keepouts,
		has_pier, pier_a, pier_b, trail_ctx, stepping_xf, stepping_col)

	# 9. Populate Layer 10: Living Sculpted Tropical Butterflies (lush islands only, sRGB colors).
	var butterfly_xf: Array[Transform3D] = []
	var butterfly_col: Array[Color] = []
	var butterfly_orbits: Array[Dictionary] = []
	if butterfly_target > 0:
		_place_butterflies(island, rng, butterfly_target, radius, hibiscus_pos,
			meadow_centers, grass_pos, trail_ctx, keepouts, has_pier, pier_a, pier_b,
			butterfly_xf, butterfly_col, butterfly_orbits)

	# 9b. Populate Layer 11: Living Scuttling Shoreline Tidepool Crabs (all non-volcanic islands).
	var crab_xf: Array[Transform3D] = []
	var crab_col: Array[Color] = []
	var crab_orbits: Array[Dictionary] = []
	if crab_target > 0:
		_place_shore_crabs(island, rng, crab_target, radius, keepouts,
			has_pier, pier_a, pier_b, crab_xf, crab_col, crab_orbits)

	# 10. Build strictly batched MultiMeshInstance3D children & register live foliage wind!
	var foliage_mat := _get_foliage_material()
	island.register_foliage_material(foliage_mat)

	var grass_vis := maxf(235.0, island.island_radius + 145.0)
	var fern_vis := maxf(270.0, island.island_radius + 165.0)
	var hibiscus_vis := maxf(255.0, island.island_radius + 155.0)
	var driftwood_vis := maxf(210.0, island.island_radius + 125.0)
	var pebble_vis := maxf(175.0, island.island_radius + 95.0)
	var tidal_vis := maxf(310.0, island.island_radius + 185.0)
	var buttress_vis := clampf(island.island_radius * 6.0 + 1200.0, 1800.0, 2400.0)
	# Wave I-9 (Local-GPU M20A GPU optimization): cull close-range micro-details cleanly offshore
	# so sailing at 150-300 m drops ~180k+ micro-prim triangles & keeps Archipelago GPU < 0.45 ms!
	var stepping_vis := clampf(island.island_radius + 58.0, 102.0, 225.0)
	var butterfly_vis := clampf(island.island_radius + 32.0, 74.0, 185.0)
	var crab_vis := clampf(island.island_radius + 26.0, 72.0, 175.0)

	details._grass_mmi = _create_multimesh_node(
		"GrassClumps", _get_grass_mesh(), foliage_mat, grass_xf, grass_col, 1.0, grass_vis, 20.0)
	details._fern_mmi = _create_multimesh_node(
		"JungleFerns", _get_fern_mesh(), foliage_mat, fern_xf, fern_col, 1.0, fern_vis, 22.0)
	details._hibiscus_mmi = _create_multimesh_node(
		"HibiscusShrubs", _get_hibiscus_mesh(), foliage_mat, hibiscus_xf, hibiscus_col, 1.0, hibiscus_vis, 22.0)
	details._driftwood_mmi = _create_multimesh_node(
		"CoastalDriftwood", _get_driftwood_mesh(), _get_wood_stone_material(), driftwood_xf, driftwood_col, 0.0, driftwood_vis, 18.0)
	details._pebbles_mmi = _create_multimesh_node(
		"ShorePebblesShells", _get_pebbles_mesh(), _get_pebble_material(), pebble_xf, pebble_col, 0.0, pebble_vis, 16.0)
	details._tidal_mmi = _create_multimesh_node(
		"TidalOutcrops", _get_tidal_rock_mesh(), _get_tidal_rock_material(), tidal_xf, tidal_col, 0.0, tidal_vis, 24.0)

	var tall_mat_override: Material = null if tall_uses_glb else _get_buttress_fallback_material()
	details._buttress_mmi = _create_multimesh_node(
		"CliffButtresses", tall_mesh, tall_mat_override, buttress_xf, buttress_col, 0.0, buttress_vis, 45.0)

	details._attach_layer(details._grass_mmi)
	details._attach_layer(details._fern_mmi)
	details._attach_layer(details._hibiscus_mmi)
	details._attach_layer(details._driftwood_mmi)
	details._attach_layer(details._pebbles_mmi)
	details._attach_layer(details._tidal_mmi)
	details._attach_layer(details._buttress_mmi)

	if use_wide_layer and not buttress_wide_xf.is_empty():
		var wide_mat_override: Material = null if wide_uses_glb else _get_buttress_fallback_material()
		details._buttress_wide_mmi = _create_multimesh_node(
			"CliffButtressesWide", wide_mesh, wide_mat_override, buttress_wide_xf, buttress_wide_col, 0.0, buttress_vis, 45.0)
		details._attach_layer(details._buttress_wide_mmi)

	if not stepping_xf.is_empty():
		details._stepping_stone_mmi = _create_multimesh_node(
			"TrailSteppingStones", _get_stepping_stone_mesh(), _get_stepping_stone_material(),
			stepping_xf, stepping_col, 0.0, stepping_vis, 18.0)
		details._attach_layer(details._stepping_stone_mmi)

	if not butterfly_xf.is_empty():
		details._butterfly_mmi = _create_multimesh_node(
			"IslandButterflies", _get_butterfly_mesh(), _get_butterfly_material(),
			butterfly_xf, butterfly_col, 4.0, butterfly_vis, 18.0)
		var init_tod := fposmod(Weather.time_of_day, 24.0)
		details._butterfly_mmi.visible = init_tod >= 6.0 and init_tod <= 18.8 and Weather.storminess < 0.55
		details._attach_layer(details._butterfly_mmi)

	if not crab_xf.is_empty():
		details._crab_mmi = _create_multimesh_node(
			"ShoreCrabs", _get_crab_mesh(), _get_crab_material(),
			crab_xf, crab_col, 3.5, crab_vis, 16.0)
		details._crab_mmi.visible = Weather.storminess < 0.75
		details._attach_layer(details._crab_mmi)

	details._grass_count = grass_xf.size()
	details._fern_count = fern_xf.size()
	details._hibiscus_count = hibiscus_xf.size()
	details._driftwood_count = driftwood_xf.size()
	details._pebbles_count = pebble_xf.size()
	details._tidal_count = tidal_xf.size()
	details._buttress_count = buttress_xf.size()
	details._buttress_wide_count = buttress_wide_xf.size()
	details._stepping_stone_count = stepping_xf.size()
	details._butterfly_count = butterfly_xf.size()
	details._crab_count = crab_xf.size()
	details._placed_buttress_normals_y = buttress_normals_y
	details._placed_grass_positions = grass_pos
	details._placed_pebble_positions = pebble_pos
	details._butterfly_orbits = butterfly_orbits
	details._crab_orbits = crab_orbits
	details.set_process((not butterfly_orbits.is_empty()) or (not crab_orbits.is_empty()))

	island.add_child(details)
	return details


func _attach_layer(mmi: MultiMeshInstance3D) -> void:
	if mmi == null:
		return
	add_child(mmi)
	_owned_multimeshes.append(mmi)


# ------------------------------------------------------------------ inspection API

## Number of `MultiMeshInstance3D` draw-call nodes owned by this island detail node (8..11 across archetypes).
func get_multimesh_count() -> int:
	var count := 0
	for child in get_children():
		if child is MultiMeshInstance3D:
			count += 1
	return count


## Total placed detail instances across every batched MultiMesh layer.
func get_total_instance_count() -> int:
	var total := 0
	for child in get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi != null and mmi.multimesh != null:
			total += mmi.multimesh.instance_count
	return total


func get_grass_count() -> int:
	return _grass_count


func get_fern_count() -> int:
	return _fern_count


func get_hibiscus_count() -> int:
	return _hibiscus_count


## Combined count of `CoastalDriftwood` + `ShorePebblesShells` + `TidalOutcrops`.
func get_coastal_detail_count() -> int:
	return _driftwood_count + _pebbles_count + _tidal_count


## Combined count of steep-slope `CliffButtresses` (+ optional `CliffButtressesWide`).
func get_cliff_buttress_count() -> int:
	return _buttress_count + _buttress_wide_count


## Placed walkable path flagstones + trail-edge border curb stones in `TrailSteppingStones`.
func get_stepping_stone_count() -> int:
	return _stepping_stone_count


## Placed animated tropical swallowtail butterflies in `IslandButterflies`.
func get_butterfly_count() -> int:
	return _butterfly_count


## Placed animated shoreline tidepool crabs in `ShoreCrabs`.
func get_shore_crab_count() -> int:
	return _crab_count


## Copy of terrain `normal.y` values recorded at every placed cliff buttress (reliable under `--headless`).
func get_placed_buttress_normals_y() -> PackedFloat32Array:
	return _placed_buttress_normals_y.duplicate()


## Copy of local-space positions for every placed `GrassClumps` instance (reliable under `--headless`).
func get_placed_grass_positions() -> PackedVector3Array:
	return _placed_grass_positions.duplicate()


## Copy of local-space positions for every placed `ShorePebblesShells` instance (reliable under `--headless`).
func get_placed_pebble_positions() -> PackedVector3Array:
	return _placed_pebble_positions.duplicate()


# ------------------------------------------------------------------ budget & keepout helpers

static func _compute_grass_target(arch: StringName, radius: float, radius_t: float,
		is_volcanic: bool, is_tiny: bool) -> int:
	if is_volcanic:
		return clampi(int(roundf(lerpf(225.0, 285.0, radius_t))), 215, 295)
	if is_tiny:
		return clampi(int(roundf(lerpf(105.0, 172.0, clampf((radius - 28.0) / 17.0, 0.0, 1.0)))), 90, 190)
	var lush_k := 1.0
	match arch:
		&"grand_citadel", &"twin_spires", &"skull_bluff":
			lush_k = 1.07
		&"crescent_lagoon", &"palm_atoll", &"treasure_peak", &"smuggler_cove":
			lush_k = 1.04
		&"outpost", &"grand_outpost", &"fort_rock":
			lush_k = 0.96
		&"wreck_shoal":
			lush_k = 0.98
	var base := lerpf(256.0, 650.0, radius_t) * lush_k
	return clampi(int(roundf(base)), 230, 675)


static func _compute_fern_hibiscus_targets(arch: StringName, radius_t: float,
		is_volcanic: bool, is_tiny: bool) -> Vector2i:
	var combined := 0
	if is_volcanic:
		combined = clampi(int(roundf(lerpf(58.0, 90.0, radius_t))), 46, 100)
		var ferns_v := int(roundf(float(combined) * 0.65))
		return Vector2i(ferns_v, maxi(12, combined - ferns_v))
	if is_tiny:
		combined = 54
		return Vector2i(32, 22)
	var lush_k := 1.0
	match arch:
		&"grand_citadel", &"twin_spires", &"smuggler_cove", &"skull_bluff":
			lush_k = 1.07
		&"crescent_lagoon", &"palm_atoll", &"treasure_peak":
			lush_k = 1.04
		&"outpost", &"grand_outpost":
			lush_k = 0.95
	combined = clampi(int(roundf(lerpf(124.0, 316.0, radius_t) * lush_k)), 112, 336)
	var fern_n := int(roundf(float(combined) * 0.60))
	return Vector2i(fern_n, combined - fern_n)


static func _collect_keepouts(island: Island, arch: StringName, caller_exclusions: Array[Vector3],
		out_keepouts: Array[Vector3]) -> Dictionary:
	for ex in caller_exclusions:
		out_keepouts.append(ex)

	for dp in island.dig_points:
		out_keepouts.append(Vector3(dp.x, dp.z, DIG_KEEPOUT_RADIUS))

	var has_pier := false
	var pier_a := Vector2.ZERO
	var pier_b := Vector2.ZERO

	if island is Outpost:
		var op := island as Outpost
		var db := Basis(Vector3.UP, op.dock_yaw)
		var harbour_zones: Array[Array] = [
			[0.0, -34.0, 15.0],
			[4.5, -39.5, 11.0],
			[0.0, -18.0, 14.5],
			[-11.0, -7.5, 10.5],
			[9.2, -18.5, 6.5],
			[-6.6, -19.5, 4.5],
			[24.0, -6.5, 9.0],
		]
		if arch == &"grand_outpost":
			harbour_zones.append([0.0, -64.0, 22.0])
			harbour_zones.append([0.0, -104.0, 26.0])
		for hz in harbour_zones:
			var wp := db * Vector3(float(hz[0]), 0.0, float(hz[1]))
			out_keepouts.append(Vector3(wp.x, wp.z, float(hz[2])))

		has_pier = true
		pier_a = Vector2(op.dock_local_transform.origin.x, op.dock_local_transform.origin.z)
		pier_b = Vector2(op.dock_pier_end_local.x, op.dock_pier_end_local.z)
		if pier_a.distance_squared_to(pier_b) < 1.0:
			var p_start := db * Vector3(0.0, 0.0, -28.0)
			var p_end := db * Vector3(0.0, 0.0, -44.0)
			pier_a = Vector2(p_start.x, p_start.z)
			pier_b = Vector2(p_end.x, p_end.z)

		# Defensive keepouts around actual instantiated outpost buildings if shifted.
		if op.tavern_node != null and is_instance_valid(op.tavern_node):
			out_keepouts.append(Vector3(op.tavern_node.position.x, op.tavern_node.position.z, 9.5))
		if op.merchant_stall != null and is_instance_valid(op.merchant_stall):
			out_keepouts.append(Vector3(op.merchant_stall.position.x, op.merchant_stall.position.z, 5.5))
		if op.beacon_node != null and is_instance_valid(op.beacon_node):
			out_keepouts.append(Vector3(op.beacon_node.position.x, op.beacon_node.position.z, 8.5))
		if op.notice_board_node != null and is_instance_valid(op.notice_board_node):
			out_keepouts.append(Vector3(op.notice_board_node.position.x, op.notice_board_node.position.z, 4.0))
	else:
		var m_pos := island.mooring_transform.origin
		if Vector2(m_pos.x, m_pos.z).length_squared() > 1.0:
			out_keepouts.append(Vector3(m_pos.x, m_pos.z, MOORING_KEEPOUT_RADIUS))

	# Automatically avoid overlapping major placed structures (bastions, warehouses, campfires, grottoes,
	# vents, and Wave I-2 signature landmarks).
	var props_root := island.get_node_or_null(^"Props") as Node3D
	if props_root != null:
		_collect_prop_keepouts(props_root, props_root.transform, out_keepouts)
	var landmarks_root := island.get_node_or_null(^"Landmarks") as Node3D
	if landmarks_root != null:
		_collect_prop_keepouts(landmarks_root, landmarks_root.transform, out_keepouts)

	for child in island.get_children():
		var n3 := child as Node3D
		if n3 == null:
			continue
		if n3.name.begins_with("VolcanicFumarole") or n3.name.ends_with("Waterfall"):
			out_keepouts.append(Vector3(n3.position.x, n3.position.z, 5.0))

	return {
		"has_pier": has_pier,
		"pier_a": pier_a,
		"pier_b": pier_b,
	}


static func _collect_prop_keepouts(container: Node3D, parent_xf: Transform3D,
		out_keepouts: Array[Vector3]) -> void:
	for child in container.get_children():
		var n3 := child as Node3D
		if n3 == null:
			continue
		var cname := String(n3.name)
		if cname == "Landmarks" or cname == "IslandLandmarks":
			_collect_prop_keepouts(n3, parent_xf * n3.transform, out_keepouts)
			continue
		var keep_r := _prop_keepout_radius(cname)
		if keep_r > 0.0:
			var p := parent_xf * n3.position
			out_keepouts.append(Vector3(p.x, p.z, keep_r))


static func _prop_keepout_radius(cname: String) -> float:
	if cname == "FortBastion":
		return 18.5
	if cname.begins_with("SkullCliffCarving"):
		return 15.0
	if cname.begins_with("SmugglerGrotto") or cname.begins_with("CoastalSeaArch"):
		return 10.5
	if cname.begins_with("TempleStairway"):
		return 9.0
	if cname.begins_with("VolcanicObsidianArch"):
		return 8.8
	if cname.begins_with("CliffCatwalk") or cname.begins_with("ImpaledShipwreck"):
		return 8.5
	if cname.begins_with("CliffOverhang") or cname.begins_with("CliffButtressWide"):
		return 8.0
	if cname.begins_with("ShipDrydock"):
		return 7.8
	if cname.begins_with("HarbourWarehouse") or cname.begins_with("Shipwreck") or cname.begins_with("SummitCrag"):
		return 7.5
	if cname.begins_with("SeawallBastion") or cname.begins_with("CitadelSeawall") or cname.begins_with("LeviathanRibcage"):
		return 7.2
	if cname.begins_with("VolcanicBasaltSpire") or cname.begins_with("RuinAqueduct") \
			or cname.begins_with("SunkenStern") or cname.begins_with("TidalCoralArch"):
		return 7.0
	if cname.begins_with("HarbourCrane") or cname.begins_with("CompassMonolith"):
		return 6.8
	if cname.begins_with("FortWatchtower") or cname.begins_with("AstronomerOrrery"):
		return 6.5
	if cname.begins_with("UpperStrataRib") or cname.begins_with("SmugglerJetty"):
		return 6.0
	if cname.begins_with("HeadlandWatchtower") or cname.begins_with("FishingHut") \
			or cname.begins_with("CitadelTimberBridge") or cname.begins_with("CanyonTimberBridge") \
			or cname.begins_with("BluffTimberBridge"):
		return 5.8
	if cname.begins_with("PirateCamp") or cname.begins_with("CannonBastion") \
			or cname.begins_with("VolcanicBridgeRuin"):
		return 5.6
	if cname.begins_with("PirateWatchpost"):
		return 5.5
	if cname.begins_with("SeaGodIdol") or cname.begins_with("LavaCauldronShrine") \
			or cname.begins_with("JungleAltar") or cname.begins_with("CascadeShrine"):
		return 5.4
	if cname.begins_with("VolcanicChainPylon") or cname.begins_with("SkeletonThrone"):
		return 5.2
	if cname.begins_with("SundialPlaza"):
		return 5.0
	if cname.begins_with("TreasureVault") or cname.begins_with("DriftwoodCamp"):
		return 4.8
	if cname.begins_with("SmugglerHoard") or cname.begins_with("LookoutBell") \
			or cname.begins_with("ObsidianVent") or cname.begins_with("CrowNestMast") \
			or cname.begins_with("RumDistillery"):
		return 4.6
	if cname.begins_with("AnchorMemorial"):
		return 4.5
	if cname.begins_with("BeachCampfire") or cname.begins_with("OutpostCampfire") \
			or cname.begins_with("MossyBoulder") or cname.begins_with("ReefBeacon") \
			or cname.begins_with("StoneWell") or cname.begins_with("SerpentTotem"):
		return 4.2
	if cname.begins_with("SignalBrazier"):
		return 4.0
	if cname.begins_with("BeachedRowboat") or cname.begins_with("PirateGibbet") or cname.begins_with("SupplyCart"):
		return 3.8
	if cname.begins_with("TrailLantern") or cname.begins_with("StoneCairn"):
		return 2.0
	# ObeliskGate & TrailFootbridge straddle walkable trails; skip keepout here so
	# TrailSteppingStones continue smoothly through the open archway and bridge deck.
	return 0.0


static func _collect_trail_context(island: Island) -> Dictionary:
	var seg_a := PackedVector2Array()
	var seg_b := PackedVector2Array()
	var polylines: Array[PackedVector2Array] = []
	var empty_ctx := {
		"active": false,
		"half_width": 0.0,
		"landing_yaw": 0.0,
		"cos_y": 1.0,
		"sin_y": 0.0,
		"clear_r_sq": 0.0,
		"min_u": 0.0,
		"max_u": 0.0,
		"min_v": 0.0,
		"max_v": 0.0,
		"raw_min_u": 0.0,
		"raw_max_u": 0.0,
		"raw_min_v": 0.0,
		"raw_max_v": 0.0,
		"polylines": polylines,
		"seg_a": seg_a,
		"seg_b": seg_b,
	}
	if not island.has_meta(&"trail_polylines"):
		return empty_ctx

	# Keep tall foliage strictly outside the walkable trail centerline (`half_w + 0.20 m`) while
	# dedicated trail-edge framing passes pack lush grass, ferns & curb stones right along both shoulders.
	var half_w := maxf(0.0, float(island.get_meta(&"trail_half_width", 2.8)))
	if half_w <= 0.001:
		return empty_ctx
	var clear_r := half_w + 0.20

	var raw_trails: Variant = island.get_meta(&"trail_polylines", [])
	var min_u := INF
	var max_u := -INF
	var min_v := INF
	var max_v := -INF

	if raw_trails is Array:
		for poly_var: Variant in (raw_trails as Array):
			var pts := PackedVector2Array()
			if poly_var is PackedVector2Array:
				pts = poly_var as PackedVector2Array
			elif poly_var is Array:
				for p_var: Variant in (poly_var as Array):
					if p_var is Vector2:
						pts.append(p_var as Vector2)
			if pts.size() < 2:
				continue
			polylines.append(pts)
			for i in range(pts.size() - 1):
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[i + 1]
				if a.distance_squared_to(b) < 1e-6:
					continue
				seg_a.append(a)
				seg_b.append(b)
				min_u = minf(min_u, minf(a.x, b.x))
				max_u = maxf(max_u, maxf(a.x, b.x))
				min_v = minf(min_v, minf(a.y, b.y))
				max_v = maxf(max_v, maxf(a.y, b.y))

	if seg_a.is_empty():
		return empty_ctx

	var landing_yaw := float(island.get_meta(&"landing_yaw", 0.0))
	return {
		"active": true,
		"half_width": half_w,
		"landing_yaw": landing_yaw,
		"cos_y": cos(landing_yaw),
		"sin_y": sin(landing_yaw),
		"clear_r_sq": clear_r * clear_r,
		"min_u": min_u - clear_r,
		"max_u": max_u + clear_r,
		"min_v": min_v - clear_r,
		"max_v": max_v + clear_r,
		"raw_min_u": min_u,
		"raw_max_u": max_u,
		"raw_min_v": min_v,
		"raw_max_v": max_v,
		"polylines": polylines,
		"seg_a": seg_a,
		"seg_b": seg_b,
	}


static func _uv_to_local_xz(uv: Vector2, cos_y: float, sin_y: float) -> Vector2:
	return Vector2(uv.x * cos_y + uv.y * sin_y, -uv.x * sin_y + uv.y * cos_y)


static func _trail_distance(pt: Vector2, trail_ctx: Dictionary) -> float:
	if not bool(trail_ctx["active"]):
		return INF
	var cos_y: float = float(trail_ctx["cos_y"])
	var sin_y: float = float(trail_ctx["sin_y"])
	var uv := Vector2(pt.x * cos_y - pt.y * sin_y, pt.x * sin_y + pt.y * cos_y)
	var seg_a: PackedVector2Array = trail_ctx["seg_a"] as PackedVector2Array
	var seg_b: PackedVector2Array = trail_ctx["seg_b"] as PackedVector2Array
	var min_sq := INF
	for i in seg_a.size():
		var d_sq := _point_segment_dist_sq(uv, seg_a[i], seg_b[i])
		if d_sq < min_sq:
			min_sq = d_sq
	return sqrt(min_sq) if min_sq < INF else INF


static func _is_on_trail(pt: Vector2, trail_ctx: Dictionary) -> bool:
	if not bool(trail_ctx["active"]):
		return false
	var cos_y: float = float(trail_ctx["cos_y"])
	var sin_y: float = float(trail_ctx["sin_y"])
	var uv := Vector2(pt.x * cos_y - pt.y * sin_y, pt.x * sin_y + pt.y * cos_y)
	if uv.x < float(trail_ctx["min_u"]) or uv.x > float(trail_ctx["max_u"]) \
			or uv.y < float(trail_ctx["min_v"]) or uv.y > float(trail_ctx["max_v"]):
		return false
	var clear_r_sq: float = float(trail_ctx["clear_r_sq"])
	var seg_a: PackedVector2Array = trail_ctx["seg_a"] as PackedVector2Array
	var seg_b: PackedVector2Array = trail_ctx["seg_b"] as PackedVector2Array
	for i in seg_a.size():
		if _point_segment_dist_sq(uv, seg_a[i], seg_b[i]) < clear_r_sq:
			return true
	return false


static func _is_in_keepout(pt: Vector2, keepouts: Array[Vector3], has_pier: bool,
		pier_a: Vector2, pier_b: Vector2, extra_margin: float = 0.0) -> bool:
	for ex in keepouts:
		var r := ex.z + extra_margin
		var dx := pt.x - ex.x
		var dz := pt.y - ex.y
		if dx * dx + dz * dz < r * r:
			return true
	if has_pier:
		var pr := PIER_KEEPOUT_RADIUS + extra_margin
		if _point_segment_dist_sq(pt, pier_a, pier_b) < pr * pr:
			return true
	return false


static func _point_segment_dist_sq(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_squared_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_squared_to(a + ab * t)


# ------------------------------------------------------------------ 2D spatial hash grid

static func _grid_is_clear(grid: Dictionary, cell_size: float, pt: Vector2, min_dist: float) -> bool:
	var d2 := min_dist * min_dist
	var cx := int(floorf(pt.x / cell_size))
	var cz := int(floorf(pt.y / cell_size))
	var span := maxi(1, int(ceilf(min_dist / cell_size)))
	for oz in range(-span, span + 1):
		for ox in range(-span, span + 1):
			var bucket: Variant = grid.get(Vector2i(cx + ox, cz + oz))
			if bucket != null:
				for other: Vector2 in bucket as Array:
					if pt.distance_squared_to(other) < d2:
						return false
	return true


static func _grid_insert(grid: Dictionary, cell_size: float, pt: Vector2) -> void:
	var key := Vector2i(int(floorf(pt.x / cell_size)), int(floorf(pt.y / cell_size)))
	var bucket: Variant = grid.get(key)
	if bucket == null:
		grid[key] = [pt]
	else:
		(bucket as Array).append(pt)


# ------------------------------------------------------------------ placement: meadow & foliage layers

static func _discover_meadow_centers(island: Island, rng: RandomNumberGenerator, radius: float,
		max_grass_h: float, keepouts: Array[Vector3], has_pier: bool,
		pier_a: Vector2, pier_b: Vector2) -> Array[Vector2]:
	var centers: Array[Vector2] = []
	var desired := clampi(int(roundf(radius / 11.5)), 5, 16)
	var min_sep := clampf(radius * 0.17, 7.5, 22.0)
	var grid: Dictionary = {}
	for _attempt in desired * 26:
		if centers.size() >= desired:
			break
		var pt := _sample_disk_xz(rng, radius * 0.06, radius * 0.88)
		if _is_in_keepout(pt, keepouts, has_pier, pier_a, pier_b):
			continue
		var h := island.surface_height(pt.x, pt.y)
		if h < 2.2 or h > max_grass_h:
			continue
		if island.surface_normal(pt.x, pt.y).y < 0.74:
			continue
		if _grid_is_clear(grid, min_sep, pt, min_sep):
			centers.append(pt)
			_grid_insert(grid, min_sep, pt)
	return centers


static func _scan_highland_ledge_candidates(island: Island, rng: RandomNumberGenerator,
		r_min: float, r_max: float, h_min: float, h_max: float, n_min: float, n_max: float,
		keepouts: Array[Vector3], has_pier: bool, pier_a: Vector2, pier_b: Vector2,
		trail_ctx: Dictionary) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var radial_steps := clampi(int(roundf((r_max - r_min) / 2.0)), 18, 36)
	var ang_step_arc := clampf(r_max * 0.048, 2.0, 4.8)
	for ri in range(1, radial_steps + 1):
		var frac := float(ri) / float(radial_steps)
		var r_base := lerpf(r_min, r_max, frac)
		var ring_samples := maxi(18, int(roundf(TAU * r_base / ang_step_arc)))
		var phase := float(ri) * 0.517 + rng.randf() * 0.25
		for ai in ring_samples:
			var r_s := clampf(r_base + rng.randf_range(-0.65, 0.65), r_min, r_max)
			var ang := phase + (float(ai) + rng.randf_range(-0.28, 0.28)) / float(ring_samples) * TAU
			var pt := Vector2(cos(ang) * r_s, sin(ang) * r_s)
			if _is_in_keepout(pt, keepouts, has_pier, pier_a, pier_b):
				continue
			if _is_on_trail(pt, trail_ctx):
				continue
			var h := island.surface_height(pt.x, pt.y)
			if h < h_min or h > h_max:
				continue
			var n := island.surface_normal(pt.x, pt.y)
			if n.y < n_min or n.y > n_max:
				continue
			candidates.append({
				"pt": pt,
				"h": h,
				"n": n,
			})

	# Deterministic Fisher-Yates shuffle so highland tufts distribute naturally around every cliff face.
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Dictionary = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp
	return candidates


static func _append_highland_grass_tuft(arch: StringName, rng: RandomNumberGenerator, pt: Vector2,
		h: float, n: Vector3, grid: Dictionary, cell_size: float, out_xf: Array[Transform3D],
		out_col: Array[Color], out_pos: PackedVector3Array) -> void:
	var sx := rng.randf_range(1.45, 2.25)
	var sz := sx * rng.randf_range(0.86, 1.15)
	var sy := rng.randf_range(1.20, 1.85)
	if h > 30.0:
		var wind_t := clampf((h - 30.0) / 28.0, 0.0, 1.0)
		sy *= lerpf(1.0, 0.88, wind_t)
		sx *= lerpf(1.0, 1.08, wind_t)
		sz *= lerpf(1.0, 1.08, wind_t)
	var slope_sink := 0.14 * clampf((0.84 - n.y) / 0.34, 0.0, 1.0)
	var sink := 0.10 + maxf(0.0, (0.70 - n.y) * 0.30) + slope_sink
	var origin := Vector3(pt.x, h - sink, pt.y)
	var xf := _grounded_transform(origin, n, 0.55, rng.randf() * TAU, Vector3(sx, sy, sz))
	var srgb_col := _pick_jittered_color(rng, GRASS_HIGHLAND_PALETTE, 0.024, 0.10)
	srgb_col = _apply_highland_alpine_tint(srgb_col, arch, pt, h, true, false)
	out_xf.append(xf)
	out_col.append(srgb_col.srgb_to_linear())
	out_pos.append(origin)
	_grid_insert(grid, cell_size, pt)


static func _append_highland_fern_rosette(arch: StringName, rng: RandomNumberGenerator, pt: Vector2,
		h: float, n: Vector3, bush_grid: Dictionary, cell_size: float, out_xf: Array[Transform3D],
		out_col: Array[Color]) -> void:
	var sc := rng.randf_range(1.30, 2.05)
	var sy := sc * rng.randf_range(0.86, 1.15)
	if arch in HIGHLAND_RUIN_ARCHETYPES:
		sc *= 1.06
	var slope_sink := 0.22 * clampf((0.88 - n.y) / 0.34, 0.0, 1.0)
	var sink := 0.10 + maxf(0.0, (0.68 - n.y) * 0.30) + slope_sink
	var origin := Vector3(pt.x, h - sink, pt.y)
	var xf := _grounded_transform(origin, n, 0.54, rng.randf() * TAU, Vector3(sc, sy, sc))
	var srgb_col := _pick_jittered_color(rng, FERN_HIGHLAND_PALETTE, 0.022, 0.10)
	srgb_col = _apply_highland_alpine_tint(srgb_col, arch, pt, h, true, true)
	out_xf.append(xf)
	out_col.append(srgb_col.srgb_to_linear())
	_grid_insert(bush_grid, cell_size, pt)


static func _place_grass_clumps(island: Island, arch: StringName, rng: RandomNumberGenerator,
		target: int, radius: float, max_grass_h: float, is_volcanic: bool,
		meadow_centers: Array[Vector2], keepouts: Array[Vector3], has_pier: bool,
		pier_a: Vector2, pier_b: Vector2, trail_ctx: Dictionary, out_xf: Array[Transform3D],
		out_col: Array[Color], out_pos: PackedVector3Array) -> void:
	var base_spacing := clampf(radius * 0.015, 0.85, 2.25)
	var cell_size := maxf(1.6, base_spacing)
	var grid: Dictionary = {}

	# Pass 0 (Highland Cliff-Ledge Scrub): Zero-extra-DC bold alpine-tropical tufts across stepped
	# upper mountain benches (h = 18..68 m, 0.48 <= n.y <= 0.94) on tall non-volcanic islands!
	if island.peak_height >= 26.0 and not is_volcanic:
		var highland_cap := mini(target, clampi(int(roundf(float(target) * 0.15)), 20, 96))
		var hl_h_min := 18.0
		var hl_h_max := minf(68.0, island.peak_height * 0.88)
		if hl_h_max > hl_h_min + 0.5:
			var hl_r_min := radius * 0.08
			var hl_r_max := radius * 0.86
			var hl_sep := maxf(1.65, base_spacing * 0.90)
			var hl_candidates := _scan_highland_ledge_candidates(island, rng, hl_r_min, hl_r_max,
				hl_h_min, hl_h_max, 0.48, 0.94, keepouts, has_pier, pier_a, pier_b, trail_ctx)
			for cand in hl_candidates:
				if out_xf.size() >= highland_cap:
					break
				var pt: Vector2 = cand["pt"] as Vector2
				if not _grid_is_clear(grid, cell_size, pt, hl_sep):
					continue
				var h: float = float(cand["h"])
				var n: Vector3 = cand["n"] as Vector3
				_append_highland_grass_tuft(arch, rng, pt, h, n, grid, cell_size, out_xf, out_col, out_pos)

				# Cluster 1..2 companion tufts tangentially along the stepped cliff-ledge contour.
				var tan_xz := Vector2(-n.z, n.x)
				if tan_xz.length_squared() < 0.0004:
					tan_xz = Vector2(-pt.y, pt.x)
				tan_xz = tan_xz.normalized()
				var rad_xz := Vector2(tan_xz.y, -tan_xz.x)
				var cluster_n := rng.randi_range(1, 2)
				for _ci in cluster_n:
					if out_xf.size() >= highland_cap:
						break
					var side_sign := 1.0 if rng.randf() < 0.5 else -1.0
					var cpt := pt + tan_xz * (side_sign * rng.randf_range(1.85, 4.4)) + rad_xz * rng.randf_range(-0.95, 0.95)
					var cr := cpt.length()
					if cr < hl_r_min or cr > hl_r_max:
						continue
					if _is_in_keepout(cpt, keepouts, has_pier, pier_a, pier_b):
						continue
					if _is_on_trail(cpt, trail_ctx):
						continue
					if not _grid_is_clear(grid, cell_size, cpt, hl_sep):
						continue
					var ch := island.surface_height(cpt.x, cpt.y)
					if ch < hl_h_min or ch > hl_h_max:
						continue
					var cn := island.surface_normal(cpt.x, cpt.y)
					if cn.y < 0.48 or cn.y > 0.94:
						continue
					_append_highland_grass_tuft(arch, rng, cpt, ch, cn, grid, cell_size, out_xf, out_col, out_pos)

			if out_xf.size() < highland_cap and hl_sep > 1.65:
				for cand in hl_candidates:
					if out_xf.size() >= highland_cap:
						break
					var pt: Vector2 = cand["pt"] as Vector2
					if not _grid_is_clear(grid, cell_size, pt, 1.65):
						continue
					var h: float = float(cand["h"])
					var n: Vector3 = cand["n"] as Vector3
					_append_highland_grass_tuft(arch, rng, pt, h, n, grid, cell_size, out_xf, out_col, out_pos)

	# Pass 0.5 (Trail-Edge Grass Framing Pass): Lush golden-sage & emerald grass ribbons framing
	# both shoulders of every walkable trail (`d in [half_w + 0.25, half_w + 1.45]`, strictly
	# keeping the trail centerline `d < half_w + 0.20` 100% clear!).
	if bool(trail_ctx["active"]) and out_xf.size() < target:
		var half_w: float = float(trail_ctx["half_width"])
		var cos_y: float = float(trail_ctx["cos_y"])
		var sin_y: float = float(trail_ctx["sin_y"])
		var polylines: Array[PackedVector2Array] = trail_ctx["polylines"] as Array[PackedVector2Array]
		var trail_cap := mini(target, out_xf.size() + clampi(int(roundf(float(target) * 0.20)), 24, 120))
		var verge_sep := maxf(0.72, base_spacing * 0.52)
		var min_trail_clear := half_w + 0.20

		for poly in polylines:
			if out_xf.size() >= trail_cap:
				break
			var accum := 0.0
			var next_arc := rng.randf_range(0.6, 1.8)
			for i in range(poly.size() - 1):
				if out_xf.size() >= trail_cap:
					break
				var a := poly[i]
				var b := poly[i + 1]
				var seg := b - a
				var seg_len := seg.length()
				if seg_len < 0.001:
					continue
				var dir_uv := seg / seg_len
				var perp_uv := Vector2(-dir_uv.y, dir_uv.x)
				while next_arc <= accum + seg_len and out_xf.size() < trail_cap:
					var t := (next_arc - accum) / seg_len
					var base_uv := a + seg * t
					for side: float in [-1.0, 1.0]:
						if out_xf.size() >= trail_cap:
							break
						var off := half_w + rng.randf_range(0.25, 1.45)
						var pt_uv := base_uv + perp_uv * (side * off)
						var pt := _uv_to_local_xz(pt_uv, cos_y, sin_y)
						if _is_in_keepout(pt, keepouts, has_pier, pier_a, pier_b):
							continue
						if _trail_distance(pt, trail_ctx) < min_trail_clear:
							continue
						if not _grid_is_clear(grid, cell_size, pt, verge_sep):
							continue
						var h := island.surface_height(pt.x, pt.y)
						if h < 1.55 or h > max_grass_h + 2.0:
							continue
						var n := island.surface_normal(pt.x, pt.y)
						if n.y < 0.66:
							continue

						var is_tall_accent := rng.randf() < 0.42
						var sx := rng.randf_range(1.06, 1.74) if is_tall_accent else rng.randf_range(0.92, 1.44)
						var sz := sx * rng.randf_range(0.86, 1.15)
						var sy := rng.randf_range(1.18, 1.66) if is_tall_accent else rng.randf_range(0.80, 1.16)
						if is_volcanic:
							sx *= 0.80
							sz *= 0.80
							sy *= 0.74
						var slope_sink := 0.14 * clampf((0.84 - n.y) / 0.34, 0.0, 1.0)
						var origin := Vector3(pt.x, h - 0.06 - slope_sink, pt.y)
						var xf := _grounded_transform(origin, n, 0.62, rng.randf() * TAU, Vector3(sx, sy, sz))

						var srgb_col: Color
						if is_volcanic:
							srgb_col = _pick_jittered_color(rng, GRASS_VOLCANIC_PALETTE, 0.02, 0.10)
						else:
							var em_col := _pick_jittered_color(rng, GRASS_TROPICAL_PALETTE, 0.022, 0.10)
							var sg_col := _pick_jittered_color(rng, GRASS_VERGE_PALETTE, 0.018, 0.08)
							var verge_blend := rng.randf_range(0.24, 0.70)
							srgb_col = em_col.lerp(sg_col, verge_blend)
						srgb_col = _apply_grass_biome_tint(srgb_col, arch, is_volcanic, pt, h)

						out_xf.append(xf)
						out_col.append(srgb_col.srgb_to_linear())
						out_pos.append(origin)
						_grid_insert(grid, cell_size, pt)
					next_arc += rng.randf_range(2.0, 3.5)
				accum += seg_len

	# Pass 1: Lush multi-height meadow carpet (h >= 2.75 m) + golden beach-verge sea-oats (h = 1.95..4.4 m).
	var passes: Array[Array] = [
		[2.75, max_grass_h, 0.72, base_spacing, 0.56, target * 14 + 280],
		[2.30, max_grass_h + 4.0, 0.70, base_spacing * 0.66, 0.36, target * 12 + 240],
		[1.95, max_grass_h + 6.0, 0.64, 0.60, 0.22, target * 14 + 320],
	]

	for cfg in passes:
		if out_xf.size() >= target:
			break
		var h_min: float = float(cfg[0])
		var h_max: float = float(cfg[1])
		var n_min: float = float(cfg[2])
		var min_sep: float = float(cfg[3])
		var cluster_prob: float = float(cfg[4])
		var attempts: int = int(cfg[5])
		var patch_max := clampf(radius * 0.18, 6.5, 22.0)

		for _i in attempts:
			if out_xf.size() >= target:
				break
			var pt := _sample_clustered_xz(rng, meadow_centers, radius * 0.04, radius * 0.94,
				cluster_prob, 1.4, patch_max)
			if _is_in_keepout(pt, keepouts, has_pier, pier_a, pier_b):
				continue
			if _is_on_trail(pt, trail_ctx):
				continue
			if not _grid_is_clear(grid, cell_size, pt, min_sep):
				continue
			var h := island.surface_height(pt.x, pt.y)
			if h < h_min or h > h_max:
				continue
			var n := island.surface_normal(pt.x, pt.y)
			if n.y < n_min:
				continue

			# Layered multi-height meadow silhouette: low dense ground tufts + tall swaying tussocks.
			var height_tier := rng.randf()
			var sx := rng.randf_range(1.06, 1.88)
			var sz := sx * rng.randf_range(0.86, 1.15)
			var sy := rng.randf_range(0.80, 1.12) if height_tier < 0.34 else (
				rng.randf_range(1.12, 1.48) if height_tier < 0.78 else rng.randf_range(1.45, 1.74))
			if is_volcanic:
				sx *= 0.82
				sz *= 0.82
				sy *= 0.76
				var v_band := _volcanic_caldera_band(pt, h)
				if v_band == 2:
					# Low cushiony sulfur-gold ember-moss scrub hugging ash flats.
					sy *= 0.88
					sx *= 1.08
					sz *= 1.08
				elif v_band == 1:
					# Slightly taller scorched burnt-russet cinder tussocks.
					sy *= 1.08
			elif h < 4.4:
				# Coastal dune sea-oats grow slightly taller and slenderer along the sandy verge.
				var dune_t := clampf((4.4 - h) / 2.8, 0.0, 1.0)
				sy *= 1.0 + 0.16 * dune_t
				sx *= 1.0 - 0.08 * dune_t
				sz *= 1.0 - 0.08 * dune_t
			elif h > 30.0:
				var alp_t := clampf((h - 30.0) / 28.0, 0.0, 1.0)
				sy *= lerpf(1.0, 0.90, alp_t)
				sx *= lerpf(1.0, 1.06, alp_t)
				sz *= lerpf(1.0, 1.06, alp_t)
			var slope_sink := 0.14 * clampf((0.84 - n.y) / 0.34, 0.0, 1.0)
			var origin := Vector3(pt.x, h - 0.06 - slope_sink, pt.y)
			var xf := _grounded_transform(origin, n, 0.62, rng.randf() * TAU, Vector3(sx, sy, sz))

			var srgb_col: Color
			if is_volcanic:
				srgb_col = _pick_jittered_color(rng, GRASS_VOLCANIC_PALETTE, 0.02, 0.10)
			elif h < 3.6:
				var verge_t := clampf((3.6 - h) / 1.4, 0.0, 1.0)
				var g_col := _pick_jittered_color(rng, GRASS_TROPICAL_PALETTE, 0.022, 0.10)
				var v_col := _pick_jittered_color(rng, GRASS_VERGE_PALETTE, 0.018, 0.08)
				srgb_col = g_col.lerp(v_col, clampf(verge_t * 0.85, 0.0, 1.0))
			else:
				srgb_col = _pick_jittered_color(rng, GRASS_TROPICAL_PALETTE, 0.025, 0.11)
			srgb_col = _apply_grass_biome_tint(srgb_col, arch, is_volcanic, pt, h)

			out_xf.append(xf)
			out_col.append(srgb_col.srgb_to_linear())
			out_pos.append(origin)
			_grid_insert(grid, cell_size, pt)


static func _append_jungle_fern_instance(arch: StringName, rng: RandomNumberGenerator, pt: Vector2,
		h: float, n: Vector3, is_volcanic: bool, bush_grid: Dictionary, cell_size: float,
		out_xf: Array[Transform3D], out_col: Array[Color], scale_mul: float = 1.0) -> void:
	var sc := rng.randf_range(0.86, 1.60) * scale_mul * (0.76 if is_volcanic else 1.0)
	var sy := sc * rng.randf_range(0.86, 1.18)
	if not is_volcanic and arch in LUSH_JUNGLE_TEMPLE_ARCHETYPES and h < 20.0:
		var lush_t := clampf((20.0 - h) / 14.0, 0.0, 1.0)
		sc *= 1.0 + 0.08 * lush_t
		sy *= 1.0 + 0.06 * lush_t
	var slope_sink := 0.22 * clampf((0.88 - n.y) / 0.34, 0.0, 1.0)
	var origin := Vector3(pt.x, h - 0.07 - slope_sink, pt.y)
	var xf := _grounded_transform(origin, n, 0.52, rng.randf() * TAU, Vector3(sc, sy, sc))
	var srgb_col := _pick_jittered_color(rng,
		FERN_VOLCANIC_PALETTE if is_volcanic else FERN_TROPICAL_PALETTE, 0.022, 0.10)
	srgb_col = _apply_fern_biome_tint(srgb_col, arch, is_volcanic, pt, h)
	out_xf.append(xf)
	out_col.append(srgb_col.srgb_to_linear())
	_grid_insert(bush_grid, cell_size, pt)


static func _place_jungle_ferns(island: Island, arch: StringName, rng: RandomNumberGenerator,
		target: int, radius: float, max_fern_h: float, is_volcanic: bool,
		meadow_centers: Array[Vector2], keepouts: Array[Vector3], has_pier: bool,
		pier_a: Vector2, pier_b: Vector2, trail_ctx: Dictionary, bush_grid: Dictionary,
		out_xf: Array[Transform3D], out_col: Array[Color]) -> void:
	var min_sep := clampf(radius * 0.022, 1.25, 2.95)
	var cell_size := 2.4

	# Pass 0 (Highland Cliff-Ledge Cascading Ferns): Bold emerald cliff-edge rosettes gripping
	# stepped canyon ledges & upper mountain terraces (h = 18..64 m, n.y >= 0.48) with +0 DC!
	if island.peak_height >= 26.0 and not is_volcanic:
		var highland_cap := mini(target, clampi(int(roundf(float(target) * 0.17)), 12, 36))
		var hl_h_min := 18.0
		var hl_h_max := minf(64.0, island.peak_height * 0.86)
		if hl_h_max > hl_h_min + 0.5:
			var hl_r_min := radius * 0.08
			var hl_r_max := radius * 0.86
			var hl_sep := maxf(1.85, min_sep * 0.84)
			var hl_candidates := _scan_highland_ledge_candidates(island, rng, hl_r_min, hl_r_max,
				hl_h_min, hl_h_max, 0.48, 1.01, keepouts, has_pier, pier_a, pier_b, trail_ctx)
			for cand in hl_candidates:
				if out_xf.size() >= highland_cap:
					break
				var pt: Vector2 = cand["pt"] as Vector2
				if not _grid_is_clear(bush_grid, cell_size, pt, hl_sep):
					continue
				var h: float = float(cand["h"])
				var n: Vector3 = cand["n"] as Vector3
				_append_highland_fern_rosette(arch, rng, pt, h, n, bush_grid, cell_size, out_xf, out_col)

				# Pair with a companion cascading fern along the same ledge terrace when space permits.
				if out_xf.size() < highland_cap:
					var tan_xz := Vector2(-n.z, n.x)
					if tan_xz.length_squared() < 0.0004:
						tan_xz = Vector2(-pt.y, pt.x)
					tan_xz = tan_xz.normalized()
					var rad_xz := Vector2(tan_xz.y, -tan_xz.x)
					var side_sign := 1.0 if rng.randf() < 0.5 else -1.0
					var cpt := pt + tan_xz * (side_sign * rng.randf_range(2.05, 4.6)) + rad_xz * rng.randf_range(-0.9, 0.9)
					var cr := cpt.length()
					if cr >= hl_r_min and cr <= hl_r_max \
							and not _is_in_keepout(cpt, keepouts, has_pier, pier_a, pier_b) \
							and not _is_on_trail(cpt, trail_ctx) \
							and _grid_is_clear(bush_grid, cell_size, cpt, hl_sep):
						var ch := island.surface_height(cpt.x, cpt.y)
						if ch >= hl_h_min and ch <= hl_h_max:
							var cn := island.surface_normal(cpt.x, cpt.y)
							if cn.y >= 0.48:
								_append_highland_fern_rosette(arch, rng, cpt, ch, cn, bush_grid, cell_size, out_xf, out_col)

			if out_xf.size() < highland_cap and hl_sep > 1.75:
				for cand in hl_candidates:
					if out_xf.size() >= highland_cap:
						break
					var pt: Vector2 = cand["pt"] as Vector2
					if not _grid_is_clear(bush_grid, cell_size, pt, 1.75):
						continue
					var h: float = float(cand["h"])
					var n: Vector3 = cand["n"] as Vector3
					_append_highland_fern_rosette(arch, rng, pt, h, n, bush_grid, cell_size, out_xf, out_col)

	# Pass 0.5 (Trail-Border Lush Ferns): Frame footpath edges with arching fern clusters.
	if bool(trail_ctx["active"]) and out_xf.size() < target:
		var half_w: float = float(trail_ctx["half_width"])
		var cos_y: float = float(trail_ctx["cos_y"])
		var sin_y: float = float(trail_ctx["sin_y"])
		var polylines: Array[PackedVector2Array] = trail_ctx["polylines"] as Array[PackedVector2Array]
		var trail_cap := mini(target, out_xf.size() + clampi(int(roundf(float(target) * 0.22)), 10, 48))
		var verge_sep := maxf(1.15, min_sep * 0.68)
		var min_clear := half_w + 0.35

		for poly in polylines:
			if out_xf.size() >= trail_cap:
				break
			var accum := 0.0
			var next_arc := rng.randf_range(1.4, 3.0)
			for i in range(poly.size() - 1):
				if out_xf.size() >= trail_cap:
					break
				var a := poly[i]
				var b := poly[i + 1]
				var seg := b - a
				var seg_len := seg.length()
				if seg_len < 0.001:
					continue
				var dir_uv := seg / seg_len
				var perp_uv := Vector2(-dir_uv.y, dir_uv.x)
				while next_arc <= accum + seg_len and out_xf.size() < trail_cap:
					var t := (next_arc - accum) / seg_len
					var base_uv := a + seg * t
					var side := 1.0 if rng.randf() < 0.5 else -1.0
					var off := half_w + rng.randf_range(0.55, 2.30)
					var pt := _uv_to_local_xz(base_uv + perp_uv * (side * off), cos_y, sin_y)
					if not _is_in_keepout(pt, keepouts, has_pier, pier_a, pier_b) \
							and _trail_distance(pt, trail_ctx) >= min_clear \
							and _grid_is_clear(bush_grid, cell_size, pt, verge_sep):
						var h := island.surface_height(pt.x, pt.y)
						if h >= 2.15 and h <= max_fern_h + 3.0:
							var n := island.surface_normal(pt.x, pt.y)
							if n.y >= 0.64:
								_append_jungle_fern_instance(arch, rng, pt, h, n, is_volcanic,
									bush_grid, cell_size, out_xf, out_col, rng.randf_range(0.92, 1.12))
					next_arc += rng.randf_range(3.6, 5.8)
				accum += seg_len

	# Pass 1: Shady inland glades, cove pockets & layered companion fern clusters.
	var passes: Array[Array] = [
		[2.85, max_fern_h, 0.72, min_sep, 0.58, target * 16 + 200],
		[2.35, max_fern_h + 5.0, 0.66, min_sep * 0.66, 0.32, target * 12 + 180],
		[2.05, max_fern_h + 8.0, 0.62, maxf(0.90, min_sep * 0.48), 0.20, target * 14 + 240],
	]

	for cfg in passes:
		if out_xf.size() >= target:
			break
		var h_min: float = float(cfg[0])
		var h_max: float = float(cfg[1])
		var n_min: float = float(cfg[2])
		var sep: float = float(cfg[3])
		var cluster_prob: float = float(cfg[4])
		var attempts: int = int(cfg[5])
		var patch_max := clampf(radius * 0.20, 7.0, 24.0)

		for _i in attempts:
			if out_xf.size() >= target:
				break
			var pt := _sample_clustered_xz(rng, meadow_centers, radius * 0.06, radius * 0.92,
				cluster_prob, 1.5, patch_max)
			if _is_in_keepout(pt, keepouts, has_pier, pier_a, pier_b):
				continue
			if _is_on_trail(pt, trail_ctx):
				continue
			if not _grid_is_clear(bush_grid, cell_size, pt, sep):
				continue
			var h := island.surface_height(pt.x, pt.y)
			if h < h_min or h > h_max:
				continue
			var n := island.surface_normal(pt.x, pt.y)
			if n.y < n_min:
				continue

			_append_jungle_fern_instance(arch, rng, pt, h, n, is_volcanic, bush_grid, cell_size, out_xf, out_col)

			# Cluster a companion layered fern in lush cove pockets & shady inland glades!
			if not is_volcanic and out_xf.size() < target and h <= 18.0 and rng.randf() < 0.34:
				var c_ang := rng.randf() * TAU
				var c_dist := rng.randf_range(1.45, 2.95)
				var cpt := pt + Vector2(cos(c_ang) * c_dist, sin(c_ang) * c_dist)
				if not _is_in_keepout(cpt, keepouts, has_pier, pier_a, pier_b) \
						and not _is_on_trail(cpt, trail_ctx) \
						and _grid_is_clear(bush_grid, cell_size, cpt, maxf(1.05, sep * 0.62)):
					var ch := island.surface_height(cpt.x, cpt.y)
					if ch >= h_min and ch <= h_max:
						var cn := island.surface_normal(cpt.x, cpt.y)
						if cn.y >= n_min:
							_append_jungle_fern_instance(arch, rng, cpt, ch, cn, is_volcanic,
								bush_grid, cell_size, out_xf, out_col, rng.randf_range(0.76, 1.04))


static func _append_hibiscus_instance(arch: StringName, rng: RandomNumberGenerator, pt: Vector2,
		h: float, n: Vector3, is_volcanic: bool, bush_grid: Dictionary, cell_size: float,
		out_xf: Array[Transform3D], out_col: Array[Color], out_pos: PackedVector3Array,
		scale_mul: float = 1.0) -> void:
	var sc := rng.randf_range(0.82, 1.44) * scale_mul * (0.74 if is_volcanic else 1.0)
	var sy := sc * rng.randf_range(0.88, 1.18)
	if not is_volcanic and arch in LAGOON_ATOLL_ARCHETYPES:
		sc *= 1.05
		sy *= 1.04
	var slope_sink := 0.22 * clampf((0.88 - n.y) / 0.34, 0.0, 1.0)
	var origin := Vector3(pt.x, h - 0.08 - slope_sink, pt.y)
	var xf := _grounded_transform(origin, n, 0.42, rng.randf() * TAU, Vector3(sc, sy, sc))
	var tint_srgb := _pick_jittered_color(rng,
		HIBISCUS_VOLCANIC_TINTS if is_volcanic else HIBISCUS_TROPICAL_TINTS, 0.015, 0.05)
	tint_srgb = _apply_hibiscus_biome_tint(tint_srgb, arch, is_volcanic, pt)
	out_xf.append(xf)
	out_col.append(tint_srgb.srgb_to_linear())
	out_pos.append(origin)
	_grid_insert(bush_grid, cell_size, pt)


static func _place_hibiscus_shrubs(island: Island, arch: StringName, rng: RandomNumberGenerator,
		target: int, radius: float, max_shrub_h: float, is_volcanic: bool,
		meadow_centers: Array[Vector2], keepouts: Array[Vector3], has_pier: bool,
		pier_a: Vector2, pier_b: Vector2, trail_ctx: Dictionary, bush_grid: Dictionary,
		out_xf: Array[Transform3D], out_col: Array[Color], out_pos: PackedVector3Array) -> void:
	var min_sep := clampf(radius * 0.027, 1.50, 3.45)
	var cell_size := 2.4

	# Pass 0 (Trail-Border Flowering Hibiscus): Frame sunlit trail shoulders with vibrant blossoms!
	if bool(trail_ctx["active"]) and out_xf.size() < target:
		var half_w: float = float(trail_ctx["half_width"])
		var cos_y: float = float(trail_ctx["cos_y"])
		var sin_y: float = float(trail_ctx["sin_y"])
		var polylines: Array[PackedVector2Array] = trail_ctx["polylines"] as Array[PackedVector2Array]
		var trail_cap := mini(target, clampi(int(roundf(float(target) * 0.24)), 8, 34))
		var verge_sep := maxf(1.30, min_sep * 0.72)
		var min_clear := half_w + 0.45

		for poly in polylines:
			if out_xf.size() >= trail_cap:
				break
			var accum := 0.0
			var next_arc := rng.randf_range(2.2, 4.4)
			for i in range(poly.size() - 1):
				if out_xf.size() >= trail_cap:
					break
				var a := poly[i]
				var b := poly[i + 1]
				var seg := b - a
				var seg_len := seg.length()
				if seg_len < 0.001:
					continue
				var dir_uv := seg / seg_len
				var perp_uv := Vector2(-dir_uv.y, dir_uv.x)
				while next_arc <= accum + seg_len and out_xf.size() < trail_cap:
					var t := (next_arc - accum) / seg_len
					var base_uv := a + seg * t
					var side := 1.0 if rng.randf() < 0.5 else -1.0
					var off := half_w + rng.randf_range(0.65, 2.55)
					var pt := _uv_to_local_xz(base_uv + perp_uv * (side * off), cos_y, sin_y)
					if not _is_in_keepout(pt, keepouts, has_pier, pier_a, pier_b) \
							and _trail_distance(pt, trail_ctx) >= min_clear \
							and _grid_is_clear(bush_grid, cell_size, pt, verge_sep):
						var h := island.surface_height(pt.x, pt.y)
						if h >= 2.55 and h <= max_shrub_h + 2.0:
							var n := island.surface_normal(pt.x, pt.y)
							if n.y >= 0.66:
								_append_hibiscus_instance(arch, rng, pt, h, n, is_volcanic,
									bush_grid, cell_size, out_xf, out_col, out_pos, rng.randf_range(0.92, 1.12))
					next_arc += rng.randf_range(4.6, 7.2)
				accum += seg_len

	# Pass 1: Sunlit meadow glades, cove pockets & paired flowering hibiscus clusters.
	var passes: Array[Array] = [
		[3.05, max_shrub_h, 0.74, min_sep, 0.54, target * 18 + 180],
		[2.85, max_shrub_h + 5.0, 0.68, min_sep * 0.66, 0.30, target * 14 + 160],
		[2.85, max_shrub_h + 8.0, 0.64, maxf(1.00, min_sep * 0.48), 0.18, target * 16 + 240],
	]

	for cfg in passes:
		if out_xf.size() >= target:
			break
		var h_min: float = float(cfg[0])
		var h_max: float = float(cfg[1])
		var n_min: float = float(cfg[2])
		var sep: float = float(cfg[3])
		var cluster_prob: float = float(cfg[4])
		var attempts: int = int(cfg[5])
		var patch_max := clampf(radius * 0.19, 6.5, 22.0)

		for _i in attempts:
			if out_xf.size() >= target:
				break
			var pt := _sample_clustered_xz(rng, meadow_centers, radius * 0.08, radius * 0.90,
				cluster_prob, 1.7, patch_max)
			if _is_in_keepout(pt, keepouts, has_pier, pier_a, pier_b):
				continue
			if _is_on_trail(pt, trail_ctx):
				continue
			if not _grid_is_clear(bush_grid, cell_size, pt, sep):
				continue
			var h := island.surface_height(pt.x, pt.y)
			if h < h_min or h > h_max:
				continue
			var n := island.surface_normal(pt.x, pt.y)
			if n.y < n_min:
				continue

			_append_hibiscus_instance(arch, rng, pt, h, n, is_volcanic, bush_grid, cell_size, out_xf, out_col, out_pos)

			# Pair occasional companion hibiscus shrub in lush cove pockets & sunlit meadow glades!
			if not is_volcanic and out_xf.size() < target and h <= 16.0 and rng.randf() < 0.28:
				var c_ang := rng.randf() * TAU
				var c_dist := rng.randf_range(1.75, 3.35)
				var cpt := pt + Vector2(cos(c_ang) * c_dist, sin(c_ang) * c_dist)
				if not _is_in_keepout(cpt, keepouts, has_pier, pier_a, pier_b) \
						and not _is_on_trail(cpt, trail_ctx) \
						and _grid_is_clear(bush_grid, cell_size, cpt, maxf(1.20, sep * 0.65)):
					var ch := island.surface_height(cpt.x, cpt.y)
					if ch >= h_min and ch <= h_max:
						var cn := island.surface_normal(cpt.x, cpt.y)
						if cn.y >= n_min:
							_append_hibiscus_instance(arch, rng, cpt, ch, cn, is_volcanic,
								bush_grid, cell_size, out_xf, out_col, out_pos, rng.randf_range(0.76, 1.02))


# ------------------------------------------------------------------ placement: 3D trail stepping stones & curbs

static func _place_trail_stepping_stones(island: Island, arch: StringName, rng: RandomNumberGenerator,
		is_volcanic: bool, keepouts: Array[Vector3], has_pier: bool, pier_a: Vector2, pier_b: Vector2,
		trail_ctx: Dictionary, out_xf: Array[Transform3D], out_col: Array[Color]) -> void:
	if not bool(trail_ctx["active"]):
		return
	var polylines: Array[PackedVector2Array] = trail_ctx["polylines"] as Array[PackedVector2Array]
	if polylines.is_empty():
		return

	var half_w: float = float(trail_ctx["half_width"])
	var cos_y: float = float(trail_ctx["cos_y"])
	var sin_y: float = float(trail_ctx["sin_y"])
	var palette: Array[Color] = STEPPING_STONE_VOLCANIC_PALETTE if is_volcanic else (
		STEPPING_STONE_SLATE_PALETTE if arch in STEPPING_SLATE_ARCHETYPES else STEPPING_STONE_TROPICAL_PALETTE)

	var cell_size := 2.4
	var stone_grid: Dictionary = {}

	# 1. Path Stepping Stones: wide beveled flagstones stepping up walkable trail stretches!
	var step_side_alt := 1.0
	for poly in polylines:
		var accum := 0.0
		var next_arc := rng.randf_range(1.0, 2.2)
		for i in range(poly.size() - 1):
			var a := poly[i]
			var b := poly[i + 1]
			var seg := b - a
			var seg_len := seg.length()
			if seg_len < 0.001:
				continue
			var dir_uv := seg / seg_len
			var perp_uv := Vector2(-dir_uv.y, dir_uv.x)
			var tan_local := _uv_to_local_xz(dir_uv, cos_y, sin_y).normalized()
			var base_yaw := atan2(-tan_local.x, -tan_local.y)

			while next_arc <= accum + seg_len:
				var t := (next_arc - accum) / seg_len
				var lat := step_side_alt * rng.randf_range(0.08, minf(0.65, half_w * 0.24))
				step_side_alt = -step_side_alt
				var pt_uv := a + seg * t + perp_uv * lat
				var pt := _uv_to_local_xz(pt_uv, cos_y, sin_y)

				var is_sloped_step := false
				if not _is_in_keepout(pt, keepouts, has_pier, pier_a, pier_b):
					var h := island.surface_height(pt.x, pt.y)
					if h >= 0.85:
						var n := island.surface_normal(pt.x, pt.y)
						is_sloped_step = n.y < 0.93 and h > 3.2
						var min_stone_sep := 2.05 if is_sloped_step else 2.4
						if n.y >= 0.72 and _grid_is_clear(stone_grid, cell_size, pt, min_stone_sep):
							var sx := rng.randf_range(0.88, 1.34)
							var sz := rng.randf_range(0.78, 1.18)
							var sy := rng.randf_range(0.68, 0.92)
							var slope_sink := 0.08 * clampf((0.96 - n.y) / 0.24, 0.0, 1.0)
							var yaw: float
							var origin: Vector3
							var xf: Transform3D
							if is_sloped_step:
								# Widen/thicken slab & level tilt toward horizontal so sloped climbs read
								# as hand-laid pirate stone terrace steps (+0 extra DCs, 0 extra VRAM).
								sx *= 1.32
								sy *= 1.38
								sz *= 1.15
								var up_dir := n.lerp(Vector3.UP, 0.42).normalized()
								origin = Vector3(pt.x, h - 0.04 - slope_sink - 0.08, pt.y)
								yaw = base_yaw + rng.randf_range(-0.18, 0.18)
								xf = _grounded_transform(origin, up_dir, 1.0, yaw, Vector3(sx, sy, sz))
							else:
								origin = Vector3(pt.x, h - 0.04 - slope_sink, pt.y)
								yaw = base_yaw + rng.randf_range(-0.28, 0.28)
								xf = _grounded_transform(origin, n, 0.92, yaw, Vector3(sx, sy, sz))
							out_xf.append(xf)
							out_col.append(_pick_jittered_color(rng, palette, 0.014, 0.08))
							_grid_insert(stone_grid, cell_size, pt)
				next_arc += rng.randf_range(2.6, 3.6) if is_sloped_step else rng.randf_range(3.6, 5.0)
			accum += seg_len

	# 2. Trail-Edge Curb Rocks: chunkier slightly tilted border stones staggered along both shoulders!
	var min_curb_clear := half_w + 0.15
	for side_idx in 2:
		var side := -1.0 if side_idx == 0 else 1.0
		for poly in polylines:
			var accum := 0.0
			var next_arc := rng.randf_range(1.1, 2.7) if side_idx == 0 else rng.randf_range(3.0, 4.8)
			for i in range(poly.size() - 1):
				var a := poly[i]
				var b := poly[i + 1]
				var seg := b - a
				var seg_len := seg.length()
				if seg_len < 0.001:
					continue
				var dir_uv := seg / seg_len
				var perp_uv := Vector2(-dir_uv.y, dir_uv.x)
				var tan_local := _uv_to_local_xz(dir_uv, cos_y, sin_y).normalized()
				var base_yaw := atan2(-tan_local.x, -tan_local.y)

				while next_arc <= accum + seg_len:
					var t := (next_arc - accum) / seg_len
					var off := half_w + rng.randf_range(0.35, 0.85)
					var pt_uv := a + seg * t + perp_uv * (side * off)
					var pt := _uv_to_local_xz(pt_uv, cos_y, sin_y)

					if not _is_in_keepout(pt, keepouts, has_pier, pier_a, pier_b) \
							and _trail_distance(pt, trail_ctx) >= min_curb_clear \
							and _grid_is_clear(stone_grid, cell_size, pt, 1.95):
						var h := island.surface_height(pt.x, pt.y)
						if h >= 1.25:
							var n := island.surface_normal(pt.x, pt.y)
							if n.y >= 0.62:
								var sx := rng.randf_range(0.58, 0.98)
								var sz := rng.randf_range(0.84, 1.38)
								var sy := rng.randf_range(1.30, 2.25)
								var slope_sink := 0.14 * clampf((0.92 - n.y) / 0.30, 0.0, 1.0)
								var origin := Vector3(pt.x, h - 0.07 - slope_sink, pt.y)
								# Gently tilt border rock slightly toward/away from trail shoulder.
								var tilt_n := (n + Vector3(rng.randf_range(-0.18, 0.18), 0.0, rng.randf_range(-0.18, 0.18))).normalized()
								var yaw := base_yaw + rng.randf_range(-0.34, 0.34)
								var xf := _grounded_transform(origin, tilt_n, 0.72, yaw, Vector3(sx, sy, sz))
								var curb_c := _pick_jittered_color(rng, palette, 0.015, 0.09)
								var shade := rng.randf_range(0.88, 0.96)
								out_xf.append(xf)
								out_col.append(Color(curb_c.r * shade, curb_c.g * shade, curb_c.b * shade, 1.0))
								_grid_insert(stone_grid, cell_size, pt)
					next_arc += rng.randf_range(4.0, 5.8)
				accum += seg_len


# ------------------------------------------------------------------ placement & animation: living tropical butterflies

static func _shuffle_vec2_array(rng: RandomNumberGenerator, arr: Array[Vector2]) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Vector2 = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


static func _place_butterflies(island: Island, rng: RandomNumberGenerator, target: int,
		radius: float, hibiscus_pos: PackedVector3Array, meadow_centers: Array[Vector2],
		grass_pos: PackedVector3Array, trail_ctx: Dictionary, keepouts: Array[Vector3],
		has_pier: bool, pier_a: Vector2, pier_b: Vector2,
		out_xf: Array[Transform3D], out_col: Array[Color],
		out_orbits: Array[Dictionary]) -> void:
	if target <= 0:
		return

	# Build deterministic anchor pools prioritizing flowering hibiscus shrubs, trail borders, and sunlit meadows.
	var hib_pool: Array[Vector2] = []
	for hp in hibiscus_pos:
		hib_pool.append(Vector2(hp.x, hp.z))
	_shuffle_vec2_array(rng, hib_pool)

	var trail_pool: Array[Vector2] = []
	if bool(trail_ctx["active"]):
		var half_w: float = float(trail_ctx["half_width"])
		var cos_y: float = float(trail_ctx["cos_y"])
		var sin_y: float = float(trail_ctx["sin_y"])
		var polylines: Array[PackedVector2Array] = trail_ctx["polylines"] as Array[PackedVector2Array]
		for poly in polylines:
			var accum := 0.0
			var next_arc := rng.randf_range(3.0, 6.0)
			for i in range(poly.size() - 1):
				var a := poly[i]
				var b := poly[i + 1]
				var seg := b - a
				var seg_len := seg.length()
				if seg_len < 0.001:
					continue
				var dir_uv := seg / seg_len
				var perp_uv := Vector2(-dir_uv.y, dir_uv.x)
				while next_arc <= accum + seg_len:
					var t := (next_arc - accum) / seg_len
					var side := 1.0 if rng.randf() < 0.5 else -1.0
					var off := half_w + rng.randf_range(0.6, 2.4)
					var pt := _uv_to_local_xz(a + seg * t + perp_uv * (side * off), cos_y, sin_y)
					if not _is_in_keepout(pt, keepouts, has_pier, pier_a, pier_b):
						trail_pool.append(pt)
					next_arc += rng.randf_range(5.5, 9.5)
				accum += seg_len
	_shuffle_vec2_array(rng, trail_pool)

	var meadow_pool: Array[Vector2] = []
	for mc in meadow_centers:
		meadow_pool.append(mc)
	var grass_stride := maxi(1, int(float(grass_pos.size()) / 48.0))
	var gi := 0
	while gi < grass_pos.size():
		meadow_pool.append(Vector2(grass_pos[gi].x, grass_pos[gi].z))
		gi += grass_stride
	_shuffle_vec2_array(rng, meadow_pool)

	# Interleave candidates: ~55% hibiscus, ~25% trail borders, ~20% sunlit meadows.
	var candidates: Array[Vector2] = []
	var hi := 0
	var ti := 0
	var mi := 0
	while hi < hib_pool.size() or ti < trail_pool.size() or mi < meadow_pool.size():
		for _k in 3:
			if hi < hib_pool.size():
				candidates.append(hib_pool[hi])
				hi += 1
		if ti < trail_pool.size():
			candidates.append(trail_pool[ti])
			ti += 1
		if mi < meadow_pool.size():
			candidates.append(meadow_pool[mi])
			mi += 1

	var cell_size := maxf(4.0, radius * 0.08)
	var bf_grid: Dictionary = {}
	var spacing_passes: Array[float] = [clampf(radius * 0.075, 4.5, 11.5), 2.4, 0.8]

	for min_sep in spacing_passes:
		if out_orbits.size() >= target:
			break
		for pt in candidates:
			if out_orbits.size() >= target:
				break
			if not _grid_is_clear(bf_grid, cell_size, pt, min_sep):
				continue
			var ground_h := island.surface_height(pt.x, pt.y)
			if ground_h < 1.0:
				continue
			var orbit_rx := rng.randf_range(1.4, 3.1)
			var orbit_rz := rng.randf_range(1.1, 2.4)
			var safe_ground := ground_h
			safe_ground = maxf(safe_ground, island.surface_height(pt.x + orbit_rx, pt.y))
			safe_ground = maxf(safe_ground, island.surface_height(pt.x - orbit_rx, pt.y))
			safe_ground = maxf(safe_ground, island.surface_height(pt.x, pt.y + orbit_rz))
			safe_ground = maxf(safe_ground, island.surface_height(pt.x, pt.y - orbit_rz))
			var hover_h := rng.randf_range(0.8, 3.4)
			var home := Vector3(pt.x, maxf(ground_h + hover_h, safe_ground + 0.65), pt.y)

			var orbit := {
				"home": home,
				"radius_x": orbit_rx,
				"radius_z": orbit_rz,
				"yaw_frame": rng.randf() * TAU,
				"phase": rng.randf() * TAU,
				"speed": rng.randf_range(0.55, 1.05),
				"bob_amp": rng.randf_range(0.22, 0.52),
				"bob_freq": rng.randf_range(1.5, 2.7),
				"flap_freq": rng.randf_range(7.8, 11.6),
				"flap_phase": rng.randf() * TAU,
				"scale": rng.randf_range(0.85, 1.35),
			}
			out_orbits.append(orbit)
			out_xf.append(_compute_butterfly_transform(orbit, 0.0))
			out_col.append(_pick_jittered_color(rng, BUTTERFLY_PALETTE, 0.012, 0.05))
			_grid_insert(bf_grid, cell_size, pt)


static func _compute_butterfly_transform(orbit: Dictionary, clock: float) -> Transform3D:
	var home: Vector3 = orbit["home"] as Vector3
	var rx: float = float(orbit["radius_x"])
	var rz: float = float(orbit["radius_z"])
	var yaw_frame: float = float(orbit["yaw_frame"])
	var phase: float = float(orbit["phase"])
	var speed: float = float(orbit["speed"])
	var bob_amp: float = float(orbit["bob_amp"])
	var bob_freq: float = float(orbit["bob_freq"])
	var flap_freq: float = float(orbit["flap_freq"])
	var flap_phase: float = float(orbit["flap_phase"])
	var sc: float = float(orbit["scale"])

	var theta := phase + clock * speed
	var lx := sin(theta) * rx
	var lz := sin(theta * 2.0) * 0.5 * rz
	var dlx := cos(theta) * rx * speed
	var dlz := cos(theta * 2.0) * rz * speed

	var cf := cos(yaw_frame)
	var sf := sin(yaw_frame)
	var dx := lx * cf - lz * sf
	var dz := lx * sf + lz * cf
	var vx := dlx * cf - dlz * sf
	var vz := dlx * sf + dlz * cf

	var flap := sin(clock * flap_freq + flap_phase)
	var bob := sin(clock * bob_freq + phase) * bob_amp + flap * 0.045
	var vy := cos(clock * bob_freq + phase) * bob_amp * bob_freq
	var pos := home + Vector3(dx, bob, dz)

	var horiz_sq := vx * vx + vz * vz
	var heading_yaw := atan2(-vx, -vz) if horiz_sq > 1e-6 else yaw_frame
	var pitch := clampf(atan2(vy, maxf(sqrt(horiz_sq), 0.35)), -0.35, 0.35)
	var roll := flap * 0.34 + cos(theta) * 0.14

	var sx_flap := sc * (1.0 - maxf(0.0, flap) * 0.22)
	var sy_flap := sc * (1.0 + flap * 0.60)
	var rot := Basis(Vector3.UP, heading_yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)
	return Transform3D(rot.scaled(Vector3(sx_flap, sy_flap, sc)), pos)


# ------------------------------------------------------------------ placement & animation: shoreline tidepool crabs

static func _place_shore_crabs(island: Island, rng: RandomNumberGenerator, target: int,
		radius: float, keepouts: Array[Vector3], has_pier: bool, pier_a: Vector2, pier_b: Vector2,
		out_xf: Array[Transform3D], out_col: Array[Color],
		out_orbits: Array[Dictionary]) -> void:
	if target <= 0:
		return

	var r_min := maxf(4.0, radius * 0.14)
	var r_max := maxf(r_min + 10.0, island.seabed_radius * 0.92)
	var base_sep := clampf(radius * 0.085, 3.2, 9.5)
	var cell_size := maxf(3.0, base_sep * 0.6)
	var crab_grid: Dictionary = {}

	# Passes 1 & 2: Stochastic shoreline sampling along wet sandy beaches, pocket coves & tidepool shelves.
	var random_passes: Array[Array] = [
		[base_sep, target * 48 + 420],
		[maxf(2.0, base_sep * 0.52), target * 40 + 360],
	]
	for cfg in random_passes:
		if out_orbits.size() >= target:
			break
		var sep: float = float(cfg[0])
		var attempts: int = int(cfg[1])
		for _i in attempts:
			if out_orbits.size() >= target:
				break
			var pt0 := _sample_annulus_xz(rng, r_min, r_max)
			if _is_in_keepout(pt0, keepouts, has_pier, pier_a, pier_b, 0.5):
				continue
			if not _grid_is_clear(crab_grid, cell_size, pt0, sep):
				continue
			var h0 := island.surface_height(pt0.x, pt0.y)
			if h0 < 0.28 or h0 > 2.35:
				continue
			var n0 := island.surface_normal(pt0.x, pt0.y)
			if n0.y < 0.80:
				continue
			var orbit := _try_build_crab_track(island, rng, pt0, h0, n0, keepouts, has_pier, pier_a, pier_b)
			if orbit.is_empty():
				continue
			out_orbits.append(orbit)
			out_xf.append(_compute_crab_transform(orbit, 0.0))
			out_col.append(_pick_jittered_color(rng, CRAB_PALETTE, 0.014, 0.06))
			_grid_insert(crab_grid, cell_size, pt0)

	# Pass 3 (Deterministic Shoreline Scan Fallback): Guarantee pocket coves & tidepool shelves are
	# discovered even on compact steep islands (e.g. sea_stack / fort_rock).
	if out_orbits.size() < target:
		var scan_pts: Array[Vector2] = []
		var radial_steps := clampi(int(roundf((r_max - r_min) / 1.8)), 16, 32)
		var arc_step := clampf(radius * 0.042, 1.4, 3.6)
		for ri in range(1, radial_steps + 1):
			var frac := float(ri) / float(radial_steps)
			var r_ring := lerpf(r_min, r_max, frac)
			var ring_n := maxi(20, int(roundf(TAU * r_ring / arc_step)))
			var phase_ang := float(ri) * 0.383
			for ai in ring_n:
				var ang := phase_ang + float(ai) / float(ring_n) * TAU
				var pt := Vector2(cos(ang) * r_ring, sin(ang) * r_ring)
				if _is_in_keepout(pt, keepouts, has_pier, pier_a, pier_b, 0.5):
					continue
				var h_s := island.surface_height(pt.x, pt.y)
				if h_s < 0.28 or h_s > 2.35:
					continue
				if island.surface_normal(pt.x, pt.y).y < 0.80:
					continue
				scan_pts.append(pt)
		_shuffle_vec2_array(rng, scan_pts)

		for fallback_sep: float in [1.8, 1.1]:
			if out_orbits.size() >= target:
				break
			for pt0 in scan_pts:
				if out_orbits.size() >= target:
					break
				if not _grid_is_clear(crab_grid, cell_size, pt0, fallback_sep):
					continue
				var h0 := island.surface_height(pt0.x, pt0.y)
				var n0 := island.surface_normal(pt0.x, pt0.y)
				var orbit := _try_build_crab_track(island, rng, pt0, h0, n0, keepouts, has_pier, pier_a, pier_b)
				if orbit.is_empty():
					continue
				out_orbits.append(orbit)
				out_xf.append(_compute_crab_transform(orbit, 0.0))
				out_col.append(_pick_jittered_color(rng, CRAB_PALETTE, 0.014, 0.06))
				_grid_insert(crab_grid, cell_size, pt0)


static func _try_build_crab_track(island: Island, rng: RandomNumberGenerator, pt0: Vector2,
		h0: float, n0: Vector3, keepouts: Array[Vector3], has_pier: bool,
		pier_a: Vector2, pier_b: Vector2) -> Dictionary:
	# Compute horizontal shore-tangent axis perpendicular to downhill beach slope.
	var slope_xz := Vector2(n0.x, n0.z)
	var tan_xz := Vector2(-slope_xz.y, slope_xz.x)
	if tan_xz.length_squared() < 0.0004:
		tan_xz = Vector2(-pt0.y, pt0.x)
	if tan_xz.length_squared() < 0.0004:
		tan_xz = Vector2.RIGHT
	else:
		tan_xz = tan_xz.normalized()

	var pref_sign := 1.0 if rng.randf() < 0.5 else -1.0
	var base_jitter := rng.randf_range(-0.18, 0.18)
	var try_specs: Array[Array] = [
		[pref_sign, base_jitter, rng.randf_range(1.5, 2.8)],
		[-pref_sign, -base_jitter, rng.randf_range(1.4, 2.5)],
		[pref_sign, base_jitter + 0.28, rng.randf_range(1.2, 1.8)],
		[-pref_sign, -base_jitter - 0.28, rng.randf_range(1.2, 1.8)],
	]

	for spec in try_specs:
		var sgn: float = float(spec[0])
		var ang_off: float = float(spec[1])
		var span: float = float(spec[2])
		var dir_xz := (tan_xz * sgn).rotated(ang_off).normalized()
		var pt1 := pt0 + dir_xz * span
		if _is_in_keepout(pt1, keepouts, has_pier, pier_a, pier_b, 0.5):
			continue
		var h1 := island.surface_height(pt1.x, pt1.y)
		if h1 < 0.25 or h1 > 2.50:
			continue
		var n1 := island.surface_normal(pt1.x, pt1.y)
		if n1.y < 0.78:
			continue
		var ptm := (pt0 + pt1) * 0.5
		if _is_in_keepout(ptm, keepouts, has_pier, pier_a, pier_b, 0.5):
			continue
		var hm := island.surface_height(ptm.x, ptm.y)
		if hm < 0.25 or hm > 2.50 or absf(hm - 0.5 * (h0 + h1)) > 0.20:
			continue
		var nm := island.surface_normal(ptm.x, ptm.y)
		if nm.y < 0.78:
			continue

		# Face local -Z (pincers & eyes) perpendicular to the scuttle track so crabs scuttle sideways!
		var face_dir := Vector2(-dir_xz.y, dir_xz.x)
		if slope_xz.length_squared() > 0.0004 and face_dir.dot(slope_xz) < 0.0:
			face_dir = -face_dir
		if rng.randf() < 0.25:
			face_dir = -face_dir
		var face_yaw := atan2(-face_dir.x, -face_dir.y) + rng.randf_range(-0.14, 0.14)

		return {
			"p0": Vector3(pt0.x, h0 + 0.005, pt0.y),
			"p1": Vector3(pt1.x, h1 + 0.005, pt1.y),
			"n0": n0.normalized(),
			"n1": n1.normalized(),
			"face_yaw": face_yaw,
			"cycle_dur": rng.randf_range(4.2, 7.6),
			"phase": rng.randf(),
			"wiggle_freq": rng.randf_range(16.0, 23.0),
			"scale": rng.randf_range(0.74, 1.16),
		}
	return {}


static func _compute_crab_transform(orbit: Dictionary, clock: float) -> Transform3D:
	var p0: Vector3 = orbit["p0"] as Vector3
	var p1: Vector3 = orbit["p1"] as Vector3
	var n0: Vector3 = orbit["n0"] as Vector3
	var n1: Vector3 = orbit["n1"] as Vector3
	var face_yaw: float = float(orbit["face_yaw"])
	var cycle_dur: float = float(orbit["cycle_dur"])
	var phase: float = float(orbit["phase"])
	var wiggle_freq: float = float(orbit["wiggle_freq"])
	var sc: float = float(orbit["scale"])

	# Sideways crab-scuttle rhythm:
	# [0.00..0.28) burst p0 -> p1 | [0.28..0.50) alert pause | [0.50..0.78) burst p1 -> p0 | [0.78..1.00) alert pause
	var cyc := fposmod(clock / maxf(cycle_dur, 0.5) + phase, 1.0)
	var u := 0.0
	var moving := 0.0
	if cyc < 0.28:
		var s := cyc / 0.28
		u = s * s * (3.0 - 2.0 * s)
		moving = sin(s * PI)
	elif cyc < 0.50:
		u = 1.0
	elif cyc < 0.78:
		var s := (cyc - 0.50) / 0.28
		u = 1.0 - (s * s * (3.0 - 2.0 * s))
		moving = sin(s * PI)

	var pos := p0.lerp(p1, u)
	var n := n0.lerp(n1, u)
	n = n.normalized() if n.length_squared() > 1e-6 else Vector3.UP

	var wig := sin(clock * wiggle_freq + phase * TAU)
	var alert_glance := sin(clock * 1.9 + phase * TAU) * 0.07
	var yaw := face_yaw + wig * 0.14 * moving + alert_glance * (1.0 - moving)
	var roll := cos(clock * wiggle_freq + phase * TAU) * 0.09 * moving
	var hop := absf(wig) * 0.018 * moving * sc
	var origin := pos + n * hop

	var up_axis := Vector3.UP.lerp(n, 0.92).normalized()
	var ref_fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right_axis := ref_fwd.cross(up_axis)
	if right_axis.length_squared() < 0.0001:
		right_axis = Vector3.RIGHT
	else:
		right_axis = right_axis.normalized()
	var back_axis := right_axis.cross(up_axis).normalized()
	var xform_basis := (Basis(right_axis, up_axis, back_axis) * Basis(Vector3.BACK, roll)).scaled(Vector3(sc, sc, sc))
	return Transform3D(xform_basis, origin)


# ------------------------------------------------------------------ placement: coastal shoreline layers

static func _place_coastal_driftwood(island: Island, rng: RandomNumberGenerator, target: int,
		radius: float, is_volcanic: bool, keepouts: Array[Vector3], has_pier: bool,
		pier_a: Vector2, pier_b: Vector2, trail_ctx: Dictionary, out_xf: Array[Transform3D],
		out_col: Array[Color]) -> void:
	var r_min := maxf(4.0, radius * 0.16)
	var r_max := maxf(r_min + 8.0, island.seabed_radius * 0.88)
	var base_sep := clampf(radius * 0.068, 2.8, 7.5)
	var cell_size := 4.0
	var grid: Dictionary = {}

	var passes: Array[Array] = [
		[0.30, 3.10, 0.78, base_sep, target * 36 + 320],
		[0.20, 3.40, 0.72, base_sep * 0.62, target * 28 + 260],
	]

	for cfg in passes:
		if out_xf.size() >= target:
			break
		var h_min: float = float(cfg[0])
		var h_max: float = float(cfg[1])
		var n_min: float = float(cfg[2])
		var sep: float = float(cfg[3])
		var attempts: int = int(cfg[4])

		for _i in attempts:
			if out_xf.size() >= target:
				break
			var pt := _sample_annulus_xz(rng, r_min, r_max)
			if _is_in_keepout(pt, keepouts, has_pier, pier_a, pier_b):
				continue
			if _is_on_trail(pt, trail_ctx):
				continue
			if not _grid_is_clear(grid, cell_size, pt, sep):
				continue
			var h := island.surface_height(pt.x, pt.y)
			if h < h_min or h > h_max:
				continue
			var n := island.surface_normal(pt.x, pt.y, 2.0)
			if n.y < n_min:
				continue

			# Align driftwood log (+X local axis) tangentially to the local coastline contour!
			var slope_xz := Vector2(n.x, n.z)
			var tangent_xz := Vector2(-slope_xz.y, slope_xz.x)
			if tangent_xz.length_squared() < 0.0004:
				tangent_xz = Vector2(-pt.y, pt.x)
			tangent_xz = tangent_xz.normalized()
			var flip := 1.0 if rng.randf() < 0.5 else -1.0
			var tan_dir := tangent_xz * flip
			# Local +X under Basis(UP, yaw) is (cos(yaw), 0, -sin(yaw)) -> yaw = atan2(-tan.y, tan.x).
			var yaw := atan2(-tan_dir.y, tan_dir.x) + rng.randf_range(-0.26, 0.26)

			var sc_x := rng.randf_range(0.78, 1.32)
			var sc_yz := sc_x * rng.randf_range(0.84, 1.14)
			# Sample both log endpoints to seat the trunk snugly into sand without floating ends.
			var end_dx := cos(yaw) * (1.05 * sc_x)
			var end_dz := -sin(yaw) * (1.05 * sc_x)
			var h_a := island.surface_height(pt.x + end_dx, pt.y + end_dz)
			var h_b := island.surface_height(pt.x - end_dx, pt.y - end_dz)
			var h_end_min := minf(h_a, h_b)
			if h_end_min < -0.15 or absf(h_a - h_b) > 0.65 or (h - h_end_min) > 0.50:
				continue
			var seat_y := minf(h, h_end_min + 0.14 * sc_yz) - 0.06 * sc_yz

			var xf := _grounded_transform(Vector3(pt.x, seat_y, pt.y), n, 0.72, yaw, Vector3(sc_x, sc_yz, sc_yz))
			var col := _pick_jittered_color(rng,
				DRIFTWOOD_VOLCANIC_PALETTE if is_volcanic else DRIFTWOOD_PALETTE, 0.015, 0.08)
			out_xf.append(xf)
			out_col.append(_apply_wet_shore_sheen(col, h))
			_grid_insert(grid, cell_size, pt)


static func _place_shore_pebbles(island: Island, rng: RandomNumberGenerator, target: int,
		radius: float, is_volcanic: bool, keepouts: Array[Vector3], has_pier: bool,
		pier_a: Vector2, pier_b: Vector2, trail_ctx: Dictionary, out_xf: Array[Transform3D],
		out_col: Array[Color], out_pos: PackedVector3Array) -> void:
	var r_min := maxf(4.0, radius * 0.16)
	var r_max := maxf(r_min + 8.0, island.seabed_radius * 0.90)
	var base_sep := clampf(radius * 0.036, 1.5, 4.2)
	var cell_size := 2.8
	var grid: Dictionary = {}

	var passes: Array[Array] = [
		[-0.25, 2.60, 0.76, base_sep, target * 28 + 340],
		[-0.40, 2.95, 0.70, base_sep * 0.62, target * 22 + 280],
	]

	for cfg in passes:
		if out_xf.size() >= target:
			break
		var h_min: float = float(cfg[0])
		var h_max: float = float(cfg[1])
		var n_min: float = float(cfg[2])
		var sep: float = float(cfg[3])
		var attempts: int = int(cfg[4])

		for _i in attempts:
			if out_xf.size() >= target:
				break
			var pt := _sample_annulus_xz(rng, r_min, r_max)
			if _is_in_keepout(pt, keepouts, has_pier, pier_a, pier_b):
				continue
			if _is_on_trail(pt, trail_ctx):
				continue
			if not _grid_is_clear(grid, cell_size, pt, sep):
				continue
			var h := island.surface_height(pt.x, pt.y)
			if h < h_min or h > h_max:
				continue
			var n := island.surface_normal(pt.x, pt.y)
			if n.y < n_min:
				continue

			var sx := rng.randf_range(0.75, 1.42)
			var sz := sx * rng.randf_range(0.86, 1.16)
			var sy := rng.randf_range(0.78, 1.24)
			var origin := Vector3(pt.x, h - 0.045, pt.y)
			var xf := _grounded_transform(origin, n, 0.82, rng.randf() * TAU, Vector3(sx, sy, sz))
			var col := _pick_jittered_color(rng,
				PEBBLE_VOLCANIC_PALETTE if is_volcanic else PEBBLE_PALETTE, 0.015, 0.08)
			out_xf.append(xf)
			out_col.append(_apply_wet_shore_sheen(col, h))
			out_pos.append(origin)
			_grid_insert(grid, cell_size, pt)


static func _place_tidal_outcrops(island: Island, arch: StringName, rng: RandomNumberGenerator,
		target: int, radius: float, is_volcanic: bool, keepouts: Array[Vector3], has_pier: bool,
		pier_a: Vector2, pier_b: Vector2, trail_ctx: Dictionary, out_xf: Array[Transform3D],
		out_col: Array[Color]) -> void:
	var r_min := maxf(4.0, radius * 0.20)
	var r_max := maxf(r_min + 10.0, island.seabed_radius * 0.92)
	var base_sep := clampf(radius * 0.068, 3.2, 8.2)
	var cell_size := 4.8
	var grid: Dictionary = {}

	var passes: Array[Array] = [
		[-1.10, 1.70, 0.50, base_sep, target * 36 + 340],
		[-1.45, 2.15, 0.44, base_sep * 0.65, target * 28 + 260],
	]

	for cfg in passes:
		if out_xf.size() >= target:
			break
		var h_min: float = float(cfg[0])
		var h_max: float = float(cfg[1])
		var n_min: float = float(cfg[2])
		var sep: float = float(cfg[3])
		var attempts: int = int(cfg[4])

		for _i in attempts:
			if out_xf.size() >= target:
				break
			var pt := _sample_annulus_xz(rng, r_min, r_max)
			if _is_in_keepout(pt, keepouts, has_pier, pier_a, pier_b, 1.2):
				continue
			if _is_on_trail(pt, trail_ctx):
				continue
			if not _grid_is_clear(grid, cell_size, pt, sep):
				continue
			var h := island.surface_height(pt.x, pt.y)
			if h < h_min or h > h_max:
				continue
			var n := island.surface_normal(pt.x, pt.y, 2.0)
			if n.y < n_min:
				continue

			var sc_xz := rng.randf_range(0.76, 1.48)
			var sc_y := sc_xz * rng.randf_range(0.78, 1.26)
			var seat_y := h - 0.24 * sc_y
			var xf := _grounded_transform(Vector3(pt.x, seat_y, pt.y), n, 0.36, rng.randf() * TAU, Vector3(sc_xz, sc_y, sc_xz * rng.randf_range(0.88, 1.14)))
			var base_col := _pick_jittered_color(rng,
				TIDAL_ROCK_VOLCANIC_PALETTE if is_volcanic else TIDAL_ROCK_PALETTE, 0.015, 0.08)
			var col := _apply_tidal_rock_biome_tint(base_col, arch, is_volcanic, pt, h)
			out_xf.append(xf)
			out_col.append(_apply_wet_shore_sheen(col, h))
			_grid_insert(grid, cell_size, pt)


# ------------------------------------------------------------------ placement: steep-slope cliff buttresses

static func _place_cliff_buttresses(island: Island, arch: StringName, rng: RandomNumberGenerator,
		target_total: int, radius: float, is_volcanic: bool, use_wide_layer: bool,
		tall_mesh: Mesh, tall_uses_glb: bool, wide_mesh: Mesh, wide_uses_glb: bool,
		keepouts: Array[Vector3], has_pier: bool, pier_a: Vector2, pier_b: Vector2,
		out_tall_xf: Array[Transform3D], out_tall_col: Array[Color],
		out_wide_xf: Array[Transform3D], out_wide_col: Array[Color],
		out_normals_y: PackedFloat32Array) -> void:
	# 1. Systematically scan radial & elevation rings across grounded lower cliff skirts & mountain bases
	#    (keeps monumental 15-24 m rocky buttresses rooted directly into the valley floor / coastal earth!).
	var max_h: float
	var min_h := 1.6
	if is_volcanic:
		max_h = maxf(8.0, island.peak_height * 0.58)
	elif arch == &"sea_stack":
		min_h = 0.7
		max_h = clampf(island.peak_height * 0.22, 8.5, 11.5)
	elif radius < 70.0:
		max_h = clampf(island.peak_height * 0.24, 9.0, 14.0)
	else:
		max_h = clampf(island.peak_height * 0.26, 11.0, 18.5)
	var candidates: Array[Dictionary] = []  # {pos: Vector3, normal: Vector3, ny: float, az: float}

	var radial_steps := clampi(int(roundf(radius / 3.4)), 14, 38)
	for ri in range(1, radial_steps + 1):
		var frac := float(ri) / float(radial_steps)
		var r := lerpf(radius * 0.08, radius * 0.96, frac)
		var ring_samples := maxi(16, int(roundf(TAU * r / clampf(radius * 0.055, 3.2, 6.2))))
		var phase := float(ri) * 0.417
		for ai in ring_samples:
			var ang := phase + float(ai) / float(ring_samples) * TAU
			var px := cos(ang) * r
			var pz := sin(ang) * r
			var pt := Vector2(px, pz)
			if _is_in_keepout(pt, keepouts, has_pier, pier_a, pier_b, 2.5):
				continue
			var h := island.surface_height(px, pz)
			if h <= min_h or h >= max_h:
				continue
			var n := island.surface_normal(px, pz)
			if n.y >= BUTTRESS_MAX_NORMAL_Y or n.y <= BUTTRESS_MIN_NORMAL_Y:
				continue
			var out_xz := Vector3(n.x, 0.0, n.z)
			if out_xz.length_squared() < 0.04:
				continue
			candidates.append({
				"pos": Vector3(px, h, pz),
				"out_xz": out_xz.normalized(),
				"ny": n.y,
			})

	if candidates.is_empty():
		return

	# Deterministic Fisher-Yates shuffle so buttresses distribute evenly around every cliff face.
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Dictionary = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	var tall_aabb := tall_mesh.get_aabb()
	var wide_aabb := wide_mesh.get_aabb() if use_wide_layer else tall_aabb
	var tall_probes := _extract_buttress_probe_points(tall_mesh, tall_aabb)
	var wide_probes := _extract_buttress_probe_points(wide_mesh, wide_aabb) if use_wide_layer else tall_probes
	var primary_spacing := clampf(radius * 0.14, 7.6 if arch == &"sea_stack" else 10.0, 16.5)
	var fallback_spacing := maxf(4.6 if arch == &"sea_stack" else 6.2, primary_spacing * 0.56)
	var cell_size := maxf(8.0, primary_spacing)
	var grid: Dictionary = {}

	var palette := _buttress_fallback_palette(arch, is_volcanic)
	var size_scale := clampf(lerpf(0.84, 1.48, clampf((radius - 38.0) / 144.0, 0.0, 1.0)), 0.78, 1.55)

	var pass_spacings: Array[float] = [primary_spacing, fallback_spacing]
	for sp_idx in pass_spacings.size():
		var min_sep: float = pass_spacings[sp_idx]
		var pass_cap := target_total if sp_idx == 0 else mini(target_total, maxi(18, int(roundf(float(target_total) * 0.85))))
		for cand in candidates:
			var placed_total := out_tall_xf.size() + out_wide_xf.size()
			if placed_total >= pass_cap:
				break
			var pos: Vector3 = cand["pos"] as Vector3
			var pt := Vector2(pos.x, pos.z)
			if not _grid_is_clear(grid, cell_size, pt, min_sep):
				continue

			var out_xz: Vector3 = cand["out_xz"] as Vector3
			var ny: float = float(cand["ny"])
			# Mix wide coastal headland massifs (~52%) with tall rocky spurs (~48%) to eliminate repetitive silhouettes.
			var pick_wide := false
			if use_wide_layer:
				var wide_bias := 0.58 if ny > 0.44 else 0.44
				pick_wide = rng.randf() < wide_bias

			var aabb := wide_aabb if pick_wide else tall_aabb
			var probes := wide_probes if pick_wide else tall_probes
			var uses_glb := wide_uses_glb if pick_wide else tall_uses_glb

			# Monumental architectural scale so buttresses read as true carved mountain ribs & rocky spurs!
			var ref_h := maxf(4.0, aabb.size.y)
			var sc_y: float
			var sc_xz: float
			if pick_wide:
				var target_h := rng.randf_range(11.2, 16.4) * clampf(size_scale, 0.85, 1.30)
				sc_y = clampf(target_h / ref_h, 0.72, 1.38)
				sc_xz = clampf(sc_y * rng.randf_range(0.86, 1.16), 0.72, 1.36)
			else:
				var target_h := rng.randf_range(15.5, 23.5) * size_scale
				sc_y = clampf(target_h / ref_h, 0.74, 1.58)
				sc_xz = clampf(sc_y * rng.randf_range(0.82, 1.18), 0.70, 1.52)

			# Orient local -Z outward along horizontal slope direction `out_xz` with broad natural yaw/roll variety.
			# Positive pitch around +X rotates +Y toward +Z (tucking top caps INWARD into the cliff shoulder!).
			var yaw := atan2(-out_xz.x, -out_xz.z) + rng.randf_range(-0.42, 0.42)
			var pitch := rng.randf_range(0.08, 0.24) if not is_volcanic else rng.randf_range(-0.08, 0.14)
			var roll := rng.randf_range(-0.11, 0.11)
			var rot_basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.FORWARD, roll)
			var xf_basis := rot_basis.scaled(Vector3(sc_xz, sc_y, sc_xz))

			# Embed deeply into the hillside (`pos -= out_xz * embed_back`) so pitched -5.5..-7.0 m feet
			# and top caps fuse organically into the mountain rock with ZERO floating undersides or overhangs!
			var back_frac := 0.36 if pick_wide else 0.34
			var embed_back := (clampf(aabb.size.z * back_frac, 2.2, 4.4) + maxf(0.0, (0.45 - ny) * 2.2)) * sc_xz
			var base_sink := clampf(aabb.size.y * 0.24, 2.0, 4.8) * sc_y
			if aabb.position.y > -2.5:
				base_sink += (aabb.position.y + 2.5) * sc_y
			var back_px := pos.x - out_xz.x * embed_back
			var back_pz := pos.z - out_xz.z * embed_back
			var desired_origin_y := pos.y - base_sink
			var origin := Vector3(back_px, desired_origin_y, back_pz)
			var xf := Transform3D(xf_basis, origin)

			# Exact real-mesh bottom-skirt perimeter footing check guarantees ZERO floating rock bases
			# over steep canyon corners or coastal dropoffs!
			var bot_pts: PackedVector3Array = probes["bottom"] as PackedVector3Array
			var max_foot_air := -INF
			for fp in bot_pts:
				var wp := xf * fp
				var foot_air := wp.y - island.surface_height(wp.x, wp.z)
				if foot_air > max_foot_air:
					max_foot_air = foot_air
			var req_embed := 0.85 if is_volcanic else 1.00
			if max_foot_air > -req_embed:
				desired_origin_y -= (max_foot_air + req_embed)
				if not is_volcanic and desired_origin_y + (aabb.position.y + aabb.size.y) * sc_y * cos(pitch) < pos.y + 1.4:
					continue
				origin.y = desired_origin_y
				xf = Transform3D(xf_basis, origin)

			# Real-mesh anti-tip-sliver guard (fixes Local-GPU M14 Emerald Spire right canyon wall
			# horizontal mossy cap wedge!): reject any buttress whose actual upper mossy cap/shoulder
			# vertices poke above the cliff face while its supporting lower/mid rock body stays buried!
			if is_volcanic:
				var vp_mid := xf * Vector3(0.0, aabb.position.y + aabb.size.y * 0.50, 0.0)
				if vp_mid.y < island.surface_height(vp_mid.x, vp_mid.z) + 0.5:
					continue
			else:
				var low_pts: PackedVector3Array = probes["lower"] as PackedVector3Array
				var up_pts: PackedVector3Array = probes["upper"] as PackedVector3Array
				var max_up_clear := -INF
				for up in up_pts:
					var wup := xf * up
					max_up_clear = maxf(max_up_clear, wup.y - island.surface_height(wup.x, wup.z))
				if max_up_clear > -0.10:
					var max_low_clear := -INF
					var low_exposed := 0
					for lp in low_pts:
						var wlp := xf * lp
						var lc := wlp.y - island.surface_height(wlp.x, wlp.z)
						max_low_clear = maxf(max_low_clear, lc)
						if lc > 0.10:
							low_exposed += 1
					if low_exposed < 3 or max_low_clear < 0.75:
						continue

			var inst_col: Color
			if uses_glb:
				# Subtle warm-neutral variation preserves baked 512x512 GLB PBR albedo/normal/roughness!
				var v := rng.randf_range(0.95, 1.07)
				inst_col = Color(v * rng.randf_range(0.99, 1.04), v, v * rng.randf_range(0.95, 1.00), 1.0)
			else:
				inst_col = _pick_jittered_color(rng, palette, 0.016, 0.09)

			if pick_wide:
				out_wide_xf.append(xf)
				out_wide_col.append(inst_col)
			else:
				out_tall_xf.append(xf)
				out_tall_col.append(inst_col)

			out_normals_y.append(ny)
			_grid_insert(grid, cell_size, pt)


static func _extract_buttress_probe_points(mesh: Mesh, aabb: AABB) -> Dictionary:
	# Pre-extract voxel-deduplicated real-vertex envelopes (bottom skirt perimeter, lower-mid
	# supporting prow, and upper mossy cap/shoulders) so footing & anti-tip-sliver checks test
	# 100% of true mesh surface geometry with zero blind spots between angular sectors.
	var y_bot_max := aabb.position.y + 0.85
	var y_low_min := aabb.position.y + aabb.size.y * 0.14
	var y_split := aabb.position.y + aabb.size.y * 0.55

	var bot_cells: Dictionary = {}
	var low_cells: Dictionary = {}
	var up_cells: Dictionary = {}

	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		if arrays.is_empty():
			continue
		var verts_var: Variant = arrays[Mesh.ARRAY_VERTEX]
		if not (verts_var is PackedVector3Array):
			continue
		var verts: PackedVector3Array = verts_var as PackedVector3Array
		for v in verts:
			if v.y <= y_bot_max:
				var bk := Vector3i(int(roundf(v.x / 0.9)), int(roundf(v.y / 0.9)), int(roundf(v.z / 0.9)))
				if not bot_cells.has(bk):
					bot_cells[bk] = v
			if v.y >= y_low_min and v.y < y_split:
				var lk := Vector3i(int(roundf(v.x / 1.4)), int(roundf(v.y / 1.4)), int(roundf(v.z / 1.4)))
				if not low_cells.has(lk):
					low_cells[lk] = v
			elif v.y >= y_split:
				var uk := Vector3i(int(roundf(v.x / 1.2)), int(roundf(v.y / 1.2)), int(roundf(v.z / 1.2)))
				if not up_cells.has(uk):
					up_cells[uk] = v

	var bot_pts := PackedVector3Array()
	for k in bot_cells:
		bot_pts.append(bot_cells[k] as Vector3)
	var low_pts := PackedVector3Array()
	for k in low_cells:
		low_pts.append(low_cells[k] as Vector3)
	var up_pts := PackedVector3Array()
	for k in up_cells:
		up_pts.append(up_cells[k] as Vector3)

	return {
		"bottom": bot_pts,
		"lower": low_pts,
		"upper": up_pts,
	}


static func _buttress_fallback_palette(arch: StringName, is_volcanic: bool) -> Array[Color]:
	if is_volcanic:
		return BUTTRESS_FALLBACK_VOLCANIC
	if arch == &"sea_arch" or arch == &"skull_bluff":
		return BUTTRESS_FALLBACK_PALE
	return BUTTRESS_FALLBACK_LIMESTONE


# ------------------------------------------------------------------ MultiMesh & sampling utilities

static func _create_multimesh_node(node_name: String, mesh: Mesh, mat_override: Material,
		transforms: Array[Transform3D], colors: Array[Color], cull_margin: float,
		vis_end: float, vis_margin: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = false
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	if mat_override != null:
		mmi.material_override = mat_override
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = vis_end
	mmi.visibility_range_end_margin = vis_margin
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	if cull_margin > 0.0:
		mmi.extra_cull_margin = cull_margin
	return mmi


static func _sample_disk_xz(rng: RandomNumberGenerator, r_min: float, r_max: float) -> Vector2:
	var ang := rng.randf() * TAU
	var r := sqrt(lerpf(r_min * r_min, r_max * r_max, rng.randf()))
	return Vector2(cos(ang) * r, sin(ang) * r)


static func _sample_annulus_xz(rng: RandomNumberGenerator, r_min: float, r_max: float) -> Vector2:
	return _sample_disk_xz(rng, r_min, r_max)


static func _sample_clustered_xz(rng: RandomNumberGenerator, centers: Array[Vector2],
		r_min: float, r_max: float, cluster_prob: float, patch_min: float,
		patch_max: float) -> Vector2:
	if not centers.is_empty() and rng.randf() < cluster_prob:
		var ctr := centers[rng.randi_range(0, centers.size() - 1)]
		var ang := rng.randf() * TAU
		var dist := lerpf(patch_min, patch_max, sqrt(rng.randf()))
		var pt := ctr + Vector2(cos(ang) * dist, sin(ang) * dist)
		var r_len := pt.length()
		if r_len >= r_min and r_len <= r_max:
			return pt
	return _sample_disk_xz(rng, r_min, r_max)


static func _grounded_transform(origin: Vector3, normal: Vector3, tilt_weight: float,
		yaw: float, scl: Vector3) -> Transform3D:
	var up_axis := Vector3.UP.lerp(normal.normalized(), tilt_weight).normalized()
	var ref_fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right_axis := ref_fwd.cross(up_axis)
	if right_axis.length_squared() < 0.0001:
		right_axis = Vector3.RIGHT
	else:
		right_axis = right_axis.normalized()
	var back_axis := right_axis.cross(up_axis).normalized()
	var xform_basis := Basis(right_axis, up_axis, back_axis).scaled(scl)
	return Transform3D(xform_basis, origin)


static func _pick_jittered_color(rng: RandomNumberGenerator, palette: Array[Color],
		hue_jit: float = 0.02, val_jit: float = 0.08) -> Color:
	var base := palette[rng.randi_range(0, palette.size() - 1)]
	var h := wrapf(base.h + rng.randf_range(-hue_jit, hue_jit), 0.0, 1.0)
	var s := clampf(base.s * rng.randf_range(1.0 - val_jit, 1.0 + val_jit), 0.0, 1.0)
	var v := clampf(base.v * rng.randf_range(1.0 - val_jit, 1.0 + val_jit), 0.0, 1.0)
	return Color.from_hsv(h, s, v, 1.0)


# ------------------------------------------------------------------ deterministic biome tint modulators

static func _spatial_hash01(x: float, z: float) -> float:
	var raw := sin(x * 12.9898 + z * 78.233) * 43758.5453
	return clampf(raw - floorf(raw), 0.0, 0.999999)


static func _volcanic_caldera_band(pt: Vector2, h: float) -> int:
	# Pure deterministic spatial patch + fine hash -> 0: olive-slate, 1: burnt-russet, 2: sulfur-gold.
	var h_fine := _spatial_hash01(pt.x, pt.y)
	var patch := 0.5 + 0.5 * sin(pt.x * 0.17 + pt.y * 0.13) * cos(pt.x * 0.11 - pt.y * 0.19)
	var roll := clampf(h_fine * 0.72 + patch * 0.28, 0.0, 0.999999)
	var high_sulfur_boost := clampf((h - 10.0) / 20.0, 0.0, 1.0) * 0.09
	if roll < 0.50:
		return 0
	if roll < 0.84 - high_sulfur_boost:
		return 1
	return 2


static func _apply_volcanic_flora_tint(base_col: Color, pt: Vector2, h: float) -> Color:
	var band := _volcanic_caldera_band(pt, h)
	if band == 0:
		return base_col.lerp(VOLCANIC_CALDERA_SLATE, 0.74)
	if band == 1:
		return base_col.lerp(VOLCANIC_CALDERA_RUSSET, 0.76)
	return base_col.lerp(VOLCANIC_CALDERA_SULFUR, 0.78)


static func _apply_highland_alpine_tint(base_col: Color, arch: StringName, pt: Vector2, h: float,
		is_highland_pass: bool, is_fern: bool) -> Color:
	var is_ruin := arch in HIGHLAND_RUIN_ARCHETYPES
	var alt_t: float
	if is_highland_pass:
		alt_t = maxf(clampf((h - 18.0) / 22.0, 0.0, 1.0), 0.56 if is_ruin else 0.46)
	else:
		var span := 14.0 if is_ruin else 18.0
		alt_t = clampf((h - 20.0) / span, 0.0, 1.0)
	if alt_t <= 0.001:
		return base_col

	var hv := _spatial_hash01(pt.x * 0.73 + 5.1, pt.y * 0.73 - 3.7)
	var patch := 0.5 + 0.5 * sin(pt.x * 0.14 - pt.y * 0.16)
	var mix_t := clampf(hv * 0.65 + patch * 0.35, 0.0, 1.0)
	var moss_col := HIGHLAND_RUIN_MOSS if (is_ruin or is_fern) else HIGHLAND_ALPINE_MOSS
	var sage_col := HIGHLAND_LICHEN_SAGE if (is_ruin and not is_fern) else HIGHLAND_SAGE_OLIVE
	var target := moss_col.lerp(sage_col, mix_t * (0.72 if is_fern else 0.92))
	var weight := clampf(alt_t * (0.64 if is_ruin else 0.54), 0.0, 0.72)
	return base_col.lerp(target, weight)


static func _apply_grass_biome_tint(base_col: Color, arch: StringName, is_volcanic: bool,
		pt: Vector2, h: float) -> Color:
	if is_volcanic:
		return _apply_volcanic_flora_tint(base_col, pt, h)
	if h < 4.4:
		var dune_t := clampf((4.4 - h) / 2.8, 0.0, 1.0)
		var hv := _spatial_hash01(pt.x + 17.3, pt.y - 11.9)
		var is_atoll := arch in LAGOON_ATOLL_ARCHETYPES
		var sea_oat_mix := (0.62 + 0.38 * hv) if is_atoll else (0.48 + 0.52 * hv)
		var dune_target := DUNE_COASTAL_SAGE_COLOR.lerp(DUNE_SEA_OATS_COLOR, sea_oat_mix)
		var blended := base_col.lerp(dune_target, dune_t * 0.58)
		return Color(
			clampf(blended.r, 0.0, 1.06),
			clampf(blended.g, 0.0, 1.04),
			clampf(blended.b, 0.0, 1.0),
			1.0
		)
	if h > 20.0:
		return _apply_highland_alpine_tint(base_col, arch, pt, h, false, false)
	if arch in LUSH_JUNGLE_TEMPLE_ARCHETYPES and h > 5.0:
		var valley_t := clampf((h - 5.0) / 4.0, 0.0, 1.0) * clampf((20.0 - h) / 6.0, 0.0, 1.0)
		return Color(
			clampf(base_col.r * lerpf(1.0, 0.92, valley_t), 0.0, 1.0),
			clampf(base_col.g * lerpf(1.0, 1.02, valley_t), 0.0, 1.0),
			clampf(base_col.b * lerpf(1.0, 0.94, valley_t), 0.0, 1.0),
			1.0
		)
	return base_col


static func _apply_fern_biome_tint(base_col: Color, arch: StringName, is_volcanic: bool,
		pt: Vector2, h: float) -> Color:
	if is_volcanic:
		return _apply_volcanic_flora_tint(base_col, pt, h)
	if h > 20.0:
		return _apply_highland_alpine_tint(base_col, arch, pt, h, false, true)
	if arch in LUSH_JUNGLE_TEMPLE_ARCHETYPES:
		var valley_t := clampf((20.0 - h) / 12.0, 0.35, 1.0)
		var mod := Color.WHITE.lerp(JUNGLE_VALLEY_FERN_TINT, valley_t)
		return Color(
			clampf(base_col.r * mod.r, 0.0, 1.0),
			clampf(base_col.g * mod.g, 0.0, 1.0),
			clampf(base_col.b * mod.b, 0.0, 1.0),
			1.0
		)
	return base_col


static func _apply_hibiscus_biome_tint(base_tint: Color, arch: StringName, is_volcanic: bool,
		pt: Vector2) -> Color:
	var hv := _spatial_hash01(pt.x, pt.y)
	if is_volcanic:
		var ember := Color(
			VOLCANIC_HIBISCUS_EMBER.r,
			lerpf(VOLCANIC_HIBISCUS_EMBER.g - 0.05, VOLCANIC_HIBISCUS_EMBER.g + 0.05, hv),
			lerpf(VOLCANIC_HIBISCUS_EMBER.b - 0.04, VOLCANIC_HIBISCUS_EMBER.b + 0.04, hv),
			1.0
		)
		return base_tint.lerp(ember, 0.84)
	var idx := mini(HIBISCUS_LAGOON_TINTS.size() - 1, int(floorf(hv * float(HIBISCUS_LAGOON_TINTS.size()))))
	var target: Color = HIBISCUS_LAGOON_TINTS[idx]
	var strength := 0.88 if (arch in LAGOON_ATOLL_ARCHETYPES) else 0.42
	return base_tint.lerp(target, strength)


static func _apply_tidal_rock_biome_tint(base_col: Color, arch: StringName, is_volcanic: bool,
		pt: Vector2, h: float) -> Color:
	var hv := _spatial_hash01(pt.x, pt.y)
	if is_volcanic:
		var wet_t := clampf((0.75 - h) / 1.4, 0.0, 1.0)
		var obs_target := VOLCANIC_TIDAL_OBSIDIAN.lerp(Color(0.34, 0.34, 0.40, 1.0), wet_t * 0.45)
		return base_col.lerp(obs_target, 0.72 + 0.14 * hv)
	if arch in LAGOON_ATOLL_ARCHETYPES:
		var shallow_t := clampf((1.4 - h) / 2.2, 0.0, 1.0)
		return base_col.lerp(LAGOON_TIDAL_CORAL, 0.68 + 0.22 * shallow_t * (0.65 + 0.35 * hv))
	return base_col


static func _apply_wet_shore_sheen(col: Color, h: float) -> Color:
	# Damp wave-washed splash-zone darkening (h < 0.95 m) with a subtle cool marine tint on B
	# so wet pebbles, driftwood, and tidal boulders blend naturally with the wet-sand shoreline.
	if h >= WET_SHORE_MAX_H:
		return col
	var wet_t := clampf((WET_SHORE_MAX_H - h) / WET_SHORE_SPAN, 0.0, 1.0)
	var dark := lerpf(1.0, 0.76, wet_t)
	var cool_g := lerpf(1.0, 1.01, wet_t)
	var cool_b := lerpf(1.0, 1.055, wet_t)
	return Color(
		maxf(col.r * dark, 0.0),
		maxf(col.g * dark * cool_g, 0.0),
		maxf(col.b * dark * cool_b, 0.0),
		col.a
	)


# ------------------------------------------------------------------ GLB visual mesh extraction (with col_* stripping)

static func _extract_glb_visual_mesh(glb_path: String) -> Mesh:
	if _glb_mesh_cache.has(glb_path):
		return _glb_mesh_cache[glb_path] as Mesh
	if not ResourceLoader.exists(glb_path):
		_glb_mesh_cache[glb_path] = null
		return null
	var packed := load(glb_path) as PackedScene
	if packed == null:
		_glb_mesh_cache[glb_path] = null
		return null
	var inst := packed.instantiate()
	if inst == null:
		_glb_mesh_cache[glb_path] = null
		return null

	var visuals: Array[MeshInstance3D] = []
	_collect_visual_meshes(inst, visuals)

	var result: Mesh = null
	if visuals.size() == 1:
		var mi := visuals[0]
		var rel_xf := _relative_transform(mi, inst)
		if rel_xf.is_equal_approx(Transform3D.IDENTITY) and mi.mesh.get_surface_count() > 0:
			result = mi.mesh
		else:
			result = _bake_visual_meshes_to_array_mesh(visuals, inst)
	elif visuals.size() > 1:
		result = _bake_visual_meshes_to_array_mesh(visuals, inst)

	# Synchronously free the temporary GLB scene tree so ZERO nodes ever leak!
	inst.free()

	if result != null and result.get_surface_count() == 0:
		result = null
	_glb_mesh_cache[glb_path] = result
	return result


static func _collect_visual_meshes(node: Node, out_visuals: Array[MeshInstance3D]) -> void:
	if node == null:
		return
	if node.name.begins_with("col_"):
		return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null and not (mi.mesh is PrimitiveMesh):
			out_visuals.append(mi)
	for child in node.get_children():
		_collect_visual_meshes(child, out_visuals)


static func _relative_transform(node: Node, ancestor: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur := node
	while cur != null and cur != ancestor:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


static func _bake_visual_meshes_to_array_mesh(visuals: Array[MeshInstance3D], root: Node) -> ArrayMesh:
	var combined := ArrayMesh.new()
	for mi in visuals:
		var src_mesh := mi.mesh
		if src_mesh == null:
			continue
		var rel_xf := _relative_transform(mi, root)
		var norm_basis := rel_xf.basis.inverse().transposed()
		var tan_basis := rel_xf.basis
		for si in src_mesh.get_surface_count():
			if src_mesh.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays := src_mesh.surface_get_arrays(si)
			if arrays.is_empty():
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			if verts.is_empty():
				continue
			var xformed_verts := PackedVector3Array()
			xformed_verts.resize(verts.size())
			for vi in verts.size():
				xformed_verts[vi] = rel_xf * verts[vi]
			arrays[Mesh.ARRAY_VERTEX] = xformed_verts

			if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
				var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
				var xformed_norms := PackedVector3Array()
				xformed_norms.resize(norms.size())
				for ni in norms.size():
					var n := norm_basis * norms[ni]
					xformed_norms[ni] = n.normalized() if n.length_squared() > 1e-8 else Vector3.UP
				arrays[Mesh.ARRAY_NORMAL] = xformed_norms

			if arrays[Mesh.ARRAY_TANGENT] is PackedFloat32Array:
				var tans: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array
				var xformed_tans := PackedFloat32Array()
				xformed_tans.resize(tans.size())
				var idx := 0
				while idx + 3 < tans.size():
					var tv := tan_basis * Vector3(tans[idx], tans[idx + 1], tans[idx + 2])
					tv = tv.normalized() if tv.length_squared() > 1e-8 else Vector3.RIGHT
					xformed_tans[idx] = tv.x
					xformed_tans[idx + 1] = tv.y
					xformed_tans[idx + 2] = tv.z
					xformed_tans[idx + 3] = tans[idx + 3]
					idx += 4
				arrays[Mesh.ARRAY_TANGENT] = xformed_tans

			var out_surf := combined.get_surface_count()
			combined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mat := mi.get_active_material(si)
			if mat != null:
				combined.surface_set_material(out_surf, mat)
	return combined


# ------------------------------------------------------------------ shared cached materials & meshes

static func _get_foliage_material() -> ShaderMaterial:
	if _foliage_material == null:
		var mat := ShaderMaterial.new()
		mat.shader = FOLIAGE_SHADER
		mat.set_shader_parameter(&"use_albedo_tex", 0.0)
		mat.set_shader_parameter(&"use_uv2_weight", 1.0)
		mat.set_shader_parameter(&"sway_strength", 0.72)
		mat.set_shader_parameter(&"roughness_val", 0.56)
		mat.set_shader_parameter(&"sss_strength", 0.44)
		# Provide 1.08x linear sunlit headroom so UNORM8 ARRAY_COLOR [0..1] delivers crisp
		# 1.04-1.08x sunlit blade/frond tips & 1.05x vivid hibiscus petals without clipping.
		mat.set_shader_parameter(&"albedo_tint",
			Color(FOLIAGE_SUN_HEADROOM, FOLIAGE_SUN_HEADROOM, FOLIAGE_SUN_HEADROOM, 1.0).linear_to_srgb())
		_foliage_material = mat
	return _foliage_material


static func _get_wood_stone_material() -> StandardMaterial3D:
	if _wood_stone_material == null:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.roughness = 0.88
		mat.metallic = 0.0
		mat.metallic_specular = 0.22
		_wood_stone_material = mat
	return _wood_stone_material


static func _get_pebble_material() -> StandardMaterial3D:
	if _pebble_material == null:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.roughness = 0.72
		mat.metallic = 0.0
		mat.metallic_specular = 0.34
		_pebble_material = mat
	return _pebble_material


static func _get_tidal_rock_material() -> StandardMaterial3D:
	if _tidal_rock_material == null:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.roughness = 0.82
		mat.metallic = 0.0
		mat.metallic_specular = 0.28
		_tidal_rock_material = mat
	return _tidal_rock_material


static func _get_buttress_fallback_material() -> StandardMaterial3D:
	if _buttress_fallback_material == null:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.roughness = 0.86
		mat.metallic = 0.0
		mat.metallic_specular = 0.24
		_buttress_fallback_material = mat
	return _buttress_fallback_material


static func _get_stepping_stone_material() -> StandardMaterial3D:
	if _stepping_stone_mat == null:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		# Sunlit 1.02x top-face headroom so beveled sides (~0.80x) pop cleanly on foot.
		mat.albedo_color = Color(1.02, 1.02, 1.02, 1.0)
		mat.roughness = 0.88
		mat.metallic = 0.0
		mat.metallic_specular = 0.22
		_stepping_stone_mat = mat
	return _stepping_stone_mat


static func _get_butterfly_material() -> StandardMaterial3D:
	if _butterfly_mat == null:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.55
		mat.metallic = 0.0
		mat.metallic_specular = 0.25
		_butterfly_mat = mat
	return _butterfly_mat


static func _get_crab_material() -> StandardMaterial3D:
	if _crab_mat == null:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.65
		mat.metallic = 0.0
		mat.metallic_specular = 0.32
		_crab_mat = mat
	return _crab_mat


static func _get_grass_mesh() -> ArrayMesh:
	if _grass_mesh == null:
		_grass_mesh = _build_grass_mesh()
	return _grass_mesh


static func _get_fern_mesh() -> ArrayMesh:
	if _fern_mesh == null:
		_fern_mesh = _build_fern_mesh()
	return _fern_mesh


static func _get_hibiscus_mesh() -> ArrayMesh:
	if _hibiscus_mesh == null:
		_hibiscus_mesh = _build_hibiscus_mesh()
	return _hibiscus_mesh


static func _get_driftwood_mesh() -> ArrayMesh:
	if _driftwood_mesh == null:
		_driftwood_mesh = _build_driftwood_mesh()
	return _driftwood_mesh


static func _get_pebbles_mesh() -> ArrayMesh:
	if _pebbles_mesh == null:
		_pebbles_mesh = _build_pebbles_mesh()
	return _pebbles_mesh


static func _get_tidal_rock_mesh() -> ArrayMesh:
	if _tidal_rock_mesh == null:
		_tidal_rock_mesh = _build_tidal_rock_mesh()
	return _tidal_rock_mesh


static func _get_fallback_buttress_mesh() -> ArrayMesh:
	if _fallback_buttress_mesh == null:
		_fallback_buttress_mesh = _build_fallback_buttress_mesh()
	return _fallback_buttress_mesh


static func _get_fallback_buttress_wide_mesh() -> ArrayMesh:
	if _fallback_buttress_wide_mesh == null:
		_fallback_buttress_wide_mesh = _build_fallback_buttress_wide_mesh()
	return _fallback_buttress_wide_mesh


static func _get_stepping_stone_mesh() -> ArrayMesh:
	if _stepping_stone_mesh == null:
		_stepping_stone_mesh = _build_stepping_stone_mesh()
	return _stepping_stone_mesh


static func _get_butterfly_mesh() -> ArrayMesh:
	if _butterfly_mesh == null:
		_butterfly_mesh = _build_butterfly_mesh()
	return _butterfly_mesh


static func _get_crab_mesh() -> ArrayMesh:
	if _crab_mesh == null:
		_crab_mesh = _build_crab_mesh()
	return _crab_mesh


# ------------------------------------------------------------------ Mesh 1: Sculpted 28-Blade Slender Grass + 3 Plumed Seed-Stalks

static func _scale_flora_linear(col_lin: Color, gain: float) -> Color:
	# Normalize linear luminance gain into [0..1] UNORM8 vertex-color headroom so
	# `foliage_wind.gdshader` (`COLOR.rgb * albedo_tint`) reconstructs exact `gain` without clipping.
	var inv := gain / FOLIAGE_SUN_HEADROOM
	return Color(
		clampf(col_lin.r * inv, 0.0, 1.0),
		clampf(col_lin.g * inv, 0.0, 1.0),
		clampf(col_lin.b * inv, 0.0, 1.0),
		1.0
	)


static func _flora_contact_ao_gain(y: float, tip_t: float, root_ao: float = 0.76,
		tip_lift: float = 1.06, ao_top_y: float = 0.44) -> float:
	# Natural soil-contact root AO (`y <= 0.14 m` -> ~0.74-0.80x luminance) rising smoothly
	# with elevation and blade/frond progression up to sunlit leaf/blade tips (~1.04-1.08x).
	var h_t := smoothstep(0.14, ao_top_y, y)
	var sun_t := maxf(h_t, smoothstep(0.45, 0.92, tip_t))
	var base_gain := lerpf(root_ao, 1.0, sun_t)
	return lerpf(base_gain, tip_lift, smoothstep(0.55, 1.0, tip_t))


static func _build_grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Linear shading ramp (multiplied against linear instance emerald/gold colors in foliage_wind.gdshader).
	var col_root := Color(0.54, 0.65, 0.52, 1.0).srgb_to_linear()
	var col_low := Color(0.76, 0.86, 0.72, 1.0).srgb_to_linear()
	var col_mid := Color(0.92, 0.96, 0.86, 1.0).srgb_to_linear()
	var col_tip := Color(1.00, 1.00, 0.95, 1.0).srgb_to_linear()

	# 28 slender arching tropical meadow grass blades (`base_half_w = 0.026..0.042 m`) clustered
	# organically across 3 natural sub-tufts (12 central + 8 offset A + 8 offset B):
	# [azimuth, root_off, height, arch_out, base_half_w, twist_rad, droop, phase_01, cx, cz]
	var blades: Array[Array] = [
		# Central lush tuft (12 slender blades)
		[0.10, 0.04, 0.88, 0.40, 0.042,  0.22, 0.12, 0.03,  0.00,  0.00],
		[0.64, 0.10, 0.56, 0.48, 0.034, -0.24, 0.16, 0.11,  0.00,  0.00],
		[1.16, 0.05, 0.78, 0.42, 0.039,  0.19, 0.13, 0.19,  0.00,  0.00],
		[1.70, 0.13, 0.44, 0.50, 0.030, -0.26, 0.18, 0.27,  0.00,  0.00],
		[2.22, 0.06, 0.84, 0.41, 0.041,  0.25, 0.12, 0.35,  0.00,  0.00],
		[2.76, 0.12, 0.52, 0.49, 0.033, -0.20, 0.16, 0.44,  0.00,  0.00],
		[3.28, 0.05, 0.74, 0.44, 0.038,  0.18, 0.14, 0.52,  0.00,  0.00],
		[3.82, 0.14, 0.38, 0.46, 0.029, -0.23, 0.17, 0.60,  0.00,  0.00],
		[4.34, 0.06, 0.82, 0.42, 0.040,  0.21, 0.12, 0.69,  0.00,  0.00],
		[4.88, 0.11, 0.60, 0.48, 0.035, -0.19, 0.15, 0.77,  0.00,  0.00],
		[5.40, 0.05, 0.72, 0.43, 0.037,  0.24, 0.13, 0.85,  0.00,  0.00],
		[5.92, 0.13, 0.46, 0.50, 0.031, -0.22, 0.17, 0.93,  0.00,  0.00],
		# Companion offset sub-tuft A (+X, +Z) (8 slender blades)
		[0.24, 0.05, 0.72, 0.40, 0.037,  0.20, 0.13, 0.08,  0.50,  0.24],
		[1.04, 0.11, 0.48, 0.46, 0.031, -0.22, 0.16, 0.21,  0.50,  0.24],
		[1.82, 0.06, 0.64, 0.42, 0.035,  0.24, 0.14, 0.34,  0.50,  0.24],
		[2.62, 0.12, 0.36, 0.44, 0.027, -0.18, 0.16, 0.47,  0.50,  0.24],
		[3.40, 0.05, 0.74, 0.39, 0.038,  0.19, 0.12, 0.59,  0.50,  0.24],
		[4.20, 0.10, 0.52, 0.45, 0.032, -0.25, 0.15, 0.72,  0.50,  0.24],
		[4.98, 0.06, 0.62, 0.43, 0.034,  0.21, 0.14, 0.83,  0.50,  0.24],
		[5.78, 0.12, 0.40, 0.46, 0.028, -0.20, 0.17, 0.95,  0.50,  0.24],
		# Companion offset sub-tuft B (-X, -Z) (8 slender blades)
		[0.48, 0.05, 0.70, 0.41, 0.036, -0.21, 0.13, 0.14, -0.46, -0.30],
		[1.26, 0.11, 0.44, 0.46, 0.030,  0.23, 0.16, 0.26, -0.46, -0.30],
		[2.06, 0.06, 0.76, 0.40, 0.039, -0.19, 0.12, 0.39, -0.46, -0.30],
		[2.84, 0.12, 0.34, 0.43, 0.026,  0.20, 0.16, 0.51, -0.46, -0.30],
		[3.64, 0.05, 0.66, 0.42, 0.035, -0.24, 0.14, 0.64, -0.46, -0.30],
		[4.42, 0.10, 0.50, 0.46, 0.031,  0.22, 0.15, 0.76, -0.46, -0.30],
		[5.22, 0.06, 0.62, 0.43, 0.034, -0.18, 0.14, 0.88, -0.46, -0.30],
		[6.02, 0.11, 0.42, 0.45, 0.028,  0.21, 0.16, 0.97, -0.46, -0.30],
	]

	var t_steps: Array[float] = [0.0, 0.36, 0.72, 1.0]
	var w_steps: Array[float] = [1.0, 0.80, 0.42, 0.0]

	for spec in blades:
		var az: float = float(spec[0])
		var roff: float = float(spec[1])
		var h_max: float = float(spec[2])
		var arch_out: float = float(spec[3])
		var half_w0: float = float(spec[4])
		var twist: float = float(spec[5])
		var droop: float = float(spec[6])
		var phase_01: float = float(spec[7])
		var tuft_off := Vector3(float(spec[8]), 0.0, float(spec[9]))

		var rad := Vector3(cos(az), 0.0, sin(az))
		var side := Vector3(-sin(az), 0.0, cos(az))

		var left_pts: Array[Vector3] = []
		var right_pts: Array[Vector3] = []
		var cols: Array[Color] = []

		for si in t_steps.size():
			var t: float = t_steps[si]
			var y := lerpf(-0.08, h_max, sin(t * PI * 0.52)) - droop * pow(t, 2.6)
			var r_out := roff + arch_out * pow(t, 1.55)
			var ctr := tuft_off + rad * r_out + Vector3(0.0, y, 0.0)
			var tw := twist * t
			var b_side := (side * cos(tw) + rad * sin(tw)).normalized()
			var hw := half_w0 * w_steps[si]
			left_pts.append(ctr - b_side * hw)
			right_pts.append(ctr + b_side * hw)

			var c := col_root
			if si == 1:
				c = col_low
			elif si == 2:
				c = col_mid
			elif si >= 3:
				c = col_tip
			var gain := _flora_contact_ao_gain(y, t, 0.76, 1.065, 0.44)
			cols.append(_scale_flora_linear(c, gain))

		# 2 tapered curved quads + 1 sharp pointed grass tip = 5 tris/blade (140 tris across 28 blades).
		for si in range(t_steps.size() - 1):
			var t0: float = t_steps[si]
			var t1: float = t_steps[si + 1]
			var uv2_0 := Vector2(t0, phase_01)
			var uv2_1 := Vector2(t1, phase_01)
			if si < t_steps.size() - 2:
				_add_foliage_tri(st, left_pts[si], left_pts[si + 1], right_pts[si + 1],
					cols[si], cols[si + 1], cols[si + 1],
					Vector2(0.0, 1.0 - t0), Vector2(0.0, 1.0 - t1), Vector2(1.0, 1.0 - t1),
					uv2_0, uv2_1, uv2_1)
				_add_foliage_tri(st, left_pts[si], right_pts[si + 1], right_pts[si],
					cols[si], cols[si + 1], cols[si],
					Vector2(0.0, 1.0 - t0), Vector2(1.0, 1.0 - t1), Vector2(1.0, 1.0 - t0),
					uv2_0, uv2_1, uv2_0)
			else:
				var tip_pt := left_pts[si + 1]
				_add_foliage_tri(st, left_pts[si], tip_pt, right_pts[si],
					cols[si], cols[si + 1], cols[si],
					Vector2(0.0, 1.0 - t0), Vector2(0.5, 0.0), Vector2(1.0, 1.0 - t0),
					uv2_0, uv2_1, uv2_0)

	# 3 delicate tall golden-ochre plumed coastal seed-stalks rising gracefully above the 3 sub-tufts:
	# [azimuth, root_off, height, arch_out, droop, phase_01, cx, cz]
	var stalks: Array[Array] = [
		[0.52, 0.04, 0.96, 0.30, 0.13, 0.17,  0.00,  0.00],
		[2.46, 0.05, 0.86, 0.28, 0.12, 0.53,  0.50,  0.24],
		[4.64, 0.04, 0.80, 0.29, 0.12, 0.86, -0.46, -0.30],
	]
	var col_stalk_hi := Color(0.95, 0.88, 0.56, 1.0).srgb_to_linear()
	var col_plume_base := _scale_flora_linear(Color(0.96, 0.76, 0.36, 1.0).srgb_to_linear(), 1.04)
	var col_plume_mid := _scale_flora_linear(Color(1.00, 0.80, 0.40, 1.0).srgb_to_linear(), 1.065)
	var col_plume_tip := _scale_flora_linear(Color(1.00, 0.88, 0.52, 1.0).srgb_to_linear(), 1.075)
	var stalk_t: Array[float] = [0.0, 0.25, 0.50, 0.75]
	var stalk_hw: Array[float] = [0.011, 0.009, 0.007, 0.0055]

	for sspec in stalks:
		var az: float = float(sspec[0])
		var roff: float = float(sspec[1])
		var h_max: float = float(sspec[2])
		var arch_out: float = float(sspec[3])
		var droop: float = float(sspec[4])
		var phase_01: float = float(sspec[5])
		var tuft_off := Vector3(float(sspec[6]), 0.0, float(sspec[7]))

		var rad := Vector3(cos(az), 0.0, sin(az))
		var side := Vector3(-sin(az), 0.0, cos(az))

		var eval_stalk := func(t_val: float) -> Vector3:
			var y_s := lerpf(-0.07, h_max, sin(t_val * PI * 0.50)) - droop * pow(t_val, 2.5)
			var r_s := roff + arch_out * pow(t_val, 1.48)
			return tuft_off + rad * r_s + Vector3(0.0, y_s, 0.0)

		# Slender curved stalk ribbon (3 quads = 6 tris/stalk).
		var s_left: Array[Vector3] = []
		var s_right: Array[Vector3] = []
		var s_cols: Array[Color] = []
		for si in stalk_t.size():
			var tv: float = stalk_t[si]
			var ctr: Vector3 = eval_stalk.call(tv)
			var hw: float = stalk_hw[si]
			s_left.append(ctr - side * hw)
			s_right.append(ctr + side * hw)
			var sc_col := col_root.lerp(col_low, smoothstep(0.0, 0.42, tv)).lerp(col_stalk_hi, smoothstep(0.35, 0.75, tv))
			s_cols.append(_scale_flora_linear(sc_col, _flora_contact_ao_gain(ctr.y, tv, 0.76, 1.065, 0.44)))

		for si in range(stalk_t.size() - 1):
			var uv2_0 := Vector2(stalk_t[si], phase_01)
			var uv2_1 := Vector2(stalk_t[si + 1], phase_01)
			_add_foliage_tri(st, s_left[si], s_left[si + 1], s_right[si + 1],
				s_cols[si], s_cols[si + 1], s_cols[si + 1],
				Vector2(0.0, 1.0 - stalk_t[si]), Vector2(0.0, 1.0 - stalk_t[si + 1]), Vector2(1.0, 1.0 - stalk_t[si + 1]),
				uv2_0, uv2_1, uv2_1)
			_add_foliage_tri(st, s_left[si], s_right[si + 1], s_right[si],
				s_cols[si], s_cols[si + 1], s_cols[si],
				Vector2(0.0, 1.0 - stalk_t[si]), Vector2(1.0, 1.0 - stalk_t[si + 1]), Vector2(1.0, 1.0 - stalk_t[si]),
				uv2_0, uv2_1, uv2_0)

		# Feathered 3D golden-wheat diamond plume head (8 spindle tris + 4 feathery awn spikelets = 12 tris/stalk).
		var p_base: Vector3 = eval_stalk.call(0.73)
		var p_belly: Vector3 = eval_stalk.call(0.85)
		var p_tip: Vector3 = eval_stalk.call(1.00)
		var p_dir := (p_tip - p_base).normalized()
		var u_ax := side
		var v_ax := p_dir.cross(u_ax).normalized()
		var plume_r := 0.032

		var ring: Array[Vector3] = [
			p_belly + u_ax * plume_r,
			p_belly + v_ax * (plume_r * 0.88),
			p_belly - u_ax * plume_r,
			p_belly - v_ax * (plume_r * 0.88),
		]
		var uv2_pb := Vector2(0.73, phase_01)
		var uv2_pm := Vector2(0.86, phase_01)
		var uv2_pt := Vector2(1.00, phase_01)
		for k in 4:
			var nk := (k + 1) % 4
			_add_outward_tri_uv2(st, p_base, ring[k], ring[nk], p_belly,
				col_plume_base, col_plume_mid, col_plume_mid, uv2_pb, uv2_pm, uv2_pm)
			_add_outward_tri_uv2(st, ring[k], p_tip, ring[nk], p_belly,
				col_plume_mid, col_plume_tip, col_plume_mid, uv2_pm, uv2_pt, uv2_pm)

		# 4 crisp outward-flaring feathery golden wheat spikelets (2 pairs in orthogonal planes).
		var awn_specs: Array[Array] = [
			[0.78,  u_ax, 0.82, 0.90],
			[0.78, -u_ax, 0.82, 0.90],
			[0.86,  v_ax, 0.89, 0.97],
			[0.86, -v_ax, 0.89, 0.97],
		]
		for aspec in awn_specs:
			var ta: float = float(aspec[0])
			var out_v: Vector3 = aspec[1] as Vector3
			var uv2_a0 := Vector2(ta, phase_01)
			var uv2_a1 := Vector2(float(aspec[2]), phase_01)
			var uv2_at := Vector2(float(aspec[3]), phase_01)
			var ab0: Vector3 = eval_stalk.call(ta) + out_v * 0.010
			var ab1: Vector3 = ab0 + p_dir * 0.026
			var atip: Vector3 = ab0 + p_dir * 0.064 + out_v * 0.044
			_add_foliage_tri(st, ab0, ab1, atip, col_plume_base, col_plume_mid, col_plume_tip,
				Vector2(0.0, 0.3), Vector2(0.3, 0.6), Vector2(1.0, 1.0), uv2_a0, uv2_a1, uv2_at)

	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ Mesh 2: 10-Frond 2-Tier Pinnate Serrated Fern Rosette

static func _build_fern_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Grounded fibrous central fern rosette heart (UV2.x = 0.0 -> anchored firmly to soil, ~0.75-0.79x root AO).
	var crown_bot := _scale_flora_linear(Color(0.28, 0.34, 0.24, 1.0).srgb_to_linear(), 0.75)
	var crown_top := _scale_flora_linear(Color(0.42, 0.56, 0.36, 1.0).srgb_to_linear(), 0.79)
	_append_anchored_mound(st, Vector3.ZERO, 0.16, 0.14, 0.15, -0.06, 6, crown_bot, crown_top, Vector2(0.0, 0.0))

	var col_rachis_lo := Color(0.36, 0.50, 0.33, 1.0).srgb_to_linear()
	var col_rachis_hi := Color(0.66, 0.78, 0.56, 1.0).srgb_to_linear()
	var col_base := Color(0.54, 0.68, 0.54, 1.0).srgb_to_linear()
	var col_mid := Color(0.84, 0.93, 0.80, 1.0).srgb_to_linear()
	var col_tip := Color(1.00, 1.00, 0.90, 1.0).srgb_to_linear()

	# 10 graceful arching pinnate fronds in 2 tiers (6 lower spreading + 4 taller inner crown):
	# [azimuth, reach, apex_y, tip_droop, max_pin_len, phase_01, bend_scale]
	var fronds: Array[Array] = [
		# Lower spreading tier (6 fronds: reach 0.88..1.04 m, apex_y 0.40..0.50 m, droop 0.20..0.25 m)
		[0.16, 1.02, 0.48, 0.24, 0.26, 0.04, 0.90],
		[1.22, 0.92, 0.43, 0.21, 0.24, 0.21, 0.88],
		[2.24, 1.04, 0.50, 0.25, 0.27, 0.38, 0.91],
		[3.30, 0.90, 0.41, 0.20, 0.23, 0.55, 0.87],
		[4.34, 1.00, 0.47, 0.23, 0.26, 0.72, 0.90],
		[5.38, 0.88, 0.40, 0.21, 0.23, 0.88, 0.86],
		# Upper taller arching inner crown tier (4 fronds: reach 0.68..0.80 m, apex_y 0.78..0.90 m, droop 0.16..0.20 m)
		[0.68, 0.78, 0.88, 0.19, 0.21, 0.13, 0.94],
		[1.88, 0.72, 0.82, 0.17, 0.20, 0.46, 0.92],
		[3.68, 0.80, 0.90, 0.20, 0.22, 0.64, 0.94],
		[5.02, 0.68, 0.78, 0.16, 0.19, 0.82, 0.91],
	]

	var rachis_segs := 5
	var rachis_end_t := 0.88
	var pin_ts: Array[float] = [0.20, 0.35, 0.50, 0.65, 0.79]

	for spec in fronds:
		var az: float = float(spec[0])
		var reach: float = float(spec[1])
		var apex_y: float = float(spec[2])
		var droop: float = float(spec[3])
		var max_pin_len: float = float(spec[4])
		var phase_01: float = float(spec[5])
		var bend_sc: float = float(spec[6])

		var rad := Vector3(cos(az), 0.0, sin(az))
		var side := Vector3(-sin(az), 0.0, cos(az))
		var tip_lift := 1.07 if apex_y >= 0.70 else 1.05

		var eval_spine := func(tv: float) -> Vector3:
			var r_out := 0.04 + reach * pow(tv, 1.08)
			var arch_y := 0.04 + apex_y * sin(tv * PI * 0.64) - droop * pow(tv, 2.3)
			return rad * r_out + Vector3(0.0, arch_y, 0.0)

		# 1. Slender curved central rachis stem (5 tapered quads, half-width 0.016 -> 0.006 m = 10 tris/frond).
		var r_left: Array[Vector3] = []
		var r_right: Array[Vector3] = []
		var r_cols: Array[Color] = []
		var r_ts: Array[float] = []
		for s in range(rachis_segs + 1):
			var frac := float(s) / float(rachis_segs)
			var tv := rachis_end_t * frac
			r_ts.append(tv)
			var ctr: Vector3 = eval_spine.call(tv)
			var r_hw := lerpf(0.016, 0.006, frac)
			r_left.append(ctr - side * r_hw)
			r_right.append(ctr + side * r_hw)
			var rc := col_rachis_lo.lerp(col_rachis_hi, smoothstep(0.0, 0.90, tv))
			r_cols.append(_scale_flora_linear(rc,
				_flora_contact_ao_gain(ctr.y, tv, 0.75, tip_lift * 0.96, 0.44)))

		for s in rachis_segs:
			var t0: float = r_ts[s]
			var t1: float = r_ts[s + 1]
			var uv2_0 := Vector2(t0 * bend_sc, phase_01)
			var uv2_1 := Vector2(t1 * bend_sc, phase_01)
			_add_foliage_tri(st, r_left[s], r_left[s + 1], r_right[s + 1],
				r_cols[s], r_cols[s + 1], r_cols[s + 1],
				Vector2(0.42, t0), Vector2(0.42, t1), Vector2(0.58, t1),
				uv2_0, uv2_1, uv2_1)
			_add_foliage_tri(st, r_left[s], r_right[s + 1], r_right[s],
				r_cols[s], r_cols[s + 1], r_cols[s],
				Vector2(0.42, t0), Vector2(0.58, t1), Vector2(0.58, t0),
				uv2_0, uv2_1, uv2_0)

		# 2. 5 pairs of distinct angled lance-shaped pinnae (leaflets) separated by real open air gaps (20 tris/frond).
		for p_idx in pin_ts.size():
			var base_t: float = pin_ts[p_idx]
			for s_sign: float in [-1.0, 1.0]:
				var t_p := clampf(base_t + (0.011 if s_sign > 0.0 else -0.011), 0.16, 0.84)
				var ctr: Vector3 = eval_spine.call(t_p)
				var p_prev: Vector3 = eval_spine.call(maxf(0.0, t_p - 0.02))
				var p_next: Vector3 = eval_spine.call(minf(1.0, t_p + 0.02))
				var fwd := (p_next - p_prev).normalized()
				var up_n := side.cross(fwd).normalized()

				# Botanical fern length envelope `sin(pow(t, 0.7) * PI)` with clean open air gaps between leaflets.
				var env := sin(pow(t_p, 0.7) * PI)
				var basal_taper := lerpf(0.84, 1.0, smoothstep(0.16, 0.34, t_p))
				var pin_len := max_pin_len * env * basal_taper
				var pin_hw := clampf(pin_len * 0.135, 0.017, 0.032)
				var sweep_rad := deg_to_rad(lerpf(67.0, 56.0, t_p))
				var r_hw_loc := lerpf(0.016, 0.006, clampf(t_p / rachis_end_t, 0.0, 1.0))

				var pin_dir := (side * (s_sign * sin(sweep_rad)) + fwd * cos(sweep_rad)).normalized()
				var pin_perp := pin_dir.cross(up_n).normalized()
				var v_cup := pin_hw * 0.34

				var p_base := ctr + side * (s_sign * r_hw_loc * 0.55)
				var p_mid := p_base + pin_dir * (pin_len * 0.38) + up_n * (pin_len * 0.05)
				var p_tip := p_base + pin_dir * pin_len - up_n * (pin_len * 0.05)
				var p_a := p_mid + pin_perp * pin_hw + up_n * v_cup
				var p_b := p_mid - pin_perp * pin_hw + up_n * v_cup

				var c_frond := col_base.lerp(col_mid, smoothstep(0.0, 0.55, t_p)).lerp(col_tip, smoothstep(0.55, 1.0, t_p))
				var c_pin_base := _scale_flora_linear(
					Color(c_frond.r * 0.90, c_frond.g * 0.93, c_frond.b * 0.90, 1.0),
					_flora_contact_ao_gain(p_base.y, t_p, 0.75, tip_lift, 0.44))
				var c_pin_edge := _scale_flora_linear(c_frond,
					_flora_contact_ao_gain(p_a.y, minf(1.0, t_p + 0.06), 0.76, tip_lift, 0.44))
				var c_pin_tip := _scale_flora_linear(c_frond.lerp(col_tip, 0.45),
					_flora_contact_ao_gain(p_tip.y, minf(1.0, t_p + 0.14), 0.76, tip_lift, 0.44))

				var uv2_b := Vector2(t_p * bend_sc, phase_01)
				var uv2_m := Vector2(minf(1.0, (t_p + 0.05) * bend_sc), phase_01)
				var uv2_t := Vector2(minf(1.0, (t_p + 0.11) * bend_sc), phase_01)

				# Crisp 2-tri V-cupped diamond/lance pinna split along the central vein (p_base -> p_tip).
				_add_foliage_tri(st, p_base, p_tip, p_a,
					c_pin_base, c_pin_tip, c_pin_edge,
					Vector2(0.5, t_p), Vector2(0.0 if s_sign < 0.0 else 1.0, minf(1.0, t_p + 0.12)),
					Vector2(0.25 if s_sign < 0.0 else 0.75, minf(1.0, t_p + 0.06)),
					uv2_b, uv2_t, uv2_m)
				_add_foliage_tri(st, p_base, p_b, p_tip,
					c_pin_base, c_pin_edge, c_pin_tip,
					Vector2(0.5, t_p), Vector2(0.25 if s_sign < 0.0 else 0.75, t_p),
					Vector2(0.0 if s_sign < 0.0 else 1.0, minf(1.0, t_p + 0.12)),
					uv2_b, uv2_m, uv2_t)

		# 3. Crisp pointed terminal tip leaflet continuing smoothly off the rachis end (2 tris/frond).
		var tp_base: Vector3 = eval_spine.call(0.85)
		var tp_tip: Vector3 = eval_spine.call(1.00)
		var tp_dir := (tp_tip - tp_base).normalized()
		var tp_len := tp_base.distance_to(tp_tip)
		var tp_up := side.cross(tp_dir).normalized()
		var tp_perp := tp_dir.cross(tp_up).normalized()
		var tp_hw := clampf(max_pin_len * 0.14, 0.022, 0.036)
		var tp_mid := tp_base.lerp(tp_tip, 0.36) + tp_up * (tp_len * 0.04)
		var tp_cup := tp_hw * 0.34
		var tp_a := tp_mid + tp_perp * tp_hw + tp_up * tp_cup
		var tp_b := tp_mid - tp_perp * tp_hw + tp_up * tp_cup

		var c_tb := _scale_flora_linear(col_mid.lerp(col_tip, 0.65),
			_flora_contact_ao_gain(tp_base.y, 0.85, 0.76, tip_lift, 0.44))
		var c_tm := _scale_flora_linear(col_mid.lerp(col_tip, 0.85),
			_flora_contact_ao_gain(tp_a.y, 0.93, 0.76, tip_lift, 0.44))
		var c_tt := _scale_flora_linear(col_tip,
			_flora_contact_ao_gain(tp_tip.y, 1.0, 0.76, tip_lift, 0.44))

		var uv2_tb := Vector2(0.85 * bend_sc, phase_01)
		var uv2_tm := Vector2(0.93 * bend_sc, phase_01)
		var uv2_tt := Vector2(1.00 * bend_sc, phase_01)
		_add_foliage_tri(st, tp_base, tp_tip, tp_a, c_tb, c_tt, c_tm,
			Vector2(0.5, 0.85), Vector2(0.5, 1.0), Vector2(0.25, 0.93), uv2_tb, uv2_tt, uv2_tm)
		_add_foliage_tri(st, tp_base, tp_b, tp_tip, c_tb, c_tm, c_tt,
			Vector2(0.5, 0.85), Vector2(0.75, 0.93), Vector2(0.5, 1.0), uv2_tb, uv2_tm, uv2_tt)

	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ Mesh 3: Tropical Hibiscus Shrub (16 Sleek Leaves + 6 Blossoms)

static func _build_hibiscus_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Sturdy forked woody coastal shrub stems (baked linear bark brown with soil-contact root AO, 48 tris).
	var bark_lo := Color(0.24, 0.16, 0.11, 1.0).srgb_to_linear()
	var bark_hi := Color(0.36, 0.25, 0.16, 1.0).srgb_to_linear()
	var stem_tips: Array[Vector3] = [
		Vector3(0.05, 0.58, 0.04),
		Vector3(0.32, 0.44, 0.16),
		Vector3(-0.30, 0.46, 0.20),
		Vector3(-0.14, 0.42, -0.30),
		Vector3(0.26, 0.38, -0.24),
		Vector3(-0.16, 0.56, -0.10),
	]
	for si in stem_tips.size():
		var tip := stem_tips[si]
		var root_off := Vector3(tip.x * 0.18, -0.08, tip.z * 0.18)
		var bark_lo_ao := _scale_flora_linear(bark_lo,
			_flora_contact_ao_gain(root_off.y, 0.0, 0.75, 1.04, 0.48))
		var bark_hi_ao := _scale_flora_linear(bark_hi,
			_flora_contact_ao_gain(tip.y, 0.30, 0.75, 1.04, 0.48))
		_append_tapered_limb_uv2(st, root_off, tip, 0.062 if si == 0 else 0.045, 0.025, 4,
			bark_lo_ao, bark_hi_ao, Vector2(0.0, float(si) * 0.16), Vector2(0.18, float(si) * 0.16))

	# 2. 16 sleek multi-tiered serrated/pointed glossy tropical leaves (lower + mid + upper sunlit tiers, 128 tris).
	var leaf_base := Color(0.11, 0.38, 0.15, 1.0).srgb_to_linear()
	var leaf_mid := Color(0.22, 0.62, 0.20, 1.0).srgb_to_linear()
	var leaf_upper := Color(0.32, 0.72, 0.22, 1.0).srgb_to_linear()
	var leaf_tip := Color(0.46, 0.80, 0.25, 1.0).srgb_to_linear()

	# [anchor_pos, azimuth, pitch_rad, length, half_w, phase_01]
	var leaves: Array[Array] = [
		# Lower skirt tier (6 sleek tapered leaves: length 0.51..0.56 m, hw 0.16..0.18 m)
		[Vector3(0.22, 0.28,  0.10), 0.28, 0.22, 0.55, 0.175, 0.04],
		[Vector3(0.10, 0.26,  0.22), 1.32, 0.18, 0.52, 0.165, 0.15],
		[Vector3(-0.18, 0.29,  0.18), 2.34, 0.20, 0.56, 0.180, 0.26],
		[Vector3(-0.24, 0.27, -0.06), 3.38, 0.17, 0.53, 0.168, 0.37],
		[Vector3(-0.10, 0.28, -0.22), 4.42, 0.21, 0.54, 0.172, 0.49],
		[Vector3(0.18, 0.26, -0.16), 5.46, 0.19, 0.51, 0.160, 0.60],
		# Mid layered tier (6 sleek tapered leaves: length 0.48..0.53 m, hw 0.146..0.165 m)
		[Vector3(0.20, 0.43,  0.16), 0.78, 0.38, 0.52, 0.162, 0.11],
		[Vector3(-0.04, 0.45,  0.22), 1.82, 0.42, 0.50, 0.154, 0.23],
		[Vector3(-0.22, 0.44,  0.04), 2.86, 0.36, 0.53, 0.165, 0.35],
		[Vector3(-0.18, 0.42, -0.18), 3.90, 0.40, 0.49, 0.150, 0.48],
		[Vector3(0.06, 0.44, -0.22), 4.94, 0.37, 0.51, 0.158, 0.62],
		[Vector3(0.22, 0.45, -0.04), 5.96, 0.43, 0.48, 0.146, 0.74],
		# Upper sunlit crown tier (4 sleek arching leaves: length 0.44..0.48 m, hw 0.132..0.148 m)
		[Vector3(0.10, 0.58,  0.08), 0.52, 0.56, 0.47, 0.146, 0.20],
		[Vector3(-0.10, 0.60,  0.10), 2.12, 0.60, 0.46, 0.142, 0.44],
		[Vector3(-0.12, 0.57, -0.08), 3.68, 0.55, 0.48, 0.148, 0.69],
		[Vector3(0.08, 0.61, -0.10), 5.24, 0.64, 0.44, 0.132, 0.90],
	]

	for lspec in leaves:
		var anchor: Vector3 = lspec[0] as Vector3
		var az: float = float(lspec[1])
		var pitch: float = float(lspec[2])
		var length: float = float(lspec[3])
		var hw: float = float(lspec[4])
		var phase_01: float = float(lspec[5])

		var horiz := Vector3(cos(az), 0.0, sin(az))
		var side := Vector3(-sin(az), 0.0, cos(az))
		var fwd := (horiz * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
		var up_n := side.cross(fwd).normalized()

		var p0 := anchor
		var p1 := anchor + fwd * (length * 0.36) + up_n * 0.036
		var p2 := anchor + fwd * (length * 0.70) + up_n * 0.014 - Vector3(0.0, length * 0.05, 0.0)
		var p3 := anchor + fwd * length - Vector3(0.0, length * 0.16, 0.0)
		var l1 := p1 - side * hw + up_n * (hw * 0.24)
		var r1 := p1 + side * hw + up_n * (hw * 0.24)
		var l2 := p2 - side * (hw * 0.68) + up_n * (hw * 0.16)
		var r2 := p2 + side * (hw * 0.68) + up_n * (hw * 0.16)
		var c1_m := Color(leaf_mid.r * 0.84, leaf_mid.g * 0.88, leaf_mid.b * 0.84, 1.0)
		var c2_m := Color(leaf_upper.r * 0.88, leaf_upper.g * 0.92, leaf_upper.b * 0.88, 1.0)

		var leaf_tip_lift := 1.07 if anchor.y >= 0.52 else (1.06 if anchor.y >= 0.38 else 1.05)
		var c_p0 := _scale_flora_linear(leaf_base,
			_flora_contact_ao_gain(p0.y, 0.0, 0.75, leaf_tip_lift, 0.56))
		var c_p1 := _scale_flora_linear(c1_m,
			_flora_contact_ao_gain(p1.y, 0.36, 0.75, leaf_tip_lift, 0.56))
		var c_l1 := _scale_flora_linear(leaf_mid,
			_flora_contact_ao_gain(l1.y, 0.40, 0.76, leaf_tip_lift, 0.56))
		var c_r1 := _scale_flora_linear(leaf_mid,
			_flora_contact_ao_gain(r1.y, 0.40, 0.76, leaf_tip_lift, 0.56))
		var c_p2 := _scale_flora_linear(c2_m,
			_flora_contact_ao_gain(p2.y, 0.70, 0.76, leaf_tip_lift, 0.56))
		var c_l2 := _scale_flora_linear(leaf_upper,
			_flora_contact_ao_gain(l2.y, 0.74, 0.76, leaf_tip_lift, 0.56))
		var c_r2 := _scale_flora_linear(leaf_upper,
			_flora_contact_ao_gain(r2.y, 0.74, 0.76, leaf_tip_lift, 0.56))
		var c_p3 := _scale_flora_linear(leaf_tip,
			_flora_contact_ao_gain(p3.y, 1.0, 0.76, leaf_tip_lift, 0.56))

		var uv2_a := Vector2(0.16, phase_01)
		var uv2_b := Vector2(0.32, phase_01)
		var uv2_c := Vector2(0.46, phase_01)
		var uv2_d := Vector2(0.58, phase_01)

		# 8-triangle V-creased serrated/pointed oval glossy tropical leaf.
		_add_foliage_tri(st, p0, l1, p1, c_p0, c_l1, c_p1,
			Vector2(0.5, 0.0), Vector2(0.0, 0.36), Vector2(0.5, 0.36), uv2_a, uv2_b, uv2_b)
		_add_foliage_tri(st, p0, p1, r1, c_p0, c_p1, c_r1,
			Vector2(0.5, 0.0), Vector2(0.5, 0.36), Vector2(1.0, 0.36), uv2_a, uv2_b, uv2_b)
		_add_foliage_tri(st, l1, l2, p2, c_l1, c_l2, c_p2,
			Vector2(0.0, 0.36), Vector2(0.14, 0.70), Vector2(0.5, 0.70), uv2_b, uv2_c, uv2_c)
		_add_foliage_tri(st, l1, p2, p1, c_l1, c_p2, c_p1,
			Vector2(0.0, 0.36), Vector2(0.5, 0.70), Vector2(0.5, 0.36), uv2_b, uv2_c, uv2_b)
		_add_foliage_tri(st, p1, p2, r2, c_p1, c_p2, c_r2,
			Vector2(0.5, 0.36), Vector2(0.5, 0.70), Vector2(0.86, 0.70), uv2_b, uv2_c, uv2_c)
		_add_foliage_tri(st, p1, r2, r1, c_p1, c_r2, c_r1,
			Vector2(0.5, 0.36), Vector2(0.86, 0.70), Vector2(1.0, 0.36), uv2_b, uv2_c, uv2_b)
		_add_foliage_tri(st, l2, p3, p2, c_l2, c_p3, c_p2,
			Vector2(0.14, 0.70), Vector2(0.5, 1.0), Vector2(0.5, 0.70), uv2_c, uv2_d, uv2_c)
		_add_foliage_tri(st, p2, p3, r2, c_p2, c_p3, c_r2,
			Vector2(0.5, 0.70), Vector2(0.5, 1.0), Vector2(0.86, 0.70), uv2_c, uv2_d, uv2_c)

	# 3. 6 vibrant sculpted 5-petal tropical Hibiscus blossoms + golden stamen stalks (78 tris)!
	# Slight blue lift on pink/crimson/magenta petals offsets foliage_wind.gdshader's warm golden tip tint,
	# while 1.05x sunlit petal luminance keeps every bloom crisp & vivid against the shaded canopy.
	# [pos, axis, radius, throat_srgb, petal_srgb, phase_01, cup_scale]
	var blossoms: Array[Array] = [
		[Vector3(0.08, 0.88,  0.08), Vector3(0.20, 0.94,  0.24), 0.23, Color(0.72, 0.08, 0.16), Color(1.00, 0.24, 0.34), 0.10, 1.00],  # Crimson-coral
		[Vector3(0.42, 0.66,  0.24), Vector3(0.66, 0.68,  0.32), 0.22, Color(0.78, 0.12, 0.48), Color(1.00, 0.38, 0.78), 0.28, 1.00],  # Hibiscus-pink
		[Vector3(-0.40, 0.70,  0.28), Vector3(-0.62, 0.70,  0.38), 0.22, Color(0.84, 0.22, 0.05), Color(1.00, 0.52, 0.16), 0.46, 1.00], # Sunset-orange
		[Vector3(-0.22, 0.64, -0.40), Vector3(-0.36, 0.70, -0.62), 0.21, Color(0.88, 0.42, 0.06), Color(1.00, 0.84, 0.24), 0.64, 1.00], # Tropical gold
		[Vector3(0.36, 0.60, -0.32), Vector3(0.56, 0.66, -0.50), 0.21, Color(0.76, 0.12, 0.14), Color(1.00, 0.34, 0.28), 0.80, 1.00], # Bright coral-red
		[Vector3(-0.18, 0.86, -0.14), Vector3(-0.34, 0.92, -0.24), 0.19, Color(0.68, 0.06, 0.38), Color(1.00, 0.26, 0.72), 0.93, 1.38], # Magenta-rose crown bud
	]
	var stamen_col := _scale_flora_linear(Color(1.00, 0.90, 0.32, 1.0).srgb_to_linear(), 1.05)

	for bspec in blossoms:
		var b_pos: Vector3 = bspec[0] as Vector3
		var b_axis := (bspec[1] as Vector3).normalized()
		var b_rad: float = float(bspec[2])
		var col_throat := _scale_flora_linear((bspec[3] as Color).srgb_to_linear(), 0.96)
		var col_petal := _scale_flora_linear((bspec[4] as Color).srgb_to_linear(), 1.05)
		var phase_01: float = float(bspec[5])
		var cup_sc: float = float(bspec[6])

		var ref := Vector3.RIGHT if absf(b_axis.dot(Vector3.RIGHT)) < 0.88 else Vector3.FORWARD
		var u := b_axis.cross(ref).normalized()
		var v := b_axis.cross(u).normalized()
		var uv2_ctr := Vector2(0.44, phase_01)
		var uv2_rim := Vector2(0.56, phase_01)

		for pi in 5:
			var ang := float(pi) / 5.0 * TAU + phase_01 * 2.0
			var p_dir := u * cos(ang) + v * sin(ang)
			var p_side := -u * sin(ang) + v * cos(ang)
			var p_mid := b_pos + p_dir * (b_rad * 0.56) + b_axis * (b_rad * 0.14 * cup_sc)
			var p_tip := b_pos + p_dir * b_rad + b_axis * (b_rad * 0.34 * cup_sc)
			var p_l := p_mid - p_side * (b_rad * 0.44) + b_axis * (b_rad * 0.08 * cup_sc)
			var p_r := p_mid + p_side * (b_rad * 0.44) + b_axis * (b_rad * 0.04 * cup_sc)

			# Broad cupped 2-triangle Hibiscus petal.
			_add_foliage_tri(st, b_pos, p_l, p_tip, col_throat, col_petal, col_petal,
				Vector2(0.5, 0.0), Vector2(0.0, 0.6), Vector2(0.5, 1.0), uv2_ctr, uv2_rim, uv2_rim)
			_add_foliage_tri(st, b_pos, p_tip, p_r, col_throat, col_petal, col_petal,
				Vector2(0.5, 0.0), Vector2(0.5, 1.0), Vector2(1.0, 0.6), uv2_ctr, uv2_rim, uv2_rim)

		# Protruding golden Hibiscus stamen stalk pyramid (3 tris).
		var st_tip := b_pos + b_axis * (b_rad * 0.68)
		var sr := b_rad * 0.15
		var sb0 := b_pos + u * sr
		var sb1 := b_pos + (-u * 0.5 + v * 0.866) * sr
		var sb2 := b_pos + (-u * 0.5 - v * 0.866) * sr
		_add_foliage_tri(st, sb0, sb1, st_tip, col_throat, col_throat, stamen_col,
			Vector2(0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, 1.0), uv2_ctr, uv2_ctr, uv2_rim)
		_add_foliage_tri(st, sb1, sb2, st_tip, col_throat, col_throat, stamen_col,
			Vector2(0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, 1.0), uv2_ctr, uv2_ctr, uv2_rim)
		_add_foliage_tri(st, sb2, sb0, st_tip, col_throat, col_throat, stamen_col,
			Vector2(0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, 1.0), uv2_ctr, uv2_ctr, uv2_rim)

	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ Mesh 4: Sculpted Gnarled Coastal Driftwood Log

static func _build_driftwood_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Main weathered arched trunk (~2.4 m along local X): [x, y, z, rx_radius, shade_top]
	var spine: Array[Array] = [
		[-1.22, 0.04, -0.08, 0.12, 0.84],
		[-0.74, 0.13, -0.02, 0.19, 0.90],
		[-0.20, 0.20,  0.05, 0.21, 0.95],
		[ 0.36, 0.17,  0.03, 0.18, 0.93],
		[ 0.84, 0.11, -0.05, 0.14, 0.88],
		[ 1.18, 0.05, -0.10, 0.08, 0.86],
	]

	var col_under := Color(0.36, 0.29, 0.22, 1.0)
	var col_side := Color(0.62, 0.55, 0.46, 1.0)
	var col_sun := Color(0.82, 0.77, 0.69, 1.0)
	var col_splinter := Color(0.80, 0.68, 0.51, 1.0)

	# 8-sided gnarled bark profile with twisted longitudinal bark ribs & shaded furrows.
	var sides := 8
	var rings: Array[Array] = []
	var ring_cols: Array[Array] = []
	for si in spine.size():
		var row: Array = spine[si]
		var ctr := Vector3(float(row[0]), float(row[1]), float(row[2]))
		var rad: float = float(row[3])
		var shade_k: float = float(row[4])
		var pts: Array[Vector3] = []
		var cols: Array[Color] = []
		for k in sides:
			var ang := float(k) / float(sides) * TAU + float(si) * 0.14
			var ridge_sign := 1.0 if (k % 2 == 0) else -1.0
			var rib := 0.94 + 0.09 * ridge_sign + 0.07 * sin(ang * 3.0 + float(si) * 1.1)
			var dy := sin(ang) * rad * rib * 0.86
			var dz := cos(ang) * rad * rib
			pts.append(ctr + Vector3(0.0, dy, dz))
			var up_t := clampf(sin(ang) * 0.5 + 0.5, 0.0, 1.0)
			var furrow_k := 1.04 if (k % 2 == 0) else 0.88
			var c := col_under.lerp(col_side, smoothstep(0.0, 0.55, up_t)).lerp(col_sun, smoothstep(0.55, 1.0, up_t))
			cols.append(Color(
				clampf(c.r * shade_k * furrow_k, 0.0, 1.0),
				clampf(c.g * shade_k * furrow_k, 0.0, 1.0),
				clampf(c.b * shade_k * furrow_k, 0.0, 1.0),
				1.0))
		rings.append(pts)
		ring_cols.append(cols)

	for si in range(spine.size() - 1):
		var r0: Array = rings[si]
		var r1: Array = rings[si + 1]
		var c0: Array = ring_cols[si]
		var c1: Array = ring_cols[si + 1]
		var ref_ctr := (Vector3(float(spine[si][0]), float(spine[si][1]), float(spine[si][2]))
			+ Vector3(float(spine[si + 1][0]), float(spine[si + 1][1]), float(spine[si + 1][2]))) * 0.5
		for k in sides:
			var nk := (k + 1) % sides
			_add_outward_quad(st, r0[k], r1[k], r1[nk], r0[nk], ref_ctr, c0[k], c1[k], c1[nk], c0[nk])

	# Splintered jagged broken ends on -X and +X showing paler exposed heartwood.
	var cap_neg := Vector3(-1.38, 0.08, -0.10)
	var ref_neg := Vector3(-0.90, 0.10, -0.04)
	for k in sides:
		var nk := (k + 1) % sides
		_add_outward_tri(st, rings[0][k], cap_neg, rings[0][nk], ref_neg,
			ring_cols[0][k], col_splinter, ring_cols[0][nk])

	var cap_pos := Vector3(1.30, 0.07, -0.12)
	var ref_pos := Vector3(0.88, 0.10, -0.06)
	var last_i := rings.size() - 1
	for k in sides:
		var nk := (k + 1) % sides
		_add_outward_tri(st, rings[last_i][k], cap_pos, rings[last_i][nk], ref_pos,
			ring_cols[last_i][k], col_splinter, ring_cols[last_i][nk])

	# Forked gnarled coastal branch snag jutting from mid-trunk.
	_append_tapered_limb_solid(st, Vector3(0.18, 0.18, 0.04), Vector3(0.58, 0.34, 0.38),
		0.115, 0.068, 5, col_side, col_sun, false, col_splinter)
	_append_tapered_limb_solid(st, Vector3(0.58, 0.34, 0.38), Vector3(0.82, 0.44, 0.56),
		0.068, 0.036, 5, col_sun, col_splinter, true, col_splinter)

	# Stubby weathered root-knot spur on opposite side.
	_append_tapered_limb_solid(st, Vector3(-0.56, 0.14, -0.02), Vector3(-0.78, 0.24, -0.34),
		0.105, 0.048, 5, col_under.lerp(col_side, 0.6), col_splinter, true, col_splinter)

	# Secondary splintered root-crown claw: 2 gnarled weathered root spurs gripping into the sand at -X.
	var col_root_base := col_under.lerp(col_side, 0.55)
	_append_tapered_limb_solid(st, Vector3(-1.02, 0.09, -0.02), Vector3(-1.34, 0.12, 0.24),
		0.095, 0.056, 5, col_root_base, col_side, false, col_splinter)
	_append_tapered_limb_solid(st, Vector3(-1.34, 0.12, 0.24), Vector3(-1.54, -0.07, 0.36),
		0.056, 0.028, 5, col_side, col_splinter, true, col_splinter)

	_append_tapered_limb_solid(st, Vector3(-1.08, 0.07, -0.09), Vector3(-1.38, 0.05, -0.34),
		0.088, 0.052, 5, col_under, col_root_base, false, col_splinter)
	_append_tapered_limb_solid(st, Vector3(-1.38, 0.05, -0.34), Vector3(-1.56, -0.08, -0.44),
		0.052, 0.024, 5, col_root_base, col_splinter, true, col_splinter)

	# 2 clinging wet sea-kelp ribbons draped across the damp lower trunk flanks onto the sand.
	var col_kelp_dark := Color(0.24, 0.38, 0.20, 1.0)
	var col_kelp_bright := Color(0.36, 0.50, 0.24, 1.0)

	var kelp_a_pts: Array[Vector3] = []
	var kelp_a_norms: Array[Vector3] = []
	var kelp_a_widths: Array[float] = [0.028, 0.048, 0.054, 0.044, 0.026]
	var kelp_a_specs: Array[Vector2] = [
		Vector2(1.55, 1.05),
		Vector2(1.75, 0.52),
		Vector2(1.95, 0.02),
		Vector2(2.15, -0.46),
	]
	for ks in kelp_a_specs:
		var samp := _sample_driftwood_surface(spine, ks.x, ks.y, 1.06)
		kelp_a_pts.append(samp[0])
		kelp_a_norms.append(samp[1])
	kelp_a_pts.append(Vector3(0.02, 0.015, 0.33))
	kelp_a_norms.append(Vector3(0.0, 0.96, 0.28).normalized())
	_append_kelp_ribbon(st, kelp_a_pts, kelp_a_norms, kelp_a_widths,
		Vector3(0.08, -0.015, 0.39), col_kelp_dark, col_kelp_bright)

	var kelp_b_pts: Array[Vector3] = []
	var kelp_b_norms: Array[Vector3] = []
	var kelp_b_widths: Array[float] = [0.026, 0.044, 0.050, 0.040, 0.024]
	var kelp_b_specs: Array[Vector2] = [
		Vector2(2.95, 2.15),
		Vector2(3.15, 2.66),
		Vector2(3.35, 3.16),
		Vector2(3.55, 3.62),
	]
	for ks in kelp_b_specs:
		var samp := _sample_driftwood_surface(spine, ks.x, ks.y, 1.06)
		kelp_b_pts.append(samp[0])
		kelp_b_norms.append(samp[1])
	kelp_b_pts.append(Vector3(0.68, 0.015, -0.25))
	kelp_b_norms.append(Vector3(0.0, 0.96, -0.28).normalized())
	_append_kelp_ribbon(st, kelp_b_pts, kelp_b_norms, kelp_b_widths,
		Vector3(0.76, -0.015, -0.31), col_kelp_dark, col_kelp_bright)

	# 3 subtle pale coastal barnacle nodule bumps clinging to the water-washed lower flank.
	var col_barn_base := Color(0.68, 0.65, 0.58, 1.0)
	var col_barn_rim := Color(0.92, 0.90, 0.84, 1.0)
	var col_barn_cup := Color(0.38, 0.36, 0.32, 1.0)
	var dw_barnacles: Array[Array] = [
		[2.48, -0.18, 0.044, 0.044],
		[2.66, -0.34, 0.034, 0.036],
		[1.42,  3.34, 0.040, 0.040],
	]
	for bspec in dw_barnacles:
		var bsamp := _sample_driftwood_surface(spine, float(bspec[0]), float(bspec[1]), 0.90)
		_append_barnacle_cone(st, bsamp[0], bsamp[1], float(bspec[2]), float(bspec[3]), 5,
			col_barn_base, col_barn_rim, col_barn_cup)

	st.generate_normals()
	return st.commit()


static func _sample_driftwood_surface(spine: Array[Array], si_f: float, ang: float,
		rad_scale: float) -> Array[Vector3]:
	var max_idx := spine.size() - 2
	var i0 := clampi(int(floor(si_f)), 0, max_idx)
	var t := clampf(si_f - float(i0), 0.0, 1.0)
	var row0: Array = spine[i0]
	var row1: Array = spine[i0 + 1]
	var ctr := Vector3(
		lerpf(float(row0[0]), float(row1[0]), t),
		lerpf(float(row0[1]), float(row1[1]), t),
		lerpf(float(row0[2]), float(row1[2]), t))
	var rad := lerpf(float(row0[3]), float(row1[3]), t)
	var rib := rad_scale + 0.07 * sin(ang * 3.0 + si_f * 1.1)
	var pos := ctr + Vector3(0.0, sin(ang) * rad * rib * 0.86, cos(ang) * rad * rib)
	var n := Vector3(0.0, sin(ang), cos(ang)).normalized()
	return [pos, n]


static func _append_kelp_ribbon(st: SurfaceTool, pts: Array[Vector3], norms: Array[Vector3],
		widths: Array[float], tip_pos: Vector3, col_dark: Color, col_bright: Color) -> void:
	var count := mini(pts.size(), mini(norms.size(), widths.size()))
	if count < 2:
		return
	var left_ring: Array[Vector3] = []
	var mid_ring: Array[Vector3] = []
	var right_ring: Array[Vector3] = []
	for i in count:
		var p := pts[i]
		var n_out := norms[i].normalized() if norms[i].length_squared() > 1e-8 else Vector3.UP
		var tangent := Vector3.ZERO
		if i == 0:
			tangent = pts[1] - pts[0]
		elif i == count - 1:
			tangent = tip_pos - pts[i - 1]
		else:
			tangent = pts[i + 1] - pts[i - 1]
		if tangent.length_squared() < 1e-8:
			tangent = Vector3.RIGHT
		else:
			tangent = tangent.normalized()
		var side := tangent.cross(n_out)
		if side.length_squared() < 1e-8:
			side = Vector3.RIGHT
		else:
			side = side.normalized()
		var hw := widths[i]
		# Tuck ribbon flanks snugly onto the bark while lifting the glossy central midrib proud.
		left_ring.append(p - side * hw - n_out * 0.008)
		mid_ring.append(p + n_out * 0.015)
		right_ring.append(p + side * hw - n_out * 0.008)

	# Tapered start leaf tip anchored at the upper drape point.
	var start_dir := (pts[0] - pts[1]).normalized() if pts[0].distance_squared_to(pts[1]) > 1e-8 else Vector3.UP
	var start_tip := pts[0] + start_dir * 0.045 - norms[0] * 0.004
	var start_ref := pts[0] - norms[0] * 0.14
	_add_outward_tri(st, start_tip, mid_ring[0], left_ring[0], start_ref, col_dark, col_bright, col_dark)
	_add_outward_tri(st, start_tip, right_ring[0], mid_ring[0], start_ref, col_dark, col_dark, col_bright)

	for i in range(count - 1):
		var n_mid := (norms[i] + norms[i + 1]).normalized()
		var ref_seg := (mid_ring[i] + mid_ring[i + 1]) * 0.5 - n_mid * 0.16
		var c_edge_0 := col_dark.lerp(col_bright, 0.18)
		var c_edge_1 := col_dark.lerp(col_bright, 0.12)
		var c_mid_0 := col_bright.lerp(col_dark, float(i) / float(count) * 0.25)
		var c_mid_1 := col_bright.lerp(col_dark, float(i + 1) / float(count) * 0.25)
		_add_outward_quad(st, left_ring[i], mid_ring[i], mid_ring[i + 1], left_ring[i + 1],
			ref_seg, c_edge_0, c_mid_0, c_mid_1, c_edge_1)
		_add_outward_quad(st, mid_ring[i], right_ring[i], right_ring[i + 1], mid_ring[i + 1],
			ref_seg, c_mid_0, c_edge_0, c_edge_1, c_mid_1)

	# Tapered trailing tip resting on the wet beach sand.
	var last := count - 1
	var end_ref := (mid_ring[last] + tip_pos) * 0.5 - norms[last] * 0.14
	_add_outward_tri(st, left_ring[last], mid_ring[last], tip_pos, end_ref, col_dark, col_bright, col_dark)
	_add_outward_tri(st, mid_ring[last], right_ring[last], tip_pos, end_ref, col_bright, col_dark, col_dark)


static func _append_barnacle_cone(st: SurfaceTool, base_pos: Vector3, up_dir: Vector3,
		base_r: float, height: float, sides: int, col_base: Color, col_rim: Color,
		col_cup: Color) -> void:
	var n := up_dir.normalized() if up_dir.length_squared() > 1e-8 else Vector3.UP
	var ref_axis := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
	var u := n.cross(ref_axis).normalized()
	var v := n.cross(u).normalized()

	var base_ring: Array[Vector3] = []
	var rim_ring: Array[Vector3] = []
	var rim_r := base_r * 0.45
	for k in sides:
		var ang := float(k) / float(sides) * TAU
		var radial := u * cos(ang) + v * sin(ang)
		var b_jit := 0.92 + 0.12 * sin(ang * 2.0 + 0.5)
		var r_jit := 0.94 + 0.08 * cos(ang * 3.0)
		base_ring.append(base_pos - n * 0.010 + radial * (base_r * b_jit))
		rim_ring.append(base_pos + n * height + radial * (rim_r * r_jit))

	var cup_pt := base_pos + n * (height * 0.62)
	var outer_ref := base_pos + n * (height * 0.30)
	var cup_ref := base_pos - n * 0.06
	for k in sides:
		var nk := (k + 1) % sides
		_add_outward_quad(st, base_ring[k], rim_ring[k], rim_ring[nk], base_ring[nk],
			outer_ref, col_base, col_rim, col_rim, col_base)
		_add_outward_tri(st, rim_ring[k], cup_pt, rim_ring[nk], cup_ref, col_rim, col_cup, col_rim)


# ------------------------------------------------------------------ Mesh 5: Shore Pebbles, Fluted Spiral Shell & Coral Sea Star

static func _build_pebbles_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 5 sculpted beveled beach cobbles/pebbles across ~1.2 m footprint.
	# [center_xz, rx, ry, rz, yaw, col_bot, col_top]
	var cobbles: Array[Array] = [
		[Vector2(-0.34, -0.18), 0.26, 0.15, 0.21, 0.42, Color(0.54, 0.49, 0.44), Color(0.84, 0.78, 0.70)],
		[Vector2( 0.22, -0.28), 0.22, 0.13, 0.18, 1.35, Color(0.56, 0.49, 0.41), Color(0.84, 0.76, 0.65)],
		[Vector2(-0.08,  0.34), 0.24, 0.12, 0.19, 2.20, Color(0.62, 0.51, 0.39), Color(0.88, 0.76, 0.60)],
		[Vector2(-0.52,  0.18), 0.16, 0.10, 0.14, 0.85, Color(0.58, 0.54, 0.48), Color(0.86, 0.82, 0.74)],
		[Vector2( 0.46,  0.22), 0.18, 0.11, 0.15, 2.85, Color(0.48, 0.45, 0.42), Color(0.79, 0.75, 0.68)],
	]

	for cspec in cobbles:
		var cxz: Vector2 = cspec[0] as Vector2
		_append_beveled_cobble(st, Vector3(cxz.x, 0.0, cxz.y),
			float(cspec[1]), float(cspec[2]), float(cspec[3]), float(cspec[4]),
			cspec[5] as Color, cspec[6] as Color)

	# 1 sculpted fluted coastal conch/scallop shell nestled prominently near cluster center.
	_append_fluted_shell(st, Vector3(0.14, 0.03, 0.04), 0.28, 0.55)

	# 1 sculpted 5-arm coastal coral sea star resting organically on the open sandy edge.
	_append_sea_star(st, Vector3(0.22, 0.035, 0.54), 0.22, 0.58)

	st.generate_normals()
	return st.commit()


static func _append_beveled_cobble(st: SurfaceTool, center: Vector3, rx: float, ry: float,
		rz: float, yaw: float, col_bot: Color, col_top: Color) -> void:
	const SIDES := 6
	var cy := cos(yaw)
	var sy := sin(yaw)
	var bot_r: Array[Vector3] = []
	var mid_r: Array[Vector3] = []
	var top_r: Array[Vector3] = []

	for k in SIDES:
		var ang := float(k) / float(SIDES) * TAU
		var jit := 0.90 + 0.14 * sin(ang * 2.0 + yaw * 3.0)
		var lx := cos(ang) * rx * jit
		var lz := sin(ang) * rz * jit
		var wx := lx * cy - lz * sy
		var wz := lx * sy + lz * cy
		bot_r.append(center + Vector3(wx * 0.94, -0.05, wz * 0.94))
		mid_r.append(center + Vector3(wx, ry * 0.44, wz))
		top_r.append(center + Vector3(wx * 0.64, ry * 0.92, wz * 0.64))

	var crown := center + Vector3(0.0, ry, 0.0)
	var ref := center + Vector3(0.0, ry * 0.35, 0.0)
	var col_mid := col_bot.lerp(col_top, 0.52)
	var col_hi := col_top.lerp(Color(1.0, 0.98, 0.94, 1.0), 0.25)

	for k in SIDES:
		var nk := (k + 1) % SIDES
		_add_outward_quad(st, bot_r[k], mid_r[k], mid_r[nk], bot_r[nk], ref, col_bot, col_mid, col_mid, col_bot)
		_add_outward_quad(st, mid_r[k], top_r[k], top_r[nk], mid_r[nk], ref, col_mid, col_top, col_top, col_mid)
		_add_outward_tri(st, top_r[k], crown, top_r[nk], ref, col_top, col_hi, col_top)


static func _append_fluted_shell(st: SurfaceTool, origin: Vector3, length: float, yaw: float) -> void:
	# Fluted fan-ribbed coastal scallop/conch shell (5 ribs + coiled umbo apex + warm coral-pink lip).
	var cy := cos(yaw)
	var sy := sin(yaw)
	var to_world := func(p: Vector3) -> Vector3:
		return origin + Vector3(p.x * cy - p.z * sy, p.y, p.x * sy + p.z * cy)

	var col_umbo := Color(0.84, 0.75, 0.64, 1.0)
	var col_cream := Color(0.96, 0.92, 0.83, 1.0)
	var col_rib := Color(1.00, 0.97, 0.90, 1.0)
	var col_lip := Color(0.92, 0.56, 0.49, 1.0)
	var col_under := Color(0.76, 0.66, 0.58, 1.0)

	var apex: Vector3 = to_world.call(Vector3(0.0, 0.04, -length * 0.48))
	var under_hub: Vector3 = to_world.call(Vector3(0.0, -0.02, 0.02))
	var ref_ctr: Vector3 = to_world.call(Vector3(0.0, 0.03, 0.02))

	var ribs := 6
	var mid_arc: Array[Vector3] = []
	var rim_arc: Array[Vector3] = []
	var rim_cols: Array[Color] = []
	for i in range(ribs + 1):
		var u := float(i) / float(ribs)
		var fan_ang := lerpf(-0.98, 0.98, u)
		var flute := 1.0 if (i % 2 == 0) else 0.78
		var r_mid := length * 0.48
		var r_rim := length * (0.94 + 0.06 * flute)
		var y_arch := 0.09 * (1.0 - pow(u * 2.0 - 1.0, 2.0)) + 0.026 * flute
		var mx := sin(fan_ang) * r_mid
		var mz := -length * 0.42 + cos(fan_ang) * r_mid
		var rx := sin(fan_ang) * r_rim
		var rz := -length * 0.42 + cos(fan_ang) * r_rim
		mid_arc.append(to_world.call(Vector3(mx, y_arch + 0.02, mz)))
		rim_arc.append(to_world.call(Vector3(rx, 0.02 + 0.024 * flute, rz)))
		rim_cols.append(col_rib if (i % 2 == 0) else col_lip)

	for i in ribs:
		_add_outward_tri(st, apex, mid_arc[i], mid_arc[i + 1], ref_ctr, col_umbo, col_cream, col_cream)
		_add_outward_quad(st, mid_arc[i], rim_arc[i], rim_arc[i + 1], mid_arc[i + 1], ref_ctr,
			col_cream, rim_cols[i], rim_cols[i + 1], col_cream)
		_add_outward_tri(st, under_hub, rim_arc[i + 1], rim_arc[i], ref_ctr,
			col_under, rim_cols[i + 1], rim_cols[i])

	# Coiled spiral conch tail spire protruding slightly behind the apex.
	var spire_tip: Vector3 = to_world.call(Vector3(-0.04, 0.05, -length * 0.66))
	var sp_a: Vector3 = to_world.call(Vector3(-0.05, 0.02, -length * 0.44))
	var sp_b: Vector3 = to_world.call(Vector3(0.05, 0.02, -length * 0.44))
	var sp_c: Vector3 = to_world.call(Vector3(0.0, 0.08, -length * 0.44))
	_add_outward_tri(st, sp_a, sp_b, spire_tip, ref_ctr, col_umbo, col_umbo, col_lip)
	_add_outward_tri(st, sp_b, sp_c, spire_tip, ref_ctr, col_umbo, col_rib, col_lip)
	_add_outward_tri(st, sp_c, sp_a, spire_tip, ref_ctr, col_rib, col_umbo, col_lip)


static func _append_sea_star(st: SurfaceTool, origin: Vector3, arm_len: float, yaw: float) -> void:
	# Sculpted 5-arm coastal sea star: raised pentagonal disc + gently arched curved arms +
	# coral-gold dorsal spine tubercles & grounded shaded underside hugging the sand (85 tris).
	const ARMS := 5
	var col_dorsal := Color(0.95, 0.44, 0.22, 1.0)
	var col_spine := Color(1.00, 0.76, 0.46, 1.0)
	var col_flank := Color(0.84, 0.36, 0.19, 1.0)
	var col_under := Color(0.58, 0.26, 0.16, 1.0)
	var col_mid_spine := col_dorsal.lerp(col_spine, 0.68)
	var col_tip := col_dorsal.lerp(col_spine, 0.28)

	var crown := origin + Vector3(0.0, 0.054, 0.0)
	var under_ctr := origin + Vector3(0.0, -0.024, 0.0)
	var ref_disc := origin + Vector3(0.0, -0.020, 0.0)

	# 5 inter-arm web valley vertices shared cleanly between adjacent arms.
	var valleys: Array[Vector3] = []
	for a in ARMS:
		var ang_v := yaw + (float(a) + 0.5) / float(ARMS) * TAU
		var r_v := arm_len * 0.29
		valleys.append(origin + Vector3(cos(ang_v) * r_v, 0.016, sin(ang_v) * r_v))

	for a in ARMS:
		var ang_a := yaw + float(a) / float(ARMS) * TAU
		var dir := Vector3(cos(ang_a), 0.0, sin(ang_a))
		# +right_dir points toward valleys[a] (increasing angle), -right_dir toward valleys[prev].
		var right_dir := Vector3(-sin(ang_a), 0.0, cos(ang_a))
		var v_prev := valleys[(a + ARMS - 1) % ARMS]
		var v_next := valleys[a]

		var len_a := arm_len * (0.94 + 0.09 * sin(float(a) * 1.7 + 0.4))
		var sway := sin(float(a) * 2.1 + 0.5) * 0.022
		var r0 := len_a * 0.27
		var r1 := len_a * 0.62

		var root_ridge := origin + dir * r0 + Vector3(0.0, 0.044, 0.0)
		var mid_base := origin + dir * r1 + right_dir * (sway * 0.55)
		var w1 := len_a * 0.145
		var ridge_mid := mid_base + Vector3(0.0, 0.039, 0.0)
		var left_mid := mid_base - right_dir * w1 + Vector3(0.0, 0.015, 0.0)
		var right_mid := mid_base + right_dir * w1 + Vector3(0.0, 0.015, 0.0)
		var bot_mid := mid_base + Vector3(0.0, -0.020, 0.0)
		var tip := origin + dir * len_a + right_dir * sway + Vector3(0.0, 0.016, 0.0)

		var seg0_ctr := (origin + dir * r0 + mid_base) * 0.5
		var ref_seg0_top := seg0_ctr + Vector3(0.0, -0.018, 0.0)
		var ref_seg0_bot := seg0_ctr + Vector3(0.0, 0.032, 0.0)
		var ref_tip := (mid_base + tip) * 0.5 + Vector3(0.0, 0.010, 0.0)

		# Raised pentagonal central disc dorsal facets.
		_add_outward_tri(st, crown, v_prev, root_ridge, ref_disc, col_spine, col_flank, col_spine)
		_add_outward_tri(st, crown, root_ridge, v_next, ref_disc, col_spine, col_spine, col_flank)

		# Proximal arched arm dorsal & grounded shaded underside facets.
		_add_outward_quad(st, v_prev, root_ridge, ridge_mid, left_mid,
			ref_seg0_top, col_flank, col_spine, col_mid_spine, col_dorsal)
		_add_outward_quad(st, root_ridge, v_next, right_mid, ridge_mid,
			ref_seg0_top, col_spine, col_flank, col_dorsal, col_mid_spine)
		_add_outward_tri(st, v_prev, left_mid, bot_mid, ref_seg0_bot, col_flank, col_dorsal, col_under)
		_add_outward_tri(st, v_prev, bot_mid, under_ctr, ref_seg0_bot, col_flank, col_under, col_under)
		_add_outward_tri(st, v_next, bot_mid, right_mid, ref_seg0_bot, col_flank, col_under, col_dorsal)
		_add_outward_tri(st, v_next, under_ctr, bot_mid, ref_seg0_bot, col_flank, col_under, col_under)

		# Distal tapering arm tip hugging the sand.
		_add_outward_tri(st, left_mid, ridge_mid, tip, ref_tip, col_dorsal, col_mid_spine, col_tip)
		_add_outward_tri(st, ridge_mid, right_mid, tip, ref_tip, col_mid_spine, col_dorsal, col_tip)
		_add_outward_tri(st, left_mid, tip, bot_mid, ref_tip, col_dorsal, col_tip, col_under)
		_add_outward_tri(st, right_mid, bot_mid, tip, ref_tip, col_dorsal, col_under, col_tip)

		# Sculpted coral-gold dorsal spine tubercle crest along each ray.
		var r_tb := len_a * 0.44
		var tb_ctr := origin + dir * r_tb + right_dir * (sway * 0.28) + Vector3(0.0, 0.038, 0.0)
		var tb_a := tb_ctr + dir * 0.018
		var tb_b := tb_ctr - dir * 0.014 - right_dir * 0.014
		var tb_c := tb_ctr - dir * 0.014 + right_dir * 0.014
		var tb_apex := tb_ctr + Vector3(0.0, 0.015, 0.0)
		var tb_ref := tb_ctr + Vector3(0.0, -0.015, 0.0)
		_add_outward_tri(st, tb_a, tb_b, tb_apex, tb_ref, col_dorsal, col_dorsal, col_spine)
		_add_outward_tri(st, tb_b, tb_c, tb_apex, tb_ref, col_dorsal, col_dorsal, col_spine)
		_add_outward_tri(st, tb_c, tb_a, tb_apex, tb_ref, col_dorsal, col_dorsal, col_spine)


# ------------------------------------------------------------------ Mesh 6: Undercut Barnacle-Ringed Tidal Outcrop Cluster

static func _build_tidal_rock_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 4 interlocked stratified coastal rocks: dark wet sea-moss base -> wave-carved barnacle undercut -> sunlit ochre crest.
	var main_ctr := Vector3(-0.06, 0.0, 0.02)
	var main_rx := 0.96
	var main_h := 1.24
	var main_rz := 0.80
	var main_phase := 0.35
	_append_tidal_boulder(st, main_ctr, main_rx, main_h, main_rz, -0.44, 8, main_phase)
	_append_tidal_boulder(st, Vector3( 0.88, 0.0,  0.34), 0.66, 0.78, 0.56, -0.36, 7, 1.85)
	_append_tidal_boulder(st, Vector3(-0.84, 0.0, -0.30), 0.60, 0.50, 0.52, -0.34, 6, 3.40)
	_append_tidal_boulder(st, Vector3(-0.32, 0.0,  0.72), 0.44, 0.40, 0.38, -0.32, 6, 4.95)

	# 4 sculpted white-ivory barnacle/limpet shell cones hugging the damp tier-1 tidal waterline ring.
	var col_shell_base := Color(0.76, 0.74, 0.68, 1.0)
	var col_shell_rim := Color(0.97, 0.95, 0.89, 1.0)
	var col_shell_cup := Color(0.36, 0.34, 0.30, 1.0)
	# [azimuth_rad, base_r, height, is_limpet]
	var waterline_shells: Array[Array] = [
		[ 1.05, 0.105, 0.072, false],
		[ 1.28, 0.078, 0.056, false],
		[ 2.68, 0.095, 0.056, true],
		[-0.82, 0.092, 0.066, false],
	]
	for wspec in waterline_shells:
		var ang: float = float(wspec[0])
		var crag := 0.84 + 0.22 * sin(ang * 3.0 + main_phase) + 0.10 * cos(ang * 5.0 - 1.0)
		var px := main_ctr.x + cos(ang) * main_rx * 0.85 * crag
		var pz := main_ctr.z + sin(ang) * main_rz * 0.85 * crag
		var py := main_h * 0.20 + 0.06 * sin(ang * 2.0 + main_phase)
		var n_out := Vector3(cos(ang) / main_rx, 0.18, sin(ang) / main_rz).normalized()
		if bool(wspec[3]):
			_append_limpet_cone(st, Vector3(px, py, pz), n_out, float(wspec[1]), float(wspec[2]), 5,
				col_shell_base, col_shell_rim)
		else:
			_append_barnacle_cone(st, Vector3(px, py, pz), n_out, float(wspec[1]), float(wspec[2]), 5,
				col_shell_base, col_shell_rim, col_shell_cup)

	st.generate_normals()
	return st.commit()


static func _append_limpet_cone(st: SurfaceTool, base_pos: Vector3, up_dir: Vector3,
		base_r: float, height: float, sides: int, col_rim: Color, col_peak: Color) -> void:
	var n := up_dir.normalized() if up_dir.length_squared() > 1e-8 else Vector3.UP
	var ref_axis := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
	var u := n.cross(ref_axis).normalized()
	var v := n.cross(u).normalized()

	var base_ring: Array[Vector3] = []
	var mid_ring: Array[Vector3] = []
	var col_mid := col_rim.lerp(col_peak, 0.62)
	for k in sides:
		var ang := float(k) / float(sides) * TAU
		var rib := 0.90 + 0.14 * (1.0 if (k % 2 == 0) else -1.0)
		var radial := u * (cos(ang) * 1.12) + v * (sin(ang) * 0.88)
		base_ring.append(base_pos - n * 0.010 + radial * (base_r * rib))
		mid_ring.append(base_pos + n * (height * 0.56) + radial * (base_r * 0.56 * rib))

	var apex := base_pos + n * height + u * (base_r * 0.10)
	var ref := base_pos - n * 0.04
	for k in sides:
		var nk := (k + 1) % sides
		_add_outward_quad(st, base_ring[k], mid_ring[k], mid_ring[nk], base_ring[nk],
			ref, col_rim, col_mid, col_mid, col_rim)
		_add_outward_tri(st, mid_ring[k], apex, mid_ring[nk], ref, col_mid, col_peak, col_mid)


static func _append_tidal_boulder(st: SurfaceTool, center: Vector3, rx: float, height: float,
		rz: float, bot_y: float, sides: int, phase: float) -> void:
	var col_moss := Color(0.20, 0.27, 0.19, 1.0)
	var col_barnacle_a := Color(0.76, 0.74, 0.66, 1.0)
	var col_barnacle_b := Color(0.42, 0.40, 0.35, 1.0)
	var col_mid_rock := Color(0.76, 0.63, 0.46, 1.0)
	var col_crest := Color(0.91, 0.82, 0.67, 1.0)

	# 5 stratified rings with wave-carved tidal undercut notch & overhanging rock ledge:
	# [y_val, rad_scale, tier_id]
	var ring_defs: Array[Array] = [
		[bot_y, 1.08, 0],
		[height * 0.20, 0.85, 1],
		[height * 0.48, 0.94, 2],
		[height * 0.74, 0.68, 3],
		[height * 0.91, 0.40, 4],
	]

	var rings: Array[Array] = []
	var cols: Array[Array] = []
	for ri in ring_defs.size():
		var y_val: float = float(ring_defs[ri][0])
		var r_sc: float = float(ring_defs[ri][1])
		var tier: int = int(ring_defs[ri][2])
		var pts: Array[Vector3] = []
		var rcols: Array[Color] = []
		for k in sides:
			var ang := float(k) / float(sides) * TAU + phase + float(ri) * 0.18
			var crag := 0.84 + 0.22 * sin(ang * 3.0 + phase) + 0.10 * cos(ang * 5.0 - float(ri))
			var px := center.x + cos(ang) * rx * r_sc * crag
			var pz := center.z + sin(ang) * rz * r_sc * crag
			var py := y_val + (0.06 * sin(ang * 2.0 + phase) if ri > 0 else 0.0)
			pts.append(Vector3(px, py, pz))
			var c := col_moss
			if tier == 1:
				c = col_barnacle_a if (k % 2 == 0) else col_barnacle_b
			elif tier == 2:
				var k_shade := 0.93 + 0.12 * float(k % 2)
				c = Color(
					clampf(col_mid_rock.r * k_shade, 0.0, 1.0),
					clampf(col_mid_rock.g * k_shade, 0.0, 1.0),
					clampf(col_mid_rock.b * k_shade, 0.0, 1.0),
					1.0)
			elif tier == 3:
				c = col_mid_rock.lerp(col_crest, 0.55)
			elif tier == 4:
				c = col_crest
			rcols.append(c)
		rings.append(pts)
		cols.append(rcols)

	var ref := center + Vector3(0.0, height * 0.30, 0.0)
	for ri in range(rings.size() - 1):
		var r0: Array = rings[ri]
		var r1: Array = rings[ri + 1]
		var c0: Array = cols[ri]
		var c1: Array = cols[ri + 1]
		for k in sides:
			var nk := (k + 1) % sides
			_add_outward_quad(st, r0[k], r1[k], r1[nk], r0[nk], ref, c0[k], c1[k], c1[nk], c0[nk])

	var apex := center + Vector3(rx * 0.08 * cos(phase), height, rz * 0.08 * sin(phase))
	var top_i := rings.size() - 1
	for k in sides:
		var nk := (k + 1) % sides
		_add_outward_tri(st, rings[top_i][k], apex, rings[top_i][nk], ref,
			cols[top_i][k], col_crest, cols[top_i][nk])


# ------------------------------------------------------------------ Mesh 7 & 8: Sculpted Fallback Cliff Buttresses

static func _build_fallback_buttress_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Tall craggy coastal cliff buttress jutting outward along -Z with deep back/bottom skirt
	# so ZERO floating edges ever appear on steep 45..80 deg cliffs!
	_append_crag_column(st, Vector3(0.0, 0.0, 0.20), 3.35, 3.10, -3.6, 10.6, 8, 0.28, -0.55)
	_append_crag_column(st, Vector3(-2.15, -0.5, 0.55), 2.15, 2.25, -3.4, 6.8, 6, 1.42, -0.35)
	_append_crag_column(st, Vector3( 2.05, -0.8, 0.35), 2.05, 2.15, -3.5, 6.1, 6, 2.75, -0.45)

	st.generate_normals()
	return st.commit()


static func _build_fallback_buttress_wide_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Wide stepped horizontal sedimentary cliff bench (~10.4 m wide) for medium/large islands.
	_append_crag_column(st, Vector3(0.0, 0.0, 0.35), 4.65, 3.20, -3.5, 5.9, 8, 0.62, -0.42)
	_append_crag_column(st, Vector3(-3.35, -0.4, 0.65), 2.85, 2.55, -3.4, 4.4, 6, 1.94, -0.30)
	_append_crag_column(st, Vector3( 3.25, -0.3, 0.55), 2.95, 2.65, -3.4, 4.7, 6, 3.18, -0.36)

	st.generate_normals()
	return st.commit()


static func _append_crag_column(st: SurfaceTool, center: Vector3, rx: float, rz: float,
		bot_y: float, top_y: float, sides: int, phase: float, z_jut: float) -> void:
	var col_crevice := Color(0.46, 0.41, 0.37, 1.0)
	var col_strata_a := Color(0.76, 0.67, 0.56, 1.0)
	var col_strata_b := Color(0.88, 0.80, 0.68, 1.0)
	var col_ledge := Color(0.96, 0.90, 0.79, 1.0)

	# 6 stepped geological strata rings with overhanging rock shelves & back taper into cliff (+Z).
	var h_span := top_y - bot_y
	var ring_defs: Array[Array] = [
		[0.00, 1.18, 0.10, col_crevice],
		[0.24, 1.05, 0.45, col_strata_a],
		[0.44, 1.12, 0.85, col_strata_b],  # Jutting lower overhanging rock shelf!
		[0.64, 0.86, 0.60, col_strata_a],
		[0.82, 0.90, 0.45, col_strata_b],  # Upper crag cornice ledge!
		[0.95, 0.54, 0.20, col_ledge],
	]

	var rings: Array[Array] = []
	var rcols: Array[Array] = []
	for ri in ring_defs.size():
		var f_y: float = float(ring_defs[ri][0])
		var r_sc: float = float(ring_defs[ri][1])
		var jut_w: float = float(ring_defs[ri][2])
		var base_c: Color = ring_defs[ri][3] as Color
		var y_base := bot_y + h_span * f_y
		var pts: Array[Vector3] = []
		var cols: Array[Color] = []

		for k in sides:
			var ang := float(k) / float(sides) * TAU + phase
			var flute := 0.82 + 0.24 * sin(ang * 3.0 + phase) + 0.12 * cos(ang * 2.0 - float(ri) * 0.9)
			var vx := center.x + cos(ang) * rx * r_sc * flute
			var vz := center.z + sin(ang) * rz * r_sc * flute + z_jut * jut_w
			# Slant the crown gently backward into the mountain (+Z higher) so top integrates cleanly.
			var slant_y := clampf(sin(ang), -1.0, 1.0) * (0.48 * f_y)
			var vy := center.y + y_base + slant_y + 0.22 * sin(ang * 4.0 + float(ri))
			pts.append(Vector3(vx, vy, vz))

			# Crevice shading on fluted inward facets + sunlit pop on outward -Z cliff ribs.
			var shade := clampf(0.84 + 0.22 * flute - 0.10 * sin(ang), 0.62, 1.08)
			cols.append(Color(
				clampf(base_c.r * shade, 0.0, 1.0),
				clampf(base_c.g * shade, 0.0, 1.0),
				clampf(base_c.b * shade, 0.0, 1.0),
				1.0))
		rings.append(pts)
		rcols.append(cols)

	var ref := center + Vector3(0.0, (bot_y + top_y) * 0.45, 0.0)
	for ri in range(rings.size() - 1):
		var r0: Array = rings[ri]
		var r1: Array = rings[ri + 1]
		var c0: Array = rcols[ri]
		var c1: Array = rcols[ri + 1]
		for k in sides:
			var nk := (k + 1) % sides
			_add_outward_quad(st, r0[k], r1[k], r1[nk], r0[nk], ref, c0[k], c1[k], c1[nk], c0[nk])

	var apex := center + Vector3(rx * 0.06 * cos(phase), top_y, rz * 0.14)
	var top_i := rings.size() - 1
	for k in sides:
		var nk := (k + 1) % sides
		_add_outward_tri(st, rings[top_i][k], apex, rings[top_i][nk], ref,
			rcols[top_i][k], col_ledge, rcols[top_i][nk])


# ------------------------------------------------------------------ Mesh 9: Sculpted Coastal Trail Flagstone / Curb Slab

static func _build_stepping_stone_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Chunky 8-sided beveled weathered coastal flagstone (~40 tris): sunlit flat walkable top,
	# ~0.80x warm-earth beveled side rim, and recessed -0.16 m buried bottom skirt so it pops
	# cleanly at on-foot eye height without shadow maps or floating edges on slopes.
	const SIDES := 8
	const RX := 0.56
	const RZ := 0.44

	var col_skirt := Color(0.45, 0.40, 0.35, 1.0)
	var col_side := Color(0.74, 0.69, 0.62, 1.0)
	var col_bevel := Color(0.84, 0.80, 0.74, 1.0)
	var col_top_edge := Color(0.98, 0.96, 0.92, 1.0)
	var col_top := Color(1.00, 0.99, 0.95, 1.0)

	var bot_ring: Array[Vector3] = []
	var mid_ring: Array[Vector3] = []
	var top_ring: Array[Vector3] = []
	var side_cols: Array[Color] = []
	var bevel_cols: Array[Color] = []
	var top_cols: Array[Color] = []

	for k in SIDES:
		var ang := float(k) / float(SIDES) * TAU + 0.22
		# Irregular hand-hewn flagstone silhouette (no mechanical cylinder/box symmetry).
		var facet := 0.88 + 0.13 * sin(ang * 2.0 + 0.65) + 0.08 * cos(ang * 3.0 - 0.45)
		var px := cos(ang) * RX * facet
		var pz := sin(ang) * RZ * facet
		var top_jit := 0.008 * sin(ang * 3.0 + 0.9)

		bot_ring.append(Vector3(px * 0.90, -0.16, pz * 0.90))
		mid_ring.append(Vector3(px, 0.045 + top_jit * 0.5, pz))
		top_ring.append(Vector3(px * 0.78, 0.115 + top_jit, pz * 0.78))

		var shade := clampf(0.93 + 0.08 * sin(ang * 2.0 + 1.1), 0.86, 1.04)
		side_cols.append(Color(
			clampf(col_side.r * shade, 0.0, 1.0),
			clampf(col_side.g * shade, 0.0, 1.0),
			clampf(col_side.b * shade, 0.0, 1.0),
			1.0))
		var bevel_k := 0.94 + 0.06 * shade
		bevel_cols.append(Color(
			clampf(col_bevel.r * bevel_k, 0.0, 1.0),
			clampf(col_bevel.g * bevel_k, 0.0, 1.0),
			clampf(col_bevel.b * bevel_k, 0.0, 1.0),
			1.0))
		var top_k := 0.97 + 0.03 * shade
		top_cols.append(Color(
			clampf(col_top_edge.r * top_k, 0.0, 1.0),
			clampf(col_top_edge.g * top_k, 0.0, 1.0),
			clampf(col_top_edge.b * top_k, 0.0, 1.0),
			1.0))

	var top_center := Vector3(0.0, 0.125, 0.0)
	var ref_center := Vector3(0.0, -0.04, 0.0)

	# 8 * 2 (skirt -> shoulder) + 8 * 2 (shoulder -> top bevel) + 8 (flat top cap) = 40 tris.
	for k in SIDES:
		var nk := (k + 1) % SIDES
		_add_outward_quad(st, bot_ring[k], mid_ring[k], mid_ring[nk], bot_ring[nk], ref_center,
			col_skirt, side_cols[k], side_cols[nk], col_skirt)
		_add_outward_quad(st, mid_ring[k], top_ring[k], top_ring[nk], mid_ring[nk], ref_center,
			side_cols[k], bevel_cols[k], bevel_cols[nk], side_cols[nk])
		_add_outward_tri(st, top_ring[k], top_center, top_ring[nk], ref_center,
			top_cols[k], col_top, top_cols[nk])

	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ Mesh 10: Sculpted Swallowtail Tropical Butterfly

static func _build_butterfly_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 24-tri sculpted swallowtail butterfly facing local -Z:
	# tapered 3D thorax/abdomen body (8 tris) + 4 angled faceted wings (16 tris) with
	# velvety dark wingtips & luminous inner wing panels multiplied by per-instance species tint.
	var col_body := Color(0.14, 0.12, 0.15, 1.0)
	var col_body_hi := Color(0.24, 0.21, 0.25, 1.0)
	var col_root := Color(0.24, 0.22, 0.26, 1.0)
	var col_panel_hi := Color(1.00, 0.99, 0.96, 1.0)
	var col_panel_lo := Color(0.94, 0.93, 0.89, 1.0)
	var col_margin := Color(0.20, 0.18, 0.22, 1.0)
	var col_tip := Color(0.13, 0.12, 0.16, 1.0)

	# 1. Tapered 3D thorax/body (8 tris).
	var head := Vector3(0.0, 0.012, -0.105)
	var tail := Vector3(0.0, -0.004, 0.115)
	var body_ring: Array[Vector3] = [
		Vector3(0.0, 0.024, -0.020),
		Vector3(0.018, 0.004, -0.020),
		Vector3(0.0, -0.014, -0.020),
		Vector3(-0.018, 0.004, -0.020),
	]
	var body_ref := Vector3(0.0, 0.004, 0.0)
	for k in 4:
		var nk := (k + 1) % 4
		var ck := col_body_hi if k == 0 else col_body
		var cnk := col_body_hi if nk == 0 else col_body
		_add_outward_tri(st, head, body_ring[k], body_ring[nk], body_ref, col_body, ck, cnk)
		_add_outward_tri(st, tail, body_ring[nk], body_ring[k], body_ref, col_body, cnk, ck)

	# 2. Left & right swept forewings + swallowtail hindwings (16 tris, upward +Y normals).
	var wing_ref := Vector3(0.0, -1.0, 0.0)
	for side: float in [-1.0, 1.0]:
		# Swept angled forewing (4 tris).
		var fw_rf := Vector3(side * 0.014, 0.010, -0.055)
		var fw_rr := Vector3(side * 0.014, 0.006, 0.012)
		var fw_mf := Vector3(side * 0.115, 0.052, -0.052)
		var fw_mr := Vector3(side * 0.105, 0.042, 0.018)
		var fw_tip := Vector3(side * 0.215, 0.092, -0.095)
		var fw_out := Vector3(side * 0.188, 0.068, 0.010)
		_add_outward_tri(st, fw_rf, fw_mf, fw_rr, wing_ref, col_root, col_panel_hi, col_root)
		_add_outward_tri(st, fw_rr, fw_mf, fw_mr, wing_ref, col_root, col_panel_hi, col_panel_lo)
		_add_outward_tri(st, fw_mf, fw_tip, fw_out, wing_ref, col_panel_hi, col_tip, col_margin)
		_add_outward_tri(st, fw_mf, fw_out, fw_mr, wing_ref, col_panel_hi, col_margin, col_panel_lo)

		# Swallowtail hindwing with pointed streamer tip (4 tris).
		var hw_rf := Vector3(side * 0.013, 0.006, 0.006)
		var hw_rr := Vector3(side * 0.010, 0.002, 0.072)
		var hw_mo := Vector3(side * 0.128, 0.036, 0.038)
		var hw_mr := Vector3(side * 0.072, 0.020, 0.096)
		var hw_rim := Vector3(side * 0.146, 0.030, 0.088)
		var hw_tail := Vector3(side * 0.086, 0.014, 0.168)
		_add_outward_tri(st, hw_rf, hw_mo, hw_rr, wing_ref, col_root, col_panel_hi, col_root)
		_add_outward_tri(st, hw_rr, hw_mo, hw_mr, wing_ref, col_root, col_panel_hi, col_panel_lo)
		_add_outward_tri(st, hw_mo, hw_rim, hw_mr, wing_ref, col_panel_hi, col_margin, col_panel_lo)
		_add_outward_tri(st, hw_mr, hw_rim, hw_tail, wing_ref, col_panel_lo, col_margin, col_tip)

	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ Mesh 11: Sculpted Coastal Tidepool Crab

static func _build_crab_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 36-tri sculpted coastal tidepool crab facing local -Z (scuttles sideways along +-X):
	#   1. Beveled hexagonal carapace (16 tris: 12 bevel side tris + 4 domed top cap tris)
	#   2. Twin raised curved pincer claws in front (6 tris: 3 per claw)
	#   3. 6 splayed articulated walking legs (12 tris: 2 per leg — raised femur + grounded tarsus)
	#   4. Twin tiny dark upright eye-stalks on front rim (2 tris)
	var col_rim := Color(0.74, 0.70, 0.66, 1.0)
	var col_top_front := Color(0.95, 0.93, 0.89, 1.0)
	var col_top := Color(1.00, 0.98, 0.94, 1.0)
	var col_top_rear := Color(0.90, 0.87, 0.82, 1.0)
	var col_arm := Color(0.84, 0.80, 0.75, 1.0)
	var col_claw := Color(0.96, 0.92, 0.86, 1.0)
	var col_claw_hi := Color(1.00, 0.97, 0.91, 1.0)
	var col_claw_tip := Color(1.00, 0.98, 0.93, 1.0)
	var col_leg_hip := Color(0.84, 0.80, 0.75, 1.0)
	var col_leg_knee := Color(0.94, 0.90, 0.84, 1.0)
	var col_leg_foot := Color(0.56, 0.50, 0.46, 1.0)
	var col_eye_stalk := Color(0.46, 0.40, 0.36, 1.0)
	var col_eye_tip := Color(0.08, 0.08, 0.10, 1.0)

	# 1. Beveled hexagonal carapace (16 tris).
	var hex_xz: Array[Vector2] = [
		Vector2( 0.092, -0.108),  # 0: front-right
		Vector2( 0.158, -0.008),  # 1: right lateral spine
		Vector2( 0.098,  0.112),  # 2: back-right
		Vector2(-0.098,  0.112),  # 3: back-left
		Vector2(-0.158, -0.008),  # 4: left lateral spine
		Vector2(-0.092, -0.108),  # 5: front-left
	]
	var bot_ring: Array[Vector3] = []
	var top_ring: Array[Vector3] = []
	var top_cols: Array[Color] = []
	for k in 6:
		var p: Vector2 = hex_xz[k]
		var is_spine := (k == 1 or k == 4)
		var is_front := (k == 0 or k == 5)
		bot_ring.append(Vector3(p.x, 0.042, p.y))
		top_ring.append(Vector3(p.x * 0.72, 0.128 if is_spine else 0.118, p.y * 0.72))
		top_cols.append(col_top if is_spine else (col_top_front if is_front else col_top_rear))

	var ref_body := Vector3(0.0, 0.062, 0.0)
	for k in 6:
		var nk := (k + 1) % 6
		_add_outward_quad(st, bot_ring[k], top_ring[k], top_ring[nk], bot_ring[nk], ref_body,
			col_rim, top_cols[k], top_cols[nk], col_rim)

	# Symmetric 4-tri domed hexagonal top cap split along the transverse lateral ridge (v4 -> v1).
	_add_outward_tri(st, top_ring[5], top_ring[0], top_ring[1], ref_body,
		top_cols[5], top_cols[0], top_cols[1])
	_add_outward_tri(st, top_ring[5], top_ring[1], top_ring[4], ref_body,
		top_cols[5], top_cols[1], top_cols[4])
	_add_outward_tri(st, top_ring[4], top_ring[1], top_ring[2], ref_body,
		top_cols[4], top_cols[1], top_cols[2])
	_add_outward_tri(st, top_ring[4], top_ring[2], top_ring[3], ref_body,
		top_cols[4], top_cols[2], top_cols[3])

	# 2. Twin raised curved pincer claws in front (6 tris).
	var claw_ref := Vector3(0.0, -0.50, 0.12)
	for side: float in [-1.0, 1.0]:
		var sh_in := Vector3(side * 0.086, 0.072, -0.086)
		var sh_out := Vector3(side * 0.128, 0.056, -0.052)
		var elbow := Vector3(side * 0.208, 0.112, -0.172)
		var palm_out := Vector3(side * 0.228, 0.158, -0.238)
		var tip_up := Vector3(side * 0.095, 0.178, -0.268)
		var wrist_in := Vector3(side * 0.166, 0.104, -0.175)
		var tip_lo := Vector3(side * 0.082, 0.122, -0.244)

		_add_outward_tri(st, sh_in, sh_out, elbow, claw_ref, col_rim, col_arm, col_claw)
		_add_outward_tri(st, elbow, palm_out, tip_up, claw_ref, col_claw, col_claw_hi, col_claw_tip)
		_add_outward_tri(st, elbow, wrist_in, tip_lo, claw_ref, col_claw, col_rim, col_claw_tip)

	# 3. 6 splayed articulated walking legs (12 tris: 3 left, 3 right).
	# [hip_x, hip_z, knee_x, knee_y, knee_z, foot_x, foot_z]
	var leg_specs: Array[Array] = [
		[0.132, -0.042, 0.235, 0.095, -0.085, 0.285, -0.115],
		[0.146,  0.014, 0.252, 0.098,  0.022, 0.305,  0.032],
		[0.122,  0.070, 0.228, 0.088,  0.126, 0.275,  0.165],
	]
	var leg_up_ref := Vector3(0.0, -0.60, 0.0)
	for side: float in [-1.0, 1.0]:
		var leg_side_ref := Vector3(-side * 0.20, -0.10, 0.0)
		for lspec in leg_specs:
			var hx: float = float(lspec[0])
			var hz: float = float(lspec[1])
			var kx: float = float(lspec[2])
			var ky: float = float(lspec[3])
			var kz: float = float(lspec[4])
			var fx: float = float(lspec[5])
			var fz: float = float(lspec[6])

			var hip_a := Vector3(side * hx, 0.056, hz - 0.018)
			var hip_b := Vector3(side * hx, 0.056, hz + 0.018)
			var knee_top := Vector3(side * kx, ky, kz)
			var knee_bot := Vector3(side * (kx - 0.024), ky - 0.028, kz)
			var foot := Vector3(side * fx, 0.002, fz)

			_add_outward_tri(st, hip_a, hip_b, knee_top, leg_up_ref, col_leg_hip, col_leg_hip, col_leg_knee)
			_add_outward_tri(st, knee_top, knee_bot, foot, leg_side_ref, col_leg_knee, col_leg_hip, col_leg_foot)

	# 4. Tiny dark upright eye-stalks on front carapace edge (2 tris).
	var eye_ref := Vector3(0.0, 0.08, 0.12)
	for side: float in [-1.0, 1.0]:
		var eb_in := Vector3(side * 0.028, 0.108, -0.096)
		var eb_out := Vector3(side * 0.052, 0.106, -0.092)
		var eye_tip := Vector3(side * 0.044, 0.156, -0.112)
		_add_outward_tri(st, eb_in, eb_out, eye_tip, eye_ref, col_eye_stalk, col_eye_stalk, col_eye_tip)

	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ SurfaceTool geometry primitives

static func _append_anchored_mound(st: SurfaceTool, center: Vector3, rx: float, ry: float,
		rz: float, bot_y: float, segs: int, col_bot: Color, col_top: Color, uv2: Vector2) -> void:
	var bot_ring: Array[Vector3] = []
	for k in segs:
		var ang := float(k) / float(segs) * TAU
		bot_ring.append(center + Vector3(cos(ang) * rx, bot_y, sin(ang) * rz))
	var crown := center + Vector3(0.0, ry, 0.0)
	var ref := center + Vector3(0.0, (bot_y + ry) * 0.35, 0.0)
	for k in segs:
		var nk := (k + 1) % segs
		var a := bot_ring[k]
		var b := crown
		var c := bot_ring[nk]
		var n := (c - a).cross(b - a)
		if n.length_squared() < 1e-10:
			continue
		var centroid := (a + b + c) / 3.0
		if n.dot(centroid - ref) < 0.0:
			_add_foliage_tri(st, a, c, b, col_bot, col_bot, col_top,
				Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(0.5, 0.0), uv2, uv2, uv2)
		else:
			_add_foliage_tri(st, a, b, c, col_bot, col_top, col_bot,
				Vector2(0.0, 1.0), Vector2(0.5, 0.0), Vector2(1.0, 1.0), uv2, uv2, uv2)


static func _append_tapered_limb_uv2(st: SurfaceTool, p0: Vector3, p1: Vector3, r0: float,
		r1: float, sides: int, col0: Color, col1: Color, uv2_0: Vector2, uv2_1: Vector2) -> void:
	var axis := p1 - p0
	var seg_len := axis.length()
	if seg_len < 0.001:
		return
	var dir := axis / seg_len
	var ref := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
	var u := dir.cross(ref).normalized()
	var v := dir.cross(u).normalized()

	var ring0: Array[Vector3] = []
	var ring1: Array[Vector3] = []
	for i in sides:
		var ang := float(i) / float(sides) * TAU
		var radial := u * cos(ang) + v * sin(ang)
		ring0.append(p0 + radial * r0)
		ring1.append(p1 + radial * r1)

	var mid_ctr := (p0 + p1) * 0.5
	for i in sides:
		var ni := (i + 1) % sides
		_add_outward_quad_uv2(st, ring0[i], ring1[i], ring1[ni], ring0[ni], mid_ctr,
			col0, col1, col1, col0, uv2_0, uv2_1, uv2_1, uv2_0)


static func _append_tapered_limb_solid(st: SurfaceTool, p0: Vector3, p1: Vector3, r0: float,
		r1: float, sides: int, col0: Color, col1: Color, cap_tip: bool, cap_col: Color) -> void:
	var axis := p1 - p0
	var seg_len := axis.length()
	if seg_len < 0.001:
		return
	var dir := axis / seg_len
	var ref := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
	var u := dir.cross(ref).normalized()
	var v := dir.cross(u).normalized()

	var ring0: Array[Vector3] = []
	var ring1: Array[Vector3] = []
	for i in sides:
		var ang := float(i) / float(sides) * TAU
		var radial := u * cos(ang) + v * sin(ang)
		ring0.append(p0 + radial * r0)
		ring1.append(p1 + radial * r1)

	var mid_ctr := (p0 + p1) * 0.5
	for i in sides:
		var ni := (i + 1) % sides
		_add_outward_quad(st, ring0[i], ring1[i], ring1[ni], ring0[ni], mid_ctr, col0, col1, col1, col0)

	if cap_tip:
		var apex := p1 + dir * (r1 * 1.15)
		var tip_ref := p1 - dir * (r1 * 0.5)
		for i in sides:
			var ni := (i + 1) % sides
			_add_outward_tri(st, ring1[i], apex, ring1[ni], tip_ref, col1, cap_col, col1)


static func _add_outward_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_add_outward_tri(st, a, b, c, ref_center, ca, cb, cc)
	_add_outward_tri(st, a, c, d, ref_center, ca, cc, cd)


static func _add_outward_quad_uv2(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color, cd: Color,
		u2a: Vector2, u2b: Vector2, u2c: Vector2, u2d: Vector2) -> void:
	_add_outward_tri_uv2(st, a, b, c, ref_center, ca, cb, cc, u2a, u2b, u2c)
	_add_outward_tri_uv2(st, a, c, d, ref_center, ca, cc, cd, u2a, u2c, u2d)


static func _add_outward_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	_add_outward_tri_uv2(st, a, b, c, ref_center, ca, cb, cc, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)


static func _add_outward_tri_uv2(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color,
		u2a: Vector2, u2b: Vector2, u2c: Vector2) -> void:
	# Godot front-face winding is CW -> outward normal is (c - a) x (b - a).
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-10:
		return
	var centroid := (a + b + c) / 3.0
	if n.dot(centroid - ref_center) < 0.0:
		var tmp_v := b
		b = c
		c = tmp_v
		var tmp_c := cb
		cb = cc
		cc = tmp_c
		var tmp_u := u2b
		u2b = u2c
		u2c = tmp_u
	_add_foliage_tri(st, a, b, c, ca, cb, cc,
		Vector2(0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, 0.5), u2a, u2b, u2c)


static func _add_foliage_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color, uva: Vector2, uvb: Vector2, uvc: Vector2,
		uv2a: Vector2, uv2b: Vector2, uv2c: Vector2) -> void:
	if (c - a).cross(b - a).length_squared() < 1e-10:
		return
	st.set_smooth_group(-1)
	st.set_color(ca)
	st.set_uv(uva)
	st.set_uv2(uv2a)
	st.add_vertex(a)

	st.set_smooth_group(-1)
	st.set_color(cb)
	st.set_uv(uvb)
	st.set_uv2(uv2b)
	st.add_vertex(b)

	st.set_smooth_group(-1)
	st.set_color(cc)
	st.set_uv(uvc)
	st.set_uv2(uv2c)
	st.add_vertex(c)
