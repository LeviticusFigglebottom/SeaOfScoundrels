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
## `IslandLandmarks` consumes `get_trail_marker_spots()` to line trailheads,
## forks, and scenic bends with `trail_lantern_post.glb` & `stone_cairn_marker.glb`,
## and `sample_trail_dressing()` provides grounded stepping-stone & curb-stone
## transforms flanking every walkable footpath.

const TRAIL_MIN_Y := 0.72
const TRAIL_FULL_Y := 1.45
const TRAIL_MIN_NY := 0.64
const TRAIL_FULL_NY := 0.78
const TRAIL_PEAK_STRENGTH := 0.96
const TRAIL_OUTER_SCALE := 1.40
## Inner 58% of painted trail width holds a solid worn footpath core (`alpha = 0.04..0.12`,
## `1.0 - COLOR.a = 0.88..0.96`), transitioning smoothly over the outer 42% shoulder to `1.0`.
const TRAIL_CORE_RATIO := 0.58
const TRAIL_CORE_EDGE_STRENGTH := 0.916
const TRAIL_MAX_WOBBLE := 0.58

const MARKER_MIN_Y := 1.05
const MARKER_MAX_Y := 38.0
const MARKER_MIN_NY := 0.74
const MARKER_OFFSET_MIN := 2.6
const MARKER_OFFSET_MAX := 5.2

const STEPPING_STONE_MIN_Y := 0.85
const STEPPING_STONE_MIN_NY := 0.72
const STEPPING_STONE_SPACING_MIN := 3.0
const STEPPING_STONE_SPACING_MAX := 4.6

const CURB_STONE_MIN_Y := 0.85
const CURB_STONE_MIN_NY := 0.68
const CURB_STONE_OFFSET_MIN := 0.30
const CURB_STONE_OFFSET_MAX := 0.90


## Return 1 to 4 organic curved polylines in canonical `(u, v)` coordinates
## tailored to the island's archetype topography and optional `island_id`.
## Every primary spine begins cleanly at the landing beach or pier head (`h ~ 1.0..1.8 m`)
## and routes continuously along walkable shoulders (`h >= 0.75 m`) to signature landmarks.
static func get_trail_polylines(arch: StringName, radius: float,
		island_id: String = "") -> Array[PackedVector2Array]:
	var s := maxf(radius / 60.0, 0.35)
	var out: Array[PackedVector2Array] = []

	match arch:
		&"outpost", &"outpost_harbour":
			if island_id == "barnacle_haven":
				# Barnacle Haven: dry pier head -> central harbour plaza -> gentle south-east
				# shoulder skirting Copper Beacon -> east promontory seawall & signal brazier lookout.
				out.append(_catmull_rom_polyline([
					Vector2(0.0, -20.5),
					Vector2(3.5, -17.0),
					Vector2(11.5, -18.8),
					Vector2(21.0, -22.8),
					Vector2(31.0, -23.6),
					Vector2(38.5, -20.0),
					Vector2(40.0, -12.0),
					Vector2(38.5, -4.5),
				], 3))
				# West wharf promenade past Driftwood Tavern & Harbour Warehouse to Bluff Catwalk Pier.
				out.append(_catmull_rom_polyline([
					Vector2(-0.5, -18.5),
					Vector2(-6.5, -14.8),
					Vector2(-13.8, -13.6),
					Vector2(-20.5, -14.6),
					Vector2(-27.2, -15.8),
					Vector2(-33.5, -18.6),
					Vector2(-36.5, -24.0),
				], 3))
				# Sunlit upper terrace overlook spur curving smoothly behind Copper Beacon.
				out.append(_catmull_rom_polyline([
					Vector2(39.5, -11.0),
					Vector2(37.5, -2.0),
					Vector2(31.0, 3.5),
					Vector2(23.5, 7.0),
					Vector2(15.5, 11.0),
				], 3))
			else:
				# Port Scoundrel (default): dry pier head -> central harbour plaza -> gentle SE
				# switchback skirting Harbour Beacon -> sunlit upper village terrace overlook.
				out.append(_catmull_rom_polyline([
					Vector2(0.0, -20.5),
					Vector2(3.2, -16.6),
					Vector2(10.2, -16.8),
					Vector2(19.8, -21.2),
					Vector2(31.5, -20.5),
					Vector2(38.5, -11.5),
					Vector2(36.8, 0.5),
					Vector2(27.0, 8.2),
					Vector2(14.5, 10.5),
				], 3))
				# West wharf trail past Salty Lantern Tavern & Harbour Warehouse to Headland Watchtower.
				out.append(_catmull_rom_polyline([
					Vector2(-0.6, -18.2),
					Vector2(-6.8, -14.5),
					Vector2(-13.5, -13.5),
					Vector2(-20.0, -12.5),
					Vector2(-26.2, -10.5),
					Vector2(-28.8, -16.8),
					Vector2(-29.5, -25.5),
				], 3))
				# East harbour promontory spur leading to Seawall Bastion & Signal Brazier headland.
				out.append(_catmull_rom_polyline([
					Vector2(20.5, -21.2),
					Vector2(29.0, -23.8),
					Vector2(38.5, -26.5),
				], 3))

		&"grand_outpost":
			# Galleon's Reach (UNSCALED terrain frame): dry grand wharf head -> harbour plaza ->
			# gentle eastern switchback corridor threading the Beacon saddle onto upper `town_terrace`
			# past the overlook ruin pillars & aqueduct vista (clear of JungleAltar_Grove!).
			out.append(_catmull_rom_polyline([
				Vector2(0.0, -20.5),
				Vector2(4.5, -18.2),
				Vector2(12.5, -18.5),
				Vector2(21.0, -19.8),
				Vector2(27.0, -18.0),
				Vector2(31.5, -12.5),
				Vector2(32.5, -3.5),
				Vector2(27.5, 7.0),
				Vector2(15.5, 16.0),
				Vector2(-2.0, 26.5),
				Vector2(-11.0, 33.5),
				Vector2(2.0, 39.5),
				Vector2(18.0, 37.5),
			], 3))
			# East harbour & temple-stairway spur linking the eastern saddle -> TempleStairway_Overlook
			# & curving gently around the east highland shoulder to OverlookRuinPillar_2.
			out.append(_catmull_rom_polyline([
				Vector2(32.5, -8.0),
				Vector2(39.0, -5.0),
				Vector2(45.5, 5.5),
			], 3))
			# West fjord promenade weaving past Tavern & Watchtower 0 -> CliffCatwalkPier_West
			# -> HeadlandWatchtower_2 & outer SeawallBastion_2.
			out.append(_catmull_rom_polyline([
				Vector2(-1.0, -18.5),
				Vector2(-10.5, -17.2),
				Vector2(-21.5, -21.5),
				Vector2(-30.5, -28.0),
				Vector2(-36.8, -36.8),
				Vector2(-43.8, -46.2),
				Vector2(-50.0, -57.0),
				Vector2(-49.0, -68.0),
			], 3))

		&"treasure_peak", &"treasure_cove":
			# Cutlass Cay: Golden Cove landing beach -> past campfire & dig clearings ->
			# gentle S-curve up the palm valley to the twin-spire saddle overlook.
			out.append(_catmull_rom_polyline([
				Vector2(1.0 * s, -52.5 * s),
				Vector2(3.8 * s, -43.5 * s),
				Vector2(-0.8 * s, -33.5 * s),
				Vector2(3.4 * s, -22.0 * s),
				Vector2(-2.0 * s, -11.5 * s),
				Vector2(-6.0 * s, -2.5 * s),
			], 3))
			# Eastern palm terrace scenic spur (north of SmugglerHoard_Cove).
			out.append(_catmull_rom_polyline([
				Vector2(3.4 * s, -22.0 * s),
				Vector2(12.2 * s, -21.5 * s),
				Vector2(20.5 * s, -19.0 * s),
				Vector2(28.0 * s, -15.0 * s),
			], 3))
			# Western cove beach spur linking west dig clearing & camp beach overlook.
			out.append(_catmull_rom_polyline([
				Vector2(1.2 * s, -48.5 * s),
				Vector2(-9.5 * s, -47.0 * s),
				Vector2(-19.5 * s, -41.5 * s),
				Vector2(-26.5 * s, -29.0 * s),
			], 3))

		&"twin_spires":
			# Emerald Spire: landing cove beach -> curving cleanly east of PirateCamp ->
			# passing through `RuinAqueduct_CanyonGate` -> crossing `CanyonTimberBridge` ->
			# arriving at `TempleStairway_Canyon` facing the thundering waterfall!
			out.append(_catmull_rom_polyline([
				Vector2(0.0, -54.5 * s),
				Vector2(3.2 * s, -44.0 * s),
				Vector2(1.2 * s, -34.0 * s),
				Vector2(2.4 * s, -24.0 * s),
				Vector2(-0.8 * s, -14.5 * s),
				Vector2(0.0, -6.0 * s),
				Vector2(0.6 * s, 2.2 * s),
				Vector2(0.0, 8.0 * s),
			], 3))
			# Closed East Cove scenic beach & dig-clearing loop rejoining the canyon spine cleanly.
			out.append(_catmull_rom_polyline([
				Vector2(2.6 * s, -47.0 * s),
				Vector2(12.0 * s, -48.5 * s),
				Vector2(23.0 * s, -44.5 * s),
				Vector2(28.0 * s, -37.5 * s),
				Vector2(20.5 * s, -32.8 * s),
				Vector2(10.5 * s, -31.5 * s),
				Vector2(1.5 * s, -33.2 * s),
			], 3))
			# West Cove shoreline trail linking landing beach past west dig clearing toward PirateCamp.
			out.append(_catmull_rom_polyline([
				Vector2(0.0, -52.5 * s),
				Vector2(-10.5 * s, -50.0 * s),
				Vector2(-20.5 * s, -45.5 * s),
				Vector2(-28.0 * s, -39.0 * s),
			], 3))

		&"crescent_lagoon":
			# Crescent Atoll: continuous full-ring lagoon rim trail connecting the West Horn
			# landing beach -> inner turquoise lagoon shore -> back highland vista -> East Horn
			# past the reef shipwreck & pirate camp -> East Horn landing beach!
			out.append(_catmull_rom_polyline([
				Vector2(-25.5 * s, -51.0 * s),
				Vector2(-26.8 * s, -34.0 * s),
				Vector2(-23.0 * s, -16.0 * s),
				Vector2(-20.2 * s, -1.0 * s),
				Vector2(-19.2 * s, 11.5 * s),
				Vector2(-9.5 * s, 17.0 * s),
				Vector2(6.0 * s, 17.0 * s),
				Vector2(21.0 * s, 14.8 * s),
				Vector2(30.5 * s, 3.0 * s),
				Vector2(32.5 * s, -15.0 * s),
				Vector2(31.8 * s, -32.0 * s),
				Vector2(25.5 * s, -49.5 * s),
			], 3))
			# Scenic outer eastern reef overlook spur framing `ImpaledShipwreckBow_Reef`.
			out.append(_catmull_rom_polyline([
				Vector2(32.5 * s, -16.0 * s),
				Vector2(39.0 * s, -13.0 * s),
				Vector2(41.5 * s, -3.5 * s),
				Vector2(37.0 * s, 5.5 * s),
			], 3))
			# Scenic western coral-horn dune spur linking the western beach verge & message bottle shore.
			out.append(_catmull_rom_polyline([
				Vector2(-26.8 * s, -34.0 * s),
				Vector2(-38.0 * s, -30.5 * s),
				Vector2(-44.0 * s, -21.5 * s),
				Vector2(-43.5 * s, -11.5 * s),
			], 3))

		&"sea_arch":
			# Gull's Arch: tide cove landing beneath `CoastalSeaArch_Main` -> winding up onto
			# the walkable western headland bluff terrace overlooking Tern Tide Bay & PirateCamp.
			out.append(_catmull_rom_polyline([
				Vector2(0.0, -28.0 * s),
				Vector2(-1.2 * s, -19.5 * s),
				Vector2(-9.5 * s, -17.5 * s),
				Vector2(-17.5 * s, -22.0 * s),
				Vector2(-23.5 * s, -29.5 * s),
				Vector2(-22.5 * s, -40.5 * s),
			], 3))
			# Eastern headland bluff shelf overlooking Tern Tide Bay & `CoastalSeaArch_Outer`.
			out.append(_catmull_rom_polyline([
				Vector2(-0.6 * s, -19.5 * s),
				Vector2(8.8 * s, -18.0 * s),
				Vector2(17.5 * s, -20.5 * s),
				Vector2(25.5 * s, -26.0 * s),
				Vector2(31.0 * s, -31.5 * s),
			], 3))

		&"fort_rock":
			# Ironwatch Fort: Powder Cove landing beach -> wide cobbled assault ramp straight
			# up to `FortBastion` gateway.
			out.append(_catmull_rom_polyline([
				Vector2(0.0, -45.0 * s),
				Vector2(0.6 * s, -34.0 * s),
				Vector2(-0.5 * s, -22.5 * s),
				Vector2(0.0, -9.8 * s),
			], 3))
			# Bastion mesa flanking patrol terrace linking west & east watchtower approaches cleanly
			# inside the level plateau crown (`n.y >= 0.84`).
			out.append(_catmull_rom_polyline([
				Vector2(-15.5 * s, -6.8 * s),
				Vector2(-9.5 * s, -9.8 * s),
				Vector2(0.0, -10.4 * s),
				Vector2(9.5 * s, -9.8 * s),
				Vector2(15.5 * s, -6.8 * s),
			], 3))
			# Powder Cove coastal beach promenade linking BeachCampfire & landing cove flanks.
			out.append(_catmull_rom_polyline([
				Vector2(-20.0 * s, -41.0 * s),
				Vector2(-9.5 * s, -41.5 * s),
				Vector2(0.0, -42.5 * s),
				Vector2(10.5 * s, -41.5 * s),
				Vector2(19.5 * s, -37.5 * s),
			], 3))

		&"grand_citadel":
			# Sovereign's Bastion (UNSCALED terrain frame): grand cobbled highway from the
			# golden landing beach -> dig clearings -> sweeping graded ramp up to `FortBastion`!
			out.append(_catmull_rom_polyline([
				Vector2(0.0, -153.0),
				Vector2(2.5, -128.0),
				Vector2(-1.5, -102.0),
				Vector2(1.8, -74.0),
				Vector2(-1.6, -48.0),
				Vector2(1.2, -24.0),
				Vector2(0.0, 2.0),
			], 3))
			# Western jungle temple & timber bridge branch crossing `CitadelTimberBridge` (-42, -14)
			# right to the foot of `TempleStairway_West` (-54, -14), then contouring smoothly onto
			# the western seawall & lookout ridge!
			out.append(_catmull_rom_polyline([
				Vector2(-1.6, -48.0),
				Vector2(-15.0, -42.0),
				Vector2(-30.0, -28.0),
				Vector2(-42.0, -14.0),
				Vector2(-52.5, -14.5),
				Vector2(-60.0, -22.5),
				Vector2(-72.0, -26.5),
			], 3))
			# Eastern waterfall plunge cove & Cascade Shrine vista trail descending gently from
			# the main citadel ramp into the sunlit mist basin beneath `CitadelWaterfall`!
			out.append(_catmull_rom_polyline([
				Vector2(-1.0, -48.0),
				Vector2(15.0, -45.0),
				Vector2(30.0, -42.0),
				Vector2(44.0, -37.0),
				Vector2(53.0, -31.5),
				Vector2(56.0, -24.5),
			], 3))
			# Golden landing beach promenade linking BeachCampfire (-36.9, -161.5) & east dig clearings.
			out.append(_catmull_rom_polyline([
				Vector2(-34.0, -154.0),
				Vector2(-18.0, -151.0),
				Vector2(0.0, -148.0),
				Vector2(22.0, -147.0),
				Vector2(46.0, -144.0),
			], 3))

		&"wreck_shoal":
			# Wrecker's Shoal: landing sandbar -> weaving between the two stranded shipwrecks ->
			# climbing smoothly around the gentle west shoulder up to `ImpaledShipwreckBow_Main`.
			out.append(_catmull_rom_polyline([
				Vector2(6.5 * s, -46.0 * s),
				Vector2(2.8 * s, -34.0 * s),
				Vector2(-6.5 * s, -22.0 * s),
				Vector2(-7.2 * s, -10.0 * s),
				Vector2(-2.5 * s, -3.0 * s),
			], 3))
			# Western shoal sandbar salvage spur linking outer dig clearings & shipwreck bow.
			out.append(_catmull_rom_polyline([
				Vector2(3.5 * s, -41.0 * s),
				Vector2(-9.0 * s, -44.5 * s),
				Vector2(-21.5 * s, -42.5 * s),
				Vector2(-29.5 * s, -36.5 * s),
			], 3))

		&"volcano_crag":
			# Cinder Crag: dark-ash landing beach -> ash dig clearings -> straight through
			# `VolcanicObsidianArch_Portal` (-4.5, -102.7) up to the Caldera Portal Overlook!
			out.append(_catmull_rom_polyline([
				Vector2(0.0, -56.0 * s),
				Vector2(-1.4 * s, -48.5 * s),
				Vector2(-1.0 * s, -41.0 * s),
				Vector2(-1.5 * s, -35.0 * s),
				Vector2(-0.8 * s, -32.8 * s),
			], 3))
			# Southwest ash basin & coastal lava-terrace contour skirting smoothly below the west rim.
			out.append(_catmull_rom_polyline([
				Vector2(-1.2 * s, -49.0 * s),
				Vector2(-14.0 * s, -51.0 * s),
				Vector2(-26.0 * s, -49.5 * s),
				Vector2(-37.0 * s, -45.5 * s),
				Vector2(-44.5 * s, -37.5 * s),
				Vector2(-48.5 * s, -27.0 * s),
			], 3))
			# Southeast ash-cove & cauldron-shrine vista trail (cleanly framing both LavaCauldronShrines!).
			out.append(_catmull_rom_polyline([
				Vector2(0.0, -52.0 * s),
				Vector2(9.5 * s, -50.2 * s),
				Vector2(15.5 * s, -49.2 * s),
				Vector2(20.5 * s, -48.8 * s),
			], 3))

		&"skull_bluff":
			# Skull Bluff: South Sand Spit landing beach -> dig clearings -> straight across
			# `BluffTimberBridge` (0, -26*s) -> sweeping onto the lush western highland terrace
			# past `HighlandRuinArch` & overlooking Skull Brow.
			out.append(_catmull_rom_polyline([
				Vector2(0.0, -56.5 * s),
				Vector2(-2.2 * s, -47.0 * s),
				Vector2(2.0 * s, -36.5 * s),
				Vector2(0.0, -26.0 * s),
				Vector2(-11.0 * s, -22.0 * s),
				Vector2(-22.5 * s, -16.5 * s),
				Vector2(-31.0 * s, -11.5 * s),
			], 3))
			# Eastern bridgehead fork contouring smoothly up onto the eastern highland terrace
			# toward `HighlandRuinPillar_0` & `CompassMonolith_Terrace`.
			out.append(_catmull_rom_polyline([
				Vector2(0.0, -25.5 * s),
				Vector2(10.0 * s, -22.5 * s),
				Vector2(21.0 * s, -16.5 * s),
				Vector2(31.5 * s, -10.5 * s),
			], 3))
			# South Sand Spit coastal spur leading west to `LeviathanRibcage_Spit` & cove clearings.
			out.append(_catmull_rom_polyline([
				Vector2(-1.6 * s, -52.0 * s),
				Vector2(-12.5 * s, -52.5 * s),
				Vector2(-21.5 * s, -48.5 * s),
				Vector2(-26.5 * s, -41.5 * s),
			], 3))

		&"smuggler_cove":
			# Smuggler's Cove: dry hidden pocket beach winding straight into `SmugglersGrotto` mouth.
			out.append(_catmull_rom_polyline([
				Vector2(3.2 * s, -16.5 * s),
				Vector2(1.8 * s, -12.0 * s),
				Vector2(0.8 * s, -4.0 * s),
				Vector2(0.0, 4.0 * s),
			], 3))
			# East pocket-beach climb scaling smoothly toward `CliffCatwalkPier_Cove` overlook.
			out.append(_catmull_rom_polyline([
				Vector2(3.0 * s, -15.0 * s),
				Vector2(8.5 * s, -14.5 * s),
				Vector2(14.5 * s, -12.5 * s),
				Vector2(18.5 * s, -10.5 * s),
			], 3))
			# Western amphitheatre headland trail linking outer landing beach -> PirateGibbet -> HighlandRuinArch.
			out.append(_catmull_rom_polyline([
				Vector2(-14.0 * s, -52.5 * s),
				Vector2(-22.0 * s, -44.0 * s),
				Vector2(-25.5 * s, -34.0 * s),
				Vector2(-23.0 * s, -24.5 * s),
				Vector2(-21.5 * s, -16.5 * s),
			], 3))

		&"sea_stack":
			# Siren's Tooth: sweeping coral-sandbar tide-path linking the west beach clearing ->
			# main south landing beach past `LeviathanRibcage_Shelf` -> east arch & fang overlook shelf!
			out.append(_catmull_rom_polyline([
				Vector2(-26.0 * s, -31.5 * s),
				Vector2(-11.0 * s, -37.0 * s),
				Vector2(4.0 * s, -38.5 * s),
				Vector2(19.0 * s, -35.5 * s),
				Vector2(30.0 * s, -29.0 * s),
				Vector2(27.0 * s, -16.5 * s),
			], 3))

		&"palm_atoll":
			# Coral-ring footpath starting cleanly at the channel landing beach and tracing
			# the scenic western & northern lagoon rim around to the windward palms.
			out.append(_catmull_rom_polyline([
				Vector2(0.0, -43.0 * s),
				Vector2(-16.0 * s, -38.0 * s),
				Vector2(-31.0 * s, -22.0 * s),
				Vector2(-35.0 * s, 2.0 * s),
				Vector2(-26.0 * s, 24.0 * s),
				Vector2(-8.0 * s, 35.5 * s),
				Vector2(6.0 * s, 36.0 * s),
			], 3))
			# Eastern coral-rim arc tracing the sunlit windward beach cleanly south of the rock crag.
			out.append(_catmull_rom_polyline([
				Vector2(0.0, -42.0 * s),
				Vector2(16.0 * s, -37.0 * s),
				Vector2(30.0 * s, -22.0 * s),
				Vector2(34.5 * s, -5.0 * s),
				Vector2(33.0 * s, 5.5 * s),
			], 3))

		_:
			# Safe scenic cove fallback for any custom/unknown archetype.
			out.append(_catmull_rom_polyline([
				Vector2(0.0, -42.0 * s),
				Vector2(-3.5 * s, -26.0 * s),
				Vector2(3.5 * s, -10.0 * s),
				Vector2(0.0, 6.0 * s),
			], 3))

	return out


## Return the nominal trail half-width in metres for `arch`.
## Generously walkable in first-person: `3.3..4.6 m` on Tier 2–4 islands,
## `2.7..3.2 m` on compact Tier 1 cays.
static func get_trail_half_width(arch: StringName) -> float:
	match arch:
		&"grand_outpost", &"grand_citadel":
			return 4.6
		&"outpost", &"outpost_harbour", &"fort_rock":
			return 4.4
		&"volcano_crag":
			return 4.0
		&"twin_spires", &"skull_bluff":
			return 3.9
		&"crescent_lagoon":
			return 3.7
		&"smuggler_cove":
			return 3.5
		&"sea_arch":
			return 3.4
		&"palm_atoll":
			return 3.3
		&"treasure_peak", &"treasure_cove":
			return 3.2
		&"wreck_shoal":
			return 3.1
		&"sea_stack":
			return 2.7
		_:
			return 3.2


## Build a self-contained trail context dictionary for `island` usable by
## `sample_trail_dressing()`, `query_trail_distance()`, and terrain/detail consumers.
static func build_trail_context(island: Island, arch: StringName = &"",
		landing_yaw: float = 0.0) -> Dictionary:
	var resolved_arch := arch
	var resolved_yaw := landing_yaw
	var polylines: Array[PackedVector2Array] = []
	var half_width := 3.2

	if island != null:
		if resolved_arch == &"":
			resolved_arch = island.archetype
		if is_zero_approx(resolved_yaw) and island.has_meta(&"landing_yaw"):
			resolved_yaw = float(island.get_meta(&"landing_yaw", 0.0))
		polylines = _extract_polylines_from_variant(island.get_meta(&"trail_polylines", null))
		if polylines.is_empty():
			polylines = get_trail_polylines(resolved_arch, island.island_radius, island.island_id)
		half_width = float(island.get_meta(&"trail_half_width", get_trail_half_width(resolved_arch)))
	elif resolved_arch != &"":
		polylines = get_trail_polylines(resolved_arch, 60.0, "")
		half_width = get_trail_half_width(resolved_arch)

	return {
		"active": not polylines.is_empty(),
		"arch": resolved_arch,
		"polylines": polylines,
		"half_width": half_width,
		"landing_yaw": resolved_yaw,
		"cos_y": cos(resolved_yaw),
		"sin_y": sin(resolved_yaw),
	}


## Return shortest horizontal distance in metres from canonical `(u, v)` to any segment in `polylines`.
static func query_trail_distance(u: float, v: float, polylines: Array[PackedVector2Array]) -> float:
	if polylines.is_empty():
		return INF
	return _min_dist_to_polylines(u, v, polylines)


## Alias for `sample_trail_alpha()` exposing the high-contrast worn-footpath vertex `COLOR.a` profile.
static func paint_terrain_trails(u: float, v: float, polylines: Array[PackedVector2Array],
		half_width: float, slope_ny: float, y: float) -> float:
	return sample_trail_alpha(u, v, polylines, half_width, slope_ny, y)


## Sample vertex `COLOR.a` for a terrain vertex at canonical `(u, v)`, elevation `y`,
## and upward surface normal `slope_ny`.
## Carves a solid, high-contrast worn footpath core (`alpha = 0.04..0.12`, i.e.
## `1.0 - COLOR.a = 0.88..0.96`) across the inner 58% of trail width, transitioning
## smoothly over the outer 42% shoulder to `1.0` off-trail.
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
	# Subtle deterministic hand-worn width wobble so edges read organically without breaking core tread.
	var wobble := sin(u * 0.27 + v * 0.19) * 0.32 + cos(u * 0.14 - v * 0.31) * 0.24
	var eff_hw := maxf(half_width + wobble, 1.0)
	var outer_r := eff_hw * TRAIL_OUTER_SCALE
	if dist >= outer_r:
		return 1.0

	var core_r := outer_r * TRAIL_CORE_RATIO
	var radial: float
	if dist <= core_r:
		var core_t := dist / maxf(core_r, 0.001)
		radial = lerpf(1.0, TRAIL_CORE_EDGE_STRENGTH, core_t * core_t)
	else:
		radial = TRAIL_CORE_EDGE_STRENGTH * (1.0 - _smoothstep(core_r, outer_r, dist))

	var height_gate := _smoothstep(TRAIL_MIN_Y, TRAIL_FULL_Y, y)
	var slope_gate := _smoothstep(TRAIL_MIN_NY, TRAIL_FULL_NY, slope_ny)
	var trail_strength := radial * height_gate * slope_gate
	return clampf(1.0 - trail_strength * TRAIL_PEAK_STRENGTH, 0.04, 1.0)


## Sample grounded stepping-stone & trail-shoulder curb-stone transforms along `island`'s
## walkable footpaths for batched `IslandDetails` / environmental trail dressing.
## Accepts either a `build_trail_context()` dict, `IslandDetails._collect_trail_context()` dict,
## or an empty dict (falling back cleanly to `island` metadata / archetype defaults).
## Returns `{"stepping_stones": Array[Dictionary], "curb_stones": Array[Dictionary]}` where each
## entry holds `{"pos": Vector3, "tangent": Vector3, "normal": Vector3, "scale": float}` in local space.
static func sample_trail_dressing(island: Island, trail_ctx: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var stepping_stones: Array[Dictionary] = []
	var curb_stones: Array[Dictionary] = []
	if island == null:
		return {
			"stepping_stones": stepping_stones,
			"curb_stones": curb_stones,
		}

	var local_rng := rng
	if local_rng == null:
		local_rng = RandomNumberGenerator.new()
		local_rng.seed = island.island_id.hash() ^ 0x5750

	var arch := island.archetype
	var radius := island.island_radius
	var polylines := _extract_polylines_from_variant(trail_ctx.get("polylines", null))
	if polylines.is_empty() and island.has_meta(&"trail_polylines"):
		polylines = _extract_polylines_from_variant(island.get_meta(&"trail_polylines", null))
	if polylines.is_empty():
		polylines = get_trail_polylines(arch, radius, island.island_id)
	if polylines.is_empty():
		return {
			"stepping_stones": stepping_stones,
			"curb_stones": curb_stones,
		}

	var half_width: float = float(trail_ctx.get("half_width",
		island.get_meta(&"trail_half_width", get_trail_half_width(arch))))
	var landing_yaw: float
	if trail_ctx.has("landing_yaw"):
		landing_yaw = float(trail_ctx["landing_yaw"])
	elif trail_ctx.has("cos_y") and trail_ctx.has("sin_y"):
		landing_yaw = atan2(float(trail_ctx["sin_y"]), float(trail_ctx["cos_y"]))
	else:
		landing_yaw = float(island.get_meta(&"landing_yaw", 0.0))

	var basis := Basis(Vector3.UP, landing_yaw)
	var step_placed_xz: Array[Vector2] = []
	var curb_placed_xz: Array[Vector2] = []
	var step_dedup_sq := 2.6 * 2.6
	var curb_dedup_sq := 2.2 * 2.2
	var curb_center_clear := half_width * 0.90

	for poly in polylines:
		var poly_len := _polyline_length(poly)
		if poly_len < 4.0:
			continue

		# 1. Stepping stones spaced cleanly along the walkable trail center (3.0..4.6 m).
		var s_dist := local_rng.randf_range(1.4, 2.8)
		while s_dist <= poly_len - 1.2:
			var frac := s_dist / poly_len
			var sample := _sample_polyline_arc(poly, frac)
			var pt := sample["pt"] as Vector2
			var dir_uv := sample["dir"] as Vector2
			var perp_uv := Vector2(-dir_uv.y, dir_uv.x)
			var jitter_lat := local_rng.randf_range(-0.28, 0.28) * minf(half_width * 0.25, 0.95)
			var st_uv := pt + perp_uv * jitter_lat

			if not _is_in_dressing_keepout(arch, radius, st_uv.x, st_uv.y):
				var lp := basis * Vector3(st_uv.x, 0.0, st_uv.y)
				var xz := Vector2(lp.x, lp.z)
				if _is_far_from_xz(xz, step_placed_xz, step_dedup_sq):
					var h := island.surface_height(lp.x, lp.z)
					if h >= STEPPING_STONE_MIN_Y:
						var nrm := island.surface_normal(lp.x, lp.z)
						if nrm.y >= STEPPING_STONE_MIN_NY:
							var tan_v := _project_surface_tangent(basis, dir_uv, nrm)
							stepping_stones.append({
								"pos": Vector3(lp.x, h, lp.z),
								"tangent": tan_v,
								"normal": nrm,
								"scale": local_rng.randf_range(0.86, 1.22),
							})
							step_placed_xz.append(xz)

			s_dist += local_rng.randf_range(STEPPING_STONE_SPACING_MIN, STEPPING_STONE_SPACING_MAX)

		# 2. Curb stones flanking both trail shoulders (`d = half_width + 0.30..0.90 m`).
		var c_dist := local_rng.randf_range(1.8, 3.4)
		var side_toggle := 1.0 if local_rng.randf() < 0.5 else -1.0
		while c_dist <= poly_len - 1.4:
			var frac := c_dist / poly_len
			var sample := _sample_polyline_arc(poly, frac)
			var pt := sample["pt"] as Vector2
			var dir_uv := sample["dir"] as Vector2
			var perp_uv := Vector2(-dir_uv.y, dir_uv.x)

			for s_idx in 2:
				if s_idx == 1 and local_rng.randf() > 0.62:
					continue
				var side := side_toggle if s_idx == 0 else -side_toggle
				var shoulder_d := half_width + local_rng.randf_range(CURB_STONE_OFFSET_MIN, CURB_STONE_OFFSET_MAX)
				var along_jit := local_rng.randf_range(-0.65, 0.65)
				var cb_uv := pt + perp_uv * (side * shoulder_d) + dir_uv * along_jit

				if _is_in_landmark_keepout(arch, radius, cb_uv.x, cb_uv.y):
					continue
				# Strictly keep curb stones off intersecting Y-junction walking treads!
				if _min_dist_to_polylines(cb_uv.x, cb_uv.y, polylines) < curb_center_clear:
					continue

				var lp := basis * Vector3(cb_uv.x, 0.0, cb_uv.y)
				var xz := Vector2(lp.x, lp.z)
				if not _is_far_from_xz(xz, curb_placed_xz, curb_dedup_sq):
					continue
				var h := island.surface_height(lp.x, lp.z)
				if h < CURB_STONE_MIN_Y:
					continue
				var nrm := island.surface_normal(lp.x, lp.z)
				if nrm.y < CURB_STONE_MIN_NY:
					continue

				var tan_v := _project_surface_tangent(basis, dir_uv, nrm)
				curb_stones.append({
					"pos": Vector3(lp.x, h, lp.z),
					"tangent": tan_v,
					"normal": nrm,
					"scale": local_rng.randf_range(0.76, 1.24),
				})
				curb_placed_xz.append(xz)

			side_toggle = -side_toggle
			c_dist += local_rng.randf_range(3.6, 5.6)

	return {
		"stepping_stones": stepping_stones,
		"curb_stones": curb_stones,
	}


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
		# Place markers strictly outside the walkable core on the trail shoulder.
		var shoulder_min := clampf(half_width * 0.92, MARKER_OFFSET_MIN, MARKER_OFFSET_MAX - 0.5)
		var shoulder_max := clampf(half_width + 0.85, shoulder_min + 0.35, MARKER_OFFSET_MAX)
		var base_offset := clampf(
			half_width * 0.98 + sin(float(station_idx) * 2.13 + radius * 0.07) * 0.28,
			shoulder_min,
			shoulder_max
		)

		var placed := _try_place_marker_at_station(
			island, arch, radius, basis, polylines, poly, half_width,
			frac, side_sign, base_offset, shoulder_min, shoulder_max,
			kind, spots, min_spacing_sq
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


static func _extract_polylines_from_variant(raw: Variant) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if not (raw is Array):
		return out
	for item: Variant in (raw as Array):
		if item is PackedVector2Array:
			var p := item as PackedVector2Array
			if p.size() >= 2:
				out.append(p)
		elif item is Array:
			var pts := PackedVector2Array()
			for elem: Variant in (item as Array):
				if elem is Vector2:
					pts.append(elem as Vector2)
			if pts.size() >= 2:
				out.append(pts)
	return out


static func _is_far_from_xz(pt: Vector2, existing: Array[Vector2], min_dist_sq: float) -> bool:
	for prev in existing:
		if pt.distance_squared_to(prev) < min_dist_sq:
			return false
	return true


static func _project_surface_tangent(basis: Basis, dir_uv: Vector2, surface_nrm: Vector3) -> Vector3:
	var fwd := basis * Vector3(dir_uv.x, 0.0, dir_uv.y)
	var proj := fwd - surface_nrm * fwd.dot(surface_nrm)
	if proj.length_squared() > 0.0001:
		return proj.normalized()
	if fwd.length_squared() > 0.0001:
		return fwd.normalized()
	return Vector3(0.0, 0.0, 1.0)


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
		half_width: float, frac: float, pref_side: float, base_offset: float,
		shoulder_min: float, shoulder_max: float, kind: StringName,
		existing: Array[Dictionary], min_spacing_sq: float) -> Dictionary:
	# Try nominal arc position first, then gentle along-trail nudges if blocked by a cliff/keepout/water.
	var nudges: Array[float] = [0.0, 0.04, -0.04, 0.09, -0.09, 0.15, -0.15, 0.22, -0.22]
	var sides: Array[float] = [pref_side, -pref_side]
	var offsets: Array[float] = [
		base_offset,
		clampf(base_offset + 0.45, shoulder_min, shoulder_max),
		clampf(base_offset - 0.35, shoulder_min, shoulder_max),
	]
	var center_clear := maxf(half_width * 0.78, 2.2)

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
				# Keep strictly clear of walkable footpath centerlines (including Y-junction forks).
				if _min_dist_to_polylines(m_uv.x, m_uv.y, polylines) < center_clear:
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
			return 6.2
		&"wreck_shoal":
			return 6.8
		&"treasure_peak", &"treasure_cove":
			return 8.5
		&"outpost", &"outpost_harbour":
			return 10.5
		&"grand_outpost", &"grand_citadel", &"volcano_crag":
			return 16.0
		_:
			return clampf(radius * 0.11, 9.0, 14.5)


## Authored per-archetype marker stations `(poly_index, arc_fraction, kind)` framing
## beach trailheads, trail junctions, and scenic vista turns:
## - Outposts, forts, grand_citadel, smuggler_cove: 4..7 warm `&"lantern"` posts (+ vista cairns).
## - Wild treasure/cove/volcano/shoal islands: beach trailhead `&"lantern"` + junction/vista `&"cairn"`s.
static func _build_marker_plan(arch: StringName, poly_count: int) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	match arch:
		&"outpost", &"outpost_harbour":
			plan = [
				{"poly": 0, "t": 0.36, "kind": &"lantern"},
				{"poly": 0, "t": 0.62, "kind": &"lantern"},
				{"poly": 0, "t": 0.88, "kind": &"lantern"},
				{"poly": 1, "t": 0.42, "kind": &"lantern"},
				{"poly": 1, "t": 0.84, "kind": &"lantern"},
				{"poly": 2, "t": 0.56, "kind": &"lantern"},
				{"poly": 2, "t": 0.90, "kind": &"lantern"},
			]
		&"grand_outpost":
			plan = [
				{"poly": 0, "t": 0.24, "kind": &"lantern"},
				{"poly": 0, "t": 0.52, "kind": &"lantern"},
				{"poly": 0, "t": 0.86, "kind": &"lantern"},
				{"poly": 1, "t": 0.48, "kind": &"lantern"},
				{"poly": 1, "t": 0.88, "kind": &"lantern"},
				{"poly": 2, "t": 0.34, "kind": &"lantern"},
				{"poly": 2, "t": 0.72, "kind": &"lantern"},
			]
		&"fort_rock":
			plan = [
				{"poly": 0, "t": 0.08, "kind": &"lantern"},
				{"poly": 0, "t": 0.50, "kind": &"lantern"},
				{"poly": 1, "t": 0.10, "kind": &"lantern"},
				{"poly": 1, "t": 0.90, "kind": &"lantern"},
				{"poly": 2, "t": 0.16, "kind": &"lantern"},
				{"poly": 2, "t": 0.84, "kind": &"lantern"},
			]
		&"grand_citadel":
			plan = [
				{"poly": 0, "t": 0.06, "kind": &"lantern"},
				{"poly": 0, "t": 0.34, "kind": &"lantern"},
				{"poly": 0, "t": 0.68, "kind": &"lantern"},
				{"poly": 1, "t": 0.30, "kind": &"lantern"},
				{"poly": 1, "t": 0.82, "kind": &"cairn"},
				{"poly": 2, "t": 0.34, "kind": &"lantern"},
				{"poly": 2, "t": 0.86, "kind": &"lantern"},
				{"poly": 3, "t": 0.14, "kind": &"lantern"},
			]
		&"smuggler_cove":
			plan = [
				{"poly": 0, "t": 0.12, "kind": &"lantern"},
				{"poly": 0, "t": 0.52, "kind": &"lantern"},
				{"poly": 1, "t": 0.32, "kind": &"lantern"},
				{"poly": 1, "t": 0.82, "kind": &"cairn"},
				{"poly": 2, "t": 0.12, "kind": &"lantern"},
				{"poly": 2, "t": 0.54, "kind": &"cairn"},
				{"poly": 2, "t": 0.88, "kind": &"cairn"},
			]
		&"treasure_peak", &"treasure_cove":
			plan = [
				{"poly": 0, "t": 0.08, "kind": &"lantern"},
				{"poly": 0, "t": 0.48, "kind": &"lantern"},
				{"poly": 0, "t": 0.84, "kind": &"cairn"},
				{"poly": 1, "t": 0.44, "kind": &"cairn"},
				{"poly": 1, "t": 0.88, "kind": &"cairn"},
				{"poly": 2, "t": 0.56, "kind": &"cairn"},
			]
		&"twin_spires":
			plan = [
				{"poly": 0, "t": 0.06, "kind": &"lantern"},
				{"poly": 0, "t": 0.28, "kind": &"cairn"},
				{"poly": 0, "t": 0.52, "kind": &"lantern"},
				{"poly": 0, "t": 0.82, "kind": &"cairn"},
				{"poly": 1, "t": 0.36, "kind": &"cairn"},
				{"poly": 1, "t": 0.78, "kind": &"cairn"},
				{"poly": 2, "t": 0.60, "kind": &"lantern"},
			]
		&"crescent_lagoon":
			plan = [
				{"poly": 0, "t": 0.04, "kind": &"lantern"},
				{"poly": 0, "t": 0.22, "kind": &"cairn"},
				{"poly": 0, "t": 0.48, "kind": &"cairn"},
				{"poly": 0, "t": 0.74, "kind": &"cairn"},
				{"poly": 0, "t": 0.96, "kind": &"lantern"},
				{"poly": 1, "t": 0.52, "kind": &"cairn"},
				{"poly": 2, "t": 0.56, "kind": &"cairn"},
			]
		&"sea_arch":
			plan = [
				{"poly": 0, "t": 0.24, "kind": &"lantern"},
				{"poly": 0, "t": 0.56, "kind": &"cairn"},
				{"poly": 0, "t": 0.88, "kind": &"cairn"},
				{"poly": 1, "t": 0.30, "kind": &"lantern"},
				{"poly": 1, "t": 0.78, "kind": &"cairn"},
			]
		&"wreck_shoal":
			plan = [
				{"poly": 0, "t": 0.22, "kind": &"lantern"},
				{"poly": 0, "t": 0.54, "kind": &"cairn"},
				{"poly": 0, "t": 0.88, "kind": &"cairn"},
				{"poly": 1, "t": 0.62, "kind": &"lantern"},
			]
		&"volcano_crag":
			plan = [
				{"poly": 0, "t": 0.08, "kind": &"lantern"},
				{"poly": 0, "t": 0.44, "kind": &"cairn"},
				{"poly": 0, "t": 0.88, "kind": &"lantern"},
				{"poly": 1, "t": 0.30, "kind": &"cairn"},
				{"poly": 1, "t": 0.66, "kind": &"cairn"},
				{"poly": 1, "t": 0.92, "kind": &"cairn"},
				{"poly": 2, "t": 0.54, "kind": &"lantern"},
			]
		&"skull_bluff":
			plan = [
				{"poly": 0, "t": 0.06, "kind": &"lantern"},
				{"poly": 0, "t": 0.36, "kind": &"lantern"},
				{"poly": 0, "t": 0.64, "kind": &"cairn"},
				{"poly": 0, "t": 0.90, "kind": &"cairn"},
				{"poly": 1, "t": 0.42, "kind": &"cairn"},
				{"poly": 1, "t": 0.84, "kind": &"cairn"},
				{"poly": 2, "t": 0.62, "kind": &"cairn"},
			]
		&"sea_stack":
			plan = [
				{"poly": 0, "t": 0.14, "kind": &"lantern"},
				{"poly": 0, "t": 0.50, "kind": &"cairn"},
				{"poly": 0, "t": 0.86, "kind": &"cairn"},
			]
		&"palm_atoll":
			plan = [
				{"poly": 0, "t": 0.08, "kind": &"lantern"},
				{"poly": 0, "t": 0.36, "kind": &"cairn"},
				{"poly": 0, "t": 0.66, "kind": &"cairn"},
				{"poly": 0, "t": 0.92, "kind": &"cairn"},
				{"poly": 1, "t": 0.34, "kind": &"lantern"},
				{"poly": 1, "t": 0.82, "kind": &"cairn"},
			]
		_:
			plan = [
				{"poly": 0, "t": 0.14, "kind": &"lantern"},
				{"poly": 0, "t": 0.54, "kind": &"cairn"},
				{"poly": 0, "t": 0.88, "kind": &"cairn"},
			]

	var filtered: Array[Dictionary] = []
	for item in plan:
		var idx := int(item["poly"])
		if idx >= 0 and idx < poly_count:
			filtered.append(item)
	return filtered


## Lightweight keepout check for stepping stones along trail centerlines
## (keeps stones off timber bridges, outpost dock piers, grotto interiors & fort bastions).
static func _is_in_dressing_keepout(arch: StringName, radius: float, u: float, v: float) -> bool:
	var s := maxf(radius / 60.0, 0.35)
	var pt := Vector2(u, v)
	if arch == &"outpost" or arch == &"outpost_harbour" or arch == &"grand_outpost":
		if absf(u) < 4.5 and v < -22.5:
			return true
		if pt.distance_squared_to(Vector2(1.8, -14.0)) < 3.5 * 3.5:
			return true
		if pt.distance_squared_to(Vector2(-11.0, -7.5)) < 8.5 * 8.5:
			return true
		if pt.distance_squared_to(Vector2(24.0, -6.5)) < 7.5 * 7.5:
			return true
		return false
	match arch:
		&"twin_spires":
			if pt.distance_squared_to(Vector2(0.0, -6.0 * s)) < 6.2 * 6.2:
				return true
			if pt.distance_squared_to(Vector2(0.0, 8.5 * s)) < 5.5 * 5.5:
				return true
		&"skull_bluff":
			if pt.distance_squared_to(Vector2(0.0, -26.0 * s)) < 6.0 * 6.0:
				return true
		&"grand_citadel":
			if pt.distance_squared_to(Vector2(0.0, 18.0)) < 19.0 * 19.0:
				return true
			if pt.distance_squared_to(Vector2(-42.0, -14.0)) < 6.5 * 6.5:
				return true
			if pt.distance_squared_to(Vector2(-54.0, -14.0)) < 6.5 * 6.5:
				return true
			if pt.distance_squared_to(Vector2(54.0, -5.0)) < 6.5 * 6.5:
				return true
		&"fort_rock":
			if pt.distance_squared_to(Vector2(0.0, 2.0 * s)) < 16.5 * 16.5:
				return true
		&"smuggler_cove":
			var vg := 6.0 * s
			if pt.distance_squared_to(Vector2(0.0, vg + 4.0)) < 8.0 * 8.0:
				return true
	return false


## Canonical `(u, v)` keepout circles mirroring `IslandGenerator` and `IslandLandmarks`
## exclusions so trail markers & curb stones never clip into buildings, plazas, ramps,
## bridges, fort bastions, shipwrecks, or grotto walls.
static func _is_in_landmark_keepout(arch: StringName, radius: float, u: float, v: float) -> bool:
	var s := maxf(radius / 60.0, 0.35)
	var pt := Vector2(u, v)

	if arch == &"outpost" or arch == &"outpost_harbour" or arch == &"grand_outpost":
		var out_zones: Array[Vector3] = [
			Vector3(0.0, -34.0, 15.4),    # Dock pier & ramp head
			Vector3(4.5, -39.5, 11.4),    # Mooring apron
			Vector3(0.0, -18.0, 14.5),    # Central harbour plaza keepout
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
				Vector3(3.0 * s, -23.6 * s, 6.5), # RuinAqueduct_CanyonGate
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
		&"volcano_crag":
			if pt.distance_squared_to(Vector2(-1.5 * s, -35.0 * s)) < 9.5 * 9.5:
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
