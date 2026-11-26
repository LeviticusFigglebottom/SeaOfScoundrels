class_name IslandLandmarks
extends RefCounted
## Bespoke 3D signature landmark choreographer across all 14 archipelago islands.
##
## Places our 12 Wave I-1 stylized PBR `.glb` landmarks (`res://assets/generated/landmarks/`)
## with slope-aware anti-floating grounding, inward cliff-normal heel embedding,
## walkable `col_*` convex collider extraction, `foliage_wind.gdshader` vine sway
## binding, horizon/mid visibility ranges, auto-mounted flickering `Lantern_*` lights,
## keepout-zone registration, and walkable trail storytelling markers.
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

const VIS_RANGE_HORIZON := 2200.0
const VIS_RANGE_MID := 460.0
const MAX_TRAIL_MARKERS := 8

const MID_RANGE_FILES: Array[String] = [
	GLB_BOULDER_CLUSTER,
	GLB_TRAIL_LANTERN,
	GLB_STONE_CAIRN,
	GLB_ROWBOAT_WRECK,
]

# Auto-mounted OmniLight3D presets for `Lantern_*` GLB empties.
const COL_SKULL_EYE := Color(0.16, 0.98, 0.78)
const COL_MAGMA_ARCH := Color(1.0, 0.42, 0.10)
const COL_BRAZIER_FIRE := Color(1.0, 0.58, 0.18)
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

	# 2 flanking cantilevered cliff overhangs on western & eastern bluff slopes.
	var overhang_specs: Array[Array] = [
		["CliffOverhangLedge_West", -28.0 * scale_r, -4.0 * scale_r, Vector3(-0.78, 0.0, -0.62), 1.06],
		["CliffOverhangLedge_East", 28.0 * scale_r, -4.0 * scale_r, Vector3(0.78, 0.0, -0.62), 1.04],
	]
	for spec: Array in overhang_specs:
		var pref_dir := (basis * (spec[3] as Vector3)).normalized()
		if _place_cliff_overhang(island, basis, String(spec[0]), float(spec[1]), float(spec[2]),
				16.0, 14.0, 10.0, 42.0, pref_dir, float(spec[4]), 5.5,
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

	# 3 CliffOverhangLedges + 2 CliffButtressWides fortifying outer citadel headlands & promontories.
	var overhang_specs: Array[Array] = [
		["CliffOverhangLedge_West", -86.0, -36.0, Vector3(-0.75, 0.0, -0.66), 1.12],
		["CliffOverhangLedge_East", 86.0, -36.0, Vector3(0.75, 0.0, -0.66), 1.12],
		["CliffOverhangLedge_Prom", -74.0, -76.0, Vector3(-0.45, 0.0, -0.89), 1.08],
	]
	for spec: Array in overhang_specs:
		var pref_dir := (basis * (spec[3] as Vector3)).normalized()
		if _place_cliff_overhang(island, basis, String(spec[0]), float(spec[1]), float(spec[2]),
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

	# 2 CliffOverhangLedges on the outer fjord headland cliffs.
	var overhang_specs: Array[Array] = [
		["CliffOverhangLedge_West", -72.0, -76.0, Vector3(0.55, 0.0, -0.84), 1.08],
		["CliffOverhangLedge_East", 70.0, -70.0, Vector3(-0.55, 0.0, -0.84), 1.08],
	]
	for spec: Array in overhang_specs:
		var pref_dir := (basis * (spec[3] as Vector3)).normalized()
		if _place_cliff_overhang(island, basis, String(spec[0]), float(spec[1]), float(spec[2]),
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
	return count


static func _populate_outpost(island: Island, basis: Basis, landing_yaw: float,
		scale_r: float, placed: Array[Vector3], keepout_zones: Array[Vector3],
		rng: RandomNumberGenerator, prop_body: StaticBody3D, props_root: Node3D,
		foliage_cache: Dictionary, landmark_cache: Dictionary) -> int:
	var count := 0
	var is_port_scoundrel := island.island_id == "port_scoundrel"

	if is_port_scoundrel:
		# Port Scoundrel: dramatic overhang anchored onto the western cliff arm behind the tavern!
		var pref_dir := (basis * Vector3(0.75, 0.0, -0.66)).normalized()
		if _place_cliff_overhang(island, basis, "CliffOverhangLedge_TavernBluff",
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

	# 2 CliffOverhangLedges framing the amphitheatre headland wings.
	var overhang_specs: Array[Array] = [
		["CliffOverhangLedge_West", -28.0 * scale_r, -14.0 * scale_r, Vector3(0.68, 0.0, -0.73), 1.02],
		["CliffOverhangLedge_East", 32.0 * scale_r, -20.0 * scale_r, Vector3(-0.55, 0.0, -0.84), 1.00],
	]
	for spec: Array in overhang_specs:
		var pref_dir := (basis * (spec[3] as Vector3)).normalized()
		if _place_cliff_overhang(island, basis, String(spec[0]), float(spec[1]), float(spec[2]),
				16.0, 14.0, 8.0, 36.0, pref_dir, float(spec[4]), 5.5,
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
	return count


static func _populate_treasure_peak(island: Island, basis: Basis, landing_yaw: float,
		scale_r: float, placed: Array[Vector3], keepout_zones: Array[Vector3],
		rng: RandomNumberGenerator, prop_body: StaticBody3D, props_root: Node3D,
		foliage_cache: Dictionary, landmark_cache: Dictionary) -> int:
	var count := 0

	# HERO: CliffOverhangLedge anchored into the western cliff flank shadowing Golden Cove!
	var pref_dir := (basis * Vector3(0.45, 0.0, -0.89)).normalized()
	if _place_cliff_overhang(island, basis, "CliffOverhangLedge_Cove",
			-14.0 * scale_r, -4.0 * scale_r, 14.0, 14.0, 7.0, 28.0, pref_dir, 0.95, 4.8,
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

	# 1 CliffOverhangLedge on the western bluff + Wave I-3 Beached Rowboat on Tern Tide Bay!
	var pref_dir := (basis * Vector3(0.55, 0.0, -0.84)).normalized()
	if _place_cliff_overhang(island, basis, "CliffOverhangLedge_WestBluff",
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
	return count


static func _populate_fort_rock(island: Island, basis: Basis, landing_yaw: float,
		scale_r: float, placed: Array[Vector3], keepout_zones: Array[Vector3],
		rng: RandomNumberGenerator, prop_body: StaticBody3D, props_root: Node3D,
		foliage_cache: Dictionary, landmark_cache: Dictionary) -> int:
	var count := 0

	# 2 CliffOverhangLedges reinforcing the watch mesa's steep seaward flanks (clear of ramp & FortBastion).
	var overhang_specs: Array[Array] = [
		["CliffOverhangLedge_West", -28.0 * scale_r, -8.0 * scale_r, Vector3(-0.78, 0.0, -0.62), 1.02],
		["CliffOverhangLedge_East", 28.0 * scale_r, -8.0 * scale_r, Vector3(0.78, 0.0, -0.62), 1.02],
	]
	for spec: Array in overhang_specs:
		var pref_dir := (basis * (spec[3] as Vector3)).normalized()
		if _place_cliff_overhang(island, basis, String(spec[0]), float(spec[1]), float(spec[2]),
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
			# Check cross-slope stability so side foundation skirts stay solidly grounded.
			var h_l := island.surface_height(lp.x - side_dir.x * 3.6 * scale_f, lp.z - side_dir.z * 3.6 * scale_f)
			var h_r := island.surface_height(lp.x + side_dir.x * 3.6 * scale_f, lp.z + side_dir.z * 3.6 * scale_f)
			if absf(h_l - h_r) > 4.2 * scale_f:
				continue
			var rise := h_top - h_foot
			var dist_pen := sqrt(pow(u - u0, 2.0) + pow(v - v0, 2.0)) * 0.25
			var score := 12.0 - absf(rise - target_rise) * 2.2 - absf(h_l - h_r) * 0.6 - dist_pen
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
			if n.y < 0.68:
				continue
			var min_foot := _min_footprint_height(island, lp.x, lp.z, 2.3 * scale_f)
			if h - min_foot > 1.8 * scale_f:
				continue
			var dist_pen := sqrt(pow(u - u0, 2.0) + pow(v - v0, 2.0)) * 0.35
			var score := n.y * 6.0 - (h - min_foot) * 1.4 - dist_pen
			if score > best_score:
				best_score = score
				var mount_y := minf(h, min_foot + 0.72 * scale_f) - 0.28 * scale_f
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
		elif m_name.begins_with("Lantern_Magma"):
			light.light_color = COL_MAGMA_ARCH
			base_energy = 6.2
			light.omni_range = 21.0
			light.omni_attenuation = 1.25
			amp = 0.22
		elif m_name.begins_with("Lantern_Brazier"):
			light.light_color = COL_BRAZIER_FIRE
			base_energy = 5.2
			light.omni_range = 20.0
			light.omni_attenuation = 1.25
			amp = 0.20
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
