class_name IslandLandmarks
extends RefCounted
## Bespoke 3D signature landmark choreographer across all 14 archipelago islands.
##
## Places our 50 stylized PBR `.glb` landmarks (Waves I-1 through I-12,
## `res://assets/generated/landmarks/`) with slope-aware anti-floating grounding,
## inward cliff-normal heel embedding, walkable `col_*` convex collider extraction,
## `foliage_wind.gdshader` vine sway binding, horizon/mid visibility ranges,
## auto-mounted flickering `Lantern_*` lights, keepout-zone registration, and
## walkable trail storytelling markers.
##
## Zero static scene/resource variables: all loaded PackedScenes and ShaderMaterials
## live exclusively in the caller-supplied `landmark_cache` and `foliage_cache`
## dictionaries so zero resources can leak on shutdown.

const LANDMARK_DIR := "res://assets/generated/landmarks/"
const FOLIAGE_SHADER: Shader = preload("res://src/world/foliage_wind.gdshader")

const GLB_SKULL_CARVING := "skull_cliff_carving.glb"
const GLB_SEA_ARCH := "coastal_sea_arch.glb"
const GLB_BASALT_SPIRE := "volcanic_basalt_spire.glb"
const GLB_SHIPWRECK_BOW := "impaled_shipwreck_bow.glb"
const GLB_TEMPLE_STAIRWAY := "ancient_temple_stairway.glb"
const GLB_CATWALK_PIER := "cliff_catwalk_pier.glb"
const GLB_BUTTRESS_WIDE := "cliff_buttress_wide.glb"
const GLB_BUTTRESS_TALL := "cliff_buttress_tall.glb"
const GLB_OVERHANG_LEDGE := "cliff_overhang_ledge.glb"
const GLB_BOULDER_CLUSTER := "mossy_cliff_boulder_cluster.glb"
const GLB_TRAIL_LANTERN := "trail_lantern_post.glb"
const GLB_STONE_CAIRN := "stone_cairn_marker.glb"
const GLB_SEA_GOD_IDOL := "ancient_sea_god_idol.glb"
const GLB_VOLCANIC_ARCH := "volcanic_obsidian_arch.glb"
const GLB_LEVIATHAN_RIBCAGE := "leviathan_ribcage_bones.glb"
const GLB_ROWBOAT_WRECK := "beached_rowboat_wreck.glb"
const GLB_PIRATE_GIBBET := "pirate_warning_gibbet.glb"
const GLB_SIGNAL_BRAZIER := "coastal_signal_brazier.glb"
const GLB_SUMMIT_CRAG := "cliff_summit_crag_spire.glb"
const GLB_RUIN_AQUEDUCT := "cliff_ruin_aqueduct_arch.glb"
const GLB_PIRATE_WATCHPOST := "cliffside_pirate_watchpost.glb"
const GLB_STRATA_RIB := "upper_cliff_strata_rib.glb"
const GLB_PIRATE_CAMP := "pirate_camp_canopy.glb"
const GLB_SUNKEN_STERN := "sunken_galleon_stern.glb"
const GLB_CORAL_ARCH := "giant_tidal_coral_arch.glb"
const GLB_LAVA_SHRINE := "obsidian_lava_cauldron_shrine.glb"
const GLB_HARBOUR_CRANE := "harbour_cargo_crane_dock.glb"
const GLB_JUNGLE_ALTAR := "overgrown_jungle_idol_altar.glb"
const GLB_WATERFALL_SHRINE := "cliffside_waterfall_shrine.glb"
const GLB_SMUGGLER_HOARD := "smuggler_contraband_hoard.glb"
const GLB_FORT_WATCHTOWER := "fort_coastal_watchtower_ruin.glb"
const GLB_REEF_BEACON := "shipwreck_bell_buoy_beacon.glb"
const GLB_COMPASS_MONOLITH := "ancient_compass_monolith_ring.glb"
const GLB_VOLCANIC_CHAIN_PYLON := "volcanic_chain_bridge_anchor.glb"
const GLB_SHIP_DRYDOCK := "careening_ship_drydock.glb"
const GLB_SKELETON_THRONE := "cursed_skeleton_throne_shrine.glb"
const GLB_FISHING_HUT := "tropical_fishing_stilts_hut.glb"
const GLB_ASTRONOMER_ORRERY := "ancient_astronomer_orrery_ruin.glb"
const GLB_SMUGGLER_JETTY := "coastal_smuggler_jetty.glb"
const GLB_OBELISK_GATE := "ancient_ruined_obelisk_gate.glb"
const GLB_TRAIL_FOOTBRIDGE := "wooden_trail_footbridge.glb"
const GLB_LOOKOUT_BELL := "pirate_lookout_bell_frame.glb"
const GLB_SUPPLY_CART := "pirate_tavern_supply_cart.glb"
const GLB_ANCHOR_MEMORIAL := "sunken_anchor_memorial.glb"
const GLB_SUNDIAL_PLAZA := "ancient_sun_dial_plaza.glb"
const GLB_OBSIDIAN_VENT := "volcanic_obsidian_fissure_vent.glb"
const GLB_STONE_WELL := "stone_well_courtyard.glb"
const GLB_CANNON_BASTION := "ruined_sea_fort_cannon_bastion.glb"
const GLB_TREASURE_VAULT := "pirate_treasure_vault_door.glb"
const GLB_CROW_NEST_MAST := "wooden_shipwreck_crow_nest_mast.glb"

const VIS_RANGE_HORIZON := 2200.0
const VIS_RANGE_MID := 380.0
const MAX_TRAIL_MARKERS := 8

# Wave I-10/I-11/I-12 (Local-GPU M21A/M22A < 0.43 ms LOD optimization): cull mid-scale ground & cove
# props cleanly beyond 380 m offshore (24 mid-scale GLBs!) so offshore sailing adds zero extra draw calls
# while tall iconic horizon silhouettes stay crisp out to 2200 m.
const MID_RANGE_FILES: Array[String] = [
	GLB_BOULDER_CLUSTER,
	GLB_TRAIL_LANTERN,
	GLB_STONE_CAIRN,
	GLB_ROWBOAT_WRECK,
	GLB_PIRATE_GIBBET,
	GLB_SIGNAL_BRAZIER,
	GLB_PIRATE_CAMP,
	GLB_LAVA_SHRINE,
	GLB_JUNGLE_ALTAR,
	GLB_SMUGGLER_HOARD,
	GLB_SHIP_DRYDOCK,
	GLB_SKELETON_THRONE,
	GLB_FISHING_HUT,
	GLB_SMUGGLER_JETTY,
	GLB_TRAIL_FOOTBRIDGE,
	GLB_LOOKOUT_BELL,
	GLB_SUPPLY_CART,
	GLB_ANCHOR_MEMORIAL,
	GLB_SUNDIAL_PLAZA,
	GLB_OBSIDIAN_VENT,
	GLB_STONE_WELL,
	GLB_CANNON_BASTION,
	GLB_TREASURE_VAULT,
	GLB_CROW_NEST_MAST,
]

# Auto-mounted OmniLight3D presets for `Lantern_*` GLB empties.
const COL_SKULL_EYE := Color(0.16, 0.98, 0.78)
const COL_MAGMA_ARCH := Color(1.0, 0.42, 0.10)
const COL_BRAZIER_FIRE := Color(1.0, 0.58, 0.18)
const COL_WATCHPOST_BEACON := Color(1.0, 0.72, 0.30)
const COL_CAMP_FIRE := Color(1.0, 0.70, 0.28)
const COL_STERN_BRASS := Color(1.0, 0.76, 0.34)
const COL_CALDERA_SHRINE := Color(1.0, 0.38, 0.08)
const COL_CRANE_LANTERN := Color(1.0, 0.76, 0.40)
const COL_ALTAR_FIRE := Color(0.28, 0.96, 0.78)
const COL_WATERFALL_SHRINE := Color(0.96, 0.84, 0.44)
const COL_HOARD_LANTERN := Color(1.0, 0.68, 0.30)
const COL_WATCHTOWER_BEACON := Color(1.0, 0.66, 0.24)
const COL_REEF_BEACON := Color(0.38, 0.96, 0.72)
const COL_MONOLITH_GLOW := Color(0.24, 0.92, 1.0)
const COL_CHAIN_PYLON := Color(1.0, 0.44, 0.14)
const COL_DRYDOCK_LANTERN := Color(1.0, 0.62, 0.22)
const COL_THRONE_GLOW := Color(0.24, 1.0, 0.64)
const COL_FISH_HUT_LANTERN := Color(1.0, 0.76, 0.38)
const COL_ORRERY_STAR := Color(0.32, 0.84, 1.0)
const COL_FOOTBRIDGE_LANTERN := Color(1.0, 0.74, 0.34)
const COL_JETTY_LANTERN := Color(1.0, 0.72, 0.32)
const COL_OBELISK_GATE_GLOW := Color(0.24, 0.96, 0.80)
const COL_BELL_FRAME_LANTERN := Color(1.0, 0.66, 0.24)
const COL_CART_LANTERN := Color(1.0, 0.74, 0.34)
const COL_ANCHOR_LANTERN := Color(1.0, 0.70, 0.30)
const COL_SUNDIAL_FIRE := Color(1.0, 0.78, 0.32)
const COL_MAGMA_VENT := Color(1.0, 0.36, 0.08)
const COL_WELL_LANTERN := Color(1.0, 0.74, 0.36)
const COL_BASTION_TORCH := Color(1.0, 0.56, 0.18)
const COL_VAULT_GLOW := Color(0.26, 0.96, 0.78)
const COL_CROWNEST_LANTERN := Color(1.0, 0.70, 0.28)
const COL_HARBOUR_AMBER := Color(1.0, 0.72, 0.34)
const COL_TRAIL_AMBER := Color(1.0, 0.74, 0.36)


## Populate bespoke signature landmarks and trail storytelling markers on `island`.
## Returns total number of signature landmark & trail-marker instances spawned.
static func populate_signature_landmarks(
		island: Island,
		arch: StringName,
		landing_yaw: float,
		placed: Array[Vector3],
		keepout_zones: Array[Vector3],
		rng: RandomNumberGenerator,
		prop_body: StaticBody3D,
		props_root: Node3D,
		foliage_cache: Dictionary,
		landmark_cache: Dictionary,
		trail_markers: Array[Dictionary]
) -> int:
	if island == null or props_root == null:
		return 0
	var local_rng := rng
	if local_rng == null:
		local_rng = RandomNumberGenerator.new()
		local_rng.seed = island.island_id.hash() ^ 0x4C4D

	var basis := Basis(Vector3.UP, landing_yaw)
	var scale_r := island.island_radius / 60.0
	var count := 0

	match arch:
		&"skull_bluff":
			count += _populate_skull_bluff(island, basis, landing_yaw, scale_r,
				placed, keepout_zones, local_rng, prop_body, props_root, foliage_cache, landmark_cache)
		&"twin_spires":
			count += _populate_twin_spires(island, basis, landing_yaw, scale_r,
				placed, keepout_zones, local_rng, prop_body, props_root, foliage_cache, landmark_cache)
		&"grand_citadel":
			count += _populate_grand_citadel(island, basis, landing_yaw,
				placed, keepout_zones, local_rng, prop_body, props_root, foliage_cache, landmark_cache)
		&"grand_outpost":
			count += _populate_grand_outpost(island, basis, landing_yaw,
				placed, keepout_zones, local_rng, prop_body, props_root, foliage_cache, landmark_cache)
		&"outpost":
			count += _populate_outpost(island, basis, landing_yaw, scale_r,
				placed, keepout_zones, local_rng, prop_body, props_root, foliage_cache, landmark_cache)
		&"smuggler_cove":
			count += _populate_smuggler_cove(island, basis, landing_yaw, scale_r,
				placed, keepout_zones, local_rng, prop_body, props_root, foliage_cache, landmark_cache)
		&"treasure_peak":
			count += _populate_treasure_peak(island, basis, landing_yaw, scale_r,
				placed, keepout_zones, local_rng, prop_body, props_root, foliage_cache, landmark_cache)
		&"sea_arch":
			count += _populate_sea_arch(island, basis, landing_yaw, scale_r,
				placed, keepout_zones, local_rng, prop_body, props_root, foliage_cache, landmark_cache)
		&"crescent_lagoon":
			count += _populate_crescent_lagoon(island, basis, landing_yaw, scale_r,
				placed, keepout_zones, local_rng, prop_body, props_root, foliage_cache, landmark_cache)
		&"fort_rock":
			count += _populate_fort_rock(island, basis, landing_yaw, scale_r,
				placed, keepout_zones, local_rng, prop_body, props_root, foliage_cache, landmark_cache)
		&"wreck_shoal":
			count += _populate_wreck_shoal(island, basis, landing_yaw, scale_r,
				placed, keepout_zones, local_rng, prop_body, props_root, foliage_cache, landmark_cache)
		&"sea_stack":
			count += _populate_sea_stack(island, basis, landing_yaw, scale_r,
				placed, keepout_zones, local_rng, prop_body, props_root, foliage_cache, landmark_cache)
		&"volcano_crag":
			count += _populate_volcano_crag(island, basis, landing_yaw, scale_r,
				placed, keepout_zones, local_rng, prop_body, props_root, foliage_cache, landmark_cache)
		&"palm_atoll":
			count += _populate_palm_atoll(island, basis, landing_yaw, scale_r,
				placed, keepout_zones, local_rng, prop_body, props_root, foliage_cache, landmark_cache)

	count += _populate_trail_markers(island, landing_yaw, trail_markers,
		placed, keepout_zones, local_rng, prop_body, props_root, foliage_cache, landmark_cache)
	return count


# ============================================================ 14-island choreography

static func _populate_skull_bluff(island: Island, basis: Basis, landing_yaw: float,
		scale_r: float, placed: Array[Vector3], keepout_zones: Array[Vector3],
		rng: RandomNumberGenerator, prop_body: StaticBody3D, props_root: Node3D,
		foliage_cache: Dictionary, landmark_cache: Dictionary) -> int:
	var count := 0

	# HERO: ~25 m colossal stone pirate skull carved into Skull Bluff's rising -v cliff brow!
	var sea_dir := (basis * Vector3(0.0, 0.0, -1.0)).normalized()
	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found_brow := false
	var v_min := -18.0 * scale_r
	var v_max := 14.0 * scale_r
	var steps := 36
	for u_off: float in [0.0, -3.5, 3.5]:
		for i in range(steps + 1):
			var t := float(i) / float(steps)
			var v := lerpf(v_min, v_max, t)
			var lp := basis * Vector3(u_off, 0.0, v)
			var h := island.surface_height(lp.x, lp.z)
			if h < 18.0 or h > 56.0:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.5)
			var out_xz := Vector3(n.x, 0.0, n.z)
			var sea_dot := out_xz.normalized().dot(sea_dir) if out_xz.length_squared() > 0.001 else 0.0
			# Strongly prefer dramatic rising -v cliff faces at h = 26..42 m with steep seaward slope.
			var h_score := -absf(h - 34.0) * 0.65
			if h >= 26.0 and h <= 42.0:
				h_score += 8.0
			var slope_score := (1.0 - n.y) * 14.0 if n.y < 0.74 else -6.0
			var score := h_score + slope_score + sea_dot * 12.0 - absf(u_off) * 0.8
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, h, lp.z)
				found_brow = true

	if not found_brow:
		var fb := basis * Vector3(0.0, 0.0, -4.0 * scale_r)
		best_pos = Vector3(fb.x, island.surface_height(fb.x, fb.z), fb.z)

	# Embed rear cranium +3.2 m inland along +v and seat chin cleanly so cranium towers above the jungle!
	var embed_back := basis * Vector3(0.0, 0.0, 3.2)
	var skull_xz := Vector3(best_pos.x + embed_back.x, 0.0, best_pos.z + embed_back.z)
	var skull_y := clampf(best_pos.y - 6.5, 16.0, 42.0)
	var skull_scale := Vector3(1.42, 1.42, 1.35)
	var skull_xf := Transform3D(
		Basis(Vector3.UP, landing_yaw) * Basis.from_scale(skull_scale),
		Vector3(skull_xz.x, skull_y, skull_xz.z))
	if _spawn_landmark(island, GLB_SKULL_CARVING, "SkullCliffCarving", skull_xf, 15.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null:
		count += 1

	# Wave I-8 (Pass I-Q1 full overhang sweep): 2 bottom-heavy A-frame cliff buttresses locking cleanly
	# into Skull Bluff's western & eastern bluff slopes (zero flat-underside cantilevered shelves!).
	var flank_buttress_specs: Array[Array] = [
		["CliffButtressWide_West", -28.0 * scale_r, -4.0 * scale_r, Vector3(-0.78, 0.0, -0.62), 1.06],
		["CliffButtressWide_East", 28.0 * scale_r, -4.0 * scale_r, Vector3(0.78, 0.0, -0.62), 1.04],
	]
	for spec: Array in flank_buttress_specs:
		var pref_dir := (basis * (spec[3] as Vector3)).normalized()
		if _place_cliff_buttress_wide(island, basis, String(spec[0]), float(spec[1]), float(spec[2]),
				16.0, 14.0, 6.0, 36.0, pref_dir, float(spec[4]), 5.5,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# 2 mossy boulder clusters framing the south landing sand spit & lower terraces.
	var boulder_uvs: Array[Vector2] = [
		Vector2(-18.0 * scale_r, -38.0 * scale_r),
		Vector2(20.0 * scale_r, -34.0 * scale_r),
	]
	for bi in boulder_uvs.size():
		if _place_boulder_cluster(island, basis, "MossyBoulderCluster_%d" % bi,
				boulder_uvs[bi].x, boulder_uvs[bi].y, 12.0, rng.randf_range(0.92, 1.16),
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# Wave I-3 storytelling landmarks: colossal Leviathan Ribcage on south sand spit & warning gibbet!
	if _place_leviathan_ribcage(island, basis, "LeviathanRibcage_Spit",
			-24.0 * scale_r, -42.0 * scale_r, landing_yaw + 0.42, 1.04, 18.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_pirate_gibbet(island, basis, "PirateGibbet_Approach",
			24.0 * scale_r, -30.0 * scale_r, landing_yaw - 0.35, 1.04, 14.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-4 skyline & cliff-crown choreography (strictly clear of SkullCliffCarving face!).
	if _place_summit_crag(island, basis, "SummitCrag_Crown",
			10.0 * scale_r, 21.0 * scale_r, 18.0 * scale_r, 14.0 * scale_r,
			42.0, 92.0, landing_yaw + 0.35, 1.12,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	# Wave I-9 (Local-GPU M20A polish): seat PirateWatchpost_Bluff on a gentler terrace shoulder
	# (h in 9..26m) so all 4 -7.8m stilts plant deeply with zero exposed cliffside tips!
	var bluff_wp_dir := (basis * Vector3(-0.55, 0.0, -0.84)).normalized()
	if _place_pirate_watchpost(island, basis, "PirateWatchpost_Bluff",
			-28.0 * scale_r, -18.0 * scale_r, 18.0 * scale_r, 18.0 * scale_r,
			9.0, 26.0, bluff_wp_dir, 1.02,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	var bluff_rib_specs: Array[Array] = [
		["UpperStrataRib_BluffW", -22.0 * scale_r, 2.0 * scale_r, Vector3(-0.78, 0.0, -0.62), 1.08],
		["UpperStrataRib_BluffE", 22.0 * scale_r, 2.0 * scale_r, Vector3(0.78, 0.0, -0.62), 1.08],
	]
	for spec: Array in bluff_rib_specs:
		var rib_dir := (basis * (spec[3] as Vector3)).normalized()
		if _place_upper_strata_rib(island, basis, String(spec[0]), float(spec[1]), float(spec[2]),
				14.0 * scale_r, 14.0 * scale_r, 18.0, 64.0, rib_dir, float(spec[4]),
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# Wave I-5 coastal storytelling: heeled gilded galleon stern grounded on Skull Bluff's outer eastern spit!
	if _place_sunken_stern(island, basis, "SunkenStern_Spit",
			28.0 * scale_r, -54.0 * scale_r, landing_yaw - 0.68, 1.06, 26.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-6 jungle temple & smuggler stash choreography on Skull Bluff's ritual clearing & landing cove!
	if _place_jungle_altar(island, basis, "JungleAltar_Hollow",
			14.0 * scale_r, -30.0 * scale_r, landing_yaw - 0.25, 1.04, 22.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_smuggler_hoard(island, basis, "SmugglerHoard_Cove",
			11.0 * scale_r, -42.0 * scale_r, landing_yaw - 0.50, 1.02, 16.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-7 relic & headland choreography: eastern terrace compass monolith & chained western headland pylon!
	if _place_compass_monolith(island, basis, "CompassMonolith_Terrace",
			39.0 * scale_r, -16.0 * scale_r, landing_yaw - 0.30, 1.04, 22.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_volcanic_chain_pylon(island, basis, "VolcanicChainPylon_Bluff",
			-40.0 * scale_r, -24.0 * scale_r, landing_yaw + 0.65, 1.04, 22.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-9 cursed shrine choreography: captain's skeleton throne commanding Skull Bluff's western highland!
	if _place_skeleton_throne(island, basis, "SkeletonThrone_Bluff",
			-42.0 * scale_r, -13.0 * scale_r, landing_yaw + 0.42, 1.04, 18.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-10 south sand-spit landing jetty & hollow approach obelisk gateway!
	var bluff_jetty_dir := (basis * Vector3(0.28, 0.0, -0.96)).normalized()
	if _place_smuggler_jetty(island, basis, "SmugglerJetty_Spit",
			6.0 * scale_r, -56.5 * scale_r, 16.0 * scale_r, bluff_jetty_dir, 1.04,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_obelisk_gate(island, basis, "ObeliskGate_Hollow",
			-0.5 * scale_r, -43.0 * scale_r, landing_yaw + atan2(0.40, 0.92), 1.04, 12.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-11 glowing obsidian fissure vent tucked menacingly into Skull Bluff's western cursed terrace!
	if _place_obsidian_vent(island, basis, "ObsidianVent_Hollow",
			-32.0 * scale_r, -6.0 * scale_r, landing_yaw + 0.45, 1.04, 14.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-12 eastern approach headland cannon bastion & lower cliff wall pirate treasure vault!
	var skull_bast_dir := (basis * Vector3(0.45, 0.0, -0.89)).normalized()
	if _place_cannon_bastion(island, basis, "CannonBastion_Overlook",
			38.5 * scale_r, -19.5 * scale_r, 14.0 * scale_r, skull_bast_dir, 1.04,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	var skull_vault_dir := (basis * Vector3(-0.55, 0.0, -0.84)).normalized()
	if _place_treasure_vault(island, basis, "TreasureVault_Hollow",
			-14.0 * scale_r, -12.0 * scale_r, 14.0 * scale_r, 12.0 * scale_r, skull_vault_dir, 1.04,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	return count


static func _populate_twin_spires(island: Island, basis: Basis, landing_yaw: float,
		scale_r: float, placed: Array[Vector3], keepout_zones: Array[Vector3],
		rng: RandomNumberGenerator, prop_body: StaticBody3D, props_root: Node3D,
		foliage_cache: Dictionary, landmark_cache: Dictionary) -> int:
	var count := 0

	# HERO: Ancient Temple Stairway ascending the walkable emerald canyon floor toward the waterfall!
	if _place_temple_stairway(island, basis, "TempleStairway_Canyon",
			0.0, 6.5 * scale_r, landing_yaw, 1.18, 9.5, 10.0, 14.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-3 HERO: Colossal mossy Ancient Sea-God Idol overlooking the emerald waterfall valley!
	if _place_sea_god_idol(island, basis, "SeaGodIdol_Canyon",
			-10.0 * scale_r, -8.0 * scale_r, landing_yaw + 0.32, 1.08, 18.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# 2 massive bottom-heavy cliff buttresses locking cleanly into the western & eastern canyon toes
	# (eliminates edge-on cantilevered overhang silhouettes inside Emerald Spire's steep V-canyon; Local-GPU §7.11.4 #1).
	var buttress_specs: Array[Array] = [
		["CliffButtressWide_West", -22.0 * scale_r, -12.0 * scale_r, Vector3(0.85, 0.0, -0.52), 1.08],
		["CliffButtressWide_East", 22.0 * scale_r, -6.0 * scale_r, Vector3(-0.85, 0.0, -0.52), 1.08],
	]
	for spec: Array in buttress_specs:
		var pref_dir := (basis * (spec[3] as Vector3)).normalized()
		if _place_cliff_buttress_wide(island, basis, String(spec[0]), float(spec[1]), float(spec[2]),
				16.0, 14.0, 3.0, 14.0, pref_dir, float(spec[4]), 5.5,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# 3 mossy boulder clusters flanking the waterfall canyon & landing cove.
	var boulder_uvs: Array[Vector2] = [
		Vector2(-12.0 * scale_r, -32.0 * scale_r),
		Vector2(13.0 * scale_r, -30.0 * scale_r),
		Vector2(9.0 * scale_r, 8.0 * scale_r),
	]
	for bi in boulder_uvs.size():
		if _place_boulder_cluster(island, basis, "MossyBoulderCluster_%d" % bi,
				boulder_uvs[bi].x, boulder_uvs[bi].y, 12.0, rng.randf_range(0.90, 1.18),
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# Wave I-4 skyline choreography: twin crag crowns, canyon shoulder aqueducts & stepped canyon ribs!
	if _place_summit_crag(island, basis, "SummitCrag_West",
			-16.0 * scale_r, 18.0 * scale_r, 20.0 * scale_r, 22.0 * scale_r,
			44.0, 108.0, landing_yaw - 0.30, 1.18,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_summit_crag(island, basis, "SummitCrag_East",
			16.5 * scale_r, 11.0 * scale_r, 16.0 * scale_r, 18.0 * scale_r,
			38.0, 96.0, landing_yaw + 0.48, 1.12,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_ruin_aqueduct(island, basis, "RuinAqueduct_CanyonGate",
			0.0, -20.0 * scale_r, 10.0 * scale_r, 18.0 * scale_r,
			landing_yaw, 1.04, 2.0, 12.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	var canyon_rib_specs: Array[Array] = [
		["UpperStrataRib_CanyonW1", -18.0 * scale_r, -16.0 * scale_r, 12.0 * scale_r, 12.0 * scale_r, 20.0, 64.0, Vector3(0.86, 0.0, -0.51), 1.12],
		["UpperStrataRib_CanyonW2", -15.0 * scale_r, 6.0 * scale_r, 12.0 * scale_r, 14.0 * scale_r, 24.0, 72.0, Vector3(0.92, 0.0, -0.39), 1.14],
		["UpperStrataRib_CanyonE1", 17.0 * scale_r, -14.0 * scale_r, 12.0 * scale_r, 12.0 * scale_r, 20.0, 62.0, Vector3(-0.86, 0.0, -0.51), 1.12],
		["UpperStrataRib_CanyonE2", 16.0 * scale_r, 8.0 * scale_r, 12.0 * scale_r, 14.0 * scale_r, 24.0, 68.0, Vector3(-0.92, 0.0, -0.39), 1.14],
	]
	for spec: Array in canyon_rib_specs:
		var rib_dir := (basis * (spec[7] as Vector3)).normalized()
		if _place_upper_strata_rib(island, basis, String(spec[0]), float(spec[1]), float(spec[2]),
				float(spec[3]), float(spec[4]), float(spec[5]), float(spec[6]), rib_dir, float(spec[8]),
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# Wave I-5 coastal storytelling: pirate expedition camp canopy on Emerald Spire's sunlit landing cove!
	if _place_pirate_camp(island, basis, "PirateCamp_CanyonCove",
			-9.5 * scale_r, -40.0 * scale_r, landing_yaw - 0.38, 1.04, 18.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-6 jungle temple & cascade shrine choreography in Emerald Spire's sunlit canyon!
	if _place_jungle_altar(island, basis, "JungleAltar_Canyon",
			-5.5 * scale_r, -24.0 * scale_r, landing_yaw + 0.35, 1.04, 18.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	# Wave I-8 (Local-GPU M19B catch): seat CascadeShrine_Cascade on the western canyon flank,
	# keeping scenes/main.gd shot=emerald_waterfall foreground camera completely unobstructed!
	var canyon_shrine_dir := (basis * Vector3(0.85, 0.0, -0.52)).normalized()
	if _place_waterfall_shrine(island, basis, "CascadeShrine_Cascade",
			-22.0 * scale_r, -8.0 * scale_r, 14.0, 18.0, 2.5, 28.0, canyon_shrine_dir, 1.02,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-7 relic sanctuary: ancient compass monolith ring crowning Emerald Spire's western highland terrace!
	if _place_compass_monolith(island, basis, "CompassMonolith_Summit",
			-34.0 * scale_r, 13.0 * scale_r, landing_yaw + 0.35, 1.06, 18.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-9 celestial observatory choreography: astronomer's armillary orrery crowning the high canyon ridge!
	if _place_astronomer_orrery(island, basis, "AstronomerOrrery_Ridge",
			0.0, 27.0 * scale_r, landing_yaw, 1.10, 18.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-10 canyon-trail obelisk gateway & cove-approach arched oak footbridge!
	if _place_obelisk_gate(island, basis, "ObeliskGate_Trail",
			1.6 * scale_r, -30.5 * scale_r, landing_yaw + atan2(0.15, 0.99), 1.04, 10.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_trail_footbridge(island, basis, "TrailFootbridge_Canyon",
			3.2 * scale_r, -44.0 * scale_r, landing_yaw + atan2(0.06, 1.00), 1.04, 10.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-11 sunlit ancient sundial plaza crowning a meadow terrace beside Emerald Spire's valley!
	if _place_sundial_plaza(island, basis, "SundialPlaza_Canyon",
			14.0 * scale_r, -36.0 * scale_r, landing_yaw - 0.35, 1.06, 16.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-12 treasure vault embedded into the shaded western emerald canyon cliff toe
	# (strictly behind shot=emerald_waterfall camera lens & >60 m clear of TempleStairway_Canyon!).
	var canyon_vault_dir := (basis * Vector3(0.92, 0.0, -0.39)).normalized()
	if _place_treasure_vault(island, basis, "TreasureVault_Canyon",
			-7.2 * scale_r, -17.0 * scale_r, 12.0 * scale_r, 14.0 * scale_r, canyon_vault_dir, 1.04,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	return count


static func _populate_grand_citadel(island: Island, basis: Basis, landing_yaw: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3],
		rng: RandomNumberGenerator, prop_body: StaticBody3D, props_root: Node3D,
		foliage_cache: Dictionary, landmark_cache: Dictionary) -> int:
	var count := 0

	# TWO HERO Temple Stairways ascending onto the western & eastern jungle temple terraces!
	# West climbs from (-54, -14) uphill toward temple_terrace_w (-76, 14): atan2(-22, 28) ~ -0.66 rad.
	var west_stair_yaw := landing_yaw + atan2(-22.0, 28.0)
	if _place_temple_stairway(island, basis, "TempleStairway_West",
			-54.0, -14.0, west_stair_yaw, 1.22, 10.0, 14.0, 14.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# East climbs from (54, -12) uphill toward temple_terrace_e (74, 8): atan2(20, 20) ~ +0.785 rad.
	var east_stair_yaw := landing_yaw + atan2(20.0, 20.0)
	if _place_temple_stairway(island, basis, "TempleStairway_East",
			54.0, -12.0, east_stair_yaw, 1.22, 10.0, 16.0, 14.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-3: Twin Ancient Sea-God Idols crowning the jungle temple terraces + twin outer headland braziers!
	if _place_sea_god_idol(island, basis, "SeaGodIdol_West",
			-74.0, 14.0, landing_yaw + 0.55, 1.18, 18.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_sea_god_idol(island, basis, "SeaGodIdol_East",
			74.0, 10.0, landing_yaw - 0.55, 1.18, 18.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_signal_brazier(island, basis, "SignalBrazier_West",
			-66.0, -64.0, landing_yaw + 0.40, 1.14, 18.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_signal_brazier(island, basis, "SignalBrazier_East",
			66.0, -60.0, landing_yaw - 0.40, 1.14, 18.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-8 (Pass I-Q1 full overhang sweep): 3 headland + 2 rear bottom-heavy CliffButtressWides
	# fortifying outer citadel headlands & promontories (zero flat-underside overhang shelves!).
	var headland_buttress_specs: Array[Array] = [
		["CliffButtressWide_HeadlandW", -86.0, -36.0, Vector3(-0.75, 0.0, -0.66), 1.12],
		["CliffButtressWide_HeadlandE", 86.0, -36.0, Vector3(0.75, 0.0, -0.66), 1.12],
		["CliffButtressWide_Prom", -74.0, -76.0, Vector3(-0.45, 0.0, -0.89), 1.08],
	]
	for spec: Array in headland_buttress_specs:
		var pref_dir := (basis * (spec[3] as Vector3)).normalized()
		if _place_cliff_buttress_wide(island, basis, String(spec[0]), float(spec[1]), float(spec[2]),
				20.0, 18.0, 7.5, 42.0, pref_dir, float(spec[4]), 6.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	var buttress_specs: Array[Array] = [
		["CliffButtressWide_West", -92.0, 22.0, Vector3(-0.92, 0.0, -0.38), 1.16],
		["CliffButtressWide_East", 92.0, 22.0, Vector3(0.92, 0.0, -0.38), 1.16],
	]
	for spec: Array in buttress_specs:
		var pref_dir := (basis * (spec[3] as Vector3)).normalized()
		if _place_cliff_buttress_wide(island, basis, String(spec[0]), float(spec[1]), float(spec[2]),
				22.0, 20.0, 8.0, 48.0, pref_dir, float(spec[4]), 7.5,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# 3 mossy boulder clusters framing the grand landing cove & ramp approach.
	var boulder_uvs: Array[Vector2] = [
		Vector2(-28.0, -96.0),
		Vector2(30.0, -94.0),
		Vector2(-22.0, -52.0),
	]
	for bi in boulder_uvs.size():
		if _place_boulder_cluster(island, basis, "MossyBoulderCluster_%d" % bi,
				boulder_uvs[bi].x, boulder_uvs[bi].y, 16.0, rng.randf_range(0.95, 1.22),
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# Wave I-4 skyline choreography: twin rear citadel crags crowning top skyline, highland aqueducts & rear cliff strata ribs!
	if _place_summit_crag(island, basis, "SummitCrag_CitadelWest",
			-46.0, 94.0, 46.0, 34.0, 62.0, 114.0, landing_yaw - 0.35, 1.24,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_summit_crag(island, basis, "SummitCrag_CitadelEast",
			26.0, 98.0, 48.0, 34.0, 62.0, 114.0, landing_yaw + 0.42, 1.26,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_ruin_aqueduct(island, basis, "RuinAqueduct_CitadelWest",
			-56.0, 48.0, 32.0, 26.0, landing_yaw + 0.35, 1.12, 16.0, 46.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_ruin_aqueduct(island, basis, "RuinAqueduct_CitadelEast",
			54.0, 44.0, 32.0, 26.0, landing_yaw - 0.35, 1.12, 16.0, 46.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	var citadel_wp_dir := (basis * Vector3(-0.35, 0.0, -0.94)).normalized()
	if _place_pirate_watchpost(island, basis, "PirateWatchpost_Citadel",
			-74.0, -34.0, 26.0, 24.0, 14.0, 46.0, citadel_wp_dir, 1.06,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	var citadel_rib_specs: Array[Array] = [
		["UpperStrataRib_RearW", -44.0, 68.0, Vector3(0.28, 0.0, -0.96), 1.22],
		["UpperStrataRib_RearE", 44.0, 64.0, Vector3(-0.28, 0.0, -0.96), 1.22],
	]
	for spec: Array in citadel_rib_specs:
		var rib_dir := (basis * (spec[3] as Vector3)).normalized()
		if _place_upper_strata_rib(island, basis, String(spec[0]), float(spec[1]), float(spec[2]),
				30.0, 26.0, 24.0, 68.0, rib_dir, float(spec[4]),
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# Wave I-6 jungle temple & waterfall cascade choreography!
	if _place_jungle_altar(island, basis, "JungleAltar_Terrace",
			56.0, 14.0, landing_yaw - 0.55, 1.10, 20.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	var citadel_shrine_dir := (basis * Vector3(-0.65, 0.0, -0.76)).normalized()
	if _place_waterfall_shrine(island, basis, "CascadeShrine_Citadel",
			66.0, -40.0, 18.0, 18.0, 2.5, 32.0, citadel_shrine_dir, 1.08,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-7 fortress & relic choreography: headland watchtower & sacred western terrace compass monolith!
	if _place_fort_watchtower(island, basis, "FortWatchtower_Citadel",
			54.0, -72.0, landing_yaw - 0.35, 1.12, 26.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_compass_monolith(island, basis, "CompassMonolith_Plaza",
			-86.0, -4.0, landing_yaw + 0.40, 1.10, 28.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-9 cursed throne & observatory choreography on Sovereign's Bastion twin highland terraces!
	if _place_skeleton_throne(island, basis, "SkeletonThrone_Citadel",
			-68.0, -4.0, landing_yaw + 0.35, 1.10, 18.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_astronomer_orrery(island, basis, "AstronomerOrrery_Overlook",
			72.0, -8.0, landing_yaw - 0.35, 1.12, 18.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-10 grand highway obelisk gateway & eastern ridge trail footbridge!
	if _place_obelisk_gate(island, basis, "ObeliskGate_Citadel",
			0.0, -90.0, landing_yaw, 1.12, 16.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_trail_footbridge(island, basis, "TrailFootbridge_Ridge",
			22.0, -44.0, landing_yaw + atan2(15.0, 3.0), 1.06, 16.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-11 sunlit ancient sundial plaza crowning Sovereign's Bastion broad highland terrace!
	if _place_sundial_plaza(island, basis, "SundialPlaza_Citadel",
			30.0, -64.0, landing_yaw - 0.25, 1.12, 18.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-12 grand highway courtyard well, western promontory cannon bastion & eastern cliff treasure vault!
	if _place_stone_well(island, basis, "StoneWell_Courtyard",
			-28.0, -8.0, landing_yaw + 0.32, 1.06, 14.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	var cit_bast_dir := (basis * Vector3(-0.32, 0.0, -0.95)).normalized()
	if _place_cannon_bastion(island, basis, "CannonBastion_Headland",
			-55.0, -78.0, 16.0, cit_bast_dir, 1.08,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	var cit_vault_dir := (basis * Vector3(0.55, 0.0, -0.84)).normalized()
	if _place_treasure_vault(island, basis, "TreasureVault_Citadel",
			22.0, -7.0, 14.0, 14.0, cit_vault_dir, 1.08,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	return count


static func _populate_grand_outpost(island: Island, basis: Basis, landing_yaw: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3],
		rng: RandomNumberGenerator, prop_body: StaticBody3D, props_root: Node3D,
		foliage_cache: Dictionary, landmark_cache: Dictionary) -> int:
	var count := 0

	# TWO HERO CliffCatwalkPiers cantilevered boldly off the rocky west & east fjord harbour walls!
	var west_inward := (basis * Vector3(0.86, 0.0, -0.51)).normalized()
	if _place_cliff_catwalk(island, basis, "CliffCatwalkPier_West",
			-68.0, -26.0, -50.0, 22.0, 4.5, 9.5, west_inward, 1.12,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	var east_inward := (basis * Vector3(-0.86, 0.0, -0.51)).normalized()
	if _place_cliff_catwalk(island, basis, "CliffCatwalkPier_East",
			26.0, 68.0, -46.0, 20.0, 4.5, 9.5, east_inward, 1.12,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# HERO TempleStairway climbing toward the scenic eastern overlook (clear of Beacon Tower!).
	var overlook_yaw := landing_yaw + atan2(18.0, -10.0)
	if _place_temple_stairway(island, basis, "TempleStairway_Overlook",
			36.0, -8.0, overlook_yaw, 1.06, 9.0, 14.0, 14.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-3: Ancient Sea-God Idol on East Overlook + twin harbour mouth Coastal Signal Braziers!
	if _place_sea_god_idol(island, basis, "SeaGodIdol_Overlook",
			56.0, -22.0, landing_yaw - 0.65, 1.04, 18.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_signal_brazier(island, basis, "SignalBrazier_West",
			-62.0, -82.0, landing_yaw + 0.35, 1.12, 18.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_signal_brazier(island, basis, "SignalBrazier_East",
			62.0, -76.0, landing_yaw - 0.35, 1.12, 18.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-8 (Pass I-Q1 full overhang sweep): 2 bottom-heavy CliffButtressWides on outer fjord headlands
	# (zero flat-underside overhang shelves!).
	var headland_buttress_specs: Array[Array] = [
		["CliffButtressWide_West", -72.0, -76.0, Vector3(0.55, 0.0, -0.84), 1.08],
		["CliffButtressWide_East", 70.0, -70.0, Vector3(-0.55, 0.0, -0.84), 1.08],
	]
	for spec: Array in headland_buttress_specs:
		var pref_dir := (basis * (spec[3] as Vector3)).normalized()
		if _place_cliff_buttress_wide(island, basis, String(spec[0]), float(spec[1]), float(spec[2]),
				20.0, 18.0, 8.0, 38.0, pref_dir, float(spec[4]), 6.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# 3 mossy boulder clusters framing outer fjord beaches & headland skirts.
	var boulder_uvs: Array[Vector2] = [
		Vector2(-38.0, -96.0),
		Vector2(42.0, -90.0),
		Vector2(38.0, 18.0),
	]
	for bi in boulder_uvs.size():
		if _place_boulder_cluster(island, basis, "MossyBoulderCluster_%d" % bi,
				boulder_uvs[bi].x, boulder_uvs[bi].y, 16.0, rng.randf_range(0.92, 1.18),
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# Wave I-4 skyline choreography: twin fjord crags, saddle aqueduct, headland watchpost & fjord strata ribs!
	if _place_summit_crag(island, basis, "SummitCrag_FjordWest",
			-82.0, 12.0, 30.0, 46.0, 28.0, 76.0, landing_yaw - 0.28, 1.18,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_summit_crag(island, basis, "SummitCrag_FjordEast",
			82.0, 18.0, 30.0, 46.0, 28.0, 76.0, landing_yaw + 0.36, 1.18,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_ruin_aqueduct(island, basis, "RuinAqueduct_Overlook",
			0.0, 48.0, 36.0, 26.0, landing_yaw + 0.08, 1.10, 14.0, 44.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	var fjord_wp_dir := (basis * Vector3(0.75, 0.0, -0.66)).normalized()
	if _place_pirate_watchpost(island, basis, "PirateWatchpost_Fjord",
			-66.0, -34.0, 32.0, 36.0, 12.0, 42.0, fjord_wp_dir, 1.08,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	var fjord_rib_specs: Array[Array] = [
		["UpperStrataRib_FjordW", -64.0, -6.0, Vector3(0.88, 0.0, -0.47), 1.16],
		["UpperStrataRib_FjordE", 66.0, 2.0, Vector3(-0.88, 0.0, -0.47), 1.16],
	]
	for spec: Array in fjord_rib_specs:
		var rib_dir := (basis * (spec[3] as Vector3)).normalized()
		if _place_upper_strata_rib(island, basis, String(spec[0]), float(spec[1]), float(spec[2]),
				28.0, 36.0, 18.0, 58.0, rib_dir, float(spec[4]),
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# Wave I-6 harbour, highland grove & fjord-spring choreography!
	var fjord_crane_dir := (basis * Vector3(-0.88, 0.0, -0.47)).normalized()
	if _place_harbour_crane(island, basis, "HarbourCrane_Fjord",
			42.0, -58.0, 22.0, fjord_crane_dir, 1.08,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_jungle_altar(island, basis, "JungleAltar_Grove",
			-32.0, 30.0, landing_yaw + 0.22, 1.08, 20.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	var fjord_shrine_dir := (basis * Vector3(-0.85, 0.0, -0.52)).normalized()
	if _place_waterfall_shrine(island, basis, "CascadeShrine_Fjord",
			64.0, -42.0, 18.0, 20.0, 2.5, 32.0, fjord_shrine_dir, 1.06,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-7 maritime fortress choreography: crumbling watchtower guarding the northern harbour headland!
	if _place_fort_watchtower(island, basis, "FortWatchtower_Fjord",
			92.0, -24.0, landing_yaw - 0.65, 1.10, 20.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-9 harbour slipway & summit observatory choreography on Galleon's Reach!
	var fjord_drydock_dir := (basis * Vector3(0.20, 0.0, -0.98)).normalized()
	if _place_ship_drydock(island, basis, "ShipDrydock_Fjord",
			76.0, -121.0, 22.0, fjord_drydock_dir, 1.08,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_astronomer_orrery(island, basis, "AstronomerOrrery_Summit",
			92.0, -8.0, landing_yaw - 0.85, 1.12, 18.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-10 upper town overlook obelisk gateway & western fjord promenade footbridge!
	if _place_obelisk_gate(island, basis, "ObeliskGate_Overlook",
			3.5, 23.5, landing_yaw + atan2(-0.86, 0.51), 1.06, 14.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_trail_footbridge(island, basis, "TrailFootbridge_Fjord",
			-49.5, -65.0, landing_yaw + atan2(0.17, -0.99), 1.04, 14.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-11 bustling pirate supply cart along Galleon's Reach harbour promenade terrace!
	if _place_supply_cart(island, basis, "SupplyCart_Town",
			-14.0, 18.0, landing_yaw + 0.25, 1.02, 14.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-12 upper town courtyard stone well & harbour mouth cliff cannon bastion!
	if _place_stone_well(island, basis, "StoneWell_Town",
			-2.0, 14.0, landing_yaw + 0.18, 1.04, 12.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	var fjord_bast_dir := (basis * Vector3(0.55, 0.0, -0.84)).normalized()
	if _place_cannon_bastion(island, basis, "CannonBastion_Fjord",
			-68.0, -43.0, 16.0, fjord_bast_dir, 1.06,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	return count


static func _populate_outpost(island: Island, basis: Basis, landing_yaw: float,
		scale_r: float, placed: Array[Vector3], keepout_zones: Array[Vector3],
		rng: RandomNumberGenerator, prop_body: StaticBody3D, props_root: Node3D,
		foliage_cache: Dictionary, landmark_cache: Dictionary) -> int:
	var count := 0
	var is_port_scoundrel := island.island_id == "port_scoundrel"

	if is_port_scoundrel:
		# Wave I-8 (Pass I-Q1 full overhang sweep): bottom-heavy CliffButtressWide anchored onto
		# Port Scoundrel's western cliff arm behind the tavern (zero flat-underside overhang shelf!).
		var pref_dir := (basis * Vector3(0.75, 0.0, -0.66)).normalized()
		if _place_cliff_buttress_wide(island, basis, "CliffButtressWide_TavernBluff",
				-34.0, 3.0, 12.0, 12.0, 8.0, 30.0, pref_dir, 1.0, 6.5,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		# Wave I-3: Coastal Signal Brazier on eastern headland & weathered Beached Rowboat on outer beach!
		if _place_signal_brazier(island, basis, "SignalBrazier_Headland",
				38.0, -18.0, landing_yaw - 0.45, 1.0, 16.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		if _place_beached_rowboat(island, basis, "BeachedRowboat_Cove",
				-34.0, -34.0, landing_yaw + 0.72, 1.0, 16.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		# Wave I-5 coastal storytelling: vibrant tidal coral arch framing Port Scoundrel's outer eastern cove!
		if _place_coral_arch(island, basis, "TidalCoralArch_OuterCove",
				60.0, -52.0, landing_yaw - 0.65, 1.02, 18.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		# Wave I-8 Title-Screen starboard harbour staging: place cargo crane on the unobstructed right-hand
		# (starboard-view, u < 0) waterfront quay aiming its jib over the channel toward the moored Brigantine!
		var port_crane_dir := (basis * Vector3(0.96, 0.0, 0.28)).normalized()
		if _place_harbour_crane(island, basis, "HarbourCrane_Quay",
				-23.0, -42.0, 8.0, port_crane_dir, 1.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		if _place_smuggler_hoard(island, basis, "SmugglerHoard_Bluff",
				-40.0, -44.0, landing_yaw + 0.55, 1.0, 16.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		# Wave I-7 maritime reef warning: shipwreck bell-buoy beacon marking Port Scoundrel's outer harbour mouth!
		if _place_reef_beacon(island, basis, "ReefBeacon_HarbourMouth",
				-58.0, -64.0, landing_yaw + 0.50, 1.0, 24.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		# Wave I-9 harbour life choreography: western beach careening slipway & eastern cove stilt fishing hut!
		var port_drydock_dir := (basis * Vector3(-0.35, 0.0, -0.94)).normalized()
		if _place_ship_drydock(island, basis, "ShipDrydock_WestBeach",
				-40.0, -55.0, 18.0, port_drydock_dir, 1.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		var port_fish_dir := (basis * Vector3(0.48, 0.0, -0.88)).normalized()
		if _place_fishing_hut(island, basis, "FishingHut_EastCove",
				37.0, -49.0, 16.0, port_fish_dir, 1.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		# Wave I-10 ridge warning belfry crowning Port Scoundrel's upper harbour terrace ridge!
		if _place_lookout_bell(island, basis, "LookoutBell_Ridge",
				3.0, 13.0, landing_yaw, 0.98, 12.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		# Wave I-11 tavern lane cargo cart (strictly clear of dock/plaza & Title Screen sightline!)
		# & outer eastern coastal point galleon anchor memorial!
		if _place_supply_cart(island, basis, "SupplyCart_Plaza",
				-38.0, -26.0, landing_yaw + 0.35, 0.98, 10.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		if _place_anchor_memorial(island, basis, "AnchorMemorial_Point",
				52.0, -34.0, landing_yaw - 0.52, 0.98, 14.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		# Wave I-12 stone well courtyard along the sunlit inland upper village lane behind the outpost plaza
		# (strictly clear of Title Screen foreground sightline, dock, Tavern, Merchant, Beacon & trails!).
		if _place_stone_well(island, basis, "StoneWell_Village",
				27.5, 17.5, landing_yaw - 0.35, 0.98, 10.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
	else:
		# Barnacle Haven (and custom outposts): eastern harbour sea arch + western bluff catwalk pier!
		if _place_sea_arch(island, basis, "CoastalSeaArch_Harbour",
				42.0, -34.0, landing_yaw - 0.58, Vector3(1.05, 1.05, 1.05), 10.0, -0.8, 0.2,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

		var bluff_out := (basis * Vector3(0.62, 0.0, -0.78)).normalized()
		if _place_cliff_catwalk(island, basis, "CliffCatwalkPier_Bluff",
				-48.0, -30.0, -18.0, 12.0, 3.5, 8.5, bluff_out, 1.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		# Wave I-3: Signal Brazier on east promontory & Beached Rowboat on outer cove beach!
		if _place_signal_brazier(island, basis, "SignalBrazier_Promontory",
				30.0, -24.0, landing_yaw - 0.35, 1.0, 16.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		if _place_beached_rowboat(island, basis, "BeachedRowboat_Harbour",
				-32.0, -34.0, landing_yaw + 0.65, 1.0, 16.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		# Wave I-5 coastal storytelling: giant tidal coral arch rising from Barnacle Haven's western shallows!
		if _place_coral_arch(island, basis, "TidalCoralArch_HarbourWest",
				-68.0, -58.0, landing_yaw + 0.62, 1.0, 18.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		# Wave I-6 harbour & cliff-spring choreography: eastern cove quay crane & sheltered ridge waterfall shrine!
		var barn_crane_dir := (basis * Vector3(0.25, 0.0, -0.97)).normalized()
		if _place_harbour_crane(island, basis, "HarbourCrane_Harbour",
				36.0, -43.0, 18.0, barn_crane_dir, 1.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		var barn_shrine_dir := (basis * Vector3(0.0, 0.0, -1.0)).normalized()
		if _place_waterfall_shrine(island, basis, "CascadeShrine_Ridge",
				16.0, 18.0, 18.0, 14.0, 2.5, 32.0, barn_shrine_dir, 0.98,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		# Wave I-7 coastal watchtower & eastern shoal warning beacon!
		if _place_fort_watchtower(island, basis, "FortWatchtower_Headland",
				44.0, 2.0, landing_yaw - 0.85, 0.98, 22.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		if _place_reef_beacon(island, basis, "ReefBeacon_Shoal",
				64.0, -56.0, landing_yaw - 0.55, 1.0, 24.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		# Wave I-9 coastal village choreography: sheltered cove careening slipway & eastern shore fishing hut!
		var barn_drydock_dir := (basis * Vector3(-0.35, 0.0, -0.94)).normalized()
		if _place_ship_drydock(island, basis, "ShipDrydock_Cove",
				-42.0, -54.0, 18.0, barn_drydock_dir, 1.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		var barn_fish_dir := (basis * Vector3(0.75, 0.0, -0.66)).normalized()
		if _place_fishing_hut(island, basis, "FishingHut_EastShore",
				57.0, -33.5, 16.0, barn_fish_dir, 1.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		# Wave I-10 ridge warning belfry overlooking Barnacle Haven's harbour terrace!
		if _place_lookout_bell(island, basis, "LookoutBell_Bluff",
				4.0, 12.0, landing_yaw, 0.96, 14.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		# Wave I-11 harbour trading supply cart & western harbour headland galleon anchor memorial!
		if _place_supply_cart(island, basis, "SupplyCart_Harbour",
				46.0, -24.0, landing_yaw - 0.44, 0.98, 14.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		if _place_anchor_memorial(island, basis, "AnchorMemorial_Point",
				-50.0, -44.0, landing_yaw + 0.58, 0.98, 14.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		# Wave I-12 sunlit harbour village green stone well & western harbour bluff cannon bastion!
		if _place_stone_well(island, basis, "StoneWell_Harbour",
				7.5, -4.5, landing_yaw - 0.25, 0.98, 10.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
		var barn_bast_dir := (basis * Vector3(-0.35, 0.0, -0.94)).normalized()
		if _place_cannon_bastion(island, basis, "CannonBastion_Bluff",
				-41.0, -35.5, 10.0, barn_bast_dir, 0.98,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# 2 mossy boulder clusters along outer beach verges (strictly outside harbour keepouts).
	var boulder_uvs: Array[Vector2] = [
		Vector2(-44.0 * clampf(scale_r, 0.85, 1.25), -26.0 * clampf(scale_r, 0.85, 1.25)),
		Vector2(44.0 * clampf(scale_r, 0.85, 1.25), -14.0 * clampf(scale_r, 0.85, 1.25)),
	]
	for bi in boulder_uvs.size():
		if _place_boulder_cluster(island, basis, "MossyBoulderCluster_%d" % bi,
				boulder_uvs[bi].x, boulder_uvs[bi].y, 14.0, rng.randf_range(0.88, 1.12),
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# Wave I-4 skyline choreography: rear summit crag, coastal watchpost & backdrop strata rib!
	if _place_summit_crag(island, basis, "SummitCrag_Peak",
			-22.0 * scale_r, 22.0 * scale_r, 22.0 * scale_r, 18.0 * scale_r,
			24.0, 64.0, landing_yaw - 0.32, 0.98,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	var outpost_wp_dir := (basis * Vector3(0.55, 0.0, -0.84)).normalized()
	if _place_pirate_watchpost(island, basis, "PirateWatchpost_Overlook",
			-34.0 * scale_r, 2.0 * scale_r, 18.0 * scale_r, 22.0 * scale_r,
			10.0, 38.0, outpost_wp_dir, 0.96,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	var outpost_rib_dir := (basis * Vector3(0.0, 0.0, -1.0)).normalized()
	if _place_upper_strata_rib(island, basis, "UpperStrataRib_Ridge",
			0.0, 16.0 * scale_r, 28.0 * scale_r, 16.0 * scale_r,
			16.0, 48.0, outpost_rib_dir, 1.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	return count


static func _populate_smuggler_cove(island: Island, basis: Basis, landing_yaw: float,
		scale_r: float, placed: Array[Vector3], keepout_zones: Array[Vector3],
		rng: RandomNumberGenerator, prop_body: StaticBody3D, props_root: Node3D,
		foliage_cache: Dictionary, landmark_cache: Dictionary) -> int:
	var count := 0

	# HERO: CliffCatwalkPier cantilevered off the eastern amphitheatre cliff overlooking hidden beach!
	var cove_inward := (basis * Vector3(-0.88, 0.0, -0.47)).normalized()
	if _place_cliff_catwalk(island, basis, "CliffCatwalkPier_Cove",
			16.0 * scale_r, 34.0 * scale_r, -12.0 * scale_r, 12.0 * scale_r,
			3.5, 10.5, cove_inward, 1.04,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-3: Pirate Warning Gibbet guarding the amphitheatre entrance & Beached Rowboat on hidden beach!
	if _place_pirate_gibbet(island, basis, "PirateGibbet_Gate",
			-20.0 * scale_r, -24.0 * scale_r, landing_yaw + 0.38, 1.04, 16.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_beached_rowboat(island, basis, "BeachedRowboat_Hidden",
			11.0 * scale_r, -16.0 * scale_r, landing_yaw - 0.85, 1.0, 14.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Grounded wide buttresses anchoring both western & eastern amphitheatre headland rims cleanly.
	var west_dir := (basis * Vector3(0.68, 0.0, -0.73)).normalized()
	if _place_cliff_buttress_wide(island, basis, "CliffButtressWide_West",
			-28.0 * scale_r, -14.0 * scale_r, 16.0, 14.0, 5.0, 26.0, west_dir, 1.02, 5.5,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	var east_dir := (basis * Vector3(-0.55, 0.0, -0.84)).normalized()
	if _place_cliff_buttress_wide(island, basis, "CliffButtressWide_East",
			32.0 * scale_r, -20.0 * scale_r, 16.0, 14.0, 5.0, 26.0, east_dir, 1.00, 5.5,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# 2 mossy boulder clusters flanking the hidden pocket beach.
	var boulder_uvs: Array[Vector2] = [
		Vector2(-15.0 * scale_r, -26.0 * scale_r),
		Vector2(16.0 * scale_r, -24.0 * scale_r),
	]
	for bi in boulder_uvs.size():
		if _place_boulder_cluster(island, basis, "MossyBoulderCluster_%d" % bi,
				boulder_uvs[bi].x, boulder_uvs[bi].y, 12.0, rng.randf_range(0.88, 1.12),
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# Wave I-4 skyline choreography: rear amphitheatre crag, western watchpost & wall strata ribs!
	if _place_summit_crag(island, basis, "SummitCrag_Amphitheatre",
			8.0 * scale_r, 28.0 * scale_r, 24.0 * scale_r, 18.0 * scale_r,
			34.0, 72.0, landing_yaw + 0.28, 1.06,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	var cove_wp_dir := (basis * Vector3(0.65, 0.0, -0.76)).normalized()
	if _place_pirate_watchpost(island, basis, "PirateWatchpost_Cove",
			-24.0 * scale_r, -4.0 * scale_r, 16.0 * scale_r, 22.0 * scale_r,
			12.0, 42.0, cove_wp_dir, 1.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	var cove_rib_specs: Array[Array] = [
		["UpperStrataRib_CoveW", -20.0 * scale_r, 10.0 * scale_r, Vector3(0.75, 0.0, -0.66), 1.04],
		["UpperStrataRib_CoveE", 20.0 * scale_r, 10.0 * scale_r, Vector3(-0.75, 0.0, -0.66), 1.04],
	]
	for spec: Array in cove_rib_specs:
		var rib_dir := (basis * (spec[3] as Vector3)).normalized()
		if _place_upper_strata_rib(island, basis, String(spec[0]), float(spec[1]), float(spec[2]),
				14.0 * scale_r, 16.0 * scale_r, 16.0, 56.0, rib_dir, float(spec[4]),
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# Wave I-5 coastal storytelling: smuggler's beach camp canopy tucked inside the hidden pocket cove!
	if _place_pirate_camp(island, basis, "PirateCamp_HiddenCove",
			-10.0 * scale_r, -9.0 * scale_r, landing_yaw - 0.55, 0.98, 16.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-6 harbour & smuggler choreography: cove landing crane + twin grotto & beach contraband hoards!
	var cove_crane_dir := (basis * Vector3(0.75, 0.0, -0.66)).normalized()
	if _place_harbour_crane(island, basis, "HarbourCrane_Cove",
			-15.0 * scale_r, -18.0 * scale_r, 16.0, cove_crane_dir, 0.98,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_smuggler_hoard(island, basis, "SmugglerHoard_Grotto",
			8.0 * scale_r, -3.5 * scale_r, landing_yaw - 0.65, 1.0, 12.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_smuggler_hoard(island, basis, "SmugglerHoard_Beach",
			19.0 * scale_r, -20.0 * scale_r, landing_yaw - 0.52, 0.98, 18.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-9 smuggler slipway choreography: hidden cove careening beach drydock!
	var smug_drydock_dir := (basis * Vector3(0.45, 0.0, -0.89)).normalized()
	if _place_ship_drydock(island, basis, "ShipDrydock_Cove",
			22.0 * scale_r, -43.5 * scale_r, 16.0 * scale_r, smug_drydock_dir, 1.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-10 hidden amphitheatre cove landing jetty jutting out from the secret pocket beach!
	var smug_jetty_dir := (basis * Vector3(0.0, 0.0, -1.0)).normalized()
	if _place_smuggler_jetty(island, basis, "SmugglerJetty_Cove",
			0.0, -24.5 * scale_r, 14.0 * scale_r, smug_jetty_dir, 1.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-11 pirate cargo handcart tucked near Smuggler's Cove hidden beach landing & grotto mouth!
	if _place_supply_cart(island, basis, "SupplyCart_Cove",
			-10.0 * scale_r, -2.0 * scale_r, landing_yaw + 0.42, 0.98, 12.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-12 pirate treasure vault door tucked into Smuggler's Cove amphitheatre rock wall (clear of SmugglersGrotto)!
	var smug_vault_dir := (basis * Vector3(-0.78, 0.0, -0.62)).normalized()
	if _place_treasure_vault(island, basis, "TreasureVault_Cove",
			20.0 * scale_r, 4.0 * scale_r, 14.0 * scale_r, 14.0 * scale_r, smug_vault_dir, 1.02,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	return count


static func _populate_treasure_peak(island: Island, basis: Basis, landing_yaw: float,
		scale_r: float, placed: Array[Vector3], keepout_zones: Array[Vector3],
		rng: RandomNumberGenerator, prop_body: StaticBody3D, props_root: Node3D,
		foliage_cache: Dictionary, landmark_cache: Dictionary) -> int:
	var count := 0

	# HERO: Grounded bottom-heavy A-frame CliffButtressWide anchored right at the grassy cliff foot
	# (seamless across all 24h sun angles & on-foot close-ups; Local-GPU M19B polish).
	var pref_dir := (basis * Vector3(0.45, 0.0, -0.89)).normalized()
	if _place_cliff_buttress_wide(island, basis, "CliffButtressWide_Cove",
			-18.0 * scale_r, -10.0 * scale_r, 14.0, 14.0, 3.0, 9.5, pref_dir, 0.88, 4.8,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-11 (Pass I-Q4 onfoot_cutlass_trail cliff-wall sculpting): sculpted bottom-heavy buttress
	# anchored flush into the lower-mid central cliff wall behind Golden Cove trail & rocky cliff-foot boulders!
	var trail_wall_dir := (basis * Vector3(-0.22, 0.0, -0.98)).normalized()
	if _place_cliff_buttress_wide(island, basis, "CliffButtressWide_TrailWall",
			1.5 * scale_r, 0.0, 10.0 * scale_r, 6.0 * scale_r, 3.5, 14.0, trail_wall_dir, 0.86, 3.8,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_boulder_cluster(island, basis, "MossyBoulderCluster_TrailFoot",
			-12.0 * scale_r, -18.0 * scale_r, 8.0, 0.92,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-3: Half-buried weathered clinker pirate rowboat on Golden Cove's sunlit beach!
	if _place_beached_rowboat(island, basis, "BeachedRowboat_GoldenCove",
			14.0 * scale_r, -32.0 * scale_r, landing_yaw - 0.62, 0.96, 14.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# 2 mossy boulder clusters framing Golden Cove & the sunlit palm verge.
	var boulder_uvs: Array[Vector2] = [
		Vector2(-24.0 * scale_r, -24.0 * scale_r),
		Vector2(24.0 * scale_r, -20.0 * scale_r),
	]
	for bi in boulder_uvs.size():
		if _place_boulder_cluster(island, basis, "MossyBoulderCluster_%d" % bi,
				boulder_uvs[bi].x, boulder_uvs[bi].y, 12.0, rng.randf_range(0.84, 1.06),
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# Wave I-4/I-8 skyline choreography: keep Cutlass Cay's sheer central spire pure & un-stilted
	# (watchpost relocated to Sovereign's Bastion's spacious terrace per Local-GPU M19B), with stepped limestone rib!
	var peak_rib_dir := (basis * Vector3(0.15, 0.0, -0.99)).normalized()
	if _place_upper_strata_rib(island, basis, "UpperStrataRib_Main",
			2.0 * scale_r, 6.0 * scale_r, 20.0 * scale_r, 16.0 * scale_r,
			16.0, 56.0, peak_rib_dir, 0.92,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-5 coastal storytelling: treasure-hunter camp on Golden Cove & vibrant tidal coral arch!
	if _place_pirate_camp(island, basis, "PirateCamp_GoldenCove",
			-16.0 * scale_r, -34.0 * scale_r, landing_yaw - 0.32, 0.96, 14.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_coral_arch(island, basis, "TidalCoralArch_Cove",
			42.0 * scale_r, -44.0 * scale_r, landing_yaw - 0.58, 0.96, 16.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-6 smuggler storytelling: tarpaulin contraband stash tucked on Golden Cove's eastern flank!
	if _place_smuggler_hoard(island, basis, "SmugglerHoard_Cove",
			29.0 * scale_r, -38.0 * scale_r, landing_yaw - 0.58, 0.96, 12.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-7 relic sanctuary: ancient compass monolith ring crowning Cutlass Cay's western ridge terrace!
	if _place_compass_monolith(island, basis, "CompassMonolith_Ridge",
			-23.7 * scale_r, -10.3 * scale_r, landing_yaw + 0.42, 0.94, 16.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-9 coastal village choreography: palm-thatched stilt fishing hut on Cutlass Cay's western cove!
	var cay_fish_dir := (basis * Vector3(-0.78, 0.0, -0.62)).normalized()
	if _place_fishing_hut(island, basis, "FishingHut_Cove",
			-45.5 * scale_r, -24.0 * scale_r, 16.0 * scale_r, cay_fish_dir, 0.96,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-10 cove landing jetty welcoming ships onto Golden Cove's sunlit western landing shore!
	var cay_jetty_dir := (basis * Vector3(-0.62, 0.0, -0.78)).normalized()
	if _place_smuggler_jetty(island, basis, "SmugglerJetty_Landing",
			-32.0 * scale_r, -38.0 * scale_r, 16.0 * scale_r, cay_jetty_dir, 0.96,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-11 camp supply cart near Golden Cove clearing & ancient sundial plaza on eastern shoulder terrace!
	if _place_supply_cart(island, basis, "SupplyCart_Camp",
			36.0 * scale_r, -27.0 * scale_r, landing_yaw - 0.48, 0.96, 12.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_sundial_plaza(island, basis, "SundialPlaza_Ridge",
			37.0 * scale_r, -8.0 * scale_r, landing_yaw - 0.45, 0.94, 14.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-12 shipwreck crow's-nest lookout mast crowning Cutlass Cay's eastern reef point!
	if _place_crow_nest_mast(island, basis, "CrowNestMast_Point",
			48.0 * scale_r, 11.0 * scale_r, landing_yaw - 0.52, 0.94, 14.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	return count


static func _populate_sea_arch(island: Island, basis: Basis, landing_yaw: float,
		scale_r: float, placed: Array[Vector3], keepout_zones: Array[Vector3],
		rng: RandomNumberGenerator, prop_body: StaticBody3D, props_root: Node3D,
		foliage_cache: Dictionary, landmark_cache: Dictionary) -> int:
	var count := 0

	# TWO HERO Coastal Sea Arches straddling the bright sandy tide bay & outer eastern headland!
	if _place_sea_arch(island, basis, "CoastalSeaArch_Main",
			0.0, -island.island_radius * 0.44, landing_yaw, Vector3(1.24, 1.24, 1.24),
			11.5, -0.6, 0.4,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	if _place_sea_arch(island, basis, "CoastalSeaArch_Outer",
			island.island_radius * 0.56, -island.island_radius * 0.56, landing_yaw + 0.62,
			Vector3(1.02, 1.02, 1.02), 9.5, -0.6, 0.4,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-6 (Local-GPU M16 catch): bottom-heavy A-frame CliffButtressWide on western bluff (zero underside gap!).
	var pref_dir := (basis * Vector3(0.55, 0.0, -0.84)).normalized()
	if _place_cliff_buttress_wide(island, basis, "CliffButtressWide_WestBluff",
			-24.0 * scale_r, -4.0 * scale_r, 14.0, 14.0, 8.0, 34.0, pref_dir, 1.02, 5.2,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_beached_rowboat(island, basis, "BeachedRowboat_Bay",
			-14.0 * scale_r, -32.0 * scale_r, landing_yaw + 0.54, 0.98, 14.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	var boulder_uvs: Array[Vector2] = [
		Vector2(-20.0 * scale_r, -28.0 * scale_r),
		Vector2(22.0 * scale_r, -22.0 * scale_r),
	]
	for bi in boulder_uvs.size():
		if _place_boulder_cluster(island, basis, "MossyBoulderCluster_%d" % bi,
				boulder_uvs[bi].x, boulder_uvs[bi].y, 12.0, rng.randf_range(0.88, 1.12),
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# Wave I-4 skyline choreography: western crest summit crag & eastern bay-wall strata rib!
	if _place_summit_crag(island, basis, "SummitCrag_Crest",
			-18.0 * scale_r, 10.0 * scale_r, 18.0 * scale_r, 18.0 * scale_r,
			30.0, 68.0, landing_yaw - 0.35, 1.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	var arch_rib_dir := (basis * Vector3(-0.62, 0.0, -0.78)).normalized()
	if _place_upper_strata_rib(island, basis, "UpperStrataRib_Main",
			18.0 * scale_r, 8.0 * scale_r, 16.0 * scale_r, 18.0 * scale_r,
			16.0, 50.0, arch_rib_dir, 1.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-5 coastal storytelling: beach camp on Tern Tide Bay & western reef tidal coral arch!
	if _place_pirate_camp(island, basis, "PirateCamp_TideBay",
			-26.0 * scale_r, -38.0 * scale_r, landing_yaw - 0.52, 1.0, 16.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_coral_arch(island, basis, "TidalCoralArch_Reef",
			-46.0 * scale_r, -50.0 * scale_r, landing_yaw + 0.58, 1.04, 20.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-7 maritime reef warning: shipwreck bell-buoy beacon marking the outer channel shoal!
	if _place_reef_beacon(island, basis, "ReefBeacon_Channel",
			-28.0 * scale_r, -64.0 * scale_r, landing_yaw + 0.40, 1.0, 26.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-9 coastal village choreography: weathered stilt fishing hut on Tern Tide Bay!
	var gulls_fish_dir := (basis * Vector3(0.25, 0.0, -0.97)).normalized()
	if _place_fishing_hut(island, basis, "FishingHut_Bay",
			16.0 * scale_r, -44.0 * scale_r, 16.0 * scale_r, gulls_fish_dir, 1.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-10 cove landing jetty extending into Tern Tide Bay!
	var gulls_jetty_dir := (basis * Vector3(0.22, 0.0, -0.98)).normalized()
	if _place_smuggler_jetty(island, basis, "SmugglerJetty_Bay",
			-16.5 * scale_r, -56.5 * scale_r, 14.0 * scale_r, gulls_jetty_dir, 1.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-11 sunken galleon anchor memorial guarding Gull's Arch sunlit promontory!
	if _place_anchor_memorial(island, basis, "AnchorMemorial_Headland",
			38.0 * scale_r, -20.0 * scale_r, landing_yaw - 0.45, 0.98, 14.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-12 shipwreck crow's-nest lookout mast perched on Gull's Arch outer western bay point!
	if _place_crow_nest_mast(island, basis, "CrowNestMast_Bay",
			-42.0 * scale_r, -28.0 * scale_r, landing_yaw + 0.62, 0.98, 16.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	return count


static func _populate_crescent_lagoon(island: Island, basis: Basis, landing_yaw: float,
		scale_r: float, placed: Array[Vector3], keepout_zones: Array[Vector3],
		rng: RandomNumberGenerator, prop_body: StaticBody3D, props_root: Node3D,
		foliage_cache: Dictionary, landmark_cache: Dictionary) -> int:
	var count := 0

	# HERO: CoastalSeaArch framing the sunlit turquoise lagoon mouth!
	if _place_sea_arch(island, basis, "CoastalSeaArch_Lagoon",
			0.0, -island.island_radius * 0.58, landing_yaw, Vector3(1.18, 1.18, 1.18),
			11.0, -0.6, 0.4,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# HERO: ImpaledShipwreckBow grounded dramatically on the outer eastern reef horn!
	if _place_shipwreck_bow(island, basis, "ImpaledShipwreckBow_Reef",
			island.island_radius * 0.62, -island.island_radius * 0.34, landing_yaw - 0.52,
			1.05, 8.0, -0.8, 14.0, 18.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-3: Colossal bleached Leviathan Ribcage on west coral horn + Beached Rowboat on east cove!
	if _place_leviathan_ribcage(island, basis, "LeviathanRibcage_Horn",
			-34.0 * scale_r, -18.0 * scale_r, landing_yaw + 0.58, 1.06, 18.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_beached_rowboat(island, basis, "BeachedRowboat_Lagoon",
			24.0 * scale_r, -28.0 * scale_r, landing_yaw - 0.70, 1.0, 16.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# 2 mossy boulder clusters along the curved coral-sand horns.
	var boulder_uvs: Array[Vector2] = [
		Vector2(-34.0 * scale_r, -16.0 * scale_r),
		Vector2(28.0 * scale_r, -24.0 * scale_r),
	]
	for bi in boulder_uvs.size():
		if _place_boulder_cluster(island, basis, "MossyBoulderCluster_%d" % bi,
				boulder_uvs[bi].x, boulder_uvs[bi].y, 14.0, rng.randf_range(0.92, 1.16),
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# Wave I-5 lagoon & reef storytelling: sunlit beach camp, twin inner lagoon coral arches & sunken galleon stern!
	if _place_pirate_camp(island, basis, "PirateCamp_Lagoon",
			22.0 * scale_r, -34.0 * scale_r, landing_yaw + 0.75, 1.04, 20.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_sunken_stern(island, basis, "SunkenStern_Reef",
			48.0 * scale_r, -35.0 * scale_r, landing_yaw - 0.85, 1.08, 26.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_coral_arch(island, basis, "TidalCoralArch_LagoonW",
			-12.0 * scale_r, -16.0 * scale_r, landing_yaw + 0.55, 1.08, 22.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_coral_arch(island, basis, "TidalCoralArch_LagoonE",
			11.0 * scale_r, -11.0 * scale_r, landing_yaw - 0.55, 1.06, 22.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-7 maritime reef warning: shipwreck bell-buoy beacon marking Crescent Atoll's lagoon entry!
	if _place_reef_beacon(island, basis, "ReefBeacon_LagoonEntry",
			-30.0 * scale_r, -52.0 * scale_r, landing_yaw + 0.48, 1.04, 30.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-9 coastal village choreography: palm-thatched stilt fishing hut on Crescent Atoll's lagoon mouth!
	var atoll_fish_dir := (basis * Vector3(-0.35, 0.0, -0.94)).normalized()
	if _place_fishing_hut(island, basis, "FishingHut_Lagoon",
			16.5 * scale_r, -53.0 * scale_r, 16.0 * scale_r, atoll_fish_dir, 1.04,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-10 cove landing jetty & lagoon-rim arched footbridge choreography!
	var atoll_jetty_dir := (basis * Vector3(0.15, 0.0, -0.99)).normalized()
	if _place_smuggler_jetty(island, basis, "SmugglerJetty_Lagoon",
			-19.0 * scale_r, -56.5 * scale_r, 16.0 * scale_r, atoll_jetty_dir, 1.04,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_trail_footbridge(island, basis, "TrailFootbridge_Lagoon",
			-13.5 * scale_r, 15.8 * scale_r, landing_yaw + atan2(0.93, 0.37), 1.06, 12.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-11 sunlit ancient sundial plaza crowning Crescent Atoll's lush northern lagoon rim!
	if _place_sundial_plaza(island, basis, "SundialPlaza_Atoll",
			20.0 * scale_r, 10.0 * scale_r, landing_yaw - 0.40, 1.04, 16.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-12 shipwreck crow's-nest lookout mast crowning Crescent Atoll's outer western coral horn!
	if _place_crow_nest_mast(island, basis, "CrowNestMast_Reef",
			-50.0 * scale_r, -19.0 * scale_r, landing_yaw + 0.58, 1.04, 18.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	return count


static func _populate_fort_rock(island: Island, basis: Basis, landing_yaw: float,
		scale_r: float, placed: Array[Vector3], keepout_zones: Array[Vector3],
		rng: RandomNumberGenerator, prop_body: StaticBody3D, props_root: Node3D,
		foliage_cache: Dictionary, landmark_cache: Dictionary) -> int:
	var count := 0

	# Wave I-7 grounding polish: 2 bottom-heavy A-frame CliffButtressWides fortifying watch mesa flanks (zero shelf gap!).
	var flank_buttress_specs: Array[Array] = [
		["CliffButtressWide_West", -28.0 * scale_r, -8.0 * scale_r, Vector3(-0.78, 0.0, -0.62), 1.02],
		["CliffButtressWide_East", 28.0 * scale_r, -8.0 * scale_r, Vector3(0.78, 0.0, -0.62), 1.02],
	]
	for spec: Array in flank_buttress_specs:
		var pref_dir := (basis * (spec[3] as Vector3)).normalized()
		if _place_cliff_buttress_wide(island, basis, String(spec[0]), float(spec[1]), float(spec[2]),
				16.0, 14.0, 6.5, 32.0, pref_dir, float(spec[4]), 5.5,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# Wave I-3: Signal Brazier watching the assault cove & Pirate Warning Gibbet flanking Powder Cove!
	if _place_signal_brazier(island, basis, "SignalBrazier_Watch",
			-19.0 * scale_r, -24.0 * scale_r, landing_yaw + 0.32, 1.02, 14.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_pirate_gibbet(island, basis, "PirateGibbet_Cove",
			20.0 * scale_r, -30.0 * scale_r, landing_yaw - 0.38, 1.02, 14.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# 2 CliffButtressWides fortifying the steep outer bastion flanks.
	var buttress_specs: Array[Array] = [
		["CliffButtressWide_West", -34.0 * scale_r, 12.0 * scale_r, Vector3(-0.92, 0.0, -0.38), 1.04],
		["CliffButtressWide_East", 34.0 * scale_r, 12.0 * scale_r, Vector3(0.92, 0.0, -0.38), 1.04],
	]
	for spec: Array in buttress_specs:
		var pref_dir := (basis * (spec[3] as Vector3)).normalized()
		if _place_cliff_buttress_wide(island, basis, String(spec[0]), float(spec[1]), float(spec[2]),
				16.0, 14.0, 7.0, 34.0, pref_dir, float(spec[4]), 6.8,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# 2 mossy boulder clusters flanking the landing cove (strictly clear of the assault ramp).
	var boulder_uvs: Array[Vector2] = [
		Vector2(-22.0 * scale_r, -38.0 * scale_r),
		Vector2(22.0 * scale_r, -38.0 * scale_r),
	]
	for bi in boulder_uvs.size():
		if _place_boulder_cluster(island, basis, "MossyBoulderCluster_%d" % bi,
				boulder_uvs[bi].x, boulder_uvs[bi].y, 12.0, rng.randf_range(0.88, 1.12),
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# Wave I-4 skyline choreography: rear watch-ridge crag, seaward spur watchpost & upper fort ribs!
	if _place_summit_crag(island, basis, "SummitCrag_RearPeak",
			-6.0 * scale_r, 30.0 * scale_r, 30.0 * scale_r, 18.0 * scale_r,
			24.0, 62.0, landing_yaw - 0.25, 0.98,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	var fort_wp_dir := (basis * Vector3(-0.62, 0.0, -0.78)).normalized()
	if _place_pirate_watchpost(island, basis, "PirateWatchpost_Flank",
			-30.0 * scale_r, 8.0 * scale_r, 18.0 * scale_r, 20.0 * scale_r,
			12.0, 38.0, fort_wp_dir, 0.98,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	var fort_rib_specs: Array[Array] = [
		["UpperStrataRib_FortW", -24.0 * scale_r, 16.0 * scale_r, 16.0, 50.0, Vector3(-0.72, 0.0, -0.69), 1.02],
		["UpperStrataRib_FortE", 22.0 * scale_r, 16.0 * scale_r, 16.0, 46.0, Vector3(0.72, 0.0, -0.69), 1.02],
	]
	for spec: Array in fort_rib_specs:
		var rib_dir := (basis * (spec[5] as Vector3)).normalized()
		if _place_upper_strata_rib(island, basis, String(spec[0]), float(spec[1]), float(spec[2]),
				16.0 * scale_r, 16.0 * scale_r, float(spec[3]), float(spec[4]), rib_dir, float(spec[6]),
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# Wave I-7 sea-fort choreography: ruined seaward bluff watchtower & harbour chain-boom anchor pylon!
	if _place_fort_watchtower(island, basis, "FortWatchtower_Flank",
			21.0 * scale_r, -19.0 * scale_r, landing_yaw - 0.45, 1.0, 18.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_volcanic_chain_pylon(island, basis, "VolcanicChainPylon_Harbour",
			-32.0 * scale_r, -24.0 * scale_r, landing_yaw + 0.60, 1.02, 20.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-10 ridge warning belfry commanding Ironwatch Fort's upper western mesa crown!
	if _place_lookout_bell(island, basis, "LookoutBell_Mesa",
			-10.5 * scale_r, 16.5 * scale_r, landing_yaw + 0.35, 1.0, 14.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-12 garrison stone well courtyard & seaward cannon bastion battery overlooking Powder Cove!
	if _place_stone_well(island, basis, "StoneWell_Garrison",
			16.0 * scale_r, 4.5 * scale_r, landing_yaw - 0.30, 1.0, 12.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	var fort_batt_dir := (basis * Vector3(-0.45, 0.0, -0.89)).normalized()
	if _place_cannon_bastion(island, basis, "CannonBastion_Battery",
			-32.0 * scale_r, -13.0 * scale_r, 14.0 * scale_r, fort_batt_dir, 1.02,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	return count


static func _populate_wreck_shoal(island: Island, basis: Basis, landing_yaw: float,
		scale_r: float, placed: Array[Vector3], keepout_zones: Array[Vector3],
		rng: RandomNumberGenerator, prop_body: StaticBody3D, props_root: Node3D,
		foliage_cache: Dictionary, landmark_cache: Dictionary) -> int:
	var count := 0

	# HERO: ImpaledShipwreckBow wedged boldly onto the rocky crest above the shoal!
	if _place_shipwreck_bow(island, basis, "ImpaledShipwreckBow_Main",
			6.0 * scale_r, -4.0 * scale_r, landing_yaw + 0.34,
			1.12, 7.8, 1.2, 26.0, 12.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-3: Giant Leviathan Ribcage arcing out of the west sandbar & warning gibbet on reef spit!
	if _place_leviathan_ribcage(island, basis, "LeviathanRibcage_Shoal",
			-16.0 * scale_r, -20.0 * scale_r, landing_yaw + 0.52, 0.94, 14.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_pirate_gibbet(island, basis, "PirateGibbet_Reef",
			18.0 * scale_r, -16.0 * scale_r, landing_yaw - 0.42, 0.96, 12.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# 2 mossy boulder clusters along the broad sandy shoal apron.
	var boulder_uvs: Array[Vector2] = [
		Vector2(-18.0 * scale_r, -16.0 * scale_r),
		Vector2(24.0 * scale_r, -10.0 * scale_r),
	]
	for bi in boulder_uvs.size():
		if _place_boulder_cluster(island, basis, "MossyBoulderCluster_%d" % bi,
				boulder_uvs[bi].x, boulder_uvs[bi].y, 12.0, rng.randf_range(0.82, 1.04),
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# Wave I-5 coastal storytelling: heeled gilded galleon stern grounded in the eastern surf shoal!
	if _place_sunken_stern(island, basis, "SunkenStern_Shoal",
			38.0 * scale_r, -52.0 * scale_r, landing_yaw - 0.62, 1.0, 18.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-6 smuggler storytelling: salvaged contraband hoard tucked on the eastern shoal shore!
	if _place_smuggler_hoard(island, basis, "SmugglerHoard_Salvage",
			42.0 * scale_r, -24.0 * scale_r, landing_yaw - 0.55, 0.94, 16.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-7 maritime reef warning: shipwreck bell-buoy beacon marking the western shoal sandbar!
	if _place_reef_beacon(island, basis, "ReefBeacon_Shoal",
			-48.0 * scale_r, -44.0 * scale_r, landing_yaw + 0.55, 0.96, 22.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-9 cursed shrine choreography: captain's skeleton throne commanding Wrecker's Shoal crest!
	if _place_skeleton_throne(island, basis, "SkeletonThrone_Shoal",
			-26.5 * scale_r, -2.0 * scale_r, landing_yaw + 0.48, 0.94, 16.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-10 ridge warning belfry crowning Wrecker's Shoal overlook crest!
	if _place_lookout_bell(island, basis, "LookoutBell_Peak",
			31.5 * scale_r, 10.5 * scale_r, landing_yaw - 0.55, 0.94, 14.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-11 sunken galleon anchor memorial crowning Wrecker's Shoal rocky wreck headland!
	if _place_anchor_memorial(island, basis, "AnchorMemorial_Shoal",
			-34.0 * scale_r, -20.0 * scale_r, landing_yaw + 0.48, 0.94, 14.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-12 shipwreck crow's-nest lookout mast rising above Wrecker's Shoal eastern wreck reef!
	if _place_crow_nest_mast(island, basis, "CrowNestMast_Shoal",
			46.0 * scale_r, -12.0 * scale_r, landing_yaw - 0.55, 0.94, 14.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	return count


static func _populate_sea_stack(island: Island, basis: Basis, landing_yaw: float,
		scale_r: float, placed: Array[Vector3], keepout_zones: Array[Vector3],
		rng: RandomNumberGenerator, prop_body: StaticBody3D, props_root: Node3D,
		foliage_cache: Dictionary, landmark_cache: Dictionary) -> int:
	var count := 0

	# HERO: ImpaledShipwreckBow wedged dramatically onto the rocky seaward fang shoulder!
	if _place_shipwreck_bow(island, basis, "ImpaledShipwreckBow_Fang",
			-12.0 * scale_r, -14.0 * scale_r, landing_yaw + 0.48,
			0.94, 6.8, 0.5, 24.0, 10.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# HERO: CoastalSeaArch straddling the shallow tide chasm off the starboard flank!
	if _place_sea_arch(island, basis, "CoastalSeaArch_Tooth",
			28.0 * scale_r, -18.0 * scale_r, landing_yaw - 0.55,
			Vector3(0.86, 0.86, 0.86), 8.2, -0.7, 0.3,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-3: Bleached Leviathan Ribcage half-submerged across the shallow seaward coral shelf!
	if _place_leviathan_ribcage(island, basis, "LeviathanRibcage_Shelf",
			4.0 * scale_r, -22.0 * scale_r, landing_yaw - 0.32, 0.86, 12.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-5 coastal storytelling: broken gilded galleon stern grounded on Siren's western shoal!
	if _place_sunken_stern(island, basis, "SunkenStern_Fang",
			-44.0 * scale_r, -40.0 * scale_r, landing_yaw + 0.72, 0.90, 16.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-7 maritime reef warning: shipwreck bell-buoy beacon guarding Siren's outer starboard reef!
	if _place_reef_beacon(island, basis, "ReefBeacon_Spire",
			46.0 * scale_r, -48.0 * scale_r, landing_yaw - 0.52, 0.94, 20.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-11 impaled galleon anchor memorial gripping Siren's Tooth seaward reef shoulder!
	if _place_anchor_memorial(island, basis, "AnchorMemorial_Fang",
			-36.0 * scale_r, -14.0 * scale_r, landing_yaw + 0.55, 0.88, 12.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-12 shipwreck crow's-nest lookout mast jutting from Siren's Tooth jagged reef skirt!
	if _place_crow_nest_mast(island, basis, "CrowNestMast_Fang",
			45.0 * scale_r, -4.0 * scale_r, landing_yaw - 0.45, 0.88, 12.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	return count


static func _populate_volcano_crag(island: Island, basis: Basis, landing_yaw: float,
		scale_r: float, placed: Array[Vector3], keepout_zones: Array[Vector3],
		rng: RandomNumberGenerator, prop_body: StaticBody3D, props_root: Node3D,
		foliage_cache: Dictionary, landmark_cache: Dictionary) -> int:
	var count := 0

	# Wave I-3 HERO: Jagged magma-veined Volcanic Obsidian Arch straddling the dark-ash caldera approach trail!
	if _place_volcanic_arch(island, basis, "VolcanicObsidianArch_Portal",
			0.0, -34.0 * scale_r, landing_yaw, 1.18, 18.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# 7 HERO VolcanicBasaltSpires erupting dramatically along all 3 radiating lava-flow ridges
	# & flanking the caldera approaches (strictly clear of VolcanoCaldera & VolcanicFumarole!).
	var spire_specs: Array[Array] = [
		# East lava-flow ridge (`rib_e`: (18, 10) -> (44, 22))
		[25.0 * scale_r, 14.0 * scale_r, 1.62, 0.45],
		[39.0 * scale_r, 20.0 * scale_r, 1.28, -0.82],
		# West lava-flow ridge (`rib_w`: (-18, 12) -> (-46, -6))
		[-25.0 * scale_r, 10.0 * scale_r, 1.58, 1.35],
		[-40.0 * scale_r, -2.0 * scale_r, 1.24, -1.90],
		# North lava-flow ridge (`rib_n`: (-4, 20) -> (10, 48))
		[2.0 * scale_r, 31.0 * scale_r, 1.72, 2.55],
		# Seaward caldera approach flanks
		[-20.0 * scale_r, -16.0 * scale_r, 1.42, -0.35],
		[20.0 * scale_r, -15.0 * scale_r, 1.38, 0.65],
	]

	for si in spire_specs.size():
		var sp: Array = spire_specs[si]
		var target_u := float(sp[0])
		var target_v := float(sp[1])
		var sc_base := clampf(float(sp[2]) + rng.randf_range(-0.08, 0.08), 1.15, 1.75)
		var yaw := landing_yaw + float(sp[3]) + rng.randf_range(-0.25, 0.25)
		if _place_basalt_spire(island, basis, "VolcanicBasaltSpire_%d" % si,
				target_u, target_v, yaw, sc_base, 18.0,
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1

	# Wave I-5 volcanic storytelling: twin molten obsidian cauldron shrines framing the caldera landing
	# approach & upper SE volcanic ridge trail (strictly clear of lava rivers, fumaroles & trails!).
	if _place_lava_shrine(island, basis, "LavaCauldronShrine_Approach",
			11.0 * scale_r, -41.0 * scale_r, landing_yaw - 0.25, 1.06, 24.0, 4.0, 16.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_lava_shrine(island, basis, "LavaCauldronShrine_Ridge",
			24.0 * scale_r, -36.0 * scale_r, landing_yaw + 0.35, 1.10, 28.0, 14.0, 34.0,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-7 volcanic chain-bridge choreography: twin obsidian chain pylons flanking Cinder Crag's ridge!
	if _place_volcanic_chain_pylon(island, basis, "VolcanicChainPylon_West",
			-34.0 * scale_r, -24.0 * scale_r, landing_yaw + 0.55, 1.14, 26.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_volcanic_chain_pylon(island, basis, "VolcanicChainPylon_East",
			36.0 * scale_r, -20.0 * scale_r, landing_yaw - 0.55, 1.14, 26.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-9 cursed shrine choreography: captain's skeleton throne on Cinder Crag's western caldera bench!
	if _place_skeleton_throne(island, basis, "SkeletonThrone_Caldera",
			-28.0 * scale_r, -26.0 * scale_r, landing_yaw + 0.35, 1.12, 18.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-10 ridge warning belfry overseeing Cinder Crag's eastern volcanic approach bench!
	if _place_lookout_bell(island, basis, "LookoutBell_Approach",
			26.5 * scale_r, -26.5 * scale_r, landing_yaw - 0.35, 1.08, 16.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	# Wave I-11 volcanic obsidian fissure vents flanking Cinder Crag's approach & lava-flow ridges!
	if _place_obsidian_vent(island, basis, "ObsidianVent_Approach",
			-14.0 * scale_r, -44.0 * scale_r, landing_yaw + 0.32, 1.08, 16.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_obsidian_vent(island, basis, "ObsidianVent_WestRidge",
			-38.0 * scale_r, -30.0 * scale_r, landing_yaw + 0.52, 1.12, 16.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	if _place_obsidian_vent(island, basis, "ObsidianVent_EastBench",
			38.0 * scale_r, -22.0 * scale_r, landing_yaw - 0.48, 1.12, 16.0 * scale_r,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1
	return count


static func _populate_palm_atoll(island: Island, basis: Basis, landing_yaw: float,
		scale_r: float, placed: Array[Vector3], keepout_zones: Array[Vector3],
		rng: RandomNumberGenerator, prop_body: StaticBody3D, props_root: Node3D,
		foliage_cache: Dictionary, landmark_cache: Dictionary) -> int:
	var count := 0

	# 1 CoastalSeaArch framing the sunlit atoll channel entrance + 2 mossy boulder clusters.
	if _place_sea_arch(island, basis, "CoastalSeaArch_Atoll",
			0.0, -island.island_radius * 0.62, landing_yaw, Vector3(1.06, 1.06, 1.06),
			10.0, -0.6, 0.4,
			placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
		count += 1

	var boulder_uvs: Array[Vector2] = [
		Vector2(-24.0 * scale_r, -26.0 * scale_r),
		Vector2(24.0 * scale_r, 12.0 * scale_r),
	]
	for bi in boulder_uvs.size():
		if _place_boulder_cluster(island, basis, "MossyBoulderCluster_%d" % bi,
				boulder_uvs[bi].x, boulder_uvs[bi].y, 14.0, rng.randf_range(0.88, 1.12),
				placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache):
			count += 1
	return count


# ============================================================ trail storytelling markers

static func _populate_trail_markers(island: Island, landing_yaw: float,
		trail_markers: Array[Dictionary], placed: Array[Vector3],
		keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> int:
	if trail_markers.is_empty():
		return 0
	var spawned := 0
	var lantern_idx := 0
	var cairn_idx := 0

	for entry in trail_markers:
		if spawned >= MAX_TRAIL_MARKERS:
			break
		var pos_var: Variant = entry.get("pos", entry.get("position", null))
		var pos := Vector3.ZERO
		if pos_var is Vector3:
			pos = pos_var as Vector3
		elif pos_var is Vector2:
			var v2 := pos_var as Vector2
			pos = Vector3(v2.x, 0.0, v2.y)
		else:
			continue
		if _in_exclusion(pos.x, pos.z, keepout_zones):
			continue
		var h := island.surface_height(pos.x, pos.z)
		if h < 0.60:
			continue
		if island.surface_normal(pos.x, pos.z).y < 0.70:
			continue

		var kind := StringName(String(entry.get("kind", entry.get("type", &"cairn"))))
		var yaw_var: Variant = entry.get("yaw", entry.get("rotation_y", null))
		var yaw := float(yaw_var) if (yaw_var is float or yaw_var is int) else (landing_yaw + rng.randf_range(-0.45, 0.45))
		var sc_var: Variant = entry.get("scale", 1.0)
		var sc_vec := Vector3.ONE
		if sc_var is Vector3:
			sc_vec = sc_var as Vector3
		elif sc_var is float or sc_var is int:
			var sf := clampf(float(sc_var), 0.85, 1.20)
			sc_vec = Vector3(sf, sf, sf)

		if kind == &"lantern":
			var xform := Transform3D(
				Basis(Vector3.UP, yaw) * Basis.from_scale(sc_vec),
				Vector3(pos.x, h - 0.14, pos.z))
			if _spawn_landmark(island, GLB_TRAIL_LANTERN, "TrailLantern_%d" % lantern_idx,
					xform, 2.4, placed, keepout_zones, rng, prop_body, props_root,
					foliage_cache, landmark_cache) != null:
				lantern_idx += 1
				spawned += 1
		else:
			var xform := Transform3D(
				Basis(Vector3.UP, yaw) * Basis.from_scale(sc_vec),
				Vector3(pos.x, h - 0.12, pos.z))
			if _spawn_landmark(island, GLB_STONE_CAIRN, "StoneCairn_%d" % cairn_idx,
					xform, 2.2, placed, keepout_zones, rng, prop_body, props_root,
					foliage_cache, landmark_cache) != null:
				cairn_idx += 1
				spawned += 1

	return spawned


# ============================================================ slope-snapped placement helpers

static func _place_cliff_overhang(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, u_span: float, v_span: float, h_min: float, h_max: float,
		prefer_dir: Vector3, scale_f: float, pad_keepout: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	var best_pos := Vector3.ZERO
	var best_out := prefer_dir
	var best_front_h := 0.0
	var best_score := -INF
	var found := false
	var eff_h_min := maxf(2.0, minf(h_min, 5.5))
	var eff_h_max := minf(h_max, 12.5)
	var h_mid := (eff_h_min + eff_h_max) * 0.5

	for iu in range(-5, 6):
		var u := u0 + float(iu) * (u_span * 0.22)
		for iv in range(-5, 6):
			var v := v0 + float(iv) * (v_span * 0.22)
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, pad_keepout):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < eff_h_min or h > eff_h_max:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.2)
			if n.y < 0.14 or n.y > 0.80:
				continue
			var out_xz := _horizontal_outward(n, lp, prefer_dir)
			var dir_dot := out_xz.dot(prefer_dir)
			if dir_dot < -0.15:
				continue
			# Embed deeply BACK along inward cliff normal so rear heel & haunches weld solidly into the cliff!
			var embed_xz := Vector3(lp.x, 0.0, lp.z) - out_xz * (3.85 * scale_f)
			if _in_exclusion_padded(embed_xz.x, embed_xz.z, keepout_zones, pad_keepout):
				continue
			# Verify brow juts over a walkable alcove floor (not a 20 m sheer drop) & rear heel is backed by rising rock!
			var front_p := embed_xz + out_xz * (4.6 * scale_f)
			var back_p := embed_xz - out_xz * (2.6 * scale_f)
			var h_front := island.surface_height(front_p.x, front_p.z)
			var h_back := island.surface_height(back_p.x, back_p.z)
			var back_rise := h_back - h
			if back_rise < 1.2 * scale_f:
				continue
			var drop := h - h_front
			if drop < 0.6 or drop > 5.0 * scale_f or h_front < 0.8:
				continue
			var back_bonus := clampf(back_rise, 0.0, 9.0) * 1.15
			var dist_pen := sqrt(pow(u - u0, 2.0) + pow(v - v0, 2.0)) * 0.20
			var score := dir_dot * 9.0 + clampf(drop, 0.0, 4.2) * 1.4 + back_bonus \
				+ (0.80 - n.y) * 8.0 - absf(h - h_mid) * 0.35 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, h, lp.z)
				best_out = out_xz
				best_front_h = h_front
				found = true

	if not found:
		return false

	var mount_xz := Vector3(best_pos.x, 0.0, best_pos.z) - best_out * (3.85 * scale_f)
	var side_xz := Vector3(-best_out.z, 0.0, best_out.x)
	var heel_center := mount_xz - best_out * (2.4 * scale_f)
	var heel_min_h := minf(
		island.surface_height(heel_center.x, heel_center.z),
		minf(
			island.surface_height(heel_center.x - side_xz.x * 4.4 * scale_f, heel_center.z - side_xz.z * 4.4 * scale_f),
			island.surface_height(heel_center.x + side_xz.x * 4.4 * scale_f, heel_center.z + side_xz.z * 4.4 * scale_f)
		)
	)
	# Seat the overhang datum solidly into the alcove floor (`best_front_h - 0.50`) so both rock haunches
	# and the deep rear heel fuse seamlessly into the hillside with zero exposed undersides!
	var mount_y := minf(best_front_h - 0.50 * scale_f, heel_min_h + 0.95 * scale_f)
	var yaw := atan2(-best_out.x, -best_out.z)
	var xform := Transform3D(
		Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		Vector3(mount_xz.x, mount_y, mount_xz.z))
	return _spawn_landmark(island, GLB_OVERHANG_LEDGE, node_name, xform, 6.2 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_cliff_buttress_wide(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, u_span: float, v_span: float, h_min: float, h_max: float,
		prefer_dir: Vector3, scale_f: float, pad_keepout: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	var best_pos := Vector3.ZERO
	var best_out := prefer_dir
	var best_score := -INF
	var found := false
	var h_mid := (h_min + h_max) * 0.5

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (u_span * 0.25)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (v_span * 0.25)
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, pad_keepout):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < h_min or h > h_max:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.5)
			if n.y < 0.08 or n.y > 0.76:
				continue
			var out_xz := _horizontal_outward(n, lp, prefer_dir)
			var dir_dot := out_xz.dot(prefer_dir)
			if dir_dot < -0.15:
				continue
			var embed_xz := Vector3(lp.x, 0.0, lp.z) - out_xz * (2.8 * scale_f)
			if _in_exclusion_padded(embed_xz.x, embed_xz.z, keepout_zones, pad_keepout):
				continue
			var dist_pen := sqrt(pow(u - u0, 2.0) + pow(v - v0, 2.0)) * 0.22
			var score := dir_dot * 9.0 + (0.76 - n.y) * 10.0 - absf(h - h_mid) * 0.20 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, h, lp.z)
				best_out = out_xz
				found = true

	if not found:
		return false

	var mount_xz := Vector3(best_pos.x, 0.0, best_pos.z) - best_out * (2.8 * scale_f)
	var side_xz := Vector3(-best_out.z, 0.0, best_out.x)
	var foot_min_h := minf(
		best_pos.y,
		minf(
			island.surface_height(mount_xz.x - side_xz.x * 5.8 * scale_f, mount_xz.z - side_xz.z * 5.8 * scale_f),
			island.surface_height(mount_xz.x + side_xz.x * 5.8 * scale_f, mount_xz.z + side_xz.z * 5.8 * scale_f)
		)
	)
	# Skirt plunges to y_local = -5.50 m so anchoring near foot_min_h prevents any edge gap!
	var mount_y := minf(best_pos.y - 1.15 * scale_f, foot_min_h + 3.8 * scale_f)
	var yaw := atan2(-best_out.x, -best_out.z)
	var xform := Transform3D(
		Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		Vector3(mount_xz.x, mount_y, mount_xz.z))
	return _spawn_landmark(island, GLB_BUTTRESS_WIDE, node_name, xform, 8.2 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_cliff_catwalk(island: Island, basis: Basis, node_name: String,
		u_min: float, u_max: float, v0: float, v_span: float,
		h_min: float, h_max: float, prefer_dir: Vector3, scale_f: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# Scan along u and v to locate a rocky h = h_min..h_max cliff shelf whose deck cantilevers
	# cleanly out over water/beach (-Z) while rear pilings & knee-braces lock into cliff (+Z)!
	var best_mount := Vector3.ZERO
	var best_out := prefer_dir
	var best_score := -INF
	var found := false
	var h_mid := (h_min + h_max) * 0.5
	var u_steps := 14
	var v_steps := 7

	for iu in range(u_steps + 1):
		var u := lerpf(u_min, u_max, float(iu) / float(u_steps))
		for iv in range(v_steps + 1):
			var v := v0 + lerpf(-v_span * 0.5, v_span * 0.5, float(iv) / float(v_steps))
			var shelf := basis * Vector3(u, 0.0, v)
			var h_shelf := island.surface_height(shelf.x, shelf.z)
			if h_shelf < h_min or h_shelf > h_max:
				continue
			var n := island.surface_normal(shelf.x, shelf.z, 2.0)
			var out_xz := _horizontal_outward(n, shelf, prefer_dir)
			var dir_dot := out_xz.dot(prefer_dir)
			if dir_dot < 0.20:
				continue
			# Blend outward direction slightly toward prefer_dir so the pier frames the fjord/cove cleanly.
			var aim_xz := (out_xz * 0.72 + prefer_dir * 0.28).normalized()
			# Deck sits at y_local = +3.22 m; anchor pilings sit at z_local = +1.70..+4.25 m (y >= -2.10 m).
			# Shift origin forward +1.8 m from shelf so rear anchor sits 2.45 m inside cliff and tip juts out 8.3 m!
			var mount_xz := Vector3(shelf.x, 0.0, shelf.z) + aim_xz * (1.80 * scale_f)
			var front_xz := mount_xz + aim_xz * (6.20 * scale_f)
			var rear_xz := mount_xz - aim_xz * (4.10 * scale_f)
			var mid_pile_xz := mount_xz - aim_xz * (1.70 * scale_f)

			if _in_exclusion_padded(mount_xz.x, mount_xz.z, keepout_zones, 3.0):
				continue
			if _in_exclusion_padded(front_xz.x, front_xz.z, keepout_zones, 2.2):
				continue
			if _in_exclusion_padded(rear_xz.x, rear_xz.z, keepout_zones, 2.0):
				continue

			var h_rear := island.surface_height(rear_xz.x, rear_xz.z)
			var h_mid_pile := island.surface_height(mid_pile_xz.x, mid_pile_xz.z)
			var h_front := island.surface_height(front_xz.x, front_xz.z)

			var mount_y := h_shelf - 3.22 * scale_f + 0.14
			# Rear sill & pilings MUST be buried inside cliff; front deck MUST clear the drop!
			if h_rear < mount_y + 1.80 * scale_f:
				continue
			if h_mid_pile < mount_y - 1.95 * scale_f:
				continue
			if h_front > mount_y + 2.35 * scale_f:
				continue

			var drop := (mount_y + 3.22 * scale_f) - h_front
			var water_bonus := 4.5 if h_front < 1.2 else 0.0
			var score := dir_dot * 10.0 + clampf(drop, 0.0, 10.0) * 1.4 + water_bonus \
				- absf(h_shelf - h_mid) * 0.45 - absf(v - v0) * 0.12
			if score > best_score:
				best_score = score
				best_mount = Vector3(mount_xz.x, mount_y, mount_xz.z)
				best_out = aim_xz
				found = true

	if not found:
		return false

	var yaw := atan2(-best_out.x, -best_out.z)
	var xform := Transform3D(
		Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_mount)
	return _spawn_landmark(island, GLB_CATWALK_PIER, node_name, xform, 6.2 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_temple_stairway(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, stair_yaw: float, scale_f: float, keepout_r: float,
		u_span: float, v_span: float, placed: Array[Vector3],
		keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# AncientTempleStairway ascends from z_local = -5.50 (y=0) to z_local = +2.30..+5.80 (y=+4.80),
	# with stepped masonry foundation plunging to y_local = -2.20.
	var stair_basis := Basis(Vector3.UP, stair_yaw)
	var climb_dir := (stair_basis * Vector3(0.0, 0.0, 1.0)).normalized()
	var foot_dir := -climb_dir
	var side_dir := (stair_basis * Vector3(1.0, 0.0, 0.0)).normalized()
	var target_rise := 4.60 * scale_f

	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-3, 4):
		var u := u0 + float(iu) * (u_span / 6.0)
		for iv in range(-3, 4):
			var v := v0 + float(iv) * (v_span / 6.0)
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 3.8):
				continue
			var foot_p := lp + foot_dir * (5.3 * scale_f)
			var top_p := lp + climb_dir * (4.0 * scale_f)
			if _in_exclusion(foot_p.x, foot_p.z, keepout_zones) or _in_exclusion(top_p.x, top_p.z, keepout_zones):
				continue
			var h_foot := island.surface_height(foot_p.x, foot_p.z)
			var h_top := island.surface_height(top_p.x, top_p.z)
			var h_mid := island.surface_height(lp.x, lp.z)
			if h_foot < 1.2 or h_top < h_foot + 0.4:
				continue
			# Check cross-slope stability at BOTH midpoint & upper obelisk landing so foundation skirts
			# stay grounded AND neither upper twin obelisk sinks into a curving canyon bank (Local-GPU M22A).
			var h_l := island.surface_height(lp.x - side_dir.x * 3.6 * scale_f, lp.z - side_dir.z * 3.6 * scale_f)
			var h_r := island.surface_height(lp.x + side_dir.x * 3.6 * scale_f, lp.z + side_dir.z * 3.6 * scale_f)
			if absf(h_l - h_r) > 4.2 * scale_f:
				continue
			var h_top_l := island.surface_height(top_p.x - side_dir.x * 3.4 * scale_f, top_p.z - side_dir.z * 3.4 * scale_f)
			var h_top_r := island.surface_height(top_p.x + side_dir.x * 3.4 * scale_f, top_p.z + side_dir.z * 3.4 * scale_f)
			if absf(h_top_l - h_top_r) > 3.2 * scale_f or maxf(h_top_l, h_top_r) > h_top + 1.5 * scale_f:
				continue
			var rise := h_top - h_foot
			var dist_pen := sqrt(pow(u - u0, 2.0) + pow(v - v0, 2.0)) * 0.25
			var score := 12.0 - absf(rise - target_rise) * 2.2 - absf(h_l - h_r) * 0.6 \
				- absf(h_top_l - h_top_r) * 0.85 - dist_pen
			if score > best_score:
				best_score = score
				# Seat foot cleanly walkable while keeping rear landing above slope & foundation buried!
				var mount_y := clampf(h_top - 4.72 * scale_f, h_foot - 0.35 * scale_f, h_foot + 0.42 * scale_f)
				var min_skirt_h := minf(minf(h_foot, h_mid), minf(h_l, h_r))
				mount_y = minf(mount_y, min_skirt_h + 1.90 * scale_f)
				best_pos = Vector3(lp.x, mount_y, lp.z)
				found = true

	if not found:
		return false

	var xform := Transform3D(
		stair_basis * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_TEMPLE_STAIRWAY, node_name, xform, keepout_r,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_sea_arch(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_vec: Vector3, keepout_r: float,
		y_offset: float, y_cap: float, placed: Array[Vector3],
		keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	var arch_basis := Basis(Vector3.UP, yaw)
	var right_dir := (arch_basis * Vector3(1.0, 0.0, 0.0)).normalized()
	var u := u0
	var v := v0
	var lp := basis * Vector3(u, 0.0, v)
	var h_c := island.surface_height(lp.x, lp.z)

	# If the nominal coordinate sits high on dry land (h > 1.8 m), walk radially outward into
	# glistening shallow surf so the barnacle legs & open vault straddle the waterline cleanly!
	if h_c > 1.8:
		var out_uv := Vector2(u0, v0)
		if out_uv.length_squared() < 1.0:
			out_uv = Vector2(0.0, -1.0)
		else:
			out_uv = out_uv.normalized()
		var best_lp := lp
		var best_hc := h_c
		var best_score := -INF
		for step_i in range(1, 18):
			var dist := float(step_i) * 2.5
			var cand_uv := Vector2(u0, v0) + out_uv * dist
			var cand_lp := basis * Vector3(cand_uv.x, 0.0, cand_uv.y)
			if _in_exclusion(cand_lp.x, cand_lp.z, keepout_zones):
				continue
			var ch := island.surface_height(cand_lp.x, cand_lp.z)
			var cl := island.surface_height(cand_lp.x - right_dir.x * 7.8 * scale_vec.x, cand_lp.z - right_dir.z * 7.8 * scale_vec.x)
			var cr := island.surface_height(cand_lp.x + right_dir.x * 7.8 * scale_vec.x, cand_lp.z + right_dir.z * 7.8 * scale_vec.x)
			if minf(cl, cr) < -3.6 * scale_vec.y:
				continue
			if ch >= -1.8 and ch <= 1.1:
				var score := 10.0 - absf(ch - 0.0) * 3.5 - dist * 0.06
				if score > best_score:
					best_score = score
					best_lp = cand_lp
					best_hc = ch
		if best_score > -INF:
			lp = best_lp
			h_c = best_hc

	var h_l := island.surface_height(lp.x - right_dir.x * 7.8 * scale_vec.x, lp.z - right_dir.z * 7.8 * scale_vec.x)
	var h_r := island.surface_height(lp.x + right_dir.x * 7.8 * scale_vec.x, lp.z + right_dir.z * 7.8 * scale_vec.x)
	# Flared legs plunge down to y_local = -3.30 m; clamp so neither leg hovers above seabed!
	var y := minf(h_c, y_cap) + y_offset
	var leg_ceiling := minf(h_l, h_r) + 2.65 * scale_vec.y
	y = maxf(minf(y, leg_ceiling), -2.2)

	var xform := Transform3D(
		arch_basis * Basis.from_scale(scale_vec),
		Vector3(lp.x, y, lp.z))
	return _spawn_landmark(island, GLB_SEA_ARCH, node_name, xform, keepout_r,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_shipwreck_bow(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, keepout_r: float,
		h_min: float, h_max: float, scan_span: float, placed: Array[Vector3],
		keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false
	var h_mid := (h_min + h_max) * 0.45

	for iu in range(-3, 4):
		var u := u0 + float(iu) * (scan_span / 6.0)
		for iv in range(-3, 4):
			var v := v0 + float(iv) * (scan_span / 6.0)
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 3.0):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < h_min or h > h_max:
				continue
			var min_foot := _min_footprint_height(island, lp.x, lp.z, 3.1 * scale_f)
			if h - min_foot > 3.6 * scale_f:
				continue
			var dist_pen := sqrt(pow(u - u0, 2.0) + pow(v - v0, 2.0)) * 0.35
			var score := 10.0 - absf(h - h_mid) * 0.25 - (h - min_foot) * 0.9 - dist_pen
			if score > best_score:
				best_score = score
				var mount_y := minf(h, min_foot + 1.45 * scale_f) - 0.55 * scale_f
				best_pos = Vector3(lp.x, mount_y, lp.z)
				found = true

	if not found:
		return false

	var xform := Transform3D(
		Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_SHIPWRECK_BOW, node_name, xform, keepout_r,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_basalt_spire(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-3, 4):
		var u := u0 + float(iu) * (scan_span / 6.0)
		for iv in range(-3, 4):
			var v := v0 + float(iv) * (scan_span / 6.0)
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 3.5):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 8.0 or h > 72.0:
				continue
			var min_foot := _min_footprint_height(island, lp.x, lp.z, 2.8 * scale_f)
			var dist_pen := sqrt(pow(u - u0, 2.0) + pow(v - v0, 2.0)) * 0.30
			var ridge_bonus := clampf(h * 0.14, 0.0, 6.0)
			var score := ridge_bonus - (h - min_foot) * 0.45 - dist_pen
			if score > best_score:
				best_score = score
				# Basalt columns plunge to y_local = -2.60 m; root deeply so all 13 columns anchor cleanly!
				var mount_y := minf(h - 0.55 * scale_f, min_foot + 1.85 * scale_f)
				best_pos = Vector3(lp.x, mount_y, lp.z)
				found = true

	if not found:
		return false

	var sy := scale_f * rng.randf_range(0.95, 1.12)
	var xform := Transform3D(
		Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale_f, sy, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_BASALT_SPIRE, node_name, xform, 5.2 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_boulder_cluster(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, scan_span: float, scale_f: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-3, 4):
		var u := u0 + float(iu) * (scan_span / 6.0)
		for iv in range(-3, 4):
			var v := v0 + float(iv) * (scan_span / 6.0)
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 2.6):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 0.25 or h > 22.0:
				continue
			var n := island.surface_normal(lp.x, lp.z)
			if n.y < 0.72:
				continue
			var min_foot := _min_footprint_height_8(island, lp.x, lp.z, 2.5 * scale_f)
			if h - min_foot > 1.7 * scale_f:
				continue
			var dist_pen := sqrt(pow(u - u0, 2.0) + pow(v - v0, 2.0)) * 0.35
			var score := n.y * 6.0 - (h - min_foot) * 1.5 - dist_pen
			if score > best_score:
				best_score = score
				var mount_y := minf(h - 0.28 * scale_f, min_foot + 0.44 * scale_f)
				best_pos = Vector3(lp.x, mount_y, lp.z)
				found = true

	if not found:
		return false

	var yaw := rng.randf() * TAU
	var sy := scale_f * rng.randf_range(0.90, 1.10)
	var xform := Transform3D(
		Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale_f, sy, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_BOULDER_CLUSTER, node_name, xform, 4.2 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_sea_god_idol(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false
	for iu in range(-3, 4):
		var u := u0 + float(iu) * (scan_span / 6.0)
		for iv in range(-3, 4):
			var v := v0 + float(iv) * (scan_span / 6.0)
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 3.6 * scale_f):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 4.0 or h > 46.0:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.0)
			if n.y < 0.72:
				continue
			var min_foot := _min_footprint_height(island, lp.x, lp.z, 2.4 * scale_f)
			if h - min_foot > 2.2 * scale_f:
				continue
			var dist_pen := sqrt(pow(u - u0, 2.0) + pow(v - v0, 2.0)) * 0.30
			var score := n.y * 8.0 + clampf(h * 0.16, 0.0, 5.0) - (h - min_foot) * 1.6 - dist_pen
			if score > best_score:
				best_score = score
				# Idol plinth extends down to y_local = -1.8 m; seat flush on lowest corner!
				var mount_y := minf(h - 0.18 * scale_f, min_foot + 0.95 * scale_f)
				best_pos = Vector3(lp.x, mount_y, lp.z)
				found = true
	if not found:
		return false
	var xform := Transform3D(
		Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_SEA_GOD_IDOL, node_name, xform, 5.4 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_volcanic_arch(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	var arch_basis := Basis(Vector3.UP, yaw)
	var right_dir := arch_basis.x
	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false
	for iu in range(-2, 3):
		var u := u0 + float(iu) * (scan_span * 0.25)
		for iv in range(-3, 4):
			var v := v0 + float(iv) * (scan_span / 6.0)
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 3.0):
				continue
			var h_c := island.surface_height(lp.x, lp.z)
			if h_c < 1.6 or h_c > 24.0:
				continue
			var h_l := island.surface_height(lp.x - right_dir.x * 6.4 * scale_f, lp.z - right_dir.z * 6.4 * scale_f)
			var h_r := island.surface_height(lp.x + right_dir.x * 6.4 * scale_f, lp.z + right_dir.z * 6.4 * scale_f)
			if minf(h_l, h_r) < 0.4:
				continue
			var span_diff := absf(h_l - h_r)
			if span_diff > 4.5 * scale_f:
				continue
			var dist_pen := sqrt(pow(u - u0, 2.0) + pow(v - v0, 2.0)) * 0.22
			var score := 10.0 - span_diff * 1.4 - absf(h_c - 5.0) * 0.35 - dist_pen
			if score > best_score:
				best_score = score
				# Basalt arch piers plunge to y_local = -2.6 m; ensure both piers bury solidly below terrain!
				var mount_y := minf(h_c - 0.15 * scale_f, minf(h_l, h_r) + 1.65 * scale_f)
				best_pos = Vector3(lp.x, mount_y, lp.z)
				found = true
	if not found:
		return false
	var xform := Transform3D(
		arch_basis * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_VOLCANIC_ARCH, node_name, xform, 8.8 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_leviathan_ribcage(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false
	for iu in range(-3, 4):
		var u := u0 + float(iu) * (scan_span / 6.0)
		for iv in range(-3, 4):
			var v := v0 + float(iv) * (scan_span / 6.0)
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 3.6 * scale_f):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < -0.35 or h > 4.5:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.2)
			if n.y < 0.78:
				continue
			var min_foot := _min_footprint_height(island, lp.x, lp.z, 4.2 * scale_f)
			if h - min_foot > 2.2 * scale_f:
				continue
			var dist_pen := sqrt(pow(u - u0, 2.0) + pow(v - v0, 2.0)) * 0.25
			var score := n.y * 8.0 - absf(h - 1.35) * 1.5 - (h - min_foot) * 1.4 - dist_pen
			if score > best_score:
				best_score = score
				# Rib roots plunge to y_local = -1.8 m; nestle firmly into beach sand & tidal shallows!
				var mount_y := minf(h - 0.15 * scale_f, min_foot + 0.95 * scale_f)
				best_pos = Vector3(lp.x, mount_y, lp.z)
				found = true
	if not found:
		return false
	var xform := Transform3D(
		Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_LEVIATHAN_RIBCAGE, node_name, xform, 7.2 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_beached_rowboat(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false
	for iu in range(-3, 4):
		var u := u0 + float(iu) * (scan_span / 6.0)
		for iv in range(-3, 4):
			var v := v0 + float(iv) * (scan_span / 6.0)
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 2.8):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 0.75 or h > 2.95:
				continue
			var n := island.surface_normal(lp.x, lp.z, 1.8)
			if n.y < 0.78:
				continue
			var min_foot := _min_footprint_height(island, lp.x, lp.z, 2.0 * scale_f)
			if h - min_foot > 1.15 * scale_f:
				continue
			var dist_pen := sqrt(pow(u - u0, 2.0) + pow(v - v0, 2.0)) * 0.25
			var score := n.y * 7.0 - absf(h - 1.55) * 1.8 - (h - min_foot) * 1.6 - dist_pen
			if score > best_score:
				best_score = score
				var mount_y := minf(h - 0.10 * scale_f, min_foot + 0.42 * scale_f)
				best_pos = Vector3(lp.x, mount_y, lp.z)
				found = true
	if not found:
		return false
	var xform := Transform3D(
		Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_ROWBOAT_WRECK, node_name, xform, 3.8 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_pirate_gibbet(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false
	for iu in range(-3, 4):
		var u := u0 + float(iu) * (scan_span / 6.0)
		for iv in range(-3, 4):
			var v := v0 + float(iv) * (scan_span / 6.0)
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 3.2):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 1.8 or h > 22.0:
				continue
			var n := island.surface_normal(lp.x, lp.z, 1.8)
			if n.y < 0.72:
				continue
			var min_foot := _min_footprint_height(island, lp.x, lp.z, 1.8 * scale_f)
			if h - min_foot > 1.6 * scale_f:
				continue
			var dist_pen := sqrt(pow(u - u0, 2.0) + pow(v - v0, 2.0)) * 0.25
			var score := n.y * 7.0 + clampf(h * 0.20, 0.0, 4.0) - (h - min_foot) * 1.4 - dist_pen
			if score > best_score:
				best_score = score
				var mount_y := minf(h - 0.16 * scale_f, min_foot + 0.65 * scale_f)
				best_pos = Vector3(lp.x, mount_y, lp.z)
				found = true
	if not found:
		return false
	var xform := Transform3D(
		Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_PIRATE_GIBBET, node_name, xform, 3.8 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_signal_brazier(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false
	for iu in range(-3, 4):
		var u := u0 + float(iu) * (scan_span / 6.0)
		for iv in range(-3, 4):
			var v := v0 + float(iv) * (scan_span / 6.0)
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 3.2):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 2.2 or h > 34.0:
				continue
			var n := island.surface_normal(lp.x, lp.z, 1.8)
			if n.y < 0.72:
				continue
			var min_foot := _min_footprint_height(island, lp.x, lp.z, 2.0 * scale_f)
			if h - min_foot > 1.8 * scale_f:
				continue
			var dist_pen := sqrt(pow(u - u0, 2.0) + pow(v - v0, 2.0)) * 0.25
			var score := n.y * 7.5 + clampf(h * 0.18, 0.0, 5.0) - (h - min_foot) * 1.4 - dist_pen
			if score > best_score:
				best_score = score
				var mount_y := minf(h - 0.16 * scale_f, min_foot + 0.75 * scale_f)
				best_pos = Vector3(lp.x, mount_y, lp.z)
				found = true
	if not found:
		return false
	var xform := Transform3D(
		Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_SIGNAL_BRAZIER, node_name, xform, 4.0 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_summit_crag(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, u_span: float, v_span: float, h_min: float, h_max: float,
		yaw: float, scale_f: float, placed: Array[Vector3], keepout_zones: Array[Vector3],
		rng: RandomNumberGenerator, prop_body: StaticBody3D, props_root: Node3D,
		foliage_cache: Dictionary, landmark_cache: Dictionary) -> bool:
	# CliffSummitCragSpire (~22 m tall, flared base r ~ 8.5..9.5 m plunging to y_local = -7.50 m)
	# crowns true Tier 2-4 mountain peaks & skyline ridge crests (never mid-wall faces!).
	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-5, 6):
		var u := u0 + float(iu) * (u_span * 0.1)
		for iv in range(-5, 6):
			var v := v0 + float(iv) * (v_span * 0.1)
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 6.5 * scale_f):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < h_min or h > h_max:
				continue
			var n := island.surface_normal(lp.x, lp.z, 3.0)
			# Accept sharp eroded alpine ridge spines while rejecting sheer vertical walls.
			if n.y < 0.28:
				continue
			var r_inner := 6.8 * scale_f
			var diag_r := r_inner * 0.7071
			var ring_hs: Array[float] = [
				island.surface_height(lp.x + r_inner, lp.z),
				island.surface_height(lp.x - r_inner, lp.z),
				island.surface_height(lp.x, lp.z + r_inner),
				island.surface_height(lp.x, lp.z - r_inner),
				island.surface_height(lp.x + diag_r, lp.z + diag_r),
				island.surface_height(lp.x - diag_r, lp.z + diag_r),
				island.surface_height(lp.x + diag_r, lp.z - diag_r),
				island.surface_height(lp.x - diag_r, lp.z - diag_r),
			]
			var min_foot := h
			var max_foot := h
			for rh: float in ring_hs:
				min_foot = minf(min_foot, rh)
				max_foot = maxf(max_foot, rh)
			# Reject mid-slope wall points where rock towers steeply uphill directly behind the spire!
			if max_foot > h + 4.2 * scale_f:
				continue
			if h - min_foot > 9.8 * scale_f:
				continue
			var outer_min := _min_footprint_height(island, lp.x, lp.z, 8.8 * scale_f)
			var outer_diag := 8.8 * scale_f * 0.7071
			outer_min = minf(outer_min, island.surface_height(lp.x + outer_diag, lp.z + outer_diag))
			outer_min = minf(outer_min, island.surface_height(lp.x - outer_diag, lp.z + outer_diag))
			outer_min = minf(outer_min, island.surface_height(lp.x + outer_diag, lp.z - outer_diag))
			outer_min = minf(outer_min, island.surface_height(lp.x - outer_diag, lp.z - outer_diag))
			if h - outer_min > 14.5 * scale_f:
				continue
			var dist_pen := sqrt(pow(u - u0, 2.0) + pow(v - v0, 2.0)) * 0.06
			var crest_bonus := clampf(h - max_foot + 4.0, 0.0, 8.0) * 1.6
			var score := h * 0.90 + n.y * 6.0 + crest_bonus - (h - min_foot) * 0.65 - dist_pen
			if score > best_score:
				best_score = score
				var mount_y := minf(h - 1.35 * scale_f, min_foot + 5.8 * scale_f)
				mount_y = minf(mount_y, outer_min + 6.7 * scale_f)
				best_pos = Vector3(lp.x, mount_y, lp.z)
				found = true

	if not found:
		return false

	var xform := Transform3D(
		Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_SUMMIT_CRAG, node_name, xform, 9.2 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_ruin_aqueduct(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, u_span: float, v_span: float, yaw: float, scale_f: float,
		h_min: float, h_max: float, placed: Array[Vector3], keepout_zones: Array[Vector3],
		rng: RandomNumberGenerator, prop_body: StaticBody3D, props_root: Node3D,
		foliage_cache: Dictionary, landmark_cache: Dictionary) -> bool:
	# CliffRuinAqueductArch spans x_local = -9.35..+9.55 m with 3 piers at x = -7.8, 0.0, +7.8
	# plunging to y_local = -5.50 m and 2 open semicircular arches rising to y = +13.97 m.
	# Strictly seats on genuine terraces, saddles & valley floors (n.y >= 0.62; never stuck sideways on sheer walls!).
	var best_pos := Vector3.ZERO
	var best_yaw := yaw
	var best_score := -INF
	var found := false
	var h_mid := (h_min + h_max) * 0.5
	var yaw_offsets: Array[float] = [-0.42, -0.28, -0.14, 0.0, 0.14, 0.28, 0.42]

	for iu in range(-5, 6):
		var u := u0 + float(iu) * (u_span * 0.1)
		for iv in range(-5, 6):
			var v := v0 + float(iv) * (v_span * 0.1)
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 4.0 * scale_f):
				continue
			var h_m := island.surface_height(lp.x, lp.z)
			if h_m < h_min or h_m > h_max:
				continue
			var n_m := island.surface_normal(lp.x, lp.z, 2.5)
			if n_m.y < 0.62:
				continue
			var dist_pen := sqrt(pow(u - u0, 2.0) + pow(v - v0, 2.0)) * 0.14

			for d_yaw: float in yaw_offsets:
				var cand_yaw := yaw + d_yaw
				var arch_basis := Basis(Vector3.UP, cand_yaw)
				var right_dir := arch_basis.x
				var fwd_dir := arch_basis.z
				var p_l := lp - right_dir * (7.8 * scale_f)
				var p_r := lp + right_dir * (7.8 * scale_f)
				if _in_exclusion_padded(p_l.x, p_l.z, keepout_zones, 2.8 * scale_f):
					continue
				if _in_exclusion_padded(p_r.x, p_r.z, keepout_zones, 2.8 * scale_f):
					continue
				var h_l := island.surface_height(p_l.x, p_l.z)
				var h_r := island.surface_height(p_r.x, p_r.z)
				var h_min_pier := minf(h_m, minf(h_l, h_r))
				var h_max_pier := maxf(h_m, maxf(h_l, h_r))
				var bad_pier_slope := false
				for pier_p: Vector3 in [p_l, lp, p_r]:
					var pn := island.surface_normal(pier_p.x, pier_p.z, 2.2)
					if pn.y < 0.56:
						bad_pier_slope = true
						break
					var pf := _min_footprint_height(island, pier_p.x, pier_p.z, 1.9 * scale_f)
					var p_front := pier_p - fwd_dir * (1.9 * scale_f)
					var p_back := pier_p + fwd_dir * (1.9 * scale_f)
					pf = minf(pf, minf(
						island.surface_height(p_front.x, p_front.z),
						island.surface_height(p_back.x, p_back.z)
					))
					h_min_pier = minf(h_min_pier, pf)
				if bad_pier_slope:
					continue
				if h_min_pier < maxf(1.2, h_min - 4.0):
					continue
				var relief := h_max_pier - h_min_pier
				if relief > 4.2 * scale_f:
					continue
				var mount_y := minf(h_max_pier - 0.65 * scale_f, h_min_pier + 4.15 * scale_f)
				if h_min_pier < mount_y - 4.3 * scale_f:
					continue
				if h_max_pier > mount_y + 2.2 * scale_f:
					continue
				var span_diff := absf(h_l - h_r)
				var score := 14.0 + n_m.y * 5.0 - relief * 1.65 - span_diff * 0.65 - absf(h_m - h_mid) * 0.20 \
					- absf(d_yaw) * 3.2 - dist_pen
				if score > best_score:
					best_score = score
					best_pos = Vector3(lp.x, mount_y, lp.z)
					best_yaw = cand_yaw
					found = true

	if not found:
		return false

	var xform := Transform3D(
		Basis(Vector3.UP, best_yaw) * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_RUIN_AQUEDUCT, node_name, xform, 9.6 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_pirate_watchpost(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, u_span: float, v_span: float, h_min: float, h_max: float,
		prefer_dir: Vector3, scale_f: float, placed: Array[Vector3],
		keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# CliffsidePirateWatchpost faces seaward (-Z) with lookout deck at y = +4.6 m,
	# heavy stilts plunging to y_local = -7.80 m (z = -1.70..+3.85), rear cliff-anchor sills
	# back to z = +3.85 m, crimson pennant & glowing Lantern_Watchpost beacon.
	var best_pos := Vector3.ZERO
	var best_out := prefer_dir
	var best_score := -INF
	var found := false
	var h_mid := (h_min + h_max) * 0.5
	var stilt_reach := minf(6.8, 6.8 * scale_f)
	var front_probe := maxf(3.2, 3.2 * scale_f)

	for iu in range(-5, 6):
		var u := u0 + float(iu) * (u_span * 0.1)
		for iv in range(-5, 6):
			var v := v0 + float(iv) * (v_span * 0.1)
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 4.5 * scale_f):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < h_min or h > h_max:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.2)
			if n.y < 0.25 or n.y > 0.82:
				continue
			var out_xz := _horizontal_outward(n, lp, prefer_dir)
			var dir_dot := out_xz.dot(prefer_dir)
			if dir_dot < 0.15:
				continue

			# Tuck watchpost 1.2 m back into steep ridges (n.y < 0.72, e.g. Cutlass Cay) so front stilts
			# and rear anchor sills embed solidly into the cliff hillside!
			var tuck_back := 1.2 if n.y < 0.72 else 0.0
			var anchor_xz := Vector3(lp.x, 0.0, lp.z) - out_xz * tuck_back
			if _in_exclusion_padded(anchor_xz.x, anchor_xz.z, keepout_zones, 4.5 * scale_f):
				continue
			var h_anchor := island.surface_height(anchor_xz.x, anchor_xz.z)
			var back_p := anchor_xz - out_xz * (3.2 * scale_f)
			var front_p := anchor_xz + out_xz * front_probe
			if _in_exclusion_padded(back_p.x, back_p.z, keepout_zones, 2.8 * scale_f):
				continue
			if _in_exclusion_padded(front_p.x, front_p.z, keepout_zones, 2.5 * scale_f):
				continue
			var h_back := island.surface_height(back_p.x, back_p.z)
			var h_front := island.surface_height(front_p.x, front_p.z)
			if h_back < h_anchor - 0.6:
				continue
			if h_front > h_anchor + 0.5:
				continue

			# Sample front-left & front-right stilt ground heights ~3.2 m seaward + full stilt footprint!
			var side_xz := Vector3(-out_xz.z, 0.0, out_xz.x)
			var fl_p := anchor_xz + out_xz * front_probe - side_xz * (2.1 * scale_f)
			var fr_p := anchor_xz + out_xz * front_probe + side_xz * (2.1 * scale_f)
			var h_fl := island.surface_height(fl_p.x, fl_p.z)
			var h_fr := island.surface_height(fr_p.x, fr_p.z)
			var min_front_stilt := minf(h_fl, h_fr)

			var min_foot := _min_footprint_height(island, anchor_xz.x, anchor_xz.z, 2.2 * scale_f)
			for zoff: float in [-1.7, 1.15, 2.5]:
				for xoff: float in [-2.2, 2.2]:
					var sp := anchor_xz - out_xz * (zoff * scale_f) + side_xz * (xoff * scale_f)
					min_foot = minf(min_foot, island.surface_height(sp.x, sp.z))
			if h_anchor - min_foot > 7.4 * scale_f:
				continue

			# Guarantee base_y - 6.8 <= minf(h_fl, h_fr) - 0.5 so even the lowest -7.8 m front stilt
			# penetrates firmly into the hillside while keeping the +4.6 m lookout deck above the slope!
			var base_y := minf(h_anchor - 0.85 * scale_f, min_foot + 5.8 * scale_f)
			base_y = minf(base_y, min_front_stilt + stilt_reach - 0.5)
			if h_anchor - base_y > 3.6 * scale_f:
				continue

			var back_excess := maxf(0.0, (h_back - h_anchor) - 5.5 * scale_f)
			var drop := h_anchor - h_front
			var dist_pen := sqrt(pow(u - u0, 2.0) + pow(v - v0, 2.0)) * 0.14
			var score := dir_dot * 10.0 + clampf(drop, 0.0, 5.0) * 1.4 + (0.82 - n.y) * 5.0 \
				- back_excess * 0.6 - absf(h - h_mid) * 0.22 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(anchor_xz.x, base_y, anchor_xz.z)
				best_out = out_xz
				found = true

	if not found:
		return false

	var yaw := atan2(-best_out.x, -best_out.z)
	var xform := Transform3D(
		Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_PIRATE_WATCHPOST, node_name, xform, 5.8 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_upper_strata_rib(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, u_span: float, v_span: float, h_min: float, h_max: float,
		prefer_dir: Vector3, scale_f: float, placed: Array[Vector3],
		keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# UpperCliffStrataRib is a reclined (~58 deg) stepped limestone cliff rib (x = -7.16..+7.16,
	# y = -4.50..+13.45, z = -3.22..+8.64) whose -Z face looks downhill and massive +Z wedge
	# welds flush into steep 45-75 deg mid-to-upper tan cliff faces!
	var best_pos := Vector3.ZERO
	var best_out := prefer_dir
	var best_foot_min := 0.0
	var best_score := -INF
	var found := false
	var h_mid := (h_min + h_max) * 0.5
	var embed_depth := 3.25 * scale_f
	var min_back_rise := maxf(3.0, 3.0 * scale_f)

	for iu in range(-5, 6):
		var u := u0 + float(iu) * (u_span * 0.1)
		for iv in range(-5, 6):
			var v := v0 + float(iv) * (v_span * 0.1)
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 5.2 * scale_f):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < h_min or h > h_max:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.5)
			if n.y < 0.18 or n.y > 0.68:
				continue
			var out_xz := _horizontal_outward(n, lp, prefer_dir)
			var dir_dot := out_xz.dot(prefer_dir)
			if dir_dot < 0.10:
				continue
			# Deeply embed along -out_xz * 3.25 (>= 3.0 * scale_f) and verify solid rising rear wall
			# (h_back > h + 3.0 across center & rear wings) so ZERO thin slab ever juts into open air!
			var embed_xz := Vector3(lp.x, 0.0, lp.z) - out_xz * embed_depth
			if _in_exclusion_padded(embed_xz.x, embed_xz.z, keepout_zones, 5.0 * scale_f):
				continue
			var side_xz := Vector3(-out_xz.z, 0.0, out_xz.x)
			var back_p := embed_xz - out_xz * (2.8 * scale_f)
			var h_back := island.surface_height(back_p.x, back_p.z)
			var back_rise := h_back - h
			if back_rise <= min_back_rise:
				continue
			var back_l := back_p - side_xz * (4.0 * scale_f)
			var back_r := back_p + side_xz * (4.0 * scale_f)
			if minf(island.surface_height(back_l.x, back_l.z), island.surface_height(back_r.x, back_r.z)) < h + 2.0:
				continue

			var front_apron := embed_xz + out_xz * (2.2 * scale_f)
			var foot_min_h := minf(h, island.surface_height(front_apron.x, front_apron.z))
			for xoff: float in [-6.6, -3.5, 3.5, 6.6]:
				var fp := front_apron + side_xz * (xoff * scale_f)
				foot_min_h = minf(foot_min_h, island.surface_height(fp.x, fp.z))
			var ml_p := embed_xz - side_xz * (6.8 * scale_f)
			var mr_p := embed_xz + side_xz * (6.8 * scale_f)
			foot_min_h = minf(foot_min_h, minf(
				island.surface_height(ml_p.x, ml_p.z),
				island.surface_height(mr_p.x, mr_p.z)
			))
			if h - foot_min_h > 6.4 * scale_f:
				continue
			var slope_match := 8.0 - absf(n.y - 0.48) * 18.0
			var back_bonus := clampf(back_rise, 0.0, 10.0) * 0.9
			var dist_pen := sqrt(pow(u - u0, 2.0) + pow(v - v0, 2.0)) * 0.14
			var score := dir_dot * 9.0 + slope_match + back_bonus - (h - foot_min_h) * 0.55 \
				- absf(h - h_mid) * 0.18 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, h, lp.z)
				best_out = out_xz
				best_foot_min = foot_min_h
				found = true

	if not found:
		return false

	var mount_xz := Vector3(best_pos.x, 0.0, best_pos.z) - best_out * embed_depth
	# Base plunges to y_local = -4.50 m; clamp to foot_min_h so lower apron never hovers!
	var mount_y := minf(best_pos.y - 0.85 * scale_f, best_foot_min + 3.4 * scale_f)
	var yaw := atan2(-best_out.x, -best_out.z)
	var xform := Transform3D(
		Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		Vector3(mount_xz.x, mount_y, mount_xz.z))
	return _spawn_landmark(island, GLB_STRATA_RIB, node_name, xform, 7.2 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_pirate_camp(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# PirateCampCanopy (~6.2 m x 4.6 m, posts plunging to y_local = -1.25 m, guy-line stakes to -0.82 m)
	# requires strict flat sunlit sandy beach / grassy cove ground clear of footpaths & keepouts!
	var camp_basis := Basis(Vector3.UP, yaw)
	var right_d := camp_basis.x
	var fwd_d := camp_basis.z
	var trail_polys := IslandTrails.get_trail_polylines(island.archetype, island.island_radius, island.island_id)
	var trail_clear := IslandTrails.get_trail_half_width(island.archetype) + 3.8 * scale_f

	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			if not trail_polys.is_empty() and _min_dist_to_trails_uv(u, v, trail_polys) < trail_clear:
				continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 3.8 * scale_f):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 1.6 or h > 8.5:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.0)
			if n.y < 0.80:
				continue

			# Sample inner camp footprint (4 corner posts, map crate, kegs & campfire ring) and
			# outer guy-line beach stakes separately so inner props sit flush without burying
			# while every -1.25 m corner post & -0.82 m beach stake roots cleanly below terrain!
			var min_foot := _min_footprint_height(island, lp.x, lp.z, 2.0 * scale_f)
			var max_foot := h
			var min_stake := min_foot
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var post_p := lp + right_d * (sx * 2.15 * scale_f) + fwd_d * (sz * 1.55 * scale_f)
					var stake_p := lp + right_d * (sx * 3.05 * scale_f) + fwd_d * (sz * 2.25 * scale_f)
					var hp := island.surface_height(post_p.x, post_p.z)
					var hs := island.surface_height(stake_p.x, stake_p.z)
					min_foot = minf(min_foot, hp)
					max_foot = maxf(max_foot, hp)
					min_stake = minf(min_stake, hs)
			if min_foot < 1.25 or min_stake < 0.90:
				continue
			if h - min_foot > 0.85 * scale_f:
				continue
			var mount_y := min_foot - 0.12 * scale_f
			# Keep outer -0.82 m beach stakes embedded >= 0.30 m & prevent uphill sand burying campfire/kegs.
			if min_stake < mount_y - 0.52 * scale_f:
				continue
			if max_foot - min_foot > 0.85 * scale_f:
				continue

			var dist_pen := Vector2(u - u0, v - v0).length() * 0.16
			var score := n.y * 12.0 - (max_foot - min_foot) * 6.0 - (h - min_foot) * 3.0 \
				- absf(h - 3.0) * 0.45 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, mount_y, lp.z)
				found = true

	if not found:
		return false

	var xform := Transform3D(
		camp_basis * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_PIRATE_CAMP, node_name, xform, 5.0 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_sunken_stern(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# SunkenGalleonStern (~9.5 m wide x ~9.2 m tall, heeled broken hull plunging to y_local = -3.6 m)
	# grounds dramatically in shallow turquoise shoals & sandy surf (`h = -1.8..+1.8 m`)!
	var has_mooring := island.mooring_transform != Transform3D.IDENTITY
	var moor_xz := Vector2(island.mooring_transform.origin.x, island.mooring_transform.origin.z)

	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 4.4 * scale_f):
				continue
			if has_mooring and Vector2(lp.x, lp.z).distance_squared_to(moor_xz) < 18.0 * 18.0:
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < -1.8 or h > 1.8:
				continue
			var min_foot := _min_footprint_height_8(island, lp.x, lp.z, 4.2 * scale_f)
			if min_foot < -3.6 * scale_f or h - min_foot > 3.2 * scale_f:
				continue
			var mount_y := minf(h - 0.35 * scale_f, min_foot + 2.4 * scale_f)
			if mount_y < -2.1 * scale_f:
				continue
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.18
			var score := 12.0 - absf(h + 0.15) * 1.6 - (h - min_foot) * 1.1 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, mount_y, lp.z)
				found = true

	# Fallback radial seaward walk if nominal coordinates sit too far inland on a shifted reef.
	if not found:
		var out_uv := Vector2(u0, v0)
		out_uv = out_uv.normalized() if out_uv.length_squared() >= 1.0 else Vector2(0.0, -1.0)
		for step_i in range(1, 16):
			var cand_uv := Vector2(u0, v0) + out_uv * (float(step_i) * 3.0)
			var lp := basis * Vector3(cand_uv.x, 0.0, cand_uv.y)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 4.4 * scale_f):
				continue
			if has_mooring and Vector2(lp.x, lp.z).distance_squared_to(moor_xz) < 18.0 * 18.0:
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < -1.8 or h > 1.8:
				continue
			var min_foot := _min_footprint_height_8(island, lp.x, lp.z, 4.2 * scale_f)
			if min_foot < -3.6 * scale_f or h - min_foot > 3.2 * scale_f:
				continue
			var mount_y := minf(h - 0.35 * scale_f, min_foot + 2.4 * scale_f)
			if mount_y < -2.1 * scale_f:
				continue
			best_pos = Vector3(lp.x, mount_y, lp.z)
			found = true
			break

	if not found:
		return false

	var xform := Transform3D(
		Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_SUNKEN_STERN, node_name, xform, 6.8 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_coral_arch(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# GiantTidalCoralArch (~10.5 m wide x ~6.2 m tall, twin reef piers at +/-4.2 m plunging to y_local = -3.25 m)
	# rises out of crystal turquoise coastal shallows (`h = -2.0..+0.7 m`), strictly clear of docks & moorings!
	var arch_basis := Basis(Vector3.UP, yaw)
	var right_dir := arch_basis.x
	var has_mooring := island.mooring_transform != Transform3D.IDENTITY
	var moor_xz := Vector2(island.mooring_transform.origin.x, island.mooring_transform.origin.z)

	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			# Never intrude on an outpost's central seaward pier / sailing approach channel!
			if island.is_outpost and absf(u) < 26.0 and v < -18.0:
				continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 5.0 * scale_f):
				continue
			if has_mooring and Vector2(lp.x, lp.z).distance_squared_to(moor_xz) < 22.0 * 22.0:
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < -2.0 or h > 0.7:
				continue

			var p_l := lp - right_dir * (4.2 * scale_f)
			var p_r := lp + right_dir * (4.2 * scale_f)
			if _in_exclusion_padded(p_l.x, p_l.z, keepout_zones, 2.6 * scale_f):
				continue
			if _in_exclusion_padded(p_r.x, p_r.z, keepout_zones, 2.6 * scale_f):
				continue

			var h_l := _min_footprint_height(island, p_l.x, p_l.z, 1.2 * scale_f)
			var h_r := _min_footprint_height(island, p_r.x, p_r.z, 1.2 * scale_f)
			if minf(h_l, h_r) < -3.1 * scale_f:
				continue
			var span_diff := absf(h_l - h_r)
			if span_diff > 2.4 * scale_f:
				continue

			var mount_y := minf(h - 0.20 * scale_f, minf(h_l, h_r) + 2.2 * scale_f)
			if mount_y < -2.0 * scale_f or mount_y > 0.65 * scale_f:
				continue

			var dist_pen := Vector2(u - u0, v - v0).length() * 0.16
			var score := 12.0 - absf(h + 0.65) * 2.4 - span_diff * 1.4 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, mount_y, lp.z)
				found = true

	if not found:
		return false

	var xform := Transform3D(
		arch_basis * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_CORAL_ARCH, node_name, xform, 6.4 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_lava_shrine(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		h_min: float, h_max: float, placed: Array[Vector3],
		keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# ObsidianLavaCauldronShrine (~6.4 m wide x ~5.8 m tall, basalt ring plunging to y_local = -2.25 m)
	# seats cleanly on Cinder Crag volcanic terrace/ridge benches (`h = 4.0..34.0 m`, `n.y >= 0.65`)!
	var eff_h_min := maxf(4.0, h_min)
	var eff_h_max := minf(34.0, h_max)
	var h_mid := (eff_h_min + eff_h_max) * 0.5
	var trail_polys := IslandTrails.get_trail_polylines(island.archetype, island.island_radius, island.island_id)
	var trail_clear := IslandTrails.get_trail_half_width(island.archetype) + 3.8 * scale_f

	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			if not trail_polys.is_empty() and _min_dist_to_trails_uv(u, v, trail_polys) < trail_clear:
				continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 4.0 * scale_f):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < eff_h_min or h > eff_h_max:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.2)
			if n.y < 0.65:
				continue
			var min_foot := _min_footprint_height_8(island, lp.x, lp.z, 2.9 * scale_f)
			if min_foot < 2.5 or h - min_foot > 1.8 * scale_f:
				continue
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.16
			var score := n.y * 8.0 - (h - min_foot) * 1.8 - absf(h - h_mid) * 0.22 - dist_pen
			if score > best_score:
				best_score = score
				var mount_y := minf(h - 0.35 * scale_f, min_foot + 1.45 * scale_f)
				best_pos = Vector3(lp.x, mount_y, lp.z)
				found = true

	if not found:
		return false

	var xform := Transform3D(
		Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_LAVA_SHRINE, node_name, xform, 5.2 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_harbour_crane(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, scan_span: float, prefer_dir: Vector3, scale_f: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# HarbourCargoCraneDock (~11.4 m tall, footing +/-2.95 m plunging to y_local = -3.60 m,
	# deck y_local = +1.12 m, cantilevered cargo jib reaching z_local = -5.45 m toward seaward -Z).
	var trail_polys := IslandTrails.get_trail_polylines(island.archetype, island.island_radius, island.island_id)
	var trail_clear := IslandTrails.get_trail_half_width(island.archetype) + 3.4 * scale_f
	var has_mooring := island.mooring_transform != Transform3D.IDENTITY
	var moor_xz := Vector2(island.mooring_transform.origin.x, island.mooring_transform.origin.z)
	var inv_basis := basis.inverse()

	var best_pos := Vector3.ZERO
	var best_out := prefer_dir
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			# Strict clearance from outpost dock pier planks & central mooring approach!
			if island.is_outpost and absf(u) < 16.5 and v < -14.0 and v > -52.0:
				continue
			if not trail_polys.is_empty() and _min_dist_to_trails_uv(u, v, trail_polys) < trail_clear:
				continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 3.8 * scale_f):
				continue
			if has_mooring and Vector2(lp.x, lp.z).distance_squared_to(moor_xz) < 15.0 * 15.0:
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 0.9 or h > 10.5:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.0)
			if n.y < 0.70:
				continue

			var out_xz := _horizontal_outward(n, lp, prefer_dir)
			var aim_raw := out_xz * 0.45 + prefer_dir * 0.55
			aim_raw.y = 0.0
			var aim_xz := aim_raw.normalized() if aim_raw.length_squared() > 0.001 else prefer_dir
			var right_d := Vector3(-aim_xz.z, 0.0, aim_xz.x)

			# Verify cantilevered jib & suspended cargo sling stay clear of dock pier planks & moorings!
			var jib_p := lp + aim_xz * (5.2 * scale_f)
			if has_mooring and Vector2(jib_p.x, jib_p.z).distance_squared_to(moor_xz) < 11.5 * 11.5:
				continue
			if island.is_outpost:
				var jib_uv := inv_basis * Vector3(jib_p.x, 0.0, jib_p.z)
				if absf(jib_uv.x) < 11.5 and jib_uv.z < -18.0 and jib_uv.z > -48.0:
					continue
			var h_jib := island.surface_height(jib_p.x, jib_p.z)
			if h_jib > h + 0.8:
				continue

			# 4-corner pier footing check (+/-2.65 m x +/-2.55 m): max_y - min_y <= 3.2!
			var min_y := h
			var max_y := h
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var cp := lp + right_d * (sx * 2.65 * scale_f) + aim_xz * (sz * 2.55 * scale_f)
					var ch := island.surface_height(cp.x, cp.z)
					min_y = minf(min_y, ch)
					max_y = maxf(max_y, ch)
			if min_y < -0.6 or max_y - min_y > 3.2:
				continue

			# Seat pier footing so -3.60 m masonry skirt buries deeply below min_y while +1.12 m deck clears max_y!
			var base_y := clampf(max_y - 0.55 * scale_f, min_y + 0.05, min_y + 2.75 * scale_f)
			var water_bonus := 5.5 if h_jib < 1.2 else (2.5 if h_jib < h - 0.8 else 0.0)
			var dir_dot := aim_xz.dot(prefer_dir)
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.14
			var score := n.y * 8.0 + dir_dot * 6.0 + water_bonus - (max_y - min_y) * 1.4 \
				- absf(h - 3.2) * 0.35 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, base_y, lp.z)
				best_out = aim_xz
				found = true

	if not found:
		return false

	var yaw := atan2(-best_out.x, -best_out.z)
	var xform := Transform3D(
		Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_HARBOUR_CRANE, node_name, xform, 5.5 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_jungle_altar(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# OvergrownJungleIdolAltar (~9.2 m x ~8.2 m stepped offering plaza, masonry skirt to y_local = -3.80 m,
	# front ceremonial steps facing -Z) seats on walkable terraces & temple clearings!
	var altar_basis := Basis(Vector3.UP, yaw)
	var right_d := altar_basis.x
	var fwd_d := altar_basis.z
	var trail_polys := IslandTrails.get_trail_polylines(island.archetype, island.island_radius, island.island_id)
	var trail_clear := IslandTrails.get_trail_half_width(island.archetype) + 4.8 * scale_f

	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			if not trail_polys.is_empty() and _min_dist_to_trails_uv(u, v, trail_polys) < trail_clear:
				continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 5.2 * scale_f):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 3.5 or h > 42.0:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.2)
			if n.y < 0.72:
				continue

			# 4-corner terrace relief check (+/-4.4 m x +/-3.9 m): max_y - min_y <= 3.0!
			var min_corner_h := INF
			var max_corner_h := -INF
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var cp := lp + right_d * (sx * 4.4 * scale_f) + fwd_d * (sz * 3.9 * scale_f)
					var ch := island.surface_height(cp.x, cp.z)
					min_corner_h = minf(min_corner_h, ch)
					max_corner_h = maxf(max_corner_h, ch)
			var min_y := minf(min_corner_h, h)
			var max_y := maxf(max_corner_h, h)
			if min_y < 2.2 or max_y - min_y > 3.0:
				continue

			# Sink origin cleanly to min_corner_h + 0.15 so -3.80 m skirt roots every corner underground!
			var base_y := min_corner_h + 0.15
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.14
			var score := n.y * 10.0 - (max_y - min_y) * 4.2 + clampf(h * 0.08, 0.0, 3.0) - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, base_y, lp.z)
				found = true

	if not found:
		return false

	var xform := Transform3D(
		altar_basis * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_JUNGLE_ALTAR, node_name, xform, 6.6 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_waterfall_shrine(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, u_span: float, v_span: float, h_min: float, h_max: float,
		prefer_dir: Vector3, scale_f: float, placed: Array[Vector3],
		keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# CliffsideWaterfallShrine (~10.2 m tall x ~9.0 m wide, facing outward -Z) has a -4.20 m
	# stepped stone base + solid +4.50 m rear cliff-weld masonry backing so it welds flush into cliffs!
	var eff_h_min := maxf(2.5, h_min)
	var eff_h_max := minf(36.0, h_max)
	var trail_polys := IslandTrails.get_trail_polylines(island.archetype, island.island_radius, island.island_id)
	var trail_clear := IslandTrails.get_trail_half_width(island.archetype) + 4.0 * scale_f

	var best_pos := Vector3.ZERO
	var best_out := prefer_dir
	var best_score := -INF
	var found := false

	for iu in range(-5, 6):
		var u := u0 + float(iu) * (u_span * 0.1)
		for iv in range(-5, 6):
			var v := v0 + float(iv) * (v_span * 0.1)
			if not trail_polys.is_empty() and _min_dist_to_trails_uv(u, v, trail_polys) < trail_clear:
				continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 4.6 * scale_f):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < eff_h_min or h > eff_h_max:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.5)
			if n.y < 0.25 or n.y > 0.94:
				continue
			var out_xz := _horizontal_outward(n, lp, prefer_dir)
			var dir_dot := out_xz.dot(prefer_dir)
			if dir_dot < 0.05:
				continue
			var side_xz := Vector3(-out_xz.z, 0.0, out_xz.x)

			# Sample front steps (+3.0 m along seaward out_xz) and rear cliff-weld wall (+4.0 m behind)!
			var front_c := lp + out_xz * (3.0 * scale_f)
			var front_l := front_c - side_xz * (3.8 * scale_f)
			var front_r := front_c + side_xz * (3.8 * scale_f)
			if _in_exclusion_padded(front_c.x, front_c.z, keepout_zones, 2.4 * scale_f):
				continue
			var h_fc := island.surface_height(front_c.x, front_c.z)
			var h_fl := island.surface_height(front_l.x, front_l.z)
			var h_fr := island.surface_height(front_r.x, front_r.z)
			var min_front_h := minf(h_fc, minf(h_fl, h_fr))
			var max_front_h := maxf(h_fc, maxf(h_fl, h_fr))
			if min_front_h < 1.2 or max_front_h - min_front_h > 2.6 * scale_f:
				continue

			var rear_c := lp - out_xz * (4.0 * scale_f)
			var rear_l := rear_c - side_xz * (3.6 * scale_f)
			var rear_r := rear_c + side_xz * (3.6 * scale_f)
			var h_rc := island.surface_height(rear_c.x, rear_c.z)
			var h_rl := island.surface_height(rear_l.x, rear_l.z)
			var h_rr := island.surface_height(rear_r.x, rear_r.z)
			var min_rear_h := minf(h_rc, minf(h_rl, h_rr))
			# Rear wall +4.0 m behind MUST rise clearly higher than front steps so masonry welds cleanly!
			if h_rc <= max_front_h + 1.8 * scale_f or min_rear_h <= min_front_h + 1.5 * scale_f:
				continue

			var base_y := min_front_h - 0.15
			if h - base_y > 3.8 * scale_f:
				continue
			var rear_rise := h_rc - min_front_h
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.14
			var score := dir_dot * 9.0 + clampf(rear_rise, 0.0, 9.0) * 1.15 \
				- (max_front_h - min_front_h) * 2.2 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, base_y, lp.z)
				best_out = out_xz
				found = true

	if not found:
		return false

	var yaw := atan2(-best_out.x, -best_out.z)
	var xform := Transform3D(
		Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_WATERFALL_SHRINE, node_name, xform, 6.0 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_smuggler_hoard(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# SmugglerContrabandHoard (~6.4 m x ~5.0 m tarpaulin pirate stash, bedding skirt to y_local = -1.80 m,
	# guy stakes at +/-3.08 m x +/-2.30 m) sits strictly on gentle sheltered beach/cove/grotto ground!
	var hoard_basis := Basis(Vector3.UP, yaw)
	var right_d := hoard_basis.x
	var fwd_d := hoard_basis.z
	var trail_polys := IslandTrails.get_trail_polylines(island.archetype, island.island_radius, island.island_id)
	var trail_clear := IslandTrails.get_trail_half_width(island.archetype) + 3.8 * scale_f

	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			if not trail_polys.is_empty() and _min_dist_to_trails_uv(u, v, trail_polys) < trail_clear:
				continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 3.8 * scale_f):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 0.9 or h > 18.0:
				continue
			var n := island.surface_normal(lp.x, lp.z, 1.8)
			if n.y < 0.74:
				continue

			# 4-corner footprint check (+/-3.1 m x +/-2.3 m): max_y - min_y <= 1.6!
			var min_corner_h := INF
			var max_corner_h := -INF
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var cp := lp + right_d * (sx * 3.1 * scale_f) + fwd_d * (sz * 2.3 * scale_f)
					var ch := island.surface_height(cp.x, cp.z)
					min_corner_h = minf(min_corner_h, ch)
					max_corner_h = maxf(max_corner_h, ch)
			var min_y := minf(min_corner_h, h)
			var max_y := maxf(max_corner_h, h)
			if min_y < 0.55 or max_y - min_y > 1.6 or h - min_corner_h > 0.95:
				continue

			# Seat bedding skirt cleanly at min_corner_h + 0.05 so zero corner or stake ever hovers!
			var base_y := min_corner_h + 0.05
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.16
			var score := n.y * 10.0 - (max_y - min_y) * 5.0 - absf(h - 3.2) * 0.18 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, base_y, lp.z)
				found = true

	if not found:
		return false

	var xform := Transform3D(
		hoard_basis * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_SMUGGLER_HOARD, node_name, xform, 4.6 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_fort_watchtower(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# FortCoastalWatchtowerRuin (~12.6 m tall at finial, chamfered battered masonry foundation
	# +/-3.22 m plunging to y_local = -4.00 m) guards fortified harbour headlands & sea-fort bluffs!
	var tower_basis := Basis(Vector3.UP, yaw)
	var right_d := tower_basis.x
	var fwd_d := tower_basis.z
	var trail_polys := IslandTrails.get_trail_polylines(island.archetype, island.island_radius, island.island_id)
	var trail_clear := IslandTrails.get_trail_half_width(island.archetype) + 4.4 * scale_f
	var scale_r := island.island_radius / 60.0
	var is_fort := island.archetype == &"fort_rock" or island.archetype == &"grand_citadel"
	var bastion_uv := Vector2(0.0, 18.0 if island.archetype == &"grand_citadel" else 2.0 * scale_r)
	var bastion_clear := 27.0 if island.archetype == &"grand_citadel" else 23.0

	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			# Strict clearance from walkable trails, FortBastion center, and outpost village buildings!
			if not trail_polys.is_empty() and _min_dist_to_trails_uv(u, v, trail_polys) < trail_clear:
				continue
			if is_fort and Vector2(u, v).distance_to(bastion_uv) < bastion_clear:
				continue
			if island.is_outpost:
				if absf(u) < 20.0 and v < -4.0:
					continue
				if Vector2(u - 24.0, v + 6.5).length() < 14.5:
					continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 5.0 * scale_f):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 5.0 or h > 44.0:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.2)
			if n.y < 0.68:
				continue

			# 4-corner masonry footing check (+/-3.0 m x +/-3.0 m): max_y - min_y <= 3.2!
			var min_corner_h := INF
			var max_corner_h := -INF
			var corner_blocked := false
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var cp := lp + right_d * (sx * 3.0 * scale_f) + fwd_d * (sz * 3.0 * scale_f)
					if _in_exclusion_padded(cp.x, cp.z, keepout_zones, 2.0 * scale_f):
						corner_blocked = true
						break
					var ch := island.surface_height(cp.x, cp.z)
					min_corner_h = minf(min_corner_h, ch)
					max_corner_h = maxf(max_corner_h, ch)
				if corner_blocked:
					break
			if corner_blocked:
				continue
			var min_y := minf(min_corner_h, h)
			var max_y := maxf(max_corner_h, h)
			if min_y < 3.0 or max_y - min_y > 3.2:
				continue

			# Seat tower origin at min_corner_h + 0.2 so the -4.0 m solid masonry skirt roots deeply!
			var base_y := min_corner_h + 0.2
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.14
			var score := n.y * 8.5 + clampf(h * 0.14, 0.0, 4.5) - (max_y - min_y) * 2.4 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, base_y, lp.z)
				found = true

	if not found:
		return false

	var xform := Transform3D(
		tower_basis * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_FORT_WATCHTOWER, node_name, xform, 5.8 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_reef_beacon(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# ShipwreckBellBuoyBeacon (~9.6 m tall tripod warning beacon, -4.5 m stone-crib & piling base
	# plunging below shallow seabed) stands in outer surf/shoal water strictly clear of piers & moorings!
	var has_mooring := island.mooring_transform != Transform3D.IDENTITY
	var moor_xz := Vector2(island.mooring_transform.origin.x, island.mooring_transform.origin.z)

	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			# Strict clearance from outpost dock piers & central harbour approach channel!
			if island.is_outpost and absf(u) < 22.0 and v < -14.0:
				continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 5.2 * scale_f):
				continue
			if has_mooring and Vector2(lp.x, lp.z).distance_squared_to(moor_xz) < 18.0 * 18.0:
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < -3.2 or h > 0.9:
				continue
			var base_y := maxf(h, -1.6) + 0.35
			var min_foot := _min_footprint_height(island, lp.x, lp.z, 2.4 * scale_f)
			if min_foot < base_y - 4.0 * scale_f:
				continue
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.14
			var score := 12.0 - absf(h + 0.75) * 2.2 - absf(h - min_foot) * 0.8 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, base_y, lp.z)
				found = true

	# Fallback radial shoreline search if organic coastline noise shifts the shoal shelf from (u0, v0).
	if not found:
		var out_uv := Vector2(u0, v0)
		out_uv = out_uv.normalized() if out_uv.length_squared() >= 1.0 else Vector2(0.0, -1.0)
		var tan_uv := Vector2(-out_uv.y, out_uv.x)
		for step_i in range(-8, 19):
			var rad_off := float(step_i) * 2.5
			for tang_off: float in [0.0, -8.0, 8.0]:
				var cand_uv := Vector2(u0, v0) + out_uv * rad_off + tan_uv * tang_off
				if island.is_outpost and absf(cand_uv.x) < 22.0 and cand_uv.y < -14.0:
					continue
				var lp := basis * Vector3(cand_uv.x, 0.0, cand_uv.y)
				if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 5.2 * scale_f):
					continue
				if has_mooring and Vector2(lp.x, lp.z).distance_squared_to(moor_xz) < 18.0 * 18.0:
					continue
				var h := island.surface_height(lp.x, lp.z)
				if h < -3.2 or h > 0.9:
					continue
				var base_y := maxf(h, -1.6) + 0.35
				var min_foot := _min_footprint_height(island, lp.x, lp.z, 2.4 * scale_f)
				if min_foot < base_y - 4.0 * scale_f:
					continue
				var score := 10.0 - absf(h + 0.75) * 2.2 - absf(rad_off) * 0.10 - absf(tang_off) * 0.12
				if score > best_score:
					best_score = score
					best_pos = Vector3(lp.x, base_y, lp.z)
					found = true

	if not found:
		return false

	var xform := Transform3D(
		Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_REEF_BEACON, node_name, xform, 5.2 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_compass_monolith(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# AncientCompassMonolithRing (~9.4 m diameter circular dais with -3.6 m stone skirt, glowing brass
	# compass sundial & 5 leaning standing rune monoliths) sits on gentle sacred clearings & terraces!
	var ring_basis := Basis(Vector3.UP, yaw)
	var right_d := ring_basis.x
	var fwd_d := ring_basis.z
	var trail_polys := IslandTrails.get_trail_polylines(island.archetype, island.island_radius, island.island_id)
	var trail_clear := IslandTrails.get_trail_half_width(island.archetype) + 5.2 * scale_f

	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			if not trail_polys.is_empty() and _min_dist_to_trails_uv(u, v, trail_polys) < trail_clear:
				continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 5.4 * scale_f):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 3.0 or h > 44.0:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.2)
			if n.y < 0.74:
				continue

			# 4-corner dais perimeter relief check (+/-3.6 m x +/-3.6 m, r ~ 5.09 m): max_y - min_y <= 2.6!
			var min_corner_h := INF
			var max_corner_h := -INF
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var cp := lp + right_d * (sx * 3.6 * scale_f) + fwd_d * (sz * 3.6 * scale_f)
					var ch := island.surface_height(cp.x, cp.z)
					min_corner_h = minf(min_corner_h, ch)
					max_corner_h = maxf(max_corner_h, ch)
			var min_y := minf(min_corner_h, h)
			var max_y := maxf(max_corner_h, h)
			if min_y < 2.0 or max_y - min_y > 2.6:
				continue

			# Seat circular stone dais cleanly at min_corner_h + 0.1 so the -3.6 m skirt buries every rim!
			var base_y := min_corner_h + 0.1
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.14
			var score := n.y * 12.0 - (max_y - min_y) * 4.5 + clampf(h * 0.08, 0.0, 3.0) - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, base_y, lp.z)
				found = true

	if not found:
		return false

	var xform := Transform3D(
		ring_basis * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_COMPASS_MONOLITH, node_name, xform, 6.6 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_volcanic_chain_pylon(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# VolcanicChainBridgeAnchor (~11.5 m tall obsidian-basalt iron-chained anchor pylon with
	# -4.5 m flaring bedrock root & rooted flank mooring boulders) crowns ridges & coastal headlands!
	var pylon_basis := Basis(Vector3.UP, yaw)
	var right_d := pylon_basis.x
	var fwd_d := pylon_basis.z
	var trail_polys := IslandTrails.get_trail_polylines(island.archetype, island.island_radius, island.island_id)
	var trail_clear := IslandTrails.get_trail_half_width(island.archetype) + 4.4 * scale_f

	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			if not trail_polys.is_empty() and _min_dist_to_trails_uv(u, v, trail_polys) < trail_clear:
				continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 4.8 * scale_f):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 4.0 or h > 50.0:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.2)
			if n.y < 0.60:
				continue

			# 4-corner bedrock root & flank boulder check (+/-3.4 m x +/-3.4 m): max_y - min_y <= 4.0!
			var min_corner_h := INF
			var max_corner_h := -INF
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var cp := lp + right_d * (sx * 3.4 * scale_f) + fwd_d * (sz * 3.4 * scale_f)
					var ch := island.surface_height(cp.x, cp.z)
					min_corner_h = minf(min_corner_h, ch)
					max_corner_h = maxf(max_corner_h, ch)
			var min_y := minf(min_corner_h, h)
			var max_y := maxf(max_corner_h, h)
			if min_y < 2.0 or max_y - min_y > 4.0:
				continue

			# Seat pylon root at min_corner_h + 0.25 so the -4.5 m flaring basalt base anchors deeply!
			var base_y := min_corner_h + 0.25
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.14
			var score := n.y * 8.0 + clampf(h * 0.12, 0.0, 4.5) - (max_y - min_y) * 1.8 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, base_y, lp.z)
				found = true

	if not found:
		return false

	var xform := Transform3D(
		pylon_basis * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_VOLCANIC_CHAIN_PYLON, node_name, xform, 5.8 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_ship_drydock(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, scan_span: float, prefer_dir: Vector3, scale_f: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# CareeningShipDrydock (~10.2 m long x ~6.4 m wide, battered stone-and-piling slipway
	# plunging to y_local = -3.60 m, sloping from Y_SEA=+0.24 at -Z up to Y_LAND=+1.56 at +Z)
	# sits perpendicular to sandy harbour & cove beaches, strictly clear of piers, moorings & trails!
	var trail_polys := IslandTrails.get_trail_polylines(island.archetype, island.island_radius, island.island_id)
	var trail_clear := IslandTrails.get_trail_half_width(island.archetype) + 5.2 * scale_f
	var has_mooring := island.mooring_transform != Transform3D.IDENTITY
	var moor_xz := Vector2(island.mooring_transform.origin.x, island.mooring_transform.origin.z)
	var inv_basis := basis.inverse()

	var best_pos := Vector3.ZERO
	var best_out := prefer_dir
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			# Strict clearance from outpost dock piers, central harbour channel & village buildings!
			if island.is_outpost:
				if absf(u) < 22.0 and v < 6.0:
					continue
				if Vector2(u - 24.0, v + 6.5).length() < 15.0:
					continue
				if Vector2(u + 23.5, v + 16.5).length() < 14.0:
					continue
			if not trail_polys.is_empty() and _min_dist_to_trails_uv(u, v, trail_polys) < trail_clear:
				continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 5.4 * scale_f):
				continue
			if has_mooring and Vector2(lp.x, lp.z).distance_squared_to(moor_xz) < 18.0 * 18.0:
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 0.8 or h > 5.8:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.2)
			if n.y < 0.76:
				continue

			# Orient local -Z slipway toe strictly perpendicular to the beach water (downhill normal)!
			var out_xz := _horizontal_outward(n, lp, prefer_dir)
			var dir_dot := out_xz.dot(prefer_dir)
			if dir_dot < -0.15:
				continue
			var right_d := Vector3(-out_xz.z, 0.0, out_xz.x)

			# Verify seaward slipway toe drops toward water and stays strictly >= 18 m from mooring & piers!
			var sea_p := lp + out_xz * (5.2 * scale_f)
			var land_p := lp - out_xz * (5.2 * scale_f)
			if has_mooring and Vector2(sea_p.x, sea_p.z).distance_squared_to(moor_xz) < 18.0 * 18.0:
				continue
			if island.is_outpost:
				var sea_uv := inv_basis * Vector3(sea_p.x, 0.0, sea_p.z)
				if absf(sea_uv.x) < 18.0 and sea_uv.z < -8.0:
					continue
			var h_sea := island.surface_height(sea_p.x, sea_p.z)
			var h_land := island.surface_height(land_p.x, land_p.z)
			if h_sea >= h_land or h_sea > h + 0.1:
				continue

			# 4-corner slipway footprint check (+/-3.1 m width x +/-4.8 m length): max_y - min_y <= 2.4!
			var min_corner_h := INF
			var max_corner_h := -INF
			var corner_blocked := false
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var cp := lp + right_d * (sx * 3.1 * scale_f) + out_xz * (sz * 4.8 * scale_f)
					if _in_exclusion_padded(cp.x, cp.z, keepout_zones, 2.0 * scale_f):
						corner_blocked = true
						break
					var ch := island.surface_height(cp.x, cp.z)
					min_corner_h = minf(min_corner_h, ch)
					max_corner_h = maxf(max_corner_h, ch)
				if corner_blocked:
					break
			if corner_blocked:
				continue
			var min_y := minf(min_corner_h, h)
			var max_y := maxf(max_corner_h, h)
			if min_y < -0.8 or max_y - min_y > 2.4:
				continue

			# Seat slipway origin at min_corner_h + 0.10 so the -3.6 m stone/piling foundation roots deeply!
			var base_y := min_corner_h + 0.10
			var water_bonus := 4.5 if h_sea < 0.85 else (2.0 if h_sea < 1.6 else 0.0)
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.14
			var score := n.y * 8.0 + dir_dot * 4.0 + water_bonus - (max_y - min_y) * 3.5 \
				- absf(h - 2.0) * 1.4 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, base_y, lp.z)
				best_out = out_xz
				found = true

	if not found:
		return false

	var yaw := atan2(-best_out.x, -best_out.z)
	var xform := Transform3D(
		Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_SHIP_DRYDOCK, node_name, xform, 6.4 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_skeleton_throne(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# CursedSkeletonThroneShrine (~7.8 m wide x ~7.2 m tall jagged ancient stone & bone captain's
	# throne dais with -3.6 m stepped foundation skirt) crowns dramatic clearings & highland terraces!
	var throne_basis := Basis(Vector3.UP, yaw)
	var right_d := throne_basis.x
	var fwd_d := throne_basis.z
	var trail_polys := IslandTrails.get_trail_polylines(island.archetype, island.island_radius, island.island_id)
	var trail_clear := IslandTrails.get_trail_half_width(island.archetype) + 4.8 * scale_f
	var scale_r := island.island_radius / 60.0
	var is_fort := island.archetype == &"fort_rock" or island.archetype == &"grand_citadel"
	var bastion_uv := Vector2(0.0, 18.0 if island.archetype == &"grand_citadel" else 2.0 * scale_r)
	var bastion_clear := 28.0 if island.archetype == &"grand_citadel" else 23.0

	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			if not trail_polys.is_empty() and _min_dist_to_trails_uv(u, v, trail_polys) < trail_clear:
				continue
			if is_fort and Vector2(u, v).distance_to(bastion_uv) < bastion_clear:
				continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 5.0 * scale_f):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 3.5 or h > 44.0:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.2)
			if n.y < 0.72:
				continue

			# 4-corner stepped dais footprint check (+/-3.8 m x +/-3.4 m): max_y - min_y <= 2.8!
			var min_corner_h := INF
			var max_corner_h := -INF
			var corner_blocked := false
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var cp := lp + right_d * (sx * 3.8 * scale_f) + fwd_d * (sz * 3.4 * scale_f)
					if _in_exclusion_padded(cp.x, cp.z, keepout_zones, 2.0 * scale_f):
						corner_blocked = true
						break
					var ch := island.surface_height(cp.x, cp.z)
					min_corner_h = minf(min_corner_h, ch)
					max_corner_h = maxf(max_corner_h, ch)
				if corner_blocked:
					break
			if corner_blocked:
				continue
			var min_y := minf(min_corner_h, h)
			var max_y := maxf(max_corner_h, h)
			if min_y < 2.0 or max_y - min_y > 2.8:
				continue

			# Seat throne dais cleanly at min_corner_h + 0.10 so the -3.6 m stepped skirt anchors solidly!
			var base_y := min_corner_h + 0.10
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.14
			var score := n.y * 10.0 + clampf(h * 0.12, 0.0, 4.5) - (max_y - min_y) * 4.0 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, base_y, lp.z)
				found = true

	if not found:
		return false

	var xform := Transform3D(
		throne_basis * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_SKELETON_THRONE, node_name, xform, 6.0 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_fishing_hut(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, scan_span: float, prefer_dir: Vector3, scale_f: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# TropicalFishingStiltsHut (~8.2 m wide x ~7.4 m tall weathered palm-thatched stilt shelter with
	# -4.6 m barnacle-crusted driven pilings & seaward fishing deck at -Z) perches along cove edges!
	var trail_polys := IslandTrails.get_trail_polylines(island.archetype, island.island_radius, island.island_id)
	var trail_clear := IslandTrails.get_trail_half_width(island.archetype) + 4.6 * scale_f
	var has_mooring := island.mooring_transform != Transform3D.IDENTITY
	var moor_xz := Vector2(island.mooring_transform.origin.x, island.mooring_transform.origin.z)
	var inv_basis := basis.inverse()

	var best_pos := Vector3.ZERO
	var best_out := prefer_dir
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			# Strict clearance from outpost dock piers, central harbour channel & village buildings!
			if island.is_outpost:
				if absf(u) < 22.0 and v < 6.0:
					continue
				if Vector2(u - 24.0, v + 6.5).length() < 15.0:
					continue
			if not trail_polys.is_empty() and _min_dist_to_trails_uv(u, v, trail_polys) < trail_clear:
				continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 4.8 * scale_f):
				continue
			if has_mooring and Vector2(lp.x, lp.z).distance_squared_to(moor_xz) < 18.0 * 18.0:
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 0.3 or h > 4.2:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.0)
			if n.y < 0.72:
				continue

			var out_xz := _horizontal_outward(n, lp, prefer_dir)
			var aim_raw := out_xz * 0.65 + prefer_dir * 0.35
			aim_raw.y = 0.0
			var aim_xz := aim_raw.normalized() if aim_raw.length_squared() > 0.001 else prefer_dir
			var right_d := Vector3(-aim_xz.z, 0.0, aim_xz.x)

			# Verify seaward fishing deck faces cove water & stays >= 18 m from mooring and clear of piers!
			var deck_front := lp + aim_xz * (3.5 * scale_f)
			if has_mooring and Vector2(deck_front.x, deck_front.z).distance_squared_to(moor_xz) < 18.0 * 18.0:
				continue
			if island.is_outpost:
				var deck_uv := inv_basis * Vector3(deck_front.x, 0.0, deck_front.z)
				if absf(deck_uv.x) < 18.0 and deck_uv.z < -8.0:
					continue
			var front_h := island.surface_height(deck_front.x, deck_front.z)
			if front_h > h + 0.6:
				continue

			# 4-corner piling footprint check (+/-3.5 m width x +/-2.6 m depth): max_y - min_y <= 3.0!
			var min_corner_h := INF
			var max_corner_h := -INF
			var corner_blocked := false
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var cp := lp + right_d * (sx * 3.5 * scale_f) + aim_xz * (sz * 2.6 * scale_f)
					if _in_exclusion_padded(cp.x, cp.z, keepout_zones, 1.8 * scale_f):
						corner_blocked = true
						break
					var ch := island.surface_height(cp.x, cp.z)
					min_corner_h = minf(min_corner_h, ch)
					max_corner_h = maxf(max_corner_h, ch)
				if corner_blocked:
					break
			if corner_blocked:
				continue
			var min_y := minf(min_corner_h, h)
			var max_y := maxf(max_corner_h, h)
			if min_y < -2.2 or max_y - min_y > 3.0:
				continue

			# Seat stilt hut origin at min_corner_h + 0.20 so all -4.6 m barnacle pilings drive deeply!
			var base_y := min_corner_h + 0.20
			var dir_dot := aim_xz.dot(prefer_dir)
			var cove_bonus := 3.5 if front_h < 0.9 else (1.5 if front_h < h - 0.3 else 0.0)
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.14
			var score := n.y * 9.0 + dir_dot * 4.5 + cove_bonus - (max_y - min_y) * 3.5 \
				- absf(h - 1.5) * 1.4 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, base_y, lp.z)
				best_out = aim_xz
				found = true

	if not found:
		return false

	var yaw := atan2(-best_out.x, -best_out.z)
	var xform := Transform3D(
		Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_FISHING_HUT, node_name, xform, 5.6 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_astronomer_orrery(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# AncientAstronomerOrreryRuin (~8.8 m diameter circular carved temple-stone observatory dais with
	# -3.8 m battered plinth & towering brass armillary sphere) crowns scenic highland ridges!
	var orrery_basis := Basis(Vector3.UP, yaw)
	var right_d := orrery_basis.x
	var fwd_d := orrery_basis.z
	var trail_polys := IslandTrails.get_trail_polylines(island.archetype, island.island_radius, island.island_id)
	var trail_clear := IslandTrails.get_trail_half_width(island.archetype) + 5.2 * scale_f
	var scale_r := island.island_radius / 60.0
	var is_fort := island.archetype == &"fort_rock" or island.archetype == &"grand_citadel"
	var bastion_uv := Vector2(0.0, 18.0 if island.archetype == &"grand_citadel" else 2.0 * scale_r)
	var bastion_clear := 28.0 if island.archetype == &"grand_citadel" else 23.0

	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			if not trail_polys.is_empty() and _min_dist_to_trails_uv(u, v, trail_polys) < trail_clear:
				continue
			if is_fort and Vector2(u, v).distance_to(bastion_uv) < bastion_clear:
				continue
			if island.is_outpost:
				if absf(u) < 20.0 and v < -4.0:
					continue
				if Vector2(u - 24.0, v + 6.5).length() < 15.0:
					continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 5.4 * scale_f):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 5.5 or h > 50.0:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.2)
			if n.y < 0.72:
				continue

			# 4-corner circular observatory plinth check (+/-3.5 m x +/-3.5 m, r ~ 4.95 m): max_y - min_y <= 3.0!
			var min_corner_h := INF
			var max_corner_h := -INF
			var corner_blocked := false
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var cp := lp + right_d * (sx * 3.5 * scale_f) + fwd_d * (sz * 3.5 * scale_f)
					if _in_exclusion_padded(cp.x, cp.z, keepout_zones, 2.0 * scale_f):
						corner_blocked = true
						break
					var ch := island.surface_height(cp.x, cp.z)
					min_corner_h = minf(min_corner_h, ch)
					max_corner_h = maxf(max_corner_h, ch)
				if corner_blocked:
					break
			if corner_blocked:
				continue
			var min_y := minf(min_corner_h, h)
			var max_y := maxf(max_corner_h, h)
			if min_y < 3.0 or max_y - min_y > 3.0:
				continue

			# Seat observatory dais at min_corner_h + 0.10 so the -3.8 m battered plinth buries every rim!
			var base_y := min_corner_h + 0.10
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.14
			var score := n.y * 10.0 + clampf(h * 0.18, 0.0, 7.5) - (max_y - min_y) * 4.0 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, base_y, lp.z)
				found = true

	if not found:
		return false

	var xform := Transform3D(
		orrery_basis * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_ASTRONOMER_ORRERY, node_name, xform, 6.4 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_smuggler_jetty(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, scan_span: float, prefer_dir: Vector3, scale_f: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# CoastalSmugglerJetty (~12.0 m long extending seaward toward -Z from z=+0.55 m landward butt
	# to z=-11.45 m seaward tip, 3.4 m wide, heavy barnacle-crusted driven pilings plunging to -4.85 m)
	# projects off non-outpost cove beaches into shallow turquoise surf, >= 18 m clear of moorings!
	if island.is_outpost:
		return false
	var has_mooring := island.mooring_transform != Transform3D.IDENTITY
	var moor_xz := Vector2(island.mooring_transform.origin.x, island.mooring_transform.origin.z)

	var best_pos := Vector3.ZERO
	var best_out := prefer_dir
	var best_score := -INF
	var found := false

	for iu in range(-5, 6):
		var u := u0 + float(iu) * (scan_span * 0.1)
		for iv in range(-5, 6):
			var v := v0 + float(iv) * (scan_span * 0.1)
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 4.4 * scale_f):
				continue
			if has_mooring and Vector2(lp.x, lp.z).distance_squared_to(moor_xz) < 18.0 * 18.0:
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < -0.3 or h > 1.6:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.0)
			if n.y < 0.72:
				continue

			var out_xz := _horizontal_outward(n, lp, prefer_dir)
			var aim_raw := out_xz * 0.65 + prefer_dir * 0.35
			aim_raw.y = 0.0
			var aim_xz := aim_raw.normalized() if aim_raw.length_squared() > 0.001 else prefer_dir
			var dir_dot := aim_xz.dot(prefer_dir)
			if dir_dot < 0.15:
				continue
			var right_d := Vector3(-aim_xz.z, 0.0, aim_xz.x)

			# Verify landward end sits on dry beach (h_land >= 0.7 m) & seaward tip extends over
			# shallow turquoise surf (h_sea < 0.25 m, h_sea < h_land - 0.6), >= 18 m clear of moorings!
			var land_p := lp - aim_xz * (2.2 * scale_f)
			var mid_p := lp + aim_xz * (5.6 * scale_f)
			var sea_p := lp + aim_xz * (11.2 * scale_f)
			if has_mooring:
				if Vector2(mid_p.x, mid_p.z).distance_squared_to(moor_xz) < 18.0 * 18.0:
					continue
				if Vector2(sea_p.x, sea_p.z).distance_squared_to(moor_xz) < 18.0 * 18.0:
					continue
			if _in_exclusion_padded(land_p.x, land_p.z, keepout_zones, 2.6 * scale_f):
				continue
			if _in_exclusion_padded(mid_p.x, mid_p.z, keepout_zones, 3.6 * scale_f):
				continue
			if _in_exclusion_padded(sea_p.x, sea_p.z, keepout_zones, 3.8 * scale_f):
				continue

			var h_land := island.surface_height(land_p.x, land_p.z)
			var h_mid := island.surface_height(mid_p.x, mid_p.z)
			var h_sea := island.surface_height(sea_p.x, sea_p.z)
			if h_land < 0.7 or h_sea >= 0.25 or h_sea >= h_land - 0.6:
				continue

			var base_y := maxf(h, 0.35) + 0.55
			if h_land > base_y + 1.35 * scale_f:
				continue
			var min_piling_h := minf(h_mid, h_sea)
			for sx: float in [-1.0, 1.0]:
				var sl := lp + right_d * (sx * 1.9 * scale_f) + aim_xz * (10.8 * scale_f)
				var sm := lp + right_d * (sx * 1.9 * scale_f) + aim_xz * (5.6 * scale_f)
				min_piling_h = minf(min_piling_h, island.surface_height(sl.x, sl.z))
				min_piling_h = minf(min_piling_h, island.surface_height(sm.x, sm.z))
			if min_piling_h < base_y - 4.30 * scale_f:
				continue

			var dist_pen := Vector2(u - u0, v - v0).length() * 0.14
			var score := dir_dot * 7.0 + n.y * 5.0 - absf(h - 0.72) * 3.0 \
				- absf(h_sea + 0.75) * 1.8 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, base_y, lp.z)
				best_out = aim_xz
				found = true

	if not found:
		return false

	var yaw := atan2(-best_out.x, -best_out.z)
	var xform := Transform3D(
		Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	var inst := _spawn_landmark(island, GLB_SMUGGLER_JETTY, node_name, xform, 5.4 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache)
	if inst == null:
		return false
	# Reserve the seaward half of the 12 m jetty so later sea stacks & props never encroach!
	var sea_keep := Vector3(best_pos.x, 0.0, best_pos.z) + best_out * (6.2 * scale_f)
	var sea_rec := Vector3(sea_keep.x, sea_keep.z, 5.8 * scale_f)
	placed.append(sea_rec)
	keepout_zones.append(sea_rec)
	return true


static func _place_obelisk_gate(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# AncientRuinedObeliskGate (~9.6 m wide along X x ~9.8 m tall, open 4.84 m center archway along Z,
	# twin battered stone plinth footings plunging cleanly to y_local = -3.85 m) frames trails & overlooks!
	var gate_basis := Basis(Vector3.UP, yaw)
	var right_d := gate_basis.x
	var fwd_d := gate_basis.z
	var scale_r := island.island_radius / 60.0
	var is_fort := island.archetype == &"fort_rock" or island.archetype == &"grand_citadel"
	var bastion_uv := Vector2(0.0, 18.0 if island.archetype == &"grand_citadel" else 2.0 * scale_r)
	var bastion_clear := 28.0 if island.archetype == &"grand_citadel" else 23.0

	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			if is_fort and Vector2(u, v).distance_to(bastion_uv) < bastion_clear:
				continue
			if island.is_outpost:
				if absf(u) < 20.0 and v < 4.0:
					continue
				if Vector2(u - 24.0, v + 6.5).length() < 15.0:
					continue
				if Vector2(u + 11.0, v + 7.5).length() < 14.0:
					continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 5.0 * scale_f):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 3.5 or h > 42.0:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.2)
			if n.y < 0.74:
				continue

			# 4-corner twin-pylon plinth check (+/-4.2 m width x +/-1.5 m depth): max_y - min_y <= 2.6!
			var min_corner_h := INF
			var max_corner_h := -INF
			var corner_blocked := false
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var cp := lp + right_d * (sx * 4.2 * scale_f) + fwd_d * (sz * 1.5 * scale_f)
					if _in_exclusion_padded(cp.x, cp.z, keepout_zones, 1.8 * scale_f):
						corner_blocked = true
						break
					var ch := island.surface_height(cp.x, cp.z)
					min_corner_h = minf(min_corner_h, ch)
					max_corner_h = maxf(max_corner_h, ch)
				if corner_blocked:
					break
			if corner_blocked:
				continue
			var min_y := minf(min_corner_h, h)
			var max_y := maxf(max_corner_h, h)
			if min_y < 2.2 or max_y - min_y > 2.6:
				continue

			# Seat obelisk gate plinths at min_corner_h + 0.10 so -3.85 m footings anchor deeply!
			var base_y := min_corner_h + 0.10
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.45
			var score := n.y * 10.0 - (max_y - min_y) * 4.5 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, base_y, lp.z)
				found = true

	if not found:
		return false

	var xform := Transform3D(
		gate_basis * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_OBELISK_GATE, node_name, xform, 5.8 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_trail_footbridge(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# WoodenTrailFootbridge (~10.4 m long along local Z x 3.8 m wide along X, gently arched oak deck
	# y_local = +0.04..+1.00 m, stone abutment piers at z = +/-4.58 m plunging to y_local = -3.45 m)!
	var bridge_basis := Basis(Vector3.UP, yaw)
	var right_d := bridge_basis.x
	var fwd_d := bridge_basis.z
	var scale_r := island.island_radius / 60.0
	var is_fort := island.archetype == &"fort_rock" or island.archetype == &"grand_citadel"
	var bastion_uv := Vector2(0.0, 18.0 if island.archetype == &"grand_citadel" else 2.0 * scale_r)
	var bastion_clear := 28.0 if island.archetype == &"grand_citadel" else 23.0

	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			if is_fort and Vector2(u, v).distance_to(bastion_uv) < bastion_clear:
				continue
			if island.is_outpost:
				if absf(u) < 22.0 and v < 6.0:
					continue
				if Vector2(u - 24.0, v + 6.5).length() < 15.0:
					continue
				if Vector2(u + 11.0, v + 7.5).length() < 14.0:
					continue
				if Vector2(u + 23.5, v + 16.5).length() < 14.0:
					continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 5.0 * scale_f):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 2.0 or h > 38.0:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.2)
			if n.y < 0.72:
				continue

			# 4-corner abutment pier check (+/-2.1 m width x +/-4.6 m span): max_y - min_y <= 3.0!
			var min_corner_h := INF
			var max_corner_h := -INF
			var corner_blocked := false
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var cp := lp + right_d * (sx * 2.1 * scale_f) + fwd_d * (sz * 4.6 * scale_f)
					if _in_exclusion_padded(cp.x, cp.z, keepout_zones, 1.8 * scale_f):
						corner_blocked = true
						break
					var ch := island.surface_height(cp.x, cp.z)
					min_corner_h = minf(min_corner_h, ch)
					max_corner_h = maxf(max_corner_h, ch)
				if corner_blocked:
					break
			if corner_blocked:
				continue
			var min_y := minf(min_corner_h, h)
			var max_y := maxf(max_corner_h, h)
			if min_y < 1.0 or max_y - min_y > 3.0:
				continue

			# Seat bridge origin at min_corner_h + 0.20 so -3.45 m stone abutments anchor deeply
			# while the arched +0.04..+1.00 m oak deck rides cleanly above terrain!
			var base_y := min_corner_h + 0.20
			if h > base_y + 0.90 * scale_f:
				continue
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.45
			var score := n.y * 10.0 - (max_y - min_y) * 4.0 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, base_y, lp.z)
				found = true

	if not found:
		return false

	var xform := Transform3D(
		bridge_basis * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_TRAIL_FOOTBRIDGE, node_name, xform, 5.6 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_lookout_bell(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# PirateLookoutBellFrame (~7.4 m tall ridge-top timber warning bell belfry & spyglass post,
	# flared mossy stone cairn plinth +/-2.74 m x +/-2.38 m plunging cleanly to y_local = -3.25 m)
	# crowns scenic overlooks strictly clear of trails, village buildings, FortBastion & keepouts!
	var bell_basis := Basis(Vector3.UP, yaw)
	var right_d := bell_basis.x
	var fwd_d := bell_basis.z
	var trail_polys := IslandTrails.get_trail_polylines(island.archetype, island.island_radius, island.island_id)
	var trail_clear := IslandTrails.get_trail_half_width(island.archetype) + 4.0 * scale_f
	var scale_r := island.island_radius / 60.0
	var is_fort := island.archetype == &"fort_rock" or island.archetype == &"grand_citadel"
	var bastion_uv := Vector2(0.0, 18.0 if island.archetype == &"grand_citadel" else 2.0 * scale_r)
	var bastion_clear := 28.0 if island.archetype == &"grand_citadel" else 23.0

	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			if not trail_polys.is_empty() and _min_dist_to_trails_uv(u, v, trail_polys) < trail_clear:
				continue
			if is_fort and Vector2(u, v).distance_to(bastion_uv) < bastion_clear:
				continue
			if island.is_outpost:
				if absf(u) < 18.0 and v < 2.0:
					continue
				if Vector2(u - 24.0, v + 6.5).length() < 14.0:
					continue
				if Vector2(u + 11.0, v + 7.5).length() < 13.0:
					continue
				if Vector2(u + 23.5, v + 16.5).length() < 13.0:
					continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 4.4 * scale_f):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 6.0 or h > 48.0:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.0)
			if n.y < 0.72:
				continue

			# 4-corner cairn plinth check (+/-2.65 m x +/-2.45 m): max_y - min_y <= 2.8!
			var min_corner_h := INF
			var max_corner_h := -INF
			var corner_blocked := false
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var cp := lp + right_d * (sx * 2.65 * scale_f) + fwd_d * (sz * 2.45 * scale_f)
					if _in_exclusion_padded(cp.x, cp.z, keepout_zones, 1.8 * scale_f):
						corner_blocked = true
						break
					var ch := island.surface_height(cp.x, cp.z)
					min_corner_h = minf(min_corner_h, ch)
					max_corner_h = maxf(max_corner_h, ch)
				if corner_blocked:
					break
			if corner_blocked:
				continue
			var min_y := minf(min_corner_h, h)
			var max_y := maxf(max_corner_h, h)
			if min_y < 4.0 or max_y - min_y > 2.8:
				continue

			# Seat cairn plinth cleanly at min_corner_h + 0.10 so the -3.25 m base anchors deeply!
			var base_y := min_corner_h + 0.10
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.16
			var score := n.y * 9.0 + clampf(h * 0.16, 0.0, 6.0) - (max_y - min_y) * 3.8 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, base_y, lp.z)
				found = true

	if not found:
		return false

	var xform := Transform3D(
		bell_basis * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_LOOKOUT_BELL, node_name, xform, 4.6 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_supply_cart(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# PirateTavernSupplyCart (~4.6 m long x ~2.4 m wide cargo handcart atop a deeply skirted cobbled
	# hardstand apron +/-1.92 m x +/-3.08 m plunging to y_local = -2.65 m) tucks beside village lanes,
	# harbour approaches & cove camps strictly clear of trails, docks, plazas & keepouts!
	var cart_basis := Basis(Vector3.UP, yaw)
	var right_d := cart_basis.x
	var fwd_d := cart_basis.z
	var trail_polys := IslandTrails.get_trail_polylines(island.archetype, island.island_radius, island.island_id)
	var trail_clear := IslandTrails.get_trail_half_width(island.archetype) + 3.8 * scale_f
	var scale_r := island.island_radius / 60.0
	var is_fort := island.archetype == &"fort_rock" or island.archetype == &"grand_citadel"
	var bastion_uv := Vector2(0.0, 18.0 if island.archetype == &"grand_citadel" else 2.0 * scale_r)
	var bastion_clear := 28.0 if island.archetype == &"grand_citadel" else 23.0

	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			if not trail_polys.is_empty() and _min_dist_to_trails_uv(u, v, trail_polys) < trail_clear:
				continue
			if is_fort and Vector2(u, v).distance_to(bastion_uv) < bastion_clear:
				continue
			if island.is_outpost:
				# Keep strictly clear of dock pier, harbour channel, central plaza, Tavern, Beacon, Merchant & Warehouse!
				if absf(u) < 16.5 and v < -10.0:
					continue
				if Vector2(u + 11.0, v + 7.5).length() < 12.5:
					continue
				if Vector2(u - 24.0, v + 6.5).length() < 12.0:
					continue
				if Vector2(u - 9.2, v + 18.5).length() < 9.5:
					continue
				if Vector2(u + 23.5, v + 16.5).length() < 10.5:
					continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 3.8 * scale_f):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 1.4 or h > 18.0:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.0)
			if n.y < 0.78:
				continue

			# 4-corner cobbled hardstand apron check (+/-1.95 m x +/-3.05 m): max_y - min_y <= 2.0!
			var min_corner_h := INF
			var max_corner_h := -INF
			var corner_blocked := false
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var cp := lp + right_d * (sx * 1.95 * scale_f) + fwd_d * (sz * 3.05 * scale_f)
					if _in_exclusion_padded(cp.x, cp.z, keepout_zones, 1.4 * scale_f):
						corner_blocked = true
						break
					var ch := island.surface_height(cp.x, cp.z)
					min_corner_h = minf(min_corner_h, ch)
					max_corner_h = maxf(max_corner_h, ch)
				if corner_blocked:
					break
			if corner_blocked:
				continue
			var min_y := minf(min_corner_h, h)
			var max_y := maxf(max_corner_h, h)
			if min_y < 1.0 or max_y - min_y > 2.0 or h - min_corner_h > 1.2:
				continue

			# Seat cobbled hardstand at min_corner_h + 0.06 so the -2.65 m skirt plants with zero floating edges!
			var base_y := min_corner_h + 0.06
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.18
			var score := n.y * 12.0 - (max_y - min_y) * 5.0 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, base_y, lp.z)
				found = true

	if not found:
		return false

	var xform := Transform3D(
		cart_basis * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_SUPPLY_CART, node_name, xform, 4.6 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_anchor_memorial(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# SunkenAnchorMemorial (~6.8 m tall impaled iron galleon anchor rooted in a mossy coastal boulder
	# pedestal r ~ 3.25 m plunging cleanly to y_local = -3.60 m) guards dramatic coastal headlands!
	var anchor_basis := Basis(Vector3.UP, yaw)
	var right_d := anchor_basis.x
	var fwd_d := anchor_basis.z
	var trail_polys := IslandTrails.get_trail_polylines(island.archetype, island.island_radius, island.island_id)
	var trail_clear := IslandTrails.get_trail_half_width(island.archetype) + 4.0 * scale_f
	var has_mooring := island.mooring_transform != Transform3D.IDENTITY
	var moor_xz := Vector2(island.mooring_transform.origin.x, island.mooring_transform.origin.z)

	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			if not trail_polys.is_empty() and _min_dist_to_trails_uv(u, v, trail_polys) < trail_clear:
				continue
			if island.is_outpost:
				# Stay far clear of dock channel, Title Screen harbour foreground, Tavern & Beacon!
				if absf(u) < 22.0 and v < 2.0:
					continue
				if Vector2(u + 11.0, v + 7.5).length() < 12.5:
					continue
				if Vector2(u - 24.0, v + 6.5).length() < 12.5:
					continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 4.2 * scale_f):
				continue
			if has_mooring and Vector2(lp.x, lp.z).distance_squared_to(moor_xz) < 16.0 * 16.0:
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 1.0 or h > 16.0:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.0)
			if n.y < 0.66:
				continue

			# 8-point mossy rock pedestal perimeter check (4 corners +/-2.35 m + 4 cardinals 3.25 m): max_y - min_y <= 3.0!
			var min_perim_h := INF
			var max_perim_h := -INF
			var corner_blocked := false
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var cp := lp + right_d * (sx * 2.35 * scale_f) + fwd_d * (sz * 2.35 * scale_f)
					if _in_exclusion_padded(cp.x, cp.z, keepout_zones, 1.6 * scale_f):
						corner_blocked = true
						break
					var ch := island.surface_height(cp.x, cp.z)
					min_perim_h = minf(min_perim_h, ch)
					max_perim_h = maxf(max_perim_h, ch)
				if corner_blocked:
					break
			if corner_blocked:
				continue
			for sgn: float in [-1.0, 1.0]:
				var px := lp + right_d * (sgn * 3.25 * scale_f)
				var pz := lp + fwd_d * (sgn * 3.25 * scale_f)
				var hx := island.surface_height(px.x, px.z)
				var hz := island.surface_height(pz.x, pz.z)
				min_perim_h = minf(min_perim_h, minf(hx, hz))
				max_perim_h = maxf(max_perim_h, maxf(hx, hz))
			var min_y := minf(min_perim_h, h)
			var max_y := maxf(max_perim_h, h)
			if min_y < 0.25 or max_y - min_y > 3.0:
				continue

			# Seat mossy boulder pedestal at min_perim_h + 0.08 so the -3.60 m rock root buries every edge!
			var base_y := min_perim_h + 0.08
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.16
			var score := n.y * 8.0 + clampf(h * 0.22, 0.0, 3.5) - (max_y - min_y) * 2.5 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, base_y, lp.z)
				found = true

	if not found:
		return false

	var xform := Transform3D(
		anchor_basis * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_ANCHOR_MEMORIAL, node_name, xform, 5.0 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_sundial_plaza(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# AncientSunDialPlaza (~7.4 m octagonal mossy temple dais, r = 4.35 m deep ashlar foundation skirt
	# plunging cleanly to y_local = -3.40 m) crowns sunlit highland ridges & meadow terraces!
	var plaza_basis := Basis(Vector3.UP, yaw)
	var right_d := plaza_basis.x
	var fwd_d := plaza_basis.z
	var trail_polys := IslandTrails.get_trail_polylines(island.archetype, island.island_radius, island.island_id)
	var trail_clear := IslandTrails.get_trail_half_width(island.archetype) + 4.8 * scale_f
	var scale_r := island.island_radius / 60.0
	var is_fort := island.archetype == &"fort_rock" or island.archetype == &"grand_citadel"
	var bastion_uv := Vector2(0.0, 18.0 if island.archetype == &"grand_citadel" else 2.0 * scale_r)
	var bastion_clear := 28.0 if island.archetype == &"grand_citadel" else 23.0

	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			if not trail_polys.is_empty() and _min_dist_to_trails_uv(u, v, trail_polys) < trail_clear:
				continue
			if is_fort and Vector2(u, v).distance_to(bastion_uv) < bastion_clear:
				continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 5.2 * scale_f):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 3.0 or h > 48.0:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.2)
			if n.y < 0.74:
				continue

			# 8-point octagonal dais perimeter check (4 corners +/-3.05 m + 4 cardinals 4.35 m): max_y - min_y <= 2.6!
			var min_perim_h := INF
			var max_perim_h := -INF
			var corner_blocked := false
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var cp := lp + right_d * (sx * 3.05 * scale_f) + fwd_d * (sz * 3.05 * scale_f)
					if _in_exclusion_padded(cp.x, cp.z, keepout_zones, 1.8 * scale_f):
						corner_blocked = true
						break
					var ch := island.surface_height(cp.x, cp.z)
					min_perim_h = minf(min_perim_h, ch)
					max_perim_h = maxf(max_perim_h, ch)
				if corner_blocked:
					break
			if corner_blocked:
				continue
			for sgn: float in [-1.0, 1.0]:
				var px := lp + right_d * (sgn * 4.35 * scale_f)
				var pz := lp + fwd_d * (sgn * 4.35 * scale_f)
				var hx := island.surface_height(px.x, px.z)
				var hz := island.surface_height(pz.x, pz.z)
				min_perim_h = minf(min_perim_h, minf(hx, hz))
				max_perim_h = maxf(max_perim_h, maxf(hx, hz))
			var min_y := minf(min_perim_h, h)
			var max_y := maxf(max_perim_h, h)
			if min_y < 2.0 or max_y - min_y > 2.6:
				continue

			# Seat octagonal ashlar plaza at min_perim_h + 0.08 so the -3.40 m skirt buries every perimeter rim!
			var base_y := min_perim_h + 0.08
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.14
			var score := n.y * 12.0 - (max_y - min_y) * 4.8 + clampf(h * 0.10, 0.0, 4.0) - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, base_y, lp.z)
				found = true

	if not found:
		return false

	var xform := Transform3D(
		plaza_basis * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_SUNDIAL_PLAZA, node_name, xform, 6.4 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_obsidian_vent(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# VolcanicObsidianFissureVent (~6.0 m tall cleaved black-basalt magma vent chimney with fractured
	# lava-crust base apron r ~ 3.25 m plunging cleanly to y_local = -3.80 m) erupts on volcanic slopes!
	var vent_basis := Basis(Vector3.UP, yaw)
	var right_d := vent_basis.x
	var fwd_d := vent_basis.z
	var trail_polys := IslandTrails.get_trail_polylines(island.archetype, island.island_radius, island.island_id)
	var trail_clear := IslandTrails.get_trail_half_width(island.archetype) + 4.4 * scale_f
	var scale_r := island.island_radius / 60.0
	var is_volcano := island.archetype == &"volcano_crag"

	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			if not trail_polys.is_empty() and _min_dist_to_trails_uv(u, v, trail_polys) < trail_clear:
				continue
			if is_volcano and Vector2(u, v - 4.0 * scale_r).length() < 19.0 * scale_r:
				continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 4.6 * scale_f):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 2.5 or h > 44.0:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.2)
			if n.y < 0.56:
				continue

			# 8-point basalt apron & iron chain-stake check (4 corners +/-2.35 m + 4 cardinals 3.25 m): max_y - min_y <= 3.3!
			var min_perim_h := INF
			var max_perim_h := -INF
			var corner_blocked := false
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var cp := lp + right_d * (sx * 2.35 * scale_f) + fwd_d * (sz * 2.35 * scale_f)
					if _in_exclusion_padded(cp.x, cp.z, keepout_zones, 1.8 * scale_f):
						corner_blocked = true
						break
					var ch := island.surface_height(cp.x, cp.z)
					min_perim_h = minf(min_perim_h, ch)
					max_perim_h = maxf(max_perim_h, ch)
				if corner_blocked:
					break
			if corner_blocked:
				continue
			for sgn: float in [-1.0, 1.0]:
				var px := lp + right_d * (sgn * 3.25 * scale_f)
				var pz := lp + fwd_d * (sgn * 3.25 * scale_f)
				var hx := island.surface_height(px.x, px.z)
				var hz := island.surface_height(pz.x, pz.z)
				min_perim_h = minf(min_perim_h, minf(hx, hz))
				max_perim_h = maxf(max_perim_h, maxf(hx, hz))
			var min_y := minf(min_perim_h, h)
			var max_y := maxf(max_perim_h, h)
			if min_y < 1.2 or max_y - min_y > 3.3:
				continue

			# Seat fractured basalt skirt at min_perim_h + 0.08 so both -3.80 m apron & -0.80 m chain-stakes embed cleanly!
			var base_y := min_perim_h + 0.08
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.14
			var score := n.y * 8.0 + clampf(h * 0.12, 0.0, 4.2) - (max_y - min_y) * 2.4 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, base_y, lp.z)
				found = true

	if not found:
		return false

	var xform := Transform3D(
		vent_basis * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_OBSIDIAN_VENT, node_name, xform, 5.4 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_stone_well(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# StoneWellCourtyard (~4.4 m diameter circular cobbled courtyard apron, r = 2.38 m skirt
	# plunging cleanly to y_local = -2.70 m) anchors village lanes, harbour greens & fort terraces!
	var well_basis := Basis(Vector3.UP, yaw)
	var right_d := well_basis.x
	var fwd_d := well_basis.z
	var trail_polys := IslandTrails.get_trail_polylines(island.archetype, island.island_radius, island.island_id)
	var trail_clear := IslandTrails.get_trail_half_width(island.archetype) + 4.0 * scale_f
	var scale_r := island.island_radius / 60.0
	var is_fort := island.archetype == &"fort_rock" or island.archetype == &"grand_citadel"
	var bastion_uv := Vector2(0.0, 18.0 if island.archetype == &"grand_citadel" else 2.0 * scale_r)
	var bastion_clear := 28.0 if island.archetype == &"grand_citadel" else 23.0
	var is_volcano := island.archetype == &"volcano_crag"
	var is_port_scoundrel := island.island_id == "port_scoundrel"

	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			if not trail_polys.is_empty() and _min_dist_to_trails_uv(u, v, trail_polys) < trail_clear:
				continue
			if is_fort and Vector2(u, v).distance_to(bastion_uv) < bastion_clear:
				continue
			if is_volcano and Vector2(u, v - 4.0 * scale_r).length() < 19.0 * scale_r:
				continue
			if island.is_outpost:
				# Stay strictly clear of dock pier, harbour channel, central plaza, Tavern, Beacon, Merchant & Warehouse!
				if absf(u) < 16.5 and v < -10.0:
					continue
				if is_port_scoundrel and v < 4.0 and u < 24.0:
					# Preserve Port Scoundrel's Title Screen foreground harbour & plaza sightline 100% unobstructed!
					continue
				if Vector2(u + 11.0, v + 7.5).length() < 12.5:
					continue
				if Vector2(u - 24.0, v + 6.5).length() < 12.0:
					continue
				if Vector2(u - 9.2, v + 18.5).length() < 9.5:
					continue
				if Vector2(u + 23.5, v + 16.5).length() < 10.5:
					continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 3.8 * scale_f):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 1.6 or h > 26.0:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.0)
			if n.y < 0.78:
				continue

			# 8-point circular cobbled apron check (4 corners +/-1.75 m + 4 cardinals 2.45 m): max_y - min_y <= 2.1!
			var min_perim_h := INF
			var max_perim_h := -INF
			var corner_blocked := false
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var cp := lp + right_d * (sx * 1.75 * scale_f) + fwd_d * (sz * 1.75 * scale_f)
					if _in_exclusion_padded(cp.x, cp.z, keepout_zones, 1.4 * scale_f):
						corner_blocked = true
						break
					var ch := island.surface_height(cp.x, cp.z)
					min_perim_h = minf(min_perim_h, ch)
					max_perim_h = maxf(max_perim_h, ch)
				if corner_blocked:
					break
			if corner_blocked:
				continue
			for sgn: float in [-1.0, 1.0]:
				var px := lp + right_d * (sgn * 2.45 * scale_f)
				var pz := lp + fwd_d * (sgn * 2.45 * scale_f)
				var hx := island.surface_height(px.x, px.z)
				var hz := island.surface_height(pz.x, pz.z)
				min_perim_h = minf(min_perim_h, minf(hx, hz))
				max_perim_h = maxf(max_perim_h, maxf(hx, hz))
			var min_y := minf(min_perim_h, h)
			var max_y := maxf(max_perim_h, h)
			if min_y < 1.2 or max_y - min_y > 2.1 or h - min_perim_h > 1.2:
				continue

			# Seat cobbled apron at min_perim_h + 0.06 so the -2.70 m skirt buries every perimeter curb stone!
			var base_y := min_perim_h + 0.06
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.16
			var score := n.y * 12.0 - (max_y - min_y) * 5.0 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, base_y, lp.z)
				found = true

	if not found:
		return false

	var xform := Transform3D(
		well_basis * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_STONE_WELL, node_name, xform, 4.6 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_cannon_bastion(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, scan_span: float, prefer_dir: Vector3, scale_f: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# RuinedSeaFortCannonBastion (~7.36 m wide x ~4.68 m deep battered ashlar parapet battery,
	# skirt x in [-3.68, +3.68], z in [-2.42, +2.26] plunging to y_local = -3.60 m, aiming naval
	# cannon seaward along -Z) commands coastal bluffs, harbour mouths & fortress headlands!
	var trail_polys := IslandTrails.get_trail_polylines(island.archetype, island.island_radius, island.island_id)
	var trail_clear := IslandTrails.get_trail_half_width(island.archetype) + 4.8 * scale_f
	var scale_r := island.island_radius / 60.0
	var is_fort := island.archetype == &"fort_rock" or island.archetype == &"grand_citadel"
	var bastion_uv := Vector2(0.0, 18.0 if island.archetype == &"grand_citadel" else 2.0 * scale_r)
	var bastion_clear := 28.0 if island.archetype == &"grand_citadel" else 23.0
	var is_volcano := island.archetype == &"volcano_crag"
	var has_mooring := island.mooring_transform != Transform3D.IDENTITY
	var moor_xz := Vector2(island.mooring_transform.origin.x, island.mooring_transform.origin.z)
	var pref_xz := Vector3(prefer_dir.x, 0.0, prefer_dir.z)
	pref_xz = pref_xz.normalized() if pref_xz.length_squared() > 0.0001 else Vector3(0.0, 0.0, -1.0)

	var best_pos := Vector3.ZERO
	var best_aim := pref_xz
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			if not trail_polys.is_empty() and _min_dist_to_trails_uv(u, v, trail_polys) < trail_clear:
				continue
			if is_fort and Vector2(u, v).distance_to(bastion_uv) < bastion_clear:
				continue
			if is_volcano and Vector2(u, v - 4.0 * scale_r).length() < 19.0 * scale_r:
				continue
			if island.is_outpost:
				# Keep strictly clear of dock piers, central harbour channel & village buildings!
				if absf(u) < 22.0 and v < 2.0:
					continue
				if Vector2(u + 11.0, v + 7.5).length() < 13.5:
					continue
				if Vector2(u - 24.0, v + 6.5).length() < 13.5:
					continue
				if Vector2(u + 23.5, v + 16.5).length() < 11.5:
					continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 4.8 * scale_f):
				continue
			if has_mooring and Vector2(lp.x, lp.z).distance_squared_to(moor_xz) < 18.0 * 18.0:
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 3.5 or h > 36.0:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.2)
			if n.y < 0.62:
				continue

			# Aim local -Z smoothly seaward toward preferred ocean/harbour vector blended with bluff slope!
			var out_xz := _horizontal_outward(n, lp, pref_xz)
			var aim_raw := pref_xz * 0.72 + out_xz * 0.28
			aim_raw.y = 0.0
			var aim_xz := aim_raw.normalized() if aim_raw.length_squared() > 0.001 else pref_xz
			if aim_xz.dot(pref_xz) < 0.35:
				aim_xz = pref_xz
			var right_d := Vector3(-aim_xz.z, 0.0, aim_xz.x)
			# Ensure seaward firing arc ahead of the gun embrasure does not slam straight into a rising cliff wall!
			var arc_p := lp + aim_xz * (5.2 * scale_f)
			if island.surface_height(arc_p.x, arc_p.z) > h + 1.4 * scale_f:
				continue

			# 8-point battered ashlar foundation check (4 corners +/-3.65 m x +/-2.40 m + 4 cardinals): max_y - min_y <= 3.1!
			var min_perim_h := INF
			var max_perim_h := -INF
			var corner_blocked := false
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var cp := lp + right_d * (sx * 3.65 * scale_f) + aim_xz * (sz * 2.40 * scale_f)
					if _in_exclusion_padded(cp.x, cp.z, keepout_zones, 1.6 * scale_f):
						corner_blocked = true
						break
					var ch := island.surface_height(cp.x, cp.z)
					min_perim_h = minf(min_perim_h, ch)
					max_perim_h = maxf(max_perim_h, ch)
				if corner_blocked:
					break
			if corner_blocked:
				continue
			for sgn: float in [-1.0, 1.0]:
				var px := lp + right_d * (sgn * 3.75 * scale_f)
				var pz := lp + aim_xz * (sgn * 2.50 * scale_f)
				var hx := island.surface_height(px.x, px.z)
				var hz := island.surface_height(pz.x, pz.z)
				min_perim_h = minf(min_perim_h, minf(hx, hz))
				max_perim_h = maxf(max_perim_h, maxf(hx, hz))
			var min_y := minf(min_perim_h, h)
			var max_y := maxf(max_perim_h, h)
			if min_y < 2.2 or max_y - min_y > 3.1 or h - min_perim_h > 1.85:
				continue

			# Seat battered ashlar battery at min_perim_h + 0.08 so the -3.60 m foundation embeds deeply!
			var base_y := min_perim_h + 0.08
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.14
			var score := n.y * 8.5 + clampf(h * 0.14, 0.0, 4.5) - (max_y - min_y) * 2.6 \
				+ aim_xz.dot(pref_xz) * 3.5 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, base_y, lp.z)
				best_aim = aim_xz
				found = true

	if not found:
		return false

	var yaw := atan2(-best_aim.x, -best_aim.z)
	var xform := Transform3D(
		Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_CANNON_BASTION, node_name, xform, 5.8 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_treasure_vault(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, u_span: float, v_span: float,
		prefer_dir: Vector3, scale_f: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# PirateTreasureVaultDoor (~6.3 m wide x ~5.7 m deep carved stone treasure vault doorway,
	# x in [-3.16, +3.16], z in [-2.28, +3.40], -3.40 m threshold skirt & +Z tapered rock heel)
	# embeds dramatically into rising cliff toes facing downslope (-Z) toward trails & coves!
	var trail_polys := IslandTrails.get_trail_polylines(island.archetype, island.island_radius, island.island_id)
	var trail_clear := IslandTrails.get_trail_half_width(island.archetype) + 4.0 * scale_f
	var scale_r := island.island_radius / 60.0
	var is_fort := island.archetype == &"fort_rock" or island.archetype == &"grand_citadel"
	var bastion_uv := Vector2(0.0, 18.0 if island.archetype == &"grand_citadel" else 2.0 * scale_r)
	var bastion_clear := 28.0 if island.archetype == &"grand_citadel" else 23.0
	var is_volcano := island.archetype == &"volcano_crag"
	var is_smuggler := island.archetype == &"smuggler_cove"
	var grotto_uv := Vector2(0.0, 6.0 * scale_r)
	var is_twin_spires := island.archetype == &"twin_spires"
	var pref_xz := Vector3(prefer_dir.x, 0.0, prefer_dir.z)
	pref_xz = pref_xz.normalized() if pref_xz.length_squared() > 0.0001 else Vector3(0.0, 0.0, -1.0)

	var best_pos := Vector3.ZERO
	var best_out := pref_xz
	var best_score := -INF
	var found := false

	for iu in range(-5, 6):
		var u := u0 + float(iu) * (u_span * 0.1)
		for iv in range(-5, 6):
			var v := v0 + float(iv) * (v_span * 0.1)
			if not trail_polys.is_empty() and _min_dist_to_trails_uv(u, v, trail_polys) < trail_clear:
				continue
			if is_fort and Vector2(u, v).distance_to(bastion_uv) < bastion_clear:
				continue
			if is_volcano and Vector2(u, v - 4.0 * scale_r).length() < 19.0 * scale_r:
				continue
			if is_smuggler and Vector2(u, v).distance_to(grotto_uv) < 18.0:
				continue
			if is_twin_spires and v > -11.0 * scale_r:
				# Strictly preserve Emerald Spire's shot=emerald_waterfall camera lens & TempleStairway_Canyon!
				continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 4.4 * scale_f):
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 3.0 or h > 32.0:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.4)
			if n.y < 0.46 or n.y > 0.88:
				continue
			var out_xz := _horizontal_outward(n, lp, pref_xz)
			var dir_dot := out_xz.dot(pref_xz)
			if dir_dot < 0.05:
				continue
			var side_xz := Vector3(-out_xz.z, 0.0, out_xz.x)

			# Multi-point footing check across front threshold steps (-Z = +out_xz), mid flanks & rear rock heel (+Z = -out_xz)!
			var front_c := lp + out_xz * (2.30 * scale_f)
			var front_l := front_c - side_xz * (3.15 * scale_f)
			var front_r := front_c + side_xz * (3.15 * scale_f)
			if _in_exclusion_padded(front_c.x, front_c.z, keepout_zones, 2.2 * scale_f):
				continue
			var h_fc := island.surface_height(front_c.x, front_c.z)
			var h_fl := island.surface_height(front_l.x, front_l.z)
			var h_fr := island.surface_height(front_r.x, front_r.z)
			var min_front_h := minf(h_fc, minf(h_fl, h_fr))
			var max_front_h := maxf(h_fc, maxf(h_fl, h_fr))
			if min_front_h < 1.2 or max_front_h - min_front_h > 2.4 * scale_f:
				continue

			var mid_l := lp - side_xz * (3.15 * scale_f)
			var mid_r := lp + side_xz * (3.15 * scale_f)
			var h_ml := island.surface_height(mid_l.x, mid_l.z)
			var h_mr := island.surface_height(mid_r.x, mid_r.z)
			var min_foot_h := minf(min_front_h, minf(h, minf(h_ml, h_mr)))

			var rear_c := lp - out_xz * (3.25 * scale_f)
			var rear_l := rear_c - side_xz * (2.95 * scale_f)
			var rear_r := rear_c + side_xz * (2.95 * scale_f)
			var h_rc := island.surface_height(rear_c.x, rear_c.z)
			var h_rl := island.surface_height(rear_l.x, rear_l.z)
			var h_rr := island.surface_height(rear_r.x, rear_r.z)
			var min_rear_h := minf(h_rc, minf(h_rl, h_rr))
			# Rear +Z tapered rock heel MUST press cleanly into a rising cliff wall behind the vault!
			if h_rc < max_front_h + 1.6 * scale_f or min_rear_h < min_front_h + 1.2 * scale_f:
				continue

			# Seat threshold slightly below min_foot_h so the front steps & -3.40 m skirt bury with zero gap!
			var base_y := min_foot_h - 0.12
			if h - base_y > 3.0 * scale_f:
				continue
			var rear_rise := h_rc - min_front_h
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.14
			var score := dir_dot * 9.0 + clampf(rear_rise, 0.0, 9.0) * 1.15 \
				- (max_front_h - min_front_h) * 2.4 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, base_y, lp.z)
				best_out = out_xz
				found = true

	if not found:
		return false

	var yaw := atan2(-best_out.x, -best_out.z)
	var xform := Transform3D(
		Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_TREASURE_VAULT, node_name, xform, 5.4 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


static func _place_crow_nest_mast(island: Island, basis: Basis, node_name: String,
		u0: float, v0: float, yaw: float, scale_f: float, scan_span: float,
		placed: Array[Vector3], keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> bool:
	# WoodenShipwreckCrowNestMast (~8.5 m canted driftwood ship mast & wooden crow's-nest basket
	# rooted in a barnacle-and-moss coastal reef rock outcrop r = 2.95 m plunging to y_local = -3.60 m)
	# marks rocky headlands, reef points & shipwreck shoals cleanly clear of moorings & trails!
	var mast_basis := Basis(Vector3.UP, yaw)
	var right_d := mast_basis.x
	var fwd_d := mast_basis.z
	var trail_polys := IslandTrails.get_trail_polylines(island.archetype, island.island_radius, island.island_id)
	var trail_clear := IslandTrails.get_trail_half_width(island.archetype) + 4.0 * scale_f
	var has_mooring := island.mooring_transform != Transform3D.IDENTITY
	var moor_xz := Vector2(island.mooring_transform.origin.x, island.mooring_transform.origin.z)

	var best_pos := Vector3.ZERO
	var best_score := -INF
	var found := false

	for iu in range(-4, 5):
		var u := u0 + float(iu) * (scan_span * 0.125)
		for iv in range(-4, 5):
			var v := v0 + float(iv) * (scan_span * 0.125)
			if not trail_polys.is_empty() and _min_dist_to_trails_uv(u, v, trail_polys) < trail_clear:
				continue
			var lp := basis * Vector3(u, 0.0, v)
			if _in_exclusion_padded(lp.x, lp.z, keepout_zones, 4.4 * scale_f):
				continue
			if has_mooring and Vector2(lp.x, lp.z).distance_squared_to(moor_xz) < 16.0 * 16.0:
				continue
			var h := island.surface_height(lp.x, lp.z)
			if h < 0.8 or h > 16.0:
				continue
			var n := island.surface_normal(lp.x, lp.z, 2.0)
			if n.y < 0.64:
				continue

			# 8-point barnacle reef rock outcrop check (4 corners +/-2.15 m + 4 cardinals 3.00 m): max_y - min_y <= 3.1!
			var min_perim_h := INF
			var max_perim_h := -INF
			var corner_blocked := false
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var cp := lp + right_d * (sx * 2.15 * scale_f) + fwd_d * (sz * 2.15 * scale_f)
					if _in_exclusion_padded(cp.x, cp.z, keepout_zones, 1.5 * scale_f):
						corner_blocked = true
						break
					var ch := island.surface_height(cp.x, cp.z)
					min_perim_h = minf(min_perim_h, ch)
					max_perim_h = maxf(max_perim_h, ch)
				if corner_blocked:
					break
			if corner_blocked:
				continue
			for sgn: float in [-1.0, 1.0]:
				var px := lp + right_d * (sgn * 3.00 * scale_f)
				var pz := lp + fwd_d * (sgn * 3.00 * scale_f)
				var hx := island.surface_height(px.x, px.z)
				var hz := island.surface_height(pz.x, pz.z)
				min_perim_h = minf(min_perim_h, minf(hx, hz))
				max_perim_h = maxf(max_perim_h, maxf(hx, hz))
			var min_y := minf(min_perim_h, h)
			var max_y := maxf(max_perim_h, h)
			if min_y < 0.05 or max_y - min_y > 3.1 or h - min_perim_h > 1.85:
				continue

			# Seat barnacle reef outcrop at min_perim_h + 0.08 so the -3.60 m rock root buries cleanly!
			var base_y := min_perim_h + 0.08
			var dist_pen := Vector2(u - u0, v - v0).length() * 0.16
			var score := n.y * 8.0 + clampf(h * 0.20, 0.0, 3.2) - (max_y - min_y) * 2.4 - dist_pen
			if score > best_score:
				best_score = score
				best_pos = Vector3(lp.x, base_y, lp.z)
				found = true

	if not found:
		return false

	var xform := Transform3D(
		mast_basis * Basis.from_scale(Vector3(scale_f, scale_f, scale_f)),
		best_pos)
	return _spawn_landmark(island, GLB_CROW_NEST_MAST, node_name, xform, 5.0 * scale_f,
		placed, keepout_zones, rng, prop_body, props_root, foliage_cache, landmark_cache) != null


# ============================================================ core landmark spawner

static func _load_landmark(filename: String, landmark_cache: Dictionary) -> PackedScene:
	if landmark_cache.has(filename):
		return landmark_cache[filename] as PackedScene
	var path := LANDMARK_DIR + filename
	if not ResourceLoader.exists(path):
		landmark_cache[filename] = null
		return null
	var scene := load(path) as PackedScene
	landmark_cache[filename] = scene
	return scene


static func _spawn_landmark(island: Island, filename: String, node_name: String,
		local_xform: Transform3D, keepout_r: float, placed: Array[Vector3],
		keepout_zones: Array[Vector3], rng: RandomNumberGenerator,
		prop_body: StaticBody3D, props_root: Node3D, foliage_cache: Dictionary,
		landmark_cache: Dictionary) -> Node3D:
	var scene := _load_landmark(filename, landmark_cache)
	if scene == null:
		return null
	var inst := scene.instantiate() as Node3D
	if inst == null:
		return null
	inst.name = node_name
	inst.transform = local_xform
	props_root.add_child(inst)

	# 1. Extract every `col_*` MeshInstance3D into ConvexPolygonShape3D on prop_body (layer 1)
	#    and hide collider visuals so stairs, catwalks, overhang tops & sea arches are 100% walkable!
	for col_node in inst.find_children("col_*", "MeshInstance3D", true, false):
		var cmi := col_node as MeshInstance3D
		if cmi == null:
			continue
		cmi.visible = false
		cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if prop_body == null or cmi.mesh == null:
			continue
		var faces := cmi.mesh.get_faces()
		if faces.size() < 3:
			continue
		var shape := ConvexPolygonShape3D.new()
		shape.points = faces
		var cs := CollisionShape3D.new()
		cs.name = "Col_%s_%s" % [node_name, cmi.name]
		cs.shape = shape
		cs.transform = local_xform * _relative_transform(cmi, inst)
		prop_body.add_child(cs)

	# 2. Set visibility range on every visible mesh & bind `foliage_wind.gdshader` (+ PBR maps!) to `mat_foliage`!
	var vis_range := VIS_RANGE_MID if MID_RANGE_FILES.has(filename) else VIS_RANGE_HORIZON
	for mesh_node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_node as MeshInstance3D
		if mi == null or not mi.visible or mi.mesh == null:
			continue
		mi.visibility_range_end = vis_range
		var mesh := mi.mesh
		for surf_i in mesh.get_surface_count():
			var src_mat := mesh.surface_get_material(surf_i)
			if src_mat == null:
				src_mat = mi.get_active_material(surf_i)
			if src_mat == null or not src_mat.resource_name.begins_with("mat_foliage"):
				continue
			var tex: Texture2D = null
			var nrm_tex: Texture2D = null
			var rgh_tex: Texture2D = null
			if src_mat is StandardMaterial3D:
				var sm := src_mat as StandardMaterial3D
				tex = sm.albedo_texture
				nrm_tex = sm.normal_texture
				rgh_tex = sm.roughness_texture
			var cache_key := "default_foliage"
			if tex != null:
				cache_key = tex.resource_path if not tex.resource_path.is_empty() else "foliage_tex_%d" % tex.get_instance_id()
			cache_key += "|" + (nrm_tex.resource_path if nrm_tex != null else "")
			var wind_mat: ShaderMaterial = foliage_cache.get(cache_key) as ShaderMaterial
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

	# 3. Auto-mount flickering shadowless OmniLight3Ds on `Lantern_*` empties!
	_mount_lantern_lights(island, inst, rng)

	# 3b. Keep landmark child names strictly disjoint from `IslandWaterfall` (`*Waterfall*`) lookups!
	if filename == GLB_WATERFALL_SHRINE:
		for child_n in inst.find_children("*Waterfall*", "", true, false):
			child_n.name = String(child_n.name).replace("Waterfall", "Cascade")

	# 4. Register keepout footprint in BOTH `placed` and `keepout_zones`.
	if keepout_r > 0.0:
		var pos := local_xform.origin
		var rec := Vector3(pos.x, pos.z, keepout_r)
		placed.append(rec)
		keepout_zones.append(rec)

	return inst


static func _mount_lantern_lights(island: Island, inst: Node3D, rng: RandomNumberGenerator) -> void:
	for node in inst.find_children("Lantern_*", "Node3D", true, false):
		var marker := node as Node3D
		if marker == null:
			continue
		var m_name := marker.name
		var light := OmniLight3D.new()
		light.name = "Glow_" + m_name
		light.shadow_enabled = false

		var base_energy := 3.4
		var amp := 0.14
		if m_name.begins_with("Lantern_SkullEye"):
			light.light_color = COL_SKULL_EYE
			base_energy = 7.2
			light.omni_range = 24.0
			light.omni_attenuation = 1.25
			amp = 0.22
		elif m_name.begins_with("Lantern_IdolEye"):
			light.light_color = COL_SKULL_EYE
			base_energy = 5.4
			light.omni_range = 18.0
			light.omni_attenuation = 1.30
			amp = 0.20
		elif m_name.begins_with("Lantern_MagmaVent"):
			light.light_color = COL_MAGMA_VENT
			base_energy = 2.05
			light.omni_range = 16.0
			light.omni_attenuation = 1.25
			amp = 0.24
		elif m_name.begins_with("Lantern_Magma"):
			light.light_color = COL_MAGMA_ARCH
			base_energy = 6.2
			light.omni_range = 21.0
			light.omni_attenuation = 1.25
			amp = 0.22
		elif m_name.begins_with("Lantern_CalderaShrine"):
			light.light_color = COL_CALDERA_SHRINE
			base_energy = 5.4
			light.omni_range = 22.0
			light.omni_attenuation = 1.25
			amp = 0.24
		elif m_name.begins_with("Lantern_Brazier"):
			light.light_color = COL_BRAZIER_FIRE
			base_energy = 5.2
			light.omni_range = 20.0
			light.omni_attenuation = 1.25
			amp = 0.20
		elif m_name.begins_with("Lantern_Watchpost"):
			light.light_color = COL_WATCHPOST_BEACON
			base_energy = 4.2
			light.omni_range = 24.0
			light.omni_attenuation = 1.25
			amp = 0.18
		elif m_name.begins_with("Lantern_Camp"):
			light.light_color = COL_CAMP_FIRE
			base_energy = 3.8
			light.omni_range = 18.0
			light.omni_attenuation = 1.25
			amp = 0.22
		elif m_name.begins_with("Lantern_Stern"):
			light.light_color = COL_STERN_BRASS
			base_energy = 3.6
			light.omni_range = 17.0
			light.omni_attenuation = 1.30
			amp = 0.16
		elif m_name.begins_with("Lantern_Crane"):
			light.light_color = COL_CRANE_LANTERN
			base_energy = 1.65
			light.omni_range = 13.5
			light.omni_attenuation = 1.30
			amp = 0.14
		elif m_name.begins_with("Lantern_Altar"):
			light.light_color = COL_ALTAR_FIRE
			base_energy = 1.80
			light.omni_range = 14.0
			light.omni_attenuation = 1.25
			amp = 0.20
		elif m_name.begins_with("Lantern_WaterfallShrine"):
			light.light_color = COL_WATERFALL_SHRINE
			base_energy = 1.55
			light.omni_range = 12.5
			light.omni_attenuation = 1.30
			amp = 0.16
		elif m_name.begins_with("Lantern_Hoard"):
			light.light_color = COL_HOARD_LANTERN
			base_energy = 1.35
			light.omni_range = 10.5
			light.omni_attenuation = 1.35
			amp = 0.15
		elif m_name.begins_with("Lantern_Watchtower"):
			light.light_color = COL_WATCHTOWER_BEACON
			base_energy = 1.90
			light.omni_range = 16.0
			light.omni_attenuation = 1.25
			amp = 0.18
		elif m_name.begins_with("Lantern_ReefBeacon"):
			light.light_color = COL_REEF_BEACON
			base_energy = 1.85
			light.omni_range = 17.0
			light.omni_attenuation = 1.25
			amp = 0.20
		elif m_name.begins_with("Lantern_Monolith"):
			light.light_color = COL_MONOLITH_GLOW
			base_energy = 1.80
			light.omni_range = 14.5
			light.omni_attenuation = 1.25
			amp = 0.16
		elif m_name.begins_with("Lantern_ChainPylon"):
			light.light_color = COL_CHAIN_PYLON
			base_energy = 2.00
			light.omni_range = 16.5
			light.omni_attenuation = 1.25
			amp = 0.22
		elif m_name.begins_with("Lantern_Drydock"):
			light.light_color = COL_DRYDOCK_LANTERN
			base_energy = 1.65
			light.omni_range = 13.0
			light.omni_attenuation = 1.30
			amp = 0.16
		elif m_name.begins_with("Lantern_Throne"):
			light.light_color = COL_THRONE_GLOW
			base_energy = 1.95
			light.omni_range = 15.0
			light.omni_attenuation = 1.25
			amp = 0.22
		elif m_name.begins_with("Lantern_FishHut"):
			light.light_color = COL_FISH_HUT_LANTERN
			base_energy = 1.50
			light.omni_range = 12.0
			light.omni_attenuation = 1.30
			amp = 0.15
		elif m_name.begins_with("Lantern_Orrery"):
			light.light_color = COL_ORRERY_STAR
			base_energy = 1.85
			light.omni_range = 14.5
			light.omni_attenuation = 1.25
			amp = 0.16
		elif m_name.begins_with("Lantern_Footbridge"):
			light.light_color = COL_FOOTBRIDGE_LANTERN
			base_energy = 1.50
			light.omni_range = 12.0
			light.omni_attenuation = 1.30
			amp = 0.15
		elif m_name.begins_with("Lantern_Jetty"):
			light.light_color = COL_JETTY_LANTERN
			base_energy = 1.75
			light.omni_range = 14.5
			light.omni_attenuation = 1.30
			amp = 0.16
		elif m_name.begins_with("Lantern_ObeliskGate"):
			light.light_color = COL_OBELISK_GATE_GLOW
			base_energy = 1.80
			light.omni_range = 14.5
			light.omni_attenuation = 1.25
			amp = 0.18
		elif m_name.begins_with("Lantern_BellFrame"):
			light.light_color = COL_BELL_FRAME_LANTERN
			base_energy = 1.70
			light.omni_range = 15.0
			light.omni_attenuation = 1.25
			amp = 0.17
		elif m_name.begins_with("Lantern_Cart"):
			light.light_color = COL_CART_LANTERN
			base_energy = 1.55
			light.omni_range = 12.0
			light.omni_attenuation = 1.30
			amp = 0.15
		elif m_name.begins_with("Lantern_Anchor"):
			light.light_color = COL_ANCHOR_LANTERN
			base_energy = 1.65
			light.omni_range = 13.5
			light.omni_attenuation = 1.30
			amp = 0.16
		elif m_name.begins_with("Lantern_Sundial"):
			light.light_color = COL_SUNDIAL_FIRE
			base_energy = 1.85
			light.omni_range = 14.5
			light.omni_attenuation = 1.25
			amp = 0.18
		elif m_name.begins_with("Lantern_Well"):
			light.light_color = COL_WELL_LANTERN
			base_energy = 1.55
			light.omni_range = 12.5
			light.omni_attenuation = 1.30
			amp = 0.15
		elif m_name.begins_with("Lantern_Bastion"):
			light.light_color = COL_BASTION_TORCH
			base_energy = 1.90
			light.omni_range = 15.0
			light.omni_attenuation = 1.25
			amp = 0.20
		elif m_name.begins_with("Lantern_Vault"):
			light.light_color = COL_VAULT_GLOW
			base_energy = 1.85
			light.omni_range = 14.5
			light.omni_attenuation = 1.25
			amp = 0.18
		elif m_name.begins_with("Lantern_CrowNest"):
			light.light_color = COL_CROWNEST_LANTERN
			base_energy = 1.75
			light.omni_range = 14.5
			light.omni_attenuation = 1.28
			amp = 0.17
		elif m_name.begins_with("Lantern_Trail") or m_name.begins_with("Lantern_Rowboat"):
			light.light_color = COL_TRAIL_AMBER
			base_energy = 2.6
			light.omni_range = 11.5
			light.omni_attenuation = 1.35
			amp = 0.14
		else:
			# Lantern_Catwalk, Lantern_WreckBow, Lantern_Gallows & warm harbour lantern empties.
			light.light_color = COL_HARBOUR_AMBER
			base_energy = 3.4
			light.omni_range = 15.0
			light.omni_attenuation = 1.35
			amp = 0.14

		light.light_energy = base_energy
		marker.add_child(light)
		island.register_flicker_light(light, base_energy, amp, rng.randf() * TAU)


# ============================================================ math & exclusion helpers

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


static func _in_exclusion_padded(x: float, z: float, exclusions: Array[Vector3], pad_r: float) -> bool:
	for ex in exclusions:
		var dx := x - ex.x
		var dz := z - ex.y
		var rad := ex.z + pad_r
		if dx * dx + dz * dz < rad * rad:
			return true
	return false


static func _horizontal_outward(n: Vector3, local_pos: Vector3, fallback: Vector3) -> Vector3:
	var out_xz := Vector3(n.x, 0.0, n.z)
	if out_xz.length_squared() >= 0.0025:
		return out_xz.normalized()
	var radial := Vector3(local_pos.x, 0.0, local_pos.z)
	if radial.length_squared() >= 0.01:
		return radial.normalized()
	var fb := Vector3(fallback.x, 0.0, fallback.z)
	return fb.normalized() if fb.length_squared() >= 0.0001 else Vector3(0.0, 0.0, -1.0)


static func _min_footprint_height(island: Island, x: float, z: float, rad: float) -> float:
	var h_min := island.surface_height(x, z)
	h_min = minf(h_min, island.surface_height(x + rad, z))
	h_min = minf(h_min, island.surface_height(x - rad, z))
	h_min = minf(h_min, island.surface_height(x, z + rad))
	h_min = minf(h_min, island.surface_height(x, z - rad))
	return h_min


static func _min_footprint_height_8(island: Island, x: float, z: float, rad: float) -> float:
	var h_min := _min_footprint_height(island, x, z, rad)
	var diag := rad * 0.70710678
	h_min = minf(h_min, island.surface_height(x + diag, z + diag))
	h_min = minf(h_min, island.surface_height(x - diag, z + diag))
	h_min = minf(h_min, island.surface_height(x + diag, z - diag))
	h_min = minf(h_min, island.surface_height(x - diag, z - diag))
	return h_min


static func _min_dist_to_trails_uv(u: float, v: float, polylines: Array[PackedVector2Array]) -> float:
	var min_sq := 1e12
	for poly in polylines:
		var n := poly.size()
		for i in range(n - 1):
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
